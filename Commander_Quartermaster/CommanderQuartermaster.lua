-- Commander Quartermaster — the supply ledger.
-- A browsable database of every TBC consumable (CommanderQuartermasterData)
-- married to an account-wide inventory ledger: each character files its bags
-- as it plays, bank and mail as they are opened, and the browser reads it
-- all back with live counts on every row.

local Data = CommanderQuartermasterData
local Events = COMMANDER_QUARTERMASTER_EVENTS

local frame = CreateFrame("FRAME")
local db                      -- CommanderQuartermasterDB, bound at login
local ledger                  -- CommanderQuartermasterLedger, bound at login
local realmKey, charKey       -- this character's ledger address
local me                      -- this character's record (always exists; only
                              -- LINKED into the ledger when tracking is on)
local loaded = false
local bankOpen = false
local mailOpen = false
local inboxSeen = false       -- true once MAIL_INBOX_UPDATE delivered real data

-- ---------------------------------------------------------------------------
-- Database index
-- ---------------------------------------------------------------------------

-- byID[itemID] = { entry = item entry, cat = category } for every item the
-- curated database knows (categories AND recommendation entries, so a
-- BoP-only recommended item still gets ledger treatment)
local byID = {}

local function BuildIndex()
    for _, cat in ipairs(Data.Categories) do
        for _, entry in ipairs(cat.items) do
            if not byID[entry.id] then
                byID[entry.id] = { entry = entry, cat = cat }
            end
        end
    end
    for _, rec in pairs(Data.Recommendations) do
        for _, spec in ipairs(rec.specs) do
            for _, pick in ipairs(spec.picks) do
                for _, e in ipairs(pick.entries) do
                    if not byID[e.id] then
                        byID[e.id] = { entry = e, cat = nil }
                    end
                end
            end
        end
    end
end

-- An item is ledger-worthy if either database knows it, or the client says it
-- is a Consumable (class 0) or Projectile (class 6). The enhancement database
-- has to be asked by name: a gem is item class 3 and a scope is trade goods,
-- so neither would ever pass the class test.
local trackedCache = {}
local function IsTracked(itemID)
    if not itemID then return false end
    if byID[itemID] then return true end
    if CommanderQuartermasterEnhance and CommanderQuartermasterEnhance.IsEnhancement(itemID) then
        return true
    end
    local cached = trackedCache[itemID]
    if cached ~= nil then return cached end
    local classID
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, cid = pcall(C_Item.GetItemInfoInstant, itemID)
        if ok then classID = cid end
    end
    local tracked = (classID == 0 or classID == 6) and true or false
    trackedCache[itemID] = tracked
    return tracked
end

-- ---------------------------------------------------------------------------
-- Ledger
-- ---------------------------------------------------------------------------

local function CharToken(realm, char)
    return realm .. "\001" .. char
end

local function LinkCharacter()
    -- File this character and mark visibility. Records are NEVER deleted
    -- here: the opt-out is a per-character `hidden` flag (kept in the
    -- account-wide UntrackedChars map, so unticking it on a bank alt can
    -- only ever affect that alt), and actual deletion belongs solely to
    -- the explicit Forget Character button. A settings toggle must always
    -- be reversible.
    ledger[realmKey] = ledger[realmKey] or {}
    ledger[realmKey][charKey] = me
    local untracked = db.UntrackedChars and db.UntrackedChars[CharToken(realmKey, charKey)]
    me.hidden = untracked and true or nil
end

local function ScanContainer(bagID, into)
    local slots = (C_Container.GetContainerNumSlots(bagID)) or 0
    for slot = 1, slots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        local itemID = info and info.itemID
        if itemID and IsTracked(itemID) then
            into[itemID] = (into[itemID] or 0) + (info.stackCount or 1)
        end
    end
end

local function ScanBags()
    if not (db and db.EnableQuartermaster) then return end
    wipe(me.bags)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        ScanContainer(bag, me.bags)
    end
    me.bagsAt = time()
    me.lastSeen = time()
    if GetMoney then
        me.money = GetMoney()
    end
end

local function ScanBank()
    if not (db and db.EnableQuartermaster and db.TrackBank and bankOpen) then return end
    wipe(me.bank)
    ScanContainer(BANK_CONTAINER or -1, me.bank)
    local first = (NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
        ScanContainer(bag, me.bank)
    end
    me.bankAt = time()
end

local function ScanMail()
    if not (db and db.EnableQuartermaster and db.TrackMail and mailOpen) then return end
    -- Inbox contents are server-side and arrive with the first
    -- MAIL_INBOX_UPDATE; scanning before that would wipe a real snapshot
    -- and record an empty mailbox
    if not inboxSeen then return end
    wipe(me.mail)
    local numItems = (GetInboxNumItems and GetInboxNumItems()) or 0
    for i = 1, numItems do
        for j = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local link = GetInboxItemLink and GetInboxItemLink(i, j)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if itemID and IsTracked(itemID) then
                -- Modern signature: name, itemID, texture, count. If the
                -- count isn't where we expect it, one is the safe floor.
                local _, r2, _, r4 = GetInboxItem(i, j)
                local count = (type(r2) == "number" and type(r4) == "number") and r4 or 1
                me.mail[itemID] = (me.mail[itemID] or 0) + count
            end
        end
    end
    me.mailAt = time()
    -- A fresh mailbox snapshot supersedes anything credited to this
    -- character "in transit": whatever arrived is in me.mail (or already
    -- looted into bags) now, so keeping the transit layer would double-count
    me.transit = nil
    me.transitAt = nil
end

-- Memoized per-item counts: CountsFor is called per row, per badge, and per
-- tooltip — the cache turns a 481-item sidebar pass into table lookups.
-- Invalidated whenever the ledger, live inventory, or scope settings move.
local countsCache = {}
local function InvalidateCounts()
    wipe(countsCache)
end

-- Coalesce scan bursts (looting fires BAG_UPDATE per stack moved)
local scanQueued = false
local dirtyBags, dirtyBank, dirtyMail = false, false, false
local RefreshBrowserSoon -- forward (browser section)

local function RunQueuedScans()
    scanQueued = false
    if dirtyBags then dirtyBags = false; ScanBags() end
    if dirtyBank then dirtyBank = false; ScanBank() end
    if dirtyMail then dirtyMail = false; ScanMail() end
    InvalidateCounts()
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
end

local function QueueScan(bags, bank, mail)
    dirtyBags = dirtyBags or bags
    dirtyBank = dirtyBank or bank
    dirtyMail = dirtyMail or mail
    if not scanQueued then
        scanQueued = true
        C_Timer.After(0.25, RunQueuedScans)
    end
end

-- ---------------------------------------------------------------------------
-- Outbound mail — the "in transit" ledger
-- ---------------------------------------------------------------------------
-- The classic ledger hole: flasks mailed to the raid main vanish from every
-- count until the recipient logs in and opens the mailbox. So sending mail
-- snapshots the tracked attachments (a fail-safe observation hook) and, once
-- the server confirms the send, credits them to the recipient's ledger
-- record as a `transit` layer. The recipient's own next mailbox scan
-- supersedes it; unclaimed-mail expiry (31 days) is the backstop.

local pendingSend = nil
local sendCommitsDirectly = false -- set when MAIL_SEND_SUCCESS can't register

local function CommitPendingSend()
    local send = pendingSend
    pendingSend = nil
    if not send then return end
    local chars = ledger[realmKey]
    if not chars then return end
    -- Recipients are matched case-insensitively against characters already
    -- in this realm's ledger ("bankalt" finds Bankalt); mail to anyone the
    -- ledger doesn't know is simply not tracked. Cross-realm suffixes are
    -- stripped before matching.
    local wanted = ((send.recipient or ""):match("^([^-]+)") or ""):lower()
    if wanted == "" then return end
    local target
    for charName, rec in pairs(chars) do
        if charName:lower() == wanted then
            target = rec
            break
        end
    end
    if not target or target == me then return end
    target.transit = target.transit or {}
    for itemID, count in pairs(send.items) do
        target.transit[itemID] = (target.transit[itemID] or 0) + count
    end
    target.transitAt = time()
    InvalidateCounts()
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
end

local function OnSendMail(recipient)
    pendingSend = nil
    if not (loaded and db.EnableQuartermaster and db.TrackTransit) then return end
    -- Snapshot immediately: the hook runs synchronously after the SendMail
    -- call while the send slots are still readable; the send itself resolves
    -- async via MAIL_SEND_SUCCESS / MAIL_FAILED
    local items
    for i = 1, (ATTACHMENTS_MAX_SEND or 12) do
        local itemLink = GetSendMailItemLink and GetSendMailItemLink(i)
        local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
        if itemID and IsTracked(itemID) then
            -- Same defensive count read as the inbox scan: name, itemID,
            -- texture, count in the modern signature; one is the safe floor
            local _, r2, _, r4 = GetSendMailItem(i)
            local count = (type(r2) == "number" and type(r4) == "number") and r4 or 1
            items = items or {}
            items[itemID] = (items[itemID] or 0) + count
        end
    end
    if not items then return end
    pendingSend = { recipient = recipient, items = items }
    if sendCommitsDirectly then
        CommitPendingSend()
    end
end

local function PruneTransit()
    local cutoff = time() - 31 * 86400
    for _, chars in pairs(ledger) do
        for _, rec in pairs(chars) do
            if rec.transit and (not rec.transitAt or rec.transitAt < cutoff) then
                rec.transit = nil
                rec.transitAt = nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Counts
-- ---------------------------------------------------------------------------

local function LiveCount(itemID, includeBank)
    local ok, count = pcall(C_Item.GetItemCount, itemID, includeBank)
    return (ok and count) or 0
end

-- bags, bank, mail, alts, total for one item. The current character reads
-- LIVE from the client (GetItemCount knows the bank even when closed); the
-- ledger speaks only for everyone else. Ledger-sourced layers are gated on
-- their Track* setting so a disabled tracker's frozen snapshot can never
-- double-count against live data; hidden (untracked) characters are
-- skipped. Results are memoized in countsCache until invalidated.
local function CountsFor(itemID)
    local cached = countsCache[itemID]
    if cached then
        return cached[1], cached[2], cached[3], cached[4], cached[5]
    end
    local bags = LiveCount(itemID, false)
    local bank = LiveCount(itemID, true) - bags
    if bank < 0 then bank = 0 end
    local mail = (db.TrackMail and me and me.mail[itemID]) or 0
    if db.TrackTransit and me and me.transit and me.transit[itemID] then
        -- Mailed to THIS character and not yet seen by a mailbox scan:
        -- reachable at any mailbox, so it counts alongside mail
        mail = mail + me.transit[itemID]
    end
    local alts = 0
    for realmName, chars in pairs(ledger) do
        if (not db.CurrentRealmOnly) or realmName == realmKey then
            for charName, rec in pairs(chars) do
                if not (realmName == realmKey and charName == charKey) and not rec.hidden then
                    alts = alts
                        + ((rec.bags and rec.bags[itemID]) or 0)
                        + ((db.TrackBank and rec.bank and rec.bank[itemID]) or 0)
                        + ((db.TrackMail and rec.mail and rec.mail[itemID]) or 0)
                        + ((db.TrackTransit and rec.transit and rec.transit[itemID]) or 0)
                end
            end
        end
    end
    local total = bags + bank + mail + alts
    countsCache[itemID] = { bags, bank, mail, alts, total }
    return bags, bank, mail, alts, total
end

local function ClassColorHex(classToken)
    local color = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
    return (color and color.colorStr) or "ffffffff"
end

-- Per-character holdings of one item, sorted biggest first. Allocates; call
-- on demand (tooltips), never per frame.
local function BreakdownFor(itemID)
    local rows = {}
    for realmName, chars in pairs(ledger) do
        if (not db.CurrentRealmOnly) or realmName == realmKey then
            for charName, rec in pairs(chars) do
                if not (realmName == realmKey and charName == charKey) and not rec.hidden then
                    local bags = (rec.bags and rec.bags[itemID]) or 0
                    local bank = (db.TrackBank and rec.bank and rec.bank[itemID]) or 0
                    local mail = (db.TrackMail and rec.mail and rec.mail[itemID]) or 0
                    local transit = (db.TrackTransit and rec.transit and rec.transit[itemID]) or 0
                    if bags + bank + mail + transit > 0 then
                        rows[#rows + 1] = {
                            name = charName, realm = realmName,
                            class = rec.class,
                            bags = bags, bank = bank, mail = mail, transit = transit,
                            total = bags + bank + mail + transit,
                        }
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    return rows
end

-- ---------------------------------------------------------------------------
-- Watchlist (per-character restock targets)
-- ---------------------------------------------------------------------------

-- Targets live in the settings DB keyed by character token — the
-- UntrackedChars shape — but OUTSIDE DefaultSettings, so Restore Defaults
-- keeps them (the Orders rally-point precedent). A target means "keep N in
-- bags + bank on this character"; deficits surface in the Watchlist view,
-- row stars, tooltips, the shopping list, and the raid supply check.
local function MyWatchlist(create)
    if not db then return nil end
    local map = db.Watchlist
    if not map then
        if not create then return nil end
        map = {}
        db.Watchlist = map
    end
    local token = CharToken(realmKey or "?", charKey or "?")
    local list = map[token]
    if not list and create then
        list = {}
        map[token] = list
    end
    return list
end

-- Public (macro-friendly): read/set this character's restock target
function CommanderQuartermaster_GetWatchTarget(itemID)
    local list = MyWatchlist()
    return list and list[itemID] or nil
end

function CommanderQuartermaster_SetWatchTarget(itemID, target)
    if not (loaded and itemID) then return end
    target = tonumber(target)
    if target and target > 0 then
        target = math.floor(target)
        MyWatchlist(true)[itemID] = target
        local hit = byID[itemID]
        print(("Commander Quartermaster: keeping %d × %s on this character"):format(
            target, (hit and hit.entry.name) or ("item:" .. tostring(itemID))))
    else
        local list = MyWatchlist()
        if list then list[itemID] = nil end
    end
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
end

-- ---------------------------------------------------------------------------
-- Tooltip integration
-- ---------------------------------------------------------------------------

local MyRole -- forward (browser section): the played spec's role

local function JoinParts(parts)
    local out
    for _, part in ipairs(parts) do
        out = out and (out .. " · " .. part) or part
    end
    return out or ""
end

-- What this enhancement is for, and the shortest way to get another. Runs on
-- the enhancement's own tooltip (a glyph, a gem, a sharpening stone) — the
-- ledger's count is appended separately, by AppendHoldings.
local function AppendEnhancement(tooltip, itemID)
    local E = CommanderQuartermasterEnhance
    if not (E and db.TooltipEnhance) then return end
    local entry = E.EntryForItem(itemID)
    if not entry then return end
    for _, line in ipairs(E.DetailLines(entry)) do
        tooltip:AddLine(("%s%s"):format(("   "):rep(line.depth), line.text), 1, 1, 1, true)
    end
end

-- The other half: a piece of GEAR whose slot takes an enhancement it has not
-- got. The link is the authority — an unenchanted item says enchant 0 — so
-- this is the same verdict /cqm gear gives, delivered where you are looking.
local function AppendGearVerdict(tooltip, link)
    local E = CommanderQuartermasterEnhance
    if not (E and db.TooltipEnhance) then return end
    local lines = E.GearLines(link, MyRole())
    if #lines == 0 then return end
    tooltip:AddLine(" ")
    for _, line in ipairs(lines) do
        tooltip:AddLine(("%s%s"):format(("   "):rep(line.depth), line.text), 1, 1, 1, true)
    end
end

local function AppendHoldings(tooltip)
    if not (loaded and db.EnableQuartermaster) then return end
    if not tooltip.GetItem then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not link then return end
    local itemID = tonumber(link:match("item:(%d+)"))
    if not itemID then return end
    -- OnTooltipSetItem can fire more than once for one tooltip fill
    if tooltip._cqmItem == itemID then return end
    tooltip._cqmItem = itemID

    AppendEnhancement(tooltip, itemID)
    AppendGearVerdict(tooltip, link)

    if not (db.TooltipCounts and IsTracked(itemID)) then
        tooltip:Show()
        return
    end

    local bags, bank, mail, alts, total = CountsFor(itemID)
    local target = CommanderQuartermaster_GetWatchTarget(itemID)
    -- A watched item speaks up even when the count is zero — that IS the
    -- restock signal
    if total == 0 and not target then
        tooltip:Show()
        return
    end
    if total > 0 then
        local parts = {}
        if bags > 0 then parts[#parts + 1] = ("bags %d"):format(bags) end
        if bank > 0 then parts[#parts + 1] = ("bank %d"):format(bank) end
        if mail > 0 then parts[#parts + 1] = ("mail %d"):format(mail) end
        if alts > 0 then parts[#parts + 1] = ("alts %d"):format(alts) end
        tooltip:AddLine(("|cff33ff99Quartermaster:|r %d  |cffaaaaaa(%s)|r"):format(total, JoinParts(parts)))
    end
    if target then
        local have = bags + bank
        local color = have < target and "ffff4040" or "ff40cc40"
        tooltip:AddLine(("|cff33ff99Restock:|r |c%s%d / %d|r"):format(color, have, target))
    end
    if db.TooltipBreakdown and alts > 0 then
        local rows = BreakdownFor(itemID)
        for i = 1, math.min(#rows, 8) do
            local row = rows[i]
            local where = {}
            if row.bags > 0 then where[#where + 1] = ("bags %d"):format(row.bags) end
            if row.bank > 0 then where[#where + 1] = ("bank %d"):format(row.bank) end
            if row.mail > 0 then where[#where + 1] = ("mail %d"):format(row.mail) end
            if row.transit and row.transit > 0 then where[#where + 1] = ("transit %d"):format(row.transit) end
            tooltip:AddLine(("  |c%s%s|r %d  |cff777777%s|r"):format(
                ClassColorHex(row.class), row.name, row.total, JoinParts(where)))
        end
        if #rows > 8 then
            tooltip:AddLine(("  |cff777777…and %d more|r"):format(#rows - 8))
        end
    end
    tooltip:Show()
end

local function ClearTooltipStamp(tooltip)
    tooltip._cqmItem = nil
end

local function HookTooltip(tooltip)
    if not (tooltip and tooltip.HookScript) then return end
    pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", ClearTooltipStamp)
end

local function InstallTooltipHooks()
    -- Retail-style path first; the classic HookScript pair as fallback.
    -- Both are guarded: the hook is a nicety, never worth an error.
    local usedProcessor = false
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tooltip)
            if tooltip == GameTooltip or tooltip == ItemRefTooltip then
                AppendHoldings(tooltip)
            end
        end)
        usedProcessor = ok
    end
    if not usedProcessor then
        if GameTooltip and GameTooltip.HookScript then
            pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", AppendHoldings)
        end
        if ItemRefTooltip and ItemRefTooltip.HookScript then
            pcall(ItemRefTooltip.HookScript, ItemRefTooltip, "OnTooltipSetItem", AppendHoldings)
        end
    end
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
end

-- ---------------------------------------------------------------------------
-- Browser window
-- ---------------------------------------------------------------------------

-- 850 (was 800): the Lvl column bought its width honestly instead of
-- eating the note band
local FRAME_W, FRAME_H = 850, 560
local SIDEBAR_W = 190
local ROW_H, VISIBLE_ROWS = 30, 15
local SIDEBAR_ROW_H = 22
local MAX_SIDEBAR_ROWS = 20

-- Count column left edges within a row (right-aligned, 40 wide each).
-- LEVEL sits left of the counts: it is a property, not a holding.
local COL_W = 40
local COL_TOTAL, COL_ALTS, COL_BANK, COL_BAGS = -44, -90, -136, -182
local COL_LEVEL = -228

local browser            -- the window frame, created lazily
local sidebarButtons = {}
local listRows = {}
local displayList = {}
local offset = 0
local searchText = ""
local searchTokens = {}  -- whitespace-split lowercased search terms (AND)
local sortKey = nil      -- BAGS | BANK | ALTS | TOTAL; nil = curated order
local sortAsc = false
local rosterRealm = nil  -- Roster view realm filter; nil = all realms
local updatingSlider = false
local refreshQueued = false

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local SOURCE_COLORS = {
    AH = "ffffd100", VENDOR = "ffffffff", CREATED = "ff69ccf0",
    QUEST = "ffdcc95a", DROP = "ffff8040", BOP = "ffff4040", SEASONAL = "ff40cc40",
}

local ROLE_TAGS = {
    TANK = "|cff6699ffTank|r", HEALER = "|cff40cc40Heal|r",
    MELEE = "|cffff6060Melee|r", CASTER = "|cffcc66ffCaster|r", RANGED = "|cffff9933Ranged|r",
}

local function PlayerClassToken()
    local _, token = UnitClass("player")
    return token
end

local function CurrentClass()
    local token = db.BrowserClass
    if not (token and Data.Recommendations[token]) then
        token = PlayerClassToken()
    end
    if not (token and Data.Recommendations[token]) then
        for _, t in ipairs(CLASS_ORDER) do
            if Data.Recommendations[t] then return t end
        end
    end
    return token
end

-- Talent-tab index → loadout spec key. Feral (tab 2) can't tell Bear from
-- Cat, so it defaults to Cat and tanks pick Bear by hand. Fringe specs that
-- share a tree with a mainstream spec (Shockadin/Holy, Smite/Holy, Demo
-- Tank/Demonology, Dreamstate/Balance) keep the mainstream default — pick
-- the fringe loadout by hand.
local SPEC_BY_TAB = {
    WARRIOR = { "ARMS", "FURY", "PROTECTION" },
    PALADIN = { "HOLY", "PROTECTION", "RETRIBUTION" },
    HUNTER = { "BEAST_MASTERY", "MARKSMANSHIP", "SURVIVAL" },
    ROGUE = { "ASSASSINATION", "COMBAT", "SUBTLETY" },
    PRIEST = { "DISCIPLINE", "HOLY", "SHADOW" },
    SHAMAN = { "ELEMENTAL", "ENHANCEMENT", "RESTORATION" },
    MAGE = { "ARCANE", "FIRE", "FROST" },
    WARLOCK = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
    DRUID = { "BALANCE", "FERAL_CAT", "RESTORATION" },
}

-- Deepest talent tab decides. Handles both GetTalentTabInfo shapes — the
-- classic tuple (name, texture, points, ...) and the retail-style one
-- (id, name, description, icon, points, ...); anything unexpected just
-- means no detection and the caller falls back.
local function DetectSpecKey(classToken)
    local tabs = classToken and SPEC_BY_TAB[classToken]
    if not (tabs and type(GetTalentTabInfo) == "function") then return nil end
    local numTabs = 3
    if type(GetNumTalentTabs) == "function" then
        local ok, n = pcall(GetNumTalentTabs)
        if ok and type(n) == "number" and n > 0 then numTabs = n end
    end
    local bestTab, bestPoints = nil, 0
    for i = 1, math.min(numTabs, #tabs) do
        local ok, a, _, c, _, e = pcall(GetTalentTabInfo, i)
        if ok then
            local points
            if type(a) == "number" then
                points = (type(e) == "number") and e or 0
            else
                points = (type(c) == "number") and c or 0
            end
            if points > bestPoints then
                bestPoints, bestTab = points, i
            end
        end
    end
    return bestTab and tabs[bestTab] or nil
end

-- Manual pick > talent detection (own class only) > first spec in the file
local function CurrentSpec()
    local classToken = CurrentClass()
    local rec = Data.Recommendations[classToken]
    if not rec then return nil end
    for _, spec in ipairs(rec.specs) do
        if spec.key == db.BrowserSpec then return spec end
    end
    if classToken == PlayerClassToken() then
        local detected = DetectSpecKey(classToken)
        if detected then
            for _, spec in ipairs(rec.specs) do
                if spec.key == detected then return spec end
            end
        end
    end
    return rec.specs[1]
end

-- The spec readiness verdicts are about: ALWAYS the played class — the
-- browser may be sightseeing another class's loadout, and that must never
-- change what "ready" means. A manual spec pick is honored only while it
-- belongs to the played class.
local function MyLoadoutSpec()
    local token = PlayerClassToken()
    local rec = token and Data.Recommendations[token]
    if not rec then return nil end
    if not db.BrowserClass or db.BrowserClass == token then
        for _, spec in ipairs(rec.specs) do
            if spec.key == db.BrowserSpec then return spec end
        end
    end
    local detected = DetectSpecKey(token)
    if detected then
        for _, spec in ipairs(rec.specs) do
            if spec.key == detected then return spec end
        end
    end
    return rec.specs[1]
end

local function CategoryByKey(key)
    for _, cat in ipairs(Data.Categories) do
        if cat.key == key then return cat end
    end
end

local function ItemName(id, fallback)
    local ok, name, _, quality = pcall(C_Item.GetItemInfo, id)
    if ok and name then
        local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
        if color and color.hex then
            return color.hex .. name .. "|r", true
        end
        return name, true
    end
    return fallback or ("item:" .. tostring(id)), false
end

local function ItemIcon(id)
    local ok, icon = pcall(C_Item.GetItemIconByID, id)
    return (ok and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Item level from the client cache, memoized once known. Uncached items
-- report 0 (rendered as a dash) and fill in as GET_ITEM_INFO_RECEIVED
-- lands — never cache the miss, or the arrival couldn't correct it.
local ilvlCache = {}
local function ItemLevelOf(id)
    local cached = ilvlCache[id]
    if cached then return cached end
    local ok, _, _, _, ilvl = pcall(C_Item.GetItemInfo, id)
    if ok and type(ilvl) == "number" and ilvl > 0 then
        ilvlCache[id] = ilvl
        return ilvl
    end
    return 0
end

-- A link for the chat box. The client's own link is best, but it only has one
-- once the item is cached — and an enhancement you have never held is exactly
-- the case where it is not. Build one from what the database knows rather than
-- let shift-click silently do nothing.
local function LinkForItem(itemID, name, quality)
    if not itemID then return nil end
    local ok, _, link = pcall(C_Item.GetItemInfo, itemID)
    if ok and link then return link end
    local hex = "|cffffffff"
    local colors = ITEM_QUALITY_COLORS
    if quality and colors and colors[quality] and colors[quality].hex then
        hex = colors[quality].hex
    end
    return ("%s|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h|r"):format(
        hex, itemID, name or ("Item " .. itemID))
end

local function FormatCount(n)
    if n and n > 0 then return tostring(n) end
    return "|cff444444–|r"
end

-- ------------------------------------------------------------------
-- Popups (watch target, forget character)
-- ------------------------------------------------------------------

-- StaticPopup's edit box handle drifted across framework eras; probe every
-- known spelling so the dialogs degrade to "typed nothing" instead of erroring
local function DialogEditBox(dialog)
    if not dialog then return nil end
    if dialog.editBox then return dialog.editBox end
    if dialog.EditBox then return dialog.EditBox end
    if dialog.GetEditBox then
        local ok, editBox = pcall(dialog.GetEditBox, dialog)
        if ok and editBox then return editBox end
    end
    local name = dialog.GetName and dialog:GetName()
    return name and _G[name .. "EditBox"] or nil
end

local function RegisterPopups()
    if not StaticPopupDialogs then return end
    StaticPopupDialogs["COMMANDER_QM_TARGET"] = {
        text = "Restock target for %s\nCounts bags + bank on this character; 0 clears.",
        button1 = "Set",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 5,
        OnShow = function(dialog, data)
            local editBox = DialogEditBox(dialog)
            if editBox and data then
                editBox:SetText(data.current and tostring(data.current) or "")
                if editBox.HighlightText then editBox:HighlightText() end
            end
        end,
        OnAccept = function(dialog, data)
            local editBox = DialogEditBox(dialog)
            local n = editBox and tonumber(editBox:GetText() or "")
            if data then
                CommanderQuartermaster_SetWatchTarget(data.id, n or 0)
            end
        end,
        EditBoxOnEnterPressed = function(editBox)
            local dialog = editBox:GetParent()
            local data = dialog and dialog.data
            if data then
                CommanderQuartermaster_SetWatchTarget(data.id, tonumber(editBox:GetText() or "") or 0)
            end
            if dialog then dialog:Hide() end
        end,
        EditBoxOnEscapePressed = function(editBox)
            local dialog = editBox:GetParent()
            if dialog then dialog:Hide() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
    StaticPopupDialogs["COMMANDER_QM_FORGET"] = {
        text = "Forget %s?\nRemoves this character's ledger records. Logging the character in refiles it.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, data)
            if data and CommanderQuartermaster_ForgetCharacter then
                CommanderQuartermaster_ForgetCharacter(data.realm, data.name)
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true,
    }
end

-- ------------------------------------------------------------------
-- Display list building
-- ------------------------------------------------------------------

local function PushItem(entry, cat, why)
    displayList[#displayList + 1] = { kind = "item", id = entry.id, entry = entry, cat = cat, why = why }
end

local function PushHeader(text)
    displayList[#displayList + 1] = { kind = "header", text = text }
end

local function SetSearchText(text)
    searchText = (text or ""):lower()
    wipe(searchTokens)
    for token in searchText:gmatch("%S+") do
        searchTokens[#searchTokens + 1] = token
    end
end

-- Everything a search token may land on, baked once per entry: name, effect
-- note, restriction, source key + display name, era, category name
local hayCache = {}
local function Haystack(entry, cat)
    local hay = hayCache[entry]
    if not hay then
        local parts = { (entry.name or ""):lower() }
        if entry.note then parts[#parts + 1] = entry.note:lower() end
        if entry.req then parts[#parts + 1] = entry.req:lower() end
        if entry.src then
            parts[#parts + 1] = entry.src:lower()
            local srcName = Data.SourceNames and Data.SourceNames[entry.src]
            if srcName then parts[#parts + 1] = srcName:lower() end
        end
        if entry.era then parts[#parts + 1] = entry.era:lower() end
        if cat and cat.name then parts[#parts + 1] = cat.name:lower() end
        hay = table.concat(parts, "\n")
        hayCache[entry] = hay
    end
    return hay
end

local function ItemMatches(entry, cat)
    if #searchTokens > 0 then
        local hay = Haystack(entry, cat)
        for _, token in ipairs(searchTokens) do
            if not hay:find(token, 1, true) then return false end
        end
    end
    if db.EraFilter and db.EraFilter ~= "ALL" and (entry.era or "TBC") ~= db.EraFilter then
        return false
    end
    if db.SourceFilter and db.SourceFilter ~= "ALL" and entry.src ~= db.SourceFilter then
        return false
    end
    if db.OwnedOnly then
        local _, _, _, _, total = CountsFor(entry.id)
        if total == 0 then return false end
    end
    return true
end

-- ------------------------------------------------------------------
-- Column sorting
-- ------------------------------------------------------------------

local function ItemSortValue(itemID, key)
    if key == "LEVEL" then return ItemLevelOf(itemID) end
    local bags, bank, _, alts, total = CountsFor(itemID)
    if key == "BAGS" then return bags end
    if key == "BANK" then return bank end
    if key == "ALTS" then return alts end
    return total
end

-- rows carry .entry; ties break on name so the order is stable
local function SortEntryRows(rows)
    local key, asc = sortKey, sortAsc
    table.sort(rows, function(a, b)
        local va, vb = ItemSortValue(a.entry.id, key), ItemSortValue(b.entry.id, key)
        if va ~= vb then
            if asc then return va < vb end
            return va > vb
        end
        return (a.entry.name or "") < (b.entry.name or "")
    end)
end

-- ------------------------------------------------------------------
-- Browse / Watchlist lists
-- ------------------------------------------------------------------

local function BuildWatchList()
    local list = MyWatchlist()
    local rows = {}
    if list then
        for id, target in pairs(list) do
            local hit = byID[id]
            local entry = (hit and hit.entry) or { id = id, name = "item:" .. tostring(id) }
            local bags, bank = CountsFor(id)
            local have = bags + bank
            rows[#rows + 1] = {
                entry = entry, cat = hit and hit.cat,
                target = target, have = have,
                short = math.max(target - have, 0),
            }
        end
    end
    if #rows == 0 then
        PushHeader("|cffaaaaaaRight-click any item row to set a restock target.|r")
        return
    end
    if sortKey then
        SortEntryRows(rows)
    else
        table.sort(rows, function(a, b)
            if (a.short > 0) ~= (b.short > 0) then return a.short > 0 end
            return (a.entry.name or "") < (b.entry.name or "")
        end)
    end
    PushHeader(("|cffffd200Watchlist|r  |cff999999— restock targets for %s|r"):format(charKey or "this character"))
    for _, row in ipairs(rows) do
        local why
        if row.short > 0 then
            why = ("|cffff4040Keep %d — have %d, short %d|r"):format(row.target, row.have, row.short)
        else
            why = ("|cff40cc40Keep %d — have %d|r"):format(row.target, row.have)
        end
        PushItem(row.entry, row.cat, why)
    end
end

local function CollectCategory(cat, out)
    for _, entry in ipairs(cat.items) do
        if ItemMatches(entry, cat) then
            out[#out + 1] = { entry = entry, cat = cat }
        end
    end
end

local function BuildBrowseList()
    local searching = #searchTokens > 0
    if not searching and db.BrowserCategory == "WATCHLIST" then
        BuildWatchList()
        return
    end
    local all = searching or db.BrowserCategory == "ALL"
    if sortKey then
        -- Sorting turns the list into a leaderboard: flat, no category headers
        local matches = {}
        if all then
            for _, cat in ipairs(Data.Categories) do
                CollectCategory(cat, matches)
            end
        else
            local cat = CategoryByKey(db.BrowserCategory) or Data.Categories[1]
            if cat then CollectCategory(cat, matches) end
        end
        SortEntryRows(matches)
        for _, match in ipairs(matches) do
            PushItem(match.entry, match.cat)
        end
        return
    end
    if all then
        for _, cat in ipairs(Data.Categories) do
            local wrote = false
            for _, entry in ipairs(cat.items) do
                if ItemMatches(entry, cat) then
                    if not wrote then
                        wrote = true
                        PushHeader(("|cffffd200%s|r"):format(cat.name))
                    end
                    PushItem(entry, cat)
                end
            end
        end
    else
        local cat = CategoryByKey(db.BrowserCategory) or Data.Categories[1]
        if cat then
            for _, entry in ipairs(cat.items) do
                if ItemMatches(entry, cat) then
                    PushItem(entry, cat)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------
-- Readiness engine
-- ------------------------------------------------------------------

local READY_TAGS = {
    CARRIED = "|cff40cc40[CARRIED]|r",
    BANKED = "|cffffd200[IN BANK]|r",
    ELSEWHERE = "|cff69ccf0[ON ALTS]|r",
    MISSING = "|cffff4040[MISSING]|r",
}

-- Grade one loadout slot from its ranked picks. Tier order: something in
-- bags beats reachable-on-this-character (bank or own mailbox) beats
-- somewhere-in-the-ledger (alts, incl. transit) beats nothing; within a
-- tier the pick ranking decides which item is named.
local function SlotReadiness(pick)
    local firstReachable, firstElsewhere
    for _, e in ipairs(pick.entries) do
        local bags, bank, mail, alts, total = CountsFor(e.id)
        if bags > 0 then
            return "CARRIED", e, bags
        end
        if not firstReachable and (bank + mail) > 0 then
            firstReachable = { e, bank + mail }
        end
        if not firstElsewhere and total > 0 then
            firstElsewhere = { e, total }
        end
    end
    if firstReachable then return "BANKED", firstReachable[1], firstReachable[2] end
    if firstElsewhere then return "ELSEWHERE", firstElsewhere[1], firstElsewhere[2] end
    return "MISSING", pick.entries[1], 0
end

local function ReadinessFor(spec)
    local out = { carried = 0, banked = 0, elsewhere = 0, missing = 0, slots = {} }
    if not spec then return out end
    for _, pick in ipairs(spec.picks) do
        if #pick.entries > 0 then
            local state, entry, count = SlotReadiness(pick)
            if state == "CARRIED" then out.carried = out.carried + 1
            elseif state == "BANKED" then out.banked = out.banked + 1
            elseif state == "ELSEWHERE" then out.elsewhere = out.elsewhere + 1
            else out.missing = out.missing + 1 end
            out.slots[#out.slots + 1] = {
                slot = pick.slot,
                name = (Data.SlotNames and Data.SlotNames[pick.slot]) or pick.slot,
                state = state, entry = entry, count = count,
            }
        end
    end
    return out
end

-- This character's watchlist deficits, name-sorted
local function WatchShorts()
    local shorts = {}
    local list = MyWatchlist()
    if list then
        for id, target in pairs(list) do
            local bags, bank = CountsFor(id)
            local have = bags + bank
            if have < target then
                local hit = byID[id]
                shorts[#shorts + 1] = {
                    id = id, have = have, target = target,
                    name = (hit and hit.entry.name) or ("item:" .. tostring(id)),
                }
            end
        end
        table.sort(shorts, function(a, b) return a.name < b.name end)
    end
    return shorts
end

local function BuildLoadoutList()
    local spec = CurrentSpec()
    if not spec then
        PushHeader("|cffaaaaaaNo recommendations for this class yet.|r")
        return
    end
    local ready = ReadinessFor(spec)
    local total = #ready.slots
    local summary = ("|cffffd200Readiness|r  |cff40cc40%d/%d carried|r"):format(ready.carried, total)
    if ready.banked > 0 then summary = summary .. ("  |cffffd200%d in bank|r"):format(ready.banked) end
    if ready.elsewhere > 0 then summary = summary .. ("  |cff69ccf0%d on alts|r"):format(ready.elsewhere) end
    if ready.missing > 0 then summary = summary .. ("  |cffff4040%d missing|r"):format(ready.missing) end
    PushHeader(summary)
    local stateBySlot = {}
    for _, s in ipairs(ready.slots) do stateBySlot[s.slot] = s.state end
    for _, pick in ipairs(spec.picks) do
        local slotName = Data.SlotNames[pick.slot] or pick.slot
        local tag = READY_TAGS[stateBySlot[pick.slot]] or ""
        if pick.note and pick.note ~= "" then
            PushHeader(("|cffffd200%s|r %s  |cff999999— %s|r"):format(slotName, tag, pick.note))
        else
            PushHeader(("|cffffd200%s|r %s"):format(slotName, tag))
        end
        for _, e in ipairs(pick.entries) do
            local dbEntry = byID[e.id] and byID[e.id].entry
            PushItem(dbEntry or e, byID[e.id] and byID[e.id].cat, e.why)
        end
    end
end

-- ------------------------------------------------------------------
-- Roster (characters) list
-- ------------------------------------------------------------------

local function Ago(t)
    if not t then return "never" end
    local d = time() - t
    if d < 90 then return "now" end
    if d < 5400 then return ("%dm"):format(math.floor(d / 60 + 0.5)) end
    if d < 129600 then return ("%dh"):format(math.floor(d / 3600 + 0.5)) end
    return ("%dd"):format(math.floor(d / 86400 + 0.5))
end

local function AgoText(t)
    if not t then return "never" end
    local short = Ago(t)
    if short == "now" then return "just now" end
    return short .. " ago"
end

local function MapSum(map)
    local total = 0
    if map then
        for _, v in pairs(map) do total = total + v end
    end
    return total
end

local function SortChars(chars)
    if sortKey == "LEVEL" then
        local asc = sortAsc
        table.sort(chars, function(a, b)
            local va, vb = a.rec.level or 0, b.rec.level or 0
            if va ~= vb then
                if asc then return va < vb end
                return va > vb
            end
            return a.name < b.name
        end)
    elseif sortKey then
        local field = sortKey == "BAGS" and "bags" or sortKey == "BANK" and "bank"
            or sortKey == "ALTS" and "mail" or "total"
        local asc = sortAsc
        table.sort(chars, function(a, b)
            local va, vb = a.sums[field], b.sums[field]
            if va ~= vb then
                if asc then return va < vb end
                return va > vb
            end
            return a.name < b.name
        end)
    else
        table.sort(chars, function(a, b)
            local la, lb = a.rec.lastSeen or 0, b.rec.lastSeen or 0
            if la ~= lb then return la > lb end
            return a.name < b.name
        end)
    end
end

local function BuildCharsList()
    local realms = {}
    for realmName in pairs(ledger) do realms[#realms + 1] = realmName end
    table.sort(realms)
    local pushed = 0
    for _, realmName in ipairs(realms) do
        if not rosterRealm or rosterRealm == realmName then
            local chars = {}
            for charName, rec in pairs(ledger[realmName]) do
                local sums = {
                    bags = MapSum(rec.bags),
                    bank = MapSum(rec.bank),
                    mail = MapSum(rec.mail) + MapSum(rec.transit),
                }
                sums.total = sums.bags + sums.bank + sums.mail
                chars[#chars + 1] = { kind = "char", realm = realmName, name = charName, rec = rec, sums = sums }
            end
            SortChars(chars)
            if #chars > 0 and not rosterRealm then
                PushHeader(("|cffffd200%s|r"):format(realmName))
            end
            for _, c in ipairs(chars) do
                displayList[#displayList + 1] = c
                pushed = pushed + 1
            end
        end
    end
    if pushed == 0 then
        PushHeader("|cffaaaaaaNo characters filed yet — play a little and check back.|r")
    end
end

-- ------------------------------------------------------------------
-- Gear view — the enhancement audit and the enhancement catalogue
-- ------------------------------------------------------------------

local Enhance = CommanderQuartermasterEnhance

local function GearSlotKey()
    return db.BrowserSlot or "MYGEAR"
end

-- An enhancement row matches the search the same way an item row does, over
-- everything a player might type: its name, what it grants, its slot, its
-- profession, and every source it has.
local function EnhanceHaystack(entry)
    local hay = entry._hay
    if hay then return hay end
    local parts = { entry.name or "", entry.short or "", entry.note or "",
                    entry.recipe or "", entry.kind or "", entry.era or "" }
    for _, slot in ipairs(entry.slots or {}) do
        parts[#parts + 1] = (Enhance and CommanderQuartermasterEnhanceData.SlotNames[slot]) or slot
    end
    if entry.prof then parts[#parts + 1] = entry.prof.skill end
    for _, src in ipairs(entry.src or {}) do
        parts[#parts + 1] = src.k or ""
        parts[#parts + 1] = src.name or ""
        parts[#parts + 1] = src.zone or ""
        if src.faction then parts[#parts + 1] = src.faction.name or "" end
        for _, learn in ipairs(src.learn or {}) do
            parts[#parts + 1] = learn.name or ""
            for _, deep in ipairs(learn.src or {}) do
                parts[#parts + 1] = (deep.name or "") .. " " .. (deep.zone or "")
            end
        end
    end
    hay = table.concat(parts, " "):lower()
    entry._hay = hay
    return hay
end

local function EnhanceMatches(entry)
    if db.EraFilter ~= "ALL" and entry.era ~= db.EraFilter then return false end
    if db.OwnedOnly then
        if not entry.item then return false end
        local _, _, _, _, total = CountsFor(entry.item)
        if total == 0 then return false end
    end
    if #searchTokens == 0 then return true end
    local hay = EnhanceHaystack(entry)
    for _, token in ipairs(searchTokens) do
        if not hay:find(token, 1, true) then return false end
    end
    return true
end

local function PushEnhance(entry, bestFor)
    displayList[#displayList + 1] = {
        kind = "enh", entry = entry, id = entry.item, bestFor = bestFor,
    }
end

-- The role the shelf is sorted for: the played spec's, never the class you
-- happen to be sightseeing in the Loadout view.
function MyRole()
    local spec = MyLoadoutSpec()
    return spec and spec.role or nil
end

local function BuildGearList()
    if not Enhance then
        PushHeader("|cffaaaaaaEnhancement database not loaded.|r")
        return
    end
    local EData = CommanderQuartermasterEnhanceData
    local slot = GearSlotKey()
    local role = MyRole()
    if slot == "MYGEAR" and #searchTokens == 0 then
        local report = Enhance.ScanGear("player")
        local head = ("|cffffd200Equipped|r  |cff888888%d enhanceable slot%s, %d bare, %d socket%s empty|r"):format(
            report.enchantable, report.enchantable == 1 and "" or "s",
            report.bare, report.empty, report.empty == 1 and "" or "s")
        if report.meta then
            head = head .. (report.meta.active
                and ("  |cff33ff99%s active|r"):format(report.meta.entry.name)
                or ("  |cffff4040%s INACTIVE|r |cff888888%s|r"):format(
                    report.meta.entry.name, report.meta.entry.condText or ""))
        end
        PushHeader(head)
        for _, row in ipairs(report.rows) do
            if row.link then
                displayList[#displayList + 1] = { kind = "gearslot", row = row, id = row.id }
            end
        end
        return
    end
    -- Searching from My Gear searches everything; otherwise one slot's shelf,
    -- ordered best-first for the role you actually play.
    local gemGroup = slot:match("^GEM:(.+)$")
    if gemGroup then slot = "GEM" end
    local slots = (slot == "MYGEAR") and EData.SlotOrder or { slot }
    local many = #slots > 1
    for _, key in ipairs(slots) do
        local label = EData.SlotNames[key] or key
        -- Permanent and temporary are not alternatives: a weapon carries an
        -- enchant AND a stone, so they get their own headers and their own
        -- ranking rather than competing in one list.
        local filter = EnhanceMatches
        if gemGroup then
            filter = function(entry)
                return Enhance.GemGroup(entry) == gemGroup and EnhanceMatches(entry)
            end
        end
        for _, half in ipairs({ "PERM", "TEMP" }) do
            local ranked = Enhance.RankSlot(key, role, filter, half)
            if ranked and #ranked > 0 then
                if many then
                    PushHeader(("|cffffd200%s|r%s"):format(label,
                        half == "TEMP" and " |cff888888— temporary|r" or ""))
                elseif half == "TEMP" then
                    PushHeader("|cffffd200Temporary|r |cff888888— reapplied, and stacks with the enchant above|r")
                end
                for i, row in ipairs(ranked) do
                    PushEnhance(row.entry, i == 1 and row.score and role or nil)
                end
            end
        end
    end
    if #displayList == 0 then
        PushHeader("|cffaaaaaaNothing matches.|r")
    end
end

local function BuildList()
    wipe(displayList)
    if db.BrowserView == "GEAR" then
        BuildGearList()
    elseif db.BrowserView == "LOADOUT" then
        BuildLoadoutList()
    elseif db.BrowserView == "CHARS" then
        BuildCharsList()
    else
        BuildBrowseList()
    end
end

-- ------------------------------------------------------------------
-- Row binding
-- ------------------------------------------------------------------

local function BindRow(row, item)
    if not item then
        row:Hide()
        return
    end
    row:Show()
    row.item = item
    if item.kind == "header" then
        row.headerFS:SetText(item.text)
        row.headerFS:Show()
        row.icon:Hide(); row.nameFS:Hide(); row.noteFS:Hide(); row.tagFS:Hide()
        row.c0:Hide(); row.c1:Hide(); row.c2:Hide(); row.c3:Hide(); row.c4:Hide()
        return
    end
    row.headerFS:Hide()
    row.icon:Show(); row.nameFS:Show(); row.noteFS:Show(); row.tagFS:Show()
    row.c0:Show(); row.c1:Show(); row.c2:Show(); row.c3:Show(); row.c4:Show()

    if item.kind == "char" then
        local rec = item.rec
        local coords = CLASS_ICON_TCOORDS and rec.class and CLASS_ICON_TCOORDS[rec.class]
        if coords then
            row.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        local marker = ""
        if item.realm == realmKey and item.name == charKey then
            marker = " |cff888888(you)|r"
        end
        if rec.hidden then
            marker = marker .. " |cffff4040(hidden)|r"
        end
        row.nameFS:SetText(("|c%s%s|r%s"):format(ClassColorHex(rec.class), item.name, marker))
        -- Character level lives in the Lvl column; the note keeps gold + seen
        row.noteFS:SetText(("%dg · seen %s"):format(
            math.floor((rec.money or 0) / 10000), AgoText(rec.lastSeen)))
        row.tagFS:SetText(("|cff777777bank %s|r"):format(Ago(rec.bankAt)))
        local sums = item.sums
        row.c0:SetText(rec.level and rec.level > 0
            and ("|cffaaaaaa%d|r"):format(rec.level) or FormatCount(0))
        row.c1:SetText(FormatCount(sums.bags))
        row.c2:SetText(FormatCount(sums.bank))
        row.c3:SetText(FormatCount(sums.mail))
        row.c4:SetText(sums.total > 0 and ("|cff33ff99%d|r"):format(sums.total) or FormatCount(0))
        return
    end

    if item.kind == "gearslot" then
        local grow = item.row
        row.icon:SetTexture(item.id and ItemIcon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.nameFS:SetText(("|cffffd200%s|r  %s"):format(grow.label, grow.link or ""))
        local ench = Enhance and Enhance.EnchantName(grow)
        local note
        if ench then
            note = "|cff33ff99" .. ench .. "|r"
        elseif grow.bare then
            note = "|cffff4040Not enchanted|r"
            local best = Enhance and Enhance.BestFor(grow.slot, MyRole())
            if best then
                note = note .. ("  |cff888888·|r best by stats: |cffffd200%s|r"):format(best.name)
            end
        elseif grow.needsProfession then
            note = ("|cff777777Enchantable only by an %s|r"):format(grow.needsProfession)
        else
            note = "|cff777777Takes no enchant|r"
        end
        local sockets = grow.sockets and #grow.sockets or 0
        if sockets > 0 then
            note = note .. ("  |cff888888·|r %s%d/%d gems|r"):format(
                (grow.empty or 0) > 0 and "|cffff4040" or "|cff33ff99",
                sockets - (grow.empty or 0), sockets)
            if (grow.empty or 0) == 0 and not grow.unknownGems then
                note = note .. (grow.bonus and " |cff33ff99bonus|r"
                    or (" |cffff4040bonus lost (%d match)|r"):format(grow.matched or 0))
            end
        end
        row.noteFS:SetText(note)
        row.tagFS:SetText(grow.slot and ("|cff777777%s|r"):format(grow.slot) or "")
        row.c0:SetText(FormatCount(0))
        row.c1:SetText(FormatCount(0)); row.c2:SetText(FormatCount(0))
        row.c3:SetText(FormatCount(0)); row.c4:SetText(FormatCount(0))
        return
    end

    if item.kind == "enh" then
        local entry = item.entry
        row.icon:SetTexture(entry.item and ItemIcon(entry.item)
            or "Interface\\Icons\\Trade_Engraving")
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local nameText = entry.item and ItemName(entry.item, entry.name) or entry.name
        if item.bestFor then
            nameText = ("|cffffd200*|r %s"):format(nameText)
        end
        if entry.reqSkill then
            nameText = nameText .. (" |cffff8040(%s only)|r"):format(entry.reqSkill.skill)
        end
        row.nameFS:SetText(nameText)
        local note = entry.short or entry.note or ""
        local summary = Enhance and Enhance.SourceSummary(entry) or ""
        row.noteFS:SetText(("%s  |cff888888·|r %s"):format(note, summary))
        local tag = entry.prof and entry.prof.skill
            or (entry.src and entry.src[1] and Enhance
                and (Enhance.KindLabel[entry.src[1].k] or entry.src[1].k))
            or ""
        if entry.era == "VANILLA" then tag = tag .. " |cff888888·V|r" end
        row.tagFS:SetText(("|cffaaaaaa%s|r"):format(tag))
        row.c0:SetText((entry.lvl or entry.ilvl) and ("|cffaaaaaa%d|r"):format(entry.lvl or entry.ilvl)
            or FormatCount(0))
        if entry.item then
            local bags, bank, _, alts, total = CountsFor(entry.item)
            row.c1:SetText(FormatCount(bags))
            row.c2:SetText(FormatCount(bank))
            row.c3:SetText(FormatCount(alts))
            row.c4:SetText(total > 0 and ("|cff33ff99%d|r"):format(total) or FormatCount(0))
        else
            -- an enchanter casts it; there is nothing to hold
            row.c1:SetText(FormatCount(0)); row.c2:SetText(FormatCount(0))
            row.c3:SetText(FormatCount(0)); row.c4:SetText(FormatCount(0))
        end
        return
    end

    local entry = item.entry
    row.icon:SetTexture(ItemIcon(item.id))
    -- Char rows retint the icon's texcoords; item rows must always restore
    -- the icon crop
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local nameText = ItemName(item.id, entry.name)
    local target = CommanderQuartermaster_GetWatchTarget(item.id)
    if target then
        local bags, bank = CountsFor(item.id)
        local star = (bags + bank < target) and "|cffff4040*|r " or "|cffffd200*|r "
        nameText = star .. nameText
    end
    row.nameFS:SetText(nameText)
    local note = item.why or entry.note or ""
    row.noteFS:SetText(note)
    local ilvl = ItemLevelOf(item.id)
    row.c0:SetText(ilvl > 0 and ("|cffaaaaaa%d|r"):format(ilvl) or FormatCount(0))
    local src = entry.src
    if src then
        local color = SOURCE_COLORS[src] or "ffffffff"
        local tag = (Data.SourceNames and Data.SourceNames[src]) or src
        if entry.era == "VANILLA" then
            tag = tag .. " |cff888888·V|r"
        end
        row.tagFS:SetText(("|c%s%s|r"):format(color, tag))
    else
        row.tagFS:SetText("")
    end
    local bags, bank, _, alts, total = CountsFor(item.id)
    row.c1:SetText(FormatCount(bags))
    row.c2:SetText(FormatCount(bank))
    row.c3:SetText(FormatCount(alts))
    row.c4:SetText(total > 0 and ("|cff33ff99%d|r"):format(total) or FormatCount(0))
end

local function MaxOffset()
    return math.max(0, #displayList - VISIBLE_ROWS)
end

local function RefreshList()
    if not browser then return end
    if offset > MaxOffset() then offset = MaxOffset() end
    if offset < 0 then offset = 0 end
    for i = 1, VISIBLE_ROWS do
        BindRow(listRows[i], displayList[offset + i])
    end
    updatingSlider = true
    browser.scrollbar:SetMinMaxValues(0, MaxOffset())
    browser.scrollbar:SetValue(offset)
    updatingSlider = false
    browser.scrollbar:SetShown(MaxOffset() > 0)
end

-- ------------------------------------------------------------------
-- Sidebar binding
-- ------------------------------------------------------------------

local function BindSidebarButton(btn, opts)
    btn:Show()
    btn.key = opts.key
    btn.labelFS:SetText(opts.text)
    btn.badgeFS:SetText(opts.badge or "")
    btn.selectedTex:SetShown(opts.selected or false)
    btn.onClick = opts.onClick
end

local function RefreshSidebar()
    if not browser then return end
    local used = 0
    if db.BrowserView == "LOADOUT" then
        local rec = Data.Recommendations[CurrentClass()]
        local current = CurrentSpec()
        if rec then
            for _, spec in ipairs(rec.specs) do
                used = used + 1
                if used > MAX_SIDEBAR_ROWS then break end
                BindSidebarButton(sidebarButtons[used], {
                    key = spec.key,
                    text = spec.name,
                    badge = ROLE_TAGS[spec.role] or "",
                    selected = current and current.key == spec.key,
                    onClick = function()
                        db.BrowserSpec = spec.key
                        offset = 0
                        BuildList()
                        RefreshSidebar()
                        RefreshList()
                    end,
                })
            end
        end
    elseif db.BrowserView == "GEAR" then
        local EData = CommanderQuartermasterEnhanceData
        local function slotButton(key, text, badge)
            used = used + 1
            if used > MAX_SIDEBAR_ROWS then return end
            BindSidebarButton(sidebarButtons[used], {
                key = key,
                text = text,
                badge = badge,
                selected = GearSlotKey() == key,
                onClick = function()
                    db.BrowserSlot = key
                    offset = 0
                    BuildList()
                    RefreshSidebar()
                    RefreshList()
                end,
            })
        end
        local badge = ""
        if Enhance then
            local report = Enhance.ScanGear("player")
            local trouble = report.bare + report.empty
            badge = trouble > 0 and ("|cffff4040%d|r"):format(trouble) or "|cff33ff99ok|r"
        end
        slotButton("MYGEAR", "|cffffd200My Gear|r", badge)
        if EData then
            local function tally(list, group)
                local owned, total = 0, 0
                for _, entry in ipairs(list) do
                    if not entry.unobtainable
                        and (not group or Enhance.GemGroup(entry) == group) then
                        total = total + 1
                        if entry.item then
                            local _, _, _, _, held = CountsFor(entry.item)
                            if held > 0 then owned = owned + 1 end
                        end
                    end
                end
                return owned, total
            end
            local function countBadge(owned, total)
                return owned > 0 and ("|cff33ff99%d|r|cff666666/%d|r"):format(owned, total)
                    or ("|cff666666%d|r"):format(total)
            end
            for _, key in ipairs(EData.SlotOrder) do
                local list = Enhance and Enhance.EntriesForSlot(key)
                if list and #list > 0 then
                    if key == "GEM" then
                        -- 242 gems in one list is a wall. Colour is how a
                        -- player shops for them, so colour is how they list.
                        for _, group in ipairs(Enhance.GemGroups) do
                            local owned, total = tally(list, group.key)
                            if total > 0 then
                                slotButton("GEM:" .. group.key, "Gem — " .. group.name,
                                    countBadge(owned, total))
                            end
                        end
                    else
                        slotButton(key, EData.SlotNames[key] or key, countBadge(tally(list)))
                    end
                end
            end
        end
    elseif db.BrowserView == "CHARS" then
        local function realmButton(realmName, text, badge)
            used = used + 1
            if used > MAX_SIDEBAR_ROWS then return end
            BindSidebarButton(sidebarButtons[used], {
                key = realmName or "ALLREALMS",
                text = text,
                badge = badge,
                selected = rosterRealm == realmName,
                onClick = function()
                    rosterRealm = realmName
                    offset = 0
                    BuildList()
                    RefreshSidebar()
                    RefreshList()
                end,
            })
        end
        local realms = {}
        for realmName in pairs(ledger) do realms[#realms + 1] = realmName end
        table.sort(realms)
        realmButton(nil, "All Realms")
        for _, realmName in ipairs(realms) do
            local count = 0
            for _ in pairs(ledger[realmName]) do count = count + 1 end
            realmButton(realmName, realmName, ("|cff666666%d|r"):format(count))
        end
    else
        local function categoryButton(key, text, badge)
            used = used + 1
            if used > MAX_SIDEBAR_ROWS then return end
            BindSidebarButton(sidebarButtons[used], {
                key = key,
                text = text,
                badge = badge,
                selected = searchText == "" and db.BrowserCategory == key,
                onClick = function()
                    db.BrowserCategory = key
                    if browser.searchBox then
                        browser.searchBox:SetText("")
                    end
                    SetSearchText("")
                    offset = 0
                    BuildList()
                    RefreshSidebar()
                    RefreshList()
                end,
            })
        end
        local list = MyWatchlist()
        local watched, short = 0, 0
        if list then
            for id, target in pairs(list) do
                watched = watched + 1
                local bags, bank = CountsFor(id)
                if bags + bank < target then short = short + 1 end
            end
        end
        local watchBadge = ""
        if short > 0 then
            watchBadge = ("|cffff4040%d short|r"):format(short)
        elseif watched > 0 then
            watchBadge = ("|cff33ff99%d|r"):format(watched)
        end
        categoryButton("WATCHLIST", "|cffffd200* Watchlist|r", watchBadge)
        categoryButton("ALL", "All Items")
        for _, cat in ipairs(Data.Categories) do
            local owned = 0
            for _, entry in ipairs(cat.items) do
                local _, _, _, _, total = CountsFor(entry.id)
                if total > 0 then owned = owned + 1 end
            end
            categoryButton(cat.key, cat.name,
                owned > 0 and ("|cff33ff99%d|r|cff666666/%d|r"):format(owned, #cat.items)
                or ("|cff666666%d|r"):format(#cat.items))
        end
    end
    for i = used + 1, #sidebarButtons do
        sidebarButtons[i]:Hide()
    end
end

-- Column heads double as sort buttons; the third column reads Alts for item
-- lists and Mail in the Roster view
local function UpdateColumnHeads()
    if not (browser and browser.colBtns) then return end
    local chars = db.BrowserView == "CHARS"
    for _, col in ipairs(browser.colBtns) do
        local label = col.base
        if chars and col.key == "ALTS" then label = "Mail" end
        if sortKey == col.key then
            label = label .. (sortAsc and " ^" or " v")
        end
        col.fs:SetText(label)
    end
end

local function FullRefresh()
    if not browser then return end
    BuildList()
    RefreshSidebar()
    RefreshList()
    local view = db.BrowserView
    browser.viewBrowse:SetEnabled(view ~= "BROWSE")
    browser.viewLoadout:SetEnabled(view ~= "LOADOUT")
    if browser.viewChars then browser.viewChars:SetEnabled(view ~= "CHARS") end
    if browser.viewGear then browser.viewGear:SetEnabled(view ~= "GEAR") end
    -- Gear searches too: the catalogue is the point of searching it
    local browse = view ~= "LOADOUT" and view ~= "CHARS"
    if browser.searchBox then browser.searchBox:SetShown(browse) end
    if browser.filterBtn then
        browser.filterBtn:SetShown(browse)
        local active = (db.EraFilter and db.EraFilter ~= "ALL")
            or (db.SourceFilter and db.SourceFilter ~= "ALL")
        browser.filterBtn:SetText(active and "|cffffd200Filter *|r" or "Filter")
    end
    if browser.ownedCheck then
        browser.ownedCheck:SetShown(browse)
        -- The settings panel mirrors this flag; resync so a change made
        -- there (or Restore Defaults) reaches an already-open browser
        browser.ownedCheck:SetChecked(db.OwnedOnly and true or false)
    end
    if browser.classDrop then browser.classDrop:SetShown(view == "LOADOUT") end
    if browser.classDrop and view == "LOADOUT" then
        local token = CurrentClass()
        local label = (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(browser.classDrop, ("|c%s%s|r"):format(ClassColorHex(token), label))
        end
    end
    UpdateColumnHeads()
end

-- Coalesced refresh for scan/iteminfo bursts while the browser is open.
-- Item-info arrivals only need the visible rows re-bound (names/quality);
-- ledger changes need the full pass with sidebar badges.
local refreshFull = false
local function RunQueuedRefresh()
    refreshQueued = false
    local full = refreshFull
    refreshFull = false
    if browser and browser:IsShown() then
        if full then
            FullRefresh()
        else
            RefreshList()
        end
    end
end

RefreshBrowserSoon = function(light)
    if not (browser and browser:IsShown()) then return end
    if not light then refreshFull = true end
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, RunQueuedRefresh)
end

-- ------------------------------------------------------------------
-- Window construction
-- ------------------------------------------------------------------

local function ApplyFraming()
    if not browser then return end
    local style = db.BrowserStyle or "WINDOW"
    local windowArt = style == "WINDOW"
    if browser.NineSlice then browser.NineSlice:SetShown(windowArt) end
    if browser.Bg then browser.Bg:SetShown(windowArt) end
    if browser.TitleBg then browser.TitleBg:SetShown(windowArt) end
    if browser.TitleText then browser.TitleText:SetShown(windowArt) end
    if browser.CloseButton then browser.CloseButton:SetShown(windowArt) end
    if browser.Inset then browser.Inset:SetShown(windowArt) end
    Commander.UI.ApplyStyleBackdrop(browser, windowArt and "NONE" or style)
end

local function ApplyPosition()
    if not browser then return end
    local scale = db.BrowserScale or 1
    browser:SetScale(scale)
    -- Never re-anchor mid-drag: a throttled settings notify would snap the
    -- window out of the user's hand (same guard as the suite's HUD chrome)
    if browser._dragging then return end
    browser:ClearAllPoints()
    local pos = db.BrowserPos
    if pos and pos.point then
        -- Saved in screen space; divide the scale back out (suite convention)
        browser:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        browser:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

-- Shared suite icon shading, drawn by Commander_Events (a RequiredDep, so it
-- is always loaded). The registry is what lets a setting changed mid-session
-- reach rows that were built long before it.
local styledIcons = {}

local function ApplyIconRecess(icon)
    if not Commander.DebossIcon then return end
    Commander.DebossIcon(icon, (db and db.IconRecess) or "SOFT")
end

local function RestyleIcons()
    for icon in pairs(styledIcons) do ApplyIconRecess(icon) end
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
    row:SetPoint("RIGHT", parent, "RIGHT", -14, 0)

    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.stripe:SetVertexColor(1, 1, 1, index % 2 == 0 and 0.03 or 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- The suite's shared icon recess (Commander_Events' art). Rows are pooled
    -- and built once, so ApplySettings carries a changed style back to them.
    styledIcons[row.icon] = true
    ApplyIconRecess(row.icon)

    row.nameFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.nameFS:SetPoint("LEFT", row, "LEFT", 30, 0)
    row.nameFS:SetWidth(170)
    row.nameFS:SetJustifyH("LEFT")
    row.nameFS:SetWordWrap(false)

    -- The tag owns a fixed band and the note clips against it, so a long
    -- effect note can never render under the source tag
    row.tagFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.tagFS:SetPoint("RIGHT", row, "RIGHT", COL_LEVEL - COL_W - 14, 0)
    row.tagFS:SetWidth(70)
    row.tagFS:SetJustifyH("RIGHT")
    row.tagFS:SetWordWrap(false)

    row.noteFS = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.noteFS:SetPoint("LEFT", row, "LEFT", 204, 0)
    row.noteFS:SetPoint("RIGHT", row.tagFS, "LEFT", -6, 0)
    row.noteFS:SetJustifyH("LEFT")
    row.noteFS:SetWordWrap(false)
    row.noteFS:SetTextColor(0.66, 0.66, 0.66)

    local function CountColumn(x)
        local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("RIGHT", row, "RIGHT", x, 0)
        fs:SetWidth(COL_W)
        fs:SetJustifyH("RIGHT")
        return fs
    end
    row.c0 = CountColumn(COL_LEVEL)
    row.c1 = CountColumn(COL_BAGS)
    row.c2 = CountColumn(COL_BANK)
    row.c3 = CountColumn(COL_ALTS)
    row.c4 = CountColumn(COL_TOTAL)

    row.headerFS = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.headerFS:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.headerFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.headerFS:SetJustifyH("LEFT")
    row.headerFS:SetWordWrap(false)

    -- Rows are the full width of an 850px window, so anchoring to the row put
    -- the tooltip a long way from the pointer that summoned it. ANCHOR_CURSOR
    -- pins it to the cursor instead; the client handles flipping it when a
    -- tall one would run off the bottom of the screen.
    -- ANCHOR_CURSOR_RIGHT takes an offset and so keeps the tooltip clear of
    -- the pointer itself; it is a newer anchor than ANCHOR_CURSOR, and an
    -- anchor name SetOwner does not know is a hard error rather than a
    -- fallback. Try it, and keep the one every client has in reserve.
    local function TipAtCursor(owner)
        if not pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_CURSOR_RIGHT", 12, -6) then
            GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
        end
    end

    row:SetScript("OnEnter", function(self)
        local item = self.item
        if not item then return end
        if item.kind == "char" then
            local rec = item.rec
            TipAtCursor(self)
            GameTooltip:SetText(("%s — %s"):format(item.name, item.realm), 1, 1, 1)
            GameTooltip:AddLine(("Last seen %s"):format(AgoText(rec.lastSeen)), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(("Bags scanned %s"):format(AgoText(rec.bagsAt)), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(("Bank scanned %s"):format(AgoText(rec.bankAt)), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(("Mail scanned %s"):format(AgoText(rec.mailAt)), 0.8, 0.8, 0.8)
            if rec.transitAt then
                GameTooltip:AddLine(("Mail in transit since %s"):format(AgoText(rec.transitAt)), 0.41, 0.8, 0.94)
            end
            if rec.hidden then
                GameTooltip:AddLine("Hidden from counts", 1, 0.25, 0.25)
            end
            GameTooltip:AddLine("Click: hide/show in counts · Right-click: forget", 0.5, 0.5, 0.5)
            GameTooltip:Show()
            return
        end
        -- A row in the Gear view is either a slot you are wearing or an
        -- enhancement that could go in one. Both want the real item tooltip
        -- where there is one, so the enhancement lines the addon appends land
        -- on it the same way they do in the bags.
        if item.kind == "gearslot" then
            TipAtCursor(self)
            local shown = item.row.invSlot and
                pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", item.row.invSlot)
            if not shown and item.row.link then
                shown = pcall(GameTooltip.SetHyperlink, GameTooltip, item.row.link)
            end
            if not shown then
                GameTooltip:SetText(item.row.label or "?")
            end
            GameTooltip:Show()
            return
        end
        if item.kind == "enh" then
            local entry = item.entry
            TipAtCursor(self)
            local shown = entry.item and
                pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(entry.item))
            if not shown then
                -- An enchanter casts it: there is no item, so there is no
                -- item tooltip to borrow. Build the whole thing by hand.
                GameTooltip:SetText(entry.name or "?", 1, 1, 1)
                local E = CommanderQuartermasterEnhance
                for _, line in ipairs(E and E.DetailLines(entry) or {}) do
                    GameTooltip:AddLine(("%s%s"):format(("   "):rep(line.depth), line.text),
                        1, 1, 1, true)
                end
            end
            GameTooltip:Show()
            return
        end
        if item.kind ~= "item" then return end
        TipAtCursor(self)
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(item.id))
        if not ok then
            GameTooltip:SetText(item.entry.name or "?")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        local item = self.item
        if not item then return end
        if item.kind == "char" then
            if button == "RightButton" then
                if item.realm == realmKey and item.name == charKey then
                    print("Commander Quartermaster: you can't forget the character you're playing — hide it instead (left-click)")
                elseif StaticPopup_Show then
                    StaticPopup_Show("COMMANDER_QM_FORGET",
                        ("%s — %s"):format(item.name, item.realm), nil,
                        { realm = item.realm, name = item.name })
                end
            elseif CommanderQuartermaster_SetCharacterHidden then
                CommanderQuartermaster_SetCharacterHidden(item.realm, item.name, not item.rec.hidden)
            end
            return
        end
        -- Gear-view rows behave like item rows: shift-click links, right-click
        -- sets a restock target. A gear row links the EQUIPPED item, enchant
        -- and gems and all, because that link is already in hand and is what
        -- someone linking their gear means to show.
        if item.kind ~= "item" then
            local clickID, clickLink
            if item.kind == "gearslot" then
                clickID, clickLink = item.row and item.row.id, item.row and item.row.link
            elseif item.kind == "enh" then
                clickID = item.entry and item.entry.item
            end
            if button == "RightButton" then
                if item.kind == "enh" and clickID and StaticPopup_Show then
                    StaticPopup_Show("COMMANDER_QM_TARGET",
                        ItemName(clickID, item.entry and item.entry.name), nil,
                        { id = clickID, current = CommanderQuartermaster_GetWatchTarget(clickID) })
                end
                return
            end
            if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                clickLink = clickLink or LinkForItem(clickID,
                    item.entry and item.entry.name, item.entry and item.entry.quality)
                if clickLink then ChatEdit_InsertLink(clickLink) end
            end
            return
        end
        if button == "RightButton" then
            if StaticPopup_Show then
                local target = CommanderQuartermaster_GetWatchTarget(item.id)
                StaticPopup_Show("COMMANDER_QM_TARGET",
                    (ItemName(item.id, item.entry and item.entry.name)), nil,
                    { id = item.id, current = target })
            end
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
            local link = LinkForItem(item.id, item.entry and item.entry.name)
            if link then ChatEdit_InsertLink(link) end
        end
    end)
    return row
end

local function CreateSidebarButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(SIDEBAR_ROW_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * SIDEBAR_ROW_H))
    btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    btn.selectedTex = btn:CreateTexture(nil, "BACKGROUND")
    btn.selectedTex:SetAllPoints()
    btn.selectedTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.selectedTex:SetVertexColor(1, 0.82, 0, 0.13)
    btn.selectedTex:Hide()

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.06)

    btn.labelFS = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.labelFS:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.labelFS:SetJustifyH("LEFT")

    btn.badgeFS = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.badgeFS:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.badgeFS:SetJustifyH("RIGHT")

    btn:SetScript("OnClick", function(self)
        if self.onClick then self.onClick() end
    end)
    return btn
end

local function EnsureBrowser()
    if browser then return browser end

    browser = CreateFrame("Frame", "CommanderQuartermasterFrame", UIParent, "BasicFrameTemplateWithInset")
    browser:SetSize(FRAME_W, FRAME_H)
    browser:SetFrameStrata("MEDIUM")
    browser:SetToplevel(true)
    browser:SetMovable(true)
    browser:SetClampedToScreen(true)
    browser:Hide()
    if browser.TitleText then
        browser.TitleText:SetText("Quartermaster")
    end
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderQuartermasterFrame")
    end

    -- Drag strip across the title bar (the window's own regions don't drag)
    local drag = CreateFrame("Frame", nil, browser)
    drag:SetPoint("TOPLEFT", browser, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        browser._dragging = true
        browser:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        browser:StopMovingOrSizing()
        browser._dragging = false
        local point, _, _, x, y = browser:GetPoint(1)
        if point then
            local scale = browser:GetScale() or 1
            db.BrowserPos = { point = point, x = x * scale, y = y * scale }
        end
    end)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, browser)
    toolbar:SetPoint("TOPLEFT", browser, "TOPLEFT", 10, -28)
    toolbar:SetPoint("TOPRIGHT", browser, "TOPRIGHT", -10, -28)
    toolbar:SetHeight(30)

    browser.viewBrowse = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.viewBrowse:SetSize(74, 22)
    browser.viewBrowse:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    -- "Browse" stopped meaning anything the moment there were two things to
    -- browse. This page is the consumables database; the Gear page is the
    -- other one.
    browser.viewBrowse:SetText("Consumables")
    browser.viewBrowse:SetScript("OnClick", function()
        db.BrowserView = "BROWSE"
        offset = 0
        FullRefresh()
    end)

    browser.viewLoadout = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.viewLoadout:SetSize(74, 22)
    browser.viewLoadout:SetPoint("LEFT", browser.viewBrowse, "RIGHT", 4, 0)
    browser.viewLoadout:SetText("Loadout")
    browser.viewLoadout:SetScript("OnClick", function()
        db.BrowserView = "LOADOUT"
        offset = 0
        FullRefresh()
    end)

    browser.viewChars = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.viewChars:SetSize(74, 22)
    browser.viewChars:SetPoint("LEFT", browser.viewLoadout, "RIGHT", 4, 0)
    browser.viewChars:SetText("Roster")
    browser.viewChars:SetScript("OnClick", function()
        db.BrowserView = "CHARS"
        offset = 0
        FullRefresh()
    end)

    browser.viewGear = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.viewGear:SetSize(74, 22)
    browser.viewGear:SetPoint("LEFT", browser.viewChars, "RIGHT", 4, 0)
    browser.viewGear:SetText("Gear")
    browser.viewGear:SetScript("OnClick", function()
        db.BrowserView = "GEAR"
        offset = 0
        FullRefresh()
    end)

    browser.searchBox = CreateFrame("EditBox", "CommanderQuartermasterSearch", toolbar, "InputBoxTemplate")
    browser.searchBox:SetSize(150, 20)
    browser.searchBox:SetPoint("LEFT", browser.viewGear, "RIGHT", 16, 0)
    browser.searchBox:SetAutoFocus(false)
    browser.searchBox:SetMaxLetters(40)
    browser.searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        SetSearchText(self:GetText())
        offset = 0
        BuildList()
        RefreshSidebar()
        RefreshList()
    end)
    browser.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        SetSearchText("")
        self:ClearFocus()
        offset = 0
        BuildList()
        RefreshSidebar()
        RefreshList()
    end)
    browser.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Placeholder lives ON the edit box so hiding the box (Loadout view)
    -- hides the ghost text with it
    local searchLabel = browser.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchLabel:SetPoint("LEFT", browser.searchBox, "LEFT", 2, 0)
    searchLabel:SetText("Search…")
    browser.searchBox:HookScript("OnTextChanged", function(self)
        searchLabel:SetShown((self:GetText() or "") == "")
    end)

    -- Era/source filter menu (Browse only); the button label flags an
    -- active filter so a mysteriously short list is never a mystery
    browser.filterBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.filterBtn:SetSize(70, 22)
    browser.filterBtn:SetPoint("LEFT", browser.searchBox, "RIGHT", 10, 0)
    browser.filterBtn:SetText("Filter")
    if UIDropDownMenu_Initialize and ToggleDropDownMenu then
        local ERA_FILTERS = {
            { "ALL", "All Eras" }, { "TBC", "TBC" }, { "VANILLA", "Vanilla" },
        }
        local SOURCE_ORDER = { "AH", "VENDOR", "CREATED", "QUEST", "DROP", "BOP", "SEASONAL" }
        local function SetFilters(era, src)
            if era then db.EraFilter = era end
            if src then db.SourceFilter = src end
            offset = 0
            FullRefresh()
        end
        local menu = CreateFrame("Frame", "CommanderQuartermasterFilterMenu", toolbar, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(menu, function()
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Era"; info.isTitle = true; info.notCheckable = true
            UIDropDownMenu_AddButton(info)
            for _, era in ipairs(ERA_FILTERS) do
                info = UIDropDownMenu_CreateInfo()
                info.text = era[2]
                info.checked = (db.EraFilter or "ALL") == era[1]
                info.func = function() SetFilters(era[1], nil) end
                UIDropDownMenu_AddButton(info)
            end
            info = UIDropDownMenu_CreateInfo()
            info.text = "Source"; info.isTitle = true; info.notCheckable = true
            UIDropDownMenu_AddButton(info)
            info = UIDropDownMenu_CreateInfo()
            info.text = "All Sources"
            info.checked = (db.SourceFilter or "ALL") == "ALL"
            info.func = function() SetFilters(nil, "ALL") end
            UIDropDownMenu_AddButton(info)
            for _, src in ipairs(SOURCE_ORDER) do
                info = UIDropDownMenu_CreateInfo()
                info.text = (Data.SourceNames and Data.SourceNames[src]) or src
                info.checked = db.SourceFilter == src
                info.func = function() SetFilters(nil, src) end
                UIDropDownMenu_AddButton(info)
            end
            info = UIDropDownMenu_CreateInfo()
            info.text = "Clear Filters"; info.notCheckable = true
            info.func = function() SetFilters("ALL", "ALL") end
            UIDropDownMenu_AddButton(info)
        end, "MENU")
        browser.filterBtn:SetScript("OnClick", function(self)
            ToggleDropDownMenu(1, nil, menu, self, 0, 0)
        end)
    end

    -- Shopping list (every view — it always speaks for YOUR class)
    browser.shopBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    browser.shopBtn:SetSize(80, 22)
    browser.shopBtn:SetPoint("RIGHT", toolbar, "RIGHT", -180, 0)
    browser.shopBtn:SetText("Shopping")
    browser.shopBtn:SetScript("OnClick", function()
        if CommanderQuartermaster_ShoppingList then CommanderQuartermaster_ShoppingList() end
    end)

    -- "Owned only" quick filter (mirrors the settings checkbox)
    browser.ownedCheck = CreateFrame("CheckButton", nil, toolbar, "InterfaceOptionsCheckButtonTemplate")
    browser.ownedCheck:SetPoint("RIGHT", toolbar, "RIGHT", -70, 0)
    browser.ownedCheck:SetSize(22, 22)
    if browser.ownedCheck.Text then
        browser.ownedCheck.Text:SetText("Owned only")
    end
    browser.ownedCheck:SetScript("OnClick", function(self)
        db.OwnedOnly = self:GetChecked() and true or false
        offset = 0
        BuildList()
        RefreshSidebar()
        RefreshList()
    end)
    browser.ownedCheck:SetScript("OnShow", function(self)
        self:SetChecked(db.OwnedOnly and true or false)
    end)

    -- Class picker (Loadout view)
    if UIDropDownMenu_Initialize then
        browser.classDrop = CreateFrame("Frame", "CommanderQuartermasterClassDrop", toolbar, "UIDropDownMenuTemplate")
        browser.classDrop:SetPoint("LEFT", browser.viewGear, "RIGHT", 0, -2)
        UIDropDownMenu_SetWidth(browser.classDrop, 120)
        UIDropDownMenu_Initialize(browser.classDrop, function()
            local current = CurrentClass()
            for _, token in ipairs(CLASS_ORDER) do
                if Data.Recommendations[token] then
                    local info = UIDropDownMenu_CreateInfo()
                    local label = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token]) or token
                    info.text = ("|c%s%s|r"):format(ClassColorHex(token), label)
                    info.value = token
                    info.checked = (token == current)
                    info.func = function(button)
                        db.BrowserClass = button.value
                        db.BrowserSpec = false
                        offset = 0
                        FullRefresh()
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end)
    end

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, browser)
    sidebar:SetPoint("TOPLEFT", browser, "TOPLEFT", 10, -64)
    sidebar:SetSize(SIDEBAR_W, MAX_SIDEBAR_ROWS * SIDEBAR_ROW_H)
    local sidebarLine = browser:CreateTexture(nil, "ARTWORK")
    sidebarLine:SetColorTexture(1, 1, 1, 0.08)
    sidebarLine:SetWidth(1)
    sidebarLine:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 3, 0)
    sidebarLine:SetPoint("BOTTOMLEFT", browser, "BOTTOMLEFT", SIDEBAR_W + 13, 10)
    for i = 1, MAX_SIDEBAR_ROWS do
        sidebarButtons[i] = CreateSidebarButton(sidebar, i)
    end

    -- Column headers
    local listArea = CreateFrame("Frame", nil, browser)
    listArea:SetPoint("TOPLEFT", browser, "TOPLEFT", SIDEBAR_W + 18, -82)
    listArea:SetPoint("BOTTOMRIGHT", browser, "BOTTOMRIGHT", -10, 10)
    browser.listArea = listArea

    -- Column heads are sort buttons: click for descending, again for
    -- ascending, a third time restores curated order. Loadout keeps its
    -- slot grouping and ignores them.
    browser.colBtns = {}
    local function HeaderButton(x, key, text)
        local btn = CreateFrame("Button", nil, browser)
        btn:SetSize(COL_W + 4, 14)
        btn:SetPoint("RIGHT", listArea, "TOPRIGHT", x - 14, 8)
        local fs = btn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetAllPoints()
        fs:SetJustifyH("RIGHT")
        fs:SetText(text)
        btn:SetScript("OnClick", function()
            if db.BrowserView == "LOADOUT" then return end
            if sortKey ~= key then
                sortKey, sortAsc = key, false
            elseif not sortAsc then
                sortAsc = true
            else
                sortKey, sortAsc = nil, false
            end
            offset = 0
            FullRefresh()
        end)
        browser.colBtns[#browser.colBtns + 1] = { key = key, fs = fs, base = text, btn = btn }
        return btn
    end
    HeaderButton(COL_LEVEL, "LEVEL", "Lvl")
    HeaderButton(COL_BAGS, "BAGS", "Bags")
    HeaderButton(COL_BANK, "BANK", "Bank")
    HeaderButton(COL_ALTS, "ALTS", "Alts")
    HeaderButton(COL_TOTAL, "TOTAL", "Total")

    for i = 1, VISIBLE_ROWS do
        listRows[i] = CreateRow(listArea, i)
    end

    -- Hand-rolled vertical scrollbar: primitives only, no template risk
    local scrollbar = CreateFrame("Slider", nil, listArea)
    browser.scrollbar = scrollbar
    scrollbar:SetOrientation("VERTICAL")
    scrollbar:SetWidth(8)
    scrollbar:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", -2, 0)
    scrollbar:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -2, 0)
    local track = scrollbar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetVertexColor(0, 0, 0, 0.35)
    scrollbar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = scrollbar:GetThumbTexture()
    if thumb then
        thumb:SetSize(8, 30)
        thumb:SetVertexColor(0.55, 0.55, 0.55, 0.9)
    end
    scrollbar:SetMinMaxValues(0, 0)
    scrollbar:SetValueStep(1)
    scrollbar:SetObeyStepOnDrag(true)
    scrollbar:SetScript("OnValueChanged", function(_, value)
        if updatingSlider then return end
        offset = math.floor(value + 0.5)
        for i = 1, VISIBLE_ROWS do
            BindRow(listRows[i], displayList[offset + i])
        end
    end)

    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        RefreshList()
    end)

    browser:SetScript("OnShow", function()
        if browser.ownedCheck then
            browser.ownedCheck:SetChecked(db.OwnedOnly and true or false)
        end
        FullRefresh()
    end)

    -- Internal handles for the offline smoke harness
    browser._rows = listRows
    browser._sidebar = sidebarButtons
    browser._list = displayList

    ApplyFraming()
    ApplyPosition()
    return browser
end

-- ---------------------------------------------------------------------------
-- Shopping list
-- ---------------------------------------------------------------------------

local shopFrame

local function BuildShoppingText()
    local lines = {}
    local spec = MyLoadoutSpec()
    lines[#lines + 1] = "Commander Quartermaster — shopping list"
    lines[#lines + 1] = ("%s%s · %s"):format(
        charKey or "?",
        spec and (" (" .. spec.name .. ")") or "",
        (date and date("%Y-%m-%d %H:%M")) or "")
    lines[#lines + 1] = ""
    local wrote = false
    if spec then
        local ready = ReadinessFor(spec)
        local gaps = {}
        for _, s in ipairs(ready.slots) do
            local entryName = (s.entry and s.entry.name) or "?"
            if s.state == "MISSING" then
                gaps[#gaps + 1] = ("- %s: BUY %s (none anywhere)"):format(s.name, entryName)
            elseif s.state == "BANKED" then
                gaps[#gaps + 1] = ("- %s: %s ×%d in bank/mail — withdraw"):format(s.name, entryName, s.count)
            elseif s.state == "ELSEWHERE" then
                gaps[#gaps + 1] = ("- %s: %s ×%d on alts — mail it over"):format(s.name, entryName, s.count)
            end
        end
        if #gaps > 0 then
            lines[#lines + 1] = "LOADOUT GAPS"
            for _, gap in ipairs(gaps) do lines[#lines + 1] = gap end
        else
            lines[#lines + 1] = ("Loadout: all %d slots carried."):format(#ready.slots)
        end
        wrote = true
    end
    -- Gear gaps belong on the same list: a bare slot is a shopping trip, and
    -- one you already own the answer to is a trip to the bank instead.
    local E = CommanderQuartermasterEnhance
    if E then
        local report = E.ScanGear("player")
        local gear = {}
        for _, problem in ipairs(E.Problems(report)) do
            if problem.kind == "BARE" then
                local slot = problem.row.slot
                local held = E.BestHeld(slot, CountsFor)
                if held then
                    local bags = select(1, CountsFor(held.entry.item))
                    gear[#gear + 1] = bags > 0
                        and ("- %s: apply %s (in your bags)"):format(problem.row.label, held.name)
                        or ("- %s: %s ×%d — withdraw and apply"):format(
                            problem.row.label, held.name, held.count)
                else
                    local pick = E.BestFor(slot, MyRole())
                    if pick then
                        gear[#gear + 1] = ("- %s: %s — %s"):format(
                            problem.row.label, pick.name,
                            (E.SourceSummary(pick):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
                    end
                end
            elseif problem.kind == "SOCKET" or problem.kind == "META" then
                gear[#gear + 1] = "- " .. problem.text
            end
        end
        if #gear > 0 then
            if wrote then lines[#lines + 1] = "" end
            lines[#lines + 1] = "GEAR ENHANCEMENTS"
            for _, line in ipairs(gear) do lines[#lines + 1] = line end
            wrote = true
        end
    end
    local shorts = WatchShorts()
    if #shorts > 0 then
        if wrote then lines[#lines + 1] = "" end
        lines[#lines + 1] = "WATCHLIST"
        for _, w in ipairs(shorts) do
            lines[#lines + 1] = ("- %s: %d/%d — buy %d"):format(w.name, w.have, w.target, w.target - w.have)
        end
        wrote = true
    end
    if not wrote then
        lines[#lines + 1] = "Nothing to buy — loadout carried, gear enhanced, watchlist stocked."
    end
    return table.concat(lines, "\n")
end

local function EnsureShopFrame()
    if shopFrame then return shopFrame end
    shopFrame = CreateFrame("Frame", "CommanderQuartermasterShopFrame", UIParent, "BackdropTemplate")
    shopFrame:SetSize(430, 330)
    shopFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    shopFrame:SetFrameStrata("DIALOG")
    shopFrame:SetToplevel(true)
    shopFrame:SetMovable(true)
    shopFrame:SetClampedToScreen(true)
    shopFrame:Hide()
    Commander.UI.ApplyStyleBackdrop(shopFrame, "DARK")
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderQuartermasterShopFrame")
    end

    local title = shopFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", shopFrame, "TOPLEFT", 12, -10)
    title:SetText("Quartermaster — Shopping List")

    local drag = CreateFrame("Frame", nil, shopFrame)
    drag:SetPoint("TOPLEFT", shopFrame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", shopFrame, "TOPRIGHT", 0, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() shopFrame:StartMoving() end)
    drag:SetScript("OnDragStop", function() shopFrame:StopMovingOrSizing() end)

    local scroll = CreateFrame("ScrollFrame", nil, shopFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", shopFrame, "TOPLEFT", 12, -34)
    scroll:SetPoint("BOTTOMRIGHT", shopFrame, "BOTTOMRIGHT", -30, 40)
    local edit = CreateFrame("EditBox", nil, scroll)
    shopFrame.edit = edit
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetWidth(380)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)

    local close = CreateFrame("Button", nil, shopFrame, "UIPanelButtonTemplate")
    close:SetSize(80, 22)
    close:SetPoint("BOTTOMRIGHT", shopFrame, "BOTTOMRIGHT", -10, 10)
    close:SetText("Close")
    close:SetScript("OnClick", function() shopFrame:Hide() end)

    local selectAll = CreateFrame("Button", nil, shopFrame, "UIPanelButtonTemplate")
    selectAll:SetSize(90, 22)
    selectAll:SetPoint("RIGHT", close, "LEFT", -6, 0)
    selectAll:SetText("Select All")
    selectAll:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)

    local refresh = CreateFrame("Button", nil, shopFrame, "UIPanelButtonTemplate")
    refresh:SetSize(80, 22)
    refresh:SetPoint("RIGHT", selectAll, "LEFT", -6, 0)
    refresh:SetText("Refresh")
    refresh:SetScript("OnClick", function()
        edit:SetText(BuildShoppingText())
    end)
    return shopFrame
end

-- ---------------------------------------------------------------------------
-- Raid supply check
-- ---------------------------------------------------------------------------

local lastRaidCheckKey, lastRaidCheckAt = nil, 0

local function RaidSupplyCheck()
    if not (loaded and db.EnableQuartermaster and db.RaidCheck) then return end
    local inInstance, instanceType = false, nil
    if IsInInstance then
        inInstance, instanceType = IsInInstance()
    end
    if not inInstance or instanceType ~= "raid" then return end
    local key = (GetInstanceInfo and GetInstanceInfo())
        or (GetRealZoneText and GetRealZoneText()) or "raid"
    -- One check per raid per half hour: a graveyard release and run-back
    -- re-fires PLAYER_ENTERING_WORLD, and that must stay silent
    if key == lastRaidCheckKey and (time() - lastRaidCheckAt) < 1800 then return end
    lastRaidCheckKey, lastRaidCheckAt = key, time()
    local spec = MyLoadoutSpec()
    if not spec then return end
    local ready = ReadinessFor(spec)
    local shorts = WatchShorts()
    if ready.missing == 0 and #shorts == 0 then
        local reachable = ready.banked + ready.elsewhere
        print(("|cff33ff99Commander Quartermaster|r — supply check green: %d/%d slots carried%s"):format(
            ready.carried, #ready.slots,
            reachable > 0 and (", %d reachable"):format(reachable) or ""))
        return
    end
    local gaps = {}
    for _, s in ipairs(ready.slots) do
        if s.state == "MISSING" then gaps[#gaps + 1] = s.name end
    end
    local parts = {}
    if #gaps > 0 then parts[#parts + 1] = "missing " .. table.concat(gaps, ", ") end
    if #shorts > 0 then
        parts[#parts + 1] = ("%d watchlist item%s below target"):format(#shorts, #shorts == 1 and "" or "s")
    end
    print(("|cffff4040Commander Quartermaster — supply check:|r %s"):format(table.concat(parts, "; ")))
    print("  Full detail: /cqm ready · shopping list: /cqm shop")
    if db.RaidCheckSound then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959)
    end
end

-- ---------------------------------------------------------------------------
-- Public entry points (slash handlers live in the DB file)
-- ---------------------------------------------------------------------------

function CommanderQuartermaster_Toggle()
    if not loaded then return end
    if not db.EnableQuartermaster then
        print("Commander Quartermaster is disabled — enable it in its settings panel")
        return
    end
    EnsureBrowser()
    if browser:IsShown() then
        browser:Hide()
    else
        browser:Show()
    end
end

function CommanderQuartermaster_Scan()
    if not loaded then return end
    ScanBags()
    ScanBank()
    ScanMail()
    InvalidateCounts()
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
    local kinds = 0
    for _ in pairs(me.bags) do kinds = kinds + 1 end
    print(("Commander Quartermaster: rescanned — %d tracked items in bags%s%s"):format(
        kinds,
        bankOpen and ", bank updated" or "",
        mailOpen and ", mail updated" or ""))
end

function CommanderQuartermaster_Report()
    if not loaded then return end
    print("|cff33ff99Commander Quartermaster|r — holdings by category:")
    local any = false
    for _, cat in ipairs(Data.Categories) do
        local kinds, qty = 0, 0
        for _, entry in ipairs(cat.items) do
            local _, _, _, _, total = CountsFor(entry.id)
            if total > 0 then
                kinds = kinds + 1
                qty = qty + total
            end
        end
        if kinds > 0 then
            any = true
            print(("  %s: %d of %d items, %d total"):format(cat.name, kinds, #cat.items, qty))
        end
    end
    if not any then
        print("  Nothing tracked yet — play a little, open the bank, check /cqm")
    end
end

-- Readiness verdict to chat: per-slot grades for YOUR class/spec, then
-- watchlist deficits. Same engine the raid supply check runs.
function CommanderQuartermaster_Ready()
    if not loaded then return end
    local spec = MyLoadoutSpec()
    if not spec then
        print("Commander Quartermaster: no loadout data for this class")
        return
    end
    local ready = ReadinessFor(spec)
    print(("|cff33ff99Commander Quartermaster|r — readiness (%s):"):format(spec.name))
    for _, s in ipairs(ready.slots) do
        local entryName = (s.entry and s.entry.name) or "?"
        if s.state == "CARRIED" then
            print(("  %s: %s %s ×%d in bags"):format(s.name, READY_TAGS.CARRIED, entryName, s.count))
        elseif s.state == "BANKED" then
            print(("  %s: %s %s ×%d in bank/mail"):format(s.name, READY_TAGS.BANKED, entryName, s.count))
        elseif s.state == "ELSEWHERE" then
            print(("  %s: %s %s ×%d on alts"):format(s.name, READY_TAGS.ELSEWHERE, entryName, s.count))
        else
            print(("  %s: %s top pick %s"):format(s.name, READY_TAGS.MISSING, entryName))
        end
    end
    local shorts = WatchShorts()
    for _, w in ipairs(shorts) do
        print(("  Watchlist: |cffff4040%s %d/%d|r"):format(w.name, w.have, w.target))
    end
    print(("  Overall: %d/%d carried, %d reachable, %d missing%s"):format(
        ready.carried, #ready.slots, ready.banked + ready.elsewhere, ready.missing,
        #shorts > 0 and (", %d watchlist short"):format(#shorts) or ""))
end

-- Gear audit to chat: what every equipped slot is enchanted and gemmed with,
-- and what is bare. The counts come from the ledger, so a bare slot whose
-- enhancement is sitting in your bank says so instead of sending you shopping.
function CommanderQuartermaster_Gear()
    if not loaded then return end
    local E = CommanderQuartermasterEnhance
    if not E then
        print("Commander Quartermaster: enhancement database not loaded")
        return
    end
    local report = E.ScanGear("player")
    print(("|cff33ff99Commander Quartermaster|r — gear enhancements (%d enhanceable slot%s):"):format(
        report.enchantable, report.enchantable == 1 and "" or "s"))
    for _, row in ipairs(report.rows) do
        if row.link then
            local bits = {}
            local ench = E.EnchantName(row)
            if ench then
                bits[#bits + 1] = "|cff33ff99" .. ench .. "|r"
            elseif row.takesEnchant then
                bits[#bits + 1] = "|cffff4040not enchanted|r"
            elseif row.needsProfession then
                bits[#bits + 1] = ("|cff777777needs %s|r"):format(row.needsProfession)
            end
            local sockets = row.sockets and #row.sockets or 0
            if sockets > 0 then
                local filled = sockets - (row.empty or 0)
                bits[#bits + 1] = ("%sgems %d/%d|r"):format(
                    (row.empty or 0) > 0 and "|cffff4040" or "|cff33ff99", filled, sockets)
                if (row.empty or 0) == 0 and not row.unknownGems then
                    bits[#bits + 1] = row.bonus and "|cff33ff99socket bonus|r"
                        or "|cffff4040socket bonus lost|r"
                end
            end
            if #bits > 0 then
                print(("  %s %s  %s"):format(row.label, row.link, table.concat(bits, "  ")))
            end
        end
    end
    if report.meta then
        print(("  %s%s|r %s"):format(report.meta.active and "|cff33ff99" or "|cffff4040",
            report.meta.entry.name,
            report.meta.active and "is active" or
                ("is INACTIVE — " .. (report.meta.entry.condText or "colour requirement unmet"))))
    end
    -- What to do about it, priced against what you already hold
    for _, problem in ipairs(E.Problems(report)) do
        if problem.kind == "BARE" then
            local best = E.BestHeld and E.BestHeld(problem.row.slot, CountsFor)
            if best then
                print(("  |cffff8040->|r %s: you are holding %s ×%d"):format(
                    problem.row.label, best.name, best.count))
            else
                local pick = E.BestFor and E.BestFor(problem.row.slot, MyRole())
                if pick then
                    print(("  |cffff8040->|r %s: best by stats is %s |cff888888(%s)|r"):format(
                        problem.row.label, pick.name, E.SourceSummary(pick)))
                end
            end
        end
    end
end

function CommanderQuartermaster_ShoppingList()
    if not loaded then return end
    if not db.EnableQuartermaster then
        print("Commander Quartermaster is disabled — enable it in its settings panel")
        return
    end
    EnsureShopFrame()
    shopFrame.edit:SetText(BuildShoppingText())
    shopFrame:Show()
end

-- Roster support: hide/unhide a character from all counts. Writes both the
-- durable opt-out map (their next login re-derives from it) and the live
-- record flag (so counts change immediately).
function CommanderQuartermaster_SetCharacterHidden(realmName, charName, hidden)
    if not (loaded and realmName and charName) then return end
    local rec = ledger[realmName] and ledger[realmName][charName]
    if not rec then return end
    rec.hidden = hidden and true or nil
    db.UntrackedChars = db.UntrackedChars or {}
    db.UntrackedChars[CharToken(realmName, charName)] = hidden and true or nil
    InvalidateCounts()
    Commander.Notify(Events.UPDATE)
end

-- Panel support: the settings page's Forget Character dropdown
function CommanderQuartermaster_ListCharacters(excludeCurrent)
    local out = {}
    if not ledger then return out end
    for realmName, chars in pairs(ledger) do
        for charName, rec in pairs(chars) do
            if not (excludeCurrent and realmName == realmKey and charName == charKey) then
                out[#out + 1] = {
                    realm = realmName, name = charName,
                    class = rec.class, level = rec.level, lastSeen = rec.lastSeen,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.realm ~= b.realm then return a.realm < b.realm end
        return a.name < b.name
    end)
    return out
end

function CommanderQuartermaster_ForgetCharacter(realmName, charName)
    if not (ledger and realmName and charName and ledger[realmName]) then return end
    ledger[realmName][charName] = nil
    if next(ledger[realmName]) == nil then
        ledger[realmName] = nil
    end
    InvalidateCounts()
    Commander.Notify(Events.LEDGER)
    if RefreshBrowserSoon then RefreshBrowserSoon() end
    print(("Commander Quartermaster: forgot %s — %s"):format(charName, realmName))
end

-- ---------------------------------------------------------------------------
-- Settings application & events
-- ---------------------------------------------------------------------------

local function ApplySettings()
    if not loaded then return end
    LinkCharacter()
    RestyleIcons()
    -- Scope and tracking settings all change what CountsFor answers
    InvalidateCounts()
    if browser then
        ApplyFraming()
        ApplyPosition()
        if browser:IsShown() then
            FullRefresh()
        end
    end
end

frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        db = CommanderQuartermasterDB
        CommanderQuartermasterLedger = CommanderQuartermasterLedger or {}
        ledger = CommanderQuartermasterLedger

        realmKey = (GetRealmName and GetRealmName()) or "Unknown"
        charKey = (UnitName and UnitName("player")) or "Unknown"
        ledger[realmKey] = ledger[realmKey] or {}
        me = ledger[realmKey][charKey] or {}
        me.bags = me.bags or {}
        me.bank = me.bank or {}
        me.mail = me.mail or {}
        me.class = PlayerClassToken()
        me.level = UnitLevel and UnitLevel("player") or 0
        me.faction = UnitFactionGroup and UnitFactionGroup("player") or nil
        me.lastSeen = time()
        if GetMoney then me.money = GetMoney() end

        BuildIndex()
        loaded = true
        LinkCharacter()
        InstallTooltipHooks()
        RegisterPopups()
        PruneTransit()

        -- BAG_UPDATE_DELAYED coalesces a whole loot burst into one event;
        -- fall back to raw BAG_UPDATE if this client refuses it (the
        -- IsEventValid guard is NOT sufficient on this engine — see the
        -- MINIMAP_PING lesson — so just try the registration)
        if not pcall(self.RegisterEvent, self, "BAG_UPDATE_DELAYED") then
            self:RegisterEvent("BAG_UPDATE")
        end
        self:RegisterEvent("BANKFRAME_OPENED")
        self:RegisterEvent("BANKFRAME_CLOSED")
        self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
        self:RegisterEvent("MAIL_SHOW")
        self:RegisterEvent("MAIL_INBOX_UPDATE")
        self:RegisterEvent("MAIL_CLOSED")
        self:RegisterEvent("PLAYER_LEVEL_UP")
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("PLAYER_MONEY")
        -- Talent moves change the auto-detected loadout spec; guarded like
        -- every optionally-valid event on this engine
        pcall(self.RegisterEvent, self, "CHARACTER_POINTS_CHANGED")

        -- Outbound-mail transit: the hook is pure observation and fail-safe.
        -- If the confirm event won't register on this client, commit at
        -- send time instead (optimistic; expiry cleans a failed send).
        if type(SendMail) == "function" and type(hooksecurefunc) == "function" then
            hooksecurefunc("SendMail", function(recipient)
                pcall(OnSendMail, recipient)
            end)
            if not pcall(self.RegisterEvent, self, "MAIL_SEND_SUCCESS") then
                sendCommitsDirectly = true
            end
            pcall(self.RegisterEvent, self, "MAIL_FAILED")
        end

        ScanBags()
        Commander.AddListener(Events.UPDATE, ApplySettings)
    elseif not loaded then
        return
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        QueueScan(true, bankOpen, false)
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        QueueScan(false, true, false)
    elseif event == "BANKFRAME_CLOSED" then
        -- Flush a scan still sitting in the 0.25s coalesce window: the
        -- bank cache is readable during this dispatch, and dropping the
        -- scan would freeze a pre-withdrawal snapshot that double-counts
        if dirtyBank then
            dirtyBank = false
            ScanBank()
            InvalidateCounts()
        end
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" then
        QueueScan(false, true, false)
    elseif event == "MAIL_SHOW" then
        -- Do NOT scan yet: inbox data arrives with MAIL_INBOX_UPDATE;
        -- scanning now would record an empty mailbox over a real snapshot
        mailOpen = true
        inboxSeen = false
    elseif event == "MAIL_INBOX_UPDATE" then
        inboxSeen = true
        QueueScan(false, false, true)
    elseif event == "MAIL_CLOSED" then
        -- Same flush as the bank: 'take attachment, close' inside the
        -- coalesce window must not leave collected items counted in mail
        if dirtyMail then
            dirtyMail = false
            ScanMail()
            InvalidateCounts()
        end
        mailOpen = false
    elseif event == "MAIL_SEND_SUCCESS" then
        CommitPendingSend()
    elseif event == "MAIL_FAILED" then
        pendingSend = nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Let loading-screen instance info settle before the supply check
        C_Timer.After(2, RaidSupplyCheck)
    elseif event == "PLAYER_MONEY" then
        if me and GetMoney then me.money = GetMoney() end
        if RefreshBrowserSoon then RefreshBrowserSoon(true) end
    elseif event == "CHARACTER_POINTS_CHANGED" then
        if RefreshBrowserSoon then RefreshBrowserSoon() end
    elseif event == "PLAYER_LEVEL_UP" then
        me.level = tonumber(arg1) or me.level
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Names/quality resolve lazily; re-bind visible rows when one of
        -- OUR items lands (arg1 = itemID; anything else is other addons'
        -- traffic and none of our rows can have changed). While sorted by
        -- item level the ORDER itself depends on arrivals — full rebuild.
        if byID[arg1] and RefreshBrowserSoon then
            RefreshBrowserSoon(sortKey ~= "LEVEL")
        end
    end
end)

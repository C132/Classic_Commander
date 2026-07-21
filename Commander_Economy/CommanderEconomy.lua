-- Commander Economy: session bookkeeping for the mission summary. Tracking
-- runs whether or not the module is enabled (same precedent as Top Bar's XP
-- bookkeeping) so enabling mid-session still yields a full-session report;
-- the flag gates the report output and the hourly ticker.

local sessionStart = 0
local goldEarned, goldSpent = 0, 0
local lastMoney = nil
local xpGained = 0
local prevXP, prevXPMax, prevLevel = nil, nil, nil
local questsTurnedIn = 0
local deaths = 0
local deadNow = false   -- PLAYER_DEAD re-fires in odd rez flows; count once
local hourlyTicker = nil
local lootCount, lootRarePlus = 0, 0
local lootedItems = {}         -- itemIDs in loot order, session-long
local kills = 0                -- kill credits from combat XP messages
local lootValue = 0            -- summed vendor value of looted items
local maxGain, maxSpend = 0, 0 -- biggest single money swing each way
local bestFindID, bestFindQuality, bestFindValue = nil, nil, 0
local segmentHistory = {}      -- completed instance segments, newest last
local SEGMENT_HISTORY_CAP = 5
local instanceSnap = nil       -- counters snapshotted at instance entry
local lastInstanceReport = nil -- deltas from the most recent completed instance
local session                  -- reload-resilient mirror of all of the above

local function SyncCounters()
    if not session then return end
    session.goldEarned, session.goldSpent = goldEarned, goldSpent
    session.xpGained = xpGained
    session.quests, session.deaths = questsTurnedIn, deaths
    session.lootCount, session.lootRare = lootCount, lootRarePlus
    session.kills = kills
    session.lootValue = lootValue
    session.maxGain, session.maxSpend = maxGain, maxSpend
    session.bestFindID = bestFindID or false
    session.bestFindQuality = bestFindQuality or false
    session.bestFindValue = bestFindValue
end

local function Coins(copper)
    local sign = copper < 0 and "-" or ""
    copper = math.abs(copper)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    if gold > 0 then
        return string.format("%s%dg %ds", sign, gold, silver)
    end
    return string.format("%s%ds %dc", sign, silver, copper % 100)
end

local function SessionDuration()
    local elapsed = GetTime() - sessionStart
    if elapsed < 0 then elapsed = 0 end
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes), elapsed
    end
    return string.format("%dm", minutes), elapsed
end

local function DurationString(elapsed)
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end
    return string.format("%dm", minutes)
end

function CommanderEconomy_Report()
    if not (CommanderEconomyDB and CommanderEconomyDB.EnableEconomy) then
        print("Commander Economy: module is disabled (enable it in settings or /ceco)")
        return
    end
    local duration, elapsed = SessionDuration()
    print(string.format("Commander Economy — mission summary (%s):", duration))
    print(string.format("  Gold: %s earned, %s spent (net %s)",
        Coins(goldEarned), Coins(goldSpent), Coins(goldEarned - goldSpent)))
    if elapsed >= 60 and xpGained > 0 then
        print(string.format("  Experience: %d gained (%d per hour)",
            xpGained, math.floor(xpGained / (elapsed / 3600))))
    else
        print(string.format("  Experience: %d gained", xpGained))
    end
    print(string.format("  Quests turned in: %d | Casualties: %d", questsTurnedIn, deaths))
    print(string.format("  Supplies: %d item%s looted (%d uncommon+)",
        lootCount, lootCount == 1 and "" or "s", lootRarePlus))
end

-- ---------------------------------------------------------------------------
-- After Action Report window: the score screen, in a frame instead of a
-- chat scroll. Shows either the full session or the most recent instance
-- segment; instance segments are detected automatically.
-- ---------------------------------------------------------------------------
local AAR_LINES = 9
local AAR_ICONS = 12

local aar = CreateFrame("Frame", "CommanderEconomyAAR", UIParent)
aar:SetSize(420, 348)
aar:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
aar:SetFrameStrata("DIALOG")
aar:SetMovable(true)
aar:EnableMouse(true)
aar:RegisterForDrag("LeftButton")
aar:SetScript("OnDragStart", aar.StartMoving)
aar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Screen-space save, like every other Commander frame
    local point, _, _, x, y = self:GetPoint(1)
    if point and CommanderEconomyDB then
        local aarScale = self:GetScale() or 1
        CommanderEconomyDB.AarPos = { point = point, x = x * aarScale, y = y * aarScale }
    end
end)
aar:Hide()

-- Style, scale, and saved position, aligned with the suite's framing
local function ApplyAarLook()
    local aarScale = (CommanderEconomyDB and CommanderEconomyDB.AarScale) or 1
    aar:SetScale(aarScale)
    Commander.UI.ApplyStyleBackdrop(aar, (CommanderEconomyDB and CommanderEconomyDB.AarStyle) or "CLASSIC")
    local pos = CommanderEconomyDB and CommanderEconomyDB.AarPos
    aar:ClearAllPoints()
    if pos and pos.point then
        aar:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / aarScale, (pos.y or 0) / aarScale)
    else
        aar:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    end
end
if UISpecialFrames then
    table.insert(UISpecialFrames, "CommanderEconomyAAR")
end

local aarTitle = aar:CreateFontString(nil, "OVERLAY")
aarTitle:SetFontObject(GameFontNormalLarge)
aarTitle:SetPoint("TOP", aar, "TOP", 0, -18)
aarTitle:SetText("AFTER ACTION REPORT")
aarTitle:SetTextColor(1, 0.82, 0.15)

local aarSubtitle = aar:CreateFontString(nil, "OVERLAY")
aarSubtitle:SetFontObject(GameFontHighlightSmall)
aarSubtitle:SetPoint("TOP", aarTitle, "BOTTOM", 0, -4)

local aarLines = {}
for i = 1, AAR_LINES do
    local line = aar:CreateFontString(nil, "OVERLAY")
    line:SetFontObject(GameFontHighlight)
    line:SetPoint("TOPLEFT", aar, "TOPLEFT", 26, -58 - (i - 1) * 22)
    line:SetPoint("RIGHT", aar, "RIGHT", -26, 0)
    line:SetJustifyH("LEFT")
    -- Truncate rather than wrap: a wrapped line would overlap the next row
    if line.SetWordWrap then
        line:SetWordWrap(false)
    end
    aarLines[i] = line
end

local aarClose = CreateFrame("Button", nil, aar, "UIPanelCloseButton")
aarClose:SetPoint("TOPRIGHT", aar, "TOPRIGHT", -4, -4)

-- Share the displayed report to the group (instance > raid > party)
local function ShareChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

-- Declared HERE, above every reader: the original Share button read a
-- global aarCurrent that was forever nil because this local used to be
-- declared 180 lines below the share function — the button never worked
local aarCurrent     -- what the window is currently showing (share/print)
local aarHistoryPos = 0   -- 0 = live view; N = Nth-newest completed run

local function ReportIsEmpty(d)
    return (d.goldEarned or 0) == 0 and (d.goldSpent or 0) == 0
        and (d.xpGained or 0) == 0 and (d.kills or 0) == 0
        and (d.quests or 0) == 0 and (d.loot or 0) == 0
        and (d.deaths or 0) == 0
end

local function ShareReportData(subtitle, d)
    local channel = ShareChannel()
    if not channel then
        print("Commander Economy: no group to share the report with")
        return
    end
    if ReportIsEmpty(d) then
        print("Commander Economy: this report recorded nothing — not sharing an empty page")
        return
    end
    SendChatMessage(string.format("Commander AAR — %s (%s)", subtitle, d.duration), channel)
    SendChatMessage(string.format("Gold: %s earned, %s spent (net %s)",
        Coins(d.goldEarned), Coins(d.goldSpent), Coins(d.goldEarned - d.goldSpent)), channel)
    local xpText
    if d.elapsed >= 60 and d.xpGained > 0 then
        xpText = string.format("%d (%d/hour)", d.xpGained, math.floor(d.xpGained / (d.elapsed / 3600)))
    else
        xpText = tostring(d.xpGained)
    end
    SendChatMessage(string.format("XP: %s | Kills: %d | Quests: %d | Deaths: %d | Loot: %d items (%d uncommon+)",
        xpText, d.kills or 0, d.quests, d.deaths, d.loot, d.lootRare), channel)
end

function CommanderEconomy_ShareReport()
    if not aarCurrent then
        print("Commander Economy: open a report first (/ceco aar)")
        return
    end
    ShareReportData(aarCurrent.subtitle, aarCurrent.data)
end

local function PrintReportData(subtitle, d)
    print(string.format("Commander AAR — %s (%s)", subtitle, d.duration))
    print(string.format("  Gold: %s earned, %s spent (net %s)",
        Coins(d.goldEarned), Coins(d.goldSpent), Coins(d.goldEarned - d.goldSpent)))
    print(string.format("  XP: %d | Kills: %d | Quests: %d | Deaths: %d",
        d.xpGained, d.kills or 0, d.quests, d.deaths))
    local lootLine = string.format("  Loot: %d item%s (%d uncommon+)",
        d.loot, d.loot == 1 and "" or "s", d.lootRare)
    if (d.lootValue or 0) > 0 then
        lootLine = lootLine .. string.format(", worth ~%s", Coins(d.lootValue))
    end
    print(lootLine)
end

function CommanderEconomy_PrintReport()
    if not aarCurrent then
        print("Commander Economy: open a report first (/ceco aar)")
        return
    end
    PrintReportData(aarCurrent.subtitle, aarCurrent.data)
end

local aarShare = CreateFrame("Button", nil, aar, "UIPanelButtonTemplate")
aarShare:SetSize(62, 20)
aarShare:SetPoint("BOTTOMLEFT", aar, "BOTTOMLEFT", 24, 14)
aarShare:SetText("Share")
aarShare:SetScript("OnClick", function()
    CommanderEconomy_ShareReport()
end)

local aarPrint = CreateFrame("Button", nil, aar, "UIPanelButtonTemplate")
aarPrint:SetSize(56, 20)
aarPrint:SetPoint("LEFT", aarShare, "RIGHT", 6, 0)
aarPrint:SetText("Print")
aarPrint:SetScript("OnClick", function()
    CommanderEconomy_PrintReport()
end)
Commander.UI.AttachTooltip(aarPrint, "Print",
    "Print this report to your chat window — a local copy, nothing sent to the group.")

local aarHistory = CreateFrame("Button", nil, aar, "UIPanelButtonTemplate")
aarHistory:SetSize(68, 20)
aarHistory:SetPoint("LEFT", aarPrint, "RIGHT", 6, 0)
aarHistory:SetText("History")
aarHistory:SetScript("OnClick", function()
    if CommanderEconomy_CycleHistory then CommanderEconomy_CycleHistory() end
end)
Commander.UI.AttachTooltip(aarHistory, "Run History",
    "Cycle through this session's completed dungeon and raid runs, newest first, then back to the full session.")

local aarNewMission = CreateFrame("Button", nil, aar, "UIPanelButtonTemplate")
aarNewMission:SetSize(100, 20)
aarNewMission:SetPoint("LEFT", aarHistory, "RIGHT", 6, 0)
aarNewMission:SetText("New Mission")
aarNewMission:SetScript("OnClick", function()
    if CommanderEconomy_NewMission then CommanderEconomy_NewMission() end
end)
Commander.UI.AttachTooltip(aarNewMission, "New Mission",
    "Zero every session counter and start the books fresh — gold, XP, kills, loot, runs, records (also: /ceco newmission).")

-- Icon strip: the report's spoils, hoverable for full item tooltips
local aarIcons = {}
for i = 1, AAR_ICONS do
    local icon = CreateFrame("Button", nil, aar)
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", aar, "TOPLEFT", 26 + (i - 1) * 28, -262)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(self.itemID)
            end
            GameTooltip:Show()
        end
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:Hide()
    aarIcons[i] = icon
end

local function FillReportIcons(items)
    local shown = 0
    if items then
        -- Newest first, capped at the strip length
        for i = #items, 1, -1 do
            if shown >= AAR_ICONS then break end
            local itemID = items[i]
            shown = shown + 1
            local icon = aarIcons[shown]
            icon.itemID = itemID
            local texture
            if C_Item and C_Item.GetItemInfo then
                texture = select(10, C_Item.GetItemInfo(itemID))
            end
            icon.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            icon:Show()
        end
    end
    for i = shown + 1, AAR_ICONS do
        aarIcons[i]:Hide()
        aarIcons[i].itemID = nil
    end
end

-- ---------------------------------------------------------------------------
-- Bag glow: items in the report glow in the bags until moused over. Armed
-- exactly once each time a report is shown, feature-flagged.
-- ---------------------------------------------------------------------------
local glowSet = {}
local glowsShown = 0   -- lit glows on screen, so empty scans can bail

local function HideButtonGlow(button)
    if button._commanderEcoGlow and button._commanderEcoGlowShown then
        button._commanderEcoGlowShown = nil
        glowsShown = glowsShown - 1
        button._commanderEcoGlow:Hide()
    end
end

local function ApplyBagGlows()
    -- The else-branch of the loop is the cleanup pass that hides glows no
    -- longer wanted — but with nothing armed AND nothing lit there is no
    -- possible work, and that is the overwhelmingly common case (glows
    -- only exist between opening a report and mousing over the loot).
    -- Bailing here skips a per-slot scan on every bag event.
    if not next(glowSet) and glowsShown == 0 then return end
    for f = 1, 13 do
        local containerFrame = _G["ContainerFrame" .. f]
        if containerFrame and containerFrame:IsShown() then
            local bagID = containerFrame:GetID()
            local baseName = containerFrame:GetName() .. "Item"
            for j = 1, containerFrame.size or 0 do
                local button = _G[baseName .. j]
                if button then
                    -- GetContainerItemID returns a plain number; the old
                    -- GetContainerItemInfo allocated a table per slot
                    local itemID = C_Container.GetContainerItemID
                        and C_Container.GetContainerItemID(bagID, button:GetID())
                    local wanted = itemID and glowSet[itemID]
                    if wanted then
                        if not button._commanderEcoGlow then
                            local glow = button:CreateTexture(nil, "OVERLAY")
                            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                            glow:SetBlendMode("ADD")
                            glow:SetVertexColor(1, 0.82, 0.15, 0.9)
                            glow:SetPoint("CENTER")
                            glow:SetSize(button:GetWidth() and button:GetWidth() * 1.7 or 62, button:GetHeight() and button:GetHeight() * 1.7 or 62)
                            button._commanderEcoGlow = glow
                        end
                        if not button._commanderEcoGlowShown then
                            button._commanderEcoGlowShown = true
                            glowsShown = glowsShown + 1
                        end
                        button._commanderEcoGlow:Show()
                        if not button._commanderEcoHooked then
                            button._commanderEcoHooked = true
                            button:HookScript("OnEnter", function(self)
                                local hoveredID = C_Container.GetContainerItemID
                                    and C_Container.GetContainerItemID(
                                        self:GetParent() and self:GetParent():GetID() or 0, self:GetID())
                                if hoveredID then
                                    glowSet[hoveredID] = nil
                                end
                                HideButtonGlow(self)
                            end)
                        end
                    else
                        HideButtonGlow(button)
                    end
                end
            end
        end
    end
end

local function ArmBagGlows(items)
    -- Always wipe first: opening a report with the flag off must clear any
    -- previously armed set, not leave it re-applying forever
    wipe(glowSet)
    if CommanderEconomyDB and CommanderEconomyDB.BagGlow and items then
        for _, itemID in ipairs(items) do
            glowSet[itemID] = true
        end
    end
    ApplyBagGlows()
end

-- Opening a bag fires no BAG_UPDATE, so the glows also need a hook on the
-- open paths themselves (deferred a frame so the container frames exist).
-- Coalesced: ToggleAllBags cascades into per-bag hooks, so one keypress
-- would otherwise queue ~6 timers and 6 redundant scans in the same frame.
local applyPending = false
local function RunDeferredApply()
    applyPending = false
    ApplyBagGlows()
end
local function DeferredApply()
    if applyPending then return end
    applyPending = true
    C_Timer.After(0, RunDeferredApply)
end
if hooksecurefunc then
    pcall(hooksecurefunc, "ToggleBag", DeferredApply)
    pcall(hooksecurefunc, "ToggleAllBags", DeferredApply)
    pcall(hooksecurefunc, "OpenAllBags", DeferredApply)
    pcall(hooksecurefunc, "OpenBag", DeferredApply)
end

local function FillReport(subtitle, data)
    aarCurrent = { subtitle = subtitle, data = data }
    aarSubtitle:SetText(subtitle)

    local goldLine = string.format("Gold:  %s earned   %s spent   (net %s)",
        Coins(data.goldEarned), Coins(data.goldSpent), Coins(data.goldEarned - data.goldSpent))
    if (data.elapsed or 0) >= 60 then
        goldLine = goldLine .. string.format("  ·  %s/hr",
            Coins(math.floor((data.goldEarned - data.goldSpent) / (data.elapsed / 3600))))
    end
    aarLines[1]:SetText(goldLine)

    local xpLine
    if data.elapsed >= 60 and data.xpGained > 0 then
        xpLine = string.format("Experience:  %d gained  (%d per hour)",
            data.xpGained, math.floor(data.xpGained / (data.elapsed / 3600)))
    else
        xpLine = string.format("Experience:  %d gained", data.xpGained)
    end
    if data.levelIn then
        xpLine = xpLine .. string.format("  ·  level up in ~%s", data.levelIn)
    end
    aarLines[2]:SetText(xpLine)

    if (data.kills or 0) > 0 and data.elapsed >= 60 then
        aarLines[3]:SetText(string.format("Kills:  %d  (%d per hour)",
            data.kills, math.floor(data.kills / (data.elapsed / 3600))))
    else
        aarLines[3]:SetText(string.format("Kills:  %d", data.kills or 0))
    end

    aarLines[4]:SetText(string.format("Quests turned in:  %d", data.quests))
    aarLines[5]:SetText(string.format("Casualties:  %d", data.deaths))

    local supplyLine = string.format("Supplies:  %d item%s looted  (%d uncommon+)",
        data.loot, data.loot == 1 and "" or "s", data.lootRare)
    if (data.lootValue or 0) > 0 then
        supplyLine = supplyLine .. string.format("  ·  worth ~%s", Coins(data.lootValue))
    end
    aarLines[6]:SetText(supplyLine)

    if data.bestFindID and C_Item and C_Item.GetItemInfo then
        local _, link = C_Item.GetItemInfo(data.bestFindID)
        aarLines[7]:SetText("Best find:  " .. (link or "(item data loading — reopen in a moment)"))
    else
        aarLines[7]:SetText("Best find:  —")
    end

    if data.maxGain then
        aarLines[8]:SetText(string.format("Biggest haul:  +%s   Biggest expense:  -%s",
            Coins(data.maxGain), Coins(data.maxSpend or 0)))
    else
        aarLines[8]:SetText("")
    end

    aarLines[9]:SetText(string.format("Duration:  %s", data.duration))

    FillReportIcons(data.items)
    -- The Share button only lights up when there is a group to receive it
    aarShare:SetEnabled(ShareChannel() ~= nil)
    ApplyAarLook()
    aar:Show()
    -- Bag glow arms exactly once per report display
    ArmBagGlows(data.items)
end

function CommanderEconomy_ShowReport(kind)
    if not (CommanderEconomyDB and CommanderEconomyDB.EnableEconomy) then
        print("Commander Economy: module is disabled (enable it in settings or /ceco)")
        return
    end
    aarHistoryPos = 0
    if kind == "instance" then
        if not lastInstanceReport then
            print("Commander Economy: no completed instance segment this session yet")
            return
        end
        FillReport(lastInstanceReport.name, lastInstanceReport)
        return
    end
    local duration, elapsed = SessionDuration()
    -- At the current XP pace, when does the next level land? Only shown
    -- once the pace means something (5+ minutes, some XP, not capped)
    local levelIn
    if xpGained > 0 and elapsed >= 300 and UnitXP and UnitXPMax then
        local xpMax = UnitXPMax("player") or 0
        local remaining = xpMax - (UnitXP("player") or 0)
        local rate = xpGained / elapsed
        if xpMax > 0 and remaining > 0 and rate > 0 then
            levelIn = DurationString(remaining / rate)
        end
    end
    -- Only the newest items: arming a glow for hours of loot would light
    -- up the whole bag, defeating spot-the-spoils
    local recent = {}
    for i = math.max(#lootedItems - (AAR_ICONS - 1), 1), #lootedItems do
        recent[#recent + 1] = lootedItems[i]
    end
    FillReport("Full session", {
        goldEarned = goldEarned, goldSpent = goldSpent, xpGained = xpGained,
        quests = questsTurnedIn, deaths = deaths,
        loot = lootCount, lootRare = lootRarePlus,
        kills = kills, lootValue = lootValue,
        bestFindID = bestFindID,
        maxGain = maxGain, maxSpend = maxSpend,
        levelIn = levelIn,
        duration = duration, elapsed = elapsed,
        items = recent,
    })
end

function CommanderEconomy_CycleHistory()
    if #segmentHistory == 0 then
        print("Commander Economy: no completed runs recorded yet this session")
        return
    end
    local nextPos = aarHistoryPos + 1
    if nextPos > #segmentHistory then
        CommanderEconomy_ShowReport("session")
        return
    end
    local entry = segmentHistory[#segmentHistory - nextPos + 1]
    FillReport(string.format("%s  —  run %d of %d, newest first",
        entry.name or "Instance", nextPos, #segmentHistory), entry)
    aarHistoryPos = nextPos
end

-- CommanderEconomy_NewMission is defined AFTER the instance-segment
-- section below: it writes pendingExit and calls SyncSegments and
-- CheckInstanceSegment, and a definition up here would compile those as
-- globals instead of the locals declared later (the same forward-
-- reference class of bug that silenced the original Share button)

-- ---------------------------------------------------------------------------
-- Instance segments
-- ---------------------------------------------------------------------------
-- A dungeon run is not over just because the player briefly left the
-- instance: ghost releases, meeting-stone summons, and BG queue pops all
-- exit and return. The segment only finalizes after a grace period spent
-- genuinely outside (or when a different instance begins).
local EXIT_GRACE = 180
local pendingExit = nil   -- { snap, at }
local pendingAutoShow = false   -- auto-report deferred until combat ends

local function FinalizeSegment(snap)
    -- Epoch-based: segment durations stay correct across /reload and even
    -- a full client restart mid-run
    local elapsed = snap.startEpoch and (time() - snap.startEpoch) or (GetTime() - (snap.start or GetTime()))
    -- Items looted during the segment: everything past the entry watermark
    local segmentItems = {}
    for i = (snap.itemWatermark or 0) + 1, #lootedItems do
        segmentItems[#segmentItems + 1] = lootedItems[i]
    end
    -- Best find within this run alone
    local segBestID, segBestQuality, segBestValue
    if C_Item and C_Item.GetItemInfo then
        for i = 1, #segmentItems do
            local _, _, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(segmentItems[i])
            if quality and (quality > (segBestQuality or -1)
                or (quality == segBestQuality and (sellPrice or 0) > (segBestValue or 0))) then
                segBestID, segBestQuality, segBestValue = segmentItems[i], quality, sellPrice or 0
            end
        end
    end
    lastInstanceReport = {
        name = snap.name,
        goldEarned = goldEarned - snap.goldEarned,
        goldSpent = goldSpent - snap.goldSpent,
        xpGained = xpGained - snap.xpGained,
        quests = questsTurnedIn - snap.quests,
        deaths = deaths - snap.deaths,
        loot = lootCount - snap.loot,
        lootRare = lootRarePlus - snap.lootRare,
        kills = kills - (snap.kills or 0),
        lootValue = lootValue - (snap.lootValue or 0),
        bestFindID = segBestID,
        duration = DurationString(elapsed),
        elapsed = elapsed,
        items = segmentItems,
    }
    segmentHistory[#segmentHistory + 1] = lastInstanceReport
    while #segmentHistory > SEGMENT_HISTORY_CAP do
        table.remove(segmentHistory, 1)
    end
    if session then
        session.lastInstanceReport = lastInstanceReport
        session.segmentHistory = segmentHistory
    end
    -- Empty runs (walked in, walked out) never pop a window or say a word
    if not (CommanderEconomyDB.EnableEconomy) or ReportIsEmpty(lastInstanceReport) then
        return
    end
    if CommanderEconomyDB.AutoInstanceReport then
        if UnitAffectingCombat and UnitAffectingCombat("player") then
            -- Never ambush mid-pull: the report waits for the fight to end
            pendingAutoShow = true
        else
            CommanderEconomy_ShowReport("instance")
        end
    end
    if CommanderEconomyDB.AutoShare then
        ShareReportData(lastInstanceReport.name, lastInstanceReport)
    end
end

local function SyncSegments()
    if not session then return end
    session.instanceSnap = instanceSnap or false
    session.pendingExit = pendingExit or false
end

local function ArmExitGraceTimer(delay)
    C_Timer.After(delay, function()
        if pendingExit and (time() - (pendingExit.atEpoch or 0)) >= (EXIT_GRACE - 1) then
            FinalizeSegment(pendingExit.snap)
            pendingExit = nil
            SyncSegments()
        end
    end)
end

local function CheckInstanceSegment()
    local inInstance, instanceType = IsInInstance()
    local tracking = inInstance and (instanceType == "party" or instanceType == "raid")
    if tracking then
        local name = GetInstanceInfo() or "Instance"
        if pendingExit then
            if pendingExit.snap.name == name then
                -- Back in the same run within the grace period: resume
                instanceSnap = pendingExit.snap
                pendingExit = nil
                SyncSegments()
                return
            end
            FinalizeSegment(pendingExit.snap)
            pendingExit = nil
        end
        if not instanceSnap then
            instanceSnap = {
                name = name,
                startEpoch = time(),
                goldEarned = goldEarned, goldSpent = goldSpent, xpGained = xpGained,
                quests = questsTurnedIn, deaths = deaths,
                loot = lootCount, lootRare = lootRarePlus,
                kills = kills, lootValue = lootValue,
                itemWatermark = #lootedItems,
            }
        end
        SyncSegments()
    elseif instanceSnap then
        -- Ghost releases land outside the instance; ignore them entirely
        if UnitIsDeadOrGhost("player") then return end
        pendingExit = { snap = instanceSnap, atEpoch = time() }
        instanceSnap = nil
        SyncSegments()
        ArmExitGraceTimer(EXIT_GRACE)
    end
end

-- Zero every session counter and start the books fresh. Defined below the
-- segment section on purpose: it writes pendingExit and calls SyncSegments
-- and CheckInstanceSegment, which must resolve as locals.
function CommanderEconomy_NewMission()
    goldEarned, goldSpent, xpGained = 0, 0, 0
    questsTurnedIn, deaths, kills = 0, 0, 0
    lootCount, lootRarePlus, lootValue = 0, 0, 0
    maxGain, maxSpend = 0, 0
    bestFindID, bestFindQuality, bestFindValue = nil, nil, 0
    wipe(lootedItems)
    wipe(segmentHistory)
    lastInstanceReport = nil
    instanceSnap, pendingExit = nil, nil
    aarHistoryPos = 0
    sessionStart = GetTime()
    lastMoney = GetMoney()
    if session then
        session.startEpoch = time()
        session.lastInstanceReport = false
        SyncCounters()
        SyncSegments()
    end
    -- Mid-instance reset: open a fresh segment for the rest of this run
    CheckInstanceSegment()
    print("Commander Economy: new mission — the books start fresh")
    if aar:IsShown() then
        CommanderEconomy_ShowReport("session")
    end
end

-- ---------------------------------------------------------------------------
-- Loot bookkeeping: self-loot chat messages carry the item link's quality
-- color. Count everything, and uncommon-or-better separately.
-- ---------------------------------------------------------------------------
local RARE_COLORS = {
    ["ff1eff00"] = true, -- uncommon
    ["ff0070dd"] = true, -- rare
    ["ffa335ee"] = true, -- epic
    ["ffff8000"] = true, -- legendary
}

local function OnLootMessage(message)
    if type(message) ~= "string" then return end
    if not (message:find("You receive loot") or message:find("You receive item")) then return end
    lootCount = lootCount + 1
    local color = message:match("|c(%x%x%x%x%x%x%x%x)")
    if color and RARE_COLORS[color:lower()] then
        lootRarePlus = lootRarePlus + 1
    end
    local itemID = tonumber(message:match("|Hitem:(%d+)"))
    if itemID then
        lootedItems[#lootedItems + 1] = itemID
        -- Vendor-value running total and session best find. Item data may
        -- not be cached on first sight; those items simply don't count
        -- toward the estimate (hence the "~").
        if C_Item and C_Item.GetItemInfo then
            local _, _, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(itemID)
            if sellPrice then
                lootValue = lootValue + sellPrice
            end
            if quality and (quality > (bestFindQuality or -1)
                or (quality == bestFindQuality and (sellPrice or 0) > bestFindValue)) then
                bestFindID, bestFindQuality, bestFindValue = itemID, quality, sellPrice or 0
            end
        end
    end
end

local function UpdateTicker()
    local wantTicker = CommanderEconomyDB
        and CommanderEconomyDB.EnableEconomy and CommanderEconomyDB.HourlyReport
    if wantTicker and not hourlyTicker then
        hourlyTicker = C_Timer.NewTicker(3600, CommanderEconomy_Report)
    elseif not wantTicker and hourlyTicker then
        hourlyTicker:Cancel()
        hourlyTicker = nil
    end
    -- Turning Bag Glow off must clear glows that are already lit
    if CommanderEconomyDB and not CommanderEconomyDB.BagGlow and next(glowSet) then
        wipe(glowSet)
        ApplyBagGlows()
    end
end

local function OnMoney()
    local money = GetMoney()
    if lastMoney then
        local delta = money - lastMoney
        if delta > 0 then
            goldEarned = goldEarned + delta
            if delta > maxGain then maxGain = delta end
        elseif delta < 0 then
            goldSpent = goldSpent - delta
            if -delta > maxSpend then maxSpend = -delta end
        end
    end
    lastMoney = money
end

local function OnXP()
    local xp, xpMax, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if prevXP then
        local delta
        if level > prevLevel then
            -- Leveled since the last update: finish the old bar, then add
            -- progress into the new one (multi-level jumps under-count the
            -- skipped bars, acceptable for a session summary)
            delta = (prevXPMax - prevXP) + xp
        else
            delta = xp - prevXP
        end
        if delta > 0 then
            xpGained = xpGained + delta
        end
    end
    prevXP, prevXPMax, prevLevel = xp, xpMax, level
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("CHAT_MSG_LOOT")
events:RegisterEvent("BAG_UPDATE_DELAYED")
-- Quest turn-in event: valid on this client, but guard like MINIMAP_PING in
-- case a future patch moves it — quests just stop counting, nothing breaks
if not C_EventUtils or C_EventUtils.IsEventValid("QUEST_TURNED_IN") then
    pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
end
-- Kill credit rides the combat XP message ("X dies, you gain N experience.")
-- — free compared to a combat-log listener; guarded the same way
if not C_EventUtils or C_EventUtils.IsEventValid("CHAT_MSG_COMBAT_XP_GAIN") then
    pcall(events.RegisterEvent, events, "CHAT_MSG_COMBAT_XP_GAIN")
end
events:RegisterEvent("PLAYER_REGEN_ENABLED")

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- Resume the session's economics across /reload; only a real
        -- break starts the books over
        local fresh
        session, fresh = Commander.RestoreSession(CommanderEconomyDB, {
            startEpoch = time(),
            goldEarned = 0, goldSpent = 0, xpGained = 0,
            quests = 0, deaths = 0, lootCount = 0, lootRare = 0,
            kills = 0, lootValue = 0, maxGain = 0, maxSpend = 0,
            bestFindID = false, bestFindQuality = false, bestFindValue = 0,
            lootedItems = {}, segmentHistory = {},
            lastInstanceReport = false, instanceSnap = false, pendingExit = false,
        })
        if fresh then
            session.startEpoch = time()
        end
        goldEarned, goldSpent = session.goldEarned, session.goldSpent
        xpGained = session.xpGained
        questsTurnedIn, deaths = session.quests, session.deaths
        lootCount, lootRarePlus = session.lootCount, session.lootRare
        -- `or` guards: sessions written by older versions miss these keys
        kills = session.kills or 0
        lootValue = session.lootValue or 0
        maxGain, maxSpend = session.maxGain or 0, session.maxSpend or 0
        bestFindID = session.bestFindID or nil
        bestFindQuality = session.bestFindQuality or nil
        bestFindValue = session.bestFindValue or 0
        lootedItems = session.lootedItems
        segmentHistory = session.segmentHistory or {}
        session.segmentHistory = segmentHistory
        lastInstanceReport = session.lastInstanceReport or nil
        sessionStart = GetTime() - (time() - session.startEpoch)
        if session.instanceSnap then
            -- Mid-run reload: the segment carries straight on
            instanceSnap = session.instanceSnap
        end
        if session.pendingExit then
            pendingExit = session.pendingExit
            local remaining = EXIT_GRACE - (time() - (pendingExit.atEpoch or 0))
            if remaining > 0 then
                ArmExitGraceTimer(remaining)
            else
                FinalizeSegment(pendingExit.snap)
                pendingExit = nil
                SyncSegments()
            end
        end
        -- Money/XP watermarks always re-baseline from live values
        lastMoney = GetMoney()
        prevXP, prevXPMax, prevLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        Commander.AddListener(COMMANDER_ECONOMY_EVENTS.UPDATE, UpdateTicker)
        Commander.AddListener(COMMANDER_ECONOMY_EVENTS.UPDATE, ApplyAarLook)
        UpdateTicker()
    elseif event == "PLAYER_MONEY" then
        OnMoney()
        SyncCounters()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP()
        SyncCounters()
    elseif event == "PLAYER_DEAD" then
        -- Feign Death can emit PLAYER_DEAD without the unit being dead
        if not deadNow and UnitIsDeadOrGhost("player") then
            deaths = deaths + 1
            deadNow = true
            SyncCounters()
        end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if not UnitIsGhost("player") then
            deadNow = false
        end
    elseif event == "QUEST_TURNED_IN" then
        questsTurnedIn = questsTurnedIn + 1
        SyncCounters()
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        -- Plain quest XP messages carry no "dies," — only kill credit does
        if type(arg1) == "string" and arg1:find("dies,", 1, true) then
            kills = kills + 1
            SyncCounters()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingAutoShow then
            pendingAutoShow = false
            CommanderEconomy_ShowReport("instance")
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        CheckInstanceSegment()
    elseif event == "CHAT_MSG_LOOT" then
        OnLootMessage(arg1)
        SyncCounters()
    elseif event == "BAG_UPDATE_DELAYED" then
        -- Re-run pending glows when bags open or contents shift
        ApplyBagGlows()
    end
end)

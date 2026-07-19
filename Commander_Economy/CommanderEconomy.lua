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
local instanceSnap = nil       -- counters snapshotted at instance entry
local lastInstanceReport = nil -- deltas from the most recent completed instance
local session                  -- reload-resilient mirror of all of the above

local function SyncCounters()
    if not session then return end
    session.goldEarned, session.goldSpent = goldEarned, goldSpent
    session.xpGained = xpGained
    session.quests, session.deaths = questsTurnedIn, deaths
    session.lootCount, session.lootRare = lootCount, lootRarePlus
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
local AAR_LINES = 6
local AAR_ICONS = 12

local aar = CreateFrame("Frame", "CommanderEconomyAAR", UIParent, "BackdropTemplate")
aar:SetSize(420, 282)
aar:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
aar:SetFrameStrata("DIALOG")
aar:SetBackdrop({
    bgFile = "Interface\\BankFrame\\Bank-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
})
aar:SetBackdropColor(0.45, 0.45, 0.45, 1)
aar:SetMovable(true)
aar:EnableMouse(true)
aar:RegisterForDrag("LeftButton")
aar:SetScript("OnDragStart", aar.StartMoving)
aar:SetScript("OnDragStop", aar.StopMovingOrSizing)
aar:Hide()
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
    line:SetPoint("TOPLEFT", aar, "TOPLEFT", 26, -62 - (i - 1) * 24)
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

function CommanderEconomy_ShareReport()
    if not aarCurrent then
        print("Commander Economy: open a report first (/ceco aar)")
        return
    end
    local channel = ShareChannel()
    if not channel then
        print("Commander Economy: no group to share the report with")
        return
    end
    local d = aarCurrent.data
    SendChatMessage(string.format("Commander AAR — %s (%s)", aarCurrent.subtitle, d.duration), channel)
    SendChatMessage(string.format("Gold: %s earned, %s spent (net %s)",
        Coins(d.goldEarned), Coins(d.goldSpent), Coins(d.goldEarned - d.goldSpent)), channel)
    local xpText
    if d.elapsed >= 60 and d.xpGained > 0 then
        xpText = string.format("%d (%d/hour)", d.xpGained, math.floor(d.xpGained / (d.elapsed / 3600)))
    else
        xpText = tostring(d.xpGained)
    end
    SendChatMessage(string.format("XP: %s | Quests: %d | Deaths: %d | Loot: %d items (%d uncommon+)",
        xpText, d.quests, d.deaths, d.loot, d.lootRare), channel)
end

local aarShare = CreateFrame("Button", nil, aar, "UIPanelButtonTemplate")
aarShare:SetSize(90, 20)
aarShare:SetPoint("BOTTOMLEFT", aar, "BOTTOMLEFT", 24, 14)
aarShare:SetText("Share")
aarShare:SetScript("OnClick", function()
    CommanderEconomy_ShareReport()
end)

-- Icon strip: the report's spoils, hoverable for full item tooltips
local aarIcons = {}
for i = 1, AAR_ICONS do
    local icon = CreateFrame("Button", nil, aar)
    icon:SetSize(24, 24)
    icon:SetPoint("TOPLEFT", aar, "TOPLEFT", 26 + (i - 1) * 28, -212)
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

local function HideButtonGlow(button)
    if button._commanderEcoGlow then
        button._commanderEcoGlow:Hide()
    end
end

local function ApplyBagGlows()
    -- No empty-set early return: the loop's else-branch is also the
    -- cleanup pass that hides glows which are no longer wanted
    for f = 1, 13 do
        local containerFrame = _G["ContainerFrame" .. f]
        if containerFrame and containerFrame:IsShown() then
            local bagID = containerFrame:GetID()
            for j = 1, containerFrame.size or 0 do
                local button = _G[containerFrame:GetName() .. "Item" .. j]
                if button then
                    local info = C_Container.GetContainerItemInfo(bagID, button:GetID())
                    local wanted = info and info.itemID and glowSet[info.itemID]
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
                        button._commanderEcoGlow:Show()
                        if not button._commanderEcoHooked then
                            button._commanderEcoHooked = true
                            button:HookScript("OnEnter", function(self)
                                local hoveredInfo = C_Container.GetContainerItemInfo(
                                    self:GetParent() and self:GetParent():GetID() or 0, self:GetID())
                                if hoveredInfo and hoveredInfo.itemID then
                                    glowSet[hoveredInfo.itemID] = nil
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
-- open paths themselves (deferred a frame so the container frames exist)
local function DeferredApply()
    C_Timer.After(0, ApplyBagGlows)
end
if hooksecurefunc then
    pcall(hooksecurefunc, "ToggleBag", DeferredApply)
    pcall(hooksecurefunc, "ToggleAllBags", DeferredApply)
    pcall(hooksecurefunc, "OpenAllBags", DeferredApply)
    pcall(hooksecurefunc, "OpenBag", DeferredApply)
end

local aarCurrent   -- what the window is currently showing, for sharing

local function FillReport(subtitle, data)
    aarCurrent = { subtitle = subtitle, data = data }
    aarSubtitle:SetText(subtitle)
    aarLines[1]:SetText(string.format("Gold:  %s earned   %s spent   (net %s)",
        Coins(data.goldEarned), Coins(data.goldSpent), Coins(data.goldEarned - data.goldSpent)))
    if data.elapsed >= 60 and data.xpGained > 0 then
        aarLines[2]:SetText(string.format("Experience:  %d gained  (%d per hour)",
            data.xpGained, math.floor(data.xpGained / (data.elapsed / 3600))))
    else
        aarLines[2]:SetText(string.format("Experience:  %d gained", data.xpGained))
    end
    aarLines[3]:SetText(string.format("Quests turned in:  %d", data.quests))
    aarLines[4]:SetText(string.format("Casualties:  %d", data.deaths))
    aarLines[5]:SetText(string.format("Supplies:  %d item%s looted  (%d uncommon+)",
        data.loot, data.loot == 1 and "" or "s", data.lootRare))
    aarLines[6]:SetText(string.format("Duration:  %s", data.duration))
    FillReportIcons(data.items)
    aar:Show()
    -- Bag glow arms exactly once per report display
    ArmBagGlows(data.items)
end

function CommanderEconomy_ShowReport(kind)
    if not (CommanderEconomyDB and CommanderEconomyDB.EnableEconomy) then
        print("Commander Economy: module is disabled (enable it in settings or /ceco)")
        return
    end
    if kind == "instance" then
        if not lastInstanceReport then
            print("Commander Economy: no completed instance segment this session yet")
            return
        end
        FillReport(lastInstanceReport.name, lastInstanceReport)
        return
    end
    local duration, elapsed = SessionDuration()
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
        duration = duration, elapsed = elapsed,
        items = recent,
    })
end

-- ---------------------------------------------------------------------------
-- Instance segments
-- ---------------------------------------------------------------------------
local function DurationString(elapsed)
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end
    return string.format("%dm", minutes)
end

-- A dungeon run is not over just because the player briefly left the
-- instance: ghost releases, meeting-stone summons, and BG queue pops all
-- exit and return. The segment only finalizes after a grace period spent
-- genuinely outside (or when a different instance begins).
local EXIT_GRACE = 180
local pendingExit = nil   -- { snap, at }

local function FinalizeSegment(snap)
    -- Epoch-based: segment durations stay correct across /reload and even
    -- a full client restart mid-run
    local elapsed = snap.startEpoch and (time() - snap.startEpoch) or (GetTime() - (snap.start or GetTime()))
    -- Items looted during the segment: everything past the entry watermark
    local segmentItems = {}
    for i = (snap.itemWatermark or 0) + 1, #lootedItems do
        segmentItems[#segmentItems + 1] = lootedItems[i]
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
        duration = DurationString(elapsed),
        elapsed = elapsed,
        items = segmentItems,
    }
    if session then session.lastInstanceReport = lastInstanceReport end
    if CommanderEconomyDB.EnableEconomy and CommanderEconomyDB.AutoInstanceReport then
        CommanderEconomy_ShowReport("instance")
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
        elseif delta < 0 then
            goldSpent = goldSpent - delta
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

events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- Resume the session's economics across /reload; only a real
        -- break starts the books over
        local fresh
        session, fresh = Commander.RestoreSession(CommanderEconomyDB, {
            startEpoch = time(),
            goldEarned = 0, goldSpent = 0, xpGained = 0,
            quests = 0, deaths = 0, lootCount = 0, lootRare = 0,
            lootedItems = {},
            lastInstanceReport = false, instanceSnap = false, pendingExit = false,
        })
        if fresh then
            session.startEpoch = time()
        end
        goldEarned, goldSpent = session.goldEarned, session.goldSpent
        xpGained = session.xpGained
        questsTurnedIn, deaths = session.quests, session.deaths
        lootCount, lootRarePlus = session.lootCount, session.lootRare
        lootedItems = session.lootedItems
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

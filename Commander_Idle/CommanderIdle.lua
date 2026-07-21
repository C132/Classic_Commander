-- Commander Idle: the RTS idle-worker alert. When the character has been
-- completely inactive (not moving, not in combat, not casting, not dead)
-- for the configured time, a pulsing pocket-watch button appears in the
-- lower-left corner — click it to open the quest log ("check your orders").
-- Any activity hides it instantly.

local CHECK_INTERVAL = 1

local button = CreateFrame("Button", "CommanderIdleButton", UIParent)
button:SetSize(44, 44)
button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 16, 180)
button:SetFrameStrata("HIGH")
button:Hide()

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")

local ringHighlight = button:CreateTexture(nil, "OVERLAY")
ringHighlight:SetPoint("TOPLEFT", -6, 6)
ringHighlight:SetPoint("BOTTOMRIGHT", 6, -6)
ringHighlight:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Expand")
ringHighlight:SetVertexColor(1, 0.85, 0.2, 0.9)

button:SetScript("OnClick", function()
    button:Hide()
    ToggleQuestLog()
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Idle", 1, 1, 1)
    GameTooltip:AddLine("Your character is standing around. Click to review your orders (quest log).", nil, nil, nil, true)
    -- A line of class flavor from the shared identity layer, in class color
    local info = Commander.GetClassInfo and Commander.GetClassInfo()
    if info and info.line then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(info.line, info.color[1], info.color[2], info.color[3], true)
    end
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Gentle pulse while shown
local pulseTime = 0
button:SetScript("OnUpdate", function(self, elapsed)
    pulseTime = pulseTime + elapsed
    local pulse = 0.65 + 0.35 * math.abs(math.sin(pulseTime * 2))
    ringHighlight:SetAlpha(pulse)
end)

local idleSince
local alerted = false

-- Standing at a vendor, mailbox, auctioneer, quest giver, bank, trainer, or
-- flight master is work, not idling — suppress while any of these are open
-- (AuctionFrame is load-on-demand, hence the nil guards)
local INTERACTION_FRAMES = {
    "MerchantFrame", "MailFrame", "AuctionFrame", "TradeFrame",
    "GossipFrame", "QuestFrame", "BankFrame", "TaxiFrame",
    "ClassTrainerFrame", "CraftFrame", "TradeSkillFrame",
}

local function IsInteracting()
    for _, name in ipairs(INTERACTION_FRAMES) do
        local interactionFrame = _G[name]
        if interactionFrame and interactionFrame.IsShown and interactionFrame:IsShown() then
            return true
        end
    end
    return false
end

local function IsIdleNow()
    if UnitAffectingCombat("player") then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    if (GetUnitSpeed("player") or 0) > 0 then return false end
    if IsInteracting() then return false end
    if IsResting() and not CommanderIdleDB.IdleWhileResting then return false end
    return true
end

local function HideAlert()
    if alerted then
        alerted = false
        button:Hide()
    end
end

-- Opt-in class flavor: one short class-appropriate emote when the alert first
-- appears (default off; it is a visible /emote). Idle alerts only fire out of
-- combat, so DoEmote is always safe here; pcall guards an unknown token.
local function IdleEmote()
    if not (CommanderIdleDB and CommanderIdleDB.RPEmote) then return end
    if not (Commander.GetClassInfo and DoEmote) then return end
    local info = Commander.GetClassInfo()
    if info and info.emote then
        pcall(DoEmote, info.emote)
    end
end

local ticker

local function Check()
    if not CommanderIdleDB.EnableIdle then
        HideAlert()
        return
    end
    if IsIdleNow() then
        idleSince = idleSince or GetTime()
        if not alerted and (GetTime() - idleSince) >= (CommanderIdleDB.IdleSeconds or 30) then
            alerted = true
            pulseTime = 0
            button:Show()
            if CommanderIdleDB.IdleSound then
                PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
            end
            IdleEmote()
        end
    else
        idleSince = nil
        HideAlert()
    end
end

-- Standard suite tester: show the alert immediately. Real activity (or
-- the click itself) dismisses it exactly like a genuine idle alert.
function CommanderIdle_Test()
    if not (CommanderIdleDB and CommanderIdleDB.EnableIdle) then
        print("Commander Idle: module is disabled (enable it in settings or /cidle)")
        return
    end
    alerted = true
    pulseTime = 0
    button:Show()
    if CommanderIdleDB.IdleSound then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
    IdleEmote()
    print("Commander Idle: test alert — click the pocket watch or start moving to dismiss")
end

local function ApplyEnabled()
    if CommanderIdleDB.EnableIdle then
        if not ticker then
            ticker = C_Timer.NewTicker(CHECK_INTERVAL, Check)
        end
    else
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        idleSince = nil
        HideAlert()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_IDLE_EVENTS.UPDATE, ApplyEnabled)
        ApplyEnabled()
    end
end)

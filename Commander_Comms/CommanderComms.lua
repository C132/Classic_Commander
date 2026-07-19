-- Commander Comms: a radial wheel of eight quick battle calls. Opened by
-- keybind (Bindings.xml), slash, or the settings button; each call routes
-- to the widest channel that fits the group (raid > party > say). Clicking
-- a call sends and closes; Escape or a second toggle also closes.

BINDING_HEADER_COMMANDERCOMMS = "Commander Comms"
BINDING_NAME_COMMANDERCOMMS_TOGGLE = "Open Comms Wheel"

local RADIUS = 110

local CALLS = {
    { label = "On My Way", msg = "On my way." },
    { label = "Attack", msg = "Attack my target!", targetMsg = "Attack %s!" },
    { label = "Need Healing", msg = "I need healing!" },
    { label = "Fall Back", msg = "Fall back and regroup!" },
    { label = "Incoming", msg = "Incoming enemies - get ready!" },
    { label = "Out of Mana", msg = "I'm out of mana." },
    { label = "Ready", msg = "Ready to go." },
    { label = "Help", msg = "Help me!", targetMsg = "Help me with %s!" },
}

local function PickChannel()
    -- Battlegrounds and arenas are instance-category groups on this
    -- engine: IsInRaid() is true in a BG but "RAID" fails there — the
    -- instance group speaks INSTANCE_CHAT
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return "SAY"
end

local function ClickSound()
    if CommanderCommsDB.CommsSound then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
end

local wheel = CreateFrame("Frame", "CommanderCommsWheel", UIParent)
wheel:SetPoint("CENTER")
wheel:SetSize((RADIUS + 60) * 2, (RADIUS + 30) * 2)
wheel:SetFrameStrata("DIALOG")
-- Swallow clicks between the buttons: a miss must not fall through to the
-- world and retarget right before a targeted call
wheel:EnableMouse(true)
wheel:Hide()
if UISpecialFrames then
    table.insert(UISpecialFrames, "CommanderCommsWheel")
end

local center = wheel:CreateFontString(nil, "OVERLAY")
center:SetFontObject(GameFontNormalLarge)
center:SetPoint("CENTER")
center:SetText("COMMS")
center:SetTextColor(0.3, 1, 0.4)

local function SendCall(call)
    local message = call.msg
    if call.targetMsg and CommanderCommsDB.IncludeTarget and UnitExists("target") then
        local targetName = UnitName("target")
        if targetName then
            message = string.format(call.targetMsg, targetName)
        end
    end
    SendChatMessage(message, PickChannel())
    ClickSound()
    wheel:Hide()
end

for i, call in ipairs(CALLS) do
    local button = CreateFrame("Button", nil, wheel, "UIPanelButtonTemplate")
    button:SetSize(110, 24)
    button:SetText(call.label)
    -- Slot 1 at the top, remaining calls clockwise at 45-degree steps
    local angle = math.rad(90 - (i - 1) * 45)
    button:SetPoint("CENTER", wheel, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
    button:SetScript("OnClick", function() SendCall(call) end)
end

function CommanderComms_Toggle()
    if not (CommanderCommsDB and CommanderCommsDB.EnableComms) then
        print("Commander Comms: module is disabled (enable it in settings or /ccomms)")
        return
    end
    if wheel:IsShown() then
        wheel:Hide()
    else
        wheel:Show()
        ClickSound()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    Commander.AddListener(COMMANDER_COMMS_EVENTS.UPDATE, function()
        if not CommanderCommsDB.EnableComms then
            wheel:Hide()
        end
    end)
end)

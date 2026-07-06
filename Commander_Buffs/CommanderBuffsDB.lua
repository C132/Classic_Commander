CommanderBuffsDB = _G.CommanderBuffsDB or {}

COMMANDER_BUFFS_EVENTS = {
    UPDATE = "COMMANDER_BUFFS_UPDATE"
}

local DefaultSettings = {
    BuffScale = 1.0,
    LockBuffFrames = true,
    BuffFramePoint = "TOPRIGHT",
    BuffFrameX = -205,
    BuffFrameY = -13,
    ShowAnchorInCombat = false,
    BuffsPerRow = 8,
}

-- Ensure all settings exist with valid values
-- (must run at ADDON_LOADED - SavedVariables replace the global after this file executes)
local function ApplyDefaults()
    for key, value in pairs(DefaultSettings) do
        if CommanderBuffsDB[key] == nil or
           (key == "BuffFramePoint" and type(CommanderBuffsDB[key]) ~= "string") then
            CommanderBuffsDB[key] = value
        end
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    for key, value in pairs(DefaultSettings) do
        CommanderBuffsDB[key] = value
    end
    Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
    print("Commander Buffs: settings restored to defaults")
end

local function ResetPosition()
    CommanderBuffsDB.BuffFramePoint = DefaultSettings.BuffFramePoint
    CommanderBuffsDB.BuffFrameX = DefaultSettings.BuffFrameX
    CommanderBuffsDB.BuffFrameY = DefaultSettings.BuffFrameY
    Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Buffs",
        title = "Buffs",
        addonName = "Commander_Buffs",
        description = "Makes the buff display movable and adjustable: drag it anywhere with the unlock anchor, scale it, and choose how many buffs sit on each row.",
        event = COMMANDER_BUFFS_EVENTS.UPDATE,
        slash = { "/cbuff" },
        slashHandlers = {
            reset = Reset,
        },
    })

    panel:AddSection("Position")
    panel:AddCheckbox({
        label = "Lock Buff Frame",
        tooltip = "Hide the drag anchor and keep the buff frame fixed in place. Uncheck to show a drag handle above the buffs.",
        get = function() return CommanderBuffsDB.LockBuffFrames end,
        set = function(value) CommanderBuffsDB.LockBuffFrames = value end,
    })
    panel:AddCheckbox({
        label = "Show Anchor in Combat",
        tooltip = "Keep the drag anchor visible during combat while the frame is unlocked. Normally the anchor hides itself when a fight starts.",
        get = function() return CommanderBuffsDB.ShowAnchorInCombat end,
        set = function(value) CommanderBuffsDB.ShowAnchorInCombat = value end,
        isEnabled = function() return not CommanderBuffsDB.LockBuffFrames end,
    })
    panel:AddButtonRow({
        {
            label = "Reset Position",
            tooltip = "Move the buff frame back to its default spot near the minimap.",
            onClick = ResetPosition,
        },
    })

    panel:AddSection("Layout")
    panel:AddSlider({
        label = "Buff Frame Scale",
        tooltip = "Overall size of the buff display.",
        min = 0.5, max = 2.0, step = 0.05,
        format = function(value) return string.format("%d%%", value * 100 + 0.5) end,
        get = function() return CommanderBuffsDB.BuffScale end,
        set = function(value) CommanderBuffsDB.BuffScale = value end,
    })
    panel:AddSlider({
        label = "Buffs Per Row",
        tooltip = "How many buff icons are placed on each row before wrapping to the next.",
        min = 4, max = 16, step = 1,
        format = "%d",
        get = function() return CommanderBuffsDB.BuffsPerRow end,
        set = function(value) CommanderBuffsDB.BuffsPerRow = value end,
    })

    local category = panel:Finalize({ onDefaults = Reset })
    -- Shared with CommanderBuffs.lua for the anchor's settings button
    CommanderBuffsCategoryID = category:GetID()
end

local function OnAwake()
    CreateOptionsPanel()
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Buffs" then
        ApplyDefaults()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)

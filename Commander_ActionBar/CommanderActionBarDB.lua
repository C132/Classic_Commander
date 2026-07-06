CommanderActionBarDB = _G.CommanderActionBarDB or {}

COMMANDER_ACTIONBAR_EVENTS = {
    UPDATE = "COMMANDER_ACTIONBAR_UPDATE"
}

local DefaultSettings = {
    locked = true,
    showBagButtons = true,
    position = {
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 0,
        yOfs = 0
    }
}

local function DefaultPosition()
    local p = DefaultSettings.position
    return { point = p.point, relativePoint = p.relativePoint, xOfs = p.xOfs, yOfs = p.yOfs }
end

local function ApplyDefaultSettings()
    for key, value in pairs(DefaultSettings) do
        if CommanderActionBarDB[key] == nil then
            if key == "position" then
                CommanderActionBarDB[key] = DefaultPosition()
            else
                CommanderActionBarDB[key] = value
            end
        end
    end
end

ApplyDefaultSettings()

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
local loaded = false

local function Reset()
    CommanderActionBarDB.locked = DefaultSettings.locked
    CommanderActionBarDB.showBagButtons = DefaultSettings.showBagButtons
    CommanderActionBarDB.position = DefaultPosition()
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: settings restored to defaults")
end

local function ResetPosition()
    CommanderActionBarDB.position = DefaultPosition()
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
end

local function SetLocked(locked)
    CommanderActionBarDB.locked = locked
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar " .. (locked and "locked" or "unlocked"))
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBar",
        title = "Action Bar",
        addonName = "Commander_ActionBar",
        description = "Replaces the default action bars with a compact, movable RTS-style command card and repositions the bag buttons.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
        slash = { "/cab" },
        slashHandlers = {
            reset = Reset,
            lock = function() SetLocked(true) end,
            unlock = function() SetLocked(false) end,
        },
    })

    panel:AddSection("Action Bar")
    panel:AddCheckbox({
        label = "Lock Action Bar",
        tooltip = "Prevent the command card from being dragged. Uncheck to move it, then lock it again to avoid accidental drags.",
        get = function() return CommanderActionBarDB.locked end,
        set = function(value) CommanderActionBarDB.locked = value end,
    })
    panel:AddButtonRow({
        {
            label = "Reset Position",
            tooltip = "Move the command card back to the center of the screen.",
            onClick = ResetPosition,
        },
    })

    panel:AddSection("Bag Buttons")
    panel:AddCheckbox({
        label = "Show Bag Buttons",
        tooltip = "Show the four bag slot buttons in the bottom-right corner of the screen.",
        get = function() return CommanderActionBarDB.showBagButtons end,
        set = function(value) CommanderActionBarDB.showBagButtons = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

-- Set when a bag button update is skipped due to combat lockdown; applied on
-- PLAYER_REGEN_ENABLED
local pendingBagButtonUpdate = false

local function ApplyBagButtonVisibility()
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:SetShown(CommanderActionBarDB.showBagButtons)
        end
    end
end

local function OnUpdate()
    -- CharacterBag0-3Slot are protected; SetShown on them during combat
    -- lockdown trips ADDON_ACTION_BLOCKED, so defer until combat ends
    if InCombatLockdown() then
        pendingBagButtonUpdate = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ApplyBagButtonVisibility()
    end
end

local function OnAwake()
    CreateOptionsPanel()
    Commander.AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnUpdate)
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so re-apply defaults here
        if addonName == "Commander_ActionBar" then
            CommanderActionBarDB = CommanderActionBarDB or {}
            ApplyDefaultSettings()
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingBagButtonUpdate then
            pendingBagButtonUpdate = false
            ApplyBagButtonVisibility()
        end
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)

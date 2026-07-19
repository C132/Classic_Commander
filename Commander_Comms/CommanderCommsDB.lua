CommanderCommsDB = _G.CommanderCommsDB or {}

COMMANDER_COMMS_EVENTS = {
    UPDATE = "COMMANDER_COMMS_UPDATE"
}

local DefaultSettings = {
    EnableComms = true,
    IncludeTarget = true,
    CommsSound = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderCommsDB, DefaultSettings)
    Commander.Notify(COMMANDER_COMMS_EVENTS.UPDATE)
    print("Commander Comms: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Comms",
        title = "Comms",
        addonName = "Commander_Comms",
        description = "Battle comms on a radial wheel, like pinging in an RTS or MOBA. One keybind opens eight quick calls — on my way, need healing, attack, fall back — sent to raid, party, or say automatically depending on your group. Bind the wheel under Key Bindings > AddOns > Commander Comms.",
        event = COMMANDER_COMMS_EVENTS.UPDATE,
        slash = { "/ccomms" },
        slashHandlers = {
            toggle = function()
                if CommanderComms_Toggle then CommanderComms_Toggle() end
            end,
        },
    })

    panel:AddSection("Comms Wheel")
    panel:AddCheckbox({
        label = "Enable Comms",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderCommsDB.EnableComms end,
        set = function(value) CommanderCommsDB.EnableComms = value end,
    })
    panel:AddCheckbox({
        label = "Include Target Names",
        tooltip = "Calls like Attack and Focus name your current target when you have one.",
        get = function() return CommanderCommsDB.IncludeTarget end,
        set = function(value) CommanderCommsDB.IncludeTarget = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddCheckbox({
        label = "Comms Sound",
        tooltip = "Play a click when the wheel opens and when a call is sent.",
        get = function() return CommanderCommsDB.CommsSound end,
        set = function(value) CommanderCommsDB.CommsSound = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddButtonRow({
        {
            label = "Open Wheel",
            width = 120,
            tooltip = "Preview the comms wheel (also: /ccomms toggle, or the keybind).",
            onClick = function()
                if CommanderComms_Toggle then CommanderComms_Toggle() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Comms" then
        Commander.UI.ApplyDefaults(CommanderCommsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

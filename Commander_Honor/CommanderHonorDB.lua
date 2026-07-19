CommanderHonorDB = _G.CommanderHonorDB or {}

COMMANDER_HONOR_EVENTS = {
    UPDATE = "COMMANDER_HONOR_UPDATE"
}

local DefaultSettings = {
    EnableHonor = true,
    HonorFlash = true,
    HonorText = true,
    HonorSound = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderHonorDB, DefaultSettings)
    Commander.Notify(COMMANDER_HONOR_EVENTS.UPDATE)
    print("Commander Honor: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Honor",
        title = "Honor",
        addonName = "Commander_Honor",
        description = "PvP kills with the weight they deserve. Every honorable kill flashes the screen crimson with an HONORABLE KILL callout, and the session tally keeps score of kills and estimated honor — your personal war record, one battle at a time.",
        event = COMMANDER_HONOR_EVENTS.UPDATE,
        slash = { "/chonor" },
        slashHandlers = {
            report = function()
                if CommanderHonor_Report then CommanderHonor_Report() end
            end,
            test = function()
                if CommanderHonor_Test then CommanderHonor_Test() end
            end,
        },
    })

    panel:AddSection("War Record")
    panel:AddCheckbox({
        label = "Enable Honor",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderHonorDB.EnableHonor end,
        set = function(value) CommanderHonorDB.EnableHonor = value end,
    })
    panel:AddCheckboxPair({
        label = "Honor Flash",
        tooltip = "Crimson screen-edge flash on each honorable kill.",
        get = function() return CommanderHonorDB.HonorFlash end,
        set = function(value) CommanderHonorDB.HonorFlash = value end,
        isEnabled = function() return CommanderHonorDB.EnableHonor end,
    }, {
        label = "HONORABLE KILL Text",
        tooltip = "Floating callout naming the fallen enemy.",
        get = function() return CommanderHonorDB.HonorText end,
        set = function(value) CommanderHonorDB.HonorText = value end,
        isEnabled = function() return CommanderHonorDB.EnableHonor end,
    })
    panel:AddCheckbox({
        label = "Honor Sound",
        tooltip = "Play a chime with each honorable kill.",
        get = function() return CommanderHonorDB.HonorSound end,
        set = function(value) CommanderHonorDB.HonorSound = value end,
        isEnabled = function() return CommanderHonorDB.EnableHonor end,
    })
    panel:AddButtonRow({
        {
            label = "War Record",
            width = 120,
            tooltip = "Print this session's honorable kills and estimated honor (also: /chonor report).",
            onClick = function()
                if CommanderHonor_Report then CommanderHonor_Report() end
            end,
        },
        {
            label = "Test",
            width = 90,
            tooltip = "Preview the honorable-kill feedback (also: /chonor test).",
            onClick = function()
                if CommanderHonor_Test then CommanderHonor_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Honor" then
        Commander.UI.ApplyDefaults(CommanderHonorDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

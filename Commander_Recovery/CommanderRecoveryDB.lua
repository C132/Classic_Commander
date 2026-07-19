CommanderRecoveryDB = _G.CommanderRecoveryDB or {}

COMMANDER_RECOVERY_EVENTS = {
    UPDATE = "COMMANDER_RECOVERY_UPDATE"
}

local DefaultSettings = {
    EnableRecovery = true,
    DeathReport = true,
    CorpseOrder = true,
    RecoverySound = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderRecoveryDB, DefaultSettings)
    Commander.Notify(COMMANDER_RECOVERY_EVENTS.UPDATE)
    print("Commander Recovery: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Recovery",
        title = "Recovery",
        addonName = "Commander_Recovery",
        description = "Casualty response, RTS style. When your unit falls, Recovery logs where and when, keeps a session casualty count, and — with Commander Orders installed — issues an automatic move order pointing your ghost back at its corpse.",
        event = COMMANDER_RECOVERY_EVENTS.UPDATE,
        slash = { "/crec" },
        slashHandlers = {
            report = function()
                if CommanderRecovery_Report then CommanderRecovery_Report() end
            end,
        },
    })

    panel:AddSection("Casualty Response")
    panel:AddCheckbox({
        label = "Enable Recovery",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderRecoveryDB.EnableRecovery end,
        set = function(value) CommanderRecoveryDB.EnableRecovery = value end,
    })
    panel:AddCheckbox({
        label = "Death Report",
        tooltip = "Print a short casualty report in chat when you die: location and session death count.",
        get = function() return CommanderRecoveryDB.DeathReport end,
        set = function(value) CommanderRecoveryDB.DeathReport = value end,
        isEnabled = function() return CommanderRecoveryDB.EnableRecovery end,
    })
    panel:AddCheckbox({
        label = "Corpse Run Order",
        tooltip = "When you release your spirit, automatically issue a Commander Orders move order at your corpse. Requires the Commander Orders addon.",
        get = function() return CommanderRecoveryDB.CorpseOrder end,
        set = function(value) CommanderRecoveryDB.CorpseOrder = value end,
        isEnabled = function()
            return CommanderRecoveryDB.EnableRecovery and CommanderOrders_IssueOrder ~= nil
        end,
    })
    panel:AddCheckbox({
        label = "Recovery Sound",
        tooltip = "Play a short confirmation when your unit is recovered (back to life).",
        get = function() return CommanderRecoveryDB.RecoverySound end,
        set = function(value) CommanderRecoveryDB.RecoverySound = value end,
        isEnabled = function() return CommanderRecoveryDB.EnableRecovery end,
    })
    panel:AddButtonRow({
        {
            label = "Casualty Report",
            width = 140,
            tooltip = "Print this session's casualty report in chat (also: /crec report).",
            onClick = function()
                if CommanderRecovery_Report then CommanderRecovery_Report() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Recovery" then
        Commander.UI.ApplyDefaults(CommanderRecoveryDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

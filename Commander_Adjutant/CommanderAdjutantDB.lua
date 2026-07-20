CommanderAdjutantDB = _G.CommanderAdjutantDB or {}

COMMANDER_ADJUTANT_EVENTS = {
    UPDATE = "COMMANDER_ADJUTANT_UPDATE"
}

local DefaultSettings = {
    EnableAdjutant = true,
    PlaySounds = true,
    AlertUnderAttack = true,
    AlertLowHealth = true,
    AlertRepair = true,
    AlertBagsFull = true,
    AlertLevelUp = true,
    AlertReinforcements = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderAdjutantDB, DefaultSettings)
    Commander.Notify(COMMANDER_ADJUTANT_EVENTS.UPDATE)
    print("Commander Adjutant: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Adjutant",
        title = "Adjutant",
        addonName = "Commander_Adjutant",
        description = "Your personal battle adjutant, RTS-style: dramatic on-screen banners and alert sounds when your forces come under attack, take critical damage, need repairs, run out of storage, finish an upgrade, or receive reinforcements.",
        event = COMMANDER_ADJUTANT_EVENTS.UPDATE,
        slash = { "/cadj" },
        slashHandlers = {
            test = function()
                if CommanderAdjutant_TestAlert then
                    CommanderAdjutant_TestAlert()
                end
            end,
        },
    })

    panel:AddSection("Adjutant", "The master switch; turn it off and the announcer stands down entirely.")
    panel:AddCheckbox({
        label = "Enable Adjutant",
        tooltip = "Enable the announcer. Individual alerts can be tuned below.",
        get = function() return CommanderAdjutantDB.EnableAdjutant end,
        set = function(value) CommanderAdjutantDB.EnableAdjutant = value end,
    })
    panel:AddCheckbox({
        label = "Play Alert Sounds",
        tooltip = "Play a sound with each banner. Uncheck for silent, banner-only alerts.",
        get = function() return CommanderAdjutantDB.PlaySounds end,
        set = function(value) CommanderAdjutantDB.PlaySounds = value end,
        isEnabled = function() return CommanderAdjutantDB.EnableAdjutant end,
    })

    panel:AddSection("Alerts", "Use /cadj test to preview the banner.")
    local function AlertCheckbox(key, label, tooltip)
        panel:AddCheckbox({
            label = label,
            tooltip = tooltip,
            get = function() return CommanderAdjutantDB[key] end,
            set = function(value) CommanderAdjutantDB[key] = value end,
            isEnabled = function() return CommanderAdjutantDB.EnableAdjutant end,
        })
    end
    AlertCheckbox("AlertUnderAttack", "Under Attack", "\"Our forces are under attack!\" when combat begins after a stretch of peace.")
    AlertCheckbox("AlertLowHealth", "Critical Damage", "\"We're taking critical damage!\" when your health drops below 25% (once per fight).")
    AlertCheckbox("AlertRepair", "Units Require Repair", "When your lowest equipment durability falls below 20%.")
    AlertCheckbox("AlertBagsFull", "Storage at Capacity", "When your bags run completely out of free slots.")
    AlertCheckbox("AlertLevelUp", "Upgrade Complete", "When you level up.")
    AlertCheckbox("AlertReinforcements", "Reinforcements", "When players join your party or raid.")

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Adjutant" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        Commander.UI.ApplyDefaults(CommanderAdjutantDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

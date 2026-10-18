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
    RepairWaypoint = true,      -- the repair alert marks the nearest known vendor (Logistics + Orders)
    AlertBagsFull = true,
    VendorWaypoint = true,      -- the full-bags alert marks the nearest vendor (Logistics + Orders)
    AlertLevelUp = true,
    AlertReinforcements = true,
    AlertQueuePop = true,
    -- Deployment countdown
    ShowQueueTimer = true,
    KeepQueueTimer = true,
    QueueTimerWarning = 10,
}
for key, value in pairs(Commander.UI.HudChromeDefaults("QueueTimer", "DARK")) do
    DefaultSettings[key] = value
end

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
        description = "Your personal battle adjutant, RTS-style: dramatic on-screen banners and alert sounds when your forces come under attack, take critical damage, need repairs, run out of storage, finish an upgrade, or receive reinforcements — plus a countdown on the battleground invite, so you know exactly how long you can keep doing what you were doing before the port expires.",
        event = COMMANDER_ADJUTANT_EVENTS.UPDATE,
        slash = { "/cadj" },
        slashHandlers = {
            test = function()
                if CommanderAdjutant_TestAlert then
                    CommanderAdjutant_TestAlert()
                end
            end,
            timer = function()
                if CommanderAdjutant_TestQueueTimer then
                    CommanderAdjutant_TestQueueTimer()
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
    -- Two to a row: the alert list has outgrown a single column
    local function Alert(key, label, tooltip)
        return {
            label = label,
            tooltip = tooltip,
            get = function() return CommanderAdjutantDB[key] end,
            set = function(value) CommanderAdjutantDB[key] = value end,
            isEnabled = function() return CommanderAdjutantDB.EnableAdjutant end,
        }
    end
    panel:AddCheckboxPair(
        Alert("AlertUnderAttack", "Under Attack", "\"Our forces are under attack!\" when combat begins after a stretch of peace."),
        Alert("AlertLowHealth", "Critical Damage", "\"We're taking critical damage!\" when your health drops below 25% (once per fight)."))
    panel:AddCheckboxPair(
        Alert("AlertRepair", "Units Require Repair", "When your lowest equipment durability falls below 20%."),
        Alert("AlertBagsFull", "Storage at Capacity", "When your bags run completely out of free slots."))
    panel:AddCheckboxPair(
        Alert("AlertLevelUp", "Upgrade Complete", "When you level up."),
        Alert("AlertReinforcements", "Reinforcements", "When players join your party or raid."))
    panel:AddCheckboxPair(
        Alert("AlertQueuePop", "Transport Ready", "When a battleground or arena invite arrives. No sound of its own: the client already plays one for the invite."))
    panel:AddCheckbox({
        label = "Mark the Nearest Repair",
        tooltip = "With Commander Logistics remembering the repair vendors you open, the repair alert names the nearest one on your continent and marks it with a Commander Orders waypoint. The mark never takes the arrow from a waypoint or route you are following, or after you cleared the arrow: the arrow points at it only when Commander Orders' Follow the Closest has nothing of yours left on this continent. It waits for combat to end, and is taken down once your gear is mended.",
        get = function() return CommanderAdjutantDB.RepairWaypoint end,
        set = function(value) CommanderAdjutantDB.RepairWaypoint = value end,
        isEnabled = function() return CommanderAdjutantDB.EnableAdjutant and CommanderAdjutantDB.AlertRepair end,
    })
    panel:AddCheckbox({
        label = "Mark the Nearest Vendor",
        tooltip = "When your bags fill up, the alert names the nearest vendor on your continent (the repair vendors Commander Logistics remembers, and with Questie every vendor it knows) and marks it with a Commander Orders waypoint, the same quiet offer as the repair mark: it never takes the arrow from what you are following, waits for combat to end, and is taken down by the first merchant you open or the first free bag slot.",
        get = function() return CommanderAdjutantDB.VendorWaypoint end,
        set = function(value) CommanderAdjutantDB.VendorWaypoint = value end,
        isEnabled = function() return CommanderAdjutantDB.EnableAdjutant and CommanderAdjutantDB.AlertBagsFull end,
    })

    panel:AddSection("Deployment Countdown",
        "The battleground invite never says how long the port stays open. This puts the clock on it. Use /cadj timer for a 20-second demo.")
    local function TimerEnabled()
        return CommanderAdjutantDB.EnableAdjutant and CommanderAdjutantDB.ShowQueueTimer
    end
    panel:AddCheckboxPair({
        label = "Countdown on the Invite",
        tooltip = "Draw a draining countdown bar under the battleground invite window.",
        get = function() return CommanderAdjutantDB.ShowQueueTimer end,
        set = function(value) CommanderAdjutantDB.ShowQueueTimer = value end,
        isEnabled = function() return CommanderAdjutantDB.EnableAdjutant end,
    }, {
        label = "Keep It After Hiding",
        tooltip = "Press Hide on the invite and the countdown stays on screen on its own, click-to-enter, until the port expires. Drag it anywhere with the frame options below.",
        get = function() return CommanderAdjutantDB.KeepQueueTimer end,
        set = function(value) CommanderAdjutantDB.KeepQueueTimer = value end,
        isEnabled = TimerEnabled,
    })
    panel:AddSlider({
        label = "Closing Warning",
        tooltip = "Banner and alert sound when the port is about to expire. Set to Off for a silent countdown.",
        min = 0, max = 30, step = 5,
        format = function(value)
            if value <= 0 then return "Off" end
            return string.format("%ds", value)
        end,
        get = function() return CommanderAdjutantDB.QueueTimerWarning end,
        set = function(value) CommanderAdjutantDB.QueueTimerWarning = value end,
        isEnabled = TimerEnabled,
    })
    Commander.UI.AddHudChromeOptions(panel, CommanderAdjutantDB, "QueueTimer", {
        isEnabled = function() return TimerEnabled() and CommanderAdjutantDB.KeepQueueTimer end,
        onChanged = function() Commander.Notify(COMMANDER_ADJUTANT_EVENTS.UPDATE) end,
    })

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

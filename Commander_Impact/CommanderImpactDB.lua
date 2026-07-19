CommanderImpactDB = _G.CommanderImpactDB or {}

COMMANDER_IMPACT_EVENTS = {
    UPDATE = "COMMANDER_IMPACT_UPDATE"
}

local DefaultSettings = {
    EnableImpact = true,
    KillFlash = true,
    KillText = true,
    KillSound = false,
    CritFlash = true,
    CritThreshold = 400,
    FlashIntensity = 0.4,
    FlashDuration = 1.0,
    HonorKills = true,
    HonorFlash = true,
    HonorText = true,
    HonorSound = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderImpactDB, DefaultSettings)
    Commander.Notify(COMMANDER_IMPACT_EVENTS.UPDATE)
    print("Commander Impact: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Impact",
        title = "Impact",
        addonName = "Commander_Impact",
        description = "Makes your blows land on the screen, not just the target. Killing blows pulse the screen edge gold with a TARGET ELIMINATED callout; crits past your threshold slam a red-orange pulse scaled to the damage; honorable kills flash crimson and feed a session war record. The same full-screen language as Commander Casting's glow, spent on payoff instead of buildup.",
        event = COMMANDER_IMPACT_EVENTS.UPDATE,
        slash = { "/cimpact" },
        slashHandlers = {
            test = function()
                if CommanderImpact_Test then CommanderImpact_Test() end
            end,
            testhonor = function()
                if CommanderImpact_TestHonor then CommanderImpact_TestHonor() end
            end,
            report = function()
                if CommanderImpact_WarRecord then CommanderImpact_WarRecord() end
            end,
        },
    })

    panel:AddSection("Kill Confirmation")
    panel:AddCheckbox({
        label = "Enable Impact",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderImpactDB.EnableImpact end,
        set = function(value) CommanderImpactDB.EnableImpact = value end,
    })
    panel:AddCheckboxPair({
        label = "Kill Flash",
        tooltip = "Gold screen-edge pulse on your killing blows.",
        get = function() return CommanderImpactDB.KillFlash end,
        set = function(value) CommanderImpactDB.KillFlash = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    }, {
        label = "TARGET ELIMINATED",
        tooltip = "Floating confirmation text on your killing blows.",
        get = function() return CommanderImpactDB.KillText end,
        set = function(value) CommanderImpactDB.KillText = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    })
    panel:AddCheckboxPair({
        label = "Kill Sound",
        tooltip = "Play a confirmation chime with each killing blow.",
        get = function() return CommanderImpactDB.KillSound end,
        set = function(value) CommanderImpactDB.KillSound = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    }, {
        label = "Crit Flash",
        tooltip = "Red-orange edge pulse when one of your hits crits past the threshold, scaled to the damage.",
        get = function() return CommanderImpactDB.CritFlash end,
        set = function(value) CommanderImpactDB.CritFlash = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    })
    panel:AddSliderPair({
        label = "Crit Threshold",
        tooltip = "Minimum critical damage before the crit flash fires — set it around your 'that felt good' number.",
        min = 100, max = 2000, step = 50,
        format = "%.0f damage",
        get = function() return CommanderImpactDB.CritThreshold end,
        set = function(value) CommanderImpactDB.CritThreshold = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact and CommanderImpactDB.CritFlash end,
    }, {
        label = "Flash Intensity",
        tooltip = "Maximum brightness of the edge pulses.",
        min = 0.1, max = 0.8, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderImpactDB.FlashIntensity end,
        set = function(value) CommanderImpactDB.FlashIntensity = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    })
    panel:AddSlider({
        label = "Flash Duration",
        tooltip = "How long each pulse lingers before fading out completely.",
        min = 0.3, max = 3.0, step = 0.1,
        format = "%.1fs",
        get = function() return CommanderImpactDB.FlashDuration end,
        set = function(value) CommanderImpactDB.FlashDuration = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    })
    panel:AddSection("War Record (PvP)")
    panel:AddCheckboxPair({
        label = "Honorable Kills",
        tooltip = "Honorable-kill feedback: every HK celebrated on screen, with a running session tally of kills and estimated honor — your personal war record.",
        get = function() return CommanderImpactDB.HonorKills end,
        set = function(value) CommanderImpactDB.HonorKills = value end,
        isEnabled = function() return CommanderImpactDB.EnableImpact end,
    }, {
        label = "Honor Sound",
        tooltip = "Play a chime with each honorable kill.",
        get = function() return CommanderImpactDB.HonorSound end,
        set = function(value) CommanderImpactDB.HonorSound = value end,
        isEnabled = function()
            return CommanderImpactDB.EnableImpact and CommanderImpactDB.HonorKills
        end,
    })
    panel:AddCheckboxPair({
        label = "Honor Flash",
        tooltip = "Crimson screen-edge flash on each honorable kill.",
        get = function() return CommanderImpactDB.HonorFlash end,
        set = function(value) CommanderImpactDB.HonorFlash = value end,
        isEnabled = function()
            return CommanderImpactDB.EnableImpact and CommanderImpactDB.HonorKills
        end,
    }, {
        label = "HONORABLE KILL Text",
        tooltip = "Floating callout naming the fallen enemy.",
        get = function() return CommanderImpactDB.HonorText end,
        set = function(value) CommanderImpactDB.HonorText = value end,
        isEnabled = function()
            return CommanderImpactDB.EnableImpact and CommanderImpactDB.HonorKills
        end,
    })
    panel:AddButtonRow({
        {
            label = "Test Impact",
            width = 110,
            tooltip = "Preview the kill confirmation (also: /cimpact test).",
            onClick = function()
                if CommanderImpact_Test then CommanderImpact_Test() end
            end,
        },
        {
            label = "Test HK",
            width = 90,
            tooltip = "Preview the honorable-kill feedback (also: /cimpact testhonor).",
            onClick = function()
                if CommanderImpact_TestHonor then CommanderImpact_TestHonor() end
            end,
        },
        {
            label = "War Record",
            width = 110,
            tooltip = "Print this session's honorable kills and estimated honor (also: /cimpact report).",
            onClick = function()
                if CommanderImpact_WarRecord then CommanderImpact_WarRecord() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Impact" then
        Commander.UI.ApplyDefaults(CommanderImpactDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

CommanderResourceDB = CommanderResourceDB or {}

COMMANDER_RESOURCE_EVENTS = {
    FIVE_SECOND_RULE_CHANGED = "FIVE_SECOND_RULE_CHANGED",
}

local DefaultSettings = {
    ShowFiveSecondRule = true,
    PlayReadySound = true,
    LockBar = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function ApplyDefaultSettings()
    -- One-time migration: pre-2.0 code persisted ShowFiveSecondRule=false for
    -- every install ("... = CommanderResourceDB.ShowFiveSecondRule or false")
    -- and no UI could write true, so a saved false was never intentional.
    -- Flip it once to the new default; afterwards a user-set false sticks.
    if not CommanderResourceDB._defaultsV2 then
        if CommanderResourceDB.ShowFiveSecondRule == false then
            CommanderResourceDB.ShowFiveSecondRule = true
        end
        CommanderResourceDB._defaultsV2 = true
    end

    Commander.UI.ApplyDefaults(CommanderResourceDB, DefaultSettings)
end

local function Reset()
    Commander.UI.ResetToDefaults(CommanderResourceDB, DefaultSettings)
    -- Also forget the dragged bar position (not part of DefaultSettings)
    if CommanderResources_ResetBarPosition then
        CommanderResources_ResetBarPosition()
    else
        CommanderResourceDB.BarPosition = nil
    end
    Commander.Notify(COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED)
    print("Commander Resources: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Resources",
        title = "Resources",
        addonName = "Commander_Resources",
        description = "Tracks the five second rule for mana users: after you spend mana, a countdown shows when spirit regeneration resumes, then flips to your estimated mana per tick until you are full again.",
        event = COMMANDER_RESOURCE_EVENTS.FIVE_SECOND_RULE_CHANGED,
        slash = { "/cres" },
    })

    panel:AddSection("Five Second Rule", "Only shown on characters whose active power type is mana.")
    panel:AddCheckbox({
        label = "Show Five Second Rule Bar",
        tooltip = "Show the regeneration tracker bar. It only appears on characters whose active power type is mana.",
        get = function() return CommanderResourceDB.ShowFiveSecondRule end,
        set = function(value) CommanderResourceDB.ShowFiveSecondRule = value end,
    })
    panel:AddCheckbox({
        label = "Play Sound When Mana is Full",
        tooltip = "Play the ready-check sound when your mana returns to full.",
        get = function() return CommanderResourceDB.PlayReadySound end,
        set = function(value) CommanderResourceDB.PlayReadySound = value end,
        isEnabled = function() return CommanderResourceDB.ShowFiveSecondRule end,
    })

    panel:AddSection("Position")
    panel:AddCheckbox({
        label = "Lock Bar Position",
        tooltip = "Prevent the tracker bar from being dragged. Its position is saved between sessions either way.",
        get = function() return CommanderResourceDB.LockBar end,
        set = function(value) CommanderResourceDB.LockBar = value end,
        isEnabled = function() return CommanderResourceDB.ShowFiveSecondRule end,
    })
    panel:AddButtonRow({
        {
            label = "Reset Bar Position",
            tooltip = "Move the tracker bar back to the center of the screen.",
            onClick = function()
                if CommanderResources_ResetBarPosition then
                    CommanderResources_ResetBarPosition()
                end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Resources" then
        -- SavedVariables replace the global after this file runs, so re-ensure the table here
        CommanderResourceDB = CommanderResourceDB or {}
        ApplyDefaultSettings()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end)

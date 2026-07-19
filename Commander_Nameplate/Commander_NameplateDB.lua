CommanderNameplateDB = _G.CommanderNameplateDB or {}

COMMANDER_NAMEPLATE_EVENTS = {
    UPDATE = "COMMANDER_NAMEPLATE_UPDATE"
}

local DefaultSettings = {
    showPlayerName = true,
    fadeWhileMoving = false,
    fadeIntensity = 0.5,
    showHealthPercent = false,
    showManaPercent = false,
    alwaysShowMana = false,
    unlockPlate = false,
    classColorHealth = false,
    hidePowerBar = false,
    plateScale = 1.0,
    castBarColor = "GOLD",
    position = {"CENTER", "UIParent", "CENTER", 0, 300}
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderNameplateDB, DefaultSettings)
    Commander.Notify(COMMANDER_NAMEPLATE_EVENTS.UPDATE)
    print("Commander Nameplate: settings restored to defaults")
end

local function ResetPosition()
    CommanderNameplateDB.position = Commander.UI.CopyValue(DefaultSettings.position)
    Commander.Notify(COMMANDER_NAMEPLATE_EVENTS.UPDATE)
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Nameplate",
        title = "Nameplate",
        addonName = "Commander_Nameplate",
        description = "A personal plate floating above your character with health, mana, and cast bars. It appears when something is happening — combat, casting, missing resources — and melts away when you are topped off.",
        event = COMMANDER_NAMEPLATE_EVENTS.UPDATE,
        slash = { "/cnp" },
    })

    panel:AddSection("Display", "Percent text and the always-on power bar are optional extras on top of the base plate.")
    panel:AddCheckboxPair({
        label = "Show Player Name",
        tooltip = "Show your character's name above the nameplate.",
        get = function() return CommanderNameplateDB.showPlayerName end,
        set = function(value) CommanderNameplateDB.showPlayerName = value end,
    }, {
        label = "Show Health Percentage",
        tooltip = "Display your health as a percentage on the health bar.",
        get = function() return CommanderNameplateDB.showHealthPercent end,
        set = function(value) CommanderNameplateDB.showHealthPercent = value end,
    })
    panel:AddCheckboxPair({
        label = "Show Power Percentage",
        tooltip = "Display your mana, rage, or energy as a percentage on the power bar.",
        get = function() return CommanderNameplateDB.showManaPercent end,
        set = function(value) CommanderNameplateDB.showManaPercent = value end,
    }, {
        label = "Always Show Power Bar",
        tooltip = "Keep the power bar visible out of combat instead of showing it only while fighting or casting.",
        get = function() return CommanderNameplateDB.alwaysShowMana end,
        set = function(value) CommanderNameplateDB.alwaysShowMana = value end,
    })
    panel:AddCheckboxPair({
        label = "Class-Colored Health",
        tooltip = "Color the health bar in your class color instead of the green/yellow/red condition gradient.",
        get = function() return CommanderNameplateDB.classColorHealth end,
        set = function(value) CommanderNameplateDB.classColorHealth = value end,
    }, {
        label = "Hide Power Bar",
        tooltip = "Never show the power bar — health and cast bar only.",
        get = function() return CommanderNameplateDB.hidePowerBar end,
        set = function(value) CommanderNameplateDB.hidePowerBar = value end,
    })
    panel:AddSlider({
        label = "Plate Scale",
        tooltip = "Overall size of the nameplate.",
        min = 0.7, max = 1.8, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderNameplateDB.plateScale end,
        set = function(value) CommanderNameplateDB.plateScale = value end,
    })
    panel:AddDropdown({
        label = "Cast Bar Color",
        tooltip = "Color of the casting bar.",
        options = {
            { text = "Command Gold", value = "GOLD" },
            { text = "Signal Green", value = "GREEN" },
            { text = "Arcane Blue", value = "BLUE" },
            { text = "Fel Purple", value = "PURPLE" },
            { text = "Alert Red", value = "RED" },
        },
        width = 140,
        get = function() return CommanderNameplateDB.castBarColor end,
        set = function(value) CommanderNameplateDB.castBarColor = value end,
    })

    panel:AddCheckboxPair({
        label = "Fade While Moving",
        tooltip = "Make the nameplate translucent while your character is moving.",
        get = function() return CommanderNameplateDB.fadeWhileMoving end,
        set = function(value) CommanderNameplateDB.fadeWhileMoving = value end,
    }, {
        label = "Unlock Plate",
        tooltip = "Unlock to drag the plate anywhere. Lock again when placed — a locked plate never intercepts mouse clicks.",
        get = function() return CommanderNameplateDB.unlockPlate end,
        set = function(value) CommanderNameplateDB.unlockPlate = value end,
    })
    panel:AddSlider({
        label = "Faded Opacity",
        tooltip = "How visible the nameplate remains while you are moving. Lower values make it more transparent.",
        min = 0, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderNameplateDB.fadeIntensity end,
        set = function(value) CommanderNameplateDB.fadeIntensity = value end,
        isEnabled = function() return CommanderNameplateDB.fadeWhileMoving end,
    })
    panel:AddButtonRow({
        {
            label = "Reset Position",
            tooltip = "Move the nameplate back to its default spot above your character.",
            onClick = ResetPosition,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnAwake()
    CreateOptionsPanel()
end

local function OnEvent(self, event, addon)
    if event == "ADDON_LOADED" and addon == "Commander_Nameplate" then
        CommanderNameplateDB = CommanderNameplateDB or {}
        Commander.UI.ApplyDefaults(CommanderNameplateDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)

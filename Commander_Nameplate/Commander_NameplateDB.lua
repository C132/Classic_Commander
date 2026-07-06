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
        description = "A personal nameplate above your character with health, mana, and cast bars. It appears when you are in combat or below full resources, and hides itself when you are topped off.",
        event = COMMANDER_NAMEPLATE_EVENTS.UPDATE,
        slash = { "/cnp" },
    })

    panel:AddSection("Display")
    panel:AddCheckbox({
        label = "Show Player Name",
        tooltip = "Show your character's name above the nameplate.",
        get = function() return CommanderNameplateDB.showPlayerName end,
        set = function(value) CommanderNameplateDB.showPlayerName = value end,
    })
    panel:AddCheckbox({
        label = "Show Health Percentage",
        tooltip = "Display your health as a percentage on the health bar.",
        get = function() return CommanderNameplateDB.showHealthPercent end,
        set = function(value) CommanderNameplateDB.showHealthPercent = value end,
    })
    panel:AddCheckbox({
        label = "Show Mana Percentage",
        tooltip = "Display your mana as a percentage on the mana bar.",
        get = function() return CommanderNameplateDB.showManaPercent end,
        set = function(value) CommanderNameplateDB.showManaPercent = value end,
    })
    panel:AddCheckbox({
        label = "Always Show Mana Bar",
        tooltip = "Keep the mana bar visible out of combat instead of showing it only while fighting or casting.",
        get = function() return CommanderNameplateDB.alwaysShowMana end,
        set = function(value) CommanderNameplateDB.alwaysShowMana = value end,
    })

    panel:AddSection("Movement Fade")
    panel:AddCheckbox({
        label = "Fade While Moving",
        tooltip = "Make the nameplate translucent while your character is moving.",
        get = function() return CommanderNameplateDB.fadeWhileMoving end,
        set = function(value) CommanderNameplateDB.fadeWhileMoving = value end,
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

    panel:AddSection("Position")
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

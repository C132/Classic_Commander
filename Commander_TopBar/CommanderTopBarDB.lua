CommanderTopBarDB = _G.CommanderTopBarDB or {}

COMMANDER_TOPBAR_EVENTS = {
    UPDATE = "COMMANDER_TOPBAR_UPDATE"
}

local DefaultSettings = {
    EnableTopBar = true,
    BarStyle = "NONE",
    RightOffset = 12,
    ShowGold = true,
    ShowGoldRate = true,
    ShowBags = true,
    ShowAmmo = true,
    ShowDurability = true,
    ShowXP = true,
    ShowCoords = false,
    ShowClock = true,
    ShowPerformance = true,
}

local BAR_STYLES = {
    { text = "None (SC2)", value = "NONE" },
    { text = "Dark Strip", value = "DARK" },
    { text = "Console Metal", value = "CONSOLE" },
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderTopBarDB, DefaultSettings)
    Commander.Notify(COMMANDER_TOPBAR_EVENTS.UPDATE)
    print("Commander Top Bar: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "TopBar",
        title = "Top Bar",
        addonName = "Commander_TopBar",
        description = "A command readout along the top of the screen, SC2-style: floating icons and numbers with no backdrop, right-aligned to the screen edge — gold, income, supply, ammo, condition, XP, and more at a glance.",
        event = COMMANDER_TOPBAR_EVENTS.UPDATE,
        slash = { "/ctopbar", "/ctb" },
        slashHandlers = {
            toggle = function()
                CommanderTopBarDB.EnableTopBar = not CommanderTopBarDB.EnableTopBar
                Commander.Notify(COMMANDER_TOPBAR_EVENTS.UPDATE)
            end,
        },
    })

    panel:AddSection("Command Bar")
    panel:AddCheckbox({
        label = "Enable Top Bar",
        tooltip = "Master switch for the whole readout strip.",
        get = function() return CommanderTopBarDB.EnableTopBar end,
        set = function(value) CommanderTopBarDB.EnableTopBar = value end,
    })
    panel:AddDropdown({
        label = "Bar Style",
        tooltip = "None: floating readouts with no backdrop, like SC2. Dark Strip: a translucent black band. Console Metal: the lower console's rail art flipped onto the top edge, tinted with the console's own color setting so the two always match.",
        options = BAR_STYLES,
        width = 150,
        get = function() return CommanderTopBarDB.BarStyle end,
        set = function(value) CommanderTopBarDB.BarStyle = value end,
        isEnabled = function() return CommanderTopBarDB.EnableTopBar end,
    })
    panel:AddSlider({
        label = "Right Offset",
        tooltip = "Distance from the right screen edge to the first readout. Raise it if something else lives in your top-right corner.",
        min = 0, max = 500, step = 10,
        format = "%d px",
        get = function() return CommanderTopBarDB.RightOffset end,
        set = function(value) CommanderTopBarDB.RightOffset = value end,
        isEnabled = function() return CommanderTopBarDB.EnableTopBar end,
    })

    panel:AddSection("Readouts")
    local function Toggle(key, label, tooltip)
        return {
            label = label,
            tooltip = tooltip,
            get = function() return CommanderTopBarDB[key] end,
            set = function(value) CommanderTopBarDB[key] = value end,
            isEnabled = function() return CommanderTopBarDB.EnableTopBar end,
        }
    end
    panel:AddCheckboxPair(
        Toggle("ShowGold", "Gold", "Your current money."),
        Toggle("ShowGoldRate", "Gold Income", "Net gold earned per hour this session (green earning, red spending)."))
    panel:AddCheckboxPair(
        Toggle("ShowBags", "Supply (Bag Slots)", "Used / total bag slots, red when nearly full."),
        Toggle("ShowAmmo", "Ammo", "Equipped ammo count with its icon; red under 200. Hidden for classes without ammo."))
    panel:AddCheckboxPair(
        Toggle("ShowDurability", "Durability", "Lowest equipment durability; red when repairs loom."),
        Toggle("ShowXP", "XP Rate", "XP per hour and estimated time to level. Hidden at max level."))
    panel:AddCheckboxPair(
        Toggle("ShowCoords", "Coordinates", "Your current map coordinates. Hidden where the map has no position data."),
        Toggle("ShowClock", "Clock", "Local time."))
    panel:AddCheckboxPair(
        Toggle("ShowPerformance", "Performance", "Framerate and home latency."),
        nil)

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_TopBar" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        Commander.UI.ApplyDefaults(CommanderTopBarDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

CommanderAfflictionsDB = _G.CommanderAfflictionsDB or {}

COMMANDER_AFFLICTIONS_EVENTS = {
    UPDATE = "COMMANDER_AFFLICTIONS_UPDATE"
}

local DefaultSettings = {
    EnableAfflictions = true,
    MaxBars = 6,
    ShowTargetNames = true,
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "CLASSIC")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderAfflictionsDB, DefaultSettings)
    Commander.Notify(COMMANDER_AFFLICTIONS_EVENTS.UPDATE)
    print("Commander Afflictions: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Afflictions",
        title = "Afflictions",
        addonName = "Commander_Afflictions",
        description = "Your afflictions as a live operations board. Every debuff you land — DoTs, curses, diseases, stuns — becomes a draining bar, and the board stays truthful: dispels, immunities, and target deaths remove bars the moment they happen, not when a timer guesses.",
        event = COMMANDER_AFFLICTIONS_EVENTS.UPDATE,
        slash = { "/caff" },
        slashHandlers = {},
    })

    panel:AddSection("Affliction Board")
    panel:AddCheckbox({
        label = "Enable Afflictions",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderAfflictionsDB.EnableAfflictions end,
        set = function(value) CommanderAfflictionsDB.EnableAfflictions = value end,
    })
    panel:AddCheckbox({
        label = "Show Target Names",
        tooltip = "Append the afflicted unit's name to each bar (useful when dotting multiple targets).",
        get = function() return CommanderAfflictionsDB.ShowTargetNames end,
        set = function(value) CommanderAfflictionsDB.ShowTargetNames = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    })
    panel:AddSlider({
        label = "Board Length",
        tooltip = "Maximum number of affliction bars shown at once (soonest to expire first).",
        min = 1, max = 12, step = 1,
        format = "%.0f bars",
        get = function() return CommanderAfflictionsDB.MaxBars end,
        set = function(value) CommanderAfflictionsDB.MaxBars = value end,
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
    })

    panel:AddSection("Frame")
    Commander.UI.AddHudChromeOptions(panel, CommanderAfflictionsDB, "Hud", {
        isEnabled = function() return CommanderAfflictionsDB.EnableAfflictions end,
        onChanged = function() Commander.Notify(COMMANDER_AFFLICTIONS_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Afflictions" then
        Commander.UI.ApplyDefaults(CommanderAfflictionsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

CommanderTalentsDB = _G.CommanderTalentsDB or {}

COMMANDER_TALENTS_EVENTS = {
    UPDATE = "COMMANDER_TALENTS_UPDATE",
}

local DefaultSettings = {
    EnableTalents = true,

    -- Calculator window (the Quartermaster browser conventions)
    BrowserStyle = "WINDOW",    -- WINDOW | DARK | CLASSIC
    BrowserScale = 1.0,
    -- false (not nil) so Restore Defaults clears a saved drag position
    BrowserPos = false,
    ShowBriefing = true,        -- the stat-priority / consumables side panel

    -- Session memory (widget-less, mirrors Quartermaster's Browser* keys)
    SelClass = false,           -- false = your class
    SelBuildKind = false,       -- "PRESET" | "CUSTOM" | false
    SelBuildKey = false,        -- preset spec key or custom build name
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderTalentsDB, DefaultSettings)
    Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
    print("Commander Talents: settings restored to defaults")
end

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Talents",
        title = "Talents",
        addonName = "Commander_Talents",
        description = "The war academy. A full TBC talent calculator for all nine classes — every tree on its proper art with working prerequisites, tier gates, and the 61-point budget. Preset loadouts mirror Quartermaster's specializations with stat priorities and consumable recommendations on the side; your own builds save account-wide, and builds import and export as Wowhead-style talent strings. Bare /ctalents opens the calculator.",
        event = COMMANDER_TALENTS_EVENTS.UPDATE,
        slash = { "/ctalents", "/ctal" },
        slashHandlers = {
            [""] = function() if CommanderTalents_Toggle then CommanderTalents_Toggle() end end,
            export = function() if CommanderTalents_PrintExport then CommanderTalents_PrintExport() end end,
        },
    })

    local function Enabled()
        return CommanderTalentsDB.EnableTalents
    end

    panel:AddSection("Calculator", "The talent calculator window.")
    panel:AddCheckboxPair({
        label = "Enable Talents",
        tooltip = "Master switch for the calculator window and its slash commands.",
        get = function() return CommanderTalentsDB.EnableTalents end,
        set = function(value) CommanderTalentsDB.EnableTalents = value end,
    }, {
        label = "Show Briefing Panel",
        tooltip = "The right-hand panel: the selected loadout's stat priority, notes, and Quartermaster consumable recommendations.",
        get = function() return CommanderTalentsDB.ShowBriefing end,
        set = function(value) CommanderTalentsDB.ShowBriefing = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Window Style",
        tooltip = "Window keeps the full framed window with title and close button; Dark and Classic are the suite's flat backdrops.",
        options = {
            { text = "Window", value = "WINDOW" },
            { text = "Dark", value = "DARK" },
            { text = "Classic", value = "CLASSIC" },
        },
        get = function() return CommanderTalentsDB.BrowserStyle end,
        set = function(value) CommanderTalentsDB.BrowserStyle = value end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Overall size of the calculator window.",
        min = 0.6, max = 1.4, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderTalentsDB.BrowserScale end,
        set = function(value) CommanderTalentsDB.BrowserScale = value end,
        isEnabled = Enabled,
    })
    panel:AddButtonRow({
        {
            label = "Open Calculator",
            tooltip = "Open the talent calculator (same as bare /ctalents).",
            onClick = function() if CommanderTalents_Toggle then CommanderTalents_Toggle() end end,
            isEnabled = Enabled,
        },
        {
            label = "Reset Position",
            tooltip = "Clear the saved drag position and re-center the calculator window.",
            onClick = function()
                CommanderTalentsDB.BrowserPos = false
                Commander.Notify(COMMANDER_TALENTS_EVENTS.UPDATE)
            end,
            isEnabled = Enabled,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Talents" then
        Commander.UI.ApplyDefaults(CommanderTalentsDB, DefaultSettings)
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
    end
end)

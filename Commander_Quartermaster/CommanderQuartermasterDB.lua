CommanderQuartermasterDB = _G.CommanderQuartermasterDB or {}

COMMANDER_QUARTERMASTER_EVENTS = {
    UPDATE = "COMMANDER_QUARTERMASTER_UPDATE",
    -- Fired by the core after any ledger scan so open UI can refresh
    LEDGER = "COMMANDER_QUARTERMASTER_LEDGER",
}

local DefaultSettings = {
    EnableQuartermaster = true,
    TrackThisCharacter = true,  -- opt-out for bank alts you don't want listed
    TrackBank = true,
    TrackMail = true,
    TooltipCounts = true,       -- append holdings to consumable tooltips
    TooltipBreakdown = false,   -- per-character lines under the counts
    CurrentRealmOnly = true,

    -- Browser window
    BrowserStyle = "WINDOW",    -- WINDOW | DARK | CLASSIC
    BrowserScale = 1.0,
    -- false (not nil) so Restore Defaults clears a saved drag position
    BrowserPos = false,
    OwnedOnly = false,          -- browse filter: only rows you hold somewhere

    -- Browser session memory (which page you were on)
    BrowserView = "BROWSE",     -- BROWSE | LOADOUT
    BrowserCategory = "FLASKS",
    BrowserClass = false,       -- false = your class
    BrowserSpec = false,
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderQuartermasterDB, DefaultSettings)
    Commander.Notify(COMMANDER_QUARTERMASTER_EVENTS.UPDATE)
    print("Commander Quartermaster: settings restored to defaults")
end

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Quartermaster",
        title = "Quartermaster",
        addonName = "Commander_Quartermaster",
        description = "The supply ledger. A browsable database of every TBC consumable — flasks to bandages to ammunition — with loadout recommendations per class and spec, and live counts of what you hold across bags, bank, mail, and every alt. Each character reports as it plays: bags are live, bank and mail are as of the last visit. Bare /cqm opens the browser.",
        event = COMMANDER_QUARTERMASTER_EVENTS.UPDATE,
        slash = { "/cquartermaster", "/cqm" },
        slashHandlers = {
            [""] = function() if CommanderQuartermaster_Toggle then CommanderQuartermaster_Toggle() end end,
            scan = function() if CommanderQuartermaster_Scan then CommanderQuartermaster_Scan() end end,
            report = function() if CommanderQuartermaster_Report then CommanderQuartermaster_Report() end end,
        },
    })

    local function Enabled()
        return CommanderQuartermasterDB.EnableQuartermaster
    end

    panel:AddSection("Tracking", "What each character files into the account-wide ledger.")
    panel:AddCheckboxPair({
        label = "Enable Quartermaster",
        tooltip = "Master switch for the whole module: scanning, tooltip counts, and the browser.",
        get = function() return CommanderQuartermasterDB.EnableQuartermaster end,
        set = function(value) CommanderQuartermasterDB.EnableQuartermaster = value end,
    }, {
        label = "Include This Character",
        tooltip = "File this character's inventory into the ledger so your other characters can see it. Turn off on characters you don't want listed.",
        get = function() return CommanderQuartermasterDB.TrackThisCharacter end,
        set = function(value) CommanderQuartermasterDB.TrackThisCharacter = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Track Bank",
        tooltip = "Record bank contents whenever the bank is open. Bank data is 'as of last visit'.",
        get = function() return CommanderQuartermasterDB.TrackBank end,
        set = function(value) CommanderQuartermasterDB.TrackBank = value end,
        isEnabled = Enabled,
    }, {
        label = "Track Mail",
        tooltip = "Record consumables sitting in the mailbox whenever it is open — the classic parking spot for flasks in transit.",
        get = function() return CommanderQuartermasterDB.TrackMail end,
        set = function(value) CommanderQuartermasterDB.TrackMail = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Tooltips & Scope", "Where the ledger speaks up.")
    panel:AddCheckboxPair({
        label = "Tooltip Counts",
        tooltip = "Append a holdings line to consumable tooltips: total, and where it sits (bags, bank, mail, alts).",
        get = function() return CommanderQuartermasterDB.TooltipCounts end,
        set = function(value) CommanderQuartermasterDB.TooltipCounts = value end,
        isEnabled = Enabled,
    }, {
        label = "Tooltip Alt Breakdown",
        tooltip = "Under the counts line, list each character holding the item.",
        get = function() return CommanderQuartermasterDB.TooltipBreakdown end,
        set = function(value) CommanderQuartermasterDB.TooltipBreakdown = value end,
        isEnabled = function() return Enabled() and CommanderQuartermasterDB.TooltipCounts end,
    })
    panel:AddCheckboxPair({
        label = "Current Realm Only",
        tooltip = "Count only characters on this realm. Turn off to pool every realm's ledger together.",
        get = function() return CommanderQuartermasterDB.CurrentRealmOnly end,
        set = function(value) CommanderQuartermasterDB.CurrentRealmOnly = value end,
        isEnabled = Enabled,
    }, {
        label = "Owned Items Only",
        tooltip = "Browser filter: show only items you hold somewhere. Toggleable from the browser too.",
        get = function() return CommanderQuartermasterDB.OwnedOnly end,
        set = function(value) CommanderQuartermasterDB.OwnedOnly = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Browser", "The item browser window itself.")
    panel:AddDropdown({
        label = "Window Style",
        tooltip = "Window keeps the full framed window with title and close button; Dark and Classic are the suite's flat backdrops.",
        options = {
            { text = "Window", value = "WINDOW" },
            { text = "Dark", value = "DARK" },
            { text = "Classic", value = "CLASSIC" },
        },
        get = function() return CommanderQuartermasterDB.BrowserStyle end,
        set = function(value) CommanderQuartermasterDB.BrowserStyle = value end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Overall size of the browser window.",
        min = 0.6, max = 1.4, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderQuartermasterDB.BrowserScale end,
        set = function(value) CommanderQuartermasterDB.BrowserScale = value end,
        isEnabled = Enabled,
    })
    panel:AddButtonRow({
        {
            label = "Open Browser",
            tooltip = "Open the Quartermaster browser (same as bare /cqm).",
            onClick = function() if CommanderQuartermaster_Toggle then CommanderQuartermaster_Toggle() end end,
            isEnabled = Enabled,
        },
        {
            label = "Reset Position",
            tooltip = "Clear the saved drag position and re-center the browser window.",
            onClick = function()
                CommanderQuartermasterDB.BrowserPos = false
                Commander.Notify(COMMANDER_QUARTERMASTER_EVENTS.UPDATE)
            end,
            isEnabled = Enabled,
        },
    })

    panel:AddSection("Ledger", "Housekeeping for the account-wide inventory records.")
    -- The character list is dynamic: repopulate the options table IN PLACE on
    -- every panel refresh (the dropdown initializer and its text lookup both
    -- read this same table by reference). Registered before the dropdown so
    -- the repopulate runs first in refresher order.
    local forgetOptions = {}
    local forgetSelection = nil
    panel:AddRefresher(function()
        for i = #forgetOptions, 1, -1 do
            forgetOptions[i] = nil
        end
        local seen = false
        if CommanderQuartermaster_ListCharacters then
            for _, rec in ipairs(CommanderQuartermaster_ListCharacters(true)) do
                forgetOptions[#forgetOptions + 1] = {
                    text = string.format("%s — %s", rec.name, rec.realm),
                    value = rec.realm .. "\001" .. rec.name,
                }
                if forgetSelection == forgetOptions[#forgetOptions].value then
                    seen = true
                end
            end
        end
        if not seen then
            forgetSelection = nil
        end
    end)
    panel:AddDropdown({
        label = "Character",
        tooltip = "Pick a character to remove from the ledger — for alts you've deleted or renamed. Logging the character back in refiles it.",
        options = forgetOptions,
        width = 180,
        get = function() return forgetSelection end,
        set = function(value) forgetSelection = value end,
        isEnabled = function() return Enabled() and #forgetOptions > 0 end,
    })
    panel:AddButtonRow({
        {
            label = "Forget Character",
            tooltip = "Remove the selected character's records from the ledger.",
            onClick = function()
                if forgetSelection and CommanderQuartermaster_ForgetCharacter then
                    local realm, name = forgetSelection:match("^(.-)\001(.+)$")
                    CommanderQuartermaster_ForgetCharacter(realm, name)
                    forgetSelection = nil
                    Commander.Notify(COMMANDER_QUARTERMASTER_EVENTS.UPDATE)
                end
            end,
            isEnabled = function() return Enabled() and forgetSelection ~= nil end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Quartermaster" then
        Commander.UI.ApplyDefaults(CommanderQuartermasterDB, DefaultSettings)
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
    end
end)

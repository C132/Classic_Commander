CommanderQuartermasterDB = _G.CommanderQuartermasterDB or {}

COMMANDER_QUARTERMASTER_EVENTS = {
    UPDATE = "COMMANDER_QUARTERMASTER_UPDATE",
    -- Fired by the core after any ledger scan so open UI can refresh
    LEDGER = "COMMANDER_QUARTERMASTER_LEDGER",
}

local DefaultSettings = {
    EnableQuartermaster = true,
    -- Per-character listing opt-outs, keyed "<realm>\001<char>". A hidden
    -- character's records stay in the ledger (reversible); only the
    -- explicit Forget button deletes.
    UntrackedChars = {},
    TrackBank = true,
    TrackMail = true,
    TrackTransit = true,        -- credit mailed consumables to the recipient
    TooltipCounts = true,       -- append holdings to consumable tooltips
    TooltipBreakdown = false,   -- per-character lines under the counts
    CurrentRealmOnly = true,

    -- Raid supply check (readiness verdict on zoning into a raid)
    RaidCheck = true,
    RaidCheckSound = true,

    -- Browser window
    BrowserStyle = "WINDOW",    -- WINDOW | DARK | CLASSIC
    BrowserScale = 1.0,
    -- false (not nil) so Restore Defaults clears a saved drag position
    BrowserPos = false,
    OwnedOnly = false,          -- browse filter: only rows you hold somewhere

    -- Browser session memory (which page you were on)
    BrowserView = "BROWSE",     -- BROWSE | LOADOUT | CHARS
    BrowserCategory = "FLASKS",
    BrowserClass = false,       -- false = your class
    BrowserSpec = false,        -- false = auto-detect from talents
    EraFilter = "ALL",          -- ALL | TBC | VANILLA
    SourceFilter = "ALL",       -- ALL | a source key

    -- NOTE: the Watchlist map (per-character restock targets) deliberately
    -- lives OUTSIDE this table — the Orders rally-point precedent — so
    -- Restore Defaults never wipes targets. It is initialized on load below.
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderQuartermasterDB, DefaultSettings)
    Commander.Notify(COMMANDER_QUARTERMASTER_EVENTS.UPDATE)
    print("Commander Quartermaster: settings restored to defaults")
end

-- The one setting that is genuinely about THIS character. Stored as a keyed
-- map in the account-wide DB so toggling it on a bank alt can never affect
-- any other character (an account-wide boolean here once meant logging in
-- with it off deleted every character's ledger record in turn).
local function MyCharToken()
    return ((GetRealmName and GetRealmName()) or "Unknown")
        .. "\001" .. ((UnitName and UnitName("player")) or "Unknown")
end

-- This page carries more rows than the Settings canvas is tall, so its rows
-- flow into a scroll frame — the Reticle/Shield pattern: AddRow is
-- overridden on this panel INSTANCE only, the shared framework is untouched.
-- Returns the function to call once Finalize has added the footer.
local function MakeScrollable(panel, frameName)
    local scroll = CreateFrame("ScrollFrame", frameName, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel._anchor, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 28
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnSizeChanged", function(_, width) scrollChild:SetWidth(width) end)

    local seed = CreateFrame("Frame", nil, scrollChild)
    seed:SetHeight(1)
    seed:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    seed:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    panel._anchor = seed
    panel._contentHeight = 0
    panel.AddRow = function(self, height, spacing)
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(height)
        row:SetPoint("TOPLEFT", self._anchor, "BOTTOMLEFT", 0, -(spacing or 8))
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        self._anchor = row
        self._contentHeight = self._contentHeight + height + (spacing or 8)
        return row
    end

    return function()
        scrollChild:SetHeight(panel._contentHeight + 24)
    end
end

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Quartermaster",
        title = "Quartermaster",
        addonName = "Commander_Quartermaster",
        description = "The supply ledger. A browsable database of every TBC consumable — flasks to bandages to ammunition — with loadout recommendations per class and spec, and live counts of what you hold across bags, bank, mail, and every alt. Each character reports as it plays: bags are live, bank and mail are as of the last visit; mail sent to alts stays counted in transit. Bare /cqm opens the browser; 'ready' grades your raid loadout, 'shop' builds the shopping list.",
        event = COMMANDER_QUARTERMASTER_EVENTS.UPDATE,
        slash = { "/cquartermaster", "/cqm" },
        slashHandlers = {
            [""] = function() if CommanderQuartermaster_Toggle then CommanderQuartermaster_Toggle() end end,
            scan = function() if CommanderQuartermaster_Scan then CommanderQuartermaster_Scan() end end,
            report = function() if CommanderQuartermaster_Report then CommanderQuartermaster_Report() end end,
            ready = function() if CommanderQuartermaster_Ready then CommanderQuartermaster_Ready() end end,
            shop = function() if CommanderQuartermaster_ShoppingList then CommanderQuartermaster_ShoppingList() end end,
        },
    })
    local FinishScroll = MakeScrollable(panel, "CommanderQuartermasterSettingsScroll")

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
        tooltip = "List this character's holdings for your other characters. Applies to this character only — turning it off hides (never deletes) its records, so it's the right switch for bank alts you don't want in the Alts column.",
        get = function()
            local map = CommanderQuartermasterDB.UntrackedChars
            return not (map and map[MyCharToken()])
        end,
        set = function(value)
            local map = CommanderQuartermasterDB.UntrackedChars
            if not map then
                map = {}
                CommanderQuartermasterDB.UntrackedChars = map
            end
            map[MyCharToken()] = (not value) and true or nil
        end,
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
    panel:AddCheckbox({
        label = "Track Outbound Mail",
        tooltip = "When you mail consumables to another of your characters, keep them counted 'in transit' against the recipient until their own mailbox scan takes over (or 31 days pass). Closes the classic gap where mailed flasks vanish from every count.",
        get = function() return CommanderQuartermasterDB.TrackTransit end,
        set = function(value) CommanderQuartermasterDB.TrackTransit = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Raid Readiness", "The loadout verdict: carried, banked, on alts, or missing.")
    panel:AddCheckboxPair({
        label = "Raid Supply Check",
        tooltip = "On zoning into a raid, print the readiness verdict for your spec's loadout plus any watchlist deficits — once per raid per half hour, so corpse runs stay quiet. Also on demand via /cqm ready.",
        get = function() return CommanderQuartermasterDB.RaidCheck end,
        set = function(value) CommanderQuartermasterDB.RaidCheck = value end,
        isEnabled = Enabled,
    }, {
        label = "Supply Check Sound",
        tooltip = "Play the raid-warning sound when the supply check finds gaps. A green check is always silent.",
        get = function() return CommanderQuartermasterDB.RaidCheckSound end,
        set = function(value) CommanderQuartermasterDB.RaidCheckSound = value end,
        isEnabled = function() return Enabled() and CommanderQuartermasterDB.RaidCheck end,
    })
    panel:AddButtonRow({
        {
            label = "Readiness Report",
            tooltip = "Print the slot-by-slot readiness verdict to chat (same as /cqm ready).",
            onClick = function() if CommanderQuartermaster_Ready then CommanderQuartermaster_Ready() end end,
            isEnabled = Enabled,
        },
        {
            label = "Shopping List",
            tooltip = "Open the copyable shopping list built from loadout gaps and watchlist deficits (same as /cqm shop).",
            onClick = function() if CommanderQuartermaster_ShoppingList then CommanderQuartermaster_ShoppingList() end end,
            isEnabled = Enabled,
        },
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
    FinishScroll()
end

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Quartermaster" then
        Commander.UI.ApplyDefaults(CommanderQuartermasterDB, DefaultSettings)
        -- Outside DefaultSettings on purpose (survives Restore Defaults)
        CommanderQuartermasterDB.Watchlist = CommanderQuartermasterDB.Watchlist or {}
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
    end
end)

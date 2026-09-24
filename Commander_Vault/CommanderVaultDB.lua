CommanderVault = CommanderVault or {}
CommanderVaultDB = _G.CommanderVaultDB or {}
CommanderVaultCache = _G.CommanderVaultCache or {}

COMMANDER_VAULT_EVENTS = {
    UPDATE = "COMMANDER_VAULT_UPDATE",
}

local DefaultSettings = {
    EnableVault = true,
    TakeOverBankFrame = true,
    Columns = 14,
    ButtonSize = 37,
    FrameStyle = "BANK",
    -- Detailed, not Sections. Ten broad headings is the safe default and the
    -- less useful one: "Equipment" is the biggest pile in most banks and the
    -- question actually asked of it is "have I got a spare helm", which a
    -- single heading cannot answer. Detailed splits it by the slot the piece
    -- goes in, which is the shape the player already thinks in.
    Grouping = "DETAIL",
    ShowSlotCounts = true,
    ColorCodeItems = true,
    BorderThickness = 2,
    RarityHalo = true,
    BindBadges = "BOTH",
    ShowItemLevel = true,
    SearchMode = "DIM",
    AutoFocusSearch = true,
    SortOrder = "CATEGORY",
    ShowAdvisor = true,
    StaleDays = 60,
    TrackDwell = true,
    RememberBank = true,
    FramePos = false,
    FrameScale = 1.0,
    -- The dragged size. false rather than nil so Restore Defaults genuinely
    -- gives the window back to the Columns slider: ResetToDefaults only
    -- rewrites keys that appear in this table.
    FrameW = false,
    FrameH = false,
    ShowCarried = false,
    View = "GRID",
    TooltipCounts = "ALL",
    TooltipCarried = false,
    RosterCurrentRealmOnly = true,
    TrackGuildBank = true,
    RosterChar = false,
    -- Section keys the player has folded shut. A table so Restore Defaults
    -- genuinely reopens everything rather than leaving stale keys behind.
    Collapsed = {},
}

local FRAME_STYLES = {
    { text = "Bank", value = "BANK" },
    { text = "Window", value = "WINDOW" },
    { text = "Dark Panel", value = "DARK" },
}

local GROUPINGS = {
    { text = "Sections", value = "SECTION" },
    { text = "Detailed", value = "DETAIL" },
    { text = "One Grid", value = "NONE" },
}

local BIND_BADGES = {
    { text = "Soulbound & BoE", value = "BOTH" },
    { text = "BoE only", value = "BOE" },
    { text = "Off", value = "OFF" },
}

local SORT_ORDERS = {
    { text = "Category", value = "CATEGORY" },
    { text = "Quality", value = "QUALITY" },
    { text = "Item Level", value = "ILVL" },
    { text = "Name (A-Z)", value = "NAME" },
    { text = "Vendor Value", value = "VALUE" },
}

local TOOLTIP_MODES = {
    { text = "Vault and alts", value = "ALL" },
    { text = "This vault only", value = "VAULT" },
    { text = "Off", value = "OFF" },
}

local SEARCH_MODES = {
    { text = "Dim the rest", value = "DIM" },
    { text = "Hide the rest", value = "HIDE" },
}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderVaultDB, DefaultSettings)
    Commander.Notify(COMMANDER_VAULT_EVENTS.UPDATE)
    print("Commander Vault: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Vault",
        title = "Vault",
        addonName = "Commander_Vault",
        description = "The bank window this client never got round to writing. Every bank slot and every bank bag on one grid, grouped into sections you can read from across the room, with a search box that takes more than names, a sort that gives you slots back rather than merely tidying, and a standing report on what in here is dead weight — all of it browsable from the far side of the continent, because a vault you can only look at while standing in it is the window you already have.",
        event = COMMANDER_VAULT_EVENTS.UPDATE,
        slash = { "/cvault", "/cbank", "/cv" },
        slashHandlers = {
            [""] = function()
                if CommanderVault_Toggle then CommanderVault_Toggle() end
            end,
            sort = function()
                if CommanderVault_SortBank then CommanderVault_SortBank() end
            end,
            guild = function()
                if CommanderVault_SweepGuildBank then CommanderVault_SweepGuildBank() end
            end,
            stop = function()
                if CommanderVault.StopMover then CommanderVault.StopMover("stopped") end
            end,
            report = function()
                if CommanderVault_PrintReport then CommanderVault_PrintReport() end
            end,
            -- Searching from the command line lives on its own slash command
            -- (/vfind, registered in the UI file) rather than here: the shared
            -- dispatcher matches the WHOLE message against its handler table,
            -- so a subcommand can never carry an argument.
        },
    })

    panel:AddSection("The Vault",
        "Master switch and how the window takes the stage. With the takeover on, visiting a banker opens this window instead of the stock one; the stock frame stays open behind it, which is what keeps the banker's session alive.")
    panel:AddCheckbox({
        label = "Enable Vault",
        tooltip = "Master switch. Off returns the stock bank window and stops the vault cache updating. Nothing already remembered is forgotten.",
        get = function() return CommanderVaultDB.EnableVault end,
        set = function(value) CommanderVaultDB.EnableVault = value end,
    })
    panel:AddCheckbox({
        label = "Replace the Bank Window",
        tooltip = "Open the vault instead of Blizzard's bank frame when you talk to a banker. Off keeps the stock window and leaves the vault to /cvault.",
        get = function() return CommanderVaultDB.TakeOverBankFrame end,
        set = function(value) CommanderVaultDB.TakeOverBankFrame = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddCheckbox({
        label = "Remember the Vault",
        tooltip = "Keep a snapshot of the bank so the window is browsable and searchable anywhere in the world. Off means the vault is readable only while you are standing at a banker.",
        get = function() return CommanderVaultDB.RememberBank end,
        set = function(value) CommanderVaultDB.RememberBank = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })

    panel:AddSection("Layout", "How the window is dressed, how wide the grid runs, and how the items are grouped inside it.")
    panel:AddDropdown({
        label = "Frame Style",
        tooltip = "Bank wears the stock bank window's own dressing: the era's light window stone, the gold dialog border, the carved header plate, and the client's own bank socket behind every item and every bag slot. Window is the lighter inset panel the suite's other browsers use. Dark Panel is the flat HUD backing.",
        options = FRAME_STYLES,
        width = 140,
        get = function() return CommanderVaultDB.FrameStyle end,
        set = function(value) CommanderVaultDB.FrameStyle = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddSliderPair({
        label = "Columns",
        tooltip = "How many item slots per row a freshly-sized window opens with. Dragging the grip in the bottom-right corner takes over from here — the grid then fits as many columns as the width allows, and Reset Size hands the decision back to this slider.",
        min = 8, max = 20, step = 1,
        format = function(value) return string.format("%d", value) end,
        get = function() return CommanderVaultDB.Columns end,
        set = function(value) CommanderVaultDB.Columns = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Slot Size",
        tooltip = "Size of each item slot in pixels.",
        min = 28, max = 46, step = 1,
        format = function(value) return string.format("%d px", value) end,
        get = function() return CommanderVaultDB.ButtonSize end,
        set = function(value) CommanderVaultDB.ButtonSize = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddDropdownPair({
        label = "Grouping",
        tooltip = "Detailed is the default: equipment is split by the slot it goes in — helms apart from cloaks apart from trinkets — and everything else by its own subtype, potions apart from elixirs. Sections is the coarser view, ten broad headings and nothing below them. One Grid draws the vault as the raw slots, in bag order.",
        options = GROUPINGS,
        width = 140,
        get = function() return CommanderVaultDB.Grouping end,
        set = function(value) CommanderVaultDB.Grouping = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Search Behaviour",
        tooltip = "Whether items that do not match the search are dimmed in place — keeping the shape of the vault — or removed from the grid entirely.",
        options = SEARCH_MODES,
        width = 140,
        get = function() return CommanderVaultDB.SearchMode end,
        set = function(value) CommanderVaultDB.SearchMode = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddCheckboxPair({
        label = "Show Free Slots",
        tooltip = "Draw the empty slots in each section's grid, so the vault's real capacity is visible rather than implied.",
        get = function() return CommanderVaultDB.ShowSlotCounts end,
        set = function(value) CommanderVaultDB.ShowSlotCounts = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Bags Alongside",
        tooltip = "Add a second grid under the vault showing what you are carrying, so a deposit is a drag rather than a trip between two windows.",
        get = function() return CommanderVaultDB.ShowCarried end,
        set = function(value) CommanderVaultDB.ShowCarried = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddSliderPair({
        label = "Window Scale",
        tooltip = "Overall size of the vault window.",
        min = 0.6, max = 1.6, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderVaultDB.FrameScale end,
        set = function(value) CommanderVaultDB.FrameScale = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Stale After",
        tooltip = "How long an item has to sit untouched in the vault before the report calls it out. Zero switches the check off.",
        min = 0, max = 180, step = 5,
        format = function(value)
            return value == 0 and "Off" or string.format("%d days", value)
        end,
        get = function() return CommanderVaultDB.StaleDays end,
        set = function(value) CommanderVaultDB.StaleDays = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })

    panel:AddSection("Item Highlighting",
        "The same reading the bags get: quality colours around the border, a padlock for bind state, and the item level on the corner of anything you could wear.")
    panel:AddCheckboxPair({
        label = "Color Code Items",
        tooltip = "Draw a coloured border around each item: quality colours for gear, yellow for quest items, cyan for consumables, red for grey junk.",
        get = function() return CommanderVaultDB.ColorCodeItems end,
        set = function(value) CommanderVaultDB.ColorCodeItems = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Rarity Halo",
        tooltip = "A faint second ring inside the border in the same colour, so an epic reads as a glow rather than a hairline.",
        get = function() return CommanderVaultDB.RarityHalo end,
        set = function(value) CommanderVaultDB.RarityHalo = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault and CommanderVaultDB.ColorCodeItems end,
    })
    panel:AddSlider({
        label = "Border Thickness",
        tooltip = "How heavy the quality border is drawn, in pixels.",
        min = 1, max = 4, step = 1,
        format = function(value) return string.format("%d px", value) end,
        get = function() return CommanderVaultDB.BorderThickness end,
        set = function(value) CommanderVaultDB.BorderThickness = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault and CommanderVaultDB.ColorCodeItems end,
    })
    panel:AddDropdown({
        label = "Bind Badges",
        tooltip = "Soulbound & BoE badges both states so nothing is ambiguous. BoE only marks the items you have not bound yet. Off hides them.",
        options = BIND_BADGES,
        width = 140,
        get = function() return CommanderVaultDB.BindBadges end,
        set = function(value) CommanderVaultDB.BindBadges = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddCheckboxPair({
        label = "Show Item Level",
        tooltip = "Print the item level in the corner of anything equippable, so bank gear can be compared without a tooltip each.",
        get = function() return CommanderVaultDB.ShowItemLevel end,
        set = function(value) CommanderVaultDB.ShowItemLevel = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Focus Search on Open",
        tooltip = "Put the cursor in the search box the moment the vault opens, so a visit can be one word and a glance.",
        get = function() return CommanderVaultDB.AutoFocusSearch end,
        set = function(value) CommanderVaultDB.AutoFocusSearch = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })

    panel:AddSection("Everywhere Else",
        "Every character who has stood at a banker while this module was running leaves a snapshot behind, which is what lets an item tooltip anywhere in the game answer \"you already own four of these, and three of them are on your alt\" — before you buy a fifth.")
    panel:AddDropdownPair({
        label = "Tooltip Counts",
        tooltip = "Add a count to every item tooltip in the game. Vault and alts names the characters holding the rest; This vault only keeps it to what you own here; Off adds nothing.",
        options = TOOLTIP_MODES,
        width = 140,
        get = function() return CommanderVaultDB.TooltipCounts end,
        set = function(value) CommanderVaultDB.TooltipCounts = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Sort Order",
        tooltip = "Category follows the vault's own sections. Quality puts epics first and junk last. Item Level puts the strongest gear first. Vendor Value puts the money first.",
        options = SORT_ORDERS,
        width = 140,
        get = function() return CommanderVaultDB.SortOrder end,
        set = function(value) CommanderVaultDB.SortOrder = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddCheckboxPair({
        label = "Count Your Bags Too",
        tooltip = "Add a Bags line to the tooltip alongside the Vault line. Off by default — the stack count under the icon already half-answers that one.",
        get = function() return CommanderVaultDB.TooltipCarried end,
        set = function(value) CommanderVaultDB.TooltipCarried = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault and CommanderVaultDB.TooltipCounts ~= "OFF" end,
    }, {
        label = "Track the Guild Bank",
        tooltip = "Remember whichever guild bank tab you open, so tooltips can say the guild already has one. Nothing is ever deposited or withdrawn, and no tab is read unless you open it or ask for a full sweep.",
        get = function() return CommanderVaultDB.TrackGuildBank end,
        set = function(value) CommanderVaultDB.TrackGuildBank = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddCheckboxPair({
        label = "This Realm Only",
        tooltip = "Count only characters on the realm you are playing on. Off counts every character in the file, which is honest but rarely actionable.",
        get = function() return CommanderVaultDB.RosterCurrentRealmOnly end,
        set = function(value) CommanderVaultDB.RosterCurrentRealmOnly = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })

    panel:AddSection("The Report",
        "What the vault has to say back: grey items and their value, gear you cannot wear, stacks split across slots, recipes you already know, and anything that has been sitting here since the expansion before last. Clicking a line filters the grid to exactly those items.")
    panel:AddCheckboxPair({
        label = "Show the Report",
        tooltip = "Offer the report tab in the vault window. Off leaves the grid alone.",
        get = function() return CommanderVaultDB.ShowAdvisor end,
        set = function(value) CommanderVaultDB.ShowAdvisor = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    }, {
        label = "Track Dwell Time",
        tooltip = "Remember when each item first arrived in the vault, which is the only way anything can answer how long it has been there. Off disables the stale check.",
        get = function() return CommanderVaultDB.TrackDwell end,
        set = function(value) CommanderVaultDB.TrackDwell = value end,
        isEnabled = function() return CommanderVaultDB.EnableVault end,
    })
    panel:AddButtonRow({
        {
            label = "Open Vault",
            width = 110,
            tooltip = "Open the vault window. Away from a banker it shows the last remembered snapshot.",
            onClick = function()
                if CommanderVault_Toggle then CommanderVault_Toggle(true) end
            end,
        },
        {
            label = "Print Report",
            width = 110,
            tooltip = "Write the report to chat.",
            onClick = function()
                if CommanderVault_PrintReport then CommanderVault_PrintReport() end
            end,
        },
        {
            label = "Reset Size",
            width = 110,
            tooltip = "Put the window back to the size the Columns slider asks for, undoing anything the corner grip did. Shift-clicking the grip itself does the same thing.",
            onClick = function()
                CommanderVaultDB.FrameW, CommanderVaultDB.FrameH = nil, nil
                Commander.Notify(COMMANDER_VAULT_EVENTS.UPDATE)
            end,
        },
        {
            label = "Forget Snapshot",
            width = 130,
            tooltip = "Discard the remembered contents of this character's vault. The next visit to a banker records it again.",
            onClick = function()
                local record = CommanderVault.CharRecord and CommanderVault.CharRecord(false)
                if record then
                    record.items, record.seen, record.at = nil, nil, nil
                end
                Commander.Notify(COMMANDER_VAULT_EVENTS.UPDATE)
                print("Commander Vault: snapshot forgotten — right-click a character in the Roster view to forget an alt")
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so the
        -- defaults have to be applied here rather than at file scope
        if addonName == "Commander_Vault" then
            CommanderVaultDB = CommanderVaultDB or {}
            CommanderVaultCache = CommanderVaultCache or {}
            Commander.UI.ApplyDefaults(CommanderVaultDB, DefaultSettings)
            -- Moving a default only reaches NEW databases: ApplyDefaults fills
            -- missing keys and never overwrites, so every existing install
            -- keeps carrying the old default it was handed. That is right for
            -- a setting someone chose and wrong for one nobody ever saw, and
            -- Grouping was the second: Detailed was there from the start and
            -- undiscoverable, because the only thing pointing at it was a
            -- dropdown already showing a reasonable answer.
            --
            -- So the old default is moved exactly once, and only from the
            -- value it used to be. A player who genuinely prefers Sections
            -- sets it back and it stays set back -- the flag has already been
            -- written and this never runs again.
            if not CommanderVaultDB.GroupingDefaultMoved then
                CommanderVaultDB.GroupingDefaultMoved = true
                if CommanderVaultDB.Grouping == "SECTION" then
                    CommanderVaultDB.Grouping = "DETAIL"
                end
            end
            -- Kept OUT of DefaultSettings on purpose (the Quartermaster
            -- watchlist precedent): Restore Defaults resets options, and the
            -- sections the player authored are their data, not an option
            CommanderVaultDB.ItemSection = CommanderVaultDB.ItemSection or {}
            CommanderVaultDB.SectionOrder = CommanderVaultDB.SectionOrder or {}
        end
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

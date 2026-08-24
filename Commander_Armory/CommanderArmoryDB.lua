-- CommanderArmoryDB.lua
--
-- Owns the two saved variables and the settings page, and nothing else.
-- CommanderArmoryDB is settings: exactly the options drawn on the panel below.
-- CommanderArmorySets is prized state -- the gear sets the player authored by
-- hand, the bank snapshot taken the last time they stood at a bank, and the
-- flyout items they chose to hide. The split is the whole reason Restore
-- Defaults is a safe button to press: ResetToDefaults iterates DefaultSettings,
-- so it can only touch keys named there, and no set is ever named there.
--
-- This file deliberately owns NO behaviour. No frames past the settings canvas,
-- no equipment API, no event handling past ADDON_LOADED and PLAYER_LOGIN, no
-- reads of the engine. Every button and every slash subcommand dispatches to a
-- CommanderArmory_* global defined in one of the other files, called behind an
-- existence check, so that a load-order accident costs a feature instead of
-- throwing an error into the player's chat frame at login.
--
-- The one constraint that shaped it: a set belongs to one character, and the
-- suite has no per-character SavedVariables file anywhere. Everything is
-- account-wide and keyed "<realm>\001<name>" (the Quartermaster ledger
-- precedent), which is why CommanderArmory_CharKey and CommanderArmory_CharStore
-- live down here with the storage rather than up in the engine.

CommanderArmoryDB = _G.CommanderArmoryDB or {}
-- Second saved variable: sets, the bank cache and the hidden-item list, kept
-- apart from settings so restoring settings can never cost the player a kit
-- they spent an evening assembling (the Quartermaster/Dossier precedent).
CommanderArmorySets = _G.CommanderArmorySets or {}

COMMANDER_ARMORY_EVENTS = {
    UPDATE = "COMMANDER_ARMORY_UPDATE"
}

-- ---------------------------------------------------------------------------
-- Schema versioning: the Meters ladder. MIGRATIONS[n] migrates n -> n+1 and
-- runs in order. DBVersion is deliberately NOT a default, because Restore
-- Defaults would otherwise stamp the database back to version 1 and re-run
-- every migration on the next login.
-- ---------------------------------------------------------------------------

local DB_VERSION = 1
local MIGRATIONS = {}

local function Migrate(db)
    local v = tonumber(db.DBVersion) or DB_VERSION
    while v < DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
    end
    db.DBVersion = DB_VERSION
end

local DefaultSettings = {
    EnableArmory = true,

    -- Character panel: four independent surfaces, because a player who wants
    -- the flyouts may well not want a sixth tab, and vice versa.
    ShowSlotFlyouts = true,
    ShowArmoryTab = true,
    ShowIgnoreMarkers = true,   -- shown whenever a set is selected, not only in edit mode
    ShowSetOnTooltip = true,

    -- Flyout
    FlyoutSort = "ILVL",        -- ILVL | QUALITY | NAME | SCORE (SCORE needs Pawn)
    FlyoutMinQuality = 0,       -- 0 Poor .. 4 Epic; 0 shows everything
    FlyoutShowBank = true,      -- list cached bank rows, greyed and unequippable
    FlyoutColumns = 5,
    FlyoutMaxRows = 4,

    -- Equipping
    CombatQueue = true,
    AutoConfirmBoE = false,     -- opt-in: a bind is permanent, a partial set is not
    AnnounceSwaps = true,
    WarnBroken = true,
    CaptureCosmetic = false,    -- shirt and tabard stay hands-off unless asked for

    -- Appearance: baked into the frames at login, so both ask for a /reload.
    AccentColor = "AMBER",      -- AMBER | CYAN | GREEN | RED | WHITE, or any
                                -- Commander_Console suite tint; unknown keys
                                -- fall back to amber
    TextSize = 11,              -- 10 | 11 | 12
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Say(message)
    print("|cff66ccffCommander Armory|r: " .. message)
end

local function Complain(message)
    print("|cff66ccffCommander Armory|r: |cffff4433" .. message .. "|r")
end

-- ---------------------------------------------------------------------------
-- The per-character store
-- ---------------------------------------------------------------------------
-- Sets belong to a character; the suite's saved variables are all account-wide.
-- The reconciliation everywhere in the suite is a composite key, and \001 is
-- the separator because no realm or character name can contain it, so the key
-- can never be ambiguous the way "Realm-Name" is on a realm with a hyphen.

function CommanderArmory_CharKey()
    return ((GetRealmName and GetRealmName()) or "Unknown")
        .. "\001" .. ((UnitName and UnitName("player")) or "Unknown")
end

-- Lazily creates this character's store and hands it back fully formed. Three
-- other files call this on paths where a nil sub-table would be a crash rather
-- than a missing feature, so each of the three is repaired independently: a
-- store written by an older build, or one hand-edited in the .lua, can be
-- missing exactly one of them.
function CommanderArmory_CharStore()
    CommanderArmorySets.Chars = CommanderArmorySets.Chars or {}
    local key = CommanderArmory_CharKey()
    local store = CommanderArmorySets.Chars[key]
    if not store then
        store = {}
        CommanderArmorySets.Chars[key] = store
    end
    store.sets = store.sets or {}
    store.bank = store.bank or {}
    store.bank.items = store.bank.items or {}
    store.bank.at = store.bank.at or 0
    store.hidden = store.hidden or {}
    return store
end

-- ---------------------------------------------------------------------------
-- Destructive action: confirmation first
-- ---------------------------------------------------------------------------
-- A KEY is added to StaticPopupDialogs; the table is never assigned. Assigning
-- the whole table taints it, and a tainted StaticPopupDialogs has already cost
-- this suite a bug where the player could not log out without a /reload (the
-- story is written out at length in CommanderDossier.lua). Writing one key
-- taints only that key, which nothing but our own dialog ever reads.
-- FrameXML always defines the table; the guard is for the offline harness.
--
-- The dialog lives here rather than in the host because THIS file owns the
-- storage: CommanderArmory_WipeSets does the clearing and the UI teardown, but
-- if it never loaded we can still honour the player's request ourselves.
if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_ARMORY_WIPE"] = {
        text = "Delete every Commander Armory gear set saved on this character?\n\nThe bank cache and the hidden-item list go with them. This cannot be undone. Your settings are not affected.",
        button1 = "Wipe",
        button2 = "Cancel",
        OnAccept = function()
            -- The host's wipe announces itself, so saying it again here printed
            -- two near-identical lines and made a destructive action look like
            -- it had happened twice. Only the fallback path -- which exists for
            -- a load order where the host file never arrived -- speaks.
            if CommanderArmory_WipeSets then
                CommanderArmory_WipeSets()
                Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
                return
            end
            local store = CommanderArmory_CharStore()
            store.sets = {}
            store.bank = { items = {}, at = 0 }
            store.hidden = {}
            Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
            Say("every set on this character has been deleted.")
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local function Reset()
    -- ResetToDefaults bypasses the widgets' set() closures, so the two
    -- bake-at-login options have to issue their reload hint from here.
    local needsReload = CommanderArmoryDB.AccentColor ~= DefaultSettings.AccentColor
        or CommanderArmoryDB.TextSize ~= DefaultSettings.TextSize
    Commander.UI.ResetToDefaults(CommanderArmoryDB, DefaultSettings)
    Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
    print("|cff66ccffCommander Armory|r: settings restored to defaults (your sets are untouched)")
    if needsReload then
        print("|cff66ccffCommander Armory|r: appearance change applies after /reload")
    end
end

local function Enabled()
    return CommanderArmoryDB.EnableArmory
end

local function FlyoutsEnabled()
    return CommanderArmoryDB.EnableArmory and CommanderArmoryDB.ShowSlotFlyouts
end

-- ---------------------------------------------------------------------------
-- Slash dispatch
-- ---------------------------------------------------------------------------
-- Finalize builds SlashCmdList itself and dispatches on an EXACT match of the
-- lowercased, trimmed message against the handler table. "/cgear equip arena"
-- is therefore one string, "equip arena", and no fixed key can ever match it.
--
-- Rather than register our own SlashCmdList entry behind the framework's back,
-- we give the handler table an __index that parses "<verb> <argument>" and
-- returns a closure over the argument. The framework's own lookups are
-- unchanged: it reads handlers[""], handlers.reset and handlers.settings, none
-- of which contain a space, so __index returns nil for all three and the
-- auto-wiring behaves exactly as it does for every other module. pairs() in
-- Lua 5.1 ignores __index, so the usage line still lists only the real keys --
-- which is why "equip" and "save" are also registered bare, both to appear in
-- that line and to answer "/cgear equip" with the argument they need.
--
-- Note the argument arrives LOWERCASED by the framework. Set-name lookup on the
-- other side of these calls must therefore be case-insensitive.

local ARG_HANDLERS = {
    equip = function(name)
        if CommanderArmory_EquipSetByName then
            CommanderArmory_EquipSetByName(name)
        else
            Complain("the Armory has not finished loading.")
        end
    end,
    save = function(name)
        if CommanderArmory_SaveSetByName then
            CommanderArmory_SaveSetByName(name)
        else
            Complain("the Armory has not finished loading.")
        end
    end,
}

local slashHandlers = {
    [""] = function()
        if CommanderArmory_Toggle then CommanderArmory_Toggle() end
    end,
    equip = function() Say("usage: /cgear equip <set name>") end,
    save = function() Say("usage: /cgear save <set name>") end,
    list = function()
        if CommanderArmory_ListSets then
            CommanderArmory_ListSets()
        else
            Complain("the Armory has not finished loading.")
        end
    end,
    wipe = function()
        if StaticPopup_Show then StaticPopup_Show("COMMANDER_ARMORY_WIPE") end
    end,
}

setmetatable(slashHandlers, {
    __index = function(_, message)
        local verb, argument = tostring(message):match("^(%a+)%s+(.+)$")
        local handler = verb and ARG_HANDLERS[verb]
        if not handler then return nil end
        return function() handler(argument) end
    end,
})

-- The chrome block and five feature sections push this page well past the
-- Settings canvas, so its rows flow into a scroll frame -- AddRow overridden on
-- the panel INSTANCE only (the Reticle/Quartermaster/Meters/Dossier pattern),
-- never on the shared framework. Returns the closure to call once Finalize has
-- added the footer row.
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

local RELOAD_NOTE = "Takes effect after /reload (baked into the frames at login)."

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Armory",
        title = "Armory",
        addonName = "Commander_Armory",
        description = "The equipment manager this client never shipped. Every paperdoll slot gets a popout listing every item that could go there — bags, bank, or another equipped slot — sorted by item level rather than by where it happens to sit in your bags. Named sets swap a whole kit, and check the whole plan before touching anything: if a piece is missing, or in your bank, or you are two bag slots short, it says so and equips nothing rather than leaving you half-dressed. Slots you mark hands-off stay exactly as they are, which is what makes a two-piece hit-cap swap a set rather than a chore.",
        event = COMMANDER_ARMORY_EVENTS.UPDATE,
        slash = { "/cgear", "/carmory" },
        slashHandlers = slashHandlers,
    })
    local finishScroll = MakeScrollable(panel, "CommanderArmoryPanelScroll")

    panel:AddSection("Armory",
        "Your gear sets live in their own saved file, keyed to this character on this realm, separate from every option on this page. Restore Defaults at the bottom never touches them — only Wipe All Sets does.")

    panel:AddCheckbox({
        label = "Enable Armory",
        tooltip = "Master switch. Off retires the character-panel tab, the slot popouts, the tooltip lines and the combat queue, and stops the bank cache updating. Every set you have saved is kept — this puts the module away, it does not forget anything.",
        get = function() return CommanderArmoryDB.EnableArmory end,
        set = function(value) CommanderArmoryDB.EnableArmory = value end,
    })

    panel:AddSection("Character Panel",
        "Everything here is added to Blizzard's character sheet; nothing of theirs is replaced, re-anchored or hidden. TBC ships no equipment manager UI at all, so each surface below is one we draw ourselves, and turning one off simply removes it.")

    panel:AddCheckboxPair({
        label = "Slot Popouts",
        tooltip = "Put a popout arrow on every paperdoll slot. Clicking one lists everything that could go in that slot and equips your choice in one more click — the fastest way to change a single piece without going through your bags. This is also where a slot is marked hands-off for the selected set.",
        get = function() return CommanderArmoryDB.ShowSlotFlyouts end,
        set = function(value) CommanderArmoryDB.ShowSlotFlyouts = value end,
        isEnabled = Enabled,
    }, {
        label = "Armory Tab",
        tooltip = "Add a sixth tab to the character sheet: the set manager. Save, equip, rename, re-icon and delete sets, with a slot-by-slot preview of exactly what equipping one would change and what it would leave alone.",
        get = function() return CommanderArmoryDB.ShowArmoryTab end,
        set = function(value) CommanderArmoryDB.ShowArmoryTab = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Ignore Markers",
        tooltip = "Mark the slots the selected set will leave alone whenever a set is selected — not only while you are editing it. Retail hides these the moment the manager pane closes, which is precisely why nobody there can tell what their own set is going to do.",
        get = function() return CommanderArmoryDB.ShowIgnoreMarkers end,
        set = function(value) CommanderArmoryDB.ShowIgnoreMarkers = value end,
        isEnabled = Enabled,
    }, {
        label = "Sets On Tooltips",
        tooltip = "Add a line to an item's tooltip naming the sets that ask for it — and saying \"not in any set\" when none does, because silence is not an answer when the question is whether this is safe to vendor.\n\nOnly on gear that could actually be in a set: never on reagents, potions or ammo. Cheap insurance against vendoring the boots your arena kit needs. Co-exists with Commander_Tooltip rather than replacing anything it adds.",
        get = function() return CommanderArmoryDB.ShowSetOnTooltip end,
        set = function(value) CommanderArmoryDB.ShowSetOnTooltip = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Flyout",
        "A popout lists every item that could legally occupy the slot you clicked, wherever it currently lives — bags, bank, or another equipped slot — minus the one already in it. Items you cannot use proficiently are dimmed, never hidden: a warrior levelling in mail is making a legitimate choice and an addon that hides it is wrong.")

    panel:AddDropdownPair({
        label = "Sort By",
        tooltip = "How candidates are ordered. Item level answers the question you were actually asking; Blizzard's own flyout sorts by physical bag position, which is its single worst property. Pawn Score requires Pawn to be installed and falls back to item level when it is not.",
        options = {
            { text = "Item Level", value = "ILVL" },
            { text = "Quality", value = "QUALITY" },
            { text = "Name", value = "NAME" },
            { text = "Pawn Score", value = "SCORE" },
        },
        get = function() return CommanderArmoryDB.FlyoutSort end,
        set = function(value) CommanderArmoryDB.FlyoutSort = value end,
        isEnabled = FlyoutsEnabled,
    }, {
        label = "Minimum Quality",
        tooltip = "Hide candidates below this quality. Twelve levelling greens burying the two items you actually alternate between is the reason this exists. Items you have hidden by hand are a separate list and this filter neither adds to nor overrides it.",
        options = {
            { text = "Everything", value = 0 },
            { text = "Common", value = 1 },
            { text = "Uncommon", value = 2 },
            { text = "Rare", value = 3 },
            { text = "Epic", value = 4 },
        },
        get = function() return CommanderArmoryDB.FlyoutMinQuality end,
        set = function(value) CommanderArmoryDB.FlyoutMinQuality = value end,
        isEnabled = FlyoutsEnabled,
    })

    panel:AddCheckbox({
        label = "Show Banked Items",
        tooltip = "List items we last saw in your bank, greyed and marked as banked. Nothing can be equipped straight out of the bank, so these are never clickable — but naming the bank is the difference between an instruction and a dead end, and it is the one thing every competing set manager on this client gets wrong.",
        get = function() return CommanderArmoryDB.FlyoutShowBank end,
        set = function(value) CommanderArmoryDB.FlyoutShowBank = value end,
        isEnabled = FlyoutsEnabled,
    })

    panel:AddSliderPair({
        label = "Columns",
        tooltip = "Icons per row in the popout.",
        min = 3, max = 8, step = 1,
        format = "%d",
        get = function() return CommanderArmoryDB.FlyoutColumns end,
        set = function(value) CommanderArmoryDB.FlyoutColumns = value end,
        isEnabled = FlyoutsEnabled,
    }, {
        label = "Rows",
        tooltip = "How tall a popout gets before the list starts scrolling. Wrath's flyout silently truncated at twenty-three items and told nobody; ours scrolls.",
        min = 2, max = 8, step = 1,
        format = "%d",
        get = function() return CommanderArmoryDB.FlyoutMaxRows end,
        set = function(value) CommanderArmoryDB.FlyoutMaxRows = value end,
        isEnabled = FlyoutsEnabled,
    })

    panel:AddSection("Equipping",
        "Armor cannot be swapped in combat on this client: the server refuses every slot except main hand, off hand and ranged, and the client blocks even those to anything but a keypress you make yourself. So a set is checked in full before a single item moves — if a piece is missing, banked, or you are short of bag space, nothing is equipped at all — and whatever combat, casting or death refuses is held in the queue and run the instant the restriction lifts.")

    panel:AddCheckboxPair({
        label = "Combat Queue",
        tooltip = "Hold a swap that combat, casting or death has refused, and fire it the moment the restriction lifts, instead of failing silently. The queued swap is announced, visible, and cancellable. This turns TBC's most common equipment failure — 'nothing happened' — into a scheduled action.",
        get = function() return CommanderArmoryDB.CombatQueue end,
        set = function(value) CommanderArmoryDB.CombatQueue = value end,
        isEnabled = Enabled,
    }, {
        label = "Announce Swaps",
        tooltip = "Print a line to chat for each swap: what went on, what it displaced, and anything the set could not do and why. Off leaves only the failures, which are never silent.",
        get = function() return CommanderArmoryDB.AnnounceSwaps end,
        set = function(value) CommanderArmoryDB.AnnounceSwaps = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Auto-Confirm Binding",
        tooltip = "Answer the 'this item will bind to you' dialog automatically while a set is equipping. Off pauses the run and waits for you, which is the right default — a bind is permanent and a half-finished set is not.",
        get = function() return CommanderArmoryDB.AutoConfirmBoE end,
        set = function(value) CommanderArmoryDB.AutoConfirmBoE = value end,
        isEnabled = Enabled,
    }, {
        label = "Warn On Broken Gear",
        tooltip = "Say so when a set equips something at zero durability. Broken items equip perfectly well, they simply give no stats — so this is a warning and never a refusal.",
        get = function() return CommanderArmoryDB.WarnBroken end,
        set = function(value) CommanderArmoryDB.WarnBroken = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Include Shirt And Tabard",
        tooltip = "Record the cosmetic slots when saving a set. Off leaves both marked hands-off, because somebody saving an arena kit does not mean 'and also put my guild tabard back on' — silently stripping these two is the canonical complaint about every set manager that has ever shipped.",
        get = function() return CommanderArmoryDB.CaptureCosmetic end,
        set = function(value) CommanderArmoryDB.CaptureCosmetic = value end,
        isEnabled = Enabled,
    })

    panel:AddButtonRow({
        {
            label = "Open Armory",
            tooltip = "Open the set manager. Same as /cgear.",
            onClick = function()
                if CommanderArmory_Toggle then CommanderArmory_Toggle() end
            end,
        },
        {
            label = "List Sets",
            tooltip = "Print every set saved on this character to chat, with how many slots each one touches and how many it leaves alone. Same as /cgear list.",
            onClick = function()
                if CommanderArmory_ListSets then CommanderArmory_ListSets() end
            end,
        },
    })

    panel:AddButtonRow({
        {
            label = "Wipe All Sets",
            tooltip = "Delete every set saved on this character, along with the bank cache and the hidden-item list. Asks first. This is the only thing in the module that can remove a set — Restore Defaults, below, never touches them.",
            onClick = function()
                if StaticPopup_Show then StaticPopup_Show("COMMANDER_ARMORY_WIPE") end
            end,
        },
    })

    panel:AddSection("Appearance",
        "Accent and text size are baked into the frames when they are built at login, so changing either asks for a /reload. Neither ever touches an item quality colour: quality is data, not decoration.")

    -- Accent choices: the local five, plus every suite tint published by
    -- Commander_Console (the TopBar soft-fail pattern), so the whole HUD can
    -- agree from one named palette even though nothing here depends on Console
    -- being installed.
    local accentOptions = {
        { text = "Amber", value = "AMBER" },
        { text = "Cyan", value = "CYAN" },
        { text = "Green", value = "GREEN" },
        { text = "Red", value = "RED" },
        { text = "White", value = "WHITE" },
    }
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        accentOptions[#accentOptions + 1] = {
            text = (color.text or color.value):gsub("%s*%(.-%)$", ""),
            value = color.value,
        }
    end
    do
        -- A dropdown with no option matching its value renders BLANK and drops
        -- the saved key the moment anything else is picked. So if the player
        -- saved a Console tint and then uninstalled Console, give the orphan an
        -- option of its own and say why it is not being drawn.
        local saved = CommanderArmoryDB.AccentColor
        local known = false
        for _, opt in ipairs(accentOptions) do
            if opt.value == saved then known = true end
        end
        if saved and not known then
            accentOptions[#accentOptions + 1] = {
                text = tostring(saved):sub(1, 1):upper() .. tostring(saved):sub(2):lower()
                    .. " (Commander_Console missing — shown as Amber)",
                value = saved,
            }
        end
    end

    panel:AddDropdownPair({
        label = "Accent Color",
        tooltip = "The single active colour in the chrome: headings, the selected set, the popout arrows, the ignore markers. Item quality colours and the missing/banked status colours are data and are never re-tinted. " .. RELOAD_NOTE,
        options = accentOptions,
        get = function() return CommanderArmoryDB.AccentColor end,
        set = function(value)
            if CommanderArmoryDB.AccentColor ~= value then
                CommanderArmoryDB.AccentColor = value
                print("|cff66ccffCommander Armory|r: accent change applies after /reload")
            end
        end,
        isEnabled = Enabled,
    }, {
        label = "Text Size",
        tooltip = "Base font size for the set manager and the popouts. " .. RELOAD_NOTE,
        options = {
            { text = "Small (10)", value = 10 },
            { text = "Standard (11)", value = 11 },
            { text = "Large (12)", value = 12 },
        },
        get = function() return CommanderArmoryDB.TextSize end,
        set = function(value)
            if CommanderArmoryDB.TextSize ~= value then
                CommanderArmoryDB.TextSize = value
                print("|cff66ccffCommander Armory|r: text size change applies after /reload")
            end
        end,
        isEnabled = Enabled,
    })

    -- Chrome last, per the suite convention.
    panel:AddSection("Frame",
        "Chrome for the standalone Armory window — the one /cgear opens. The character-sheet tab is drawn inside Blizzard's frame and is not affected. An unlocked window always shows, so you can place it.")
    Commander.UI.AddHudChromeOptions(panel, CommanderArmoryDB, "Hud", {
        isEnabled = Enabled,
        onChanged = function() Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE) end,
        defaultPoint = { point = "CENTER", x = 0, y = 40 },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page to its default value. Your saved gear sets are NOT touched — they live in a separate file, and only Wipe All Sets (or /cgear wipe) can remove them.",
    })
    finishScroll()
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Armory" then
        Migrate(CommanderArmoryDB)
        Commander.UI.ApplyDefaults(CommanderArmoryDB, DefaultSettings)
        -- Seeded outside DefaultSettings on purpose: ApplyDefaults would fill
        -- it just as happily, but ResetToDefaults iterates the same table and
        -- would then hand every character an empty set list.
        CommanderArmorySets.Chars = CommanderArmorySets.Chars or {}
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
    end
end)

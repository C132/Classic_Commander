CommanderActionBarDB = _G.CommanderActionBarDB or {}

COMMANDER_ACTIONBAR_EVENTS = {
    UPDATE = "COMMANDER_ACTIONBAR_UPDATE"
}

local DefaultSettings = {
    locked = true,
    showBagButtons = true,
    position = {
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 0,
        yOfs = 0
    },
    -- Grid layout
    buttonsPerRow = 6,
    buttonSize = 32,
    buttonSpacing = 10,
    gridPadding = 14,
    cardScale = 1.0,
    includeBottomLeft = true,
    includeRightBars = false,
    reverseRows = false,
    -- Card framing
    cardStyle = "CLASSIC",
    cardOpacity = 1.0,
    borderTint = "WHITE",
    combatGlow = false,
    oocFade = false,
    fadeOpacity = 0.4,
    mouseoverReveal = true,
    -- Button cosmetics
    hideMacroText = false,
    hideHotkeys = false,
    abbrevHotkeys = false,
    pushedFlash = "CYAN",
    iconRecess = "SOFT",   -- shared suite icon shading: OFF|SOFT|DEEP|CARVED
    rangeTint = false,
    manaTint = false,
    cooldownText = false,
    readyFlash = false,
    hideEmptySlots = false,
    -- Bag block, micro menu, pet bar, extras
    bagPosition = "BOTTOMRIGHT",
    bagButtonScale = 1.0,
    bagVertical = true,
    showMicroMenu = false,
    microMenuScale = 0.9,
    petBarPosition = "ABOVE",
    petBarScale = 0.7,
    showKeyring = false,
    extraBars = "DEFAULT",
    -- Numpad card (a second grid laid out like a keypad). Every key here
    -- starts with "numpad": the numpad page's Restore Defaults resets by that.
    numpadEnabled = false,
    numpadBindKeys = true,
    numpadLayout = "APPLE",        -- APPLE (Mac keypad) | STANDARD (PC)
    numpadAnchor = "RIGHT",        -- RIGHT | LEFT of the grid card, or FREE
    numpadScale = 1.0,             -- times Card Scale: 1 = the grid's own key size
    numpadPosition = {             -- only used while FREE
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 320,
        yOfs = 0,
        scale = 1,                 -- the card's scale when saved (offsets are in its units)
    },
    numpadDigitsBar = "BOTTOMRIGHT",   -- the 12 number-block keys: a whole bar
    numpadOpsBar = "LEFT",             -- operators + F16-F19: first 9 slots of a bar
    numpadNumLock = false,             -- Clear on the Mac pad
    numpadFunctionRow = false,         -- the Mac pad's F16-F19 row
    -- Function-key row (` then F1-F5, one row on top of the grid). Every key
    -- here starts with "fkey": its page's Restore Defaults resets by that.
    fkeyEnabled = false,
    fkeyBindKeys = true,
    fkeyAnchor = "ABOVE",          -- ABOVE the grid card, or FREE
    fkeyScale = 1.0,               -- times Card Scale: 1 = the grid's own key size
    fkeyPosition = {               -- only used while FREE
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 0,
        yOfs = 160,
        scale = 1,                 -- the card's scale when saved (offsets are in its units)
    },
    fkeyBar = "RIGHT",             -- the first six slots of a spare bar, ` first
    fkeyMode = "ACTIONS",          -- what F1-F5 do: ACTIONS | MARKS (raid marks) | PARTY (party, you last)
}

-- The spare bars are shared out: the numpad's number keys, its operator keys
-- and the function-key row each hold a different one, so no two blocks ever
-- draw the same slots. Choosing a bar another block holds trades with it.
local BAR_FIELDS = { "numpadDigitsBar", "numpadOpsBar", "fkeyBar" }
local function ClaimBar(field, value)
    for _, other in ipairs(BAR_FIELDS) do
        if other ~= field and CommanderActionBarDB[other] == value then
            CommanderActionBarDB[other] = CommanderActionBarDB[field]
        end
    end
    CommanderActionBarDB[field] = value
end

-- When the row lands on a bar the numpad holds (a save from before the row
-- existed, or a page's Restore Defaults), the row is the one that moves: to
-- the first bar neither numpad block holds
local SPARE_BAR_ORDER = { "RIGHT", "PAGE2", "LEFT", "BOTTOMRIGHT" }
local function SettleBars()
    local db = CommanderActionBarDB
    if db.fkeyBar ~= db.numpadDigitsBar and db.fkeyBar ~= db.numpadOpsBar then return end
    for _, bar in ipairs(SPARE_BAR_ORDER) do
        if bar ~= db.numpadDigitsBar and bar ~= db.numpadOpsBar then
            db.fkeyBar = bar
            return
        end
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderActionBarDB, DefaultSettings)
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: settings restored to defaults")
end

local function ResetPosition()
    CommanderActionBarDB.position = Commander.UI.CopyValue(DefaultSettings.position)
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
end

local function SetLocked(locked)
    CommanderActionBarDB.locked = locked
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar " .. (locked and "locked" or "unlocked"))
end

-- The numpad page resets only its own options, as its button says
local function ResetNumpad()
    for key, value in pairs(DefaultSettings) do
        if key:match("^numpad") then
            CommanderActionBarDB[key] = Commander.UI.CopyValue(value)
        end
    end
    SettleBars()
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: numpad settings restored to defaults")
end

local function ToggleNumpad()
    CommanderActionBarDB.numpadEnabled = not CommanderActionBarDB.numpadEnabled
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: numpad " .. (CommanderActionBarDB.numpadEnabled and "on" or "off"))
end

-- The function-key page resets only its own options, like the numpad's
local function ResetFKeys()
    for key, value in pairs(DefaultSettings) do
        if key:match("^fkey") then
            CommanderActionBarDB[key] = Commander.UI.CopyValue(value)
        end
    end
    SettleBars()
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: function key settings restored to defaults")
end

local function ToggleFKeys()
    CommanderActionBarDB.fkeyEnabled = not CommanderActionBarDB.fkeyEnabled
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: function key bar " .. (CommanderActionBarDB.fkeyEnabled and "on" or "off"))
end

local db = function() return CommanderActionBarDB end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBar",
        title = "Action Bar",
        addonName = "Commander_ActionBar",
        description = "Replaces the sprawling default action bars with a single compact command card: an RTS-style grid of your actions on a movable armored plate. This page shapes the card itself; button behavior, bags, and the satellite bars live on the Action Bar Buttons page, the optional numpad card beside it on Action Bar Numpad, and the optional ` F1-F5 row above it on Action Bar Function Keys.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
        slash = { "/cab" },
        slashHandlers = {
            lock = function() SetLocked(true) end,
            unlock = function() SetLocked(false) end,
            center = ResetPosition,
            numpad = ToggleNumpad,
            fkeys = ToggleFKeys,
        },
    })

    panel:AddCheckboxPair({
        label = "Lock Action Bar",
        tooltip = "Prevent the command card from being dragged. Uncheck to move it, then lock it again. /cab center recenters it.",
        get = function() return db().locked end,
        set = function(value) db().locked = value end,
    }, {
        label = "Show Bag Buttons",
        tooltip = "Master switch for the bag bar — the bag slots plus the keyring, and any backpack/reagent/expand buttons the client shows. Uncheck to hide every bag button completely. Position and scale are on the Action Bar Buttons page.",
        get = function() return db().showBagButtons end,
        set = function(value) db().showBagButtons = value end,
    })
    panel:AddSliderPair({
        label = "Buttons Per Row",
        tooltip = "Grid columns — 12 makes long thin bars, 4 makes a tall block.",
        min = 1, max = 12, step = 1,
        format = "%d",
        get = function() return db().buttonsPerRow end,
        set = function(value) db().buttonsPerRow = value end,
    }, {
        label = "Button Size",
        tooltip = "Size of each action button.",
        min = 24, max = 48, step = 1,
        format = "%d",
        get = function() return db().buttonSize end,
        set = function(value) db().buttonSize = value end,
    })
    panel:AddSliderPair({
        label = "Button Spacing",
        tooltip = "Gap between buttons.",
        min = 2, max = 20, step = 1,
        format = "%d",
        get = function() return db().buttonSpacing end,
        set = function(value) db().buttonSpacing = value end,
    }, {
        label = "Card Padding",
        tooltip = "Inner margin between the card's border and the grid.",
        min = 6, max = 28, step = 1,
        format = "%d",
        get = function() return db().gridPadding end,
        set = function(value) db().gridPadding = value end,
    })
    panel:AddSliderPair({
        label = "Card Scale",
        tooltip = "Overall size of the card and its buttons. The numpad card and the function-key row follow it; the scale on each of their pages sizes them against this.",
        min = 0.6, max = 1.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().cardScale end,
        set = function(value) db().cardScale = value end,
    }, {
        label = "Card Opacity",
        tooltip = "Opacity of the card's backdrop art.",
        min = 0.2, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().cardOpacity end,
        set = function(value) db().cardOpacity = value end,
    })
    panel:AddCheckboxPair({
        label = "Include Bottom-Left Bar",
        tooltip = "Fold MultiBarBottomLeft's 12 buttons into the grid (24 total).",
        get = function() return db().includeBottomLeft end,
        set = function(value) db().includeBottomLeft = value end,
    }, {
        label = "Include Right Bars",
        tooltip = "Also fold the two right bars into the grid (up to 48 buttons).",
        get = function() return db().includeRightBars end,
        set = function(value) db().includeRightBars = value end,
    })
    panel:AddCheckboxPair({
        label = "Reverse Rows",
        tooltip = "Row 1 at the bottom of the card, SC2 style, instead of the top.",
        get = function() return db().reverseRows end,
        set = function(value) db().reverseRows = value end,
    }, {
        label = "Combat Border Glow",
        tooltip = "The card's border turns red while you are in combat.",
        get = function() return db().combatGlow end,
        set = function(value) db().combatGlow = value end,
    })
    panel:AddDropdownPair({
        label = "Card Style",
        tooltip = "The card's framing: the classic armored plate, the suite's dark panel, or nothing at all.",
        options = {
            { text = "Classic Plate", value = "CLASSIC" },
            { text = "Dark Panel", value = "DARK" },
            { text = "None", value = "NONE" },
        },
        get = function() return db().cardStyle end,
        set = function(value) db().cardStyle = value end,
    }, {
        label = "Border Tint",
        tooltip = "Color of the card's border.",
        options = {
            { text = "White", value = "WHITE" },
            { text = "Gold", value = "GOLD" },
            { text = "Green", value = "GREEN" },
            { text = "Class Color", value = "CLASS" },
        },
        get = function() return db().borderTint end,
        set = function(value) db().borderTint = value end,
    })
    panel:AddCheckboxPair({
        label = "Fade Out of Combat",
        tooltip = "The whole card (buttons included) fades while you are out of combat.",
        get = function() return db().oocFade end,
        set = function(value) db().oocFade = value end,
    }, {
        label = "Mouseover Reveal",
        tooltip = "A faded card returns to full opacity while the mouse is over it.",
        get = function() return db().mouseoverReveal end,
        set = function(value) db().mouseoverReveal = value end,
        isEnabled = function() return db().oocFade end,
    })
    panel:AddCheckbox({
        label = "Show Keyring",
        tooltip = "Show the keyring button above the bag buttons.",
        get = function() return db().showKeyring end,
        set = function(value) db().showKeyring = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

-- Second subcategory: button behavior, bags, micro menu, pet bar, extras
local function CreateButtonsPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBarButtons",
        title = "Action Bar Buttons",
        addonName = "Commander_ActionBar",
        description = "Button-level behavior for the command card — text, tints, cooldown feedback — plus the satellite pieces: bag buttons, micro menu, pet bar, and keyring. Everything here is feature-flagged; the defaults match the classic card.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
    })

    panel:AddCheckboxPair({
        label = "Hide Macro Text",
        tooltip = "Hide the macro name text on buttons.",
        get = function() return db().hideMacroText end,
        set = function(value) db().hideMacroText = value end,
    }, {
        label = "Hide Hotkeys",
        tooltip = "Hide the keybind text on buttons.",
        get = function() return db().hideHotkeys end,
        set = function(value) db().hideHotkeys = value end,
    })
    panel:AddCheckboxPair({
        label = "Abbreviate Hotkeys",
        tooltip = "Shorten keybind text: Shift- becomes S, Ctrl- becomes C, Alt- becomes A.",
        get = function() return db().abbrevHotkeys end,
        set = function(value) db().abbrevHotkeys = value end,
        isEnabled = function() return not db().hideHotkeys end,
    }, {
        label = "Out-of-Range Tint",
        tooltip = "Tint a button's icon red while its target is out of range.",
        get = function() return db().rangeTint end,
        set = function(value) db().rangeTint = value end,
    })
    panel:AddDropdown({
        label = "Icon Recess",
        tooltip = "Shading laid over every action button's icon so it reads as set into the bar rather than pasted on it. The art is the suite's shared set, so a button here is cut the same way as an icon on any other Commander board. Soft is a shallow press; Deep and Carved drive it harder, which suits the larger button sizes.",
        options = Commander.ICON_STYLES,
        get = function() return db().iconRecess end,
        set = function(value) db().iconRecess = value end,
    })
    panel:AddCheckboxPair({
        label = "No-Resource Tint",
        tooltip = "Tint a button's icon blue when you lack the mana/energy/rage for it, grey when it is otherwise unusable.",
        get = function() return db().manaTint end,
        set = function(value) db().manaTint = value end,
    }, {
        label = "Cooldown Numbers",
        tooltip = "Numeric countdown on buttons that are on cooldown (longer than the GCD).",
        get = function() return db().cooldownText end,
        set = function(value) db().cooldownText = value end,
    })
    panel:AddCheckboxPair({
        label = "Ready Flash",
        tooltip = "A brief bright flash on a button the moment its cooldown finishes.",
        get = function() return db().readyFlash end,
        set = function(value) db().readyFlash = value end,
    }, {
        label = "Dim Empty Slots",
        tooltip = "Fade empty action slots so only real abilities stand out on the grid.",
        get = function() return db().hideEmptySlots end,
        set = function(value) db().hideEmptySlots = value end,
    })
    panel:AddDropdownPair({
        label = "Pushed Flash",
        tooltip = "Color of the press-flash on buttons. Class Color uses your class color, matching the Class border tint.",
        options = {
            { text = "Cyan", value = "CYAN" },
            { text = "Gold", value = "GOLD" },
            { text = "Green", value = "GREEN" },
            { text = "Red", value = "RED" },
            { text = "Class Color", value = "CLASS" },
        },
        get = function() return db().pushedFlash end,
        set = function(value) db().pushedFlash = value end,
    }, {
        label = "Bag Buttons",
        tooltip = "Where the four bag slot buttons live.",
        options = {
            { text = "Bottom Right", value = "BOTTOMRIGHT" },
            { text = "Bottom Left", value = "BOTTOMLEFT" },
            { text = "Beside the Card", value = "CARD" },
        },
        get = function() return db().bagPosition end,
        set = function(value) db().bagPosition = value end,
        isEnabled = function() return db().showBagButtons end,
    })
    panel:AddSliderPair({
        label = "Bag Button Scale",
        tooltip = "Size of the bag slot buttons.",
        min = 0.6, max = 1.4, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().bagButtonScale end,
        set = function(value) db().bagButtonScale = value end,
        isEnabled = function() return db().showBagButtons end,
    }, {
        label = "Micro Menu Scale",
        tooltip = "Size of the micro menu buttons when shown.",
        min = 0.6, max = 1.2, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().microMenuScale end,
        set = function(value) db().microMenuScale = value end,
        isEnabled = function() return db().showMicroMenu end,
    })
    panel:AddCheckboxPair({
        label = "Stack Bags Vertically",
        tooltip = "Bag buttons stack in a column instead of a row.",
        get = function() return db().bagVertical end,
        set = function(value) db().bagVertical = value end,
        isEnabled = function() return db().showBagButtons end,
    }, {
        label = "Show Micro Menu",
        tooltip = "Bring back the character/spellbook/talents/map micro buttons as a compact bottom-right cluster.",
        get = function() return db().showMicroMenu end,
        set = function(value) db().showMicroMenu = value end,
    })
    panel:AddDropdownPair({
        label = "Pet Bar",
        tooltip = "Where the pet bar sits relative to the card, or hide it entirely. Above the Card moves up past the function-key row when that is docked on top.",
        options = {
            { text = "Above the Card", value = "ABOVE" },
            { text = "Left of the Card", value = "LEFT" },
            { text = "Hidden", value = "HIDDEN" },
        },
        get = function() return db().petBarPosition end,
        set = function(value) db().petBarPosition = value end,
    }, {
        label = "Extra Bars",
        tooltip = "The action bars the grid does not fold in — the bottom-right bar, plus the two side bars when Include Right Bars is off. Leave them at their default UI position, or hide them entirely. The bar the numpad's number keys use is hidden either way while the numpad is up.",
        options = {
            { text = "Leave Default", value = "DEFAULT" },
            { text = "Hidden", value = "HIDDEN" },
        },
        get = function() return db().extraBars end,
        set = function(value) db().extraBars = value end,
    })
    panel:AddSliderPair({
        label = "Pet Bar Scale",
        tooltip = "Size of the pet bar.",
        min = 0.5, max = 1.2, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().petBarScale end,
        set = function(value) db().petBarScale = value end,
        isEnabled = function() return db().petBarPosition ~= "HIDDEN" end,
    }, {
        label = "Faded Opacity",
        tooltip = "How visible the card stays while faded out of combat (Fade Out of Combat, main page).",
        min = 0, max = 0.8, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().fadeOpacity end,
        set = function(value) db().fadeOpacity = value end,
        isEnabled = function() return db().oocFade end,
    })

    panel:Finalize({ onDefaults = Reset })
end

-- Third subcategory: the numpad card
local SPARE_BAR_OPTIONS = {
    { text = "Bottom Right Bar", value = "BOTTOMRIGHT" },
    { text = "Right Bar", value = "RIGHT" },
    { text = "Right Bar 2", value = "LEFT" },
    { text = "Action Page 2", value = "PAGE2" },
}

local function NumpadOn() return db().numpadEnabled end

local function CreateNumpadPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBarNumpad",
        title = "Action Bar Numpad",
        addonName = "Commander_ActionBar",
        description = "An optional second command card, laid out like your Mac's numeric keypad (or a PC one) and docked beside the grid: 7 8 9 above 4 5 6 above 1 2 3, 0 two keys wide, Clear = / * and the - + column where the keypad has them, and optionally the F16-F19 row on top. While it is up each key is bound to the numpad key it mirrors, so the keypad becomes a second bank of binds beside the grid's. Spacing, framing, fade and every button option follow the main card, and so does its size unless Numpad Scale says otherwise. Enter is never bound: the game cannot tell the keypad's Enter from the main one, which opens chat.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
    })

    panel:AddCheckboxPair({
        label = "Show Numpad Bar",
        tooltip = "Add the numpad card beside the command card. /cab numpad toggles it.",
        get = function() return db().numpadEnabled end,
        set = function(value) db().numpadEnabled = value end,
    }, {
        label = "Bind Numpad Keys",
        tooltip = "While the numpad is shown, each keypad key presses the button it mirrors, and the button wears that key's cap. These are override bindings: your saved key bindings are not touched, and switching this or the numpad off gives every key straight back to whatever it did before. Off, the numpad is click-only.",
        get = function() return db().numpadBindKeys end,
        set = function(value) db().numpadBindKeys = value end,
        isEnabled = NumpadOn,
    })
    panel:AddDropdownPair({
        label = "Keypad",
        tooltip = "Which keypad the card mirrors. Mac is Apple's keypad: F16-F19 on top (see F16-F19 Row), then Clear = / *, with - and + down the right. PC is the standard keypad: Num Lock / * - across the top and a tall + on the right. Each key keeps its action when you switch.",
        options = {
            { text = "Mac", value = "APPLE" },
            { text = "PC", value = "STANDARD" },
        },
        get = function() return db().numpadLayout end,
        set = function(value) db().numpadLayout = value end,
        isEnabled = NumpadOn,
    }, {
        label = "Numpad Position",
        tooltip = "Docked beside the command card, sharing its bottom edge and moving with it; or free-standing, when it drags on its own while Lock Action Bar is off. Bags placed Beside the Card and a pet bar Left of the Card step out past a docked numpad.",
        options = {
            { text = "Right of the Card", value = "RIGHT" },
            { text = "Left of the Card", value = "LEFT" },
            { text = "Free", value = "FREE" },
        },
        get = function() return db().numpadAnchor end,
        set = function(value) db().numpadAnchor = value end,
        isEnabled = NumpadOn,
    })
    panel:AddSlider({
        label = "Numpad Scale",
        tooltip = "Size of the numpad against the command card: 100% gives it the grid's own key size, and it follows Card Scale either way. Docked, it keeps sharing the card's bottom edge; free-standing, it keeps its place.",
        min = 0.5, max = 1.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().numpadScale end,
        set = function(value) db().numpadScale = value end,
        isEnabled = NumpadOn,
    })
    panel:AddDropdownPair({
        label = "Number Keys",
        tooltip = "Which bar's twelve action slots the number block uses: 1-9 are its first nine, 0 the tenth, . the eleventh, + the twelfth. That bar's own buttons are hidden while the numpad is up, since its actions live here now (unless the grid already folds that bar in). Bottom Right Bar is slots 49-60, Right Bar 25-36, Right Bar 2 37-48, Action Page 2 13-24 (the main bar's second page). Choosing the bar the operator keys or the function-key row use swaps the two.",
        options = SPARE_BAR_OPTIONS,
        get = function() return db().numpadDigitsBar end,
        set = function(value) ClaimBar("numpadDigitsBar", value) end,
        isEnabled = NumpadOn,
    }, {
        label = "Operator Keys",
        tooltip = "Which bar's first nine action slots the other keys use: / first, then *, -, =, Clear (Num Lock), and F16 to F19 as slots six to nine. The rest of that bar is left alone and its buttons stay where they are. Choosing the bar the number keys or the function-key row use swaps the two.",
        options = SPARE_BAR_OPTIONS,
        get = function() return db().numpadOpsBar end,
        set = function(value) ClaimBar("numpadOpsBar", value) end,
        isEnabled = NumpadOn,
    })
    panel:AddCheckboxPair({
        label = "Clear Key",
        tooltip = "Add the Clear key (Num Lock on a PC keypad; the game sees one key) to the card. Off by default because it is Autorun in the default bindings; with key binding on, the numpad takes it over while shown.",
        get = function() return db().numpadNumLock end,
        set = function(value) db().numpadNumLock = value end,
        isEnabled = NumpadOn,
    }, {
        label = "F16-F19 Row",
        tooltip = "Add the Mac keypad's top row, F16 to F19, to the card. Off by default: those keys often hold binds of your own (gear-set swaps and the like), and with key binding on the numpad takes them over while shown, giving them back when it is not.",
        get = function() return db().numpadFunctionRow end,
        set = function(value) db().numpadFunctionRow = value end,
        isEnabled = function() return db().numpadEnabled and db().numpadLayout == "APPLE" end,
    })

    panel:Finalize({
        onDefaults = ResetNumpad,
        defaultsTooltip = "Reset the numpad options on this page. The command card's own options are left alone.",
    })
end

-- Fourth subcategory: the function-key row
local function FKeysOn() return db().fkeyEnabled end

local function CreateFKeysPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBarFKeys",
        title = "Action Bar Function Keys",
        addonName = "Commander_ActionBar",
        description = "An optional row of keys on top of the command card: the ` key first, then F1 to F5. Six keys, so on the grid's default six columns each one sits over a column. While it is up each key is bound to the button it mirrors, the way the numpad's are, so the top-left corner of the keyboard becomes another bank of binds. F1 to F5 can instead put raid marks on your target or target your party (F1-F5 Keys). Spacing, framing, fade and every button option follow the main card, and so does its size unless Function Key Scale says otherwise. A pet bar placed Above the Card moves up past the row.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
    })

    panel:AddCheckboxPair({
        label = "Show Function Key Bar",
        tooltip = "Add the ` F1-F5 row on top of the command card. /cab fkeys toggles it.",
        get = function() return db().fkeyEnabled end,
        set = function(value) db().fkeyEnabled = value end,
    }, {
        label = "Bind Function Keys",
        tooltip = "While the row is shown, ` and F1 to F5 press the buttons they mirror, and each button wears its key's cap. These are override bindings: your saved key bindings are not touched, and switching this or the row off gives every key straight back to whatever it did before (target self and party members by default, raid marks for some). Only the bare keys are taken; Shift-F1 and the like keep what they do. Off, the row is click-only.",
        get = function() return db().fkeyBindKeys end,
        set = function(value) db().fkeyBindKeys = value end,
        isEnabled = FKeysOn,
    })
    panel:AddDropdown({
        label = "F1-F5 Keys",
        tooltip = "What F1 to F5 do (` always presses its action button). Row Actions: they press the row's action buttons. Raid Marks: F1 skull, F2 cross, F3 square, F4 moon, F5 triangle on your target, and the same key again takes it off, as the game's own raid-mark keys do; the row shows the marks, lights the one your target wears, and clicking one marks too (in a raid you need to be leader or assistant). Party Targets: they target your party in party order with you last, so the key after your last party member is you and the keys past that do nothing: solo F1 is you, in a 3v3 F1 and F2 are your partners and F3 is you, in a full party F5 is you. The row shows who each key targets. A party change mid-fight waits for combat to end before the keys move, and the row shows who they hit until then.",
        options = {
            { text = "Row Actions", value = "ACTIONS" },
            { text = "Raid Marks", value = "MARKS" },
            { text = "Party Targets", value = "PARTY" },
        },
        get = function() return db().fkeyMode end,
        set = function(value) db().fkeyMode = value end,
        isEnabled = FKeysOn,
    })
    panel:AddDropdownPair({
        label = "Function Key Position",
        tooltip = "Docked on top of the command card, its left edge on the card's and moving with it; or free-standing, when it drags on its own while Lock Action Bar is off.",
        options = {
            { text = "Above the Card", value = "ABOVE" },
            { text = "Free", value = "FREE" },
        },
        get = function() return db().fkeyAnchor end,
        set = function(value) db().fkeyAnchor = value end,
        isEnabled = FKeysOn,
    }, {
        label = "Function Key Slots",
        tooltip = "Which bar's first six action slots the row uses: ` the first, then F1 to F5 (only ` uses one while F1-F5 Keys is Raid Marks or Party Targets). The rest of that bar is left alone and its buttons stay where they are. Right Bar is slots 25-30, Right Bar 2 37-42, Bottom Right Bar 49-54, Action Page 2 13-18. Choosing a bar the numpad uses swaps the two.",
        options = SPARE_BAR_OPTIONS,
        get = function() return db().fkeyBar end,
        set = function(value) ClaimBar("fkeyBar", value) end,
        isEnabled = FKeysOn,
    })
    panel:AddSlider({
        label = "Function Key Scale",
        tooltip = "Size of the row against the command card: 100% gives it the grid's own key size, so each key sits over a grid column, and it follows Card Scale either way. Docked, it stays on the card's top edge; free-standing, it keeps its place.",
        min = 0.5, max = 1.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return db().fkeyScale end,
        set = function(value) db().fkeyScale = value end,
        isEnabled = FKeysOn,
    })

    panel:Finalize({
        onDefaults = ResetFKeys,
        defaultsTooltip = "Reset the function-key options on this page. The command card's own options and the numpad's are left alone; if the row's default bar is one the numpad holds, the row takes the first free one instead.",
    })
end

-- Set when a bag button update is skipped due to combat lockdown; applied on
-- PLAYER_REGEN_ENABLED
local pendingBagButtonUpdate = false

local function ApplyBagButtonVisibility()
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:SetShown(CommanderActionBarDB.showBagButtons)
        end
    end
end

local function OnUpdate()
    -- CharacterBag0-3Slot are protected; SetShown on them during combat
    -- lockdown trips ADDON_ACTION_BLOCKED, so defer until combat ends
    if InCombatLockdown() then
        pendingBagButtonUpdate = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ApplyBagButtonVisibility()
    end
end

local function OnAwake()
    CreateOptionsPanel()
    CreateButtonsPanel()
    CreateNumpadPanel()
    CreateFKeysPanel()
    Commander.AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnUpdate)
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        if addonName == "Commander_ActionBar" then
            CommanderActionBarDB = CommanderActionBarDB or {}
            Commander.UI.ApplyDefaults(CommanderActionBarDB, DefaultSettings)
            -- Retired option: the stance bar is Blizzard's again
            CommanderActionBarDB.showStanceBar = nil
            -- A save from before the row may have the numpad on its default bar
            SettleBars()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    elseif event == "PLAYER_REGEN_ENABLED" then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingBagButtonUpdate then
            pendingBagButtonUpdate = false
            ApplyBagButtonVisibility()
        end
    end
end

frame:SetScript("OnEvent", OnEvent)

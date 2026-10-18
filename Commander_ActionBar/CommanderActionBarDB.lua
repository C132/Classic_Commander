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
    numpadLayout = "STANDARD",     -- STANDARD (PC) | APPLE (extended Mac keypad)
    numpadAnchor = "RIGHT",        -- RIGHT | LEFT of the grid card, or FREE
    numpadPosition = {             -- only used while FREE
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 320,
        yOfs = 0
    },
    numpadDigitsBar = "BOTTOMRIGHT",   -- the 12 number-block keys: a whole bar
    numpadOpsBar = "LEFT",             -- the operators: first 5 slots of a bar
    numpadNumLock = false,
}

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
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: numpad settings restored to defaults")
end

local function ToggleNumpad()
    CommanderActionBarDB.numpadEnabled = not CommanderActionBarDB.numpadEnabled
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    print("Commander Action Bar: numpad " .. (CommanderActionBarDB.numpadEnabled and "on" or "off"))
end

local db = function() return CommanderActionBarDB end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBar",
        title = "Action Bar",
        addonName = "Commander_ActionBar",
        description = "Replaces the sprawling default action bars with a single compact command card: an RTS-style grid of your actions on a movable armored plate. This page shapes the card itself; button behavior, bags, and the satellite bars live on the Action Bar Buttons page, and the optional numpad card beside it on Action Bar Numpad.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
        slash = { "/cab" },
        slashHandlers = {
            lock = function() SetLocked(true) end,
            unlock = function() SetLocked(false) end,
            center = ResetPosition,
            numpad = ToggleNumpad,
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
        tooltip = "Overall size of the card and its buttons.",
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
        tooltip = "Where the pet bar sits relative to the card, or hide it entirely.",
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
local NUMPAD_BAR_OPTIONS = {
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
        description = "An optional second command card, laid out like your numeric keypad and docked beside the grid: 7 8 9 across the top, 1 2 3 at the bottom, 0 two keys wide, the operators where the keypad has them. While it is up each key is bound to the numpad key it mirrors, so the keypad becomes a second bank of binds beside the grid's. Size, spacing, framing, fade and every button option follow the main card. Enter is never bound: the game cannot tell the keypad's Enter from the main one, which opens chat.",
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
        tooltip = "Which keypad the card mirrors. Standard is the PC keypad: Num Lock / * - across the top and a tall + on the right. Apple Extended is the Mac keypad: Clear = / * across the top, with - and + down the right.",
        options = {
            { text = "Standard", value = "STANDARD" },
            { text = "Apple Extended", value = "APPLE" },
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
    panel:AddDropdownPair({
        label = "Number Keys",
        tooltip = "Which bar's twelve action slots the number block uses: 1-9 are its first nine, 0 the tenth, . the eleventh, + the twelfth. That bar's own buttons are hidden while the numpad is up, since its actions live here now (unless the grid already folds that bar in). Bottom Right Bar is slots 49-60, Right Bar 25-36, Right Bar 2 37-48, Action Page 2 13-24 (the main bar's second page). Choosing the operator keys' bar swaps the two.",
        options = NUMPAD_BAR_OPTIONS,
        get = function() return db().numpadDigitsBar end,
        set = function(value)
            if value == db().numpadOpsBar then db().numpadOpsBar = db().numpadDigitsBar end
            db().numpadDigitsBar = value
        end,
        isEnabled = NumpadOn,
    }, {
        label = "Operator Keys",
        tooltip = "Which bar's first five action slots the operator keys use: / first, then *, -, = and Num Lock. The rest of that bar is left alone and its buttons stay where they are. Choosing the number keys' bar swaps the two.",
        options = NUMPAD_BAR_OPTIONS,
        get = function() return db().numpadOpsBar end,
        set = function(value)
            if value == db().numpadDigitsBar then db().numpadDigitsBar = db().numpadOpsBar end
            db().numpadOpsBar = value
        end,
        isEnabled = NumpadOn,
    })
    panel:AddCheckbox({
        label = "Num Lock Key",
        tooltip = "Add the Num Lock key (Clear on an Apple keypad) to the card. Off by default because it is Autorun in the default bindings; with key binding on, the numpad takes it over while shown.",
        get = function() return db().numpadNumLock end,
        set = function(value) db().numpadNumLock = value end,
        isEnabled = NumpadOn,
    })

    panel:Finalize({
        onDefaults = ResetNumpad,
        defaultsTooltip = "Reset the numpad options on this page. The command card's own options are left alone.",
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

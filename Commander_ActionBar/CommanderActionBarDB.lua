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
    showStanceBar = false,
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

local db = function() return CommanderActionBarDB end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBar",
        title = "Action Bar",
        addonName = "Commander_ActionBar",
        description = "Replaces the sprawling default action bars with a single compact command card: an RTS-style grid of your actions on a movable armored plate. This page shapes the card itself; button behavior, bags, and the satellite bars live on the Action Bar Buttons page.",
        event = COMMANDER_ACTIONBAR_EVENTS.UPDATE,
        slash = { "/cab" },
        slashHandlers = {
            lock = function() SetLocked(true) end,
            unlock = function() SetLocked(false) end,
            center = ResetPosition,
        },
    })

    panel:AddCheckboxPair({
        label = "Lock Action Bar",
        tooltip = "Prevent the command card from being dragged. Uncheck to move it, then lock it again. /cab center recenters it.",
        get = function() return db().locked end,
        set = function(value) db().locked = value end,
    }, {
        label = "Show Bag Buttons",
        tooltip = "Show the four bag slot buttons (position and scale on the Action Bar Buttons page).",
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
    panel:AddCheckboxPair({
        label = "Show Keyring",
        tooltip = "Show the keyring button above the bag buttons.",
        get = function() return db().showKeyring end,
        set = function(value) db().showKeyring = value end,
    }, {
        label = "Show Stance Bar",
        tooltip = "Un-park the stance/shapeshift bar and place it above the card.",
        get = function() return db().showStanceBar end,
        set = function(value) db().showStanceBar = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

-- Second subcategory: button behavior, bags, micro menu, pet bar, extras
local function CreateButtonsPanel()
    local panel = Commander.UI.NewPanel({
        key = "ActionBarButtons",
        title = "Action Bar Buttons",
        addonName = "Commander_ActionBar",
        description = "Button-level behavior for the command card — text, tints, cooldown feedback — plus the satellite pieces: bag buttons, micro menu, pet bar, keyring, and stance bar. Everything here is feature-flagged; the defaults match the classic card.",
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
        tooltip = "Color of the press-flash on buttons.",
        options = {
            { text = "Cyan", value = "CYAN" },
            { text = "Gold", value = "GOLD" },
            { text = "Green", value = "GREEN" },
            { text = "Red", value = "RED" },
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
    }, nil)
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
    Commander.AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnUpdate)
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        if addonName == "Commander_ActionBar" then
            CommanderActionBarDB = CommanderActionBarDB or {}
            Commander.UI.ApplyDefaults(CommanderActionBarDB, DefaultSettings)
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

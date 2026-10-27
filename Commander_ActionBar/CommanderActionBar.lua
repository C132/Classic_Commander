local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
-- PLAYER_STARTED/STOPPED_MOVING deliberately NOT registered: each one ran a
-- full unthrottled cosmetics pass, multiplying every per-tick allocation on
-- top of the 0.25s poll — which already refreshes everything within 250ms
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Re-apply deferred layout after combat (protected frames are locked in combat)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
local loaded = false
local inCombat = false

local backdrop
-- The optional numpad card and its buttons (see "Numpad card" below). Declared
-- up here because the bag, pet-bar, framing and fade passes all read them.
local numpadCard
local numpadButtons = {}   -- every numpad button ever created, in NUMPAD_KEY_ORDER
local numpadByKey = {}     -- binding key name -> button
-- The function-key row on top of the grid (see "Function-key row" below):
-- the same three pieces, read by the same passes
local fkeyCard
local fkeyButtons = {}     -- in FKEY_ROW order
local fkeyByKey = {}
local fkeyMarkFaces = {}   -- F key -> its raid-mark face (fkeyMode MARKS)
local fkeyPartyFaces = {}  -- F key -> its party-seat face (fkeyMode PARTY)
-- The F1-F5 mode the row's faces show now. LayoutFKeys sets it, out of
-- combat only, so a mode chosen mid-fight is not drawn (or seated) until
-- the faces have actually swapped.
local fkeyShownMode
-- Both keyed cards once built, for the passes that treat them alike
local keyCards = {}
-- Set when a layout pass is skipped due to combat lockdown; applied on PLAYER_REGEN_ENABLED
local pendingUpdate = false

local function DB()
    return CommanderActionBarDB
end

-- ---------------------------------------------------------------------------
-- Default-UI suppression
-- ---------------------------------------------------------------------------
-- Frame names for the 2.5.5 (Anniversary) client; looked up by name so a missing
-- frame is skipped instead of truncating the list.
-- NOTE: everything here must be a plain (insecure) frame whose Hide() is the raw
-- widget method. EditMode bars must NOT go in this list -- see hiddenHolder below.
local elementsToHide = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
    "StatusTrackingBarManager",
    "MainMenuBarBackpackButton", "MainMenuBarPerformanceBarFrame",
}

local microButtons = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
    "GuildMicroButton", "WorldMapMicroButton", "SocialsMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

-- The EditMode action bars can't be hidden with Hide(): they inherit
-- EditModeActionBarTemplate, so Hide() is really EditModeActionBarMixin:HideOverride,
-- which writes bar.isShownExternal and re-runs UpdateVisibility -> SetShownBase
-- (Blizzard_ActionBar/Shared/ActionBar.lua). Calling that from addon code taints
-- isShownExternal; the bar's own PLAYER_REGEN_ENABLED/DISABLED handler then reads
-- it inside UpdateVisibility during combat and trips ADDON_ACTION_BLOCKED even
-- when our call happened out of combat. Instead, park the bar under a permanently
-- hidden holder: SetParent is not overridden by the Edit Mode mixin and writes no
-- Lua state on the bar, so Blizzard's visibility code stays untainted and the bar
-- (with its secure buttons) renders and clicks nothing.
--
-- The stance bar is deliberately NOT managed here any more. Parking it was fine;
-- moving it onto the card never held against UIParent_ManageFramePositions, so the
-- Show Stance Bar feature was retired and the bar is left entirely to Blizzard.
local hiddenHolder = CreateFrame("Frame", nil, UIParent)
hiddenHolder:Hide()

-- ---------------------------------------------------------------------------
-- Idempotent apply helpers
--
-- Everything below re-runs four times a second off the poll. That is fine for
-- reading state and wrong for writing it: on Blizzard's frames these setters
-- are not the raw widget methods. On the EditMode systems (PetActionBar) SetPoint/ClearAllPoints/Hide are the EditModeSystemMixin
-- overrides, which dirty EditModeManagerFrame; on anything living in a layout
-- container (the micro menu, the bag bar) Hide/SetShown marks the container
-- dirty. Either way Blizzard relayouts on the next frame and puts the frame
-- back where IT wants it -- and our next tick moves it again. That ping-pong,
-- not the position we pick, is what the eye sees as flicker.
--
-- So: write only when the live state is actually wrong. Reading the frame back
-- rather than caching a "we did it" flag keeps each apply idempotent in the
-- steady state AND self-healing when something genuinely moves the frame.
-- ---------------------------------------------------------------------------

-- Does the frame carry exactly the one anchor we were about to write?
local function AnchoredAt(frame, point, relTo, relPoint, x, y)
    if frame:GetNumPoints() ~= 1 then return false end
    local p, rt, rp, ox, oy = frame:GetPoint(1)
    return p == point and rt == relTo and rp == relPoint
        and math.abs((ox or 0) - x) < 0.01 and math.abs((oy or 0) - y) < 0.01
end

local function SetAnchor(frame, point, relTo, relPoint, x, y)
    if AnchoredAt(frame, point, relTo, relPoint, x, y) then return end
    frame:ClearAllPoints()
    frame:SetPoint(point, relTo, relPoint, x, y)
end

local function SetScaleIfNeeded(frame, scale)
    if frame:GetScale() ~= scale then frame:SetScale(scale) end
end

local function SetShownIfNeeded(frame, shown)
    if frame.IsShown and frame:IsShown() ~= shown then frame:SetShown(shown) end
end

-- ---------------------------------------------------------------------------
-- Getting the bar away from Blizzard's position manager
--
-- Being polite with SetPoint was never going to be enough, because we were not
-- competing with Blizzard's anchor -- we were being erased by it.
--
-- On this client (verified against the classic_anniversary UI source)
-- EditModeUtil:IsBottomAnchoredActionBar counts StanceBar and PetActionBar, but
-- EditModeManagerFrameMixin:GetBottomActionBars returns only { MainActionBar },
-- with the comment: "Classic's other bottom action bars are handled by
-- UIParent_ManageFramePositions." That manager re-parks the pet bar on its
-- own schedule, which is both why a bar sits somewhere other than the card and
-- why it flickers -- it showed at our anchor only for the instants between a
-- manager pass and our next poll.
--
-- Its opt-out is the long-standing FrameXML flag `ignoreFramePositionManager`.
-- It is the same field EditModeSystemMixin:BreakFromFrameManager sets, so it is
-- also the right flag if a future build ever routes these bars through the
-- EditMode managed-frame container instead (that container is inert here -- no
-- action bar on this client inherits UIParentManagedFrameTemplate, so
-- GetManagedFrameContainer returns nil for all of them).
--
-- Re-asserted rather than set once: ApplySystemAnchor clears the flag whenever
-- an EditMode layout is applied. In the steady state it costs one field read.
-- ---------------------------------------------------------------------------
local function ReleaseFromPositionManager(frame)
    if not frame or frame.ignoreFramePositionManager then return end
    frame.ignoreFramePositionManager = true
    -- Only meaningful on a build where these bars ARE container-managed; asking
    -- the frame keeps this correct either way instead of assuming
    if frame.GetManagedFrameContainer and frame.BreakFromFrameManager
        and frame:GetManagedFrameContainer() and not InCombatLockdown() then
        frame:BreakFromFrameManager()
    end
end

-- ---------------------------------------------------------------------------
-- Numpad card: the data
--
-- An optional second command card shaped like a numeric keypad, sitting beside
-- the grid. Its buttons draw on action slots the grid does not page, and while
-- it is shown each one is bound to the numpad key it mirrors, so the keypad
-- becomes a second bank of binds next to the grid's.
--
-- Cells are on a 4-wide keypad; w/h are spans (0 is two cells wide, + two
-- tall on the standard pad). A spanning key stays a square button, centered
-- in its span the way the keycap is. Rows nobody uses are trimmed off the
-- top, so the Mac pad without its F16-F19 row is five keys tall, not six.
--
-- ENTER is absent from both pads on purpose. The client has no NUMPADENTER:
-- the key names in the binary run NUMPAD0-9, PLUS, MINUS, MULTIPLY, DIVIDE,
-- DECIMAL and EQUALS, so the keypad's Enter IS the main Enter, and binding it
-- would take the chat box away. Its cells are left empty.
-- ---------------------------------------------------------------------------
local NUMPAD_COLS = 4

local NUMPAD_LAYOUTS = {
    -- The conventional (PC) keypad
    STANDARD = {
        { key = "NUMLOCK", col = 1, row = 1 },
        { key = "NUMPADDIVIDE", col = 2, row = 1 },
        { key = "NUMPADMULTIPLY", col = 3, row = 1 },
        { key = "NUMPADMINUS", col = 4, row = 1 },
        { key = "NUMPAD7", col = 1, row = 2 },
        { key = "NUMPAD8", col = 2, row = 2 },
        { key = "NUMPAD9", col = 3, row = 2 },
        { key = "NUMPADPLUS", col = 4, row = 2, h = 2 },
        { key = "NUMPAD4", col = 1, row = 3 },
        { key = "NUMPAD5", col = 2, row = 3 },
        { key = "NUMPAD6", col = 3, row = 3 },
        { key = "NUMPAD1", col = 1, row = 4 },
        { key = "NUMPAD2", col = 2, row = 4 },
        { key = "NUMPAD3", col = 3, row = 4 },
        { key = "NUMPAD0", col = 1, row = 5, w = 2 },
        { key = "NUMPADDECIMAL", col = 3, row = 5 },
    },
    -- The Mac keypad (Apple's Magic Keyboard with Numeric Keypad): F16-F19
    -- across the very top, then Clear (NUMLOCK to the client) = / *, with
    -- - and + down the right and a tall Enter at the bottom
    APPLE = {
        { key = "F16", col = 1, row = 1 },
        { key = "F17", col = 2, row = 1 },
        { key = "F18", col = 3, row = 1 },
        { key = "F19", col = 4, row = 1 },
        { key = "NUMLOCK", col = 1, row = 2, label = "Clr" },
        { key = "NUMPADEQUALS", col = 2, row = 2 },
        { key = "NUMPADDIVIDE", col = 3, row = 2 },
        { key = "NUMPADMULTIPLY", col = 4, row = 2 },
        { key = "NUMPAD7", col = 1, row = 3 },
        { key = "NUMPAD8", col = 2, row = 3 },
        { key = "NUMPAD9", col = 3, row = 3 },
        { key = "NUMPADMINUS", col = 4, row = 3 },
        { key = "NUMPAD4", col = 1, row = 4 },
        { key = "NUMPAD5", col = 2, row = 4 },
        { key = "NUMPAD6", col = 3, row = 4 },
        { key = "NUMPADPLUS", col = 4, row = 4 },
        { key = "NUMPAD1", col = 1, row = 5 },
        { key = "NUMPAD2", col = 2, row = 5 },
        { key = "NUMPAD3", col = 3, row = 5 },
        { key = "NUMPAD0", col = 1, row = 6, w = 2 },
        { key = "NUMPADDECIMAL", col = 3, row = 6 },
    },
}

-- What each key is: its cap label and which slot it takes. Fixed per KEY, not
-- per cell, so switching pads never moves an action from one key to another.
-- The twelve number-block keys fill one whole bar; the operators (and the Mac
-- pad's F16-F19) take the first nine slots of a second bar.
local NUMPAD_KEYS = {
    NUMPAD1 = { label = "1", block = "digits", index = 1 },
    NUMPAD2 = { label = "2", block = "digits", index = 2 },
    NUMPAD3 = { label = "3", block = "digits", index = 3 },
    NUMPAD4 = { label = "4", block = "digits", index = 4 },
    NUMPAD5 = { label = "5", block = "digits", index = 5 },
    NUMPAD6 = { label = "6", block = "digits", index = 6 },
    NUMPAD7 = { label = "7", block = "digits", index = 7 },
    NUMPAD8 = { label = "8", block = "digits", index = 8 },
    NUMPAD9 = { label = "9", block = "digits", index = 9 },
    NUMPAD0 = { label = "0", block = "digits", index = 10 },
    NUMPADDECIMAL = { label = ".", block = "digits", index = 11 },
    NUMPADPLUS = { label = "+", block = "digits", index = 12 },
    NUMPADDIVIDE = { label = "/", block = "ops", index = 1 },
    NUMPADMULTIPLY = { label = "*", block = "ops", index = 2 },
    NUMPADMINUS = { label = "-", block = "ops", index = 3 },
    NUMPADEQUALS = { label = "=", block = "ops", index = 4 },
    NUMLOCK = { label = "Num", block = "ops", index = 5 },
    F16 = { label = "F16", block = "ops", index = 6 },
    F17 = { label = "F17", block = "ops", index = 7 },
    F18 = { label = "F18", block = "ops", index = 8 },
    F19 = { label = "F19", block = "ops", index = 9 },
}
-- Creation order, so button names and the bind list come out the same every session
local NUMPAD_KEY_ORDER = {
    "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", "NUMPAD5", "NUMPAD6",
    "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPAD0", "NUMPADDECIMAL", "NUMPADPLUS",
    "NUMPADDIVIDE", "NUMPADMULTIPLY", "NUMPADMINUS", "NUMPADEQUALS", "NUMLOCK",
    "F16", "F17", "F18", "F19",
}

-- The Blizzard bars a numpad block (or the function-key row) can take: whole
-- bars only, and never the grid's own (the main bar and the bottom-left bar).
-- Action Page 2 is the main bar's second page, which only shows when the main
-- bar is paged. The settings keep the three blocks on three different bars.
local SPARE_BARS = {
    BOTTOMRIGHT = { first = 49, frame = "MultiBarBottomRight" },
    RIGHT = { first = 25, frame = "MultiBarRight" },
    LEFT = { first = 37, frame = "MultiBarLeft" },
    PAGE2 = { first = 13 },
}
local NUMPAD_BAR_DEFAULTS = { digits = "BOTTOMRIGHT", ops = "LEFT" }

local function NumpadBar(block)
    local key = (block == "digits") and DB().numpadDigitsBar or DB().numpadOpsBar
    return SPARE_BARS[key] or SPARE_BARS[NUMPAD_BAR_DEFAULTS[block]]
end

local function NumpadSlot(key)
    local spec = NUMPAD_KEYS[key]
    return NumpadBar(spec.block).first + spec.index - 1
end

local function NumpadLayout()
    return NUMPAD_LAYOUTS[DB().numpadLayout] or NUMPAD_LAYOUTS.APPLE
end

-- The keys that take something over are opt-in: Num Lock / Clear is Autorun
-- in the default bindings, and F16-F19 are where people park their own binds
-- (gear-set swaps, for one)
local FUNCTION_ROW = { F16 = true, F17 = true, F18 = true, F19 = true }
local function NumpadKeyUsed(key)
    if key == "NUMLOCK" then return DB().numpadNumLock and true or false end
    if FUNCTION_ROW[key] then return DB().numpadFunctionRow and true or false end
    return true
end

-- Is the numpad up and docked on this side of the grid? The satellites that
-- sit "beside the card" (bags right, pet bar left) move out past it.
local function NumpadAttached(side)
    return numpadCard ~= nil and numpadCard:IsShown() and DB().numpadEnabled
        and (DB().numpadAnchor or "RIGHT") == side
end

-- ---------------------------------------------------------------------------
-- Function-key row: the data
--
-- An optional third card, one row of keys on top of the grid: the ` key
-- first, then F1 to F5. Six keys, so on the grid's default six columns each
-- one sits over a column. Same mechanics as the numpad: its buttons draw on
-- slots the grid does not page, and while it is shown each one is bound to
-- the key it mirrors.
--
-- The slots are the first six of one spare bar, in row order. `name` is the
-- button-name suffix where the key itself would make a poor global name.
--
-- F1-F5 can do something other than press an action (fkeyMode): put a raid
-- mark on the target (`mark`, the order Blizzard's own RAIDTARGET binds run,
-- skull first), or target a party member (`seat`). ` always presses its
-- action.
-- ---------------------------------------------------------------------------
local FKEY_ROW = {
    { key = "`", label = "`", name = "Grave" },
    { key = "F1", label = "F1", mark = 8, seat = 1 },   -- skull
    { key = "F2", label = "F2", mark = 7, seat = 2 },   -- cross
    { key = "F3", label = "F3", mark = 6, seat = 3 },   -- square
    { key = "F4", label = "F4", mark = 5, seat = 4 },   -- moon
    { key = "F5", label = "F5", mark = 4, seat = 5 },   -- triangle
}

local function FKeySlot(index)
    return (SPARE_BARS[DB().fkeyBar] or SPARE_BARS.RIGHT).first + index - 1
end

-- Who a party seat targets: your party in the client's order (party1-4,
-- which never has gaps) with you last, so the seat right after the last
-- member is you and any seat past that targets nobody. Solo, F1 is you; in
-- a 3v3, F1 and F2 are your partners and F3 is you. Read on the poll, so
-- the unit names are built once.
local PARTY_UNITS = { "party1", "party2", "party3", "party4" }
local function PartySeatUnit(seat)
    local unit = PARTY_UNITS[seat]
    if unit and UnitExists(unit) then return unit end
    if seat == 1 or UnitExists(PARTY_UNITS[seat - 1]) then return "player" end
    return nil
end

-- Is the row up and docked on top of the grid? The pet bar, which sits above
-- the card, moves up past it.
local function FKeysAttached()
    return fkeyCard ~= nil and fkeyCard:IsShown() and DB().fkeyEnabled
        and (DB().fkeyAnchor or "ABOVE") == "ABOVE"
end

local function ApplyMicroMenu()
    if DB().showMicroMenu then
        local previous
        local scale = DB().microMenuScale or 0.9
        for _, name in ipairs(microButtons) do
            local button = _G[name]
            if button then
                SetShownIfNeeded(button, true)
                SetScaleIfNeeded(button, scale)
                if previous then
                    SetAnchor(button, "BOTTOMLEFT", previous, "BOTTOMRIGHT", 1, 0)
                else
                    SetAnchor(button, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -120, 2)
                end
                previous = button
            end
        end
    else
        for _, name in ipairs(microButtons) do
            local button = _G[name]
            if button then SetShownIfNeeded(button, false) end
        end
    end
end

-- Every bag-related frame the client might show. "Show Bag Buttons = off"
-- force-hides the whole set so nothing bag-related lingers (some are only
-- ever hidden, never repositioned, to preserve the default look when on).
-- Guarded by existence: absent frames (e.g. reagent bag on TBC) are skipped.
local BAG_ALL_FRAMES = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterReagentBag0Slot",
    "KeyRingButton",
    "BagBarExpandToggle",
}

local function ApplyBagButtons()
    -- Coerced: SetShownIfNeeded compares against IsShown's boolean, so a nil
    -- setting must arrive as false rather than as "not equal to anything"
    local show = DB().showBagButtons and true or false
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            SetShownIfNeeded(bagButton, show)
            if bagButton:IsShown() then
                SetScaleIfNeeded(bagButton, DB().bagButtonScale or 1)
                local mode = DB().bagPosition or "BOTTOMRIGHT"
                local step = DB().bagVertical and (i * 42) or 0
                local slide = DB().bagVertical and 0 or (i * 42)
                if mode == "BOTTOMLEFT" then
                    SetAnchor(bagButton, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 300 + slide, 8 + step)
                elseif mode == "CARD" and backdrop then
                    -- Beside the whole console: past the numpad when it is docked on the right
                    local card = NumpadAttached("RIGHT") and numpadCard or backdrop
                    SetAnchor(bagButton, "BOTTOMLEFT", card, "BOTTOMRIGHT", 6 + slide, 4 + step)
                else
                    SetAnchor(bagButton, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300 - slide, 8 + step)
                end
            end
        end
    end
    -- Keyring rides with the bag bar: it needs bags shown as well as its own toggle
    local keyring = _G["KeyRingButton"]
    if keyring then
        SetShownIfNeeded(keyring, show and DB().showKeyring and true or false)
        if keyring:IsShown() then
            SetAnchor(keyring, "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300, 178)
        end
    end
    -- Master off: completely hide everything bag-related, including frames the
    -- positioning code above does not touch (backpack, reagent bag, expand toggle)
    if not show then
        for _, name in ipairs(BAG_ALL_FRAMES) do
            local f = _G[name]
            if f and f.Hide and f.IsShown and f:IsShown() then f:Hide() end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Extra bars: the action bars the grid does not fold in — the bottom-right bar
-- always, plus the bottom-left bar (unless Include Bottom-Left is on) and the
-- two side bars (unless Include Right Bars is on). Leave them at their default
-- UI position, or hide them. Hiding uses the same taint-free SetParent parking
-- as described at hiddenHolder -- Hide() on these EditMode bars taints.
-- ---------------------------------------------------------------------------
local EXTRA_BARS = { "MultiBarBottomRight", "MultiBarBottomLeft", "MultiBarRight", "MultiBarLeft" }
local function BarIsGridOwned(name)
    if name == "MultiBarBottomLeft" then
        return DB().includeBottomLeft ~= false
    elseif name == "MultiBarRight" or name == "MultiBarLeft" then
        return DB().includeRightBars and true or false
    end
    return false  -- the bottom-right bar is never folded into the grid
end
-- The bar whose twelve slots the numpad's number keys took. Its actions now
-- live on the numpad, so its own buttons would only show them a second time.
-- The operator bar is NOT folded: the numpad uses at most nine of its twelve
-- slots. Nor is the function-key row's, which uses six.
local function BarIsNumpadOwned(name)
    if not DB().numpadEnabled then return false end
    return NumpadBar("digits").frame == name
end
local function ApplyExtraBars()
    local hide = (DB().extraBars == "HIDDEN")
    for _, name in ipairs(EXTRA_BARS) do
        local bar = _G[name]
        if bar then
            -- Never park a bar whose buttons the grid is actively positioning
            local gridOwned = BarIsGridOwned(name)
            if bar.__cmdOrigParent == nil then
                bar.__cmdOrigParent = bar:GetParent() or UIParent
            end
            if (hide or BarIsNumpadOwned(name)) and not gridOwned then
                if bar:GetParent() ~= hiddenHolder then
                    bar:SetParent(hiddenHolder)
                end
            elseif bar:GetParent() == hiddenHolder then
                bar:SetParent(bar.__cmdOrigParent)
            end
        end
    end
end

local function HideDefaults()
    -- Reparenting bars and the bag slots are blocked in combat; defer the
    -- whole pass to PLAYER_REGEN_ENABLED while in lockdown
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    for _, name in ipairs(elementsToHide) do
        local element = _G[name]
        -- Only when it is actually showing: several of these are members of
        -- Blizzard's bottom layout containers, and a Hide() on a member is what
        -- marks the container dirty (see the note above the anchor helpers)
        if element and element:IsShown() then
            element:Hide()
        end
    end
    -- Page number and up/down arrows live on MainActionBar now
    local pageNumber = MainActionBar and MainActionBar.ActionBarPageNumber
    if pageNumber and pageNumber:IsShown() then
        pageNumber:Hide()
    end
    ApplyMicroMenu()
    ApplyBagButtons()
    ApplyExtraBars()
end

-- ---------------------------------------------------------------------------
-- The card: framing, tint, fade
-- ---------------------------------------------------------------------------
local CARD_STYLES = {
    CLASSIC = {
        bgFile = "Interface\\BankFrame\\Bank-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    DARK = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
}

local BORDER_TINTS = {
    WHITE = { 1, 1, 1 },
    GOLD = { 1, 0.82, 0.15 },
    GREEN = { 0.3, 1, 0.4 },
}

local function BorderColor()
    if DB().combatGlow and inCombat then
        return 1, 0.25, 0.2
    end
    local tint = DB().borderTint or "WHITE"
    if tint == "CLASS" then
        local _, classToken = UnitClass("player")
        local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if color then return color.r, color.g, color.b end
    end
    local rgb = BORDER_TINTS[tint] or BORDER_TINTS.WHITE
    return rgb[1], rgb[2], rgb[3]
end

-- One framing for every card, so the numpad and the function-key row read as
-- parts of the grid
local function StyleCard(card)
    if not card then return end
    local key = DB().cardStyle or "CLASSIC"
    local style = CARD_STYLES[key]
    if card._appliedStyle ~= key then
        card._appliedStyle = key
        card:SetBackdrop(style)  -- nil clears for NONE
    end
    if style then
        local opacity = DB().cardOpacity or 1
        if key == "DARK" then
            card:SetBackdropColor(0, 0, 0, 0.7 * opacity)
        else
            card:SetBackdropColor(0.5, 0.5, 0.5, opacity)
        end
        local r, g, b = BorderColor()
        card:SetBackdropBorderColor(r, g, b, opacity)
    end
end

local function ApplyCardStyle()
    StyleCard(backdrop)
    StyleCard(numpadCard)
    StyleCard(fkeyCard)
end

-- Is the cursor carrying something a slot could take? Placing an icon is a
-- left-press-and-drag across the plate, which is the same gesture that moves
-- an unlocked card -- and the same gesture the empty-slot fade hides the
-- targets for. Both back off while this is true.
local function CursorHoldsAction()
    return GetCursorInfo and GetCursorInfo() ~= nil
end

local function SetLockState()
    -- The card is in the protected buttons' anchor family (see ApplyLayering),
    -- so EnableMouse on it is a protected call in combat: a settings change
    -- mid-fight defers this with the rest of the layout
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not DB().locked then
        backdrop:SetMovable(true)
        backdrop:EnableMouse(true)
        backdrop:RegisterForDrag("LeftButton")
        -- Not backdrop.StartMoving directly: with an icon on the cursor the
        -- drag is a drop in progress, and grabbing the card yanks the whole
        -- grid out from under it mid-gesture.
        backdrop:SetScript("OnDragStart", function(self)
            -- Nor mid-fight: Blizzard's protected buttons are anchored to
            -- the card, so StartMoving on it is blocked (the keyed cards
            -- carry the same guard)
            if CursorHoldsAction() or InCombatLockdown() then return end
            self.__cmdMoving = true
            self:StartMoving()
        end)
        backdrop:SetScript("OnDragStop", function(self)
            if not self.__cmdMoving then return end
            self.__cmdMoving = nil
            self:StopMovingOrSizing()
            local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
            DB().position = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
            Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
        end)
    else
        backdrop:SetMovable(false)
        backdrop:EnableMouse(false)
    end
end

-- Anchor the backdrop from the saved position so Reset visually restores the
-- default position without a reload
local function ApplyPosition()
    if not backdrop then return end
    backdrop:ClearAllPoints()
    if DB().position and DB().position.point then
        backdrop:SetPoint(
            DB().position.point,
            UIParent,
            DB().position.relativePoint,
            DB().position.xOfs,
            DB().position.yOfs
        )
    else
        backdrop:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function CreateRTSBackdrop()
    if backdrop then return backdrop end
    backdrop = CreateFrame("Frame", "RTSActionBarBackdrop", UIParent, "BackdropTemplate")
    -- Strata/level are not set here: ApplyLayering derives them from the live
    -- buttons and the console once both exist (see the note there)
    ApplyPosition()
    backdrop:SetSize(274, 190)
    ApplyCardStyle()
    SetLockState()
    return backdrop
end

-- ---------------------------------------------------------------------------
-- Button grid
-- ---------------------------------------------------------------------------
local managedButtons = {}

local function CollectButtons()
    wipe(managedButtons)
    for i = 1, 12 do
        managedButtons[#managedButtons + 1] = _G["ActionButton" .. i]
    end
    if DB().includeBottomLeft ~= false then
        for i = 1, 12 do
            managedButtons[#managedButtons + 1] = _G["MultiBarBottomLeftButton" .. i]
        end
    end
    if DB().includeRightBars then
        for i = 1, 12 do
            managedButtons[#managedButtons + 1] = _G["MultiBarRightButton" .. i]
        end
        for i = 1, 12 do
            managedButtons[#managedButtons + 1] = _G["MultiBarLeftButton" .. i]
        end
    end
end

local PUSHED_COLORS = {
    CYAN = { 0, 1, 1, 0.3 },
    GOLD = { 1, 0.82, 0.15, 0.35 },
    GREEN = { 0.3, 1, 0.4, 0.3 },
    RED = { 1, 0.25, 0.2, 0.35 },
}

-- r, g, b, a of the press flash, or nil for an unknown setting
local function PushedColor()
    local flashKey = DB().pushedFlash or "CYAN"
    if flashKey == "CLASS" and Commander.GetClassInfo then
        local c = Commander.GetClassInfo().color
        return c[1], c[2], c[3], 0.35
    end
    local flash = PUSHED_COLORS[flashKey]
    if flash then
        return flash[1], flash[2], flash[3], flash[4]
    end
end

-- Keep a button's art tracking its size. Classic action buttons draw their
-- slot border (the NormalTexture, UI-Quickslot2) at a FIXED ~66px anchored by
-- its CENTER, not to the button edges -- so once we shrink a button into the
-- grid the border keeps its full size, swallowing the icon (the reported
-- "buttons nearly hidden") and leaving the hover / checked highlight visibly
-- offset. Rescale the border to the button (ratio captured once at native
-- size) and pin the overlay textures so they cover the button exactly. On
-- retail-style buttons the border is edge-anchored and SetSize is ignored, so
-- this is a harmless no-op there.
local BORDER_RATIO_FALLBACK = 66 / 36
local function PinToButton(tex, button)
    if tex and tex.SetAllPoints then
        tex:ClearAllPoints()
        tex:SetAllPoints(button)
    end
end
local function NormalizeButtonArt(button, buttonSize)
    local native = button.__cmdNativeSize or 36
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        -- Capture the border/button size ratio the first time, before we have
        -- ever resized the border, so GetWidth still reports the native size
        if button.__cmdBorderRatio == nil then
            local nw = (normal.GetWidth and normal:GetWidth()) or 0
            if nw > 0 and native > 0 then
                button.__cmdBorderRatio = nw / native
            end
        end
        local ratio = button.__cmdBorderRatio or BORDER_RATIO_FALLBACK
        if normal.SetSize then
            normal:SetSize(buttonSize * ratio, buttonSize * ratio)
        end
    end
    PinToButton(button.GetHighlightTexture and button:GetHighlightTexture(), button)
    PinToButton(button.GetCheckedTexture and button:GetCheckedTexture(), button)
    PinToButton(button.GetPushedTexture and button:GetPushedTexture(), button)
end

-- ---------------------------------------------------------------------------
-- Draw order: the card sits ABOVE the Commander console art and BELOW the
-- buttons it frames.
--
-- The card used to be a flat SetFrameStrata("BACKGROUND"), which is the same
-- strata AND (both being direct UIParent children) the same frame level as
-- CAB_ConsoleBackdrop. Ties there resolve by creation order, and Commander_Console
-- loads after Commander_ActionBar, so the console's full-screen art drew over the
-- card and hid it.
--
-- Rather than hardcode a strata for the buttons -- they belong to Blizzard and
-- EditMode re-levels them -- read where they actually are and slot the card one
-- notch underneath, then clamp so it can never fall back below the console.
-- ---------------------------------------------------------------------------
local STRATA_ORDER = {
    "BACKGROUND", "LOW", "MEDIUM", "HIGH",
    "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}
local STRATA_INDEX = {}
for i, name in ipairs(STRATA_ORDER) do STRATA_INDEX[name] = i end

-- The console parents a strip frame, which parents a trim frame, so its own
-- level + 2 is still console art. Clear all of it with room to spare.
local CONSOLE_CLEARANCE = 5
-- Where to land when the buttons sit at the very bottom of their strata and we
-- have to drop a whole strata to get under them: high enough to stay over
-- anything else parked down there.
local STRATA_TOP_LEVEL = 100

-- Lowest (strata, level) among the buttons the grid owns -- the ceiling the
-- card has to stay under. nil when no buttons have been collected yet.
local function ButtonFloor()
    local floorStrata, floorLevel
    for _, button in ipairs(managedButtons) do
        if button and button.GetFrameStrata then
            local s = STRATA_INDEX[button:GetFrameStrata()] or STRATA_INDEX.MEDIUM
            local l = button:GetFrameLevel() or 1
            if not floorStrata or s < floorStrata or (s == floorStrata and l < floorLevel) then
                floorStrata, floorLevel = s, l
            end
        end
    end
    return floorStrata, floorLevel
end

-- One notch under a (strata, level): a level down in the same strata when
-- there is room, otherwise the top of the strata below. Falls back to the
-- floor of the UI when there is nowhere lower left to go.
local function OneUnder(strata, level)
    if level > 0 then
        return strata, level - 1
    elseif strata > 1 then
        return strata - 1, STRATA_TOP_LEVEL
    end
    return strata, 0
end

local function ApplyLayering()
    if not backdrop then return end
    -- The card is our own insecure frame, but MoveActionButtons anchors Blizzard's
    -- protected action buttons TO it, which pulls it into their anchor family:
    -- restacking the card restacks them, so SetFrameStrata/SetFrameLevel on it are
    -- restricted in combat exactly like a protected frame's would be. Calling them
    -- anyway is what tripped ADDON_ACTION_BLOCKED on
    -- "RTSActionBarBackdrop:SetFrameStrata()". Defer to PLAYER_REGEN_ENABLED.
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end

    local floorStrata, floorLevel = ButtonFloor()
    if not floorStrata then
        -- Called before the first CollectButtons: assume the default-UI bar
        floorStrata, floorLevel = STRATA_INDEX.MEDIUM, 1
    end
    local strata, level = OneUnder(floorStrata, floorLevel)

    -- Never sink to or below the console. Guarded by name so a client running
    -- without Commander_Console just keeps the button-derived layer.
    local console = _G["CAB_ConsoleBackdrop"]
    if console and console.GetFrameStrata then
        local cs = STRATA_INDEX[console:GetFrameStrata()] or STRATA_INDEX.BACKGROUND
        local cl = (console:GetFrameLevel() or 1) + CONSOLE_CLEARANCE
        if strata < cs then
            strata, level = cs, cl
        elseif strata == cs and level < cl then
            level = cl
        end
    end

    -- The button floor is a ceiling, not a preference: whatever the console
    -- clearance just asked for, the card ends up STRICTLY under the lowest
    -- button. Landing on them draws the plate over the icons and -- while the
    -- card is unlocked, which is when it is mouse-enabled -- makes it swallow
    -- every click and every drag-drop aimed at a slot, so the bar reads as
    -- switched off and refuses new icons. A tie is not good enough either:
    -- equal (strata, level) resolves by frame creation order, and that coin
    -- flip is what made this intermittent and "fixed" by a reload or two.
    -- Losing the card behind console art would only be cosmetic; losing the
    -- buttons is not, so the buttons win.
    if strata > floorStrata or (strata == floorStrata and level >= floorLevel) then
        strata, level = OneUnder(floorStrata, floorLevel)
    end

    local stratumName = STRATA_ORDER[strata] or "BACKGROUND"
    if backdrop:GetFrameStrata() ~= stratumName then
        backdrop:SetFrameStrata(stratumName)
    end
    if backdrop:GetFrameLevel() ~= level then
        backdrop:SetFrameLevel(level)
    end
    -- The numpad and the function-key row stack with the grid card. Their
    -- buttons are their own children, so they ride one level above with no
    -- floor to clear; the console clearance above is the part they need. Same
    -- combat rule: each parents secure buttons, so restacking it is protected
    -- (deferred at the top).
    for _, card in ipairs(keyCards) do
        if card:GetFrameStrata() ~= stratumName then
            card:SetFrameStrata(stratumName)
        end
        if card:GetFrameLevel() ~= level then
            card:SetFrameLevel(level)
        end
    end
end

local function MoveActionButtons()
    -- Action buttons are protected; Show/SetPoint on them is blocked in combat
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    CollectButtons()
    local buttonSize = DB().buttonSize or 32
    local spacing = DB().buttonSpacing or 10
    local perRow = DB().buttonsPerRow or 6
    local pad = DB().gridPadding or 14
    local cardScale = DB().cardScale or 1
    local reverse = DB().reverseRows

    local count = 0
    for _, button in ipairs(managedButtons) do
        if button then count = count + 1 end
    end
    local rows = math.max(math.ceil(count / perRow), 1)

    backdrop:SetScale(cardScale)
    backdrop:SetSize(
        perRow * (buttonSize + spacing) - spacing + pad * 2,
        rows * (buttonSize + spacing) - spacing + pad * 2)

    local index = 0
    for _, button in ipairs(managedButtons) do
        if button then
            index = index + 1
            -- Record the button's native size once, BEFORE our first SetSize,
            -- so the border-ratio math has the real starting dimensions
            if button.__cmdNativeSize == nil then
                local w = (button.GetWidth and button:GetWidth()) or 0
                button.__cmdNativeSize = (w > 0) and w or 36
            end
            button:ClearAllPoints()
            button:SetScale(cardScale)
            button:SetSize(buttonSize, buttonSize)
            NormalizeButtonArt(button, buttonSize)
            local row = math.ceil(index / perRow)
            if reverse then
                row = rows - row + 1
            end
            local col = (index - 1) % perRow + 1
            local xOffset = (col - 1) * (buttonSize + spacing) + pad
            local yOffset = (row - 1) * (buttonSize + spacing) + pad
            button:SetPoint("TOPLEFT", backdrop, "TOPLEFT", xOffset, -yOffset)
            button:Show()
            local pushedTexture = button:GetPushedTexture()
            local r, g, b, a = PushedColor()
            if pushedTexture and r then
                pushedTexture:SetColorTexture(r, g, b, a)
            end
        end
    end
    ApplyLayering()
end

local function MovePetBar()
    -- PetActionBar is EditMode-managed and protected in combat
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not (PetActionBar and backdrop) then return end
    local mode = DB().petBarPosition or "ABOVE"
    if mode == "HIDDEN" then
        -- Hide() here is EditModeSystemMixin:HideOverride, not the raw widget
        -- method -- same trap as the note at hiddenHolder. Only call it when it has work
        -- to do instead of re-running Blizzard's hide path four times a second.
        if PetActionBar:IsShown() then PetActionBar:Hide() end
        return
    end
    -- Anchor the bar whether or not it is SHOWN. It only becomes visible once
    -- the pet has an action bar (PetActionBarMixin shows it off UNIT_PET /
    -- PET_BAR_UPDATE), and for a mid-fight summon or a rez that moment is
    -- inside combat lockdown, where the move above is illegal -- so a bar we
    -- refused to anchor while hidden appeared at Blizzard's EditMode position
    -- and stayed there for the whole fight, snapping into place only when
    -- combat dropped. Parking it while hidden is safe and it sticks: the
    -- EditMode hide path only breaks frames snapped TO the bar, never its own
    -- points.
    -- Same manager, same opt-out: EditModeUtil counts PetActionBar as a bottom
    -- anchored bar too, and Classic leaves it to UIParent_ManageFramePositions
    ReleaseFromPositionManager(PetActionBar)
    -- Scale BEFORE anchoring. EditModeSystemMixin:SetScaleOverride re-SetPoints
    -- every existing point by oldScale/newScale to hold the bar still, so a
    -- SetScale *after* ours multiplied our offsets by 1/scale.
    SetScaleIfNeeded(PetActionBar, DB().petBarScale or 0.7)
    if mode == "LEFT" then
        -- Left of the whole console: past the numpad when it is docked on the left
        local card = NumpadAttached("LEFT") and numpadCard or backdrop
        SetAnchor(PetActionBar, "RIGHT", card, "LEFT", -6, 0)
    else
        -- Above the whole console: over the function-key row when it is docked on top
        local card = FKeysAttached() and fkeyCard or backdrop
        SetAnchor(PetActionBar, "BOTTOM", card, "TOP", 10, 5)
    end
end

-- ---------------------------------------------------------------------------
-- Button cosmetics: all combat-safe (text, alpha, vertex color) so they run
-- from the poll even during lockdown
-- ---------------------------------------------------------------------------
local cooldownTexts = {}   -- button -> fontstring
local readyAt = {}         -- button -> cooldown expiry we are watching
local flashTextures = {}   -- button -> additive flash overlay

local function CooldownTextFor(button)
    local text = cooldownTexts[button]
    if not text then
        local holder = CreateFrame("Frame", nil, button)
        holder:SetAllPoints(button)
        holder:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
        text = holder:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(GameFontHighlightSmall)
        local fontPath, fontSize = text:GetFont()
        if fontPath then
            text:SetFont(fontPath, fontSize or 10, "OUTLINE")
        end
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        cooldownTexts[button] = text
    end
    return text
end

local function FlashFor(button)
    local flash = flashTextures[button]
    if not flash then
        flash = button:CreateTexture(nil, "OVERLAY")
        flash:SetTexture("Interface\\Buttons\\WHITE8X8")
        flash:SetBlendMode("ADD")
        flash:SetAllPoints(button)
        flash:SetVertexColor(1, 1, 0.6, 0.55)
        flash:Hide()
        -- One hide-closure per button for its lifetime, not one per flash
        flash._hide = function() flash:Hide() end
        flashTextures[button] = flash
    end
    return flash
end

local function FormatCooldown(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    end
    return string.format("%d", math.ceil(seconds))
end

local function AbbreviateHotkey(text)
    if not text then return text end
    text = text:gsub("SHIFT%-", "S"):gsub("Shift%-", "S")
    text = text:gsub("CTRL%-", "C"):gsub("Ctrl%-", "C")
    text = text:gsub("ALT%-", "A"):gsub("Alt%-", "A")
    return text
end

-- A keyed card's key-cap label for one of its buttons, or nil while its key
-- is not bound -- then the button keeps whatever Blizzard's own hotkey logic
-- shows, because a "7" on a button the 7 key does not press is a lie. Bound
-- means the binding that is live (BindKeys marks what it bound: an action
-- face's proxy, or a mode face itself), not the setting: switched off
-- mid-fight, a key stays bound until combat drops, and so does its cap.
local function KeyCapLabel(button)
    if not (button.__cmdProxy or button).__cmdBound then return nil end
    return button.__cmdLabel
end

-- Icon recess, from the suite's shared art. On an action button these are
-- BLIZZARD's icon textures, so the shading is created in manual mode -- its
-- visibility is driven from here rather than by wrapping a Blizzard
-- texture's Show/Hide, which would put addon code inside an action button's
-- own paths. Re-created only when the setting actually changes; the callers
-- run on a throttle, not once.
local function RecessIcon(button, icon, db)
    if not (icon and Commander.DebossIcon) then return end
    local recess = db.iconRecess or "SOFT"
    if button.__cmdRecess ~= recess then
        button.__cmdRecess = recess
        button.__cmdShade = Commander.DebossIcon(
            icon, recess ~= "OFF" and recess or nil, false, true)
    end
    local shade = button.__cmdShade
    if shade then
        shade:SetShown(recess ~= "OFF" and icon:IsShown() and true or false)
    end
end

-- One button's per-tick cosmetics. The grid's buttons and the keyed cards'
-- share every rule; a keyed button's hotkey shows its key cap rather than the
-- binding text, since the cap IS the binding there.
local function StyleButton(button, db, now, placing, isKeyed)
    local name = button:GetName()
    -- Macro name and hotkey text
    local macroText = button.Name or (name and _G[name .. "Name"])
    if macroText then
        macroText:SetShown(not db.hideMacroText)
    end
    local hotkey = button.HotKey or (name and _G[name .. "HotKey"])
    local keyLabel = isKeyed and KeyCapLabel(button)
    if hotkey then
        if db.hideHotkeys then
            hotkey:Hide()
        elseif keyLabel then
            if hotkey:GetText() ~= keyLabel then
                hotkey:SetText(keyLabel)
            end
            hotkey:Show()
        elseif not isKeyed then
            -- An unbound keyed button is left to Blizzard, which shows its
            -- hotkey only as the range dot, and only when range applies
            hotkey:Show()
            if db.abbrevHotkeys then
                local current = hotkey:GetText()
                local shortened = AbbreviateHotkey(current)
                if shortened ~= current then
                    hotkey:SetText(shortened)
                end
            end
        end
    end

    local slot = button.action
    local icon = button.icon or (name and _G[name .. "Icon"])
    -- Empty slot fading
    local hasAction = slot and HasAction and HasAction(slot)
    if db.hideEmptySlots and slot and HasAction then
        button:SetAlpha((hasAction or placing) and 1 or 0.15)
    end

    -- Range / mana tinting, restored to white when off or fine
    if icon and slot then
        local r, g, b = 1, 1, 1
        if hasAction then
            if db.manaTint and IsUsableAction then
                local usable, noMana = IsUsableAction(slot)
                if noMana then
                    r, g, b = 0.35, 0.5, 1
                elseif not usable then
                    r, g, b = 0.45, 0.45, 0.45
                end
            end
            if db.rangeTint and IsActionInRange and IsActionInRange(slot) == false then
                r, g, b = 1, 0.3, 0.25
            end
        end
        icon:SetVertexColor(r, g, b)
    end

    RecessIcon(button, icon, db)

    -- Cooldown countdown text + ready flash
    if slot and GetActionCooldown then
        local start, duration = GetActionCooldown(slot)
        local remaining = (start and duration and duration > 1.5)
            and (start + duration - now) or 0
        if db.cooldownText and remaining > 0 then
            local text = CooldownTextFor(button)
            -- Signed key (-minutes vs +seconds) is bijective with
            -- the displayed string, so unchanged ticks skip both
            -- the format allocation and the SetText relayout
            local key = remaining >= 60 and -math.ceil(remaining / 60)
                or math.ceil(remaining)
            if text._last ~= key then
                text._last = key
                text:SetText(FormatCooldown(remaining))
            end
            text:Show()
        elseif cooldownTexts[button] then
            cooldownTexts[button]:Hide()
        end
        if db.readyFlash then
            if remaining > 0.5 then
                readyAt[button] = true
            elseif readyAt[button] and remaining <= 0 then
                readyAt[button] = nil
                local flash = FlashFor(button)
                flash:Show()
                C_Timer.After(0.35, flash._hide)
            end
        end
    end
end

-- The row's raid-mark and party faces, which say what F1-F5 do right now:
-- the target's mark and the party roster change under them, so they are
-- drawn on the poll. Textures, text and alpha only, so it runs mid-fight.
local function StyleModeFaces(db)
    local mode = fkeyShownMode
    local faces = (mode == "MARKS" and fkeyMarkFaces) or (mode == "PARTY" and fkeyPartyFaces)
    if not faces then return end
    local targetMark = mode == "MARKS" and GetRaidTargetIndex("target")
    for _, face in pairs(faces) do
        -- Our own faces have no Blizzard hotkey logic to fall back on: no
        -- cap means no text at all
        local label = KeyCapLabel(face)
        if label and not db.hideHotkeys then
            if face.HotKey:GetText() ~= label then face.HotKey:SetText(label) end
            face.HotKey:Show()
        else
            face.HotKey:Hide()
        end
        if mode == "MARKS" then
            face.__cmdLit:SetShown(targetMark == face.__cmdMark)
        else
            -- Who the key targets is the button's own unit, not a fresh read
            -- of the roster: a change mid-fight only reaches the button when
            -- combat drops, and until then the face shows who it really hits
            local unit = face:GetAttribute("unit")
            local icon = face.icon
            if unit and UnitExists(unit) then
                local _, token = UnitClass(unit)
                if face.__cmdClass ~= token then
                    face.__cmdClass = token
                    local info = token and Commander.GetClassInfo and Commander.GetClassInfo(token)
                    local coords = info and info.iconCoords
                    if coords then
                        icon:SetTexture(info.icon)
                        icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                    end
                end
                icon:SetShown(face.__cmdClass ~= nil)
                icon:SetDesaturated((UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)) and true or false)
                -- Out-of-Range Tint, as on the action buttons: a partner out
                -- of range goes red. UnitInRange (40 yards) answers for group
                -- members only, so your own seat never tints; it is also the
                -- one range check addons may call here (CheckInteractDistance
                -- is protected on this client, see Commander_PartyFrames).
                local r, g, b = 1, 1, 1
                if db.rangeTint and UnitInRange then
                    local inRange, checked = UnitInRange(unit)
                    if checked and not inRange then r, g, b = 1, 0.3, 0.25 end
                end
                icon:SetVertexColor(r, g, b)
                local name = UnitName(unit)
                if face.__cmdName ~= name then
                    face.__cmdName = name
                    face.Name:SetText(name or "")
                end
                face:SetAlpha(1)
            else
                icon:Hide()
                if face.__cmdName then
                    face.__cmdName = nil
                    face.Name:SetText("")
                end
                -- An empty seat dims like an empty slot does
                face:SetAlpha(0.35)
            end
            RecessIcon(face, icon, db)
        end
    end
end

local function ApplyButtonCosmetics()
    local db = DB()
    local now = GetTime()
    -- 15% alpha over the card art is invisible, and an invisible slot is one
    -- you cannot aim at. Blizzard reveals the empty grid the moment an action
    -- lands on the cursor; this poll used to fade it straight back out within
    -- 250ms, so the bar appeared to switch off exactly when a drop was aimed
    -- at it. Hold every slot at full alpha for as long as the cursor is armed.
    local placing = CursorHoldsAction()
    for _, button in ipairs(managedButtons) do
        if button then StyleButton(button, db, now, placing, false) end
    end
    if numpadCard and numpadCard:IsShown() then
        for _, button in ipairs(numpadButtons) do
            if button:IsShown() then StyleButton(button, db, now, placing, true) end
        end
    end
    if fkeyCard and fkeyCard:IsShown() then
        for _, button in ipairs(fkeyButtons) do
            if button:IsShown() then StyleButton(button, db, now, placing, true) end
        end
        StyleModeFaces(db)
    end
end

-- A keyed card fades with the grid. Its buttons are its children, so its
-- alpha already reaches them; theirs is relative. Dimmed, a slot lands where
-- a grid slot does.
local function FadeKeyCard(card, buttons, alpha, db, placing)
    card:SetAlpha(alpha)
    local dim = alpha > 0 and math.min(1, 0.15 / alpha) or 1
    for _, button in ipairs(buttons) do
        if button:IsShown() then
            button:SetAlpha((db.hideEmptySlots and not placing
                and button.action and HasAction and not HasAction(button.action))
                and dim or 1)
        end
    end
end

-- Out-of-combat fade: alpha is not a protected attribute, so the whole
-- card (backdrop + buttons) can fade even during lockdown
local function ApplyFade()
    if not backdrop then return end
    local db = DB()
    local alpha = 1
    if db.oocFade and not inCombat then
        alpha = db.fadeOpacity or 0.4
        -- The cards are one console: hovering any one of them wakes them all
        if db.mouseoverReveal and MouseIsOver then
            if MouseIsOver(backdrop) then
                alpha = 1
            else
                for _, card in ipairs(keyCards) do
                    if card:IsShown() and MouseIsOver(card) then
                        alpha = 1
                        break
                    end
                end
            end
        end
    end
    backdrop:SetAlpha(alpha)
    -- Runs after ApplyButtonCosmetics on the same tick and writes the same
    -- alpha, so the drop exception has to be repeated here or this undoes it
    local placing = CursorHoldsAction()
    for _, button in ipairs(managedButtons) do
        if button then
            button:SetAlpha((db.hideEmptySlots and not placing
                and button.action and HasAction and not HasAction(button.action))
                and math.min(alpha, 0.15) or alpha)
        end
    end
    if numpadCard and numpadCard:IsShown() then
        FadeKeyCard(numpadCard, numpadButtons, alpha, db, placing)
    end
    if fkeyCard and fkeyCard:IsShown() then
        FadeKeyCard(fkeyCard, fkeyButtons, alpha, db, placing)
    end
end

-- ---------------------------------------------------------------------------
-- Keyed cards: the frames (data at "Numpad card: the data" and "Function-key
-- row: the data" up top)
--
-- The numpad and the function-key row are built alike. Each key is TWO
-- secure buttons, because one cannot do both jobs:
--
--   * the face is an ActionBarButtonTemplate button -- Blizzard's own action
--     button, so icon, cooldown, count, usable/range tint, checked state,
--     tooltip, drag-off and drop-on all come with it, driven by the `action`
--     attribute (an ID-0 button reads its slot from there, see
--     SecureActionButtonMixin:CalculateAction);
--   * the key is a bare SecureActionButtonTemplate proxy, and the binding
--     clicks THAT. A key bound straight to the face would cast on key UP no
--     matter what: the template's OnClick hands SecureActionButton_OnClick
--     isSecureAction with no isKeyPress, which reads as a mouse press and
--     ignores ActionButtonUseKeyDown. The bare template's OnClick passes
--     neither flag, so the proxy honours the CVar like Blizzard's own binds.
--
-- Everything here is protected once the buttons exist (the card parents
-- them), so it is all built, moved and bound out of combat only, deferring
-- through pendingUpdate like the grid. A card is only created the first
-- time it is switched on: nobody who never uses the numpad carries 42 secure
-- buttons around.
-- ---------------------------------------------------------------------------
local CARD_GAP = 2   -- between a docked keyed card and the grid card

-- A plain frame per card owns its override bindings: never protected, never
-- hidden, and clearing one card's binds never touches the other's
local numpadBindOwner = CreateFrame("Frame")
local appliedNumpadBinds = ""   -- signature of the keys bound right now
local fkeyBindOwner = CreateFrame("Frame")
local appliedFKeyBinds = ""

-- A keyed button's hotkey shows its cap. Blizzard's UpdateHotkeys runs on
-- every UPDATE_BINDINGS and blanks it -- an ID-0 button has no binding
-- command of its own to find -- so put the cap straight back. A post-hook on
-- our own button: Blizzard's code runs untouched first.
local function RelabelKeyButton(button)
    local label = KeyCapLabel(button)
    local hotkey = button.HotKey
    if not (label and hotkey) or DB().hideHotkeys then return end
    if hotkey:GetText() ~= label then hotkey:SetText(label) end
    hotkey:Show()
end

-- The face's own pushed state only answers the mouse; this overlay answers
-- the key, lit by the proxy's PostClick (down = pressed, up = released).
-- A texture, so it is free to show and hide mid-fight.
local function KeyPressFor(button)
    local press = button.__cmdPress
    if not press then
        press = button:CreateTexture(nil, "OVERLAY")
        press:SetAllPoints(button)
        press:Hide()
        button.__cmdPress = press
    end
    return press
end

-- Keeping our faces out of Blizzard's button lists. The template's OnLoad
-- appends every ActionBarButtonTemplate button to
-- ActionBarButtonEventsFrame.frames, and Update() keys one holding an action
-- into ActionBarActionEventsFrame.frames. Both are walked in plain loops,
-- and an entry an addon wrote is tainted: reading it taints the rest of the
-- walk. ActionBarController walks the first on every zone-in and page or
-- stance change and then, in the same pass, shows MainActionBar and the
-- MultiBars (ValidateActionBarTransition), so the bars' isShownExternal
-- would be written tainted -- the hiddenHolder trap noted up top, blocked
-- at the next combat change. The second is a hash, so whichever of
-- Blizzard's grid buttons come after ours would run tainted. So each face
-- leaves both lists the moment it is made, and gets the same events from
-- our own frame instead, handed to the same OnEvent with nothing of
-- Blizzard's after them. (Blizzard_ActionBar/Shared/ActionButton.lua and
-- Blizzard_ActionBarController/ActionBarController.lua, classic_anniversary.)
-- The per-slot range and usable watchers keep ours: they only ever reach
-- buttons on the same slot, and only with texture updates.
local keyFaces = {}   -- every ActionBarButtonTemplate face, both cards

-- ActionBarButtonEventsFrame's events go to every face; the rest are
-- ActionBarActionEventsFrame's, which only faces holding an action hear
-- (Blizzard's own eventsRegistered flag says which), the spellcasts only
-- for the face whose spell it is
local FACE_EVENTS = {
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS",
    "GAME_PAD_ACTIVE_CHANGED", "UPDATE_SHAPESHIFT_FORM", "ACTIONBAR_UPDATE_COOLDOWN",
    "PET_BAR_UPDATE", "PLAYER_MOUNT_DISPLAY_CHANGED",
}
local FACE_PET_EVENTS = { "UNIT_FLAGS", "UNIT_AURA" }
local FACE_ACTION_EVENTS = {
    "SPELL_UPDATE_CHARGES", "UPDATE_INVENTORY_ALERTS", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    "ARCHAEOLOGY_CLOSED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT", "START_AUTOREPEAT_SPELL",
    "STOP_AUTOREPEAT_SPELL", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE", "COMPANION_UPDATE",
    "UNIT_INVENTORY_CHANGED", "UNIT_SPELLCAST_SENT", "LEARNED_SPELL_IN_SKILL_LINE",
    "PET_STABLE_UPDATE", "PET_STABLE_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "UPDATE_SUMMONPETS_ACTION", "SPELL_UPDATE_ICON",
}
local FACE_PLAYER_EVENTS = {
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_RETICLE_TARGET", "UNIT_SPELLCAST_RETICLE_CLEAR",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
    "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
}
local ACTION_EVENT = {}
for _, event in ipairs(FACE_ACTION_EVENTS) do ACTION_EVENT[event] = true end
for _, event in ipairs(FACE_PLAYER_EVENTS) do ACTION_EVENT[event] = true end

local faceEvents   -- built with the first face, so a bar without cards listens to nothing

local function DispatchFaceEvent(_, event, ...)
    if not ACTION_EVENT[event] then
        for _, face in ipairs(keyFaces) do face:OnEvent(event, ...) end
        return
    end
    -- Blizzard's own filter for the spellcasts: the player's, on this spell
    local spellID
    if event:match("^UNIT_SPELLCAST_") then
        local unit = ...
        if unit ~= "player" then return end
        spellID = select(event == "UNIT_SPELLCAST_SENT" and 4 or 3, ...)
    end
    for _, face in ipairs(keyFaces) do
        if face.eventsRegistered and (not spellID or face:MatchesActiveButtonSpellID(spellID)) then
            face:OnEvent(event, ...)
        end
    end
end

local function EnsureFaceEvents()
    if faceEvents then return end
    faceEvents = CreateFrame("Frame")
    -- pcall: an event this build has dropped must not stop the rest
    for _, event in ipairs(FACE_EVENTS) do pcall(faceEvents.RegisterEvent, faceEvents, event) end
    for _, event in ipairs(FACE_ACTION_EVENTS) do pcall(faceEvents.RegisterEvent, faceEvents, event) end
    for _, event in ipairs(FACE_PET_EVENTS) do
        pcall(faceEvents.RegisterUnitEvent, faceEvents, event, "pet")
    end
    for _, event in ipairs(FACE_PLAYER_EVENTS) do
        pcall(faceEvents.RegisterUnitEvent, faceEvents, event, "player")
    end
    faceEvents:SetScript("OnEvent", DispatchFaceEvent)
end

-- Out of ActionBarActionEventsFrame's list, wherever Blizzard's Update put it
local function LeaveActionList(face)
    local list = ActionBarActionEventsFrame and ActionBarActionEventsFrame.frames
    if list and list[face] then list[face] = nil end
end

-- A face just made: out of both lists. OnLoad's RegisterFrame was the last
-- append to ActionBarButtonEventsFrame, so clearing the end of that array
-- moves no Blizzard entry. Update() is wrapped so a face that gains an
-- action never rejoins the other; eventsRegistered keeps meaning what it
-- does to Blizzard, which is how the dispatcher reads it.
local function DetachFace(face)
    local list = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
    if list and list[#list] == face then list[#list] = nil end
    LeaveActionList(face)
    local blizzardUpdate = face.Update
    face.Update = function(self, ...)
        blizzardUpdate(self, ...)
        LeaveActionList(self)
    end
    keyFaces[#keyFaces + 1] = face
    EnsureFaceEvents()
end

-- Stands in for the template's UpdatePressAndHoldAction on our faces
local function KeepPressAndHold() end

local function CreateKeyButton(card, name, key, buttons, byKey)
    local button = CreateFrame("CheckButton", name, card, "ActionBarButtonTemplate")
    button.__cmdKey = key
    DetachFace(button)
    -- The template's Update() ends in UpdatePressAndHoldAction, which writes
    -- the face's "pressAndHoldAction" attribute every time. Blizzard's own
    -- buttons run that secure; ours run it as us, so an ACTIONBAR_SLOT_CHANGED
    -- for one of our slots mid-fight (a conditional macro flipping its icon,
    -- a spell dragged on) would make it a blocked SetAttribute. Nothing on
    -- this client presses and holds, and OnLoad has already written false
    -- out of combat, so ours never write it again. It is the only protected
    -- call on the face's event paths (Blizzard_ActionBar/Shared/ActionButton.lua;
    -- grid changes are issecure()-guarded).
    button.UpdatePressAndHoldAction = KeepPressAndHold
    -- Left button only. The template's OnClick reads self.action before it
    -- casts when the click is a right one, and on our faces that field was
    -- written by us, so a right-click cast was always a blocked UseAction.
    -- Keys never click the face, so this costs them nothing.
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    -- Same attributes Blizzard puts on its action buttons, so self-cast,
    -- focus-cast and mouseover modifiers behave identically from the key.
    -- Not its "typerelease": that is retail press-and-hold, and the
    -- ReleaseAction it calls is not in this client's binary.
    local proxy = CreateFrame("Button", name .. "Key", button, "SecureActionButtonTemplate")
    proxy:SetAttribute("type", "action")
    proxy:SetAttribute("checkselfcast", true)
    proxy:SetAttribute("checkfocuscast", true)
    proxy:SetAttribute("checkmouseovercast", true)
    -- Both phases: the secure gate fires on exactly one of them, per the CVar
    proxy:RegisterForClicks("AnyDown", "AnyUp")
    -- Never in the mouse's way: it exists to be clicked by the binding only
    proxy:EnableMouse(false)
    proxy:SetSize(1, 1)
    proxy:SetPoint("CENTER", button, "CENTER", 0, 0)
    proxy:HookScript("PostClick", function(_, _, down)
        KeyPressFor(button):SetShown(down and true or false)
    end)
    button.__cmdProxy = proxy
    hooksecurefunc(button, "UpdateHotkeys", RelabelKeyButton)
    buttons[#buttons + 1] = button
    byKey[key] = button
    return button
end

-- A keyed card's plate. Docked, it moves with the grid; free (its anchor
-- setting is "FREE"), it drags on its own while the bar is unlocked and keeps
-- its place in its position setting.
local function CreateKeyCard(frameName, anchorKey, positionKey)
    local card = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    card:SetSize(1, 1)
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(false)
    card:RegisterForDrag("LeftButton")
    -- Same drop guard as the grid card: with an icon on the cursor the drag is
    -- a drop in progress, not a move
    card:SetScript("OnDragStart", function(self)
        if DB().locked or DB()[anchorKey] ~= "FREE"
            or CursorHoldsAction() or InCombatLockdown() then return end
        self.__cmdMoving = true
        self:StartMoving()
    end)
    card:SetScript("OnDragStop", function(self)
        if not self.__cmdMoving then return end
        self.__cmdMoving = nil
        self:StopMovingOrSizing()
        local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
        -- Offsets are in the card's own scaled units, so the scale they were
        -- taken at travels with them (see AnchorFree)
        DB()[positionKey] = { point = point, relativePoint = relativePoint,
            xOfs = xOfs, yOfs = yOfs, scale = self:GetScale() }
        Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    end)
    keyCards[#keyCards + 1] = card
    return card
end

local function SetKeyCardLockState(card, anchorKey)
    -- Draggable only when it is free-standing; docked, it moves with the grid
    local free = not DB().locked and DB()[anchorKey] == "FREE"
    if card:IsMouseEnabled() ~= free then
        card:EnableMouse(free)
    end
end

-- A keyed card's own scale is relative: it follows Card Scale, so by default
-- its keys are the grid's keys and the cards stay matched
local function KeyCardScale(scaleKey)
    return (DB().cardScale or 1) * (DB()[scaleKey] or 1)
end

-- A free-standing card at its saved position, or CENTER offset by (x, y)
-- before it has one. A point's offsets are multiplied by the frame's own
-- scale on screen. Re-express them at today's scale so a free card grows and
-- shrinks about its anchor instead of sliding across the screen. A position
-- saved without its scale is taken as already at this one.
local function AnchorFree(card, pos, x, y)
    local current = card:GetScale()
    local factor = (pos and pos.scale and current > 0) and (pos.scale / current) or 1
    if pos and pos.point then
        SetAnchor(card, pos.point, UIParent, pos.relativePoint or pos.point,
            (pos.xOfs or 0) * factor, (pos.yOfs or 0) * factor)
    else
        SetAnchor(card, "CENTER", UIParent, "CENTER", x * factor, y * factor)
    end
end

-- A face onto its spot on the card (x, y down from the card's top-left
-- corner), sized and dressed like a grid key
local function PlaceFace(button, card, size, x, y)
    if button.__cmdNativeSize == nil then
        local w = (button.GetWidth and button:GetWidth()) or 0
        button.__cmdNativeSize = (w > 0) and w or 36
    end
    button:SetSize(size, size)
    NormalizeButtonArt(button, size)
    SetAnchor(button, "TOPLEFT", card, "TOPLEFT", x, -y)
    local r, g, b, a = PushedColor()
    local pushed = button:GetPushedTexture()
    local press = KeyPressFor(button)
    if r then
        if pushed then pushed:SetColorTexture(r, g, b, a) end
        press:SetColorTexture(r, g, b, a)
    end
    press:Hide()
    if not button:IsShown() then button:Show() end
    RelabelKeyButton(button)
end

-- One key's action face and proxy onto its slot, and onto its spot
local function PlaceKeyButton(button, card, slot, size, x, y)
    if button:GetAttribute("action") ~= slot then
        button:SetAttribute("action", slot)
    end
    local proxy = button.__cmdProxy
    if proxy:GetAttribute("action") ~= slot then
        proxy:SetAttribute("action", slot)
    end
    PlaceFace(button, card, size, x, y)
end

-- Bind each of `keys` to the button `targets` names for it (an action
-- face's proxy, or a face that is its own key), and give back every key the
-- owner held that is no longer listed. Override bindings sit on top of the
-- saved set without touching it: switching a card off restores whatever its
-- keys did before (movement, autorun, raid marks, your own binds), with
-- nothing to undo. Protected in combat, so deferred. Returns the signature
-- now bound, for the caller to keep: an unchanged one skips the rebind --
-- and the UPDATE_BINDINGS it fires.
local function BindKeys(owner, keys, targets, buttons, applied)
    -- Each key's target is in the signature too: switching the row's mode
    -- moves keys onto other buttons without changing which keys are held
    local parts = {}
    for i, key in ipairs(keys) do
        parts[i] = key .. "=" .. targets[key]:GetName()
    end
    local signature = table.concat(parts, " ")
    if signature == applied then return applied end
    if InCombatLockdown() then
        pendingUpdate = true
        return applied
    end
    ClearOverrideBindings(owner)
    -- What is bound now is what the caps follow (KeyCapLabel)
    for _, target in ipairs(owner.__cmdBound or {}) do target.__cmdBound = nil end
    local bound = {}
    for _, key in ipairs(keys) do
        local target = targets[key]
        SetOverrideBindingClick(owner, false, key, target:GetName(), "LeftButton")
        target.__cmdBound = true
        bound[#bound + 1] = target
    end
    owner.__cmdBound = bound
    -- Let Blizzard recompute every face's hotkey (blank on an unbound one),
    -- then the post-hook lays the cap back on the bound ones
    for _, button in ipairs(buttons) do
        button:UpdateHotkeys(button.buttonType)
    end
    return signature
end

-- ---------------------------------------------------------------------------
-- Numpad card: layout and binds
-- ---------------------------------------------------------------------------
local function EnsureNumpad()
    if numpadCard then return numpadCard end
    -- CreateFrame from a secure template runs its OnLoad under our taint, and
    -- that OnLoad sets attributes: illegal on a secure frame in combat
    if InCombatLockdown() then
        pendingUpdate = true
        return nil
    end
    numpadCard = CreateKeyCard("CommanderActionBarNumpad", "numpadAnchor", "numpadPosition")
    for _, key in ipairs(NUMPAD_KEY_ORDER) do
        CreateKeyButton(numpadCard, "CommanderNumpadButton" .. (key:gsub("^NUMPAD", "")),
            key, numpadButtons, numpadByKey)
    end
    return numpadCard
end

local function AnchorNumpad()
    local mode = DB().numpadAnchor or "RIGHT"
    if mode == "FREE" or not backdrop then
        AnchorFree(numpadCard, DB().numpadPosition, 320, 0)
    elseif mode == "LEFT" then
        -- Bottoms level with the grid's: the numpad is a row taller, and the
        -- two read as one console when they share a baseline
        SetAnchor(numpadCard, "BOTTOMRIGHT", backdrop, "BOTTOMLEFT", -CARD_GAP, 0)
    else
        SetAnchor(numpadCard, "BOTTOMLEFT", backdrop, "BOTTOMRIGHT", CARD_GAP, 0)
    end
end

local function LayoutNumpad()
    local db = DB()
    if not db.numpadEnabled then
        if numpadCard and numpadCard:IsShown() then
            if InCombatLockdown() then
                pendingUpdate = true
                return
            end
            numpadCard:Hide()
        end
        return
    end
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not EnsureNumpad() then return end

    -- The grid's measurements, so a numpad key is the size of a grid key and
    -- the two cards share a pitch
    local size = db.buttonSize or 32
    local spacing = db.buttonSpacing or 10
    local pad = db.gridPadding or 14
    local cell = size + spacing
    -- Before AnchorNumpad below: a free position is converted at this scale
    SetScaleIfNeeded(numpadCard, KeyCardScale("numpadScale"))

    -- Only the rows something sits in: a pad with its top row switched off
    -- loses the row rather than wearing a gap
    local placed = {}
    local topRow, bottomRow = math.huge, 0
    for _, entry in ipairs(NumpadLayout()) do
        if NumpadKeyUsed(entry.key) then
            placed[entry.key] = entry
            topRow = math.min(topRow, entry.row)
            bottomRow = math.max(bottomRow, entry.row + (entry.h or 1) - 1)
        end
    end
    local rows = math.max(bottomRow - topRow + 1, 1)
    numpadCard:SetSize(
        NUMPAD_COLS * cell - spacing + pad * 2,
        rows * cell - spacing + pad * 2)
    for _, button in ipairs(numpadButtons) do
        local key = button.__cmdKey
        local entry = placed[key]
        if entry then
            button.__cmdLabel = entry.label or NUMPAD_KEYS[key].label
            -- A spanning key sits centered in its span, like the keycap
            local x = pad + (entry.col - 1) * cell + ((entry.w or 1) - 1) * cell / 2
            local y = pad + (entry.row - topRow) * cell + ((entry.h or 1) - 1) * cell / 2
            PlaceKeyButton(button, numpadCard, NumpadSlot(key), size, x, y)
        elseif button:IsShown() then
            button:Hide()
        end
    end

    AnchorNumpad()
    if not numpadCard:IsShown() then numpadCard:Show() end
    StyleCard(numpadCard)
    SetKeyCardLockState(numpadCard, "numpadAnchor")
    -- A card built just now has never been stacked
    ApplyLayering()
end

-- Every shown key bound while the numpad is up, none while it is not
local function ApplyNumpadBindings()
    local db = DB()
    local keys, targets = {}, {}
    if db.numpadEnabled and db.numpadBindKeys and numpadCard then
        for _, entry in ipairs(NumpadLayout()) do
            if NumpadKeyUsed(entry.key) then
                keys[#keys + 1] = entry.key
                targets[entry.key] = numpadByKey[entry.key].__cmdProxy
            end
        end
    end
    appliedNumpadBinds = BindKeys(numpadBindOwner, keys, targets, numpadButtons, appliedNumpadBinds)
end

-- ---------------------------------------------------------------------------
-- Function-key row: layout and binds
-- ---------------------------------------------------------------------------

-- Blizzard's own RAIDTARGETn binding, as a button: the mark onto the target,
-- or off it when the target already wears that one
local function ToggleRaidMark(mark)
    if not UnitExists("target") then return end
    if GetRaidTargetIndex("target") == mark then
        SetRaidTarget("target", 0)
    else
        SetRaidTarget("target", mark)
    end
end

-- A face of our own, for the modes where an F key does something other than
-- press an action: Blizzard's slot art round an icon, so the row reads the
-- same in every mode, with a HotKey for the cap and a Name along the bottom
local function DressModeFace(face, entry)
    face.__cmdKey = entry.key
    face.__cmdLabel = entry.label
    local bg = face:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(face)
    bg:SetColorTexture(0, 0, 0, 0.5)
    local icon = face:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", face, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", -2, 2)
    face.icon = icon
    -- The action button's border, drawn larger than the button and centred
    -- the way the template draws it; NormalizeButtonArt keeps the ratio
    face:SetNormalTexture("Interface\\Buttons\\UI-Quickslot2")
    local normal = face:GetNormalTexture()
    normal:ClearAllPoints()
    normal:SetPoint("CENTER", face, "CENTER", 0, -1)
    face.__cmdBorderRatio = BORDER_RATIO_FALLBACK
    face:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    face:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    face.HotKey = face:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    face.HotKey:SetPoint("TOPRIGHT", face, "TOPRIGHT", -2, -3)
    face.Name = face:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    face.Name:SetPoint("BOTTOMLEFT", face, "BOTTOMLEFT", 1, 2)
    face.Name:SetPoint("BOTTOMRIGHT", face, "BOTTOMRIGHT", -1, 2)
    face.Name:SetWordWrap(false)
    face:Hide()
    return face
end

-- A raid-mark face: an insecure button, since marking is not protected. It
-- hears both phases and acts on the one ActionButtonUseKeyDown picks, like
-- the secure keys, so a mark lands when a spell on the next key would.
local function CreateMarkFace(entry)
    local face = DressModeFace(CreateFrame("Button", "CommanderFKeyMark" .. entry.key, fkeyCard), entry)
    face.__cmdMark = entry.mark
    face.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. entry.mark)
    -- Lit while the target wears this mark
    local lit = face:CreateTexture(nil, "OVERLAY")
    lit:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    lit:SetBlendMode("ADD")
    lit:SetAllPoints(face)
    lit:Hide()
    face.__cmdLit = lit
    face:RegisterForClicks("AnyDown", "AnyUp")
    face:SetScript("OnClick", function(self, _, down)
        KeyPressFor(self):SetShown(down and true or false)
        if (down and true or false) == GetCVarBool("ActionButtonUseKeyDown") then
            ToggleRaidMark(self.__cmdMark)
        end
    end)
    fkeyMarkFaces[entry.key] = face
end

-- A party-seat face: the secure "target" action, so it works mid-fight, with
-- the unit SeatPartyFaces gives it (none: it does nothing at all). The bare
-- template's OnClick honours ActionButtonUseKeyDown, so the face is its own
-- key and needs no proxy (see the keyed-card note).
local function CreatePartyFace(entry)
    local face = DressModeFace(CreateFrame("Button", "CommanderFKeyParty" .. entry.key, fkeyCard,
        "SecureActionButtonTemplate"), entry)
    face.__cmdSeat = entry.seat
    face:SetAttribute("type", "target")
    face:RegisterForClicks("AnyDown", "AnyUp")
    face:HookScript("PostClick", function(self, _, down)
        KeyPressFor(self):SetShown(down and true or false)
    end)
    fkeyPartyFaces[entry.key] = face
end

local function EnsureFKeys()
    if fkeyCard then return fkeyCard end
    -- Secure templates, so built out of combat only (see EnsureNumpad)
    if InCombatLockdown() then
        pendingUpdate = true
        return nil
    end
    fkeyCard = CreateKeyCard("CommanderActionBarFKeys", "fkeyAnchor", "fkeyPosition")
    for _, entry in ipairs(FKEY_ROW) do
        local button = CreateKeyButton(fkeyCard, "CommanderFKeyButton" .. (entry.name or entry.key),
            entry.key, fkeyButtons, fkeyByKey)
        button.__cmdLabel = entry.label
        if entry.mark then CreateMarkFace(entry) end
        if entry.seat then CreatePartyFace(entry) end
    end
    return fkeyCard
end

-- The face a key shows, and its binding clicks, in the row's mode: its
-- action button, or for F1-F5 its raid-mark or party face
local function FKeyFace(entry, mode)
    if mode == "MARKS" and entry.mark then return fkeyMarkFaces[entry.key] end
    if mode == "PARTY" and entry.seat then return fkeyPartyFaces[entry.key] end
    return fkeyByKey[entry.key]
end

local function HideUnlessLive(face, live)
    if face and face ~= live and face:IsShown() then face:Hide() end
end

-- Each party face onto the unit its seat holds now. An attribute on a
-- secure button, so out of combat only: the poll re-seats after a roster
-- change, and one that happens mid-fight waits for combat to drop -- the
-- faces show the seats as they really stand until then.
local function SeatPartyFaces()
    if fkeyShownMode ~= "PARTY" or InCombatLockdown() then return end
    for _, face in pairs(fkeyPartyFaces) do
        local unit = PartySeatUnit(face.__cmdSeat)
        if face:GetAttribute("unit") ~= unit then
            face:SetAttribute("unit", unit)
        end
    end
end

local function AnchorFKeys()
    if DB().fkeyAnchor == "FREE" or not backdrop then
        AnchorFree(fkeyCard, DB().fkeyPosition, 0, 160)
    else
        -- On the grid's top edge with the left edges lined up: at the grid's
        -- own scale each key sits straight over a grid column
        SetAnchor(fkeyCard, "BOTTOMLEFT", backdrop, "TOPLEFT", 0, CARD_GAP)
    end
end

local function LayoutFKeys()
    local db = DB()
    if not db.fkeyEnabled then
        if fkeyCard and fkeyCard:IsShown() then
            if InCombatLockdown() then
                pendingUpdate = true
                return
            end
            fkeyCard:Hide()
        end
        return
    end
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not EnsureFKeys() then return end

    -- The grid's measurements, so the row's keys are grid keys on its pitch
    local size = db.buttonSize or 32
    local spacing = db.buttonSpacing or 10
    local pad = db.gridPadding or 14
    local cell = size + spacing
    -- Before AnchorFKeys below: a free position is converted at this scale
    SetScaleIfNeeded(fkeyCard, KeyCardScale("fkeyScale"))
    fkeyCard:SetSize(#FKEY_ROW * cell - spacing + pad * 2, size + pad * 2)
    for i, entry in ipairs(FKEY_ROW) do
        local x = pad + (i - 1) * cell
        local live = FKeyFace(entry, db.fkeyMode)
        if live.__cmdProxy then
            PlaceKeyButton(live, fkeyCard, FKeySlot(i), size, x, pad)
        else
            PlaceFace(live, fkeyCard, size, x, pad)
        end
        HideUnlessLive(fkeyByKey[entry.key], live)
        HideUnlessLive(fkeyMarkFaces[entry.key], live)
        HideUnlessLive(fkeyPartyFaces[entry.key], live)
    end
    fkeyShownMode = db.fkeyMode
    SeatPartyFaces()

    AnchorFKeys()
    if not fkeyCard:IsShown() then fkeyCard:Show() end
    StyleCard(fkeyCard)
    SetKeyCardLockState(fkeyCard, "fkeyAnchor")
    -- A card built just now has never been stacked
    ApplyLayering()
end

-- All six keys bound while the row is up, each to the face its mode shows
-- (an action face's proxy, or a mark or party face itself); none while the
-- row is down
local function ApplyFKeyBindings()
    local db = DB()
    local keys, targets = {}, {}
    if db.fkeyEnabled and db.fkeyBindKeys and fkeyCard then
        for _, entry in ipairs(FKEY_ROW) do
            local face = FKeyFace(entry, db.fkeyMode)
            keys[#keys + 1] = entry.key
            targets[entry.key] = face.__cmdProxy or face
        end
    end
    appliedFKeyBinds = BindKeys(fkeyBindOwner, keys, targets, fkeyButtons, appliedFKeyBinds)
end

-- ---------------------------------------------------------------------------
-- Update loop
-- ---------------------------------------------------------------------------
local function OnUpdate()
    -- A roster change re-seats the party faces (it waits out combat on its
    -- own), ahead of the cosmetics so they draw the seats as they now stand
    SeatPartyFaces()
    -- Cosmetics are combat-safe and always run
    ApplyButtonCosmetics()
    ApplyFade()
    ApplyCardStyle()
    -- Re-running the layering here is what closes the load-order gap:
    -- Commander_Console builds its backdrop on its own PLAYER_LOGIN, which can
    -- land after ours. It self-defers in combat (see ApplyLayering).
    ApplyLayering()
    -- Protected frames can't be shown/hidden/moved in combat; retried on PLAYER_REGEN_ENABLED
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    HideDefaults()
    MovePetBar()
    for _, button in ipairs(managedButtons) do
        -- Same rule as everything else on this poll: Show() only a button that
        -- is actually hidden. These are Blizzard's protected buttons and the
        -- unconditional call re-entered their bar's visibility path every tick.
        if button and not button:IsShown() then button:Show() end
    end
end

-- Throttle so the hide/reposition work doesn't run every single frame
local UPDATE_INTERVAL = 0.25
local timeSinceUpdate = 0
local function OnUpdateThrottled(self, elapsed)
    timeSinceUpdate = timeSinceUpdate + elapsed
    if timeSinceUpdate < UPDATE_INTERVAL then return end
    timeSinceUpdate = 0
    OnUpdate()
end

local function OnSettingsUpdate()
    SetLockState()
    -- Re-anchoring the backdrop also moves the protected buttons anchored to it,
    -- so defer during combat lockdown
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    ApplyPosition()
    MoveActionButtons()
    LayoutNumpad()
    ApplyNumpadBindings()
    LayoutFKeys()
    ApplyFKeyBindings()
    ApplyCardStyle()
    OnUpdate()
end

local function OnAwake()
    CreateRTSBackdrop()
    MoveActionButtons()
    LayoutNumpad()
    ApplyNumpadBindings()
    LayoutFKeys()
    ApplyFKeyBindings()
    frame:SetScript("OnUpdate", OnUpdateThrottled)
    Commander.AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnSettingsUpdate)
end

local function OnDestroy()
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        -- A /reload mid-fight fires no PLAYER_REGEN_DISABLED: without this
        -- the bar took the fight for peace and faded, and dropped its combat
        -- border, until the next fight
        inCombat = InCombatLockdown() and true or false
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Apply any layout work that was deferred during combat lockdown
        if loaded and pendingUpdate then
            pendingUpdate = false
            SetLockState()
            ApplyPosition()
            MoveActionButtons()
            LayoutNumpad()
            ApplyNumpadBindings()
            LayoutFKeys()
            ApplyFKeyBindings()
            OnUpdate()
        end
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)

-- ---------------------------------------------------------------------------
-- /cabdiag -- who moved my bar?
--
-- Dormant until you type it, and it never writes anything: it watches. When a
-- frame the grid manages moves, hides or fades on its own, the only way to
-- name what did it -- from inside the client, where we cannot read Blizzard's
-- source -- is to sit on the frame and print a stack the moment it changes.
--
--   /cabdiag        start / stop watching
--   /cabdiag dump   print the current state of every watched frame, once
--
-- Two independent sensors, because they catch different culprits: secure
-- post-hooks name a Lua caller, and a per-frame sampler catches changes that
-- come from layout code with no Lua call to hook. Every line is prefixed
-- [CABdiag] so a chat log greps clean.
--
-- The hooks install on first use and stay for the session (there is no
-- unhook); the `watching` flag is what gates the printing. They are
-- hooksecurefunc post-hooks, which is the taint-safe form, but this is a
-- debugging tool -- leave it off when you are not chasing something.
-- ---------------------------------------------------------------------------
do
    local WATCH = {
        -- The card first: when it stacks at or above the buttons it frames, it
        -- covers them and (unlocked, so mouse-enabled) eats their clicks. Read
        -- its strata/level against ActionButton1's below.
        "RTSActionBarBackdrop",
        "PetActionBar",
        "MainActionBar", "MultiBarBottomLeft",
        "ActionButton1", "MultiBarBottomLeftButton1",
        -- The numpad card and one of its keys, when it has been switched on
        "CommanderActionBarNumpad", "CommanderNumpadButton7",
        -- The function-key row and its F1, likewise
        "CommanderActionBarFKeys", "CommanderFKeyButtonF1",
    }
    local HOOK_METHODS = {
        "SetPoint", "ClearAllPoints", "SetParent", "SetScale",
        "Show", "Hide", "SetShown", "SetAlpha",
    }
    local LINE_CAP = 400

    local watching, lines, hooked = false, 0, {}
    local lastState = {}
    local watcher

    local function Stop(reason)
        watching = false
        if watcher then watcher:SetScript("OnUpdate", nil) end
        print("[CABdiag] off" .. (reason and (" -- " .. reason) or ""))
    end

    local function Say(text)
        if not watching then return end
        lines = lines + 1
        if lines > LINE_CAP then
            Stop("line cap hit, /cabdiag to restart")
            return
        end
        print("[CABdiag] " .. text)
    end

    -- Trimmed call stack: enough frames to cross from the widget method into
    -- whatever addon or Blizzard file actually made the call
    local function Caller()
        local stack = debugstack(3, 5, 0) or "?"
        stack = stack:gsub("[\r\n]+", " <- "):gsub("Interface[/\\]AddOns[/\\]", "")
        return stack:sub(1, 350)
    end

    -- Everything about a frame that these two bugs could be hiding in: is it
    -- shown, is it actually visible (a shown frame under a hidden parent is
    -- not), how faded, whose child, and every anchor it carries
    -- Is Blizzard's container still driving this frame? While it is, it owns
    -- the position and the alpha and nothing we write survives -- so this is
    -- the field to read first when a bar will not stay put.
    local function Managed(f)
        local container = f.GetManagedFrameContainer and f:GetManagedFrameContainer()
        if not container then return "unmanaged" end
        local listed = container.showingFrames and container.showingFrames[f] and "IN-CONTAINER" or "not-listed"
        return string.format("managed(%s,%s,ignoreFPM=%s)",
            container:GetName() or "unnamed", listed, tostring(f.ignoreFramePositionManager))
    end

    local function Signature(f)
        local parent = f:GetParent()
        local out = string.format("%s/%s a=%.2f s=%.2f %s:%d parent=%s %s",
            f:IsShown() and "shown" or "HIDDEN",
            f:IsVisible() and "visible" or "INVISIBLE",
            f:GetAlpha() or 1, f:GetScale() or 1,
            -- Draw/hit order, the pair that decides whether the card frames the
            -- buttons or buries them
            tostring(f:GetFrameStrata()), f:GetFrameLevel() or 0,
            parent and (parent:GetName() or "unnamed") or "none",
            Managed(f))
        for i = 1, f:GetNumPoints() do
            local point, relTo, relPoint, x, y = f:GetPoint(i)
            out = out .. string.format(" | %s->%s.%s(%.1f,%.1f)",
                tostring(point),
                relTo and (relTo:GetName() or "unnamed") or "nil",
                tostring(relPoint), x or 0, y or 0)
        end
        return out
    end

    local function InstallHooks()
        for _, name in ipairs(WATCH) do
            local f = _G[name]
            if f and not hooked[name] then
                hooked[name] = true
                for _, method in ipairs(HOOK_METHODS) do
                    if f[method] then
                        hooksecurefunc(f, method, function()
                            Say(name .. ":" .. method .. "() <- " .. Caller())
                        end)
                    end
                end
            end
        end
    end

    -- The sampler runs every frame, not on the 0.25s poll: a flicker that
    -- resolves inside one poll interval is exactly what we are hunting
    local function Sample()
        for _, name in ipairs(WATCH) do
            local f = _G[name]
            if f then
                local now = Signature(f)
                if lastState[name] ~= now then
                    if lastState[name] then Say(name .. " CHANGED " .. now) end
                    lastState[name] = now
                end
            end
        end
    end

    SLASH_COMMANDERACTIONBARDIAG1 = "/cabdiag"
    SlashCmdList["COMMANDERACTIONBARDIAG"] = function(msg)
        if (msg or ""):lower():match("dump") then
            for _, name in ipairs(WATCH) do
                local f = _G[name]
                print("[CABdiag] " .. name .. " = " .. (f and Signature(f) or "MISSING"))
            end
            return
        end
        if watching then
            Stop()
            return
        end
        watcher = watcher or CreateFrame("Frame")
        InstallHooks()
        wipe(lastState)
        lines = 0
        watching = true
        watcher:SetScript("OnUpdate", Sample)
        print("[CABdiag] on -- watching " .. #WATCH .. " frames. Reproduce the bug, then /cabdiag to stop.")
    end
end

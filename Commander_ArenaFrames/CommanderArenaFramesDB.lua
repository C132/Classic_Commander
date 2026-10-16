CommanderArenaFramesDB = _G.CommanderArenaFramesDB or {}

COMMANDER_ARENAFRAMES_EVENTS = {
    UPDATE = "COMMANDER_ARENAFRAMES_UPDATE"
}

-- Defaults are the opinionated part of this file. The brief was "the best
-- out-of-the-box settings", which is not the same as "everything on": a board
-- with every instrument lit is a board nobody reads at 200ms. So the defaults
-- are what a rank-1 player would actually want visible in a 3v3 — health,
-- mana, cast, DR, trinket, the enemy's cooldowns and their immunities — and
-- the quieter instruments (announcements, sounds, the target-of-target
-- readout, click-casting) are off until asked for, because each of them is a
-- decision about how someone else's team communicates.
local DefaultSettings = {
    Enable = true,

    -- Where the board is allowed to exist. ARENA is the honest default: these
    -- are arena unit tokens and they do not exist anywhere else, so a board
    -- that claims to work in a battleground would just be an empty frame.
    -- TEST is not a setting -- it is /caf test, and it draws over anything.
    HideBlizzardArena = true,   -- Blizzard's own arena frames, hidden while ours is up
    CombatOnly = false,         -- only draw once the gates are open
    ShowInPrep = true,          -- draw during the gates: a placeholder per seat until each enemy is seen

    -- Layout
    Grow = "DOWN",              -- DOWN | UP
    -- Density: the board tightens as the bracket grows. The sizes below are
    -- the ROOMY ones; TIGHT scales every vertical and icon dimension by 0.8
    -- and halves the spacing, and AUTO picks TIGHT from 4 enemies up. Without
    -- this a 5v5 board is five times a 2v2 row and takes half the screen.
    Density = "AUTO",           -- AUTO | ROOMY | TIGHT
    FrameWidth = 200,
    RowHeight = 28,
    RowSpacing = 4,             -- blank space BETWEEN enemy blocks; the target ring is 3px out
    -- Every gap INSIDE a row comes from this one number: icon to bar, band to
    -- band, icon to icon, and the inset keeping text off a bar's edge. 0 is
    -- genuinely flush. Not scaled by density -- shrinking a one-pixel gap has
    -- nowhere to go.
    Padding = 1,
    BarTexture = "GLOSS",       -- FLAT | BLIZZARD | GLOSS | BEVEL | RIDGE | GLASS
    IconRecess = "SOFT",        -- OFF | SOFT | DEEP | CARVED
    SortMode = "FIXED",         -- FIXED (arena1..5, never moves) | HEALTH | ROLE
    -- The look that makes a row read as ONE enemy: a black line around each
    -- element on the top block (class square, bars, trinket) and around the
    -- cast bar, a dark plate under the whole row, and a clock face swept
    -- over every icon that is counting. All three are what Gladdy and
    -- Gladius draw, and what the eye has been trained on for fifteen years.
    ElementBorders = true,
    RowBackdrop = "DARK",       -- NONE | DARK | DARKER
    Sweeps = true,              -- the cooldown spiral on every timed icon

    -- Identity
    ShowName = true,
    NameMaxChars = 10,
    ShowSpec = true,            -- the spec, ONCE they have proven it (never a guess)
    ShowClassIcon = true,
    ShowRace = false,           -- the racial matters more than the race; off by default
    -- CLASS: the row's colour is WHO this is, the way every arena frame since
    -- Gladius has done it -- the priest row is white, the mage's is blue, and
    -- that is read from the corner of the eye before a name could be. How
    -- much is left is the fill and the number; the kill window still turns
    -- the bar red. VALUE (green -> amber -> red) is one dropdown away.
    HealthBarColor = "CLASS",   -- CLASS | VALUE | FLAT
    ClassColorName = false,

    -- Health
    HealthText = "PERCENT",     -- NONE | PERCENT | CURRENT | BOTH | DEFICIT
    HealthTextSize = 11,
    ExecuteRange = 20,          -- % at or under which the bar reddens: the kill window
    ShowExecute = true,

    -- Power. An enemy healer's mana is the single most important number on an
    -- arena board and the one thing the enemy cannot hide, so it is on, it is
    -- tall enough to read, and it carries a number for mana users.
    PowerBar = true,
    PowerBarHeight = 6,
    PowerBarColor = "TYPE",     -- TYPE (blue/red/yellow/...) | CLASS
    PowerText = "MANA",         -- NONE | MANA (percent, mana users only) | ALL

    -- The enemy's pet: a thin bar under a hunter's, warlock's or mage's row
    -- with the pet's family and health. Reserved by class rather than by
    -- presence, so the row never changes height mid-fight.
    PetBars = true,
    PetBarHeight = 10,

    -- Cast bar. The reason to have an enemy frame at all is to kick what is on
    -- it, so this is on, it is its own bar rather than an overlay, and it says
    -- what the cast is.
    CastBar = true,
    CastBarHeight = 12,
    CastBarPosition = "BELOW",  -- BELOW | OVERLAY (drawn on the health bar)
    CastIcon = true,
    CastText = true,
    CastTimer = true,
    CastTarget = false,         -- who the cast is aimed at, when the client will say
    CastSpark = true,           -- the bright edge riding the fill

    -- Diminishing returns. The headline feature; on, and placed where the eye
    -- already is. Only categories that have actually been opened are drawn --
    -- a permanent row of sixteen empty brackets is not information.
    DR = true,
    DRPosition = "RIGHT",       -- RIGHT | LEFT | BELOW
    DRIconSize = 18,
    DRMax = 5,                  -- most categories drawn at once
    DRText = true,              -- the fraction (1/2, 1/4) on the icon
    DRTimer = true,             -- seconds until the category resets
    DRHoldColor = true,         -- a distinct tint while the clock is frozen by an active aura
    DRIcons = "CATEGORY",       -- CATEGORY (Hammer of Justice for stun, Polymorph for poly...) | SPELL (whichever last opened it)
    DRCategories = {},          -- per-category overrides; absent = the default below
    DRDefaultOff = {            -- categories off out of the box: real, rarely decisive
        DISARM = true, CHARM = true, BANISH = true, LIMIT = true,
    },

    -- Enemy cooldowns, learned from the combat log.
    Cooldowns = true,
    CooldownSize = 16,
    -- FIT shrinks the icons just enough to land the whole book on ONE line,
    -- which is what stops a twelve-ability paladin's strip being taller than
    -- his own health bar. WRAP honours CooldownPerRow instead.
    CooldownFit = "FIT",        -- FIT | WRAP
    CooldownPerRow = 8,
    CooldownRoles = { DEF = true, OFF = true, CC = true, KICK = true, UTIL = false },
    CooldownTrack = {},         -- per-ability overrides, keyed "CLASS:Name"
    CooldownUnseen = "GHOST",   -- GHOST (dim, no timer) | HIDE | SHOW (lit like ready)
    CooldownText = true,
    ReadyPulse = true,          -- a white pulse on the rim the moment one comes back

    -- The PvP trinket. Its own slot, never in the cooldown strip: "can they
    -- break my Blind" is asked on its own and answered on its own.
    Trinket = true,
    TrinketFillRow = true,      -- the row's height, exactly like the class square
    TrinketSize = 20,           -- ...or this, when it is not
    TrinketAlert = true,        -- flash the row the moment it is used
    TrinketBadge = true,        -- the trinket again, in the class square's bottom-right corner

    -- Auras on the enemy. Two strips with different jobs: what protects them
    -- (so you stop), and what YOU have on them (so you know your CC is live).
    Auras = true,
    AuraSize = 16,
    AuraMax = 5,
    AuraShow = "NOTED",         -- NOTED (the curated list) | PURGEABLE | ALL
    AuraMineOnly = false,       -- debuffs: only the ones you cast

    -- The state strip: one bar across the enemy's own health bar for the
    -- things that have to stop what you are doing. Crowd control leads it --
    -- who is sapped, who is feared, who is trapped and for how much longer is
    -- the question this board is asked more than any other, and an icon in a
    -- strip is not a way to answer it.
    CCBanner = true,            -- the crowd-control bar
    CCNextBracket = true,       -- ...and what the NEXT one in that category lands at
    CCOnClassIcon = true,       -- the control's icon, sweep and seconds on the class square
    ImmunityBanner = true,      -- a full-width bar across the row while untouchable
    StealthBanner = true,       -- and while they are stealthed

    -- Who is on whom
    TargetHighlight = true,     -- ring the enemy you are targeting
    FocusHighlight = true,      -- and your focus, differently
    ShowTargetOf = false,       -- a mini class icon: who this enemy is targeting
    ShowTargetOfSelf = true,    -- ...but always flag it when the answer is YOU

    -- Click-cast. ON by default: a board of enemy frames you cannot click to
    -- target is a board you have to target around, with tab or a macro, which
    -- is the one thing every arena addon exists to stop. The starting bindings
    -- below are the three clicks that get made constantly -- target, focus,
    -- assist -- so it is useful the moment it loads.
    --
    -- The cost of it being on is that the rows take the mouse, so a click that
    -- lands on the board no longer reaches the world behind it. Turning it off
    -- gives that back and asks for a reload, because the row's frame TYPE (a
    -- secure unit button) cannot be swapped live.
    ClickCast = true,
    ClickBinds = {},            -- [modPrefix .. button] = spellID | "TARGET" | "FOCUS" | false
    RowTooltip = "EXTRAS",      -- FULL | EXTRAS | OFF

    -- Death. There is deliberately no range fade: CheckInteractDistance is
    -- PROTECTED on this client, so the call is blocked in combat and answers
    -- nothing -- which the old code read as "out of range" and used to fade
    -- every enemy on the board, permanently, while raising ADDON_ACTION_BLOCKED
    -- on the paint path. The feature was not degraded, it was inverted, and
    -- the two settings it left behind were controls that changed nothing.
    DeadFade = true,

    -- Alerts. Everything here is off: an alert is a claim on attention, and
    -- which claims are worth making is personal.
    AlertTrinket = false,
    AlertDefensive = false,
    AlertDrink = false,
    AlertSound = false,
    AnnounceTrinket = false,    -- ...to party chat
    AnnounceDefensive = false,
    AnnounceChannel = "PARTY",  -- PARTY | SELF (print locally instead)

    -- Drinking: worth its own instrument. A drinking enemy is out of the game
    -- for as long as you let them be.
    DrinkBanner = true,
}
-- NONE, not DARK. The dark panel insets the whole board by eight pixels on
-- every side, which is by some distance the largest padding anywhere in this
-- module and the most visible, because it is on the outside. An arena board
-- wants to be flush against the world; anyone who wants the panel back is one
-- dropdown away at the bottom of the page.
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "NONE")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderArenaFramesDB, DefaultSettings)
    Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
    print("Commander Arena Frames: settings restored to defaults")
end

local function Enabled()
    return CommanderArenaFramesDB.Enable
end

-- ---------------------------------------------------------------------------
-- Per-item override helpers. Both grids below (DR categories, enemy
-- cooldowns) store only what the user has CHANGED, so the saved variables
-- never carry a row for something left alone -- which means a later change to
-- a default actually reaches everyone who never touched it.
-- ---------------------------------------------------------------------------

local function OverrideGet(field, key, fallback)
    local store = CommanderArenaFramesDB[field]
    local stored = store and store[key]
    if stored == nil then return fallback end
    return stored and true or false
end

local function OverrideSet(field, key, value, fallback)
    local store = CommanderArenaFramesDB[field]
    if not store then
        store = {}
        CommanderArenaFramesDB[field] = store
    end
    if (value and true or false) == (fallback and true or false) then
        store[key] = nil          -- back to the default: forget it entirely
    else
        store[key] = value and true or false
    end
end

local function DRDefault(key)
    return not (CommanderArenaFramesDB.DRDefaultOff or {})[key]
end

-- Read by the engine as well as by this page, so the two can never disagree
-- about which categories are live.
function CommanderArenaFrames_DRTracked(key)
    return OverrideGet("DRCategories", key, DRDefault(key))
end

-- An ability's own default. Most are on; the rotational ones the book marks
-- `off` (Mortal Strike, Mind Blast, Conflagrate...) start hidden, because a
-- six-second cooldown on a strip is a light that blinks constantly and never
-- tells you anything you would act on. They stay one click away in the grid.
local function CooldownDefault(classToken, name)
    local entry = CommanderArenaFrames_Engine.BookEntry(classToken, nil, nil, name)
    return not (entry and entry.off)
end

function CommanderArenaFrames_CooldownTracked(classToken, name)
    return OverrideGet("CooldownTrack", classToken .. ":" .. name,
                       CooldownDefault(classToken, name))
end

-- ---------------------------------------------------------------------------
-- A toggle GRID. Both per-item lists on this page are the same shape -- a
-- caption, a lot of small things, each on or off -- and a column of forty
-- checkboxes is unreadable and unscrollable. So: cells laid out in rows,
-- lit when tracked and ghosted when not, each with its own tooltip.
--
-- Built once and refreshed like any other widget, so the panel's normal
-- Refresh keeps it in step with a Restore Defaults or a change made from a
-- slash command.
-- ---------------------------------------------------------------------------

local CELL_W, CELL_H, CELL_GAP = 116, 20, 4

local function PaintCell(cell)
    local on = cell.isOn()
    cell.bg:SetVertexColor(on and 0.22 or 0.10, on and 0.30 or 0.10, on and 0.24 or 0.10, 0.9)
    cell.label:SetTextColor(on and 1 or 0.45, on and 1 or 0.45, on and 1 or 0.45)
    if cell.swatch then
        local r, g, b = cell.swatchColor()
        cell.swatch:SetVertexColor(r, g, b, on and 1 or 0.35)
    end
end

local function NewCell(panel, row, index, perRow, spec)
    local cell = CreateFrame("Button", nil, row)
    cell:SetSize(CELL_W, CELL_H)
    local col = (index - 1) % perRow
    local line = math.floor((index - 1) / perRow)
    cell:SetPoint("TOPLEFT", row, "TOPLEFT",
        col * (CELL_W + CELL_GAP), -line * (CELL_H + CELL_GAP))

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    cell.bg:SetAllPoints()

    local textLeft = 5
    if spec.swatchColor then
        cell.swatch = cell:CreateTexture(nil, "ARTWORK")
        cell.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        cell.swatch:SetSize(3, CELL_H - 6)
        cell.swatch:SetPoint("LEFT", cell, "LEFT", 3, 0)
        cell.swatchColor = spec.swatchColor
        textLeft = 10
    end

    cell.label = cell:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cell.label:SetPoint("LEFT", cell, "LEFT", textLeft, 0)
    cell.label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
    cell.label:SetJustifyH("LEFT")
    cell.label:SetText(spec.label)

    cell.isOn = spec.isOn
    cell:SetScript("OnClick", function(self)
        spec.toggle(not self.isOn())
        PaintCell(self)
        panel:_Changed()
    end)
    Commander.UI.AttachTooltip(cell, spec.label, spec.tooltip)
    panel:AddRefresher(function() PaintCell(cell) end)
    return cell
end

-- specs: array of { label, tooltip, isOn, toggle, swatchColor }
local function AddGrid(panel, specs, perRow)
    perRow = perRow or 4
    local lines = math.ceil(#specs / perRow)
    local row = panel:AddRow(lines * (CELL_H + CELL_GAP), 6)
    for i, spec in ipairs(specs) do
        NewCell(panel, row, i, perRow, spec)
    end
    return row
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function AddBoardSection(panel)
    panel:AddSection("Board",
        "Where the board lives and how it is shaped. It draws on arena unit tokens, which exist only inside an arena -- there is nothing for it to read in a battleground, so it does not pretend to. Use /caf test anywhere to lay it out.")

    panel:AddCheckboxPair({
        label = "Hide Blizzard's Arena Frames",
        tooltip = "Hide the default enemy frames while this board is up, and give them back the moment it is switched off. Blizzard's frames are not removed, only hidden, so nothing about the game's own UI is broken by turning this on.",
        get = function() return CommanderArenaFramesDB.HideBlizzardArena end,
        set = function(value) CommanderArenaFramesDB.HideBlizzardArena = value end,
        isEnabled = Enabled,
    }, {
        label = "Show During the Gates",
        tooltip = "Draw the board in the preparation phase, before the gates open: one row per seat in the bracket, each a placeholder until that enemy has been seen, so a rogue who opens from stealth already has the row you will click. Off keeps the board out of sight until the first enemy is spotted. Either way the rows themselves are put in place before the gates -- with Click-Casting on that is the only moment the client allows it.",
        get = function() return CommanderArenaFramesDB.ShowInPrep end,
        set = function(value) CommanderArenaFramesDB.ShowInPrep = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Combat Only",
        tooltip = "Keep the board hidden until the gates open and the fight starts. Off by default: the seconds before the gates are when the opener is decided.",
        get = function() return CommanderArenaFramesDB.CombatOnly end,
        set = function(value) CommanderArenaFramesDB.CombatOnly = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdownPair({
        label = "Grow",
        tooltip = "Which way the rows stack from the anchor.",
        options = { { text = "Down", value = "DOWN" }, { text = "Up", value = "UP" } },
        get = function() return CommanderArenaFramesDB.Grow end,
        set = function(value) CommanderArenaFramesDB.Grow = value end,
        isEnabled = Enabled,
    }, {
        label = "Order",
        tooltip = "Fixed keeps each enemy on the slot the client gave them (arena1 at the top, always) -- which is what makes muscle memory possible, and why it is the default. The other two re-sort live, and a row that moves is a row you have to read before you click it.\n\nWith Click-Casting on this is forced to Fixed and this control does nothing: a secure row is bound to its unit once, out of combat, so re-ordering the art over it would leave a row showing one enemy and targeting another.",
        options = {
            { text = "Fixed", value = "FIXED" },
            { text = "Lowest health", value = "HEALTH" },
            { text = "Healers first", value = "ROLE" },
        },
        get = function() return CommanderArenaFramesDB.SortMode end,
        set = function(value) CommanderArenaFramesDB.SortMode = value end,
        isEnabled = function() return Enabled() and not CommanderArenaFramesDB.ClickCast end,
    })

    panel:AddDropdownPair({
        label = "Density",
        tooltip = "How tightly the board packs itself. Auto is the point of the setting: the same sizes that read comfortably against two enemies are half a screen against five, so from 4v4 up the board scales every vertical and icon dimension to 80% and halves the spacing between enemies. Roomy and Tight pin it either way.\n\nThe frame WIDTH is never scaled -- you chose that number, and a board that changes width between games is a board you have to find again.",
        options = {
            { text = "Auto (by bracket)", value = "AUTO" },
            { text = "Always roomy", value = "ROOMY" },
            { text = "Always tight", value = "TIGHT" },
        },
        get = function() return CommanderArenaFramesDB.Density end,
        set = function(value) CommanderArenaFramesDB.Density = value end,
        isEnabled = Enabled,
    }, {
        label = "Cooldown Strip",
        tooltip = "Fit shrinks the cooldown icons just enough to land a whole class book on ONE line -- twelve abilities across a 200-pixel frame is sixteen pixels each, which is the size they were anyway. It exists because a wrapped strip is the tallest thing on the row: a paladin's twelve abilities at eight per line made a block of cooldowns taller than his own health bar, five times over in a 5v5. Wrap honours the per-line number below instead.",
        options = { { text = "Fit to one line", value = "FIT" }, { text = "Wrap", value = "WRAP" } },
        get = function() return CommanderArenaFramesDB.CooldownFit end,
        set = function(value) CommanderArenaFramesDB.CooldownFit = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns end,
    })

    panel:AddSliderPair({
        label = "Width", min = 140, max = 340, step = 2,
        format = function(v) return string.format("%dpx", v or 0) end,
        tooltip = "Overall width of each enemy's row.",
        get = function() return CommanderArenaFramesDB.FrameWidth end,
        set = function(value) CommanderArenaFramesDB.FrameWidth = value end,
        isEnabled = Enabled,
    }, {
        label = "Row Height", min = 20, max = 60, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        tooltip = "Height of the health bar and the identity block beside it, on a roomy board. The strips below it are sized separately, and a tight board scales all of them down together.",
        get = function() return CommanderArenaFramesDB.RowHeight end,
        set = function(value) CommanderArenaFramesDB.RowHeight = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Spacing", min = 0, max = 40, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        tooltip = "Blank space between one enemy's block and the next. Each block already contains its own cast bar, cooldown strip and auras and grows to fit them; this is only the breathing room BETWEEN blocks, and a tight board halves it again.",
        get = function() return CommanderArenaFramesDB.RowSpacing end,
        set = function(value) CommanderArenaFramesDB.RowSpacing = value end,
        isEnabled = Enabled,
    }, {
        label = "Padding", min = 0, max = 6, step = 1,
        format = function(v) return (v or 0) == 0 and "flush" or string.format("%dpx", v) end,
        tooltip = "Every gap INSIDE a row comes from this one number -- class icon to bar, one band to the next, icon to icon in a strip, and the inset that keeps text off the edge of its own bar. At 0 the board is genuinely flush, with the only remaining space being the pixel that stops a number reading as clipped.\n\nThis is not scaled by density: shrinking a one-pixel gap has nowhere to go. If the board still feels boxed in after this, the space around the OUTSIDE of it belongs to Frame Style at the bottom of this page -- set it to None for no backdrop at all.",
        get = function() return CommanderArenaFramesDB.Padding end,
        set = function(value) CommanderArenaFramesDB.Padding = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdownPair({
        label = "Bar Texture",
        tooltip = "How the fills are drawn.",
        options = {
            { text = "Flat", value = "FLAT" }, { text = "Blizzard", value = "BLIZZARD" },
            { text = "Gloss", value = "GLOSS" }, { text = "Bevel", value = "BEVEL" },
            { text = "Ridge", value = "RIDGE" }, { text = "Glass", value = "GLASS" },
        },
        get = function() return CommanderArenaFramesDB.BarTexture end,
        set = function(value) CommanderArenaFramesDB.BarTexture = value end,
        isEnabled = Enabled,
    }, {
        label = "Icon Shading",
        tooltip = "How deeply icons are set into the board.",
        options = Commander.ICON_STYLES,
        get = function() return CommanderArenaFramesDB.IconRecess end,
        set = function(value) CommanderArenaFramesDB.IconRecess = value end,
        isEnabled = Enabled,
    })

    -- Three sizes in one click. The sliders below are the fine control;
    -- these are the coarse one, and "Gladdy-sized" is there because a
    -- player coming from Gladdy is used to a 60-pixel bar and will find a
    -- 28-pixel one small before they find it tidy.
    local SIZE_PRESETS = {
        COMPACT  = { FrameWidth = 200, RowHeight = 28, PowerBarHeight = 6,  CastBarHeight = 12,
                     DRIconSize = 18, CooldownSize = 16, AuraSize = 16, PetBarHeight = 10, HealthTextSize = 11 },
        STANDARD = { FrameWidth = 240, RowHeight = 36, PowerBarHeight = 8,  CastBarHeight = 14,
                     DRIconSize = 24, CooldownSize = 20, AuraSize = 20, PetBarHeight = 12, HealthTextSize = 13 },
        LARGE    = { FrameWidth = 280, RowHeight = 48, PowerBarHeight = 10, CastBarHeight = 18,
                     DRIconSize = 32, CooldownSize = 24, AuraSize = 24, PetBarHeight = 14, HealthTextSize = 15 },
    }
    local function ApplyPreset(key)
        for setting, value in pairs(SIZE_PRESETS[key]) do
            CommanderArenaFramesDB[setting] = value
        end
        Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
    end
    panel:AddButtonRow({
        { label = "Compact", width = 110,
          tooltip = "The sizes the board ships with: a 28-pixel row, 200 wide. Sets every size slider on this page at once.",
          onClick = function() ApplyPreset("COMPACT") end, isEnabled = Enabled },
        { label = "Standard", width = 110,
          tooltip = "A 36-pixel row, 240 wide, with every icon scaled to match.",
          onClick = function() ApplyPreset("STANDARD") end, isEnabled = Enabled },
        { label = "Gladdy-sized", width = 110,
          tooltip = "A 48-pixel row, 280 wide: close to what Gladdy draws by default. Every size slider on this page moves with it; the sliders remain the fine control.",
          onClick = function() ApplyPreset("LARGE") end, isEnabled = Enabled },
    })

    panel:AddDropdownPair({
        label = "Row Plate",
        tooltip = "A dark plate under each enemy's whole row -- bars, cast bar, cooldowns and auras together -- so the row reads as one enemy rather than as five things that happen to be near each other. Per row, so the space BETWEEN enemies stays open. Darker is for a bright map; None is the world showing through.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Dark", value = "DARK" },
            { text = "Darker", value = "DARKER" },
        },
        get = function() return CommanderArenaFramesDB.RowBackdrop end,
        set = function(value) CommanderArenaFramesDB.RowBackdrop = value end,
        isEnabled = Enabled,
    }, nil)

    panel:AddCheckboxPair({
        label = "Black Borders",
        tooltip = "A one-pixel black line around the class square, the bars, the trinket and the cast bar. It is the single thing that most makes a row look like a frame rather than a stack of coloured rectangles, and every arena addon since Gladius has drawn it.",
        get = function() return CommanderArenaFramesDB.ElementBorders end,
        set = function(value) CommanderArenaFramesDB.ElementBorders = value end,
        isEnabled = Enabled,
    }, {
        label = "Clock Faces",
        tooltip = "The cooldown spiral over every icon that is counting: an enemy cooldown, a diminishing-returns reset, the trinket, an aura, the control on the class square. How much is left reads from the face before the number can be read at all.",
        get = function() return CommanderArenaFramesDB.Sweeps end,
        set = function(value) CommanderArenaFramesDB.Sweeps = value end,
        isEnabled = Enabled,
    })
end

local function AddIdentitySection(panel)
    panel:AddSection("Identity",
        "Who the row is. Specialization is shown only once an enemy has PROVEN it by casting something nothing else can cast -- the board never guesses a spec from a class, because \"probably a resto druid\" costs more than it pays on the one game it is wrong.")

    panel:AddCheckboxPair({
        label = "Name",
        tooltip = "The enemy's name on the row.",
        get = function() return CommanderArenaFramesDB.ShowName end,
        set = function(value) CommanderArenaFramesDB.ShowName = value end,
        isEnabled = Enabled,
    }, {
        label = "Class Icon",
        tooltip = "The class portrait leading each row -- the fastest read on the board, and the one that works while the name is still unknown.",
        get = function() return CommanderArenaFramesDB.ShowClassIcon end,
        set = function(value) CommanderArenaFramesDB.ShowClassIcon = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Specialization",
        tooltip = "Append the spec once it has been revealed -- \"Rogue\" becomes \"Sub\" the moment a Shadowstep lands. TBC has no specialization API, so this is the only honest source: what they have actually cast.",
        get = function() return CommanderArenaFramesDB.ShowSpec end,
        set = function(value) CommanderArenaFramesDB.ShowSpec = value end,
        isEnabled = Enabled,
    }, {
        label = "Race",
        tooltip = "Show the enemy's race next to their specialization. Off by default: what actually matters about a race is its racial, and every one of those already has its own slot on the cooldown strip.",
        get = function() return CommanderArenaFramesDB.ShowRace end,
        set = function(value) CommanderArenaFramesDB.ShowRace = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdown({
        label = "Health Bar Colour",
        tooltip = "What the fill's colour says. By Class: the enemy's class colour, so the bar says WHO -- the priest row is white and the mage's is blue, read from the corner of the eye before a name could be, which is how every arena frame since Gladius has done it. By Value: green at full, amber at half, red as it empties -- the number said a second way. Plain: the same red on every bar. Whichever is chosen, the execute window below still turns the bar its own red.",
        options = {
            { text = "By class", value = "CLASS" },
            { text = "By value", value = "VALUE" },
            { text = "Plain red", value = "FLAT" },
        },
        get = function() return CommanderArenaFramesDB.HealthBarColor end,
        set = function(value) CommanderArenaFramesDB.HealthBarColor = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Class-Coloured Names",
        tooltip = "Colour the name text by the enemy's class. Off by default -- with the class icon beside it, colouring the name as well says the same thing twice and costs contrast.",
        get = function() return CommanderArenaFramesDB.ClassColorName end,
        set = function(value) CommanderArenaFramesDB.ClassColorName = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Name Length", min = 4, max = 14, step = 1,
        format = function(v) return string.format("%d chars", v or 0) end,
        tooltip = "Truncate names past this many characters, so a long name cannot push the numbers off the row.",
        get = function() return CommanderArenaFramesDB.NameMaxChars end,
        set = function(value) CommanderArenaFramesDB.NameMaxChars = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.ShowName end,
    })
end

local function AddVitalsSection(panel)
    panel:AddSection("Health & Power",
        "An enemy healer's mana is the one number they cannot hide and the one an arena is most often decided by, so the power strip is on, tall enough to read, and carries a percentage of its own.")

    panel:AddDropdownPair({
        label = "Health Text",
        tooltip = "What the number on the health bar says.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Percent", value = "PERCENT" },
            { text = "Current", value = "CURRENT" },
            { text = "Both", value = "BOTH" },
            { text = "Missing", value = "DEFICIT" },
        },
        get = function() return CommanderArenaFramesDB.HealthText end,
        set = function(value) CommanderArenaFramesDB.HealthText = value end,
        isEnabled = Enabled,
    }, {
        label = "Power Text",
        tooltip = "Mana shows a percentage only for the classes that actually run on mana -- a rogue's energy is already fully described by the strip, and a number on it is noise.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Mana only", value = "MANA" },
            { text = "Everyone", value = "ALL" },
        },
        get = function() return CommanderArenaFramesDB.PowerText end,
        set = function(value) CommanderArenaFramesDB.PowerText = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.PowerBar end,
    })

    panel:AddCheckboxPair({
        label = "Power Strip",
        tooltip = "A live resource strip under each health bar -- mana, rage, energy, a pet's focus. It is what tells you a healer is nearly out and a rogue is about to open.",
        get = function() return CommanderArenaFramesDB.PowerBar end,
        set = function(value) CommanderArenaFramesDB.PowerBar = value end,
        isEnabled = Enabled,
    }, {
        label = "Kill Window",
        tooltip = "Redden the health bar once the enemy drops under the threshold below, so the moment to commit everything is visible without reading a number.",
        get = function() return CommanderArenaFramesDB.ShowExecute end,
        set = function(value) CommanderArenaFramesDB.ShowExecute = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Power Height", min = 3, max = 16, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        tooltip = "Height of the resource strip. The row does not grow with it.",
        get = function() return CommanderArenaFramesDB.PowerBarHeight end,
        set = function(value) CommanderArenaFramesDB.PowerBarHeight = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.PowerBar end,
    }, {
        label = "Kill Window At", min = 5, max = 50, step = 1,
        format = function(v) return string.format("%d%%", v or 0) end,
        tooltip = "Health at or under which the bar turns to the kill colour.",
        get = function() return CommanderArenaFramesDB.ExecuteRange end,
        set = function(value) CommanderArenaFramesDB.ExecuteRange = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.ShowExecute end,
    })

    panel:AddCheckbox({
        label = "Pet Bars",
        tooltip = "A thin bar at the foot of a hunter's, warlock's or mage's row with their pet's family and health -- Felhunter, Succubus, Water Elemental. Killing the Felhunter is a decision an arena is made of, and nothing else on the board can inform it. The band is reserved by class rather than by whether a pet is out, so a row never changes height mid-fight; with no pet it reads \"no pet\".",
        get = function() return CommanderArenaFramesDB.PetBars end,
        set = function(value) CommanderArenaFramesDB.PetBars = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Pet Bar Height", min = 5, max = 16, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        get = function() return CommanderArenaFramesDB.PetBarHeight end,
        set = function(value) CommanderArenaFramesDB.PetBarHeight = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.PetBars end,
    })

    panel:AddSlider({
        label = "Health Text Size", min = 8, max = 20, step = 1,
        format = function(v) return string.format("%dpt", v or 0) end,
        tooltip = "Point size of the number on the health bar. Worth raising: it is read in peripheral vision while your eyes are on the enemy, not on the board.",
        get = function() return CommanderArenaFramesDB.HealthTextSize end,
        set = function(value) CommanderArenaFramesDB.HealthTextSize = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.HealthText ~= "NONE" end,
    })

    panel:AddDropdown({
        label = "Power Colour",
        tooltip = "By resource gives each its own colour -- blue mana, red rage, yellow energy -- which means the strip says WHAT they run on before you have read anything else.",
        options = { { text = "By resource", value = "TYPE" }, { text = "By class", value = "CLASS" } },
        get = function() return CommanderArenaFramesDB.PowerBarColor end,
        set = function(value) CommanderArenaFramesDB.PowerBarColor = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.PowerBar end,
    })
end

local function AddCastSection(panel)
    panel:AddSection("Cast Bar",
        "The reason to look at an enemy frame at all is to kick what is on it, so each enemy gets a real cast bar rather than a tint on the health bar. Channels are drawn too, draining rather than filling.")

    panel:AddCheckboxPair({
        label = "Cast Bars",
        tooltip = "A cast bar per enemy, fed by their unit token.",
        get = function() return CommanderArenaFramesDB.CastBar end,
        set = function(value) CommanderArenaFramesDB.CastBar = value end,
        isEnabled = Enabled,
    }, {
        label = "Spell Icon",
        tooltip = "The spell's icon at the head of the bar -- the fastest way to tell a Polymorph from a Frostbolt without reading.",
        get = function() return CommanderArenaFramesDB.CastIcon end,
        set = function(value) CommanderArenaFramesDB.CastIcon = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    })

    panel:AddCheckboxPair({
        label = "Spell Name",
        tooltip = "Name the spell on the bar.",
        get = function() return CommanderArenaFramesDB.CastText end,
        set = function(value) CommanderArenaFramesDB.CastText = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    }, {
        label = "Time Left",
        tooltip = "Seconds remaining on the cast, on the right of the bar -- the number a kick is timed against.",
        get = function() return CommanderArenaFramesDB.CastTimer end,
        set = function(value) CommanderArenaFramesDB.CastTimer = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    })

    panel:AddCheckboxPair({
        label = "Cast Target",
        tooltip = "Show who the cast is aimed at, when the client will say. It often will not for an enemy -- there is no API that reports another player's spell target, so this is read from who they are TARGETING, which is right for a direct cast and wrong for a smart heal. Off by default for that reason.",
        get = function() return CommanderArenaFramesDB.CastTarget end,
        set = function(value) CommanderArenaFramesDB.CastTarget = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    }, {
        label = "Spark",
        tooltip = "The bright edge riding the head of the fill. Where the cast is, without reading the number.",
        get = function() return CommanderArenaFramesDB.CastSpark end,
        set = function(value) CommanderArenaFramesDB.CastSpark = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    })

    panel:AddDropdownPair({
        label = "Position",
        tooltip = "Below keeps the health bar clean and gives the cast its own space. Overlay draws it across the health bar, which is tighter and harder to read at speed.",
        options = { { text = "Below the row", value = "BELOW" }, { text = "Over the health bar", value = "OVERLAY" } },
        get = function() return CommanderArenaFramesDB.CastBarPosition end,
        set = function(value) CommanderArenaFramesDB.CastBarPosition = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    }, nil)

    panel:AddSlider({
        label = "Cast Bar Height", min = 6, max = 24, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        get = function() return CommanderArenaFramesDB.CastBarHeight end,
        set = function(value) CommanderArenaFramesDB.CastBarHeight = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CastBar end,
    })
end

-- ---------------------------------------------------------------------------
-- Diminishing returns
-- ---------------------------------------------------------------------------

-- Each category gets a colour so the bracket is legible without reading its
-- label -- three cues, the way the party board does it: position (a fixed
-- slot), colour (the category), and the fraction itself.
local DR_TINT = {
    STUN      = { 0.98, 0.86, 0.35 },
    STUN_PROC = { 0.78, 0.68, 0.30 },
    KIDNEY    = { 1.00, 0.72, 0.28 },
    BLIND     = { 0.72, 0.52, 0.95 },
    POLY      = { 0.55, 0.78, 0.98 },
    FEAR      = { 0.85, 0.42, 0.85 },
    ROOT      = { 0.45, 0.85, 0.80 },
    ROOT_PROC = { 0.35, 0.66, 0.62 },
    FREEZE    = { 0.62, 0.88, 1.00 },
    SLEEP     = { 0.60, 0.60, 0.95 },
    BANISH    = { 0.70, 0.45, 0.95 },
    HORROR    = { 0.55, 0.35, 0.55 },
    DISARM    = { 0.80, 0.80, 0.80 },
    CHARM     = { 0.95, 0.55, 0.55 },
    DRAGONS   = { 0.98, 0.55, 0.28 },
    LIMIT     = { 0.60, 0.72, 0.55 },
}
CommanderArenaFrames_DRTint = DR_TINT

local function AddDRSection(panel)
    panel:AddSection("Diminishing Returns",
        "The bracket the NEXT piece of control in each category would land at: full, half, quarter, immune. Only categories that have actually been opened are drawn -- a permanent row of sixteen empty brackets is not information. The clock under each one is the fifteen seconds to reset, and it starts when the aura FADES rather than when it lands, which is the difference between a board you can trust on a re-stun and one that is optimistic by the whole length of the first CC.")

    panel:AddCheckboxPair({
        label = "Track Diminishing Returns",
        tooltip = "The whole feature. Categories are read from the client's own spell data, so every rank of every spell counts -- including the triggered auras nobody trains, like Freezing Trap Effect.",
        get = function() return CommanderArenaFramesDB.DR end,
        set = function(value) CommanderArenaFramesDB.DR = value end,
        isEnabled = Enabled,
    }, {
        label = "Show the Fraction",
        tooltip = "Write 1/2, 1/4 or IMM on each bracket. With this off the icon's tint and its border carry it alone.",
        get = function() return CommanderArenaFramesDB.DRText end,
        set = function(value) CommanderArenaFramesDB.DRText = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    })

    panel:AddCheckboxPair({
        label = "Reset Timer",
        tooltip = "Count the fifteen seconds down under each bracket, so a re-stun can be timed rather than guessed.",
        get = function() return CommanderArenaFramesDB.DRTimer end,
        set = function(value) CommanderArenaFramesDB.DRTimer = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    }, {
        label = "Mark a Held Category",
        tooltip = "Tint a bracket differently while something in that category is still ON them -- because the reset clock is not running yet, and a bracket showing no timer for that reason means something quite different from one that has finished counting.",
        get = function() return CommanderArenaFramesDB.DRHoldColor end,
        set = function(value) CommanderArenaFramesDB.DRHoldColor = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    })

    panel:AddDropdown({
        label = "Bracket Icons",
        tooltip = "The picture each bracket wears. Category is the classic set every DR tracker has taught -- Hammer of Justice for a stun, Polymorph for the polymorph ladder, Fear for fear, Kidney Shot, Blind, Frost Nova for a root -- always the same picture for the same ladder, in its own colours. Last Spell is whichever spell most recently opened the ladder, washed in the category's tint: more to read, and a different icon every time.",
        options = {
            { text = "Category (classic)", value = "CATEGORY" },
            { text = "Last spell", value = "SPELL" },
        },
        width = 180,
        get = function() return CommanderArenaFramesDB.DRIcons end,
        set = function(value) CommanderArenaFramesDB.DRIcons = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    })

    panel:AddSliderPair({
        label = "Bracket Size", min = 12, max = 34, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        get = function() return CommanderArenaFramesDB.DRIconSize end,
        set = function(value) CommanderArenaFramesDB.DRIconSize = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    }, {
        label = "Most at Once", min = 2, max = 8, step = 1,
        format = function(v) return string.format("%d", v or 0) end,
        tooltip = "Cap on how many categories are drawn for one enemy, worst bracket first. Five is enough for anything a 3v3 produces.",
        get = function() return CommanderArenaFramesDB.DRMax end,
        set = function(value) CommanderArenaFramesDB.DRMax = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    })

    panel:AddDropdown({
        label = "Bracket Position",
        tooltip = "Where the brackets sit relative to the row.",
        options = {
            { text = "Right of the row", value = "RIGHT" },
            { text = "Left of the row", value = "LEFT" },
            { text = "Below the row", value = "BELOW" },
        },
        get = function() return CommanderArenaFramesDB.DRPosition end,
        set = function(value) CommanderArenaFramesDB.DRPosition = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.DR end,
    })

    panel:AddSection("Categories Tracked",
        "TBC's own categories, straight out of the rules the server enforces -- which is why Kidney Shot is here on its own (it does not share the stun ladder), why cast stuns and PROC stuns are separate, and why there is no silence entry at all: silence has no diminishing returns until 3.0.8. Four are off out of the box because they are real but rarely decide a game.")

    local specs = {}
    for _, group in ipairs(CommanderArenaFrames_Data.DR_GROUPS) do
        specs[#specs + 1] = {
            label = group.label,
            tooltip = group.note .. "\n\nDiminishes on: "
                .. (group.drtype == "ALL" and "players and creatures alike."
                    or group.drtype == "PLAYER" and "players only."
                    or "nothing -- this one is only a duration cap."),
            isOn = function() return CommanderArenaFrames_DRTracked(group.key) end,
            toggle = function(value)
                OverrideSet("DRCategories", group.key, value, DRDefault(group.key))
            end,
            swatchColor = function()
                local tint = DR_TINT[group.key] or { 1, 1, 1 }
                return tint[1], tint[2], tint[3]
            end,
        }
    end
    AddGrid(panel, specs, 4)

    panel:AddButtonRow({
        {
            label = "All Categories",
            tooltip = "Track every category, including the four that are off by default.",
            onClick = function()
                CommanderArenaFramesDB.DRCategories = {}
                for _, group in ipairs(CommanderArenaFrames_Data.DR_GROUPS) do
                    OverrideSet("DRCategories", group.key, true, DRDefault(group.key))
                end
                Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
            end,
        },
        {
            label = "Default Set",
            tooltip = "Back to the categories tracked out of the box.",
            onClick = function()
                CommanderArenaFramesDB.DRCategories = {}
                Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
            end,
        },
    })
end

-- ---------------------------------------------------------------------------
-- Enemy cooldowns
-- ---------------------------------------------------------------------------

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local ROLE_LABEL = {
    DEF = "Defensive", OFF = "Offensive", CC = "Control",
    KICK = "Interrupt", UTIL = "Utility",
}
local ROLE_NOTE = {
    DEF  = "They survive with it: Ice Block, Divine Shield, Cloak of Shadows, Shield Wall. Knowing one is down is knowing the kill is real.",
    OFF  = "They kill with it: Death Wish, Bestial Wrath, Icy Veins, Avenging Wrath. The cue to peel, or to spend your own.",
    CC   = "The control they can land on you next -- and the one number that says whether you can afford to be out of position.",
    KICK = "Their interrupt. A kick on cooldown is a free cast, and it is the single most valuable thing on this list for any caster.",
    UTIL = "Mobility, dispels, mana. Real, but the busiest category and the least often decisive, so it is off by default.",
}
local ROLE_TINT = {
    DEF = { 0.55, 0.80, 1.00 }, OFF = { 1.00, 0.55, 0.45 }, CC = { 0.85, 0.60, 1.00 },
    KICK = { 1.00, 0.85, 0.40 }, UTIL = { 0.70, 0.85, 0.70 },
}
CommanderArenaFrames_RoleTint = ROLE_TINT

local cooldownClass = "MAGE"   -- which class the grid below is showing

local function AddCooldownSection(panel)
    panel:AddSection("Enemy Cooldowns",
        "What each enemy has spent, learned from the combat log -- the client will not tell you an enemy's cooldowns, so every entry here was witnessed. Two things the board is honest about that most are not: an ability never seen used is UNKNOWN rather than ready (they may have opened with it out of sight), and the timer is the BASE cooldown, since the log never says which talents they took. Abilities carrying a talent that shortens them say so on the tooltip.")

    panel:AddCheckboxPair({
        label = "Track Enemy Cooldowns",
        tooltip = "The cooldown strip under each enemy. Slots are in a fixed order per class, so a cooldown is in the same place every game -- which is the only way a strip is readable at a glance.",
        get = function() return CommanderArenaFramesDB.Cooldowns end,
        set = function(value) CommanderArenaFramesDB.Cooldowns = value end,
        isEnabled = Enabled,
    }, {
        label = "Time Remaining",
        tooltip = "Write the seconds left on each icon, as well as sweeping it.",
        get = function() return CommanderArenaFramesDB.CooldownText end,
        set = function(value) CommanderArenaFramesDB.CooldownText = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns end,
    })

    panel:AddCheckbox({
        label = "Pulse When Ready",
        tooltip = "The moment a cooldown comes BACK is worth more than the whole time it was down -- \"their trinket is up again\" is the fact that ends a setup. The icon's rim pulses white for a second when one returns, on the strip and on the trinket.",
        get = function() return CommanderArenaFramesDB.ReadyPulse end,
        set = function(value) CommanderArenaFramesDB.ReadyPulse = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns end,
    })

    panel:AddSliderPair({
        label = "Icon Size", min = 12, max = 30, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        tooltip = "Icon size on a roomy board, and the CEILING on a tight one -- Fit and the density setting only ever make them smaller, never larger than this.",
        get = function() return CommanderArenaFramesDB.CooldownSize end,
        set = function(value) CommanderArenaFramesDB.CooldownSize = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns end,
    }, {
        label = "Per Line", min = 4, max = 16, step = 1,
        format = function(v) return string.format("%d", v or 0) end,
        tooltip = "How many icons go on one line before the strip wraps. Only used when the strip is set to Wrap -- on Fit the line length is whatever it takes to show the whole book at once.",
        get = function() return CommanderArenaFramesDB.CooldownPerRow end,
        set = function(value) CommanderArenaFramesDB.CooldownPerRow = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns
            and CommanderArenaFramesDB.CooldownFit == "WRAP" end,
    })

    panel:AddDropdown({
        label = "Never Seen Used",
        tooltip = "How to draw an ability nobody has watched them spend. Ghosted is the honest answer -- it says \"we have not seen this\", which is a different bet from \"this is up\". Showing it lit reads as knowledge the board does not have.",
        options = {
            { text = "Ghosted", value = "GHOST" },
            { text = "Hidden until used", value = "HIDE" },
            { text = "Lit, as if ready", value = "SHOW" },
        },
        get = function() return CommanderArenaFramesDB.CooldownUnseen end,
        set = function(value) CommanderArenaFramesDB.CooldownUnseen = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns end,
    })

    panel:AddSection("Which Kinds", nil)
    local roleSpecs = {}
    for _, role in ipairs({ "DEF", "OFF", "CC", "KICK", "UTIL" }) do
        roleSpecs[#roleSpecs + 1] = {
            label = ROLE_LABEL[role],
            tooltip = ROLE_NOTE[role],
            isOn = function() return (CommanderArenaFramesDB.CooldownRoles or {})[role] end,
            toggle = function(value)
                CommanderArenaFramesDB.CooldownRoles = CommanderArenaFramesDB.CooldownRoles or {}
                CommanderArenaFramesDB.CooldownRoles[role] = value and true or false
            end,
            swatchColor = function()
                local tint = ROLE_TINT[role]
                return tint[1], tint[2], tint[3]
            end,
        }
    end
    AddGrid(panel, roleSpecs, 5)

    panel:AddSection("Per Ability",
        "Everything the book knows, one class at a time. Switching a kind off above hides its abilities wherever they appear; switching one OFF here hides just that ability, and survives changing your mind about the kind.")

    panel:AddDropdown({
        label = "Class",
        tooltip = "Which class's book the grid below is showing. Purely a view -- what is toggled applies to that class on every enemy.",
        options = (function()
            local out = {}
            for _, token in ipairs(CLASS_ORDER) do
                out[#out + 1] = {
                    text = (LOCALIZED_CLASS_NAMES_MALE or {})[token] or token,
                    value = token,
                }
            end
            return out
        end)(),
        get = function() return cooldownClass end,
        set = function(value) cooldownClass = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Cooldowns end,
        onSelect = function() Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE) end,
    })

    -- One grid, rebuilt in place. The book's longest class is well under the
    -- cell count below, so every class fits the same frame and switching the
    -- dropdown only repaints -- no frames created after login, which keeps the
    -- page cheap and keeps it out of trouble in combat.
    local MAX_CELLS = 20
    local grid = panel:AddRow(math.ceil(MAX_CELLS / 4) * (CELL_H + CELL_GAP), 6)
    local cells = {}
    for i = 1, MAX_CELLS do
        local cell = CreateFrame("Button", nil, grid)
        cell:SetSize(CELL_W, CELL_H)
        local col, line = (i - 1) % 4, math.floor((i - 1) / 4)
        cell:SetPoint("TOPLEFT", grid, "TOPLEFT",
            col * (CELL_W + CELL_GAP), -line * (CELL_H + CELL_GAP))
        cell.bg = cell:CreateTexture(nil, "BACKGROUND")
        cell.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        cell.bg:SetAllPoints()
        cell.swatch = cell:CreateTexture(nil, "ARTWORK")
        cell.swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        cell.swatch:SetSize(3, CELL_H - 6)
        cell.swatch:SetPoint("LEFT", cell, "LEFT", 3, 0)
        cell.label = cell:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        cell.label:SetPoint("LEFT", cell, "LEFT", 10, 0)
        cell.label:SetPoint("RIGHT", cell, "RIGHT", -4, 0)
        cell.label:SetJustifyH("LEFT")
        cell:SetScript("OnClick", function(self)
            if not self.entry then return end
            local key = cooldownClass .. ":" .. self.entry.name
            OverrideSet("CooldownTrack", key,
                not CommanderArenaFrames_CooldownTracked(cooldownClass, self.entry.name),
                CooldownDefault(cooldownClass, self.entry.name))
            panel:Refresh()
            panel:_Changed()
        end)
        cell:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.name, 1, 1, 1)
            GameTooltip:AddLine(ROLE_LABEL[self.entry.role] or self.entry.role, 0.7, 0.7, 0.7)
            GameTooltip:AddLine(string.format("Cooldown %s",
                CommanderArenaFrames_Engine.FormatTime(self.entry.cd)), 1, 0.82, 0)
            if self.entry.dur and self.entry.dur > 0 then
                GameTooltip:AddLine(string.format("Lasts %s",
                    CommanderArenaFrames_Engine.FormatTime(self.entry.dur)), 0.7, 0.7, 0.7)
            end
            if self.entry.off then
                GameTooltip:AddLine("Off by default -- its cooldown is short enough that the slot would blink constantly without ever telling you something to act on.", 0.55, 0.55, 0.55, true)
            end
            if self.entry.talent then
                GameTooltip:AddLine(string.format(
                    "%s can shorten this, and the combat log never says whether they took it -- so treat the timer as the longest it could be.",
                    self.entry.talent), 0.9, 0.7, 0.4, true)
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(CommanderArenaFrames_CooldownTracked(cooldownClass, self.entry.name)
                and "Click to stop tracking it." or "Click to track it.", 0.5, 0.8, 0.5)
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cells[i] = cell
    end

    panel:AddRefresher(function()
        local book = CommanderArenaFrames_Data.ENEMY_BOOK[cooldownClass] or {}
        for i, cell in ipairs(cells) do
            local entry = book[i]
            cell.entry = entry
            if not entry then
                cell:Hide()
            else
                cell:Show()
                cell.label:SetText(entry.name)
                local on = CommanderArenaFrames_CooldownTracked(cooldownClass, entry.name)
                    and (CommanderArenaFramesDB.CooldownRoles or {})[entry.role]
                cell.bg:SetVertexColor(on and 0.22 or 0.10, on and 0.30 or 0.10, on and 0.24 or 0.10, 0.9)
                cell.label:SetTextColor(on and 1 or 0.45, on and 1 or 0.45, on and 1 or 0.45)
                local tint = ROLE_TINT[entry.role] or { 1, 1, 1 }
                cell.swatch:SetVertexColor(tint[1], tint[2], tint[3], on and 1 or 0.35)
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Trinket, auras, targeting
-- ---------------------------------------------------------------------------

local function AddControlSection(panel)
    panel:AddSection("Crowd Control",
        "Who cannot act, and for how much longer. This is the question an arena board is asked more than any other and the one that is hardest to answer from an icon: a Sap is a ten-second window that decides whether you open, reset or run, and it has to be readable without looking for it.\n\nSo it is written on the enemy's own health bar -- the word where the name was, a clock beside the health number, a tinted rim, and a thin line under the bar that drains -- rather than a slot on a strip. The bar itself is never covered: its fill, its colour and its number stay exactly as they are while the state is up. The class icon beside it becomes the control's own icon, with a sweep and the seconds left across it, so a chain can be timed from across the screen.\n\nThe strip shows one state at a time, worst first: a full crowd control, then an immunity, then a lockout, then a drink, then a stealth. Roots and disarms deliberately do not appear -- a rooted caster is still casting at you and a disarmed warrior is still intercepting, and both of them are on the aura strip where they belong.")

    panel:AddCheckboxPair({
        label = "Crowd Control Bar",
        tooltip = "Write the control that is on this enemy -- SAPPED, FEARED, STUNNED, TRAPPED, BLINDED, SILENCED -- on their health bar, with the seconds left on it and a line under the bar that drains as they run out. The bar and its number stay visible underneath.\n\nSilences are in this list and in no other on the board: TBC gives silence no diminishing returns at all, so a locked-out healer carries no bracket and nothing else here would ever draw one.",
        get = function() return CommanderArenaFramesDB.CCBanner end,
        set = function(value) CommanderArenaFramesDB.CCBanner = value end,
        isEnabled = Enabled,
    }, {
        label = "Next Bracket On It",
        tooltip = "Add what the NEXT control in the same category would land at -- >1/2, >1/4, IMM -- to the bar itself.\n\nThat is the question actually being asked while a crowd control is running: whether there is a re-stun on the other side of it or whether the setup has to go somewhere else. The bracket shown already counts the one currently on them, so it is genuinely the next cast.",
        get = function() return CommanderArenaFramesDB.CCNextBracket end,
        set = function(value) CommanderArenaFramesDB.CCNextBracket = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.CCBanner end,
    })

    panel:AddCheckbox({
        label = "Control On The Class Icon",
        tooltip = "While an enemy is controlled, their class icon becomes the control itself: the spell's icon, a sweep that empties as it runs out, and the seconds left written large across it.\n\nThis is the picture a chain is decided from -- a sap at four seconds means the next one goes now -- and it reads from the corner of the eye in a way a word on a bar cannot. The class is the one thing about them that never changes, so its square is the one that can be borrowed. Needs the class icon on.",
        get = function() return CommanderArenaFramesDB.CCOnClassIcon end,
        set = function(value) CommanderArenaFramesDB.CCOnClassIcon = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.ShowClassIcon end,
    })

    panel:AddCheckboxPair({
        label = "Immunity Bar",
        tooltip = "The same bar while the enemy is untouchable -- Ice Block, Divine Shield, Cloak of Shadows, Hand of Protection. Nothing on an arena board is worth more than not spending a cooldown into an immunity, and an icon in a strip is not loud enough to stop a cast.",
        get = function() return CommanderArenaFramesDB.ImmunityBanner end,
        set = function(value) CommanderArenaFramesDB.ImmunityBanner = value end,
        isEnabled = Enabled,
    }, {
        label = "Stealth Bar",
        tooltip = "Mark a row whose enemy has gone into stealth. Their slot stays exactly where it is -- dropping the row would remove the thing you were about to use to find them -- and their health bar holds the last reading taken before they disappeared.",
        get = function() return CommanderArenaFramesDB.StealthBanner end,
        set = function(value) CommanderArenaFramesDB.StealthBanner = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Drinking Bar",
        tooltip = "Call out an enemy who has sat down to drink. A drinking enemy is out of the game for exactly as long as you allow, and this is the cue to make that short.",
        get = function() return CommanderArenaFramesDB.DrinkBanner end,
        set = function(value) CommanderArenaFramesDB.DrinkBanner = value end,
        isEnabled = Enabled,
    })
end

local function AddTrinketSection(panel)
    panel:AddSection("Trinket & Auras",
        "The PvP trinket gets a slot of its own rather than a place in the cooldown strip, because \"can they break my Blind\" is a question asked on its own and deserves to be answered on its own. It is also the one enemy cooldown the client will actually tell you about, so unlike everything else on the strip it is known rather than witnessed.")

    panel:AddCheckboxPair({
        label = "Trinket Slot",
        tooltip = "A dedicated slot per enemy for their PvP trinket, read from the client's own arena crowd-control report -- so it is right from the first second of the game rather than from the first time you watch them press it.",
        get = function() return CommanderArenaFramesDB.Trinket end,
        set = function(value) CommanderArenaFramesDB.Trinket = value end,
        isEnabled = Enabled,
    }, {
        label = "Flash on Trinket",
        tooltip = "Flash the row the instant a trinket is used. That moment is the whole game for a setup team, and it is very easy to miss on an icon alone.",
        get = function() return CommanderArenaFramesDB.TrinketAlert end,
        set = function(value) CommanderArenaFramesDB.TrinketAlert = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Trinket end,
    })

    panel:AddCheckbox({
        label = "Trinket Badge on Class Icon",
        tooltip = "The trinket again, small, in the bottom-right corner of the class icon -- where the Arena Replay puts it, and where your eye already is when it reads who an enemy is. It stays on top of the crowd-control icon, because that is exactly when you are asking whether they can trinket. Works with or without the Trinket Slot.",
        get = function() return CommanderArenaFramesDB.TrinketBadge end,
        set = function(value) CommanderArenaFramesDB.TrinketBadge = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.ShowClassIcon end,
    })

    panel:AddCheckboxPair({
        label = "Aura Strip",
        tooltip = "Auras on each enemy: what is protecting them, and the control you have landed. Curated by default -- see the picker below.",
        get = function() return CommanderArenaFramesDB.Auras end,
        set = function(value) CommanderArenaFramesDB.Auras = value end,
        isEnabled = Enabled,
    }, {
        label = "Only My Debuffs",
        tooltip = "Show only the debuffs YOU applied. Useful for a caster tracking their own control; it also hides your partner's, which is usually the wrong trade in 3v3.",
        get = function() return CommanderArenaFramesDB.AuraMineOnly end,
        set = function(value) CommanderArenaFramesDB.AuraMineOnly = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Auras end,
    })

    panel:AddDropdown({
        label = "Which Auras",
        tooltip = "Curated shows the list the board has an opinion about -- immunities, damage reductions, freedoms, burst windows, stealth. Purgeable narrows it to magic effects you could actually take off. Everything shows the lot, which is honest and unreadable.",
        options = {
            { text = "Curated", value = "NOTED" },
            { text = "Purgeable only", value = "PURGEABLE" },
            { text = "Everything", value = "ALL" },
        },
        get = function() return CommanderArenaFramesDB.AuraShow end,
        set = function(value) CommanderArenaFramesDB.AuraShow = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Auras end,
    })

    panel:AddSliderPair({
        label = "Aura Size", min = 12, max = 30, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        get = function() return CommanderArenaFramesDB.AuraSize end,
        set = function(value) CommanderArenaFramesDB.AuraSize = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Auras end,
    }, {
        label = "Most Auras", min = 2, max = 10, step = 1,
        format = function(v) return string.format("%d", v or 0) end,
        get = function() return CommanderArenaFramesDB.AuraMax end,
        set = function(value) CommanderArenaFramesDB.AuraMax = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Auras end,
    })

    panel:AddCheckbox({
        label = "Trinket Fills the Row",
        tooltip = "Size the trinket to the row, exactly as the class square is -- three elements at one height on one line, which is what makes the top of the row read as a frame. Off, the slider below sets it.",
        get = function() return CommanderArenaFramesDB.TrinketFillRow end,
        set = function(value) CommanderArenaFramesDB.TrinketFillRow = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Trinket end,
    })

    panel:AddSlider({
        label = "Trinket Size", min = 14, max = 34, step = 1,
        format = function(v) return string.format("%dpx", v or 0) end,
        get = function() return CommanderArenaFramesDB.TrinketSize end,
        set = function(value) CommanderArenaFramesDB.TrinketSize = value end,
        isEnabled = function() return Enabled() and CommanderArenaFramesDB.Trinket
            and not CommanderArenaFramesDB.TrinketFillRow end,
    })
end

local function AddTargetingSection(panel)
    panel:AddSection("Targeting",
        "Which row is yours, and who they are on. The client will name an arena enemy's target, which is the only place a board can tell you that the enemy healer has swapped to you.")

    panel:AddCheckboxPair({
        label = "Ring My Target",
        tooltip = "Outline the enemy you currently have targeted, so the row and the nameplate agree without you checking.",
        get = function() return CommanderArenaFramesDB.TargetHighlight end,
        set = function(value) CommanderArenaFramesDB.TargetHighlight = value end,
        isEnabled = Enabled,
    }, {
        label = "Ring My Focus",
        tooltip = "The same for your focus, in its own colour -- the two are different jobs and a single highlight for both is worse than neither.",
        get = function() return CommanderArenaFramesDB.FocusHighlight end,
        set = function(value) CommanderArenaFramesDB.FocusHighlight = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Who They Are On",
        tooltip = "A small class icon per enemy showing who they are currently targeting. Off by default -- in a 3v3 it is three more things moving on a board that already has plenty, and the one case that really matters has its own switch beside this.",
        get = function() return CommanderArenaFramesDB.ShowTargetOf end,
        set = function(value) CommanderArenaFramesDB.ShowTargetOf = value end,
        isEnabled = Enabled,
    }, {
        label = "Flag When It Is You",
        tooltip = "Mark the row whenever that enemy is targeting YOU, whether or not the full readout above is on. This is the one that is worth interrupting your attention for.",
        get = function() return CommanderArenaFramesDB.ShowTargetOfSelf end,
        set = function(value) CommanderArenaFramesDB.ShowTargetOfSelf = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Fade the Dead",
        tooltip = "Dim an enemy who has died rather than dropping their row, so the board keeps its shape and the slots stay where your hand expects them.",
        get = function() return CommanderArenaFramesDB.DeadFade end,
        set = function(value) CommanderArenaFramesDB.DeadFade = value end,
        isEnabled = Enabled,
    })

end

local function AddAlertsSection(panel)
    panel:AddSection("Alerts & Calls",
        "Everything here is off. An alert is a claim on attention and an announcement is a claim on your team's chat, and which of those are worth making is personal in a way a default cannot be.")

    panel:AddCheckboxPair({
        label = "Alert on Trinket",
        tooltip = "Flash and, optionally, sound when an enemy trinkets.",
        get = function() return CommanderArenaFramesDB.AlertTrinket end,
        set = function(value) CommanderArenaFramesDB.AlertTrinket = value end,
        isEnabled = Enabled,
    }, {
        label = "Alert on Defensive",
        tooltip = "The same when an enemy spends a major defensive -- a bubble, an Ice Block, a Cloak.",
        get = function() return CommanderArenaFramesDB.AlertDefensive end,
        set = function(value) CommanderArenaFramesDB.AlertDefensive = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Alert on Drink",
        tooltip = "Flag the moment an enemy sits down to drink.",
        get = function() return CommanderArenaFramesDB.AlertDrink end,
        set = function(value) CommanderArenaFramesDB.AlertDrink = value end,
        isEnabled = Enabled,
    }, {
        label = "Alert Sound",
        tooltip = "Play a sound with any alert above, as well as flashing.",
        get = function() return CommanderArenaFramesDB.AlertSound end,
        set = function(value) CommanderArenaFramesDB.AlertSound = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Call Trinkets",
        tooltip = "Say it in party chat when an enemy trinkets, with the time until it is back. Off by default: it is your team's chat, and a board should not start talking in it without being asked.",
        get = function() return CommanderArenaFramesDB.AnnounceTrinket end,
        set = function(value) CommanderArenaFramesDB.AnnounceTrinket = value end,
        isEnabled = Enabled,
    }, {
        label = "Call Defensives",
        tooltip = "The same for major defensives.",
        get = function() return CommanderArenaFramesDB.AnnounceDefensive end,
        set = function(value) CommanderArenaFramesDB.AnnounceDefensive = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdown({
        label = "Where Calls Go",
        tooltip = "Party puts the call in your team's chat. Just Me prints it to your own chat frame instead -- the same information, none of the social cost, and the right setting for trying this out.",
        options = { { text = "Party chat", value = "PARTY" }, { text = "Just me", value = "SELF" } },
        get = function() return CommanderArenaFramesDB.AnnounceChannel end,
        set = function(value) CommanderArenaFramesDB.AnnounceChannel = value end,
        isEnabled = function() return Enabled()
            and (CommanderArenaFramesDB.AnnounceTrinket or CommanderArenaFramesDB.AnnounceDefensive) end,
    })
end


-- ---------------------------------------------------------------------------
-- The click-binding matrix: every modifier x every mouse button, one cell
-- each. A grid rather than a column of dropdowns because there are forty of
-- them, and because the shape of the grid IS the information -- which row of
-- modifiers is empty is the thing you want to see.
-- ---------------------------------------------------------------------------

local CLICK_LABEL_W, CLICK_CELL, CLICK_CELL_GAP = 108, 26, 6
local BIND_BOOK_CHUNK = 20      -- spells per alphabetical submenu

local bindMenu, bindMenuCell

local function BindCellTooltip(self)
    local _, label, missing = CommanderArenaFrames_BindDisplay(self.bindValue)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.modLabel .. " + " .. self.btnLabel, 1, 1, 1)
    if label == "Unbound" then
        GameTooltip:AddLine("Nothing bound -- the click falls through.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(label, 0.4, 0.9, 0.4)
    end
    if missing then
        GameTooltip:AddLine("This character cannot cast that -- the click will do nothing.",
            1, 0.4, 0.4, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to rebind, right-click to clear.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BindCellPick(value)
    if not bindMenuCell then return end
    CommanderArenaFrames_SetBind(bindMenuCell.bindKey, value)
    Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
    if bindMenuCell.owner then bindMenuCell.owner:Refresh() end
end

local function BindMenuInit(_, level)
    level = level or 1
    local info
    if level == 1 then
        info = UIDropDownMenu_CreateInfo()
        info.text, info.isTitle, info.notCheckable = "Bind to", true, true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "Clear this binding", true
        info.func = function() BindCellPick(nil); CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)

        -- The three that are not spells, first: they are the answer most of
        -- the time on an enemy frame.
        for _, action in ipairs(CommanderArenaFrames_GetClickActions()) do
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.icon = action.label, true, action.icon
            info.func = function() BindCellPick(action.value); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end

        -- Then the live spellbook, in alphabetical buckets. A single flat list
        -- of everything a level 70 knows is not a menu you can find anything
        -- in; and building it from the spellbook rather than from a shipped
        -- list means it can never offer a spell this character cannot cast.
        local book = CommanderArenaFrames_GetSpellBook()
        if #book > 0 then
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.isTitle = " ", true, true
            UIDropDownMenu_AddButton(info, level)
            for first = 1, #book, BIND_BOOK_CHUNK do
                local last = math.min(first + BIND_BOOK_CHUNK - 1, #book)
                info = UIDropDownMenu_CreateInfo()
                info.text = string.format("Spells: %s - %s",
                    book[first].name:sub(1, 10), book[last].name:sub(1, 10))
                info.notCheckable, info.hasArrow = true, true
                info.menuList = "BOOK:" .. first
                UIDropDownMenu_AddButton(info, level)
            end
        end
    elseif level == 2 then
        local first = tonumber(tostring(UIDROPDOWNMENU_MENU_VALUE):match("^BOOK:(%d+)$") or "")
        if not first then return end
        local book = CommanderArenaFrames_GetSpellBook()
        for i = first, math.min(first + BIND_BOOK_CHUNK - 1, #book) do
            local spell = book[i]
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.icon = spell.name, true, spell.icon
            -- Stored by id; the client casts the highest rank of that name.
            info.func = function() BindCellPick(spell.id); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

local function BindCellClick(self, button)
    if button == "RightButton" then
        CommanderArenaFrames_SetBind(self.bindKey, nil)
        Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
        if self.owner then self.owner:Refresh() end
        BindCellTooltip(self)
        return
    end
    bindMenuCell = self
    if not bindMenu then
        bindMenu = CreateFrame("Frame", "CommanderArenaFramesBindMenu", UIParent,
            "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(bindMenu, BindMenuInit, "MENU")
    ToggleDropDownMenu(1, nil, bindMenu, self, 0, 0)
end

local function AddClickMatrix(panel)
    local cells = {}
    local mods = CommanderArenaFrames_GetClickMods()
    local btns = CommanderArenaFrames_GetClickButtons()

    local head = panel:AddRow(16, 10)
    for c, btn in ipairs(btns) do
        local fs = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("LEFT", head, "LEFT",
            CLICK_LABEL_W + (c - 1) * (CLICK_CELL + CLICK_CELL_GAP) - 6, 0)
        fs:SetWidth(CLICK_CELL + CLICK_CELL_GAP + 8)
        fs:SetText(btn.label)
    end

    for _, mod in ipairs(mods) do
        local row = panel:AddRow(CLICK_CELL + 2, 3)
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetWidth(CLICK_LABEL_W - 6)
        label:SetJustifyH("LEFT")
        label:SetText(mod.label)
        for c, btn in ipairs(btns) do
            local cell = CreateFrame("Button", nil, row)
            cell:SetSize(CLICK_CELL, CLICK_CELL)
            cell:SetPoint("LEFT", row, "LEFT",
                CLICK_LABEL_W + (c - 1) * (CLICK_CELL + CLICK_CELL_GAP), 0)
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cell.bindKey = mod.key .. btn.key
            cell.modLabel, cell.btnLabel, cell.owner = mod.label, btn.label, panel
            cell.bg = cell:CreateTexture(nil, "BACKGROUND")
            cell.bg:SetAllPoints(cell)
            cell.bg:SetColorTexture(1, 1, 1, 0.07)
            cell.icon = cell:CreateTexture(nil, "ARTWORK")
            cell.icon:SetAllPoints(cell)
            cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cell.icon:Hide()
            -- A red rim means: bound to something this character cannot cast.
            -- That is a click which saves perfectly and then does nothing in a
            -- game, which is the worst way for a binding to be wrong.
            cell.warn = cell:CreateTexture(nil, "OVERLAY")
            cell.warn:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
            cell.warn:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
            cell.warn:SetColorTexture(0.95, 0.25, 0.25, 0.8)
            cell.warn:Hide()
            cell:SetScript("OnClick", BindCellClick)
            cell:SetScript("OnEnter", BindCellTooltip)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cells[#cells + 1] = cell
        end
    end

    panel:AddButtonRow({
        {
            label = "Reset Bindings",
            tooltip = "Drop every binding and go back to the starting set: left-click targets, right-click sets focus, shift and left-click assists.",
            onClick = function()
                CommanderArenaFramesDB.ClickBinds = {}
                Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
                panel:Refresh()
            end,
            isEnabled = function() return Enabled() and CommanderArenaFramesDB.ClickCast end,
        },
    })

    panel:AddRefresher(function()
        local on = CommanderArenaFramesDB.Enable and CommanderArenaFramesDB.ClickCast
        for _, cell in ipairs(cells) do
            cell.bindValue = CommanderArenaFrames_GetBind(cell.bindKey)
            local icon, _, missing = CommanderArenaFrames_BindDisplay(cell.bindValue)
            if icon then
                cell.icon:SetTexture(icon)
                cell.icon:SetDesaturated(not on)
                cell.icon:SetVertexColor(1, 1, 1, on and 1 or 0.5)
                cell.icon:Show()
            else
                cell.icon:Hide()
            end
            cell.warn:SetShown(missing and true or false)
            cell:SetEnabled(on and true or false)
            cell.bg:SetColorTexture(1, 1, 1, on and 0.07 or 0.03)
        end
    end)
end

local function AddClickSection(panel)
    panel:AddSection("Click-Casting",
        "Turn each enemy row into a real unit button, so a click targets them and a @mouseover macro fires at them. This changes the row's frame TYPE, which the client will not let an addon swap while the game is running -- so switching it asks for a /reload, and it is the one setting on this page that does.")

    panel:AddCheckbox({
        label = "Rows Are Unit Buttons",
        tooltip = "Bind each row to its arena unit. Bindings are set once, out of combat, on the raw tokens (arena1, arena2, ...), so nothing secure ever changes mid-fight while the visible board keeps updating at full speed.",
        get = function() return CommanderArenaFramesDB.ClickCast end,
        set = function(value) CommanderArenaFramesDB.ClickCast = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdown({
        label = "Row Tooltip",
        tooltip = "What hovering a row shows. Notes Only is the default: the board is already telling you the name, the health and the auras, so the game's own unit tooltip mostly repeats it -- what is worth adding is the DR brackets and the cooldowns in full. None of the three touch the unit attribute that makes @mouseover macros work.",
        options = {
            { text = "Unit tooltip + notes", value = "FULL" },
            { text = "Notes only", value = "EXTRAS" },
            { text = "Nothing", value = "OFF" },
        },
        get = function() return CommanderArenaFramesDB.RowTooltip end,
        set = function(value) CommanderArenaFramesDB.RowTooltip = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Bindings",
        "Every modifier against every mouse button. Click a cell to bind it -- to targeting, to focus, to assist (target what they are targeting), or to any spell this character has actually trained; right-click a cell to clear it. A cell with a red rim is bound to something you cannot cast, which is a click that saves perfectly and then does nothing in a game.\n\nBindings are written once, out of combat, so a change made mid-game takes effect when it ends.")
    AddClickMatrix(panel)
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "ArenaFrames",
        title = "Arena Frames",
        addonName = "Commander_ArenaFrames",
        description = "Enemy frames built for arena, and the other half of Commander Party Frames -- that board is your team, this one is theirs. Health and live resource per enemy (a healer's mana is the number an arena is most often decided by), a real cast bar to time a kick against, their PvP trinket read from the client rather than guessed, every cooldown they spend learned from the combat log, the auras that mean stop casting, and -- the headline -- a diminishing-returns bracket per category, per enemy, with TBC's own rules: Kidney Shot on its own ladder, proc stuns separate from cast stuns, no bracket at all on silence, and a reset clock that starts when the aura fades rather than when it lands.",
        event = COMMANDER_ARENAFRAMES_EVENTS.UPDATE,
        slash = { "/caf", "/carena" },
        slashHandlers = {
            test = function() if CommanderArenaFrames_Test then CommanderArenaFrames_Test() end end,
            report = function() if CommanderArenaFrames_Report then CommanderArenaFrames_Report() end end,
            lock = function()
                CommanderArenaFramesDB.HudLocked = not CommanderArenaFramesDB.HudLocked
                Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
                print("Commander Arena Frames: board "
                    .. (CommanderArenaFramesDB.HudLocked and "locked" or "unlocked -- drag it, right-click to lock"))
            end,
        },
    })

    panel:AddCheckbox({
        label = "Enable Arena Frames",
        tooltip = "The whole module. Off gives Blizzard's own arena frames back immediately.",
        get = function() return CommanderArenaFramesDB.Enable end,
        set = function(value) CommanderArenaFramesDB.Enable = value end,
    })

    panel:AddButtonRow({
        {
            label = "Test Board",
            tooltip = "Draw a full three-enemy board with every instrument populated -- brackets part-way down the ladder, cooldowns mid-count, a cast in flight, an immunity up -- so it can be placed and sized without queueing. Works anywhere; clears itself after a few seconds, or on the next /caf test.",
            onClick = function() if CommanderArenaFrames_Test then CommanderArenaFrames_Test() end end,
            isEnabled = Enabled,
        },
        {
            label = "Unlock & Move",
            tooltip = "Unlock the board so it can be dragged. Right-click it to lock again, or triple right-click a locked board to unlock it without coming back here.",
            onClick = function()
                CommanderArenaFramesDB.HudLocked = false
                Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
            end,
            isEnabled = Enabled,
        },
    })

    AddBoardSection(panel)
    AddIdentitySection(panel)
    AddVitalsSection(panel)
    AddCastSection(panel)
    AddDRSection(panel)
    AddControlSection(panel)
    AddCooldownSection(panel)
    AddTrinketSection(panel)
    AddTargetingSection(panel)
    AddClickSection(panel)
    AddAlertsSection(panel)

    -- Chrome last, per the suite convention
    Commander.UI.AddHudChromeOptions(panel, CommanderArenaFramesDB, "Hud", {
        isEnabled = Enabled,
        onChanged = function() Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

-- One-time repairs, keyed by a revision OUTSIDE DefaultSettings so Restore
-- Defaults can never un-migrate.
--
-- Rev 1 is the resize. ApplyDefaults only fills keys that are MISSING, so a
-- board that had already been loaded once kept every original size -- and the
-- whole point of the resize was that those sizes were too big. The rule below
-- is deliberately narrow: a value is moved only if it still equals the figure
-- it was shipped with, which means a size the player chose themselves is left
-- exactly alone. Anyone who liked the old board can put any of it back.
local RESIZE_REV_1 = {
    FrameWidth     = { 210, 200 },
    RowHeight      = { 34,  28  },
    RowSpacing     = { 12,  3   },
    CastBarHeight  = { 12,  10  },
    PowerBarHeight = { 7,   6   },
    DRIconSize     = { 20,  18  },
    CooldownSize   = { 18,  16  },
    AuraSize       = { 18,  16  },
    TrinketSize    = { 22,  20  },
    HudStyle       = { "DARK", "NONE" },
}

local function Migrate()
    if (CommanderArenaFramesDB.AFRev or 0) < 1 then
        for key, pair in pairs(RESIZE_REV_1) do
            if CommanderArenaFramesDB[key] == pair[1] then
                CommanderArenaFramesDB[key] = pair[2]
            end
        end
        CommanderArenaFramesDB.AFRev = 1
    end
    -- Rev 2 is click-cast becoming the default. ApplyDefaults only fills keys
    -- that are MISSING, and this one was written to the saved variables the
    -- first time the board ever loaded -- so every existing install would keep
    -- an off switch it never actually chose. The flip happens once; anyone who
    -- did mean to turn it off can turn it off again and it stays off, because
    -- the revision has already moved past this rule.
    if (CommanderArenaFramesDB.AFRev or 0) < 2 then
        if CommanderArenaFramesDB.ClickCast == false then
            CommanderArenaFramesDB.ClickCast = true
        end
        CommanderArenaFramesDB.AFRev = 2
    end
    -- Rev 3 clears out the range fade. It was two controls wired to two saved
    -- values that nothing read: CheckInteractDistance is PROTECTED on this
    -- client, the blocked call answered nothing, and the paint path read that
    -- as "out of range" -- so the feature was removed and the settings were
    -- left behind. Left in the saved variables they are dead weight that a
    -- future key of the same name would inherit.
    if (CommanderArenaFramesDB.AFRev or 0) < 3 then
        CommanderArenaFramesDB.RangeFade = nil
        CommanderArenaFramesDB.RangeFadeAlpha = nil
        CommanderArenaFramesDB.AFRev = 3
    end
    -- Rev 4 replaces the class-colour switch with a colour MODE, and the new
    -- default is by value: the bar's colour tracks the health it shows.
    -- Anyone who had switched class colouring OFF meant plain red and keeps
    -- it; everyone else moves to the new default, which is the reason the
    -- mode exists.
    -- (The retired key is read through rawget so settings_reach.py sees a
    -- migration rather than a live control reading a key nobody declares.)
    if (CommanderArenaFramesDB.AFRev or 0) < 4 then
        if CommanderArenaFramesDB.HealthBarColor == nil then
            CommanderArenaFramesDB.HealthBarColor =
                (rawget(CommanderArenaFramesDB, "ClassColorBar") == false) and "FLAT" or "VALUE"
        end
        CommanderArenaFramesDB.ClassColorBar = nil
        CommanderArenaFramesDB.AFRev = 4
    end
    -- Rev 5 is the Gladdy pass (2026-09-20): black element borders, a plate
    -- under each row, sweeps on every timed icon, the trinket at row height,
    -- class-coloured bars, a taller cast band and a row spacing that clears
    -- the new target ring. The new keys arrive through ApplyDefaults on their
    -- own; the three CHANGED defaults move only where the saved value still
    -- equals the figure it shipped with, so a number the player chose is
    -- left exactly alone.
    if (CommanderArenaFramesDB.AFRev or 0) < 5 then
        for key, pair in pairs({
            RowSpacing     = { 3, 4 },
            CastBarHeight  = { 10, 12 },
            HealthBarColor = { "VALUE", "CLASS" },
        }) do
            if CommanderArenaFramesDB[key] == pair[1] then
                CommanderArenaFramesDB[key] = pair[2]
            end
        end
        CommanderArenaFramesDB.AFRev = 5
    end
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_ArenaFrames" then
        Migrate()
        Commander.UI.ApplyDefaults(CommanderArenaFramesDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

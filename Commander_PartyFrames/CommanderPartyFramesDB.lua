CommanderPartyFramesDB = _G.CommanderPartyFramesDB or {}

COMMANDER_PARTYFRAMES_EVENTS = {
    UPDATE = "COMMANDER_PARTYFRAMES_UPDATE"
}

local DefaultSettings = {
    EnableShield = true,
    Scope = "PARTY",         -- PARTY (you + party) or RAID (you + raid)
    IncludeSelf = true,
    IncludePets = true,      -- allies' pets get ally rows too (buffable, healable)
    SelfFirst = false,       -- pin yourself to the top instead of sorting by urgency
    RowOrder = "URGENCY",    -- the sorted board's order: URGENCY | CLASS_DIST | CLASS_NAME
    ShowHeader = true,       -- PW:S cooldown + your nominal shield value strip
    HeaderBackdrop = true,   -- dark panel behind the top bar

    -- How the banner is DRAWN. Every default here is the number the header
    -- used to hard-code, so a board that never opens the Header section is
    -- pixel-for-pixel the board it always was.
    HeaderHeight = 15,            -- the strip's height in pixels
    HeaderInset = 4,              -- how far in from the left edge it starts
    HeaderIconSize = 12,          -- one readout segment's icon edge
    HeaderSegmentGap = 8,         -- space between one segment and the next
    HeaderChromeScale = 1,        -- size of the gear / rows / refresh buttons

    -- Board scale by group size, you included: 1-3 (solo, 2s, 3s), 4-5
    -- (5s, a dungeon) and 6+ (raids, battlegrounds). These replace the HUD
    -- chrome's single HudScale; party vs raid is deliberately not a factor.
    HudScaleSmall = 1,
    HudScaleParty = 1,
    HudScaleLarge = 1,
    HeaderFont = "DEFAULT",       -- DEFAULT | NARROW | RUNE | ROMAN
    HeaderFontSize = 10,
    HeaderFontOutline = "NONE",   -- NONE | OUTLINE | THICK
    HeaderBackdropTint = "BLACK", -- BLACK|CHARCOAL|SLATE|BLOOD|FOREST|CLASS
    HeaderBackdropAlpha = 0.55,
    HeaderRule = false,           -- hairline along the banner's bottom edge
    HeaderProduction = false,     -- Commander_Production's queue in place of the class cooldowns
    HideBlizzardParty = false, -- hide Blizzard's own party frames (header button toggles it)
    OnlyAlerts = false,      -- hide healthy SHIELDED/OTHER rows, keep the ones needing a decision
    AlwaysShow = false,
    FixedHeight = false,
    MaxRows = 6,
    FrameWidth = 214,

    -- Nearby Raid: the board as party frames inside a raid or battleground —
    -- you plus the closest few raid members instead of the whole roster.
    -- Every key here is flagged off or neutral, so a board that has never
    -- touched them behaves exactly as it always did.
    NearMode = false,        -- master flag for the whole nearby-raid feature
    NearCount = 5,           -- how many PEOPLE on the board, you included (2-15)
    NearSort = "DISTANCE",   -- row order once picked: DISTANCE (as picked) | URGENCY | CLASS_DIST | CLASS_NAME
    NearAuto = false,        -- re-pick on a timer instead of on the button
    NearInterval = 3,        -- seconds between automatic re-picks (1-15)
    NearGhostsFar = true,    -- a released ghost ranks as infinitely far; an unreleased corpse keeps its yards
    NearButton = true,       -- the refresh control on the header
    LowAbsorbPct = 25,       -- absorb at/under this % of capacity counts as "low"
    LowTimeSecs = 5,         -- shield with this many seconds left counts as "expiring"

    -- Identity & icons (defaults are icon-first, minimal text)
    ShowSpellIcon = true,
    UnitDisplay = "CLASS_ICON", -- CLASS_ICON | PORTRAIT | NAME | ICON_NAME | ICON_PORTRAIT
    ColorShieldTypes = true,    -- tint embedded shield segments per type (off = one cream)
    BarTexture = "FLAT",        -- FLAT | BLIZZARD | GLOSS | BEVEL | RIDGE | GLASS
    IconRecess = "SOFT",        -- icon shading: OFF | SOFT | DEEP | CARVED
    SweepEdge = false,          -- leading-edge spark on the aura duration sweeps
    NameMaxChars = 6,
    -- The bar's left span: the ally's name, unless the row has a state word
    -- to put there. Which words are allowed to is the player's call, kind by
    -- kind; the master hands the span to the name outright. All on, so the
    -- board reads exactly as it always has.
    BarTextAlwaysName = false,  -- never a word: the span is always the name
    BarTextDead = true,         -- DEAD / OFFLINE
    BarTextDispel = true,       -- MAGIC / CURSED / POISON / DISEASE
    BarTextCC = true,           -- the crowd control's name
    BarTextAsk = true,          -- BLESS / HOT: what to cast on them
    BarTextLock = true,         -- EXPOSED / SHIELDED*: why you cannot, or need not
    BarTextNumber = true,       -- seconds or minutes left, absorb amounts, UP
    ShowTargeters = true,       -- enemy-NPCs-targeting count over the class icon
    ShowTargetMarks = true,     -- raid mark of the unit each ally is targeting
    ShowCombat = true,          -- crossed blades on every ally who is in combat
    ShowBGBuffs = true,         -- flag carry + battleground powerups, in a battleground only
    MarkLayout = "GRID",        -- GRID (one 2x2 seat for every mark) | ROW (one seat per mark, side by side)

    -- Ten flagged features (all neutral defaults, so current behavior is kept)
    ClickCast = false,          -- rows become secure mouseover/click unit buttons
    -- Click bindings: the full modifier x button matrix, per talent build.
    -- ClickBinds[profileKey][modPrefix .. button] = spellID | "TARGET" |
    -- "TARGETTARGET" | "ARROW" (Commander Orders follows them, 5.41.0) |
    -- false (deliberately cleared). Absent = the layer default, until the
    -- profile is first edited.
    ClickBinds = {},
    ClickBindsMigrated = false, -- one-time seed from the old flat keys
    ClickProfileMode = "TALENT",-- TALENT (follow the build) | FIXED
    ClickProfileFixed = "",     -- which profile when FIXED
    -- What hovering a click-cast row shows. FULL is the game's unit tooltip
    -- plus our own lines; EXTRAS drops the unit half (a party frame is
    -- already telling you the name, the health and the buffs) and keeps only
    -- what the board has to add; OFF shows nothing. None of them touch the
    -- unit attribute that makes @mouseover macros work.
    RowTooltip = "EXTRAS",
    -- Their arena ratings (Commander Muster) at the end of the notes-only
    -- tooltip. Off: that one line is enough to open the tooltip, and once
    -- the Ladder feed knows your group, it opened on every row you crossed.
    RowTooltipRatings = false,
    -- In an arena, hovering ANYTHING on the board shows no tooltip — rows,
    -- ability cells, banner buttons, the blessing slot. They anchor beside
    -- what you hovered, which on this board is the next row's debuffs.
    HideArenaTooltips = true,
    -- Per-button click-cast bindings (spell ID, or "TARGET" / "NONE")
    ClickLeft = 17,             -- left-click   = Power Word: Shield ("bubble")
    ClickRight = 139,           -- right-click  = Renew
    ClickMiddle = 2061,         -- middle-click = Flash Heal
    ClickModLeft = 2060,        -- modifier + left-click = Greater Heal
    ClickModifier = "shift",    -- modifier key for the mod binding: shift | ctrl | alt
    RangeFade = false,          -- dim units out of shield range
    RangeFadeStrength = 0.6,    -- how much an out-of-range row dims (0.6 = row at 40% alpha)
    ShieldSwipe = false,        -- radial 30s shield-duration sweep on the spell icon
    -- The shield slot's second clock, drawn on the icon's own border so it
    -- costs no width: the Weakened Soul lockout fused with the spell's
    -- cooldown, which together are the whole answer to "can I shield them".
    ShieldLockRing = true,
    WSReadyGlow = false,        -- glow rows whose reshield window is open
    Grow = "DOWN",             -- board growth direction (DOWN | UP)
    CombatOnly = false,         -- only show the board in combat
    PinFocus = false,           -- pin your focus unit to the top
    TrackUptime = false,        -- track session shield coverage (+/cpf report)
    ExposeAlert = false,        -- flash a row when your shield breaks off an ally
    ExposeAlertSound = false,   -- also play a sound with the expose flash
    -- The priest's own hots (Renew, Prayer of Mending) ride the shared strip
    -- now, so WHICH of them get a slot lives in BuffTrack with everyone
    -- else's. RenewTrack is gone with the right-edge icon it switched on.
    RenewFlash = true,          -- pulse a hot's slot when it is about to expire
    RenewRefreshAt = 4,         -- seconds left at/under which a hot counts as expiring
    -- The low-health alarm: a faint red ring around a row whose ally is far
    -- enough down to want a Renew and has none of ours on them. Shares the
    -- overheal ring's frame — see the paint for why the two can.
    RenewNeedRing = true,
    RenewNeedAt = 85,           -- health % at/under which a hotless ally rings
    -- Prayer of Mending, which is the one thing on any strip that is not an
    -- aura on a row: a single five-charge object that bounces between allies
    -- until it is spent. The alert is deliberately about the OBJECT ending —
    -- spent, expired, dispelled, gone with a dead holder — and never about a
    -- bounce, which is the spell working and happens four times a cast.
    -- Which sound each audio alert makes. Keys into the engine's
    -- SDATA.ALERT_SOUNDS catalogue, one per alert, all reachable from the
    -- Alert Sounds section on every page that can make that noise. The two
    -- Mending lines default to the bell pair — one instrument, two pitches —
    -- so the spell has a voice of its own instead of the stock raid warning
    -- that half the client's addons already use.
    SoundExpose = "WARNING",
    SoundLBLate = "QUEST",
    SoundPoMSpent = "TOLL_HI",
    -- A Mending that ended with charges thrown away -- expired, purged, or
    -- healed with nobody in range to jump to. The holy fizzle: small, and
    -- nothing else on the client sounds like it.
    SoundPoMWasted = "FIZZLE",
    SoundPoMLost = "TOLL_LO",
    -- Team Shields: the priest's block of dials, one per seat (you and your
    -- party), each carrying that teammate's Power Word: Shield and Weakened
    -- Soul, and the Mending badge with its bounce reach.
    TeamDials = true,
    TeamDialsSelf = true,       -- your own seat leads the line
    PoMTrack = true,            -- master gate: the tracker, the pips, the hop and the alert
    PoMAlert = true,            -- flash + sound when your Mending ENDS (never on a bounce)
    PoMAlertSound = true,       -- the sound half; spent and lost get different ones
    PoMPips = true,             -- five charge lights alongside the stack digit
    PoMCooldownRing = true,     -- the SPELL's cooldown as a ring on the slot's border
    PoMTrail = true,            -- flare the row it lands on, ghost the row it left
    PriestBannerCooldowns = true, -- Pain Suppression/PI/Fear Ward/... segments on the banner

    -- Mage layer: Int/Brilliance upkeep, mage click bindings (their own keys —
    -- the DB is account-wide, so priest bindings must survive untouched), and
    -- the opt-in self-shield extra
    ShowSettingsButton = true,  -- small gear on the header opening this settings page
    IntRefreshAt = 300,         -- Int seconds left at/under which the rebuff window opens
    -- The power strip under each ally's health bar. Used to be mana-only on
    -- three of the four boards; it is now every class's live resource on
    -- every board, because a rogue's energy and a warrior's rage are the two
    -- an arena plans around and neither had anywhere to be shown.
    --   PowerBar       OFF | MANA (mana users only, the old board) | ALL
    --   PowerBarColor  TYPE (blue/red/yellow/orange/green by resource) | BLUE
    --   PowerBarHeight strip height in pixels; the row does not grow with it
    PowerBar = "ALL",
    PowerBarColor = "TYPE",
    PowerBarHeight = 6,
    ShowManaBar = true,         -- legacy: only read to migrate a pre-PowerBar DB

    -- Forecast: what is already on its way to an ally before it lands —
    -- damage queued in their dots, healing rolling from hots, and a heal in
    -- the air from anyone in the group. Learned from the combat log; see the
    -- FORECAST block in the engine for why there is no other way in TBC.
    --   Forecast        OFF | BAR (ghost fills) | TICK (hairlines) |
    --                   TEXT (numbers) | BOTH (fills + numbers)
    Forecast = "BAR",
    ForecastDots = true,        -- count pending dot damage
    ForecastHots = true,        -- count rolling hot healing (any caster's)
    ForecastCasts = true,       -- count a group member's heal mid-cast
    ForecastWindow = 5,         -- only what lands in the next N seconds (0 = all)
    ForecastNet = false,        -- collapse healing and damage into one figure
    ForecastMinPct = 2,         -- ignore anything under this % of their max health
    ForecastTooltip = true,     -- itemise the forecast in the row tooltip

    -- Overheal: the forecast's other half, and the only part of the healing
    -- accounting the combat log reports outright. A thin ring just inside the
    -- row when healing on that ally spilled, brightness riding how much of it
    -- did. Chassis, like the forecast — wasted healing means the same thing
    -- whatever you cast.
    OverhealGlow = true,
    OverhealMine = true,        -- only YOUR heals count as your waste
    OverhealPct = 50,           -- share of a heal that must spill to count
    OverhealHold = 1,           -- seconds the ring lingers, fading out
    MageClickLeft = 1459,       -- mage row left-click   = Arcane Intellect
    MageClickRight = 475,       -- mage row right-click  = Remove Curse
    MageClickMiddle = "TARGET", -- mage row middle-click = target the ally
    MageClickModLeft = 1008,    -- mage row mod+left     = Amplify Magic
    SelfShieldRows = true,      -- your own shields, leading the ally rows
    -- How the personal block (My Shields, the Water Elemental) is drawn.
    --   DIALS  the radial plate's language: one disc per tracker on ONE line
    --   ROWS   the original: a half-height bar row per tracker, stacked
    PersonalStyle = "DIALS",
    DialSize = 28,              -- a dial's diameter in pixels (shrinks to fit the frame)
    -- What a dial's absorb band is drawn with: MATCH (whatever Bar Texture
    -- is) | FLAT | BLIZZARD | GLOSS | BEVEL | RIDGE | GLASS
    DialTexture = "MATCH",
    DialTextSize = 0,           -- the number's font size in points (0 = sized off the dial)
    DialTextShade = 0.45,       -- how far a lit dial's face darkens under its number (0 = not at all)
    MageBannerCooldowns = true, -- Ice Block + Cold Snap segments on the banner

    -- Druid layer: the hot board. Its own click keys for the same reason the
    -- mage's are separate — the DB is account-wide, so a priest's and a
    -- mage's bindings have to survive a druid touching these.
    -- Ally-buff strip. BuffTrack/BuffAdvise are per-buff overrides keyed
    -- "LAYER:KEY" (absent = the registry's own default), the same shape the
    -- ability book uses, so the DB never carries a row for a buff you have
    -- not touched.
    BuffTrack = {},             -- which buffs get a slot
    BuffAdvisor = true,         -- master switch for the urgency (dark red) read
    BuffAdvise = {},            -- per-buff urgency overrides
    HotRefreshAt = 4,           -- seconds left at/under which a hot counts as expiring
    -- Lifebloom, which is a ROLL rather than a hot: seven seconds, three
    -- stacks, and a refresh you owe every five seconds forever. It gets its
    -- own instruments because the shared ones are tuned for twelve- and
    -- twenty-one-second hots, and on a seven-second buff they read as
    -- permanently urgent — which is the same as not reading at all.
    --   LBDisplay  OFF (a plain hot slot) | CLOCK | BAR | BOTH
    LBDisplay = "BOTH",
    LBRefreshAt = 3,            -- its own refresh window, separate from HotRefreshAt
    LBLateAt = 1.5,             -- under this you are refreshing behind, not early
    LBStackPips = true,         -- three pips instead of a stack digit
    LBPriority = false,         -- an expiring roll outranks other expiring hots
    LBAlert = false,            -- flash the row when the roll goes late
    LBAlertSound = false,       -- and play a sound with it
    HotReadyAt = 90,            -- health % at/under which a hotless ally goes READY
    HotBannerCooldowns = true,  -- Innervate/NS/Rebirth/Barkskin segments on the banner
    DruidClickLeft = 774,       -- druid row left-click   = Rejuvenation
    DruidClickRight = 33763,    -- druid row right-click  = Lifebloom
    DruidClickMiddle = "TARGET",-- druid row middle-click = target the ally
    DruidClickModLeft = 8936,   -- druid row mod+left     = Regrowth

    -- Paladin layer: the blessing board. Its own click keys for the same
    -- reason every other layer's are separate — the DB is account-wide.
    -- (No BlessReadyAt any more: that was the Hands strip's health bar, and
    -- the slot it read no longer exists. A naked ally is always READY.)
    BlessRefreshAt = 3,         -- seconds left at/under which a Freedom / Protection / Sacrifice counts as expiring
    BlessBannerCooldowns = true,-- Lay on Hands / bubble / wings segments on the banner
    -- The blessing family as ONE slot per ally (Pally Power's shape), showing
    -- whichever blessing of yours is on them. On by default: nine mutually
    -- exclusive slots is nine icons answering a question that only ever has
    -- one answer, eight of them always dark.
    BlessCombine = true,        -- collapse the blessings into one slot
    BlessMineOnly = true,       -- only blessings YOU cast count as cover
    BlessRowMenu = true,        -- click an ally's blessing slot to reassign (out of combat)
    BlessAssign = {},           -- per-player override   ("Grimtusk" -> "KINGS" / "NONE")
    BlessClass = {},            -- per-class default     ("MAGE"     -> "KINGS" / "NONE")
    -- No legacy PalaClick* keys: the paladin layer was born after click
    -- bindings moved into per-talent-profile stores, so its starting bindings
    -- live in the engine's SDATA.BIND_DEFAULTS with everyone else's and there
    -- is nothing here to migrate off.

    -- Banner utility buttons. Bandage is chassis (every class) and stays on:
    -- it is the one you press mid-fight. The mage's four are between-games
    -- convenience and default OFF as a group, because on the banner they sit
    -- in FRONT of the readout and push the segments that matter during a
    -- fight toward the truncation edge.
    MageUtilityButtons = false, -- conjure / consume / gem / portals cluster
    ShowUtilityCounts = true,   -- inventory tallies over the water/food/gem/bandage icons
    ShowPortalButton = true,    -- portals & teleports popout (within the cluster)
    ShowGemButton = true,       -- mana gem: use / conjure (within the cluster)
    ShowBandageButton = true,   -- First Aid: bandage, lockout, open the window

    -- Party Ability Bar (engine lands in phases; keys reserved now)
    ShowAbilityBar = true,      -- cooldown strip under every player row (a row that cannot have one holds no band)
    AbilityMaxIcons = 6,        -- most ability icons per strip (3-8)
    AbilityBarSelf = true,      -- include your own row's strip
    AbilityBarOnlySelf = false, -- ...and ONLY your own row's
    AbilityCdText = true,       -- remaining-time text on cooling icons
    AbilityBarBackdrop = true,  -- dark panel behind each strip, hugging its icons
    AbilityTrack = {},          -- per-ability overrides ("CLASS:KEY" -> bool; absent = book default)
    TrackManaShield = true,     -- Mana Shield row in the self-shield extra
    TrackWards = true,          -- Fire Ward / Frost Ward rows in the extra
    TrackIceBlock = true,       -- the Ice Block tracker: Hypothermia > Block > Cold Snap > the shorter wait

    -- Dispellable-debuff strip (right of the frame)
    ShowDispels = false,        -- master switch for the strip
    DispelShowAll = false,      -- show every debuff, not just ones you can dispel
    DispelShowImportant = true, -- include healer-relevant undispellables (Mortal Strike, Blind...)
    BurstGlow = true,           -- violet edge + wash on a row whose ally popped Arcane Power
    DispelCCGlow = true,        -- pulse a glow on crowd-control debuffs
    DispelHealGlow = true,      -- red pulse on healing-reduction debuffs
    DispelSweep = true,         -- radial duration sweep on each debuff icon
    DispelMaxIcons = 3,         -- icons per row (1-16)
    DispelIconSize = 16,        -- icon size in pixels
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderPartyFramesDB, DefaultSettings)
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    print("Commander Party Frames: settings restored to defaults")
end

-- Options that do nothing in secure Click-Cast mode (it uses a fixed roster
-- order so unit attributes never change in combat)
local function SortableMode()
    return CommanderPartyFramesDB.EnableShield and not CommanderPartyFramesDB.ClickCast
end

-- The per-layer click dropdown lists, and the single "which modifier?" picker
-- they went with, are gone: the binding grid builds its picker from the live
-- spellbook instead (see AddClickMatrix). That is both a bigger surface — every
-- modifier combination the client delivers, not one — and an honest one, since
-- it cannot offer a spell this character has never trained.

-- One definition, added to both class layers' Identity sections: the bar art
-- is chassis, not a class choice.
-- Shared with the rest of the suite: the art and the styles both come from
-- Commander_Events, so an icon on this board and an icon on any other
-- Commander board are shaded the same way at the same setting.
local ICON_STYLE_OPTION = {
    label = "Icon Recess",
    tooltip = "Shading laid over every spell icon on the board — the ability strip, dispel slots, consumables, class icons and portraits. Flat leaves them as Blizzard drew them. The other three shade the icon's rim so it reads as set into the row rather than pasted on it: Soft is a shallow press (what small icons want), Deep drives it harder, Carved is a hard narrow bevel.",
    options = Commander.ICON_STYLES,
    get = function() return CommanderPartyFramesDB.IconRecess end,
    set = function(value) CommanderPartyFramesDB.IconRecess = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

-- Also defined once and added to all three layers: the tracker strips are
-- chassis, so the spark is not a class decision either.
local SWEEP_EDGE_OPTION = {
    label = "Sweep Edge",
    tooltip = "Put a bright spark on the leading edge of the radial duration timers, so where a sweep IS reads at a glance instead of only how much shadow it has eaten. Affects the aura timers on the tracker strips: the own-aura strip, the ally-buff icons, and the dispellable-debuff icons. The party ability bar is deliberately left plain — those sweeps count down a cooldown, where the only question is ready or not, and a spark orbiting every one of them is motion you would have to learn to ignore.",
    get = function() return CommanderPartyFramesDB.SweepEdge end,
    set = function(value) CommanderPartyFramesDB.SweepEdge = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

local POWER_BAR_OPTION = {
    label = "Power Bar",
    tooltip = "The thin strip under each ally's health bar, showing what they actually run on. All Classes reads the unit's LIVE resource — mana, a warrior's rage, a rogue's or a shifted druid's energy, a hunter pet's focus — so a druid's strip changes the moment it shifts, and the two resources an arena plans around finally have somewhere to be seen. Mana Users Only is the board as it was: a strip for casters and nothing for anyone else. Off gives the row back the height.",
    options = {
        { text = "All Classes", value = "ALL" },
        { text = "Mana Users Only", value = "MANA" },
        { text = "Off", value = "OFF" },
    },
    get = function() return CommanderPartyFramesDB.PowerBar end,
    set = function(value) CommanderPartyFramesDB.PowerBar = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}
local POWER_COLOR_OPTION = {
    label = "Power Colors",
    tooltip = "By Resource tints each strip for what it is — blue mana, red rage, yellow energy, orange focus, green happiness — which on a mixed board is the fastest read of what a row even is. Classic Blue paints every strip the one blue the mana strip always wore, for a quieter bar.",
    options = {
        { text = "By Resource", value = "TYPE" },
        { text = "Classic Blue", value = "BLUE" },
    },
    get = function() return CommanderPartyFramesDB.PowerBarColor end,
    set = function(value) CommanderPartyFramesDB.PowerBarColor = value end,
    isEnabled = function()
        return CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.PowerBar ~= "OFF"
    end,
}
local BAR_TEXTURE_OPTION = {
    label = "Bar Texture",
    tooltip = "What every bar on a row is drawn with — the health/absorb fill, the shield segments riding it, the mana strip and the lockout drain. Flat is a solid block, which reads fastest at a glance and stays crisp on the half-height personal rows. Blizzard is the gloss the default unit frames have always worn. The last four are the board's own art: Gloss is lit from above and falls away, Bevel is flat with a lit top edge, Ridge adds a brushed grain, and Glass cuts hard across the middle — each of them also grooves the empty part of the bar, so a track reads even when it is empty. Colors are unchanged whichever you pick.",
    options = {
        { text = "Flat", value = "FLAT" },
        { text = "Blizzard", value = "BLIZZARD" },
        { text = "Gloss", value = "GLOSS" },
        { text = "Bevel", value = "BEVEL" },
        { text = "Ridge", value = "RIDGE" },
        { text = "Glass", value = "GLASS" },
    },
    get = function() return CommanderPartyFramesDB.BarTexture end,
    set = function(value) CommanderPartyFramesDB.BarTexture = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

-- ---------------------------------------------------------------------------
-- Tracked Abilities window: one row per class (plus the shared racials and
-- trinket), each with a dropdown of that class's ability book — check an
-- ability to let it on the strip, uncheck to hide it. Overrides live in
-- CommanderPartyFramesDB.AbilityTrack ("CLASS:KEY" -> bool, "*:KEY" for
-- shared); absent means the book default, so `off` entries ship untracked
-- and the curated default strip is unchanged until you opt in.
-- ---------------------------------------------------------------------------
local ABILITY_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ABILITY_KIND_LABELS = { DEF = "Defensive", CC = "Crowd control", KICK = "Interrupt", OFF = "Offensive", UTIL = "Utility" }
local ABILITY_ROW_H = 30
local abilityWindow

-- ---------------------------------------------------------------------------
-- Ally-buff controls. One pair of checkboxes per buff the class maintains on
-- other people: whether it gets a slot at all, and whether that slot is
-- allowed to judge how badly it is missed. Both store only DEVIATIONS from the
-- registry's own defaults, so SavedVariables stay small and a buff you never
-- touched follows any later re-tuning of the registry.
-- ---------------------------------------------------------------------------
local function BuffOverride(field, def, value, fallback)
    local t = CommanderPartyFramesDB[field]
    if not t then t = {}; CommanderPartyFramesDB[field] = t end
    if value == fallback then t[def.dbKey] = nil else t[def.dbKey] = value end
end

local function BuffFlag(field, def, fallback)
    local t = CommanderPartyFramesDB[field]
    local v = t and t[def.dbKey]
    if v == nil then return fallback end
    return v
end

-- Everything this class can put on somebody else, as a grid of the spells'
-- own icons — the icon IS the switch. A list of twelve checkboxes reading
-- "Track Prayer of Fortitude" is a worse way to answer "what am I watching"
-- than twelve icons where the lit ones are the answer.
--
--   left click   track / untrack (lit vs drained)
--   right click  let this slot judge urgency, or hush it (the gold pip)
--
-- Spells this character has not TRAINED are drawn struck through and refuse
-- both clicks. That is the honest version of "why is there no Lifebloom
-- slot": not silence, but the icon saying so.
-- Pitch, not gap: the cell is 30 wide but the LABEL under it needs room, and
-- at a 36px pitch every name past five characters clipped to "Aboli...". A
-- label you cannot read is worse than no label, so the pitch is set by the
-- text and the icon sits centred in it.
local BUFF_ICON_SIZE, BUFF_PITCH, BUFF_PER_ROW = 30, 54, 7
local BUFF_LABEL_H = 22       -- two short lines of GameFontHighlightSmall

local BUFF_ADVICE_TEXT = {
    ALWAYS = "always — there is no fight where you would rather not have it",
    VS_MELEE = "when an enemy melee is parked on them, or a wounded melee ally is trading hits",
    VS_SHADOW = "only against a team that actually deals shadow damage",
    VS_PHYSICAL = "only against an all-physical team, where the extra magic damage taken costs nothing",
    VS_CASTER = "only against a caster team worth blunting",
    VS_FEAR = "only against a team that brings a fear",
}

local function BuffFlag(field, def, fallback)
    local tbl = CommanderPartyFramesDB[field]
    local v = tbl and tbl[def.dbKey]
    if v == nil then return fallback end
    return v
end

local function BuffOverride(field, def, value, fallback)
    local tbl = CommanderPartyFramesDB[field]
    if not tbl then tbl = {}; CommanderPartyFramesDB[field] = tbl end
    if value == fallback then tbl[def.dbKey] = nil else tbl[def.dbKey] = value end
end

local function BuffTrackedUI(def) return BuffFlag("BuffTrack", def, def.default and true or false) end
local function BuffAdvisedUI(def) return BuffFlag("BuffAdvise", def, def.advise and true or false) end

-- Is this cell's toggle currently inert? The blessings share ONE assigned slot
-- while Combine is on, so their per-buff track switches decide nothing — and a
-- switch that does nothing has to say so rather than sit there looking live.
local function BuffCellMoot(def)
    return def.oneOf == "BLESSING" and CommanderPartyFramesDB.BlessCombine and true or false
end

local function BuffCellTooltip(self)
    local def = self.def
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(def.spellName or def.label, 1, 1, 1)
    if not def.known then
        GameTooltip:AddLine("Not trained on this character.", 1, 0.4, 0.4, true)
        GameTooltip:AddLine("It cannot take a slot, so the board will not show it.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
        return
    end
    if def.isHot then
        GameTooltip:AddLine("Your own, on that ally — the slot carries its remaining time as a sweep.",
            0.7, 0.7, 0.7, true)
    elseif def.emergency then
        GameTooltip:AddLine("A blessing on this client, not a Hand: it takes the ally's one blessing slot, and the slot shows it while it is on them.",
            0.7, 0.7, 0.7, true)
    elseif def.mine and CommanderPartyFramesDB.BlessMineOnly then
        GameTooltip:AddLine("Only yours counts; the Greater version fills the same slot.",
            0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine("Any caster's counts as covered; the group version fills the same slot.",
            0.7, 0.7, 0.7, true)
    end
    -- Said before the track/advise lines below, because if the switch is inert
    -- there is no point reading what it would have done.
    if BuffCellMoot(def) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("The blessings share one assigned slot right now, so this switch decides nothing.",
            1, 0.65, 0.3, true)
        GameTooltip:AddLine("Set who gets it under Blessings below, or turn One Blessing Slot off to give each blessing its own slot again.",
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
        return
    end
    if def.targets == "MANA" then
        GameTooltip:AddLine("Only appears on mana users.", 0.7, 0.7, 0.7, true)
    elseif def.targets == "MELEE" then
        GameTooltip:AddLine("Only appears on allies who swing a weapon (and on pets).",
            0.7, 0.7, 0.7, true)
    end
    if def.oneOf then
        GameTooltip:AddLine("One per ally: another of these already on them means this one is not missing.",
            0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(" ")
    if BuffTrackedUI(def) then
        GameTooltip:AddLine("Tracked — click to drop its slot", 0.4, 0.9, 0.4)
    else
        GameTooltip:AddLine("Not tracked — click to give it a slot", 0.8, 0.8, 0.8)
    end
    if def.advise then
        local how = BUFF_ADVICE_TEXT[def.advise] or "when the situation calls for it"
        if BuffAdvisedUI(def) then
            GameTooltip:AddLine("Advises: turns dark red " .. how, 1, 0.82, 0.25, true)
            GameTooltip:AddLine("Right-click to hush it", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("Hushed — tracks, never reddens", 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine("Right-click to let it advise " .. how, 0.6, 0.6, 0.6, true)
        end
    else
        GameTooltip:AddLine("No urgency rule — this one never reddens.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function BuffCellClick(self, button)
    local def = self.def
    if not def.known then return end
    -- Inert while the blessings share one slot: taking the click and silently
    -- storing a preference that changes nothing on screen reads as broken.
    -- The tooltip says where the live control is.
    if BuffCellMoot(def) then return end
    if button == "RightButton" then
        if not def.advise then return end
        BuffOverride("BuffAdvise", def, not BuffAdvisedUI(def), def.advise and true or false)
    else
        BuffOverride("BuffTrack", def, not BuffTrackedUI(def), def.default and true or false)
    end
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    if self.owner and self.owner.Refresh then self.owner:Refresh() end
    BuffCellTooltip(self)
end

-- ---------------------------------------------------------------------------
-- The click matrix: every modifier x every mouse button, as a grid of the
-- bound spells' own icons.
--
-- The old shape was four dropdowns and a "which modifier?" picker, which could
-- express exactly one modified click out of the twenty-four the client will
-- actually deliver. This is the whole surface: a row per modifier combination
-- in the order the secure code itself uses (alt, ctrl, shift), a column per
-- button, and each cell a click-to-open picker filtered to the spells this
-- character has really trained.
-- ---------------------------------------------------------------------------
local CLICK_CELL, CLICK_CELL_GAP, CLICK_LABEL_W = 28, 4, 104
local BIND_BOOK_CHUNK = 20      -- spells per alphabetical submenu

local bindMenu, bindMenuCell

local function ClickCellTooltip(self)
    local icon, label, missing = CommanderPartyFrames_BindDisplay(self.bindValue)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.modLabel .. " + " .. self.btnLabel, 1, 1, 1)
    if label == "Unbound" then
        GameTooltip:AddLine("Nothing bound — the click falls through.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(label, 0.4, 0.9, 0.4)
    end
    if missing then
        GameTooltip:AddLine("This character cannot cast that — the click will do nothing.",
            1, 0.4, 0.4, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to rebind, right-click to clear.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function ClickCellPick(value)
    if not bindMenuCell then return end
    CommanderPartyFrames_SetBind(bindMenuCell.bindKey, value)
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    if bindMenuCell.owner then bindMenuCell.owner:Refresh() end
end

local function ClickMenuInit(_, level)
    level = level or 1
    local info
    if level == 1 then
        info = UIDropDownMenu_CreateInfo()
        info.text, info.isTitle, info.notCheckable = "Bind to", true, true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "Clear this binding", true
        info.func = function() ClickCellPick(nil); CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)

        for _, a in ipairs(CommanderPartyFrames_GetClickActions()) do
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.icon = a.label, true, a.icon
            info.func = function() ClickCellPick(a.value); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end

        -- The curated groups first: what this class actually casts at a
        -- friendly unit, which is the answer nineteen times in twenty
        local byGroup, groups = CommanderPartyFrames_GetBindables()
        for _, g in ipairs(groups) do
            if byGroup[g] then
                info = UIDropDownMenu_CreateInfo()
                info.text, info.notCheckable, info.hasArrow = g, true, true
                info.menuList = g
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- ...then the whole spellbook, for the twentieth. Alphabetical
        -- buckets, because a single flat list of everything a level 70 knows
        -- is not a menu you can find anything in.
        local book = CommanderPartyFrames_GetSpellBook()
        if #book > 0 then
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.isTitle = " ", true, true
            UIDropDownMenu_AddButton(info, level)
            for first = 1, #book, BIND_BOOK_CHUNK do
                local last = math.min(first + BIND_BOOK_CHUNK - 1, #book)
                info = UIDropDownMenu_CreateInfo()
                info.text = string.format("All spells: %s - %s",
                    book[first].name:sub(1, 8), book[last].name:sub(1, 8))
                info.notCheckable, info.hasArrow = true, true
                info.menuList = "BOOK:" .. first
                UIDropDownMenu_AddButton(info, level)
            end
        end
    elseif level == 2 then
        local menuList = UIDROPDOWNMENU_MENU_VALUE
        local first = type(menuList) == "string" and menuList:match("^BOOK:(%d+)$")
        if first then
            local book = CommanderPartyFrames_GetSpellBook()
            first = tonumber(first)
            for i = first, math.min(first + BIND_BOOK_CHUNK - 1, #book) do
                local sp = book[i]
                info = UIDropDownMenu_CreateInfo()
                info.text, info.notCheckable, info.icon = sp.name, true, sp.icon
                -- Bound by name via the id; the client casts the highest rank
                info.func = function() ClickCellPick(sp.id); CloseDropDownMenus() end
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end
        local byGroup = CommanderPartyFrames_GetBindables()
        for _, sp in ipairs(byGroup[menuList] or {}) do
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.icon = sp.name, true, sp.icon
            info.func = function() ClickCellPick(sp.id); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

local function ClickCellClick(self, button)
    if button == "RightButton" then
        CommanderPartyFrames_SetBind(self.bindKey, nil)
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        if self.owner then self.owner:Refresh() end
        ClickCellTooltip(self)
        return
    end
    bindMenuCell = self
    if not bindMenu then
        bindMenu = CreateFrame("Frame", "CommanderPartyFramesBindMenu", UIParent,
            "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(bindMenu, ClickMenuInit, "MENU")
    ToggleDropDownMenu(1, nil, bindMenu, self, 0, 0)
end

-- Copy-from / reset, driven off the profile list. Both are destructive to the
-- profile you are looking at, which is exactly why the header above says which
-- one that is before you reach these.
local profileScratch = {}
local copyMenu

local function CopyMenuInit(_, level)
    local active = CommanderPartyFrames_ActiveProfile()
    CommanderPartyFrames_ListProfiles(profileScratch)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.isTitle, info.notCheckable = "Copy bindings from", true, true
    UIDropDownMenu_AddButton(info, level or 1)
    local any = false
    for _, key in ipairs(profileScratch) do
        if key ~= active then
            any = true
            info = UIDropDownMenu_CreateInfo()
            info.text = CommanderPartyFrames_ProfileLabel(key)
            info.notCheckable = true
            info.func = function()
                CommanderPartyFrames_CopyProfile(key, active)
                Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level or 1)
        end
    end
    if not any then
        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable, info.disabled = "No other profile yet", true, true
        UIDropDownMenu_AddButton(info, level or 1)
    end
end

local function AddClickMatrix(panel)
    local cells = {}
    local mods = CommanderPartyFrames_GetClickMods()
    local btns = CommanderPartyFrames_GetClickButtons()

    -- Which profile am I editing? Destructive controls sit below this line,
    -- so it has to be answered before the player reaches them.
    -- 22, not 18: the buttons in here are 20 tall, and a row shorter than its
    -- own contents is exactly how the section notes ended up drawing over the
    -- next control. Tagged so the harness can hold every custom row to that.
    local hdr = panel:AddRow(22, 8)
    hdr.probeChildren = {}
    local hdrText = hdr:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdrText:SetPoint("LEFT", hdr, "LEFT", 0, 0)
    local copyBtn = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    copyBtn:SetSize(96, 20)
    hdr.probeChildren[#hdr.probeChildren + 1] = copyBtn
    copyBtn:SetPoint("RIGHT", hdr, "RIGHT", -84, 0)
    copyBtn:SetText("Copy from...")
    copyBtn:SetScript("OnClick", function(self)
        if not copyMenu then
            copyMenu = CreateFrame("Frame", "CommanderPartyFramesCopyMenu", UIParent,
                "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(copyMenu, CopyMenuInit, "MENU")
        ToggleDropDownMenu(1, nil, copyMenu, self, 0, 0)
    end)
    local resetBtn = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, 20)
    hdr.probeChildren[#hdr.probeChildren + 1] = resetBtn
    resetBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    resetBtn:SetText("Defaults")
    resetBtn:SetScript("OnClick", function()
        CommanderPartyFrames_ResetProfile()
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        panel:Refresh()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset this profile", 1, 1, 1)
        GameTooltip:AddLine("Drops every binding in the profile shown above and goes back to this class's starting set. The other profiles are untouched.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Column headers
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
        row.probeChildren = {}
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
            -- Red rim: bound to something this character cannot cast, which
            -- is a click that saves fine and then silently does nothing
            cell.warn = cell:CreateTexture(nil, "OVERLAY")
            cell.warn:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
            cell.warn:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
            cell.warn:SetColorTexture(0.95, 0.25, 0.25, 0.8)
            cell.warn:Hide()
            cell:SetScript("OnClick", ClickCellClick)
            cell:SetScript("OnEnter", ClickCellTooltip)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.probeChildren[#row.probeChildren + 1] = cell
            cells[#cells + 1] = cell
        end
    end
    panel:AddRefresher(function()
        local on = CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast
        local active = CommanderPartyFrames_ActiveProfile()
        local auto = CommanderPartyFramesDB.ClickProfileMode ~= "FIXED"
        hdrText:SetText(string.format("Editing profile: |cffffd100%s|r %s",
            CommanderPartyFrames_ProfileLabel(active),
            auto and "|cff888888(follows your talent build)|r" or "|cff888888(single set)|r"))
        copyBtn:SetEnabled(on and true or false)
        resetBtn:SetEnabled(on and true or false)
        for _, cell in ipairs(cells) do
            cell.bindValue = CommanderPartyFrames_GetBind(cell.bindKey)
            local icon, _, missing = CommanderPartyFrames_BindDisplay(cell.bindValue)
            if icon then
                cell.icon:SetTexture(icon)
                cell.icon:SetDesaturated(not on)
                cell.icon:SetVertexColor(1, 1, 1, on and 1 or 0.5)
                cell.icon:Show()
            else
                cell.icon:Hide()
            end
            if missing then cell.warn:Show() else cell.warn:Hide() end
            cell:SetEnabled(on and true or false)
            cell.bg:SetColorTexture(1, 1, 1, on and 0.07 or 0.03)
        end
    end)
end

local function AddBuffSection(panel, layerMode)
    local defs = {}
    local book = CommanderPartyFrames_GetBuffBook and CommanderPartyFrames_GetBuffBook(layerMode)
    if book then for _, d in ipairs(book) do defs[#defs + 1] = d end end
    -- The druid's hots answer the same two questions and belong in the same
    -- grid: they are things you put on an ally and watch a slot for.
    local hots = CommanderPartyFrames_GetStripBook and CommanderPartyFrames_GetStripBook(layerMode)
    if hots then for _, d in ipairs(hots) do defs[#defs + 1] = d end end
    if #defs == 0 then return end

    panel:AddSection("Ally Buffs", "One slot per buff on the left of every row. The icon is the switch: left-click to track, right-click to let it judge urgency. Hover any icon for what it does.")
    panel:AddCheckbox({
        label = "Urgency Advisor",
        tooltip = "Master switch for the dark-red read. With it off every slot still tracks its buff, it just stops judging. Nothing reddens on an ally you cannot reach, on a spell that is genuinely cooling down, or while a druid is shifted out of caster form — urgency you cannot act on is not urgency — and two buffs that overwrite each other never both ask at once. |cffffd100/cpf buffs|r prints each slot's current verdict in the rule's own words.",
        get = function() return CommanderPartyFramesDB.BuffAdvisor end,
        set = function(value) CommanderPartyFramesDB.BuffAdvisor = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })

    local lines = math.ceil(#defs / BUFF_PER_ROW)
    local grid = panel:AddRow(lines * (BUFF_ICON_SIZE + BUFF_LABEL_H + 8) + 4, 10)
    grid.buffCells = {}
    -- Row height has to cover the label under the last line of icons, not just
    -- the icons: getting that wrong is what clipped the names to "Aboli..."
    grid.probeReach = lines * (BUFF_ICON_SIZE + BUFF_LABEL_H + 8)
    for i, def in ipairs(defs) do
        local col, line = (i - 1) % BUFF_PER_ROW, math.floor((i - 1) / BUFF_PER_ROW)
        local cell = CreateFrame("Button", nil, grid)
        cell:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
        cell:SetPoint("TOPLEFT", grid, "TOPLEFT",
            col * BUFF_PITCH + (BUFF_PITCH - BUFF_ICON_SIZE) / 2,
            -line * (BUFF_ICON_SIZE + BUFF_LABEL_H + 8))
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell.def, cell.owner = def, panel
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetAllPoints(cell)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Lit border on the tracked ones, so "what am I watching" is legible
        -- from across the page rather than needing a squint at saturation
        cell.border = cell:CreateTexture(nil, "BACKGROUND")
        cell.border:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
        cell.border:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
        cell.border:SetColorTexture(1, 0.82, 0.25, 0.85)
        cell.border:Hide()
        -- Gold corner pip: this slot is allowed to judge
        cell.pip = cell:CreateTexture(nil, "OVERLAY")
        cell.pip:SetColorTexture(1, 0.82, 0.25, 1)
        cell.pip:SetSize(6, 6)
        cell.pip:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 1, 1)
        cell.pip:Hide()
        -- Struck through: not in the spellbook, not a choice
        cell.slash = cell:CreateTexture(nil, "OVERLAY")
        cell.slash:SetColorTexture(0.95, 0.25, 0.25, 0.9)
        cell.slash:SetHeight(2)
        cell.slash:SetPoint("LEFT", cell, "LEFT", 2, 0)
        cell.slash:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
        cell.slash:Hide()
        cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
        cell.label:SetWidth(BUFF_PITCH - 2)
        cell.label:SetHeight(BUFF_LABEL_H)
        cell.label:SetJustifyH("CENTER")
        cell.label:SetJustifyV("TOP")
        cell.label:SetMaxLines(2)
        cell:SetScript("OnClick", BuffCellClick)
        cell:SetScript("OnEnter", BuffCellTooltip)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        grid.buffCells[i] = cell
    end

    panel:AddRefresher(function()
        for _, cell in ipairs(grid.buffCells) do
            local def = cell.def
            -- Live spell data: the icon and name only exist after login, and
            -- `known` changes with training and respecs
            local id = def.id or def.baseId
            if GetSpellInfo and id then
                local n, _, icon = GetSpellInfo(id)
                def.spellName = n or def.label
                if icon then def.icon = icon end
            end
            cell.icon:SetTexture(def.icon)
            local tracked = BuffTrackedUI(def)
            if not def.known then
                -- Readable, but plainly unavailable. Sunk any darker and the
                -- icon vanished into the page, leaving the red strike drawn
                -- across nothing at all.
                cell.icon:SetDesaturated(true)
                cell.icon:SetVertexColor(0.6, 0.6, 0.6, 0.85)
                cell.border:Hide(); cell.pip:Hide(); cell.slash:Show()
                cell.label:SetTextColor(0.75, 0.4, 0.4)
            elseif BuffCellMoot(def) then
                -- Trained, but its switch is currently moot. Drawn as the
                -- assignment grid draws an inherited answer — legible, plainly
                -- not a live decision — rather than as the untrained strike,
                -- which would claim something false about the spellbook.
                cell.slash:Hide()
                cell.icon:SetDesaturated(true)
                cell.icon:SetVertexColor(0.6, 0.6, 0.6, 0.6)
                cell.border:Hide(); cell.pip:Hide()
                cell.label:SetTextColor(0.5, 0.5, 0.5)
            else
                cell.slash:Hide()
                cell.icon:SetDesaturated(not tracked)
                if tracked then
                    cell.icon:SetVertexColor(1, 1, 1, 1)
                    cell.border:Show()
                    cell.label:SetTextColor(1, 0.82, 0.25)
                else
                    cell.icon:SetVertexColor(0.45, 0.45, 0.5, 0.85)
                    cell.border:Hide()
                    cell.label:SetTextColor(0.55, 0.55, 0.55)
                end
                if tracked and def.advise and BuffAdvisedUI(def)
                    and CommanderPartyFramesDB.BuffAdvisor then
                    cell.pip:Show()
                else
                    cell.pip:Hide()
                end
            end
            cell.label:SetText(def.label)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Blessing assignment: who should be carrying what.
--
-- Two grids over one idea. The class grid is the answer for everybody — set
-- Kings on mages once and every mage you ever group with is handled. The
-- player list is the exception: the one warrior you want on Sanctuary, the
-- healer you want on Wisdom. A player row that has never been touched shows
-- the class answer greyed, so "what will actually happen here" is visible
-- without having to hold the fallback ladder in your head.
--
-- The board itself carries the same menu on each ally's blessing slot, which
-- is where you will really use it; this page exists so the class defaults are
-- editable while you are alone, and so an override on someone who is offline
-- can still be found and cleared.
-- ---------------------------------------------------------------------------
local BLESS_CELL, BLESS_PER_ROW, BLESS_ROSTER_MAX = 30, 5, 12
local BLESS_LABEL_H, BLESS_ROSTER_H = 16, 22

local assignMenu, assignCell

local function ClassLabel(classKey)
    if classKey == "PET" then return "Pets" end
    local name = classKey and LOCALIZED_CLASS_NAMES_MALE
        and LOCALIZED_CLASS_NAMES_MALE[classKey]
    if name then return name end
    if not classKey then return "?" end
    return classKey:sub(1, 1) .. classKey:sub(2):lower()
end

local function ClassRGB(classKey)
    local cc = classKey and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classKey]
    if cc then return cc.r, cc.g, cc.b end
    return 0.85, 0.85, 0.85
end

local function AssignMenuInit(_, level)
    local cell = assignCell
    if not cell then return end
    level = level or 1
    local stored = CommanderPartyFrames_BlessGet(cell.field, cell.assignKey)
    local none = CommanderPartyFrames_BlessNone()
    local info

    info = UIDropDownMenu_CreateInfo()
    info.text, info.isTitle, info.notCheckable = cell.title or "Blessing", true, true
    UIDropDownMenu_AddButton(info, level)

    for _, def in ipairs(CommanderPartyFrames_BlessOptions(cell.probeKey)) do
        info = UIDropDownMenu_CreateInfo()
        info.text, info.icon = def.label, def.icon
        info.checked = (stored == def.key)
        info.func = function()
            CommanderPartyFrames_BlessSet(cell.field, cell.assignKey, def.key)
            CloseDropDownMenus()
            if cell.owner then cell.owner:Refresh() end
        end
        UIDropDownMenu_AddButton(info, level)
    end

    info = UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable = "Don't bless them", true
    info.checked = (stored == none)
    info.func = function()
        CommanderPartyFrames_BlessSet(cell.field, cell.assignKey, none)
        CloseDropDownMenus()
        if cell.owner then cell.owner:Refresh() end
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = cell.field == "BlessAssign" and "Follow their class" or "Back to the default"
    info.notCheckable, info.disabled = true, (stored == nil)
    info.func = function()
        CommanderPartyFrames_BlessSet(cell.field, cell.assignKey, nil)
        CloseDropDownMenus()
        if cell.owner then cell.owner:Refresh() end
    end
    UIDropDownMenu_AddButton(info, level)
end

local function AssignCellClick(self, button)
    if not self.assignKey then return end
    -- Right-click clears, the same verb it has in the binding grid and the
    -- buff grid: on this page right-click always means "undo this cell".
    if button == "RightButton" then
        CommanderPartyFrames_BlessSet(self.field, self.assignKey, nil)
        if self.owner then self.owner:Refresh() end
        return
    end
    assignCell = self
    if not assignMenu then
        assignMenu = CreateFrame("Frame", "CommanderPartyFramesAssignMenu", UIParent,
            "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(assignMenu, AssignMenuInit, "MENU")
    ToggleDropDownMenu(1, nil, assignMenu, self, 0, 0)
end

local function AssignCellTooltip(self)
    if not self.assignKey then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.title or "Blessing", 1, 1, 1)
    if self.showDef then
        GameTooltip:AddLine(self.showDef.label, 1, 0.82, 0.25)
    else
        GameTooltip:AddLine("Nothing — leave them unblessed", 0.7, 0.7, 0.7)
    end
    if not self.stored then
        GameTooltip:AddLine(self.field == "BlessAssign"
            and "Inherited from their class — nothing set on them by name."
            or "The built-in default; nothing set here yet.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to choose, right-click to clear.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- Draw one assignment cell from its current answer. Shared by both grids: the
-- only difference between a class cell and a player cell is which table the
-- answer is stored in, and an inherited answer draws dimmed so a cell that is
-- merely showing you the fallback never looks like a decision you made.
local function PaintAssignCell(cell, def, stored)
    cell.showDef, cell.stored = def, stored
    if def then
        cell.icon:SetTexture(def.icon)
        cell.icon:SetDesaturated(not stored)
        cell.icon:SetVertexColor(1, 1, 1, stored and 1 or 0.55)
        cell.icon:Show()
        cell.empty:Hide()
    else
        cell.icon:Hide()
        cell.empty:Show()
    end
    if stored then cell.border:Show() else cell.border:Hide() end
end

local function NewAssignCell(parent, panel, field)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetSize(BLESS_CELL, BLESS_CELL)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell.owner, cell.field = panel, field
    cell.border = cell:CreateTexture(nil, "BACKGROUND")
    cell.border:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
    cell.border:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
    cell.border:SetColorTexture(1, 0.82, 0.25, 0.85)
    cell.border:Hide()
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints(cell)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- The "nothing" state needs to be a mark, not an absence: an empty square
    -- reads as "not loaded yet" rather than "deliberately unblessed".
    cell.empty = cell:CreateTexture(nil, "ARTWORK")
    cell.empty:SetAllPoints(cell)
    cell.empty:SetColorTexture(0.18, 0.18, 0.2, 0.9)
    cell.empty:Hide()
    cell:SetScript("OnClick", AssignCellClick)
    cell:SetScript("OnEnter", AssignCellTooltip)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return cell
end

local function AddBlessingSection(panel)
    panel:AddSection("Blessings",
        "One slot per ally showing whichever blessing of yours is on them right now — a Kings with its minutes, or the Protection you just spent on them with its seconds — and, when none is, the blessing you decided they should have, ghosted. Set that answer per class below, override it per player, or just click an ally's blessing slot on the board.")
    panel:AddCheckboxPair({
        label = "One Blessing Slot",
        tooltip = "Collapse all nine blessings — Kings, Might, Wisdom, Salvation, Sanctuary and Light, plus Freedom, Protection and Sacrifice, which are blessings on this client and take the same slot — into a single slot on each ally's row. It shows whichever of yours is on them with its own remaining time; when none is, it shows the one you assigned, ghosted. The game only lets you hold ONE blessing on a target, so nine slots were nine icons answering a question with one answer. Off gives you back a slot per tracked blessing, chosen in the Ally Buffs grid above — and the row's colour stops reading the blessing, because the READY / REFRESH / SHIELDED ladder is the one slot's.",
        get = function() return CommanderPartyFramesDB.BlessCombine end,
        set = function(value) CommanderPartyFramesDB.BlessCombine = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Only Mine",
        tooltip = "Count only blessings YOU cast. Two paladins may each hold a different blessing on the same target, so another paladin's Kings tells you nothing about whether yours is on them — with this off, their buff makes your slot look handled while your own blessing has been gone for ten minutes. Leave it on unless you have a reason.",
        get = function() return CommanderPartyFramesDB.BlessMineOnly end,
        set = function(value) CommanderPartyFramesDB.BlessMineOnly = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckbox({
        label = "Click to Reassign",
        tooltip = "Click an ally's blessing slot on the board to pick what they should be carrying, without opening this page. Out of combat only, and deliberately: the slot is a small insecure target sitting on top of a click-cast row, so leaving it live in combat would quietly swallow a binding at the worst possible moment. In combat the icon goes back to being an icon and every click on the row is your binding again.",
        get = function() return CommanderPartyFramesDB.BlessRowMenu end,
        set = function(value) CommanderPartyFramesDB.BlessRowMenu = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.BlessCombine end,
    })

    -- ---- By class: the answer for everybody ----
    local order = CommanderPartyFrames_BlessClassOrder and CommanderPartyFrames_BlessClassOrder()
    if not order then return end
    panel:AddSection("By Class",
        "What a member of each class should be carrying. This is the answer for anyone you have not named below — set it once and every mage you ever group with is handled.")
    local lines = math.ceil(#order / BLESS_PER_ROW)
    local pitch = math.floor(BLESS_CELL * 2.2)
    local gridH = lines * (BLESS_CELL + BLESS_LABEL_H + 8)
    local grid = panel:AddRow(gridH + 4, 10)
    grid.probeReach = gridH
    grid.probeChildren = {}
    local classCells = {}
    for i, classKey in ipairs(order) do
        local col, line = (i - 1) % BLESS_PER_ROW, math.floor((i - 1) / BLESS_PER_ROW)
        local cell = NewAssignCell(grid, panel, "BlessClass")
        cell:SetPoint("TOPLEFT", grid, "TOPLEFT",
            col * pitch + (pitch - BLESS_CELL) / 2,
            -line * (BLESS_CELL + BLESS_LABEL_H + 8))
        cell.assignKey, cell.probeKey = classKey, classKey
        cell.title = ClassLabel(classKey)
        cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
        cell.label:SetWidth(pitch - 2)
        cell.label:SetHeight(BLESS_LABEL_H)
        cell.label:SetJustifyH("CENTER")
        cell.label:SetText(ClassLabel(classKey))
        cell.label:SetTextColor(ClassRGB(classKey))
        grid.probeChildren[#grid.probeChildren + 1] = cell
        classCells[i] = cell
    end

    -- ---- By player: the exceptions ----
    panel:AddSection("By Player",
        "Everyone in your group right now, plus anyone who already has an override saved. A name you have not touched shows its class answer greyed — that is what the board will do, not a choice you made.")
    local listH = BLESS_ROSTER_MAX * BLESS_ROSTER_H
    local list = panel:AddRow(listH + 4, 6)
    list.probeReach = listH
    list.probeChildren = {}
    local rosterRows = {}
    for n = 1, BLESS_ROSTER_MAX do
        local rr = {}
        rr.frame = CreateFrame("Frame", nil, list)
        rr.frame:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(n - 1) * BLESS_ROSTER_H)
        rr.frame:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        rr.frame:SetHeight(BLESS_ROSTER_H)
        rr.name = rr.frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rr.name:SetPoint("LEFT", rr.frame, "LEFT", 2, 0)
        rr.name:SetJustifyH("LEFT")
        rr.cell = NewAssignCell(rr.frame, panel, "BlessAssign")
        rr.cell:SetSize(BLESS_ROSTER_H - 4, BLESS_ROSTER_H - 4)
        rr.cell:SetPoint("LEFT", rr.frame, "LEFT", 150, 0)
        rr.frame:Hide()
        list.probeChildren[#list.probeChildren + 1] = rr.cell
        rosterRows[n] = rr
    end
    local more = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    more:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 2, 2)
    more:Hide()

    panel:AddRefresher(function()
        -- Both grids go flat when the family is not collapsed: with six
        -- separate slots there is no assignment for them to be about, and a
        -- live-looking grid that changes nothing is worse than a dim one.
        local enabled = (CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.BlessCombine) and true or false
        for _, cell in ipairs(classCells) do
            local def, stored = CommanderPartyFrames_BlessResolve(cell.assignKey)
            PaintAssignCell(cell, def, stored)
            cell:SetEnabled(enabled)
            cell:SetAlpha(enabled and 1 or 0.4)
        end
        local roster = CommanderPartyFrames_BlessRoster and CommanderPartyFrames_BlessRoster() or {}
        local shown = math.min(#roster, BLESS_ROSTER_MAX)
        for n = 1, BLESS_ROSTER_MAX do
            local rr, e = rosterRows[n], roster[n]
            if n <= shown and e then
                rr.cell.assignKey = e.key
                rr.cell.probeKey = e.isPet and "PET" or e.class
                rr.cell.title = e.name
                rr.name:SetText(e.name)
                rr.name:SetTextColor(ClassRGB(e.class))
                rr.name:SetAlpha(e.online and 1 or 0.6)
                -- The RESOLVED answer, not the stored one: a row showing
                -- nothing because you never named this person would be hiding
                -- exactly what the board is about to do on their row.
                local stored = CommanderPartyFrames_BlessGet("BlessAssign", e.key)
                local def
                if stored == CommanderPartyFrames_BlessNone() then
                    def = nil
                else
                    def = CommanderPartyFrames_BlessResolveFor(e.key, rr.cell.probeKey)
                end
                PaintAssignCell(rr.cell, def, stored ~= nil)
                rr.cell:SetEnabled(enabled)
                rr.frame:SetAlpha(enabled and 1 or 0.4)
                rr.frame:Show()
            else
                rr.frame:Hide()
            end
        end
        if #roster > BLESS_ROSTER_MAX then
            more:SetText(string.format("...and %d more — assign those from their row on the board.",
                #roster - BLESS_ROSTER_MAX))
            more:Show()
        else
            more:Hide()
        end
    end)
end

local function AbilityList(classToken)
    if not CommanderPartyFrames_GetAbilityBook then return nil end
    local book, shared = CommanderPartyFrames_GetAbilityBook()
    if classToken == "SHARED" then return shared end
    return book[classToken]
end

local function AbilityTok(classToken, entry)
    return (classToken == "SHARED" and "*" or classToken) .. ":" .. entry.key
end

local function AbilityTracked(classToken, entry)
    local overrides = CommanderPartyFramesDB.AbilityTrack
    local value = overrides and overrides[AbilityTok(classToken, entry)]
    if value == nil then return not entry.off end
    return value
end

-- Store only deviations from the book default, so SavedVariables stay small
-- and untouched abilities follow any later re-curation of the book
local function WriteAbilityOverride(classToken, entry, tracked)
    local overrides = CommanderPartyFramesDB.AbilityTrack
    if not overrides then
        overrides = {}
        CommanderPartyFramesDB.AbilityTrack = overrides
    end
    if tracked == (not entry.off) then
        overrides[AbilityTok(classToken, entry)] = nil
    else
        overrides[AbilityTok(classToken, entry)] = tracked
    end
end

local function AbilityCounts(classToken)
    local list = AbilityList(classToken)
    if not list then return 0, 0 end
    local tracked = 0
    for _, entry in ipairs(list) do
        if AbilityTracked(classToken, entry) then tracked = tracked + 1 end
    end
    return tracked, #list
end

local function FormatAbilityCd(cd)
    if cd >= 60 then return string.format("%dm", math.floor(cd / 60 + 0.5)) end
    return string.format("%ds", cd)
end

local function RefreshAbilityWindow()
    if not (abilityWindow and abilityWindow:IsShown()) then return end
    for _, row in ipairs(abilityWindow.rows) do
        local tracked, total = AbilityCounts(row.classToken)
        row.count:SetText(string.format("%d of %d", tracked, total))
        local c = tracked > 0 and 0.85 or 0.5
        row.count:SetTextColor(c, c, c)
    end
end

local function AbilityMenuInit(menu)
    local classToken = menu.classToken
    local list = AbilityList(classToken)
    if not list then return end

    local title = UIDropDownMenu_CreateInfo()
    title.isTitle = true
    title.notCheckable = true
    title.text = menu.classLabel or classToken
    UIDropDownMenu_AddButton(title)

    for _, entry in ipairs(list) do
        local info = UIDropDownMenu_CreateInfo()
        local name = entry.dispName or entry.name
        info.text = string.format("|T%s:16|t %s  |cff8a8a8a%s|r",
            entry.dispIcon or entry.icon, name, FormatAbilityCd(entry.cd))
        info.isNotRadio = true
        info.keepShownOnClick = true
        info.checked = function() return AbilityTracked(classToken, entry) end
        info.func = function(_, _, _, checked)
            WriteAbilityOverride(classToken, entry, checked and true or false)
            Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
            RefreshAbilityWindow()
        end
        local detail = (ABILITY_KIND_LABELS[entry.kind] or entry.kind)
            .. (entry.tier == 1 and " — always on the strip while tracked."
                or " — shows only while cooling down.")
        if entry.spec then
            detail = detail .. "  " .. entry.spec:sub(1, 1) .. entry.spec:sub(2):lower() .. " only."
        end
        info.tooltipTitle = name
        info.tooltipText = detail
        info.tooltipOnButton = 1
        UIDropDownMenu_AddButton(info)
    end

    local function QuickSet(label, value)
        local info = UIDropDownMenu_CreateInfo()
        info.text = label
        info.notCheckable = true
        info.keepShownOnClick = true
        info.func = function()
            for _, entry in ipairs(list) do
                WriteAbilityOverride(classToken, entry, value == nil and (not entry.off) or value)
            end
            Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
            RefreshAbilityWindow()
            -- Repaint the open menu's checkmarks (only the clicked button
            -- refreshes itself)
            if UIDropDownMenu_Refresh then UIDropDownMenu_Refresh(menu, nil, 1) end
        end
        UIDropDownMenu_AddButton(info)
    end
    QuickSet("Track all", true)
    QuickSet("Track none", false)
    QuickSet("Book defaults", nil)
end

local function BuildAbilityWindow()
    local rowTokens = {}
    for i, token in ipairs(ABILITY_CLASSES) do rowTokens[i] = token end
    rowTokens[#rowTokens + 1] = "SHARED"

    local window = CreateFrame("Frame", "CommanderPartyFramesAbilityWindow", UIParent)
    window:SetSize(348, 74 + #rowTokens * ABILITY_ROW_H + 12)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetClampedToScreen(true)
    Commander.UI.ApplyStyleBackdrop(window, "DARK")
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderPartyFramesAbilityWindow")
    end

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Party Ability Bar — Tracked Abilities")
    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", window, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Choose what each class's strip may show. New options ship unchecked — the curated default holds until you opt in.")

    local menu = CreateFrame("Frame", "CommanderPartyFramesAbilityMenu", window, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, function() AbilityMenuInit(menu) end, "MENU")

    window.rows = {}
    for index, classToken in ipairs(rowTokens) do
        local row = CreateFrame("Frame", nil, window)
        row:SetHeight(ABILITY_ROW_H)
        row:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -66 - (index - 1) * ABILITY_ROW_H)
        row:SetPoint("RIGHT", window, "RIGHT", -12, 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        if classToken == "SHARED" then
            icon:SetTexture(Commander.TrinketIcon and Commander.TrinketIcon("player")
                or "Interface\\Icons\\INV_Jewelry_TrinketPVP_01")
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            label:SetText("Everyone — racials & trinket")
        else
            local info = Commander.GetClassInfo(classToken)
            icon:SetTexture(info.icon)
            if info.iconCoords then icon:SetTexCoord(unpack(info.iconCoords)) end
            label:SetText(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken)
            label:SetTextColor(info.color[1], info.color[2], info.color[3])
        end

        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(90, 22)
        button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        button:SetText("Choose…")
        button:SetScript("OnClick", function(self)
            menu.classToken = classToken
            menu.classLabel = label:GetText()
            ToggleDropDownMenu(1, nil, menu, self, 0, 0)
        end)

        local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("RIGHT", button, "LEFT", -10, 0)

        row.classToken, row.count = classToken, count
        window.rows[#window.rows + 1] = row
    end

    window:SetScript("OnShow", RefreshAbilityWindow)
    window:Hide()
    return window
end

function CommanderPartyFrames_ToggleAbilityWindow()
    if not CommanderPartyFrames_GetAbilityBook then
        print("Commander Party Frames: ability book unavailable")
        return
    end
    if not abilityWindow then abilityWindow = BuildAbilityWindow() end
    abilityWindow:SetShown(not abilityWindow:IsShown())
end

-- The whole module on one scrollable page, built for the class that is logged
-- in: the Priest reshield board, the Mage party frames, or a dormant-class note.
-- The party ability bar is pure chassis — every layer shows the same strip
-- of other players' cooldowns — and every one of the four pages carried a
-- byte-identical copy of this section. One copy now.
-- Alert Sounds: every noise this board can make, on one page, with the sound
-- each one plays and a button to hear it.
--
-- It exists because the alerts themselves are scattered by subject — the
-- shield break sits with the shield, Lifebloom's late warning with the roll,
-- Mending's with Mending — which is the right place for their ON/OFF switches
-- and the worst possible place to answer the question you actually have,
-- which is "what was that noise, and can I make it something else". So the
-- switches stay where they are and the SOUNDS gather here; a line whose alert
-- is currently muted greys out, which is also how this page tells you what is
-- live without adding a fifth copy of the same toggle.
--
-- Built from SDATA.ALERT_LINES, filtered to the layer, so a new alert appears
-- here the day it is added and nothing has to be kept in step by hand.
local function AddAlertSoundsSection(panel, layerKey)
    if not CommanderPartyFrames_GetAlertLines then return end
    local lines = CommanderPartyFrames_GetAlertLines(layerKey)
    if #lines == 0 then return end

    local options = {}
    for _, snd in ipairs(CommanderPartyFrames_GetAlertSounds()) do
        -- `text`, which is the key the panel framework reads. Calling it
        -- `label` (as every other control in this file does for its own
        -- caption) built a dropdown with a blank face and blank entries.
        options[#options + 1] = { value = snd.key, text = snd.label }
    end

    -- One get/set pair per saved variable, written out rather than indexed by
    -- line.dbKey. Table-driven would be four lines shorter and would also make
    -- these four reads invisible to settings_reach, which can only see the
    -- reads it can read — and that check is the one tool that has caught a
    -- control quietly missing from a page, three separate times. Four literal
    -- pairs is a cheap price for keeping it able to see this section.
    --
    -- It doubles as the drift guard below: an alert whose key falls out of
    -- step with the engine's table stops being DRAWN, rather than silently
    -- drawing a control that writes a saved variable nothing reads.
    local access = {
        SoundExpose = {
            get = function() return CommanderPartyFramesDB.SoundExpose end,
            set = function(v) CommanderPartyFramesDB.SoundExpose = v end },
        SoundLBLate = {
            get = function() return CommanderPartyFramesDB.SoundLBLate end,
            set = function(v) CommanderPartyFramesDB.SoundLBLate = v end },
        SoundPoMSpent = {
            get = function() return CommanderPartyFramesDB.SoundPoMSpent end,
            set = function(v) CommanderPartyFramesDB.SoundPoMSpent = v end },
        SoundPoMWasted = {
            get = function() return CommanderPartyFramesDB.SoundPoMWasted end,
            set = function(v) CommanderPartyFramesDB.SoundPoMWasted = v end },
        SoundPoMLost = {
            get = function() return CommanderPartyFramesDB.SoundPoMLost end,
            set = function(v) CommanderPartyFramesDB.SoundPoMLost = v end },
    }
    for i = #lines, 1, -1 do
        if not (lines[i].dbKey and access[lines[i].dbKey]) then
            table.remove(lines, i)
        end
    end
    if #lines == 0 then return end

    panel:AddSection("Alert Sounds", "Every noise this board makes, and which sound it makes. Each alert's own on/off switch stays with the thing it warns about, so a currently muted line is greyed here rather than given a fifth copy of the same toggle — and picking a sound plays it, which is how you tell two of them apart before the fight instead of during it.")

    local function Spec(line)
        return {
            label = line.label,
            tooltip = line.tip .. "|n|nPicking a sound plays it. A choice that stays silent is one whose file did not ship with this client — pick another; nothing breaks either way.",
            options = options,
            get = function() return access[line.dbKey].get() or line.default end,
            set = function(value) access[line.dbKey].set(value) end,
            onSelect = function() CommanderPartyFrames_PlayAlert(line.key) end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB[line.onKey] and true or false
            end,
        }
    end

    for i = 1, #lines, 2 do
        panel:AddDropdownPair(Spec(lines[i]), lines[i + 1] and Spec(lines[i + 1]) or nil)
    end

    local buttons = {}
    for _, line in ipairs(lines) do
        buttons[#buttons + 1] = {
            label = line.label,
            width = 118,
            tooltip = "Play the " .. line.label .. " sound now, whether or not that alert is currently switched on.",
            onClick = function() CommanderPartyFrames_PlayAlert(line.key) end,
        }
    end
    panel:AddButtonRow(buttons)
end

local function AddAbilityBarSection(panel)
    panel:AddSection("Party Ability Bar", "A curated cooldown strip under every player: match-deciders always visible (lit = ready, swept = cooling), trinkets/racials surfacing only once spent, a red rim for lockouts (Hypothermia, Forbearance), and a gold pip when Cold Snap or Preparation can refund a cooldown. Your own strip is read off your spellbook, so it is exactly the cooldowns you have -- a hybrid build included -- and follows a respec. Everyone else's is learned from the combat log: a talent appears once it has been seen cast, or once their build has shown one tree and only one, and a build that has shown two is not guessed at. The strip's line belongs to the row that can use it: a pet has no cooldown book and holds no line, and neither does anyone whose strip you have switched off — their rows close up rather than keeping an empty band.")
    panel:AddCheckboxPair({
        label = "Show Ability Bar",
        tooltip = "Master switch for the per-player cooldown strips.",
        get = function() return CommanderPartyFramesDB.ShowAbilityBar end,
        set = function(value) CommanderPartyFramesDB.ShowAbilityBar = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Include Your Row",
        tooltip = "Also show the strip under your own row — you know your cooldowns, but under pressure the sanity check is free.",
        get = function() return CommanderPartyFramesDB.AbilityBarSelf end,
        set = function(value) CommanderPartyFramesDB.AbilityBarSelf = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddCheckbox({
        label = "Mine Only",
        tooltip = "Show the strip under YOUR row and nobody else's. The narrowest the ability bar goes without switching it off — the reminder of your own cooldowns, without a wall of everyone else's, and without the line each of theirs took: every other row closes up to a bare row. Needs Include Your Row on, or there would be nothing left to draw.",
        get = function() return CommanderPartyFramesDB.AbilityBarOnlySelf end,
        set = function(value) CommanderPartyFramesDB.AbilityBarOnlySelf = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.ShowAbilityBar
                and CommanderPartyFramesDB.AbilityBarSelf
        end,
    })
    panel:AddSlider({
        label = "Max Ability Icons",
        tooltip = "Most icons per strip; overflow evicts utility first, defensives last.",
        min = 3, max = 8, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.AbilityMaxIcons end,
        set = function(value) CommanderPartyFramesDB.AbilityMaxIcons = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddCheckbox({
        label = "Cooldown Text",
        tooltip = "Show remaining time on cooling icons (hidden under 10s — the sweep carries it).",
        get = function() return CommanderPartyFramesDB.AbilityCdText end,
        set = function(value) CommanderPartyFramesDB.AbilityCdText = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddCheckbox({
        label = "Bar Backdrop",
        tooltip = "Dark panel behind each strip, sized to the icons actually shown — so a short strip leaves no bar hanging under the row, and an empty one draws nothing.",
        get = function() return CommanderPartyFramesDB.AbilityBarBackdrop end,
        set = function(value) CommanderPartyFramesDB.AbilityBarBackdrop = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddButtonRow({
        {
            label = "Tracked Abilities…",
            width = 150,
            tooltip = "Open the tracked-abilities window — a dropdown per class choosing exactly which cooldowns its strip may show (also: /cpf abilities). New options ship unchecked, so the default strip is unchanged until you opt in.",
            onClick = function() CommanderPartyFrames_ToggleAbilityWindow() end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        },
    })
end

-- ...and so is the way a page ends: HUD chrome, then Finalize (which sizes
-- the shared framework's scroll child to whatever was actually built).
local function FinishPanel(panel)
    -- Chrome last, per the suite convention
    local live = CommanderPartyFrames_ScaleKey and CommanderPartyFrames_ScaleKey()
    local function Note(key)
        return key == live and "\n\n|cff66ff66This is the bracket you are in right now.|r" or ""
    end
    Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
        scaleSliders = {
            { key = "HudScaleSmall", label = "Scale: 1-3 Players",
              tooltip = "Size of the board while your group is three or fewer, you included: solo, 2v2 and 3v3." .. Note("HudScaleSmall") },
            { key = "HudScaleParty", label = "Scale: 4-5 Players",
              tooltip = "Size of the board while your group is four or five, you included: 5v5 and a dungeon party." .. Note("HudScaleParty") },
            { key = "HudScaleLarge", label = "Scale: 6+ Players",
              tooltip = "Size of the board while your group is six or more, you included: raids and battlegrounds. Party or raid makes no difference, only the head count." .. Note("HudScaleLarge") },
        },
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

-- What each page says where the pages differ. Everything not in here is
-- identical across all four and lives in the shared builders above.
local LAYER_UI = {
    INT = {
        headerTooltip = "Show your management banner at the top: your armor with time left (a red OFF when you have none) with the click-to-switch popout, your Ice Block / Cold Snap / Evocation / Counterspell / Icy Veins / Presence of Mind / Arcane Power / Combustion / Invisibility / Frost Nova cooldowns, session shield uptime when tracked, team alerts (curses to remove, teammates in CC), and the conjure/consume/settings buttons. Live shield tracking lives on the My Shields rows below the board.",
        selfTooltip = "Add your own row to the board — your Int upkeep and any curses on you, alongside your allies'.",
        petsTooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, curse and CC colors, dispel strip and click-casting every ally row gets, so they can be buffed and healed like anyone else. Mana pets take the mana strip and the Arcane Intellect slot; a pet's portrait stands in for the class icon, and it carries no name — not beside the icon, not on its bar — so every row with a name on it is a player. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort — but a cursed pet still outranks a quiet teammate. They count against Max Rows. Your own Water Elemental is not listed here: it already has its richer row below the board.",
        alertsTooltip = "Hide the quiet rows and keep only the ones that want attention — cursed or CC'd teammates (you always stay visible). No effect in Click-Cast mode (fixed roster order).",
        backdropTooltip = "Dark panel behind the banner across the top of the board, so the icons and text read against it instead of against the world. Independent of the frame's own styled backdrop.",
        maxRowsTooltip = "Most ALLY rows shown at once (most urgent first). Your own rows — the elemental and My Shields — always fit below the cap.",
        widthTooltip = "Overall width of the board — widen until names and numbers sit comfortably.",
        rebuffTooltip = "Treat an ally's Arcane Intellect as due when this much time or less remains — their Int status icon turns amber so you can rebuff before it drops.",
        rangeTooltip = "Dim allies who are out of range, so you only act on the ones you can actually reach.",
        glowLabel = "Action Glow",
        glowTooltip = "Softly glow any row with an open action — a curse to remove, a missing Int, or a rebuff window — so the next cast jumps out.",
        uptimeTooltip = "Track your SHIELD uptime — the share of the session you keep an absorb up on yourself (Mana Shield, Ice Barrier, a priest's bubble). Shown in the banner; detailed by /cpf report.",
        breakLabel = "Shield Broke Flash",
        breakTooltip = "Flash a row red the moment a teammate's LAST shield breaks — that is exactly when the enemy team commits. Also flashes a self-shield row when that shield breaks.",
        breakSoundLabel = "Break Sound",
        breakSoundTooltip = "Also play an alert sound with the flash.",
        iconLabel = "Status Icons",
        iconTooltip = "Show the two team-synergy icons on the left of each row: Arcane Intellect only when it needs you (ghost when missing, amber inside the rebuff window — hidden while healthy) and the ally's biggest shield with a sweep for its remaining time. The row's number is their TOTAL shielding — Power Word: Shield, Ice Barrier, Mana Shield, wards, Sacrifice, whoever cast them.",
        shieldTypesTooltip = "Tint each embedded shield segment by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
        dispelIntro = "A strip of icons to the right of each row showing debuffs you can remove — Curses, purple rim — with a glow on crowd control. Curses also turn the whole row purple, whatever is shown here.",
        dispelShow = "Show, to the right of each ally's row, the Curses you can remove (purple rim, countdown sweep). The CURSED row state works even with this strip off; the strip tells you WHICH curse it is.",
        dispelHealGlow = "Pulse a red glow on debuffs that cut healing received. Worth acting on: absorbs ignore Mortal Strike effects, so a shield lands at full value where a heal does not.",
    },
    HOT = {
        headerTooltip = "Show your upkeep banner at the top: the form you are in (red when it blocks healing — every other piece of advice on this board is unreachable until you shift out), your Innervate / Nature's Swiftness / Rebirth / Barkskin cooldowns, session hot uptime when tracked, team alerts (what you can remove, who is in CC), and the bandage/settings buttons.",
        selfTooltip = "Add your own row to the board — hots you have on yourself, and anything on you that you can remove.",
        petsTooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, curse and poison colors, dispel strip and click-casting every ally row gets, so your hots land on them like anyone else. Mark of the Wild applies whatever a pet runs on, so the buff slot is there even without a mana strip. A pet's portrait stands in for the class icon, and it carries no name — not beside the icon, not on its bar — so every row with a name on it is a player. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort — but a poisoned pet still outranks a quiet teammate. They count against Max Rows.",
        alertsTooltip = "Hide the quiet rows and keep only the ones that want a global — hots about to fall off, hurt allies carrying none, and anyone cursed, poisoned or in CC (you always stay visible). No effect in Click-Cast mode (fixed roster order).",
        backdropTooltip = "Dark panel behind the banner across the top of the board, so the icons and text read against it instead of against the world. Independent of the frame's own styled backdrop.",
        maxRowsTooltip = "Most ally rows shown at once (most urgent first).",
        widthTooltip = "Overall width of the board — widen until the hot strip, names and numbers sit comfortably.",
        rebuffTooltip = "Treat an ally's Mark of the Wild as due when this much time or less remains — their status icon turns amber so you can rebuff before it drops.",
        rangeTooltip = "Dim allies who are out of range, so you only act on the ones you can actually reach.",
        glowLabel = "Action Glow",
        glowTooltip = "Softly glow any row with an open action — something to remove, a hot to start or refresh, or a missing Mark — so the next global jumps out.",
        uptimeTooltip = "Track your HOT uptime — the share of the session your living teammates were carrying at least one hot of yours. Shown in the banner; detailed by /cpf report.",
        breakLabel = "Shield Broke Flash",
        breakTooltip = "Flash a row red the moment a teammate's LAST absorb breaks — that is exactly when the enemy team commits, and on this board it is the cue to pre-hot before the damage lands.",
        breakSoundLabel = "Break Sound",
        breakSoundTooltip = "Also play an alert sound with the flash.",
        iconLabel = "Status Icons",
        iconTooltip = "Show the left status slot and the hot strip beside it. The status slot carries Mark of the Wild only when it needs you — ghost when missing, amber inside the rebuff window, hidden while healthy — and unlike Arcane Intellect it applies to your rage and energy allies too.",
        shieldTypesTooltip = "Tint each absorb embedded in an ally's health bar by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
        dispelIntro = "A strip of icons to the right of each row showing debuffs you can remove — Curses with a purple rim, Poisons with a green one — and a glow on crowd control. Both schools also color the whole row, whatever is shown here.",
        dispelShow = "Show, to the right of each ally's row, the Curses and Poisons you can remove (rim colored by school, countdown sweep). The CURSED and POISONED row states work even with this strip off; the strip tells you WHICH debuff it is.",
        dispelHealGlow = "Red pulse on debuffs that cut healing received (Mortal Strike, Wound Poison). On a hot board that is the cue to stop topping and start pre-hotting through it.",
    },
    BLESS = {
        headerTooltip = "Show your upkeep banner at the top: the aura you are running and the seal you are holding (both red when you have none — a paladin is always meant to be running both, and both are click-to-switch), your Lay on Hands / bubble / Protection / Freedom / Sacrifice / wings cooldowns, session blessing uptime when tracked, team alerts (what you can cleanse, who is in CC), and the bandage/settings buttons.",
        selfTooltip = "Add your own row to the board — the blessing you have on yourself, your own Forbearance, and anything on you that you can cleanse.",
        petsTooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, magic and poison colors, dispel strip and click-casting every ally row gets, so a Freedom or a blessing lands on them like anyone else. Blessing of Might applies to anything that swings, so a pet keeps that slot even without a mana strip. A pet's portrait stands in for the class icon, and it carries no name — not beside the icon, not on its bar — so every row with a name on it is a player. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort — but a poisoned pet still outranks a quiet teammate. They count against Max Rows.",
        alertsTooltip = "Hide the quiet rows and keep only the ones that want a global — allies with none of your blessings, blessings about to fall off, and anyone with something you can cleanse or in CC (you always stay visible). No effect in Click-Cast mode (fixed roster order).",
        backdropTooltip = "Dark panel behind the banner across the top of the board, so the icons and text read against it instead of against the world. Independent of the frame's own styled backdrop.",
        maxRowsTooltip = "Most ally rows shown at once (most urgent first).",
        widthTooltip = "Overall width of the board — widen until the blessing slot, names and numbers sit comfortably.",
        rebuffTooltip = "Treat an ally's upkeep blessing as due when this much time or less remains — its slot turns amber so you can rebless before it drops. Greater blessings run thirty minutes and singles ten, so this is the one number that decides how often the slot asks you for anything. Freedom, Protection and Sacrifice have their own window in seconds, under Emergency Blessings below.",
        rangeTooltip = "Dim allies who are out of range, so you only act on the ones you can actually reach.",
        glowLabel = "Action Glow",
        glowTooltip = "Softly glow any row with an open action — something to cleanse, a blessing to give or rebless — so the next global jumps out.",
        uptimeTooltip = "Track your BLESSING uptime — the share of the session your living teammates were carrying a blessing of yours, Freedom, Protection and Sacrifice included (for the ten seconds a Protection is on them, they are blessed — that is what a Protection is on this client). Shown in the banner; detailed by /cpf report.",
        breakLabel = "Shield Broke Flash",
        breakTooltip = "Flash a row red the moment a teammate's LAST absorb breaks — that is exactly when the enemy team commits, and on this board it is the cue to have a Protection ready before the damage lands.",
        breakSoundLabel = "Break Sound",
        breakSoundTooltip = "Also play an alert sound with the flash.",
        iconLabel = "Status Icons",
        iconTooltip = "Show the blessing slot. Each ally gets ONE, and it shows whichever blessing of yours is on them right now with its remaining time on the sweep — Kings with its minutes, or the Protection you just spent on them with its seconds, because on this client Protection, Freedom and Sacrifice are blessings and take the same slot. Amber means rebless: inside the rebuff window, or carrying a different upkeep blessing of yours than the one you assigned them. When none of yours is on them the slot shows the assigned blessing ghosted (set it under Blessings below, or click the slot itself out of combat), dark-red when the advisor says that absence is costing you. Only blessings YOU cast count, so another paladin's Kings never makes a naked ally look handled.",
        shieldTypesTooltip = "Tint each absorb embedded in an ally's health bar by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
        dispelIntro = "A strip of icons to the right of each row showing debuffs you can remove — a paladin cleanses Magic, Poison and Disease, which is more schools than anyone else on this board — and a glow on crowd control. A removable debuff also colors the whole row, whatever is shown here.",
        dispelShow = "Show, to the right of each ally's row, the Magic, Poison and Disease debuffs you can cleanse (rim colored by school, countdown sweep). The row states work even with this strip off; the strip tells you WHICH debuff it is.",
        dispelHealGlow = "Red pulse on debuffs that cut healing received (Mortal Strike, Wound Poison). On a paladin board that is the cue to stop trading Flash of Light against it and spend a cooldown instead.",
    },
    PWS = {
        headerTooltip = "Show your upkeep banner at the top: Inner Fire (red when it has fallen off), your Power Word: Shield cooldown — or its current absorb estimate once it is back — your Pain Suppression / Power Infusion / Fear Ward / Psychic Scream / Silence / Inner Focus / Shadowfiend / Mass Dispel / Desperate Prayer cooldowns, session shield uptime when tracked, team alerts (what you can dispel, who is in CC), and the bandage/settings buttons.",
        selfTooltip = "Add your own row to the board — track your own shield and Weakened Soul alongside your allies'.",
        petsTooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, Weakened Soul lockout, dispel strip and click-casting every ally row gets, so a pet can be shielded and healed like anyone else. A pet's portrait stands in for the class icon, and it carries no name — not beside the icon, not on its bar — so every row with a name on it is a player. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort. They count against Max Rows.",
        alertsTooltip = "Hide the healthy rows and keep only the ones that want a decision: exposed, expiring, or ready to shield. No effect in Click-Cast mode (fixed roster order).",
        backdropTooltip = "Dark panel behind the strip across the top of the board, so the cooldown and shield value read against it instead of against the world. Independent of the frame's own styled backdrop.",
        maxRowsTooltip = "Most rows shown at once (most urgent first).",
        widthTooltip = "Overall width of the board — widen until names and numbers sit comfortably.",
        rebuffTooltip = "Treat an ally buff as due when this much time or less remains — its slot turns amber so you can recast before it drops. Fortitude and Divine Spirit both run thirty minutes, so this is the number that decides how often the strip asks you for anything.",
        lowShield = true,
        rangeTooltip = "Dim allies who are out of your shield range, so you only act on the ones you can actually reach. (Each row's bar is the ally's health with their absorbs embedded — always on.)",
        glowLabel = "Reshield Glow",
        glowTooltip = "Softly glow any row whose reshield window is open — no shield and no Weakened Soul (or a low shield you can top off) — so the next cast jumps out.",
        uptimeTooltip = "Track how much of your group is carrying your shield over the session (shown in the header, detailed by /cpf report).",
        breakLabel = "Expose Alert",
        breakTooltip = "Flash a row red the moment your shield breaks off a living ally — they need a reshield now.",
        breakSoundLabel = "Expose Sound",
        breakSoundTooltip = "Also play an alert sound with the expose flash.",
        iconLabel = "Spell Icon",
        iconTooltip = "Show the Power Word: Shield icon at the start of each row (dimmed when no shield of yours is up).",
        shieldTypesTooltip = "Tint each embedded shield segment by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
        -- The absorb board is the only one whose status slot is a single
        -- icon with a duration of its own to draw.
        shieldSwipe = true,
        dispelIntro = "A strip of icons to the right of each row showing debuffs you can remove — a priest dispels Magic and Disease — color-coded by school, with a glow on crowd control. A removable debuff also colors the whole row, and a teammate in crowd control turns it orange.",
        dispelShow = "Show, to the right of each ally's row, the debuffs your class can actually dispel — Priests see Magic and Disease, Paladins Magic/Poison/Disease, Druids Curse/Poison, Mages Curse, Shamans Poison/Disease. Each icon's rim is colored by school (blue Magic, purple Curse, brown Disease, green Poison) and carries a countdown sweep.",
        dispelHealGlow = "Pulse a red glow on debuffs that cut healing received. Worth acting on: absorbs ignore Mortal Strike effects, so a shield lands at full value where a heal does not.",
    },
}

-- The dispellable-debuff strip. Same controls on every page — only the
-- wording changes with what the class can actually take off — but they had
-- drifted into four different subsets of one section. Two settings the
-- engine reads on EVERY layer had no control at all on some pages: Show All
-- Debuffs existed only for priests, and the heal-reduction glow only for
-- everyone but mages. This is the superset, so every board can reach every
-- setting it is already subject to.
local function AddDispelSection(panel, ui)
    panel:AddSection("Dispellable Debuffs", ui.dispelIntro)
    panel:AddCheckboxPair({
        label = "Show Dispellable Debuffs",
        tooltip = ui.dispelShow,
        get = function() return CommanderPartyFramesDB.ShowDispels end,
        set = function(value) CommanderPartyFramesDB.ShowDispels = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "CC Glow",
        tooltip = "Pulse a bright glow behind crowd-control debuffs (Polymorph, Fear, Sap-likes, roots, stuns, Mind Control...) so the one that needs dispelling first jumps out of a busy strip.",
        get = function() return CommanderPartyFramesDB.DispelCCGlow end,
        set = function(value) CommanderPartyFramesDB.DispelCCGlow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    })
    panel:AddCheckboxPair({
        label = "Important Debuffs",
        tooltip = "Also show debuffs that matter to a healer even though you cannot dispel them: healing reductions (Mortal Strike, Aimed Shot, Wound Poison), undispellable crowd control and stuns (Blind, Sap, Gouge, Kidney Shot, Cyclone, Intimidating Shout...), and silences. These get a category-colored rim — red for healing reduction, orange for crowd control — and are sorted to the front of the strip. Immunities ride along too: Ice Block and Divine Shield are buffs, not debuffs, but they answer whether to heal the row at all, so they take the first slot with an ice-blue rim.",
        get = function() return CommanderPartyFramesDB.DispelShowImportant end,
        set = function(value) CommanderPartyFramesDB.DispelShowImportant = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    }, {
        label = "Heal-Reduction Glow",
        tooltip = ui.dispelHealGlow,
        get = function() return CommanderPartyFramesDB.DispelHealGlow end,
        set = function(value) CommanderPartyFramesDB.DispelHealGlow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels
            and CommanderPartyFramesDB.DispelShowImportant end,
    })
    panel:AddCheckboxPair({
        label = "Show All Debuffs",
        tooltip = "Also show debuffs you cannot dispel. Off (default) keeps the strip strictly actionable — only what you can actually remove. Sated and Exhaustion, the ten minutes after a Bloodlust or Heroism, never show either way: they sit on every row at once and there is nothing to do about them.",
        get = function() return CommanderPartyFramesDB.DispelShowAll end,
        set = function(value) CommanderPartyFramesDB.DispelShowAll = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    }, {
        label = "Duration Sweep",
        tooltip = "Draw a radial countdown over each debuff icon showing how long it has left.",
        get = function() return CommanderPartyFramesDB.DispelSweep end,
        set = function(value) CommanderPartyFramesDB.DispelSweep = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    })
    panel:AddSliderPair({
        label = "Debuff Icons",
        tooltip = "How many debuff icons to show per row. The strip grows rightward outside the frame, so a long one takes screen space, not board width.",
        min = 1, max = 16, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.DispelMaxIcons end,
        set = function(value) CommanderPartyFramesDB.DispelMaxIcons = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    }, {
        label = "Debuff Icon Size",
        tooltip = "Size of each debuff icon in the strip.",
        min = 10, max = 24, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.DispelIconSize end,
        set = function(value) CommanderPartyFramesDB.DispelIconSize = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    })

end

-- Identity, icons and bar art. The same section on every page — only the
-- status-slot wording changes with what the class actually keeps there,
-- and only the priest board has a second toggle to pair with it.
-- The bar's left span. It is the ally's name until the row has a state word
-- to put there — MAGIC, BLESS, a CC's name, the seconds left on a hot — and
-- for most of the board's life every word simply won. Some people read a
-- board by names and want the span to stay theirs; more people want SOME of
-- the words (a MAGIC you can cleanse is worth the name; "24m" is not), so
-- each kind has a switch of its own under the master. One section on every
-- page: the kinds are chassis, and which of them a given board can produce is
-- said in each tooltip rather than by hiding the switch.
local function AddBarTextSection(panel)
    panel:AddSection("Bar Text", "What the left of each ally's health bar says. It is their name in class colour whenever the row has nothing else to say there, and a state word — MAGIC, BLESS, a crowd control's name, the seconds left on your hot — when it does. Pick which kinds of word are allowed to take the name's place, or keep the name always: the stripe colour, the icons and the sort keep saying everything the words did.")
    panel:AddCheckbox({
        label = "Always the Name",
        tooltip = "The span is always the ally's name, whatever the row is doing. Every switch below goes quiet while this is on. The row still changes colour, still sorts up, still ghosts and reddens its icons — this only decides what the text says. Your own self-spell rows are not affected: their text is the row.",
        get = function() return CommanderPartyFramesDB.BarTextAlwaysName end,
        set = function(value) CommanderPartyFramesDB.BarTextAlwaysName = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    local function live() return CommanderPartyFramesDB.EnableShield and not CommanderPartyFramesDB.BarTextAlwaysName end
    panel:AddCheckboxPair({
        label = "Removable Debuffs",
        tooltip = "MAGIC, CURSED, POISON or DISEASE — something on them YOU can take off. The loudest word the board has, on every layer. Off, the row still turns that school's colour; only the word goes.",
        get = function() return CommanderPartyFramesDB.BarTextDispel end,
        set = function(value) CommanderPartyFramesDB.BarTextDispel = value end,
        isEnabled = live,
    }, {
        label = "Crowd Control",
        tooltip = "The name of the crowd control an ally is sitting in (Polymorph, Fear, Sap...), trimmed to ten letters. Every layer. Off, the row still goes orange and the dispel strip still glows; only the word goes.",
        get = function() return CommanderPartyFramesDB.BarTextCC end,
        set = function(value) CommanderPartyFramesDB.BarTextCC = value end,
        isEnabled = live,
    })
    panel:AddCheckboxPair({
        label = "What To Cast",
        tooltip = "BLESS on the paladin board (an ally with none of your blessings) and HOT on the druid board (a hurt ally with none of your hots). The priest and mage boards have no word of this kind — a shieldless ally already says so by their ghosted icon. Off, the row still pulses yellow and sorts up; only the word goes.",
        get = function() return CommanderPartyFramesDB.BarTextAsk end,
        set = function(value) CommanderPartyFramesDB.BarTextAsk = value end,
        isEnabled = live,
    }, {
        label = "Lockouts",
        tooltip = "EXPOSED (a Weakened Soul you cannot shield through) and SHIELDED* (another priest's shield on them) on the priest board. The other boards have no word of this kind. Off, the row keeps its red stripe and the drain under the bar; only the word goes.",
        get = function() return CommanderPartyFramesDB.BarTextLock end,
        set = function(value) CommanderPartyFramesDB.BarTextLock = value end,
        isEnabled = live,
    })
    panel:AddCheckboxPair({
        label = "Numbers",
        tooltip = "Every number the span can carry: what is left of your shield on the priest board and UP when it has no readable size, an ally's total absorbs on the mage board, the seconds left on your soonest hot on the druid board, the minutes or seconds left on your blessing on the paladin board. The sweeps on the icons carry the same clocks, which is why this is the one most people turn off.",
        get = function() return CommanderPartyFramesDB.BarTextNumber end,
        set = function(value) CommanderPartyFramesDB.BarTextNumber = value end,
        isEnabled = live,
    }, {
        label = "Dead & Offline",
        tooltip = "DEAD and OFFLINE, on every layer. Off, the row still greys out; only the word goes.",
        get = function() return CommanderPartyFramesDB.BarTextDead end,
        set = function(value) CommanderPartyFramesDB.BarTextDead = value end,
        isEnabled = live,
    })
end

local function AddIdentitySection(panel, ui)
    panel:AddSection("Identity & Icons")
    panel:AddDropdownPair({
        label = "Show Unit As",
        tooltip = "How each ally is labelled. Class Icon is the most compact (no name); Portrait shows their 2D model (class icon when off-screen); Name is text only; Icon + Name shows icon and name; Icon + Portrait shows the class icon beside the live portrait; the Specialization modes swap in the talent-tree icon once a player's spec has been learned from their casts (class icon until then).",
        options = {
            { text = "Class Icon", value = "CLASS_ICON" },
            { text = "Portrait", value = "PORTRAIT" },
            { text = "Name", value = "NAME" },
            { text = "Icon + Name", value = "ICON_NAME" },
            { text = "Icon + Portrait", value = "ICON_PORTRAIT" },
            { text = "Specialization", value = "SPEC" },
            { text = "Spec + Portrait", value = "SPEC_PORTRAIT" },
        },
        get = function() return CommanderPartyFramesDB.UnitDisplay end,
        set = function(value) CommanderPartyFramesDB.UnitDisplay = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Grow",
        tooltip = "Direction the board grows from its anchor.",
        options = {
            { text = "Down", value = "DOWN" },
            { text = "Up", value = "UP" },
        },
        get = function() return CommanderPartyFramesDB.Grow end,
        set = function(value) CommanderPartyFramesDB.Grow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    -- The icon toggle, and — on the priest board only — the shield's duration
    -- sweep beside it. Every other layer's status slot is a strip whose slots
    -- carry their own sweeps, so there is nothing for a second toggle to do.
    local iconToggle = {
        label = ui.iconLabel,
        tooltip = ui.iconTooltip,
        get = function() return CommanderPartyFramesDB.ShowSpellIcon end,
        set = function(value) CommanderPartyFramesDB.ShowSpellIcon = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }
    if ui.shieldSwipe then
        panel:AddCheckboxPair(iconToggle, {
            label = "Shield Duration Sweep",
            tooltip = "Draw a radial 30-second sweep over the spell icon showing the shield's remaining duration. Requires Spell Icon.",
            get = function() return CommanderPartyFramesDB.ShieldSwipe end,
            set = function(value) CommanderPartyFramesDB.ShieldSwipe = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowSpellIcon end,
        })
        panel:AddCheckbox({
            label = "Reshield Ring",
            tooltip = "Draw the wait before you can shield this ally again around the spell icon's own border — their Weakened Soul, and the spell's cooldown if this client ever gives it one, whichever is longer. It drains clockwise like every other lockout on this board, so an empty border means cast it now.\n\nIt is on the border because the icon's face is already busy: the sweep behind it is the shield's own thirty seconds. Two clocks, one icon, no width taken from the health bar — and the answer to \"can I bubble them\" stops being three pixels tall under the bar, competing with everything else down there.",
            get = function() return CommanderPartyFramesDB.ShieldLockRing end,
            set = function(value) CommanderPartyFramesDB.ShieldLockRing = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowSpellIcon end,
        })
    else
        panel:AddCheckbox(iconToggle)
    end
    panel:AddCheckboxPair({
        label = "NPC Target Counter",
        tooltip = "Show, over each unit's class icon or portrait, how many enemy NPCs are currently targeting them — white 1, amber 2, red 3+. Reads the visible enemy nameplates, so turn enemy nameplates on (default V) for full coverage; needs an icon to sit on, so it hides in Name-only display.",
        get = function() return CommanderPartyFramesDB.ShowTargeters end,
        set = function(value) CommanderPartyFramesDB.ShowTargeters = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.UnitDisplay ~= "NAME"
        end,
    }, {
        label = "Target Marks",
        tooltip = "Show, at each row's right edge, the raid mark of the unit that ally is CURRENTLY targeting — watch your tank hold skull (or drift off it), and pair with the Assist click binding to jump onto their target.\n\nHolds a 16-pixel seat to the right of the health bar whether or not a mark is up, so the bar never twitches mid-fight; off, the bar takes that width.",
        get = function() return CommanderPartyFramesDB.ShowTargetMarks end,
        set = function(value) CommanderPartyFramesDB.ShowTargetMarks = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckbox({
        label = "Combat Marks",
        tooltip = "Mark every ally who is IN COMBAT with the game's own crossed-swords icon — the one your portrait lights on every pull — at their row's right edge — dimmed when they are fighting out of your casting range.\n\nIt is a mark you use in two directions. An ally already fighting is combat you can take: one heal on them and you are in combat too, and a Sap does not open on a target in combat. And a board with no blades left on it is the one that says sit down — nobody here is still fighting, so the drink will finish.\n\nOnly ever marks the ones who ARE fighting. An ally far enough out that your client is not tracking their unit reports no combat at all, so a drawn \"out of combat\" would be a claim this cannot honestly make — an empty slot means \"nothing seen\", and your own row is always exact.\n\nSeparate from Only In Combat, which is about whether the board is on screen at all.",
        get = function() return CommanderPartyFramesDB.ShowCombat end,
        set = function(value) CommanderPartyFramesDB.ShowCombat = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckbox({
        label = "Battleground Marks",
        tooltip = "In a battleground, mark every ally who is CARRYING THE FLAG or holding one of the ground powerups, beside the combat mark at their row's right edge — same size, same corner, read the same way.\n\nWhat it is for: on a battleground board the question stops being \"who is hurt\" and becomes \"which of these ten people are the next thirty seconds about\". The flag carrier is a healing target with a different price on it than anyone else on the row list, and the powerup they just picked up changes that price again — a carrier on Berserking is taking 10% more damage while dealing 30% more, and one on Restoration is getting healing you do not have to spend a global on.\n\nTwo slots per row, best first, and the flag always takes the first one: a carrier with Berserking up is still, first, the carrier. Below it the powerups rank by how much they change what you would do next — Berserking, then Restoration, then Speed.\n\nThe slots are held open only INSIDE a battleground. Every other mark on this row reserves its width from the setting so the health bar cannot twitch mid-fight, but these auras cannot exist in an arena or a raid, and a permanent hole for a mark that can never light is width the bar should keep. Zoning is the only thing that moves them, and zoning happens out of combat.\n\nLike the combat mark it is a positive claim only, dimmed when they are out of your casting range. An ally too far out for your client to read auras from wears the last thing you saw on them rather than losing it — which is the point, since a carrier running for the tunnel is exactly who you stop being able to see.",
        get = function() return CommanderPartyFramesDB.ShowBGBuffs end,
        set = function(value) CommanderPartyFramesDB.ShowBGBuffs = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddDropdown({
        label = "Mark Layout",
        tooltip = "How the marks above sit to the right of the health bar.\n\nSTACKED puts every mark into ONE seat: a two-by-two block where each cell always means the same thing -- their target's raid mark top-left, the crossed swords top-right, the flag bottom-left, the powerup bottom-right. Four marks at once still read at a glance, because which cell is lit says what it is before the icon does, and the seat costs 21 pixels instead of the 64 a row of seats did.\n\nSIDE BY SIDE is the older layout: one seat per mark in a line, the battleground pair only inside a battleground.\n\nThe diagram at the top of the page redraws for either.",
        options = {
            { text = "Stacked (one 2x2 seat)", value = "GRID" },
            { text = "Side by side", value = "ROW" },
        },
        width = 180,
        get = function() return CommanderPartyFramesDB.MarkLayout end,
        set = function(value) CommanderPartyFramesDB.MarkLayout = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckbox({
        label = "Color Shield Types",
        tooltip = ui.shieldTypesTooltip,
        get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
        set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddDropdown(BAR_TEXTURE_OPTION)
    panel:AddDropdown(ICON_STYLE_OPTION)
    -- The power strip sits with the bar art rather than with the decision
    -- aids: it is part of what a row LOOKS like, and unlike everything in
    -- Decision Aids it is the same control on all four boards.
    panel:AddDropdownPair(POWER_BAR_OPTION, POWER_COLOR_OPTION)
    panel:AddSlider({
        label = "Power Bar Height",
        tooltip = "How tall the power strip is, in pixels. The row does not grow with it — the bars are centred in a fixed row height, so a taller strip eats padding rather than costing you a row.",
        min = 2, max = 7, step = 1,
        format = function(value) return string.format("%dpx", value or 0) end,
        get = function() return CommanderPartyFramesDB.PowerBarHeight end,
        set = function(value) CommanderPartyFramesDB.PowerBarHeight = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.PowerBar ~= "OFF"
        end,
    })
    panel:AddCheckbox(SWEEP_EDGE_OPTION)
    panel:AddSlider({
        label = "Name Length",
        tooltip = "Trim ally names to this many characters (keeps rows compact). Applies when Show Unit As includes a name.",
        min = 3, max = 12, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.NameMaxChars end,
        set = function(value) CommanderPartyFramesDB.NameMaxChars = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and (CommanderPartyFramesDB.UnitDisplay == "NAME" or CommanderPartyFramesDB.UnitDisplay == "ICON_NAME")
        end,
    })
    AddBarTextSection(panel)
    panel:AddSection("Burst", "An ally's damage cooldown, worn by their whole row. When a mage pops Arcane Power the row takes a violet edge and a faint violet wash: a flare on the pop, a slow pulse while it runs, and a wash that thins as the seconds run out. No icon and no word — it is meant for the corner of your eye, so you know whose fifteen seconds this is before the Pyroblast lands.")
    panel:AddCheckbox({
        label = "Arcane Power Edge",
        tooltip = "Violet outline and wash on a row for as long as that ally's Arcane Power runs. Every layer. Off, the row looks the same as any other while they burst.",
        get = function() return CommanderPartyFramesDB.BurstGlow end,
        set = function(value) CommanderPartyFramesDB.BurstGlow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
end

-- The forecast: pending dot damage, rolling hot healing, and a heal in the
-- air. One section, identical on all four boards, because the three questions
-- mean exactly the same thing whatever you cast — the mage wants to know a
-- teammate is already handled before spending a Remove Curse global on them
-- for the same reason the priest wants to know before spending a Greater Heal.
--
-- The whole point of this section is that the RIGHT shape is a matter of
-- taste and of how busy your board already is, so all five are here rather
-- than one opinionated default: paint it on the bar, reduce it to hairlines,
-- spell it out in numbers, do both, or turn it off.
local FORECAST_MODE_OPTION = {
    label = "Show Forecast As",
    tooltip = "How the pending damage and healing are drawn.\n\nBar Overlay paints them onto the health bar itself: healing as a translucent ghost continuing past the fill (where they are heading), damage as a dark shade eating back into it (the part of their green that is already spoken for). Nothing costs the row any width and both read at a glance — the right default for most boards.\n\nTicks reduces the same two answers to hairlines at the projected health, keeping the bar's own colors uncluttered. The quietest option that still answers the question.\n\nNumbers puts the figures on the bar's centre instead — green for what is coming in, red for what is going out. Slower to read than a bar but exact, and the only mode that survives a very short bar.\n\nBoth is the overlay with the numbers on top.",
    options = {
        { text = "Bar Overlay", value = "BAR" },
        { text = "Ticks", value = "TICK" },
        { text = "Numbers", value = "TEXT" },
        { text = "Overlay + Numbers", value = "BOTH" },
        { text = "Off", value = "OFF" },
    },
    get = function() return CommanderPartyFramesDB.Forecast end,
    set = function(value) CommanderPartyFramesDB.Forecast = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

local function ForecastOn()
    return CommanderPartyFramesDB.EnableShield
        and CommanderPartyFramesDB.Forecast ~= "OFF"
end

local function AddForecastSection(panel, ui)
    panel:AddSection("Damage & Healing Forecast",
        "What is already on its way to an ally, before any of it lands: damage still queued in the dots ticking on them, healing still rolling from hots, and a heal in the air from anyone in the group — you included. A teammate at 40% with a full Corruption on him is not a teammate at 40%, and one at 55% with two hots and an inbound Greater Heal does not need your global at all.\n\nTBC exposes none of this, so it is LEARNED from the combat log: every tick and every completed heal arrives with its exact amount, which already includes gear, talents and resistances. A spell nobody has watched tick yet is worth nothing until its first tick lands — usually the first second of a fight.")
    panel:AddDropdown(FORECAST_MODE_OPTION)
    panel:AddCheckboxPair({
        label = "Pending Dot Damage",
        tooltip = "Count the damage still queued in every dot ticking on an ally — ticks remaining times what that dot has actually been hitting them for. This is the read that stops a teammate dying at what looked like a safe percentage.",
        get = function() return CommanderPartyFramesDB.ForecastDots end,
        set = function(value) CommanderPartyFramesDB.ForecastDots = value end,
        isEnabled = ForecastOn,
    }, {
        label = "Pending Hot Healing",
        tooltip = "Count the healing still rolling from hots on an ally — Renew, Rejuvenation, Regrowth, Lifebloom. ANY caster's, not just yours: their other healer's Renew is exactly as good a reason not to spend your global as your own.",
        get = function() return CommanderPartyFramesDB.ForecastHots end,
        set = function(value) CommanderPartyFramesDB.ForecastHots = value end,
        isEnabled = ForecastOn,
    })
    panel:AddCheckboxPair({
        label = "Inbound Cast Heals",
        tooltip = "Count a heal that a group member — you included — is part way through casting, so two healers stop landing on the same target.\n\nOne caveat worth knowing: the client will not say who another player is casting AT, so the target is read the way the game itself resolves one — their current target if it is friendly, themselves if it is not. That is exactly right for a healer playing off their target frame and wrong for one playing off mouseover or click-casting, and there is no way around it from inside an addon. A heal whose size has never been seen land still shows as an inbound +? rather than a number.",
        get = function() return CommanderPartyFramesDB.ForecastCasts end,
        set = function(value) CommanderPartyFramesDB.ForecastCasts = value end,
        isEnabled = ForecastOn,
    }, {
        label = "Net Only",
        tooltip = "Collapse the two into one figure — healing minus damage — so the row shows only which way the ally is actually heading. One ghost, or one signed number, instead of two answers pointing at each other. Quieter, at the cost of not being able to see that a big heal and a big dot are cancelling out.",
        get = function() return CommanderPartyFramesDB.ForecastNet end,
        set = function(value) CommanderPartyFramesDB.ForecastNet = value end,
        isEnabled = ForecastOn,
    })
    panel:AddSliderPair({
        label = "Look Ahead",
        tooltip = "Only count what lands within this many seconds. This is the setting that makes the forecast usable rather than merely true: a full Curse of Agony is most of two thousand damage over twenty-four seconds, and almost none of that is a reason to do anything right now. Capping it at the next few seconds turns \"what will eventually happen\" into \"what happens before my next global matters\". Set to 0 to count each aura's whole remaining duration.",
        min = 0, max = 15, step = 1,
        format = function(value)
            if (value or 0) <= 0 then return "Full" end
            return string.format("%ds", value)
        end,
        get = function() return CommanderPartyFramesDB.ForecastWindow end,
        set = function(value) CommanderPartyFramesDB.ForecastWindow = value end,
        isEnabled = ForecastOn,
    }, {
        label = "Noise Floor",
        tooltip = "Ignore any forecast smaller than this share of the ally's own MAX health. A share rather than a flat number, because two hundred points is a rounding error on a warrior and a real read on a mage. Raise it until only the amounts you would actually act on survive.",
        min = 0, max = 15, step = 1,
        format = function(value) return string.format("%d%%", value or 0) end,
        get = function() return CommanderPartyFramesDB.ForecastMinPct end,
        set = function(value) CommanderPartyFramesDB.ForecastMinPct = value end,
        isEnabled = ForecastOn,
    })
    panel:AddCheckbox({
        label = "Itemise In Tooltip",
        tooltip = "List the working in each row's tooltip — which dot, which hot, whose cast, how many ticks are left and what each is worth. The bar answers how much; this answers because of what, which is the half you want when a read looks wrong.",
        get = function() return CommanderPartyFramesDB.ForecastTooltip end,
        set = function(value) CommanderPartyFramesDB.ForecastTooltip = value end,
        isEnabled = ForecastOn,
    })
end

-- Mouseover and click-casting. Identical on all four pages — the bindings
-- themselves are per-layer (they live in the profile store, not here), but
-- the CONTROLS over them never differed by a character. It was four
-- byte-identical copies until this was extracted, which is the exact shape
-- that has already put three settings on some pages and not others (see the
-- note at the top of Harness/settings_reach.py).
local function AddClickSection(panel)
    panel:AddSection("Mouseover & Click", "Every modifier and button the client delivers. Click a cell to bind it, right-click to clear. Besides spells, a cell can target the ally, assist them, or point the Commander Orders arrow at them (Arrow to them: it follows them as they move; /cpf arrow and the key binding Arrow to My Target do the same for your target on any board). Enabling needs a /reload and fixes the roster order.")
    panel:AddCheckbox({
        label = "Enable Row Clicks",
        tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each bound click casts its spell. Because secure frames cannot change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
        get = function() return CommanderPartyFramesDB.ClickCast end,
        set = function(value) CommanderPartyFramesDB.ClickCast = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddDropdown({
        label = "Binding Profile",
        tooltip = "Which set of bindings is live. Follow Talent Build keys them to the tree you have most points in, so respeccing from your arena build to your PvE one brings back the bindings you left for it — this is a TBC client, so the talent build is what stands in for dual spec. Single Set keeps one profile whatever you respec into.",
        options = {
            { text = "Follow Talent Build", value = "TALENT" },
            { text = "Single Set", value = "FIXED" },
        },
        get = function() return CommanderPartyFramesDB.ClickProfileMode end,
        set = function(value)
            CommanderPartyFramesDB.ClickProfileMode = value
            if value == "FIXED" and (CommanderPartyFramesDB.ClickProfileFixed or "") == "" then
                CommanderPartyFramesDB.ClickProfileFixed =
                    CommanderPartyFrames_ActiveProfile and CommanderPartyFrames_ActiveProfile() or ""
            end
        end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end,
    })
    panel:AddDropdown({
        label = "Row Tooltip",
        tooltip = "What hovering a row shows. This is the click-cast board's tooltip only: it has never existed on the sorted board, and it is entirely separate from what makes @mouseover macros work — that is the row's unit attribute, which every option here leaves alone. Your macros keep working whichever you pick.\n\nUnit + Board Notes is the game's own unit tooltip with the board's extra lines under it. Board Notes Only drops the unit half — the name, level, health and buff list a party frame is already telling you — and keeps just what the board itself has to add, such as the forecast's breakdown of which dot and which hot make up the pending numbers. It shows nothing at all when the board has nothing to add, so a quiet row stays quiet. Off means hovering a row does nothing.\n\nThe ability strip's cells and the paladin's blessing slot keep their own tooltips whichever you pick: those explain a control you can click rather than describing a unit. Inside an arena none of them show at all while Hide Tooltips In Arena, under Board, is on.",
        options = {
            { text = "Unit + Board Notes", value = "FULL" },
            { text = "Board Notes Only", value = "EXTRAS" },
            { text = "Off", value = "OFF" },
        },
        get = function() return CommanderPartyFramesDB.RowTooltip end,
        set = function(value) CommanderPartyFramesDB.RowTooltip = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end,
    })
    panel:AddCheckbox({
        label = "Ratings In Board Notes",
        tooltip = "End Board Notes Only with the ally's arena ratings, from Commander Muster. That line is enough on its own to open the tooltip, so once Muster knows your group's ratings — and with the Ladder feed it knows most rated players on the realm — every row you cross shows one. Off by default, which keeps a quiet row quiet.\n\nUnit + Board Notes is the game's own unit tooltip, and Muster adds its ratings line there itself; this setting does not reach it.",
        get = function() return CommanderPartyFramesDB.RowTooltipRatings end,
        set = function(value) CommanderPartyFramesDB.RowTooltipRatings = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast
                and CommanderPartyFramesDB.RowTooltip == "EXTRAS"
        end,
    })
    AddClickMatrix(panel)
end

-- Decision aids. Every layer offers the same five, and every layer means
-- something different by them — a mage's action glow is a curse to remove,
-- a paladin's is a blessing to give — so this is the section where LAYER_UI
-- carries the most wording. Its shape is now identical on all four boards:
-- the one control that used to differ, the mana strip, became the power
-- strip and moved up to Identity & Icons where the rest of the bar art is.
local function AddDecisionAids(panel, ui)
        panel:AddSection("Decision Aids")
        panel:AddCheckbox({
            label = "Range Fade",
            tooltip = ui.rangeTooltip,
            get = function() return CommanderPartyFramesDB.RangeFade end,
            set = function(value) CommanderPartyFramesDB.RangeFade = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Range Fade Strength",
            tooltip = "How far an out-of-range ally's row dims. Low keeps them nearly as readable as everyone else; high all but hides them. The default, 60%, leaves the row at 40% opacity.",
            min = 0.1, max = 0.9, step = 0.05,
            format = Commander.UI.FormatPercent,
            get = function() return CommanderPartyFramesDB.RangeFadeStrength end,
            set = function(value) CommanderPartyFramesDB.RangeFadeStrength = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.RangeFade end,
        })
        panel:AddCheckboxPair({
            label = ui.glowLabel,
            tooltip = ui.glowTooltip,
            get = function() return CommanderPartyFramesDB.WSReadyGlow end,
            set = function(value) CommanderPartyFramesDB.WSReadyGlow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Pin Focus",
            tooltip = "Keep your focus unit's row at the top of the board. No effect in Click-Cast mode (fixed roster order).",
            get = function() return CommanderPartyFramesDB.PinFocus end,
            set = function(value) CommanderPartyFramesDB.PinFocus = value end,
            isEnabled = SortableMode,
        })
        panel:AddCheckboxPair({
            label = "Combat Only",
            tooltip = "Only show the board while you are in combat.",
            get = function() return CommanderPartyFramesDB.CombatOnly end,
            set = function(value) CommanderPartyFramesDB.CombatOnly = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Track Uptime",
            tooltip = ui.uptimeTooltip,
            get = function() return CommanderPartyFramesDB.TrackUptime end,
            set = function(value) CommanderPartyFramesDB.TrackUptime = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = ui.breakLabel,
            tooltip = ui.breakTooltip,
            get = function() return CommanderPartyFramesDB.ExposeAlert end,
            set = function(value) CommanderPartyFramesDB.ExposeAlert = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = ui.breakSoundLabel,
            tooltip = ui.breakSoundTooltip,
            get = function() return CommanderPartyFramesDB.ExposeAlertSound end,
            set = function(value) CommanderPartyFramesDB.ExposeAlertSound = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ExposeAlert end,
        })
        panel:AddCheckboxPair({
            label = "Overheal Glow",
            tooltip = "Draw a thin ring just inside a row when healing on that ally SPILLED — the part of a heal that landed on someone already full. The ring brightens with how much of the heal was wasted, so a little spill is a hint and a heal that did nothing at all is a statement; it fades over Hold, which means a one-off waste reads as a pulse while a hot ticking into a capped ally sits there as a steady ring saying so.\n\nThe left edge deliberately starts past the row's state stripe rather than over it: the stripe answers a different question and covering it would trade one answer for another.\n\nRead straight off the combat log, which reports the spilled amount outright — this is the one half of the healing accounting that needs no guessing.",
            get = function() return CommanderPartyFramesDB.OverhealGlow end,
            set = function(value) CommanderPartyFramesDB.OverhealGlow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "My Heals Only",
            tooltip = "Count only healing YOU cast. Another healer's waste is real information — it means the target is capped and nobody needs to top them — but it is not your global being thrown away, and counting both makes the ring mean less of each. Off widens it to every heal landing on that ally, whoever cast it.",
            get = function() return CommanderPartyFramesDB.OverhealMine end,
            set = function(value) CommanderPartyFramesDB.OverhealMine = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.OverhealGlow
            end,
        })
        panel:AddSliderPair({
            label = "Overheal At",
            tooltip = "How much of a heal has to spill before the ring says anything. At 50% a heal that landed half its value is worth knowing about; raise it toward 100% to hear only about heals that did nothing at all, or drop it to see every drop of waste. This is the knob that decides whether the ring is a rare cue or a constant readout.",
            min = 10, max = 100, step = 5,
            format = function(value) return string.format("%d%%", value or 0) end,
            get = function() return CommanderPartyFramesDB.OverhealPct end,
            set = function(value) CommanderPartyFramesDB.OverhealPct = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.OverhealGlow
            end,
        }, {
            label = "Overheal Hold",
            tooltip = "How long the ring lingers after a spill, fading as it goes. Short enough and each wasted heal is its own pulse; long enough and a target being continuously overhealed keeps a steady ring, because every tick refreshes it before the last has faded.",
            min = 0.5, max = 4, step = 0.5,
            format = function(value) return string.format("%.1fs", value or 0) end,
            get = function() return CommanderPartyFramesDB.OverhealHold end,
            set = function(value) CommanderPartyFramesDB.OverhealHold = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.OverhealGlow
            end,
        })
        -- Chassis, so it rides the shared section rather than being added
        -- four times: every board asks the same three questions of an ally.
        AddForecastSection(panel, ui)
end

-- The banner's appearance, as opposed to its contents: how tall the strip is,
-- how big the icons on it are, what the text is written in, and what (if
-- anything) is drawn behind it. Every control here is chassis — the banner is
-- the same shape on all four class pages, so the thing that changes with the
-- class is what the readout SAYS, never how it is drawn.
--
-- Two rules shaped the ranges. Nothing may go below the size where a
-- twelve-pixel glyph stops being legible, because a banner you cannot read
-- during a game is a banner that is off; and the defaults are all exactly what
-- the header hard-coded before this section existed, so opening it changes
-- nothing until you move something.
-- Commander_Production is an optional dependency: loaded, it publishes the
-- accessor the header draws its queue from, and that is the only thing the
-- embed needs. Checked at click time rather than cached, the same way the
-- board itself asks at the draw rate.
local function ProductionLoaded()
    return CommanderProduction_Queue ~= nil
end

-- The four per-class Banner Cooldowns toggles are moot while Production is
-- standing in for the run they switch, so they grey out together with it
-- instead of appearing to do something.
local function BannerCdsOn()
    return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader
        and not (CommanderPartyFramesDB.HeaderProduction and ProductionLoaded())
end

local function AddHeaderSection(panel, ui)
    local function HeaderOn()
        return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader
    end
    local function BackdropOn()
        return HeaderOn() and CommanderPartyFramesDB.HeaderBackdrop
    end

    panel:AddSection("Header",
        "How the banner across the top of the board is drawn. Show Header at the top of this page decides whether it is there at all; everything below decides what it looks like when it is. The readout sizes itself from these — a taller strip centres its icons in the new height, a bigger icon pushes the text along with it, and the right-hand controls scale as a group — so the banner stays one object however far you take it.")
    panel:AddCheckboxPair({
        label = "Header Backdrop",
        tooltip = ui.backdropTooltip,
        get = function() return CommanderPartyFramesDB.HeaderBackdrop end,
        set = function(value) CommanderPartyFramesDB.HeaderBackdrop = value end,
        isEnabled = HeaderOn,
    }, {
        label = "Settings Button",
        tooltip = "Show a small gear at the header's right edge that opens this settings page.",
        get = function() return CommanderPartyFramesDB.ShowSettingsButton end,
        set = function(value) CommanderPartyFramesDB.ShowSettingsButton = value end,
        isEnabled = HeaderOn,
    })
    panel:AddSliderPair({
        label = "Header Height",
        tooltip = "How tall the banner strip is. Everything on it centres itself in whatever you set — the icons, the text and the buttons on the right all hang from the middle line — so this is a spacing control rather than a crop. It also moves the board: the rows begin directly under the strip, and the frame grows and shrinks with it.",
        min = 10, max = 40, step = 1,
        format = function(value) return string.format("%dpx", value or 0) end,
        get = function() return CommanderPartyFramesDB.HeaderHeight end,
        set = function(value) CommanderPartyFramesDB.HeaderHeight = value end,
        isEnabled = HeaderOn,
    }, {
        label = "Left Inset",
        tooltip = "How far in from the board's left edge the banner's content starts, past the class stripe. The buttons and the readout share that starting point, so this indents the whole left block at once — worth a couple of pixels if you run a heavy styled backdrop whose border would otherwise crowd the first icon.",
        min = 0, max = 20, step = 1,
        format = function(value) return string.format("%dpx", value or 0) end,
        get = function() return CommanderPartyFramesDB.HeaderInset end,
        set = function(value) CommanderPartyFramesDB.HeaderInset = value end,
        isEnabled = HeaderOn,
    })
    panel:AddSliderPair({
        label = "Icon Size",
        tooltip = "The edge of every icon in the readout — your armor, your cooldowns, the alert mark. Bigger icons cost width, and the banner truncates from the right when it runs out: the layers fill it most-urgent-first precisely so that what survives a squeeze is what matters. Popouts that hang off a segment (the mage's armors, the paladin's auras and seals) follow the size down.",
        min = 8, max = 24, step = 1,
        format = function(value) return string.format("%dpx", value or 0) end,
        get = function() return CommanderPartyFramesDB.HeaderIconSize end,
        set = function(value) CommanderPartyFramesDB.HeaderIconSize = value end,
        isEnabled = HeaderOn,
    }, {
        label = "Segment Gap",
        tooltip = "Space between one icon+text segment and the next. Tighten it to fit more cooldowns on a narrow board, open it up if the numbers run together at a glance. Costs or buys width for every segment at once, so it is the cheapest way to change how much of the strip survives truncation.",
        min = 0, max = 24, step = 1,
        format = function(value) return string.format("%dpx", value or 0) end,
        get = function() return CommanderPartyFramesDB.HeaderSegmentGap end,
        set = function(value) CommanderPartyFramesDB.HeaderSegmentGap = value end,
        isEnabled = HeaderOn,
    })
    panel:AddSliderPair({
        label = "Font Size",
        tooltip = "Point size of every number the banner writes: cooldowns remaining, your shield value, session uptime, the team alert counts. Text width feeds the same truncation the icons do, so a large face on a narrow board buys legibility with segments.",
        min = 7, max = 20, step = 1,
        format = function(value) return string.format("%dpt", value or 0) end,
        get = function() return CommanderPartyFramesDB.HeaderFontSize end,
        set = function(value) CommanderPartyFramesDB.HeaderFontSize = value end,
        isEnabled = HeaderOn,
    }, {
        label = "Control Size",
        tooltip = "Scales the controls at the banner's right edge as a group — the gear, the stacked-rows toggle and the Nearby Raid refresh. They are drawn rather than loaded, so they stay sharp at any size, and the readout reserves exactly the width they take, so growing them takes that width from the segments rather than letting the two overlap.",
        min = 0.6, max = 2, step = 0.05,
        format = function(value) return string.format("%d%%", math.floor((value or 1) * 100 + 0.5)) end,
        get = function() return CommanderPartyFramesDB.HeaderChromeScale end,
        set = function(value) CommanderPartyFramesDB.HeaderChromeScale = value end,
        isEnabled = HeaderOn,
    })
    panel:AddDropdownPair({
        label = "Font",
        tooltip = "Which face the banner writes in. All four ship with the client, so none of them can go missing across a patch. Default is the game's own Friz Quadrata; Narrow is Arial Narrow, which is the one to reach for when you want more segments on the same width.",
        options = {
            { text = "Default", value = "DEFAULT" },
            { text = "Narrow", value = "NARROW" },
            { text = "Rune", value = "RUNE" },
            { text = "Roman", value = "ROMAN" },
        },
        get = function() return CommanderPartyFramesDB.HeaderFont end,
        set = function(value) CommanderPartyFramesDB.HeaderFont = value end,
        isEnabled = HeaderOn,
    }, {
        label = "Outline",
        tooltip = "An outline around the banner's text. Worth switching on the moment you run the backdrop off or thin: a bare number over the world is at the mercy of whatever is behind it, and an outline is what makes it readable against a snowfield and a stormwind night alike. Thick trades a little sharpness for the same insurance at small sizes.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Outline", value = "OUTLINE" },
            { text = "Thick", value = "THICK" },
        },
        get = function() return CommanderPartyFramesDB.HeaderFontOutline end,
        set = function(value) CommanderPartyFramesDB.HeaderFontOutline = value end,
        isEnabled = HeaderOn,
    })
    panel:AddDropdown({
        label = "Backdrop Tint",
        tooltip = "What colour the panel behind the banner is. The five fixed tints are already mixed down to backdrop weight — this sits under a readout whose whole job is to be read, so a saturated panel is a worse panel. Class takes your own class colour and lays it on at a third strength: enough to say whose board this is at a glance across an alt roster, nowhere near enough to fight the icons on top of it. Also tints the hairline below.",
        options = {
            { text = "Black", value = "BLACK" },
            { text = "Charcoal", value = "CHARCOAL" },
            { text = "Slate", value = "SLATE" },
            { text = "Blood", value = "BLOOD" },
            { text = "Forest", value = "FOREST" },
            { text = "Class Colour", value = "CLASS" },
        },
        get = function() return CommanderPartyFramesDB.HeaderBackdropTint end,
        set = function(value) CommanderPartyFramesDB.HeaderBackdropTint = value end,
        isEnabled = BackdropOn,
    })
    panel:AddSlider({
        label = "Backdrop Opacity",
        tooltip = "How solid that panel is. Low and it is a wash that only separates the strip from the world; high and it is a bar the board hangs from. Independent of the frame's own styled backdrop, which is why turning this to nothing is not the same as switching the backdrop off — the panel is still there to be turned back up.",
        min = 0, max = 1, step = 0.05,
        format = function(value) return string.format("%d%%", math.floor((value or 0) * 100 + 0.5)) end,
        get = function() return CommanderPartyFramesDB.HeaderBackdropAlpha end,
        set = function(value) CommanderPartyFramesDB.HeaderBackdropAlpha = value end,
        isEnabled = BackdropOn,
    })
    panel:AddCheckbox({
        label = "Divider Line",
        tooltip = "A hairline along the banner's bottom edge, in a lifted version of the tint above. This is the answer for a board you want separated from the world without a slab of black over it: switch the backdrop off, switch this on, and the strip is still bounded. It is drawn from the tint whether or not the panel itself is showing.",
        get = function() return CommanderPartyFramesDB.HeaderRule end,
        set = function(value) CommanderPartyFramesDB.HeaderRule = value end,
        isEnabled = HeaderOn,
    })
    panel:AddCheckbox({
        label = "Production in Header",
        tooltip = "Put Commander Production's queue on the banner in place of the class cooldowns: every cooldown you are currently waiting on, soonest ready first, drawn as the same icon-and-countdown segments — dimmed with the time left, lit once it is READY — and truncated against the right-hand controls like the rest of the readout. Everything else on the banner stays where it is: the utility cluster still leads the line, the gear, the rows toggle and the refresh still close it, and the segments in front of the cooldowns (your armor, seal or form, the team alerts) keep their slots. Production's own frame is not moved or hidden — this is a second view of the same queue, so it follows Production's Queue Length and Minimum Cooldown, and the Banner Cooldowns toggle on this page greys out while it is on. Needs Commander Production loaded and enabled; without it the class cooldowns draw as before.",
        get = function() return CommanderPartyFramesDB.HeaderProduction end,
        set = function(value) CommanderPartyFramesDB.HeaderProduction = value end,
        isEnabled = function() return HeaderOn() and ProductionLoaded() end,
    })
end

-- ---------------------------------------------------------------------------
-- The anatomy diagram: one ally row, drawn to scale from the SAME layout the
-- live rows go through (CommanderPartyFrames_RowBlueprint lays out a scratch
-- row and reports back). It exists to answer one question the board itself
-- never does: what is the space to the right of the health bar FOR. The
-- answer is three seats held open for marks -- the target mark, the combat
-- mark, and (inside a battleground) the flag and powerup -- reserved from the
-- settings rather than from what is up, so the bar never jitters mid-fight.
-- Turn a mark off and the diagram shows the bar taking the width.
-- ---------------------------------------------------------------------------
local ANATOMY_H = 118
local WHITE8 = "Interface\\Buttons\\WHITE8X8"

local function AnatomyQuad(parent, layer, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetTexture(WHITE8)
    return t
end

local function AnatomyLabel(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 9, "OUTLINE")
    return fs
end

-- A box with an optional outline and a label under (or over) it
local function AnatomyBox(parent)
    local box = { fill = AnatomyQuad(parent, "ARTWORK", 1), label = AnatomyLabel(parent, 9) }
    box.edge = {}
    for i = 1, 4 do box.edge[i] = AnatomyQuad(parent, "ARTWORK", 2) end
    return box
end

local function PlaceBox(box, parent, x, y, w, h, fill, edge, text, labelBelow)
    box.fill:ClearAllPoints()
    box.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    box.fill:SetSize(math.max(1, w), math.max(1, h))
    if fill then box.fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1); box.fill:Show() else box.fill:Hide() end
    local e = box.edge
    if edge then
        e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); e[1]:SetSize(w, 1)
        e[2]:ClearAllPoints(); e[2]:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -(y + h - 1)); e[2]:SetSize(w, 1)
        e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y); e[3]:SetSize(1, h)
        e[4]:ClearAllPoints(); e[4]:SetPoint("TOPLEFT", parent, "TOPLEFT", x + w - 1, -y); e[4]:SetSize(1, h)
        for i = 1, 4 do e[i]:SetVertexColor(edge[1], edge[2], edge[3], edge[4] or 1); e[i]:Show() end
    else
        for i = 1, 4 do e[i]:Hide() end
    end
    box.label:ClearAllPoints()
    if text and text ~= "" then
        if labelBelow then
            box.label:SetPoint("TOP", parent, "TOPLEFT", x + w / 2, -(y + h + 2))
        else
            box.label:SetPoint("BOTTOM", parent, "TOPLEFT", x + w / 2, -(y - 2))
        end
        box.label:SetText(text)
        box.label:Show()
    else
        box.label:Hide()
    end
end

local function HideBox(box)
    box.fill:Hide(); box.label:Hide()
    for i = 1, 4 do box.edge[i]:Hide() end
end

local function AddAnatomyRow(panel)
    local row = panel:AddRow(ANATOMY_H, 6)
    local bg = AnatomyQuad(row, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetVertexColor(0.05, 0.05, 0.05, 0.6)
    local title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -4)
    title:SetText("Where the width goes")
    local caption = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    caption:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 4)
    caption:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    caption:SetJustifyH("LEFT")
    local frameBox = AnatomyBox(row)
    local stripe = AnatomyQuad(row, "ARTWORK", 1)
    local slots, reserves = {}, {}
    for i = 1, 14 do slots[i] = AnatomyBox(row) end
    for i = 1, 8 do reserves[i] = AnatomyBox(row) end
    local barBox, healthBox = AnatomyBox(row), AnatomyBox(row)
    local note = AnatomyLabel(row, 9)

    local SLOT_FILL = { 0.22, 0.22, 0.26, 1 }
    local SLOT_EDGE = { 0.5, 0.5, 0.55, 1 }
    local RESERVE_EDGE = { 1, 0.75, 0.2, 0.9 }
    local RESERVE_DIM = { 1, 0.75, 0.2, 0.35 }

    panel:AddRefresher(function()
        local bp = CommanderPartyFrames_RowBlueprint and CommanderPartyFrames_RowBlueprint()
        for _, b in ipairs(slots) do HideBox(b) end
        for _, b in ipairs(reserves) do HideBox(b) end
        if not bp then
            HideBox(frameBox); HideBox(barBox); HideBox(healthBox); stripe:Hide(); note:Hide()
            caption:SetText("The board has not built a row yet; open this page again once you are logged in on a class with a board.")
            return
        end
        local avail = math.max(300, (row:GetWidth() or 520) - 24)
        local s = math.min(2.4, avail / bp.width)
        local x0, y0 = 12, 30
        local rowH = bp.rowH * s
        -- The frame
        PlaceBox(frameBox, row, x0, y0, bp.width * s, rowH, { 0.10, 0.10, 0.12, 1 }, { 0.35, 0.35, 0.4, 1 }, nil, true)
        stripe:ClearAllPoints()
        stripe:SetPoint("TOPLEFT", row, "TOPLEFT", x0, -y0)
        stripe:SetSize(bp.stripeW * s, rowH)
        stripe:SetVertexColor(0.3, 0.8, 0.4, 1)
        stripe:Show()
        -- Left-hand slots, labels alternating above and below so they can be read
        for i, slot in ipairs(bp.slots) do
            local b = slots[i]
            if b then
                local w = slot.w * s
                local h = math.min(rowH - 4, slot.w * s)
                local label = slot.label or slot.kind
                if #label > 7 then label = label:sub(1, 6) .. "." end
                PlaceBox(b, row, x0 + slot.x * s, y0 + (rowH - h) / 2, w, h, SLOT_FILL, SLOT_EDGE, label, i % 2 == 0)
            end
        end
        -- The bar and the power strip
        local barH = bp.barH * s
        local stackH = barH + bp.healthH * s
        local barY = y0 + (rowH - stackH) / 2
        PlaceBox(barBox, row, x0 + bp.barX * s, barY, bp.barW * s, barH, { 0.25, 0.7, 0.3, 1 }, nil, "health bar  (takes whatever is left)", false)
        if bp.healthH > 0 then
            PlaceBox(healthBox, row, x0 + bp.barX * s, barY + barH, bp.barW * s, bp.healthH * s, { 0.25, 0.45, 0.85, 1 }, nil, nil, true)
        else
            HideBox(healthBox)
        end
        -- The seats to the right of the bar, drawn from the right edge inward
        local rx = x0 + (bp.width - bp.pad + 2) * s
        local n = 0
        local function Reserve(w, label, live)
            if w <= 0 then return end
            n = n + 1
            rx = rx - w * s
            local h = rowH - 6
            PlaceBox(reserves[n], row, rx, y0 + 3, w * s, h, nil, live and RESERVE_EDGE or RESERVE_DIM, label, true)
            if not live then reserves[n].label:SetTextColor(0.7, 0.6, 0.4) else reserves[n].label:SetTextColor(1, 0.85, 0.4) end
        end
        if bp.grid and (bp.seat or 0) > 0 then
            -- One seat, four cells, each with a fixed meaning
            local seatW = bp.seat * s
            rx = rx - seatW
            local cell = bp.cell * s
            n = n + 1
            PlaceBox(reserves[n], row, rx, y0 + (rowH - (2 * cell + s)) / 2, seatW, 2 * cell + s, nil, RESERVE_EDGE, "marks", true)
            reserves[n].label:SetTextColor(1, 0.85, 0.4)
            local cells = {
                { 0, 0, bp.seatMarks, "target" }, { cell + s, 0, bp.seatCombat, "combat" },
                { 0, cell + s, bp.seatBg, "flag" }, { cell + s, cell + s, bp.seatBg, "powerup" },
            }
            local top = y0 + (rowH - (2 * cell + s)) / 2
            for i, c in ipairs(cells) do
                n = n + 1
                local b = reserves[n]
                if b then
                    PlaceBox(b, row, rx + c[1] + 1, top + c[2] + 1, cell - 2, cell - 2,
                        c[3] and { 1, 0.75, 0.2, 0.35 } or { 0.3, 0.3, 0.3, 0.3 }, nil, nil, true)
                end
            end
            -- The cell legend, to the right of the frame
            note:ClearAllPoints()
            note:SetPoint("TOPLEFT", row, "TOPLEFT", x0 + bp.width * s + 8, -(y0 + 2))
            note:SetJustifyH("LEFT")
            note:SetText(string.format("|cffffd966target%s  combat%s|r\n|cffffd966flag%s  powerup%s|r",
                bp.seatMarks and "" or " (off)", bp.seatCombat and "" or " (off)",
                bp.seatBg and "" or " (off)", bp.seatBg and "" or " (off)"))
            note:Show()
        else
            note:Hide()
        end
        Reserve(bp.marks, "target mark", true)
        Reserve(bp.combat, "in combat", true)
        if bp.bg > 0 then
            Reserve(bp.bg, "flag + powerup", true)
        elseif bp.bgPossible > 0 then
            -- Not reserved here; drawn dim INSIDE the bar's end to show what a
            -- battleground will take
            n = n + 1
            local w = bp.bgPossible * s
            PlaceBox(reserves[n], row, rx - w, y0 + 3, w, rowH - 6, nil, RESERVE_DIM, "flag + powerup (in a BG)", true)
            reserves[n].label:SetTextColor(0.7, 0.6, 0.4)
        end
        local reservedNow = bp.marks + bp.combat + bp.bg + (bp.seat or 0)
        if bp.grid and (bp.seat or 0) > 0 then
            caption:SetText(string.format("Right of the bar: one %d px seat holding every mark in a fixed cell -- their target's raid mark top-left, crossed swords while they fight top-right, the flag bottom-left, the powerup bottom-right -- so all four at once still read. Reserved from the settings, not from what is up, so the bar never twitches mid-fight. Switch Mark Layout (Identity & Icons) to Side by side for one seat per mark.", bp.seat))
        elseif reservedNow > 0 then
            caption:SetText(string.format("Right of the bar: %d px held open for marks -- the raid mark of each ally's target, the crossed swords while they fight%s. Reserved from the settings, not from what is up, so the bar never twitches mid-fight. Turn a mark off (Identity & Icons) and the bar takes its width; Frame Width sets the total.",
                reservedNow, bp.bg > 0 and ", and the flag and powerup" or (bp.bgPossible > 0 and " (plus two battleground slots once you zone in)" or "")))
        else
            caption:SetText("Nothing is reserved to the right of the bar; it runs to the frame's edge. Target Marks, Combat Marks and Battleground Marks (Identity & Icons) each hold a seat there when on.")
        end
    end)
    return row
end

-- The head of every page: the master switch, what goes on the board, how big
-- it is, and the test button. Pure chassis — the only thing that changes
-- with the class is what the tooltips say the board is FOR, and the one
-- control the absorb board has that nothing else does (a shield strength
-- low enough to top off, which needs a shield to be a strength of).
local function AddPageHead(panel, ui)
        panel:AddCheckboxPair({
            label = "Enable Shield",
            tooltip = "Master switch for the whole module.",
            get = function() return CommanderPartyFramesDB.EnableShield end,
            set = function(value) CommanderPartyFramesDB.EnableShield = value end,
        }, {
            label = "Show Header",
            tooltip = ui.headerTooltip,
            get = function() return CommanderPartyFramesDB.ShowHeader end,
            set = function(value) CommanderPartyFramesDB.ShowHeader = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        -- Everything above the first heading stays on the page whatever is
        -- folded, so it is only the master switches; the board's own shape
        -- is a section like the rest
        panel:AddSection("Board", "Who is on the board, in what order, how many rows and how wide, and when it shows at all.")
        panel:AddCheckboxPair({
            label = "Include Self",
            tooltip = ui.selfTooltip,
            get = function() return CommanderPartyFramesDB.IncludeSelf end,
            set = function(value) CommanderPartyFramesDB.IncludeSelf = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Self First",
            tooltip = "Pin your own row to the top instead of sorting it in with everyone else — by urgency, or into your class's group under a class order. In Click-Cast mode you are already the first row unless a class order is on, where this pins you above the class list.",
            get = function() return CommanderPartyFramesDB.SelfFirst end,
            set = function(value) CommanderPartyFramesDB.SelfFirst = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.IncludeSelf end,
        })
        panel:AddDropdown({
            label = "Sort Rows",
            tooltip = "How the board orders its rows, on every board. Urgency is the board as it has always been: most-urgent first, so the row that wants a global is the top one. The two class orders read the board as a class list instead — warriors, paladins, hunters, rogues, priests, shamans, mages, warlocks, druids — so the rows hold still while the fight changes: Class, then Distance puts each class's members closest to you first, so the nearest mage is always the first mage; Class, then Name keeps each class alphabetical, the order that never moves at all. A pet sits under its owner's class, after that class's players. Where the client will not report positions (some instanced content), the distance order ties everyone in range and falls back to the name. Self First and Pin Focus still lift a row to the top in any order. With Max Rows tight, the classes at the bottom of the order are the ones that fall off.\n\nIn Click-Cast mode the rows are secure buttons bound out of combat, so Urgency cannot apply there (the board keeps its roster order) — but the class orders can: they are applied when the rows are bound, a change asked for mid-fight lands the moment the fight ends, and the distance kind re-checks itself every few seconds out of combat. Nearby Raid has its own Row Order in its section below, with these same orders and the pick's own nearest-first order, because the pick is a different board.",
            options = {
                { text = "Urgency", value = "URGENCY" },
                { text = "Class, then Distance", value = "CLASS_DIST" },
                { text = "Class, then Name", value = "CLASS_NAME" },
            },
            get = function()
                local v = CommanderPartyFramesDB.RowOrder
                if v == "CLASS" then return "CLASS_DIST" end
                return v or "URGENCY"
            end,
            set = function(value)
                CommanderPartyFramesDB.RowOrder = value
                -- The trap this setting fell into on its first day: Nearby
                -- Raid was drawing its pick nearest-first and quietly
                -- ignoring the class order. Say so the moment it would.
                if value ~= "URGENCY" and CommanderPartyFramesDB.NearMode
                    and (CommanderPartyFramesDB.NearSort or "DISTANCE") == "DISTANCE" then
                    print("Commander Party Frames: Nearby Raid keeps drawing its pick nearest-first until its own Row Order (in the Nearby Raid section) is changed.")
                end
            end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckbox({
            label = "Include Pets",
            tooltip = ui.petsTooltip,
            get = function() return CommanderPartyFramesDB.IncludePets end,
            set = function(value) CommanderPartyFramesDB.IncludePets = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Only Show Alerts",
            tooltip = ui.alertsTooltip,
            get = function() return CommanderPartyFramesDB.OnlyAlerts end,
            set = function(value) CommanderPartyFramesDB.OnlyAlerts = value end,
            isEnabled = SortableMode,
        }, {
            label = "Always Show",
            tooltip = "Keep the board frame on screen even when there is nothing to report.",
            get = function() return CommanderPartyFramesDB.AlwaysShow end,
            set = function(value) CommanderPartyFramesDB.AlwaysShow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        -- Settings Button and Header Backdrop used to sit here, next to
        -- these two. They moved into the Header section below, where the rest
        -- of the banner's appearance now lives: a backdrop toggle three rows
        -- above the tint and the opacity that only apply to it is a worse
        -- place for it than one row above them.
        panel:AddCheckboxPair({
            label = "Fixed Frame Size",
            tooltip = "Keep the frame (and its styled backdrop) sized for the full board length instead of shrinking to what is currently shown.",
            get = function() return CommanderPartyFramesDB.FixedHeight end,
            set = function(value) CommanderPartyFramesDB.FixedHeight = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Hide Default Party Frames",
            tooltip = "Hide Blizzard's own party frames — and its raid frames — and run on this board alone. The raid manager tab on the left edge stays, since it holds the ready check, world markers and tank assignment. The header's stacked-rows button toggles the same setting, and |cffffd100/cpf blizzard|r works from anywhere — worth knowing, because this board is Priest/Mage/Druid/Paladin only and can hide itself. Changes apply out of combat; switching the module off gives the default frames back.",
            get = function() return CommanderPartyFramesDB.HideBlizzardParty end,
            set = function(value) CommanderPartyFramesDB.HideBlizzardParty = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckbox({
            label = "Hide Tooltips In Arena",
            tooltip = "Inside an arena, hovering anything on the board shows no tooltip at all: the rows, the ability strip's cells, the banner and header buttons, the blessing slot. Every one of them opens beside what you hovered, and on this board that is the next row's debuffs — the thing you were looking for. Clicks and @mouseover macros work exactly the same; only the tooltip goes. Battlegrounds and the open world keep them.",
            get = function() return CommanderPartyFramesDB.HideArenaTooltips end,
            set = function(value) CommanderPartyFramesDB.HideArenaTooltips = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown({
            label = "Watch",
            tooltip = "Which allies to put on the board. Party watches you and your party; Raid watches you and your raid group (use Max Rows and Only Show Alerts to keep a large raid readable).",
            options = {
                { text = "Party", value = "PARTY" },
                { text = "Raid", value = "RAID" },
            },
            get = function() return CommanderPartyFramesDB.Scope end,
            set = function(value) CommanderPartyFramesDB.Scope = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSliderPair({
            label = "Max Rows",
            tooltip = ui.maxRowsTooltip,
            min = 1, max = 40, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.MaxRows end,
            set = function(value) CommanderPartyFramesDB.MaxRows = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Frame Width",
            tooltip = ui.widthTooltip .. " The health bar takes whatever the icons on the left and the mark seats on the right leave -- the diagram below shows the split.",
            min = 180, max = 340, step = 2,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.FrameWidth end,
            set = function(value) CommanderPartyFramesDB.FrameWidth = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        AddAnatomyRow(panel)
        -- The absorb board is the only one with a shield strength to call low.
        if ui.lowShield then
            panel:AddSliderPair({
                label = "Low Absorb",
                tooltip = "A shield holding at or below this share of its capacity is treated as low — flagged to top off (or as fading if you cannot reshield yet).",
                min = 5, max = 60, step = 5,
                format = function(value) return string.format("%d%%", value or 0) end,
                get = function() return CommanderPartyFramesDB.LowAbsorbPct end,
                set = function(value) CommanderPartyFramesDB.LowAbsorbPct = value end,
                isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
            }, {
                label = "Expiring At",
                tooltip = "A shield with this many seconds or fewer remaining is treated as expiring, the same as running low on absorb.",
                min = 1, max = 15, step = 1,
                format = function(value) return string.format("%ds", value or 0) end,
                get = function() return CommanderPartyFramesDB.LowTimeSecs end,
                set = function(value) CommanderPartyFramesDB.LowTimeSecs = value end,
                isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
            })
        end
        panel:AddButtonRow({
            {
                label = "Test Board",
                width = 110,
                tooltip = "Fill the board with sample rows in every state so you can see and position it without a group (also: /cpf test).",
                onClick = function() if CommanderPartyFrames_Test then CommanderPartyFrames_Test() end end,
            },
        })

        panel:AddSlider({
            label = "Rebuff Window",
            tooltip = ui.rebuffTooltip,
            min = 60, max = 900, step = 30,
            format = function(value) return string.format("%dm", math.floor((value or 0) / 60 + 0.5)) end,
            get = function() return CommanderPartyFramesDB.IntRefreshAt end,
            set = function(value) CommanderPartyFramesDB.IntRefreshAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })

        AddHeaderSection(panel, ui)

        -- Nearby Raid. Every control here is gated on the flag above it, so a
        -- board that never switches it on has exactly the settings it always
        -- had, and the whole block reads as one feature rather than five
        -- strays scattered through the page.
        panel:AddSection("Nearby Raid",
            "In a raid or a battleground the roster is forty people and this board is unreadable — but the allies who actually matter to you are the ones standing next to you. Switch this on and the board becomes party frames again: you, plus the closest few raid members, on the same rows with the same class layer. It is a snapshot rather than a live per-frame sort: the pick holds until the refresh control on the header, the auto-refresh timer, or a roster change takes a new one — and every one of those re-sorts nearest-first. Off everywhere outside a raid; a five-man party already is this board.")
        panel:AddCheckboxPair({
            label = "Nearby Raid",
            tooltip = "Replace the raid roster with you and the closest few raid members whenever you are in a raid or a battleground. Watch (Party/Raid) above has no say while this is on — the point is that neither of those is what you want in a battleground.",
            get = function() return CommanderPartyFramesDB.NearMode end,
            set = function(value) CommanderPartyFramesDB.NearMode = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Refresh Button",
            tooltip = "A refresh control on the header, beside the gear: left-click picks again sorted by distance, right-click toggles auto-refresh. Its tint is the auto state — grey manual, green automatic, amber when a pick is made and waiting for the fight to end (Click-Cast rows cannot be re-bound in combat). Also |cffffd100/cpf near|r, which prints who it chose and how far away they are.",
            get = function() return CommanderPartyFramesDB.NearButton end,
            set = function(value) CommanderPartyFramesDB.NearButton = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.NearMode
            end,
        })
        panel:AddSliderPair({
            label = "People",
            tooltip = "How many people the board carries in nearby mode, YOU included — so 5 is a party, 10 is two and 15 is three. This is the row bound while nearby mode is on: Max Rows above is the whole-raid control and would silently clip a pick of fifteen down to six. Allies' pets ride their owners on top of this count, exactly as they do in a party.",
            min = 2, max = 15, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.NearCount end,
            set = function(value) CommanderPartyFramesDB.NearCount = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.NearMode
            end,
        }, {
            label = "Auto Every",
            tooltip = "How long between automatic re-picks, when Auto Refresh is on. Short values keep the order honest while people move; long ones keep the rows still.",
            min = 1, max = 15, step = 1,
            format = function(value) return string.format("%ds", value or 0) end,
            get = function() return CommanderPartyFramesDB.NearInterval end,
            set = function(value) CommanderPartyFramesDB.NearInterval = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.NearMode and CommanderPartyFramesDB.NearAuto
            end,
        })
        panel:AddCheckbox({
            label = "Auto Refresh",
            tooltip = "Take the same sorted pick the button takes, on a timer, so the board re-orders itself as people move around you. The one difference from pressing it by hand is invisible and deliberate: an automatic pick lets whoever is already on the board keep their place against a MARGINALLY closer outsider, so two allies drifting either side of the cutoff do not swap in and out every few seconds. Pressing the button gives no such credit — a fresh collection means exactly that. In Click-Cast mode a re-pick made mid-fight is parked and applied the moment combat ends; secure rows cannot be re-bound in combat, and the header control goes amber to say so.",
            get = function() return CommanderPartyFramesDB.NearAuto end,
            set = function(value) CommanderPartyFramesDB.NearAuto = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.NearMode
            end,
        })
        panel:AddDropdown({
            label = "Row Order",
            tooltip = "How the picked allies are laid out. The pick decides WHO is on the board; this decides where. As Picked draws them nearest-first, held to the snapshot, which is what makes a refresh visible as a refresh. Urgency is the board's own most-urgent-first sort. Class, then Distance groups the pick by class in the suite's class order — warriors, paladins, hunters, rogues, priests, shamans, mages, warlocks, druids — each class's members closest-first, live rather than held to the snapshot. Class, then Name keeps the same groups alphabetical, the order that never moves at all. A pet sits under its owner's class, after that class's players. On the Click-Cast board Urgency cannot apply (secure rows keep the pick order instead); the class orders are applied when the rows are bound, so a refresh made mid-fight lands when the fight ends.",
            options = {
                { text = "As Picked (nearest first)", value = "DISTANCE" },
                { text = "Urgency", value = "URGENCY" },
                { text = "Class, then Distance", value = "CLASS_DIST" },
                { text = "Class, then Name", value = "CLASS_NAME" },
            },
            get = function()
                local v = CommanderPartyFramesDB.NearSort
                -- Older spellings: one build wrote CLASS for the distance
                -- kind and BOARD for "whatever Sort Rows says"
                if v == "CLASS" then return "CLASS_DIST" end
                if v == "BOARD" then
                    local r = CommanderPartyFramesDB.RowOrder
                    if r == "CLASS" then return "CLASS_DIST" end
                    return r or "URGENCY"
                end
                return v or "DISTANCE"
            end,
            set = function(value) CommanderPartyFramesDB.NearSort = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.NearMode
            end,
        })
        panel:AddCheckbox({
            label = "Ghosts Count As Far",
            tooltip = "A released ghost is standing at the graveyard, not where they fell, and there is nothing on them to heal, buff or dispel -- so the nearby pick ranks them as infinitely far and they never take a seat from someone you can act on. An ally who has died but NOT released is still a body at a real distance (a Rebirth or a Redemption is a decision about exactly that body), so their yards stay as they are.",
            get = function() return CommanderPartyFramesDB.NearGhostsFar end,
            set = function(value) CommanderPartyFramesDB.NearGhostsFar = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.NearMode
            end,
        })
        panel:AddButtonRow({
            {
                label = "Refresh Now",
                width = 110,
                tooltip = "Take a fresh pick, sorted by distance — the same thing the header control does on a left-click, and |cffffd100/cpf near|r from anywhere.",
                onClick = function()
                    if CommanderPartyFrames_Near then CommanderPartyFrames_Near() end
                end,
            },
        })


end

local function CreateCorePanel()
    -- Ask the engine which class layer this character gets (nil = none)
    local layerMode, classToken
    if CommanderPartyFrames_GetProfileMode then layerMode, classToken = CommanderPartyFrames_GetProfileMode() end
    local mageMode = layerMode == "INT"
    local druidMode = layerMode == "HOT"
    local palaMode = layerMode == "BLESS"
    local unsupported = not layerMode

    local description
    if unsupported then
        local localizedClass = UnitClass("player")
        description = string.format(
            "Swiss-army-knife party frames with a class layer. Priests get the reshield board (Power Word: Shield, Weakened Soul, dispels); Mages get buff-upkeep frames (Arcane Intellect, decursing, an optional self-shield strip); Druids get the hot board (Rejuvenation, Regrowth, Lifebloom stacks, curses and poisons); Paladins get the blessing board (one blessing slot per ally, Forbearance). %s has no layer yet, so the module stays dormant on this character. Settings here are shared account-wide — boards on your Priest, Mage, Druid or Paladin characters are unaffected.",
            localizedClass or "This class")
    elseif palaMode then
        description = "Arena party frames with a paladin's brain. Health and mana per ally, absorbs embedded in the bar, and — leading each row — ONE blessing slot showing whichever blessing of yours is on that ally right now, timed by a radial sweep: Kings with its minutes, or the Protection, Freedom or Sacrifice you just spent on them with its seconds, because on this client those are blessings and take the same slot (a Protection takes your Kings off, and the slot says so). When none of yours is on them it shows the blessing you decided they should carry, ghosted. Blessings are counted only when YOU cast them, so a second paladin never makes a naked teammate look handled. Forbearance draws the red drain under the bar, because a target who cannot be Protected is a target you plan around. A removable debuff turns the row purple or green, crowd control orange. The banner on top is your own upkeep: aura, seal, cooldowns, blessing uptime, team alerts. Allies' pets get full rows too."
    elseif druidMode then
        description = "Arena party frames with a resto druid's brain. Health and mana per ally, absorbs embedded in the bar, and — leading each row — your ally buffs and the hots you have rolling there, each in a fixed slot timed by a radial sweep. A removable Curse turns the row purple, a Poison green, crowd control orange. The banner on top is your own upkeep: form, cooldowns, hot uptime, team alerts. Allies' pets get full rows too."
    elseif mageMode then
        description = "Arena party frames with a mage's brain. Health and mana per ally, their TOTAL shielding — every absorb from any caster — drained live by real absorb events, and an ally-buff strip leading each row. A removable curse turns the row purple; a teammate in crowd control turns it orange with the CC and time left. The banner is your own management: armor, shield uptime, alerts, and the conjure/consume cluster."
    else
        description = "Every absorb on the board at once, yours and everyone else's, embedded in each ally's health bar — with your own shield's remaining absorb as the row's number and the Weakened Soul lockout that blocks a reshield. Sorted most-urgent first, with an ally-buff strip leading each row. Built for Priests."
    end

    local panel = Commander.UI.NewPanel({
        key = "PartyFrames",
        title = "Party Frames",
        addonName = "Commander_PartyFrames",
        description = description,
        event = COMMANDER_PARTYFRAMES_EVENTS.UPDATE,
        slash = { "/cpf", "/cpframes" },
        slashHandlers = {
            test = function() if CommanderPartyFrames_Test then CommanderPartyFrames_Test() end end,
            report = function() if CommanderPartyFrames_Report then CommanderPartyFrames_Report() end end,
            debug = function() if CommanderPartyFrames_Debug then CommanderPartyFrames_Debug() end end,
            buffs = function() if CommanderPartyFrames_Buffs then CommanderPartyFrames_Buffs() end end,
            binds = function() if CommanderPartyFrames_Binds then CommanderPartyFrames_Binds() end end,
            abilities = function() CommanderPartyFrames_ToggleAbilityWindow() end,
            -- Re-picks the nearby-raid board and prints what it chose, which
            -- is also the only place that says whether the distances behind it
            -- are real yards or interact-distance bands
            near = function() if CommanderPartyFrames_Near then CommanderPartyFrames_Near() end end,
            -- Commander Orders' arrow follows your current target, when they
            -- are in your group; the click-cast board's twin is the "Arrow to
            -- them" binding below
            arrow = function() if CommanderPartyFrames_ArrowTo then CommanderPartyFrames_ArrowTo("target") end end,
            -- Always-available twin of the header button: the board is
            -- Priest/Mage/Druid/Paladin only, and it can hide itself
            blizzard = function()
                if CommanderPartyFrames_ToggleBlizzardParty then
                    CommanderPartyFrames_ToggleBlizzardParty()
                end
            end,
        },
    })

    -- Dormant class: the description above says everything — no controls that
    -- would silently do nothing (and, DB being account-wide, nothing to safely
    -- toggle from here anyway).
    if unsupported then
        panel:Finalize({ onDefaults = Reset })
        return
    end

    -- ---- Mage party frames: buff upkeep + decursing on the ally chassis ----
    if mageMode then
        AddPageHead(panel, LAYER_UI.INT)
        AddBuffSection(panel, "INT")

        AddIdentitySection(panel, LAYER_UI.INT)

        AddClickSection(panel)

        AddDecisionAids(panel, LAYER_UI.INT)

        panel:AddSection("Banner", "The strip across the top of the board: which of your cooldowns it carries beside your upkeep.")
        panel:AddCheckbox({
            label = "Banner Cooldowns",
            tooltip = "Show Ice Block and Cold Snap on the banner — lit when ready, dimmed with the time left when not. Only these two: they are the pair you check when there is no time to look anywhere, and Cold Snap only means anything next to Block and Barrier. Your other cooldowns are not here on purpose — each already wears a swipe on your action bar, three times this size, exactly where you look to press it again. Ice Barrier and the Water Elemental have their own rows below the board, saying more than a segment could.",
            get = function() return CommanderPartyFramesDB.MageBannerCooldowns end,
            set = function(value) CommanderPartyFramesDB.MageBannerCooldowns = value end,
            isEnabled = BannerCdsOn,
        })

        panel:AddSection("Banner Buttons", "Sit-down management, off by default: these four live at the banner's left edge, in front of the readout, so every one of them costs width the fight itself could be using. Turn the cluster on when you want them and off when you are queuing. Bandage below is separate — it stays on, because it is the one you press mid-fight.")
        panel:AddCheckbox({
            label = "Mage Utility Cluster",
            tooltip = "Show the between-games buttons: Conjure (left-click water, right-click food), Consume (left-click drink, right-click eat — pressing both is the full sit-down), and, filtered by the two toggles below, the Mana Gem and the Portals popout.",
            get = function() return CommanderPartyFramesDB.MageUtilityButtons end,
            set = function(value) CommanderPartyFramesDB.MageUtilityButtons = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Portals & Teleports",
            tooltip = "Add a button opening a two-row popout of every teleport (top) and portal (bottom) you have trained — the armor switcher's pattern, for travel. Hidden until you learn your first teleport.",
            get = function() return CommanderPartyFramesDB.ShowPortalButton end,
            set = function(value) CommanderPartyFramesDB.ShowPortalButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.MageUtilityButtons end,
        }, {
            label = "Mana Gem",
            tooltip = "Add a mana gem button: left-click uses the best gem in your bags, right-click (or holding your modifier and left-clicking) steps a castsequence through every gem you know — Ruby, Citrine, Jade, Agate — so four presses leave you carrying one of each. Ten seconds off the button restarts the sequence at the top rank. Counter over the icon shows how many gems you are carrying.",
            get = function() return CommanderPartyFramesDB.ShowGemButton end,
            set = function(value) CommanderPartyFramesDB.ShowGemButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.MageUtilityButtons end,
        })
        panel:AddCheckboxPair({
            label = "Bandage",
            tooltip = "Add a First Aid button: left or right-click bandages a living friendly target (or yourself when you have none), the icon reddens with a countdown while Recently Bandaged blocks another, and middle-click opens the First Aid window.",
            get = function() return CommanderPartyFramesDB.ShowBandageButton end,
            set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Inventory Counters",
            tooltip = "Show how many you are carrying over each button — water on Conjure, food on Consume, gems on Mana Gem, bandages on Bandage. These keep counting during a fight, when the buttons' bindings themselves cannot be re-aimed.",
            get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
            set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })

        AddDispelSection(panel, LAYER_UI.INT)

        panel:AddSection("My Shields", "Your own Ice Barrier, Mana Shield and wards, the Water Elemental, and the Ice Block tracker, in the block that leads the board — the one between the banner and the first ally. Drawn as a line of dials in the radial nameplates' language: the spell is the face, the absorb left is the band round it, the time left is the thin arc outside that, and a cooldown is a clock wipe across the face with its seconds written on it. A shield that is not up is a dark face, so nothing ever moves. Works on both the sorted and the Click-Cast boards.")
        panel:AddDropdown({
            label = "Draw As",
            tooltip = "Dials puts every tracker on ONE line as a disc: icon, absorb band, clock, and the number on the face. The block is the same height whether you track one shield or five.\n\nRows is the original: a half-height bar per tracker with its name beside it, stacked, so four shields is four rows.",
            options = {
                { text = "Dials (one line)", value = "DIALS" },
                { text = "Rows (a bar each)", value = "ROWS" },
            },
            width = 180,
            get = function() return CommanderPartyFramesDB.PersonalStyle end,
            set = function(value) CommanderPartyFramesDB.PersonalStyle = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown({
            label = "Band Style",
            tooltip = "What the band round each dial is drawn with. Flat is a solid block of the shield's colour. The others are the board's bar styles bent round the face and lit from the outer edge -- Blizzard is the stock status bar's bright lip and darker foot, Gloss a soft tube, Bevel a flat block with a lit edge, Ridge brushed metal, Glass a hard cut across the middle.\n\nSame As The Bars follows whatever Bar Texture is set to, so the dials and the rows under them always match.",
            options = {
                { text = "Same as the bars", value = "MATCH" },
                { text = "Flat", value = "FLAT" },
                { text = "Blizzard", value = "BLIZZARD" },
                { text = "Gloss", value = "GLOSS" },
                { text = "Bevel", value = "BEVEL" },
                { text = "Ridge", value = "RIDGE" },
                { text = "Glass", value = "GLASS" },
            },
            width = 180,
            get = function() return CommanderPartyFramesDB.DialTexture end,
            set = function(value) CommanderPartyFramesDB.DialTexture = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.PersonalStyle == "DIALS"
            end,
        })
        panel:AddSlider({
            label = "Number Size",
            tooltip = "The font size of the number on each dial's face. Auto sizes it off the dial, so it follows Dial Size; a fixed size stays put whatever the dial does.",
            min = 0, max = 18, step = 1,
            format = function(v) return v == 0 and "Auto" or string.format("%dpt", v) end,
            get = function() return CommanderPartyFramesDB.DialTextSize end,
            set = function(value)
                CommanderPartyFramesDB.DialTextSize = (value > 0 and value < 7) and 7 or value
            end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.PersonalStyle == "DIALS"
            end,
        })
        panel:AddSlider({
            label = "Darken Face Under Text",
            tooltip = "How far a lit dial's face darkens while a number is written across it. The number also carries a black shadow, which holds its edges; this is what holds its middle -- a white 1.1k over Ice Barrier's pale icon has an outline and nothing inside it to tell from the picture. Only a face with a number on it is darkened. 0 leaves the icon untouched.",
            min = 0, max = 0.8, step = 0.05,
            format = function(v) return v == 0 and "Off" or string.format("%d%%", v * 100 + 0.5) end,
            get = function() return CommanderPartyFramesDB.DialTextShade end,
            set = function(value) CommanderPartyFramesDB.DialTextShade = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.PersonalStyle == "DIALS"
            end,
        })
        panel:AddSlider({
            label = "Dial Size",
            tooltip = "A dial's diameter in pixels. The block is this tall plus a few pixels of air. If the dials you track would not fit across the frame at this size they shrink until they do.",
            min = 20, max = 44, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.DialSize end,
            set = function(value) CommanderPartyFramesDB.DialSize = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.PersonalStyle == "DIALS"
            end,
        })
        panel:AddCheckboxPair({
            label = "Show My Shields",
            tooltip = "A tracker for each self-shield you know: ready to cast (dark), on cooldown (dark, wiped, with the seconds left and a red rim), running low (the band and rim change colour), or holding (lit, with the absorb remaining). Switch this off and only the Water Elemental is left in the block.",
            get = function() return CommanderPartyFramesDB.SelfShieldRows end,
            set = function(value) CommanderPartyFramesDB.SelfShieldRows = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Track Mana Shield",
            tooltip = "Give Mana Shield its own row in the extra. No cooldown, so its row only ever asks: is it up, and how much is left?",
            get = function() return CommanderPartyFramesDB.TrackManaShield end,
            set = function(value) CommanderPartyFramesDB.TrackManaShield = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.SelfShieldRows end,
        })
        panel:AddCheckboxPair({
            label = "Track Wards",
            tooltip = "Give Fire Ward and Frost Ward rows in the extra (only the ones you know). Their 30s cooldown shows as the red drain, so you can pre-ward the moment it matters.",
            get = function() return CommanderPartyFramesDB.TrackWards end,
            set = function(value) CommanderPartyFramesDB.TrackWards = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.SelfShieldRows end,
        }, {
            label = "Ice Block Tracker",
            tooltip = "One more seat in the block, last in the line (a dial, or a row when Draw As is Rows), answering the one question there is never time to look for: can I Block? It shows whichever answer is true, highest first:\n\n1. Hypothermia -- you cannot, whatever else is ready: dark, wiped for what is left, red rim. While you are inside the Block its ten seconds run the thin clock outside.\n2. Ice Block ready -- the lit Ice Block.\n3. Cold Snap ready -- Block is cooling but Snap can refund it: the lit Cold Snap, gold rim.\n4. Both cooling -- whichever comes back first, wiped with its time on the face.\n\nWithout Cold Snap (fire, arcane) step 3 never appears. Shown whether or not Show My Shields is on.",
            get = function() return CommanderPartyFramesDB.TrackIceBlock end,
            set = function(value) CommanderPartyFramesDB.TrackIceBlock = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })

        AddAlertSoundsSection(panel, "INT")

        AddAbilityBarSection(panel)

        FinishPanel(panel)
        return
    end

    -- ---- Druid party frames: rolling hots + two schools of removal ----
    if druidMode then
        AddPageHead(panel, LAYER_UI.HOT)
        AddBuffSection(panel, "HOT")

        panel:AddSection("Hots", "Your own hots on each ally, one fixed slot each, timed by a radial sweep. The row's number is whichever falls off first.")
        panel:AddSlider({
            label = "Refresh Window",
            tooltip = "Seconds left at or under which a hot counts as expiring — the row turns cyan (REFRESH) and sorts up by how long is actually left. Rejuvenation and Regrowth only: Lifebloom has its own window below, because four seconds of a seven-second buff is most of its life and a slot that is amber most of the time stops meaning anything.",
            min = 1, max = 10, step = 1,
            format = "%.0fs",
            get = function() return CommanderPartyFramesDB.HotRefreshAt end,
            set = function(value) CommanderPartyFramesDB.HotRefreshAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Hot Me At",
            tooltip = "Health at or under which an ally carrying none of your hots turns yellow (READY — start one now). Above it they stay quiet, so a full-health party does not light the whole board up. Set it to 100% to flag every hotless ally.",
            min = 30, max = 100, step = 5,
            format = "%.0f%%",
            get = function() return CommanderPartyFramesDB.HotReadyAt end,
            set = function(value) CommanderPartyFramesDB.HotReadyAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSection("Banner", "The strip across the top of the board: which of your cooldowns it carries beside your upkeep.")
        panel:AddCheckbox({
            label = "Banner Cooldowns",
            tooltip = "Show Innervate, Nature's Swiftness, Rebirth and Barkskin on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so a feral never sees a Nature's Swiftness slot.",
            get = function() return CommanderPartyFramesDB.HotBannerCooldowns end,
            set = function(value) CommanderPartyFramesDB.HotBannerCooldowns = value end,
            isEnabled = BannerCdsOn,
        })

        panel:AddSection("Lifebloom",
            "Lifebloom is not a hot with a stack count on it. Seven seconds, three stacks, a refresh that resets the whole duration — so it is a decision you make every five seconds forever, and one missed refresh costs three globals to rebuild or pops the bloom you were holding. On the shared hot strip it looked like everything else, which is exactly why it kept falling off: a radial sweep is a fine way to say \"there is time\" and a useless way to say \"there are two seconds\".\n\nThese give it its own instruments. Everything below is off the strip's shared settings, so tuning Lifebloom never touches Rejuvenation or Regrowth.")
        panel:AddDropdown({
            label = "Lifebloom Display",
            tooltip = "Clock replaces the slot's radial sweep with a countdown on the icon itself — whole seconds, then tenths under three, where a tenth is the difference between a refresh and a bloom. It also gives the slot its own three colours instead of the strip's one amber: green while there is time, gold inside the refresh window, purple at three stacks (refresh, or let it bloom), red once you are late.\n\nBar puts the roll on the thin drain strip under the health bar — the strip the druid board has never used, because there is no Weakened Soul and no Forbearance on a hot board. It empties over the seven seconds in the same colours, which makes it the one instrument here you can read with the corner of your eye while looking somewhere else. That is what keeps a roll going.\n\nBoth is the pair, and the default. Off puts Lifebloom back on the shared hot strip exactly as it was.",
            options = {
                { text = "Clock + Bar", value = "BOTH" },
                { text = "Clock Only", value = "CLOCK" },
                { text = "Bar Only", value = "BAR" },
                { text = "Off (plain hot slot)", value = "OFF" },
            },
            get = function() return CommanderPartyFramesDB.LBDisplay end,
            set = function(value) CommanderPartyFramesDB.LBDisplay = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSliderPair({
            label = "Refresh Window",
            tooltip = "Seconds left at or under which Lifebloom counts as due — the clock, the pips and the bar all turn gold together. Its own number, not the hot strip's: set it to the point where you actually want to be pressing the button, which for a roll is usually one global plus your reaction time.",
            min = 1, max = 6, step = 1,
            format = function(value) return string.format("%ds", value or 0) end,
            get = function() return CommanderPartyFramesDB.LBRefreshAt end,
            set = function(value) CommanderPartyFramesDB.LBRefreshAt = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.LBDisplay ~= "OFF"
            end,
        }, {
            label = "Late At",
            tooltip = "Seconds left at or under which you are no longer refreshing early, you are refreshing behind. Everything turns red and the slot starts pulsing — and unlike the refresh window, which a rolling Lifebloom enters every five seconds by design, this one only happens when you are actually late. That is what makes it worth an alarm.",
            min = 0.5, max = 3, step = 0.5,
            format = function(value) return string.format("%.1fs", value or 0) end,
            get = function() return CommanderPartyFramesDB.LBLateAt end,
            set = function(value) CommanderPartyFramesDB.LBLateAt = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.LBDisplay ~= "OFF"
            end,
        })
        panel:AddCheckboxPair({
            label = "Stack Pips",
            tooltip = "Show the stack count as three lights along the bottom of the icon instead of a digit. \"Am I at three\" is a question you ask a hundred times a fight, and a shape answers it without being read. Off keeps the plain number the rest of the strip uses.",
            get = function() return CommanderPartyFramesDB.LBStackPips end,
            set = function(value) CommanderPartyFramesDB.LBStackPips = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.LBDisplay ~= "OFF"
            end,
        }, {
            label = "Sort First",
            tooltip = "Float an expiring Lifebloom above other expiring hots. A Rejuvenation about to drop is one global to replace; a three-stack Lifebloom about to drop is three, or the bloom you were saving. Off by default because it reorders a board you have learned to read.",
            get = function() return CommanderPartyFramesDB.LBPriority end,
            set = function(value) CommanderPartyFramesDB.LBPriority = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.LBDisplay ~= "OFF"
            end,
        })
        panel:AddCheckboxPair({
            label = "Late Warning",
            tooltip = "Flash the row red the moment a Lifebloom of yours goes late — once per cycle, on the edge, so holding it late does not strobe and a refresh re-arms it for the next one. Deliberately tied to Late At rather than the refresh window: a roll enters its window every five seconds by design, and an alarm on that is a metronome, not a warning.",
            get = function() return CommanderPartyFramesDB.LBAlert end,
            set = function(value) CommanderPartyFramesDB.LBAlert = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.LBDisplay ~= "OFF"
            end,
        }, {
            label = "Late Sound",
            tooltip = "Also play a sound with the late flash. Worth it if you are watching the enemy team rather than the board, which is most of an arena.",
            get = function() return CommanderPartyFramesDB.LBAlertSound end,
            set = function(value) CommanderPartyFramesDB.LBAlertSound = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.LBDisplay ~= "OFF"
                    and CommanderPartyFramesDB.LBAlert
            end,
        })

        AddIdentitySection(panel, LAYER_UI.HOT)

        AddClickSection(panel)

        AddDecisionAids(panel, LAYER_UI.HOT)

        panel:AddSection("Banner Buttons", "First Aid is not a class layer, so the bandage control rides this banner too.")
        panel:AddCheckboxPair({
            label = "Bandage Button",
            tooltip = "Show the First Aid control: left or right-click bandages your friendly target (or you), middle-click opens the First Aid window. The icon carries a count of the bandages in your bags and sweeps while the target is locked out by Recently Bandaged.",
            get = function() return CommanderPartyFramesDB.ShowBandageButton end,
            set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        }, {
            label = "Inventory Counts",
            tooltip = "Show the live tally of what is in your bags over the button icon.",
            get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
            set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })

        AddDispelSection(panel, LAYER_UI.HOT)

        AddAlertSoundsSection(panel, "HOT")

        AddAbilityBarSection(panel)

        FinishPanel(panel)
        return
    end

    -- ---- Paladin party frames: the blessing slot and Forbearance ----
    if palaMode then
        AddPageHead(panel, LAYER_UI.BLESS)
        AddBuffSection(panel, "BLESS")
        AddBlessingSection(panel)

        panel:AddSection("Emergency Blessings", "Freedom, Protection and Sacrifice. On this client they are blessings, not Hands: each takes the ally's ONE blessing slot, so a Protection on an ally carrying your Kings takes the Kings off. The slot shows whichever is on them — the Protection with its ten seconds, then the ghosted Kings asking to go back on — and when a target is carrying Forbearance, the red drain under the bar is the minute you cannot Protect them for.")
        panel:AddSlider({
            label = "Expiring Window",
            tooltip = "Seconds left at or under which a Freedom, Protection or Sacrifice counts as expiring — its slot turns amber and the row goes cyan (REFRESH), sorted up by how long is actually left. This is the seconds-scale sister of the Rebuff Window above, which is for the ten- and thirty-minute blessings. Ten seconds of Freedom goes fast, so set this to the reaction time you actually want.",
            min = 1, max = 10, step = 1,
            format = "%.0fs",
            get = function() return CommanderPartyFramesDB.BlessRefreshAt end,
            set = function(value) CommanderPartyFramesDB.BlessRefreshAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSection("Banner", "The strip across the top of the board: which of your cooldowns it carries beside your upkeep.")
        panel:AddCheckbox({
            label = "Banner Cooldowns",
            tooltip = "Show Lay on Hands, Divine Shield, Divine Protection, Blessing of Protection, Freedom and Sacrifice, Divine Favor, Avenging Wrath, Hammer of Justice, Divine Illumination and Repentance on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so a holy paladin never sees a Repentance slot.",
            get = function() return CommanderPartyFramesDB.BlessBannerCooldowns end,
            set = function(value) CommanderPartyFramesDB.BlessBannerCooldowns = value end,
            isEnabled = BannerCdsOn,
        })

        AddIdentitySection(panel, LAYER_UI.BLESS)

        AddClickSection(panel)

        AddDecisionAids(panel, LAYER_UI.BLESS)

        panel:AddSection("Banner Buttons", "First Aid is not a class layer, so the bandage control rides this banner too.")
        panel:AddCheckboxPair({
            label = "Bandage Button",
            tooltip = "Show the First Aid control: left or right-click bandages your friendly target (or you), middle-click opens the First Aid window. The icon carries a count of the bandages in your bags and sweeps while the target is locked out by Recently Bandaged.",
            get = function() return CommanderPartyFramesDB.ShowBandageButton end,
            set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        }, {
            label = "Inventory Counts",
            tooltip = "Show the live tally of what is in your bags over the button icon.",
            get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
            set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })

        AddDispelSection(panel, LAYER_UI.BLESS)

        AddAlertSoundsSection(panel, "BLESS")

        AddAbilityBarSection(panel)

        FinishPanel(panel)
        return
    end


    -- ---- Priest ally board (the original page, unchanged) ----
    AddPageHead(panel, LAYER_UI.PWS)
    AddBuffSection(panel, "PWS")

    AddIdentitySection(panel, LAYER_UI.PWS)

    AddClickSection(panel)

    AddDecisionAids(panel, LAYER_UI.PWS)
    panel:AddSection("Banner Buttons", "First Aid is not a class layer, so the bandage control rides this banner too.")
    panel:AddCheckboxPair({
        label = "Bandage",
        tooltip = "Add a First Aid button at the banner's right edge: left or right-click bandages a living friendly target (or yourself when you have none), the icon reddens with a countdown while Recently Bandaged blocks another, and middle-click opens the First Aid window.",
        get = function() return CommanderPartyFramesDB.ShowBandageButton end,
        set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Inventory Counters",
        tooltip = "Show how many bandages you are carrying over the button. The count keeps updating during a fight, when the button's binding itself cannot be re-aimed.",
        get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
        set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.ShowBandageButton end,
    })

    AddDispelSection(panel, LAYER_UI.PWS)

    panel:AddSection("Banner", "The strip across the top of the board: which of your cooldowns it carries beside your upkeep.")
    panel:AddCheckbox({
        label = "Banner Cooldowns",
        tooltip = "Show Pain Suppression, Power Infusion, Fear Ward, Psychic Scream, Silence, Inner Focus, Shadowfiend, Mass Dispel and Desperate Prayer on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so a holy priest never sees a Pain Suppression slot.",
        get = function() return CommanderPartyFramesDB.PriestBannerCooldowns end,
        set = function(value) CommanderPartyFramesDB.PriestBannerCooldowns = value end,
        isEnabled = BannerCdsOn,
    })

    panel:AddSection("Team Shields", "A dial for you and each of your party — your subgroup in a raid — in the block between the banner and the first ally, in the radial nameplates' language. The face is who it is: lit while a shield is on them, dark while they are bare. The band round it is the shield's absorb left and the thin arc outside that its thirty seconds. Weakened Soul is a red clock wipe across the face — yours too — so a red wedge retreating is your next shield coming back, whether the face under it is lit or dark. No numbers: lit or dark, how much band, how much red. The rim says what to do: red, no shield and still locked (you cannot help with a shield yet); yellow, bare and unlocked in a fight (shield them); blue, a low shield you can replace; orange, a low shield you cannot yet. Your Prayer of Mending sits on the four o'clock badge of whoever is holding it, with a ring for whether it can bounce on: green, someone is within twenty yards of them; red, nobody is, so their next hit spends the heal and wastes the rest; no ring where the client gives no positions. The seats hold still, so nothing ever shuffles, and they work on both the sorted and the Click-Cast boards.")
    local function TeamOn()
        return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.TeamDials
    end
    panel:AddCheckboxPair({
        label = "Team Shield Dials",
        tooltip = "The line of dials above the board: one per teammate, carrying their Power Word: Shield and their Weakened Soul. The space is held whether the group is two people or five, so the rows under it never move.",
        get = function() return CommanderPartyFramesDB.TeamDials end,
        set = function(value) CommanderPartyFramesDB.TeamDials = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Include Yourself",
        tooltip = "Your own dial leads the line. Off, the line is your party alone.",
        get = function() return CommanderPartyFramesDB.TeamDialsSelf end,
        set = function(value) CommanderPartyFramesDB.TeamDialsSelf = value end,
        isEnabled = TeamOn,
    })
    panel:AddSlider({
        label = "Dial Size",
        tooltip = "A dial's diameter in pixels. The block is this tall plus a few pixels of air. Five dials have to fit across the frame, so at a narrow width they shrink until they do. Shared with the mage's dials.",
        min = 20, max = 44, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.DialSize end,
        set = function(value) CommanderPartyFramesDB.DialSize = value end,
        isEnabled = TeamOn,
    })
    panel:AddDropdown({
        label = "Band Style",
        tooltip = "What the absorb band round each dial is drawn with. Same As The Bars follows Bar Texture, so the dials and the rows under them match.",
        options = {
            { text = "Same as the bars", value = "MATCH" },
            { text = "Flat", value = "FLAT" },
            { text = "Blizzard", value = "BLIZZARD" },
            { text = "Gloss", value = "GLOSS" },
            { text = "Bevel", value = "BEVEL" },
            { text = "Ridge", value = "RIDGE" },
            { text = "Glass", value = "GLASS" },
        },
        width = 180,
        get = function() return CommanderPartyFramesDB.DialTexture end,
        set = function(value) CommanderPartyFramesDB.DialTexture = value end,
        isEnabled = TeamOn,
    })

    panel:AddSection("Your Hots", "Renew and Prayer of Mending on each ally, one fixed slot each on the left of the row, timed by a radial sweep — the same strip a druid's hots ride. Which of them get a slot is set in the Ally Buffs grid above. The row's state stays what it has always been: the shield and the Weakened Soul lockout, because no hot outranks those on this board.")
    panel:AddCheckbox({
        label = "Refresh Flash",
        tooltip = "Pulse a hot's slot red while it is inside the refresh window below, so an about-to-drop Renew catches your eye. With this off the slot still tints amber — it just stops pulsing. This is the only warning the priest board gives about an expiring hot: on the druid and paladin boards the whole row changes colour, but here the row is busy saying something about the shield.",
        get = function() return CommanderPartyFramesDB.RenewFlash end,
        set = function(value) CommanderPartyFramesDB.RenewFlash = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddSlider({
        label = "Refresh At",
        tooltip = "Treat one of your hots as expiring when this many seconds or fewer remain — its slot tints, and pulses if Refresh Flash is on.",
        min = 1, max = 10, step = 1,
        format = function(value) return string.format("%ds", value or 0) end,
        get = function() return CommanderPartyFramesDB.RenewRefreshAt end,
        set = function(value) CommanderPartyFramesDB.RenewRefreshAt = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckbox({
        label = "Needs a Renew Ring",
        tooltip = "Ring a row faintly in red when that ally is low enough to want a Renew and has none of yours on them — the same hairline the overheal ring uses, in the opposite colour, and it deepens as they drop.\n\nIt reads your Renew whether or not you have given Renew a slot on the strip: hiding the icon is a display choice, and it should not stop the board telling you a dying ally has nothing rolling on them. When a heal of yours spills on that same ally the overheal ring takes the border for the second it lasts, then the red comes back.",
        get = function() return CommanderPartyFramesDB.RenewNeedRing end,
        set = function(value) CommanderPartyFramesDB.RenewNeedRing = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddSlider({
        label = "Needs a Renew At",
        tooltip = "Health at or under which a Renew-less ally starts to ring. The ring is faintest here and deepens the further they fall, so the threshold is where it starts speaking rather than where it shouts.",
        min = 50, max = 100, step = 5,
        format = function(value) return string.format("%d%%", value or 0) end,
        get = function() return CommanderPartyFramesDB.RenewNeedAt end,
        set = function(value) CommanderPartyFramesDB.RenewNeedAt = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.RenewNeedRing end,
    })

    panel:AddSection("Prayer of Mending", "The one thing on this strip that is not a buff on a row. Mending is a single object with five charges that lands on an ally, heals, and JUMPS to the next — you own exactly one of them, and every row's slot is a view of the same one. That makes the interesting moments belong to the object rather than to any row, and it makes the obvious warning — \"it left this ally\" — useless, because on a full cast that happens four times and is the spell working.")
    -- The master first, and everything else greys out under it: this is one
    -- feature, not four, and the tracker behind it does no work at all with
    -- the switch off.
    local function PoMOn()
        return CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.PoMTrack
    end
    panel:AddCheckboxPair({
        label = "Track Mending",
        tooltip = "Follow your Prayer of Mending as the single travelling object it is — one spell with five charges, hopping between allies — rather than as an aura that appears and vanishes on unrelated rows. Everything below is part of this one switch, and with it off the tracker does no work at all: the slot goes back to being an ordinary strip entry with a sweep and a number.",
        get = function() return CommanderPartyFramesDB.PoMTrack end,
        set = function(value) CommanderPartyFramesDB.PoMTrack = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Charge Pips",
        tooltip = "Show the charges as five lights along the bottom of the slot instead of a digit, emptying as they are spent and reddening on the last one. A charge count only ever goes down, so what you want off it is how much is LEFT — which is a shape, not a number to read. Off keeps the plain digit.",
        get = function() return CommanderPartyFramesDB.PoMPips end,
        set = function(value) CommanderPartyFramesDB.PoMPips = value end,
        isEnabled = PoMOn,
    })
    panel:AddCheckboxPair({
        label = "End Alert",
        tooltip = "Flash and sound when your Mending ENDS — the last charge spent, the thirty seconds run out, a purge or dispel taking it, a heal with nobody within twenty yards to jump to, or the holder dying with it. Never on a bounce: when the aura leaves someone the board waits a beat to see whether it reappears on anyone else, and a bounce cancels the warning before it can fire. The flash lands on whoever was holding it, coloured by which it was — green for spent, amber for expired, violet for dispelled, orange for nobody in range, red for simply gone.",
        get = function() return CommanderPartyFramesDB.PoMAlert end,
        set = function(value) CommanderPartyFramesDB.PoMAlert = value end,
        isEnabled = PoMOn,
    }, {
        label = "End Sound",
        tooltip = "Also play a sound with it, and three different ones. Spent: it did exactly what you cast it for and only the cooldown is left to wait on (a high bell). Wasted: it ended without bouncing on — it sat out its thirty seconds, a purge took it, or it healed with nobody in range to jump to — and the recast is yours to make now (the holy fizzle, small and unlike anything else). Lost: it went with a holder who died (a low bell). Worth it if you are watching the enemy team rather than the board, which is most of an arena — and the sound is the half that still reaches you when the holder has died off the board entirely. Each sound is picked under Alert Sounds below.",
        get = function() return CommanderPartyFramesDB.PoMAlertSound end,
        set = function(value) CommanderPartyFramesDB.PoMAlertSound = value end,
        isEnabled = function() return PoMOn() and CommanderPartyFramesDB.PoMAlert end,
    })
    panel:AddCheckboxPair({
        label = "Cooldown Ring",
        tooltip = "Draw Mending's own cooldown around the slot's border, on every ally's row rather than only the one carrying it — because \"can I cast this here right now\" is a question every row asks, and for one travelling object the answer is the same everywhere. A dark slot with a closing ring is a Mending on cooldown; a dark slot with no ring is one you can cast this instant.\n\nThe border, not the face: the sweep on the face is the aura's remaining thirty seconds, and those two are genuinely different numbers — the object can be sitting on someone with twenty seconds left while you are still four from the next cast.",
        get = function() return CommanderPartyFramesDB.PoMCooldownRing end,
        set = function(value) CommanderPartyFramesDB.PoMCooldownRing = value end,
        isEnabled = PoMOn,
    }, {
        label = "Show the Hop",
        tooltip = "Light both ends of a bounce: a flare on the slot that just took the Mending, and a fading ghost on the slot it left. It is the only thing on this board that says \"that was fine\" — everything else Mending does now makes a noise — and it turns a number quietly changing rows into movement you actually see.",
        get = function() return CommanderPartyFramesDB.PoMTrail end,
        set = function(value) CommanderPartyFramesDB.PoMTrail = value end,
        isEnabled = PoMOn,
    })

    AddAlertSoundsSection(panel, "PWS")

    AddAbilityBarSection(panel)

    FinishPanel(panel)
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_PartyFrames" then
        -- One-time repairs, keyed by a revision OUTSIDE DefaultSettings so
        -- Restore Defaults can never un-migrate. Rev 2: the rename-era
        -- default seeded SelfShieldRows=false before the default flipped on.
        if (CommanderPartyFramesDB.PFRev or 0) < 2 then
            CommanderPartyFramesDB.SelfShieldRows = true
            CommanderPartyFramesDB.PFRev = 2
        end
        -- Rev 3: the mana strip became the power strip. Anyone who had turned
        -- the old one OFF gets it off — the new default is ALL, and applying
        -- it blind would put bars back on a board they deliberately cleared.
        -- Everyone else lands on ALL, which is the point of the change.
        if (CommanderPartyFramesDB.PFRev or 0) < 3 then
            if CommanderPartyFramesDB.ShowManaBar == false then
                CommanderPartyFramesDB.PowerBar = "OFF"
            end
            CommanderPartyFramesDB.PFRev = 3
        end
        -- Rev 4: one Frame Scale became three group-size brackets. Each
        -- starts at the scale you had, so nothing moves until you tune one.
        if (CommanderPartyFramesDB.PFRev or 0) < 4 then
            local was = tonumber(CommanderPartyFramesDB.HudScale) or 1
            for _, key in ipairs({ "HudScaleSmall", "HudScaleParty", "HudScaleLarge" }) do
                if CommanderPartyFramesDB[key] == nil then CommanderPartyFramesDB[key] = was end
            end
            CommanderPartyFramesDB.PFRev = 4
        end
        Commander.UI.ApplyDefaults(CommanderPartyFramesDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

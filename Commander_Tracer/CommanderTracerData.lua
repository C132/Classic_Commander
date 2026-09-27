-- Commander Tracer: the tables.
--
-- Everything here is a LIST the rest of the module walks -- the lanes, the
-- kinds of thing that can happen, the motions a number can make, the faces
-- it can be written in, the sounds it can make, the CVars it takes over from
-- Blizzard. The engine and the settings page both read these, so a lane or a
-- kind added here gets its controls, its routing and its harness coverage at
-- once, and the settings-reach check can enumerate every key the module can
-- possibly own.
--
-- Nothing in this file touches the client.

CommanderTracer_Data = CommanderTracer_Data or {}
local DATA = CommanderTracer_Data

-- ---------------------------------------------------------------------------
-- Lanes. A lane is one anchored place on the screen where text appears, with
-- its own motion, face, colour rule and chrome. Six of them: four for the
-- numbers, one for the ledger (the SC2-style alert column), one for the big
-- callouts. Every per-lane setting is stored as <key><Setting>, e.g.
-- OutFontSize, and the HUD chrome keys come from the same prefix
-- (OutStyle / OutScale / OutLocked / OutPos).
-- ---------------------------------------------------------------------------
DATA.LANES = {
    { key = "Out",    title = "Outgoing Damage",  short = "Outgoing",
      note = "Everything you and your pet land on somebody else: hits, crits, dot ticks, misses. Rises to the right of your character by default, the way the stock text does, so muscle memory carries over.",
      point = { point = "CENTER", x = 250, y = 30 },
      motion = "SCROLL", direction = "UP", fontSize = 18, color = "SCHOOL", format = "AMOUNT", icon = "LEFT" },
    { key = "Heal",   title = "Outgoing Healing", short = "Healing",
      note = "Your heals and hot ticks on anyone, yourself included. Under the damage lane by default so a healer's two columns read as one.",
      point = { point = "CENTER", x = 250, y = -110 },
      motion = "SCROLL", direction = "UP", fontSize = 16, color = "KIND", format = "AMOUNT", icon = "LEFT" },
    { key = "In",     title = "Incoming Damage",  short = "Incoming",
      note = "What lands on YOU: hits, dot ticks, what you dodged and parried, what your shield ate. To the left of your character, falling, so damage taken reads as a different thing from damage done at a glance.",
      point = { point = "CENTER", x = -250, y = 30 },
      motion = "SCROLL", direction = "DOWN", fontSize = 18, color = "SCHOOL", format = "AMOUNT_SPELL", icon = "RIGHT" },
    { key = "InHeal", title = "Incoming Healing", short = "Incoming Heals",
      note = "Heals landing on you from anyone, and the mana, rage and energy you gain. Under the incoming damage lane.",
      point = { point = "CENTER", x = -250, y = -110 },
      motion = "SCROLL", direction = "UP", fontSize = 15, color = "KIND", format = "AMOUNT_SPELL", icon = "RIGHT" },
    { key = "Log",    title = "Ledger",           short = "Ledger",
      note = "The linger log: an alert column the way a strategy game reports a finished building. One row per event with its icon, the text, and a tinted accent, sliding in at the top, holding for a few seconds, then fading. Repeats of the same spell merge into one row with a count rather than stacking six Fireballs.",
      point = { point = "LEFT", x = 30, y = 140 },
      motion = "STACK", direction = "DOWN", fontSize = 13, color = "KIND", format = "FULL", icon = "LEFT" },
    { key = "Call",   title = "Callouts",         short = "Callouts",
      note = "The moments: a killing blow, an interrupt you landed, a proc ready, a dispel. Big text at the top of the screen that punches in and fades. Off for the ordinary numbers, on for the things you would say out loud.",
      point = { point = "TOP", x = 0, y = -180 },
      motion = "POP", direction = "DOWN", fontSize = 26, color = "KIND", format = "FULL", icon = "LEFT" },
}
DATA.LANE_BY_KEY = {}
for _, lane in ipairs(DATA.LANES) do DATA.LANE_BY_KEY[lane.key] = lane end

-- The per-lane settings and their defaults. `lane.<field>` overrides come
-- from the LANES entry above (motion, direction, fontSize, color, format,
-- icon), everything else is shared. The settings page builds one control
-- per entry per lane, the reach check enumerates prefix x key.
DATA.LANE_DEFAULTS = {
    Enable = true,
    Motion = "SCROLL",          -- SCROLL | FOUNTAIN | POP | STACK
    Direction = "UP",           -- UP | DOWN (scroll: travel; stack: growth; pop: stagger)
    Side = "ALTERNATE",         -- LEFT | RIGHT | ALTERNATE (fountain)
    Duration = 2.2,             -- seconds on screen
    Speed = 70,                 -- px/s (scroll), launch strength (fountain)
    Spread = 24,                -- px of sideways scatter so two numbers do not print on top of each other
    Merge = 0,                  -- seconds; same spell inside the window becomes one entry with a count. 0 = off
    MaxLines = 12,              -- more than this and the oldest goes
    MinAmount = 0,              -- hide anything smaller (0 = show all)
    Font = "DEFAULT",           -- DEFAULT | NARROW | RUNE | ROMAN
    FontSize = 18,
    Outline = "OUTLINE",        -- NONE | OUTLINE | THICK
    Shadow = true,
    Icon = "LEFT",              -- NONE | LEFT | RIGHT
    IconSize = 16,
    ColorMode = "SCHOOL",       -- SCHOOL | KIND | FLAT | CLASS
    FlatColor = "STEEL",        -- a palette key (Console's, when it is there)
    CritScale = 1.5,
    CritMark = "BANG",          -- NONE | BANG | WORD | STARS
    CritPunch = true,           -- a crit lands big and settles, rather than just being big
    Format = "AMOUNT",          -- AMOUNT | AMOUNT_SPELL | SPELL_AMOUNT | AMOUNT_TARGET | FULL
    Alpha = 1.0,
    ShowPartials = false,       -- "(320 absorbed)" after the number
    -- stack (ledger) only
    Width = 260,
    SlideIn = 40,               -- px the row slides in from
    RowBackdrop = true,
    RowAccent = true,
    Sub = true,                 -- the small second line (target, count)
}

-- ---------------------------------------------------------------------------
-- Kinds. Every event the module understands, in the order the routing page
-- lists them. Each is stored as <key>Lane (which lane, or OFF) and
-- <key>Ledger (also a ledger row). `group` is the routing page's heading.
-- `color` is the KIND colour rule's answer; `sound` names the sound slot a
-- kind can ring, if any.
-- ---------------------------------------------------------------------------
DATA.KINDS = {
    -- yours
    { key = "DamageDone",   label = "Your Hits",         group = "YOURS", lane = "Out",  ledger = true,
      tip = "Direct damage you deal with a spell, a shot or a weapon swing that is not the auto-attack.",
      color = { 1, 1, 1 } },
    { key = "AutoAttack",   label = "Auto-Attacks",      group = "YOURS", lane = "Out",  ledger = false,
      tip = "Your white swings. Off the ledger by default: a rogue's auto-attacks would be the whole column.",
      color = { 0.9, 0.85, 0.75 } },
    { key = "PeriodicDone", label = "Your Dot Ticks",    group = "YOURS", lane = "Out",  ledger = false,
      tip = "Every tick of your damage-over-time spells.",
      color = { 0.85, 0.65, 1 } },
    { key = "PetDamage",    label = "Pet Damage",        group = "YOURS", lane = "Out",  ledger = false,
      tip = "What your pet lands, tagged so it cannot be mistaken for yours.",
      color = { 0.8, 0.8, 0.8 } },
    { key = "MissDone",     label = "Your Misses",       group = "YOURS", lane = "Out",  ledger = false,
      tip = "Miss, dodge, parry, block, resist, immune: the word for what went wrong, so a resisted Frostbolt is not a silent gap.",
      color = { 0.7, 0.7, 0.7 } },
    { key = "HealDone",     label = "Your Heals",        group = "YOURS", lane = "Heal", ledger = true,
      tip = "Direct heals you land on anyone, including yourself.",
      color = { 0.35, 1, 0.45 } },
    { key = "PeriodicHeal", label = "Your Hot Ticks",    group = "YOURS", lane = "Heal", ledger = false,
      tip = "Every tick of your healing-over-time spells.",
      color = { 0.5, 0.95, 0.6 } },
    -- on you
    { key = "DamageTaken",  label = "Damage On You",     group = "ONYOU", lane = "In",   ledger = false,
      tip = "Direct hits landing on you, with the spell that did it.",
      color = { 1, 0.3, 0.3 } },
    { key = "PeriodicTaken", label = "Dots On You",      group = "ONYOU", lane = "In",   ledger = false,
      tip = "Every tick of a damage-over-time effect on you.",
      color = { 0.9, 0.4, 0.6 } },
    { key = "MissTaken",    label = "You Avoided",       group = "ONYOU", lane = "In",   ledger = false,
      tip = "What you dodged, parried, blocked or resisted, and what was immune on you.",
      color = { 0.75, 0.75, 0.85 } },
    { key = "AbsorbTaken",  label = "Your Shield Ate",   group = "ONYOU", lane = "In",   ledger = false,
      tip = "Damage a shield on you absorbed, as its own line rather than a footnote on the hit.",
      color = { 1, 0.85, 0.35 } },
    { key = "HealTaken",    label = "Heals On You",      group = "ONYOU", lane = "InHeal", ledger = false,
      tip = "Heals landing on you from anyone but yourself (your own are Your Heals).",
      color = { 0.35, 1, 0.45 } },
    { key = "Energize",     label = "Power Gains",       group = "ONYOU", lane = "InHeal", ledger = false,
      tip = "Mana, rage, energy or focus gained from a spell or a proc, coloured by the power.",
      color = { 0.4, 0.55, 1 } },
    { key = "BuffGained",   label = "Buffs On You",      group = "ONYOU", lane = "OFF",  ledger = true,
      tip = "A helpful aura landing on you, as a ledger row with its icon.",
      color = { 0.6, 0.9, 1 } },
    { key = "BuffFaded",    label = "Buffs Fading",      group = "ONYOU", lane = "OFF",  ledger = false,
      tip = "A helpful aura leaving you.",
      color = { 0.55, 0.55, 0.65 } },
    { key = "DebuffGained", label = "Debuffs On You",    group = "ONYOU", lane = "OFF",  ledger = true,
      tip = "A harmful aura landing on you: the sheep, the fear, the dot.",
      color = { 1, 0.45, 0.25 } },
    -- moments
    { key = "KillingBlow",  label = "Killing Blows",     group = "MOMENTS", lane = "Call", ledger = true,
      tip = "You landed the blow that killed something. Commander Impact draws its own TARGET ELIMINATED for the same moment; keep one of the two.",
      color = { 1, 0.82, 0.3 }, sound = "SoundKill" },
    { key = "Interrupt",    label = "Your Interrupts",   group = "MOMENTS", lane = "Call", ledger = true,
      tip = "A cast you stopped, named.",
      color = { 1, 0.6, 0.2 }, sound = "SoundInterrupt" },
    { key = "Dispel",       label = "Your Dispels",      group = "MOMENTS", lane = "Call", ledger = true,
      tip = "An aura you removed or stole, named.",
      color = { 0.55, 0.85, 1 } },
    { key = "ProcReady",    label = "Procs Ready",       group = "MOMENTS", lane = "Call", ledger = true,
      tip = "The client's own reactive-ability call: Overpower, Revenge, Mongoose Bite and friends lighting up.",
      color = { 1, 0.95, 0.5 }, sound = "SoundProc" },
    { key = "HonorGained",  label = "Honor Gained",      group = "MOMENTS", lane = "OFF",  ledger = true,
      tip = "Honor points as they arrive.",
      color = { 1, 0.75, 0.75 } },
    { key = "CombatState",  label = "Entering / Leaving Combat", group = "MOMENTS", lane = "OFF", ledger = false,
      tip = "A ledger row when combat starts and when it ends.",
      color = { 0.8, 0.8, 0.8 } },
}
DATA.KIND_BY_KEY = {}
for _, kind in ipairs(DATA.KINDS) do DATA.KIND_BY_KEY[kind.key] = kind end
DATA.KIND_GROUPS = {
    { key = "YOURS",   title = "Routing: Your Output",
      note = "Where each thing you do is drawn. A lane, or Off, and whether it also gets a ledger row." },
    { key = "ONYOU",   title = "Routing: On You",
      note = "Where each thing that happens to you is drawn." },
    { key = "MOMENTS", title = "Routing: The Moments",
      note = "The events worth a callout: kills, interrupts, dispels, procs, honor." },
}

-- ---------------------------------------------------------------------------
-- Motions
-- ---------------------------------------------------------------------------
DATA.MOTIONS = {
    { value = "SCROLL",   text = "Scroll",   tip = "The classic: the number appears at the anchor and travels up (or down) at a steady speed, fading at the end." },
    { value = "FOUNTAIN", text = "Fountain", tip = "The number is thrown outward in an arc and falls, alternating sides. The old parabola style; reads well for burst." },
    { value = "POP",      text = "Pop",      tip = "The number appears in place, punches in a size, holds, and fades. Newer ones stack below (or above) the older. The quietest style." },
    { value = "STACK",    text = "Stack",    tip = "A column of rows, newest first, that slide in and shove the rest along. The ledger's motion; any lane can use it." },
}
DATA.DIRECTIONS = {
    { value = "UP",   text = "Up" },
    { value = "DOWN", text = "Down" },
}
DATA.SIDES = {
    { value = "ALTERNATE", text = "Alternate" },
    { value = "LEFT",      text = "Left" },
    { value = "RIGHT",     text = "Right" },
}
DATA.FORMATS = {
    { value = "AMOUNT",        text = "Amount",           tip = "Just the number: 1,204" },
    { value = "AMOUNT_SPELL",  text = "Amount, Spell",    tip = "1,204 Fireball" },
    { value = "SPELL_AMOUNT",  text = "Spell, Amount",    tip = "Fireball 1,204" },
    { value = "AMOUNT_TARGET", text = "Amount, Target",   tip = "1,204 on Gankmage" },
    { value = "FULL",          text = "Everything",       tip = "Fireball 1,204 on Gankmage" },
}
DATA.ICON_PLACES = {
    { value = "NONE",  text = "None" },
    { value = "LEFT",  text = "Left of the text" },
    { value = "RIGHT", text = "Right of the text" },
}
DATA.COLOR_MODES = {
    { value = "SCHOOL", text = "By School",  tip = "Fire orange, frost blue, shadow purple, holy gold, nature green, arcane violet, physical white. Heals green, misses grey, power by its kind." },
    { value = "KIND",   text = "By Kind",    tip = "One colour per kind of event (yours white, dots violet, incoming red, heals green, kills gold), whatever the school." },
    { value = "FLAT",   text = "One Colour", tip = "Every entry in the lane in the colour picked below." },
    { value = "CLASS",  text = "Class Colour", tip = "Your own class colour on everything in the lane." },
}
DATA.CRIT_MARKS = {
    { value = "NONE",  text = "Size only" },
    { value = "BANG",  text = "1,204!" },
    { value = "WORD",  text = "1,204 crit" },
    { value = "STARS", text = "*1,204*" },
}
DATA.NUMBER_STYLES = {
    { value = "PLAIN",     text = "Plain (1204)" },
    { value = "SEPARATED", text = "Separated (1,204)" },
    { value = "SHORT",     text = "Short (12.3k)" },
}
DATA.STRATA = {
    { value = "BACKGROUND", text = "Under everything" },
    { value = "LOW",        text = "Under windows" },
    { value = "MEDIUM",     text = "With the frames" },
    { value = "HIGH",       text = "Over the frames" },
}

-- The four faces the client ships, so none can go missing across a patch.
DATA.FONTS = {
    DEFAULT = "Fonts\\FRIZQT__.TTF",
    NARROW  = "Fonts\\ARIALN.TTF",
    RUNE    = "Fonts\\SKURRI.TTF",
    ROMAN   = "Fonts\\MORPHEUS.TTF",
}
DATA.FONT_OPTIONS = {
    { value = "DEFAULT", text = "Default" },
    { value = "NARROW",  text = "Narrow" },
    { value = "RUNE",    text = "Rune (the old damage font)" },
    { value = "ROMAN",   text = "Roman" },
}
DATA.OUTLINES = { NONE = "", OUTLINE = "OUTLINE", THICK = "THICKOUTLINE" }
DATA.OUTLINE_OPTIONS = {
    { value = "NONE",    text = "None" },
    { value = "OUTLINE", text = "Outline" },
    { value = "THICK",   text = "Thick" },
}

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------
-- Spell schools by mask bit. A multi-school spell (Frostfire = 20) averages
-- the bits it carries.
DATA.SCHOOLS = {
    { bit = 1,  name = "Physical", color = { 1, 1, 0.85 } },
    { bit = 2,  name = "Holy",     color = { 1, 0.9, 0.5 } },
    { bit = 4,  name = "Fire",     color = { 1, 0.5, 0.15 } },
    { bit = 8,  name = "Nature",   color = { 0.4, 0.95, 0.35 } },
    { bit = 16, name = "Frost",    color = { 0.5, 0.8, 1 } },
    { bit = 32, name = "Shadow",   color = { 0.7, 0.45, 1 } },
    { bit = 64, name = "Arcane",   color = { 1, 0.6, 1 } },
}
-- Power types by the combat log's number
DATA.POWERS = {
    [0] = { name = "Mana",      color = { 0.35, 0.55, 1 } },
    [1] = { name = "Rage",      color = { 1, 0.25, 0.25 } },
    [2] = { name = "Focus",     color = { 1, 0.55, 0.25 } },
    [3] = { name = "Energy",    color = { 1, 1, 0.35 } },
    [4] = { name = "Happiness", color = { 0.4, 1, 0.8 } },
}
-- A miss type's word
DATA.MISS_WORDS = {
    MISS = "Miss", DODGE = "Dodge", PARRY = "Parry", BLOCK = "Block", RESIST = "Resist",
    ABSORB = "Absorb", IMMUNE = "Immune", EVADE = "Evade", DEFLECT = "Deflect", REFLECT = "Reflect",
}
-- The lane's own flat palette. Console's palette is offered too when it is
-- loaded (the TopBar pattern); these stand on their own without it.
DATA.COLORS = {
    { text = "Steel",   value = "STEEL",   r = 1, g = 1, b = 1 },
    { text = "Gold",    value = "GOLD",    r = 1, g = 0.85, b = 0.5 },
    { text = "Ember",   value = "EMBER",   r = 1, g = 0.55, b = 0.4 },
    { text = "Crimson", value = "CRIMSON", r = 0.85, g = 0.2, b = 0.24 },
    { text = "Forest",  value = "FOREST",  r = 0.6, g = 1, b = 0.65 },
    { text = "Frost",   value = "FROST",   r = 0.6, g = 0.8, b = 1 },
    { text = "Arcane",  value = "ARCANE",  r = 0.8, g = 0.6, b = 1 },
    { text = "Command Blue", value = "COMMAND", r = 0.25, g = 0.5, b = 0.95 },
}

-- ---------------------------------------------------------------------------
-- Sounds: the suite's vetted list (every file below ships with this client).
-- ---------------------------------------------------------------------------
DATA.SOUNDS = {
    { key = "NONE",    label = "Silent", silent = true },
    { key = "WARNING", label = "Raid Warning", kit = "RAID_WARNING", id = 8959, file = "Sound\\Interface\\RaidWarning.wav" },
    { key = "READY",   label = "Ready Check",  kit = "READY_CHECK", id = 8960, file = "Sound\\Interface\\ReadyCheck.wav" },
    { key = "QUEST",   label = "Quest Chime",  kit = "IG_QUEST_LIST_COMPLETE", id = 883 },
    { key = "TOLL_HI", label = "Bell, High",   file = "Sound\\Doodad\\BellTollAlliance.wav" },
    { key = "TOLL_LO", label = "Bell, Low",    file = "Sound\\Doodad\\BellTollHorde.wav" },
    { key = "DOCK",    label = "Docking Bell", file = "Sound\\Doodad\\BoatDockedWarning.wav" },
    { key = "PING",    label = "Map Ping",     file = "Sound\\Interface\\MapPing.wav" },
    { key = "OPEN",    label = "Window Open",  file = "Sound\\Interface\\AuctionWindowOpen.wav" },
    { key = "LEVEL",   label = "Level Up",     file = "Sound\\Interface\\LevelUp.wav" },
}
DATA.SOUND_BY_KEY = {}
for _, snd in ipairs(DATA.SOUNDS) do DATA.SOUND_BY_KEY[snd.key] = snd end
-- The sound slots: which saved variable, which default, what it is for
DATA.SOUND_SLOTS = {
    { key = "SoundCrit",      label = "Big Crit",   default = "NONE",
      tip = "Rings when one of your crits is at least the Crit Chime From amount." },
    { key = "SoundKill",      label = "Killing Blow", default = "NONE",
      tip = "Rings on your killing blows." },
    { key = "SoundProc",      label = "Proc Ready", default = "PING",
      tip = "Rings when the client calls a reactive ability ready." },
    { key = "SoundInterrupt", label = "Interrupt",  default = "NONE",
      tip = "Rings when you land an interrupt." },
}

-- ---------------------------------------------------------------------------
-- Blizzard's own text, and the CVars that switch it off. Two families on
-- this client: the engine's numbers over units in the world, and the
-- LoadOnDemand Blizzard_CombatText addon that scrolls around your character.
-- Names verified by `strings` on the 2.5.6 binary and against the
-- classic_anniversary UI source (the _v2 suffix is real).
-- ---------------------------------------------------------------------------
DATA.CVARS_WORLD = {
    "floatingCombatTextCombatDamage_v2",
    "floatingCombatTextCombatHealing_v2",
    "floatingCombatTextCombatLogPeriodicSpells_v2",
    "floatingCombatTextPetMeleeDamage_v2",
    "floatingCombatTextPetSpellDamage_v2",
}
DATA.CVARS_PLAYER = {
    "enableFloatingCombatText",
}

# Commander Party Frames — Party Ability Bar

## Vision

A second row under every player on the board (allies AND yourself): the
**Party Ability Bar** — a hyper-curated strip of that player's key cooldowns,
inferred from the combat log, so the team's real options are readable at a
glance. This is the information war again: knowing the enemy kidney-shot the
priest matters less than knowing your mage still has Block, your paladin's
BoP is locked behind Forbearance, and Cold Snap is sitting ready to refund
everything. The bar must be *intelligent first, complete never* — a dumb
"every cooldown" tracker overflows instantly and reads as noise.

## Placement & anatomy

- One ability row per player row, directly beneath it, sharing the row's
  width and indentation. Shorter than a main row (~16px). Rendered from a
  dedicated insecure pool (same pattern as the personal rows — must work on
  the Click-Cast board and be positionable mid-combat).
- Content: up to `AbilityMaxIcons` (default 6) small icons, left-aligned.
  Each icon = the ability, with:
  - **Ready**: lit, full color. The quiet default — ready is the common state.
  - **On cooldown**: desaturated + radial sweep + small remaining text at
    ≥10s ("1.5m", "45"), text hidden under 10s (the sweep carries it).
  - **Relationship overlays** (see grammar below): rim color and/or a single
    corner pip. Never more than rim + one pip per icon.
- Master toggle `ShowAbilityBar` (default on for the mage layer), per-row
  suppression for DEAD/EMPTY rows. Board height accounting includes ability
  rows (they are part of the row stride when enabled).

## Curation: tiers, not lists

Per class+spec, abilities are tiered. The bar shows Tier 1 always; Tier 2
only while on cooldown (a used Trinket matters, a ready one is assumed);
never anything below.

- **Tier 1 (always visible, ready-or-not)**: match-deciding defensives and
  enablers. Mage: Ice Block, Cold Snap, Counterspell, (Frost) Summon Water
  Elemental, (Fire) Combustion/Dragon's Breath, (Arcane) Presence of Mind +
  Arcane Power. Priest: Psychic Scream, Pain Suppression (Disc), Power
  Infusion, Fear Ward, Shadowfiend, (Shadow) Silence. Rogue: Vanish,
  Preparation, Blind, Sprint, Evasion, Cloak of Shadows, Kick. Paladin:
  Divine Shield, BoP, Hammer of Justice, Blessing of Freedom, (Holy) Divine
  Favor, (Ret) Repentance. Warrior: Intercept, Pummel, Berserker Rage,
  (Arms) Death Wish? no — MS warrior: Intimidating Shout, Recklessness/
  Shield Wall by stance seen. Druid: Bash/Feral Charge (feral), Nature's
  Swiftness (resto), Innervate, Barkskin, (any) Rebirth. Warlock: Death
  Coil, Fear is spammable (NOT tracked), Fel Domination, (Destro)
  Shadowfury. Hunter: Intimidation, Scatter Shot, Freezing Trap is CD-gated
  → track trap cooldown, Deterrence, Bestial Wrath (BM). Shaman: NS (resto),
  Grounding Totem (10s CD — borderline; Tier 2), Earth Shock (interrupt →
  Tier 1 for enh/ele).
- **Tier 2 (visible only while cooling down)**: PvP trinket (all classes,
  detected by its spell cast), racials (WotF, Stoneform, Blood Fury...),
  long utility (Lay on Hands, Reincarnation).
- **Explicit noise list (never shown)**: rotational damage (Fire Blast, Cone
  of Cold, Arcane Explosion...), short offensive CDs < 20s unless they are
  interrupts, anything whose absence never changes a decision.

Data model: `ABILITY_BOOK[class] = { { spellIds={...}, cd=300, tier=1,
spec="FROST"|nil, kind="DEF"|"CC"|"KICK"|"OFF"|"UTIL", links={...} }, ... }`.
`spec=nil` = all specs. Cooldowns are BASE values; talent reductions (e.g.
Improved Preparation-likes) are accepted error — the bar rounds toward
pessimism and corrects itself the next time the ability is actually cast.

## Cooldown inference (no API exists for other players' CDs)

- CLEU `SPELL_CAST_SUCCESS` from tracked party GUIDs (and their pets where
  relevant) → look up in ABILITY_BOOK → stamp `cdEnd = now + cd`.
- Some abilities never emit CAST_SUCCESS reliably → fall back to
  `SPELL_AURA_APPLIED` on the caster (Evasion, Recklessness) or on a target
  (Psychic Scream). The book entry declares its detection event.
- State store: `abilityState[guid][entryKey] = { cdEnd, lastCast }`, pruned
  with the roster. Test board seeds representative states.

## The relationship grammar (the "hyper intelligent" part)

Three link types, each with ONE fixed visual so the grammar stays learnable:

1. **LOCKOUT (red rim)** — a debuff forbids recast independently of the CD.
   Ice Block ↔ Hypothermia (30s), Divine Shield/BoP ↔ Forbearance (60s).
   While the lockout debuff is live on that player (aura-scanned — we
   already scan party debuffs), the icon wears a red rim and the sweep shows
   the LONGER of (cooldown, lockout). Compact: one icon carries both facts.
2. **RESET (gold corner pip)** — another ready ability can refund this one.
   Cold Snap → Ice Block/Water Elemental (mage frost CDs); Preparation →
   Vanish/Sprint/Evasion/Blind. While the resetter is READY and the target
   is ON COOLDOWN, the target's icon shows a gold pip: "this cooldown is
   fake — it can come back instantly." When the resetter is spent, pips
   vanish board-wide for that player. The resetter itself is a normal Tier 1
   icon.
3. **PAIR (shared sweep)** — abilities that gate each other (future use:
   shared cooldowns). Reserved in the grammar; nothing ships with it in v1.

## Spec detection

No spec API in TBC — infer, and degrade gracefully:

- **Passive CLEU markers** (primary): `SPEC_MARKERS[class] = { [spellId] =
  "FROST", ... }` — 31687 Water Elemental→Frost, Combustion→Fire, PoM/AP→
  Arcane, Pain Suppression→Disc, Vampiric Embrace→Shadow, Tree of Life aura→
  Resto, Bestial Wrath→BM, Mutilate→Assassination, etc. First marker seen
  stamps `specState[guid]`; conflicting later markers overwrite (respec).
- **Aura markers** (secondary): forms/auras visible in our existing buff
  scans (Moonkin/Tree form, shaman... ) feed the same table.
- Until known: class-level Tier 1 entries only (spec=nil rows), and the
  identity display falls back to the class icon.
- `specState` is session-local; persist per-GUID in the DB later if it
  proves annoying to re-learn each login.

## Show Unit As additions

- **Specialization**: spec icon (talent-tree icon: Frost = Spell_Frost_
  FrostBolt02, etc.) replacing the class icon once spec is known; class icon
  until then.
- **Spec + Portrait**: spec icon beside the live portrait (mirrors the
  existing Icon + Portrait mode).
- Both reuse `unitIcon`/`unitIcon2` slots; `SPEC_ICONS[class][spec]` table.

## Settings (mage page first, chassis-level where sane)

- `ShowAbilityBar` (default on), `AbilityMaxIcons` (3–8, default 6),
  `AbilityBarSelf` (include your own row's bar, default on — you know your
  own CDs, but the bar doubles as a sanity check under pressure),
  `AbilityCdText` (default on). UnitDisplay gains SPEC / SPEC_PORTRAIT.

## Constraints and codebase patterns to respect

- Ability rows: insecure pool, positioned after each player row — the row
  stride becomes dynamic (ROW_H + ABILITY_H when that row's bar is shown).
  PositionRow grows an offset accumulator instead of fixed index math.
- Protected-frame rules: nothing about ability rows may anchor to regions
  of secure rows — anchor to `root` with computed offsets (the armorPop
  lesson).
- CLEU layout per the verified notes (sourceGUID param 4, spellId arg12).
- Spellbook-by-name for anything about OUR OWN knowledge; other players are
  CLEU-only.
- Priest layer gets the ability bar too — it is chassis, not mage-layer.
- Test board: every visual state seeded (ready / cooling / lockout-rimmed /
  reset-pipped / tier-2 trinket) without needing a group.

## Phases

1. **Foundation**: spec detection (markers + specState), SPEC/SPEC_PORTRAIT
   display modes, settings keys.
2. **Engine**: ABILITY_BOOK (all 9 classes, Tier 1+2, mage+priest deepest),
   CLEU inference, abilityState, lockout/reset link resolution.
3. **Render**: ability-row pool, dynamic row stride, icon painting with the
   grammar, test board states.
4. **Polish**: overflow eviction order (kind priority: DEF > CC > KICK >
   OFF > UTIL), tooltips on icons, adversarial review pass.

## Phase 5 — Tracked Abilities window (landed 2026-08-04, v4.1.0)

The book roughly doubled: every class gained opt-in extras (Frost Nova,
Ice Barrier, Avenging Wrath, Charge/Disarm/Sweeping Strikes, Feign Death,
Misdirection, Earth Shock, elemental totems, Swiftmend, Soulshatter, more
racials...) flagged `off = true` — present in the book but untracked by
default, so the curated default strip is pixel-identical until the user
opts in. "Intelligent first, complete never" now means the DEFAULT is
curated and completeness is a per-ability choice.

- A standalone movable window (`/cpf abilities`, or the Tracked Abilities…
  button in the settings' Party Ability Bar section) lists one row per
  class plus an "Everyone — racials & trinket" row: class icon, colored
  name, a live "n of m" tracked count, and a Choose… dropdown.
- Each dropdown lists that class's full book as stay-open checkboxes
  (`isNotRadio` + `keepShownOnClick`) with icon, name, and cooldown, a
  hover tooltip (kind, tier behavior, spec gate), and three quick-sets:
  Track all / Track none / Book defaults.
- Overrides persist account-wide in `AbilityTrack` keyed `entry.tok`
  ("CLASS:KEY", "*:KEY" for shared), storing only deviations from the book
  default — untouched abilities follow any later re-curation. The engine
  honors them in `StripConsider` (hoisted `stripTrack`).
- Untracked abilities still record casts in `abilityState` (and still feed
  spec inference), so enabling one mid-session shows any cooldown already
  observed.

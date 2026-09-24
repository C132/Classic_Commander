# Commander_Forecast — assumptions to verify in game

Both harnesses pass, which proves the parser, the arithmetic and the load/repaint path and
nothing about the live client. Numbered so a test session can report against them. A1–A4 decide
whether the module works at all; the rest degrade into a missing number on one icon.

The single most important thing to know before reading further: **the modeled number is
knowingly incomplete, and that is by design, not by omission.** Nothing in the TBC API reports
your talents or the percentage modifiers your buffs apply, so a modeled Fireball on a fire mage
reads perhaps 25–40% under the truth. The module's answer is not to guess at a talent database —
it is to measure. Once a spell has landed a few times the modeled number is thrown away and the
combat log's average takes its place, and that average knows every talent, buff, resistance and
armour value without having had to reason about any of them.

---

## A1 — `GameTooltip:SetSpellByID` exists and actually fills

**Load bearing for the whole modeled half.** The scanning tooltip is our own frame
(`CommanderForecastScanTooltip`), never `GameTooltip`, because other suite modules hook
`GameTooltip`'s methods and a scan is not a hover.

Per the client notes, a tooltip `Set*` can produce nothing without raising, so the fill is judged
by `NumLines() > 0` after a `ClearLines()`, never by `pcall` returning true — and there is a
`SetHyperlink(GetSpellLink(id))` fallback behind it.

Test: hover any damage spell on a bar with **Tooltip Breakdown** on. A modeled entry prints
"Direct", "Over time" and "Power × coefficient". If every spell instead prints nothing at all,
neither fill worked.

## A2 — An action button's slot is `button.action`

The repaint reads `button.action`, then `button:GetAttribute("action")`. Both are reads; nothing
here ever calls a setter on a Blizzard action button, in or out of combat.

Test: page your main bar (or shift into a form as a druid) and confirm the numbers follow. If a
paged bar keeps the numbers from page 1, this read is wrong for that bar.

## A3 — An insecure child frame may be parented to a protected action button

Protection propagates from secure CHILDREN upward, not from protected parents downward, so a
plain `CreateFrame("Frame", nil, ActionButton1)` holding one font string should be free to write
to in combat. The suite has verified the upward direction the hard way (Commander_PartyFrames);
the downward freedom is the standard behaviour every action-bar addon relies on, but it has not
been proven in this client by this module.

Test: fight something. If numbers freeze the moment combat starts, or BugSack shows
ADDON_ACTION_BLOCKED naming a `SetText`/`Show`, this is wrong and the overlays need to be
parented to UIParent and anchored to the buttons instead.

## A4 — Combat log argument positions

Taken from Commander_Meters' engine, which decodes the same layout in the field: for a `SPELL_`
prefix, `a12` spellId / `a13` spellName / `a14` school, then `_DAMAGE` = a15 amount, a20
absorbed, a21 critical; `_HEAL` = a15 amount, a16 overhealing, a18 critical; `_MISSED` = a15
missType.

Two deliberate choices inside that: **absorbed damage is added back in** (the shield is the
target's problem, not a smaller cast), and **healing uses the full amount including overheal**
(the question is what the cast does, not what the target had room for).

Test: `/cfc report` after a fight. The numbers should be recognisable as your actual hits.

## A5 — School indices for the character-sheet getters

`GetSpellBonusDamage(school)` / `GetSpellCritChance(school)` are indexed 1 Physical, 2 Holy,
3 Fire, 4 Nature, 5 Frost, 6 Shadow, 7 Arcane, as Blizzard's own PaperDoll loop uses them.

Test: on a character with school-specific spell damage (a Fire Mage in fire gear), the modeled
Fireball should scale with the *fire* number on the character sheet, not the lowest one.

## A6 — The parser reads your class's tooltip wording

**The known soft spot, and enUS only.** The parser is patterns over the spell's description
text. It is proven against verbatim TBC wording from mage, warlock, priest, shaman, paladin,
druid, rogue and warrior spells in `Harness/forecast_model_smoke.lua`, including the shapes that
fool a naive pattern: Immolate's two damage numbers, Prayer of Mending's "damage" that is not
damage, Power&nbsp;Word:&nbsp;Shield's absorb, Sunder Armor's duration masquerading as a heal,
and a mana potion masquerading as one.

What it will still get wrong somewhere: a spell nobody wrote a pattern for gets **no number**,
which is the correct failure — a blank icon, never a wrong number. The measured path then fills
it in the moment you cast it, because measurement never needed the tooltip.

Test: play for an hour and note any icon that stays blank after you have cast it several times.
That combination — blank AND cast repeatedly — is the only real bug shape here, and it means the
combat log path missed it too.

## A7 — `GetMacroSpell` returns a spell ID

Handled either way (number → the ID, string → resolved through `GetSpellInfo`), so this one only
decides which branch runs.

Test: put a `#showtooltip` macro on a bar and confirm it carries the same number as the spell.

## A8 — `GetCombatRatingBonus(CR_HIT_SPELL)` exists

Guarded: absent, spell hit reads 0 and the modeled miss chance is the raw level table. Affects
the modeled average only — the measured average derives its miss rate from your own misses.

Test: `/dump GetCombatRatingBonus(CR_HIT_SPELL)` on a character with hit gear.

## A9 — What the model cannot see, and does not pretend to

Listed so nobody debugs them as faults:

- **Talents and percentage buffs.** No API reports them. Modeled numbers read low; measured ones
  do not. This is the reason the module measures at all.
- **Downranking.** TBC's rank penalty needs the spell's own base/max level, which the client does
  not expose. A modeled low rank therefore reads too high. Measured ranks are correct, and each
  rank is its own spell ID with its own record.
- **The AoE coefficient penalty.** Not detected from tooltip text; a modeled AoE reads high.
- **Armour mitigation** on physical abilities. There is no armour value for a hostile target, so
  the modeled swing is pre-mitigation and reads high. Measured swings are post-mitigation.
- **Partial resists** on the modeled side, for the same reason.

## A10 — Sample buckets and the victim's level

Samples are filed per spell ID by (is-a-player, level difference clamped to ±3). The victim's
level is only knowable while a token is held on them — target, focus or mouseover — and in
practice you cast at what you target. When it is not knowable the cast files into the same-level
bucket. `BestRecord` falls back from the exact bucket to the fullest one there is, and the
tooltip says "(other targets)" when it has done so.

Test: hit a training dummy, then hit a level 70 mob, and confirm the tooltip stops saying
"(other targets)" once the second bucket fills.

## A11 — `SavedVariablesPerCharacter`

The learned log is per character, which is the only correct scope for it: your rogue's Sinister
Strike is not your mage's Fireball. Settings stay account-wide like every other suite module.

Test: learn something on one character, log to another, and confirm `/cfc report` is empty there
while the settings page still remembers your options.

## A12 — Spell text is asynchronous, and the first field session proved it

**Found 2026-09-10: Ice Lance had no number.** The tooltip scan at login came back with the spell
name and nothing under it, parsed to nothing, and that nothing was cached for the session. The
fix is structural: `M.SpellProfile` never caches an EMPTY description (it requests the data via
`C_Spell.RequestLoadSpellData` and retries on later repaints), and `SPELL_TEXT_UPDATE` /
`SPELL_DATA_LOAD_RESULT` drop whatever was learned about that spell ID. Only a description that
was actually read and still parsed to nothing is final.

Both event names are registered under `pcall`; if neither exists on this client the retry path
alone still heals the icon within a few repaints, because every context change invalidates the
cache.

Test: log in, look at the bar within the first second, and confirm every damage spell has a
number by the time you have targeted something.

## A13 — What counts as Frozen

Ice Lance's "triple damage against Frozen targets" is switched on by a combat-log map of freeze
auras, by victim GUID, from ANY source: Frost Nova, Frostbite, the Water Elemental's Freeze, and
Freezing Trap Effect (Shatter counts it, so this should too). Learned from CLEU rather than the
aura API so that an Ice Lance's own damage event — which arrives BEFORE the `SPELL_AURA_BROKEN`
its hit causes — is still filed as a hit into a frozen target. Those hits live in their own
bucket variant (`n3f`) and are never averaged with unfrozen ones.

Test: Frost Nova a mob and watch Ice Lance's number triple the instant the nova lands, then drop
back when it breaks. Hover it while frozen: the tooltip shows "Target is Frozen ×3". If a freeze
you know of does not flex it, its aura name is missing from `FREEZE_AURAS` in
CommanderForecast.lua — report the name.

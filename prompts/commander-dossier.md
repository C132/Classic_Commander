# Commander_Dossier — the intelligence file on the enemy

## The one-line pitch

Every other module in the suite watches *you*. This one watches *them*: what
crowd control still lands on that warlock right now, and who that warlock is —
what you have seen them cast before, what spec that makes them, and how many
times they have killed you.

## Why it does not exist yet

The suite has thirty-odd modules and every one of them faces inward. Meters
counts your damage, Threat counts your threat, PartyFrames keeps your team
alive, Afflictions tracks your debuffs, Talents plans your build. Radar is the
closest thing to enemy-facing and it only answers "is someone there".

Nothing in the suite answers the two questions that actually decide a TBC arena
game:

1. **Can I re-CC this target, and for how long?** Diminishing returns are the
   whole economy of TBC PvP. A fear at full duration is a won game; a fear at a
   quarter is a wasted global and a dead healer. The information exists in the
   combat log and nowhere on screen.
2. **Who am I fighting?** Arena is a small world. The same names come back.
   Their class is on the nameplate; their *spec* is not, and neither is the fact
   that they opened with Shadowstep on you twice last week.

Both are enemy intelligence. That is one module: a live tactical board and a
persistent file.

## Pillar and identity

- Pillar: **Command & Control**, after Radar. Radar finds them, Dossier reads them.
- Key `Dossier`, slash `/cdossier` (+ `/cdoss`), bare command opens the file
  window (the Quartermaster `[""]` override).
- SavedVariables are **two**, the Quartermaster precedent: `CommanderDossierDB`
  for settings and `CommanderDossierFile` for the intel. Restoring settings to
  defaults must never wipe intelligence gathered over months.

## Half one: the DR board (live)

One row per player carrying a live diminishing-return window; a strip of
category pips per row. Each pip says what the **next** application of that
category will land at:

    FULL  (green)   →  ½ (yellow)  →  ¼ (orange)  →  IMMUNE (red)

with the seconds until the window resets. Categories with no window are hidden
unless "Show All Categories" is on, so a fresh target is an empty row and a
kited healer is a wall of colour — the board's density is itself the read.

Rules, from the DR canon (see DECISIONS D2 for sourcing):

- Windows are per **(unit, category)**, not per spell.
- The reset clock runs **from the moment the effect fades**, not from when it
  landed. A 20-second window is the safe read of TBC's dynamic 15–20s reset.
- Three applications and the fourth is immune.
- Against **NPCs** only `stun`, `random_stun` and `kidney_shot` diminish at
  all; everything else is a PvP-only rule and the board must not lie about it.
- Silences do **not** diminish in TBC. Not a category, not a pip. (Unstable
  Affliction's silence is its own self-only category, which is why it appears
  and Counterspell does not.)

Both directions are worth watching, so the board takes a mode: enemies (when
can I re-CC), allies (when will their fear land full on my healer), or both.

## Half two: the file (persistent)

Every enemy player the combat log names gets a record, keyed Name-Realm,
account-wide:

- class, race, guild, level, faction, first seen, last seen, last zone
- encounters (a fresh one after a five-minute gap), your kills, your deaths
- every spell of theirs you have witnessed, with counts
- an **inferred specialisation**
- a free-text note you write yourself

### Spec inference without new data

This is the part worth being proud of. The suite already owns a DBC-verified
TBC talent grid — nine `CommanderTalentsData_<Class>.lua` files, every name,
row and column checked against wowsims snapshots. A talent that grants an
ability shares its name with that ability, and a talent that grants a proc
shares its name with the proc's aura. So:

> Index every talent name in the verified grid. When an enemy of known class
> casts something whose name is in their class's index, score that tree by the
> talent's **row** — depth is evidence. Mortal Strike is row 7 Arms; Blackout is
> row 3 Shadow; Shadowstep is row 9 Subtlety and is very nearly proof.

Zero new static data, zero new verification burden, and it inherits the talent
grid's accuracy for free. Commander_Talents is an **OptionalDep**: without it
the file still records everything and simply never names a spec.

## Non-goals

- **Not an enemy cooldown tracker.** Trinket and defensive-cooldown timers need
  a spell table this module would have to verify from scratch, and getting it
  half-right is worse than not shipping it. BACKLOG, not v1.
- **Not a scoreboard or an arena mod.** No match history, no MMR, no team
  tracking.
- **Nothing leaves the client.** The file is yours; there is no export to chat
  of another player's record, no automatic callout naming a person. The DR
  board may optionally call out *categories* to party chat, which is a fact
  about the fight, not about a person — and per suite policy it defaults off.

## Shape

Five files, the Meters/Threat three-layer shape plus data:

    CommanderDossierData.lua     categories, spell → category, verified
    CommanderDossierEngine.lua   pure Lua: DR ledger, records, inference
    CommanderDossierDB.lua       settings panel, migration ladder
    CommanderDossier.lua         CLEU wiring, DR board, file window
    Harness/                     engine fixture + UI smoke, luajit

Conventions the suite already fixed and this module must not re-litigate: HUD
chrome last on the settings page, scrollable panel via the instance-level
`AddRow` override, a tester (`/cdossier test`) because it draws something, a
reporter (`/cdossier report`) because it accumulates something, epoch `time()`
for everything persisted, and the pure engine gets a fixture harness that runs
under luajit with no client.

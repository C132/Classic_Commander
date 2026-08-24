# Commander_Dossier — decisions

Numbered so code comments and future sessions can cite them.

## D1 — Two SavedVariables, not one

`CommanderDossierDB` holds settings; `CommanderDossierFile` holds the intel.
The Quartermaster ledger precedent. Restoring settings to defaults must never
cost a player months of gathered records, and the two have completely
different lifetimes. Restore Defaults says so in its tooltip and prints "the
file is untouched"; only `/cdossier wipe` (which asks first) can empty it.

## D2 — The DR canon is sourced, not remembered

Categories, spell ids, the 20-second reset, the 100/50/25/immune ladder and
the PvE exemption list were all checked against the ecosystem's DR library
(`wardz/DRList-1.0`, its `tbc` branch) rather than written from model memory.
The suite has already paid for the other approach once: the memory-generated
Commander_Talents classes shipped with a missing Aura Mastery, a shifted
Protection column and nine missing Druid arrows, all caught later by a
verification sweep.

Three TBC-specific facts that this sourcing changed, and which a plausible
guess would have got wrong:

- **Silences do not diminish in TBC.** No silence category exists. Counterspell,
  Spell Lock, Silencing Shot and Garrote-Silence are all free, forever.
  Unstable Affliction's dispel-silence appears only because it diminishes
  with *itself*.
- **Blind and Cyclone are their own pair** (`disorient`), sharing with each
  other and with nothing else — not with fear, which is the intuitive guess.
- **Kidney Shot has its own category**, so it is undiminished after a Cheap
  Shot. Getting this wrong would mis-advise the exact opener the module exists
  to help with.

## D3 — The combat log is the only source

There is no unit token for "the warlock over there" in TBC outside arena, so
an aura scan cannot see most of the players whose windows matter. The combat
log reports every application and every fade in its range whether or not
anything is targeted. The price is that coverage equals combat-log range, and
the option tooltips say so rather than pretending to omniscience.

Consequence: the module registers `COMBAT_LOG_EVENT_UNFILTERED` and does its
own filtering, which is the standard cost of this data source.

## D4 — The reset clock starts at the FADE

Not at the application. A four-second stun followed by twenty seconds of
freedom is a reset; a four-second stun read as "window started when it landed"
would promise a reset four seconds early, which is exactly the error that
loses a game. `E.Level` therefore reports **no countdown at all** while the
effect is up (the pip reads "up"), because the window has not begun.

## D5 — Level 3 is both the cap and the alarm

Three applications exhaust the ladder: the third lands at a quarter, the
fourth does not land. So level 3 means "the next one is refused", which is
simultaneously the highest level worth storing and the only moment worth
sounding a klaxon over. The first draft capped at 4 and alarmed at 4, which
meant the alarm never fired — caught by the engine harness.

## D6 — A CC we never saw fade gets a guard, not a pin

If the target leaves combat-log range mid-polymorph, no fade event arrives.
Without a guard that window stays "up" forever and the board lies for the rest
of the session. `D.MAX_ACTIVE` (50s, the longest relevant TBC crowd control)
releases it and starts the reset from there. Erring toward "the window has
reset" is the safe direction: you expect less duration than you get.

## D7 — PvE exemptions are honoured, not smoothed over

Only `stun`, `random_stun` and `kidney_shot` diminish against creatures. A
pair that does not diminish never opens a window at all, so the board can
never show a fear pip on a boss. It would have been less code to track
everything and let players ignore the wrong rows; it would also have been a
board that lies.

## D8 — Spec inference reuses Commander_Talents, and scores by depth

The suite already owns a DBC-verified TBC talent grid. A talent that grants an
ability shares its name with that ability, and a talent that grants a proc
shares its name with the proc's aura, so an index of talent names is a
signature table that needed no new verification.

Scoring is **per distinct talent, weighted by row**, never per cast. Depth is
the evidence: anybody can have a row-1 talent, and a row-9 talent is very
nearly proof. Weighting by cast frequency would let a spammed filler outvote a
41-pointer, which the harness now asserts against.

Below `MIN_EVIDENCE` (3 row-points) the module says "not enough witnessed"
instead of guessing. Without Commander_Talents it says "needs Commander_Talents"
and records everything else regardless — and because the verdict is derived
lazily, records gathered before Talents was installed gain their spec the
moment it appears.

## D9 — A meeting, not a message

`ENCOUNTER_GAP` is 300 seconds. Every combat-log line from a player refreshes
their last-seen stamp, but only a line after five minutes of silence counts as
a new meeting. Otherwise "met 400 times" would mean "was in one long
battleground with them".

## D10 — Deaths are attributed to the last attacker, within a window

The combat log's `UNIT_DIED` does not name a killer. The module remembers
whoever last damaged the player and credits them if the death follows within
`KILL_WINDOW` (10s). A fall death half a minute after an arena belongs to
nobody, and the culprit is consumed on use so one attacker cannot collect two
deaths from one hit.

## D11 — The nemesis is whoever kills you most, not whoever leads on net

The first draft picked the largest `deaths - kills`, which hid a rival you
have fought twenty times evenly behind a stranger who ganked you twice. Picked
on their kill count, tie-broken toward whoever you have beaten less.

## D12 — Ten settings and the chrome block

`EnableDossier`, `BoardMode`, `ShowAllCategories`, `CombatOnly`, `ImmuneWarn`,
`BarRows`, `FrameWidth`, `RecordIntel`, `KeepDays`, `AccentColor`. Board
side-selection is a mode rather than two booleans because "enemies and allies
both off" is not a state worth being able to reach — that is what Hidden is.
`FilePos` is widget-less window state and deliberately outside the defaults so
a settings reset does not move a window the player placed.

## D13 — No enemy cooldown tracking in v1

Trinkets, Ice Block, Divine Shield and the rest would need a spell table
verified from scratch, and a cooldown tracker that is half right is worse than
no cooldown tracker — a player who trusts a wrong "trinket is down" loses the
game they would otherwise have won by assuming the worst. BACKLOG.

## D14 — Nothing leaves the client

No export of another player's record to chat, no automatic callout naming a
person, no sharing. The suite's public-output policy governs flavour and
informational callouts; a dossier on a named human being is neither, so the
answer is simply that this data has no outbound path at all.

## D15 — Truncate before sorting

`E.Board` reuses one scratch array. `table.sort` sorts the whole array, so
clearing the tail after sorting let a leftover unit from a busier tick take
part in the sort and land inside the drawn rows. Clear first, then sort. The
engine harness now arranges for the *busiest* unit to be the one that lapses,
so the regression cannot pass by luck.

## D16 — Witness events are casts and auras, never damage

`SPELL_CAST_SUCCESS`, `SPELL_AURA_APPLIED`, `SPELL_SUMMON`, `SPELL_RESURRECT`.
Damage events repeat the same handful of names hundreds of times a fight and
would add nothing to a table keyed by name — the inference scores distinct
talents, so volume is not evidence anyway.

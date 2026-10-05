# Commander Diminish — harness

Four checks and no generator. Nothing here runs in the game; everything here
runs without it, which is the point.

```
luajit  Harness/diminish_engine_smoke.lua      the rules
luajit  Harness/diminish_board_smoke.lua       where a strip sits, and what it wears
python3 Harness/order_lint.py                  use-before-declaration
python3 Harness/settings_reach.py              every setting has a control
```

`diminish_board_smoke.lua` loads all four files over a small WoW mock and
covers the two decisions the engine cannot see. The **icons**: a ladder wears
its category's own picture (Hammer of Justice for a stun, Polymorph for the
polymorph ladder) rather than whichever spell last opened it, unless the Icons
setting asks for the other. And the **placement**: by default a strip is
embedded on the frame of the person it is about -- an ally's Commander Party
Frames row (through `CommanderPartyFrames_RowFor`), a unit frame for the
target and focus -- is not drawn at all for an arena enemy Commander Arena
Frames already carries (`CommanderArenaFrames_ShowsDR`), and comes down with
the module when it is switched off even though it is parented to somebody
else's frame.

## Where the spell table comes from

`CommanderDiminishData.lua` carries a generated block — sixteen groups and 884
spells — and **this module does not own the generator**. There is one, in
Commander Arena Frames:

```
python3 ../Commander_ArenaFrames/Harness/make_dr_table.py --csv <dir> --out dr.lua
```

It transcribes the server's own classifier (CMaNGOS `mangos-tbc`
`GetDiminishingReturnsGroupForSpell`) over the client's own mechanic and
spell-family columns, which is what makes the result an implementation of TBC's
rules rather than a list somebody typed. Its README explains the three
hand-maintained parts and the traps in the DB2 columns.

Two addons, two copies of its output, one generator. The copies exist because
this tracker has to keep working with Arena Frames disabled — and turning an
arena module off before a battleground is exactly the thing a person does. A
second *generator* would be a different matter: two transcriptions of one
classifier can disagree, and then neither is authoritative. So the generator
stays single, and after a client patch the same block is pasted into both data
files.

The copies drifting apart is caught rather than trusted: **section A of the
smoke test diffs this module's table against Commander Arena Frames'**, id by
id, and fails on any mismatch — a regenerated table pasted into one file and
not the other is a red test, not a bracket that is quietly wrong six weeks
later. With Arena Frames absent the section says so and skips, because a
missing neighbour is not a failure.

## What the smoke test is actually asserting

Not the data pipeline — the *rules*. Each check is a claim about TBC that would
survive a regeneration, and if one ever stops holding, that is a change in the
game's behaviour and deserves to be read rather than re-baselined:

* **the reset clock starts on the FADE.** Section C stuns at t=100, ends it at
  t=104, and asserts the category is still halved at t=116. A tracker that
  stamps the apply says "full" there, and is wrong by exactly the length of the
  CC that opened the ladder — worst precisely on the long first cast.
* **the clock freezes while anything in the category is up.** Section D
  overlaps two people's stuns and checks the fifteen seconds do not start when
  the first one drops.
* **broken CC ends a ladder.** Section E. `SPELL_AURA_BROKEN` fires *instead of*
  `SPELL_AURA_REMOVED`, and in a battleground almost every CC you land is
  broken by somebody's cleave. Miss it and the bracket sticks all game.
* **the categories people get wrong.** Section B: Kidney Shot on its own ladder,
  proc stuns separate from cast stuns while Charge and Intercept are *not*,
  Freezing Trap not on the Polymorph ladder, and silence carrying no bracket at
  all — silence DR is a 3.0.8 rule and does not exist here.
* **a refresh is a new cast, not a second aura.** Section E2. `SPELL_AURA_REFRESH`
  means the CC was re-cast on someone still under it: the server walks the
  ladder, but there is still only one aura and only one removal will ever
  arrive. Counting it as a second stack leaves the category permanently
  one-deep — the clock never starts and it reads as held for the rest of the
  game. This was a real bug, found by tracing a re-sheep.
* **the ladder is checked against the server.** Section E3. Everything else here
  is inference from the combat log; the duration the server put on the aura is
  not. A 10-second polymorph landed at full and a 5-second one at half, and
  where the reading disagrees with the model the reading wins — silently
  correcting the ladder, and loudly enough to appear in `/cdr log`, because a
  disagreement is the most useful thing this module can report. Full durations
  are learned per spell (the longest ever seen), which self-corrects when the
  first CC you ever watch was already diminished.
* **an observation with no combat log behind it.** Section E4. `Observe`
  creates ladder entries and every other writer stamps the reset clock; this
  one did not, so a CC seen on someone whose `SPELL_AURA_APPLIED` never reached
  us minted a row with `used` counted and no clock at all. That row could never
  expire, so its bracket stuck for the rest of the game — and `ResetAt` walked
  into `nil + 15` from inside a draw that runs every frame. Every other Observe
  test runs on a GUID that `Applied` touched first, which is why it shipped.
  E4 also pins the stamp to the aura's EXPIRY rather than the moment it was
  read: observation runs off `UNIT_AURA`, so nothing re-reads a polymorph
  quietly running its course, and stamping the read calls the category full
  while the target is still standing there sheeped.
* **the tailoring.** Section F builds profiles out of spell ids and checks the
  answers change with the talents: the same class, two builds, one Dragon's
  Breath row between them.
* **it forgets people.** Section H runs forty battleground GUIDs through and
  checks they are all dropped once their ladders reset — and that somebody
  still stunned never is, however long the fight runs.

`CAT_ICON` is checked too (A6), and that check has already earned its place: the
fallback for Freezing Trap was the spell that *lays* the trap, which has no
ladder at all. The one that diminishes is the aura the trap applies.

## When a bracket turns out to be wrong

`/cdr log` records every DR event with a timestamp — what arrived, what the
ladder did with it, and every place the ladder disagreed with the duration the
server actually handed a CC:

```
  1841.2  APPLIED  POLY       Someone -> next is half
  1851.4  FADED    POLY       Someone -- full again in 15s
  1867.9  APPLIED  POLY       Someone -> next is half
  1868.0  CORRECT  POLY       Someone landed at half (5.0s of 10.0s) -- ladder said full
```

A `CORRECT` line is the whole diagnosis: the gap between the `FADED` stamp and
the `APPLIED` one is how long the category really needed, against the fifteen
seconds the ladder allowed it. One game of that settles a rules argument that
impressions never will.

## The other two

`order_lint.py` compiles each file with luajit and flags any name read as a
global that the same file declares as a local — always a call sitting above the
`local function` it names, which compiles to a nil global lookup and fails only
on the branch that runs it. In a combat addon that branch can easily need an
enemy to press a specific button.

`settings_reach.py` walks the settings table, the tracker, and the page, and
reports the two mismatches that are bugs: a setting the tracker obeys that no
control can change, and a control that writes a setting nothing reads.

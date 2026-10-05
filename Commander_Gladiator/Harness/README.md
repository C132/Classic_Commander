# Commander Gladiator — harness

Two checks and no generator. Nothing here runs in the game; everything here
runs without it.

```
luajit  Harness/gladiator_engine_smoke.lua    the rules, the data, the balance   (1326 checks, about 36 s)
luajit  Harness/gladiator_ui_smoke.lua        the window over a WoW mock         (921 checks, about 7 s)
```

Both print `N checks, 0 failures` and exit non-zero on a red line. Both turn
the JIT off: the client is plain Lua 5.1, and the engine's branchy loops are
faster interpreted on this machine anyway.

The count is the last line of a run, and for the UI smoke it is the last
line whatever a check or a section did — see "A widget the window never
painted" below. The one exception is a shipping file that will not compile
or errors while loading: the UI smoke stops there, naming the file.
In a red run the count of checks can be lower than 921: a section that
stopped on an error is one failed check, and the checks it never reached are
not counted.

## Which one to run

**Touched a number in `CommanderGladiatorData.lua`, or anything in the
engine: run both, the engine smoke first.** The balance is an average over
openings and it is sharp. Which enemy each side opens on is rolled; side A
wins a little over three matches in five when side B opens on the rogue and
a little over one in three when it opens on the priest; and fifty health on the
warrior is worth about four points of win rate. So sections E and F are the
receipt for the tuning, not a formality. Their thresholds are the brief's; a
red line there means retune the data, not widen the line.

The UI smoke is in that sentence because a retune reaches it too. Every seed
plays a different match after one, and section A of the UI smoke plays the
twelve matches a fresh install is dealt first (the default `Seed` in
`CommanderGladiatorDB.lua`, 104 today) and wants a win to open on, five to
seven wins in the twelve, and no run of more than three. When that goes red
the fix is another default seed, with its twelve results written beside it.

The engine's two verbs reach it as well: section M of the UI smoke plays
two hundred matches by clicking on the window and holds them, seed for seed,
to the same policy played straight on `match:Pin` and `match:Tap`.

**Touched the window, the settings file or the `.toc`: run the UI smoke.**

## What the engine smoke defends

A match is a pure function of two team lists and a seed, so there is no mock:
the two files are loaded and played.

| | |
| --- | --- |
| A | the data: every ability row speaks only the two vocabularies (twelve effect kinds, five targeting rules), every icon is a path, both teams resolve, side B's marks are side A's mirrored |
| B | determinism: one seed, one event log, byte for byte; and the event shapes the window is told to expect |
| C | each effect kind and each rule on its own, on hand-built situations that start AWAY from the defaults, so a check cannot pass by restating one. The player's two verbs are here: a pin set, moved, released, refused, cleared by a death and made at the gates; a pin that will not break the team's own sheep; what lights a big spell and each thing that does not; a tap that fires at once, starts the beat again and is refused when not lit |
| D | rules of play, audited over five hundred seeded matches from the event log alone: no hitting the sheep, no crowd control on the kill target, nobody acting while disabled or dead, nobody off the floor, no heal or shield pressed for nothing, nothing mending or guarding a routed side, nobody routed while the other side has no damage dealer alive, no routed side winning or drawing. Then a fuzz of teams nobody tuned — every twenty-third of the 46,656 ordered pairings of three specs against three, and one pairing by name: 2030 matches — held to six things: no error, an ending, END as the last event, the last two rules of the audit, and the side that did the routing taking no damage afterwards. Then both again with a hand on side A: the whole audit over six hundred preset matches played by a scripted good player and a careless one, with fourteen rules a hand adds (a tap fires only what was lit and only on its rule's target, a pin never points at the dead or at the player's own side, the team leaves a pin only while it is sheeped, feared or cycloned, side B never pins or taps) and "nobody pressed twice inside one beat" restated for the presses a unit makes by itself; and the 2030 again with careless input on side A, held to the same six |
| E | endings, balance and variety over 1000 seeds of the preset matchup: who wins, how long it takes, how soon a rout becomes a kill, and that the matches are not all one match (openings, kill orders, who dies first, every spell pressed in at least nine matches in ten) |
| F | side fairness: the same team on both sides, 1000 seeds each |
| G | hands. The fingerprint: one checksum over the event logs of seeds 1 to 200, recorded from the engine before it had a pin or a tap, which an untouched match must still give — and still give with every unit asked twice a tick whether it is lit. It is recorded again only with a deliberate retune, never to make a red line go away. Then what a hand is worth over seeds 1 to 1000, side A played by a script: nobody 0.46 to 0.54, the good player 0.62 to 0.78, the careless one no more than three points above nobody, the good player with slow hands at least five points above, and at most nine inputs a match |

As measured on the files as they are now, over seeds 1 to 1000, which is the
range sections E and F assert on:

- side A wins 0.504 of the preset matchup, side B 0.495, and one match in the
  thousand is a draw;
- a match runs 29.2 s on average (median 27.7 s, 95th percentile 42.1 s,
  longest 59.4 s, none at the 90 s cap);
- 0.363 of matches have a rout, and the kill follows it in 4.3 s on average
  and 8.8 s at the worst;
- the side with the first kill wins 0.674 of decided matches, and there are
  143 distinct kill orders;
- each side opens on each of its three enemies in about a third of matches
  (0.315 to 0.356);
- the least-pressed spell is Fear, in 0.927 of matches;
- the mirrors come out at 0.507 (team A both sides) and 0.472 (team B both
  sides) for the left side.

With a hand on side A (section G, the same thousand seeds): the scripted
good player wins 0.764 at 5.6 inputs a match (7 at the 95th percentile) and
0.638 with slow hands; its pins alone 0.633, its taps alone 0.608; a random
legal input every second and a half 0.058; three random inputs in the first
ten seconds 0.275. On seeds 30001 to 31000 and 60001 to 61000, measured and
not asserted, the good player is at 0.779 and 0.765 against 0.510 and 0.510
for nobody.

On seeds the tuning never saw (10001 to 11000, measured and not asserted):
side A 0.520, 29.2 s on average, 95th percentile 43.4 s, longest 55.9 s, and
mirrors of 0.525 and 0.526.

### The rout, block by block

A side is routed when it has nothing left that takes health — no damage
dealer alive, none of its dots on a living enemy — and the other side has a
damage dealer **alive**. A dot the dead left behind keeps a match going and
routs nobody. From the rout on nothing heals that side and no new shield
goes up on it (one already up soaks until it is spent), its
healer presses no damage-taken buff (Pain Suppression) on it, every hit on
it lands twice as hard, and it has lost: the match ends on the kill, or at
the cap for the other side.

Section E asserts two things about the wait from ROUT to END, on seeds 1 to
1000: at most 5 s on average and at most 14 s at the worst. The second line
used to be 12 s, drawn from that one block, and was not true of the next
ones. It was set again from these twenty blocks of the preset matchup, on
the files as they are now:

| seeds | side A wins | routs | ROUT to END, mean | worst |
| --- | --- | --- | --- | --- |
| 1 to 1000 | 0.504 | 363 | 4.34 s | 8.8 s |
| 1001 to 2000 | 0.552 | 379 | 4.60 s | 8.9 s |
| 2001 to 3000 | 0.484 | 384 | 4.40 s | 8.7 s |
| 5001 to 6000 | 0.518 | 379 | 4.44 s | 10.9 s |
| 10001 to 11000 | 0.520 | 379 | 4.38 s | 10.2 s |
| 20001 to 21000 | 0.494 | 388 | 4.43 s | 11.0 s |
| 30001 to 31000 | 0.510 | 367 | 4.33 s | 10.2 s |
| 40001 to 41000 | 0.503 | 340 | 4.42 s | 10.8 s |
| 50001 to 51000 | 0.531 | 371 | 4.45 s | 9.3 s |
| 60001 to 61000 | 0.510 | 386 | 4.47 s | 9.9 s |
| 70001 to 71000 | 0.526 | 370 | 4.36 s | 8.8 s |
| 80001 to 81000 | 0.500 | 369 | 4.31 s | 11.0 s |
| 90001 to 91000 | 0.488 | 374 | 4.24 s | 8.7 s |
| 100001 to 101000 | 0.521 | 361 | 4.51 s | 8.7 s |
| 250001 to 251000 | 0.529 | 380 | 4.35 s | 10.0 s |
| 500001 to 501000 | 0.476 | 387 | 4.50 s | 9.8 s |
| 1000001 to 1001000 | 0.453 | 359 | 4.47 s | 11.7 s |
| 5000001 to 5001000 | 0.518 | 393 | 4.53 s | 10.2 s |
| 12345001 to 12346000 | 0.487 | 399 | 4.36 s | 12.2 s |
| 99990001 to 99991000 | 0.546 | 355 | 4.36 s | 10.0 s |

and from eighty more (the blocks starting at 13001, 26001 and so on, every
13,000 seeds up to 1040001), whose means ran from 4.19 s to 4.60 s and whose
worsts from 8.3 s to 11.8 s. Over all hundred — 37,893 routs — no block's
mean is above 4.60 s and the slowest ending is 12.2 s, so the line at 14 s
has 1.8 s to spare on these. An independent check on 240 further random
blocks found a slowest ending of 12.7 s and a largest block mean of 4.63 s,
so the true margin is nearer 1.3 s. Before Pain Suppression was refused on a routed side the
same twenty blocks had means of 4.32 s to 4.71 s and three worsts over 12 s
(12.1, 12.2 and 12.4).

What is left at the slow end is not a buff. The two slowest in the table,
seeds 12345720 and 1000414, are the same ending: a routed druid at full
health Cyclones the last rogue, who then has to cross the floor to her, stun
her and Shadowstep before the first hit lands. A routed side's crowd control
is still pressed; only its heals, new shields and damage-taken buffs are
not. The other slow ending, seen among the eighty (seed 702546, 11.8 s), is
a finisher who cannot act yet: a warlock still a sheep when the rout is
said.

The win-rate column is there because it was measured in the same run, and it
is a warning about reading one block: side A's share runs from 0.453 to
0.553 over the hundred blocks (mean 0.508), and seven of them are outside
0.46 to 0.54. The two ranges the tuning is held to, 1 to 1000 and 10001 to
11000, are inside it at 0.504 and 0.520, exactly where they were before the
rout was tightened: no number in the data file was changed for it.

Teams nobody tuned are another matter, and the fuzz in section D is a sample
of them. Played in full on three seeds each — 139,968 matches — the 46,656
pairings raised no error, never reached the cap, never routed a side with
nobody alive to finish it and never let a routed side win or draw; on the
engine as it was before, the same three runs had 99 routs by a dead unit's
dot and five routed sides that won or drew. The slowest ending in them is
23.7 s after the rout, which the preset's 14 s line says nothing about.

## What the UI smoke defends

It loads the four shipping files in `.toc` order — read out of the `.toc`,
so the order is written once — opens the window with the slash command,
drives whole matches through the real `OnUpdate` with fake frames, and
asserts on **what was painted**: the texture on a token's face, the cooldown
a health ring was handed, the point a shadow was anchored to. Not on what
the window believes about itself.

| | |
| --- | --- |
| A | login: defaults fill in round a saved record and seed, `/cglad` exists, Restore Defaults keeps the record and forgets that the hint was followed, nothing is built or shown — and the first twelve matches a fresh install is dealt are a fair opening |
| B | open: the window where a window never dragged opens, registered for the drag it is scripted for, top-level and clamped; a match from the saved seed, **held at its gates** with the countdown over the heads of the back row; six tokens dressed and placed, the three enemy ones taking the mouse and the three of yours not; **the bar** — three buttons in slot order, centred, each at least 36 px, wearing its gladiator's big spell, class colour and short name, clear of the floor's slab and inside the window; the hint in two halves either side of it, clear of the floor — then **every one of the 5151 places on the engine's floor**: feet on the painted floor, token inside the window and under the header, its name clear of the bar, never touching a pillar |
| C | a whole match: the gates hold it for two seconds with every token on its mark, and the frame that opens them takes no tick; then tokens glide between ticks, a thirty-second frame costs exactly the step cap and leaves no backlog, the banner says the right word in the right colour on its band, the record moves by one, nobody can be clicked and no button glows after the bell, and the next match is dealt from the next seed, at its gates |
| D | what is painted, forced through the engine's own doors, in five parts. **States**: the sheep's face and its return, the ring at 590 of 900 (on a mock machine up for more than a day, and once at a young uptime), the shield rim to its last point, the glow, the frost icon clear of the name and the mark, the stun pin, cyclone, fear, the two kill marks, the dead dimmed and sunk, a teleport — then a clean slate at the next deal, a deal of six *different* units (tokens, buttons and tooltip alike), and one of a class the client has no badge for. **What flies**: how each of the eighteen rows is delivered, and one of each in the air — a projectile at the right point of its arc, a bump toward its target, a call-out above its token that fades and goes, numbers side by side in their lanes that rise, fade and stay under the spell's name, a hit soaked whole throwing no 0, a fourth number stacked above the first, the nova's ring from the caster's feet to its range, a Charge run and not jumped. **A forced draw**: the word, the grey, the column, the header's "drawn". **The hand**, by clicks at points of the window: the pointer's ring over an enemy and not over one of yours; a pin made at the gates, moved, and let go, with the gold disc following `match.pin` and the plain skull left on the focus; a button that will not fire at the gates and shakes its head; each of glowing, sweeping (at ten fourteenths), dim (out of reach, stunned, nobody hurt) and greyed, driven through the engine, and what a click on each does; a tap heard on the click, with its call-out and its projectile; the three tooltips; a click where your rogue stands on an enemy landing on the enemy; a pinned sheep still wearing its pin; a dead token no longer clickable; the hint through its two verbs; and a pin at the gates being the opening, on a seed whose untouched match opens elsewhere. **The healing line**: nothing while healing is whole, `Healing 43%`, `No healing`, and `Routed` in the routed side's colour when the engine calls a rout |
| E | pooling: two more matches create no widget, one of them with a pointer, a tooltip, a pin, a tap and a miss in it, and the banner has its three seconds at 2x. And the audit that ran after every frame of every match played out up to here: every ring showed its unit's health, nobody left the floor, the healing line said what the match was doing, every button said what its big spell was doing (and its wedge was the engine's count of ticks), only living enemies in a match still being fought took the mouse, the gold disc was on the pinned enemy and nobody else, and every kind of number was seen at least once, by colour and by size |
| F | hidden means paused — a match, a button in mid-sweep, and the wait at the gates; switched off means closed |
| G | depth: larger and drawn over toward the front, frame levels touched only when the order changes and following a raised window; personal space, on one spot, in a corner and three in a row |
| H | speed: 2x is twice the match in the same frames, from the header button and the settings page alike, and half the gates by the wall; a thirty-second frame at the gates costs them half a second; frames that add up to the wait a float's hair short still open them; Restore Defaults reaches the header and brings the hint back; the hint goes on the second verb whichever comes second; the speed control is greyed while the module is off |
| I | the `.toc` and the art: version 0.2.0, notes that name the two verbs, every listed file exists, every Lua file is listed, the four copied textures are Plates' byte for byte and all four are referenced |
| J | every shipping file compiles, keeps under 150 chunk-level locals, and touches no global outside a written list |
| K | field proof — see below |
| L | a second session: built again, the window opens where the first one was dropped |
| M | a good player through real clicks: seeds 1 to 200 played on the second session's window by a script that looks only at widgets (the cross, the gold disc, a greyed badge, the rogue's ring, which buttons glow) and clicks only at points; the same policy played straight on the engine; and twenty of the seeds through the window untouched. The matches end the same way seed for seed, every click lands on what it was aimed at, and nothing new is made or called |

Section E's "every kind of number was seen" is a count over all the frames
of the run and nothing more: damage, heal, absorb, a crit, a tick, each at
least once. What a single number does — which lane, how high, which size,
when it fades — is section D's, on one hand-pressed tick.

### A widget the window never painted

The smoke reads recorded fields off the mock's widgets — a colour, an
anchor, a size, a cooldown — and a widget the window never painted has none
of them. That is a failed check and used not to be: the read was an error
of the smoke's own, the run ended on a stack trace, and nothing printed the
count. Two things now stand in the way.

The readers the checks go through (`Colour`, `Foot`, `Centre`, `TokenRect`,
`PillarRect`, `OnFloor`, `RingShare`) hand back not-a-number where the
window wrote nothing. Every comparison with it is false, so the check that
asked goes red with `nan` in its detail and the run carries on. A check
that asks for an absence (a token clear of the pillars) is not turned red by
it; wherever there is one, the same numbers are read the straight way by
the checks beside it.

And every section runs under a guard, for the fields that are read without
a reader (a texture's coordinates, a number's anchor, a ring's colour). An
error there is one failed check naming the section and the line, the
sections after it still run, and the count is still the last line.

### The mock is strict where the client is

About 460 lines, in the file. A method a real widget of that kind does not
have is `nil` there too, so an unguarded call to one is the same "attempt to
call a nil value" it would be in the game: `SetScript` on a Texture,
`SetTexture` on a Frame, a misspelt anything. A FontString with no font
refuses `SetText`; `SetFont` refuses flags it does not know; a template, a
draw layer or a font object that does not exist is an error; a cooldown
started before zero is an error; a NaN in a `SetPoint` is an error. And a
hidden frame's `OnUpdate` does not run — which is all section F is.

It has a mouse. A click is made at a point of the window, not on a widget,
and goes to the frame the client would give it to: shown, taking the mouse
(a Button from the moment it is made, anything else only once told to),
under the pointer, and the highest of those by frame level. Only then is
that frame's `OnClick` run. So "a dead token takes no click" and "your rogue
standing on the pinned enemy does not eat it" are checks that can fail. The
pointer stays where it was put while frames move under it, `OnEnter` and
`OnLeave` are worked out again after every frame, and a `HIGHLIGHT` texture
counts as drawn only while the pointer is over the frame that owns it.
`GameTooltip` is a strict stub that keeps what it was last told.

The mock's clock starts at 200000 seconds: a Mac that sleeps rather than
shuts down has been up for days, and past a day the health ring's frozen
cooldown is capped at a day, which is the branch the game will really run.

`Commander` is stubbed with only what the module calls, and the stub is
strict too: a framework name the module reaches for that the stub has never
seen is an error, not a quiet no-op. The slash wiring in the stub's
`Finalize` is the real one's, line for line.

### Section K: field proof

Nobody can run the game from here, so the bar for a client call is: *some
other shipped Commander module already makes it*. The mock records every
method name the module reaches for on a widget; the strict stub records every
framework function; section J lists every global. Section K then greps the
shipping Lua of every other Commander module (Harness folders, stale
worktrees and this module excluded) for each one, checks the framework
functions against `Commander_Events`' own source, and prints anything it
could not find. Today that list is empty: 47 widget methods, 9 client
globals, 13 framework functions. Stage 2 added four methods (`SetWidth`
and `SetJustifyH` for the hint, `SetOwner` and `AddLine` for the tooltip)
and one global (`GameTooltip`); everything else it leans on — a Button with
`OnClick`, `OnEnter` and `OnLeave`, `EnableMouse`, a `HIGHLIGHT` texture —
is likewise in other shipped modules, though a draw layer and a script name
are arguments and not methods, so K does not grep for those two. Section M
runs after K and ends by checking that it called nothing K had not seen.

That is a statement about *calls*, not about *results*. "Another module makes
this call" is not "somebody has watched it work" — see the last section.

## Proved by breaking it

A smoke that cannot fail is not one, and "every mutant we tried died" is only
as good as the mutants. So this section says which were tried, and which
were tried and lived.

**The window and the settings file: 142 of 142.** Each is one site changed in
`CommanderGladiator.lua` or `CommanderGladiatorDB.lua`, in place, the UI
smoke run, and the file restored byte-identical (`cmp`) after it. Sixty are
the first pass's — the face never restored after a sheep, the record counted
twice, the step cap removed, the projection ignoring depth, the clock moved
to a free-standing frame, a font string made per number, the ring showing
the missing share, levels set every frame, a pillar moved into the walk, a
misspelt method, a misspelt local. Eighty-two came after a review ran its own
mutants and found most of them alive, in the places the sixty had not gone:
everything that flies (the delivery rule swapped, one widget for every number
or every projectile, a projectile that never leaves its caster, a ring
anchored at the corner, a bump that always points right), the banner's band
and colour, `RegisterForDrag`, the first-open anchor and the drawn-match
path, a ring cooldown not capped at a day, the slowed shadow, the dead dim,
a Charge that snaps, a `0` beside an absorbed hit, Restore Defaults not
reaching the header. The rest of the eighty-two are what that review
changed, each broken back to what it was: one pass of the spreading, numbers
thrown from the token's top edge, no lift for a fourth number, the frost
icon across the name, the healing line unpainted or miscounted, the default
seed at 1. The checks in section D's second half, section L and the bell's
extra lines were written against these, and every one of the 142 turns a
check red on the files as they are. They were run again, on copies, after
the smoke learned to report an unpainted widget: 142 of 142, and all 142
now end on the count. Seven of them used to end on a stack trace instead
(the healing line never painted was one).

Six more were run in place for that change, each restored byte-identical:
the healing line never given a colour, never painted at all, written and
never shown; a full ring never given its colour; a token's shadow never
anchored; a health ring shown without a cooldown. All six are red, and all
six end on the count: the healing line's three and the shadow as ordinary
red checks, with `nan` wherever a reader was asked for what was never
painted; the ring's colour through the section guards; the cooldown through
both.

Rerunning the first sixty found one that had only ever been caught by luck:
"the back row is as wide as the front" turned the row-width check on two
numbers equal to nine places, and which was the smaller depended on where the
tokens had glided from. That check has a margin now.

**Stage 2, the hand: 79 of 79.** Each is one site of what stage 2 added to
the window or the settings file, changed in place, the UI smoke run, and the
file restored byte-identical (`cmp`). Seventy-six were red on the first run:
a pin made for side B, either flag not remembered, the hint not looked at
again after a pin or a tap, a tap firing at the gates or not heard on the
click, a miss that does not shake (or shakes up and down, or never stops),
the tooltip's title, body, wrapping, owner and hiding, the bar off centre,
too small, overlapping, dealt in reverse or dealt the enemy's three, a
button wearing the basic attack, its look kept across a deal, the cooldown
in seconds for ticks or drawn as the elapsed share, a dead owner's button
still sweeping, the dead not greyed, buttons glowing at the gates or without
asking the engine, the countdown rounded down or never hidden, no gates, the
match stepping at them, a hitch throwing them open, the gates on the wall's
clock, the dead or your own or anybody after the bell taking the mouse, the
pin drawn from the focus instead of `match.pin`, a pinned sheep losing its
skull, the hover ring as ordinary art, any of the three scripts not wired,
the hint going after one verb or never, Restore Defaults not reaching it,
the floor not moved up or the window not grown for the bar, a flag missing
from the defaults. Three lived, and each got a check: the gates opening
without the float's hair (they opened a frame late on frames of a sixtieth
of a second — section H now counts 120 of those), the hover ring never
anchored (section B), and the health ring handed the button's disc for its
swipe (section D). All 79 are red on the files as they are.

The 142 above were run again after stage 2, on copies of the files as they
are now: 142 of 142, none without a line to change.

**Tried and alive, on purpose, in stage 2.** Eight looks: the halo's pulse,
the shake dying away, the colour of the pointer's ring, how far the hint
stands from the bar, which side of a button its tooltip opens on, the size
of the countdown's type, the tooltip title's white, and how bright a
sweeping button's rim is.

**Tried and alive, on purpose.** Eight more were run to say plainly what the
UI smoke does *not* defend, and all eight leave it green: the cyclone's sway,
the pulse of the Pain Suppression glow, the shadow scaling with depth, the
two flags that keep cooldown-count addons off the health ring, the guard on a
bump of no length, how long a body takes to sink, the size of the banner's
band, and the grey of the healing line. They are looks and not logic, and
the game is the check for them.

**The engine: 80 of 80 of its own, and twelve of a reviewer's still alive.**
Of the first pass's fifty, three no longer have a line to change (the engine
has been rewritten under them) and the other 47 are caught: that count is
from before the rout was tightened, and those fifty have not been run
since. Everything else here was run against copies of the engine and data
as they are now. The 24 written when the rout, the rolled opening and the
dampened healers went in are all caught, four of them moved to the lines
that replaced theirs in the bell. Nine were written when the rout was
tightened and are all caught: a dead unit's dot routs a side again; the cap
goes to health after a rout; a side is routed with its own dot still
ticking; a dead unit's dot no longer keeps a match going; Pain Suppression
is pressed on a routed side, onto itself, or never; a damage-taken debuff is
refused on a routed enemy too; and the first two together, which is the
fault as it was found, and the only one of the nine to turn "no routed side
won, and none drew" red — either half of the fix keeps that rule by itself.
A reviewer's further 36 are the honest part: three have no line left, 21 are
caught (one of them moved to the bell's new last line), and twelve leave the
engine smoke green —

- a feared enemy is hit like anybody else (the tier for a disable that breaks
  after some damage);
- a disable does not clear its victim's target;
- crowd control is thrown from any distance; Frost Nova is pressed for an
  enemy already held; Shadowstep is pressed while still empowered;
- a healer's tie between two equally hurt allies goes to the higher slot;
- the kite's fallback direction (a melee on exactly the caster's spot) is
  reversed;
- a hot's pulse clock is not restarted when it is refreshed;
- `AURA_GAINED.duration` is always 0, `aura.expires` is always 0, and an area
  press names its caster as the target — three things the window is told it
  may rely on, and today does not;
- the opening stagger cut from a second to a tenth.

These are not known bugs. Each is a shipped line that could be broken
without a red check.

Two mutants survived the very first pass, and each was a hole: nothing
checked that a heal's number was thrown at all, or that a token re-dressed
for a different unit took the new class colour. Sections D and E grew the
checks that catch them (the numbers' colours, signs and sizes; a deal of the
two teams swapped over). A third was equivalent and is in no count: the
floating numbers' font-object template is redundant, because `SetFont` always
runs before `SetText` — it is kept as the fallback if the font path ever
fails.

## Stage 2: hands

A match nobody touches is a stage-1 match: the engine's section G holds two
hundred untouched matches to a checksum taken before there was a hand. What
stage 2 adds is two verbs and nothing else.

1. **Click an enemy** to pin it as your team's kill target. It holds until
   that enemy dies, another enemy is clicked (the pin moves), or the pinned
   one is clicked again (the pin is let go). Every match starts with none.
   The pin is soft: the team will not break its own sheep to obey it.
2. **Tap a glowing button** to fire that gladiator's big spell now, on
   whoever the spell's own rule picks, rather than on its next beat. A
   button glows when a tap would fire; a tap on one that does not glow does
   nothing, and the button shakes.

In the window: a match is held at its **gates** for two seconds of its own
clock after the deal, where an enemy can be pinned (that pin is the
opening) and the buttons show but do not fire. The window is 560 by 432;
the bar's three buttons are 42 px discs (36 px icon) centred 42 px up from
the bottom edge and 64 px apart; the floor's slab ends at 75 px.

What a hand is worth — the engine smoke's section G, side A's share of the
preset matchup with a draw as not won, on seeds 1 to 1000 (asserted) /
30001 to 31000 / 60001 to 61000 (measured):

| player | side A wins | inputs a match |
| --- | --- | --- |
| HANDS_OFF, nobody | 0.504 / 0.510 / 0.510 | 0 |
| GOOD: sees 0.4 s late, one input per 0.7 s | 0.764 / 0.779 / 0.765 | 5.6, 7 at the 95th percentile |
| GOOD with slow hands: 0.8 s late, one input per 1.2 s | 0.638 / 0.669 / 0.678 | |
| PIN_ONLY: GOOD's pins and no taps | 0.633 / 0.683 / 0.657 | 2.65 |
| TAP_ONLY: GOOD's taps and no pins | 0.608 / 0.637 / 0.585 | 2.9 |
| CARELESS: a random legal input every 1.5 s | 0.058 / 0.071 / 0.072 | about 18 |
| NOVICE: three random inputs in the first 10 s | 0.275 / 0.264 / 0.316 | 3 |

Asserted there: HANDS_OFF in 0.46 to 0.54, GOOD in 0.62 to 0.78, CARELESS no
more than three points over HANDS_OFF, slow GOOD at least five over it, and
at most nine inputs a match.

GOOD makes two inputs before the first tick: it pins the druid and taps
Polymorph. The window refuses a tap while the gates are shut, so through
the window the second of those is the first thing after they open. The UI
smoke's section M plays it that way, by clicks, on seeds 1 to 200 — the tap
landing before the first tick, as a script's can — and gets 0.755 against
0.535 for nobody, the same matches the engine gives for the same policy,
seed for seed, at 5.5 inputs a match. A person is later than a script. With
the pin made at the gates and the opening tap landing some ticks after they
open (the same three ranges, measured on the engine, not asserted):

| the opening tap lands | side A wins |
| --- | --- |
| before the first tick | 0.764 / 0.779 / 0.765 |
| 0.1 s after the gates open | 0.750 / 0.767 / 0.743 |
| 0.2 s | 0.700 / 0.746 / 0.724 |
| 0.3 s | 0.698 / 0.707 / 0.708 |
| 0.5 s | 0.694 / 0.698 / 0.707 |
| never: the mage is left to cast it | 0.673 / 0.689 / 0.686 |

So a person with a good policy is nearer 0.70 than 0.76, which is inside the
band either way.

Known and accepted: a tap rewards tempo more than judgment (random taps
alone beat nobody); the pin is worth most in the first second, which is what
the gates are for; random clicking on enemies loses nearly every match.

What only the client can confirm about stage 2 is in the list below, from
"Clicks on tokens" to "The tooltip".

## What only the game can say

The mock returns nothing for a width it was not given and cannot see a pixel.
What is unconfirmed until somebody opens `/cglad`:

- **The health ring.** It is Commander Plates' frozen-cooldown arc, and
  Plates' own `ASSUMPTIONS.md` (A1) says that recipe has not been verified in
  game either. If the ring creeps, shorten `DRIFT`; if it does not draw,
  `STATIC` should come down. Whether a Cooldown's swipe fades with its
  parent's alpha (a cycloned token is thinned to 0.7) is the same unknown.
- **The picture.** The floor's colours, whether the squashed disc reads as an
  arena, whether two pillars at the ends look like pillars, whether 44 px
  tokens and 10 px names are legible, whether the raid-target skull and cross
  read at 15 px, and the skull on a 23 px gold disc as "pinned". Layout was
  checked in a drawing made from the mock's widget tree, not in the client.
- **Numbers on the face.** A floating number now starts on its token's face
  and rises to about its top edge, so that it no longer climbs through the
  spell call-out's name. Counted in the mock over forty matches, that takes
  "a number across a call-out's name" from 16% of frames to 3% — and puts a
  number over its own token's badge in half of them. Whether that reads as
  "this one was hit" or as a badge you cannot see is the client's to say.
- **Lane width.** The three lanes are 14 px apart, and a three-digit number
  in the client's font is probably wider than that. Nothing here has the
  font, so the widths in every overlap count are a guess (0.55 em a digit).
  By that guess, lanes 22 px apart cut two numbers overlapping from 18% of
  frames to 6% but put a number on a NEIGHBOUR's face in 19% instead of 11%,
  which is why the pitch was left alone. `numberLane` is one number in the
  layout.
- **Personal space.** Tokens are drawn 10 floor units apart, which for a
  token 36 to 44 px wide is a touch and not a gap, and three passes of the
  spreading settle most pile-ups and not all (see `G.Spread`). Whether a
  melee and its target read as two tokens, and whether `space` wants to be
  larger, is a look.
- **The frost icon.** It sits on the token's lower-left shoulder, clear of
  the name by arithmetic. Whether it reads as "rooted" there is not known.
- **The healing line.** Its place beside the record (a font string anchored
  to a font string, with no width given to either), its grey, whether
  `Routed` in the routed side's green or red is understood as *whose* rout,
  and whether a number doubled on a routed healer reads as the rule it is.
- **Feel.** Smoothing rate, bump reach, projectile speed, how long a spell
  call-out stays up, whether 2x is too fast to follow, whether the first
  dozen matches of a fresh install feel like a fair game.
- **Top-level behaviour.** The window is `MEDIUM` and top-level, and the
  tokens re-read the stage's frame level every frame so a click that raises
  the window cannot leave them under the floor — that is reasoned, and
  tested against the mock, not seen. The same goes for dragging: the smoke
  checks the window registered for it, not that the client delivers it.
- **Clicks on tokens.** A token is a Button whose mouse is switched on only
  while it is a living enemy, with three plain child frames over it (the
  ring's two and the face). That those children let the click through, that
  a Button with no template and no `RegisterForClicks` answers a left click
  as it does everywhere else in the suite, and that a token walking under
  the pointer between press and release still gets its `OnClick`, is
  reasoned and mocked, not seen. A token that takes the mouse also takes a
  window drag that starts on it.
- **The pointer's ring.** It is a `HIGHLIGHT` texture on the token, drawn by
  the client and never by this module; the token's ring and face are child
  frames a level or two above it, so the ring shows only where it is wider
  than they are. Whether that reads as a ring is a look.
- **The bar.** Whether 42 px discs with a 36 px icon are easy to hit;
  whether glowing, sweeping, dim and greyed are four things at a glance;
  whether a Cooldown swept from a disc texture draws a clean wedge over a
  round icon (it is the health ring's recipe with different art, and that
  recipe is itself unconfirmed); whether the wedge is see-through at alpha
  0.65; whether the icon stays square on a client that will not mask.
- **The hint and the countdown.** Each half of the hint is broken by hand
  into two lines and given a 130 px width; what the client's font makes of
  that, and whether "Gates open in 2" in 16 px type over the back row is
  noticed, is the client's to say.
- **The gates.** Two seconds of the match's clock, so one at 2x. Whether
  that is long enough to pick an enemy and short enough not to be a wait.
- **The tooltip.** `ANCHOR_RIGHT` opens it over the floor's front edge; the
  wording is one line per targeting rule and has not been read by a player.
- **New files.** The module's files are new since the client was last
  started, so it needs a full restart, not a `/reload`. Textures that are not
  found draw nothing rather than erroring: everything a token cannot do
  without (class badge, name, numbers, spell icons) is the client's own art.

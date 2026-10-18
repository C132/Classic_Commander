# Commander_Recruit harnesses

Three luajit checks, all in-addon. Run all three before any change.

```bash
/opt/homebrew/bin/luajit recruit_engine_smoke.lua   # the engine, no mock — 132 checks
/opt/homebrew/bin/luajit recruit_ui_harness.lua     # wiring under a WoW mock — 172 checks
/opt/homebrew/bin/luajit globals_lint.lua           # 3 files, 0 undeclared globals
```

## `recruit_engine_smoke.lua`

Names (a written realm kept, a bare one flagged as a guess); the book (sightings merge
without forgetting, freshness, Gone, pruning); the board (brackets apart, highest first,
ties to the more recently seen, a player in several brackets, the minimum rating per
bracket, the class filter, the unrated count); the sweep (a query per class per faction,
the race split at the cap asked before the next class, partials, the progress count, every
class/race pair real for TBC, localized names quoted).

Section E (1.9.0) is the steered sweep (R20): login age to odds; no roster, an empty one, none of
our faction or no faction falls back; the other faction, an impossible pair and a player under the
lowest rating are left out; a guild, a pair and a whole class expect their unfound players' odds;
the arena zones come first at their prior; a class is never offered when it gave more than 50
lately, when its pairs did between them, or when /who has been listing many per rated player, and
a half-hour-old total is not trusted; players on the board stop counting; the arena's timer, its
estimate moving halfway to its finds, and its fade and retry; finds counted only for rated players
of ours not on the board; a guild answer under the cap proves the rest offline but drops nobody
from the board; a class answer proves every unlisted one offline for the board and settles its
pairs; an unanswered query is recorded; a capped pair is partial, proves nobody offline, lowers the
rest's odds by Bayes and counts for its share of 50 next time; a capped class is not partial; one
rated player alone is not worth a press; the sweep ends for good; labels for the bar.

Section F runs both sweeps against a modelled realm (800 rated, 600 unrated level 70s on, /who's
50 cap) and checks the steered one finds more, in no more presses, with the fixed plan's haul by
70% of its presses and a third more after ten. It prints its numbers.

## `recruit_ui_harness.lua`

The real shared framework plus the three files under the Ladder harness's mock, with fakes
for /who, the group finder, guild, friends, GUIDs, whisper/invite and Muster. Drives: the
window (three columns, Escape), a sweep (one query per press, the social origin, the answer
routed to the list and back, the gap, the split after a capped class, a Who window the sweep
opened shut and one the player opened left open, an answer lost past the timeout asked
again), the board off Muster's ratings (order, win-loss, counts, the status and the unrated
line), the clicks and the tooltip, every source (a bare group finder name asked for bare,
chat with the say/yell faction check, guild and friends on and off, mouseover of either
faction, a source's switch), the lowest-rating filter, freshness, the master switch and
Forget All.

Section W (1.1.0) is the watch list: the eye adds a non-friend with the "Recruit watch"
note and saves it per character as Recruit's, the list confirms it, the header counts it, an
existing friend is only marked and stays a friend when un-watched, Recruit's friend comes off
by the list's own spelling, a watched friend going offline leaves the board even with the
Friends source off, a rewritten note makes them yours, a hand-removed friend stops being
watched, an empty login list removes nobody, an add that never lands is dropped and said, and
Stop Watching All removes only Recruit's friends.

Section P (1.3.0) is the ladder probe, and its point is the safety property: nothing is
probed before the friends list is read (P0); the highest-rated non-friend on our realm goes
first with Recruit's note and is saved per character; one probe at a time and a gap between;
the answer takes them off at once (online: onto the board as "probe" and said in chat;
offline: not on the board); existing friends are skipped; a note written mid-probe keeps
them; a timed-out add is cleaned up when it lands late; a /reload leftover with Recruit's
note comes off and one with yours stays; and over the whole run no friend you had or claimed
was ever added or removed, and every one is still on the list.

1.3.1 adds: the Probe button reads "Reading friends..." greyed before the list is known; a
second press while it reads says nothing more; a list the client already holds is read with
no FRIENDLIST_UPDATE at all and chat says the probe is ready; a probe friend that arrives
with no note is left on the list, named once in chat, and taken off only by Clean Up Probes.

Section N (1.4.0) is the one key: /who ready sweeps; /who waiting probes; inside the gap it
probes again; a probe in flight with /who not ready waits; the gap passed sweeps again; and
both probes came off the friends list.

1.4.1 adds the row layout checks: no cell wraps, the name stretches between the rank and the
rating, the age, win-loss and rating chain from the right edge, the win-loss is 56 wide, the
watch mark is a dot, and the columns are 250 wide.

1.5.0 moves the progress checks onto the strip: the sweep bar says it is waiting, counts the
split in and fills to 2/12; the probe bar says it is reading the list, names who it is checking,
counts "3 of 6 checked · 1 online · next: Second (3v3 2100)" half full, and "all 6 checked"
full; the buttons keep the short labels Sweep and Probe.

1.6.0: a /who that never answers counts as nobody and the sweep moves on (it used to ask again
for ever); the probe hears the friends system's words — "Player not found." remembers the name
as gone for a week and frees the probe at once, words seconds later are not the probe's,
"already your friend" settles without removing, "friends list is full" stops the probe and says
so until the list shrinks; left-click opens the player's conversation in Commander Contacts, a
plain whisper without it.

1.7.0 is batches (R15). Section P and N run at one a press (`ProbeBatch = 1`) and keep their
1.6.0 meaning; section PB runs at five: one press adds the five best non-friends in order, each
noted and saved; a second press while they are out adds nobody; the bar says "checking 5
players (Alpha 2500 and 4 more)" and "next: Alpha (2v2 2500) and 4 more"; three landing in one
list are each answered and taken off; one "Player not found." down both channels counts once,
marks nobody while two wait, and is pinned on the last one once the other lands; the chat
filter hides the probes' own "added"/"removed" lines (a player link too) and "Player not found."
just after a press, and nothing else, and nothing with Quiet Probe Chat off or seconds later;
a refusal from another addon or another function changes nothing; the game refusing an add
after the press takes the last waiting player back, keeps the first, goes to one a press and
says so, and the refused player is tried next press alone; a refusal inside the add itself
stops the press there; five adds with one answer twice running goes to one a press, the four
with no answer tried again rather than skipped, a late one still taken off; a full list part
way through answers the ones that landed and marks the rest neither gone nor left to remove;
and your friend and the other realm are never touched. The engine smoke adds `ProbeBatch`
(best first, none twice, at least one) and `BatchErrorsSettle` (errors matched by count).

1.7.1: a friend row the server has not filled in yet (name "", level 0, "Unknown", but the
GUID and Recruit's note) is no error and is nobody: nothing removed, a watched friend whose row
is blank still watched, the probe still waiting; filled in, the ticker reads the list again and
it is answered and taken off within the second; one filled in only after the probe gave up is
still put on the board, said, and taken off.

1.8.0 removes the probe (R17): sections P0, P, N and PB are gone, and the engine smoke's probe
and batch checks with them. Section F0 reads a friends list the client already holds with no
event and takes off a probe friend the old feature left behind; section L is the leftover rule
in full (only Recruit's exact note, never a watched one, a note you wrote or a noteless row; a
blank row is no error; the record lets go of yours, watched and day-old ones, keeps a noteless
one until its note returns, and goes away once empty; one sweep key under the old NEXT name).
Section Q is R18: a mouse-wheel notch moves three rows and looks up no rating, a quiet tick and
the five-second rebuild look nothing up, a new player costs one lookup, and after five minutes
ratings are asked again.

1.9.0, section R (R20), with a Commander Ladder mock whose roster the test controls: the roster is
asked for our realm; the bar says the sweep is aimed, at how many, and what comes first; the first
press asks about arena matches and the sweep is the steered one; the bar names what it waits on;
an arena answer puts its rated player on the board and moves the estimate; then the Ruins, then
the guild in one /who (its new rated player counted, not the one already seen), then a whole class
expected under 50; that class's answer takes a paladin seen in chat off the board; chat and the bar
say the sweep is done with 4 queries and 3 found; a press with nothing worth asking sends nothing and keeps that count; done, the bar names what a press starts again
with; 2000 as the lowest rating shown leaves the 1500 out; nothing worth asking greys the button
and a press sends nothing; and with an empty roster the fixed plan runs and its bar names Warrior.
The mock's buttons now record SetEnabled.

1.10.0 is the search order (R21). The engine smoke's section O: a saved order made whole
(unknowns and repeats dropped, missing classes added), a class moved up and down, ranks without
the classes switched off, the fixed plan in the player's order and without them; on a steered
roster (12 paladins, 6 priests and 4 rogues in one guild) best first is unchanged, a class
switched off loses its queries, an arena zone is worth only the share still searched, a guild only
its searched players, in order everything for the first class goes before the next (its guild
first), and options set on a sweep under way apply. The UI harness's section O: the nine-row list
beside the board, in the default order, with on/rated counts and every class checked; the class
the next press searches for marked; a click or the box switches a class off and back; a drag
shows its drop line, drops a row at the top and between two others, turns Search in this order
on, and a drop in place moves nothing; the sweep asks in the new order, takes a class switched
off mid-sweep at once, and the counts follow the board; Hide unchecked classes hides them and the
header says so; Reset; and the fixed plan without a roster in the order and without classes off.
The layout check now expects the 974-wide window.

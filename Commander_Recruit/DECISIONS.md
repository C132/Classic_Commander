# Commander_Recruit — decisions

Numbered so code comments and future sessions can cite them.

## R1 — "Online" is a sighting, because nothing lists everyone logged in

Devin asked (2026-10-17) for "all of the players online in my faction sorted by highest
arena rating grouped by bracket so I can find people to play with". The client has no list
of who is logged in. So the book is filled from every place a player can only appear while
on: /who answers, the group finder's listings, chat lines, the guild roster's and friends
list's online flags, and friendly players under the cursor, targeted or on a nameplate. A
sighting counts for `FreshMinutes` (15); a roster or friends list saying "offline" takes
them off at once. Everything is your faction already except say and yell, which are checked
by race through `GetPlayerInfoByGUID`.

## R2 — The sweep is one /who per press

`C_FriendList.SendWho` carries `HasRestrictions` on the classic_anniversary branch: an addon
may send it only from a click or a key press. So "everyone online" is a plan walked a press
at a time (a button, and a key binding to tap): every class at level 70; a class whose
answer hits /who's 50-name cap is asked again race by race (only real TBC class/race pairs);
a race still at the cap is reported as partial, not split further. Five seconds between
queries, an answer given up on after eight. The answer is routed to the Who list
(`SetWhoToUi(true)`, back to false after) and a Who window the sweep popped is shut; one the
player had open is left alone.

## R3 — Three columns, never tabs

2v2, 3v3 and 5v5 side by side, each highest first. Devin finds tabbed views hard to read
(PartyFrames memory: the arena replay north star), and the three lists answer three
different questions; a player stands in every bracket they are rated in.

## R4 — Ratings are Muster's

`CommanderMuster.RatingsFor` is the suite's one rating source (Muster D11): it merges what it
has seen in game with Commander Ladder's web feed, and hands a player it cannot rate to the
feed's next run. A name the game gave without a realm is asked for bare (Ladder L8). Without
Muster, Ladder is read directly.

## R5 — Left-click whispers, right-click invites

The board exists to find a partner, so the two clicks are the two first moves. The name the
game gave is used as given (a bare name stays bare, so the server resolves it).

## R6 — The watch list (1.1.0): friends Recruit adds, and only those it removes

Devin asked for an automatic sweep, or to friend people and remove them again. Neither can run
unattended: `SendWho` and `AddFriend` both carry `HasRestrictions` (a click or a key press per
call), and a friend-add checks one person where a /who checks fifty. Firing them off unrelated
clicks would be dodging the restriction's purpose, so that is not built. What a friend DOES
give for free is the server's online/offline notice, forever after one click. So the eye on a
row watches a player: `AddFriend(name, "Recruit watch")` unless they are already a friend
(then only marked). Rules, in `CommanderRecruitWatch` (per character, as the friends list is):

- `byUs` records who put them there. Un-watching, and Stop Watching All, call `RemoveFriend`
  only for `byUs` entries, by the name the friends list itself shows (`friendName`), never the
  name the add was asked with.
- A friend whose note you rewrite becomes yours (`byUs` false): never removed.
- A watched friend you removed yourself is no longer watched; an EMPTY list (login) is not
  taken as a removal.
- An add that does not appear on the list within ten seconds failed (not found, another
  realm, or a full list) and is dropped with a chat line.
- Watched friends' online status feeds the board even with the Friends source switched off.

## R7 — A way in from the Social window (1.2.0)

Devin asked for a button in the Social pane (O). It is an icon in the window's title bar,
left of the close button, so it is on every tab: the Friends tab's spare gap between its
corner buttons already holds Commander Contacts' button, and the Who tab's bottom row is
full. A plain Button parented to `FriendsFrame` (a UIPanel, not protected), installed at
login and again at PLAYER_ENTERING_WORLD (idempotent), switched by `SocialButton`.

## R8 — The ladder probe (1.3.0): one player per press, friends never touched

Devin, after the watch list: "can we not use the db and /friend and unfriend as an option, if
the person isn't currently on my friends list? I don't want to accidentally wipe my friend
list." Probe Ladder walks the Commander Ladder feed's players on our realm, best rating first
(`E.ProbeCandidates`), one press each (`AddFriend` has restrictions, like SendWho): add with
the note "Recruit probe", read the server's online flag from the next friends list, remove at
once. It is the way to ask about particular players — the strongest on the ladder — which
/who cannot. The safety rules, each held by a harness check:

- Nothing is probed until this session's friends list has arrived; a press before that asks
  for it and says why.
- Never probed: anyone on the friends list, anyone watched, anyone seen online in the
  freshness window, anyone probed in the last 15 minutes, anyone on another realm.
- Removed: only a name in `CommanderRecruitProbe` (Recruit's own adds, per character), by the
  friends list's own spelling, and only while its note is still Recruit's or reported empty
  (`E.ProbeRemovable`). A note you write — even mid-probe — makes them yours for good.
- An add that does not land within six seconds is given up on but stays recorded, so a late
  arrival, or one left by a /reload, comes off at the next friends list.
- There is no "remove friends" anywhere except those two lists' own entries.

**1.3.1 (2026-10-17).** Devin: "it says press again in a moment but that's unclear if it's
still running". The list was only counted as read on a FRIENDLIST_UPDATE, which the server
sends once at login (possibly before Recruit listens) and does not always repeat when asked,
so the probe could wait for ever. Now the client's own copy counts the moment it holds any
friends (`CheckFriends`, every second), and a list asked for eight seconds ago that is still
empty is empty. The Probe button says what it is doing — "Reading friends..." greyed, then
"Probe Ladder" — and a press made while it read gets one chat line when it is ready. And
removal got stricter: on its own Recruit removes a probe friend only when the note is
exactly "Recruit probe"; NO note is not proof of anything, so such a friend is left, said
once in chat, and taken off only by Clean Up Probes, which the player presses.

He also asked for a checkbox to sweep automatically. Not built: SendWho and AddFriend refuse
to run outside a click or key press, so a checkbox could only work by firing them off the
player's unrelated presses, which is exactly what the restriction exists to stop.

## R9 — One key for both (1.4.0)

Asked for in place of the auto-sweep checkbox R8's note declines. The binding "Next: Sweep,
or Probe Between" (`CommanderRecruit_NextStep`) sends the sweep's next /who when /who can
take one (`SweepReady`: nothing awaited, five seconds since the last), and otherwise runs one
ladder probe — so tapping a single key keeps both going, a probe filling each /who gap. It
is still one press, one action: it only spares the player choosing which. When neither can
act (a probe in flight and /who not ready) the press does nothing.

## R10 — Rows laid out from both ends (1.4.1)

Devin's first in-game screenshot: "some overlapping text and general layout issues". Every
cell had a fixed width guessed for a small font, laid left to right; at his UI scale the
win-loss ("165-126") wrapped onto a second line and ran into the age, and an owl icon on
every row was the busiest thing on the board. Now each row is anchored from both ends — dot
and rank from the left; age, win-loss (56 wide) and rating from the right, chained off each
other — and the name stretches between, cut with an ellipsis rather than pushed into the
numbers. No cell wraps (`Cell`). The watch mark is a 6px dot, faint until watched. Columns
250 wide, the window 790. The harness checks the anchors, the widths and the no-wrap.

## R11 — Friending is our realm's (1.4.2)

Devin, 2026-10-17: "I can not friend nightslayer players nor do I want to, just people on my
realm." So the probe stays what it was built as — the ladder data's players on our realm only
(R8) — and Watch, which is a friend add, is offered only where one can work: the dot is gone
from rows of players on another realm (`CommanderRecruit.CanFriend`), and a watch asked for one
adds nobody. A bare name, which is how the game gives our own realm's players, keeps its dot.
Other-realm players still appear on the board (marked `*`) for whispering.

## R12 — Progress lives in a strip, not in the buttons (1.5.0)

Devin: "I need a clear progress bar on the probe feature and the text doesn't fit in the
button". Two full-width bars now sit between the header and the columns, Sweep (gold) above
Probe (blue), each a fill as wide as its fraction under one line of text:

- Sweep: "N of M queries · next /who in 3s" / "waiting for /who to answer..." / "done, N
  queries (K still past /who's 50) · ready to sweep again"; fill = queries done of planned.
- Probe: "reading your friends list first..." / "no ladder data for <realm> yet" / "X of Y
  checked · Z online · next: Name (2v2 2100)" / "checking Name (2v2 2100)..." / "all Y
  checked in the last 15 min"; fill = checked of the realm's candidates, where "checked" is
  whatever the probe would skip now (probed in 15 min, a friend, watched, seen online), so the
  bar measures what is left, not presses made.

The buttons are back to "Sweep" and "Probe" and only grey out when a press would do nothing.
The window grew 38px for the strip. He asked again, the same day, why there is no automatic
/who: the client refuses SendWho outside a press, and the only ways round it (firing off
unrelated presses, or an outside key-presser) are the thing the restriction stops and against
Blizzard's terms — so the answer stays the one key (R9). He also asked whether a 1600 floor
helps the probe: barely on Dreamscythe (1,606 of 1,627 ladder players are 1600+, since the
ladders hold the top ~5,000), 1800+ halves it (895), 2000+ is 193; "1600 and up" was added to
the menu anyway.

## R13 — A run never stalls (1.6.0)

Devin: "it looks like the sweep breaks when it hits a player not found error." Two stalls:

- **The probe.** "Player not found." is the friends system's answer to an add for a name that is
  not on the realm any more (renamed, transferred, deleted since the feed saw it; three were
  stuck in his saved probes). Recruit heard nothing and waited six seconds for a friend who
  would never appear, the Next key doing nothing meanwhile, and asked again fifteen minutes
  later. Now the system and error lines are read (`FriendError`): not found frees the probe at
  once and remembers the name as gone for a week (`CommanderRecruitGone`, per character; never
  removed, it was never added); "already your friend" settles it without ever removing; "your
  friends list is full" stops the probe, says so on the bar, until the list shrinks. Only words
  inside three seconds of the add count — the same words can follow your own invite.
- **The sweep.** A /who that got no answer was sent again, and again: one with no matches may
  send no WHO_LIST_UPDATE at all. Now it counts as answered with nobody (`unanswered`) and the
  plan moves on; the bar and the end-of-sweep line say how many.

## R14 — Left-click opens the conversation in Commander Contacts (1.6.0)

Devin: "instead of left click whisper I want it to bring up left click contacts whisper window
for that person, that way I know the history of chat I've had with them." Left-click calls
`CommanderContacts_OpenWhisper` (Contacts D14): the thread with them on Contacts' Activity tab,
made if there is none, history above the compose box. A plain chat whisper when Contacts is not
loaded or is off. The row tooltip says which.

## R15 — A batch of probes per press (1.7.0)

Devin: "it seems like [probe] is still only doing 1 person at a time", then "try batching 5
probes per press, with a setting for the batch size, and fall back to one per press if the
game blocks the extra adds." Whether one key press lets an addon make several restricted
AddFriend calls is not documented (A22), so Recruit tries and watches:

- **The batch.** One press adds the next `ProbeBatch` players (Players Per Press, 1-10,
  default 5) best first (`E.ProbeBatch`), each with Recruit's note and saved in
  `CommanderRecruitProbe` before the call, so the safety rules of R8 hold per player. The next
  press waits until every one of them has an answer or the six-second timeout.
- **Answers matched back.** A landed friend is matched by key; "already your friend" by the
  name in the line; "Player not found." names nobody, so it is matched by count
  (`E.BatchErrorsSettle`): once there are as many errors as players still waiting, those are
  the ones. The same error can come as a system line and as an error message, so each channel
  is counted on its own and the larger count is used. A full list settles the waiting ones
  without marking them gone. An ambiguous leftover times out as failed, as before.
- **Falling back.** Two ways the game can refuse: loudly, ADDON_ACTION_BLOCKED/_FORBIDDEN naming
  Commander_Recruit and AddFriend (each one takes the last waiting player back off the batch,
  unsaved, to try next press; a refusal inside the call itself stops the press there), or
  silently, the extra adds simply never answered (several adds and at most one answer, twice
  running; those players are tried again, not skipped as failed). Either way `ProbeBlocked`
  (account-wide) puts the probe on one a press and chat says so once. Changing Players Per
  Press, or Restore Defaults, clears it and tries a batch again. A loud refusal also shows the
  game's own "blocked from an action" popup once: that cannot be prevented from an addon.
- **Given up, not forgotten.** A timed-out add stays in the saved probes marked `lapsed`: the
  probe may try that player again, and if the old add lands within ten minutes it is still
  taken off. After that it is dropped, so a run is not skipped for a day.
- **Quiet Probe Chat** (default on): five adds a press is ten "added to friends." / "removed
  from friends." lines, so a CHAT_MSG_SYSTEM filter hides the friends system's lines about the
  names Recruit itself just added or took off as probes (ten seconds), and "Player not found."
  within three seconds of a press. A watch, or any friend you add yourself, still prints.

## R16 — A friend row not filled in yet is nobody (1.7.1)

Devin's first batch run in game: `CommanderRecruit.lua:343: table index is nil`. Row 36 of his
friends list was a probe the server had not filled in yet: name "", level 0, class and area
"Unknown", but its GUID and the "Recruit probe" note already set. `E.Key("")` is nil, and the
list read died there, before any probe was taken off. Now such a row is skipped and marks the
list partial: the ticker reads it again each second until every row has a name, and while it is
partial no watched friend is taken to have left (a blank row may be them). A probe whose row
fills in only after its timeout still answers when it lands: on the board if online, said in
chat, then taken off as before. A blank row is never removed by index: Recruit only removes by
name, so it waits for the name.

## R17 — Probe Ladder removed (1.8.0)

Devin, after the first batch run: "overall the probe feature is a failure and should just be
removed." Gone: the Probe button and bar, the probe key binding, the Ladder Probe settings
(Probe From, Rank By, Players Per Press, Quiet Probe Chat, Clean Up Probes), the friend-error
reading, the blocked-add fallback, `CommanderRecruitGone`, and the engine's candidate/batch
functions. R8, R13 (its probe half) and R15 are history. Two things stay:

- **Leftovers come off.** A crash (R16) or a /reload can leave a probe friend on the list.
  `CommanderRecruitProbe` still loads, and each friends-list read takes off a name in it whose
  row carries exactly "Recruit probe" and is not watched — by the list's own spelling, as
  before. A note of yours or a watch makes the record go; a noteless row is kept a day for its
  note to come back; the record goes away once empty.
- **The key keeps working.** The binding is still named COMMANDERRECRUIT_NEXT (now "Sweep: Next
  /who"), so the key Devin bound for Next sweeps. The separate Sweep and Probe bindings are
  gone: Bindings.xml changed, so the client needs a restart, not a /reload.

## R18 — The window does not rebuild the board to scroll (1.8.0)

Devin: "the game is pretty laggy when the recruit window is open and I'm scrolling through the
entries." Every mouse-wheel notch marked the board dirty and rebuilt it: every sighting in the
book scanned, every online player's ratings looked up through Muster (which resolves the name,
asks Commander Ladder, merges sources and may queue a feed wish), three lists sorted — then the
rows painted. On top, the probe bar walked all ~1,600 of the realm's ladder candidates every
second. Now:

- The board is built when something changed (at most once a second, on the ticker), every five
  seconds as sightings age, or on demand (the window opening, a setting); scrolling and the
  ticking ages repaint rows from the last board only.
- Ratings are kept per player: five minutes for a rating, one minute for "none" (Muster can
  learn one from an inspect or an arena at any time); entries older than five minutes are
  pruned. The settings page's status line uses the same cache.
- The probe bar's per-second scan went with the probe (R17).

## R19 — Where the sweep goes next (researched 2026-10-17; built as R20)

Devin asked for "the best path forward to improve sweep to make narrowing down players online
faster." Today's plan asks every class at level 70 and splits a capped class by race: about 35
presses at peak, and since most class/race pairs still pass /who's 50, it finds perhaps half of
the rated players who are on. One query cannot name several players or guilds (filters AND,
one of each), so the gain has to come from asking better questions, steered by the ladder data:

1. **The feed learns who the realm's rated players are.** The leaderboard gives only name,
   realm, rating and record; the character profile summary should also give faction, class,
   race, guild and last login (retail layout; unconfirmed for Anniversary — check the field
   names with one probe first). About 1,600 lookups for Dreamscythe, cached, refreshed weekly.
2. **Recruit orders its queries by expected rated finds per press:** `z-"Arena"` (substring:
   both TBC arena zones, if /who reports them; repeat every few minutes) and the Ruins of
   Lordaeron; `g-"Guild"` for the guilds holding the most recently active rated players (one
   press can return a guild's whole online list); then only the class/race pairs that still
   hold rated players not found, and never the class-level queries that always cap at peak.
   Estimate: 15-25 presses for most of what /who can reach.
3. **Free extras:** a custom channel's roster (`ListChannelByName`, unrestricted outside
   combat; name and GUID only) if Devin's realm has a big one; the group finder, chat and
   nameplates as today.

Unknowns before building: the profile fields on Anniversary, whether /who shows an arena match
as its zone, and whether a capped query returns the same 50 every time.

## R20 — The sweep, steered by the ladder (1.9.0, 2026-10-17)

R19, built. The feed now describes every rated player on our realm — faction, class, race, guild,
last login (Ladder L9; the profile fields were checked live first, Ladder B7) — and
`CommanderLadder.Roster()` hands them to Recruit. A sweep made from it (`E.NewSteeredSweep`) no
longer walks a fixed plan; each press asks the one /who expected to find the most rated players
of our faction who are NOT on the board yet:

- **The candidates.** The arena zones — `70-70 z-"Arena"` (Nagrand and Blade's Edge, a part of the
  name) and `70-70 z-"Ruins of Lordaeron"` — again every three minutes; `70-70 g-"Guild"` for every
  guild holding rated players; every real class/race pair holding them; and a whole class, but
  only while it should come in under /who's 50. A class expected past 50 is never offered — the
  peak-hour class queries that always capped are gone.
- **What a player is worth.** Odds of being on from their last login (1.0 today down to 0.02 past
  a month, times 0.25: roughly how many of the active are on at a busy hour). Every answer that
  could have listed them and did not lowers the odds by the share of its matches it showed
  (Bayes); an answer under the cap showed them all, so it proves them offline for the sweep.
  Players on the board (seen inside Online For) count as found.
- **What a query is worth.** Its unfound players' odds, times the share of its matches that fits
  in 50. The matches are the total /who gave for that text in the last half hour, else the rated
  players likely on times how many /who lists per rated player of ours — 6 for a class or pair, 3
  for a guild, before any answer, then learned from every answer. A class's matches are at least
  what its pairs gave between them. The arena zones start at 10 and 5 expected finds (an answer
  that works is all rated players, so they go first; one that does not halves each time) and move
  halfway to what they found each time; one that stopped finding anyone is tried every 15 minutes,
  last.
- **Order and end.** Highest first; ties go arena, class, guild, pair. Each query is asked once a
  sweep. Nothing left worth 1 find ends the sweep, for good; the next press starts a new one
  (which forgets who it proved offline). Fewer presses than the fixed plan is not the promise —
  finding more, sooner, is.
- **The board benefits too.** A class or pair answered under the cap without a player who is on
  the board takes them off at once (class and race do not change; a guild can, so a guild answer
  does not). Only with the /who source on.
- **Kept from before.** One /who per press, the five-second gap, the eight-second unanswered
  timeout, the key binding, the Who list routing. MinRating narrows who is looked for. Without
  the roster (no feed, or one written before L9, or nobody of our faction in it) the fixed plan
  runs exactly as before.
- **The bar says what comes next**: "Sweep: 4 of ~19 queries · next: guild <Name> (~2.1 rated) ·
  in 3s", "first: arena matches (~3.0 rated)", "nothing worth a /who now: ...", and when done how
  many rated players the sweep found. The total is "~" because it moves as players turn up. The
  fixed plan's bar names its next class or race too.

**Tuned on the real roster.** The first feed run with L9 (2026-10-17) described 2,002 Dreamscythe
players: 778 rated Alliance (373 logged in within three days, 276 guilds, the biggest holding 26)
and 1,224 Horde (808, 345 guilds, biggest 37). Guilds are small, so the big class/race pairs come
first (each worth about 50/6 at the start) with guilds and arenas mixed in. Run against that roster
with a modelled evening (a third of the recently active on, a tenth of those in an arena, 500 to
2,000 unrated level 70s spread like the rated ones, /who's 50 in an order that is not "rated
first"):

| | fixed plan | steered |
|---|---|---|
| Horde, 272 rated on | 32-35 presses, 129-229 found; 39-79 after 10 | 28-45 presses, 180-237 found; 71-161 after 10; the fixed plan's haul by press 21-24 |
| Alliance, 131 rated on | 29-35 presses, 53-98 found; 11-23 after 10 | 15-25 presses, 63-99 found; 34-84 after 10; the fixed plan's haul by press 15-17 |

The stop at 1 expected find was picked from that run: at 0.5 a crowded evening's sweep ran to 90
presses, the last 50 finding about one rated player each. The engine smoke's section F keeps a
small synthetic version as a check. A model, not the game: whether /who reports arena matches at
all, and how many presses a real sweep takes, are for Devin to see (A26-A30).

## R21 — The search order: a class list to drag and switch off (1.10.0)

Devin: "can you visualize the sweep search order into a draggable reorderable listed region based
on classes so I can disable some or prioritize them based on what I'm looking for." A list beside
the board, one row per class: a grip, a box, the class icon and name, and "on/rated" (rated players
of that class on the board now, of those in the ladder roster at the board's lowest rating; "N on"
without a roster). Drag a row to move it; click it or its box to search that class or not. The
class the next press searches for is lit. Below: **Search in this order**, **Hide unchecked
classes** and **Reset**. Saved account-wide: SweepOrder, SweepOff, SweepInOrder, SweepHideOff.

- **Switched off** is "not what I am looking for": the steered sweep (R20) looks for none of that
  class's players — no class or pair query for it, nothing added to a guild's worth, an arena zone
  worth only the share of rated players still searched — though they still count toward /who's 50.
  The fixed plan (no roster) leaves the class out. Hide unchecked classes (on by default) keeps
  them off the board too; a player whose class is not known yet stays; the header counts the
  hidden.
- **The order** only matters with Search in this order on, and dragging turns it on (moving a row
  is saying the order matters). In order, every query gets a tier: the place of the first searched
  class whose own unfound players make it worth a press (MIN_EXPECT); the arena zones are tier 0,
  since one answer lists every class; a query no single class makes worth a press comes last. The
  sweep asks tier by tier, each tier by that class's expected finds, so the list is followed
  strictly and still no press goes on a query not worth one. Off, the sweep stays best first
  (R20's tuned order) and the list only says which classes to look for — the default, so nothing
  changes until Devin moves something.
- **Live.** A change applies to a steered sweep under way on the next press (`E.SteerOptions`);
  the fixed plan starts again in the new order. The window repaints at once.
- **Layout.** The list is 176 wide on the left of the three columns (the window 974 wide); rows
  anchored from both ends, no wrap; the grip drawn from quads.

## R22 — Race and talent-tree icons before the name (1.11.0, 2026-10-18)

Devin: "include race and specialization icons before the player's name in the recruit window for
the entries - might need to update the client to have that info." Each row is now dot, rank,
**race icon, talent-tree icon**, name.

- **Race** is drawn from the client's own atlases, `raceicon-<race>-<male|female>` (read from the
  2.5.6.70006 build's UiTextureAtlasMember table; Blizzard's `GetRaceAtlas` spells Scourge
  "undead"). An atlas the client lacks is not drawn (`C_Texture.GetAtlasInfo`, asked once a name).
  Race and sex come from the ladder roster first (the feed now writes sex, Ladder L10), else from
  what the game showed: /who's `raceStr` and `gender`, a GUID's race and sex (chat, friends), a
  unit's `UnitRace`/`UnitSex`. Unknown sex draws the male icon.
- **Talent tree** only exists in the ladder data: the feed reads each described player's talents
  (`/specializations`, the active group of a dual spec, the tree with the most points; Ladder L10).
  The icons are the talent-tab icons Commander PartyFrames already uses for its spec display.
  Other-realm and unrated players have no tree; a player's tree is up to a week old.
- **Alignment.** An unknown icon is left empty, never closed up, so the names stay in one column.
- **Room.** Two 14px icons took 30px from the name, so the columns grew from 250 to 280 and the
  window from 974 to 1064 wide; the name keeps the width it had. If 1064 is too wide at Devin's UI
  scale, the age column (30) is the next thing to give.
- The tooltip adds "Night Elf · Subtlety (talents, from the ladder feed)".

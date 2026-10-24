# Commander_QuestLog — decisions

Numbered so later work can argue with them by name.

**D1 — A new module, not more of Commander_Objectives.** Objectives is an
announcer: it watches quest progress go by and puts toasts and banners on
screen. This is a browser over the log itself, with a model, a display list and
a set of actions behind it. They share nothing but the subject, and folding
them together would have given both a settings page nobody could read.

**D2 — Reading and drawing are separate passes.** Everything the module knows
about the log is read in `CommanderQuestLogModel.lua` and nowhere else. That is
not tidiness: reading a quest's detail requires `SelectQuestLogEntry`, which
moves a **global** selection that the stock quest log and every other addon
reads. A model pass takes that selection, reads what it needs and puts it back.
A layout pass calling the API row by row would leave the selection wherever the
last drawn row happened to land.

**D3 — Expand the client's headers once; collapse in our own state.** Collapsed
headers **remove** their quests from the index space, so log indices are only
stable while everything is expanded. The scan therefore expands first — and
only when something is actually collapsed, because `ExpandQuestHeader` fires
`QUEST_LOG_UPDATE`, which is what drove the scan, which is a loop. Folding a
zone shut in *this* window is display state kept in `CommanderQuestLogDB.Collapsed`
and never touches the client's flags.

**D4 — A quest's identity is its questID, never its log index.** A log index is
invalidated by any quest being accepted or turned in. The selection is
remembered by key (`id:9002`, falling back to the title on a client that
answers questID 0) and re-found on every scan. Every action re-derives the
index at the moment it runs and **refuses** if the title at that index no
longer matches — see D5.

**D5 — Abandon carries the quest by name, and re-finds it at accept time.** The
stock flow arms `SetAbandonQuest()` and, on accept, drops whatever the
selection points at. The confirmation dialog sits on screen while the world
keeps moving, so a quest turned in while it was up drops the wrong quest. Ours
carries the title, walks the log for it at accept time, and says so rather than
guessing when it is gone. This is section H of the harness and it is verified
to bite: with the selection-based flow, three checks fail and the wrong quest
is abandoned.

**D6 — The selection must be a row that is actually on screen.** Finding the
selected quest in the scan is not enough. Narrowing the filter past it, or
folding its zone shut, would leave the briefing showing a quest the navigator
no longer lists. The refresh checks the built list, not the scan, and re-picks
when the selection has gone out of view.

**D7 — `isComplete` is a tri-state, not a boolean.** The era answers `1` for
complete, `-1` for **failed** and `nil` for neither. A plain truth test calls a
failed quest done — which puts it in the "Ready" filter and paints it green,
telling the player to walk back to a quest giver who will not take it. Failed
is carried separately and drawn in red with the abandon-and-retake advice.

**D8 — The tracker being full is reported.** `AddQuestWatch` past five declines
**silently** on this client. A Track button that does nothing and says nothing
reads as broken, so the module checks whether the watch actually took.

**D9 — Two doors on the takeover, both live.** Replacing `ToggleQuestLog`
catches the key binding and the micro button; hooking `QuestLogFrame`'s
`OnShow` catches every other path — a quest link, `QuestLog_OpenToQuest`,
another addon. Neither is a one-way door: both consult the setting on every
call, so turning the takeover off hands Blizzard's window straight back with no
reload.

**D10 — One refresh per frame, not one per event.** `QUEST_LOG_UPDATE` arrives
in bursts: several per accepted quest, and again on every objective tick. A
pass per event relayouts both panes a dozen times a second during an ordinary
grind. Events set a flag; a 0.05s timer does the work once.

**D11 — Chrome is drawn from quads, borrowed art is the exception.** The
selection bar, the collapse chevrons, the progress bars and the reward quality
rings are all `WHITE8X8` quads tinted from Commander_Console's palette, for the
reasons Meters and Bags document: ARIALN renders shape glyphs as missing-glyph
boxes, icon *files* move across client patches, and `IconBorder` writes do not
stick on this client. The one Blizzard region deliberately kept is
`Interface\QuestFrame\QuestBackground` behind the window — already vetted in
this suite by Commander_Console — because it is the quest log's own parchment
and is what makes this read as a quest log rather than as a generic browser.
*(D26 adds the second and last exception: Questie's own quest-giver icons,
on the world-map pins, drawn only while Questie is loaded.)*

**D12 — The window never takes keyboard focus on open.** It is opened with a
key, and an autofocused search box turns WASD into typing. This is the trap
Commander_Vault paid for at the banker; the search box is reachable by click or
by its own binding.

**D13 — No quest database.** *(Superseded by D19: the Log still reports only
what the client knows, but the Zones tab and the world-map drawer read
Questie's database — the one this decision pointed at — rather than shipping
a second.)* The module reports what the client knows and
nothing else: no turn-in locations, no chain lookups, no levels for quests you
have not taken. Questie already does that, does it from a shipped database, and
is a different piece of software. Everything here comes from the live log.

**D14 — Every piece of text in this window sits on dark.** *(Superseded by
D16: the half-black inset over the paper never made the panes dark, only
muddy, and the text sat on tan all along.)* Both panes carry
their own dark inset and the toolbar carries a dark strip, so the parchment is
a *frame* rather than a background. This is not decoration: Blizzard's disabled
font is a mid-grey that all but disappears on tan, which is the same trap
Commander_Oracle hit over grass. The filter labels take an explicit colour
applied **after** the font object is swapped, because swapping it re-applies
the font's own colour and would wash out anything set at build time.

**D15 — Briefing blocks are pooled by position, so font and colour are
re-applied every pass.** Two quests of different shape put different kinds of
line at the same position: block five is the green "Ready to turn in." on a
complete quest and an ordinary objective on an active one. A pooled block
handed over as-is renders that objective in the heading's font and colour for
the rest of the session.

**D16 — On paper, every colour is ink.** The parchment is the default skin,
and the in-game report was that the log was hard to read on it. The neutrals
had been re-picked for the paper; everything *semantic* had not. Difficulty
yellow is (1,1,0), a green item is (0.12,1,0), an objective still to do was
(0.92,0.86,0.6) — colours chosen for a near-black panel, and on tan each is
within a shade of the sheet. So every colour written on the paper now goes
through one function, `Paper()`, which keeps the hue and scales it down to a
fixed ink luminance (0.34); a colour already that dark passes untouched, and
so does everything when the skin is not paper. The sheet itself moved from a
mid-tone tan to cream, and the panes' half-black wash (D14) became a thin wash
of ink — paper is light, and the ink does the contrast. The alternative,
keeping the bright literals and darkening the paper under them, is the dark
skin, which already exists. Harness section O holds the two skins to it.
*(2026-10-04.)* Fills too: a selection band, a rule, a tab or filter
underline, a chevron, a chain's current-quest band. They took the console
accent as it is, on the reasoning that a pale tint suits any background, and
the default accent is white -- on cream, no mark at all. Everything drawn on
the sheet now takes `InkAccent()` (the accent put on the paper; the accent
itself off it). The toolbar's strip, which D14 made 45% black so light labels
sat on dark, is a thin wash of ink on the paper like the panes: the labels
on it have been ink since D16, and ink on that strip read at 1.2:1. Window
harness Q2. *(Round 2.)* The pale strip made a HOVERED label vanish: the
highlight font is white, and white over the wash reads at 1.6:1. On paper a
tab or filter is inked while the pointer is on it too (`InkOnHover`: at once,
and again a frame later, after the client's own swap); off the paper the
white hover stays. No font object of our own, which would be a global name.

**D17 — The sheet is dark stone by default; parchment is a choice.** D16
made the paper legible, and the next report was that legible paper is still
too bright next to a suite that is dark everywhere else. So the sheet keeps
the quest log's own dialog border and header plate but is cut from the dark
stone of Blizzard's dialog boxes (`UI-DialogBox-Background-Dark`, the
Console's "Dark Stone"), carrying the same light ink as Window and Dark. The
paper stays in the dropdown for anyone who wants the stock look, and it is a
choice now rather than a default: a log saved before `StyleGeneration`
existed that is still on PARCHMENT is moved to STONE once at load, and the
generation stamp means a parchment picked after that is never moved again.

**D18 — Two clocks under the navigator, and the weekly one is checked
against the calendar.** The daily reset is `GetQuestResetTime`, the era's own
clock and the one Blizzard's TBC quest log hangs its daily count on. The
weekly reset — arena points paid, raid lockouts cleared — has a modern API
in this binary, `C_DateAndTime.GetSecondsUntilWeeklyReset`, which is
documented on the `classic_anniversary` branch but has never been watched
answer on this client. So it is believed only when its answer is plausible:
in range, not before the next daily reset, and a whole number of days after
it (to within the hour a DST shift can move it). Otherwise the weekly reset
is **computed** as the next daily reset that lands on the region's reset day
— a weekday in *server-local* time, derived from `GetGameTime` against
`GetServerTime`, because KR and TW reset Thursday 07:00 local, which is
Wednesday 22:00 UTC, and a weekday read off the UTC clock is a day late
there. The tooltip says when the figure is worked out rather than read. The
lockout list under the weekly clock carries each instance's own seconds
rather than pointing at the big clock: an extended lock, or a heroic's daily
lock, keeps its own date. The footer is a child of the window, so a closed
window stops the clock for free; a one-second throttle on `OnUpdate` writes a
string only when it changes. Section P of the harness.

**D19 — Questie is the quest database, and this module reads it.**
*(Supersedes D13.)* D13 said there would be no quest database here because
Questie already ships one, and that is still why there is none. What changed
is the question. "How much of this zone have I done, and what is left?" is
about every quest a zone holds for this character, and only a database knows
the quests you have never seen. So the Zones tab and the world-map drawer
read Questie's — the same race-, class- and blacklist-filtered set Questie
draws from, with its corrections applied — and the Log tab stays exactly what
D13 described: the live log, with or without Questie. One file,
`CommanderQuestLogQuestie.lua`, names Questie; the engine
(`CommanderQuestLogCompletion.lua`) is pure Lua over plain tables, so every
rule runs under bare luajit; the window and the drawer only draw what the
engine decided, so they cannot disagree about a number. Questie is an
OptionalDep. Without it the Zones tab says so in one line and the Log is
untouched (harness R). QuestieDB loaded without Questie counts as absent, not
as a degraded mode: it has no blacklist and no character state, so every
percentage it produced would be wrong.

**D20 — Questie's verdict first, then a completionist's reading of it.**
Whether a quest is done, in the log, available, locked or gone is Questie's
call: `IsDoableVerbose`, whose third return is a `DoableStates` number. The
adapter turns the number back into a NAME through a map built from the live
enum at ready time, so a renumbering in a Questie update cannot shift every
row by one, and it always passes `returnText = true`, without which every
answer is AVAILABLE. The engine maps all 33 names. But Questie answers ONE
reason — the first check that fails, in its own order, level before
prerequisites before reputation — and a completionist view that only
repeated it would promise a quest at the next ding and then file it under a
chain. So every locked quest is re-examined from its own fields for every
reason that holds ("Needs level 64 and "Report to Nazgrel""), with Questie's
reason leading. And **missing beats locking**: a permanent reason Questie's
early return hid behind a temporary one — outlevelled, the breadcrumb's
target already done, past this point in the chain, a one-way reputation
gone past its limit — makes the quest missed now, not at the level-up, so a
ding never shrinks a zone's denominator. A quest with no verdict, or one this
file does not know, goes through a raw classifier that mirrors the same
checks; another race's or class's quest is not listed at all, as in Questie's
own Journey. Engine harness B–E.

**D21 — What 100% means.** The denominator is every quest this character
has done or can still do in the zone: done, in the log, available now, and
locked — behind a level, an earlier quest, a reputation, a skill or a choice
still to be made. Listed but never counted, each under its own heading and
each for a reason: **missed** quests, gone for good and each with why;
**the other Aldor or Scryer side** (D23); **dailies, repeatables and
seasonal** quests, which come round again and so have no "done";
**optional** quests, Questie's `HIDE_ON_MAP` set, mostly sets removed in
later patches and several mutually exclusive, which would otherwise leave
some zones unable to reach 100% at all; **ignored** quests, the player's own
per-character list (`CommanderQuestLogChar.Ignored`, never Questie's hidden
list — writing that is writing Questie's state, D28); and **also starting
here**, the dungeon, class and profession quests whose giver stands in the
zone but which Questie files under their own heading. Three toggles move
quests back in (Count Optional, Count Both Aldor and Scryers, Count Dungeon
and Class Quests), each off by default for the reason its tooltip gives. The
percentage FLOORS: 199 of 200 is 99%, and 100% appears only when the zone is
actually finished. The breakdown ("Done 62 · In log 4 · Open 9 · Locked 12")
reads the counted tally, whose four figures always add up to the
denominator; rows are dimmed by whether they count, not by their bucket,
because an exclusive group's other members keep an ordinary bucket and do
not count. Engine harness G, J.

**D22 — An exclusive choice is one slot, wherever it was made; and
`exclusiveTo` is one-way.** Questie's own Journey counts a quest whose rival
was taken as COMPLETED, so picking one of three moves its percentage by two.
Here a group of quests that exclude each other is ONE slot. Before the
choice, one member counts — one you can take now before one that is locked,
then the lowest required level, then the lowest id — and the others read
"One of 3 choices; only one counts". With one in the log, the others are
locked as a choice. Once one is done, it counts and the others are missed
("You chose ..."). The denominator does not move when you choose, which is
what keeps 100% reachable.

*(Revised 2026-10-04.)* Which quests are rivals is read the way Questie reads
it: **a quest is blocked only by its OWN `exclusiveTo` list**
(`IsDoableVerbose`, and the preGroup substitution in
`IsPreQuestGroupFulfilled`). The data leans on that — 192 one-way pairs in
TBC, most of them a breadcrumb naming the quest it leads to — and reading the
relation both ways, as this decision first did through the adapter's reverse
index, called quests missed that Questie offers ("Plainstrider Menace" after
"Journey to the Crossroads", "Ending Their World" after "Vindicator's Rest").
So each entry is decided by its own list; a slot is built only from MUTUAL
edges (A names B and B names A); and the reverse index only ever names a
choice. Groups still cross zone borders — Area 52's seven, the Netherwing
drakes — and a member's own list still reaches peers outside the zone: a
choice made in another zone moves that slot out of this one ("You chose X",
the total drops by one), deliberately, as before. **Tiered lines.** The
Caverns of Time rings are four lines of four tiers, every later tier naming
the other lines' first quest; union-find over every edge made all sixteen
one slot, and the pledge then moved the zone from 92% to 82%. Now the four
pledges are the slot, and a tier whose list names nothing but that slot's
members, all but one, FOLLOWS the one it leaves out: it counts only while its
line holds the slot ("Follows "Defender's Pledge", one of 4 choices; only one
line counts"), so the denominator is one line's length before and after.
Engine harness H, H1, H2; adapter harness O.

*(Round 2.)* The follower rule also matches breadcrumbs into a choice:
"Muren Stormpike" leads to "Vejrek" and names the other three level-10
warrior quests, and it was uncounted -- in the log, or done -- while the slot
kept counting "Bartleby the Drunk", a line the player was not on. A follower
in the log or done is never uncounted now, and its head takes the slot: the
line the player started is the one that counts. And an uncounted slot member
(an ignored pledge, an optional one) is still one of the slot's CHOICES for
the follower test, though never its holder: ignoring one ring pledge used to
turn every later tier of all four lines into an ordinary quest (Caverns of
Time 17 to 26). Lines of unequal length still move the denominator by the
difference, and the class quests have them: a later quest that names no
choice counts until the choice is made (the Warrior view: 37, 38 with Muren
Stormpike taken, 36 once Vejrek is done). Engine harness H2.

**D23 — The Aldor and the Scryers are a rival side, not a missed one.** In
TBC the other side can be ground back up, so its quests are not gone; but a
completion figure should not assume you will grind it. They get their own
bucket, "Other faction", outside the 100% unless the player asks for both
sides. It is decided by a pure standing comparison — both standings known,
the rival's higher — with no quest ids written down, and it is applied to
every locked quest, not only Questie's MISSING_REPUTATION, because Questie
reports a rival quest above your level as level-locked first and it would
otherwise drop out of the count at the ding. The rule is mirrored through
`requiredMaxRep`: ten pre-pledge quests (10017, 10019, 11094, 11095, 11097
on the Aldor; 10024, 10025, 11099, 11100, 11101 on the Scryers) are offered
only while you stay below Neutral with the side you then join, and without
the mirror Shattrath could never reach 100% on either side. A standing the
client cannot read never locks anything. *(2026-10-04.)* One tie-break: a
character of any race but the Blood Elves and the Draenei starts both at
Neutral, and with the standings level both sides used to count, so the
pledge pulled about forty quests out of Netherstorm, Shadowmoon and
Shattrath at once. With them level, the lower faction id (the Aldor) is the
side that counts and the Scryers' quests are its rivals — "until you side
with the Aldor or the Scryers only one side's quests count". *(Round 2.)* The
tie first covered only gates still UNMET at it; a {Scryers, Neutral} minimum
is met at 0/0 (Firewing Signets, Synthesis of Power, Voren'thal the Seer, the
Sunfury Signets) and so is a maximum on the Aldor (Strained Supplies, the
Scryers' own pre-pledge quest), so they counted and the Aldor pledge still
pulled six out (real Questie, an unpledged human: 534 before it, 528 after).
At an exact tie those are the other side's too (`TieSide`), except an open
one with both sides counted, which stays open; an Aldor pledge now moves
nothing (528 and 528). A Scryer pledge swaps the sets, and they are not the
same size: Shattrath 26 to 25, Shadowmoon 134 to 135, and Netherstorm by a
whole chain (116 to 133) when the Aldor's Netherstorm chain is already gone
because another Area 52 breadcrumb was taken (D33) -- the tie is static and
does not ask which side's chain is still reachable. And a rival quest behind
a prerequisite gone for good (the other side's pledge, "Assist Exarch
Orelis") is missed, not the other side's (D33). Engine harness F, Q.

**D24 — A zone is a quest-log heading, read from Questie's `zoneMap`.**
Which quests "belong" to a zone is the question the quest log itself already
answers: the zone heading a quest is filed under, which is Questie's
`zoneOrSort`. The adapter reads `QuestieJourney.zoneMap[areaId]` — Questie's
own index, built once at login and already race-, class- and
blacklist-filtered — with every id checked against `QuestPointers`, because
a Questie bug files NPC ids in it too. The orphan subzone 3535 is folded into
Hellfire (3483); dungeon wings are folded into the quest-log group Questie
files most of their quests under (Hellfire Citadel 3563, Auchindoun 3917,
Tempest Keep 3845, Caverns of Time 1941), and a group's view reads its wings'
keys as well, because Questie files a few quests under the wing. The Coilfang
wings are the exception: Questie files their quests under each wing's own
key, so each is a zone of its own. Where a quest STARTS is a different fact
and is kept as one: a row whose giver stands elsewhere says "starts in
Shattrath City", quests filed elsewhere whose giver stands here are the
uncounted "Also starting here" layer, and map pins go where the givers
stand. Questie's ids are AreaTable areaIds and the world map's are uiMapIDs
(area 1941 is the Caverns of Time, map 1941 is Eversong); every variable says
which it holds, and the adapter is the only bridge. Adapter harness C, D, E.

**D25 — The map drawer is a plain child of `WorldMapFrame`, and never sets a
strata.** The question gets asked with the map open, and the maximized map is
FULLSCREEN over this HIGH-strata window, so the answer has to live on the map
too. The drawer is parented to `WorldMapFrame`, so it rides the map's own
FULLSCREEN/MEDIUM switch; a strata of its own would leave it behind the
maximized map or floating over the windowed one. It is anchored inside the
`ScrollContainer`'s right edge, (-8, -40) to (-8, 8), clear of Questie's map
button row, and Blizzard re-points that container in both modes, so the
drawer follows every layout without knowing a size: 250 wide maximized, 220
windowed. Its frame level is the container's plus 2200 or ten over the map's
topmost pin level (`GetPinFrameLevelsManager`), whichever is higher, capped at
9000: the pins' levels are absolute, from 2000 up, and on TBC the player
arrow, the party dots, the corpse and the battlefield flags sit at 2753-2757,
over a container-relative 2200 *(2026-10-04)*. No field on `WorldMapFrame` is ever
assigned — the hooks are `hooksecurefunc` and `HookScript`, and the one write
is a key added under `pinPools`, as HereBeDragons does — and nothing secure
goes near the map, which would pull Blizzard's own resizing into combat
protection. "Open in the quest log" closes the map first with `HideUIPanel`
(Questie avoids `:Hide()` there for taint) and then opens the Zones tab on
that quest — out of combat only: in combat `HideUIPanel` from addon code is
refused and reported as blocked, so the window opens with a line saying to
close the map with M. The open drawer covers the map's east quarter, so a
quest pulsed from a row or from Show on Map has its pins lifted over the
drawer for the pulse (the pin's `ApplyFrameLevel`), rather than pulsing
unseen underneath it. The header tooltip says what the five groups leave out,
and Focus on a quest with no row answers not found. The drawer lists five groups only — In your log, Open, Locked,
Missed, Done (folded) — and leaves the uncounted headings to the Zones tab;
on a continent it lists the zones with their percentages, worked out in the
background. No LibStub and no Krowi button, which would mean a global frame
name, a TOOLTIP strata and a library dependency. Map harness A, B, E.

**D26 — Pins come from our own data provider, and Questie's icons are the one
borrowed art.** The pins mark the quest givers Questie does NOT draw — the
locked ones, and on request the done and the missed — and never one it does:
a quest in Questie's `AvailableQuests` set gets no pin of ours whatever its
status, so two icons never stack. The provider is a
`MapCanvasDataProviderMixin`, and since the suite ships no XML the pin pool
is HereBeDragons' recipe *as HBD runs it on this client*:
`CreateUnsecuredRegionPoolInstance`, then the creation and reset functions
set under both their old and new names, registered under `pinPools`.
*(Corrected 2026-10-04.)* The first build used `CreateFramePool`, which on
2.5.6 is the SECURE pool — a proxy that ignores writes to its fields — so
every pin was a bare frame, `AcquirePin`'s `OnLoad` errored, and the bare
frame stayed active for Blizzard's every-frame pin passes to error on, with
no pin of ours ever drawn. The SPEC had cited HBD's overwrite and missed the
branch above it. Where the unsecured pool is missing, `CreateFramePool` gets
the mixin through its sixth argument, `postCreate`, which both pool
generations honour. The map harness's pools are now the real ones' shape. Pins carry HBD's no-op `SetPassThroughButtons` (its in-combat
fix) and take mouse motion only, so a click still reaches the map. The art
is Questie's own icon files — available, grey available, the checkmark —
which is the one exception to D11 beside the quest log's parchment: a pin
exists only while Questie is loaded, so the files it draws are always there,
and a giver drawn in Questie's style reads as one at a glance. The focus ring,
the continent labels and the drawer are quads and plain words. Map harness C,
F, H, K, N.

**D27 — Waypoints go to TomTom, then Commander Orders, then the chat
frame.** TomTom is what a player who installed it expects to see; Commander
Orders' arrow is the suite's own, there whenever Orders is; and with neither,
the coordinates are printed, because a Waypoint button that does nothing is
worse than one that tells you where to go. Orders answering false (a map
with no world coordinates) falls through to the chat line. Every Waypoint
tooltip says which of the three will run before it is pressed. A quest in the
log and ready goes to its turn-in; otherwise to its giver in the viewed zone,
else the first one anywhere. Adapter harness K.
*Superseded by D35 (1.5.0, 2026-10-04): TomTom left the suite, and Commander
Orders 3.0 is the one path; the chat line stays as the refusal.*

**D28 — Questie is read through its internals, behind feature checks and
pcall; never written, never kept.** Questie publishes a ready signal and an
update callback and no data, so the data is read from its modules behind
`QuestieLoader._modules` — internal, working, and without a contract. The
discipline that makes that safe: modules are looked up, never imported
(`ImportModule` silently creates an empty module for a name it does not
know); the ready callback runs inside Questie's own init coroutine, so it
only schedules the work a frame later; calls that look like reads and are
not — `IsDoable` (writes the autoBlacklist), `IsComplete` (scans every bag),
`HideQuest` (writes the hidden list and redraws), `GetZonesWithQuests`
(mutates and yields), `IsLevelRequirementsFulfilled` (caches by quest id and
would poison Questie's map filter) — are never called, and the fake Questie
the harnesses run on raises on each; tables Questie reassigns at runtime
(`complete`, `currentQuestlog`, `QuestPointers`, `hiddenQuests`) are read
through their module every time and never held; the client's
`GetQuestTagInfo`, which answers nil on first ask and makes Questie schedule
a retry timer per quest, is never touched (dungeon and raid tags come from
where Questie files the quest). Every Questie call is pcall'd, and every
public entry point that walks Questie's answers runs under pcall too, so a
Questie update that changes a shape costs a section of the Zones tab, never a
Lua error in the window; `/cql status` says what went wrong. Adapter harness
A, B, N, P.

**D29 — One generation number, stepped once per burst.** Everything cached
is cached against a generation. Questie's update callback, QUEST_ACCEPTED,
QUEST_TURNED_IN, QUEST_REMOVED, UPDATE_FACTION, SKILL_LINES_CHANGED,
PLAYER_LEVEL_UP, an Ignore, a settings change and the log's set of ready
quests changing all Bump; bumps within 0.25 s become one step and one call to
each listener. The delay also lets Questie's own QUEST_TURNED_IN handler
update `complete` first. Full engine views are kept for the last three zones;
the three numbers a percentage needs are kept for every zone ever computed,
so the zone menu and the continent labels never blink. A zone is computed on
demand, synchronously, one at a time — about 150 quests — and never all at
once: continent percentages are worked out one zone per 0.05 s tick, and the
reverse exclusive index reads 400 quests per frame after ready and steps the
generation when it is done. The window redraws through its own one-pass-per-
frame queue (D10), the drawer coalesces to one redraw a frame.
*(2026-10-04.)* A generation step no longer rewinds the background summary
jobs: a zone menu's job outlived its menu and, rewound by every reputation
kill, rebuilt whole zones twenty times a second through a dungeon. A job now
finishes its pass against whatever generation each zone meets, and the drawer
re-asks for what is not current on its own redraw. Summaries are built from
facts without their givers (half the cost on real data), and land in the
drawer at most four times a second. A reputation or skill change is bumped
again 2.2 s later, after Questie's own 2 s bucket has refreshed the caches its
verdicts read. "Ready to hand in" is read off the client's log
(`GetQuestLogIndexByID`), not only the window's scan, so the drawer knows it
with the window shut. *(Round 2.)* That call cannot index a quest under a
heading collapsed in the stock log, and the scan does not cover it either
(it expands first, D3), so `IsQuestComplete(questID)` is asked then, and
believed only when it says complete. The late look after a reputation or
skill change is trailing-edge: a change that arrives while it is pending,
later than it covers, gets one more look a bucket after itself, so a second
kill's reputation 1.2 s after the first is not read before Questie's bucket
for it has run. Tier crossings never needed it (Questie refreshes at once on
"You are now Friendly with ..."); in-tier thresholds and skills do. And on a map show the pins are drawn once, in the map's
own provider pass. Adapter harness G, H, I, J, Q; map harness D, G, M.

**D30 — The Zones tab is its own file with its own widgets.** The Log's rows
and briefing are closures written for the live log (right-click tracks,
objectives come off the client's selection), and threading a second mode
through each of them would make every Log code path a mode switch — the
regression risk this tab is not worth — and would spend the 200-local and
60-upvalue budgets of a file that is already large. So
`CommanderQuestLogZones.lua` builds its own tabs, toolbar set, zone card,
navigator rows, briefing pools and action buttons inside the same frame, and
the window shows one tab's widgets and hides the other's. The two share ink
through `Q._kit`, which `CommanderQuestLogUI.lua` exports, because a second
`Paper()` that drifted from the first is exactly how D16 would quietly come
undone. Folds are separate namespaces: `ZoneCollapsed` for the Zones tab,
`MapCollapsed` for the drawer, never the Log's `Collapsed`; Restore Defaults
keeps all three, and the per-character ignore list too. Group titles are fixed
strings because they are the fold keys, and a chain whose title collides with
another is given a distinct one. The LEVEL and NAME groupings are flat lists
in the engine's ascending order with no heading at all, so a fold made in the
Guide cannot hide their rows. The new globals are few and named:
`CommanderQuestLogChar` (the per-character saved variable),
`CommanderQuestLog_OpenToZone` (the way in from the map drawer and
`/cql zone`), and three frames — `CommanderQuestLogZoneGroupDrop` and
`CommanderQuestLogZoneMenu`, because `UIDropDownMenuTemplate` names its
children after its parent and will not work without one, and
`CommanderQuestLogMapDrawer`, so `/dump` can reach the drawer. Window
harness Q.
*(1.6.0: the Zones tab's widgets are now built by the catalogue factory and
the tabs are a register, D36; "the window shows one tab's widgets and hides
the other's" becomes "every other tab's".)*

**D31 — On the Zones tab, nothing selected means the zone.** The briefing
with no selection is the zone's overview — the completion bar, the
breakdown, NEXT UP, the chains, the missed and why — so a selection a filter,
a search or a fold takes off the list falls back to it rather than to the
first row (D6, kept: the briefing never shows a quest the list does not).
Clicking the briefed row again, Escape on an empty search, or a click on the
zone card also go back to it. A quest asked for by name — the map drawer,
`CommanderQuestLog_OpenToZone` — is different: the caller wants that quest,
so its search is cleared, the filter opened and its group unfolded. Each tab
keeps its own search text in the one shared box, swapped with `SetText` on a
tab change, which `OnTextChanged` sees as not user input. The Zones tab never
moves the client's quest-log selection (D2): it reads a quest in the log only
through `Q.ReadDetail`, and puts back an EMPTY selection that call leaves
moved. A quest link or a tracker click asks for a quest in the log, so it
lands on the Log tab whichever tab was up. *(2026-10-04.)* The same holds the
other way: Open in Log asks for a quest by name, so the Log's own fold,
filter and search are opened for it (`Q.RevealInLog`) rather than its
re-pick briefing the first row. The Zones search matches quest names only —
its headings are status groups, and "pick" used to list the whole "Pick up
now" group — and the box's tooltip says which search it is. Each tab opens at
its own top, and the zone card's inset follows whatever decides the Zones tab
draws. *(Round 2.)* A quest asked for from outside — Open in Log, a quest
link (`CommanderQuestLog_OpenToQuest`), the map drawer
(`CommanderQuestLog_OpenToZone`) — also has its row scrolled into view, a
third of the pane below the top, when it is off screen; the tab switch had
just put the list at its top, and the last quest of a long log was briefed
with its row 250 px below the fold. Only for those: a refresh never moves
the player's own scrolling. Window harness Q, Q2.

**D32 — Show on Map refuses in combat, and steps aside only for a windowed
map.** Opening a Blizzard panel from addon code is the one thing the Zones tab
does outside its own window, so it is refused in combat with a line saying
so. Out of combat it opens the map on the zone and hands the drawer the
selected quest and its zone, so the drawer can move the map itself if the
`SetMapID` did not land. A maximized map is FULLSCREEN and covers the window,
which is still where it was when the map closes; a windowed map is MEDIUM and
this window (HIGH) would sit on top of it, so the window closes. Window
harness Q.

**D33 — A quest whose only way in is gone is missed; Riding is a lock.**
Questie answers a quest behind a lost prerequisite with
`NO_PREQUESTSINGLE`, a temporary verdict, so it stayed counted and locked for
ever: an Aldor who took any other Area 52 breadcrumb can never do "Assist
Exarch Orelis", the only way into sixteen Netherstorm quests, and a
completionist Alliance run stopped at 86%. So after classifying, the engine
walks the prerequisites itself: a locked quest whose every preSingle, or any
preGroup member, is gone for good is missed ("Needs "Assist Exarch Orelis"
(Shattrath City), which you can no longer get."), repeated until nothing
moves, so a chain falls with its first link. Gone means missed in this view,
or — outside it — Questie's own verdict being final (`char.isGone`: exclusive
done, past in chain, skipped breadcrumb, outlevelled, blacklisted, disabled,
another race or class). A preGroup member that a quest in its own exclusive
list could still stand in for is never called gone, and an outside quest's
own prerequisites are not walked: both err towards counting. *(Round 2.)*
The other Aldor or Scryer side is walked too: its standing can be ground
back, a lost pledge cannot, so "A Cure for Zahlia" behind "Allegiance to the
Aldor" is missed for a Scryer rather than "gated on the faction you did not
side with" -- and with both sides counted, Netherstorm no longer sits at 88%
for ever (horde70: 146 counted, 130 now). Riding is the
mirror case: Questie keeps riding-gated quests in their zone, every character
can train it, and "no Riding skill line yet" is a lock ("Needs 225 Riding and
level 70."), not a quest missed — or the denominator grew when the player
trained it. Glowcap Mushrooms, capped below Friendly with Sporeggar and left
out of Questie's one-way list ("TO DO CHECK THIS"), is on the adapter's own.
Engine harness Q; adapter harness Q.

**D34 — The zone menu pages a long category.** The Classic dropdown never
scrolls and is not clamped to the screen: a level-2 list grows 16 per row
and, near the bottom, flips to grow upward — off the top. At the window's
default spot on a 768-unit screen 24 rows fit, and the Dungeons list holds
34 (with Serpentshrine and Magtheridon's Lair, which Questie files quests
under but leaves off its own Journey list). So a category over 20 zones is
cut into pages, each its own row, and a category row keeps the menu open
when clicked rather than hovered. *(Round 2.)* The cuts fall where the
initial changes, nearest the even split: an even cut of the real 34 fell
inside the R's ("A-R" and "R-Z", Razorfen on the second page), and two rows
claiming one letter tell the player nothing. Now "Dungeons  A-O" (16) and
"Dungeons  R-Z" (18). An initial is a whole UTF-8 character (a byte of
"Ödland" was an invalid string on a deDE client), and where one letter runs
past a page the rows are numbered as well ("(1/2)"). Window harness Q2;
adapter harness Q.

**D35 — Waypoints and zone routes go to Commander Orders, owned, with every
spawn.** (1.5.0.) Commander Orders 3.0 replaced TomTom across the suite, so
the TomTom-first chain of D27 is gone and so is the legacy
`CommanderOrders_IssueOrder` (one account-wide slot that every caller
overwrote). A Waypoint press calls `CommanderOrders.Add` with source
"QuestLog" and key "quest:<id>": the quest owns ONE waypoint, and pressing
again -- the giver first, the turn-in once the quest is ready -- moves it
rather than stacking a second. It carries every placed spawn of its giver as
`alternatives` (the zone's facts keep eight, a turn-in reads up to 32), so
Orders points at the spawn nearest the player and re-picks as they move;
TomTom was handed whichever spawn Questie listed first, which for a patrol is
often the far end. Session only, Orders' default for a consumer: a quest
waypoint is an errand, not a place to keep. Orders refusing -- absent, turned
off, a map with no world position -- prints the place and a `/way` line (D27's
"never do nothing" survives), and the tooltips name the path before the
press, telling "turned off" apart from "not loaded". **Route Zone** on the
Zones tab's action bar, and a right-click on the map drawer's header strip,
hand Orders ONE nearest-first route through the givers of the zone's OPEN
quests: the AVAILABLE bucket, the drawer's "Open" group, so ignored, daily,
seasonal, optional and rival quests stay off it; a giver with several open
quests is one stop; a giver standing outside the zone is still a stop,
because its quest counts here; item starters have nowhere to go. The route is
owned as (QuestLog, "open:<areaId>"), so routing the zone again replaces it.
The button is greyed out without Orders rather than printing a dozen lines.
Finally the adapter answers Orders' "entrance" question for DUNGEON maps from
Questie's own dungeon table (`ZoneDB:GetDungeonLocation`), so a giver inside
a dungeon, or a ghost's corpse in one, is pointed at the way in; only dungeon
maps are put through Questie's uiMap-to-area bridge, whose fallback is a name
match over every area. Two corrections over Questie (2026-10-04 review): its
override table answers uiMap 246, The Shattered Halls on this build, with
3713, The Blood Furnace (`uiMapIdToAreaId.lua:15` beats its correct base
row), so a small known-bad table answers 246 with 3714 first and the Halls
get their own door; and the map ASKED about may be Orphan-typed (6), because
this build types The Black Morass, Old Hillsbrad, Hyjal Summit, Zul'Aman,
Zul'Farrak, Zul'Gurub, Dire Maul and the Ruins of Ahn'Qiraj that way and
every one has an explicit Questie row with a dungeon location; the walk to
parent maps stays on Dungeon maps. Adapter harness K and O, window harness Q, map harness
D and F, and the contract harness (questlog_orders_contract.lua) A-E, which runs
the adapter against the real Orders: the dungeon giver getting its entrance,
the nearest spawn winning, the route taken.

**D36 — The Zones tab is one catalogue instance; the tabs are a register.**
(1.6.0. Supersedes D30's two-tab wording; D30's reasons stand.) A second
browser over Questie -- every quest of a faction -- was the Zones tab again
over another set of ids, and threading a mode through it would have been
exactly the mode-switch D30 turned down. So the generic three quarters of
`CommanderQuestLogZones.lua` moved into `CommanderQuestLogCatalogue.lua` as a
factory, `Q.NewCatalogue(spec)` (= `Q.Catalogue.New`): every call builds its
own toolbar set, card, rows, briefing pools, actions and state, all on first
use, and a spec says where its quests come from and how its card, overview,
rows and briefing differ (the hooks are listed at the top of the file).
`Q.Zones = Q.NewCatalogue(ZONE_SPEC)` keeps every name it had: its public
functions, the `Zone*` keys, `S.areaId` / `S.areaName` (read-only aliases of
the generic `S.key` / `S.keyName`) and the W field names. The window's tabs
are a register, `Q.RegisterTab{ id, order, label, width, tooltip, IsEnabled,
Refresh, HideAll, SearchText, SetSearch, EscapeSearch, NavTopInset,
SearchTip, PrepareOpen }`, which each catalogue joins itself (as `Z.tab`); the
Log registers too (order 10; the Zones tab 20, the Reputations tab 30). The
26 places that knew "Log or Zones" now ask the register: `ViewMode` is a
registered, enabled tab's id or the Log (an unknown or switched-off id opens
the Log), `Q.Refresh` hides every tab but the one it draws, a quest link from
any tab lands on the Log, the search box routes to the tab that is up, the
buttons are placed by order and width, and `Q.OpenToTab(id, key, questId)`
is the one way in from outside (`CommanderQuestLog_OpenToZone` is it with
"ZONE"). The strip is hidden only when no tab but the Log is enabled, which
generalises "Zones Tab off hides both tabs". Frame names follow one stem
rule, because `UIDropDownMenuTemplate` names its children after its parent:
an instance's two dropdowns are `CommanderQuestLog<prefix>GroupDrop` and
`CommanderQuestLog<prefix>Menu` and its settings `<prefix>Filter`,
`<prefix>Group`, `<prefix>Collapsed`, `<prefix>Follow`, `<prefix>Picked` --
so the Zones tab keeps its two frames and the Reputations tab adds
`CommanderQuestLogRepGroupDrop` and `CommanderQuestLogRepMenu`, the only new
frame names. Every catalogue shares one adapter generation listener. The
factory's body closes over 40 of Lua's 60 upvalues: a new shared helper
belongs on `Q.Catalogue` (reached through `cat`), not in another file-level
local. Window harness Q3; every other window check unedited.

**D37 — One reputation number per quest, from our own rules; never
Questie's.** (1.6.0.) The brief came from a player sweeping Hellfire for
Honor Hold who found too late that some quests paid next to nothing, so
every surface that shows a quest says what it pays this character NOW, and
they must agree. The number comes from one place:
`CommanderQuestLogStanding.lua` (`Q.Standing`), a pure engine over the
generated data (D38) -- no client API, no Questie, its inputs handed in --
through the adapter's `A.RepEffects` / `A.RepLine`, worked out once per quest
per generation and shared read-only by every surface. Questie's
`QuestieReputation.GetReputationReward` is never shown: it never rounds
(+137.5), takes a Human's rival loss from the raw value (-275 where the
server takes -302), has no reward clamp, boosts the stored Sha'tar row as if
it were a reward and shows a Human +46200 for Ally of the Netherwing. The
rules are the server's (CMaNGOS `CalculateReputationGain` and
`SetReputation`) with the client's Faction.db2: every turn-in truncated
toward zero on its own (a Human's 25-point mark is 27, never 27.5);
Diplomacy (`UnitRace`'s race file "Human") and Invocation of the Wickerman
(aura 24705) +10% each, added for a gain and taken away for a loss, read at
the moment of asking and never stored (a change in the aura is a Bump); the
doubled quest rate of Argent Dawn, the Cenarion Circle and Timbermaw Hold;
the quest's reward clamp, then the 42,999 ceiling, THEN spillover from that
clamped, boosted gain at the DB2 edge's own rate (a header passes at each
child's rate, critic W4); the Aldor / Scryers loss is the -110% edge, not a
stored row; the other side's factions are dropped, since an audited quest
can pay Honor Hold AND Thrallmar (critic 3.9); no low-level penalty (CMaNGOS
"2.0.1"; the rules flag `lowLevelQuestPenalty` stays for calibration).
CMaNGOS's quirk is kept: any result, a loss too, is 0 once the standing is
at the quest's clamp. A quest capped to nothing says "0 The Aldor (capped)",
never "No reputation": the quest is worth nothing to you now, and that is
the news. Standing smoke; adapter harness R1 and R12; the cross-surface
check, rep-everywhere harness H.

**D38 — The reputation data is generated, stored spillover is dropped, and
a Wowhead correction must beat both databases.** (1.6.0.) No client API says
what a quest pays (`GetQuestLogRewardFactionInfo` is not in the 2.5.6
binary), so `Harness/make_reputations.py` writes
`CommanderQuestLogReputationData.lua` -- the one new global, pure data --
from the Faction DB2 for this build (bases, parents, spill rate and the
highest rank a spill lands in; the same table per locale for names) and the
CMaNGOS dump (the reward clamps, item costs, rotating givers), with the
template-against-DB2 reconciliation recorded in the file and held to zero
by its smoke. Questie's rows carry spillover written in as if it were a
reward: the Sha'tar's half on 85 Aldor and Scryers quests, the Exodar's on
4766 and the goblin towns' on 9266 / 9268 (those two exist only in Questie,
so the generator carries them as a snapshot that `--questie` re-checks).
These are `derived`, dropped and regenerated from the spill rules, which
also gets the window and Diplomacy right; otherwise the Sha'tar is paid
twice. An equal pair on a header's 100% edge (281: Alliance and Gnomeregan,
7642: Alliance and Darnassus) is NOT marked: equality there proves nothing.
The reward clamps are every RewMaxRepValue row (critic W1's fifteen quests)
plus one written by hand, 10871 = 0, the Human copy of 10870 that CMaNGOS
only has as a stub. Item costs are flat pair lists (80 turn-ins take more
than one item) for every rep-paying repeatable and daily, classic ones too,
because the picker lists classic factions by default. Overrides come from a
Wowhead audit (190 quests) and every one cites its page; but Wowhead's /tbc/
pages turned out to carry the Wrath value on a family of quests (Sporeggar
750 -> 250, Mag'har and Kurenai halved, Hero of the Mag'har 2000 -> 1000,
Mana-Tombs Wanted 350 -> 500), so a row is overridden only where Wowhead
disagrees with BOTH databases AND a TBC-era source or plain arithmetic backs
it. Five pass: 10871 (Netherwing 38182 = 42000 / 1.1, so Diplomacy lands a
Human on exactly 0) and the four Hellfire Citadel Wanted dailies (Honor Hold
and Thrallmar 350 / 350 / 350 / 250, which both databases lack; medium
confidence, A44). An override is the quest's complete corrected row set; 0
removes a row. **Widened 2026-10-04** (the lead's decision on the accuracy
review, which matched the engine to an independent CMaNGOS-rules
computation and found these quests differ only by data): where Wowhead
(TBC) AND CMaNGOS agree against Questie, the override is written too. Nine
quests, mostly classic rows that bake the capitals' quarter in and are then
paid again as spillover: 4267, 5096, 6804, 7639, 7640, 7781, 7782, 10016
(Timber Worg Tails, Terokkar: +547 to each Alliance capital became nothing)
and 11211 (+698 to each Horde capital became Gadgetzan 10); each is the
quest's whole row set, Questie's extra rows at 0, cited with a note. 7781 /
7782 (The Lord of Blackrock, five 500 rows) compound -- each capital's 550
plus four 137 spills, as the CMaNGOS server pays it -- and a mixed move is
no sample (D40), so those two rest on the sources (A57). Fourteen overrides
in all. The file is 31.6 KB against a ~20 KB guide (localized
names 5 KB, behind `SHIP_NAMES`; classic item costs 6.5 KB), kept whole for
now. Data smoke K5; standing smoke Q.

**D39 — A faction not met is its starting standing, and an unknown standing
has no word.** (1.6.0.) `GetFactionInfoByID` may answer nil for a faction
the character has not met (A21, A39). Its standing is then its Faction.db2
base for this race and class -- the first base row whose masks fit:
Sporeggar -2500, Kurenai -1200, Mag'har -500, Netherwing -42000, the Aldor
and the Scryers +-3500 for a Draenei or a Blood Elf, the other side's
factions -42000 -- never "Neutral". `C.StandingWord(value, base)` reads the
base when the value is unknown and answers nil with neither (it used to say
"Neutral", critic W6); its one caller always has a number. The completion
engine's `char.repValue` keeps its meaning (unknown never locks, D23) and
`char.standing` is the new reading. The player's side is the client's
`UnitFactionGroup`, else the data's vote (a -42000 base votes for the other
side; the flags do not say it, critic W9). A name is the client's once met,
else this locale's from the data (the 22 TBC factions, nine locales, only
where they differ), else English; standing words are the client's
`GetText("FACTION_STANDING_LABEL"..n, UnitSex("player"))`, English filling a
gap. The picker lists every TBC faction met or not. Engine smoke O; standing
smoke D and L; adapter harness R7.

**D40 — What the game paid replaces the data, per character.** (1.6.0.)
Both databases share a lineage, so the runtime is the tie-breaker. A rolling
snapshot of all 75 standing-slot factions is read once in every frame where
UPDATE_FACTION fires and diffed; the chat line (patterns built from the
client's own `FACTION_STANDING_INCREASED` / `_DECREASED` formats) is the
second source. On CMaNGOS the moves arrive BEFORE `QUEST_TURNED_IN`, so a
turn-in's window runs both ways, one second before and two after. Moves are
matched to the factions the quest may move (its rows and the spill targets
of its direct rows) and stored in `CommanderQuestLogChar.RepObserved` as the
listed value that reproduces the move -- normalised by the multiplier of
the moment (a direct move by 100 +- mods and the quest rate, a spill by the
multiplier alone), so a sample taken under the Wickerman reads right
without it. Thrown out: a move that hit the ceiling, the bottom, a reward
clamp or a spill window's top; a faction another turn-in in the window also
names, or that moved twice (a kill and the quest); a spill share whose
source gain was clamped; a turn-in where nothing moved; and (2026-10-04
review) a MIXED move, which several of the quest's own direct rows made
between them -- a direct faction another of its rows spills into (Orgrimmar
on Cutting Teeth, which pays the Darkspear Trolls too) or a spill target two
of them feed (the Undercity): such a sample is a sum, and read back as one
faction's value it was paid again on every share, doubling 123 quests
(most of Durotar and Dun Morogh, the Exodar and Silvermoon pairs) after a
single turn-in. `R.MixedSources` names them, the adapter sets them aside
("mixed") and drops any an older build kept, and `R.Effects` never reads
one; a spill reads only a share stored as a spill (`R.ObservedFor` is the
reading for a faction's own value). A wrong sample would
override the data, a lost one costs nothing. A direct row whose faction is
met and uncapped, and did not move while the turn-in's other moves were
seen, is a sample of 0: "this quest paid nothing" is exactly what the brief
asked to know. A sample overrides the data for display ("seen in game"); a
faction seen moving that no rule names is shown as seen. Restore Defaults
never touches the samples; a value there that is not a table is dropped at
load. Standing smoke P; adapter harness R9.

**D41 — "Can quests alone get me there" is an ordered, capped simulation.**
(1.6.0.) A sum overstates it. Several quests are offered only BELOW a
standing (the Consortium's crystal and ivory quests under 3000, Sporeggar's
under Friendly, Cenarion Expedition 9784 under 8999), the Sha'tar takes the
Aldor's and the Scryers' spillover only while it is Friendly or below, and an
exclusive choice counts once. So `R.Project` simulates the best order: the
spill window first while it is open, each closing quest slotted in just
before the step that would shut it; then the closing quests still open,
soonest first; then the rest; every turn-in truncated and clamped on its
own. A reward clamp below the ceiling (Ally of the Netherwing pays up to
exactly 0) is ordered like a gate but never locked out; the Aldor and the
Scryers as sources are one choice, the better simulated (an exclusive slot
among the spilling quests -- the two pledges -- is settled inside each
choice, so the Scryers' side is weighed with the Scryers' pledge). A
source's quest spills only if the source's own climb gets it done: the
adapter projects the source over the same quests first (the zone's, or
every quest a faction view lists that pays it) and drops from the window
each quest that projection leaves unreached or locks out, so an unpledged
character's Shadowmoon no longer reads +1,574 for the Sha'tar from Scryers
quests that need Friendly with the Scryers (2026-10-05 review; on the
Zones tab that is "quests here alone", as the source's own line says).
The Sha'tar's
spill stops at 8,999, the top of Friendly ("capTop"): the DB2 says
spillover lands only up to Friendly, and CMaNGOS itself clamps every
Sha'tar row of the mark turn-ins at 8999 (critic W1); the rules' "mangos"
setting lets the last spill overshoot, for calibration (A41). Repeatables
come after the once-only quests (`repeatReach`), never interleaved, so a
ladder whose one-time quests wait on ranks only dailies reach (Netherwing)
reads short on "quests alone". Sporeggar's quests behind Neutral, which
plain repeatables (More Spore Sacs) reach, are no different: the zone
totals hand the zone's non-daily repeatables in too, so `repeatReach` and
`unreachedCount` let the overview say "N wait on a standing" rather than
"0 left in N" (2026-10-04 review; interleaving them would make "quests
alone" untrue on the Reputations tab). The projection also reports what
each quest paid in its order (`gains`). The order gives the hints "Do "A Head Full
of Ivory" before Friendly". Done quests' worth is an estimate: a standing
mixes quests, kills and items. Greedy, not exhaustive: exact for the gate
shapes TBC has. Standing smoke O; adapter harness R3, R6 and R14.

**D42 — Rotating dailies are never income; Halaa is a condition.** (1.6.0.)
The Wanted dailies are one normal (Nether-Stalker Mah'duun) and one heroic
(Wind Trader Zhareem) a day, read from the two givers in the dump (8 and
16). Today's is the one in the log or done today, else the one candidate
Questie's own record of what the NPCs did NOT offer leaves
(`Questie.db.global.unavailableQuestsDeterminedByTalking[realm]`, read,
never written, never kept); quests Questie holds back (the Magisters' Terrace
pair) are never candidates. A pool is summed only when today's is known, and
the day's total is held to `GetMaxDailyQuests()` (25). In Defense of Halaa
and Enemies, Old and New are listed as "only while your side holds Halaa",
not counted. "Done today" (2026-10-04 review): Questie rebuilds its done list
at login and never clears it at the reset (only its "not offered" record),
so a rotating daily done counts as today's only when the session began
after the last reset (`GetServerTime` + `GetQuestResetTime`) or the adapter
saw the turn-in since; otherwise yesterday's Wanted would be named today's
in a session that ran through the reset. A client that cannot say when the
reset was keeps the plain reading. Income is what a turn-in pays from the
standing now (`R.DailyIncome` opts.value: the row's clamp and the ceiling,
the day's total held to the room left), so at Exalted 999 a daily is worth
the 0 its row shows, not +165. Standing smoke N; adapter harness R8 and R13.

**D43 — The Reputations tab.** (1.6.0.) A catalogue (D36), id REP, prefix
"Rep", over `A.FactionView`: the engine's view of every quest that pays the
faction plus `view.rep`, on a cache of its own (two views by generation)
because faction ids collide with area ids (47 is Ironforge and The
Hinterlands); a quest's detail is read by kind ("FACTION"), and Show on Map
opens the zone the quest starts in, so a faction id never reaches anything
zone-keyed. The faction index (every quest's rows, about 6,700 reads) is
read the first time a faction is asked about, 400 quests a frame, never at
login. Membership is a DIRECT row after `derived` and the overrides; a quest
that reaches the faction only by spillover is summed in the overview, not
listed -- except the Sha'tar's window on the Aldor and Scryers quests,
listed in its own "Via Aldor/Scryers (until Honored)" group and never
counted. Following is the faction on the reputation bar
(`C_Reputation.GetWatchedFactionData`; `GetWatchedFactionInfo` is not in the
2.5.6 binary), else the faction the log's quests pay most, else the pin;
only a faction the tab can show (in the data, not a heading, not the other
side's, which is refused). `RepPicked` is account-wide like every key, so a
pin of the other side's faction is an alt's: it is passed over (the card
asks for a pick, the navigator names whose pin it was), never shown as a
dead end this character could not have chosen. The Guide is the engine's retold for a faction:
Turn in, In progress, **Will lock soon**, Pick up now (most rep first),
Unlocks with level, After another quest, Needs reputation or skill, Done,
then the uncounted tail with Repeatable sources and Dailies apart. Will lock
soon sits AHEAD of Pick up now -- the SPEC put it after the locks -- because
the climb shuts those quests and the Guide is the to-do order (one line to
swap back). By zone heads by Questie's own quest-log heading; By value by
what each pays now. A row's badge is the engine's effect on THIS faction;
a 0 is faint and dims its title ("0 capped" when a clamp did it): every
quest listed here pays the faction, so one that pays nothing now is the
news. (The Zones tab never dims for it, D44: there a dim title means "not
counted".) The card's second line is short
(one 280 px line, cut short rather than wrapped onto the navigator -- the
catalogue's card note never wraps): how much is left and where it reaches,
and "pinned" only when pinned; its tooltip says it in full. The picker says
what its number counts ("Honor Hold  Honored  ·  31/49 done", the once-only
quests): a bare percentage beside the standing word read as progress
through the standing. A quest's REPUTATION section is the Zones tab's own
painter (`Z.PaintReputation`, this faction in the strong ink), so one quest
reads the same in the same words on both tabs, and on this tab it comes
straight under the quest's reason with AS A SOURCE / WILL LOCK SOON
(`reputationFirst`): a 22-quest chain put them out of the pane. An item
cost is "Mark of Kil'jaeden x10 a turn-in" (an item's name is never
pluralised by hand). A Wanted pool whose pick is not known says how many of
the rotation pay this faction, "on a day one of them is offered" -- the
engine's count is this faction's share, not the rotation's size, and "one
of 1 a day" promised Honor Hold a Wanted daily every day; with every pool
unknown and no steady daily the section reads "Nothing to count on yet",
not "None you can do today". At the ceiling (Exalted 999 / 1,000, the
engine's `R.CAP`, where it holds every gain to 0) DAILIES is one line,
"Exalted 999 / 1,000: dailies pay nothing more.", and QUESTS "N quests left,
none pays anything more": "up to 0", "worth 0" and a Wanted pick blamed for
a day that pays nothing whatever is offered were the alternative; below it,
open dailies a reward clamp holds to 0 say so in words (2026-10-05 review,
second round). The CHAIN heading says what it counts, "CHAIN (quests that
pay Honor Hold)" (the catalogue's `chainLabel`): the faction view holds only
the quests that pay it, so its chains break at a step that pays nothing and
"18 of 22" is not the Zones tab's "22 of 31" for the same quest. Drawing the
zone view's whole chain here, the 0-rep steps faint, is the fuller fix,
left for when a player asks for it. A faction whose every quest a later phase
holds back says so in the navigator rather than blaming the search. Watch Faction finds the faction's
row by a read-only walk of `GetFactionInfo` and calls
`SetWatchedFactionIndex`; it never calls `ExpandFactionHeader` (that would
rewrite the player's pane) and says so when the faction is under a folded
heading or not met. `/cql rep [name]`: the settings framework matches a
subcommand on the whole line, so DB.lua wraps its slash handler to take
"rep <name>" (any case, apostrophes optional, a prefix, an id) and passes
every other line on. "N quests not in this phase yet" counts the hidden
quests Questie's own phase list (`ContentPhases.BlacklistTbcQuestsByPhase`)
holds back. Reputations harness.

**D44 — Reputation on every surface, the quest giver's dialog included.**
(1.6.0.) The Log's briefing gives "Reputation: +275 Honor Hold" (or "No
reputation") as a reward line, under the facts when a quest has no rewards,
looked up once per quest per generation (D2's discipline). A Zones row's
badge is the biggest direct gain and the faction it is for ("+275 HH",
"+550 CC": the catalogue's `RepTag`, the rules engine's abbreviation made
unique over the zone's factions -- "+550" alone made Missing Missive, a
Cenarion Circle quest, read as Hellfire's best Honor Hold one, the very
surprise of the brief; held to 12 characters by `C.RepBadgeText`, the comma
dropped and then the tag cut to four letters, "+1000 Scry", so the 64-px
cap never eats the tag, A54), a faint "0"
for none or capped -- and never dims the row, because on that tab a dim
title means "not counted"; its tooltip and briefing carry every effect,
with the stock raw-row section kept when the rules failed to load or
Reputation on Every Quest is off (then the briefing is 1.5.0's, raw rows
at the end; with a number to give, REPUTATION comes straight under the
quest's reason). The zone's overview adds REPUTATION IN THIS ZONE straight
under the zone's completion, before NEXT UP -- "can 100%-ing this zone get
me there" is the question, and in Hellfire the chains alone fill the pane
-- per faction: left (the quests the projection does, the dungeon quests'
share named), done, whether it reaches the next standing and how far that
leaves Exalted, what the spill window lands from "the Aldor's" quests,
the quests waiting on a standing these quests never reach (never "0 left
in 2 quests"), the steady repeatables and dailies at their best OPEN
turn-in, the rotating Wanted ones apart ("on a day one is offered (one
normal and one heroic a day in all)") and Halaa's with its condition, and
the quests to do first. A faction at the ceiling (`R.CAP`, Exalted 999 /
1,000) is one name on one line, "Exalted, nothing more to earn here: Honor
Hold.", never "0 left in 13 quests" and "0 a turn-in" under a standing
nobody can raise; between 42,000 and the ceiling the verdict is "Already
Exalted.", as on the Reputations tab, never "Quests here reach Exalted";
quests and repeatables a reward clamp holds to 0 are said in words ("none
pays anything more"), never as a 0 (2026-10-05 review, second round). Every figure there is the projection's own (its
order, unreached, spill window), never a raw sum. Worked out once per zone
per generation, and the Zones tab gains a By reputation grouping. What those
totals count (`A.ZoneRepTotals`, 2026-10-04 review): the zone's 100%, plus
the dungeon quests that start here (the EXTRA layer, whatever Count Extras
says: their reputation is as real, the Reputations tab counts them, and
Hellfire's +2,255 Honor Hold in six of them was missing from "how far")
and the other members of an undecided exclusive choice, because the
choice is per faction (the Scryers' pledge is the Scryers' to make while
the zone counts the Aldor's; a shared slot key keeps one per faction);
never a missed, rival, ignored, optional or seasonal quest, and done and
left read that one set. `extraLeft` / `extraCount` say how much of it is
dungeon quests. The spill share (`viaSpill`) is what the projection's
window LANDS from the one source it chose -- 0 once the Sha'tar is past
Friendly -- not a sum over both rivals, and only from the source's quests
its own projection here reaches (D41). Every per-turn-in figure is what a
turn-in pays from the standing now (0 at the cap, as the row says); the
best repeatable quoted is the best OPEN one (a level-70 Wanted heroic is
no headline at 64), and each repeatable carries `rotating`,
`conditional` and `open` for the overview to set the Wanted pools apart.
The map
drawer's rows and giver pins carry the line in their tooltips, and its rows
a badge only when the map is maximized (the windowed drawer is 30 px
narrower); Reputation on Zone Rows governs that badge too. A quest's
waypoint carries the line as its Commander Orders note, set in `A.Waypoint`,
the one place that calls Orders, and kept current: on each generation step
every note the adapter wrote that Orders still holds unchanged is written
again through Orders' `Update` when the words differ (the Wickerman, a cap,
a sample) -- never re-added, so a waypoint the player removed stays
removed, and never over a note someone else changed. The NPC's dialog gets a line under its
rewards on the offer and the turn-in panels
(`CommanderQuestLogQuestFrame.lua`): post-hooks only -- `hooksecurefunc` on
`QuestInfo_Display` and `QuestInfo_ShowRewards`, `HookScript` OnHide on the
two panels -- one plain nameless frame parented to the scroll child the
dialog draws into, the dialog's own ink (`GetMaterialTextColors`), following
the detail panel's fade, one faction a line under "Reputation:" when a
quest moves several (275 px wraps a single line inside an effect, "+385" at
one line's end and "Honor Hold" at the next one's start; the Log's wider
pane keeps the one line, and "(seen in game)" heads those lines,
"Reputation (seen in game):", rather than trailing the last one), and no field of any Blizzard frame written, so
nothing can taint; the quest is `GetQuestID()`, else for a turn-in the one
log quest with the dialog's title. "(seen in game)" marks a calibrated line
on every full-line surface, never a badge. Show Reputation Everywhere,
Reputation on Zone Rows and Reputation in the Quest Dialog are read as
"~= false" and live, so a setting needs no Bump. Rep-everywhere harness
(its section H is the SPEC's cross-surface check: four quests, eight
surfaces, plain, under the Wickerman and calibrated), quest-dialog harness,
map harness O; adapter harness R13 (the zone totals and the waypoint note).

**D45 — "Go to": the suite's Go buttons, Orders' words, a Go per
objective, and the quest's waypoint gone at the turn-in.** (1.7.0, with
Commander Orders 3.1.) Orders 3.1 made a waypoint press one thing across the
suite: its `GoTo` (a place, or a query for its locator), the suite's
`Commander.UI.GoButton` in Commander_Events, and one words-and-gestures rule
written in Orders' DECISIONS (D31) -- "Go to <Thing>" on a standalone button,
"Go" on a row, "[Go]" in chat, "Waypoint" only the noun; click Go,
Shift-click share the place in chat, Ctrl-click copy its /way line, and on a
list row with no room for a button Ctrl+Right-click Go, hinted in its
tooltip. This module follows it:

- **The buttons.** The Log's action bar has **Go to Turn-in** (was
  Waypoint, 120 px for "Going to Turn-in"); the Zones and Reputations tabs'
  bar has **Go** (it acts on the selected quest, like Track and Share; their
  bar has no room for "Go to Quest" beside Watch Faction). Both are the
  suite's GoButton: lit "Going" while the arrow is on their target, greyed
  with Orders' own reason (`CommanderOrders.Reason`) when it cannot go, its
  tooltip naming the place. Without the GoButton file (an older
  Commander_Events) they are plain buttons on the 1.5.0 path.
- **One call, Orders' words.** Every press goes through `A.GoSpec` ->
  `CommanderOrders.GoTo(place, { source = "QuestLog", key, icon = "QUEST" })`.
  Orders says what happened -- "Waypoint set: ..." behind its Announce
  setting, or ONE refusal line with the place and its [Go] link (whose
  Ctrl-click is the /way line) -- so the adapter no longer prints a /way
  line of its own when Orders is there; its D27 line is now only the
  fallback with no Orders (or an Orders 3.0 without GoTo, which still gets
  D35's spec through Add).
- **Objectives (S2).** Each objective of a log quest that Questie can place
  gets a row **Go** at its line's right end, on the Log's briefing and on
  the Zones tab's briefing of an in-log quest: a creature or kill-credit
  objective to the creature's spawns, an object to its spawns, an item to
  the creatures and objects Questie says drop it (quest items, the one kind
  QuestieDB keeps drops for), an explore objective to its trigger's spot; a
  spawn inside a dungeon is its entrance, as for givers; the player's zone's
  spawns first, at most 48, the arrow taking the nearest. Objective n of the
  log is objective n of Questie's list because the adapter lines Questie's
  objectives up the way Questie's own `GetQuest` does (creatures, objects,
  items, reputation, kill credit, spells, then the explore trigger, each
  put first where Questie's `*ObjectiveFirst` tables name the quest), which
  is how Questie itself matches them against the client's. A finished
  objective, a reputation goal and a spell objective get none.
- **Prerequisites and follow-ups.** A REQUIRES or LEADS TO row still to do
  gets a **Go** to where that quest starts (`A.StarterSpec`, the player's
  zone's giver first).
- **The Log's rows.** Ctrl+Right-click goes to the row's turn-in (the same
  Go as the action bar's); a plain right-click still tracks (D2's Log
  gesture), so the row gesture is the suite's without taking Track away.
  The Zones and Reputations rows and the map drawer's keep their plain
  right-click Go (the drawer's hint now reads "Right-click: Go").
- **One waypoint per quest, four kinds of target.** D35's rule holds across
  start, turn-in, objectives and a follow-up's giver: start and turn-in keep
  the key `quest:<id>`, objective n is `quest:<id>:<n>` (so each button
  lights only for its own target), and a Go that lands drops the quest's
  other keys (`A.NoteGo` -> `A.ClearQuestWaypoints(id, keep)`).
- **Turned in or abandoned, it goes.** Orders 3.1 keeps the waypoint the
  arrow is pinned to across a /reload (its D33, the critic's D5), so a turn-in
  waypoint could outlive its quest. On `QUEST_TURNED_IN` and
  `QUEST_REMOVED` (payload: the quest id) every key of the quest is removed
  through `CommanderOrders.RemoveBy("QuestLog", key)`; keys match whole, so
  quest 900's turn-in never touches 9005's.
- **Another module reads the adapter.** Commander_Objectives' Turn-in Offer
  (3.1, off by default) asks `CommanderQuestLog.Questie.Finisher(questID)`
  (pcall'd) for `{ name, uiMapId, x, y (0..100), spawns = { { uiMapId, x, y },
  ... } }`. Keep that shape, or publish a stable global for it and tell
  Objectives' owner (Orders' DECISIONS D41: Objectives owns the turn-in
  offer).

The window harness (`questlog_harness.lua`) still loads no GoButton, so its
checks keep proving the plain path; `questlog_goto_harness.lua` loads it over
a recording Orders 3.1 and the GoWorld fixture (quest 9005 with an objective
of every kind), and the contract harness's sections F-K run GoTo, the
objectives, one waypoint per quest, the turn-in cleanup across a /reload and
a follow-up's Go on the real Orders. Rejected: an objective Go through
Orders' locator (`{ npc = id }` queries): the objectives are quest data, the
spawn conversion, the dungeon-door rule and the zone preference are already
this adapter's for givers, and a Go must answer the same way as the giver's
next to it; and a Go on every objective line by matching its text against
Questie's names (the index is how Questie does it).

**D46 — A creature inside an instance goes to Orders' door; a greyed Go
promises no press.** (1.7.0, the Go-to review's round 2, 2026-10-05.) Two
fixes Orders' DECISIONS (D37, D42) had left to this module:

- **The door is Orders'.** The suite's lead decision made Orders' shipped
  door table the one way into a dungeon: the arrow's dungeon hint, the
  corpse run, Quartermaster's and Formulary's Gos all use it. `GiverRecords`
  still turned Questie's `{-1, -1}` "inside an instance" spawn into Questie's
  own dungeon spot (`ZoneDB:GetDungeonLocation`), so one dungeon had two ways
  in depending on which Go was pressed: Murmur's objective Go (quest 10095)
  stopped on Terokkar 39.6, 71.0, 100 yd short of the Shadow Labyrinth portal
  in the Auchindoun tunnel, where every other Go lands on 39.63, 73.78; the
  Auchenai Crypts, Sethekk Halls and Mana-Tombs the same (99-103 yd), Gruul's
  and Magtheridon's Lairs 45 and 60 yd. Givers, finishers and every monster,
  kill-credit, object and item-drop objective go through that branch. Now it
  asks Orders' locator first, through its public, documented query
  `CommanderOrders.Locate({ entrance = { area = <Questie's instance area> } })`
  (`OrdersDoorSpots`, pcall'd, cached per generation): every spot it answers
  (the approach where the table has one, every door of a several-door
  instance) becomes a record on its own uiMap. Questie's spot is the fallback
  when Orders is absent, its locator still the stand-in ("loading"), raising,
  or knowing no door. Which zone LISTS the quest stays Questie's: a door keeps
  the area and zone of Questie's entrance drawn on the same map; a door on a
  map none of Questie's entrances is on is a spot for the arrow only (zone
  nil: never counted, never "starts here"). On the real data the two always
  share maps (113 instance areas, none without a shared map, none with an
  extra one), and the zone lists of 17 zones, Searing Gorge, Burning Steppes,
  Tanaris, the Barrens and Thousand Needles among them, came out identical
  before and after; Murmur's and Exarch Maladaar's Gos moved from 100 and
  103 yd off to 0. Rejected: `CommanderOrders.Entrance({ area = id })`, which
  works today (Orders' door lookup takes the shape) but is not the documented
  argument of `Entrance`; reading Orders' door table directly (its private
  data). Contract L, adapter Q2.
- **A greyed Go promises no press.** Since Orders turned the GoButton's
  motion scripts on (its D31), a greyed Go shows its tooltip, and the Go to
  Turn-in's and the Zones and Reputations Go's said "Goes to Commander
  Orders, which is turned off (/corder): a press says so in chat" above the
  red "Commander Orders is turned off (/corder)". 2.5.6 delivers no OnClick
  to a disabled Button, so nothing was said. With the suite's GoButton and
  Orders turned off (`GoGreyedOff`, in the Kit) both now read "Greyed out
  while Commander Orders is turned off (/corder); <the row's gesture> then
  says so in chat, with the place and its [Go] link": the row's gesture is
  `A.Waypoint`, which Orders' `GoTo` refuses in exactly those words. The
  plain button that stands in without the GoButton is not greyed by Orders'
  state and keeps the ORDERS_OFF words, which are true for it. Go harness F.

**D47 — No hole in the quest dialog's reward buttons, whoever left it.**
(1.7.1, 2026-10-24.) Field report: opening the Wanted daily (quest 11371,
one item, 16g 39s) died in Blizzard's own code, "attempt to index field
'?' (a nil value)" at TBC/QuestInfo.lua:513, with
`QuestInfoRewardsFrame.RewardButtons` holding slots 1, 2, 4 and -1.
`QuestInfo_ShowRewards` hides every slot above the quest's count with
`for i = count + 1, #RewardButtons`; over 1, 2, 4 `#` answered 4 and slot 3
was nil. Blizzard only ever asks `QuestInfo_GetRewardButton` for 1, 2, 3
in turn, so the hole was another addon's: RXPGuides 4.11.23 (and 4.11.27,
the latest on 2026-10-24) marks its best reward by asking that factory
for its pick outright. Its quest-log hook (`SelectQuestLogEntry`, which
this module's model calls on every read, so the window trips it far more
than the stock log would) asks for the gold pick by its LOG choice number
when no `QuestLogItem` button answers to the UPGRADE pick, which is -1
whenever there is none: a 4-choice quest makes slot 4 in the dialog's
frame. Its turn-in path asks for -1 outright. Both are RXP's bugs.
The fix here, because RXP's files are replaced on every update and the
bug is still upstream: a post-hook on `QuestInfo_GetRewardButton` asks
Blizzard's own function for every slot missing under the one just asked
for, and hides what it makes until the dialog lays it out
(`CommanderQuestLogQuestFrame.lua`). Blizzard's own calls never leave a
hole, so on them it only reads. Slots under 1, fractions and slots past
`MAX_NUM_ITEMS` (10) are no reward slot and `#` never lands on them, so
they are left alone. The buttons it adds carry this addon's taint, next to
the one above them that carries RXP's, and the dialog reads both in the
same pass; nothing protected happens there. It runs whatever the settings
say, since it draws nothing. Rejected: patching RXPGuides in place (lost
on its next update, and not ours); replacing `QuestInfo_GetRewardButton`
(taints every caller); deleting the stray slots (orphans a named frame,
and the next ask makes a second one under the same global name). Quest
dialog harness J, which first shows the unguarded dialog dying as the
client did (the mock's `#` takes the highest border, as the client's did).
Not yet seen in game: `/dump CommanderQuestLog.QuestFrame._State().filled`
counts the buttons it has made.

## Assumptions worth re-checking in game

The Zones tab, the Questie adapter and the map drawer keep theirs in
`ASSUMPTIONS.md`, each with a `/cql status` or `/dump` line to settle it.

- **`HideUIPanel` inside `QuestLogFrame`'s `OnShow`.** This is the standard
  frame-replacement gesture and the harness covers the logic, but the UIPanel
  manager's own bookkeeping is not modelled. If the stock frame ever flickers
  or leaves a gap in the panel layout, defer the hide by a frame instead.
- **`MAX_QUESTS`.** Read from the global with a fallback of 25, which is the
  era's cap either way; the readout is the only thing that depends on it.
- **`C_DateAndTime.GetSecondsUntilWeeklyReset` on this client.** Present in
  the binary and in the generated API docs, never seen answer in the field.
  D18 guards it; if the weekly tooltip keeps saying "worked out from the
  daily reset" on a US or EU realm, the API is answering something the guard
  rejects, and the rejected value is worth printing once to see why.
- **`GetGameTime` is server-local.** The offset derivation (and so the
  computed weekly reset's weekday) rests on it. If the weekly clock lands on
  the wrong day, check the offset first: `/dump CommanderQuestLog.ReadResets()`.
- **`GetQuestLogTitle`'s third return.** Vanilla answered a tag string, this
  client answers a suggested party size. Both are carried rather than one being
  assumed, so a client that changes its mind degrades to a missing facts entry
  rather than to a number rendered as a word.

# Commander_QuestLog — assumptions to verify in game

The Zones tab, the Questie adapter and the world-map drawer (1.4.0) pass four
headless harnesses, which prove the logic against a fake Questie and a mocked
map and nothing about the live client or the real Questie. Numbered so a test
session can report against them. A1–A4 decide whether the Zones tab works at
all; A12–A15 decide whether the map drawer does; the rest degrade to a missing
line, a slower frame or a wrong colour. A28–A35 were added by the review of
2026-10-04, for fixes whose last step can only be watched in the client,
A36 by its second round, A37 with the move to Commander Orders (1.5.0), and A38 by the Orders review's entrance fixes. The Log tab's own assumptions (the
takeover, the reset clocks) stay at the end of `DECISIONS.md`.

Most tests start with `/cql status`, which prints what the adapter can see:

```
Questie: READY (version …)
Completion engine: loaded
Exclusive-choice index: complete (N quests read, M list a choice)
Generation: n (last: …)
Your zone: Hellfire Peninsula (area 3483, map 1944)
Cached: 1 zone view, 4 zone summaries
Waypoints go to …
Last error: …            (only when something failed)
```

---

## A1 — Questie's internal modules keep the shape the adapter reads

**Load bearing.** Questie publishes no data, so the adapter reads its
internals through `QuestieLoader._modules`: `QuestieDB` (`IsDoableVerbose`,
`DoableStates`, `QueryQuest`, `QueryQuestSingle`, `QueryNPCSingle`,
`QueryObjectSingle`, `QuestPointers`), `ZoneDB` (colon methods
`GetAreaIdByUiMapId`, `GetUiMapIdByAreaId`, `GetParentZoneId`,
`GetDungeonLocation`), `QuestiePlayer`, `QuestieJourney` (`zoneMap`, `zones`,
`continents`), `QuestieCorrections.hiddenQuests` and `Questie.db.char.complete`.
Each is feature-checked at ready time and every call is pcall'd (D28), so a
Questie update that moves one degrades rather than errors.

Symptom if wrong: the Zones tab says "Questie is loaded but did not answer the
way this window expects (…)" and the drawer says "Questie could not be read".

Test: `/cql status` — the first line reads `Questie: READY`, and there is no
`Last error:` line after opening the Zones tab on two or three zones.

## A2 — `Questie.API.RegisterOnReady` fires once Questie's login stages are done, and `IsDoableVerbose` is trustworthy from then

**Load bearing.** `IsDoableVerbose` reads state set across Questie's three
init stages (race and class flags, reputations, professions), so it is called
only after the ready callback, which the adapter answers a frame later. When
`RegisterOnReady` is missing it polls `Questie.API.isReady` once a second for
two minutes and then gives up.

Symptom if wrong: the Zones tab stays on "Questie is still loading…", or
`/cql status` reads `BROKEN — Questie never reported ready`.

Test: `/cql status` about ten seconds after login reads `Questie: READY` and
`Exclusive-choice index: complete`.

## A3 — `IsDoableVerbose(id, false, true, false)` answers the `DoableStates` number third

**Load bearing.** The state is the third return, and only with
`returnText = true`; without it every quest reads AVAILABLE. The number is
turned back into a name through the live enum, so a renumbering is harmless,
but a change in the return ORDER is not.

Symptom if wrong: on a character below 70 nothing in Outland is ever locked,
and every row reads "open".

Test: on a level 60–64 character in Hellfire,
`/run local v=CommanderQuestLog.Questie.ZoneView(3483) for k,n in pairs(v.totals.byStatus) do if n>0 then print(k,n) end end`
lists LOCKED with a non-zero count.

## A4 — `Questie.db.char.complete` is the completed set, and Questie updates it before the 0.25 s debounce ends

**Load bearing for "done".** On this client Questie fills `complete` from
`GetQuestsCompleted()` at login (critic C1) and adds to it in its own
`QUEST_TURNED_IN` handler. The adapter's bump on the same event waits 0.25 s,
which should let Questie's handler run first.

Symptom if wrong: a quest just turned in stays under "Turn in" until the next
event moves the generation on.

Test: turn a quest in with the Zones tab open; within a second it is under
Done and the card's percentage has moved.

## A5 — `C_QuestLog.IsOnQuest` exists on 2.5.6

Not load bearing. "In the log" is asked of the client first; without it the
adapter reads Questie's `currentQuestlog`, which can lag one frame behind an
accept.

Symptom if wrong: a freshly accepted quest reads "open" for a moment.

Test: `/dump C_QuestLog.IsOnQuest(<a questID in your log>)` prints `true`.

## A6 — `QuestieJourney.zoneMap` is what this character's quest log would file per zone

**Load bearing for the totals.** It is built once at Questie's login,
race-, class- and blacklist-filtered (D24). The decoded database predicts
about 90–160 visible quests in a large Outland zone.

Symptom if wrong: zone totals far from that range, or a zone missing from the
zone menu.

Test: `/run local v=CommanderQuestLog.Questie.ZoneView(3483) print(#v.entries, v.totals.counted)`
on Hellfire prints two numbers in the low hundreds and somewhat below.

## A7 — Questie's hard-coded TBC content phase 3 matches the realm

Not load bearing for other zones. Questie fixes
`ContentPhases.activePhases.TBC = 3` with no setting, so every Zul'Aman and
Sunwell / Isle of Quel'Danas quest is blacklisted and absent from `zoneMap`. The adapter never writes that value
(D28).

Symptom if wrong (the realm is past phase 3): those quests are missing from
Ghostlands and Zul'Aman, and Isle of Quel'Danas has no zone view at all.

Test: pick Isle of Quel'Danas from the zone menu (it is absent at phase 3);
on a realm where the Isle is open, its absence is this assumption failing.

## A8 — Dungeon and raid tags can come from where Questie files a quest

Not load bearing (display only). The facts line's "Dungeon" / "Raid" / "PvP"
comes from `zoneOrSort`, never from the client's `GetQuestTagInfo`, which
answers nil on first ask and makes Questie schedule a retry timer per quest
(critic §3.4). Elite is never shown.

Symptom if wrong: a dungeon quest's briefing lacks "Dungeon".

Test: on the Hellfire Citadel zone (from the Dungeons menu), select any
Ramparts quest; its facts line reads "Dungeon".

## A9 — The exclusive-choice sweep does not hitch

Not load bearing. After ready the adapter reads `exclusiveTo` for every quest
in `QuestPointers` (about 6,700, each a fresh CBOR decode), 400 per frame.

Symptom if wrong: a short stutter some seconds after login.

Test: `/cql status` within ten seconds of login reads
`Exclusive-choice index: complete (… quests read, … list a choice)` with no
visible hitch.

## A10 — One zone view costs tens of milliseconds, and recomputing on a reputation tick is acceptable

Not load bearing. A view is about 150 `IsDoableVerbose` calls, 150
`QueryQuest` reads and 100 NPC spawn reads, computed on demand for one zone.
`UPDATE_FACTION` is one of the bump events, so while grinding reputation with
the Zones tab or the drawer open, every kill recomputes the shown zone once.

Symptom if wrong: a hitch when opening the Zones tab on a large zone, or on
each kill while the tab is open.

Test: `/run local t=debugprofilestop() CommanderQuestLog.Questie._Facts(3483) print(debugprofilestop()-t)`
prints well under 50 (ms).

## A11 — Questie's own events plus our six are every change that moves a verdict

Not load bearing. The adapter bumps on Questie's `RegisterForQuestUpdates`
callback, `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_REMOVED`,
`UPDATE_FACTION`, `SKILL_LINES_CHANGED` and `PLAYER_LEVEL_UP`, and does not
hook `AvailableQuests.CalculateAndDrawAll` (critic §4.8; Questie queues that
behind combat on a level-up anyway).

Symptom if wrong: a stale view until the next event, for example "lv 63"
rows that stay locked after the ding.

Test: ding with the Zones tab open; the rows that read your new level move to
Pick up now within a second.

## A12 — The world map is loaded by `PLAYER_LOGIN`, with the MapCanvas surface the drawer uses

**Load bearing for the drawer.** `Blizzard_WorldMap` is not load-on-demand on
this client, so `WorldMapFrame` exists at login with `ScrollContainer`,
`GetCanvas`, `pinPools`, `AddDataProvider`, `GetMapID`, `SetMapID` and
`IsMaximized` (`ADDON_LOADED "Blizzard_WorldMap"` is the second chance).

Symptom if wrong: no drawer and no pins, silently.

Test: `/dump CommanderQuestLog.Map._State().attached` prints `true` after
login, and `/dump WorldMapFrame:IsProtected()` prints `false`.

## A13 — `WorldMapFrame:SynchronizeDisplayState` and `:OnMapChanged` are hookable methods on 2.5.6

**Load bearing for layout.** Read from the classic_anniversary source, never
watched (critic §4.6). Both hooks are guarded; the map's `OnShow` hook and the
container's `OnSizeChanged` still refresh without them.

Symptom if wrong: the drawer keeps the old width when the map is maximized or
windowed, or shows the previous zone after a map change until the map is
reopened.

Test: toggle maximized and windowed with the map open;
`/dump CommanderQuestLog.Map._State().width` reads 250 maximized and 220
windowed.

## A14 — The drawer's anchors and frame level put it inside the map, over every pin, under Questie's buttons

**Load bearing for looks.** The maximized map is FULLSCREEN and the windowed
one MEDIUM, and the drawer inherits whichever (D25). It is anchored to the
`ScrollContainer`'s right edge at (-8, -40) and (-8, 8), the top inset
clearing Questie's map button row. Its frame level is the container's plus
2200 or ten over the pin-level manager's topmost level, whichever is higher.
The pins' levels are absolute (Questie's from 2016, ours 2018, and the player
arrow, party dots, corpse and flags at 2753-2757 on TBC, read from the
2.5.6 source); the container's own level was never read in the client,
which is why the floor is the manager's answer and not the container's.

Symptom if wrong: the drawer hides behind the maximized map, covers Questie's
map button, or the player arrow or Questie's icons draw on top of it.

Test: open the map both ways; the drawer sits inside the right edge, below
Questie's button. `/dump WorldMapFrame.ScrollContainer:GetFrameLevel(), CommanderQuestLogMapDrawer:GetFrameLevel(), WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST")`
prints a second value at least ten over the third. Stand on the east side of
a zone with the map maximized: your arrow is hidden under the drawer's list,
not drawn on it.

## A15 — `CreateUnsecuredRegionPoolInstance` is the pool HereBeDragons uses on 2.5.6, and it reads the fields we set

**Load bearing for the pins.** *(Corrected 2026-10-04; the first build's
recipe was wrong.)* On 2.5.6 `CreateFramePool` is the SECURE pool, a proxy
that ignores writes to `createFunc` / `resetFunc`, so the first build's pins
were bare frames and Blizzard's map code errored on them every frame (read
from the classic_anniversary 2.5.6.69795 source and reproduced against its
real `Pools.lua`). The drawer now takes `CreateUnsecuredRegionPoolInstance`
as HBD does (`HereBeDragons-Pins-2.0.lua:33-39`), and falls back to
`CreateFramePool` with the mixin in its `postCreate`. `AcquirePin` calls a new
pin's `OnLoad` on this build; `OnAcquired` still runs it should one not.

Symptom if wrong: no pins at all, or a Lua error from Blizzard's map code
(`Blizzard_MapCanvas.lua`, "OnLoad" or "SetNudgeVector" a nil value) every
frame the map is open.

Test: `/dump CreateUnsecuredRegionPoolInstance ~= nil` prints `true`. On a zone
with quests above your level, grey givers appear that Questie does not draw,
hovering one lists its quests with a reason each, and zooming the map with
BugSack open records nothing.

## A16 — `SetPassThroughButtons` is harmless to stub

**Not load bearing on 2.5.6.** HereBeDragons replaces it with a no-op to avoid
an in-combat error. The 2.5.6 source never calls it anywhere in
`Blizzard_MapCanvas`, `Blizzard_WorldMap` or the shared map providers
(review, 2026-10-04), so the stub is kept as HBD's belt and braces only.

Symptom if wrong: `ADDON_ACTION_BLOCKED` naming the pins when the map is
opened in combat.

Test: open the map in combat on a zone with pins showing; no blocked-action
warning.

## A17 — `C_Map.GetMapRectOnMap(zone, continent)` answers four numbers

Not load bearing. The continent labels sit at the centre of each zone's
rectangle (left, right, top, bottom). On Azeroth (947) it may answer nil for
some zones, which costs that zone its label only.

Symptom if wrong: no percentage labels on Outland.

Test: `/dump C_Map.GetMapRectOnMap(1944, 1945)` prints four fractions, and
the Outland map shows a "%" over each zone.

## A18 — Setting the map from addon code causes no taint

Not load bearing, unless it does. `WorldMapFrame:SetMapID` (a drawer zone
row, Focus, Show on Map), `ToggleWorldMap` and `HideUIPanel(WorldMapFrame)`
are all called out of combat or from a click.

Symptom if wrong: a taint warning, or the map refusing to open, later in
combat.

Test: click a few continent rows in the drawer, ctrl-click a quest row, then
open the map in combat: no taint or blocked-action warning.

## A19 — `GetPlayerMapPosition` answers nil or (0, 0) off the map, and the player's zone resolves through `GetBestMapForUnit`

Not load bearing. The Guide orders "Pick up now" by distance when the player
stands on the zone's map; caves and entrances fall back to Questie's own zone
read, pcall'd because it can throw.

Symptom if wrong: "Pick up now" in level order where you stand, or the Zones
tab not following you into a zone.

Test: `/cql status` reads `Your zone: <the zone you are in> (area …, map …)`.

## A20 — Questie's `GetUiMapIdByAreaId` knows the dungeon wings

Not load bearing. A dungeon group (Hellfire Citadel 3563, Auchindoun 3917,
Tempest Keep 3845, Caverns of Time 1941) has no map of its own and borrows its
first wing's for Show on Map and the drawer.

Symptom if wrong: Show on Map greyed out on a dungeon group.

Test: `/dump CommanderQuestLog.Questie.UiMapForArea(3563)` prints a map id
(347, Hellfire Ramparts).

## A21 — `GetFactionInfoByID` answers the bar value sixth, and nil for a faction not met

**Load bearing for the Aldor / Scryers rule (D23).** Both standings must be
known for a quest to be called the other side's; an unreadable standing never
locks anything.

Symptom if wrong: rival quests counted as ordinary reputation locks, or never
locked at all.

Test: `/dump GetFactionInfoByID(932)` — the sixth value is your Aldor bar
value. With one side Hostile, the other side's quests list under
"Other faction".

## A22 — An unanchored MENU dropdown opens under the zone card, and level-2 lists work and fit

**Load bearing for picking a zone.** `ToggleDropDownMenu(1, nil, menu, card)`
on a `UIDropDownMenuTemplate` initialised in "MENU" mode, with each category's
zones a level down through `menuList` (a table, for a page of a long
category). The menu frame is never anchored so its invisible button cannot
take clicks meant for the navigator. The Classic dropdown never scrolls, so a
category over 20 zones is paged (D34): at most 20 rows, which at the window's
default spot fit a 768-unit screen.

Symptom if wrong: clicking the card shows nothing, the zone lists never
open, or a list runs off the top of the screen.

Test: click the zone card; "Where I am" and the continents appear, hovering
Outland lists its zones (with percentages on the second opening), and
"Dungeons  A-…" and its second page each list their zones entirely on
screen. Clicking (not hovering) a category row leaves the menu open.

## A23 — `SelectQuestLogEntry(0)` empties the log selection

Not load bearing. The Zones tab reads an in-log quest's objectives through
`Q.ReadDetail` and empties an empty selection again afterwards (D31).

Symptom if wrong: the stock quest log or another addon finds a quest selected
that the player did not pick.

Test: on the Zones tab, select a quest that is in your log, then
`/dump GetQuestLogSelection()` prints 0.

## A24 — The Log / Zones tabs clear the title art on every skin

Not load bearing. The two tabs sit at x 12–130, y -5 to -25, above the drag
strip's frame level so they take clicks.

Symptom if wrong: a tab overlaps the title or cannot be clicked.

Test: switch the window style through Stone, Parchment, Window and Dark with
the window open; both tabs are readable and clickable on each.

## A25 — `Q.DifficultyColor` agrees with Questie's green and grey at 60–70

Not load bearing. Zone rows colour levels with the module's own era formula;
Questie uses `GetQuestGreenRange` (critic §4.2). They may disagree by a level
at the grey line.

Symptom if wrong: a row's level grey where Questie's "!" is green, or the
reverse.

Test: at level 70, compare a level-61 quest's row colour with Questie's map
icon for the same giver.

## A26 — `QuestieProfessions:GetProfessionName` names professions by skill-line id

Not load bearing. "Needs 300 Mining." reads "Needs profession skill 300."
without it.

Test: `/run print(CommanderQuestLog.Questie.Character().skillName(186))`
prints "Mining".

## A27 — `AvailableQuests.__availableQuests` holds exactly the quests Questie draws

Not load bearing. Pins skip any quest in it, so ours never stack on Questie's
"!" (D26). It is a stable table read in place and never written.

Symptom if wrong: a pin of ours on top of Questie's icon, or an available giver
with no mark when Questie draws none.

Test: on a zone with quests you can take, every giver shows exactly one icon.

## A28 — A hover's font swap puts the font's own colour back, and our ink goes back on a frame later

Not load bearing on the dark skins; on Parchment it decides whether a tab or
filter label stays readable. The tabs and filters have a normal and a
highlight font object, and a hover swaps between them; the D14 lesson is that
a swap re-applies the font's own colour (gold, grey, white) over the ink. The
fix re-inks on `OnLeave`, a frame later so it lands after the client's swap
whichever runs first. *(Round 2.)* While the pointer is ON a label it used to
show the highlight font's white, which over the paper's pale toolbar wash
reads at 1.6:1 -- the word faded out under the pointer. On paper `OnEnter`
now inks the label as well, at once and again a frame later; a frame of
white is possible if the client swaps after both, which is the part only the
client can show.

Symptom if wrong: after hovering, a tab or filter label stays gold or grey on
the paper until the next refresh; or, while hovered, it is white and all but
invisible on the cream.

Test: on Parchment, hover then leave the active "Zones" tab and an inactive
filter ("Locked"): while the pointer is on each, the word is dark ink, not
white; after it leaves, each is its own ink again at once, not gold or grey.
`/dump GameFontNormalSmall:GetTextColor()` prints the gold a label that stayed
swapped would show. On Stone the hovered label is white as before.

## A29 — `CommanderQuestLog_OpenToQuest` can be handed a heading or a stale index

Not load bearing. Reached only through the stock quest log's `OnShow` with
whatever `GetQuestLogSelection()` holds; Blizzard and Questie select a real
quest before showing the frame, so a heading needs a third-party
`ShowUIPanel(QuestLogFrame)`. The function now refreshes whatever the index
is, so the window cannot be left half-switched either way.

Test: with the window open on the Zones tab,
`/run SelectQuestLogEntry(1); ShowUIPanel(QuestLogFrame)` (entry 1 is a
heading) leaves the window cleanly on the Log, no zone card showing.

## A30 — A background zone summary costs a few milliseconds in the client

Not load bearing. A summary is built without its givers (D29); on real data
under LuaJIT's interpreter the whole 85-zone pass took 129 ms, the worst
single tick 8 ms. The client's Lua 5.1 is slower (estimated 3-5x on the Lua
part; the CBOR decode is native there). One zone per 0.05 s tick.

Symptom if wrong: a stutter for a few seconds after opening a continent map or
a zone-menu category.

Test: open Outland's map with `/run local t=debugprofilestop() CommanderQuestLog.Questie.RequestSummaries({3523,3520,3518}, function() end) print(debugprofilestop()-t)`
first (it should print near 0: nothing is computed synchronously), then
watch the frame rate while the three land.

## A31 — The search box and the two dropdowns stay legible on Parchment without the dark strip

Not load bearing. The toolbar strip is a thin wash of ink on the paper now
(D16), not 45% black. The search box (`InputBoxTemplate`) and the dropdowns
(`UIDropDownMenuTemplate`) draw their own dark art, and their text is the
client's white over it, so they should read as before; never seen.

Symptom if wrong: the search text, its "Search quests" ghost, or a dropdown's
label washes out on the cream.

Test: pick the Parchment style, type in the search box and open both
dropdowns; every word is readable.

## A32 — A pin lifted to the drawer's level draws over the drawer

Not load bearing. Pins are children of the canvas, the drawer of
`WorldMapFrame`; both share the map's strata, so the higher frame level
draws on top and the canvas's clipping still lets a pin show inside the
container's rectangle, which the drawer sits in.

Symptom if wrong: a quest whose giver stands under the open drawer still
pulses unseen after a row click or Show on Map.

Test: on Hellfire with the drawer open, click a drawer row for a quest whose
giver stands on the east side (Wing Commander Dabir's, for one); the ringed
pin shows over the drawer for about three seconds.

## A33 — Questie refreshes its reputation and profession caches within 2.2 s of the event

Not load bearing. `UPDATE_FACTION` and `SKILL_LINES_CHANGED` bump at once and
again 2.2 s later, after Questie's 2 s chat-event bucket
(`EventHandler.lua:112-120`) has refreshed what `IsDoableVerbose` reads.
*(Round 2.)* The late look is trailing-edge: an event that arrives while it
is pending, more than 0.1 s after the one that armed it (`GetTime`), gets one
more look 2.2 s after the first fires, so every such event is followed by a
look at least a bucket after itself. A tier crossing never depended on this:
Questie refreshes its reputations at once on the "You are now Friendly with
..." system message. What it covers is a threshold inside a tier (Darkmoon,
the {Aldor 1} / {Scryers 1} gates, the 8999 / 20999 maxima) and every skill
gate.

Symptom if wrong: a quest gated on a reputation threshold inside a tier, or
on a skill just trained, stays locked until some unrelated event.

Test: train Riding 225 with the Zones tab on Terokkar Forest; within about
three seconds the Skyguard quests stop reading "Needs 225 Riding". Then, on
a profession view, skill up twice about a second apart where the second
crosses a quest's gate in the middle of a rank: the quest opens within about
three seconds of the second skill-up, with nothing else happening.

## A34 — Before the pledge, the Aldor and the Scryers read the same standing for most races

Not load bearing outside Shattrath, Netherstorm and Shadowmoon. The
tie-break (D23) applies only while both standings are known and equal; a
Blood Elf or a Draenei starts with a side, and a faction the client has not
met answers nothing, which never locks (A21).

Symptom if wrong: before pledging, both sides' quests count (the old
behaviour) or neither does.

Test: on an unpledged human, `/dump select(6, GetFactionInfoByID(932)), select(6, GetFactionInfoByID(934))`
prints two equal values, and Shattrath lists the Scryers' quests under
"Other faction" with "Until you side with the Aldor or the Scryers…" --
including the ones open at Neutral (Synthesis of Power, Voren'thal the Seer)
and Strained Supplies *(round 2)*. Note Shattrath's count, pledge to the
Aldor, and it is the same.

## A35 — `GetQuestLogIndexByID` answers 0 for a quest under a collapsed heading

Not load bearing. "Ready to hand in" is read off the client's log (D29).
*(Corrected in round 2.)* For a quest the call cannot index, the first fix
fell back to the window's last scan and said the two agree; they do not. The
scan expands every heading first (D3), so it never sees a heading collapsed
in the stock log afterwards (TakeOverQuestLog off), or before the window's
first open this session: its answer is missing or stale. So the adapter asks
`IsQuestComplete(questID)` there, which Blizzard's own quest map provider
calls by questID and which is in the 2.5.6 binary next to
`GetQuestLogIndexByID`. Its by-ID signature on this client is unverified, so
it is pcall'd and believed only when it answers true (or 1); anything else
falls back to the scan. Failed still needs the indexed read or the scan.

Symptom if wrong: under a collapsed heading a finished quest's drawer row
reads "log", not "ready", and its waypoint goes to the giver, not the
turn-in. If `IsQuestComplete` ignores its argument and answers for the quest
dialog, a quest could read "ready" only while a quest giver's window is open.

Test: `/dump GetQuestLogIndexByID(<a questID in your log>)` prints its index,
and with the quest's objectives done the map drawer's row reads "ready" with
the quest log window shut. Then turn TakeOverQuestLog off, collapse that
quest's heading in the stock quest log, `/dump GetQuestLogIndexByID(<id>), IsQuestComplete(<id>)`
(expect 0 and true), and the drawer still reads "ready"; with the objectives
NOT done it prints false and the row reads "log".

## A36 — A scroll frame takes an offset past its old range a frame after its child grows

Not load bearing. Open in Log, a quest link and the map drawer's way in
scroll the navigator to the asked-for quest's row (D31). The offset is worked
out from the child's new height, but `UIPanelScrollFrameTemplate`'s scrollbar
clamps to the range it last heard of (`OnScrollRangeChanged`, at the next
layout), and its `OnValueChanged` sets the clamped value back. So the offset
is set at once and again a frame later; a scroll in between (a tab switch)
cancels the second.

Symptom if wrong: Open in Log on a quest at the bottom of a long log briefs
it, but its highlighted row is still below the visible list, or the list
jumps to its end.

Test: with a log of twenty or more quests, select the last one's zone on the
Zones tab, pick that quest and press Open in Log: its row is on screen with
the list scrolled, not at the top. Scroll the list up by hand and let a
quest objective tick: the list stays where you put it.

## A37 — Questie's dungeon table places every TBC dungeon's entrance, and a dungeon uiMap bridges to its area

Not load bearing. Commander Orders asks the adapter where a dungeon map's
entrance is (D35): a quest giver inside a dungeon, or a ghost whose corpse
lies in one, gets an arrow to the way in. The answer is read from
`ZoneDB:GetDungeonLocation(areaId)` -- the `{ zoneAreaId, x, y }` entrances
Questie draws for a dungeon's `-1, -1` spawn -- after
`ZoneDB:GetAreaIdByUiMapId` has turned the dungeon's uiMap into its area. A
floor map with no row of its own is tried through its dungeon-map parents.

Symptom if wrong: Orders' arrow says "Other continent" (or "No position
here") for a dungeon quest giver with no entrance offered, and a dungeon
death gets no corpse arrow, while `/cql status` still says the resolver is
registered.

Test: `/dump CommanderQuestLog.Questie.Entrance(347)` should print Hellfire
Ramparts' entrance on Hellfire Peninsula (map 1944, coordinates in 0..1); try
a multi-floor dungeon's lower floor too (`/dump C_Map.GetBestMapForUnit("player")`
inside it, then the same call with that id).

## A38 — An instance corpse is answered by `GetCorpseMapPosition`, so the entrance fallback rarely runs

Not load bearing. Two 2026-10-04 corrections to the entrance resolver (D35):
uiMap 246 answers The Shattered Halls' own door (Questie's override table
says the Blood Furnace), and the Orphan-typed instance maps (The Black
Morass, Old Hillsbrad, Hyjal Summit, Zul'Aman and five older ones) are
answered at all. Both matter in game mostly through Orders' corpse arrow,
and that asks the resolver only when `C_DeathInfo.GetCorpseMapPosition`
finds nothing on the ghost's map chain. The server very likely reports an
instance corpse at the instance's outdoor ghost entrance (Map.csv gives
these maps a CorpseMapID of 1 or 530, and TomTom's corpse arrow has no
instance case), in which case the fallback never runs and these corrections
change nothing a player sees. No quest giver Questie places sits on 246 with
real coordinates, and the Guide asks for raid maps with its own cited table
behind.

Symptom if wrong (the fallback does run): a wipe in The Shattered Halls,
then a release, shows "Your corpse: The Shattered Halls entrance", now at
the Halls' own door (before: the Blood Furnace's, about 90 yd away). No
corpse arrow at all after a release in The Black Morass would mean the
client's corpse query AND this resolver both came up empty.

Test: die in The Black Morass (or The Shattered Halls), release, and on the
outside map `/dump C_DeathInfo.GetCorpseMapPosition(1446)` (1944 for the
Halls). A position means the fallback is never reached; nil means the arrow
comes from this resolver: `/dump CommanderQuestLog.Questie.Entrance(273)`
should print Tanaris 0.657, 0.498 and `...Entrance(246)` Hellfire 0.477,
0.520 titled "The Shattered Halls entrance".

---

Not relied on, so not listed above: whether `C_QuestLog.GetQuestInfo` returns
titles for quests never seen (critic §4.1 — there is no Questie-less fallback),
`C_Map.SetUserWaypoint` and `QuestMapFrame` (absent on this client and unused),
and the XML parentKeys of the maximized map (the drawer anchors to
`ScrollContainer` only).

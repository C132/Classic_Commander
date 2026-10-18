# Commander_QuestLog — assumptions to verify in game

The Zones tab, the Questie adapter and the world-map drawer (1.4.0) pass four
headless harnesses, which prove the logic against a fake Questie and a mocked
map and nothing about the live client or the real Questie. Numbered so a test
session can report against them. A1–A4 decide whether the Zones tab works at
all; A12–A15 decide whether the map drawer does; the rest degrade to a missing
line, a slower frame or a wrong colour. A28–A35 were added by the review of
2026-10-04, for fixes whose last step can only be watched in the client,
A36 by its second round, A37 with the move to Commander Orders (1.5.0), and A38 by the Orders review's entrance fixes. A39–A55 came with
the Reputations tab and reputation on every surface (1.6.0): A39, A40 and
A53 decide whether the numbers and the quest dialog's line are right at
all, A40–A47 are the in-game checks the research could not settle (critic
§5 and the Wowhead audit), and every one of those also corrects itself
once calibration (D40) has watched a turn-in. A56–A59 came with that tab's
review (2026-10-04): the nine data corrections, the compounding that
calibration now cannot settle, today's Wanted pick across a reset, and the
waypoint note kept current; A60 with its UI fixes (the card's note on one
line). The Log tab's own assumptions (the
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
Reputation rules: loaded (data for 2.5.6.69795)
Faction index: complete (N quests read, M pay reputation, K factions)
Reputation multiplier: 110% (Diplomacy)
Reputation seen in game: N quests, M samples
Cached: 1 faction view, 12 faction summaries
Wanted dailies today: normal …, heroic …
```

The faction index is read the first time a faction is asked about; until
then its line reads "not read yet".

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

*(1.6.0.)* The reputation numbers rest on the nil half of this too: a faction
not met is read as its Faction.db2 base. A39 has the test that settles it,
and what changes if the client answers the base instead.

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

## A39 — A faction not met answers nil from `GetFactionInfoByID`, or its starting standing

**Load bearing for every faction a character has not met** (Netherwing,
Sporeggar, the Kurenai or the Mag'har, the Ogri'la, the Skyguard). The
reports disagreed (critic W6): A21 assumes nil, the function is documented
as answering "regardless of whether the faction is known". 1.6.0 is built
for both answers (D39). With nil, the adapter uses the faction's Faction.db2
base for this race and class (Netherwing -42000, Sporeggar -2500, Kurenai
-1200), names it from the data (the client's name only once met), and the
picker says "not met yet". With an answer, the client's own bar value and
name are used and nothing is "not met". Either way a first gain is measured
from that value, so calibration (D40) sees it as a move from the base.

Symptom if wrong: an unmet Netherwing reads Neutral (the client answers 0,
not -42000), so "Ally of the Netherwing" shows +42000 capped to 0 rather
than the climb from Hated -- or a met faction reads "not met yet".

Test: on a character that has never met Netherwing (or Sporeggar),
`/dump GetFactionInfoByID(1015)` (970). nil confirms A21; a name and a
sixth value of -42000 (-2500) means the client answers the base and the
"not met" wording never shows. Then `/dump CommanderQuestLog.Questie.FactionStanding(1015)`
reads value -42000, word "Hated", met false (nil case) or true.

## A40 — A Human's Aldor turn-in pays +275 / -302 / +137: the stored Sha'tar row is spillover, paid once

**Load bearing for every Aldor and Scryers number** (critic §5.2). The quest
data stores the Sha'tar's half on 85 Aldor and Scryers quests; the generator
drops it as `derived` (D38) and the rules regenerate it as spillover from
the boosted, clamped gain, so a Human sees Aldor +275, Scryers -302 (the
-110% edge of 275) and Sha'tar +137. CMaNGOS today pays the Sha'tar twice
(the template AND the row); Questie shows -275 and +137.5. Calibration
replaces whatever the game actually does after one turn-in.

Symptom if wrong: the Sha'tar moves +262 (or +250 for a non-Human: paid
twice), or the Scryers lose 275 rather than 302; every Aldor or Scryers
line is off by that much until a turn-in calibrates it.

Test: as a Human below Friendly with the Sha'tar, turn in 10326 More Marks
of Kil'jaeden (or any Aldor item turn-in); the chat says Aldor +275, Scryers
-302, Sha'tar +137, and afterwards `/dump CommanderQuestLogChar.RepObserved[10326]`
holds raw 250 for the Aldor (932) and samples for 934 and 935 with no
"changed" count, the quest's briefing marking each "seen in game".

## A41 — The Sha'tar's spillover stops at 8,999, the top of Friendly

Not load bearing outside the Sha'tar. The rules' default `spillClamp =
"capTop"` (D41) stops a spill at the top of the window's highest rank; the
DB2's maxRankIn says Friendly, and CMaNGOS clamps every Sha'tar row of the
mark turn-ins at 8999 (critic W1). The emulator's own code checks the rank
BEFORE the gain, so the last spill could carry past 8999 into Honored (the
"mangos" setting in the data's rules).

Symptom if wrong: a Sha'tar at 8,900 gains the full +137 from an Aldor
turn-in and ends in Honored, where the briefing said "+99 ... spillover
stops at 8,999".

Test: with the Sha'tar a little under 8,999, one Aldor or Scryers item
turn-in: the Sha'tar stops at 8,999 (5,999 / 6,000 Friendly), and any later
turn-in moves it 0. If it overshoots, make the `rules` line in
`Harness/make_reputations.py` say `spillClamp = "mangos"` and re-run it.

## A42 — Pledging to the Aldor or the Scryers moves the Sha'tar +1750

Not load bearing. Allegiance (10551 / 10552) pays +3500 to the side and has
no stored Sha'tar row; the rules give the rival -3850 and the Sha'tar
+1750 by spillover (critic §2). If the server does not spill on these, the
pledge's briefing overstates the Sha'tar by 1,750 until calibrated; a
faction seen moving that the rules do not name is shown "seen in game only".

Symptom if wrong: after pledging, the Sha'tar did not move, while the
briefing had said +1,750 (+1,925 for a Human).

Test: before pledging, note `/dump select(6, GetFactionInfoByID(935))`;
pledge; read it again. Or, on an alt that already pledged, read
`CommanderQuestLogChar.RepObserved[10551]` (or 10552) after the next pledge.

## A43 — The databases' values are the TBC values where Wowhead's /tbc/ pages show Wrath's

**Load bearing for Sporeggar, the Kurenai and the Mag'har.** The audit
(D38) found Wowhead's /tbc/ pages carrying the Wrath value on a family of
quests and kept the databases' (both CMaNGOS and Questie, backed by TBC
guides): Sporeggar 9742 More Spore Sacs 750 (Wowhead 250), Kurenai 10477
More Warbeads and Mag'har 10478 More Warbeads! 500 (Wowhead 250), Hero of
the Mag'har 10212 2000 (Wowhead 1000).

Symptom if wrong: those repeatables pay a third or half of what the tab
promises; the turn-ins-to-Friendly count is too low by that factor.

Test: one More Spore Sacs turn-in below Friendly with Sporeggar: +750
(+825 for a Human). One More Warbeads: +500 (+550). Calibration then shows
either one as "seen in game".

## A44 — The Hellfire Citadel Wanted dailies pay Honor Hold or Thrallmar

Not load bearing outside four dailies, and medium confidence. Both
databases pay the Consortium only on 11354, 11362, 11363 and 11364; the
audit's overrides add Honor Hold and Thrallmar (350 / 350 / 350 / 250) on
Wowhead's TBC pages, a 2007 guide and the symmetry with every other Wanted
daily paying its dungeon's faction (critic W3). Only the player's side is
shown.

Symptom if wrong: the daily's Honor Hold (Thrallmar) gain never arrives;
the first turn-in calibrates it to 0 ("0 Honor Hold, seen in game").

Test: turn in Wanted: Nazan's Riding Crop (11354) or Wanted: Shattered Hand
Centurions (11364): the chat says Consortium and Honor Hold (Thrallmar).
`/dump CommanderQuestLog.Questie.RepLine(11364)` before it reads "+250 The
Consortium  +250 Honor Hold" (+275 each for a Human).

## A45 — Ally of the Netherwing lands a Human on exactly Neutral 0

Not load bearing. 10871 is the Human-only copy of 10870; the audit's
override (38182 = 42000 / 1.1) and the hand-written reward clamp of 0 land a
Human with Diplomacy on 0 from -42000, as 10870 does every other race
(Questie stores 42000: +46200). Under the Wickerman the gain is clamped at
0 too.

Symptom if wrong: a Human ends a little short of (or past) Neutral 0 after
the quest; Netherwing's projection is off by the difference.

Test: as a Human at Netherwing -42000, turn in Ally of the Netherwing:
`/dump select(6, GetFactionInfoByID(1015))` prints 0.

## A46 — No quest pays less for being grey, and three Classic factions pay double

Not load bearing for TBC factions. TBC has no low-level quest penalty
(CMaNGOS "2.0.1"; the rules keep the flag off), and CMaNGOS doubles quest
gains for Argent Dawn (529), the Cenarion Circle (609) and Timbermaw Hold
(576), which the rules copy (D37). Neither is confirmed on Blizzard's
server (critic W5, §2).

Symptom if wrong: a quest six or more levels grey pays a fraction of the
line; an Argent Dawn or Timbermaw turn-in pays half of it.

Test: hand in a quest grey to you that pays a TBC faction and compare the
chat line with the briefing's; then one Timbermaw Hold feather turn-in
(the briefing shows the listed value doubled).

## A47 — A daily turned in stays done until the reset, and Questie keeps today's Wanted record by realm

Not load bearing. A daily's DONE state (the Guide, the daily income) comes
from Questie's complete table and `IsQuestFlaggedCompleted` (critic §5.8);
today's Wanted pick from `Questie.db.global.unavailableQuestsDeterminedByTalking[GetRealmName()]`,
which Questie fills when you talk to the NPCs and replaces at the reset
(D42). The real-data boot had that record empty, so "today" is unverified
on real data.

Symptom if wrong: a daily done today reads as open again before the reset;
the Wanted pools stay "today's not known yet" after both givers were asked.

Test: turn in a daily, then `/dump C_QuestLog.IsQuestFlaggedCompleted(<id>)`
is true until the reset. Talk to Nether-Stalker Mah'duun and Wind Trader
Zhareem, then `/cql status` reads "Wanted dailies today: normal <quest>,
heroic <quest>".

## A48 — A turn-in's moves arrive as UPDATE_FACTION within about two seconds, and reading every standing then is cheap

Load bearing for calibration (D40) only. The adapter reads all 75 standing
slots once in every frame where `UPDATE_FACTION` fires -- every reputation
kill in a dungeon -- and matches the moves to a turn-in within one second
before it and two after (on CMaNGOS they arrive before
`QUEST_TURNED_IN`). The chat line (`CHAT_MSG_COMBAT_FACTION_CHANGE`, parsed
with patterns built from this locale's `FACTION_STANDING_INCREASED` /
`_DECREASED`) is the second source. Auto-turn-in chains that share a
faction inside the window are set aside, by design.

Symptom if wrong: `/cql status` never counts a sample ("Reputation seen in
game: 0 quests") after several turn-ins, or counts them "set aside"; or a
frame hitch on every reputation kill.

Test: turn in two reputation quests a few seconds apart; `/cql status`
reads "Reputation seen in game: 2 quests, ..." with nothing set aside. In a
dungeon, kill a pack with the Reputations tab shut: no hitch.

## A49 — `C_UnitAuras.GetPlayerAuraBySpellID(24705)` answers, and `UNIT_AURA` fires for the Wickerman

Not load bearing outside Hallow's End. The multiplier reads Invocation of
the Wickerman by spell id through `C_UnitAuras` (in the 2.5.6 binary),
falling back to a buff scan; `UnitBuff` exists on this client only behind
the deprecation fallbacks. A change in it is seen on `UNIT_AURA` (0.5 s
settle) and Bumps, so every surface moves at once.

Symptom if wrong: with the buff up, the lines still read 100% (or 110% for
a Human), or one surface updates and another does not until the next
event.

Test: take the buff at a Wickerman bonfire; `/cql status` reads
"Reputation multiplier: 110% (Invocation of the Wickerman)" (120% for a
Human), and the Log's briefing, the Zones badge and an open quest dialog all
show the bigger number without another click.

## A50 — `GetText("FACTION_STANDING_LABEL"..n, UnitSex("player"))` gives the client's word, female form included

Not load bearing. Standing words come from the client so a localised
client reads its own, and a locale with female forms
(`FACTION_STANDING_LABEL1_FEMALE`) reads hers; English fills a gap.

Symptom if wrong: English standing words on a localised client, or the
male form for a female character where the locale has both.

Test: on a localised client (frFR has female forms), a female character's
Reputations card reads the same word for a standing as the game's own
Reputation pane does; `/dump GetText("FACTION_STANDING_LABEL5", UnitSex("player"))`
prints it.

## A51 — The watched faction and the Reputation pane read as the tab expects

Not load bearing outside Following and Watch Faction (D43).
`C_Reputation.GetWatchedFactionData()` answers a table with `factionID` (nil,
or 0, with none watched); `GetFactionInfo(index)` answers isWatched twelfth
and factionID fourteenth, as Classic's ReputationFrame.lua reads them;
`SetWatchedFactionIndex` moves the bar and fires `UPDATE_FACTION`;
`FACTION_BAR_COLORS` holds colours with `.r`, `.g`, `.b`.

Symptom if wrong: the tab never follows the watched faction (it falls back
to the log's), Watch Faction watches the wrong row or does nothing, the
card's bar is the fallback colour.

Test: tick "Show as experience bar" on the Consortium in the game's pane;
the Reputations tab (following) switches to it. Pick the Sha'tar and press
Watch Faction: the bar shows the Sha'tar and the button greys out. Fold
"Shattrath City" in the pane, pick the Aldor, press it: a chat line says the
heading is folded and nothing unfolds.

## A52 — `GET_ITEM_INFO_RECEIVED` brings an item cost's name

Not load bearing. A repeatable's item cost is named by `GetItemInfo`, else
"item N" until the client has the item, and redrawn when
`GET_ITEM_INFO_RECEIVED` names that item id first.

Symptom if wrong: "10 of item 25433 each" stays until the next refresh.

Test: on a fresh login, open the Reputations tab on the Kurenai (or the
Mag'har) and read REPEATABLE SOURCES: "Obsidian Warbeads" appears within a
second.

## A53 — The quest dialog's line sits under the rewards, scrolls with them and fades in with them

**Load bearing for the dialog line** (D44). `GetQuestID()` names the quest
on both the detail and the reward panel (the binary has it; Blizzard's TBC
QuestInfo.lua calls it); our nameless child of the dialog's scroll child is
expected to extend the scroll range the way QuestInfo's own spacer does;
`GetMaterialTextColors` and the `QuestFont` object exist; the line copies
the alpha of the element it hangs under while the detail panel fades its
rewards in. A dialog-replacing addon (Immersion and the like) never calls
`QuestInfo_Display`, so there is simply no line.

Symptom if wrong: no line at a quest giver, a line cut off at the bottom of
a long quest that the scroll bar does not reach, a line showing before the
description has finished typing, or the wrong ink on the parchment.

A quest that moves several factions gets one per line under
"Reputation:" ("\n" in the one FontString, the holder sized from
`GetStringHeight`), so 275 px never wraps a gain away from its faction.

Test: accept a Honor Hold quest from Hellfire's quest givers: after the text
has typed out, "Reputation: +250 Honor Hold" (+275 for a Human) appears
under the rewards in the dialog's own brown; on a long quest, scroll to
the bottom and the line is reachable. Hand it in: the line is on the
reward panel too. Take Marks of Kil'jaeden from Adyen: "Reputation:" then
the Aldor, the Scryers and the Sha'tar each on a line of its own, all three
reachable by the scroll bar.

## A54 — The new words fit their widths

Not load bearing. "Reputations" fits its 78 px tab (estimated, about 60 px
in GameFontNormalSmall); the card's second line ("+1,375 in quests ·
reaches Friendly · pinned") fits 280 px in Friz Quadrata; "Watch Faction"
fits 104 px; a row badge is measured with `GetUnboundedStringWidth` and held
to 64 px on the tabs and in the maximized drawer. With its faction's tag a
badge is kept to 12 characters (`C.RepBadgeText`, 2026-10-05 review), which
at about 5.3 px a character in Friz Quadrata 10 is expected to fit whole:
"+1,100 HH", "+385 Cons", "+275 Exodar", "+385 Scryers", "+550 Sha'tar"
and "+42,000 Neth" (Ally of the Netherwing, the widest, about 60 px) as
they are; a longer one loses its thousands comma first ("+1000 Exodar")
and then its tag is cut to four letters ("+1000 Scry" for Varedis Must Be
Stopped and Turning Point's "+1,000 Scryers", "+3850 Scry", "+2000 Mag"
for Hero of the Mag'har, "+1000 Kure"), where "+1,000 Scryers" whole was
about 70-77 px and ended in "+1,000 Sc...", the tag being the part lost.
The row tooltip names the faction in full. Long titles on the
Reputations tab end in an ellipsis (about 153 px against the Zones tab's
180, the badge taking the rest); the row tooltip has the whole title.

Symptom if wrong: clipped tab label, card line or button; badges
overlapping the state word; a 12-character badge ("+385 Scryers", "+550
Sha'tar", "+42,000 Neth") ending in an ellipsis, which would want
`BADGE_CHARS` at 11 (or 10).

Test: open the Reputations tab on the Consortium: the strip reads Log /
Zones / Reputations unclipped; the card's two lines and the action bar's
five buttons fit; widen nothing. On the Zones tab in Hellfire and in the
maximized map's drawer, the badges read "+275 HH" and the like whole, no
ellipsis. On the Zones tab in Shattrath City, Allegiance to the Scryers
reads "+3850 Scry" and Trial of the Naaru: Tenacity "+550 Sha'tar", both
whole; in Shadowmoon Valley (a Scryer) Varedis Must Be Stopped reads
"+1000 Scry", and in Netherstorm Turning Point the same, no ellipsis on
either, here or in the maximized map's drawer.

## A55 — A faction view costs about a zone view, and the faction index never hitches

Not load bearing. Under LuaJIT on the real Questie data a faction view cost
4.8 ms (the Sha'tar) against 4.0 ms for Shattrath's zone view, and the
whole index 5.3 ms over 18 frames; WoW's interpreter is slower (A10). A view
is rebuilt on each generation step while the tab is up, so a reputation
kill recomputes it as a zone view is recomputed.

Symptom if wrong: a hitch on opening the Reputations tab, on each pick, or
on every reputation kill while it is open.

Test: `/run local t=debugprofilestop() CommanderQuestLog.Questie.FactionView(935) print(debugprofilestop()-t)`
(after a reputation change, so the view is not cached) prints well under 50
(ms); `/cql status` within a few seconds of first opening the tab reads
"Faction index: complete (...)".

## A56 — Where Wowhead (TBC) and CMaNGOS agree against Questie, 2.5.6 pays what they say

**Load bearing for nine quests** (D38, widened 2026-10-04): 4267, 5096,
6804, 7639, 7640, 7781, 7782, 10016 and 11211 now read the two sources'
rows, not Questie's. Both share a lineage with Questie (D40), and Wowhead's
/tbc/ pages carry Wrath values on some quests (A43), so offline nothing
settles which one the Anniversary server follows. 10016 Timber Worg Tails
is the one a TBC leveller meets.

Symptom if wrong: a Human's Timber Worg Tails moves the Alliance capitals
(about +547 each) while every surface says "No reputation"; Poisoned Water
moves each Horde capital by about +498 where it says +250.

Test: turn in 10016 on an Alliance character with the chat frame showing
reputation lines: no "Reputation with Stormwind increased" line, and
`/cql status` counts no new set-aside for it. On the Horde, 6804 Poisoned
Water: one "Reputation with Horde" line and +250 for each capital; 11211
Help for Mudsprocket: Gadgetzan +10 only.

## A57 — Two rows of one quest that spill into each other compound, as the rules pay them

**Load bearing for 123 quests** (most of Durotar and Dun Morogh, the Exodar
and Silvermoon pairs, The Lord of Blackrock 7781 / 7782). The rules pay each
direct row and then its spillover, so Cutting Teeth (Darkspear 250,
Orgrimmar 250) moves Orgrimmar 250 + 62 = +312 and each other Horde capital
62 + 62 = +124, and The Lord of Blackrock gives a Human about +1,098 with
each Alliance capital. That is CMaNGOS's RewardReputation, one row at a
time. Calibration cannot settle it: those moves are sums and are set aside
("mixed", D40), so the data stands.

Symptom if wrong: on those quests the capitals move by the plain row (+250 /
+62) and the line overstates them by a quarter or so.

Test: turn in 788 Cutting Teeth on a new Orc or Troll and read the chat:
"Reputation with Orgrimmar increased by 312", Darkspear Trolls 312,
Undercity, Thunder Bluff and Silvermoon City 124 each (a Troll's Darkspear
line is the same). `/cql status` then counts five set aside.

## A58 — Questie keeps a daily done until a relog, and the client says when the last reset was

Not load bearing. Today's Wanted pick (D42) treats a rotating daily in
Questie's done list as today's only when this session began after the last
daily reset, `GetServerTime() + GetQuestResetTime() - 86400`, or the adapter
saw the turn-in since. That rests on Questie's `complete` table being
rebuilt at login and never cleared at the reset (QuestLifecycle,
QuestieQuest; read from its source, not watched), and on both client calls
answering server seconds.

Symptom if wrong: after playing through the reset, the Reputations tab's
DAILIES still names yesterday's Wanted as today's; or, the other way, a
Wanted done today stops being named after a relog.

Test: turn in a heroic Wanted daily, stay logged in across the daily reset,
then `/cql status`: "Wanted dailies today: ... heroic not known yet" until
Wind Trader Zhareem is talked to. `/dump GetServerTime(), GetQuestResetTime()`
answers seconds since 1970 and under 86400.

## A59 — Commander Orders lists our waypoints by source and takes a new note through Update

Not load bearing. A quest waypoint's note (D44) is kept current with
`CommanderOrders.List({ source = "QuestLog" })` and `CommanderOrders.Update(uid,
{ note = ... })`, matched by the waypoint's key `quest:<id>`; both are
Orders' public API (CommanderOrders.lua) and its tooltip prints the note as
stored.

Symptom if wrong: a waypoint's note keeps the figure it was set with after
the Wickerman, a cap or a calibration sample changes the quest's line.

Test: set a waypoint from the Zones tab for an Honor Hold quest as a Human,
take Invocation of the Wickerman, and hover the Orders pin: its note reads
the +20% line (+300 for a 250 quest). Remove the waypoint and take the buff
off: it does not come back.

## A60 — The card's note is one line in Friz Quadrata, cut short rather than wrapped

Not load bearing (the 1.6.0 review's one PLAUSIBLE finding, fixed blind).
The catalogue's card note (Zones and Reputations) is a 280 px FontString on
a 46 px card; the review's renderer, with a substitute font, wrapped the
Reputations tab's longest note ("No quests left · repeatables reach
Friendly · pinned", about 265-290 px in Friz Quadrata at 10) onto the
navigator's top border. The note now has `SetWordWrap(false)` and
`SetMaxLines(1)` (both guarded), so the worst case is a trailing ellipsis;
the card's tooltip says it all in full.

Symptom if wrong: the note's last word ("pinned") lost to an ellipsis more
often than expected, or (a client without either method) a second line over
the navigator's first row.

Test: on the Reputations tab pin the Consortium after its once-only quests
are done, then `/run local n=CommanderQuestLog.Reps._Widgets().card.note print(n:GetStringWidth(), n:GetWidth(), n:IsTruncated and n:IsTruncated())`:
the width is at most 280, and the note sits on one line above the
navigator.

---

Not relied on, so not listed above: whether `C_QuestLog.GetQuestInfo` returns
titles for quests never seen (critic §4.1 — there is no Questie-less fallback),
`C_Map.SetUserWaypoint` and `QuestMapFrame` (absent on this client and unused),
the XML parentKeys of the maximized map (the drawer anchors to
`ScrollContainer` only), and the payload of `FACTION_STANDING_CHANGED`
(critic §5.6: calibration reads the bars and the chat line, never that
event).

## A61 — The log's objectives come in Questie's objective order

Load bearing for the objective Go buttons (D45). Objective n of
`GetQuestLogLeaderBoard` is matched to entry n of Questie's objective list as
the adapter builds it (creatures, objects, items, reputation, kill credit,
spells, then the explore trigger, with Questie's `*ObjectiveFirst` tables
moving one kind first). Questie matches them the same way
(`QuestieQuest.lua` reads `quest.ObjectiveData[objective.Index]`), so a quest
where the order is wrong is wrong in Questie's own tracker too, and Questie
carries the corrections. Checked offline against the real thing
(2026-10-05): with the installed Questie and QuestieDB booted under luajit
(the session's real-data boot, a level-64 Horde paladin), the adapter's
order matched Questie's own `QuestieDB.GetQuest(id).ObjectiveData` kind for
kind on all 6657 quests (4137 with objectives, 3 with a `*First` flag), and
5172 of the 6484 objectives had a place (every explore trigger and kill
credit, 1597 of 1627 creatures, 191 of 207 objects, 3113 of 4203 items --
an item no creature or object drops, such as Purified Helboar Meat, has
none). The log's own order against Questie's is not seen in game.

Symptom if wrong: an objective's Go leads to another objective's creature
(the "Patrol Sentry slain" Go walking to the poster).

Test: take a quest with a kill and a loot objective (Hellfire's "Know Your
Enemy" style), hover each objective's Go: the tooltip names the creature or
the item on its own line ("Where Questie places Patrol Sentry (8 spots ...)").

## A62 — QUEST_REMOVED fires for an abandon and QUEST_TURNED_IN for a turn-in, with the quest id

Load bearing for the turn-in cleanup (D45). Both carry the quest id first
(`QuestLogDocumentation.lua` in the 2.5.6 source); the adapter removes every
`quest:<id>` waypoint of that quest on either. Read from the documentation;
the firing on an abandon is assumed.

Symptom if wrong: a quest's waypoint stays in Commander Orders after the
quest is gone (the arrow keeps pointing at a turn-in you made).

Test: Go to Turn-in on a quest, hand it in: the waypoint is gone from the
manager (`/corder`). Go to an objective of another quest, abandon it: gone
too. `/reload` with a quest's Go pinned and hand it in after: gone.

## A63 — The Go buttons fit their bars

Not load bearing. "Go to Turn-in" sits in a 120 px button on the Log's
action bar (lit: "Going to Turn-in"), between Announce and Abandon with
about 20 px to spare; the Zones tab's "Go" keeps the 80 px the Waypoint
button had; an objective's row Go is 48 px, enough for "Going". Widths from
the mock's string metrics, not seen in game.

Test: open the Log on a quest Questie knows, press Go to Turn-in: the lit
label is whole and clear of Abandon.

## A64 — A Go to a creature inside an instance lands on Orders' door (D46)

Load bearing for every Go of a giver, finisher or objective whose creature
stands inside an instance. The adapter asks `CommanderOrders.Locate({
entrance = { area = <Questie's instance area> } })` and takes every spot it
answers; Questie's own dungeon spot only when Orders answers nothing. Proved
over the fake Questie with the real Orders (contract L) and over the real
Questie and QuestieDB in a scratch boot (Murmur and Exarch Maladaar 0 yd from
Orders' door, 100 and 103 yd before; the zone lists of 17 zones unchanged),
never in the client.

Symptom if wrong: the arrow for "Into the Heart of the Labyrinth" stops in
the Auchindoun tunnel short of the portal, or a dungeon quest moves to a
different zone's list on the Zones tab.

Test: track "Into the Heart of the Labyrinth" (10095), press Go on its
Murmur objective: the arrow points at the Shadow Labyrinth portal in
Auchindoun (Terokkar 39.6, 73.8), the same spot the arrow's dungeon hint
gives inside the instance. The Zones tab's Terokkar Forest count is what it
was before the update.

## A65 — A greyed Go's tooltip says what still answers (D46)

Not load bearing. With Commander Orders turned off (`/corder off`), the Go
to Turn-in and the Zones tab's Go are greyed and their tooltips no longer
promise a press; they say the row's gesture still answers in chat. Relies on
the GoButton showing a greyed button's tooltip (Orders' D31,
`SetMotionScriptsWhileDisabled`), not seen in game.

Test: `/corder off`, hover Go to Turn-in on a quest Questie knows: no "a
press says so" line, the red "Commander Orders is turned off (/corder)"
under it; Ctrl+Right-click the quest's row: one chat line with the place
and its [Go] link. `/corder on` after.

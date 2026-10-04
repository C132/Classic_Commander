# Commander_QuestLog harnesses

Five luajit checks, run from the AddOns root. Each resolves the AddOns root
from its own file location, so it works in a git worktree as well as in the
live AddOns directory (and from any working directory), and exits non-zero if
any check fails. Run all five before touching anything in the module: the
window harness loads every file but the map, the next three load the engine
and the adapter the window and the drawer both stand on, and the contract
harness runs the adapter against the real Commander Orders.

```bash
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_harness.lua        # 447 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/completion_engine_smoke.lua # 747 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questie_adapter_smoke.lua   # 423 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_map_harness.lua    # 309 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_orders_contract.lua # 25 checks
```

Mutation hooks, for proving a check bites against a broken copy of a file
(the copy lives anywhere; the live file is never touched):

```bash
CQL_ADAPTER=/path/copy.lua  luajit .../questie_adapter_smoke.lua   # a mutated adapter
CQL_ENGINE=/nonexistent     luajit .../questie_adapter_smoke.lua   # the engine-absent path (prints SKIPPED for O)
CQL_MAP=/path/copy.lua      luajit .../questlog_map_harness.lua    # a mutated map module
CQL_ADAPTER=/path/copy.lua  luajit .../questlog_orders_contract.lua  # the adapter against real Orders
```

`fake_questie.lua` is not a harness: it is the Questie the others run on
(see "The fake Questie" below).

The suite's own settings smoke (`Commander_Events/Harness/settings_ui_smoke.lua`)
is worth a run after a change to the settings page: it exercises the framework
this module's page is built on, including the fold-and-search layout a page
with more than three sections gets.

---

# questlog_harness.lua — the window (447 checks)

The harness loads the real `CommanderSettingsUI.lua` and `CommanderEvents.lua`
alongside the window's files — DB, Model, Completion, Questie, UI and Zones, in
TOC order; not Map, which has its own harness and needs a world map this mock
does not have — under a permissive WoW mock. The fake Questie is installed
BEFORE the module files load, as Questie loads before this addon in game.
It builds a nine-entry quest log across three zone headings, fires login, and
then drives a whole session — including turning quests in underneath the
window while it is open.

## What it covers

- **A — the scan.** Headers and quests in log order, each quest carrying its
  zone; `isComplete` is the era's tri-state, so `-1` reads as **failed** rather
  than as done; `frequency == 2` is a daily; `have/need` is parsed out of the
  objective's text; a quest the server calls complete counts every objective
  done, because an "event" objective reads as unfinished on one that is; each
  heading tallies its own zone. And the scan puts the client's log selection
  back where it found it.
- **B — collapsed headers.** The mock hides a collapsed zone's quests from the
  index space exactly as the client does. The scan expands **once**, only when
  something is actually collapsed, and the `QUEST_LOG_UPDATE` that expand fires
  does not re-enter the scan. Calling `ExpandQuestHeader` unconditionally is
  the loop this guard exists for.
- **C — the display list.** Search over name, zone and objective text, case
  insensitively; the four filters; the three sorts; folding a zone shut in
  *our* window hides its quests and keeps its heading; a filtered list never
  leaves a heading with nothing under it; a sort drops the zone grouping rather
  than sorting inside it.
- **D — progress.** Weighted by count, not by objective: 3/3 and 0/1 is
  three quarters, not half.
- **E — the detail read.** Description, objective summary, reward choices with
  their usability and their item links, a taught spell, reward money, and a
  quest that cannot be shared saying so — with the selection put back after.
- **F — the window.** It opens, never takes keyboard focus (or WASD types into
  the search box), counts the log, selects a quest on its own so the briefing
  is never blank, and **re-selects when the filter narrows past the
  selection** — finding the selected quest in the scan is not enough if the
  navigator no longer lists it. The drawn state is read back: every visible row
  sits at its own offset, and the briefing actually carries the name, the
  facts line, the objectives under their heading, the reward choices, the
  taught spell and the ready-to-turn-in line. Share greys itself out for a
  quest the game will not share rather than offering a dead button. Briefing
  blocks are pooled by **position**, and two quests of different shape put
  different kinds of line at the same position — so both the font and the
  colour are re-applied every pass, and the checks switch between a complete
  quest and an active one to prove it. The filter labels take an explicit
  colour applied **after** the font object is swapped, because swapping it
  re-applies the font's own grey.
- **G — the actions.** Track and untrack; a **full tracker** is reported rather
  than swallowed (the era declines silently past five, which reads as a broken
  button); Share refuses an unshareable quest and explains why; Announce
  reaches the raid over the party, carries the remaining objectives, and talks
  to you rather than erroring when you are alone.
- **H — abandoning, and the index that moved.** This section exists for one
  bug. The confirmation dialog sits on screen while the world keeps moving, and
  the stock flow re-reads the *selection* at accept time — so a quest turned in
  while the dialog was up drops whatever slid into that slot. Our dialog
  carries the quest by **name**, re-finds it at accept time, and refuses
  outright when it is gone. Verified to bite: with the selection-based flow,
  three of these fail and the wrong quest is dropped.
- **I — the selection survives the log moving.** A log index is invalidated by
  any accept or turn-in. The selected quest is remembered by questID and
  re-found on every scan, so it stays selected at its new index; turning in the
  selected quest picks another rather than emptying the pane.
- **J — cost.** `QUEST_LOG_UPDATE` arrives in bursts — several per accepted
  quest and again on every objective tick. Twenty events in one frame do no
  work, then exactly one pass.
- **K — the takeover.** The `L` key opens ours and not Blizzard's; showing the
  stock frame by any *other* path (a quest link, `QuestLog_OpenToQuest`,
  another addon) comes here too and puts the stock frame away; and turning the
  setting off hands Blizzard's window straight back, with no reload and without
  stealing the show from it.
- **L — settings.** Restore Defaults puts the options back, and leaves a folded
  zone alone: that is data the player authored, not an option.
- **M — difficulty colours.** The era's thresholds, including the grey line
  moving with the player's level. Computed rather than read from
  `GetQuestDifficultyColor`, which is FrameXML's and not the API's.
- **P — the reset clocks.** The server's UTC offset is read off the game clock
  and rounded to the quarter hour; the weekly reset is computed as the next
  daily reset on the region's reset day in **server-local** time (the KR case,
  where the reset is Wednesday in UTC, is the check that a UTC weekday fails);
  the modern weekly API is believed only when plausible, and a missing, zero,
  too-early or misaligned answer falls back to the calendar; countdowns read
  at the resolution that is moving; the footer is on screen with the
  navigator shortened to make room, it ticks once a second and not before,
  the value warms up inside a quarter hour, both tooltips carry the countdown,
  the server-time moment and (weekly) the lockout list with each lock's own
  clock, extended and lapsed locks read right, the setting hides the footer and
  gives the navigator its room back, and on paper the clocks are ink.
- **O — ink on paper.** On the parchment every colour written on the sheet is
  scaled to ink luminance (D16); on the dark skins the same colours are left
  alone. Once Questie is ready the Log's "Turn in:" line is held to it too.
- **Q — the Zones tab.** Over the fake Questie's small Hellfire Peninsula (13
  count, 2 done, 15%). The Log first: with Questie ready the briefing carries
  "Turn in: NPC — Zone (x, y)" and a Waypoint button that goes there. Then the
  Log / Zones tabs (above the drag strip, the right widgets shown and hidden
  on a switch); the zone card's name, "2 / 13 · 15%" and bar; the rows —
  status strip, level, state word, dimmed when they do not count, the Guide's
  "Pick up now" in distance order from where the player stands; folds kept in
  `ZoneCollapsed` and never in the Log's `Collapsed`; the overview (breakdown,
  the uncounted line, NEXT UP drawn without regrouping the navigator, chains,
  missed); a quest's briefing (its reason sentence, Starts / Ends, the chain
  with the current quest banded, REQUIRES, LEADS TO, OBJECTIVES live from the
  log when it is in it, REPUTATION) — and that briefing an in-log quest never
  moves the client's log selection (D2, D31); a selection the filter or a
  fold takes away falling back to the overview (D6); row tooltips; ink on
  paper; the action bar's enable states; a waypoint through a recording
  Commander Orders, owned by its quest ("quest:<id>", moved rather than
  doubled when the quest turns ready) and never through the legacy
  `CommanderOrders_IssueOrder`; Route Zone (D35) live on the overview, its
  tooltip counting the six givers, its click one NEAREST route, greyed out
  without Orders and the Waypoint tooltip then promising a `/way` line; Ignore and Count moving the percentage after the debounce, per
  character; Show on Map refused in combat and, out of it, opening the map on
  the zone and focusing the drawer on the quest and its zone; Open in Log;
  each tab's own search; filters and groupings; the zone menu (Where I am,
  categories, zones a level down with percentages); `CommanderQuestLog_OpenToZone`
  revealing the quest it was asked for; a quest link landing on the Log
  whichever tab was up; the settings page's two new sections, the pin kinds
  greyed out with the pins; Restore Defaults keeping the folds and the ignore
  list; `/cql zone` and `/cql status`; Questie still loading; and the Zones
  Tab setting off meaning the Log and no tabs at all.
- **Q2 — the review's fixes (2026-10-04).** The zone menu cuts a long
  category into pages a screen can hold and keeps a clicked category open;
  the Zones search matches quest names, never the status headings ("pick"
  used to list the whole Pick up now group), and its tooltip says so; titles
  are one line on both tabs; each tab opens at its own top; on paper the
  toolbar strip is a wash, the selection bands, the chain band, the
  underlines and every briefing quad are ink, and a hover's font swap no
  longer leaves a label gold or grey; Open in Log reveals the quest through
  the Log's fold, filter and search; the zone card's inset follows the tab
  that draws, with the module switched off; `OpenToQuest` on a heading leaves
  the window cleanly on the Log; Restore Defaults brings the reset footer
  back with the window open and with it shut. *Round 2:* the zone menu cuts
  where the initial changes (the real 34 dungeons: A-O and R-Z, where an
  even cut put R on both pages), takes a whole UTF-8 character for an
  initial (deDE's "Ödland"), and numbers the pages when one letter outruns a
  page; on paper a label is ink WHILE hovered, not the highlight font's
  white, and off paper the white stays; Open in Log, a quest link and the
  map drawer's way in scroll the asked-for row into view on a log longer
  than the pane, and an ordinary refresh leaves the player's scrolling
  alone. Run over `UI.lua` and `Zones.lua` from before round 2 (a copy of
  the AddOns tree; the harness finds its files from its own location), 13 of
  these fail.
- **R — no Questie at all.** A second load of every file with the Questie
  globals gone and `ViewMode` left on ZONE: the window opens, the Log works,
  the Zones tab says Questie is not loaded, and nothing errors.
- **N — the global footprint.** The module publishes its six entry points
  (`CommanderQuestLog_OpenToZone` is the new one) and its two key bindings and
  nothing else. `Bindings.xml` is read as *text* (the
  client parses it, not Lua): every binding it declares must have a
  `BINDING_NAME_` the addon publishes and must call a function that exists, and
  no comment may contain a double hyphen — that is illegal XML and voids the
  whole file, registering zero bindings with only a `LUA_WARNING` to say so.

## Mock notes

Lessons already paid for, so the next run does not re-learn them:

- **The quest log is MUTABLE and its indices MOVE.** That is the whole point.
  Every index bug this module can have is an index that went stale between the
  row being drawn and the button being pressed, and a fixture whose indices
  never move proves nothing.
- **Collapsing a header removes its quests from the index space**, in the mock
  as in the client. `ExpandQuestHeader` fires `QUEST_LOG_UPDATE` off its own
  back, which is what section B is checking.
- **`Show`/`Hide` fire `OnShow`/`OnHide`** — and, as in the client, `Show` on
  a frame already shown fires nothing. The window does all its work in
  `OnShow`; a mock that skipped it would test an empty frame, and one that
  fired it every time hid a window left half-switched.
- **Fonts carry their colours and buttons their font objects**, so a hover's
  font swap can be acted out (`HoverButton`): it is what puts a label's own
  font colour back over its ink. `HoverIn` / `HoverOut` are the same hover in
  two halves, for a check on the label while the pointer is still on it.
- **Nothing is laid out**, so a scroll frame's height is 0 unless a check
  gives it one (Q2 gives the navigator 200 for the scroll-into-view checks
  and takes it back).
- **A ScrollFrame keeps its vertical offset**, and the log answers
  `GetQuestLogIndexByID` in its own index space, so the adapter reads "ready"
  off the client here as it does in game.
- **Widths and heights are tracked for real.** The navigator advances its
  layout by each row's height and sizes its progress bars off the pane, so a
  mock answering 0 to both would draw every row on top of the first — and the
  check that catches it reads the offsets back off the rows.
- **Focus is tracked**, so "does the window steal the keyboard" is a real
  check rather than a vacuous one.
- The mock character is a level **62** warrior, which is what puts the fixture
  quests either side of every difficulty threshold.
- **The fake Questie goes in before the module files load**, as Questie
  loads before this addon in game; the adapter attaches at load and at login.
  Section R uninstalls it and loads every file a second time.
- **Frame levels are tracked.** The mock used to answer a constant 2, which
  made "the tabs sit above the drag strip" a check that could not fail.
- **The main chunk is close to Lua's 200 locals.** Sections Q and R are each
  wrapped in `do ... end`; a new section should be too.

---

# completion_engine_smoke.lua — the engine (747 checks)

Loads `CommanderQuestLogCompletion.lua` ALONE into a sealed environment in
which reading any global the engine was not handed raises — the proof that the
engine is pure, not a grep for API names. No WoW mock, no fake Questie: facts
and the character are written by hand.

The hand-built `char` has `exclusiveTo` (each quest's own list, the one the
engine decides by; it defaults to the symmetric `peers` most fixtures use)
apart from `exclusivePeers` (the adapter's forward-plus-reverse answer, for
naming only), and `isGone`.

- **A** the constants; **B** every one of Questie's 33 `DoableStates` names
  (base, bucket, lock kind, reason, counted) plus the three refined rows;
  **C** the raw classifier for a quest with no verdict; **D** multi-reason
  locks (level and a quest and a reputation, Questie's reason leading) and
  missing beating locking; **E** prerequisites, mirroring Questie's
  any-of singles and all-of groups, exclusive substitution and negative ids.
- **F** the Aldor / Scryers rule both ways, through `requiredMinRep` and
  `requiredMaxRep`, with and without counting both sides; **G** bucket
  precedence (ignored, seasonal, repeatable, optional, extra) and effective
  levels.
- **H** exclusive slots: a choice made here, made in another zone, in the
  log, not yet made (one counts), a lone member, and the denominator the same
  before and after the choice. **H1** `exclusiveTo` is one-way, as in
  Questie: a quest only NAMED by a done or logged quest stays available and
  counted, a one-way pair is not a slot, and a preGroup member is stood in
  for only through its own list. **H2** tiered lines (the Caverns of Time
  rings): the first quests are the slot, later tiers follow their line, and
  the denominator is one line's length before, during and after the pledge;
  *round 2:* a follower in the log or done stays counted and its head takes
  the slot, an ignored pledge (the first one the others name, or another) is
  still a choice so the total stays one line, and a breadcrumb into a choice
  (Muren Stormpike into Vejrek) follows it, then holds the slot once taken.
- **I** chains: topological order, the level tie-break, a cycle that cannot
  hang, standalone quests, prerequisites outside the zone.
- **J** the zone view, its totals and the FLOORED percentage (nothing counted
  is no percentage); **K** the groupings — Guide, by status, by chain, flat by
  level and name — their fixed titles, header counts and distance order;
  **L** the filters; **M** state words; **N** every reason sentence; **Q**
  prerequisites gone for good (a chain behind a lost quest is missed, and
  named, in view and out of it; an open any-of option or an exclusive
  stand-in keeps it locked), Riding a lock and not a miss, the unpledged
  Aldor / Scryers tie, same-title twins; *round 2:* the tie for gates already
  met at it (a Scryer Neutral quest, a maximum on the Aldor), so an Aldor
  pledge moves nothing and a Scryer one swaps the sets, an open quest staying
  open with both sides counted; a rival quest behind a lost pledge missed, in
  both modes; **O** standings; **P** no shape
  glyphs anywhere.
- **Z** last, and in a SEPARATE environment: the real
  `CommanderQuestLogModel.lua`, proving a zone entry is a valid `Q.BuildList`
  entry — search walks its objectives, `Q.Progress` answers 0, folds hide a
  group's rows, a flat list survives a fold made in the Guide, and
  `matchHeader = false` keeps a search off the status headings.

Mutation-tested when written: seven deliberate engine breakages each caught.
The 2026-10-04 checks (H1, H2, Q) were each run against the engine as it was
before the review and fail there; the round-2 checks fail 25 times against
the engine before round 2.

# questie_adapter_smoke.lua — the Questie adapter (423 checks)

Drives `CommanderQuestLogQuestie.lua` over `fake_questie.lua` under a WoW mock
just big enough for it: a `C_Timer` on a manual clock that runs one frame at a
time (and `GetTime` on the same clock), an event frame, print capture and the
client stubs the fake installs.
Every forbidden Questie call, every dot-for-colon slip and every
`IsDoableVerbose` without `returnText` is recorded by the fake (the adapter's
pcall would otherwise swallow it) and must stay empty.

- **A** no Questie at all; **B** LOADING, and the ready callback deferred a
  frame with no work done inside Questie's coroutine; **C** uiMap to areaId
  through the bridge that throws, the parent, 3535 and dungeon-group folds, the
  continents; **D** the zone menu and continent zone lists.
- **E** facts: the `returnText` gotcha, the repeatable and daily bit
  arithmetic, hidden-on-map, events, one-way reputation, givers with names
  and coordinates, the dungeon sentinel, "starts in", the EXTRA layer;
  **F** the reverse exclusive index, chunked, and the generation step when it
  is done; **G** the character table read fresh (a reassigned `complete`,
  Questie's log as the fallback, "ready" off the client's log before the
  window's scan, `exclusiveTo` that the reverse index never adds to,
  `isGone`, reputations, faction and profession names).
- **H** one generation step and one listener call per burst of bumps; **I**
  views cached by generation, at most three, summaries kept for all; **J**
  background summaries one zone per tick, never rewound by a generation
  step (a stream of bumps no longer keeps one rebuilding); **K** waypoints
  to Commander Orders (D35) through a recording stand-in: owned per quest,
  every spawn of the giver as 0..1 alternatives (a turn-in reads up to 32,
  facts keep eight), "turned off" told from "not loaded", every refusal (off,
  refused, raising) ending in the place and a `/way` line, TomTom and the
  legacy order never called; Route Zone's stops (one per giver, the giver's
  spawns kept, item starters and done quests left out) and its one owned
  NEAREST route, with the chat line for each refusal; the entrance resolver
  registered once at Init, answering Ramparts and the Underbog on their zone
  maps as copies from a cache, The Shattered Halls with its own door although
  the fake's uiMap 246 answers 3713 as Questie's override table does, an
  Orphan-typed instance map (The Black Morass, Zul'Aman) with its door while
  the parent walk never climbs onto one, and never sending a zone or
  continent through Questie's bridge; **L** giver pins merged within half a map
  percent and capped at five spawns a quest; **M** quest detail, the finisher,
  the best starter, Questie's own available set.
- **N** broken and absent Questies degrade, never raise; **O** end to end
  through the REAL engine (the percentages, the Guide opening with Turn in,
  distance from the player, a skill lock named through Questie's professions,
  background summaries, detail levels, the one-way trio, Route Zone visiting
  exactly the six givers of Hellfire's open quests and dropping an ignored
  one) — printed as
  SKIPPED only when `CQL_ENGINE` points at a missing engine; **Q** the
  review's fixes, each on a fresh instance: Cosmic lists every zone, a raid
  key missing from Questie's Journey list still reaches the Dungeons menu,
  Glowcap Mushrooms is one-way, a reputation or skill change bumps again
  after Questie's 2 s bucket, summaries skip the givers, ready without any
  window scan, a quest behind a prerequisite Questie calls gone is missed and
  a Riding quest is locked; *round 2:* a second reputation change inside the
  late look's window gets a look of its own a bucket after it, and then no
  more; ready under a heading collapsed in the stock log (through
  `IsQuestComplete`), beating a stale scan, and only on a true answer; **P** nothing forbidden, nothing leaked into
  globals, no glyphs.

Mutation-tested when written: about thirty-five single-line breakages of the
adapter, each failing at least one check; and on 2026-10-04 each of the
review's nine adapter fixes reverted alone, each caught (`CQL_ADAPTER`); the
adapter from before round 2 fails four of the round-2 checks.

# questlog_map_harness.lua — the world-map drawer and pins (309 checks)

Loads the REAL engine, the REAL adapter over the fake Questie, and the map
module — not the window files, so the drawer is proved to work without the
window's kit and DB defaults. Every scenario boots fresh. `WorldMapFrame` is a
proxy that records every field write (there must be none); the map mock calls
providers on show and on every map change the way `MapCanvasMixin` does, and
errors on a pin's `SetPassThroughButtons` unless our stub replaced it.

The pools are 2.5.6's shape (corrected 2026-10-04, after the review found the
drawer's first pool recipe made bare frames on the real client):
`CreateFramePool` is the SECURE pool, a proxy that stores a write to its
`createFunc` and never reads it (its `postCreate` is run);
`CreateUnsecuredRegionPoolInstance` is the plain pool whose fields are read.
`AcquirePin` is Blizzard's: a new pin always gets `OnLoad`, then `Show` and
`OnAcquired`; `SetPosition` applies an absolute level from the map's pin-level
manager (AREA_POI 2018, topmost 2757); and every acquire or release marks the
canvas dirty, so the next frame calls a `MapCanvasPinMixin` method on every
active pin, as the canvas's `OnUpdate` does — where a bare frame errors.

- **A** load and attach: hooks in, nothing built; **B** the first show on
  Hellfire — parent, anchors, width, frame level above every pin (the player
  arrow included), the
  strip's name, "2/13 · 15%" and bar, the breakdown, the five groups with Done
  folded; **C** pins — the pool and provider registered once, every pin
  filter live, nothing on a quest Questie draws, subzone spawns, the
  five-spawn cap, tooltips.
- **D** drawer interactions: folds (the chevron the right way round),
  tooltips, the focus band and ring, waypoints (owned by their quest), a
  right-click on the strip routing the zone's open quests without folding
  the drawer, the finisher when the client's log says ready (no window
  scan), ctrl-click into the quest log
  and, in combat, without `HideUIPanel`, the wheel and its indicator; **E** relayout for the windowed map and the
  container's level, the window's kit and its absence.
- **F** a continent: zone rows, summaries arriving, label pins at each zone's
  rectangle centre, a zone click, and no route from the strip; **G** maps with nothing to list (empty,
  unknown, uncounted-only, a dungeon), Cosmic listing every zone, and landed
  summaries redrawing once a quarter second rather than once each; **H**
  Focus, including from a closed map, a pulsing pin lifted over the drawer
  and dropped back, a quest with no row reported not found, and a focus made
  with the drawer folded in view when it unfolds; **I** settings that hide
  things; **J** hygiene — no globals, no writes to `WorldMapFrame`, no
  strata, nothing forbidden, no glyphs, and Blizzard's every-pin pass finding
  nothing bare.
- **K** Questie still loading on first show, and `AcquirePin` calling
  `OnLoad`; **L** Questie absent: nothing built, nothing raised; **M** settings
  off before the first show, the late world map, a re-show drawing the pins
  once, a map change inside Blizzard's own `OnShow`, and an adapter error
  whose line fits the windowed strip; **N** a client without the unsecured
  pool: `CreateFramePool`'s proxy still makes real pins through `postCreate`.

Mutation-tested when written: 31 single-line breakages, 30 caught; the
survivor removes a deliberately redundant guard. On 2026-10-04 the map file
from before the review fails the pool checks en masse (no pin is ever drawn),
and each of the review's ten map fixes reverted alone is caught (`CQL_MAP`).

# The fake Questie

`fake_questie.lua` returns a builder: `Fake.DefaultWorld()` (a fresh copy of
a small Outland every call), `Fake.Install(world)` (the `Questie` and
`QuestieLoader` globals and the modules behind them, with the real
`DoableStates` numbers and the real call styles) and `Fake.InstallClient(world)`
(the `C_Map`, `C_QuestLog`, faction and unit stubs a harness has not already
got). Its header documents the world format, every function on the handle it
returns and the figures the engine makes of the default world. It reproduces
Questie's traps rather than smoothing them: `ImportModule` conjuring empty
modules, `GetAreaIdByUiMapId` throwing, `IsDoableVerbose` answering AVAILABLE
without `returnText`, junk ids in `zoneMap`, tables reassigned at runtime, and
the calls that write Questie's state raising when called. Its
`IsDoableVerbose` runs the real exclusive check — the quest's OWN
`exclusiveTo`, one-way — and its default trio is deliberately not a clique
(9013 names 9014, 9014 names nothing). `InstallClient` also gives a harness
with no quest log of its own the client's `GetQuestLogIndexByID` /
`GetQuestLogTitle` pair over `world.log`, with `world.logComplete` for the
tri-state "ready"; `world.logCollapsed` collapses its one heading, which
takes the quests out of the index space as the client does, and
`IsQuestComplete(questID)` answers by id whatever the headings.

---

# questlog_orders_contract.lua — the adapter against the real Commander Orders (25 checks)

The other harnesses prove what the Quest Log asks Commander Orders for, through
a recording stand-in; this one proves Orders takes it (D35). It boots
`Commander_Orders/Harness/orders_mock.lua` — the client Orders' own harnesses
share, with this build's UiMap and UiMapAssignment rows, the real settings
framework and every Orders file — installs the fake Questie underneath it
(filling only the client calls the Orders mock lacks), and loads the engine and
the adapter after Orders' `ADDON_LOADED`, the client's order for an addon with
`OptionalDeps: Commander_Orders`.

- **A** the entrance resolver is registered at login and answers Orders' own
  lookup for Hellfire Ramparts (347) from Questie's dungeon table; a zone map
  has none.
- **B** a giver inside a dungeon: Orders takes the dungeon map (instance 543),
  draws no straight arrow from Hellfire, and offers the entrance the resolver
  gave — the case the old single slot left on a grey "other continent".
- **C** the Patrol Sentry's eight spawns kept as alternatives, the arrow on the
  one the player stands nearest, and a second press on the same quest moving
  its one waypoint.
- **D** Route Zone taken as one owned, active NEAREST route with a stop's
  eight spawns intact, and routing again replacing it.
- **E** Orders turned off: the path says so and the press prints the `/way`
  line, with nothing sent.

`CQL_ADAPTER` loads a mutated adapter here too; the alternatives, the key, the
route mode, the registration at Init and the entrance's 0..1 scaling each fail
a check when broken.


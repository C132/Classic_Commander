# Commander_QuestLog harnesses

Fourteen luajit checks and two generator checks, run from the AddOns root.
Each resolves the AddOns root from its own file location, so it works in a git
worktree as well as in the live AddOns directory (and from any working
directory), and exits non-zero if any check fails. Run them all before
touching anything in the module. The first five are the 1.5.0 set: the window
(every file but the map and the 1.6.0 ones), the engine and the adapter the
window and the drawer both stand on, the drawer, and the adapter against the
real Commander Orders. The next five came with the Reputations tab (1.6.0):
the generated reputation data, the reputation rules engine, the Reputations
tab, reputation on every other surface, and the NPC's quest dialog. The
eleventh came with "Go to" (1.7.0, DECISIONS D45, Commander Orders 3.1): the
window's Go buttons over the suite's own `Commander.UI.GoButton`. The last
three came with the Attunements tab (1.8.0, DECISIONS D48-D57): the generated
attunement data, the engine that ticks its guides off from the client, and the
tab itself; the second generator check is that data file's.

```bash
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_harness.lua         # 525 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/completion_engine_smoke.lua  # 756 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questie_adapter_smoke.lua    # 676 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_map_harness.lua     # 337 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_orders_contract.lua # 65 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/reputation_data_smoke.lua    # 432 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/standing_smoke.lua           # 609 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_reps_harness.lua    # 192 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_rep_everywhere_harness.lua  # 203 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questframe_harness.lua       # 86 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_goto_harness.lua    # 72 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/attune_data_smoke.lua        # 256 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_attune_engine_harness.lua  # 238 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_attunements_harness.lua  # 192 checks
python3 Commander_QuestLog/Harness/make_reputations.py --check                   # exit 0: the data file is current
python3 Commander_QuestLog/Harness/make_attunements.py --check                   # exit 0: the data file is current
```

**1.8.0 (Attunements, D48-D57).** Three new harnesses and a second generator
check. One existing check moves with the tab strip: the Reputations harness's
A check counted three tabs (Log, Zones, Reputations) and now meets Attunements
as the fourth, since `mock.TocFiles` reads the TOC and the TOC lists the three
new files; its expectation now reads four tabs with Attunements fourth, and every
other count is unchanged. `attune_data_smoke.lua` (256 checks, D1-D34)
loads the generated `CommanderQuestLogAttuneData.lua` alone and proves its
shape: the five phases and rules rows, the 26 guides and their step kinds, the
alternative groups, the unlock proofs, the account-wide gates, and every
correction the research audit landed. `questlog_attune_engine_harness.lua` (238
checks; sections A phase, B detectors, C side and class, D scoring and lists,
I marks, L events) boots the engine over `questlog_mock.lua` with hand-built
contexts and no window. `questlog_attunements_harness.lua` (192 checks; E
registration and switch, F rows and toolbar, G briefing, H Go, J card, K
settings, DB and slash, Q Questie absent, Z hygiene) drives the tab in the
window over the same mock, the suite GoButton and a recording Orders 3.1
stand-in with a six-row door table, and reloads the module files with the fake
Questie uninstalled for Q. The engine and the tab are two harness files rather
than one so the engine's checks need no window. `make_attunements.py --check`
reads the research bundles from `attune_research/research-0.json` to
`research-6.json` (git-tracked, the generator's default `--research` path) and
exits 1 when the data file is stale. Mutation hooks: `CQL_ATTUNE_DATA`
(another data file), `CQL_ATTUNE_ENGINE` (a mutated engine), `CQL_ATTUNE` (a
mutated tab). Mutation runs, each to fail at least one check: no IsExpanding
guard; GetQuestsCompleted used; ExpandSkillHeader called; CLEU registered
everywhere; STATE_W 46; lessons drawn in the navigator; a detected Done shown
Locked; impliedBy applied to Tempest Keep; linear back-propagation; a Show on
Map button; PrepareOpen reading a third argument; evidence lowering the phase;
the phase button warn-toned when set; the guide word "Attuned"; the tab using
kit.LineGo (a door Go silent without Orders); a door target carrying spec and
query together (Orders' table never asked); C_Timer.NewTicker for the calendar
tick; a daily counted in Ogri'la; the ledger written from a guide mark; a
positional phase capture.

**1.7.1 (the reward-button hole, D47).** The quest dialog harness 72 -> 86:
section J (13) and one check in I (the late hook covers the reward
buttons too). `questframe_mock.lua` now builds the dialog's reward buttons
as Blizzard does (the XML's first, the rest from `QuestInfo_GetRewardButton`,
the hide-unused loop by `#`), which the rep-everywhere harness also runs
on; every other count is unchanged.

**1.7.0 ("Go to", D45).** The contract harness 25 -> 60 (sections F-K) and
the new `questlog_goto_harness.lua` (67); every other count is unchanged.
Two existing checks moved with the SPEC's words, nothing else: the contract
harness's E (Orders turned off) now expects Orders 3.1's one refusal line --
"Commander Orders is turned off (/corder): Know Your Enemy (Hellfire
Peninsula 61.8, 60.6)" with the place's [Go] link -- where it expected the
adapter's own /way line, because a press with Orders 3.1 is Orders' `GoTo`,
which words its refusal itself; and the drawer harness's D row hint reads
"Right-click: Go" where it read "Right-click: waypoint" ("Waypoint" is the
noun only). The window, adapter and drawer harnesses load no GoButton and
stub an Orders 3.0 (Add, no GoTo), so they keep proving the plain-button
path and D35's Add spec unchanged. Mutation runs: 23 hand-made mutants of the
adapter, the window and the catalogue (no GoTo, no turn-in or abandon
cleanup, no one-waypoint-per-quest, Questie's objective order ignored, an
item's droppers dropped, the objective key shared, a sloppy key prefix, no
starter, the trigger ignored, one spot only, no Ctrl+Right-click, a Go on a
finished objective, no room left on the line, the turn-in key never set, no
row hint, plain buttons, the pools never put away, no LEADS TO Go, the
catalogue's Go a plain button, no objective Go on the Zones tab, the key not
following the selection): each fails at least one check.

The 1.6.0 counts against 1.5.0's: the window 447 -> 525 (section Q3, the tab
register), the engine 747 -> 756 (section O, `StandingWord` with no value),
the adapter 423 -> 635 (section R, reputation), the drawer 309 -> 335
(section O, reputation). Every 1.5.0 check is unedited; each count only grew.
The 1.6.0 review's fixes (2026-10-04) added, without editing a check: the
adapter 635 -> 661 (R13), the data 431 -> 432 (K5), the rules engine
584 -> 609 (N, O, P and Q). On the UI side the review changed what the
player reads (D43, D44), so some 1.6.0 checks moved deliberately, each to the new
words, and new ones came with them: the drawer 335 -> 337 (O1/O6/O7 read
"+275 HH", O10 new), the Reputations tab 179 -> 185 (C's Wanted reason, D's
and F's item costs ("Mark of Kil'jaeden x10 a turn-in"), the heroic pool's
words and the REPUTATION section in the Zones tab's words, N's one space, J
an alt's pin passed over; B's one-line note and the new section P),
reputation everywhere 183 -> 196 (B's and H's badges name their faction, D
re-drawn for the section's new place, the Wanted pools, "the Aldor's" and
the Exalted gap, with new checks in B, C and D), the quest dialog 70 -> 71
(D: several factions one per line). The 1.5.0 checks are still unedited.
The 2026-10-05 review added, without editing a check, the adapter 661 -> 666
(R14, the spill window held to the source's own gate); its UI fixes added,
also without editing one, the Reputations tab 185 -> 192 (G: Honor Hold at
the ceiling with today's Wanted known and not, at Exalted 900, open dailies
held to 0, the CHAIN heading's label), reputation everywhere 196 -> 203 (B:
the badge's 12-character fit and Shattrath's "+3850 Scry"; D: a faction at
the ceiling, at Exalted 500, and quests and repeatables held to 0; F: the
drawer's fit; H: several factions seen in game) and the quest dialog
71 -> 72 (H: "(seen in game)" on the heading).
The Go-to review's round 2 (2026-10-05, D46) added the adapter 666 -> 676
(Q2: a {-1, -1} spawn is Orders' door, Questie's zone kept), the contract
harness 60 -> 65 (L: Murmur's Go on Orders' Shadow Labyrinth door, within 5
yd, where Questie's spot is 100 yd short) and the Go harness 67 -> 72 (F: a
greyed Go promises no press). One check moved with the fix: the contract
harness's G expected Questie's Blood Furnace spot (46.0, 51.8) and now
expects Orders' own door there (`Entrance({ instance = 542 })`, 45.87,
51.93). Run against the old sentinel branch (`CQL_ADAPTER`), Q2 fails 5, G
and L fail 1 each; against the old tooltips (`CQL_UI`, `CQL_CATALOGUE`), F's
own-line checks fail.

Mutation hooks, for proving a check bites against a broken copy of a file
(the copy lives anywhere; the live file is never touched):

```bash
CQL_ADAPTER=/path/copy.lua  luajit .../questie_adapter_smoke.lua   # a mutated adapter
CQL_ENGINE=/nonexistent     luajit .../questie_adapter_smoke.lua   # the engine-absent path (SKIPPED for O and R: 343 checks)
CQL_STANDING=/path/copy.lua luajit .../questie_adapter_smoke.lua   # a mutated rules engine (R; /nonexistent: R SKIPPED, 423 checks)
CQL_REPDATA=/path/copy.lua  luajit .../questie_adapter_smoke.lua   # another reputation data file (R)
CQL_MAP=/path/copy.lua      luajit .../questlog_map_harness.lua    # a mutated map module
CQL_ADAPTER=/path/copy.lua  luajit .../questlog_orders_contract.lua  # the adapter against real Orders
CQL_REPDATA=/path/copy.lua  luajit .../reputation_data_smoke.lua   # another data file
CQL_STANDING=/path/copy.lua luajit .../standing_smoke.lua          # a mutated rules engine
CQL_REPDATA=/path/copy.lua  luajit .../standing_smoke.lua          # another data file (the scratch prototype: Q SKIPPED, 555)
CQL_REPS=/path/copy.lua     luajit .../questlog_reps_harness.lua   # a mutated Reputations tab
CQL_UI= / CQL_ZONES= / CQL_QUESTFRAME= / CQL_MAP=/path/copy.lua luajit .../questlog_rep_everywhere_harness.lua
CQL_WITH_REPS=1             luajit .../questlog_rep_everywhere_harness.lua  # also load the Reputations tab (still 203)
CQL_QUESTFRAME=/path/copy.lua luajit .../questframe_harness.lua    # a mutated quest-dialog file
CQL_ATTUNE_DATA=/path/copy.lua luajit .../attune_data_smoke.lua  # another attunement data file
CQL_ATTUNE_ENGINE=/path/copy.lua luajit .../questlog_attune_engine_harness.lua  # a mutated engine
CQL_ATTUNE=/path/copy.lua   luajit .../questlog_attunements_harness.lua  # a mutated Attunements tab
```

Three files in this folder are not harnesses but what the harnesses stand on:
`fake_questie.lua` is the Questie they run on ("The fake Questie" below),
`questlog_mock.lua` is the WoW client the window harnesses run on (lifted out
of `questlog_harness.lua` in 1.6.0 so another file can drive the window), and
`questframe_mock.lua` is the 2.5.6 NPC quest dialog. `make_reputations.py`
writes `CommanderQuestLogReputationData.lua`, and `reputation_overrides.json`
is its one hand-written input (the Wowhead audit).

The suite's own settings smoke (`Commander_Events/Harness/settings_ui_smoke.lua`,
89 checks) is worth a run after a change to the settings page: it exercises
the framework this module's page is built on, including the fold-and-search
layout a page with more than three sections gets (1.6.0 made it six, with
Reputation between Zones & Completion and World Map; 1.8.0 made it seven,
Attunements after Reputation). Commander Orders' own
harnesses (`Commander_Orders/Harness/*.lua`, their counts in that folder's
README) boot the pins and the store the contract harness hands waypoints to;
a change to the adapter's `A.Waypoint` / `A.GoSpec` is worth a run of them
too, and so is `Commander_Events/Harness/gobutton_smoke.lua` (the Go button
this module's buttons are, D45).

---

# questlog_harness.lua — the window (525 checks)

The harness loads the real `CommanderSettingsUI.lua` and `CommanderEvents.lua`
alongside the window's files — DB, Model, Completion, Questie, UI, Catalogue
and Zones, in TOC order; not Map, which has its own harness and needs a world
map this mock does not have, and not the 1.6.0 reputation files, which have
harnesses of their own on the same mock — under a permissive WoW mock
(`questlog_mock.lua`, below). The fake Questie is installed
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
- **Q3 — the tab register and a second catalogue (1.6.0).** The tabs are a
  register (`Q.RegisterTab`, D36) and the Zones tab one instance of the
  catalogue (`Q.NewCatalogue`), so a third tab is registered here the way the
  Reputations tab is: a catalogue of its own over the fake Hellfire, every
  hook a spec can hand the catalogue answered by a stub. The register: three
  buttons placed by order and width; moving off a tab puts ITS widgets away
  whichever tab comes next; a quest link from it lands on the Log; its switch
  takes its button away and puts the window on the Log; a `ViewMode` nobody
  registered is the Log; each tab keeps its own search text. The hooks: the
  spec's own groupings (`Group`, `cat.Emit`, its own fold key), filters
  (`PassesFilter`), row badge (`RowRight`, with its dim flag), card,
  overview and its extra sections, briefing sections, state words, reasons,
  row tooltip, menu (`MenuInit`, paged by `cat.AddCategoryPages`), stock and
  custom actions, the ignore list shared with the Zones tab, its two named
  dropdowns (`CommanderQuestLog<prefix>GroupDrop` / `...Menu`) and
  `Q.OpenToTab` — and the Zones tab's widgets never touched. When written,
  a scratch copy without `HideOtherTabs`, with a binary `OpenToQuest`, with
  `IsEnabled` ignored, without `RowRight` and with fixed-width placement each
  failed a check. The window does NOT load the rules engine, so the Zones
  tab here has no badge and its briefing keeps Questie's raw REPUTATION rows
  (`+250  Honor Hold`): loading `CommanderQuestLogReputationData.lua` and
  `CommanderQuestLogStanding.lua` here would deliberately move exactly two
  checks (Q's "REPUTATION lists what it pays", which becomes "+275 Honor
  Hold" for a Human, and Q3's "the Zones tab, with no RowRight, never makes a
  badge"); reputation on the window's surfaces is
  `questlog_rep_everywhere_harness.lua`'s.
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

The mock lives in `questlog_mock.lua` since 1.6.0 (the harness `dofile`s it
and binds its fourteen bare state names — `log`, `selection`, `watched` and
the rest — with `mock.Bind`, so every section reads them as it always did;
from the fixtures on the file is byte for byte what it was, apart from Q3).
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
- **The main chunk is close to Lua's 200 locals.** Sections Q, Q3 and R are
  each wrapped in `do ... end`; a new section should be too (91 of 200 used).

---

# completion_engine_smoke.lua — the engine (756 checks)

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
  both modes; **O** standings, and *(1.6.0)* an unknown standing that is NOT
  Neutral: `StandingWord(nil)` has no word, an unmet faction reads the DB2
  base handed in as the second argument (Sporeggar, Kurenai and Mag'har
  Unfriendly, Netherwing Hated), a known value wins over the base, and a word
  is neither (critic W6; nine checks, a do-block of their own, nothing above
  them edited; three mutants of the fix each caught); **P** no shape
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

# questie_adapter_smoke.lua — the Questie adapter (676 checks)

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
  `IsQuestComplete`), beating a stale scan, and only on a true answer; **Q2**
  (D46) a {-1, -1} spawn asks Orders' locator first: the Blood Furnace's
  sentinel is the stub's door, Hellfire still lists the quest (Questie's
  entrance zone kept), the Underbog's door on Zangarmarsh keeps Zangarmarsh,
  a second door on Hellfire is a spot for the arrow only (zone nil, so
  Hellfire does not start listing it), the turn-in follows; a locator that
  raises or answers "loading" leaves Questie's spot; **P** nothing forbidden,
  nothing leaked into globals, no glyphs.
- **R — reputation (1.6.0)**, 238 checks over `Fake.RepWorld()` (real quest
  ids with Questie's real rows) with the REAL rules engine and the generated
  data, both loaded for this section only and taken away after it, a fresh
  adapter over a fresh world per subsection. **R1** one number per quest
  (+275 for a Human's 250, the rival's -302 and the Sha'tar's +137, the
  audited Hellfire Wanted rows on the player's side only, the Netherwing
  clamp, the 42,999 ceiling, "No reputation", rows handed in for a quest
  Questie does not know, one answer per generation, the adapter's DIRECT
  rows equal to the engine's own on every quest of the world, a waypoint's
  note and its switches); **R2** the faction index read on first need, never
  at login, 400 quests a frame, stepping the generation when done, audited
  rows members and stored spillover halves not; **R3** faction views on their
  own two-slot cache (area 47 The Hinterlands against faction 47
  Ironforge), `view.rep`, the Sha'tar window listed as uncounted extras,
  order hints, repeatable item costs, `QuestDetail` by kind; **R4** the
  picker (groups, sides, `RepIncludeClassic`, notes); **R5** faction
  summaries in the background, waiting on the index; **R6** a zone's totals
  per faction; **R7** the character (standings, the base for a faction not
  met, the multiplier, the Orc clamp, the side); **R8** today's rotating
  dailies from Questie's record and quests held back by phase; **R9**
  calibration from the bars and from the chat line (the two-way window,
  ambiguity, a faction moving twice, source-capped spills, zero samples,
  normalised under the Wickerman, no saved variables); **R10** the guards
  (no rules, a raising engine); **R11** `/cql status`; **R12** the same
  number on every surface; **R13** the 1.6.0 review's fixes (2026-10-04):
  the zone totals' spill share is what the window lands (0 when the
  Sha'tar's is shut, the chosen side's alone when both rivals have quests
  here), an undecided choice counted per faction (the Scryers' pledge), a
  dungeon quest that starts here in the totals (`extraLeft`), the best OPEN
  turn-in quoted and the Wanted dailies flagged, an ignored quest out of
  done and left, every per-turn-in figure 0 at the cap as the row is,
  Sporeggar's quest waiting on Neutral (`unreachedCount`, `repeatReach`),
  a mixed calibration move set aside and an older build's samples of one
  never read, today's Wanted pick across a daily reset (the world's
  `serverTime` / `questResetIn`), and a waypoint note rewritten through
  Orders' `Update` when the numbers move, never over another's note or a
  removed waypoint. Every R13 check fails against the adapter and engine as
  they stood before the review (18 failures). **R14** the 2026-10-05 review: a
  spill window lands only the source quests the source's own projection
  reaches -- an unpledged character's Shadowmoon (Aldor 0) gets the
  Sha'tar +137 from the one ungated Aldor quest, not the Friendly-gated
  one's too; the Sha'tar's faction view, whose pledge reaches Friendly,
  keeps that one and drops the Revered-gated one; pledged, the quest shut
  above Neutral is dropped as locked out. With the adapter's `GateSpill`
  a no-op, three of its five checks fail. Printed as SKIPPED (and the count 423) when
  `CQL_STANDING` points at a missing engine; with `CQL_ENGINE` missing too,
  343. The 423 checks above it are unedited: the 1.5.0 smoke file itself,
  run against the 1.6.0 adapter and fake, still passes 423/0. All 40
  single-change adapter mutations tried when written are caught.

Mutation-tested when written: about thirty-five single-line breakages of the
adapter, each failing at least one check; and on 2026-10-04 each of the
review's nine adapter fixes reverted alone, each caught (`CQL_ADAPTER`); the
adapter from before round 2 fails four of the round-2 checks.

# questlog_map_harness.lua — the world-map drawer and pins (337 checks)

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
- **O — reputation (1.6.0)**, 26 checks appended before the last line (none
  above edited), over `Fake.RepWorld()` with the REAL rules engine and data,
  loaded for this section only. **O0** the default world without the rules:
  no badge, no line; **O1-O9** the badge in the MAXIMIZED drawer only (the
  windowed one is 30 px narrower), the row and giver-pin tooltips'
  "Reputation: ..." line, a waypoint's note, the Wickerman, a sample seen in
  game, `ZoneRowRep` and `ShowRepEverywhere`, no stale badge on a pooled
  zone row; **O10** the badge names its faction ("+275 Aldor" beside "+550
  Sha'tar" in Shattrath; "+1,100 HH" whole in the 64 px cap); globals,
  writes and glyphs. The reputation client is uninstalled afterwards.

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

**The reputation world (1.6.0).** `Fake.RepWorld()` is a level-70 Human
paladin pledged to the Aldor, over REAL quest ids carrying Questie's real
`reputationReward` rows (from the real-data boot; synthetic ids start at
91000), with `rep = true` so `InstallClient` also calls
`Fake.InstallRepClient(world, opts)`: `UnitRace`, `UnitSex`,
`UnitFactionGroup`, `GetRealmName`, `GetLocale`, `GetText` and the
`FACTION_STANDING_*` strings, `GetMaxDailyQuests`, `GetItemInfo` and the aura
APIs; `Fake.UninstallRepClient()` puts back exactly what was there. A faction
missing from `world.factions` is NOT MET (`GetFactionInfoByID` answers nil,
A21). Its handle adds `SetUnavailable` (Questie's "not offered today"
record), `ResetDailies`, `SetAura` (24705, the Wickerman), `Meet` and
`RepChange` (moves a bar and returns the client's chat line). The world keys
(`realm`, `locale`, `unavailableByTalking`, `contentPhases`, `unmetNames`,
`itemCache`, `maxDailies`, `noAuraById`, `femaleLabels`, and since the
2026-10-04 review `serverTime` / `questResetIn`, which install
`GetServerTime` / `GetQuestResetTime` only for a world that sets them) are
documented in the fake's header. The default world is never given reputation fixtures: its
counts are other harnesses' assertions.

---

# questlog_orders_contract.lua — the adapter against the real Commander Orders (65 checks)

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

Since 1.7.0 (D45) it boots `Fake.GoWorld()` (the default world plus quest
9005's objectives, below), and E expects Orders 3.1's one refusal line with
the place's [Go] link. The new sections run the "Go to" work on the real
Orders 3.1:

- **F** a press is Orders' `GoTo`: Orders' own "Waypoint set" line and none
  of the Quest Log's; owned (QuestLog, `quest:9005`) with the quest's icon.
- **G** quest 9005's objectives in Questie's order (the object first, as
  `objectObjectiveFirst` asks), each named, each one's spots (the poster, the
  eight sentries, the missive's nine droppers' spawns, none for the
  reputation goal, Orders' own Blood Furnace door for Caza'rez (D46), the
  explore trigger's spot); the sentry Go taken by Orders with all eight spawns and
  the arrow on the one the player stands by.
- **H** one waypoint per quest across its keys: objective, turn-in, objective
  again; another quest's left alone.
- **I** `QUEST_TURNED_IN` and `QUEST_REMOVED` remove every key of the quest
  and nobody else's (quest 900's turn-in leaves 9005's).
- **J** the pinned quest Go survives `M.Reload` (Orders 3.1 keeps it) and the
  turn-in after the reload still clears it.
- **K** a follow-up's Go: The Legion Reborn starts with Danath; an
  item-started quest has nowhere to go.
- **L** (D46) the Shadow Labyrinth as Questie has it (area 3789, Terokkar
  39.6, 71.0), Murmur inside it and quest 10095 to kill him, added to the
  world in `BootOpts`: Murmur's objective Go lands within 5 yd of Orders'
  `Entrance({ instance = 555 })` (Questie's own spot is 100 yd short), one
  place, and the real Orders takes it.


---

# reputation_data_smoke.lua — the generated reputation data (432 checks)

Loads the GENERATED `CommanderQuestLogReputationData.lua` alone into a SEALED
environment: reading any global raises, and the only global it may write is
its own table, so the run itself proves the file is pure data. Then it walks
the table the way the rules engine and the adapter read it, and holds the
generator to what it claimed.

- **A** the file is data: one global, no functions, no metatables; **B** the
  scalars: build, bottom, cap, the eight thresholds, the rules (no low-level
  penalty, Diplomacy 20599, the Wickerman 24705, spillClamp "capTop").
- **C** all 75 factions: a name, a slot, base rows that fit, known parents,
  spill edges onto real factions at sane rates and sides, and the starting
  standings the design leans on fitted as the client fits them (Sporeggar
  -2500, Kurenai -1200 for every Alliance race, Mag'har -500, Netherwing
  -42000, the Aldor and the Scryers +-3500 by race, Silvermoon and the
  Exodar by race, the other side's -42000).
- **D** the picker groups: order (Outland, Shattrath, the other TBC
  factions, then the classic headings), membership, no faction twice, no
  heading; the `tbc`, `side` and `header` fields. **E** the localized names:
  TBC factions only, only where they differ from English.
- **F** `rewardCap`: every RewMaxRepValue row (critic W1's fifteen quests)
  plus the manual 10871. **G** `derived`: the spillover written into rows
  (10326, 9266, 4766) and not the header coincidences (281, 7642). **H**
  `repeatCost` (flat pair lists), **I** `rotating`, **J** `conditional`.
- **K** `overrides`: every row cites its Wowhead page, none was refused;
  **K5** the nine corrections where Wowhead and CMaNGOS agree against
  Questie (D38, widened 2026-10-04) are emitted whole, every Questie row
  they drop written as 0 (it fails against the data generated before them).
  **L** the reconciliation the generator recorded: zero template mismatches.

Rules that hold for every row are batched into one check each (the count of
offenders and the first one on failure), so the count does not move when
the generator is re-run on new data. Twelve deliberate breakages of a copy
of the data file (`CQL_REPDATA`) each failed it when written.

## make_reputations.py — the generator

```bash
python3 Commander_QuestLog/Harness/make_reputations.py            # rebuild from the cache (no network)
python3 Commander_QuestLog/Harness/make_reputations.py --check    # write nothing; exit 1 if the file is stale
python3 Commander_QuestLog/Harness/make_reputations.py --fetch    # fetch Faction_<locale>.csv (and any missing input) first
python3 Commander_QuestLog/Harness/make_reputations.py --questie dump.tsv   # also reconcile against a Questie dump (qrep.lua format)
```

Inputs: the client's Faction DB2 for this build (wago.tools CSV,
2.5.6.69795) and the same table per locale, and the CMaNGOS tbc-db dump read
through `Commander_Formulary/Harness/cmangos.py` (gzipped, through its
`_columns` / `_tuples`; the script sets `dont_write_bytecode` so nothing is
written into Formulary's folder). Both live in the suite's shared, git-ignored
generator cache, `Commander_Quartermaster/Harness/.cache` (`--cache` or
`$CQL_REP_CACHE` override it). `--fetch` writes only `Faction_<locale>.csv`
there, and `Faction.csv` when it is missing; the dump comes from
Quartermaster's own `tbcdb_to_sqlite.py --fetch`. A rerun without the
locale files stops rather than silently shipping no names. The one
hand-written input is `reputation_overrides.json` (the Wowhead audit, D38):
every row must cite its page, name a known faction and carry integers, or it
is refused and counted (`reconciliation.overridesRefused`, which the smoke
holds to 0). The stdout report is the list of everything that did not
reconcile: read it by hand after a run. `SHIP_NAMES = False` in the script
ships an empty names table (about 5 KB of the 31.6 KB). Whenever
`reputation_overrides.json` changes, run the generator, then the data smoke
and `standing_smoke.lua`; neither count moves (unless a check names the
override: K5 and standing Q do for the nine of 2026-10-04).

# standing_smoke.lua — the reputation rules engine (609 checks)

Loads `CommanderQuestLogStanding.lua` ALONE into a sealed environment, as the
completion smoke does, so the run proves the engine is pure. The generated
data is loaded into an environment of its own (it may write its one global
and read none) and handed to the engine as an argument. Two kinds of check,
kept apart: ENGINE checks run on the real factions table with a FIXTURE of
quest tables written in the harness, so they prove the rules whatever the
generator emits; DATA CONTRACT checks (section Q, 53 checks) run the same
scenarios on the generated quest tables.

- **A** loading; **B** the data as the engine reads it; **C** ranks and their
  edges (-6001/-6000, -1/0, 8999/9000, 41999/42000, the 42999 clamp); **D**
  starting standings, the first base row that fits; **E** the multiplier and
  one turn-in (`trunc(250 x 110%) = 275`, the doubled quest rate of the
  three Classic factions, the reward clamp, the ceiling).
- **F** effects on the Aldor, the Scryers and the Sha'tar (+275 / -302 /
  +137 for a Human); **G** clamps, the Sha'tar window (capTop: spill stops at
  8999), the ceiling and the bottom (an Orc at 8900 Aldor doing 10326: +99 /
  -108 / +49; 10870 from -42000: 0); **H** derived rows dropped (10326, 9266,
  4766), overrides applied (0 removes a row), headers at each child's rate,
  sides, unknown standings, observations; **I** `Primary` and `For`.
- **J** the line ("+250 Honor Hold", the full three-faction line, "No
  reputation", "0 ... (capped)", the compact form, "and N more"); **K**
  abbreviations, unique within a table; **L** words and numbers (localised
  labels, a female form, `FormatProgress`).
- **M** repeatables: turn-ins to the next rank, to the cap and to Exalted, a
  gate's last turn-in, the reward clamp, every item cost of a multi-item
  turn-in; **N** today's rotating Wanted dailies and daily income (never
  summed, the cap of 25, Halaa conditional, and from the standing now: 0 at
  Exalted 999, the 99 left below it); **O** the projection: the best
  order, closing gates first (the Consortium's below-3000 quests before the
  big ones), the Sha'tar window, exclusive slots counted once, Aldor against
  Scryers as one choice, Ally of the Netherwing early, the "Do X before
  Friendly" hints, what each quest paid in the order (`gains`), the two
  pledges as one slot weighed inside each side (the Scryers' choice keeps
  the Scryers' pledge); **P**
  calibration: normalisation by the multiplier that applied and the drop
  rules (ceiling, bottom, reward clamp, spill cap), and a MIXED move --
  Orgrimmar and the Darkspear spilling into each other -- stored exactly and
  read back as the same numbers, not doubled (`MixedSources`, `ObservedFor`,
  a spill never reading a DIRECT sample).
- **Q** the data contract (critic W1's caps, the derived rows, every override
  cited, and the nine corrections of 2026-10-04 end to end on Questie's own
  rows: Timber Worg Tails and Rise of the Silithid pay nothing, Poisoned
  Water the Horde header's 250, Help for Mudsprocket Gadgetzan 10, The Lord
  of Blackrock's compounding 1,098). With the scratch prototype as data
  (`CQL_REPDATA`) it prints Q SKIPPED and counts 555. **Z** glyphs (only the middle dot and the em dash
  outside ASCII), purity and code bans.

Mutation-tested when written: 49 of 49 mutated engine copies (`CQL_STANDING`)
were caught; the 2026-10-04 additions to N, O and P fail against the engine as
  it stood before the review (10 failures), the Q additions against the data
  generated before the nine overrides (9). Budgets: main chunk 55 of 200
  locals, at most 25 of 60 upvalues.

# questlog_reps_harness.lua — the Reputations tab (192 checks)

The window's third tab over `Fake.RepWorld()` with the REAL rules engine,
generated data, adapter, catalogue and window, on `questlog_mock.lua`. Every
TOC file loads but the map drawer and the NPC dialog, which have harnesses of
their own (a scratch copy that also loads the dialog file gives 192/0 too).
The client's Reputation pane is modelled here, because nothing else needs
it: headings that fold and the factions under them behind `GetNumFactions` /
`GetFactionInfo` (isWatched 12th, factionID 14th, as Classic's
ReputationFrame.lua reads them), the watched faction behind
`C_Reputation.GetWatchedFactionData`, and `SetWatchedFactionIndex` and
`ExpandFactionHeader` recorded, so "Watch Faction never unfolds the pane" is
a real check.

- **A** the tab, its settings and `/cql rep`; **B** following (the watched
  faction, else the faction the log's quests pay most, else the pin), the
  index being read, the card; **C** rows (the badge, "0 capped" dimmed, the
  state words for repeatables) and the five groupings (Guide, By zone, By
  value, By status, By chain); **D** the Consortium's overview and a quest's
  briefing; **E** the Sha'tar's spill window, open and shut, a quest in the
  log; **F** the Aldor's repeatables, item costs (a name the client does not
  have yet, redrawn on `GET_ITEM_INFO_RECEIVED`), a quest's every effect and
  a cap; **G** Honor Hold, Netherwing not met (its base, Hated) and
  Stormwind (a capital's quarter); Honor Hold at the ceiling (Exalted 999 /
  1,000: DAILIES one line whether today's Wanted is known or not, QUESTS
  "none pays anything more", never "worth 0" or "up to 0"), at Exalted 900
  (held to the 99 left), open dailies a reward clamp holds to 0 (stubbed),
  and the CHAIN heading's "(quests that pay Honor Hold)" (a chain handed to
  the view: the fake world's faction views have none).
- **H** the actions (Waypoint, Show on Map on the zone the quest starts in,
  Open in Log, Watch Faction, Ignore / Count); **I** `/cql rep` following,
  `/cql rep <name>` by name in any case without the apostrophe, by the start
  of a name, by id, the other side's faction and nonsense not found, and
  every other subcommand still the framework's; **J** nothing to show: the other side's
  faction pinned (`RepPicked` is account-wide, so that pin is an alt's: passed
  over, and the navigator says whose it was), no quests, no rules; **K** the register: moving off, switching
  off; **L** on the parchment; **M** standing words in the client's female
  form; **N** one number: every row's badge is the adapter's effect on the
  faction and every briefing's line `A.RepLine`'s; **O** no glyph in 200+
  drawn strings (the middle dot, the em dash and the ellipsis are the only
  characters outside ASCII); **P** words that say what they count: the
  picker's "0/4 done" (never a bare percentage beside the standing word),
  the Consortium with today's Wanted not known ("Nothing to count on yet",
  never "None you can do today"; each pool "N in the rotation pay it"), the
  Shattered Sun before its phase (the navigator says why it is empty), and
  REPUTATION and AS A SOURCE above WHERE; **Z** clean: no error, nothing forbidden asked
  of Questie, the pane never unfolded, no adapter error.

`CQL_REPS` loads a mutated copy of the tab; 37 of 37 single-change mutants
were caught when written, and each of the review's UI fixes reverted alone
(2026-10-05, a scratch copy of the module) is caught here, in the
rep-everywhere harness, the drawer's or the dialog's: 25 of 25; the second
round's ten (the ceiling's words on both tabs, the badge fit on the tab and
in the drawer, the dialog's heading, the CHAIN label) likewise, 10 of 10. The mock's `RegisterUnitEvent` is a no-op here, so
the Wickerman check steps the generation with `A.Bump`; the adapter smoke
covers the event path.

# questlog_rep_everywhere_harness.lua — one number on every surface (203 checks)

The whole module as the TOC loads it (data, rules, adapter, window,
catalogue and Zones tab, the quest dialog and the map drawer; the
Reputations tab only with `CQL_WITH_REPS=1`, still 203/0) on
`questlog_mock.lua`, over `Fake.RepWorld()` with four quests in the log, the
2.5.6 quest dialog (`questframe_mock.lua`), a small world map for the drawer
and a recording Commander Orders.

- **A** the Log's briefing: "Reputation: +275 Honor Hold" as a reward line
  under REWARDS, or under the facts when there is none; "No reputation";
  the switches; ink on paper; "(seen in game)"; the Log's waypoint note.
- **B** the Zones rows: the badge left of the state word, naming its
  faction ("+275 HH", "+385 Cons", a faint "0"), a quest worth 0 still
  counted and never dimmed for it, the row tooltip's line (light on the
  parchment too: the tooltip is the game's dark one), `ZoneRowRep` and
  `ShowRepEverywhere`; the badge held to 12 characters
  (`C.RepBadgeText`: "+1000 Scry", "+2000 Mag", UTF-8 safe) and Shattrath's
  Allegiance to the Scryers reading "+3850 Scry". **C** the Zones briefing's REPUTATION: every effect
  with its kind and cap, the multiplier, a shut spill window shown at 0,
  the section under the reason (before WHERE), and with Reputation on Every
  Quest off 1.5.0's section (Questie's raw row, at the end). **D** the
  overview's REPUTATION IN THIS ZONE, straight under the zone's completion:
  left (the projection's count), done, whether it reaches the next standing
  and how far short of Exalted, what the spill window LANDS from the source
  chosen (open, about to shut at 8,500, shut at 9,500, and a stubbed
  totals table whose raw sum differs), the dungeon quests' share, quests
  waiting on a standing never reached, the steady dailies apart from the
  rotating Wanted ones and Halaa's, order hints, factions not met, the
  done-only line, worked out once a generation; Honor Hold at the ceiling
  (one "Exalted, nothing more to earn here" line, no "0 left in", "0 a
  turn-in" or "up to 0") and at Exalted 500 ("Already Exalted.", never
  "Quests here reach Exalted."), and a stubbed table with quests and
  repeatables held to 0 below the ceiling and two factions at it.
  **E** By reputation.
- **F** the map drawer: the badge (maximized only, "+275 HH", Shattrath's
  "+3850 Scry" fitted as on the tab), the tooltip, the waypoint's note. **G** the quest dialog.
- **H** THE CROSS-SURFACE CHECK (SPEC section 9): four quests on eight
  surfaces each (the Log, the Zones badge, tooltip and briefing, the
  waypoint's note, the drawer's badge and tooltip, the dialog, whose
  several factions are one per line), the same number three times over: plain, under the Wickerman, and after a sample
  seen in game replaces the data's (Marks of Kil'jaeden's too, whose dialog
  puts "(seen in game)" on its heading).
- **I** hygiene: no global beyond the documented ones, no glyph, no error,
  nothing forbidden asked of Questie.

`CQL_UI`, `CQL_ZONES`, `CQL_QUESTFRAME` and `CQL_MAP` load mutated copies;
56 single-line breaks were caught when written.

# questframe_harness.lua — the NPC quest dialog's line (86 checks)

Drives `CommanderQuestLogQuestFrame.lua` over `questframe_mock.lua` (the
2.5.6 dialog as Blizzard builds it) on `questlog_mock.lua`, with
`Fake.RepWorld()` and the REAL rules and data behind the adapter.

- **A** loading: post-hooks only, at load; no global; no field written on
  any Blizzard frame or table, ever (read again at the end of the run).
- **B** the offer: "Reputation: +275 Honor Hold" under the rewards, in the
  dialog's own ink and font, in the scroll child the dialog draws into,
  arriving with the rewards' fade and not before; **C** the turn-in panel;
  **D** "No reputation", a quest with no rewards (under what the spacer
  hangs from), several factions one per line under "Reputation:" (in 275 px
  one line wraps inside an effect), word for word the adapter's line.
- **E** every other panel, another caller's Display (the TBC quest log has
  none, but the shared frames are anyone's) and the dialog closing take it
  away; **F** rewards arriving late (`QUEST_ITEM_UPDATE`);
  **G** no quest id from the client: a turn-in found in the log by title, an
  offer gets nothing, two log quests with one title get nothing.
- **H** the settings (flipped while the dialog is up), Questie still loading,
  the Wickerman and a calibration sample changing what an open dialog says
  (several factions seen in game: "Reputation (seen in game):" heads them);
  **I** what cannot be answered gets no line; an error is reported and the
  dialog drawn all the same; a client without the dialog at load is hooked
  at PLAYER_LOGIN.
- **J** (D47) another addon asking for a reward button out of turn, as
  RXPGuides' marks do (slot 4 from a quest-log choice number, -1 for no
  pick): unguarded, the stock dialog alone keeps the report's list (-1, 1,
  2, 4) and the next dialog dies on slot 3; with the module the hole is
  filled by Blizzard's own factory, hidden, Blizzard's own calls fill
  nothing, a fraction, 0 and slot 12 fill nothing, and the next dialog
  draws its one reward with the line under it.

`CQL_QUESTFRAME` loads a mutated copy.

# questlog_goto_harness.lua — "Go to" in the window (72 checks)

D45 (1.7.0). The window harness drives the window WITHOUT
`Commander_Events/CommanderGoButton.lua`, so its checks keep proving the
plain-button path; this one loads it, on the same client (`questlog_mock.lua`,
its silent `Enable` / `Disable` given state here), over the fake Questie's
`GoWorld` (quest 9005 in the log with an objective of every kind) and a
recording Commander Orders 3.1 (`GoTo` merging its options into the place as
the real one does, `IsGoing` by the arrow's owner, `PlaceFor`, `Reason`,
`SharePoint`, `CopyText`, `List`, `RemoveBy`; its `Add` raises, since no Go
may take the 3.0 path while GoTo is there).

- **A** the Log's "Go to Turn-in" (120 px) and the Zones tab's "Go" are the
  suite's GoButton.
- **B** the Log's briefing: a row Go on the poster, the sentries, Caza'rez
  and the trigger, none on the finished missive or the reputation goal; at
  the briefing's right edge, the line keeping room for it; its tooltip; a
  click is GoTo under `quest:9005:2` with all eight spawns, lit "Going" for
  that objective alone; Shift-click shares through `SharePoint(..., "CHAT")`,
  Ctrl-click copies the /way line; Caza'rez goes to the Blood Furnace's
  entrance and the quest keeps one waypoint.
- **C** Go to Turn-in: `quest:9005`, the finisher's title, the objective's
  waypoint dropped, lit "Going to Turn-in", its tooltip and gestures.
- **D** a log row's Ctrl+Right-click goes to its turn-in, a plain
  right-click still tracks, the tooltip names the gesture, and a quest with
  nothing to place puts the objective Go buttons away.
- **E** the Zones tab: Go on the selected quest (its own key, every spawn,
  lit, greyed with nothing selected); LEADS TO's Go to that quest's giver;
  an in-log quest's objectives carry the Log's Go; a quest with nothing to
  place has none.
- **F** Orders turned off: every Go greyed, Orders' reason in the tooltip;
  a greyed Go promises no press (D46: 2.5.6 delivers no OnClick to a
  disabled Button): neither the hover nor the module's own line (read
  straight from `_goOpts.tooltip`) says "a press says so" or "Goes to", and
  the own line names the row's gesture instead; on again, "Goes to the
  Commander Orders arrow".
- **G** no error, plain ASCII words, no global written.

`CQL_UI`, `CQL_CATALOGUE` and `CQL_ADAPTER` load a mutated copy.

`fake_questie.lua` gained `Fake.GoWorld()` for this (and the contract
harness): the default world plus quest 9005's `objectives` (a creature, an
object, an item with `npcDrops`, a reputation goal, a kill credit whose
creature stands only inside the Blood Furnace) and `triggerEnd`, with
`objectObjectiveFirst` naming 9005. `Install` now gives every world
Questie's five `*ObjectiveFirst` tables (empty unless `world.objectiveFirst`
says). The default world itself is untouched: its counts are other
harnesses' assertions.

# questlog_mock.lua and questframe_mock.lua — not harnesses

`questlog_mock.lua` is the permissive client `questlog_harness.lua` was
written against, lifted out in 1.6.0 so the Reputations tab, reputation on
every surface and the quest dialog can drive the window on the same client.
Load it FIRST (it installs its globals on load); its header has the recipe
(`mock.state`, `mock.Bind`, `mock.Checker()`, `mock.TocFiles(exclude)`,
`mock.LoadFramework` / `LoadModule` / `Login`, `mock.Header` / `Quest`,
`RunTimers`, `Fire`, the hover helpers, the print and error logs). Any
widget method it never heard of is a silent no-op whose Get answers nil, so a
check that reads one back proves nothing: assert on what the mock tracks
(sizes, levels, shown state, text, colours, word wrap). `GameTooltip`
records each line's text in `__lines` and, since the 1.6.0 review, the
colour it was given in `__colors` (a tooltip line's ink was unchecked).

`questframe_mock.lua` is the 2.5.6 NPC quest dialog cut down from
Blizzard's own source (`Classic/QuestFrame.lua` with `TBC/QuestFrame.xml`,
`TBC/QuestInfo.lua` and `.xml`): the detail and reward panels laying
themselves out through `QuestInfo_Display`, the rewards' late re-layout
through the global `QuestInfo_ShowRewards`, the detail panel's fade, and a
record of every field the module writes on a Blizzard table (there must be
none). In this process it also gives `questlog_mock`'s widgets
`SetParent` / `GetParent` and a `RegisterUnitEvent` that registers (the
plain mock's is a no-op).

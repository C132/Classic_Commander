# Commander_QuestLog harness

One luajit check. Run it before any change to the scan, the display list, the
briefing, the actions, or the takeover.

```bash
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_harness.lua   # 146 checks
```

It resolves the AddOns root from its own file location, so it works in a git
worktree as well as in the live AddOns directory, and exits non-zero if any
check fails.

## What it covers

The harness loads the real `CommanderSettingsUI.lua` and `CommanderEvents.lua`
alongside all three `Commander_QuestLog` files under a permissive WoW mock,
builds a nine-entry quest log across three zone headings, fires login, and then
drives a whole session — including turning quests in underneath the window
while it is open.

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
- **N — the global footprint.** The module publishes its five entry points and
  its two key bindings and nothing else. `Bindings.xml` is read as *text* (the
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
- **`Show`/`Hide` fire `OnShow`/`OnHide`.** The window does all its work in
  `OnShow`; a mock that skipped it would test an empty frame.
- **Widths and heights are tracked for real.** The navigator advances its
  layout by each row's height and sizes its progress bars off the pane, so a
  mock answering 0 to both would draw every row on top of the first — and the
  check that catches it reads the offsets back off the rows.
- **Focus is tracked**, so "does the window steal the keyboard" is a real
  check rather than a vacuous one.
- The mock character is a level **62** warrior, which is what puts the fixture
  quests either side of every difficulty threshold.

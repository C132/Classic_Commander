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

**D12 — The window never takes keyboard focus on open.** It is opened with a
key, and an autofocused search box turns WASD into typing. This is the trap
Commander_Vault paid for at the banker; the search box is reachable by click or
by its own binding.

**D13 — No quest database.** The module reports what the client knows and
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

## Assumptions worth re-checking in game

- **`HideUIPanel` inside `QuestLogFrame`'s `OnShow`.** This is the standard
  frame-replacement gesture and the harness covers the logic, but the UIPanel
  manager's own bookkeeping is not modelled. If the stock frame ever flickers
  or leaves a gap in the panel layout, defer the hide by a frame instead.
- **`MAX_QUESTS`.** Read from the global with a fallback of 25, which is the
  era's cap either way; the readout is the only thing that depends on it.
- **`GetQuestLogTitle`'s third return.** Vanilla answered a tag string, this
  client answers a suggested party size. Both are carried rather than one being
  assumed, so a client that changes its mind degrades to a missing facts entry
  rather than to a number rendered as a word.

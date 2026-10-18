# Commander_Notebook harnesses

Four luajit checks, all in-addon. Run **all four** before any change.

```bash
/opt/homebrew/bin/luajit notebook_harness.lua         # store fixture - 235 checks
/opt/homebrew/bin/luajit notebook_ui_harness.lua      # UI + host     - 190 checks
/opt/homebrew/bin/luajit notebook_orders_smoke.lua    # the REAL Commander Orders - 55 checks
/opt/homebrew/bin/luajit globals_lint.lua             # 3 files, 0 undeclared globals
```

All three resolve the AddOns root from their own file location, so they work in a git worktree as
well as in the live AddOns directory. Each is silent on success and exits non-zero on the first
failure it finds.

---

## `notebook_harness.lua` — the store

No mock at all. `CommanderNotebookStore` is pure Lua, so this loads that one file and drives
hand-built SavedVariables tables through the real calls. A failure here is always a real logic bug,
never a mock artefact. The clock is frozen and advanced by hand (`TICK`), because otherwise every
"did this restamp `updated`" assertion would be a race against a one-second tick.

Covers the normalising `Attach` contract against tables damaged the way a hand edit or an older
build damages them; the notebook and tag models including the merge case; every mutator's no-op
guard; the two-stage trash and its age-out; the search grammar (`tag:`, `notebook:`, `is:`, quoted
phrases, ANDed bare terms, and matching *inside* a hyperlink label); the ordering rules, including
the id tiebreaker that keeps an unchanged list from flickering; and link extraction.

Sections worth knowing about:

- **A3–A6** are the damaged-table cases. A note pointing at a deleted notebook, a `NextID` that has
  fallen behind the ids in use, junk where a table should be. The invariant being proved is that
  loading a broken file loses a *folder*, never a *note*.
- **E1–E2** prove the no-op guards. They exist because loading a note into the editor fires
  `OnTextChanged` with the note's own text, and without them merely reading a note would restamp it.
- **F2** is the trash invariant: a trashed note appears in the trash scope and in no other view.
- **H6** creates eight notes in the same frozen second and lists them five times. `table.sort` is not
  stable, so without the id tiebreaker this is where the flicker would show up.
- **K1–K7** are where a note was written (1.1.0, DECISIONS D10): a context is kept only with a map
  and coordinates in range, as a copy, without counting as an edit, and a stamp with no position
  never erases the last place; `S.Location` prefers the context and otherwise reads the newest old
  stamp line that names a place (never the date, never a target named like coordinates); duplicates
  keep the map; `Attach` cleans a damaged context.

## `notebook_ui_harness.lua` — the UI and the host

Loads the **real** shared framework (`CommanderSettingsUI.lua`, `CommanderEvents.lua`) plus all
three addon files under the suite's permissive widget mock, on top of a fixtured previous session:
one notebook, two notes, a remembered source pointing at a notebook that no longer exists, and a
saved setting that the defaults pass must not overwrite.

The mock is the shared suite preamble plus one addition that matters: **edit boxes have real focus
and real text**. This module branches on `HasFocus` for its auto-save contract, its deferred
re-sort and its shift-click link path, so a mock without focus would pass every test while proving
nothing. `Type(box, text)` sets the text and fires `OnTextChanged` with `userInput` true, which is
the flag every handler in the module actually reads.

It drives login, the settings panel, building the window, writing and saving, search, the sidebar,
the trash, quick capture, the link wrapper, both skins, stamping, the notebook dialogs, and every
slash entry point.

The checks worth naming:

- **R1/R2** — Restore Defaults cannot delete writing. R1 checks it as a property of the defaults
  table; R2 runs the real `/cnote reset` path and counts the notes afterwards. This is the one
  mistake in this module a user could not recover from, so it is checked from both ends.
- **C7/C8** — switching notes and closing the window flush first. Both are asserted by typing
  something, doing the thing, and reading the *store* rather than the widget.
- **C9** — opening a note does not count as editing it.
- **C10** — a repaint from a menu action does not roll back keystrokes that have not been saved yet.
- **H1/H3** — the `ChatEdit_InsertLink` wrapper claims a link when the editor has focus and falls
  through to the real chat path when it does not. The fall-through is proved by counting calls into
  the original, not assumed.
- **K2** — deleting a notebook does not delete its notes.
- **L1–L9** — a stamp is a way back (1.1.0). The stamp keeps its exact map and coordinates; Go sits
  after Stamp and the six verbs still fit the 456 px row; Go and the menu entry ask Commander Orders
  (a recording stub here) for one waypoint keyed by the note; an old stamp goes through
  `CommanderOrders.Import` as a `/way <zone> x y title` line, and an ambiguous zone lists its
  candidates; a note with no place offers neither; Orders off says so; Orders missing prints the
  `/way` line; Stamp New Notes keeps the place too.

- **L10** - (1.2.0, Commander Orders 3.1, DECISIONS D11) one Go button follows whichever note is
  open (its key and its place), an old name-only stamp keeps the plain Go, a note with no place hides
  it, and Orders off greys it with the reason.

Since 1.2.0 the stub is Orders 3.1's surface: a map-stamped Go goes through `GoTo(target, opts)`
(recorded as the target and opts merged, the spec the real GoTo hands its Add), `IsAvailable` and
`Reason` answer the Go button, and the harness loads `Commander_Events/CommanderGoButton.lua` in its
TOC slot. Checks changed for the SPEC's words only: L4/L6 read the menu entry **Go To This Note**
(was "Waypoint To This Note"), and L2's "a one-line confirmation" now passes when the Notebook
prints nothing itself and GoTo was not silent (the line is Orders' "Waypoint set: ..."). L2 gained
the NOTE icon and "the Go is Commander Orders' Go button".

Mutation hooks: `NOTEBOOK_STORE=/path` (both harnesses) and `NOTEBOOK_UI=/path` load a copy in place of
the real file. Twenty-two hand-made mutants of the 1.1.0 code are all killed; of the 1.2.0 ones, the
UI harness kills the Go key not following the note, a name-only stamp given the Go button and the
Go button left showing on a note with no place, and the contract harness kills the NOTE icon
dropped (on the button and on the menu's path), the old "waypoint to" words and the old menu words.
L5 (and the real-Orders E) also read a name-only stamp's "Waypoint set" against Orders' Announce In
Chat: said while on or with no Orders settings, never while off; the line printed always, never,
or only with an Orders settings table are each killed.

## `notebook_orders_smoke.lua` - the way back against the real Commander Orders

Boots the real Orders over `Commander_Orders/Harness/orders_mock.lua` (this build's map rows, the
real settings framework and Go button) and loads the Notebook's three files after it, as the client
does. A: loads clean. B: a map-stamped note's Go is Orders' Go button; a click makes ONE waypoint
(Notebook, `note:<id>`) at the stamp's exact spot in the NOTE tint with the arrow on it, Orders'
"Waypoint set" line once and none of the Notebook's, lit "Going" while the arrow is there, the same
record on a second press, and another note its own waypoint through the same button. C: the menu's
**Go To This Note** asks for the same record. D: Orders switched off greys the button with the
reason, a click says Orders' words once, and the menu's press says Orders' ONE refusal line with the
place and a [Go] link. E: an old stamp still goes by name through Orders' `/way` resolver
(`Import`) and says "Waypoint set"; with Orders' Announce In Chat off the waypoint is made and no
line is printed by anyone, from the button, the menu or a map-stamped note alike. F: without
Orders, the `/way` line from the button and the menu.

## `globals_lint.lua` — scoping

In Lua a local declared *after* a function body is not in that body's scope, so the reference
silently compiles to a global access and reads nil at runtime. This module is built out of
mutually-recursive refresh functions — `RefreshAll` calls `RefreshList` calls `SelectNote` calls
`LoadNote` — which is exactly the shape that bug hides in, and none of it would raise until a
particular click order happened to run.

luajit's bytecode listing names every global a file really touches, so the check is exact rather
than heuristic: dump `GGET`/`GSET`, subtract the globals we mean to touch, and anything left is a
scoping bug or an undeclared API. Add a genuinely new WoW API to `ALLOWED`; do not add a name just
to make it quiet.

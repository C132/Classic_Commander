# Commander_Who harnesses

Three luajit checks, all in-addon. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit who_harness.lua      # engine fixture — 157 checks
/opt/homebrew/bin/luajit who_ui_harness.lua   # host + UI      — 145 checks
/opt/homebrew/bin/luajit globals_lint.lua     # 4 files, 0 undeclared globals
```

All three resolve the AddOns root from their own file location, so they work in
a git worktree as well as in the live AddOns directory. Each is silent on
success and exits non-zero on the first failure it finds.

---

## `who_harness.lua` — the engine

No mock at all. `CommanderWhoEngine` is pure Lua, so this loads that one file
and drives hand-written `/who` result sets through the real calls. A failure
here is always a real logic bug, never a mock artefact.

Covers identity keying, the field-alias normalisation (including the
`classStr`-vs-`className` difference that blanked the class column in 2.1), the
selection set and its prune-on-re-search behaviour, shift-click ranges, the
whisper plan with its cap and skip-yourself accounting, message validation, and
the run state machine.

The centrepiece is a **paint simulation**: a four-row pool scrolled over a
ten-player list, asserting that a tick made at offset 0 is still on the same
player at offset 4 and is not on whoever now occupies that row. That is the
reported scrolling bug, reduced to the model.

## `who_ui_harness.lua` — the host and the window

Loads the **real** shared framework (`CommanderSettingsUI.lua`,
`CommanderEvents.lua`) plus all four Commander_Who files under a permissive
widget mock, on top of a fixtured Who window: `FriendsFrame`, `WhoFrame`, a faux
scroll frame, and seventeen `WhoFrameButton` rows each with a `$parentName` font
string carrying a real column width.

The row pool is the reason this file exists. It is built the way FriendsFrame.xml
builds it — fixed count, fixed widgets, an offset that moves under them — so
`Scroll(n)` in the harness means what scrolling means in the client, and the
checks can assert against the actual `CheckButton` widgets the module created.

It also covers the 2.1 saved-variable migration, the slash-command registration
(specifically that `/cw` is gone and `/cwho` is not), the reversibility of the
name-font-string shift, the toolbar counts, both directions of the shared
selection between the Who tab and the window, the confirmation dialog, the cap,
Stop mid-run, and refusal of a second concurrent run.

### Mutation-tested

Both headline fixes have been checked by breaking them on purpose and confirming
the harness fails:

- reverting the per-paint rebind to widget-owned state (`check:SetChecked(…)`
  removed) → **7 failures**, all of them the scroll assertions;
- reverting the plan to "everyone in the list" (`if selection:Get(record.key)`
  → `if true`) → **7 failures**, all of them the mass-whisper assertions.

If a future edit makes either of those pass again, the harness is lying and
should be fixed before the code is.

## `globals_lint.lua` — scoping

In Lua a local declared *after* a function body is not in that body's scope, so
the reference silently compiles to a global read and returns nil at runtime.
Nothing warns. This module has three forward-declared locals (`RefreshRows`,
`Repaint`, and the engine's `Selection` metatable), which is exactly the shape
that produces the bug.

luajit's bytecode listing names every global a file actually touches, so the
check is exact rather than heuristic: dump GGET/GSET, subtract the globals we
mean to touch, and anything left is a scoping bug or an undeclared API.

Add a genuinely new WoW API to `ALLOWED` with a comment saying where it is called
from. Do **not** add a name just to make this quiet — that is precisely the
failure mode it exists to prevent.

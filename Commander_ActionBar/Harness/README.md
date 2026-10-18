# Commander_ActionBar harnesses

Two luajit checks, both in-addon. Run **both** before any change.

```bash
/opt/homebrew/bin/luajit actionbar_numpad_harness.lua   # numpad card + grid wiring under a WoW mock — 136 checks
/opt/homebrew/bin/luajit globals_lint.lua               # 2 files, 0 undeclared globals
```

Each prints only its failures and exits non-zero if there were any.

## `actionbar_numpad_harness.lua` — the numpad card (2.2.0)

Loads the **real** shared framework (`CommanderSettingsUI.lua`,
`CommanderEvents.lua`) and both module files under a mock written for this
module. The mock is not permissive about the things the numpad depends on:
anchors, parents and visibility are real state; a frame built from a secure
template, an ancestor of one, or an anchor target of one is **protected**, and
any protected call on it during combat (SetPoint, SetSize, Show/Hide,
SetAttribute, EnableMouse, restacking, building a secure frame) is recorded as
a violation; override bindings are a table, and a key press is delivered the
way the client delivers a CLICK binding — down and up, each only if the button
registered for that phase — into a stand-in for the bare
`SecureActionButtonTemplate` OnClick that honours `ActionButtonUseKeyDown`.

It drives: login with the numpad off (nothing built, nothing bound, the grid's
own placement unchanged); switching it on mid-fight (nothing secure built or
bound until combat drops); the standard keypad's shape cell by cell (the tall
+ and wide 0 centred in their spans), its slots (number block on the
bottom-right bar, operators on Right Bar 2), its fifteen binds to the key
proxies and never Enter or Num Lock, the caps surviving Blizzard's
UpdateHotkeys; docking and stacking with the grid card; the bottom-right bar
parked while its slots live on the numpad; key presses in both key-down and
key-up mode and the press overlay; presses, polls and the fade mid-fight;
the Apple keypad (= and the shifted operators, actions staying on their keys)
and opting into Num Lock ("Clr" on Apple); the two bar dropdowns swapping
instead of colliding; docking left/free, dragging and saving a free position,
no drag in combat, bags and the pet bar stepping out past a docked numpad;
binding off and on, no rebinding when nothing changed; `/cab numpad` in and
out of combat; and the numpad page's Restore Defaults leaving the card's own
options alone.

Mutation-checked when written: removing the combat deferral, registering the
proxy for key-up only, or flattening the tall + each fail it.

What it cannot tell you: anything about taint. The numpad faces are
addon-created `ActionBarButtonTemplate` buttons (the template Blizzard's own
bars use), and only the client can say whether that ever trips an
`ADDON_ACTION_BLOCKED`. Watch for one naming a `CommanderNumpad` frame.

## `globals_lint.lua` — scoping

Dumps every GGET/GSET from the luajit bytecode of both files and reports any
global not on the allowed list — a local declared after its use compiles to
exactly that and reads nil at runtime.

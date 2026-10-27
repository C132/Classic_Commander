# Commander_ActionBar harnesses

Two luajit checks, both in-addon. Run **both** before any change.

```bash
/opt/homebrew/bin/luajit actionbar_numpad_harness.lua   # numpad card, function-key row + grid wiring under a WoW mock — 291 checks
/opt/homebrew/bin/luajit globals_lint.lua               # 2 files, 0 undeclared globals
```

Each prints only its failures and exits non-zero if there were any.

## `actionbar_numpad_harness.lua` — the numpad card (2.2.0, 2.3.0)

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
bound until combat drops); the default Mac keypad's shape cell by cell (its
unused F16-F19 row trimmed off the top, the wide 0 centred in its span), its
slots (number block on the bottom-right bar, operators on Right Bar 2), its
sixteen binds to the key proxies and never Enter, Clear or F16-F19 unasked,
the caps surviving Blizzard's UpdateHotkeys; docking and stacking with the grid card; the bottom-right bar
parked while its slots live on the numpad; key presses in both key-down and
key-up mode and the press overlay; presses, polls and the fade mid-fight;
the F16-F19 row (a sixth row, slots 6-9 of the operator bar, bound and given
back), opting into Clear, and the PC keypad (Num Lock / * - on top, the tall +
centred across two rows, no =, no F row, actions staying on their keys); the two bar dropdowns swapping
instead of colliding; docking left/free, dragging and saving a free position,
no drag in combat, bags and the pet bar stepping out past a docked numpad;
Numpad Scale (2.3.0: relative to Card Scale, the grid card untouched, keys
inheriting rather than rescaled, still on the shared bottom edge, deferred in
combat, and a free numpad keeping its place on screen when rescaled, its
drag saving the scale it was taken at);
binding off and on, no rebinding when nothing changed; `/cab numpad` in and
out of combat; and the numpad page's Restore Defaults leaving the card's own
options alone.

Mutation-checked when written: removing the combat deferral, registering the
proxy for key-up only, flattening the tall +, dropping the empty-row trim,
ignoring Numpad Scale, or applying a free position without its scale each
fail it.

What it cannot tell you: anything about taint. The numpad faces are
addon-created `ActionBarButtonTemplate` buttons (the template Blizzard's own
bars use), and only the client can say whether that ever trips an
`ADDON_ACTION_BLOCKED`. Watch for one naming a `CommanderNumpad` frame.

## The function-key row (2.4.0), same harness

Sections I-L drive the ` F1-F5 row through the same mock, with the numpad up
beside it the whole time so the two cards have to share the console: the row
switched on mid-fight (nothing built or bound until combat drops); its shape
(one row of six grid keys at grid pitch, exactly as wide as the six-column
grid, docked on the grid's top edge with the left edges lined up so each key
sits over a column); its slots (Right Bar 25-30, ` first); its six binds on
an owner of its own, beside the numpad's sixteen and never Shift-F1 or
Shift-`, and beside the numpad's F16-F19 when that row is on; the caps
surviving UpdateHotkeys; presses in both key modes and mid-fight; the pet bar
stepping up past it; one fade for all three cards, hovering the row waking
them all; the three bar choices trading instead of colliding, from either
page, and the row giving way to the first free bar when a page reset (either
page's) lands it on a bar the numpad holds; free and docked, dragging and
saving its own position; Function Key Scale (relative, deferred in combat);
binding off and on without touching the numpad's keys; `/cab fkeys` in and
out of combat; and its page's Restore Defaults leaving the card's and the
numpad's options alone.

Mutation-checked when written: pinning the pet bar to the grid, sharing the
numpad's bind owner, dropping the settle on the row's reset, skipping the
row in the fade or the hover, a one-way bar choice, and centring the row
instead of lining it up each fail it. The row's own combat guards in
`LayoutFKeys`/`EnsureFKeys` are NOT exercised: every settings change already
defers in `OnSettingsUpdate` (removing that fails 14 checks), so those guards
only matter for a login or `/reload` mid-fight, which this harness does not
drive. The same holds for the numpad's.

## `globals_lint.lua` — scoping

Dumps every GGET/GSET from the luajit bytecode of both files and reports any
global not on the allowed list — a local declared after its use compiles to
exactly that and reads nil at runtime.

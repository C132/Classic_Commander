# Commander_ActionBar harnesses

Two luajit scripts, both in-addon, three runs. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit actionbar_numpad_harness.lua   # numpad card, function-key row + grid wiring under a WoW mock — 386 checks
/opt/homebrew/bin/luajit actionbar_numpad_harness.lua combatboot  # a /reload mid-fight — 11 checks
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

What it can tell you about taint is what the mock models of Blizzard's
action-button plumbing, read from the classic_anniversary source
(Blizzard_ActionBar/Shared/ActionButton.lua,
Blizzard_ActionBarController/ActionBarController.lua): the template's OnLoad
appends every button to `ActionBarButtonEventsFrame.frames`, `Update()` keys
one holding an action into `ActionBarActionEventsFrame.frames`, both are
walked in plain loops, and an addon-written entry taints the REST of the
walk. ActionBarController walks the first on every zone-in and page or
stance change and then shows `MainActionBar` in the same execution, which
would write its `isShownExternal` tainted (the hiddenHolder trap). Sections
N and O (2.6.0) hold the fix: our faces leave both lists the moment they are
made, a wrapped `Update()` keeps them out, our own frame hands them the same
events (only faces holding an action hear the action-list ones), their
`UpdatePressAndHoldAction` is a no-op, and they take the left button only
(the template's right-click path reads the addon-written `self.action`
before casting). Mutation-checked: leaving a face in either list, not
detaching, no dispatcher, a grid card that drags mid-fight, and faces that
keep the right button each fail it.

Still only the client's to say: anything outside that plumbing. One known
gap: dragging an action onto or off a face MID-FIGHT reads the addon-written
`self.action` in `PickupAction`/`PlaceAction` and would be blocked (out of
combat it is fine). Watch for an `ADDON_ACTION_BLOCKED` naming a
`CommanderNumpad` or `CommanderFKey` frame.

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
instead of lining it up each fail it. The row's own combat guards in `LayoutFKeys`/`EnsureFKeys` (and the
numpad's) are held by the `combatboot` run, not this one: every settings
change already defers in `OnSettingsUpdate` (removing that fails 14 checks
here), so those guards only matter for a login or `/reload` mid-fight.

## The row's F1-F5 modes (2.5.0), same harness

Section M: the F1-F5 Keys dropdown (Row Actions, Raid Marks, Party Targets),
a mode chosen mid-fight swapping nothing and rebinding nothing until combat
drops, ` keeping its action in every mode.

Raid Marks: a mark face in each action face's place, skull to triangle in
Blizzard's RAIDTARGET order, F1-F5 bound to those faces; a press marks the
target on the phase `ActionButtonUseKeyDown` picks, the same key again takes
the mark off (Blizzard's `SetRaidTargetIcon` toggle), the face wearing the
target's mark is lit, mouse clicks mark too, no target marks nothing, and
marking works mid-fight.

Party Targets: secure "target" faces seated party1..partyN then you (solo F1
is you, a 3v3 F3, a full party F5), keys past you targeting nobody (an empty
unit does nothing in `SECURE_ACTIONS.target`); names and class icons on the
seats, empty seats dimmed, dead or offline greyed, out of range red under
Out-of-Range Tint (2.6.0: `UnitInRange`, group members only, so your own
seat never tints; clears mid-fight, nothing with the option off); a join
mid-fight holding
every seat, and the face still naming who the key really hits, until combat
drops; binding off taking the caps off our own faces; back to Row Actions
restoring the action faces, slots and proxies. The mock gained a roster, a
target that wears marks, slot textures, and the secure "target" action as
Blizzard's source defines it.

Mutation-checked when written: self seated first, seating mid-fight, a mark
that never toggles off, a mark on both phases, a bind signature blind to its
targets, seats drawn from the live roster instead of the button's unit, the
action face left up under a mode, marks bound to the action proxy, and an
undimmed empty seat each fail it.

## Settings changed mid-fight (2.6.0), same harness

Section P: binds wait for combat to drop, so the caps and faces must keep
showing what the keys really do until then. Bind Numpad Keys or Bind
Function Keys switched off mid-fight leaves every key bound AND capped
until combat drops; Party Targets chosen mid-fight leaves the mark faces up,
bound, lit and capped until it drops, then the party faces arrive. The caps
follow what `BindKeys` actually bound (`__cmdBound`, cleared on every
rebind), and the mode faces the mode `LayoutFKeys` last drew
(`fkeyShownMode`), never the setting. Mutation-checked: caps read from the
setting, faces drawn from the setting, and stale bound marks each fail it.

## `combatboot` — a /reload mid-fight (2.5.1)

The same script with `combatboot` boots the addon with combat already on
and the numpad (with F16-F19), the function-key row in party mode and the
out-of-combat fade saved on, runs section Z and exits: nothing secure built,
moved or bound while the fight lasts, no fade during the fight it reloaded
into, then both cards built and bound, the party seats taken and the grid
laid out when combat drops, and a second fight clean. Mutation-checked when
written: stripping either card's own `Layout*`/`Ensure*` combat guards, or
not reading the combat state at login, each fail it. The last was a real
bug it found: the bar took a fight it was reloaded into for peace (no
PLAYER_REGEN_DISABLED fires on a reload) and faded mid-fight.

## `globals_lint.lua` — scoping

Dumps every GGET/GSET from the luajit bytecode of both files and reports any
global not on the allowed list — a local declared after its use compiles to
exactly that and reads nil at runtime.

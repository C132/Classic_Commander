# Commander_TopBar harness

One luajit harness, never loaded by the client. Run it from the AddOns root;
it finds the root from its own path, so it also runs from this folder or any
other directory, and exits non-zero on a single failed check.

```bash
/opt/homebrew/bin/luajit Commander_TopBar/Harness/topbar_orders_smoke.lua   # 210 checks
TOPBAR_RUNTIME=/path/copy.lua luajit .../topbar_orders_smoke.lua           # a mutated CommanderTopBar.lua
```

## topbar_orders_smoke.lua — the Commander Orders half (210 checks)

The coordinates segment takes a click and the optional Nav segment (2.2.0)
shows where the arrow is going; both are only as good as what Commander Orders
does with them. So the harness boots the REAL Orders (Data, Geo, Store, DB and
the runtime; the pins and the manager left out, as Orders' own runtime harness
does) over the shared client mock, `Commander_Orders/Harness/orders_mock.lua`,
with the real Commander_Events framework, and loads the Top Bar on top the way
the client would (OptionalDeps: Orders first). A run with Orders' Pins and UI
loaded too also passes.

- **A** loads clean beside Orders; the coordinates show (Orders' own reading,
  `CommanderOrders.Coords.Text`, at Coordinate Decimals: "42.0, 65.5") and
  take the mouse.
- **B** click = a waypoint where you stand (`CommanderOrders.Coords.Gesture`,
  source "user", pinned, deduplicated).
- **C** Shift-click = the spot shared in chat as Orders' readable line (solo
  /say, the party's or the raid's chat), and NO waypoint of your own;
  Ctrl-click = its `/way` line in Orders' copy box.
- **D** right-click = Orders' coordinate menu, whose "Open the manager" opens
  the waypoint manager.
- **E** the Nav segment, read from `CommanderOrders.Status()`: the arrow's own
  distance (582 yd, the D1 walk), an arrival time while walking, the
  other-landmass words, hidden with no target, refreshed by Orders' CHANGED
  within a second; a `|` in a title is escaped; opt-in (ShowNav off).
- **F** tooltips: Orders' coordinate card (the spot to a tenth, the gesture
  hints) and the arrow's line under it.
- **G** Orders switched off: a click says so, the Nav segment goes away.
- **H** combat changes nothing: the click works, nothing protected is called.
- **I** Orders not loaded at all: a click prints the /way line, nothing errors.
- **J** the settings page: the checkbox present, disabled without Orders.
- **K** globals: the Top Bar writes only its own and reads only what it means to.
- **L** the supply readouts (2.3.0): durability, bag slots and ammo take the
  mouse (over their text, with Orders' Go-to, Go from the Readouts on) and go
  to the nearest repair, vendor and ammo vendor through Orders' locator (a
  harness resolver stands in for Questie): one `GoTo` waypoint per readout
  under (TopBar, repair | vendor | ammo) that takes the arrow, worded by
  Orders; the hover card (where a click goes, "the arrow points here now",
  the gestures; the locator asked once per hover, never on the 1 s tick);
  Shift-click /say, Ctrl-click the copy box; nobody known says why; Orders
  off; the option off; combat; no surfaces without Orders.

Twelve hand-made mutants through TOPBAR_RUNTIME were all killed (one only
by failing to compile). 2.3.0 added seven more (the supply key, the option
gate, the arrow request, the Shift/Ctrl split, the tooltip tick refresh,
Orders' coordinate text, the vendor query), all killed.

2.3.0 (Commander Orders 3.1) changed what the coordinates do, so these
existing checks were edited, all forced by Orders' SPEC 1 gestures (Orders
DECISIONS D31) and precision, not by taste: A "at the player's spot" (now "42.0, 65.5", Orders'
Coordinate Decimals; the segment finder's first needle with it); C rewritten
(Shift-click shares in chat, solo to /say, instead of an addon message to
the group; Ctrl-click added); D (right-click opens the coordinate menu, and
the manager is its entry); F's three hint words (Orders' coordinate card);
K's read list gained `IsControlKeyDown` and `geterrorhandler`. After a change to Orders' public API, its R surface
or `orders_mock.lua`, run this beside Orders' own harnesses
(`Commander_Orders/Harness/README.md`).

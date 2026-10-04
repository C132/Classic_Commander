# Commander_TopBar harness

One luajit harness, never loaded by the client. Run it from the AddOns root;
it finds the root from its own path, so it also runs from this folder or any
other directory, and exits non-zero on a single failed check.

```bash
/opt/homebrew/bin/luajit Commander_TopBar/Harness/topbar_orders_smoke.lua   # 163 checks
TOPBAR_RUNTIME=/path/copy.lua luajit .../topbar_orders_smoke.lua           # a mutated CommanderTopBar.lua
```

## topbar_orders_smoke.lua — the Commander Orders half (163 checks)

The coordinates segment takes a click and the optional Nav segment (2.2.0)
shows where the arrow is going; both are only as good as what Commander Orders
does with them. So the harness boots the REAL Orders (Data, Geo, Store, DB and
the runtime; the pins and the manager left out, as Orders' own runtime harness
does) over the shared client mock, `Commander_Orders/Harness/orders_mock.lua`,
with the real Commander_Events framework, and loads the Top Bar on top the way
the client would (OptionalDeps: Orders first). A run with Orders' Pins and UI
loaded too also passes.

- **A** loads clean beside Orders; the coordinates show and take the mouse.
- **B** click = a waypoint where you stand (`CommanderOrders.Here`, source
  "user", pinned, deduplicated).
- **C** Shift-click = your position shared with the group through
  `CommanderOrders.SharePoint`, and NO waypoint of your own; solo it says why;
  the wire decodes to where you stand; the raid channel.
- **D** right-click = the waypoint manager.
- **E** the Nav segment, read from `CommanderOrders.Status()`: the arrow's own
  distance (582 yd, the D1 walk), an arrival time while walking, the
  other-landmass words, hidden with no target, refreshed by Orders' CHANGED
  within a second; a `|` in a title is escaped; opt-in (ShowNav off).
- **F** tooltips: the spot to a tenth, the arrow's line, the three hints.
- **G** Orders switched off: a click says so, the Nav segment goes away.
- **H** combat changes nothing: the click works, nothing protected is called.
- **I** Orders not loaded at all: a click prints the /way line, nothing errors.
- **J** the settings page: the checkbox present, disabled without Orders.
- **K** globals: the Top Bar writes only its own and reads only what it means to.

Twelve hand-made mutants through TOPBAR_RUNTIME were all killed (one only
by failing to compile). After a change to Orders' public API, its R surface
or `orders_mock.lua`, run this beside Orders' own harnesses
(`Commander_Orders/Harness/README.md`).

# Commander_Ping harness

One luajit harness, never loaded by the client. Run it from the AddOns root;
it finds the root from its own path, so it also runs from this folder or any
other directory, and exits non-zero on a single failed check.

```bash
/opt/homebrew/bin/luajit Commander_Ping/Harness/ping_orders_smoke.lua   # 242 checks
PING_RUNTIME=/path/copy.lua luajit .../ping_orders_smoke.lua           # a mutated CommanderPing.lua
```

## ping_orders_smoke.lua — the Commander Orders half (242 checks)

A minimap ping is an offset from the minimap's centre, and the only honest test
of turning it into a place is to put the place back on the minimap. So the
harness boots the REAL Commander Orders (its Geo owns the minimap yard table
and the forward placement its pins use) over the shared client mock,
`Commander_Orders/Harness/orders_mock.lua` (this build's real UiMap rows),
loads Commander Ping on top, fires MINIMAP_PING, follows the callout's
`[Waypoint]` link (an `addon:` hyperlink routed the way 2.5.6's
ItemRefHandlersShared.lua routes it, through EventRegistry's "SetItemRef"
callback), and checks every waypoint two ways: its world point against the
player's position plus the offset worked out by hand, and
`Geo.MinimapPlace(waypoint)` against the pixel the ping was drawn at (under
0.01 px over a grid).

- **A** loads clean beside Orders; the panel registers; nothing written but its own.
- **B** east, north, south-west: world yards = 2 x offset x radius, signs right.
- **C** every zoom outdoors and indoors, the indoor tie broken by IsIndoors,
  no SetZoom nudge.
- **D** a rotating minimap at four facings (the inverse of MinimapPlace's turn).
- **E** forward(inverse(ping)) == ping over a grid, rotating and not.
- **F** past the zone's edge: a neighbouring zone first (smallest), then the
  continent; Elwynn into Redridge, Silverpine into Undercity.
- **G** the 530 frame (Eversong): its own zone answers, across the border
  Ghostlands does, and off the coast nothing pretends to.
- **H** no position (inside an instance): a plain callout, no link, no waypoint.
- **I** the link: pinned on click, one Ping waypoint that each ping moves,
  session-only across a reload, too-old links refused, other addons' links
  ignored.
- **J** "Waypoint on Group Pings": automatic, temporary, never asks for the
  arrow: with nothing of yours it is followed as the closest, and it never
  takes the arrow from your pin, a running route, your closest mark or a
  Clear (Orders refuses a temporary pin only over a pinned waypoint, so an
  automatic ping that asked re-pinned the arrow in the other three cases).
- **K** Orders off or missing: the callout is the old one and nothing errors.
- **L** globals (static): the module writes only its own.

Twenty-three hand-made mutants through PING_RUNTIME: 22 killed, one equivalent
(an explicit `setArrow = true` on the clicked path, which pins through
`SetArrow` either way). The 23rd is the old automatic path asking for the
arrow (`setArrow = not explicit`): six J checks fail on it. After a change to Orders' Geo, public API or
`orders_mock.lua`, run this beside Orders' own harnesses.

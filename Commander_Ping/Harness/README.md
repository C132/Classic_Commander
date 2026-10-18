# Commander_Ping harness

One luajit harness, never loaded by the client. Run it from the AddOns root;
it finds the root from its own path, so it also runs from this folder or any
other directory, and exits non-zero on a single failed check.

```bash
/opt/homebrew/bin/luajit Commander_Ping/Harness/ping_orders_smoke.lua   # 300 checks
PING_RUNTIME=/path/copy.lua luajit .../ping_orders_smoke.lua           # a mutated CommanderPing.lua
```

## ping_orders_smoke.lua - the Commander Orders half (300 checks)

A minimap ping is an offset from the minimap's centre, and the only honest test
of turning it into a place is to put the place back on the minimap. So the
harness boots the REAL Commander Orders (its Geo owns the minimap yard table
and the forward placement its pins use) over the shared client mock,
`Commander_Orders/Harness/orders_mock.lua` (this build's real UiMap rows),
loads Commander Ping on top, fires MINIMAP_PING, follows the callout's
`[Go]` link (an `addon:` hyperlink routed the way 2.5.6's
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
  session-only across a reload, a link 25 pings old still moving it to its
  own spot, other addons' links ignored.
- **J** "Waypoint on Group Pings": automatic, temporary, never asks for the
  arrow: with nothing of yours it is followed as the closest, and it never
  takes the arrow from your pin, a running route, your closest mark or a
  Clear (Orders refuses a temporary pin over a pinned waypoint and over a
  running route, so an automatic ping that asked re-pinned the arrow away
  from your closest mark and out of a Clear).
- **K** Orders off or missing: the callout is the old one and nothing errors.
- **L** globals (static): the module writes only its own.
- **M** the Orders 3.1 fold-in: the callout's `[Go]` is
  `CommanderOrders.ChatLink`'s own link (the place rides in it), the only
  SetItemRef callback is Orders' chat file's, Ping claims the plain click
  (`CommanderOrders.ClaimChatLink`) so it moves the one Ping waypoint while
  Ctrl (copy box) and Right (menu, whose Go is Ping's) stay Orders', after a
  reload the old link is Orders' plain Go (a waypoint of yours there, never
  "too old"), and without Orders' chat file there is no link at all.
- **N** the Go-to migration (Orders 3.1 SPEC 5, Ping 2.3.0): the link reads
  `[Go]` (Orders' word for a chat link; "Waypoint" is only the noun), a click
  goes through `CommanderOrders.GoTo` and says Orders' "Waypoint set" line
  once (nothing with Orders' Announce off), Orders switched off between the
  ping and the click gives Orders' one refusal line in Orders' words and no
  line of Ping's, the automatic waypoint is silent, and (static) Ping keeps
  no refusal table and formats no `/way` line of its own.

The words follow Orders' DECISIONS (D31, the 3.1 "Go to" words and gestures):
`LastLink()`, `ClickLink()`, B's "carries a [Go] link" and M's "reading
[Go]" changed from `[Waypoint]` to `[Go]` for that wording change only.

Since the fold-in, `LastLink()` reads Orders' payload
(`addon:CommanderOrders:w:<map>:<x>:<y>:<title>`), and I's old check "a link
25 pings old says so" became "still moves the Ping waypoint to its own spot":
the SPEC's fold-in removed the 20-ping list that made a link too old. The
harness boots Orders with its chat file, so `CommanderOrdersChat.lua` answers
the clicks here.

Seven more mutants for the fold-in (no claim, a claim without Orders' chat
file, a claim that does not pin, a SetItemRef callback of Ping's own, another
title, another link text, the automatic waypoint lost): all killed.
Twenty-three hand-made mutants through PING_RUNTIME before it: 22 killed, one equivalent
(an explicit `setArrow = true` on the clicked path, which pins through
`SetArrow` either way). The 23rd is the old automatic path asking for the
arrow (`setArrow = not explicit`): six J checks fail on it. For the GoTo
migration: a clicked ping made silent (4 N checks), the old `[Waypoint]` word
(44 failures), the automatic waypoint pinned (7): all killed; looking Orders
up by `Add` instead of `GoTo` is equivalent (Orders 3.1 has both). After a
change to Orders' Geo, public API or `orders_mock.lua`, run this beside
Orders' own harnesses.

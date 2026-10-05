# Commander_Orders harnesses

Five luajit harnesses and one Python art check, none of them loaded by the
client (nothing here is in the TOC). Run them from the AddOns root; each one
also finds the root from its own path, so it works from `Harness/`, from any
other directory and from a git worktree. Every one exits non-zero on a single
failed check. Run all six before touching anything in the module:

```bash
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_geo_smoke.lua    # 679 checks (Geo alone, sealed)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_store_smoke.lua  # 569 checks (Store alone, sealed)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_harness.lua      # 779 checks (the runtime, end to end)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_pins_harness.lua # 523 checks (minimap + world map)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_ui_harness.lua   # 490 checks (the manager window)
python3 Commander_Orders/Harness/make_art.py --check                      # 8 textures x 4 rules = 32 checks
```

Then the suite's own settings smoke, because the settings page and the arrow's
HUD chrome are the framework's code:

```bash
/opt/homebrew/bin/luajit Commander_Events/Harness/settings_ui_smoke.lua    # 89 checks
```

And, after any change to the public API, the R surface or `orders_mock.lua`,
the consumers' contract harnesses, which boot the REAL Orders through this
folder's mock and drive it from the consumer's side:

```bash
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_orders_contract.lua  # 25 checks
/opt/homebrew/bin/luajit Commander_Recovery/Harness/recovery_orders_smoke.lua     # 54 checks
/opt/homebrew/bin/luajit Commander_TopBar/Harness/topbar_orders_smoke.lua         # 163 checks
/opt/homebrew/bin/luajit Commander_Ping/Harness/ping_orders_smoke.lua             # 242 checks
/opt/homebrew/bin/luajit Commander_Logistics/Harness/logistics_orders_smoke.lua   # 159 checks
```

`orders_mock.lua` is not a harness: it is the WoW client the runtime, pins,
manager and contract harnesses share (see "The mock" below).

---

## Mutation hooks

Each harness can run against a broken COPY of a file (the copy lives anywhere;
the live file is never touched), to prove a check bites:

```bash
ORDERS_GEO=/path/copy.lua   luajit .../orders_geo_smoke.lua    # a mutated Geo (also honoured by the mock)
CO_STORE=/path/copy.lua     luajit .../orders_store_smoke.lua  # a mutated Store
ORDERS_RUNTIME=/path/copy.lua luajit .../orders_harness.lua    # the mock loads the copy in the file's TOC slot;
ORDERS_DB=... ORDERS_DATA=... ORDERS_STORE=... ORDERS_GEO=...  #   likewise for the other Orders files,
ORDERS_PINS=... ORDERS_UI=...                                  #   and Pins/UI in every full-TOC boot
ORDERS_PINS=/path/copy.lua  luajit .../orders_pins_harness.lua # the pins harness loads that copy itself
ORDERS_UI=/path/copy.lua    luajit .../orders_ui_harness.lua   # the manager harness loads that copy itself
ORDERS_UI_PINS=1            luajit .../orders_ui_harness.lua   # the manager with the pins file loaded too
```

Mutation sweeps run while building (scripts in the session scratchpad, not
kept here): Geo about 35 hand-made mutants, all killed but one equivalent
(string.match for a plain find after FoldName strips every magic character);
Store 22, all killed but one equivalent (callbacks on the persist whitelist,
which copies scalars only); runtime 37, all killed but one equivalent (a
root:EnableMouse(false) that Arrow.UpdateMouse repeats at once); pins 58 of
58; manager 38 of 38. Integration added four more, all killed: the Store's
idle TARGET restored (store H); the arrow's distance created from a missing
outlined font, SharePoint ignoring `silent`, and Entrance handing out the
resolver's own table (runtime Q). The review's fixes added 30 more, all
killed: store 4 (a temporary pin over a route, the shared empty event list,
MarkReached's stamp, Claim on a keyed record), runtime 15 (one per fix in
section R), pins 8 (the drawer lift, the route's lift, the drawer watch,
the coordinates' level and anchor, the map notice, the wide badge, the top
strip) and manager 3 (the fit, the search let go, the raised dialog).
The second review's fixes were checked the same way, each new check failing
on the code before it: the whole running route lifted over QuestLog's
drawer (pins L, 6 failures), and a unit's position copied a tick (store F
and H, runtime R: 2 each).

---

## orders_geo_smoke.lua (679 checks)

`CommanderOrdersGeo.lua` ALONE in a SEALED environment: reading any global but
Lua's own libraries and `CommanderOrders` raises, and so does writing any
global but `CommanderOrders`, so a client call slipped into a code path fails
the run, not a grep. The world is this build's real UiMap and
UiMapAssignment DB2 rows (84 maps, 80 with world rectangles), driven through
modelled `GetWorldPosFromMapPos`, `GetMapRectOnMap`, `GetMapInfoAtPosition`
and `GetMapChildrenInfo`.

- **A** purity: the sealed load, the published API, nothing else written.
- **B** distance and bearing in all four quadrants and the four diagonals.
- **C** the D1 regression: Goldshire to Northshire on Elwynn's real rectangle
  is 582.4 yd at 339.0 deg; the transposed pairing is asserted to give 12,952.
- **D** relative angle and alignment: the wrap at +-pi, multiples of 2 pi.
- **E** landmass: the continent walk, caching, the 530 traps (Eversong vs
  Hellfire, the Ghostlands / Eastern Plaguelands seam), dungeons, battlegrounds.
- **F** ToWorld with vector and number envs, throwing envs, no world data.
- **G** projection round trips up, down and across siblings, world-exact.
- **H** ZoneAt: continent and world clicks, ocean, self, refusals, and a
  24x24 click grid on the Eastern Kingdoms, Kalimdor, Outland and Azeroth
  proving every answer keeps the click's world point.
- **I** minimap: the diameter table (outdoor zoom 3 = 266.67), radius, the
  indoor rule, round / square / corner placement, rotation, the 0.9 rim,
  edge angles.
- **J** the angle filter (no wrap jump, no overshoot) and the ETA filter
  (seed, reset on a new target, teleport, walking away, standing still).
- **K** every format: distance (yards, metres, AUTO), ETA, coordinates,
  /way lines, folded names.
- **L** the zone index and matcher: tiers, aliases, what is left out.
- **M** an 80-row /way grammar table, TomTom B12, B13, B18 and B23 fixed.
- **N** WayLine -> ParseWay round trips; plain ASCII everywhere.

## orders_store_smoke.lua (569 checks)

`CommanderOrdersStore.lua` alone, sealed the same way, over a FAKE world:
maps with a yard origin and a landmass tag, map 20 overlapping map 10's
coordinates on another landmass (the 530 trap). Geo is not loaded: the Store
only ever sees the functions its ctx hands it. Each section runs under pcall.

- **A** construction, validation, defaults, normalising.
- **B** dedup: same place, (source, key) moves, corpse and unit identity.
- **C** Find (tolerance), Get, Remove, RemoveBy, List, Clear, Update, onRemove;
  Claim (a keyless record changes owner, a keyed one or a stop never).
- **D** targeting: corpse > pinned > route > closest; temporary never steals
  a pin, nor a running route's arrow (moved offers and pings too); the
  dismissed arrow; MarkReached (the closest moves on).
- **E** closest: landmass, eligibility, tiers, hysteresis (20% AND 30 yd),
  the rescan throttle.
- **F** nearest-of-N alternatives with hysteresis; a unit's keyed position
  handed on as given, never copied (a positional one still read).
- **G** routes: ordered, nearest, landmass grouping, next / prev / reverse /
  optimise, add stop, replace by key, removal bookkeeping.
- **H** the arrival machine: NEAR / ARRIVED / DONE timing, the exit margin,
  taxis, the fresh-born rule, re-entry, clearOnArrive false, route advance
  and completion, a target that loses the arrow mid-hold, and an idle tick
  with no target emitting nothing; a quiet tick hands back the shared,
  read-only S.NO_EVENTS, ArrivalState reads without a copy, and 2000 quiet
  ticks allocate next to nothing; nor do 2000 ticks following a member on
  another landmass (measured with the JIT off: its trace recorder's own
  allocations are as large as the 160 B a tick looked for).
- **I** distance bands (the TomTom shim's callbacks): inward crossings only.
- **J** Serialize / Load: plain data only, the 16-digit round trip, counters,
  tolerant matching afterwards, garbage in.
- **K** the sealed environment saw nothing it should not have.

## orders_harness.lua (779 checks)

The RUNTIME end to end over `orders_mock.lua`, with the real
`CommanderSettingsUI.lua` and `CommanderEvents.lua` loaded and every Orders
file in TOC order except Pins and UI (their harnesses load them; section P
loads the full TOC). Each section boots a fresh client.

- **A** boot: a quiet login, the public API, the globals written, TOC,
  bindings, defaults, the arrow built and chromed out of combat, asleep with
  nothing to do.
- **B** the D1 regression through the real UnitPosition axis order (582 yd at
  339 deg, not 12,952); colours, turn around, smoothing, every-frame
  rotation, the ETA, text written only on change.
- **C** arrival: the NEAR pulse, ARRIVED (ring, text, one chime), DONE clears,
  in flight never arrives, /wayb never clears under your feet.
- **D** states: OTHER LANDMASS with Horde and Alliance hints and Guide me, the
  530 traps, dungeon targets with a resolver and with C_EncounterJournal's
  list, NO POSITION, no heading, group members, the auto-hide options, the
  combat layout unchanged by default.
- **E** the mouse: click-through when locked, the modifier, the menu,
  unlock / lock, a login in combat that waits to chrome.
- **F** the API: refusals while disabled (and no TomTom global for Questie
  while Orders is off), nil-safety, copies, source defaults, the debounced
  CHANGED event, continent points stored on the zone.
- **G** the legacy wrappers: IssueOrder, ClearOrder, Rally*.
- **H** the TomTom shim: install rules, Questie's exact TrackerUtils and
  QuestieFrame patterns (a stale uid after a reload, a one-bit-off copy),
  WhatsTraining's dedup, callbacks, tier 2, tier 3 absent, refusals.
- **I** /way end to end, /wayb, /cway, /corder way with its case kept.
- **J** sharing: send, channels, result enum, receive, the prompt, self-echo,
  auto-add, the throttle, TomTom's prefix, garbage.
- **K** the v2 -> v3 migration; Restore Defaults keeps places.
- **L** persistence across a simulated reload (the uid counter continues).
- **M** the corpse run: release, reload as a ghost, resurrection, Feign Death,
  battlegrounds, a dungeon death pointing at the entrance, arrival.
- **N** the settings page on the real framework.
- **O** the driver sleeps; places, paste / export, routes on the arrow,
  bindings.
- **P** every TOC file that exists loads with the runtime.
- **Q** what the consumers asked for: Entrance (resolvers first, a copy,
  a raising resolver passed over), Status (the arrow's own words, nil for a
  removed target), SharePoint (shared, never added or pinned, one send path
  with Share), OpenPaste(text); and the arrow's distance font on a client
  without `GameFontNormalLargeOutline`.
- **R** the review's fixes, each check naming the lens that found it: the
  shim never removes a waypoint it does not own (the user's /way and an
  accepted share, either order; a user re-add claims it, a consumer's does
  not) and finds a continent uid (Blackrock Mountain on 1415) after a
  reload; received titles lose their UI escapes on both wires; the share,
  copy and clear-all dialogs draw over the maximized map; a share added
  without "go" stays behind your own waypoints in Follow the Closest; Mark
  arrived on a kept mark moves the arrow on; a temporary offer leaves a
  running route; Guide me hands back through a portal, on removal, on Mark
  arrived, and lets go when you pick something else; a unit follow costs
  about one map position a second (the player's) and no copies of the
  arrival state, on another landmass hands the Store's position on as one
  reused table, and with UnitPosition blind (the map position kept) does no
  world-position lookup a frame; the status line wraps at the arrow's width; a closed
  Window-style arrow is not re-shown every pass and Reset Position reopens
  it; Status, WayLine, Share, `/corder arrow` and the tooltip at the chosen
  spawn; Import numbers lines as the box does.

## orders_pins_harness.lua (523 checks)

`CommanderOrdersPins.lua` over the mock with the real runtime, Geo and Store;
the manager is left out so this answers for the pins alone. The harness
extends the widget metatable to record Line anchors, thickness and
`Minimap:GetChildren`.

- **A** load: the hooks, no new global, nothing assigned to WorldMapFrame,
  the unsecured pool and provider, the overlay with its pass-through set once.
- **B** minimap: a pin for every waypoint on the player's landmass and none for
  the rest (the 530 traps, a followed unit, teleports inside 530 caught on the
  same frame), unnamed, above Commander_Radar's overlay.
- **C** placement: round, square, CORNER-*, rotated, the edge clamp and edge
  angle, zoom levels, indoor / outdoor with the IsIndoors tie-break and no
  SetZoom nudge, Minimap size, per-frame movement only while pins show, a taxi
  is not a teleport, MinimapEdge / MinimapPins off; on a square map the top
  rim rides 22 units under the edge (Commander_Minimap's zone name), the
  bottom rim untouched.
- **D** minimap pins: tooltip, Shift-click, plain click, right-click menu,
  the arrow's target ringed, the corpse art.
- **E** world map: zone, continent (the Eversong 530 sub-rectangle), Azeroth,
  Outland and Durotar projection against world-derived positions, levels above
  Questie's and below the party dots, AcquirePin's mouse wiring (OnMouseUp,
  OnMouseDown, OnEnter), alternatives, corpse, reached, a source's tint from
  `Data.SOURCE_ICONS`, refresh while open, WorldPins / EnableOrders off.
- **F** routes: numbered badges, lines at canvas coordinates, a walked leg
  dimmed, a loop, cross-landmass legs left out, RouteLines off, no CreateLine,
  a Line that refuses its colour (one report, then off).
- **G** world-pin clicks: click, menu, Shift-drag on a zone and on a continent
  (ZoneAt), a change during a drag deferred, a press that never moves is a
  click, an ocean drop refused without a stray click.
- **H** the map-click overlay: show / hide on the exact modifier; zone,
  continent, ocean, Azeroth, Cosmic and dungeon clicks; ALT / SHIFT / OFF;
  closing the map; Orders off; a login in combat; never re-applied in combat.
- **I** coordinates: both lines for the viewed map, the 0.1 s throttle with
  writes only on change, windowed mode, Questie's own coordinates (read
  only), MapCoords off, the frame level.
- **J** reload.
- **K** the real `Commander_Minimap/CommanderMinimap.lua`: GetMinimapShape is
  SQUARE once its mask is on, its button tidy never fades an Orders pin, pins
  clamp to the square (the top under its zone name).
- **L** Commander_QuestLog's drawer, built from QuestLog's own OnShow hook:
  the arrow's target over it, alone (the running route's other badges stay
  under it, and the next stop takes the target's place), everything else
  under it, back down when it folds; the coordinates one level under it;
  refusals said on the map (over the drawer, faded after three seconds,
  cleared with the map) as well as in chat; two-digit minimap badges; "Copy
  /way line" from a pin's menu over the maximized map.

## orders_ui_harness.lua (490 checks)

`CommanderOrdersUI.lua` over the mock with every other Orders file; the
manager file is loaded by the harness itself, last, in its TOC slot (so
`ORDERS_UI` can swap in a copy), and the pins only with `ORDERS_UI_PINS=1`.

- **A** load: nothing built, nothing printed, no global at load, the O.UI
  surface the runtime calls, plain ASCII.
- **B** open and close: the stone sheet, Esc, toggle by binding and /corder,
  no keyboard focus on open, every box autoFocus off, position and scale kept
  across a reload, refused while Orders is off, combat-safe.
- **C** the list: Arrow / Routes / by zone, the player's zone first, rows
  (tint, title, zone, distance, source tag), a source's tint and name from
  `Data.SOURCE_ICONS` / `SOURCE_WORDS`, stops under their route, grouping by
  who set it, folding, corpse and group members.
- **D** live distance: 1 Hz while open, written only on change, rows never
  reorder, nothing while hidden, the arrow's ETA.
- **E** every waypoint action: Set as arrow, Rename (Enter, Escape, cleared,
  committed on leaving, never clobbered by a refresh), Share, Copy /way,
  Remove, double-click, right-click.
- **F** every route action: Start, Previous, Next (at the end), Reverse,
  Optimise order, Export, Remove route, fold on a second click.
- **G** the toolbar: Add here (and with no position), Clear... by reached,
  by source and everything.
- **H** search: title, zone, source, route stops, nothing found, Escape.
- **I** paste: with and without /way, comma decimals, #map ids, bad lines by
  the box's own number (blank lines count) with how they start, as many as
  the result box holds with the count of the rest, routes in order and
  nearest first, Ctrl+Enter, export with nil titles, saved pages.
- **J** places: mark, rename, go there, copy, other faction, search, remove
  (confirmed over the maximized map, safe when the list moved).
- **K** entry points: Open(uid) on a folded stop, Open(uid) letting go of a
  search its waypoint fails, Open(routeId), the arrow's click, CHANGED while
  open and while hidden, disabling Orders.
- **L** hygiene: the named globals, D11 (no byte above 127 in any text), no
  "nil" in any text, no protected call.

## make_art.py (32 checks)

Regenerates the eight textures in `Textures/` (stdlib only: zlib + struct,
RGBA8, power-of-two sizes, 4x4 supersampling) and asserts, on the rendered
buffer and again on the PNG decoded back from disk, four rules per texture:
the size is a power of two, it decodes at that size, every pixel with alpha
lies inside r <= side/2 - 2 measured to the pixel's FAR corner, and the outer
two rows and columns are fully transparent.

```bash
python3 Commander_Orders/Harness/make_art.py              # regenerate and verify
python3 Commander_Orders/Harness/make_art.py --check      # verify what is on disk
python3 Commander_Orders/Harness/make_art.py --contact out.png   # a review sheet
```

New or changed PNGs need a full client restart; `/reload` does not load them.

---

## The mock (orders_mock.lua)

A WoW 2.5.6 client modelled on Blizzard's own UI source and this build's DB2
rows. `M.Boot(opts)` is a fresh process as far as the addon can tell: every
global written since the mock loaded is removed, the client rebuilt, the real
`Commander_Events` settings framework and HUD chrome loaded, then the Orders
files in TOC order. `M.Reload(opts)` writes the saved variables the way the
client's writer does (16 significant digits, functions and userdata dropped)
and boots again with them, which is what makes a /reload testable. Its full
API is documented at the top of the file; the parts other harnesses rely on:

- **Boot options:** `saved`, `loaded` (what `C_AddOns.IsAddOnLoaded` answers),
  `before(M, W)` (after the client is installed, before any file; globals are
  served through `_G`'s `__index`, so `rawset(_G, name, false)` hides one),
  `afterFiles(M, W)`, `combat`, `player`, `faction`, `files`, `skipFiles`.
- **Time and events:** `M.Advance(seconds)`, `M.Frame(dt)`, `M.Fire(event, ...)`.
- **The world:** `M.SetPlayer`, `M.SetPlayerWorld`, `M.SetFacing`,
  `M.SetSpeed`, `M.SetTaxi`, `M.SetIndoors`, `M.SetNoPosition`, `M.SetLife`,
  `M.SetInstance`, `M.SetCombat`, `M.SetModifier`, `M.SetGroup`, `M.SetUnit`,
  `M.SetUnitNoWorld` (UnitPosition blind for one member, its map position
  kept), `M.SetCorpse`, `M.SetEntrances`, `M.SetMinimapShape`, `M.SetZoom`,
  `M.Receive`, `M.World`, `M.MapPos`, `W.cvars`, `W.sendResult`.
- **The world map:** a WorldMapFrame PROXY that records every field write (only
  `pinPools` keys and hooks are allowed), Blizzard's AcquirePin order and mouse
  wiring (OnMouseUp calls `pin:OnMouseUp(button)` and then `pin:OnClick` only
  when the release is inside; OnMouseDown is the mixin's own), 2.5.6's secure
  `CreateFramePool` proxy beside `CreateUnsecuredRegionPoolInstance`.
- **What came out:** `M.prints`, `M.errors`, `M.sounds`, `M.sent`, `M.chat`,
  `M.popups`, `M.menu`, `M.tooltip`, `M.blocked` (protected calls refused in
  combat), `M.writes` (every new global), `M.loadErrors`; `M.Click`, `M.Hover`,
  `M.ClickMenu`, `M.ClickPopup`.
- **Fidelity points that have caught bugs:** `FontString:SetText` raises with
  no font set; `SetPassThroughButtons` is refused in combat without an error;
  frames update only while they and every parent are shown;
  `StaticPopup_Show` parents the dialog to UIParent at DIALOG strata before
  its OnShow (StaticPopup_SetUpPosition), and `M.SetMapMaximized(true)` puts
  the map at FULLSCREEN (TBC's SynchronizeDisplayState), compared with
  `M.StrataOver`; `SetWordWrap` / `SetMaxLines` are recorded.

The consumers' contract harnesses (QuestLog, Recovery, TopBar, Ping,
Logistics) load it with `dofile` and use `M.Boot{ files, skipFiles, player,
saved, before, afterFiles }`, `M.Fire`, `M.Advance`, `M.Click`, `M.Hover`,
`M.World`, the setters above, `M.W.cvars / .mods / .minimap / .widgets`,
`M.sent / prints / tooltip / blocked / writes / errors / loadErrors`,
`M.Reload` and `CommanderOrders.R.View()`. Keep those stable, or run the five
contract harnesses after changing them. Boot fires `ADDON_LOADED` only for
`Commander_Events` and `Commander_Orders`; a consumer loaded on top registers
for Orders' `ADDON_LOADED` from a hook frame (see
`recovery_orders_smoke.lua`) until the mock grows an `opts.addons` list.

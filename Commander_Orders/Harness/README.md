# Commander_Orders harnesses

Eight luajit harnesses and two Python checks, none of them loaded by the
client (nothing here is in the TOC). Run them from the AddOns root; each one
also finds the root from its own path, so it works from `Harness/`, from any
other directory and from a git worktree. Every one exits non-zero on a single
failed check. Run all of them before touching anything in the module:

```bash
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_geo_smoke.lua     # 728 checks (Geo alone, sealed)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_store_smoke.lua   # 614 checks (Store alone, sealed)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_harness.lua       # 996 checks (the runtime, end to end)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_pins_harness.lua  # 561 checks (minimap + world map)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_ui_harness.lua    # 514 checks (the manager window)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_coords_harness.lua # 392 checks (the coordinates, 3.1)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_chat_harness.lua  # 648 checks (chat links, 3.1)
/opt/homebrew/bin/luajit Commander_Orders/Harness/orders_locate_smoke.lua  # 487 checks (the locator, 3.1; see below)
python3 Commander_Orders/Harness/make_art.py --check                       # 8 textures x 4 rules = 32 checks
COMMANDER_DB2=<dir> python3 Commander_Orders/Harness/make_entrances.py --check  # the door table is current
```

`orders_locate_smoke.lua` counts 339 checks on the committed fixture, 148
more when the session's real-Questie boot tooling is present (it SKIPS
cleanly otherwise), and one more with `COMMANDER_DB2` set (it re-runs the
generator's `--check`). `make_entrances.py --check` exits 2 when an input is
missing: `AreaTrigger.csv` is not in the Quartermaster cache, so it needs
`--fetch --db2 DIR` once (below).

Then the suite's own harnesses in Commander_Events, because the settings page,
the HUD chrome and the Go button are the framework's code:

```bash
/opt/homebrew/bin/luajit Commander_Events/Harness/settings_ui_smoke.lua    # 89 checks
/opt/homebrew/bin/luajit Commander_Events/Harness/gobutton_smoke.lua       # 99 checks (Commander.UI.GoButton, 3.1)
/opt/homebrew/bin/luajit Commander_Events/Harness/health_smoke.lua         # 41 checks
```

And, after any change to the public API, the R surface, the Go button or
`orders_mock.lua`, the consumers' contract harnesses, which boot the REAL
Orders through this folder's mock (or the real Go button over the module's
own mock) and drive it from the consumer's side:

```bash
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_orders_contract.lua  # 60 checks
/opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_goto_harness.lua     # 72 checks
/opt/homebrew/bin/luajit Commander_Recovery/Harness/recovery_orders_smoke.lua     # 68 checks
/opt/homebrew/bin/luajit Commander_Guide/Harness/guide_orders_smoke.lua           # 81 checks
/opt/homebrew/bin/luajit Commander_TopBar/Harness/topbar_orders_smoke.lua         # 210 checks
/opt/homebrew/bin/luajit Commander_Ping/Harness/ping_orders_smoke.lua             # 300 checks
/opt/homebrew/bin/luajit Commander_Logistics/Harness/logistics_orders_smoke.lua   # 236 checks
/opt/homebrew/bin/luajit Commander_Adjutant/Harness/adjutant_queue_smoke.lua      # 106 checks (stub Logistics)
/opt/homebrew/bin/luajit Commander_Oracle/Harness/oracle_orders_smoke.lua         # 120 checks
/opt/homebrew/bin/luajit Commander_Notebook/Harness/notebook_orders_smoke.lua     # 55 checks
/opt/homebrew/bin/luajit Commander_Chat/Harness/chat_orders_smoke.lua             # 25 checks (the [Go] hover card)
/opt/homebrew/bin/luajit Commander_Spoils/Harness/spoils_orders_smoke.lua         # 92 checks
/opt/homebrew/bin/luajit Commander_Contacts/Harness/contacts_orders_smoke.lua     # 34 checks
/opt/homebrew/bin/luajit Commander_Bags/Harness/bags_orders_smoke.lua             # 33 checks
/opt/homebrew/bin/luajit Commander_Vitals/Harness/vitals_orders_smoke.lua         # 29 checks
/opt/homebrew/bin/luajit Commander_Objectives/Harness/objectives_orders_smoke.lua # 42 checks
/opt/homebrew/bin/luajit Commander_Promotion/Harness/promotion_orders_smoke.lua   # 46 checks
/opt/homebrew/bin/luajit Commander_Minimap/Harness/minimap_coords_harness.lua     # 51 checks (sandbox)
```

Every other harness of a module with a Go (the coverage table at the end)
loads the Go button or a recording Orders stand-in and must pass too; each
module's own Harness/README lists them. Comms and PartyFrames have READMEs
of their own since 3.1.

`orders_mock.lua` is not a harness: it is the WoW client the runtime, pins,
manager, coordinates, chat, locator and contract harnesses share (see "The
mock" below). `fake_questiedb.lua` is the locator's committed QuestieDB /
Questie fixture: real rows from the installed QuestieDB, four marked
synthetic, and the real public surface.

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
ORDERS_COORDS=/path/copy.lua luajit .../orders_coords_harness.lua  # a mutated CommanderOrdersCoords.lua
MINIMAP_FILE=/path/copy.lua  luajit .../orders_coords_harness.lua  # a mutated CommanderMinimap.lua (G, H)
ORDERS_CHAT=/path/copy.lua   luajit .../orders_chat_harness.lua    # a mutated CommanderOrdersChat.lua
ORDERS_LOCATE=/path/copy.lua luajit .../orders_locate_smoke.lua    # a mutated CommanderOrdersLocate.lua
ORDERS_REALDATA_BOOT=<boot.lua> luajit .../orders_locate_smoke.lua # where section R's real-Questie boot lives
ORDERS_GOBUTTON=/path/copy.lua  luajit Commander_Events/Harness/gobutton_smoke.lua  # the mock loads that
                                                                   #   Go button in every boot
```

The consumers' harnesses carry hooks of their own (CQL_ADAPTER, GUIDE_RUNTIME,
PING_RUNTIME, ORACLE_RUNTIME, SPOILS_RUNTIME, CONTACTS_UI, ARMORY_UI, VAULT_UI,
BAGS_DB, VITALS_RUNTIME, OBJECTIVES_RUNTIME, PROMOTION_RUNTIME, COMMS_RUNTIME,
...): see each module's Harness/README.

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

3.1's sweeps, all killed unless noted: the runtime 14, the Store 11, Geo 6
(the new API and the core fixes); the locator 29; the coordinates 53 over
Coords, Pins and Commander_Minimap, and 9 over the minimap sandbox; the chat
file 41, 40 killed and one equivalent (pair values over 100: Geo.ChatLink
refuses x > 1 itself); Ping's link fold-in 7; the Go button 5 (integration:
the query's own title in the tooltip, a spec function's reason, the late
listener, the reason dropped by Value, Listen not asked by Refresh). Each
consumer's sweep is in its own README.

The 3.1 review's fixes (2026-10-05) were checked the same way: 22 mutants,
one per fix, all killed. The runtime 13 (the capital folded into its zone;
the resolver asked before the door table; no door standing in for you inside
an instance; no island beside the landmass; the island's winner mixed with
mainland choices; PlaceFor naming a far townsfolk; a query measured twice; a
Vector2D pair a place; ties broken by float noise; a continent map's two
frames given one landmass; the corpse with one door; the guide link not
restored, not recorded), the Store 2 (the guided target
not kept, guideFor not persisted), the settings 1 (the block on by default),
the coordinates 2 (the old spot on the quest tracker, the minimap's menu not
offering the block), the chat file 2 (OpenWorldMap, no ToggleWorldMap) and the
Go button 2 (no motion scripts while disabled, an enabled query's lookup
reason dropped).

The second review's fixes (review-r2) likewise: the runtime 4, all killed
(Go.Origin without the instance-id door: 6 failures in K, 3 in R; the death
not recording its instance id: 5; the corpse not looked up by it: 4; the
corpse named by a zone map that found no door: 1), and
one equivalent (dropping the dungeon-or-raid gate on the id: the door table
holds only dungeons and raids, so a battleground's or a continent's id finds
no door either way); the Go button 2, both killed (the module's line kept
under Orders' state: 3 failures; left out for every reason: 1).

---

## orders_geo_smoke.lua (728 checks)

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
- **O** (3.1) islands (Teldrassil's key, its maps and the shore's), Geo.Zone
  (dungeon, micro and orphan maps climb to their zone; continents have none),
  PlainText, ChatText (never starting with "/", the 255-byte cap, the title cut
  first), ChatLink / ParseChatLink (the escapes, a 200-link round trip within
  5e-5, other links refused).

## orders_store_smoke.lua (606 checks)

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
- **L** (3.1) persistence of the pinned record and the active route (D33:
  a temporary offer and a unit follow excluded, kept records still
  session-only after the load); a pinned "Guide me" hop keeps the record its
  `guideFor` names, and the link (never a unit follow); Follow the Closest's
  zone scope, "mine only" and `anyOwner`; `Retarget`.

## orders_harness.lua (996 checks)

The RUNTIME end to end over `orders_mock.lua`, with the real
`CommanderSettingsUI.lua`, `CommanderGoButton.lua` and `CommanderEvents.lua`
loaded and every Orders file in TOC order except Pins, UI and Locate (their
harnesses load them; the locator's door table would answer entrances that D
and Q expect to be unknown; sections P and S24 load the full TOC). Section S
boots without Locate, Coords and Chat too, so it answers for the runtime
alone. Each section boots a fresh client.

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
- **Q** what the consumers asked for: Entrance (with no door table loaded,
  the resolvers; a copy; a raising resolver passed over), Status (the arrow's own words, nil for a
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
  arrived, and lets go when you pick something else, and after a /reload
  still does (the hop's `guideFor` and its session-only target kept: review
  core); a unit follow costs
  about one map position a second (the player's) and no copies of the
  arrival state, on another landmass hands the Store's position on as one
  reused table, and with UnitPosition blind (the map position kept) does no
  world-position lookup a frame; the status line wraps at the arrow's width; a closed
  Window-style arrow is not re-shown every pass and Reset Position reopens
  it; Status, WayLine, Share, `/corder arrow` and the tooltip at the chosen
  spawn; Import numbers lines as the box does.
- **S** (3.1, SPEC 1-2) S1 the API; S2 the words for a place; S3 one refusal
  vocabulary; S4 the copy box; S5 GoTo a place; S6 a refusal while off (one
  line with the place and its link); S7 a query before the locator; S8 many
  places, one waypoint; S9 IsGoing answers for a route's owner; S10 Update
  through Add's checks; S11 the pinned Go and the active route across a
  reload; S12 the battleground hedge; S13 the closest scope; S14 a unit
  follow by GUID (S13 also: a capital is part of the zone around it,
  Stormwind City and Elwynn either way, Westfall still not); S15 shares stack, chat through C_ChatInfo, no inbox; S16
  an Orphan map's hint; S17 the nearest departure; S18 Teldrassil's island;
  S19 the menus; S20 typed coordinates; S21 the settings of the round and
  the MapCoords repair (CoordsBlock now defaults off); S22 doors by instance
  id, the door table over a registered resolver, which answers what the
  table lacks; S23
  the mock's 3.1 surface; S24 the full TOC with every 3.1 file.

## orders_pins_harness.lua (561 checks)

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
- (3.1) **I** gained World Map Coordinates AUTO / ON / OFF (a dungeon
  included) and Coordinate Decimals; **E** M7, every spawn pin naming its own
  spot and distance (the others never claim the arrow) and the minimap card
  naming the followed spawn; **C** the top strip under Minimap Coordinates
  (38, the old 48 still asserted with the label off).
- **L** Commander_QuestLog's drawer, built from QuestLog's own OnShow hook:
  the arrow's target over it, alone (the running route's other badges stay
  under it, and the next stop takes the target's place), everything else
  under it, back down when it folds; the coordinates one level under it;
  refusals said on the map (over the drawer, faded after three seconds,
  cleared with the map) as well as in chat; two-digit minimap badges; "Copy
  /way line" from a pin's menu over the maximized map.

## orders_ui_harness.lua (514 checks)

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
- **M** (3.1, S8) "Add at..." and "Move..." through the typed-coordinates box,
  "Save as place", the row menu's new entries.

## orders_coords_harness.lua (392 checks, 3.1)

`CommanderOrdersCoords.lua` over the mock with the real settings framework
and HUD chrome, the runtime, Geo, Store and pins, and in G and H the REAL
`Commander_Minimap/CommanderMinimap.lua`, loaded before Orders as the client
loads it. The manager, the chat links and the locator are left out.

- **A** load: `CommanderOrders.Coords`, the block built at login, unnamed, no
  new global, a quiet login; OFF by default (the lead's decision, D39: the
  minimap's coordinates default on and their menu offers the block), a
  saved true kept; the Solid plate under the Orders arrow's default box, out
  of the quest tracker's right column (review: render); the click surface
  under the drag overlay; a login in combat waits to chrome. Every other
  section boots with a saved settings table that turned the block on.
- **B** reading: zone numbers from UnitPosition with no Vector2D (no map
  position asked in ten seconds, two world probes per map), a cave's map
  climbs to its zone, an other-instance map refused, "--", the battleground
  hedge, the taxi, the 0.2 s throttle and write-on-change, decimals 0..2.
- **C** the block's words and size: subzone over zone, the zone alone, the
  unlocked block, zone events, D11.
- **D** gestures: click, Shift (into the chat box, else posted), Ctrl, Right
  and every menu entry, the tooltip, no position, Orders off.
- **E** settings and chrome; combat changes and refuses nothing.
- **F** `/corder coords` through the real slash wrapper.
- **G** Commander_Minimap's label: under the zone name, written on change,
  hidden by its switch or with Orders off, its click surface over the text.
- **H** Ctrl+Right-click on the minimap: no ping; every other click pings as
  before; the placement round trip against Geo.MinimapPlace (north up,
  rotated, zoom, indoors, scale 1.37 and 1); square corners vs round; outside
  the face; Elwynn's edge to Duskwood, Eversong to Ghostlands (530); an
  instance; the switches; Orders raising.

## orders_chat_harness.lua (648 checks, 3.1)

The REAL Orders with `CommanderOrdersChat.lua` on top, fed chat lines the way
ChatFrameFilters.lua does (the mock runs ChatFrameUtil's filter chain the
2.5.6 way and routes addon links SetItemRef -> EventRegistry).

- **A** loads clean: no global, one filter per event, the callbacks under an
  owner table of its own.
- **B** plain-text stretches: links, colours, textures, {...} skipped.
- **C** tier A, /way lines: every spelling, a bare /way's context (yours, a
  group member's, nearby, nobody's), refusals, punctuation.
- **D** tier B, "Zone x, y": exact names and long aliases only; times, money,
  ranges, percents, decimal commas and bare pairs never linked.
- **E** Orders' own shared line: ONE link, the title back, every precision.
- **F** the filter's contract: fourteen arguments, a bare false, the lineID
  cache, the switches, errors contained.
- **G** Blizzard's formatting after the filters (simulated) leaves the link.
- **H** the click: Go, Ctrl, Shift (typed or posted), Right and every entry;
  other links ignored; a refused Go's own printed link. The mock's world map
  is 2.5.6's: `OpenWorldMap` raises (HandleUserActionOpenSelf is a Wrath
  method), so "Open the map here" must go through ToggleWorldMap and
  SetMapID (review: blizzard).
- **I** hover, and only our own tooltip hidden on leave.
- **J** ClaimChatLink: 64 kept, newest wins, errors contained, gone after a
  reload. **K** Linkify. **L** globals (static). **M** the full TOC.

## orders_locate_smoke.lua (487 checks, 3.1)

`CommanderOrdersLocate.lua` and the generated door table over the mock, with
`fake_questiedb.lua` installed before the files load.

- **A** boot: the real Locate replaces the stand-in, the hooks, no global, a
  client with no Questie at all.
- **B** the door table: shape, every spot valid and on a zone, the keys, spot
  checks against the generator's sources (and its `--check` with
  `COMMANDER_DB2`).
- **C** doors by uiMap, instance and areaId; approaches; several doors; the
  world-position fallback; Entrance()'s order; the arrow's dungeon hint.
- **D** npc and object queries; instance-only NPCs answer their doors.
- **E** townsfolk: every kind, aliases, faction filter, blacklist, otherside,
  class and profession trainers, the vendor lists and their union, caching.
- **F** Questie's states (Stage 0 / 1 / 3, QuestieDB alone, nothing, a
  contract mismatch, a broken Townsfolk), the ready hook, the pre-warm (never
  in combat).
- **G** items: itemVendor, itemSource. **H** registered resolvers (townsfolk
  merge, npc first, a raising one, the runtime's kinds untouched). **I** GoTo,
  PlaceFor, IsGoing and a GoButton with a query. **J** robustness.
- **K** the 3.1 review's fixes: inside Serpentshrine (no UnitPosition) the
  door stands in for you and the list is sorted before the 256 cap (the
  smith by the door is the 260th in the locator's order), and walking out
  the arrow is on him; no position, or an instance with no door: no nearest
  townsfolk named; a nearest-of-300 PlaceFor costs two world probes per map
  and one measuring pass; ties keep the list's order; a continent map's
  two frames (Quel'Thalas, 530) told apart; Darnassus' bank from
  Auberdine (the island beside the landmass), its choices the island's
  alone; PlaceFor's "elsewhere" from Honor Hold (a named NPC flagged
  instead); a death in Karazhan carries both doors. Review-r2: inside
  Magisters' Terrace, which has no uiMap on 2.5.6 (`M.SetNoMap`), the
  instance id (`M.SetInstance("party", 585)`, GetInstanceInfo's 8th) finds
  the door: the Isle's smith, 260th in the locator's order, is the Go, and
  out of the door a straight arrow; with no id, the old "instance" answer;
  a death in there is remembered by the id and the ghost's arrow goes to
  its door; and should the client answer the Isle's zone map in there, the
  id still finds the door, the corpse named by the door, not the zone.
- **R** the REAL Questie 12.0.3 / QuestieDB 1.0.4 booted inside the mock in a
  child process per faction (148 checks; review-r2: inside Magisters'
  Terrace a Repair and a Vendor Go keep Smith Hauthaa and Sereth
  Duskbringer); SKIPS cleanly without the session's boot tooling (339
  checks then).

## make_entrances.py (the door table)

```bash
python3 Commander_Orders/Harness/make_entrances.py --fetch --db2 DIR --check  # download the 5 DB2 CSVs (build
                                                                              #   2.5.6.69795) into DIR, then check
python3 Commander_Orders/Harness/make_entrances.py --db2 DIR --check   # 0 current, 1 differs, 2 an input is missing
python3 Commander_Orders/Harness/make_entrances.py --db2 DIR           # regenerate CommanderOrdersEntrances.lua
```

Inputs: the client's AreaTrigger, Map, UiMap, UiMapAssignment and AreaPOI
DB2s (wago.tools; it sends a curl User-Agent, urllib's gets a 403), the
CMaNGOS TBC world dump in the Quartermaster cache (`tbcdb.sql.gz`), and the
installed QuestieDB (dungeons.lua and the zone tables; regenerating without
it exits 2). `--db2` defaults to `$COMMANDER_DB2`, else
`Commander_Quartermaster/Harness/.cache` (git-ignored). It never writes
bytecode into Formulary's folder (it borrows Formulary's boundary rule).

## Commander_Events/Harness/gobutton_smoke.lua (99 checks, 3.1)

`Commander.UI.GoButton` over this mock: **A** the file alone (only
`Commander` written, its TOC slot); **B** with Orders (click = GoTo under
(source, key), lit "Going" and its refresh on CHANGED and OnShow, Shift and
Ctrl, the tooltip, greyed while off or with no place, a query through
Locate, onGo); **C** without Orders (a spec prints its /way line, a query
greys out); **D** hygiene; **E** integration (a query's own list title in
the tooltip, a spec or query function's `nil, reason`, a button made before
Orders loaded still hearing CHANGED; review: a greyed button runs its
motion scripts while disabled, so its red reason shows, and takes no click;
an enabled query whose lookup answers nothing says why in red, with no
"Go to:" line and no click hints; review-r2: greyed by Orders' own state,
turned off (B), absent for a query (C) or loading (E), the module's extra
line is left out, since it says what a press does, and a reason of the
spec's own keeps it (E)).

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
  `afterFiles(M, W)`, `combat`, `player`, `faction`, `files`, `skipFiles`,
  and (3.1) `addons`: consumer addons loaded after Orders' files, each by
  name (its TOC's .lua files that exist) or `{ name, files }`, with
  `ADDON_LOADED` fired for each after Orders'.
- **Time and events:** `M.Advance(seconds)`, `M.Frame(dt)`, `M.Fire(event, ...)`.
- **The world:** `M.SetPlayer`, `M.SetPlayerWorld`, `M.SetFacing`,
  `M.SetSpeed`, `M.SetTaxi`, `M.SetIndoors`, `M.SetNoPosition`, `M.SetLife`,
  `M.SetInstance(kind, id)` (id: GetInstanceInfo's 8th value while inside;
  outside it answers the continent frame's id), `M.SetNoMap` (review-r2:
  GetBestMapForUnit answers nil, as inside Magisters' Terrace),
  `M.SetCombat`, `M.SetModifier`, `M.SetGroup`, `M.SetUnit`,
  `M.SetUnitNoWorld` (UnitPosition blind for one member, its map position
  kept), `M.SetCorpse`, `M.SetEntrances`, `M.SetMinimapShape`, `M.SetZoom`,
  `M.Receive`, `M.World`, `M.MapPos`, `W.cvars`, `W.sendResult`.
- **The world map:** a WorldMapFrame PROXY that records every field write (only
  `pinPools` keys and hooks are allowed), Blizzard's AcquirePin order and mouse
  wiring (OnMouseUp calls `pin:OnMouseUp(button)` and then `pin:OnClick` only
  when the release is inside; OnMouseDown is the mixin's own), 2.5.6's secure
  `CreateFramePool` proxy beside `CreateUnsecuredRegionPoolInstance`.
- **3.1 additions** (additive, but for one fidelity fix: `M.Click` delivers
  nothing to a disabled Button, and `M.Hover` runs a disabled Button's
  OnEnter only after `SetMotionScriptsWhileDisabled(true)`, both returning
  false when the client would not; recorded as `__motionWhileDisabled`. The
  mock used to deliver both, which hid the greyed GoButton whose reason no
  player could see; every contract harness was re-run after it): the Go button
  loaded in its Events TOC slot (`ORDERS_GOBUTTON` swaps in a copy);
  `C_ChatInfo.SendChatMessage` recorded into `M.chat`; a dialog's
  `maxLetters` applied to its edit box; `UnitGUID` for group members
  ("Player-1-<name>"); `EventRegistry` (callbacks called as fn(owner, ...));
  `SetItemRef` routing `addon:` links to EventRegistry "SetItemRef", others
  into `M.itemRefs`; `M.ClickLink(text, button)`;
  `ChatFrameUtil.AddMessageEventFilter` and `M.RunChatFilters(event,
  arg1..arg14)` with ProcessFilters' fourteen-argument semantics,
  `M.filterCalls`.
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

The consumers' contract harnesses (the list at the top) load it with
`dofile` and use `M.Boot{ files, skipFiles, player, saved, before,
afterFiles, addons }`, `M.Fire`, `M.Advance`, `M.Click`, `M.Hover`,
`M.ClickLink`, `M.RunChatFilters`, `M.World`, the setters above,
`M.W.cvars / .mods / .minimap / .widgets`, `M.sent / prints / chat / popups /
tooltip / blocked / writes / errors / loadErrors`, `M.Reload` and
`CommanderOrders.R.View()`. Keep those stable, or run every contract harness
after changing them. Boot fires `ADDON_LOADED` for `Commander_Events`,
`Commander_Orders` and then each of `opts.addons`; the older harnesses that
register for Orders' `ADDON_LOADED` from a hook frame (see
`recovery_orders_smoke.lua`) still work.

---

## "Go to" coverage: all 60 Commander modules (3.1, DECISIONS D41)

`ls -d Commander_*/ | wc -l` is 60. Every module is a row: its Go surfaces
(the words and gestures are DECISIONS D31; "source" is the waypoint's owner
in `Data.SOURCE_ICONS` / `SOURCE_WORDS`), or why it has none. 24 consumers,
2 infrastructure, 34 N/A. The harness that proves each consumer's surfaces is
named in its module's Harness/README.

| Module | Go surfaces | N/A reason |
|---|---|---|
| ActionBar | | Action bars only; no place data. |
| Adjutant | Repair alert: quiet, temporary waypoint at the nearest repair (asks Logistics' "Repair" line). Bags full: the banner names the nearest vendor and a quiet, temporary waypoint (Logistics' "Vendor" line; Mark the Nearest Vendor). Both parked in combat, withdrawn when solved. | |
| Advisor | | Combat rules engine; knows only the instance type. |
| Afflictions | | Auras; no place data. |
| ArenaFrames | | Arena enemies; no positions, and no arrow inside an arena. |
| Armory | "Go to Bank" GoButton in the set pane when a set's item is in the bank (`{ townsfolk = "Banker" }`, source Armory, key bank, BANK); the flyout's banked-row line names it. | |
| Bags | "Go to Vendor" and "Go to Repair" GoButtons on its settings page (Vendor and Repair), `/cb vendor`, `/cb repair` (source Bags, VENDOR). | |
| Buffs | | Auras; no place data. |
| Camera | | Camera settings; no place data. |
| Casting | | Cast bars; no place data. |
| Chat | Orders' chat filter puts a [Go] after `/way` lines and "Zone x, y" in every chat frame; its mirror window fires the same EventRegistry SetItemRef and hyperlink hover events as Blizzard's chat frame, so a [Go] click reaches Orders and Orders' hover card shows there too (Commander_Chat 2.1.1, D41; `chat_smoke.lua`, `chat_orders_smoke.lua`). | |
| Comms | Rally on Me: the spot shared to the group through `SharePoint` (never a waypoint of your own), its chat line at Coordinate Decimals, a refused share in Orders' words. | |
| Console | | The command console; no place data. |
| Contacts | "Arrow To Them" on friend rows and whisper threads while the person is in your group (a unit follow by GUID, source Contacts, key follow, UNIT); [Go] links in logged lines (`Linkify`) with Orders' hover tooltip. "Go to their zone" is N/A: a zone is not a place. | |
| Debug | | Diagnostics dump; no place to walk to. |
| Diminish | | Diminishing returns; no positions. |
| Dossier | | An enemy's last-seen zone name is not a destination. |
| Economy | | Instance segment names, recorded where you already are. |
| Events | Infrastructure: `Commander.UI.GoButton`, `GoRowHint`, `RefreshGoButtons` (CommanderGoButton.lua). | |
| Forecast | | Spell output on action bars; no place data. |
| Formulary | Every source row is a GoButton (vendors, droppers, trainers, quest givers; source Formulary, `place:<name>@<map>`); a creature inside an instance goes to its dungeon's door (`instance = <id>`, key `door:<instance>`); "any trainer" goes to the nearest trainer; the rank readout's Ctrl+Right-click goes to the next rank's source (key `rank:<profession>`); the Trips' routes. | |
| Gladiator | | Queue minigame; no place data. |
| Guide | "Go to Entrance" GoButton in the window (Orders' door table through `{ entrance = { instance = id } }`, source Guide, key `entrance:<RAID>`), the settings button, `/cguide entrance`, a key binding. Greyed inside the raid ("You are already inside"). | |
| Idle | | Names service frames only, to stay quiet while you use them. |
| Impact | | Kill feedback; no place data. |
| Inventory | | Usable items; the hearthstone's bind spot is not a walk target. |
| Kicks | | Enemy interrupt cooldowns; no positions. |
| Logistics | "Go to Nearest Repair" and "Go to Nearest Vendor" on its settings page are `Commander.UI.GoButton`s (source Logistics, keys repair and vendor, the spot from `CommanderLogistics_SupplySpec`), `/clog repair`, `/clog vendor`; its learned repair book is a "townsfolk" resolver for Repair and Vendor (merged with Questie's lists); the supply waypoints Adjutant's offers use (source Logistics, keys repair, vendor). | |
| Meters | | Damage segments named by zone; no place to go. |
| Minimap | Your coordinates under its zone name (Orders' gestures) and Ctrl+Right-click on the map for a waypoint that never pings (Orders' MinimapCoords, MinimapClick). | |
| Momentum | | Best chains per zone name; no place. |
| Muster | | Gear score and ratings; no place data. |
| Nameplate | | Nameplates; no place data. |
| Notebook | A Go button (GoButton) on map-stamped notes and the menu's "Go To This Note" (source Notebook, `note:<id>`, NOTE); old name-only stamps keep a plain Go through Orders' `/way` resolver. | |
| Objectives | Turn-in Offer (off by default): a quiet, temporary waypoint at the finisher when a quest turns complete (QuestLog's adapter; source Objectives, `turnin:<id>`, QUEST). | |
| Oracle | Arathi Basin flag pips (source Oracle, key node, PVP); "Go to the Flag" (a key binding and `/coracle flag`, WSG and EotS, following the carrier); `/coracle nodes` prints every place the battleground map names with a claimed [Go]. | |
| Orders | Infrastructure and provider: the arrow and its menu, the pins, the manager (Add at..., Move..., Save as place), the coordinate block, the map's Ctrl+Right-click, `/way`, `/cway`, the chat links, the corpse run, the TomTom bridge. | |
| PartyFrames | Click-cast "Arrow to them", `/cpf arrow`, and the binding "Arrow to My Target" (unbound until you set it): a unit follow by GUID that keeps the member through roster changes (source PartyFrames, key follow, UNIT). | |
| Ping | The callout's [Go] link (Orders' link, claimed so a click moves its one "Ping" waypoint); Waypoint on Group Pings (automatic, silent, temporary). | |
| Plates | | Nameplates; no place data. |
| Production | | Cooldown queue; no place data. |
| Promotion | Level-up banner names the nearest class trainer; Trainer Offer (on): a quiet, temporary waypoint there out of combat, removed at a class trainer; `/cpromo trainer` (source Promotion, key trainer, TRAINER). | |
| Quartermaster | Browser rows: Ctrl+Right-click (and the tooltip's hint) goes to where the item comes from: the nearest auctioneer, its vendors (your faction's first), the trainer, a dropper (an instance dropper's door), the quest giver, the container (source Quartermaster, VENDOR). Plain right-click stays the restock target. | |
| QuestLog | "Go to Turn-in" on the Log's bar, "Go" on the Zones and Reputations bars, a row "Go" per objective Questie can place, "Go" on REQUIRES / LEADS TO lines (the quest's starter), Ctrl+Right-click on Log rows, right-click on Zones, Reputations and drawer rows, Route Zone (source QuestLog, keys `quest:<id>` and `quest:<id>:<n>`, QUEST; every key removed at turn-in or abandon). | |
| Radar | | A minimap overlay; no place data of its own. |
| RankCheck | | Spell ranks on bars; no place data. |
| Recovery | A [Go] link ("Where you fell") on the death report and `/crec test`; the corpse arrow itself is Orders' (D24). | |
| Resources | | Resource bars; no place data. |
| Reticle | | A screen reticle; no place data. |
| Spoils | "Go to Farm" GoButton on its settings page, the header glyph's right-click and `/cspoils back` (source Spoils, key farm, FARM). | |
| Suite | | The suite dashboard; no place data. |
| Talents | | Builds and consumable picks; a consumable's source is Quartermaster's Go. |
| Threat | | Threat meter; no place data. |
| Tooltip | | Vendor prices and item levels; no place data. |
| TopBar | The coordinates are Orders' coordinate surface (click, Shift, Ctrl, Right; Coordinate Decimals); the durability, bags and ammo readouts go to the nearest repair, vendor and ammo vendor (Go from the Readouts; source TopBar, keys repair, vendor, ammo, VENDOR); the Nav segment opens the manager. | |
| Tracer | | Floating combat text; no place data. |
| Tradecraft | Every place row is a GoButton (vendors, trainers, book vendors, quest givers), "any trainer" lines go to the nearest trainer, Ctrl+Right-click on a trade-supply reagent row goes to the nearest vendor of it, Route This Trip (source Tradecraft); its Set Waypoints switch is kept. | |
| Vault | "Go to Bank" GoButton on the footer line while your own vault is shown away from the bank (source Vault, key bank, BANK). The guild vault has none: no locator kind lists guild vaults. | |
| Vitals | A worn slot's tooltip names the nearest repairer; `/cvitals repair` goes there (rows stay hover-only, so the HUD keeps passing clicks through). | |
| Who | | A stranger's zone is not a destination. |

**New globals written by the consumers this round** (each a documented
entry point in its module): `CommanderLogistics_Nearest`,
`CommanderLogistics_SupplyWaypoint`, `CommanderLogistics_ClearSupplyWaypoint`,
`CommanderLogistics_SupplySpec` (the settings GoButtons' spot)
(Logistics; NearestRepair, RepairWaypoint and ClearRepairWaypoint stay as
wrappers); `CommanderOracle_GoToFlag`, `CommanderOracle_Nodes`,
`BINDING_HEADER_COMMANDERORACLE`, `BINDING_NAME_COMMANDERORACLE_FLAG`
(Oracle, with its new Bindings.xml); `BINDING_HEADER_COMMANDERPARTYFRAMES`,
`BINDING_NAME_COMMANDERPARTYFRAMES_ARROW` (PartyFrames, with its new
Bindings.xml); `CommanderPromotion_GoToTrainer`; `CommanderVitals_GoToRepair`.
Orders and Events write none (Orders adds one dialog,
`COMMANDER_ORDERS_COORDS`). Checked with luajit's bytecode listing (GSET)
against HEAD for every changed file.

**Restart the client, not /reload.** New files this round:
Commander_Orders/CommanderOrdersEntrances.lua, CommanderOrdersLocate.lua,
CommanderOrdersCoords.lua, CommanderOrdersChat.lua;
Commander_Events/CommanderGoButton.lua; Commander_Oracle/Bindings.xml;
Commander_PartyFrames/Bindings.xml. A /reload leaves them unloaded ("Error
loading" in BugSack, no coordinate block, no [Go] links, every "nearest" Go
answering "still loading"); ASSUMPTIONS A61.

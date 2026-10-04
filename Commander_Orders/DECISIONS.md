# Commander_Orders — decisions

Numbered so later work can argue with them by name. These are 3.0's decisions
(2026-10-04), the release that rebuilt Orders into the suite's own navigation
and retired TomTom. The 2.x module's defects are cited as "2.x defect Dn": the
numbering of the old review, kept in the header of `CommanderOrders.lua`
where each one is fixed. In-game unknowns are in `ASSUMPTIONS.md`; the
harnesses and their counts in `Harness/README.md`.

**D1 — Rebuilt, not patched.** The 2.x arrow was "quite buggy", and the bugs
were structural, not cosmetic. It paired UnitPosition's WEST with the
waypoint's NORTH (2.x defect D1, since 0bfa0d12), so it showed 12,952 yd while
the player stood on a target 582 yd away and never arrived. It had one
account-wide slot that every caller overwrote (D3), so a quest button wiped a
corpse order and an alt inherited the main's waypoint on another continent
(D2). It compared raw instance ids, and Eversong and Hellfire are both 530
(D4). It ignored its own master switch (D7), hooked the world map's canvas
click handler (D8, the taint factory), cancelled on any click and ate camera
turns (D9), sat in the raid-warning band (D10), turned in 18 degree steps
(D11), went silent instead of saying why it could not point (D5, D12), and ran
every frame of the session (D17). A model with owners, a pure geometry layer,
a click-through HUD and a real arrival machine is not an edit of that file, so
3.0 keeps the module key ("Orders"), folder, title, slash and legacy globals,
and replaces everything behind them. TomTom is not wanted in the suite; the
brief was a navigation system good enough that it is not missed, every
Commander module with a location wired into it, and a shim so Questie and
WhatsTraining keep working with TomTom removed.

**D2 — Seven files, one table.** Data (pure tables), Geo (pure maths, parser,
formats, filters), Store (pure model), DB (settings, migration, page),
CommanderOrders (the runtime: client, arrow, API, slash, shim, sharing,
corpse), Pins (minimap and world map), UI (the manager), loaded in that order.
They share ONE global table, `CommanderOrders` (`O`), with sub-tables
`O.Data`, `O.Geo`, `O.Store`, `O.DB`, `O.Pins`, `O.UI` and `O.R`; the table is
also the public API. Geo and Store make no client call at all: the runtime
hands Geo an `env` of client functions (built once per session, its caches are
keyed by it) and the Store a `ctx` of answers (position, distance, landmass,
ghost, taxi, clock). That is what lets their harnesses load each file ALONE in
a sealed environment where touching any other global raises.

**D3 — The axis convention is named, not remembered.** A waypoint is
`{ map = uiMapID, x = 0..1, y = 0..1 }` (TomTom's convention; a consumer
holding 0..100 divides by 100). A world position is
`north, west, _, instance = UnitPosition("player")`, and
`instance, v = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))` gives
`v.x = north`, `v.y = west`. Variables holding world coordinates are named
`north` / `west`, never x / y, and only Geo pairs a player's with a
waypoint's. The bearing is `atan2(west_t - west_p, north_t - north_p)`,
counter-clockwise from north like GetPlayerFacing, so the arrow's rotation is
`normalize(bearing - facing)` passed straight to SetRotation. Geo uses
`math.atan2/sin/cos` only: the global `sin` and friends take degrees on this
client. The D1 regression (582 yd at 339 deg) is asserted in both the Geo
smoke and the runtime harness, through UnitPosition's real argument order.

**D4 — A straight arrow needs the same instance AND the same landmass.** The
landmass key is `"<first Continent ancestor>:<world instance>"`
(`Geo.Landmass`): Eversong, Ghostlands, Silvermoon and Quel'Danas are children
of the Eastern Kingdoms map but live in 530, so `1415:530` is Quel'Thalas, a
landmass of its own; `1414:530` is the Azuremyst Isles and `1945:530` Outland.
A map with no Continent ancestor (a battleground under Azeroth) uses its
top-most non-World ancestor, so Alterac Valley is `1459:30`. Across landmasses
there is no arrow and no distance, ever: the Store checks `sameLandmass` before
every measurement, the minimap shows pins for the player's landmass only, and
route lines leave out a leg between two.

**D5 — Waypoints are owned records.** Every waypoint has a stable uid ("w12",
per character, the counter saved with the store) and a `source` ("user",
"QuestLog", "TomTom:Questie", "share:Thrall", ...). `(source, key)` is unique
among standalone records: adding again MOVES the existing record, so a quest
button pressed twice leaves one waypoint and a repair offer is one record
whoever asks. Without a key, a record within 1e-6 map units of the same map,
place and title is the same record (1e-6 survives the saved-variable writer's
16 significant digits). A dedup hit returns the record unchanged, as TomTom
does, except that it is promoted to persistent or non-temporary when asked,
its reached mark clears, and `setArrow` re-pins it. Route stops are always
fresh records; there is one corpse record; a unit follow dedups on
(unit, title). Titles are cut to 255 bytes on a UTF-8 boundary.

**D6 — Who holds the arrow.** Corpse (while a released ghost and CorpseArrow
is on) > the pinned target (what the user chose, or a consumer's
`setArrow = true`) > the running route's current stop > the closest waypoint
on the player's landmass (AutoClosest, on by default). A `temporary` waypoint
never replaces a non-temporary pin, nor a running route (which holds the
arrow with no pin at all, so the pin alone does not say so: the review found
Adjutant's repair offer and an automatic ping taking the arrow off a route
stop): Adjutant's repair offer, an Oracle flag pip or a group ping cannot
take the arrow from a waypoint or a route you set. Closest and
nearest-of-N alternatives change only when a challenger is BOTH 20% nearer AND
30 yd nearer (one bar alone flickers between two spawns either side of a
road), scanned at most twice a second. "Clear arrow" sets a dismissed flag
(persisted) that keeps the route and closest rules quiet until you pick
something again; the corpse still wins for a ghost.

**D7 — The arrival machine.** NAVIGATING -> NEAR (inside 3x the radius,
left only beyond 3.3x so the line does not pulse) -> ARRIVED (inside the
radius: one chime, held 2.5 s) -> DONE (cleared and/or the route advances).
Never on a taxi. The radius is the waypoint's own, else the ArriveYards
setting (10), resolved every tick, so changing the setting reaches existing
waypoints. A target first measured inside its radius on the tick it was born
does not arrive until the player leaves and comes back (the fresh-born rule),
so `/wayb` and "Mark place here" never clear under your feet; route stops made
earlier are exempt. A target that loses the arrow while ARRIVED still gets
its DONE. KeepMyMarks keeps the user's own marks after arrival, stamped
reached and left out of AutoClosest; the arrow menu's "Mark arrived" stamps
a mark that does not clear the same way (`Store:MarkReached`), or the closest
rule handed the same waypoint straight back. An idle tick with no target says
nothing (no TARGET nil -> nil; the runtime keeps a uid ~= previous filter as
a defence, because a TARGET every tick would fire CHANGED every pass).

**D8 — Routes.** `ORDERED` walks the stops as given; `NEAREST` re-orders the
stops still ahead nearest-neighbour from the player, a landmass at a time: the
player's landmass first, then the others in the order of their first stop.
Arrival advances; arriving at the last stop of an open route finishes it ("Route
complete", the route and its kept stops removed). RouteNext at the end answers
"last stop" rather than finishing, so a stray key press never throws a route
away. Pinning a stop jumps the route to it. A route is owned by (source, key)
like a waypoint, so "Route open quests here" or "Route this trip" pressed
again replaces the route rather than stacking a second.

**D9 — The arrow is click-through, with a modifier-gated surface (Commander
Tracer D12's precedent).** Locked, the arrow takes no mouse at all: no camera
turn is ever eaten and no stray click clears anything (2.x defect D9). The
shared HUD chrome owns the root frame's mouse and OnMouseUp, so after every
ApplyHudChrome the root's mouse is switched off again, and the clickable
surface is a child Button enabled only while the chosen modifier (Shift by
default; ArrowModifier) is held: MODIFIER_STATE_CHANGED toggling the mouse of
an unprotected frame is legal in combat. Shift-click opens the manager,
Shift-right-click the menu (next / previous stop, Guide me, mark arrived,
clear arrow, remove, share, copy /way, open manager, lock). The chrome's
triple-right-click unlock cannot reach a click-through frame, so unlocking is
on the settings page and `/corder unlock`, and the page says so.

**D10 — The chrome is first applied out of combat.** The chrome's
SetPassThroughButtons is protected and refused in combat WITHOUT an error, so
a pcall says ok and the chrome would believe the frame passes left clicks.
The arrow is built and first chromed at PLAYER_LOGIN; a login in combat (a
/reload mid-fight) waits for PLAYER_REGEN_ENABLED. Its default spot is TOP
-340, UNDER the top-centre band (about 110..330 px from the top) that the
suite's toasts (Objectives, Adjutant, Impact, Production, Promotion),
Momentum's plate, Blizzard's zone text and the raid warnings (hung under
UIErrorsFrame) all share, and above Diminish (CENTER -160) and Kicks (CENTER
-220). 2.x sat in that band at -220 (2.x defect D10) and 3.0's first -140
was still inside it, despite this paragraph saying otherwise (review:
render). It is also 240 right of the centre column: between the toast band
and the character's head the centre column has only about 54-97 units free,
less than the arrow's 158-unit box, so the arrow sits beside the character
rather than on it (review round 2; TomTom's own default is dead centre). The
style is NONE: the arrow floats.

**D11 — Smooth to look at, cheap to run.** One SetRotation every frame,
eased by `Geo.AngleFilter`: the exact critically damped solution on the
circle (no jump at +-pi, no overshoot, a long hitch lands on the target),
tau 0.1 s, SmoothArrow on by default. Distance, ETA, arrival and the text run
at 10 Hz and write a FontString only when its text changes, and a quiet pass
allocates nothing: `Store:Tick` hands back one shared read-only empty list
when nothing happened (the array is made on a tick's first event),
`Store:ArrivalState()` reads the arrival record without a copy, and a
followed group member is measured from `UnitPosition(unit)` and its map id,
never the map position (a Vector2D a call; the review measured 2 KB/s idle
and 17 KB/s following a unit before). The Store's own occasional unit asks
are sampled at most once a second. The driver frame
is hidden whenever the Store says nothing needs ticking, and woken by the
events that can change that (2.x defect D17). The ETA is distance over an
EMA of ground speed seeded from GetUnitSpeed, reset on a new target or a
teleport-sized jump, and blank while standing still, walking away or on a
taxi. The arrow's colour runs green -> yellow -> red by alignment, with a
cooler "locked on" green within 4 degrees.

**D12 — Every state is said, never faked (2.x defects D5, D12).** NAV (with
"Turn around" past 150 degrees, "In flight", "No heading", "Stop 2 of 5"),
ARRIVED (the ring and tick art), OTHER ("In Outland, via the Dark Portal in
the Blasted Lands"), NOPOS ("No position inside instances"), NOWORLD (a map
with no world coordinates), UNIT_LOST ("Party member not visible"). The text-
only states leave the arrow quad empty so the layout never shifts. OTHER
offers "Guide me" when the first hop has a place: a session-only waypoint
(source "guide", key "hop") at the departure, which hands the arrow back to
the original target when its DONE arrives, when it is marked arrived or
removed by hand, and when the player reaches another landmass without
walking onto it (a portal, a hearthstone, the far end of a boat: the hop is
removed, so the arrow never sends anyone back across the crossing just made).
Picking anything else as the arrow ends the guide. The status line is the
arrow's own width and wraps to two lines, so "via the Thalassian Pass, from
the Eastern Plaguelands" stays inside every frame style and the screen
clamp. The hops are a breadth-first search
over `Data.CONNECTIONS`, a deliberately SMALL table filtered by faction in
which every coordinate is cited from QuestieDB spawns; a crossing with no
citable spot (the Thalassian Pass, Booty Bay to Ratchet) is named but offers
no Guide me. A dungeon TARGET points at its entrance when a resolver knows it
(QuestLog's, from Questie), else at the client's
C_EncounterJournal.GetDungeonEntrancesForMap list, else says "No known way
there". Combat layout never changes by default: HideInCombat, HideInInstances
and HideWithMap are all off; only HideNoTarget is on.

**D13 — Continent points are stored on their zone.** A continent map holds
two coordinate frames (the 530 sub-rectangles of Quel'Thalas and the
Azuremyst Isles), so any position given on a World or Continent map, a map
click, a pin drag or a consumer's Add, becomes the zone under it through
`Geo.ZoneAt`. ZoneAt asks GetMapInfoAtPosition which zone it is, but takes the
final coordinates from that zone's OWN rectangle on the clicked map
(GetMapRectOnMap) and refuses unless that rectangle contains the click: the
DB2 shows Azeroth (947) placing the 530 zones through their own rows
inconsistently with the Eastern Kingdoms' rectangle (Eversong at 0.915, 0.333
one way and 0.835, 0.150 the other). A refusal is an honest "Zoom in to place
an order", never a waypoint in the wrong zone. A position with no world data
at all (Cosmic, the ocean) is refused with "no world position"; a dungeon map
answers for itself and is never told to zoom in.

**D14 — Map input is an overlay, never the canvas click handler.** A Button
over WorldMapFrame.ScrollContainer, shown only while the chosen modifier (and
no other) is held with the map open; Ctrl+Right-click by default
(MapClickModifier CTRL / ALT / SHIFT / OFF). Its SetPassThroughButtons
(Left, Middle, Button4, Button5) is called ONCE, at login out of combat or on
the first PLAYER_REGEN_ENABLED after a login in combat, and the overlay is
never shown before that, because it would swallow left clicks. TomTom called
it every frame the modifier was held; AddCanvasClickHandler is the taint
factory 2.x used (D8), it ties with the battleground report-AFK handler at
priority 0, and RemoveCanvasClickHandler errors on this client. The overlay
sits three levels over the ScrollContainer and far under the pins, so a
Shift+Right on a pin always reaches the pin.

**D15 — Pins.** Minimap: one pin for EVERY waypoint on the player's landmass
(TomTom showed the current zone only), at the position the arrow would use
(the chosen spawn of a nearest-of-N waypoint), riding the rim as a rotated
chevron when off the map (MinimapEdge). Pins are UNNAMED frames, because
Commander_Minimap's tidy fades children named like minimap buttons; they sit
three levels above Commander_Radar's overlay; they move every frame only while
shown; a jump of more than 250 yd between two frames counts as a loading
screen (a portal inside 530 keeps the instance). Minimap pins take Shift-click
(arrow) and right-click (menu) only: a plain click passing through would need
the protected SetPassThroughButtons on every pin, in combat too. World map: a
data provider on QuestLog 1.4.0's recipe (CreateUnsecuredRegionPoolInstance,
because 2.5.6's CreateFramePool is the secure proxy that drops our functions),
pins click- and motion-enabled at creation for AcquirePin's wiring, at
PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST (above Questie's icons, below the party
dots) with the arrow's target one level up and ringed. Every spawn of a
nearest-of-N waypoint is drawn on the world map (the chosen one full size),
the chosen one only on the minimap; no pin for unit follows (the client draws
group members). Click sets the arrow, right-click opens the menu, Shift-drag
moves a standalone point or a stop. Route lines are Line regions for the
ACTIVE route only, a walked leg dimmed, a cross-landmass leg left out; a Line
that refuses its colour switches lines off for the session after one report.
A redraw releases every pin, so while a pin is dragged a change only marks the
map stale, and the redraw after a drop waits a frame (Blizzard calls OnMouseUp
then OnClick on the same pin object). The world-map coordinates (player and
cursor, for the MAP ON SCREEN) are parented to WorldMapFrame, not BorderFrame
(hidden in the windowed map, TomTom B2), and step aside while Questie's own
are on (`Questie.db.profile.mapCoordinatesEnabled`, read only).
Commander_QuestLog's completion drawer (open by default with Questie, docked
right, 88% opaque and mouse-enabled at max(container + 2200, TOPMOST + 10))
covered every pin under it. While it is shown, the arrow's own target
alone is lifted over it the way QuestLog lifts its own pulsing pins (the
level is worked out by the same formula, never read off the drawer; its
show and hide re-level them), and the coordinates sit bottom-left one level
under it, so the stacking is defined where they meet. A running route's
current stop is the target, so the next place to go stays in sight; the
route's other badges and its lines stay under the drawer. Lifting the whole
route (round 1) put up to a dozen badges on the drawer's quest rows and
group headers: a click meant for a row set the arrow, a right-click opened
Orders' menu, a header's fold never folded (review-r2 orders). Other pins
stay under it too: lifted, every pin would sit over the party dots and the
player arrow. The lifted target itself can still cover a row or two of the
drawer (an 18-22 unit pin over 16-unit rows) and take their clicks there;
accepted for now (ASSUMPTIONS A40). The full answer is a small edge marker
on the drawer's left border at the target's height, the minimap's edge
chevron recipe, kept out of the row area. A Ctrl+Right-click inside the
drawer reaches the drawer, not the map-click overlay; folding the drawer
places a waypoint there (accepted). A refused map click or drop is said
over the map for three seconds as well as in chat, which the maximized
map's blackout hides. On the minimap a two-digit route number gets an 18-unit badge, and
on a SQUARE map an edge chevron at the top rides 22 units under the edge,
clear of Commander_Minimap's zone name.

**D16 — Commander_Minimap answers GetMinimapShape.** Its square mask has been
on since ADDON_LOADED with nothing saying so, so every pin library
(HereBeDragons in Questie and RXP, LibDBIcon, these pins) clamped to a circle
inside the square. Commander_Minimap 2.4.0 defines the global
`GetMinimapShape()` returning "SQUARE" where the mask goes on, and never over
another addon's own definition. It is the ecosystem's contract, so it is the
one global outside this folder the release writes.

**D17 — The TomTom shim: exactly what callers use, nothing they could
mistake for TomTom.** Installed at PLAYER_LOGIN only when no `TomTom` global
exists, TomTom is not loaded, the TomTomShim setting is on and Orders itself
is on (with Orders off every add is refused, and a shim answering nothing
left Questie's and WhatsTraining's waypoint buttons showing and doing
nothing; the settings event installs and removes it); tagged
`isCommanderShim = true`, `version = "Commander_Orders"`. Tier 1 is what
Questie and WhatsTraining call: AddWaypoint returns TomTom's own plain-data
uid `{ m, x, y, title =, from = }` with the numbers exactly as passed (Questie
compares `uid[2] ~= x`) and only scalar options copied in (Questie saves the
uid; a function in it would be dropped and a frame would drag a widget in);
RemoveWaypoint is silent for anything it does not know and finds by
identity, then by a %.6f key, then by place and title among TomTom-sourced
records only (Questie hands back a one-bit-off copy after a reload, and a
user's own waypoint at the same spot must survive), the stale place first
put through the continent-to-zone step every add takes (D13: Questie's
Blackrock Mountain and Silithus NPCs sit on 1414 / 1415). It removes ONLY a
record whose source is still `TomTom:*`: the Store's same place and title is
the same record whoever added it, so Questie's handle can land on the
user's own /way or an accepted share, and its later RemoveWaypoint only lets
go of the handle. The user re-adding a TomTom caller's spot (a /way line, an
accepted share, a place) claims the record (`Store:Claim`; keyless records
only, a consumer's (source, key) never changes hands). Distance callbacks are
honoured (pcall'd, inward crossings only); cleardistance > 0 becomes the
arrival radius, 0 becomes clearOnArrive = false; a duplicate AddWaypoint
re-pins the arrow (TomTom's B16 kept the old target). Tier 2 is thin
wrappers (WaypointExists, GetKey, distance and direction, the crazy arrow,
closest). Tier 3 is deliberately absent: no db or profile, no catch-all
metatable, no arrow hijack, no ClearAllWaypoints, and IsAddOnLoaded("TomTom")
is never faked, so Questie's own options still say TomTom is not installed
(accepted). The TOC keeps `OptionalDeps: TomTom` so a real TomTom, should
one be installed, loads first and is deferred to; it is the only TomTom
reference in any Commander TOC.

**D18 — /way is claimed only when TomTom is absent, under our own keys.**
Three slash keys, because one key cannot tell /way from /wayb:
COMMANDERORDERS_WAY (/way, /tway), COMMANDERORDERS_WAYBACK (/wayb, /wayback),
COMMANDERORDERS_CWAY (/cway, /closestway); never TOMTOM_WAY, and /tomtomway is
left alone. Registered at PLAYER_LOGIN when TomTom is not loaded and
ClaimWaySlash is on; turning ClaimWaySlash off takes effect after a reload
(SlashCmdList entries cannot be withdrawn). `/corder way ...` always works.
/corder is the settings framework's slash with exact-match handlers, which
lowercase the message; the free-text forms (way, here, mark, go, share) wrap
Orders' own SlashCmdList entry after Finalize so their case is kept, and
every other word falls through to the framework.

**D19 — The /way grammar and zone names live in Geo.** `Geo.ParseWay`
returns a structured command (ADD, LOCAL, LIST, ARROW, RESET, USAGE, ERROR)
and is shared by /way, the paste window and Notebook's old stamps. A leading
/way, /tway or /tomtomway is stripped (TomTom B18 ate the first word of a
pasted line); `45,66` reads as two numbers only when a number follows the
comma; values outside 0..100 are refused. Zones resolve against an index of
every Zone and Continent map walked from 946 (dungeons only by `#id`),
folded (lowercase, no spaces or punctuation), in tiers exact name > alias
(`Data.ZONE_ALIASES`) > prefix > substring (3+ characters), with a plain
find, never a pattern (TomTom B12). Two hits in a tier are ambiguous: the
candidates are printed with their `/way #id x y` lines, never guessed. A
registered "zone" resolver is asked after the index.

**D20 — Sharing never takes your arrow from you.** Addon messages under the prefix
`CmdrOrders`, payload `1:<map>:<x %.5f>:<y %.5f>:<title>` with `%`, `:`, `|`
and control characters escaped as %XX and the title cut at 120 bytes. The
channel is the group's (INSTANCE_CHAT > RAID > PARTY) unless named;
`SendAddonMessage`'s result is an enum where every value is truthy, so only 0
(or nil / true) is success and the rest is put into words. Receiving: your own
echo is ignored (Ambiguate "none"), three shares per sender per 10 s, then
ShareAccept decides: ASK (a dialog: Add / Add and go / Ignore), GROUP_AUTO_ADD
(party or raid members added quietly, never GUILD; anyone else asked) or OFF.
A received share never pins the arrow unless you press "Add and go", and one
added without "go" is `temporary`: behind every waypoint of your own when
Follow the Closest picks, so it points the arrow only when you have nothing
else (it used to swing the arrow off your own closest one; the settings text
says this rule now). A received title is plain words: colours and textures
are dropped whole, a link keeps its text, and any `|` or control character
left over goes, on both wires. TomTom
users' `TOMTOM4` messages are read only behind ListenTomTom (off). "Copy /way
line" is offered everywhere, and the CHAT / SAY forms post a /way line for
players without addons, from menu clicks only (SAY needs a hardware event).
`Share` and `SharePoint` (a spot that is not one of your waypoints: Rally on
me, the TopBar's Shift-click) go through one send path.

**D21 — The public API.** Every function is pcall'd at the boundary, nil-safe,
answers `nil, reason` on refusal, and refuses every add with "disabled" while
Orders is off (2.x defect D7). It hands out COPIES (`Store.Copy` plus a `zone`
name); the live records are reached only by Pins and UI through `O.R`. SPEC 6:
Add, AddRoute, Remove, RemoveBy, Clear, SetArrow, ClearArrow, Get, List,
Distance, Active, IsAvailable, Describe, Here, Share, WayLine,
RegisterResolver ("entrance", "zone"), OpenManager, OpenPaste. Added while
the consumers were wired in: Entrance(map) (Guide's raid doors: resolvers
first, then the client list, a copy), Status() (the arrow's own view in its
own words, for the TopBar's Nav segment), SharePoint(spec, channel),
CorpseArrow() / SetCorpseArrow(on) (Recovery's option), OpenPaste(text),
Import / Export, PastePages / SavePastePage / DeletePastePage, the route
functions (Routes, GetRoute, ActiveRoute, RouteStart / Next / Prev / Reverse /
Optimize, RemoveRoute), MarkArrived, Guide, Update, the places (MarkPlace,
GoPlace, Places, RemovePlace, RenamePlace), ToggleManager, Command and Binding.
Add returns a third value, "added" | "moved" | "existing". Status, WayLine,
Share, the arrow's tooltip and `/corder arrow` name the spawn the arrow
follows of a nearest-of-N waypoint (its chosen alternative), never a primary
spawn it is not on. Defaults: source
"user"; `persistent` true for the user's own sources (user, place, legacy,
share:*) and false for consumers unless they say; `setArrow` true for every
source (a consumer's Add follows a button press), with D6's temporary rule on
top. The hub event `COMMANDER_ORDERS_EVENTS.CHANGED` is debounced to one per
frame and also fires when the arrow changes hands; UPDATE stays the settings
event. The legacy globals keep working as documented wrappers:
`CommanderOrders_IssueOrder` is ONE record under (legacy, order) that every new
order moves (the old single-slot feel, not a pile), ClearOrder removes it or
else dismisses the pinned target, and `RallySet / RallyGo / RallyList` are
Places titled "Rally N".

**D22 — One table says who set a waypoint.** `Data.SOURCE_ICONS` (the tint a
source wears when it names no icon) and `Data.SOURCE_WORDS` ("Quest Log",
"Raid Guide") are read by both the pins and the manager, so a source never
wears two colours. The consumers' sources and keys: QuestLog `quest:<id>`
(icon QUEST, every spawn as alternatives) and routes `open:<areaId>`;
Tradecraft `place:<name>@<zone>` (VENDOR / TRAINER / QUEST) and routes
`trip:<guide>:<bracket>`; Formulary `place:<name>@<map>`, routes
`trip:<prof>:<zone>` and `trips:<prof>`; Oracle `node` (temporary); Ping `ping`
(temporary); Notebook `note:<id>`; Guide `entrance:<raid>`; Spoils `farm`;
PartyFrames `follow` (kind unit); Logistics `repair` (Adjutant asks Logistics,
so the alert's offer and the manual request are one record); Recovery adds
nothing (D24). The TopBar's click is the user's own mark (source "user").
All of them are session-only by D21's default. Quartermaster is not wired in:
its generated data carries zone names only (its Harness/README has the
follow-up).

**D23 — Persistence.** `CommanderOrdersDB` is ACCOUNT-wide: settings, Places
(named spots tagged with the faction that marked them), PastePages, the
manager's window state. `CommanderOrdersChar` is PER CHARACTER: the store
(records, routes, the pinned target, the dismissed flag, the uid and route
counters) and the death the corpse arrow works from. DBVersion, Places,
PastePages, ManagerPos, ManagerScale and ManagerGroupBy are kept out of the
defaults, so Restore Defaults never re-stamps the schema or loses a place.
The store is serialized as plain whitelisted records (callbacks and handles
never), saved on every CHANGED flush and at logout, and `Store.Load`
tolerates junk and a newer schema. The ladder: a 2.x saved variable (no
DBVersion, some keys) migrates 2 -> 3: the account-wide `Waypoint` is dropped,
`RallyPoints[1..4]` become Places "Rally N", OrderSound becomes Sounds, and the
user's EnableOrders is kept exactly; an empty table is a fresh install and is
stamped 3.

**D24 — Orders owns the corpse run.** Commander_Recovery used to issue a
normal order that overwrote yours and could not clear it reliably. Orders
remembers the death per character (so a reload or relog as a ghost still
finds the way), asks C_DeathInfo.GetCorpseMapPosition on the map you stand on
and each parent to the continent (a corpse found only on the continent is
stored on its zone, D13), and puts the corpse first only while you are a
released ghost (D6); it is removed when you live. Feign Death is not a death;
battlegrounds and arenas resurrect at a graveyard on a timer and get no
arrow; a death inside an instance points at its entrance through the
resolvers. Recovery 2.3.0 issues nothing, reads no Orders saved variable, and
drives the CorpseArrow setting through CorpseArrow() / SetCorpseArrow().
CORPSE_IN_RANGE is not used: arrival is by distance like any waypoint.

**D25 — Our own art.** TomTom's art is All Rights Reserved / CC BY-NC, and
2.x borrowed the minimap's death arrow. `Harness/make_art.py` (stdlib Python)
draws eight textures, WHITE with grey shading in the RGB so SetVertexColor
carries the hue and the dark outline stays dark under any tint: Arrow,
ArrowShadow, Arrived and Ring at 256, Pin, PinEdge, Badge and Corpse at 64.
Every pixel with alpha lies inside r <= side/2 - 2 measured to the pixel's far
corner, so the art is whole whether SetRotation turns the quad or only the
texture coordinates (ASSUMPTIONS). The arrow points up at rotation 0 and is
0.66 of its quad tip to tail (an 84 px quad draws a 55 px arrow). ArrowShadow
is white, tinted black at 0.6 with a fixed screen-space offset. Transparent
pixels carry the nearest edge colour, so straight-alpha filtering leaves no
dark fringe. Paths carry the .png extension; new files need a client restart.
No shape glyph is drawn in any text (D11 of the suite: ARIALN draws them as
boxes); markers are textures and chevrons are quads.

**D26 — The manager is one window with three tabs.** Waypoints, Places and
Paste are tabs rather than the SPEC's toolbar buttons that swap sub-panels: a
tab says which view you are in. The look is the Quest Log's stone sheet
(QuestLog D16/D17: dark by default, no parchment). The list groups Arrow (what
the arrow follows, not repeated in its zone), Routes (stops indented under
each), then zones (yours first) or who set it. Remove and Remove route stand
apart at the bottom right, where a quick click along the action row cannot
land. The title is edited in place and committed on Enter or on leaving the
box, never overwritten by a refresh while it has the keyboard. The ETA shows
for the arrow's own target only (the speed filter behind it is the arrow's).
The window never takes the keyboard on open (QuestLog D12); Export is the one
click-driven exception, so Ctrl+C works at once. Its position, scale and
grouping are kept out of the defaults. A paste's unreadable lines are named
by the box's own line numbers (blank lines count) with the start of what
they said, as many as the result box holds, the "and N more" line always
kept. Opening the manager on a waypoint lets go of a search it fails, so the
detail never shows a waypoint the list has no row for.

**D27 — Settings.** The page (key "Orders", `/corder`) has Arrow (with the
chrome rows), Behaviour, Map & Minimap, Sharing, Compatibility and Places,
and a button row Open Manager / Paste Waypoints / Clear All. ArrowModifier
(SHIFT / CTRL / ALT) is an addition: the modifier that makes the arrow
clickable. Units AUTO means yards in the US region and metres elsewhere
(GetCurrentRegion; Geo itself cannot see the region). Sounds are two kits
Blizzard's TBC UI plays, never the same one (2.x defect D15): MAP_PING 3175 on
set and receive, IG_QUEST_LIST_COMPLETE 878 on arrival. Announce lines are
for the user's own actions only; consumers print their own.

**D28 — Numbers corrected from the community tables.** The minimap's
outdoor zoom 3 diameter is 266.67 yd (800/3), not HereBeDragons' 266.33: the
series 466.67 / {1, 7/6, 1.4, 1.75, 7/3, 3.5} shows that value is a typo.
Indoor/outdoor is read from Minimap:GetZoom() against the minimapZoom and
minimapInsideZoom CVars with IsIndoors() breaking a tie; Minimap:SetZoom is
never nudged to find out, as HereBeDragons does, because Questie and RXP
already nudge it.

**D29 — Fonts the client may not have are not assumed.** The arrow's
distance uses GameFontNormalLargeOutline when the client defines it, else
GameFontNormalLarge with an OUTLINE set on it. Only GameFontHighlightOutline and
GameFontHighlightSmallOutline are seen in 2.5.6's own FrameXML, and a
FontString inheriting a missing font has no font: its first SetText raises,
ten times a second.

**D30 — Dialogs and refusals over the maximized map.** TBC opens the world
map maximized by default: FULLSCREEN strata with an opaque BlackoutFrame over
all of UIParent, while StaticPopup_Show puts every dialog on UIParent at
DIALOG strata, under it. Every Orders dialog (copy /way line, a received
share, clear all, forget a place) raises itself to FULLSCREEN_DIALOG in its
OnShow (`R.RaisePopup`), Blizzard's own fix for its dialog over the map
(GameDialogDefs.lua 3218-3221); the next StaticPopup_Show resets the strata
for whoever uses the frame after. Before, "Copy /way line" from a map pin
opened an unseen box that held the keyboard. The pins' refusals go on the
map for the same reason (D15). The mock models both (the dialog at DIALOG
before its OnShow, the maximized map at FULLSCREEN).

# Commander_Orders — decisions

Numbered so later work can argue with them by name. D1-D30 are 3.0's
decisions (2026-10-04), the release that rebuilt Orders into the suite's own
navigation and retired TomTom; D31-D41 are 3.1's (2026-10-05), "Go to"
everywhere: one API, one button, one set of words and gestures, the locator,
the coordinates and the chat links. Where 3.1 changed an older entry, that
entry says so in a "(3.1: ...)" note and names the new one. The 2.x module's defects are cited as "2.x defect Dn": the
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
a sealed environment where touching any other global raises. (3.1: eleven
files, in this TOC order: Data, Entrances (generated door data, D37), Geo,
Store, DB, CommanderOrders, Locate (D36), Pins, Coords (D39), Chat (D38), UI;
`O.Entrances`, `O.Coords` and `O.Chat` join the sub-tables. The three new
code files build on the public API and `O.R` only, as Pins and UI do. A new
file is a full client restart, never a /reload.)

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
there". (3.1: resolvers, then the shipped door table, then the client's list,
D37; Orphan-typed instance maps count as dungeons, D37; new legs, the nearest
departure among equal ways and the Teldrassil island, D40.) Combat layout never changes by default: HideInCombat, HideInInstances
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
clear of Commander_Minimap's zone name. (3.1: 38 while Minimap Coordinates
puts a label under that name; the world-map readout is AUTO / ON / OFF
instead of stepping aside whenever Questie's is on; a nearest-of-N
waypoint's every pin names its own spawn: D39.)

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
(3.1: they post the readable ChatText line through C_ChatInfo.SendChatMessage,
a GoButton's Shift-click among the clicks; dialogs stack; D40.)
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
Places titled "Rally N". (3.1: the list grows by D32; the pinned record and the
active route survive a reload whoever made them, D33.)

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
follow-up). (3.1: every consumer has a row in both tables, Quartermaster
included (it asks the locator at runtime, D36), and the new tints PVP, NOTE,
FARM, UNIT and BANK; the pinned record outlives a reload, D33; the 60-module
coverage table is in Harness/README, D41.)

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
for the user's own actions only; consumers print their own. (3.1: a Go a
module asks for on the user's behalf is the user's own action, so Orders says
"Waypoint set: ..." for it under Announce and the modules print nothing, D31;
the round's settings, D40.)

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

---

# 3.1 (2026-10-05): "Go to" everywhere

The user's brief: "focus on the waypoints and coords, finish the upgrade and
complete integration of 'go to' buttons across ALL of the Commander apps".
The contract was the session's SPEC with the completeness critic's
corrections adopted (critic D1-D13). Nothing below has been seen in game;
ASSUMPTIONS A46-A61 are the checks, with Test: lines.

**D31 — "Go to": one set of words, one set of gestures.** Before 3.1, 14
modules had a Go-to and each carried its own Orders lookup, its own /way
formatter (ten of them, disagreeing on titles and precision), its own
refusal words and tooltip. Now there is one of each, and every consumer
cites this entry.

- *Words.* "Go" on a row button; "Go to <Thing>" on a standalone one ("Go to
  Entrance", "Go to Bank", "Go to Farm", "Go to Turn-in", "Go to the Flag");
  "[Go]" for a chat link; "Waypoint" is only the noun for the record. A lit
  button reads "Going" / "Going to <Thing>". A unit follow is an arrow, not a
  place: "Arrow To Them" (Contacts' Title Case menus), "Arrow to My Target"
  (PartyFrames' binding). Menus keep their module's case ("Go To This Note").
- *A button* is `Commander.UI.GoButton(parent, opts)` (Commander_Events
  CommanderGoButton.lua; every module requires Events, only some list Orders).
  Click = `CommanderOrders.GoTo(spec or query, opts)` under (source, key);
  Shift-click = `SharePoint(place, "CHAT")`, the readable ChatText line in the
  group's chat, else /say; Ctrl-click = `CopyText(WayLineFor(...))`. The
  tooltip says "Go to: <title> - <zone> <x, y>", the clicks ("Shift-click:
  share in chat. Ctrl-click: copy a /way line.") and, in red, why it cannot go.
  It greys out while Orders is turned off or loading, without Orders for a
  query, and when the spec or query answers nothing; a spec or query function
  may answer `nil, reason` (an Orders reason code or a sentence of the
  module's own: Guide's "You are already inside"). Greyed for Orders' own
  state (off, loading, absent for a query) its tooltip leaves out the
  module's extra line, which says what a press does (review-r2); a reason
  of the spec's or query's own keeps it. A greyed button still
  explains itself: it runs its motion scripts while disabled
  (`SetMotionScriptsWhileDisabled(true)`; 2.5.6 gives a disabled Button no
  OnEnter otherwise, so before the 3.1 review no player ever saw the red
  line) and, as the client rules, takes no click. An enabled query whose
  lookup answers nothing now (Questie loading or absent, none on your
  landmass) shows Orders' reason in the same red line instead of "Go to:"
  and clicks that would only print it. It is lit while
  `IsGoing(source, key)`, refreshed on CHANGED and UPDATE and in its OnShow
  (a button made before Orders loaded starts listening on its first refresh
  that finds Orders' events). `opts.key` is read after the spec runs, so a
  spec function may re-point a pooled button (QuestLog, Guide). Without
  Orders a spec still prints its /way line (formatted locally) and a query
  says "Needs Commander Orders". A plain Button, never secure; the SPEC's em
  dash and middle dot became " - " and a full stop (suite D11).
- *A coordinate surface* (the coordinate block, the TopBar's coordinates,
  Commander_Minimap's label, an Orders chat link): Left = Go (a waypoint
  there, or where you stand, with the arrow on it), Shift = share (typed into
  an open chat box as ChatText, else posted like a GoButton), Ctrl = copy the
  /way line, Right = a menu, the manager one of its entries. The block, the
  TopBar and the label all call `CommanderOrders.Coords.Gesture`; the links
  are CommanderOrdersChat.lua's (D38).
- *A list row with no room for a button*: Ctrl+Right-click = Go (the map's
  MapClickModifier CTRL, the user's saved value), with
  `Commander.UI.GoRowHint` ("Ctrl+Right-click: Go") in the row's tooltip:
  QuestLog's Log rows, Quartermaster's rows, Tradecraft's reagent rows,
  Formulary's rank readout. Rows whose plain right-click already set a
  waypoint (QuestLog's Zones, Reputations and drawer rows) keep it.
- *Feedback.* A Go the user asked for is `GoTo` not silent: Orders says
  "Waypoint set: <title> (<Zone x, y>)" under Announce (on by default), or ONE
  refusal line, `Reason(why)` plus ": <title> (<Zone x, y>)" and the place's
  [Go] link when the coordinates are known. The modules' own confirmation and
  refusal tables are gone. An automatic offer is `silent`, `temporary` and
  `setArrow = false` (Adjutant's, Promotion's, Objectives', Ping's automatic
  waypoint, Oracle's flag re-point, PartyFrames' roster re-point).

Cited by QuestLog D45, Guide D12, Tradecraft D18, Formulary D15, Spoils D24,
Notebook D11, Contacts D12, Armory D18 and Vault D48, and by the Harness
READMEs of Bags, Logistics, Ping, TopBar, Comms and PartyFrames.

**D32 — The 3.1 API (D21's list grows).** Every function is pcall'd at the
boundary as before; `Locate`, `Linkify` and `ClaimChatLink` guard
themselves, and the `Coords` functions are called guarded by their hosts
(Commander_Minimap and the TopBar pcall them).

- `GoTo(target, opts) -> uid | nil, reason`. `target`: a place `{ map, x, y
  [, title] [, alternatives] }` (0..1; a continent point lands on its zone as
  Add's does), a unit follow `{ kind = "unit", unit = token | guid = GUID }`,
  or a query for `Locate` (`npc`, `object`, `townsfolk`, `entrance`,
  `itemVendor`, `itemSource`; D36). Many places become ONE waypoint,
  measured from you or, inside a dungeon or raid (no UnitPosition), from the
  instance's door, which stands in for you (the door table; 3.1 review),
  found from your dungeon uiMap, else from the instance id (GetInstanceInfo's
  8th) for Magisters' Terrace, which has no uiMap on 2.5.6 (review-r2). The
  candidates are the places on that landmass and on an island of the same
  continent frame (D40); the nearest wins (whole centimetres, a tie keeps the
  list's order) and the places on ITS landmass, nearest first, at most 256
  (the Store's cap), are the `alternatives` the arrow follows by D6's
  hysteresis. With no candidate, the list landmass by landmass, those one
  cited leg away first, each in the order given; with nothing to measure
  from, the places on your continent first. Never cut at 256 in the given
  order before that (Mortog Steamhead was the 260th repairer of 268, and the
  nearest from Serpentshrine's door). World positions come from each map's
  two probes and arithmetic (A53), never a Vector2D pair a place. The title
  is the caller's, else the list's own
  ("Nearest innkeeper"), else the places' shared one. `opts`: source, key,
  title, icon, note, setArrow (default true), persistent, temporary,
  clearOnArrive, arrive, colour, silent (D31's feedback).
- `IsGoing(source[, key])`: the arrow's target is (source, key)'s; a route
  stop answers for its route's owner; a nil key matches any key of the source.
- `PlaceFor(target) -> { map, x, y, title, alternatives[, elsewhere] } | nil,
  reason`: the spot GoTo would point at first, for a Shift- or Ctrl-click and
  the tooltips. A query is measured once (in Resolve), not again. "The
  nearest <townsfolk>" with no candidate on your landmass (or the island
  beside it) is `nil, "elsewhere"`, never a starting-zone trainer from
  Outland (Promotion's and Vitals' lines stay quiet, as their comments
  promise); with nothing to measure from, `nil, "instance"` or `nil, "no
  position"`. Any other target answers its first place, `elsewhere = true`
  when it is not on your landmass. GoTo still goes in every case: the arrow
  shows the crossing.
- `Reason(why) -> sentence`: the one refusal vocabulary, `Data.REASONS`:
  disabled "Commander Orders is turned off (/corder)", loading "Commander
  Orders is still loading", nowhere "No known location", nomap "No map for
  that place", nocoords "No coordinates for that place", instance "No position
  inside instances", otherside "Only the other faction has one", elsewhere
  "None on your landmass" (3.1 review), noquestie
  "Needs Questie to look that up", notready "Questie is still loading",
  needsorders "Needs Commander Orders", noquery "Nothing to look up", unknown
  "Commander Orders cannot look that up", error "Something went wrong (see your
  error log)", and the 3.0 answers kept as codes so no consumer's comparison
  breaks ("no world position", "no position", "invalid unit", "invalid
  position", "unknown waypoint", "not in a group", "no chat", "chat is locked
  down", "no guide", "unknown place", "no stops", "no fields", ...). An
  unknown code (or a module's own sentence) comes back capitalised.
- Words for a place: `FormatCoords(x01, y01[, decimals])` ("45.2, 66.8", at
  CoordDecimals by default), `WayLineFor(map, x01, y01, title)` (always 2 dp),
  `ChatText(map, x01, y01, title)` ("Title - Hellfire Peninsula 45.2, 66.8
  (/way #1944 45.20 66.80)", never starting with "/", at most 255 bytes),
  `ChatLink(map, x01, y01, title[, text])` and `ParseChatLink(link)` (D38),
  `CopyText(text)` (the copy box, D40), `ParseCoords(text)` (what /way would
  make of a typed line).
- Places: `SaveAsPlace(uid[, title])` (at the spot the arrow follows) and
  `MarkPlace(title[, at])` (`at = { map, x, y }` instead of where you stand).
- `Entrance(uiMap | { instance = id })`: the door table, then the
  registered resolvers for a uiMap it does not know, then the client (D37,
  the lead's decision); a door's alternatives are copied out too.
- `Locate(query) -> places | nil, reason` (D36; a stand-in answering
  "loading" until CommanderOrdersLocate.lua replaces it);
  `RegisterResolver` widened with "townsfolk" and "npc" (D36).
- `Linkify(text, ctx)` and `ClaimChatLink(link, fn)` (D38); `Coords` (D39:
  Read, Text, Here, Gesture, Tooltip, Waypoint, Share, Copy, Menu,
  MinimapText, WantsMinimapClick, MinimapPoint, MinimapClick, Command).
- For the other Orders files (`O.R`): Decimals, AskCoords, TypedCoords,
  UnitForGuid, RemapUnits, DoorLookup (the locator's to set), LocateState;
  `Store:Retarget(uid, unit)`, `Store:Closest(ctx, anyOwner)`; Geo: Zone,
  PlainText, ChatText, ChatLink, ParseChatLink, LinkEscape / LinkUnescape,
  LINK_PREFIX, `env.islands`; Data: REASONS, ISLANDS, CLOSEST_SCOPES,
  MAP_COORDS, the new ICON_COLOURS keys. One new dialog,
  `COMMANDER_ORDERS_COORDS`; no new global.
- In Commander_Events: `Commander.UI.GoButton`, `Commander.UI.GoRowHint`,
  `Commander.UI.RefreshGoButtons`.

**D33 — Persistence, amended: the pinned target and the active route survive
a reload (critic D5).** 3.0 kept consumer records session-only (D21, D22),
so a Go pressed before a /reload pointed at nothing after it. Now the Store's
Serialize keeps the record the arrow is PINNED to and the ACTIVE route even
when they are session-only, and (3.1 review) the record a pinned "Guide me"
hop leads to: the hop names it in `guideFor` (a persisted field), the Store
keeps it beside the hop under the same two exclusions, and LoadStore
restores the runtime's guide link, so a crossing made off the hop's spot
after a /reload still hands the arrow back instead of pointing across it. They load still session-only, so the next save
keeps them only while they hold the arrow: everything else a consumer made
stays session-only, and nothing piles up. Two exclusions: a unit follow (a
token is another member after a relog) and a temporary offer (a group ping,
a battleground node, a repair offer: the moment is gone; Commander_Ping's
"gone after a reload" check holds it to that). Routes save their persistent
flag; a 3.0 save's routes load as persistent. A persisted record needs its
owner to clear it: QuestLog removes every key of a quest on QUEST_TURNED_IN
and QUEST_REMOVED (QuestLog D45), Logistics' vendor waypoint goes at any
merchant, Oracle's go when the battleground ends.

**D34 — The battleground hedge (critic D6).** UnitPosition may answer
nothing inside a battleground (A1 is unproven either way) while the map
position does. When `UnitPosition("player")` answers nothing and
`IsInInstance()` says "pvp", the player's world position is the map position
through `Geo.ToWorld`, sampled at most ten times a second (a Vector2D a
call). Group members are not hedged. Oracle's Arathi pips and its WSG/EotS
"Go to the Flag" work through it if only the map position answers, and so
does the coordinate block's reading. A46 settles it.

**D35 — Follow the Closest keeps to your zone, and to your own (S3).**
`ClosestScope` "ZONE" (the default, TomTom's rule) or "LANDMASS" (3.0's): in
the zone scope a candidate's spot (a nearest-of-N waypoint's chosen spawn)
must share the player's zone (`Geo.Zone` of both maps). `ClosestMineOnly`
(on): records whose source is "TomTom:*" (Questie's and WhatsTraining's asks
through the bridge) are left out; every Commander module's records count as
the user's own. `/cway` and "Point at the closest" follow both; the bridge's
own GetClosestWaypoint / SetClosestWaypoint pass `anyOwner` and see
everything, because TomTom's callers expect their own waypoints there.
`/cway` with nothing in scope names the setting. A capital is part of the
zone around it (the lead's decision, 3.1 review): every capital is a Zone map
whose parent is the continent (UiMap.csv: Stormwind City 1453 and Elwynn
Forest 1429 both hang off 1415), so `Data.CITY_ZONES` folds each into its
zone (Stormwind into Elwynn, Orgrimmar into Durotar, Ironforge into Dun
Morogh, Thunder Bluff into Mulgore, Darnassus into Teldrassil, Undercity
into Tirisfal, the Exodar into Azuremyst, Silvermoon into Eversong,
Shattrath into Terokkar) in this scope ONLY: Geo.Zone stays the city, the
coordinate frame the block and the chat links read. "My landmass" restores
3.0.

**D36 — The locator: CommanderOrdersLocate.lua is the one Orders file that
names Questie (SPEC 3).** It mirrors QuestLog's rule for its adapter, so
when Questie changes shape the damage is one file wide and a Go button says
"Needs Questie to look that up", never a Lua error. Every read is
feature-detected and pcall'd, and nothing is decided at load (Orders loads
before Questie and QuestieDB). What answers, in order:

1. Registered resolvers. "townsfolk" ones are MERGED with Questie's lists (a
   learned place stands for Questie's spawn of the same NPC on that map, or
   any Questie place within 0.002 of it); "npc" ones answer FIRST.
   `RegisterResolver("townsfolk", fn(kind, query))`,
   `RegisterResolver("npc", fn(idOrName, query))`, each answering nil, a list
   of `{ map, x, y, title?, npc? }` or one such table. Logistics registers its
   learned book for BOTH "Repair" and "Vendor" (a repair vendor is a vendor).
2. QuestieDB's public contract (`LibQuestieDB.RequireContract(2)`): NPC,
   object and item reads.
3. Questie's Townsfolk module (`QuestieLoader._modules.Townsfolk`, internal:
   a REQUIRED-list probe, pcall, never ImportModule) and
   `Questie.db.char.vendorList`, for the "nearest X" kinds.
4. The shipped door table (D37).

Kinds: `npc` (id, exact name or a list of ids; an NPC found only inside an
instance answers its door: QuestieDB's {-1, -1} spawn), `object`,
`townsfolk` (Repair, Vendor, Innkeeper, Banker, Auctioneer, Flight Master,
Battlemaster, Weapon Master, Stable Master, Spirit Healer, Mailbox, Meeting
Stone, Class Trainer [class], Portal Trainer, Profession Trainer [profession]
or "<Profession> Trainer", and the vendor lists Reagents, Poisons, Trade
Goods, Bags, Potions, Food, Drink, Ammo; aliases folded: "inn", "fp", "ah",
"bank", "water", ...), `itemVendor`, `itemSource` (vendors, then droppers,
then containers; an instance source answers its door) and `entrance` (a
uiMap, `{ instance = id }` or `{ area = questieAreaId }`). Faction-filtered as
Questie's own map is (friendlyToFaction, its NPC blacklist). List titles are
"Nearest <words>". The reasons it answers are D32's codes (noquery,
unknown, noquestie, notready, nowhere, otherside, instance, error). Hover is
cheap: every list is built once per Questie source table and every id, name
and item answer memoized; all of it is dropped when Questie says it is ready,
and then the eight common lists are built one per 0.1 s, never in combat. A
NAME query builds QuestieDB's name index once (55 ms under luajit): modules
pass ids. Without Questie only resolvers answer. A shipped townsfolk table
for players without Questie is a follow-up (D41).

**D37 — The door table (SPEC 3, critic D4).** `Harness/make_entrances.py`
writes `CommanderOrdersEntrances.lua` from the client's AreaTrigger DB2 (build
2.5.6.69795) joined to the CMaNGOS `areatrigger_teleport` table: 51
instances, 65 doors, 113 dungeon uiMaps and 113 Questie areaIds, `--check`
byte for byte (it needs the DB2 CSVs: `--fetch --db2 DIR`). A door's zone is
its dungeon map's parent when the trigger lies inside that zone, else
Formulary's boundary rule (the rule alone put Wailing Caverns in Mulgore). 23
instances whose portal is in a cave, a mountain or under a lake ship their
outdoor mouth (an "approach", each row citing its source) when any door is
more than 100 yd from it; several doors become alternatives and the arrow
takes the nearest. The research's "matches Questie within 0.3 map-%" held for
10 of 51; every instance's verdict is in the file's header, and a new
disagreement is flagged UNREVIEWED. `Entrance()` asks the registered
resolvers, then this table (`R.DoorLookup`), then
C_EncounterJournal; it takes `{ instance = id }` too (Guide and Formulary key
by instance id), and Orphan-typed instance maps (mapType 6: the Black Morass
273, Old Hillsbrad 274, Hyjal 329, Zul'Aman 333) count as dungeons in the
hint, the landmass name and the client lookup. Guide adopted the table
(Guide D12) without registering its own as a resolver. DECIDED (the lead,
3.1 review; was OPEN): the table comes FIRST for every dungeon it knows, and
the registered resolvers answer only what it lacks (QuestLog's, from
Questie's dungeon list, keeps working for those). So the corpse run, the
arrow's dungeon hint and a uiMap-keyed `{ entrance = map }` get the reviewed
door with every door or approach as alternatives (the corpse record carries
them now, so the nearest door wins). QuestLog's own givers and objectives
inside a dungeon (the {-1, -1} spawn) now ask `CommanderOrders.Locate({
entrance = area })` for the door too, falling back to Questie's spot only when
Orders has none (QuestLog, 3.1 review round 2), so every Go into a dungeon
points at the same door.

**D38 — Places in chat you can click (SPEC 4, CHAT).**
CommanderOrdersChat.lua adds a [Go] link after a place someone types:
tier A, a `/way`, `/tway` or `/tomtomway` line (any case); tier B, "Zone x,
y" when up to four words before the pair fold to exactly one zone name or an
alias of four letters or more. There is no bare "x, y" tier (critic D7: "2,
5" in Trade is not a place). A bare `/way 45 66` takes the sender's map: your
own line, a group member's (their map), or SAY, YELL, EMOTE and the zone's
General and LocalDefense channels (zoneChannelID 1 and 22, assumed: A48);
anything else gets no link. The map is raised to its zone and written into
the link, so a later click never guesses. Orders' own shared line ("Title -
Zone x, y (/way ...)") gets ONE link, its title read back. The filter
(critic D10) goes through `ChatFrameUtil.AddMessageEventFilter` (the
deprecated global only as a fallback) on 17 events (not SYSTEM, MONSTER or
LOOT), hands back all fourteen arguments or a bare false, keeps the last 64
lines by lineID, reads plain text only (links, colours, textures, kstrings
and {...} skipped whole), rejects a line with no digit in one find, adds at
most four links, and contains its errors (five reports a session).

The link is LOCAL: `|cff71d5ff|Haddon:CommanderOrders:w:<map>:<x %.4f>:<y
%.4f>:<title>|h[Go]|h|r`, the title plain words, at most 120 bytes (60 from
a typed /way), braces dropped, and `%`, `:`, `|`, `[`, `]` and control
characters %XX-escaped, so Blizzard's formatting after the filters (% doubled,
{...} icons, runs of spaces) leaves it whole; it round-trips map, x, y within
5e-5 and the title exactly. What is SENT is ChatText. The click travels
OnHyperlinkClick, SetItemRef, LinkUtil's "addon" handler, EventRegistry
"SetItemRef"; hover is EventRegistry "ChatFrame.OnHyperlinkEnter" /
"OnHyperlinkLeave" (read in the 2.5.6 source): one owner table, nothing
hooked or replaced. Gestures are D31's; the menu: Go, Add without the arrow,
Open the map here, Share with group, Post in chat, Copy /way line, Save as
place. `Linkify(text, ctx)` serves text that never passed the filters
(Contacts' logged lines); `ClaimChatLink(link, fn)` lets a module keep a
printed link's plain click for the session (Ping's callout moves its one
"Ping" waypoint; Oracle's `/coracle nodes`), the last 64 kept, a lost claim
falling back to the plain Go. Ping's `[Waypoint]` link, an index into a
20-ping list that died on a reload, folded into this one (map:x:y survives).
One setting, ChatLinks, covers both tiers. Known false positive: a level
range written with a space ("Hellfire Peninsula 58 60").

**D39 — Your coordinates, visible by default (SPEC 4, COORDS; the block
opt-in since the 3.1 review).** On this
install the player saw no Commander coordinates anywhere (critic 2: the
TopBar segment off, Questie's minimap numbers in a zone text Commander_Minimap
hides, Orders' map readout stepping aside for Questie's). Now:

- *The coordinate block* (CommanderOrdersCoords.lua): OFF by default (the
  lead's decision, 3.1 review: `CoordsBlock` false; a saved value is kept as
  it is, no migration), so Commander_Minimap's label is the default surface;
  the label's right-click menu, and every surface but the block, offers
  "Show the coordinate block". The shared HUD chrome (prefix "Coords", style
  SOLID, TOP +240, -504, under the Orders arrow's default box, 150 wide, LOW
  strata). Not under the minimap any more: 3.1's TOPRIGHT -21, -208 sat in
  the right column where 2.5.6 manages the quest tracker (QuestWatchFrame,
  right-aligned from 192 down, up to about 290 wide) and its lines 2 to 5
  drew over the block (review: render; A65). It shows "42.0, 65.5" over the
  subzone (gold) and the zone (grey), "--" with no position. An unconditional 0.2 s throttle, written
  only on change (critic 1.6: taxis, boats, knockbacks move you without a
  movement event). It reads UnitPosition through each map's world rectangle
  (two GetWorldPosFromMapPos probes per map, kept), never a Vector2D five
  times a second, and speaks in ZONE numbers (Geo.Zone), so a cave or a city
  sub-map reads like the world map. First chromed out of combat (D10), its
  click surface a child Button under the drag overlay; unnamed, no global,
  no secure child; no scale grip on a small plate. `/corder coords` [on | off
  | lock | unlock | reset | 0 | 1 | 2 | where].
- *MapCoords* AUTO | ON | OFF (the world-map readout, Pins): AUTO shows ours
  when Questie's are off, OR the viewed map is not the player's (where
  Questie's "Player" is wrong), OR inside a dungeon or raid (Questie writes
  nothing there). A 3.0 boolean is repaired to AUTO / OFF in DB.Init;
  DBVersion stays 3.
- *CoordDecimals* (0..2, default 1) everywhere Orders writes readable
  coordinates; /way lines always carry 2.
- *Commander_Minimap* 2.5.0: a label under its zone name (MinimapCoords) and
  Ctrl+Right-click = a waypoint there (MinimapClick). Blizzard's
  Minimap_OnClick pings for ANY button, so the minimap's OnMouseUp is wrapped
  with SetScript, keeping whatever handler was there: Ctrl alone with the
  right button goes to Orders and never pings (no ping reaches the group, and
  Commander_Ping echoes no second waypoint); every other click runs the old
  handler. The placement is the exact inverse of Geo.MinimapPlace (square
  bounds when GetMinimapShape() says SQUARE, the facing turned back under
  rotateMinimap); past the zone's edge the smallest sibling zone takes it;
  outside the map's face nothing happens. Without Orders there is no label
  and every click pings as before.
- *Pins*: on a SQUARE minimap with the label on, the top edge chevron rides
  38 under the edge (D15's 22 otherwise); every world pin of a nearest-of-N
  waypoint names its own spawn and distance, and one the arrow is not on says
  so (M7).
- The label is on by default and the block off (the lead's decision), so
  the numbers show once; each has its switch.

**D40 — The smaller 3.1 fixes (SPEC 2).**
- `Update` goes through Add's zone and world checks (critic C11): a
  continent point lands on its zone, a spot with no world position is
  refused.
- Shares: the share dialog stacks (`multiple = true`, each with its own share
  as data; a second share no longer cancelled the first, critic D13); with no
  dialog the line carries the place's [Go] link (there is no inbox to point
  at); CHAT and SAY post ChatText through `C_ChatInfo.SendChatMessage` (the
  bare global is the deprecation shim, kept as the fallback; critic D11).
- The copy box: `maxLetters = 255` (2.5.6's pooled edit box keeps the last
  dialog's 24 or 40 otherwise) and "Ctrl+C to copy" (a pasted /way runs, it is
  not sent; critic D12).
- Connections (S7), every spot cited from QuestieDB: Grom'gol's zeppelin
  (npc 3149, Horde), Theramore's boat to Menethil (npc 12716 on the pier,
  INFERRED to be the dock: A57), Auberdine to Teldrassil (object 176365) and
  back (npc 3838, Rut'theran's hippogryph master). Shattrath's portals are
  named with no place (no citable spot); Exodar to Darnassus is not listed;
  Booty Bay to Ratchet stays text only. Among the first hops of every
  SHORTEST way the nearest departure wins (H3), a text-only hop only when
  nothing placed ties. `Data.ISLANDS`: Teldrassil and Darnassus are
  "1414:1:teldrassil", so the arrow names the crossing instead of pointing
  across the sea; the Isle of Quel'Danas stays on Quel'Thalas (its crossings
  are a portal and a taxi). An island must not hide the nearest place, though
  (3.1 review: from Auberdine the nearest bank was Everlook, 5,211 yd through
  Felwood, with Darnassus one boat away): "nearest" lists count the places on
  an island of the same continent frame, measured in a straight line (the
  same world frame), and when one wins the waypoint's choices are that
  island's alone, so the arrow shows the boat until you cross. A landmass a
  cited leg away in another frame (Outland, the Eastern Kingdoms from
  Kalimdor) is not counted: its arrival spot is not citable for every leg
  (the Menethil dock serves two boats, Ratchet's lands at an unplaced Booty
  Bay), so it only orders the "elsewhere" fallback (D32).
- Unit follows (S6): `{ kind = "unit", guid = ... }` finds the token; every
  follow remembers the member's GUID and is re-pointed after
  GROUP_ROSTER_UPDATE (`Store:Retarget`); a follow defaults to
  `clearOnArrive = false`. A35's "a token, not a person" no longer holds.
- The manager (S8): "Add at..." and "Move..." take typed coordinates through
  the `COMMANDER_ORDERS_COORDS` box (Geo.ParseWay, then Add or Update); "Save
  as place" keeps a waypoint as a named place. The arrow and pin menus gain
  Mark arrived, Save as place and Point at the closest. A place from a map
  click is a pin's Save as place (no new gesture).
- Settings (Orders owns every key of the round; the other files read them
  with these defaults): CoordDecimals 1, CoordsBlock off (it was on until the
  3.1 review; D39) and the Coords chrome keys (style SOLID), MapCoords AUTO, MinimapCoords on, MinimapClick on,
  ChatLinks on, ClosestScope ZONE, ClosestMineOnly on. The rows went into the
  existing sections (Behaviour: Closest Within, Only My Own and Shared; Map &
  Minimap: World Map Coordinates, Coordinate Block, Minimap Coordinates,
  Ctrl+Right-Click the Minimap, Coordinate Decimals and the block's chrome
  rows; Sharing: Clickable Places in Chat).
- TOC 3.1.0; the four new files (Entrances, Locate, Coords, Chat) and
  Commander_Events' CommanderGoButton.lua need a full client restart.
  Bindings.xml is unchanged.

**D41 — "Everywhere" is a table, and what is left.** Of the 60 Commander
modules (`ls -d Commander_*/`), 24 have Go surfaces, 2 are the
infrastructure (Orders, Events) and 34 hold no place a player walks to;
`Harness/README.md` has the row for every one, each N/A with its reason, so
"all" can be checked. One owner per offer (critic S9): Logistics owns the
repair and vendor supply lines (Adjutant's repair and full-bags offers ask
it), Promotion owns the level-up class-trainer offer (Adjutant adds none),
Objectives owns the turn-in offer (off by default). The consumers' new
globals are documented entry points, listed under the table. Left to Devin:
PartyFrames' click-cast
rows fire every binding on both the down and the up phase (it is ours;
menus act on the up phase only, so spells, macros and targets double; the
fix needs 2.5.6's "downbutton" remap per phase and an in-game test, and was
not built); Tradecraft keeps its Set Waypoints switch and Formulary has none
(critic D7's "pick one" left as it was). Follow-ups, not built (critic's
COULD list and the builders' asks): a shipped townsfolk / stations table for
players without Questie; flight, hearth, graveyard, station and town kinds;
per-kind pin icons; arrow alpha and strata; RXP coexistence; more bindings
(nearest repair or bank, follow my target from Orders); route reorder, loop
and share; TOMTOM4 send; an inbox; guild share in the menus; LDB feeds
(replaced by TopBar segments); `/corder status` printing `R.LocateState()`;
`Commander.UI.WayLine` for the consumers' last no-Orders formatter;
`CommanderOrders.Nearest(query)` / `DistanceTo(place)` (a nearest place with
its own title and yards, which Logistics, Vitals and Promotion work out
themselves). (Commander_Chat's mirror window now fires the same
EventRegistry hover events as Blizzard's chat frame, so the [Go] hover card
shows there too: Commander_Chat 2.1.1.)

**D42 — The 3.1 review's fixes, and the lead's three decisions (2026-10-05).**
Six review lenses (client fidelity, the locator on real Questie, the core,
consistency, pictures, cost) made twelve findings (one of them found twice);
every one is fixed here
except where a consumer must follow, and each fix has a harness check that
fails on the code before it (README: 22 mutants, all killed). The lead
decided: (1) the door table outranks a registered entrance resolver for
every dungeon it knows (D37); (2) the coordinate block is off by default and
the minimap label on, the label offering D31's gestures (it calls
`Coords.Gesture` and `Coords.Tooltip`) and the block (D39); (3) Follow the
Closest's zone scope counts a capital as part of its zone (D35). The fixes:
"Open the map here" through ToggleWorldMap and SetMapID, because 2.5.6's
OpenWorldMap raises (D38, A62); a greyed Go button runs its motion scripts
while disabled, and an enabled query's lookup reason shows (D31, A63);
"nearest" from inside an instance measured from its door and sorted before
the 256 cap (D32, A64); PlaceFor's "elsewhere" (D32); the island beside your
landmass counted (D40, A68); a "Guide me" hop's target and link survive a
/reload (D33, A66); the block's default spot moved off the quest tracker
(D39, A65); world positions by each map's two probes and arithmetic, and a
query measured once (D32, A53; a nearest-of-600 hover made 1,200 Vector2Ds);
the corpse run with every door. The harness mock was blind to two of them:
`M.Click` now delivers nothing to a disabled Button and `M.Hover` runs its
OnEnter only with motion scripts on, and the chat harness's world map is
2.5.6's (OpenWorldMap raises). Left to the consumers' owners (their files):
Formulary, Tradecraft and the Quest Log say in their own tooltip lines that
a press of a greyed Go prints in chat, which the client never delivers
(their GoButton's red line already says why); QuestLog's sentinel branch
(D37); `questlog_orders_contract.lua` B expects its resolver's door for the
Ramparts, where the table's now answers (the lead's decision 1).
The second review (review-r2) added three: Magisters' Terrace has no uiMap
on 2.5.6, so "nearest" from inside it and a death in it now find its door
by the instance id (GetInstanceInfo's 8th; D32, A64; the corpse record keeps
`instanceID`); a greyed Go leaves out its module's line while Orders is off,
loading or absent, since those lines describe a press (D31, A63; the
consumers' own wording is their owners' to fix as well); and the harness
README's counts, Chat's hover row and Logistics' GoButtons and global were
brought up to date.

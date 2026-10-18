# Commander Logistics — harness

Run from the AddOns directory (it finds the AddOns root from its own path, so
a worktree works too):

    /opt/homebrew/bin/luajit Commander_Logistics/Harness/logistics_orders_smoke.lua   # 236 checks

Never loaded by the client (not in the TOC). Must exit 0 before a Logistics
or Adjutant repair change ships.

`logistics_orders_smoke.lua` tests the 2.2.0 repair vendors where they
actually live: Logistics learns them, Commander Adjutant's durability alert
offers the nearest one, and Commander Orders points at it. So it boots the
client mock Orders' own harnesses use
(`Commander_Orders/Harness/orders_mock.lua`: this build's UiMap DB2 rows as
the world, the REAL `Commander_Events` settings framework, every Orders
file) and loads Logistics and Adjutant on top, as one session would.

- **A** boot: both modules load clean beside Orders, the defaults (Remember
  Repair Vendors and Mark the Nearest Repair on; the vendor book is data and
  not a default, so Restore Defaults never forgets it), and the globals they
  write are only their documented ones.
- **B** learning: a repair merchant is remembered with the player's map
  position, UnitPosition's north and west (never crossed), the world instance
  and the landmass; a merchant who cannot repair is not, nor a vendor met
  with no position (instances); both switches; a revisit updates rather than
  twins; the per-faction cap drops the oldest sighting.
- **C** nearest: by real yards; from Eversong neither the Outland smith (same
  instance 530, other landmass) nor the Eastern Kingdoms ones (instance 0)
  count, from Hellfire the Thrallmar smith does and the Eversong one does
  not; no position inside instances; each faction its own book.
- **D** the waypoint on the real Orders (made through `CommanderOrders.GoTo`
  since 2.3.0): keyed (Logistics, repair), takes the arrow, worded once by
  Orders ("Waypoint set: Repair: ..."), the arrow's distance equals Logistics'
  distance, a second request moves the same record, any repair merchant takes
  it down and a grocer does not; Orders turned off (its own words, from
  `CommanderOrders.Reason`) and Orders absent both print the `/way` line.
- **E** Adjutant end to end: the banner names the vendor and its distance;
  the mark is temporary and never takes the arrow from the player's own
  waypoint, but has it once that is gone; nothing appears in combat until the
  fight ends; mended gear takes it down; switched off it names but never marks.
  The offer never ASKS for the arrow (an offer that asked could still re-pin
  it away from a mark of yours followed as the closest, or out of a Clear),
  so it leaves a running route, a mark of yours followed as the closest, and
  a Clear alone, and with nothing of yours it is followed as the closest,
  never pinned. The offer and a request share (Logistics, repair), one
  record: an offer you then ask for yourself is yours (no longer temporary),
  so mended gear leaves it and a repair merchant still takes it down; and in
  the other order an alert over your own repair waypoint is refused
  ("yours") and leaves it as it was (review 2026-10-05).
- **F** the settings pages and `/clog repair`, Forget Repair Vendors. Go to
  Nearest Repair and Go to Nearest Vendor are `Commander.UI.GoButton`s on the
  REAL GoButton (Orders D31; review 2026-10-05: they were plain buttons):
  owned by Logistics on their keys, a click is the request `/clog repair`
  makes (yours, the arrow on it, worded once by Orders), the button reads
  "Going to Nearest Repair" while the arrow is there, Ctrl-click opens
  Orders' copy box with the vendor's `/way` line, Shift-click shares the
  nearest vendor in chat, neither gesture sets a waypoint, and with no repair
  on the continent the button greys out with Logistics' own sentence
  (`CommanderLogistics_SupplySpec`, nil and the line's reason).
- **G** the consumer contract for the other modules wired in the same change:
  Commander_Guide's own `E.EntranceSpec` (Karazhan's two doors, the arrow
  taking the nearer, also when a resolver answered only Questie's first door,
  as the Quest Log's does), `CommanderOrders.Entrance` (nil, the client's list, a
  registered resolver first, a copy handed out), Commander_Spoils' farm spec
  and Commander_PartyFrames' unit follow (navigates to the ally at the live
  distance; a re-pointed follow keeps its uid and never re-takes the arrow;
  pets and the player are refused, which is why PartyFrames filters them
  first). Those modules' own harnesses test their halves against a recording
  stub; this is where the real Orders says yes. (Orders 3.1: G keeps these
  3.0 `Add` shapes on purpose, as the legacy path. Spoils and PartyFrames
  now call `GoTo` (Spoils with the FARM icon, PartyFrames with the member's
  GUID and the UNIT icon); the real Orders answering those shapes is
  `Commander_Spoils/Harness/spoils_orders_smoke.lua` and, for a unit follow
  by GUID through a roster shuffle,
  `Commander_Contacts/Harness/contacts_orders_smoke.lua`.)
- **H** one pass of the repair flow with every Orders file loaded, its map
  pins and manager included (A to G leave them out, as Orders' own runtime
  harness does, so a fault there cannot hide behind these checks).
- **I** the supply lines through Orders' locator (2.3.0, Orders 3.1): the
  learned book answers `CommanderOrders.Locate({ townsfolk = "Repair" })` and
  `"Vendor"` as a registered resolver (not other kinds, not while Logistics is
  off), merged with a second source standing in for Questie's lists; the
  nearest of all on the landmass wins (by yards, never across 530's two
  landmasses); the repair and vendor waypoints go through `GoTo` on their own
  keys and any merchant takes the vendor one down; a learned vendor is stored
  at its own spawn when the locator knows one within 40 yd, else at your
  spot; Adjutant's full-bags alert names and offers the nearest vendor (never
  in combat, withdrawn by a free slot or a merchant, its switch); `/clog
  vendor`. The full-bags offer and `/clog vendor` share (Logistics, vendor):
  yours first, then full bags, and the offer is refused, your waypoint left
  yours and a freed slot leaving it; the offer first, then `/clog vendor`,
  and the record is yours with the arrow on it, a slot freed on the way
  leaves it under the arrow, and a merchant takes it down; an offer nobody
  took over is still withdrawn by a free slot (review 2026-10-05: the
  withdrawal took the waypoint you asked for from under the arrow).

A to G boot Orders without its locator file (`CommanderOrdersLocate.lua`,
3.1) as well as without the pins and the manager: the locator's shipped door
table answers the entrances section G expects to be unknown, and A to G pin
the learned-book path that runs when the locator answers nothing. H and I
load it.

Mutation sweep (2026-10-04, by hand in the session scratchpad): 17 mutants
of Logistics, Adjutant's offer and `CommanderOrders.Entrance` (landmass and
instance checks, crossed axes, the merchant clear, the temporary flag, the
cap, the repair gate, the continent walk, the vendor key, the faction book,
the switches, the refusal reason, the `/way` line, the waypoint key, combat
deferral, the copy) are all killed. Since the 2026-10-04 review two more:
the repair offer asking for the arrow again (`setArrow = true`: six E checks
fail) and Guide's resolver path dropping the table's doors (two G checks).
Since the 2026-10-05 Go-to review five more, all killed: Adjutant's vendor
withdrawal without `offerOnly` (two I checks), its repair withdrawal without
it (one E), Logistics' offer refusal ("yours") removed (three E, two I),
`ClearSupplyWaypoint` ignoring `offerOnly` (one E, two I), and the settings
page building plain buttons again (F).

2.3.0 (Commander Orders 3.1, its "Go to everywhere" round): the waypoint goes
through `CommanderOrders.GoTo`, the refusals through `CommanderOrders.Reason`,
the `/way` line through `CommanderOrders.WayLineFor`; the words follow Orders'
one Go-to rule (Orders DECISIONS D31, the 3.1 words and gestures entry: "Go to
<Thing>" on a standalone button, the success line Orders' own). Three checks
were reworded for it: D "one line says so" and E "...says it was marked" now
read Orders' "Waypoint set: Repair: Goldshire Smith", and D "...in words"
reads Orders' "Commander Orders is turned off". The boot's SKIP list gained
`CommanderOrdersLocate` (see above). Orders' new files need a full client
restart, not a /reload.

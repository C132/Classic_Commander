# Commander Logistics — harness

Run from the AddOns directory (it finds the AddOns root from its own path, so
a worktree works too):

    /opt/homebrew/bin/luajit Commander_Logistics/Harness/logistics_orders_smoke.lua   # 159 checks

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
- **D** the waypoint on the real Orders: keyed (Logistics, repair), takes the
  arrow, the arrow's distance equals Logistics' distance, a second request
  moves the same record, any repair merchant takes it down and a grocer does
  not; Orders switched off and Orders absent both print the `/way` line.
- **E** Adjutant end to end: the banner names the vendor and its distance;
  the mark is temporary and never takes the arrow from the player's own
  waypoint, but has it once that is gone; nothing appears in combat until the
  fight ends; mended gear takes it down; switched off it names but never marks.
  The offer never ASKS for the arrow (Orders refuses a temporary pin only
  over a pinned waypoint), so it also leaves a running route, a mark of yours
  followed as the closest, and a Clear alone, and with nothing of yours it is
  followed as the closest, never pinned.
- **F** the settings pages and `/clog repair`, Forget Repair Vendors.
- **G** the consumer contract for the other modules wired in the same change:
  Commander_Guide's own `E.EntranceSpec` (Karazhan's two doors, the arrow
  taking the nearer, also when a resolver answered only Questie's first door,
  as the Quest Log's does), `CommanderOrders.Entrance` (nil, the client's list, a
  registered resolver first, a copy handed out), Commander_Spoils' farm spec
  and Commander_PartyFrames' unit follow (navigates to the ally at the live
  distance; a re-pointed follow keeps its uid and never re-takes the arrow;
  pets and the player are refused, which is why PartyFrames filters them
  first). Those modules' own harnesses test their halves against a recording
  stub; this is where the real Orders says yes.
- **H** one pass of the repair flow with every Orders file loaded, its map
  pins and manager included (A to G leave them out, as Orders' own runtime
  harness does, so a fault there cannot hide behind these checks).

Mutation sweep (2026-10-04, by hand in the session scratchpad): 17 mutants
of Logistics, Adjutant's offer and `CommanderOrders.Entrance` (landmass and
instance checks, crossed axes, the merchant clear, the temporary flag, the
cap, the repair gate, the continent walk, the vendor key, the faction book,
the switches, the refusal reason, the `/way` line, the waypoint key, combat
deferral, the copy) are all killed. Since the 2026-10-04 review two more:
the repair offer asking for the arrow again (`setArrow = true`: six E checks
fail) and Guide's resolver path dropping the table's doors (two G checks).

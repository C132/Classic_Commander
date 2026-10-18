# Commander_Comms harness

One luajit harness, never loaded by the client (nothing here is in the TOC).
Run it with the compile-gate luajit; it must exit 0 before any Comms change
ships:

```bash
/opt/homebrew/bin/luajit Commander_Comms/Harness/comms_smoke.lua   # 188 checks
COMMS_RUNTIME=/path/copy.lua luajit .../comms_smoke.lua            # a mutated CommanderComms.lua
```

The AddOns path is absolute at the top of the file (`ADDONS`): adjust it if
the install moves. The mock is modelled on Commander_Chat's harness: the
combat log, the group, unit tokens, spell links, the client's own failure
strings and the Commander framework surface the module touches, all driven
by the checks. It prints `N checks, M failures` and exits non-zero on one
failure.

## What it covers, by release

- **2.3.0 callouts:** spell links in the interrupt, cleanse and CC-break
  announcements and every fallback down to a bare name; the kicked-on-me
  callout (school, lockout seconds, the kicker's class); the inferred channel
  kick the combat log never reports, with its false-positive guards (a
  natural end, a missed kick, a dead caster, a real SPELL_INTERRUPT already
  covering it).
- **2.4.0 battlegrounds:** quiet by default, and routed to the party you
  queued with when asked (every automatic callout, cleanse included); an
  arena is not a battleground.
- **2.6.0 failed casts:** range and line of sight whispered to the ally after
  a run of four (the heal-only gate, the run rules, the per-ally cooldown,
  cross-realm addressing, separate runs per reason, the no-cast-event
  fallback that reads the aim off the unit tokens); out of mana and
  crowd-controlled told to the group (the /oom latch, the mana-users-only
  rule, the named CC state, the battleground rule).
- **2.7.0 support calls:** a cooldown spent on one ally whispered to that
  ally, gated on your own spellbook, one per spell per ally.
- **2.8.0 mana burn:** a drain on any group member's mana told to the group
  with what is left (the mana-only and group-only gates, the threshold that
  adds small ticks up, the per-victim window, the deferred read of the bar,
  the battleground rule).
- **2.10.0 Rally on Me:** the chat line with the zone and coordinates, the
  spot shared through `CommanderOrders.SharePoint` (never a waypoint of your
  own), its setting, Orders missing, no map position, the binding and slash,
  the centre button clear of the ring of calls.
- **2.11.0 Rally on Me in Commander Orders 3.1's words** (the last block,
  "rally 3.1"): the coordinates are Orders' `FormatCoords` at the player's
  Coordinate Decimals (0, 1 and 2; the default 1 gives the 2.10 line), a
  share Orders refuses is said in Orders' words (`CommanderOrders.Reason`),
  and "not in a group" (the solo case) says nothing. No existing check was
  edited for it.

Rally on Me is Comms' only Go surface: a share to the group, not a Go of
your own. The words and gestures are Commander Orders' (its DECISIONS D31);
the suite-wide coverage table is in `Commander_Orders/Harness/README.md`.
After a change to Orders' public API, run this beside Orders' own harnesses.

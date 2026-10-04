# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit, from anywhere (each resolves the AddOns root
from its own path, so a worktree works too):

    /opt/homebrew/bin/luajit Commander_Recovery/Harness/recovery_release_smoke.lua   # 63 checks
    /opt/homebrew/bin/luajit Commander_Recovery/Harness/recovery_orders_smoke.lua    # 54 checks

Both must exit 0 before any Recovery change ships.

## recovery_release_smoke.lua — auto-release and the casualty flow

A WoW mock loading the REAL Commander_Events framework, with Commander Orders
as a recording stand-in for its public table.

Covers auto-release end to end: the delay before the first press, the retry
loop and the window that ends it, the chat line announced once per death
rather than once per press, and every hold — open world, arena (until opted
in), a self-resurrect on offer, an incoming resurrection, a decided match,
Feign Death's phantom `PLAYER_DEAD`, and both switches. Also the two things
auto-release had to leave intact: no order of Recovery's own on release, and
the death popup left standing while the release is unconfirmed (hiding it
early would strand the player with no manual way out).

Section **I** is the 2.3.0 hand-over of the corpse arrow to Commander Orders:
the 2.2 "Corpse Run Order: off" migrated into Orders' `CorpseArrow` at login
with the old keys (`CorpseOrder`, the account-wide `IssuedOrder`) dropped; the
legacy `CommanderOrders_IssueOrder` / `ClearOrder` never called; the "follow
the Commander Orders arrow" line a frame after the release and only when
Orders holds a corpse (never inside the event, never with the setting off,
Orders turned off or not loaded, never in a battleground); Feign Death not a
casualty and not swallowing the next real death; the settings checkbox
writing Orders' setting through its API; the tester saying what a release
would do.

The honest part of this mock is the death state: `UnitIsDead`/`UnitIsGhost`
are driven by hand and `RepopMe` only logs the press, so the retry loop is
tested against a server that has not answered yet — which is the only reason
that loop exists. `C_DeathInfo.GetSelfResurrectOptions` is mocked in place of
`HasSoulstone`, which does not exist on this client.

## recovery_orders_smoke.lua — Recovery with the real Commander Orders

Boots `Commander_Orders/Harness/orders_mock.lua` (the client Orders' own
harnesses share: this build's map rows, the real settings framework, every
Orders file in TOC order) and loads Recovery after Orders' `ADDON_LOADED`, as
the client does for an addon with `OptionalDeps: Commander_Orders`. Each boot
is a fresh client; a relog is two boots with the saved variables written and
read back between them.

- **A** the migration with Orders present: "off" becomes Orders' own
  `CorpseArrow = false`, "on" changes nothing, the old keys go, a later login
  leaves a choice the player made in Orders since alone.
- **B** Orders not loaded at the first 2.3 login: the choice is kept, and
  handed over at the first login where Orders is there.
- **C** an open-world death and release: exactly one corpse waypoint (Orders'
  own), no legacy order, the player's own mark untouched and the arrow handed
  back to it on resurrection; Recovery's report, its one "follow the arrow"
  line a frame after the release, and its recovery line.
- **D** Feign Death: no casualty, no corpse; the next real death reported.
- **E** a battleground death: Orders draws no corpse arrow, Recovery promises
  none.
- **F** the settings checkbox reads and writes Orders' setting; Recovery's
  globals are its own.

Mutation hooks: `RECOVERY_RUNTIME=/path/copy.lua` and `RECOVERY_DB=/path/copy.lua`
load a broken copy in place of the live file. Eight hand-made mutants (no
frame's delay before the release line, the legacy order put back, the Feign
Death guard dropped, the line said whatever Orders holds, the "off" dropped
when Orders is absent, no migration, the checkbox writing Recovery's own key,
"on" migrated as "off") each fail at least one check.

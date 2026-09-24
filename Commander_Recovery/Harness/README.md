# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit recovery_release_smoke.lua   # the 2.2.0 battleground
                                                          # auto-release under a WoW
                                                          # mock, loading the REAL
                                                          # Commander_Events
                                                          # framework (40 checks)

Covers auto-release end to end: the delay before the first press, the retry
loop and the window that ends it, the chat line announced once per death
rather than once per press, and every hold — open world, arena (until opted
in), a self-resurrect on offer, an incoming resurrection, a decided match,
Feign Death's phantom `PLAYER_DEAD`, and both switches. Also the two things
auto-release had to leave intact: the corpse-run order still issued on
release, and the death popup left standing while the release is unconfirmed
(hiding it early would strand the player with no manual way out).

The honest part of this mock is the death state: `UnitIsDead`/`UnitIsGhost`
are driven by hand and `RepopMe` only logs the press, so the retry loop is
tested against a server that has not answered yet — which is the only reason
that loop exists. `C_DeathInfo.GetSelfResurrectOptions` is mocked in place of
`HasSoulstone`, which does not exist on this client.

The AddOns path is absolute at the top of the file — adjust if the install
moves. Must exit 0 before any Recovery change ships.

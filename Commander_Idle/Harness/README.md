# Headless harness (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit idle_clock_smoke.lua   # the 3.1.0 battleground AFK
                                                    # clock, against the REAL
                                                    # CommanderIdleClock.lua
                                                    # (94 checks)

`CommanderIdleClock.lua` is pure by construction — no frames, no globals of its
own, one snapshot in and one state out — so the harness loads the shipping file
directly rather than mocking around it. There is no WoW mock here at all; that
is the point of splitting the ladder out of `CommanderIdle.lua`.

**The rule most of these checks defend is silence.** 3.0.0 shipped a "quiet"
stopwatch that appeared while the player was legitimately holding a base and
told them nothing they could act on, which is worse than showing nothing. A
large block of the suite now asserts that `Evaluate` returns `nil` — while
defending, while out in the world, and for the first four minutes of stillness.

Also covered: the auto-AFK countdown and that its bar spans the WARNING window
rather than the full five minutes (a bar that sits at 100% for four minutes says
nothing); that the auto-AFK wording never claims PvP combat resets it, because
it does not; rung ordering (a live debuff outranks the input clock, Inactive
outranks Idle, the kick beats the lockout); the `FLAGGED` fallback that exists
so nothing ever matches a localized aura name; that the Deserter lockout is
NOT a rung (removed 2026-09-13 — a fifteen-minute wait after the battleground
is over is not worth a bar); the bar-span rules; the master switch; the
warning marks; and that all four rungs are reachable, so none of the wording
is dead.

## What is not covered here, and why

The frames, the input watcher and the ticker live in `CommanderIdle.lua` and
are not exercised. The facts they rest on were verified against the client and
against Blizzard's documented behaviour rather than tested:

* **Going Away inside a battleground removes you immediately** and casts
  Deserter — no debuff first, no countdown (warcraft.wiki.gg "Away";
  CMaNGOS `Player::ToggleAFK()` calls `LeaveBattleground()` on the spot, which
  casts 26013 on the way out). The client flags you Away after **5 minutes with
  no keyboard or mouse input**.
* There is **no idle-input API** on this client — no `GetLastInputTime` or
  equivalent in the 2.5.6.69546 Mac binary — so the five-minute clock is
  rebuilt from `GetCursorPosition`, `IsMouselooking`, `GetUnitSpeed`,
  `PLAYER_STARTED_MOVING` and `UNIT_SPELLCAST_SENT`. That set can only
  UNDER-count (a keypress that does nothing visible is invisible to an addon),
  so the bar can warn early, never late.
* `PlayerIsPVPInactive("unit")` and `UnitIsAFK("unit")` both exist here.
* Spells 43680 *Idle*, 43681 *Inactive* and 26013 *Deserter* carry the wording
  quoted in `CommanderIdleClock.lua`, checked against the Anniversary tooltip
  dataset on 2026-09-08. Their spans are documentation — the module never
  counts with them.

The AddOns path is absolute at the top of the file — adjust if the install
moves. Must exit 0 before any Idle change ships.

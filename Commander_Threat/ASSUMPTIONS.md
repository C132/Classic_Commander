# Commander Threat — Assumptions

Numbered, each with a one-line in-game test. The code fails safe on every
one: a wrong assumption degrades to an empty board or a missing footer
fact, never to a wrong warning.

1. **`UnitDetailedThreatSituation(unit, mob)` exists and returns
   (isTanking, status, scaledPercentage, rawPercentage, threatValue) with
   threatValue = threat × 100.** Login stands down loudly if the function
   is missing; a nil return simply drops the unit from the list.
   *Test:* attack a training dummy, then
   `/dump UnitDetailedThreatSituation("player", "target")` — expect five
   values, the last ≈ 100× a plausible threat number.
2. **scaledPercentage folds the 110% melee / 130% ranged thresholds — 100
   means "you pull now", and the tanking unit reads 100.** The bars, the
   WarnAt slider, and the headline all assume it.
   *Test:* as melee DPS, climb until the mob turns: the board should read
   ~100% at the turn. If it turns at ~91%, the client is returning raw in
   the scaled slot — report and lower WarnAt meanwhile.
3. **Threat queries accept "targettarget" as the mob.** The healer-targets-
   tank fallback depends on it.
   *Test:* target the tank mid-fight; the board should populate from the
   tank's target within a tick.
4. **Nameplate unit tokens accept threat queries.** The token pattern
   (`C_NamePlate.GetNamePlates()[i].namePlateUnitToken`) is field-proved by
   Radar and Shield, but not previously for `UnitDetailedThreatSituation`.
   *Test:* as tank with three mobs and enemy plates on, the footer's
   HELD n/m should match reality; as healer, PEAK should name an off-target
   mob you are healing through.
5. **`UnitPlayerOrPetInParty` / `UnitPlayerOrPetInRaid` exist** (vanilla-era
   globals). Guarded — absence narrows the engagement test to
   player/pet-targeted mobs instead of erroring.
   *Test:* `/dump UnitPlayerOrPetInParty("party1")` in a party.
6. **`partypet1-4` / `raidpetN` tokens resolve for threat queries**, so
   pets on the list appear on the board.
   *Test:* party with a warlock; the pet shows (neutral color) during a
   pull it has threat on.
7. **`SOUNDKIT.RAID_WARNING` (8959) plays on the Master channel** (Shield
   and Production ship the same call live).
   *Test:* `/cthreat test` with Warning Sound on.
8. **The LowHealth vignette + ADD blend renders as a red edge pulse**
   (Impact ships the same construction live — inherited, not new).
   *Test:* `/cthreat test` with Screen Flash on.
9. **PLAYER_TARGET_CHANGED / REGEN / GROUP_ROSTER_UPDATE deliver via plain
   RegisterEvent** (all used live by Meters and others). No UNIT_THREAT_*
   event is registered at all — the poll makes their delivery moot (D1).
   *Test:* switching targets mid-fight repopulates the board same-frame.
10. **`GetRealmName()` is stable at panel-build time** for the RoleByChar
    key. A nil realm degrades to a "Name-" key that still round-trips.
    *Test:* set a role, `/reload`, confirm the dropdown kept it.
11. **`TargetFrame` and `TargetFrameHealthBar` exist as globals at
    PLAYER_LOGIN, and the health bar is the 119×12 strip in the frame's
    middle band** (read off `Blizzard_UnitFrame/Classic/TargetFrame.xml` on
    the `classic_anniversary` branch: `name="$parentHealthBar"` under
    `TargetFrameTemplate`, instanced as `TargetFrame`). Both are looked up
    through a fallback chain (`TargetFrame.HealthBar` / `.healthbar`) and a
    miss simply means no readout is ever built — the board and the warnings
    do not notice.
    *Test:* with Target Frame set to Bar + Text, pull a mob: a slim colored
    fill should sit on the bottom edge of the target's health bar and the
    percentage above its right end, both tracking the board's number.
12. **The right end of the target frame's name band is free of Blizzard
    art and text.** The readout's percentage is anchored there
    (`BOTTOMRIGHT` of the health bar's `TOPRIGHT`). The name fontstring is
    centred well to the left, but this is a visual judgement, not an API
    fact.
    *Test:* target an elite with a long name and a rare/elite dragon border;
    if the number collides, Bar-only still gives the full reading.

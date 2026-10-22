# Commander Meters — Assumptions

Numbered, unverified-against-the-live-client assumptions. Each has a one-line
in-game test. Design rule: every one of these fails **loud** (anomaly counter,
visible wrong label, or missing feature) rather than silently mis-attributing.
`/cmeters health` shows the anomaly counters.

1. **Plain `frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")` delivers
   events.** The generated docs flag CLEU with the same restriction pair as
   the callback-only MINIMAP_PING; Epic DM works with plain registration, and
   the code pcall-falls-back to `RegisterEventCallback`.
   *Test*: `/cmeters dump`, hit a training dummy once, `/cmeters dump` — the
   print must report ≥ 1 captured event.

2. **Totems are Creature-GUID units flagged `TYPE_OBJECT` (0x4000) with group
   affiliation, summoned via `SPELL_SUMMON`.** The engine folds any
   affiliated PET/GUARDIAN/OBJECT minion with a known summon.
   *Test*: drop a Searing Totem on a mob — its damage must appear under the
   shaman as "Searing Totem: Attack", and `/cmeters health` must show no
   "unknown owner" anomaly.

3. **Chained summons resolve** (snake-trap snakes summoned by the trap,
   elementals by the totem): the engine resolves the summoner through the
   fold, but only if the intermediate object's own summon was seen.
   *Test*: Snake Trap a mob — snake damage lands under the hunter, not as a
   "Snake" actor.

4. **`ENCOUNTER_START` fires on Anniversary raid bosses** (server-side data;
   the event exists client-side). Only fight *names* depend on it —
   segmentation is fully heuristic regardless.
   *Test*: pull any Karazhan boss; the closed fight should be named after the
   boss either way (heuristic namer), with the encounter name winning if the
   event fired mid-fight.

5. **`SPELL_ABSORBED` payload layouts** (both forms, discriminated by
   `type(arg12)`) are as previously field-verified for Commander_Shield. The
   parser validates every field and skips-with-anomaly on mismatch.
   *Test*: PW:S a tank, let a mob swing into it — the priest's Healing mode
   must show a "Power Word: Shield" entry; `/cmeters health` clean.

6. **The `overhealing` field is server-accurate on this build** (Blizzard's
   own processor subtracts it; accuracy of the value itself is assumed).
   *Test*: fully overheal a full-HP target — Healing mode must not move, and
   the ability tooltip's Overheal line must grow by the cast's full amount.

7. **`UnitIsFeignDeath` works for group units on this client** (guarded: if
   the API is absent the guard no-ops and a feign counts as a death).
   *Test*: have a grouped hunter Feign Death mid-fight — Deaths must not
   increment.

8. **ARIALN digit advances are uniform on this client's renderer** (the
   no-jitter premise for value columns).
   *Test*: watch any bar's value tick during sustained damage — the digits
   must not shimmy horizontally.

9. **`ToggleDropDownMenu` + `UIDropDownMenu_Initialize(frame, fn, "MENU")`
   works for context menus.** The suite uses the dropdown machinery
   extensively in settings panels, but not the "MENU" display mode.
   *Test*: click the window's mode label — a 5-entry menu must appear.

10. **Graph hover math** (`GetCursorPosition() / GetEffectiveScale() -
    GetLeft()`) yields plot-local pixels under HUD scaling.
    *Test*: open the graph on a finished fight, hover — the amber hairline
    must track the cursor across the full plot width at any Frame Scale.

11. **`loadDeprecationFallbacks` remains enabled** (the `COMBATLOG_OBJECT_*`
    globals and `CombatLogGetCurrentEventInfo` come from the deprecation
    shim). The code prefers `C_CombatLog.GetCurrentEventInfo` and carries hex
    fallbacks for every flag constant, so a disabled shim costs nothing.
    *Test*: `/dump GetCVarBool("loadDeprecationFallbacks")`.

12. **`GetInstanceInfo()`'s 8th return is a stable instance identifier** for
    the enter-instance auto-reset key.
    *Test*: enable "On Entering an Instance", zone into a dungeon (reset
    fires once), run a hallway loading screen inside — no second reset.

13. **`UNIT_PET` fires with the owner's unit token on pet summon/dismiss**
    for group members in range.
    *Test*: a party warlock re-summons mid-session — pet damage keeps landing
    under the warlock (no "unknown owner" anomaly).

14. **`PLAYER_ENTERING_WORLD` fires after every loading screen** with
    (isInitialLogin, isReloadingUi) — used only for roster refresh + the
    instance-reset key, both idempotent.
    *Test*: /reload — window state, settings, and (empty) data come back
    without errors.

15. **Environmental damage carries no source** (nil source name); the victim's
    breakdown keys it by environment type ("Falling").
    *Test*: take falling damage mid-fight — Damage Taken detail must show a
    "Falling" row.

16. **`SPELL_AURA_BROKEN(_SPELL)` orientation**: the prefix spell is the
    BROKEN aura (extra = the breaking spell in the `_SPELL` form) and the
    source is the breaker. Type-validated; a wrong layout skips with an
    anomaly.
    *Test*: break your own Polymorph with a Frostbolt — CC BREAKS +1 with a
    "Polymorph" row.

17. **`Texture:SetRotation` rotates about the texture's center** on this
    client (the pie spokes and death-curve segments depend on it).
    *Test*: click any ability in the detail — the pie must be a disc, not a
    stack of vertical bars.

18. **`SPELL_INTERRUPT`/`SPELL_DISPEL` carry the extra spell at args 15-17**
    (extraSpellId, extraSpellName, extraSchool; dispels add auraType@18).
    *Test*: Pummel a cast — INTERRUPTS +1 keyed by the interrupted spell.

19. **`ENCOUNTER_END`'s 5th argument is success (1/0)** on this client.
    *Test*: kill any raid boss — LAST shows the boss name tagged KILL.

20. **`SendChatMessage` channel validity** ("RAID" fails in battleground
    groups; the Share menu offers INSTANCE there instead, per the suite's
    verified BG lesson).
    *Test*: share to PARTY in a dungeon group — five plain lines arrive.

21. **`C_Spell.GetSpellInfo`'s return shape on this client** (table on
    retail, possibly tuple or absent here — the lookup handles all three
    and falls back to the native global).
    *Test*: log in — no "only N/18 CC names resolved" warning appears.

22. **`EnableMouse(false)` on Button frames passes clicks through to the
    world** (the Click-Through premise).
    *Test*: enable Click-Through When Locked, click squarely on a bar —
    your character should interact with whatever is behind the window.

23. **`PLAYER_LOGOUT` reliably precedes the SavedVariables flush on
    /reload** (the persistence write moment; the suite's session stamper
    already relies on this).
    *Test*: enable Keep Data Through /reload, run a test fight, /reload —
    "session resumed" prints and Overall still shows the fight.

## Arena (D27, 2026-09-27) — none of these has been seen in a live match yet

24. **Arena Preparation is aura 32727 or 32728, and its REMOVED event on a
    seat reaches the combat log.** The gate clock hangs on it (the first
    blow between the teams is the fallback).
    *Test*: in the report of any match, the summary must read a GATES time
    near 1:00 and the first moment must be GATES, not a blow.

25. **`GetBattlefieldWinner()` compared with `GetBattlefieldArenaFaction()`
    decides the result** (Blizzard's TBC WorldStateFrame pattern; the
    faction indexes 0/1 are the arena's green/gold sides).
    *Test*: win a skirmish — the header must read WIN, not LOSS.

26. **`GetBattlefieldTeamInfo(index)` returns teamName, oldTeamRating,
    newTeamRating, teamMMR for a rated match.** Every value is type-checked
    and anything odd is not recorded, so a different shape costs only the
    ratings line.
    *Test*: after a rated game the summary shows "US 1850 → 1864"; if it
    shows only the RATED tag, the shape differs — /dump GetBattlefieldTeamInfo(0).

27. ~~Every TBC PvP trinket casts spell 42292 ("PvP Trinket").~~ **FALSE,
    field-reported 2026-09-30**: presses were not tracked. The medallions
    and insignias cast their own item spells. Replaced by: the client's
    `C_PvP.GetArenaCrowdControlInfo(arenaN)` answers (spellId, startMs,
    durationMs; zero while ready) for enemies, `UNIT_SPELLCAST_SUCCEEDED`
    fires for `player`/`partyN` with the spell id as its third argument,
    and the log's cast NAME is one of PvP Trinket / Medallion of the
    Alliance|Horde / Insignia of the Alliance|Horde. Will of the Forsaken
    (7744) and Escape Artist (20589) still ride along by id.
    *Test*: trinket a Polymorph yourself, and watch an enemy trinket —
    both badges must go red with a clock within a second, and
    `/cmeters health` must show no arena anomaly.

28. **`UNIT_HEALTH` fires for `arenaN` and `partyN` tokens, and
    `UnitHealth` answers for visible enemies.** The 1 Hz sample covers the
    gaps; a stealthed enemy simply has no snapshot until seen.
    *Test*: scrub the timeline of a finished match — every seat's HP strip
    must move, and a dead seat must read 0 from its death onward.

29. **`GetArenaOpponentSpec(i)` → `GetSpecializationInfoByID(specId)`
    yields (id, name, description, icon, role, classToken)** in the prep
    phase on this client. Failure means no spec tag beside enemy names,
    nothing else.
    *Test*: enter a rated match — enemy seats should show "Resto"/"Arms"
    before the gates open.

30. **Hostile players carry `COMBATLOG_OBJECT_REACTION_HOSTILE` (0x40) and
    `TYPE_PLAYER`** in arena combat-log flags, so a not-yet-seen enemy can
    be seated from the log alone.
    *Test*: an enemy rogue's Sap opener must create their seat (with their
    name) before Arena Frames ever shows them.

31. **`SPELL_AURA_BROKEN(_SPELL)` and `SPELL_DISPEL` orientation** as in
    assumptions 16/18 hold for player targets, and the DR table from Arena
    Frames / Diminish classifies the AURA id the log reports.
    *Test*: cheap shot, then kidney, then a second cheap shot — the ledger
    must read full, full, half.

32. **Ranged/spell damage into an immune target arrives as `SPELL_MISSED`
    with missType IMMUNE**, so wasted CC counts.
    *Test*: sheep a Divine Shield — the seat card's "CC into immunity"
    must increment.

33. **Signature spells reach the combat log as `SPELL_CAST_SUCCESS` with the
    ids in Arena Frames' SPEC_MARKERS** (Mortal Strike, Lifebloom, …), so
    an enemy's spec is revealed on their first cast of one.
    *Test*: fight a warrior whose prep spec was not shown — after their
    first Mortal Strike the seat reads "Arms" and a SPEC moment appears.

34. **`IsMouseButtonDown("LeftButton")` exists** (the timeline drag ends
    itself when the button is released off the plot). Guarded: absent, the
    drag ends on the plot's own OnMouseUp only.
    *Test*: drag the cursor, release outside the plot — the cursor must
    stop following the mouse.

35. **`GetInstanceInfo()`'s first return is the arena's name** ("Nagrand
    Arena") inside an arena; the zone text is the fallback.
    *Test*: the report header and the match menu name the arena, not
    "Azeroth" or a city.

36. **`GetBattlefieldScore`'s `faction` in an ARENA is the same 0/1 index
    `GetBattlefieldArenaFaction()` returns**, which is what seats a
    scoreboard-only player on the right team.
    *Test*: in a 5v5 where an enemy never came into range, the SCOREBOARD
    ONLY seat must appear under ENEMY, not YOUR TEAM.

37. **In a battleground `GetBattlefieldWinner()` returns 0 for Horde and
    1 for Alliance**, matching `UnitFactionGroup("player")`; the match
    segment's WIN / LOSS tag depends on it (D28).
    *Test*: win any battleground — LAST in the meter window must read
    "<MAP> WIN", not LOSS.

38. **`IsInInstance()` reports `"pvp"` for battlegrounds and `"arena"` for
    arenas on this client**, the two gates of match mode.
    *Test*: enter a battleground, fight, ride to another node for two
    minutes, fight again — the meter window must still show ONE current
    fight, not a new one per skirmish.

39. **Feign Death logs SPELL_CAST_SUCCESS and SPELL_AURA_APPLIED (spell
    5384 / "Feign Death") within two seconds of its UNIT_DIED**, in either
    order, for enemy hunters as well as friendly ones. If neither reaches
    the log, the recovery path still undoes the death at the hunter's next
    cast, swing or living health reading.
    *Test*: have a hunter feign mid-match — the card must read FEIGN (not
    DEAD), no kill is credited, and when the feign ends the card is normal;
    the ledger shows a FEIGN moment at that second.

40. **Mass Dispel's immunity break (39897, DISPEL_MECHANIC 29) logs no
    SPELL_DISPEL** — the shield's SPELL_AURA_REMOVED is the only trace, so
    D29 infers the break from the fade. Either answer is safe: if the log
    does name it, the correlator counts it once and drops the "inferred"
    flag.
    *Test*: Mass Dispel a Divine Shield or Ice Block — the dispel log shows
    it under that Mass Dispel as SHATTER (or PURGE if the log named it),
    your OFF count goes up by one, and never by two.

41. **The two Mass Dispel halves log as SPELL_DISPEL with spell ids 32375
    (friendly targets, auraType DEBUFF) and 32592 (enemy targets, BUFF)**,
    both named "Mass Dispel", from the priest, within the same instant as
    the 32375 SPELL_CAST_SUCCESS.
    *Test*: Mass Dispel a fight with debuffs on your team and buffs on
    theirs — ONE cast line in the dispel log with every removal under it,
    debuffs tagged DISPEL, buffs tagged PURGE.

42. **SPELL_DISPEL_FAILED carries the dispel at args 12-14 and the aura that
    resisted at 15-17**, like SPELL_DISPEL without the aura type; a dispel
    into Cloak of Shadows arrives as SPELL_MISSED IMMUNE with the dispel's
    own id.
    *Test*: Dispel Magic / Mass Dispel a rogue under Cloak — the log shows
    the attempt as IMMUNE under its cast, MISS +1 in the tally.


43. **The scoreboard's 14th value (`preMatchMMR`) is the player's own MMR
    for the bracket, and the 15th does not exist** — there is no
    `mmrChange` on this client. Supported by Devin's saved rated games
    (ArenaArmory's store, 2026-10-20): every player carries a distinct
    pre-match MMR, no row carries a post-match one, and his own pre-match
    MMR moves every game in the direction of his rating change (usually
    about twice its size). D31's MMR± column rests on it: the change is
    read from the player's pre-match MMR in your next game.
    *Test*: play two rated games in a row in one bracket — the first
    game's SCOREBOARD shows your MMR± (and your partner's) the moment the
    second one ends, equal to the second game's MMR minus the first's.

44. **Ratings can reach the scoreboard after the winner is declared**, and
    `UPDATE_BATTLEFIELD_SCORE` keeps firing while Blizzard's end-of-match
    board is up (its OnUpdate calls `RequestBattlefieldScoreData` every
    frame). D31 re-reads the board onto the closed match until you leave,
    for at most two minutes; if the ratings were already there at the
    winner, the re-read changes nothing.
    *Test*: finish a rated game, open the replay before leaving — MMR and
    RTG± are filled for every player, not dashes; leave and reopen — the
    numbers are kept.

45. **An aura fade the combat log never delivered is not seen.** The
    interval runs from the APPLIED to the REMOVED (or the break, the
    death, the end). A player out of combat-log range when a debuff fell
    off leaves it counted until the next sign: a new application, their
    death, or the match's end. The cards' icon rows have always read the
    same intervals; D32's uptime inherits them.
    *Test*: in a game where a druid kited into travel form across the map,
    compare the drawer's Judgement of Justice stretches with when it was
    really judged — a stretch far longer than 20 s without refreshes
    means a missed fade.

46. **Intervals are kept per debuff NAME on a seat**, so two casters' copies
    of one debuff (two warlocks' Corruption) are one interval: the first
    REMOVED ends it while the second copy is still up, and uptime reads
    low. Mortal Strike and the other healing cuts do not stack across
    casters, so D32's main answers are untouched; a double-same-class
    comp's dots are the case to doubt.
    *Test*: a game against (or with) two of one class — compare a shared
    dot's uptime with each caster's casts.

47. **`SPELL_ABSORBED` names the shielded player as its destination** — the
    one whose damage the shield took — and the shield's caster in the
    trailing caster fields. The engine already credited the absorb to the
    caster's healing on that reading; D33's HEALED list also credits it
    to the destination. Supported by the client's own combat-log layout
    (the absorb rides the attack's source and destination).
    *Test*: shield a teammate who then takes a hit — the BREAKDOWN on you
    lists Power Word: Shield under SPELLS and that teammate under HEALED,
    with the same amount.

48. **A target name matches its seat by the name before the realm** when the
    log and the roster disagree on the realm: the exact name first, else
    the one seat whose realm-less name is the same. A cross-realm player
    the log names "Name-Realm" still wears their class in TARGETS and
    HEALED; two seats sharing a name on different realms match neither
    and show uncoloured (the numbers are right either way: the list is
    keyed by the log's name).
    *Test*: a game against players from another realm — every enemy in
    the mage's TARGETS carries a class icon and colour.

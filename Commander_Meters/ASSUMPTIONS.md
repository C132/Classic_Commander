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

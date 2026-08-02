# Commander Threat — Build Brief

## Mission

Build a role-adaptive threat meter named Commander Threat, as a new addon inside my Commander suite, targeting the TBC Classic Anniversary client (interface version from the existing Commander `.toc` files). Tanks, damage dealers, and healers all manage threat, but they manage *opposite sides* of it — so the interface carries a **role dropdown (Tank / Damage / Healer)** and reshapes itself around the selected role instead of showing everyone the same list. Ship it in one pass: investigate, decide, build, self-verify against the acceptance criteria, then hand back the finished addon plus the reports in §8.

## Autonomy rules

Same contract as the Meters brief: never block on me (conservative call + `DECISIONS.md`), never guess silently (`ASSUMPTIONS.md` with a one-line in-game test each), loop until green, and scope discipline — anything not in this brief goes to `BACKLOG.md`.

## 1. Authority ranking and lineage

Threat metering has three generations; know what each contributed and what made it obsolete:

1. **KLHThreatMeter (vanilla).** Estimated threat by re-implementing the threat table from combat-log parsing, then synced estimates over an addon channel — every raider had to run it. Its architecture is a fossil: patch 2.4 added a real threat API and the client has known the truth ever since. Carry nothing from it except the lesson: *never calculate what the client will tell you.*
2. **Omen3 (2.4+).** The gold standard and this addon's primary design reference: threat bars for the group on your current target, percentage relative to the aggro holder, TPS, and the aggro warning flash+sound that saved more wipes than any other addon feature of its era. Its target-of-target fallback (a healer targeting the tank sees the tank's target's threat list) is load-bearing and must be preserved.
3. **TinyThreat (Details! plugin).** Proof that most players need less than Omen showed: one compact percentage list. Its lesson is restraint, not features.

Authority: the live client API first, Commander's own conventions second, Omen's design third, no reference addon's *code* ever. Commander_Meters is the sibling addon — where a visual or settings question has an answer in Meters, that answer wins.

## 2. The role dropdown is the product

One saved role per **character** (a tank alt and a healer main must not share it), default Damage, switchable from three places: the settings panel dropdown, a role tag on the board header (click cycles/menus), and slash subcommands (`tank` / `damage` / `healer`). The board relayouts immediately; no reload.

**Damage** — Omen's classic job. Headline: your scaled pull percentage on the display mob (100% = you pull *now*; the API already folds in the 110% melee / 130% ranged thresholds). Group bars beneath. Warning at a configurable threshold (flash + klaxon + optional full-screen vignette), a louder alert the moment you actually gain aggro. Footer names the current aggro holder.

**Tank** — the mirror image. Headline: your grip — secure / insecure / LOST, plus the closest chaser's percentage of your threat. Warning when a chaser crosses the threshold; a loud alert on *losing* aggro (falling edge, mob still alive — a dying mob is not a lost mob). Footer: held-vs-engaged count from visible nameplates ("HELD 4/6 · LOOSE 2"), because a loose mob eating a healer is the tank failure the target-based list can't show.

**Healer** — threat is diffuse (heal aggro splits across every engaged mob), so the current target means little. Headline: your *worst* scaled percentage across all visible engaged mobs, named. Alert the moment any engaged mob actually targets you (INBOUND). Bars stay (the healer watching the tank sees the fight's shape) but the emphasis is the two alerts.

Nameplate-derived facts (tank footer, healer sweep) follow enemy-nameplate visibility, same as Shield's targeter counter — the options say so rather than pretending.

## 3. Client constraints

Verify against the live client; unverifiable items go to `ASSUMPTIONS.md` and the code fails loudly, not silently:

* `UnitDetailedThreatSituation(unit, mob)` → isTanking, status 0–3, scaledPercentage, rawPercentage, threatValue (threat × 100). This API is the whole data layer; if it is missing, say so once in chat and stand down.
* `UNIT_THREAT_LIST_UPDATE` / `UNIT_THREAT_SITUATION_UPDATE` event delivery (guarded registration — the MINIMAP_PING lesson).
* Threat query units: player + party/raid members + their pets. Display mob: attackable target, else target-of-target.
* Nameplate sweep via `C_NamePlate.GetNamePlates()` / `namePlateUnitToken` (field-proved by Radar and Shield on this client).
* TPS is *derived* (threatValue deltas over a short window) — the API reports state, not rate.

## 4. Architecture

Three files, the Meters shape: **DB** (defaults, migration ladder, settings panel), **Engine** (pure data — ingest observation snapshots, maintain TPS windows, sort rows, run the warning edge/hysteresis state machines; zero frames, zero Unit* calls, fully harness-drivable), **UI** (queries the API on a ~4 Hz tick, feeds the engine, paints the board, plays the alerts). Warnings are engine-owned edges with hysteresis so a percentage jittering across the threshold alarms once, not per tick. The tester (`test` slash + panel button) seeds a scripted fake fight through the real ingest path — it must walk the full alert chain (approach → warn → aggro) so every role can preview its warnings.

## 5. Visual direction

Meters' RTS language, unchanged: ARIALN condensed, fixed geometry (bar height, columns, headline block never shift — only digits and bar order change), class colors as the data encoding on bars, one accent for chrome/selection, dark low-luminance panels, quad-drawn chrome. HUD chrome via the shared `Commander.UI` mechanism (style / scale / lock / position), chrome options last on the panel.

**One bar scaling for every role: scaled percentage.** Full bar width *is* the pull point — the aggro holder rides at 100%, and everyone else's bar shows their true distance to the ledge. This is more honest than Omen's relative-to-top bars, where the last safe pixel sat at an unmarked 91%. The aggro row wears an accent stripe; your row is always visible (pinned into the last slot with its real rank when it would scroll out — Omen's "always show self"). Status colors are role-aware semantics: a tank securely tanking reads green, a DPS at 100% reads red — the same fact, opposite meanings.

## 6. Settings

Derived, not accumulated — the Meters §6.5 method. Master switch; Role (the product); Warning At threshold (one slider, role-contextual meaning: pull % for Damage/Healer, chaser % for Tank); Warning Sound (checkbox — an alarm has one correct sound, the raid-warning klaxon; Production's chime *dropdown* is a preference, an alarm is not); Screen Flash (the Impact red-vignette pulse); Show TPS; Bar Rows and Window Width (Meters' names, ranges, defaults); Only In Combat; Accent Color (the suite-tint dropdown, bake-at-login, the Meters/TopBar pattern). **Ceiling: 10.** Role storage is excluded from the defaults table so Restore Defaults never wipes a character's role (the Orders rally-point precedent).

## 7. Acceptance criteria

* Harness (in-addon, `Harness/`, luajit): engine fixtures — sort stability, TPS math, pinned-self row, warn edge fires exactly once with hysteresis, re-arms on mob change, aggro-lost only on a live mob, healer inbound edge, role switching mid-fight; UI smoke — real DB + settings framework under the permissive mock, board builds, tester runs, every slash handler answers.
* Compile gate: luajit parse of every `.lua`, TOC lists existing files, interface version matches the suite.
* Conformance: indistinguishable from the suite — shared settings framework, HUD chrome, per-module event, tester convention, full-word slash + short alias, `## Category: Commander`.
* Simplicity: theme is one flat table; no abstraction for a single call site; settings at the ceiling.

## 8. Deliverables

The addon, plus `FINDINGS.md` (lineage → what was taken from each generation), `DECISIONS.md`, `ASSUMPTIONS.md` (numbered, each with an in-game test), `BACKLOG.md`, and a final report with the top three things most likely to be wrong in-game.

## 9. Non-goals

No KTM-style raid sync or addon channel. No chat announcements of threat (public-output policy). No nameplate recoloring (Commander_Nameplate's turf). No multi-mob sweep for the Damage role (backlog). No pull timers, no tranq/misdirection tracking, no threat *simulation* of any kind — the client is the only authority on threat.

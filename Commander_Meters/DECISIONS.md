# Commander Meters — Decisions

Every ambiguity resolved during the one-shot build, with the rejected
alternatives. Numbers referenced here are enforced in code and re-checked by
the harnesses.

## D1. Identity and placement
`Commander_Meters`, three files (`DB` → `Engine` → main, data-first TOC
order like Quartermaster), SavedVariables `CommanderMetersDB` (settings) +
`CommanderMetersLog` (debug captures — separate so settings resets never touch
a captured session). Slash `/cmeters` + `/cm` (both free in the suite
registry). Pillar: **Battle HUD** — the meter is glance-driven combat
information, same family as Vitals/Afflictions. *Rejected*: Feedback & Alerts
(those are moment-triggered effects, not persistent boards).

## D2. Attribution model
- **Damage done = landed amount + absorbed portion.** A shield eating your
  hit doesn't erase your hit. Fully absorbed swings arrive as `_MISSED
  ABSORB` and are credited identically (attacker damage + victim damage
  taken). *Rejected*: post-absorb amounts only (undercounts vs every meter
  users compare against, and makes absorbed hits vanish).
- **Absorb credit to healers comes exclusively from `SPELL_ABSORBED`** (the
  only event naming the shield caster) and lands as a "Power Word: Shield"
  style entry in the Healing mode. The `absorbed` field on `_DAMAGE` /
  `amountMissed` on `_MISSED` feed only the attacker side. Each absorbed
  point feeds exactly one metric per actor — no double count.
- **Healing = effective healing** (amount − overhealing, Blizzard's own
  formula in its combat log processor) **+ absorb credit**; overheal is
  tracked per ability and shown in the detail tooltip. *Rejected*: gross
  healing as the headline (Recount's default; inflates and disagrees with
  the modern convention).
- The `absorbed` field on `_HEAL` events (heal-absorb debuffs) is ignored —
  near-nonexistent mechanic in TBC content.

## D3. Entity resolution
Actors are keyed by GUID, never name. Pets, guardians, and totems fold into
their **owner at ingestion time**, with the contribution kept visible as
`"PetName: Ability"` keys. Ownership comes from `SPELL_SUMMON` (source
resolves through the fold, so a totem's elemental still lands on the shaman)
plus the `UNIT_PET` roster map. Flags alone cannot supply an owner (verified:
no owner link exists in CLEU flags). A minion whose owner is unknown stays
visible as its own actor **and raises a loud anomaly counter** —
*rejected*: guessing an owner (silent mis-attribution) and dropping the
damage (silent undercount). *Rejected*: Recount's display-time merging
(duplicated denominators, "Pet <Owner>" name mangling, tooltip scraping).

## D4. Segmentation
- **Heuristic core; encounter events are a naming refinement only.**
  `ENCOUNTER_START` exists client-side but server-side firing on Anniversary
  raids is unverified — so it may only ever improve a fight's *name*, never
  gate a boundary. Segmentation works identically if it never fires.
- **Damage opens a fight** (either direction: group deals or receives).
  Heals, summons, and misses never open one; a stray out-of-combat whiff
  can't create a segment. Events with no fight open are **dropped**, which
  makes *Overall exactly equal the sum of its segments* — the invariant the
  fixture asserts. *Rejected*: recording out-of-fight heals into Overall
  only (breaks the invariant; drink-up healing between pulls is noise).
- **A fight closes** when the player is out of combat AND no group-relevant
  event has arrived for `IdleTimeout` (default 3 s, setting). The close is
  stamped at the **last real event**, so idle never pads duration. A dead,
  released player still sees the raid's CLEU, so the fight stays open while
  others fight on.
- Fights shorter than the timeout still count (no 3 s minimum like Recount;
  a one-shot pull is a real pull).

## D5. Rate denominator — the meter-disagreement decision
**DPS/HPS divide by wall-clock segment duration.** Overall divides by
accumulated fight time (idle between pulls excluded). Per-actor *active
time* (gaps ≤ 5 s between that actor's events merged) is tracked in the data
model and shown in the detail header — but it is never the denominator.
*Rejected*: Recount's active-time denominator (inflates everyone's number
and makes cross-actor comparison depend on their own uptime); a setting for
it (settings that switch what a number means mid-conversation are how meter
arguments start — pick one meaning and label the other clearly).

## D6. Segment data model
Each segment owns its actor tables; every credit dual-writes to the live
fight and Overall through the same helper (one code path, byte-equal
semantics). `Current` → `Last` is a pointer move at close (the fixture
asserts table identity). *Rejected*: Recount's per-combatant
`Fight1..FightN` shuffling (aliasing hazards, display-cache resets) and
lazy aggregation at read time (turns every repaint into a walk of all
segments).

## D7. Reset semantics (the full table)
| | totals | segment list | time series | in-progress fight | open detail/graph |
|---|---|---|---|---|---|
| **RESET FIGHT** (`/cm wipefight`) | current segment zeroed | untouched (Overall keeps everything already recorded, incl. this pull's earlier events — **and its elapsed time**, so Overall rates stay honest) | current segment's buckets dropped | restarts recording from now, same fight number | repaint immediately; detail shows "no data" until new events |
| **RESET EVERYTHING** (`/cm wipe`) | all zeroed | emptied, numbering restarts at 1 | all dropped | if in combat, a fresh Fight #1 opens at the reset instant and records the rest of the pull | repaint immediately |

Two hardening rules from the adversarial review: every reset re-arms the
idle clock (a reset clicked in the post-kill idle window must not be
instantly closed by a stale timer), and a segment that closes with nothing
recorded is discarded outright and returns its fight number — no phantom
empty "Skirmish" entries.

Resetting Overall mid-combat is deliberate and instant: the rest of the pull
records into a fresh world. No confirmation dialogs (the brief says instant;
tooltips carry the warning). Both live under one header button (`R`) as a
**one-level menu with fully written labels** — *rejected*: two separate
header buttons (at 240 px the labels degrade to cryptic glyphs, which fails
"clearly labeled" harder than one extra click) and Recount's confirm dialog
(fails "instant").

`/cmeters reset` keeps the **suite-wide meaning** (restore settings
defaults) because every Commander addon wires `reset` that way — a user who
knows one Commander addon must not find a booby trap here. Data wipes are
`wipe`/`wipefight`, plus the window's R menu.

Auto-reset triggers (new fight / entering an instance / ready check) each
perform RESET EVERYTHING, are off by default, independently toggleable, and
wired to `OpenFight` (inline, to avoid callback re-entry),
`PLAYER_ENTERING_WORLD` + instance-key change, and `READY_CHECK`.

## D8. Retention and the memory ceiling
Constants in the engine, not settings: **10 closed fights** kept (`Fight #N`
ring); **graphs on the newest 5** closed fights + the live one; **3600
buckets** (1 h) per actor per fight, then that fight stops graphing; owner
map pruned above 400 entries after 10 min idle; debug capture capped at
2000 events. Three series exist per actor (damage done, healing, damage
taken — the last added after review so the TAKEN/DEATHS graphs plot real
data). Worst-case series memory: 25 actors × 3 series × 3600 buckets ×
6 fights ≈ 1.6 M numbers ≈ **~26 MB absolute worst case** (every actor
active every second of six one-hour fights); a realistic raid night (5 min
fights) is ≈ 2 MB. Fights beyond 10 drop wholesale; Overall keeps totals
forever (that's its job) but never keeps series or death logs — measured
snapshot of a 6000 s 25-actor fight: 90,000 damage buckets ≈ 1.8 MB
serialized. *Rejected*: per-actor series on Overall (unbounded by design)
and settings for any of these numbers (memory policy is the addon's
responsibility).

## D9. Graph
**Per-fight only.** Overall shows "PER-FIGHT ONLY — PICK A FIGHT SEGMENT";
expired fights say the graphs are kept for the newest five. *Rejected*:
concatenated multi-fight graphs with gap markers (a graph spanning idle time
answers no question anyone asks mid-raid, and Recount's wall-clock-series
version of it is exactly what made its TimeData a memory hog). Rendering:
1 s buckets sampled into 2 px columns (span-averaged), smoothed with a ±2 s
moving average, top-5 actors for the current mode, class-colored quads from
a reused pool; legend chips toggle actors per session; hover shows a
hairline + per-actor values at that second. Damage modes graph the damage
series; Healing graphs healing; Damage Taken graphs its own taken series;
Deaths also graphs the taken series (the spikes around a death are exactly
what that graph is for).

## D10. Current vs Overall, unambiguously
The segment name lives permanently in the window header (uppercase, with an
amber ● when the shown segment is the live fight). Auto-switch ("Follow
Combat", **default on** as the brief mandates a stated default): fight start
→ view flips to CURRENT, fight end → to LAST, each flip flashing the segment
button amber for 0.8 s — the visually obvious transition. With it off, the
view never moves; CURRENT between fights honestly shows "CURRENT (IDLE)"
with an empty list (Recount's semantic). One `view` state drives bars,
detail, and graph — there is a single `ViewSegment()` accessor, so no view
can silently diverge. Bars/segment/mode/graph all repaint from the same
2 Hz pass.

## D11. Visual system
- SC2 palette = **chrome only**: near-black panel fills, thin steel edges,
  one amber accent for selection/active/live markers. Class colors are the
  bars' data encoding and are never tinted, shaded, or overridden — the
  resolution of the palette-vs-class-colors tension is *separation of
  jurisdictions*: amber may touch chrome and text, never a bar; class colors
  may touch bars and names, never chrome. Classless actors (orphan minions)
  get a neutral steel gray.
- Fonts: `Fonts\ARIALN.TTF` (Arial Narrow) — condensed, uppercase-friendly,
  and the font Blizzard itself uses for numbers; digit advances are uniform,
  so values tick without jitter. No font file is shipped (the suite ships
  none). *Rejected*: bundling a true tabular TTF (a vendored asset for a
  marginal gain over ARIALN).
- Stable geometry: bar height 16, rank/name/value/%/rate columns at fixed
  anchors (three separate right-aligned strings, so digit-count changes
  never move a column), fills `WHITE8X8` at 0.30 alpha behind the text.
  DPS mode swaps the *contents* of the value/rate columns, never the
  geometry. No gradients, no glows, no animations on values (the only
  animation anywhere is the 0.8 s segment-switch flash, which exists to
  satisfy "visually obvious transition").

## D12. Settings derivation (§6.5) — ceiling = 8
Recount exposes ~70 options. Triage: **load-bearing 24** (collection
filters, merge policies, segmentation knobs, persisted UI state, deletion
hygiene, death filters, report length), **legacy ~12** (dead keys, retail
guards, sync, network monitors, scenario filters), **decoration ~34** (color
trees, textures, fonts, bar-text composition, per-window buttons, row
metrics). Dropped legacy and decoration wholesale. The load-bearing set
collapsed hard against this design: the 4×9 filter matrix exists because
Recount tracks everyone — tracking group-only removes it; merge-pet options
became the fixed attribution model (D3); MaxFights/AutoDelete became the
fixed retention policy (D8); report options fell with the report feature
(BACKLOG); persisted window state became HudChrome + three widget-less DB
keys. Survivors, cross-checked against suite wording/defaults:

1. `EnableMeters` (suite-standard master switch)
2. `AutoSwitchCurrent` "Follow Combat" (brief-mandated, default on)
3. `MaxRows` (the one Recount window metric a real user changes)
4. `FrameWidth` (ditto)
5. `IdleTimeout` (Recount's hardcoded fight-end made honest)
6. `AutoResetOnNewFight` (brief-mandated trio, off)
7. `AutoResetOnInstance` (off; Recount's delete-on-instance, made total)
8. `AutoResetOnReadyCheck` (off)

Plus the suite-wide HudChrome block (Style/Scale/Lock/Position — consumed,
not re-implemented). `WindowShown`/`ViewMode`/`ViewSegment` are persisted UI
state written by window chrome, with no settings widget — the round-trip
Recount's CurDataSet/MainWindowMode provided. **8 is the ceiling**; anything
past it needs a written justification here.

## D13. Combat data is session-only *(amended by D18)*
No SavedVariables persistence of fights/Overall — *originally*. Batch 3
added an **opt-in** exception for Overall + Last (see D18); everything else
here still holds: fight history beyond Last is session-only, nothing
flushes mid-play (the telemetry work established mid-play flushes
hard-crash this client), and `Commander.RestoreSession` stays rejected
(designed for small counters, not megabyte tables). The debug capture
remains the other bounded exception: 2000 events, its own SavedVariables
file, flushed on the next clean logout/reload.

## D14. Hot-path discipline
`OnCleu` allocates nothing on the common path (first-touch of an
ability/actor record and death snapshots are the exceptions); payload
arrives as plain arguments (no varargs tables, no re-fetch); pet key strings
are memoized two-level; `Commander.Notify` is never called from the combat
path (telemetry cost); repaint is a single 2 Hz pass that reuses row/quad
pools and one shared sort scratch. Measured under luajit: 0.11 µs/event
ingest (9.4 M events/s), CollectRows 3 µs — even at 1/30th interpreter
speed, a 500-event/s raid burst costs ~1.7 ms/s of frame time total.

## D15. Test and debug conventions
`/cmeters test` replays a canned mini-fight **through the real parser**
(suite tester convention: live data path, not a parallel render path) —
sentinel GUIDs, a pet, both SPELL_ABSORBED forms, overheal, a death. It
deliberately pollutes live data (that *is* the test) and says so; RESET
EVERYTHING clears it. `/cmeters dump` toggles a raw-event capture into
`CommanderMetersLog` for schema verification against a real session
(brief §4.1). `/cmeters health` prints anomaly counters — every parse
guard that skips an event counts and announces itself once, so a wrong
assumption shows up as a visible number, never a silent mis-attribution.

## D17. Batch 2 (2026-07-31): seven backlog items + split view + pie
Requested as a follow-up loop; decisions made along the way:

- **Bar scrolling**: the wheel scrolls each pane's ranking; rank numbers
  always show the actor's TRUE rank, never the visual slot. Offsets reset
  on segment/mode switches and clamp every repaint.
- **Report to chat** is manual-only (a header Share button → one-level
  channel menu), five lines fixed, plain text. No channel or line-count
  settings — the channel is chosen per use, and a report that needs
  configuring before it can brag is a report nobody sends. Complies with
  the suite's public-output policy because nothing is ever sent
  automatically.
- **Split view**: two panes with independent MODES, one SHARED segment —
  two panes silently showing different fights is exactly the ambiguity D10
  exists to kill, so the segment selector stays singular in the chrome.
  Pane captions appear only while split (the one deliberate geometry change,
  triggered only by the explicit toggle). `SplitOpen`/`SplitMode` are
  widget-less persisted view state; the settings ceiling stays 8. The graph
  and the report follow pane 1; the detail view follows whichever pane was
  clicked.
- **Pie breakdown**: clicking any entry in a detail list opens a pie of
  that LIST's shares (top 8 + OTHER), drawn as ~120 thin rotated spokes
  from a pooled set — no wedge art, no libraries. The slice palette colors
  shares of one actor's own output and never actors; class colors keep
  that jurisdiction. Row swatches double as the legend; the center readout
  shows the selected entry's share.
- **Kill/wipe tagging**: ENCOUNTER_END may tag the open fight or the
  newest fight closed within the last 10 s — never anything older, so a
  late event can't rewrite history. Purely a labeling refinement, like
  ENCOUNTER_START.
- **Utility modes** (INTERRUPTS / DISPELS / CC BREAKS): records key what
  was interrupted, dispelled, or broken — never the tool used. SPELL_STOLEN
  counts as a dispel. CC breaks are filtered against a curated base-spell-ID
  list resolved locale-safe at login (all ranks share the base name); an
  unfiltered aura-break feed would drown the mode in trash procs. Utility
  events hold fights open but never open one.
- **Hit-table detail**: glancing count + partial resist/block sums live on
  attacker ability records; crushing lands on the victim's taken records
  (players cannot crush, mobs cannot glance meaningfully). Full
  resists/blocks stay misses, and avoided amounts are never damage.
- **Death health curve**: drawn from the death trail's own hp snapshots
  (damage red, heals green, the terminal drop to zero), from pooled rotated
  segments. No new data — the ring already carried hp/hpMax.

## D18. Batch 3 (2026-07-31): release hardening + appearance
Devin picked hardening items 5/6/7/9/10 from the release review and asked
for theme options plus richer lock controls. Decisions:

- **Schema versioning**: `DBVersion` + a `MIGRATIONS[n]` ladder runs before
  `ApplyDefaults` on every load. v1 = the unversioned original; v2 stamps
  the version. Every future key rename/retype ships as a ladder step —
  settings survive upgrades forever. `DBVersion` is deliberately not in the
  defaults table, so Restore Defaults never un-migrates.
- **Native-first API ladder**: the CLEU getter already preferred
  `C_CombatLog`; batch 3 adds a loud disable (not per-event errors) if no
  getter exists at all, and spell names resolve via `C_Spell.GetSpellInfo`
  (both table and tuple return shapes handled) before the deprecation-track
  global, with a resolved-count warning if CC names come up short. The flag
  constants were already hex-fallback shim-independent.
- **Opt-in reload persistence** (`PersistData`, default off): at
  PLAYER_LOGOUT (which fires on /reload) the engine exports Overall + Last
  by reference into `CommanderMetersSession`; at login a fresh-and-sane
  snapshot within the suite's 10-minute resume window is adopted, anything
  malformed or stale is refused outright. Only Overall + Last persist —
  the bounded pair that answers "what did tonight look like" — never the
  full fight ring. A crash loses the session (SavedVariables only flush on
  clean logout; documented constraint, tooltip says so).
- **Name-map caps**: targets/sources/enemies maps cap at 60 distinct names;
  overflow folds into one `"(other)"` bucket so every sum invariant holds
  byte-exact, and the overflow bucket can never name a fight. This is the
  battleground-evening bound — chosen over a "disable in BGs" setting (a
  cap keeps the meter useful in PvP instead of turning it off).
- **Graph cap honesty**: fights past the one-hour series cap label the
  plot "FIRST HOUR SHOWN" instead of silently truncating.
- **Appearance options — the ceiling moves 8 → 14, by request.** Per D12's
  rule, each addition carries its justification: `PersistData` (top
  complaint driver for session-only meters), `AccentColor` + `TextSize` +
  `BgOpacity` + `BarOpacity` (Devin asked for theme control; these four are
  the load-bearing subset — accent stays chrome-only and can never touch
  class-colored bars), `ClickThrough` (Devin asked for lock behavior;
  Recount's equivalent sat in the borderline pile). **Mechanism**: no skin
  engine grew — the accent/text-size overrides are written INTO the THEME
  table once at login (widgets keep reading the same constants; changes ask
  for a /reload, the Shield ClickCast precedent), and the two opacities are
  read live from the DB at their exact two consumers. The settings page
  adopted the suite's scrollable-panel pattern to fit.
- **Lock controls**: `/cmeters lock` and `/cmeters unlock` drive the same
  HudChrome state as the panel checkbox (no parallel lock system), and
  `ClickThrough` makes a LOCKED window release the mouse on bars, panes,
  graph, and legend chips while the header strip stays interactive — you
  can always reach the menus, and the slashes work regardless.
- **Post-review hardening of the hardening** (3 confirmed findings): the
  instance auto-reset baseline moved into the DB (`LastInstanceKey`,
  widget-less) because the old session-local baseline made every in-instance
  /reload look like "entering a new instance" — which wiped the session the
  PersistData import had resumed seconds earlier; Restore Defaults now
  prints the /reload hint when it resets a bake-at-login appearance option;
  and click-through covers the graph's legend chips.

## D20. Semantic stat colors (2026-07-31)
Devin asked for more color coding in tooltips and breakdowns. The color
jurisdictions now read: **class colors own actors** (bars, names, detail
titles); **the accent owns selection and active state** (segment dot,
flash, hairline, graph toggle, pie fallback); **semantic stat colors own
values** — damage ember, taken hot-orange, healing green, deaths red,
utility cyan, crit gold, miss steel — applied wherever a stat is read:
the header mode label and pane captions (mode identity is data, not
selection, so it moved off the accent), detail value columns, the detail
sub-line, bar and ability tooltips, and the graph's scale label. Death
trails color their HP readouts by threshold (≥50% green / 20–49% amber /
<20% red) so a death spiral reads by color alone, ability rows flag
crit-carrying entries in gold, and the pie's center readout wears its
slice's color. All of it lives as `stat*`/`hp*` constants in the one THEME
table; shared row pools reset every dynamically-colored field in every
branch so no view inherits another's tint. Reports stay plain text (chat
strips escapes for other clients).

## D21. Icons and tooltip layout (2026-07-31)
Devin asked for spell icons and better tooltip formatting. Ability records
(damage, taken, healing, utility) and death-trail entries now carry the
first-seen `spellId` (ranks share icons, so first-wins), captured at
ingestion; the UI resolves textures once per id (`GetSpellTexture` →
`GetSpellInfo` fallback, memoized) and renders them inline via `|T|t` with
the suite's standard 0.08–0.92 icon trim. Melee gets the classic Attack
sword; unknowns get the question mark, never a guess. Both hover tooltips
were rebuilt on `AddDoubleLine` — dim labels left, colored values right
(mode color for stats, gold/steel for crits/misses, the existing special
lines each on their own labeled row) — and the ability tooltip's title
carries its spell's icon. Icons also appear in the detail ability list,
the deaths list (killing blow), and the death trail. No geometry changed:
inline textures consume text space, so the fixed columns hold.

Follow-up (same day): the pie is **always on** — the breakdown opens with
the top entry pre-selected (a nil `pieKey` auto-selects rank 1), clicking
any row in either list re-targets it, and the close-toggle is gone (the
detail's X and Escape close everything). The lists gained right-aligned
column header labels on the section-title line (zero vertical cost):
TOTAL / % / N-CRIT for record lists, TIME and AMOUNT / HP in the death
log — set per view, cleared in the no-data branch like every other
per-branch paint.

## D19. The detail view is a floating popup (2026-07-31)
Changed on request from a side panel anchored to the window's right edge to
a centered, title-bar-draggable popup (DIALOG strata, clamped to screen).
Position is session-scoped — it stays where you drag it until reload, then
returns to center; not persisted, because a transient inspection window
that reappears wherever it was three days ago reads as lost, not
remembered. It still closes with the meter window and with Escape, and
still follows the window's segment and the clicked pane's mode.

## D16. The adversarial pass
After the build went green, a six-lens review (engine correctness, client
API, suite conformance, performance/memory, simplicity budget, brief
compliance) produced 37 findings; a three-skeptic panel confirmed 35
(~20 distinct) and refuted 2. All confirmed findings were fixed and are
pinned by regression checks in the harness. The heaviest: SPELL_ABSORBED
arriving *before* its paired damage event on a pull's opening shielded hit
was dropped (absorbs now open fights); RESET FIGHT kept the discarded
damage in Overall but dropped its elapsed time (permanently inflating
Overall DPS — the duration is now folded in); the segment-flash animation
ran on a Texture, which cannot carry OnUpdate on this client (crash on
every auto-switch — now driven by the button); and the TAKEN graph plotted
damage *done* (a real taken series now exists). The harnesses live in
`Harness/` inside this folder (not TOC-listed, never loaded by the client)
so the verification instrument survives beyond the build session.

## D21. Split polish batch (2026-08-02)
Devin flagged the split view's geometry and chrome; four changes, all
window-layer only:

- **The footprint holds.** Splitting used to DOUBLE the window width
  (`FrameWidth * 2 + 1`) — the one geometry break in an addon whose
  visual contract is "geometry never shifts." Now the total width never
  changes: the panes take half each, and the bar rows condense from the
  full rank/name/value/%/rate column set to rank/name/value (each set
  still fixed — two constant states, not fluid resizing). `Window Width`
  is now honestly "the window's width," not "per pane."
- **Captions carry the segment.** A split pane's caption reads
  `MODE  ·  SEGMENT` (mode in its stat color, segment dimmed), so each
  pane states in full what it is showing — the shared-segment rule made
  visible per pane instead of implied by the header. While split, the
  header's mode button hides (the captions are the mode menus; it was
  pane 1's duplicate) and the segment button takes the freed width. The
  captions are treated as chrome by Click-Through — they stay clickable
  like the header strip, since while split they are the only mode menus.
- **Header glyphs are drawn, not typed.** The `‖` split glyph rendered as
  the missing-glyph box (ARIALN on this client has no shape characters),
  so Share/Split/Graph/Reset — and the detail close — became DRAWN icons:
  little stacks of tinted WHITE8X8 quads (the pie-spoke technique), which
  can neither miss like a font glyph nor vanish like an icon file, and
  tint with the theme exactly like text (accent when active, dim
  otherwise). The harness finds these buttons by `glyphName` now.
- **The accent speaks suite.** `AccentColor` still resolves through the
  local five presets, but any other key is looked up in
  `CommanderConsole_Colors` — the suite's de-facto palette — via the
  TopBar pattern (read the global live, soft-fail to amber when Console
  is absent). The settings dropdown appends every Console tint, including
  CLASS (resolved live from the player's class at login). No parallel
  color system, no copied list, no new DB keys; D20's jurisdictions are
  untouched — this only widens what the one accent can be.

The batch got its own adversarial pass (four lenses — layout math, client
API, state/lifecycle, harness fidelity — every finding then attacked by a
skeptic): 15 findings, 12 confirmed, all fixed. The substantive ones: the
pane divider ran through the full-width graph and sat half a pixel off the
actual seam (it now spans exactly the caption+rows band at [center,
center+1]); the condensed name column starved at small widths (rank and
value tightened to 12/40px in split, name right edge pulled to -48); a
saved suite accent with Console gone left the settings dropdown blank (an
explanatory orphan option is appended); Restore Defaults reset the DB's
modes without the window adopting them (Apply now re-reads ViewMode/
SplitMode — safe, the menus keep the DB current on every normal path);
and CLASS accents now copy rather than alias GetClassInfo's memoized
color table. The harness lens proved (by sabotage) that the suite-accent
path, the close glyph, the caption visibility, the modeBtn hand-off, and
pane 2's condensation were all unexecuted or unpinned — the UI harness now
seeds a Console palette fixture + a saved FEL accent and pins each of
those (87 → 97 checks, each new check verified to FAIL under the mutation
it exists to catch).

## D22. External live pane modes — the Commander_Threat embed (2026-08-03)

Commander_Threat gained an "Embed in Commander Meters" setting, so Meters
now exposes a cross-addon pane contract instead of Threat drawing over the
window: `CommanderMeters_RegisterExternalMode{key, label, collect, caption,
empty}`, plus `CommanderMeters_ShowExternalPane(key)` (the provider-side
"open the split on me" used by the checkbox) and
`CommanderMeters_RetireExternalMode(key)`. Design calls, in the spirit of
"modes as data": an external mode is just a mode entry with an `external`
spec and no engine fields — `series = nil` makes the graph message correct
for free, empty `lists` plus guid-less rows keep the detail view, the bar
tooltip, and the click path off provider rows without new guards (the one
real guard is RepaintDetail closing itself if its pane SWITCHES to an
external mode while open). The provider returns FINISHED display strings
and a 0..1 bar fraction — Meters arranges, never interprets, so Threat's
pull-point bar encoding survives the embed; providers must return pooled
rows (2 Hz repaint) and are pcall-isolated like Notify listeners. A saved
ViewMode/SplitMode naming an absent provider falls through ModeByKey to
the default mode; registration re-runs Apply because SplitMode persists
and resolves before the provider's addon logs in. Retiring points orphaned
panes back at real modes explicitly. Share on an external pane reports the
provider's rows (still manual-only). Rejected: a pane-frame handoff where
the provider paints into Meters' region — it would have leaked two
addons' pooling and click-through rules into each other for no user
benefit. UI harness 97 → 114 checks.

## D23. Hover-driven inspection + death-log spell tooltips (2026-08-03)

The detail view's inspect gesture moved from click to hover: resting the
mouse on any record row (either list) re-targets the pie to it — readout,
swatch hand-off, slice highlight — and raises its stats tooltip in the
same motion. The selection is sticky on leave, so the mouse can travel
over to the pie to read the readout without losing it; clicking still
selects (kept so click-era muscle memory never dead-ends). Death rows are
deliberately EXCLUDED from hover-select: the mouse path from a death row
down to its trail crosses the other death rows, and hover-select would
re-target the inspected death mid-travel — death selection stays on click
and the "DEATHS (CLICK ONE)" title stays honest. Death-log entries
already carried the raw spellId in the ring, so the death log gained
hover tooltips for free: trail rows and deaths rows (the killing blow)
show the REAL spell tooltip via SetSpellByID — pcall-guarded with a
SetHyperlink fallback and a plain titled tooltip for id-less entries
(melee, environmental) — with the event's own numbers appended (HIT/
HEALED FOR, HP AFTER with the threshold color, BEFORE DEATH). Ref
hygiene rode along: mode switches now clear cross-mode row refs
(blowRef/logRef, and keyRef on death-mode rows), which also retires the
pre-existing nit where clicking a trail row with a stale targets-mode
keyRef re-targeted the hidden pie. Hints updated (CLICK → HOVER); the
ability tooltip dropped its "Click for the pie breakdown" line since
hovering already did it. UI harness 114 → 126 checks, each verified to
FAIL under the sabotage it exists to catch (hover-select reverted to
tooltip-only, death tooltip branch gutted).

## D24. Death reports to chat (2026-08-04)

Deaths joined the report surface. Two entry points, one path: the header
share bubble now treats an OPEN death-log detail as the current view and
reports the selected death instead of the pane ranking, and the detail's
title bar grows its own share glyph in deaths mode — report THIS death
from where you are reading it. The glyph exists exactly when a death is
selected (which, via the self-healing selection, means deaths exist),
opens the same channel menu (SAY/PARTY/RAID/INSTANCE/GUILD with the
battleground home-category gates from D-earlier), and stays manual-only.
The report itself: a header naming the fallen, the clock time, and the
segment label, then the trail's last REPORT_LINES events OLDEST-FIRST —
chat reads down to the killing blow, the reverse of the UI's newest-first
list, because a transcript ends at the death while a log opens on it.
Lines are plain text (no icon escapes, no colors — SendChatMessage would
mangle them), formatted like the trail rows: -7.0s Skull Crack -1.1k
(62% HP). Capped at header + 5 so a death report weighs exactly what a
top-5 ranking weighs; a death with an empty trail still sends its header
(who/when is the fact that matters — the noise rule guards empty
RANKINGS, not empty trails). ShareMenu picked up a forward declaration
so the detail (built earlier in the file) can open it. Rejected: putting
DEATH LOG in the share menu as a sixth channel-agnostic entry — the menu
lists destinations, not subjects; and auto-reporting on death — the
suite's "nothing is ever sent automatically" line is load-bearing.
UI harness 126 → 134 checks, sabotage-verified (glyph-show line removed,
death branch forced false — three checks fail, including the fallback
proving the ranking path survives).

## D25. Each pane owns its own segment (2026-09-05, redone 2026-09-06)

Devin wanted the split able to show one metric on two segments — DPS now
beside DPS overall, "am I ramping or falling off?" — not just two metrics
on one segment.

**The first attempt was wrong and is recorded here as the mistake it
was.** It shipped a `SplitAxis` setting: the split differed in EITHER
mode OR segment, flipped by right-clicking the split glyph, with pane 2
borrowing pane 1's mode while comparing. It passed 155 harness checks and
Devin could not find the feature at all. Two failures, both mine. The
control was a right-click on a glyph with no affordance saying so — a
gesture nobody discovers. And the axis was a mode where the user had
asked for a *control*: "set overall/current/last on a per panel basis"
describes each pane having a segment, not the window having a comparison
setting. An option that has to be armed before the obvious click does the
obvious thing is not an option, it is a maze.

What shipped instead: **the caption IS the pane, so the caption's menu is
the whole pane.** Two titled sections, still one level deep (the
Quartermaster Era/Source pattern):

    RIGHT PANE SHOWS      OVER
      DAMAGE                FOLLOW LEFT PANE
      HEALING …             OVERALL / CURRENT / LAST / F#n …

No axis, no mode, no gesture. Click the pane you want to change and both
halves of what it shows are right there. Mode and segment are fully
independent now — a pane may differ in both, which the old axis forbade.
D17's shared-segment argument was never about forbidding divergence; it
was about forbidding *silent* divergence, and the caption states the pane
in full either way.

The right pane FOLLOWS the window's segment until pinned (`view.segSel2`
nil = follow; persisted as `SplitSegment` = "follow" | "current" |
"overall", with "last" and fight ids session-scoped exactly as
`ViewSegment` has always been). FOLLOW LEFT PANE is the default and the
way back, and it is what carries the checkmark while unpinned — an
unpinned pane checks no segment of its own, because it has none. A pinned
caption wears the ACCENT on its segment half; a following one leaves it
dimmed. That is the whole anti-ambiguity mechanism: a divergence you did
not ask for can never look like agreement.

Plumbing: `PaneSelector`/`PaneSegment` resolve per pane, and every
consumer that used to call the window-wide `ViewSegment()` now asks by
pane — bar rows, the bar tooltip, and the detail popup, which follows
`view.detailPane` for its mode already and now for its segment and
subtitle too (a detail opened from the Overall pane must never be
captioned CURRENT). `ViewSegment()` survives as `PaneSegment(1)` for the
graph, the header, and the chat report, all pane-1 surfaces by
definition. `ModeMenu` split back out of `PaneMenu` so the header's mode
button (unsplit only) stays a plain mode list — offering a segment
section there would duplicate the segment button sitting next to it.

A pinned pane never auto-follows combat: Follow Combat moves `view.segSel`
only, since the pin is the fixed reference the live pane is read against
and being yanked to Last at every kill would collapse the comparison.
Only a pruned fight id moves a pin, and then to Overall, which can never
be pruned. External panes (D22) get no segment section at all — they own
their data and know nothing about segments, so offering one would be a
lie.

Rejected: a third pane (D17's footprint rule is absolute — the window
never widens); a settings-page control for any of this (the pane is the
control; a panel row for it would be a second place to look); and keeping
the axis as a "preset" beside the per-pane menus (two ways to say the
same thing, one of them modal).

UI harness 134 → 152 checks, sabotage-verified five ways: the pin
ignored, the segment section removed, the FOLLOW entry removed, the
pinned accent removed, and the header segment dragging the pin along —
each fails exactly the checks written to catch it.

## D26. APM — who is spending their globals (2026-09-13)
Devin asked for an SC2-style actions-per-minute board: the meter that
separates the raider who is pressing buttons from the one who is not,
independent of class, gear, or assignment. Decisions:

- **Signal = `SPELL_CAST_SUCCESS`, group players only.** It is the one
  combat-log event that fires once per completed decision for everyone
  in range — instants, hard casts, channels, consumables, stance dances,
  trinkets. Movement and cancelled casts are invisible to the log, so
  this is *casts* per minute wearing the SC2 name; the mode's own
  breakdown (CASTS list, keyed by spell with counts and icons) makes the
  number self-auditing — anything inflating it is one click away.
  *Rejected*: `SPELL_CAST_START` (double-counts every hard cast) and
  damage/heal event counts (one keypress can be twenty ticks).
- **Minions never fold in.** D3's owner fold is skipped for this one
  metric: a felguard's autocast Cleave is not the warlock's keypress, and
  the pet commands that *are* keypresses do not reach the log. The
  fixture pins a pet cast and a totem cast landing on nobody.
- **Auto-attacks are excluded by spell ID** (`AUTO_CASTS`: Auto Shot 75,
  wand Shoot 5019) — the client reports both as casts, neither is a
  decision. The list is data; anything else found spamming can join it.
- **Casts never open a fight and never hold one open.** Unlike utility
  events they do not stamp `lastEventTs`/`lastActivityTs`, so every
  DPS/HPS denominator is byte-identical to before, a pre-pull buff opens
  nothing, and a post-kill rebuff cannot pad a fight. Casts inside an
  open fight simply count.
- **Per-minute is a mode property, not a special case.** `rateScale`
  (default 1) multiplies the per-second rate every other mode uses;
  `CollectRows` applies it and the UI's one `ModeRate` helper mirrors it
  in the tooltip and detail sub-line; the graph keeps plotting the 1 s
  `sCasts` buckets and multiplies only its scale label. `valueLabel`
  joined at the same time so the tooltip reads CASTS / APM instead of
  APM / APM — and fixed the DPS mode's identical DAMAGE / DPS quirk in
  passing.
- **Presentation** follows DPS: the rate is the headline, the count the
  small column, `activeCast` (2 s-gap-merged, the ACTIVE_GAP rule) in the
  detail header so "42 APM, active 1:10 of 3:00" reads as the dead-time
  it is. Its stat color is a violet of its own (`statApm`) — activity is
  neither damage nor utility. Fourth per-actor series: worst-case memory
  in D8 rises by a third, realistically by far less (a cast bucket is a
  small integer, never a 5-digit sum).
- **Session snapshot version 1 → 2**: a pre-APM snapshot has actors
  without the new fields and is refused, per D18's "malformed is refused,
  never guessed" rule — the cost is one lost resume on the upgrade
  /reload.

Engine harness 736 → 842 checks, UI harness 152 → 164; the fixture pins
the counts, the record/series sum invariants, the auto-attack and
pet/totem/enemy exclusions, the unmoved fight-end stamp, the per-minute
rate, and the v1 snapshot rejection.

## D27. The Arena Report — both teams, the whole match, replayable (2026-09-27)

Devin asked for "a new arena mode that does a team split view breakdown for
all the different stats — I want to know everything about the match and
even have a time replay breakdown." Decisions:

- **A second engine, not a second segment kind.** The core engine records
  the GROUP's story (D3: actors are group-affiliated players and their
  minions; everything else is "bystander violence"). An arena's question
  is symmetric — the enemy's numbers matter exactly as much — and has a
  shape a fight segment lacks: two rosters, a gate clock, a result that
  costs rating. Bolting `them` onto segments would have put a
  team-conditional into every credit helper and every mode. So
  `CommanderMetersArena.lua` is its own pure engine (no frames, no unit
  reads, harness-replayable byte-for-byte) fed by the same CLEU payload —
  one getter call, varargs riding the stack to both engines (`DispatchCleu`).
  *Rejected*: a Recount-style "record everyone" flag on the core engine
  (it would have made Overall a battleground-evening memory hog again, the
  exact thing D18's name caps exist to prevent).

- **Seats are learned three ways and never guessed.** Unit tokens
  (`player`/`partyN`, `arenaN`, with `arenapetN`/`partypetN` owners),
  `GetArenaOpponentSpec` at the prep phase (class + spec), and the combat
  log itself: a hostile PLAYER GUID (TYPE_PLAYER + REACTION_HOSTILE) the
  tokens have not shown yet becomes an enemy seat on the spot — the log
  sees a stealthed rogue's opener before any token does. Nil unit answers
  never erase a seat (the stealth trap from Arena Frames). Minions with no
  owner are skipped with an anomaly, per D3.

- **The clock is match-relative and the gates are a moment.** Everything
  is stored as seconds from zoning in; the gates are stamped when Arena
  Preparation (32727/32728) FADES on any seat, or on the first blow between
  the teams if that fade was missed (a mid-match /reload). Rates divide by
  gates→cursor, so the pre-gate minute never dilutes DPS. The server's
  `GetBattlefieldInstanceRunTime` is kept alongside as the honest duration.

- **Everything the log knows, as counters AND as a ledger.** Per seat:
  damage/healing/taken with the core engine's attribution rules, CC
  applied and taken with the DR BRACKET each cast landed at (the server's
  rule: 15 s reset from the FADE, frozen while stacked — the same ladder
  Arena Frames and Diminish implement), real CC durations from apply to
  fade, who broke a CC early and whether that was an OWN-TEAM break (the
  mistake worth a number), CC cast into immunity/resist (wasted), kicks and
  what they stopped, dispels split into friendly dispels and offensive
  purges/steals, killing blows (last hit within 6 s of a death), deaths,
  casts (APM, D26's rules), mana drained and drunk, trinkets, and every
  book cooldown pressed. Alongside the counters a bounded LEDGER of
  moments (4000; past it only deaths and END land, and the drop count is
  shown) keeps the order of events, which is what makes the timeline and
  the ledger list possible. Per-second series (damage, healing, taken,
  casts) and HP snapshots (UNIT_HEALTH while a match is on, plus a 1 Hz
  sample of every readable seat) feed the replay.

- **The cursor IS the replay.** One time value drives the whole report:
  the team board (values, HP strips, control tags, DEAD), the totals, the
  versus bar and the ledger all read the match AS OF the cursor. Series
  stats sum buckets to the cursor; ledger stats count moments to it, so
  every one of the ten stats replays, not just damage. Drag the timeline,
  wheel a second, click a moment, or press play (1x/2x/4x). *Rejected*:
  a separate "replay" view (two windows that disagree about the same
  match is D10's ambiguity again) and per-event storage of every damage
  tick (a 10-minute 5v5 would be tens of thousands of rows for a curve
  the 1 s buckets already draw).

- **Team is its own color jurisdiction.** Blue us / red them touches only
  team chrome: the 2 px stripe on ARENA pane rows, the team headers, the
  versus bar, the pressure columns. Class colors keep seats, stat colors
  keep values, the accent keeps selection (cursor, tab, seat). Three new
  stat colors joined D20's set: control (violet-magenta, matching Arena
  Frames' FULL control tint), mana (blue), cooldowns (pale gold).

- **Rule data is borrowed, never copied.** The DR table (Arena Frames or
  Diminish — the same generated block), control kinds, the cooldown book
  and the drink list are read from those addons' globals at login when
  installed. Without them CC still counts by the locale-safe CC name list
  the CC BREAKS mode already resolves (no brackets), cooldowns are not
  logged, and `/cmeters health` says exactly which is missing. *Rejected*:
  a third copy of the 884-spell DR table (Diminish's harness already diffs
  two; a third is a third way to drift).

- **Pane modes for the live glance, one window for everything.** Four
  ARENA modes (DMG / HEAL / TAKEN / CC) join the mode menu under their own
  title, painting BOTH teams' seats sorted by the stat with the team
  stripe; they ignore the pane's segment (a match is its own segment, so
  the caption menu drops the OVER section like an external mode) and a
  click opens the Arena Report on that seat instead of the detail popup.
  The report itself (`CommanderMetersArenaUI.lua`, 640 px, DIALOG strata,
  title-drag, Escape) has fixed bands top to bottom: header with a match
  menu, summary line, ten stat tabs, the team board, the mirrored
  pressure timeline with the scrubber, the moments ledger, and the
  selected seat's two breakdown lists. It builds itself on first open, so a
  raider who never queues pays nothing.

- **Persistence is the point this time.** D13 kept combat data
  session-only because raid segments are not revisited; arena matches ARE
  — "why did we lose that one" is asked the next morning. So closed matches
  persist by default (`ArenaKeepMatches`, 10, 0 = session only) into a
  fourth SavedVariables file written at PLAYER_LOGOUT (still never
  mid-play, D13's crash lesson), with a live match archived as LEFT first
  so a /reload mid-match keeps what was recorded. Import validates every
  match's shape and refuses malformed ones outright. Memory: a seat is a
  few dozen numbers plus ≤40-entry record maps and ≤1800-bucket series; a
  ten-minute 5v5 with a full ledger is a few hundred KB, ten of them a few
  MB. The session ring holds 20.

- **Settings ceiling 14 → 17, by request.** `ArenaRecord` (the master
  switch for a whole recorder; a raider may want none of it),
  `ArenaAutoOpen` (a window that pops at match end is exactly the kind of
  thing people turn off), `ArenaKeepMatches` (the one memory policy a user
  legitimately owns, because it is their SavedVariables file). Everything
  else — ledger cap, series cap, kill window, ring size — stays a constant.

- **Result and ratings from the scoreboard API, type-checked.**
  `GetBattlefieldWinner()` on `UPDATE_BATTLEFIELD_SCORE` compared with
  `GetBattlefieldArenaFaction()` decides WIN/LOSS; `GetBattlefieldScore`
  rows (Blizzard's TBC WorldStateFrame order, D-notes) merge onto seats by
  short name for the server's damage/healing/KB/deaths/rating change/MMR —
  the board shows "server 31.2k" beside our number when they differ, since
  the server saw the whole box; `GetBattlefieldTeamInfo(0/1)` gives team
  names and before/after ratings when it answers with numbers, and is
  simply not recorded otherwise. Bracket comes from the larger roster
  snapped to 2/3/5, never from `GetBattlefieldStatus`'s positional
  `teamSize` (its return order differs between the Classic and retail
  shapes and this client is a retail UI over TBC).

- **Test path.** `/cmeters arenatest` injects a canned 3v3 (RMP vs
  warrior/druid/warlock: a full opener, a half-bracket Intercept, an
  own-team sap break, a fear dispelled, a wasted sheep, a spell lock, a
  counterspell, three mana burns, a drink, a trinket, book cooldowns,
  three kills) through the REAL arena engine with HP snapshots, and closes
  it as a WIN with a scoreboard — so the whole report can be read at a
  desk. It joins the match list like any other; Arena › Forget Matches
  removes it. `/cmeters health` prints the arena engine's anomalies and
  which rule data is missing.

Harnesses: `Harness/meters_arena_harness.lua` (new, 186 checks: both
teams' attribution, the DR ladder from the fade, the frozen clock, own-team
breaks, wasted CC, kicks/purges/drains/drinks/trinkets/book, kills and
unattributed deaths, cumulative values and replay state at chosen seconds,
pressure buckets, retention, the ledger cap, discard/LEFT, the persistence
round trip and refusals, determinism, throughput 0.08 µs/event) and the UI
harness 164 → 304 (the canned match, all ten tabs, scrubbing, playback at
2x, the ledger jump and bracket text, seat selection, the match menu,
plain-text share, the ARENA pane mode with stripes and click-through to
the report, a LIVE match driven through PLAYER_ENTERING_WORLD /
ARENA_OPPONENT_UPDATE / UNIT_HEALTH / UPDATE_BATTLEFIELD_SCORE with a
scoreboard and team-info fixture, LOSS, LEFT/discard, and the logout
export). The harness stopped brute-force clicking every Button to find
menus (it was firing the settings panel's Test/Forget buttons as a side
effect); the header buttons are tagged `headerRole` for it instead.

### D27 review pass 1 (2026-09-27, the loop's second iteration)

Six findings against the fresh engine, all confirmed and fixed, each
pinned in `meters_arena_harness.lua` Stage F:

1. **A missed fade froze an aura for the whole match.** The apply path
   returned early whenever the same aura name was already open on the
   target, so a Cheap Shot whose REMOVED was never logged (target out of
   range) silently swallowed every later Cheap Shot on that target — no
   moment, no count, and a DR ladder that never reset. Now a fresh
   APPLIED while the aura is open closes the stale one at its cap and
   counts; only a REFRESH is "the same CC". Drinks got the same rule.
2. **The unclosed-CC cap was 60 s.** TBC's PvP cap is 10 s; nothing that
   controls a player lasts longer. 60 s of phantom control on one missed
   fade is a lie the seat card would repeat. Now 12.
3. **Self-inflicted deaths earned a kill.** A Life Tap or Hellfire death's
   last hit was the victim's own, so the victim was credited a killing
   blow; a death to an orphan minion named a GUID nobody could label. A
   killing blow now requires a SEAT that is not the victim; the blow is
   still named either way.
4. **END could land before the last event.** Finish stamps from `time()`
   (whole seconds) while the log carries milliseconds, so a 12:00:00.7
   blow followed by Finish at 12:00:00 put END out of order and shaved the
   duration. The match tracks the newest log time; END is at least that.
5. **Scoreboard rows for unseen players were dropped.** A 5v5 healer who
   stayed out of range all game had a scoreboard row and no seat, so the
   board showed nine players. The merge now seats such rows (team from the
   row's faction against `GetBattlefieldArenaFaction`, synthetic guid,
   `fromScoreboard`), with the server's numbers as their only numbers.
6. **Ledger stats rescanned the ledger per seat per repaint.** Ten seats ×
   4000 moments at 10 Hz while scrubbing. `CollectRows` now makes one pass
   filling per-guid accumulators; the per-seat scan survives for single
   queries and the harness asserts the two agree for every ledger stat.

Also: the 1 Hz ticker re-reads the arena/party tokens while a match is on
(ten unit reads — insurance against a missed roster event), and the
harness's HEAL special case in `SeatValueAt` was dead code and went.

### D27 review pass 2 (2026-09-27, the loop's third iteration) — the window

Five findings on the report and the pane integration, all fixed:

1. **The live timeline drifted.** Pressure columns were laid out over the
   newest bucket any seat had written while the cursor and markers were
   laid out over elapsed time — during a lull the columns compressed and
   a death marker sat a few seconds off its column. `Pressure` now takes
   the bucket count the window wants (the bucket holding the end time),
   and the plot uses ONE x scale (`pw / endT`) for columns, markers, the
   gates line and the cursor.
2. **Seat rows overlapped themselves.** The bottom-line tag ran to −70 and
   the 90 px sub-value column started at −93: twenty pixels of collision
   on every row. Tag now ends at −96.
3. **A drag could outlive the mouse.** Releasing the button outside the
   plot never reaches its OnMouseUp, so the cursor kept following the
   mouse until the next click. The OnUpdate loop now checks
   `IsMouseButtonDown` and ends the drag itself.
4. **Scoreboard-only seats looked like silent players.** A seat created
   from a scoreboard row (review pass 1) showed zero for every log stat
   with nothing saying why. Its tag now leads with SCOREBOARD ONLY.
5. **The header lied while the left pane read an arena match.** The
   segment button still said CURRENT (IDLE) over a pane showing 3v3
   NAGRAND · WIN. While pane 1 is an arena mode the button names the
   match; its menu still moves the segment for the right pane and the
   detail popup.

Also in the pane menu's ARENA section: OPEN ARENA REPORT…, so the report
is reachable from the menu everyone already opens, not only from `/cm
arena` and the settings page. Harness: arena 284 → 288, UI 304 → 308.

### D27 pass 3 (2026-09-27, the loop's fourth iteration) — two backlog items

- **Cooldowns at the cursor.** The book already carried each ability's
  cooldown and the ledger the press time, so the replay state now lists,
  per seat, every book press and trinket whose cooldown still covers the
  cursor, with seconds left (trinkets carry 120 s, Escape Artist 60 s, on
  the moment itself). On the board the seat's tag line switches from
  class · race to "Shield Wall 22s · Trinket 1:40" whenever anything is
  down at the cursor — live or scrubbed — because "their trinket is down
  for 1:40" is what that second is about. Three shown, "+N" beyond.
- **Spec inference from signature spells.** Arena Frames' SPEC_MARKERS
  (one unmistakable spell per spec) are borrowed like the DR table; a
  player seat without a spec that casts one learns it, the seat is marked
  `specRevealed`, and a SPEC moment lands on the ledger ("Arms revealed").
  Pets never reveal their owner's spec; class alone never becomes a spec
  (Arena Frames' rule, kept). The canned match leaves the warrior's spec
  to be revealed by his first Mortal Strike so the path runs at a desk.

Backlog trimmed accordingly.

Found while pinning: the canned match's script is written by SUBJECT (the
opener, then the mage's damage loop, then the kicks…) and the Intercept
block landed in the code before a loop that emits earlier seconds — so the
engine received events out of clock order, its bisection-searched ledger
went unsorted, and the report quietly skipped a moment. The injector now
queues its events and replays them sorted by time (emission order breaks
ties), and the engine's ledger clamps any moment that arrives behind the
newest one up to it, so a misordered feed can degrade a timestamp but never
the search. Harness: arena 288 → 302, UI 308 → 310.

### D27 pass 4 (2026-09-27, the loop's fifth iteration) — insights

"Know everything about the match" was so far a ledger and a board: every
fact, none of the conclusions. `A.Insights(m)` is the engine reading its
own match back as findings — pure derivation, so every line can point at
the moment it came from: first blood; every KILL with the controls that sat
on the VICTIM's teammates inside the last ten seconds ("Leafshade
Polymorph 4.0s" beside the warrior's death is the sentence an arena player
looks for first); own-team breaks (who broke whose CC on whom); each
trinket and the control it ended (a CC on the presser closing within half
a second of the press); wasted CC and drink time per seat; each team's top
damage and healing seat with its share; and control time, kicks and purges
us-vs-them. Timed findings lead in clock order, summaries follow.

Surface: the ledger band's title became its mode switch — MOMENTS ·
INSIGHTS — so the geometry holds and the eight pooled rows serve both;
insights that carry a time jump the cursor on click, the wheel scrolls
them. Cached per match and ledger length (a live match re-derives as it
grows). The canned match gained a Polymorph on the druid across the
warrior's death so the pattern is visible at a desk.

Measured: the canned 3v3 (30 moments, ~80 s) serializes to ~33 KB, so the
"few hundred KB" ceiling in D27 holds for a ten-minute 5v5 with a full
ledger; ten saved matches stay in the low megabytes.
Harness: arena 302 → 321, UI 310 → 321.

### D27 pass 5 (2026-09-27, the loop's sixth iteration) — history

The kept matches were ten separate reports; `A.History(list)` reads them
together: the record (W/L/left) and win rate, the rating trend across
rated games (team ratings first, the player's own scoreboard change as the
fallback), per-bracket and per-map records, the record against every enemy
COMPOSITION (class tokens sorted inside the key, so "WARRIOR/DRUID" and
"DRUID/WARRIOR" are one comp), average length (forfeits excluded), average
first-blood time from the gates, and first-blood conversion — how often we
drew it and won, how often we gave it and still won. Surface: a third tab
on the ledger band, HISTORY, sharing the eight pooled rows; cached on the
kept-match count. Rejected: a separate history window (the band already
has the room and the wheel).

The store gained the settings DB's version ladder (`STORE_MIGRATIONS[v]`
upgrades v → v+1 on import; a store newer than the code, or older with no
step, is refused rather than guessed), so a future reshape of a saved
match never costs a user their history.
Harness: arena 321 → 334, UI 321 → 326.

### D27 pass 6 (2026-09-27, the loop's seventh iteration) — hardening numbers

A worst-case fixture (5v5, ten minutes from the gates, a blow every
quarter second from both sides, a Polymorph every 1.5 s, a kick and a
Shield Wall every 3 s, HP every second; 803 moments) under LuaJIT with the
JIT OFF — the closest stand-in for the client's interpreter:

| call (per repaint) | interpreter |
|---|---|
| StateAt (all seats: hp, alive, control, cooldowns) | 0.075 ms |
| CollectRows DMG at cursor | 0.018 ms |
| CollectRows CC at cursor / whole | 0.011 / 0.063 ms |
| Pressure (661 buckets) | 0.056 ms |
| Insights | 0.067 ms |
| LedgerIndexAt | 0.001 ms |

At the report's 10 Hz scrub rate that is well under a millisecond a second;
even a full 4000-moment ledger scales to a few tenths. No optimization was
warranted, and none was made.

The footprint was the finding. That match serialized to **520 KB**, and the
per-second HP fractions were part of it: a fraction lands in SavedVariables
as a 17-digit float, and there are up to 600 of them per seat. HP snapshots
are now per-mille integers (0..1000; readers divide), which took the match
to **448 KB**; the rest is the per-second damage/taken series (up to 600
buckets × 10 seats × 2) and the ledger itself, both of which ARE the replay
and stay. Honest numbers replace D27's "a few hundred KB": a typical 3v3
(2–4 minutes) is 100–200 KB, a long 5v5 about 450 KB, ten kept matches one
to a few megabytes. The Keep Matches tooltip says so. *Rejected*:
downsampling the series of older saved matches (a replay that gets
blurrier with age is a second data shape to reason about, for a file size
Details and WeakAuras exceed routinely).
Also: the timeline lost its hover tooltip (the mouse lives there while scrubbing; a tooltip popping on every crossing sat over the board) and carries its marker key on the plot instead.

### D27 pass 7 (2026-09-27, the loop's eighth iteration) — audit

Consistency read across both windows against D20: the report's window title
wore the accent (reserved for the cursor, the chosen tab, the chosen seat)
and now wears plain text like every other Meters title. ASSUMPTIONS 33-36
added for what iterations 2-7 came to rely on without an in-game test:
signature casts in the log, IsMouseButtonDown, GetInstanceInfo's name, and
the scoreboard faction index in arenas. Nothing else diverged.

### D27 pass 8 (2026-09-27) — Devin's first look: layout, and no auto-open

Devin ran it: "the arena report has a lot of layout issues and I only want
it to open when I click a button on commander meters instead of auto open
after a match."

**Opening.** `ArenaAutoOpen` is retired (DB v2 → v3 migration deletes the
key; the settings ceiling drops to 16) and the report never opens itself.
It opens from a crossed-swords glyph in the meter window's header (accent
while the report is up), from `/cm arena`, from OPEN ARENA REPORT… in the
mode menu, or by clicking an ARENA row. An open report still switches to
the finished match when one ends. *Rejected*: keeping the setting with a
false default — a window that pops during the scoreboard was the whole
complaint, and a setting is a second place it could come back from.

**Layout, found in a picture rather than a guess.** The Meters UI mock now
records anchors, textures, layers and justification like Arena Frames'
board mock, and `Harness/meters_arena_render.lua` dumps the report's
resolved rectangles after the canned match (optionally with the cursor
scrubbed) for Arena Frames' `render_svg.py`. The first render showed,
in order of severity:

1. Seat rows overlapped themselves: two text lines (11 + 10 pt) and an HP
   strip in a 24 px row. Rows are 30 px; the name line owns the top 13,
   the tag line the next 12, the strip the bottom 4, each with a fixed
   height so no line can drift into another.
2. The versus bar's "77% · 23%" label had nowhere to sit on a 6 px bar and
   collided with the team heads and the first row. The share now rides
   with each team's total ("56.7k  77%"); the bar is just a bar.
3. The timeline spent half its width on the pre-gate minute. The plot's
   origin is three seconds before the gates; columns, markers, the gates
   line and the cursor all share `pw / span` from that origin.
4. The marker key sat over the enemy's pressure columns; it lives in the
   hint line now, and the peak readout moved into the axis row.
5. Enemy death markers hung below the plot (anchored upside down); they
   stand on the bottom edge inside it.
6. A 3v3 board reserved five rows a side and left a 180 px hole above the
   timeline. The three lower bands live in container frames that a small
   `Layout(rows)` positions from the bracket (the larger roster seen,
   never fewer than two rows, never more than five); the window's height
   follows. This is the one deliberate geometry change per match — it
   happens once, when the match is known, never while reading.
7. Cooldown tags ("Shield Wall 29:16") showed on a finished match at its
   end, where the class line belongs; they show only while the cursor is
   inside the match or the match is live.
8. The hint line was longer than the window.

The renderer is now part of the harness kit: render before shipping any
report change, the way the Gladdy pass did for Arena Frames.

### D27 pass 9 (2026-09-28) — the replay, redesigned as a spectator view

Devin: "I don't want both teams combined, I want them split, and I really
want more of a replay system. I like the time scrubber but all those
different tabs are hard to understand. I want something that looks like an
arena spectator addon — fully time-scrubbable replay watching where I can
see everyone's GCD, buff/debuff/loss-of-control style class icon
portraits, with all the details below it for meters."

**Engine.** Three records joined the seat so a spectator view can be
read at any second: POWER snapshots (per-mille, with Blizzard's power
type — mana, rage, energy — fed by UNIT_POWER_UPDATE and the 1 Hz pass),
a CAST LOG (`SPELL_CAST_START` opens, `_SUCCESS` closes OK — or records
an instant when nothing was open — `_FAILED` closes FAIL, a kick on the
target closes KICKED, a death or the next start closes anything left at
a 10 s cap; capped at 1500 per seat) from which `StateAt` derives the
cast in progress and the GLOBAL COOLDOWN (the last success within 1.5 s,
as a fraction), and AURA INTERVALS (every APPLIED opens one, REFRESH and
a DOSE extend it, REMOVED or death closes it; buff/debuff and the source
kept; capped at 800 per seat with the overflow counted). Pets' casts
are not their owner's bar. The persisted store carries them; an older
store without them imports with empty logs.

**Window — one screen, no tabs.** The ten stat tabs, the MOMENTS ·
INSIGHTS · HISTORY switch and the breakdown lists are gone from the
window (the engine's Insights and History stay, pinned, for a later
surface). What replaced them, top to bottom:

- TEAMS: your team left, the enemy right, one PLAYER CARD per seat, the
  shape an arena frame or a spectator client uses — class portrait (the
  class ring with CLASS_ICON_TCOORDS, a class-tinted tile with the class
  letter when the sheet is absent), dimmed with a red ring and DEAD
  under it when dead, ringed violet with the control's icon over it and
  the seconds left under it when controlled; name and spec; a health bar
  with "6.2k / 8.2k · 75%" tinted by the HP thresholds; a power bar in
  the power's color; a CAST BAR that shows, in order of what matters, the
  control on them (violet, counting down — a controlled player is not
  casting anyway), the cast in progress with its time left (accent), a
  kicked cast (red, for a second and a half), or the GCD sweep (dim); a
  row of buffs (green border) beside the running cooldowns (gold border,
  minutes or seconds left over the icon); a row of debuffs (red border).
  Icons carry the real spell tooltip plus when it was applied, by whom,
  and when it ends.
- TIMELINE: unchanged — the scrubber Devin liked.
- METERS: one table per team (DMG · HEAL · TAKEN · CC · KICK · K/D), as of
  the cursor. The two teams are never in one list.
- MOMENTS: the feed around the cursor, each row striped in its team's
  color.

The ARENA pane modes in the meter window also stopped interleaving: our
seats first, theirs after, each side ranked within itself.

**Verified in pictures.** Three renders (end, mid-cast at 0:15, mid-stun
at 1:08) drove the two fixes the first render needed: the control word
under a 44 px portrait ("KIDNEY SHOT 1.0s") overran the buff row — the
control's name, bracket and clock moved onto the cast bar and the word
under the portrait is just the seconds; and "29:29" over a 16 px icon
collided with its neighbour — cooldowns past a minute read "29m".

Harness: arena 334 → 370 (Stage G: power fractions and types, a hard
cast start→success, the GCD fraction and its expiry, instants, a kick,
a failed cast, a pet's start, the 10 s cap, buff/debuff intervals with
refresh/dose/removal, newest-first ordering, a stun being both a control
and a debuff, death closing casts and auras, the 800 cap, the round
trip); UI 330 → 304 (the tab checks went with the tabs; new checks cover
the cards, the cast bar text, the loss-of-control text, cooldown and
aura icons and their tooltips, the team-split meters, the striped feed,
play restarting before the gates, and the pane's us-then-them order).

### D27 pass 10 (2026-09-28) — card polish

- **DR on the icon.** A debuff that is also a control at the cursor wears
  the control color on its border and its DR bracket ("½ 4") over the
  icon, so the half-duration sheep is visible on the card itself.
- **Who they are on.** A cast success carries the spell's target in the
  combat log; the cast log keeps it, and the card's name line ends with
  "on Nethra" (class-colored) for eight seconds after the newest targeted
  cast. Honest and cheap: no target polling, nothing inferred from
  damage direction.
- **A cast still open on a live match** fills against a typical three
  seconds and reads "Frostbolt …" instead of crawling toward the ten-
  second cap.
- **5v5 rendered** (the renderer's `5v5` argument synthesizes one through
  the engine): five cards a side, ~870 px tall, no collisions; fits 1080p
  at the default UI scale. A compact card for five-a-side is in the
  backlog if that ever proves tight.

Harness: arena 370 → 373, UI 304 → 306.

### D27 pass 11 (2026-09-28) — what a spectator client says that the cards did not

- **Killed by.** For five seconds after a death the dead card's cast bar
  reads "KILLED ← Frostbolt (Frostweaver)" in red — the blow and the
  killer from the death record, where the eye already is.
- **Pressure.** When nothing else claims the cast bar (no control, no
  cast, no kick aftermath, no GCD) it reads "2 on them: Frostweaver,
  Shiv" — every seat's cast target, inverted once per repaint. "Three on
  the healer" is the sentence a caster spectates for, and the bar was
  idle exactly when it matters.
- **Hover clock.** A dim hairline and the gate-time follow the mouse across
  the plot (the graph's hover hairline, in dim), so a click lands where
  the eye expects. Hidden on leave.
- The readout tells allies from enemies: "1 on them: Frostweaver · with: Leafshade" — a healer casting on a teammate is not pressure. The canned match also stopped driving a seat's HP to zero before its scripted death (non-fatal hits floor at 5%).

Harness: UI 306 → 311.

### D27 pass 12 (2026-09-28) — the recorder and the live path, measured again

The worst-case fixture grew the replay's records: two aura applies a
second per side (each removed 12 s on), a hard cast every 0.75 s per side,
power every second — 2,800 aura intervals and 1,000 cast records over a
ten-minute 5v5, on top of the 803 moments. Under the interpreter:

| call (per repaint) | interpreter |
|---|---|
| StateAt (hp, power, cast, GCD, auras, control, cooldowns; all seats) | 0.22 ms |
| the six-stat meters pass (one CollectRows per stat) | 0.04 ms |
| SeatValueAt DMG at t, ten seats (cumulative cache) | 0.001 ms |
| Pressure / Insights | 0.07 / 0.08 ms |

Two costs were fixed on the way: the meters table had asked each of ten
seats for each of six stats, and the three ledger stats rescanned the
ledger per seat — it now asks the engine once per stat (one ledger pass
each); and "damage up to t" summed up to 1,800 buckets per seat per
repaint — a CLOSED match now keeps a cumulative array per seat and series,
built on first use, session-only (stripped from the store), while a live
match still sums directly. The live-edge path (window open at 10 Hz on a
match in progress) is under half a millisecond per repaint. The
UNIT_HEALTH / UNIT_POWER_UPDATE handler stays a GUID lookup that returns
for anything that is not a seat — nameplates fire it constantly.

The store is the finding, again: that match serializes to **1.2 MB** (was
448 KB before casts, auras and power rode along). Nothing in it is
padding — the aura intervals ARE the buff and debuff rows, the cast log IS
the cast bar — so the response is to bound and to say so: aura intervals
cap at 600 per seat (280 per seat in the fixture; the cap catches the
pathological match), the default Keep Matches drops from 10 to 6 (six
long 5v5s ≈ 7 MB; six typical 3v3s ≈ 2 MB), and the tooltip quotes the
real numbers. Existing saves keep their own value. *Rejected*: dropping
aura names from the store (the tooltip and the control match need them
when the client cannot resolve an id) and a positional interval format
(a second shape to reason about for ~40% off one component).

Harness: arena 373 → 379 (the cache agrees with the direct sum, is built on
first use, is stripped from the store; the 600 cap).

### D27 pass 13 (2026-09-28) — the last desk pass

What a headless mock cannot see was checked the two ways left: Arena
Frames' bytecode order lint over all four Meters files (no local used
above its declaration — the failure that throws only when a branch first
runs mid-match), now a fourth step in the harness README; and every
client API the replay leans on cross-checked against the rest of the
suite for prior use (IsMouseButtonDown, UnitPowerType, UNIT_POWER_UPDATE,
UnitRace, GetSpecializationInfoByID, GetBattlefieldTeamInfo,
GetBattlefieldArenaFaction, SetTexCoord, the drag and Escape idioms).
The remaining unknowns are the in-game ones ASSUMPTIONS 24–36 list, and
they end this loop: the next quality gain needs a queue, not a desk.

### D27 pass 14 (2026-09-29) — the GCD names its spell

Devin: "for the GCD timer, the spell icon and name for what it was spent
on." `StateAt` already found the last cast success to size the sweep; it
now hands that cast to the card, and the cast bar reads the spell's icon
(inline, the suite's 5..59 trim) and name with a dim GCD after it — "they
just Kidney Shotted" reads off the bar instead of a bare sweep. Harness:
arena 379 → 381, UI 311 → 312.

## D28. One fight per match (2026-09-30)

Devin: "for both arena and non arena metrics ensure everything is properly
grouped by match and not combat cycles." D4's segmentation — a fight
closes when the player is out of combat and nothing has happened for
IdleTimeout — is right for a raid and wrong for a game: an arena has a
lull at the pillar, a battleground has the ride between nodes, and each
one split the match into a fight per skirmish, with Follow Combat flipping
the window to LAST at every drop.

The engine gained MATCH MODE: `E.SetMatch(true)` on entering an arena or a
battleground suspends the idle close entirely (Tick returns), so the fight
that opens on the first blow stays open through every lull;
`E.SetMatch(false, name, result, now)` when a winner is declared or the
player leaves closes it named after the match ("3v3 Nagrand Arena",
"Arathi Basin"), flagged `match`, with `success` set from WIN / LOSS (or
left nil when the player left without a result). The end stamp is the
match end, not the last blow, so a game that ends with thirty quiet
seconds keeps them in its duration. Outside a match nothing changed:
pulls still close on idle, and the fight-ends-after slider still governs
them.

The window's KILL / WIPE tags become WIN / LOSS on match segments (raid
words on a game were wrong), so the segment button, the fight list and
the chat report read "LAST — 3V3 NAGRAND ARENA WIN". Arenas drive it from
the recorder's begin / finish / abort; battlegrounds from PLAYER_ENTERING_
WORLD (`instanceType == "pvp"`) and `GetBattlefieldWinner` against
`UnitFactionGroup` (0 Horde / 1 Alliance, the TBC scoreboard convention).
A battleground gets no replay — forty players are beyond the log's reach —
but DAMAGE, HEALING, deaths and the graph read per game there.

*Rejected*: a longer idle timeout inside instances (a two-minute node ride
would still split, and it changes what "fight" means everywhere) and
merging the segments at read time (the same lazy-aggregation trap D6
refused).

Harness: engine 842 → 862 (Stage M: no idle close while armed, the close
on deactivate with name / flag / tag / end stamp, idle back afterwards, a
left match untagged, LOSS, no-fight and unarmed deactivations quiet); the
UI harness drives both lifecycles through the event path.

### D27 pass 15 (2026-09-30) — the match history sidebar

Devin: "add a side bar that lets me navigate my match history." The
replay grew a 172 px column down the left: MATCHES with a count, one
two-line row per kept match newest first ("3v3  NAGRAND ARENA" over
"WIN +14  1:21  Sep 27 21:14", the result colored and a stripe in its
color), the live match on top while one is on, the shown match
highlighted in the accent, the wheel scrolling when the list outgrows the
window, and the running record at the foot ("3 W 1 L"). Click opens that
match at its end. The window widened to 812 px rather than squeezing the
cards (the icon rows need every pixel of a 315 px card); the content
column is one frame anchored past the sidebar, so every band moved with
one number. The header's match menu stays as the keyboard-free duplicate.
Harness after the sidebar and D28: engine 862, arena 381, UI 330; a WIN/LOSS tag declared below its own assignment (a global written, a nil local read) was caught by the UI harness on the way.

### D27 pass 16 (2026-09-30) — the trinket badge

Devin: "in a small icon next to the class icon portraits I want to see a
CD tracker for their PvP trinkets." An 18 px badge on the portrait's
top-right corner carries the medallion's icon (spell 42292): full color
with a gold border while it is up, desaturated with a red border and the
m:ss left while it is down — read from the recorder's TRINKET moments (a
press starts two minutes; nothing seen means up, and the tooltip says
so). The medallion left the generic cooldown row so it is not shown
twice; racial breaks (Will of the Forsaken, Escape Artist) stay there.
The badge sits over the portrait's corner rather than beside it because
the name and bars begin six pixels from the portrait's edge, and a badge
in the corner is what an arena frame does with it.
Harness: UI 330 → 333.

### D27 pass 17 (2026-09-30) — the trinket badge, as Devin wants it

"Show the faction based PvP trinket icon instead of the spell icon, make
it radial, and put it bottom right corner instead of top right." Done as
said: the badge wears the medallion's own art per faction
(INV_Jewelry_TrinketPVP_01 Alliance / _02 Horde), chosen from the seat's
race file token — the scoreboard's faction field is the arena SIDE in
arenas, so the race is the source; an unread race falls back to the
player's faction for our team and the other faction for theirs, the
honest limit of the log. The cooldown is drawn as the client's own
radial sweep (a Cooldown frame, `SetCooldown` set to the cursor's
elapsed and paused where the client offers Pause; otherwise it creeps at
most half a second between repaints before the next reset), with the
m:ss clock on the badge. The badge sits inside the portrait's
bottom-right corner; the control icon moved a little up-left of center
to stay clear of it. The UI mock learned `SetCooldown` so the sweep's
start and length are pinned. Harness: UI 333 → 337.

### D27 pass 18 (2026-09-30) — the trinket was not being tracked

Devin, in game: "the trinket icon looks good but the addon isn't actually
properly tracking the cooldown." ASSUMPTION 27 was wrong: the recorder
recognised a trinket press as SPELL_CAST_SUCCESS of spell 42292 and
nothing else. On this client the medallions and insignias cast their OWN
item spells — which is why Party Frames matches the trinket by five spell
NAMES and Arena Frames never uses the log for it at all, asking the
client instead (`C_PvP.GetArenaCrowdControlInfo`). Both facts were in the
suite; the recorder used neither.

A press is now recorded from three sources, deduplicated in the engine:

- **The client's own answer, for enemies.** `C_PvP.GetArenaCrowdControl
  Info(arenaN)` returns the trinket's spell id and its start and duration
  in milliseconds on the GetTime clock (zero while ready). It is read on
  ARENA_CROWD_CONTROL_SPELL_UPDATE, ARENA_COOLDOWNS_UPDATE, the 1 Hz pass
  and once more as the match ends; each enemy's trinket is requested once
  (`RequestCrowdControlSpell`). The press is stamped when it STARTED, not
  when it was read, and carries the client's cooldown length.
- **The cast event, for our side.** UNIT_SPELLCAST_SUCCEEDED for `player`
  and `partyN` (registered only while a match is on) names the unit and
  the spell id directly.
- **The combat log, by name as well as id.** The five aliases Party Frames
  uses, plus the localized name of 42292 resolved at login; a pet's cast
  is never a trinket.

`RecordTrinket` treats reports within three seconds of a recorded press as
the same press (the client's length refines it), so the three sources and
the once-a-second re-read cannot double count. A press reported after
newer moments were logged is clamped to the ledger's newest time (the
bisection invariant) and its cooldown shortened by the same amount, so it
still ENDS when it really does; the real press time is kept as `t0` for
the dedup.

Harness: arena 381 → 405 (Stage H), UI 337 → 347 (the client path through
ARENA_CROWD_CONTROL_SPELL_UPDATE with a C_PvP mock, the once-only
request, the cast event, the live badge).

### D27 pass 19 (2026-10-01) — Feign Death is not a death

Devin, in game: "feign death is messing up the replay system — it seems to
not recover when the hunter cancels or when it's canceled." Feign Death
puts a real UNIT_DIED in the combat log for the hunter. The recorder took
it at face value: a death, a kill for the last hitter, first blood, every
aura and cast on the seat closed, and — because an arena death is final —
a card reading DEAD until the gates closed. (The core meter's guard,
`UnitIsFeignDeath(token)`, only answers for your own group; the recorder
needed its own.)

Two mechanisms, because either alone leaves a hole:

- **Prevention.** A Feign Death cast or aura (id 5384, or its name, the
  localized one fed at login) stamps the seat; a UNIT_DIED within two
  seconds of that stamp is the feign's own and becomes a FEIGN moment —
  no death, no kill, nothing closed.
- **Recovery.** A seat recorded dead that then ACTS was never dead: a cast
  start or success of its own (not its pet's, and the feign itself
  counts), gaining the feign's aura, a melee swing, or a living health
  reading more than a second and a half after the "death". This also
  covers the reversed order, UNIT_DIED logged before the feign. `Revive`
  removes the death record, takes the kill back, recomputes first blood
  from the deaths that remain, rewrites the DEATH moment as FEIGN so the
  timeline still says what happened then, and reopens the auras the false
  death closed (those nothing re-applied since). Spell damage and dots do
  NOT revive — bolts in flight and dots outlive their caster — and
  neither does the pet. Control and drink records the false death cut
  short stay cut: reopening them would mean unwinding the DR ladder, and
  a hunter feigning out of a CC is rare enough to leave.

A seat can die once (a second UNIT_DIED for a dead seat is ignored), and a
real death long after a feign is a death. While the feign's aura is on,
the replay state carries `feign` and the card reads FEIGN, dimmed with a
grey ring — on the floor, not dead — and returns to normal when the aura
fades or is cancelled.

Harness: arena 405 → 447 (Stage I: the normal order, the reversed order,
an unannounced feign undone by a cast / a cast start / a swing / a living
reading, the auras handed back, what must not revive, first blood passing
to the real death, a localized name); UI 347 → 351 (the enemy hunter
feigns and cancels in the live flow). Unverified in game.

## D29. Dispels — both sides, Mass Dispel's shields, and a dispel log (2026-10-07)

Devin: "commander meters is really not tracking everything I offensively
and defensively dispel when I'm using my MD in arena. I want the dispels
section to properly work for both offensive and defensive dispels as well
as a replay like dispel log that shows the sequencing for what cast got
what buffs."

What was actually wrong, in order of how much it cost him:

1. **Mass Dispel's shield break was invisible.** On this client Mass Dispel
   is three spells (SpellEffect, build 2.5.6.69795): 32375 (the cast; DISPEL
   Magic on allies), which triggers 32592 (DISPEL Magic on enemies), which
   triggers 39897 — effect 108 DISPEL_MECHANIC, mechanic 29 IMMUNE_SHIELD:
   Divine Shield, Ice Block, Blessing of Protection, Divine Protection. The
   first two log SPELL_DISPEL; a mechanic removal does not (A40) — the
   shield just fades. Neither engine ever saw the play that matters most.
2. **The meter window's DISPELS mode dropped the opening.** Utility never
   opened a fight (D17), and in an arena the fight opened on the first blow
   (D28), so the gates purge and an opening Mass Dispel landed before any
   fight existed and were thrown away.
3. **No side.** DISPELS was one number keyed by aura, purges and cleanses
   mixed. The arena engine split them by comparing teams, which fell
   through to "defensive" whenever the far end was a pet (Purge on a
   felhunter).
4. **Nothing showed the sequence.** The replay's meters band had no dispel
   column and the six-row moments feed interleaved dispels with everything.

The fix:

- **CommanderMetersDispel.lua** (new, pure, loaded before both engines):
  the side rule — the removed aura's TYPE, SPELL_DISPEL's 18th argument:
  BUFF off = offensive, DEBUFF off = defensive, SPELL_STOLEN always
  offensive; the engines' sides decide only when the log leaves it out —
  and the **Mass Dispel correlator**. A landing (the 32375 cast success,
  or any SPELL_DISPEL from the family) and a shatterable aura fading off
  the OTHER side pair within a lopsided window: 0.3 s fade-before-landing
  (log print order only), 0.6 s after. A shield that ran its full DB2
  length (±0.5 s) expired; an Ice Block cancelled during the 1.5 s cast
  fades well before the landing and is not credited. If the log DOES name
  the removal (A40 wrong, or a BoP the 32592 half dispelled normally), the
  correlator either suppresses the inference (named first) or hands the
  engine its earlier credit to upgrade (named after) — never two counts.
- **Group engine**: actors gained `purges` / `cleanses` and two record
  lists, `purgeSpells` / `cleanseSpells` (replacing `dispelSpells`;
  session snapshot v3 refuses v2, the D26 precedent). Inside a match a
  dispel OPENS the fight (D28 amended: the gates purge is the match's first
  action); outside one utility still never opens a fight. It sees aura
  APPLIED/REMOVED now, but only to ask "is this an enemy shield?" — one
  lookup, out. Our Mass Dispel's shattered shields land on the offensive
  list by name.
- **Arena engine**: the side rule, a pet target folds to its owner's seat
  (counted as the warlock's loss, logged with the pet's name), seats gained
  `dispelFails` (SPELL_DISPEL_FAILED, and SPELL_MISSED of a dispel tool —
  RESIST, IMMUNE under Cloak) and `shatters`. The match gained the **dispel
  log**: `dlog` = casts in time order, `{t, src, id, name, pet, hits}`, a
  hit `{dst, pet, dn, id, name, off, steal, inf, r}`. One caster's
  same-named removals within 0.6 s are one cast (a Mass Dispel's ten arrive
  in one instant; Abolish Poison's pulses are pulses); the Mass Dispel cast
  success opens its record so a Mass Dispel into nothing still reads as a
  press. Bounded: 400 casts × 24 hits. DISPEL moments carry `by` (the cast
  name), `byId`, `pet`, `inf`. A match saved before the log rebuilds one
  from its DISPEL moments on first read (`_dlog`, session-only, stripped).
  The DISPEL stat's `count` is the offensive share (`countIf` on the
  ledger pass), so any pane can print the split as of any cursor.
- **Replay**: a DISPELS header button toggles a 300 px drawer to the right
  (`db.ArenaDispelLog`, default open; the content column is now a fixed
  width so the drawer widens the window and never stretches the replay).
  Top: OURS / THEIRS / OFFENSIVE / DEFENSIVE filter chips. Then a per-seat
  tally as of the cursor — OFF, DEF, MISS, LOST (their buffs purged), FREED
  (their debuffs dispelled). Then the log: a cast line (time, caster, the
  spell, "3 removed" / "took nothing") and its removals under it in log
  order (aura → target, tagged PURGE / STEAL / SHATTER / DISPEL / RESISTED
  / IMMUNE). Past-the-cursor lines dim, the cast at the cursor is lit, a
  click moves the cursor; the list follows the cursor until the wheel
  scrolls it and follows again when the cursor moves. A finished match
  reads from the gates; a live one keeps the newest at the bottom. While
  the drawer is open, dispels mark the timeline as dots on the caster's
  side (offensive cyan, defensive mint — `statCleanse`, a new semantic
  color). The moments feed names the cast ("PURGE Thorns off Leafshade ·
  Mass Dispel", SHATTER for an inferred break).
- **Meter window**: DISPELS rows read total + "off/def" in the small
  column; the tooltip names both sides and each side's top auras; the
  detail lists OFFENSIVE · PURGED / STOLEN and DEFENSIVE · CLEANSED (a
  records list in the second slot keeps its icons and whole names —
  ShortName would cut "Mind-numbing Poison" at the dash). A fifth arena
  mode, ARENA DISPELS, shows both teams with the split. The arena seat
  tooltip gives off/def, shields shattered, dispels that took nothing, and
  purged-off / cleansed-off.

*Rejected*: guessing a shatter from a Mass Dispel CAST alone (no fade →
nothing broken; a cast is not a removal); a fixed window both ways (a
cancelled Ice Block during the cast would be credited); a second meter mode
per side (the split belongs on one row — two modes would rank the same
priest twice); adding a dispel column to the replay's meters band (93 px of
names left for 63, and the drawer's tally says more).

Harness: engine 862 → 910 (record-sum and split invariants on every
actor; Stage N: the gates purge in and out of a match, our Mass Dispel's
bubble on the offensive list, named-later not double counted, expiry and
own-team shields not credited, Overall agrees); arena 453 → 519 (Stage J:
pet folding, sides with and without an aura type, cast grouping, both
Mass Dispel halves under one press, a whiff, the shatter in both log
orders, named-later upgrade, named-first suppression, full-length expiry,
the cancelled Ice Block, own-team and enemy-priest shields, failed and
missed dispels, the stat split / tally / index as of a cursor, a pre-log
match rebuilt, the store round trip); UI 353 → 399 (the drawer: lines,
order, tags, tooltips, click, dimming, filters, wheel/follow, toggle and
the remembered choice, ARENA DISPELS rows, the DISPELS mode's split, tooltip
and both detail lists). The canned arena match gained a Mass Dispel
(roots off the mage, Gift of the Wild and Thorns off the enemy) and a
resisted Devour Magic; the canned fight a purge. Unverified in game — A40
to A42.

## D30. Arena ratings on bar and seat tooltips, from Commander Muster (2026-10-16)

Devin wants a player's 2v2/3v3/5v5 ratings wherever their name shows. Meters
asks `CommanderMuster.RatingsLine` (an OptionalDep), the suite's one rating
source. It merges what Muster has inspected with the Commander Ladder web
feed, which is the only way to know an enemy's rating.

- **Placement:** an ARENA line second on the bar tooltip, and after the
  team line on the arena seat tooltip, which the Arena Report portraits
  open too.
- **Players only:** a pet's or creature's GUID never asks, so its name never
  reaches the feed as a player's.
- **Current, not historical:** these are the player's ratings now, with
  their age, not what they had in the match. That is why the report cards
  carry no rating suffix: on a replayed match it would read as the match's
  number.


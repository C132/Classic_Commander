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

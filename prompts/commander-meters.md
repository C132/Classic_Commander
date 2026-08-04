# Commander Damage Meter — One-Shot Build Brief

## Mission

Build a complete, working damage meter named Commander Meters, as a new addon inside my Commander suite, targeting WoW TBC Classic. Determine the exact client and interface version from the existing Commander `.toc` files rather than asking me. Ship it in one pass. Do not stop to ask questions, do not propose a plan and wait, do not deliver a spec for review. Investigate, decide, build, self-verify, and iterate until the acceptance criteria in §7 all pass — then hand me the finished addon plus the reports in §8.

## Autonomy rules

* Never block on me. When something is ambiguous, pick the most conservative option that preserves correctness, proceed, and record the call in `DECISIONS.md` with the alternatives you rejected and why.
* Never guess silently. Anything you couldn't verify against the live client goes in `ASSUMPTIONS.md` as a numbered item with a one-line in-game test I can run to confirm it.
* Loop until green. Build, run your own fixtures, check the invariants in §7, fix, repeat. Do not hand me code with a known-failing invariant; hand me code plus a note if one is genuinely unreachable without a live session.
* Scope discipline. The non-goals in §9 are hard. If you think of a feature not in this brief, it goes in `BACKLOG.md`, not in the addon.

## 1. Authority ranking

You have Recount and Epic DM available. When they conflict with anything, this ranking decides:

1. The live TBC Classic API — ground truth for what's possible.
2. Commander's own conventions — authority on structure, naming, and style.
3. Recount as a design reference — authority on what a meter tracks and how it presents it.
4. Recount and Epic DM's actual code — no authority. Assume nothing.

Recount is broken on TBC Classic. Any API usage, event signature, or field access copied from it is suspect by default. Never carry an API call across from a reference addon without independently confirming it exists and behaves that way in this client.

Epic DM is a negative reference. It claimed simplicity and didn't deliver, and its theming is heavily over-engineered. Read it to catalogue what went wrong — which abstraction, which system, which generality-for-its-own-sake. Do not carry its architecture, its theming layer, or its abstractions into Commander.

## 2. Start by reading, not writing

Before any code, work through the following. Findings feed the build and get summarized in `FINDINGS.md`:

The suite. How a new addon is registered, loaded, and namespaced. Which shared libraries and internal APIs already exist that the meter must consume instead of reimplementing — event dispatch, timers, table pooling, string formatting, class/color lookup, unit resolution. Config and profile system. Saved-variable conventions and migration pattern. The shared frame/widget layer, skinning, fonts, textures, anchoring helpers. Slash commands, localization, error handling, debug logging. Build and packaging setup. Any existing test harness.

Why Recount breaks here. For each failure, name the stale assumption underneath it. That list is your requirements list — every assumption there is something the data layer must handle correctly and explicitly.

Where Epic DM's complexity came from. Specific mechanisms, so you can avoid them by name.

## 3. TBC Classic constraints

Verify each against the live API. Do not take my word or a reference addon's word for any of them. Anything you can't verify without being in-game becomes a numbered item in `ASSUMPTIONS.md`, and the code must fail loudly rather than silently mis-attribute if the assumption is wrong:

* Combat log payload: how event data is retrieved (event args vs. a getter function), exact field order, which fields exist in this client.
* Absorbs: a field on damage events, a separate event, or both.
* Healing: whether overheal and absorb fields are present and reliable.
* Encounter boundaries: whether encounter start/end events exist at all. If they don't, segmentation is entirely heuristic — combat entry, combat exit, idle timeout — and the code and docs must say so rather than pretending otherwise.
* Pet and totem ownership: what source flags actually tell you and what must be tracked manually. Handle warlock and hunter pets, totems, and any temporary summons that deal damage in TBC.
* GUID formats for players, creatures, pets, and totems.
* Timer, table, and string APIs available in this client vs. retail.

Where a capability is genuinely absent, design around the absence explicitly. Do not emulate a retail behavior the client can't support.

## 4. Architecture

Build in this order, each layer independently testable: ingestion → data model → time series → modes → UI.

1. Ingestion. Parse the combat log from first principles based on §3, not from Recount's parser. Also ship a debug command — following Commander's existing slash-command conventions — that dumps raw events to saved variables, so I can confirm your schema against a real session.
2. Entity resolution. Stable IDs, never display names. Pets, guardians, and totems attribute to their owner. Reuse Commander's existing unit resolution.
3. Data model. actor → ability → target. Per ability: hits, crits, misses, min/max/avg, absorbed. Damage taken stored symmetrically.
4. Time series. Per-actor fixed 1s buckets recorded as events arrive — not derived after the fact. This is part of the data model, not the UI; the graph is unbuildable later if it isn't here now. Document bucket size, smoothing, and memory cost as buckets × actors × segments.
5. Segmentation. Overall / Current / Last / Fight #N, with combat entry and exit detection and an idle timeout. Decide and document whether the rate denominator is actor active-time or wall-clock fight duration — this is the single biggest source of disagreement between meters.
6. Modes as data, not code. Damage Done, DPS, Damage Taken, Healing, Deaths. Adding a mode is a table entry, not a new file.
7. UI. Main window of sorted bars: rank, name, value, % of total, per-second rate. Repaint throttled to ~2Hz regardless of event rate. Click-through detail view with ability and target breakdowns. Death log: last 10 events before each death with timestamps and remaining HP.
8. Memory. Retention and pruning policy covering time-series data. State the ceiling and enforce it.

## 5. The three things this addon exists to do well

Graph view. Multi-actor lines over fight elapsed time, hover readout at a point, show/hide individual actors. A graph across "Overall" spanning idle time between pulls is meaningless — decide explicitly what the graph shows per segment (per-fight only, or concatenated with gap markers) and document it. Graph data participates in retention and pruning.

Current vs. Overall, unambiguously. The active segment is visible at all times in the window chrome, never inferred. A user glancing mid-pull must never be unsure which numbers they're looking at. Switching is explicit; if the meter auto-switches to the current fight on combat start, that's a setting with a stated default and a visually obvious transition. Overall, Current, Last, and Fight #N are all reachable without a menu deeper than one level. The same segment selection applies consistently across bars, detail view, and graph — no view silently showing a different segment.

Reset. Reset Overall and reset Current are separate, clearly labeled, and neither is buried. Document what reset does to accumulated totals, the segment list, the time series, an in-progress fight, and open detail/graph windows. Resetting Overall while in combat is a real case — decide it deliberately. Optional auto-reset triggers (new fight, entering an instance, ready check) are off by default and independently toggleable. Reset is instant and total: no lingering state that makes the next fight's numbers wrong.

## 6. Visual direction

SC2/RTS-inspired, carrying Recount's functional clarity.

Governing principle: RTS interfaces are built for someone who is not looking at them. That's exactly a combat meter's job. Every visual decision serves peripheral glanceability, not decoration.

* Dark, low-luminance chrome with angular panel edges and thin accent rules. Restrained metallic/tech framing. Chrome recedes; data reads.
* Uppercase condensed labels for headers and segment/mode selectors. Tabular (fixed-width) numerals so digits don't jitter as values climb — a bar whose number reflows is unreadable in peripheral vision.
* Stable layout. Bar height, name column width, and number column position do not shift between frames. Rank ordering may change; geometry may not.
* Class colors are data, not decoration. They survive the theme intact and are the primary encoding on bars. The SC2 palette lives in chrome, accents, and selection states — never overriding a class color. Resolve this tension deliberately and record it in `DECISIONS.md`: an SC2 palette is cohesive because it controls every color on screen, and eleven fixed class colors are being injected into it.
* One accent color for active/selected state. Not a palette.
* Preserve deliberately from Recount: permanent visible segment selector, bar rows dense enough to read a raid at a glance, click-through to detail with no ceremony.

Anti-goals: gradients as ornament, glow effects, animated transitions on value changes, decorative borders that consume vertical space, anything that makes the window prettier at a standstill and worse mid-pull.

## 6.5 Settings

Don't invent a settings list and don't port Recount's wholesale. Derive it:

1. Enumerate Recount's settings and sort them into three buckets: load-bearing (a real user changes this and the meter is meaningfully better for them), legacy (exists because of a retail-era feature, a version quirk, or an old bug), and decoration (cosmetic knobs that exist because the option was cheap to add).
2. Keep the load-bearing bucket. Drop the other two entirely. Anything in §5 that the brief explicitly calls a setting — auto-switch on combat start, the auto-reset triggers — is load-bearing by definition.
3. Cross-check the survivors against the rest of the Commander suite. Where another Commander addon already exposes an equivalent option, match its name, its wording, its default, and its position in the config layout exactly. A user who has configured one Commander addon should find nothing surprising here.
4. Anything Commander handles suite-wide — profiles, positioning, visibility rules, whatever the inventory in §2 turns up — is not re-implemented as a local setting. Consume the suite mechanism.

State the resulting count in `DECISIONS.md` and treat it as the ceiling. Every setting added past that point requires a justification written into `DECISIONS.md` alongside it. Settings that exist to paper over an undecided default are not settings — pick the default instead.

## 7. Acceptance criteria — verify these yourself before handing back

Correctness. Build a replayable fixture: a canned event stream covering a multi-actor fight with pets, totems, crits, misses, absorbs, overheal, and at least one death. Run it and assert:

* Sum of per-ability == actor total == sum of per-target.
* Pet and totem damage appears exactly once, under the owner.
* Time-series buckets sum to the segment total.
* Segment totals are consistent: Current during a fight becomes Last after it, and Overall equals the sum of segments.
* Reset Current leaves Overall intact; reset Overall clears everything including time series.
* Replaying the same fixture twice from a clean state produces byte-identical results.

Performance. Sustained raid-scale event throughput with no measurable frame-time impact. Repaint stays throttled under load. Report measured numbers, not assurances.

Conformance. The addon is indistinguishable from something I wrote for the suite: same file layout, naming, config plumbing, window chrome, error handling. Zero vendored dependencies that duplicate something Commander already provides. If you wrote a utility, confirm the suite didn't already have it.

Simplicity budget. Simplicity is a constraint with numbers, not an adjective:

* Theming is a single flat table of constants — colors, fonts, textures, spacing — consumed directly by widgets. No skin engine, no theme registry, no runtime theme switching, no per-element override system. A widget that needs a color reads a constant.
* No abstraction introduced for a single call site.
* Settings count at or under the ceiling you derived in §6.5, with the derivation shown.
* No subsystem that needs a diagram to explain.

Report your actual numbers against each line.

## 8. Deliverables

The working addon, plus:

* `FINDINGS.md` — suite inventory, why Recount breaks here, where Epic DM went wrong.
* `DECISIONS.md` — every ambiguity you resolved, the alternatives rejected, and why.
* `ASSUMPTIONS.md` — numbered unverified API assumptions, each with a one-line in-game test.
* `BACKLOG.md` — anything you deliberately didn't build.
* A final report: acceptance criteria results with measured numbers, and the top three things most likely to be wrong when I first run it in-game.

## 9. Non-goals

No cross-client sync. No settings beyond the derived list in §6.5. No threat tracking. No retail-parity features this client can't support. No theming system beyond §7.

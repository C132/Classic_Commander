# Commander Threat — Decisions

**D1 — Poll-only data path.** A 4 Hz ticker re-reads the whole truth
(roster × display mob, plus the nameplate sweep) instead of registering
`UNIT_THREAT_LIST_UPDATE`/`UNIT_THREAT_SITUATION_UPDATE`. Rejected: Omen's
event-driven-with-throttle shape. The events would only wake a repaint the
next tick performs anyway, their delivery on this client is an unverified
assumption (the MINIMAP_PING lesson says event names can lie here), and a
missed event can never wedge a stale warning when every tick recomputes
from scratch. Cost: ~10 C-calls per tick in a party, ~80 in a full raid —
Omen-era addons did the same per event, which was busier.
PLAYER_TARGET_CHANGED and the combat edges get an immediate out-of-band
tick so a mob switch answers same-frame.

**D2 — One bar scaling for every role: scaled percentage.** Full bar width
IS the pull point; the aggro holder rides at 100 and everyone else's bar
shows true distance to the ledge. Rejected: Omen's relative-to-top scaling,
where the last safe pixel sat at an unmarked ~91% (melee) or ~77% (ranged).
The API already folds the 110/130 thresholds into scaledPercentage — using
anything else would re-derive what the client computes. No raw-vs-scaled
toggle: scaled is strictly the more honest encoding, and a toggle to be
less honest is not a setting.

**D3 — Settings ceiling: 10, re-derived to 11 in D13 and 13 in D14/D15.**
EnableThreat, Role, WarnAt, WarnSound, WarnFlash, ShowTPS, BarRows,
FrameWidth, CombatOnly, AccentColor (+ the shared HudChrome quartet, owned
by the suite mechanism, per the Meters counting convention). MetersEmbed is
the eleventh (D13); BoardLayout the twelfth (D14) and TargetEmbed the
thirteenth (D15) — all three Devin-requested, each justified where it
lands. Every one of them answers *where the module draws*, which is the one
axis the original ten never covered. Derived by sorting Omen's option sprawl into
load-bearing / legacy / decoration and keeping only the first bucket, then
cross-checking survivors against the suite: Bar Rows and Window Width take
Meters' names, ranges, and defaults exactly. Dropped: bar textures and
fonts (theme constants), announce-to-chat (public-output policy), per-mob
window (BACKLOG), a warning-sound picker (see D5), per-role thresholds
(one slider, role-contextual reading — the tooltip explains it).

**D4 — Role is per-character, outside the defaults table, default Damage.**
`RoleByChar` is keyed Name-Realm in the account DB and deliberately NOT in
`DefaultSettings`, so Restore Defaults never wipes a character's role (the
Orders rally-point precedent for prized per-character state; also the
Quartermaster lesson — per-char opt-state must be a keyed map, never a
shared scalar). Default is Damage for everyone: a class-based guess
(Warrior→Tank?) is wrong often enough to mislead, and tanks and healers
know who they are.

**D5 — Warnings are engine-owned edges with hysteresis, one fixed sound.**
Fire once at the threshold, re-arm 10 points below (or on mob change), plus
a 3-second per-type gap as a belt. Approaching the line is quieter than
aggro actually moving (vignette 0.5 vs 0.85; INBOUND 0.7). One sound — the
raid-warning klaxon: Production's Ready Sound dropdown is a *preference*
about a chime; an alarm has one correct sound, and a picker for it would be
decoration.

**D6 — Aggro-lost requires a contested list; first sight adopts silently.**
A mob dying empties its list — that must never read as "you lost it", so
the loss edge fires only when someone else still stands on the list.
Fresh state (login mid-fight, role switch, mob switch) adopts the current
tanking fact without an edge, so switching role can never manufacture an
alarm from old state read through new rules.

**D7 — Tank held/loose counts use a group-engagement test.** A plate counts
as engaged only when the player is on its threat list or its target is in
the group (player, pet, party/raid member) — never bare "in combat", or
another group's world mobs would pad the counts. Coverage follows enemy
nameplate visibility; the option tooltip says so out loud (the Shield
targeter-counter precedent).

**D8 — The healer's number is the worst mob, not the target.** The sweep
computes the player's scaled percentage against every engaged plate; the
headline, the pull warning, and PEAK naming all key on the maximum. INBOUND
fires on a mob *targeting* the healer regardless of threat numbers — being
targeted is the healer's real signal, and it works with no target selected
at all.

**D9 — The holder stripe is white, not accent.** Who the mob is on is
DATA; the accent marks chrome/active only (the Meters D20 discipline).
Status colors are role-aware semantics: SECURE green for a tank is the
same fact as AGGRO red for a DPS.

**D10 — TPS is a 1-second-sampled EMA (α 0.4), drops clamp to zero.** The
API reports state, not rate, so this is the addon's only derived number.
Threat drops (fade, feign, wipe) read as 0 output, not negative. The
column is optional; off gives the name column the room back.

**D11 — Pets render neutral.** `UnitClass` on pets returns creature
classes ("Warrior" hunter pets) that would paint misleading class colors;
pets get the steel neutral and sort like anyone else. Pets stay in the
chaser scan — a Growling pet rips like anyone else.

**D12 — Board default is LEFT (Meters sits RIGHT).** The two combat boards
flank the field of view; both are HudChrome consumers so either moves
anywhere.

**D13 — Meters embed (2026-08-03, ceiling 10 → 11).** "Embed in Commander
Meters" (default off, grayed without Commander_Meters) retires the
standalone board and serves the threat list as a live THREAT pane through
Meters' external-mode contract (`CommanderMeters_RegisterExternalMode` —
see Meters D22). The split is where it shines: damage beside threat in one
window. Division of labor: Threat keeps the engine, the 4 Hz sampler, and
EVERY warning (klaxon, vignette — only the rendering surface moves; the
board flash has no surface while embedded and the header flash simply goes
unseen); Meters owns arrangement and never interprets. The provider hands
back finished strings with the scaled percentage in the always-visible
value column — Meters' split condenses to rank/name/value, and the % is
the number that matters — absolute threat and TPS ride the wide-window
columns. Enabling is the explicit action that opens Meters' split
(ShowExternalPane); the silent login path only registers, letting Meters'
own SplitOpen/SplitMode persistence decide the layout. Everything
soft-fails (the TopBar pattern): Meters absent → checkbox grayed, a saved
`true` degrades to the standalone board; Threat absent → Meters' saved
THREAT pane falls back to its default mode. What the embed costs, stated
honestly: no role headline, no footer facts (holder / HELD-LOOSE /
INBOUND text), no holder stripe, no player-row pinning — the pane is the
LIST, and the warnings carry the role story. Rejected: forcing the split
open at every login (Meters' persistence already remembers), and a
board-inside-Meters frame graft (two addons' pooling and click-through
rules tangled for no user benefit).

**D14 — Board Layout is one dropdown with three values, not two settings
(2026-08-04, ceiling 11 → 12).** Full / Compact / Hidden. Compact is a
DENSITY table, not a second painter: every metric that differs between the
layouts (heights, three type sizes, four column widths) lives in one table
per layout, `M` points at the active one, and the painters never branch on
it. What compact actually does: the headline block folds up into the header
strip at reading size (13pt, still the largest thing on the board) and the
rows tighten 16 → 13px — about a third less height for the same facts. The
single fact it gives up is the mob NAME, because that is the one thing the
target frame already tells you (and D15 now puts the number there too);
everything load-bearing — percentage, label, status word, bars, footer —
survives. Hidden retires the board outright, which is what someone running
the target-frame readout or the Meters embed alone actually wants; it costs
nothing extra because it is a third value on a dropdown that had to exist
anyway, and it is deliberately stronger than the unlock override (there is
nothing to place). Applied live, never baked: nothing in the density table
is a creation-time property once every fontstring is registered by SIZE KIND
rather than a number, so Full ⇄ Compact needs no `/reload` note the way the
accent does. Rejected: a separate "Hide Board" checkbox (two settings for
one question), and a compact mode that dropped the footer instead of the mob
name — the tank's LOOSE count is the footer's whole reason to exist.

**D15 — Target-frame readout is additive, and shows the number only for the
targeted mob (2026-08-04, ceiling 12 → 13).** Six modes over two surfaces:
Off / Bar / Below Portrait / Bar + Below Portrait / On Portrait / Bar + On
Portrait. BAR is a 4px fill along the bottom of `TargetFrameHealthBar` (the
board's D2 encoding unchanged — full width IS the pull point); the other two
place the percentage on a small plate reading AGGRO once the mob is yours.
Role-adaptive like everything else: Damage and
Healer see their own climb, a tank sees the chaser's climb while holding and
their own climb to take it back when not. Unlike the Meters embed this
RETIRES nothing — it is a second surface for the same tick, so the board,
the embed, and every warning are untouched (pair it with Board Layout:
Hidden for a target-frame-only setup). Two hard rules: it draws only for an
ATTACKABLE target, because an unattackable one means the engine's list came
from target-of-target (Omen's fallback, D1) and that mob's number does not
belong on this frame; and nothing it creates takes the mouse, because the
target frame is protected and its clicks are load-bearing (the
Commander_Resources player-frame precedent). Alerts wash the whole health
bar red rather than flashing one surface, so the cue reads the same in every
mode. Blizzard's own `TargetFrameNumericalThreat` is left alone: it
is CVar-gated, off by default, sits above the frame, and is not
role-aware — suppressing it would need a hook on
`UnitFrame_UpdateThreatIndicator` to buy nothing. Rejected: reusing its frame
as the surface (its position and art are not ours to redefine), and putting
the bar under the mana bar (it would land on frame art whose geometry we
have not verified; the health bar's rect is known).

**D15a — The percentage anchors to the PORTRAIT, on its own plate (revised
2026-08-04, same day, on Devin's read of it in game).** It first shipped as
bare outlined text above the health bar's right end; that lives in the name
band, which a long name or a rare/elite border can crowd, and it read as
loose text rather than a readout. Both replacements key off
`TargetFramePortrait` instead: centred and hung 1px under its bottom edge,
or centred 2px inside its top edge. The portrait is the target frame's one
landmark whose rect never moves with a name, a level, or a border variant,
which makes it the only honest anchor on that frame. The plate is the
board's own language — dark fill plus the same 1px steel edge from
`MakeEdge` — because the number now lands ON portrait art, where the
outline alone was carrying the whole legibility burden; it sizes itself from
`GetStringWidth`, and only when the string actually changes, since this
repaints 4×/s. ONE placement at a time, not both: the two are alternatives
for the same number, and the mode names carry the placement so the
surface-map table stays a pure on/off. No portrait resolvable → the plate
falls back to the old health-bar anchor rather than vanishing. The vocabulary
change (`TEXT`/`BOTH` → `BELOW`/`BAR_BELOW`) rides a real DB migration
(v1 → v2) instead of a silent reset: the old names had nowhere to say WHERE.

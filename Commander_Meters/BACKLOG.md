# Commander Meters — Backlog

Deliberately not built. Each entry was considered and cut for scope or
simplicity; none is blocked by the architecture.

- **Pet damage taken.** Taken is tracked for players only; a pet's incoming
  damage is currently dropped (documented in DECISIONS D3 scope).
- **Total row** (raid-wide summary bar above the ranks) and a raid-DPS
  headline in the header.
- **Overkill tracking** as a per-ability stat (the field is parsed and
  discarded; only the death log benefits today).
- **School/element breakdowns** (damage by school; the hit-table stats —
  crush/glance/resist/block — shipped in batch 2).
- **Extra modes**: power gains, friendly fire, DOT/HOT uptime (interrupts,
  dispels, and CC breaks shipped in batch 2). Modes are table entries, so
  each is data work, not architecture work.
- **Boss-only segmenting** (Recount's SegmentBosses; kill/wipe tagging
  shipped in batch 2).
- **Whisper target for reports** (the Share menu covers the group channels;
  whisper needs a name prompt, which needs an edit box).
- **Full fight-history persistence** (Overall + Last ship opt-in as of
  batch 3, DECISIONS D18; the other nine kept fights stay session-only —
  persisting them all multiplies the SavedVariables size for segments
  nobody revisits after a reload).
- **Same-class line differentiation** in the graph (Recount uses 8 shade
  variants per class; two mages currently share a color and are told apart
  by the legend/hover).
- **Keybindings** for mode/segment cycling and window toggle.
- **Window snap/grouping, multiple windows, realtime strips** — Epic DM
  territory; explicitly out.
- **Cross-client sync** — non-goal, permanently.

## Arena (D27) — considered and not built

- **Positioning / pillars** — the log has no positions; nothing to replay.
- **Cross-match trends** (win rate per comp, average first-blood time,
  DR bracket distribution) over the saved history — the data is on disk.
- **Exporting a match as text** beyond the five-line share (a chat
  channel cannot carry a ledger; a copy box would need an edit box).
- **Damage by school / partial resists** on arena seats (the core
  engine tracks them; the arena seat keeps totals, crits, misses, absorbs).
- **Pet HP / pet deaths** as seat events.
- **Insights and History surfaces.** Both engine passes (`A.Insights`,
  `A.History`) stay pinned in the harness; their tabs left the replay
  window in D27 pass 9 (Devin: "all those different tabs are hard to
  understand"). A home for them — a tooltip on the match title, a
  second page — is a design question, not a data one.
- **Cast bar duration for open casts on a live match** (the bar has no
  end until the success lands; it fills against the 10 s cap until then).
- **Compact 5v5 cards.** Five cards a side stand ~870 px tall; a
  two-row card (buffs and debuffs sharing one row) would save ~100 px if
  a smaller screen ever needs it.

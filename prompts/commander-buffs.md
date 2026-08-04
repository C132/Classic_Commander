# Commander Buffs — player auras on the player frame

> Commander_Buffs v1 was retired 2026-07-06 because Edit Mode already moves
> the default buff frame. This is a different module wearing the old name:
> it does not *move* Blizzard's buff frame, it **replaces** it with a block
> that mirrors the target frame's aura design, and it puts the single most
> interesting thing in your aura stack on your portrait.

## Vision

Your unit frame should read like the target's. On the target you already
get the whole picture in one glance: a tight grid of small icons hugging
the frame, debuffs rimmed by school, everything anchored to the portrait
you are already looking at. On yourself the client instead flings your
auras to the far corner of the screen, so the two halves of the same fight
live 1400 pixels apart.

Two features, one idea — *put the player's aura truth where the player's
eyes already are*:

1. **The block** — every player buff and debuff rendered next to the player
   unit frame, in the target frame's layout language, with Blizzard's own
   frames hidden.
2. **The sentinel** — one (or up to three) portrait icons showing the
   *most interesting* aura on you right now, chosen by a priority engine,
   wearing a radial duration ring.

The sentinel is the part that has to be smart. A stack of 20 auras always
contains exactly one fact that matters this second — you are Ice Blocked,
you are Polymorphed, your Bloodlust has 4 seconds left, you are stacking
Sunder 5 — and no static list finds it. So the priority system is the
product, and its **editor** is a first-class window, not a settings row.

## Feature 1 — The aura block

### Layout, mirrored from the target frame

Blizzard's target frame lays its auras out with a handful of constants
(`LARGE_AURA_SIZE = 21`, `SMALL_AURA_SIZE = 17`, `AURA_OFFSET_Y = 3`,
`NUM_TOT_AURA_ROWS = 2`, buffs and debuffs in separate row groups). We
copy the *design*, not the code: our own frames, our own pool, insecure,
so nothing we do can be blocked mid-combat.

- One block frame anchored to `PlayerFrame` (default `BOTTOMLEFT` of the
  frame's art, growing right), with saved offsets so it can be nudged.
- Buff rows and debuff rows are separate groups. Group order is the
  **Buffs On Top** property (below). Icons wrap at `IconsPerRow`.
- Buff icon size and debuff icon size are separate sliders defaulting to
  the client's own 21px, spacing defaults to Blizzard's 3px.
- Debuffs wear a rim colored by `DebuffTypeColor[dispelName]` — the same
  encoding the target frame uses, so the grammar transfers with zero
  learning. Buffs cast by you may wear a faint gold rim (`MineRim`).
- Stack count bottom-right; remaining time under the icon (`ShowTimers`),
  or a radial sweep on the icon itself (`IconSweep`), or both.
- Growth direction (`GrowRight`) and row growth (up/down) follow from the
  anchor choice, so a left-side player frame can grow left.

### The Buffs On Top property, mirrored from Target

Edit Mode ships a per-unit-frame **Buffs On Top** setting; the target
frame is the only unit frame most people ever set it on. Treating it as a
property to *mirror* rather than duplicate is the whole trick:

- `BuffsOnTopMode` = `MIRROR_TARGET` (default) | `ON` | `OFF`.
- `MIRROR_TARGET` reads the target frame's live value — `TargetFrame.buffsOnTop`
  first (the field Blizzard's own layout code reads), then the Edit Mode
  manager's setting lookup, both pcall-guarded — and re-reads on
  `EDIT_MODE_LAYOUTS_UPDATED` and `PLAYER_ENTERING_WORLD`.
- When neither source answers, mirroring degrades to `OFF` and the panel
  says so instead of silently lying.
- The same mirroring hook is written to take more properties later (icon
  size, stride); Buffs On Top is the one that ships.

### Hiding the default frames

`HideDefaultAuras` (default on, and *only* honored while the block is
enabled — the module must never leave you with no auras at all):

- `BuffFrame` and `DebuffFrame` are hidden and kept hidden: unregister
  their events, `Hide()`, and re-hide from a `hooksecurefunc` on their
  `Show`/`UpdateAuras` so Edit Mode and layout changes cannot resurrect
  them. Never in combat — hides are deferred to `PLAYER_REGEN_ENABLED`
  (the Console viewport lesson: even non-combat-looking frame work fired
  from a settings callback can be refused).
- Turning the option off restores the frames' events and shows them again;
  a `/reload` is never required in either direction.
- Temporary weapon enchants (`TemporaryEnchantFrame`) are a separate toggle
  (`HideTempEnchants`, default off) because our block does not render them.

### What we deliberately do not do

- **No secure buttons.** A frame created from a secure template is
  protected: it cannot be moved, shown, or re-attributed in combat from
  insecure code (the PartyFrames click-cast lesson). An aura block that
  cannot re-lay-out mid-fight is worthless, so the block is display-only.
- Right-click cancel is therefore *best effort*: a pcall'd
  `CancelUnitBuff("player", index)` behind `RightClickCancel`. If the
  client refuses it (it is protected on the retail-era framework this
  build runs), the click is a no-op and the option's tooltip says so.
  Keeping Blizzard's frames visible remains the supported way to cancel.

## Feature 2 — The portrait sentinel

- Up to `Slots` (1–3, default 1) icons on the player portrait. Slot 1 sits
  where the option says (`Anchor` + offsets, default dead center over the
  portrait); slots 2 and 3 trail beside it at `SlotSpacing`.
- The icon is **cut into a disc** by a circular alpha mask (`RoundSentinel`,
  default on) with a matching circular rim, so it reads as one shape with
  the ring around it rather than a square fighting a round timer. The block
  gets the same option, defaulted off — its square grid is the thing that
  mirrors the target frame.
- **Opacity** (`PortraitOpacity`, and `BlockOpacity` for the block) rides
  the container, so icon, ring, rim, count, and timer fade together and the
  expiry pulse keeps working on top of it.
- Each icon: the aura's texture, a **radial duration** drawn by a
  `CooldownFrameTemplate` — `SweepStyle` = `RING` (our generated donut
  swipe texture: a true progress ring that never covers the face) or
  `WEDGE` (the classic dark sweep) — plus stack count, optional remaining
  text, and an expiry pulse under `PulseUnder` seconds.
- The rim is colored by what won: debuff school, or the rule's own color
  override, so the sentinel says *category* before you read the icon.
- `MinScore` gates the display: nothing scoring under it is interesting
  enough to occupy your portrait. That single number is how a user tunes
  "quiet" vs "chatty" without touching a rule.
- Momentum also draws on the portrait; the sentinel's anchor/offset exists
  partly so the two can coexist, and the option tooltip says which.

## Feature 3 — The priority engine

Pure Lua, zero frames, zero `Unit*` calls: the UI hands it plain aura
tables, it hands back a ranked list. Everything worth testing lives here.

### The rule model

Rules are an **ordered list**. For each aura, the first rule whose matcher
accepts it claims that aura and assigns its base score; later rules never
see it. That makes the list read top-to-bottom like a policy, which is what
makes the editor teachable.

```lua
{
  id = 7, name = "Crowd control on me", enabled = true,
  action = "SHOW" | "HIDE",           -- HIDE claims and drops the aura
  match = {
    auraType = "ANY" | "BUFF" | "DEBUFF",
    source   = "ANY" | "MINE" | "OTHER",
    spellIds = { 118, 12824, ... },    -- exact ids, any rank
    namePart = "sunder",               -- case-insensitive substring
    dispel   = { Magic = true, ... },  -- nil = any; NONE matches undispellable
    minStacks = 3,
    minDuration = 0, maxDuration = 600,-- the aura's FULL duration, seconds
    bossOnly = false, stealableOnly = false, permanentOnly = false,
  },
  score = 90,                          -- base priority
  expiringUnder = 5, expiringBonus = 40, -- urgency ramp
  stackBonus = 2,                      -- per application
  color = nil,                         -- rim override (Console palette key)
}
```

Final score = `score` + (remaining ≤ `expiringUnder` and `expiringBonus`)
+ `stacks * stackBonus`. Ties break on *least time remaining*, then on rule
order — so two equally-important auras resolve to the one about to matter.

Auras no rule claims fall to `FallbackMode`: `IGNORE` (default),
`DEBUFFS` (score them 10), or `ALL` (score them 5). A user who wants "just
never miss a debuff" gets it with one dropdown and no rules at all.

### The shipped ruleset

Nine rules, ordered, each one a demonstration of a different matcher so the
default list doubles as documentation:

1. **Silence & incapacitate** (`DEBUFF`, curated CC spell ids) — 100
2. **Boss debuffs** (`bossOnly`) — 95
3. **My defensive cooldowns** (per-class ids: Ice Block, Divine Shield,
   Cloak of Shadows, Shield Wall, Barkskin, Evasion, Grounding …) — 92
4. **Dispellable on me** (`DEBUFF`, `dispel` any of the four schools) — 80
5. **Any other debuff** — 60
6. **Hide raid buffs** (`BUFF`, `minDuration = 600`) → `HIDE`
7. **Hide auras with no duration** (`permanentOnly`) → `HIDE`
8. **My short buffs** (`BUFF`, `MINE`, `maxDuration = 60`) — 45
9. **Everything else that is a buff** — 20

Rules live in `CommanderBuffsDB.Rules`, deliberately **outside**
`DefaultSettings` (the Orders rally-point / Quartermaster watchlist
precedent) so Restore Defaults can never destroy hand-authored rules. The
editor has its own explicit "Restore Default Rules" button.

## Feature 4 — The rule editor

A dedicated window (`/cbuffs`), not a settings page. Three columns:

- **Left — the rule list.** Ordered rows: enable box, action chip
  (SHOW green / HIDE grey), name, score, and ▲▼ reorder. Selection drives
  the inspector. Buttons: New, Duplicate, Delete, Restore Defaults.
- **Center — the inspector.** Every field of the selected rule, grouped:
  Identity (name, enabled, action), Match (type, source, spell ids, name
  contains, dispel schools, stacks, duration window, boss/stealable/
  permanent), Priority (score, expiring bonus + window, per-stack bonus,
  rim color).
- **Right — the live trace.** *This is the part no generic options UI
  gives you.* A mock portrait rendering exactly what the sentinel shows
  right now, above a live-updating table of your actual aura stack: icon,
  name, the rule that claimed it, the computed score, and remaining time,
  sorted by score. Editing a rule repaints the trace instantly, so you can
  see the effect of a change on your real auras before you leave the
  window. A **Capture** button turns any row of that table into a new
  spell-id rule, so building a rule never requires knowing an id.

The window follows the Quartermaster/Talents chassis:
`BasicFrameTemplateWithInset`, the WINDOW/DARK/CLASSIC framing toggle, a
drag strip, screen-space saved position, and a scale slider.

## Settings page

Master `EnableBuffs` first (the suite's master-first rule), chrome last.
Sections: Block (enable, hide defaults, hide temp enchants, buffs-on-top
mode, icons per row, buff/debuff size, spacing, direction, timers, sweep,
mine-rim, right-click cancel), Portrait (enable, slots, size, anchor,
offsets, sweep style, stacks, timer, pulse, min score), and an Open Editor
button. Page scrolls (the Reticle `MakeScrollable` instance override).

## Constraints and codebase patterns to respect

- `C_UnitAuras.GetBuffDataByIndex` / `GetDebuffDataByIndex` on this client;
  `UnitBuff`/`UnitDebuff` are CVar-gated shims and must not be used.
- Radial rings come free from `CooldownFrameTemplate` + `SetSwipeTexture`
  on a generated donut PNG (the Reticle/Momentum finding). Ship the art in
  `Textures/`; generate it, do not depend on another addon's file.
- Nothing anchors to regions of protected frames in a way that could break
  when Blizzard re-anchors them; the block hangs off `PlayerFrame` itself
  and re-applies on `EDIT_MODE_LAYOUTS_UPDATED`.
- `SetFont` with an invalid flag hard-errors — use `SetFontObject` or
  `"OUTLINE"`.
- Three-file shape (DB / Engine / UI) plus the editor, panel built at
  `PLAYER_LOGIN`, all writes through the panel's `set`, one module event.
- In-addon harnesses: an engine fixture harness and a UI smoke harness,
  both luajit, both run before any change.

## Phases

1. **Brief** (this file).
2. **Engine**: rule model, matcher, scorer, default ruleset, validation,
   engine harness.
3. **Block + sentinel**: aura scan, block render, portrait sentinel,
   default-frame hiding, buffs-on-top mirroring, generated ring art.
4. **Editor**: window, list, inspector, live trace, capture.
5. **Settings + suite wiring**: panel, pillar entry, UI harness.

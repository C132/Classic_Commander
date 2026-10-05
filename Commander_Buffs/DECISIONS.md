# Commander Buffs — decisions

**D1. Replace Blizzard's aura frames, do not move them.** The retired v1
module made `BuffFrame` draggable, and Edit Mode made that pointless. This
module draws its own block and hides the client's frames instead. Moving a
frame Edit Mode owns means fighting it on every layout update forever;
hiding it is one hook.

**D2. The block is insecure and display-only.** A frame built from a secure
template is protected: it cannot be moved, shown, or re-attributed in combat
from addon code (the PartyFrames click-cast lesson). An aura block must
re-lay-out mid-fight — auras land and drop constantly — so secure aura
buttons were never an option. The price is right-click cancel, which is a
best-effort `pcall(CancelUnitBuff, ...)` and says so in its tooltip.

**D3. Buffs On Top is MIRRORED, not duplicated.** Edit Mode already carries
this property on the target frame. Reading it (`TargetFrame.buffsOnTop`
first, the Edit Mode manager's setting lookup second, both pcall-guarded)
means one setting governs both frames. When neither source answers, the
mirror degrades to debuffs-on-top and the settings page SAYS SO under the
dropdown rather than silently lying.

**D4. Hiding the defaults is gated on drawing a replacement.** `wantHide`
is `EnableBuffs and EnableBlock and HideDefaultAuras`. No combination of
settings can leave a player with no aura display at all.

**D5. Hiding is deferred out of combat.** The Console viewport lesson: even
non-combat-looking frame work fired from a settings callback can be refused.
`ApplyDefaultFrames` sets `pendingDefaults` in combat and re-runs on
`PLAYER_REGEN_ENABLED`; the re-show hook does the same.

**D6. The rule model is an ORDERED POLICY, not a filter bag.** The first
rule whose matcher accepts an aura claims it; later rules never see it. This
is what makes the editor's list readable top-to-bottom, makes a HIDE rule a
one-line veto instead of a separate blacklist system, and makes "why did
this show?" answerable by pointing at a row.

**D7. Score is base + urgency + stacks; ties break on least time remaining.**
A portrait icon that flickers between two equally-scored auras is worse than
either, so ordering is fully deterministic (score, then remaining, then rule
index, then spell id). Urgency is what lets a fading Ice Block outrank a
fresh one without a second rule.

**D8. A duration window never matches an untimed aura.** Otherwise "hide
long buffs" (minDuration 600) would swallow every permanent aura and the
"hide auras with no timer" rule below it would be dead. Untimed auras are
reachable only through `permanentOnly`.

**D9. Rules live outside `DefaultSettings`.** Hand-authored rules are prized
state (the Orders rally-point / Quartermaster watchlist precedent), so the
settings page's Restore Defaults cannot destroy them. The editor's own
"Defaults" button is the only thing that replaces the list, and it says so
in its tooltip.

**D10. Derived lookups never live on a rule.** The rule table IS the
SavedVariables record; a spell-id set parked on `rule.match` would be
written to disk forever and re-read as data. They live in a weak-keyed side
table rebuilt by `NormalizeRule`.

**D11. Trace selection is a spell id, not an aura table.** Aura tables are
pooled and recycled on every scan; a held reference would silently start
describing a different aura a moment later.

**D12. The editor is a window, not a settings section.** An ordered policy
is only learnable if you can watch it run, so the third column is a LIVE
TRACE of the real aura stack with the claiming rule and computed score for
every aura — including the ones that were dropped, because "why is this
missing" is the more common question. Capture turns any traced aura into a
spell-id rule so writing one never requires knowing an id.

**D13. Cycle buttons instead of dropdowns in the inspector.** No global
frame names, no menu machinery, and the current value is always legible
without opening anything — which matters when sixteen controls share one
column.

**D14. Two ticks, two jobs.** The render layer re-evaluates at 10 Hz
(scores change as auras approach expiry, with no `UNIT_AURA` to announce
it) but only walks the block's countdown text — a full re-layout ten times
a second would churn a SetPoint per icon for text that changes once a
second. The editor's trace runs its own 5 Hz repaint while open.

**D15. The sentinel icon is cut into a disc, and opacity rides the
container.** A square icon inside a round timer is two objects fighting over
the same 26 pixels, so the icon wears a circular alpha mask
(`CreateMaskTexture` + `AddMaskTexture`, the Afflictions portrait pattern)
and a circular rim to match — and the rim only goes circular if the mask
actually took, so a client without mask textures keeps square icons rather
than a round rim around a square face. The block gets the same option,
defaulted OFF because the square grid is what mirrors the target frame.
Opacity is set on the block frame and the sentinel container rather than
per-region: icon, ring, rim, count, and timer fade together, and the expiry
pulse keeps setting slot alpha in the 0.45–1 range because child alpha
multiplies with the parent's.

**D16. Every sweep is reversed.** A stock cooldown swipe starts full and
unwinds, which is right for "when can I press this again" and exactly
backwards for "how long do I have left" — an expiring buff would be at its
brightest in the last second before it falls off. All three sweeps (block
icon, sentinel ring, editor preview) call `SetReverse(true)` at build time,
so the shade or ring GROWS toward expiry and "dark/full" always means "about
to drop". Guarded, like every other cooldown call here: a client without
`SetReverse` keeps the old direction instead of erroring.

**D17. The block wears Blizzard's aura language, measured not guessed.**
The first version mirrored the TARGET frame — a 21px trimmed grid with a rim
on every icon — and the result read as an addon sitting next to the unit
frame rather than as part of the client. The geometry now comes from this
client's own UI source (`Blizzard_BuffFrame/BuffFrameTemplates.xml` and
`Classic/BuffFrame.lua` on `Gethe/wow-ui-source`, branch
`classic_anniversary`): 30px icons, **untrimmed** art, `UI-Debuff-Overlays`
at 33x32 CENTERED so it overhangs, no border on buffs at all,
`NumberFontNormal` count inside the icon at (-2,2), `GameFontNormalSmall`
duration below in `NORMAL` yellow turning `HIGHLIGHT` white under
`BUFF_DURATION_WARNING_TIME`, `iconStride` 8 and `iconPadding` 5, and a cell
40 tall so the duration text has its own 10px lane. The old look survives as
the COMMANDER style, because the trimmed grid is genuinely tidier — it is
just not what "looks like WoW" means.

**D18. Loss of control is a TAXONOMY, not a spell-id bag.** The retired flat
`CC_IDS` list could say "something is on you" and nothing more, so the
sentinel showed a square of art that looked exactly like a buff. Each aura is
now filed under what it actually took from you — STUN, INCAP, FEAR, CHARM,
SILENCE, ROOT, DISARM — which is what lets the portrait print the word, tint
the ring by category, and let a rule match "only silences". The categories
are ORDERED, and that order is the severity ladder both the shipped rules and
the editor's checkbox row read. `CC_IDS` still exists for the rest of the
suite, derived from the categories so the two descriptions cannot drift.

**D19. ALERT is a third action, not a flag on SHOW.** "Never quiet this one"
had to be expressible inside the ordered policy rather than special-cased in
the render layer, or loss of control would be a hardcoded exception the
editor could not show, explain, or let you change. ALERT is SHOW that is
exempt from Minimum Score — it buys exemption from the floor, NOT the top of
the list, so a higher-scoring aura still outranks it and an earlier HIDE
still vetoes it.

**D20. Minimum Score is the PORTRAIT's dial, spent at the last moment.**
It used to be passed into `E.Evaluate`, which meant raising it also gutted
the block's Rules Applied mode and blanked rows out of the editor's trace —
the one place you go to ask why something is missing. The shared ranking is
now computed with no floor and every consumer reads it whole; only
`SentinelPasses` applies the floor. The trace tells the two kinds of missing
apart: HIDDEN was vetoed or matched nothing, BELOW FLOOR scored fine and is
merely too quiet today.

**D21. The shipped policy is score BANDS, and the upgrade respects your
edits.** ALERT 110-130 is loss of control, 90-100 is emergencies you can act
on, 20-80 is everything that belongs in the block; the floor ships at 90.
Because rules are prized state (D9), the v3 migration replaces the rule list
ONLY when it is still verbatim a set we shipped — `E.IsUntouchedRuleSet`
checks both the current and the previous default names in order. A player who
edited theirs keeps them and gets one line at login pointing at Restore
Default Rules. The retuned scalars (icon sizes, spacing, Minimum Score) move
only where the saved value is still exactly the old default.
**D22. Enlarging my own buffs grows the CELL, not just the icon.** "Draw my
buffs bigger" has an obvious cheap implementation — scale the texture inside
the existing grid slot — and it produces overlapping icons the moment the
enlargement exceeds the gap (at the shipped 30px/5px that is anything past
about 117%). Instead the row's cell is sized for the largest icon the group
can hold and every icon is anchored by its BOTTOM CENTER to the foot of its
cell: enlarged icons grow UPWARD into space that was already reserved, small
ones sit on the same baseline, and the duration texts stay on one line per
row. The cost is a wider block, which is honest and visible, rather than
icons quietly colliding. Scoped to BUFFS only, matching the gold rim: the
feature separates your upkeep from the raid's, and a debuff you applied to
yourself is not upkeep.

**D23. Right-click cancel is a secure SIBLING of the block, bound by name, and
sticky in combat.** `CancelUnitBuff` is protected in combat on this client
(ADDON_ACTION_BLOCKED, 17 times in one session through the old pcall), so a
cancel that works mid-fight has to come from secure code. The obvious shapes
were both wrong: making the icons secure would make the block protected and
unable to re-lay-out in combat (the whole reason it is insecure), and a
`SecureAuraHeader` would hand Blizzard the layout the module exists to own.
Instead each icon gets a `SecureActionButton` overlay parented to UIParent,
whose right button runs the macro `/cancelaura <name>` (a secure slash command
on this branch). The overlay is pinned to the icon's rect on SCREEN and never
anchored to the icon: the first cut used `SetAllPoints(icon)` and the client
answered with `CommanderBuffsIcon1:SetSize()` blocked in a combat relayout, and
a block that stopped drawing new auras mid-fight — the frame a secure button is
anchored to joins its protected family and is locked in combat like a parent.
So in combat both the overlay's macro and its place are frozen, and the BUFF
group is held to match: a buff keeps the cell the last free layout gave it, a
faded buff's cell goes to a new buff first (the overlay there cancels an absent
buff, a no-op, and serves the newcomer's tooltip off the icon), and the buff
grid grows only past its recorded cells. Debuffs carry no overlay and reflow
freely on their own rows, exactly as out of combat. The groups are NEVER
merged: a debuff never takes a buff's cell and a buff never lands on a debuff
row (the first combat layout did merge them, and was thrown out the day it
shipped). With debuffs on top their rows are reserved at the free layout's
count, and a debuff row past that is drawn under the buffs rather than push
them. The paint after `PLAYER_REGEN_ENABLED` lays everything out free again
and re-binds.
Cancel by NAME rather than index on purpose: an index frozen at combat start
would cancel a neighbour the moment an earlier aura fades. A test-stack aura
carries no index and is never bound, so the test stack cannot cancel a real
buff. The 10 Hz ticker watches one bound icon for drift (Edit Mode, a scale
change) and re-places the overlays out of combat.

**D24. Cancelling in combat is opt-in, because its held layout is visible.**
D23's honest combat layout holds every buff cell, leaves gaps where buffs
fade and puts newcomers where a cell is free — and the first two versions of it
were rejected on sight ("there is always something messed up when I'm in
combat", 2026-09-24). A secure cancel cannot be had without holding the cells,
and the block's own reasons for existing (policy filtering, enlargement, the
Blizzard-exact look) rule out handing the layout to a `SecureAuraHeader`. So
the choice is the player's: Right-Click to Cancel alone is exact out of combat
and leaves the block flowing freely in a fight (no secure button is ever
created), and Also In Combat, off by default, buys the mid-fight cancel at the
price D23 describes.

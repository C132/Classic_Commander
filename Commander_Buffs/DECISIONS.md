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

# Commander Buffs — in-game assumptions

Everything below is reasoned from the client's framework and the suite's
verified API notes, and is **not yet confirmed in the field**. Each one is
written so that being wrong degrades to a visible, harmless fallback rather
than an error. Test them in this order — the first four carry the feature.

**A1. `TargetFrame.buffsOnTop` is a readable boolean on this client.**
Used by the Buffs-On-Top mirror. If the field is absent the mirror falls
back to the Edit Mode manager lookup (A2), and if that fails too the
settings page reports "Target frame is not answering". *Test:* toggle Buffs
On Top on the target frame in Edit Mode and watch the note under the
dropdown flip between "buffs on top" and "buffs on bottom".

**A2. `EditModeManagerFrame:GetSettingValueBool(Enum.EditModeSystem.UnitFrame,
Enum.EditModeUnitFrameSystemIndices.Target, Enum.EditModeUnitFrameSetting.BuffsOnTop)`
answers on this client.** The fallback path for A1; entirely pcall-guarded.
*Test:* only reachable if A1's field is missing — check the note still
tracks Edit Mode.

**A3. `BuffFrame` / `DebuffFrame` can be hidden by an addon and stay
hidden.** The hide is a `Hide()` plus a `hooksecurefunc` on `Show`. If the
client re-shows them through some path we do not hook, the symptom is
duplicated auras (block + default frames), not an error. *Test:* log in
with the block on, enter and leave combat, open Edit Mode, `/reload`, and
zone — the default frames must stay down through all of it.

**A4. Hiding those frames in combat is refused, so it is deferred.** We
never call `Hide()` on them while `InCombatLockdown()`. If the deferral is
unnecessary the only cost is that a mid-combat settings change lands a few
seconds late. *Test:* toggle Hide Default Auras during a fight; the change
should land the moment combat ends, with no `ADDON_ACTION_BLOCKED`.

**A5. `CancelUnitBuff("player", index)` is protected here.** Assumed
refused, which is why right-click cancel is a silent-failing pcall and the
option tooltip says so. *Test:* right-click a cancellable buff in the block.
If it cancels, the assumption was pessimistic and the tooltip should be
softened; if nothing happens, the tooltip is already honest.

**A6. Buff and debuff indices from `C_UnitAuras.Get{Buff,Debuff}DataByIndex`
are the same indices `GameTooltip:SetUnitBuff`/`SetUnitDebuff` expect.**
Used for block tooltips. A mismatch shows the wrong tooltip, so the test
stack deliberately carries NO index (its icons fall back to a name-only
tooltip). *Test:* hover several block icons with a full stack and confirm
each tooltip matches its icon.

**A7. `data.isBossAura` is populated on this client.** The shipped "Boss
debuffs" rule depends on it; if it is always false that rule simply never
claims anything and the debuff rules below it take over. *Test:* take a boss
debuff and check the editor's trace names the boss rule as the claimant.

**A8. `data.isFromPlayerOrPlayerPet` is populated.** Drives the MINE source
matcher and the gold rim; `sourceUnit == "player"` is the fallback. *Test:*
the trace's "From me: yes/no" line on one of your own buffs.

**A9. A `Cooldown` frame with a donut swipe texture draws a ring on a 26px
icon.** Verified at reticle sizes; unverified this small. If the ring reads
as mush at 26px, raise Icon Size or switch Duration Style to Wedge. *Test:*
eyeball the sentinel with a 10-second buff.

**A9b. `CreateMaskTexture` + `Texture:AddMaskTexture` work here.** Used to
cut the sentinel icon (and optionally the block icons) into a disc. Verified
in the suite by Commander_Afflictions' round portraits, so this is the
safest of the lot; the guard means a failure keeps square icons AND a square
rim, never a round rim around a square face. *Test:* the sentinel icon
should be a circle sitting inside its ring.

**A10. Nothing else is drawing where the sentinel lands.** Commander
Momentum's streak ring uses the same portrait. The sentinel's Anchor and
offsets exist for exactly this; the default is dead center. *Test:* run both
modules and confirm they can be separated.

**A11. `PlayerPortrait` exists as a global on this client.** The sentinel
anchors to it and falls back to `PlayerFrame` if not. *Test:* the sentinel
lands on the face rather than the frame's center.

**A12. The block's anchor offsets suit the default player frame art.**
Defaults are +8, -4 below the frame; they were chosen by reading the frame's
geometry, not by measuring on screen. *Test:* look at it, then nudge Offset
X/Y.

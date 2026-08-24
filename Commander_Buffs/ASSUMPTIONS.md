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
X/Y. NOTE: icons went 21 -> 30 with the Blizzard style, so a row is now 280px
wide rather than 192 — this is the assumption most likely to need a nudge.

**A13. The Blizzard block style renders identically to the client's own aura
frames.** The path, size and texcoords all came out of this client's
`Blizzard_BuffFrame` source rather than measurement, so the individual
numbers are not in doubt — what is untested is the WHOLE thing side by side.
A missing texture draws nothing, so the worst failure mode is borderless
debuffs, not an error. *Test:* turn Hide Default Auras off for a moment so
both are on screen at once, and compare a debuff in each: border shape,
overhang, icon crop, count position, timer color. Anything that differs is a
constant to re-read from the source, not to eyeball.

**A14. `NORMAL_FONT_COLOR` / `HIGHLIGHT_FONT_COLOR` exist as tables with
`.r`.** Used for Blizzard's yellow-until-90s duration text. Guarded: a client
without them gets plain white timers. *Test:* a long buff's timer should be
yellow and turn white as it drops under 90 seconds.

(Not an assumption, recorded so nobody re-derives it: `SecondsToTimeAbbrev`
was read from this client's `Blizzard_SharedXML/TimeUtil.lua` and does return
a plural-aware FORMAT plus its value, which is why the duration text goes
through `SetFormattedText` and not `string.format`.)

**A15. The loss-of-control spell ids are the ones this client actually
applies.** The categories were built from TBC base ids; every rank shares its
base id in aura data, so ranks are covered, but an id that is simply wrong
means that aura silently never counts as control. The failure mode is a
missing alert, not an error — which is the dangerous kind. *Test:* the
editor's live trace now prints the category for every aura, so get hit with
one of each (a stun, a fear, a silence, a root) in a battleground and confirm
the trace names it. Anything unlabeled is a missing id.

**A16. `GameFontNormalSmall` is legible as the sentinel's category label at
its default 26px icon size.** The word sits ABOVE the icon and is wider than
it — "DISARMED" at this font is roughly 55px against a 26px icon, so it
overhangs on both sides by design. *Test:* trigger the test stack (`/cbuffs
test`, which now seeds a Kidney Shot) and look at the portrait. If the word
collides with anything, the Sentinel X/Y nudges or a smaller Icon Size are
the dials; if it is unreadable, the label wants an OUTLINE font object.

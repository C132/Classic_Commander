# Commander Tracer — assumptions

Things this module believes about the client that have NOT been verified in
the field as of 2026-09-26. Each says what breaks if it is wrong and how to
tell.

**A1. The `floatingCombatText*_v2` CVars are the engine's world numbers.**
`floatingCombatTextCombatDamage_v2`, `...CombatHealing_v2`,
`...CombatLogPeriodicSpells_v2`, `...PetMeleeDamage_v2` and
`...PetSpellDamage_v2` are present in the 2.5.6 binary by `strings`, and the
`_v2` spelling is the one the classic_anniversary UI source reads; the
belief is that setting them to 0 removes the damage and healing numbers the
engine draws over units in the 3D world (Options > Combat > "Show Damage").
If wrong: Blizzard's numbers keep drawing over targets beside this module's.
Tell by: hitting a dummy with Hide Blizzard's World Numbers ticked.

**A2. `enableFloatingCombatText` = 0 silences Blizzard_CombatText.**
The LoadOnDemand addon registers a settings callback on that CVar and calls
`CombatTextUtil.UpdateEventRegistration`, so the scrolling text round the
character should stop the moment the CVar is written, without a reload.
If wrong: both texts draw round the character. Tell by: any hit with Hide
Blizzard's Player Text ticked.

**A3. `C_CombatText.GetCurrentEventInfo()` returns `(data, arg3, arg4)`.**
Read from `CombatText.lua` on classic_anniversary; the runtime also accepts
`(messageType, data, ...)` (shifts past a first value equal to the type) and
falls back to the event's own varargs. Used for SPELL_ACTIVE (the reactive
name) and HONOR_GAINED (the amount) only. If wrong: procs and honor never
draw, nothing else is affected. Tell by: an Overpower proc with the
Callouts lane on.

**A4. `SPELL_ENERGIZE` is `(amount, overEnergize, powerType)` on 2.5.6.**
The engine takes powerType from a17 when a17 is a number, else from a16
(the older two-value layout). If both wrong: power gains are drawn with the
wrong power name and colour. Tell by: a Judgement of Wisdom proc reading
"Mana".

**A5. `PARTY_KILL` fires for the player's own killing blows on this client**
with sourceGUID = the player. If wrong: no Killing Blow callouts (Commander
Impact, which reads the same event, would be blind too).

**A6. A frame's anchor offsets are in its own scaled space.** `Place`
divides x, y by the crit scale before `SetPoint` so a 1.5x crit sits where
a plain hit would. If the client scales offsets differently, crits drift
away from the lane by half their offset. Tell by: a fountain lane's crits
landing further out than its hits.

**A7. Setting these CVars is not combat-protected.** The runtime defers them
to PLAYER_REGEN_ENABLED anyway (the nameplate CVars are protected, so the
same discipline costs nothing). If they ARE protected and a write is
attempted in combat, `pcall` eats the error and the deferral catches it.

**A8. `GetSpellTexture(spellId)` answers for every id the combat log
names**, including ranks of spells the player does not know. A nil answer
just draws no icon.

**A9. `COMBAT_TEXT_UPDATE` fires for addons whatever `enableFloatingCombatText`
says.** The CVar gates Blizzard_CombatText's own registration, not the
event; this module registers the event on its own frame. If the engine
gates the event by the CVar, procs and honor stop drawing while Hide
Blizzard's Player Text is ticked. Tell by: an Overpower proc with that box
on and the Callouts lane on. If it is gated, the fix is to leave that CVar
on and hide `CombatText` (the addon's frame) instead.

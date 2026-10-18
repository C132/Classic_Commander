# Commander_Advisor — assumptions

Things the module relies on that have not been verified in a live client.
Each has a guard so a wrong assumption degrades, not errors. Strike them
through as they are confirmed.

- **`CreateAnimation("FlipBook")` with `SetTarget`, `SetFlipBookRows/Columns/Frames`
  exists in Lua on 2.5.x.** The XML template `ActionButtonSpellAlertTemplate` uses
  `<FlipBook>`, so the animation type exists; the Lua spellings are the modern
  ones. Guard: every call is pcall-wrapped in `MakeFlipbook`; on failure the
  holder has no `loop` and the border art is used for every tier.
- **The atlases `UI-HUD-ActionBar-Proc-Loop-Flipbook` / `-Start-Flipbook` are in
  the client's atlas table.** Checked with `C_Texture.GetAtlasInfo` before use;
  absent means the border style.
- **`C_LossOfControl.GetActiveLossOfControlData(i)` returns a table with
  `locType`** (the modern struct). An older tuple form is handled by taking the
  first return as the type. Absent API: no control state, so the trinket rule
  and the held/silenced suppression never fire.
- **`GetShapeshiftFormInfo` returns `icon, active, castable, spellID`** on this
  client. The older `icon, name, ...` shape is detected by the second return
  being a string.
- **`unit .. "target"` resolves for `nameplateN` tokens** so a hostile cast aimed
  at you can be recognised. If it does not, `incomingCasts` stays empty and the
  Fear Ward / Grounding / Spell Reflection / Kick rungs that need it are quiet.
- **`UnitCastingInfo` is the 9-return modern shape (spellId last) and
  `UnitChannelInfo` the 8-return one.**
- **`IsUsableSpell` is the global on this client** (with `C_Spell.IsSpellUsable`
  as the fallback). If both are absent every spell reads usable.
- **`GetSpellCooldown(spellID)` reports the longer of the global and the real
  cooldown** (per the API notes); a duration of 1.5s or less is treated as the
  global and therefore "ready".
- **`GetSpellBookItemName(i, "spell")` third return is the spellID** (per the
  API notes on rank text). Without it the book maps names to `true` and every
  cooldown read goes by name.
- **Item cooldowns via `C_Item.GetItemCooldown`, else `C_Container.`, else the
  global.** All pcall'd; a miss reads as ready.
- **`SWING_DAMAGE` carries the amount at arg12 and school at arg14;
  `SPELL_DAMAGE` the school at arg14 and amount at arg15;
  `ENVIRONMENTAL_DAMAGE` the amount at arg13.**
- **Hanging an insecure child frame on a Blizzard action button and drawing on
  it does not taint the button** — the same pattern Commander_Forecast ships.

## 1.3.0 (2026-10-16) — teammates, overlays, bounce range. Unverified in game.

- **`SecureCmdOptionParse(options)` is callable from addon code and returns
  `action, target`** for a macro line's conditional text, as on retail. If it
  is missing or errors (pcall'd), a macro button answers for your friendly
  target or you, like a plain button.
- **`GetMacroBody(id)` returns the macro text** so the overlay can find the
  line that casts the spell. Absent: the same fallback.
- **`IsSpellInRange(name, unit)` answers 1/0/nil for party members in combat.**
  Used for "can my shield reach them" (40 yd) and the reach bounds (30/40 yd).
  `CheckInteractDistance` is protected on this client and `IsItemInRange` is
  refused on friendlies in combat (TBC API notes), so these are the only
  bounds there are.
- **`UnitPosition(partyN)` in an arena is UNTESTED.** It answers in the open
  world and in battlegrounds for group members; arenas have no UiMap and may
  blank it. If it is blank there, the Mending rim in arena is red only when
  Mending is on you and everyone is beyond thirty yards, and otherwise shows
  nothing. `/cadv range` in a skirmish answers this.
- **Mending can jump to any group member, not only your subgroup**, in a raid
  (battleground). The reach estimate counts the whole raid; the Shield pips
  and the ally rule use your subgroup (at most five seats).
- **Party members' `UnitHealth` is the real value**, so a teammate's
  time-to-die is in seconds like yours.
- **`UNIT_AURA` fires for a party member's token (and for `target` when it is
  them) when their auras change.** The overlays cache aura reads per GUID and
  re-read on that event, or after a second at most.

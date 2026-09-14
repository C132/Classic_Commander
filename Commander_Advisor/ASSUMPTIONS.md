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

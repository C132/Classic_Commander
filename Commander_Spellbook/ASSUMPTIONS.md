# Commander_Spellbook — assumptions

What the module relies on that has NOT been seen in game yet, numbered for citation. 1.0.0 was built
and harness-tested on 2026-10-26 against the `classic_anniversary` UI source and the suite's mocks;
nothing here has been field-verified. When one is confirmed or broken in game, say so here.

- **A1 — `PickupSpell(id)` is not protected, in or out of combat.** Dragging a row, a rank chip or
  the big icon calls it from insecure code. Blizzard's own classic book calls `PickupSpell` from
  `CoreAbilitySpellMixin:OnDragStart` and `PickupSpellBookItem` from its spell buttons, but those are
  Blizzard's code; no installed addon calls either. If it throws ADDON_ACTION_BLOCKED in combat, the
  drag handlers must check `InCombatLockdown()` and say "drag from the book after combat".
- **A2 — `PickupSpell(id)` picks up a lower rank the book is not listing** (Show all spell ranks
  unticked), because the rank is still known (`IsPlayerSpell`). Down-ranking from the ladder depends
  on it.
- **A3 — `PlaceAction(slot)` is callable by an addon out of combat** and swaps cursor and slot.
  Rank Check's Update depends on it (ActionBarProfiles-style addons do this on classic clients).
  The guard rails in D9 hold whatever happens: the slot is re-read, the cursor must be empty before
  and hold a spell after the pickup.
- **A4 — `EditMacro(index, nil, nil, body)` keeps the macro's name and icon** out of combat. Not a
  guess any more: it is exactly how Blizzard's own macro window saves (`MacroFrameMixin:SaveMacro`,
  Blizzard_MacroUI.lua, classic_anniversary). Still unseen in game: a Blizzard macro window left open
  re-saves its own copy of the text when it closes, which would undo an Update made underneath it.
- **A5 — A `type = "spell"` secure button casts a lower rank by id** (`CastSpellByID`, the
  SecureTemplates path) and a pet ability by name (`CastSpellByName("Firebolt")`). Pet COMMANDS are
  recognised by name against `PET_ACTION_*` / `PET_MODE_*` and get no cast button (D8); if the pet
  book on this client lists no commands, that guard simply never fires.
- **A6 — `GetBindingKey("TOGGLESPELLBOOK")` returns the player's own bindings, not the override
  ones this module sets.** If it returned ours, ApplyBindings would still be stable (same keys) but
  turning the takeover off would clear them correctly only because ClearOverrideBindings runs first.
- **A7 — Hiding the stock book with `HideUIPanel` from its own OnShow hook, out of combat, leaves no
  taint that matters** — the Quest Log does exactly this to QuestLogFrame and has been in use since
  2026-09; the spellbook differs in having secure children, which is why it is never done in combat.
- **A8 — `IsPassiveSpell(slot, "spell")`, `GetSpellTexture(slot, "spell")`, `GetSpellBookItemInfo`
  and `GetSpellAutocast(slot, "pet")` keep their legacy two-argument forms on 2.5.6** (Blizzard's
  `Vanilla/SpellBookFrame.lua`, loaded for TBC, calls every one of them that way).
- **A9 — Trainer prices in the CMaNGOS world DB are the Anniversary prices** before reputation
  discounts. The generator's cross-check against WhatsTraining lists every disagreement.
- **A10 — `C_SpellBook.IsSpellKnown(id)` answers for a lower rank the book is not listing**, as the
  deprecated IsPlayerSpell it wraps did (D11). If it turned out to answer only for listed spells, the
  ladder would show lower ranks as unknown with Show all spell ranks unticked.
- **A11 — Hiding the stock book from its OnShow hook taints nothing that matters later.** The review
  (2026-10-26) noted the Quest Log's identical pattern is weak evidence, because QuestLogFrame is not
  protected and SpellBookFrame is. If a micro-button open of the stock book in combat ever raises
  ADDON_ACTION_BLOCKED naming this addon, `/console taintLog 1` will say whether this hook is why;
  the fallback is to leave the OnShow door off and keep only the override keys.


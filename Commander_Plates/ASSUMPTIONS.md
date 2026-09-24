# Commander Plates — what only the game can confirm

Everything below is covered by the harnesses as far as a widget mock can go
(see `Harness/README.md`); these are the claims the mock cannot make, written
down so a first session in game knows what to look at.

## The radial plate (1.2.0, 2026-09-23 — none verified in game yet)

- **A1. A frozen Cooldown draws a static arc.** Health and mana are Cooldown
  frames started in the past (`SetCooldown(now - f * span, span)`, reverse on)
  with a donut swipe texture — the same technique Commander Casting's rings
  and Reticle use for LIVE sweeps, but never before for a still one. Look for:
  a health ring that sits at the unit's health and does not creep. If it
  creeps, the fix is shortening `DRIFT`; if it does not draw at all, a long
  duration is being refused and `STATIC` should come down.
- **A2. A 100% arc is the plain texture.** A cooldown at its end hides itself,
  so a full ring is drawn by `arc.full`. Full-health plates should show a
  complete ring with no seam at twelve o'clock.
- **A3. Alpha 0 hides Blizzard's plate for good.** `HealthBarsContainer`,
  `name`, `CastBarsContainer`, `LevelFrame`, `RaidTargetFrame`,
  `ClassificationFrame`. The twice-a-second tick re-hides the health
  container if Blizzard resets it; nothing re-hides the others. Look for a
  bar or name peeking out behind a disc, especially after targeting.
- **A4. The disc's hit box.** Points relative to the health bar's CENTER. The
  mouse should select a disc anywhere on it and on its name, and nowhere
  else.
- **A5. Stacking.** The client stacks plates by the PLATE's size, which is
  still the bar's. Discs are taller than bars, so crowded plates may overlap
  vertically. `Stack Plates By The Disc` (off by default) calls
  `C_NamePlate.SetNamePlateEnemySize/FriendlySize` out of combat and hands
  back via `NamePlateDriverFrame:UpdateNamePlateOptions()`, re-asserting
  after Blizzard's own pass. Unverified: that both exist on this client, that
  insecure code may call them out of combat, and that existing plates pick
  the size up (they may only on re-show).
- **A6. `UnitGetIncomingHeals` and `UNIT_HEAL_PREDICTION`.** Guarded; if the
  client lacks them the heal arc simply never appears.
- **A7. `UNIT_SPELLCAST_INTERRUPTED` for nameplate tokens.** The interrupt
  flash hangs off it. Note it also fires for a cast the caster cancelled by
  moving — which is still, from the plate's point of view, a cast that did
  not land.
- **A8. `SetPortraitTexture` into a masked texture** on a nameplate token
  (Afflictions does it for group tokens). Portraits should be round.
- **A10. `<nameplateN>target` resolves** for the cast line's "who is this
  aimed at". It is the unit's CURRENT target, which for most casts is the
  cast's target; a caster who swaps target mid-cast moves the name with them.
- **A11. The trinket badge** reads `C_PvP.GetArenaCrowdControlInfo("arenaN")`
  exactly as Commander Arena Frames does (see the suite's arena notes); it
  only appears on a disc once the plate is matched to an arena seat.
- **A12. `UNIT_TARGET` fires for nameplate tokens**, driving the
  targets-you ring. The twice-a-second tick re-checks regardless.
- **A13. The control countdown on the face is a MASKED clock wipe**, not a
  Cooldown (a Cooldown's swipe cannot be masked, and was drawing past the
  face onto the rings). Two `HalfRight.png` textures, each clipped by a
  half-disc mask and turned with `SetRotation` (E.WipeAngles). Relies on a
  mask clipping a ROTATED texture, and on rotation turning the picture about
  the quad's centre. Look for: a dark wedge that grows clockwise from twelve
  and never leaves the round icon. Without masks it falls back to the
  Cooldown, drawn beneath every ring.
- **A9. `Texture:SetRotation`** for the markers and the cast spark (Casting
  relies on it on this client).

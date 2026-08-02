# Commander Threat — Findings

## The lineage, and what was taken from each generation

**KLHThreatMeter (vanilla).** Re-implemented the threat table by parsing the
combat log, then synced every raider's estimate over an addon channel —
correctness depended on everyone running the same version and the sync
staying alive. Patch 2.4 made the whole architecture a fossil by giving the
client a real threat API. Taken: one lesson, engraved on the engine header —
*never calculate what the client will tell you.* Commander Threat contains
zero threat simulation; every number is read from
`UnitDetailedThreatSituation`.

**Omen3 (2.4+).** The gold standard and this addon's primary reference.
Taken: the group threat list on the current target; the target-of-target
fallback (a healer targeting the tank reads the tank's target's list — this
is load-bearing and preserved verbatim); TPS; the aggro warning flash+sound
that saved more wipes than any other addon feature of its era; and
"always show self" (the player's row pinned into the last visible slot).
Dropped: the per-mob tab strip, the AceConfig options sprawl, and the
relative-to-top bar scaling — see DECISIONS D2 for why scaled percentage is
strictly more honest.

**TinyThreat (Details! plugin).** Proof that most players need one compact
percentage list. Taken: restraint — the board is one fixed-geometry panel,
not a window manager.

## What is new here

**Role adaptation.** Every prior threat meter showed everyone the same list,
but tanks, damage, and healers manage *opposite sides* of threat. The role
dropdown (per character; panel + board header tag + slash) reshapes the
headline, footer, warnings, and status colors around the selected role.

**Nameplate facts.** `C_NamePlate.GetNamePlates()` / `namePlateUnitToken`
is field-proved on this client by Commander_Radar and Commander_Shield's
targeter counter, which makes two things possible that Omen's era could not
do: the tank's HELD n/m · LOOSE n footer (a loose mob eating a healer is
the tank failure the target-based list can't show) and the healer's
worst-mob sweep + INBOUND alert (heal aggro is diffuse; the current target
means little to a healer).

## Suite inventory consumed (nothing re-implemented)

- `Commander.UI.NewPanel` + widget builders, `MakeScrollable` instance
  override (Reticle/Quartermaster/Meters pattern) for the over-tall page.
- `Commander.UI.HudChromeDefaults/ApplyHudChrome/AddHudChromeOptions`
  (prefix "Hud"), chrome options last on the panel.
- `Commander.GetClassInfo` for class colors (bars) — pets deliberately
  render neutral (D11).
- `CommanderConsole_Colors` via the TopBar/Meters soft-fail pattern for the
  Accent Color dropdown (bake-at-login, orphan-key option, parenthetical
  strip).
- The Impact vignette language (LowHealth ADD-blend pulse on a Frame
  driver) for the screen flash — the art is itself red, which is exactly
  the color threat danger wants.
- The Meters RTS visual contract (ARIALN, fixed geometry, class colors as
  data, one accent) and its in-addon harness pattern.

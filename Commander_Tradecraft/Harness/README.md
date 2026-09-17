# Commander_Tradecraft harnesses

Three luajit checks, all in-addon. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit tradecraft_engine_smoke.lua   # data + engine — 752 checks
/opt/homebrew/bin/luajit tradecraft_ui_harness.lua     # UI + host    — 97 checks
/opt/homebrew/bin/luajit globals_lint.lua              # 4 files, 0 undeclared globals
```

All three resolve the AddOns root from their own file location, so they work in a git worktree as
well as in the live AddOns directory. Each is silent on success and exits non-zero on the first
failure it finds.

---

## `tradecraft_engine_smoke.lua` — the data and the engine

No mock at all. The data and engine files are pure Lua, so this loads both and pushes fixed
characters through `Build`. A failure here is a real logic or data bug, never a mock artefact.

- **A1–A4** are data integrity: every step's recipe, reagent, formula and vendor exists; craft steps
  are contiguous and reach the segment end; no step runs into grey; every formula has a vendor each
  faction can use; the trainer ladder rises and Master is at 275.
- **B1–B4** are the skill-up model against the guide's own counts: exact on all-orange steps, within
  twenty percent everywhere, and the margin lands on the uncertain part only (B3b: one rod is one rod).
- **C1–C14** are characters. A fresh enchanter; the trainer banner at 50, at the cap, with no
  profession, at 275; a Horde enchanter at 146 with the cloak formula never bought (behind them, so
  done); the buy step at 110 through holding and learning the formula; the alternatives; skipping;
  **C7** the Moonglade case (the Arcanite formula at 299 is still wanted); **C10** the Superior
  Defense formula still wanted at 300 for the 301–317 step; the bank option; finished; the shopping
  list against the guide's own list within fifteen percent.

## `tradecraft_ui_harness.lua` — the UI and the host

Loads the **real** shared framework (`CommanderSettingsUI.lua`, `CommanderEvents.lua`) plus all four
addon files under the suite's permissive widget mock, extended with a skill list (header first, the
way the client shows it), a craft window with a list to scan and a `DoCraft` that raises the
targeting cursor for enchants, equipped slots and bags, the replace-enchant popup, TomTom and
Auctionator stubs, and a combat flag.

It drives login on a fixtured Horde enchanter at 146 with a saved path choice; the craft window
opening (scan, auto-open, Craft enabled); the Craft button through `DoCraft`, the bracers, the bag
bracers, the no-target refusal and the replace answer including its three-second rule; a skill-up
with its chat line and sound; the alternatives from the slash command and the button; the buy step
with faction-filtered vendors, price, zone and the TomTom waypoint; skip and un-skip; reset; the
trainer banner capped and uncapped and the Master trainers by faction; the ledger in both modes and
the Auctionator hand-off; disable/enable; the combat rule on the secure button; finished; Restore
Defaults; status.

Checks worth naming:

- **B2** — the popup answered after our cast, and left alone five seconds later.
- **C1** — "Alternative" applies to the *coming* segment when the current one has no choice.
- **F2** — in combat the Open button is neither offered nor touched; after combat it is back.
- **F4** — Restore Defaults leaves the character's choices alone.
- **Z** — the skill headers were expanded exactly once, for the no-profession case, never while the
  line was there.

## `globals_lint.lua` — scoping

luajit's bytecode listing names every global a file touches; the check subtracts the ones we mean to
touch and reports the rest. It caught `InCombat` being defined after its first use on the first run.
Add a genuinely new WoW API to `ALLOWED` with a comment saying where it is called from; never add a
name just to make the lint quiet.

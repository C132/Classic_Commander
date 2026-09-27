# Commander Tracer — harness

Four checks. Nothing here runs in the game; everything here runs without it,
which is the point.

```
luajit  Harness/tracer_engine_smoke.lua     the rules (numbers, colours, classification, routing, text, motion)
luajit  Harness/tracer_ui_smoke.lua         the runtime over a widget mock + the REAL settings framework
python3 Harness/order_lint.py               use-before-declaration
python3 Harness/settings_reach.py           every setting has a control, every control writes a setting, every setting is obeyed
```

## What the engine smoke asserts

Decisions a player would make by hand, as claims that survive an edit:

* **the combat log's 2.5.x field layout is decoded right.** A spell prefix is
  (id, name, school) at a12..a14 with the suffix from a15; a swing has no
  prefix; environmental damage carries its type at a12. Damage, misses,
  heals, energize (both the three-number and two-number layouts), absorbs
  (both layouts, told apart by a12's type), interrupts, dispels and steals,
  PARTY_KILL, auras applied and removed. Every one from you, from your pet
  (by GUID or by the MINE + PET/GUARDIAN flags), at you, and between two
  strangers (nil).
* **self-damage is damage taken; a self-heal is a heal of yours.**
* **routing means what the page says.** A lane or Off; the ledger flag on
  top; the flag redundant when the lane IS the ledger.
* **every format, crit mark, partial and count writes the string it
  promises**, and the moments have their own grammar (Killing Blow: name,
  Interrupted X, Stole X, X ready, +15 Honor, + Buff / - Buff).
* **the flat palette resolves the module's own keys and Console's**, and a
  missing key is white rather than an error.
* **spawn:** the stagger window, the scatter, the fountain's alternating
  sides, MaxLines trimming the oldest, the merge window summing, counting,
  marking a crit, punching, and restarting a stack row's linger.
* **motion:** scroll at the speed set, both directions; the fountain rises
  then falls while still travelling outward; a pop punches in and settles,
  newer pops stacking below or above; a stack slides in, shoves older rows
  one slot along (lerped, not teleported, and clamped through a hitch),
  grows in either direction, and expires; fade in, fade out, a crit's punch
  and settle, the merge punch.
* **the test volley** is in time order, every shot is a known kind with
  text and a colour, and under the default routing it reaches every lane
  and shows every kind it claims to.

## What the UI smoke asserts

The half the engine cannot reach. The mock is the Plates board recorder set
(fonts, colours, points, scale, strata, alpha and visibility are all
RECORDED, not swallowed), and it enforces the client's one FontString rule
that bit the first in-game load: `SetText` on a string with no font object
and no `SetFont` yet is an error ("Font not set"), so writing text before
setting the face fails here rather than 79 times on the settings page plus the real `CommanderSettingsUI.lua` and
`CommanderEvents.lua`, so the page is built the way the client builds it.

* login applies 255 defaults, builds six named roots on the strata set,
  and takes Blizzard's seven CVars while remembering each one's old value
  (including one that was already off, so restore is exact);
* a Fireball in the log becomes a number in Outgoing dressed with its icon,
  school colour, face, size, outline and shadow, and a ledger row with a
  backdrop, an accent in the entry's colour and the full sentence;
* the number rises, fades, expires, and its frame goes back to the pool;
  the ledger row holds its six seconds;
* the ledger merges a repeat into one row with a sum and a count, punches
  the accent, and shoves the older row down a slot;
* incoming damage falls on the left with its spell and its icon on the
  right; a dodge is a grey word without an icon; heals and mana land in
  Incoming Heals in their colours;
* crits are marked, scaled and punched; anchor offsets are divided by the
  scale; the mark and the punch follow their settings; the big-hit
  threshold promotes a non-crit;
* sounds: silent by default, the kill bell when picked, never twice inside
  the gap, the crit chime only past its threshold and never for a big hit,
  auditioning from the page regardless;
* the client's own feed: SPELL_ACTIVE becomes a callout and a row with the
  proc chime, read correctly whether or not the feed repeats the type
  first; HONOR_GAINED becomes a row; the feed's DAMAGE is ignored;
* routing: Off, ledger-only, any lane, a disabled lane's root hides and
  draws nothing, hide-below drops a tick but keeps a miss, the pet's Claw
  is tagged and untagged, the number style flows through, another module's
  post draws and an unknown kind is refused;
* off: every root hides, every CVar is given back exactly and the backup
  empties; on: taken and remembered again; the boxes one at a time; a
  write in combat waits for REGEN; combat state rows when asked;
* the volley reaches every lane, Clear empties them, an unlocked lane wears
  its name, the draw layer follows the setting, a fountain lane throws;
* the page registers as a module with its slash command, every one of its
  hundred-odd dropdowns has entries with a face and a value and shows its
  current value after a refresh, the page folds and gets a search box, the
  previews take the lane's face and follow a change, `/ctracer unlock |
  lock | report | reset` work, and reset keeps the CVar backup.

## The settings-reach check

This module stores most of its settings by PATTERN — `<lane><Key>` for the
six lanes, `<kind>Lane` / `<kind>Ledger` for the twenty-two kinds, one key
per sound slot — so `settings_reach.py` expands the patterns (from
`DATA.LANES`, `DATA.LANE_DEFAULTS`, `DATA.KINDS`, `DATA.SOUND_SLOTS`) rather
than reading only literal keys, on all three sides: declared, obeyed (the
runtime's `G("Key")` / `L(P, "Key")` / `cfg.Key`, the engine's
`db[rec.kind .. "Lane"]`), and reachable (the page's
`CommanderTracerDB[P .. "Key"]` / `[kind.key .. "Lane"]` / `[slot.key]`, and
the chrome keys `AddHudChromeOptions` gives every lane). It reports
UNREACHABLE, DEAD and UNREAD. 255 settings, all three ways.

# Commander Plates — harness

Five checks and one generator. (`CommanderPlatesDraw.lua` holds the ring, halo and colour-key brushes shared by the plates and the settings-page preview, so the preview cannot drift from the plate.) Nothing here runs in the game; everything here
runs without it, which is the point.

```
luajit  Harness/plates_engine_smoke.lua       the rules (1312 checks)
luajit  Harness/plates_board_smoke.lua        the runtime over a widget mock (401 checks)
python3 Harness/order_lint.py                 use-before-declaration
python3 Harness/settings_reach.py             every setting has a control
python3 Harness/make_cc_table.py              regenerate the CC block (after a patch)
python3 Harness/make_wipe.py                  regenerate the clock-wipe half discs
python3 Harness/make_glows.py                 regenerate the ten target-glow styles (asserts no alpha on any edge)
```

## Where the crowd-control table comes from

`CommanderPlatesData.lua` carries a generated block — `CC_BY_SPELL`, 884
spells across sixteen DR groups — and **this module does not own the
generator**. Commander Arena Frames' `make_dr_table.py` transcribes the
server's own DR classifier over the client's spell tables; Commander Diminish
carries a copy; `make_cc_table.py` copies Diminish's into this file. Three
addons, three copies, one generator, so each keeps working with the others
disabled — and section A of the engine smoke diffs this copy against
Diminish's, id by id, so a regenerated table pasted into one file and not the
other is a red test rather than a Polymorph the big icon quietly stops
recognising.

Everything that is NOT diminishing returns — immunities, offensive and
defensive cooldowns, Mortal Strike, silences (which have no DR in TBC), the
totem list, the healer spells, the cast-emphasis list — is hand-written by
aura NAME in the same file. Section H of the engine smoke checks every one of
those names against the client's own `SpellName` table (from Commander
Quartermaster's `.cache`) and every totem's rank-1 spell id against its name,
so a typo is a failure rather than an aura that is never recognised.

## What the engine smoke asserts

Decisions a PvP player would make by hand, as claims that survive a
regeneration:

* **the big slot ranks by category, then by what ends later.** A stun beats a
  root even when the root outlasts it; between two stuns, the one you will
  still be sitting in when the other drops wins; silence beats root; an
  immunity takes the slot only when no control is up, and only while the
  immunity toggle is on.
* **the filters mean what the dropdowns say.** Mine / mine + notable /
  everything on enemies; dispellable-by-me / + notable / everything on
  friends, with a druid seeing the Curse and Poison and not the Polymorph, a
  priest the reverse, a warrior nothing dispellable but still the sheep.
* **the whitelist beats every filter, the blacklist loses only to it.**
* **the cap trims the right end.** Under PRIORITY sort the stun stays and the
  twelfth dot goes; permanents sort last under TIME.
* **the big aura leaves the row** unless duplicates are asked for.
* **the hit box, totems, timers, healer memory, emphasis and dispel sets**
  each do the one thing their setting describes.

## What the board smoke asserts

The half the engine cannot reach: hooks firing, alphas written and **given
back**, because Blizzard's unit frames are pooled and the next occupant of one
is somebody else. A Grounding Totem becomes an icon and its bar goes to alpha
0; the unit leaves; the same frame carries a warrior and his bar is visible.
The hit box is refused in combat (the client's `CanChangeHitTestPoints`
rule) and lands at `PLAYER_REGEN_ENABLED`. Disabling the module hands back
Blizzard's colour, aura frame and hit box, and a plate that arrives while
disabled is untouched. The settings page BUILDS — every control's options
table is checked for a face and a value, and every dropdown's default is one
of its own options.

## The radial plate

`CommanderPlatesRadial.lua` is the second plate style's brushes, shared with
the settings preview the way `CommanderPlatesDraw.lua` is. Engine section K
pins its geometry and rules: who becomes a disc (never a totem), that angles
run clockwise from twelve like the client's Cooldown sweep (health ENDS at twelve and drains clockwise), the nearest ring
weight, the radii with a pixel of air between bands, an orbit that spills
into a second ring rather than overlapping (40 icons, no two closer than an
icon), the centre text in every mode, threat for a damage dealer and a tank,
and the damage trail's hold, drain and landing. Board section R drives a live
disc: Blizzard's bar, name and cast bar go to alpha 0 and come back on
removal, on Classic, on a narrower scope and with the module off; health and
mana arcs read back at the right fraction; a hit leaves a trail that drains
and stops the animation clock; a cast sweeps the outer ring, takes the face,
lights the halo and clears; an interrupt flashes and fades; a stun takes the
face with its swipe and is not drawn twice; target glow, arrows, scale and
combo pips; an elite NPC's portrait, level, gold rim, skull and threat halo;
a totem stays an icon; a pooled frame's next occupant inherits nothing;
Commander Diminish's open categories orbit as icons labelled with the NEXT
bracket and sweep to reset; the cast line names its target ("YOU" in red) and
follows a mid-cast swap; plate stacking is sized to the disc, deferred out of
combat, and handed back through Blizzard's own sizing pass; an enemy player
targeting you wears a red ring that goes when they look away; an arena
seat's trinket sits on the rim, green when ready, greyed and sweeping once
used; a corpse's face goes grey with "Dead" in the middle; under a red /
green ring colour an enemy mage's ring stays mage blue while a friend's keeps
the green, and goes red with Enemy Players: Class Colour Ring off. The
preview repaints as discs under every scope, name place, face and icon shape.
Three mutations (fill direction, flash length, the totem exemption) were run
against it and each turned it red.

## The settings-reach check

`settings_reach.py` walks `DefaultSettings`, every `DB("Key")` / `S("Key")`
read in the runtime and engine, every `toggle = "Key"` in `DATA.KIND`, every
`key = "Cv..."` in `DATA.CVARS`, and every `CommanderPlatesDB.Key` the page
touches, and reports a setting the plates obey that no control can change
(UNREACHABLE) or a control that writes a setting nothing declares (DEAD).
171 settings, all reachable (the radial brushes read theirs through `G("Key")`,
which the check also walks).

# Commander Threat harnesses

Run both before any change (luajit, absolute paths baked in):

    /opt/homebrew/bin/luajit threat_harness.lua      # engine fixtures (pure Lua, no mock)
    /opt/homebrew/bin/luajit threat_ui_harness.lua   # UI smoke: real Commander_Events framework under the WoW mock

`threat_harness.lua` drives canned observation streams through the real
engine: sorting/ranks, TPS math, and every warning edge (hysteresis,
mob-change re-arm, silent adoption, contested-list loss, healer inbound).

`threat_ui_harness.lua` loads the real settings framework plus all three
addon files, then walks login, the panel, role switching, live sampling in
all three roles, the pinned-self row, warnings (klaxon counts), the test
fight per role, visibility rules, Restore Defaults keeping roles, the
Meters embed cycle (registration, board retirement, provider rows,
warnings-while-embedded, graceful degradation with Meters absent), the
three board layouts (Full ⇄ Compact height and dropped header text, Hidden
beating both Only In Combat and the unlock override, warnings unaffected by
all three), and the target-frame readout (all six modes, the fill fraction
against Blizzard's real 119px health bar, both portrait anchors for the
percentage plate, AGGRO, the tank's chaser reading, the alert wash and its
decay, and the hide rules for an unattackable or absent target). The saved
variables it seeds carry the v1 `TargetEmbed` vocabulary, so the DB
migration ladder is exercised at login rather than assumed.

Both harnesses resolve the AddOns root from their own location, so they test
the tree they live in — a git worktree included.

The Meters side of the embed contract is pinned in
`Commander_Meters/Harness/meters_ui_harness.lua` (its external-mode
section) — run that too when touching the embed.

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
fight per role, visibility rules, and Restore Defaults keeping roles.

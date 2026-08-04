# Commander Buffs harnesses

Run both before any change (luajit; paths resolve from the harness file, so
these work in a worktree):

    /opt/homebrew/bin/luajit buffs_engine_harness.lua   # priority engine (pure Lua, no mock)
    /opt/homebrew/bin/luajit buffs_ui_harness.lua       # UI smoke: real Commander_Events framework under the WoW mock

`buffs_engine_harness.lua` drives the ordered policy: every matcher (type,
source, spell ids, name fragment, dispel school incl. the NONE pseudo-school,
stacks, duration window, boss/stealable/untimed), scoring (expiry bonus,
per-stack bonus), first-match-wins claim order, HIDE vetoes, the three
fallback modes, the minimum-score gate, deterministic tie-breaks, the
editor's list operations, and normalization of whatever SavedVariables hands
back. It also pins the invariant that derived lookups never get written onto
a rule — the rule table IS the saved record.

`buffs_ui_harness.lua` loads the real settings framework plus all four addon
files under a fixture-driven aura API, then walks: the migration off the
retired v1 module's keys, the panel and its slashes, the block (icon pooling,
the three Block Contents modes, group order), the Buffs-On-Top mirror in all
three modes including the no-source fallback, the hiding of Blizzard's frames
(including the combat deferral, a client re-show being put back down, and the
"no block means no hide" guarantee), the portrait sentinel (slots, minimum
score, empty stack), the test stack, and the whole editor — list operations,
inspector cycling, the live trace, Capture, Restore Default Rules, and the
proof that the settings page's Restore Defaults leaves hand-authored rules
alone.

The UI harness's mock adds two things the shared Threat preamble lacks:
`RegisterUnitEvent` routed to the event registry, and the extra named regions
of `BasicFrameTemplateWithInset` (`NineSlice`, `Bg`, `TitleBg`, `Inset`) —
without them the permissive widget metatable hands back a bare function that
indexes fine and then explodes on the method call.

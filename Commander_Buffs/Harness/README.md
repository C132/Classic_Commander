# Commander Buffs harnesses

Run both before any change (luajit; paths resolve from the harness file, so
these work in a worktree):

    /opt/homebrew/bin/luajit buffs_engine_harness.lua   # priority engine (pure Lua, no mock)
    /opt/homebrew/bin/luajit buffs_ui_harness.lua       # UI smoke: real Commander_Events framework under the WoW mock

`buffs_engine_harness.lua` drives the ordered policy: every matcher (type,
source, spell ids, name fragment, dispel school incl. the NONE pseudo-school,
loss-of-control category, stacks, duration window, boss/stealable/untimed),
scoring (expiry bonus, per-stack bonus), first-match-wins claim order, HIDE
vetoes, the three fallback modes, the minimum-score gate, deterministic
tie-breaks, the editor's list operations, and normalization of whatever
SavedVariables hands back. It also pins the invariant that derived lookups
never get written onto a rule — the rule table IS the saved record.

Three things it guards specifically, because they are the module's promises
rather than its mechanics:

- **The control taxonomy is coherent.** Seven categories, unique keys, every
  category carrying a label and a color, and the flat `CC_IDS` list the rest
  of the suite reads being EXACTLY the union of the categories — so the two
  descriptions of "what counts as CC" cannot drift apart.
- **ALERT beats the floor and nothing else.** A minimum score above every
  rule in the policy still lets an ALERT through; an ALERT still loses to a
  higher score, and an earlier HIDE still vetoes it.
- **The shipped policy actually focuses.** Against the shipped floor of 90,
  every one of the seven categories takes the portrait over a boss debuff AND
  a defensive, while a dispellable debuff, a stacking debuff, a short buff of
  mine and a raid buff all fail to reach it at all.

`E.IsUntouchedRuleSet` — the test the v3 migration uses to decide whether it
may replace the rule list — is covered here too, against both the current and
the previous shipped rule names, with renamed / deleted / added rules all
correctly reading as touched.

`buffs_ui_harness.lua` loads the real settings framework plus all four addon
files under a fixture-driven aura API, then walks: the migration off the
retired v1 module's keys, the panel and its slashes, the block (icon pooling,
the three Block Contents modes, group order), the Buffs-On-Top mirror in all
three modes including the no-source fallback, the hiding of Blizzard's frames
(including the combat deferral, a client re-show being put back down, and the
"no block means no hide" guarantee), the portrait sentinel (slots, minimum
score, control takeover, empty stack), the test stack, and the whole editor —
list operations, inspector cycling, the live trace, Capture, Restore Default
Rules, and the proof that the settings page's Restore Defaults leaves
hand-authored rules alone.

The `K:` block is the guard on the Blizzard icon style, and it checks
appearance rather than behavior: that Blizzard style leaves the icon art
UNTRIMMED, puts no border at all on someone else's buff, uses the client's own
`UI-Debuff-Overlays` art for debuffs (and for the optional gold on your own
buffs), and sizes that border to overhang its icon exactly as Blizzard's
does — then that Commander style trims the art back and rims everything
again. The mock records `SetTexCoord` purely for this: whether the icon art is
trimmed is the single loudest tell that a block belongs to an addon.

The `G:` block covers My Buffs Larger, and most of it is about what the
enlargement must NOT touch: someone else's buff keeps its size, a debuff YOU
applied keeps its size (the feature is scoped to upkeep, like the gold rim),
the block widens to hold the larger cell instead of letting icons overlap,
and the debuff border scales with the icon it belongs to.

Two `S:` checks are the redesign's central promise and should be the first
things looked at if the sentinel ever feels chatty again: no floor can silence
loss of control (an ALERT rule ignores Minimum Score entirely), and control
takes the portrait ALONE — asking for three slots still gets one while
something has hold of you.

The UI harness's mock adds two things the shared Threat preamble lacks:
`RegisterUnitEvent` routed to the event registry, and the extra named regions
of `BasicFrameTemplateWithInset` (`NineSlice`, `Bg`, `TitleBg`, `Inset`) —
without them the permissive widget metatable hands back a bare function that
indexes fine and then explodes on the method call.

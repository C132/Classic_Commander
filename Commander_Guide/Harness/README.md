# Commander Guide — harness

Run from the AddOns directory:

    /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_engine_smoke.lua   # 236 checks
    /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_ui_smoke.lua       # 143 checks
    /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_orders_smoke.lua   # 81 checks
    python3 Commander_ArenaFrames/Harness/order_lint.py Commander_Guide/*.lua  # must print "no use-before-declaration"

(Caution, 2026-10-05: `order_lint.py` ignores its arguments and lints its
own FILES list, Commander_ArenaFrames' files, so the last line checks nothing
of the Guide's. The Guide's files were checked by hand for 1.2.0 the same
way: `luajit -bl` over each one, every global READ that should have been a
local. Fixing the script is Commander_ArenaFrames' follow-up.)

`guide_engine_smoke.lua` is pure: the data file and the engine, no mock.
It validates every page and callout (ids present, kinds known, combat lines
at most fourteen words, `%t` only where there is a person), then drives
pulls through the engine: Moroes by encounter id, Maiden by creature id,
Aran's Flame Wreath on you versus on a friend, Netherspite's stack count,
Nightbane's yells, cooldown / once / per-person rules, the speech queue's
stale drop and urgent cut-in, the brief and the page layout.

`guide_ui_smoke.lua` loads the suite's REAL settings framework over a widget
mock with a recording voice (`C_VoiceChat.SpeakText` captured with its five
arguments), then plays a client at the runtime: login in Karazhan, targeting
Moroes reads the brief once, `ENCOUNTER_START` opens the pull and lines
queue behind speech, Blind cuts in, `UNIT_HEALTH` crosses 30 %, a pull with
no `ENCOUNTER_START` opens on a creature id and closes after the grace, the
window renders eleven bosses and every section, the settings page lists
the voices, and the slash words work.

Since 1.1.0 both also cover the way in (DECISIONS D11). The engine smoke's
section I checks every raid door in `D.ENTRANCES` against Questie's own
dungeon rows (0..100, so a missing division fails) and against the raid
map's parent in the UiMap DB2 (so a door filed on the wrong zone fails),
then the Add spec: Orders' resolver answer first and only when it is a
position, the table otherwise with both of Karazhan's doors as
alternatives, a resolver point that is one of the table's doors (QuestLog's
resolver answers Questie's first door only) carrying the other doors along
too, one key per raid, the `/way` line. The UI smoke's section J
drives the button, the slash word, the key binding and the settings
button against a recording Commander Orders stub: greyed out inside
Karazhan and lit again on zoning out, the resolver asked for uiMap 350
first, a throwing resolver or a throwing Add caught, a refusal
("disabled") put into words with the `/way` line, and Orders absent
printing the line instead. The real Orders runtime accepting the same
spec is checked in `Commander_Logistics/Harness/logistics_orders_smoke.lua`
section G, including the arrow taking the nearer Karazhan door when a
resolver answered the first one.

1.2.0 (DECISIONS D12, Commander Orders 3.1) renamed the button "Go to
Entrance" and the binding "Go to the raid's entrance", and took Orders' one
refusal vocabulary ("Commander Orders is turned off (/corder)"): those four
wording checks in section J moved with it (labelled, the binding's name, the
turned-off line, the settings page's button). Section J's stand-in is an
Orders 3.0 (Add and Entrance, no GoTo), so it still proves D11's path.

`guide_orders_smoke.lua` boots the REAL Orders 3.1 through
`Commander_Orders/Harness/orders_mock.lua` (Commander.UI.GoButton in its
Events slot, every Orders file, the locator's door table) and loads the
guide after Orders' ADDON_LOADED. A: the window's button is the suite's
GoButton, "Go to Entrance". B: `CommanderGuide_Entrance` goes through
`GoTo({ entrance = { instance = 532 } })`: one waypoint (Guide,
entrance:KARAZHAN), the very two doors `CommanderOrders.Entrance({ instance
= 532 })` answers, the arrow on the nearer, Orders' own "Waypoint set" line
and none of the guide's. C: the window's button is the same Go, lit "Going
to Entrance", its tooltip, Shift-click sharing the readable line, Ctrl-click
the /way line in Orders' copy box, greyed inside Karazhan. D: Orders turned
off: one line from Orders with the door and its [Go]; the button greyed with
Orders' reason. E: Orders without its locator files: the guide's cited table
through the same GoTo, both doors, greyed inside all the same. F: Orders'
door table answers all nine raids on the zone the guide's row names. G:
Orders not loaded: the button and the slash word print the /way line.
Mutation hook `GUIDE_RUNTIME=/path/copy.lua`; six hand-made mutants (no GoTo
branch, the table always, no GoButton, the key never set, inside ignored on
the table path, a line of the guide's own on success) each fail at least one
check.

None of them touches the game. What they cannot see is in `../ASSUMPTIONS.md`.

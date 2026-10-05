# Commander Guide — harness

Run from the AddOns directory:

    /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_engine_smoke.lua   # 236 checks
    /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_ui_smoke.lua       # 143 checks
    python3 Commander_ArenaFrames/Harness/order_lint.py Commander_Guide/*.lua  # must print "no use-before-declaration"

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

Neither touches the game. What they cannot see is in `../ASSUMPTIONS.md`.

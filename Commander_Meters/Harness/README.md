# Headless harnesses (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit meters_harness.lua      # engine fixture: §7 invariants,
                                                     # determinism, retention, resets,
                                                     # throughput measurement, match mode, dispels (910 checks)
    /opt/homebrew/bin/luajit meters_arena_harness.lua # arena match engine: both teams,
                                                     # the DR ladder, replay state,
                                                     # persistence round trip, insights, history, replay records, the three-source trinket, Feign Death, your personal rating in a teamless season, dispels + Mass Dispel + the dispel log (519 checks)
    /opt/homebrew/bin/luajit meters_ui_harness.lua   # UI smoke under a WoW mock, loading
                                                     # the REAL Commander_Events framework,
                                                     # incl. the Arena Report and a live
                                                     # match through the event path, the spectator replay, the sidebar, match mode, the trinket badge and its client source, a live feign, the dispel log drawer and the DISPELS split (399 checks)

Paths to the AddOns dir are absolute at the top of each file — adjust if the
install moves. All three must exit 0 before any engine or UI change ships. Then:

    python3 Commander_ArenaFrames/Harness/order_lint.py Commander_Meters/*.lua

Arena Frames' bytecode lint: a local used above its own declaration compiles
to a nil global and throws only when that branch first runs — in this addon,
possibly mid-match. Must print "No use-before-declaration".

## The Arena Report renderer

```
luajit Commander_Meters/Harness/meters_arena_render.lua report.json [cursorSeconds]
python3 Commander_ArenaFrames/Harness/render_svg.py report.json report.svg 2
qlmanage -t -s 1900 -o . report.svg        # report.svg.png, on a Mac
```

The UI smoke's mock records every SetPoint, SetSize, colour, texture,
font size and text; this runs the smoke and, at the moment the Arena
Report is up on the canned 3v3, resolves every anchor to a rectangle and
writes the lot for Arena Frames' SVG script. Text widths are estimated
(no font metrics; icon escapes show as their raw text); positions, sizes
and colours are exact. Pass a cursor time (e.g. `128`) to see the board
scrubbed mid-match — HP strips, control tags, cooldown tags. Devin's
first-look layout pass (D27 pass 8) was made against these pictures;
render before shipping any change to the report.

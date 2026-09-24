# Headless harnesses (never loaded by the client — not in the TOC)

Run with the compile-gate luajit:

    /opt/homebrew/bin/luajit forecast_model_smoke.lua   # the estimator, with no client at all:
                                                        # tooltip parser against verbatim TBC
                                                        # spell text, TBC's coefficient rules,
                                                        # the sample arithmetic, and which of
                                                        # the two estimates wins (132 checks)

    /opt/homebrew/bin/luajit forecast_ui_harness.lua    # UI smoke under a WoW mock, loading the
                                                        # REAL Commander_Events framework plus
                                                        # all three module files: login, the
                                                        # settings page, the repaint over mocked
                                                        # action buttons, the combat log, the
                                                        # tooltip breakdown, both slash
                                                        # subcommands, and the mage bar
                                                        # from the field: async spell text,
                                                        # Ice Barrier, Frost Ward, Ice Lance
                                                        # flexing on Frozen (56 checks)

`FORECAST_DUMP=1` on the UI harness prints the numbers each mocked button ends up carrying —
useful when changing the model, because a wrong coefficient shows up as a plausible-looking
number that no assertion happens to name.

The model file gates its whole runtime section on `CreateFrame` existing, which is what lets the
first harness load it with no client and drive the parser directly.

Paths to the AddOns dir are absolute at the top of each file — adjust if the install moves. Both
must exit 0 before anything here ships.

The UI mock is copied from `Commander_Meters/Harness/meters_ui_harness.lua` and extended with the
surfaces this module reads: the character sheet, the action bars, a tooltip that really fills and
really counts lines, and a scriptable combat log.

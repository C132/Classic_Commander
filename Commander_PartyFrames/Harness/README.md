# Commander_PartyFrames harness

One luajit harness, run per class layer, and one Python reachability check.
None of it is loaded by the client (nothing here is in the TOC). Both run
from any directory (the smoke's paths are absolute, the script finds its
files from its own path); every documented run must exit 0 before any Party
Frames change ships:

```bash
cd Commander_PartyFrames/Harness    # or name the files by full path
/opt/homebrew/bin/luajit partyframes_banner_smoke.lua MAGE              # 764 checks
/opt/homebrew/bin/luajit partyframes_banner_smoke.lua PRIEST            # 557 checks
/opt/homebrew/bin/luajit partyframes_banner_smoke.lua DRUID             # 496 checks
/opt/homebrew/bin/luajit partyframes_banner_smoke.lua PALADIN           # 509 checks
/opt/homebrew/bin/luajit partyframes_banner_smoke.lua MAGE clickcast    # 58 checks
/opt/homebrew/bin/luajit partyframes_banner_smoke.lua DRUID clickcast   # 58 checks
python3 settings_reach.py                                               # 148 keys across 4 pages, exit 0
```

The AddOns path is absolute at the top of the smoke (`ADDONS`): adjust it if
the install moves. It loads the real Commander_Events settings framework and
chrome, then the module's own files, under a client mock modelled on
Commander_Production's harness.

## partyframes_banner_smoke.lua

A class with no layer has no board and no banner, so it runs once per
supported class. The sorted run covers the banner utilities (the split
drink / eat button, inventory counters, the mana gem, the portals popout, the
bandage button), each class layer (the priest's shield board and Prayer of
Mending, the mage's absorb tracking and upkeep banner, the druid's hot board
and Lifebloom, the paladin's one blessing slot per ally and Forbearance), the
header, Nearby Raid, sorting, the power strip, the forecast, and every
settings key the layer reads.

The `clickcast` mode runs the secure CLICK-CAST board in a process of its
own: whether the rows are secure is decided once at login, so the sorted run
cannot reach it. It exits after the secure-board section. MAGE and DRUID are
the documented runs. PRIEST and PALADIN clickcast runs have 5 class-order
failures each that are PRE-EXISTING (the same 5 on the last commit's files,
checked on a `git archive` copy, 2026-10-05): their expected class order is
the mage's; they are not documented runs. Since 5.44.0 the PRIEST clickcast
run also checks Team Shields on the secure board (a dial per seat, the bound
rows under the dial line): 60 checks since 5.45.0, the same 5 pre-existing failures.

**Team Shields and Mending Wasted (5.44.0).** The PRIEST run adds two
sections at the end of the Mending tracker. Mending Wasted, in a mock party:
a five-charge Mending that heals and jumps nowhere waits out the grace and
then plays the holy fizzle BY FILE ID (569772); four grouped hops count the
charges down so the fifth heal is SPENT (the high bell, 566564); a mid-chain
heal with charges left fizzles; expired and purged fizzle; died-with-holder
is the low bell (565853); the new line honours Silent and appears in the
priest's Alert Sounds. Team Shields: a dial per seat with the class icon as
the face, Weakened Soul as the wipe with its seconds and the red EXPOSED
rim, a shielded teammate lit with band and clock, the yellow READY rim only
when hurt or fighting, the Mending badge with its charges and a green ring
inside twenty yards (UnitPosition stub), red when everyone walks off, no
ring when a teammate cannot be placed, and Include Yourself / Team Shield
Dials switching seats off.

**5.45.1: no numbers, Weakened Soul in red.** The team dials write nothing on
the face or the Mending badge (checked), and Weakened Soul is a RED wipe
(the mock records SetSwipeColor as `__swipe`) on a bare dial and a shielded
one alike. Your own seat is checked under your own shield with your own
Weakened Soul — the case that read as "not tracked" in game — and follows
the expiry read straight off your auras.

**Arrow to them (5.41.0, Commander Orders) and 5.42.0 (Orders 3.1).** Every
run drives `/cpf arrow`, Orders' refusals, the no-Orders `/way` line and the
roster tracking: a reshuffle re-points the follow at the same GUID without
taking the arrow back, someone who left is unfollowed, and a follow Orders
dropped is not brought back. The Orders stand-in is `GoTo` (it records the
target and the options): the checks assert the follow is
`{ kind = "unit", unit = token, guid = UnitGUID(token) }` with the UNIT icon,
that the roster re-point is silent, and that the board prints no line of its
own (Orders speaks for the press: "Waypoint set" or its one refusal line,
Orders' DECISIONS D31). The clickcast run binds Shift+Right to the action
and dispatches the row's custom action type the way SecureTemplates.lua does,
in combat and as a physical click. 5.42.0 also adds the key binding "Arrow
to My Target" (Bindings.xml, `COMMANDERPARTYFRAMES_ARROW`, unbound until the
player sets a key; a new file, so a full client restart).

Existing checks edited for 3.1, all forced by Orders' words rather than
taste: "arrow: one line says so", "arrow: ...in words", "a throwing Add is
caught" (it throws in GoTo now) and the clickcast "...and ONE chat line"
(it counts the non-silent GoTo asks; the board has no line of its own).

Open, for Devin (not changed): the click-cast rows register AnyDown and
AnyUp, and 2.5.6's SecureUnitButton_OnClick dispatches every phase, so a
spell, macro or target binding runs twice per click (menus act on the up
phase only). A fix needs per-phase attributes through 2.5.6's "downbutton"
remap and an in-game test; Orders' DECISIONS D41.

**Ice Block tracker and the arena reset (5.43.0).** The MAGE run has a
section of its own for the tracker (`ice block:`): its seat, last on the
shields' line; each rung of its ladder (Hypothermia over a ready Cold Snap,
with the Block's ten seconds on the outer clock; Ice Block ready; Cold Snap
ready in gold; both cooling, whichever ends first); the global cooldown
ignored; a mage without Cold Snap; its own switch, independent of Show My
Shields; untrained means no seat; the Rows shape and Alerts Only; and, last
in the run, the `/cpf test` preview (last because the preview builds pooled
rows a later check expects to be new). Every class runs `CheckArenaReset`
(`arena reset:`): a party warrior's Intimidating Shout and your own Will of
the Forsaken come back on an arena zone-in, a thirty-minute Shield Wall does
not, and a battleground or the open world hands nothing back.

One existing section's SETUP changed, its checks did not: the shield-dial
section ("The personal block as dials") counts shield seats, so it now holds
`TrackIceBlock` off for its duration and restores it after. The tracker is on
by default and the mock mage knows Ice Block, so without that the section's
five seat counts would each read one more.

## settings_reach.py

Walks the engine's `DB("Key")` reads and the four settings pages (shared
builders expanded inline) and fails when a setting the engine reads on a
layer cannot be reached from that layer's page. `LAYER_SCOPED` in the script
is the only hand-kept part. Prints `settings_reach: OK` and the count.

## make_bars.py, make_dials.py

Generators for the bar and dial art in `../Textures` (stdlib only), not
checks: run them only to regenerate the art, and restart the client after a
new or changed PNG.

# Headless harness (never loaded by the client — not in the TOC)

Run all four with the compile-gate luajit. All must exit 0 before any Oracle
change ships.

    /opt/homebrew/bin/luajit globals_lint.lua          # 5 files, 0 undeclared globals
    /opt/homebrew/bin/luajit oracle_engine_smoke.lua   # the projection math (122 checks)
    /opt/homebrew/bin/luajit oracle_roster_smoke.lua   # the Impact score, the
                                                       # one-line read and the
                                                       # range shapes (95 checks)
    /opt/homebrew/bin/luajit oracle_ui_smoke.lua       # the live half under a
                                                       # client mock, loading the
                                                       # REAL Commander_Events
                                                       # framework (266 checks)

`oracle_roster_smoke.lua` needs no mock either, for the same reason as the
engine: `CommanderOracleRoster.lua` is rows in, ranking out. It checks that the
denominator is the trimmed top three rather than the single best (so one farmed
outlier cannot flatten the board), that a metric nobody scored on drops out and
its weight is redistributed rather than quietly reading low for everyone, that
a healer is judged on healing rather than punished for having no damage, that
the TRADE separates two players with identical output and different death
counts, that objectives cannot buy the board on their own, that a player who did
nothing scores nothing however long they lived, and that the one-line read only
names somebody when they actually STAND OUT — leading is not standing out, and
two healers splitting the load is not one healer to focus. The army-level trade
read has to be agreed by BOTH sides before it speaks: one side's killing blows
are the other's deaths, so a real advantage shows up twice, and a bloodbath
everybody is winning is not a trade read.

`F2` is the reweight itself, held to the board that prompted it: a healer with
three base defends used to out-score a warlock on twelve killing blows and the
best damage in the match. Objective columns are 0-to-5 integers — five distinct
values against a trimmed top of about three — so a single cap saturates its own
share, and at the heaviest weight that coarseness ran the whole board. They are
now the smallest weight on purpose. Objectives still decide the MATCH; the
BATTLE tab is what prices them.

`oracle_engine_smoke.lua` needs no mock at all: the canon and the engine never
touch the WoW API, which is the reason they are separate files. It checks the
rates against hand-computed Arathi Basin numbers, the ladder's monotonicity,
and the deadline algebra — including that the deadline is a real boundary, by
running the position forward a second either side of it and confirming the
outcome flips.

`oracle_ui_smoke.lua` drives the two things Oracle actually reads. The mock is
honest about both: `GetAreaPOIForMap` hands back one POI per node the way the
client does, and the resource widget's two bars are fed in the widget's own
order — deliberately swapped in one section, to prove the auto side-detection
settles it from the income rates rather than from a string.

`S` checks that the settings page scrolls. It had quietly outgrown Blizzard's
settings canvas — a little over 500px against the ~1150 this page now flows —
so its last rows were simply unreachable, which is a page with missing
features rather than a cosmetic problem. The rows go into a scroll frame with
`AddRow` overridden on the panel INSTANCE only, the same retrofit ten other
Commander pages already carry; the one difference here is that the scroll
child is re-sized on every refresh rather than once at build time, because a
section note only knows how tall it wraps after the page has a real width, and
the one-shot version leaves whatever grew after it below the bottom.

`R` holds the clickable rows to the rule the protection model imposes. There is
no separate list any more: the ranked rows themselves are secure buttons —
left-click `/targetexact`, right-click `/focus` — which makes the whole board
protected, so every structural call in the module goes through the `Safe*`
wrappers and every one of them is a no-op rather than an error while you fight.

The split those tests exist to defend is structure versus paint. With combat
on, a scoreboard that completely reorders the enemy side must not move a row,
re-bind one, or change the board's height; but the score and the range on those
rows must keep updating, and the name on a row must still match the macro it
carries — a row that relabelled without re-binding would target somebody other
than the name printed on it, which is the one failure that would be worse than
not clicking at all. A tab asked for mid-fight cannot take either, so the strip
lights the tab you are LOOKING at and marks the requested one with a `*`;
`PLAYER_REGEN_ENABLED` lands everything held at once.

`R` also covers the range column, with a mock honest about the client's actual
asymmetry: `UnitPosition` answers for the raid you are in and returns nothing
for anyone else. Its `IsProtected` walks *up* the frame tree the way the engine
does, which is what makes the combat half of `R` mean anything — the board
really does report as protected there, so the `Safe*` wrappers are exercised
rather than merely present.

`T` is the raid markers, and it is written as much around what the feature must
NOT do as what it must: nothing at all until it is switched on, nothing while
you hold neither lead nor assist, nothing on the enemy side, no re-issuing a
mark for two players swapping places, no icon taken from somebody else, no
fighting for one that was taken from us, and everything we placed handed back
when the feature is switched off or the battleground ends. The mock LOGS
`SetRaidTarget` as well as applying it, because "did not re-mark anybody" is a
real requirement and only the call log can prove it.

`U` is the arena half of the markers, where the question is not who is playing
best but who is who, so the team is matched to icons by CLASS COLOUR. The
matching itself is pure and lives in `oracle_roster_smoke.lua` (`A3`): hue
leads and saturation only breaks ties, which is what keeps the mage off the
green triangle — on plain RGB distance a pale cyan and a pale green are close
neighbours and perceptually nothing alike — and a colour is never matched to a
non-colour, so the priest's white takes the skull and nobody else may go near
it. It is matched over the team ACTUALLY present rather than through a fixed
nine-class table, so a warrior is never turned away for having no brown marker
and two mages still get two different icons. Ties break by slot then icon, so
the same team always resolves the same way — an assignment that wobbled would
re-mark the party for nothing.

The UI smoke's `P` and `Q` sections cover the tabs and the scoreboard reader:
the BATTLE tab is offered in Arathi and *gone* in a Warsong Gulch (an Arathi
answer on another map is a wrong one, not a disabled one), the roster tabs are
offered in both, a tab that is not on offer falls back to one that is, and the
server is only polled for a scoreboard while somebody has a ranking open.

## Facts the tests encode (all verified before they were written)

* `GetBattlefieldScore(index)` returns, in this order: name, killingBlows,
  honorableKills, deaths, honorGained, faction, rank, race, class, classToken,
  **damageDone, healingDone** — read out of Blizzard's own
  `Interface/AddOns/Blizzard_FrameXML/TBC/WorldStateFrame.lua` on the
  `classic_anniversary` branch, which is the client this addon runs on. Damage
  and healing ARE reported here; the Wrath-era assumption that they are not is
  wrong for 2.5.x. **faction 0 is Horde and 1 is Alliance** (the same file
  counts the sides that way). Getting the order or the numbering wrong is
  silent and total, so the mock speaks the client's shape rather than a
  convenient one.
* Targeting a player by name is PROTECTED. The only route is a secure button
  carrying `/targetexact <name>` (`SLASH_COMMAND.TARGET_EXACT` is registered
  through `CheckAddSecureSlashCommand` on this client, and `TargetUnit` is only
  reachable from secure code). A secure button cannot be re-bound, moved, shown
  or hidden in combat, and the block walks UP: any frame carrying one is
  protected too. The board carries them, so the board is protected: its layout
  holds the shape it had when the fight started, and every structural call goes
  through a wrapper that no-ops instead of erroring. Painting — textures and
  fontstrings, including those inside a secure button — is never protected, and
  that is the whole reason a held row can still be honest.
* Raid markers: `SetRaidTarget(unit, index)` / `GetRaidTargetIndex(unit)` /
  `CanBeRaidTarget(unit)` are all present and are NOT protected, so they work
  in combat, which is the whole point. `IsRaidLeader`/`IsRaidOfficer` are GONE
  from this client — permission is `UnitIsGroupLeader("player")` and
  `UnitIsGroupAssistant("player")`, and the server refuses a marker from anyone
  else. Marking is only possible where the client hands out a unit token, which
  in a battleground is your own raid and nothing else — so "mark our side's
  best" is exactly the shape the API supports, and marking the enemy is not
  available at any price.
* `UnitPosition` answers for members of your own group and returns nothing for
  anyone else, so an enemy's distance is not available in a battleground at
  all. What is available is the interaction bands
  (`CheckInteractDistance(unit, 3/2/1)` = 10 / 11 / 28 yards) against whatever
  unit token you happen to be holding — target, focus, mouseover, or a
  nameplate. Those are upper bounds, and the range column writes them as
  bounds.
* Objective columns belong to the map, not to the addon:
  `GetNumBattlefieldStats()` / `GetBattlefieldStatInfo(i)` name them and
  `GetBattlefieldStatData(playerIndex, i)` fills them, so Arathi's bases,
  Warsong's flags and Alterac's five all arrive without a table here to
  falsify.

* Arathi Basin is uiMapID **1461** on this client (Classic map set, not
  retail's 93) and instance map **529** — client `UiMap` DB2.
* Each node has five area POIs, one per state, gated on a world state. The IDs
  in `CommanderOracleData.lua` come from the client's own `AreaPOI` DB2 at
  build 2.5.6.69546, and match CMaNGOS `BattleGroundAB.h` one for one.
* Ticks: `{0, 12000, 9000, 6000, 3000, 1000}` ms for `{0,10,10,10,10,30}`
  points. The fifth base is worth **nine times** the fourth.
* Cap 2000, near-victory 1800, flag capture 60s.
* The old `GetNumWorldStateUI`/`GetWorldStateUIInfo`/`GetMapLandmarkInfo` API
  is **absent from this client's binary** — it runs the modern widget
  framework. Node ownership comes from `C_AreaPoiInfo`. Do not reach for the
  vanilla API here.
* **Resources are TWO `IconAndText` widgets, not a `DoubleStatusBar`.** The
  DoubleStatusBar is the retail shape and was what this reached for first; in
  a live Arathi Basin on 2026-09-06 it read back empty while Blizzard's own
  display showed `Bases: 1  Resources: 20/2000` on two lines. Only the numbers
  are parsed (the pair around the slash, then the number in front of it), so
  the reader is locale-proof. The bar path is kept as a fallback.
* **Which line is which faction is decided by arithmetic, not by text.** Each
  line states its side's base count, and the map already gave the exact count
  per faction — matching them names the sides with certainty whenever the two
  counts differ, and the answer is remembered for the moments they are equal.

## The comms header

Three buttons across the top post to battleground chat: CALL (the whole read),
DEFEND (the flags they are taking, with what losing them costs) and TAKE (how
many more bases and how long there is left). Everything about them is designed
so the addon can never become chat spam, and the tests in section O enforce
each part: **nothing is ever sent without a click** (sixty seconds of ticking
must produce an empty chat log), each button is throttled 8s with a 2s global
floor, a button with nothing true to say is disabled rather than hidden (so the
header cannot reflow under the cursor), and hovering shows the exact line
first. The slash commands `/coracle call|defend|take` go through the same
builder, so what they post and what the buttons post cannot drift.

## Typography rules that came from the board being unreadable

Both of these were shipped the wrong way round first and had to be corrected
against a live game, so they are worth stating.

* **Shadow always, outline only on request.** An `OUTLINE` flag on a 10-12pt
  FRIZQT glyph closes up the counters and reads as a smudge; the hard shadow
  gives the same separation from the world at no cost to the letterforms.
  `TextOutline` therefore defaults to OFF.
* **Nothing may use `GameFontDisableSmall`.** It is locked to Blizzard's
  mid-grey, which over Arathi's grass with no panel behind it is the least
  readable thing that can be put on screen. Every caption takes an explicit
  `SetTextColor` instead.
* **Compact saves height by dropping elements, never by shrinking type.** Text
  sizes are identical at Full and Compact; the saving comes from swapping the
  bars for their own numbers and folding the ladder into a strip. "Compact"
  refers to the information, not the pixels.
* **Node ownership is a rule under the name, not a colour block behind it.**
  Text on a tinted quad fights its own background for contrast, five times
  over, and a 3px underline carries the same colour information.

## Four behaviours worth not "fixing"

* **The ladder disagrees with the headline, on purpose.** Every ladder row
  assumes the enemy takes every base you do not hold, so a row is a guarantee;
  the headline reads the board as it actually stands, where a neutral or
  ticking node pays nobody. The on-screen header says so.
* **Leaving has a ten second grace, entering does not.** Releasing to the
  graveyard fires `PLAYER_ENTERING_WORLD` with the player reported outside the
  instance; committing to that would wipe the contested clocks and the carried
  score on every death.
* **A deadline is hidden when it lands after the game would end anyway.** In
  the opening minutes, while you out-earn them, the algebra honestly returns
  something like two hours — a real answer to a question nobody is asking,
  which on screen reads as a broken clock.
* **A section with nothing to say is hidden, not drawn empty.** An
  unprojectable board used to reserve six blank ladder rows and leave a hole
  the size of the addon in the middle of the frame.

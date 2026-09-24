# Commander_Muster — assumptions to verify in game

Everything here passes the headless harnesses, which prove the logic and nothing
about the live client. Numbered so a test session can report against them.
A1–A3 carry the tooltip feature; the rest degrade to "a line is missing".

The inspect and arena API shapes were read from Blizzard's own 2.5.x UI source
(`Gethe/wow-ui-source`, branch `classic_anniversary`: `Blizzard_InspectUI/TBC`,
`Blizzard_InspectUI/Classic/InspectPVPFrame.lua`,
`Blizzard_UIPanels_Game/Classic/PVPFrameBase.lua`) before a line was written.
What is listed here is the residue source cannot settle — runtime behaviour and
server rules.

---

## A1 — A quiet `NotifyInspect` answers with `INSPECT_READY(guid)` and fills `GetInventoryItemLink(unit, slot)`

**Load bearing for the tooltip.** The inspect window does exactly this
(`InspectFrame_Show` → `NotifyInspect` → `INSPECT_READY` → `InspectPaperDollItemSlotButton_Update`
reading `GetInventoryItemTexture(unit, id)`), so the channel exists; what is
assumed is that it works with no frame shown. TacoTip and LibClassicInspector
run on this exact basis on 2.5.x, which is strong evidence.

Test: mouse over a guildmate in a city. Within a second the tooltip should
gain a `Gear score` line. `/gs report` is your own; for theirs, open the
inspect window and compare the readout with what the tooltip said.

## A2 — `CanInspect(unit, false)` is the right gate, and is false for the other faction

The module only ever inspects a unit `CanInspect` accepts. If the second
argument is ignored and the client prints the "you cannot inspect" error text
on every cross-faction mouseover, that is this assumption failing.

Test: mouse over an enemy-faction player in Shattrath. No error text, no line.

## A3 — `RequestInspectHonorData()` → `INSPECT_HONOR_UPDATE` works for the current inspect target without the PvP tab

Blizzard requests it from `InspectPVPFrame_OnShow`; the module requests it
right after `INSPECT_READY`. If the server only answers while the PvP tab is
showing, the honor timeout (3s) fires, the gear line stays and the arena line
is simply absent. The next hover asks again.

Test: mouse over someone you know is rated. The `Arena` line should arrive with
or just after the `Gear score` line.

## A4 — The season is TEAMLESS on this realm (`GetCurrentArenaSeasonUsesTeams()` is false)

Both shapes are implemented and the branch is taken at runtime, so nothing
depends on the answer. It decides which functions are read:

- teamless: own `GetPersonalRatedInfo(i)` (after `RequestRatedInfo()`,
  `PVP_RATED_STATS_UPDATE`), inspected `GetInspectArenaData(i)`
- teams: own `GetArenaTeam(i)` (`ARENA_TEAM_UPDATE`), inspected
  `GetInspectArenaTeamData(i)`

Test: `/dump GetCurrentArenaSeasonUsesTeams()`. Then check that your own
readout's `Arena` line matches the PvP frame's numbers.

## A5 — The `teamSize` return position in each tuple

- `GetPersonalRatedInfo`: 12th return
- `GetInspectArenaData`: 7th return
- `GetArenaTeam` / `GetInspectArenaTeamData`: 2nd return

Read from Blizzard's own destructuring in the files above. A wrong position
shows as a bracket printed under the wrong label (a 2v2 rating as 3v3) or
every bracket missing. Test: compare the readout against the PvP frame.

## A6 — `INSPECT_READY` fires for the inspect window's target with `InspectFrame.unit` still set

The inspect readout rides along on the window's own answer and reads through
`InspectFrame.unit`. `InspectFrame_OnEvent` does the same comparison
(`UnitGUID(InspectFrame.unit) == guid`), so this is Blizzard's own contract.

Test: inspect someone. The readout should appear in the top-right of the model
at the same moment their gear does.

## A7 — `frame:EnableMouseMotion(true)` exists, so the readout takes hover without taking the drag

Noted in the suite's API memory as present on this engine. The code falls back
to `EnableMouse(true)` if the method is absent; the cost is that the top-right
170×28 of the model no longer rotates it on drag.

Test: hover the readout for the breakdown tooltip; then drag from that same
corner and confirm the model still turns.

## A8 — `GET_ITEM_INFO_RECEIVED` follows `C_Item.RequestLoadItemDataByID` for an inspected player's items

Standard in the suite (Armory, Spoils, Quartermaster all rely on it). Here the
consequence of it not firing is a permanent `…` after a stranger's score until
the next inspect.

## A9 — Item links carry the name for an uncached item

`ItemName(link)` reads the `[Name]` from the link so the breakdown can name a
piece that is still loading. If a link arrives with an empty name the row
prints `?`, harmlessly.

## A10 — `ITEM_QUALITY_COLORS[q].hex` is present

Used to colour piece names in the breakdown; a missing `.hex` falls back to
white.

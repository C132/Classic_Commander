# Commander_Muster — decisions

Numbered so code comments and future sessions can cite them.

## D1 — The score is TacoTip's TBC GearScore, to the digit

A gear score is a convention, and a convention only works if everyone's
number agrees. On TBC Classic the number people quote comes from TacoTip
(anzz1/TacoTip, `gearscore.lua`), which is GearScoreLite's formula with one
fix: the original was written for Wrath and switches curves at item level
120, which for this expansion is a cliff — a Tier 4 helm at 120 scores 145
and a Tier 5 helm at 133 would have scored 119. TacoTip keeps epics on the
low curve to 168, rares to 148, uncommons to 138, and gives sub-100 epics
their own curve. The result is monotonic across every item TBC drops (the
engine harness sweeps item level 1–170 for each quality to prove it) and
matches what other players' tooltips say.

Consequences worth knowing: a full Tier 6 kit is ~2270, full Tier 4 ~1790,
pre-raid blues ~1380, quest greens ~980. The colour bands are 400 points wide
(TacoTip's TBC bracket), so full T6 reads orange and T4 reads purple.

## D2 — Average item level is printed beside the score, always

The score is a weighted ranking with a formula behind it; the item level is
a plain mean that needs no trust. Rank-1 players compare item level, not
GearScore. Showing both costs eight characters.

## D3 — One quiet inspect at a time, newest wins, and never under the window

The client holds exactly one inspect target, and Blizzard's inspect window
is the other customer for it. Rules, in priority order:

1. Never `NotifyInspect` while `InspectFrame` is shown or has `.unit` set
   (the gap between `InspectFrame_Show` asking and the frame appearing).
2. Never `ClearInspectPlayer` in that state either.
3. One in-flight request; a hover during the 1.5s cooldown is queued, and a
   later hover replaces the queued one — the cursor moved, the old wish is
   moot.
4. A request that gets no `INSPECT_READY` in 5s fails and that GUID backs
   off for 30s. A honor page that does not arrive in 3s keeps the gear and
   drops the arena line until the next hover.

The window's own answers are read too (its `INSPECT_READY` fills the book and
the inspect readout), so opening the window on someone spares their tooltip
an inspect afterwards.

## D4 — Records keep their item links, and complete themselves later

`GetInventoryItemLink` answers only while the player is the inspect target,
but the link it returns is a permanent handle. A piece the item cache had not
seen is stored as its link, `RequestLoadItemDataByID` goes out, and the
record re-scores itself on `GET_ITEM_INFO_RECEIVED` — no second inspect. The
score shows `…` until then rather than a number that leaves a slot out.

## D5 — The readout lives in the top-right of the model viewport

On the TBC paper doll every other margin is taken: the rotate buttons hold
the top-left of the model, the two stat dropdowns overlay its bottom edge,
the attribute panel runs from the model's bottom to 9px above the weapon row,
and the level text and title dropdown fill the strip above. The top-right of
the model is the one clear rectangle, and a humanoid's head sits centred, so
a right-aligned line there covers nothing. The inspect model has the same
buttons, so the same corner is used for symmetry. The readout takes hover
only (`EnableMouseMotion`), so dragging the model still rotates it.

## D6 — Both season shapes are implemented, branched at runtime

`GetCurrentArenaSeasonUsesTeams()` exists on this branch precisely because
the anniversary season is teamless; the teams shape (`GetArenaTeam`,
`GetInspectArenaTeamData`) is kept behind the same branch Blizzard's PvP
frame uses, so a later season with teams costs nothing. In a teams season
the PERSONAL rating is what prints, with the team rating in the breakdown —
personal rating is what gear requirements are checked against.

## D7 — Session memory only

Records live in a session book (10-minute trust, 200 most recent). Nothing
is written to SavedVariables: gear changes between sessions, and the
persistent file on a player is Commander_Dossier's job.

## D8 — Nothing prints for players who cannot be inspected

The other faction, out-of-range players, and creatures get no line at all —
not "unknown", not "?". A line that says nothing is noise on every tooltip.
The one exception is a pending honor page, where the score line is printed
and the arena line simply waits.

## D9 — Combat gate defaults on

A mouseover inspect is a server round trip per new player under the cursor,
and a battleground puts forty of them under it. `InspectInCombat` defaults
off; the tooltip still reads from the book in combat, it just stops adding
to it. The option exists for sizing up a pug mid-pull. It cannot reach an
enemy either way: `CanInspect` refuses hostile units, so arena opponents and
the other faction never print — that is a client rule, not a setting.

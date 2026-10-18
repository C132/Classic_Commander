# Commander_Orders — assumptions to verify in game

Orders passes its headless harnesses (`Harness/README.md`), which prove the
logic against Blizzard's own 2.5.6 UI source and this build's DB2 map rows
and nothing about the live client. Orders 3.0 and its wired consumers HAVE
loaded and run in game: the saved variables carry 3.0's DBVersion and
per-character stores, and eight client sessions after the 3.0 commit recorded
no Lua error (the 3.1 critic, 1.1). The behaviours below are still unproven
one by one. Numbered so a test session can report against them. A1–A13 are
the in-game probes of the 3.0 design review (P1–P14, merged with the client
report's P1–P8); A14–A38 are the builders' open points; A39–A45 came with the
review's fixes (each names the decision it tests); A46–A61 are 3.1's
(2026-10-05, DECISIONS D31–D41), none of them seen in game; A62–A68 came
with the 3.1 review's fixes and the lead's three decisions, also unseen.

**First: restart the client, do not /reload (A61).** 3.1 adds files the
running client has never seen. **Load bearing** marks the
ones that decide whether a feature works at all; the others degrade to a
missing line, a hint or a slightly wrong number.

Most tests are a `/dump` or `/run` in the chat frame. `/corder arrow` prints
what the arrow thinks it is showing, e.g.
`arrow NAV Northshire (Elwynn Forest 48.0, 42.0) (pinned) 582 yd`.

---

## A1 — UnitPosition answers in the open world, on a taxi and as a ghost, and nil in instances (P1)

**Load bearing.** The arrow, the distance, arrival and the minimap pins all
stand on `UnitPosition("player")`; the NO POSITION state assumes it answers
nil inside a dungeon, raid, battleground or arena, and the corpse run assumes
it answers for a ghost.

Symptom if wrong: in the open world the arrow sits on "No position here"; or,
in a dungeon, it points somewhere instead of saying there is no position; or a
ghost gets no corpse arrow.

Test: `/dump UnitPosition("player"), GetPlayerFacing()` in the open world, a
5-man, Karazhan, a battleground, an arena, on a taxi and as a ghost.

## A2 — GetWorldPosFromMapPos answers on Cosmic, Azeroth and the continents as the DB2 says (P2, P3)

**Load bearing for the continent maps.** Projection of pins onto the
continent and Azeroth maps, and ZoneAt for continent clicks, use the
UiMapAssignment rows; the 530 sub-rectangle inside the Eastern Kingdoms map
(the C3 question: which row wins there) decides where Quel'Thalas pins land.

Symptom if wrong: pins on the Eastern Kingdoms map sit in the wrong place for
Eversong and Ghostlands, or a continent click in Quel'Thalas lands in the
wrong zone (ZoneAt refuses rather than guess when the rows disagree, so the
likelier symptom is "Zoom in to place an order" there).

Test: `/dump C_Map.GetWorldPosFromMapPos(946, CreateVector2D(.5,.5))`,
`/dump C_Map.GetWorldPosFromMapPos(947, CreateVector2D(.45,.5))` and
`/dump C_Map.GetWorldPosFromMapPos(1415, CreateVector2D(.55,.15))`; the last
should name instance 530.

## A3 — The world axes pair as Geo pairs them: UnitPosition's north is the vector's x (P4)

**Load bearing.** This is the 2.x defect D1 the whole rebuild started from.

Symptom if wrong: thousands of yards to a waypoint you stand on, an arrow at
90 degrees to the truth, nothing ever arrives.

Test: `/run local n,w=UnitPosition("player") local m=C_Map.GetBestMapForUnit("player") local _,v=C_Map.GetWorldPosFromMapPos(m,C_Map.GetPlayerMapPosition(m,"player")) print(n,w,v:GetXY())`
prints the same two numbers twice (n == v.x, w == v.y). Then `/way 50 50`,
walk onto it: the distance counts down to "Arrived".

## A4 — Texture:SetRotation keeps the art whole at every angle (P5)

Not load bearing: the art is built for either answer (every pixel inside the
inscribed circle, DECISIONS D25). This only says which.

Symptom if wrong: the arrow's tips clip at 45 degrees (it would mean the
generator's margin rule was broken, since a square margin is not enough).

Test: `/run local t=UIParent:CreateTexture() t:SetColorTexture(1,1,1) t:SetSize(200,60) t:SetPoint("CENTER") t:SetRotation(math.pi/4)`
draws a tilted bar if the quad turns; a clamped square if only the texture
coordinates do. Then turn on the spot with a waypoint set: the arrow stays
whole all the way round.

## A5 — Addon messages: the prefix registers and chat is not locked down (P6)

**Load bearing for sharing.**

Symptom if wrong: "Share with group" answers "chat is locked down" or nothing
reaches the other player.

Test: `/dump C_ChatInfo.InChatMessagingLockdown(), C_ChatInfo.RegisterAddonMessagePrefix("CmdrOrders")`
prints `false` and a success; then share a waypoint with a grouped friend
running Orders: they get the "shared a waypoint" dialog.

## A6 — GetUnitSpeed reports ground speed on foot, mounted and swimming (P7)

Not load bearing: it seeds the ETA filter, which then measures closing speed.

Symptom if wrong: the ETA starts wildly off for its first second or two, or
shows on a taxi (it should be blank there).

Test: `/dump GetUnitSpeed("player")` on foot (7), mounted, swimming and on a
taxi; then walk to a waypoint and watch the ETA count down steadily.

## A7 — P8 (ClosestUnitPosition) is not relied on

Nothing in Orders asks for an NPC's position; consumers hand over map
positions from their own data. Listed so a test session does not hunt for it.

## A8 — C_EncounterJournal.GetDungeonEntrancesForMap has data on 2.5.6 (P9)

Not load bearing: it is the last resort after the registered entrance
resolvers (QuestLog's, from Questie's dungeon table: QuestLog A37, Guide A11).
Orders matches an entry to the dungeon by name.

Symptom if wrong: with Questie absent, a dungeon target and a dungeon death
say "No known way there" instead of naming the entrance.

(3.1: it is now the LAST resort, after the resolvers and the shipped door
table, DECISIONS D37; it answers only maps the table lacks.)

Test: `/dump C_EncounterJournal.GetDungeonEntrancesForMap(1944)` and `(1415)`
list entrances with positions; with Questie loaded,
`/dump CommanderOrders.Entrance(347)` names Hellfire Ramparts on map 1944 and
`/dump CommanderOrders.Entrance(350)` Karazhan on map 1430.

## A9 — GetCorpseMapPosition answers on the zone you stand in, and on its continent (P10)

**Load bearing for the corpse run.** Orders asks the map you are on, then each
parent up to the continent, and stores a continent answer on the zone under it.

Symptom if wrong: after a release no corpse arrow appears (or appears only once
you run into the right zone).

Test: die in the open world, release, then
`/dump C_DeathInfo.GetCorpseMapPosition(C_Map.GetBestMapForUnit("player"))` and
the same call on the continent map; die in a dungeon, release, and check that
the arrow points at the entrance ("Your corpse: <dungeon> entrance").

## A10 — The 530 zones project onto the Eastern Kingdoms map the way the DB2 rows say (P11)

Not load bearing: only where a Quel'Thalas pin sits on the continent map.

Symptom if wrong: an Eversong waypoint's pin on the Eastern Kingdoms map sits
away from Eversong's painted outline.

Test: in Eversong,
`/run local n,w,_,i=UnitPosition("player") print(C_Map.GetMapPosFromWorldPos(i,CreateVector2D(n,w),1415))`,
then `/way 50 50 test`, open the Eastern Kingdoms map: the pin sits where the
printed position says.

## A11 — "BATTLEGROUND" is not a valid addon channel (P12)

Orders never sends on it (INSTANCE_CHAT is used in instance groups), so this
only confirms the choice.

Test: in a group, `/dump C_ChatInfo.SendAddonMessage("CmdrOrders","t","BATTLEGROUND")`
prints 4 (InvalidChatType); inside a battleground, a share reaches the raid.

## A12 — GetMapInfoAtPosition names the zone under a continent or Azeroth click (P13)

**Load bearing for continent clicks.** ZoneAt asks it, then insists the zone's
own rectangle on the clicked map contains the click (DECISIONS D13).

Symptom if wrong: Ctrl+Right-click on a continent says "Zoom in to place an
order" where it should drop a waypoint; on Azeroth (947) over Quel'Thalas or
the draenei isles ZoneAt may refuse by design.

Test: `/dump C_Map.GetMapInfoAtPosition(1415,.55,.15)` names 1941 or 1942;
`/dump C_Map.GetMapRectOnMap(1941, 947)`; then Ctrl+Right-click Eversong on the
Eastern Kingdoms map and on Azeroth and see where the waypoint lands.

## A13 — Indoor and outdoor minimap zoom read correctly (P14)

Not load bearing: a wrong guess scales minimap pins by the indoor/outdoor
ratio (about 1.7x).

Symptom if wrong: walking into a building, minimap pins jump in or out
relative to the map art.

Test: indoors and outdoors,
`/dump IsIndoors(), Minimap:GetZoom(), GetCVar("minimapZoom"), GetCVar("minimapInsideZoom")`;
then stand 50 yd from a waypoint and compare its pin with a party member's
dot at the same spot.

## A14 — The minimap diameters are the game's

The table is the community's (HereBeDragons / Questie), not measured on TBC,
except outdoor zoom 3 corrected to 266.67 (DECISIONS D28).

Symptom if wrong: minimap pins sit nearer or farther than the map art at one
zoom level.

Test: stand a measured distance from a waypoint (the arrow's yards) at each
zoom level; the pin should sit where a group member standing on it is drawn.

## A15 — A StaticPopup with button3 and selectCallbackByIndex works on 2.5.6's GameDialog

The share dialog has three buttons: Add (1), Ignore (2), Add and go (3).

Symptom if wrong: "Add and go" does nothing, or adds without taking the arrow,
or the third button is not drawn.

Test: have a friend share a waypoint; press each button once on three shares.

## A16 — CHAT_MSG_ADDON's sender is "Name-Realm" and Ambiguate(sender, "none") is your own name for your own echo

Symptom if wrong: you get a dialog for your own share, or GROUP_AUTO_ADD never
recognises a party member.

Test: share in a party: no dialog appears for you; with "Add from my group",
a party member's share is added without a dialog.

## A17 — MODIFIER_STATE_CHANGED may enable the arrow's mouse in combat

The arrow's hit surface is an unprotected Button; enabling its mouse is legal
in combat.

Symptom if wrong: Shift over the arrow in combat does nothing (or an
ADDON_ACTION_BLOCKED report names CommanderOrdersArrow).

Test: in combat, hold Shift over the arrow and right-click: the menu opens;
release Shift and right-drag the camera across the arrow: the camera turns.

## A18 — The connection spots (Data.CONNECTIONS) are where the boats, zeppelins, portal and orbs are

They are QuestieDB spawn positions of the NPCs and objects at each one, not
field measurements.

Symptom if wrong: "Guide me" pins a spot a few yards off the dock or the
portal.

Test: with a target in Outland from the Eastern Kingdoms, Shift-right-click
the arrow, "Guide me", and follow it to the Dark Portal; repeat for the Undercity
orb (Horde), the Tirisfal and Durotar zeppelin towers, Menethil, Auberdine,
Ratchet and Azuremyst. 3.1's new legs are A57.

## A19 — SendChatMessage SAY needs a hardware event

"As a /way line in /say" is offered only from menu clicks for that reason.
(3.1: the line is ChatText now, sent through C_ChatInfo.SendChatMessage, and a
GoButton's Shift-click is one of the clicks: A55.)

Symptom if wrong: nothing (a blocked call would show as an error).

Test: from the manager, Share -> "As a /way line in /say": the line appears.

## A20 — New textures need a full client restart

Symptom if wrong: none; if the PNGs are added during a running session, the
arrow and pins draw blank (or as the client's missing-texture fill) until the
client restarts.

Test: after installing, restart the client (not /reload) and check the arrow
art.

## A21 — The Minimap and Commander_Radar's overlay share LOW strata, so frame level decides who is on top

Symptom if wrong: radar blips cover waypoint pins.

Test: `/dump Minimap:GetFrameStrata(), CommanderRadarOverlay and CommanderRadarOverlay:GetFrameStrata()`;
then stand near a waypoint with a radar blip on the same spot.

## A22 — A Line region accepts SetColorTexture, SetThickness and SetStartPoint

There is a WHITE8X8 + SetVertexColor fallback, then a latch that turns lines
off for the session after one report.

Symptom if wrong: no lines between route stops (the numbered badges remain),
and one error report.

Test: start a pasted route of three stops in one zone and open the map.

## A23 — The map's canvas does not take a right-click meant for the overlay

The overlay sits three levels above the ScrollContainer.

Symptom if wrong: Ctrl+Right-click on the map zooms out instead of adding a
waypoint.

Test: Ctrl+Right-click a zone map: a waypoint appears and the map stays put.

## A24 — An unanchored 1x1 child of the Minimap gets OnUpdate

The minimap pins' driver is one.

Symptom if wrong: minimap pins appear but never move as you walk.

Test: walk past a waypoint and watch its pin slide across the minimap.

## A25 — The map calls a data provider's OnCanvasScaleChanged

Symptom if wrong: route lines get fatter or thinner as the map zooms.

Test: with a route shown, zoom the map in and out.

## A26 — Questie's map-coordinates option is still `Questie.db.profile.mapCoordinatesEnabled`

Symptom if wrong: two sets of coordinates on the world map, or none.

Test: toggle Questie's map coordinates option; Orders' readout steps aside
while it is on. (3.1: only with World Map Coordinates on Automatic, and only
while the map shows the zone you stand in, outside instances: DECISIONS D39.)

## A27 — AcquirePin wires OnMouseDown and calls pin:OnMouseUp before OnClick (Blizzard_MapCanvas.lua)

Read from the 2.5.6 source and modelled in the mock.

Symptom if wrong: Shift-drag on a world-map pin does nothing, or a drop also
acts as a click on another pin.

Test: Shift-drag a waypoint's pin across a zone map and drop it; then a plain
click on another pin points the arrow at that one only.

## A28 — The manager's multi-line paste box: a scripted OnEnterPressed suppresses the client's newline

The script inserts "\n" itself; Ctrl+Enter imports.

Symptom if wrong: Enter puts two newlines in, or none.

Test: on the Paste tab, type a line, press Enter, type another; Ctrl+Enter adds
them.

## A29 — InputBoxTemplate boxes with SetAutoFocus(false) never take the keyboard on open

Symptom if wrong: opening the manager and pressing W types into a box instead
of walking.

Test: `/corder manager`, then walk with W.

## A30 — UISpecialFrames closes the manager on Escape

Test: open the manager, click nothing, press Escape: it closes.

## A31 — A row's OnDoubleClick arrives after its first OnClick

Test: double-click a waypoint row: it is selected and the arrow points at it.

## A32 — UI-DialogBox-Background-Dark and UI-DialogBox-Header draw as on the Quest Log

Test: open the manager: a dark stone sheet with a header plate reading
"Orders".

## A33 — GameFontNormalLargeOutline exists (or the fallback is used)

DECISIONS D29: if the client lacks it, the distance uses GameFontNormalLarge
with an outline set on it, so nothing breaks either way.

Test: `/dump GameFontNormalLargeOutline ~= nil` and look at the distance line.

## A34 — Questie's dungeon table answers raid maps too (QuestLog A37, Guide A11)

QuestLog's entrance resolver answers any uiMap whose mapType is Dungeon (4),
raids included, from Questie's dungeonLocations (outside positions);
Commander Guide asks `CommanderOrders.Entrance(raidMap)` before its own table.

Symptom if wrong: Guide falls back to its own cited door table (it still works);
a raid death gets no entrance arrow without Questie.

Test: `/dump CommanderOrders.Entrance(350)` names map 1430 (Deadwind Pass).
(3.1: Guide asks `Entrance({ instance = 532 })`, which QuestLog's resolver
does not answer, so Orders' door table does; A58.)

## A35 — A unit follow is a roster token, not a person

*(2026-10-05, 3.1: superseded. Orders now remembers the member's GUID and
re-points the follow after every roster change, DECISIONS D40; A59 is the
test.)*

Orders follows `partyN` / `raidN`; it never re-resolves who that is.
Commander_PartyFrames re-resolves its follow by GUID on every roster change
and removes it when the person leaves; any other caller of kind "unit" would
keep following whoever inherits the token.

Test: follow a party member from the click-cast board, then have someone
else leave the party: the arrow keeps pointing at the same person.

## A36 — Consumer-side field checks that touch Orders

Listed here because the symptom shows on Orders' arrow; each module's own
ASSUMPTIONS has the detail.

- MINIMAP_PING's x, y are fractions of the minimap's width and height, in
  rotated screen space when the minimap rotates (Commander_Ping). Test: a
  party member pings a spot you stand on; Ping's [Go] link (3.1: Orders' own
  link, DECISIONS D38) reads close to 0 yd in its tooltip.
- The chat frame's addon-link click reaches EventRegistry's "SetItemRef"
  callback (Commander_Ping; 3.1: every Orders link, A47). Test: click a ping
  callout's [Go].
- `C_AreaPoiInfo.GetAreaPOIInfo(1461, poi).position` is filled in a live
  Arathi Basin (Commander_Oracle). Test:
  `/dump C_AreaPoiInfo.GetAreaPOIInfo(1461, C_AreaPoiInfo.GetAreaPOIForMap(1461)[1])`.
- UnitPosition works inside Arathi Basin (A1) for the Oracle flag arrow.
- Questie's raid doors are where the portals are (Commander_Guide A10).

## A37 — The /way slash claim made at PLAYER_LOGIN is found by the chat frame

Symptom if wrong: "/way 45 66" prints "Type /help for a list of commands"
with TomTom absent.

Test: with TomTom uninstalled, `/way 45 66 test`, `/wayb`, `/cway`.

## A38 — The shim is what Questie and WhatsTraining find

Symptom if wrong: Questie's "Set TomTom Target" and its Ctrl-click on map
icons do nothing, or WhatsTraining's trainer waypoints are missing.

Test: with TomTom uninstalled, `/dump TomTom and TomTom.isCommanderShim`
prints true; Questie's tracker right-click "Set TomTom Target" puts the
arrow on the quest; `/reload` and remove it from Questie: the Orders waypoint
goes too. Then `/way` the same NPC yourself (same spot, the NPC's name as the
title), target the next objective in Questie: your waypoint stays. Turn
Commander Orders off: `/dump TomTom` prints nil and Questie's "Set TomTom
Target" entries are gone; on again, they are back.

## A39 — A StaticPopup raised to FULLSCREEN_DIALOG in its OnShow draws over the maximized map, edit box and all

DECISIONS D30. Read from the 2.5.6 source (StaticPopup_SetUpPosition sets
DIALOG before OnShow; GameDialogDefs.lua 3218-3221 raises a dialog the same
way) and modelled in the mock; not seen in game. The dialog's level is set
to 3000 too, as Blizzard does, which should carry its children (the edit
box, the buttons) with it.

Symptom if wrong: "Copy /way line" from a world-map pin, or a share arriving
while the map is open, shows nothing until the map closes, and the hidden
copy box keeps the keyboard (pressing M types an "m").

Test: open the map (maximized, the default), right-click a waypoint's pin,
"Copy /way line": the box shows over the map with the line selected; press
Escape, then M closes the map. Have a party member share a waypoint while
your map is open: the dialog shows over it.

## A40 — The arrow's target, alone, draws and takes clicks over Commander_QuestLog's drawer

DECISIONS D15. Both are children of WorldMapFrame (same strata); the arrow's
target goes to max(container + 2200, TOPMOST + 10) + 11, over the formula
the drawer takes its own level from. Every other pin, a running route's
other badges included, stays under the drawer (round 1 lifted the whole
route, and its badges sat on the drawer's quest rows: review-r2 orders).
Accepted, not verified: the lifted target can cover a row or two of the
drawer and take their clicks while the arrow points there.

Symptom if wrong: with Questie loaded and the drawer open, a waypoint in the
east of the map (the Dark Portal's "Guide me" hop at Hellfire 87, 50) is
hidden under the drawer and cannot be clicked; or a running route's later
stops draw on the drawer's quest names; or the target pin on a row is a
nuisance (clicking that row sets the arrow instead of focusing the quest).

Test: Hellfire Peninsula, QuestLog's drawer open, `/way 87 50 Portal`; open
the map: the pin and its ring show over the drawer, its tooltip and
right-click menu work; fold the drawer and open it again: still over it.
Then start a route of four or more stops in the east of Hellfire (the
drawer side): only the current stop's badge shows over the drawer, the
others are hidden under it, and every quest row not under the target pin
focuses its quest on a click, every group header folds. If the target pin
on a row gets in the way, say so: the planned answer is an edge marker on
the drawer's left border (D15).

## A41 — FontString:SetMaxLines exists, and the arrow's status line wraps inside 190 px

DECISIONS D12. Both calls are guarded; without SetMaxLines the line still
wraps (SetWordWrap), only without a cap. Two lines of the small font end
inside the arrow's 158 px frame.

Symptom if wrong: the OTHER-landmass hint runs off both sides of a Dark,
Classic, Solid or Window frame style, or a third line overlaps whatever sits
under the arrow.

Test: `/dump CommanderOrders.R.ArrowState().status.SetMaxLines ~= nil`; then,
with an Alliance character in the Eastern Kingdoms, a waypoint in Eversong
(`/way #1941 50 50`) and arrow style Dark: "via the Thalassian Pass, from the
Eastern Plaguelands" shows on two lines inside the frame.

## A42 — The arrow's default spot (TOP +240, -340) is clear of the toasts and of the character

*(2026-10-04: moved 240 units right of the centre column, because the analysis below shows no centred
spot fits between the toast band and the character; the box now runs x +145..+335 from the centre.)*

DECISIONS D10. Worked out from the anchors in the suite's files and
Blizzard's ZoneText.xml / RaidWarning.xml; UIErrorsFrame's own position is
assumed (TOP -122), not in the source dump. The arrow's box runs 340..498
units from the top: the arrow art 354..438 (the arrow itself 368..424), the
distance, ETA and status lines 438..498. Where that lands on the character
depends on UIParent's height. Devin's Config.wtf sets no uiScale or
useUiScale, and with useUiScale 0 this client scales the UI down by
resolution and DPI on its own, stopping at minimumAutomaticUiScale (the
client's strings say Classic used 0.9): UIParent is likely about 800-853
units high, not 768, and not the 1080-1200 of a hand-set small scale. At
853 (centre 427) the arrow art ends just above the centre, but the text
lines under it cross where the default third-person camera puts the head
and shoulders; at 768 the arrow itself sits 12 units under the centre.
Offline arithmetic only (review-r2 orders): the camera's framing is not
known here. No centred y fits both bands: between the toast band's end
(about 330, Momentum's plate included) and the head (about H / 2) the
centre column has 54-97 units free at H 768-853, and the arrow's box is 158
tall, so a y worked out from UIParent's height (max(340, 0.30 * H) is a
no-op under H 1133) would not help either.

Symptom if wrong: a zone change, a quest progress toast or a raid warning
still draws across the arrow; or the arrow or its distance and ETA lines
cover your character.

Test: at the client's DEFAULT UI scale (Use UI Scale unticked), reset the
arrow's position (Orders page, Reset Position), then: change zones, complete
a quest objective, kill something with Impact's kill text on, and have a
raid leader send a /rw: nothing overlaps the arrow. `/dump
UIParent:GetHeight()` and look at your character at the default camera
zoom: if the arrow or the lines under it cover the head or shoulders, say
so with that height. The answer then is not another centred y: either an x
offset clear of Tracer's +-250 lanes, or the distance and ETA lines beside
the arrow instead of under it, so the 158-unit stack shortens.

## A43 — Commander_Minimap's zone name ends 15 units under the top of its square map

DECISIONS D15. A top-edge chevron rides 22 units under the edge (its 12-unit
art spans 42..54 above the centre of a 140-unit map); the zone name is
GameFontNormal at TOP -2.

Symptom if wrong: a waypoint straight ahead (north, or ahead on a rotating
map) and off the minimap shows its chevron on the zone name's letters, or
visibly low on the rim.

Test: on the square map, `/way` a spot 600 yd due north; the chevron sits
just under "Elwynn Forest" (or any long subzone name), not on it. (3.1: with
Minimap Coordinates on, a label sits under the name and the chevron rides 38
units down, under the label: DECISIONS D39.)

## A44 — Loading through a portal changes C_Map.GetBestMapForUnit before the next 10 Hz pass

DECISIONS D12 (Guide me hands the arrow back when the player reaches
another landmass). The check runs on the first pass that has a position on
the new landmass; inside instances (no position) it waits.

Symptom if wrong: the hop stays pinned after a crossing made away from its
spot, and the arrow says "In the Eastern Kingdoms, via the Dark Portal"
while you stand in Outland.

Test: target a Shattrath spot from the Blasted Lands, Shift-right-click the
arrow, "Guide me", then walk through the portal along its edge (not onto the
NPC spot the hop marks): in Hellfire the hop is gone and the arrow points at
Shattrath. Repeat with a hearthstone to Shattrath and the Outland -> Azeroth
direction (a Shattrath portal).

## A45 — Questie's own waypoint toggle and a claimed waypoint

DECISIONS D17. Verified offline with the real Questie code (review:
questie-shim), not in game: once you re-add a spot Questie targeted, Questie's
Ctrl-click toggle turns its own handle off but leaves your waypoint.

Symptom if wrong: Ctrl-clicking Questie's map icon again removes the /way
you set at the same spot.

Test: Ctrl-click a Questie quest-giver icon on the map (an Orders waypoint
appears), then `/way` the same coordinates with the NPC's name; Ctrl-click
the icon again: the waypoint stays (it is yours now, "Set by you" in its
tooltip).

## A46 — Inside a battleground the map position answers, whatever UnitPosition does (critic 5.1; D34)

**Load bearing for Oracle's Go-tos.** The arrow's battleground hedge derives
your world position from `C_Map.GetPlayerMapPosition` when `UnitPosition`
answers nothing in a "pvp" instance. This settles A1 for battlegrounds.

Symptom if wrong: in Arathi Basin an Oracle pip's waypoint says "No position
here", or the arrow points but the coordinate block reads "--".

Test: inside Arathi Basin, `/dump UnitPosition("player")` and
`/dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"),"player")`;
then click a flag pip on Oracle's board: the arrow points at the flag and
the yards count down as you run. In Warsong Gulch, `/coracle flag` with an
enemy carrying your flag points at the carrier and follows them about once a
second (A60).

## A47 — An Orders chat link clicks and hovers (critic 5.2-5.3; D38)

**Load bearing for chat links.** Read in the 2.5.6 source and modelled in
the mock: the click reaches EventRegistry "SetItemRef" through SetItemRef
and LinkUtil's "addon" handler; hover reaches EventRegistry
"ChatFrame.OnHyperlinkEnter" / "OnHyperlinkLeave".

Symptom if wrong: clicking a [Go] does nothing, or an error names
LinkUtil; no tooltip on hover; a line shows twice or loses its sender link.

Test: have a party member post `/way Hellfire Peninsula 45 66 test`. The
line keeps the sender's name link, shows once in each chat window, and has a
[Go] after it. Hover the [Go]: a tooltip with the title, "Hellfire Peninsula
45.0, 66.0", the distance or the landmass, and the four hints. Then click it
plain (a waypoint, the arrow on it, "Waypoint set: test (...)"), with Shift
and the chat box open (the readable line is typed into the box), with Shift
and the box closed (the line is posted to the party), with Ctrl (the copy box
with the /way line) and with the right button (the menu). No Lua error. Ping's
callout and a refused Go's printed line carry the same link (A36).

## A48 — General is zoneChannelID 1 and LocalDefense 22 (D38)

ASSUMED from the classic ChatChannels data, not read on this build. A bare
`/way 45 66` there is read on your own map.

Symptom if wrong: a bare `/way 45 66` in General gets no [Go] (the safe
failure: no link rather than a wrong one).

Test: in General, have someone type `/way 45 66 here`: it gets a [Go] that
points into your zone. In Trade or LookingForGroup it gets none.

## A49 — Blizzard's formatting after the filters leaves the link's payload whole (D38)

Simulated in the chat harness from the 2.5.6 source: % doubled for format,
{...} rewritten into icons (C_ChatInfo.ReplaceIconAndGroupExpressions),
runs of spaces collapsed.

Symptom if wrong: a [Go] that points at the wrong spot, or a click that does
nothing.

Test: in a party, `/p /way #1944 45 66 {star} 50% off` and click the [Go]:
the waypoint is at Hellfire Peninsula 45.0, 66.0, titled from the line.

## A50 — Ctrl+Right-click on the minimap makes a waypoint and pings nobody (critic 5.4; D39)

**Load bearing for the minimap gesture.** Commander_Minimap wraps the
minimap's OnMouseUp with SetScript, keeping the handler it found
(Minimap_OnClick by name if none). The placement is worked out from
GetCursorPosition, the minimap's effective scale and centre, as
Minimap_OnClick does, inverted through Geo.MinimapPlace.

Symptom if wrong: a ping reaches your group (and Commander_Ping makes a
second waypoint) along with ours; the waypoint lands off the spot you
clicked; the square map's corners do nothing; any other click stops pinging.

One more risk: SetScript replaces the handler and, if the client drops
HookScript hooks with it, an addon that hooked the minimap's OnMouseUp
before Commander_Minimap loaded would stop hearing clicks.

Test: `/dump Minimap:GetScript("OnMouseUp")` names a function. In a group,
Ctrl+Right-click a spot on the minimap: one waypoint there, the arrow on it,
and no ping on anyone's minimap. Repeat at zoom 0 and 5, with Rotate Minimap
on and off, in a square map's corner, and past the edge of the zone (it lands
in the zone beside it). A plain left click still pings.

## A51 — The copy box takes a 255-letter line (critic 5.5; D40)

2.5.6's pooled dialog edit box keeps the last dialog's letter limit unless a
dialog names its own; Orders' names 255.

Symptom if wrong: "Copy /way line" after another dialog shows the line cut
at 24 or 40 letters.

Test: open the Talents "Save build" dialog (or any dialog with a short name
box), close it, then "Copy /way line" on a waypoint with a long title: the
whole line is in the box, under "Ctrl+C to copy".

## A52 — UnitPosition keeps answering on taxis, boats and zeppelins (critic 5.6; D39)

The coordinate block reads every 0.2 s whatever you do; a movement event
would not fire on a taxi.

Symptom if wrong: the block's numbers freeze for a flight, or read "--".

Test: show the coordinate block (`/corder coords on`: off by default since
the 3.1 review), take a taxi and a boat: the numbers move all the way, and so
do the minimap's.

## A53 — A zone map is linear in world coordinates, and the zone texts answer (D39)

The block turns UnitPosition into map numbers through each map's world
rectangle, read once from two GetWorldPosFromMapPos probes. Since the 3.1
review the runtime leans on the same fact the other way: every place's world
position on a zone, dungeon, micro or orphan map (mapType 3 and up) is the
map's two probes plus arithmetic (`WorldOf`), for "nearest" lists, the
arrow and the pins alike (every UiMapAssignment row of such a map in build
69795 shares one transform; checked over the whole DB2). GetZoneText /
GetSubZoneText name the place lines.

Symptom if wrong: the block's numbers drift from the world map's own player
position toward one edge of a zone; the place lines are empty or wrong inside
an instance or a city.

Test: stand anywhere and compare the block with the world map's coordinates
(Orders' readout, World Map Coordinates on Always): the same to the tenth,
at the middle and near every edge of a zone. Walk into a cave (a micro map):
the block keeps the zone's numbers. Enter a dungeon: "--", with the dungeon's
name under it. And: `/way` a spot near a zone's edge, and the arrow's distance
on arrival is a few yards, not tens.

## A54 — ChatFrameUtil.GetActiveWindow and ChatFrameUtil.InsertLink exist on 2.5.6 (D31, D38, D39)

Blizzard's own Classic code calls both. A Shift-click on the block, the
minimap label, the TopBar's coordinates or a [Go] types the readable line
into an open chat box.

Symptom if wrong: with the chat box open, Shift-click posts the line instead
of typing it.

Test: open the chat box, Shift-click the minimap's coordinates: "Elwynn Forest
42.0, 65.5 (/way #1429 42.00 65.50)" (or your spot) appears in the box,
unsent.

## A55 — C_ChatInfo.SendChatMessage to SAY from a click is allowed outdoors (D40, D31)

A GoButton's Shift-click when you are alone, "Post in chat" on a link's
menu, and the manager's "/say" share all post to SAY from a click (a
hardware event).

Symptom if wrong: nothing is said, or a blocked-action report names
SendChatMessage.

Test: alone in the open world, Shift-click any Go button (the Guide's "Go to
Entrance", the Quest Log's "Go to Turn-in"): the readable line appears in
/say. In a party it goes to /party.

## A56 — Two shared waypoints show two dialogs (D40)

`multiple = true` on COMMANDER_ORDERS_SHARE; StaticPopup_FindVisible
would otherwise cancel the first.

Symptom if wrong: the first share's dialog vanishes when the second arrives.

Test: have two party members share a waypoint at the same moment (or one
share twice quickly): two dialogs, each with its own place, each button
acting on its own share.

## A57 — 3.1's connection spots are where the boats, zeppelins and fliers leave (D40)

QuestieDB spawn positions: Grom'gol's zeppelin master (npc 3149, Stranglethorn
31.4, 29.9), the boat to Teldrassil (object 176365, Darkshore 32.7, 41.8),
Rut'theran's hippogryph master (npc 3838, Teldrassil 58.4, 94.0), and
Theramore's pier (npc 12716, Dustwallow 71.3, 56.3, INFERRED to be the dock).

Symptom if wrong: "Guide me" pins a spot off the dock or the tower; the
arrow points across the sea at Teldrassil.

Test: Horde in Stranglethorn with a target in Kalimdor: "Guide me" leads to
the Grom'gol tower. Alliance in Dustwallow with a target in the Eastern
Kingdoms: it leads to the Theramore pier where the Menethil boat docks (say
if the spot is off the dock). Alliance in Darkshore with a target in
Darnassus: the arrow says "In Teldrassil, via the boat to Teldrassil at
Auberdine" instead of pointing west across the water; from Darnassus back, it
names Rut'theran's hippogryph master.

## A58 — The locator in game (D36, D37)

Verified offline against the real Questie 12.0.3 / QuestieDB 1.0.4 booted
under luajit, never in the client.

Symptom if wrong: a Go button for a "nearest" query says "Questie is still
loading" for the whole session, picks a far spawn, or the client hitches
after login.

Tests:
- Horde in Shattrath, a button or `/run CommanderOrders.GoTo({ townsfolk = "Innkeeper" })`:
  the arrow points at the nearest innkeeper; no Lua error.
- After login, when Questie says it is ready, the pre-warm (eight lists, one
  per 0.1 s) causes no visible hitch.
- With Commander_QuestLog disabled, `/way #347 50 50` (inside Hellfire
  Ramparts) from Hellfire Peninsula: the arrow says "via the entrance of
  Hellfire Ramparts".
- `/run CommanderOrders.GoTo({ entrance = { instance = 269 } })`: the arrow
  leads to the Caverns of Time's mouth in Tanaris, not into the rock.
- `/run local t=debugprofilestop(); NpcDB.BuildNameIndex(); print(debugprofilestop()-t)`
  (Questie's name index, which a name query builds once): say how long.

## A59 — A followed member stays followed through a roster change (D40, replaces A35)

Orders keeps each follow's GUID and re-points it after GROUP_ROSTER_UPDATE.

Symptom if wrong: after someone leaves or joins, the arrow follows whoever
inherited the token.

Test: follow a party member (Contacts' "Arrow To Them", PartyFrames' "Arrow
to My Target" binding or `/cpf arrow`), then have someone ABOVE them in the
party leave: the arrow keeps pointing at the same person, and it does not
clear when you reach them.

## A60 — The consumers' field checks (D31, the coverage table)

Each module's own ASSUMPTIONS or Harness README has the detail; listed here
because the symptom shows on Orders' arrow or in Orders' words.

- Quest Log A61 (objective Go in Questie's order), A62 (QUEST_REMOVED on an
  abandon, QUEST_TURNED_IN on a turn-in, after a /reload with the quest's Go
  pinned: the waypoint goes), A63 (Go to Turn-in fits the Log's bar).
- Guide A12: from south Deadwind, "Go to Entrance" says "Waypoint set" once
  and points at the nearer Karazhan door; Shift-click shares the readable line.
- Recovery: die, release, click the [Go] on the death line: a "Where you
  fell" waypoint.
- TopBar: click, Shift-click, Ctrl-click and right-click the coordinates; click
  the durability, bags and ammo readouts (nearest repair, vendor, ammo vendor).
- Logistics: open a repair vendor with Questie on, then `/dump
  CommanderLogisticsDB.RepairVendors`: the record has `spawn = true` and the
  NPC's own coordinates.
- Adjutant: fill your bags out of combat: the banner names a vendor and a
  quiet waypoint appears, gone at the first merchant.
- Quartermaster: Ctrl+Right-click a flask row: the arrow to the nearest
  auctioneer (from Outland, Kalimdor or the Eastern Kingdoms: no Outland AH).
- Tradecraft A17 and Formulary A10: their Go buttons behave as D31 says.
- Oracle: in Warsong Gulch, `/coracle flag` with an enemy carrying your flag;
  `/dump GetNumBattlefieldFlagPositions(), GetBattlefieldFlagPosition(1)`
  (the call 2.5.6's own BattlefieldFlagDataProvider makes; the third return
  is the flag ART, expected as a fileID number that Oracle matches against
  GetFileIDFromPath of the AllianceFlag / HordeFlag textures; if it matches
  neither, Oracle lists "Flag 1 / Flag 2" with a [Go] each instead of
  guessing the carrier). In Alterac Valley and the Eye, `/coracle nodes` lists the
  map's places, each with a [Go].
- Key Bindings: "Commander Party Frames > Arrow to My Target" and "Commander
  Oracle > Go to the Flag" exist (new Bindings.xml files: A61).
- Contacts A14: hover a [Go] in a logged line: Orders' tooltip.
- Promotion: level up below 70: the banner names the nearest class trainer, a
  quiet waypoint appears out of combat, opening a class trainer removes it, a
  profession trainer does not.
- Objectives (Turn-in Offer is off by default): switched on, a quest turning
  complete marks its finisher.
- Vault: with your own vault shown away from the bank, "Go to Bank" sits on
  the footer line above the bag rack, clear of it, in both frame styles.
  Armory: "Go to Bank" in the set pane's bottom right when a set's item is
  banked.

## A61 — Restart the client, not /reload, after installing 3.1 (critic 5.7, 1.2)

**Load bearing for everything 3.1 adds.** The client only loads files it
saw at start-up; a TOC naming a file it does not know logs "Error loading
<file>" (seen in BugGrabber for Pins and UI in session 615). New this round:
Commander_Orders/CommanderOrdersEntrances.lua, CommanderOrdersLocate.lua,
CommanderOrdersCoords.lua, CommanderOrdersChat.lua;
Commander_Events/CommanderGoButton.lua; Commander_Oracle/Bindings.xml;
Commander_PartyFrames/Bindings.xml.

Symptom if wrong (a /reload instead): "Error loading" warnings; no coordinate
block, no [Go] links, every "nearest" Go says Commander Orders is still
loading; the modules' Go buttons fall back to plain buttons (they still call
GoTo); `/corder coords` says the block is not loaded.

Test: quit the game completely, start it, log in: no "Error loading" line in
BugSack; the minimap shows your coordinates under its zone name (the
coordinate block is off by default: `/corder coords on` shows it under the
arrow's spot); `/dump
CommanderOrders.Coords ~= nil, CommanderOrders.Linkify ~= nil,
Commander.UI.GoButton ~= nil` prints true three times.

## A62 — "Open the map here" opens the TBC world map on the link's zone (D38)

2.5.6's `OpenWorldMap(mapID)` calls `WorldMapFrame:HandleUserActionOpenSelf`,
a method only the Wrath files define (Blizzard_WorldMap_TBC.toc does not load
QuestLogOwnerMixin), so it raised every time. The menu entry now opens the
map the player's way, `ToggleWorldMap()` when it is shut (it keeps the
mini-map setting), then `WorldMapFrame:SetMapID(map)`, as Commander_QuestLog's
"Show on map" does.

Symptom if wrong: BugSack catches an error from CommanderOrdersChat.lua, or
the map opens on your own zone, or the windowed map comes up when you use the
full one.

Test: right-click a [Go] in chat (`/way Hellfire Peninsula 45 66 Test`), pick
"Open the map here": the map opens on Hellfire Peninsula, no error. With the
map already open on another zone, do it again: the map moves, and stays open.

## A63 — A greyed Go button shows its reason when you hover it (D31)

2.5.6 gives a disabled Button no OnEnter (and no OnClick) unless
SetMotionScriptsWhileDisabled(true); every Go button now sets it. An enabled
query button whose lookup answers nothing (Questie loading or absent, none
on your landmass) says Orders' reason in the same red line. Greyed by
Orders' own state (turned off, loading, or absent for a lookup) the button
leaves out its module's extra line, which says what a press does
(review-r2: the Quest Log's, Formulary's, Tradecraft's and Guide's promised
a press a greyed button never gets).

Symptom if wrong: hovering a grey Go shows nothing at all.

Test: `/corder` off (Enable off), hover the Quest Log's "Go to Turn-in": the
tooltip names the button and says "Commander Orders is turned off (/corder)"
in red, with no line about what a press does; clicking it does nothing. Inside Karazhan hover the Raid Guide's "Go
to Entrance": "You are already inside". Within a few seconds of logging in
(Questie still loading) hover Armory's or Vault's "Go to Bank": "Questie is
still loading" in red, no "Go to:" line.

## A64 — "Nearest" from inside an instance is measured from its door (D32)

Inside a dungeon or raid UnitPosition answers nil, so a "nearest" list had
no reference point and was cut to 256 in Questie's order; it named Questie's
first entry wherever you were. Now the instance's door (the door table)
stands in for you, the list is sorted from it before the cap, and its
landmass decides.

Symptom if wrong: inside a raid, Vitals' worn-slot line or the TopBar's
durability tooltip names Corina Steele (Elwynn Forest) for an Alliance
player, or Grimnal (Swamp of Sorrows) for a Horde one.

Magisters' Terrace has no uiMap at all on 2.5.6 (build 69795: no UiMap row,
no UiMapAssignment row for instance 585), so GetBestMapForUnit should answer
nil in there and the door cannot be found from the map. The instance's own
id, the 8th value of GetInstanceInfo (as 2.5.6's AdventureGuideUtil.lua and
Questie read it), finds it instead, for "nearest" and for a death in there
(review-r2).

Symptom if wrong: inside Magisters' Terrace "Go to Repair" (TopBar
durability, Bags) sends an Alliance player to the smith in Goldshire ("In the
Eastern Kingdoms..."), or a ghost who died in there gets no corpse arrow.

Test: Alliance inside Serpentshrine Cavern with worn gear: the durability
tooltip names Mortog Steamhead (Zangarmarsh 51.5, 35.4); click the TopBar's
durability, walk out of the portal: the arrow points about 100 yd to him.
Inside Magisters' Terrace: `/dump C_Map.GetBestMapForUnit("player"),
select(8, GetInstanceInfo())` answers nil, 585 (if it answers a map, the
old path already works and this is moot); the durability tooltip names
Smith Hauthaa (Isle of Quel'Danas 50.6, 40.8); click it, walk out: the arrow
points about 420 yd to him. Die in there and release: the arrow points at
the entrance (61.5, 31.1, "Your corpse: Magisters' Terrace entrance"), or
at the corpse marker the client gives on the Isle's map.
Then, level 58-69 in Outland, ding: Promotion's banner has no trainer line
(none on your landmass, "elsewhere"), and Quartermaster's "nearest
auctioneer" from Shattrath still sets a waypoint whose arrow names the way
to another continent.

## A65 — The coordinate block, turned on, clears the quest tracker (D39)

The block is off by default (the lead's decision). Turned on it sits under
the Orders arrow's default box (TOP +240, -504), out of the right column
from 192 down where 2.5.6 manages the quest tracker (QuestWatchFrame,
right-aligned, up to about 290 wide).

Symptom if wrong: the block draws over the tracker's lines, or over the
arrow, or under the action bars at your UI scale.

Test: track a quest; `/corder coords on`; the block and the tracker must not
overlap; set a waypoint: the block and the arrow must not overlap either.
Check at your own UI scale, with the right action bars shown and hidden.

## A66 — A "Guide me" hop survives a /reload with its target (D33)

The hop records its target (`guideFor`); the Store keeps that record beside
the pinned hop, and the runtime restores the link at login.

Symptom if wrong: after a /reload and a crossing made off the hop's spot (a
hearthstone, a portal, the other boat), the arrow points back across the
crossing ("In the Eastern Kingdoms via the Dark Portal in Hellfire
Peninsula").

Test: in the Blasted Lands, point at something in Hellfire Peninsula, use
"Guide me", `/reload`, then take the portal through Shattrath or hearth to
the other side: the arrow is back on the target. Once more with the target
from a module (a Quest Log Go): it is still there after the reload.

## A67 — Follow the Closest in a capital sees the zone around it (D35)

ClosestScope "My zone" folds each capital into its zone (Stormwind City into
Elwynn, Orgrimmar into Durotar, Shattrath into Terokkar...), only for that
scope: the coordinate block and the chat links keep the city's own numbers.

Symptom if wrong: in Stormwind, `/cway` says "no waypoint in this zone" for a
mark just outside the gate.

Test: in Stormwind City, mark a spot in Elwynn just outside the gate
(`/way Elwynn Forest 32 49 Gate`), clear the arrow, `/cway`: it picks the
gate mark. In Elwynn, a mark in the Trade District: the same.

## A68 — The nearest bank from Auberdine is Darnassus, one boat away (D40)

Teldrassil is its own landmass (D40's islands), so Darnassus' banks were
left out of "nearest" lists from Darkshore and the arrow sent you through
Felwood to Everlook. A place on an island of the same continent frame now
counts, measured in a straight line; when it wins, the waypoint's choices
are the island's alone and the arrow names the boat.

Symptom if wrong: from Auberdine "Go to Bank" points at Everlook (Winterspring,
about 5,200 yd).

Test: Alliance in Auberdine, Armory's or Vault's "Go to Bank": the tooltip
names a Darnassus banker; the arrow says "In Teldrassil" and "via the boat to
Teldrassil at Auberdine"; across the water it points at the bank.

---

Not relied on, so not listed above: `IsFlying` (no "you are above it" hint
yet), `C_Map.SetUserWaypoint` (absent on this client), `ClosestUnitPosition`
(A7), CORPSE_IN_RANGE (arrival is by distance, DECISIONS D24).

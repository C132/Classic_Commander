# Commander_Orders — assumptions to verify in game

Orders 3.0 passes six headless harnesses (`Harness/README.md`), which prove
the logic against Blizzard's own 2.5.6 UI source and this build's DB2 map rows
and nothing about the live client. Nothing below has been run in game yet.
Numbered so a test session can report against them. A1–A13 are the in-game
probes of the 3.0 design review (P1–P14, merged with the client report's
P1–P8); A14–A38 are the builders' open points; A39–A45 came with the
review's fixes (each names the decision it tests). **Load bearing** marks the
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
Ratchet and Azuremyst.

## A19 — SendChatMessage SAY needs a hardware event

"As a /way line in /say" is offered only from menu clicks for that reason.

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
while it is on.

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

## A35 — A unit follow is a roster token, not a person

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
  party member pings a spot you stand on; Ping's [Waypoint] link reads close
  to 0 yd.
- The chat frame's addon-link click reaches EventRegistry's "SetItemRef"
  callback (Commander_Ping). Test: click a ping callout's [Waypoint].
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
just under "Elwynn Forest" (or any long subzone name), not on it.

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

---

Not relied on, so not listed above: `IsFlying` (no "you are above it" hint
yet), `C_Map.SetUserWaypoint` (absent on this client), `ClosestUnitPosition`
(A7), CORPSE_IN_RANGE (arrival is by distance, DECISIONS D24).

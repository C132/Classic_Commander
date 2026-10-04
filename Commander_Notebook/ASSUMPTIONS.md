# Commander_Notebook — assumptions to verify in game

Everything here passes the three headless harnesses, which prove the logic and nothing about the
live client. Numbered so a test session can report against them. A1–A3 decide whether the module
works at all; the rest degrade gracefully.

---

## A1 — A multi-line `EditBox` used as a `ScrollChild` sizes its own height to its text

**Load bearing.** The writing area is an `EditBox` with `SetMultiLine(true)` inside a
`UIPanelScrollFrameTemplate`, and its height is deliberately never set — only its width, which is
pinned to the scroll frame on every resize.

This is not a guess. Two shipped modules in this suite already do exactly this against this client:
`Commander_Debug`'s error-report window and the Quartermaster's shopping-list window. Both set the
width, neither sets the height, and both scroll correctly. The pattern is copied rather than
reinvented for that reason.

Symptom if it is wrong: the note text lays out on one endless line, or the scrollbar never appears.

Test: open a note, paste or type more than a screenful, and confirm the scrollbar appears and the
mouse wheel moves the text.

## A2 — `OnCursorChanged` reports a usable cursor offset, and the view follows the caret

**Load bearing for long notes.** Typing past the bottom of the visible area has to scroll the view.
Blizzard's own `ScrollingEdit_OnCursorChanged` exists for this, but it is a FrameXML global whose
presence on this client is not provable from the files this module can see, so the arithmetic is
done here instead: `OnCursorChanged` hands over the cursor's y offset and height, and the scroll
frame is moved just far enough to keep it in view.

Symptom if the arguments differ: typing at the bottom of a long note leaves the caret off screen.
The note is still saved correctly — this is a view bug, not a data bug.

Test: type thirty lines into one note without touching the mouse and confirm the view follows.

## A3 — Wrapping `ChatEdit_InsertLink` catches shift-clicks into our edit boxes

**Load bearing for the headline feature.** The client routes shift-clicked item, spell and quest
links through this function. The module replaces it with a wrapper that claims the link when one of
its own boxes has focus and calls the original otherwise.

The wrapper is plain-function replacement, not `hooksecurefunc`, because the original's *return
value* decides whether the client considers the click handled and a hook cannot change that.
`ChatEdit_InsertLink` is not a protected function, and this is the standard addon path, but it is
still a global replacement and worth confirming once.

Symptom if it is wrong: shift-clicking an item with the cursor in a note either does nothing or puts
the link in the chat box instead.

Test: open a note, click into the writing area, shift-click an item in your bags. The link should
appear in the note, coloured, and the chat box should stay empty. Then click out of the note and
shift-click again — that one *should* go to chat.

## A4 — `StaticPopupDialogs` edit-box access

**Degrades to a refusal, not an error.** Naming and renaming a notebook uses a `StaticPopup` with
`hasEditBox = true`. The dialog's edit box is reached as `self.editBox`, with a fallback to
`self:GetEditBox()` — the accessor changed between client generations and only one of the two is
guaranteed here.

Symptom if both are wrong: "New Notebook" opens a dialog that creates a notebook called nothing,
which the store refuses with a printed message. No data is at risk.

Test: New Notebook, type a name, press Enter. Then do it again and press the Create button instead —
both paths are wired separately.

## A5 — `C_Map.GetBestMapForUnit` / `GetPlayerMapPosition` on this client

**Costs one field.** The Stamp button writes who you are, where you are standing and the time. The
coordinates come from `C_Map`, guarded by an existence check on both functions and on the returned
position object's `GetXY`.

Symptom if absent: the stamp still names the zone, the subzone, the target and the time, and simply
omits the numbers.

Test: `/dump C_Map.GetBestMapForUnit("player")` in the open world, then press Stamp in a note and
read the line it writes.

## A6 — `FontString:SetWordWrap`

**Cosmetic, guarded.** Row titles, snippets and tag lines are single-line and are told not to wrap.
`SetWordWrap` is not used anywhere else in this suite, so every call goes through a guard: a client
without it gets a wrapping label rather than an error.

Symptom if absent: long titles in the note list wrap to a second line and overflow their row.

## A7 — `SOUNDKIT.IG_QUEST_LOG_OPEN` is the right click for quick capture

**Cosmetic.** The capture sound is played through `pcall`, with a numeric fallback id, so a wrong or
missing key costs silence and nothing else.

Test: `/cnb testing` with Capture Sound on.

## A8 — Nothing here is protected, so none of it breaks in combat

**Believed safe by construction, worth confirming once.** There is no secure frame, no
`SecureActionButton`, no protected API call anywhere in this module — it is text in a window. The
quick-capture path in particular is meant to be usable mid-fight.

Test: `/cnb mid fight note` while in combat, then open the notebook afterwards and confirm the line
landed.

## A9 — The map `GetBestMapForUnit` names is the one a waypoint should go on

**Costs a waypoint's accuracy, never a note.** The context keeps the uiMapID `GetBestMapForUnit`
returned alongside the coordinates `GetPlayerMapPosition` gave on that same map, and Go hands
exactly that pair to Commander Orders. If the client ever answered with a map whose coordinates do
not match (a micro map inside a zone, say), the arrow would point at the wrong spot on the right
map. Old text-only stamps are resolved by zone NAME through Orders' `/way` resolver, which assumes
`GetRealZoneText()` (what the stamp line says) is a zone name Orders knows; a subzone-level map
whose real zone name differs would resolve to the wrong zone or to none, and the note says so in
chat rather than guessing.

Test: stamp a note in Goldshire and another in Stormwind City, walk away from each, press Go, and
check the arrow's distance closes to zero at the spot. For an old stamp, write a line by hand such
as `-- Me | Goldshire, Elwynn Forest 42.0, 65.5 | today` and press Go.


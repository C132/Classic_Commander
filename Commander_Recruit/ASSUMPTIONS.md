# Commander_Recruit — assumptions to verify in game

The harnesses prove the logic under a mock. Devin's first in-game screenshot (2026-10-17)
settled some of it: the window loads and lays out cleanly after 1.4.1 (he confirmed), the
board filled (307 seen, 25 rated across the three brackets), and the sweep button read
"Sweep 12/18" — so presses sent /who (A1) and capped classes were split by race (A4).

- **A1 — CONFIRMED 2026-10-17 (the sweep reached 12 of 18). A click or a key binding counts as the hardware event SendWho needs.** From the API
  docs (`HasRestrictions = true`). Test: press Sweep; a /who answer should arrive and the
  button should count 1/9.
- **A2 — `SetWhoToUi(true)` sends the answer to the Who list silently.** If the Who window pops
  anyway, R2 shuts it; if a page of /who lines lands in chat instead, A2 is wrong.
- **A3 — Five seconds is enough between two /who queries.** If answers stop coming, the gap
  (`WHO_GAP`) is too short.
- **A4 — CONFIRMED 2026-10-17 (9 class queries grew to 18). A capped answer reports `total > shown` or exactly 50 shown.** Read from
  `C_FriendList.GetNumWhoResults()`; either triggers the race split.
- **A5 — `GetWhoInfo` fields are `fullName`, `level`, `filename`, `area`, `fullGuildName`.**
  Confirmed by the branch's own API docs (`WhoInfo`, FriendListDocumentation.lua).
- **A6 — /who covers which realms?** Dreamscythe and Nightslayer players meet in the group
  finder; whether /who on one returns the other is not known. The board takes whatever comes.
- **A7 — Chat events carry the sender at arg 2 and the GUID at arg 12** (the standard order).
- **A8 — `GetGuildRosterInfo` returns online at 9 and the class file name at 11.**
- **A9 — The group finder only lists your own faction.** If it lists both, the other
  faction's players appear on the board (they are only ever whispered or invited, which the
  server refuses across factions).
- **A10 — The eye's click is the hardware event `AddFriend` needs**, as for SendWho.
- **A11 — `RemoveFriend` accepts the name exactly as `GetFriendInfoByIndex` shows it**
  (bare for your realm). Recruit removes by that spelling (R6).
- **A12 — SETTLED 2026-10-17 by Devin: a player on the other realm cannot be friended** (his
  Dreamscythe character cannot friend Nightslayer players), and he wants only his realm. The
  probe already walks only our realm; the watch dot is gone from other-realm rows (R11).
- **A13 — `FriendInfo.notes` comes back with the note Recruit set**, so a rewritten note can be
  told apart (R6). If notes never come back, nobody is ever re-classed as yours, which is safe.
- **A14 — `FriendsFrame.CloseButton` exists (ButtonFrameTemplate's parentKey)** and the title
  bar has room left of it: the title text is 250 wide and centred. If the icon overlaps the
  title or sits off the bar, re-anchor it (R7).
- **A15 — The friends list arrives after AddFriend with the new friend's online flag**, so one
  FRIENDLIST_UPDATE answers a probe. If it takes longer than six seconds, probes time out and
  are cleaned up late (R8): raise PROBE_TIMEOUT.
- **A16 — The server takes a friend add a second.** If adds start failing in a row, the probe
  says so after three; PROBE_GAP is the knob.
- **A17 — Adding someone as a friend does not notify them** (it never has in WoW).
- **A18 — `C_FriendList.GetNumFriends()` answers from the client's copy of the list as soon as
  the login burst has arrived**, which is what lets the probe start without waiting for a
  fresh FRIENDLIST_UPDATE (1.3.1).
- **A19 — `FriendInfo.notes` is the note AddFriend set.** Automatic removal depends on it now
  (exact match). If it never comes back, every probe friend is left on the list and named in
  chat, and Clean Up Probes is the way to take them off — safe, but not quiet.
- **A20 — The friends system's answers to an add arrive as CHAT_MSG_SYSTEM or UI_ERROR_MESSAGE
  text equal to `ERR_FRIEND_NOT_FOUND` / `ERR_FRIEND_LIST_FULL` / `ERR_FRIEND_ALREADY_S`**
  (English fallbacks "Player not found.", "Your friends list is full.", "%s is already your
  friend."). Devin saw "player not found" on screen; if the probe still waits six seconds after
  one, the words arrive some other way.
- **A21 — A /who with no matches may send no WHO_LIST_UPDATE.** Either way the sweep now moves
  on after eight seconds, counting the query as unanswered (R13).

- **A22 — Unknown: how many restricted AddFriend calls one key press allows** (1.7.0, R15).
  Recruit tries the batch and watches for ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN
  (args: addon name, function name) and for adds that never answer. If the game allows only one
  and refuses without either sign, the drop rule (one answer from several adds, twice running)
  catches it within two presses.
- **A23 — The friends system says "%s added to friends." / "%s removed from friends."
  (`ERR_FRIEND_ADDED_S` / `ERR_FRIEND_REMOVED_S`) as CHAT_MSG_SYSTEM**, the name plain or as a
  player link; Quiet Probe Chat hides those for probe names only. If they arrive some other way,
  the lines simply still print.
- **A24 — CONFIRMED in game 2026-10-17: a friend just added can be listed with `name = ""`**,
  level 0, className and area "Unknown", the GUID and notes already set, until the server fills
  it in (R16). Whether a fresh FRIENDLIST_UPDATE follows the fill-in is not known, so Recruit
  re-reads the list each second while any row is blank.
- **A25 — A rating can be five minutes stale on the board** (R18): a player Muster rates
  differently mid-session shows the new number within five minutes, an unrated one within one.
- **A26 — Unknown: whether /who lists a player in an arena match with the arena as their zone**
  (R20). If it does, `70-70 z-"Arena"` finds rated players mid-match; if it shows nothing (or their
  last zone), the arena's estimate (10 to start) halves with each empty answer, every three minutes
  at most, and after four it is only tried every 15 minutes, last. Test: queue a skirmish with a friend watching, or press Sweep at peak and
  see whether the first query (arena matches) puts anyone on the board.
- **A27 — `z-` and `g-` match a part of the name, like `n-`.** So `z-"Arena"` is both Nagrand Arena
  and Blade's Edge Arena, and `g-"Lions"` would also list "Lions Den". If `z-` needs the whole zone
  name, the arena query finds nobody (A26's fade handles it) and two named queries should replace
  it. The zone names are English (arenas have no UiMap to localize them from).
- **A28 — A guild query lists only level 70s with `70-70` in front**, so a big guild's lowbies do
  not crowd its answer past 50.
- **A29 — Unknown: whether a capped /who returns the same 50 every time.** The steered sweep never
  repeats a query inside a sweep, so either way it does not matter within one; the Bayes discount
  assumes the 50 are not biased toward or against rated players.
- **A30 — Unknown: how many presses a steered sweep takes on Dreamscythe.** The model on the real
  roster (R20) says 15-25 for Alliance and 28-45 for Horde on a busy evening, against the fixed
  plan's 29-35, with the fixed plan's whole haul in roughly the first half. The
  bar's "~N" is the live estimate; the chat line at the end says how many rated players it found.
- **A31 — A drag in the class list lands where the line shows** (R21): OnDragStart/OnDragStop
  on the rows, the drop gap from `GetCursorPosition()` divided by the list's effective scale
  against its top. Written from the API, checked only under the mock; if a drop lands one row off
  at Devin's UI scale, that division is the place to look.
- **A32 — CONFIRMED from the client's tables, not yet seen in game: the race atlases exist.**
  `raceicon-<race>-<male|female>` for all ten TBC races is in UiTextureAtlasMember for build
  2.5.6.70006 (wago.tools), and Blizzard's own SharedXML on this branch builds the same names
  (`GetRaceAtlas`). If a row's race icon is blank for a player whose race is known, the atlas
  lookup (`C_Texture.GetAtlasInfo`) said no (R22).
- **A33 — Unknown: the scale of /who's `gender` number.** Recruit reads 2 as male and 3 as female,
  as `UnitSex` does. If /who uses 0/1 instead, players known only from /who get the male race icon;
  ladder, GUID and unit sightings are unaffected.

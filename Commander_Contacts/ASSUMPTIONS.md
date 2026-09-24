# Commander_Contacts — assumptions to verify in game

Everything here passes the three headless harnesses, which prove the logic and nothing about the
live client. Numbered so a test session can report against them. A1–A3 decide whether the module
works at all; the rest degrade gracefully.

---

## A1 — The chat event payloads sit where the API documentation says

**Load bearing.** `CHAT_MSG_WHISPER` is read as `(text, sender, …, guid)` with the GUID at
argument 12, and `CHAT_MSG_BN_WHISPER` with the Battle.net sender id at argument 13. This is
straight from `ChatInfoDocumentation.lua` on the `classic_anniversary` branch, and Commander_Chat
already reads the first two.

Symptom if wrong: whispers file under the right name but with no class colour (GUID missing), or
Battle.net whispers do not file at all.

Test: have someone whisper you; the thread should appear in Activity with their name class-coloured.

## A2 — `CHAT_MSG_WHISPER_INFORM` fires for whispers sent by `SendChatMessage` from an addon

**Load bearing for the compose box.** The window sends and files nothing (D4); the reply only
appears in the thread when the client echoes it back. Blizzard's own chat frame prints your sent
whispers from the same event, so it should.

Symptom if wrong: you can send from the box, the other person receives it, but your side of the
conversation never appears.

Test: reply from the compose box and confirm the line appears under "You".

## A3 — `SendChatMessage(text, "WHISPER", nil, "Name-Realm")` accepts the full name a whisper arrived with

The thread whispers back to exactly the sender string the event delivered. Commander_Who sends to
`fullName` the same way, so this is expected to hold.

Symptom if wrong: "the whisper was refused" in chat when replying to a cross-realm player.

## A4 — `C_FriendList.GetFriendInfoByIndex` answers `className` as a *localised* name

The friends sidebar colours names by class, and the token is recovered by reverse-mapping
`LOCALIZED_CLASS_NAMES_MALE/FEMALE`. On an English client the fallback (upper-case the name) gives
the same answer, so a missing table costs nothing there.

Symptom if wrong: online friends listed in plain white.

## A5 — Party members are reachable as `party1..4` / `raid1..40` through `UnitName` when the roster event fires

The group session's member list is built from those unit tokens at `GROUP_ROSTER_UPDATE`. At login
the roster can arrive before the names resolve (`UNKNOWNOBJECT`); those are skipped and picked up
on the next roster event, and anyone who *speaks* is added from their line regardless.

Symptom if wrong: a group thread whose subtitle says "Party with nobody yet" until someone talks.

## A6 — A `Frame` with `SetHyperlinksEnabled(true)` receives `OnHyperlinkClick/Enter/Leave` for links in its child FontStrings

Item and spell links in a line are meant to be hoverable and clickable. The call is guarded, so a
client without it simply shows the link text. Blizzard's own chat frame is a ScrollingMessageFrame
rather than a plain Frame, so this one has not been exercised elsewhere in the suite.

Symptom if wrong: links in the transcript are coloured but inert.

Test: get an item linked to you in a whisper; hover it in the thread.

## A7 — `FontString:GetStringHeight()` is right on the same frame the text was set

Each transcript row is sized from the wrapped text height immediately after `SetText`. If the
engine only answers after a layout pass, rows would overlap on first draw and correct themselves
on the next refresh.

Symptom if wrong: overlapping lines the first time a long thread is opened.

## A8 — `C_BattleNet.GetAccountInfoByID(bnetID).accountName` names a Battle.net thread

Without it the thread is called by the tokenised `|Kq…|k` string the event carries, which a
FontString renders correctly but which cannot be searched.

Symptom if wrong: Battle.net threads searchable only by their lines, not their name.

## A9 — `Ambiguate(name, "none")` strips only the player's own realm

Used first, with the store's own realm comparison as the fallback. If it behaves differently
(strips every realm, say), two "Bob"s from two realms would share a thread.

Symptom if wrong: a cross-realm stranger's lines appearing in a same-realm friend's thread.

## A10 — The friends window's bottom buttons carry their Classic names and leave the gap the XML says

The Contacts button is anchored between `FriendsFrameAddFriendButton` and
`FriendsFrameSendMessageButton` (Friends tab) and between `FriendsFrameIgnorePlayerButton` and
`FriendsFrameUnsquelchButton` (Ignore tab), and expects ~110px between them. All four names are
guarded, so a renamed button costs the Contacts button on that tab and nothing else.

Symptom if wrong: no Contacts button on the game's friends window (names), or a squashed one
overlapping its neighbours (gap narrower than the XML says).

Test: open the game's friends list (O) and look between Add Friend and Send Message.

## A11 — Same-realm names on the battleground scoreboard carry no realm suffix

**Load bearing for suggestions.** `GetBattlefieldScore` is documented (and verified by Oracle) to
return `Name-Realm` for cross-realm players; the scout treats a name with no suffix, or with your
own realm's suffix, as "from my server". If same-realm names also arrived suffixed with a realm
spelled differently from `GetNormalizedRealmName` (spaces, say), nobody would ever be recorded.

Symptom if wrong: an empty Suggested section after a full battleground.

Test: finish one battleground and check `/ccontacts stats`-style evidence: a Suggested row should
appear for whoever topped damage or healing on your side from your realm.

## A12 — `UnitPVPName(unit)` returns "Title Name" with the title in front

The title is recovered by stripping the plain name off the end of the PvP name. A client that puts
the title after the name, or uses a separator other than a space, would produce no title (the
suffix check fails safe) and only lose that feed.

Symptom if wrong: no "Wears the … title" suggestions even standing next to a titled Gladiator.

## A13 — Commander_Muster's record carries `arena[teamSize].rating` and its `RECORD` event names the GUID

Read straight off Muster's own source (`ReadInspectArena`, `RecordFor`), so this only breaks if
Muster changes shape. The rating feed is optional; without Muster the scout runs on the scoreboard
and titles alone.

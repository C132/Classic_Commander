# Commander_Contacts — decisions

Numbered so code comments and future sessions can cite them.

## D1 — One window, three tabs, one layout

Slack's shape is the whole design: a navigator down the left, the thing you picked filling the
right, a box at the bottom to answer from. The three tabs only change what the navigator lists.
The right-hand pane keeps one layout for all of them — a header card (name, status, the verbs
that apply), the conversation, the compose box — because a friend *is* a thread with a status
line on top, and an ignored player is a thread you have chosen not to answer. Building three
different right-hand panes would have been three chances to get the transcript wrong.

`ResolveSelection` is the seam: it turns whatever is selected into a **view** (title, subtitle,
verbs, the thread to draw, whether you may reply, and how a reply is sent) and `RefreshMain` only
draws views. Adding a fourth tab means adding a branch there and nothing else.

## D2 — Friends and Ignore are read live; Activity is the store

The friends list and the ignore list are the client's own, read through `C_FriendList` every time
the sidebar is drawn. Keeping a copy would mean a second thing to keep in step with a list the
player also edits from Blizzard's frame and from `/friend` in chat. The one thing the game does
not keep is what people *said*, so that is the only thing the store holds.

The two meet by name: a friend's thread is `dm:<short name>`, where the short name is the
`Name-Realm` with the player's own realm removed. Friends in TBC are same-realm, so this is always
the friends-list name; a whisper from another realm keeps its realm and can never collide.

## D3 — A thread is keyed by who, and a group is a session

People are `dm:<short name>` and Battle.net accounts are `bn:<accountID>` — the account, not the
character, because a Battle.net friend hopping characters is still one conversation.

A group is not a place, it is a **session**: the thread opens the moment the roster says you are
in a group and closes when it says you are not, and everything on party, raid, battleground or
raid-warning in between is one conversation. The active key is in the DB so a `/reload`
mid-dungeon continues the same thread rather than starting a second one; `Attach` clears it if
the group it names has already ended. A party that grows into a raid stays one thread and its
default name follows (`Party · 14 Sep` → `Raid · 14 Sep`) unless the user renamed it.

A party line that arrives before any roster event — the order is not guaranteed at login — opens
the session from the line itself rather than being dropped (harness C6).

## D4 — The compose box files nothing; the echo is the record

Sending a whisper writes nothing to the store. The client echoes what you sent as
`CHAT_MSG_WHISPER_INFORM` (Battle.net: `CHAT_MSG_BN_WHISPER_INFORM`; a group: the same party
event everyone else gets, with you as the sender), and that echo is filed like any other line.
Filing at send time as well would print every reply twice, and would record replies the server
refused. Harness D5 proves the send leaves the thread untouched and the echo lands.

The same rule means "Your Replies" is a logging switch, not a UI switch.

## D5 — Unread is a counter, read is a moment

Each thread carries `unread` (incremented by a line from *them*, never by one from you) and
`lastRead`. Opening a thread zeroes it; a line arriving on the thread you have open is read at
once; a line on any other thread is not (harness D6). The counter is stored rather than derived
from timestamps because it survives a prune of the lines it counted and costs nothing to sum for
the title.

## D6 — Restore Defaults is made safe by construction

`CommanderContactsDB` is one SavedVariables table holding both the options and every line kept.
`Commander.UI.ResetToDefaults` iterates the **defaults** table, not the saved one, so it can only
rewrite keys that appear in `DefaultSettings`. `Conversations`, `ActiveGroup` and `NextID`
deliberately do not appear there, and neither does the view state (`LastTab`, `LastSelected`,
`LastFilter`, `FramePos`). Checked twice in the harness — as a property of the defaults table (R1)
and by running the real `/ccontacts reset` path and counting the threads afterwards (R2) — because
it is the one mistake in this module a user could not recover from.

## D7 — The store is pure Lua and the host is the only client-facing file

`CommanderContactsStore` touches no widget and no client API; its clock is an injection point.
`CommanderContacts.lua` (the host) is where every `C_FriendList`, `C_BattleNet`, `SendChatMessage`
and event registration lives, each behind a guard and a `pcall`, so a function this client turns
out not to have costs a feature — no Battle.net section, no invite button — never a window that
fails to open. Every event registration is its own `pcall` because a throw inside a registration
loop silently drops every event after it.

## D8 — Names are learned, not looked up

A thread's `target` (what `SendChatMessage` is given) starts as whatever created it and is
upgraded whenever a fuller form arrives: the friends list knows `Bob`, a whisper knows
`Bob-Realm`, and the fuller one wins and is never downgraded. Class is the same — the friends list
only knows it while the friend is online, a whisper carries the GUID — so both are refreshed
opportunistically and neither is ever blanked by a source that does not know.

## D9 — The way in from Blizzard's window is a button in the gap, one per tab

The Classic friends window is 384 wide and both its Friends and Ignore tabs put one 131px button in
each bottom corner, leaving roughly 110px between them that nothing uses (verified against
`Classic/FriendsFrame.xml` on the `classic_anniversary` branch). One "Contacts" button sits in
that gap on each tab, **parented to the tab's own sub-frame** (`FriendsListFrame`,
`IgnoreListFrame`) so it appears and disappears with the tab and never has to be told which one is
showing. Each opens this window on the matching tab. Nothing protected is touched — Commander_Who's
toolbar hangs off the same window the same way — and the install is idempotent and tried at both
`PLAYER_LOGIN` and `PLAYER_ENTERING_WORLD` in case the window is built late.

## D10 — Battle.net friends are a folder, and a search opens it

Battle.net friends are their own section under the character friends, and that section is the one
heading in the window that folds: click it to collapse to the heading, click again to open. The
fold state is the `FoldBattleNet` setting itself rather than separate view state, so the options
page and the heading are two handles on one switch and Restore Defaults puts it back open.
`ShowBattleNet` removes the section altogether for people who keep their Battle.net list in the
game's own window. A search always unfolds the section, because a hit you cannot see is worse than
a fold you did not ask for; clearing the search folds it back.

## D11 — Suggested friends are weighed from evidence the game already shows, and only for people you could add

Three feeds, one pure module (`CommanderContactsScout.lua`): the scoreboard at the end of every
battleground (damage, healing, killing blows for all forty players, read once per board the moment
a winner is declared), the PvP title in front of a teammate's name (`UnitPVPName` on the raid
inside a battleground), and — when Commander_Muster is installed — the arena ratings its inspect
reads, taken off its `RECORD` event through `RecordFor`. Nothing is asked of anyone and nothing is
inspected by this addon; it only weighs what is already on screen.

Only your own faction and your own realm are recorded, because nobody else can be a friend. Ranks
are taken over the whole match, both sides, so "top damage" means top of the game, not top of your
team. A title and a rating are the same argument twice and only the stronger counts; arena and
battleground evidence are two arguments and add. The rating bands (2200 Gladiator range, 2000
Duelist, 1850 Rival, 1650 Challenger) are the rough TBC season shape and the sentence says "range"
for that reason. Friends are filtered at list time, not record time, so a friend you later remove
comes back into the list with their history intact; "Not Interested" is the opposite — the name is
never recorded again. The record (`Performers`, `Dismissed`) lives beside the conversations and is
equally out of reach of Restore Defaults (harness S18).

## D12 - Commander Orders: Arrow To Them, and a [Go] in the log

1.1.0, 2026-10-05 (Commander Orders 3.1, its SPEC 5). Three additions, each looked up at the moment
it is needed, so the window is unchanged without Orders (now in the OptionalDeps so it loads first).

**Arrow To Them** is offered in a person's menu (a friend's row, a whisper thread) only while they
stand in your party or raid: Orders follows them as a unit follow named by GUID (source `Contacts`,
key `follow`), so asking for someone else moves the one follow, Orders finds the same person again
after the roster shuffles, and catching up with them does not end it. The press goes through
`CommanderOrders.GoTo`, not silent, so Orders says "Waypoint set: <name>" or its ONE refusal line in
its own words. Nobody ungrouped is offered anything: the friends list's zone name is a zone, not a
place, and "go to their zone" is not a Go-to (Orders' DECISIONS D31, the 3.1 "Go to" words: Go to a
place, follow a person). The words are the SPEC's "Arrow to them", in this window's Title Case.

**A [Go] in the log.** Each logged line is run through `CommanderOrders.Linkify` when it is drawn
and the result is kept per line (until its text or Orders' Chat Links setting changes), so a
`/way ...` or "Zone 45.2, 66.8" someone sent carries the same [Go] as it does in chat. A line from
the log is given no live context: where the sender stood then is not where anybody stands now, so a
bare "/way 45 66" stays text; a line naming its zone or map is linked.

**Hover.** `GameTooltip:SetHyperlink` cannot show an `addon:` link, so hovering one fires
EventRegistry's `ChatFrame.OnHyperlinkEnter` / `ChatFrame.OnHyperlinkLeave` with the row, the way a
chat frame does, and Orders shows its tooltip (A14). Clicks already reached Orders through
`SetItemRef`.

## D13 - Arena ratings beside every name, from Commander Muster (1.2.0)

Devin wants a player's 2v2/3v3/5v5 ratings wherever their name shows.
Contacts asks `CommanderMuster.RatingsLine` (already an OptionalDep), the
suite's one rating source. It merges what Muster has inspected with the
Commander Ladder web feed, so an offline friend or a whisperer from far away
still shows a number, with its age.

The ratings lead three lines: a friend's row in the sidebar, the friend
card's subtitle, and the subtitle of a whisper thread with a person. They
come first so a long zone truncates and they do not. Group threads and
message previews are left alone. The Scout's own `Performers[...].ratings`
stay as they are: they rank strangers for suggestions by the highest rating
seen, which is a different question from what someone is rated now.


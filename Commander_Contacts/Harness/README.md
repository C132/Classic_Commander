# Commander_Contacts harnesses

Five luajit checks, all in-addon. Run **all five** before any change.

```bash
/opt/homebrew/bin/luajit contacts_store_smoke.lua   # store fixture - 131 checks
/opt/homebrew/bin/luajit contacts_scout_smoke.lua   # scout fixture - 70 checks
/opt/homebrew/bin/luajit contacts_ui_harness.lua    # UI + host     - 316 checks
/opt/homebrew/bin/luajit contacts_orders_smoke.lua  # the REAL Commander Orders - 34 checks
/opt/homebrew/bin/luajit globals_lint.lua           # 5 files, 0 undeclared globals
```

All five resolve the AddOns root from their own file location, so they work in a git worktree as
well as in the live AddOns directory. Each is silent on success apart from a one-line count and
exits non-zero if anything failed.

---

## `contacts_store_smoke.lua` — the store

No mock at all. `CommanderContactsStore` is pure Lua, so this loads that one file and drives
hand-built SavedVariables tables through the real calls. A failure here is always a real logic bug,
never a mock artefact. The clock is frozen and advanced by hand (`TICK`); `date` is stood up as
`os.date` because the client has a global `date()` and plain luajit does not — without it the
group thread's default name silently loses its date.

Covers the name helpers (`Shorten`, `PlainText`, `Preview`); the normalising `Attach` contract
against tables damaged the way a hand edit or an older build damages them; person and Battle.net
threads; the group session lifecycle (start, roster merge, party-to-raid rename, close); appending
with the unread rule and the per-thread cap; read state and totals; the listing grammar (kind,
friends/strangers filter, search inside link labels and member names, three sorts, pinned first,
stable tiebreak); and pruning.

Sections worth knowing about:

- **B2–B7** are the damaged-table cases. A thread with junk lines, a group with duplicate members,
  a `NextID` that has fallen behind, an `ActiveGroup` pointing at a group that already ended. The
  invariant being proved is that loading a broken file loses junk, never a line of chat.
- **E1–E2** are the unread rule: a line from them counts, a line from you does not.
- **G8** lists eight threads created in the same frozen second twice. `table.sort` is not stable,
  so without the key tiebreaker this is where a flicker would show up.
- **H4** proves the prune keeps the live group and a pinned empty thread while dropping an old
  empty one.

## `contacts_scout_smoke.lua` — the scout

No mock. `CommanderContactsScout` is pure Lua: this feeds it hand-built scoreboards (both
factions, a cross-realm teammate, the player themself, a zero row), titles and ratings, and checks
who it suggests and the exact sentence it gives for each.

Worth knowing: **B4** proves the three exclusions (other faction, other realm, you); **G1** proves a
title and a rating are one argument, not two; **H1/H2** prove arena and battleground evidence add up
and the sentence leads with the stronger half; **J1** proves a dismissed name is never recorded
again, not merely hidden.

## `contacts_ui_harness.lua` — the UI and the host

Loads the **real** shared framework (`CommanderSettingsUI.lua`, `CommanderEvents.lua`) plus all
four addon files under the suite's permissive widget mock, on top of a fixtured previous session:
a thread older than the retention window, a recent thread with an item link in it, a group that
ended but was left marked active, a remembered tab, and a saved setting the defaults pass must not
overwrite.

The mock is the shared suite preamble plus what this module needs: **edit boxes with real focus
and real text** (the compose, notes and search boxes all branch on `HasFocus`), and a social API
fixture — two friends, one ignore, one Battle.net friend, and a group roster the test flips
between party, raid and nothing. `SendChatMessage`, `C_BattleNet.SendWhisper`,
`C_PartyInfo.InviteUnit` and `ChatFrameUtil.SendTell` are logged, never assumed.

It drives login, whispers filing (own realm stripped, foreign realm kept, class from the GUID,
outgoing echoes, every logging switch), party sessions following the roster, then the window on
all three tabs: selecting, replying, the unread pill and title count, search, the filter menu, the
right-click menus, the notes box, the folding Battle.net section, every verb, every dialog, every
slash entry point, and the Contacts buttons planted on Blizzard's own Friends and Ignore tabs.
Section S stands up a battleground (instance type, zone, scoreboard, winner), titled raid members
and a stand-in Commander_Muster, and proves the scout is fed only inside a battleground, only once
per board, and that the Suggested section, its card, its verbs and its switches all behave.

The checks worth naming:

- **R1/R2** — Restore Defaults cannot delete a thread. R1 checks it as a property of the defaults
  table; R2 runs the real `/ccontacts reset` path and counts the threads afterwards.
- **D5** — the compose box sends and files *nothing*; the client's `CHAT_MSG_WHISPER_INFORM` echo
  is the record. Proved by counting the thread before and after the send, then firing the echo.
- **D6** — a line arriving on the open thread is read at once; a line on another thread is not,
  and its row grows a pill with the count.
- **C6** — a party line that arrives before any roster event opens a session rather than being
  dropped.
- **E7** — replying to a friend with no thread yet creates the thread, and the echo shows in the
  card without reselecting.

## `globals_lint.lua` — scoping

In Lua a local declared *after* a function body is not in that body's scope, so the reference
silently compiles to a global access and reads nil at runtime. This module is built out of
mutually-recursive refresh functions — `Select` calls `RefreshMain` calls `RefreshTranscript` —
which is exactly the shape that bug hides in.

luajit's bytecode listing names every global a file really touches, so the check is exact rather
than heuristic: dump `GGET`/`GSET`, subtract the globals we mean to touch, and anything left is a
scoping bug or an undeclared API. Add a genuinely new WoW API to `ALLOWED`; do not add a name just
to make it quiet.

## Commander Orders 3.1 (1.1.0, DECISIONS D12)

`contacts_ui_harness.lua` section **G** drives the three additions against a recording stand-in for
Orders: Arrow To Them in a grouped friend's menu (a unit follow on their token, named by GUID,
source Contacts, key follow, the UNIT tint, not silent) and none when they are not grouped or
Orders is absent; a whisper thread's menu in a raid (the raid token, the short name as the title);
a logged line run through `Linkify` once and kept per line across redraws; hovering an `addon:`
link firing EventRegistry's `ChatFrame.OnHyperlinkEnter` / `...Leave` with the row, and an item
link keeping the game tooltip. `CONTACTS_UI=/path` loads a copy of `CommanderContactsUI.lua` (added
for this round); five mutants (the entry always offered, the link cache dropped, the hover not
fired, the log not linked, the title not shortened) are all killed. The globals lint now allows
`UnitExists`, `UnitIsUnit`, `EventRegistry`, `CommanderOrders` and `CommanderOrdersDB`.

`contacts_orders_smoke.lua` boots the REAL Commander Orders (its chat file included) over
`Commander_Orders/Harness/orders_mock.lua` and the Contacts files after it. A loads clean; B Arrow
To Them on a grouped person's thread is a real unit follow (Contacts, follow) on their token, in the
UNIT tint, that does not clear on arrival, with the arrow on it and Orders' "Waypoint set" line
once; after a roster shuffle Orders follows the same person by GUID; asking for someone else moves
the one follow; C not grouped offers nothing; D a logged "Elwynn Forest 42.5, 61.2" carries
Orders' own [Go] link and clicking it is Orders' Go, a bare "/way 45 66" stays text, and with
Orders' Chat Links off the line is drawn plain; E hovering the link shows Orders' tooltip. Passing
the GUID is equivalent against the real Orders (Orders records the token's GUID itself when a
follow names none); the UI harness's G1 holds Contacts to passing it.

Section **R** (1.2.1): `CommanderContacts_OpenWhisper` makes and opens a thread for a player with no
history (Activity tab, that conversation selected, kept like any other), opens an existing one on
its history, refuses an empty name, and raises no errors.

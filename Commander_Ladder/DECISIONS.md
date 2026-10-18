# Commander_Ladder — decisions

Numbered so code comments and future sessions can cite them.

## L1 — Ratings for players nobody inspected come from outside the game

The client tells an addon another player's rating only through an inspect,
and only for your own faction within about 28 yards. The arena scoreboard
gives MMR and rating change, not rating. `C_PvP.GetScoreInfo` is not on this
client. Addons cannot use the network. So the numbers come from Blizzard's
web API, the source ironforge.pro uses. `Tools/ladder_feed.py` fetches them
on the Mac and writes `CommanderLadderData.lua`, which the game loads at
login or `/reload`.

## L2 — Commander_Muster is the only caller

Ladder answers three calls: `Lookup`, `Want` and `Generated`. Everything
else in the suite asks `CommanderMuster.RatingsFor`, which merges the feed
with what Muster has seen. The newest reading wins (Muster D11). This keeps
one rule for which number to believe, in one place.

## L3 — The data file is generated, untracked and optional

`CommanderLadderData.lua` is in `.gitignore`. An hourly refresh would bury
the history in noise, and the file is Devin's local copy of public data.
The toc still lists it, so the file must ALWAYS exist: a missing toc file is
a LUA_WARNING at every login (B5, disproven in game 2026-10-16). Before the
first run it is a comment-only placeholder, which leaves `CommanderLadderData`
unset, so every lookup is nil. The script writes to a temp file and renames
it, so the game never loads half a file, and it never deletes the file.

## L4 — Two sources: the ladder, then the names you meet

A run pulls every bracket's leaderboard for the current pvp season — on
Anniversary that is the retail path `/data/wow/pvp-season/{id}/pvp-leaderboard/{bracket}`,
about 5,000 players each (B2); older Classic flavours put a pvp region in front. Then it looks up, by profile, the names the addon saved through
`Want`: players you met whom the ladder lacks. That is three requests per
name, at most 800 names a run, newest wishes first. Entries a run does not
refresh are carried over for a week, so a player who fell off the ladder
keeps their last number with its age. A new season carries nothing.

## L5 — Credentials stay in the Keychain

The client id and secret are read with `security find-generic-password` at
the start of each run. They are never printed, logged, put in a URL or
written to a file in this folder, which is a git repo. Errors pass through
`redact()`, and the tests check that neither the secret nor the token
appears in any output.

## L6 — Polite by default

The script makes 20 requests a second against the API's 100, and stops at
30,000 an hour against its 36,000. A 429 or 5xx waits out `Retry-After` (or
doubles its wait), and an expired token is fetched again. Only the standard
library is used, run under `python3 -I`, so nothing next to the script can
be imported in its place. The SavedVariables and old data files are read by
`sv_to_json.lua` in an empty Lua environment.

## L7 — A daily refresh, by launchd (2026-10-17)

Devin asked for the feed to run itself. A user LaunchAgent,
`~/Library/LaunchAgents/com.commander.ladder-feed.plist` (outside this repo, on his Mac
only), runs `/opt/homebrew/bin/python3 -I Tools/ladder_feed.py run` at 06:00 every day;
launchd runs a missed time once on wake. Output goes to
`~/Library/Logs/CommanderLadder.log` (one line a run; errors pass through `redact()`).
It reads the Keychain from his login session, which a LaunchAgent has. The game still only
sees new data at login or `/reload`. Off: `launchctl bootout gui/$(id -u)/com.commander.ladder-feed`;
now: `launchctl kickstart gui/$(id -u)/com.commander.ladder-feed`. First kickstart
2026-10-17: exit 0, 9,505 players.

## L8 — A name the game gave without a realm (1.1.0, 2026-10-17)

The group finder lists Nightslayer players by bare name, and Muster used to fill in our
realm: 28 of 37 wanted names the feed could not find were exactly that (Muster D14). Now:

- `Lookup(name, realm, anyRealm)`: with `anyRealm` and a bare name, our realm is tried
  first; on a miss, the one other realm in the data that has the name answers. Two other
  realms with it is left unanswered rather than guessed (an index built once per file).
- `Want(name, realm, anyRealm)` files the name as `Name-*OurRealm`.
- The feed skips a `*` name that one realm's ladder already has (the game matches it by
  name). Otherwise it asks the character summary
  (`/profile/wow/character/{realm}/{name}`, a 404 when no such character) on our realm
  first, then the ladder's realms busiest first, then the rest of the index; brackets are
  fetched only where the character lives, and an unrated one there does not stop the
  search, since a bare name could be either person.

The cost of a bare name is ambiguity: the same name on both realms shows ours, or
failing that the other one's. That is rarer than the miss it replaces.

## L9 — Who the home realm's rated players are (1.2.0, 2026-10-17)

For Commander_Recruit's sweep (its R20): /who can only be aimed by class, race, guild or zone,
so to look where the rated players are Recruit needs those facts about them, which the
leaderboard does not carry (name, realm, faction, rating, record only). The character profile
summary does: `faction`, `character_class`, `race`, `guild` and `last_login_timestamp` (B7,
field names checked live first with `ladder_feed.py fields`).

- **Which players.** Every player in the data file on a realm in `HOME_REALMS` (Dreamscythe: 2,019
  on 2026-10-17, ladder players plus carried-over and wanted ones; 2,002 described, 17 gone). Nightslayer would add ~7,900 requests a week and Devin plays Dreamscythe; adding
  it is one line.
- **Cached a week, outside the repo.** `~/Library/Caches/CommanderLadder/profiles.json`
  (`COMMANDER_LADDER_CACHE` overrides): one record per player, fetched again after five to seven
  days (fixed per name, so the first fill does not all come due one morning), never-fetched
  first, at most 2,500 a run. The first run fetches them all: 2,019 requests, roughly eight of that
  run's 27 minutes (6,736 requests, most of them its 800 wanted names, L8), since each request is
  a new TLS connection; after that a daily run fetches a few hundred at most, plus new ladder
  players. A 404 (renamed, moved, deleted) is cached as gone and asked again in a week; a
  spent request budget stops the fetching and keeps what came; a player off the data for a
  month is dropped from the cache.
- **Written compactly.** A described player's line gains
  `w = { faction, class, race, lastLogin, guild }` — `"A"`/`"H"`, the game's own tokens
  (`"ROGUE"`, `"BloodElf"`, `"Scourge"`), epoch seconds (the API sends milliseconds), and the
  guild name, left off when there is none. Ratings and `t` are unchanged, so `Lookup`, Muster's
  `FeedSource` and the feed's own carry-over read the file exactly as before.
- **A fresher last login.** The summary is up to a week old; the ladder is a day old. A player
  whose won/lost moved since the last run played a match after it, so their last login is
  raised to the last run's time.
- **In game.** `CommanderLadder.Roster(realm)` lists our realm's described players as
  `{ key, name, faction, class, race, last, guild, best }`, built once per data file. It is the
  second caller-facing purpose after ratings (L2 still holds for ratings: they go through
  Muster); Recruit is its one caller.

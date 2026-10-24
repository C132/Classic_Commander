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
only), runs `/opt/homebrew/bin/python3 -I Tools/ladder_feed.py run` at 06:00 every day (since
2026-10-18 also 18:00 and once at each login, L11); launchd runs a missed time once on wake. Output goes to
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

## L10 — Sex and talent tree too (1.3.0, 2026-10-18)

For Recruit's race and tree icons (its R22). The summary already carried `gender.type`; the tree
needs one more request per player, `/profile/wow/character/{realm}/{name}/specializations` (B8):
the active group of a dual spec (else the first), the tree with the most `spent_points`, written
as the en_US name's letters in capitals (`"SUBTLETY"`, `"BEASTMASTERY"`, `"FERALCOMBAT"`); no
talents, or a 404, is no tree.

- `w` gains named fields, each left off when unknown: `sex = "M"|"F"`, `spec = "SUBTLETY"`.
  Named, so the positional five keep their places and older readers ignore them.
- The cache records carry `x` (sex), `s` (tree) and `v = 2`; a described record without `v = 2`
  is fetched again on the next run whatever its age, so the cache filled on 2026-10-17 was redone
  once: the LaunchAgent's first run at load, 2026-10-18, exit 0, 2,318 Dreamscythe players described,
  every one with sex and a tree, 9,501 requests in about 45 minutes (most of them wanted names, L8). A spent budget mid-player keeps the players before it.
- Two requests a player now: the weekly spread (L9) is ~2,000 summaries and ~2,000 trees.
- `Roster()` adds `sex` and `spec`.

## L11 — A flaky network does not end a run (1.3.0, 2026-10-18)

The first run after L10 died 25 minutes in: a read timed out while `urlopen_fetch` was reading a
404's body, and only `HTTPError` was caught, so the TimeoutError ended the run and nothing was
written. Now every network failure (a timeout, a reset, DNS, also inside an error's body) comes back
as status 599 and `Api.get` retries it like a 5xx, with the same backoff. If a request still fails
six times, the wanted-name lookups stop there (as the profile refresh already did) and the ladder
is written anyway. This matters more now that the LaunchAgent runs at 06:00, 18:00 and at each
login (Devin's ask, 2026-10-18; L7's plist, outside the repo).

## L12 — Wanted names: remembered when unrated, a quick run, one run at a time (1.4.0, 2026-10-18)

Devin, with two group-finder players Recruit had no rating for (Udeadmon and Desmurigor,
Dreamscythe, rated 1448-1555, so below the leaderboard's cut-off, which is Blizzard's, not ours:
roughly 1630-1790): "still missing a lot of data on players". Traced:

- **They never reached the feed.** Wanted names travel in SavedVariables, which the game writes
  only at a /reload or logout; the saved list was from 03:56 and the two were seen after that.
- **The list was noise.** 1,000 wishes, the cap, covered only the last ~2.5 hours of sweeping:
  869 bare names, 384 of them already in the data, and every run looked the same few hundred
  unrated level 70s up again, about eight requests each (a bare name is tried on every realm,
  L8) -- most of a 20-45 minute run.

Changes:

- **Unrated is remembered.** A wish looked up and found unrated or nowhere goes in `checked.json`
  beside the profile cache and is skipped for two days (`RECHECK_UNRATED`), so a run looks up
  only names it has not seen lately. Found rated, it leaves the list. Nothing is filtered by rating:
  any rated player found is written, whatever the number.
- **`ladder_feed.py wanted`**, a quick run: the last data file as it stands (descriptions kept),
  plus the wanted names it lacks, plus profiles for new home players only. No ladders, no weekly
  refresh. Minutes once `checked.json` has filled. For right after a /reload.
- **One run at a time.** `run` and `wanted` take a lock (`run.lock` in the cache folder); a second
  waits for the first.
- **The cap is 3,000** wishes (was 1,000): hours of sweeping instead of 2.5. Recruit also stops
  asking about players under 70 (its R24), who cannot be rated.

So a player Recruit sees reaches the board after: a /reload (or logout), a feed run (06:00, 18:00,
login, or `wanted` by hand -- or, since L13, on its own right after the save), and another /reload.

## L13 — The quick run starts itself when the game saves (1.4.0, 2026-10-20)

Devin said yes to running `wanted` whenever the game writes Commander_Ladder's saved variables. A
second user LaunchAgent, `~/Library/LaunchAgents/com.commander.ladder-wanted.plist` (outside the
repo, beside L7's), watches `WTF/Account/RETROTEC1/SavedVariables/Commander_Ladder.lua`
(`WatchPaths`) and runs `ladder_feed.py wanted --notify`, at most once a minute
(`ThrottleInterval` 60), never at load. Same log as L7.

- **The save first.** launchd starts it the instant the file changes, possibly mid-write, so with
  `--notify` the run first waits until the file is five seconds old (`settle`, 60 s at most).
- **One run at a time.** It takes L12's lock, so it waits out a full 06:00/18:00/login run.
- **Nothing new, nothing written.** A quick run that finds no one and fetches no profile leaves the
  data file alone.
- **A notification** ("N new rated players found. /reload to see them.") when it found someone,
  through `osascript` with the text as an argument, never through a shell.

The loop is now: /reload (the game saves the names it wants) -> a minute or two later, the
notification -> /reload again. Off: `launchctl bootout gui/$(id -u)/com.commander.ladder-wanted`.
Tested 2026-10-20 by touching the file with the game closed: the run started within a second.

## L14 — A home player's brackets the ladders left out; one kept-alive connection (1.4.0, 2026-10-21)

Devin, with Attackboss-Dreamscythe's tooltip showing only 3v3 1698: "Why do I not see this guy's
5s? ... my data is out of date". Asked live: 2v2 1619 (49-46), 3v3 1698, 5v5 1724 (62-43). The ladders
list only the top ~5,000 a bracket (cut-offs that night: 2v2 1681, 3v3 1637, 5v5 1789), so he was
on the 3v3 ladder alone -- and once a player is in the data the wanted lookup (L4, L8) never asks for
anything more. Every home player in the top 5,000 of one bracket showed only that bracket.

- **Asked for.** A full run fetches, for each home-realm player, every bracket the ladders did not
  list this run (`refresh_brackets`, `/pvp-bracket/{2v2|3v3|5v5}`): about once a day each (20 hours,
  less up to 8, fixed per name), oldest first, at most 3,000 players a run, and at once when a
  bracket has just gone missing (fallen off its ladder). A 404 is unrated. Cached in
  `brackets.json` beside the profile cache; a wanted name just looked up (all three brackets) is
  recorded there too, so it is not asked again the same day.
- **Merged.** `merge_brackets` fills the left-out brackets from the cache; the ladder's own number
  always wins; a bracket now unrated drops an old carried number. Carried-over home players (off
  every ladder) get all three refreshed the same way, so they no longer age up to a week.
- **Cost.** About 4,400 home players, most missing one or two brackets: ~7,500 requests a day, split
  between the two daily runs. Affordable because:
- **One connection, kept alive.** `keepalive_fetch` (now `Api`'s default) holds one HTTPS
  connection per host: 97 ms a request against 253 ms for a new TLS connection each (measured, 30
  requests). A dropped connection is opened once more; a second failure is a 599, retried as L11
  says. `urlopen_fetch` stays as the plain fallback.
- Other realms (Nightslayer) are still ladder-only: Devin plays and friends on Dreamscythe.

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
The toc still lists it, and a missing file only means every lookup is nil.
The script writes to a temp file and renames it, so the game never loads
half a file.

## L4 — Two sources: the ladder, then the names you meet

A run pulls every bracket's leaderboard for each pvp region's current
season. Then it looks up, by profile, the names the addon saved through
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

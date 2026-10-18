# Commander_Ladder checks

Three offline checks. Run all three before any change:

```bash
python3 -I ../Tools/test_ladder_feed.py          # the feed script, fixtures only — 31 tests
/opt/homebrew/bin/luajit ladder_harness.lua      # the addon under the WoW mock — 50 checks
/opt/homebrew/bin/luajit globals_lint.lua        # 2 files, 0 undeclared globals
```

None of them touch the network or the Keychain.

## `Tools/test_ladder_feed.py`: the feed script

- **Parsers:** the realm index (spaces removed, localized names), leaderboards, pvp-bracket
  payloads, and the region and season indexes.
- **Lua writer:** the file loads back through luajit, quotes and backslashes survive, and no temp
  file is left behind.
- **Sandbox:** the SavedVariables shim merges accounts, and a hostile file cannot reach `io`.
- **Carry-over:** a week-old entry is dropped, a new season carries nothing over, and this run's
  data wins.
- **HTTP:** the token flow, 404 as None, 429 and 5xx backoff with Retry-After, renewal of an
  expired token, and pacing.
- **Secrets:** no client id, secret or token appears in any error, URL or probe output.
- **Profiles (L9):** a summary becomes game tokens (milliseconds to seconds, no guild as "", no
  faction read from the race, a death knight refused); the cache round-trips, is made with its
  folder and starts over when damaged; only summaries about a week old are fetched (five to seven days, fixed per name, so they do not all come due one morning), never-fetched first,
  under the limit, a 404 cached as gone, an accented name encoded; a spent budget keeps what came;
  pruning drops only month-old strangers; `w` is attached to home-realm players only and its last
  login raised when the record moved; the line loads back through luajit with the ratings
  unchanged; a full run describes the home realm and the next day fetches nothing; `fields`
  prints names and never values. Every test points the cache at a temp folder.

## `ladder_harness.lua`: the addon

It loads the real shared framework plus the addon's two files. The mock is the generic half of
`Commander_Muster/Harness/muster_ui_harness.lua`.

- **No data file:** every call is nil and nothing errors.
- **Lookup:** by bare name, by name and realm, by `Name-Realm`, and with a realm containing a
  space.
- **Want:** renewal, the two-week expiry, and the 1000-name cap keeping the newest.
- **Roster (L9):** only our realm's described players, every `w` field by name, best of the
  brackets, nil for no guild or login, built once, another realm by name, nobody when off, and a
  line with `w` still read as ratings.
- **Also:** the master switch, the slash command, and the settings page.

## `globals_lint.lua`

This is Muster's lint. `CommanderLadderData.lua` is generated, so it is not linted.

## The live checks (need the Battle.net client in the Keychain)

```bash
python3 -I ../Tools/ladder_feed.py probe   # namespaces, regions, seasons, ladders, one profile
python3 -I ../Tools/ladder_feed.py fields  # field names of one ladder entry and one profile summary
python3 -I ../Tools/ladder_feed.py run     # writes ../CommanderLadderData.lua
```

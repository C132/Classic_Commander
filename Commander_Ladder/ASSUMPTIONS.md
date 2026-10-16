# Commander_Ladder — assumptions to verify

Everything here passes the offline checks. Those prove the logic and nothing
about Blizzard's API or the live client. `ladder_feed.py probe` settles B1–B4
in one run.

## B1 — The Anniversary namespaces are `dynamic-classicann-us` and `profile-classicann-us`

This comes from a Feb 2026 Blizzard forum reply ("the new namespace is
classicann-{region}"), and ironforge.pro's avatars come from
`render.worldofwarcraft.com/classicann-us`. The script falls back to
`dynamic-classic-us` and `profile-classic-us` if those don't answer.

## B2 — Classic PvP ladders live under `pvp-region`

The path assumed is
`/data/wow/pvp-region/{id}/pvp-season/{id}/pvp-leaderboard/{2v2|3v3|5v5}`.
Each entry is assumed to carry `character.name`, `character.realm.slug`,
`rating` and `season_match_statistics` (played / won / lost). The parsers
are tolerant: a missing field skips that entry rather than failing the run.
Older Classic flavours had stale ladders, so `probe` prints a sample to
compare against ironforge.pro.

## B3 — `/profile/wow/character/{realm}/{name}/pvp-bracket/{bracket}` answers for Anniversary characters

This endpoint is what serves wanted names the ladder lacks. A 404 is read as
"unrated in that bracket". If profiles don't work at all, the feed runs from
the ladder alone.

## B4 — Realm names normalize to the game's keys

The realm index's names lose their spaces, matching `GetNormalizedRealmName()`.
A realm whose name has an apostrophe or a dash would key differently in game.
None of the Anniversary US realms seem to have one.

## B5 — A missing file listed in the toc is harmless

If `CommanderLadderData.lua` doesn't exist yet, the client should log the
missing file to FrameXML.log without a Lua error popup, and every lookup is
nil.

Test: log in before the first feed run. `/cladder status` should say
"No feed yet".

## B6 — The data file's size is fine for the client

A full ladder (up to several thousand players per bracket) is one table
constructor with one line per player. That is far under Lua 5.1's
per-function constant limit, and smaller than many SavedVariables files the
client already loads.

Test: after a `run`, time a `/reload`.

# Commander_Ladder — assumptions to verify

Everything here passes the offline checks. Those prove the logic and nothing
about Blizzard's API or the live client. `ladder_feed.py probe` settles B1–B4
in one run.

## B1 — The Anniversary namespaces are `dynamic-classicann-us` and `profile-classicann-us` — CONFIRMED 2026-10-16

First live probe: a token, `dynamic-classicann-us` answered the realm index (5 realms), and
`profile-classicann-us` answered a character's pvp brackets.

This comes from a Feb 2026 Blizzard forum reply ("the new namespace is
classicann-{region}"), and ironforge.pro's avatars come from
`render.worldofwarcraft.com/classicann-us`. The script falls back to
`dynamic-classic-us` and `profile-classic-us` if those don't answer.

## B2 — Where the ladders live — CORRECTED 2026-10-16

Anniversary uses the RETAIL layout, seasons with no region level:
`/data/wow/pvp-season/index` (current season 3 on 2026-10-16), then
`/data/wow/pvp-season/{season}/pvp-leaderboard/{2v2|3v3|5v5}`, about 5,000 players a bracket
(the cut-off that day was roughly 1680 / 1630 / 1790). The first version asked only the
older Classic layout, `/data/wow/pvp-region/{id}/pvp-season/{id}/...`, got a 404 and concluded
there were no ladders; `discover` now asks the season layout first and keeps the region layout
as a fallback. Each entry carries `character.name`, `character.realm.slug` (no realm name:
the realm index maps the slug), `rating` and `season_match_statistics` — what the parser
already read. First full run: 9,441 players (9,428 from the ladders, 13 more from wanted
names), 79 requests, an 0.9 MB file that loads in ~14 ms outside the client.

Players below a bracket's cut-off are not on its ladder; they reach the file only as wanted
names (profiles, B3).

## B3 — `/profile/wow/character/{realm}/{name}/pvp-bracket/{bracket}` answers for Anniversary characters — CONFIRMED 2026-10-16

Polypopin-Dreamscythe came back 2v2 1534 (21-18), 3v3 1531 (21-29), 5v5 1682 (52-56). ironforge.pro
the same day showed 1534 / 1531 / 1605: two of three exact, 5v5 newer from the API.

This endpoint is what serves wanted names the ladder lacks. A 404 is read as
"unrated in that bracket". If profiles don't work at all, the feed runs from
the ladder alone.

## B4 — Realm names normalize to the game's keys

The realm index's names lose their spaces, matching `GetNormalizedRealmName()`.
A realm whose name has an apostrophe or a dash would key differently in game.
None of the Anniversary US realms seem to have one.

## B5 — A missing file listed in the toc is harmless — DISPROVEN 2026-10-16

It is not. Logging in before the first feed run gave Devin
`2x LUA_WARNING: Commander_Ladder/Commander_Ladder.toc:11 Error loading
Commander_Ladder/CommanderLadderData.lua`. The fix (L3): the file always
exists. Until the first run it is a placeholder that is only comments, so
`CommanderLadderData` stays unset, every lookup is nil, `/cladder status`
says "No feed yet", and the feed's carry-over reads it as `null` (a first
run). The feed replaces it atomically and never deletes it. On a fresh
checkout, create the placeholder before logging in (copy the comment block
from L3's note, or just run the feed).

## B6 — The data file's size is fine for the client

A full ladder (up to several thousand players per bracket) is one table
constructor with one line per player. That is far under Lua 5.1's
per-function constant limit, and smaller than many SavedVariables files the
client already loads.

Test: after a `run`, time a `/reload`.

## B7 — The character profile summary describes a player — CONFIRMED 2026-10-17

`ladder_feed.py fields` (reads only, prints field names and types, never values) on a
Dreamscythe 2v2 ladder player: the summary at `/profile/wow/character/{realm}/{name}`
(`profile-classicann-us`) carries `faction.type`, `character_class.id`/`.name`, `race.id`/`.name`,
`guild.name` (plus its id, faction and realm) and `last_login_timestamp`, along with level,
gender, item levels and links. The leaderboard entry itself carries `faction.type` too. The feed
maps class and race by id to the game's tokens (L9), so the locale of `.name` does not matter.

Not yet checked: that `last_login_timestamp` is milliseconds as on retail (the feed divides
anything past 10^11 by 1000, so either works), and how quickly a guild change reaches the
summary (a week-old cache makes that moot).

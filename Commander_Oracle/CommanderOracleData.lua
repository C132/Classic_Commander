-- Commander Oracle: the Arathi Basin canon.
--
-- Every number in this file is the server's, not a guess. Sources:
--   * Node identity and per-state area POIs — the client's OWN AreaPOI DB2 at
--     build 2.5.6.69546 (five rows per node: uncontrolled, Alliance
--     controlled, Horde controlled, and two "In Conflict" rows separated by
--     the world state each is gated on).
--   * Resource ticks, the score cap, the near-victory warning and the flag
--     capture time — CMaNGOS mangos-tbc `BattleGroundAB.h`, whose world state
--     IDs match the DB2 rows above one for one, which is what makes the tick
--     tables next to them trustworthy.
--
-- Nothing in this file touches the WoW API, so the headless harness loads it
-- straight.

CommanderOracle_AB = {
    -- The Arathi Basin battle map on THIS client. Not retail's 93: the
    -- Classic map set numbers it 1461 (verified against the client's UiMap
    -- DB2), and C_AreaPoiInfo.GetAreaPOIForMap wants this one.
    uiMapID = 1461,
    instanceMapID = 529,

    maxScore = 2000,        -- BG_AB_MAX_TEAM_SCORE (TBC; 1600 is a later era)
    warnScore = 1800,       -- BG_AB_WARNING_NEAR_VICTORY_SCORE
    captureSeconds = 60,    -- BG_AB_FLAG_CAPTURING_TIME, 60000ms

    -- Resources accrue in lumps, not a trickle: holding `n` bases pays
    -- tickPoints[n] every tickInterval[n] seconds. The jump at five bases is
    -- the whole reason a full cap ends a game in about a minute — it is not
    -- 4 bases plus a bit, it is nine times the rate of four.
    --   abTickIntervals[6] = {0, 12000, 9000, 6000, 3000, 1000}
    --   abTickPoints[6]    = {0,    10,   10,   10,   10,   30}
    tickInterval = { [0] = 0, 12, 9, 6, 3, 1 },
    tickPoints   = { [0] = 0, 10, 10, 10, 10, 30 },

    -- Listed the way the map reads them, north to south.
    nodes = {
        { key = "STABLES",    name = "Stables",     short = "ST",
          poi = { none = 1609, alliance = 1610, horde = 1611, conAlliance = 1612, conHorde = 1613 } },
        { key = "LUMBERMILL", name = "Lumber Mill", short = "LM",
          poi = { none = 1619, alliance = 1620, horde = 1621, conAlliance = 1622, conHorde = 1623 } },
        { key = "BLACKSMITH", name = "Blacksmith",  short = "BS",
          poi = { none = 1614, alliance = 1615, horde = 1616, conAlliance = 1617, conHorde = 1618 } },
        { key = "GOLDMINE",   name = "Gold Mine",   short = "GM",
          poi = { none = 1624, alliance = 1625, horde = 1626, conAlliance = 1627, conHorde = 1628 } },
        { key = "FARM",       name = "Farm",        short = "FM",
          poi = { none = 1629, alliance = 1630, horde = 1631, conAlliance = 1632, conHorde = 1633 } },
    },
}

-- areaPoiID -> { node = <node table>, state = , owner = , assaulter = }
--
-- Only ONE of a node's five POIs is live at a time (the others' world states
-- are off), so whatever GetAreaPOIForMap hands back reads straight through
-- this table into a board state — no icon paths, no localized strings, no
-- textureIndex ordering to guess at.
--
-- "CON ALLIANCE" is the Alliance ASSAULTING, not the Alliance defending: the
-- node belongs to nobody for the sixty seconds the flag is ticking down, and
-- lands with the assaulter.
CommanderOracle_POI = {}

for index, node in ipairs(CommanderOracle_AB.nodes) do
    node.index = index
    local P = CommanderOracle_POI
    P[node.poi.none]        = { node = node, state = "NEUTRAL" }
    P[node.poi.alliance]    = { node = node, state = "OWNED",     owner = "ALLIANCE" }
    P[node.poi.horde]       = { node = node, state = "OWNED",     owner = "HORDE" }
    P[node.poi.conAlliance] = { node = node, state = "CONTESTED", assaulter = "ALLIANCE" }
    P[node.poi.conHorde]    = { node = node, state = "CONTESTED", assaulter = "HORDE" }
end

CommanderOracle_FACTION_COLORS = {
    -- Console's palette values, so the suite agrees with itself
    ALLIANCE = { r = 0.20, g = 0.40, b = 0.95 },
    HORDE    = { r = 0.85, g = 0.15, b = 0.10 },
    NEUTRAL  = { r = 0.70, g = 0.70, b = 0.70 },
}

function CommanderOracle_Opposite(faction)
    if faction == "ALLIANCE" then return "HORDE" end
    if faction == "HORDE" then return "ALLIANCE" end
    return nil
end

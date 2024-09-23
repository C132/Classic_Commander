PartyPlannerSettings = {}
PartyPlanner = {}
PartyPlanner.DATA = {}

-- Constants
PartyPlanner.DATA.MAX_CHANNELS = 10

PartyPlanner.DATA.forbidenChannels = {
    "LocalDefense",
    "WorldDefense",
    "GuildRecruitment"
}

PartyPlanner.DATA.selectedInstance = nil

PartyPlanner.DATA.currentMessage = ""

PartyPlanner.DATA.INSTANCES = {
    {
        ["type"] = "Fill"
    },
    {
        ["name"] = "Ragefire Chasm",
        ["minLevel"] = 13,
        ["maxLevel"] = 16,
        ["abr"] = "RFC",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Deadmines",
        ["minLevel"] = 17,
        ["maxLevel"] = 21,
        ["abr"] = "DM",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Wailing Caverns",
        ["minLevel"] = 17,
        ["maxLevel"] = 23,
        ["abr"] = "WC",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Shadowfang Keep",
        ["minLevel"] = 18,
        ["maxLevel"] = 23,
        ["abr"] = "SFK",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Blackfathom Deeps",
        ["minLevel"] = 20,
        ["maxLevel"] = 27,
        ["abr"] = "BFD",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "The Stockade",
        ["minLevel"] = 23,
        ["maxLevel"] = 30,
        ["abr"] = "Stocks",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Razorfen Kraul",
        ["minLevel"] = 25,
        ["maxLevel"] = 32,
        ["abr"] = "RFK",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Gnomeregan",
        ["minLevel"] = 28,
        ["maxLevel"] = 35,
        ["abr"] = "Gnomer",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "SM: Graveyard",
        ["minLevel"] = 29,
        ["maxLevel"] = 35,
        ["abr"] = "SM:GY",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "SM: Library",
        ["minLevel"] = 31,
        ["maxLevel"] = 37,
        ["abr"] = "SM:Lib",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "SM: Armory",
        ["minLevel"] = 35,
        ["maxLevel"] = 40,
        ["abr"] = "SM:Arm",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "SM: Cathedral",
        ["minLevel"] = 36,
        ["maxLevel"] = 42,
        ["abr"] = "SM:Cath",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Razorfen Downs",
        ["minLevel"] = 37,
        ["maxLevel"] = 43,
        ["abr"] = "RFD",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Uldaman",
        ["minLevel"] = 41,
        ["maxLevel"] = 47,
        ["abr"] = "Ulda",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Zul'Farrak",
        ["minLevel"] = 44,
        ["maxLevel"] = 59,
        ["abr"] = "ZF",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Maraudon",
        ["minLevel"] = 47,
        ["maxLevel"] = 52,
        ["abr"] = "Mara",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Blackrock Depths",
        ["minLevel"] = 49,
        ["maxLevel"] = 53,
        ["abr"] = "BRD",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Sunken Temple",
        ["minLevel"] = 50,
        ["maxLevel"] = 55,
        ["abr"] = "ST",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Dire Maul East",
        ["minLevel"] = 57,
        ["maxLevel"] = 60,
        ["abr"] = "DM: East",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Dire Maul West",
        ["minLevel"] = 57,
        ["maxLevel"] = 60,
        ["abr"] = "DM: West",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Dire Maul North",
        ["minLevel"] = 57,
        ["maxLevel"] = 60,
        ["abr"] = "DM: North",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Stratholme",
        ["minLevel"] = 58,
        ["maxLevel"] = 60,
        ["abr"] = "Strat",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Scholomance",
        ["minLevel"] = 58,
        ["maxLevel"] = 60,
        ["abr"] = "Scholo",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Lower Blackrock Spire",
        ["minLevel"] = 58,
        ["maxLevel"] = 60,
        ["abr"] = "LBRS",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["name"] = "Upper Blackrock Spire",
        ["minLevel"] = 58,
        ["maxLevel"] = 60,
        ["abr"] = "UBRS",
        ["groupSize"] = 5,
        ["type"] = "Dungeon"
    },
    {
        ["type"] = "Fill"
    },
    {
        ["name"] = "Molten Core",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "MC",
        ["groupSize"] = 40,
        ["type"] = "Raid"
    },
    {
        ["name"] = "Onyxia's Lair",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "Ony",
        ["groupSize"] = 40,
        ["type"] = "Raid"
    },
    {
        ["name"] = "Blackwing Lair",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "BWL",
        ["groupSize"] = 40,
        ["type"] = "Raid"
    },
    {
        ["name"] = "Zul'Gurub",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "ZG",
        ["groupSize"] = 20,
        ["type"] = "Raid"
    },
    {
        ["name"] = "Temple of Ahn'Qiraj",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "AQ40",
        ["groupSize"] = 40,
        ["type"] = "Raid"
    },
    {
        ["name"] = "Ruins of Ahn'Qiraj",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "AQ20",
        ["groupSize"] = 20,
        ["type"] = "Raid"
    },
    {
        ["name"] = "Naxxramas",
        ["minLevel"] = 60,
        ["maxLevel"] = 60,
        ["abr"] = "Naxx",
        ["groupSize"] = 40,
        ["type"] = "Raid"
    }
}


PartyPlanner.DATA.defaultLFMMessage = "LF%nM %i need %r"
PartyPlanner.DATA.defaultLFGMessage = " %l %c %r LFG %i"
PartyPlanner.DATA.currentMode = "LFM"

PartyPlanner.DATA.characterLevel = 0

PartyPlanner.DATA.timeSinceLastSend = 121
PartyPlanner.DATA.maxTrackedTime = 120

PartyPlanner.UI = CreateFrame("FRAME", "partyPlanner-root", UIParent, "BasicFrameTemplate")
PartyPlanner.UI.isReady = false
PartyPlanner.UI.PP_DARK_FONT_COLOR = "|cFF222222"

-- Backdrops
PartyPlanner.UI.PP_BACKDROP = CopyTable(BACKDROP_ACHIEVEMENTS_0_64)
PartyPlanner.UI.PP_BACKDROP.bgFile = "Interface\\AdventureMap\\AdventureMapParchmentTile"
PartyPlanner.UI.PP_BACKDROP.insets = { left = 24, right = 24, top = 22, bottom = 24 }


-- Data for me:

-- local borderFiles = {
--     ["UI-DialogBox-TestWatermark-Border"] = "Interface\\DialogFrame\\UI-DialogBox-TestWatermark-Border",
--     ["UI-DialogBox-Border"] = "Interface\\DialogFrame\\UI-DialogBox-Border",
--     ["UI-DialogBox-Gold-Border"] = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
--     ["UI-Toast-Border"] = "Interface\\FriendsFrame\\UI-Toast-Border",
--     ["UI-SliderBar-Border"] = "Interface\\Buttons\\UI-SliderBar-Border",
--     ["UI-Arena-Border"] = "Interface\\ARENAENEMYFRAME\\UI-Arena-Border",
--     ["ChatBubble-Backdrop"] = "Interface\\Tooltips\\ChatBubble-Backdrop",
--     ["UI-Tooltip-Border"] = "Interface\\Tooltips\\UI-Tooltip-Border",
--     ["UI-TalentFrame-Active"] = "Interface\\TALENTFRAME\\UI-TalentFrame-Active",
-- }

-- local backgroundFiles = {
--     ["UI-Background-Rock"] = "Interface\\FrameGeneral\\UI-Background-Rock",
--     ["UI-Background-Marble"] = "Interface\\FrameGeneral\\UI-Background-Marble",
--     ["GarrisonMissionParchment"] = "Interface\\Garrison\\GarrisonMissionParchment",
--     ["AdventureMapParchmentTile"] = "Interface\\AdventureMap\\AdventureMapParchmentTile",
--     ["AdventureMapTileBg"] = "Interface\\AdventureMap\\AdventureMapTileBg",
--     ["Bank-Background"] = "Interface\\BankFrame\\Bank-Background",
--     ["UI-Party-Background"] = "Interface\\CharacterFrame\\UI-Party-Background",
--     ["GarrisonLandingPageMiddleTile"] = "Interface\\Garrison\\GarrisonLandingPageMiddleTile",
--     ["GarrisonMissionUIInfoBoxBackgroundTile"] = "Interface\\Garrison\\GarrisonMissionUIInfoBoxBackgroundTile",
--     ["GarrisonShipMissionParchment"] = "Interface\\Garrison\\GarrisonShipMissionParchment",
--     ["GarrisonUIBackground"] = "Interface\\Garrison\\GarrisonUIBackground",
--     ["GarrisonUIBackground2"] = "Interface\\Garrison\\GarrisonUIBackground2",
--     ["CollectionsBackgroundTile"] = "Interface\\Collections\\CollectionsBackgroundTile",
--     ["BlackMarketBackground-Tile"] = "Interface\\BlackMarket\\BlackMarketBackground-Tile",
-- }

-- Backdrops
-- BACKDROP_ACHIEVEMENTS_0_64
-- BACKDROP_ARENA_32_32
-- BACKDROP_DIALOG_32_32
-- BACKDROP_DARK_DIALOG_32_32
-- BACKDROP_DIALOG_EDGE_32
-- BACKDROP_GOLD_DIALOG_32_32
-- BACKDROP_WATERMARK_DIALOG_0_16
-- BACKDROP_SLIDER_8_8
-- BACKDROP_PARTY_32_32
-- BACKDROP_TOAST_12_12
-- BACKDROP_CALLOUT_GLOW_0_16
-- BACKDROP_CALLOUT_GLOW_0_20
-- BACKDROP_TEXT_PANEL_0_16
-- BACKDROP_CHARACTER_CREATE_TOOLTIP_32_32
-- BACKDROP_TUTORIAL_16_16

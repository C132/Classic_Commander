AnglerAtlasSettings = {}
AnglerAtlas = {}
AnglerAtlas.SKILL = {}
AnglerAtlas.PLAYER = {}
AnglerAtlas.STATE = {
    selectedFish = nil,
    selectedFishInfo = nil,
    selectedZone = nil,
    zones = {},
}
AnglerAtlas.DATA = {}
AnglerAtlas.DATA.zones = {
    ["11"] = {
        ["id"] = 11,
        ["name"] = "Wetlands",
        ["faction"] = "Contested",
        ["fishingLevel"] = 125,
        ["fishStats"] = {
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.49,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.24,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.17,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.02,
            },
        }
    },
    ["17"] = {
        ["id"] = 17,
        ["name"] = "The Barrens",
        ["faction"] = "Horde",
        ["fishingLevel"] = 100,
        ["fishStats"] = {
            -- Deviate Fish
            ["6522"] = {
                ["catchChance"] = 0.27,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.19,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.18,
            },
            -- Raw Brisstle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.07,
            },
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.07,
            },
            -- Raw Slitherskin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.05,
            },
        }
    },
    ["40"] = {
        ["id"] = 40,
        ["name"] = "Westfall",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 100,
        ["fishStats"] = {
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.41,
            },
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.21,
            },
            -- Raw Slitherskin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.14,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.04,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.01,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["130"] = {
        ["id"] = 130,
        ["name"] = "Silverpine Forest",
        ["faction"] = "Horde",
        ["fishingLevel"] = 100,
        ["fishStats"] = {
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.38,
            },
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.19,
            },
            -- Raw Slitherskin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.12,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Sagefish
            ["21071"] = {
                ["catchChance"] = 0.04,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.02,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["148"] = {
        ["id"] = 148,
        ["name"] = "Darkshore",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 100,
        ["fishStats"] = {
            -- Darkshore Grouper
            -- ["12238"] = {
            --     ["catchChance"] = 0.29,
            -- },
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.19,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.17,
            },
            -- Raw Slitherskin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.13,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.09,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.03,
            },
        }
    },
    ["267"] = {
        ["id"] = 267,
        ["name"] = "Hillsbrad Foothills",
        ["faction"] = "Contested",
        ["fishingLevel"] = 150,
        ["fishStats"] = {
            -- Raw Sagefish
            ["21071"] = {
                ["catchChance"] = 0.25,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.16,
            },
            -- Raw Brisstle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.15,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.12,
            },
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.10,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.08,
            },
        }
    },
    ["1497"] = {
        ["id"] = 1497,
        ["name"] = "Undercity",
        ["faction"] = "Horde",
        ["fishingLevel"] = 100,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.42,
            },
            -- Sickly Looking Fish
            -- ["6299"] = {
            --     ["catchChance"] = 0.15,
            -- },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.15,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.12,
            },
        }
    },
    ["33"] = {
        ["id"] = 33,
        ["name"] = "Stranglethorn Vale",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.18,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.18,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.16,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.07,
            },
            -- Raw Greater Sagefish
            ["21153"] = {
                ["catchChance"] = 0.05,
            },
            -- Stonescale Eel
            ["13422"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Mitril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Brisstle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.02,
            },
        }
    },
    ["16"] = {
        ["id"] = 16,
        ["name"] = "Azshara",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Darkclaw Lobster
            ["13888"] = {
                ["catchChance"] = 0.26,
            },
            -- Winter Squid
            ["13755"] = {
                ["catchChance"] = 0.14,
            },
            -- Stonescale Eel
            ["13422"] = {
                ["catchChance"] = 0.12,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.11,
            },
            -- Large Raw Mightfish
            ["13893"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.04,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Glossy Mightfish
            ["13754"] = {
                ["catchChance"] = 0.02,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.02,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.02,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.01,
            },
            -- Raw Summer Bass
            ["13756"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["405"] = {
        ["id"] = 405,
        ["name"] = "Desolace",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.27,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.18,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.15,
            },
            -- Raw Brisstle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.14,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.11,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.06,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["357"] = {
        ["id"] = 357,
        ["name"] = "Feralas",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.32,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.12,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.09,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.09,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.06,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.06,
            },
            -- Stonescale Eel
            ["13422"] = {
                ["catchChance"] = 0.05,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Glossy Mightfish
            ["13754"] = {
                ["catchChance"] = 0.02,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.02,
            },
            -- Winter Squid
            ["13755"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["440"] = {
        ["id"] = 440,
        ["name"] = "Tanaris",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.27,
            },
            -- Stonescale Eel
            ["13422"] = {
                ["catchChance"] = 0.14,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.14,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.08,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.07,
            },
            -- Raw Gossy Mightfish
            ["13754"] = {
                ["catchChance"] = 0.06,
            },
            -- Winter Squid
            ["13755"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Summer Bass
            ["13756"] = {
                ["catchChance"] = 0.02,
            },
        }
    },
    ["15"] = {
        ["id"] = 15,
        ["name"] = "Dustwallow Marsh",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.27,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.24,
            },
            -- Raw Brisstle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.13,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.11,
            },
            -- Oliy Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.10,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.10,
            },
        }
    },
    ["8"] = {
        ["id"] = 8,
        ["name"] = "Swamp of Sorrows",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.49,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.18,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.1,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.08,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.04,
            },
        }
    },
    ["406"] = {
        ["id"] = 406,
        ["name"] = "Stonetalon Mountains",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.51,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.28,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.08,
            },
            -- Raw Sagefish
            ["21071"] = {
                ["catchChance"] = 0.05,
            },
        }
    },
    ["45"] = {
        ["id"] = 45,
        ["name"] = "Arathi Highlands",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Mitril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.48,
            },
            -- Raw Bistle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.26,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.09,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.05,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.03,
            },
        }
    },
    ["47"] = {
        ["id"] = 47,
        ["name"] = "Hinterlands",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.24,
            },
            -- Raw Spotted Yellowtail
            ["4603"] = {
                ["catchChance"] = 0.21,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Glossy Mightfish
            ["13754"] = {
                ["catchChance"] = 0.06,
            },
            -- Stonescale Eel
            ["13422"] = {
                ["catchChance"] = 0.05,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.05,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Rockscale Cod
            ["6362"] = {
                ["catchChance"] = 0.05,
            },
            -- Winter Squid
            ["13755"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Suncale Salmon
            ["13760"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Summer Bass
            ["13756"] = {
                ["catchChance"] = 0.02,
            },
        }
    },
    ["331"] = {
        ["id"] = 331,
        ["name"] = "Ashenvale",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.39,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.21,
            },
            -- Raw Rainbow Fin Albacore
            ["6361"] = {
                ["catchChance"] = 0.21,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.08,
            },
            -- Raw Sagefish
            ["21071"] = {
                ["catchChance"] = 0.05,
            },
            -- Firefin Snapper
            ["6359"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["361"] = {
        ["id"] = 331,
        ["name"] = "Felwood",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.51,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.19,
            },
            -- Oliy Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.09,
            },
        }
    },
    ["493"] = {
        ["id"] = 493,
        ["name"] = "Moonglade",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.50,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.22,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.06,
            },
        }
    },
    ["490"] = {
        ["id"] = 490,
        ["name"] = "Un'Goro Crater",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.50,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.22,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.06,
            },
        }
    },
    ["28"] = {
        ["id"] = 28,
        ["name"] = "Western Plaguelands",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.50,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.20,
            },
            -- Oily Blackmouth
            ["6358"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.1,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.08,
            },
        }
    },
    ["1"] = {
        ["id"] = 1,
        ["name"] = "Dun Morogh",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.60,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.38,
            },
        }
    },
    ["215"] = {
        ["id"] = 215,
        ["name"] = "Mulgore",
        ["faction"] = "Horde",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.60,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.38,
            },
        }
    },
    ["12"] = {
        ["id"] = 12,
        ["name"] = "Elwynn Forest",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.59,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.37,
            },
        }
    },
    ["85"] = {
        ["id"] = 85,
        ["name"] = "Tirisfal Glades",
        ["faction"] = "Horde",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.45,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.29,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.02,
            },
            -- Raw Slitherskin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.01,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.01,
            },
        }
    },
    ["141"] = {
        ["id"] = 141,
        ["name"] = "Teldrassil",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Slither Skin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.58,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.25,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.16,
            },
        }
    },
    ["14"] = {
        ["id"] = 14,
        ["name"] = "Durotar",
        ["faction"] = "Horde",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Slither Skin Mackerel
            ["6303"] = {
                ["catchChance"] = 0.56,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.24,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.17,
            },
        }
    },
    ["1657"] = {
        ["id"] = 1657,
        ["name"] = "Darnassus",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.60,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.22,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.17,
            },
        }
    },
    ["1637"] = {
        ["id"] = 1637,
        ["name"] = "Orgrimmar",
        ["faction"] = "Horde",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.60,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.22,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.17,
            },
        }
    },
    ["1519"] = {
        ["id"] = 1519,
        ["name"] = "Stormwind City",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.60,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.22,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.17,
            },
        }
    },
    ["1638"] = {
        ["id"] = 1638,
        ["name"] = "Thunder Bluff",
        ["faction"] = "Horde",
        ["fishingLevel"] = 1,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.60,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.22,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.17,
            },
        }
    },
    ["4"] = {
        ["id"] = 4,
        ["name"] = "Blasted Lands",
        ["faction"] = "Contested",
        ["fishingLevel"] = 250,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.33,
            },
            -- Deviate Fish
            ["6522"] = {
                ["catchChance"] = 0.12,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.09,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.09,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.03,
            },
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.03,
            },
        }
    },
    ["1377"] = {
        ["id"] = 1377,
        ["name"] = "Silithus",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.37,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.22,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.06,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.04,
            },
        }
    },
    ["38"] = {
        ["id"] = 38,
        ["name"] = "Loch Modan",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.31,
            },
            -- Raw Sagefish
            ["21071"] = {
                ["catchChance"] = 0.19,
            },
            -- Raw Brisstle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.12,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.09,
            },
        }
    },
    ["10"] = {
        ["id"] = 10,
        ["name"] = "Duskwood",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.46,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.30,
            },
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Brilliant Smallfish
            ["6291"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.02,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.02,
            },
        }
    },
    ["44"] = {
        ["id"] = 44,
        ["name"] = "Redridge Mountains",
        ["faction"] = "Alliance",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.64,
            },
            -- Raw Longjaw Mud Snapper
            ["6289"] = {
                ["catchChance"] = 0.35,
            },
        }
    },
    ["400"] = {
        ["id"] = 400,
        ["name"] = "Thousand Needles",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.62,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.35,
            },
        }
    },
    ["36"] = {
        ["id"] = 36,
        ["name"] = "Alterac Mountains",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Greater Sagefish
            ["21153"] = {
                ["catchChance"] = 0.49,
            },
            -- Raw Mithril Head Trout
            ["8365"] = {
                ["catchChance"] = 0.24,
            },
            -- Raw Bristle Whisker Catfish
            ["6308"] = {
                ["catchChance"] = 0.13,
            },
        }
    },
    ["618"] = {
        ["id"] = 618,
        ["name"] = "Winterspring",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.39,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.20,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.11,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.09,
            },
        }
    },
    ["41"] = {
        ["id"] = 41,
        ["name"] = "Deadwind Pass",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.40,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.19,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.11,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.05,
            },
        }
    },
    ["139"] = {
        ["id"] = 139,
        ["name"] = "Eastern Plaguelands",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.37,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.19,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.11,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.05,
            },
        }
    },
    ["46"] = {
        ["id"] = 46,
        ["name"] = "Burning Steppes",
        ["faction"] = "Contested",
        ["fishingLevel"] = 300,
        ["fishStats"] = {
            -- Raw Whitescale Salmon
            ["13889"] = {
                ["catchChance"] = 0.15,
            },
            -- Raw Sunscale Salmon
            ["13760"] = {
                ["catchChance"] = 0.08,
            },
            -- Raw Nightfin Snapper
            ["13759"] = {
                ["catchChance"] = 0.05,
            },
            -- Raw Redgill
            ["13758"] = {
                ["catchChance"] = 0.02,
            },
        }
    }

}

---------------------------------
AnglerAtlas.DATA.fish = {
    ["13888"] = {
        ["name"] = "Darkclaw Lobster",
        ["type"] = "C",
        ["minimumFishingLevel"] = 330,
        ["avoidGetawayLevel"] = 425,
        ["fishedIn"] = {
            "16" -- Azshara
        }
    },
    ["6522"] = {
        ["name"] = "Deviate Fish",
        ["type"] = "I",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 75,
        ["isBuffFish"] = true,
        ["isAlchemicFish"] = true,
        ["fishedIn"] = {
            "17", -- The Barrens
            "4" -- Blasted Lands
        }
    },
    ["6359"] = {
        ["name"] = "Firefin Snapper",
        ["type"] = "C",
        ["minimumFishingLevel"] = 55,
        ["avoidGetawayLevel"] = 150,
        ["isAlchemicFish"] = true,
        ["fishedIn"] = {
            "33", -- Stranglethorn Vale
            "11", -- Wetlands
            "405", -- Desolace
            "440", -- Tanaris
            "267", -- Hillsbrad Foothills
            "15", -- Dustwallow Marsh
            "8", -- Swamp of Sorrows
            "406", -- Stonetalon Mountains
            "45", -- Arathi Highlands
            "357", -- Feralas
            "47", -- Hinterlands
            "331", -- Ashenvale
            "16" -- Azshara
        }
    },
    ["13893"] = {
        ["name"] = "Large Raw Mightfish",
        ["type"] = "C",
        ["minimumFishingLevel"] = 330,
        ["avoidGetawayLevel"] = 425,
        ["isBuffFish"] = true,
        ["fishedIn"] = {
            "16" -- Azshara
        }
    },
    ["6358"] = {
        ["name"] = "Oily Blackmouth",
        ["type"] = "C",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 75,
        ["isAlchemicFish"] = true,
        ["fishedIn"] = {
            "40", -- Westfall
            "130", -- Silverpine Forest
            "11", -- Wetlands
            "17", -- The Barrens
            "148", -- Darkshore
            "267", -- Hillsbrad Foothills
            "33", -- Stranglethorn Vale
            "405", -- Desolace
            "15", -- Dustwallow Marsh
            "361", -- Felwood
            "493", -- Moonglade
            "8", -- Swamp of Sorrows
            "490", -- Un'Goro Crater
            "28", -- Western Plaguelands
            "357", -- Feralas
            "331", -- Ashenvale
            "440", -- Tanaris
            "45", -- Arathi Highlands
            "47", -- Hinterlands
            "16" -- Azshara
        }
    },
    ["6291"] = {
        ["name"] = "Raw Brilliant Smallfish",
        ["type"] = "I",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 25,
        ["fishedIn"] = {
            "1", -- Dun Morogh
            "215", -- Mulgore
            "12", -- Elwynn Forest
            "85", -- Tirisfal Glades
            "141", -- Teldrassil
            "14", -- Durotar
            "1657", -- Darnassus
            "1637", -- Orgrimmar
            "1519", -- Stormwind City
            "1638", -- Thunder Bluff
            "1497", -- Undercity
            "4", -- Blasted Lands
            "38", -- Loch Modan
            "17", -- The Barrens
            "10", -- Duskwood
            "148", -- Darkshore
            "130", -- Silverpine Forest
            "40", -- Westfall
        }
    },
    ["6308"] = {
        ["name"] = "Raw Bristle Whisker Catfish",
        ["type"] = "I",
        ["minimumFishingLevel"] = 55,
        ["avoidGetawayLevel"] = 150,
        ["fishedIn"] = {
            "44", -- Redridge Mountains
            "406", -- Stonetalon Mountains
            "10", -- Duskwood
            "331", -- Ashenvale
            "400", -- Thousand Needles
            "45", -- Arathi Highlands
            "1657", -- Darnassus
            "1637", -- Orgrimmar
            "1519", -- Stormwind City
            "1638", -- Thunder Bluff
            "267", -- Hillsbrad Foothills
            "1497", -- Undercity
            "405", -- Desolace
            "36", -- Alterac Mountains
            "15", -- Dustwallow Marsh
            "38", -- Loch Modan
            "4", -- Blasted Lands
            "17", -- The Barrens
            "8", -- Swamp of Sorrows
            "148", -- Darkshore
            "130", -- Silverpine Forest
            "11", -- Wetlands
            "33", -- Stranglethorn Vale
            "40", -- Westfall
            "85", -- Tirisfal Glades

        }
    },
    ["13754"] = {
        ["name"] = "Raw Glossy Mightfish",
        ["type"] = "C",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["isBuffFish"] = true,
        ["fishedIn"] = {
            "440", -- Tanaris
            "47", -- Hinterlands
            "16", -- Azshara
            "357", -- Feralas
        }
    },
    ["21153"] = {
        ["name"] = "Raw Greater Sagefish",
        ["type"] = "I",
        ["minimumFishingLevel"] = 130,
        ["avoidGetawayLevel"] = 225,
        ["isBuffFish"] = true,
        ["fishedIn"] = {
            "36", -- Alterac Mountains
            "33", -- Stranglethorn Vale
        }
    },
    ["6289"] = {
        ["name"] = "Raw Longjaw Mud Snapper",
        ["type"] = "I",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 75,
        ["fishedIn"] = {
            "1657", -- Darnassus
            "1637", -- Orgrimmar
            "1519", -- Stormwind City
            "1638", -- Thunder Bluff
            "1497", -- Undercity
            "1", -- Dun Morogh
            "215", -- Mulgore
            "12", -- Elwynn Forest
            "44", -- Redridge Mountains
            "4", -- Blasted Lands
            "38", -- Loch Modan
            "10", -- Duskwood
            "85", -- Tirisfal Glades
            "406", -- Stonetalon Mountains
            "331", -- Ashenvale
            "17", -- The Barrens
            "14", -- Durotar
            "141", -- Teldrassil
            "148", -- Darkshore
            "267", -- Hillsbrad Foothills
            "130", -- Silverpine Forest
            "40", -- Westfall
        }
    },
    ["8365"] = {
        ["name"] = "Raw Mithril Head Trout",
        ["type"] = "I",
        ["minimumFishingLevel"] = 130,
        ["avoidGetawayLevel"] = 225,
        ["fishedIn"] = {
            "400", -- Thousand Needles
            "45", -- Arathi Highlands
            "405", -- Desolace
            "36", -- Alterac Mountains
            "15", -- Dustwallow Marsh
            "361", -- Felwood
            "493", -- Moonglade
            "490", -- Un'Goro Crater
            "28", -- Western Plaguelands
            "8", -- Swamp of Sorrows
            "357", -- Feralas
            "47", -- Hinterlands
            "33", -- Stranglethorn Vale
            "85", -- Tirisfal Glades
        }
    },
    ["13759"] = {
        ["name"] = "Raw Nightfin Snapper",
        ["type"] = "I",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["isBuffFish"] = true,
        ["requirements"] = {
            "Increased chance to catch between 00:00 and 06:00.",
            "Unavailable between 12:00 and 18:00."
        },
        ["fishedIn"] = {
            "493", -- Moonglade
            "490", -- Un'Goro Crater
            "28", -- Western Plaguelands
            "618", -- Winterspring
            "41", -- Deadwind Pass
            "139", -- Eastern Plaguelands
            "361", -- Felwood
            "357", -- Feralas
            "47", -- Hinterlands
            "1377", -- Silithus
            "46", -- Burning Steppes
            "10", -- Duskwood
            "16", -- Azshara
        }
    },
    ["6361"] = {
        ["name"] = "Raw Rainbow Fin Albacore",
        ["type"] = "C",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 75,
        ["fishedIn"] = {
            "11", -- Wetlands
            "331", -- Ashenvale
            "40", -- Westfall
            "148", -- Darkshore
            "130", -- Silverpine Forest
            "267", -- Hillsbrad Foothills
            "17", -- The Barrens
        }
    },
    ["13758"] = {
        ["name"] = "Raw Redgill",
        ["type"] = "I",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["fishedIn"] = {
            "361", -- Felwood
            "493", -- Moonglade
            "490", -- Un'Goro Crater
            "28", -- Western Plaguelands
            "357", -- Feralas
            "47", -- Hinterlands
            "139", -- Eastern Plaguelands
            "41", -- Deadwind Pass
            "618", -- Winterspring
            "16", -- Azshara
            "1377", -- Silithus
            "46", -- Burning Steppes
            "405", -- Desolace
            "331", -- Ashenvale
        }
    },
    ["6362"] = {
        ["name"] = "Raw Rockscale Cod",
        ["type"] = "C",
        ["minimumFishingLevel"] = 130,
        ["avoidGetawayLevel"] = 225,
        ["fishedIn"] = {
            "8", -- Swamp of Sorrows
            "15", -- Dustwallow Marsh
            "405", -- Desolace
            "33", -- Stranglethorn Vale
            "45", -- Arathi Highlands
            "440", -- Tanaris
            "47", -- Hinterlands
            "16", -- Azshara
            "357", -- Feralas
        }
    },
    ["21071"] = {
        ["name"] = "Raw Sagefish",
        ["type"] = "I",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 75,
        ["isBuffFish"] = true,
        ["fishedIn"] = {
            "267", -- Hillsbrad Foothills
            "38", -- Loch Modan
            "331", -- Ashenvale
            "406", -- Stonetalon Mountains
            "130", -- Silverpine Forest
        }
    },
    ["6303"] = {
        ["name"] = "Raw Slitherskin Mackerel",
        ["type"] = "C",
        ["minimumFishingLevel"] = 1,
        ["avoidGetawayLevel"] = 25,
        ["fishedIn"] = {
            "141", -- Teldrassil
            "14", -- Durotar
            "40", -- Westfall
            "148", -- Darkshore
            "130", -- Silverpine Forest
            "17", -- The Barrens
            "85", -- Tirisfal Glades
        }
    },
    ["4603"] = {
        ["name"] = "Raw Spotted Yellowtail",
        ["type"] = "C",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["fishedIn"] = {
            "440", -- Tanaris
            "47", -- Hinterlands
            "8", -- Swamp of Sorrows
            "16", -- Azshara
            "15", -- Dustwallow Marsh
            "357", -- Feralas
            "33", -- Stranglethorn Vale
            "405", -- Desolace
            "45", -- Arathi Highlands
        }
    },
    ["13756"] = {
        ["name"] = "Raw Summer Bass",
        ["type"] = "C",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["isBuffFish"] = true,
        ["requirements"] = {
            "Only available between the Spring Equinox and the Autumn Equinox",
            "Unavailable between 00:00 and 06:00.",
        },
        ["fishedIn"] = {
            "47", -- Hinterlands
            "440", -- Tanaris
            "16", -- Azshara
        }
    },
    ["13760"] = {
        ["name"] = "Raw Sunscale Salmon",
        ["type"] = "I",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["isBuffFish"] = true,
        ["fishedIn"] = {
            "1377", -- Silithus
            "41", -- Deadwind Pass
            "139", -- Eastern Plaguelands
            "618", -- Winterspring
            "361", -- Felwood
            "46", -- Burning Steppes
            "28", -- Western Plaguelands
            "357", -- Feralas
            "493", -- Moonglade
            "490", -- Un'Goro Crater
            "4", -- Blasted Lands
            "47", -- Hinterlands
            "10", -- Duskwood

        }
    },
    ["13889"] = {
        ["name"] = "Raw Whitescale Salmon",
        ["type"] = "I",
        ["minimumFishingLevel"] = 330,
        ["avoidGetawayLevel"] = 425,
        ["fishedIn"] = {
            "41", -- Deadwind Pass
            "618", -- Winterspring
            "139", -- Eastern Plaguelands
            "1377", -- Silithus
            "46", -- Burning Steppes
            "10", -- Duskwood
            "4", -- Blasted Lands
        }
    },
    ["13422"] = {
        ["name"] = "Stonescale Eel",
        ["type"] = "C",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["isAlchemicFish"] = true,
        ["requirements"] = {
            "Increased chance to catch between 00:00 and 12:00.",
            "Decreased chance to catch between 12:00 and 00:00."
        },
        ["fishedIn"] = {
            "440", -- Tanaris
            "16", -- Azshara
            "357", -- Feralas
            "33", -- Stranglethorn Vale
            "47" -- Hinterlands
        }
    },
    ["13755"] = {
        ["name"] = "Winter Squid",
        ["type"] = "C",
        ["minimumFishingLevel"] = 205,
        ["avoidGetawayLevel"] = 300,
        ["isBuffFish"] = true,
        ["requirements"] = {
            "Only available between the Autumn Equinox and the Spring Equinox",
            "Unavailable between 00:00 and 06:00."
        },
        ["fishedIn"] = {
            "16", -- Azshara
            "440", -- Tanaris
            "47", -- Hinterlands
            "357", -- Feralas
        }
    }
}

AnglerAtlas.DATA.recipes = {
    --|   Darkclaw Lobster
    ["13888"] = {
        {
            ["productId"] = "18245",
            ['productQ'] = 1,
            ["recipeName"] = "Lobster Stew",
            ['reagents'] = {
                -- Darkclaw Lobster
                {
                    ["itemId"] = "13888",
                    ["itemQ"] = 1
                },
                -- Refreshing Spring Water
                {
                    ["itemId"] = "159",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13947"

        }
    },
    --|   Deviate Fish
    ["6522"] = {
        {
            ["productId"] = "6657",
            ['productQ'] = 1,
            ["recipeName"] = "Savory Deviate Delight",
            ['reagents'] = {
                -- Deviate Fish
                {
                    ["itemId"] = "6522",
                    ["itemQ"] = 1
                },
                -- Mild Spices
                {
                    ["itemId"] = "2678",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6661"
        },
        {
            ["productId"] = "6662",
            ['productQ'] = 1,
            ["recipeName"] = "Elixir of Giant Growth",
            ['reagents'] = {
                -- Deviate Fish
                {
                    ["itemId"] = "6522",
                    ["itemQ"] = 1
                },
                -- Earthroot
                {
                    ["itemId"] = "2449",
                    ["itemQ"] = 1
                },
                -- Empty Vial
                {
                    ["itemId"] = "3371",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6663"
        }
    },
    --|   Firefin Snapper
    ["6359"] = {
        {
            ["productId"] = "6371",
            ['productQ'] = 1,
            ["recipeName"] = "Fire Oil",
            ['reagents'] = {
                -- Firefin Snapper
                {
                    ["itemId"] = "6359",
                    ["itemQ"] = 2
                },
                -- Empty Vial
                {
                    ["itemId"] = "3371",
                    ["itemQ"] = 1
                },
            }
        }
    },
    --|   Large Raw Mightfish
    ["13893"] = {
        {
            ["productId"] = "13934",
            ['productQ'] = 1,
            ["recipeName"] = "Mightfish Steak",
            ['reagents'] = {
                -- Large Raw Mightfish
                {
                    ["itemId"] = "13893",
                    ["itemQ"] = 1
                },
                -- Hot Spices
                {
                    ["itemId"] = "2692",
                    ["itemQ"] = 1
                },
                -- Soothing Spices
                {
                    ["itemId"] = "3713",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13948"
        }
    },
    --|   Oily Blackmouth
    ["6358"] = {
        {
            ["productId"] = "6370",
            ['productQ'] = 1,
            ["recipeName"] = "Blackmouth Oil",
            ['reagents'] = {
                -- Oily Blackmouth
                {
                    ["itemId"] = "6358",
                    ["itemQ"] = 2
                },
                -- Empty Vial
                {
                    ["itemId"] = "3371",
                    ["itemQ"] = 1
                },
            }
        }
    },
    --|   Raw Brilliant Smallfish
    ["6291"] = {
        {
            ["productId"] = "6290",
            ['productQ'] = 1,
            ["recipeName"] = "Brilliant Smallfish",
            ['reagents'] = {
                -- Raw Brilliant Smallfish
                {
                    ["itemId"] = "6291",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6325"
        }
    },
    --|   Raw Bristle Whisker Catfish
    ["6308"] = {
        {
            ["productId"] = "4593",
            ['productQ'] = 1,
            ["recipeName"] = "Bristle Whisker Catfish",
            ['reagents'] = {
                -- Raw Bristle Whisker Catfish
                {
                    ["itemId"] = "6308",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6330"
        },
    },
    --|   Raw Glossy Mightfish
    ["13754"] = {
        {
            ["productId"] = "13927",
            ['productQ'] = 1,
            ["recipeName"] = "Cooked Glossy Mightfish",
            ['reagents'] = {
                -- Raw Glossy Mightfish
                {
                    ["itemId"] = "13754",
                    ["itemQ"] = 1
                },
                -- Soothing Spices
                {
                    ["itemId"] = "3713",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13940"
        }
    },
    --|   Raw Greater Sagefish
    ["21153"] = {
        {
            ["productId"] = "21217",
            ['productQ'] = 1,
            ["recipeName"] = "Sagefish Delight",
            ['reagents'] = {
                -- Raw Greater Sagefish
                {
                    ["itemId"] = "21153",
                    ["itemQ"] = 1
                },
                -- Hot Spices
                {
                    ["itemId"] = "2692",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "21219"
        }
    },
    --|   Raw Longjaw Mud Snapper
    ["6289"] = {
        {
            ["productId"] = "4592",
            ['productQ'] = 1,
            ["recipeName"] = "Longjaw Mud Snapper",
            ['reagents'] = {
                -- Raw Longjaw Mud Snapper
                {
                    ["itemId"] = "6289",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6328"
        }
    },
    --|   Raw Mithril Head Trout
    ["8365"] = {
        {
            ["productId"] = "8364",
            ['productQ'] = 1,
            ["recipeName"] = "Mithril Head Trout",
            ['reagents'] = {
                -- Raw Mithril Head Trout
                {
                    ["itemId"] = "8365",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "17062"
        }
    },
    --|   Raw Nightfin Snapper
    ["13759"] = {
        {
            ["productId"] = "13931",
            ['productQ'] = 1,
            ["recipeName"] = "Nightfin Soup",
            ['reagents'] = {
                -- Raw Nightfin Snapper
                {
                    ["itemId"] = "13759",
                    ["itemQ"] = 1
                },
                -- Refreshing Spring Water
                {
                    ["itemId"] = "159",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13945"
        }
    },
    --|   Raw Rainbow Fin Albacore
    ["6361"] = {
        {
            ["productId"] = "5095",
            ['productQ'] = 1,
            ["recipeName"] = "Rainbow Fin Albacore",
            ['reagents'] = {
                -- Raw Rainbow Fin Albacore
                {
                    ["itemId"] = "6361",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6368"
        }
    },
    --|   Raw Redgill
    ["13758"] = {
        {
            ["productId"] = "13930",
            ['productQ'] = 1,
            ["recipeName"] = "Filet of Redgill",
            ['reagents'] = {
                -- Raw Redgill
                {
                    ["itemId"] = "13758",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13941"
        }
    },
    --|   Raw Rockscale Cod
    ["6362"] = {
        {
            ["productId"] = "4594",
            ['productQ'] = 1,
            ["recipeName"] = "Rockscale Cod",
            ['reagents'] = {
                -- Raw Rockscale Cod
                {
                    ["itemId"] = "6362",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6369"
        }
    },
    --|   Raw Sagefish
    ["21071"] = {
        {
            ["productId"] = "21072",
            ['productQ'] = 1,
            ["recipeName"] = "Smoked Sagefish",
            ['reagents'] = {
                -- Raw Sagefish
                {
                    ["itemId"] = "21071",
                    ["itemQ"] = 1
                },
                -- Mild Spices
                {
                    ["itemId"] = "2678",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "21099"
        }
    },
    --|   Raw Slitherskin Mackerel
    ["6303"] = {
        {
            ["productId"] = "787",
            ['productQ'] = 1,
            ["recipeName"] = "Slitherskin Mackerel",
            ['reagents'] = {
                -- Raw Slitherskin Mackerel
                {
                    ["itemId"] = "6303",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "6326"
        }
    },
    --|   Raw Spotted Yellowtail
    ["4603"] = {
        {
            ["productId"] = "6887",
            ['productQ'] = 1,
            ["recipeName"] = "Spotted Yellowtail",
            ['reagents'] = {
                -- Raw Spotted Yellowtail
                {
                    ["itemId"] = "4603",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13939"
        }
    },
    --|   Raw Summer Bass
    ["13756"] = {
        {
            ["productId"] = "13929",
            ['productQ'] = 1,
            ["recipeName"] = "Hot Smoked Bass",
            ['reagents'] = {
                -- Raw Summer Bass
                {
                    ["itemId"] = "13756",
                    ["itemQ"] = 1
                },
                -- Hot Spices
                {
                    ["itemId"] = "2692",
                    ["itemQ"] = 2
                },
            },
            ["recipeItemId"] = "13943"
        }
    },
    --|   Raw Sunscale Salmon
    ["13760"] = {
        {
            ["productId"] = "13932",
            ['productQ'] = 1,
            ["recipeName"] = "Poached Sunscale Salmon",
            ['reagents'] = {
                -- Raw Sunscale Salmon
                {
                    ["itemId"] = "13760",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13946"
        }
    },
    --|   Raw Whitescale Salmon
    ["13889"] = {
        {
            ["productId"] = "13935",
            ['productQ'] = 1,
            ["recipeName"] = "Baked Salmon",
            ['reagents'] = {
                -- Raw Whitescale Salmon
                {
                    ["itemId"] = "13889",
                    ["itemQ"] = 1
                },
                -- Soothing Spices
                {
                    ["itemId"] = "3713",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13949"
        }
    },
    --|   Stonescale Eel
    ["13422"] = {
        {
            ["productId"] = "13423",
            ['productQ'] = 1,
            ["recipeName"] = "Stonescale Oil",
            ['reagents'] = {
                -- Stonescale Eel
                {
                    ["itemId"] = "13422",
                    ["itemQ"] = 2
                },
                -- Leaded Vial
                {
                    ["itemId"] = "3372",
                    ["itemQ"] = 1
                },
            }
        }
    },
    --|   Winter Squid
    ["13755"] = {
        {
            ["productId"] = "13928",
            ['productQ'] = 1,
            ["recipeName"] = "Grilled Squid",
            ['reagents'] = {
                -- Winter Squid
                {
                    ["itemId"] = "13755",
                    ["itemQ"] = 1
                },
                -- Soothing Spices
                {
                    ["itemId"] = "3713",
                    ["itemQ"] = 1
                },
            },
            ["recipeItemId"] = "13942"
        }
    }
}

AnglerAtlas.DATA.equipment = {
    ["gear"] = {
        {
            ["id"] = 19972,
            ["order"] = 1,
            ["desc"] = "Reward for turning in a rare Keefer’s Angelfish during the Stranglethorn Fishing Extravaganza."
        },
        {
            ["id"] = 19969,
            ["order"] = 2,
            ["desc"] = "Reward for turning in a rare Brownell’s Blue Striped Racer during the Stranglethorn Fishing Extravaganza."
        },
    },
    ["rods"] = {
        {
            ["id"] = 6256,
            ["order"] = 1,
            ["desc"] = "Sold by vendors accross the world."
        },
        {
            ["id"] = 12225,
            ["order"] = 2,
            ["desc"] = "Alliance only. Quest reward from \"The Family and the Fishing Pole\" from Gubber Blump south west of Auberdine in Darkshore."
        },
        {
            ["id"] = 6365,
            ["order"] = 3,
            ["desc"] = "Sold by vendors accross the world in limmited stock."
        },
        {
            ["id"] = 6366,
            ["order"] = 4,
            ["desc"] = "Extremely rare drop from inland fishing spots in 10-20 zones."
        },
        {
            ["id"] = 6367,
            ["order"] = 5,
            ["desc"] = "Found in \"Shellfish Trap\" in SW corner of Desolace. ~1% drop rate."
        },
        {
            ["id"] = 19022,
            ["order"] = 6,
            ["desc"] = "Horde only. Quest reward from \"Snapjaws, Mon!\" from Katoom the Angler on the eastern shore of the Hinterlands."
        },
        {
            ["id"] = 19970,
            ["order"] = 7,
            ["desc"] = "Reward for winning the prestigious Stranglethorn Fishing Extravaganza."
        },
    },
    ["lures"] = {
        {
            ["id"] = 6529,
            ["order"] = 1,
            ["desc"] = "Sold by vendors accross the world."
        },
        {
            ["id"] = 6530,
            ["order"] = 2,
            ["desc"] = "Sold by vendors accross the world."
        },
        {
            ["id"] = 6532,
            ["order"] = 3,
            ["desc"] = "Sold by vendors accross the world."
        },
        {
            ["id"] = 6533,
            ["order"] = 4,
            ["desc"] = "Sold by vendors accross the world in limmited supply"
        },
    },
    ["other"] = {
        {
            ["id"] = 19971,
            ["order"] = 1,
            ["desc"] = "Reward for turning in a rare Dezian Queenfish during the Stranglethorn Fishing Extravaganza. This is a permanent +5 fishing to a pole."
        },
        {
            ["id"] = 11152,
            ["order"] = 2,
            ["desc"] = "Enchanters can find this recipe on the murlocs in Hillsbrad Foothills."
        }
    }
}

AnglerAtlas.skillRankNames = {
    {
        ["name"]= "Apprentice",
        ["rank"]= 149
    },
    {
        ["name"]= "Journeyman",
        ["rank"]= 224
    },
    {
        ["name"]= "Expert",
        ["rank"]= 299
    },
    {
        ["name"]= "Artisan",
        ["rank"]= 300
    }
}

AnglerAtlas.DATA.validFish = {}
for k in pairs(AnglerAtlas.DATA.fish) do table.insert(AnglerAtlas.DATA.validFish, k) end
AnglerAtlas.DATA.validZones = {}
for k in pairs(AnglerAtlas.DATA.zones) do table.insert(AnglerAtlas.DATA.validZones, k) end
    
AnglerAtlas.UI = CreateFrame("FRAME", "angler-root", UIParent, "BasicFrameTemplate")
AnglerAtlas.UI.ANGLER_DARK_FONT_COLOR = "|cFF222222"

-- Backdrops
AnglerAtlas.UI.ANGLER_BACKDROP = CopyTable(BACKDROP_ACHIEVEMENTS_0_64)
AnglerAtlas.UI.ANGLER_BACKDROP.bgFile = "Interface\\AdventureMap\\AdventureMapParchmentTile"
AnglerAtlas.UI.ANGLER_BACKDROP.insets = { left = 24, right = 24, top = 22, bottom = 24 }

function AnglerAtlas:getRankNameForLevel(level)
    for i = 1, #AnglerAtlas.skillRankNames do
        if level <= AnglerAtlas.skillRankNames[i].rank then
            return AnglerAtlas.skillRankNames[i].name
        end
    end
    return "Apprentice"
end

function AnglerAtlas:loadPlayerData()
    -- print("Loading player data...")
    -- load player name and realm
    AnglerAtlas.PLAYER.name, AnglerAtlas.PLAYER.realm = UnitName("player")
    -- load player level
    AnglerAtlas.PLAYER.level = UnitLevel("player")

    AnglerAtlas.SKILL.hasFishing = false
    for skillIndex = 1, GetNumSkillLines() do
        -- skillName, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, isAbandonable, stepCost, rankCost, minLevel, skillCostType, skillDescription
        local skillName, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, isAbandonable, stepCost, rankCost, minLevel, skillCostType, skillDescription = GetSkillLineInfo(skillIndex)

        -- print(skillName)

        if skillName == "Fishing" then
            AnglerAtlas.SKILL.hasFishing = true
            -- print("---SKILL DATA---")
            -- print("skillName: " .. skillName)
            -- print("isExpanded: " .. tostring(isExpanded))
            -- print("skillRank: " .. skillRank)
            -- print("numTempPoints: " .. numTempPoints)
            -- print("skillModifier: " .. skillModifier)
            -- print("skillMaxRank: " .. skillMaxRank)
            -- print("isAbandonable: " .. tostring(isAbandonable))
            -- print("minLevel: " .. minLevel)
            -- print("skillCostType: " .. skillCostType)
            -- print("skillDescription: " .. skillDescription)
            -- print("----------------")
            AnglerAtlas.SKILL.level = skillRank
            AnglerAtlas.SKILL.maxLevel = skillMaxRank
            AnglerAtlas.SKILL.rankName = AnglerAtlas:getRankNameForLevel(skillRank)
            AnglerAtlas.SKILL.skillModifier = skillModifier
            AnglerAtlas.SKILL.modLevel = skillRank + skillModifier
        end
    end
end





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

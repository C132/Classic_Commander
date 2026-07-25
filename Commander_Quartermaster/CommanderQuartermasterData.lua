-- Commander Quartermaster — the consumables database.
-- Generated offline from a curated, web-verified item survey (see
-- prompts/commander-quartermaster.md); edit the generator, not this file's
-- item lists, when the database needs to change.
--
-- Shape:
--   Categories:      ordered list of { key, name, items = { entry... } }
--   entry:           { id, name, src, note, req?, era, rank }
--   Recommendations: [classToken] = { specs = { { key, name, role, picks } } }
--   pick:            { slot, note, entries = { { id, name, why } } }

local function I(id, name, src, note, req, era, rank)
    return {
        id = id, name = name, src = src, note = note,
        req = (req ~= "" and req) or nil,
        era = era, rank = rank,
    }
end

local function E(id, name, why)
    return { id = id, name = name, why = why }
end

CommanderQuartermasterData = {
    SlotOrder = {
        "FLASK", "BATTLE_ELIXIR", "GUARDIAN_ELIXIR", "FOOD",
        "WEAPON", "COMBAT_POTION", "RECOVERY_POTION", "EXTRAS",
    },
    SlotNames = {
        FLASK = "Flask",
        BATTLE_ELIXIR = "Battle Elixir",
        GUARDIAN_ELIXIR = "Guardian Elixir",
        FOOD = "Food",
        WEAPON = "Weapon",
        COMBAT_POTION = "Combat Potion",
        RECOVERY_POTION = "Recovery Potion",
        EXTRAS = "Extras",
    },
    SourceNames = {
        AH = "AH", VENDOR = "Vendor", CREATED = "Created", QUEST = "Quest",
        DROP = "Drop", BOP = "BoP", SEASONAL = "Event",
    },

    Categories = {
        { key = "FLASKS", name = "Flasks", items = {
            I(22851, "Flask of Fortification", "AH", "+500 health and +10 defense rating for 2 h, persists through death", "", "TBC", 1),
            I(22861, "Flask of Blinding Light", "AH", "+80 Arcane/Holy/Nature spell damage for 2 h, persists through death", "", "TBC", 1),
            I(22854, "Flask of Relentless Assault", "AH", "+120 attack power for 2 h, persists through death", "", "TBC", 1),
            I(22866, "Flask of Pure Death", "AH", "+80 Fire/Frost/Shadow spell damage for 2 h, persists through death", "", "TBC", 1),
            I(22853, "Flask of Mighty Restoration", "AH", "+25 mana per 5 for 2 h, persists through death", "", "TBC", 1),
        }},
        { key = "POTIONS_RECOVERY", name = "Recovery Potions", items = {
            I(22829, "Super Healing Potion", "AH", "Restores 1500-2500 health, 2 min cooldown", "", "TBC", 1),
            I(22832, "Super Mana Potion", "AH", "Restores 1800-3000 mana, 2 min cooldown", "", "TBC", 1),
        }},
    },

    Recommendations = {
        WARRIOR = { specs = {
            { key = "FURY", name = "Fury", role = "MELEE", picks = {
                { slot = "FLASK", note = "Flask on progression; elixir pair on farm.", entries = {
                    E(22854, "Flask of Relentless Assault", "Highest sustained AP"),
                }},
            }},
        }},
    },
}

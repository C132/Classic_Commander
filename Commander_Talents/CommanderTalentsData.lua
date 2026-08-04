-- Commander_Talents — shared data namespace.
-- The nine CommanderTalentsData_<Class>.lua files each fill one entry of
-- Classes; they are GENERATED (see prompts/commander-talents.md) and checked
-- by Harness/validate_class_data.lua — regenerate rather than hand-edit.

CommanderTalentsData = {
    Classes = {},

    -- In-game class order, matching Commander_Quartermaster's browser
    ClassOrder = {
        "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
        "SHAMAN", "MAGE", "WARLOCK", "DRUID",
    },
}

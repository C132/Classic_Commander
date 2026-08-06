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

-- PvP builds live in their own hand-curated file (CommanderTalentsPvP.lua),
-- appended after the generated class data — the Quartermaster fringe-loadout
-- precedent. The generated per-class files stay machine-owned; this is where
-- arena, battleground and duelling specs are added without touching them.
--
-- Each entry: { key, name, role, bracket, qmSpec, points, stats, notes }
--   bracket = ARENA | BG | DUEL | WORLD — what the build is FOR
--   qmSpec  = the Quartermaster spec key whose consumables suit it (or nil)
function CommanderTalentsData.AddPvPBuilds(classToken, builds)
    local class = CommanderTalentsData.Classes[classToken]
    if not class then return end        -- class data absent; skip silently
    class.pvpBuilds = class.pvpBuilds or {}
    local seen = {}
    for _, existing in ipairs(class.pvpBuilds) do
        seen[existing.key] = true
    end
    for _, build in ipairs(builds) do
        if build.key and not seen[build.key] then
            class.pvpBuilds[#class.pvpBuilds + 1] = build
            seen[build.key] = true
        end
    end
end

-- Commander Quartermaster — fringe-spec loadouts.
-- HAND-CURATED, unlike CommanderQuartermasterData.lua (which is generated and
-- must never be hand-edited): this file appends off-meta specs — Shockadin,
-- Smite Priest, Subtlety, the warlock tank, Dreamstate — to the generated
-- Recommendations at load. Rule of the file: every item ID here MUST already
-- exist in the generated database (categories or v1 recommendations), so the
-- web-verification the generator guarantees is never diluted. The harness
-- enforces this mechanically.

local Data = CommanderQuartermasterData
if not (Data and Data.Recommendations) then return end

local function E(id, name, why)
    return { id = id, name = name, why = why }
end

-- Append specs to a class, skipping keys that somehow already exist (a
-- future regeneration of the data file may absorb these)
local function AddSpecs(classToken, specs)
    local rec = Data.Recommendations[classToken]
    if not rec then return end
    local have = {}
    for _, spec in ipairs(rec.specs) do have[spec.key] = true end
    for _, spec in ipairs(specs) do
        if not have[spec.key] then
            rec.specs[#rec.specs + 1] = spec
        end
    end
end

-- ---------------------------------------------------------------------------
-- Paladin — Shockadin (Holy-tree spell DPS)
-- ---------------------------------------------------------------------------
AddSpecs("PALADIN", {
    { key = "SHOCKADIN", name = "Shockadin", role = "CASTER", picks = {
        { slot = "FLASK", note = "Fringe build — Holy Shock and Judgement are all Holy school, so Blinding Light is YOUR flask.", entries = {
            E(22861, "Flask of Blinding Light", "+80 Arcane/Holy/Nature — covers every spell you press"),
            E(13512, "Flask of Supreme Power", "+70 general spell damage, cheap vanilla fallback"),
            E(32900, "Shattrath Flask of Supreme Power", "Mark-of-Illidari freebie inside the big raids"),
        }},
        { slot = "BATTLE_ELIXIR", note = "", entries = {
            E(28103, "Adept's Elixir", "+24 damage +24 spell crit — crit feeds Illumination mana back"),
            E(13454, "Greater Arcane Elixir", "+35 spell damage when Adept's is scarce"),
        }},
        { slot = "GUARDIAN_ELIXIR", note = "", entries = {
            E(22840, "Elixir of Major Mageblood", "+16 mp5 — Shockadin mana is the real boss fight"),
            E(32067, "Elixir of Draenic Wisdom", "int/spirit budget option"),
        }},
        { slot = "FOOD", note = "", entries = {
            E(27657, "Blackened Basilisk", "+23 spell damage +20 spirit staple"),
            E(33825, "Skullfish Soup", "+20 spell crit — more Illumination returns"),
        }},
        { slot = "WEAPON", note = "", entries = {
            E(20749, "Brilliant Wizard Oil", "+36 damage +14 crit beats flat damage for crit builds"),
            E(22522, "Superior Wizard Oil", "+42 flat damage if you'd rather have throughput"),
        }},
        { slot = "COMBAT_POTION", note = "", entries = {
            E(22839, "Destruction Potion", "+120 damage +2% crit — line it up with Avenging Wrath"),
        }},
        { slot = "RECOVERY_POTION", note = "", entries = {
            E(22832, "Super Mana Potion", "chain from the pull; the spec runs dry fast"),
        }},
        { slot = "EXTRAS", note = "The mana economy is the whole fight.", entries = {
            E(12662, "Demonic Rune", "mana off the potion cooldown"),
            E(20520, "Dark Rune", "same rune, dungeon-farmed"),
            E(21177, "Symbol of Kings", "blessing reagent — never raid without a stack"),
        }},
    }},
})

-- ---------------------------------------------------------------------------
-- Priest — Smite (Holy DPS)
-- ---------------------------------------------------------------------------
AddSpecs("PRIEST", {
    { key = "SMITE", name = "Smite", role = "CASTER", picks = {
        { slot = "FLASK", note = "Fringe build — Smite and Holy Fire are Holy school; Blinding Light beats the generic caster flasks.", entries = {
            E(22861, "Flask of Blinding Light", "+80 Holy — the Smite flask"),
            E(13512, "Flask of Supreme Power", "+70 spell damage vanilla budget pick"),
            E(32900, "Shattrath Flask of Supreme Power", "cheap in-raid substitute"),
        }},
        { slot = "BATTLE_ELIXIR", note = "", entries = {
            E(28103, "Adept's Elixir", "+24 damage +24 crit — crit procs Surge of Light"),
            E(13454, "Greater Arcane Elixir", "flat +35 alternative"),
        }},
        { slot = "GUARDIAN_ELIXIR", note = "", entries = {
            E(22840, "Elixir of Major Mageblood", "+16 mp5 keeps the Smite spam funded"),
            E(32067, "Elixir of Draenic Wisdom", "int/spirit — spirit double-dips with Meditation"),
        }},
        { slot = "FOOD", note = "", entries = {
            E(27657, "Blackened Basilisk", "+23 spell damage staple"),
            E(33825, "Skullfish Soup", "+20 spell crit for Surge of Light fishing"),
        }},
        { slot = "WEAPON", note = "", entries = {
            E(20749, "Brilliant Wizard Oil", "+36 damage +14 crit"),
            E(22521, "Superior Mana Oil", "14 mp5 when mana wins over damage"),
        }},
        { slot = "COMBAT_POTION", note = "", entries = {
            E(22839, "Destruction Potion", "+120 damage +2% crit on burn windows"),
        }},
        { slot = "RECOVERY_POTION", note = "", entries = {
            E(22832, "Super Mana Potion", "on cooldown — Smite mana math never balances"),
        }},
        { slot = "EXTRAS", note = "", entries = {
            E(12662, "Demonic Rune", "mana off the potion cooldown"),
            E(20520, "Dark Rune", "Scholomance-farmed twin"),
            E(22836, "Major Dreamless Sleep Potion", "between-pull mana in dungeons"),
        }},
    }},
})

-- ---------------------------------------------------------------------------
-- Rogue — Subtlety (PvP / Hemo)
-- ---------------------------------------------------------------------------
AddSpecs("ROGUE", {
    { key = "SUBTLETY", name = "Subtlety", role = "MELEE", picks = {
        { slot = "FLASK", note = "PvP hits different — staying alive beats parse throughput.", entries = {
            E(22851, "Flask of Fortification", "+500 HP for arena and world-PvP staying power"),
            E(22854, "Flask of Relentless Assault", "+120 AP when you'd rather burst"),
        }},
        { slot = "BATTLE_ELIXIR", note = "", entries = {
            E(22831, "Elixir of Major Agility", "+35 agi +20 crit all-rounder"),
            E(28102, "Onslaught Elixir", "+60 AP burst alternative"),
        }},
        { slot = "GUARDIAN_ELIXIR", note = "", entries = {
            E(32068, "Elixir of Ironskin", "+30 resilience — the arena guardian pick"),
            E(32062, "Elixir of Major Fortitude", "+250 HP with regen elsewhere"),
        }},
        { slot = "FOOD", note = "", entries = {
            E(27659, "Warp Burger", "+20 agility staple"),
            E(27667, "Spicy Crawdad", "+30 stamina into burst teams"),
        }},
        { slot = "WEAPON", note = "Poisons ARE the weapon slot.", entries = {
            E(21927, "Instant Poison VII", "mainhand burst"),
            E(3776, "Crippling Poison II", "offhand snare — the Subtlety control game"),
            E(22055, "Wound Poison V", "against healer teams — the healing cut wins mauls"),
            E(9186, "Mind-numbing Poison III", "caster-lock alternative"),
        }},
        { slot = "COMBAT_POTION", note = "", entries = {
            E(5634, "Free Action Potion", "pre-pot before the opener — stun immunity wins games"),
            E(20008, "Living Action Potion", "the reactive version: breaks what's already on you"),
        }},
        { slot = "RECOVERY_POTION", note = "", entries = {
            E(22829, "Super Healing Potion", "emergency button between Cheap Shots"),
        }},
        { slot = "EXTRAS", note = "The reset kit — Subtlety wins by leaving the fight first.", entries = {
            E(7676, "Thistle Tea", "40 energy at 70 — opener fuel"),
            E(22826, "Sneaking Potion", "deeper stealth for the opener"),
            E(9172, "Invisibility Potion", "drop combat, force the restart"),
            E(21991, "Heavy Netherweave Bandage", "restealth, bandage, come back ahead"),
        }},
    }},
})

-- ---------------------------------------------------------------------------
-- Warlock — Demo Tank (the Leotheras / Illidan niche)
-- ---------------------------------------------------------------------------
AddSpecs("WARLOCK", {
    { key = "TANK", name = "Demo Tank", role = "TANK", picks = {
        { slot = "FLASK", note = "The Leotheras and Illidan demon-phase job: stamina first, threat second.", entries = {
            E(22851, "Flask of Fortification", "+500 HP +10 def — you are a tank now"),
        }},
        { slot = "BATTLE_ELIXIR", note = "", entries = {
            E(28103, "Adept's Elixir", "+24 spell damage — Searing Pain threat"),
            E(22835, "Elixir of Major Shadow Power", "+55 shadow for a shadow-threat build"),
        }},
        { slot = "GUARDIAN_ELIXIR", note = "", entries = {
            E(32062, "Elixir of Major Fortitude", "+250 HP standard"),
            E(22834, "Elixir of Major Defense", "+550 armor into melee phases"),
            E(32063, "Earthen Elixir", "flat 20-per-hit shave on spell-heavy phases"),
        }},
        { slot = "FOOD", note = "", entries = {
            E(27667, "Spicy Crawdad", "+30 stamina — biggest health food"),
            E(27663, "Blackened Sporefish", "+20 stam +8 mp5 — Life Tap less often"),
        }},
        { slot = "WEAPON", note = "", entries = {
            E(22522, "Superior Wizard Oil", "+42 spell damage is +threat"),
        }},
        { slot = "COMBAT_POTION", note = "Pre-pot before your phase so the cooldown returns mid-tank.", entries = {
            E(22849, "Ironshield Potion", "+2500 armor for melee phases"),
            E(22832, "Super Mana Potion", "Life Tap is not a defensive"),
        }},
        { slot = "RECOVERY_POTION", note = "", entries = {
            E(22829, "Super Healing Potion", "you're the one getting hit now"),
        }},
        { slot = "EXTRAS", note = "Match the protection potion to the phase you tank.", entries = {
            E(22846, "Major Shadow Protection Potion", "Illidan demon phase — Shadow Blast eats these"),
            E(22841, "Major Fire Protection Potion", "fire-heavy phases and adds"),
            E(22797, "Nightmare Seed", "+2000 HP panic button for the transition"),
            E(22795, "Fel Blossom", "absorb shield on demand (herbalists)"),
        }},
    }},
})

-- ---------------------------------------------------------------------------
-- Druid — Dreamstate (Balance-tree mana-battery healer)
-- ---------------------------------------------------------------------------
AddSpecs("DRUID", {
    { key = "DREAMSTATE", name = "Dreamstate", role = "HEALER", picks = {
        { slot = "FLASK", note = "Fringe arena healer — Dreamstate regen scales off Intellect, so int IS regen.", entries = {
            E(22853, "Flask of Mighty Restoration", "+25 mp5 — the build's whole thesis"),
            E(13511, "Flask of Distilled Wisdom", "+65 int, double-dipped by Dreamstate"),
        }},
        { slot = "BATTLE_ELIXIR", note = "", entries = {
            E(22825, "Elixir of Healing Power", "+50 healing — the healer battle elixir"),
        }},
        { slot = "GUARDIAN_ELIXIR", note = "", entries = {
            E(32067, "Elixir of Draenic Wisdom", "+30 int/spirit — int again"),
            E(22840, "Elixir of Major Mageblood", "+16 mp5 alternative"),
        }},
        { slot = "FOOD", note = "", entries = {
            E(27666, "Golden Fish Sticks", "+44 healing +20 spirit staple"),
            E(18254, "Runn Tum Tuber Surprise", "+10 int — on-theme budget bite"),
        }},
        { slot = "WEAPON", note = "", entries = {
            E(22521, "Superior Mana Oil", "14 mp5"),
            E(20748, "Brilliant Mana Oil", "+25 healing variant"),
        }},
        { slot = "COMBAT_POTION", note = "", entries = {
            E(22832, "Super Mana Potion", "with Dreamstate underneath, you simply do not go oom"),
        }},
        { slot = "RECOVERY_POTION", note = "", entries = {
            E(22829, "Super Healing Potion", "trinket-swap emergency heal"),
        }},
        { slot = "EXTRAS", note = "Arena kit.", entries = {
            E(5634, "Free Action Potion", "pre-pot into stun setups"),
            E(12662, "Demonic Rune", "mana off everything else's cooldown"),
        }},
    }},
})

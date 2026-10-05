-- Commander Guide — the guide itself
--
-- Raids, boss by boss, one page per ROLE. Pure data: no WoW API is touched
-- here, so the harness can validate every page and every callout with no
-- client attached (Harness/guide_engine_smoke.lua section A).
--
-- Shape (DECISIONS D2):
--
--   RAIDS[i]            { key, title, short, instanceMapID, size, bosses }
--   ENTRANCES[id]       the door of each TBC raid, by instanceMapID (bottom
--                       of this file, with where every number came from)
--   bosses[j]           { key, title, encounterID, npcs, adds, roles }
--                         encounterID  the client's DungeonEncounter id, what
--                                      ENCOUNTER_START reports
--                         npcs         creature ids that ARE the boss (any of
--                                      them in the combat log names the fight
--                                      when ENCOUNTER_START is silent)
--                         adds         creature ids worth naming in callouts
--   roles.HEALER        { oneLiner, job, phases, watch, callouts }
--                         oneLiner     the fight in one sentence
--                         job          bullets: what you, the healer, do
--                         phases       { {title, lines}, ... } in order
--                         watch        { {spell, name, kind, note}, ... }
--                                      kind: MAGIC CURSE POISON DISEASE
--                                            BLEED STUN SILENCE FEAR NONE
--                         callouts     what the voice says and when (below)
--
--   A callout: { on, spell|npc|below|match|stacks, whom, say, sayMe, text,
--                cooldown, priority, once, delay }
--     on        START | END | AURA_APPLIED | AURA_REMOVED | DOSE | CAST_START
--               | CAST_SUCCESS | DAMAGE | SUMMON | UNIT_DIED | FIRST_SEEN
--               | HEALTH | YELL
--     whom      me | friend | any  (default friend for aura/damage kinds:
--               a friendly PLAYER, you included; casts match by spell alone)
--     say       spoken line; %t is the target's first name, "you" when it is
--               you (then sayMe wins when given)
--     text      banner line when it should differ from the spoken one
--     cooldown  seconds before the same callout may fire again (default 4)
--     priority  1 interrupts whatever is being said; 2 queues (default 2)
--     once      fires once per pull (phase changes, first sightings)
--     delay     seconds to hold before speaking
--
-- Every spell id below was checked against Wowhead's Anniversary tooltip
-- endpoint on 2026-09-28 (name matches); creature ids come from AtlasLoot's
-- data-tbc.lua and the CMaNGOS TBC world DB; encounter ids from the client's
-- own DungeonEncounter table. What is NOT verified is which of these the
-- live combat log actually emits and when — see ASSUMPTIONS.md.

CommanderGuide_Data = CommanderGuide_Data or {}
local D = CommanderGuide_Data

D.VERSION = 1

D.ROLES = {
    { key = "HEALER", title = "Healer", short = "HEAL", ready = true },
    { key = "TANK",   title = "Tank",   short = "TANK", ready = false },
    { key = "DPS",    title = "Damage", short = "DPS",  ready = false },
}

D.KINDS = {
    START = true, END = true, AURA_APPLIED = true, AURA_REMOVED = true,
    DOSE = true, CAST_START = true, CAST_SUCCESS = true, DAMAGE = true,
    SUMMON = true, UNIT_DIED = true, FIRST_SEEN = true, HEALTH = true,
    YELL = true,
}

D.WATCH_KINDS = {
    MAGIC = true, CURSE = true, POISON = true, DISEASE = true, BLEED = true,
    STUN = true, SILENCE = true, FEAR = true, NONE = true,
}

-- ---------------------------------------------------------------------------
-- Karazhan
-- ---------------------------------------------------------------------------

local KARAZHAN = {
    key = "KARAZHAN", title = "Karazhan", short = "Kara",
    instanceMapID = 532, size = 10,
    bosses = {},
}

local function Boss(t) KARAZHAN.bosses[#KARAZHAN.bosses + 1] = t; return t end

-- 1. Attumen the Huntsman ----------------------------------------------------
Boss({
    key = "ATTUMEN", title = "Attumen the Huntsman", encounterID = 652,
    npcs = { 16151, 15550, 16152 },     -- Midnight, Attumen, Attumen mounted
    adds = {},
    roles = {
        HEALER = {
            oneLiner = "A tank-and-spank with one curse to remove and a charge you avoid by standing close.",
            job = {
                "Phase one is Midnight alone: keep the tank up and save your mana. Nothing else happens.",
                "At 95 percent Attumen appears. A second tank takes him. He Shadow Cleaves: the tank plus up to two people next to the tank, so nobody stands beside the tank.",
                "Intangible Presence is a curse that halves spell hit for 30 seconds. Mages and druids remove it. If you are a druid, decursing is your job before anything else.",
                "At 25 percent Attumen mounts Midnight and threat resets. Mounted, he Charges anyone standing 8 to 25 yards away. Stand inside 8 yards behind him, or at 25 plus. Healers tuck in behind.",
                "Mounted damage on the tank is higher. Expect to spend mana here, not in phase one.",
            },
            phases = {
                { title = "Phase 1: Midnight (100 to 95 percent)", lines = {
                    "One tank, light damage. Use cheap heals.",
                } },
                { title = "Phase 2: Attumen joins (95 to 25 percent)", lines = {
                    "Two tanks, two targets. Cover the Attumen tank: Shadow Cleave lands a weapon hit plus shadow on him and his two nearest allies.",
                    "Intangible Presence on random people: curse, decurse it fast. Your own casts half-miss while you carry it.",
                } },
                { title = "Phase 3: Mounted (25 percent)", lines = {
                    "Threat resets when he mounts. The tank re-establishes; heal calmly, do not spike threat on the first second.",
                    "Charge hits anyone 8 to 25 yards out. Get behind him inside 8 yards and stay there.",
                } },
            },
            watch = {
                { spell = 29833, name = "Intangible Presence", kind = "CURSE", note = "Halves spell hit. Decurse (mage, druid)." },
                { spell = 29832, name = "Shadow Cleave", kind = "NONE", note = "Tank plus two nearest. Do not stand beside the tank." },
                { spell = 29847, name = "Charge", kind = "NONE", note = "Mounted only. Targets 8 to 25 yards away. Stand close behind." },
            },
            callouts = {
                { on = "START", say = "Attumen. Midnight first. Save your mana.", once = true },
                { on = "FIRST_SEEN", npc = 15550, say = "Attumen is up. Second tank needs heals.", once = true },
                { on = "AURA_APPLIED", spell = 29833, say = "Curse on %t. Decurse.", sayMe = "Curse on you. Get it decursed.", cooldown = 5 },
                { on = "HEALTH", npc = 16151, below = 32, say = "Mount phase soon. Get behind him, inside eight yards.", once = true },
                { on = "HEALTH", npc = 15550, below = 32, say = "Mount phase soon. Get behind him, inside eight yards.", once = true },
                { on = "FIRST_SEEN", npc = 16152, say = "Attumen mounted. Threat reset. Stay close behind him.", once = true, priority = 1 },
            },
        },
    },
})

-- 2. Moroes -----------------------------------------------------------------
Boss({
    key = "MOROES", title = "Moroes", encounterID = 653,
    npcs = { 15687 },
    adds = { 17007, 19872, 19873, 19874, 19875, 19876 },
    roles = {
        HEALER = {
            oneLiner = "Garrote is the fight: the bleed never falls off, so whoever has it needs a heal every few seconds until Moroes dies.",
            job = {
                "Four of his six dinner guests are up. Two get crowd controlled, two die first. Until they are dead, the add tank is your priority.",
                "Garrote: a 5 minute bleed on a random non-tank, roughly a thousand every 3 seconds, and it stacks up across the raid as the fight goes on. Every garroted player needs a healer assigned. Say who has whom.",
                "If you are a paladin, Blessing of Protection wipes Garrote off a caster. Use it on a healer or a mage. Divine Shield, Ice Block and Stoneform clear it too.",
                "Vanish is the tell: he vanishes, then Garrotes someone. Top everyone up when he vanishes.",
                "Blind takes one of you out for 10 seconds. If it is you, the others cover your Garrote targets. Gouge stuns the tank for 6 seconds, the off tank picks him up.",
                "Baroness Dorothea Mana Burns from 30 yards. Stand more than 30 yards from her, or your mana is gone. Baron Rafe stuns the tank with Hammer of Justice. Lord Robin Mortal Strikes the add tank: half healing for 5 seconds, so pre-cast big.",
                "At 30 percent Moroes enrages: faster, harder hits on the tank. Save a cooldown for it.",
            },
            phases = {
                { title = "Phase 1: the guests", lines = {
                    "Two adds are controlled, two are killed. Heal the add tank; Mortal Strike and Hammer of Justice both land on him.",
                    "Stay out of Mana Burn range of the Baroness (30 yards).",
                } },
                { title = "Phase 2: Moroes", lines = {
                    "Garrotes accumulate. Assign them as they land. Nobody with Garrote is allowed below half.",
                    "Vanish means a Garrote is coming: pre-heal.",
                } },
                { title = "30 percent: enrage", lines = {
                    "Tank damage jumps. Two healers on the tank, one on the garroted.",
                } },
            },
            watch = {
                { spell = 37066, name = "Garrote", kind = "BLEED", note = "Permanent bleed. Assign a healer. Paladin BoP removes it." },
                { spell = 34694, name = "Blind", kind = "NONE", note = "You are out for 10 seconds. Others cover your targets." },
                { spell = 29425, name = "Gouge", kind = "STUN", note = "Tank stunned 6 seconds. Off tank steps in." },
                { spell = 29405, name = "Mana Burn", kind = "NONE", note = "Baroness. Stay 30 plus yards away." },
                { spell = 29572, name = "Mortal Strike", kind = "NONE", note = "Lord Robin. Half healing on the add tank for 5 seconds." },
                { spell = 13005, name = "Hammer of Justice", kind = "STUN", note = "Baron Rafe. Tank stunned 6 seconds." },
            },
            callouts = {
                { on = "START", say = "Moroes. Adds first. Stay out of Mana Burn range.", once = true },
                { on = "AURA_APPLIED", spell = 37066, say = "Garrote on %t. Keep a heal on them.", sayMe = "Garrote on you. Heal yourself between casts.", cooldown = 3 },
                { on = "CAST_SUCCESS", spell = 29448, say = "Vanish. Garrote coming. Top everyone up.", cooldown = 8 },
                { on = "AURA_APPLIED", spell = 34694, say = "Blind on %t. Cover their targets.", sayMe = "You are blind. Others cover your targets.", cooldown = 5, priority = 1 },
                { on = "AURA_APPLIED", spell = 29425, say = "Gouge on %t. Off tank has him.", cooldown = 6 },
                { on = "CAST_START", spell = 29405, say = "Mana Burn cast. Casters out of range.", cooldown = 15 },
                { on = "AURA_APPLIED", spell = 29572, say = "Mortal Strike on %t. Half healing. Cast big.", cooldown = 8 },
                { on = "HEALTH", npc = 15687, below = 32, say = "Moroes enraged. Everything on the tank.", once = true, priority = 1 },
                { on = "UNIT_DIED", npc = 15687, say = "Moroes down. Garrotes fall off now.", once = true },
            },
        },
    },
})

-- 3. Maiden of Virtue ---------------------------------------------------------
Boss({
    key = "MAIDEN", title = "Maiden of Virtue", encounterID = 654,
    npcs = { 16457 },
    adds = {},
    roles = {
        HEALER = {
            oneLiner = "Stay off her platform, spread ten yards, dispel Holy Fire on sight, and heal the Holy Fire target first when Repentance breaks.",
            job = {
                "Holy Ground pulses holy damage and a one second silence to everyone within 12 yards of her. Healers stand well outside it, spread around the pillars.",
                "Holy Wrath is a chain lightning that jumps between people standing within 10 yards of each other and grows 40 percent per jump. Ten yards from everyone, always.",
                "Holy Fire: a 3 second cast on a random player, big hit plus a fire DoT for 12 seconds. It is Magic. Dispel it the moment it lands. Priests and paladins own this.",
                "Repentance incapacitates the whole raid for 12 seconds. Damage breaks it, and she casts Holy Fire on someone while you are down. When you wake up, that person is dying: heal them first, then the tank.",
                "A paladin can pre-bubble to skip Repentance and keep healing through it. Priests cannot; a Prayer of Mending or a Renew before it lands keeps ticking.",
            },
            phases = {
                { title = "Whole fight (no phases)", lines = {
                    "Position: outside 12 yards, 10 yards from everyone else, in range of the tank.",
                    "Holy Fire lands, dispel it. Repentance lands, wait; wake up, heal the Holy Fire target.",
                } },
            },
            watch = {
                { spell = 29522, name = "Holy Fire", kind = "MAGIC", note = "Dispel immediately." },
                { spell = 29511, name = "Repentance", kind = "NONE", note = "12 second incapacitate on everyone. Heal the Holy Fire target when you wake." },
                { spell = 32445, name = "Holy Wrath", kind = "NONE", note = "Chains within 10 yards. Spread." },
                { spell = 29512, name = "Holy Ground", kind = "SILENCE", note = "12 yard pulse with a silence. Stay out." },
            },
            callouts = {
                { on = "START", say = "Maiden. Spread ten yards. Stay off the platform.", once = true },
                { on = "AURA_APPLIED", spell = 29522, say = "Holy Fire on %t. Dispel it.", sayMe = "Holy Fire on you. Dispel yourself.", cooldown = 3, priority = 1 },
                { on = "CAST_START", spell = 29511, say = "Repentance. Heal now.", cooldown = 10, priority = 1 },
                { on = "AURA_REMOVED", spell = 29511, whom = "me", say = "You are up. Heal the Holy Fire target first.", cooldown = 10, priority = 1 },
                { on = "DAMAGE", spell = 32445, say = "Holy Wrath. Spread out.", cooldown = 12 },
            },
        },
    },
})

-- 4. Opera Hall ----------------------------------------------------------------
Boss({
    key = "OPERA", title = "Opera Hall", encounterID = 655,
    npcs = { 17535, 17548, 17546, 17543, 17547, 18168, 17521, 17534, 17533 },
    adds = {},
    roles = {
        HEALER = {
            oneLiner = "One of three plays: Oz is spread damage and fears, the Wolf is keeping a runner alive, Romulo and Julianne is poison cleansing and healing through Blinding Passion.",
            job = {
                "You find out which play it is when the curtain opens. All three are covered below; the voice only calls what is actually on stage.",
                "Wizard of Oz. Kill order Dorothee, Tito, Roar, Strawman, Tinhead, then the Crone. Dorothee's Water Bolts hit random people for 2 thousand plus, that is your main load. Roar fears with Frightened Scream: Fear Ward or Tremor Totem on the tanks. Strawman stuns his tank with Brain Bash. The Crone's Chain Lightning jumps between people, spread; her Cyclones throw you in the air, walk away from them.",
                "Big Bad Wolf. He puts Little Red Riding Hood on a random player: armor zero, silenced, extra run speed, and he chases them for 20 seconds. If it is you, run the outside of the stage and do not stop. If it is someone else, the whole raid stands in the middle and you heal the runner as they pass. Terrifying Howl fears: Fear Ward the tank.",
                "Romulo and Julianne. Julianne first: heal the Blinding Passion target through 1.5 thousand plus 3 thousand over 4 seconds; DPS interrupt her heal. Then Romulo: Poisoned Thrust stacks minus 10 percent stats on the tank, cleanse the poison (druid, paladin, shaman). Daring makes him hit 35 percent harder and faster for 8 seconds. Then both together: they must die within 10 seconds of each other, so hold cooldowns for the end.",
            },
            phases = {
                { title = "Wizard of Oz", lines = {
                    "Water Bolt targets, fears from Roar, Brain Bash stuns on the Strawman tank.",
                    "Crone: Chain Lightning, spread; Cyclones, step away.",
                } },
                { title = "Big Bad Wolf", lines = {
                    "Red Riding Hood runs the edge. Everyone else in the middle. Heal the runner in passing. Howl fears.",
                } },
                { title = "Romulo and Julianne", lines = {
                    "Julianne: Blinding Passion targets. Romulo: cleanse Poisoned Thrust, cover Daring. Both: kill together.",
                } },
            },
            watch = {
                { spell = 31012, name = "Water Bolt", kind = "NONE", note = "Oz. Random 2 thousand frost. Heal the target." },
                { spell = 31013, name = "Frightened Scream", kind = "FEAR", note = "Oz, Roar. Fear Ward and Tremor." },
                { spell = 32337, name = "Chain Lightning", kind = "NONE", note = "Crone. Spread." },
                { spell = 30756, name = "Little Red Riding Hood", kind = "NONE", note = "Wolf. The runner. Heal them in passing." },
                { spell = 30752, name = "Terrifying Howl", kind = "FEAR", note = "Wolf. Fear Ward the tank." },
                { spell = 30890, name = "Blinding Passion", kind = "NONE", note = "Julianne. Heal the target through it." },
                { spell = 30822, name = "Poisoned Thrust", kind = "POISON", note = "Romulo. Cleanse the tank." },
                { spell = 30841, name = "Daring", kind = "NONE", note = "Romulo buff. Tank takes more for 8 seconds." },
            },
            callouts = {
                { on = "FIRST_SEEN", npc = 17535, say = "Wizard of Oz. Heal the Water Bolt targets. Fear Ward the tanks.", once = true },
                { on = "CAST_SUCCESS", spell = 31013, say = "Roar fears. Tremor, Fear Ward.", cooldown = 10 },
                { on = "AURA_APPLIED", spell = 31046, say = "Brain Bash. Tank stunned.", cooldown = 8 },
                { on = "FIRST_SEEN", npc = 18168, say = "Crone. Spread for Chain Lightning. Walk out of Cyclones.", once = true, priority = 1 },
                { on = "FIRST_SEEN", npc = 17521, say = "Big Bad Wolf. Raid in the middle. Red Riding Hood runs the edge.", once = true },
                { on = "AURA_APPLIED", spell = 30756, say = "Red Riding Hood on %t. Heal them as they pass.", sayMe = "Red Riding Hood on you. Run the outside. Do not stop.", cooldown = 2, priority = 1 },
                { on = "AURA_REMOVED", spell = 30756, say = "%t is free. Top them up.", sayMe = "You are free. Get back to the middle.", cooldown = 2 },
                { on = "CAST_SUCCESS", spell = 30752, say = "Terrifying Howl. Fear.", cooldown = 8 },
                { on = "FIRST_SEEN", npc = 17534, say = "Julianne first. Heal the Blinding Passion targets.", once = true },
                { on = "AURA_APPLIED", spell = 30890, say = "Blinding Passion on %t. Heal them through it.", sayMe = "Blinding Passion on you. Heal yourself.", cooldown = 3 },
                { on = "FIRST_SEEN", npc = 17533, say = "Romulo. Cleanse Poisoned Thrust off the tank.", once = true },
                { on = "AURA_APPLIED", spell = 30822, say = "Poisoned Thrust on %t. Cleanse poison.", cooldown = 6 },
                { on = "AURA_APPLIED", spell = 30841, whom = "any", say = "Daring. Tank takes more for eight seconds.", cooldown = 8 },
                { on = "YELL", match = "gentle night", say = "Both are up. They must die together. Cooldowns now.", once = true, priority = 1 },
            },
        },
    },
})

-- 5. The Curator ------------------------------------------------------------------
Boss({
    key = "CURATOR", title = "The Curator", encounterID = 656,
    npcs = { 15691 },
    adds = { 17096 },
    roles = {
        HEALER = {
            oneLiner = "Hateful Bolt hits whoever is second on threat, the Astral Flares hurt everyone in a spread, and Evocation is your twenty seconds to catch up.",
            job = {
                "Hateful Bolt: 4.5 to 6 thousand arcane every few seconds on a high-threat, high-health non-tank. Usually a melee or a hunter. Know who that is and keep them near full.",
                "An Astral Flare spawns every 10 seconds. Its Arcing Sear chains to anyone within 10 yards of the target, so spread 10 yards. Flares die fast; heal whoever they picked.",
                "Each flare costs him mana. When he is empty he Evocates for 20 seconds and takes triple damage. Nothing hits the raid then: top everyone, drink a mana potion, refresh your buffs.",
                "At 15 percent he stops summoning and gains Arcane Infusion: heavy arcane on every melee swing on the tank. Every healer on the tank, save your big cooldown for this.",
                "Berserk at 12 minutes. Your mana has to last; Evocations are when you regen too.",
            },
            phases = {
                { title = "Flares (until his mana is gone)", lines = {
                    "Spread 10 yards. Heal the Hateful Bolt target and whoever the flare is on.",
                } },
                { title = "Evocation (20 seconds)", lines = {
                    "No incoming damage. Top up, potion, prepare.",
                } },
                { title = "15 percent: Arcane Infusion", lines = {
                    "Tank takes big arcane hits. Everyone heals the tank.",
                } },
            },
            watch = {
                { spell = 30383, name = "Hateful Bolt", kind = "NONE", note = "Second on threat. Keep them high." },
                { spell = 30235, name = "Arcing Sear", kind = "NONE", note = "Flare chain within 10 yards. Spread." },
                { spell = 30254, name = "Evocation", kind = "NONE", note = "20 seconds of quiet. Regen." },
                { spell = 30403, name = "Arcane Infusion", kind = "NONE", note = "15 percent. Tank heals only." },
            },
            callouts = {
                { on = "START", say = "Curator. Spread for the flares. Know your Hateful Bolt target.", once = true },
                { on = "DAMAGE", spell = 30383, say = "Hateful Bolt on %t. Heal them.", sayMe = "Hateful Bolt on you. Heal yourself.", cooldown = 4 },
                { on = "CAST_START", spell = 30254, say = "Evocation. Twenty seconds. Top everyone. Potion.", cooldown = 20, priority = 1 },
                { on = "AURA_REMOVED", spell = 30254, whom = "any", say = "Evocation over. Flares again. Spread.", cooldown = 20 },
                { on = "AURA_APPLIED", spell = 30403, whom = "any", say = "Arcane Infusion. Everything on the tank.", once = true, priority = 1 },
            },
        },
    },
})

-- 6. Terestian Illhoof --------------------------------------------------------------
Boss({
    key = "ILLHOOF", title = "Terestian Illhoof", encounterID = 657,
    npcs = { 15688 },
    adds = { 17229, 17248 },
    roles = {
        HEALER = {
            oneLiner = "Every half minute someone is Sacrificed into chains and bleeds 1500 a second: spam heal them until the chains die, and keep yourself out of imp fire.",
            job = {
                "Sacrifice: a random non-tank is stunned inside Demon Chains and loses 1500 health per second for up to 30 seconds. The raid kills the chains. Until they die, that player is your only patient. Big heals, no hesitation.",
                "If YOU are sacrificed you cannot cast. The other healers take you. Before a pull, agree who covers whom.",
                "Imps stream in from the two portals and Firebolt random people. That is constant low raid damage on top of the Sacrifice. Do not stand next to a portal.",
                "Kil'rek is his imp. When Kil'rek dies, Illhoof takes 25 percent more damage from Broken Pact, and Kil'rek comes back 45 seconds later. Nothing for you to do but notice the burn window.",
                "Berserk at 10 minutes.",
            },
            phases = {
                { title = "Whole fight (no phases)", lines = {
                    "Sacrifice lands: heal that person through 1500 a second until the chains break.",
                    "Between Sacrifices: imp Firebolt damage on random people, Shadow Bolts near the tank.",
                } },
            },
            watch = {
                { spell = 30115, name = "Sacrifice", kind = "STUN", note = "1500 a second. Spam heal until the chains die." },
                { spell = 30050, name = "Firebolt", kind = "NONE", note = "Imps. Constant random damage." },
                { spell = 30065, name = "Broken Pact", kind = "NONE", note = "On Illhoof when Kil'rek dies. Burn window." },
            },
            callouts = {
                { on = "START", say = "Illhoof. Sacrifice targets get spam heals. Stay away from the portals.", once = true },
                { on = "AURA_APPLIED", spell = 30115, say = "Sacrifice on %t. Heal them until the chains die.", sayMe = "You are sacrificed. The others heal you.", cooldown = 3, priority = 1 },
                { on = "AURA_REMOVED", spell = 30115, say = "%t is free.", sayMe = "You are free. Back to healing.", cooldown = 3 },
                { on = "UNIT_DIED", npc = 17229, say = "Kil'rek dead. Illhoof takes more. Burn.", cooldown = 20 },
            },
        },
    },
})

-- 7. Shade of Aran --------------------------------------------------------------------
Boss({
    key = "ARAN", title = "Shade of Aran", encounterID = 658,
    npcs = { 16524 },
    adds = { 17167, 18254 },
    roles = {
        HEALER = {
            oneLiner = "No tank and random targets: stand still for Flame Wreath, run for Arcane Explosion, walk out of Blizzard, and keep everyone above ten thousand when he drinks.",
            job = {
                "He has no aggro table. Fireballs and Frostbolts land on random people for 4 to 5 thousand. That is the steady load: keep the whole raid high, nobody sits at half.",
                "Counterspell locks a school for 10 seconds on everyone within 15 yards of him. Stand 20 to 25 yards out, in range of the whole room.",
                "Flame Wreath: three people get a ring. If you have it, DO NOT MOVE for 20 seconds, and nobody crosses a ring. Moving explodes the raid. Healing is fine, jumping is not.",
                "Arcane Explosion: a 10 second cast that hits everyone within 20-ish yards for 10 thousand. Run to the walls. He Mass Slows right before it, so start early.",
                "Blizzard walks around the room. If it is on you, walk out of it. Chains of Ice roots you; that is the 10 seconds you might have to eat.",
                "At 40 percent he Mass Polymorphs the raid and summons four Water Elementals for 90 seconds. You wake up, heal, and he Pyroblasts. Shield and HoT as the sheep ends.",
                "When his mana hits 20 percent he Drinks for 10 seconds, then Pyroblasts everyone for 8 to 10 thousand. Everyone above ten thousand before it lands. No Mana Burn on him, ever.",
                "Shadows of Aran at his berserk timer means the pull is over. Before then it is a mana marathon: cheap heals, drink your potions on cooldown.",
            },
            phases = {
                { title = "The whole fight", lines = {
                    "Random bolts on random people. Keep everyone high.",
                    "Flame Wreath: still. Arcane Explosion: run. Blizzard: walk out. Counterspell: stay 20 yards from him.",
                } },
                { title = "40 percent: Polymorph and elementals", lines = {
                    "Wake up, heal up, Pyroblast follows. Water Elementals bolt random people for 90 seconds.",
                } },
                { title = "20 percent mana: Drink", lines = {
                    "10 seconds, then a Pyroblast on everyone. Everyone above ten thousand.",
                } },
            },
            watch = {
                { spell = 29946, name = "Flame Wreath", kind = "NONE", note = "Do not move for 20 seconds." },
                { spell = 29973, name = "Arcane Explosion", kind = "NONE", note = "10 second cast. Run out." },
                { spell = 29951, name = "Blizzard", kind = "NONE", note = "Walk out of the ice." },
                { spell = 29961, name = "Counterspell", kind = "SILENCE", note = "Within 15 yards of him. Stay out." },
                { spell = 29963, name = "Mass Polymorph", kind = "NONE", note = "40 percent. Heal when you wake, Pyroblast follows." },
                { spell = 30024, name = "Drink", kind = "NONE", note = "Pyroblast on everyone after. 10 thousand health minimum." },
                { spell = 29964, name = "Dragon's Breath", kind = "NONE", note = "6 thousand over 6 seconds plus disorient. Heal the target." },
            },
            callouts = {
                { on = "START", say = "Aran. No tank. Stand still on Flame Wreath. Run on Arcane Explosion.", once = true },
                { on = "CAST_START", spell = 30004, say = "Flame Wreath. Nobody moves.", cooldown = 15, priority = 1 },
                { on = "AURA_APPLIED", spell = 29946, whom = "me", say = "Wreath on you. Stand still twenty seconds.", cooldown = 15, priority = 1 },
                { on = "AURA_REMOVED", spell = 29946, whom = "me", say = "Wreath gone. You can move.", cooldown = 15 },
                { on = "CAST_START", spell = 29973, say = "Arcane Explosion. Run out. Twenty yards.", cooldown = 15, priority = 1 },
                { on = "CAST_SUCCESS", spell = 29951, say = "Blizzard. Walk out of the ice.", cooldown = 15 },
                { on = "CAST_START", spell = 29963, say = "Polymorph. Heal up when you wake. Pyroblast follows.", cooldown = 30, priority = 1 },
                { on = "AURA_REMOVED", spell = 29963, whom = "me", say = "You are awake. Big heals now. Pyroblast incoming.", cooldown = 30, priority = 1 },
                { on = "FIRST_SEEN", npc = 17167, say = "Water elementals. Ninety seconds. Heal their targets.", once = true },
                { on = "CAST_START", spell = 30024, say = "Aran is drinking. Pyroblast next. Everyone above ten thousand.", cooldown = 30, priority = 1 },
                { on = "DAMAGE", spell = 29964, say = "Dragon's Breath on %t.", sayMe = "Dragon's Breath on you.", cooldown = 6 },
                { on = "AURA_APPLIED", spell = 29961, whom = "me", say = "You are counterspelled. Ten seconds.", cooldown = 10 },
                { on = "FIRST_SEEN", npc = 18254, say = "Shadows of Aran. Berserk. Finish him now.", once = true, priority = 1 },
            },
        },
    },
})

-- 8. Netherspite --------------------------------------------------------------------------
Boss({
    key = "NETHERSPITE", title = "Netherspite", encounterID = 659,
    npcs = { 15689 },
    adds = { 17646 },
    roles = {
        HEALER = {
            oneLiner = "Portal duty: the green beam is yours; step in when it is your turn, step out on Exhaustion, and never stand in red or blue.",
            job = {
                "Three portals fire beams at him. Red is the tank beam, blue is the damage beam, green is the healer beam. A beam that reaches him empowers him, so each one must be blocked by a body at all times.",
                "In the green beam you heal more per stack but lose max mana per stack. Block it for 20 to 25 stacks, then swap with the next healer. Call your swap out loud.",
                "Leaving a beam gives you Nether Exhaustion for 90 seconds: you cannot block that color again. Two or three healers rotate the green portal.",
                "Do not touch red or blue. Red on a healer makes the tank lose the beam; blue makes you take more damage.",
                "Nether Burn ticks shadow on everyone the whole fight. Someone always needs a top-up; the beam healer covers the raid, the free healer covers the beam healers.",
                "After 60 seconds he banishes for 30: Netherbreath cones knock people around and Void Zones appear. Spread, walk out of the zones, heal through it, then get back to your portal before the beams return.",
            },
            phases = {
                { title = "Portal phase (60 seconds)", lines = {
                    "Green beam blocked at all times. Swap on 20 to 25 stacks. Exhausted healers heal the raid.",
                } },
                { title = "Banish phase (30 seconds)", lines = {
                    "Spread. Netherbreath knockbacks. Void Zones: move. Get back to position before the portals reopen.",
                } },
            },
            watch = {
                { spell = 30422, name = "Serenity (green beam)", kind = "NONE", note = "Your beam. Swap at 20 to 25 stacks." },
                { spell = 38638, name = "Nether Exhaustion (green)", kind = "NONE", note = "90 seconds. Cannot take green." },
                { spell = 30421, name = "Perseverance (red beam)", kind = "NONE", note = "Tank beam. Never." },
                { spell = 30423, name = "Dominance (blue beam)", kind = "NONE", note = "Damage beam. Never." },
                { spell = 37063, name = "Void Zone", kind = "NONE", note = "Banish phase. Move out." },
                { spell = 30522, name = "Nether Burn", kind = "NONE", note = "Constant raid tick." },
            },
            callouts = {
                { on = "START", say = "Netherspite. Green beam is yours. Everyone else stays out of the beams.", once = true },
                { on = "AURA_APPLIED", spell = 30422, whom = "me", say = "You are in the green beam. Count your stacks.", cooldown = 25 },
                { on = "DOSE", spell = 30422, whom = "me", stacks = 20, say = "Twenty stacks. Swap out soon.", cooldown = 25 },
                { on = "AURA_APPLIED", spell = 38638, say = "%t is exhausted on green. Next healer in.", sayMe = "Green Exhaustion. Ninety seconds. Stay out of green.", cooldown = 3, priority = 1 },
                { on = "AURA_APPLIED", spell = 30421, whom = "me", say = "Wrong beam. Red is the tank beam. Move.", cooldown = 5, priority = 1 },
                { on = "AURA_APPLIED", spell = 30423, whom = "me", say = "Wrong beam. Blue is the damage beam. Move.", cooldown = 5, priority = 1 },
                { on = "CAST_START", spell = 38523, say = "Banish phase. Spread. Watch for Void Zones.", cooldown = 40, priority = 1 },
                { on = "DAMAGE", spell = 37063, whom = "me", say = "Void Zone under you. Move.", cooldown = 4, priority = 1 },
                { on = "AURA_APPLIED", spell = 30421, whom = "any", say = "Portals are back. Get to your beam.", cooldown = 45, delay = 0 },
            },
        },
    },
})

-- 9. Chess Event ----------------------------------------------------------------------------
Boss({
    key = "CHESS", title = "Chess Event", encounterID = 660,
    npcs = { 16816 },
    adds = {},
    roles = {
        HEALER = {
            oneLiner = "Not a healing fight. Take a Cleric or a Necrolyte, heal your King, and step out of Medivh's fire.",
            job = {
                "You control a piece, not your character. As Alliance take a Human Cleric, as Horde an Orc Necrolyte: both have a heal. Healers keep the King and the front pieces alive.",
                "Medivh cheats. Fury of Medivh sets squares on fire: move your piece off it. Hand of Medivh heals one of his pieces. Nothing you do about that except keep pressure on.",
                "Kill his King. Your King dying loses the game. Everything you heal is in service of that.",
                "If you die as a piece, take another one. There is no character death here.",
            },
            phases = {
                { title = "The game", lines = {
                    "Pieces move one square, abilities have cooldowns. Face your piece at what you want to hit or heal.",
                } },
            },
            watch = {},
            callouts = {
                { on = "START", say = "Chess. Take a Cleric or Necrolyte. Heal the King. Move off the fire.", once = true },
            },
        },
    },
})

-- 10. Prince Malchezaar --------------------------------------------------------------------------
Boss({
    key = "PRINCE", title = "Prince Malchezaar", encounterID = 661,
    npcs = { 15690 },
    adds = { 17646 },
    roles = {
        HEALER = {
            oneLiner = "Enfeeble drops five people to one health and no healing works on them: they run out, you heal the tank, they come back, you heal them; the rest is Sunders and infernals.",
            job = {
                "Enfeeble every 30 seconds: five random non-tanks go to one health and cannot be healed for 7 seconds. Two seconds later he casts Shadow Nova, 3 thousand within 30 yards. If you are enfeebled, run past 30 yards immediately. If not, stay and heal the tank.",
                "When Enfeeble fades, five people walk back in at one health. Heal them up fast before the next infernal lands.",
                "Infernals fall every 45 seconds and Hellfire the area around them the whole fight. They never leave. Move the raid away from each one, keep moving as the room fills.",
                "Shadow Word: Pain on random people in phase one and two. It is Magic: dispel it.",
                "Phase two at 60 percent: he dual wields, Thrashes for extra swings, and Sunders the tank to 5 stacks. Tank damage triples. Two healers on the tank, one on the enfeebled.",
                "Phase three at 30 percent: Enfeeble stops. Axes fly and fixate random people for 15 seconds, 2 thousand hits: heal the axe target. Amplify Damage doubles damage taken on one person for 10 seconds: dispel it instantly, it is Magic.",
            },
            phases = {
                { title = "Phase 1 (100 to 60 percent)", lines = {
                    "Enfeeble, Shadow Nova, Shadow Word: Pain, infernals. Learn the rhythm: enfeeble, nova, heal back.",
                } },
                { title = "Phase 2 (60 to 30 percent)", lines = {
                    "Sunder Armor stacks. Thrash. The tank is the fight now. Enfeeble continues.",
                } },
                { title = "Phase 3 (30 percent)", lines = {
                    "No Enfeeble. Axes on random people. Amplify Damage: dispel. Shadow Nova still hits.",
                } },
            },
            watch = {
                { spell = 30843, name = "Enfeeble", kind = "NONE", note = "One health, unhealable 7 seconds. Run out 30 yards." },
                { spell = 30852, name = "Shadow Nova", kind = "NONE", note = "3 thousand within 30 yards, after Enfeeble." },
                { spell = 30854, name = "Shadow Word: Pain", kind = "MAGIC", note = "Dispel." },
                { spell = 39095, name = "Amplify Damage", kind = "MAGIC", note = "Phase 3. Dispel instantly." },
                { spell = 30901, name = "Sunder Armor", kind = "NONE", note = "Phase 2. Tank damage climbs per stack." },
                { spell = 39131, name = "Hellfire", kind = "NONE", note = "Infernals. Move away." },
            },
            callouts = {
                { on = "START", say = "Prince. Enfeebled, run out thirty yards. Not enfeebled, heal the tank.", once = true },
                { on = "AURA_APPLIED", spell = 30843, whom = "me", say = "Enfeebled. Run out thirty yards now.", cooldown = 10, priority = 1 },
                { on = "AURA_APPLIED", spell = 30843, say = "Enfeeble out. Nothing heals them until it fades.", cooldown = 10 },
                { on = "CAST_START", spell = 30852, say = "Shadow Nova. Enfeebled players out.", cooldown = 6, priority = 1 },
                { on = "AURA_REMOVED", spell = 30843, say = "Enfeeble over. Heal everyone back up.", cooldown = 10 },
                { on = "CAST_SUCCESS", spell = 37277, say = "Infernal landing. Move away from it.", cooldown = 10, priority = 1 },
                { on = "AURA_APPLIED", spell = 30854, say = "Shadow Word Pain on %t. Dispel.", sayMe = "Shadow Word Pain on you. Dispel yourself.", cooldown = 6 },
                { on = "HEALTH", npc = 15690, below = 62, say = "Phase two soon. Sunders. Two healers on the tank.", once = true },
                { on = "HEALTH", npc = 15690, below = 32, say = "Phase three soon. Axes. Dispel Amplify Damage.", once = true },
                { on = "AURA_APPLIED", spell = 39095, say = "Amplify Damage on %t. Dispel it now.", sayMe = "Amplify Damage on you. Dispel it now.", cooldown = 3, priority = 1 },
                { on = "DOSE", spell = 30901, stacks = 4, say = "Four sunders. The tank is soft. Big heals.", cooldown = 15 },
            },
        },
    },
})

-- 11. Nightbane ---------------------------------------------------------------------------------
Boss({
    key = "NIGHTBANE", title = "Nightbane", encounterID = 662,
    npcs = { 17225 },
    adds = { 17261 },
    roles = {
        HEALER = {
            oneLiner = "Ground phases are a tank fight with fear and fire to step out of; air phases are Rain of Bones on one person and skeletons: heal that person, then the skeleton tank.",
            job = {
                "Ground. Bellowing Roar is a 2.5 second cast that fears the whole raid. Fear Ward the tank, Tremor Totem down, and finish your cast before it lands. Charred Earth sets the ground under a random player on fire for 30 seconds: walk out. Smoldering Breath is a frontal cone for 4 thousand: never in front of him. Cleave on the tank.",
                "Distracting Ash cuts your hit chance and range: nothing to dispel, just close the distance if your heals start falling short.",
                "Air, at 75, 50 and 25 percent. Rain of Bones: an 11 second channel on one random player, big damage over time, and three skeletons spawn on them. Heal that person hard and have them run to the tank. Smoking Blast hits the top threat people for 2 thousand plus a burn. Fireball Barrage punishes anyone more than 40 yards from him: stay inside 40.",
                "He lands and Roars almost immediately. Fear Ward the tank as he comes down.",
            },
            phases = {
                { title = "Ground (100 to 75, 75 to 50, 50 to 25, 25 to 0)", lines = {
                    "Fear on Roar, walk out of Charred Earth, stay off his front, heal the tank.",
                } },
                { title = "Air (at 75, 50, 25 percent)", lines = {
                    "Rain of Bones target: heal them, they run to the tank. Skeletons to the tank. Stay within 40 yards.",
                } },
            },
            watch = {
                { spell = 36922, name = "Bellowing Roar", kind = "FEAR", note = "2.5 second cast. Fear Ward, Tremor." },
                { spell = 30129, name = "Charred Earth", kind = "NONE", note = "Fire under you for 30 seconds. Move." },
                { spell = 30210, name = "Smoldering Breath", kind = "NONE", note = "Frontal cone, 4 thousand. Never in front." },
                { spell = 37098, name = "Rain of Bones", kind = "NONE", note = "Air. Heal the target, skeletons spawn on them." },
                { spell = 30128, name = "Smoking Blast", kind = "NONE", note = "Air. Top threat targets, 2 thousand plus burn." },
                { spell = 30282, name = "Fireball Barrage", kind = "NONE", note = "Someone is past 40 yards. Close in." },
                { spell = 30130, name = "Distracting Ash", kind = "NONE", note = "Less hit and range. Stand closer." },
            },
            callouts = {
                { on = "START", say = "Nightbane. Fear Ward the tank. Move out of Charred Earth.", once = true },
                { on = "CAST_START", spell = 36922, say = "Bellowing Roar. Fear in two seconds.", cooldown = 8, priority = 1 },
                { on = "CAST_START", spell = 30129, say = "Charred Earth. Move off the fire.", cooldown = 6 },
                { on = "DAMAGE", spell = 30129, whom = "me", say = "You are in Charred Earth. Move.", cooldown = 4, priority = 1 },
                { on = "CAST_START", spell = 37098, say = "Rain of Bones on %t. Heal them. Skeletons to the tank.", sayMe = "Rain of Bones on you. Run to the tank.", cooldown = 10, priority = 1 },
                { on = "DAMAGE", spell = 30128, say = "Smoking Blast on %t.", sayMe = "Smoking Blast on you.", cooldown = 5 },
                { on = "DAMAGE", spell = 30282, say = "Fireball Barrage. Someone is too far. Inside forty yards.", cooldown = 12 },
                { on = "YELL", match = "from the air", say = "Taking off. Stay inside forty yards. Rain of Bones coming.", cooldown = 30, priority = 1 },
                { on = "YELL", match = "crush you", say = "Landing. Roar next. Fear Ward the tank.", cooldown = 30, priority = 1 },
            },
        },
    },
})

D.RAIDS = { KARAZHAN }

-- Names for the creature ids callouts mention, so the window can say "When
-- Kil'rek dies" without a client lookup (creature names are not queryable
-- offline; these are the live names).
D.NPC_NAMES = {
    [15550] = "Attumen the Huntsman", [16151] = "Midnight", [16152] = "Attumen (mounted)",
    [15687] = "Moroes", [16457] = "Maiden of Virtue",
    [17535] = "Dorothee", [17548] = "Tito", [17546] = "Roar", [17543] = "Strawman",
    [17547] = "Tinhead", [18168] = "The Crone", [17521] = "The Big Bad Wolf",
    [17534] = "Julianne", [17533] = "Romulo",
    [15691] = "The Curator", [17096] = "Astral Flare",
    [15688] = "Terestian Illhoof", [17229] = "Kil'rek", [17248] = "Demon Chains",
    [16524] = "Shade of Aran", [17167] = "Water Elemental", [18254] = "Shadow of Aran",
    [15689] = "Netherspite", [17646] = "Infernal",
    [16816] = "Echo of Medivh", [15690] = "Prince Malchezaar",
    [17225] = "Nightbane", [17261] = "Restless Skeleton",
}

-- ---------------------------------------------------------------------------
-- Raid entrances: the "Waypoint to Entrance" action (DECISIONS D11)
-- ---------------------------------------------------------------------------
-- Keyed by the instanceMapID GetInstanceInfo reports, like RAIDS, so a raid
-- page written later finds its door without touching this table. All nine
-- TBC raids are here for that reason; only the ones in RAIDS are reachable.
--
-- Nothing in it is remembered or guessed. Every point is Questie's own
-- dungeon table (QuestieDB/support/Zones/dungeons.lua, field [4], the
-- dungeonLocations of each TBC raid row; the WotLK and Cataclysm overrides
-- further down that file are gated on the expansion and do not apply to this
-- client), divided by 100. Questie writes a location as { areaId, x, y }; the
-- areaId became the zone's uiMapID through Questie's areaIdToUiMapId
-- (QuestieDB/support/Zones/areaIdToUiMapId.lua: 41 -> 1430, 440 -> 1446,
-- 3433 -> 1942, 3483 -> 1944, 3520 -> 1948, 3521 -> 1946, 3522 -> 1949,
-- 3523 -> 1953, 4080 -> 1957), and raidMap is the raid's own row in that same
-- table (3457 -> 350 and so on), whose parent in this build's UiMap DB2 is
-- exactly that zone. Karazhan has two doors in Questie's row, so it carries
-- two points and Commander Orders points at the nearer (alternatives).
--   raidMap  the raid's own uiMap: what Orders' entrance resolvers are asked
--   zone     the zone's name, for the chat line and the tooltip
--   points   { { map = zone uiMap, x, y }, ... }, 0..1 on that zone
D.ENTRANCES = {
    [532] = { title = "Karazhan", raidMap = 350, zone = "Deadwind Pass",    -- areaId 3457 in zone 41
              points = { { map = 1430, x = 0.467, y = 0.702 }, { map = 1430, x = 0.469, y = 0.747 } } },
    [565] = { title = "Gruul's Lair", raidMap = 330, zone = "Blade's Edge Mountains",   -- 3923 in 3522
              points = { { map = 1949, x = 0.687, y = 0.243 } } },
    [544] = { title = "Magtheridon's Lair", raidMap = 331, zone = "Hellfire Peninsula", -- 3836 in 3483
              points = { { map = 1944, x = 0.466, y = 0.5281 } } },
    [548] = { title = "Serpentshrine Cavern", raidMap = 332, zone = "Zangarmarsh",      -- 3607 in 3521
              points = { { map = 1946, x = 0.504, y = 0.409 } } },
    [550] = { title = "Tempest Keep", raidMap = 334, zone = "Netherstorm",              -- 3845 in 3523
              points = { { map = 1953, x = 0.737, y = 0.637 } } },
    [534] = { title = "Hyjal Summit", raidMap = 329, zone = "Tanaris",                  -- 3606 in 440
              points = { { map = 1446, x = 0.657, y = 0.498 } } },                     -- the Caverns of Time
    [564] = { title = "Black Temple", raidMap = 339, zone = "Shadowmoon Valley",        -- 3959 in 3520
              points = { { map = 1948, x = 0.71, y = 0.464 } } },
    [568] = { title = "Zul'Aman", raidMap = 333, zone = "Ghostlands",                   -- 3805 in 3433
              points = { { map = 1942, x = 0.8225, y = 0.643 } } },
    [580] = { title = "Sunwell Plateau", raidMap = 335, zone = "Isle of Quel'Danas",    -- 4075 in 4080
              points = { { map = 1957, x = 0.443, y = 0.455 } } },
}

-- Lookups built once at load; the engine reads these, never the arrays.
D.BY_ENCOUNTER, D.BY_NPC, D.BY_KEY = {}, {}, {}
for _, raid in ipairs(D.RAIDS) do
    for order, boss in ipairs(raid.bosses) do
        boss.raid, boss.order = raid, order
        D.BY_KEY[raid.key .. ":" .. boss.key] = boss
        if boss.encounterID then D.BY_ENCOUNTER[boss.encounterID] = boss end
        for _, npc in ipairs(boss.npcs or {}) do D.BY_NPC[npc] = boss end
        for _, role in pairs(boss.roles or {}) do
            for _, c in ipairs(role.callouts or {}) do
                if c.npc and not c.npcName then c.npcName = D.NPC_NAMES[c.npc] end
            end
        end
    end
end

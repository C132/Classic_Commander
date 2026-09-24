-- Commander Kicks: the cold data the bar reads and never writes.
--
-- One table, hand-curated, and short on purpose. An interrupt bar is not a
-- cooldown tracker with fewer rows: it answers exactly one question -- "can
-- I cast right now?" -- and every icon that is not an interrupt makes that
-- question slower to read. So the book is the interrupts of TBC and nothing
-- else: the eight class kicks and the one racial.
--
-- WHICH abilities count is the judgement call made here. Every id, cooldown
-- and lockout attached to them is the client's own: the ids and cooldowns are
-- the ones Commander Arena Frames' generator (Harness/make_cooldown_book.py)
-- read out of SpellCooldowns for build 2.5.6.69546, and the lockouts are the
-- spell descriptions in Spell.csv for the same build, which is why they are
-- in the comments beside each entry rather than trusted from memory.
--
-- Ranks are matched by NAME. The combat log reports the exact rank that was
-- cast, and the book carries one id per spell for its icon; a levelling
-- rogue's rank-two Kick arrives as an id the book has never seen and a name
-- it knows perfectly well.

CommanderKicks_Data = CommanderKicks_Data or {}
local DATA = CommanderKicks_Data

DATA.BUILD = "2.5.6.69546"

-- The book. Order is the order icons take on the bar for one enemy, so it
-- puts the true interrupts before the silences that also happen to lock.
--
--   id     the top rank, used for the icon and as a first-choice match
--   cd     seconds until it is back
--   lock   seconds the victim cannot cast the school it hit (a silence's
--          duration for the silences) -- drawn as the red opening stretch
--          of the sweep, because for that long the kick is doing its work
--          and after it the only thing left to fear is the cooldown ending
--   class  who carries it; `race` for the racial
--   pet    cast by the demon, not the warlock: the combat-log source is a
--          pet, and the bar credits its owner where it can name one
--   also   other spell NAMES that spend the same cooldown (the shocks)
DATA.BOOK = {
    -- Rogue. Kick: 10s, "prevents any spell in that school from being cast
    -- for 5 sec" (ranks 1-5: 1766, 1767, 1768, 1769, 38768)
    { id = 38768, name = "Kick", class = "ROGUE", cd = 10, lock = 5 },
    -- Warrior. Pummel needs Berserker Stance; Shield Bash a shield. Both
    -- are drawn for every warrior because the bar cannot see stances, and a
    -- warrior with both on cooldown is a warrior who cannot interrupt.
    { id = 6554, name = "Pummel", class = "WARRIOR", cd = 10, lock = 4 },
    { id = 29704, name = "Shield Bash", class = "WARRIOR", cd = 12, lock = 6 },
    -- Mage. Counterspell: 24s, 8s lockout (Improved Counterspell adds a
    -- silence, not cooldown).
    { id = 2139, name = "Counterspell", class = "MAGE", cd = 24, lock = 8 },
    -- Shaman. The shocks share one 6s cooldown, so a Frost Shock or a Flame
    -- Shock spends the Earth Shock too -- which is why they are listed under
    -- it rather than ignored. Reverberation can shave up to a second off;
    -- the bar assumes the untalented 6 and errs on the side of caution.
    { id = 25454, name = "Earth Shock", class = "SHAMAN", cd = 6, lock = 2,
      also = { "Frost Shock", "Flame Shock" } },
    -- Warlock. Spell Lock is the felhunter's: 24s, silence 6s at rank 2
    -- (19244 is rank 1). The source in the log is the pet.
    { id = 19647, name = "Spell Lock", class = "WARLOCK", cd = 24, lock = 6, pet = true },
    -- Hunter. Silencing Shot: 20s, 3s silence. A talent, so a hunter without
    -- it has an icon that never lights -- the price of not guessing specs.
    { id = 34490, name = "Silencing Shot", class = "HUNTER", cd = 20, lock = 3 },
    -- Priest. Silence: 45s, 5s. Also a talent.
    { id = 15487, name = "Silence", class = "PRIEST", cd = 45, lock = 5 },
    -- Druid. Feral Charge: 15s; the interrupt effect (19675) locks for 4s.
    { id = 16979, name = "Feral Charge", class = "DRUID", cd = 15, lock = 4 },
    -- Blood elf. Arcane Torrent: 2 minutes, 2s silence around the caster.
    -- 25046 is the rogue's energy version; same name, same cooldown.
    { id = 28730, name = "Arcane Torrent", race = "BloodElf", cd = 120, lock = 2 },
}

-- The eight seats' colours are the class colours; these are the bar's own.
DATA.TINT = {
    READY = { 0.20, 0.85, 0.35 },       -- rim on an interrupt that is UP
    DOWN = { 0.30, 0.30, 0.33 },        -- rim while it is on cooldown
    LOCK = { 0.95, 0.25, 0.20 },        -- the opening stretch: the lockout
    FLASH = { 1.00, 0.95, 0.60 },       -- the halo when a cooldown ends
}

DATA.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

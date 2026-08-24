-- Commander Rank Check harness (luajit) — run with:
--
--     /opt/homebrew/bin/luajit rankcheck_harness.lua
--
-- The mock models this client's ACTUAL spell APIs, which is the whole point:
-- C_Spell's SpellInfo struct carries no subtext, so GetSpellInfo returns nil in
-- the old "rank" slot and rank text is only reachable through
-- C_Spell.GetSpellSubtext — asynchronously, empty until the spell's data loads.
-- The regression this guards is the silent one: a scan that reads no rank
-- anywhere checks nothing and reports a cheerful PASS.
--
-- DUMP=1 prints every chat line the run produced, in order.

local ADDON = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns/Commander_RankCheck"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local chat = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }

local function ChatText()
    return table.concat(chat, "\n"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

function CreateFrame()
    local f = {}
    setmetatable(f, { __index = function() return function() end end })
    return f
end

Commander = { AddListener = function() end, UI = {} }
COMMANDER_RANKCHECK_EVENTS = { UPDATE = "COMMANDER_RANKCHECK_UPDATE" }

local nextFrame, timers = {}, {}
function RunNextFrame(fn) nextFrame[#nextFrame + 1] = fn end
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }

-- Spell data. `sub` is the rank line; `loaded` gates whether the client has it
-- yet, exactly like the real async load.
local SPELLS = {}
local loaded = {}
local pendingLoads = {}

local function DefineSpell(id, name, sub)
    SPELLS[id] = { name = name, sub = sub }
end

C_Spell = {
    GetSpellSubtext = function(id)
        if not (SPELLS[id] and loaded[id]) then return "" end
        return SPELLS[id].sub or ""
    end,
    IsSpellDataCached = function(id) return loaded[id] == true end,
}

-- The client's GetSpellInfo: a wrapper over C_Spell.GetSpellInfo, whose struct
-- has name/icon/castTime/ranges/spellID and NO subtext. The second return is
-- nil forever — never a rank.
function GetSpellInfo(id)
    local s = SPELLS[id]
    if not s then return nil end
    return s.name, nil, 0, 0, 0, 0, id
end

local SpellMixin = {}
SpellMixin.__index = SpellMixin
function SpellMixin:IsSpellEmpty() return self.spellID == nil end
function SpellMixin:IsSpellDataCached() return loaded[self.spellID] == true end
function SpellMixin:ContinueOnSpellLoad(cb)
    if loaded[self.spellID] then cb() return end
    pendingLoads[self.spellID] = pendingLoads[self.spellID] or {}
    table.insert(pendingLoads[self.spellID], cb)
end
Spell = {
    CreateFromSpellID = function(_, id)
        return setmetatable({ spellID = id }, SpellMixin)
    end,
}

-- Spellbook: one tab, slots in definition order. The legacy second return of
-- GetSpellBookItemName is "" here, matching a client whose own spellbook
-- discards it and fetches subtext by ID instead.
local book = {}
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", "", 0, #book end
function GetSpellBookItemName(index)
    local id = book[index]
    if not id then return nil end
    return SPELLS[id].name, "", id
end

local bars = {}
function GetActionInfo(slot)
    local id = bars[slot]
    if not id then return nil end
    return "spell", id, "spell"
end

local macros = {}
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
function GetMacroInfo(i)
    local m = macros[i]
    if not m then return nil end
    return m.name, "icon", m.body
end

-- ===========================================================================
-- Fixture + driver
-- ===========================================================================

local function Reset()
    chat, book, bars, macros = {}, {}, {}, {}
    SPELLS, loaded, pendingLoads = {}, {}, {}
    nextFrame, timers = {}, {}
    CommanderRankCheckDB = {
        EnableRankCheck = true, ShowSpellbookButton = true,
        CheckActionBars = true, CheckMacros = true,
        AnnounceClean = true, RunOnLogin = false,
    }
end

local function Learn(id, name, sub)
    DefineSpell(id, name, sub)
    book[#book + 1] = id
end

-- Deliver the queued spell-data loads, then drain the frame/timer queues the
-- report is scheduled on.
local function Settle(loadSpells)
    if loadSpells ~= false then
        for id, cbs in pairs(pendingLoads) do
            loaded[id] = true
            for _, cb in ipairs(cbs) do cb() end
        end
        pendingLoads = {}
    end
    for _ = 1, 4 do
        local frameQueue, timerQueue = nextFrame, timers
        nextFrame, timers = {}, {}
        for _, fn in ipairs(frameQueue) do fn() end
        for _, t in ipairs(timerQueue) do t.fn() end
    end
end

CommanderRankCheckDB = {}
dofile(ADDON .. "/CommanderRankCheck.lua")

-- ---------------------------------------------------------------------------
-- 1. A stale bar slot is caught — the headline case that was silently passing.
-- ---------------------------------------------------------------------------
Reset()
Learn(116, "Frostbolt", "Rank 1")
Learn(8412, "Frostbolt", "Rank 7")
Learn(38697, "Frostbolt", "Rank 11")
Learn(1449, "Arcane Explosion", "Rank 1")
Learn(1953, "Blink", nil)          -- rankless: can never be flagged
bars[1] = 8412                     -- Frostbolt 7 on the bar, 11 is trained
bars[2] = 38697
bars[7] = 1953
CommanderRankCheck_Run()
Settle()
local out = ChatText()
CHECK(out:find("FAIL"), "stale bar slot reports FAIL", out)
CHECK(out:find("Bar slot 1: Frostbolt %(Rank 7%) \226\134\146 Rank 11 available"),
    "names the slot, the stale rank and the replacement", out)
CHECK(not out:find("Bar slot 2"), "the current rank is not flagged", out)
CHECK(not out:find("Blink"), "a rankless spell is never flagged", out)
CHECK(out:find("1 of 2 ranked references out of date"), "counts only ranked references", out)

-- ---------------------------------------------------------------------------
-- 2. Regression guard: the scan must actually READ ranks. Before the fix every
--    slot came back rankless and the count was zero, so this asserts the count.
-- ---------------------------------------------------------------------------
Reset()
Learn(8412, "Frostbolt", "Rank 7")
bars[1] = 8412
bars[3] = 8412
CommanderRankCheck_Run()
Settle()
out = ChatText()
CHECK(out:find("PASS"), "clean loadout reports PASS", out)
CHECK(out:find("all 2 ranked references"), "both slots were genuinely checked, not skipped", out)

-- ---------------------------------------------------------------------------
-- 3. Rank text arrives asynchronously — the report has to wait for it.
--    Reading before the load resolves is what produces a false PASS.
-- ---------------------------------------------------------------------------
Reset()
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
bars[1] = 116
CommanderRankCheck_Run()
CHECK(#chat == 0, "no verdict is printed while spell text is still loading", ChatText())
Settle()                            -- loads land
out = ChatText()
CHECK(out:find("Frostbolt %(Rank 1%) \226\134\146 Rank 11 available"),
    "the verdict lands once the text arrives", out)

-- ---------------------------------------------------------------------------
-- 4. Spell data that never loads must not hang the report (the 2s safety net)
--    — and the report must not call an unread bar clean.
-- ---------------------------------------------------------------------------
Reset()
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
bars[1] = 116
CommanderRankCheck_Run()
Settle(false)                       -- only the safety timer fires; nothing loads
out = ChatText()
CHECK(#chat > 0, "a stuck spell load still produces a report", out)
CHECK(out:find("3 spells could not be read"),
    "unread spells are called out instead of passing silently", out)

-- ---------------------------------------------------------------------------
-- 5. Macros: an explicit downrank is caught, a rankless /cast never is.
-- ---------------------------------------------------------------------------
Reset()
Learn(139, "Renew", "Rank 1")
Learn(25222, "Renew", "Rank 12")
Learn(2061, "Flash Heal", "Rank 9")
macros[1] = { name = "Heal", body = "/cast Renew(Rank 4)\n/cast Flash Heal" }
macros[2] = { name = "Feral", body = "/cast Faerie Fire (Feral)(Rank 4)" }
CommanderRankCheck_Run()
Settle()
out = ChatText()
CHECK(out:find('Macro "Heal": Renew %(Rank 4%) \226\134\146 Rank 12 available'),
    "macro downrank is caught", out)
CHECK(not out:find("Flash Heal"), "a rankless /cast is never flagged", out)

-- ---------------------------------------------------------------------------
-- 6. Toggles and the quiet login run.
-- ---------------------------------------------------------------------------
Reset()
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
bars[1] = 116
CommanderRankCheckDB.CheckActionBars = false
CommanderRankCheck_Run()
Settle()
CHECK(not ChatText():find("Bar slot"), "Check Action Bars off skips the bars", ChatText())

Reset()
Learn(8412, "Frostbolt", "Rank 7")
bars[1] = 8412
CommanderRankCheck_Run(true)        -- login run, clean
Settle()
CHECK(#chat == 0, "the quiet login run says nothing when clean", ChatText())

Reset()
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
bars[1] = 116
CommanderRankCheck_Run(true)        -- login run, stale
Settle()
CHECK(ChatText():find("FAIL"), "the quiet login run still speaks up when stale", ChatText())

Reset()
CommanderRankCheckDB.EnableRankCheck = false
CommanderRankCheck_Run()
Settle()
CHECK(ChatText():find("module is disabled"), "disabled module says so", ChatText())

-- ---------------------------------------------------------------------------
-- 7. /crank debug dumps what the scan sees, so "clean" can be told apart from
--    "scanned nothing".
-- ---------------------------------------------------------------------------
Reset()
Learn(8412, "Frostbolt", "Rank 7")
Learn(38697, "Frostbolt", "Rank 11")
bars[4] = 8412
CommanderRankCheck_Run(false, true)
Settle()
out = ChatText()
CHECK(out:find("2 spellbook entries %(1 ranked spell%), 1 spell action on bars"),
    "debug summarizes the scan", out)
CHECK(out:find("slot   4  Frostbolt  id=8412  rank=7  known max=11"),
    "debug dumps the slot, the rank read and the known max", out)

Reset()
Learn(8412, "Frostbolt", "Rank 7")
CommanderRankCheck_Run(false, true)
Settle()
CHECK(ChatText():find("no spell actions found"), "debug calls out empty bars", ChatText())

-- ===========================================================================

if os.getenv("DUMP") == "1" then
    io.write("\n--- chat ---\n", ChatText(), "\n")
end
io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

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

local notified = {}
Commander = {
    AddListener = function() end, UI = {},
    Notify = function(event, ...) notified[#notified + 1] = { event = event, args = { ... } } end,
}
COMMANDER_RANKCHECK_EVENTS = { UPDATE = "COMMANDER_RANKCHECK_UPDATE", RESULT = "COMMANDER_RANKCHECK_RESULT" }

local combat = false
function InCombatLockdown() return combat end

-- The cursor and the two action calls Update uses. PlaceAction swaps: the
-- slot takes what the cursor holds, the cursor takes what the slot held.
local cursor
local pickable = {}
function GetCursorInfo() if cursor then return "spell", nil, nil, cursor end return nil end
function ClearCursor() cursor = nil end
function PickupSpell(id) if pickable[id] ~= false then cursor = id end end
local placed = {}

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
function PlaceAction(slot)
    placed[#placed + 1] = slot
    local old = bars[slot]
    bars[slot] = cursor
    cursor = old
end
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
function GetMacroIndexByName(name)
    for i, m in pairs(macros) do if m.name == name then return i end end
    return 0
end
local edits = {}
-- nil name and icon keep the macro's own (Blizzard's MacroFrame:SaveMacro
-- calls it exactly so)
function EditMacro(i, name, icon, body)
    edits[#edits + 1] = { i = i, name = name, icon = icon, body = body }
    macros[i] = { name = name or macros[i].name, body = body }
end

-- ===========================================================================
-- Fixture + driver
-- ===========================================================================

local function Reset()
    chat, book, bars, macros = {}, {}, {}, {}
    SPELLS, loaded, pendingLoads = {}, {}, {}
    nextFrame, timers = {}, {}
    notified, edits, placed, pickable = {}, {}, {}, {}
    cursor, combat = nil, false
    CommanderRankCheckChar = {}
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
CHECK(out:find("Bar slot 1: Frostbolt %(Rank 7%), Rank 11 available"),
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
CHECK(out:find("Frostbolt %(Rank 1%), Rank 11 available"),
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
CHECK(out:find('Macro "Heal": Renew %(Rank 4%), Rank 12 available'),
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

-- ---------------------------------------------------------------------------
-- 8. The scan as data (3.0): every ranked reference, stale or not, with the
--    best rank's id, and the result broadcast for Commander Spellbook.
-- ---------------------------------------------------------------------------
Reset()
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
Learn(25222, "Renew", "Rank 12")
bars[1] = 116
bars[2] = 38697
macros[1] = { name = "Heal", body = "/cast Renew(Rank 4)\n/cast Renew(Rank 12)" }
local result
CommanderRankCheck.Scan(function(r) result = r end)
Settle()
CHECK(result ~= nil, "Scan hands back a result")
CHECK(result and #result.refs == 4, "every ranked reference is listed, stale or not", result and #result.refs)
CHECK(result and #result.issues == 2, "two of them are out of date", result and #result.issues)
CHECK(#chat == 0, "Scan alone writes nothing to chat", ChatText())
local barRef
for _, ref in ipairs(result and result.refs or {}) do if ref.key == "bar:1" then barRef = ref end end
CHECK(barRef and barRef.stale and barRef.bestID == 38697 and barRef.best == 11 and barRef.where == "Bar slot 1",
    "a stale bar reference carries the best rank's id", barRef and barRef.bestID)
CHECK(notified[1] and notified[1].event == "COMMANDER_RANKCHECK_RESULT" and notified[1].args[1] == result,
    "the result is broadcast")
CHECK(CommanderRankCheck.Last() == result, "Last() is the latest result")

-- ---------------------------------------------------------------------------
-- 9. Update on a bar slot: the best rank goes in, the old one is dropped, and
--    nothing happens in combat, over a changed slot, or with a full cursor.
-- ---------------------------------------------------------------------------
combat = true
local ok, why = CommanderRankCheck.Fix(barRef)
CHECK(not ok and bars[1] == 116 and #placed == 0, "Update does nothing in combat", why)
combat = false
cursor = 9999
ok, why = CommanderRankCheck.Fix(barRef)
CHECK(not ok and bars[1] == 116 and cursor == 9999, "Update refuses while the cursor holds something", why)
cursor = nil
pickable[38697] = false
ok, why = CommanderRankCheck.Fix(barRef)
CHECK(not ok and bars[1] == 116 and #placed == 0,
    "a pickup that fails never reaches PlaceAction (it would lift the old spell off the bar)", why)
pickable[38697] = nil
ok = CommanderRankCheck.Fix(barRef)
CHECK(ChatText():find("could not update.-the cursor is holding something"), "a refused Update says why", ChatText())
CHECK(ok and bars[1] == 38697 and cursor == nil, "Update puts the best rank in the slot and drops the old one",
    tostring(bars[1]) .. " " .. tostring(cursor))
CHECK(ChatText():find("Bar slot 1 now casts Frostbolt %(Rank 11%)"), "Update says what it did", ChatText())
bars[1] = 116
local stale = { kind = "BAR", slot = 1, key = "bar:1", spellID = 8412, stale = true, bestID = 38697, best = 11, rank = 7,
    name = "Frostbolt", where = "Bar slot 1" }
ok, why = CommanderRankCheck.Fix(stale)
CHECK(not ok and bars[1] == 116, "a slot that changed since the check is left alone", why)

-- ---------------------------------------------------------------------------
-- 10. Update on a macro rewrites that spell's rank and nothing else.
-- ---------------------------------------------------------------------------
local body, n = CommanderRankCheck.RewriteMacro(
    "#showtooltip\n/cast [@mouseover] Renew(Rank 4); Renew(Rank 4)\n/cast Flash Heal(Rank 4)\n/cast Renew(Rank 9)",
    "Renew", 4, 12)
CHECK(n == 2 and body == "#showtooltip\n/cast [@mouseover] Renew(Rank 12); Renew(Rank 12)\n/cast Flash Heal(Rank 4)\n/cast Renew(Rank 9)",
    "the rewrite moves only that spell at that rank", body)
body, n = CommanderRankCheck.RewriteMacro("/cast Faerie Fire (Feral)(Rank 2)", "Faerie Fire (Feral)", 2, 5)
CHECK(n == 1 and body == "/cast Faerie Fire (Feral)(Rank 5)", "a paren-named spell is rewritten whole", body)

local macroRef
for _, ref in ipairs(result.issues) do if ref.kind == "MACRO" then macroRef = ref end end
ok = CommanderRankCheck.Fix(macroRef)
CHECK(ok and macros[1].body == "/cast Renew(Rank 12)\n/cast Renew(Rank 12)", "Update rewrites the macro", macros[1].body)
CHECK(edits[1] and edits[1].name == nil and edits[1].icon == nil and macros[1].name == "Heal",
    "the macro keeps its name and icon (EditMacro with nil, as Blizzard's macro window saves)")

-- ---------------------------------------------------------------------------
-- 11. Keep: a kept reference stops failing (here and at login) until the slot
--     holds something else; Update All leaves kept ones alone.
-- ---------------------------------------------------------------------------
Reset()
Learn(2050, "Lesser Heal", "Rank 1")
Learn(2053, "Lesser Heal", "Rank 3")
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
bars[5] = 2050
bars[6] = 116
CommanderRankCheck.Scan(function(r) result = r end)
Settle()
local keepRef
for _, ref in ipairs(result.issues) do if ref.slot == 5 then keepRef = ref end end
CommanderRankCheck.Keep(keepRef, true)
CHECK(CommanderRankCheckChar.Kept["bar:5"] == 2050, "a bar keep is tied to the exact rank in the slot")
chat = {}
CommanderRankCheck_Run()
Settle()
out = ChatText()
CHECK(out:find("FAIL") and out:find("1 of 2 ranked references out of date %(1 kept on purpose%)"),
    "a kept reference no longer fails and the report says it was kept", out)
CHECK(not out:find("Bar slot 5"), "the kept slot is not listed", out)
CommanderRankCheck.Scan(function(r) result = r end)
Settle()
local fixed = CommanderRankCheck.FixAll(result)
CHECK(fixed == 1 and bars[6] == 38697 and bars[5] == 2050, "Update All updates the issues and leaves the kept slot",
    tostring(bars[5]) .. " " .. tostring(bars[6]))
bars[5] = 2052
DefineSpell(2052, "Lesser Heal", "Rank 2")
CommanderRankCheck.Scan(function(r) result = r end)
Settle()
CHECK(#result.issues == 1 and result.issues[1].slot == 5, "a different rank in the kept slot fails again",
    #result.issues)
CommanderRankCheck.Keep(result.issues[1], true)
CommanderRankCheck.Keep(result.issues[1], false)
CHECK(CommanderRankCheckChar.Kept["bar:5"] == nil, "Unkeep takes it back")
CHECK(CommanderRankCheck.ClearKept() == 0, "Clear Kept counts what it cleared")

-- ---------------------------------------------------------------------------
-- 12. #showtooltip lines, an account and a character macro of one name, a
--     body that would outgrow 255 characters, and Update All's tally.
-- ---------------------------------------------------------------------------
Reset()
Learn(2050, "Lesser Heal", "Rank 1")
Learn(2053, "Lesser Heal", "Rank 3")
Learn(116, "Frostbolt", "Rank 1")
Learn(38697, "Frostbolt", "Rank 11")
macros[1] = { name = "Heal", body = "#showtooltip Lesser Heal(Rank 1)\n/cast Lesser Heal(Rank 1)" }
macros[121] = { name = "Heal", body = "/cast Frostbolt(Rank 1)" }
macros[2] = { name = "Long", body = "/cast Frostbolt(Rank 1)" .. string.rep(" ", 232) }
CommanderRankCheck.Scan(function(r) result = r end)
Settle()
local keys = {}
for _, ref in ipairs(result.issues) do keys[#keys + 1] = ref.key end
table.sort(keys)
CHECK(table.concat(keys, " ") == "macro:a:Heal:lesser heal:1 macro:a:Long:frostbolt:1 macro:c:Heal:frostbolt:1",
    "a #showtooltip line is read, and same-named macros keep apart", table.concat(keys, " "))
chat = {}
fixed = CommanderRankCheck.FixAll(result)
CHECK(macros[1].body == "#showtooltip Lesser Heal(Rank 3)\n/cast Lesser Heal(Rank 3)",
    "Update moves the tooltip line with the cast line", macros[1].body)
CHECK(macros[121].body == "/cast Frostbolt(Rank 11)", "the character macro of the same name is the one updated",
    macros[121].body)
CHECK(fixed == 2 and #macros[2].body == 255 and macros[2].body:find("Rank 1%)"),
    "a rewrite past 255 characters is refused, the macro untouched", fixed)
CHECK(ChatText():find("255 characters") and ChatText():find("updated 2 of 3"), "Update All says what it could not do and the tally",
    ChatText())

-- ===========================================================================

if os.getenv("DUMP") == "1" then
    io.write("\n--- chat ---\n", ChatText(), "\n")
end
io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

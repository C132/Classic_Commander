-- Commander Rank Check: a unit test for your action bars and macros. It builds
-- the set of highest spell ranks you know from your spellbook, then scans every
-- action slot and every macro for a lower rank of the same spell — the classic
-- chore of re-dragging spells and editing macros after training. It runs on
-- demand (/crank, or Commander Spellbook's Rank Check view) and reports like a
-- test runner: a PASS line when clean, or a list of each stale reference and
-- the rank that should replace it. Macros that /cast a spell WITHOUT a rank
-- always use your highest and are correctly never flagged.
--
-- 3.0 (2026-10-26) splits the scan from the report so Commander Spellbook can
-- show it: CommanderRankCheck.Scan hands back every ranked reference it read
-- (stale or not) and broadcasts it, and two actions act on one —
--   Update  puts the best rank where the old one is: the action slot gets the
--           spell (out of combat, and never over something on the cursor), the
--           macro gets its "(Rank N)" rewritten
--   Keep    leaves it on its rank on purpose (a down-ranked heal), per
--           character, so it stops failing the check and the login run
-- The spellbook button inside Blizzard's book is kept for when Blizzard's book
-- is the one in use; with Commander Spellbook taking over it never shows.

CommanderRankCheck = CommanderRankCheck or {}
local R = CommanderRankCheck

local PREFIX = "|cff66ccffCommander Rank Check|r: "
local BOOKTYPE = "spell"
local NUM_ACTION_SLOTS = 120

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function RankNum(sub)
    return sub and tonumber(tostring(sub):match("%d+")) or 0
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function CharDB()
    if type(CommanderRankCheckChar) ~= "table" then CommanderRankCheckChar = {} end
    if type(CommanderRankCheckChar.Kept) ~= "table" then CommanderRankCheckChar.Kept = {} end
    return CommanderRankCheckChar
end

-- Where the rank actually lives on this client. "Rank 5" is a spell's SUBTEXT,
-- and subtext is no longer a return value of GetSpellInfo or
-- GetSpellBookItemName: the C_Spell SpellInfo struct this client's GetSpellInfo
-- is built on has no subtext field at all, so the old
-- `local name, rank = GetSpellInfo(id)` reads nil for every spell and every
-- action slot looks rankless (which is exactly how this module silently passed
-- while checking nothing). It must be fetched per spell ID — and it loads
-- asynchronously, empty until the client has the spell's text, which is why
-- Blizzard's own spellbook waits on Spell:ContinueOnSpellLoad before drawing
-- its rank line.
local function Subtext(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellSubtext then
        local text = C_Spell.GetSpellSubtext(spellID)
        if text and text ~= "" then return text end
    end
    if GetSpellSubtext then
        local text = GetSpellSubtext(spellID)
        if text and text ~= "" then return text end
    end
    return nil
end

-- Whether the client has the spell's text in hand. This is what tells a
-- genuinely rankless spell (Blink) apart from one whose rank simply has not
-- arrived yet — without it, a slow load and a passive spell look identical and
-- the report happily calls an unread bar clean.
local function TextCached(spellID)
    if not (spellID and C_Spell and C_Spell.IsSpellDataCached) then return true end
    return C_Spell.IsSpellDataCached(spellID) and true or false
end

-- Ask the client to load the text for every spell we are about to inspect, then
-- run onReady once they have all arrived (or a moment later, whichever comes
-- first — a spell whose data never loads must not hang the report). The extra
-- frame before the callback is deliberate: subtext can still read empty inside
-- the load continuation itself.
local function PrimeSpellText(ids, onReady)
    local finished = false
    local function Finish()
        if finished then return end
        finished = true
        if RunNextFrame then
            RunNextFrame(onReady)
        elseif C_Timer then
            C_Timer.After(0, onReady)
        else
            onReady()
        end
    end

    -- Starts at 1 so a spell that resolves synchronously mid-loop cannot drive
    -- the count to zero before the rest are registered.
    local pending = 1
    local function Release()
        pending = pending - 1
        if pending <= 0 then Finish() end
    end

    if Spell and Spell.CreateFromSpellID then
        for id in pairs(ids) do
            local spell = Spell:CreateFromSpellID(id)
            if spell and not spell:IsSpellEmpty() and not spell:IsSpellDataCached() then
                pending = pending + 1
                spell:ContinueOnSpellLoad(Release)
            end
        end
    end
    if C_Timer then C_Timer.After(2, Finish) end
    Release()
end

-- ---------------------------------------------------------------------------
-- Collection. Both passes resolve a spell ID first and read the rank from it;
-- the spellbook's legacy subtext return is kept only as a fallback for entries
-- that report no ID.
-- ---------------------------------------------------------------------------

local function CollectSpellbook()
    local entries = {}
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then
        return entries
    end
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for i = offset + 1, offset + numSpells do
                local name, legacySub, spellID = GetSpellBookItemName(i, BOOKTYPE)
                if name then
                    entries[#entries + 1] = {
                        name = name, spellID = spellID,
                        -- "" is what this client returns here, and an empty
                        -- string is truthy — normalize it away or it masks the
                        -- "rank text never arrived" case entirely.
                        legacySub = (legacySub ~= "") and legacySub or nil,
                    }
                end
            end
        end
    end
    return entries
end

-- Action bar slots 1-120 cover the main bar's six pages plus the side/bottom
-- bars. GetActionInfo returns the spell ID of the exact rank sitting in the
-- slot, which is what makes a stale slot detectable at all.
local function CollectBars()
    local entries = {}
    if not (GetActionInfo and GetSpellInfo) then return entries end
    for slot = 1, NUM_ACTION_SLOTS do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and id ~= 0 then
            entries[#entries + 1] = { slot = slot, spellID = id }
        end
    end
    return entries
end

-- Highest known rank per spell name (lowercased), and the spell ID of that
-- rank (what Update puts on a bar). Non-ranked spells map to 0, so they can
-- never be flagged as outdated.
local function BuildMaxRanks(book, stats)
    local maxRank, bestID = {}, {}
    for _, entry in ipairs(book) do
        local sub = Subtext(entry.spellID) or entry.legacySub
        if not sub and not TextCached(entry.spellID) then
            stats.unresolved = stats.unresolved + 1
        end
        local rank = RankNum(sub)
        local key = entry.name:lower()
        if not maxRank[key] or rank > maxRank[key] then
            maxRank[key] = rank
            bestID[key] = entry.spellID
        end
    end
    return maxRank, bestID
end

-- A kept reference is the player's "this one is on purpose". A bar slot's
-- keep is tied to the exact rank in it: put another spell (or another rank)
-- there and the keep no longer applies. A macro's key carries its rank.
local function IsKept(ref)
    local value = CharDB().Kept[ref.key]
    if value == nil then return false end
    if ref.kind == "BAR" then return value == ref.spellID end
    return value and true or false
end

-- A slot holding a specific rank of a spell is stale if the spellbook has a
-- higher one.
local function CheckActionBars(bars, maxRank, bestID, refs, stats, debugLines)
    for _, entry in ipairs(bars) do
        local name = GetSpellInfo(entry.spellID)
        if name then
            local sub = Subtext(entry.spellID)
            if not sub and not TextCached(entry.spellID) then
                stats.unresolved = stats.unresolved + 1
            end
            local rank = RankNum(sub)
            local key = name:lower()
            local best = maxRank[key]
            if debugLines then
                debugLines[#debugLines + 1] = string.format(
                    "   slot %3d  |cffffd100%s|r  id=%d  rank=%s  known max=%s",
                    entry.slot, name, entry.spellID,
                    rank > 0 and rank or "none", best and best > 0 and best or "unranked")
            end
            if rank > 0 then
                stats.checked = stats.checked + 1
                local ref = {
                    kind = "BAR", slot = entry.slot, key = "bar:" .. entry.slot,
                    where = "Bar slot " .. entry.slot,
                    name = name, spellID = entry.spellID, rank = rank,
                    best = best or rank, bestID = bestID[key],
                    stale = (best and best > rank) and true or false,
                }
                ref.kept = ref.stale and IsKept(ref)
                refs[#refs + 1] = ref
            end
        end
    end
end

-- The "(Rank N)" references in a macro body, with where each one sits: a
-- list of { name, rank, from, to } where from..to is the "(Rank N)" itself.
-- The name class allows parentheses so paren-named spells (e.g. Faerie Fire
-- (Feral)) are caught; leading command words are stripped from the /cast case.
local RANK_PATTERN = "([%a][%a%s'%-%(%)]-)%(Rank%s*(%d+)%)"

local function MacroRanks(body)
    local out = {}
    local init = 1
    while true do
        local from, to, raw, rankStr = body:find(RANK_PATTERN, init)
        if not from then break end
        local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
        name = name:gsub("^[Cc]ast%s+", ""):gsub("^[Uu]se%s+", ""):gsub("^[Cc]astsequence%s+", "")
        -- "#showtooltip Greater Heal(Rank 5)": the line that picks the icon
        -- names a rank too, and Update must move it with the /cast line
        name = name:gsub("^[Ss]howtooltip%s+", ""):gsub("^[Ss]how%s+", "")
        -- The "(Rank N)" itself is the tail of the match: find it from the end
        local rankFrom = body:find("%(Rank%s*%d+%)", from + #raw - 1)
        out[#out + 1] = { name = name, rank = tonumber(rankStr) or 0, from = rankFrom or from, to = to }
        init = to + 1
    end
    return out
end

-- Macros: any explicit "Spell(Rank N)" whose N is below the known max.
-- An account macro and a character macro may share a name, so a reference's
-- key says which list it is in (a, c): keeping one must not keep the other.
local function MacroSide(index)
    return (index > (MAX_ACCOUNT_MACROS or 120)) and "c" or "a"
end

local function CheckMacros(maxRank, bestID, refs, stats)
    if not GetMacroInfo then return end
    local maxIndex = (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18)
    for i = 1, maxIndex do
        local mname, _, body = GetMacroInfo(i)
        if mname and body then
            local seen = {}
            local side = MacroSide(i)
            for _, found in ipairs(MacroRanks(body)) do
                local key = (found.name ~= "") and found.name:lower() or nil
                local best = key and maxRank[key]
                if best and found.rank > 0 then
                    stats.checked = stats.checked + 1
                    local refKey = "macro:" .. side .. ":" .. mname .. ":" .. key .. ":" .. found.rank
                    if not seen[refKey] then
                        seen[refKey] = true
                        local ref = {
                            kind = "MACRO", macro = i, macroName = mname, side = side, key = refKey,
                            where = 'Macro "' .. mname .. '"',
                            name = found.name, rank = found.rank, best = best, bestID = bestID[key],
                            stale = best > found.rank,
                        }
                        ref.kept = ref.stale and IsKept(ref)
                        refs[#refs + 1] = ref
                    end
                end
            end
        end
    end
end

local lastResult

-- Read the book, the bars and the macros, wait for the rank text, and hand
-- back every ranked reference:
--   result.refs        every ranked bar slot and macro reference read
--   result.issues      the stale ones not kept on purpose (what FAILs)
--   result.kept        the stale ones kept on purpose
--   result.checked     how many ranked references were compared
--   result.unresolved  spells whose rank text never arrived
-- opts.verbose collects /crank debug's per-slot lines; opts.bars forces the
-- bar pass on even with Check Action Bars off (the debug dump does).
-- Every result is also broadcast as COMMANDER_RANKCHECK_EVENTS.RESULT.
function R.Scan(onDone, opts)
    opts = opts or {}
    local db = CommanderRankCheckDB or {}
    local scanBars = db.CheckActionBars or opts.bars
    local book = CollectSpellbook()
    local bars = scanBars and CollectBars() or {}

    -- Rank text has to be in hand before anything can be compared, so the whole
    -- report waits on it rather than reading a half-loaded spellbook.
    local ids = {}
    for _, entry in ipairs(book) do
        if entry.spellID then ids[entry.spellID] = true end
    end
    for _, entry in ipairs(bars) do
        ids[entry.spellID] = true
    end
    PrimeSpellText(ids, function()
        local stats = { checked = 0, unresolved = 0 }
        local refs = {}
        local maxRank, bestID = BuildMaxRanks(book, stats)
        local debugLines = opts.verbose and {} or nil
        if scanBars then
            CheckActionBars(bars, maxRank, bestID, refs, stats, debugLines)
        end
        if db.CheckMacros then
            CheckMacros(maxRank, bestID, refs, stats)
        end
        local result = {
            refs = refs, issues = {}, kept = {},
            checked = stats.checked, unresolved = stats.unresolved,
            debugLines = debugLines, bookCount = #book, barCount = #bars, maxRank = maxRank,
        }
        for _, ref in ipairs(refs) do
            if ref.stale and ref.kept then
                result.kept[#result.kept + 1] = ref
            elseif ref.stale then
                result.issues[#result.issues + 1] = ref
            end
        end
        lastResult = result
        if Commander and Commander.Notify and COMMANDER_RANKCHECK_EVENTS and COMMANDER_RANKCHECK_EVENTS.RESULT then
            Commander.Notify(COMMANDER_RANKCHECK_EVENTS.RESULT, result)
        end
        if onDone then onDone(result) end
    end)
end

function R.Last() return lastResult end

function R.Enabled()
    return CommanderRankCheckDB and CommanderRankCheckDB.EnableRankCheck and true or false
end

-- Whether Commander Spellbook should carry the check (its footer and view)
function R.ShowInSpellbook()
    return R.Enabled() and CommanderRankCheckDB.ShowSpellbookButton ~= false
end

local function Report(result, quiet, verbose)
    if verbose then
        local ranked = 0
        for _, rank in pairs(result.maxRank or {}) do
            if rank > 0 then ranked = ranked + 1 end
        end
        Print(string.format("debug — %d spellbook entries (%d ranked spell%s), %d spell action%s on bars.",
            result.bookCount or 0, ranked, ranked == 1 and "" or "s",
            result.barCount or 0, result.barCount == 1 and "" or "s"))
        for _, line in ipairs(result.debugLines or {}) do
            DEFAULT_CHAT_FRAME:AddMessage(line)
        end
        if (result.barCount or 0) == 0 then
            Print("|cffff4040no spell actions found on slots 1-" .. NUM_ACTION_SLOTS ..
                "|r — nothing to check.")
        end
    end

    -- Never report a clean bill of health over spells whose text the client
    -- had not sent yet: an unread rank is an unchecked one, not a passing one.
    local function Caution()
        if result.unresolved > 0 and not quiet then
            Print(string.format(
                "|cffff8000%d spell%s could not be read|r — the client had not sent their rank text. Run /crank again.",
                result.unresolved, result.unresolved == 1 and "" or "s"))
        end
    end

    local kept = #result.kept
    local keptWords = kept > 0 and string.format(" (%d kept on purpose)", kept) or ""
    if #result.issues == 0 then
        if CommanderRankCheckDB.AnnounceClean and not quiet then
            Print(string.format("|cff33ff33PASS|r — all %d ranked reference%s on your bars and macros are current%s.",
                result.checked, result.checked == 1 and "" or "s", keptWords))
        end
        Caution()
        return
    end
    Print(string.format("|cffff4040FAIL|r — %d of %d ranked reference%s out of date%s:",
        #result.issues, result.checked, result.checked == 1 and "" or "s", keptWords))
    -- A comma, not an arrow: the client's fonts draw arrow glyphs as boxes
    -- (Commander_Formulary D10's screenshot)
    for _, issue in ipairs(result.issues) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "   |cffffd100%s|r: %s (Rank %d), |cff33ff33Rank %d|r available",
            issue.where, issue.name, issue.rank, issue.best))
    end
    Caution()
end

-- quiet suppresses the "disabled" and clean PASS lines (used by the auto login
-- run, so it stays silent unless something is actually out of date). verbose
-- dumps what the scan actually sees, slot by slot (/crank debug).
function CommanderRankCheck_Run(quiet, verbose)
    if not (CommanderRankCheckDB and CommanderRankCheckDB.EnableRankCheck) then
        if not quiet then
            Print("module is disabled — enable it in settings (/crank settings).")
        end
        return
    end
    R.Scan(function(result)
        Report(result, quiet, verbose)
    end, { verbose = verbose, bars = verbose })
end

-- ---------------------------------------------------------------------------
-- Acting on a reference
-- ---------------------------------------------------------------------------

-- Rewrite one "Name(Rank from)" in a macro body to "Name(Rank to)". Only the
-- references to that spell at that rank move; everything else in the body is
-- left byte for byte. Returns the new body and how many it changed.
function R.RewriteMacro(body, spellName, fromRank, toRank)
    local want = (spellName or ""):lower()
    local parts, last, changed = {}, 1, 0
    for _, found in ipairs(MacroRanks(body or "")) do
        if found.name:lower() == want and found.rank == fromRank then
            parts[#parts + 1] = body:sub(last, found.from - 1)
            parts[#parts + 1] = "(Rank " .. toRank .. ")"
            last = found.to + 1
            changed = changed + 1
        end
    end
    parts[#parts + 1] = body:sub(last)
    return table.concat(parts), changed
end

local function CursorEmpty()
    if not GetCursorInfo then return true end
    return GetCursorInfo() == nil
end

-- The macro a reference was read from, found again: its own index first
-- (names repeat between the account and character lists), else the first
-- macro of the same name on the same list whose body still holds that
-- reference. Returns index, name, body, the rewritten body.
local function FindMacro(ref)
    local function Try(index)
        local mname, _, body = GetMacroInfo(index)
        if mname ~= ref.macroName or not body then return nil end
        local newBody, changed = R.RewriteMacro(body, ref.name, ref.rank, ref.best)
        if changed == 0 then return nil end
        return index, mname, body, newBody
    end
    local index, mname, body, newBody = Try(ref.macro)
    if index then return index, mname, body, newBody end
    local first = (ref.side == "c") and ((MAX_ACCOUNT_MACROS or 120) + 1) or 1
    local last = (ref.side == "c") and ((MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18))
        or (MAX_ACCOUNT_MACROS or 120)
    for i = first, last do
        index, mname, body, newBody = Try(i)
        if index then return index, mname, body, newBody end
    end
    return nil
end

-- A macro body may hold 255 characters; "(Rank 9)" to "(Rank 10)" grows it
local MACRO_MAX = 255

-- Put the best rank where an old one is, without a word. Out of combat only
-- (action slots and macros are locked mid-fight). A bar slot is only touched
-- if it still holds the rank the scan saw, and only with an empty cursor:
-- PlaceAction swaps, and whatever comes back off the slot is dropped, so a
-- cursor that picked up nothing must never reach it (it would lift the old
-- spell off the bar and drop it). A macro keeps its name and icon the way
-- Blizzard's own macro window saves one: EditMacro(index, nil, nil, body).
-- Returns ok, words.
local function FixOne(ref)
    if not ref or not ref.stale then return false, "nothing to update" end
    if InCombat() then return false, "not in combat" end
    if ref.kind == "BAR" then
        if not (PickupSpell and PlaceAction and ClearCursor and GetActionInfo) then
            return false, "this client cannot place actions"
        end
        if not ref.bestID then return false, "no best rank known" end
        local actionType, id = GetActionInfo(ref.slot)
        if actionType ~= "spell" or id ~= ref.spellID then
            return false, "the slot has changed since the check"
        end
        if not CursorEmpty() then return false, "the cursor is holding something" end
        PickupSpell(ref.bestID)
        local kind = GetCursorInfo and GetCursorInfo()
        if GetCursorInfo and kind ~= "spell" then
            ClearCursor()
            return false, "could not pick up the best rank"
        end
        PlaceAction(ref.slot)
        ClearCursor()
        return true
    elseif ref.kind == "MACRO" then
        if not (GetMacroInfo and EditMacro) then return false, "this client cannot edit macros" end
        local index, _, _, newBody = FindMacro(ref)
        if not index then return false, "the macro has changed since the check" end
        if #newBody > MACRO_MAX then
            return false, "the macro would run past 255 characters; edit it by hand"
        end
        EditMacro(index, nil, nil, newBody)
        return true
    end
    return false, "unknown reference"
end

local function Outcome(ref, ok, words)
    if ok then
        Print(string.format("%s now casts %s (Rank %d).", ref.where, ref.name, ref.best))
    else
        Print(string.format("|cffff8000could not update|r %s (%s, Rank %d): %s.",
            ref.where or "?", ref.name or "?", ref.rank or 0, words or "unknown"))
    end
end

-- Update one reference, and say what happened either way
function R.Fix(ref)
    local ok, words = FixOne(ref)
    Outcome(ref, ok, words)
    return ok, words
end

-- Update every out-of-date reference a result lists (not the kept ones),
-- with a line per failure and one for the lot
function R.FixAll(result)
    result = result or lastResult
    if not result then return 0 end
    if InCombat() then
        Print("|cffff8000not in combat|r: bars and macros are locked mid-fight.")
        return 0
    end
    local fixed, total = 0, 0
    for _, ref in ipairs(result.issues or {}) do
        total = total + 1
        local ok, words = FixOne(ref)
        if ok then fixed = fixed + 1 else Outcome(ref, false, words) end
    end
    Print(string.format("updated %d of %d out-of-date reference%s.", fixed, total, total == 1 and "" or "s"))
    return fixed
end

-- Keep a reference on its rank on purpose, or take that back
function R.Keep(ref, keep)
    if not ref then return end
    local kept = CharDB().Kept
    if keep then
        kept[ref.key] = (ref.kind == "BAR") and ref.spellID or true
    else
        kept[ref.key] = nil
    end
    ref.kept = keep and true or false
end

function R.ClearKept()
    local n = 0
    for _ in pairs(CharDB().Kept) do n = n + 1 end
    CharDB().Kept = {}
    return n
end

-- ---------------------------------------------------------------------------
-- A "Rank Check" button inside Blizzard's spellbook, running the same check:
-- for when Blizzard's book is the one in use. Parented to the spellbook so it
-- shows and hides with it; the setting gates whether it is shown at all, and
-- it stands down while Commander Spellbook has taken the book over.
-- ---------------------------------------------------------------------------
local spellbookButton

local function EnsureSpellbookButton()
    if spellbookButton then return spellbookButton end
    local parent = SpellBookFrame
    if not parent then return nil end
    spellbookButton = CreateFrame("Button", "CommanderRankCheckButton", parent, "UIPanelButtonTemplate")
    spellbookButton:SetSize(104, 22)
    spellbookButton:SetText("Rank Check")
    spellbookButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -44, 82)
    spellbookButton:SetFrameStrata("HIGH")
    spellbookButton:SetScript("OnClick", function()
        if CommanderRankCheck_Run then CommanderRankCheck_Run() end
    end)
    if Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(spellbookButton, "Rank Check",
            "Scan your action bars and macros for spells left on an out-of-date rank (also: /crank).")
    end
    return spellbookButton
end

local function CommanderBookTakesOver()
    local book = CommanderSpellbook
    return type(book) == "table" and type(book.TakingOver) == "function" and book.TakingOver()
end

local function ApplyButton()
    local want = CommanderRankCheckDB and CommanderRankCheckDB.EnableRankCheck
        and CommanderRankCheckDB.ShowSpellbookButton and not CommanderBookTakesOver()
    if want then
        local btn = EnsureSpellbookButton()
        if btn then btn:Show() end
    elseif spellbookButton then
        spellbookButton:Hide()
    end
end

R.ApplyButton = ApplyButton

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        CharDB()
        Commander.AddListener(COMMANDER_RANKCHECK_EVENTS.UPDATE, ApplyButton)
        if COMMANDER_SPELLBOOK_EVENTS and COMMANDER_SPELLBOOK_EVENTS.UPDATE then
            Commander.AddListener(COMMANDER_SPELLBOOK_EVENTS.UPDATE, ApplyButton)
        end
        ApplyButton()
        -- Auto-run a few seconds after login, once the spellbook and action
        -- bars have populated. Quiet unless something is out of date.
        if CommanderRankCheckDB and CommanderRankCheckDB.EnableRankCheck
            and CommanderRankCheckDB.RunOnLogin and C_Timer then
            C_Timer.After(5, function()
                if CommanderRankCheck_Run then CommanderRankCheck_Run(true) end
            end)
        end
    elseif event == "ADDON_LOADED"
        and (addonName == "Blizzard_SpellBookFrame" or addonName == "Blizzard_PlayerSpells") then
        -- Spellbook is load-on-demand on some clients; attach once it exists
        ApplyButton()
    end
end)

-- Commander Rank Check: a unit test for your action bars and macros. It builds
-- the set of highest spell ranks you know from your spellbook, then scans every
-- action slot and every macro for a lower rank of the same spell — the classic
-- chore of re-dragging spells and editing macros after training. It runs on
-- demand (/crank or the spellbook button) and reports like a test runner: a
-- PASS line when clean, or a list of each stale reference and the rank that
-- should replace it. Macros that /cast a spell WITHOUT a rank always use your
-- highest and are correctly never flagged.

local PREFIX = "|cff66ccffCommander Rank Check|r: "
local BOOKTYPE = "spell"
local NUM_ACTION_SLOTS = 120

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function RankNum(sub)
    return sub and tonumber(tostring(sub):match("%d+")) or 0
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

-- Highest known rank per spell name (lowercased). Non-ranked spells map to 0,
-- so they can never be flagged as outdated.
local function BuildMaxRanks(book, stats)
    local maxRank = {}
    for _, entry in ipairs(book) do
        local sub = Subtext(entry.spellID) or entry.legacySub
        if not sub and not TextCached(entry.spellID) then
            stats.unresolved = stats.unresolved + 1
        end
        local rank = RankNum(sub)
        local key = entry.name:lower()
        if not maxRank[key] or rank > maxRank[key] then
            maxRank[key] = rank
        end
    end
    return maxRank
end

-- A slot holding a specific rank of a spell is stale if the spellbook has a
-- higher one.
local function CheckActionBars(bars, maxRank, issues, stats, debugLines)
    for _, entry in ipairs(bars) do
        local name = GetSpellInfo(entry.spellID)
        if name then
            local sub = Subtext(entry.spellID)
            if not sub and not TextCached(entry.spellID) then
                stats.unresolved = stats.unresolved + 1
            end
            local rank = RankNum(sub)
            local best = maxRank[name:lower()]
            if debugLines then
                debugLines[#debugLines + 1] = string.format(
                    "   slot %3d  |cffffd100%s|r  id=%d  rank=%s  known max=%s",
                    entry.slot, name, entry.spellID,
                    rank > 0 and rank or "none", best and best > 0 and best or "unranked")
            end
            if rank > 0 then
                stats.checked = stats.checked + 1
                if best and best > rank then
                    issues[#issues + 1] = {
                        where = "Bar slot " .. entry.slot,
                        name = name, rank = rank, best = best,
                    }
                end
            end
        end
    end
end

-- Macros: any explicit "Spell(Rank N)" whose N is below the known max. The name
-- class allows parentheses so paren-named spells (e.g. Faerie Fire (Feral)) are
-- caught; leading command words are stripped from the /cast case.
local function CheckMacros(maxRank, issues, stats)
    if not GetMacroInfo then return end
    local maxIndex = (MAX_ACCOUNT_MACROS or 120) + (MAX_CHARACTER_MACROS or 18)
    for i = 1, maxIndex do
        local mname, _, body = GetMacroInfo(i)
        if mname and body then
            for raw, rankStr in body:gmatch("([%a][%a%s'%-%(%)]-)%(Rank%s*(%d+)%)") do
                local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
                name = name:gsub("^[Cc]ast%s+", ""):gsub("^[Uu]se%s+", ""):gsub("^[Cc]astsequence%s+", "")
                local rank = tonumber(rankStr) or 0
                local best = (name ~= "") and maxRank[name:lower()]
                if best and rank > 0 then
                    stats.checked = stats.checked + 1
                    if best > rank then
                        issues[#issues + 1] = {
                            where = 'Macro "' .. mname .. '"',
                            name = name, rank = rank, best = best,
                        }
                    end
                end
            end
        end
    end
end

local function Report(book, bars, quiet, verbose)
    local issues, stats = {}, { checked = 0, unresolved = 0 }
    local maxRank = BuildMaxRanks(book, stats)
    local debugLines = verbose and {} or nil

    if CommanderRankCheckDB.CheckActionBars or verbose then
        CheckActionBars(bars, maxRank, issues, stats, debugLines)
    end
    if CommanderRankCheckDB.CheckMacros then
        CheckMacros(maxRank, issues, stats)
    end

    if verbose then
        local ranked = 0
        for _, rank in pairs(maxRank) do
            if rank > 0 then ranked = ranked + 1 end
        end
        Print(string.format("debug — %d spellbook entries (%d ranked spell%s), %d spell action%s on bars.",
            #book, ranked, ranked == 1 and "" or "s", #bars, #bars == 1 and "" or "s"))
        for _, line in ipairs(debugLines) do
            DEFAULT_CHAT_FRAME:AddMessage(line)
        end
        if #bars == 0 then
            Print("|cffff4040no spell actions found on slots 1-" .. NUM_ACTION_SLOTS ..
                "|r — nothing to check.")
        end
    end

    -- Never report a clean bill of health over spells whose text the client
    -- had not sent yet: an unread rank is an unchecked one, not a passing one.
    local function Caution()
        if stats.unresolved > 0 and not quiet then
            Print(string.format(
                "|cffff8000%d spell%s could not be read|r — the client had not sent their rank text. Run /crank again.",
                stats.unresolved, stats.unresolved == 1 and "" or "s"))
        end
    end

    if #issues == 0 then
        if CommanderRankCheckDB.AnnounceClean and not quiet then
            Print(string.format("|cff33ff33PASS|r — all %d ranked reference%s on your bars and macros are current.",
                stats.checked, stats.checked == 1 and "" or "s"))
        end
        Caution()
        return
    end
    Print(string.format("|cffff4040FAIL|r — %d of %d ranked reference%s out of date:",
        #issues, stats.checked, stats.checked == 1 and "" or "s"))
    for _, issue in ipairs(issues) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "   |cffffd100%s|r: %s (Rank %d) \226\134\146 |cff33ff33Rank %d|r available",
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

    local book = CollectSpellbook()
    local bars = (CommanderRankCheckDB.CheckActionBars or verbose) and CollectBars() or {}

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
        Report(book, bars, quiet, verbose)
    end)
end

-- ---------------------------------------------------------------------------
-- A "Rank Check" button inside the spellbook window, running the same check.
-- Parented to the spellbook so it shows and hides with it; the setting only
-- gates whether it is shown at all.
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

local function ApplyButton()
    local want = CommanderRankCheckDB and CommanderRankCheckDB.EnableRankCheck
        and CommanderRankCheckDB.ShowSpellbookButton
    if want then
        local btn = EnsureSpellbookButton()
        if btn then btn:Show() end
    elseif spellbookButton then
        spellbookButton:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_RANKCHECK_EVENTS.UPDATE, ApplyButton)
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

-- Commander Rank Check: a unit test for your action bars and macros. It builds
-- the set of highest spell ranks you know from your spellbook, then scans every
-- action slot and every macro for a lower rank of the same spell — the classic
-- chore of re-dragging spells and editing macros after training. It runs on
-- demand (/crank or the spellbook button) and reports like a test runner: a
-- PASS line when clean, or a list of each stale reference and the rank that
-- should replace it. Macros that /cast a spell WITHOUT a rank always use your
-- highest and are correctly never flagged.

local PREFIX = "|cff66ccffCommander Rank Check|r: "

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function RankNum(sub)
    return sub and tonumber(tostring(sub):match("%d+")) or 0
end

-- Highest known rank per spell name (lowercased). Non-ranked spells map to 0,
-- so they can never be flagged as outdated.
local function BuildMaxRanks()
    local maxRank = {}
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then
        return maxRank
    end
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSpells = GetSpellTabInfo(tab)
        if offset and numSpells then
            for i = offset + 1, offset + numSpells do
                local name, sub = GetSpellBookItemName(i, "spell")
                if name then
                    local rank = RankNum(sub)
                    local key = name:lower()
                    if not maxRank[key] or rank > maxRank[key] then
                        maxRank[key] = rank
                    end
                end
            end
        end
    end
    return maxRank
end

-- Action bar slots 1-120 cover the main bar's six pages plus the side/bottom
-- bars. A slot holding a specific rank of a spell is stale if the spellbook
-- has a higher one.
local function CheckActionBars(maxRank, issues, stats)
    if not (GetActionInfo and GetSpellInfo) then return end
    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id then
            local name, sub = GetSpellInfo(id)
            if name then
                local rank = RankNum(sub)
                if rank > 0 then
                    stats.checked = stats.checked + 1
                    local best = maxRank[name:lower()]
                    if best and best > rank then
                        issues[#issues + 1] = {
                            where = "Bar slot " .. slot,
                            name = name, rank = rank, best = best,
                        }
                    end
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

function CommanderRankCheck_Run()
    if not (CommanderRankCheckDB and CommanderRankCheckDB.EnableRankCheck) then
        Print("module is disabled — enable it in settings (/crank settings).")
        return
    end
    local maxRank = BuildMaxRanks()
    local issues, stats = {}, { checked = 0 }
    if CommanderRankCheckDB.CheckActionBars then CheckActionBars(maxRank, issues, stats) end
    if CommanderRankCheckDB.CheckMacros then CheckMacros(maxRank, issues, stats) end

    if #issues == 0 then
        if CommanderRankCheckDB.AnnounceClean then
            Print(string.format("|cff33ff33PASS|r — all %d ranked reference%s on your bars and macros are current.",
                stats.checked, stats.checked == 1 and "" or "s"))
        end
        return
    end
    Print(string.format("|cffff4040FAIL|r — %d of %d ranked reference%s out of date:",
        #issues, stats.checked, stats.checked == 1 and "" or "s"))
    for _, issue in ipairs(issues) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "   |cffffd100%s|r: %s (Rank %d) \226\134\146 |cff33ff33Rank %d|r available",
            issue.where, issue.name, issue.rank, issue.best))
    end
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
    elseif event == "ADDON_LOADED"
        and (addonName == "Blizzard_SpellBookFrame" or addonName == "Blizzard_PlayerSpells") then
        -- Spellbook is load-on-demand on some clients; attach once it exists
        ApplyButton()
    end
end)

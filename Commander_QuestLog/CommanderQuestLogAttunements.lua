-- Commander Quest Log: the Attunements tab.
--
-- The fourth tab of the quest log window: a course list for TBC. Every raid
-- attunement, heroic key, dungeon key, reputation hub, the flying ranks and
-- a Badge of Justice route, each a guide of steps the tab ticks off by
-- itself. The navigator lists the modules (six categories) and their courses
-- (the guides), each with one word in its state column and a thin bar; the
-- briefing shows the course page (the steps as a single-open accordion with
-- the current one banded) or, with nothing selected, the overview: the
-- phase, where you stand per module, what to continue, what is up next.
-- Over the navigator sits the hero card: continue where you left off.
--
-- Every number and every word comes from the engine
-- (CommanderQuestLogAttune.lua, Q.Attune): phase, guide and step views,
-- scoring, marks, places and Go. This file draws. It registers raw with
-- Q.RegisterTab (not a catalogue instance: the catalogue needs Questie and
-- lists quests, D48) and owns its widgets -- toolbar overlay, card, rows on
-- the navigator child, blocks and quads on the briefing child, action
-- overlay -- built lazily on the first Refresh because the window's frame
-- does not exist before it first opens. It draws only through the window's
-- kit (Q._kit) and the catalogue's instance-free exports (tones, markup,
-- tooltips, the re-ink after a hover).
--
-- Lua 5.1 (which luajit enforces): the main chunk keeps its locals under
-- 120 by holding the names in tables -- W (widgets), S (state), P (the
-- briefing cursor), H (private helpers) and Draw (the painters) -- with each
-- section in its own do-block.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog
local T = {}
Q.Attunements = T

-- The engine and the catalogue's exports. Both load before this file (the
-- TOC order); without either there is nothing to draw with.
local A = Q.Attune
local C = Q.Catalogue
if type(A) ~= "table" or type(C) ~= "table" then return end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local TAB_ID = "ATTUNE"
local FILTER_W = 42
local STATE_W = 60           -- "Not needed" and "200 badges" (A66)
local CARD_H, CARD_GAP, CARD_BAR_H = 46, 4, 4
local MARK_SIZE = 6
local ROW_BAR_H = 2
local PHASE_BTN_W = 110
local NAV_CHILD_W = 262
local SEP, DASH = C.SEP, C.DASH
local Tip, HideTooltip = C.Tip, C.HideTooltip
local ToneRGB, ToneT, InkT, ReinkAfterHover = C.ToneRGB, C.ToneT, C.InkT, C.ReinkAfterHover
local GREEN = { 0.25, 0.82, 0.25 }
local EMPTY = {}

local FILTERS = {
    { key = "ALL", label = "All",
      tip = "Every guide for your faction, including the ones no longer needed and the ones a later phase opens." },
    { key = "TODO", label = "To do", tip = "Guides you still need this phase." },
    { key = "DONE", label = "Done", tip = "Finished guides." },
    { key = "OTHER", label = "Other", tip = "Not needed this phase, or not yet open." },
}
local EMPTY_WORDS = {
    ALL = "No guide matches.", TODO = "Nothing left to do this phase.",
    DONE = "Nothing finished yet.", OTHER = "Nothing else.",
}
local CONTINUE_WORDS = {
    opened = "You opened this guide last", progressed = "You made progress here most recently",
    started = "The first guide you have started", first = "The first guide you can start",
}
local FAINT_STATUS = { OPTIONAL = true, WAIVED = true, LATER = true, PAST = true, NOTE = true }
local NO_MARK_STATUS = { NOTE = true, SET = true, UNSET = true, HIDDEN = true }
local OFF_MESSAGE = "Commander Quest Log: the Attunements tab is switched off (Settings, Attunements)."
local MARK_TIP = "Mark this step done yourself. Shift-click marks the whole guide, for an attunement another character finished."

-- ---------------------------------------------------------------------------
-- The tables that hold the names
-- ---------------------------------------------------------------------------

-- Widgets: the toolbar set, the card, the action bar, and the pools
local W = { filters = {}, rows = {}, blocks = {}, quads = {}, bands = {}, hits = {}, goLines = {} }

-- State
local S = {
    selected = nil, focus = nil, search = "", pendingGuide = nil, pendingStep = nil, reveal = false,
    revealStep = false, showOtherPhases = false, showDone = nil,
    items = {}, totals = {}, steps = nil, summary = nil,
    phase = { n = 1, votes = {} }, selectedTop = nil, selectedHeight = nil,
    continueKey = nil, continueStep = nil, continueReason = nil,
}

-- The briefing cursor
local P = { y = 6, width = 426, block = 1, quad = 1, band = 1, go = 1, hit = 1 }

-- Private helpers and the painters
local H = {}
local Draw = {}

local function Kit() return Q._kit end
local function DB() return CommanderQuestLogDB or {} end

-- The one colour lookup the tab uses for words, strips and marks: the five
-- tones through the catalogue, the four neutrals through the kit; then
-- Paper() wherever it lands on the sheet (D16)
local function TONE(key)
    if key == "primary" or key == "secondary" or key == "faint" or key == "strong" then
        return Kit().Ink(key)
    end
    return ToneRGB(key)
end

-- ---------------------------------------------------------------------------
-- Helpers: data records, words, numbers
-- ---------------------------------------------------------------------------

do
    local byKey = {}

    function H.Data()
        local D = CommanderQuestLogAttuneData
        if type(D) == "table" then return D end
        return nil
    end

    -- The guide's data record (title, phase, unlocks, prerequisites,
    -- accountWide, summary, steps): the engine's index first, else a scan
    function H.DataGuide(key)
        if not key then return nil end
        local index = type(A.byKey) == "table" and A.byKey[key]
        if type(index) == "table" and index.key == key then return index end
        if byKey[key] then return byKey[key] end
        local D = H.Data()
        for _, guide in ipairs(D and D.guides or EMPTY) do
            if guide.key == key then
                byKey[key] = guide
                return guide
            end
        end
        return nil
    end

    function H.DataStep(record, stepKey)
        if not (record and stepKey) then return nil end
        for _, step in ipairs(record.steps or EMPTY) do
            if step.key == stepKey then return step end
        end
        return nil
    end

    -- A value split by faction or side, resolved for this character; nil
    -- while the side is undecided
    function H.Flat(v)
        if type(v) ~= "table" then return v end
        if v.A ~= nil or v.H ~= nil then return v[A.Faction()] end
        if v.ALDOR ~= nil or v.SCRYER ~= nil or v.SCRYERS ~= nil then
            local side = A.Side()
            if not side then return nil end
            if side == "SCRYER" then
                if v.SCRYER ~= nil then return v.SCRYER end
                return v.SCRYERS
            end
            return v[side]
        end
        return v
    end

    -- Inline markup for a status word inside a longer line: the tone through
    -- TONE (the eight keys), then the paper, as every drawn word is (D16)
    function H.Markup(tone, text)
        local r, g, b = Kit().Paper(TONE(tone or "faint"))
        return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5), text or "")
    end

    -- The key the guide's unlock proof names, for the notice ("the
    -- Flamewrought Key"): the ITEM step holding one of the unlock items,
    -- else "the key"
    function H.UnlockKeyName(record)
        local unlock = record and record.unlock
        local ids = {}
        for _, id in ipairs(type(unlock) == "table" and unlock.items or EMPTY) do ids[id] = true end
        for _, step in ipairs(record and record.steps or EMPTY) do
            local item = step.kind == "ITEM" and type(step.item) == "table" and step.item or nil
            if item then
                local hit = ids[H.Flat(item.id)]
                for _, id in ipairs(type(H.Flat(item.anyOf)) == "table" and H.Flat(item.anyOf) or EMPTY) do
                    if ids[id] then hit = true end
                end
                local name = H.Flat(item.name)
                if hit and type(name) == "string" and name ~= "" then return "the " .. name end
            end
        end
        return "the key"
    end

    function H.CategoryLabel(category)
        local D = H.Data()
        for _, row in ipairs(D and D.CATEGORIES or EMPTY) do
            if row.key == category then return row.label end
        end
        for _, item in ipairs(S.items or EMPTY) do
            if item.kind == "header" and item.category == category then return item.label end
        end
        return category or ""
    end

    function H.InstanceName(id)
        local D = H.Data()
        local name = D and type(D.INSTANCES) == "table" and D.INSTANCES[id]
        return type(name) == "string" and name or nil
    end

    function H.PhaseSince(n)
        local D = H.Data()
        local row = D and type(D.PHASES) == "table" and D.PHASES[n]
        return row and row.since or false
    end

    -- "12 Oct" / "22 Oct 2026"
    function H.DateWord(epoch, withYear)
        if type(epoch) ~= "number" or not date then return nil end
        local text = date(withYear and "%d %b %Y" or "%d %b", epoch)
        if type(text) ~= "string" then return nil end
        return (text:gsub("^0", ""))
    end

    function H.Percent(pct)
        return string.format("%d%%", math.floor((tonumber(pct) or 0) * 100 + 0.5))
    end

    function H.FirstSentence(text)
        if type(text) ~= "string" then return nil end
        local first = text:match("^(.-%.)%s") or text
        return first
    end

    -- "1,250" (the rules engine's grouping), the number itself without it
    function H.Num(n)
        local R = Q.Standing
        local text = R and R.FormatNumber and R.FormatNumber(n)
        return text or tostring(n or 0)
    end

    -- The client's standing words, English filling any gap (the
    -- Reputations tab's Labels pattern)
    local labels
    function H.StandingWord(standingID)
        if not labels then
            local out, sex = {}, nil
            if UnitSex then
                local ok, value = pcall(UnitSex, "player")
                if ok then sex = value end
            end
            for n = 1, 8 do
                local text
                if GetText then
                    local ok, value = pcall(GetText, "FACTION_STANDING_LABEL" .. n, sex)
                    if ok then text = value end
                end
                if type(text) ~= "string" or text == "" then text = _G["FACTION_STANDING_LABEL" .. n] end
                if type(text) == "string" and text ~= "" then out[n] = text end
            end
            labels = out
        end
        local R = Q.Standing
        local rank = (tonumber(standingID) or 0) - 1
        if R and R.StandingWord then return R.StandingWord(rank, labels) or "" end
        return labels[rank + 1] or ""
    end

    -- Done steps fold under one line unless the setting, or the session's
    -- override of it, shows them
    function H.ShowDone()
        if S.showDone ~= nil then return S.showDone end
        return DB().AttuneShowDone ~= false
    end

    function H.AutoPhase()
        local votes = S.phase.votes or EMPTY
        return math.max(tonumber(votes.calendar) or 1, tonumber(votes.questie) or 0, tonumber(votes.evidence) or 0)
    end

    -- The step view for a key, among the steps of the selected guide
    function H.StepView(stepKey)
        if not stepKey then return nil end
        for _, view in ipairs(S.steps or EMPTY) do
            if view.key == stepKey then return view end
        end
        return nil
    end

    -- Whether a step of the selected guide is drawn on the page this pass
    function H.IsDrawn(stepKey)
        local view = H.StepView(stepKey)
        if not view then return false end
        if view.section == "SPEND" then return false end
        if view.status == "DONE" and not H.ShowDone() then return false end
        return true
    end

    -- The step the action bar works on: the focused one, else the current
    function H.FocusedView()
        if not S.selected then return nil end
        if S.focus then
            local view = H.StepView(S.focus)
            if view then return view end
        end
        return A.CurrentStep(S.selected)
    end

    function H.HasSideSplit(record)
        for _, step in ipairs(record and record.steps or EMPTY) do
            if step.side then return true end
            local q = step.questId
            if type(q) == "table" and (q.ALDOR ~= nil or q.SCRYER ~= nil) then return true end
            for _, place in ipairs(step.places or EMPTY) do
                if type(place) == "table" and (place.ALDOR ~= nil or place.SCRYER ~= nil) then return true end
            end
        end
        return false
    end

    -- The ink a step's line takes
    function H.LineInk(view)
        if FAINT_STATUS[view.status] or (type(view.reason) == "string" and view.reason:find("^Not counted")) then
            return InkT("faint")
        end
        return InkT("primary")
    end

    -- A place's coordinates, read from the place's own target (fallback is
    -- the authored row's on every coordinate row, door rows included). Never
    -- from data.places[i]: an undecided side-split row is two view places
    -- over one data row, so the indices drift apart after it.
    local function Coords(place)
        local target = place and place.target
        local c = type(target) == "table" and (target.fallback or target.spec) or nil
        if type(c) == "table" and type(c.x) == "number" and type(c.y) == "number" then
            return c.x * 100, c.y * 100
        end
        return nil
    end

    -- "Khadgar, Shattrath City 54.6, 44.2"
    function H.PlaceWhere(place, data)
        local name = place.name or place.zoneName or ""
        local text = name
        local zone = place.zoneName
        if type(zone) == "string" and zone ~= "" and zone ~= name then text = text .. ", " .. zone end
        local x, y = Coords(place)
        if x and y then text = text .. string.format(" %.1f, %.1f", x, y) end
        return text
    end

    -- The place line of an open lesson: the role faint, the place primary
    function H.PlaceLine(place, data)
        if place.role == "inside" then
            return H.Markup("faint", "Inside") .. "  " .. (place.name or place.zoneName or "")
                .. "; Go takes you to its door"
        end
        return H.Markup("faint", place.roleWord or "") .. "  " .. H.PlaceWhere(place, data)
    end

    -- The progress line under an open lesson
    function H.ProgressLine(view, data)
        local p = view.progress
        if type(p) ~= "table" then return nil end
        local have, need = tonumber(p.have) or 0, tonumber(p.need) or 0
        local kind = view.kind
        -- A level lock on any kind carries the level, never the kind's noun
        if view.status == "LOCKED" or kind == "LEVEL" then
            return "Level " .. have .. " of " .. need
        end
        if kind == "REP" then
            return (view.word or "") .. " " .. H.Num(have) .. " of " .. H.Num(need)
        elseif kind == "SKILL" then
            local skill = data and type(data.skill) == "table" and data.skill.name
            return (skill and (skill .. " ") or "") .. have .. " of " .. need
        elseif kind == "ITEM" then
            local item = data and type(data.item) == "table" and H.Flat(data.item.name)
            return have .. " of " .. need .. (item and (" " .. item) or "")
        elseif kind == "KILL" then
            return have .. " of " .. need .. " bosses this lockout"
        elseif kind == "QUEST" and data and type(data.questIds) == "table" then
            return have .. " of " .. need .. " quests"
        end
        return have .. " of " .. need
    end

    function H.SetOwnWidgetsShown(shown)
        if W.toolbar then W.toolbar:SetShown(shown) end
        if W.card then W.card:SetShown(shown) end
        if W.actions then W.actions:SetShown(shown) end
    end

    -- Opens a guide from a page line or the card: at its current step, or
    -- at the one asked for
    function H.OpenGuide(key, stepKey)
        if not key then return end
        A.Touch(key)
        S.selected = key
        S.focus = stepKey
        S.reveal = true
        S.revealStep = true
        Q.Refresh()
    end
end

-- ---------------------------------------------------------------------------
-- Go: the suite's button over the engine's targets
--
-- One pooled opts per button carrying BOTH spec and query functions (the
-- door rule, 4.9: a target holds one of the two, and the suite button's
-- Evaluate runs spec first and asks query only when spec answered nil, so a
-- door row reaches Orders' door table while Orders is loaded and reads
-- "Needs Commander Orders" without it). The kit's LineGo carries a spec
-- function only, so it is not used here.
-- ---------------------------------------------------------------------------

do
    function H.GoOpts(label, width, height)
        local opts = { label = label, width = width, height = height, source = "QuestLog" }
        -- One A.PlaceFor per evaluation, both functions share it
        local function Resolve()
            local t, why
            if opts.target then t, why = opts.target() end
            opts.why = why
            opts.key, opts.questId, opts.note, opts.title = t and t.key, t and t.questId, t and t.note, t and t.title
            return t
        end
        opts.spec = function()
            local t = Resolve()
            return t and t.spec or nil, (t and t.reason) or opts.why
        end
        opts.query = function()
            local t = Resolve()
            return t and t.query or nil, (t and t.reason) or opts.why
        end
        opts.onGo = function(uid)
            if uid and opts.key and opts.key:find("^quest:") and Q.Questie and Q.Questie.NoteGo then
                -- nil: NoteGo's note is the adapter's reputation note only;
                -- the step title the waypoint carries is left alone
                Q.Questie.NoteGo(opts.questId, opts.key, nil)
            end
        end
        opts.fallback = function()
            local t = Resolve()
            if t then A.Go(t) end
        end
        opts.tooltip = function() return opts.tip and opts.tip() or nil end
        return opts
    end

    -- A row "Go" at the right of a briefing line, pooled by position
    function H.LineGo(pool, position, top, targetFn, tipFn)
        local kit = Kit()
        local button = pool[position]
        if not button then
            local opts = H.GoOpts("Go", kit.LINE_GO_W, kit.LINE_GO_H)
            button = kit.GoButton(kit.DetailChild(), opts)
            button._lineOpts = opts
            pool[position] = button
        end
        local opts = button._lineOpts
        opts.target, opts.tip = targetFn, tipFn
        button:ClearAllPoints()
        button:SetPoint("TOPRIGHT", kit.DetailChild(), "TOPRIGHT", -kit.PAD, -(top - 3))
        button:Show()
        kit.RefreshGo(button, true)
        return button
    end
end

-- ---------------------------------------------------------------------------
-- Toolbar overlay: four filters, the count, the phase button and its menu
-- ---------------------------------------------------------------------------

do
    local function PhaseMenuInit()
        if not (UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton) then return end
        local setting = S.phase.votes and S.phase.votes.setting
        if setting == nil then setting = "AUTO" end
        for n = 0, 5 do
            local value = (n == 0) and "AUTO" or n
            local info = UIDropDownMenu_CreateInfo()
            info.text = (n == 0) and "Automatic" or ("Phase " .. n)
            info.value = value
            info.checked = (setting == value)
            info.func = function()
                A.SetPhase(value)
                if CloseDropDownMenus then CloseDropDownMenus() end
                Q.Refresh()
            end
            local sentences = A.PhaseSentences((n == 0) and H.AutoPhase() or n)
            info.tooltipTitle = info.text
            info.tooltipText = table.concat(type(sentences) == "table" and sentences or EMPTY, "\n")
            info.tooltipOnButton = true
            UIDropDownMenu_AddButton(info)
        end
    end

    local function PhaseEnter(self)
        if not GameTooltip then return end
        local phase = S.phase
        local votes = phase.votes or EMPTY
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(phase.short or "", 1, 1, 1)
        GameTooltip:AddLine((phase.name or "") .. "; Blizzard calls it " .. (phase.blizzard or ""), 0.85, 0.85, 0.85, true)
        if phase.why then GameTooltip:AddLine(phase.why, 0.85, 0.85, 0.85, true) end
        GameTooltip:AddLine("Calendar: Phase " .. tostring(votes.calendar or phase.n or 1), 0.7, 0.7, 0.75)
        if votes.questie then
            -- stale: the calendar or the evidence has moved past Questie's number
            local stale = (tonumber(votes.questie) or 0) < H.AutoPhase()
            GameTooltip:AddLine("Questie: Phase " .. tostring(votes.questie) .. (stale and " (stale)" or ""), 0.7, 0.7, 0.75)
        else
            GameTooltip:AddLine("Questie: none", 0.7, 0.7, 0.75)
        end
        if votes.evidence then
            GameTooltip:AddLine("Evidence: Phase " .. tostring(votes.evidence)
                .. (votes.evidenceWhy and (", " .. tostring(votes.evidenceWhy)) or ""), 0.7, 0.7, 0.75, true)
        else
            GameTooltip:AddLine("Evidence: none", 0.7, 0.7, 0.75)
        end
        local setting = votes.setting
        if setting == nil or setting == "AUTO" then
            GameTooltip:AddLine("Your setting: automatic", 0.7, 0.7, 0.75)
        else
            GameTooltip:AddLine("Your setting: Phase " .. tostring(setting), 0.7, 0.7, 0.75)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to choose.", 0.55, 0.55, 0.6)
        GameTooltip:Show()
    end

    function H.BuildToolbar(frame)
        local kit = Kit()
        local bar = CreateFrame("Frame", nil, frame.toolbar)
        bar:SetAllPoints(frame.toolbar)
        W.toolbar = bar

        for index, filter in ipairs(FILTERS) do
            local button = CreateFrame("Button", nil, bar)
            button:SetSize(FILTER_W, kit.TOOLBAR_H)
            button:SetNormalFontObject(GameFontDisableSmall)
            button:SetHighlightFontObject(GameFontHighlightSmall)
            button:SetText(filter.label)
            button:SetPoint("LEFT", bar, "LEFT", (index - 1) * (FILTER_W + 2), 0)
            button.underline = kit.Quad(button, "ARTWORK")
            button.underline:SetHeight(2)
            button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 5, 2)
            button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
            local key = filter.key
            button:SetScript("OnClick", function()
                DB().AttuneFilter = key
                Q.Refresh()
            end)
            Tip(button, filter.label, filter.tip, "ANCHOR_BOTTOM")
            ReinkAfterHover(button, function() Draw.RestyleToolbar() end)
            W.filters[index] = button
        end

        -- "12 shown", beside the shared search box
        local hit = CreateFrame("Frame", nil, bar)
        hit:SetSize(80, kit.TOOLBAR_H)
        hit:SetPoint("LEFT", frame.searchBox, "RIGHT", 8, 0)
        hit:EnableMouse(true)
        W.countHit = hit
        W.countFS = hit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        W.countFS:SetPoint("LEFT", hit, "LEFT", 0, 0)
        W.countFS:SetJustifyH("LEFT")
        Tip(hit, "Shown", function()
            local totals = S.totals or EMPTY
            return string.format("Done %d, To do %d, Not needed %d, Opens later %d",
                totals.done or 0, totals.todo or 0, totals.notNeeded or 0, totals.later or 0)
        end, "ANCHOR_BOTTOM")

        -- The phase button and its menu
        local phaseBtn = CreateFrame("Button", nil, bar)
        phaseBtn:SetSize(PHASE_BTN_W, kit.TOOLBAR_H)
        phaseBtn:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
        phaseBtn:SetNormalFontObject(GameFontNormalSmall)
        phaseBtn:SetHighlightFontObject(GameFontHighlightSmall)
        phaseBtn:SetText("")
        local fs = phaseBtn.GetFontString and phaseBtn:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("RIGHT", phaseBtn, "RIGHT", -4, 0)
            fs:SetJustifyH("RIGHT")
        end
        phaseBtn.underline = kit.Quad(phaseBtn, "ARTWORK")
        phaseBtn.underline:SetHeight(2)
        phaseBtn.underline:SetPoint("BOTTOMLEFT", phaseBtn, "BOTTOMLEFT", 5, 2)
        phaseBtn.underline:SetPoint("BOTTOMRIGHT", phaseBtn, "BOTTOMRIGHT", -5, 2)
        phaseBtn:SetScript("OnClick", function(self)
            if ToggleDropDownMenu and W.phaseMenu then ToggleDropDownMenu(1, nil, W.phaseMenu, self, 0, 0) end
        end)
        phaseBtn:SetScript("OnEnter", PhaseEnter)
        phaseBtn:SetScript("OnLeave", HideTooltip)
        ReinkAfterHover(phaseBtn, function() Draw.RestyleToolbar() end)
        W.phaseBtn = phaseBtn

        -- Never anchored, like the suite's other menu frames: a MENU
        -- dropdown keeps an invisible button of its own that would eat
        -- clicks. The list hangs off the phase button (ToggleDropDownMenu).
        local menu = CreateFrame("Frame", "CommanderQuestLogAttunePhaseMenu", frame, "UIDropDownMenuTemplate")
        if UIDropDownMenu_Initialize then UIDropDownMenu_Initialize(menu, PhaseMenuInit, "MENU") end
        W.phaseMenu = menu
    end

    function Draw.Toolbar()
        local kit = Kit()
        local db = DB()
        local ar, ag, ab = kit.InkAccent()
        local current = db.AttuneFilter or "ALL"
        for index, filter in ipairs(FILTERS) do
            local button = W.filters[index]
            local active = current == filter.key
            if button.SetNormalFontObject then
                button:SetNormalFontObject(active and GameFontNormalSmall or GameFontDisableSmall)
            end
            -- After the font object, never before: the swap re-applies the
            -- font's own grey
            local fs = button.GetFontString and button:GetFontString()
            if fs then
                if active then fs:SetTextColor(kit.Ink("strong")) else fs:SetTextColor(kit.Ink("faint")) end
            end
            button.underline:SetVertexColor(ar, ag, ab, active and 0.95 or 0)
        end

        -- The guides the search and the filter leave on the list, folded
        -- modules included (their headers count what they hold)
        local shown, fromHeaders = 0, false
        for _, item in ipairs(S.items or EMPTY) do
            if item.kind == "header" and type(item.shown) == "number" then
                shown, fromHeaders = shown + item.shown, true
            end
        end
        if not fromHeaders then
            for _, item in ipairs(S.items or EMPTY) do
                if item.kind == "guide" then shown = shown + 1 end
            end
        end
        W.countFS:SetText(string.format("%d shown", shown))
        W.countFS:SetTextColor(kit.Ink("secondary"))

        local phase = S.phase
        local setting = phase.votes and phase.votes.setting
        local set = setting ~= nil and setting ~= "AUTO"
        local button = W.phaseBtn
        if button.SetNormalFontObject then button:SetNormalFontObject(GameFontNormalSmall) end
        button:SetText((phase.short or "") .. (set and " (set)" or ""))
        local fs = button.GetFontString and button:GetFontString()
        if fs then
            if set then fs:SetTextColor(kit.Ink("secondary")) else fs:SetTextColor(ar, ag, ab) end
        end
        button.underline:SetVertexColor(ar, ag, ab, 0.6)
    end

    -- The labels again, after a hover put a font's own colour back
    function Draw.RestyleToolbar()
        if W.toolbar and W.toolbar:IsShown() and Kit() then Draw.Toolbar() end
    end
end

-- ---------------------------------------------------------------------------
-- The hero card: continue where you left off
-- ---------------------------------------------------------------------------

do
    local function CardEnter(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Continue where you left off", 1, 1, 1)
        local key, step, reason = S.continueKey, S.continueStep, S.continueReason
        local record = H.DataGuide(key)
        if key and record then
            GameTooltip:AddLine(record.title or record.name or "", 0.85, 0.85, 0.85, true)
            local view = A.CurrentStep(key)
            if view and step and view.key ~= step then view = nil end
            if view then
                GameTooltip:AddLine(view.title or "", 0.85, 0.85, 0.85, true)
                if view.how then GameTooltip:AddLine(view.how, 0.7, 0.7, 0.75, true) end
            end
            local sentence = CONTINUE_WORDS[reason]
            if sentence then GameTooltip:AddLine(sentence, 0.7, 0.7, 0.75, true) end
        elseif reason == "done" then
            GameTooltip:AddLine("Everything needed this phase is done.", 0.85, 0.85, 0.85, true)
        else
            GameTooltip:AddLine("Pick a guide to begin.", 0.85, 0.85, 0.85, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open. Right-click for the overview.", 0.55, 0.55, 0.6)
        GameTooltip:Show()
    end

    function H.BuildCard(frame)
        local kit = Kit()
        local card = CreateFrame("Button", nil, frame)
        card:SetSize(kit.NAV_W, CARD_H)
        card:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
        card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        card.bg = kit.Quad(card, "BACKGROUND")
        card.bg:SetAllPoints()
        card.rule = kit.Quad(card, "ARTWORK")
        card.rule:SetHeight(1)
        card.rule:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card.rule:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)

        card.name = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        card.name:SetPoint("RIGHT", card, "RIGHT", -104, 0)
        card.name:SetJustifyH("LEFT")
        if card.name.SetWordWrap then card.name:SetWordWrap(false) end

        card.totals = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        card.totals:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
        card.totals:SetJustifyH("RIGHT")

        card.barBg = kit.Quad(card, "ARTWORK", 1)
        card.barBg:SetHeight(CARD_BAR_H)
        card.barBg:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -24)
        card.barBg:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -24)
        card.bar = kit.Quad(card, "ARTWORK", 2)
        card.bar:SetHeight(CARD_BAR_H)
        card.bar:SetPoint("TOPLEFT", card.barBg, "TOPLEFT", 0, 0)

        card.note = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -32)
        card.note:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.note:SetJustifyH("LEFT")
        -- One line, cut short rather than wrapped: the card is CARD_H tall
        if card.note.SetWordWrap then card.note:SetWordWrap(false) end
        if card.note.SetMaxLines then card.note:SetMaxLines(1) end

        local highlight = card:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(kit.QUAD)
        highlight:SetVertexColor(1, 1, 1, 0.05)
        card:SetHighlightTexture(highlight)

        card:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                S.selected = nil
                Q.Refresh()
                return
            end
            if S.continueKey then
                H.OpenGuide(S.continueKey, S.continueStep)
            end
        end)
        card:SetScript("OnEnter", CardEnter)
        card:SetScript("OnLeave", HideTooltip)
        W.card = card
    end

    function Draw.Card()
        local card, kit = W.card, Kit()
        local ar, ag, ab = kit.InkAccent()
        if kit.OnPaper() then
            card.bg:SetVertexColor(0.30, 0.20, 0.08, 0.10)
        else
            card.bg:SetVertexColor(0, 0, 0, 0.4)
        end
        card.rule:SetVertexColor(ar, ag, ab, 0.35)
        if kit.OnPaper() then card.barBg:SetVertexColor(0, 0, 0, 0.14) else card.barBg:SetVertexColor(1, 1, 1, 0.1) end

        local key, reason = S.continueKey, S.continueReason
        local item = key and A.Guide(key) or nil
        local totals = S.totals or EMPTY
        local name, ratio, note, pct, green
        if item then
            name = item.name or ""
            if item.status == "RECURRING" then
                ratio = item.word or ""
            else
                ratio = string.format("%d/%d", item.done or 0, item.total or 0)
            end
            local title = item.currentTitle or ""
            if item.currentLocked then
                note = "Locked: " .. title
            elseif (item.done or 0) == 0 then
                note = "Start here: " .. title
            else
                note = "Next: " .. title
            end
            pct = (item.status == "RECURRING") and 0 or (item.pct or 0)
            green = item.status == "DONE"
        elseif reason == "done" then
            name = "Attunements"
            ratio = string.format("%d/%d", totals.done or 0, totals.needed or 0)
            note = "Everything needed this phase is done."
            pct, green = 1, true
        else
            name = "Attunements"
            ratio = string.format("%d/%d", totals.done or 0, totals.needed or 0)
            note = "Pick a guide to begin."
            pct = 0
        end

        card.name:SetFontObject(GameFontNormal)
        card.name:SetText(name)
        card.name:SetTextColor(ar, ag, ab)
        card.totals:SetFontObject(GameFontNormalSmall)
        card.totals:SetText(ratio)
        card.totals:SetTextColor(kit.Paper(kit.Ink("primary")))

        local span = (card:GetWidth() or 0) - 16
        if span <= 0 then span = kit.NAV_W - 16 end
        if pct > 0 then
            card.bar:SetWidth(math.max(1, span * math.min(pct, 1)))
            if green then
                local r, g, b = kit.Paper(GREEN[1], GREEN[2], GREEN[3])
                card.bar:SetVertexColor(r, g, b, 0.95)
            else
                card.bar:SetVertexColor(ar, ag, ab, 0.9)
            end
            card.bar:Show()
        else
            card.bar:Hide()
        end

        card.note:SetFontObject(GameFontDisableSmall)
        card.note:SetText(note)
        card.note:SetTextColor(kit.Paper(kit.Ink("faint")))
    end
end

-- ---------------------------------------------------------------------------
-- Navigator rows: module headers and guide rows (never lessons, D51)
-- ---------------------------------------------------------------------------

do
    local function RowClick(self, button)
        if self.category then
            local db = DB()
            local collapsed = db.AttuneCollapsed
            if type(collapsed) ~= "table" then
                collapsed = {}
                db.AttuneCollapsed = collapsed
            end
            collapsed[self.category] = (not collapsed[self.category]) or nil
            Q.Refresh()
            return
        end
        local key = self.guideKey
        if not key then return end
        if button == "RightButton" then
            if IsControlKeyDown and IsControlKeyDown() then
                local view = A.CurrentStep(key)
                if view then A.Go((A.PlaceFor(view, nil))) end
            end
            return
        end
        -- Clicking the open course again goes back to the overview
        if S.selected == key then
            S.selected = nil
        else
            S.selected = key
            S.focus = nil
            A.Touch(key)
            S.revealStep = true
            local scroll = Kit().DetailScroll()
            if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
        end
        Q.Refresh()
    end

    local function RowEnter(self)
        local item = self.item
        if not (item and GameTooltip) then return end
        local record = H.DataGuide(item.key)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(record and record.title or item.title or item.name or "", 1, 1, 1)
        local summary = H.FirstSentence(record and record.summary)
        if summary then GameTooltip:AddLine(summary, 0.85, 0.85, 0.85, true) end
        if item.status == "RECURRING" then
            GameTooltip:AddLine((item.word or "") .. " in bags and bank, resets with each lockout", 0.85, 0.85, 0.85)
        elseif (item.total or 0) > 0 then
            GameTooltip:AddLine(string.format("%d of %d steps, %s", item.done or 0, item.total or 0, H.Percent(item.pct)),
                0.85, 0.85, 0.85)
        end
        if item.minLevel then
            if item.underLevel then
                local r, g, b = ToneRGB("warn")
                GameTooltip:AddLine("From level " .. item.minLevel .. ", you are " .. tostring(A.Level()), r, g, b)
            else
                GameTooltip:AddLine("From level " .. item.minLevel, 0.7, 0.7, 0.75)
            end
        end
        local sentence = item.notice
        if not sentence then
            if item.status == "LATER" and record then
                local n = record.phase and record.phase.introduced
                local since = H.DateWord(H.PhaseSince(n), true)
                sentence = "Opens in Phase " .. tostring(n) .. (since and (" on " .. since) or ", no date announced") .. "."
            elseif item.account then
                sentence = "Done by " .. tostring(item.account.char) .. ", " .. (H.DateWord(item.account.at) or "")
            end
        end
        if sentence then GameTooltip:AddLine(sentence, 0.7, 0.7, 0.75, true) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to open. " .. ((Commander and Commander.UI and Commander.UI.GoRowHint) or ""),
            0.55, 0.55, 0.6)
        GameTooltip:Show()
    end

    local function AcquireRow(position)
        local row = W.rows[position]
        if row then return row end
        local kit = Kit()
        row = CreateFrame("Button", nil, kit.NavChild())
        row:SetHeight(kit.QUEST_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.selection = kit.Quad(row, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:Hide()

        row.strip = kit.Quad(row, "ARTWORK", 1)
        row.strip:SetWidth(3)
        row.strip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.strip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.strip:Hide()

        row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.title:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.title:SetJustifyH("LEFT")
        if row.title.SetWordWrap then row.title:SetWordWrap(false) end

        row.state = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.state:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.state:SetWidth(STATE_W)
        row.state:SetJustifyH("RIGHT")

        row.barBg = kit.Quad(row, "ARTWORK", 1)
        row.barBg:SetHeight(ROW_BAR_H)
        row.barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 14, 3)
        row.barBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
        row.barBg:Hide()
        row.bar = kit.Quad(row, "ARTWORK", 2)
        row.bar:SetHeight(ROW_BAR_H)
        row.bar:SetPoint("BOTTOMLEFT", row.barBg, "BOTTOMLEFT", 0, 0)
        row.bar:Hide()

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(kit.QUAD)
        highlight:SetVertexColor(1, 1, 1, 0.07)
        row:SetHighlightTexture(highlight)

        row:SetScript("OnClick", RowClick)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", HideTooltip)
        W.rows[position] = row
        return row
    end

    local function LayoutHeaderRow(row, item, ar, ag, ab)
        local kit = Kit()
        row.category = item.category
        row:SetHeight(kit.ROW_H)
        kit.PointChevron(row, not item.collapsed)
        for _, bar in ipairs(row.chevron) do
            bar:SetVertexColor(ar, ag, ab, 0.9)
            bar:Show()
        end
        row.title:SetFontObject(GameFontNormalSmall)
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row, "LEFT", 20, 0)
        row.title:SetPoint("RIGHT", row, "RIGHT", -(STATE_W + 8), 0)
        row.title:SetText(item.label or "")
        row.title:SetTextColor(ar, ag, ab)
        row.state:SetFontObject(GameFontNormalSmall)
        if item.category == "BADGES" then
            row.state:SetText("")
        else
            local set = kit.InkSet()
            row.state:SetText(string.format("|cff%s%d|r/|cff%s%d|r", set.countDone, item.done or 0, set.countAll, item.total or 0))
        end
        row.state:SetTextColor(kit.Paper(kit.Ink("secondary")))
        row.selection:SetVertexColor(ar, ag, ab, 0.08)
        row.selection:Show()
    end

    local function LayoutGuideRow(row, item, ar, ag, ab)
        local kit = Kit()
        row.guideKey, row.item = item.key, item
        if row.chevron then
            for _, bar in ipairs(row.chevron) do bar:Hide() end
        end
        local hasRatio = item.status == "PROGRESS" or item.status == "DONE"
        local withBar = DB().ShowProgress ~= false and hasRatio
        row:SetHeight(withBar and kit.QUEST_ROW_H_BAR or kit.QUEST_ROW_H)

        local strip = item.strip
        if not strip then
            if item.status == "DONE" then strip = "good"
            elseif item.status == "LATER" then strip = "warn"
            elseif item.status == "RECURRING" then strip = "open"
            elseif item.status == "PROGRESS" and (item.done or 0) > 0 then strip = "open"
            else strip = "faint" end
        end
        row.strip:SetVertexColor(kit.Paper(TONE(strip)))
        row.strip:Show()

        local selected = S.selected ~= nil and item.key == S.selected
        row.title:SetFontObject(GameFontNormalSmall)
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.title:SetPoint("RIGHT", row, "RIGHT", -(STATE_W + 10), 0)
        row.title:SetText(item.name or "")
        if selected then
            row.title:SetTextColor(kit.Paper(kit.Ink("strong")))
        elseif item.bucket == "OTHER" then
            row.title:SetTextColor(kit.Paper(kit.Ink("faint")))
        else
            row.title:SetTextColor(kit.Paper(kit.Ink("primary")))
        end

        row.state:SetFontObject(GameFontNormalSmall)
        row.state:SetText(item.word or "")
        local tone = item.tone
        if item.status == "PROGRESS" then tone = "secondary" end
        row.state:SetTextColor(kit.Paper(TONE(tone or "faint")))

        if withBar then
            if kit.OnPaper() then row.barBg:SetVertexColor(0, 0, 0, 0.14) else row.barBg:SetVertexColor(1, 1, 1, 0.1) end
            row.barBg:Show()
            local pct = item.pct or 0
            if pct > 0 then
                local span = kit.NavChild():GetWidth() or 0
                if span <= 0 then span = NAV_CHILD_W end
                row.bar:SetWidth(math.max(1, (span - 22) * math.min(pct, 1)))
                if item.status == "DONE" then
                    local r, g, b = kit.Paper(GREEN[1], GREEN[2], GREEN[3])
                    row.bar:SetVertexColor(r, g, b, 0.95)
                else
                    row.bar:SetVertexColor(ar, ag, ab, 0.8)
                end
                row.bar:Show()
            end
        end

        if selected then
            row.selection:SetVertexColor(ar, ag, ab, 0.22)
            row.selection:Show()
        end
    end

    function Draw.Rows()
        local kit = Kit()
        local navChild = kit.NavChild()
        local ar, ag, ab = kit.InkAccent()
        local y = 4
        S.selectedTop, S.selectedHeight = nil, nil

        local items = S.items or EMPTY
        for position, item in ipairs(items) do
            local row = AcquireRow(position)
            row.category, row.guideKey, row.item = nil, nil, nil
            row.selection:Hide()
            row.strip:Hide()
            row.barBg:Hide()
            row.bar:Hide()
            if item.kind == "header" then
                LayoutHeaderRow(row, item, ar, ag, ab)
            else
                LayoutGuideRow(row, item, ar, ag, ab)
                if S.selected and item.key == S.selected then
                    S.selectedTop, S.selectedHeight = y, row:GetHeight()
                end
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)
            row:Show()
            y = y + row:GetHeight()
        end
        for position = #items + 1, #W.rows do W.rows[position]:Hide() end

        if #items == 0 then
            if not W.emptyFS then
                W.emptyFS = navChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                W.emptyFS:SetPoint("TOPLEFT", navChild, "TOPLEFT", 12, -16)
                W.emptyFS:SetWidth(kit.NAV_W - 30)
                W.emptyFS:SetJustifyH("LEFT")
            end
            local word
            if S.search ~= "" then word = EMPTY_WORDS.ALL else word = EMPTY_WORDS[DB().AttuneFilter or "ALL"] or EMPTY_WORDS.ALL end
            W.emptyFS:SetFontObject(GameFontDisableSmall)
            W.emptyFS:SetText(word)
            W.emptyFS:SetTextColor(kit.Paper(kit.Ink("faint")))
            W.emptyFS:Show()
            y = y + 60
        elseif W.emptyFS then
            W.emptyFS:Hide()
        end
        navChild:SetHeight(math.max(y + 6, 1))
    end
end

-- ---------------------------------------------------------------------------
-- The briefing: drawing primitives (the catalogue's, with the cursor P;
-- font and colour put back on every pass, D15)
-- ---------------------------------------------------------------------------

do
    local function AcquireBlock(position, template)
        local block = W.blocks[position]
        if not block then
            block = Kit().DetailChild():CreateFontString(nil, "ARTWORK", template)
            block:SetJustifyH("LEFT")
            block:SetJustifyV("TOP")
            block._template = template
            W.blocks[position] = block
            return block
        end
        if block._template ~= template then
            block._template = template
            local font = _G[template]
            if font and block.SetFontObject then block:SetFontObject(font) end
        end
        return block
    end

    local function AcquireQuad(pool, position, layer)
        local quad = pool[position]
        if quad then return quad end
        quad = Kit().Quad(Kit().DetailChild(), layer)
        pool[position] = quad
        return quad
    end

    -- One line of text at the cursor; colour is an {r, g, b} table and goes
    -- through Paper() here. Returns block, height.
    function H.Line(text, template, colour, indent, right)
        local kit = Kit()
        indent = indent or 0
        local block = AcquireBlock(P.block, template or "GameFontHighlightSmall")
        P.block = P.block + 1
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -P.y)
        block:SetWidth(P.width - indent - (right or 0))
        block:SetText(text or "")
        local c = colour or InkT("secondary")
        block:SetTextColor(kit.Paper(c[1], c[2], c[3]))
        block:Show()
        local height = math.max(block:GetStringHeight() or 12, 12)
        P.y = P.y + height + 3
        return block, height
    end

    function H.Heading(text)
        return H.Line(text, "GameFontNormalSmall", { Kit().InkAccent() })
    end

    -- A bar: a ground quad and an accent fill across `fraction` of it,
    -- green once full
    function H.Bar(indent, height, fraction, gap)
        local kit = Kit()
        local span = P.width - indent
        local ground = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        ground:ClearAllPoints()
        ground:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -P.y)
        ground:SetSize(span, height)
        if kit.OnPaper() then ground:SetVertexColor(0, 0, 0, 0.14) else ground:SetVertexColor(1, 1, 1, 0.1) end
        ground:Show()
        if fraction and fraction > 0 then
            local fill = AcquireQuad(W.quads, P.quad, "ARTWORK")
            P.quad = P.quad + 1
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", ground, "TOPLEFT", 0, 0)
            fill:SetSize(math.max(1, span * math.min(fraction, 1)), height)
            if fraction >= 1 then
                local r, g, b = kit.Paper(GREEN[1], GREEN[2], GREEN[3])
                fill:SetVertexColor(r, g, b, 0.95)
            else
                local r, g, b = kit.InkAccent()
                fill:SetVertexColor(r, g, b, 0.9)
            end
            fill:Show()
        end
        P.y = P.y + height + (gap or 6)
    end

    function H.Rule(spacingAbove)
        local kit = Kit()
        P.y = P.y + (spacingAbove or 6)
        local rule = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD, -P.y)
        rule:SetSize(P.width, 1)
        local r, g, b = kit.InkAccent()
        rule:SetVertexColor(r, g, b, 0.25)
        rule:Show()
        P.y = P.y + 7
    end

    -- A small square at the cursor for a step's state (a quad, never a
    -- bullet glyph, D11). It does not move the cursor.
    function H.Mark(indent, toneKey)
        local kit = Kit()
        local mark = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -(P.y + 3))
        mark:SetSize(MARK_SIZE, MARK_SIZE)
        local r, g, b = kit.Paper(TONE(toneKey or "faint"))
        mark:SetVertexColor(r, g, b, 1)
        mark:Show()
    end

    -- The accent band under the current step's line
    function H.Band(top, height)
        local kit = Kit()
        local band = AcquireQuad(W.bands, P.band, "BACKGROUND")
        P.band = P.band + 1
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD - 2, -top)
        band:SetSize(P.width + 4, height)
        local r, g, b = kit.InkAccent()
        band:SetVertexColor(r, g, b, 0.16)
        band:Show()
    end

    -- A line with the tab's own Go at its right
    function H.GoLine(text, colour, indent, targetFn, tipFn)
        local kit = Kit()
        local top = P.y
        local block, height = H.Line(text, "GameFontHighlightSmall", colour, indent, kit.LINE_GO_W + 6)
        H.LineGo(W.goLines, P.go, top, targetFn, tipFn)
        P.go = P.go + 1
        P.y = math.max(P.y, top + kit.LINE_GO_H)
        return block, height
    end

    -- An invisible button over a line: a click and a tooltip, nothing drawn
    -- but its hover
    function H.Hit(top, height, onClick, onEnter, right)
        local kit = Kit()
        local hit = W.hits[P.hit]
        if not hit then
            hit = CreateFrame("Button", nil, kit.DetailChild())
            hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local highlight = hit:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetTexture(kit.QUAD)
            highlight:SetVertexColor(1, 1, 1, 0.05)
            hit:SetHighlightTexture(highlight)
            hit:SetScript("OnClick", function(self, button) if self.onClick then self.onClick(self, button) end end)
            hit:SetScript("OnEnter", function(self) if self.onEnter then self.onEnter(self) end end)
            hit:SetScript("OnLeave", HideTooltip)
            W.hits[P.hit] = hit
        end
        P.hit = P.hit + 1
        hit.onClick, hit.onEnter = onClick, onEnter
        hit:ClearAllPoints()
        hit:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD, -(top - 1))
        hit:SetSize(math.max(1, P.width - (right or 0)), height + 2)
        hit:Show()
        return hit
    end
end

-- ---------------------------------------------------------------------------
-- The briefing: the course page
-- ---------------------------------------------------------------------------

do
    local Line, Heading, Bar, Rule, Mark, Band, GoLine, Hit =
        H.Line, H.Heading, H.Bar, H.Rule, H.Mark, H.Band, H.GoLine, H.Hit

    -- A step's line: mark, word and title, a Go when its default place has
    -- a target. Returns top, height, hasGo.
    function Draw.StepLine(view, tipFn)
        local top = P.y
        local tone = view.tone or "faint"
        local isNote = view.status == "NOTE"
        if not isNote then Mark(4, tone) end
        local text
        if isNote then
            text = view.title or ""
        else
            text = H.Markup(tone, view.word or "") .. "  " .. (view.title or "")
        end
        local colour = H.LineInk(view)
        local target = (A.PlaceFor(view, nil))
        local block, height
        if target then
            block, height = GoLine(text, colour, 16, function() return (A.PlaceFor(view, nil)) end, tipFn)
        else
            block, height = Line(text, "GameFontHighlightSmall", colour, 16)
        end
        return top, height, target ~= nil
    end

    -- The row tooltip of a step line
    local function StepEnter(view, record)
        return function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(view.title or "", 1, 1, 1)
            if type(view.reason) == "string" and view.reason ~= "" then
                -- The five tones keep their colour; the neutral inks are the
                -- sheet's, so the dark tooltip takes its own greys
                local tone = view.tone or "faint"
                local r, g, b = 0.85, 0.85, 0.85
                if C.TONES and C.TONES[tone] then
                    r, g, b = ToneRGB(tone)
                elseif tone == "faint" then
                    r, g, b = 0.7, 0.7, 0.75
                end
                GameTooltip:AddLine(view.reason, r, g, b, true)
            end
            for _, place in ipairs(view.places or EMPTY) do
                GameTooltip:AddLine((place.roleWord or "") .. ": " .. H.PlaceWhere(place), 0.7, 0.7, 0.75, true)
            end
            if view.how and view.status ~= "NOTE" then GameTooltip:AddLine("How the tab knows: " .. view.how, 0.7, 0.7, 0.75, true) end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine((Commander and Commander.UI and Commander.UI.GoRowHint) or "", 0.55, 0.55, 0.6)
            GameTooltip:Show()
        end
    end

    local function StepClick(view, summary)
        return function(_, button)
            if button == "RightButton" then
                if IsControlKeyDown and IsControlKeyDown() then A.Go((A.PlaceFor(view, nil))) end
                return
            end
            local open = S.focus or (summary and summary.current)
            if open == view.key then S.focus = nil else S.focus = view.key end
            Q.Refresh()
        end
    end

    -- The open lesson's body under its line
    local function Body(view, record)
        local kit = Kit()
        local data = H.DataStep(record, view.key)
        local n = S.phase.n
        -- A note has no reason and nothing to tick: no Checked line
        if type(view.reason) == "string" and view.reason ~= "" then
            Line("Checked: " .. view.reason, "GameFontNormalSmall", { TONE(view.tone or "faint") }, 16)
        end
        local detail = view.detail
        if data and type(data.detailByPhase) == "table" then
            detail = H.Flat(data.detailByPhase[n]) or detail
        end
        if type(detail) == "string" and detail ~= "" then
            Line(detail, "GameFontHighlightSmall", InkT("secondary"), 16)
        end
        for i, place in ipairs(view.places or EMPTY) do
            local text = H.PlaceLine(place)
            if (A.PlaceFor(view, i)) then
                GoLine(text, InkT("primary"), 16, function() return (A.PlaceFor(view, i)) end, nil)
            else
                Line(text, "GameFontHighlightSmall", InkT("primary"), 16)
            end
        end
        local progress = H.ProgressLine(view, data)
        if progress then Line(progress, "GameFontHighlightSmall", ToneT("open"), 16) end
        if data then
            local cost = H.Flat(data.cost)
            if type(cost) == "string" and cost ~= "" then
                Line("Costs " .. cost, "GameFontHighlightSmall", InkT("secondary"), 16)
            end
            local pouch = data.pouch
            if type(pouch) == "table" then
                Line("Pouch: " .. tostring(H.Flat(pouch.name) or "") .. ", " .. tostring(H.Flat(pouch.cost) or "")
                    .. " at " .. H.StandingWord(pouch.standing or 7), "GameFontHighlightSmall", InkT("secondary"), 16)
            end
            local needs = data.needs
            if type(needs) == "table" and H.Flat(needs.name) then
                Line("Needs: " .. tostring(H.Flat(needs.name)), "GameFontHighlightSmall", InkT("secondary"), 16)
            end
            local needsStanding = data.needsStanding
            if type(needsStanding) == "table" and H.Flat(needsStanding.factionName) then
                Line("Needs: " .. tostring(H.Flat(needsStanding.factionName)) .. " at "
                    .. H.StandingWord(needsStanding.standing or 5), "GameFontHighlightSmall", InkT("secondary"), 16)
            end
            local provided = data.provided
            if type(provided) == "table" and H.Flat(provided.name) then
                Line("Gives: " .. tostring(H.Flat(provided.name)), "GameFontHighlightSmall", InkT("secondary"), 16)
            end
            local questItem = data.questItem
            if type(questItem) == "table" and H.Flat(questItem.name) then
                local count = tonumber(questItem.count)
                Line("Item: " .. tostring(H.Flat(questItem.name)) .. ((count and count > 1) and (", " .. count) or ""),
                    "GameFontHighlightSmall", InkT("secondary"), 16)
            end
            for _, row in ipairs(type(data.questItems) == "table" and data.questItems or EMPTY) do
                if type(row) == "table" and H.Flat(row.name) then
                    Line("Item: " .. tostring(H.Flat(row.name)), "GameFontHighlightSmall", InkT("secondary"), 16)
                end
            end
            for _, row in ipairs(type(data.list) == "table" and data.list or EMPTY) do
                if type(row) == "table" and row.name then
                    Line(tostring(row.name) .. ": " .. tostring(row.badges or 0) .. " badges",
                        "GameFontHighlightSmall", InkT("faint"), 16)
                end
            end
            local side = A.Side()
            for _, row in ipairs(type(data.choice) == "table" and data.choice or EMPTY) do
                if type(row) == "table" and row.name then
                    local name = tostring(row.name)
                    local mine = side and name:find(side == "ALDOR" and "Aldor" or "Scryer")
                    if mine then
                        Line(H.Markup("good", "Done") .. ": " .. name, "GameFontHighlightSmall", InkT("primary"), 16)
                    else
                        Line(name, "GameFontHighlightSmall", InkT("faint"), 16)
                    end
                end
            end
        end
        -- The pledge, said by hand while the bars and the flags are silent
        if record and record.key == "ALDOR_SCRYER_CHOICE" and not A.Side() then
            for _, pledge in ipairs({ { "I pledged the Aldor", "ALDOR" }, { "I pledged the Scryers", "SCRYER" } }) do
                local top = P.y
                local _, height = Line(pledge[1], "GameFontHighlightSmall", InkT("primary"), 16)
                Hit(top, height, function()
                    local char = Q.EnsureCharDB and Q.EnsureCharDB() or CommanderQuestLogChar
                    if type(char) ~= "table" then return end
                    if type(char.Attune) ~= "table" then char.Attune = {} end
                    char.Attune.side = pledge[2]
                    if A.Invalidate then A.Invalidate("store") end
                    Q.Refresh()
                end, nil, 0)
            end
        end
        if view.status ~= "NOTE" then
            Line("How the tab knows: " .. (view.how or ""), "GameFontDisableSmall", InkT("faint"), 16)
        end
        P.y = P.y + 4
    end

    -- The notices under the facts line (5.4 item 4)
    local function Notices(item, record, summary, steps)
        local kit = Kit()
        local phase = record.phase or EMPTY
        if item.status == "LATER" then
            local n = phase.introduced
            local _, name = A.PhaseName(n)
            local since = H.DateWord(H.PhaseSince(n), true)
            Line("Opens in Phase " .. tostring(n) .. " (" .. tostring(name or "") .. ")"
                .. (since and (" on " .. since) or ", no date announced")
                .. ". Read ahead; nothing here can be started yet.", "GameFontNormalSmall", ToneT("warn"))
        elseif item.status == "NOTNEEDED" then
            -- The notice is the guide's phase note (5.4 item 4), which on
            -- every gated raid already opens with "Not needed since Phase N
            -- (date):" (3.8.3); the clause is composed only for a guide
            -- whose note is missing, so it is never drawn twice
            local text = phase.note
            if type(text) ~= "string" or text == "" then
                local n = phase.requiredUntil
                if type(n) == "number" then
                    local since = H.DateWord(H.PhaseSince(n), true)
                    text = "Not needed since Phase " .. n .. (since and (" (" .. since .. ")") or "") .. "."
                else
                    text = item.notice or "Not needed this phase."
                end
            end
            Line(text, "GameFontNormalSmall", InkT("faint"))
        end
        if summary.unlockHeld then
            local levelDone = true
            for _, view in ipairs(steps) do
                if view.kind == "LEVEL" and view.status ~= "DONE" then levelDone = false end
            end
            -- The engine's sentence when it wrote one; else the same shape
            -- from the key's name and the guide's
            local text = summary.notice
            if type(text) ~= "string" or text == "" then
                local keyName = H.UnlockKeyName(record)
                local door = record.name or item.name or "this guide"
                if levelDone then
                    text = "You hold " .. keyName .. ": " .. door .. " is open to you."
                else
                    text = "You hold " .. keyName .. "; " .. door .. " opens at level "
                        .. tostring(item.minLevel or record.minLevel or 70) .. "."
                end
            end
            Line(text, "GameFontNormalSmall", levelDone and ToneT("good") or ToneT("warn"))
        end
        if record.accountWide and item.status ~= "DONE" then
            Line("Account-wide on Anniversary: if another character finished this, the raid is open to you too, but this client cannot see that. Shift-click Mark Done to tick the whole guide.",
                "GameFontNormalSmall", ToneT("log"))
        end
        if item.account and item.status == "DONE" then
            Line("Done by " .. tostring(item.account.char) .. " on " .. (H.DateWord(item.account.at) or "")
                .. " (account ledger).", "GameFontNormalSmall", ToneT("good"))
        end
        if not A.Side() and H.HasSideSplit(record) then
            Line("Pick a side in the Aldor or Scryers guide to settle the side-specific steps here.",
                "GameFontNormalSmall", InkT("faint"))
        end
        local minLevel = item.minLevel or record.minLevel
        if minLevel and A.Level() < minLevel then
            Line("Your level is " .. tostring(A.Level()) .. "; this guide begins at " .. tostring(minLevel) .. ".",
                "GameFontNormalSmall", InkT("faint"))
        end
    end

    -- Returns the focused step's top and height for the reveal
    function Draw.Course()
        local kit = Kit()
        local item = A.Guide(S.selected)
        local record = H.DataGuide(S.selected) or EMPTY
        if not item then
            Line("This guide is not listed for this character.", "GameFontHighlightSmall", InkT("faint"))
            return nil
        end
        local steps, summary = S.steps or EMPTY, S.summary or EMPTY
        local n = S.phase.n
        local recurring = item.status == "RECURRING" or record.recurring == true
        local badges = tonumber((tostring(item.word or "")):match("^(%d+)")) or 0
        local done, total = summary.done or item.done or 0, summary.total or item.total or 0
        local pct = summary.pct or item.pct or 0

        -- 1, 2: title and facts
        Line(record.title or item.title or item.name or "", "GameFontNormalLarge", kit.InkSet().title)
        local facts
        if recurring then
            facts = "Badges of Justice" .. SEP .. badges .. " in bags and bank" .. SEP .. "resets with each lockout"
        else
            local phase = record.phase or EMPTY
            local intro, untilPhase = phase.introduced or 1, phase.requiredUntil
            local phaseWords
            if item.status == "LATER" then
                phaseWords = "Opens in Phase " .. tostring(intro)
            elseif type(untilPhase) == "number" then
                phaseWords = "From Phase " .. tostring(intro) .. ", required until Phase " .. tostring(untilPhase)
            else
                phaseWords = "From Phase " .. tostring(intro)
            end
            facts = H.CategoryLabel(item.category) .. SEP .. phaseWords .. SEP .. done .. " of " .. total .. " steps"
                .. SEP .. H.Percent(pct)
        end
        Line(facts, "GameFontDisableSmall", InkT("secondary"))

        -- 3: the bar
        if not recurring then Bar(0, 6, pct, 6) end

        -- 4: notices
        Notices(item, record, summary, steps)

        -- 5: what it unlocks
        if type(record.unlocks) == "string" and record.unlocks ~= "" then
            Line(record.unlocks, "GameFontHighlightSmall", InkT("primary"))
        end

        -- 6: the heading
        Rule()
        if recurring then
            Heading("EARN THIS PHASE")
        else
            Heading("STEPS" .. SEP .. done .. " of " .. total .. " done")
        end

        -- 7, 8, 9: the steps, the open lesson, the folds
        local focus = S.focus or summary.current
        local showDone = H.ShowDone()
        local doneFolded = 0
        local focusTop, focusHeight
        for _, view in ipairs(steps) do
            -- SPEND lines and the recurring guide's spend note draw under
            -- SPEND THIS PHASE (item 10), not here
            if view.section ~= "SPEND" and not (recurring and view.key == "spend") then
                if view.status == "DONE" and not showDone then
                    doneFolded = doneFolded + 1
                else
                    local top, height, hasGo = Draw.StepLine(view, nil)
                    if view.key == summary.current then Band(top - 1, height + 2) end
                    Hit(top, height, StepClick(view, summary), StepEnter(view, record), hasGo and 54 or 0)
                    if view.key == focus then
                        focusTop, focusHeight = top, height
                        Body(view, record)
                    end
                end
            end
        end
        if doneFolded > 0 then
            local top = P.y
            local _, height = Line(doneFolded .. (doneFolded == 1 and " step done. Show" or " steps done. Show"), "GameFontHighlightSmall", InkT("faint"), 16)
            Hit(top, height, function()
                S.showDone = not H.ShowDone()
                Q.Refresh()
            end, nil, 0)
        end
        local hidden = tonumber(summary.hiddenOtherPhases) or 0
        if hidden > 0 and not S.showOtherPhases then
            local top = P.y
            local _, height = Line(hidden .. (hidden == 1 and " step from another phase. Show" or " steps from other phases. Show"), "GameFontHighlightSmall", InkT("faint"), 16)
            Hit(top, height, function()
                S.showOtherPhases = not S.showOtherPhases
                Q.Refresh()
            end, nil, 0)
        end

        -- 10: the recurring guide's SPEND section
        if recurring then
            Rule()
            Heading("SPEND THIS PHASE")
            local spend = H.DataStep(record, "spend")
            local prose = spend and type(spend.detailByPhase) == "table" and H.Flat(spend.detailByPhase[n])
            if type(prose) == "string" and prose ~= "" then
                Line(prose, "GameFontHighlightSmall", InkT("secondary"))
            end
            for _, view in ipairs(steps) do
                if view.section == "SPEND" and view.kind == "TALK" then
                    local place = view.places and view.places[1]
                    local data = H.DataStep(record, view.key)
                    local row = data and type(data.places) == "table" and H.Flat(data.places[1]) or nil
                    local text = (view.status == "DONE" and (H.Markup("good", "Done") .. "  ") or "")
                        .. H.Markup("faint", "Vendor") .. "  " .. (place and H.PlaceWhere(place, row) or (view.title or ""))
                    if (A.PlaceFor(view, nil)) then
                        GoLine(text, InkT("primary"), 16, function() return (A.PlaceFor(view, nil)) end,
                            function() return view.reason end)
                    else
                        Line(text, "GameFontHighlightSmall", InkT("primary"), 16)
                    end
                end
            end
        end

        -- 11: prerequisites
        local prerequisites = type(record.prerequisites) == "table" and record.prerequisites or EMPTY
        if #prerequisites > 0 then
            Rule()
            Heading("ALSO NEEDED")
            for _, pre in ipairs(prerequisites) do
                local other = pre.guide and A.Guide(pre.guide)
                if other then
                    local top = P.y
                    Mark(4, other.tone or "faint")
                    local _, height = Line(H.Markup(other.tone or "faint", other.word or "") .. "  " .. (other.name or "")
                        .. (pre.hard == false and "  (recommended)" or ""), "GameFontHighlightSmall", InkT("primary"), 16)
                    local key = pre.guide
                    Hit(top, height, function() H.OpenGuide(key, nil) end, nil, 0)
                end
            end
        end

        -- 12: the phase sentence at the foot, unless the Not needed notice
        -- (item 4) already drew it
        local footNote = record.phase and record.phase.note
        if type(footNote) == "string" and footNote ~= "" and item.status ~= "NOTNEEDED" then
            Rule()
            Line(footNote, "GameFontDisableSmall", InkT("faint"))
        end
        return focusTop, focusHeight
    end
end

-- ---------------------------------------------------------------------------
-- The briefing: the overview (no guide selected)
-- ---------------------------------------------------------------------------

do
    local function ByPct(a, b)
        if (a.pct or 0) ~= (b.pct or 0) then return (a.pct or 0) > (b.pct or 0) end
        return a.index < b.index
    end

    function Draw.Overview()
        local Line, Heading, Bar, Rule, Mark, GoLine, Hit = H.Line, H.Heading, H.Bar, H.Rule, H.Mark, H.GoLine, H.Hit
        local kit = Kit()
        local phase = S.phase
        local totals = S.totals or EMPTY
        local n = phase.n

        -- 1, 2: the title and the phase
        Line("Attunements", "GameFontNormalLarge", kit.InkSet().title)
        local since = H.DateWord(phase.since, true)
        Line((phase.short or "") .. ", " .. (phase.name or "") .. " (Blizzard: " .. (phase.blizzard or "") .. "), "
            .. (since and ("since " .. since) or "no date announced") .. ".", "GameFontHighlightSmall", InkT("primary"))
        if phase.why then Line(phase.why, "GameFontHighlightSmall", InkT("faint")) end

        -- 3: the totals
        Line((totals.done or 0) .. " of " .. (totals.needed or 0) .. " guides done" .. SEP .. H.Percent(totals.pct),
            "GameFontHighlight", InkT("primary"))
        Bar(0, 6, totals.pct or 0, 6)
        Line("Done " .. (totals.done or 0) .. SEP .. "To do " .. (totals.todo or 0) .. SEP .. "Not needed "
            .. (totals.notNeeded or 0) .. SEP .. "Opens later " .. (totals.later or 0), "GameFontHighlightSmall", InkT("secondary"))

        -- 4: below 58
        local level = A.Level()
        if level < 58 then
            Line("You are level " .. tostring(level) .. ". Outland attunements begin at 58; the guides are listed for planning.",
                "GameFontHighlightSmall", InkT("secondary"))
        end

        -- 5: where you stand, over every guide whatever the filter
        local all = A.Guides({ filter = "ALL", search = "", collapsed = EMPTY }) or EMPTY
        Rule()
        Heading("WHERE YOU STAND")
        for _, item in ipairs(all) do
            if item.kind == "header" then
                if item.category == "BADGES" then
                    local badges = 0
                    for _, guide in ipairs(all) do
                        if guide.kind == "guide" and guide.category == "BADGES" then
                            badges = tonumber((tostring(guide.word or "")):match("^(%d+)")) or 0
                        end
                    end
                    Line((item.label or "Badges of Justice") .. "  " .. badges .. " in bags and bank",
                        "GameFontHighlightSmall", InkT("primary"))
                else
                    local total = item.total or 0
                    Line((item.label or "") .. "  " .. (item.done or 0) .. " of " .. total .. " done",
                        "GameFontHighlightSmall", InkT("primary"))
                    Bar(4, 3, total > 0 and (item.done or 0) / total or 0, 4)
                end
            end
        end

        -- 6: continue
        Rule()
        Heading("CONTINUE")
        local key, step, reason = S.continueKey, S.continueStep, S.continueReason
        if key then
            local view = A.CurrentStep(key)
            if view and step and view.key ~= step then
                local steps = A.Steps(key, { otherPhases = false }) or EMPTY
                view = nil
                for _, candidate in ipairs(steps) do
                    if candidate.key == step then view = candidate end
                end
            end
            if view then
                local top, height, hasGo = Draw.StepLine(view, nil)
                Hit(top, height, function() H.OpenGuide(key, step) end, nil, hasGo and 54 or 0)
            end
            Line(CONTINUE_WORDS[reason] or "", "GameFontHighlightSmall", InkT("faint"), 16)
        elseif reason == "done" then
            Line("Everything needed this phase is done.", "GameFontHighlightSmall", InkT("primary"))
        else
            Line("Pick a guide to begin.", "GameFontHighlightSmall", InkT("faint"))
        end

        -- 7: up next
        local started = {}
        for index, item in ipairs(all) do
            if item.kind == "guide" and item.bucket == "NEEDED" and item.status ~= "RECURRING" and (item.done or 0) > 0 then
                started[#started + 1] = { item = item, pct = item.pct or 0, index = index }
            end
        end
        if #started > 0 then
            table.sort(started, ByPct)
            Rule()
            Heading("UP NEXT")
            for position = 1, math.min(6, #started) do
                local item = started[position].item
                local guideKey = item.key
                local top = P.y
                local text = (item.name or "") .. SEP .. string.format("%d/%d", item.done or 0, item.total or 0)
                    .. SEP .. (item.currentTitle or "")
                local _, height = GoLine(text, InkT("primary"), 4, function()
                    local view = A.CurrentStep(guideKey)
                    if not view then return nil, "Nothing to go to" end
                    return A.PlaceFor(view, nil)
                end, nil)
                Hit(top, height, function() H.OpenGuide(guideKey, nil) end, nil, 54)
            end
        end

        -- 8: this phase
        Rule()
        Heading("THIS PHASE")
        for _, sentence in ipairs(A.PhaseSentences(n) or EMPTY) do
            Line(sentence, "GameFontHighlightSmall", InkT("primary"), 4)
        end

        -- 9: where the phase comes from
        Rule()
        Line("The phase comes from the calendar, Questie's phase number, what this account has seen in game, and your setting; the highest wins. Change it on the phase button.",
            "GameFontHighlightSmall", InkT("faint"))
    end

    function Draw.Briefing()
        local kit = Kit()
        P.y, P.block, P.quad, P.band, P.go, P.hit = 6, 1, 1, 1, 1, 1
        P.width = kit.DetailWidth() - kit.PAD
        local focusTop, focusHeight
        if S.selected then
            focusTop, focusHeight = Draw.Course()
        else
            Draw.Overview()
        end
        for position = P.block, #W.blocks do W.blocks[position]:Hide() end
        for position = P.quad, #W.quads do W.quads[position]:Hide() end
        for position = P.band, #W.bands do W.bands[position]:Hide() end
        for position = P.hit, #W.hits do W.hits[position]:Hide() end
        if kit.HideLineGo then kit.HideLineGo(W.goLines, P.go) end
        kit.DetailChild():SetHeight(math.max(P.y + 10, 1))
        if S.revealStep then
            S.revealStep = false
            if focusTop and kit.ScrollIntoView then
                kit.ScrollIntoView(kit.DetailScroll(), kit.DetailChild(), focusTop, focusHeight)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Action bar overlay: Go to Step, Mark Done or Undo Mark, Open in Log; and
-- Overview at the right. No Show on Map in 1.8.0 (D52).
-- ---------------------------------------------------------------------------

do
    local function Button(parent, label, width, tooltip, handler)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        button:SetScript("OnClick", handler)
        Tip(button, label, tooltip, "ANCHOR_TOP")
        return button
    end

    function H.BuildActions(frame)
        local kit = Kit()
        local actions = CreateFrame("Frame", nil, frame.actions)
        actions:SetAllPoints(frame.actions)
        W.actions = actions

        local opts = H.GoOpts("Go to Step", 92, 22)
        opts.anchor = "ANCHOR_TOP"
        opts.target = function()
            local view = H.FocusedView()
            if not view then return nil, "Nothing to go to" end
            return A.PlaceFor(view, nil)
        end
        local goBtn = kit.GoButton(actions, opts)
        goBtn._lineOpts = opts
        goBtn:SetPoint("LEFT", actions, "LEFT", 0, 0)
        W.goBtn = goBtn

        local markBtn = Button(actions, "Mark Done", 84, MARK_TIP, function()
            local key = S.selected
            if not key then return end
            local view = H.FocusedView()
            if IsShiftKeyDown and IsShiftKeyDown() then
                A.MarkGuide(key, not A.IsMarked(key, nil))
            elseif H.OnGuideMark(view) then
                A.MarkGuide(key, false)
            else
                if not view then return end
                A.Mark(key, view.key, not A.IsMarked(key, view.key))
            end
            Q.Refresh()
        end)
        markBtn:SetPoint("LEFT", goBtn, "RIGHT", 4, 0)
        W.markBtn = markBtn

        local logBtn = Button(actions, "Open in Log", 88, nil, function()
            local view = H.FocusedView()
            if not (view and view.inLog and Q.RevealInLog) then return end
            Q.RevealInLog(view.logKey or ("id:" .. tostring(view.questId)))
        end)
        logBtn:SetPoint("LEFT", markBtn, "RIGHT", 4, 0)
        W.logBtn = logBtn

        local overviewBtn = Button(actions, "Overview", 72, nil, function()
            S.selected = nil
            Q.Refresh()
        end)
        overviewBtn:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
        W.overviewBtn = overviewBtn
    end

    -- The whole guide is marked and the focused step is one of the steps it
    -- made Done (no step mark of its own), or nothing is focused because it
    -- made every counted step Done: a plain click undoes the guide mark
    function H.OnGuideMark(view)
        if not (S.selected and A.IsMarked(S.selected, nil)) then return false end
        return view == nil or (view.status == "DONE" and not view.markedAt)
    end

    function Draw.Actions()
        local kit = Kit()
        local view = S.selected and H.FocusedView() or nil
        kit.RefreshGo(W.goBtn, view ~= nil)

        local marked = (S.selected and view) and A.IsMarked(S.selected, view.key) or nil
        local onGuideMark = H.OnGuideMark(view)
        W.markBtn:SetText((marked or onGuideMark) and "Undo Mark" or "Mark Done")
        local canMark = S.selected ~= nil and (onGuideMark or (view ~= nil and not NO_MARK_STATUS[view.status]
            and not (view.status == "DONE" and not view.markedAt)))
        W.markBtn:SetEnabled(canMark and true or false)

        W.logBtn:SetEnabled((view ~= nil and view.inLog) and true or false)
        W.overviewBtn:SetEnabled(true)
    end
end

-- ---------------------------------------------------------------------------
-- The pass, the switch, the search, the way in, the register
-- ---------------------------------------------------------------------------

do
    function H.EnsureBuilt(frame)
        if W.built then return end
        W.built = true
        H.BuildToolbar(frame)
        H.BuildCard(frame)
        H.BuildActions(frame)
    end

    -- The tab's pass. UI.lua's Q.Refresh has scanned the log (entries) and
    -- put the other tabs' widgets away; this draws everything else.
    function T.Refresh(entries)
        local kit = Kit()
        local frame = kit and kit.Frame()
        if not frame then return end
        H.EnsureBuilt(frame)
        H.SetOwnWidgetsShown(true)
        if A.SetLogEntries then A.SetLogEntries(entries) end
        -- Opening the tab asks the server for fresh lockouts once (the
        -- engine throttles it), so raid kills read current on first view
        if not S.active then
            S.active = true
            if A.RequestRaidInfo then pcall(A.RequestRaidInfo) end
        end

        -- The phase as named fields, never a positional capture
        local n, source, since, why, votes = A.Phase()
        S.phase = { n = n or 1, source = source, since = since, why = why, votes = type(votes) == "table" and votes or {} }
        S.phase.short, S.phase.name, S.phase.blizzard = A.PhaseName(S.phase.n)

        local opened = false
        if S.pendingGuide then
            S.selected = S.pendingGuide
            S.focus = S.pendingStep
            S.revealStep = true
            S.reveal = true
            S.pendingGuide, S.pendingStep = nil, nil
            opened = true
        end

        local db = DB()
        local collapsed = db.AttuneCollapsed
        if type(collapsed) ~= "table" then collapsed = {} end
        S.items, S.totals = A.Guides({ filter = db.AttuneFilter or "ALL", search = S.search, collapsed = collapsed })
        S.items = S.items or {}
        S.totals = S.totals or {}
        -- A guide asked for by name that the search, the filter or a fold
        -- has taken off the list: clear the search, open the filter, unfold
        -- its group (the catalogue's Reveal). An open whose row is already
        -- listed leaves all three alone.
        if opened and S.selected then
            local listed = false
            for _, item in ipairs(S.items) do
                if item.kind == "guide" and item.key == S.selected then listed = true end
            end
            local guide = (not listed) and A.Guide(S.selected) or nil
            if guide then
                S.search = ""
                if frame.searchBox then frame.searchBox:SetText("") end
                db.AttuneFilter = "ALL"
                if guide.category and type(db.AttuneCollapsed) == "table" then
                    db.AttuneCollapsed[guide.category] = nil
                end
                S.items, S.totals = A.Guides({ filter = "ALL", search = "", collapsed = collapsed })
                S.items = S.items or {}
                S.totals = S.totals or {}
            end
        end

        S.steps, S.summary = nil, nil
        if S.selected and not A.Guide(S.selected) then S.selected = nil end
        if S.selected then
            S.steps, S.summary = A.Steps(S.selected, { otherPhases = S.showOtherPhases })
            S.steps = S.steps or {}
            S.summary = S.summary or {}
            if S.focus == nil or not H.IsDrawn(S.focus) then
                S.focus = S.summary.current
            end
        end
        S.continueKey, S.continueStep, S.continueReason = A.Continue()

        local reveal = S.reveal
        S.reveal = false
        Draw.Rows()
        if reveal and S.selectedTop and kit.ScrollIntoView then
            kit.ScrollIntoView(kit.NavScroll(), kit.NavChild(), S.selectedTop, S.selectedHeight)
        end
        Draw.Briefing()
        Draw.Toolbar()
        Draw.Card()
        Draw.Actions()
    end

    -- Everything this tab drew, put away for another tab. Nil-safe: the
    -- window calls every inactive tab's HideAll on every pass, including
    -- the passes before this tab has ever been shown.
    function T.HideAll()
        S.active = nil
        if not W.built then return end
        H.SetOwnWidgetsShown(false)
        for _, row in ipairs(W.rows) do row:Hide() end
        if W.emptyFS then W.emptyFS:Hide() end
        for _, block in ipairs(W.blocks) do block:Hide() end
        for _, quad in ipairs(W.quads) do quad:Hide() end
        for _, band in ipairs(W.bands) do band:Hide() end
        for _, hit in ipairs(W.hits) do hit:Hide() end
        for _, button in ipairs(W.goLines) do button:Hide() end
    end

    function T.SetSearch(text)
        S.search = text or ""
    end

    function T.SearchText()
        return S.search
    end

    -- Escape walks back one level: the search, the lesson, the course
    function T.EscapeSearch()
        if S.search ~= "" then
            S.search = ""
        elseif S.selected and S.focus ~= (S.summary and S.summary.current) then
            S.focus = nil
        elseif S.selected then
            S.selected = nil
        end
    end

    -- Called before the window switches to this tab (Q.OpenToTab). key is
    -- a guide key, stepKey one of its steps; nil leaves the overview.
    function T.PrepareOpen(key, stepKey)
        if DB().ShowAttuneTab == false then
            print(OFF_MESSAGE)
            return false
        end
        if type(key) == "string" and A.Guide(key) then
            S.pendingGuide = key
            if stepKey ~= nil then
                S.pendingStep = tostring(stepKey)
                S.reveal = true
            else
                S.pendingStep = nil
            end
        else
            S.pendingGuide, S.pendingStep = nil, nil
            S.selected = nil
        end
        return true
    end

    function T.IsActive()
        local db = DB()
        return Q.ViewMode ~= nil and Q.ViewMode() == TAB_ID and db.ShowAttuneTab ~= false and db.EnableQuestLog ~= false
    end

    -- /cql attune <text>: the tab on the guide the text names
    function T.OpenTo(text)
        if not Q.OpenToTab then return end
        if text == nil or tostring(text):match("^%s*$") then
            Q.OpenToTab(TAB_ID)
            return
        end
        local key = A.Find(tostring(text))
        if not key then
            print("Commander Quest Log: no attunement guide matches '" .. tostring(text)
                .. "'. Try /cql attune and pick from the list.")
            Q.OpenToTab(TAB_ID)
            return
        end
        Q.OpenToTab(TAB_ID, key)
    end

    -- Harness accessors. Nothing in the game reads these.
    function T._Widgets() return W end
    function T._State() return S end

    T.tab = {
        id = TAB_ID, order = 40, label = "Attunements", width = 76,
        tooltip = "Guides for every TBC attunement, key and reputation hub, ticked off by the tab itself.",
        IsEnabled = function() return DB().ShowAttuneTab ~= false and DB().EnableQuestLog ~= false end,
        Refresh = function(entries) T.Refresh(entries) end,
        HideAll = function() T.HideAll() end,
        SearchText = function() return T.SearchText() end,
        SetSearch = function(text) T.SetSearch(text) end,
        EscapeSearch = function() T.EscapeSearch() end,
        SearchTip = "Matches a guide's name, or a step's title inside a guide.",
        NavTopInset = function() return (Q.ViewMode and Q.ViewMode() == TAB_ID) and (CARD_H + CARD_GAP) or 0 end,
        PrepareOpen = function(key, stepKey) return T.PrepareOpen(key, stepKey) end,
    }
    if Q.RegisterTab then Q.RegisterTab(T.tab) end

    -- The one listener: the engine says a domain moved; the window's own
    -- coalesced queue draws, and only while this tab is up (D10)
    if A.AddListener then
        A.AddListener(function()
            if not (Q.ViewMode and Q.ViewMode() == TAB_ID and T.IsActive()) then return end
            local kit = Kit()
            local frame = kit and kit.Frame()
            if not (frame and frame:IsShown()) then return end
            if Q.QueueRefresh then Q.QueueRefresh() end
        end)
    end
end

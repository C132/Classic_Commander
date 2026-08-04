-- Commander Talents — the war academy.
-- A full TBC talent calculator in the Quartermaster window language: pick a
-- class, load a preset (the same specializations Quartermaster stocks
-- consumables for), or lay out your own build across three trees drawn on
-- their proper talent art with live tier gates, prerequisites, and the
-- 61-point budget. The right-hand briefing carries the loadout's stat
-- priority and, when Commander_Quartermaster is present, its consumables.

local Data = CommanderTalentsData
local E = CommanderTalentsEngine
local Events = COMMANDER_TALENTS_EVENTS

local frame = CreateFrame("FRAME")
local db                      -- CommanderTalentsDB, bound at login
local customs                 -- CommanderTalentsCustom, bound at login
local loaded = false

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local FRAME_W, FRAME_H = 1010, 590
local SIDEBAR_W = 180
local SIDEBAR_ROW_H, MAX_SIDEBAR_ROWS = 22, 19
local BRIEF_W = 222

local TREE_W = 186
local TREE_GAP = 6
local TREE_HEADER_H = 24
local BTN = 30
local PITCH_X, PITCH_Y = 40, 50
local GRID_X0 = (TREE_W - (3 * PITCH_X + BTN)) / 2
local GRID_Y0 = TREE_HEADER_H + 10

local CLASS_ORDER = Data.ClassOrder

local ROLE_TAGS = {
    TANK = "|cff6699ffTank|r", HEALER = "|cff40cc40Heal|r",
    MELEE = "|cffff6060Melee|r", CASTER = "|cffcc66ffCaster|r", RANGED = "|cffff9933Ranged|r",
}

-- Rim colors by talent state
local RIM = {
    locked  = { 0.28, 0.28, 0.28 },
    open    = { 0.72, 0.60, 0.05 },
    partial = { 0.10, 0.85, 0.10 },
    maxed   = { 1.00, 0.82, 0.00 },
}

local BRANCH_TEX = "Interface\\TalentFrame\\UI-TalentBranches"
local ARROW_TEX = "Interface\\TalentFrame\\UI-TalentArrows"
local BRANCH_COORDS = {
    v = { on = { 0.12890625, 0.25390625, 0, 0.484375 }, off = { 0.12890625, 0.25390625, 0.515625, 1 } },
    h = { on = { 0.2578125, 0.3828125, 0, 0.5 }, off = { 0.2578125, 0.3828125, 0.5, 1 } },
}
local ARROW_COORDS = {
    down  = { on = { 0, 0.5, 0, 0.5 }, off = { 0, 0.5, 0.5, 1 } },
    right = { on = { 1, 0.5, 0, 0.5 }, off = { 1, 0.5, 0.5, 1 } },
    left  = { on = { 0.5, 1, 0, 0.5 }, off = { 0.5, 1, 0.5, 1 } },
}
-- Corner pieces for bent arrows (down from the prereq, then across into the
-- dependent). Named by the sides the elbow connects: up+right / up+left.
local CORNER_COORDS = {
    upright = { on = { 0.515625, 0.640625, 0, 0.5 }, off = { 0.515625, 0.640625, 0.5, 1 } },
    upleft  = { on = { 0.640625, 0.515625, 0, 0.5 }, off = { 0.640625, 0.515625, 0.5, 1 } },
}

-- ---------------------------------------------------------------------------
-- Class / build state
-- ---------------------------------------------------------------------------

local calc                    -- the window, created lazily
local states = {}             -- classToken -> engine state (session scratch)
-- Per-class UI status rides ON the engine state (state.edited: allocation
-- deviates from the selection; state.liveLabel: "My Talents"/"Imported"
-- transient), so switching classes never leaks one class's status to another

local function PlayerClassToken()
    local _, token = UnitClass("player")
    return token
end

local function CurrentClass()
    local token = db.SelClass
    if not (token and Data.Classes[token]) then
        token = PlayerClassToken()
    end
    if not (token and Data.Classes[token]) then
        for _, t in ipairs(CLASS_ORDER) do
            if Data.Classes[t] then return t end
        end
    end
    return token
end

local function ClassState(token)
    if not (token and Data.Classes[token]) then return nil end
    if not states[token] then
        states[token] = E.NewState(Data.Classes[token])
    end
    return states[token]
end

local function ClassColorHex(classToken)
    local color = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
    return (color and color.colorStr) or "ffffffff"
end

local function ClassLabel(token)
    return (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
end

local function Presets(token)
    local class = Data.Classes[token]
    return (class and class.builds) or {}
end

local function PresetByKey(token, key)
    for _, b in ipairs(Presets(token)) do
        if b.key == key then return b end
    end
end

local function CustomList(token)
    if not customs then return nil end
    customs[token] = customs[token] or {}
    return customs[token]
end

local function CustomByName(token, name)
    local list = CustomList(token)
    if not list then return nil end
    for i, b in ipairs(list) do
        if b.name == name then return b, i end
    end
end

local function SelectedBuild()
    local token = CurrentClass()
    if db.SelBuildKind == "PRESET" then
        return PresetByKey(token, db.SelBuildKey), "PRESET"
    elseif db.SelBuildKind == "CUSTOM" then
        return CustomByName(token, db.SelBuildKey), "CUSTOM"
    end
    return nil, false
end

-- The spec key that briefing content (stats/consumables) should follow:
-- presets carry their own; customs remember the spec they were based on.
local function BriefingSpecKey()
    local build, kind = SelectedBuild()
    if not build then return nil, nil end
    if kind == "PRESET" then return build.key, build end
    if kind == "CUSTOM" and build.basedOn then
        local base = PresetByKey(CurrentClass(), build.basedOn)
        return build.basedOn, base
    end
    return nil, nil
end

-- ---------------------------------------------------------------------------
-- Quartermaster bridge (soft-fail: the crate may not be installed)
-- ---------------------------------------------------------------------------

local function QMSpec(classToken, specKey)
    local qm = _G.CommanderQuartermasterData
    if not (qm and qm.Recommendations and specKey) then return nil end
    local rec = qm.Recommendations[classToken]
    if not rec then return nil end
    for _, spec in ipairs(rec.specs) do
        if spec.key == specKey then return spec end
    end
end

local function QMSlotName(slot)
    local qm = _G.CommanderQuartermasterData
    return (qm and qm.SlotNames and qm.SlotNames[slot]) or slot
end

local function OpenQuartermaster(classToken, specKey)
    if not (CommanderQuartermaster_Toggle and CommanderQuartermasterDB) then return end
    CommanderQuartermasterDB.BrowserView = "LOADOUT"
    CommanderQuartermasterDB.BrowserClass = classToken
    CommanderQuartermasterDB.BrowserSpec = specKey
    local qmFrame = _G.CommanderQuartermasterFrame
    if qmFrame and qmFrame:IsShown() then
        qmFrame:Hide()
    end
    CommanderQuartermaster_Toggle()
end

-- ---------------------------------------------------------------------------
-- Item helpers (briefing consumables)
-- ---------------------------------------------------------------------------

local function ItemName(id, fallback)
    local ok, name, _, quality = pcall(C_Item.GetItemInfo, id)
    if ok and name then
        local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
        if color and color.hex then
            return color.hex .. name .. "|r"
        end
        return name
    end
    return fallback or ("item:" .. tostring(id))
end

local function ItemIcon(id)
    local ok, icon = pcall(C_Item.GetItemIconByID, id)
    return (ok and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ---------------------------------------------------------------------------
-- Error flash (footer)
-- ---------------------------------------------------------------------------

local flashGen = 0
local function FlashError(text)
    if not calc then return end
    flashGen = flashGen + 1
    local gen = flashGen
    calc.flashFS:SetText(text or "")
    if text and text ~= "" then
        C_Timer.After(3, function()
            if calc and flashGen == gen then
                calc.flashFS:SetText("")
            end
        end)
    end
end

local function AddBlockText(state, t, block)
    if not block then return nil end
    if block.type == "MAX" then
        return "Already at max rank"
    elseif block.type == "CAP" then
        return "No talent points remaining"
    elseif block.type == "TIER" then
        return ("Requires %d points in %s Talents"):format(block.need, state.class.trees[t].name)
    elseif block.type == "REQ" then
        return ("Requires %d point%s in %s"):format(block.need, block.need == 1 and "" or "s", block.name)
    end
end

local function RemoveBlockText(block)
    if not block or block.type == "EMPTY" then return nil end
    if block.type == "SUPPORT" then
        return ("That point supports %s"):format(block.name)
    elseif block.type == "REQ" then
        return ("%s depends on it"):format(block.name)
    end
end

-- ---------------------------------------------------------------------------
-- Forward declarations
-- ---------------------------------------------------------------------------

local UpdateAll, RefreshSidebar, BindBriefing, BindPanes
local RefreshBriefSoon

-- ---------------------------------------------------------------------------
-- Selection / mutation entry points
-- ---------------------------------------------------------------------------

local function ApplyTargetsWithReport(state, build)
    local _, problems = E.ApplyBuild(state, build)
    if #problems > 0 then
        FlashError(("Build loaded with %d problem(s) — see chat"):format(#problems))
        print("|cff33ff99Commander Talents:|r build did not fully apply:")
        for i = 1, math.min(#problems, 6) do
            print("   " .. problems[i])
        end
    end
end

local function SelectPreset(key)
    local token = CurrentClass()
    local build = PresetByKey(token, key)
    local state = ClassState(token)
    if not (build and state) then return end
    db.SelBuildKind, db.SelBuildKey = "PRESET", key
    state.edited, state.liveLabel = false, false
    ApplyTargetsWithReport(state, build)
    UpdateAll()
end

local function SelectCustom(name)
    local token = CurrentClass()
    local build = CustomByName(token, name)
    local state = ClassState(token)
    if not (build and state) then return end
    db.SelBuildKind, db.SelBuildKey = "CUSTOM", name
    state.edited, state.liveLabel = false, false
    ApplyTargetsWithReport(state, build)
    UpdateAll()
end

local function SelectClass(token)
    db.SelClass = token
    local state = ClassState(token)
    if state and E.TotalSpent(state) == 0 then
        -- First visit this session: land on the spec's canonical preset
        local presets = Presets(token)
        if presets[1] then
            db.SelBuildKind, db.SelBuildKey = "PRESET", presets[1].key
            state.edited, state.liveLabel = false, false
            ApplyTargetsWithReport(state, presets[1])
        else
            db.SelBuildKind, db.SelBuildKey = false, false
        end
    else
        -- Returning to in-progress work: keep it exactly as left
        local build = SelectedBuild()
        if not build then
            db.SelBuildKind, db.SelBuildKey = false, false
        end
    end
    BindPanes()
    UpdateAll()
end

-- ---------------------------------------------------------------------------
-- Live talents (own class import)
-- ---------------------------------------------------------------------------

local function ReadLiveTalents()
    if type(GetTalentInfo) ~= "function" then return nil end
    local targets = { {}, {}, {} }
    local sawAny = false
    for t = 1, 3 do
        for i = 1, 60 do
            local ok, a, b, c, d, e, f = pcall(GetTalentInfo, t, i)
            if not ok or a == nil then break end
            if type(a) == "string" then
                -- Classic shape: name, icon, tier, column, rank, maxRank
                sawAny = true
                if type(e) == "number" and e > 0 then
                    targets[t][a] = e
                end
            elseif type(b) == "string" then
                -- Id-first shape: best effort, rank near the tail
                sawAny = true
                if type(f) == "number" and f > 0 then
                    targets[t][b] = f
                end
            end
        end
    end
    if not sawAny then return nil end
    return targets
end

local function ImportMyTalents()
    local token = PlayerClassToken()
    if CurrentClass() ~= token then return end
    local targets = ReadLiveTalents()
    if not targets then
        FlashError("Could not read your talents")
        return
    end
    local state = ClassState(token)
    if not state then return end
    local unknown = E.ApplyRaw(state, targets)
    db.SelBuildKind, db.SelBuildKey = false, false
    state.edited, state.liveLabel = false, "My Talents"
    if #unknown > 0 then
        FlashError(("%d talent(s) didn't match the database — see chat"):format(#unknown))
        print("|cff33ff99Commander Talents:|r unmatched live talents: " .. table.concat(unknown, ", "))
    end
    UpdateAll()
end

-- ---------------------------------------------------------------------------
-- Custom build storage
-- ---------------------------------------------------------------------------

local pendingSaveName = ""

local function DoSaveBuild(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return end
    local token = CurrentClass()
    local state = ClassState(token)
    local list = CustomList(token)
    if not (state and list) then return end

    local basedOn = nil
    if db.SelBuildKind == "PRESET" then
        basedOn = db.SelBuildKey
    elseif db.SelBuildKind == "CUSTOM" then
        local prior = CustomByName(token, db.SelBuildKey)
        basedOn = prior and prior.basedOn or nil
    end

    local entry = {
        name = name,
        basedOn = basedOn,
        points = E.SerializePoints(state),
        at = time(),
    }
    local existing, idx = CustomByName(token, name)
    if existing then
        list[idx] = entry
        print(("|cff33ff99Commander Talents:|r overwrote build \"%s\""):format(name))
    else
        list[#list + 1] = entry
        print(("|cff33ff99Commander Talents:|r saved build \"%s\""):format(name))
    end
    db.SelBuildKind, db.SelBuildKey = "CUSTOM", name
    state.edited, state.liveLabel = false, false
    UpdateAll()
end

local function DoDeleteBuild(name)
    local token = CurrentClass()
    local _, idx = CustomByName(token, name)
    if not idx then return end
    table.remove(CustomList(token), idx)
    if db.SelBuildKind == "CUSTOM" and db.SelBuildKey == name then
        db.SelBuildKind, db.SelBuildKey = false, false
    end
    print(("|cff33ff99Commander Talents:|r deleted build \"%s\""):format(name))
    UpdateAll()
end

-- ---------------------------------------------------------------------------
-- Static popups
-- ---------------------------------------------------------------------------

local function PopupEditBox(popup)
    if not popup then return nil end
    return popup.editBox or popup.EditBox
        or (popup.GetName and popup:GetName() and _G[popup:GetName() .. "EditBox"])
end

local pendingExport = ""

StaticPopupDialogs["COMMANDER_TALENTS_SAVE"] = {
    text = "Save this build as:",
    button1 = SAVE or "Save",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1, maxLetters = 40,
    OnShow = function(self)
        local box = PopupEditBox(self)
        if box then
            box:SetText(pendingSaveName or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    OnAccept = function(self)
        local box = PopupEditBox(self)
        DoSaveBuild(box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        DoSaveBuild(self:GetText() or "")
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

StaticPopupDialogs["COMMANDER_TALENTS_DELETE"] = {
    text = "Delete build \"%s\"?",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(self, data)
        if data then DoDeleteBuild(data) end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

StaticPopupDialogs["COMMANDER_TALENTS_EXPORT"] = {
    text = "Talent string — Ctrl-C to copy:",
    button1 = OKAY or "Okay",
    hasEditBox = 1, editBoxWidth = 290,
    OnShow = function(self)
        local box = PopupEditBox(self)
        if box then
            box:SetText(pendingExport or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

local function DoImportString(text)
    local token = CurrentClass()
    local state = ClassState(token)
    if not state then return end
    local ok, err = E.Import(state, text or "")
    if not ok then
        FlashError(err or "Import failed")
        return
    end
    db.SelBuildKind, db.SelBuildKey = false, false
    state.edited, state.liveLabel = false, "Imported"
    UpdateAll()
end

StaticPopupDialogs["COMMANDER_TALENTS_IMPORT"] = {
    text = "Paste a talent string or Wowhead TBC link:",
    button1 = ACCEPT or "Import",
    button2 = CANCEL or "Cancel",
    hasEditBox = 1, editBoxWidth = 290, maxLetters = 255,
    OnAccept = function(self)
        local box = PopupEditBox(self)
        DoImportString(box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        DoImportString(self:GetText() or "")
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

-- ---------------------------------------------------------------------------
-- Talent buttons
-- ---------------------------------------------------------------------------

local function TalentOnEnter(self)
    local pane = self.pane
    local state = ClassState(CurrentClass())
    if not (state and self.talentIdx) then return end
    local t = pane.treeIdx
    local tree = state.class.trees[t]
    local talent = tree.talents[self.talentIdx]
    local rank = E.Rank(state, t, self.talentIdx)

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(talent.name, 1, 1, 1)
    GameTooltip:AddLine(("Rank %d/%d"):format(rank, talent.max), 1, 1, 1)

    local block = E.AddBlock(state, t, self.talentIdx)
    if block and (block.type == "TIER" or block.type == "REQ") then
        GameTooltip:AddLine(AddBlockText(state, t, block), 1, 0.13, 0.13, true)
    end

    local desc = rank > 0 and talent.ranks[rank] or talent.ranks[1]
    if desc then
        GameTooltip:AddLine(desc, 1, 0.82, 0, true)
    end
    if rank > 0 and rank < talent.max and talent.ranks[rank + 1] then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Next rank:", 1, 1, 1)
        GameTooltip:AddLine(talent.ranks[rank + 1], 1, 0.82, 0, true)
    end

    local canAdd = block == nil
    local removeBlock = E.RemoveBlock(state, t, self.talentIdx)
    if canAdd or (rank > 0) then
        GameTooltip:AddLine(" ")
    end
    if canAdd then
        GameTooltip:AddLine("Left-click to add a point", 0.1, 1, 0.1)
    end
    if rank > 0 then
        if not removeBlock then
            GameTooltip:AddLine("Right-click to remove a point", 0.1, 1, 0.1)
        else
            local why = RemoveBlockText(removeBlock)
            if why then
                GameTooltip:AddLine("Locked — " .. why, 0.6, 0.6, 0.6)
            end
        end
    end
    GameTooltip:Show()
end

local function TalentOnClick(self, mouseButton)
    local pane = self.pane
    local state = ClassState(CurrentClass())
    if not (state and self.talentIdx) then return end
    local t = pane.treeIdx
    if mouseButton == "RightButton" then
        local block = E.RemoveBlock(state, t, self.talentIdx)
        if block then
            local why = RemoveBlockText(block)
            if why then FlashError(why) end
            return
        end
        E.Remove(state, t, self.talentIdx)
        state.edited = true
    else
        local block = E.AddBlock(state, t, self.talentIdx)
        if block then
            local why = AddBlockText(state, t, block)
            if why then FlashError(why) end
            return
        end
        E.Add(state, t, self.talentIdx)
        state.edited = true
    end
    UpdateAll()
    if GameTooltip:GetOwner() == self then
        TalentOnEnter(self)
    end
end

local function CreateTalentButton(pane)
    local btn = CreateFrame("Button", nil, pane)
    btn:SetSize(BTN, BTN)
    btn.pane = pane

    btn.rim = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    btn.rim:SetPoint("TOPLEFT", -2, 2)
    btn.rim:SetPoint("BOTTOMRIGHT", 2, -2)
    btn.rim:SetTexture("Interface\\Buttons\\WHITE8X8")

    btn.backing = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    btn.backing:SetPoint("TOPLEFT", -1, 1)
    btn.backing:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.backing:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.backing:SetVertexColor(0, 0, 0, 1)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.12)

    btn.rankBack = btn:CreateTexture(nil, "OVERLAY", nil, 0)
    btn.rankBack:SetSize(24, 12)
    btn.rankBack:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 5, -5)
    btn.rankBack:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.rankBack:SetVertexColor(0, 0, 0, 0.82)

    btn.rankFS = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.rankFS:SetPoint("CENTER", btn.rankBack, "CENTER", 0, 0)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", TalentOnClick)
    btn:SetScript("OnEnter", TalentOnEnter)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

-- ---------------------------------------------------------------------------
-- Tree panes
-- ---------------------------------------------------------------------------

local function ButtonXY(row, col)
    return GRID_X0 + (col - 1) * PITCH_X, -(GRID_Y0 + (row - 1) * PITCH_Y)
end

local function CreatePane(parent, index)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetSize(TREE_W, 1)
    pane:SetPoint("TOPLEFT", parent, "TOPLEFT", (index - 1) * (TREE_W + TREE_GAP), 0)
    pane:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0)

    -- Four-piece talent background art, proportioned like the original
    -- 320x384 layout (256+64 wide, 256+128 tall)
    local wa = TREE_W * 256 / 320
    pane.bgTL = pane:CreateTexture(nil, "BACKGROUND", nil, 0)
    pane.bgTL:SetPoint("TOPLEFT")
    pane.bgTR = pane:CreateTexture(nil, "BACKGROUND", nil, 0)
    pane.bgTR:SetPoint("TOPLEFT", wa, 0)
    pane.bgTR:SetPoint("TOPRIGHT")
    pane.bgBL = pane:CreateTexture(nil, "BACKGROUND", nil, 0)
    pane.bgBL:SetPoint("BOTTOMLEFT")
    pane.bgBR = pane:CreateTexture(nil, "BACKGROUND", nil, 0)
    pane.bgBR:SetPoint("BOTTOMLEFT", wa, 0)
    pane.bgBR:SetPoint("BOTTOMRIGHT")

    pane.dim = pane:CreateTexture(nil, "BACKGROUND", nil, 2)
    pane.dim:SetAllPoints()
    pane.dim:SetTexture("Interface\\Buttons\\WHITE8X8")
    pane.dim:SetVertexColor(0, 0, 0, 0.30)

    -- Header: tree name + spent count, on a dark strip
    pane.headerBack = pane:CreateTexture(nil, "BORDER")
    pane.headerBack:SetPoint("TOPLEFT")
    pane.headerBack:SetPoint("TOPRIGHT")
    pane.headerBack:SetHeight(TREE_HEADER_H)
    pane.headerBack:SetTexture("Interface\\Buttons\\WHITE8X8")
    pane.headerBack:SetVertexColor(0, 0, 0, 0.55)

    pane.headerFS = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pane.headerFS:SetPoint("CENTER", pane.headerBack, "CENTER", 0, 0)

    pane.buttons = {}          -- talentIdx -> button
    pane.branchRecs = {}       -- { line, arrow, dep, req }
    pane.branchPool = {}
    pane.arrowPool = {}
    return pane
end

local function AcquireTex(pane, pool, layer)
    local tex = table.remove(pool)
    if not tex then
        tex = pane:CreateTexture(nil, layer or "BORDER", nil, 1)
    end
    tex:Show()
    return tex
end

local function ReleaseBranches(pane)
    for _, rec in ipairs(pane.branchRecs) do
        rec.line:Hide()
        table.insert(pane.branchPool, rec.line)
        if rec.line2 then
            rec.line2:Hide()
            table.insert(pane.branchPool, rec.line2)
        end
        if rec.corner then
            rec.corner:Hide()
            table.insert(pane.branchPool, rec.corner)
        end
        rec.arrow:Hide()
        table.insert(pane.arrowPool, rec.arrow)
    end
    wipe(pane.branchRecs)
end

local function BindPane(pane, treeIdx)
    local state = ClassState(CurrentClass())
    pane.treeIdx = treeIdx
    ReleaseBranches(pane)
    for _, btn in pairs(pane.buttons) do
        btn:Hide()
        btn.talentIdx = nil
    end
    if not state then
        pane.headerFS:SetText("")
        return
    end
    local tree = state.class.trees[treeIdx]

    local bg = "Interface\\TalentFrame\\" .. (tree.bg or "WarriorArms")
    pane.bgTL:SetTexture(bg .. "-TopLeft")
    pane.bgTR:SetTexture(bg .. "-TopRight")
    pane.bgBL:SetTexture(bg .. "-BottomLeft")
    pane.bgBR:SetTexture(bg .. "-BottomRight")
    local h = pane:GetHeight()
    if not h or h < 1 then h = 492 end
    local ha = h * 256 / 384
    pane.bgTL:SetHeight(ha); pane.bgTR:SetHeight(ha)
    pane.bgBL:SetHeight(h - ha); pane.bgBR:SetHeight(h - ha)

    -- Buttons
    local free = {}
    for _, btn in pairs(pane.buttons) do free[#free + 1] = btn end
    wipe(pane.buttons)
    for i, talent in ipairs(tree.talents) do
        local btn = table.remove(free) or CreateTalentButton(pane)
        local x, y = ButtonXY(talent.row, talent.col)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", pane, "TOPLEFT", x, y)
        btn.talentIdx = i
        local icon = talent.icon and ("Interface\\Icons\\" .. talent.icon)
            or "Interface\\Icons\\INV_Misc_QuestionMark"
        btn.icon:SetTexture(icon)
        btn:Show()
        pane.buttons[i] = btn
    end

    -- Prerequisite branches
    local info = state.class._idx[treeIdx]
    for i, talent in ipairs(tree.talents) do
        local ri = info.req[i]
        if ri then
            local req = tree.talents[ri]
            local depBtn, reqBtn = pane.buttons[i], pane.buttons[ri]
            if depBtn and reqBtn then
                local line = AcquireTex(pane, pane.branchPool)
                local arrow = AcquireTex(pane, pane.arrowPool, "ARTWORK")
                line:SetTexture(BRANCH_TEX)
                arrow:SetTexture(ARROW_TEX)
                arrow:SetSize(16, 16)
                arrow:ClearAllPoints()
                line:ClearAllPoints()
                local kind, arrowDir, cornerDir
                local line2, corner
                if req.col == talent.col then
                    kind, arrowDir = "v", "down"
                    arrow:SetPoint("BOTTOM", depBtn, "TOP", 0, -3)
                    line:SetWidth(14)
                    line:SetPoint("TOP", reqBtn, "BOTTOM", 0, 2)
                    line:SetPoint("BOTTOM", arrow, "TOP", 0, -2)
                elseif req.row == talent.row then
                    kind = "h"
                    line:SetHeight(14)
                    if req.col < talent.col then
                        arrowDir = "right"
                        arrow:SetPoint("RIGHT", depBtn, "LEFT", 3, 0)
                        line:SetPoint("LEFT", reqBtn, "RIGHT", -2, 0)
                        line:SetPoint("RIGHT", arrow, "LEFT", 2, 0)
                    else
                        arrowDir = "left"
                        arrow:SetPoint("LEFT", depBtn, "RIGHT", -3, 0)
                        line:SetPoint("RIGHT", reqBtn, "LEFT", 2, 0)
                        line:SetPoint("LEFT", arrow, "RIGHT", -2, 0)
                    end
                else
                    -- Bent arrow (TBC ships one: Serrated Blades -> Hemorrhage):
                    -- drop from the prereq to the dependent's row, elbow, then
                    -- run across into its near side
                    kind = "l"
                    corner = AcquireTex(pane, pane.branchPool)
                    corner:SetTexture(BRANCH_TEX)
                    corner:SetSize(16, 16)
                    corner:ClearAllPoints()
                    local rx = GRID_X0 + (req.col - 1) * PITCH_X + BTN / 2
                    local dy = -(GRID_Y0 + (talent.row - 1) * PITCH_Y) - BTN / 2
                    corner:SetPoint("CENTER", pane, "TOPLEFT", rx, dy)
                    line:SetWidth(14)
                    line:SetPoint("TOP", reqBtn, "BOTTOM", 0, 2)
                    line:SetPoint("BOTTOM", corner, "TOP", 0, -2)
                    line2 = AcquireTex(pane, pane.branchPool)
                    line2:SetTexture(BRANCH_TEX)
                    line2:ClearAllPoints()
                    line2:SetHeight(14)
                    if req.col < talent.col then
                        arrowDir, cornerDir = "right", "upright"
                        arrow:SetPoint("RIGHT", depBtn, "LEFT", 3, 0)
                        line2:SetPoint("LEFT", corner, "RIGHT", -2, 0)
                        line2:SetPoint("RIGHT", arrow, "LEFT", 2, 0)
                    else
                        arrowDir, cornerDir = "left", "upleft"
                        arrow:SetPoint("LEFT", depBtn, "RIGHT", -3, 0)
                        line2:SetPoint("RIGHT", corner, "LEFT", 2, 0)
                        line2:SetPoint("LEFT", arrow, "RIGHT", -2, 0)
                    end
                end
                pane.branchRecs[#pane.branchRecs + 1] = {
                    line = line, line2 = line2, corner = corner,
                    arrow = arrow, dep = i, req = ri,
                    kind = kind, arrowDir = arrowDir, cornerDir = cornerDir,
                }
            end
        end
    end
end

local function UpdatePaneStates(pane)
    local state = ClassState(CurrentClass())
    if not (state and pane.treeIdx) then return end
    local t = pane.treeIdx
    local tree = state.class.trees[t]
    pane.headerFS:SetText(("%s |cffffd200(%d)|r"):format(tree.name, E.Spent(state, t)))

    for i, btn in pairs(pane.buttons) do
        local talent = tree.talents[i]
        local rank = E.Rank(state, t, i)
        local block = E.AddBlock(state, t, i)
        local rim, desat, iconAlpha
        if rank >= talent.max then
            rim, desat, iconAlpha = RIM.maxed, false, 1
        elseif rank > 0 then
            rim, desat, iconAlpha = RIM.partial, false, 1
        elseif block == nil or block.type == "CAP" then
            rim, desat, iconAlpha = RIM.open, false, 0.92
        else
            rim, desat, iconAlpha = RIM.locked, true, 0.55
        end
        btn.rim:SetVertexColor(rim[1], rim[2], rim[3], 1)
        btn.icon:SetDesaturated(desat)
        btn.icon:SetAlpha(iconAlpha)
        local rankColor
        if rank >= talent.max then rankColor = "|cffffd200"
        elseif rank > 0 then rankColor = "|cff1eff00"
        else rankColor = "|cff808080" end
        btn.rankFS:SetText(("%s%d/%d|r"):format(rankColor, rank, talent.max))
    end

    for _, rec in ipairs(pane.branchRecs) do
        local req = tree.talents[rec.req]
        local active = E.Rank(state, t, rec.req) >= req.max
        local onoff = active and "on" or "off"
        local b = BRANCH_COORDS[rec.kind == "h" and "h" or "v"][onoff]
        rec.line:SetTexCoord(b[1], b[2], b[3], b[4])
        if rec.line2 then
            local b2 = BRANCH_COORDS.h[onoff]
            rec.line2:SetTexCoord(b2[1], b2[2], b2[3], b2[4])
        end
        if rec.corner then
            local c = CORNER_COORDS[rec.cornerDir][onoff]
            rec.corner:SetTexCoord(c[1], c[2], c[3], c[4])
        end
        local a = ARROW_COORDS[rec.arrowDir][onoff]
        rec.arrow:SetTexCoord(a[1], a[2], a[3], a[4])
    end
end

-- ---------------------------------------------------------------------------
-- Sidebar
-- ---------------------------------------------------------------------------

local sidebarButtons = {}

local function CreateSidebarButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(SIDEBAR_ROW_H)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * SIDEBAR_ROW_H))
    btn:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    btn.selectedTex = btn:CreateTexture(nil, "BACKGROUND")
    btn.selectedTex:SetAllPoints()
    btn.selectedTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.selectedTex:SetVertexColor(1, 0.82, 0, 0.13)
    btn.selectedTex:Hide()

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.06)

    btn.labelFS = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.labelFS:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.labelFS:SetJustifyH("LEFT")

    btn.badgeFS = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    btn.badgeFS:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.badgeFS:SetJustifyH("RIGHT")

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, mouseButton)
        if self.onClick then self.onClick(mouseButton) end
    end)
    btn:SetScript("OnEnter", function(self)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipTitle or "", 1, 1, 1)
            GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return btn
end

local function BindSidebarButton(btn, opts)
    btn:Show()
    btn.labelFS:SetText(opts.text)
    btn.badgeFS:SetText(opts.badge or "")
    btn.selectedTex:SetShown(opts.selected or false)
    btn.onClick = opts.onClick
    btn.tooltip = opts.tooltip
    btn.tooltipTitle = opts.tooltipTitle
end

local function BuildSignature(build)
    local sums = { 0, 0, 0 }
    for t = 1, 3 do
        for _, rank in pairs((build.points or {})[t] or {}) do
            sums[t] = sums[t] + rank
        end
    end
    return ("%d/%d/%d"):format(sums[1], sums[2], sums[3])
end

RefreshSidebar = function()
    if not calc then return end
    local token = CurrentClass()
    local used = 0
    local function row(opts)
        used = used + 1
        if used > MAX_SIDEBAR_ROWS then return end
        BindSidebarButton(sidebarButtons[used], opts)
    end

    row({ text = "|cffffd200PRESET BUILDS|r" })
    for _, build in ipairs(Presets(token)) do
        row({
            text = build.name,
            badge = ROLE_TAGS[build.role] or "",
            selected = db.SelBuildKind == "PRESET" and db.SelBuildKey == build.key,
            tooltipTitle = ("%s — %s"):format(build.name, BuildSignature(build)),
            tooltip = build.notes,
            onClick = function() SelectPreset(build.key) end,
        })
    end

    row({ text = "|cffffd200MY BUILDS|r" })
    local list = CustomList(token)
    if list and #list > 0 then
        for _, build in ipairs(list) do
            local name = build.name
            row({
                text = "|cff69ccf0" .. name .. "|r",
                badge = "|cff999999" .. BuildSignature(build) .. "|r",
                selected = db.SelBuildKind == "CUSTOM" and db.SelBuildKey == name,
                tooltipTitle = name,
                tooltip = ("%s%s\nRight-click to delete."):format(
                    BuildSignature(build),
                    build.basedOn and ("  ·  based on " .. tostring(build.basedOn)) or ""),
                onClick = function(mouseButton)
                    if mouseButton == "RightButton" then
                        local dialog = StaticPopup_Show("COMMANDER_TALENTS_DELETE", name)
                        if dialog then dialog.data = name end
                    else
                        SelectCustom(name)
                    end
                end,
            })
        end
    else
        row({ text = "|cff666666(none saved yet)|r" })
    end
    row({
        text = "|cff1eff00+ Save Current Build…|r",
        tooltipTitle = "Save Current Build",
        tooltip = "Store the point layout on this class's build list (account-wide).",
        onClick = function()
            local build = SelectedBuild()
            pendingSaveName = (db.SelBuildKind == "CUSTOM" and db.SelBuildKey)
                or (build and build.name and (build.name .. " variant"))
                or "New Build"
            StaticPopup_Show("COMMANDER_TALENTS_SAVE")
        end,
    })

    for i = used + 1, #sidebarButtons do
        sidebarButtons[i]:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Briefing panel
-- ---------------------------------------------------------------------------

local briefItemIDs = {}

local function BriefSection(fs, text)
    fs:SetText(text or "")
    fs:SetShown(text ~= nil and text ~= "")
end

BindBriefing = function()
    if not calc then return end
    local brief = calc.brief
    if not db.ShowBriefing then
        brief:Hide()
        return
    end
    brief:Show()
    wipe(briefItemIDs)

    local token = CurrentClass()
    local build, kind = SelectedBuild()
    local specKey, statsSource = BriefingSpecKey()

    -- Identity
    local state = ClassState(token)
    local title, subtitle
    if build then
        title = build.name
        local role = build.role or (statsSource and statsSource.role)
        subtitle = (ROLE_TAGS[role] or "") .. "  |cff999999" .. BuildSignature(build) .. "|r"
    elseif state and state.liveLabel then
        title = state.liveLabel
        subtitle = ""
    else
        title = "Freeform"
        subtitle = "|cff999999no loadout selected|r"
    end
    if state then
        subtitle = ("|c%s%s|r  %s"):format(ClassColorHex(token), ClassLabel(token), subtitle or "")
    end
    brief.titleFS:SetText(title or "")
    brief.subFS:SetText(subtitle or "")

    -- Stats
    local stats = (statsSource and statsSource.stats) or (build and build.stats)
    if stats and #stats > 0 then
        local lines = {}
        for i, s in ipairs(stats) do
            lines[#lines + 1] = ("|cffffd200%d.|r %s"):format(i, s)
        end
        brief.statsHeadFS:Show()
        BriefSection(brief.statsFS, table.concat(lines, "\n"))
    else
        brief.statsHeadFS:Hide()
        BriefSection(brief.statsFS, nil)
    end

    -- Notes
    local notes = (statsSource and statsSource.notes) or (build and build.notes)
    if notes and notes ~= "" then
        brief.notesHeadFS:Show()
        BriefSection(brief.notesFS, "|cffbbbbbb" .. notes .. "|r")
    else
        brief.notesHeadFS:Hide()
        BriefSection(brief.notesFS, nil)
    end

    -- Consumables (Quartermaster)
    local spec = QMSpec(token, specKey)
    local shown = 0
    if spec then
        for _, pick in ipairs(spec.picks) do
            local entry = pick.entries and pick.entries[1]
            if entry and shown < #brief.consRows then
                shown = shown + 1
                local rowBtn = brief.consRows[shown]
                rowBtn:Show()
                rowBtn.itemID = entry.id
                briefItemIDs[entry.id] = true
                rowBtn.icon:SetTexture(ItemIcon(entry.id))
                rowBtn.nameFS:SetText(ItemName(entry.id, entry.name))
                rowBtn.slotFS:SetText("|cff777777" .. QMSlotName(pick.slot) .. "|r")
            end
        end
    end
    for i = shown + 1, #brief.consRows do
        brief.consRows[i]:Hide()
        brief.consRows[i].itemID = nil
    end
    if spec then
        brief.consHeadFS:Show()
        brief.consHintFS:Hide()
        brief.qmBtn:SetShown(CommanderQuartermaster_Toggle ~= nil)
        brief.qmBtn.specKey = specKey
    else
        brief.consHeadFS:SetShown(false)
        brief.qmBtn:Hide()
        if not _G.CommanderQuartermasterData then
            brief.consHintFS:SetText("|cff666666Commander Quartermaster adds consumable recommendations here.|r")
        elseif build then
            brief.consHintFS:SetText("|cff666666No Quartermaster loadout for this build.|r")
        else
            brief.consHintFS:SetText("")
        end
        brief.consHintFS:Show()
    end

    -- Flow layout: everything hangs off the previous visible block
    local y = -8
    local function place(region, gap, height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", brief, "TOPLEFT", 10, y - (gap or 0))
        region:SetPoint("RIGHT", brief, "RIGHT", -10, 0)
        local h = height or region:GetStringHeight() or 0
        y = y - (gap or 0) - h
    end
    place(brief.titleFS, 0)
    place(brief.subFS, 4)
    if brief.statsHeadFS:IsShown() then
        place(brief.statsHeadFS, 14)
        place(brief.statsFS, 6)
    end
    if brief.notesHeadFS:IsShown() then
        place(brief.notesHeadFS, 14)
        place(brief.notesFS, 6)
    end
    if brief.consHeadFS:IsShown() then
        place(brief.consHeadFS, 14)
        for i = 1, shown do
            local rowBtn = brief.consRows[i]
            rowBtn:ClearAllPoints()
            rowBtn:SetPoint("TOPLEFT", brief, "TOPLEFT", 10, y - 5)
            rowBtn:SetPoint("RIGHT", brief, "RIGHT", -10, 0)
            y = y - 5 - rowBtn:GetHeight()
        end
        if brief.qmBtn:IsShown() then
            brief.qmBtn:ClearAllPoints()
            brief.qmBtn:SetPoint("TOPLEFT", brief, "TOPLEFT", 10, y - 10)
        end
    elseif brief.consHintFS:IsShown() then
        place(brief.consHintFS, 14)
    end
end

RefreshBriefSoon = function()
    if not (calc and calc:IsShown()) then return end
    if calc._briefQueued then return end
    calc._briefQueued = true
    C_Timer.After(0.1, function()
        calc._briefQueued = false
        if calc and calc:IsShown() then
            BindBriefing()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Chrome (summary, footer)
-- ---------------------------------------------------------------------------

local function UpdateChrome()
    local token = CurrentClass()
    local state = ClassState(token)
    if not state then
        calc.summaryFS:SetText("|cffff4040No talent data installed|r")
        calc.remainFS:SetText("")
        calc.levelFS:SetText("")
        return
    end
    local total = E.TotalSpent(state)
    local remaining = E.MAX_POINTS - total
    local build = SelectedBuild()
    local selName
    if build then
        selName = build.name
    elseif state.liveLabel then
        selName = state.liveLabel
    else
        selName = "Freeform"
    end
    calc.summaryFS:SetText(("|c%s%s|r  ·  %s%s  ·  |cffffd200%s|r"):format(
        ClassColorHex(token), ClassLabel(token),
        selName, state.edited and " |cff999999(edited)|r" or "",
        E.Signature(state)))

    if remaining > 0 then
        calc.remainFS:SetText(("Points remaining: |cff1eff00%d|r"):format(remaining))
    else
        calc.remainFS:SetText("Points remaining: |cff8080800|r")
    end
    local level = E.RequiredLevel(state)
    if level > 0 then
        calc.levelFS:SetText(("Required level: |cffffffff%d|r"):format(math.max(level, 10)))
    else
        calc.levelFS:SetText("")
    end

    if UIDropDownMenu_SetText and calc.classDrop then
        UIDropDownMenu_SetText(calc.classDrop,
            ("|c%s%s|r"):format(ClassColorHex(token), ClassLabel(token)))
    end
    calc.myTalentsBtn:SetEnabled(token == PlayerClassToken())

    local hasData = Data.Classes[token] ~= nil
    calc.noDataFS:SetShown(not hasData)
    for _, pane in ipairs(calc.panes) do
        pane:SetShown(hasData)
    end
end

UpdateAll = function()
    if not calc then return end
    for _, pane in ipairs(calc.panes) do
        UpdatePaneStates(pane)
    end
    UpdateChrome()
    RefreshSidebar()
    BindBriefing()
end

BindPanes = function()
    if not calc then return end
    local token = CurrentClass()
    calc._boundClass = token
    for i, pane in ipairs(calc.panes) do
        BindPane(pane, i)
    end
end

-- ---------------------------------------------------------------------------
-- Window construction
-- ---------------------------------------------------------------------------

local function ApplyFraming()
    if not calc then return end
    local style = db.BrowserStyle or "WINDOW"
    local windowArt = style == "WINDOW"
    if calc.NineSlice then calc.NineSlice:SetShown(windowArt) end
    if calc.Bg then calc.Bg:SetShown(windowArt) end
    if calc.TitleBg then calc.TitleBg:SetShown(windowArt) end
    if calc.TitleText then calc.TitleText:SetShown(windowArt) end
    if calc.CloseButton then calc.CloseButton:SetShown(windowArt) end
    if calc.Inset then calc.Inset:SetShown(windowArt) end
    Commander.UI.ApplyStyleBackdrop(calc, windowArt and "NONE" or style)
end

local function ApplyPosition()
    if not calc then return end
    local scale = db.BrowserScale or 1
    calc:SetScale(scale)
    if calc._dragging then return end
    calc:ClearAllPoints()
    local pos = db.BrowserPos
    if pos and pos.point then
        calc:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        calc:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function ApplyBriefingLayout()
    if not calc then return end
    local shift = db.ShowBriefing and 0 or math.floor((BRIEF_W + 8) / 2)
    calc.treesArea:ClearAllPoints()
    calc.treesArea:SetPoint("TOPLEFT", calc, "TOPLEFT", SIDEBAR_W + 18 + shift, -64)
    calc.treesArea:SetPoint("BOTTOMLEFT", calc, "BOTTOMLEFT", SIDEBAR_W + 18 + shift, 34)
end

local function EnsureCalculator()
    if calc then return calc end

    calc = CreateFrame("Frame", "CommanderTalentsFrame", UIParent, "BasicFrameTemplateWithInset")
    calc:SetSize(FRAME_W, FRAME_H)
    calc:SetFrameStrata("MEDIUM")
    calc:SetToplevel(true)
    calc:SetMovable(true)
    calc:SetClampedToScreen(true)
    calc:Hide()
    if calc.TitleText then
        calc.TitleText:SetText("Talents")
    end
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderTalentsFrame")
    end

    local drag = CreateFrame("Frame", nil, calc)
    drag:SetPoint("TOPLEFT", calc, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", calc, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        calc._dragging = true
        calc:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        calc:StopMovingOrSizing()
        calc._dragging = false
        local point, _, _, x, y = calc:GetPoint(1)
        if point then
            local scale = calc:GetScale() or 1
            db.BrowserPos = { point = point, x = x * scale, y = y * scale }
        end
    end)

    -- Toolbar
    local toolbar = CreateFrame("Frame", nil, calc)
    toolbar:SetPoint("TOPLEFT", calc, "TOPLEFT", 10, -28)
    toolbar:SetPoint("TOPRIGHT", calc, "TOPRIGHT", -10, -28)
    toolbar:SetHeight(30)

    if UIDropDownMenu_Initialize then
        calc.classDrop = CreateFrame("Frame", "CommanderTalentsClassDrop", toolbar, "UIDropDownMenuTemplate")
        calc.classDrop:SetPoint("LEFT", toolbar, "LEFT", -16, -2)
        UIDropDownMenu_SetWidth(calc.classDrop, 116)
        UIDropDownMenu_Initialize(calc.classDrop, function()
            local current = CurrentClass()
            for _, token in ipairs(CLASS_ORDER) do
                if Data.Classes[token] then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = ("|c%s%s|r"):format(ClassColorHex(token), ClassLabel(token))
                    info.value = token
                    info.checked = (token == current)
                    info.func = function(button)
                        SelectClass(button.value)
                    end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end)
    end

    calc.clearBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    calc.clearBtn:SetSize(52, 22)
    calc.clearBtn:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    calc.clearBtn:SetText("Clear")
    calc.clearBtn:SetScript("OnClick", function()
        local state = ClassState(CurrentClass())
        if not state then return end
        E.Clear(state)
        state.edited = true
        FlashError("")
        UpdateAll()
    end)

    calc.exportBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    calc.exportBtn:SetSize(58, 22)
    calc.exportBtn:SetPoint("RIGHT", calc.clearBtn, "LEFT", -4, 0)
    calc.exportBtn:SetText("Export")
    calc.exportBtn:SetScript("OnClick", function()
        local state = ClassState(CurrentClass())
        if not state then return end
        pendingExport = E.Export(state)
        if pendingExport == "" then
            FlashError("Nothing to export — the build is empty")
            return
        end
        StaticPopup_Show("COMMANDER_TALENTS_EXPORT")
    end)

    calc.importBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    calc.importBtn:SetSize(58, 22)
    calc.importBtn:SetPoint("RIGHT", calc.exportBtn, "LEFT", -4, 0)
    calc.importBtn:SetText("Import")
    calc.importBtn:SetScript("OnClick", function()
        StaticPopup_Show("COMMANDER_TALENTS_IMPORT")
    end)

    calc.myTalentsBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    calc.myTalentsBtn:SetSize(86, 22)
    calc.myTalentsBtn:SetPoint("RIGHT", calc.importBtn, "LEFT", -4, 0)
    calc.myTalentsBtn:SetText("My Talents")
    calc.myTalentsBtn:SetScript("OnClick", ImportMyTalents)
    calc.myTalentsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Load My Talents", 1, 1, 1)
        GameTooltip:AddLine("Copy your character's live talents into the calculator (own class only).", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    calc.myTalentsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    calc.summaryFS = calc:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    calc.summaryFS:SetPoint("LEFT", calc.classDrop or toolbar, "RIGHT", calc.classDrop and -6 or 0, calc.classDrop and 2 or 0)
    calc.summaryFS:SetPoint("RIGHT", calc.myTalentsBtn, "LEFT", -8, 0)
    calc.summaryFS:SetJustifyH("LEFT")
    calc.summaryFS:SetWordWrap(false)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, calc)
    sidebar:SetPoint("TOPLEFT", calc, "TOPLEFT", 10, -64)
    sidebar:SetSize(SIDEBAR_W, MAX_SIDEBAR_ROWS * SIDEBAR_ROW_H)
    local sidebarLine = calc:CreateTexture(nil, "ARTWORK")
    sidebarLine:SetColorTexture(1, 1, 1, 0.08)
    sidebarLine:SetWidth(1)
    sidebarLine:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 3, 0)
    sidebarLine:SetPoint("BOTTOMLEFT", calc, "BOTTOMLEFT", SIDEBAR_W + 13, 34)
    for i = 1, MAX_SIDEBAR_ROWS do
        sidebarButtons[i] = CreateSidebarButton(sidebar, i)
    end

    -- Trees
    calc.treesArea = CreateFrame("Frame", nil, calc)
    calc.treesArea:SetSize(3 * TREE_W + 2 * TREE_GAP, 1)
    calc.panes = {}
    for i = 1, 3 do
        calc.panes[i] = CreatePane(calc.treesArea, i)
    end

    calc.noDataFS = calc:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    calc.noDataFS:SetPoint("CENTER", calc.treesArea, "CENTER", 0, 0)
    calc.noDataFS:SetText("|cffff4040Talent data for this class is not installed.|r")
    calc.noDataFS:Hide()

    -- Briefing panel
    local brief = CreateFrame("Frame", nil, calc)
    calc.brief = brief
    brief:SetPoint("TOPRIGHT", calc, "TOPRIGHT", -12, -64)
    brief:SetPoint("BOTTOMRIGHT", calc, "BOTTOMRIGHT", -12, 34)
    brief:SetWidth(BRIEF_W)
    local briefBack = brief:CreateTexture(nil, "BACKGROUND")
    briefBack:SetAllPoints()
    briefBack:SetTexture("Interface\\Buttons\\WHITE8X8")
    briefBack:SetVertexColor(0, 0, 0, 0.35)

    brief.titleFS = brief:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    brief.titleFS:SetJustifyH("LEFT")
    brief.subFS = brief:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    brief.subFS:SetJustifyH("LEFT")
    brief.statsHeadFS = brief:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    brief.statsHeadFS:SetText("|cffffd200STAT PRIORITY|r")
    brief.statsHeadFS:SetJustifyH("LEFT")
    brief.statsFS = brief:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    brief.statsFS:SetJustifyH("LEFT")
    brief.statsFS:SetSpacing(3)
    brief.notesHeadFS = brief:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    brief.notesHeadFS:SetText("|cffffd200NOTES|r")
    brief.notesHeadFS:SetJustifyH("LEFT")
    brief.notesFS = brief:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    brief.notesFS:SetJustifyH("LEFT")
    brief.notesFS:SetSpacing(2)
    -- Long build notes must not push the consumables off the panel
    pcall(brief.notesFS.SetMaxLines, brief.notesFS, 8)
    brief.consHeadFS = brief:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    brief.consHeadFS:SetText("|cffffd200CONSUMABLES|r")
    brief.consHeadFS:SetJustifyH("LEFT")
    brief.consHintFS = brief:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    brief.consHintFS:SetJustifyH("LEFT")
    brief.consHintFS:SetWordWrap(true)

    brief.consRows = {}
    for i = 1, 8 do
        local rowBtn = CreateFrame("Button", nil, brief)
        rowBtn:SetHeight(20)
        rowBtn.icon = rowBtn:CreateTexture(nil, "ARTWORK")
        rowBtn.icon:SetSize(18, 18)
        rowBtn.icon:SetPoint("LEFT", rowBtn, "LEFT", 0, 0)
        rowBtn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        rowBtn.nameFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rowBtn.nameFS:SetPoint("LEFT", rowBtn, "LEFT", 24, 0)
        rowBtn.nameFS:SetJustifyH("LEFT")
        rowBtn.nameFS:SetWordWrap(false)
        rowBtn.slotFS = rowBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rowBtn.slotFS:SetPoint("RIGHT", rowBtn, "RIGHT", 0, 0)
        rowBtn.slotFS:SetJustifyH("RIGHT")
        rowBtn.nameFS:SetPoint("RIGHT", rowBtn.slotFS, "LEFT", -4, 0)
        rowBtn:SetScript("OnEnter", function(self)
            if not self.itemID then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ("item:%d"):format(self.itemID))
            if not ok then GameTooltip:SetText("item:" .. self.itemID) end
            GameTooltip:Show()
        end)
        rowBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rowBtn:SetScript("OnMouseUp", function(self)
            if self.itemID and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                local okInfo, _, link = pcall(C_Item.GetItemInfo, self.itemID)
                if okInfo and link then ChatEdit_InsertLink(link) end
            end
        end)
        rowBtn:Hide()
        brief.consRows[i] = rowBtn
    end

    brief.qmBtn = CreateFrame("Button", nil, brief, "UIPanelButtonTemplate")
    brief.qmBtn:SetSize(170, 21)
    brief.qmBtn:SetText("Open in Quartermaster")
    brief.qmBtn:SetScript("OnClick", function(self)
        OpenQuartermaster(CurrentClass(), self.specKey)
    end)
    brief.qmBtn:Hide()

    -- Footer
    local footer = CreateFrame("Frame", nil, calc)
    footer:SetPoint("BOTTOMLEFT", calc, "BOTTOMLEFT", 10, 10)
    footer:SetPoint("BOTTOMRIGHT", calc, "BOTTOMRIGHT", -10, 10)
    footer:SetHeight(22)
    calc.remainFS = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    calc.remainFS:SetPoint("LEFT", footer, "LEFT", 4, 0)
    calc.levelFS = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    calc.levelFS:SetPoint("LEFT", calc.remainFS, "RIGHT", 18, 0)
    calc.flashFS = footer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    calc.flashFS:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
    calc.flashFS:SetJustifyH("RIGHT")
    calc.flashFS:SetTextColor(1, 0.25, 0.25)

    calc:SetScript("OnShow", function()
        -- A fresh, untouched state should open showing something worth
        -- looking at: the remembered selection, else the first preset
        local state = ClassState(CurrentClass())
        if state and E.TotalSpent(state) == 0 and not state.edited then
            local build = SelectedBuild()
            if not build then
                local presets = Presets(CurrentClass())
                if presets[1] then
                    db.SelBuildKind, db.SelBuildKey = "PRESET", presets[1].key
                    build = presets[1]
                end
            end
            if build then
                ApplyTargetsWithReport(state, build)
            end
        end
        BindPanes()
        UpdateAll()
    end)

    -- Internal handles for the offline smoke harness
    calc._sidebar = sidebarButtons
    calc._state = function() return ClassState(CurrentClass()) end

    ApplyFraming()
    ApplyPosition()
    ApplyBriefingLayout()
    return calc
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

function CommanderTalents_Toggle()
    if not loaded then return end
    if not db.EnableTalents then
        print("Commander Talents is disabled — enable it in its settings panel")
        return
    end
    EnsureCalculator()
    if calc:IsShown() then
        calc:Hide()
    else
        calc:Show()
    end
end

function CommanderTalents_PrintExport()
    if not loaded then return end
    local token = CurrentClass()
    local state = ClassState(token)
    if not state then
        print("Commander Talents: no talent data installed")
        return
    end
    local s = E.Export(state)
    if s == "" then
        print("Commander Talents: the current build is empty")
    else
        print(("|cff33ff99Commander Talents:|r %s %s — %s"):format(
            ClassLabel(token), E.Signature(state), s))
    end
end

-- ---------------------------------------------------------------------------
-- Settings application & events
-- ---------------------------------------------------------------------------

local function ApplySettings()
    if not loaded then return end
    if calc then
        ApplyFraming()
        ApplyPosition()
        ApplyBriefingLayout()
        if calc:IsShown() then
            UpdateAll()
        end
    end
end

frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        db = CommanderTalentsDB
        CommanderTalentsCustom = CommanderTalentsCustom or {}
        customs = CommanderTalentsCustom
        loaded = true
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        Commander.AddListener(Events.UPDATE, ApplySettings)
    elseif not loaded then
        return
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if briefItemIDs[arg1] and RefreshBriefSoon then
            RefreshBriefSoon()
        end
    end
end)

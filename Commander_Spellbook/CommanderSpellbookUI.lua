-- Commander Spellbook: the window.
--
-- The Quest Log's shape (DECISIONS D1): double wide, split down the middle.
-- The left half is the navigator — every spell you know, one row per spell
-- however many ranks it has, in foldouts by what it does (or by talent tree),
-- searchable. The right half is the briefing for the selected spell: its
-- ranks laid out one per line, known and still to train, the selected rank's
-- own tooltip, and where your bars and macros cast it.
--
-- One window, no tabs. The toolbar's three filters change what the
-- navigator lists, never the frame: Spells (the book), Training (what a
-- trainer will teach you, our What's Training?) and Rank Check (the bars and
-- macros on an old rank, Commander Rank Check's results).
--
-- Chrome is drawn, not borrowed, by the Quest Log's rules: quads cut from
-- WHITE8X8 and tinted from the Console palette, the ink switched for the
-- parchment sheet. Casting goes through the secure buttons of
-- CommanderSpellbookSecure.lua, laid over this window and never inside it.

CommanderSpellbook = CommanderSpellbook or {}
local S = CommanderSpellbook

BINDING_HEADER_COMMANDERSPELLBOOK = "Commander Spellbook"
BINDING_NAME_COMMANDERSPELLBOOK_TOGGLE = "Open the Spellbook"
BINDING_NAME_COMMANDERSPELLBOOK_PETBOOK = "Open the Spellbook on your pet"
BINDING_NAME_COMMANDERSPELLBOOK_TRAINING = "Open Training"
BINDING_NAME_COMMANDERSPELLBOOK_SEARCH = "Search the Spellbook"

local QUAD = "Interface\\Buttons\\WHITE8X8"
local PAD = 10
local NAV_W = 316
local TOOLBAR_H = 24
local ACTIONS_H = 26
local HEADER_H = 20
local ROW_H = 24
local ICON = 18
local BIG_ICON = 40
local LADDER_H = 18
local CHIP = 16
local FRAME_W, FRAME_H = 800, 540

local frame, navScroll, navChild, detailScroll, detailChild
local navRows = {}
local book, rows, training, checkResult
local nameIndex = {}
local selectedKey, selectedRankId, selectedIssueKey
local selectedFamily, selectedItem, selectedRef
local searchText = ""
local pendingRefresh = false
local ApplyFraming

local function DB()
    return CommanderSpellbookDB or {}
end

local function Enabled()
    return DB().EnableSpellbook ~= false
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

-- Commander Rank Check, when it is loaded, switched on and set to show in
-- the spellbook (its Show in Spellbook setting)
local function RankCheck()
    local rc = CommanderRankCheck
    if type(rc) ~= "table" or type(rc.Scan) ~= "function" then return nil end
    if type(rc.ShowInSpellbook) == "function" and not rc.ShowInSpellbook() then return nil end
    return rc
end

local VIEWS = { "BOOK", "TRAIN", "CHECK" }
local VIEW_LABEL = { BOOK = "Spells", TRAIN = "Training", CHECK = "Rank Check" }
local VIEW_TIP = {
    BOOK = "Every spell you know, one row per spell. Click a row for its ranks; drag a row or its icon to a bar; click the icon to cast.",
    TRAIN = "What your class trainer will teach you now, in the next levels and later, with the gold it costs. Weapon skills from a weapon master too.",
    CHECK = "Commander Rank Check: the action bar slots and macros still casting a lower rank than you know, with Update to put your best rank there.",
}

local function View()
    local view = DB().Filter or "BOOK"
    if view == "CHECK" and not RankCheck() then view = "BOOK" end
    if view ~= "BOOK" and view ~= "TRAIN" and view ~= "CHECK" then view = "BOOK" end
    return view
end

-- ---------------------------------------------------------------------------
-- Tint and ink: the Quest Log's, for the same two grounds (see its UI file
-- for the whole story of why the parchment needs ink of its own)
-- ---------------------------------------------------------------------------

local function Accent()
    local key = (CommanderConsoleDB and CommanderConsoleDB.ConsoleColor) or "STEEL"
    if key == "CLASS" then
        local _, class = UnitClass("player")
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key then
            return color.r or 1, color.g or 1, color.b or 1
        end
    end
    return 1, 1, 1
end

local INK = {
    PARCHMENT = {
        primary   = { 0.16, 0.10, 0.04 },
        secondary = { 0.34, 0.26, 0.16 },
        faint     = { 0.48, 0.40, 0.30 },
        strong    = { 0.36, 0.16, 0.02 },
        title     = { 0.30, 0.13, 0.02 },
    },
    DARK = {
        primary   = { 0.86, 0.86, 0.90 },
        secondary = { 0.72, 0.72, 0.76 },
        faint     = { 0.55, 0.55, 0.60 },
        strong    = { 1.00, 0.95, 0.80 },
        title     = { 1.00, 0.82, 0.30 },
    },
}

local function OnPaper()
    return (DB().FrameStyle or "STONE") == "PARCHMENT"
end

local function InkSet()
    return OnPaper() and INK.PARCHMENT or INK.DARK
end

local PAPER_LUM = 0.34

local function Paper(r, g, b)
    if not OnPaper() then return r, g, b end
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum <= PAPER_LUM then return r, g, b end
    local k = PAPER_LUM / lum
    return r * k, g * k, b * k
end

local function PaperHex(hex)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    r, g, b = Paper(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function InkAccent()
    return Paper(Accent())
end

local function Ink(shade)
    local color = InkSet()[shade] or InkSet().primary
    return color[1], color[2], color[3]
end

local function InkHex(shade)
    local r, g, b = Ink(shade)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The semantic colours: the same meaning on any ground, put on the paper
local GREEN, AMBER, RED, BLUE = "40d040", "ffb030", "ff5555", "6cb8ff"

local function Hex(hex) return "|cff" .. PaperHex(hex) end

-- ---------------------------------------------------------------------------
-- Small drawing helpers
-- ---------------------------------------------------------------------------

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

-- A chevron from two rotated bars: right when shut, down when open (the
-- Quest Log's, drawn rather than a glyph or a texture file)
local function EnsureChevron(button)
    if button.chevron then return button.chevron end
    local chevron = { Quad(button, "OVERLAY"), Quad(button, "OVERLAY") }
    for _, bar in ipairs(chevron) do bar:SetSize(7, 2) end
    button.chevron = chevron
    return chevron
end

local function PointChevron(button, open)
    local chevron = EnsureChevron(button)
    local top, bottom = chevron[1], chevron[2]
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if open then
        top:SetPoint("CENTER", button, "LEFT", 8, 1.5)
        bottom:SetPoint("CENTER", button, "LEFT", 12.5, 1.5)
    else
        top:SetPoint("CENTER", button, "LEFT", 9, 2)
        bottom:SetPoint("CENTER", button, "LEFT", 9, -2)
    end
    top:SetRotation(-math.pi / 4)
    bottom:SetRotation(math.pi / 4)
end

local function NoWrap(fs)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end

local function SpellLink(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellLink then
        local link = C_Spell.GetSpellLink(id)
        if link then return link end
    end
    if GetSpellLink then return GetSpellLink(id) end
    return nil
end

local function InsertLink(link)
    if not link then return false end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then return ChatFrameUtil.InsertLink(link) end
    if ChatEdit_InsertLink then return ChatEdit_InsertLink(link) end
    return false
end

local function CombatHint()
    return "In combat the book does not cast: drag the spell to a bar, or cast it from the book once the fight is over."
end

-- ---------------------------------------------------------------------------
-- Acting on a spell
-- ---------------------------------------------------------------------------

-- Put a rank on the cursor, for a bar. A pet ability goes by its book slot;
-- a player spell by its id, which names the exact rank even when the book
-- lists only the highest (Show all spell ranks unticked).
function S.Pickup(family, entry)
    if not family or family.passive then return false end
    entry = entry or family.highest
    if not (entry and entry.known) then return false end
    if family.bookType == "pet" then
        if entry.slot and PickupSpellBookItem then PickupSpellBookItem(entry.slot, "pet") return true end
        return false
    end
    if PickupSpell then
        PickupSpell(entry.id)
        return true
    end
    if entry.slot and PickupSpellBookItem then
        PickupSpellBookItem(entry.slot, "spell")
        return true
    end
    return false
end

local function RankWords(entry)
    if not entry then return "" end
    if entry.rank then return "Rank " .. entry.rank end
    return ""
end

-- The spell a cast button casts for a family: a pet ability by name, a
-- player spell by the exact rank's id
local function CastTarget(family, entry)
    if not family or family.passive then return nil end
    entry = entry or family.highest
    if not (entry and entry.known) then return nil end
    local target
    if family.bookType == "pet" then
        if entry.command then return nil end
        target = { pet = family.name, autocast = entry.autocast }
    else
        target = { spell = entry.id }
    end
    -- Shift-click on any cast button links the rank it casts
    target.onLink = function() InsertLink(SpellLink(entry.id)) end
    return target
end

-- ---------------------------------------------------------------------------
-- The Rank Check results, as this window reads them
-- ---------------------------------------------------------------------------

local refsByName = {}

local function IndexCheck()
    refsByName = {}
    if not checkResult then return end
    for _, ref in ipairs(checkResult.refs or {}) do
        local key = (ref.name or ""):lower()
        refsByName[key] = refsByName[key] or {}
        table.insert(refsByName[key], ref)
    end
end

local function RefsFor(family)
    if not family then return {} end
    return refsByName[(family.name or ""):lower()] or {}
end

local function StaleCount(family)
    local n = 0
    for _, ref in ipairs(RefsFor(family)) do
        if ref.stale and not ref.kept then n = n + 1 end
    end
    return n
end

local scanQueued = false

-- Ask Rank Check to look again, quietly (no chat), at most twice a second
local function RequestCheck()
    local rc = RankCheck()
    if not rc or scanQueued then return end
    scanQueued = true
    local function Run()
        scanQueued = false
        rc.Scan(function(result)
            checkResult = result
            IndexCheck()
            if S.QueueRefresh then S.QueueRefresh() end
        end, { quiet = true })
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, Run) else Run() end
end

S.RequestCheck = RequestCheck

-- ---------------------------------------------------------------------------
-- The navigator
-- ---------------------------------------------------------------------------

local castTargets = {}

local function RowTooltip(row, owner)
    local tip = GameTooltip
    tip:SetOwner(owner or row, "ANCHOR_RIGHT")
    if row.headerGroup then
        tip:SetText(row.headerLabel or "", 1, 1, 1)
        local words = row.headerTip
        if words then tip:AddLine(words, nil, nil, nil, true) end
        tip:AddLine("Click to fold or unfold.", 0.55, 0.55, 0.6)
        tip:Show()
        return
    end
    local family = row.family
    if not family then return end
    local entry = row.entry or family.highest or family.ranks[1]
    local shown = false
    if family.bookType == "pet" and entry and entry.slot and tip.SetSpellBookItem then
        shown = tip:SetSpellBookItem(entry.slot, "pet") and true or false
    end
    if not shown and entry and entry.id and tip.SetSpellByID then
        tip:SetSpellByID(entry.id)
        shown = true
    end
    if not shown then tip:SetText(family.name or "", 1, 1, 1) end
    if row.item then
        local item = row.item
        tip:AddLine(" ")
        if item.weapon then
            tip:AddLine("Taught by a weapon master.", 0.85, 0.85, 0.85)
        else
            tip:AddLine(string.format("Class trainer, level %d.", item.level or 1), 0.85, 0.85, 0.85)
        end
        if (item.cost or 0) > 0 then
            tip:AddLine("Costs " .. S.Money(item.cost) .. " (less from a trainer of a faction you are Honored or better with).", 0.85, 0.85, 0.85, true)
        end
        if item.note then tip:AddLine(item.note, 1, 0.7, 0.2) end
    elseif row.ref then
        local ref = row.ref
        tip:AddLine(" ")
        tip:AddLine(string.format("%s casts rank %d; you know rank %d.", ref.where or "", ref.rank or 0, ref.best or 0),
            1, 0.7, 0.2, true)
    else
        tip:AddLine(" ")
        if family.unlearned then
            local nextWords = S.NextRankWords(family)
            if nextWords then tip:AddLine(nextWords .. ".", 0.42, 0.72, 1) end
        elseif not family.passive then
            tip:AddLine("Click the icon to cast. Drag to a bar. Shift-click to link.", 0.55, 0.55, 0.6, true)
            if InCombat() then tip:AddLine(CombatHint(), 1, 0.5, 0.3, true) end
        end
        if family.trainableNow and family.trainableNow > 0 then
            tip:AddLine(string.format("%d higher rank%s to train now.", family.trainableNow,
                family.trainableNow == 1 and "" or "s"), 0.25, 0.82, 0.25)
        end
        local stale = StaleCount(family)
        if stale > 0 then
            tip:AddLine(string.format("%d bar or macro reference%s on an old rank.", stale, stale == 1 and "" or "s"),
                1, 0.7, 0.2)
        end
    end
    tip:Show()
end

local function SelectFamily(family, rankId)
    if not family then return end
    selectedKey = family.key
    selectedRankId = rankId
end

local function RowClick(row, button)
    if row.foldKey then
        local collapsed = DB().Collapsed or {}
        collapsed[row.foldKey] = not S.IsFolded(collapsed, row.foldKey)
        DB().Collapsed = collapsed
        S.Refresh()
        return
    end
    local family = row.family
    if not family then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        local entry = row.entry or family.highest or family.ranks[1]
        InsertLink(SpellLink(entry and entry.id))
        return
    end
    if button == "RightButton" and IsControlKeyDown and IsControlKeyDown() and row.item then
        -- The suite's row Go (Commander Orders D31). Straight to Orders, not
        -- through the Go button: a Click() with Ctrl still held is that
        -- button's own Ctrl-click, which copies a /way line instead
        SelectFamily(family, row.item.id)
        S.Refresh()
        S.GoToTrainer()
        return
    end
    if row.ref then selectedIssueKey = row.ref.key end
    SelectFamily(family, row.item and row.item.id or (row.ref and row.ref.spellID) or nil)
    S.Refresh()
end

local function AcquireNavRow(position)
    local row = navRows[position]
    if row then return row end

    row = CreateFrame("Button", nil, navChild)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:RegisterForDrag("LeftButton")

    row.selection = Quad(row, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:Hide()

    row.pip = Quad(row, "ARTWORK", 1)
    row.pip:SetWidth(3)
    row.pip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -3)
    row.pip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 3)
    row.pip:Hide()

    -- A frame, not a bare texture: the cast button is pinned over it and
    -- needs a rect and a scale to copy
    row.iconFrame = CreateFrame("Frame", nil, row)
    row.iconFrame:SetSize(ICON, ICON)
    row.iconFrame:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Anchored from both ends, never wrapped (the suite's list-row rule):
    -- the value cells off the right edge, the name stretched between
    row.right = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.right:SetJustifyH("RIGHT")
    NoWrap(row.right)

    row.badge = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.badge:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.badge:SetJustifyH("RIGHT")
    NoWrap(row.badge)

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.title:SetJustifyH("LEFT")
    NoWrap(row.title)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.07)
    row:SetHighlightTexture(highlight)

    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", function(self) RowTooltip(self) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnDragStart", function(self)
        local family = self.family
        if not family then return end
        local entry = self.ref and self.ref.bestEntry or nil
        S.Pickup(family, entry)
    end)

    navRows[position] = row
    return row
end

local function ResetRow(row)
    row.family, row.item, row.ref, row.entry = nil, nil, nil, nil
    row.foldKey, row.headerGroup, row.headerLabel, row.headerTip = nil, nil, nil, nil
    row.selection:Hide()
    row.pip:Hide()
    row.badge:SetText("")
    row.right:SetText("")
    row.icon:SetDesaturated(false)
    row.icon:SetAlpha(1)
    row.iconFrame:Hide()
    if row.chevron then for _, bar in ipairs(row.chevron) do bar:Hide() end end
end

local function PaintHeader(row, item, ar, ag, ab)
    local group = item.header
    row.foldKey = item.foldKey
    row.headerGroup = group.key
    row.headerLabel = group.label
    row.headerTip = (View() == "TRAIN") and S.TrainTip(group.key) or S.GroupTip(group.key)
    row:SetHeight(HEADER_H)
    PointChevron(row, not item.collapsed)
    for _, bar in ipairs(row.chevron) do
        bar:SetVertexColor(ar, ag, ab, 0.9)
        bar:Show()
    end
    row.title:ClearAllPoints()
    row.title:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.title:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
    row.title:SetText(group.label)
    row.title:SetTextColor(InkAccent())
    local count = item.count or #group.items
    if View() == "TRAIN" and (group.cost or 0) > 0 and (group.key == "NOW" or group.key == "WEAPON") then
        row.badge:SetText(Hex(InkHex("secondary")) .. count .. "|r")
        local money = S.Money(group.cost)
        if GetMoney and GetMoney() < group.cost then money = Hex(RED) .. money .. "|r" end
        row.right:SetText(money)
    else
        row.right:SetText(tostring(count))
    end
    row.right:SetTextColor(Ink("secondary"))
    row.selection:SetVertexColor(ar, ag, ab, 0.08)
    row.selection:Show()
end

local function PaintIcon(row, family, dim)
    row.iconFrame:Show()
    row.icon:SetTexture(family.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    if dim then
        row.icon:SetDesaturated(true)
        row.icon:SetAlpha(0.6)
    end
    row.title:ClearAllPoints()
    row.title:SetPoint("LEFT", row.iconFrame, "RIGHT", 6, 0)
    row.title:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
end

local function PaintFamily(row, family)
    row.family = family
    row:SetHeight(ROW_H)
    local dim = family.unlearned or family.passive
    PaintIcon(row, family, family.unlearned)
    row.title:SetText(family.name)
    if family.unlearned then
        row.title:SetTextColor(Ink("faint"))
        local nextRank = family.nextRank
        if nextRank and nextRank.level then
            row.right:SetText(Hex(nextRank.now and GREEN or BLUE) .. "Lv " .. nextRank.level .. "|r")
        else
            row.right:SetText(Hex(InkHex("faint")) .. "not learned|r")
        end
        return
    end
    row.title:SetTextColor(Ink(dim and "faint" or "primary"))
    local highest = family.highest
    if family.passive then
        row.right:SetText(Hex(InkHex("faint")) .. "Passive|r")
    elseif highest and highest.rank then
        local of = (family.total and family.total > 1 and family.chain) and ("/" .. family.total) or ""
        row.right:SetText(Hex(InkHex("secondary")) .. highest.rank .. of .. "|r")
    end
    if DB().RowBadges ~= false then
        local marks = {}
        if (family.trainableNow or 0) > 0 then
            marks[#marks + 1] = Hex(GREEN) .. "+" .. family.trainableNow .. "|r"
        end
        if StaleCount(family) > 0 then
            marks[#marks + 1] = Hex(AMBER) .. "!|r"
        end
        row.badge:SetText(table.concat(marks, " "))
    end
    local target = CastTarget(family)
    if target then
        target.region = row.iconFrame
        target.clip = navScroll
        target.onEnter = function(button)
            row:LockHighlight()
            RowTooltip(row, button)
        end
        target.onLeave = function()
            row:UnlockHighlight()
            GameTooltip:Hide()
        end
        target.onDrag = function() S.Pickup(family) end
        target.onClick = function(_, button)
            if button == "RightButton" and family.bookType ~= "pet" then RowClick(row, "LeftButton") end
        end
        castTargets[#castTargets + 1] = target
    end
end

local function PaintTrainItem(row, item)
    local family = item.family
    row.family, row.item, row.entry = family, item, item.entry
    row:SetHeight(ROW_H)
    PaintIcon(row, family, false)
    local rank = item.entry and item.entry.rank
    local name = family.name or ""
    if rank then name = name .. "  " .. Hex(InkHex("faint")) .. "Rank " .. rank .. "|r" end
    row.title:SetText(name)
    local status = item.status
    if status == "NOW" or status == "WEAPON" then
        row.title:SetTextColor(Ink("primary"))
    else
        row.title:SetTextColor(Ink("secondary"))
    end
    if status == "SOON" or status == "LATER" then
        row.badge:SetText(Hex(status == "SOON" and BLUE or InkHex("faint")) .. "Lv " .. (item.level or 0) .. "|r")
    elseif status == "NEEDS" or status == "TALENT" then
        row.badge:SetText(Hex(AMBER) .. (status == "TALENT" and "talent" or "earlier rank") .. "|r")
    end
    local cost = item.cost or 0
    local money = cost > 0 and S.Money(cost) or "free"
    if status == "NOW" and GetMoney and GetMoney() < cost then money = Hex(RED) .. money .. "|r" end
    row.right:SetText(money)
    row.right:SetTextColor(Ink("secondary"))
end

local function PaintRef(row, ref)
    local family = ref.family
    row.family, row.ref = family, ref
    row:SetHeight(ROW_H)
    if family then
        PaintIcon(row, family, false)
    else
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row, "LEFT", 32, 0)
        row.title:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
    end
    row.title:SetText(ref.name or "")
    row.title:SetTextColor(Ink("primary"))
    if ref.stale and not ref.kept then
        row.badge:SetText(Hex(AMBER) .. "Rank " .. (ref.rank or 0) .. " of " .. (ref.best or 0) .. "|r")
    elseif ref.kept then
        row.badge:SetText(Hex(InkHex("faint")) .. "Rank " .. (ref.rank or 0) .. ", kept|r")
    else
        row.badge:SetText(Hex(InkHex("faint")) .. "Rank " .. (ref.rank or 0) .. "|r")
    end
    row.right:SetText(ref.where or "")
    row.right:SetTextColor(Ink("secondary"))
end

local function IsSelectedRow(item)
    if item.family then return selectedKey and item.family.key == selectedKey end
    if item.train then
        return selectedKey and item.train.family.key == selectedKey and selectedRankId == item.train.id
    end
    if item.ref then return selectedIssueKey and item.ref.key == selectedIssueKey end
    return false
end

local selectedTop, selectedHeight

local function LayoutNav()
    local ar, ag, ab = InkAccent()
    local y = 4
    selectedTop, selectedHeight = nil, nil
    for position, item in ipairs(rows) do
        local row = AcquireNavRow(position)
        ResetRow(row)
        if item.header then
            PaintHeader(row, item, ar, ag, ab)
        elseif item.family then
            PaintFamily(row, item.family)
        elseif item.train then
            PaintTrainItem(row, item.train)
        elseif item.ref then
            PaintRef(row, item.ref)
        end
        if not item.header and IsSelectedRow(item) then
            row.selection:SetVertexColor(ar, ag, ab, 0.22)
            row.selection:Show()
            row.pip:SetVertexColor(ar, ag, ab, 1)
            row.pip:Show()
            selectedTop, selectedHeight = y, row:GetHeight()
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)
        row:Show()
        y = y + row:GetHeight()
    end
    for position = #rows + 1, #navRows do navRows[position]:Hide() end

    if #rows == 0 then
        if not navChild.emptyFS then
            navChild.emptyFS = navChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            navChild.emptyFS:SetPoint("TOPLEFT", navChild, "TOPLEFT", 12, -16)
            navChild.emptyFS:SetPoint("RIGHT", navChild, "RIGHT", -12, 0)
            navChild.emptyFS:SetJustifyH("LEFT")
        end
        local view = View()
        local words
        if searchText ~= "" then
            words = "Nothing here matches this search."
        elseif view == "TRAIN" then
            words = "Nothing left to train. Your trainer has taught you everything your level allows."
        elseif view == "CHECK" then
            words = checkResult and "No ranked spell on any bar or macro."
                or "Rank Check has not looked yet. Press Run Check below."
        else
            words = "Your spellbook is empty."
        end
        navChild.emptyFS:SetText(words)
        navChild.emptyFS:SetTextColor(Ink("faint"))
        navChild.emptyFS:Show()
        y = y + 40
    elseif navChild.emptyFS then
        navChild.emptyFS:Hide()
    end
    navChild:SetHeight(math.max(y + 6, 1))
end

-- ---------------------------------------------------------------------------
-- The briefing
--
-- Widgets are pooled by kind and laid out top-down by measuring each wrapped
-- string, as the Quest Log's are. The font is re-applied on every pass: a
-- pooled string made large once must not stay large when reused small.
-- ---------------------------------------------------------------------------

local pools = { text = {}, ladder = {}, refLine = {}, rule = {} }
local used = { text = 0, ladder = 0, refLine = 0, rule = 0 }
local spellTip
local DETAIL_W = FRAME_W - PAD * 2 - NAV_W - 8 - 30

local function DetailWidth()
    local width = detailChild and detailChild:GetWidth() or 0
    if width <= 1 then width = DETAIL_W end
    return width
end

local function ResetDetail()
    for kind, pool in pairs(pools) do
        for _, widget in ipairs(pool) do widget:Hide() end
        used[kind] = 0
    end
    if spellTip then spellTip:Hide() end
end

local function Text(font)
    used.text = used.text + 1
    local fs = pools.text[used.text]
    if not fs then
        fs = detailChild:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        pools.text[used.text] = fs
    end
    fs:SetFontObject(font or "GameFontHighlightSmall")
    fs:ClearAllPoints()
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    if fs.SetMaxLines then fs:SetMaxLines(0) end
    fs:Show()
    return fs
end

local function Rule()
    used.rule = used.rule + 1
    local rule = pools.rule[used.rule]
    if not rule then
        rule = Quad(detailChild, "ARTWORK")
        rule:SetHeight(1)
        pools.rule[used.rule] = rule
    end
    rule:ClearAllPoints()
    rule:Show()
    return rule
end

local function Measure(fs)
    local h = (fs.GetStringHeight and fs:GetStringHeight()) or fs:GetHeight() or 0
    if not h or h <= 0 then h = 12 end
    return h
end

-- A heading with a hairline of the accent under it; returns the new y
local function Heading(text, y)
    local fs = Text("GameFontNormal")
    fs:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, -y)
    fs:SetText(text)
    fs:SetTextColor(Ink("title"))
    local h = Measure(fs)
    local rule = Rule()
    local ar, ag, ab = InkAccent()
    rule:SetVertexColor(ar, ag, ab, 0.35)
    rule:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, -(y + h + 2))
    rule:SetPoint("RIGHT", detailChild, "RIGHT", -4, 0)
    return y + h + 7
end

local function Paragraph(text, y, shade, font)
    local fs = Text(font)
    fs:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, -y)
    fs:SetWidth(DetailWidth() - 6)
    fs:SetText(text)
    fs:SetTextColor(Ink(shade or "secondary"))
    return y + Measure(fs) + 4
end

-- The big icon at the top of the briefing: the selected rank cast from it
-- and dragged off it like a book button
local function EnsureBigIcon()
    if detailChild.bigIcon then return detailChild.bigIcon end
    local holder = CreateFrame("Button", nil, detailChild)
    holder:SetSize(BIG_ICON, BIG_ICON)
    holder:RegisterForDrag("LeftButton")
    holder.icon = holder:CreateTexture(nil, "ARTWORK")
    holder.icon:SetAllPoints()
    holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    holder.border = Quad(holder, "BACKGROUND")
    holder.border:SetPoint("TOPLEFT", holder, "TOPLEFT", -1, 1)
    holder.border:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 1, -1)
    holder:SetScript("OnDragStart", function(self)
        if self.family then S.Pickup(self.family, self.entry) end
    end)
    holder:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(self.entry.id)
        if InCombat() and self.entry.known then GameTooltip:AddLine(CombatHint(), 1, 0.5, 0.3, true) end
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)
    detailChild.bigIcon = holder
    return holder
end

-- One line of the rank ladder: chip, rank, level, state. A Button so the
-- whole line selects its rank; the chip is a frame of its own for the cast
-- button to sit on.
local function LadderLine()
    used.ladder = used.ladder + 1
    local line = pools.ladder[used.ladder]
    if not line then
        line = CreateFrame("Button", nil, detailChild)
        line:SetHeight(LADDER_H)
        line:RegisterForClicks("LeftButtonUp")
        line:RegisterForDrag("LeftButton")
        line.selection = Quad(line, "BACKGROUND")
        line.selection:SetAllPoints()
        line.chip = CreateFrame("Frame", nil, line)
        line.chip:SetSize(CHIP, CHIP)
        line.chip:SetPoint("LEFT", line, "LEFT", 2, 0)
        line.chipIcon = line.chip:CreateTexture(nil, "ARTWORK")
        line.chipIcon:SetAllPoints()
        line.chipIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        line.rankFS = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line.rankFS:SetPoint("LEFT", line.chip, "RIGHT", 6, 0)
        line.rankFS:SetWidth(58)
        line.rankFS:SetJustifyH("LEFT")
        NoWrap(line.rankFS)
        line.levelFS = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line.levelFS:SetPoint("LEFT", line.rankFS, "RIGHT", 2, 0)
        line.levelFS:SetWidth(64)
        line.levelFS:SetJustifyH("LEFT")
        NoWrap(line.levelFS)
        line.stateFS = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line.stateFS:SetPoint("LEFT", line.levelFS, "RIGHT", 2, 0)
        line.stateFS:SetPoint("RIGHT", line, "RIGHT", -4, 0)
        line.stateFS:SetJustifyH("LEFT")
        NoWrap(line.stateFS)
        local highlight = line:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(QUAD)
        highlight:SetVertexColor(1, 1, 1, 0.07)
        line:SetHighlightTexture(highlight)
        line:SetScript("OnClick", function(self)
            if IsShiftKeyDown and IsShiftKeyDown() then
                InsertLink(SpellLink(self.entry and self.entry.id))
                return
            end
            selectedRankId = self.entry and self.entry.id
            S.Refresh()
        end)
        line:SetScript("OnDragStart", function(self)
            if self.family and self.entry then S.Pickup(self.family, self.entry) end
        end)
        line:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.entry.id)
            GameTooltip:AddLine("Click to read this rank below. Drag to put this rank on a bar.", 0.55, 0.55, 0.6, true)
            GameTooltip:Show()
        end)
        line:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pools.ladder[used.ladder] = line
    end
    line:ClearAllPoints()
    line:Show()
    return line
end

local function RankState(family, entry)
    if entry.known then return Hex(GREEN) .. "Known|r" end
    if entry.learned then return Hex(InkHex("faint")) .. "Replaced by a higher rank|r" end
    if entry.allowed == false then return Hex(InkHex("faint")) .. "Not for your race|r" end
    local chain = family.chain
    if chain and chain.src == "L" and entry == family.ranks[1] then
        return Hex(AMBER) .. "Talent|r"
    end
    if chain and chain.src == "Q" and entry == family.ranks[1] then
        return Hex(AMBER) .. "Quest reward|r"
    end
    if not entry.level then return Hex(InkHex("faint")) .. "Not from a trainer|r" end
    local cost = (entry.cost or 0) > 0 and ("  " .. S.Money(entry.cost)) or ""
    if entry.now then return Hex(GREEN) .. "Train now|r" .. cost end
    if entry.level <= (book and book.level or 1) then
        return Hex(AMBER) .. "After the rank before|r" .. cost
    end
    return Hex(BLUE) .. "At level " .. entry.level .. "|r" .. cost
end

local function SelectedEntry(family)
    if not family then return nil end
    if selectedRankId then
        for _, entry in ipairs(family.ranks) do
            if entry.id == selectedRankId then return entry end
        end
    end
    return family.highest or family.nextRank or family.ranks[#family.ranks]
end

local function PaintLadder(family, y)
    if not family.ranks or #family.ranks < 2 then return y end
    y = Heading(string.format("Ranks  %s%d of %d known|r", Hex(InkHex("faint")),
        family.learnedCount or 0, #family.ranks), y)
    local ar, ag, ab = InkAccent()
    local selected = SelectedEntry(family)
    for _, entry in ipairs(family.ranks) do
        local line = LadderLine()
        line.family, line.entry = family, entry
        line:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, -y)
        line:SetPoint("RIGHT", detailChild, "RIGHT", -4, 0)
        line.chipIcon:SetTexture(S.SpellIcon(entry.id) or family.icon)
        line.chipIcon:SetDesaturated(not entry.known)
        line.chipIcon:SetAlpha(entry.known and 1 or 0.55)
        line.rankFS:SetText(RankWords(entry) ~= "" and RankWords(entry) or "-")
        line.rankFS:SetTextColor(Ink(entry.known and "primary" or "secondary"))
        line.levelFS:SetText(entry.level and ("Level " .. entry.level) or "")
        line.levelFS:SetTextColor(Ink("faint"))
        line.stateFS:SetText(RankState(family, entry))
        if entry == selected then
            line.selection:SetVertexColor(ar, ag, ab, 0.18)
            line.selection:Show()
        else
            line.selection:Hide()
        end
        local target = CastTarget(family, entry)
        if target and family.bookType ~= "pet" then
            target.region = line.chip
            target.clip = detailScroll
            target.onEnter = function(button)
                line:LockHighlight()
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(entry.id)
                GameTooltip:AddLine("Click to cast this rank. Drag it to a bar.", 0.55, 0.55, 0.6, true)
                GameTooltip:Show()
            end
            target.onLeave = function()
                line:UnlockHighlight()
                GameTooltip:Hide()
            end
            target.onDrag = function() S.Pickup(family, entry) end
            castTargets[#castTargets + 1] = target
        end
        y = y + LADDER_H
    end
    return y + 6
end

-- The selected rank's own tooltip, embedded: the client writes the mana, the
-- cast time, the range and the numbers exactly as a hover would (the
-- Formulary's D7). Its height is only known once laid out; a first paint
-- that reads nothing tries again a frame later.
local function EnsureSpellTip()
    if spellTip then return spellTip end
    spellTip = CreateFrame("GameTooltip", "CommanderSpellbookSpellTip", detailChild, "GameTooltipTemplate")
    spellTip:SetFrameStrata(frame:GetFrameStrata() or "HIGH")
    spellTip:SetFrameLevel((detailChild:GetFrameLevel() or 1) + 2)
    if spellTip.SetClampedToScreen then spellTip:SetClampedToScreen(false) end
    return spellTip
end

local function PaintSpellTip(family, entry, y)
    if not entry then return y end
    local tip = EnsureSpellTip()
    tip:SetOwner(detailChild, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", detailChild, "TOPLEFT", -2, -y)
    local ok
    if family.bookType == "pet" and entry.slot and tip.SetSpellBookItem then
        ok = pcall(tip.SetSpellBookItem, tip, entry.slot, "pet")
    else
        ok = pcall(tip.SetSpellByID, tip, entry.id)
    end
    if not ok then
        tip:Hide()
        return y
    end
    tip:Show()
    local h = tip:GetHeight()
    if not h or h < 20 then
        h = 20
        -- Not laid out yet on its first showing: paint again a frame later,
        -- once per rank. A tooltip that never grows must not repaint the
        -- whole window every frame.
        if frame._tipRetried ~= entry.id then
            frame._tipRetried = entry.id
            C_Timer.After(0, function()
                if frame:IsShown() then S.Refresh() end
            end)
        end
    end
    return y + h + 6
end

local function RefLine()
    used.refLine = used.refLine + 1
    local line = pools.refLine[used.refLine]
    if not line then
        line = CreateFrame("Frame", nil, detailChild)
        line:SetHeight(22)
        line.text = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line.text:SetPoint("LEFT", line, "LEFT", 0, 0)
        line.text:SetJustifyH("LEFT")
        NoWrap(line.text)
        line.keep = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
        line.keep:SetSize(58, 20)
        line.keep:SetPoint("RIGHT", line, "RIGHT", -4, 0)
        line.fix = CreateFrame("Button", nil, line, "UIPanelButtonTemplate")
        line.fix:SetSize(64, 20)
        line.fix:SetPoint("RIGHT", line.keep, "LEFT", -4, 0)
        line.text:SetPoint("RIGHT", line.fix, "LEFT", -6, 0)
        line.fix:SetText("Update")
        if line.fix.SetMotionScriptsWhileDisabled then line.fix:SetMotionScriptsWhileDisabled(true) end
        line.fix:SetScript("OnClick", function(self)
            local rc = RankCheck()
            if rc and rc.Fix and self.ref then
                rc.Fix(self.ref)
                RequestCheck()
            end
        end)
        line.fix:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Update", 1, 1, 1)
            if self.ref and self.ref.kind == "MACRO" then
                GameTooltip:AddLine("Rewrite the rank in this macro to the best one you know.", nil, nil, nil, true)
            else
                GameTooltip:AddLine("Put the best rank you know in this action slot.", nil, nil, nil, true)
            end
            if InCombat() then GameTooltip:AddLine("Not in combat: bars and macros are locked mid-fight.", 1, 0.3, 0.25, true) end
            GameTooltip:Show()
        end)
        line.fix:SetScript("OnLeave", function() GameTooltip:Hide() end)
        line.keep:SetScript("OnClick", function(self)
            local rc = RankCheck()
            if rc and rc.Keep and self.ref then
                rc.Keep(self.ref, not self.ref.kept)
                RequestCheck()
            end
        end)
        Commander.UI.AttachTooltip(line.keep, "Keep",
            "Leave this one on its rank on purpose (a down-ranked heal, a cheap rank for a proc): Rank Check stops calling it out of date, here and at login. Press again to take that back.",
            "ANCHOR_TOP")
        pools.refLine[used.refLine] = line
    end
    line:ClearAllPoints()
    line:Show()
    return line
end

local function PaintRefs(family, y)
    local rc = RankCheck()
    if not rc then return y end
    local refs = RefsFor(family)
    y = Heading("On Your Bars", y)
    if not checkResult then
        return Paragraph("Rank Check has not looked yet.", y, "faint")
    end
    if #refs == 0 then
        return Paragraph("Not on any action bar slot or macro by rank.", y, "faint")
    end
    for _, ref in ipairs(refs) do
        local line = RefLine()
        line.fix.ref, line.keep.ref = ref, ref
        line:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, -y)
        line:SetPoint("RIGHT", detailChild, "RIGHT", -4, 0)
        local state
        if ref.stale and not ref.kept then
            state = Hex(AMBER) .. "rank " .. (ref.rank or 0) .. ", best " .. (ref.best or 0) .. "|r"
        elseif ref.kept then
            state = Hex(InkHex("faint")) .. "rank " .. (ref.rank or 0) .. ", kept on purpose|r"
        else
            state = Hex(GREEN) .. "rank " .. (ref.rank or 0) .. ", current|r"
        end
        line.text:SetText((ref.where or "") .. "  " .. state)
        line.text:SetTextColor(Ink("primary"))
        local stale = ref.stale and true or false
        line.fix:SetShown(stale and not ref.kept)
        line.fix:SetEnabled(not InCombat())
        line.keep:SetShown(stale)
        line.keep:SetText(ref.kept and "Unkeep" or "Keep")
        if selectedIssueKey and ref.key == selectedIssueKey then
            line.text:SetTextColor(Ink("strong"))
        end
        y = y + 22
    end
    return y + 4
end

local function PaintWeapon(family, y)
    local weapon = family.weapon
    if not weapon then return y end
    y = Heading("Taught By", y)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local trainers = weapon.trainers and faction and weapon.trainers[faction] or {}
    if #trainers == 0 then
        return Paragraph("No weapon master of your faction teaches it.", y, "faint")
    end
    for _, trainer in ipairs(trainers) do
        local zone
        if C_Map and C_Map.GetMapInfo and trainer.map then
            local info = C_Map.GetMapInfo(trainer.map)
            zone = info and info.name
        end
        y = Paragraph(string.format("%s%s|r  %s", Hex(InkHex("primary")), trainer.name or "?",
            zone and (Hex(InkHex("faint")) .. zone .. "|r") or ""), y, "primary")
    end
    return y
end

local function LayoutDetail()
    ResetDetail()
    local family = selectedFamily
    local bigIcon = detailChild.bigIcon
    if not family then
        if bigIcon then bigIcon:Hide() end
        local y = Paragraph(View() == "CHECK" and "Select a reference on the left." or "Select a spell on the left.",
            4, "faint")
        detailChild:SetHeight(y + 10)
        return
    end
    local entry = SelectedEntry(family)
    local y = 2

    -- The header: icon, name, and one line of what it is
    bigIcon = EnsureBigIcon()
    bigIcon:ClearAllPoints()
    bigIcon:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, -y)
    bigIcon.family, bigIcon.entry = family, entry
    bigIcon.icon:SetTexture((entry and S.SpellIcon(entry.id)) or family.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    bigIcon.icon:SetDesaturated(not (entry and entry.known))
    local ar, ag, ab = InkAccent()
    bigIcon.border:SetVertexColor(ar, ag, ab, 0.6)
    bigIcon:Show()

    local name = Text("GameFontNormalLarge")
    name:SetPoint("TOPLEFT", bigIcon, "TOPRIGHT", 10, -1)
    name:SetWidth(DetailWidth() - BIG_ICON - 20)
    if name.SetWordWrap then name:SetWordWrap(false) end
    name:SetText(family.name or "")
    name:SetTextColor(Ink("title"))

    local facts = {}
    if family.passive then facts[#facts + 1] = "Passive" end
    if entry and entry.rank then
        if family.total and family.total > 1 and family.chain then
            facts[#facts + 1] = string.format("Rank %d of %d", entry.rank, family.total)
        else
            facts[#facts + 1] = "Rank " .. entry.rank
        end
    end
    if family.role and family.role ~= "WEAPON" then facts[#facts + 1] = S.GroupLabel(family.role, book) end
    if family.tab and book and book.tabs[family.tab] and family.tab > 1 then
        facts[#facts + 1] = book.tabs[family.tab].name
    end
    if family.weapon then facts[#facts + 1] = "Weapon skill" end
    if family.unlearned then facts[#facts + 1] = "Not learned yet" end
    local sub = Text("GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    sub:SetWidth(DetailWidth() - BIG_ICON - 20)
    sub:SetText(table.concat(facts, "  \194\183  "))
    sub:SetTextColor(Ink("secondary"))

    local nextWords = (not family.weapon) and S.NextRankWords(family) or nil
    local nextFS
    if nextWords then
        nextFS = Text("GameFontHighlightSmall")
        nextFS:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -3)
        local nextRank = family.nextRank
        local cost = nextRank and (nextRank.cost or 0) > 0 and (", " .. S.Money(nextRank.cost)) or ""
        nextFS:SetText(nextWords .. cost)
        nextFS:SetTextColor(Paper(nextRank and nextRank.now and 0.25 or 0.42, nextRank and nextRank.now and 0.82 or 0.72,
            nextRank and nextRank.now and 0.25 or 1))
    end
    local headerH = math.max(BIG_ICON, Measure(name) + Measure(sub) + 6 + (nextFS and (Measure(nextFS) + 3) or 0))
    y = y + headerH + 10

    if not family.passive and entry and entry.known then
        local target = CastTarget(family, entry)
        if target then
            target.region = bigIcon
            target.clip = detailScroll
            target.onEnter = function(button)
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(entry.id)
                GameTooltip:AddLine("Click to cast. Drag to a bar.", 0.55, 0.55, 0.6, true)
                GameTooltip:Show()
            end
            target.onLeave = function() GameTooltip:Hide() end
            target.onDrag = function() S.Pickup(family, entry) end
            castTargets[#castTargets + 1] = target
        end
    end

    if View() == "CHECK" then
        y = PaintRefs(family, y)
        y = PaintLadder(family, y)
        y = PaintSpellTip(family, entry, y)
    else
        y = PaintLadder(family, y)
        y = PaintWeapon(family, y)
        y = PaintSpellTip(family, entry, y)
        if not family.unlearned and not family.passive and not family.weapon then
            y = PaintRefs(family, y)
        end
    end
    detailChild:SetHeight(math.max(y + 10, 1))
end

-- ---------------------------------------------------------------------------
-- Toolbar, actions and footer
-- ---------------------------------------------------------------------------

local function StyleFilters()
    if not frame then return end
    local ar, ag, ab = InkAccent()
    local view = View()
    for _, key in ipairs(VIEWS) do
        local button = frame.filters[key]
        local active = view == key
        if button.SetNormalFontObject then
            button:SetNormalFontObject(active and GameFontNormalSmall or GameFontDisableSmall)
        end
        local fs = button.GetFontString and button:GetFontString()
        if fs then fs:SetTextColor(Ink(active and "strong" or "faint")) end
        button.underline:SetVertexColor(ar, ag, ab, active and 0.95 or 0)
        button:SetShown(key ~= "CHECK" or RankCheck() ~= nil)
    end
end

local shownCount, totalCount = 0, 0

local function UpdateToolbar()
    if not frame then return end
    StyleFilters()
    local view = View()
    local text
    if view == "TRAIN" then
        local count = training and training.nowCount or 0
        if count > 0 then
            text = string.format("%s%d now|r  \194\183  %s", Hex(GREEN), count, S.Money(training.nowCost))
        else
            text = "Nothing to train now"
        end
    elseif view == "CHECK" then
        if not checkResult then
            text = "Not checked yet"
        elseif #(checkResult.issues or {}) > 0 then
            text = string.format("%s%d out of date|r", Hex(AMBER), #checkResult.issues)
        else
            text = string.format("%sPASS|r  \194\183  %d checked", Hex(GREEN), checkResult.checked or 0)
        end
    else
        if shownCount ~= totalCount then
            text = string.format("%d shown  \194\183  %d spells", shownCount, totalCount)
        else
            text = string.format("%d spells", totalCount)
        end
    end
    frame.countFS:SetText(text)
    frame.countFS:SetTextColor(Ink("secondary"))
    frame.groupDrop:SetShown(view == "BOOK")
    if frame.titleAccent then
        local ar, ag, ab = InkAccent()
        frame.titleAccent:SetVertexColor(ar, ag, ab, 0.5)
    end
end

local function RefreshGo(button)
    if button and button.Refresh then button:Refresh() end
end

-- The actions under the briefing change with the view: Cast and Link for a
-- spell; Ignore on the Training view; Update, Keep and Update All on the
-- Rank Check view; Go to the trainer wherever there is something to learn
local function UpdateActions()
    if not frame then return end
    local view = View()
    local family = selectedFamily
    local entry = SelectedEntry(family)
    local castable = family and not family.passive and entry and entry.known and CastTarget(family, entry) ~= nil
    local placed = {}
    local function Place(button, show)
        button:SetShown(show and true or false)
        if show then placed[#placed + 1] = button end
    end
    Place(frame.castBtn, view ~= "CHECK" and castable)
    Place(frame.linkBtn, view ~= "CHECK" and family and entry ~= nil)
    Place(frame.fixBtn, view == "CHECK" and selectedRef ~= nil and selectedRef.stale and not selectedRef.kept)
    Place(frame.keepBtn, view == "CHECK" and selectedRef ~= nil and selectedRef.stale)
    Place(frame.fixAllBtn, view == "CHECK" and checkResult ~= nil and #(checkResult.issues or {}) > 0)
    local previous
    for _, button in ipairs(placed) do
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", frame.actions, "LEFT", 0, 0)
        end
        previous = button
    end
    frame.castBtn:SetEnabled(castable and not InCombat())
    -- The Cast button's click is the secure button pinned over it
    if castable and frame.castBtn:IsShown() then
        local target = CastTarget(family, entry)
        if target then
            target.region = frame.castBtn
            target.onEnter = function(button)
                frame.castBtn:LockHighlight()
                GameTooltip:SetOwner(button, "ANCHOR_TOP")
                GameTooltip:SetText("Cast", 1, 1, 1)
                GameTooltip:AddLine("Cast " .. (family.name or "") .. (entry.rank and (" (Rank " .. entry.rank .. ")") or "")
                    .. ". The icon at the top of the briefing, and the icon of each rank, cast too.", nil, nil, nil, true)
                GameTooltip:Show()
            end
            target.onLeave = function()
                frame.castBtn:UnlockHighlight()
                GameTooltip:Hide()
            end
            castTargets[#castTargets + 1] = target
        end
    end
    frame.fixBtn:SetEnabled(not InCombat())
    frame.fixAllBtn:SetEnabled(not InCombat())
    if selectedRef then frame.keepBtn:SetText(selectedRef.kept and "Unkeep" or "Keep") end

    -- The right end: Ignore on Training, Go to the trainer when there is a
    -- rank to learn (or a weapon skill), Run Check on the Rank Check view
    local ignoreId = view == "TRAIN" and selectedItem and selectedItem.id or nil
    frame.ignoreBtn:SetShown(ignoreId ~= nil)
    if ignoreId then
        frame.ignoreBtn:SetText(S.IsIgnored(ignoreId) and "Unignore" or "Ignore")
    end
    local learnable = family and (family.weapon or family.nextRank ~= nil)
    frame.goBtn:SetShown(view ~= "CHECK" and learnable and true or false)
    if frame.goBtn:IsShown() then
        -- The Go button keeps its own label (it reads "Going to ..." while
        -- the arrow is its); the words are changed there, not on the text
        local label = family.weapon and "Go to Weapon Master" or "Go to Trainer"
        if frame.goBtn._goLabel ~= label then
            frame.goBtn._goLabel = label
            -- Its Refresh writes the text only when the Going state flips,
            -- so a new label is put on here while it is not lit
            if not frame.goBtn._goGoing then frame.goBtn:SetText(label) end
        end
        RefreshGo(frame.goBtn)
    end
    frame.runBtn:SetShown(view == "CHECK")
    local right = frame.actions
    local rightPoint = "RIGHT"
    for _, button in ipairs({ frame.runBtn, frame.goBtn, frame.ignoreBtn }) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint("RIGHT", right, rightPoint, right == frame.actions and 0 or -4, 0)
            right, rightPoint = button, "LEFT"
        end
    end
end

local function UpdateFooter()
    if not (frame and frame.footer) then return end
    local rc = RankCheck()
    frame.footer:SetShown(rc ~= nil)
    if not rc then return end
    local words
    if not checkResult then
        words = Hex(InkHex("faint")) .. "not checked yet|r"
    elseif #(checkResult.issues or {}) > 0 then
        words = string.format("%s%d out of date|r", Hex(AMBER), #checkResult.issues)
    else
        words = string.format("%sPASS|r %s%d checked|r", Hex(GREEN), Hex(InkHex("faint")), checkResult.checked or 0)
        if (checkResult.unresolved or 0) > 0 then
            words = words .. string.format(" %s(%d unread)|r", Hex(AMBER), checkResult.unresolved)
        end
    end
    frame.footer.value:SetText(words)
    frame.footer.label:SetTextColor(Ink("secondary"))
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

local function PlaceCast()
    if not (frame and frame:IsShown()) or InCombat() then return end
    S.Cast.Place(castTargets)
end

local function RebuildNameIndex()
    nameIndex = {}
    for _, family in ipairs(book.list) do
        if family.bookType ~= "pet" then nameIndex[(family.name or ""):lower()] = family end
    end
end

-- The Rank Check view's rows: out of date, kept on purpose, up to date
local function BuildCheckRows()
    local out = {}
    if not checkResult then return out, 0 end
    local groups = {
        { key = "STALE", label = "Out of Date", items = {} },
        { key = "KEPT", label = "Kept on Purpose", items = {} },
        { key = "CURRENT", label = "Up to Date", items = {} },
    }
    local query = searchText:lower()
    for _, ref in ipairs(checkResult.refs or {}) do
        ref.family = (ref.spellID and S.FamilyFor(book, ref.spellID)) or nameIndex[(ref.name or ""):lower()]
        if ref.family and ref.bestID then
            for _, entry in ipairs(ref.family.ranks) do
                if entry.id == ref.bestID then ref.bestEntry = entry end
            end
        end
        if query == "" or (ref.name or ""):lower():find(query, 1, true) then
            local group = (ref.stale and not ref.kept) and groups[1] or (ref.kept and groups[2]) or groups[3]
            table.insert(group.items, ref)
        end
    end
    local collapsed = DB().Collapsed or {}
    local shown = 0
    for _, group in ipairs(groups) do
        if #group.items > 0 then
            local foldKey = "CHECK:" .. group.key
            local isCollapsed = S.IsFolded(collapsed, foldKey) and query == ""
            out[#out + 1] = { header = group, foldKey = foldKey, collapsed = isCollapsed, count = #group.items }
            if not isCollapsed then
                for _, ref in ipairs(group.items) do out[#out + 1] = { ref = ref } end
            end
            shown = shown + #group.items
        end
    end
    return out, shown
end

function S.Refresh()
    if not (frame and frame:IsShown()) then return end
    local db = DB()
    local view = View()
    castTargets = {}

    if frame._view ~= view then
        frame._view = view
        if navScroll then navScroll:SetVerticalScroll(0) end
        if detailScroll then detailScroll:SetVerticalScroll(0) end
    end

    book = S.Scan({ unlearned = db.ShowUnlearned or searchText ~= "" })
    RebuildNameIndex()
    training = S.Training(book, { soon = db.SoonLevels })

    selectedFamily, selectedItem, selectedRef = nil, nil, nil
    local shown
    -- The selection stays where the player put it while it still exists,
    -- even in a folded group (folding the group, or an Ignore that moves
    -- the item into the folded Ignored, must not move the briefing to some
    -- other spell for good). Only a search re-picks, when it hides the
    -- selection: typing to find a spell briefs the first one it finds.
    local searching = searchText ~= ""
    local function Visible(test)
        for _, row in ipairs(rows) do
            if test(row) then return row end
        end
        return nil
    end
    if view == "TRAIN" then
        rows, shown = S.BuildTrainRows(training, { search = searchText, collapsed = db.Collapsed })
        totalCount = shown
        local function IsSelected(item)
            return item.family.key == selectedKey and (not selectedRankId or item.id == selectedRankId)
        end
        for _, group in pairs(training.groups) do
            for _, item in ipairs(group.items) do
                if not selectedItem and IsSelected(item) then selectedItem = item end
            end
        end
        if selectedItem and searching and not Visible(function(row) return row.train == selectedItem end) then
            selectedItem = nil
        end
        if not selectedItem then
            local row = Visible(function(r) return r.train ~= nil end)
            selectedItem = row and row.train
        end
        if selectedItem then
            selectedFamily = selectedItem.family
            selectedKey, selectedRankId = selectedFamily.key, selectedItem.id
        end
    elseif view == "CHECK" then
        rows, shown = BuildCheckRows()
        totalCount = shown
        for _, ref in ipairs(checkResult and checkResult.refs or {}) do
            if ref.key == selectedIssueKey then selectedRef = ref break end
        end
        if selectedRef and searching and not Visible(function(row) return row.ref == selectedRef end) then
            selectedRef = nil
        end
        if not selectedRef then
            local row = Visible(function(r) return r.ref ~= nil end)
            selectedRef = row and row.ref
        end
        if selectedRef then
            selectedIssueKey = selectedRef.key
            selectedFamily = selectedRef.family
            if selectedFamily then
                selectedKey = selectedFamily.key
                selectedRankId = selectedRef.spellID
            end
        end
    else
        rows, shown, totalCount = S.BuildBookRows(book, {
            search = searchText, groupBy = db.GroupBy, collapsed = db.Collapsed,
            passives = db.ShowPassives ~= false, unlearned = db.ShowUnlearned,
        })
        selectedFamily = selectedKey and book.families[selectedKey] or nil
        if selectedFamily and (searching or selectedFamily.unlearnedFamily)
            and not Visible(function(row) return row.family == selectedFamily end) then
            selectedFamily = nil
        end
        if not selectedFamily then
            selectedFamily = S.FirstFamily(rows)
            selectedRankId = nil
        end
        if selectedFamily then selectedKey = selectedFamily.key end
    end
    shownCount = shown or 0
    if selectedFamily and view ~= "CHECK" then
        local charDB = S.EnsureCharDB and S.EnsureCharDB()
        if charDB then charDB.Selected = selectedKey end
    end

    LayoutNav()
    LayoutDetail()
    UpdateToolbar()
    UpdateActions()
    UpdateFooter()
    PlaceCast()
    -- Rects settle once the pass's anchors resolve; place again a frame on
    if C_Timer and C_Timer.After then C_Timer.After(0, PlaceCast) end
end

local function QueueRefresh()
    if pendingRefresh or not (frame and frame:IsShown()) then return end
    pendingRefresh = true
    local function Run()
        pendingRefresh = false
        S.Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.05, Run) else Run() end
end

S.QueueRefresh = QueueRefresh
S.onTextLoaded = function() QueueRefresh() end

-- ---------------------------------------------------------------------------
-- Position and framing (the Quest Log's sheet, see its UI file)
-- ---------------------------------------------------------------------------

local function SavePosition()
    if not frame then return end
    local point, _, _, x, y = frame:GetPoint(1)
    if point then
        local scale = frame:GetScale() or 1
        DB().FramePos = { point = point, x = x * scale, y = y * scale }
    end
end

function S.ApplyPosition()
    if not frame then return end
    local db = DB()
    local scale = db.FrameScale or 1
    frame:SetScale(scale)
    if frame._dragging then return end
    frame:ClearAllPoints()
    local pos = db.FramePos
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local SHEET_BACKDROP = {
    PARCHMENT = {
        bgFile = "Interface\\QuestFrame\\QuestBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 256, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
    STONE = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
}
local SHEET_BASE = {
    PARCHMENT = { 0.91, 0.85, 0.70 },
    STONE = { 0.09, 0.09, 0.10 },
}

local INSET_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function EnsureSheet(material)
    local art = frame.sheet
    if not art then
        art = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        art:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
        frame.sheet = art
    end
    if art._material ~= material then
        art._material = material
        if art.SetBackdrop then
            art:SetBackdrop(SHEET_BACKDROP[material] or SHEET_BACKDROP.STONE)
            art:SetBackdropColor(1, 1, 1, 1)
            art:SetBackdropBorderColor(1, 1, 1, 1)
        end
        if frame.paperBase then
            local base = SHEET_BASE[material] or SHEET_BASE.STONE
            frame.paperBase:SetColorTexture(base[1], base[2], base[3], 1)
        end
    end
    if frame.headerPlate then return art end
    -- The fill is a tinted quad under the backdrop: a bgFile that fails to
    -- resolve draws only its edge, and the window would be a hole
    local base = art:CreateTexture(nil, "BACKGROUND", nil, -8)
    local fill = SHEET_BASE[material] or SHEET_BASE.STONE
    base:SetColorTexture(fill[1], fill[2], fill[3], 1)
    base:SetPoint("TOPLEFT", art, "TOPLEFT", 10, -10)
    base:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -10, 10)
    frame.paperBase = base

    local plate = art:CreateTexture(nil, "ARTWORK")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(256, 64)
    plate:SetPoint("TOP", frame, "TOP", 0, 12)
    frame.headerPlate = plate

    local title = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", plate, "TOP", 0, -14)
    title:SetText("Spellbook")
    frame.plateTitle = title
    return art
end

function ApplyFraming(force)
    if not frame then return end
    local style = DB().FrameStyle or "STONE"
    if not force and frame._framedAs == style then return end
    frame._framedAs = style
    local parchment = style == "PARCHMENT"
    local sheet = parchment or style == "STONE"
    Commander.UI.SetTemplateDressing(frame, not sheet)
    if sheet then
        EnsureSheet(style)
        frame.sheet:Show()
        frame.headerPlate:Show()
        frame.plateTitle:Show()
    elseif frame.sheet then
        frame.sheet:Hide()
        frame.headerPlate:Hide()
        frame.plateTitle:Hide()
    end
    Commander.UI.ApplyStyleBackdrop(frame, (style == "DARK") and "DARK" or "NONE")
    for _, pane in ipairs({ frame.navPane, frame.detailPane }) do
        if pane and pane.SetBackdropColor then
            if parchment then
                pane:SetBackdropColor(0.30, 0.20, 0.08, 0.10)
                pane:SetBackdropBorderColor(0.50, 0.38, 0.22, 1)
            else
                pane:SetBackdropColor(0, 0, 0, 0.5)
                pane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
            end
        end
    end
    if frame.toolbarBg then
        if parchment then
            frame.toolbarBg:SetVertexColor(0.30, 0.20, 0.08, 0.10)
        else
            frame.toolbarBg:SetVertexColor(0, 0, 0, 0.45)
        end
    end
end

S.ApplyFraming = ApplyFraming

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local GROUPS = {
    { text = "By role", value = "ROLE" },
    { text = "By talent tree", value = "TREE" },
}

local function SetView(view)
    if view == "CHECK" and not RankCheck() then view = "BOOK" end
    DB().Filter = view
    if view == "CHECK" then RequestCheck() end
    S.Refresh()
end

local function ScrollWheel(self, delta)
    local target = self:GetVerticalScroll() - delta * 40
    local maxScroll = self:GetVerticalScrollRange()
    if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
    self:SetVerticalScroll(target)
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "CommanderSpellbookFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Spellbook") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderSpellbookFrame") end

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        frame._dragging = true
        frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame._dragging = false
        SavePosition()
        PlaceCast()
    end)

    -- Toolbar: the three views, search, grouping, the count
    local toolbar = CreateFrame("Frame", nil, frame)
    frame.toolbar = toolbar
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
    toolbar:SetHeight(TOOLBAR_H)

    frame.toolbarBg = Quad(frame, "BACKGROUND")
    frame.toolbarBg:SetPoint("TOPLEFT", toolbar, "TOPLEFT", -4, 3)
    frame.toolbarBg:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", 4, -3)
    frame.toolbarBg:SetVertexColor(0, 0, 0, 0.45)

    frame.filters = {}
    local previous
    for _, key in ipairs(VIEWS) do
        local button = CreateFrame("Button", nil, toolbar)
        button:SetSize(key == "CHECK" and 76 or 62, TOOLBAR_H)
        button:SetNormalFontObject(GameFontDisableSmall)
        button:SetHighlightFontObject(GameFontHighlightSmall)
        button:SetText(VIEW_LABEL[key])
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
        end
        button.underline = Quad(button, "ARTWORK")
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 2)
        button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 2)
        button:SetScript("OnClick", function() SetView(key) end)
        Commander.UI.AttachTooltip(button, VIEW_LABEL[key], VIEW_TIP[key], "ANCHOR_BOTTOM")
        button:HookScript("OnLeave", function()
            if C_Timer and C_Timer.After then C_Timer.After(0, StyleFilters) else StyleFilters() end
        end)
        frame.filters[key] = button
        previous = button
    end

    frame.searchBox = CreateFrame("EditBox", "CommanderSpellbookSearchBox", toolbar, "InputBoxTemplate")
    frame.searchBox:SetSize(150, 20)
    frame.searchBox:SetPoint("LEFT", previous, "RIGHT", 14, 0)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetMaxLetters(60)
    frame.searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        searchText = self:GetText() or ""
        S.Refresh()
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        searchText = ""
        self:ClearFocus()
        S.Refresh()
    end)
    frame.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local ghost = frame.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ghost:SetPoint("LEFT", frame.searchBox, "LEFT", 4, 0)
    ghost:SetText("Search spells")
    frame.searchBox:HookScript("OnTextChanged", function(self)
        ghost:SetShown((self:GetText() or "") == "")
    end)
    Commander.UI.AttachTooltip(frame.searchBox, "Search",
        "Matches spell names, and the name of a group (\"heal\", \"control\"). A search also finds the class spells you have not learned yet, and opens every foldout it found something in. Escape clears it.",
        "ANCHOR_BOTTOM")

    frame.groupDrop = CreateFrame("Frame", "CommanderSpellbookGroupDrop", toolbar, "UIDropDownMenuTemplate")
    frame.groupDrop:SetPoint("LEFT", frame.searchBox, "RIGHT", -6, -2)
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(frame.groupDrop, function()
            for _, option in ipairs(GROUPS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.text
                info.value = option.value
                info.checked = (DB().GroupBy or "ROLE") == option.value
                info.func = function()
                    DB().GroupBy = option.value
                    UIDropDownMenu_SetSelectedValue(frame.groupDrop, option.value)
                    UIDropDownMenu_SetText(frame.groupDrop, option.text)
                    S.Refresh()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetWidth(frame.groupDrop, 104)
    end

    frame.countHit = CreateFrame("Frame", nil, toolbar)
    frame.countHit:SetPoint("RIGHT", toolbar, "RIGHT", -2, 0)
    frame.countHit:SetSize(150, TOOLBAR_H)
    frame.countHit:EnableMouse(true)
    frame.countFS = frame.countHit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.countFS:SetPoint("RIGHT", frame.countHit, "RIGHT", 0, 0)
    frame.countFS:SetJustifyH("RIGHT")
    NoWrap(frame.countFS)

    frame.titleAccent = Quad(frame, "ARTWORK")
    frame.titleAccent:SetHeight(1)
    frame.titleAccent:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    frame.titleAccent:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)

    -- The navigator, with the Rank Check footer under it
    local navPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.navPane = navPane
    navPane:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    navPane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + 4 + ACTIONS_H + 4)
    navPane:SetWidth(NAV_W)
    if navPane.SetBackdrop then
        navPane:SetBackdrop(INSET_BACKDROP)
        navPane:SetBackdropColor(0, 0, 0, 0.5)
        navPane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
    end

    navScroll = CreateFrame("ScrollFrame", "CommanderSpellbookNavScroll", navPane, "UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT", navPane, "TOPLEFT", 6, -6)
    navScroll:SetPoint("BOTTOMRIGHT", navPane, "BOTTOMRIGHT", -16, 6)
    navScroll:EnableMouseWheel(true)
    navScroll:SetScript("OnMouseWheel", ScrollWheel)
    navChild = CreateFrame("Frame", nil, navScroll)
    navChild:SetSize(NAV_W - 34, 1)
    navScroll:SetScrollChild(navChild)
    navScroll:SetScript("OnSizeChanged", function(_, width) navChild:SetWidth(width) end)
    -- The cast buttons are pinned to the screen: a scroll moves the rows out
    -- from under them, so every scroll re-places them (out of combat)
    navScroll:HookScript("OnVerticalScroll", PlaceCast)

    local detailPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.detailPane = detailPane
    detailPane:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", NAV_W + 8, -8)
    detailPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 4 + ACTIONS_H + 4)
    if detailPane.SetBackdrop then
        detailPane:SetBackdrop(INSET_BACKDROP)
        detailPane:SetBackdropColor(0, 0, 0, 0.5)
        detailPane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
    end

    detailScroll = CreateFrame("ScrollFrame", "CommanderSpellbookDetailScroll", detailPane, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 8, -8)
    detailScroll:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -16, 6)
    detailScroll:EnableMouseWheel(true)
    detailScroll:SetScript("OnMouseWheel", ScrollWheel)
    detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(DETAIL_W, 1)
    detailScroll:SetScrollChild(detailChild)
    detailScroll:SetScript("OnSizeChanged", function(_, width) detailChild:SetWidth(width) end)
    detailScroll:HookScript("OnVerticalScroll", PlaceCast)

    Commander.UI.SlimScrollBar("CommanderSpellbookNavScroll", 2, 2)
    Commander.UI.SlimScrollBar("CommanderSpellbookDetailScroll", 2, 2)

    -- The actions, under the briefing and never inside it
    local actions = CreateFrame("Frame", nil, frame)
    frame.actions = actions
    actions:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -4)
    actions:SetPoint("TOPRIGHT", detailPane, "BOTTOMRIGHT", 0, -4)
    actions:SetHeight(ACTIONS_H)

    local function ActionButton(name, label, width, tooltip, handler)
        local button = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
        button:SetScript("OnClick", handler)
        Commander.UI.AttachTooltip(button, label, tooltip, "ANCHOR_TOP")
        button:Hide()
        frame[name] = button
        return button
    end

    -- Cast: a plain button for the look; the click is taken by the secure
    -- button pinned over it (CommanderSpellbookSecure.lua). In combat that
    -- one is away and this one is greyed out.
    ActionButton("castBtn", "Cast", 64, function()
        if InCombat() then return CombatHint() end
        return "Cast the selected rank. The icon at the top of the briefing, and the icon of each rank, cast too."
    end, function() end)
    ActionButton("linkBtn", "Link", 56, "Put a link to the selected rank in the chat box. Shift-clicking a row does the same.",
        function()
            local entry = SelectedEntry(selectedFamily)
            InsertLink(SpellLink(entry and entry.id))
        end)
    ActionButton("fixBtn", "Update", 70, function()
        local words = "Put the best rank you know where this one is: the action slot, or the rank written in the macro."
        if InCombat() then words = words .. " Not in combat: bars and macros are locked mid-fight." end
        return words
    end, function()
        local rc = RankCheck()
        if rc and rc.Fix and selectedRef then
            rc.Fix(selectedRef)
            RequestCheck()
        end
    end)
    ActionButton("keepBtn", "Keep", 64,
        "Leave this one on its rank on purpose (a down-ranked heal): Rank Check stops calling it out of date. Press again to take that back.",
        function()
            local rc = RankCheck()
            if rc and rc.Keep and selectedRef then
                rc.Keep(selectedRef, not selectedRef.kept)
                RequestCheck()
            end
        end)
    ActionButton("fixAllBtn", "Update All", 84, function()
        local words = "Update every out-of-date reference at once. The ones you kept on purpose stay as they are."
        if InCombat() then words = words .. " Not in combat." end
        return words
    end, function()
        local rc = RankCheck()
        if rc and rc.FixAll and checkResult then
            rc.FixAll(checkResult)
            RequestCheck()
        end
    end)
    ActionButton("ignoreBtn", "Ignore", 76,
        "Leave this spell off this character's Training list (a rank you will never use). It moves to Ignored, where Unignore brings it back.",
        function()
            if not selectedItem then return end
            S.SetIgnored(selectedItem.id, not S.IsIgnored(selectedItem.id))
            S.Refresh()
        end)
    ActionButton("runBtn", "Run Check", 84,
        "Look at every action bar slot and macro again (also: /crank, which writes the result to chat).",
        function() RequestCheck() end)

    -- Go to the trainer: the class trainer through Orders' locator (Questie
    -- knows where they stand), or for a weapon skill the weapon masters of
    -- your faction who teach it, the arrow on the nearest
    frame.goBtn = Commander.UI.GoButton(actions, {
        label = "Go to Trainer", width = 156, height = 22, source = "Spellbook", anchor = "ANCHOR_TOP",
        icon = "TRAINER",
        tooltip = function()
            local family = selectedFamily
            if family and family.weapon then
                return "Go to the nearest weapon master of your faction who teaches " .. (family.name or "it") .. "."
            end
            return "Go to the nearest trainer of your class (needs Questie, which knows where they stand)."
        end,
    })
    frame.goBtn._goOpts.spec = function(button)
        local family = selectedFamily
        if not (family and family.weapon) then return nil end
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        local trainers = family.weapon.trainers and faction and family.weapon.trainers[faction] or {}
        local places = {}
        for _, trainer in ipairs(trainers) do
            if trainer.map and trainer.x and trainer.y then
                places[#places + 1] = { map = trainer.map, x = trainer.x, y = trainer.y,
                    title = (trainer.name or "Weapon Master") .. " (" .. (family.name or "") .. ")" }
            end
        end
        if #places == 0 then return nil, "nowhere" end
        button._goOpts.key = "weapon:" .. (family.ranks[1] and family.ranks[1].id or 0)
        local first = places[1]
        return { map = first.map, x = first.x, y = first.y, title = first.title, alternatives = places }
    end
    frame.goBtn._goOpts.query = function(button)
        local family = selectedFamily
        if family and family.weapon then return nil end
        button._goOpts.key = "trainer"
        return { townsfolk = "Class Trainer" }
    end
    frame.goBtn:Hide()

    -- The same place the Go button would go to, for a row's Ctrl+Right-click
    function S.GoToTrainer()
        local opts = frame.goBtn._goOpts
        local orders = CommanderOrders
        if type(orders) ~= "table" or type(orders.GoTo) ~= "function" then
            print("Commander Spellbook: Go needs Commander Orders.")
            return
        end
        local target = opts.spec(frame.goBtn) or opts.query(frame.goBtn)
        if not target then
            print("Commander Spellbook: no trainer to go to for that.")
            return
        end
        orders.GoTo(target, { source = opts.source, key = opts.key, icon = opts.icon })
    end

    -- The Rank Check footer, under the navigator and level with the actions
    local footer = CreateFrame("Button", nil, frame)
    frame.footer = footer
    footer:SetPoint("TOPLEFT", navPane, "BOTTOMLEFT", 0, -4)
    footer:SetPoint("TOPRIGHT", navPane, "BOTTOMRIGHT", 0, -4)
    footer:SetHeight(ACTIONS_H)
    footer.label = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footer.label:SetPoint("LEFT", footer, "LEFT", 4, 0)
    footer.label:SetText("Rank Check")
    footer.value = footer:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    footer.value:SetPoint("LEFT", footer.label, "RIGHT", 8, 0)
    footer.value:SetPoint("RIGHT", footer, "RIGHT", -4, 0)
    footer.value:SetJustifyH("LEFT")
    NoWrap(footer.value)
    local footerHighlight = footer:CreateTexture(nil, "HIGHLIGHT")
    footerHighlight:SetAllPoints()
    footerHighlight:SetTexture(QUAD)
    footerHighlight:SetVertexColor(1, 1, 1, 0.05)
    footer:SetHighlightTexture(footerHighlight)
    footer:SetScript("OnClick", function() SetView("CHECK") end)
    Commander.UI.AttachTooltip(footer, "Rank Check",
        "Whether your action bars and macros cast the best rank you know of every spell. Click for the list, with Update and Keep for each one.",
        "ANCHOR_TOP")

    -- Scale grip, matching the Quest Log's
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 25)
    grip.tex = grip:CreateTexture(nil, "ARTWORK")
    grip.tex:SetAllPoints()
    grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function()
        frame._dragging = true
        local startX, startY = GetCursorPosition()
        local startScale = DB().FrameScale or 1
        local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local delta = ((x - startX) - (y - startY)) / 2 / uiScale
            local newScale = math.max(0.6, math.min(1.6, startScale + delta / 160))
            DB().FrameScale = math.floor(newScale * 100 + 0.5) / 100
            frame:SetScale(DB().FrameScale)
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        frame._dragging = false
        SavePosition()
        Commander.Notify(COMMANDER_SPELLBOOK_EVENTS.UPDATE)
    end)
    Commander.UI.AttachTooltip(grip, "Resize", "Drag to resize the window.", "ANCHOR_LEFT")

    frame:SetScript("OnShow", function()
        ApplyFraming(true)
        S.ApplyPosition()
        if UIDropDownMenu_SetSelectedValue then
            local group = DB().GroupBy or "ROLE"
            UIDropDownMenu_SetSelectedValue(frame.groupDrop, group)
            for _, option in ipairs(GROUPS) do
                if option.value == group then UIDropDownMenu_SetText(frame.groupDrop, option.text) end
            end
        end
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_OPEN then PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN) end
        RequestCheck()
        S.Refresh()
    end)
    frame:SetScript("OnHide", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_SPELLBOOK_CLOSE then PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE) end
        S.Cast.Withdraw()
    end)

    S.Cast.Attach(frame, PlaceCast)
    ApplyFraming(true)
    S.ApplyPosition()
    local charDB = S.EnsureCharDB and S.EnsureCharDB()
    if charDB and charDB.Selected then selectedKey = charDB.Selected end
    return frame
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

function CommanderSpellbook_Show()
    if not Enabled() then
        print("Commander Spellbook: the module is switched off in its settings.")
        return
    end
    EnsureFrame()
    frame:Show()
    -- Never take keyboard focus on open: the window opens with a key, and a
    -- focused search box would turn WASD into typing
    if frame.searchBox then frame.searchBox:ClearFocus() end
end

function CommanderSpellbook_Hide()
    if frame then frame:Hide() end
end

function CommanderSpellbook_Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        CommanderSpellbook_Show()
    end
end

-- Open on a view ("BOOK", "TRAIN", "CHECK") or on the pet's abilities
-- ("PET": the Spells view with the pet's foldout open and in view)
function CommanderSpellbook_Open(view)
    if view == "PET" then
        local db = DB()
        db.Filter = "BOOK"
        local collapsed = db.Collapsed or {}
        collapsed[(db.GroupBy == "TREE" and "TREE" or "ROLE") .. ":PETBOOK"] = false
        db.Collapsed = collapsed
    elseif view then
        DB().Filter = view
    end
    if frame and frame:IsShown() then
        S.Refresh()
    else
        CommanderSpellbook_Show()
    end
    if view == "PET" and frame and frame:IsShown() then
        -- A frame later: a scroll frame learns its new range only when it
        -- next lays out, and a jump clamped to the old one goes nowhere
        local function Reveal()
            for position, row in ipairs(rows or {}) do
                if row.header and row.header.key == "PETBOOK" then
                    local top = 0
                    for i = 1, position - 1 do
                        top = top + ((navRows[i] and navRows[i]:GetHeight()) or ROW_H)
                    end
                    local range = navScroll:GetVerticalScrollRange() or 0
                    local content = navChild:GetHeight() - navScroll:GetHeight()
                    navScroll:SetVerticalScroll(math.max(0, math.min(top, math.max(range, content))))
                    break
                end
            end
        end
        Reveal()
        if C_Timer and C_Timer.After then C_Timer.After(0, Reveal) end
    end
end

-- The pet book key: the pet's foldout when the window is shut, closed when
-- it is already up (as Shift-P closes the stock pet book)
function CommanderSpellbook_TogglePet()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        CommanderSpellbook_Open("PET")
    end
end

function CommanderSpellbook_FocusSearch()
    CommanderSpellbook_Show()
    if frame and frame.searchBox then frame.searchBox:SetFocus() end
end

S.Toggle = CommanderSpellbook_Toggle
S.Show = CommanderSpellbook_Show

-- Drawn state, for the harness: what the window put on screen
function S._NavRows() return navRows end
function S._Rows() return rows end
function S._Frame() return frame end
function S._Selected() return selectedFamily, selectedItem, selectedRef end
function S._SetSearch(text)
    searchText = text or ""
    if frame and frame.searchBox then frame.searchBox:SetText(searchText) end
    S.Refresh()
end
function S._CastTargets() return castTargets end
function S._Check() return checkResult end

-- ---------------------------------------------------------------------------
-- Taking over the stock spellbook
--
-- Two doors, and neither replaces a Blizzard function (ToggleSpellBook is
-- called from secure code, and an addon's copy of it would taint the book's
-- own state, then the spell buttons that read it):
--   * The keys. Every key bound to the spellbook or the pet book gets an
--     OVERRIDE binding to this window's own binding, set out of combat and
--     re-set when the player rebinds. A key press never reaches Blizzard's
--     book, so it works mid-fight too.
--   * Everything else that shows the stock book (the micro button, another
--     addon) is caught on the book's OnShow and handed over: the stock book
--     is put away and this one opened. Out of combat only — the stock book
--     has secure spell buttons and cannot be hidden by an addon mid-fight, so
--     a micro-button click in combat gets Blizzard's book, as it always did.
-- Both consult the setting live: turning the takeover off gives Blizzard's
-- book back with no reload.
-- ---------------------------------------------------------------------------

local function TakingOver()
    return Enabled() and DB().TakeOverSpellbook ~= false
end

S.TakingOver = TakingOver

local bindOwner = CreateFrame("Frame", "CommanderSpellbookBindings", UIParent)
local appliedBindings = ""
local bindingsPending = false

function S.ApplyBindings()
    if InCombat() then
        bindingsPending = true
        return
    end
    bindingsPending = false
    local want = {}
    if TakingOver() and GetBindingKey then
        for _, key in ipairs({ GetBindingKey("TOGGLESPELLBOOK") }) do
            want[#want + 1] = { key, "COMMANDERSPELLBOOK_TOGGLE" }
        end
        for _, key in ipairs({ GetBindingKey("TOGGLEPETBOOK") }) do
            want[#want + 1] = { key, "COMMANDERSPELLBOOK_PETBOOK" }
        end
    end
    local parts = {}
    for _, pair in ipairs(want) do parts[#parts + 1] = pair[1] .. "=" .. pair[2] end
    local signature = table.concat(parts, ";")
    -- SetOverrideBinding raises UPDATE_BINDINGS, which calls this again:
    -- the signature is what stops that from being a loop
    if signature == appliedBindings then return end
    appliedBindings = signature
    if ClearOverrideBindings then ClearOverrideBindings(bindOwner) end
    if SetOverrideBinding then
        for _, pair in ipairs(want) do SetOverrideBinding(bindOwner, false, pair[1], pair[2]) end
    end
end

local function InstallTakeover()
    if S._takeoverInstalled then return end
    S._takeoverInstalled = true
    if SpellBookFrame and SpellBookFrame.HookScript then
        SpellBookFrame:HookScript("OnShow", function(self)
            if not TakingOver() or InCombat() then return end
            local pet = BOOKTYPE_PET and self.bookType == BOOKTYPE_PET
            if HideUIPanel then HideUIPanel(self) else self:Hide() end
            -- A toggle, as the micro button is: with this window already up,
            -- the click that would have opened the stock book closes it
            if frame and frame:IsShown() then
                frame:Hide()
            else
                CommanderSpellbook_Open(pet and "PET" or nil)
            end
        end)
    end
    S.ApplyBindings()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local EVENTS = {
    "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED", "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_MONEY", "UPDATE_BINDINGS",
    "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
}
for _, event in ipairs(EVENTS) do
    -- One pcall each: a name this client does not know must not take the
    -- registrations after it down with it (the suite's Tradecraft lesson)
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InstallTakeover()
        if Commander and Commander.AddListener then
            Commander.AddListener(COMMANDER_SPELLBOOK_EVENTS.UPDATE, function()
                S.ApplyBindings()
                if frame and frame:IsShown() then
                    ApplyFraming(true)
                    S.ApplyPosition()
                    S.Refresh()
                end
            end)
            if COMMANDER_RANKCHECK_EVENTS and COMMANDER_RANKCHECK_EVENTS.RESULT then
                Commander.AddListener(COMMANDER_RANKCHECK_EVENTS.RESULT, function(result)
                    checkResult = result
                    IndexCheck()
                    QueueRefresh()
                end)
            end
        end
        return
    end
    if event == "UPDATE_BINDINGS" then
        S.ApplyBindings()
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if bindingsPending then S.ApplyBindings() end
        QueueRefresh()
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- The Cast and Update buttons grey out; the cast buttons themselves
        -- were put away by the Secure file's own handler
        if frame and frame:IsShown() then UpdateActions() end
        return
    end
    if event == "UNIT_PET" and ... ~= "player" then return end
    if not (frame and frame:IsShown()) then return end
    if event == "PLAYER_LEVEL_UP" and C_Timer and C_Timer.After then
        -- UnitLevel can still answer the old level while this event is
        -- being dispatched (WhatsTraining's note on the same event): look
        -- again once it has caught up
        C_Timer.After(1, QueueRefresh)
    end
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" or event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        RequestCheck()
    end
    QueueRefresh()
end)

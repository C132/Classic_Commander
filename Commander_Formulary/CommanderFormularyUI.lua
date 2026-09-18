-- Commander Formulary: the window.
--
-- Double wide, split down the middle, the way the Quest Log and the
-- Quartermaster are. The left half is the navigator: every recipe the
-- profession has, under the slot it enchants or the thing it makes, with a
-- filter bar (all / known / unknown / learnable now), a search box that
-- reaches into reagents, sellers and droppers, and a sort. The right half
-- is the recipe: the client's own tooltip for it, the reagents against your
-- bags, exactly how to learn it — trainer, formula, every vendor with
-- coordinates and a waypoint, every dropper with its chance, the quest, the
-- reputation — and a Craft button.
--
-- It replaces the stock Enchanting window. Enchanting is a CRAFT-frame
-- profession on this client and its window is a 1-column list with a
-- Create button; this is the same list with the other two thirds of the
-- profession beside it. The craft window's own list is still read every
-- time it opens, because it is the one authority on what this character
-- knows (ASSUMPTIONS A2), and then it is put away.
--
-- Chrome is drawn, not borrowed: selection bars, progress hairlines and
-- chevrons are quads cut from WHITE8X8 and tinted from the Console palette,
-- per the suite's rule (ARIALN renders shape glyphs as boxes; art files move
-- across patches). The sheet behind the window is the Quest Log's.

CommanderFormulary = CommanderFormulary or {}
local F = CommanderFormulary

BINDING_HEADER_COMMANDERFORMULARY = "Commander Formulary"
BINDING_NAME_COMMANDERFORMULARY_TOGGLE = "Open the Formulary"
BINDING_NAME_COMMANDERFORMULARY_SEARCH = "Search the Formulary"

local D_ALL = CommanderFormulary_Data
local M = CommanderFormulary_Model
local Events = COMMANDER_FORMULARY_EVENTS

local QUAD = "Interface\\Buttons\\WHITE8X8"
local PAD = 10
local NAV_W = 330
local TOOLBAR_H = 24
local ACTIONS_H = 28
local ROW_H = 22
local HEAD_H = 24
local FRAME_W, FRAME_H = 840, 560

local db, char
local loaded = false
local frame, navScroll, navChild, detailScroll, detailChild
local navRows = {}
local view, rows
local selectedSpell
local searchText = ""
local craftOpen = false
local pendingRefresh = false

local function DB() return CommanderFormularyDB or {} end

local function Data()
    return D_ALL.ENCHANTING
end

-- ---------------------------------------------------------------------------
-- Tint and ink (the Quest Log's rules, verbatim in spirit)
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
        primary = { 0.16, 0.10, 0.04 }, secondary = { 0.34, 0.26, 0.16 }, faint = { 0.48, 0.40, 0.30 },
        strong = { 0.36, 0.16, 0.02 }, title = { 0.30, 0.13, 0.02 },
    },
    DARK = {
        primary = { 0.86, 0.86, 0.90 }, secondary = { 0.72, 0.72, 0.76 }, faint = { 0.60, 0.60, 0.64 },
        strong = { 1.00, 0.95, 0.80 }, title = { 1.00, 0.82, 0.30 },
    },
}

local function OnPaper() return (DB().FrameStyle or "STONE") == "PARCHMENT" end
local function InkSet() return OnPaper() and INK.PARCHMENT or INK.DARK end

local PAPER_LUM = 0.34
local function Paper(r, g, b)
    if not OnPaper() then return r, g, b end
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum <= PAPER_LUM then return r, g, b end
    local k = PAPER_LUM / lum
    return r * k, g * k, b * k
end

local function Ink(shade)
    local c = InkSet()[shade] or InkSet().primary
    return c[1], c[2], c[3]
end

local function Hex(r, g, b)
    r, g, b = Paper(r, g, b)
    return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Difficulty colours are the craft list's own
local DIFF = {
    orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 },
}
local GOOD = { 0.3, 1, 0.4 }
local BAD = { 1, 0.35, 0.3 }
local WARN = { 1, 0.6, 0.2 }

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

local function AttachTooltip(widget, title, text, anchor)
    Commander.UI.AttachTooltip(widget, title, text, anchor or "ANCHOR_RIGHT")
end

local function Announce(text)
    print("|cff33ff99Commander Formulary|r: " .. text)
end

-- ---------------------------------------------------------------------------
-- Client shims and the world
-- ---------------------------------------------------------------------------

local GetItemInfo_ = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount_ = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemIcon_ = (C_Item and C_Item.GetItemIconByID) or GetItemIcon

local function ItemName(id)
    local name = GetItemInfo_ and GetItemInfo_(id)
    if name then return name end
    return Data().items[id] or ("item " .. tostring(id))
end

local function ItemIcon(id)
    local icon = GetItemIcon_ and GetItemIcon_(id)
    if icon then return icon end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function SpellName(spell)
    local name = GetSpellInfo and GetSpellInfo(spell)
    return name
end

local function SpellIcon(spell)
    return (GetSpellTexture and GetSpellTexture(spell)) or "Interface\\Icons\\Trade_Engraving"
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local expandTried = false
local function ReadSkill()
    local data = Data()
    if not (GetNumSkillLines and GetSkillLineInfo) then return 0, 0 end
    local wanted = SpellName(data.abilitySpell) or data.name
    local function scan()
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and name == wanted then return rank or 0, maxRank or 0 end
        end
    end
    local rank, maxRank = scan()
    if rank == nil and ExpandSkillHeader and not expandTried then
        expandTried = true
        ExpandSkillHeader(0)
        rank, maxRank = scan()
    end
    return rank or 0, maxRank or 0
end

-- The craft window: read on every open, put away when replacing
local craftNameToSpell
local function CraftWindowIsOurs()
    local shown = craftOpen or (CraftFrame and CraftFrame.IsShown and CraftFrame:IsShown())
    if not shown then return false end
    if not GetCraftDisplaySkillLine then return true end
    return GetCraftDisplaySkillLine() == (SpellName(Data().abilitySpell) or Data().name)
end

local function ScanCraftWindow()
    if not CraftWindowIsOurs() or not GetNumCrafts then return false end
    if not craftNameToSpell then
        craftNameToSpell = {}
        for _, rec in ipairs(Data().recipes) do
            craftNameToSpell[SpellName(rec.spell) or rec.name] = rec.spell
        end
    end
    local seen = 0
    for i = 1, GetNumCrafts() do
        local name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            local spell = craftNameToSpell[name]
            if spell then
                char.known[spell] = true
                seen = seen + 1
            end
        end
    end
    char.scanned = true
    return seen > 0
end

local function Known(spell)
    if IsSpellKnown and IsSpellKnown(spell) then return true end
    if IsPlayerSpell and IsPlayerSpell(spell) then return true end
    return char.known[spell] == true
end

local function Count(item, includeBank)
    if not GetItemCount_ then return 0 end
    return GetItemCount_(item, includeBank and true or false) or 0
end

local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    if f == "Alliance" or f == "Horde" then return f end
    return nil
end

local function Standing(factionId)
    if GetFactionInfoByID then
        local _, _, standing = GetFactionInfoByID(factionId)
        return standing
    end
    return nil
end

local function BuildWorld()
    local rank, maxRank = ReadSkill()
    return {
        rank = rank, maxRank = maxRank,
        known = Known, count = Count, faction = Faction(), standing = Standing,
        name = function(id) return GetItemInfo_ and GetItemInfo_(id) or nil end,
        spellName = SpellName,
    }
end

-- ---------------------------------------------------------------------------
-- The view
-- ---------------------------------------------------------------------------

local Repaint -- forward
local world

local function Rebuild()
    if not loaded then return end
    if craftOpen then ScanCraftWindow() end
    world = BuildWorld()
    view = M.Build(Data(), world, { bank = db.CountBank })
    Repaint()
end

local function ScheduleRefresh()
    if pendingRefresh or not loaded then return end
    pendingRefresh = true
    C_Timer.After(0, function()
        pendingRefresh = false
        if frame and frame:IsShown() then Rebuild() end
    end)
end

-- ---------------------------------------------------------------------------
-- Waypoints
-- ---------------------------------------------------------------------------

local function SetWaypoint(place, title)
    if place.map and place.x and TomTom and TomTom.AddWaypoint then
        local ok = pcall(TomTom.AddWaypoint, TomTom, place.map, place.x / 100, place.y / 100,
            { title = title or place.name, persistent = false, minimap = true, world = true, crazy = true })
        if ok then
            Announce(("Waypoint set: %s — %s (%.1f, %.1f)"):format(place.name, place.zone, place.x, place.y))
            return
        end
    end
    if place.x then
        Announce(("%s — %s (%.1f, %.1f)"):format(place.name, place.zone, place.x, place.y))
    else
        Announce(("%s — %s"):format(place.name, place.zone or "?"))
    end
end

-- ---------------------------------------------------------------------------
-- Crafting: a secure macro button (DoCraft and casting by name are protected
-- on this client — Commander_Tradecraft DECISIONS D7 has the whole story)
-- ---------------------------------------------------------------------------

local TARGET_SLOT = { WRIST = 9, CHEST = 5, CLOAK = 15, FEET = 8, HANDS = 10, SHIELD = 17, FINGER = 11,
    WEAPON = 16, TWOHAND = 16, RANGED = 18 }

local function CraftMacro(entry)
    if not entry then return "" end
    local lines = { "/cast " .. entry.name }
    local slot = TARGET_SLOT[entry.category]
    if entry.rec.enchant and slot and db.AutoTargetGear and GetInventoryItemID and GetInventoryItemID("player", slot) then
        lines[#lines + 1] = "/use " .. slot
        if db.AutoConfirmReplace then lines[#lines + 1] = "/click StaticPopup1Button1" end
    end
    return table.concat(lines, "\n")
end

local craftHolder, craftButton, craftMacroText
local function EnsureCraftButton(parent)
    if craftHolder then return craftHolder end
    if InCombat() then return nil end
    craftHolder = CreateFrame("Frame", nil, parent)
    craftHolder:SetSize(90, 22)
    craftButton = CreateFrame("Button", "CommanderFormularyCraft", craftHolder, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    craftButton:SetAllPoints(craftHolder)
    craftButton:RegisterForClicks("AnyDown", "AnyUp")
    craftButton:SetAttribute("type", "macro")
    craftButton:SetAttribute("macrotext", "")
    craftButton:SetText("Craft")
    craftHolder:Hide()
    return craftHolder
end

local function SetCraftMacro(entry)
    if not craftHolder or InCombat() then return false end
    local text = CraftMacro(entry)
    if text ~= craftMacroText then
        craftMacroText = text
        craftButton:SetAttribute("macrotext", text)
    end
    return true
end

local openHolder
local function EnsureOpenButton(parent)
    if openHolder then return openHolder end
    if InCombat() then return nil end
    openHolder = CreateFrame("Frame", nil, parent)
    openHolder:SetSize(120, 22)
    local b = CreateFrame("Button", "CommanderFormularyOpen", openHolder, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    b:SetAllPoints(openHolder)
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "spell")
    b:SetAttribute("spell", SpellName(Data().abilitySpell) or Data().name)
    b:SetText("Read Recipes")
    AttachTooltip(b, "Read what you know",
        "Opens the stock Enchanting window for a moment so the list of recipes you know can be read, then puts it away again. The Formulary does this on its own whenever that window opens.")
    openHolder:Hide()
    return openHolder
end

-- ---------------------------------------------------------------------------
-- The sheet (borrowed from the Quest Log)
-- ---------------------------------------------------------------------------

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
local SHEET_BASE = { PARCHMENT = { 0.91, 0.85, 0.70 }, STONE = { 0.09, 0.09, 0.10 } }
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
        -- Drawn fill under the backdrop: a bgFile that fails to resolve draws
        -- its edge and no background at all (the Quest Log found this out)
        local base = art:CreateTexture(nil, "BACKGROUND", nil, -8)
        base:SetTexture(QUAD)
        base:SetPoint("TOPLEFT", art, "TOPLEFT", 10, -10)
        base:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -10, 10)
        frame.sheetBase = base
        local plate = art:CreateTexture(nil, "ARTWORK")
        plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        plate:SetSize(256, 64)
        plate:SetPoint("TOP", frame, "TOP", 0, 12)
        frame.headerPlate = plate
        local title = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", plate, "TOP", 0, -14)
        title:SetText("Formulary")
        frame.plateTitle = title
    end
    if art._material ~= material then
        art._material = material
        if art.SetBackdrop then
            art:SetBackdrop(SHEET_BACKDROP[material] or SHEET_BACKDROP.STONE)
            art:SetBackdropColor(1, 1, 1, 1)
            art:SetBackdropBorderColor(1, 1, 1, 1)
        end
        local fill = SHEET_BASE[material] or SHEET_BASE.STONE
        frame.sheetBase:SetVertexColor(fill[1], fill[2], fill[3], 1)
    end
    return art
end

local function ApplyFraming(force)
    if not frame then return end
    local style = DB().FrameStyle or "STONE"
    if not force and frame._framedAs == style then return end
    frame._framedAs = style
    local sheet = (style == "PARCHMENT" or style == "STONE")
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
            if OnPaper() then
                pane:SetBackdropColor(0.30, 0.20, 0.08, 0.10)
                pane:SetBackdropBorderColor(0.50, 0.38, 0.22, 1)
            else
                pane:SetBackdropColor(0, 0, 0, 0.5)
                pane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
            end
        end
    end
    frame:SetScale(DB().FrameScale or 1)
end

-- ---------------------------------------------------------------------------
-- Navigator rows
-- ---------------------------------------------------------------------------

local function EnsureChevron(button)
    if button.chevron then return button.chevron end
    local chevron = { Quad(button, "OVERLAY"), Quad(button, "OVERLAY") }
    for _, bar in ipairs(chevron) do bar:SetSize(7, 2) end
    button.chevron = chevron
    return chevron
end

local function SetChevron(button, open, r, g, b)
    local c = EnsureChevron(button)
    for _, bar in ipairs(c) do
        bar:ClearAllPoints()
        bar:SetVertexColor(r, g, b, 1)
        bar:Show()
    end
    if open then
        c[1]:SetPoint("CENTER", button, "LEFT", 7, 1); c[1]:SetRotation(math.rad(-45))
        c[2]:SetPoint("CENTER", button, "LEFT", 11, 1); c[2]:SetRotation(math.rad(45))
    else
        c[1]:SetPoint("CENTER", button, "LEFT", 9, 3); c[1]:SetRotation(math.rad(45))
        c[2]:SetPoint("CENTER", button, "LEFT", 9, -1); c[2]:SetRotation(math.rad(-45))
    end
end

local function NavRow(i)
    local row = navRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, navChild)
    row:SetHeight(ROW_H)
    row.bar = Quad(row, "BACKGROUND")
    row.bar:SetAllPoints()
    row.bar:Hide()
    row.hl = Quad(row, "HIGHLIGHT")
    row.hl:SetVertexColor(1, 1, 1, 0.07)
    row.hl:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon:SetPoint("LEFT", row, "LEFT", 22, 0)
    row.dot = Quad(row, "OVERLAY")
    row.dot:SetSize(5, 5)
    row.dot:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")
    row.right:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.right:SetWidth(98)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.progress = Quad(row, "ARTWORK")
    row.progress:SetHeight(2)
    row.progress:Hide()
    row.track = Quad(row, "BACKGROUND", 1)
    row.track:SetHeight(2)
    row.track:Hide()
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    navRows[i] = row
    return row
end

local function SelectRecipe(spell)
    selectedSpell = spell
    char.selected = spell
    Repaint()
end

-- The trainers are listed under their own header at the foot of the
-- navigator; selecting one puts their place and a waypoint in the briefing
local function TrainerRows()
    local out = {}
    local data = Data()
    local faction = world and world.faction
    local mine = {}
    for _, t in ipairs(data.trainers) do
        if not t.faction or not faction or t.faction == faction then mine[#mine + 1] = t end
    end
    if #mine == 0 then return out end
    out[#out + 1] = { kind = "trainers", count = #mine, collapsed = char.collapsed.TRAINERS and true or false }
    if not char.collapsed.TRAINERS then
        for _, t in ipairs(mine) do out[#out + 1] = { kind = "trainer", trainer = t } end
    end
    return out
end

local function ToggleCategory(key)
    char.collapsed[key] = not char.collapsed[key] or nil
    Repaint()
end

local SOURCE_TINT = { Trainer = { 0.6, 0.85, 1 }, Vendor = { 0.8, 0.8, 0.8 }, Reputation = { 0.85, 0.7, 1 },
    Drop = { 1, 0.75, 0.5 }, ["World drop"] = { 1, 0.75, 0.5 }, Quest = { 1, 0.9, 0.5 }, Chest = { 0.8, 0.8, 0.8 }, Container = { 0.8, 0.8, 0.8 } }

local function PaintNav()
    local pr, pg, pb = Ink("primary")
    local sr, sg, sb = Ink("secondary")
    local fr, fg, fb = Ink("faint")
    local tr, tg, tb = Ink("title")
    local ar, ag, ab = Accent()
    local y = 0
    local n = 0
    for _, r in ipairs(rows) do
        n = n + 1
        local row = NavRow(n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", navChild, "TOPRIGHT", 0, y)
        row.bar:Hide(); row.dot:Hide(); row.icon:Hide(); row.progress:Hide(); row.track:Hide()
        if row.chevron then for _, bar in ipairs(row.chevron) do bar:Hide() end end
        row.name:ClearAllPoints()
        row.right:SetText("")
        row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil)
        if r.kind == "trainers" then
            row:SetHeight(HEAD_H)
            SetChevron(row, not r.collapsed, tr, tg, tb)
            row.name:SetPoint("LEFT", row, "LEFT", 20, 2)
            row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            row.name:SetFontObject(GameFontNormalSmall)
            row.name:SetText("Trainers")
            row.name:SetTextColor(tr, tg, tb)
            row.right:SetText(("%s%d|r"):format(Hex(fr, fg, fb), r.count))
            row:SetScript("OnClick", function() ToggleCategory("TRAINERS") end)
            AttachTooltip(row, "Trainers", "Every Enchanting trainer your faction can use, with where they stand. Master rank is taught only in Outland.", "ANCHOR_RIGHT")
        elseif r.kind == "trainer" then
            local t = r.trainer
            row:SetHeight(ROW_H)
            row.icon:SetTexture(Data().icon)
            row.icon:SetAlpha(t.outland and 1 or 0.7)
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            row.name:SetFontObject(GameFontHighlightSmall)
            row.name:SetText(t.name)
            row.name:SetTextColor(pr, pg, pb)
            row.right:SetText(("%s%s|r"):format(Hex(fr, fg, fb), t.outland and "Master" or "to Artisan"))
            if selectedSpell == "trainer:" .. t.npc then
                row.bar:SetVertexColor(ar, ag, ab, OnPaper() and 0.25 or 0.18)
                row.bar:Show()
            end
            local key = "trainer:" .. t.npc
            row:SetScript("OnClick", function() SelectRecipe(key) end)
            AttachTooltip(row, t.name, ("%s (%.1f, %.1f)"):format(t.zone, t.x, t.y), "ANCHOR_RIGHT")
        elseif r.kind == "category" then
            local cat = r.cat
            row:SetHeight(HEAD_H)
            SetChevron(row, not r.collapsed, tr, tg, tb)
            row.name:SetPoint("LEFT", row, "LEFT", 20, 2)
            row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            row.name:SetFontObject(GameFontNormalSmall)
            row.name:SetText(cat.label)
            row.name:SetTextColor(tr, tg, tb)
            local extra = cat.learnable > 0 and (Hex(GOOD[1], GOOD[2], GOOD[3]) .. ("+%d|r "):format(cat.learnable)) or ""
            row.right:SetText(("%s%s%d|r %s/ %d|r"):format(extra, Hex(pr, pg, pb), cat.known, Hex(fr, fg, fb), cat.total))
            row.right:SetTextColor(pr, pg, pb)
            -- completion hairline
            row.track:ClearAllPoints()
            row.track:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 20, 2)
            row.track:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 2)
            row.track:SetVertexColor(1, 1, 1, OnPaper() and 0.15 or 0.08)
            row.track:Show()
            row.progress:ClearAllPoints()
            row.progress:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 20, 2)
            local width = math.max(1, (navChild:GetWidth() - 26) * (cat.total > 0 and cat.known / cat.total or 0))
            row.progress:SetWidth(width)
            row.progress:SetVertexColor(ar, ag, ab, 0.8)
            row.progress:Show()
            local key = cat.key
            row:SetScript("OnClick", function() ToggleCategory(key) end)
            AttachTooltip(row, cat.label, ("%d of %d known.%s Click to %s."):format(cat.known, cat.total,
                cat.learnable > 0 and (" %d could be learned now."):format(cat.learnable) or "",
                r.collapsed and "expand" or "collapse"), "ANCHOR_RIGHT")
        else
            local e = r.entry
            row:SetHeight(ROW_H)
            row.icon:SetTexture(SpellIcon(e.spell))
            row.icon:SetAlpha(e.known and 1 or 0.45)
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            row.name:SetFontObject(GameFontHighlightSmall)
            row.name:SetText(e.name)
            if e.known then
                local c = DIFF[e.colour] or DIFF.grey
                row.name:SetTextColor(Paper(c[1], c[2], c[3]))
                if e.craftable > 0 then
                    row.right:SetText(("%s×%d|r"):format(Hex(pr, pg, pb), e.craftable))
                else
                    row.right:SetText("")
                end
            else
                row.name:SetTextColor(sr, sg, sb)
                local tint = SOURCE_TINT[e.sourceWord] or { 0.8, 0.8, 0.8 }
                if db.ShowSourceColumn then
                    row.right:SetText(("%s%s|r %s%d|r"):format(Hex(tint[1] * 0.85, tint[2] * 0.85, tint[3] * 0.85), e.sourceWord, Hex(fr, fg, fb), e.learnSkill))
                else
                    row.right:SetText(("%s%d|r"):format(Hex(fr, fg, fb), e.learnSkill))
                end
            end
            if e.learnable then
                row.dot:SetVertexColor(GOOD[1], GOOD[2], GOOD[3], 1)
                row.dot:Show()
            end
            if e.spell == selectedSpell then
                row.bar:SetVertexColor(ar, ag, ab, OnPaper() and 0.25 or 0.18)
                row.bar:Show()
            end
            local spell = e.spell
            row:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    if ChatEdit_InsertLink and pcall(ChatEdit_InsertLink, GetSpellLink and GetSpellLink(spell) or e.name) then return end
                end
                SelectRecipe(spell)
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if not pcall(GameTooltip.SetHyperlink, GameTooltip, "enchant:" .. spell) then
                    GameTooltip:AddLine(e.name)
                end
                if not e.known then
                    GameTooltip:AddLine(("Not known — %s, %d skill."):format(e.sourceWord, e.learnSkill), 0.7, 0.7, 0.7)
                    if e.learnable then GameTooltip:AddLine("You could learn this now.", GOOD[1], GOOD[2], GOOD[3]) end
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        row:Show()
        y = y - row:GetHeight()
    end
    for i = n + 1, #navRows do navRows[i]:Hide() end
    navChild:SetHeight(-y + 4)
end

-- ---------------------------------------------------------------------------
-- The briefing
-- ---------------------------------------------------------------------------

local blocks = { text = {}, icon = {}, button = {}, hover = {} }
local used = { text = 0, icon = 0, button = 0, hover = 0 }
local dy

local function ReleaseBlocks()
    for kind, list in pairs(blocks) do
        for i = 1, #list do list[i]:Hide() end
        used[kind] = 0
    end
end

local function DText()
    used.text = used.text + 1
    local fs = blocks.text[used.text]
    if not fs then
        fs = detailChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        blocks.text[used.text] = fs
    end
    fs:ClearAllPoints()
    fs:SetFontObject(GameFontHighlightSmall)
    fs:SetJustifyH("LEFT")
    fs:SetAlpha(1)
    fs:Show()
    return fs
end

local function DIcon()
    used.icon = used.icon + 1
    local t = blocks.icon[used.icon]
    if not t then
        t = detailChild:CreateTexture(nil, "ARTWORK")
        blocks.icon[used.icon] = t
    end
    t:ClearAllPoints()
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t:SetAlpha(1)
    t:Show()
    return t
end

local function DButton(text, width, onClick, title, tooltip)
    used.button = used.button + 1
    local b = blocks.button[used.button]
    if not b then
        b = CreateFrame("Button", nil, detailChild, "UIPanelButtonTemplate")
        b:SetHeight(18)
        blocks.button[used.button] = b
    end
    b:ClearAllPoints()
    b:SetWidth(width)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
    if title then AttachTooltip(b, title, tooltip, "ANCHOR_RIGHT") end
    b:Show()
    return b
end

local function DHover()
    used.hover = used.hover + 1
    local h = blocks.hover[used.hover]
    if not h then
        h = CreateFrame("Button", nil, detailChild)
        blocks.hover[used.hover] = h
    end
    h:ClearAllPoints()
    h:SetScript("OnClick", nil)
    h:SetScript("OnEnter", nil); h:SetScript("OnLeave", nil)
    h:Show()
    return h
end

local function Line(text, opts)
    opts = opts or {}
    local fs = DText()
    fs:SetPoint("TOPLEFT", detailChild, "TOPLEFT", opts.indent or 0, dy)
    fs:SetPoint("RIGHT", detailChild, "RIGHT", -(opts.rightPad or 0), 0)
    if opts.font then fs:SetFontObject(opts.font) end
    local r, g, b
    if opts.color then r, g, b = opts.color[1], opts.color[2], opts.color[3] else r, g, b = Ink(opts.ink or "primary") end
    fs:SetTextColor(Paper(r, g, b))
    fs:SetText(text)
    local h = fs:GetStringHeight()
    if not h or h < 12 then h = 12 end
    dy = dy - h - (opts.gap or 3)
    return fs
end

local function Gap(n) dy = dy - (n or 8) end

local function Heading(text)
    Gap(6)
    local fs = Line(text:upper(), { font = GameFontNormalSmall, ink = "title", gap = 4 })
    return fs
end

-- The recipe's own tooltip, embedded: the client renders the effect text,
-- the reagent list and the requirements exactly as the craft window would
local recipeTip
local function EnsureRecipeTip()
    if recipeTip then return recipeTip end
    recipeTip = CreateFrame("GameTooltip", "CommanderFormularyRecipeTip", detailChild, "GameTooltipTemplate")
    -- The template puts tooltips on the TOOLTIP strata, above everything and
    -- outside the scroll frame's clip; this one is part of the page
    recipeTip:SetFrameStrata("HIGH")
    recipeTip:SetFrameLevel((detailChild:GetFrameLevel() or 1) + 2)
    if recipeTip.SetClampedToScreen then recipeTip:SetClampedToScreen(false) end
    return recipeTip
end

local function PaintRecipeTip(spell)
    local tip = EnsureRecipeTip()
    tip:ClearAllPoints()
    tip:SetOwner(detailChild, "ANCHOR_NONE")
    tip:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, dy)
    local ok = pcall(tip.SetHyperlink, tip, "enchant:" .. spell)
    if not ok then
        tip:Hide()
        return false
    end
    tip:Show()
    local h = tip:GetHeight()
    if not h or h < 20 then
        -- Not laid out yet on the frame it was shown: paint again next frame
        h = 20
        if not frame._tipRepaint then
            frame._tipRepaint = true
            C_Timer.After(0, function()
                frame._tipRepaint = nil
                if frame:IsShown() then Repaint() end
            end)
        end
    end
    dy = dy - h - 4
    return true
end

local function PaintReagents(entry)
    Heading("Reagents")
    local pr, pg, pb = Ink("primary")
    local fr, fg, fb = Ink("faint")
    for _, line in ipairs(entry.reagentLines) do
        local rowY = dy
        local icon = DIcon()
        icon:SetSize(16, 16)
        icon:SetTexture(ItemIcon(line.id))
        icon:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, dy)
        local ok = line.reachable >= line.per
        local right = (ok and Hex(GOOD[1], GOOD[2], GOOD[3]) or Hex(BAD[1], BAD[2], BAD[3])) .. line.have .. "|r"
        if db.CountBank and line.bank > 0 then right = right .. Hex(fr, fg, fb) .. (" +%d bank"):format(line.bank) .. "|r" end
        Line(("%s  %s×%d|r"):format(ItemName(line.id), Hex(fr, fg, fb), line.per), { indent = 24, rightPad = 90, gap = 4 })
        local rfs = DText()
        rfs:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", -4, rowY)
        rfs:SetJustifyH("RIGHT")
        rfs:SetTextColor(pr, pg, pb)
        rfs:SetText(right)
        if rowY - dy < 18 then dy = rowY - 18 end
        local hover = DHover()
        hover:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, rowY)
        hover:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, rowY)
        hover:SetHeight(rowY - dy)
        local id = line.id
        hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id) then GameTooltip:AddLine(ItemName(id)) end
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local n = entry.craftable
    Line(n > 0 and ("%sYou can make this %d time%s from what you hold.|r"):format(Hex(GOOD[1], GOOD[2], GOOD[3]), n, n == 1 and "" or "s")
        or (Hex(fr, fg, fb) .. "You are short of a reagent.|r"), { indent = 2, gap = 2 })
end

local function GoButton(place, title, rowY)
    if not place.x then return end
    local b = DButton("Go", 40, function() SetWaypoint(place, title) end, "Waypoint",
        TomTom and "Sets a TomTom waypoint." or "Prints the coordinates to chat (TomTom is not installed).")
    b:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", -2, rowY + 1)
end

local function PaintHowToLearn(entry)
    Heading(entry.known and "Where it came from" or "How to learn it")
    local lines = M.HowToLearn(Data(), entry, world)
    local sr, sg, sb = Ink("secondary")
    if #lines == 0 then
        Line("No source on record.", { ink = "faint" })
    end
    for _, l in ipairs(lines) do
        local rowY = dy
        if l.kind == "trainer" then
            Line(l.text, { indent = 2 })
            if not entry.known and entry.learnable == "trainer" then
                Line(Hex(GOOD[1], GOOD[2], GOOD[3]) .. "You have the skill — any trainer will teach it now." .. "|r", { indent = 12 })
            end
            if l.outland then
                for _, t in ipairs(Data().trainers) do
                    if t.outland and (not t.faction or not world.faction or t.faction == world.faction) then
                        local ty = dy
                        Line(("%s — %s (%.1f, %.1f)"):format(t.name, t.zone, t.x, t.y), { indent = 14, ink = "secondary", rightPad = 46 })
                        GoButton(t, t.name, ty)
                    end
                end
            end
        elseif l.kind == "formula" then
            local iconTex = DIcon()
            iconTex:SetSize(16, 16)
            iconTex:SetTexture(ItemIcon(l.item))
            iconTex:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, dy)
            local colour = l.held and GOOD or nil
            Line(l.text, { indent = 24, color = colour })
            if l.held then
                Line("Right-click it to learn the recipe" .. (l.skill > world.rank and (" once your skill reaches %d."):format(l.skill) or "."), { indent = 24, ink = "secondary" })
            end
            local hover = DHover()
            hover:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, rowY)
            hover:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, rowY)
            hover:SetHeight(rowY - dy)
            local item = l.item
            hover:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item) then GameTooltip:AddLine(ItemName(item)) end
                GameTooltip:Show()
            end)
            hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        elseif l.kind == "rep" then
            Line(l.text, { indent = 24, color = l.short and BAD or WARN })
        elseif l.kind == "vendor" then
            local colour = (not l.usable) and { sr * 0.8, sg * 0.8, sb * 0.8 } or nil
            Line(("Sold by %s%s"):format(l.text, l.usable and "" or (" — " .. (l.why or "not for you"))), { indent = 24, color = colour, rightPad = 46 })
            GoButton(l.place, l.place.name, rowY)
        elseif l.kind == "drop" then
            Line("Drops from " .. l.text, { indent = 24, rightPad = 46 })
            GoButton(l.place, l.place.name, rowY)
        elseif l.kind == "zone" then
            Line("Drops in " .. l.text, { indent = 24 })
        elseif l.kind == "world" then
            Line(l.text, { indent = 24 })
        elseif l.kind == "object" then
            Line("From " .. l.text, { indent = 24 })
        elseif l.kind == "container" then
            Line(l.text, { indent = 24 })
        elseif l.kind == "quest" then
            Line(l.text, { indent = 24 })
        elseif l.kind == "note" then
            Line(l.text, { indent = 24, ink = "secondary" })
        end
    end
end

local function PaintDetail()
    ReleaseBlocks()
    if recipeTip then recipeTip:Hide() end
    if craftHolder then craftHolder:Hide() end
    if openHolder then openHolder:Hide() end
    dy = -4
    -- A trainer selected from the foot of the navigator
    if type(selectedSpell) == "string" then
        local npc = tonumber(selectedSpell:match("^trainer:(%d+)$"))
        for _, t in ipairs(Data().trainers) do
            if t.npc == npc then
                local icon = DIcon()
                icon:SetSize(36, 36)
                icon:SetTexture(Data().icon)
                icon:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, dy)
                Line(t.name, { indent = 46, font = GameFontNormalLarge, ink = "title", gap = 1 })
                Line(("%s trainer%s"):format(Data().name, t.outland and " — teaches Master" or " — up to Artisan"), { indent = 46, ink = "secondary" })
                if dy > -44 then dy = -44 end
                Gap(6)
                local rowY = dy
                Line(("%s (%.1f, %.1f)"):format(t.zone, t.x, t.y), { indent = 2, rightPad = 46 })
                GoButton(t, t.name, rowY)
                -- What this trainer would teach you right now
                local teachable = {}
                for _, e in pairs(view.entries) do
                    if e.learnable == "trainer" and (not e.rec.trainer.outland or t.outland) then teachable[#teachable + 1] = e end
                end
                table.sort(teachable, function(a, b) return a.learnSkill < b.learnSkill end)
                if #teachable > 0 then
                    Heading("Would teach you now")
                    for _, e in ipairs(teachable) do
                        local ey = dy
                        local ic = DIcon()
                        ic:SetSize(16, 16)
                        ic:SetTexture(SpellIcon(e.spell))
                        ic:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, dy)
                        Line(("%s  %s%d skill%s|r"):format(e.name, Hex(Ink("faint")), e.learnSkill,
                            e.rec.trainer.cost > 0 and (", " .. M.FormatMoney(e.rec.trainer.cost)) or ""), { indent = 24 })
                        local hover = DHover()
                        hover:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, ey)
                        hover:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, ey)
                        hover:SetHeight(ey - dy)
                        local spell = e.spell
                        hover:SetScript("OnClick", function() SelectRecipe(spell) end)
                    end
                end
                detailChild:SetHeight(-dy + 8)
                return
            end
        end
    end
    local entry = view and selectedSpell and view.entries[selectedSpell]
    if not entry then
        Line(view and view.hasProfession and "Pick a recipe on the left." or "Learn Enchanting from a trainer in any capital city, then come back here.", { ink = "secondary" })
        detailChild:SetHeight(-dy + 8)
        return
    end
    local rec = entry.rec

    -- Title block: icon, name, category, colour
    local icon = DIcon()
    icon:SetSize(36, 36)
    icon:SetTexture(SpellIcon(rec.spell))
    icon:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, dy)
    local titleColour = entry.known and (DIFF[entry.colour] or DIFF.grey) or nil
    Line(entry.name, { indent = 46, font = GameFontNormalLarge, color = titleColour, ink = "title", gap = 1 })
    local cat = view.byKey[entry.category]
    local sub
    if entry.known then
        sub = ("%s · %s at your skill · yellow %d, green %d, grey %d"):format(cat and cat.label or "", entry.colour, rec.yellow, math.floor((rec.yellow + rec.grey) / 2), rec.grey)
    else
        sub = ("%s · not known · learned at %d skill · %s"):format(cat and cat.label or "", entry.learnSkill, entry.sourceWord)
    end
    Line(sub, { indent = 46, ink = "secondary" })
    if dy > -44 then dy = -44 end
    -- On the leveling route? Commander_Tradecraft says so when it is loaded
    if CommanderTradecraft_Plan then
        local plan = CommanderTradecraft_Plan()
        if plan and plan.steps then
            for _, step in ipairs(plan.steps) do
                if step.kind == "craft" and step.spell == rec.spell then
                    local state = step.status == "current" and "the step you are on" or step.status == "done" and "a step behind you" or "a step ahead"
                    Line(("%sOn the Tradecraft leveling route:|r %d – %d, %s."):format(Hex(Ink("strong")), step.from, step.to, state), { indent = 46, ink = "secondary" })
                    break
                end
            end
        end
    end
    if entry.learnable then
        local why = ({ trainer = "Your trainer will teach this now.", held = "The formula is in your bags — right-click it.",
            ["held-soon"] = "The formula is in your bags; it needs more skill.", vendor = "A vendor you can use sells the formula.",
            bank = "The formula is in your bank." })[entry.learnable]
        Line(Hex(GOOD[1], GOOD[2], GOOD[3]) .. why .. "|r", { indent = 46, gap = 4 })
    end
    Gap(4)

    -- The client's tooltip for the recipe (effect text and requirements)
    PaintRecipeTip(rec.spell)

    PaintReagents(entry)
    PaintHowToLearn(entry)

    if rec.creates then
        Heading("Makes")
        local rowY = dy
        local mk = DIcon()
        mk:SetSize(16, 16)
        mk:SetTexture(ItemIcon(rec.creates))
        mk:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 2, dy)
        Line(ItemName(rec.creates), { indent = 24 })
        local hover = DHover()
        hover:SetPoint("TOPLEFT", detailChild, "TOPLEFT", 0, rowY)
        hover:SetPoint("TOPRIGHT", detailChild, "TOPRIGHT", 0, rowY)
        hover:SetHeight(rowY - dy)
        local item = rec.creates
        hover:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. item) then GameTooltip:AddLine(ItemName(item)) end
            GameTooltip:Show()
        end)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    detailChild:SetHeight(-dy + 8)
end

-- ---------------------------------------------------------------------------
-- Header and actions
-- ---------------------------------------------------------------------------

local function PaintHeader()
    local pr, pg, pb = Ink("primary")
    local fr, fg, fb = Ink("faint")
    local data = Data()
    if not view or not view.hasProfession then
        frame.rankFS:SetText(Hex(fr, fg, fb) .. data.name .. " — not learned|r")
        frame.progress:SetWidth(1)
        frame.countFS:SetText("")
        return
    end
    frame.rankFS:SetText(("%s%s|r %s%d / %d|r"):format(Hex(pr, pg, pb), data.name, Hex(fr, fg, fb), view.rank, view.maxRank))
    local ar, ag, ab = Accent()
    frame.progress:SetVertexColor(ar, ag, ab, 0.9)
    frame.progress:SetWidth(math.max(1, frame.track:GetWidth() * (view.rank / 375)))
    local nextRank, trainable = M.NextRank(data, view)
    local rankNote = ""
    if nextRank and trainable then
        rankNote = ("  %s%s trainable|r"):format(Hex(GOOD[1], GOOD[2], GOOD[3]), nextRank.name)
    end
    frame.countFS:SetText(("%s%d|r %s/ %d known|r%s%s"):format(Hex(pr, pg, pb), view.known, Hex(fr, fg, fb), view.total,
        view.learnable > 0 and ("  %s+%d learnable now|r"):format(Hex(GOOD[1], GOOD[2], GOOD[3]), view.learnable) or "", rankNote))
end

local function PaintActions()
    local entry = view and selectedSpell and view.entries[selectedSpell]
    local actions = frame.actions
    local x = 0
    if entry and entry.known and not InCombat() then
        local holder = EnsureCraftButton(actions)
        if holder and SetCraftMacro(entry) then
            holder:ClearAllPoints()
            holder:SetPoint("LEFT", actions, "LEFT", x, 0)
            holder:Show()
            x = x + 94
        end
    end
    frame.gearCheck:SetChecked(db.AutoTargetGear and true or false)
    frame.gearCheck:ClearAllPoints()
    frame.gearCheck:SetPoint("LEFT", actions, "LEFT", x, 0)
    frame.gearCheck:SetShown(entry ~= nil and entry.known and entry.rec.enchant ~= nil)
    local sr, sg, sb = Ink("secondary")
    frame.craftNote:SetTextColor(sr, sg, sb)
    if entry and entry.known then
        frame.craftNote:SetText(entry.rec.enchant and (db.AutoTargetGear and "Casts on the piece you are wearing." or "Casts, then you click the piece to enchant.")
            or "Makes one.")
    else
        frame.craftNote:SetText("")
    end
    if not InCombat() and not craftOpen and not char.scanned then
        local oh = EnsureOpenButton(actions)
        if oh then
            oh:ClearAllPoints()
            oh:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
            oh:Show()
        end
    end
end

Repaint = function()
    if not (frame and frame:IsShown() and view) then return end
    ApplyFraming()
    rows = M.Rows(view, { filter = db.Filter, search = searchText, sort = db.Sort, collapsed = char.collapsed }, world)
    if searchText == "" and (db.Filter or "ALL") == "ALL" then
        for _, r in ipairs(TrainerRows()) do rows[#rows + 1] = r end
    end
    -- The filter bar
    for key, button in pairs(frame.filters) do
        local on = (db.Filter or "ALL") == key
        local fs = button:GetFontString()
        if fs then
            if on then fs:SetTextColor(Ink("strong")) else fs:SetTextColor(Ink("secondary")) end
        end
        local ar, ag, ab = Accent()
        button.underline:SetVertexColor(ar, ag, ab, on and 0.9 or 0)
    end
    PaintHeader()
    PaintNav()
    PaintDetail()
    PaintActions()
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local FILTERS = {
    { key = "ALL", label = "All", tooltip = "Every recipe the profession has." },
    { key = "KNOWN", label = "Known", tooltip = "The ones you can cast, coloured by difficulty." },
    { key = "UNKNOWN", label = "Unknown", tooltip = "The ones you cannot yet, with where they come from." },
    { key = "LEARNABLE", label = "Learnable", tooltip = "The ones you could learn right now: a trainer at your skill, a formula in your bags or bank, or a vendor you can use." },
}

local function SavePosition()
    local point, _, _, x, y = frame:GetPoint(1)
    if point then char.pos = { point = point, x = x, y = y } end
end

local function ApplyPosition()
    frame:ClearAllPoints()
    local p = char.pos
    if p and p.point then
        frame:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    end
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "CommanderFormularyFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Formulary") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderFormularyFrame") end

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing() SavePosition() end)

    -- Toolbar: filters, search, sort, the rank
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
    for _, spec in ipairs(FILTERS) do
        local button = CreateFrame("Button", nil, toolbar)
        button:SetSize(64, TOOLBAR_H)
        button:SetNormalFontObject(GameFontDisableSmall)
        button:SetHighlightFontObject(GameFontHighlightSmall)
        button:SetText(spec.label)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 2, 0) else button:SetPoint("LEFT", toolbar, "LEFT", 0, 0) end
        button.underline = Quad(button, "ARTWORK")
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 2)
        button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 2)
        local key = spec.key
        button:SetScript("OnClick", function()
            db.Filter = key
            Repaint()
        end)
        AttachTooltip(button, spec.label, spec.tooltip, "ANCHOR_BOTTOM")
        frame.filters[key] = button
        previous = button
    end

    frame.searchBox = CreateFrame("EditBox", "CommanderFormularySearchBox", toolbar, "InputBoxTemplate")
    frame.searchBox:SetSize(150, 20)
    frame.searchBox:SetPoint("LEFT", previous, "RIGHT", 14, 0)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetMaxLetters(60)
    frame.searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        searchText = self:GetText() or ""
        Repaint()
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        searchText = ""
        self:ClearFocus()
        Repaint()
    end)
    frame.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local ghost = frame.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ghost:SetPoint("LEFT", frame.searchBox, "LEFT", 4, 0)
    ghost:SetText("Search recipes")
    frame.searchBox:HookScript("OnTextChanged", function(self) ghost:SetShown((self:GetText() or "") == "") end)
    AttachTooltip(frame.searchBox, "Search", "Matches a recipe's name, its reagents, the vendor or creature it comes from, the zone, and the reputation it needs.", "ANCHOR_BOTTOM")

    frame.sortDrop = CreateFrame("Frame", "CommanderFormularySortDrop", toolbar, "UIDropDownMenuTemplate")
    frame.sortDrop:SetPoint("LEFT", frame.searchBox, "RIGHT", -6, -2)
    local SORTS = { { text = "By skill", value = "SKILL" }, { text = "By name", value = "NAME" } }
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(frame.sortDrop, function()
            for _, option in ipairs(SORTS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.text
                info.value = option.value
                info.checked = (db.Sort or "SKILL") == option.value
                info.func = function()
                    db.Sort = option.value
                    UIDropDownMenu_SetSelectedValue(frame.sortDrop, option.value)
                    UIDropDownMenu_SetText(frame.sortDrop, option.text)
                    Repaint()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetWidth(frame.sortDrop, 90)
        for _, option in ipairs(SORTS) do
            if option.value == (db.Sort or "SKILL") then UIDropDownMenu_SetText(frame.sortDrop, option.text) end
        end
    end

    -- The rank and the count, on the right of the toolbar
    frame.rankFS = toolbar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.rankFS:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -2, -1)
    frame.rankFS:SetJustifyH("RIGHT")
    frame.track = Quad(toolbar, "ARTWORK")
    frame.track:SetHeight(3)
    frame.track:SetWidth(180)
    frame.track:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", -2, 3)
    frame.track:SetVertexColor(1, 1, 1, 0.12)
    frame.progress = Quad(toolbar, "OVERLAY")
    frame.progress:SetHeight(3)
    frame.progress:SetPoint("BOTTOMLEFT", frame.track, "BOTTOMLEFT", 0, 0)
    frame.countFS = toolbar:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.countFS:SetPoint("RIGHT", frame.track, "LEFT", -12, 0)
    frame.countFS:SetJustifyH("RIGHT")

    frame.titleAccent = Quad(frame, "ARTWORK")
    frame.titleAccent:SetHeight(1)
    frame.titleAccent:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    frame.titleAccent:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)

    -- The navigator
    local navPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.navPane = navPane
    navPane:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    navPane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + 4)
    navPane:SetWidth(NAV_W)
    if navPane.SetBackdrop then navPane:SetBackdrop(INSET_BACKDROP) end

    navScroll = CreateFrame("ScrollFrame", "CommanderFormularyNavScroll", navPane, "UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT", navPane, "TOPLEFT", 6, -6)
    navScroll:SetPoint("BOTTOMRIGHT", navPane, "BOTTOMRIGHT", -16, 6)
    navScroll:EnableMouseWheel(true)
    navScroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 44
        local limit = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)
    navChild = CreateFrame("Frame", nil, navScroll)
    navChild:SetSize(NAV_W - 34, 1)
    navScroll:SetScrollChild(navChild)
    navScroll:SetScript("OnSizeChanged", function(_, width) navChild:SetWidth(width) end)

    -- The briefing
    local detailPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.detailPane = detailPane
    detailPane:SetPoint("TOPLEFT", navPane, "TOPRIGHT", 8, 0)
    detailPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 4 + ACTIONS_H + 4)
    if detailPane.SetBackdrop then detailPane:SetBackdrop(INSET_BACKDROP) end

    detailScroll = CreateFrame("ScrollFrame", "CommanderFormularyDetailScroll", detailPane, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 8, -8)
    detailScroll:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -18, 8)
    detailScroll:EnableMouseWheel(true)
    detailScroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 44
        local limit = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)
    detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(FRAME_W - NAV_W - 60, 1)
    detailScroll:SetScrollChild(detailChild)
    detailScroll:SetScript("OnSizeChanged", function(_, width) detailChild:SetWidth(width) end)

    Commander.UI.SlimScrollBar("CommanderFormularyNavScroll", 2, 2)
    Commander.UI.SlimScrollBar("CommanderFormularyDetailScroll", 2, 2)

    -- Actions under the briefing: Craft, its target rule, and a way to read
    -- what you know before the craft window has ever opened
    local actions = CreateFrame("Frame", nil, frame)
    frame.actions = actions
    actions:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -4)
    actions:SetPoint("TOPRIGHT", detailPane, "BOTTOMRIGHT", 0, -4)
    actions:SetHeight(ACTIONS_H)

    frame.gearCheck = CreateFrame("CheckButton", "CommanderFormularyGearCheck", actions, "UICheckButtonTemplate")
    frame.gearCheck:SetSize(22, 22)
    -- The template's label is a named child on this client
    local label = frame.gearCheck.Text or _G["CommanderFormularyGearCheckText"]
    if label then
        label:SetText("on my gear")
        label:SetFontObject(GameFontHighlightSmall)
    end
    frame.gearCheck:SetScript("OnClick", function(self)
        db.AutoTargetGear = self:GetChecked() and true or false
        Repaint()
    end)
    AttachTooltip(frame.gearCheck, "Cast on my own gear", "Add a /use line so the enchant lands on the matching piece you are wearing, and answer the replace question. Off: the glowing cursor is yours to aim.", "ANCHOR_TOP")

    frame.craftNote = actions:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.craftNote:SetPoint("LEFT", actions, "LEFT", 190, 0)
    frame.craftNote:SetJustifyH("LEFT")

    ApplyFraming(true)
    ApplyPosition()
    frame:SetScript("OnShow", function() Rebuild() end)
    return frame
end

-- ---------------------------------------------------------------------------
-- The stock craft window
-- ---------------------------------------------------------------------------

local function TakingOver()
    return db and db.EnableFormulary and db.ReplaceCraftWindow
end

local craftHooked = false
local function PutAwayCraftFrame()
    if CraftFrame and CraftFrame.IsShown and CraftFrame:IsShown() then
        if HideUIPanel then HideUIPanel(CraftFrame) else CraftFrame:Hide() end
    end
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

function CommanderFormulary_Show()
    if not loaded then return end
    if not db.EnableFormulary then
        Announce("the Formulary is disabled in its settings")
        return
    end
    EnsureFrame()
    selectedSpell = selectedSpell or char.selected
    if frame:IsShown() then Rebuild() else frame:Show() end
end

function CommanderFormulary_Hide()
    if frame then frame:Hide() end
end

function CommanderFormulary_Toggle()
    if frame and frame:IsShown() then CommanderFormulary_Hide() else CommanderFormulary_Show() end
end

function CommanderFormulary_Search(text)
    CommanderFormulary_Show()
    if not frame then return end
    text = text or ""
    frame.searchBox:SetText(text)
    searchText = text
    if text == "" then frame.searchBox:SetFocus() end
    Repaint()
end

function CommanderFormulary_Select(spell)
    CommanderFormulary_Show()
    if frame then SelectRecipe(spell) end
end

function CommanderFormulary_ResetChar()
    if not loaded then return end
    char.known = {}
    char.scanned = nil
    Announce("recipe memory forgotten for this character — open your Enchanting window to read it again")
    if frame and frame:IsShown() then Rebuild() end
end

function CommanderFormulary_Status()
    if not loaded then return end
    world = BuildWorld()
    local v = M.Build(Data(), world, { bank = db.CountBank })
    Announce(("%s %d / %d — %d of %d recipes known, %d learnable now"):format(Data().name, v.rank, v.maxRank, v.known, v.total, v.learnable))
    local bySpellbook, byMemory = 0, 0
    for _, rec in ipairs(Data().recipes) do
        if (IsSpellKnown and IsSpellKnown(rec.spell)) or (IsPlayerSpell and IsPlayerSpell(rec.spell)) then bySpellbook = bySpellbook + 1 end
        if char.known[rec.spell] then byMemory = byMemory + 1 end
    end
    Announce(("known by the spellbook: %d, seen in the craft window: %d"):format(bySpellbook, byMemory))
end

function CommanderFormulary_View()
    return view
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")

local WATCHED = {
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_OPENED",
    "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE",
    "SPELLS_CHANGED", "NEW_RECIPE_LEARNED",
    "UPDATE_FACTION", "UNIT_INVENTORY_CHANGED",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "GET_ITEM_INFO_RECEIVED",
}

events:SetScript("OnEvent", function(_, event, arg1)
    if not loaded then return end
    if event == "CRAFT_SHOW" then
        craftOpen = true
        local ours = CraftWindowIsOurs()
        if ours then
            ScanCraftWindow()
            if TakingOver() then
                -- Blizzard_CraftUI loads on demand from this same event and
                -- shows itself in its own handler, which ran before ours
                PutAwayCraftFrame()
                if CraftFrame and not craftHooked and CraftFrame.HookScript then
                    craftHooked = true
                    CraftFrame:HookScript("OnShow", function(self)
                        if TakingOver() and CraftWindowIsOurs() then
                            ScanCraftWindow()
                            if HideUIPanel then HideUIPanel(self) else self:Hide() end
                            CommanderFormulary_Show()
                        end
                    end)
                end
                CommanderFormulary_Show()
                return
            end
        end
    elseif event == "CRAFT_CLOSE" then
        craftOpen = false
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
        return
    end
    ScheduleRefresh()
end)

function CommanderFormulary_OnLogin()
    db = CommanderFormularyDB
    char = CommanderFormularyChar
    loaded = true
    for _, e in ipairs(WATCHED) do
        local ok = pcall(events.RegisterEvent, events, e)
        if not ok then print("Commander Formulary: this client has no event " .. e .. " — skipped") end
    end
    Commander.AddListener(Events.UPDATE, function()
        if frame and frame:IsShown() then
            ApplyFraming(true)
            Rebuild()
        end
    end)
end

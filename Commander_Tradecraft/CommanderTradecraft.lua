-- Commander Tradecraft: the guide window, the route and shopping ledger, the
-- Craft button, and the events that keep the plan honest.
--
-- The shape of it:
--   * `world` is a handful of readers over the client (skill line, known
--     recipes, item counts, faction, reputation). Everything the engine
--     needs, nothing it does not.
--   * `Rebuild` asks the engine for a fresh plan and repaints. It is
--     scheduled, not called, from events: a bag update fires in bursts and
--     the skill line changes a beat after the craft, so the plan is built
--     once per frame at most, from whatever the last event left behind.
--   * The guide window is a list of "lines" rebuilt on every repaint from
--     pooled widgets — a text, a reagent row, a row of buttons — laid out top
--     to bottom, and the frame takes the height that comes out. No line owns
--     a fixed position, which is what lets a buy step (vendors, coordinates,
--     a waypoint button) and a craft step (reagents, a craft button) share
--     one window without either leaving gaps in the other.
--   * The Craft button is a secure macro button running "/cast <recipe>"
--     and "/use <slot>": it casts the enchant and lands it on your own
--     bracers in one click, and the module answers the "replace the
--     enchant?" question — the three things you would otherwise do a
--     hundred times between 2 and 90. DoCraft is protected on this client,
--     so there is no insecure way to craft (DECISIONS D7).
--
-- Enchanting on this client goes through the CRAFT frame and its API
-- (GetNumCrafts / GetCraftInfo), which is only populated while the window
-- is open. Recipes seen there are remembered per character so the guide can
-- tell a formula you have learned from one you have not while the window is
-- closed; IsSpellKnown is asked first and the memory is the fallback
-- (ASSUMPTIONS.md A2).

local D = CommanderTradecraft_Data
local E = CommanderTradecraft_Engine
local Events = COMMANDER_TRADECRAFT_EVENTS

local db, char
local plan
local loaded = false

-- Key bindings (Bindings.xml)
BINDING_HEADER_COMMANDERTRADECRAFT = "Commander Tradecraft"
_G["BINDING_NAME_CLICK CommanderTradecraftCraftKey:LeftButton"] = "Craft the current step"
BINDING_NAME_COMMANDERTRADECRAFT_TOGGLE = "Show / hide the guide"
BINDING_NAME_COMMANDERTRADECRAFT_SHOP = "Open the shopping list"

local WIDTH = 300
local LINE = 14
local PAD = 6

-- Colours
local C = {
    title = { 1, 0.82, 0.15 },
    text = { 0.95, 0.95, 0.95 },
    dim = { 0.6, 0.6, 0.6 },
    good = { 0.3, 1, 0.4 },
    bad = { 1, 0.35, 0.3 },
    warn = { 1, 0.6, 0.2 },
    orange = { 1, 0.5, 0.25 },
    yellow = { 1, 1, 0 },
    green = { 0.25, 0.75, 0.25 },
    grey = { 0.5, 0.5, 0.5 },
}
local HEX = {
    good = "|cff4cff66", bad = "|cffff5a4c", warn = "|cffff9933", dim = "|cff999999",
    title = "|cffffd115", white = "|cffffffff", orange = "|cffff8040", yellow = "|cffffff00",
    green = "|cff40bf40", grey = "|cff808080",
}

-- ---------------------------------------------------------------------------
-- Client shims
-- ---------------------------------------------------------------------------

local GetItemInfo_ = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount_ = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemIcon_ = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local ContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local ContainerItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID

local function ItemName(id)
    local name = GetItemInfo_ and GetItemInfo_(id)
    if name then return name end
    local info = D.ITEMS[id]
    return info and info.name or ("item " .. tostring(id))
end

local function ItemIcon(id)
    local icon = GetItemIcon_ and GetItemIcon_(id)
    if icon then return icon end
    if GetItemInfo_ then
        local _, _, _, _, _, _, _, _, _, texture = GetItemInfo_(id)
        if texture then return texture end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function SpellName(spell)
    local name = GetSpellInfo and GetSpellInfo(spell)
    if name then return name end
    local rec = D.RECIPES[spell]
    return rec and rec.name or ("spell " .. tostring(spell))
end

local function SpellIcon(spell)
    local icon = GetSpellTexture and GetSpellTexture(spell)
    if icon then return icon end
    return "Interface\\Icons\\Trade_Engraving"
end

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Guide()
    local key = char and char.guide or "ENCHANTING"
    return D.GUIDES[key] or D.GUIDES.ENCHANTING
end

local function Profession()
    return D.PROFESSIONS[Guide().profession]
end

-- ---------------------------------------------------------------------------
-- The world, as the engine wants it
-- ---------------------------------------------------------------------------

-- The skill line: rank and max rank, 0/0 when the profession is not known.
-- Collapsed headers hide their lines from GetSkillLineInfo, so a miss is
-- retried once with every header expanded (the same thing Questie does) —
-- once per session, not once per bag update, for a character who simply
-- does not have the profession.
local expandTried = false
local function ReadSkill(prof)
    if not (GetNumSkillLines and GetSkillLineInfo) then return 0, 0 end
    local wanted = SpellName(prof.abilitySpell)
    local function scan()
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if not isHeader and name == wanted then
                return rank or 0, maxRank or 0
            end
        end
        return nil
    end
    local rank, maxRank = scan()
    if rank == nil and ExpandSkillHeader and not expandTried then
        expandTried = true
        ExpandSkillHeader(0)
        rank, maxRank = scan()
    end
    return rank or 0, maxRank or 0
end

-- The craft window, when it is open on our profession. CRAFT_SHOW and
-- CRAFT_CLOSE keep `craftOpen`; the frame's own IsShown is the belt to that
-- brace, because Blizzard_CraftUI is loaded on demand by the same event and
-- may not be there yet when our handler runs.
local craftIndexBySpell = {}   -- spell -> index in the open craft list
local craftNameToSpell          -- localised recipe name -> spell, built once
local craftOpen = false

local function CraftWindowIsOurs()
    local shown = craftOpen or (CraftFrame and CraftFrame.IsShown and CraftFrame:IsShown())
    if not shown then return false end
    if not GetCraftDisplaySkillLine then return true end
    -- Strict: a hunter's Beast Training uses the same frame and answers
    -- nil here, and the guide must not pop for it
    return GetCraftDisplaySkillLine() == SpellName(Profession().abilitySpell)
end

local function ScanCraftWindow()
    if not CraftWindowIsOurs() or not GetNumCrafts then return false end
    if not craftNameToSpell then
        craftNameToSpell = {}
        for spell in pairs(D.RECIPES) do
            craftNameToSpell[SpellName(spell)] = spell
        end
    end
    local seen = false
    craftIndexBySpell = {}
    for i = 1, GetNumCrafts() do
        local name, _, craftType = GetCraftInfo(i)
        if name and craftType ~= "header" then
            local spell = craftNameToSpell[name]
            if spell then
                craftIndexBySpell[spell] = i
                char.knownRecipes[spell] = true
                seen = true
            end
        end
    end
    return seen
end

local function KnownRecipe(spell)
    if IsSpellKnown and IsSpellKnown(spell) then return true end
    if IsPlayerSpell and IsPlayerSpell(spell) then return true end
    return char.knownRecipes[spell] == true
end

local function Count(item, includeBank)
    if not GetItemCount_ then return 0 end
    return GetItemCount_(item, includeBank and true or false) or 0
end

local function Faction()
    if UnitFactionGroup then
        local f = UnitFactionGroup("player")
        if f == "Alliance" or f == "Horde" then return f end
    end
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
    local prof = Profession()
    local rank, maxRank = ReadSkill(prof)
    return {
        rank = rank, maxRank = maxRank,
        known = KnownRecipe,
        count = Count,
        faction = Faction(),
        standing = Standing,
    }
end

-- ---------------------------------------------------------------------------
-- The plan
-- ---------------------------------------------------------------------------

local Repaint, PaintLedger -- forward
local lastCurrentKey, lastRank

local function Announce(text)
    print("|cff33ff99Commander Tradecraft|r: " .. text)
end

local function StepTitle(step)
    if step.kind == "craft" then return SpellName(step.spell) end
    return "Buy " .. ItemName(step.item)
end

local function Rebuild()
    if not loaded then return end
    -- The craft list is read here, a frame after the event that announced
    -- it, so it is populated by the time it is scanned
    if craftOpen then ScanCraftWindow() end
    local world = BuildWorld()
    plan = E.Build(Guide(), world, char, {
        margin = db.Margin,
        bank = db.CountBank,
    })

    -- A step finished since the last look: say so
    local key = plan.current and plan.current.key or "done"
    if lastCurrentKey and key ~= lastCurrentKey then
        local finished
        for _, step in ipairs(plan.steps) do
            if step.key == lastCurrentKey and step.status == "done" then finished = step end
        end
        if finished then
            if db.AnnounceSteps then
                if plan.current then
                    Announce(("%s done. Next: %s%s|r"):format(StepTitle(finished), HEX.white, StepTitle(plan.current)))
                elseif plan.finished then
                    Announce(("%s done — and that is %d. Well earned."):format(StepTitle(finished), plan.target))
                end
            end
            if db.StepSound and PlaySound and SOUNDKIT then
                pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
            end
        end
    end
    lastCurrentKey = key
    lastRank = plan.rank

    Repaint()
    PaintLedger()
end

-- Rebuild once per frame at most, whatever the events do
local pending = false
local function ScheduleRebuild()
    if pending or not loaded then return end
    pending = true
    C_Timer.After(0, function()
        pending = false
        Rebuild()
    end)
end

-- ---------------------------------------------------------------------------
-- Widgets: the guide window
-- ---------------------------------------------------------------------------

local guide = CreateFrame("Frame", "CommanderTradecraftGuide", UIParent)
guide:SetSize(WIDTH, 100)
guide:SetFrameStrata("MEDIUM")
guide:SetClampedToScreen(true)
guide:Hide()

-- Header: icon, name, rank, progress bar
local headerIcon = guide:CreateTexture(nil, "ARTWORK")
headerIcon:SetSize(18, 18)
headerIcon:SetPoint("TOPLEFT", guide, "TOPLEFT", 0, 0)
headerIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local headerName = guide:CreateFontString(nil, "OVERLAY")
headerName:SetFontObject(GameFontNormal)
headerName:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
headerName:SetTextColor(unpack(C.title))

local headerRank = guide:CreateFontString(nil, "OVERLAY")
headerRank:SetFontObject(GameFontNormal)
headerRank:SetPoint("TOPRIGHT", guide, "TOPRIGHT", -2, -2)
headerRank:SetJustifyH("RIGHT")

local bar = CreateFrame("StatusBar", nil, guide)
bar:SetPoint("TOPLEFT", headerIcon, "BOTTOMLEFT", 0, -4)
bar:SetPoint("RIGHT", guide, "RIGHT", -2, 0)
bar:SetHeight(6)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(1, 0.82, 0.15, 0.9)
bar.bg = bar:CreateTexture(nil, "BACKGROUND")
bar.bg:SetAllPoints()
bar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
bar.bg:SetVertexColor(0, 0, 0, 0.5)

-- Pools
local pools = { text = {}, icon = {}, button = {}, hover = {} }
local used = { text = 0, icon = 0, button = 0, hover = 0 }

local function ReleaseAll()
    for kind, list in pairs(pools) do
        for i = 1, #list do list[i]:Hide() end
        used[kind] = 0
    end
end

local function NewText()
    used.text = used.text + 1
    local fs = pools.text[used.text]
    if not fs then
        fs = guide:CreateFontString(nil, "OVERLAY")
        fs:SetFontObject(GameFontHighlightSmall)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        if fs.SetWordWrap then fs:SetWordWrap(true) end
        pools.text[used.text] = fs
    end
    fs:ClearAllPoints()
    fs:SetFontObject(GameFontHighlightSmall)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(unpack(C.text))
    fs:SetAlpha(1)
    fs:Show()
    return fs
end

local function NewIcon()
    used.icon = used.icon + 1
    local tex = pools.icon[used.icon]
    if not tex then
        tex = guide:CreateTexture(nil, "ARTWORK")
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        pools.icon[used.icon] = tex
    end
    tex:ClearAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tex:SetAlpha(1)
    tex:Show()
    return tex
end

local function AttachTooltip(widget, fn)
    widget:SetScript("OnEnter", function(self)
        if not fn then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        fn(GameTooltip)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function NewButton(text, width, onClick, tooltip)
    used.button = used.button + 1
    local b = pools.button[used.button]
    if not b then
        b = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate")
        b:SetHeight(20)
        pools.button[used.button] = b
    end
    b:ClearAllPoints()
    b:SetWidth(width)
    b:SetHeight(20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b:SetEnabled(true)
    AttachTooltip(b, tooltip)
    b:Show()
    return b
end

-- An invisible mouse surface over a row, for its tooltip
local function NewHover()
    used.hover = used.hover + 1
    local h = pools.hover[used.hover]
    if not h then
        h = CreateFrame("Button", nil, guide)
        pools.hover[used.hover] = h
    end
    h:ClearAllPoints()
    h:SetScript("OnClick", nil)
    h:Show()
    return h
end

-- A radio marker: the client's own two-state radio art
local RADIO = "Interface\\Buttons\\UI-RadioButton"
local function Radio(tex, checked)
    tex:SetTexture(RADIO)
    if checked then tex:SetTexCoord(0.25, 0.5, 0, 1) else tex:SetTexCoord(0, 0.25, 0, 1) end
end

-- Secure buttons. DoCraft is a protected function on this client (it threw
-- ADDON_ACTION_FORBIDDEN the first time it was pressed), and so is casting
-- by name, so both the Open button and the Craft button are
-- SecureActionButtons. Each is a protected frame that nothing may show,
-- hide or move in combat, so each sits inside a plain holder frame that is
-- the thing the layout shows, hides and anchors: hiding an ordinary parent
-- takes a protected child with it and is allowed at any time. Attributes
-- are only ever written out of combat.
--
-- The Craft button runs the macro enchanters have typed by hand since
-- vanilla: "/cast <recipe>" and then "/use <slot>" to land it on your own
-- gear, which does not even need the craft window open.
local OPEN_WIDTH, CRAFT_WIDTH = 130, 70
local secure = {}   -- key -> { holder, button }

local function EnsureSecure(key, width, text, tooltipFn)
    if secure[key] then return secure[key] end
    if InCombat() then return nil end
    local holder = CreateFrame("Frame", nil, guide)
    holder:SetSize(width, 20)
    local button = CreateFrame("Button", "CommanderTradecraft" .. key, holder,
        "SecureActionButtonTemplate, UIPanelButtonTemplate")
    button:SetAllPoints(holder)
    -- BOTH edges. SecureActionButton_OnClick acts on exactly one of them,
    -- the one the ActionButtonUseKeyDown CVar names (down, by default), and
    -- discards the other — so registering only "AnyUp" delivered a click
    -- the handler threw away, and the button did nothing. (In-game
    -- 2026-09-17; the suite's other secure buttons already knew.)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetText(text)
    AttachTooltip(button, tooltipFn)
    holder:Hide()
    secure[key] = { holder = holder, button = button }
    return secure[key]
end

local function EnsureOpenButton()
    local s = EnsureSecure("Open", OPEN_WIDTH, "Open " .. Profession().name, function(tip)
        tip:AddLine("Open " .. Profession().name)
        tip:AddLine("Casts the profession to open its window — handy for watching the list, though the Craft button does not need it open.", 1, 1, 1, true)
    end)
    if s and not s.ready then
        s.ready = true
        s.button:SetAttribute("type", "spell")
        s.button:SetAttribute("spell", SpellName(Profession().abilitySpell))
    end
    return s and s.holder
end

local craftTooltip -- set per paint

local function EnsureCraftButton()
    local s = EnsureSecure("Craft", CRAFT_WIDTH, "Craft", function(tip)
        if craftTooltip then craftTooltip(tip) end
    end)
    if s and not s.ready then
        s.ready = true
        s.button:SetAttribute("type", "macro")
        s.button:SetAttribute("macrotext", "")
    end
    return s and s.holder
end

-- Layout cursor
local y -- negative offset from the top of the content area
-- Set when a wrapped line could not report its height yet (a font string
-- on a frame that has never been shown may answer 0); the paint is redone
-- once the frame is on screen so nothing overlaps
local heightMissing = false

local function Line(text, opts)
    opts = opts or {}
    local fs = NewText()
    local indent = opts.indent or 0
    fs:SetPoint("TOPLEFT", guide, "TOPLEFT", indent, y)
    fs:SetPoint("RIGHT", guide, "RIGHT", -(opts.rightPad or 0), 0)
    if opts.font then fs:SetFontObject(opts.font) end
    if opts.color then fs:SetTextColor(unpack(opts.color)) end
    if opts.alpha then fs:SetAlpha(opts.alpha) end
    fs:SetText(text)
    local h = fs:GetStringHeight()
    if not h or h <= 0 then heightMissing = true end
    if not h or h < LINE then h = LINE end
    y = y - h - (opts.gap or 2)
    return fs
end

local function Gap(n) y = y - (n or PAD) end

-- A line with an icon on the left
local function IconLine(icon, text, opts)
    opts = opts or {}
    local size = opts.size or 16
    local tex = NewIcon()
    tex:SetSize(size, size)
    tex:SetTexture(icon)
    tex:SetPoint("TOPLEFT", guide, "TOPLEFT", opts.indent or 0, y)
    if opts.alpha then tex:SetAlpha(opts.alpha) end
    opts.indent = (opts.indent or 0) + size + 5
    local startY = y
    local fs = Line(text, opts)
    -- Never let the row be shorter than its icon
    if startY - y < size + 2 then y = startY - size - 2 end
    return fs, tex
end

-- One of a segment's two ways, as a clickable row: radio, label, and the
-- guide's note under it in grey
local function OptionRow(path, chosen, onClick)
    local rowY = y
    local mark = NewIcon()
    mark:SetSize(14, 14)
    Radio(mark, chosen)
    mark:SetPoint("TOPLEFT", guide, "TOPLEFT", 8, y - 1)
    Line((chosen and HEX.white or "") .. path.label .. (chosen and "|r" or ""), { indent = 26, color = chosen and C.text or C.dim, gap = 0 })
    if path.note then
        Line(HEX.dim .. path.note .. "|r", { indent = 26, gap = 3 })
    end
    local hover = NewHover()
    hover:SetPoint("TOPLEFT", guide, "TOPLEFT", 4, rowY)
    hover:SetPoint("RIGHT", guide, "RIGHT", 0, 0)
    hover:SetHeight(rowY - y)
    hover:SetScript("OnClick", onClick)
    AttachTooltip(hover, function(tip)
        tip:AddLine(path.label)
        tip:AddLine(chosen and "The way you are taking." or "Click to take this way instead.", 1, 1, 1, true)
    end)
end

-- Reagent row: icon, name, have / need on the right, tooltip on hover
local reagentRows = {}
local function ReagentRow(line, alpha)
    local have = line.reachable
    local ok = have >= line.need
    local right
    if line.need == math.huge then
        right = HEX.dim .. "—|r"
    else
        right = (ok and HEX.good or HEX.bad) .. have .. "|r" .. HEX.dim .. " / " .. line.need .. "|r"
    end
    local name = ItemName(line.id)
    local suffix = ""
    if db.CountBank and line.bank > 0 then
        suffix = HEX.dim .. ("  (%d in bank)"):format(line.bank) .. "|r"
    end
    local rowY = y
    IconLine(ItemIcon(line.id), name .. suffix, { indent = 8, rightPad = 70, alpha = alpha })
    local rfs = NewText()
    rfs:SetPoint("TOPRIGHT", guide, "TOPRIGHT", -2, rowY)
    rfs:SetJustifyH("RIGHT")
    rfs:SetText(right)
    if alpha then rfs:SetAlpha(alpha) end
    -- Hover anywhere on the row for the item tooltip
    local hover = NewHover()
    hover:SetPoint("TOPLEFT", guide, "TOPLEFT", 8, rowY + 1)
    hover:SetPoint("RIGHT", guide, "RIGHT", 0, 0)
    hover:SetHeight(rowY - y - 1)
    AttachTooltip(hover, function(tip)
        tip:SetHyperlink("item:" .. line.id)
    end)
end

-- A row of buttons, left to right
local function ButtonRow(defs)
    local x = 0
    local h = 0
    for _, def in ipairs(defs) do
        local b
        if def.secure then
            b = def.secure == "Craft" and EnsureCraftButton() or EnsureOpenButton()
            if b then
                b:ClearAllPoints()
                b:Show()
            end
        else
            b = NewButton(def.text, def.width, def.onClick, def.tooltip)
            if def.disabled then b:SetEnabled(false) end
        end
        if b then
            b:SetPoint("TOPLEFT", guide, "TOPLEFT", x, y)
            x = x + def.width + 4
            h = 20
        end
    end
    y = y - h - 4
end

-- ---------------------------------------------------------------------------
-- Waypoints
-- ---------------------------------------------------------------------------

local function SetWaypoint(place, title)
    local zone = place.zone
    local mapID = D.ZONES[zone]
    if db.UseWaypoints and TomTom and TomTom.AddWaypoint and mapID then
        local ok = pcall(TomTom.AddWaypoint, TomTom, mapID, place.x / 100, place.y / 100, {
            title = title or place.name,
            persistent = false, minimap = true, world = true, crazy = true,
        })
        if ok then
            Announce(("Waypoint set: %s — %s (%.1f, %.1f)"):format(place.name, zone, place.x, place.y))
            return
        end
    end
    Announce(("%s — %s, %s (%.1f, %.1f)"):format(place.name, place.where or "", zone, place.x, place.y))
end

-- ---------------------------------------------------------------------------
-- Crafting
-- ---------------------------------------------------------------------------

-- Bags: the first item matching an equip location
local function FindInBags(target)
    if not (ContainerNumSlots and ContainerItemID and GetItemInfo_) then return nil end
    local accepts = D.TARGET_ACCEPTS[target] or { [target] = true }
    for bag = 0, 4 do
        for slot = 1, (ContainerNumSlots(bag) or 0) do
            local id = ContainerItemID(bag, slot)
            if id then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo_(id)
                if equipLoc and accepts[equipLoc] then
                    return bag, slot
                end
            end
        end
    end
    return nil
end

-- The worn piece an enchant can land on. The off-hand slot is checked by
-- what is in it, not just that something is: a tome in the shield slot
-- is not a shield.
local function FindEquipped(target)
    local slots = D.TARGET_SLOTS[target]
    if not (slots and GetInventoryItemID) then return nil end
    local accepts = D.TARGET_ACCEPTS[target] or { [target] = true }
    for _, slot in ipairs(slots) do
        local id = GetInventoryItemID("player", slot)
        if id then
            local equipLoc = GetItemInfo_ and select(9, GetItemInfo_(id))
            -- An uncached item answers nil; trust the slot then
            if equipLoc == nil or accepts[equipLoc] then return slot end
        end
    end
    return nil
end

-- Whether the current enchant has something to land on, and where
local function TargetFor(recipe)
    if not recipe.target then return "none" end
    local slot = FindEquipped(recipe.target)
    if slot then return "equipped", slot end
    local bag, bagSlot = FindInBags(recipe.target)
    if bag then return "bags", bag, bagSlot end
    return nil
end

-- The macro the Craft button runs for a step. "/cast" by the recipe's
-- localised name; for an enchant, "/use <slot>" (worn) or "/use <bag> <slot>"
-- (bags) hands the glowing cursor its target on the same click, and
-- "/click StaticPopup1Button1" answers the replace-enchant question the
-- client raises synchronously inside that /use. ReplaceEnchant() is
-- protected on this client (in game 2026-09-17), so the answer has to come
-- from inside the secure macro; StaticPopup_OnClick returns at once when
-- the dialog is not shown, so the line is a no-op on a fresh piece.
local function CraftMacro(step)
    if not (step and step.kind == "craft") then return "" end
    local lines = { "/cast " .. SpellName(step.spell) }
    local recipe = step.recipe
    if recipe.target and db.AutoTargetGear then
        local where, a, b = TargetFor(recipe)
        if where == "equipped" then
            lines[#lines + 1] = "/use " .. a
        elseif where == "bags" then
            lines[#lines + 1] = "/use " .. a .. " " .. b
        end
        if where and db.AutoConfirmReplace then
            lines[#lines + 1] = "/click StaticPopup1Button1"
        end
    end
    return table.concat(lines, "\n")
end

-- The binding's target: a second secure button with the same macro, parked
-- off-screen and always shown, so "Craft the current step" works from a key
-- whether or not the guide window is on screen (Commander_Armory parks its
-- weapon-swap button the same way, for the same reason). Made once, out of
-- combat, at login or the first paint after.
local keyButton, keyMacro
local function EnsureKeyButton()
    if keyButton then return keyButton end
    if InCombat() then return nil end
    local host = CreateFrame("Frame", nil, UIParent)
    host:SetSize(1, 1)
    host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -512, -512)
    keyButton = CreateFrame("Button", "CommanderTradecraftCraftKey", host, "SecureActionButtonTemplate")
    keyButton:SetSize(1, 1)
    keyButton:SetPoint("CENTER", host, "CENTER", 0, 0)
    keyButton:EnableMouse(false)
    keyButton:RegisterForClicks("AnyDown", "AnyUp")
    keyButton:SetAttribute("type", "macro")
    keyButton:SetAttribute("macrotext", "")
    return keyButton
end

-- Written on every paint, out of combat only (attributes on a protected
-- frame), to the guide's button and the binding's. Returns false when it
-- could not be written.
local function SetCraftMacro(step)
    if InCombat() then return false end
    local text = CraftMacro(step)
    local s = secure.Craft
    if s and s.macro ~= text then
        s.macro = text
        s.button:SetAttribute("macrotext", text)
    end
    if EnsureKeyButton() and keyMacro ~= text then
        keyMacro = text
        keyButton:SetAttribute("macrotext", text)
    end
    return s ~= nil
end

-- A real macro, kept up to date with the button's text, for anyone who
-- would rather press a key: drag "Tradecraft" from the macro window to a
-- bar once and it follows the route from then on (the way RXP keeps its
-- targeting macro). Per character, written out of combat only, and only
-- when the text changes.
local MACRO_NAME = "Tradecraft"
local macroWarned = false
local lastMacroBody
-- The macro list is not there at PLAYER_LOGIN; UPDATE_MACROS (or entering
-- the world) says when it is. Writing before that failed silently.
local macrosReady = false

local function UpdateMacro(step)
    if not (db.KeepMacro and CreateMacro and EditMacro and GetMacroInfo) then return end
    if InCombat() or not macrosReady then return end
    local body = CraftMacro(step)
    if body == "" then
        body = "/run print('Commander Tradecraft: nothing to craft right now')"
    end
    local icon = step and step.kind == "craft" and SpellIcon(step.spell) or nil
    -- General tab, not character-specific: one macro, one bar slot, every
    -- character. (The first build made it per character; the character
    -- tab is where nobody looks.) A per-character one left over from that
    -- build is removed first — indices past the account block are the
    -- character block.
    local index = GetMacroIndexByName and GetMacroIndexByName(MACRO_NAME) or 0
    local accountSlots = MAX_ACCOUNT_MACROS or 120
    if index > accountSlots and DeleteMacro then
        pcall(DeleteMacro, index)
        index = GetMacroIndexByName(MACRO_NAME) or 0
    end
    if index == 0 or not GetMacroInfo(MACRO_NAME) then
        local account = GetNumMacros()
        if (account or 0) >= accountSlots then
            if not macroWarned then
                macroWarned = true
                Announce("your general macro slots are full, so the Tradecraft macro could not be made — the Craft button still works")
            end
            return
        end
        local ok, err = pcall(CreateMacro, MACRO_NAME, icon or "INV_Misc_QuestionMark", body)
        if ok then
            lastMacroBody = body
            Announce(("a macro called %s%s|r is kept up to date with the Craft button — it is on the General tab of the macro window (/macro); drag it to a bar and bind it, or bind 'Craft the current step' under Key Bindings"):format(HEX.white, MACRO_NAME))
        elseif not macroWarned then
            macroWarned = true
            Announce("could not create the Tradecraft macro: " .. tostring(err))
        end
        return
    end
    if body ~= lastMacroBody then
        local ok, err = pcall(EditMacro, MACRO_NAME, MACRO_NAME, icon, body)
        if ok then
            lastMacroBody = body
        elseif not macroWarned then
            macroWarned = true
            Announce("could not update the Tradecraft macro: " .. tostring(err))
        end
    end
end

-- /ctc craft: there is no insecure way to cast, so this can only say how
local function CraftCurrent()
    if not (plan and plan.current and plan.current.kind == "craft") then
        Announce("nothing to craft right now")
        return
    end
    local step = plan.current
    Announce(("crafting is a protected action — press the Craft button on the guide, or put this in a macro:\n%s"):format(
        CraftMacro(step):gsub("\n", "  ")))
end

-- ---------------------------------------------------------------------------
-- Painting the guide window
-- ---------------------------------------------------------------------------

local function ColourFor(colour)
    return C[colour] or C.text
end

local function RankText(plan_)
    return ("%s%d|r %s/ %d|r"):format(HEX.white, plan_.rank, HEX.dim, plan_.target)
end

local function PaintTrainBanner(p)
    local t = p.train
    if not t then return end
    local prof = p.profession
    local text
    if not p.hasProfession then
        text = ("%sLearn %s|r from any %s trainer — every capital city has one."):format(HEX.title, prof.name, prof.name)
        Line(text, { color = C.warn })
    else
        local rankName = t.rank.name
        if t.urgent then
            text = ("%sYou are at your cap (%d).|r Train %s %s (needs %d)."):format(HEX.bad, p.maxRank, rankName, prof.name, t.rank.at)
        else
            text = ("%sTrainer:|r %s %s is available (needs %d, cap %d)."):format(HEX.title, rankName, prof.name, t.rank.at, t.rank.cap)
        end
        Line(text, { color = C.text })
        if t.rank.outland and prof.masterTrainers then
            local faction = Faction()
            for _, trainer in ipairs(prof.masterTrainers) do
                if not trainer.faction or not faction or trainer.faction == faction then
                    local rowY = y
                    Line(("%s — %s (%.1f, %.1f)"):format(trainer.name, trainer.where, trainer.x, trainer.y),
                        { indent = 10, color = C.dim, rightPad = 50 })
                    local b = NewButton("Go", 44, function() SetWaypoint(trainer, trainer.name) end,
                        function(tip) tip:AddLine("Waypoint to " .. trainer.name) end)
                    b:SetPoint("TOPRIGHT", guide, "TOPRIGHT", 0, rowY + 2)
                    b:SetHeight(18)
                end
            end
        else
            Line("Any " .. prof.name .. " trainer in a capital city.", { indent = 10, color = C.dim })
        end
    end
    Gap(4)
end

local function PaintCraftStep(step, p)
    local colour = ColourFor(step.colour)
    local title = SpellName(step.spell)
    local rowY = y
    IconLine(SpellIcon(step.spell), title, { font = GameFontNormal, color = colour, size = 18 })
    -- Hover the title for the recipe's own tooltip (craft recipes link as
    -- enchant:<spell> on this client)
    local hover = NewHover()
    hover:SetPoint("TOPLEFT", guide, "TOPLEFT", 0, rowY)
    hover:SetPoint("RIGHT", guide, "RIGHT", 0, 0)
    hover:SetHeight(rowY - y)
    AttachTooltip(hover, function(tip)
        if not pcall(tip.SetHyperlink, tip, "enchant:" .. step.spell) then
            tip:AddLine(title)
        end
        tip:AddLine(("%s at %d — yellow %d, green %d, grey %d"):format(
            step.colour, p.rank, step.recipe.yellow, step.recipe.green, step.recipe.grey), 0.7, 0.7, 0.7)
    end)

    -- How many more
    local count
    if step.remaining == math.huge then
        count = HEX.bad .. "this recipe cannot take you to " .. step.to .. "|r"
    elseif step.remaining <= 1 then
        count = "one craft"
    else
        count = ("about %s%d|r more crafts"):format(HEX.white, step.remaining)
    end
    local range = ("%s%d – %d|r"):format(HEX.dim, step.effectiveFrom or step.from, step.to)
    local ref = step.guideCount and (HEX.dim .. ("  · guide says ×%d"):format(step.guideCount) .. "|r") or ""
    Line(("%s   %s%s"):format(range, count, ref), { indent = 23, color = C.dim })
    Gap(3)

    -- Reagents, sized for the planned count
    if step.reagents then
        for _, line in ipairs(step.reagents) do
            ReagentRow(line)
        end
    end
    Gap(2)

    -- What stands in the way
    if step.capped then
        Line(HEX.bad .. "At your skill cap — see the trainer first." .. "|r", { indent = 8 })
    end
    -- "Not known" is only certain once the craft list has been read this
    -- character; before that, IsSpellKnown may simply not answer for
    -- recipes (ASSUMPTIONS A2), and the honest line is to ask for a look
    if (step.needsFormula or step.needsTrainer) and next(char.knownRecipes) == nil and not craftOpen then
        Line(("%sOpen your %s window once|r so the guide can read which recipes you know."):format(HEX.warn, p.profession.name), { indent = 8 })
    elseif step.needsFormula then
        Line(("%sYou do not know this recipe yet.|r Learn it from %s."):format(HEX.warn, ItemName(step.needsFormula)), { indent = 8 })
    elseif step.needsTrainer then
        Line(("%sYou do not know this recipe yet.|r Your %s trainer teaches it at %d."):format(HEX.warn, p.profession.name, step.needsTrainer), { indent = 8 })
    end
    for _, w in ipairs(p.warnings) do
        Line(HEX.warn .. w .. "|r", { indent = 8 })
    end
    if step.recipe.target and db.AutoTargetGear and not TargetFor(step.recipe) then
        Line(("%sYou need %s to cast this on|r — equip one or keep one in your bags."):format(HEX.warn, D.TARGET_WORDS[step.recipe.target] or "a target"), { indent = 8 })
    end
    Gap(2)

    -- Buttons. The Craft button is secure: its macro is written here, out
    -- of combat, and the holder is shown only when it could be written and
    -- the recipe is known
    local open = CraftWindowIsOurs()
    local inCombat = InCombat()
    local buttons = {}
    local canCraft = step.known and not inCombat and not step.capped
    local shortReagent = false
    for _, line in ipairs(step.reagents or {}) do
        if line.have < line.per then shortReagent = true end
    end
    if not inCombat then UpdateMacro(canCraft and step or nil) end
    if canCraft and EnsureCraftButton() and SetCraftMacro(step) then
        craftTooltip = function(tip)
            tip:AddLine("Craft " .. title)
            if step.recipe.target then
                local where = TargetFor(step.recipe)
                if where == "equipped" then
                    tip:AddLine("Casts it on the " .. (D.TARGET_WORDS[step.recipe.target] or "gear") .. " you are wearing" .. (db.AutoConfirmReplace and " and answers the replace question." or "."), 1, 1, 1, true)
                elseif where == "bags" then
                    tip:AddLine("Casts it on the " .. (D.TARGET_WORDS[step.recipe.target] or "gear") .. " in your bags.", 1, 1, 1, true)
                else
                    tip:AddLine("Leaves the glowing cursor for you to pick a target with.", 1, 0.6, 0.2, true)
                end
            else
                tip:AddLine("Casts the recipe once.", 1, 1, 1, true)
            end
            if shortReagent then tip:AddLine("You are short of a reagent.", 1, 0.35, 0.3, true) end
            tip:AddLine(("Macro: %s"):format((CraftMacro(step):gsub("\n", "  "))), 0.6, 0.6, 0.6, true)
            if db.KeepMacro then
                tip:AddLine("The same text is kept in a macro called " .. MACRO_NAME .. " for binding.", 0.6, 0.6, 0.6, true)
            end
        end
        buttons[#buttons + 1] = { secure = "Craft", width = CRAFT_WIDTH }
    else
        buttons[#buttons + 1] = { text = "Craft", width = CRAFT_WIDTH, disabled = true,
            tooltip = function(tip)
                tip:AddLine("Craft " .. title)
                if inCombat then tip:AddLine("Not in combat.", 1, 0.6, 0.2, true)
                elseif not step.known then tip:AddLine("You do not know this recipe yet.", 1, 0.6, 0.2, true)
                elseif step.capped then tip:AddLine("You are at your skill cap.", 1, 0.6, 0.2, true) end
            end }
    end
    if not open and not inCombat and p.hasProfession then
        buttons[#buttons + 1] = { secure = "Open", width = OPEN_WIDTH }
    end
    ButtonRow(buttons)
end

local function PaintBuyStep(step, p)
    local name = ItemName(step.item)
    IconLine(ItemIcon(step.item), "Buy " .. name, { font = GameFontNormal, color = C.title, size = 18 })
    local cost = E.FormatMoney(step.cost or 0)
    local learns = SpellName(step.learns)
    Line(("%s%s|r · teaches %s%s|r · needs %d"):format(HEX.white, cost, HEX.white, learns, step.at or 0), { indent = 23, color = C.dim })
    if step.rep then
        local short = step.repShort
        Line(("%sRequires %s|r"):format(short and HEX.bad or HEX.warn, step.rep.label), { indent = 8 })
    end
    Gap(3)
    if #step.vendors == 0 then
        Line(HEX.bad .. "No vendor your faction can trade with." .. "|r", { indent = 8 })
    end
    for _, v in ipairs(step.vendors) do
        local rowY = y
        Line(("%s%s|r — %s, %s (%.1f, %.1f)"):format(HEX.white, v.name, v.where or "", v.zone, v.x, v.y), { indent = 8, color = C.text, rightPad = 50 })
        local b = NewButton("Go", 44, function() SetWaypoint(v, name) end,
            function(tip)
                tip:AddLine("Waypoint to " .. v.name)
                tip:AddLine(TomTom and "Sets a TomTom waypoint." or "Prints the coordinates to chat (TomTom is not installed).", 1, 1, 1, true)
            end)
        b:SetPoint("TOPRIGHT", guide, "TOPRIGHT", 0, rowY + 2)
        b:SetHeight(18)
    end
    Gap(3)
    if step.holding then
        Line(HEX.good .. "It is in your bags — right-click it to learn the recipe." .. "|r", { indent = 8 })
    else
        Line("Then right-click the formula to learn it.", { indent = 8, color = C.dim })
    end
    Gap(2)
end

-- The segment's two ways, when the step you are on has them: shown as two
-- rows with radio marks, the chosen one lit, the other a click away. There
-- is no button for it; a segment with one path shows nothing.
local function ChoosePath(seg, path)
    char.choices[seg.key] = path.key
    Announce(("%d – %d: now taking %s%s|r"):format(seg.from, seg.to, HEX.white, path.label))
    Rebuild()
end

local function PaintOptions(p)
    local step = p.current
    if not (step and step.alternatives) then return end
    local seg = step.segment
    Gap(2)
    Line(("%sTWO WAYS THROUGH %d – %d|r"):format(HEX.dim, seg.from, seg.to), { font = GameFontDisableSmall, gap = 3 })
    for _, path in ipairs(seg.paths) do
        OptionRow(path, path == step.path, function() ChoosePath(seg, path) end)
    end
end

local function PaintFooter(p)
    local buttons = {}
    buttons[#buttons + 1] = { text = "Route", width = 56, onClick = function() CommanderTradecraft_Route() end,
        tooltip = function(tip) tip:AddLine("The whole route"); tip:AddLine("Every step, every alternative, and where you are.", 1, 1, 1, true) end }
    buttons[#buttons + 1] = { text = "Shopping", width = 76, onClick = function() CommanderTradecraft_Shopping() end,
        tooltip = function(tip) tip:AddLine("Shopping list"); tip:AddLine("Everything the rest of the route needs, less what you hold.", 1, 1, 1, true) end }
    ButtonRow(buttons)
end

-- Set by /ctc show for the session, so a character without the profession
-- can still look at the guide on purpose without every non-enchanter in
-- the suite being told to go and learn Enchanting at login
local openedByHand = false

local function GuideWanted()
    if not (db and db.EnableTradecraft) then return false end
    if Commander.UI.HudUnlocked(db, "Guide") then return true end
    if not db.ShowGuide then return false end
    if plan and not plan.hasProfession and not openedByHand then return false end
    if plan and plan.finished and db.HideWhenFinished then return false end
    return true
end

Repaint = function()
    if not loaded then return end
    ReleaseAll()
    -- Holders are plain frames: hiding them is fine in combat too
    for _, entry in pairs(secure) do entry.holder:Hide() end
    local p = plan
    if not p then guide:Hide() return end

    headerIcon:SetTexture(p.profession.icon)
    headerName:SetText(Guide().title)
    headerRank:SetText(RankText(p))
    bar:SetMinMaxValues(0, p.target)
    bar:SetValue(p.rank)
    -- Cap marker: the part of the bar you cannot reach yet is darker
    if p.hasProfession and p.maxRank < p.target then
        bar:SetStatusBarColor(1, 0.82, 0.15, 0.9)
    end

    y = -(18 + 4 + 6 + PAD)
    heightMissing = false

    -- Step counter, and the bracket you are levelling through
    if p.current then
        local b = p.bracket
        Line(("%sSTEP %d OF %d%s|r"):format(HEX.dim, p.current.index, p.totalSteps,
            b and ("  ·  " .. b.name:upper() .. " " .. b.from .. " – " .. b.to) or ""),
            { font = GameFontDisableSmall, gap = 3 })
    end

    PaintTrainBanner(p)

    if p.finished then
        Line(HEX.good .. Guide().title .. " — complete." .. "|r", { font = GameFontNormal })
        Line("Nothing left on the route. /ctc hides the window; it comes back if the guide ever changes.", { color = C.dim })
    elseif not p.hasProfession then
        Line("Once you have learned it, the first step is a Runed Copper Rod.", { color = C.dim })
    elseif p.current then
        if p.current.kind == "craft" then
            PaintCraftStep(p.current, p)
        else
            PaintBuyStep(p.current, p)
        end

        -- The guide's note for this path (the option rows carry it when
        -- there are two ways, so it is not printed twice)
        if db.ShowTips and p.current.path.note and not p.current.alternatives then
            Line(HEX.dim .. p.current.path.note .. "|r", { indent = 4, gap = 4 })
        end
        PaintOptions(p)

        -- Upcoming
        local up = E.Upcoming(p, db.PreviewSteps or 0)
        if #up > 0 then
            Gap(2)
            Line(HEX.dim .. "NEXT" .. "|r", { font = GameFontDisableSmall, gap = 3 })
            for _, step in ipairs(up) do
                local text
                if step.kind == "craft" then
                    text = ("%s  %s%d – %d|r"):format(SpellName(step.spell), HEX.dim, step.from, step.to)
                    IconLine(SpellIcon(step.spell), text, { indent = 4, alpha = 0.6, size = 14 })
                else
                    text = ("Buy %s  %s%s · needs %d|r"):format(ItemName(step.item), HEX.dim,
                        step.vendors[1] and (step.vendors[1].zone .. " ") or "", step.at or 0)
                    IconLine(ItemIcon(step.item), text, { indent = 4, alpha = 0.6, size = 14 })
                end
            end
        end
    end

    Gap(4)
    if p.hasProfession and not p.finished then
        PaintFooter(p)
    end

    guide:SetSize(WIDTH, -y + 2)
    Commander.UI.ApplyHudChrome(guide, db, "Guide", {
        title = "Tradecraft",
        defaultPoint = { point = "RIGHT", x = -40, y = -160 },
    })
    local wasShown = guide:IsShown()
    guide:SetShown(GuideWanted())
    if heightMissing and guide:IsShown() and not wasShown and not guide._repaintQueued then
        guide._repaintQueued = true
        C_Timer.After(0, function()
            guide._repaintQueued = nil
            Repaint()
        end)
    end
end

-- ---------------------------------------------------------------------------
-- The ledger: route and shopping in one scrolling window
-- ---------------------------------------------------------------------------

local ledger
local ledgerMode = "route"

-- The route as rows. Each entry paints one line of the list:
--   { kind = "bracket", bracket = b }
--   { kind = "step", step = step, indent = n }
--   { kind = "ways", segment = seg }            "two ways through 156 – 185"
--   { kind = "option", segment = seg, path = path, chosen = bool }
-- A segment with two ways lists both under a header, the chosen one lit,
-- and then the chosen way's steps indented beneath.
local function RouteEntries(p)
    local out = {}
    local lastBracket, lastSeg
    for _, step in ipairs(p.steps) do
        if step.bracket and step.bracket ~= lastBracket then
            lastBracket = step.bracket
            out[#out + 1] = { kind = "bracket", bracket = step.bracket }
        end
        local seg = step.segment
        local indent = 0
        -- A finished segment's other way is history; only its steps are listed
        if #seg.paths > 1 and p.rank < seg.to then
            if seg ~= lastSeg then
                out[#out + 1] = { kind = "ways", segment = seg }
                for _, path in ipairs(seg.paths) do
                    out[#out + 1] = { kind = "option", segment = seg, path = path, chosen = path == step.path }
                end
            end
            indent = 1
        end
        lastSeg = seg
        out[#out + 1] = { kind = "step", step = step, indent = indent }
    end
    return out
end

-- One bracket's shopping rows as lines: to buy, covered, formulas, and a
-- plain paste list
local function ShoppingRows(out, rows, formulas, formulaCost, pasteLabel)
    local toBuy, held = {}, {}
    for _, row in ipairs(rows) do
        if row.buy > 0 then toBuy[#toBuy + 1] = row else held[#held + 1] = row end
    end
    if #toBuy == 0 and #held == 0 and #formulas == 0 then
        out[#out + 1] = HEX.dim .. "  Nothing needed." .. "|r"
        return
    end
    if #toBuy > 0 then
        out[#out + 1] = HEX.white .. "  To buy" .. "|r"
        for _, row in ipairs(toBuy) do
            local line = ("    %s%d|r × %s"):format(HEX.bad, row.buy, ItemName(row.id))
            if row.covered and row.covered > 0 then
                line = line .. HEX.dim .. ("   (need %d, %d already yours)"):format(row.need, row.covered) .. "|r"
            elseif row.have and row.have + (row.bank or 0) > 0 and not row.covered then
                line = line .. HEX.dim .. ("   (need %d, have %d%s)"):format(row.need, row.have,
                    (row.bank or 0) > 0 and (" + %d in bank"):format(row.bank) or "") .. "|r"
            end
            if row.note then line = line .. HEX.dim .. "   " .. row.note .. "|r" end
            out[#out + 1] = line
        end
    end
    if #held > 0 then
        out[#out + 1] = HEX.white .. "  Covered" .. "|r"
        for _, row in ipairs(held) do
            out[#out + 1] = ("    %s%d|r × %s %s(already yours)|r"):format(HEX.green, row.need, ItemName(row.id), HEX.dim)
        end
    end
    if #formulas > 0 then
        out[#out + 1] = HEX.white .. "  Formulas" .. "|r" .. HEX.dim .. ("  %s in all"):format(E.FormatMoney(formulaCost)) .. "|r"
        for _, step in ipairs(formulas) do
            local v = step.vendors[1]
            out[#out + 1] = ("    %s  %s%s — %s%s|r"):format(ItemName(step.item), HEX.dim, E.FormatMoney(step.cost or 0),
                v and (v.name .. ", " .. v.zone) or "no vendor for your faction",
                step.rep and ("  (" .. step.rep.label .. ")") or "")
        end
    end
    if #toBuy > 0 and pasteLabel then
        out[#out + 1] = HEX.dim .. "  " .. pasteLabel .. "|r"
        for _, row in ipairs(toBuy) do
            out[#out + 1] = "    " .. ItemName(row.id)
        end
    end
end

local function PendingFormulas(steps)
    local formulas = {}
    for _, step in ipairs(steps) do
        if step.kind == "buy" and (step.status == "current" or step.status == "pending") then
            formulas[#formulas + 1] = step
        end
    end
    return formulas
end

-- Grouped by trainer bracket: a bracket is one shopping trip. What you
-- hold is counted against the earliest bracket that wants it; the whole
-- route's totals close the list for anyone shopping once.
local function BuildShoppingText(p)
    local out = {}
    out[#out + 1] = ("%sShopping list|r  %s  %s%s|r"):format(HEX.title, RankText(p), HEX.dim,
        db.CountBank and "(bags and bank counted)" or "(bags counted)")
    out[#out + 1] = HEX.dim .. ("By trainer bracket — each one is a shopping trip. Planned with a %d%% margin on yellow and green crafts; what you hold pays for the earliest bracket first; rods you make along the way are left off."):format(math.floor((db.Margin or 0) * 100 + 0.5)) .. "|r"
    if p.finished then
        out[#out + 1] = ""
        out[#out + 1] = "Nothing left to buy."
        return table.concat(out, "\n")
    end
    for _, b in ipairs(p.brackets or {}) do
        if not b.done then
            out[#out + 1] = ""
            out[#out + 1] = ("%s%s %d – %d|r%s"):format(HEX.title, b.name:upper(), b.from, b.to,
                b.current and (HEX.title .. "  you are here|r") or "")
            ShoppingRows(out, b.shopping, PendingFormulas(b.steps), b.formulaCost,
                b.current and "Plain names for an auction search:" or nil)
        end
    end
    out[#out + 1] = ""
    out[#out + 1] = HEX.title .. "EVERYTHING LEFT, ALL BRACKETS" .. "|r"
    ShoppingRows(out, p.shopping, PendingFormulas(p.steps), E.FormulaCosts(p), nil)
    return table.concat(out, "\n")
end

local function EnsureLedger()
    if ledger then return ledger end
    ledger = CreateFrame("Frame", "CommanderTradecraftLedger", UIParent, "BackdropTemplate")
    ledger:SetSize(620, 460)
    ledger:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    ledger:SetFrameStrata("DIALOG")
    ledger:SetToplevel(true)
    ledger:SetMovable(true)
    ledger:SetClampedToScreen(true)
    ledger:Hide()
    Commander.UI.ApplyStyleBackdrop(ledger, "DARK")
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderTradecraftLedger")
    end

    local title = ledger:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", ledger, "TOPLEFT", 12, -10)
    ledger.title = title

    local drag = CreateFrame("Frame", nil, ledger)
    drag:SetPoint("TOPLEFT", ledger, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", ledger, "TOPRIGHT", 0, 0)
    drag:SetHeight(28)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() ledger:StartMoving() end)
    drag:SetScript("OnDragStop", function() ledger:StopMovingOrSizing() end)

    local scroll = CreateFrame("ScrollFrame", "CommanderTradecraftLedgerScroll", ledger, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", ledger, "TOPLEFT", 12, -34)
    scroll:SetPoint("BOTTOMRIGHT", ledger, "BOTTOMRIGHT", -30, 40)
    Commander.UI.SlimScrollBar("CommanderTradecraftLedgerScroll", 2, 2)
    ledger.shopScroll = scroll

    -- The route: a second scroll frame of pooled rows, shown in route mode
    local rscroll = CreateFrame("ScrollFrame", "CommanderTradecraftRouteScroll", ledger, "UIPanelScrollFrameTemplate")
    rscroll:SetPoint("TOPLEFT", ledger, "TOPLEFT", 12, -34)
    rscroll:SetPoint("BOTTOMRIGHT", ledger, "BOTTOMRIGHT", -30, 40)
    Commander.UI.SlimScrollBar("CommanderTradecraftRouteScroll", 2, 2)
    local rcontent = CreateFrame("Frame", nil, rscroll)
    rcontent:SetSize(1, 1)
    rscroll:SetScrollChild(rcontent)
    rscroll:SetScript("OnSizeChanged", function(_, width) rcontent:SetWidth(width) end)
    rscroll:EnableMouseWheel(true)
    rscroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 36
        local limit = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)
    ledger.routeScroll, ledger.routeContent = rscroll, rcontent
    ledger.rows = {}
    -- A multi-line EditBox as the scroll child sizes its own height to its
    -- text (Quartermaster's shopping list and Debug's report do the same)
    local edit = CreateFrame("EditBox", nil, scroll)
    ledger.edit = edit
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlightSmall)
    edit:SetWidth(570)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Read-only in effect: any typed change is thrown away on the next paint
    edit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and ledger.text then self:SetText(ledger.text) end
    end)
    scroll:SetScrollChild(edit)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 28
        local limit = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)

    local close = CreateFrame("Button", nil, ledger, "UIPanelButtonTemplate")
    close:SetSize(70, 22)
    close:SetPoint("BOTTOMRIGHT", ledger, "BOTTOMRIGHT", -10, 10)
    close:SetText("Close")
    close:SetScript("OnClick", function() ledger:Hide() end)

    local selectAll = CreateFrame("Button", nil, ledger, "UIPanelButtonTemplate")
    selectAll:SetSize(90, 22)
    selectAll:SetPoint("RIGHT", close, "LEFT", -6, 0)
    selectAll:SetText("Select All")
    selectAll:SetScript("OnClick", function()
        edit:SetFocus()
        edit:HighlightText()
    end)
    ledger.selectAll = selectAll

    local route = CreateFrame("Button", nil, ledger, "UIPanelButtonTemplate")
    route:SetSize(70, 22)
    route:SetPoint("BOTTOMLEFT", ledger, "BOTTOMLEFT", 10, 10)
    route:SetText("Route")
    route:SetScript("OnClick", function() CommanderTradecraft_Route() end)
    ledger.routeButton = route

    local shop = CreateFrame("Button", nil, ledger, "UIPanelButtonTemplate")
    shop:SetSize(90, 22)
    shop:SetPoint("LEFT", route, "RIGHT", 6, 0)
    shop:SetText("Shopping")
    shop:SetScript("OnClick", function() CommanderTradecraft_Shopping() end)
    ledger.shopButton = shop

    local auc = CreateFrame("Button", nil, ledger, "UIPanelButtonTemplate")
    auc:SetSize(150, 22)
    auc:SetPoint("LEFT", shop, "RIGHT", 6, 0)
    auc:SetText("Bracket to Auctionator")
    auc:SetScript("OnClick", function() CommanderTradecraft_AuctionatorList("bracket") end)
    ledger.aucButton = auc

    local aucAll = CreateFrame("Button", nil, ledger, "UIPanelButtonTemplate")
    aucAll:SetSize(120, 22)
    aucAll:SetPoint("LEFT", auc, "RIGHT", 6, 0)
    aucAll:SetText("All to Auctionator")
    aucAll:SetScript("OnClick", function() CommanderTradecraft_AuctionatorList("all") end)
    ledger.aucAllButton = aucAll
    return ledger
end

local ROW_H, HEAD_H = 20, 26

local function RouteRow(i)
    local row = ledger.rows[i]
    if row then return row end
    local content = ledger.routeContent
    row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_H)
    row.bar = row:CreateTexture(nil, "BACKGROUND")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetAllPoints()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.hl:SetVertexColor(1, 1, 1, 0.06)
    row.hl:SetAllPoints()
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetSize(14, 14)
    row.mark:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFontObject(GameFontHighlightSmall)
    row.name:SetJustifyH("LEFT")
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.range = row:CreateFontString(nil, "OVERLAY")
    row.range:SetFontObject(GameFontHighlightSmall)
    row.range:SetJustifyH("RIGHT")
    row.range:SetPoint("RIGHT", row, "RIGHT", -110, 0)
    row.range:SetWidth(90)
    row.count = row:CreateFontString(nil, "OVERLAY")
    row.count:SetFontObject(GameFontHighlightSmall)
    row.count:SetJustifyH("RIGHT")
    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.count:SetWidth(100)
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.line:SetVertexColor(1, 1, 1, 0.15)
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 2)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 2)
    ledger.rows[i] = row
    return row
end

local function StepRowText(step)
    -- name, range, count, colour
    local st = step.status
    local colour = (st == "done" and C.green) or (st == "current" and C.title) or (st == "skipped" and C.grey) or C.text
    if step.kind == "craft" then
        local range = ("%d – %d"):format(step.from, step.to)
        local count
        if st == "done" then
            count = step.count and ("×%d"):format(step.count) or ""
        elseif step.remaining then
            count = (step.remaining == math.huge) and "?" or ("~%d more"):format(step.remaining)
            if step.guideCount then count = count .. (" (guide ×%d)"):format(step.guideCount) end
        else
            count = ""
        end
        return SpellName(step.spell), range, count, colour, SpellIcon(step.spell)
    else
        local v = step.vendors[1]
        local name = "Buy " .. ItemName(step.item) .. (v and (HEX.dim .. "  — " .. v.name .. ", " .. v.zone .. "|r") or "")
        return name, ("needs %d"):format(step.at or 0), E.FormatMoney(step.cost or 0), colour, ItemIcon(step.item)
    end
end

local function PaintRoute(p)
    local entries = RouteEntries(p)
    local content = ledger.routeContent
    local y = 0
    local n = 0
    for _, e in ipairs(entries) do
        n = n + 1
        local row = RouteRow(n)
        -- TOPLEFT + TOPRIGHT only: a LEFT or RIGHT anchor would centre the
        -- row on the content frame and fight the y below
        row:ClearAllPoints()
        row.mark:Hide(); row.icon:Hide(); row.line:Hide(); row.bar:Hide()
        row.range:SetText(""); row.count:SetText("")
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil)
        row.name:ClearAllPoints()
        row.name:SetPoint("RIGHT", row.range, "LEFT", -8, 0)
        if e.kind == "bracket" then
            local b = e.bracket
            row:SetHeight(HEAD_H)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            row.name:SetPoint("LEFT", row, "LEFT", 6, -3)
            row.name:SetFontObject(GameFontNormal)
            row.name:SetText(("%s %d – %d"):format(b.name:upper(), b.from, b.to))
            row.name:SetTextColor(unpack(C.title))
            row.count:SetText(b.done and (HEX.green .. "done|r") or b.current and (HEX.title .. "you are here|r") or "")
            row.line:Show()
        elseif e.kind == "ways" then
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            row.name:SetPoint("LEFT", row, "LEFT", 24, 0)
            row.name:SetFontObject(GameFontDisableSmall)
            row.name:SetText(("TWO WAYS THROUGH %d – %d"):format(e.segment.from, e.segment.to))
            row.name:SetTextColor(unpack(C.dim))
        elseif e.kind == "option" then
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            row.mark:ClearAllPoints()
            row.mark:SetPoint("LEFT", row, "LEFT", 28, 0)
            Radio(row.mark, e.chosen)
            row.mark:Show()
            row.name:SetPoint("LEFT", row, "LEFT", 46, 0)
            row.name:SetFontObject(GameFontHighlightSmall)
            row.name:SetText(e.path.label)
            row.name:SetTextColor(unpack(e.chosen and C.text or C.dim))
            local seg, path = e.segment, e.path
            row:SetScript("OnClick", function() ChoosePath(seg, path) end)
            AttachTooltip(row, function(tip)
                tip:AddLine(path.label)
                if path.note then tip:AddLine(path.note, 1, 1, 1, true) end
                tip:AddLine(e.chosen and "The way you are taking." or "Click to take this way instead.", 0.6, 0.6, 0.6, true)
            end)
        else
            local step = e.step
            local name, range, count, colour, icon = StepRowText(step)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
            local x = 24 + e.indent * 22
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", row, "LEFT", x, 0)
            row.icon:SetTexture(icon)
            row.icon:SetAlpha(step.status == "done" and 0.5 or 1)
            row.icon:Show()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.name:SetFontObject(GameFontHighlightSmall)
            row.name:SetText(name)
            row.name:SetTextColor(unpack(colour))
            row.range:SetText(range)
            row.range:SetTextColor(unpack(step.status == "done" and C.dim or C.text))
            row.count:SetText(count)
            row.count:SetTextColor(unpack(step.status == "done" and C.dim or C.text))
            if step.status == "current" then
                row.bar:SetVertexColor(1, 0.82, 0.15, 0.12)
                row.bar:Show()
            end
            AttachTooltip(row, function(tip)
                if step.kind == "craft" then
                    if not pcall(tip.SetHyperlink, tip, "enchant:" .. step.spell) then tip:AddLine(name) end
                    tip:AddLine(("yellow %d, green %d, grey %d"):format(step.recipe.yellow, step.recipe.green, step.recipe.grey), 0.7, 0.7, 0.7)
                else
                    if not pcall(tip.SetHyperlink, tip, "item:" .. step.item) then tip:AddLine(name) end
                    for _, v in ipairs(step.vendors) do
                        tip:AddLine(("%s — %s, %s (%.1f, %.1f)"):format(v.name, v.where or "", v.zone, v.x, v.y), 1, 1, 1, true)
                    end
                    if step.rep then tip:AddLine(step.rep.label, 1, 0.6, 0.2) end
                end
            end)
        end
        row:Show()
        y = y - row:GetHeight()
    end
    for i = n + 1, #ledger.rows do ledger.rows[i]:Hide() end
    content:SetHeight(-y + 4)
end

PaintLedger = function()
    if not (ledger and ledger:IsShown() and plan) then return end
    if ledgerMode == "shop" then
        ledger.title:SetText(("Tradecraft — Shopping List  %s"):format(RankText(plan)))
        local text = BuildShoppingText(plan)
        ledger.text = text
        ledger.edit:SetText(text)
        ledger.shopScroll:Show()
        ledger.routeScroll:Hide()
        ledger.selectAll:Show()
    else
        ledger.title:SetText(("Tradecraft — %s  %s"):format(Guide().title, RankText(plan)))
        ledger.shopScroll:Hide()
        ledger.routeScroll:Show()
        ledger.selectAll:Hide()
        PaintRoute(plan)
    end
    ledger.routeButton:SetEnabled(ledgerMode ~= "route")
    ledger.shopButton:SetEnabled(ledgerMode ~= "shop")
    local haveAuc = ledgerMode == "shop" and Auctionator and Auctionator.API and Auctionator.API.v1
        and Auctionator.API.v1.CreateShoppingList and true or false
    ledger.aucButton:SetShown(haveAuc)
    ledger.aucAllButton:SetShown(haveAuc)
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

function CommanderTradecraft_Show()
    if not loaded then return end
    db.ShowGuide = true
    openedByHand = true
    Commander.Notify(Events.UPDATE)
    Rebuild()
    if not guide:IsShown() and plan and plan.finished and db.HideWhenFinished then
        Announce(("%s is complete — Hide When Finished is on, so the guide stays away. /ctc route shows the route anyway."):format(Guide().title))
    end
end

function CommanderTradecraft_Hide()
    if not loaded then return end
    db.ShowGuide = false
    guide:Hide()
end

function CommanderTradecraft_Toggle()
    if not loaded then return end
    if guide:IsShown() then CommanderTradecraft_Hide() else CommanderTradecraft_Show() end
end

function CommanderTradecraft_Route()
    if not loaded then return end
    EnsureLedger()
    ledgerMode = "route"
    Rebuild()
    ledger:Show()
    PaintLedger()
end

function CommanderTradecraft_Shopping()
    if not loaded then return end
    EnsureLedger()
    ledgerMode = "shop"
    Rebuild()
    ledger:Show()
    PaintLedger()
end

-- Toggle (or set, with "main" / "alt") the path through the next segment
-- that has one. A segment key first ("/ctc alt 320-340 alt") picks any
-- segment on the route instead, for deciding ahead.
function CommanderTradecraft_Alternative(arg)
    if not (loaded and plan) then return end
    local which = arg and arg:match("^%s*(.-)%s*$") or ""
    local seg, currentPath
    local segKey, rest = which:match("^(%d+%-%d+)%s*(.*)$")
    if segKey then
        for _, candidate in ipairs(Guide().segments) do
            if candidate.key == segKey then seg = candidate end
        end
        if not seg then
            Announce("no segment called " .. segKey .. " — the keys are the skill ranges, like 320-340")
            return
        end
        if #seg.paths < 2 then
            Announce(segKey .. " has no alternative")
            return
        end
        currentPath = E.PathFor(seg, char.choices)
        which = rest
    else
        if not plan.current then
            Announce("no current step")
            return
        end
        seg = plan.current.segment
        if #seg.paths < 2 then
            Announce("this step has one way through it — name a segment to decide a later one, e.g. /ctc alt 320-340 alt")
            return
        end
        currentPath = plan.current.path
    end
    local target
    if which and which ~= "" then
        for _, path in ipairs(seg.paths) do
            if path.key == which then target = path end
        end
        if not target then
            Announce("no path called '" .. which .. "' — the choices here are main and alt")
            return
        end
    else
        for i, path in ipairs(seg.paths) do
            if path == currentPath then
                target = seg.paths[i % #seg.paths + 1]
            end
        end
    end
    if not target then return end
    char.choices[seg.key] = target.key
    Announce(("%d – %d: now taking %s%s|r"):format(seg.from, seg.to, HEX.white, target.label))
    if target.note then Announce(HEX.dim .. target.note .. "|r") end
    Rebuild()
end

function CommanderTradecraft_Craft()
    if not loaded then return end
    CraftCurrent()
end

function CommanderTradecraft_ResetProgress()
    if not loaded then return end
    char.choices = {}
    char.skipped = {}
    char.lastSkipped = nil
    Announce("route choices and skipped steps forgotten for this character")
    Rebuild()
end

function CommanderTradecraft_Status()
    if not loaded then return end
    Rebuild()
    local p = plan
    if not p.hasProfession then
        Announce(("you do not know %s yet"):format(p.profession.name))
        return
    end
    Announce(("%s %s"):format(Guide().title, RankText(p)))
    if p.current then
        Announce(("step %d of %d: %s"):format(p.current.index, p.totalSteps, StepTitle(p.current)))
    end
    if p.train then
        Announce(("trainer: %s %s (needs %d)"):format(p.train.rank.name, p.profession.name, p.train.rank.at))
    end
    -- How recipes are being detected (ASSUMPTIONS A2): by the spellbook
    -- call, by the craft-window memory, or not at all yet
    local bySpellbook, byMemory = 0, 0
    for spell in pairs(D.RECIPES) do
        if (IsSpellKnown and IsSpellKnown(spell)) or (IsPlayerSpell and IsPlayerSpell(spell)) then
            bySpellbook = bySpellbook + 1
        end
        if char.knownRecipes[spell] then byMemory = byMemory + 1 end
    end
    Announce(("recipes on the route you know: %d by the spellbook, %d seen in the craft window%s"):format(
        bySpellbook, byMemory,
        (bySpellbook == 0 and byMemory > 0) and " — the spellbook call does not answer for recipes on this client; the craft window is doing the work" or ""))
end

-- Hand the to-buy list to Auctionator as a shopping list: the current
-- bracket's (the default — one trip) or the whole route's
function CommanderTradecraft_AuctionatorList(scope)
    if not (loaded and plan) then return end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.CreateShoppingList) then
        Announce("Auctionator is not installed")
        return
    end
    local rows, label = plan.shopping, Guide().title
    if scope ~= "all" and plan.bracket then
        rows = plan.bracket.shopping
        label = ("%s %d-%d"):format(plan.profession.name, plan.bracket.from, plan.bracket.to)
    end
    local terms = {}
    for _, row in ipairs(rows) do
        if row.buy > 0 then
            local name = ItemName(row.id)
            if api.ConvertToSearchString then
                local ok, term = pcall(api.ConvertToSearchString, "Commander_Tradecraft", { searchString = name, isExact = true })
                terms[#terms + 1] = ok and term or name
            else
                terms[#terms + 1] = name
            end
        end
    end
    if #terms == 0 then
        Announce("nothing left to buy")
        return
    end
    local ok, err = pcall(api.CreateShoppingList, "Commander_Tradecraft", "Tradecraft: " .. label, terms)
    if ok then
        Announce(("%d items sent to the Auctionator shopping list 'Tradecraft: %s'"):format(#terms, label))
    else
        Announce("Auctionator refused the list: " .. tostring(err))
    end
end

-- The live plan, for other modules
function CommanderTradecraft_Plan()
    return plan
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")

-- Every name here is in this client's Blizzard_APIDocumentationGenerated
-- (checked 2026-09-17). LEARNED_SPELL_IN_TAB is not, and registering it
-- threw at login and took every event after it down with it; SPELLS_CHANGED
-- and NEW_RECIPE_LEARNED cover a formula being learned.
local WATCHED = {
    "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "BAG_UPDATE_DELAYED", "PLAYERBANKSLOTS_CHANGED", "BANKFRAME_OPENED",
    "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE",
    "SPELLS_CHANGED", "NEW_RECIPE_LEARNED",
    "UPDATE_FACTION", "PLAYER_ENTERING_WORLD",
    "UNIT_INVENTORY_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "GET_ITEM_INFO_RECEIVED", "UPDATE_MACROS",
}

events:SetScript("OnEvent", function(_, event, arg1)
    if not loaded then return end
    if event == "CRAFT_SHOW" then
        craftOpen = true
        if db.AutoOpenWithCraft and db.EnableTradecraft and CraftWindowIsOurs() then
            db.ShowGuide = true
        end
    elseif event == "CRAFT_CLOSE" then
        craftOpen = false
        craftIndexBySpell = {}
    elseif event == "UPDATE_MACROS" or event == "PLAYER_ENTERING_WORLD" then
        macrosReady = true
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then
        return
    end
    ScheduleRebuild()
end)

function CommanderTradecraft_OnLogin()
    db = CommanderTradecraftDB
    char = CommanderTradecraftChar
    loaded = true
    -- Each registration on its own: an event this client does not know
    -- must cost that one event, never the rest of the list
    for _, e in ipairs(WATCHED) do
        local ok = pcall(events.RegisterEvent, events, e)
        if not ok then
            print("Commander Tradecraft: this client has no event " .. e .. " — skipped")
        end
    end
    Commander.AddListener(Events.UPDATE, function()
        if not db.EnableTradecraft then
            guide:Hide()
            return
        end
        ScheduleRebuild()
    end)
    -- The binding's button, so the key works before the guide ever paints
    EnsureKeyButton()
    Rebuild()
end

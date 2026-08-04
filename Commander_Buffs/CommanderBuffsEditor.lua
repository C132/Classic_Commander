-- Commander Buffs: the priority editor.
--
-- A settings page can toggle a feature; it cannot teach a policy. This
-- window exists because the sentinel's rules are ORDERED — the first rule
-- that accepts an aura claims it — and an ordered policy is only learnable
-- if you can see it run. So the window is three columns: the rule list
-- (the policy), the inspector (one rule's every field), and the LIVE TRACE
-- — your actual aura stack, right now, with the rule that claimed each aura
-- and the score it produced. Edit a rule and the trace repaints instantly.
-- That feedback loop is the feature; the widgets are just how you reach it.

local E = CommanderBuffsEngine

local FRAME_W, FRAME_H = 960, 580
local ROW_H = 24
local LIST_ROWS = 17
local TRACE_ROWS = 15

local editor
local selected = 1        -- index into the rule list
local listOffset = 0
local traceSelected       -- an aura table picked out of the trace
local inspectorRefreshers = {}
local listRows, traceRows = {}, {}
local lastTrace = 0

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function DB()
    return CommanderBuffsDB
end

local function Rules()
    local db = DB()
    if not db then return {} end
    db.Rules = db.Rules or {}
    return db.Rules
end

local function Selected()
    return Rules()[selected]
end

-- Rule edits repaint the world directly rather than firing the module event:
-- a Notify would run the whole Apply path (including the deferred hide of
-- Blizzard's frames) on every keystroke in the inspector.
local function Repaint()
    if CommanderBuffs_Refresh then CommanderBuffs_Refresh() end
end

local function Changed(rule)
    if rule then E.NormalizeRule(rule, Rules()) end
    Repaint()
end

local function Truncate(text, limit)
    text = tostring(text or "")
    if #text <= limit then return text end
    return text:sub(1, limit - 1) .. "…"
end

-- ---------------------------------------------------------------------------
-- Widget kit. Small, local, and compact on purpose: the inspector has ~16
-- controls and every pixel of height it saves is a rule row the list keeps.
-- ---------------------------------------------------------------------------

local function Tip(widget, title, text)
    if Commander and Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(widget, title, text)
    end
end

local function MakeHeader(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    return fs
end

local function MakeCheck(parent, label, tooltip, get, set, width)
    local check = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
    check:SetSize(22, 22)
    if check.Text then
        check.Text:SetText(label)
        check.Text:SetFontObject("GameFontHighlightSmall")
    end
    Tip(check, label, tooltip)
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    inspectorRefreshers[#inspectorRefreshers + 1] = function()
        check:SetChecked(get() and true or false)
    end
    check._width = width or 100
    return check
end

-- A cycle button beats a dropdown here: no global frame name, no menu taint,
-- and the current value is always legible without opening anything.
local function MakeCycle(parent, label, tooltip, options, get, set, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 150, 20)
    Tip(button, label, (tooltip or "") .. "\n\nLeft-click cycles forward, right-click back.")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local function Sync()
        local value = get()
        if value == nil then
            button:SetText(label .. ": —")
            return
        end
        local text = value
        for _, option in ipairs(options) do
            if option.value == value then text = option.text end
        end
        button:SetText(label .. ": " .. tostring(text))
    end

    button:SetScript("OnClick", function(_, mouse)
        local value = get()
        local index = 1
        for i, option in ipairs(options) do
            if option.value == value then index = i end
        end
        index = index + (mouse == "RightButton" and -1 or 1)
        if index < 1 then index = #options elseif index > #options then index = 1 end
        set(options[index].value)
        Sync()
    end)
    inspectorRefreshers[#inspectorRefreshers + 1] = Sync
    return button
end

local function MakeEdit(parent, label, tooltip, get, set, boxWidth)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetText(label)

    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(boxWidth or 180, 18)
    box:SetAutoFocus(false)
    box:SetMaxLetters(200)
    Tip(box, label, tooltip)
    box:SetScript("OnEnterPressed", function(self)
        set(self:GetText())
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        set(self:GetText())
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    inspectorRefreshers[#inspectorRefreshers + 1] = function()
        if box:HasFocus() then return end
        box:SetText(get() or "")
        box:SetCursorPosition(0)
    end
    box._label = fs
    return box
end

-- Hand-rolled slider (the suite convention: OptionsSliderTemplate's atlas
-- track does not render reliably on this client), laid out on ONE line —
-- label, track, value — so the inspector fits without scrolling.
local function MakeSlider(parent, label, tooltip, min, max, step, get, set, format)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetText(label)

    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(140, 16)
    slider:SetHitRectInsets(0, 0, -6, -6)
    slider:SetBackdrop(BACKDROP_SLIDER_8_8 or {
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileEdge = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then thumb:SetSize(28, 28) end
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    Tip(slider, label, tooltip)

    local value = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")

    local syncing = false
    slider:SetScript("OnValueChanged", function(self, raw)
        if syncing then return end
        local snapped = min + math.floor((raw - min) / step + 0.5) * step
        if snapped < min then snapped = min elseif snapped > max then snapped = max end
        value:SetText(string.format(format or "%d", snapped))
        set(snapped)
    end)
    inspectorRefreshers[#inspectorRefreshers + 1] = function()
        syncing = true
        local current = get() or min
        slider:SetValue(current)
        value:SetText(string.format(format or "%d", current))
        syncing = false
    end

    slider._label = fs
    slider._value = value
    return slider
end

-- ---------------------------------------------------------------------------
-- Rule list
-- ---------------------------------------------------------------------------

local function RefreshList()
    if not editor then return end
    local rules = Rules()
    local total = #rules
    local maxOffset = math.max(0, total - LIST_ROWS)
    if listOffset > maxOffset then listOffset = maxOffset end
    if listOffset < 0 then listOffset = 0 end

    for i = 1, LIST_ROWS do
        local row = listRows[i]
        local index = i + listOffset
        local rule = rules[index]
        if rule then
            row.index = index
            row.enable:SetChecked(rule.enabled and true or false)
            row.name:SetText(Truncate(rule.name, 26))
            if rule.action == "HIDE" then
                row.chip:SetVertexColor(0.45, 0.45, 0.48, 1)
                row.score:SetText("hide")
                row.score:SetTextColor(0.55, 0.55, 0.58)
            else
                row.chip:SetVertexColor(0.35, 0.80, 0.45, 1)
                row.score:SetText(tostring(rule.score or 0))
                row.score:SetTextColor(0.92, 0.92, 0.92)
            end
            row.name:SetTextColor(rule.enabled and 0.95 or 0.5,
                rule.enabled and 0.95 or 0.5, rule.enabled and 0.95 or 0.5)
            row.select:SetShown(index == selected)
            row:Show()
        else
            row.index = nil
            row:Hide()
        end
    end
    editor.listCount:SetText(total .. " rules")
end

local function SelectRule(index)
    local rules = Rules()
    if index < 1 then index = 1 end
    if index > #rules then index = #rules end
    selected = index
    if selected < listOffset + 1 then listOffset = selected - 1 end
    if selected > listOffset + LIST_ROWS then listOffset = selected - LIST_ROWS end
    RefreshList()
    if editor and editor.RefreshInspector then editor.RefreshInspector() end
end

local function BuildListRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    row.select = row:CreateTexture(nil, "BACKGROUND")
    row.select:SetAllPoints()
    row.select:SetTexture(WHITE)
    row.select:SetVertexColor(1, 0.78, 0.2, 0.16)
    row.select:Hide()

    row.enable = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    row.enable:SetSize(20, 20)
    row.enable:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.enable:SetScript("OnClick", function(self)
        local rule = Rules()[row.index]
        if not rule then return end
        rule.enabled = self:GetChecked() and true or false
        Changed(rule)
        RefreshList()
    end)
    Tip(row.enable, "Enabled", "A disabled rule is skipped entirely: the auras it used to claim fall through to the rules below it.")

    row.chip = row:CreateTexture(nil, "ARTWORK")
    row.chip:SetSize(3, 14)
    row.chip:SetTexture(WHITE)
    row.chip:SetPoint("LEFT", row.enable, "RIGHT", 4, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.chip, "RIGHT", 6, 0)
    row.name:SetJustifyH("LEFT")

    row.score = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.score:SetPoint("RIGHT", row, "RIGHT", -6, 0)

    row:SetScript("OnClick", function(self)
        if self.index then SelectRule(self.index) end
    end)
    row:SetScript("OnEnter", function(self)
        if self.index ~= selected then self.select:SetAlpha(0.5); self.select:Show() end
    end)
    row:SetScript("OnLeave", function(self)
        self.select:SetAlpha(1)
        self.select:SetShown(self.index == selected)
    end)
    return row
end

-- ---------------------------------------------------------------------------
-- Live trace
-- ---------------------------------------------------------------------------

local function RefreshTrace()
    if not editor or not editor:IsShown() then return end
    if not CommanderBuffs_GetTrace then return end
    local auras, auraN, ranked = CommanderBuffs_GetTrace()
    local now = GetTime and GetTime() or 0
    local rules = Rules()

    -- The sentinel preview: exactly what slot 1 is drawing right now.
    local top = ranked and ranked[1]
    if top then
        editor.previewIcon:SetTexture(top.aura.icon)
        editor.previewIcon:Show()
        editor.previewName:SetText(Truncate(top.aura.name, 22))
        local remaining = E.Remaining(top.aura, now)
        editor.previewInfo:SetText(("score %d   %s"):format(top.score,
            remaining and (E.FormatTime(remaining) .. "s left") or "no timer"))
        local duration = top.aura.duration or 0
        if duration > 0 and remaining then
            editor.previewRing:SetCooldown(top.aura.expirationTime - duration, duration)
            editor.previewRing:Show()
        else
            editor.previewRing:Hide()
        end
    else
        editor.previewIcon:Hide()
        editor.previewRing:Hide()
        editor.previewName:SetText("(nothing shown)")
        editor.previewInfo:SetText("no aura clears Minimum Score")
    end

    -- Score/claim lookup for every aura, including the ones that were
    -- dropped — seeing WHY something is missing is the point of a trace.
    local scoreByAura, ruleByAura = {}, {}
    for _, entry in ipairs(ranked or {}) do
        scoreByAura[entry.aura] = entry.score
        ruleByAura[entry.aura] = entry.rule
    end

    local list = {}
    for i = 1, (auraN or 0) do
        local aura = auras[i]
        local rule = ruleByAura[aura]
        local claimed, claimIndex = E.Claim(rules, aura, now)
        list[#list + 1] = {
            aura = aura,
            score = scoreByAura[aura],
            rule = rule or claimed,
            ruleIndex = claimIndex,
            hidden = scoreByAura[aura] == nil,
        }
    end
    table.sort(list, function(a, b)
        local as = a.score or -1
        local bs = b.score or -1
        if as ~= bs then return as > bs end
        return (a.aura.name or "") < (b.aura.name or "")
    end)

    for i = 1, TRACE_ROWS do
        local row = traceRows[i]
        local item = list[i]
        if item then
            row.entry = item
            row.icon:SetTexture(item.aura.icon)
            row.name:SetText(Truncate(item.aura.name, 18))
            if item.hidden then
                row.name:SetTextColor(0.45, 0.45, 0.48)
                row.score:SetText("—")
                row.score:SetTextColor(0.45, 0.45, 0.48)
                row.icon:SetDesaturated(true)
            else
                row.name:SetTextColor(0.95, 0.95, 0.95)
                row.score:SetText(tostring(item.score))
                row.score:SetTextColor(1, 0.82, 0.3)
                row.icon:SetDesaturated(false)
            end
            local ruleName = item.rule and item.rule.name
                or (item.hidden and "no rule" or "unmatched")
            if item.rule and item.rule.action == "HIDE" then
                ruleName = "hidden by " .. item.rule.name
            end
            row.rule:SetText(Truncate(ruleName, 30))
            row.select:SetShown(traceSelected == item.aura.spellId)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
    editor.traceCount:SetText((auraN or 0) .. " auras on you")
end

local function BuildTraceRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -((index - 1) * ROW_H))
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    row.select = row:CreateTexture(nil, "BACKGROUND")
    row.select:SetAllPoints()
    row.select:SetTexture(WHITE)
    row.select:SetVertexColor(0.3, 0.8, 0.95, 0.18)
    row.select:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -1)
    row.name:SetJustifyH("LEFT")

    row.rule = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.rule:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 5, 1)
    row.rule:SetJustifyH("LEFT")

    row.score = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.score:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    -- Selection is stored as a SPELL ID, never as the aura table: aura
    -- tables are pooled and recycled on every scan, so holding one would
    -- silently start pointing at a different aura a moment later.
    row:SetScript("OnClick", function(self)
        if not self.entry then return end
        traceSelected = self.entry.aura.spellId
        RefreshTrace()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        local item = self.entry
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(item.aura.name)
        GameTooltip:AddDoubleLine("Spell id", tostring(item.aura.spellId), 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Type", item.aura.isHarmful and "Debuff" or "Buff", 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("School", E.SchoolOf(item.aura), 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("From me", item.aura.mine and "yes" or "no", 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Stacks", tostring(item.aura.stacks or 0), 0.6, 0.6, 0.6, 1, 1, 1)
        GameTooltip:AddDoubleLine("Duration",
            (item.aura.duration or 0) > 0 and (E.FormatTime(item.aura.duration) .. "s") or "none",
            0.6, 0.6, 0.6, 1, 1, 1)
        if item.rule then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Claimed by",
                ("#%d %s"):format(item.ruleIndex or 0, item.rule.name), 0.6, 0.6, 0.6, 1, 0.82, 0.3)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to select, then Capture to build a rule from it.", 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- ---------------------------------------------------------------------------
-- Inspector
-- ---------------------------------------------------------------------------

local function ColorOptions()
    local options = { { text = "None", value = "" } }
    for _, key in ipairs({ "RED", "GOLD", "GREEN", "CYAN", "PURPLE", "WHITE" }) do
        options[#options + 1] = {
            text = key:sub(1, 1) .. key:sub(2):lower(),
            value = key,
        }
    end
    -- Every Commander_Console suite tint too (the TopBar soft-fail pattern),
    -- so a rule's rim can match the rest of the interface.
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.r then
            options[#options + 1] = {
                text = (color.text or color.value):gsub("%s*%(.-%)$", ""),
                value = color.value,
            }
        end
    end
    return options
end

local function BuildInspector(parent)
    local widgets = {}
    local y = 0
    local function Place(widget, indent, dy)
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", indent or 0, y)
        y = y - (dy or 24)
        return widget
    end
    local function Gap(amount) y = y - (amount or 6) end

    local function rule() return Selected() end
    local function match()
        local r = rule()
        return r and r.match or {}
    end

    widgets.header = MakeHeader(parent, "Rule")
    Place(widgets.header, 0, 22)

    local nameBox = MakeEdit(parent, "Name",
        "What this rule is for. Names are for you — the engine never reads them.",
        function() local r = rule(); return r and r.name end,
        function(text)
            local r = rule()
            if not r then return end
            r.name = (text ~= "" and text) or "Rule"
            Changed(r)
            RefreshList()
        end, 210)
    nameBox._label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y - 3)
    nameBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 42, y)
    y = y - 24

    local enabled = MakeCheck(parent, "Enabled",
        "Skip this rule entirely when off.",
        function() local r = rule(); return r and r.enabled end,
        function(value)
            local r = rule()
            if not r then return end
            r.enabled = value
            Changed(r)
            RefreshList()
        end)
    enabled:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y + 2)

    local action = MakeCycle(parent, "Action",
        "Show scores the aura and lets it compete for the portrait. Hide claims it and drops it — a one-line veto that also removes it from the block when Block Contents is not Everything.",
        { { text = "Show", value = "SHOW" }, { text = "Hide", value = "HIDE" } },
        function() local r = rule(); return r and r.action end,
        function(value)
            local r = rule()
            if not r then return end
            r.action = value
            Changed(r)
            RefreshList()
        end, 120)
    action:SetPoint("TOPLEFT", parent, "TOPLEFT", 120, y)
    y = y - 26
    Gap(2)

    widgets.matchHeader = MakeHeader(parent, "Match")
    Place(widgets.matchHeader, 0, 20)

    local auraType = MakeCycle(parent, "Type",
        "Which side of the stack this rule looks at.",
        { { text = "Any", value = "ANY" }, { text = "Buff", value = "BUFF" },
          { text = "Debuff", value = "DEBUFF" } },
        function() return match().auraType end,
        function(value) local r = rule(); if r then r.match.auraType = value; Changed(r) end end,
        110)
    auraType:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)

    local source = MakeCycle(parent, "From",
        "Who applied it. Mine covers you and your pet.",
        { { text = "Anyone", value = "ANY" }, { text = "Me", value = "MINE" },
          { text = "Others", value = "OTHER" } },
        function() return match().source end,
        function(value) local r = rule(); if r then r.match.source = value; Changed(r) end end,
        120)
    source:SetPoint("TOPLEFT", parent, "TOPLEFT", 116, y)
    y = y - 26

    local idBox = MakeEdit(parent, "Ids",
        "Spell ids, comma or space separated. Present means the aura MUST be one of them — the strongest and most locale-proof matcher there is. Every rank of a spell shares its base id. Select an aura in the trace and press Capture to fill this in for you.",
        function() return E.FormatSpellIds(match().spellIds) end,
        function(text)
            local r = rule()
            if not r then return end
            r.match.spellIds = E.ParseSpellIds(text)
            Changed(r)
        end, 210)
    idBox._label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y - 3)
    idBox:SetPoint("TOPLEFT", parent, "TOPLEFT", 42, y)
    y = y - 24

    local nameFrag = MakeEdit(parent, "Text",
        "Case-insensitive fragment of the aura's name. Handy for families the ids do not cover, but it does not travel across languages — prefer ids.",
        function() return match().namePart end,
        function(text)
            local r = rule()
            if not r then return end
            r.match.namePart = text or ""
            Changed(r)
        end, 210)
    nameFrag._label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y - 3)
    nameFrag:SetPoint("TOPLEFT", parent, "TOPLEFT", 42, y)
    y = y - 26

    local schoolLabel = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    schoolLabel:SetText("School")
    schoolLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y - 4)

    local SCHOOL_LABELS = {
        { key = "Magic", text = "Mag" }, { key = "Curse", text = "Cur" },
        { key = "Disease", text = "Dis" }, { key = "Poison", text = "Poi" },
        { key = "NONE", text = "None" },
    }
    local schoolX = 46
    for _, school in ipairs(SCHOOL_LABELS) do
        local check = MakeCheck(parent, school.text,
            "Restrict this rule to the " .. school.key .. " school. With none of the five ticked the rule ignores schools entirely; None means an undispellable aura.",
            function() local m = match(); return m.dispel and m.dispel[school.key] end,
            function(value)
                local r = rule()
                if not r then return end
                r.match.dispel = r.match.dispel or {}
                r.match.dispel[school.key] = value or nil
                Changed(r)
            end)
        check:SetPoint("TOPLEFT", parent, "TOPLEFT", schoolX, y + 2)
        schoolX = schoolX + 58
    end
    y = y - 26

    local bossOnly = MakeCheck(parent, "Boss",
        "Only auras the client flags as coming from a boss.",
        function() return match().bossOnly end,
        function(value) local r = rule(); if r then r.match.bossOnly = value; Changed(r) end end)
    bossOnly:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y + 2)

    local stealable = MakeCheck(parent, "Stealable",
        "Only auras a mage could spellsteal or a dispel could strip from you.",
        function() return match().stealableOnly end,
        function(value) local r = rule(); if r then r.match.stealableOnly = value; Changed(r) end end)
    stealable:SetPoint("TOPLEFT", parent, "TOPLEFT", 76, y + 2)

    local permanent = MakeCheck(parent, "No timer",
        "Only auras with no duration at all — auras, presences, forms, the things that are simply always on.",
        function() return match().permanentOnly end,
        function(value) local r = rule(); if r then r.match.permanentOnly = value; Changed(r) end end)
    permanent:SetPoint("TOPLEFT", parent, "TOPLEFT", 182, y + 2)
    y = y - 28

    local function DurationField(labelText, key, tooltip, x)
        local box = MakeEdit(parent, labelText, tooltip,
            function()
                local value = match()[key]
                return value and tostring(value) or ""
            end,
            function(text)
                local r = rule()
                if not r then return end
                r.match[key] = tonumber(text) or nil
                Changed(r)
            end, 48)
        box._label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 3)
        box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 62, y)
        return box
    end
    DurationField("Min secs", "minDuration",
        "Only auras whose FULL duration is at least this many seconds — how the shipped rule hides long raid buffs. A duration window never matches an aura with no timer; use No timer for those.", 2)
    DurationField("Max secs", "maxDuration",
        "Only auras whose FULL duration is at most this many seconds — how the shipped rule finds your own short cooldown buffs.", 160)
    y = y - 26

    local stacks = MakeSlider(parent, "Stacks", "Only auras stacked at least this high.",
        0, 20, 1,
        function() return match().minStacks or 0 end,
        function(value) local r = rule(); if r then r.match.minStacks = value; Changed(r) end end)
    stacks._label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y - 2)
    stacks:SetPoint("TOPLEFT", parent, "TOPLEFT", 80, y - 2)
    stacks._value:SetPoint("LEFT", stacks, "RIGHT", 8, 0)
    y = y - 28
    Gap(2)

    widgets.scoreHeader = MakeHeader(parent, "Priority")
    Place(widgets.scoreHeader, 0, 20)

    local function ScoreSlider(labelText, tooltip, min, max, step, get, set)
        local slider = MakeSlider(parent, labelText, tooltip, min, max, step, get, set)
        slider._label:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, y - 2)
        slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 80, y - 2)
        slider._value:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        y = y - 26
        return slider
    end

    ScoreSlider("Score", "The base priority every aura this rule claims gets. The highest final score in your stack wins the portrait; Minimum Score on the settings page decides how high is high enough to show at all.",
        0, 150, 5,
        function() local r = rule(); return r and r.score or 0 end,
        function(value)
            local r = rule()
            if not r then return end
            r.score = value
            Changed(r)
            RefreshList()
        end)

    ScoreSlider("Urgent at", "Seconds remaining at which this rule's urgency bonus kicks in. Zero turns the bonus off.",
        0, 30, 1,
        function() local r = rule(); return r and r.expiringUnder or 0 end,
        function(value) local r = rule(); if r then r.expiringUnder = value; Changed(r) end end)

    ScoreSlider("Urgent +", "How much score to add once the aura is inside that window. This is what lets a fading Ice Block outrank a fresh one.",
        0, 100, 5,
        function() local r = rule(); return r and r.expiringBonus or 0 end,
        function(value) local r = rule(); if r then r.expiringBonus = value; Changed(r) end end)

    ScoreSlider("Per stack", "Score added for each application beyond the first — how a debuff stacking toward a kill climbs the list on its own.",
        0, 20, 1,
        function() local r = rule(); return r and r.stackBonus or 0 end,
        function(value) local r = rule(); if r then r.stackBonus = value; Changed(r) end end)

    local color = MakeCycle(parent, "Rim",
        "Rim color for the portrait icon when this rule wins. None keeps the automatic coloring: dispel school for debuffs, gold for your own buffs.",
        ColorOptions(),
        function() local r = rule(); return r and (r.color or "") end,
        function(value)
            local r = rule()
            if not r then return end
            r.color = value ~= "" and value or nil
            Changed(r)
        end, 200)
    color:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    y = y - 26

    return widgets
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function ApplyFraming()
    if not editor then return end
    local db = DB()
    local style = db and db.EditorStyle or "WINDOW"
    local windowArt = style == "WINDOW"
    if editor.NineSlice then editor.NineSlice:SetShown(windowArt) end
    if editor.Bg then editor.Bg:SetShown(windowArt) end
    if editor.TitleBg then editor.TitleBg:SetShown(windowArt) end
    if editor.TitleText then editor.TitleText:SetShown(windowArt) end
    if editor.CloseButton then editor.CloseButton:SetShown(windowArt) end
    if editor.Inset then editor.Inset:SetShown(windowArt) end
    if Commander and Commander.UI and Commander.UI.ApplyStyleBackdrop then
        Commander.UI.ApplyStyleBackdrop(editor, windowArt and "NONE" or style)
    end
end

local function ApplyPosition()
    if not editor then return end
    local db = DB()
    local scale = (db and db.EditorScale) or 1
    editor:SetScale(scale)
    if editor._dragging then return end
    editor:ClearAllPoints()
    local pos = db and db.EditorPos
    if pos and pos.point then
        editor:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        editor:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

local function EnsureEditor()
    if editor then return editor end

    editor = CreateFrame("Frame", "CommanderBuffsEditorFrame", UIParent, "BasicFrameTemplateWithInset")
    editor:SetSize(FRAME_W, FRAME_H)
    editor:SetFrameStrata("MEDIUM")
    editor:SetToplevel(true)
    editor:SetMovable(true)
    editor:SetClampedToScreen(true)
    editor:Hide()
    if editor.TitleText then editor.TitleText:SetText("Buffs — Priority Editor") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderBuffsEditorFrame") end

    local drag = CreateFrame("Frame", nil, editor)
    drag:SetPoint("TOPLEFT", editor, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        editor._dragging = true
        editor:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        editor:StopMovingOrSizing()
        editor._dragging = false
        local point, _, _, x, y = editor:GetPoint(1)
        local db = DB()
        if point and db then
            local scale = editor:GetScale() or 1
            db.EditorPos = { point = point, x = x * scale, y = y * scale }
        end
    end)

    -- ---- Left column: the ordered policy --------------------------------
    local listHeader = editor:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -32)
    listHeader:SetText("Priority Rules")

    editor.listCount = editor:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    editor.listCount:SetPoint("LEFT", listHeader, "RIGHT", 8, 0)

    local listNote = editor:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    listNote:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -3)
    listNote:SetText("First rule that matches an aura claims it.")

    local listArea = CreateFrame("Frame", nil, editor)
    listArea:SetPoint("TOPLEFT", editor, "TOPLEFT", 14, -68)
    listArea:SetSize(300, LIST_ROWS * ROW_H)
    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        listOffset = listOffset - delta
        RefreshList()
    end)
    for i = 1, LIST_ROWS do listRows[i] = BuildListRow(listArea, i) end

    local function ListButton(text, tooltip, x, row, onClick)
        local button = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
        button:SetSize(72, 20)
        button:SetPoint("TOPLEFT", listArea, "BOTTOMLEFT", x, -6 - (row - 1) * 24)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        Tip(button, text, tooltip)
        return button
    end

    ListButton("New", "Add an empty rule at the end of the list and select it.", 0, 1, function()
        local rules = Rules()
        rules[#rules + 1] = E.NewRule(rules)
        Repaint()
        SelectRule(#rules)
    end)
    ListButton("Duplicate", "Copy the selected rule directly below it — the fastest way to build a family of related rules.", 76, 1, function()
        if E.DuplicateRule(Rules(), selected) then
            Repaint()
            SelectRule(selected + 1)
        end
    end)
    ListButton("Delete", "Remove the selected rule. Auras it used to claim fall through to the rules below.", 152, 1, function()
        if E.DeleteRule(Rules(), selected) then
            Repaint()
            SelectRule(math.min(selected, #Rules()))
        end
    end)
    ListButton("Move Up", "Raise the selected rule's priority: it now sees auras before the rule above it did.", 0, 2, function()
        if E.MoveRule(Rules(), selected, -1) then
            Repaint()
            SelectRule(selected - 1)
        end
    end)
    ListButton("Move Down", "Lower the selected rule so the rule below it gets first look.", 76, 2, function()
        if E.MoveRule(Rules(), selected, 1) then
            Repaint()
            SelectRule(selected + 1)
        end
    end)
    ListButton("Defaults", "Replace the WHOLE list with the nine shipped rules. This is the only thing that ever destroys your rules — the settings page's Restore Defaults leaves them alone.", 152, 2, function()
        local db = DB()
        if not db then return end
        db.Rules = E.DefaultRules()
        E.NormalizeRules(db.Rules)
        print("|cff66ccffCommander Buffs|r: priority rules restored to the shipped nine")
        Repaint()
        SelectRule(1)
    end)

    -- ---- Center column: the inspector -----------------------------------
    local inspector = CreateFrame("Frame", nil, editor)
    inspector:SetPoint("TOPLEFT", editor, "TOPLEFT", 330, -32)
    inspector:SetSize(300, FRAME_H - 80)
    BuildInspector(inspector)

    local divider = editor:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(WHITE)
    divider:SetVertexColor(1, 1, 1, 0.10)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", editor, "TOPLEFT", 320, -30)
    divider:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 320, 16)

    local divider2 = editor:CreateTexture(nil, "ARTWORK")
    divider2:SetTexture(WHITE)
    divider2:SetVertexColor(1, 1, 1, 0.10)
    divider2:SetWidth(1)
    divider2:SetPoint("TOPLEFT", editor, "TOPLEFT", 646, -30)
    divider2:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 646, 16)

    -- ---- Right column: the live trace -----------------------------------
    local traceHeader = editor:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    traceHeader:SetPoint("TOPLEFT", editor, "TOPLEFT", 662, -32)
    traceHeader:SetText("Live Trace")

    editor.traceCount = editor:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    editor.traceCount:SetPoint("LEFT", traceHeader, "RIGHT", 8, 0)

    -- The sentinel preview: the same aura, the same ring, drawn big enough
    -- to judge. Seeing the outcome next to the policy is the whole point.
    local preview = CreateFrame("Frame", nil, editor)
    preview:SetPoint("TOPLEFT", editor, "TOPLEFT", 662, -52)
    preview:SetSize(280, 52)

    editor.previewIcon = preview:CreateTexture(nil, "ARTWORK")
    editor.previewIcon:SetSize(40, 40)
    editor.previewIcon:SetPoint("LEFT", preview, "LEFT", 4, 0)
    editor.previewIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    editor.previewRing = CreateFrame("Cooldown", nil, preview, "CooldownFrameTemplate")
    editor.previewRing:SetPoint("TOPLEFT", editor.previewIcon, "TOPLEFT", -3, 3)
    editor.previewRing:SetPoint("BOTTOMRIGHT", editor.previewIcon, "BOTTOMRIGHT", 3, -3)
    if editor.previewRing.SetHideCountdownNumbers then
        editor.previewRing:SetHideCountdownNumbers(true)
    end
    if editor.previewRing.SetDrawEdge then editor.previewRing:SetDrawEdge(false) end
    if editor.previewRing.SetSwipeTexture then
        editor.previewRing:SetSwipeTexture("Interface\\AddOns\\Commander_Buffs\\Textures\\Ring.png")
        if editor.previewRing.SetSwipeColor then
            editor.previewRing:SetSwipeColor(1, 0.82, 0.3, 0.95)
        end
    end

    local previewCaption = preview:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    previewCaption:SetPoint("TOPLEFT", editor.previewIcon, "TOPRIGHT", 8, -2)
    previewCaption:SetText("On your portrait now")

    editor.previewName = preview:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    editor.previewName:SetPoint("TOPLEFT", previewCaption, "BOTTOMLEFT", 0, -2)

    editor.previewInfo = preview:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    editor.previewInfo:SetPoint("TOPLEFT", editor.previewName, "BOTTOMLEFT", 0, -2)

    local traceArea = CreateFrame("Frame", nil, editor)
    traceArea:SetPoint("TOPLEFT", editor, "TOPLEFT", 662, -110)
    traceArea:SetSize(282, TRACE_ROWS * ROW_H)
    for i = 1, TRACE_ROWS do traceRows[i] = BuildTraceRow(traceArea, i) end

    local capture = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    capture:SetSize(130, 20)
    capture:SetPoint("TOPLEFT", traceArea, "BOTTOMLEFT", 0, -8)
    capture:SetText("Capture Rule")
    Tip(capture, "Capture Rule",
        "Build a new rule from the aura selected in the trace: its spell id, its side of the stack, and a score above everything else, inserted at the TOP of the list so it wins immediately. Then tune it in the inspector.")
    capture:SetScript("OnClick", function()
        local picked
        if traceSelected and CommanderBuffs_GetTrace then
            local auras, auraN = CommanderBuffs_GetTrace()
            for i = 1, (auraN or 0) do
                if auras[i].spellId == traceSelected then picked = auras[i] end
            end
        end
        if not picked then
            print("|cff66ccffCommander Buffs|r: select an aura in the trace first")
            return
        end
        local rules = Rules()
        local rule = E.NewRule(rules, picked.name)
        rule.match.spellIds = { picked.spellId }
        rule.match.auraType = picked.isHarmful and "DEBUFF" or "BUFF"
        rule.score = 110
        E.NormalizeRule(rule, rules)
        table.insert(rules, 1, rule)
        Repaint()
        SelectRule(1)
    end)

    local testButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    testButton:SetSize(110, 20)
    testButton:SetPoint("LEFT", capture, "RIGHT", 8, 0)
    testButton:SetText("Test Stack")
    Tip(testButton, "Test Stack",
        "Seed a fake aura stack for 15 seconds so the trace has something to show — and so you can shape rules without waiting to be hit by the thing you are writing a rule about.")
    testButton:SetScript("OnClick", function()
        if CommanderBuffs_Test then CommanderBuffs_Test() end
    end)

    local settingsButton = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
    settingsButton:SetSize(110, 20)
    settingsButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -14, 14)
    settingsButton:SetText("Settings")
    Tip(settingsButton, "Settings", "Open the Commander Buffs settings page — sizes, placement, and how quiet the sentinel is.")
    settingsButton:SetScript("OnClick", function()
        if Commander and Commander.OpenModuleSettings then
            Commander.OpenModuleSettings("Buffs")
        end
    end)

    editor.RefreshInspector = function()
        for _, refresh in ipairs(inspectorRefreshers) do pcall(refresh) end
    end

    editor:SetScript("OnShow", function()
        ApplyFraming()
        ApplyPosition()
        E.NormalizeRules(Rules())
        SelectRule(selected)
        RefreshTrace()
    end)

    -- The trace is a live readout, so it needs its own heartbeat: aura
    -- timers tick down with no event to announce it.
    editor:SetScript("OnUpdate", function(_, elapsed)
        lastTrace = lastTrace + elapsed
        if lastTrace < 0.2 then return end
        lastTrace = 0
        RefreshTrace()
    end)

    ApplyFraming()
    ApplyPosition()
    return editor
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

function CommanderBuffs_ToggleEditor()
    local db = DB()
    if not db then return end
    if not db.EnableBuffs then
        print("Commander Buffs is disabled — enable it in its settings panel")
        return
    end
    EnsureEditor()
    if editor:IsShown() then editor:Hide() else editor:Show() end
end

-- Called by the render layer after every refresh, so an aura landing on you
-- shows up in the trace at the same instant it shows up on your portrait.
function CommanderBuffsEditor_Repaint()
    if editor and editor:IsShown() then
        RefreshList()
        RefreshTrace()
    end
end

-- Settings that describe the window itself (style, scale, position reset)
-- arrive on the module event like every other setting in the suite.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    Commander.AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, function()
        if not editor then return end
        ApplyFraming()
        ApplyPosition()
    end)
end)

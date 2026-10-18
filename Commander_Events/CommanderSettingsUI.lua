-- Commander.UI: shared settings-panel framework for the Commander suite.
--
-- Every module builds its options page through UI.NewPanel, which provides a
-- consistent header (title, version, description), uniformly spaced widgets
-- that re-sync themselves from the module DB whenever the module's update
-- event fires (or the panel is shown), dependent enable/disable states, a
-- standard "Restore Defaults" footer, and standardized slash commands.
--
-- Every page also SCROLLS, from here rather than from each module. A canvas
-- subcategory is handed a fixed viewport and simply clips whatever runs past
-- it — no scrollbar, no error, just options that stop existing, and since
-- Finalize adds the footer last the first casualty of an overlong page is
-- Restore Defaults. Modules used to each grow their own copy of the scroll
-- frame to escape that, which meant the next page to grow one option too
-- many quietly lost its tail; NewPanel builds it for all of them now. The
-- header stays on the canvas above the scroll, so title, version and
-- description hold still while the options move under them.
--
-- One consequence for module code: anything you hang on the page yourself
-- belongs on the ROW it relates to, not on the panel frame — the panel is
-- the fixed viewport, and a widget parented there holds still while the
-- control it belongs to scrolls away underneath it.
--
-- Panels register themselves in the Commander module registry
-- (Commander.RegisterModule / Commander.GetModules) so suite-level UIs such
-- as Commander_Suite can enumerate every installed module.

Commander = Commander or {}
Commander.UI = Commander.UI or {}
-- Which foldouts are open, per page. Declared here so it exists before any
-- module builds a page; the client's saved copy replaces it at ADDON_LOADED.
CommanderUIDB = CommanderUIDB or {}

local UI = Commander.UI

-- ---------------------------------------------------------------------------
-- Module registry
-- ---------------------------------------------------------------------------

local modules = {}

function Commander.RegisterModule(info)
    if info and info.key then
        modules[info.key] = info
    end
end

function Commander.GetModules()
    local list = {}
    for _, info in pairs(modules) do
        list[#list + 1] = info
    end
    table.sort(list, function(a, b) return (a.title or "") < (b.title or "") end)
    return list
end

-- Open a registered module's settings page by its panel key (e.g. "Buffs").
-- Returns false when the module is not loaded or not yet registered.
function Commander.OpenModuleSettings(key)
    local info = modules[key]
    if info and info.categoryID then
        Settings.OpenToCategory(info.categoryID)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Layout constants
-- ---------------------------------------------------------------------------

local LEFT_MARGIN = 16
local RIGHT_MARGIN = 16
local ROW_SPACING = 6
-- Room under the last row so the footer never sits flush against the bottom
local SCROLL_BOTTOM_PAD = 24
-- The scrollbar lives in this strip on the right of the canvas
local SCROLLBAR_GUTTER = 28
local SLIDER_WIDTH = 280
local DROPDOWN_WIDTH = 180
local DISABLED_ALPHA = 0.4

local dropdownCounter = 0

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- text may be a function: evaluated on hover, so tooltips can reflect
-- current state (return nil to show just the title). anchor overrides the
-- default ANCHOR_RIGHT for widgets living near the right screen edge.
local function AttachTooltip(widget, title, text, anchor)
    if not title and not text then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "", 1, 1, 1)
        local body = text
        if type(body) == "function" then
            body = body()
        end
        if body then
            GameTooltip:AddLine(body, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Shared so suite-level UIs (Commander_Suite) show tooltips identically
UI.AttachTooltip = AttachTooltip

local function FormatValue(fmt, value)
    if type(fmt) == "function" then
        return fmt(value)
    end
    return string.format(fmt or "%.1f", value)
end

-- Standard slider format for 0..N scale/opacity values shown as percentages
function UI.FormatPercent(value)
    return string.format("%d%%", value * 100 + 0.5)
end

local function CopyValue(value)
    if type(value) == "table" then
        local copy = {}
        for k, v in pairs(value) do
            copy[k] = CopyValue(v)
        end
        return copy
    end
    return value
end

UI.CopyValue = CopyValue

-- Fill in missing keys from a defaults table (deep-copying table values so
-- the shared defaults are never aliased into SavedVariables)
function UI.ApplyDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            db[key] = CopyValue(value)
        end
    end
end

-- Overwrite every defaulted key; iterates the defaults table so a newly
-- added setting can never be silently skipped by a hand-written reset list
function UI.ResetToDefaults(db, defaults)
    for key, value in pairs(defaults) do
        db[key] = CopyValue(value)
    end
end

-- ---------------------------------------------------------------------------
-- Panel methods
-- ---------------------------------------------------------------------------

local PanelMethods = {}

-- Create a full-width row container of the given height, flowing below the
-- previously added row.
--
-- Rows live in the page's scroll child, not on the canvas: the Settings
-- window hands a canvas page a fixed height and simply CLIPS whatever runs
-- past it, so a page that grew one option too many lost its footer — and
-- with it Restore Defaults — with no scrollbar and no warning. The child is
-- the full width of the viewport, so a row still spans the page.
function PanelMethods.AddRow(panel, height, spacing)
    local host = panel._content or panel
    local row = CreateFrame("Frame", nil, host)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", panel._anchor, "BOTTOMLEFT", 0, -(spacing or ROW_SPACING))
    -- The scroll child already sits inside the page margins; the bare canvas
    -- (a panel built before its scroll frame exists) still needs them
    row:SetPoint("RIGHT", host, "RIGHT", panel._content and 0 or -RIGHT_MARGIN, 0)
    panel._anchor = row
    -- Every row is remembered in order, with the foldout it was added under,
    -- so a page that uses foldouts can re-flow itself (Relayout). A page that
    -- never calls AddFoldout never re-flows, and lays out exactly as before.
    panel._rows = panel._rows or {}
    local entry = { row = row, spacing = spacing or ROW_SPACING, fold = panel._fold }
    panel._rows[#panel._rows + 1] = entry
    row._panelEntry = entry
    -- Running total of what has been flowed. A panel that scrolls its rows
    -- needs it to size the scroll child; GrowRow keeps it honest when a row
    -- turns out taller than it could be declared. Tracked here so GrowRow's
    -- contract is the same whether or not the caller overrode AddRow.
    panel._contentHeight = (panel._contentHeight or 0) + height + (spacing or ROW_SPACING)
    return row
end

-- Grow a row after the fact, keeping the panel's running content height in
-- step. AddRow has to commit a height before its contents exist, so anything
-- whose real size depends on text wrapping has to come back and correct it —
-- and a panel that flows its rows into a scroll frame is tracking that total.
function PanelMethods.GrowRow(panel, row, height)
    local cur = row:GetHeight() or 0
    if not height or height <= cur then return end
    row:SetHeight(height)
    -- A folding page recounts its whole height on every Relayout (a row in a
    -- closed foldout takes no room at all), so a running total would only
    -- double-count
    if panel._hasFolds then
        -- Grown outside a refresh (a live readout on a ticker): re-flow now,
        -- or everything under it overlaps until the next one
        if not panel._loading then panel:Relayout() end
        return
    end
    if panel._contentHeight then
        panel._contentHeight = panel._contentHeight + (height - cur)
    end
end

-- Size the scroll child to what has actually been flowed into it. Called
-- from Finalize and again on every Refresh, because GrowRow only learns a
-- wrapped section note's real height once the page has a resolved width —
-- latching the build-time number would leave the last rows unreachable.
function PanelMethods.ResizeScroll(panel)
    if not panel._content then return end
    panel._content:SetHeight((panel._contentHeight or 0) + SCROLL_BOTTOM_PAD)
    -- Width normally arrives through the scroll frame's OnSizeChanged, but a
    -- page whose size settled before the child existed never fires one, and a
    -- zero-width child draws the whole page as a column of invisible frames.
    -- Re-asserting it here is idempotent and costs a single call.
    local width = panel._scroll and panel._scroll:GetWidth()
    if width and width > 1 then panel._content:SetWidth(width) end
end

-- Every section is a FOLDOUT unless the page opted out (NewPanel's
-- foldSections = false) or this one asked to stay a plain heading
-- (opts.plain). A page with only a few sections opens them all by default;
-- a longer one opens its first and remembers the rest as they are left.
function PanelMethods.AddSection(panel, text, subtext, opts)
    if not (opts and opts.plain) and panel._autoFold and panel.AddRow == PanelMethods.AddRow then
        local fold = panel:AddFoldout(text, subtext, { key = text, auto = true })
        return fold.header
    end
    local row = panel:AddRow(subtext and 40 or 24, 14)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
    label:SetText(text)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("LEFT", label, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    if subtext then
        local note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        note:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        note:SetJustifyH("LEFT")
        note:SetTextColor(0.75, 0.75, 0.75)
        note:SetText(subtext)
        -- Two lines is all the 40 above pays for. A longer note draws straight
        -- over whatever control comes next, which is not a subtle failure — it
        -- is a checkbox sitting on top of a paragraph. The wrapped height is
        -- only knowable once the panel has a real width, so it is measured on
        -- refresh rather than here.
        --
        -- Measured on EVERY refresh, and deliberately not latched after the
        -- first. Panel:Refresh() is called once at BUILD time, before this
        -- page has ever been shown and therefore before its rows have a
        -- resolved width — and a fontstring with no width to wrap into
        -- reports its height as a single line. Latching that first answer
        -- pinned every long note to two lines' worth of row for the life of
        -- the session, which is exactly the overlap the row growth exists to
        -- prevent. Re-measuring is cheap (refreshers run on show and on a
        -- settings change, not per frame) and GrowRow only ever grows, so the
        -- reading taken with a real width is the one that wins and repeating
        -- it is idempotent.
        panel:AddRefresher(function()
            if not note.GetStringHeight then return end
            -- A row with no resolved width yet cannot wrap, so its answer
            -- would be the single-line one. Wait for a real page.
            local w = row.GetWidth and row:GetWidth() or 0
            if w <= 1 then return end
            local h = note:GetStringHeight()
            if not h or h <= 0 then return end
            panel:GrowRow(row, 22 + math.ceil(h) + 6)
        end)
    end
    return row
end

function PanelMethods.AddSpacer(panel, height)
    return panel:AddRow(height or 8, 0)
end

-- What a search box matches a row against: every control's label and
-- tooltip, lower-cased. Public as TagRow for rows a module builds itself.
local function Tag(row, ...)
    local parts = { row._keywords or "" }
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        if type(text) == "string" then parts[#parts + 1] = text:lower() end
    end
    row._keywords = table.concat(parts, " ")
end

function PanelMethods.TagRow(panel, row, ...)
    Tag(row, ...)
end

local function BuildCheckbox(panel, row, opts, xOffset)
    Tag(row, opts.label, opts.tooltip)
    local check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("LEFT", row, "LEFT", xOffset or 0, 0)
    check.Text:SetText(opts.label)
    AttachTooltip(check, opts.label, opts.tooltip)

    check:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if checked then
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        else
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        opts.set(checked)
        panel:_Changed()
    end)

    panel:AddRefresher(function()
        check:SetChecked(opts.get() and true or false)
        local enabled = not opts.isEnabled or opts.isEnabled()
        check:SetEnabled(enabled)
        check:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    end)

    return check
end

-- opts: label, tooltip, get, set, isEnabled
function PanelMethods.AddCheckbox(panel, opts)
    local row = panel:AddRow(26, 2)
    return BuildCheckbox(panel, row, opts, 0)
end

-- Two compact checkboxes sharing one row — for long toggle lists that would
-- otherwise blow the page's no-scroll height budget. Each opts table is the
-- same shape AddCheckbox takes; right may be nil for an odd final entry.
function PanelMethods.AddCheckboxPair(panel, left, right)
    local row = panel:AddRow(26, 2)
    local leftCheck = BuildCheckbox(panel, row, left, 0)
    local rightCheck = right and BuildCheckbox(panel, row, right, 270) or nil
    return leftCheck, rightCheck
end

-- opts: label, tooltip, min, max, step, get, set, format, isEnabled
local function BuildSlider(panel, row, opts, xOffset, width)
    Tag(row, opts.label, opts.tooltip)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset + 2, 0)
    label:SetText(opts.label)

    -- Hand-rolled slider: the deprecated OptionsSliderTemplate draws its
    -- track via NineSlice "SliderBar" atlas pieces, which do not render
    -- reliably on this client. Blizzard's own sanctioned alternative (used
    -- by its TBC credits screen) is a Slider inheriting BackdropTemplate
    -- with the BACKDROP_SLIDER_8_8 track, so draw it that way ourselves.
    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset + 2, -18)
    slider:SetSize(width, 17)
    slider:SetHitRectInsets(0, 0, -10, -10)
    slider:SetBackdrop(BACKDROP_SLIDER_8_8 or {
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileEdge = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(32, 32)
    end
    slider:SetMinMaxValues(opts.min, opts.max)
    slider:SetValueStep(opts.step)
    slider:SetObeyStepOnDrag(true)

    local lowText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    lowText:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 2, -1)
    lowText:SetText(FormatValue(opts.format, opts.min))
    local highText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    highText:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", -2, -1)
    highText:SetText(FormatValue(opts.format, opts.max))
    AttachTooltip(slider, opts.label, opts.tooltip)

    local valueText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    valueText:SetPoint("LEFT", slider, "RIGHT", 14, 0)

    local function Snap(value)
        local snapped = opts.min + math.floor((value - opts.min) / opts.step + 0.5) * opts.step
        -- Clean up float drift so saved values stay tidy (e.g. 0.7000000001)
        snapped = math.floor(snapped * 10000 + 0.5) / 10000
        if snapped < opts.min then snapped = opts.min end
        if snapped > opts.max then snapped = opts.max end
        return snapped
    end

    slider:SetScript("OnValueChanged", function(self, value)
        local snapped = Snap(value)
        valueText:SetText(FormatValue(opts.format, snapped))
        if panel._loading then return end
        if self._lastValue == snapped then return end
        self._lastValue = snapped
        opts.set(snapped)
        -- Sliders fire continuously during a drag; coalesce the module
        -- notifies so expensive apply paths run a few times per second
        -- instead of once per pixel (the DB write above is immediate)
        panel:_ChangedThrottled()
    end)

    panel:AddRefresher(function()
        local value = Snap(tonumber(opts.get()) or opts.min)
        slider._lastValue = value
        slider:SetValue(value)
        valueText:SetText(FormatValue(opts.format, value))
        local enabled = not opts.isEnabled or opts.isEnabled()
        if enabled then slider:Enable() else slider:Disable() end
        local alpha = enabled and 1 or DISABLED_ALPHA
        slider:SetAlpha(alpha)
        label:SetAlpha(alpha)
        valueText:SetAlpha(alpha)
        lowText:SetAlpha(alpha)
        highText:SetAlpha(alpha)
    end)

    return slider
end

function PanelMethods.AddSlider(panel, opts)
    local row = panel:AddRow(52, 8)
    return BuildSlider(panel, row, opts, 0, SLIDER_WIDTH)
end

-- Two compact sliders sharing one row — same budget trick as
-- AddCheckboxPair. Each opts table is the AddSlider shape; right may be
-- nil for an odd final entry.
function PanelMethods.AddSliderPair(panel, left, right)
    local row = panel:AddRow(52, 8)
    local leftSlider = BuildSlider(panel, row, left, 0, 170)
    local rightSlider = right and BuildSlider(panel, row, right, 270, 170) or nil
    return leftSlider, rightSlider
end

-- opts: label, tooltip, options ({text=, value=}...), get, set, width,
--       isEnabled, onSelect
local function BuildDropdown(panel, row, opts, xOffset, defaultWidth)
    Tag(row, opts.label, opts.tooltip)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset + 2, 0)
    label:SetText(opts.label)

    -- UIDropDownMenu_EnableDropDown/DisableDropDown resolve child regions via
    -- _G[frame:GetName()..suffix] on this client, so the frame must have a
    -- unique global name.
    dropdownCounter = dropdownCounter + 1
    local dropdown = CreateFrame("Frame", "CommanderUIDropDown" .. dropdownCounter, row, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", row, "TOPLEFT", xOffset - 14, -14)
    UIDropDownMenu_SetWidth(dropdown, opts.width or defaultWidth)
    -- The template's arrow button forwards OnEnter/OnLeave to the parent, but
    -- only covers its own 24px; enable mouse on the container so the tooltip
    -- also shows when hovering the dropdown's text area
    if opts.tooltip then
        dropdown:EnableMouse(true)
    end
    AttachTooltip(dropdown, opts.label, opts.tooltip)

    local function TextForValue(value)
        for _, option in ipairs(opts.options) do
            if option.value == value then
                return option.text
            end
        end
        return ""
    end

    UIDropDownMenu_Initialize(dropdown, function()
        local current = opts.get()
        for _, option in ipairs(opts.options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (option.value == current)
            info.func = function(button)
                UIDropDownMenu_SetSelectedValue(dropdown, button.value)
                UIDropDownMenu_SetText(dropdown, TextForValue(button.value))
                opts.set(button.value)
                panel:_Changed()
                if opts.onSelect then
                    opts.onSelect(button.value)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    panel:AddRefresher(function()
        local value = opts.get()
        UIDropDownMenu_SetSelectedValue(dropdown, value)
        UIDropDownMenu_SetText(dropdown, TextForValue(value))
        local enabled = not opts.isEnabled or opts.isEnabled()
        if enabled then
            UIDropDownMenu_EnableDropDown(dropdown)
        else
            UIDropDownMenu_DisableDropDown(dropdown)
        end
        label:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    end)

    return dropdown
end

function PanelMethods.AddDropdown(panel, opts)
    local row = panel:AddRow(52, 8)
    return BuildDropdown(panel, row, opts, 0, DROPDOWN_WIDTH)
end

-- Two compact dropdowns sharing one row — the AddCheckboxPair trick for
-- dropdowns. Each opts table is the AddDropdown shape; right may be nil.
function PanelMethods.AddDropdownPair(panel, left, right)
    local row = panel:AddRow(52, 8)
    local leftDropdown = BuildDropdown(panel, row, left, 0, 120)
    local rightDropdown = right and BuildDropdown(panel, row, right, 270, 120) or nil
    return leftDropdown, rightDropdown
end

-- buttons: array of {label, onClick, tooltip, width, isEnabled}
function PanelMethods.AddButtonRow(panel, buttons)
    local row = panel:AddRow(26, 10)
    local previous
    local created = {}
    for _, spec in ipairs(buttons) do
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(spec.width or 140, 22)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        else
            button:SetPoint("LEFT", row, "LEFT", 0, 0)
        end
        button:SetText(spec.label)
        Tag(row, spec.label, spec.tooltip)
        button:SetScript("OnClick", function()
            spec.onClick()
        end)
        AttachTooltip(button, spec.label, spec.tooltip)
        if spec.isEnabled then
            panel:AddRefresher(function()
                button:SetEnabled(spec.isEnabled() and true or false)
            end)
        end
        previous = button
        created[#created + 1] = button
    end
    return created
end

-- ---------------------------------------------------------------------------
-- Foldouts and search. Opt-in: a long page groups its options under headers
-- that open and close, and a search box above them filters every option on
-- the page by its label and tooltip. Open/closed is remembered per page in
-- CommanderUIDB, so a page reopens the way it was left.
--
-- Rows added after AddFoldout belong to it until the next AddFoldout,
-- EndFoldout, or Finalize. Rows added before the first one (an enable box, a
-- preview) are always on the page. A foldout's `isShown` hides it header and
-- all -- the radial plate's options on a page set to bar plates, say -- and is
-- re-asked on every refresh, so it follows the setting it depends on.
-- ---------------------------------------------------------------------------
local FOLD_OPEN = "Interface\\Buttons\\UI-MinusButton-Up"
local FOLD_SHUT = "Interface\\Buttons\\UI-PlusButton-Up"
local FOLD_HEADER_H = 22

local function FoldStore()
    CommanderUIDB = CommanderUIDB or {}   -- declared at load; the saved copy replaces it
    CommanderUIDB.Folds = CommanderUIDB.Folds or {}
    return CommanderUIDB.Folds
end

local function FoldShown(fold)
    return not fold.isShown or fold.isShown() and true or false
end

-- opts: key (what the open/closed state is remembered by; defaults to the
--       title), expanded (the state before anyone touched it; default shut),
--       isShown (predicate), summary (function -> a few words drawn at the
--       right of the header, visible while it is shut)
function PanelMethods.AddFoldout(panel, title, subtext, opts)
    opts = opts or {}
    panel._fold = nil
    panel._hasFolds = true
    local row = panel:AddRow(FOLD_HEADER_H, 10)
    local fold = {
        title = title, header = row, isShown = opts.isShown, summary = opts.summary,
        key = tostring(panel._key or "?") .. ":" .. tostring(opts.key or title),
    }
    local saved = FoldStore()[fold.key]
    if saved == nil then fold.expanded = opts.expanded == true else fold.expanded = saved end
    -- An automatic foldout nobody has touched gets its default at Finalize,
    -- once the page knows how many foldouts it has
    fold.auto = opts.auto == true
    fold.defaulted = saved == nil
    row._panelEntry.header = fold
    Tag(row, title, subtext)
    panel._folds = panel._folds or {}
    panel._folds[#panel._folds + 1] = fold

    local button = CreateFrame("Button", nil, row)
    button:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    button:SetHeight(FOLD_HEADER_H)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(button)
    bg:SetColorTexture(1, 1, 1, 0.06)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    hover:SetColorTexture(1, 0.82, 0, 0.10)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", button, "LEFT", 4, 0)
    local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    label:SetText(title)
    local summary = button:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    summary:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    fold.icon, fold.summaryText, fold.button = icon, summary, button

    if subtext then
        local note = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 4, -6)
        note:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        note:SetJustifyH("LEFT")
        note:SetTextColor(0.75, 0.75, 0.75)
        note:SetText(subtext)
        fold.note = note
    end

    button:SetScript("OnClick", function()
        PlaySound(fold.expanded and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        panel:SetFoldout(fold, not fold.expanded)
    end)

    -- The note's wrapped height is only knowable once the page has a width
    -- (the same reason AddSection measures on refresh), and the summary
    -- follows the settings it describes
    panel:AddRefresher(function()
        if fold.note and fold.note.GetStringHeight then
            local w = row.GetWidth and row:GetWidth() or 0
            if w > 1 then
                local h = fold.note:GetStringHeight()
                if h and h > 0 then fold.noteHeight = math.ceil(h) end
            end
        end
        if fold.summary then
            local ok, text = pcall(fold.summary)
            summary:SetText(ok and text or "")
        end
    end)

    panel._fold = fold
    return fold
end

function PanelMethods.EndFoldout(panel)
    panel._fold = nil
end

function PanelMethods.SetFoldout(panel, fold, expanded)
    fold.expanded = expanded and true or false
    FoldStore()[fold.key] = fold.expanded
    panel:Relayout()
end

function PanelMethods.SetAllFoldouts(panel, expanded)
    for _, fold in ipairs(panel._folds or {}) do
        fold.expanded = expanded and true or false
        FoldStore()[fold.key] = fold.expanded
    end
    panel:Relayout()
end

-- Re-flow the page: every row that should be seen, one under the next,
-- and the scroll child resized to exactly what is left
function PanelMethods.Relayout(panel)
    if not panel._rows or not panel._anchorSeed then return end
    local host = panel._content or panel
    local rightInset = panel._content and 0 or -RIGHT_MARGIN
    local search = panel._search

    -- Under a search, a foldout is open if anything in it matched, and all
    -- of it is shown if its own title or note did
    local hit = {}
    if search then
        for _, e in ipairs(panel._rows) do
            local keywords = e.row._keywords
            if keywords and keywords:find(search, 1, true) then
                if e.header then hit[e.header] = "all"
                elseif e.fold and not hit[e.fold] then hit[e.fold] = "some" end
            end
        end
    end

    local prev, total = panel._anchorSeed, 0
    for _, e in ipairs(panel._rows) do
        local row, visible = e.row, true
        if e.header then
            local fold = e.header
            visible = FoldShown(fold) and (not search or hit[fold] ~= nil)
            local open = search and true or fold.expanded
            fold.icon:SetTexture(open and FOLD_OPEN or FOLD_SHUT)
            if fold.summaryText then fold.summaryText:SetShown(not open) end
            local h = FOLD_HEADER_H
            if fold.note then
                if open and not search then
                    fold.note:Show()
                    h = h + 10 + (fold.noteHeight or 24)
                else
                    fold.note:Hide()
                end
            end
            row:SetHeight(h)
        elseif e.fold then
            local fold = e.fold
            if not FoldShown(fold) then
                visible = false
            elseif search then
                local keywords = row._keywords
                visible = hit[fold] == "all" or (keywords ~= nil and keywords:find(search, 1, true) ~= nil)
            else
                visible = fold.expanded
            end
        end
        if visible then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -e.spacing)
            row:SetPoint("RIGHT", host, "RIGHT", rightInset, 0)
            row:Show()
            total = total + (row:GetHeight() or 0) + e.spacing
            prev = row
        else
            row:Hide()
        end
    end
    panel._contentHeight = total
    panel:ResizeScroll()
end

-- A search box, with Expand All / Collapse All beside it. Typing filters
-- every foldout down to the options whose label or tooltip mention it.
function PanelMethods.AddSearchBox(panel, opts)
    opts = opts or {}
    local row = panel:AddRow(26, 10)
    local box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    box:SetSize(opts.width or 260, 20)
    box:SetPoint("LEFT", row, "LEFT", 8, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    local hint = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", box, "LEFT", 2, 0)
    hint:SetText(opts.placeholder or "Search options...")
    AttachTooltip(box, "Search", "Type a word to show only the options that mention it -- in their name or their description -- with their sections opened. Escape clears it.")

    local function Apply(self)
        local text = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        hint:SetShown(text == "" and not self:HasFocus())
        local search = text ~= "" and text or nil
        if search ~= panel._search then
            panel._search = search
            panel:Relayout()
        end
    end
    box:SetScript("OnTextChanged", Apply)
    box:SetScript("OnEditFocusGained", function() hint:Hide() end)
    box:SetScript("OnEditFocusLost", Apply)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus(); Apply(self) end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel._searchBox = box

    local collapse = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    collapse:SetSize(100, 22)
    collapse:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    collapse:SetText("Collapse All")
    collapse:SetScript("OnClick", function() panel:SetAllFoldouts(false) end)
    local expand = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    expand:SetSize(100, 22)
    expand:SetPoint("RIGHT", collapse, "LEFT", -6, 0)
    expand:SetText("Expand All")
    expand:SetScript("OnClick", function() panel:SetAllFoldouts(true) end)
    return box
end

-- Public extension point: register a function run on every panel Refresh
-- (used by custom widgets such as Commander_Casting's texture preview)
function PanelMethods.AddRefresher(panel, fn)
    panel._refreshers[#panel._refreshers + 1] = fn
end

function PanelMethods.Refresh(panel)
    if panel._loading then return end
    panel._loading = true
    -- pcall each refresher: a corrupt saved value must surface as a normal
    -- addon error, not leave _loading latched true (which would silently
    -- freeze every slider and re-sync on this panel until reload)
    for _, fn in ipairs(panel._refreshers) do
        local ok, err = pcall(fn)
        if not ok then
            geterrorhandler()(err)
        end
    end
    panel._loading = false
end

-- Fired after any widget writes to the DB: notify the module's update event
-- so the addon (and any other panel mirroring the setting) reacts immediately.
function PanelMethods._Changed(panel)
    if panel._event then
        Commander.Notify(panel._event)
    end
end

-- Trailing-edge throttle for continuous sources (slider drags): at most one
-- notify per window, always ending with the final value since DB writes are
-- immediate and the deferred notify reads the DB when it fires.
local NOTIFY_THROTTLE = 0.15

function PanelMethods._ChangedThrottled(panel)
    if not panel._event then return end
    if panel._notifyPending then return end
    panel._notifyPending = true
    C_Timer.After(NOTIFY_THROTTLE, function()
        panel._notifyPending = false
        Commander.Notify(panel._event)
    end)
end

-- opts: onDefaults (function), defaultsTooltip
-- Builds the standard footer, registers the subcategory, wires refresh
-- triggers and slash commands, and registers the module in the registry.
function PanelMethods.Finalize(panel, opts)
    opts = opts or {}
    -- The footer never belongs to the last foldout
    panel._fold = nil

    if panel._hasFolds then
        local folds = panel._folds or {}
        for i, fold in ipairs(folds) do
            if fold.auto and fold.defaulted then fold.expanded = (#folds <= 3) or i == 1 end
        end
        -- A page long enough to fold is long enough to search: the box goes
        -- in above the first foldout
        if #folds >= 4 and not panel._searchBox then
            panel:AddSearchBox()
            local entry = table.remove(panel._rows)
            local at = #panel._rows + 1
            for i, e in ipairs(panel._rows) do
                if e.header then at = i break end
            end
            table.insert(panel._rows, at, entry)
        end
    end

    local footer = panel:AddRow(34, 16)
    local line = footer:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)

    if opts.onDefaults then
        local defaultsButton = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
        defaultsButton:SetSize(140, 22)
        defaultsButton:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 0)
        defaultsButton:SetText("Restore Defaults")
        defaultsButton:SetScript("OnClick", function()
            opts.onDefaults()
        end)
        AttachTooltip(defaultsButton, "Restore Defaults",
            opts.defaultsTooltip or "Reset every option on this page to its default value.")
    end

    if panel._slash and panel._slash[1] then
        local hint = footer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 4)
        hint:SetText("Slash command: " .. panel._slash[1])
    end

    -- Registered last, so it runs after every GrowRow refresher above it and
    -- sizes the scroll child against heights that have already settled
    if panel._hasFolds then
        panel:AddRefresher(function() panel:Relayout() end)
        panel:Relayout()
    end
    panel:AddRefresher(function() panel:ResizeScroll() end)
    panel:ResizeScroll()

    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, panel._title)
    panel._categoryID = category:GetID()

    if panel._event then
        Commander.AddListener(panel._event, function()
            panel:Refresh()
        end)
    end
    panel:SetScript("OnShow", function()
        panel:Refresh()
    end)
    panel:Refresh()

    -- Standardized slash commands: bare command opens the panel (unless the
    -- module overrides it via a "" handler, e.g. /ci toggling the item grid,
    -- in which case a "settings" subcommand is provided automatically) and
    -- registered subcommands dispatch to their handler. A "reset" subcommand
    -- is wired to onDefaults automatically.
    if panel._slash and panel._slash[1] then
        local key = "COMMANDERUI_" .. panel._key:upper()
        for i, cmd in ipairs(panel._slash) do
            _G["SLASH_" .. key .. i] = cmd
        end
        local handlers = panel._slashHandlers or {}
        local function OpenPanel()
            Settings.OpenToCategory(panel._categoryID)
        end
        if opts.onDefaults and not handlers.reset then
            handlers.reset = opts.onDefaults
        end
        if handlers[""] and not handlers.settings then
            handlers.settings = OpenPanel
        end
        local usage = "Usage: " .. panel._slash[1]
        local subcommands = {}
        for sub in pairs(handlers) do
            if sub ~= "" then
                subcommands[#subcommands + 1] = sub
            end
        end
        table.sort(subcommands)
        if #subcommands > 0 then
            usage = usage .. " [" .. table.concat(subcommands, "|") .. "]"
        end
        SlashCmdList[key] = function(msg)
            msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if handlers[msg] then
                handlers[msg]()
            elseif msg == "" then
                OpenPanel()
            else
                print(usage)
            end
        end
    end

    Commander.RegisterModule({
        key = panel._key,
        title = panel._title,
        addonName = panel._addonName,
        description = panel._description,
        categoryID = panel._categoryID,
        slash = panel._slash and panel._slash[1],
        version = panel._version,
    })

    return category
end

-- ---------------------------------------------------------------------------
-- Panel header (shared with the root Commander page in CommanderEvents.lua)
-- ---------------------------------------------------------------------------

-- Draws the standard header — title, version tag, wrapped description, and a
-- divider — and returns the divider (the anchor for content below) plus the
-- resolved version string.
function UI.BuildPanelHeader(panel, opts)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_MARGIN, -16)
    title:SetText(opts.titleText)

    local version = opts.addonName and C_AddOns.GetAddOnMetadata(opts.addonName, "Version")
    if version then
        local versionText = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        versionText:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -RIGHT_MARGIN, -24)
        versionText:SetText("v" .. version)
    end

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    description:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    description:SetJustifyH("LEFT")
    description:SetText(opts.description or "")

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10)
    divider:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)

    return divider, version
end

-- ---------------------------------------------------------------------------
-- Panel constructor
-- ---------------------------------------------------------------------------

-- UIPanelScrollFrameTemplate resolves its scrollbar through _G[name .. "ScrollBar"],
-- so the scroll frame needs a real global name — and the panel it hangs on
-- has none. Panel keys are already unique (they key the slash commands), so
-- they make the name; anything not name-safe is dropped.
local usedScrollNames = {}
local function ScrollFrameName(key)
    local base = "CommanderUIScroll" .. tostring(key or "Panel"):gsub("%W", "")
    local name, n = base, 1
    while usedScrollNames[name] do
        n = n + 1
        name = base .. n
    end
    usedScrollNames[name] = true
    return name
end

-- opts: key (unique short id), title (subcategory name), addonName,
--       description, event (Commander update event to listen for / notify),
--       slash (array of slash commands), slashHandlers (map subcommand->fn;
--       a "" key overrides what the bare command does), foldSections (false
--       keeps AddSection a plain heading instead of a foldout)
function UI.NewPanel(opts)
    local panel = CreateFrame("Frame")
    panel.name = opts.title
    panel._key = opts.key
    panel._title = opts.title
    panel._addonName = opts.addonName
    panel._description = opts.description
    panel._event = opts.event
    panel._slash = opts.slash
    panel._slashHandlers = opts.slashHandlers
    panel._refreshers = {}
    panel._contentHeight = 0
    panel._loading = false
    panel._autoFold = opts.foldSections ~= false

    for name, fn in pairs(PanelMethods) do
        panel[name] = fn
    end

    local divider, version = UI.BuildPanelHeader(panel, {
        titleText = "Commander |cffffffff" .. opts.title .. "|r",
        addonName = opts.addonName,
        description = opts.description,
    })
    panel._version = version

    -- Every page scrolls, from here rather than from each module.
    --
    -- A canvas subcategory is handed a fixed viewport and clips whatever runs
    -- past it: no scrollbar, no error, just options that stop existing — and
    -- since Finalize adds the footer LAST, the first thing an overlong page
    -- loses is Restore Defaults. Sixteen modules had each grown their own
    -- copy of this scroll frame to get out from under that, which meant the
    -- seventeenth page to grow one option too many silently lost its tail.
    --
    -- The header stays on the canvas above the scroll frame, so the title,
    -- version and description hold still while the options move under them.
    local scroll = CreateFrame("ScrollFrame", ScrollFrameName(opts.key), panel,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SCROLLBAR_GUTTER, 12)
    -- The template's own scrollbar handles dragging; the wheel has to be
    -- asked for, and it is the only way most people will ever scroll this
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 28
        local limit = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    -- A scroll child does not inherit its parent's width; without this every
    -- row is one pixel wide and every label wraps to nothing
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    panel._scroll, panel._content = scroll, content

    -- Anchor target for the first row
    local anchorSeed = CreateFrame("Frame", nil, content)
    anchorSeed:SetHeight(1)
    anchorSeed:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    anchorSeed:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    panel._anchor = anchorSeed
    panel._anchorSeed = anchorSeed

    return panel
end

-- ---------------------------------------------------------------------------
-- HUD chrome: shared style / unlock+drag / scale treatment for the suite's
-- on-screen HUD frames (Production queue, Vitals wireframe, ...) so they
-- all offer the same options and can match the command card's framing.
-- ---------------------------------------------------------------------------

-- Keys used in the module's SavedVariables, derived from the prefix:
--   <prefix>Style ("NONE" | "CLASSIC" | "DARK" | "SOLID" | "WINDOW"), <prefix>Scale,
--   <prefix>Locked (bool), <prefix>Pos ({point, x, y} or nil = default)
function UI.HudChromeDefaults(prefix, styleDefault)
    return {
        [prefix .. "Style"] = styleDefault or "DARK",
        [prefix .. "Scale"] = 1.0,
        [prefix .. "Locked"] = true,
        -- false (not nil) so Restore Defaults actually clears a saved drag
        -- position: ResetToDefaults only writes keys present here
        [prefix .. "Pos"] = false,
    }
end

-- Which DB key holds the frame's scale. Normally <prefix>Scale; a module
-- whose right size depends on context (Party Frames: one scale per group
-- size bracket) passes opts.scaleKey, a key or a function returning one,
-- and every reader and writer here (slider, grips, Apply) follows it.
local function HudScaleKey(prefix, opts)
    local key = opts and opts.scaleKey
    if type(key) == "function" then key = key() end
    return key or (prefix .. "Scale")
end
UI.HudScaleKey = HudScaleKey

-- Session-scoped "closed" flags for window-style HUD frames (weak-keyed on
-- the module DB, so nothing persists or leaks)
local hudClosed = setmetatable({}, { __mode = "k" })

local function IsHudClosed(db, prefix)
    return hudClosed[db] and hudClosed[db][prefix]
end

local function SetHudClosed(db, prefix, value)
    hudClosed[db] = hudClosed[db] or {}
    hudClosed[db][prefix] = value or nil
end

local HUD_STYLES = {
    -- Matches the command card (Commander_ActionBar) framing
    CLASSIC = {
        backdrop = {
            bgFile = "Interface\\BankFrame\\Bank-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        },
        bg = { 0.5, 0.5, 0.5, 1 },
        border = { 1, 1, 1, 1 },
        pad = 12,
    },
    DARK = {
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        },
        bg = { 0, 0, 0, 0.6 },
        border = { 0.6, 0.6, 0.6, 1 },
        pad = 8,
    },
    -- The dark-mode plate. Dark Panel is a tint: the world shows through it,
    -- which is the point of it and also why a white number over a snowfield
    -- still reads as a number over a snowfield. This one is a FLOOR --
    -- near-black and all but opaque, so everything drawn on it has the same
    -- contrast wherever the camera is pointing -- with a one-pixel hairline
    -- for an edge instead of the tooltip border's rounded rope, and half the
    -- pad, because a frame that exists to be compact should not spend eight
    -- pixels a side on its own margin.
    SOLID = {
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        },
        bg = { 0.045, 0.05, 0.06, 0.96 },
        border = { 0.22, 0.24, 0.28, 1 },
        pad = 4,
    },
    -- Commander_Inventory's framing: a real little window
    -- (BasicFrameTemplateWithInset) with title, lock, close, and a
    -- scale-driving resize grip
    WINDOW = { window = true },
}

-- Standalone style backdrop for frames that manage their own window art
-- (Commander_Inventory's grid): applies the CLASSIC/DARK backdrops from
-- the shared style table, or hides the backdrop for NONE/WINDOW.
-- ---------------------------------------------------------------------------
-- Window dressing
--
-- Every region BasicFrameTemplate / BasicFrameTemplateWithInset draws, by
-- parentKey, taken from THIS client's UIPanelTemplates.xml
-- (BaseBasicFrameTemplate + BasicFrameTemplate + BasicFrameTemplateWithInset).
--
-- This list lives here because three separate windows guessed at it and got it
-- wrong the same way. The guess was { "NineSlice", "Bg", "TitleBg", "Inset" },
-- and on this client THREE of those four do not exist: there is no NineSlice
-- and no Inset frame. What there is instead is nine border pieces, a tiled
-- title bar, a streak layer and a marble inset -- none of which were being
-- hidden. The visible result is a window wearing the template's steel frame
-- with its own art stranded behind it (the art frame sits a level below, which
-- is what lets the template's Bg cover it), a doubled title bar, and text
-- coloured for a background nobody can see.
--
-- CloseButton is deliberately absent: every window here wants one.
UI.TEMPLATE_REGIONS = {
    "TopLeftCorner", "TopRightCorner", "TopBorder", "TitleText",
    "BotLeftCorner", "BotRightCorner", "BottomBorder",
    "LeftBorder", "RightBorder",
    "Bg", "TitleBg", "TopTileStreaks",
    "InsetBg",
    "InsetBorderTopLeft", "InsetBorderTopRight",
    "InsetBorderBottomLeft", "InsetBorderBottomRight",
    "InsetBorderTop", "InsetBorderBottom",
    "InsetBorderLeft", "InsetBorderRight",
    -- Names this client does not use but a future one might; harmless here
    "NineSlice", "Inset", "PortraitContainer", "portrait",
}

-- Show or hide a templated window's own dressing as one piece, so a module
-- that draws its own frame art can get the template out of the way.
--
-- Every region is guarded: a template that stops shipping one must degrade to
-- a plainer window, never to an error.
function UI.SetTemplateDressing(frame, shown)
    if not frame then return end
    for _, key in ipairs(UI.TEMPLATE_REGIONS) do
        local region = frame[key]
        -- type-checked, not just truthy: several of these names are only
        -- present on some clients, and a frame whose metatable answers an
        -- unknown key with something other than a widget must cost us a
        -- hidden region, never an error inside a repaint.
        if type(region) == "table" and region.SetShown then
            region:SetShown(shown)
        end
    end
end

-- UIPanelScrollFrameTemplate hangs a stepper bar off the right of the scroll
-- frame: a slider with an up and a down button, both of which are drawn as
-- floating squares against a dark pane because the bar's own track art does
-- not read there. The wheel and the drag do everything those buttons do, so
-- they come off and the bar is pulled in tight against the content.
--
-- The template resolves its children through _G[name .. suffix], which is why
-- the scroll frame has to have been created with a real global name.
function UI.SlimScrollBar(scrollFrameName, insetTop, insetBottom)
    local bar = _G[scrollFrameName .. "ScrollBar"]
    if not bar then return nil end
    for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local button = _G[scrollFrameName .. "ScrollBar" .. suffix]
        if button then
            button:Hide()
            if button.SetWidth then button:SetWidth(1) end
        end
    end
    local scroll = _G[scrollFrameName]
    if scroll and bar.ClearAllPoints then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, -(insetTop or 0))
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, (insetBottom or 0))
    end
    return bar
end

-- `opaque` draws the style's fill solid whatever its own alpha is: a window
-- of text to be read wants a floor under it, not a tint the world shows
-- through.
function UI.ApplyStyleBackdrop(frame, styleKey, opaque)
    local style = HUD_STYLES[styleKey]
    if style and style.window then
        style = nil
    end
    if not frame._styleBackdrop then
        if not style then return end
        frame._styleBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame._styleBackdrop:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
    end
    local backdrop = frame._styleBackdrop
    if style then
        if frame._styleBackdropKey ~= styleKey then
            frame._styleBackdropKey = styleKey
            backdrop:ClearAllPoints()
            backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            backdrop:SetBackdrop(style.backdrop)
        end
        local r, g, b, a = unpack(style.bg)
        backdrop:SetBackdropColor(r, g, b, opaque and 1 or a)
        backdrop:SetBackdropBorderColor(unpack(style.border))
        backdrop:Show()
    else
        frame._styleBackdropKey = nil
        backdrop:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- A corner to scale a window by.
--
-- A grip at the bottom right of `frame` (or of opts.corner, when the edge the
-- eye takes for the window's is a backdrop drawn outside it). Dragging it
-- scales the WHOLE frame -- SetScale, so everything in it grows together --
-- about its top-left corner: that corner stays where it is on screen and the
-- one under the cursor is the one that moves, which is what dragging a corner
-- means everywhere else.
--
-- The scale chosen is the one that brings the bottom-right corner nearest the
-- cursor along the frame's own diagonal, so a drag in any direction tracks
-- and one along a single edge cannot make it jitter.
--
-- opts: min, max (0.6 / 1.6), corner, inset (3),
--       set(scale)           the scale changed (save it)
--       onStart()            a drag has begun
--       onStop(point, x, y)  it has ended: the frame is anchored by `point` to
--                            the same point of UIParent, x and y in UIParent's
--                            own units -- screen space, the form HUD chrome
--                            saves a position in
--
-- The frame must not be protected: SetScale and SetPoint on a secure frame,
-- or on anything one is parented or anchored to, are refused in combat.
-- ---------------------------------------------------------------------------
function UI.AttachScaleGrip(frame, opts)
    opts = opts or {}
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    local inset = opts.inset or 3
    grip:SetPoint("BOTTOMRIGHT", opts.corner or frame, "BOTTOMRIGHT", -inset, inset)
    grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 25)
    grip.tex = grip:CreateTexture(nil, "ARTWORK")
    grip.tex:SetAllPoints()
    grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    if grip.SetHighlightTexture then
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end
    local lo, hi = opts.min or 0.6, opts.max or 1.6

    local function Stop()
        if not grip._dragging then return end
        grip._dragging = nil
        grip:SetScript("OnUpdate", nil)
        if opts.onStop then opts.onStop("TOPLEFT", grip._x, grip._y) end
    end

    grip:SetScript("OnMouseDown", function()
        local eff = frame:GetEffectiveScale() or 1
        local scale = frame:GetScale() or 1
        local outer = eff / scale       -- the scale of whatever the frame sits in
        local ui = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
        local left, top = frame:GetLeft(), frame:GetTop()
        if not (left and top) or w <= 0 or h <= 0 then return end
        -- Screen pixels from here on. The pinned corner; the top of the
        -- screen it is measured down from; and how far off the frame's own
        -- corner the cursor took hold, so the first move does not jump.
        left, top = left * eff, top * eff
        local screenTop = (UIParent:GetHeight() or 0) * ui
        local cx, cy = GetCursorPosition()
        local grabX, grabY = cx - (left + w * eff), cy - (top - h * eff)
        grip._x, grip._y = left / ui, (top - screenTop) / ui
        grip._dragging = true
        if opts.onStart then opts.onStart() end
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local dx, dy = (x - grabX - left) / outer, (top - (y - grabY)) / outer
            local wanted = (dx * w + dy * h) / (w * w + h * h)
            wanted = math.floor(math.max(lo, math.min(hi, wanted)) * 100 + 0.5) / 100
            if wanted == frame:GetScale() then return end
            -- Offsets are in the frame's own units, so the same corner is a
            -- different number at every scale. Anchor first, scale second:
            -- whatever follows the scale then reads the rect it ends up with.
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
                left / (outer * wanted), (top - screenTop) / (outer * wanted))
            frame:SetScale(wanted)
            if opts.set then opts.set(wanted) end
        end)
    end)
    grip:SetScript("OnMouseUp", Stop)
    -- A window closed mid-drag must not come back still following the mouse
    grip:SetScript("OnHide", Stop)
    AttachTooltip(grip, "Resize", "Drag to scale the whole window.")
    return grip
end

-- Build the window dressing lazily on first use. All template children
-- are guarded: the smoke harness's CreateFrame ignores templates.
local function EnsureWindowChrome(frame, db, prefix)
    if frame._hudWindow then return frame._hudWindow end
    local win = CreateFrame("Frame", nil, frame, "BasicFrameTemplateWithInset")
    frame._hudWindow = win
    win:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
    win:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 28)
    win:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -10)

    if win.CloseButton then
        win.CloseButton:SetScript("OnClick", function()
            SetHudClosed(db, prefix, true)
            frame:Hide()
            print("Commander: window closed for this session — Reset Position in its settings reopens it")
        end)
    end

    local lock = CreateFrame("Button", nil, win)
    win.lockButton = lock
    lock:SetSize(16, 16)
    if win.CloseButton then
        lock:SetPoint("RIGHT", win.CloseButton, "LEFT", -1, 0)
    else
        lock:SetPoint("TOPRIGHT", win, "TOPRIGHT", -24, -4)
    end
    lock.tex = lock:CreateTexture(nil, "ARTWORK")
    lock.tex:SetAllPoints()
    lock:SetScript("OnClick", function()
        db[prefix .. "Locked"] = not db[prefix .. "Locked"]
        if frame._hudOpts then
            UI.ApplyHudChrome(frame, db, prefix, frame._hudOpts)
        end
    end)
    AttachTooltip(lock, "Lock / Unlock", "Unlocked frames can be dragged anywhere; lock when placed.")

    -- Resize grip: dragging it scales the frame, saved to the module's
    -- Frame Scale setting, position preserved on release
    local grip = CreateFrame("Button", nil, win)
    win.grip = grip
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 25)
    grip.tex = grip:CreateTexture(nil, "ARTWORK")
    grip.tex:SetAllPoints()
    grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function()
        frame._hudDragging = true    -- freezes re-anchoring while sizing
        local startX, startY = GetCursorPosition()
        local scaleKey = HudScaleKey(prefix, frame._hudOpts)
        local startScale = db[scaleKey] or 1
        local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local delta = ((x - startX) - (y - startY)) / 2 / uiScale
            local newScale = math.max(0.6, math.min(1.6, startScale + delta / 160))
            newScale = math.floor(newScale * 100 + 0.5) / 100
            db[scaleKey] = newScale
            frame:SetScale(newScale)
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        frame._hudDragging = false
        -- Re-save the position in screen space under the new scale so the
        -- window stays where it visually ended up
        local point, _, _, x, y = frame:GetPoint(1)
        if point then
            local scale = frame:GetScale() or 1
            db[prefix .. "Pos"] = { point = point, x = x * scale, y = y * scale }
        end
        if frame._hudOpts then
            UI.ApplyHudChrome(frame, db, prefix, frame._hudOpts)
        end
    end)
    AttachTooltip(grip, "Resize", "Drag to resize the window (adjusts Frame Scale).")

    return win
end

-- True while the module's HUD frame is unlocked for dragging. Consumers
-- must keep their frame SHOWN while unlocked (even with nothing to
-- display) so there is something on screen to drag.
function UI.HudUnlocked(db, prefix)
    return not db[prefix .. "Locked"]
end

-- Re-appliable: call from the module's settings listener. opts:
--   defaultPoint = {point=, x=, y=} (required) — position when no saved drag
--   opaque = true — the style's fill is drawn solid (see ApplyStyleBackdrop)
--   scaleGrip = true — a grip in the bottom-right corner scales the frame,
--     driving <prefix>Scale, in every style (the Window style has its own)
function UI.ApplyHudChrome(frame, db, prefix, opts)
    frame._hudOpts = opts
    if not frame._hudChromeInit then
        frame._hudChromeInit = true
        frame._hudBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame._hudBackdrop:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        -- Window-style close is session-scoped; a consumer's SetShown must
        -- not resurrect a closed window
        frame:HookScript("OnShow", function(self)
            if IsHudClosed(db, prefix) then
                self:Hide()
            end
        end)
        -- Triple right-click on a LOCKED frame unlocks it. Only possible
        -- where the client can pass left-clicks through (so a locked frame
        -- still never blocks normal interaction); without the API the old
        -- fully-transparent contract stands.
        if frame.SetPassThroughButtons then
            local ok = pcall(frame.SetPassThroughButtons, frame, "LeftButton")
            frame._hudRightCatch = ok or nil
            frame:SetScript("OnMouseUp", function(self, mouseButton)
                if mouseButton ~= "RightButton" then return end
                local now = GetTime()
                if not (self._hudRightAt and (now - self._hudRightAt) < 0.7) then
                    self._hudRightClicks = 0
                end
                self._hudRightClicks = (self._hudRightClicks or 0) + 1
                self._hudRightAt = now
                if self._hudRightClicks >= 3 then
                    self._hudRightClicks = 0
                    db[prefix .. "Locked"] = false
                    UI.ApplyHudChrome(frame, db, prefix, frame._hudOpts)
                end
            end)
        end

        -- The drag surface is a dedicated overlay ABOVE the frame's
        -- content: module content frequently has its own mouse-enabled
        -- children (tooltip rows), which would otherwise swallow every
        -- drag; and while unlocked the overlay doubles as the visual cue
        -- even with Frame Style set to None. The root frame itself never
        -- takes the mouse, so locked frames stay click-transparent.
        local overlay = CreateFrame("Frame", nil, frame)
        frame._hudDragOverlay = overlay
        -- Cover the chrome pad too, so the styled border is also a grab
        -- handle — a bigger target than the content alone
        overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", -12, 12)
        overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 12, -12)
        overlay:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
        overlay:EnableMouse(true)
        overlay:RegisterForDrag("LeftButton")
        overlay.fill = overlay:CreateTexture(nil, "OVERLAY")
        overlay.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
        overlay.fill:SetVertexColor(0.3, 1, 0.4, 0.25)
        overlay.fill:SetAllPoints()
        overlay.label = overlay:CreateFontString(nil, "OVERLAY")
        overlay.label:SetFontObject(GameFontHighlightSmall)
        overlay.label:SetPoint("CENTER")
        overlay.label:SetText("DRAG · right-click locks")
        overlay:Hide()
        -- Right-click on an unlocked frame locks it in place — no trip
        -- back to the settings panel needed
        overlay:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "RightButton" then
                db[prefix .. "Locked"] = true
                UI.ApplyHudChrome(frame, db, prefix, frame._hudOpts or opts)
            end
        end)
        overlay:SetScript("OnDragStart", function()
            frame._hudDragging = true
            frame:StartMoving()
        end)
        overlay:SetScript("OnDragStop", function()
            frame._hudDragging = false
            frame:StopMovingOrSizing()
            local point, _, _, x, y = frame:GetPoint(1)
            if point then
                -- Store offsets in SCREEN space (multiply out the frame's
                -- scale) so a later scale change keeps the frame where the
                -- user put it instead of migrating the anchor
                local scale = frame:GetScale() or 1
                db[prefix .. "Pos"] = { point = point, x = x * scale, y = y * scale }
            end
        end)
    end

    local scale = db[HudScaleKey(prefix, opts)] or 1
    if (frame:GetScale() or 1) ~= scale then frame:SetScale(scale) end

    -- Never re-anchor mid-drag: throttled setting notifies would snap the
    -- frame out of the user's hand
    if not frame._hudDragging then
        local pos = db[prefix .. "Pos"]
        frame:ClearAllPoints()
        if pos and pos.point then
            frame:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
        else
            local p = opts.defaultPoint
            frame:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
        end
    end

    local styleKey = db[prefix .. "Style"] or "NONE"
    local style = HUD_STYLES[styleKey]
    local backdrop = frame._hudBackdrop
    if style and style.window then
        backdrop:Hide()
        frame._hudStyleApplied = styleKey
        local win = EnsureWindowChrome(frame, db, prefix)
        if win.TitleText then
            win.TitleText:SetText(opts.title or "Commander")
        end
        if win.lockButton and win.lockButton.tex then
            win.lockButton.tex:SetTexture(db[prefix .. "Locked"]
                and "Interface\\Buttons\\LockButton-Locked-Up"
                or "Interface\\Buttons\\LockButton-Unlocked-Up")
        end
        win:Show()
    elseif style then
        if frame._hudWindow then
            frame._hudWindow:Hide()
        end
        if frame._hudStyleApplied ~= styleKey then
            frame._hudStyleApplied = styleKey
            backdrop:ClearAllPoints()
            backdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", -style.pad, style.pad)
            backdrop:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", style.pad, -style.pad)
            backdrop:SetBackdrop(style.backdrop)
        end
        local r, g, b, a = unpack(style.bg)
        backdrop:SetBackdropColor(r, g, b, opts.opaque and 1 or a)
        backdrop:SetBackdropBorderColor(unpack(style.border))
        backdrop:Show()
    else
        frame._hudStyleApplied = nil
        backdrop:Hide()
        if frame._hudWindow then
            frame._hudWindow:Hide()
        end
    end

    -- The scale grip sits in the corner of whatever is drawn as the frame's
    -- edge: the plate when there is one, the frame itself under None. The
    -- Window style carries a grip of its own.
    if opts.scaleGrip and not (style and style.window) then
        local grip = frame._hudScaleGrip
        if not grip then
            grip = UI.AttachScaleGrip(frame, {
                set = function(value) db[HudScaleKey(prefix, frame._hudOpts)] = value end,
                -- freezes re-anchoring while sizing, as a drag does
                onStart = function() frame._hudDragging = true end,
                onStop = function(point, x, y)
                    frame._hudDragging = false
                    db[prefix .. "Pos"] = { point = point, x = x, y = y }
                    UI.ApplyHudChrome(frame, db, prefix, frame._hudOpts)
                end,
            })
            frame._hudScaleGrip = grip
        end
        if grip._corner ~= (style and styleKey or "NONE") then
            grip._corner = style and styleKey or "NONE"
            grip:ClearAllPoints()
            grip:SetPoint("BOTTOMRIGHT", style and backdrop or frame, "BOTTOMRIGHT", -3, 3)
        end
        grip:Show()
    elseif frame._hudScaleGrip then
        frame._hudScaleGrip:Hide()
    end

    local locked = db[prefix .. "Locked"]
    -- Locked + right-catch support: the root listens for the triple
    -- right-click unlock while left-clicks pass straight through.
    -- Unlocked: the drag overlay owns the mouse instead.
    if frame._hudRightCatch then
        frame:EnableMouse(locked and true or false)
    end
    -- Recompute the level each apply: module content created after init
    -- (pooled rows) must never end up above the drag surface
    frame._hudDragOverlay:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    frame._hudDragOverlay:SetShown(not locked)
    if not locked then
        if style and not style.window then
            backdrop:SetBackdropBorderColor(0.3, 1, 0.4, 1)
        end
        -- A hidden frame cannot be dragged; force it visible as a
        -- placeholder while unlocked (consumers keep it shown too)
        frame:Show()
    end
    -- Closed windows stay closed no matter what the consumer decides
    if IsHudClosed(db, prefix) then
        frame:Hide()
    end
end

-- The standard settings rows every chromed HUD module offers. opts:
--   isEnabled (fn gating all rows), onChanged (fn run after any change,
--   usually the module's Apply), defaultPoint (for Reset Position)
function UI.AddHudChromeOptions(panel, db, prefix, opts)
    local enabled = opts.isEnabled
    -- Style and scale share one row (dropdown left, slider right) so the
    -- chrome block costs each panel two rows, not three
    local chromeRow = panel:AddRow(52, 8)
    BuildDropdown(panel, chromeRow, {
        label = "Frame Style",
        tooltip = "Backing panel drawn behind the frame. Classic Panel matches the command card's dialog framing; Dark Panel is a translucent tint the world shows through; Solid Dark is a near-black plate with a hairline edge and a tight margin -- the same contrast behind every number wherever the camera points, and the most compact of them; Window turns it into a little window with a title bar, lock and close buttons, and a resize grip."
            .. (opts.opaque and "\n\nOn this frame every panel is drawn solid: none of them lets the world show through." or ""),
        options = {
            { text = "None", value = "NONE" },
            { text = "Classic Panel", value = "CLASSIC" },
            { text = "Dark Panel", value = "DARK" },
            { text = "Solid Dark", value = "SOLID" },
            { text = "Window", value = "WINDOW" },
        },
        get = function() return db[prefix .. "Style"] or "NONE" end,
        set = function(value) db[prefix .. "Style"] = value end,
        isEnabled = enabled,
    }, 0, 120)
    -- opts.scaleSliders = { { key, label, tooltip }, ... } replaces the one
    -- Frame Scale slider with several (a scale per context, chosen at Apply
    -- by opts.scaleKey): the first takes the usual seat beside the style
    -- dropdown, the rest follow two to a row.
    local sliders = opts.scaleSliders or {
        { key = prefix .. "Scale", label = "Frame Scale", tooltip = "Overall size of the frame." },
    }
    local gripNote = opts.scaleGrip and " Dragging the grip in the frame's bottom-right corner sets the same number." or ""
    local function ScaleSlider(row, spec, x)
        BuildSlider(panel, row, {
            label = spec.label,
            tooltip = spec.tooltip .. gripNote,
            min = 0.6, max = 1.6, step = 0.05,
            format = UI.FormatPercent,
            get = function() return db[spec.key] or 1 end,
            set = function(value) db[spec.key] = value end,
            isEnabled = enabled,
        }, x, 170)
    end
    ScaleSlider(chromeRow, sliders[1], 270)
    for i = 2, #sliders, 2 do
        local row = panel:AddRow(52, 8)
        ScaleSlider(row, sliders[i], 0)
        if sliders[i + 1] then ScaleSlider(row, sliders[i + 1], 270) end
    end
    -- Compact final row: unlock checkbox left, reset button right, sharing
    -- one 26px row to respect the panels' no-scroll height budget
    local row = panel:AddRow(26, 2)
    BuildCheckbox(panel, row, {
        label = "Unlock Frame",
        tooltip = "Unlock to drag the frame anywhere (border turns green); right-click the unlocked frame to lock it, triple right-click a locked frame to unlock it from here on out.",
        get = function() return not db[prefix .. "Locked"] end,
        set = function(value) db[prefix .. "Locked"] = not value end,
        isEnabled = enabled,
    }, 0)
    local reset = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    reset:SetSize(130, 24)
    reset:SetPoint("LEFT", row, "LEFT", 270, 0)
    reset:SetText("Reset Position")
    reset:SetScript("OnClick", function()
        db[prefix .. "Pos"] = nil
        -- Also reopens a window closed with its X for this session
        SetHudClosed(db, prefix, nil)
        if opts.onChanged then opts.onChanged() end
    end)
    AttachTooltip(reset, "Reset Position", "Return the frame to its default position (and reopen it if its window was closed).")
    if enabled then
        panel:AddRefresher(function()
            reset:SetEnabled(enabled() and true or false)
        end)
    end
end

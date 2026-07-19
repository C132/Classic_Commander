-- Commander.UI: shared settings-panel framework for the Commander suite.
--
-- Every module builds its options page through UI.NewPanel, which provides a
-- consistent header (title, version, description), uniformly spaced widgets
-- that re-sync themselves from the module DB whenever the module's update
-- event fires (or the panel is shown), dependent enable/disable states, a
-- standard "Restore Defaults" footer, and standardized slash commands.
--
-- Panels register themselves in the Commander module registry
-- (Commander.RegisterModule / Commander.GetModules) so suite-level UIs such
-- as Commander_Suite can enumerate every installed module.

Commander = Commander or {}
Commander.UI = Commander.UI or {}

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
function PanelMethods.AddRow(panel, height, spacing)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", panel._anchor, "BOTTOMLEFT", 0, -(spacing or ROW_SPACING))
    row:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    panel._anchor = row
    return row
end

function PanelMethods.AddSection(panel, text, subtext)
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
    end
    return row
end

function PanelMethods.AddSpacer(panel, height)
    return panel:AddRow(height or 8, 0)
end

local function BuildCheckbox(panel, row, opts, xOffset)
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

-- opts: key (unique short id), title (subcategory name), addonName,
--       description, event (Commander update event to listen for / notify),
--       slash (array of slash commands), slashHandlers (map subcommand->fn;
--       a "" key overrides what the bare command does)
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
    panel._loading = false

    for name, fn in pairs(PanelMethods) do
        panel[name] = fn
    end

    local divider, version = UI.BuildPanelHeader(panel, {
        titleText = "Commander |cffffffff" .. opts.title .. "|r",
        addonName = opts.addonName,
        description = opts.description,
    })
    panel._version = version

    -- Anchor target for the first row
    local anchorSeed = CreateFrame("Frame", nil, panel)
    anchorSeed:SetHeight(1)
    anchorSeed:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, 0)
    anchorSeed:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    panel._anchor = anchorSeed

    return panel
end

-- ---------------------------------------------------------------------------
-- HUD chrome: shared style / unlock+drag / scale treatment for the suite's
-- on-screen HUD frames (Production queue, Vitals wireframe, ...) so they
-- all offer the same options and can match the command card's framing.
-- ---------------------------------------------------------------------------

-- Keys used in the module's SavedVariables, derived from the prefix:
--   <prefix>Style ("NONE" | "CLASSIC" | "DARK"), <prefix>Scale,
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
    -- Commander_Inventory's framing: a real little window
    -- (BasicFrameTemplateWithInset) with title, lock, close, and a
    -- scale-driving resize grip
    WINDOW = { window = true },
}

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
        local startScale = db[prefix .. "Scale"] or 1
        local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local delta = ((x - startX) - (y - startY)) / 2 / uiScale
            local newScale = math.max(0.6, math.min(1.6, startScale + delta / 160))
            newScale = math.floor(newScale * 100 + 0.5) / 100
            db[prefix .. "Scale"] = newScale
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
            local scale = db[prefix .. "Scale"] or 1
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

    local scale = db[prefix .. "Scale"] or 1
    frame:SetScale(scale)

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
        backdrop:SetBackdropColor(unpack(style.bg))
        backdrop:SetBackdropBorderColor(unpack(style.border))
        backdrop:Show()
    else
        frame._hudStyleApplied = nil
        backdrop:Hide()
        if frame._hudWindow then
            frame._hudWindow:Hide()
        end
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
        tooltip = "Backing panel drawn behind the frame. Classic Panel matches the command card's dialog framing; Window turns it into a little window with a title bar, lock and close buttons, and a resize grip.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Classic Panel", value = "CLASSIC" },
            { text = "Dark Panel", value = "DARK" },
            { text = "Window", value = "WINDOW" },
        },
        get = function() return db[prefix .. "Style"] or "NONE" end,
        set = function(value) db[prefix .. "Style"] = value end,
        isEnabled = enabled,
    }, 0, 120)
    BuildSlider(panel, chromeRow, {
        label = "Frame Scale",
        tooltip = "Overall size of the frame.",
        min = 0.6, max = 1.6, step = 0.05,
        format = UI.FormatPercent,
        get = function() return db[prefix .. "Scale"] or 1 end,
        set = function(value) db[prefix .. "Scale"] = value end,
        isEnabled = enabled,
    }, 270, 170)
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

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
function PanelMethods.AddSlider(panel, opts)
    local row = panel:AddRow(52, 8)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    label:SetText(opts.label)

    -- Hand-rolled slider: the deprecated OptionsSliderTemplate draws its
    -- track via NineSlice "SliderBar" atlas pieces, which do not render
    -- reliably on this client. Blizzard's own sanctioned alternative (used
    -- by its TBC credits screen) is a Slider inheriting BackdropTemplate
    -- with the BACKDROP_SLIDER_8_8 track, so draw it that way ourselves.
    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -18)
    slider:SetSize(SLIDER_WIDTH, 17)
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

-- opts: label, tooltip, options ({text=, value=}...), get, set, width,
--       isEnabled, onSelect
function PanelMethods.AddDropdown(panel, opts)
    local row = panel:AddRow(52, 8)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    label:SetText(opts.label)

    -- UIDropDownMenu_EnableDropDown/DisableDropDown resolve child regions via
    -- _G[frame:GetName()..suffix] on this client, so the frame must have a
    -- unique global name.
    dropdownCounter = dropdownCounter + 1
    local dropdown = CreateFrame("Frame", "CommanderUIDropDown" .. dropdownCounter, row, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", row, "TOPLEFT", -14, -14)
    UIDropDownMenu_SetWidth(dropdown, opts.width or DROPDOWN_WIDTH)
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

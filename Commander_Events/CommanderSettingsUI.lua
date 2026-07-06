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

local function AttachTooltip(widget, title, text)
    if not title and not text then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title or "", 1, 1, 1)
        if text then
            GameTooltip:AddLine(text, nil, nil, nil, true)
        end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function FormatValue(fmt, value)
    if type(fmt) == "function" then
        return fmt(value)
    end
    return string.format(fmt or "%.1f", value)
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

function PanelMethods.AddSection(panel, text)
    local row = panel:AddRow(24, 14)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 4)
    label:SetText(text)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", 8, 2)
    line:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    return row
end

function PanelMethods.AddSpacer(panel, height)
    return panel:AddRow(height or 8, 0)
end

-- opts: label, tooltip, get, set, isEnabled
function PanelMethods.AddCheckbox(panel, opts)
    local row = panel:AddRow(26, 2)
    local check = CreateFrame("CheckButton", nil, row, "InterfaceOptionsCheckButtonTemplate")
    check:SetPoint("LEFT", row, "LEFT", 0, 0)
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

    panel:_AddRefresher(function()
        check:SetChecked(opts.get() and true or false)
        local enabled = not opts.isEnabled or opts.isEnabled()
        check:SetEnabled(enabled)
        check:SetAlpha(enabled and 1 or DISABLED_ALPHA)
    end)

    return check
end

-- opts: label, tooltip, min, max, step, get, set, format, isEnabled
function PanelMethods.AddSlider(panel, opts)
    local row = panel:AddRow(50, 8)

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
    label:SetText(opts.label)

    local slider = CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -18)
    slider:SetWidth(SLIDER_WIDTH)
    slider:SetMinMaxValues(opts.min, opts.max)
    slider:SetValueStep(opts.step)
    slider:SetObeyStepOnDrag(true)
    slider.Text:SetText("")
    slider.Low:SetText(FormatValue(opts.format, opts.min))
    slider.High:SetText(FormatValue(opts.format, opts.max))
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
        panel:_Changed()
    end)

    panel:_AddRefresher(function()
        local value = Snap(opts.get() or opts.min)
        slider._lastValue = value
        slider:SetValue(value)
        valueText:SetText(FormatValue(opts.format, value))
        local enabled = not opts.isEnabled or opts.isEnabled()
        if enabled then slider:Enable() else slider:Disable() end
        local alpha = enabled and 1 or DISABLED_ALPHA
        slider:SetAlpha(alpha)
        label:SetAlpha(alpha)
        valueText:SetAlpha(alpha)
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

    panel:_AddRefresher(function()
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
            panel:_AddRefresher(function()
                button:SetEnabled(spec.isEnabled() and true or false)
            end)
        end
        previous = button
        created[#created + 1] = button
    end
    return created
end

function PanelMethods._AddRefresher(panel, fn)
    panel._refreshers[#panel._refreshers + 1] = fn
end

function PanelMethods.Refresh(panel)
    if panel._loading then return end
    panel._loading = true
    for _, fn in ipairs(panel._refreshers) do
        fn()
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

    -- Standardized slash commands: bare command opens the panel, registered
    -- subcommands (e.g. "reset") dispatch to their handler.
    if panel._slash and panel._slash[1] then
        local key = "COMMANDERUI_" .. panel._key:upper()
        for i, cmd in ipairs(panel._slash) do
            _G["SLASH_" .. key .. i] = cmd
        end
        local handlers = panel._slashHandlers or {}
        local usage = "Usage: " .. panel._slash[1]
        local subcommands = {}
        for sub in pairs(handlers) do
            subcommands[#subcommands + 1] = sub
        end
        table.sort(subcommands)
        if #subcommands > 0 then
            usage = usage .. " [" .. table.concat(subcommands, "|") .. "]"
        end
        SlashCmdList[key] = function(msg)
            msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if msg == "" then
                Settings.OpenToCategory(panel._categoryID)
            elseif handlers[msg] then
                handlers[msg]()
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
-- Panel constructor
-- ---------------------------------------------------------------------------

-- opts: key (unique short id), title (subcategory name), addonName,
--       description, event (Commander update event to listen for / notify),
--       slash (array of slash commands), slashHandlers (map subcommand->fn)
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

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT_MARGIN, -16)
    title:SetText("Commander |cffffffff" .. opts.title .. "|r")

    local version = C_AddOns.GetAddOnMetadata(opts.addonName, "Version")
    panel._version = version
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

    -- Anchor target for the first row
    local anchorSeed = CreateFrame("Frame", nil, panel)
    anchorSeed:SetHeight(1)
    anchorSeed:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, 0)
    anchorSeed:SetPoint("RIGHT", panel, "RIGHT", -RIGHT_MARGIN, 0)
    panel._anchor = anchorSeed

    return panel
end

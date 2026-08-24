-- Commander Debug — report builder and copy window
--
-- The report is a markdown prompt: a short brief telling Claude what to do
-- with the pile, the client context needed to avoid a fix written against the
-- wrong API version, and then every captured error as its own section.
--
-- The client has no clipboard API, so "copy to clipboard" is the same trick
-- every addon uses: a multiline EditBox holding the text, focused and
-- highlighted, and you press the copy key. What this addon adds is that the
-- text is worth pasting — assembled, deduped, attributed and prompted.
--
-- Build/Pages are pure string functions taking their inputs as arguments so
-- the headless harness can exercise them with no WoW client in sight.

BINDING_HEADER_COMMANDERDEBUG = "Commander Debug"
BINDING_NAME_COMMANDERDEBUG_TOGGLE = "Open the error report"
BINDING_NAME_COMMANDERDEBUG_COPY = "Open and select the report"

CommanderDebug = CommanderDebug or {}
local Capture = CommanderDebug.Capture
local Report = {}
CommanderDebug.Report = Report

local WINDOW_NAME = "CommanderDebugReport"

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

-- Reads the saved settings, falling back to the defaults for anything missing
-- so the builder can run before ADDON_LOADED (and inside the harness).
function CommanderDebug.Options()
    local db = _G.CommanderDebugDB or {}
    local defaults = CommanderDebug.Defaults or {}
    local opts = {}
    for key, value in pairs(defaults) do
        opts[key] = value
    end
    for key, value in pairs(db) do
        if opts[key] ~= nil then
            opts[key] = value
        end
    end
    return opts
end

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

-- Strip UI escape sequences: an EditBox renders |cff.. as colour rather than
-- text, so anything left in would silently vanish from what you paste.
local function Sanitize(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|n", "\n"):gsub("\r\n", "\n"):gsub("\r", "\n")
    text = text:gsub("%s+$", "")
    return text
end

CommanderDebug.Sanitize = Sanitize

-- Keep the first `limit` lines; the head of a stack is where the fix lives.
local function TrimLines(text, limit)
    if not text or limit <= 0 then return nil end
    local kept, count = {}, 0
    local dropped = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            if count < limit then
                count = count + 1
                kept[count] = line
            else
                dropped = dropped + 1
            end
        end
    end
    if count == 0 then return nil end
    if dropped > 0 then
        kept[count + 1] = string.format("... (%d more line%s trimmed)", dropped, dropped == 1 and "" or "s")
    end
    return table.concat(kept, "\n")
end

CommanderDebug.TrimLines = TrimLines

local function RelativeTime(epoch, now)
    if not epoch or epoch <= 0 then return "unknown" end
    local delta = (now or time()) - epoch
    if delta < 0 then delta = 0 end
    if delta < 60 then return string.format("%ds ago", delta) end
    if delta < 3600 then return string.format("%dm ago", math.floor(delta / 60)) end
    if delta < 86400 then return string.format("%dh ago", math.floor(delta / 3600)) end
    return string.format("%dd ago", math.floor(delta / 86400))
end

CommanderDebug.RelativeTime = RelativeTime

local function Clock(epoch)
    if not epoch or epoch <= 0 then return "??:??:??" end
    return date("%H:%M:%S", epoch)
end

-- The first source line in the error, which is the one worth naming up top.
local function OriginLine(record)
    local text = record.message or ""
    local file, line = text:match("([%w_%-%.]+%.lua):(%d+)")
    if file then
        local addon = record.addon and (record.addon .. "/") or ""
        return addon .. file .. ":" .. line
    end
    return record.addon or "unknown"
end

CommanderDebug.OriginLine = OriginLine

-- ---------------------------------------------------------------------------
-- Client context
-- ---------------------------------------------------------------------------

function CommanderDebug.Context()
    local version, build, buildDate, tocVersion = GetBuildInfo()
    local name = UnitName("player")
    local realm = GetRealmName and GetRealmName() or nil
    local class = UnitClass("player")   -- localized name, not the token
    local ctx = {
        version = version,
        build = build,
        buildDate = buildDate,
        toc = tocVersion,
        locale = GetLocale and GetLocale() or nil,
        player = name,
        realm = realm,
        level = UnitLevel and UnitLevel("player") or nil,
        class = class,
        source = Capture.SourceLabel(),
        now = time(),
    }
    return ctx
end

-- Loaded addons with versions, Commander first — the suite is what a fix will
-- most often have to reason about, everything else is background noise.
function CommanderDebug.LoadedAddons()
    local getNum = (C_AddOns and C_AddOns.GetNumAddOns) or _G.GetNumAddOns
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or _G.GetAddOnInfo
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if not (getNum and getInfo and isLoaded) then return {}, {} end

    local commander, other = {}, {}
    for i = 1, getNum() do
        if isLoaded(i) then
            local addonName = getInfo(i)
            if addonName then
                local addonVersion = getMeta and getMeta(i, "Version") or nil
                if addonVersion then
                    -- Some authors already ship the v; do not end up with "vv12.0"
                    addonVersion = addonVersion:gsub("^[vV]", "")
                end
                local entry = addonName .. (addonVersion and (" v" .. addonVersion) or "")
                if addonName:match("^Commander") then
                    commander[#commander + 1] = entry
                else
                    other[#other + 1] = entry
                end
            end
        end
    end
    return commander, other
end

-- ---------------------------------------------------------------------------
-- Report assembly
-- ---------------------------------------------------------------------------

local BRIEF = {
    "Every Lua error my World of Warcraft client raised is listed below. Work through all of them.",
    "",
    "For each error: read the source at the file and line named, find the actual cause (not just",
    "the symptom the error text describes), and fix it. Then say in one line what was wrong.",
    "",
    "- Group your work by addon, and fix shared root causes once rather than per error.",
    "- The occurrence count is a priority signal: something firing hundreds of times is in a hot",
    "  path or an OnUpdate, and matters more than a one-off.",
    "- Errors are deduped by message, so one entry can span the whole session.",
    "- Verify each API you reach for exists on this client build before using it. This is not retail.",
    "- If an error is not actually mine to fix (another author's addon, or a client quirk), say so",
    "  instead of inventing a fix.",
}

-- Returns the shared header, as a string.
function Report.Header(ctx, stats, opts, pageIndex, pageCount)
    local out = {}
    local function line(fmt, ...)
        out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    line("# Fix these World of Warcraft addon Lua errors")
    line("")
    for _, text in ipairs(BRIEF) do
        line(text)
    end
    line("")

    if pageCount and pageCount > 1 then
        line("> **Part %d of %d.** The errors are split across %d messages; this part is",
            pageIndex, pageCount, pageCount)
        line("> self-contained, and the remaining parts follow with the same header.")
        line("")
    end

    line("## Capture")
    line("")
    line("- **Source:** %s", ctx.source or "unknown")
    line("- **Scope:** %s", opts.Scope == "ALL"
        and "every error kept, across all sessions"
        or "this session only (since the last login or /reload)")
    line("- **Errors:** %d unique, %d total occurrences", stats.unique or 0, stats.occurrences or 0)
    if stats.newest then
        line("- **Window:** %s to %s", Clock(stats.oldest), Clock(stats.newest))
    end
    if (stats.hidden or 0) > 0 then
        line("- **Not shown:** %d more error%s outside the current scope, filter or cap",
            stats.hidden, stats.hidden == 1 and "" or "s")
    end
    if opts.OnlyCommander then
        line("- **Filter:** Commander_* addons only")
    end
    if not opts.IncludeStacks then
        line("- **Note:** call stacks were excluded from this report")
    end
    line("")

    if opts.IncludeSystemInfo then
        line("## Client")
        line("")
        line("- **Build:** %s (%s), interface %s, %s", tostring(ctx.version), tostring(ctx.build),
            tostring(ctx.toc), tostring(ctx.buildDate))
        if ctx.player then
            line("- **Character:** %s%s%s", ctx.player,
                ctx.realm and ("-" .. ctx.realm) or "",
                ctx.level and string.format(", level %d %s", ctx.level, tostring(ctx.class)) or "")
        end
        if ctx.locale then
            line("- **Locale:** %s", ctx.locale)
        end
        line("")
    end

    if opts.IncludeAddonList and ctx.addons then
        line("## Loaded addons")
        line("")
        if ctx.addons.commander and #ctx.addons.commander > 0 then
            line("Commander suite: %s", table.concat(ctx.addons.commander, ", "))
            line("")
        end
        if ctx.addons.other and #ctx.addons.other > 0 then
            line("Other: %s", table.concat(ctx.addons.other, ", "))
            line("")
        end
    end

    line("## Errors")
    return table.concat(out, "\n")
end

-- One error as its own markdown section.
function Report.Block(record, index, opts, now)
    local out = {}
    local function line(fmt, ...)
        out[#out + 1] = select("#", ...) > 0 and string.format(fmt, ...) or fmt
    end

    local occurrences = record.counter > 1
        and string.format(" — %d occurrences", record.counter)
        or ""
    -- Two blank lines: markdown wants one clear line before a heading, and
    -- the previous block ends flush against a closing fence.
    line("")
    line("")
    line("### %d. %s%s", index, OriginLine(record), occurrences)
    line("")
    line("*%s (%s)*", Clock(record.time), RelativeTime(record.time, now))
    line("")
    line("```")
    line("%s", Sanitize(record.message) or "<no message>")
    line("```")

    if opts.IncludeStacks then
        local stack = TrimLines(Sanitize(record.stack), opts.StackLines or 14)
        if stack then
            line("")
            line("Stack:")
            line("")
            line("```")
            line("%s", stack)
            line("```")
        end
    end

    if opts.IncludeLocals then
        local locals = TrimLines(Sanitize(record.locals), opts.LocalsLines or 20)
        if locals then
            line("")
            line("Locals:")
            line("")
            line("```")
            line("%s", locals)
            line("```")
        end
    end

    return table.concat(out, "\n")
end

local FOOTER = "\n\nGenerated by Commander Debug · /cdebug"

-- Splits the report into pages at error boundaries, each carrying the full
-- header so any one page stands alone as a prompt. Always returns at least
-- one page, even with nothing captured.
function Report.Pages(records, stats, ctx, opts, now)
    opts = opts or CommanderDebug.Options()
    now = now or (ctx and ctx.now) or time()

    if #records == 0 then
        local header = Report.Header(ctx, stats, opts, 1, 1)
        return { header .. "\n\nNo errors captured in this scope — nothing to fix. Change the scope in"
            .. "\nthe Commander Debug settings to reach further back." .. FOOTER }
    end

    local blocks = {}
    for index, record in ipairs(records) do
        blocks[index] = Report.Block(record, index, opts, now)
    end

    -- First pass with a placeholder page count, to learn how many pages the
    -- blocks need; the header grows by a couple of lines once it says
    -- "Part 1 of N", which is well inside the slack of a page budget.
    local budget = math.max(2000, tonumber(opts.PageSize) or 18000)
    local probe = #Report.Header(ctx, stats, opts, 1, 2) + #FOOTER

    local grouped, current, size = {}, {}, probe
    for _, block in ipairs(blocks) do
        if #current > 0 and (size + #block) > budget then
            grouped[#grouped + 1] = current
            current, size = {}, probe
        end
        current[#current + 1] = block
        size = size + #block
    end
    if #current > 0 then
        grouped[#grouped + 1] = current
    end

    local pages = {}
    for index, group in ipairs(grouped) do
        pages[index] = Report.Header(ctx, stats, opts, index, #grouped)
            .. table.concat(group)
            .. FOOTER
    end
    return pages
end

-- Everything in one call: read the capture layer, build the pages.
function CommanderDebug.BuildPages()
    local opts = CommanderDebug.Options()
    local records, stats = Capture.GetErrors({
        scope = opts.Scope,
        onlyCommander = opts.OnlyCommander,
        max = opts.MaxErrors,
    })
    local ctx = CommanderDebug.Context()
    if opts.IncludeAddonList then
        local commander, other = CommanderDebug.LoadedAddons()
        ctx.addons = { commander = commander, other = other }
    end
    return Report.Pages(records, stats, ctx, opts, ctx.now), records, stats
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local window = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
window:SetSize(680, 520)
window:SetPoint("CENTER", 0, 20)
window:SetFrameStrata("DIALOG")
window:SetMovable(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", function(self) self:StartMoving() end)
window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
window:SetClampedToScreen(true)
window:Hide()
Commander.UI.ApplyStyleBackdrop(window, "DARK")
if UISpecialFrames then
    table.insert(UISpecialFrames, WINDOW_NAME)
end

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", 12, -10)
title:SetText("Commander Debug — Error Report")

local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", 2, 2)

local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
hint:SetPoint("RIGHT", window, "RIGHT", -12, 0)
hint:SetJustifyH("LEFT")

local scroll = CreateFrame("ScrollFrame", WINDOW_NAME .. "Scroll", window, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -50)
scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -30, 42)

local edit = CreateFrame("EditBox", nil, scroll)
edit:SetMultiLine(true)
edit:SetAutoFocus(false)
edit:SetMaxLetters(0)
edit:SetFontObject(GameFontHighlightSmall)
edit:SetWidth(616)
edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
scroll:SetScrollChild(edit)

local pages, pageIndex = {}, 1
local UpdatePagingButtons  -- defined once the buttons exist

local function CopyKeyHint()
    local mac = type(IsMacClient) == "function" and IsMacClient()
    return mac and "Cmd+C" or "Ctrl+C"
end

local function SelectAll()
    edit:SetFocus()
    edit:HighlightText()
end

local function ShowPage(index)
    if #pages == 0 then return end
    pageIndex = math.max(1, math.min(index, #pages))
    edit:SetText(pages[pageIndex])
    if edit.SetCursorPosition then
        edit:SetCursorPosition(0)
    end
    scroll:SetVerticalScroll(0)
    local paging = #pages > 1
        and string.format("Part %d of %d — copy each part into its own message.  ", pageIndex, #pages)
        or ""
    hint:SetText(paging .. "Select All, then " .. CopyKeyHint() .. " — paste into Claude as-is.")
    UpdatePagingButtons()
    if CommanderDebug.Options().AutoSelect then
        SelectAll()
    end
end

local function Rebuild()
    local built, _, stats = CommanderDebug.BuildPages()
    pages = built
    if pageIndex > #pages then pageIndex = 1 end
    ShowPage(pageIndex)
    return stats
end

CommanderDebug.Rebuild = Rebuild

local selectAllButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
selectAllButton:SetSize(110, 22)
selectAllButton:SetPoint("BOTTOMLEFT", 12, 10)
selectAllButton:SetText("Select All")
selectAllButton:SetScript("OnClick", SelectAll)
Commander.UI.AttachTooltip(selectAllButton, "Select All",
    "Highlight the whole report so " .. CopyKeyHint() .. " takes all of it. The client has no clipboard API — this is as close as an addon can get.")

local refreshButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
refreshButton:SetSize(100, 22)
refreshButton:SetPoint("LEFT", selectAllButton, "RIGHT", 8, 0)
refreshButton:SetText("Rebuild")
refreshButton:SetScript("OnClick", function() Rebuild() end)
Commander.UI.AttachTooltip(refreshButton, "Rebuild",
    "Re-read the captured errors and regenerate the prompt — for when something new fires while this window is open.")

local prevButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
prevButton:SetSize(70, 22)
prevButton:SetPoint("LEFT", refreshButton, "RIGHT", 8, 0)
prevButton:SetText("< Prev")
prevButton:SetScript("OnClick", function() ShowPage(pageIndex - 1) end)

local nextButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
nextButton:SetSize(70, 22)
nextButton:SetPoint("LEFT", prevButton, "RIGHT", 4, 0)
nextButton:SetText("Next >")
nextButton:SetScript("OnClick", function() ShowPage(pageIndex + 1) end)

local settingsButton = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
settingsButton:SetSize(90, 22)
settingsButton:SetPoint("BOTTOMRIGHT", -12, 10)
settingsButton:SetText("Settings")
settingsButton:SetScript("OnClick", function()
    if CommanderDebug.CategoryID then
        Settings.OpenToCategory(CommanderDebug.CategoryID)
    end
end)

function UpdatePagingButtons()
    prevButton:SetShown(#pages > 1)
    nextButton:SetShown(#pages > 1)
    prevButton:SetEnabled(pageIndex > 1)
    nextButton:SetEnabled(pageIndex < #pages)
end

window:SetScript("OnShow", function() Rebuild() end)

-- ---------------------------------------------------------------------------
-- Clear confirmation
-- ---------------------------------------------------------------------------

StaticPopupDialogs["COMMANDER_DEBUG_CLEAR"] = {
    text = "Throw away every captured error?\n\nThis empties the shared error database, so BugSack loses them too. There is no undo.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        Capture.Clear()
        print("|cff33ff99Commander Debug|r: captured errors cleared")
        if window:IsShown() then
            Rebuild()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- Public entry points (slash commands, keybinding, other modules)
-- ---------------------------------------------------------------------------

function CommanderDebug_Show()
    if window:IsShown() then
        Rebuild()          -- already open: refresh in place
    else
        window:Show()      -- OnShow rebuilds
    end
end

function CommanderDebug_Hide()
    window:Hide()
end

function CommanderDebug_Toggle()
    if window:IsShown() then
        window:Hide()
    else
        CommanderDebug_Show()
    end
end

-- Open and go straight to selected text, one keystroke from pasted.
function CommanderDebug_Copy()
    CommanderDebug_Show()
    SelectAll()
    if #pages > 1 then
        print(string.format("|cff33ff99Commander Debug|r: report split into %d parts — copy each in turn with Next.", #pages))
    end
end

function CommanderDebug_Clear()
    StaticPopup_Show("COMMANDER_DEBUG_CLEAR")
end

-- A one-screen summary in chat, for when you just want to know what is broken.
function CommanderDebug_List()
    local opts = CommanderDebug.Options()
    local records, stats = Capture.GetErrors({
        scope = opts.Scope,
        onlyCommander = opts.OnlyCommander,
        max = opts.MaxErrors,
    })
    print(string.format("|cff33ff99Commander Debug|r: %d unique error%s (%d occurrences) via %s",
        stats.unique, stats.unique == 1 and "" or "s", stats.occurrences, Capture.SourceLabel()))
    if stats.unique == 0 then
        print("  Nothing captured in this scope. |cffffd200/cdebug|r to change it.")
        return
    end
    for index, record in ipairs(records) do
        if index > 10 then
            print(string.format("  ... and %d more — |cffffd200/cdebug|r for the full report", stats.unique - 10))
            break
        end
        local first = (Sanitize(record.message) or ""):match("^[^\n]*") or ""
        if #first > 90 then first = first:sub(1, 87) .. "..." end
        print(string.format("  |cffffd200%d.|r %s |cff888888(x%d, %s)|r",
            index, first, record.counter, RelativeTime(record.time)))
    end
end

-- Deliberately raises one error so you can confirm the whole path works.
function CommanderDebug_RaiseTestError()
    print("|cff33ff99Commander Debug|r: raising a test error — it is harmless, and it should appear in the report.")
    local ok, err = pcall(function()
        local absent
        return absent.field
    end)
    if not ok then
        geterrorhandler()("Commander Debug test error: " .. tostring(err))
    end
end

-- Keep the window honest while it is open and settings change underneath it.
Commander.AddListener(COMMANDER_DEBUG_EVENTS.UPDATE, function()
    if window:IsShown() then
        Rebuild()
    end
end)

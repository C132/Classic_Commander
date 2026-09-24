-- Commander.UI settings-framework smoke (luajit):
--     luajit settings_ui_smoke.lua
--
-- Covers the piece every module in the suite now leans on: a settings page
-- that SCROLLS. A canvas subcategory is handed a fixed viewport and clips
-- whatever runs past it — no scrollbar, no error, just options that stop
-- existing, and since Finalize adds the footer last, the first casualty of
-- an overlong page is Restore Defaults. Sixteen modules had each grown
-- their own copy of the scroll frame to escape that; this checks the one
-- that replaced them.
--
-- Mock modeled on Commander_Debug/Harness.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

print = function() end

local caughtErrors = {}
local errorHandler = function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
function geterrorhandler() return errorHandler end

local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2,
    GetNumPoints = 1, GetVerticalScroll = 0, GetVerticalScrollRange = 0,
}

local function IsMethodName(key)
    return type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Add") or key:match("^Has"))
end

local eventRegistry = {}
local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    local simple = {
        SetPoint = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint,
                x = x, y = y }
        end,
        ClearAllPoints = function(s) s.__points = nil end,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        SetWidth = function(s, w) s.__w = w end,
        SetHeight = function(s, h) s.__h = h end,
        -- A real page is about 680 wide; the scroll child reports whatever it
        -- has actually been given, which is what the wrap measuring reads
        GetWidth = function(s) return s.__w or 680 end,
        GetHeight = function(s) return s.__h or 520 end,
        SetText = function(s, text) s.__text = text end,
        GetText = function(s) return s.__text end,
        -- Two lines at the size the framework assumes, unless a test says
        -- otherwise: that is what GrowRow is measuring
        GetStringHeight = function(s) return s.__stringHeight or 20 end,
        Show = function(s) s.__shown = true end,
        Hide = function(s) s.__shown = false end,
        IsShown = function(s) return s.__shown end,
        SetShown = function(s, v) s.__shown = not not v end,
        SetScript = function(s, name, handler) s.__scripts[name] = handler end,
        HookScript = function(s, name, handler) s.__scripts[name] = handler end,
        GetScript = function(s, name) return s.__scripts[name] end,
        RegisterEvent = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end,
        CreateTexture = function(s)
            local t = NewWidget("Texture"); t.__parent = s
            s.__children[#s.__children + 1] = t
            return t
        end,
        CreateFontString = function(s)
            local t = NewWidget("FontString"); t.__parent = s
            s.__children[#s.__children + 1] = t
            return t
        end,
        SetScrollChild = function(s, child) s.__child = child end,
        GetParent = function(s) return s.__parent end,
    }
    local fn = simple[key]
    if fn then rawset(self, key, fn); return fn end
    if IsMethodName(key) then
        local blank = function() end
        rawset(self, key, blank); return blank
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __children = {},
        __shown = true }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if parent and parent.__children then
        parent.__children[#parent.__children + 1] = f
    end
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    return f
end

UIParent = NewWidget("Frame", "UIParent")
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall" }) do
    _G[f] = NewWidget("Font")
end

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
SlashCmdList = {}

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(_, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

C_AddOns = { GetAddOnMetadata = function() return "9.9.9" end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end

-- ===========================================================================
-- Load the real framework
-- ===========================================================================

assert(loadfile(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua"))()

Commander.MainCategory = { GetID = function() return 1 end }
Commander.AddListener = function() end
Commander.Notify = function() end

local UI = Commander.UI

-- Walk a widget tree looking for a frame, so "is this row inside the scroll
-- child" is answered by descent rather than taken on faith
local function IsDescendantOf(widget, ancestor)
    local node = widget
    while node do
        if node == ancestor then return true end
        node = node.__parent
    end
    return false
end

local function FindText(root, needle)
    for _, child in ipairs(root.__children or {}) do
        if child.__text and tostring(child.__text):find(needle, 1, true) then return child end
        local found = FindText(child, needle)
        if found then return found end
    end
    return nil
end

-- ===========================================================================
-- A page is built the way every module builds one
-- ===========================================================================

local DB = { Thing = true }
local panel = UI.NewPanel({
    key = "SmokeOne",
    title = "Smoke One",
    addonName = "Commander_Events",
    description = "A page built exactly the way a module builds one.",
    slash = { "/csmoke" },
    foldSections = false,   -- the plain layout, which the checks below pin
})

CHECK(panel._scroll ~= nil, "the page has a scroll frame")
CHECK(panel._scroll and panel._scroll.__template == "UIPanelScrollFrameTemplate",
    "on the client's own scroll template", panel._scroll and panel._scroll.__template)
CHECK(panel._scroll and panel._scroll.__name == "CommanderUIScrollSmokeOne",
    "named, because the template finds its scrollbar by name",
    panel._scroll and panel._scroll.__name)
CHECK(panel._content ~= nil and panel._scroll.__child == panel._content,
    "with a scroll child attached to it")
CHECK(panel._scroll.__parent == panel,
    "the scroll frame hangs on the canvas the Settings window registers")

-- The header is deliberately NOT in the scroll child: the title, version and
-- description hold still while the options move under them
local title = FindText(panel, "Smoke One")
CHECK(title ~= nil and not IsDescendantOf(title, panel._content),
    "the header stays fixed on the canvas above the scroll")

local firstRow = panel:AddRow(30, 6)
CHECK(IsDescendantOf(firstRow, panel._content),
    "rows flow into the scroll child, not onto the clipped canvas")

panel:AddSection("Section", "A note under the section heading.")
panel:AddCheckbox({
    label = "A Thing",
    tooltip = "Toggles the thing.",
    get = function() return DB.Thing end,
    set = function(v) DB.Thing = v end,
})
panel:AddSlider({
    label = "A Number",
    tooltip = "Sets the number.",
    min = 1, max = 10, step = 1,
    get = function() return DB.Number or 5 end,
    set = function(v) DB.Number = v end,
})

local flowed = panel._contentHeight
panel:Finalize({ onDefaults = function() end })

-- The whole point: the child is as tall as what was put in it, so the page
-- can be scrolled to the end of it
CHECK(panel._content:GetHeight() > flowed,
    "Finalize sizes the scroll child to the content that was flowed",
    panel._content:GetHeight())
CHECK(panel._content:GetHeight() >= panel._contentHeight,
    "and the footer row is inside that height, not past it",
    panel._content:GetHeight() .. " vs " .. panel._contentHeight)

-- Restore Defaults is the control an overlong page used to lose first,
-- because Finalize adds it last
local footerButton = FindText(panel, "Restore Defaults")
CHECK(footerButton ~= nil, "the Restore Defaults footer was drawn")
CHECK(footerButton and IsDescendantOf(footerButton, panel._content),
    "and it is inside the scroll child, so an overlong page can reach it")

-- ===========================================================================
-- A section note that turns out to wrap taller than declared has to move the
-- scroll child with it, or the last rows sit past the end of the page
-- ===========================================================================

local before = panel._content:GetHeight()
local note = FindText(panel, "A note under the section heading.")
CHECK(note ~= nil, "the section note was drawn")
if note then
    note.__stringHeight = 200   -- a long note on a narrow page
    panel:Refresh()
end
CHECK(panel._content:GetHeight() > before,
    "a note that grows on refresh grows the scroll child with it",
    before .. " -> " .. panel._content:GetHeight())

-- ...and re-measuring is idempotent, so a second refresh does not creep
local settled = panel._content:GetHeight()
panel:Refresh()
CHECK(panel._content:GetHeight() == settled,
    "and re-measuring the same page does not creep",
    settled .. " -> " .. panel._content:GetHeight())

-- ===========================================================================
-- The wheel, including both ends of it
-- ===========================================================================

local scroll = panel._scroll
local wheel = scroll.__scripts.OnMouseWheel
CHECK(wheel ~= nil, "the wheel scrolls the page")
if wheel then
    local at = 100
    scroll.GetVerticalScroll = function() return at end
    scroll.GetVerticalScrollRange = function() return 400 end
    scroll.SetVerticalScroll = function(_, value) at = value end
    wheel(scroll, -1)
    CHECK(at == 128, "down moves down the page", at)
    wheel(scroll, 1)
    CHECK(at == 100, "and up moves back", at)
    at = 10
    wheel(scroll, 1)
    CHECK(at == 0, "it stops at the top rather than scrolling past it", at)
    at = 390
    wheel(scroll, -1)
    CHECK(at == 400, "and at the bottom", at)
end

-- The scroll child has no width of its own; without one every row inside it
-- measures zero and the page draws as a column of invisible frames
local sized = scroll.__scripts.OnSizeChanged
CHECK(sized ~= nil, "the scroll frame hands its width down to the child")
if sized then
    sized(scroll, 640)
    CHECK(panel._content:GetWidth() == 640, "the child takes the viewport's width",
        panel._content:GetWidth())
end

-- ===========================================================================
-- Two pages must not share a scroll frame name, or the second one's
-- scrollbar resolves to the first one's
-- ===========================================================================

local second = UI.NewPanel({
    key = "SmokeTwo",
    title = "Smoke Two",
    addonName = "Commander_Events",
    description = "A second page.",
})
second:AddRow(20, 6)
second:Finalize({})
CHECK(second._scroll.__name ~= panel._scroll.__name,
    "a second page gets its own scroll frame name", second._scroll.__name)
CHECK(second._content ~= panel._content, "and its own scroll child")

-- A key that is not name-safe still has to produce a usable global name
local odd = UI.NewPanel({
    key = "Smoke Three!",
    title = "Smoke Three",
    addonName = "Commander_Events",
    description = "A page whose key is not name-safe.",
})
CHECK(odd._scroll.__name == "CommanderUIScrollSmokeThree",
    "a key with punctuation is reduced to a name the client can resolve",
    odd._scroll.__name)

-- ===========================================================================
-- Foldouts and search
-- ===========================================================================

CHECK(panel._hasFolds == nil, "a page that never folds never re-flows (the old layout, untouched)")

local FDB = { A = true, B = false, C = 3, ShowBeta = true }
local fp = UI.NewPanel({ key = "SmokeFold", title = "Smoke Fold", addonName = "Commander_Events", description = "Folding." })
fp:AddCheckbox({ label = "Enable", get = function() return true end, set = function() end })
fp:AddSearchBox()
local alpha = fp:AddFoldout("Alpha", "What alpha is for.", { key = "a" })
local rowA = fp:AddRow(26, 2); fp:TagRow(rowA, "Execute Marker", "A line at twenty percent.")
fp:AddCheckbox({ label = "Plain Toggle", tooltip = "Nothing special.", get = function() return FDB.A end, set = function(v) FDB.A = v end })
local beta = fp:AddFoldout("Beta", nil, { key = "b", expanded = true, isShown = function() return FDB.ShowBeta end,
    summary = function() return "C is " .. FDB.C end })
fp:AddSlider({ label = "Gamma Size", tooltip = "How big.", min = 1, max = 5, step = 1, get = function() return FDB.C end, set = function(v) FDB.C = v end })
fp:Finalize({ onDefaults = function() end })

local function Shown(row) return row.__shown ~= false end
local function EntryFor(fold)
    local out = {}
    for _, e in ipairs(fp._rows) do if e.fold == fold then out[#out + 1] = e.row end end
    return out
end
local alphaRows, betaRows = EntryFor(alpha), EntryFor(beta)
CHECK(#alphaRows == 2 and #betaRows == 1, "rows belong to the foldout they were added under", #alphaRows .. "/" .. #betaRows)
CHECK(not Shown(alphaRows[1]) and not Shown(alphaRows[2]), "a foldout starts shut unless it says otherwise")
CHECK(Shown(betaRows[1]), "...and open when it does")
CHECK(Shown(alpha.header) and Shown(beta.header), "headers are always there")
CHECK(alpha.note.__shown == false and alpha.header.__h == 22, "a shut foldout hides its note and is one header tall")
local footerRow = fp._rows[#fp._rows].row
CHECK(footerRow._panelEntry.fold == nil and Shown(footerRow), "the footer belongs to no foldout")
local shutHeight = fp._content:GetHeight()

-- Beta's first row sits right under Beta's header: shut rows take no room
local p1 = betaRows[1].__points and betaRows[1].__points[1]
CHECK(p1 and p1.rel == beta.header, "an open row is anchored to the row above it that is actually shown")
local hp = beta.header.__points and beta.header.__points[1]
CHECK(hp and hp.rel == alpha.header, "...and a shut foldout's rows are skipped entirely")

alpha.button.__scripts.OnClick(alpha.button)
CHECK(Shown(alphaRows[1]) and Shown(alphaRows[2]) and alpha.note.__shown == true, "clicking the header opens it, note and all")
CHECK(fp._content:GetHeight() > shutHeight, "...and the page grows by what it opened", shutHeight .. " -> " .. fp._content:GetHeight())
CHECK(CommanderUIDB and CommanderUIDB.Folds["SmokeFold:a"] == true, "...and remembers it")
alpha.button.__scripts.OnClick(alpha.button)
CHECK(not Shown(alphaRows[1]) and fp._content:GetHeight() == shutHeight, "clicking again shuts it and gives the room back")

-- A page rebuilt later reopens the way it was left
CommanderUIDB.Folds["SmokeFold2:a"] = true
local fp2 = UI.NewPanel({ key = "SmokeFold2", title = "Smoke Fold 2", addonName = "Commander_Events", description = "x" })
local remembered = fp2:AddFoldout("Alpha", nil, { key = "a" })
fp2:Finalize({})
CHECK(remembered.expanded == true, "the remembered state beats the default")

-- isShown: a foldout that does not apply disappears, header and all
FDB.ShowBeta = false
fp:Refresh()
CHECK(not Shown(beta.header) and not Shown(betaRows[1]), "isShown false hides the whole foldout")
FDB.ShowBeta = true
fp:Refresh()
CHECK(Shown(beta.header) and Shown(betaRows[1]), "...and it comes back with its setting")

-- The summary is drawn while shut
beta.button.__scripts.OnClick(beta.button)
CHECK(beta.summaryText.__text == "C is 3" and beta.summaryText.__shown == true, "a shut foldout shows its summary")
beta.button.__scripts.OnClick(beta.button)
CHECK(beta.summaryText.__shown == false, "...an open one does not need it")

-- Search: by a control's tooltip, by a foldout's own title
local box = fp._searchBox
box.HasFocus = function() return false end
box.__text = "twenty"
box.__scripts.OnTextChanged(box)
CHECK(Shown(alpha.header) and Shown(alphaRows[1]) and not Shown(alphaRows[2]), "searching opens the foldout and shows only the match (found in its tooltip)")
CHECK(not Shown(beta.header), "...a foldout with no match is hidden")
CHECK(Shown(footerRow) and Shown(fp._rows[1].row), "...rows outside every foldout stay")
CHECK(alpha.expanded == false, "...without changing what is remembered")
box.__text = "BETA"
box.__scripts.OnTextChanged(box)
CHECK(Shown(beta.header) and Shown(betaRows[1]) and not Shown(alpha.header), "a foldout's own title matches all of it, any case")
box.__scripts.OnEscapePressed(box)
CHECK(fp._search == nil and not Shown(alphaRows[1]) and Shown(betaRows[1]), "Escape clears the search and the page is as it was")

fp:SetAllFoldouts(true)
CHECK(Shown(alphaRows[1]) and Shown(betaRows[1]), "Expand All")
fp:SetAllFoldouts(false)
CHECK(not Shown(alphaRows[1]) and not Shown(betaRows[1]), "Collapse All")

-- Automatic foldouts: a module's ordinary AddSection calls fold on their own
local ap = UI.NewPanel({ key = "SmokeAuto", title = "Smoke Auto", addonName = "Commander_Events", description = "x" })
local topRow = ap:AddRow(20, 6)
local secRows = {}
for i = 1, 5 do
    secRows[i] = ap:AddSection("Section " .. i, i == 1 and "A note." or nil)
    ap:AddCheckbox({ label = "Option " .. i, tooltip = "Tip " .. i, get = function() return true end, set = function() end })
end
ap:AddSection("Kept Plain", nil, { plain = true })
ap:Finalize({})
CHECK(#ap._folds == 5 and ap._folds[1].auto, "five AddSection calls became five foldouts", #ap._folds)
CHECK(secRows[1] == ap._folds[1].header, "AddSection still returns the header row")
CHECK(ap._folds[1].expanded == true and ap._folds[2].expanded == false, "a long page opens its first foldout and shuts the rest")
CHECK(ap._searchBox ~= nil, "...and gets a search box")
local searchAt, firstHeaderAt
for i, e in ipairs(ap._rows) do
    if e.row == ap._searchBox:GetParent() then searchAt = i end
    if e.header and not firstHeaderAt then firstHeaderAt = i end
end
CHECK(searchAt and firstHeaderAt and searchAt == firstHeaderAt - 1, "...placed just above the first foldout", tostring(searchAt) .. "/" .. tostring(firstHeaderAt))
local plainHeader = FindText(ap._content, "Kept Plain")
CHECK(plainHeader ~= nil and plainHeader:GetParent()._panelEntry.header == nil, "plain = true keeps an ordinary heading")
local sp = UI.NewPanel({ key = "SmokeShort", title = "Smoke Short", addonName = "Commander_Events", description = "x" })
sp:AddSection("Only"); sp:AddCheckbox({ label = "A", get = function() return true end, set = function() end })
sp:AddSection("Two"); sp:AddCheckbox({ label = "B", get = function() return true end, set = function() end })
sp:Finalize({})
CHECK(sp._folds[1].expanded and sp._folds[2].expanded and sp._searchBox == nil, "a short page opens everything and needs no search")
-- A row grown by a ticker (outside any refresh) re-flows a folding page at once
local grown = sp._rows[2].row
local before2 = sp._content:GetHeight()
sp:GrowRow(grown, 200)
CHECK(sp._content:GetHeight() > before2, "growing a row outside a refresh re-flows the page", before2 .. " -> " .. sp._content:GetHeight())

CHECK(#caughtErrors == 0, "no refresher raised across the whole run", caughtErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

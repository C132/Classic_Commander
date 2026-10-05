-- Commander Orders: the manager window.
--
-- The arrow answers "which way". This window answers "what have I got":
-- every waypoint you and the rest of the suite have set, every route, the
-- places you keep, and a box to paste a list of /way lines into. TomTom never
-- had one (tomtom.md 4: "/way list" in chat was all there was), which is why
-- a pasted list of forty quest givers felt like a pile instead of a plan.
--
-- ---------------------------------------------------------------------------
-- The shape
-- ---------------------------------------------------------------------------
-- The suite's own window: the Quest Log's dark stone sheet (dialog border,
-- header plate, a WHITE8X8 floor under it; QuestLog D16/D17), the Contacts
-- list on the left and detail on the right. Three tabs across the top:
--
--   Waypoints  the list, grouped: Arrow (what the arrow follows right now),
--              Routes (each route with its stops under it, foldable), then
--              every other waypoint by zone, or by who set it ("Group by"
--              at the top of the list). Rows carry the waypoint's tint, its
--              title, zone, live distance (1 Hz while the window is open)
--              and a source tag. The detail pane edits the title in place
--              and offers Set as arrow / Rename / Share / Copy /way / Remove;
--              a route offers Start / Previous / Next / Reverse / Optimise
--              order / Export / Remove route. Remove stands apart, bottom
--              right, where a quick click along the row cannot land on it.
--              The arrival time shows for the arrow's own target only: the
--              speed filter behind it is the arrow's, and a guess for every
--              row would be a guess. "Add here" and "Clear..." sit on the
--              toolbar.
--   Places     the account-wide named spots (the old rally points), with Go
--              there / Rename / Copy /way / Remove and "Mark place here".
--   Paste      SPEC 7.5: paste any number of /way lines, with or without the
--              /way in front (TomTom B18 stripped the first word of every
--              line, so a bare "45 66" lost its x), import them as waypoints
--              or as a route (in order, or nearest first), keep the text as
--              a named page, export waypoints or a route back to /way lines
--              (a nil title is simply left off, never "nil": B18 again).
--
-- The SPEC drew "Paste..." and "Places" as toolbar buttons that open
-- sub-panels. They are tabs here: each is a whole view of the same window,
-- and a tab says which one you are looking at, where a button that swapped
-- the body out from under you would not.
--
-- ---------------------------------------------------------------------------
-- Why it reads one way and writes another
-- ---------------------------------------------------------------------------
-- Reading goes through CommanderOrders.R, the runtime's surface for the pins
-- and this window: the LIVE store (no copy per row per second), a fresh ctx,
-- the words the arrow uses for a waypoint. Every change goes through the
-- public API (CommanderOrders.SetArrow, .Update, .Remove, .Import, ...),
-- never into a record: the API is what refuses while Orders is off, saves,
-- plays the cue, announces, and fires the debounced CHANGED event. This
-- window listens to CHANGED and rebuilds, so a waypoint added by a Waypoint
-- button anywhere in the suite appears here without the window knowing who
-- added it.
--
-- ---------------------------------------------------------------------------
-- Traps worth knowing before changing anything
-- ---------------------------------------------------------------------------
-- * Never take the keyboard on open (QuestLog D12). An EditBox's autoFocus
--   defaults to TRUE: shown, it grabs the keyboard and the player walks into
--   a wall typing "wwww" into a search box. Every box here is SetAutoFocus
--   (false); focus only ever follows a click on the box itself, on Rename,
--   or on Export (so Ctrl+C works at once). The harness asserts it.
-- * The multi-line paste box. With an OnEnterPressed script set, the client
--   no longer puts the newline in itself (Blizzard's ScrollingEditBox does
--   the same Insert("\n")), so the script inserts it, and Ctrl+Enter imports
--   instead. ScrollingEdit_OnTextChanged / _OnCursorChanged / _OnUpdate keep
--   the caret in view; each is guarded.
-- * UIPanelScrollFrameTemplate resolves its children through _G[name ..
--   "ScrollBar"], so every scroll frame here has a global name, and the
--   shared SlimScrollBar takes the stepper buttons off.
-- * Rows are pooled. Every pass sets every text and every colour again
--   (QuestLog D15): a row that showed a route header last time must not
--   keep its chevron, its count or its ink.
-- * The list is REBUILT only when something changed (CHANGED, search, tab,
--   grouping, folding). The 1 Hz pass rewrites the distance strings and
--   nothing else, so rows never reorder under the cursor while you walk.
-- * A rebuild never overwrites the title box while it has the keyboard: the
--   arrow ticking over mid-rename would otherwise eat what you typed.
-- * D11: no shape glyphs in any string. The chevrons are two quads, the
--   markers are our own textures, separators are words and commas.
-- * FrameXML tables are only added to: one UISpecialFrames entry (Esc
--   closes), one StaticPopupDialogs key.
--
-- ---------------------------------------------------------------------------
-- Globals and saved keys
-- ---------------------------------------------------------------------------
-- Writes no global of its own except named frames (a scroll frame needs a
-- name; InputBoxTemplate's edge textures hang off $parent): the window
-- CommanderOrdersManager; CommanderOrdersManagerListScroll,
-- CommanderOrdersManagerPasteScroll, CommanderOrdersManagerPagesScroll (and
-- their template children); CommanderOrdersManagerSearch,
-- CommanderOrdersManagerTitleBox, CommanderOrdersManagerRouteTitle,
-- CommanderOrdersManagerPageName (and theirs). All are made on first open,
-- none at load. Saved: CommanderOrdersDB.ManagerPos, .ManagerScale and
-- .ManagerGroupBy, kept OUT of the defaults like Contacts' LastTab, so
-- Restore Defaults leaves where you put the window alone.
--
-- Public: O.UI.Open(uid | routeId), Toggle(), OpenPaste(text), OpenPlaces(),
-- Close(), IsShown(), Refresh(), Select(kind, id); the runtime calls Open,
-- Toggle and OpenPaste (guarded). O.UI._W() / _State() are for the harness.

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
O.UI = O.UI or {}
local UIM = O.UI
local D = O.Data or {}

local type, pairs, ipairs, tostring, pcall = type, pairs, ipairs, tostring, pcall
local format, strlower, tconcat, tsort = string.format, string.lower, table.concat, table.sort
local floor, max, min = math.floor, math.max, math.min

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local QUAD = "Interface\\Buttons\\WHITE8X8"
local FRAME_NAME = "CommanderOrdersManager"
local FRAME_W, FRAME_H = 660, 440
local PAD = 14                    -- inside the dialog border's visible band
local TOOLBAR_Y = -30
local TOOLBAR_H = 24
local BODY_TOP = -62
local BODY_BOTTOM = 14
local LIST_W = 270
local ROW_H = 34
local HEADER_H = 20
local GROUP_H = 24                -- the "Group by" strip over the list
local BUTTON_H = 21
local ICON = 14
local INDENT = 12                 -- route stops under their route
local LIVE_INTERVAL = 1.0         -- seconds between distance passes
local ERRORS_SHOWN = 4            -- unreadable paste lines listed by name, at most
-- The paste result box, for fitting the error list into it: its size as laid
-- out in the 660x440 window (the client's own GetWidth / GetHeight win once
-- it has laid the box out), the small font's line height and a generous
-- average letter width, so the estimate errs towards listing fewer
local RESULT_W, RESULT_H = 424, 107
local RESULT_LINE_H, RESULT_CHAR_W = 12, 6
local ERROR_TEXT = 24             -- letters of a bad line quoted next to its number
local MAX_LETTERS = 30000         -- the paste box (TomTom's own limit)
local PAGES_W = 196
local INFO_LABEL_W = 64
local TITLE_LETTERS = 100

local TEX = D.TEXTURES or {}
local ICON_COLOURS = D.ICON_COLOURS or {}
local PAL = D.PALETTE or {}

-- One light ink set for the dark stone (QuestLog INK.DARK, Contacts SKIN)
local INK = {
    primary = { 0.88, 0.88, 0.91 },
    secondary = { 0.72, 0.72, 0.76 },
    faint = { 0.54, 0.54, 0.58 },
    header = { 0.66, 0.66, 0.72 },
    strong = { 1.00, 0.95, 0.80 },
    title = { 1.00, 0.82, 0.30 },
    warn = { 1.00, 0.56, 0.30 },
    good = { 0.45, 0.88, 0.45 },
}
local SKIN = { selection = 0.30, hover = 0.12, rule = { 1, 1, 1, 0.15 } }

local SHEET_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local SHEET_BASE = { 0.09, 0.09, 0.10 }
local PANE_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TABS = {
    { id = "WAYPOINTS", label = "Waypoints", width = 86 },
    { id = "PLACES", label = "Places", width = 66 },
    { id = "PASTE", label = "Paste", width = 60 },
}

local PASTE_MODES = {
    { id = "WAYPOINTS", label = "Waypoints", width = 74 },
    { id = "ORDERED", label = "A route, in order", width = 112 },
    { id = "NEAREST", label = "A route, nearest first", width = 136 },
}

-- Who set a waypoint, in words (the tag on a row, the "Set by" line), and
-- the tint of a source that names no icon itself: Data's tables, shared
-- with the pins so a source never wears two colours
local SOURCE_WORDS = D.SOURCE_WORDS or {}
local SOURCE_ICON = D.SOURCE_ICONS or {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local W = {                       -- widgets (built on first open)
    rows = {}, info = {}, actions = {}, actionByKey = {}, pageRows = {}, tabs = {},
    groupButtons = {}, modeButtons = {}, boxes = {},
}
local state = {
    tab = "WAYPOINTS",
    sel = {},                     -- per tab: { kind = "wp"|"route"|"place", uid|id|index }
    search = "",
    folded = {},                  -- route ids and group keys folded this session
    entries = {},
    dirty = true,
    pasteMode = "WAYPOINTS",
    liveAcc = 0,
}

local List, Detail, Paste, Places, Tabs, Build, Live = {}, {}, {}, {}, {}, {}, {}
local EMPTY = {}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function DB()
    local db = CommanderOrdersDB
    if type(db) ~= "table" then return EMPTY end
    return db
end

local function R() return O.R or EMPTY end

local function Store()
    local fn = R().Store
    return fn and fn() or nil
end

local function Enabled() return DB().EnableOrders and true or false end

local function Say(msg)
    local fn = R().Say
    if fn then fn(msg) else print("Commander Orders: " .. msg) end
end

local function Accent()
    local fn = R().Accent
    if fn then return fn() end
    return 1, 1, 1
end

local function Report(err)
    if geterrorhandler then
        local handler = geterrorhandler()
        if handler then handler(err) end
    end
end

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Lower(s) return strlower(tostring(s or "")) end

-- Cut to n bytes on a UTF-8 boundary, with "..." (plain dots: D11)
local function Cut(s, n)
    if type(s) ~= "string" or #s <= n then return s end
    local cut = n - 3
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut) .. "..."
end

local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

local function Ink(fs, shade)
    local c = INK[shade or "primary"] or INK.primary
    fs:SetTextColor(c[1], c[2], c[3])
end

local function NoWrap(fs)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
end

local function Rule(parent)
    local tex = Quad(parent, "ARTWORK")
    tex:SetHeight(1)
    tex:SetColorTexture(SKIN.rule[1], SKIN.rule[2], SKIN.rule[3], SKIN.rule[4])
    return tex
end

-- The text a FontString or EditBox shows, written only when it changes
local function SetIf(region, text)
    text = text or ""
    if region.ordersText ~= text then
        region.ordersText = text
        region:SetText(text)
    end
end

local function Title(wp)
    local fn = R().Title
    if fn then return fn(wp) end
    return wp and wp.title or ""
end

local function ZoneName(map)
    if type(map) ~= "number" then return nil end
    local fn = R().MapName
    return (fn and fn(map)) or ("Map " .. map)
end

local function Coords(x, y)
    local G = O.Geo
    return (G and G.FormatCoords and G.FormatCoords(x, y, 1)) or ""
end

local function WhereText(p)
    if type(p) ~= "table" or type(p.map) ~= "number" then return nil end
    return (ZoneName(p.map) or ("Map " .. p.map)) .. " " .. Coords(p.x, p.y)
end

local function WayLineOf(p)
    local G = O.Geo
    if not (G and G.WayLine and type(p) == "table" and p.map) then return nil end
    return G.WayLine(p.map, p.x, p.y, p.title)
end

local function SourceLabel(source)
    if type(source) ~= "string" then return "Unknown" end
    local w = SOURCE_WORDS[source]
    if w then return w end
    local from = source:match("^share:(.+)$")
    if from then return "From " .. from end
    local tt = source:match("^TomTom:(.*)$")
    if tt then
        if tt == "" or tt == "?" then return "TomTom request" end
        return tt .. " (TomTom)"
    end
    return source
end

-- The colour key of a waypoint: its own colour, its icon, else its source
local function IconKey(wp)
    if wp.colour and ICON_COLOURS[wp.colour] then return wp.colour end
    if wp.icon and ICON_COLOURS[wp.icon] then return wp.icon end
    if wp.kind == "corpse" then return "CORPSE" end
    if wp.kind == "stop" then return "ROUTE" end
    local s = wp.source
    if SOURCE_ICON[s] then return SOURCE_ICON[s] end
    if type(s) == "string" then
        if s:sub(1, 6) == "share:" then return "SHARE" end
        if s:sub(1, 7) == "TomTom:" then return "TOMTOM" end
    end
    return "USER"
end

local function IconColour(key)
    local c = ICON_COLOURS[key] or ICON_COLOURS.USER or { 1, 0.82, 0.3 }
    return c[1], c[2], c[3]
end

local function WhenText(stamp)
    if type(stamp) ~= "number" or stamp <= 0 or type(date) ~= "function" then return nil end
    local now = (time and time()) or stamp
    local ok, day = pcall(date, "%Y-%j", stamp)
    if not ok then return nil end
    local clock = date("%H:%M", stamp)
    if day == date("%Y-%j", now) then return "Today, " .. clock end
    if day == date("%Y-%j", now - 86400) then return "Yesterday, " .. clock end
    return date("%d %b %Y", stamp)
end

local function InGroup()
    return IsInGroup and IsInGroup() and true or false
end

local function Faction()
    if not UnitFactionGroup then return nil end
    return (UnitFactionGroup("player"))
end

-- ---------------------------------------------------------------------------
-- Distances, in words
-- ---------------------------------------------------------------------------
local function LandOf(map)
    local fn = R().Landmass
    if not (fn and type(map) == "number") then return nil end
    local ok, key = pcall(fn, map)
    if not ok or key == nil then return nil end
    local names = D.LANDMASS_NAMES or EMPTY
    local name = names[key]
    return key, name and (name:gsub("^the ", "")) or nil
end

-- A waypoint that cannot be measured says where it is when that is another
-- landmass ("Outland"), and nothing when there is no position to measure from
local function FarText(p, ctx)
    if not (p and p.map and ctx and ctx.player and ctx.player.map) then return "" end
    local key, name = LandOf(p.map)
    local here = LandOf(ctx.player.map)
    if key and here and key ~= here then return name or "elsewhere" end
    return ""
end

local function YardsText(yards)
    local fn = R().Distance
    return (fn and fn(yards)) or (floor(yards + 0.5) .. " yd")
end

local function DistanceOf(wp, ctx)
    local st = Store()
    if not (st and wp) then return "", nil end
    local ok, d = pcall(st.Distance, st, wp, ctx)
    if ok and type(d) == "number" then return YardsText(d), d end
    return FarText(wp, ctx), nil
end

local function PlaceDistance(p, ctx)
    if not (ctx and ctx.player and type(ctx.distance) == "function") then return "", nil end
    local ok, d = pcall(ctx.distance, ctx.player, p)
    if ok and type(d) == "number" then return YardsText(d), d end
    return FarText(p, ctx), nil
end

local function Ctx()
    local fn = R().Ctx
    if not fn then return nil end
    local ok, c = pcall(fn)
    return ok and c or nil
end

-- ---------------------------------------------------------------------------
-- Widgets: buttons, chevrons, boxes
-- ---------------------------------------------------------------------------
local function Tooltip(widget, title, text)
    widget.tooltipTitle, widget.tooltipText = title, text
    widget:HookScript("OnEnter", function(self)
        if not (GameTooltip and self.tooltipTitle) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
        local body = self.tooltipText
        if type(body) == "function" then body = body() end
        if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
        GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- A flat text button with a hover wash and an accent underline (Contacts'
-- tabs): the tabs, "Group by" and the paste modes
local function TextButton(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b:EnableMouse(true)
    b.label = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    b.label:SetPoint("CENTER", b, "CENTER", 0, 1)
    b.label:SetText(label)
    b.text = label
    b.underline = Quad(b, "ARTWORK")
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 1)
    b.underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 1)
    b.underline:Hide()
    b.hover = Quad(b, "BACKGROUND")
    b.hover:SetAllPoints(b)
    b.hover:Hide()
    b:SetScript("OnEnter", function(self)
        local r, g, bl = Accent()
        self.hover:SetColorTexture(r, g, bl, SKIN.hover)
        self.hover:Show()
    end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

local function PaintTextButton(b, active)
    local r, g, bl = Accent()
    b.underline:SetColorTexture(r, g, bl, 1)
    b.underline:SetShown(active and true or false)
    Ink(b.label, active and "primary" or "faint")
end

local function PanelButton(parent, label, width, onClick, tipTitle, tipText)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, BUTTON_H)
    b:EnableMouse(true)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tipTitle then Tooltip(b, tipTitle, tipText) end
    return b
end

local function InputBox(name, parent, width, letters)
    local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetMaxLetters(letters)
    if box.SetTextColor then box:SetTextColor(INK.primary[1], INK.primary[2], INK.primary[3]) end
    W.boxes[#W.boxes + 1] = box
    return box
end

-- A faint hint inside an empty box, gone while it has the keyboard
local function Ghost(box, text, x)
    local ghost = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ghost:SetPoint("LEFT", box, "LEFT", x or 2, 0)
    ghost:SetPoint("RIGHT", box, "RIGHT", -2, 0)
    ghost:SetJustifyH("LEFT")
    NoWrap(ghost)
    ghost:SetText(text)
    Ink(ghost, "faint")
    box.ghost = ghost
    return ghost
end

local function SyncGhost(box)
    if not box.ghost then return end
    local empty = (box:GetText() or "") == ""
    box.ghost:SetShown(empty and not (box.HasFocus and box:HasFocus()))
end

-- Two bars make a chevron (D11: no glyph): open points down, shut points right
local function PointChevron(owner, open, x)
    if not owner.chevron then
        owner.chevron = { Quad(owner, "OVERLAY"), Quad(owner, "OVERLAY") }
        for _, bar in ipairs(owner.chevron) do bar:SetSize(6, 2) end
    end
    local a, b = owner.chevron[1], owner.chevron[2]
    local c = INK.header
    for _, bar in ipairs(owner.chevron) do
        bar:SetColorTexture(c[1], c[2], c[3], 0.9)
        bar:ClearAllPoints()
        bar:Show()
    end
    x = x or 8
    if open then
        a:SetPoint("CENTER", owner, "LEFT", x - 2, 0)
        b:SetPoint("CENTER", owner, "LEFT", x + 2, 0)
        a:SetRotation(-math.pi / 4)
        b:SetRotation(math.pi / 4)
    else
        a:SetPoint("CENTER", owner, "LEFT", x, 2)
        b:SetPoint("CENTER", owner, "LEFT", x, -2)
        a:SetRotation(math.pi / 4)
        b:SetRotation(-math.pi / 4)
    end
end

local function HideChevron(owner)
    if not owner.chevron then return end
    owner.chevron[1]:Hide()
    owner.chevron[2]:Hide()
end

local function WheelScroll(scroll, step)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = (self:GetVerticalScroll() or 0) - delta * (step or 32)
        local limit = self:GetVerticalScrollRange() or 0
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)
end

local function MakePane(parent)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if pane.SetBackdrop then
        pane:SetBackdrop(PANE_BACKDROP)
        pane:SetBackdropColor(0, 0, 0, 0.5)
        pane:SetBackdropBorderColor(0.45, 0.40, 0.32, 1)
    end
    return pane
end

local function ShowMenu(entries, anchor)
    local fn = R().ShowMenu
    if fn then return fn(entries, anchor) end
    return false
end

-- ---------------------------------------------------------------------------
-- Position
-- ---------------------------------------------------------------------------
local function SavePosition()
    local f = W.frame
    if not f then return end
    local point, _, _, x, y = f:GetPoint(1)
    if not point then return end
    local scale = f:GetScale() or 1
    local db = CommanderOrdersDB
    if type(db) == "table" then db.ManagerPos = { point = point, x = (x or 0) * scale, y = (y or 0) * scale } end
end

local function ApplyPosition()
    local f = W.frame
    if not f or f._dragging then return end
    local scale = tonumber(DB().ManagerScale) or 1
    if scale < 0.6 or scale > 1.6 then scale = 1 end
    f:SetScale(scale)
    f:ClearAllPoints()
    local pos = DB().ManagerPos
    if type(pos) == "table" and type(pos.point) == "string" then
        f:SetPoint(pos.point, UIParent, pos.point, (tonumber(pos.x) or 0) / scale, (tonumber(pos.y) or 0) / scale)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    end
end

-- ---------------------------------------------------------------------------
-- The list: entries
-- ---------------------------------------------------------------------------
-- An entry is what a row shows:
--   { kind = "header", key, label, count, fold }
--   { kind = "wp", wp, uid, stop = index | nil, depth, isTarget }
--   { kind = "route", route, id, active }
--   { kind = "place", place, index }
local function Matches(wp, needle)
    if needle == "" then return true end
    local find = string.find
    if find(Lower(Title(wp)), needle, 1, true) then return true end
    if wp.map and find(Lower(ZoneName(wp.map)), needle, 1, true) then return true end
    if find(Lower(SourceLabel(wp.source)), needle, 1, true) then return true end
    if wp.note and find(Lower(wp.note), needle, 1, true) then return true end
    return false
end

local function GroupBy()
    return DB().ManagerGroupBy == "SOURCE" and "SOURCE" or "ZONE"
end

-- key, label, rank of the group a standalone waypoint falls in
local function GroupOf(wp, playerMap)
    if GroupBy() == "SOURCE" then
        local s = wp.source
        if s == "user" or s == "legacy" then return "s:user", "Yours", 0 end
        if s == "place" then return "s:place", "Places", 1 end
        if type(s) == "string" and s:sub(1, 6) == "share:" then return "s:share", "Shared with you", 2 end
        if s == "corpse" then return "s:corpse", "Corpse", 3 end
        return "s:" .. tostring(s), SourceLabel(s), 4
    end
    if not wp.map then return "z:unit", "Group members", 3 end
    if wp.map == playerMap then return "z:" .. wp.map, ZoneName(wp.map), 0 end
    return "z:" .. wp.map, ZoneName(wp.map), 1
end

local function ByTitle(a, b)
    local ta, tb = Lower(Title(a)), Lower(Title(b))
    if ta ~= tb then return ta < tb end
    return tostring(a.uid) < tostring(b.uid)
end

local function Header(out, key, label, count, fold, noCount)
    out[#out + 1] = { kind = "header", key = key, label = label, count = count, fold = fold,
                      folded = fold and state.folded[key] or false, noCount = noCount }
end

function List.BuildWaypoints(ctx)
    local out = {}
    local st = Store()
    if not st then return out end
    local needle = Lower(Trim(state.search))
    local target, why
    if Enabled() then
        local ok, wp, reason = pcall(st.ActiveTarget, st, ctx)
        if ok then target, why = wp, reason end
    end
    state.target, state.targetWhy = target, why

    -- The arrow's target, first
    if target and Matches(target, needle) then
        Header(out, "ARROW", "Arrow", 1, false, true)
        out[#out + 1] = { kind = "wp", wp = target, uid = target.uid, isTarget = true,
                          stop = target.routeId and target.routeIndex or nil, depth = 0 }
    end

    -- Routes, each with its stops under it
    local routes = st:Routes()
    local active = st:ActiveRoute()
    local block = {}
    for _, route in ipairs(routes) do
        local titleHit = needle == "" or Lower(route.title):find(needle, 1, true) ~= nil
        local stops = {}
        for i, uid in ipairs(route.stops) do
            local wp = st:Get(uid)
            if wp and (titleHit or Matches(wp, needle)) then
                stops[#stops + 1] = { kind = "wp", wp = wp, uid = uid, stop = i, depth = 1,
                                      isTarget = wp == target }
            end
        end
        if titleHit or #stops > 0 then
            local folded = state.folded[route.id] and true or false
            block[#block + 1] = { kind = "route", route = route, id = route.id, active = route == active,
                                  folded = folded }
            if not folded then
                for _, e in ipairs(stops) do block[#block + 1] = e end
            end
        end
    end
    if #block > 0 then
        local n = 0
        for _, e in ipairs(block) do if e.kind == "route" then n = n + 1 end end
        Header(out, "ROUTES", "Routes", n, false)
        for _, e in ipairs(block) do out[#out + 1] = e end
    end

    -- Every other waypoint, by zone or by source
    local playerMap = ctx and ctx.player and ctx.player.map
    local groups, order = {}, {}
    for _, wp in ipairs(st:List({ routeId = false })) do
        if wp ~= target and Matches(wp, needle) then
            local key, label, rank = GroupOf(wp, playerMap)
            local g = groups[key]
            if not g then
                g = { key = key, label = label or "?", rank = rank, list = {} }
                groups[key] = g
                order[#order + 1] = g
            end
            g.list[#g.list + 1] = wp
        end
    end
    tsort(order, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return Lower(a.label) < Lower(b.label)
    end)
    for _, g in ipairs(order) do
        tsort(g.list, ByTitle)
        Header(out, g.key, g.label, #g.list, true)
        if not state.folded[g.key] then
            for _, wp in ipairs(g.list) do
                out[#out + 1] = { kind = "wp", wp = wp, uid = wp.uid, depth = 0 }
            end
        end
    end
    return out
end

local function PlaceList()
    local fn = O.Places
    if type(fn) ~= "function" then return {} end
    local list = fn()
    return type(list) == "table" and list or {}
end

function List.BuildPlaces()
    local out = {}
    local needle = Lower(Trim(state.search))
    local mine = Faction()
    for _, p in ipairs(PlaceList()) do
        local hit = needle == "" or Lower(p.title):find(needle, 1, true)
            or Lower(p.zone):find(needle, 1, true)
        if hit then
            out[#out + 1] = { kind = "place", place = p, index = p.index,
                              otherFaction = p.faction and mine and p.faction ~= mine and p.faction or nil }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The list: rows
-- ---------------------------------------------------------------------------
local function SameSelection(entry, sel)
    if not sel then return false end
    if entry.kind == "wp" then return sel.kind == "wp" and sel.uid == entry.uid end
    if entry.kind == "route" then return sel.kind == "route" and sel.id == entry.id end
    if entry.kind == "place" then return sel.kind == "place" and sel.index == entry.index end
    return false
end

function List.Row(i)
    local row = W.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, W.listChild)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = Quad(row, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:Hide()
    row.bar = Quad(row, "ARTWORK")
    row.bar:SetWidth(3)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    row.bar:Hide()

    row.ring = row:CreateTexture(nil, "ARTWORK", nil, 0)
    row.ring:SetTexture(TEX.RING)
    row.ring:SetSize(ICON * 1.7, ICON * 1.7)
    row.ring:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK", nil, 1)
    row.icon:SetSize(ICON, ICON)
    row.ring:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.badge:SetPoint("CENTER", row.icon, "CENTER", 0, 0)

    row.dist = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.dist:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -5)
    row.dist:SetJustifyH("RIGHT")
    NoWrap(row.dist)
    row.tag = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.tag:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 6)
    row.tag:SetJustifyH("RIGHT")
    NoWrap(row.tag)
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.label:SetJustifyH("LEFT")
    NoWrap(row.label)
    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sub:SetJustifyH("LEFT")
    NoWrap(row.sub)
    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.count:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e or self.selected or (e.kind == "header" and not e.fold) then return end
        local r, g, b = Accent()
        self.highlight:SetColorTexture(r, g, b, SKIN.hover)
        self.highlight:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if not self.selected then self.highlight:Hide() end
    end)
    row:SetScript("OnClick", function(self, button) List.Click(self.entry, button, self) end)
    row:SetScript("OnDoubleClick", function(self)
        local e = self.entry
        if e and e.kind == "wp" then Detail.SetArrow(e.uid) end
    end)
    W.rows[i] = row
    return row
end

local function PaintHeader(row, e)
    row:SetHeight(HEADER_H)
    row.icon:Hide()
    row.ring:Hide()
    row.badge:Hide()
    row.sub:Hide()
    row.dist:Hide()
    row.tag:Hide()
    row.count:Show()
    row.label:ClearAllPoints()
    if e.fold then PointChevron(row, not e.folded, 9) else HideChevron(row) end
    row.label:SetPoint("LEFT", row, "LEFT", 18, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.label:SetFontObject(GameFontNormalSmall)
    row.label:SetText(e.label or "")
    Ink(row.label, "header")
    row.count:SetText((e.count and not e.noCount) and tostring(e.count) or "")
    Ink(row.count, "faint")
end

local function PaintBody(row, indent)
    row:SetHeight(ROW_H)
    row.count:Hide()
    row.icon:Show()
    row.sub:Show()
    row.dist:Show()
    row.tag:Show()
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 10 + indent, 4)
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 28 + indent, -4)
    row.label:SetPoint("RIGHT", row.dist, "LEFT", -6, 0)
    row.label:SetFontObject(GameFontNormal)
    row.sub:ClearAllPoints()
    row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.tag, "LEFT", -6, 0)
end

local function PaintWaypoint(row, e, ctx)
    local wp = e.wp
    PaintBody(row, (e.depth or 0) * INDENT)
    HideChevron(row)
    local key = IconKey(wp)
    local r, g, b = IconColour(key)
    if wp.kind == "corpse" then
        row.icon:SetTexture(TEX.CORPSE)
        row.badge:Hide()
    elseif e.stop then
        row.icon:SetTexture(TEX.BADGE)
        row.badge:SetText(tostring(e.stop))
        row.badge:SetTextColor(1, 1, 1)
        row.badge:Show()
    else
        row.icon:SetTexture(TEX.PIN)
        row.badge:Hide()
    end
    row.icon:SetVertexColor(r, g, b)
    row.icon.iconKey = key
    if e.isTarget then
        local c = PAL.GOOD or INK.good
        row.ring:SetVertexColor(c[1], c[2], c[3])
        row.ring:Show()
    else
        row.ring:Hide()
    end
    row.label:SetText(Title(wp))
    Ink(row.label, (e.isTarget and "strong") or (wp.reached and "secondary") or "primary")
    local sub
    if wp.kind == "unit" then
        sub = "Following a group member"
    elseif wp.map and wp.kind == "point" and not (wp.title and wp.title ~= "") then
        -- the title line already reads its place (R.Title): no zone twice
        sub = "Untitled waypoint"
    elseif wp.map then
        sub = ZoneName(wp.map)
        if wp.alternatives and #wp.alternatives > 1 then
            sub = sub .. ", nearest of " .. #wp.alternatives
        end
    else
        sub = ""
    end
    row.sub:SetText(sub)
    Ink(row.sub, "faint")
    SetIf(row.dist, (DistanceOf(wp, ctx)))
    row.distText = row.dist.ordersText
    Ink(row.dist, e.isTarget and "strong" or "secondary")
    local own = (D.USER_SOURCES or EMPTY)[wp.source] and wp.source ~= "place"
    row.tag:SetText((wp.reached and "reached") or (own and "") or Cut(SourceLabel(wp.source), 18))
    Ink(row.tag, wp.reached and "good" or "faint")
end

local function ModeText(route)
    local words = route.mode == "NEAREST" and "Nearest first" or "In order"
    if route.loop then words = words .. ", a loop" end
    return words
end

local function PaintRoute(row, e)
    local route = e.route
    PaintBody(row, 8)
    PointChevron(row, not e.folded, 8)
    row.icon:SetTexture(TEX.BADGE)
    local r, g, b = IconColour("ROUTE")
    row.icon:SetVertexColor(r, g, b)
    row.icon.iconKey = "ROUTE"
    row.badge:Hide()
    row.ring:Hide()
    row.label:SetText((route.title and route.title ~= "") and route.title or "Route")
    Ink(row.label, e.active and "strong" or "primary")
    row.sub:SetText(ModeText(route) .. ", " .. Plural(#route.stops, "stop", "stops"))
    Ink(row.sub, "faint")
    SetIf(row.dist, format("Stop %d of %d", route.index or 1, #route.stops))
    row.distText = row.dist.ordersText
    Ink(row.dist, e.active and "strong" or "secondary")
    local own = (D.USER_SOURCES or EMPTY)[route.source]
    row.tag:SetText((e.active and "running") or (own and "") or Cut(SourceLabel(route.source), 18))
    Ink(row.tag, e.active and "good" or "faint")
end

local function PaintPlace(row, e, ctx)
    local p = e.place
    PaintBody(row, 0)
    HideChevron(row)
    row.icon:SetTexture(TEX.PIN)
    local r, g, b = IconColour("PLACE")
    row.icon:SetVertexColor(r, g, b)
    row.icon.iconKey = "PLACE"
    row.badge:Hide()
    row.ring:Hide()
    row.label:SetText(p.title or "Place")
    Ink(row.label, "primary")
    row.sub:SetText(WhereText(p) or "")
    Ink(row.sub, "faint")
    SetIf(row.dist, (PlaceDistance(p, ctx)))
    row.distText = row.dist.ordersText
    Ink(row.dist, "secondary")
    row.tag:SetText(e.otherFaction or "")
    Ink(row.tag, "warn")
end

function List.Paint(row, e, ctx)
    row.entry = e
    row.selected = false
    row.highlight:Hide()
    row.bar:Hide()
    if e.kind == "header" then
        PaintHeader(row, e)
        row:EnableMouse(e.fold and true or false)
        return
    end
    row:EnableMouse(true)
    if e.kind == "wp" then
        PaintWaypoint(row, e, ctx)
    elseif e.kind == "route" then
        PaintRoute(row, e)
    else
        PaintPlace(row, e, ctx)
    end
    if SameSelection(e, state.sel[state.tab]) then
        local r, g, b = Accent()
        row.selected = true
        row.highlight:SetColorTexture(r, g, b, SKIN.selection)
        row.highlight:Show()
        row.bar:SetColorTexture(r, g, b, 1)
        row.bar:Show()
    end
end

function List.Rebuild()
    if not W.listChild then return end
    local ctx = Ctx()
    local entries
    if state.tab == "PLACES" then entries = List.BuildPlaces() else entries = List.BuildWaypoints(ctx) end
    state.entries = entries
    local offset = 0
    for i, e in ipairs(entries) do
        local row = List.Row(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", W.listChild, "TOPLEFT", 0, -offset)
        row:SetPoint("TOPRIGHT", W.listChild, "TOPRIGHT", 0, -offset)
        List.Paint(row, e, ctx)
        row:Show()
        e.offset = offset
        offset = offset + (e.kind == "header" and HEADER_H or ROW_H)
    end
    for i = #entries + 1, #W.rows do
        W.rows[i].entry = nil
        W.rows[i]:Hide()
    end
    W.listChild:SetHeight(max(offset, 1))

    local any = false
    for _, e in ipairs(entries) do if e.kind ~= "header" then any = true break end end
    if any then
        W.listEmpty:Hide()
    else
        local searching = Trim(state.search) ~= ""
        if searching then
            W.listEmpty:SetText("Nothing matches that.")
        elseif state.tab == "PLACES" then
            W.listEmpty:SetText("No places yet.\n\nMark place here (above) keeps where you stand, for every character on this account.")
        else
            W.listEmpty:SetText("No waypoints yet.\n\nType /way 45 66 Name, Ctrl+Right-click the world map, press Add here above, or paste a list on the Paste tab.")
        end
        Ink(W.listEmpty, "faint")
        W.listEmpty:Show()
    end
end

-- Bring the selected row into view (Open(uid) from the arrow or a pin). A
-- scroll frame knows its height and range only after a layout pass, so the
-- callers ask for it a frame later (List.RevealSoon).
function List.Reveal()
    local scroll = W.listScroll
    if not scroll then return end
    local sel = state.sel[state.tab]
    for _, e in ipairs(state.entries) do
        if SameSelection(e, sel) and e.offset then
            local top = scroll:GetVerticalScroll() or 0
            local height = scroll:GetHeight() or 0
            if height > 0 and (e.offset < top or e.offset + ROW_H > top + height) then
                local range = scroll:GetVerticalScrollRange() or 0
                scroll:SetVerticalScroll(max(0, min(range, e.offset - ROW_H)))
            end
            return
        end
    end
end

function List.RevealSoon()
    if C_Timer and C_Timer.After then C_Timer.After(0, List.Reveal) else List.Reveal() end
end

function List.Click(e, button, row)
    if not e then return end
    if e.kind == "header" then
        if e.fold then
            state.folded[e.key] = not state.folded[e.key] or nil
            List.Rebuild()
        end
        return
    end
    if e.kind == "route" and button ~= "RightButton" and state.sel.WAYPOINTS
        and state.sel.WAYPOINTS.kind == "route" and state.sel.WAYPOINTS.id == e.id then
        -- a second click on the selected route folds or unfolds it
        state.folded[e.id] = not state.folded[e.id] or nil
        List.Rebuild()
        return
    end
    if e.kind == "wp" then
        UIM.Select("wp", e.uid)
    elseif e.kind == "route" then
        UIM.Select("route", e.id)
    else
        UIM.Select("place", e.index)
    end
    if button == "RightButton" then Detail.RowMenu(e, row) end
end

-- ---------------------------------------------------------------------------
-- The detail pane
-- ---------------------------------------------------------------------------
-- A view is { title, editable, ghost, kind, info = { { label, value, shade } },
-- actions = { { key, label, width, onClick, tip, disabled } }, live = fn(ctx) ->
-- value of info[liveIndex] }.
local function Status(text, shade)
    state.status, state.statusShade = text, shade
    if W.status then
        W.status:SetText(text or "")
        Ink(W.status, shade or "secondary")
    end
end

local function Reason(err)
    if err == "disabled" then return "Commander Orders is turned off (/corder to turn it on)." end
    if err == "loading" then return "Still loading." end
    if err == "unknown" or err == "unknown waypoint" then return "That waypoint is gone." end
    if err == "not in a group" then return "You are not in a group." end
    if err == "no position" then return "There is no map position here (instances have none)." end
    if err == "no world position" then return "That map has no world coordinates." end
    return tostring(err or "That did not work.")
end

function Detail.SetArrow(uid)
    local ok, err = O.SetArrow(uid)
    if ok then Status("The arrow follows it now.", "good") else Status(Reason(err), "warn") end
end

function Detail.Share(uid, channel)
    local ok, err = O.Share(uid, channel)
    if ok then
        Status(channel == nil and "Sent to your group." or "Posted in chat as a /way line.", "good")
    else
        Status("Could not share: " .. Reason(err), "warn")
    end
end

function Detail.ShareMenu(uid, anchor)
    local group = InGroup()
    local entries = { { text = "Share", isTitle = true } }
    entries[#entries + 1] = { text = "With your group", disabled = not group,
        func = function() Detail.Share(uid, nil) end }
    if group then
        entries[#entries + 1] = { text = "As a /way line in group chat", func = function() Detail.Share(uid, "CHAT") end }
    end
    entries[#entries + 1] = { text = "As a /way line in /say", func = function() Detail.Share(uid, "SAY") end }
    ShowMenu(entries, anchor)
end

function Detail.Rename()
    local box = W.titleBox
    if not (box and box:IsShown()) then return end
    box:SetFocus()
    if box.HighlightText then box:HighlightText() end
end

local function Copy(text)
    local fn = R().CopyLine
    if text and fn then fn(text) end
end

local function WaypointActions(wp, route)
    local uid = wp.uid
    local actions = {
        { key = "arrow", label = "Set as arrow", width = 96, onClick = function() Detail.SetArrow(uid) end,
          tip = route and "Point the arrow here: the route jumps to this stop." or "Point the arrow at this waypoint." },
        { key = "rename", label = "Rename", width = 70, onClick = function() Detail.Rename() end,
          tip = "Type a new title in the box above, then press Enter." },
        { key = "share", label = "Share", width = 64, disabled = not wp.map,
          onClick = function(self) Detail.ShareMenu(uid, self) end,
          tip = "Send it to your group, or post it in chat as a /way line for players without addons." },
        { key = "copy", label = "Copy /way", width = 80, disabled = not wp.map,
          onClick = function() Copy(O.WayLine(uid)) end, tip = "A /way line to copy and paste anywhere." },
        { key = "remove", label = "Remove", width = 70, danger = true, onClick = function()
            local title = Title(wp)
            if O.Remove(uid) then
                state.sel.WAYPOINTS = nil
                Status("Removed " .. Cut(title, 40) .. ".", "secondary")
            end
        end, tip = "Remove this waypoint." },
    }
    return actions
end

local WHY_WORDS = {
    CORPSE = "Following it: your corpse comes first",
    PINNED = "Following it: you chose it",
    ROUTE = "Following it: the route's current stop",
    CLOSEST = "Following it: the closest waypoint",
}

function Detail.WaypointView(sel)
    local st = Store()
    local wp = st and st:Get(sel.uid)
    if not wp then return nil end
    local route = wp.routeId and st:GetRoute(wp.routeId)
    local view = { editable = true, title = wp.title or "", ghost = "Untitled: " .. (WhereText(wp) or "a waypoint") }
    if route then
        view.kind = format("Stop %d of %d on %s", wp.routeIndex or 0, #route.stops,
            (route.title and route.title ~= "") and route.title or "a route")
    elseif wp.kind == "corpse" then
        view.kind = "Your corpse"
    elseif wp.kind == "unit" then
        view.kind = "Follows a group member"
    else
        view.kind = "Waypoint"
    end
    local info = {}
    if wp.map then info[#info + 1] = { "Where", WhereText(wp) } end
    info[#info + 1] = { "Distance", "", "secondary" }
    view.liveIndex = #info
    view.live = function(ctx)
        local text, yards = DistanceOf(wp, ctx)
        local target = state.target
        if yards and target == wp then
            local eta = R().Eta and R().Eta()
            local G = O.Geo
            local words = eta and G and G.FormatEta and G.FormatEta(eta)
            if words then text = text .. ", about " .. words end
        end
        if text == "" then text = (ctx and ctx.player) and "Cannot measure from here" or "No position here" end
        return text
    end
    info[#info + 1] = { "Set by", SourceLabel(wp.source) }
    if state.target == wp then
        info[#info + 1] = { "Arrow", WHY_WORDS[state.targetWhy] or "Following it", "good" }
    end
    if wp.alternatives and #wp.alternatives > 1 then
        info[#info + 1] = { "Spots", format("The nearest of %d", #wp.alternatives) }
    end
    if wp.reached then
        info[#info + 1] = { "Reached", WhenText(wp.reached) or "yes", "good" }
    end
    local yards = wp.arrive or DB().ArriveYards or 10
    info[#info + 1] = { "Arrival", format("Within %d yd, then %s", floor(yards + 0.5),
        wp.clearOnArrive and "it clears" or "it stays, ticked off") }
    if wp.note then info[#info + 1] = { "Note", wp.note } end
    local when = WhenText(wp.created)
    if when then info[#info + 1] = { "Added", when } end
    if not wp.persistent then info[#info + 1] = { "Kept", "This session only", "faint" } end
    view.info = info
    view.actions = WaypointActions(wp, route)
    return view
end

function Detail.RouteAction(id, fn, done, verb)
    local a, err = fn(id)
    if a then
        Status(done, "good")
    elseif err == "last stop" then
        Status("That was the last stop: arriving there finishes the route.", "secondary")
    elseif err == "first stop" then
        Status("That is the first stop.", "secondary")
    elseif err == "no distance" then
        Status("Cannot " .. verb .. " from here: there is no position to measure from.", "warn")
    else
        Status(Reason(err), "warn")
    end
end

function Detail.RouteView(sel)
    local st = Store()
    local route = st and st:GetRoute(sel.id)
    if not route then return nil end
    local id = route.id
    local active = st:ActiveRoute() == route
    local view = { editable = false, title = (route.title and route.title ~= "") and route.title or "Route" }
    view.kind = active and "Route, running" or "Route"
    local current = st:Get(route.stops[route.index or 1] or "")
    local info = {
        { "Order", ModeText(route) },
        { "Stops", format("%s, on stop %d", Plural(#route.stops, "stop", "stops"), route.index or 1) },
    }
    if current then
        info[#info + 1] = { "Next", Title(current) }
        info[#info + 1] = { "Distance", "", "secondary" }
        view.liveIndex = #info
        view.live = function(ctx)
            local text = DistanceOf(current, ctx)
            if text == "" then text = (ctx and ctx.player) and "Cannot measure from here" or "No position here" end
            return text
        end
    end
    info[#info + 1] = { "Set by", SourceLabel(route.source) }
    local when = WhenText(route.created)
    if when then info[#info + 1] = { "Added", when } end
    view.info = info
    view.actions = {
        { key = "start", label = active and "Restart" or "Start", width = 66,
          onClick = function() Detail.RouteAction(id, O.RouteStart, "The arrow follows the route.", "start") end,
          tip = "Point the arrow at the route's current stop (a nearest-first route re-orders from where you stand)." },
        { key = "prev", label = "Previous", width = 74,
          onClick = function() Detail.RouteAction(id, O.RoutePrev, "Back one stop.", "step") end,
          tip = "Go back to the stop before this one." },
        { key = "next", label = "Next", width = 58,
          onClick = function() Detail.RouteAction(id, O.RouteNext, "On to the next stop.", "step") end,
          tip = "Skip to the next stop." },
        { key = "reverse", label = "Reverse", width = 70,
          onClick = function() Detail.RouteAction(id, O.RouteReverse, "The stops now run the other way.", "reverse") end,
          tip = "Walk the stops in the opposite order; the current stop stays current." },
        { key = "optimise", label = "Optimise order", width = 112,
          onClick = function() Detail.RouteAction(id, O.RouteOptimize, "Re-ordered: nearest first from here.", "optimise") end,
          tip = "Re-order the stops still ahead, nearest first from where you stand, one landmass at a time." },
        { key = "export", label = "Export", width = 66, onClick = function() Paste.ExportInto(id) end,
          tip = "The route as /way lines on the Paste tab, to copy or keep as a page." },
        { key = "removeRoute", label = "Remove route", width = 104, danger = true, onClick = function()
            if O.RemoveRoute(id) then
                state.sel.WAYPOINTS = nil
                Status("Route removed.", "secondary")
            end
        end, tip = "Remove the route and all of its stops." },
    }
    return view
end

local function FindPlace(sel)
    if not sel then return nil end
    for _, p in ipairs(PlaceList()) do
        if p.index == sel.index then return p end
    end
    return nil
end

function Detail.PlaceView(sel)
    local p = FindPlace(sel)
    if not p then return nil end
    local index = p.index
    local view = { editable = true, title = p.title or "", ghost = "A name for this place", kind = "Place" }
    local info = { { "Where", WhereText(p) or "" }, { "Distance", "", "secondary" } }
    view.liveIndex = 2
    view.live = function(ctx)
        local text = PlaceDistance(p, ctx)
        if text == "" then text = (ctx and ctx.player) and "Cannot measure from here" or "No position here" end
        return text
    end
    if p.faction then
        local mine = Faction()
        info[#info + 1] = { "Faction", p.faction .. ((mine and mine ~= p.faction) and ", not yours" or ""),
                            (mine and mine ~= p.faction) and "warn" or nil }
    end
    local when = WhenText(p.created)
    if when then info[#info + 1] = { "Marked", when } end
    info[#info + 1] = { "Kept", "For every character on this account", "faint" }
    view.info = info
    -- the place as it is when the button is pressed (a rename may have
    -- landed since this view was built), never the copy taken for it
    local function Now() return FindPlace({ index = index }) end
    view.actions = {
        { key = "go", label = "Go there", width = 80, onClick = function() Places.Go(index) end,
          tip = "A waypoint at this place, and the arrow on it." },
        { key = "rename", label = "Rename", width = 70, onClick = function() Detail.Rename() end,
          tip = "Type a new name in the box above, then press Enter." },
        { key = "copy", label = "Copy /way", width = 80, onClick = function() Copy(WayLineOf(Now())) end,
          tip = "A /way line to copy and paste anywhere." },
        { key = "remove", label = "Remove", width = 70, danger = true, onClick = function()
            local now = Now()
            if now then Places.ConfirmRemove(now) end
        end, tip = "Forget this place (you are asked first)." },
    }
    return view
end

-- Lay the buttons out left to right, wrapping at the pane's width. The one
-- that destroys something (Remove, Remove route) stands apart, bottom right,
-- where a quick click along the row cannot land on it.
local function LayoutActions(actions)
    local width = (W.detailPane:GetWidth() or 0)
    if width <= 0 then width = FRAME_W - 2 * PAD - LIST_W - 6 end
    width = width - 24
    W.actionByKey = {}
    local x, y = 0, 0
    local danger
    for i, spec in ipairs(actions) do
        local b = W.actions[i]
        if not b then
            b = PanelButton(W.detailPane, "", 80, function(self) if self.onClick then self.onClick(self) end end)
            Tooltip(b, nil, nil)
            W.actions[i] = b
        end
        local w = spec.width or 80
        b:SetWidth(w)
        b:SetText(spec.label)
        b.onClick, b.key = spec.onClick, spec.key
        b.tooltipTitle, b.tooltipText = spec.tip and spec.label or nil, spec.tip
        if spec.disabled then b:Disable() else b:Enable() end
        b:ClearAllPoints()
        if spec.danger then
            b:SetPoint("BOTTOMRIGHT", W.detailPane, "BOTTOMRIGHT", -12, 10)
            danger = b
        else
            if x > 0 and x + w > width then
                x, y = 0, y + BUTTON_H + 4
            end
            b:SetPoint("TOPLEFT", W.actionAnchor, "BOTTOMLEFT", x, -y)
            x = x + w + 4
        end
        b:Show()
        W.actionByKey[spec.key] = b
    end
    for i = #actions + 1, #W.actions do W.actions[i]:Hide() end
    W.status:ClearAllPoints()
    W.status:SetPoint("BOTTOMLEFT", W.detailPane, "BOTTOMLEFT", 12, 12)
    if danger then
        W.status:SetPoint("RIGHT", danger, "LEFT", -8, 0)
    else
        W.status:SetPoint("RIGHT", W.detailPane, "RIGHT", -12, 0)
    end
end

local function InfoLine(i)
    local line = W.info[i]
    if line then return line end
    local pane = W.detailPane
    line = {
        label = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
        value = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
    }
    line.label:SetWidth(INFO_LABEL_W)
    line.label:SetJustifyH("RIGHT")
    NoWrap(line.label)
    line.value:SetJustifyH("LEFT")
    W.info[i] = line
    return line
end

function Detail.ShowEmpty()
    W.detailView = nil
    W.titleBox:Hide()
    W.titleText:Hide()
    W.kindText:Hide()
    W.detailRule:Hide()
    for _, line in ipairs(W.info) do line.label:Hide() line.value:Hide() end
    for _, b in ipairs(W.actions) do b:Hide() end
    W.actionByKey = {}
    W.status:ClearAllPoints()
    W.status:SetPoint("BOTTOMLEFT", W.detailPane, "BOTTOMLEFT", 12, 12)
    W.status:SetPoint("RIGHT", W.detailPane, "RIGHT", -12, 0)
    if state.tab == "PLACES" then
        W.detailEmpty:SetText("Pick a place on the left.\n\nPlaces are spots you keep for good; Go there sets a waypoint on one whenever you need it.")
    else
        W.detailEmpty:SetText("Pick a waypoint or a route on the left.\n\nRight-click a row for its menu; double-click a waypoint to point the arrow at it.")
    end
    Ink(W.detailEmpty, "faint")
    W.detailEmpty:Show()
end

function Detail.Paint()
    if not W.detailPane then return end
    local sel = state.sel[state.tab]
    local view
    if sel then
        if sel.kind == "wp" then view = Detail.WaypointView(sel)
        elseif sel.kind == "route" then view = Detail.RouteView(sel)
        elseif sel.kind == "place" then view = Detail.PlaceView(sel) end
        if not view then state.sel[state.tab] = nil end
    end
    if W.status then
        W.status:SetText(state.status or "")
        Ink(W.status, state.statusShade or "secondary")
    end
    if not view then
        Detail.ShowEmpty()
        return
    end
    W.detailEmpty:Hide()
    W.detailView = view
    local box = W.titleBox
    if view.editable then
        W.titleText:Hide()
        box:Show()
        -- never under the cursor of someone typing in it
        if not (box.HasFocus and box:HasFocus()) or box.selKey ~= tostring(sel.kind) .. tostring(sel.uid or sel.id or sel.index) then
            box:SetText(view.title or "")
            box.original = view.title or ""
            if box.SetCursorPosition then box:SetCursorPosition(0) end
        end
        box.selKey = tostring(sel.kind) .. tostring(sel.uid or sel.id or sel.index)
        box.ghost:SetText(view.ghost or "")
        SyncGhost(box)
    else
        box:Hide()
        box.selKey = nil
        W.titleText:Show()
        W.titleText:SetText(view.title or "")
        Ink(W.titleText, "title")
    end
    W.kindText:Show()
    W.detailRule:Show()
    W.kindText:SetText(view.kind or "")
    Ink(W.kindText, "faint")

    local y = -58
    local valueW = (W.detailPane:GetWidth() or 0) - INFO_LABEL_W - 36
    if valueW <= 0 then valueW = FRAME_W - 2 * PAD - LIST_W - 6 - INFO_LABEL_W - 36 end
    local ctx = view.live and Ctx() or nil
    for i, spec in ipairs(view.info) do
        local line = InfoLine(i)
        local value = spec[2]
        if i == view.liveIndex and view.live then value = view.live(ctx) end
        line.label:ClearAllPoints()
        line.label:SetPoint("TOPLEFT", W.detailPane, "TOPLEFT", 12, y)
        line.label:SetText(spec[1])
        Ink(line.label, "faint")
        line.value:ClearAllPoints()
        line.value:SetPoint("TOPLEFT", line.label, "TOPRIGHT", 10, 0)
        line.value:SetWidth(valueW)
        line.value.ordersText = nil
        SetIf(line.value, value or "")
        Ink(line.value, spec[3] or "primary")
        line.label:Show()
        line.value:Show()
        local h = line.value.GetStringHeight and line.value:GetStringHeight() or 12
        y = y - max(16, (h or 12) + 5)
    end
    for i = #view.info + 1, #W.info do
        W.info[i].label:Hide()
        W.info[i].value:Hide()
    end
    W.actionAnchor:ClearAllPoints()
    W.actionAnchor:SetPoint("TOPLEFT", W.detailPane, "TOPLEFT", 12, y - 6)
    LayoutActions(view.actions)
end

function Detail.Live(ctx)
    local view = W.detailView
    if not (view and view.live and view.liveIndex) then return end
    local line = W.info[view.liveIndex]
    if line then SetIf(line.value, view.live(ctx)) end
end

-- The title box: Enter (or leaving it) renames, Escape puts it back
function Detail.CommitTitle()
    local box = W.titleBox
    local sel = state.sel[state.tab]
    if not (box and sel and box:IsShown()) then return end
    local text = Trim(box:GetText())
    if text == (box.original or "") then return end
    box.original = text
    if sel.kind == "wp" then
        local copy = O.Update(sel.uid, { title = text ~= "" and text or false })
        if copy then Status(text ~= "" and "Renamed." or "Title cleared.", "good") end
    elseif sel.kind == "place" then
        if text == "" then
            local p = FindPlace(sel)
            box:SetText(p and p.title or "")
            box.original = p and p.title or ""
            return
        end
        if O.RenamePlace(sel.index, text) then Status("Renamed.", "good") end
    end
    UIM.Refresh()
end

function Detail.RowMenu(e, anchor)
    if e.kind == "wp" then
        local fn = R().WaypointMenu
        local entries = fn and fn(e.uid) or {}
        if #entries > 0 then ShowMenu(entries, anchor) end
    elseif e.kind == "route" then
        local id = e.id
        ShowMenu({
            { text = Cut((e.route.title and e.route.title ~= "") and e.route.title or "Route", 40), isTitle = true },
            { text = "Start", func = function() Detail.RouteAction(id, O.RouteStart, "The arrow follows the route.", "start") end },
            { text = "Next stop", func = function() Detail.RouteAction(id, O.RouteNext, "On to the next stop.", "step") end },
            { text = "Previous stop", func = function() Detail.RouteAction(id, O.RoutePrev, "Back one stop.", "step") end },
            { text = "Export as /way lines", func = function() Paste.ExportInto(id) end },
            { text = "Remove route", func = function()
                if O.RemoveRoute(id) then state.sel.WAYPOINTS = nil end
            end },
        }, anchor)
    elseif e.kind == "place" then
        local p = e.place
        ShowMenu({
            { text = Cut(p.title or "Place", 40), isTitle = true },
            { text = "Go there", func = function() Places.Go(p.index) end },
            { text = "Copy /way line", func = function() Copy(WayLineOf(p)) end },
            { text = "Remove", func = function() Places.ConfirmRemove(p) end },
        }, anchor)
    end
end

-- ---------------------------------------------------------------------------
-- Toolbar actions
-- ---------------------------------------------------------------------------
function UIM.AddHere()
    local uid, err = O.Here()
    if uid then
        state.sel.WAYPOINTS = { kind = "wp", uid = uid }
        Status("A waypoint where you stand; rename it above.", "good")
        UIM.Refresh()
        List.RevealSoon()
    else
        Status(Reason(err), "warn")
        UIM.Refresh()
    end
end

-- "Clear...": reached ones, everything one addon added, or everything
function UIM.ClearMenu(anchor)
    local st = Store()
    if not st then return end
    local reached = st:Count({ reached = true })
    local counts, order = {}, {}
    local user = D.USER_SOURCES or EMPTY
    for _, wp in ipairs(st:List()) do
        local s = wp.source
        if wp.kind ~= "corpse" and type(s) == "string" and not user[s] then
            if not counts[s] then order[#order + 1] = s end
            counts[s] = (counts[s] or 0) + 1
        end
    end
    tsort(order, function(a, b) return Lower(SourceLabel(a)) < Lower(SourceLabel(b)) end)
    local entries = { { text = "Remove", isTitle = true } }
    entries[#entries + 1] = { text = format("Reached ones (%d)", reached), disabled = reached == 0, func = function()
        local n = O.Clear({ reached = true }) or 0
        Status(Plural(n, "reached waypoint", "reached waypoints") .. " removed.", "secondary")
    end }
    for _, s in ipairs(order) do
        local source = s
        local sender = s:match("^share:(.+)$")
        local text = sender and format("Shared by %s (%d)", sender, counts[s])
            or format("Set by %s (%d)", SourceLabel(s), counts[s])
        entries[#entries + 1] = { text = text, func = function()
            local n = O.RemoveBy(source) or 0
            Status(Plural(n, "waypoint", "waypoints") .. " removed.", "secondary")
        end }
    end
    entries[#entries + 1] = { text = "Everything...", disabled = st:Count() == 0 and #st:Routes() == 0,
        func = function() O.Command("clearall") end }
    ShowMenu(entries, anchor)
end

-- ---------------------------------------------------------------------------
-- Places
-- ---------------------------------------------------------------------------
function Places.Mark()
    local index, err = O.MarkPlace("")
    if index then
        state.sel.PLACES = { kind = "place", index = index }
        Status("Place marked; name it above.", "good")
    else
        Status("Could not mark a place here: " .. Reason(err), "warn")
    end
    UIM.Refresh()
    List.RevealSoon()
end

function Places.Go(index)
    local uid, err = O.GoPlace(index)
    if uid then
        Status("The arrow points at it now.", "good")
    else
        Status(Reason(err), "warn")
    end
end

function Places.Remove(data)
    if type(data) ~= "table" then return end
    -- the list may have moved under the dialog: the index must still be the
    -- place the dialog named
    local index
    for _, p in ipairs(PlaceList()) do
        if p.index == data.index and p.title == data.title then index = p.index break end
    end
    if not index then
        for _, p in ipairs(PlaceList()) do
            if p.title == data.title then index = p.index break end
        end
    end
    if index and O.RemovePlace(index) then
        state.sel.PLACES = nil
        Status("Place removed.", "secondary")
        UIM.Refresh()
    end
end

function Places.ConfirmRemove(p)
    local data = { index = p.index, title = p.title }
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.COMMANDER_ORDERS_REMOVE_PLACE then
        StaticPopup_Show("COMMANDER_ORDERS_REMOVE_PLACE", p.title or "this place", nil, data)
    else
        Places.Remove(data)
    end
end

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs.COMMANDER_ORDERS_REMOVE_PLACE = {
        text = "Forget the place \"%s\"? Every character on this account loses it.",
        button1 = "Forget", button2 = CANCEL or "Cancel",
        OnAccept = function(_, data) Places.Remove(data) end,
        -- over the maximized world map too (CommanderOrders.lua, RaisePopup)
        OnShow = function(self)
            local raise = R().RaisePopup
            if raise then raise(self) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

-- ---------------------------------------------------------------------------
-- Paste
-- ---------------------------------------------------------------------------
local function Result(text, shade)
    state.result, state.resultShade = text, shade
    if W.result then
        W.result:SetText(text or "")
        Ink(W.result, shade or "secondary")
    end
end

function Paste.Text()
    return W.pasteBox and (W.pasteBox:GetText() or "") or ""
end

function Paste.SetText(text)
    if not W.pasteBox then return end
    W.pasteBox:SetText(text or "")
    if W.pasteBox.SetCursorPosition then W.pasteBox:SetCursorPosition(0) end
    SyncGhost(W.pasteBox)
end

-- One unreadable line in words: its number (the box's own line), the start
-- of what it said, why, and an exact /way line when the zone was ambiguous
function Paste.ErrorLines(e)
    if not (e.line and e.line > 0) then return { Reason(e.message) } end
    local said = Trim(e.text)
    local head = said ~= "" and format("Line %d (%s)", e.line, Cut(said, ERROR_TEXT)) or format("Line %d", e.line)
    local out = { head .. ": " .. tostring(e.message or "not a /way line") }
    local c = e.candidates and e.candidates[1]
    if c and c.line then out[2] = "    for example " .. c.line end
    return out
end

-- Whether the result box holds these lines (wrapped at its width) plus the
-- block and the tail; an estimate from letter counts, on the safe side
function Paste.Fits(lines, block, tail)
    local box = W.result
    local w = box and box.GetWidth and box:GetWidth()
    local h = box and box.GetHeight and box:GetHeight()
    if type(w) ~= "number" or w <= 0 then w = RESULT_W end
    if type(h) ~= "number" or h <= 0 then h = RESULT_H end
    local perLine = max(1, floor(w / RESULT_CHAR_W))
    local used = 0
    local function Count(line) used = used + max(1, math.ceil(#line / perLine)) end
    for _, line in ipairs(lines) do Count(line) end
    for _, line in ipairs(block) do Count(line) end
    if tail then Count(tail) end
    return used * RESULT_LINE_H <= h
end

function Paste.Import()
    local text = Paste.Text()
    if Trim(text) == "" then
        Result("Nothing to add yet: paste some /way lines into the box first.", "faint")
        return
    end
    local opts = {}
    if state.pasteMode ~= "WAYPOINTS" then
        opts.route = true
        opts.mode = state.pasteMode
        local name = Trim(W.routeTitle:GetText())
        if name ~= "" then opts.title = name end
    end
    local added, errors, routeId = O.Import(text, opts)
    if type(added) ~= "number" then
        Result("Could not read that (" .. tostring(errors) .. ").", "warn")
        return
    end
    errors = type(errors) == "table" and errors or {}
    local lines = {}
    if added == 0 then
        lines[1] = "Nothing was added."
    elseif routeId then
        local st = Store()
        local route = st and st:GetRoute(routeId)
        lines[1] = format("Added a route of %s%s; the arrow follows its first stop.", Plural(added, "stop", "stops"),
            route and route.title and (": " .. route.title) or "")
        state.sel.WAYPOINTS = { kind = "route", id = routeId }
    else
        lines[1] = format("Added %s; the arrow follows the first.", Plural(added, "waypoint", "waypoints"))
    end
    local bad = 0
    for _, e in ipairs(errors) do if e.line and e.line > 0 then bad = bad + 1 end end
    if bad > 0 then
        lines[#lines + 1] = format("%s could not be read:", Plural(bad, "line", "lines"))
    end
    -- As many errors as the box holds, the "and N more" line always kept:
    -- four ambiguous zones wrote fifteen lines into a nine-line box and the
    -- client cut the tail, the count of the rest with it (review: render)
    local shown = 0
    for _, e in ipairs(errors) do
        if shown >= ERRORS_SHOWN then break end
        local block = Paste.ErrorLines(e)
        local rest = #errors - shown - 1
        local tail = rest > 0 and format("and %d more.", rest) or nil
        local fits = Paste.Fits(lines, block, tail)
        if not fits and #block > 1 then
            block = { block[1] }                    -- without its example line
            fits = Paste.Fits(lines, block, tail)
        end
        if not fits then break end
        for _, line in ipairs(block) do lines[#lines + 1] = line end
        shown = shown + 1
    end
    if #errors > shown then lines[#lines + 1] = format("and %d more.", #errors - shown) end
    Result(tconcat(lines, "\n"), (added > 0 and #errors == 0) and "good" or (added > 0 and "secondary" or "warn"))
    if W.pasteBox.ClearFocus then W.pasteBox:ClearFocus() end
end

-- Fill the box with /way lines: nil = every standalone waypoint, a route id
-- = that route's stops. Focus follows (a click asked for it) so Ctrl+C works.
function Paste.Export(filter)
    local lines = O.Export(filter) or {}
    Paste.SetText(tconcat(lines, "\n"))
    if #lines == 0 then
        Result("Nothing to export.", "faint")
        return lines
    end
    Result(format("%s exported. Press Ctrl+C to copy them, or save them as a page.", Plural(#lines, "line", "lines")), "good")
    if W.pasteBox.SetFocus and W.frame:IsShown() and state.tab == "PASTE" then
        W.pasteBox:SetFocus()
        if W.pasteBox.HighlightText then W.pasteBox:HighlightText() end
    end
    return lines
end

function Paste.ExportInto(routeId)
    Tabs.Set("PASTE")
    Paste.Export(routeId)
    local st = Store()
    local route = st and routeId and st:GetRoute(routeId)
    if route and W.pageName then
        W.pageName:SetText(route.title or "")
        SyncGhost(W.pageName)
    end
end

function Paste.ExportMenu(anchor)
    local st = Store()
    if not st then return end
    local standalone = #(O.Export() or {})
    local entries = { { text = "Export as /way lines", isTitle = true } }
    entries[#entries + 1] = { text = format("Every waypoint (%d)", standalone), disabled = standalone == 0,
        func = function() Paste.Export(nil) end }
    for _, route in ipairs(st:Routes()) do
        local id = route.id
        entries[#entries + 1] = { text = format("Route: %s (%d)", Cut(route.title or "Route", 32), #route.stops),
            func = function() Paste.Export(id) end }
    end
    ShowMenu(entries, anchor)
end

function Paste.SetMode(mode)
    state.pasteMode = mode
    Paste.Paint()
end

function Paste.PageRow(i)
    local row = W.pageRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, W.pagesChild)
    row:SetHeight(20)
    row:EnableMouse(true)
    row.highlight = Quad(row, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:Hide()
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.label:SetJustifyH("LEFT")
    NoWrap(row.label)
    row:SetScript("OnEnter", function(self)
        if self.current then return end
        local r, g, b = Accent()
        self.highlight:SetColorTexture(r, g, b, SKIN.hover)
        self.highlight:Show()
    end)
    row:SetScript("OnLeave", function(self) if not self.current then self.highlight:Hide() end end)
    row:SetScript("OnClick", function(self) Paste.LoadPage(self.page) end)
    W.pageRows[i] = row
    return row
end

function Paste.LoadPage(page)
    if type(page) ~= "table" then return end
    Paste.SetText(page.text or "")
    W.pageName:SetText(page.name or "")
    SyncGhost(W.pageName)
    state.page = page.name
    Result(format("Page \"%s\" loaded.", page.name or "?"), "secondary")
    Paste.Paint()
end

function Paste.SavePage()
    local name = Trim(W.pageName:GetText())
    if name == "" then
        Result("Name the page first (the box under the list).", "warn")
        return
    end
    local text = Paste.Text()
    if Trim(text) == "" then
        Result("The box is empty: there is nothing to save.", "warn")
        return
    end
    if O.SavePastePage(name, text) then
        state.page = name
        Result(format("Page \"%s\" saved, for every character on this account.", name), "good")
    end
    if W.pageName.ClearFocus then W.pageName:ClearFocus() end
    Paste.Paint()
end

function Paste.DeletePage()
    local name = Trim(W.pageName:GetText())
    if name == "" then name = state.page or "" end
    if name == "" then
        Result("Pick a page to delete first.", "warn")
        return
    end
    if O.DeletePastePage(name) then
        if state.page and Lower(state.page) == Lower(name) then state.page = nil end
        W.pageName:SetText("")
        SyncGhost(W.pageName)
        Result(format("Page \"%s\" deleted.", name), "secondary")
    else
        Result(format("There is no page called \"%s\".", name), "warn")
    end
    Paste.Paint()
end

function Paste.Paint()
    if not W.pastePane then return end
    for _, b in ipairs(W.modeButtons) do PaintTextButton(b, b.id == state.pasteMode) end
    local route = state.pasteMode ~= "WAYPOINTS"
    W.routeTitle:SetShown(route)
    W.routeLabel:SetShown(route)
    local pages = O.PastePages and O.PastePages() or {}
    local y = 0
    for i, page in ipairs(pages) do
        local row = Paste.PageRow(i)
        row.page = page
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", W.pagesChild, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", W.pagesChild, "TOPRIGHT", 0, -y)
        row.label:SetText(page.name or "?")
        row.current = state.page ~= nil and Lower(state.page) == Lower(page.name)
        if row.current then
            local r, g, b = Accent()
            row.highlight:SetColorTexture(r, g, b, SKIN.selection)
            row.highlight:Show()
            Ink(row.label, "primary")
        else
            row.highlight:Hide()
            Ink(row.label, "secondary")
        end
        row:Show()
        y = y + 20
    end
    for i = #pages + 1, #W.pageRows do W.pageRows[i]:Hide() end
    W.pagesChild:SetHeight(max(y, 1))
    W.pagesEmpty:SetShown(#pages == 0)
    SyncGhost(W.routeTitle)
    SyncGhost(W.pageName)
    if W.result then
        W.result:SetText(state.result or "")
        Ink(W.result, state.resultShade or "secondary")
    end
    SyncGhost(W.pasteBox)
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
function Tabs.Paint()
    for _, b in ipairs(W.tabs) do PaintTextButton(b, b.id == state.tab) end
    local paste = state.tab == "PASTE"
    W.listPane:SetShown(not paste)
    W.detailPane:SetShown(not paste)
    W.pastePane:SetShown(paste)
    W.search:SetShown(not paste)
    W.addHere:SetShown(state.tab == "WAYPOINTS")
    W.clear:SetShown(state.tab == "WAYPOINTS")
    W.markPlace:SetShown(state.tab == "PLACES")
    local grouped = state.tab == "WAYPOINTS"
    W.groupStrip:SetShown(grouped)
    W.listScroll:ClearAllPoints()
    W.listScroll:SetPoint("TOPLEFT", W.listPane, "TOPLEFT", 4, grouped and -(GROUP_H + 4) or -6)
    W.listScroll:SetPoint("BOTTOMRIGHT", W.listPane, "BOTTOMRIGHT", -16, 5)
    local by = GroupBy()
    for _, b in ipairs(W.groupButtons) do PaintTextButton(b, b.id == by) end
    W.search.ghost:SetText(state.tab == "PLACES" and "Search places" or "Search waypoints")
    SyncGhost(W.search)
    local r, g, b = Accent()
    W.toolbarRule:SetColorTexture(r, g, b, 0.45)
end

-- A rename in progress is kept, never dropped, when the view moves on
local function SettleTitle()
    local box = W.titleBox
    if box and box.HasFocus and box:HasFocus() then
        Detail.CommitTitle()
        box:ClearFocus()
    end
end

-- The tab, without a repaint: each tab keeps its own selection, the search
-- starts empty
local function SwitchTab(tab)
    if tab ~= "WAYPOINTS" and tab ~= "PLACES" and tab ~= "PASTE" then return end
    if state.tab == tab then return end
    SettleTitle()
    -- the pane going out of sight gives the keyboard back
    for _, box in ipairs(W.boxes) do
        if box ~= W.search and box.HasFocus and box:HasFocus() then box:ClearFocus() end
    end
    state.tab = tab
    state.search = ""
    if W.search then
        W.search:SetText("")
        if W.search.ClearFocus then W.search:ClearFocus() end
        SyncGhost(W.search)
    end
    Status(nil)
end

function Tabs.Set(tab)
    SwitchTab(tab)
    UIM.Refresh()
end

-- ---------------------------------------------------------------------------
-- Building the window (first open only)
-- ---------------------------------------------------------------------------
function Build.Window()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
    W.frame = f
    f:SetSize(FRAME_W, FRAME_H)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, FRAME_NAME) end
    local UI = Commander and Commander.UI
    -- The template's steel steps aside for the stone sheet, all of it
    -- (UI.TEMPLATE_REGIONS is the verified list; CloseButton stays)
    if UI and UI.SetTemplateDressing then UI.SetTemplateDressing(f, false) end

    local art = CreateFrame("Frame", nil, f, "BackdropTemplate")
    art:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    art:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    art:SetFrameLevel(max((f:GetFrameLevel() or 1) - 1, 0))
    if art.SetBackdrop then
        art:SetBackdrop(SHEET_BACKDROP)
        art:SetBackdropColor(1, 1, 1, 1)
        art:SetBackdropBorderColor(1, 1, 1, 1)
    end
    -- The floor is drawn, not borrowed: a backdrop whose bgFile fails still
    -- draws its edge and no fill (QuestLog's EnsureSheet)
    local base = art:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetColorTexture(SHEET_BASE[1], SHEET_BASE[2], SHEET_BASE[3], 1)
    base:SetPoint("TOPLEFT", art, "TOPLEFT", 10, -10)
    base:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -10, 10)
    local plate = art:CreateTexture(nil, "ARTWORK")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(256, 64)
    plate:SetPoint("TOP", f, "TOP", 0, 12)
    local title = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", plate, "TOP", 0, -14)
    title:SetText("Orders")
    W.art, W.plate, W.plateTitle = art, plate, title

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, 0)
    drag:SetHeight(26)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        f._dragging = true
        f:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        f._dragging = false
        SavePosition()
    end)
    W.drag = drag

    if UI and UI.AttachScaleGrip then
        -- on the sheet's own corner, clear of the detail pane's buttons
        W.grip = UI.AttachScaleGrip(f, {
            inset = 4,
            set = function(value)
                local db = CommanderOrdersDB
                if type(db) == "table" then db.ManagerScale = value end
            end,
            onStop = function() SavePosition() end,
        })
    end

    f:SetScript("OnShow", function()
        state.liveAcc = 0
        UIM.Refresh()
    end)
    f:SetScript("OnHide", function()
        if GameTooltip then GameTooltip:Hide() end
        if CloseDropDownMenus then CloseDropDownMenus() end
        for _, box in ipairs(W.boxes) do
            if box.ClearFocus then box:ClearFocus() end
        end
    end)
    f:SetScript("OnUpdate", function(_, elapsed) Live.OnUpdate(elapsed) end)
end

function Build.Toolbar()
    local f = W.frame
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, TOOLBAR_Y)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, TOOLBAR_Y)
    bar:SetHeight(TOOLBAR_H)
    W.toolbar = bar

    local previous
    for _, spec in ipairs(TABS) do
        local tab = TextButton(bar, spec.label, spec.width, TOOLBAR_H, function(self) Tabs.Set(self.id) end)
        tab.label:SetFontObject(GameFontNormal)
        tab.id = spec.id
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 2, 0) else tab:SetPoint("LEFT", bar, "LEFT", 0, 0) end
        previous = tab
        W.tabs[#W.tabs + 1] = tab
    end

    W.addHere = PanelButton(bar, "Add here", 80, function() UIM.AddHere() end,
        "Add here", "A waypoint where you stand (/wayb), to come back to.")
    W.addHere:SetPoint("LEFT", previous, "RIGHT", 14, 0)
    W.clear = PanelButton(bar, "Clear...", 70, function(self) UIM.ClearMenu(self) end,
        "Clear", "Remove the waypoints you have reached, everything one addon set, or everything.")
    W.clear:SetPoint("LEFT", W.addHere, "RIGHT", 4, 0)
    W.markPlace = PanelButton(bar, "Mark place here", 118, function() Places.Mark() end,
        "Mark place here", "Keep where you stand as a place, for every character on this account. Name it in the box on the right.")
    W.markPlace:SetPoint("LEFT", previous, "RIGHT", 14, 0)

    local search = InputBox("CommanderOrdersManagerSearch", bar, 150, 60)
    search:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    Ghost(search, "Search waypoints", 2)
    search:SetScript("OnTextChanged", function(self, userInput)
        SyncGhost(self)
        if userInput == false then return end
        local text = self:GetText() or ""
        if text == state.search then return end
        state.search = text
        List.Rebuild()
    end)
    search:SetScript("OnEditFocusGained", function(self) SyncGhost(self) end)
    search:SetScript("OnEditFocusLost", function(self) SyncGhost(self) end)
    search:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        state.search = ""
        self:ClearFocus()
        List.Rebuild()
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    Tooltip(search, "Search", "Matches a waypoint's title, its zone, who set it and its note; on Places, a place's name and zone.")
    W.search = search

    local rule = Quad(f, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
    rule:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -3)
    W.toolbarRule = rule
end

function Build.ListPane()
    local f = W.frame
    local pane = MakePane(f)
    pane:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, BODY_TOP)
    pane:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, BODY_BOTTOM)
    pane:SetWidth(LIST_W)
    W.listPane = pane

    local strip = CreateFrame("Frame", nil, pane)
    strip:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -3)
    strip:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -4, -3)
    strip:SetHeight(GROUP_H - 2)
    W.groupStrip = strip
    local label = strip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    label:SetPoint("LEFT", strip, "LEFT", 6, 0)
    label:SetText("Group by")
    Ink(label, "faint")
    W.groupLabel = label
    local previous = label
    for _, spec in ipairs({ { id = "ZONE", label = "Zone", width = 46 }, { id = "SOURCE", label = "Who set it", width = 70 } }) do
        local b = TextButton(strip, spec.label, spec.width, GROUP_H - 4, function(self)
            local db = CommanderOrdersDB
            if type(db) == "table" then db.ManagerGroupBy = self.id end
            UIM.Refresh()
        end)
        b.id = spec.id
        b:SetPoint("LEFT", previous, "RIGHT", previous == label and 8 or 2, 0)
        previous = b
        W.groupButtons[#W.groupButtons + 1] = b
    end
    local rule = Rule(strip)
    rule:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 2, -1)
    rule:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -2, -1)

    local scroll = CreateFrame("ScrollFrame", "CommanderOrdersManagerListScroll", pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -(GROUP_H + 4))
    scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -16, 5)
    WheelScroll(scroll, ROW_H)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(LIST_W - 22, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(_, width) if width and width > 0 then child:SetWidth(width) end end)
    W.listScroll, W.listChild = scroll, child

    local empty = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    empty:SetPoint("CENTER", pane, "CENTER", 0, 10)
    empty:SetWidth(LIST_W - 40)
    empty:SetJustifyH("CENTER")
    empty:Hide()
    W.listEmpty = empty
end

function Build.DetailPane()
    local f = W.frame
    local pane = MakePane(f)
    pane:SetPoint("TOPLEFT", W.listPane, "TOPRIGHT", 6, 0)
    pane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, BODY_BOTTOM)
    W.detailPane = pane

    local box = InputBox("CommanderOrdersManagerTitleBox", pane, 200, TITLE_LETTERS)
    box:SetPoint("TOPLEFT", pane, "TOPLEFT", 18, -10)
    box:SetPoint("RIGHT", pane, "RIGHT", -12, 0)
    box:SetHeight(24)
    if box.SetFontObject then box:SetFontObject(GameFontHighlight) end
    Ghost(box, "", 2)
    box:SetScript("OnEnterPressed", function(self)
        Detail.CommitTitle()
        self:ClearFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(self.original or "")
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusGained", function(self) SyncGhost(self) end)
    box:SetScript("OnEditFocusLost", function(self)
        Detail.CommitTitle()
        SyncGhost(self)
    end)
    box:SetScript("OnTextChanged", function(self) SyncGhost(self) end)
    box:Hide()
    W.titleBox = box

    local title = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 14, -14)
    title:SetPoint("RIGHT", pane, "RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    NoWrap(title)
    title:Hide()
    W.titleText = title

    local kind = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    kind:SetPoint("TOPLEFT", pane, "TOPLEFT", 14, -38)
    kind:SetPoint("RIGHT", pane, "RIGHT", -12, 0)
    kind:SetJustifyH("LEFT")
    NoWrap(kind)
    W.kindText = kind

    local rule = Rule(pane)
    rule:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -52)
    rule:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -8, -52)
    W.detailRule = rule

    local anchor = CreateFrame("Frame", nil, pane)
    anchor:SetSize(1, 1)
    W.actionAnchor = anchor

    local status = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 12, 10)
    status:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -12, 10)
    status:SetJustifyH("LEFT")
    W.status = status

    local empty = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("CENTER", pane, "CENTER", 0, 16)
    empty:SetWidth(280)
    empty:SetJustifyH("CENTER")
    W.detailEmpty = empty
end

function Build.PastePane()
    local f = W.frame
    local pane = CreateFrame("Frame", nil, f)
    pane:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, BODY_TOP)
    pane:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, BODY_BOTTOM)
    pane:Hide()
    W.pastePane = pane

    local hint = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", pane, "TOPLEFT", 2, -2)
    hint:SetPoint("RIGHT", pane, "RIGHT", -(PAGES_W + 10), 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Paste /way lines, one to a line, with or without the /way in front. Zone names, #map ids and 45,66 all work. Ctrl+Enter adds them.")
    Ink(hint, "secondary")
    W.pasteHint = hint

    local boxPane = MakePane(pane)
    boxPane:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -32)
    boxPane:SetPoint("RIGHT", pane, "RIGHT", -(PAGES_W + 8), 0)
    boxPane:SetHeight(132)
    W.pasteBoxPane = boxPane

    local scroll = CreateFrame("ScrollFrame", "CommanderOrdersManagerPasteScroll", boxPane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", boxPane, "TOPLEFT", 8, -6)
    scroll:SetPoint("BOTTOMRIGHT", boxPane, "BOTTOMRIGHT", -18, 6)
    W.pasteScroll = scroll
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(MAX_LETTERS)
    box:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    box:SetWidth(FRAME_W - 2 * PAD - PAGES_W - 8 - 26)
    box:SetHeight(120)
    box:EnableMouse(true)
    if box.SetTextInsets then box:SetTextInsets(2, 2, 2, 2) end
    if box.SetTextColor then box:SetTextColor(INK.primary[1], INK.primary[2], INK.primary[3]) end
    scroll:SetScrollChild(box)
    scroll:SetScript("OnSizeChanged", function(_, width) if width and width > 0 then box:SetWidth(width) end end)
    -- a click anywhere in the pane is a click in the box
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() box:SetFocus() end)
    W.boxes[#W.boxes + 1] = box
    W.pasteBox = box
    local ghost = scroll:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ghost:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -4)
    ghost:SetText("/way Elwynn Forest 42.1 65.9 Goldshire\n/way #1944 87.4 50.3 Dark Portal\n45.2 66.8 Without /way, in your zone")
    ghost:SetJustifyH("LEFT")
    Ink(ghost, "faint")
    box.ghost = ghost
    box:SetScript("OnEnterPressed", function(self)
        if IsControlKeyDown and IsControlKeyDown() then
            Paste.Import()
        elseif self.Insert then
            self:Insert("\n")
        end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) SyncGhost(self) end)
    box:SetScript("OnEditFocusLost", function(self) SyncGhost(self) end)
    box:SetScript("OnTextChanged", function(self)
        SyncGhost(self)
        if ScrollingEdit_OnTextChanged then ScrollingEdit_OnTextChanged(self, scroll) end
    end)
    box:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if ScrollingEdit_OnCursorChanged then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
    end)
    box:SetScript("OnUpdate", function(self, elapsed)
        if ScrollingEdit_OnUpdate then ScrollingEdit_OnUpdate(self, elapsed, scroll) end
    end)

    -- Add as: waypoints, or a route
    local modeLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    modeLabel:SetPoint("TOPLEFT", boxPane, "BOTTOMLEFT", 2, -10)
    modeLabel:SetText("Add as")
    Ink(modeLabel, "faint")
    local previous = modeLabel
    for _, spec in ipairs(PASTE_MODES) do
        local b = TextButton(pane, spec.label, spec.width, 20, function(self) Paste.SetMode(self.id) end)
        b.id = spec.id
        b:SetPoint("LEFT", previous, "RIGHT", previous == modeLabel and 8 or 2, 0)
        previous = b
        W.modeButtons[#W.modeButtons + 1] = b
    end

    local routeLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    routeLabel:SetPoint("TOPLEFT", modeLabel, "BOTTOMLEFT", 0, -14)
    routeLabel:SetText("Route name")
    Ink(routeLabel, "faint")
    W.routeLabel = routeLabel
    local routeTitle = InputBox("CommanderOrdersManagerRouteTitle", pane, 200, TITLE_LETTERS)
    routeTitle:SetPoint("LEFT", routeLabel, "RIGHT", 12, 0)
    Ghost(routeTitle, "Pasted route", 2)
    routeTitle:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    routeTitle:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    routeTitle:SetScript("OnTextChanged", function(self) SyncGhost(self) end)
    routeTitle:SetScript("OnEditFocusGained", function(self) SyncGhost(self) end)
    routeTitle:SetScript("OnEditFocusLost", function(self) SyncGhost(self) end)
    W.routeTitle = routeTitle

    W.import = PanelButton(pane, "Add them", 90, function() Paste.Import() end,
        "Add them", "Add every line as a waypoint, or as one route. Lines that cannot be read are listed below, with the reason.")
    W.import:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", -2, -14)
    W.export = PanelButton(pane, "Export...", 84, function(self) Paste.ExportMenu(self) end,
        "Export", "Put your waypoints, or one route, in the box as /way lines (titles included when they have one).")
    W.export:SetPoint("LEFT", W.import, "RIGHT", 4, 0)
    W.clearText = PanelButton(pane, "Clear text", 84, function()
        Paste.SetText("")
        Result(nil)
        state.page = nil
        Paste.Paint()
    end, "Clear text", "Empty the box (saved pages are not touched).")
    W.clearText:SetPoint("LEFT", W.export, "RIGHT", 4, 0)

    local result = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    result:SetPoint("TOPLEFT", W.import, "BOTTOMLEFT", 2, -8)
    result:SetPoint("RIGHT", pane, "RIGHT", -(PAGES_W + 10), 0)
    result:SetPoint("BOTTOM", pane, "BOTTOM", 0, 2)
    result:SetJustifyH("LEFT")
    if result.SetJustifyV then result:SetJustifyV("TOP") end
    W.result = result

    -- Saved pages, down the right
    local pages = MakePane(pane)
    pages:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
    pages:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    pages:SetWidth(PAGES_W)
    W.pagesPane = pages
    local head = pages:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    head:SetPoint("TOPLEFT", pages, "TOPLEFT", 10, -9)
    head:SetText("Saved pages")
    Ink(head, "header")
    local pscroll = CreateFrame("ScrollFrame", "CommanderOrdersManagerPagesScroll", pages, "UIPanelScrollFrameTemplate")
    pscroll:SetPoint("TOPLEFT", pages, "TOPLEFT", 5, -26)
    pscroll:SetPoint("BOTTOMRIGHT", pages, "BOTTOMRIGHT", -18, 64)
    WheelScroll(pscroll, 20)
    local pchild = CreateFrame("Frame", nil, pscroll)
    pchild:SetSize(PAGES_W - 26, 1)
    pscroll:SetScrollChild(pchild)
    pscroll:SetScript("OnSizeChanged", function(_, width) if width and width > 0 then pchild:SetWidth(width) end end)
    W.pagesScroll, W.pagesChild = pscroll, pchild
    local pempty = pages:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pempty:SetPoint("TOPLEFT", pages, "TOPLEFT", 10, -30)
    pempty:SetPoint("RIGHT", pages, "RIGHT", -10, 0)
    pempty:SetJustifyH("LEFT")
    pempty:SetText("None yet. Name the text in the box below and save it, to paste it again on any character.")
    Ink(pempty, "faint")
    W.pagesEmpty = pempty

    local name = InputBox("CommanderOrdersManagerPageName", pages, PAGES_W - 30, 40)
    name:SetPoint("BOTTOMLEFT", pages, "BOTTOMLEFT", 16, 34)
    Ghost(name, "Page name", 2)
    name:SetScript("OnEnterPressed", function() Paste.SavePage() end)
    name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    name:SetScript("OnTextChanged", function(self) SyncGhost(self) end)
    name:SetScript("OnEditFocusGained", function(self) SyncGhost(self) end)
    name:SetScript("OnEditFocusLost", function(self) SyncGhost(self) end)
    W.pageName = name
    W.savePage = PanelButton(pages, "Save page", 86, function() Paste.SavePage() end,
        "Save page", "Keep the box's text under this name, for every character on this account. A page with the same name is replaced.")
    W.savePage:SetPoint("BOTTOMLEFT", pages, "BOTTOMLEFT", 8, 8)
    W.deletePage = PanelButton(pages, "Delete", 86, function() Paste.DeletePage() end,
        "Delete page", "Delete the saved page with this name.")
    W.deletePage:SetPoint("LEFT", W.savePage, "RIGHT", 4, 0)
end

local function EnsureFrame()
    if W.frame then return W.frame end
    Build.Window()
    Build.Toolbar()
    Build.ListPane()
    Build.DetailPane()
    Build.PastePane()
    local UI = Commander and Commander.UI
    if UI and UI.SlimScrollBar then
        for _, name in ipairs({ "CommanderOrdersManagerListScroll", "CommanderOrdersManagerPasteScroll",
                "CommanderOrdersManagerPagesScroll" }) do
            UI.SlimScrollBar(name, 2, 2)
        end
    end
    ApplyPosition()
    return W.frame
end

-- ---------------------------------------------------------------------------
-- Live distances (1 Hz while the window is open)
-- ---------------------------------------------------------------------------
function Live.Pass()
    if state.tab == "PASTE" then return end
    local ctx = Ctx()
    for _, row in ipairs(W.rows) do
        local e = row.entry
        if e and row:IsShown() then
            if e.kind == "wp" then
                SetIf(row.dist, (DistanceOf(e.wp, ctx)))
            elseif e.kind == "place" then
                SetIf(row.dist, (PlaceDistance(e.place, ctx)))
            end
            row.distText = row.dist.ordersText
        end
    end
    Detail.Live(ctx)
end

function Live.OnUpdate(elapsed)
    state.liveAcc = state.liveAcc + (elapsed or 0)
    if state.liveAcc < LIVE_INTERVAL then return end
    state.liveAcc = 0
    local ok, err = pcall(Live.Pass)
    if not ok then Report(err) end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------
local function Ready()
    if not (O.R and O.R.Store and O.R.Store()) then
        Say("still loading")
        return false
    end
    if not Enabled() then
        Say("Commander Orders is turned off (/corder to turn it on)")
        return false
    end
    return true
end

function UIM.Refresh()
    if not (W.frame and W.frame:IsShown()) then
        state.dirty = true
        return
    end
    state.dirty = false
    Tabs.Paint()
    if state.tab == "PASTE" then
        Paste.Paint()
    else
        List.Rebuild()
        Detail.Paint()
    end
end

function UIM.Select(kind, id)
    SettleTitle()
    if kind == "wp" then
        state.sel.WAYPOINTS = { kind = "wp", uid = id }
    elseif kind == "route" then
        state.sel.WAYPOINTS = { kind = "route", id = id }
    elseif kind == "place" then
        state.sel.PLACES = { kind = "place", index = id }
    else
        state.sel[state.tab] = nil
    end
    Status(nil)
    UIM.Refresh()
end

-- Open on the waypoint list, a waypoint (uid) or a route (id) selected
function UIM.Open(uid)
    if not Ready() then return false end
    EnsureFrame()
    local st = Store()
    if uid ~= nil then
        if type(uid) == "table" then uid = uid.uid end
        if st:Get(uid) then
            state.sel.WAYPOINTS = { kind = "wp", uid = uid }
            local wp = st:Get(uid)
            if wp.routeId then state.folded[wp.routeId] = nil end
            -- a search left in the box that this waypoint fails would show
            -- it in the detail with no row in the list (review: surfaces)
            if Trim(state.search) ~= "" and not Matches(wp, Lower(Trim(state.search))) then
                state.search = ""
                if W.search then
                    W.search:SetText("")
                    SyncGhost(W.search)
                end
            end
        elseif st:GetRoute(uid) then
            state.sel.WAYPOINTS = { kind = "route", id = uid }
        end
        Status(nil)
        SwitchTab("WAYPOINTS")
    end
    if W.frame:IsShown() then UIM.Refresh() else W.frame:Show() end
    if state.dirty then UIM.Refresh() end
    List.RevealSoon()
    return true
end

function UIM.OpenPaste(text)
    if not Ready() then return false end
    EnsureFrame()
    SwitchTab("PASTE")
    if type(text) == "string" then Paste.SetText(text) end
    if W.frame:IsShown() then UIM.Refresh() else W.frame:Show() end
    if state.dirty then UIM.Refresh() end
    return true
end

function UIM.OpenPlaces()
    if not Ready() then return false end
    EnsureFrame()
    SwitchTab("PLACES")
    if W.frame:IsShown() then UIM.Refresh() else W.frame:Show() end
    if state.dirty then UIM.Refresh() end
    return true
end

function UIM.Toggle()
    if W.frame and W.frame:IsShown() then
        W.frame:Hide()
        return true
    end
    return UIM.Open()
end

function UIM.Close()
    if W.frame then W.frame:Hide() end
end

function UIM.IsShown()
    return W.frame ~= nil and W.frame:IsShown() and true or false
end

-- For the harness: the widgets and the session state
function UIM._W() return W end
function UIM._State() return state end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function OnChanged()
    if W.frame and W.frame:IsShown() then
        UIM.Refresh()
    else
        state.dirty = true
    end
end

local function OnSettings()
    if not W.frame then return end
    if not Enabled() then
        W.frame:Hide()
        return
    end
    OnChanged()
end

if Commander and Commander.AddListener and COMMANDER_ORDERS_EVENTS then
    if COMMANDER_ORDERS_EVENTS.CHANGED then Commander.AddListener(COMMANDER_ORDERS_EVENTS.CHANGED, OnChanged) end
    if COMMANDER_ORDERS_EVENTS.UPDATE then Commander.AddListener(COMMANDER_ORDERS_EVENTS.UPDATE, OnSettings) end
    -- the Console accent tints the tabs, the selection and the hairline
    if COMMANDER_CONSOLE_EVENTS and COMMANDER_CONSOLE_EVENTS.UPDATE then
        Commander.AddListener(COMMANDER_CONSOLE_EVENTS.UPDATE, OnChanged)
    end
end

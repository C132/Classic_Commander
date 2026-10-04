-- Commander Orders: the manager window harness (luajit).
--
--     luajit Commander_Orders/Harness/orders_ui_harness.lua
--     ORDERS_UI=/tmp/mutant.lua luajit Commander_Orders/Harness/orders_ui_harness.lua
--     ORDERS_UI_PINS=1 luajit Commander_Orders/Harness/orders_ui_harness.lua
--
-- Drives CommanderOrdersUI.lua over orders_mock.lua: the real settings
-- framework and HUD chrome (Commander_Events), every Orders file in TOC
-- order, the DB2 map world. The manager file is loaded by this harness, last,
-- where the TOC puts it, so ORDERS_UI can swap in a copy (mutation runs). The
-- pins file is left out unless ORDERS_UI_PINS is set: the manager never calls
-- it, and it is built separately. Each section boots a fresh client.
--
--   A  load: nothing built, nothing printed, no global written at load, the
--      O.UI surface the runtime calls, plain ASCII
--   B  open and close: the stone sheet, Esc, toggle (binding, /corder),
--      no keyboard focus on open, every box autoFocus off, position and
--      scale kept across a reload, refused while Orders is off, combat-safe
--   C  the list: Arrow / Routes / by zone, the player's zone first, rows
--      (tint, title, zone, distance, source tag), stops under their route,
--      grouping by who set it (kept), folding, corpse and group members
--   D  live distance: 1 Hz while open, text written only on change, rows
--      never reorder on the pass, nothing while hidden, the arrow's ETA
--   E  selection and every waypoint action: Set as arrow, Rename (Enter,
--      Escape, cleared, committed on leaving, never clobbered by a refresh),
--      Share (each channel), Copy /way, Remove, double-click, right-click
--   F  every route action: Start, Previous, Next (at the end), Reverse,
--      Optimise order, Export, Remove route, fold on a second click
--   G  the toolbar: Add here (and with no position), Clear... by reached,
--      by source and everything
--   H  search: title, zone, source, route stops, nothing found, Escape
--   I  paste: with and without /way, comma decimals, #map ids, bad lines
--      reported by number, routes in order and nearest first, Ctrl+Enter,
--      export (nil titles), saved pages
--   J  places: mark, rename, go there, copy, other faction, search, remove
--      (confirmed, and safe when the list moved)
--   K  entry points: Open(uid) on a folded stop, Open(routeId), the arrow's
--      click, CHANGED while open and while hidden, disabling Orders
--   L  hygiene: the named globals, D11 (no byte above 127 in any text), no
--      "nil" in any text, no protected call

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local M = dofile(HERE .. "/orders_mock.lua")
local UI_PATH = os.getenv("ORDERS_UI") or (M.ORDERS .. "/CommanderOrdersUI.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function NEAR(got, want, eps, label)
    CHECK(type(got) == "number" and math.abs(got - want) <= eps, label,
        "got " .. tostring(got) .. ", want " .. tostring(want) .. " +- " .. tostring(eps))
end
local function HAS(s, needle, label)
    CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, "got " .. tostring(s))
end
local function NOERR(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

-- ---------------------------------------------------------------------------
-- Boot with the manager loaded last (its TOC place), from UI_PATH
-- ---------------------------------------------------------------------------
local function LoadUI()
    local chunk, err = loadfile(UI_PATH)
    if not chunk then
        M.loadErrors[#M.loadErrors + 1] = "CommanderOrdersUI.lua: " .. tostring(err)
        return
    end
    local ok, runErr = pcall(chunk)
    if not ok then M.loadErrors[#M.loadErrors + 1] = "CommanderOrdersUI.lua: " .. tostring(runErr) end
end

local function Opts(opts)
    opts = opts or {}
    local skip = { CommanderOrdersUI = true }
    if not os.getenv("ORDERS_UI_PINS") then skip.CommanderOrdersPins = true end
    opts.skipFiles = skip
    local after, noUI = opts.afterFiles, opts.noUI
    opts.afterFiles = function(m, w)
        if not noUI then LoadUI() end
        if after then after(m, w) end
    end
    return opts
end
local function Boot(opts) return M.Boot(Opts(opts)) end
local function Reload(opts) return M.Reload(Opts(opts)) end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function O() return CommanderOrders end
local function R() return CommanderOrders.R end
local function UIW() return CommanderOrders.UI._W() end
local function UIS() return CommanderOrders.UI._State() end
local function Store() return CommanderOrders.R.Store() end
local function DB() return CommanderOrdersDB end
local function Tick(n) for _ = 1, (n or 2) do M.Frame() end end
local function Notify() Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE) end

local GOLDSHIRE = { 1429, 0.42, 0.655 }
local INK_STRONG = { 1.00, 0.95, 0.80 }

local function Rows()
    local out = {}
    for _, row in ipairs(UIW().rows) do
        if row.entry and M.Visible(row) then out[#out + 1] = row end
    end
    return out
end

local function HeaderLabels()
    local out = {}
    for _, row in ipairs(Rows()) do
        if row.entry.kind == "header" then out[#out + 1] = row.label.__text end
    end
    return table.concat(out, ",")
end

local function RowsUnder(header)
    local out, inside = {}, false
    for _, row in ipairs(Rows()) do
        if row.entry.kind == "header" then
            inside = row.label.__text == header
        elseif inside then
            out[#out + 1] = row.label.__text
        end
    end
    return table.concat(out, ",")
end

local function RowBy(title, kind)
    for _, row in ipairs(Rows()) do
        local e = row.entry
        if e.kind ~= "header" and (kind == nil or e.kind == kind) and row.label.__text == title then return row end
    end
    return nil
end

local function CountRows(title)
    local n = 0
    for _, row in ipairs(Rows()) do
        if row.entry.kind ~= "header" and row.label.__text == title then n = n + 1 end
    end
    return n
end

local function HeaderRow(label)
    for _, row in ipairs(Rows()) do
        if row.entry.kind == "header" and row.label.__text == label then return row end
    end
    return nil
end

local function Press(b, button)
    if not b then return false end
    if b.IsEnabled and not b:IsEnabled() then return false end
    return M.Click(b, button or "LeftButton")
end

local function Action(key) return UIW().actionByKey[key] end

local function Info(label)
    for _, line in ipairs(UIW().info) do
        if line.label.__shown ~= false and line.label.__text == label then return line.value.__text end
    end
    return nil
end

local function Focused()
    for _, w in ipairs(M.W.widgets) do
        if w.__kind == "EditBox" and w.__focus then return w end
    end
    return nil
end

local function Type(box, text)
    box:SetText(text)
    local h = box.__scripts.OnTextChanged
    if h then h(box, true) end
end
local function Enter(box) box.__scripts.OnEnterPressed(box) end
local function Escape(box) box.__scripts.OnEscapePressed(box) end

local function MenuEntry(text)
    for _, e in ipairs(M.menu or {}) do if e.text == text then return e end end
    return nil
end

local function LastPopup(which)
    for i = #M.popups, 1, -1 do
        if M.popups[i].which == which then return M.popups[i] end
    end
    return nil
end

local function Colour(t) local c = t.__vertex or t.__color or {} return c[1], c[2], c[3] end
local function SameColour(t, want)
    local r, g, b = Colour(t)
    return r ~= nil and math.abs(r - want[1]) < 1e-6 and math.abs(g - want[2]) < 1e-6 and math.abs(b - want[3]) < 1e-6
end

local function Ancestor(w, root)
    local p = w
    while type(p) == "table" do
        if p == root then return true end
        p = p.__parent
    end
    return false
end

local function Populate()
    local o = O()
    local u = {}
    u.north = o.Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire Abbey" })
    u.lion = o.Add({ map = 1429, x = 0.43, y = 0.66, title = "Lion's Pride Inn", setArrow = false })
    u.sentinel = o.Add({ map = 1436, x = 0.56, y = 0.47, title = "Sentinel Hill", setArrow = false })
    u.portal = o.Add({ map = 1944, x = 0.87, y = 0.50, title = "Dark Portal", setArrow = false })
    u.dughan = o.Add({ map = 1429, x = 0.42, y = 0.66, title = "Marshal Dughan", source = "QuestLog", key = "quest:1", setArrow = false })
    u.share = o.Add({ map = 1429, x = 0.83, y = 0.66, title = "Eastvale camp", source = "share:Thrall", setArrow = false })
    u.tt = o.Add({ map = 1429, x = 0.64, y = 0.69, title = "Tharynn Bouden", source = "TomTom:Questie", icon = "TOMTOM", setArrow = false })
    u.route = o.AddRoute({ title = "Elwynn herbs", mode = "ORDERED", start = false, stops = {
        { map = 1429, x = 0.30, y = 0.30, title = "Peaceleaf" }, { map = 1429, x = 0.50, y = 0.55 },
        { map = 1429, x = 0.62, y = 0.61, title = "Briarthorn" } } })
    Tick()
    return u
end

local function Walk(n2, w2, speed, seconds)
    M.SetSpeed(speed)
    for _ = 1, math.floor(seconds * 30 + 0.5) do
        local p = M.W.player
        local dn, dw = n2 - p.north, w2 - p.west
        local d = math.sqrt(dn * dn + dw * dw)
        local step = speed / 30
        if d <= step then
            M.SetPlayerWorld(p.inst, n2, w2)
        else
            M.SetPlayerWorld(p.inst, p.north + dn / d * step, p.west + dw / d * step)
        end
        M.Frame(1 / 30)
    end
    M.SetSpeed(0)
end

-- ===========================================================================
-- A: load
-- ===========================================================================
Section("A", function()
    Boot({ noUI = true, player = GOLDSHIRE })
    local without = {}
    for _, name in ipairs(M.OrdersWrites()) do without[name] = true end
    Boot({ player = GOLDSHIRE })
    NOERR("A load")
    EQ(#M.prints, 0, "A: a quiet login")
    local extra = {}
    for _, name in ipairs(M.OrdersWrites()) do
        if not without[name] then extra[#extra + 1] = name end
    end
    EQ(#extra, 0, "A: the manager writes no global at load (" .. table.concat(extra, " ") .. ")")
    local ui = O().UI
    EQ(type(ui), "table", "A: O.UI")
    for _, name in ipairs({ "Open", "Toggle", "OpenPaste", "OpenPlaces", "Close", "IsShown", "Refresh", "Select" }) do
        EQ(type(ui[name]), "function", "A: O.UI." .. name)
    end
    EQ(rawget(_G, "CommanderOrdersManager"), nil, "A: nothing built before the first open")
    EQ(ui.IsShown(), false, "A: not shown")
    EQ(type(StaticPopupDialogs.COMMANDER_ORDERS_REMOVE_PLACE), "table", "A: the remove-place dialog is a key added")
    local src = io.open(UI_PATH):read("*a")
    CHECK(not src:find("[\128-\255]"), "A: plain ASCII source (D11)")
    CHECK(not src:find("UISpecialFrames%s*="), "A: UISpecialFrames is never assigned")
    CHECK(not src:find("StaticPopupDialogs%s*="), "A: StaticPopupDialogs is never assigned")
    -- Refresh before any open is harmless
    ui.Refresh()
    NOERR("A refresh unbuilt")
end)

-- ===========================================================================
-- B: open and close
-- ===========================================================================
Section("B", function()
    Boot({ player = GOLDSHIRE })
    local ok = O().OpenManager()
    Tick()
    EQ(ok, true, "B: OpenManager answers true")
    local W = UIW()
    local f = W.frame
    EQ(f, rawget(_G, "CommanderOrdersManager"), "B: the window is CommanderOrdersManager")
    CHECK(M.Visible(f), "B: shown")
    EQ(O().UI.IsShown(), true, "B: IsShown")
    EQ(f.__strata, "HIGH", "B: HIGH strata")
    EQ(f.__w, 660, "B: width")
    EQ(f.__h, 440, "B: height")
    EQ(f.__template, "BasicFrameTemplateWithInset", "B: the suite's window template")
    local listed = false
    for _, name in ipairs(UISpecialFrames) do if name == "CommanderOrdersManager" then listed = true end end
    CHECK(listed, "B: Esc closes (UISpecialFrames)")
    EQ(f.Bg.__shown, false, "B: template Bg hidden for the stone sheet")
    EQ(f.TitleText.__shown, false, "B: template title hidden")
    CHECK(f.CloseButton.__shown ~= false, "B: the close button stays")
    EQ(W.plateTitle.__text, "Orders", "B: the header plate says Orders")
    HAS(W.art.__backdrop and W.art.__backdrop.bgFile, "UI-DialogBox-Background-Dark", "B: dark stone sheet")
    CHECK(W.grip ~= nil, "B: a scale grip")
    EQ(Focused(), nil, "B: no keyboard focus on open")
    EQ(#W.boxes, 5, "B: five edit boxes")
    for i, box in ipairs(W.boxes) do EQ(box.__autoFocus, false, "B: box " .. i .. " autoFocus off") end
    local stray = 0
    for _, w in ipairs(M.W.widgets) do
        if w.__kind == "EditBox" and Ancestor(w, f) then
            local known = false
            for _, box in ipairs(W.boxes) do if box == w then known = true end end
            if not known then stray = stray + 1 end
        end
    end
    EQ(stray, 0, "B: every edit box in the window is accounted for")
    EQ(UIS().tab, "WAYPOINTS", "B: opens on Waypoints")
    CHECK(M.Visible(W.listPane) and M.Visible(W.detailPane), "B: list and detail shown")
    CHECK(not M.Visible(W.pastePane), "B: paste hidden")

    -- Toggle through every door
    O().ToggleManager()
    CHECK(not M.Visible(f), "B: ToggleManager closes")
    O().ToggleManager()
    CHECK(M.Visible(f), "B: ToggleManager opens")
    EQ(Focused(), nil, "B: still no focus after reopening")
    O().Binding("MANAGER")
    CHECK(not M.Visible(f), "B: the key binding closes")
    SlashCmdList.COMMANDERUI_ORDERS("manager")
    CHECK(M.Visible(f), "B: /corder manager opens")
    O().UI.Close()
    CHECK(not M.Visible(f), "B: Close")
    O().UI.Open()
    CHECK(M.Visible(f), "B: Open")

    -- Position: a drag saves it, a reload restores it, at the saved scale
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -80)
    W.drag.__scripts.OnDragStart(W.drag)
    EQ(f.__moving, true, "B: dragging moves the window")
    W.drag.__scripts.OnDragStop(W.drag)
    local pos = DB().ManagerPos
    CHECK(pos and pos.point == "TOPLEFT" and pos.x == 100 and pos.y == -80, "B: drag saves the position",
        pos and (tostring(pos.point) .. " " .. tostring(pos.x) .. " " .. tostring(pos.y)))
    DB().ManagerScale = 1.25
    Reload({})
    O().OpenManager()
    f = UIW().frame
    local p = f.__points[#f.__points]
    CHECK(p and p.point == "TOPLEFT" and math.abs(p.x - 80) < 1e-9 and math.abs(p.y + 64) < 1e-9,
        "B: position restored after a reload, in the window's own units", p and (p.x .. " " .. p.y))
    EQ(f.__scale, 1.25, "B: scale restored")
    DB().ManagerScale = 9
    Reload({})
    O().OpenManager()
    EQ(UIW().frame.__scale, 1, "B: a nonsense saved scale is ignored")

    -- Off: refused, and an open window closes
    DB().EnableOrders = false
    Notify()
    CHECK(not M.Visible(UIW().frame), "B: turning Orders off closes the window")
    M.ClearLog()
    EQ(O().UI.Open(), false, "B: Open refused while off")
    CHECK(M.Has(M.prints, "turned off"), "B: and says why", M.prints[1])
    CHECK(not M.Visible(UIW().frame), "B: still closed")
    DB().EnableOrders = true
    Notify()

    -- Combat: an ordinary window, nothing protected
    M.SetCombat(true)
    M.ClearLog()
    O().OpenManager()
    Tick()
    CHECK(M.Visible(UIW().frame), "B: opens in combat")
    EQ(#M.blocked, 0, "B: no protected call refused")
    M.SetCombat(false)
    NOERR("B")
end)

-- ===========================================================================
-- C: the list
-- ===========================================================================
Section("C", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    O().OpenManager()
    Tick()
    local W = UIW()
    EQ(HeaderLabels(), "Arrow,Routes,Elwynn Forest,Hellfire Peninsula,Westfall",
        "C: Arrow, Routes, then zones with the player's first")
    EQ(RowsUnder("Arrow"), "Northshire Abbey", "C: the arrow's target on top")
    EQ(CountRows("Northshire Abbey"), 1, "C: and not repeated in its zone")
    local north = RowBy("Northshire Abbey")
    CHECK(north.ring.__shown ~= false, "C: the target wears the ring")
    local tc = north.label.__textColor
    CHECK(tc and tc[1] == INK_STRONG[1] and tc[2] == INK_STRONG[2] and tc[3] == INK_STRONG[3],
        "C: the target's title in strong ink")
    local lc = RowBy("Lion's Pride Inn").label.__textColor
    CHECK(lc and lc[1] ~= INK_STRONG[1], "C: other titles in plain ink")
    EQ(HeaderRow("Arrow").count.__text, "", "C: no count on the Arrow heading")
    EQ(HeaderRow("Routes").count.__text, "1", "C: Routes counts routes")
    EQ(HeaderRow("Elwynn Forest").count.__text, "4", "C: Elwynn counts its rows")
    EQ(RowsUnder("Elwynn Forest"), "Eastvale camp,Lion's Pride Inn,Marshal Dughan,Tharynn Bouden",
        "C: rows by title inside a group")
    EQ(RowsUnder("Hellfire Peninsula"), "Dark Portal", "C: Hellfire")
    EQ(RowsUnder("Westfall"), "Sentinel Hill", "C: Westfall")
    -- the zone you stand in leads, whatever its name
    M.SetPlayer(1436, 0.50, 0.50)
    O().UI.Refresh()
    EQ(HeaderLabels(), "Arrow,Routes,Westfall,Elwynn Forest,Hellfire Peninsula", "C: in Westfall, Westfall first")
    M.SetPlayer(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])
    O().UI.Refresh()

    -- Row content
    local lion = RowBy("Lion's Pride Inn")
    EQ(lion.sub.__text, "Elwynn Forest", "C: the zone under the title")
    local wp = Store():Get(u.lion)
    local want = R().Distance(Store():Distance(wp, R().Ctx()))
    EQ(lion.dist.__text, want, "C: the live distance")
    HAS(lion.dist.__text, " yd", "C: in yards")
    EQ(lion.tag.__text, "", "C: your own waypoint needs no source tag")
    EQ(lion.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Pin.png", "C: our pin art")
    CHECK(SameColour(lion.icon, O().Data.ICON_COLOURS.USER), "C: your tint")
    local dughan = RowBy("Marshal Dughan")
    EQ(dughan.tag.__text, "Quest Log", "C: the Quest Log's tag")
    CHECK(SameColour(dughan.icon, O().Data.ICON_COLOURS.QUEST), "C: quest tint")
    local share = RowBy("Eastvale camp")
    EQ(share.tag.__text, "From Thrall", "C: who shared it")
    CHECK(SameColour(share.icon, O().Data.ICON_COLOURS.SHARE), "C: share tint")
    local tt = RowBy("Tharynn Bouden")
    EQ(tt.tag.__text, "Questie (TomTom)", "C: a TomTom request names its addon")
    CHECK(SameColour(tt.icon, O().Data.ICON_COLOURS.TOMTOM), "C: TomTom tint")
    -- a source that names no icon wears Data.SOURCE_ICONS' tint, the table
    -- the pins read too, and Data.SOURCE_WORDS' name
    local rep = O().Add({ map = 1429, x = 0.36, y = 0.36, title = "Smith", source = "Logistics", key = "t:rep",
        setArrow = false })
    O().UI.Refresh()
    CHECK(RowBy("Smith") and SameColour(RowBy("Smith").icon, O().Data.ICON_COLOURS.VENDOR),
        "C: Logistics, no icon: the vendor tint from Data.SOURCE_ICONS")
    EQ(RowBy("Smith") and RowBy("Smith").tag.__text, "Logistics", "C: ...and its name from Data.SOURCE_WORDS")
    O().Remove(rep)
    O().UI.Refresh()
    EQ(RowBy("Dark Portal").dist.__text, "Outland", "C: another landmass says which")
    HAS(RowBy("Sentinel Hill").dist.__text, " yd", "C: Westfall is measured (same landmass)")
    CHECK(lion.ring.__shown == false, "C: no ring off target")

    -- The route and its stops
    local route = RowBy("Elwynn herbs", "route")
    CHECK(route ~= nil, "C: the route row")
    EQ(route.sub.__text, "In order, 3 stops", "C: route order and size")
    EQ(route.dist.__text, "Stop 1 of 3", "C: where the route stands")
    EQ(route.icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Badge.png", "C: route badge art")
    EQ(RowsUnder("Routes"), "Elwynn herbs,Peaceleaf,Stop 2,Briarthorn", "C: stops under their route, in order")
    local stop = RowBy("Peaceleaf")
    EQ(stop.badge.__text, "1", "C: the stop's number on its badge")
    EQ(RowBy("Briarthorn").badge.__text, "3", "C: third stop")
    EQ(stop.icon.__points[1].x, 22, "C: stops indented under the route")
    EQ(lion.icon.__points[1].x, 10, "C: plain rows not indented")

    -- Group by who set it, kept
    Press(W.groupButtons[2])
    EQ(DB().ManagerGroupBy, "SOURCE", "C: Group by who set it")
    EQ(HeaderLabels(), "Arrow,Routes,Yours,Shared with you,Quest Log,Questie (TomTom)", "C: source groups")
    EQ(RowsUnder("Yours"), "Dark Portal,Lion's Pride Inn,Sentinel Hill", "C: yours together")
    -- consumers' waypoints are session-only (SPEC 6), so the reload keeps
    -- yours and the shares; the grouping itself is what is checked
    Reload({})
    O().OpenManager()
    Tick()
    EQ(DB().ManagerGroupBy, "SOURCE", "C: the grouping is saved")
    EQ(HeaderLabels(), "Arrow,Routes,Yours,Shared with you", "C: and used after a reload")
    Press(UIW().groupButtons[1])
    EQ(DB().ManagerGroupBy, "ZONE", "C: back to zones")
    EQ(HeaderLabels(), "Arrow,Routes,Elwynn Forest,Hellfire Peninsula,Westfall", "C: zones again")

    -- Folding
    local elwynn = HeaderRow("Elwynn Forest")
    CHECK(Press(elwynn), "C: a zone heading takes a click")
    EQ(RowsUnder("Elwynn Forest"), "", "C: folded")
    EQ(RowBy("Lion's Pride Inn"), nil, "C: its rows gone")
    Press(HeaderRow("Elwynn Forest"))
    EQ(RowsUnder("Elwynn Forest"), "Eastvale camp,Lion's Pride Inn", "C: unfolded")
    CHECK(not Press(HeaderRow("Arrow")), "C: the Arrow heading is not a button")

    -- Group members and the corpse
    M.SetGroup("party", { "Bob" })
    M.SetUnit("party1", 1429, 0.5, 0.5)
    local unit = O().Add({ kind = "unit", unit = "party1", title = "Bob", setArrow = false })
    CHECK(unit ~= nil, "C: a group member to follow")
    Tick()
    EQ(RowsUnder("Group members"), "Bob", "C: group members have their own group")
    EQ(RowBy("Bob").sub.__text, "Following a group member", "C: and say so")
    local st = Store()
    st:Add({ kind = "corpse", source = "corpse", map = 1429, x = 0.40, y = 0.60, title = "Your corpse", setArrow = false })
    M.SetLife("GHOST")
    R().Changed("corpse", true)
    Tick()
    EQ(RowsUnder("Arrow"), "Your corpse", "C: a ghost's arrow is the corpse")
    EQ(RowBy("Your corpse").icon.__texture, "Interface\\AddOns\\Commander_Orders\\Textures\\Corpse.png", "C: tombstone art")
    M.SetLife("ALIVE")

    -- Empty
    Boot({ player = GOLDSHIRE })
    O().OpenManager()
    Tick()
    CHECK(M.Visible(UIW().listEmpty), "C: an empty list says so")
    HAS(UIW().listEmpty.__text, "No waypoints yet", "C: and how to add one")
    CHECK(M.Visible(UIW().detailEmpty), "C: an empty detail says what to do")
    EQ(UIW().detailRule.__shown, false, "C: no stray rule on an empty detail")
    NOERR("C")
end)

-- ===========================================================================
-- D: live distance
-- ===========================================================================
Section("D", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    O().OpenManager()
    Tick()
    local row = RowBy("Lion's Pride Inn")
    local calls = 0
    local orig = row.dist.SetText
    row.dist.SetText = function(s, t) calls = calls + 1 return orig(s, t) end
    local entries = UIS().entries
    M.Advance(3.2)
    EQ(calls, 0, "D: standing still writes nothing")
    EQ(UIS().entries, entries, "D: the live pass never rebuilds the list")
    -- walking: about one write a second, not one a frame
    local n0, w0 = M.World(1429, 0.43, 0.66)
    local before = row.dist.__text
    local pn, pw = M.W.player.north, M.W.player.west
    Walk(pn + (pn - n0) * 3, pw + (pw - w0) * 3, 7, 5)
    CHECK(calls >= 4 and calls <= 6, "D: 1 Hz while walking", calls)
    CHECK(row.dist.__text ~= before, "D: the distance moved", row.dist.__text)
    local want = R().Distance(Store():Distance(Store():Get(u.lion), R().Ctx()))
    M.Advance(1.05)
    EQ(row.dist.__text, want, "D: and reads true")
    EQ(UIS().entries, entries, "D: still the same rows")
    -- the detail's distance line too
    O().UI.Select("wp", u.lion)
    local was = Info("Distance")
    M.SetPlayer(1429, 0.44, 0.70)
    M.Advance(1.05)
    CHECK(Info("Distance") ~= was, "D: the detail's distance follows", Info("Distance"))
    -- hidden: no work; reopened: fresh at once
    O().UI.Close()
    calls = 0
    M.SetPlayer(1429, 0.42, 0.655)
    M.Advance(3)
    EQ(calls, 0, "D: nothing while hidden")
    O().OpenManager()
    local fresh = R().Distance(Store():Distance(Store():Get(u.lion), R().Ctx()))
    EQ(RowBy("Lion's Pride Inn").dist.__text, fresh, "D: reopened, the distance is current at once")
    -- the arrow target's ETA
    O().UI.Select("wp", u.north)
    local tn, tw = M.World(1429, 0.48, 0.42)
    M.SetFacing(0)
    Walk(tn, tw, 7, 3)
    HAS(Info("Distance"), ", about ", "D: the arrow's target shows the arrival time while you walk")
    O().UI.Select("wp", u.lion)
    CHECK(not (Info("Distance") or ""):find("about", 1, true), "D: other waypoints show distance only")
    NOERR("D")
end)

-- ===========================================================================
-- E: selection and the waypoint actions
-- ===========================================================================
Section("E", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    O().OpenManager()
    Tick()
    local W = UIW()
    local st = Store()
    CHECK(Press(RowBy("Lion's Pride Inn")), "E: a row takes a click")
    local sel = UIS().sel.WAYPOINTS
    CHECK(sel and sel.kind == "wp" and sel.uid == u.lion, "E: selected")
    local row = RowBy("Lion's Pride Inn")
    CHECK(row.selected and row.highlight.__shown ~= false and row.bar.__shown ~= false, "E: the selection is marked")
    EQ(W.titleBox.__text, "Lion's Pride Inn", "E: the title, editable")
    CHECK(M.Visible(W.titleBox), "E: the title box shows")
    EQ(W.kindText.__text, "Waypoint", "E: what it is")
    EQ(Info("Where"), "Elwynn Forest 43.0, 66.0", "E: zone and coordinates")
    EQ(Info("Set by"), "You", "E: who set it")
    HAS(Info("Added"), "Today, ", "E: when")
    EQ(Info("Arrival"), "Within 10 yd, then it clears", "E: what arriving does")
    HAS(Info("Distance"), " yd", "E: distance")
    EQ(Focused(), nil, "E: selecting takes no focus")
    local labels = {}
    for _, key in ipairs({ "arrow", "rename", "share", "copy", "remove" }) do
        local b = Action(key)
        CHECK(b and M.Visible(b), "E: action " .. key)
        labels[#labels + 1] = b and b.__text or "?"
    end
    EQ(table.concat(labels, ","), "Set as arrow,Rename,Share,Copy /way,Remove", "E: the action labels")
    local rp = Action("remove").__points[1]
    CHECK(rp and rp.point == "BOTTOMRIGHT" and rp.rel == W.detailPane, "E: Remove stands apart, bottom right")
    EQ(Action("arrow").__points[1].y, 0, "E: the others share one row")
    EQ(Action("copy").__points[1].y, 0, "E: one row (Copy)")

    -- Set as arrow
    Press(Action("arrow"))
    EQ(st:Pinned() and st:Pinned().uid, u.lion, "E: Set as arrow pins it")
    EQ(W.status.__text, "The arrow follows it now.", "E: and says so")
    Tick()
    EQ(RowsUnder("Arrow"), "Lion's Pride Inn", "E: the Arrow group follows")
    EQ(CountRows("Northshire Abbey"), 1, "E: the old target is back in its zone")
    EQ(Info("Arrow"), "Following it: you chose it", "E: why the arrow follows it")

    -- Rename: Enter commits, focus leaves
    Press(Action("rename"))
    EQ(W.titleBox.__focus, true, "E: Rename puts the keyboard in the title")
    Type(W.titleBox, "Lion's Pride")
    Enter(W.titleBox)
    EQ(st:Get(u.lion).title, "Lion's Pride", "E: Enter renames")
    EQ(W.titleBox.__focus, false, "E: and lets the keyboard go")
    Tick()
    CHECK(RowBy("Lion's Pride") ~= nil, "E: the row follows the new title")
    -- Escape puts it back
    Press(Action("rename"))
    Type(W.titleBox, "junk")
    Escape(W.titleBox)
    EQ(W.titleBox.__text, "Lion's Pride", "E: Escape restores the title")
    EQ(st:Get(u.lion).title, "Lion's Pride", "E: and changes nothing")
    -- Cleared: the place stands in for it
    Press(Action("rename"))
    Type(W.titleBox, "")
    Enter(W.titleBox)
    EQ(st:Get(u.lion).title, nil, "E: an empty title clears it")
    Tick()
    CHECK(RowBy("Elwynn Forest 43.0, 66.0") ~= nil, "E: an untitled row reads its place")
    EQ(RowBy("Elwynn Forest 43.0, 66.0").sub.__text, "Untitled waypoint", "E: and does not repeat its zone")
    EQ(W.titleBox.ghost.__text, "Untitled: Elwynn Forest 43.0, 66.0", "E: the box says so")
    CHECK(W.titleBox.ghost.__shown ~= false, "E: the hint shows in the empty box")
    -- Committed when you move on
    Press(Action("rename"))
    Type(W.titleBox, "Inn")
    Press(RowBy("Marshal Dughan"))
    EQ(st:Get(u.lion).title, "Inn", "E: picking another row keeps the rename")
    EQ(W.titleBox.__focus, false, "E: and drops the keyboard")
    EQ(W.titleBox.__text, "Marshal Dughan", "E: the box shows the new selection")
    -- Never clobbered by a refresh mid-typing
    Press(RowBy("Inn"))
    Press(Action("rename"))
    Type(W.titleBox, "typing...")
    O().Add({ map = 1429, x = 0.70, y = 0.70, title = "Arrives mid-rename", source = "QuestLog", key = "q:9", setArrow = false })
    Tick()
    EQ(W.titleBox.__text, "typing...", "E: a refresh never overwrites what you are typing")
    CHECK(RowBy("Arrives mid-rename") ~= nil, "E: while the list still updates")
    Escape(W.titleBox)
    EQ(st:Get(u.lion).title, "Inn", "E: and Escape still restores")

    -- Share
    M.ClearLog()
    Press(Action("share"))
    local group = MenuEntry("With your group")
    CHECK(group and group.disabled, "E: Share: not in a group, the group entry is off")
    CHECK(MenuEntry("As a /way line in group chat") == nil, "E: no group chat without a group")
    CHECK(M.ClickMenu("As a /way line in /say"), "E: Share: say it")
    local said = M.chat[#M.chat]
    CHECK(said and said.chatType == "SAY" and said.text == "/way #1429 43.00 66.00 Inn", "E: /say carries the /way line",
        said and said.text)
    EQ(W.status.__text, "Posted in chat as a /way line.", "E: and says so")
    M.SetGroup("party", { "Bob" })
    Press(Action("share"))
    CHECK(not MenuEntry("With your group").disabled, "E: in a group, the group entry is on")
    M.ClickMenu("With your group")
    local sent = M.sent[#M.sent]
    CHECK(sent and sent.prefix == "CmdrOrders" and sent.channel == "PARTY", "E: shared on the addon channel", sent and sent.channel)
    EQ(W.status.__text, "Sent to your group.", "E: and says so")
    Press(Action("share"))
    M.ClickMenu("As a /way line in group chat")
    said = M.chat[#M.chat]
    CHECK(said and said.chatType == "PARTY", "E: group chat goes to the party", said and said.chatType)
    W.status.__text = nil
    M.W.sendResult = 5
    Press(Action("share"))
    M.ClickMenu("With your group")
    HAS(W.status.__text, "Could not share", "E: a refused send says so")
    M.W.sendResult = 0

    -- Copy /way
    M.ClearLog()
    Press(Action("copy"))
    local pop = LastPopup("COMMANDER_ORDERS_COPY")
    CHECK(pop ~= nil, "E: Copy /way opens the copy box")
    EQ(R().ArrowState().copyText, "/way #1429 43.00 66.00 Inn", "E: with the line")

    -- Double-click and right-click
    local dughan = RowBy("Marshal Dughan")
    dughan.__scripts.OnDoubleClick(dughan)
    EQ(st:Pinned() and st:Pinned().uid, u.dughan, "E: a double-click points the arrow")
    M.Click(RowBy("Eastvale camp"), "RightButton")
    EQ(UIS().sel.WAYPOINTS.uid, u.share, "E: a right-click selects")
    CHECK(MenuEntry("Set as arrow") and MenuEntry("Copy /way line") and MenuEntry("Remove"), "E: and opens the menu",
        table.concat(M.MenuTexts(), "|"))

    -- Remove
    Press(RowBy("Inn"))
    Press(Action("remove"))
    EQ(st:Get(u.lion), nil, "E: Remove removes")
    EQ(UIS().sel.WAYPOINTS, nil, "E: and drops the selection")
    Tick()
    EQ(RowBy("Inn"), nil, "E: the row is gone")
    CHECK(M.Visible(W.detailEmpty), "E: the detail is empty again")
    HAS(W.status.__text, "Removed Inn.", "E: and says what went")

    -- A group member has no place to copy or share
    local unit = O().Add({ kind = "unit", unit = "party1", title = "Bob", setArrow = false })
    Tick()
    O().UI.Select("wp", unit)
    EQ(Action("copy"):IsEnabled(), false, "E: no /way line for a group member")
    EQ(Action("share"):IsEnabled(), false, "E: nothing to share")
    CHECK(not Press(Action("copy")), "E: a disabled button does nothing")
    NOERR("E")
end)

-- ===========================================================================
-- F: the route actions
-- ===========================================================================
Section("F", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    O().OpenManager()
    Tick()
    local W = UIW()
    local st = Store()
    local route = st:GetRoute(u.route)
    Press(RowBy("Elwynn herbs", "route"))
    EQ(UIS().sel.WAYPOINTS.id, u.route, "F: the route selected")
    CHECK(not M.Visible(W.titleBox) and M.Visible(W.titleText), "F: a route's title is not edited in place")
    EQ(W.titleText.__text, "Elwynn herbs", "F: its title")
    EQ(W.kindText.__text, "Route", "F: what it is")
    EQ(Info("Order"), "In order", "F: order")
    EQ(Info("Stops"), "3 stops, on stop 1", "F: stops")
    EQ(Info("Next"), "Peaceleaf", "F: the next stop")
    HAS(Info("Distance"), " yd", "F: and how far")
    local labels = {}
    for _, key in ipairs({ "start", "prev", "next", "reverse", "optimise", "export", "removeRoute" }) do
        local b = Action(key)
        CHECK(b and M.Visible(b), "F: action " .. key)
        labels[#labels + 1] = b and b.__text or "?"
    end
    EQ(table.concat(labels, ","), "Start,Previous,Next,Reverse,Optimise order,Export,Remove route", "F: the labels")

    Press(Action("start"))
    EQ(st:ActiveRoute(), route, "F: Start runs the route")
    EQ(W.status.__text, "The arrow follows the route.", "F: and says so")
    Tick()
    EQ(Action("start").__text, "Restart", "F: Start becomes Restart")
    EQ(RowBy("Elwynn herbs", "route").tag.__text, "running", "F: the row says it runs")
    EQ(RowsUnder("Arrow"), "Peaceleaf", "F: the arrow on its first stop")
    Press(Action("next"))
    EQ(route.index, 2, "F: Next")
    Press(Action("next"))
    EQ(route.index, 3, "F: Next again")
    Press(Action("next"))
    EQ(route.index, 3, "F: Next at the end stays")
    HAS(W.status.__text, "last stop", "F: and explains")
    Press(Action("prev"))
    EQ(route.index, 2, "F: Previous")
    Press(Action("reverse"))
    EQ(st:Get(route.stops[1]).title, "Briarthorn", "F: Reverse")
    EQ(route.index, 2, "F: the current stop stays current")
    Press(Action("optimise"))
    EQ(W.status.__text, "Re-ordered: nearest first from here.", "F: Optimise order")
    Press(Action("prev"))
    Press(Action("prev"))
    HAS(W.status.__text, "first stop", "F: Previous at the start explains")

    -- Export: the Paste tab, the lines, the name, the keyboard for Ctrl+C
    Press(Action("export"))
    EQ(UIS().tab, "PASTE", "F: Export opens the paste tab")
    local text = W.pasteBox.__text
    local n = 0
    for line in text:gmatch("[^\n]+") do
        n = n + 1
        CHECK(line:match("^/way #1429 %d+%.%d%d %d+%.%d%d"), "F: an exported line", line)
    end
    EQ(n, 3, "F: one line per stop")
    EQ(W.pageName.__text, "Elwynn herbs", "F: named after the route")
    EQ(W.pasteBox.__focus, true, "F: the box has the keyboard for Ctrl+C (Export was clicked)")
    Press(W.tabs[1])
    EQ(UIS().tab, "WAYPOINTS", "F: back to the list")
    EQ(UIS().sel.WAYPOINTS.id, u.route, "F: the route still selected")
    EQ(W.pasteBox.__focus, false, "F: leaving the paste tab gives the keyboard back")

    -- A second click on the selected route folds it
    Press(RowBy("Elwynn herbs", "route"))
    EQ(RowsUnder("Routes"), "Elwynn herbs", "F: folded")
    Press(RowBy("Elwynn herbs", "route"))
    EQ(RowsUnder("Routes"), "Elwynn herbs,Briarthorn,Stop 2,Peaceleaf", "F: unfolded")

    Press(Action("removeRoute"))
    EQ(st:GetRoute(u.route), nil, "F: Remove route")
    EQ(UIS().sel.WAYPOINTS, nil, "F: and the selection with it")
    Tick()
    EQ(RowBy("Elwynn herbs", "route"), nil, "F: gone from the list")
    NOERR("F")
end)

-- ===========================================================================
-- G: the toolbar
-- ===========================================================================
Section("G", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    O().OpenManager()
    Tick()
    local W = UIW()
    local st = Store()
    CHECK(M.Visible(W.addHere) and M.Visible(W.clear), "G: Add here and Clear on the Waypoints tab")
    CHECK(not M.Visible(W.markPlace), "G: Mark place only on Places")
    EQ(W.addHere.__text, "Add here", "G: label")
    EQ(W.clear.__text, "Clear...", "G: label")
    local count = st:Count()
    Press(W.addHere)
    EQ(st:Count(), count + 1, "G: Add here adds")
    local sel = UIS().sel.WAYPOINTS
    local wp = sel and st:Get(sel.uid)
    CHECK(wp and wp.map == 1429 and math.abs(wp.x - 0.42) < 1e-6 and math.abs(wp.y - 0.655) < 1e-6,
        "G: where you stand, selected")
    EQ(st:Pinned(), wp, "G: with the arrow")
    HAS(W.status.__text, "where you stand", "G: and says so")
    M.SetNoPosition(true)
    Press(W.addHere)
    EQ(st:Count(), count + 1, "G: no position, nothing added")
    HAS(W.status.__text, "no map position", "G: and says why")
    M.SetNoPosition(false)

    -- Clear...: reached ones, by source, everything
    local keep = O().Add({ map = 1429, x = 0.425, y = 0.655, title = "Keep me", clearOnArrive = false })
    M.Advance(0.5)              -- first measured outside its radius
    M.SetPlayer(1429, 0.425, 0.655)
    M.Advance(4)
    CHECK(st:Get(keep) and st:Get(keep).reached, "G: a kept waypoint is reached")
    M.SetPlayer(1429, 0.42, 0.655)
    Tick()
    EQ(RowBy("Keep me").tag.__text, "reached", "G: and its row says so")
    M.ClearLog()
    Press(W.clear)
    local texts = table.concat(M.MenuTexts(), "|")
    CHECK(MenuEntry("Reached ones (1)") and not MenuEntry("Reached ones (1)").disabled, "G: Clear offers the reached", texts)
    CHECK(MenuEntry("Set by Quest Log (1)") ~= nil, "G: by source", texts)
    CHECK(MenuEntry("Shared by Thrall (1)") ~= nil, "G: shares by sender", texts)
    CHECK(MenuEntry("Set by Questie (TomTom) (1)") ~= nil, "G: TomTom requests by addon", texts)
    CHECK(MenuEntry("Everything...") ~= nil, "G: and everything", texts)
    CHECK(not texts:find("You", 1, true), "G: never your own marks by source", texts)
    M.ClickMenu("Reached ones (1)")
    EQ(st:Get(keep), nil, "G: reached ones removed")
    Press(W.clear)
    M.ClickMenu("Set by Quest Log (1)")
    EQ(st:Get(u.dughan), nil, "G: the Quest Log's removed")
    CHECK(st:Get(u.share) ~= nil and st:Get(u.lion) ~= nil, "G: nobody else's")
    HAS(W.status.__text, "1 waypoint removed", "G: and counted")
    Press(W.clear)
    EQ(MenuEntry("Reached ones (0)").disabled, true, "G: nothing reached, the entry is off")
    local standing = st:Count()
    CHECK(standing > 0, "G: some left to clear")
    M.ClickMenu("Everything...")
    local pop = LastPopup("COMMANDER_ORDERS_CLEAR_ALL")
    CHECK(pop ~= nil, "G: Everything asks first")
    EQ(st:Count(), standing, "G: nothing removed before the answer")
    M.ClickPopup("COMMANDER_ORDERS_CLEAR_ALL", 1)
    EQ(st:Count(), 0, "G: everything removed")
    EQ(#st:Routes(), 0, "G: routes too")
    Tick()
    CHECK(M.Visible(W.listEmpty), "G: the list is empty")
    NOERR("G")
end)

-- ===========================================================================
-- H: search
-- ===========================================================================
Section("H", function()
    Boot({ player = GOLDSHIRE })
    Populate()
    O().OpenManager()
    Tick()
    local W = UIW()
    EQ(W.search.ghost.__text, "Search waypoints", "H: the search box says what it searches")
    Type(W.search, "dughan")
    EQ(HeaderLabels(), "Elwynn Forest", "H: by title: only its group")
    EQ(RowsUnder("Elwynn Forest"), "Marshal Dughan", "H: only the match")
    EQ(HeaderRow("Elwynn Forest").count.__text, "1", "H: counted")
    CHECK(W.search.ghost.__shown == false, "H: the hint gives way to text")
    Type(W.search, "WESTFALL")
    EQ(RowsUnder("Westfall"), "Sentinel Hill", "H: by zone, any case")
    Type(W.search, "quest log")
    EQ(RowsUnder("Elwynn Forest"), "Marshal Dughan", "H: by who set it")
    Type(W.search, "thrall")
    EQ(RowsUnder("Elwynn Forest"), "Eastvale camp", "H: by sender")
    Type(W.search, "peace")
    EQ(RowsUnder("Routes"), "Elwynn herbs,Peaceleaf", "H: a route with only its matching stop")
    Type(W.search, "herbs")
    EQ(RowsUnder("Routes"), "Elwynn herbs,Peaceleaf,Stop 2,Briarthorn", "H: a route's own title shows every stop")
    Type(W.search, "northshire")
    EQ(RowsUnder("Arrow"), "Northshire Abbey", "H: the arrow's target")
    Type(W.search, "zzz")
    CHECK(M.Visible(W.listEmpty), "H: nothing found says so")
    EQ(W.listEmpty.__text, "Nothing matches that.", "H: in words")
    Type(W.search, "a.b%")
    NOERR("H magic characters are plain text")
    Escape(W.search)
    EQ(W.search.__text, "", "H: Escape clears")
    EQ(HeaderLabels(), "Arrow,Routes,Elwynn Forest,Hellfire Peninsula,Westfall", "H: everything back")
    Type(W.search, "lion")
    Press(W.tabs[2])
    EQ(W.search.__text, "", "H: a tab change starts a fresh search")
    EQ(UIS().search, "", "H: (state too)")
    EQ(W.search.ghost.__text, "Search places", "H: and says what it searches now")
    NOERR("H")
end)

-- ===========================================================================
-- I: paste
-- ===========================================================================
Section("I", function()
    Boot({ player = GOLDSHIRE })
    local ok = O().OpenPaste()
    Tick()
    local W = UIW()
    local st = Store()
    EQ(ok, true, "I: OpenPaste")
    EQ(UIS().tab, "PASTE", "I: on the paste tab")
    CHECK(M.Visible(W.pastePane), "I: the paste pane")
    CHECK(not M.Visible(W.listPane) and not M.Visible(W.detailPane), "I: in place of the list")
    CHECK(not M.Visible(W.search), "I: no search here")
    CHECK(not M.Visible(W.addHere) and not M.Visible(W.markPlace), "I: no list actions here")
    EQ(Focused(), nil, "I: no keyboard focus on open")
    EQ(W.pasteBox.__autoFocus, false, "I: the paste box never grabs it")
    CHECK(type(W.pasteBox.__scripts.OnEnterPressed) == "function", "I: Enter handled (newline / Ctrl+Enter)")
    CHECK(M.Visible(W.pasteBox.ghost), "I: an example while empty")
    CHECK(not M.Visible(W.routeTitle), "I: no route name while adding waypoints")

    -- Nothing yet
    Press(W.import)
    HAS(W.result.__text, "Nothing to add yet", "I: an empty box says so")
    EQ(st:Count(), 0, "I: and adds nothing")

    -- Waypoints: with and without /way, comma decimals, #ids, bad lines
    W.pasteBox:SetText(table.concat({
        "/way 45 66 Plain current zone",
        "48.1 41.9 Bare line without way",
        "/way #1436 56,47 Comma pair",
        "/way Westfall 45,2 66,8 Decimal commas",
        "#1429 30 40",
        "/way Narnia 10 10 Nowhere",
        "hello world",
        "/way 120 40 Out of range",
        "",
        "/tway 50 50 TomTom spelling",
    }, "\n"))
    Press(W.import)
    local function Find(title)
        for _, wp in ipairs(st:List()) do if wp.title == title then return wp end end
        return nil
    end
    EQ(st:Count(), 6, "I: six lines added")
    local a = Find("Plain current zone")
    CHECK(a and a.map == 1429 and math.abs(a.x - 0.45) < 1e-9 and math.abs(a.y - 0.66) < 1e-9, "I: current zone")
    local b = Find("Bare line without way")
    CHECK(b and math.abs(b.x - 0.481) < 1e-9 and math.abs(b.y - 0.419) < 1e-9, "I: no /way in front keeps x (TomTom B18)")
    local c = Find("Comma pair")
    CHECK(c and c.map == 1436 and math.abs(c.x - 0.56) < 1e-9 and math.abs(c.y - 0.47) < 1e-9, "I: #id and a 56,47 pair")
    local d = Find("Decimal commas")
    CHECK(d and d.map == 1436 and math.abs(d.x - 0.452) < 1e-9 and math.abs(d.y - 0.668) < 1e-9, "I: zone name and decimal commas")
    local e = st:Find(1429, 0.30, 0.40, nil)
    CHECK(e ~= nil and e.title == nil, "I: an untitled line stays untitled")
    CHECK(Find("TomTom spelling") ~= nil, "I: /tway too")
    EQ(st:Pinned(), a, "I: the arrow on the first")
    local text = W.result.__text
    HAS(text, "Added 6 waypoints", "I: the count")
    HAS(text, "3 lines could not be read:", "I: the refusals counted")
    HAS(text, "Line 6 (/way Narnia 10 10 Now...): ", "I: by line number (unknown zone), with how it starts")
    HAS(text, "Narnia", "I: with the reason")
    HAS(text, "Line 7 (hello world): ", "I: not a /way line")
    HAS(text, "Line 8 (/way 120 40 Out of range): ", "I: out of range")
    CHECK(not text:find("Line 9", 1, true), "I: an empty line is not an error")
    EQ(W.pasteBox.__focus, false, "I: adding lets the keyboard go")

    -- Blank lines count: "Line N" is the box's own line (review: surfaces)
    -- (the first line is one already added: the same record, the same arrow)
    W.pasteBox:SetText("/way 45 66 Plain current zone\n\n/way Nowhereland 12 Second\n\n\n/way Nowhereland 50 50 Third")
    Press(W.import)
    HAS(W.result.__text, "Line 3 (/way Nowhereland 12 S...)", "I: a bad line after a blank one: its box line")
    HAS(W.result.__text, "Line 6 (/way Nowhereland 50 5...)", "I: after three blank ones too")
    CHECK(not W.result.__text:find("Line 2", 1, true), "I: the old count (blank lines skipped) is gone")
    EQ(st:Count(), 6, "I: (nothing new added)")

    -- Many bad lines: as many as the box holds, the count of the rest kept
    -- (four ambiguous zones wrote fifteen lines into a nine-line box)
    W.pasteBox:SetText(table.concat({
        "/way Plaguelands 40 40 One", "/way Plaguelands 41 41 Two", "/way Plaguelands 42 42 Three",
        "/way Plaguelands 43 43 Four", "/way Nowhereland 50 50 Five",
    }, "\n"))
    Press(W.import)
    local many = W.result.__text
    HAS(many, "5 lines could not be read:", "I: five refusals counted")
    HAS(many, "Line 1 (", "I: the first one named")
    local more = tonumber(many:match("and (%d+) more%.$"))
    CHECK(more ~= nil, "I: the last line says how many more", many)
    local listed = 0
    for _ in many:gmatch("Line %d+ %(") do listed = listed + 1 end
    EQ(listed + (more or 0), 5, "I: named plus the rest is every bad line")
    local wrapped = 0
    for line in (many .. "\n"):gmatch("([^\n]*)\n") do wrapped = wrapped + math.max(1, math.ceil(#line / (424 / 6))) end
    CHECK(wrapped * 12 <= 107, "I: and all of it fits the 424 x 107 box", wrapped .. " lines")

    -- Ambiguous zones offer the exact line
    W.pasteBox:SetText("/way Plaguelands 40 40 Bridge")
    Press(W.import)
    HAS(W.result.__text, "for example /way #", "I: an ambiguous zone offers a /way #id line")
    HAS(W.result.__text, "Nothing was added.", "I: and adds nothing")

    -- A route, in order
    Press(W.modeButtons[2])
    EQ(UIS().pasteMode, "ORDERED", "I: route in order")
    CHECK(M.Visible(W.routeTitle), "I: the route gets a name box")
    CHECK(W.modeButtons[2].underline.__shown ~= false and W.modeButtons[1].underline.__shown == false, "I: the mode is marked")
    Type(W.routeTitle, "Paste test")
    W.pasteBox:SetText("/way 30 30 One\n/way 60 60 Two\nnot a line\n/way 40 40 Three")
    Press(W.import)
    local routes = st:Routes()
    local r = routes[#routes]
    CHECK(r and r.title == "Paste test" and r.mode == "ORDERED" and #r.stops == 3, "I: one route of three stops",
        r and (tostring(r.title) .. " " .. tostring(r.mode) .. " " .. #r.stops))
    EQ(st:Get(r.stops[1]).title, "One", "I: in the order given")
    EQ(st:Get(r.stops[3]).title, "Three", "I: to the last")
    EQ(st:ActiveRoute(), r, "I: started")
    HAS(W.result.__text, "Added a route of 3 stops: Paste test", "I: and said so")
    HAS(W.result.__text, "Line 3 (not a line): ", "I: the bad line still reported")
    CHECK(UIS().sel.WAYPOINTS and UIS().sel.WAYPOINTS.id == r.id, "I: the new route is selected for the list")
    -- Nearest first, unnamed
    Press(W.modeButtons[3])
    Type(W.routeTitle, "")
    W.pasteBox:SetText("/way 80 80 Far\n/way 43 66 Near")
    Press(W.import)
    routes = st:Routes()
    r = routes[#routes]
    CHECK(r and r.mode == "NEAREST" and r.title == "Pasted route", "I: nearest first, a default name",
        r and (tostring(r.mode) .. " " .. tostring(r.title)))
    EQ(st:Get(r.stops[1]).title, "Near", "I: nearest first from where you stand")
    Press(W.modeButtons[1])
    CHECK(not M.Visible(W.routeTitle), "I: back to waypoints")

    -- Ctrl+Enter adds; Enter is a newline
    local before = st:Count()
    W.pasteBox:SetText("/way 33 33 Ctrl enter")
    M.SetModifier("CTRL", true)
    Enter(W.pasteBox)
    M.SetModifier("CTRL", false)
    EQ(st:Count(), before + 1, "I: Ctrl+Enter adds")
    local inserted
    W.pasteBox.Insert = function(_, s) inserted = s end
    W.pasteBox:SetText("/way 34 34 Plain enter")
    Enter(W.pasteBox)
    EQ(st:Count(), before + 1, "I: plain Enter adds nothing")
    EQ(inserted, "\n", "I: plain Enter is a newline")

    -- Export, untitled lines included, no "nil"
    M.ClearLog()
    Press(W.export)
    local every = MenuEntry(string.format("Every waypoint (%d)", #O().Export()))
    CHECK(every ~= nil, "I: Export offers every waypoint", table.concat(M.MenuTexts(), "|"))
    CHECK(MenuEntry("Route: Paste test (3)") ~= nil, "I: and each route", table.concat(M.MenuTexts(), "|"))
    W.pasteBox:ClearFocus()
    every.func()
    local out = W.pasteBox.__text
    CHECK(not out:find("nil", 1, true), "I: no 'nil' for an untitled waypoint (TomTom B18)")
    CHECK(("\n" .. out .. "\n"):find("\n/way #1429 30.00 40.00\n", 1, true) ~= nil, "I: the untitled line, bare", out)
    HAS(out, "/way #1436 45.20 66.80 Decimal commas", "I: a titled line")
    local lines = 0
    for _ in out:gmatch("[^\n]+") do lines = lines + 1 end
    EQ(lines, #O().Export(), "I: one line per waypoint")
    EQ(W.pasteBox.__focus, true, "I: exported text is ready for Ctrl+C")
    HAS(W.result.__text, "exported", "I: and says so")
    Press(W.export)
    M.ClickMenu("Route: Paste test (3)")
    lines = 0
    for _ in W.pasteBox.__text:gmatch("[^\n]+") do lines = lines + 1 end
    EQ(lines, 3, "I: a route exports its stops")
    -- the exported lines read back in
    local count = st:Count()
    W.pasteBox:SetText(out)
    Press(W.import)
    EQ(st:Count(), count, "I: exported lines read back as the same waypoints (no twins)")

    -- Saved pages
    Type(W.pageName, "")
    Press(W.savePage)
    HAS(W.result.__text, "Name the page first", "I: a page needs a name")
    Type(W.pageName, "Elwynn list")
    W.pasteBox:SetText("")
    Press(W.savePage)
    HAS(W.result.__text, "nothing to save", "I: and some text")
    W.pasteBox:SetText("/way 45 66 Saved")
    Press(W.savePage)
    local pages = O().PastePages()
    CHECK(#pages == 1 and pages[1].name == "Elwynn list" and pages[1].text == "/way 45 66 Saved", "I: saved")
    HAS(W.result.__text, "saved", "I: and said so")
    local prow = W.pageRows[1]
    CHECK(prow and M.Visible(prow) and prow.label.__text == "Elwynn list", "I: the page is listed")
    CHECK(not M.Visible(W.pagesEmpty), "I: the empty note goes")
    Press(W.clearText)
    EQ(W.pasteBox.__text, "", "I: Clear text empties the box")
    EQ(#O().PastePages(), 1, "I: and keeps the pages")
    CHECK(Press(prow), "I: a page takes a click")
    EQ(W.pasteBox.__text, "/way 45 66 Saved", "I: and loads")
    EQ(W.pageName.__text, "Elwynn list", "I: with its name")
    CHECK(prow.current, "I: the loaded page is marked")
    Press(W.deletePage)
    EQ(#O().PastePages(), 0, "I: Delete")
    CHECK(M.Visible(W.pagesEmpty), "I: none left says so")
    Press(W.deletePage)
    HAS(W.result.__text, "Pick a page", "I: deleting nothing says so")

    -- Off: the import refuses in words
    DB().EnableOrders = false
    W.pasteBox:SetText("/way 45 66 Off")
    Press(W.import)
    HAS(W.result.__text, "turned off", "I: refused while Orders is off")
    DB().EnableOrders = true
    NOERR("I")
end)

-- ===========================================================================
-- J: places
-- ===========================================================================
Section("J", function()
    Boot({ player = GOLDSHIRE })
    O().OpenManager()
    Tick()
    local W = UIW()
    Press(W.tabs[2])
    EQ(UIS().tab, "PLACES", "J: the Places tab")
    CHECK(M.Visible(W.markPlace) and not M.Visible(W.addHere) and not M.Visible(W.clear), "J: Mark place here instead")
    CHECK(not M.Visible(W.groupStrip), "J: no grouping here")
    EQ(W.listScroll.__points[1].y, -6, "J: the list takes the strip's room")
    HAS(W.listEmpty.__text, "No places yet", "J: an empty list says so")
    EQ(W.markPlace.__text, "Mark place here", "J: label")

    Press(W.markPlace)
    local places = O().Places()
    EQ(#places, 1, "J: Mark place here")
    EQ(places[1].title, "Place 1", "J: named for now")
    EQ(UIS().sel.PLACES.index, 1, "J: selected")
    Tick()
    EQ(W.titleBox.__text, "Place 1", "J: the name, editable")
    EQ(W.kindText.__text, "Place", "J: what it is")
    EQ(Info("Where"), "Elwynn Forest 42.0, 65.5", "J: where")
    EQ(Info("Distance"), "0 yd", "J: how far")
    EQ(Info("Faction"), "Horde", "J: whose")
    HAS(Info("Marked"), "Today, ", "J: when")
    local labels = {}
    for _, key in ipairs({ "go", "rename", "copy", "remove" }) do
        local b = Action(key)
        CHECK(b and M.Visible(b), "J: action " .. key)
        labels[#labels + 1] = b and b.__text or "?"
    end
    EQ(table.concat(labels, ","), "Go there,Rename,Copy /way,Remove", "J: the labels")
    Press(Action("rename"))
    Type(W.titleBox, "Farm")
    Enter(W.titleBox)
    EQ(O().Places()[1].title, "Farm", "J: renamed")
    Press(Action("rename"))
    Type(W.titleBox, "")
    Enter(W.titleBox)
    EQ(O().Places()[1].title, "Farm", "J: a place keeps a name")
    EQ(W.titleBox.__text, "Farm", "J: the box puts it back")

    Press(Action("go"))
    local wp = Store():ByKey("place", "place:farm")
    CHECK(wp and wp.title == "Farm", "J: Go there sets a waypoint on it")
    EQ(Store():Pinned(), wp, "J: with the arrow")
    EQ(W.status.__text, "The arrow points at it now.", "J: and says so")
    Press(Action("copy"))
    EQ(R().ArrowState().copyText, "/way #1429 42.00 65.50 Farm", "J: Copy /way")
    O().RenamePlace(1, "Farm spot")
    Press(Action("copy"))
    EQ(R().ArrowState().copyText, "/way #1429 42.00 65.50 Farm spot", "J: the place as it is now, not as the view saw it")
    O().RenamePlace(1, "Farm")
    Tick()

    -- Another faction's, another zone's
    local list = DB().Places
    list[#list + 1] = { title = "Ironforge bank", map = 1455, x = 0.35, y = 0.60, faction = "Alliance", created = time() - 86400 * 3 }
    M.SetPlayer(1436, 0.5, 0.5)
    Press(W.markPlace)
    M.SetPlayer(1429, 0.42, 0.655)
    Tick()
    local iron = RowBy("Ironforge bank")
    EQ(iron and iron.tag.__text, "Alliance", "J: another faction's place is tagged")
    EQ(iron and iron.sub.__text, "Ironforge 35.0, 60.0", "J: with its place")
    HAS(iron and iron.dist.__text, " yd", "J: and distance")
    EQ(RowBy("Farm").tag.__text, "", "J: your faction's is not")
    Press(iron)
    EQ(Info("Faction"), "Alliance, not yours", "J: the detail says so")
    CHECK(Info("Marked") and not Info("Marked"):find("Today", 1, true), "J: an older date")
    Type(W.search, "iron")
    EQ(#Rows(), 1, "J: search places")
    Escape(W.search)

    -- Remove asks first, and is safe when the list moved meanwhile
    M.ClearLog()
    Press(RowBy("Farm"))
    Press(Action("remove"))
    local pop = LastPopup("COMMANDER_ORDERS_REMOVE_PLACE")
    CHECK(pop and pop.a1 == "Farm", "J: Remove asks, naming it")
    CHECK(pop and M.StrataOver(pop.dialog:GetFrameStrata(), "FULLSCREEN"),
        "J: the question draws over the maximized world map", pop and pop.dialog:GetFrameStrata())
    EQ(#O().Places(), 3, "J: nothing removed before the answer")
    M.ClickPopup("COMMANDER_ORDERS_REMOVE_PLACE", 1)
    EQ(#O().Places(), 2, "J: removed")
    for _, p in ipairs(O().Places()) do CHECK(p.title ~= "Farm", "J: the right one") end
    EQ(UIS().sel.PLACES, nil, "J: the selection goes")
    -- [Ironforge bank, Place 3, Spare]: ask about the second, lose the first
    -- meanwhile; the second's number now belongs to Spare
    DB().Places[#DB().Places + 1] = { title = "Spare", map = 1429, x = 0.5, y = 0.5, created = time() }
    Tick()
    CHECK(Press(RowBy("Place 3")), "J: the Westfall place")
    Press(Action("remove"))
    table.remove(DB().Places, 1)
    M.ClickPopup("COMMANDER_ORDERS_REMOVE_PLACE", 1)
    local left = O().Places()
    CHECK(#left == 1 and left[1].title == "Spare", "J: the named place went, not the one now at its number",
        left[1] and left[1].title)
    NOERR("J")
end)

-- ===========================================================================
-- K: entry points and live updates
-- ===========================================================================
Section("K", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    local st = Store()
    O().UI.OpenPlaces()
    Tick()
    local W = UIW()
    UIS().folded[u.route] = true
    local stopUid = st:GetRoute(u.route).stops[3]
    O().OpenManager(stopUid)
    EQ(UIS().tab, "WAYPOINTS", "K: Open(uid) shows the list")
    EQ(UIS().sel.WAYPOINTS.uid, stopUid, "K: with it selected")
    CHECK(RowBy("Briarthorn") ~= nil and RowBy("Briarthorn").selected, "K: its folded route opened to show it")
    O().OpenManager(u.route)
    EQ(UIS().sel.WAYPOINTS.id, u.route, "K: Open(routeId) selects the route")
    O().OpenManager("w9999")
    EQ(UIS().sel.WAYPOINTS.id, u.route, "K: an unknown uid changes nothing")
    -- a selection far down the list is scrolled into view, a frame later
    -- (the client knows a scroll frame's height only after layout)
    local scroll = W.listScroll
    scroll.__h = 120
    scroll.GetVerticalScrollRange = function() return 600 end
    scroll:SetVerticalScroll(0)
    O().OpenManager(u.tt)
    EQ(scroll:GetVerticalScroll(), 0, "K: not before the layout pass")
    Tick(1)
    CHECK((scroll:GetVerticalScroll() or 0) > 0, "K: Open(uid) scrolls the row into view", scroll:GetVerticalScroll())
    local top = scroll:GetVerticalScroll()
    O().OpenManager(u.north)
    Tick(1)
    CHECK(scroll:GetVerticalScroll() < top, "K: and back up for a row above", scroll:GetVerticalScroll())

    -- A search the target fails is let go of: the detail never shows a
    -- waypoint the list has no row for (review: surfaces)
    Type(W.search, "zzz")
    O().UI.Close()
    O().OpenManager(u.north)
    EQ(UIS().search, "", "K: Open(uid) clears a search its waypoint fails")
    EQ(W.search.__text, "", "K: ...the box too")
    CHECK(RowBy("Northshire Abbey") ~= nil and RowBy("Northshire Abbey").selected, "K: ...and its row shows, selected")
    Type(W.search, "dughan")
    O().OpenManager(u.dughan)
    EQ(UIS().search, "dughan", "K: a search it matches is kept")

    -- The arrow's own click opens the manager on its target
    O().UI.Close()
    local a = R().ArrowState()
    a.hit.__scripts.OnClick(a.hit, "LeftButton")
    CHECK(M.Visible(W.frame), "K: the arrow's click opens the manager")
    EQ(UIS().sel.WAYPOINTS.uid, u.north, "K: on what it points at")

    -- CHANGED: open, the list follows; hidden, it catches up on open
    O().Add({ map = 1429, x = 0.33, y = 0.33, title = "From a consumer", source = "Tradecraft", key = "s:1", setArrow = false })
    Tick()
    CHECK(RowBy("From a consumer") ~= nil, "K: another addon's waypoint appears while open")
    EQ(RowBy("From a consumer").tag.__text, "Tradecraft", "K: tagged with who set it")
    O().UI.Close()
    O().RemoveBy("Tradecraft")
    O().Add({ map = 1429, x = 0.34, y = 0.34, title = "While hidden", setArrow = false })
    Tick()
    EQ(UIS().dirty, true, "K: changes while hidden only mark it stale")
    O().OpenManager()
    CHECK(RowBy("While hidden") ~= nil and RowBy("From a consumer") == nil, "K: caught up on open")
    -- the arrow changing hands moves the Arrow group
    O().SetArrow(u.dughan)
    Tick()
    EQ(RowsUnder("Arrow"), "Marshal Dughan", "K: the Arrow group follows the arrow")
    O().ClearArrow()
    Tick()
    EQ(RowsUnder("Arrow"), "", "K: dismissed, no Arrow group")
    -- the selected waypoint arrives and clears: the detail lets go
    O().UI.Select("wp", u.lion)
    O().Remove(u.lion)
    Tick()
    CHECK(M.Visible(W.detailEmpty), "K: a selection that vanished empties the detail")
    -- Restore Defaults keeps the manager's own keys
    DB().ManagerGroupBy = "SOURCE"
    DB().ManagerPos = { point = "CENTER", x = 1, y = 2 }
    O().DB.Reset()
    EQ(DB().ManagerGroupBy, "SOURCE", "K: Restore Defaults keeps the grouping")
    CHECK(DB().ManagerPos and DB().ManagerPos.x == 1, "K: and the window's place")
    NOERR("K")
end)

-- ===========================================================================
-- L: hygiene
-- ===========================================================================
Section("L", function()
    Boot({ player = GOLDSHIRE })
    local u = Populate()
    local first = #M.writes
    O().OpenManager(u.lion)
    Tick()
    local W = UIW()
    -- visit every view
    O().UI.Select("route", u.route)
    Press(W.tabs[2])
    Press(W.markPlace)
    Press(W.tabs[3])
    W.pasteBox:SetText("/way 45 66 x\nbad")
    Press(W.import)
    Press(W.export)
    Press(W.tabs[1])
    Press(W.clear)
    Tick()
    local DOCUMENTED = {
        CommanderOrdersManager = true, CommanderOrdersManagerListScroll = true, CommanderOrdersManagerPasteScroll = true,
        CommanderOrdersManagerPagesScroll = true, CommanderOrdersManagerSearch = true,
        CommanderOrdersManagerTitleBox = true, CommanderOrdersManagerRouteTitle = true,
        CommanderOrdersManagerPageName = true, CommanderOrdersMenu = true,
    }
    local bad = {}
    for i = first + 1, #M.writes do
        local name = M.writes[i].name
        if not DOCUMENTED[name] and not name:match("^CommanderUIDropDown%d+$") then bad[#bad + 1] = name end
    end
    EQ(#bad, 0, "L: only the documented named frames (" .. table.concat(bad, " ") .. ")")
    local nonAscii, nilText, n = {}, {}, 0
    for _, w in ipairs(M.W.widgets) do
        if Ancestor(w, W.frame) and type(w.__text) == "string" then
            n = n + 1
            if w.__text:find("[\128-\255]") then nonAscii[#nonAscii + 1] = w.__text end
            if w.__text:find("%f[%a]nil%f[%A]") then nilText[#nilText + 1] = w.__text end
        end
    end
    CHECK(n > 40, "L: a fair sample of text", n)
    EQ(#nonAscii, 0, "L: D11: no byte above 127 in any text", nonAscii[1])
    EQ(#nilText, 0, "L: no 'nil' in any text", nilText[1])
    for _, entry in ipairs(M.menu or {}) do
        CHECK(not tostring(entry.text):find("[\128-\255]"), "L: menu text plain", entry.text)
    end
    EQ(#M.blocked, 0, "L: no protected call")
    NOERR("L")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

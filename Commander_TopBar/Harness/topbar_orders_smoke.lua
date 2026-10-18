-- Commander Top Bar: the Commander Orders half (luajit).
--
--     /opt/homebrew/bin/luajit Commander_TopBar/Harness/topbar_orders_smoke.lua
--
-- Runs from the AddOns root, from this folder or from anywhere else: the root
-- is found from this file's own path. Mutation hook: TOPBAR_RUNTIME=/path of a
-- copy of CommanderTopBar.lua to load in its place.
--
-- The Top Bar's coordinates take a click and its optional Nav segment shows
-- where the arrow is going. Both are only as good as what Commander Orders
-- does with them, so this boots the REAL Orders (Data, Geo, Store, DB and the
-- runtime; the pins and the manager are left out, as the runtime's own
-- harness does) over the shared client mock, Commander_Orders/Harness/
-- orders_mock.lua, with the REAL Commander_Events framework, and loads the
-- Top Bar on top the way the client would (OptionalDeps: Orders first).
--
--   A  it loads clean beside Orders; the coordinates show (Orders' reading,
--      at Coordinate Decimals) and take the mouse
--   B  click = a waypoint where you stand (source user, pinned, announced)
--   C  Shift-click = the spot shared in chat as Orders' readable line (your
--      group's chat, else /say) and NO waypoint of your own; Ctrl-click = its
--      /way line in Orders' copy box (2.3.0: Orders' coordinate gestures)
--   D  right-click = Orders' coordinate menu; its last entry opens the
--      manager, at no waypoint
--   E  the Nav segment: the arrow's own distance (582 yd, the D1 walk), an
--      arrival time while walking, the other-landmass words, hidden with no
--      target, refreshed by Orders' CHANGED inside a second
--   F  tooltips: the spot to a tenth, the arrow's line, the three hints
--   G  Orders switched off: a click says so, the Nav segment goes away
--   H  combat changes nothing: the click works and nothing protected is called
--   I  Orders not loaded at all: a click prints the /way line, nothing errors
--   J  the settings page: Waypoint checkbox present, disabled without Orders
--   K  globals: the Top Bar writes only its own two globals and reads only
--      what it means to (a local declared after its use shows up here)
--   L  the supply readouts (2.3.0): durability, bags and ammo go to the
--      nearest repair, vendor and ammo vendor through Orders' locator (a
--      harness resolver stands in for Questie); Go, Shift share, Ctrl copy,
--      the hover card, refusals, the option, Orders off and absent, combat

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")
local TOPBAR = ADDONS .. "/Commander_TopBar"
local LUAJIT = "/opt/homebrew/bin/luajit"

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
-- Booting the Top Bar over Orders
-- ---------------------------------------------------------------------------
local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }

-- The client API the Top Bar's other segments read, at harmless values
local function ClientStubs()
    rawset(_G, "GetMoney", function() return 1234567 end)
    rawset(_G, "UnitXP", function() return 100 end)
    rawset(_G, "UnitXPMax", function() return 1000 end)
    rawset(_G, "GetInventoryItemCount", function() return 0 end)
    rawset(_G, "GetInventoryItemTexture", function() return nil end)
    rawset(_G, "GetInventoryItemDurability", function() return 50, 100 end)
    rawset(_G, "GetNetStats", function() return 0, 0, 42, 42 end)
    rawset(_G, "GetFramerate", function() return 60 end)
    rawset(_G, "C_Container", {
        GetContainerNumSlots = function() return 16 end,
        GetContainerNumFreeSlots = function() return 4 end,
    })
end

local function Boot(opts)
    opts = opts or {}
    local saved = opts.topbar or { ShowCoords = true, ShowNav = true }
    return M.Boot({
        files = opts.noOrders and {} or nil,
        skipFiles = SKIP,
        player = opts.player or GOLDSHIRE,
        saved = opts.saved,
        before = function() ClientStubs() end,
        afterFiles = function(m, w)
            -- The client loads the Top Bar after Orders (OptionalDeps), hands
            -- it its saved variables, then sends its ADDON_LOADED
            w.phase = "topbar"
            for _, file in ipairs({ "CommanderTopBarDB.lua", "CommanderTopBar.lua" }) do
                local path = (file == "CommanderTopBar.lua" and os.getenv("TOPBAR_RUNTIME")) or (TOPBAR .. "/" .. file)
                local chunk, err = loadfile(path)
                if not chunk then
                    m.loadErrors[#m.loadErrors + 1] = file .. ": " .. tostring(err)
                else
                    local ok, runErr = pcall(chunk)
                    if not ok then m.loadErrors[#m.loadErrors + 1] = file .. ": " .. tostring(runErr) end
                end
            end
            local copy = {}
            for k, v in pairs(saved) do copy[k] = v end
            rawset(_G, "CommanderTopBarDB", copy)
            m.Fire("ADDON_LOADED", "Commander_TopBar")
            w.phase = "orders"
        end,
    })
end

-- The bar's regions, found by what they are rather than by a name
local function Bar() return rawget(_G, "CommanderTopBar") end
local function Kids(kind)
    local out = {}
    for _, w in ipairs(Bar().__children) do
        if w.__kind == kind then out[#out + 1] = w end
    end
    return out
end
-- The FontString a click surface is anchored to
local function HitFor(segment)
    for _, hit in ipairs(Kids("Button")) do
        local p = hit.__points and hit.__points[1]
        if p and p.rel == segment then return hit end
    end
    return nil
end
local function SegmentWith(needle)
    for _, fs in ipairs(Kids("FontString")) do
        if M.Visible(fs) and type(fs.__text) == "string" and fs.__text:find(needle, 1, true) then return fs end
    end
    return nil
end
-- The coordinates segment is the one with the grey "nn, nn"; the Nav one
-- carries the map icon
local NAV_ICON = "INV_Misc_Map_01"
local function CoordsSegment() return SegmentWith("|cffc7c7cf42.0, 65.5|r") or SegmentWith(", ") end
local function NavSegment()
    for _, fs in ipairs(Kids("FontString")) do
        if type(fs.__text) == "string" and fs.__text:find(NAV_ICON, 1, true) then return fs end
    end
    return nil
end
local function NavText()
    local fs = NavSegment()
    if not (fs and M.Visible(fs)) then return nil end
    return fs.__text
end

local function Click(hit, button) return M.Click(hit, button or "LeftButton") end
local function ShiftClick(hit)
    M.W.mods.SHIFT = true
    local delivered = M.Click(hit, "LeftButton")
    M.W.mods.SHIFT = false
    return delivered
end
local function Decode(text)
    local v, map, x, y, title = tostring(text):match("^(%d+):(%d+):([%d%.]+):([%d%.]+):(.*)$")
    return tonumber(v), tonumber(map), tonumber(x), tonumber(y), title
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
local function O() return CommanderOrders end

-- ---------------------------------------------------------------------------
-- A  it loads clean beside Orders
-- ---------------------------------------------------------------------------
local hit, coords
Section("A", function()
    Boot()
    NOERR("A: Top Bar over Orders")
    M.Advance(1.05)
    CHECK(Bar() and M.Visible(Bar()), "A: the bar is up")
    coords = CoordsSegment()
    CHECK(coords ~= nil, "A: the coordinates are drawn")
    HAS(coords and coords.__text, "42.0, 65.5", "A: at the player's spot (Goldshire)")
    hit = coords and HitFor(coords)
    CHECK(hit ~= nil, "A: a click surface sits on the coordinates")
    CHECK(hit and M.Visible(hit) and hit.__mouse, "A: shown and taking the mouse")
    CHECK(Bar().__mouse ~= true, "A: the bar itself stays mouse-free (camera drags near the top survive)")
    EQ(NavText(), nil, "A: no waypoint, no Nav segment")
    EQ(#O().List(), 0, "A: Orders starts empty")
end)

-- ---------------------------------------------------------------------------
-- B  click = a waypoint where you stand
-- ---------------------------------------------------------------------------
Section("B", function()
    M.ClearLog()
    CHECK(Click(hit), "B: the click lands")
    local list = O().List()
    EQ(#list, 1, "B: one waypoint")
    local wp = list[1] or {}
    EQ(wp.source, "user", "B: it is the user's own mark (the same as /wayb)")
    EQ(wp.map, 1429, "B: on Elwynn Forest")
    NEAR(wp.x, 0.42, 1e-6, "B: x where you stand")
    NEAR(wp.y, 0.655, 1e-6, "B: y where you stand")
    EQ(wp.persistent, true, "B: it survives a reload, like any mark of yours")
    local active = O().Active()
    EQ(active and active.uid, wp.uid, "B: and the arrow follows it")
    CHECK(M.Has(M.prints, "waypoint set"), "B: Orders says so once", M.prints[1])
    -- A second click on the same spot is the same waypoint, not a pile
    Click(hit)
    EQ(#O().List(), 1, "B: clicking again does not stack a second mark")
    NOERR("B")
end)

-- ---------------------------------------------------------------------------
-- C  Shift-click = the spot shared in chat, with no waypoint of your own;
--    Ctrl-click = its /way line in the copy box (Orders' coordinate gestures)
-- ---------------------------------------------------------------------------
local function CtrlClick(h)
    M.W.mods.CTRL = true
    local delivered = M.Click(h, "LeftButton")
    M.W.mods.CTRL = false
    return delivered
end
Section("C", function()
    O().Clear()
    M.Advance(0.1)
    M.ClearLog()
    ShiftClick(hit)
    EQ(#M.sent, 0, "C: solo, nothing is sent")
    local said = M.chat[#M.chat] or {}
    EQ(said.chatType, "SAY", "C: solo, the spot goes to /say (Orders' share in chat)")
    HAS(said.text, "Elwynn Forest 42.0, 65.5 (/way #1429 42.00 65.50)", "C: as Orders' readable line")
    CHECK(type(said.text) == "string" and said.text:sub(1, 1) ~= "/", "C: never a line that starts with a slash", said.text)
    EQ(#O().List(), 0, "C: and no waypoint appeared")

    M.SetGroup("party", { "Zuljin" })
    M.ClearLog()
    ShiftClick(hit)
    said = M.chat[#M.chat] or {}
    EQ(said.chatType, "PARTY", "C: in a party, to the party's chat")
    HAS(said.text, "/way #1429 42.00 65.50", "C: the /way part where you stand")
    EQ(#O().List(), 0, "C: still no waypoint of your own (the point of sharing)")
    EQ(O().Active(), nil, "C: and the arrow was not pinned at your feet")

    -- A mark of yours at the very same spot is left alone
    O().Here()
    local before = #O().List()
    ShiftClick(hit)
    EQ(#O().List(), before, "C: sharing never removes a waypoint at the same spot")

    M.SetGroup("raid", { "Zuljin", "Rokhan" })
    M.ClearLog()
    ShiftClick(hit)
    EQ(M.chat[#M.chat] and M.chat[#M.chat].chatType, "RAID", "C: in a raid, to the raid")
    M.SetGroup(nil)

    -- Ctrl-click: the /way line, in Orders' copy box
    M.ClearLog()
    CtrlClick(hit)
    local pop = M.popups[#M.popups]
    EQ(pop and pop.which, "COMMANDER_ORDERS_COPY", "C: Ctrl-click opens Orders' copy box")
    HAS(pop and pop.dialog.editBox.__text, "/way #1429 42.00 65.50", "C: ...holding the /way line")
    EQ(#M.chat, 0, "C: ...and posts nothing")
    NOERR("C")
end)

-- ---------------------------------------------------------------------------
-- D  right-click = the coordinate menu, with the waypoint manager in it
-- ---------------------------------------------------------------------------
Section("D", function()
    local opened = "never"
    O().UI = { Open = function(uid) opened = uid end }
    M.menu = {}
    Click(hit, "RightButton")
    local texts = table.concat(M.MenuTexts(), " | ")
    HAS(texts, "Waypoint here", "D: right-click opens Orders' coordinate menu")
    HAS(texts, "Copy /way line", "D: ...with the copy entry")
    CHECK(M.ClickMenu("Open the manager"), "D: ...and the manager entry")
    EQ(opened, nil, "D: right-click opens the manager, at no particular waypoint")
    O().UI = nil
    M.ClearLog()
    Click(hit, "RightButton")
    M.ClickMenu("Open the manager")
    CHECK(M.Has(M.prints, "waypoints"), "D: without the manager file, Orders' chat list stands in", M.prints[1])
    NOERR("D")
end)

-- ---------------------------------------------------------------------------
-- E  the Nav segment
-- ---------------------------------------------------------------------------
Section("E", function()
    Boot()
    M.Advance(1.05)
    -- On a tick boundary, then a change: the CHANGED listener (0.2 s), not
    -- the 1 s tick, has to bring the segment up
    local uid = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    CHECK(uid ~= nil, "E: Northshire set")
    M.Advance(0.4)
    local text = NavText()
    CHECK(text ~= nil, "E: the segment appears inside half a second (CHANGED, not the tick)")
    HAS(text, "Northshire", "E: with the waypoint's title")
    HAS(text, "582 yd", "E: and the arrow's own distance (the D1 walk: 582, never 12,952)")
    local st = O().Status()
    EQ(st and st.mode, "NAV", "E: Status says NAV")
    NEAR(st and st.distance, 582.4, 1.0, "E: Status distance in yards")
    EQ(st and st.distanceText, "582 yd", "E: worded the way the arrow words it")

    -- Walking toward it gives an arrival time
    local _, tn, tw = M.World(1429, 0.48, 0.42)
    Walk(tn, tw, 7, 2.2)
    M.SetSpeed(7)
    M.Advance(1.05)
    text = NavText()
    CHECK(text and (text:find("%d+m %d%ds") or text:find(" %d+s|r")), "E: walking there, an arrival time", text)
    st = O().Status()
    CHECK(st and st.etaText ~= nil and st.eta and st.eta > 0, "E: Status carries the ETA", st and st.etaText)
    M.SetSpeed(0)

    -- Somewhere the arrow cannot point: the arrow's own words
    O().Add({ map = 1944, x = 0.5, y = 0.5, title = "Thrallmar" })
    M.Advance(1.3)
    text = NavText()
    HAS(text, "Thrallmar", "E: the new target's title")
    HAS(text, "in Outland", "E: and where it is, not a fake distance")
    st = O().Status()
    EQ(st and st.mode, "OTHER", "E: Status says OTHER")

    -- The mark that is not shown any more is not described
    O().Clear()
    M.Advance(1.3)
    EQ(NavText(), nil, "E: no waypoint, no segment")
    local navHit = HitFor(NavSegment())
    CHECK(navHit and not M.Visible(navHit), "E: and its click surface went with it")
    EQ(O().Status(), nil, "E: Status is nil with no target")

    -- Title text is somebody else's: an escape in it stays literal
    O().Add({ map = 1429, x = 0.48, y = 0.42, title = "A|cffff0000B" })
    M.Advance(1.3)
    HAS(NavText(), "A||cffff0000B", "E: a | in a title is escaped, never a colour code")

    -- Opt-in: off by default, and off means off
    CommanderTopBarDB.ShowNav = false
    M.Advance(1.05)
    EQ(NavText(), nil, "E: ShowNav off hides it")
    NOERR("E")
end)

-- ---------------------------------------------------------------------------
-- F  tooltips
-- ---------------------------------------------------------------------------
Section("F", function()
    CommanderTopBarDB.ShowNav = true
    M.SetPlayer(GOLDSHIRE[1], GOLDSHIRE[2], GOLDSHIRE[3])    -- E walked away
    O().Clear()
    O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Northshire" })
    M.Advance(1.3)
    local c = CoordsSegment()
    local h = HitFor(c)
    M.Hover(h)
    local lines = table.concat(M.tooltip, "\n")
    HAS(lines, "Elwynn Forest 42.0, 65.5", "F: the spot, named and to a tenth")
    HAS(lines, "Arrow: Northshire", "F: what the arrow is following")
    HAS(lines, "582 yd", "F: and how far")
    HAS(lines, "Click: a waypoint where you stand", "F: hint: click")
    HAS(lines, "Shift-click: share in chat", "F: hint: Shift-click")
    HAS(lines, "Right-click: menu", "F: hint: right-click")

    local navHit = HitFor(NavSegment())
    M.Hover(navHit)
    lines = table.concat(M.tooltip, "\n")
    HAS(lines, "Arrow: Northshire", "F: the Nav tooltip names the waypoint")
    HAS(lines, "Click: waypoint manager", "F: and what a click does")
    local opened = "never"
    O().UI = { Open = function(uid) opened = uid end }
    Click(navHit)
    local st = O().Status()
    EQ(opened, st and st.uid, "F: clicking the Nav segment opens the manager at that waypoint")
    O().UI = nil
    NOERR("F")
end)

-- ---------------------------------------------------------------------------
-- G  Orders switched off
-- ---------------------------------------------------------------------------
Section("G", function()
    CommanderOrdersDB.EnableOrders = false
    Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
    M.Advance(1.05)
    EQ(NavText(), nil, "G: Orders off, no Nav segment")
    M.ClearLog()
    local before = #O().List()
    Click(HitFor(CoordsSegment()))
    EQ(#O().List(), before, "G: a click adds nothing")
    CHECK(M.Has(M.prints, "turned off"), "G: and says Orders is off", M.prints[1])
    CommanderOrdersDB.EnableOrders = true
    Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
    NOERR("G")
end)

-- ---------------------------------------------------------------------------
-- H  combat changes nothing
-- ---------------------------------------------------------------------------
Section("H", function()
    Boot()
    M.Advance(1.05)
    M.SetCombat(true)
    M.Advance(1.05)
    local h = HitFor(CoordsSegment())
    CHECK(h and M.Visible(h) and h.__mouse, "H: in combat the coordinates still take the mouse")
    Click(h)
    EQ(#O().List(), 1, "H: and a click still marks the spot")
    EQ(#M.blocked, 0, "H: nothing protected was attempted", M.blocked[1])
    M.SetCombat(false)
    NOERR("H")
end)

-- ---------------------------------------------------------------------------
-- I  Orders not loaded at all
-- ---------------------------------------------------------------------------
Section("I", function()
    Boot({ noOrders = true })
    NOERR("I: Top Bar alone")
    EQ(rawget(_G, "CommanderOrders"), nil, "I: really no Orders")
    M.Advance(1.05)
    local c = CoordsSegment()
    CHECK(c ~= nil, "I: the coordinates still read")
    local h = c and HitFor(c)
    M.ClearLog()
    Click(h)
    CHECK(M.Has(M.prints, "/way #1429 42.00 65.50"), "I: a click prints the spot as a /way line", M.prints[1])
    M.ClearLog()
    ShiftClick(h)
    CHECK(M.Has(M.prints, "/way #1429"), "I: so does Shift-click", M.prints[1])
    EQ(#M.sent, 0, "I: and nothing is sent")
    M.ClearLog()
    Click(h, "RightButton")
    CHECK(M.Has(M.prints, "not loaded"), "I: right-click says what is missing", M.prints[1])
    EQ(NavText(), nil, "I: no Nav segment without Orders")
    M.Hover(h)
    HAS(table.concat(M.tooltip, "\n"), "/way line", "I: the tooltip says what a click does here")
    NOERR("I")
end)

-- ---------------------------------------------------------------------------
-- J  the settings page
-- ---------------------------------------------------------------------------
local function FindCheck(label)
    for _, w in ipairs(M.W.widgets) do
        if w.__kind == "CheckButton" and w.Text and w.Text.__text == label then return w end
    end
    return nil
end
Section("J", function()
    Boot()
    local box = FindCheck("Waypoint (Commander Orders)")
    CHECK(box ~= nil, "J: the Waypoint checkbox is on the page")
    EQ(CommanderTopBarDB.ShowNav, true, "J: (this boot saved it on)")
    Boot({ topbar = {} })
    EQ(CommanderTopBarDB.ShowNav, false, "J: it ships off: the bar's layout does not change by default")
    EQ(CommanderTopBarDB.ShowCoords, false, "J: and the coordinates ship off, as before")
    Boot({ noOrders = true })
    box = FindCheck("Waypoint (Commander Orders)")
    CHECK(box ~= nil, "J: present without Orders too")
    local panel
    for _, cat in ipairs(M.W.categories) do
        if cat.__panel and cat.__panel._key == "TopBar" then panel = cat.__panel end
    end
    CHECK(panel ~= nil, "J: the Top Bar page registered")
    if panel and panel.Refresh then panel:Refresh() end
    CHECK(box and box.__enabled == false, "J: and disabled there, with Orders absent", box and tostring(box.__enabled))
    NOERR("J")
end)

-- ---------------------------------------------------------------------------
-- K  globals (static: luajit's bytecode names every global a file touches)
-- ---------------------------------------------------------------------------
local ALLOWED_READ = {}
for name in ([[
type tonumber tostring ipairs pairs select pcall print string math table date time
CreateFrame UIParent C_Timer C_Map C_Container C_AddOns GameTooltip IsShiftKeyDown IsControlKeyDown geterrorhandler
GetMoney GetTime UnitXP UnitXPMax UnitLevel GetInventoryItemCount GetInventoryItemTexture
GetInventoryItemDurability GetNetStats GetFramerate
Commander CommanderTopBarDB COMMANDER_TOPBAR_EVENTS COMMANDER_CONSOLE_EVENTS
CommanderConsoleDB CommanderConsole_Colors CommanderOrders COMMANDER_ORDERS_EVENTS _G
]]):gmatch("[%w_]+") do ALLOWED_READ[name] = true end
local ALLOWED_WRITE = { CommanderTopBarDB = true, COMMANDER_TOPBAR_EVENTS = true }

Section("K", function()
    for _, file in ipairs({ "CommanderTopBarDB.lua", "CommanderTopBar.lua" }) do
        local pipe = assert(io.popen(string.format("%q -bl %q 2>/dev/null", LUAJIT, TOPBAR .. "/" .. file)))
        local seen = {}
        for line in pipe:lines() do
            local op, name = line:match("(G[GS]ET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
            if op and not seen[op .. name] then
                seen[op .. name] = true
                if op == "GGET" then
                    CHECK(ALLOWED_READ[name] or ALLOWED_WRITE[name], "K: " .. file .. " reads only what it means to", name)
                else
                    CHECK(ALLOWED_WRITE[name], "K: " .. file .. " writes only its own globals", name)
                end
            end
        end
        pipe:close()
    end
    -- And at run time: the frame name and the panel's slash keys are the
    -- only other names (the framework writes those for every page)
    Boot()
    for _, w in ipairs(M.writes) do
        if w.phase == "topbar" then
            CHECK(ALLOWED_WRITE[w.name] or w.name == "CommanderTopBar", "K: load-time global write", w.name)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- L  the supply readouts go places (2.3.0)
-- ---------------------------------------------------------------------------
local function SegmentWithIcon(needle)
    for _, fs in ipairs(Kids("FontString")) do
        if M.Visible(fs) and type(fs.__text) == "string" and fs.__text:find(needle, 1, true) then return fs end
    end
    return nil
end
local DURABILITY_ICON, BAGS_ICON, AMMO_ICON = "Trade_BlackSmithing", "Button-Backpack-Up", "INV_Ammo_Arrow_02"
local function Supplier(kind)
    -- What Questie's lists would hand Orders' locator, as a registered resolver
    local places = {
        Repair = { { map = 1429, x = 0.43, y = 0.65, title = "Smith Argus", npc = 90001 },
                   { map = 1944, x = 0.56, y = 0.37, title = "Thrallmar Smith", npc = 90003 } },
        Vendor = { { map = 1429, x = 0.425, y = 0.66, title = "Grocer Jan", npc = 90005 } },
    }
    return places[kind]
end
Section("L", function()
    Boot()
    rawset(_G, "GetInventoryItemCount", function(_, slot) if slot == 0 then return 150 end return 0 end)
    rawset(_G, "GetInventoryItemTexture", function(_, slot) if slot == 0 then return "Interface\\Icons\\" .. AMMO_ICON end end)
    O().RegisterResolver("townsfolk", Supplier)
    M.Advance(1.05)
    NOERR("L: boot")
    EQ(CommanderTopBarDB.SupplyClicks, true, "L: Go from the Readouts defaults on")
    local dura = SegmentWithIcon(DURABILITY_ICON)
    local bags = SegmentWithIcon(BAGS_ICON)
    local ammo = SegmentWithIcon(AMMO_ICON)
    CHECK(dura and bags and ammo, "L: (durability, bags and ammo are drawn)")
    local hd, hb, ha = dura and HitFor(dura), bags and HitFor(bags), ammo and HitFor(ammo)
    CHECK(hd and M.Visible(hd) and hd.__mouse, "L: durability takes the mouse, over its text")
    CHECK(hb and M.Visible(hb) and hb.__mouse, "L: so do the bag slots")
    CHECK(ha and M.Visible(ha) and ha.__mouse, "L: and the ammo")

    -- Durability: the nearest repair, through GoTo, worded by Orders; it
    -- takes the arrow from a mark of yours (a Go button asks for it)
    local mine = O().Add({ map = 1429, x = 0.30, y = 0.30, title = "Mine", source = "user" })
    EQ(O().Active() and O().Active().uid, mine, "L: (the arrow is on a mark of yours)")
    M.ClearLog()
    Click(hd)
    local list = O().List({ source = "TopBar" })
    EQ(#list, 1, "L: a click is one waypoint")
    local wp = list[1] or {}
    EQ(wp.key, "repair", "L: ...owned by the Top Bar's repair key")
    EQ(wp.map, 1429, "L: ...at the nearest repair on your landmass")
    NEAR(wp.x, 0.43, 1e-9, "L: ...where it stands")
    EQ(wp.title, "Nearest repair", "L: ...titled by the locator")
    EQ(wp.icon, "VENDOR", "L: ...wearing the vendor pin")
    EQ(O().Active() and O().Active().uid, wp.uid, "L: ...and the arrow is on it")
    CHECK(M.Has(M.prints, "Waypoint set: Nearest repair"), "L: Orders says so once", M.prints[1])
    Click(hd)
    EQ(#O().List({ source = "TopBar" }), 1, "L: clicking again moves the same waypoint")
    O().Remove(mine)

    -- The hover card: where a click goes and the gestures
    M.Hover(hd)
    local lines = table.concat(M.tooltip, "\n")
    HAS(lines, "Durability", "L: the hover card names the readout")
    HAS(lines, "Go to: Nearest repair - Elwynn Forest 43.0, 65.0", "L: ...where a click goes")
    HAS(lines, "The arrow points here now.", "L: ...that the arrow is on it")
    HAS(lines, "Click: Go to the nearest repair", "L: ...the click")
    HAS(lines, "Shift-click: share in chat. Ctrl-click: copy a /way line.", "L: ...and the other gestures")
    -- The card asks the locator once, on the hover, never on the bar's tick
    local asked, baseLocate = 0, O().Locate
    O().Locate = function(...) asked = asked + 1 return baseLocate(...) end
    M.Hover(hd)
    local afterHover = asked
    CHECK(afterHover > 0, "L: (the hover asked the locator)")
    M.Advance(2.1)
    EQ(asked, afterHover, "L: an open supply card is not re-asked every second")
    O().Locate = baseLocate

    -- Shift-click shares the nearest repair in chat, Ctrl-click copies it
    M.ClearLog()
    ShiftClick(hd)
    local said = M.chat[#M.chat] or {}
    EQ(said.chatType, "SAY", "L: Shift-click solo: /say")
    HAS(said.text, "Nearest repair - Elwynn Forest 43.0, 65.0 (/way #1429 43.00 65.00", "L: ...Orders' readable line")
    M.ClearLog()
    M.W.mods.CTRL = true
    M.Click(hd, "LeftButton")
    M.W.mods.CTRL = false
    local pop = M.popups[#M.popups]
    HAS(pop and pop.dialog.editBox.__text, "/way #1429 43.00 65.00 Nearest repair", "L: Ctrl-click: the /way line in the copy box")

    -- Bags: the nearest vendor (the repair vendors count as vendors too)
    Click(hb)
    local v
    for _, w in ipairs(O().List({ source = "TopBar" })) do if w.key == "vendor" then v = w end end
    EQ(v and v.title, "Nearest vendor", "L: the bag slots go to the nearest vendor")
    NEAR(v and v.x, 0.425, 1e-9, "L: ...the grocer, nearer than the smith")

    -- Ammo: nobody known here says why, and the click changes nothing
    M.Hover(ha)
    HAS(table.concat(M.tooltip, "\n"), "Needs Questie to look that up", "L: no ammo vendor known: the card says why")
    local before = #O().List({ source = "TopBar" })
    M.ClearLog()
    Click(ha)
    EQ(#O().List({ source = "TopBar" }), before, "L: ...and a click adds nothing")
    CHECK(M.Has(M.prints, "Needs Questie"), "L: ...but says why, once", M.prints[1])

    -- Orders turned off: a click is refused in Orders' words
    CommanderOrdersDB.EnableOrders = false
    M.ClearLog()
    Click(hd)
    CHECK(M.Has(M.prints, "turned off"), "L: Orders off: the click says so", M.prints[1])
    CommanderOrdersDB.EnableOrders = true

    -- The option off: the readouts never take the mouse
    CommanderTopBarDB.SupplyClicks = false
    M.Advance(1.05)
    CHECK(not M.Visible(hd) and not M.Visible(hb) and not M.Visible(ha), "L: Go from the Readouts off: no click surfaces")
    CommanderTopBarDB.SupplyClicks = true
    M.Advance(1.05)
    CHECK(M.Visible(hd), "L: ...and back on")

    -- Combat: a plain button, nothing protected
    M.SetCombat(true)
    O().Clear()
    Click(hd)
    EQ(#O().List({ source = "TopBar" }), 1, "L: in combat a click still goes")
    EQ(#M.blocked, 0, "L: ...and nothing protected was attempted", M.blocked[1])
    M.SetCombat(false)
    NOERR("L")

    -- Without Orders the readouts are plain text again
    Boot({ noOrders = true })
    M.Advance(1.05)
    local d2 = SegmentWithIcon(DURABILITY_ICON)
    local h2 = d2 and HitFor(d2)
    CHECK(d2 ~= nil and not (h2 and M.Visible(h2)), "L: no Orders: durability takes no mouse")
    NOERR("L: no Orders")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

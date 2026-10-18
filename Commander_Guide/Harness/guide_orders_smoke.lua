-- Commander Guide against the REAL Commander Orders 3.1 (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Guide/Harness/guide_orders_smoke.lua
--     GUIDE_RUNTIME=/path/copy.lua luajit ...     (a mutated CommanderGuide.lua)
--
-- guide_ui_smoke.lua drives the runtime against a recording stand-in for
-- Orders 3.0 (Add and Entrance only), which is what an Orders without GoTo
-- still gets. This harness boots the real thing through
-- Commander_Orders/Harness/orders_mock.lua -- this build's map rows, the real
-- settings framework, Commander.UI.GoButton in its Commander_Events slot and
-- every Orders file, the locator's shipped door table included -- and loads
-- Commander_Guide after Orders' ADDON_LOADED (opts.addons), as the client
-- does for an addon with OptionalDeps: Commander_Orders. DECISIONS D12:
--
--   A  the guide loads beside Orders 3.1; the window's door button is the
--      suite's GoButton, worded "Go to Entrance"
--   B  CommanderGuide_Entrance goes through GoTo with the door query: one
--      waypoint (Guide, entrance:KARAZHAN), both Karazhan doors as Orders'
--      alternatives, the arrow on the NEARER door, Orders' own "Waypoint
--      set" line; a second press is the same waypoint
--   C  the window's button: the same waypoint, lit "Going to Entrance", its
--      tooltip names the door, Shift-click shares the readable line, Ctrl-
--      click copies the /way line; greyed out inside Karazhan and lit again
--      on zoning out
--   D  Orders turned off: one line from Orders with the door and its [Go];
--      the button greys out with Orders' reason
--   E  Orders without its door table (no locator files): the cited table in
--      CommanderGuideData.lua, both doors, through the same GoTo
--   F  every raid the guide carries a door for: Orders' door table answers
--      it by instance id on the zone the guide's cited row names
--   G  Orders not loaded: the button prints the /way line from the table

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label) CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function HAS(s, needle, label) CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, s) end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local SOUTH_DOOR = { 1430, 0.47, 0.76 }       -- Deadwind Pass, beside Karazhan's southern door
local instanceMapID = 0
local GUIDE_FILES = { "CommanderGuideData.lua", "CommanderGuideEngine.lua", "CommanderGuideDB.lua",
    os.getenv("GUIDE_RUNTIME") and "" or "CommanderGuide.lua" }

local function Boot(opts)
    opts = opts or {}
    instanceMapID = 0
    local files = {}
    for _, f in ipairs(GUIDE_FILES) do if f ~= "" then files[#files + 1] = f end end
    local addons = { { name = "Commander_Guide", files = files } }
    local userBefore = opts.before
    opts.before = function(m, w)
        -- The one client call the Orders mock does not model
        rawset(_G, "GetInstanceInfo", function()
            return "", instanceMapID ~= 0 and "raid" or "none", 0, "", 10, 0, false, instanceMapID
        end)
        if userBefore then userBefore(m, w) end
    end
    local userAfter = opts.afterFiles
    opts.afterFiles = function(m, w)
        if os.getenv("GUIDE_RUNTIME") then assert(loadfile(os.getenv("GUIDE_RUNTIME")))() end
        if userAfter then userAfter(m, w) end
    end
    opts.player = opts.player or SOUTH_DOOR
    if opts.orders ~= false then opts.addons = addons end
    opts.orders = nil
    local w = M.Boot(opts)
    M.Frame()
    return w
end

local function O() return rawget(_G, "CommanderOrders") end
local function Printed(needle)
    for i = #M.prints, 1, -1 do
        if tostring(M.prints[i]):find(needle, 1, true) then return tostring(M.prints[i]) end
    end
    return nil
end
local function Tooltip() return table.concat(M.tooltip, "\n") end
local function Dist(map, x1, y1, x2, y2)
    local _, n1, w1 = M.World(map, x1, y1)
    local _, n2, w2 = M.World(map, x2, y2)
    return math.sqrt((n1 - n2) ^ 2 + (w1 - w2) ^ 2)
end

-- ===========================================================================
-- A. Loading beside Orders 3.1
-- ===========================================================================
Section("A", function()
    Boot()
    EQ(#M.loadErrors, 0, "A: Orders and the guide load cleanly", M.loadErrors[1])
    CHECK(type(O()) == "table" and type(O().GoTo) == "function", "A: (Orders 3.1, with GoTo)")
    CHECK(type(Commander.UI.GoButton) == "function", "A: (Commander.UI.GoButton is there)")
    CHECK(CommanderGuide_Show("KARAZHAN", "MOROES"), "A: the window opens on Karazhan")
    local f = CommanderGuideFrame
    local b = f and f.entrance
    CHECK(b ~= nil and f.entranceIsGo == true, "A: the window's door button is the suite's GoButton")
    EQ(b and b.__text, "Go to Entrance", "A: worded Go to Entrance")
    EQ(BINDING_NAME_COMMANDERGUIDE_ENTRANCE, "Go to the raid's entrance", "A: the binding's words")
    EQ(b and b:IsEnabled(), true, "A: live outside the raid")
    EQ(#M.errors, 0, "A: no errors", M.errors[1])
end)

-- ===========================================================================
-- B. CommanderGuide_Entrance through GoTo
-- ===========================================================================
Section("B", function()
    Boot()
    M.ClearLog()
    local ok, uid = CommanderGuide_Entrance("KARAZHAN")
    EQ(ok, true, "B: Orders took it")
    local wp = O().R.Store():ByKey("Guide", "entrance:KARAZHAN")
    CHECK(wp ~= nil and wp.uid == uid, "B: one waypoint owned (Guide, entrance:KARAZHAN)", uid)
    EQ(wp and wp.title, "Karazhan entrance", "B: titled for the raid")
    EQ(wp and wp.alternatives and #wp.alternatives, 2, "B: both Karazhan doors, from Orders' door table")
    -- Orders' doors, not the guide's cited copy (the two differ: Orders ships
    -- the AreaTrigger portals, the guide Questie's spots)
    local door = O().Entrance({ instance = 532 })
    local doors = { door }
    for _, a in ipairs(door and door.alternatives or {}) do doors[#doors + 1] = a end
    local matched = 0
    for _, a in ipairs(wp and wp.alternatives or {}) do
        for _, d in ipairs(doors) do
            if a.map == d.map and math.abs(a.x - d.x) < 1e-6 and math.abs(a.y - d.y) < 1e-6 then matched = matched + 1; break end
        end
    end
    EQ(matched, 2, "B: ...the very doors CommanderOrders.Entrance({ instance = 532 }) answers")
    local cited = CommanderGuide_Data.ENTRANCES[532].points[1]
    CHECK(not (math.abs(wp.x - cited.x) < 1e-6 and math.abs(wp.y - cited.y) < 1e-6) or matched == 2,
        "B: (the guide's own table is the fallback, not the answer)")
    EQ(O().Active() and O().Active().uid, uid, "B: it has the arrow")
    HAS(Printed("Waypoint set: Karazhan entrance"), "Waypoint set: Karazhan entrance", "B: Orders' own success line")
    CHECK(Printed("Commander Guide:") == nil, "B: and no second line of the guide's own")
    M.Advance(1.2)
    local view = O().R.View()
    EQ(view.mode, "NAV", "B: the arrow navigates")
    -- The two doors Orders knows, and the nearer one from the southern spot
    local alts = wp and wp.alternatives or {}
    local nearest
    for _, a in ipairs(alts) do
        local d = Dist(a.map, SOUTH_DOOR[2], SOUTH_DOOR[3], a.x, a.y)
        if not nearest or d < nearest then nearest = d end
    end
    CHECK(nearest and math.abs(view.distance - nearest) < 1.0, "B: ...to the NEARER door",
        tostring(view.distance) .. " vs " .. tostring(nearest))
    local again = select(2, CommanderGuide_Entrance("KARAZHAN"))
    EQ(again, uid, "B: a second press is the same waypoint")
    EQ(#O().List({ source = "Guide" }), 1, "B: never two")
    EQ(#M.errors, 0, "B: no errors", M.errors[1])
end)

-- ===========================================================================
-- C. The window's GoButton
-- ===========================================================================
Section("C", function()
    Boot()
    CommanderGuide_Show("KARAZHAN", "MOROES")
    local b = CommanderGuideFrame.entrance
    M.ClearLog()
    CHECK(M.Click(b), "C: a click")
    local wp = O().R.Store():ByKey("Guide", "entrance:KARAZHAN")
    CHECK(wp ~= nil and wp.alternatives and #wp.alternatives == 2, "C: the click is the same Go: one waypoint, both doors")
    EQ(wp and wp.title, "Karazhan entrance", "C: titled for the raid")
    EQ(b.__text, "Going to Entrance", "C: lit while the arrow is on the door")
    CommanderGuide_Entrance("KARAZHAN")
    EQ(#O().List({ source = "Guide" }), 1, "C: the button and the slash word share one waypoint")
    M.Hover(b)
    local tip = Tooltip()
    HAS(tip, "Go to: Karazhan entrance - Deadwind Pass", "C: the tooltip names the door and its zone")
    HAS(tip, "Shift-click: share in chat. Ctrl-click: copy a /way line.", "C: ...and the clicks")
    HAS(tip, "Karazhan's entrance in Deadwind Pass", "C: ...and the guide's own sentence")
    -- Shift: the readable line in chat; Ctrl: the /way line
    M.SetModifier("SHIFT", true)
    M.Click(b)
    M.SetModifier("SHIFT", false)
    local said = M.chat[#M.chat]
    HAS(said and said.text, "Karazhan entrance - Deadwind Pass ", "C: Shift-click shares the door, readable")
    HAS(said and said.text, "(/way #1430 ", "C: ...with its /way line for players without addons")
    M.SetModifier("CTRL", true)
    M.Click(b)
    M.SetModifier("CTRL", false)
    local pop = M.popups[#M.popups]
    EQ(pop and pop.which, "COMMANDER_ORDERS_COPY", "C: Ctrl-click opens Orders' copy box")
    HAS(pop and pop.dialog.editBox.__text, "/way #1430 ", "C: ...with the door's /way line")
    -- Inside Karazhan the door is behind you
    instanceMapID = 532
    M.Fire("PLAYER_ENTERING_WORLD")
    EQ(b:IsEnabled(), false, "C: greyed out inside Karazhan")
    M.Hover(b)
    HAS(Tooltip(), "inside Karazhan", "C: ...saying why")
    HAS(Tooltip(), "You are already inside", "C: ...its red line the guide's own reason (GoButton nil, reason)")
    CHECK(not Tooltip():find("No known location", 1, true), "C: ...not Orders' generic no-place line", Tooltip())
    local ok, why = CommanderGuide_Entrance()
    CHECK(ok == false and why == "inside", "C: and the slash word refuses there too", why)
    instanceMapID = 0
    M.Fire("PLAYER_ENTERING_WORLD")
    EQ(b:IsEnabled(), true, "C: zoning out lights it again")
    EQ(#M.errors, 0, "C: no errors", M.errors[1])
end)

-- ===========================================================================
-- D. Orders turned off
-- ===========================================================================
Section("D", function()
    Boot()
    CommanderGuide_Show("KARAZHAN", "MOROES")
    local b = CommanderGuideFrame.entrance
    CommanderOrdersDB.EnableOrders = false
    Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
    M.ClearLog()
    local ok, why = CommanderGuide_Entrance("KARAZHAN")
    CHECK(ok == false and why == "disabled", "D: refused, with Orders' reason", why)
    local line = Printed("Commander Orders is turned off (/corder)")
    HAS(line, "Karazhan entrance (Deadwind Pass", "D: Orders' one line names the door")
    HAS(line, "|Haddon:CommanderOrders:w:1430:", "D: ...and carries its [Go] link")
    local count = 0
    for _, l in ipairs(M.prints) do if tostring(l):find("turned off", 1, true) then count = count + 1 end end
    EQ(count, 1, "D: one line, not two")
    EQ(b:IsEnabled(), false, "D: the button greys out")
    M.Hover(b)
    HAS(Tooltip(), "Commander Orders is turned off (/corder)", "D: ...with Orders' reason")
    CommanderOrdersDB.EnableOrders = true
    Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE)
    EQ(b:IsEnabled(), true, "D: back on, back live")
    EQ(#M.errors, 0, "D: no errors", M.errors[1])
end)

-- ===========================================================================
-- E. Orders without its door table: the guide's cited table
-- ===========================================================================
Section("E", function()
    Boot({ skipFiles = { CommanderOrdersLocate = true, CommanderOrdersEntrances = true } })
    M.ClearLog()
    local ok = CommanderGuide_Entrance("KARAZHAN")
    EQ(ok, true, "E: Orders still takes the door")
    local wp = O().R.Store():ByKey("Guide", "entrance:KARAZHAN")
    local D = CommanderGuide_Data
    local row = D.ENTRANCES[532]
    CHECK(wp and wp.map == row.points[1].map and math.abs(wp.x - row.points[1].x) < 1e-9,
        "E: from the guide's own table (the first door)", wp and (tostring(wp.map) .. " " .. tostring(wp.x)))
    EQ(wp and wp.alternatives and #wp.alternatives, 2, "E: ...with both doors")
    HAS(Printed("Waypoint set: Karazhan entrance"), "Waypoint set: Karazhan entrance", "E: worded by Orders")
    CommanderGuide_Show("KARAZHAN", "MOROES")
    EQ(CommanderGuideFrame.entrance:IsEnabled(), true, "E: the button is live on the table alone")
    instanceMapID = 532
    M.Fire("PLAYER_ENTERING_WORLD")
    EQ(CommanderGuideFrame.entrance:IsEnabled(), false, "E: ...and greyed out inside Karazhan all the same")
    instanceMapID = 0
    M.Fire("PLAYER_ENTERING_WORLD")
    EQ(#M.errors, 0, "E: no errors", M.errors[1])
end)

-- ===========================================================================
-- F. Every raid door the guide knows, answered by Orders' door table
-- ===========================================================================
Section("F", function()
    Boot()
    local D = CommanderGuide_Data
    local n = 0
    for id, row in pairs(D.ENTRANCES) do
        n = n + 1
        local e = O().Entrance({ instance = id })
        CHECK(type(e) == "table" and e.map == row.points[1].map,
            "F: Orders' door for " .. row.title .. " is on " .. row.zone,
            e and (tostring(e.map) .. " vs " .. tostring(row.points[1].map)))
    end
    EQ(n, 9, "F: (all nine TBC raids)")
    EQ(#M.errors, 0, "F: no errors", M.errors[1])
end)

-- ===========================================================================
-- G. Orders not loaded
-- ===========================================================================
Section("G", function()
    Boot({ files = {} })
    CHECK(O() == nil, "G: (Orders not loaded)")
    CommanderGuide_Show("KARAZHAN", "MOROES")
    local b = CommanderGuideFrame.entrance
    EQ(b:IsEnabled(), true, "G: the button still does something")
    M.ClearLog()
    M.Click(b)
    HAS(Printed("/way #1430 46.70 70.20 Karazhan entrance"), "/way #1430 46.70 70.20 Karazhan entrance",
        "G: a click prints the door's /way line")
    M.ClearLog()
    local ok, why = CommanderGuide_Entrance("KARAZHAN")
    CHECK(ok == false and why == "absent", "G: the slash word too", why)
    HAS(Printed("/way #1430 46.70 70.20 Karazhan entrance"), "Karazhan entrance", "G: ...printing the same line")
    EQ(#M.errors, 0, "G: no errors", M.errors[1])
end)

io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

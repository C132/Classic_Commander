-- Commander.UI.GoButton smoke (luajit):
--     luajit Commander_Events/Harness/gobutton_smoke.lua
--
-- Commander_Events/CommanderGoButton.lua, the one "Go to" button every
-- Commander module uses (Commander Orders 3.1, SPEC 1), driven over the
-- client mock Commander Orders' harnesses share (Commander_Orders/Harness/
-- orders_mock.lua), which loads the real settings framework, this file in
-- its TOC slot and the real Orders. Sections:
--   A  the file alone: it loads, writes no global but Commander
--   B  with Orders: click = GoTo under (source, key), the lit "Going" state
--      and its refresh on CHANGED, Shift-click shares the readable line,
--      Ctrl-click the /way line, the tooltip, disabled while Orders is off or
--      the spec answers nothing, a query through Locate, onGo
--   C  without Orders: a spec still prints its /way line, a query greys out
--      saying it needs Commander Orders
--   (B, C and E also: greyed by Orders' own state, off, absent or loading,
--      the module's extra tooltip line is left out; review-r2)
--   D  hygiene: no protected call, no error, plain ASCII words

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")
local FILE = ADDONS .. "/Commander_Events/CommanderGoButton.lua"

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
local function HAS(s, needle, label)
    CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, "got " .. tostring(s))
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

-- Orders without the files the other 3.1 agents own, so this answers for
-- the button and the runtime alone
local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true, CommanderOrdersLocate = true,
               CommanderOrdersCoords = true, CommanderOrdersChat = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }

local function O() return CommanderOrders end
local function DB() return CommanderOrdersDB end
local function Notify() Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE) end
local function Tooltip() return table.concat(M.tooltip, "\n") end
local function Plain(s) return type(s) == "string" and not s:find("[\128-\255]") end

-- ===========================================================================
-- A  the file alone
-- ===========================================================================
Section("A", function()
    local chunk, err = loadfile(FILE)
    CHECK(chunk ~= nil, "A: the file compiles", err)
    if not chunk then return end
    local writes = {}
    local env = setmetatable({}, {
        __index = function(_, k) return rawget(_G, k) end,
        __newindex = function(t, k, v) writes[#writes + 1] = tostring(k); rawset(t, k, v) end,
    })
    setfenv(chunk, env)
    local ok, runErr = pcall(chunk)
    CHECK(ok, "A: it runs with nothing else loaded", runErr)
    EQ(table.concat(writes, ","), "Commander", "A: the only global it writes is Commander")
    local ui = rawget(env, "Commander") and rawget(env, "Commander").UI
    EQ(type(ui and ui.GoButton), "function", "A: Commander.UI.GoButton")
    EQ(ui and ui.GoRowHint, "Ctrl+Right-click: Go", "A: Commander.UI.GoRowHint")
    EQ(type(ui and ui.RefreshGoButtons), "function", "A: Commander.UI.RefreshGoButtons")
    local toc = io.open(ADDONS .. "/Commander_Events/Commander_Events.toc"):read("*a")
    HAS(toc, "CommanderSettingsUI.lua\nCommanderGoButton.lua\nCommanderEvents.lua", "A: listed in the TOC after the settings framework")
end)

-- ===========================================================================
-- B  with Orders
-- ===========================================================================
Section("B", function()
    M.Boot({ player = GOLDSHIRE, skipFiles = SKIP })
    EQ(#M.loadErrors, 0, "B: (a clean boot)", M.loadErrors[1])
    local UI = Commander.UI
    EQ(type(UI.GoButton), "function", "B: the mock loads the button in its TOC slot")
    local spec = { map = 1429, x = 0.48, y = 0.42, title = "Northshire" }
    local gone = {}
    local b = UI.GoButton(UIParent, {
        label = "Go to Northshire", spec = function() return spec end,
        source = "QuestLog", key = "quest:1", icon = "QUEST",
        onGo = function(uid, why) gone[#gone + 1] = { uid = uid, why = why } end,
    })
    EQ(b.__text, "Go to Northshire", "B: the label")
    EQ(b:IsEnabled(), true, "B: enabled")
    EQ(b.__mouse, true, "B: takes the mouse")
    CHECK((b.__w or 0) > 60 and b.__h == 22, "B: sized to its label", b.__w)

    M.ClearLog()
    CHECK(M.Click(b), "B: a click")
    local wp = O().R.Store():ByKey("QuestLog", "quest:1")
    CHECK(wp and wp.map == 1429 and wp.icon == "QUEST" and wp.title == "Northshire", "B: click = GoTo under (source, key)")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "B: the arrow follows it")
    EQ(gone[1] and gone[1].uid, wp and wp.uid, "B: onGo hears the uid")
    CHECK(M.Has(M.prints, "Waypoint set: Northshire"), "B: Orders says Waypoint set", M.prints[1])
    EQ(b.__text, "Going to Northshire", "B: lit while the arrow follows it")

    -- CHANGED relabels it
    local other = O().Add({ map = 1429, x = 0.3, y = 0.3, title = "Elsewhere" })
    M.Frame()
    EQ(O().Active() and O().Active().uid, other, "B: (the arrow moved on)")
    EQ(b.__text, "Go to Northshire", "B: ...and the button went back on CHANGED")
    M.Click(b)
    EQ(b.__text, "Going to Northshire", "B: a second click takes the arrow back")

    -- Shift: the readable line in chat; Ctrl: the /way line in the copy box
    M.ClearLog()
    M.SetModifier("SHIFT", true)
    M.Click(b)
    M.SetModifier("SHIFT", false)
    local said = M.chat[#M.chat]
    EQ(said and said.text, "Northshire - Elwynn Forest 48.0, 42.0 (/way #1429 48.00 42.00)", "B: Shift-click shares the readable line")
    EQ(said and said.chatType, "SAY", "B: ...in /say when alone")
    M.SetGroup("party", { "Bob" })
    M.SetModifier("SHIFT", true)
    M.Click(b)
    M.SetModifier("SHIFT", false)
    EQ(M.chat[#M.chat] and M.chat[#M.chat].chatType, "PARTY", "B: ...in the group's chat when grouped")
    M.SetGroup(nil, {})
    M.SetModifier("CTRL", true)
    M.Click(b)
    M.SetModifier("CTRL", false)
    local pop = M.popups[#M.popups]
    EQ(pop and pop.which, "COMMANDER_ORDERS_COPY", "B: Ctrl-click opens the copy box")
    EQ(pop and pop.dialog.editBox.__text, "/way #1429 48.00 42.00 Northshire", "B: ...with the /way line")

    -- the tooltip
    M.Hover(b)
    local tip = Tooltip()
    HAS(tip, "Go to Northshire", "B: tooltip: the button's words")
    HAS(tip, "Go to: Northshire - Elwynn Forest 48.0, 42.0", "B: tooltip: where")
    HAS(tip, "Shift-click: share in chat. Ctrl-click: copy a /way line.", "B: tooltip: the clicks")
    HAS(tip, "The arrow points here now.", "B: tooltip: lit")
    EQ(M.tooltip.owner, nil, "B: (no stray field)")

    -- disabled while Orders is off, with the reason
    DB().EnableOrders = false
    Notify()
    EQ(b:IsEnabled(), false, "B: Orders off: greyed")
    EQ(b.__text, "Go to Northshire", "B: ...and not lit")
    M.Hover(b)
    HAS(Tooltip(), "Commander Orders is turned off (/corder)", "B: ...the reason in the tooltip")
    -- review-r2: greyed by Orders' state, a module's line about what a press
    -- does is left out (the greyed button takes no press)
    local PROMISE = "A press prints the place in chat."
    local promise = UI.GoButton(UIParent, { label = "Go", spec = spec, source = "Test", key = "promise",
        tooltip = function() return PROMISE end })
    EQ(promise:IsEnabled(), false, "B: (a second button, greyed with Orders off)")
    M.Hover(promise)
    CHECK(not Tooltip():find(PROMISE, 1, true), "B: Orders off: the module's line about a press is left out", Tooltip())
    HAS(Tooltip(), "Commander Orders is turned off (/corder)", "B: ...the red reason alone says why")
    DB().EnableOrders = true
    Notify()
    EQ(b:IsEnabled(), true, "B: on again")
    M.Hover(promise)
    HAS(Tooltip(), PROMISE, "B: ...on again, the module's line is back")

    -- a spec that answers nothing
    local empty = UI.GoButton(UIParent, { label = "Go", spec = function() return nil end, source = "Test", width = 50 })
    EQ(empty:IsEnabled(), false, "B: no place: greyed")
    EQ(empty.__w, 50, "B: an explicit width")
    M.Hover(empty)
    HAS(Tooltip(), "No known location", "B: ...saying so")

    -- a query: through Locate (the stand-in first, then a real answer)
    local q = UI.GoButton(UIParent, { label = "Go", query = { townsfolk = "Innkeeper" }, source = "Test", key = "inn",
        title = "Nearest inn", onGo = function(uid, why) gone[#gone + 1] = { uid = uid, why = why } end })
    EQ(q:IsEnabled(), true, "B: a query is enabled with Orders on")
    M.ClearLog()
    M.Click(q)
    HAS(M.prints[1], "Commander Orders is still loading", "B: before the locator: Orders' one refusal line")
    EQ(gone[#gone].why, "loading", "B: ...and onGo hears why")
    CommanderOrders.Locate = function()
        return { { map = 1429, x = 0.70, y = 0.70, title = "Far inn" }, { map = 1429, x = 0.43, y = 0.66, title = "Lion's Pride" } }
    end
    M.Click(q)
    local inn = O().R.Store():ByKey("Test", "inn")
    CHECK(inn and #inn.alternatives == 2 and math.abs(inn.x - 0.43) < 1e-9 and inn.title == "Nearest inn",
        "B: a query: one waypoint, nearest first, the button's title")
    EQ(q.__text, "Going", "B: Go lit is Going")
    M.Hover(q)
    HAS(Tooltip(), "Go to: Nearest inn - Elwynn Forest 43.0, 66.0", "B: a query's tooltip names the nearest")
    M.SetModifier("CTRL", true)
    M.Click(q)
    M.SetModifier("CTRL", false)
    EQ(M.popups[#M.popups].dialog.editBox.__text, "/way #1429 43.00 66.00 Nearest inn", "B: Ctrl-click copies the nearest")

    -- a plain-table spec, and a button on a frame that is shown later
    local holder = M.NewWidget("Frame", nil, UIParent)
    holder:Hide()
    local t = UI.GoButton(holder, { spec = { map = 1429, x = 0.5, y = 0.5 }, source = "Test", key = "t" })
    EQ(t.__text, "Go", "B: the default label is Go")
    O().GoTo({ map = 1429, x = 0.5, y = 0.5 }, { source = "Test", key = "t", silent = true })
    M.Frame()
    EQ(t.__text, "Go", "B: a button under a hidden frame is not refreshed")
    holder:Show()
    t:Refresh()
    EQ(t.__text, "Going", "B: b:Refresh()")
    O().Add({ map = 1429, x = 0.31, y = 0.3, title = "Away" })
    t:Hide()
    M.Frame()
    EQ(t.__text, "Going", "B: (hidden, still the old words)")
    t:Show()
    EQ(t.__text, "Go", "B: its OnShow refreshes it")
    EQ(#M.errors, 0, "B: no errors", M.errors[1])
end)

-- ===========================================================================
-- C  without Orders
-- ===========================================================================
Section("C", function()
    M.Boot({ player = GOLDSHIRE, files = {} })
    EQ(rawget(_G, "CommanderOrders"), nil, "C: (no Orders)")
    local UI = Commander.UI
    local b = UI.GoButton(UIParent, { label = "Go to Northshire", spec = { map = 1429, x = 0.48, y = 0.42 },
        title = "Northshire", source = "QuestLog", key = "quest:1" })
    EQ(b:IsEnabled(), true, "C: a spec still goes")
    M.ClearLog()
    M.Click(b)
    EQ(M.prints[1], "Commander: /way #1429 48.00 42.00 Northshire (Commander Orders is not loaded)",
        "C: click prints the /way line")
    M.SetModifier("SHIFT", true)
    M.Click(b)
    M.SetModifier("SHIFT", false)
    EQ(#M.chat, 0, "C: Shift-click sends nothing without Orders")
    HAS(M.prints[#M.prints], "/way #1429 48.00 42.00 Northshire", "C: ...it prints the line")
    M.Hover(b)
    HAS(Tooltip(), "Go to: Northshire - Elwynn Forest 48.0, 42.0", "C: the tooltip still says where")
    local q = UI.GoButton(UIParent, { label = "Go", query = { townsfolk = "Innkeeper" }, source = "Test",
        tooltip = "Points the arrow at the nearest inn." })
    EQ(q:IsEnabled(), false, "C: a query greys out")
    M.Hover(q)
    HAS(Tooltip(), "Needs Commander Orders", "C: ...saying it needs Commander Orders")
    CHECK(not Tooltip():find("Points the arrow", 1, true), "C: ...without the module's line about a press", Tooltip())
    local s = UI.GoButton(UIParent, { label = "Go", spec = { map = 1429, x = 0.48, y = 0.42 }, source = "Test",
        tooltip = "Prints a /way line (Commander Orders is not loaded)." })
    M.Hover(s)
    HAS(Tooltip(), "Prints a /way line", "C: an enabled spec without Orders keeps the module's line")
    EQ(#M.errors, 0, "C: no errors", M.errors[1])
end)

-- ===========================================================================
-- D  hygiene
-- ===========================================================================
Section("D", function()
    EQ(#M.blocked, 0, "D: no protected call")
    local src = io.open(FILE):read("*a")
    CHECK(Plain(src), "D: plain ASCII source (no glyphs, suite D11)")
    CHECK(not src:find("SecureActionButtonTemplate", 1, true) and not src:find("SecureHandler", 1, true),
        "D: never secure")
end)

-- ===========================================================================
-- E  integration fixes (the consumers' asks): a query's own title in the
--    tooltip, a spec / query function's reason, a button made before Orders
--    loaded still hears CHANGED
-- ===========================================================================
Section("E", function()
    M.Boot({ player = GOLDSHIRE, skipFiles = SKIP })
    local UI = Commander.UI
    CommanderOrders.Locate = function()
        return { { map = 1429, x = 0.70, y = 0.70, title = "Far inn" },
                 { map = 1429, x = 0.43, y = 0.66, title = "Lion's Pride" }, title = "Nearest innkeeper" }
    end
    local q = UI.GoButton(UIParent, { label = "Go", query = { townsfolk = "Innkeeper" }, source = "Test", key = "inn" })
    M.Hover(q)
    HAS(Tooltip(), "Go to: Nearest innkeeper - Elwynn Forest 43.0, 66.0",
        "E: a query without a title of its own is named by the list Orders found")

    -- nil, reason from the spec function: an Orders code, worded by Orders
    local inside = UI.GoButton(UIParent, { label = "Go to Entrance", source = "Test", key = "door",
        spec = function() return nil, "instance" end })
    EQ(inside:IsEnabled(), false, "E: a spec answering nil, reason: greyed")
    M.Hover(inside)
    HAS(Tooltip(), "No position inside instances", "E: ...Orders' words for the code in the tooltip")
    CHECK(not Tooltip():find("No known location", 1, true), "E: ...not the generic no-place line", Tooltip())
    -- a reason of the spec's own keeps the module's line (it may explain it)
    local why = UI.GoButton(UIParent, { label = "Go to Farm", source = "Test", key = "farm",
        spec = function() return nil end, tooltip = "Needs a running farm." })
    M.Hover(why)
    HAS(Tooltip(), "Needs a running farm.", "E: a spec's own reason keeps the module's line")
    HAS(Tooltip(), "No known location", "E: ...beside the red reason")
    M.ClearLog()
    EQ(M.Click(inside), false, "E: ...a greyed button takes no click (the client's rule): the tooltip says why")
    EQ(#M.prints, 0, "E: ...so nothing is printed")
    -- review (consistency): 2.5.6 runs a disabled Button's OnEnter only with
    -- motion scripts on; without it no player ever saw the red reason
    EQ(inside.__motionWhileDisabled, true, "E: every Go button runs its motion scripts while disabled")
    inside:SetMotionScriptsWhileDisabled(false)
    M.ClearLog()
    EQ(M.Hover(inside), false, "E: (without them the client shows a greyed button no tooltip)")
    inside:SetMotionScriptsWhileDisabled(true)
    -- review (consistency): an ENABLED query whose lookup answers nothing
    -- says Orders' reason in red, not "Go to:" with clicks that only print it
    local lookup = CommanderOrders.Locate
    CommanderOrders.Locate = function() return nil, "notready" end
    local waiting = UI.GoButton(UIParent, { label = "Go to Bank", source = "Test", key = "bank",
        query = { townsfolk = "Banker" } })
    EQ(waiting:IsEnabled(), true, "E: a query is enabled while its lookup waits (a click asks again)")
    M.Hover(waiting)
    HAS(Tooltip(), "Questie is still loading", "E: ...its tooltip says why it names no place")
    CHECK(not Tooltip():find("Go to:", 1, true), "E: ...with no \"Go to:\" line", Tooltip())
    CHECK(not Tooltip():find("Shift-click", 1, true), "E: ...and no click hints", Tooltip())
    CommanderOrders.Locate = lookup
    -- or a sentence of the module's own, from a query function
    local own = UI.GoButton(UIParent, { label = "Go", source = "Test", key = "own",
        query = function() return nil, "The door is behind you" end })
    M.Hover(own)
    HAS(Tooltip(), "The door is behind you", "E: a query function's own sentence")
    -- a spec function's reason does not hide a query that answers
    local both = UI.GoButton(UIParent, { label = "Go", source = "Test", key = "both",
        spec = function() return nil, "instance" end, query = { townsfolk = "Innkeeper" } })
    EQ(both:IsEnabled(), true, "E: ...a query still answers after a spec's reason")
    EQ(#M.errors, 0, "E: no errors", M.errors[1])

    -- a button made before Orders loaded (a module sorted before
    -- Commander_Orders without it in OptionalDeps)
    M.Boot({ player = GOLDSHIRE, files = {} })
    local early = Commander.UI.GoButton(UIParent, { label = "Go to Bank", spec = { map = 1429, x = 0.5, y = 0.5 },
        source = "Early", key = "bank" })
    EQ(early.__text, "Go to Bank", "E: (made with no Orders)")
    local going = true
    rawset(_G, "COMMANDER_ORDERS_EVENTS", { CHANGED = "COMMANDER_ORDERS_CHANGED", UPDATE = "COMMANDER_ORDERS_UPDATE" })
    rawset(_G, "CommanderOrders", {
        GoTo = function() return "w1" end, IsAvailable = function() return true end,
        IsGoing = function(source, key) return going and source == "Early" and key == "bank" end,
        Reason = function(why) return tostring(why) end,
    })
    early:Hide()
    early:Show()
    EQ(early.__text, "Going to Bank", "E: Orders arrived: its OnShow refreshes it")
    going = false
    Commander.Notify("COMMANDER_ORDERS_CHANGED")
    EQ(early.__text, "Go to Bank", "E: ...and from then on it hears CHANGED")
    -- Orders still loading: greyed, the module's line about a press left out
    local loading = Commander.UI.GoButton(UIParent, { label = "Go", spec = { map = 1429, x = 0.5, y = 0.5 },
        source = "Early", key = "load", tooltip = "Points the arrow there." })
    CommanderOrders.IsAvailable = function() return false, "loading" end
    CommanderOrders.FormatCoords = function(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end
    loading:Refresh()
    EQ(loading:IsEnabled(), false, "E: Orders loading: greyed")
    M.Hover(loading)
    HAS(Tooltip(), "loading", "E: ...the reason in red")
    CHECK(not Tooltip():find("Points the arrow there.", 1, true), "E: ...without the module's line about a press",
        Tooltip())
    rawset(_G, "CommanderOrders", nil)
    rawset(_G, "COMMANDER_ORDERS_EVENTS", nil)
    EQ(#M.errors, 0, "E: no errors after the late Orders", M.errors[1])
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

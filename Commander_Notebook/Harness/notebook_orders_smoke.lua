-- Commander Notebook + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Notebook/Harness/notebook_orders_smoke.lua
--     NOTEBOOK_UI=/tmp/mutant.lua luajit ...         (a mutated CommanderNotebookUI.lua)
--
-- notebook_ui_harness.lua section L drives a stamp's way back against a
-- recording stand-in for Orders. This boots the real Orders over the client
-- mock its own harnesses share (Commander_Orders/Harness/orders_mock.lua:
-- this build's map rows, the real Commander_Events settings framework and
-- Go button) and loads the Notebook's three files after it, as the client
-- does (the Notebook lists Commander_Orders in its OptionalDeps):
--   A  loads clean beside Orders
--   B  a map-stamped note's Go is Orders' Go button: click = ONE waypoint
--      (Notebook, note:<id>) at the stamp in the NOTE tint with the arrow on
--      it, Orders' "Waypoint set" line once and none of the Notebook's, lit
--      "Going" while the arrow is there, a second press the same record
--   C  the note's menu "Go To This Note" asks for the same waypoint
--   D  Orders switched off: greyed with Orders' words, the click says Orders'
--      one line; a menu press says Orders' one line with the [Go] link
--   E  an old, name-only stamp still goes by name through Orders' /way
--      resolver (Import), under the Notebook's source, and says "Waypoint set"
--      -- only while Orders' Announce In Chat is on, like every other Go
--   F  Orders absent: the /way line, never a dead button

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
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }

local function Boot(opts)
    opts = opts or {}
    local mutant = os.getenv("NOTEBOOK_UI")
    local files = { "CommanderNotebookStore.lua", "CommanderNotebookDB.lua" }
    if not mutant then files[3] = "CommanderNotebookUI.lua" end
    return M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        files = opts.noOrders and {} or nil,
        before = function()
            rawset(_G, "GetSubZoneText", function() return "Goldshire" end)
            rawset(_G, "GetRealmName", function() return "Dreamscythe" end)
        end,
        addons = { { name = "Commander_Notebook", files = files } },
        afterFiles = function()
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
        end,
    })
end

local function O() return rawget(_G, "CommanderOrders") end
local function S() return CommanderNotebookStore end
local function N() return CommanderNotebook end
local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Count(needle)
    local n = 0
    for _, line in ipairs(M.prints) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end
-- The shown action-row button with this text
local function Button(text)
    local found
    for _, w in ipairs(M.W.widgets) do
        if rawget(w, "__text") == text and rawget(w, "__template") == "UIPanelButtonTemplate" and w.__shown then
            found = w
        end
    end
    return found
end
local function Click(b) b.__scripts.OnClick(b, "LeftButton", false) end

-- A note stamped in Goldshire (the 1.1.0 context: map id and exact spot)
local function StampedNote(title, x, y)
    local note = S().CreateNote({ title = title, body = "stamped" })
    S().SetContext(note.id, { map = 1429, x = x or 0.42, y = y or 0.655, zone = "Elwynn Forest", subzone = "Goldshire" })
    return S().Note(note.id)
end

-- ===========================================================================
Section("A", function()
    Boot()
    NoErrors("A")
    EQ(type(N().NoteWaypoint), "function", "A: the Notebook's way back is there")
end)

-- ===========================================================================
Section("B", function()
    Boot()
    local note = StampedNote("Arena comp", 0.42, 0.655)
    M.SetPlayer(1429, 0.30, 0.40)
    N().OpenToNote(note.id)
    local go = Button("Go")
    CHECK(go ~= nil, "B: a stamped note offers Go")
    CHECK(go and rawget(go, "_goOpts") ~= nil, "B: ...Commander Orders' Go button")
    if not go then return end
    EQ(go._goOpts.key, "note:" .. note.id, "B: keyed by the note")
    M.ClearLog()
    Click(go)
    M.Frame()
    local list = O().List({ source = "Notebook" })
    EQ(#list, 1, "B: one waypoint")
    local wp = list[1]
    EQ(wp and wp.key, "note:" .. note.id, "B: owned as (Notebook, note:<id>)")
    EQ(wp and wp.icon, "NOTE", "B: in the Notebook's tint")
    CHECK(wp and wp.map == 1429 and math.abs(wp.x - 0.42) < 1e-9 and math.abs(wp.y - 0.655) < 1e-9,
        "B: at the stamp's exact spot")
    EQ(wp and wp.title, "Arena comp", "B: titled with the note")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "B: the arrow on it")
    EQ(Count("Waypoint set: Arena comp"), 1, "B: Orders' own \"Waypoint set\" line, once")
    EQ(Count("Commander Notebook"), 0, "B: ...and none of the Notebook's")
    go:Refresh()
    EQ(go.__text, "Going", "B: lit while the arrow is there")
    Click(go)
    EQ(#O().List({ source = "Notebook" }), 1, "B: a second press is the same waypoint")
    -- Another note: the same button, its own waypoint
    local other = StampedNote("Second spot", 0.5, 0.5)
    N().OpenToNote(other.id)
    local go2 = Button("Go")
    EQ(go2, go, "B: one Go button, re-pointed at the open note")
    go2:Refresh()
    EQ(go2.__text, "Go", "B: ...not lit for a note the arrow is not on")
    Click(go2)
    EQ(#O().List({ source = "Notebook" }), 2, "B: each note owns its own waypoint")
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    Boot()
    local note = StampedNote("Menu spot", 0.45, 0.6)
    N().OpenToNote(note.id)
    Click(Button("Move To..."))
    CHECK(M.ClickMenu("Go To This Note"), "C: the note's menu offers Go To This Note")
    M.Frame()
    local wp = O().R.Store():ByKey("Notebook", "note:" .. note.id)
    CHECK(wp ~= nil, "C: ...the same waypoint the button makes")
    EQ(wp and wp.icon, "NOTE", "C: ...in the Notebook's tint")
    CHECK(not M.Has(M.MenuTexts(), "Waypoint To This Note"), "C: (\"Waypoint\" is only the noun now)")
    NoErrors("C")
end)

-- ===========================================================================
Section("D", function()
    Boot()
    local note = StampedNote("Closed shop", 0.4, 0.6)
    CommanderOrdersDB.EnableOrders = false
    N().OpenToNote(note.id)
    local go = Button("Go")
    go:Refresh()
    CHECK(not go:IsEnabled(), "D: Orders off: greyed")
    EQ(go._goReason, "disabled", "D: ...with the reason")
    M.ClearLog()
    Click(go)
    EQ(Count(O().Reason("disabled")), 1, "D: a click says Orders' words, once")
    EQ(#O().List({ source = "Notebook" }), 0, "D: ...and makes nothing")
    M.ClearLog()
    N().NoteWaypoint(S().Note(note.id))
    EQ(#M.prints, 1, "D: the menu's press: ONE line", table.concat(M.prints, " / "))
    local line = M.prints[1] or ""
    CHECK(line:find(O().Reason("disabled"), 1, true) and line:find("Closed shop", 1, true)
        and line:find("|Haddon:CommanderOrders:", 1, true), "D: ...Orders' refusal with the place and a [Go] link", line)
    CommanderOrdersDB.EnableOrders = true
    NoErrors("D")
end)

-- ===========================================================================
Section("E", function()
    Boot()
    local old = S().CreateNote({ title = "Rare spawn",
        body = "-- Devinp (70) | Goldshire, Elwynn Forest 42.5, 61.2 | 04 Oct 2026, 13:50" })
    N().OpenToNote(old.id)
    local go = Button("Go")
    CHECK(go ~= nil and rawget(go, "_goOpts") == nil, "E: an old stamp's Go is the plain button")
    M.ClearLog()
    Click(go)
    M.Frame()
    local list = O().List({ source = "Notebook" })
    EQ(#list, 1, "E: the zone found by name: one waypoint")
    CHECK(list[1] and list[1].map == 1429 and math.abs(list[1].x - 0.425) < 1e-9, "E: ...in Elwynn at the stamp's numbers")
    EQ(Count("Waypoint set: Rare spawn"), 1, "E: \"Waypoint set\", the same words")
    -- Orders' Announce In Chat off: no Go says "Waypoint set", this one neither
    CommanderOrdersDB.Announce = false
    O().RemoveBy("Notebook")
    M.Frame()
    M.ClearLog()
    Click(go)
    M.Frame()
    EQ(#O().List({ source = "Notebook" }), 1, "E: Announce In Chat off: the waypoint all the same")
    EQ(#M.prints, 0, "E: ...and not a line from anyone", table.concat(M.prints, " / "))
    M.ClearLog()
    N().NoteWaypoint(S().Note(old.id))
    EQ(#M.prints, 0, "E: ...from the menu's Go To This Note either", M.prints[1])
    -- A map-stamped note under the same switch: silent too (Orders' GoTo)
    local stamped = StampedNote("Quiet spot", 0.40, 0.60)
    M.ClearLog()
    N().NoteWaypoint(S().Note(stamped.id))
    M.Frame()
    EQ(#M.prints, 0, "E: ...the same as a map-stamped note's Go", M.prints[1])
    CommanderOrdersDB.Announce = true
    NoErrors("E")
end)

-- ===========================================================================
Section("F", function()
    Boot({ noOrders = true })
    local note = StampedNote("No arrow", 0.42, 0.655)
    N().OpenToNote(note.id)
    local go = Button("Go")
    M.ClearLog()
    Click(go)
    CHECK(M.Has(M.prints, "/way #1429 42.00 65.50 No arrow"), "F: no Orders: the /way line", M.prints[1])
    M.ClearLog()
    N().NoteWaypoint(S().Note(note.id))
    CHECK(M.Has(M.prints, "/way #1429 42.00 65.50 No arrow"), "F: ...from the menu too", M.prints[1])
    NoErrors("F")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

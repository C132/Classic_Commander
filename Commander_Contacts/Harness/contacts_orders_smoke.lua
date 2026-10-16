-- Commander Contacts + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Contacts/Harness/contacts_orders_smoke.lua
--     CONTACTS_UI=/tmp/mutant.lua luajit ...          (a mutated CommanderContactsUI.lua)
--
-- contacts_ui_harness.lua section G drives Arrow To Them, the [Go] links in
-- the log and their hover against a recording stand-in for Orders. This boots
-- the real Orders (its chat file included) over the client mock Orders' own
-- harnesses share (Commander_Orders/Harness/orders_mock.lua) and loads the
-- Contacts files after it, as the client does:
--   A  loads clean beside Orders
--   B  Arrow To Them on a grouped person's thread: a real unit follow
--      (Contacts, follow) on their token, named by GUID, the arrow on it,
--      Orders' "Waypoint set" line once; after a roster shuffle Orders follows
--      the same person (by GUID); asking for someone else moves the one follow
--   C  not grouped: nothing offered
--   D  a logged line "Elwynn Forest 42.5, 61.2" carries Orders' own [Go]
--      link; clicking it is Orders' Go; a bare "/way 45 66" stays text (a
--      line from the log has no live context)
--   E  hovering an Orders link in the log shows Orders' tooltip

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

local function Boot()
    local mutant = os.getenv("CONTACTS_UI")
    local files = {}
    for _, f in ipairs(M.AddonTocFiles("Commander_Contacts")) do
        if not (mutant and f == "CommanderContactsUI.lua") then files[#files + 1] = f end
    end
    M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        addons = { { name = "Commander_Contacts", files = files } },
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
    CommanderContacts.Show()
end

local function O() return rawget(_G, "CommanderOrders") end
local function S() return CommanderContactsStore end
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
-- The sidebar row showing a thread, and its right-click menu
local function Row(id)
    local found
    for _, w in ipairs(M.W.widgets) do
        local e = rawget(w, "entry")
        if type(e) == "table" and e.id == id and w.__shown ~= false then found = w end
    end
    return found
end
local function MenuOf(id)
    local row = Row(id)
    if not row then return nil end
    M.menu = {}
    row.__scripts.OnClick(row, "RightButton")
    local out = {}
    for _, e in ipairs(M.menu) do out[e.text] = e end
    return out
end
local function Thread(name)
    local conv = S().EnsureDM(name, {})
    CommanderContacts.OpenConversation(conv.key)
    CommanderContacts.ShowTab("activity")
    return conv
end
-- The drawn transcript line rows holding a text
local function LineWith(needle)
    for _, w in ipairs(M.W.widgets) do
        local fs = rawget(w, "text")
        if type(fs) == "table" and rawget(w, "author") and fs.__text and tostring(fs.__text):find(needle, 1, true) then
            return w, fs.__text
        end
    end
    return nil
end

-- ===========================================================================
Section("A", function()
    Boot()
    NoErrors("A")
end)

-- ===========================================================================
Section("B", function()
    Boot()
    M.SetGroup("party", { "Zuljin", "Rokhan" })
    M.SetUnit("party1", 1429, 0.45, 0.60)
    M.SetUnit("party2", 1429, 0.40, 0.70)
    local conv = Thread("Zuljin")
    local menu = MenuOf(conv.key)
    CHECK(menu and menu["Arrow To Them"], "B: a grouped person's thread offers Arrow To Them")
    if not (menu and menu["Arrow To Them"]) then return end
    M.ClearLog()
    menu["Arrow To Them"].func()
    M.Frame()
    local wp = O().R.Store():ByKey("Contacts", "follow")
    CHECK(wp ~= nil, "B: a waypoint (Contacts, follow)")
    EQ(wp and wp.kind, "unit", "B: ...a unit follow")
    EQ(wp and wp.unit, "party1", "B: ...on their group token")
    EQ(wp and wp.icon, "UNIT", "B: ...in the group-member tint")
    EQ(wp and wp.clearOnArrive, false, "B: ...that does not end by catching up with them")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "B: the arrow follows them")
    EQ(Count("Waypoint set: Zuljin"), 1, "B: Orders' own \"Waypoint set\" line, once")
    -- The roster shuffles: Orders finds the same person by GUID
    M.SetGroup("party", { "Rokhan", "Zuljin" })
    M.SetUnit("party1", 1429, 0.40, 0.70)
    M.SetUnit("party2", 1429, 0.45, 0.60)
    M.Fire("GROUP_ROSTER_UPDATE")
    M.Frame()
    wp = O().R.Store():ByKey("Contacts", "follow")
    EQ(wp and wp.unit, "party2", "B: after a reshuffle Orders follows the same person (by GUID)")
    -- Somebody else: the one follow moves
    local other = Thread("Rokhan")
    menu = MenuOf(other.key)
    if menu and menu["Arrow To Them"] then menu["Arrow To Them"].func() end
    M.Frame()
    EQ(#O().List({ source = "Contacts" }), 1, "B: asking for someone else moves the one follow")
    wp = O().R.Store():ByKey("Contacts", "follow")
    EQ(wp and wp.unit, "party1", "B: ...to them")
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    Boot()
    local conv = Thread("Zuljin")
    local menu = MenuOf(conv.key)
    CHECK(menu ~= nil and menu["Whisper In Chat"] ~= nil, "C: (the thread's menu)")
    EQ(menu and menu["Arrow To Them"], nil, "C: not in your group: nothing offered")
    EQ(#O().List({ source = "Contacts" }), 0, "C: ...and nothing made")
end)

-- ===========================================================================
Section("D", function()
    Boot()
    local conv = Thread("Zuljin")
    S().Append(conv.key, { from = "Zuljin", text = "meet at Elwynn Forest 42.5, 61.2 now" })
    S().Append(conv.key, { from = "Zuljin", text = "or /way 45 66 there" })
    CommanderContacts.OpenConversation(conv.key)
    local row, text = LineWith("meet at Elwynn Forest")
    CHECK(row ~= nil, "D: (the logged line is drawn)")
    CHECK(text and text:find("|Haddon:CommanderOrders:w:", 1, true) and text:find("|h[Go]|h", 1, true),
        "D: a logged \"Zone x, y\" carries Orders' own [Go] link", text)
    local _, bare = LineWith("or /way 45 66")
    CHECK(bare and not bare:find("|H", 1, true), "D: a bare /way with no zone stays text (no live context)", bare)
    M.ClearLog()
    M.ClickLink(text)
    M.Frame()
    local mine = O().List({ source = "user" })[1]
    CHECK(mine and mine.map == 1429 and math.abs(mine.x - 0.425) < 1e-4, "D: clicking it is Orders' Go, to that spot")
    -- Chat Links off: the line is drawn plain
    CommanderOrdersDB.ChatLinks = false
    CommanderContacts.OpenConversation(conv.key)
    local _, plain = LineWith("meet at Elwynn Forest")
    CHECK(plain and not plain:find("|H", 1, true), "D: with Orders' Chat Links off the line is plain", plain)
    CommanderOrdersDB.ChatLinks = true
    NoErrors("D")
end)

-- ===========================================================================
Section("E", function()
    Boot()
    local conv = Thread("Zuljin")
    S().Append(conv.key, { from = "Zuljin", text = "Elwynn Forest 42.5, 61.2" })
    CommanderContacts.OpenConversation(conv.key)
    local row, text = LineWith("Elwynn Forest 42.5")
    CHECK(row ~= nil, "E: (the line)")
    if not row then return end
    local link = text and text:match("|H(addon:CommanderOrders:[^|]+)|h")
    for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end
    row.__scripts.OnHyperlinkEnter(row, link, "[Go]")
    local tip = table.concat(M.tooltip, "\n")
    CHECK(tip:find("Elwynn Forest", 1, true) and tip:find("Click: Go.", 1, true),
        "E: hovering it shows Orders' tooltip (place and gestures)", tip)
    row.__scripts.OnHyperlinkLeave(row, link, "[Go]")
    NoErrors("E")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

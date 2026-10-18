-- Commander Orders: places in chat you can click (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Orders/Harness/orders_chat_harness.lua
--
-- Runs from the AddOns root, from this folder or from anywhere else: the root
-- is found from this file's own path. Mutation hook: ORDERS_CHAT=/path of a
-- copy of CommanderOrdersChat.lua to load in its place.
--
-- Boots the REAL Orders over the shared client mock (orders_mock.lua: this
-- build's UiMap rows, ChatFrameUtil's filter chain run the 2.5.6 way, the
-- addon-link route SetItemRef -> EventRegistry "SetItemRef") with the chat
-- file loaded on top, then feeds it chat lines the way ChatFrameFilters.lua
-- does and clicks and hovers the links it writes.
--
--   A  loads clean: no global, no chat line; one filter per chat event (the
--      ChatFrameUtil one, the deprecated global only as a fallback); the
--      click and hover callbacks on EventRegistry under a table of its own
--   B  the plain-text stretches: links, colours, textures, {...} skipped
--   C  tier A, /way lines: every spelling, the context of a bare /way
--      (yours, a group member's, nearby, nobody's), refusals, punctuation
--   D  tier B, "Zone x, y": exact names and long aliases only; times, money,
--      ranges, percents, decimal commas and bare pairs never linked
--   E  Orders' own shared line ("Title - Zone x, y (/way ...)") gets ONE link
--      with its title back, at every precision
--   F  the filter's contract: fourteen arguments back, a bare false when
--      nothing changed, the lineID cache, the switches, errors contained
--   G  what Blizzard does to the line after the filters (% doubled and
--      formatted, {...} icons, runs of spaces, Commander Chat's tags) leaves
--      the link intact
--   H  the click: Go, Ctrl copy, Shift share (typed into an open box, or
--      posted), Right menu with every entry; other addons' links ignored;
--      a refused Go's own printed link clickable
--   I  the hover tooltip, and only our own tooltip hidden on leave
--   J  ClaimChatLink: a module's plain click and Go, 64 kept, newest wins,
--      errors contained, gone after a reload
--   K  CommanderOrders.Linkify for text that never passed the filters
--   L  globals (static): reads only what it means to, writes none
--   M  the full TOC: the chat file in its slot beside every other 3.1 file

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")
local CHAT_FILE = os.getenv("ORDERS_CHAT") or (ADDONS .. "/Commander_Orders/CommanderOrdersChat.lua")
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
    CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, s)
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
-- Boot: Orders without the files other agents own (the chat file needs none
-- of them), the chat file loaded last under its own phase (so its globals
-- can be told apart), and the client pieces the shared mock leaves out
-- ---------------------------------------------------------------------------
local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true, CommanderOrdersLocate = true,
               CommanderOrdersCoords = true, CommanderOrdersChat = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }
local H = {}

local function Stubs(opts)
    H.opened = {}
    H.box = nil
    -- the TBC world map as 2.5.6 ships it (review: blizzard): OpenWorldMap
    -- calls WorldMapFrame:HandleUserActionOpenSelf, which only the Wrath
    -- files define, so it raises; ToggleWorldMap and SetMapID are the way.
    -- H.opened records the map each SetMapID lands on.
    rawset(_G, "OpenWorldMap", function(map) WorldMapFrame:HandleUserActionOpenSelf(map) end)
    H.toggles = 0
    rawset(_G, "ToggleWorldMap", function()
        H.toggles = H.toggles + 1
        if WorldMapFrame:IsShown() then WorldMapFrame:Hide() else WorldMapFrame:Show() end
    end)
    local setMapID = WorldMapFrame.SetMapID
    rawset(_G, "WorldMapFrame", setmetatable({
        SetMapID = function(self, map)
            H.opened[#H.opened + 1] = map
            return setMapID(self, map)
        end,
    }, { __index = WorldMapFrame }))
    if opts.noUtil then rawset(_G, "ChatFrameUtil", false) end
    if opts.noShim then rawset(_G, "ChatFrame_AddMessageEventFilter", false) end
    if opts.noRegistry then rawset(_G, "EventRegistry", false) end
    if not opts.noUtil and not opts.bareUtil then
        -- ChatFrameUtil.GetActiveWindow / InsertLink (Shared/ChatFrameUtil.lua
        -- 421, Classic/ChatFrameUtilOverrides.lua 1-10): the box being typed in
        local util = ChatFrameUtil
        util.GetActiveWindow = function() return H.box end
        util.InsertLink = function(text)
            if H.box then
                H.box:Insert(text)
                return true
            end
            return false
        end
    end
end

local function OpenBox()
    H.box = { inserted = {} }
    function H.box:Insert(text) self.inserted[#self.inserted + 1] = text end
    return H.box
end

local function LoadChat(m, w)
    w.phase = "chat"
    local chunk, err = loadfile(CHAT_FILE)
    if not chunk then
        m.loadErrors[#m.loadErrors + 1] = "CommanderOrdersChat.lua: " .. tostring(err)
    else
        local ok, runErr = pcall(chunk)
        if not ok then m.loadErrors[#m.loadErrors + 1] = "CommanderOrdersChat.lua: " .. tostring(runErr) end
    end
    w.phase = "orders"
end

local function Boot(opts)
    opts = opts or {}
    return M.Boot({
        player = opts.player or GOLDSHIRE,
        faction = opts.faction,
        saved = opts.saved,
        skipFiles = opts.skipFiles or SKIP,
        before = function() Stubs(opts) end,
        afterFiles = (opts.skipFiles == nil) and LoadChat or nil,
    })
end

local function O() return CommanderOrders end
local function C() return CommanderOrders.Chat end

-- A party with Zuljin (party1) standing in Hellfire Peninsula
local function Party(map, x, y)
    M.SetGroup("party", { "Zuljin" })
    M.SetUnit("party1", map or 1944, x or 0.5, y or 0.5)
end

local ZULJIN = "Player-1-Zuljin"
local STRANGER = "Player-1-Stranger"
local lineSeq = 1000

-- One chat line through the filter chain: { discard, arg1 .. arg14 }
local function Line(event, msg, opts)
    opts = opts or {}
    lineSeq = lineSeq + 1
    local id = opts.lineID
    if id == nil then id = lineSeq end
    return { M.RunChatFilters(event, msg, opts.sender or "Zuljin-Dreamscythe", "Orcish", "", "",
        "", opts.chan or 0, 0, opts.base or "", 1, id, opts.guid or ZULJIN, 0, false) }
end

-- The text a line shows after the filters
local function Shown(event, msg, opts)
    return Line(event, msg, opts)[2]
end

-- Every Orders link in a text: { payload, shown, at (where |c starts) }
local function Links(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for at, payload, shown in text:gmatch("()|cff71d5ff|H(addon:CommanderOrders:[^|]*)|h(.-)|h|r") do
        out[#out + 1] = { payload = payload, shown = shown, at = at }
    end
    return out
end

local function OnlyLink(text)
    local list = Links(text)
    if #list ~= 1 then return nil end
    return list[1]
end

local function PlaceOf(payload)
    if not payload then return nil end
    local map, x, y, title = O().ParseChatLink(payload)
    if not map then return nil end
    return { map = map, x = x, y = y, title = title }
end

local function CheckPlace(text, map, x, y, title, label)
    local link = OnlyLink(text)
    CHECK(link ~= nil, label .. ": one link", text)
    if not link then return nil end
    EQ(link.shown, "[Go]", label .. ": it reads [Go]")
    local p = PlaceOf(link.payload)
    CHECK(p ~= nil, label .. ": the link parses", link.payload)
    if not p then return nil end
    EQ(p.map, map, label .. ": map")
    NEAR(p.x, x, 1e-4, label .. ": x")
    NEAR(p.y, y, 1e-4, label .. ": y")
    EQ(p.title, title, label .. ": title")
    return link, p
end

-- Click a payload as SetItemRef would, with modifiers held
local function Click(payload, button, mods)
    for _, key in ipairs({ "SHIFT", "CTRL", "ALT" }) do M.W.mods[key] = false end
    for _, key in ipairs(mods or {}) do M.W.mods[key] = true end
    SetItemRef(payload, "[Go]", button or "LeftButton", M.chatFrame)
    for _, key in ipairs({ "SHIFT", "CTRL", "ALT" }) do M.W.mods[key] = false end
    M.Advance(0.1)
end

local function Enter(payload, frame)
    EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkEnter", frame or M.chatFrame, payload, "[Go]")
end

local function Leave(frame)
    EventRegistry:TriggerEvent("ChatFrame.OnHyperlinkLeave", frame or M.chatFrame)
end

local function Count()
    return #O().List()
end

-- Spy on the scan (Rewrite calls Chat.Scan through the table)
local function SpyScan()
    local real = C().Scan
    local spy = { n = 0 }
    C().Scan = function(...)
        spy.n = spy.n + 1
        return real(...)
    end
    spy.restore = function() C().Scan = real end
    return spy
end

-- ---------------------------------------------------------------------------
-- A  loads clean
-- ---------------------------------------------------------------------------
Section("A", function()
    local W = Boot()
    NOERR("A login")
    EQ(#M.prints, 0, "A: a quiet login (no chat lines)")
    local wrote = {}
    for _, w in ipairs(M.writes) do
        if w.phase == "chat" then wrote[#wrote + 1] = w.name end
    end
    EQ(#wrote, 0, "A: the chat file writes no global", table.concat(wrote, " "))
    EQ(type(O().Linkify), "function", "A: CommanderOrders.Linkify")
    EQ(type(O().ClaimChatLink), "function", "A: CommanderOrders.ClaimChatLink")
    EQ(type(C()), "table", "A: CommanderOrders.Chat")
    EQ(type(C().Filter), "function", "A: Chat.Filter")

    -- one filter per chat event, and only the chat events
    local events = C().EVENTS
    EQ(#events, 17, "A: seventeen chat events")
    for _, event in ipairs(events) do
        local list = W.chatFilters[event] or {}
        EQ(#list, 1, "A: one filter on " .. event)
        EQ(list[1], C().Filter, "A: ...the chat file's, on " .. event)
    end
    for _, event in ipairs({ "CHAT_MSG_SYSTEM", "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_LOOT", "CHAT_MSG_ADDON" }) do
        EQ(W.chatFilters[event], nil, "A: no filter on " .. event)
    end

    -- the click and hover callbacks, each under one table owner of its own
    local owners = {}
    for _, event in ipairs({ "SetItemRef", "ChatFrame.OnHyperlinkEnter", "ChatFrame.OnHyperlinkLeave" }) do
        local n, owner = 0, nil
        for o in pairs(W.eventCallbacks[event] or {}) do n = n + 1; owner = o end
        EQ(n, 1, "A: one EventRegistry callback for " .. event)
        EQ(type(owner), "table", "A: ...with a table owner (one callback per owner per event)")
        owners[owner or event] = true
    end
    local distinct = 0
    for _ in pairs(owners) do distinct = distinct + 1 end
    EQ(distinct, 1, "A: the same owner for all three")
    EQ(W.eventCallbacks.SetItemRef[next(W.eventCallbacks.SetItemRef)], C().OnLink, "A: SetItemRef -> Chat.OnLink")

    -- ChatFrameUtil absent: the deprecated global is the fallback
    W = Boot({ noUtil = true })
    NOERR("A: no ChatFrameUtil")
    EQ(#(W.chatFilters.CHAT_MSG_PARTY or {}), 1, "A: no ChatFrameUtil: ChatFrame_AddMessageEventFilter is used")
    -- neither, nor EventRegistry: it still loads and does nothing
    W = Boot({ noUtil = true, noShim = true, noRegistry = true })
    NOERR("A: no filter API, no EventRegistry")
    EQ(W.chatFilters.CHAT_MSG_PARTY, nil, "A: nothing to register with: no filter")
    EQ(type(O().Linkify), "function", "A: ...and the exports are still there")
end)

-- ---------------------------------------------------------------------------
-- B  plain-text stretches
-- ---------------------------------------------------------------------------
local function SpanText(text)
    local out = {}
    for _, s in ipairs(C().PlainSpans(text)) do out[#out + 1] = text:sub(s[1], s[2]) end
    return table.concat(out, "#")
end

Section("B", function()
    Boot()
    EQ(SpanText("plain words 45 66"), "plain words 45 66", "B: a plain line is one stretch")
    EQ(SpanText("a |cffffffff|Hitem:1:0|h[Boots]|h|r b"), "a # b", "B: a coloured link is skipped whole")
    EQ(SpanText("a |Hplayer:Bob|h[Bob]|h b"), "a # b", "B: a bare link is skipped whole")
    EQ(SpanText("a |cffff0000red words 45 66|r b"), "a # b", "B: a colour run is skipped to its |r")
    EQ(SpanText("{rt1} x {skull}"), " x ", "B: {...} expressions are skipped")
    EQ(SpanText("x |TInterface\\Icons\\X:0|t y"), "x # y", "B: a texture is skipped")
    EQ(SpanText("x |A:atlas:0:0|a y"), "x # y", "B: an atlas is skipped")
    EQ(SpanText("x |Hitem:1|h[open"), "x ", "B: a link left open protects the rest of the line")
    EQ(SpanText("x |cffff0000 open colour"), "x ", "B: a colour left open protects the rest")
    EQ(SpanText("x || y"), "x # y", "B: any other escape is two bytes")
    EQ(SpanText("a { b"), "a # b", "B: a lone { is only itself")
    EQ(SpanText(""), "", "B: an empty line has no stretch")
    NOERR("B")
end)

-- ---------------------------------------------------------------------------
-- C  tier A: /way lines
-- ---------------------------------------------------------------------------
Section("C", function()
    Boot()
    Party()
    local text = Shown("CHAT_MSG_PARTY", "/way Hellfire Peninsula 45 66 Boss")
    local link = CheckPlace(text, 1944, 0.45, 0.66, "Boss", "C zone name")
    if link then
        EQ(text:sub(1, link.at - 1), "/way Hellfire Peninsula 45 66 Boss ", "C: the line is kept, the link after it")
    end
    CheckPlace(Shown("CHAT_MSG_PARTY", "/tway hfp 45.5 66.25"), 1944, 0.455, 0.6625, nil, "C /tway + alias")
    CheckPlace(Shown("CHAT_MSG_PARTY", "/TomTomWay #1944 45 66"), 1944, 0.45, 0.66, nil, "C /tomtomway #id")
    CheckPlace(Shown("CHAT_MSG_PARTY", "/WAY Elwynn Forest 42 65 Inn"), 1429, 0.42, 0.65, "Inn", "C /WAY any case")
    CheckPlace(Shown("CHAT_MSG_PARTY", "/way elwynn 42.5,65.5"), 1429, 0.425, 0.655, nil, "C 42.5,65.5")

    -- A bare /way: whose map?
    CheckPlace(Shown("CHAT_MSG_PARTY", "/way 45 66 camp"), 1944, 0.45, 0.66, "camp",
        "C bare, a group member's line: their map")
    CheckPlace(Shown("CHAT_MSG_GUILD", "/way 45 66 camp"), 1944, 0.45, 0.66, "camp",
        "C bare, a group member in guild chat: still their map")
    CheckPlace(Shown("CHAT_MSG_SAY", "/way 45 66", { guid = STRANGER, sender = "Stranger" }), 1429, 0.45, 0.66, nil,
        "C bare, /say from a stranger nearby: your map")
    CheckPlace(Shown("CHAT_MSG_YELL", "/way 45 66", { guid = STRANGER }), 1429, 0.45, 0.66, nil, "C bare, /yell")
    CheckPlace(Shown("CHAT_MSG_WHISPER_INFORM", "/way 45 66", { guid = STRANGER }), 1429, 0.45, 0.66, nil,
        "C bare, your own whisper: your map")
    CheckPlace(Shown("CHAT_MSG_RAID", "/way 45 66", { guid = "Player-1-00000001" }), 1429, 0.45, 0.66, nil,
        "C bare, your own line (your GUID): your map")
    CheckPlace(Shown("CHAT_MSG_CHANNEL", "/way 45 66", { guid = STRANGER, chan = 1 }), 1429, 0.45, 0.66, nil,
        "C bare, the zone's General: your map")
    CheckPlace(Shown("CHAT_MSG_CHANNEL", "/way 45 66", { guid = STRANGER, chan = 22 }), 1429, 0.45, 0.66, nil,
        "C bare, LocalDefense: your map")
    for _, case in ipairs({
        { "CHAT_MSG_CHANNEL", 2, "Trade" }, { "CHAT_MSG_CHANNEL", 0, "a channel joined by name" },
        { "CHAT_MSG_GUILD", 0, "guild" }, { "CHAT_MSG_WHISPER", 0, "a whisper" },
        { "CHAT_MSG_BN_WHISPER", 0, "a Battle.net whisper" },
    }) do
        EQ(Shown(case[1], "/way 45 66", { guid = STRANGER, chan = case[2] }), "/way 45 66",
            "C bare, " .. case[3] .. " from someone not in your group: no map, no link")
    end
    -- The member stands in a dungeon map: its zone, which is what people read
    M.SetUnit("party1", 347, 0.5, 0.5)
    CheckPlace(Shown("CHAT_MSG_PARTY", "/way 45 66"), 1944, 0.45, 0.66, nil,
        "C bare, the member inside Hellfire Ramparts: Hellfire Peninsula's coordinates")
    M.SetUnit("party1", 1944, 0.5, 0.5)
    -- The member's map unknown: no link
    M.SetUnit("party1", nil)
    EQ(Shown("CHAT_MSG_PARTY", "/way 45 66"), "/way 45 66", "C bare, the member's map unknown: no link")
    M.SetUnit("party1", 1944, 0.5, 0.5)
    -- an explicit zone needs no context at all
    CheckPlace(Shown("CHAT_MSG_WHISPER", "/way Elwynn Forest 42 65", { guid = STRANGER }), 1429, 0.42, 0.65, nil,
        "C a stranger's whisper naming its zone")

    -- No link that would do nothing
    for _, case in ipairs({
        { "/way the 45 66", "an ambiguous zone" },
        { "/way 145 66", "out of range" },
        { "/way #99999 45 66", "a map that does not exist" },
        { "/way #234 45 66", "a dungeon map with no world position (Dire Maul)" },
        { "/way Nowhereland 45 66", "an unknown zone" },
        { "/way", "no coordinates" },
        { "/way reset all", "a reset" },
        { "/way list 45", "a list" },
        { "go/way 45 66", "/way inside a word" },
        { "/wayb 45 66", "another slash command" },
        { "|cffff0000/way 45 66|r", "a /way inside someone's colour" },
    }) do
        EQ(#Links(Shown("CHAT_MSG_PARTY", case[1])), 0, "C no link: " .. case[2])
    end

    -- Punctuation around the line
    text = Shown("CHAT_MSG_PARTY", "/way 45 66!")
    link = CheckPlace(text, 1944, 0.45, 0.66, nil, "C trailing !")
    if link then EQ(text:sub(link.at - 3, link.at - 1), "66 ", "C: the link goes after the numbers") end
    text = Shown("CHAT_MSG_PARTY", "(see /way Elwynn Forest 42 65)")
    link = CheckPlace(text, 1429, 0.42, 0.65, nil, "C inside someone's ( )")
    if link then
        EQ(text:sub(1, link.at - 1), "(see /way Elwynn Forest 42 65 ", "C: ...the link before the closing )")
        EQ(text:sub(-1), ")", "C: ...which stays")
    end
    text = Shown("CHAT_MSG_PARTY", "go (/way Elwynn Forest 42 65) now")
    link = CheckPlace(text, 1429, 0.42, 0.65, nil, "C (/way ...)")
    if link then EQ(text:sub(1, link.at - 1), "go (/way Elwynn Forest 42 65) ", "C: ...the link after its )") end
    CheckPlace(Shown("CHAT_MSG_PARTY", "/way Elwynn Forest 42 65 Boss (rare)"), 1429, 0.42, 0.65, "Boss (rare)",
        "C a title's own (...) kept")

    -- Titles
    text = Shown("CHAT_MSG_PARTY", "/way 45 66 Kill |cffffffff|Hitem:1|h[Fang]|h|r here")
    link = CheckPlace(text, 1944, 0.45, 0.66, "Kill", "C a title stops at a link")
    HAS(text, "|cffffffff|Hitem:1|h[Fang]|h|r here", "C: ...which is left as it was")
    CheckPlace(Shown("CHAT_MSG_PARTY", "/way 45 66 {rt1} Skull"), 1944, 0.45, 0.66, nil, "C a title stops at {rt1}")
    CheckPlace(Shown("CHAT_MSG_PARTY", "/way 45 66 a:b [c] 50%"), 1944, 0.45, 0.66, "a:b [c] 50%",
        "C a title with : [ ] % round-trips")
    local long = string.rep("abcdefghij", 9)
    local _, p = CheckPlace(Shown("CHAT_MSG_PARTY", "/way 45 66 " .. long), 1944, 0.45, 0.66, long:sub(1, 60),
        "C a long title is cut to 60 bytes")
    CHECK(p == nil or #p.title == 60, "C: 60 bytes", p and p.title)

    -- Several in one line, and the cap
    text = Shown("CHAT_MSG_PARTY", "/way 40 40 A /way Elwynn Forest 50 50 B")
    local list = Links(text)
    EQ(#list, 2, "C: two /way lines, two links")
    local a, b = PlaceOf(list[1] and list[1].payload), PlaceOf(list[2] and list[2].payload)
    CHECK(a and a.map == 1944 and a.title == "A", "C: the first is the member's map, titled A", a and a.title)
    CHECK(b and b.map == 1429 and b.title == "B", "C: the second names Elwynn, titled B", b and b.title)
    HAS(text, "/way 40 40 A |c", "C: the first link right after its own line")
    text = Shown("CHAT_MSG_PARTY", "/way 1 1 /way 2 2 /way 3 3 /way 4 4 /way 5 5")
    EQ(#Links(text), 4, "C: at most four links a line")
    NOERR("C")
end)

-- ---------------------------------------------------------------------------
-- D  tier B: "Zone x, y"
-- ---------------------------------------------------------------------------
Section("D", function()
    Boot()
    local opts = { guid = STRANGER }
    local text = Shown("CHAT_MSG_GUILD", "Elwynn Forest 42.1, 65.9", opts)
    local link = CheckPlace(text, 1429, 0.421, 0.659, nil, "D Zone x, y")
    if link then EQ(text:sub(1, link.at - 1), "Elwynn Forest 42.1, 65.9 ", "D: the link after the pair") end
    CheckPlace(Shown("CHAT_MSG_GUILD", "elwynn forest 42 65", opts), 1429, 0.42, 0.65, nil, "D lowercase, integers")
    CheckPlace(Shown("CHAT_MSG_GUILD", "Elwynn Forest: 42, 65", opts), 1429, 0.42, 0.65, nil, "D Zone: x, y")
    CheckPlace(Shown("CHAT_MSG_GUILD", "Elwynn Forest - 42 65", opts), 1429, 0.42, 0.65, nil, "D Zone - x y")
    CheckPlace(Shown("CHAT_MSG_GUILD", "Elwynn Forest 42.1,65.9", opts), 1429, 0.421, 0.659, nil, "D x,y")
    text = Shown("CHAT_MSG_GUILD", "at Elwynn Forest (42.1, 65.9).", opts)
    link = CheckPlace(text, 1429, 0.421, 0.659, nil, "D (x, y).")
    if link then
        EQ(text:sub(1, link.at - 1), "at Elwynn Forest (42.1, 65.9) ", "D: ...the link after the )")
        EQ(text:sub(-1), ".", "D: ...and the full stop stays")
    end
    CheckPlace(Shown("CHAT_MSG_GUILD", "The Barrens 45 66", opts), 1413, 0.45, 0.66, nil, "D a name of three words' fold")
    CheckPlace(Shown("CHAT_MSG_GUILD", "boss in hellfire 45 66", opts), 1944, 0.45, 0.66, nil, "D a long alias")
    CheckPlace(Shown("CHAT_MSG_GUILD", "Rally on me! Goldshire, Elwynn Forest 42.1, 65.9", opts), 1429, 0.421, 0.659,
        nil, "D Commander Comms' rally line")
    CheckPlace(Shown("CHAT_MSG_GUILD", "Kalimdor 45 66", opts), 1414, 0.45, 0.66, nil, "D a continent")

    for _, case in ipairs({
        { "need 2, 3 more", "a bare pair (no tier C)" },
        { "45.2, 66.8", "a bare decimal pair" },
        { "am 45 66", "a two-letter alias (an English word)" },
        { "if 45 66 then", "\"if\"" },
        { "LF2M Ramparts 70 71", "a dungeon nickname" },
        { "Elwynn Forest 12:30", "a time" },
        { "Elwynn Forest 45g 66", "money" },
        { "Elwynn Forest 45 66g", "money after" },
        { "Elwynn Forest 60-70", "a range" },
        { "Elwynn Forest 50% 60", "a percent" },
        { "Elwynn Forest 45 66yd", "yards" },
        { "Elwynn Forest 45,2 66,8", "decimal commas" },
        { "Elwynn Forest 145 66", "over 100" },
        { "Elwynn Forest |cffffffff|Hitem:1|h[X]|h|r 42 65", "a zone and a pair split by a link" },
        { "Forest 42 65", "half a name" },
    }) do
        EQ(#Links(Shown("CHAT_MSG_GUILD", case[1], opts)), 0, "D no link: " .. case[2])
    end
    -- two places in one line
    text = Shown("CHAT_MSG_GUILD", "Elwynn Forest 42 65 or Hellfire Peninsula 45 66", opts)
    local list = Links(text)
    EQ(#list, 2, "D: two places, two links")
    EQ(PlaceOf(list[1] and list[1].payload).map, 1429, "D: ...Elwynn first")
    EQ(PlaceOf(list[2] and list[2].payload).map, 1944, "D: ...then Hellfire")
    -- a "Zone x, y" before a /way: each link after its own place, in order
    text = Shown("CHAT_MSG_PARTY", "Elwynn Forest 42 65 then /way Hellfire Peninsula 45 66 Boss", opts)
    list = Links(text)
    EQ(#list, 2, "D: a pair, then a /way: two links")
    CHECK(list[1] and PlaceOf(list[1].payload).map == 1429 and text:sub(1, list[1].at - 1) == "Elwynn Forest 42 65 ",
        "D: ...the pair's right after it", text)
    CHECK(list[2] and PlaceOf(list[2].payload).map == 1944 and text:find("Boss |cff71d5ff", 1, true) ~= nil,
        "D: ...the /way's after its own line", text)
    -- a map the client has no world position for: no link (a Go would refuse)
    local realPos = O().R.PosWorld
    O().R.PosWorld = function(p) if p.map == 1429 then return nil end return realPos(p) end
    EQ(#Links(Shown("CHAT_MSG_GUILD", "Elwynn Forest 42 65", opts)), 0, "D: no world position there: no link")
    EQ(#Links(Shown("CHAT_MSG_GUILD", "/way Elwynn Forest 42 65", opts)), 0, "D: ...nor for a /way")
    O().R.PosWorld = realPos
    -- a /way line's own zone and numbers are tier A's, never linked twice
    EQ(#Links(Shown("CHAT_MSG_GUILD", "/way Elwynn Forest 42 65", opts)), 1, "D: a /way line is linked once")
    NOERR("D")
end)

-- ---------------------------------------------------------------------------
-- E  Orders' own shared line
-- ---------------------------------------------------------------------------
Section("E", function()
    Boot()
    local opts = { guid = STRANGER }
    local line = O().ChatText(1944, 0.452, 0.668, "Boss")
    EQ(line, "Boss - Hellfire Peninsula 45.2, 66.8 (/way #1944 45.20 66.80)", "E: (the shared line)")
    local text = Shown("CHAT_MSG_GUILD", line, opts)
    local link = CheckPlace(text, 1944, 0.452, 0.668, "Boss", "E shared line")
    if link then EQ(text:sub(1, link.at - 1), line .. " ", "E: one link, after its (/way ...)") end
    for _, decimals in ipairs({ 0, 2 }) do
        CommanderOrdersDB.CoordDecimals = decimals
        line = O().ChatText(1944, 0.452, 0.668, "Boss")
        CheckPlace(Shown("CHAT_MSG_GUILD", line, opts), 1944, 0.452, 0.668, "Boss",
            "E shared line at " .. decimals .. " decimals")
    end
    CommanderOrdersDB.CoordDecimals = 1
    CheckPlace(Shown("CHAT_MSG_GUILD", O().ChatText(1944, 0.452, 0.668, nil), opts), 1944, 0.452, 0.668, nil,
        "E shared line with no title")
    CheckPlace(Shown("CHAT_MSG_GUILD", O().ChatText(1944, 0.452, 0.668, "Boss - phase 2"), opts), 1944, 0.452,
        0.668, "Boss - phase 2", "E a title with its own dash")
    -- what Orders' Share actually posts
    M.ClearLog()
    local ok = O().SharePoint({ map = 1429, x = 0.43, y = 0.66, title = "Inn" }, "CHAT")
    CHECK(ok and M.chat[1], "E: (SharePoint CHAT posted)")
    if M.chat[1] then
        CheckPlace(Shown("CHAT_MSG_SAY", M.chat[1].text, { guid = "Player-1-00000001" }), 1429, 0.43, 0.66, "Inn",
            "E a posted share, read back")
    end
    NOERR("E")
end)

-- ---------------------------------------------------------------------------
-- F  the filter's contract
-- ---------------------------------------------------------------------------
Section("F", function()
    Boot()
    Party()
    -- all fourteen arguments come back
    local args = { "/way 45 66", "Zuljin-Dreamscythe", "Orcish", "4. LocalDefense", "Zuljin", "AFK", 22, 4,
                   "LocalDefense", 1, 777001, ZULJIN, 0, false }
    local res = { M.RunChatFilters("CHAT_MSG_PARTY", unpack(args, 1, 14)) }
    EQ(res[1], false, "F: never discards")
    CHECK(#Links(res[2]) == 1, "F: the text gained its link", res[2])
    for i = 2, 14 do EQ(res[i + 1], args[i], "F: argument " .. i .. " comes back") end
    -- a line with nothing: a bare false, the text untouched
    local frame = M.chatFrame
    EQ(select("#", C().Filter(frame, "CHAT_MSG_PARTY", "hello there 45 people")), 1,
        "F: nothing found: one return (false), so nothing is replaced")
    EQ(C().Filter(frame, "CHAT_MSG_PARTY", "hello there 45 people"), false, "F: ...and it is false")
    EQ(select("#", C().Filter(frame, "CHAT_MSG_PARTY", "/way 45 66", "Zuljin", "", "", "", "", 0, 0, "", 0, 777002,
        ZULJIN, 0, false)), 15, "F: something found: discard and fourteen arguments")
    -- the quick reject: no digit, no scan
    local spy = SpyScan()
    Shown("CHAT_MSG_PARTY", "no numbers here at all /way")
    EQ(spy.n, 0, "F: a line without a digit is never scanned")
    Shown("CHAT_MSG_PARTY", "one digit 7")
    EQ(spy.n, 1, "F: (a line with one is)")
    -- the lineID cache: the second window costs a lookup
    spy.n = 0
    local first = Line("CHAT_MSG_PARTY", "/way 45 66", { lineID = 9001 })
    local second = Line("CHAT_MSG_PARTY", "/way 45 66", { lineID = 9001 })
    EQ(spy.n, 1, "F: the same line in a second chat window is not scanned again")
    EQ(second[2], first[2], "F: ...and shows the same")
    Line("CHAT_MSG_PARTY", "/way 50 50", { lineID = 9001 })
    EQ(spy.n, 2, "F: another text under a reused lineID is scanned")
    Line("CHAT_MSG_PARTY", "/way 45 66", { lineID = 0 })
    Line("CHAT_MSG_PARTY", "/way 45 66", { lineID = 0 })
    EQ(spy.n, 4, "F: lineID 0 is never cached")
    local nothing = Line("CHAT_MSG_PARTY", "nothing 12", { lineID = 9002 })
    Line("CHAT_MSG_PARTY", "nothing 12", { lineID = 9002 })
    EQ(spy.n, 5, "F: a line with no place is remembered too")
    EQ(nothing[2], "nothing 12", "F: ...unchanged")
    -- 64 lines kept: the 65th pushes the oldest out
    spy.n = 0
    for i = 1, 65 do Line("CHAT_MSG_PARTY", "/way 45 " .. i, { lineID = 20000 + i }) end
    EQ(spy.n, 65, "F: (65 lines scanned)")
    Line("CHAT_MSG_PARTY", "/way 45 65", { lineID = 20065 })
    Line("CHAT_MSG_PARTY", "/way 45 2", { lineID = 20002 })
    EQ(spy.n, 65, "F: the last 64 lines are remembered")
    Line("CHAT_MSG_PARTY", "/way 45 1", { lineID = 20001 })
    EQ(spy.n, 66, "F: the 65th line back has been forgotten")
    spy.restore()

    -- the switches, read per line
    CommanderOrdersDB.ChatLinks = false
    EQ(Shown("CHAT_MSG_PARTY", "/way 45 66"), "/way 45 66", "F: Clickable Places in Chat off: no link")
    CommanderOrdersDB.ChatLinks = true
    CommanderOrdersDB.EnableOrders = false
    EQ(Shown("CHAT_MSG_PARTY", "/way 45 66"), "/way 45 66", "F: Commander Orders off: no link")
    CommanderOrdersDB.EnableOrders = true
    CHECK(#Links(Shown("CHAT_MSG_PARTY", "/way 45 66")) == 1, "F: both back on: the link again")

    -- an error in the scan leaves the line alone and is reported, a few times
    M.ClearLog()
    local real = C().Scan
    C().Scan = function() error("scan broke") end
    local broken = Line("CHAT_MSG_PARTY", "/way 45 66")
    EQ(broken[2], "/way 45 66", "F: a broken scan: the line as it was")
    EQ(broken[3], "Zuljin-Dreamscythe", "F: ...with its sender")
    CHECK(M.Has(M.errors, "scan broke"), "F: ...and the error reported", M.errors[1])
    for _ = 1, 10 do Line("CHAT_MSG_PARTY", "/way 45 66") end
    CHECK(#M.errors <= 5, "F: a scan that keeps breaking reports at most five times", #M.errors)
    C().Scan = real
    M.ClearLog()

    -- another addon's filter after ours, returning every argument: our link stays
    ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_PARTY", function(_, _, msg, ...) return false, msg .. " (seen)", ... end)
    res = Line("CHAT_MSG_PARTY", "/way 45 66")
    CHECK(#Links(res[2]) == 1 and res[2]:sub(-7) == " (seen)", "F: a later filter sees our link", res[2])
    EQ(res[3], "Zuljin-Dreamscythe", "F: ...and the sender survives both")
    NOERR("F")
end)

-- ---------------------------------------------------------------------------
-- G  Blizzard's own work on the line after the filters
-- ---------------------------------------------------------------------------
-- ChatFrameOverrides.lua MessageFormatter: % doubled, {...} -> icons
-- (C_ChatInfo.ReplaceIconAndGroupExpressions), runs of spaces collapsed
-- (RemoveExtraSpaces), then format(<"[%s]: "> .. msg, sender)
local function Blizzard(msg, sender)
    msg = msg:gsub("%%", "%%%%")
    msg = msg:gsub("{[^}]*}", "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t")
    msg = msg:gsub("  +", " ")
    return string.format("[%s]: " .. msg, sender or "Zuljin")
end

Section("G", function()
    Boot()
    Party()
    local text = Shown("CHAT_MSG_PARTY", "/way 45 66 50% off: {rt1} now")
    local before = Links(text)[1]
    local after = Links(Blizzard(text))[1]
    CHECK(before and after and before.payload == after.payload, "G: % doubled and formatted: the payload as it was",
        after and after.payload)
    local p = PlaceOf(after and after.payload)
    EQ(p and p.title, "50% off", "G: ...and its title reads back (the : before {rt1} ends the sentence)")
    HAS(Blizzard(text), "UI-RaidTargetingIcon_1", "G: (the {rt1} outside the link became an icon)")
    text = Shown("CHAT_MSG_PARTY", "Elwynn Forest   42  65   now")
    local link = Links(text)[1]
    CHECK(link and Links(Blizzard(text))[1] and Links(Blizzard(text))[1].payload == link.payload,
        "G: runs of spaces collapsed: the payload as it was")
    for _, line in ipairs({ "/way 45 66 a  b   c {x} d", "/way 45 66 Boss {skull}", "Hellfire Peninsula 45 66" }) do
        local l = Links(Shown("CHAT_MSG_PARTY", line))[1]
        CHECK(l and not l.payload:find("[{}|]") and not l.payload:find("  ", 1, true),
            "G: no brace, no bar, no run of spaces in the payload: " .. line, l and l.payload)
    end
    -- Commander Chat's short channel tags (CommanderChat.lua 61)
    text = Shown("CHAT_MSG_PARTY", "/way 45 66 Boss")
    local tagged = text:gsub("%[(%d+)%.%s?[^%]]*%]", "[%1]")
    EQ(tagged, text, "G: Commander Chat's \"[2. Trade]\" -> \"[2]\" leaves [Go] alone")
    NOERR("G")
end)

-- ---------------------------------------------------------------------------
-- H  the click
-- ---------------------------------------------------------------------------
Section("H", function()
    Boot()
    Party()
    local text = Shown("CHAT_MSG_PARTY", "/way 45 66 Boss")
    local payload = Links(text)[1] and Links(text)[1].payload
    CHECK(payload ~= nil, "H: (a link)")
    M.ClearLog()
    local before = Count()
    Click(payload)
    EQ(Count(), before + 1, "H: click: one waypoint")
    local active = O().Active()
    EQ(active and active.map, 1944, "H: ...at the place")
    NEAR(active and active.x, 0.45, 1e-9, "H: ...x")
    EQ(active and active.title, "Boss", "H: ...titled")
    EQ(active and active.why, "PINNED", "H: ...with the arrow on it")
    EQ(active and active.source, "user", "H: ...yours, as typing the /way would make it")
    CHECK(M.Has(M.prints, "Waypoint set: Boss"), "H: ...and said (Announce)", M.prints[1])
    local uid = active and active.uid
    Click(payload)
    EQ(Count(), before + 1, "H: clicking it again makes no second one")
    EQ(O().Active() and O().Active().uid, uid, "H: ...the same one")

    -- Ctrl: the /way line in the copy box, nothing added
    M.ClearLog()
    before = Count()
    Click(payload, "LeftButton", { "CTRL" })
    EQ(Count(), before, "H: Ctrl-click adds nothing")
    EQ(M.popups[1] and M.popups[1].which, "COMMANDER_ORDERS_COPY", "H: Ctrl-click: the copy box")
    EQ(O().R.ArrowState().copyText, "/way #1944 45.00 66.00 Boss", "H: ...with the /way line")

    -- Shift with a chat box open: the readable line typed into it
    M.ClearLog()
    local box = OpenBox()
    Click(payload, "LeftButton", { "SHIFT" })
    EQ(box.inserted[1], O().ChatText(1944, 0.45, 0.66, "Boss"), "H: Shift-click, box open: the readable line typed in")
    EQ(#M.chat, 0, "H: ...nothing sent")
    EQ(Count(), before, "H: ...nothing added")
    CHECK(not (box.inserted[1] or ""):find("|", 1, true), "H: ...never the link itself")
    H.box = nil
    -- Shift, no box: posted, to the group
    Click(payload, "LeftButton", { "SHIFT" })
    EQ(M.chat[1] and M.chat[1].text, O().ChatText(1944, 0.45, 0.66, "Boss"), "H: Shift-click, no box: posted")
    EQ(M.chat[1] and M.chat[1].chatType, "PARTY", "H: ...to your party")
    EQ(M.chat[1] and M.chat[1].api, "C_ChatInfo", "H: ...through C_ChatInfo.SendChatMessage")
    M.SetGroup(nil)
    M.ClearLog()
    Click(payload, "LeftButton", { "SHIFT" })
    EQ(M.chat[1] and M.chat[1].chatType, "SAY", "H: Shift-click solo: /say")

    -- Right: the menu
    M.ClearLog()
    Click(payload, "RightButton")
    EQ(table.concat(M.MenuTexts(), "|"),
        "Boss|Go|Add without the arrow|Open the map here|Post in chat|Copy /way line|Save as place",
        "H: right-click, solo: the menu")
    EQ(M.menu[1] and M.menu[1].isTitle, true, "H: ...headed by the title")
    EQ(M.menuAnchor, "cursor", "H: ...at the cursor")
    Party()
    Click(payload, "RightButton")
    EQ(table.concat(M.MenuTexts(), "|"),
        "Boss|Go|Add without the arrow|Open the map here|Share with group|Post in chat|Copy /way line|Save as place",
        "H: right-click in a group: Share with group too")
    M.ClearLog()
    M.ClickMenu("Share with group")
    EQ(M.sent[1] and M.sent[1].prefix, "CmdrOrders", "H: Share with group: Orders' addon message")
    EQ(M.sent[1] and M.sent[1].channel, "PARTY", "H: ...to the party")
    Click(payload, "RightButton")
    M.ClearLog()
    M.ClickMenu("Post in chat")
    EQ(M.chat[1] and M.chat[1].text, O().ChatText(1944, 0.45, 0.66, "Boss"), "H: Post in chat")
    Click(payload, "RightButton")
    M.ClickMenu("Copy /way line")
    EQ(O().R.ArrowState().copyText, "/way #1944 45.00 66.00 Boss", "H: Copy /way line")
    Click(payload, "RightButton")
    M.HideMap()
    M.ClearLog()
    M.ClickMenu("Open the map here")
    EQ(H.opened[#H.opened], 1944, "H: Open the map here: the map on the link's zone (SetMapID)")
    CHECK(WorldMapFrame:IsShown(), "H: ...opened through ToggleWorldMap, the player's own path")
    EQ(H.toggles, 1, "H: ...toggled once")
    EQ(#M.errors, 0, "H: ...and no error (OpenWorldMap raises on 2.5.6: review blizzard)", M.errors[1])
    Click(payload, "RightButton")
    M.ClickMenu("Open the map here")
    EQ(H.toggles, 1, "H: an open map is not toggled shut")
    EQ(H.opened[#H.opened], 1944, "H: ...it moves to the zone")
    CHECK(not pcall(OpenWorldMap, 1944), "H: (the mock's OpenWorldMap raises as the client's does)")
    local places = #O().Places()
    Click(payload, "RightButton")
    M.ClickMenu("Save as place")
    EQ(#O().Places(), places + 1, "H: Save as place: one more place")
    local saved = O().Places()[#O().Places()]
    EQ(saved and saved.title, "Boss", "H: ...named by the title")
    -- in combat the map stays shut
    M.SetCombat(true)
    Click(payload, "RightButton")
    local mapEntry
    for _, e in ipairs(M.menu) do if e.text == "Open the map here" then mapEntry = e end end
    EQ(mapEntry and mapEntry.disabled, true, "H: in combat, Open the map here is greyed")
    local opened = #H.opened
    M.ClearLog()
    if mapEntry then mapEntry.func(mapEntry) end
    EQ(#H.opened, opened, "H: ...and does not open it")
    CHECK(M.Has(M.prints, "after combat"), "H: ...saying so", M.prints[1])
    M.SetCombat(false)
    -- Go and Add without the arrow from the menu, on a fresh place
    O().ClearArrow()
    local fresh = Links(Shown("CHAT_MSG_PARTY", "/way Elwynn Forest 30 30 Mill"))[1].payload
    before = Count()
    Click(fresh, "RightButton")
    M.ClickMenu("Add without the arrow")
    EQ(Count(), before + 1, "H: Add without the arrow: a waypoint")
    CHECK(not (O().Active() and O().Active().why == "PINNED"), "H: ...the arrow not pinned to it",
        O().Active() and O().Active().why)
    Click(fresh, "RightButton")
    M.ClickMenu("Go")
    EQ(O().Active() and O().Active().title, "Mill", "H: Go from the menu: the arrow on it")
    EQ(Count(), before + 1, "H: ...the same waypoint")

    -- a link with no title: the waypoint says where it is
    local plain = Links(Shown("CHAT_MSG_GUILD", "Elwynn Forest 42 65", { guid = STRANGER }))[1].payload
    Click(plain)
    EQ(O().Active() and O().Active().title, nil, "H: no title in the link: none on the waypoint")
    Click(plain, "RightButton")
    EQ(M.menu[1] and M.menu[1].text, "Elwynn Forest 42.0, 65.0", "H: ...the menu heads with the place")

    -- not ours: another addon's link, another kind of Orders link
    M.ClearLog()
    before = Count()
    Click("addon:SomeoneElse:1:2:3")
    Click("addon:CommanderOrdersX:w:1944:0.5:0.5:x")
    Click("addon:CommanderOrders:x:1944:0.5:0.5:x")
    EQ(Count(), before, "H: other links change nothing")
    EQ(#M.prints + #M.popups + #M.chat, 0, "H: ...and say nothing")
    -- ours, to a map with no world position: GoTo's one refusal line
    Click("addon:CommanderOrders:w:99999:0.5:0.5:x")
    EQ(Count(), before, "H: a link to a map with no world position adds nothing")
    EQ(#M.prints, 1, "H: ...and says why, once")
    HAS(M.prints[1], "That map has no world coordinates", "H: ...in Orders' words")

    -- Orders off: the click says why, with the place and its link
    CommanderOrdersDB.EnableOrders = false
    M.ClearLog()
    Click(payload)
    EQ(Count(), before, "H: Orders off: nothing added")
    CHECK(M.Has(M.prints, "Commander Orders is turned off (/corder)"), "H: ...the one refusal line", M.prints[1])
    local refusal = M.prints[1]
    CommanderOrdersDB.EnableOrders = true
    O().Remove(uid)
    M.ClearLog()
    CHECK(M.ClickLink(refusal), "H: (the refusal line carries a link)")
    M.Advance(0.1)
    EQ(O().Active() and O().Active().title, "Boss", "H: ...which, clicked once Orders is back on, goes there")
    -- a module's own printed ChatLink, clicked off the chat frame
    M.ClearLog()
    print("Commander Something: the vendor " .. O().ChatLink(1429, 0.43, 0.66, "Vendor"))
    CHECK(M.ClickLink(M.prints[1]), "H: (a printed ChatLink)")
    M.Advance(0.1)
    EQ(O().Active() and O().Active().title, "Vendor", "H: a printed ChatLink goes there too")
    NOERR("H")
end)

-- ---------------------------------------------------------------------------
-- I  the hover
-- ---------------------------------------------------------------------------
Section("I", function()
    Boot()
    Party()
    local far = Links(Shown("CHAT_MSG_PARTY", "/way 45 66 Boss"))[1].payload
    local near = Links(Shown("CHAT_MSG_PARTY", "/way Elwynn Forest 42 66 Inn"))[1].payload
    local plain = Links(Shown("CHAT_MSG_GUILD", "Elwynn Forest 42 65", { guid = STRANGER }))[1].payload
    local frame = M.chatFrame
    Enter(far, frame)
    EQ(M.tooltip[1], "Boss", "I: the title")
    EQ(M.tooltip[2], "Hellfire Peninsula 45.0, 66.0", "I: the zone and the coordinates")
    EQ(M.tooltip[3], "In Outland", "I: on another landmass: which one")
    EQ(M.tooltip[4], "Click: Go. Shift-click: share. Ctrl-click: copy a /way line. Right-click: more.",
        "I: the four hints")
    EQ(GameTooltip:GetOwner(), frame, "I: owned by the chat frame")
    Enter(near, frame)
    CHECK(type(M.tooltip[3]) == "string" and M.tooltip[3]:match("^%d+ yd away$") ~= nil, "I: near: how far",
        M.tooltip[3])
    Enter(plain, frame)
    EQ(M.tooltip[1], "Elwynn Forest 42.0, 65.0", "I: no title: the place heads it")
    CommanderOrdersDB.CoordDecimals = 2
    Enter(plain, frame)
    EQ(M.tooltip[1], "Elwynn Forest 42.00, 65.00", "I: at the CoordDecimals setting")
    CommanderOrdersDB.CoordDecimals = 1
    Leave(frame)
    EQ(GameTooltip:GetOwner(), nil, "I: leaving hides it")
    -- someone else's tooltip is not ours to hide
    Enter(far, frame)
    local other = {}
    GameTooltip:SetOwner(other, "ANCHOR_RIGHT")
    Leave(frame)
    EQ(GameTooltip:GetOwner(), other, "I: a tooltip someone else took over stays")
    Enter(far, frame)
    Enter("item:12345:0", frame)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    Leave(frame)
    EQ(GameTooltip:GetOwner(), frame, "I: after hovering an item link, its tooltip is left to its owner")
    M.ClearLog()
    Enter("addon:SomeoneElse:1", frame)
    EQ(GameTooltip:GetOwner(), frame, "I: another addon's link: our tooltip code stays out")
    NOERR("I")
end)

-- ---------------------------------------------------------------------------
-- J  ClaimChatLink
-- ---------------------------------------------------------------------------
Section("J", function()
    Boot()
    local link = O().ChatLink(1429, 0.4, 0.5, "Pinged")
    local got = {}
    EQ(O().ClaimChatLink(link, function(place) got[#got + 1] = place end), true, "J: a printed link is claimed")
    local payload = link:match("|H(.-)|h")
    local before = Count()
    Click(payload)
    EQ(#got, 1, "J: its plain click is the claimer's")
    EQ(Count(), before, "J: ...and Orders adds nothing")
    CHECK(got[1] and got[1].map == 1429 and got[1].title == "Pinged" and math.abs(got[1].x - 0.4) < 1e-9,
        "J: ...handed the place")
    Click(payload, "RightButton")
    M.ClickMenu("Go")
    EQ(#got, 2, "J: the menu's Go is the claimer's too")
    Click(payload, "LeftButton", { "CTRL" })
    EQ(#got, 2, "J: Ctrl-click stays Orders' (copy)")
    EQ(O().R.ArrowState().copyText, "/way #1429 40.00 50.00 Pinged", "J: ...the copy box")
    -- a payload claims as well as the whole link
    local p2 = O().ChatLink(1429, 0.41, 0.5, "Two"):match("|H(.-)|h")
    EQ(O().ClaimChatLink(p2, function() got[#got + 1] = "two" end), true, "J: a payload is claimed too")
    Click(p2)
    EQ(got[#got], "two", "J: ...and answered")
    -- what is not a claim
    local ok, why = O().ClaimChatLink("addon:SomeoneElse:1", function() end)
    CHECK(ok == nil and type(why) == "string", "J: another addon's link cannot be claimed", why)
    ok = O().ClaimChatLink(link, nil)
    EQ(ok, nil, "J: nor without a function")
    ok = O().ClaimChatLink(nil, function() end)
    EQ(ok, nil, "J: nor nothing")
    -- the newest claim of a link wins, and survives its older slot's reuse
    local p3 = O().ChatLink(1429, 0.42, 0.5, "Three")
    O().ClaimChatLink(p3, function() got[#got + 1] = "old" end)
    O().ClaimChatLink(p3, function() got[#got + 1] = "new" end)
    -- (64 slots: link, p2, p3, p3 again, then 63 more reach p3's first slot)
    for i = 1, 63 do O().ClaimChatLink(O().ChatLink(1429, 0.5, i / 100, "filler"), function() end) end
    Click(p3:match("|H(.-)|h"))
    EQ(got[#got], "new", "J: claimed twice: the newest answers, even once the first slot is reused")
    -- 64 kept: the oldest is Orders' again
    before = Count()
    Click(payload)
    EQ(Count(), before + 1, "J: 64 claims later the first link falls back to Go (still knows its place)")
    EQ(O().Active() and O().Active().title, "Pinged", "J: ...a waypoint of yours there")
    -- a claimer that breaks
    M.ClearLog()
    local p4 = O().ChatLink(1429, 0.43, 0.5, "Broken")
    O().ClaimChatLink(p4, function() error("claimer broke") end)
    Click(p4:match("|H(.-)|h"))
    CHECK(M.Has(M.errors, "claimer broke"), "J: a claimer's error is reported", M.errors[1])
    M.ClearLog()
    -- claims last the session
    local p5 = O().ChatLink(1429, 0.44, 0.5, "Session")
    O().ClaimChatLink(p5, function() got[#got + 1] = "session" end)
    M.Reload({ skipFiles = SKIP, afterFiles = LoadChat, before = function() Stubs({}) end })
    local n = #got
    before = Count()
    Click(p5:match("|H(.-)|h"))
    EQ(#got, n, "J: after a reload the claim is gone")
    EQ(Count(), before + 1, "J: ...and the link still goes there")
    NOERR("J")
end)

-- ---------------------------------------------------------------------------
-- K  Linkify
-- ---------------------------------------------------------------------------
Section("K", function()
    Boot()
    Party()
    local text, n = O().Linkify("/way 45 66 camp", { chatType = "party", guid = ZULJIN })
    EQ(n, 1, "K: one link")
    CheckPlace(text, 1944, 0.45, 0.66, "camp", "K chatType + guid: the member's map")
    text, n = O().Linkify("/way 45 66", { event = "CHAT_MSG_WHISPER_INFORM" })
    CheckPlace(text, 1429, 0.45, 0.66, nil, "K event: your own whisper")
    text, n = O().Linkify("/way 45 66", { chatType = "SAY" })
    CheckPlace(text, 1429, 0.45, 0.66, nil, "K chatType SAY, no GUID: nearby, your map")
    text, n = O().Linkify("/way 45 66", nil)
    EQ(text, "/way 45 66", "K: no context, a bare /way: as it was")
    EQ(n, 0, "K: ...0")
    text, n = O().Linkify("Elwynn Forest 42 65")
    CheckPlace(text, 1429, 0.42, 0.65, nil, "K no context needed for Zone x, y")
    CommanderOrdersDB.ChatLinks = false
    text, n = O().Linkify("Elwynn Forest 42 65")
    CHECK(text == "Elwynn Forest 42 65" and n == 0, "K: Clickable Places off: as it was")
    CommanderOrdersDB.ChatLinks = true
    CommanderOrdersDB.EnableOrders = false
    text, n = O().Linkify("Elwynn Forest 42 65")
    CHECK(text == "Elwynn Forest 42 65" and n == 0, "K: Orders off: as it was")
    CommanderOrdersDB.EnableOrders = true
    text, n = O().Linkify(nil)
    CHECK(text == nil and n == 0, "K: not a string: handed back")
    NOERR("K")
end)

-- ---------------------------------------------------------------------------
-- L  globals (static)
-- ---------------------------------------------------------------------------
local ALLOWED_READ = {}
for name in ([[
type pairs ipairs pcall tostring tonumber print string table math
CommanderOrders C_Map ChatFrameUtil ChatFrame_AddMessageEventFilter EventRegistry GameTooltip UIParent
InCombatLockdown IsControlKeyDown IsShiftKeyDown IsInGroup UnitGUID UnitTokenFromGUID
geterrorhandler WorldMapFrame ToggleWorldMap ShowUIPanel
]]):gmatch("[%w_]+") do ALLOWED_READ[name] = true end
local ALLOWED_WRITE = { CommanderOrders = true }
Section("L", function()
    local pipe = assert(io.popen(string.format("%q -bl %q 2>/dev/null", LUAJIT, CHAT_FILE)))
    local seen, n = {}, 0
    for line in pipe:lines() do
        local op, name = line:match("(G[GS]ET)%s+%d+%s+%d+%s+;%s+\"([%w_]+)\"")
        if op and not seen[op .. name] then
            seen[op .. name] = true
            n = n + 1
            if op == "GGET" then
                CHECK(ALLOWED_READ[name], "L: reads only what it means to", name)
            else
                CHECK(ALLOWED_WRITE[name], "L: writes only CommanderOrders (its own fields)", name)
            end
        end
    end
    pipe:close()
    CHECK(n > 10, "L: (the bytecode listing was read)", n)
    -- no non-ASCII byte anywhere in the file (suite D11: no glyphs)
    local f = assert(io.open(CHAT_FILE, "rb"))
    local src = f:read("*a")
    f:close()
    EQ(src:find("[\128-\255]"), nil, "L: plain ASCII (D11)")
end)

-- ---------------------------------------------------------------------------
-- M  the full TOC
-- ---------------------------------------------------------------------------
Section("M", function()
    M.Boot({ player = GOLDSHIRE, skipFiles = {}, before = function() Stubs({}) end })
    local mine = {}
    for _, e in ipairs(M.loadErrors) do
        if e:find("CommanderOrdersChat", 1, true) then mine[#mine + 1] = e end
    end
    EQ(#mine, 0, "M: the chat file loads in its TOC slot", mine[1])
    local files = table.concat(M.TocFiles(), ",")
    HAS(files, "CommanderOrdersCoords,CommanderOrdersChat,CommanderOrdersUI", "M: ...after Coords, before UI")
    Party()
    local text = Shown("CHAT_MSG_PARTY", "/way 45 66 Boss")
    local link = CheckPlace(text, 1944, 0.45, 0.66, "Boss", "M full TOC")
    if link then
        Click(link.payload)
        EQ(O().Active() and O().Active().title, "Boss", "M: ...and its click goes there")
    end
    local chatErrors = {}
    for _, e in ipairs(M.errors) do
        if e:find("Chat", 1, true) or e:find("chat filter", 1, true) then chatErrors[#chatErrors + 1] = e end
    end
    EQ(#chatErrors, 0, "M: no chat error beside the other files", chatErrors[1])
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

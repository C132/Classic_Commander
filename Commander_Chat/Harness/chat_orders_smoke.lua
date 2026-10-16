-- Commander Chat's replacement window + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Chat/Harness/chat_orders_smoke.lua
--     CHAT_FRAME=/tmp/mutant.lua luajit ...        (a mutated CommanderChatFrame.lua)
--
-- chat_smoke.lua drives the window's link scripts against a recording
-- EventRegistry. This boots the real Orders (its chat file included) over the
-- client mock Orders' own harnesses share (Commander_Orders/Harness/
-- orders_mock.lua, whose EventRegistry calls fn(owner, ...) the way
-- CallbackRegistryMixin does) and loads the window's two files after it. The
-- rest of Commander Chat hooks Blizzard's ChatFrame1, which that mock does
-- not build, so a mirrored line is handed to the window the way the AddMessage
-- hook hands it (CommanderChatWindow_Receive):
--   A  loads clean beside Orders; the window builds when asked for
--   B  a line Orders' chat filter linked, mirrored into the window: hovering
--      its [Go] shows Orders' own card (the place and the gestures), leaving
--      it takes the card away, and a click is Orders' Go
--   C  Orders' printed [Go] (a waypoint refusal's) hovers the same way
--   D  an item link in the window is still the tooltip's own

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
    local mutant = os.getenv("CHAT_FRAME")
    local files = { "CommanderChatDB.lua" }
    if not mutant then files[#files + 1] = "CommanderChatFrame.lua" end
    M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        before = function()
            if rawget(_G, "ChatFontNormal") == nil and not ChatFontNormal then
                local font = CreateFrame("Frame")
                font.GetFont = function() return "Fonts\\FRIZQT__.TTF", 14, "" end
                rawset(_G, "ChatFontNormal", font)
            end
        end,
        addons = { { name = "Commander_Chat", files = files } },
        afterFiles = function()
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
        end,
        saved = { CommanderChatDB = { Enabled = true, ReplaceChatFrame = true } },
    })
    CommanderChatWindow_Update()
    return rawget(_G, "CommanderChatWindowBody")
end

local function O() return rawget(_G, "CommanderOrders") end
local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Tip() return table.concat(M.tooltip, "\n") end
local function ClearTip() for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end end

-- ===========================================================================
Section("A", function()
    local body = Boot()
    NoErrors("A")
    CHECK(body ~= nil, "A: the replacement window built (ReplaceChatFrame on)")
    EQ(CommanderChatWindow_IsActive(), true, "A: ...and is the active window")
    CHECK(type(O()) == "table" and type(O().ChatLink) == "function", "A: (Orders with its chat file)")
end)

-- ===========================================================================
Section("B", function()
    local body = Boot()
    -- A guild line through Orders' own chat filter, then mirrored
    local _, text = M.RunChatFilters("CHAT_MSG_GUILD", "meet at Elwynn Forest 42.5, 61.2", "Zuljin",
        "", "", "Zuljin", "", 0, 0, "", 0, 7001, "Player-1-Zuljin")
    local link, shown = tostring(text):match("|H(addon:CommanderOrders:[^|]+)|h(.-)|h")
    CHECK(link ~= nil, "B: (Orders' filter linked the line)", text)
    if not link then return end
    local added
    rawset(body, "AddMessage", function(_, line) added = line end)
    CommanderChatWindow_Receive(text, 0.25, 1, 0.25)
    EQ(added, text, "B: the linked line is in the window")
    ClearTip()
    body.__scripts.OnHyperlinkEnter(body, link, shown)
    local tip = Tip()
    CHECK(tip:find("Elwynn Forest", 1, true) and tip:find("Click: Go.", 1, true),
        "B: hovering its [Go] in the window shows Orders' card (place and gestures)", tip)
    EQ(GameTooltip:GetOwner(), body, "B: ...owned by the window")
    body.__scripts.OnHyperlinkLeave(body, link, shown)
    CHECK(GameTooltip.__shown == false and GameTooltip:GetOwner() == nil, "B: leaving it takes the card away")
    -- A click from the window is Orders' Go
    M.ClearLog()
    body.__scripts.OnHyperlinkClick(body, link, shown, "LeftButton")
    M.Frame()
    local mine = O().List({ source = "user" })[1]
    CHECK(mine and mine.map == 1429 and math.abs(mine.x - 0.425) < 1e-4, "B: a click is Orders' Go, to that spot")
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    local body = Boot()
    local printed = O().ChatLink(1429, 0.30, 0.40, "Rare spawn")
    CHECK(type(printed) == "string" and printed:find("|Haddon:CommanderOrders:", 1, true), "C: (Orders' printed link)", printed)
    local link, shown = tostring(printed):match("|H(.-)|h(.-)|h")
    CommanderChatWindow_Receive("Commander Orders: no route " .. printed)
    ClearTip()
    body.__scripts.OnHyperlinkEnter(body, link, shown)
    CHECK(Tip():find("Rare spawn", 1, true), "C: a printed [Go] hovers to Orders' card, titled", Tip())
    body.__scripts.OnHyperlinkLeave(body, link, shown)
    NoErrors("C")
end)

-- ===========================================================================
Section("D", function()
    local body = Boot()
    local asked
    GameTooltip.SetHyperlink = function(_, l) asked = l end
    ClearTip()
    body.__scripts.OnHyperlinkEnter(body, "item:19019", "[Thunderfury]")
    EQ(asked, "item:19019", "D: an item link is the tooltip's own")
    EQ(#M.tooltip, 0, "D: ...and Orders draws nothing for it")
    body.__scripts.OnHyperlinkLeave(body, "item:19019", "[Thunderfury]")
    NoErrors("D")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)

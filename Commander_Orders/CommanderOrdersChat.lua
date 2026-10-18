-- Commander Orders: places in chat you can click (3.1, SPEC 4 "CHAT").
--
-- Two jobs:
--   * A [Go] link after the places people type in chat: a /way line (tier A,
--     "/way Hellfire Peninsula 45 66 Boss", "/way 45 66" on the sender's
--     zone) and "Zone x, y" (tier B, "Elwynn Forest 42.1, 65.9", the shape
--     Commander Comms' rally line and Orders' own shared line have). There
--     is no bare "x, y" tier: "2, 3 more" in Trade is not a place. Behind the
--     ChatLinks setting, read per line, so turning it off needs no reload.
--   * The answer to every Orders chat link, however it reached a chat frame:
--     this filter's, or a CommanderOrders.ChatLink a module printed (a
--     refused Go, the share fallback, Commander Ping's callout), on any frame
--     that hands its link clicks to SetItemRef (the chat frames, Commander
--     Chat's window, Commander Contacts' rows).
--
-- The gestures are Orders' one rule for a coordinate surface (DECISIONS):
--   Click        Go: a waypoint there, the arrow on it (CommanderOrders.GoTo,
--                source "user": what typing that /way would make)
--   Shift-click  share: with a chat box open, the readable line typed into it
--                (ChatText, never the link); otherwise posted in chat the way
--                a GoButton shares (your group's chat, else /say)
--   Ctrl-click   the /way line in the copy box
--   Right-click  a menu: Go, Add without the arrow, Open the map here, Share
--                with group, Post in chat, Copy /way line, Save as place
--   Hover        a tooltip: the title, the zone and coordinates, how far, and
--                the four hints
--
-- ---------------------------------------------------------------------------
-- How a link click travels on 2.5.6 (read in the client's own Lua, build
-- 2.5.6.69795; coords.md 2.1 traced it, re-read for this file)
-- ---------------------------------------------------------------------------
-- * ChatFrameTemplate's OnHyperlinkClick is ChatFrameMixin:OnHyperlinkClick
--   (Blizzard_ChatFrameBase/Classic/ChatFrame.xml), which fires EventRegistry
--   "ChatFrame.OnHyperlinkClick" and then SetItemRef(link, text, button,
--   self) (Shared/ChatFrame.lua). `link` is the part between |H and |h.
-- * SetItemRef (Blizzard_UIPanels_Game/Classic/ItemRef.lua, loaded on TBC by
--   Blizzard_UIPanels_Game_Classic.toc) hands it to LinkUtil.ProcessLink,
--   which splits the type at the first ":" and calls the registered handler;
--   a handler answering nil counts as Handled, and SetItemRef returns before
--   ItemRefTooltip or HandleModifiedItemClick ever see the link.
-- * The "addon" type's handler (Shared/ItemRefHandlersShared.lua, "local
--   links only") is EventRegistry:TriggerEvent("SetItemRef", link, text,
--   button, frame). EventRegistry is a CallbackRegistryMixin that allows
--   undefined events; it keeps ONE callback per owner per event and calls a
--   function callback as fn(owner, ...) inside securecallfunction
--   (Blizzard_SharedXMLBase/CallbackRegistry.lua). So the owner here is a
--   table of this file's own, and nothing is hooked or replaced: no
--   hooksecurefunc("SetItemRef"), no ItemRefTooltip override, no LinkUtil
--   handler of our own (RegisterLinkHandler asserts on a duplicate type).
--   ChatFrame_OnHyperlinkShow does not exist on this client.
-- * Hover: OnHyperlinkEnter / OnHyperlinkLeave only fire EventRegistry
--   "ChatFrame.OnHyperlinkEnter" (frame, link, text, ...) and
--   "ChatFrame.OnHyperlinkLeave" (frame). The tooltip is ours to show, and
--   on Leave it is hidden only when it is still the one we showed.
-- * A link never leaves this client. What is sent is ChatText (Orders' Share
--   and the Shift-click), and every Commander reader turns its "(/way ...)"
--   back into a link here.
--
-- ---------------------------------------------------------------------------
-- The filter's traps (critic D10, coords.md 2.3-2.4, ChatFrameFilters.lua)
-- ---------------------------------------------------------------------------
-- * ChatFrameUtil.AddMessageEventFilter first; ChatFrame_AddMessageEventFilter
--   is only a deprecation shim behind the loadDeprecationFallbacks CVar.
-- * A filter that returns a new text must hand back all fourteen arguments:
--   ProcessFilters replaces arg1-arg14 together, and `return false, text`
--   alone would wipe the sender, the lineID and the GUID.
-- * The filter runs once per chat frame that shows the event: the result is
--   kept by lineID (arg11), the last 64 lines, so the second window costs a
--   table lookup.
-- * Only plain text is read. A link (|H...|h...|h), a colour (|c to |r, links
--   inside it and all), a texture, atlas or kstring and a {...} expression
--   are stepped over whole, so a [Go] is never put inside someone else's
--   link or colour (our link ends in |r).
-- * After the filters Blizzard doubles every % for format, rewrites {...}
--   into icons (C_ChatInfo.ReplaceIconAndGroupExpressions) and collapses
--   runs of spaces (ChatFrameOverrides.lua MessageFormatter). The link's
--   payload therefore holds no brace (a title loses them here), no | and no
--   run of spaces (Geo.ChatLink %XX-escapes and PlainText collapses); the %
--   of an escape comes back out of format as it went in.
-- * Quick reject: every place has a digit, so a line without one costs one
--   character-class find and nothing else runs. Errors never escape: the
--   scan runs under pcall and an error leaves the line as it was.
-- * The display text is "[Go]": Commander Chat's short channel tags rewrite
--   "[<digits>.<anything>]" on finished lines, so a link text must not start
--   with digits and a dot.
--
-- Context for a /way with no zone ("/way 45 66"): your own line (the
-- *_INFORM echoes, your GUID) and SAY, YELL, EMOTE and the zone's General
-- and LocalDefense channels (zoneChannelID 1 and 22, ASSUMED: ChatChannels
-- ids from the classic data, not read on this build) mean your map; a group
-- member's line means theirs (C_Map.GetBestMapForUnit); anything else, no
-- link. The map is taken up to its zone (people read zone coordinates off
-- the world map), and it is written into the link, so a later click never
-- guesses again.
--
-- ---------------------------------------------------------------------------
-- API (added to CommanderOrders by this file)
-- ---------------------------------------------------------------------------
--   CommanderOrders.Linkify(text, ctx) -> text with [Go] links, count. The
--       filter's core for text that never passed the chat filters (Commander
--       Contacts' logged lines). ctx = { event = "CHAT_MSG_PARTY" (or
--       chatType = "PARTY"), guid = sender GUID, zoneChannelID }. Says
--       nothing new (text, 0) when ChatLinks or Orders is off.
--   CommanderOrders.ClaimChatLink(link, fn) -> true | nil, reason. A module
--       that printed a ChatLink and wants that link's plain click (and the
--       menu's Go) for itself while this session lasts: fn(place) runs
--       instead of the default Go; Shift, Ctrl and Right stay Orders'. The
--       last 64 claims are kept; an older or reloaded link falls back to the
--       default Go, which still knows the place. Commander Ping claims its
--       callout so a click moves its one "Ping" waypoint.
--   CommanderOrders.Chat (harness surface): Filter, OnLink, OnEnter,
--       OnLeave, Scan, PlainSpans, Menu, EVENTS.
--
-- Globals written: none (CommanderOrders' fields only). A new file in the
-- TOC: a full client restart, not a /reload.

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
local G = O.Geo
local D = O.Data
O.R = O.R or {}
local R = O.R
O.Chat = O.Chat or {}
local C = O.Chat

local type, pairs, ipairs, pcall, tostring, tonumber = type, pairs, ipairs, pcall, tostring, tonumber
local strfind, strsub, strlower, strmatch = string.find, string.sub, string.lower, string.match
local tconcat, tsort = table.concat, table.sort
local abs, min = math.abs, math.min

local PREFIX = (G and G.LINK_PREFIX) or "addon:CommanderOrders:"
local MAX_LINKS = 4            -- [Go] links one line may gain
local TITLE_MAX = 60           -- bytes of a typed /way title carried in a link
local CACHE_SIZE = 64          -- chat lines remembered by lineID
local CLAIMS_KEPT = 64         -- ClaimChatLink claims remembered
local ZONE_WORDS = 4           -- words before a pair that may name its zone
local ALIAS_MIN = 4            -- a folded alias shorter than this is an English word ("if", "am", "bl")
-- A "Zone x, y" this close to a /way place on the same map is that place
-- (Orders' own shared line says both; its readable pair is rounded to
-- CoordDecimals, 0 at the coarsest, so half a map-percent)
local SAME_PLACE = 0.006

-- The chat events a place may arrive in (coords.md 2.6). Not MONSTER_*,
-- SYSTEM or LOOT: nobody types a /way there.
local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL",
}
C.EVENTS = EVENTS

local OWN_EVENTS = { CHAT_MSG_WHISPER_INFORM = true, CHAT_MSG_BN_WHISPER_INFORM = true }
local NEARBY_EVENTS = { CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_EMOTE = true }
local LOCAL_CHANNELS = { [1] = true, [22] = true }      -- General, LocalDefense (ASSUMED ids)
local WAY_WORDS = { ["/way"] = true, ["/tway"] = true, ["/tomtomway"] = true }

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local reported = 0
local function Report(err)
    -- a broken scan would otherwise report on every line of Trade
    if reported >= 5 then return end
    reported = reported + 1
    if geterrorhandler then
        local handler = geterrorhandler()
        if handler then handler(err) end
    end
end

local function DB()
    local db = type(R.DB) == "function" and R.DB()
    if type(db) == "table" then return db end
    return O.Defaults or {}
end

local function Say(msg)
    if type(R.Say) == "function" then R.Say(msg) else print("Commander Orders: " .. msg) end
end

-- Orders loaded, its store read and switched on
local function Ready()
    if not G or type(R.Store) ~= "function" or not R.Store() then return false end
    return DB().EnableOrders and true or false
end

local function Env()
    return type(R.Env) == "function" and R.Env() or nil
end

local function MapName(map)
    return type(R.MapName) == "function" and R.MapName(map) or nil
end

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Cut to n bytes on a UTF-8 boundary, with "..." when cut (D11: plain dots)
local function Cut(s, n, dots)
    if type(s) ~= "string" or #s <= n then return s end
    local cut = dots and (n - 3) or n
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut) .. (dots and "..." or "")
end

-- A title as a link may carry it: plain words, no brace (Blizzard rewrites
-- {...} after the filters, payload or not), at most TITLE_MAX bytes
local function CleanTitle(t)
    if type(t) ~= "string" then return nil end
    t = G.PlainText(t):gsub("{[^}]*}", ""):gsub("[{}]", "")
    t = Trim(Cut(Trim(t), TITLE_MAX))
    if t == "" then return nil end
    return t
end

-- "Elwynn Forest 42.1, 65.9" at the CoordDecimals setting
local function Where(place)
    local coords = (type(O.FormatCoords) == "function" and O.FormatCoords(place.x, place.y))
        or G.FormatCoords(place.x, place.y, 1) or ""
    return (MapName(place.map) or ("map #" .. tostring(place.map))) .. " " .. coords
end

-- A place the arrow could point at: a map the client knows, with a world
-- position at that spot (Dire Maul's map 234 has none: a Go there would only
-- refuse, and there is no link that does nothing)
local function Linkable(place)
    if not MapName(place.map) then return false end
    if type(R.PosWorld) ~= "function" then return false end
    return R.PosWorld(place) ~= nil
end

-- ---------------------------------------------------------------------------
-- The zone index (the /way resolver's, built once, on the first line that
-- needs it) and the resolver /way itself uses
-- ---------------------------------------------------------------------------
local index
local function Index()
    if index == nil then
        local env = Env()
        if not (env and G.ZoneIndex) then return nil end
        local built = G.ZoneIndex(env, D and D.ZONE_ALIASES)
        -- the map tree not answering yet (a line before login): try again later
        if type(built) ~= "table" or #built.entries == 0 then return nil end
        index = built
    end
    return index
end

-- Name, alias, prefix, part of a name (G.MatchZone), then the zone resolvers
-- other modules register: what /way accepts. Ambiguous answers no map.
local function Resolver(text)
    local idx = Index()
    if idx then
        local map, candidates = G.MatchZone(idx, text)
        if map then return map end
        if type(candidates) == "table" and #candidates > 0 then return nil, candidates end
    end
    local other = type(R.Resolve) == "function" and R.Resolve("zone", text)
    if type(other) == "number" then return other end
    return nil, {}
end

-- ---------------------------------------------------------------------------
-- Whose map a bare "/way 45 66" means
-- ---------------------------------------------------------------------------
local function BestMap(unit)
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, unit)
    if ok and type(map) == "number" then return map end
    return nil
end

local function GroupUnit(guid)
    if UnitTokenFromGUID then
        local ok, unit = pcall(UnitTokenFromGUID, guid)
        if ok and type(unit) == "string" and (strfind(unit, "^party%d$") or strfind(unit, "^raid%d+$")) then
            return unit
        end
    end
    if type(R.UnitForGuid) == "function" then return R.UnitForGuid(guid) end
    return nil
end

local function ContextMap(ctx)
    if ctx.done then return ctx.map end
    ctx.done = true
    local event, guid = ctx.event, ctx.guid
    if type(guid) ~= "string" or guid == "" then guid = nil end
    local me = UnitGUID and UnitGUID("player")
    local unit
    if OWN_EVENTS[event] or (guid and guid == me) then
        unit = "player"
    elseif guid then
        unit = GroupUnit(guid)
    end
    if not unit and (NEARBY_EVENTS[event]
            or (event == "CHAT_MSG_CHANNEL" and LOCAL_CHANNELS[tonumber(ctx.zoneChannelID) or -1])) then
        unit = "player"
    end
    local map = unit and BestMap(unit)
    if map then map = G.Zone(Env(), map) or map end
    ctx.map = map
    return map
end

-- ---------------------------------------------------------------------------
-- The scan: plain stretches, then /way lines (A), then "Zone x, y" (B)
-- ---------------------------------------------------------------------------
-- The plain-text stretches of a line, { { first, last }, ... }: everything
-- but a link, a colour run (to its |r, links inside it and all), a texture,
-- atlas or kstring, any other two-byte escape and a {...} expression. An
-- escape left open protects the rest of the line; a lone "{" only itself.
function C.PlainSpans(text)
    local spans, n = {}, #text
    local from, pos = 1, 1
    while pos <= n do
        local s = strfind(text, "[|{]", pos)
        if not s then break end
        local e
        if strsub(text, s, s) == "{" then
            e = strfind(text, "}", s + 1, true) or s
        else
            local k = strsub(text, s + 1, s + 1)
            if k == "H" then
                local h1 = strfind(text, "|h", s + 2, true)
                local h2 = h1 and strfind(text, "|h", h1 + 2, true)
                e = h2 and (h2 + 1) or n
            elseif k == "c" then
                local r = strfind(text, "|r", s + 2, true)
                e = r and (r + 1) or n
            elseif k == "T" or k == "A" or k == "K" then
                local close = strfind(text, "|" .. strlower(k), s + 2, true)
                e = close and (close + 1) or n
            else
                e = s + 1
            end
        end
        if s > from then spans[#spans + 1] = { from, s - 1 } end
        from = e + 1
        pos = e + 1
    end
    if from <= n then spans[#spans + 1] = { from, n } end
    return spans
end

-- Words of text[first..last] with their positions
local function Tokens(text, first, last)
    local out, pos = {}, first
    while pos <= last do
        local s, e = strfind(text, "%S+", pos)
        if not s or s > last then break end
        if e > last then e = last end
        out[#out + 1] = { text = strsub(text, s, e), s = s, e = e }
        pos = e + 1
    end
    return out
end

-- "/way", "/tway", "/tomtomway", any case, maybe opening a parenthesis
local function WayWord(word)
    local w = strlower(word)
    local open = strsub(w, 1, 1) == "("
    if open then w = strsub(w, 2) end
    return WAY_WORDS[w] == true, open
end

-- Orders' own shared line, "Title - Zone 45.2, 66.8 (/way #1944 45.20
-- 66.80)": its /way part has no title, the words before " - " are it
local function ShareTitle(text, first, last)
    if last < first then return nil end
    local t = strmatch(strsub(text, first, last), "^%s*(.-)%s+%-%s+[^%-]-%d[%d%.]*,?%s*%d[%d%.]*%s*$")
    return CleanTitle(t)
end

-- A /way segment as a place, or nil
local function WayPlace(segment, ctx)
    local cmd = G.ParseWay(segment, Resolver)
    if type(cmd) ~= "table" or cmd.kind ~= "ADD" then return nil end
    local map = cmd.map
    if map == nil then map = ContextMap(ctx) end
    if type(map) ~= "number" then return nil end
    local place = { map = map, x = cmd.x, y = cmd.y, title = CleanTitle(cmd.title) }
    if not Linkable(place) then return nil end
    return place
end

-- A /way segment without what ends the sentence around it: trailing
-- punctuation ("66!") and a ")" that closes a "(" opened before the /way
-- ("(see /way 45 66)"); a title's own "(rare)" keeps its ")"
local function Unpunctuated(segment)
    while true do
        local cut = segment:gsub("[%s%.,;:!%?]+$", "")
        local _, opens = cut:gsub("%(", "")
        local _, closes = cut:gsub("%)", "")
        if closes > opens and strsub(cut, -1) == ")" then cut = strsub(cut, 1, -2) end
        if cut == segment then return cut end
        segment = cut
    end
end

-- Tier A over one stretch: each /way runs to the next /way word or the end
-- of the stretch, or, opened by "(", to its ")". The link goes after it.
local function ScanWays(text, span, ctx, found)
    local tokens, covered = span.tokens, span.covered
    local ways = {}
    for i, tok in ipairs(tokens) do
        local isWay, open = WayWord(tok.text)
        if isWay then ways[#ways + 1] = { i = i, open = open } end
    end
    for n, w in ipairs(ways) do
        local tok = tokens[w.i]
        local segFirst = tok.s + (w.open and 1 or 0)
        local segLast = ways[n + 1] and (tokens[ways[n + 1].i].s - 1) or span[2]
        local at
        if w.open then
            local close = strfind(text, ")", tok.e + 1, true)
            if close and close <= segLast then
                segLast, at = close - 1, close
            end
        end
        local stop = at or segLast
        for j = w.i, #tokens do
            if tokens[j].s > stop then break end
            covered[j] = true
        end
        local segment = Unpunctuated(strsub(text, segFirst, segLast))
        if segment ~= "" then
            if not at then at = segFirst + #segment - 1 end
            local place = WayPlace(segment, ctx)
            if place then
                if not place.title and w.open then place.title = ShareTitle(text, span[1], tok.s - 1) end
                place.at, place.tier = at, "A"
                found[#found + 1] = place
            end
        end
    end
end

-- 0..100 from "45", "45.2" or "45."
local function Percent(s)
    if not strfind(s, "^%d+%.?%d*$") then return nil end
    local v = tonumber(s)
    if v and v >= 0 and v <= 100 then return v end
    return nil
end

-- What may follow the second number: nothing, a ")" and sentence
-- punctuation ("12:30", "45g", "66yd", "50%" are not coordinates)
local function TailOK(tail)
    return tail == "" or strfind(tail, "^%)?[%.,;:!%?]*$") ~= nil
end

-- A coordinate pair starting at token i: "45.2, 66.8", "45 66", "45.2,66.8",
-- "(45.2, 66.8)". x, y (0..100), the index of its last token and the byte
-- after which a link goes; nil when it is not one.
local function ReadPair(tokens, i, covered)
    local tok = tokens[i]
    local t, lead = tok.text, 0
    if strsub(t, 1, 1) == "(" then t, lead = strsub(t, 2), 1 end
    local a, b, tail = strmatch(t, "^(%d+%.?%d*),(%d+%.?%d*)(.*)$")
    if a then
        local x, y = Percent(a), Percent(b)
        if not (x and y and TailOK(tail)) then return nil end
        -- "45,2 66,8" is two decimal commas, not the pair 45, 2
        local nextTok = tokens[i + 1]
        if nextTok and strfind(nextTok.text, "^%d") then return nil end
        local at = tok.s + lead + #a + #b
        if strsub(tail, 1, 1) == ")" then at = at + 1 end
        return x, y, i, at
    end
    local a2 = strmatch(t, "^(%d+%.?%d*),?$")
    local x = a2 and Percent(a2)
    local nt = tokens[i + 1]
    if not (x and nt) or covered[i + 1] then return nil end
    local b2, tail2 = strmatch(nt.text, "^(%d+%.?%d*)(.*)$")
    local y = b2 and Percent(b2)
    if not (y and TailOK(tail2)) then return nil end
    local at = nt.s + #b2 - 1
    if strsub(tail2, 1, 1) == ")" then at = at + 1 end
    return x, y, i + 1, at
end

-- The zone the words just before token i name, exactly: the longest run of
-- up to ZONE_WORDS words that folds to one zone's name, or to an alias of
-- ALIAS_MIN letters or more. One punctuation word (":", "-", "(", ",") may
-- stand between the name and the numbers.
local function ZoneBefore(tokens, i, covered)
    local idx = Index()
    if not idx then return nil end
    local k = i - 1
    if k >= 1 and not covered[k] and strfind(tokens[k].text, "^[,:%-%(]+$") then k = k - 1 end
    for n = min(ZONE_WORDS, k), 1, -1 do
        local parts, ok = {}, true
        for m = k - n + 1, k do
            if covered[m] then ok = false break end
            parts[#parts + 1] = tokens[m].text
        end
        if ok then
            local folded = G.FoldName(tconcat(parts, " "))
            local hits = idx.byFolded[folded]
            if hits and #hits == 1 then return hits[1].map end
            if #folded >= ALIAS_MIN and idx.aliases[folded] then return idx.aliases[folded] end
        end
    end
    return nil
end

local function NearA(found, place)
    for _, p in ipairs(found) do
        if p.tier == "A" and p.map == place.map and abs(p.x - place.x) <= SAME_PLACE
            and abs(p.y - place.y) <= SAME_PLACE then
            return true
        end
    end
    return false
end

-- Tier B over one stretch, outside every /way segment
local function ScanPairs(span, found)
    local tokens, covered = span.tokens, span.covered
    local i = 1
    while i <= #tokens do
        local step = 1
        if not covered[i] then
            local x, y, j, at = ReadPair(tokens, i, covered)
            if x then
                local map = ZoneBefore(tokens, i, covered)
                if map then
                    step = j - i + 1
                    local place = { map = map, x = x / 100, y = y / 100, at = at, tier = "B" }
                    if Linkable(place) and not NearA(found, place) then found[#found + 1] = place end
                end
            end
        end
        i = i + step
    end
end

-- Every place in a line, in the order they appear: { map, x, y, title, at,
-- tier }. ctx: { event, guid, zoneChannelID } (for a bare /way).
function C.Scan(text, ctx)
    local found = {}
    if type(text) ~= "string" or text == "" or not G then return found end
    ctx = type(ctx) == "table" and ctx or {}
    local spans = C.PlainSpans(text)
    for _, span in ipairs(spans) do
        span.tokens = Tokens(text, span[1], span[2])
        span.covered = {}
    end
    for _, span in ipairs(spans) do ScanWays(text, span, ctx, found) end
    for _, span in ipairs(spans) do ScanPairs(span, found) end
    tsort(found, function(a, b) return a.at < b.at end)
    return found
end

-- text with a [Go] link after each place (at most MAX_LINKS), or nil
local function Rewrite(text, ctx)
    local found = C.Scan(text, ctx)
    if #found == 0 then return nil, 0 end
    local parts, prev, count = {}, 1, 0
    for _, p in ipairs(found) do
        if count >= MAX_LINKS then break end
        local link = G.ChatLink(p.map, p.x, p.y, p.title)
        if link then
            parts[#parts + 1] = strsub(text, prev, p.at)
            parts[#parts + 1] = " " .. link
            prev = p.at + 1
            count = count + 1
        end
    end
    if count == 0 then return nil, 0 end
    parts[#parts + 1] = strsub(text, prev)
    return tconcat(parts), count
end

-- ---------------------------------------------------------------------------
-- The message filter
-- ---------------------------------------------------------------------------
local cache, ring, ringAt = {}, {}, 0

local function Remember(lineID, orig, out)
    ringAt = ringAt % CACHE_SIZE + 1
    local old = ring[ringAt]
    if old ~= nil and cache[old] and cache[old].slot == ringAt then cache[old] = nil end
    ring[ringAt] = lineID
    cache[lineID] = { orig = orig, out = out or false, slot = ringAt }
end

-- ChatFrameUtil's filter: (chatFrame, event, arg1..arg14) -> discard?, and
-- when the text changed, all fourteen arguments back
function C.Filter(_, event, msg, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14)
    if type(msg) ~= "string" or not strfind(msg, "%d") then return false end
    if DB().ChatLinks == false or not Ready() then return false end
    local out
    local id = (type(a11) == "number" and a11 > 0) and a11 or nil
    local hit = id and cache[id]
    if hit and hit.orig == msg then
        out = hit.out
    else
        local ok, text = pcall(Rewrite, msg, { event = event, guid = a12, zoneChannelID = a7 })
        if not ok then
            Report(text)
            text = nil
        end
        out = text or false
        if id then Remember(id, msg, out) end
    end
    if not out then return false end
    return false, out, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14
end

-- ---------------------------------------------------------------------------
-- Claims (CommanderOrders.ClaimChatLink)
-- ---------------------------------------------------------------------------
local claims, claimRing, claimAt = {}, {}, 0

-- The "addon:CommanderOrders:..." payload of a link or of a payload
local function PayloadOf(link)
    if type(link) ~= "string" then return nil end
    if strsub(link, 1, #PREFIX) == PREFIX then return link end
    local payload = strmatch(link, "|H(.-)|h")
    if payload and strsub(payload, 1, #PREFIX) == PREFIX then return payload end
    return nil
end

local function Claim(link, fn)
    local payload = PayloadOf(link)
    if not payload or not G.ParseChatLink(payload) then return nil, "not a Commander Orders link" end
    if type(fn) ~= "function" then return nil, "no function" end
    claimAt = claimAt % CLAIMS_KEPT + 1
    local old = claimRing[claimAt]
    if old ~= nil and claims[old] and claims[old].slot == claimAt then claims[old] = nil end
    claimRing[claimAt] = payload
    claims[payload] = { fn = fn, slot = claimAt }
    return true
end

-- ---------------------------------------------------------------------------
-- What a click does
-- ---------------------------------------------------------------------------
local function Spec(place)
    return { map = place.map, x = place.x, y = place.y, title = place.title }
end

-- Go: the claim, else a waypoint of yours there with the arrow on it (what
-- typing the /way would do; clicking it again finds the same one)
local function Go(place, payload)
    local claim = payload and claims[payload]
    if claim then
        local ok, err = pcall(claim.fn, Spec(place))
        if not ok then Report(err) end
        return
    end
    if type(O.GoTo) == "function" then O.GoTo(Spec(place), { source = "user" }) end
end

local function AddQuiet(place)
    if type(O.GoTo) == "function" then O.GoTo(Spec(place), { source = "user", setArrow = false }) end
end

local function Copy(place)
    if not (type(O.CopyText) == "function" and type(O.WayLineFor) == "function") then return end
    O.CopyText(O.WayLineFor(place.map, place.x, place.y, place.title))
end

local function Post(place)
    if type(O.SharePoint) ~= "function" then return end
    local ok, why = O.SharePoint(Spec(place), "CHAT")
    if not ok then Say("could not share: " .. O.Reason(why)) end
end

local function ShareGroup(place)
    if type(O.SharePoint) ~= "function" then return end
    local ok, why = O.SharePoint(Spec(place), "GROUP")
    if not ok then Say("could not share: " .. O.Reason(why)) end
end

-- Shift: into the chat box being typed in, as words (a link would not
-- survive the trip); with none open, posted in chat
local function Share(place)
    local util = ChatFrameUtil
    local box = type(util) == "table" and type(util.GetActiveWindow) == "function" and util.GetActiveWindow()
    if box then
        local text = type(O.ChatText) == "function" and O.ChatText(place.map, place.x, place.y, place.title)
        if type(text) == "string" then
            if type(util.InsertLink) == "function" then
                util.InsertLink(text)
            elseif box.Insert then
                box:Insert(text)
            end
            return
        end
    end
    Post(place)
end

-- The world map at the link's zone. NOT OpenWorldMap: on 2.5.6 it is
-- WorldMapFrame:HandleUserActionOpenSelf(mapID) (TBC/Blizzard_WorldMap.lua
-- 324-326), a method only the Wrath file set defines (QuestLogOwnerMixin;
-- Blizzard_WorldMap_TBC.toc does not load it), so it raised every time
-- (review: blizzard). The player's own path instead, as Commander_QuestLog's
-- "Show on map" does: ToggleWorldMap (HandleUserActionToggleSelf, which
-- keeps the mini-map setting) when the map is shut, then SetMapID.
local function MapFrame()
    local map = WorldMapFrame
    if type(map) == "table" and type(map.SetMapID) == "function" then return map end
    return nil
end

local function OpenMap(place)
    if InCombatLockdown and InCombatLockdown() then
        Say("the map can be opened after combat")
        return
    end
    local map = MapFrame()
    if not map then return end
    local ok, err = pcall(function()
        if not (map.IsShown and map:IsShown()) then
            if type(ToggleWorldMap) == "function" then
                ToggleWorldMap()
            elseif type(ShowUIPanel) == "function" then
                ShowUIPanel(map)
            end
        end
        map:SetMapID(place.map)
    end)
    if not ok then Report(err) end
end

local function SavePlace(place)
    if type(O.MarkPlace) ~= "function" then return end
    local index2, why = O.MarkPlace(place.title or Where(place), { map = place.map, x = place.x, y = place.y })
    if not index2 then Say("could not save that place: " .. O.Reason(why)) end
end

function C.Menu(place, payload)
    if type(R.ShowMenu) ~= "function" then return false end
    local entries = { { text = Cut(place.title or Where(place), 40, true), isTitle = true } }
    entries[#entries + 1] = { text = "Go", func = function() Go(place, payload) end }
    entries[#entries + 1] = { text = "Add without the arrow", func = function() AddQuiet(place) end }
    if MapFrame() then
        entries[#entries + 1] = { text = "Open the map here", func = function() OpenMap(place) end,
            disabled = (InCombatLockdown and InCombatLockdown()) and true or nil }
    end
    if IsInGroup and IsInGroup() then
        entries[#entries + 1] = { text = "Share with group", func = function() ShareGroup(place) end }
    end
    entries[#entries + 1] = { text = "Post in chat", func = function() Post(place) end }
    entries[#entries + 1] = { text = "Copy /way line", func = function() Copy(place) end }
    entries[#entries + 1] = { text = "Save as place", func = function() SavePlace(place) end }
    return R.ShowMenu(entries, "cursor")
end

-- The place in an Orders link, or nil (another addon's link; another kind)
local function PlaceOf(link)
    local payload = PayloadOf(link)
    if not payload then return nil end
    local map, x, y, title = G.ParseChatLink(payload)
    if not map then return nil end
    return { map = map, x = x, y = y, title = title }, payload
end

-- EventRegistry "SetItemRef": (owner, link, text, button, frame)
local function OnLink(_, link, _, button)
    local place, payload = PlaceOf(link)
    if not place then return end
    if button == "RightButton" then
        C.Menu(place, payload)
    elseif IsControlKeyDown and IsControlKeyDown() then
        Copy(place)
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        Share(place)
    else
        Go(place, payload)
    end
end

function C.OnLink(...)
    local ok, err = pcall(OnLink, ...)
    if not ok then Report(err) end
end

-- ---------------------------------------------------------------------------
-- Hover
-- ---------------------------------------------------------------------------
-- "582 yd away", or which landmass it is on when no straight line reaches
local function Away(place)
    if type(R.PosWorld) ~= "function" or type(R.Landmass) ~= "function" then return nil end
    local inst, n, w = R.PosWorld(place)
    if inst == nil then return nil end
    local key = R.Landmass(place.map, inst)
    local pn, pw, pinst
    if type(R.PlayerWorld) == "function" then pn, pw, pinst = R.PlayerWorld() end
    local pmap = type(R.PlayerMap) == "function" and R.PlayerMap()
    if pn and pinst == inst and pmap and key and R.Landmass(pmap, pinst) == key
        and type(R.Distance) == "function" then
        return R.Distance(G.Distance(pn, pw, n, w)) .. " away"
    end
    local name = key and D and D.LANDMASS_NAMES and D.LANDMASS_NAMES[key]
    if name then return "In " .. name end
    return nil
end

local tipOwner

local function OnEnter(_, frame, link)
    local place = PlaceOf(link)
    if not place then
        tipOwner = nil           -- another link's tooltip, not ours to hide
        return
    end
    local tip = GameTooltip
    if not tip then return end
    local owner = frame or UIParent
    tip:SetOwner(owner, "ANCHOR_CURSOR")
    local where = Where(place)
    if place.title then
        tip:SetText(place.title, 1, 1, 1)
        tip:AddLine(where, 0.9, 0.9, 0.9)
    else
        tip:SetText(where, 1, 1, 1)
    end
    local away = Away(place)
    if away then tip:AddLine(away, 0.9, 0.9, 0.9) end
    tip:AddLine("Click: Go. Shift-click: share. Ctrl-click: copy a /way line. Right-click: more.",
        0.6, 0.8, 1, true)
    tip:Show()
    tipOwner = owner
end

function C.OnEnter(...)
    local ok, err = pcall(OnEnter, ...)
    if not ok then Report(err) end
end

function C.OnLeave()
    local tip = GameTooltip
    if tipOwner and tip and tip.GetOwner and tip:GetOwner() == tipOwner then tip:Hide() end
    tipOwner = nil
end

-- ---------------------------------------------------------------------------
-- The exports (never raising, like the rest of the public API)
-- ---------------------------------------------------------------------------
function O.Linkify(text, ctx)
    if type(text) ~= "string" then return text, 0 end
    if DB().ChatLinks == false or not Ready() then return text, 0 end
    if type(ctx) == "table" and ctx.event == nil and type(ctx.chatType) == "string" then
        local copy = {}
        for k, v in pairs(ctx) do copy[k] = v end
        copy.event = "CHAT_MSG_" .. ctx.chatType:upper()
        ctx = copy
    end
    local ok, out, count = pcall(Rewrite, text, type(ctx) == "table" and ctx or {})
    if not ok then
        Report(out)
        return text, 0
    end
    if not out then return text, 0 end
    return out, count
end

function O.ClaimChatLink(link, fn)
    local ok, done, why = pcall(Claim, link, fn)
    if not ok then
        Report(done)
        return nil, "error"
    end
    return done, why
end

-- ---------------------------------------------------------------------------
-- Wiring: at load, once. The filter reads the setting per line and the
-- callbacks answer only Orders links, so nothing is ever unregistered.
-- ---------------------------------------------------------------------------
local OWNER = {}                 -- EventRegistry: one callback per owner per event

local function Register()
    if C.registered or not G then return end
    C.registered = true
    local reg = EventRegistry
    if type(reg) == "table" and type(reg.RegisterCallback) == "function" then
        pcall(reg.RegisterCallback, reg, "SetItemRef", C.OnLink, OWNER)
        pcall(reg.RegisterCallback, reg, "ChatFrame.OnHyperlinkEnter", C.OnEnter, OWNER)
        pcall(reg.RegisterCallback, reg, "ChatFrame.OnHyperlinkLeave", C.OnLeave, OWNER)
    end
    local util = ChatFrameUtil
    local add = (type(util) == "table" and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if type(add) == "function" then
        for _, event in ipairs(EVENTS) do pcall(add, event, C.Filter) end
    end
end

Register()

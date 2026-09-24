-- Commander Contacts: the store.
--
-- Everything the window shows that the client does not answer live -- who
-- said what to you, when, and in which party -- lives in one SavedVariables
-- table, and this file is the only thing allowed to write it. No widgets and
-- no client calls are touched here, on purpose: the store is plain Lua, so
-- the harness drives the real functions against real fixtures and a failure
-- is always a logic bug rather than a mock artefact (the Notebook split).
--
-- The shape on disk:
--
--   CommanderContactsDB = {
--     <settings keys, flat, per the suite convention>
--     Conversations = { [key] = conversation },
--     ActiveGroup   = "group:12" | nil,   -- the party you are in right now
--     NextID        = 13,
--   }
--
--   conversation = {
--     key,                 -- "dm:Name", "bn:<bnetAccountID>", "group:<n>"
--     kind,                -- "dm" | "bn" | "group"
--     name,                -- what the sidebar prints
--     target,              -- dm: the full Name-Realm to whisper; bn: the account id
--     guid, class,         -- dm: the last seen player GUID and class token
--     members,             -- group: ordered array of short names
--     groupType,           -- group: "PARTY" | "RAID" | "INSTANCE"
--     started, ended,      -- group: epoch seconds; ended nil while it is live
--     created, updated,    -- epoch seconds
--     lastRead, unread,    -- when you last looked, and how many arrived since
--     pinned,              -- true | nil
--     messages = { { t, from, text, out, cls, ch }, ... },
--   }
--
-- A message keeps the raw chat text, hyperlinks and all, because the window
-- renders those as real links; the sidebar preview strips them down to the
-- bracketed label. Conversations are a map keyed by id and order is a
-- property of a query, for the same reasons the Notebook documents: a
-- selection has to survive the list re-sorting under it.

CommanderContactsStore = CommanderContactsStore or {}
local S = CommanderContactsStore

local DEFAULT_MAX_MESSAGES = 400
local ABSOLUTE_MAX_MESSAGES = 5000

-- ---------------------------------------------------------------------------
-- Injection points
--
-- The clock is a function so the harness can freeze it. Live it is time().
-- ---------------------------------------------------------------------------

function S.Now()
    return (type(time) == "function" and time()) or 0
end

local db
local maxMessages = DEFAULT_MAX_MESSAGES

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Name-Realm" -> "Name" when the realm is the player's own (compared with
-- spaces and hyphens removed, which is how GetNormalizedRealmName spells it).
-- Any other realm is kept, because "Bob" and "Bob-Otherrealm" are two people.
function S.Shorten(fullName, ownRealm)
    fullName = Trim(fullName)
    local name, realm = fullName:match("^([^%-]+)%-(.+)$")
    if not name then return fullName end
    if ownRealm and realm then
        local a = realm:gsub("[%s%-]", ""):lower()
        local b = tostring(ownRealm):gsub("[%s%-]", ""):lower()
        if a == b then return name end
    end
    return fullName
end

function S.DMKey(shortName)
    return "dm:" .. Trim(shortName)
end

function S.BNKey(bnetID)
    return "bn:" .. tostring(bnetID)
end

-- Chat text with its links reduced to their labels and colour codes
-- removed, for the one-line previews and for searching.
function S.PlainText(text)
    text = tostring(text or "")
    text = text:gsub("|H[^|]*|h(.-)|h", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T[^|]*|t", "")
    return text
end

local function Preview(text, limit)
    local plain = S.PlainText(text):gsub("%s+", " ")
    plain = Trim(plain)
    limit = limit or 60
    if #plain > limit then plain = plain:sub(1, limit - 1) .. "…" end
    return plain
end
S.Preview = Preview

-- ---------------------------------------------------------------------------
-- Attach / normalise
--
-- Attach is the ONLY entry point that may see a malformed table, and it must
-- survive anything: a fresh account, a table hand-edited between sessions, a
-- conversation an older build wrote with a field missing. Every later
-- function may then assume the invariants below hold.
--
-- Invariants after Attach:
--   * db.Conversations is a table; every value is a table whose key field
--     matches its map key and whose kind is one of the three
--   * every conversation has a name string, a messages array whose entries
--     each have a number t and string from/text, numbers for created,
--     updated, lastRead and unread, and (groups) a members array
--   * db.NextID is greater than every numeric id in use
--   * db.ActiveGroup either names a live group conversation or is nil
-- ---------------------------------------------------------------------------

local KINDS = { dm = true, bn = true, group = true }

local function NormaliseMessages(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, message in ipairs(list) do
        if type(message) == "table" and message.text ~= nil then
            local entry = {
                t = tonumber(message.t) or 0,
                from = tostring(message.from or "?"),
                text = tostring(message.text),
            }
            if message.out then entry.out = true end
            if type(message.cls) == "string" then entry.cls = message.cls end
            if type(message.ch) == "string" then entry.ch = message.ch end
            out[#out + 1] = entry
        end
    end
    return out
end

function S.Attach(target)
    db = target or {}
    db.Conversations = type(db.Conversations) == "table" and db.Conversations or {}
    db.NextID = tonumber(db.NextID) or 1

    local highest = 0
    for key, conv in pairs(db.Conversations) do
        if type(conv) ~= "table" or type(key) ~= "string" then
            db.Conversations[key] = nil
        else
            conv.key = key
            if not KINDS[conv.kind] then
                conv.kind = key:match("^group:") and "group"
                    or key:match("^bn:") and "bn" or "dm"
            end
            conv.name = Trim(conv.name)
            if conv.name == "" then
                conv.name = conv.kind == "group" and "Party" or (key:match("^%w+:(.+)$") or "Unknown")
            end
            conv.messages = NormaliseMessages(conv.messages)
            conv.created = tonumber(conv.created) or S.Now()
            conv.updated = tonumber(conv.updated) or conv.created
            conv.lastRead = tonumber(conv.lastRead) or 0
            conv.unread = math.max(math.floor(tonumber(conv.unread) or 0), 0)
            if conv.pinned ~= true then conv.pinned = nil end
            if conv.kind == "group" then
                if type(conv.members) ~= "table" then conv.members = {} end
                local members, seen = {}, {}
                for _, name in ipairs(conv.members) do
                    name = Trim(name)
                    if name ~= "" and not seen[name] then
                        seen[name] = true
                        members[#members + 1] = name
                    end
                end
                conv.members = members
                conv.groupType = conv.groupType or "PARTY"
                conv.started = tonumber(conv.started) or conv.created
                conv.ended = tonumber(conv.ended)
                local id = tonumber(key:match("^group:(%d+)$"))
                if id and id > highest then highest = id end
            else
                conv.members = nil
            end
        end
    end
    if db.NextID <= highest then db.NextID = highest + 1 end

    local active = db.ActiveGroup and db.Conversations[db.ActiveGroup]
    if not (active and active.kind == "group" and not active.ended) then
        db.ActiveGroup = nil
    end
    return db
end

function S.Attached()
    return db ~= nil
end

function S.SetMaxMessages(count)
    count = tonumber(count) or DEFAULT_MAX_MESSAGES
    if count < 20 then count = 20 end
    if count > ABSOLUTE_MAX_MESSAGES then count = ABSOLUTE_MAX_MESSAGES end
    maxMessages = math.floor(count)
end

function S.MaxMessages()
    return maxMessages
end

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------

function S.Conversation(key)
    return key and db and db.Conversations[key] or nil
end

function S.Count(kind)
    local count = 0
    for _, conv in pairs(db.Conversations) do
        if not kind or conv.kind == kind then count = count + 1 end
    end
    return count
end

local function NewConversation(key, kind, name)
    local now = S.Now()
    local conv = {
        key = key, kind = kind, name = name,
        messages = {},
        created = now, updated = now,
        lastRead = 0, unread = 0,
    }
    db.Conversations[key] = conv
    return conv
end

-- A direct-message thread with a player. `fields` may carry target (the
-- Name-Realm to whisper back), guid and class; each is updated whenever a
-- newer value arrives, because a player's class is not known from the
-- friends list until they are online and their GUID is not known until they
-- speak.
function S.EnsureDM(shortName, fields)
    shortName = Trim(shortName)
    if shortName == "" then return nil end
    local key = S.DMKey(shortName)
    local conv = db.Conversations[key]
    if not conv then
        conv = NewConversation(key, "dm", shortName)
        conv.target = shortName
    end
    if type(fields) == "table" then
        if fields.target and fields.target ~= "" then conv.target = fields.target end
        if fields.guid and fields.guid ~= "" then conv.guid = fields.guid end
        if fields.class and fields.class ~= "" then conv.class = fields.class end
    end
    return conv
end

function S.EnsureBN(bnetID, name)
    bnetID = tonumber(bnetID)
    if not bnetID then return nil end
    local key = S.BNKey(bnetID)
    local conv = db.Conversations[key]
    if not conv then
        conv = NewConversation(key, "bn", Trim(name) ~= "" and Trim(name) or ("Battle.net " .. bnetID))
        conv.target = bnetID
    elseif Trim(name) ~= "" then
        conv.name = Trim(name)
    end
    return conv
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function GroupLabel(groupType)
    if groupType == "RAID" then return "Raid" end
    if groupType == "INSTANCE" then return "Battleground" end
    return "Party"
end
S.GroupLabel = GroupLabel

-- Start a new group thread. The name is "Party · 14 Sep" and is rewritten
-- if the party turns into a raid, unless the user renamed it, which is the
-- one thing Rename records.
function S.StartGroup(groupType, members)
    groupType = groupType or "PARTY"
    local id = db.NextID
    db.NextID = id + 1
    local key = "group:" .. id
    local now = S.Now()
    local stamp = type(date) == "function" and date("*t", now) or nil
    local name = GroupLabel(groupType)
    if stamp then
        name = string.format("%s · %d %s", name, stamp.day, MONTHS[stamp.month] or "")
    end
    local conv = NewConversation(key, "group", name)
    conv.groupType = groupType
    conv.members = {}
    conv.started = now
    S.AddMembers(key, members)
    db.ActiveGroup = key
    return conv
end

function S.ActiveGroup()
    local conv = db.ActiveGroup and db.Conversations[db.ActiveGroup]
    if conv and conv.kind == "group" and not conv.ended then return conv end
    db.ActiveGroup = nil
    return nil
end

function S.SetGroupType(key, groupType)
    local conv = S.Conversation(key)
    if not (conv and conv.kind == "group") then return false end
    if conv.groupType == groupType then return false end
    local oldLabel = GroupLabel(conv.groupType)
    conv.groupType = groupType
    if not conv.renamed and conv.name:sub(1, #oldLabel) == oldLabel then
        conv.name = GroupLabel(groupType) .. conv.name:sub(#oldLabel + 1)
    end
    return true
end

function S.CloseGroup(key)
    local conv = S.Conversation(key)
    if not (conv and conv.kind == "group") then return false end
    if not conv.ended then conv.ended = S.Now() end
    if db.ActiveGroup == key then db.ActiveGroup = nil end
    return true
end

-- Returns how many names were new.
function S.AddMembers(key, names)
    local conv = S.Conversation(key)
    if not (conv and conv.kind == "group") or type(names) ~= "table" then return 0 end
    local seen = {}
    for _, name in ipairs(conv.members) do seen[name] = true end
    local added = 0
    for _, name in ipairs(names) do
        name = Trim(name)
        if name ~= "" and not seen[name] then
            seen[name] = true
            conv.members[#conv.members + 1] = name
            added = added + 1
        end
    end
    return added
end

function S.IsMember(key, name)
    local conv = S.Conversation(key)
    if not (conv and conv.members) then return false end
    for _, member in ipairs(conv.members) do
        if member == name then return true end
    end
    return false
end

-- "Bob, Alice and 3 others"
function S.MemberSummary(conv, limit)
    if not (conv and conv.members) or #conv.members == 0 then return "nobody yet" end
    limit = limit or 3
    local shown = {}
    for index = 1, math.min(limit, #conv.members) do shown[index] = conv.members[index] end
    local rest = #conv.members - #shown
    local text = table.concat(shown, ", ")
    if rest > 0 then
        text = text .. (rest == 1 and " and 1 other" or (" and " .. rest .. " others"))
    end
    return text
end

function S.Rename(key, name)
    local conv = S.Conversation(key)
    name = Trim(name)
    if not conv or name == "" or conv.name == name then return false end
    conv.name = name
    conv.renamed = true
    return true
end

function S.SetPinned(key, pinned)
    local conv = S.Conversation(key)
    if not conv then return false end
    local value = pinned and true or nil
    if conv.pinned == value then return false end
    conv.pinned = value
    return true
end

function S.Delete(key)
    if not S.Conversation(key) then return false end
    db.Conversations[key] = nil
    if db.ActiveGroup == key then db.ActiveGroup = nil end
    return true
end

function S.Clear(key)
    local conv = S.Conversation(key)
    if not conv then return false end
    local had = #conv.messages
    conv.messages = {}
    conv.unread = 0
    return had > 0
end

-- ---------------------------------------------------------------------------
-- Messages
-- ---------------------------------------------------------------------------

-- message: { from, text, out, cls, ch, t }. t defaults to now. Returns the
-- stored entry. A thread only ever keeps its newest maxMessages lines; the
-- trim is done here so no caller can forget it.
function S.Append(key, message)
    local conv = S.Conversation(key)
    if not (conv and type(message) == "table") then return nil end
    local text = tostring(message.text or "")
    if text == "" then return nil end
    local entry = {
        t = tonumber(message.t) or S.Now(),
        from = Trim(message.from) ~= "" and Trim(message.from) or "?",
        text = text,
    }
    if message.out then entry.out = true end
    if type(message.cls) == "string" and message.cls ~= "" then entry.cls = message.cls end
    if type(message.ch) == "string" and message.ch ~= "" then entry.ch = message.ch end
    local list = conv.messages
    list[#list + 1] = entry
    if #list > maxMessages then
        local drop = #list - maxMessages
        for _ = 1, drop do table.remove(list, 1) end
    end
    conv.updated = entry.t
    if not entry.out then conv.unread = (conv.unread or 0) + 1 end
    return entry
end

function S.Messages(key)
    local conv = S.Conversation(key)
    return conv and conv.messages or {}
end

function S.LastMessage(key)
    local conv = S.Conversation(key)
    if not conv then return nil end
    return conv.messages[#conv.messages]
end

function S.MarkRead(key)
    local conv = S.Conversation(key)
    if not conv then return false end
    local changed = (conv.unread or 0) > 0
    conv.unread = 0
    conv.lastRead = S.Now()
    return changed
end

function S.Unread(key)
    local conv = S.Conversation(key)
    return conv and conv.unread or 0
end

function S.TotalUnread(kind)
    local total = 0
    for _, conv in pairs(db.Conversations) do
        if not kind or conv.kind == kind then total = total + (conv.unread or 0) end
    end
    return total
end

-- The one-line preview under a sidebar row.
function S.PreviewFor(conv, limit)
    local last = conv and conv.messages[#conv.messages]
    if not last then
        if conv and conv.kind == "group" then return S.MemberSummary(conv) end
        return "No messages yet"
    end
    local text = Preview(last.text, limit)
    if last.out then return "You: " .. text end
    if conv.kind == "group" then return last.from .. ": " .. text end
    return text
end

-- ---------------------------------------------------------------------------
-- Listing
--
-- query = {
--   kind    = "dm" | "bn" | "group" | "people" (dm + bn) | nil for all,
--   search  = "text",             -- matches the name, a member, or a line
--   sort    = "recent" | "name" | "unread",
--   filter  = "all" | "friends" | "others",
--   friends = { [shortName] = true },   -- needed for the friends filters
-- }
-- Pinned threads come first whatever the sort. Every comparator ends on the
-- key so an unchanged list never flickers between refreshes.
-- ---------------------------------------------------------------------------

local function Matches(conv, needle)
    if needle == "" then return true end
    if conv.name:lower():find(needle, 1, true) then return true end
    if conv.members then
        for _, member in ipairs(conv.members) do
            if member:lower():find(needle, 1, true) then return true end
        end
    end
    for _, message in ipairs(conv.messages) do
        if S.PlainText(message.text):lower():find(needle, 1, true) then return true end
    end
    return false
end

local function KindMatches(conv, kind)
    if not kind or kind == "all" then return true end
    if kind == "people" then return conv.kind ~= "group" end
    return conv.kind == kind
end

local SORTS = {
    recent = function(a, b)
        if a.updated ~= b.updated then return a.updated > b.updated end
        return a.key < b.key
    end,
    name = function(a, b)
        local an, bn = a.name:lower(), b.name:lower()
        if an ~= bn then return an < bn end
        return a.key < b.key
    end,
    unread = function(a, b)
        if (a.unread or 0) ~= (b.unread or 0) then return (a.unread or 0) > (b.unread or 0) end
        if a.updated ~= b.updated then return a.updated > b.updated end
        return a.key < b.key
    end,
}

function S.List(query)
    query = query or {}
    local needle = Trim(query.search):lower()
    local friends = query.friends or {}
    local filter = query.filter or "all"
    local out = {}
    for _, conv in pairs(db.Conversations) do
        local keep = KindMatches(conv, query.kind)
        if keep and filter ~= "all" and conv.kind ~= "group" then
            local isFriend = friends[conv.name] and true or false
            if conv.kind == "bn" then isFriend = true end
            if filter == "friends" then keep = isFriend else keep = not isFriend end
        end
        if keep and Matches(conv, needle) then out[#out + 1] = conv end
    end
    local inner = SORTS[query.sort or "recent"] or SORTS.recent
    table.sort(out, function(a, b)
        if (a.pinned and true) ~= (b.pinned and true) then return a.pinned and true or false end
        return inner(a, b)
    end)
    return out
end

-- ---------------------------------------------------------------------------
-- Pruning
--
-- Runs at login. Drops lines older than `days` (0 keeps everything), then
-- drops any thread left with no lines that is not pinned and not a live
-- group. Returns (linesDropped, threadsDropped).
-- ---------------------------------------------------------------------------

function S.Prune(days)
    days = tonumber(days) or 0
    local lines, threads = 0, 0
    local cutoff = days > 0 and (S.Now() - days * 86400) or nil
    for key, conv in pairs(db.Conversations) do
        if cutoff then
            local kept = {}
            for _, message in ipairs(conv.messages) do
                if message.t >= cutoff then kept[#kept + 1] = message else lines = lines + 1 end
            end
            conv.messages = kept
        end
        if #conv.messages > maxMessages then
            local drop = #conv.messages - maxMessages
            for _ = 1, drop do table.remove(conv.messages, 1) end
            lines = lines + drop
        end
        local live = conv.kind == "group" and not conv.ended and db.ActiveGroup == key
        if #conv.messages == 0 and not conv.pinned and not live
            and cutoff and conv.updated < cutoff then
            db.Conversations[key] = nil
            threads = threads + 1
        end
    end
    return lines, threads
end

function S.Stats()
    local stats = { people = 0, bn = 0, groups = 0, lines = 0, unread = 0 }
    for _, conv in pairs(db.Conversations) do
        if conv.kind == "dm" then stats.people = stats.people + 1
        elseif conv.kind == "bn" then stats.bn = stats.bn + 1
        else stats.groups = stats.groups + 1 end
        stats.lines = stats.lines + #conv.messages
        stats.unread = stats.unread + (conv.unread or 0)
    end
    return stats
end

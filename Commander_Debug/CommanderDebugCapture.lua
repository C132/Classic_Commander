-- Commander Debug — capture layer
--
-- Two sources, one record shape.
--
-- BugGrabber (the !BugGrabber addon that BugSack draws) is preferred whenever
-- it is loaded. It installs its error hook before any other addon gets a look
-- in, dedupes by message with an occurrence counter, keeps a stack and a
-- locals dump per error, persists across sessions in its own SavedVariables,
-- and then replaces seterrorhandler with a no-op so nothing can steal the
-- hook back. That last part matters: when BugGrabber is present our own
-- seterrorhandler call would be silently swallowed, so we must not try.
--
-- Without it we install our own handler, chaining to whatever was there
-- before so the client's normal error display still fires, and keep an
-- in-memory ring for the current session only.
--
-- A record is:
--   message  (string)  the error text
--   stack    (string?)  call stack, newline separated
--   locals   (string?)  local variable dump, newline separated
--   counter  (number)  how many times this exact message fired
--   time     (number)  epoch time of the most recent occurrence
--   session  (number)  BugGrabber session id, or 1 in native mode
--   addon    (string?) addon name parsed out of the paths in message/stack

CommanderDebug = CommanderDebug or {}
local Capture = {}
CommanderDebug.Capture = Capture

local NATIVE_MAX = 250

local nativeErrors = {}      -- chronological, oldest first
local nativeByMessage = {}   -- message -> record, so repeats bump a counter
local nativeInstalled = false
local inHandler = false      -- our handler must never re-enter itself

-- ---------------------------------------------------------------------------
-- Source detection
-- ---------------------------------------------------------------------------

local function BugGrabberReady()
    local bg = _G.BugGrabber
    return type(bg) == "table" and type(bg.GetDB) == "function" and bg:GetDB() ~= nil
end

Capture.BugGrabberReady = BugGrabberReady

-- "BUGGRABBER" or "NATIVE"
function Capture.Source()
    return BugGrabberReady() and "BUGGRABBER" or "NATIVE"
end

function Capture.SourceLabel()
    if not BugGrabberReady() then
        return "Commander Debug (built-in hook)"
    end
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BugSack") then
        return "BugGrabber (shared with BugSack)"
    end
    return "BugGrabber"
end

function Capture.SessionId()
    if BugGrabberReady() then
        return _G.BugGrabber:GetSessionId()
    end
    return 1
end

-- ---------------------------------------------------------------------------
-- Attribution: pull the addon name out of the file paths in an error
-- ---------------------------------------------------------------------------

-- Error text carries paths as Interface\AddOns\<Name>\File.lua:123, sometimes
-- truncated at the front with "..." and sometimes with forward slashes.
local function AddonFromText(text)
    if type(text) ~= "string" then return nil end
    local name = text:match("[Aa]dd[Oo]ns[\\/]([^\\/]+)[\\/]")
    if name then return name end
    -- ADDON_ACTION_BLOCKED lines name the addon in quotes instead of a path
    return text:match("^%[ADDON_ACTION_[A-Z]+%] AddOn '([^']+)'")
end

Capture.AddonFromText = AddonFromText

local function ResolveAddon(record)
    return AddonFromText(record.message) or AddonFromText(record.stack)
end

-- ---------------------------------------------------------------------------
-- Native capture (only used when BugGrabber is absent)
-- ---------------------------------------------------------------------------

local function StoreNative(message, stack, locals)
    local existing = nativeByMessage[message]
    if existing then
        existing.counter = existing.counter + 1
        existing.time = time()
        return existing, false
    end

    local record = {
        message = message,
        stack = stack,
        locals = locals,
        counter = 1,
        time = time(),
        session = 1,
    }
    record.addon = ResolveAddon(record)
    nativeErrors[#nativeErrors + 1] = record
    nativeByMessage[message] = record

    while #nativeErrors > NATIVE_MAX do
        local dropped = table.remove(nativeErrors, 1)
        if nativeByMessage[dropped.message] == dropped then
            nativeByMessage[dropped.message] = nil
        end
    end

    return record, true
end

-- Exposed so the harness can drive capture without a real error handler.
Capture.StoreNative = StoreNative

local function AnnounceCapture(record, isNew)
    Commander.Notify(COMMANDER_DEBUG_EVENTS.CAPTURED, record, isNew)
    if isNew and CommanderDebugDB and CommanderDebugDB.Announce then
        local where = record.addon and (" |cffffd200" .. record.addon .. "|r") or ""
        print("|cff33ff99Commander Debug|r: error captured" .. where .. " — /cdebug to copy the report")
    end
end

Capture.Announce = AnnounceCapture

local function NativeHandler(previous)
    return function(err, ...)
        -- Chain first so the client's own display never depends on our code
        -- surviving. Everything after this point is best effort.
        if previous then
            pcall(previous, err, ...)
        end
        if inHandler then return end
        inHandler = true
        pcall(function()
            local message = tostring(err)
            local stack, locals
            if type(debugstack) == "function" then
                -- 3 skips this closure, the pcall wrapper and the handler
                stack = debugstack(3, 20, 20)
            end
            if type(debuglocals) == "function" then
                locals = debuglocals(3)
            end
            local record, isNew = StoreNative(message, stack, locals)
            AnnounceCapture(record, isNew)
        end)
        inHandler = false
    end
end

-- Errors the client reports as events rather than through the error handler.
local nativeEvents = CreateFrame("Frame")
local blockedSeen = {}

local function InstallNative()
    if nativeInstalled or BugGrabberReady() then return false end
    nativeInstalled = true

    local previous = geterrorhandler and geterrorhandler() or nil
    if type(seterrorhandler) == "function" then
        seterrorhandler(NativeHandler(previous))
    end

    nativeEvents:RegisterEvent("LUA_WARNING")
    nativeEvents:RegisterEvent("ADDON_ACTION_BLOCKED")
    nativeEvents:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    nativeEvents:SetScript("OnEvent", function(_, event, a, b)
        if event == "LUA_WARNING" then
            local record, isNew = StoreNative("LUA_WARNING: " .. tostring(a or ""))
            AnnounceCapture(record, isNew)
        else
            -- One line per addon: a tainted addon fires these by the hundred
            local name = tostring(a or "<unknown>")
            local key = event .. name
            if not blockedSeen[key] then
                blockedSeen[key] = true
                local record, isNew = StoreNative(string.format(
                    "[%s] AddOn '%s' tried to call the protected function '%s'.",
                    event, name, tostring(b or "<unknown>")))
                AnnounceCapture(record, isNew)
            end
        end
    end)
    return true
end

Capture.InstallNative = InstallNative

-- ---------------------------------------------------------------------------
-- Reading errors back out
-- ---------------------------------------------------------------------------

local function Normalize(entry, index)
    -- BugGrabber has historically stored a table for message; those are junk
    if type(entry) ~= "table" or type(entry.message) ~= "string" then return nil end
    local record = {
        message = entry.message,
        stack = type(entry.stack) == "string" and entry.stack or nil,
        locals = type(entry.locals) == "string" and entry.locals or nil,
        counter = tonumber(entry.counter) or 1,
        time = tonumber(entry.time) or 0,
        session = tonumber(entry.session) or 0,
        _order = index,
    }
    record.addon = ResolveAddon(record)
    return record
end

Capture.Normalize = Normalize

local function RawErrors()
    if BugGrabberReady() then
        return _G.BugGrabber:GetDB()
    end
    return nativeErrors
end

Capture.RawErrors = RawErrors

-- opts: scope ("SESSION"|"ALL"), onlyCommander (bool), max (number)
-- Returns records newest-first, plus a stats table:
--   { unique, occurrences, total, hidden, oldest, newest, session }
function Capture.GetErrors(opts)
    opts = opts or {}
    local raw = RawErrors() or {}
    local session = Capture.SessionId()

    local kept = {}
    local stats = { unique = 0, occurrences = 0, total = 0, hidden = 0, session = session }

    for i = 1, #raw do
        local record = Normalize(raw[i], i)
        if record then
            stats.total = stats.total + 1
            local wanted = true
            if opts.scope ~= "ALL" and record.session ~= session then
                wanted = false
            end
            if wanted and opts.onlyCommander
                and not (record.addon and record.addon:match("^Commander")) then
                wanted = false
            end
            if wanted then
                kept[#kept + 1] = record
            else
                stats.hidden = stats.hidden + 1
            end
        end
    end

    table.sort(kept, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a._order > b._order
    end)

    local max = tonumber(opts.max) or 0
    if max > 0 and #kept > max then
        stats.hidden = stats.hidden + (#kept - max)
        for i = #kept, max + 1, -1 do
            kept[i] = nil
        end
    end

    for _, record in ipairs(kept) do
        stats.unique = stats.unique + 1
        stats.occurrences = stats.occurrences + record.counter
        if record.time > 0 then
            if not stats.newest or record.time > stats.newest then stats.newest = record.time end
            if not stats.oldest or record.time < stats.oldest then stats.oldest = record.time end
        end
    end

    return kept, stats
end

-- Wipes whichever store is live. With BugGrabber that empties its saved
-- database, which BugSack reads from the same table — they clear together.
function Capture.Clear()
    if BugGrabberReady() then
        _G.BugGrabber:Reset()
    end
    wipe(nativeErrors)
    wipe(nativeByMessage)
    wipe(blockedSeen)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local lifecycle = CreateFrame("Frame")
lifecycle:RegisterEvent("PLAYER_LOGIN")
lifecycle:SetScript("OnEvent", function()
    if BugGrabberReady() then
        -- BugGrabber fans out through EventRegistry; ride that instead of
        -- polling so the announce lands the moment an error is grabbed.
        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, tableID)
                local entry = _G.BugGrabber:GetErrorByID(tableID)
                local record = entry and Normalize(entry, 0)
                if record then
                    AnnounceCapture(record, record.counter == 1)
                end
            end, Capture)
        end
    else
        InstallNative()
    end
end)

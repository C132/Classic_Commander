-- CommanderWhoEngine.lua
--
-- Pure Lua. No WoW API, no widgets, no saved variables, no globals beyond the
-- one table it exports. Everything in here is driven by the harness with
-- hand-written fixtures, so a failure there is always a real logic bug.
--
-- It owns the single idea the old module got wrong: **selection belongs to a
-- player, not to a row widget.** Blizzard's Who list is seventeen recycled
-- buttons scrolled over an arbitrarily long result set (D1), so any state
-- parked on a button is state that silently transfers to a different player
-- the moment you scroll. Selection here is a set keyed by player identity; the
-- widgets are a view of it and own nothing.
--
-- The second thing it owns is the whisper plan (D3): the list of who actually
-- gets messaged, derived from that one selection set, with the recipient cap
-- and the don't-whisper-yourself rule applied where they can be *reported*
-- rather than silently swallowed.

CommanderWhoEngine = {}
local E = CommanderWhoEngine

local format = string.format
local lower, gsub, match, len = string.lower, string.gsub, string.match, string.len
local tsort = table.sort

-- Blizzard's own whisper ceiling. A longer message is not truncated by the
-- server, it is rejected, so we refuse it up front and say by how much.
E.MAX_WHISPER_LENGTH = 255

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------
-- A key must survive a re-sort, a re-query and a scroll, and must be the same
-- string whichever of the two sources produced it (the Who row or the mass
-- whisper row). Case-folded because nothing guarantees the two call sites see
-- identical capitalisation, and the realm suffix is kept: it costs nothing on
-- this client, where /who never returns one, and it is the difference between
-- right and wrong on any client where it does.

function E.SplitName(fullName)
    if type(fullName) ~= "string" then return nil, nil end
    local name, realm = match(fullName, "^([^%-]+)%-(.+)$")
    if name then return name, realm end
    return fullName, nil
end

local function Trim(s)
    if type(s) ~= "string" then return nil end
    s = gsub(s, "^%s+", "")
    s = gsub(s, "%s+$", "")
    return s
end
E.Trim = Trim

function E.Key(fullName)
    local trimmed = Trim(fullName)
    if not trimmed or trimmed == "" then return nil end
    return lower(trimmed)
end

-- ---------------------------------------------------------------------------
-- Class identity and colour
-- ---------------------------------------------------------------------------
-- The nine classes this client can return. Death knights are deliberately
-- absent: 2.5.5 has none, and a token that cannot occur is a token nobody can
-- test. ClassColor falls back to white for anything unrecognised rather than
-- guessing, because the old module's "unknown means WARRIOR" fallback painted
-- every result warrior-brown the moment one field name changed.

E.CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 },
    PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER  = { 0.67, 0.83, 0.45 },
    ROGUE   = { 1.00, 0.96, 0.41 },
    PRIEST  = { 1.00, 1.00, 1.00 },
    SHAMAN  = { 0.00, 0.44, 0.87 },
    MAGE    = { 0.41, 0.80, 0.94 },
    WARLOCK = { 0.58, 0.51, 0.79 },
    DRUID   = { 1.00, 0.49, 0.04 },
}

-- Localised class name -> token, populated by the host from the client's own
-- LOCALIZED_CLASS_NAMES_* globals. The engine never reads a global itself; an
-- empty map simply means colouring falls back to the file name field.
local classNameMap = {}

function E.SetClassNameMap(map)
    classNameMap = {}
    if type(map) ~= "table" then return end
    for localised, token in pairs(map) do
        if type(localised) == "string" and type(token) == "string" then
            classNameMap[lower(localised)] = token
        end
    end
end

function E.ClassToken(fileName, localisedName)
    if type(fileName) == "string" and fileName ~= "" then
        local upper = string.upper(gsub(fileName, "%s", ""))
        if E.CLASS_COLORS[upper] then return upper end
    end
    if type(localisedName) == "string" and localisedName ~= "" then
        local hit = classNameMap[lower(Trim(localisedName))]
        if hit and E.CLASS_COLORS[hit] then return hit end
        -- Last resort for an English client with no map installed
        local upper = string.upper(gsub(localisedName, "%s", ""))
        if E.CLASS_COLORS[upper] then return upper end
    end
    return nil
end

function E.ClassColor(token)
    local c = token and E.CLASS_COLORS[token]
    if c then return c[1], c[2], c[3] end
    return 1, 1, 1
end

function E.ClassHex(token)
    local r, g, b = E.ClassColor(token)
    return format("%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

-- ---------------------------------------------------------------------------
-- Who result normalisation
-- ---------------------------------------------------------------------------
-- C_FriendList.GetWhoInfo returns classStr/filename/area/fullGuildName on this
-- client (ASSUMPTIONS A2). The old module read className, which does not exist
-- here, so the class column was blank on every row and the colour fell through
-- to its warrior default. Reading a small alias list instead of one hard-coded
-- field name costs nothing and makes the module survive the field being spelt
-- differently on a client we have not seen.

local function Pick(info, ...)
    for i = 1, select("#", ...) do
        local value = info[select(i, ...)]
        if value ~= nil and value ~= "" then return value end
    end
    return nil
end

-- index is the 1-based position in the *current* Who result order. It is
-- carried so shift-click range selection has something to count with, and is
-- explicitly NOT part of the identity key -- it changes on every re-sort.
function E.Normalize(info, index)
    if type(info) ~= "table" then return nil end
    local fullName = Pick(info, "fullName", "name")
    local key = E.Key(fullName)
    if not key then return nil end

    local name, realm = E.SplitName(Trim(fullName))
    local classText = Pick(info, "classStr", "className", "class")
    local token = E.ClassToken(Pick(info, "filename", "classFileName", "classFilename"), classText)

    return {
        index     = index,
        key       = key,
        fullName  = Trim(fullName),
        name      = name,
        realm     = realm,
        level     = tonumber(Pick(info, "level")) or 0,
        classText = classText or "",
        classToken = token,
        race      = Pick(info, "raceStr", "race") or "",
        zone      = Pick(info, "area", "zone") or "",
        guild     = Pick(info, "fullGuildName", "guild") or "",
    }
end

-- Builds the ordered record list from a fetcher. count and get are injected so
-- this is exercisable headless; the host passes C_FriendList's two calls.
-- Duplicate keys are dropped rather than merged: two rows claiming the same
-- player would make the count lie and would whisper them twice.
function E.BuildRecords(count, get)
    local records, seen = {}, {}
    for i = 1, (count or 0) do
        local record = E.Normalize(get(i), #records + 1)
        if record and not seen[record.key] then
            seen[record.key] = true
            records[#records + 1] = record
        end
    end
    return records
end

function E.KeySet(records)
    local set = {}
    for i = 1, #records do set[records[i].key] = true end
    return set
end

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------

local Selection = {}
Selection.__index = Selection
E.Selection = Selection

function E.NewSelection()
    return setmetatable({ _set = {}, _count = 0 }, Selection)
end

function Selection:Get(key)
    return key ~= nil and self._set[key] == true
end

-- Returns true when the value actually changed, so callers can skip a repaint.
function Selection:Set(key, on)
    if key == nil then return false end
    on = on and true or false
    local was = self._set[key] == true
    if was == on then return false end
    self._set[key] = on or nil
    self._count = self._count + (on and 1 or -1)
    return true
end

function Selection:Toggle(key)
    if key == nil then return false end
    self:Set(key, not self:Get(key))
    return self:Get(key)
end

function Selection:Count()
    return self._count
end

function Selection:Clear()
    if self._count == 0 then return false end
    self._set, self._count = {}, 0
    return true
end

function Selection:SetMany(keys, on)
    local changed = false
    for i = 1, #keys do
        if self:Set(keys[i], on) then changed = true end
    end
    return changed
end

function Selection:SetRecords(records, on)
    local changed = false
    for i = 1, #records do
        if self:Set(records[i].key, on) then changed = true end
    end
    return changed
end

function Selection:InvertRecords(records)
    local changed = false
    for i = 1, #records do
        local key = records[i].key
        if self:Set(key, not self:Get(key)) then changed = true end
    end
    return changed
end

-- Drop everything that is not in the new result set. Without this the count
-- reported in the toolbar would keep counting players who are no longer in the
-- list and cannot be messaged -- the number would be true of the selection and
-- a lie about what Send would do.
function Selection:Prune(validKeys)
    local changed = false
    for key in pairs(self._set) do
        if not validKeys[key] then
            self._set[key] = nil
            self._count = self._count - 1
            changed = true
        end
    end
    return changed
end

function Selection:Keys()
    local keys = {}
    for key in pairs(self._set) do keys[#keys + 1] = key end
    tsort(keys)
    return keys
end

-- How many of these records are selected. Cheaper and more honest than Count()
-- for "3 of 42 selected", which must be counted against the visible list.
function Selection:CountIn(records)
    local n = 0
    for i = 1, #records do
        if self:Get(records[i].key) then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Range selection
-- ---------------------------------------------------------------------------
-- Shift-click on a Who row selects everything between the last clicked row and
-- this one. Indices are positions in the *current* order, so an anchor from
-- before a re-sort is meaningless; the host clears it whenever the result set
-- changes and passes nil, which degrades to a plain single toggle.

function E.RangeKeys(records, fromIndex, toIndex)
    local keys = {}
    if not fromIndex or not toIndex then return keys end
    local lo, hi = fromIndex, toIndex
    if lo > hi then lo, hi = hi, lo end
    for i = lo, hi do
        local record = records[i]
        if record then keys[#keys + 1] = record.key end
    end
    return keys
end

-- ---------------------------------------------------------------------------
-- The whisper plan
-- ---------------------------------------------------------------------------
-- This is the fix for "mass whisper ignores the check marks". There is exactly
-- one place that decides who gets a message and it reads the selection set,
-- in list order, and nothing else. Everything it refuses to send it *counts*,
-- so the UI can say "42 selected, 50 cap, 8 will not be messaged" instead of
-- quietly dropping the tail.

function E.PlanWhispers(records, selection, opts)
    opts = opts or {}
    local cap = opts.maxTargets
    local plan = {
        targets   = {},
        selected  = 0,
        overCap   = 0,
        skippedSelf = 0,
        cap       = cap,
    }
    for i = 1, #records do
        local record = records[i]
        if selection:Get(record.key) then
            plan.selected = plan.selected + 1
            if opts.excludeKey and record.key == opts.excludeKey then
                plan.skippedSelf = plan.skippedSelf + 1
            elseif cap and #plan.targets >= cap then
                plan.overCap = plan.overCap + 1
            else
                plan.targets[#plan.targets + 1] = record
            end
        end
    end
    plan.count = #plan.targets
    plan.ok = plan.count > 0
    if not plan.ok then
        if plan.selected == 0 then
            plan.reason = "Nothing is selected. Tick the players you want in the Who list."
        elseif plan.skippedSelf > 0 and plan.selected == plan.skippedSelf then
            plan.reason = "You cannot mass whisper yourself."
        else
            plan.reason = "The recipient cap is set to zero."
        end
    end
    return plan
end

-- One line, in the user's terms, describing what Send is about to do.
function E.DescribePlan(plan)
    if not plan.ok then return plan.reason or "Nothing to send." end
    local text = format("Whispering %d %s", plan.count, plan.count == 1 and "player" or "players")
    local notes = {}
    if plan.overCap > 0 then
        notes[#notes + 1] = format("%d over the %d cap", plan.overCap, plan.cap or 0)
    end
    if plan.skippedSelf > 0 then
        notes[#notes + 1] = "you were skipped"
    end
    if #notes > 0 then
        text = text .. " (" .. table.concat(notes, ", ") .. ")"
    end
    return text .. "."
end

-- ---------------------------------------------------------------------------
-- Message validation
-- ---------------------------------------------------------------------------

function E.ValidateMessage(message)
    local text = Trim(message)
    if not text or text == "" then
        return nil, "Type a message first."
    end
    if len(text) > E.MAX_WHISPER_LENGTH then
        return nil, format("Message is %d characters over the %d limit.",
            len(text) - E.MAX_WHISPER_LENGTH, E.MAX_WHISPER_LENGTH)
    end
    return text
end

-- ---------------------------------------------------------------------------
-- The send run
-- ---------------------------------------------------------------------------
-- A plain state machine rather than a self-cancelling ticker. The old code
-- asked C_Timer.NewTicker to stop after N iterations and *also* wrote the
-- "complete" message in the branch that runs on iteration N+1, which the
-- ticker by then had cancelled -- so the run never announced it had finished.
-- Here the run knows when it is done and the host just asks for the next one.

local Run = {}
Run.__index = Run
E.Run = Run

function E.NewRun(plan, message)
    return setmetatable({
        targets = plan.targets,
        message = message,
        total   = plan.count,
        index   = 0,
        sent    = 0,
        done    = plan.count == 0,
        cancelled = false,
    }, Run)
end

function Run:IsActive()
    return not self.done and not self.cancelled
end

-- Returns the next record to message, or nil when the run is finished.
function Run:Next()
    if not self:IsActive() then return nil end
    self.index = self.index + 1
    local target = self.targets[self.index]
    if not target then
        self.done = true
        return nil
    end
    self.sent = self.sent + 1
    return target, self.sent, self.total
end

function Run:Cancel()
    self.cancelled = true
end

function Run:Progress()
    if self.cancelled then
        return format("Stopped after %d of %d.", self.sent, self.total)
    end
    if self.done then
        return format("Sent %d %s.", self.sent, self.sent == 1 and "whisper" or "whispers")
    end
    return format("Sending %d / %d", self.sent, self.total)
end

-- Wall-clock estimate for the confirm line, so a 50-recipient run at one
-- second apart does not surprise anyone half a minute in.
function E.EstimateSeconds(count, delay)
    if count <= 1 then return 0 end
    return (count - 1) * (delay or 1)
end

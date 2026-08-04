-- Commander_Talents — the rules engine. Pure Lua, zero frames, zero WoW API:
-- everything here runs byte-identical under the offline harness. The UI owns
-- presentation; this file owns what a legal TBC build IS — the 61-point cap,
-- the (row-1)*5 tier gates, prerequisite chains, validated removal, and the
-- Wowhead-compatible digit-string serialization.

CommanderTalentsEngine = {}
local E = CommanderTalentsEngine

E.MAX_POINTS = 61        -- level 70 = 61 talent points (level 9 + N)
E.POINTS_PER_TIER = 5

-- ---------------------------------------------------------------------------
-- Class data preparation (memoized on the class table)
-- ---------------------------------------------------------------------------

-- Builds per-tree lookups: row-major order (the serialization order), name
-- index, resolved prerequisite index, and the dependents of each talent.
function E.Prepare(class)
    if class._idx then return class._idx end
    local idx = {}
    for t, tree in ipairs(class.trees) do
        local info = { byName = {}, order = {}, req = {}, deps = {} }
        for i, talent in ipairs(tree.talents) do
            info.byName[talent.name] = i
            info.order[#info.order + 1] = i
        end
        table.sort(info.order, function(a, b)
            local ta, tb = tree.talents[a], tree.talents[b]
            if ta.row ~= tb.row then return ta.row < tb.row end
            return ta.col < tb.col
        end)
        for i, talent in ipairs(tree.talents) do
            if talent.req then
                local ri = info.byName[talent.req]
                if ri then
                    info.req[i] = ri
                    info.deps[ri] = info.deps[ri] or {}
                    table.insert(info.deps[ri], i)
                end
            end
        end
        idx[t] = info
    end
    class._idx = idx
    return idx
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

function E.NewState(class)
    E.Prepare(class)
    return { class = class, pts = { {}, {}, {} } }
end

function E.Rank(state, t, i)
    return state.pts[t][i] or 0
end

function E.Spent(state, t)
    local sum = 0
    for _, rank in pairs(state.pts[t]) do
        sum = sum + rank
    end
    return sum
end

function E.TotalSpent(state)
    return E.Spent(state, 1) + E.Spent(state, 2) + E.Spent(state, 3)
end

-- Points spent in rows strictly above `row` of tree t (tier-gate currency)
function E.PointsAboveRow(state, t, row)
    local tree = state.class.trees[t]
    local sum = 0
    for i, rank in pairs(state.pts[t]) do
        if tree.talents[i].row < row then
            sum = sum + rank
        end
    end
    return sum
end

function E.Signature(state)
    return ("%d/%d/%d"):format(E.Spent(state, 1), E.Spent(state, 2), E.Spent(state, 3))
end

function E.RequiredLevel(state)
    local total = E.TotalSpent(state)
    if total == 0 then return 0 end
    return 9 + total
end

function E.Clear(state, t)
    if t then
        state.pts[t] = {}
    else
        state.pts[1], state.pts[2], state.pts[3] = {}, {}, {}
    end
end

-- ---------------------------------------------------------------------------
-- Legality
-- ---------------------------------------------------------------------------

-- Why can this talent not take a point right now? nil = it can.
-- Reasons: { type = "MAX" } | { type = "CAP" }
--        | { type = "TIER", need = n, have = n }
--        | { type = "REQ", name = s, need = n }
function E.AddBlock(state, t, i)
    local tree = state.class.trees[t]
    local talent = tree.talents[i]
    if E.Rank(state, t, i) >= talent.max then
        return { type = "MAX" }
    end
    if E.TotalSpent(state) >= E.MAX_POINTS then
        return { type = "CAP" }
    end
    local need = (talent.row - 1) * E.POINTS_PER_TIER
    local have = E.PointsAboveRow(state, t, talent.row)
    if have < need then
        return { type = "TIER", need = need, have = have }
    end
    local ri = state.class._idx[t].req[i]
    if ri then
        local reqTalent = tree.talents[ri]
        if E.Rank(state, t, ri) < reqTalent.max then
            return { type = "REQ", name = reqTalent.name, need = reqTalent.max }
        end
    end
    return nil
end

function E.CanAdd(state, t, i)
    return E.AddBlock(state, t, i) == nil
end

function E.Add(state, t, i)
    if not E.CanAdd(state, t, i) then return false end
    state.pts[t][i] = E.Rank(state, t, i) + 1
    return true
end

-- Why can a point not leave this talent? nil = it can.
-- Reasons: { type = "EMPTY" }
--        | { type = "SUPPORT", name = s }  -- a lower talent would lose tier support
--        | { type = "REQ", name = s }      -- a dependent would lose its prerequisite
function E.RemoveBlock(state, t, i)
    local rank = E.Rank(state, t, i)
    if rank == 0 then
        return { type = "EMPTY" }
    end
    local tree = state.class.trees[t]
    local talent = tree.talents[i]
    local newRank = rank - 1

    -- A dependent with points needs this talent at max
    if newRank < talent.max then
        local deps = state.class._idx[t].deps[i]
        if deps then
            for _, di in ipairs(deps) do
                if E.Rank(state, t, di) > 0 then
                    return { type = "REQ", name = tree.talents[di].name }
                end
            end
        end
    end

    -- Every talent with points below this one must keep its tier support.
    -- Removing a point at row R only drains support from rows > R.
    for j, jrank in pairs(state.pts[t]) do
        if jrank > 0 then
            local jt = tree.talents[j]
            if jt.row > talent.row then
                local have = E.PointsAboveRow(state, t, jt.row) - 1
                if have < (jt.row - 1) * E.POINTS_PER_TIER then
                    return { type = "SUPPORT", name = jt.name }
                end
            end
        end
    end
    return nil
end

function E.CanRemove(state, t, i)
    return E.RemoveBlock(state, t, i) == nil
end

function E.Remove(state, t, i)
    if not E.CanRemove(state, t, i) then return false end
    local rank = E.Rank(state, t, i) - 1
    state.pts[t][i] = rank > 0 and rank or nil
    return true
end

-- ---------------------------------------------------------------------------
-- Whole-build application (presets, imports, saved builds)
-- ---------------------------------------------------------------------------

-- Apply target ranks through the normal Add gate, looping until no progress:
-- row order alone isn't enough (horizontal prerequisites can point either
-- way), but a legal build always converges. Returns applied point count and
-- a list of problems (unknown names, unplaceable points).
local function ApplyTargets(state, targets)
    E.Clear(state)
    local problems = {}
    local wanted = {}
    for t = 1, 3 do
        local info = state.class._idx[t]
        for name, rank in pairs(targets[t] or {}) do
            local i = info.byName[name]
            if not i then
                problems[#problems + 1] = ("unknown talent '%s' (tree %d)"):format(tostring(name), t)
            elseif type(rank) == "number" and rank >= 1 then
                wanted[#wanted + 1] = { t = t, i = i, rank = math.floor(rank) }
            end
        end
    end
    local applied = 0
    local progress = true
    while progress do
        progress = false
        for _, w in ipairs(wanted) do
            while E.Rank(state, w.t, w.i) < w.rank and E.Add(state, w.t, w.i) do
                applied = applied + 1
                progress = true
            end
        end
    end
    for _, w in ipairs(wanted) do
        local got = E.Rank(state, w.t, w.i)
        if got < w.rank then
            local tree = state.class.trees[w.t]
            problems[#problems + 1] = ("%s stuck at %d/%d"):format(tree.talents[w.i].name, got, w.rank)
        end
    end
    return applied, problems
end

-- build.points = { [treeIdx] = { [talentName] = rank } }
function E.ApplyBuild(state, build)
    return ApplyTargets(state, build.points or {})
end

-- The player's live talents are legal by server decree; if our static data
-- disagrees on a position the gates must not fight the truth, so raw import
-- bypasses them (clamped to max rank so display stays sane).
function E.ApplyRaw(state, targets)
    E.Clear(state)
    local unknown = {}
    for t = 1, 3 do
        local info = state.class._idx[t]
        local tree = state.class.trees[t]
        for name, rank in pairs(targets[t] or {}) do
            local i = info.byName[name]
            if not i then
                if rank and rank > 0 then
                    unknown[#unknown + 1] = tostring(name)
                end
            elseif type(rank) == "number" and rank >= 1 then
                local max = tree.talents[i].max
                state.pts[t][i] = math.min(math.floor(rank), max)
            end
        end
    end
    return unknown
end

-- Snapshot as name->rank maps (custom build storage; survives data reorders)
function E.SerializePoints(state)
    local out = {}
    for t = 1, 3 do
        local tree = state.class.trees[t]
        local map = {}
        for i, rank in pairs(state.pts[t]) do
            map[tree.talents[i].name] = rank
        end
        out[t] = map
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Wowhead-compatible strings
-- ---------------------------------------------------------------------------

-- One digit per talent in row-major order, trailing zeros trimmed per tree,
-- trees joined with "-" and trailing empty trees dropped: "05023301-0550..."
function E.Export(state)
    local parts = {}
    for t = 1, 3 do
        local tree = state.class.trees[t]
        local info = state.class._idx[t]
        local digits = {}
        for pos, i in ipairs(info.order) do
            digits[pos] = tostring(E.Rank(state, t, i))
        end
        local s = table.concat(digits):gsub("0+$", "")
        parts[t] = s
    end
    while #parts > 0 and parts[#parts] == "" do
        table.remove(parts)
    end
    return table.concat(parts, "-")
end

-- Tolerant parse: accepts a bare digit string, a hyphenated triple, or a
-- pasted Wowhead URL (the segment after the last slash, query stripped).
-- Returns ok, errOrProblems.
function E.Import(state, text)
    if type(text) ~= "string" then return false, "nothing to import" end
    local s = text:gsub("%s+", "")
    s = s:gsub("[?#].*$", "")
    if s:find("/") then
        s = s:match(".*/(.-)$") or s
    end
    if s == "" then return false, "nothing to import" end
    if s:find("[^0-9%-]") then
        return false, "not a talent string (digits and dashes only)"
    end
    -- Manual split: gmatch("[^%-]*") emits phantom empty chunks after every
    -- match, silently shifting trees — walk the characters instead
    local parts = { "", "", "" }
    local n = 1
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == "-" then
            n = n + 1
            if n > 3 then return false, "too many tree sections" end
        else
            parts[n] = parts[n] .. c
        end
    end
    local targets = { {}, {}, {} }
    for t = 1, 3 do
        local tree = state.class.trees[t]
        local info = state.class._idx[t]
        local digits = parts[t]
        if #digits > #info.order then
            return false, ("too many digits for %s (%d talents)"):format(tree.name, #info.order)
        end
        for pos = 1, #digits do
            local rank = tonumber(digits:sub(pos, pos))
            local i = info.order[pos]
            local talent = tree.talents[i]
            if rank > talent.max then
                return false, ("%s caps at %d ranks"):format(talent.name, talent.max)
            end
            if rank > 0 then
                targets[t][talent.name] = rank
            end
        end
    end
    local applied, problems = ApplyTargets(state, targets)
    if #problems > 0 then
        return false, problems[1] .. (#problems > 1 and (" (+%d more)"):format(#problems - 1) or "")
    end
    if applied > E.MAX_POINTS then
        -- ApplyTargets can't overshoot (the CAP gate holds), but keep the
        -- contract explicit for the harness
        return false, "over 61 points"
    end
    return true, applied
end

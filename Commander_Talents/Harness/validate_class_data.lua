-- Commander_Talents data validator (offline, luajit).
-- Usage: luajit validate_class_data.lua <dataFile.lua> <CLASSTOKEN> <SPEC,KEYS,CSV>
-- Checks one generated class data file against the structural rules and the
-- talent-engine legality rules. Exits non-zero with a numbered error list on
-- any failure; prints ALL CHECKS PASSED plus a per-tree census on success.

local dataFile, classToken, specCSV = ...
if not (dataFile and classToken and specCSV) then
    io.stderr:write("usage: luajit validate_class_data.lua <file> <CLASS> <SPECS,CSV>\n")
    os.exit(2)
end

CommanderTalentsData = { Classes = {} }
local ok, err = pcall(dofile, dataFile)
if not ok then
    io.stderr:write("PARSE FAILED: " .. tostring(err) .. "\n")
    os.exit(1)
end

local errors = {}
local function fail(fmt, ...)
    errors[#errors + 1] = string.format(fmt, ...)
end

local class = CommanderTalentsData.Classes[classToken]
if type(class) ~= "table" then
    io.stderr:write("MISSING: CommanderTalentsData.Classes." .. classToken .. "\n")
    os.exit(1)
end

-- ---------------------------------------------------------------- trees
if type(class.trees) ~= "table" or #class.trees ~= 3 then
    io.stderr:write("MISSING: exactly 3 trees required\n")
    os.exit(1)
end

for ti, tree in ipairs(class.trees) do
    local where = ("tree %d (%s)"):format(ti, tostring(tree.name))
    if type(tree.name) ~= "string" or tree.name == "" then
        fail("%s: missing name", where)
    end
    if type(tree.bg) ~= "string" or tree.bg == "" then
        fail("%s: missing bg", where)
    end
    if type(tree.talents) ~= "table" or #tree.talents < 12 then
        fail("%s: needs a full talent list (found %d)", where, tree.talents and #tree.talents or 0)
    else
        local byName, byCell = {}, {}
        local row9 = 0
        for i, t in ipairs(tree.talents) do
            local tag = ("%s talent %d (%s)"):format(where, i, tostring(t.name))
            if type(t.name) ~= "string" or t.name == "" then fail("%s: missing name", tag) end
            if type(t.icon) ~= "string" or t.icon == "" then fail("%s: missing icon", tag) end
            if t.icon and t.icon:find("[\\/]") then fail("%s: icon must be the bare icon token, no path", tag) end
            if type(t.row) ~= "number" or t.row < 1 or t.row > 9 or t.row % 1 ~= 0 then
                fail("%s: bad row %s", tag, tostring(t.row))
            end
            if type(t.col) ~= "number" or t.col < 1 or t.col > 4 or t.col % 1 ~= 0 then
                fail("%s: bad col %s", tag, tostring(t.col))
            end
            if type(t.max) ~= "number" or t.max < 1 or t.max > 5 then
                fail("%s: bad max %s", tag, tostring(t.max))
            end
            if type(t.ranks) ~= "table" or #t.ranks ~= (t.max or 0) then
                fail("%s: ranks must have exactly max (%s) entries, found %s",
                    tag, tostring(t.max), tostring(t.ranks and #t.ranks))
            else
                for r, text in ipairs(t.ranks) do
                    if type(text) ~= "string" or #text < 10 then
                        fail("%s: rank %d text missing or too short", tag, r)
                    end
                end
            end
            if t.name then
                if byName[t.name] then fail("%s: duplicate name in tree", tag) end
                byName[t.name] = t
            end
            if t.row and t.col then
                local cell = t.row * 10 + t.col
                if byCell[cell] then
                    fail("%s: cell %d,%d already used by %s", tag, t.row, t.col, byCell[cell].name)
                end
                byCell[cell] = t
                if t.row == 9 then row9 = row9 + 1 end
            end
        end
        if row9 ~= 1 then
            fail("%s: expected exactly one 41-point talent at row 9, found %d", where, row9)
        end
        for i, t in ipairs(tree.talents) do
            if t.req then
                local target = byName[t.req]
                if not target then
                    fail("%s talent %s: req '%s' not found in tree", where, tostring(t.name), tostring(t.req))
                elseif target == t then
                    fail("%s talent %s: req points at itself", where, tostring(t.name))
                else
                    local vertical = target.col == t.col and target.row < t.row
                    local horizontal = target.row == t.row and math.abs(target.col - t.col) == 1
                    -- Bent arrows exist (TBC ships exactly one: Serrated
                    -- Blades 4,3 -> Hemorrhage 5,4): above and across
                    local bent = target.row < t.row and target.col ~= t.col
                    if not (vertical or horizontal or bent) then
                        fail("%s talent %s: req '%s' must sit above (straight or bent) or directly beside (req %d,%d vs %d,%d)",
                            where, tostring(t.name), t.req, target.row or 0, target.col or 0, t.row or 0, t.col or 0)
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------- engine rules
local function BuildLegal(tree, pts)
    -- pts: map name -> rank for one tree; returns ok, err
    local byName = {}
    for _, t in ipairs(tree.talents) do byName[t.name] = t end
    local total = 0
    for name, rank in pairs(pts) do
        local t = byName[name]
        if not t then return false, ("'%s' not in %s"):format(name, tree.name) end
        if type(rank) ~= "number" or rank < 1 or rank % 1 ~= 0 then
            return false, ("'%s' bad rank %s"):format(name, tostring(rank))
        end
        if rank > t.max then return false, ("'%s' rank %d over max %d"):format(name, rank, t.max) end
        total = total + rank
    end
    for name, rank in pairs(pts) do
        local t = byName[name]
        local below = 0
        for other, r in pairs(pts) do
            if byName[other].row < t.row then below = below + r end
        end
        if below < (t.row - 1) * 5 then
            return false, ("'%s' (row %d) lacks tier support: %d/%d points above it"):format(
                name, t.row, below, (t.row - 1) * 5)
        end
        if t.req then
            local reqTalent = byName[t.req]
            if reqTalent and (pts[t.req] or 0) < reqTalent.max then
                return false, ("'%s' requires %d/%d %s"):format(name, reqTalent.max, reqTalent.max, t.req)
            end
        end
    end
    return true, total
end

-- ---------------------------------------------------------------- builds
local wantSpecs = {}
local specCount = 0
for key in specCSV:gmatch("[^,]+") do
    wantSpecs[key] = false
    specCount = specCount + 1
end

if type(class.builds) ~= "table" or #class.builds < 1 then
    fail("builds: missing")
else
    for bi, b in ipairs(class.builds) do
        local tag = ("build %d (%s)"):format(bi, tostring(b.key))
        if wantSpecs[b.key] == nil then
            fail("%s: key not in the Quartermaster spec list (%s)", tag, specCSV)
        elseif wantSpecs[b.key] then
            fail("%s: duplicate key", tag)
        else
            wantSpecs[b.key] = true
        end
        if type(b.name) ~= "string" or b.name == "" then fail("%s: missing name", tag) end
        if type(b.role) ~= "string" then fail("%s: missing role", tag) end
        if type(b.stats) ~= "table" or #b.stats < 3 then fail("%s: stats needs a real priority list", tag) end
        if type(b.notes) ~= "string" or #b.notes < 20 then fail("%s: notes missing", tag) end
        if type(b.points) ~= "table" then
            fail("%s: points missing", tag)
        else
            local grand = 0
            for ti = 1, 3 do
                local pts = b.points[ti]
                if pts then
                    local ok2, res = BuildLegal(class.trees[ti], pts)
                    if not ok2 then
                        fail("%s tree %d: %s", tag, ti, res)
                    else
                        grand = grand + res
                    end
                end
            end
            if grand ~= 61 then
                fail("%s: totals %d points, must be exactly 61", tag, grand)
            end
        end
    end
    for key, seen in pairs(wantSpecs) do
        if not seen then fail("builds: spec key %s has no build", key) end
    end
end

-- ---------------------------------------------------------------- verdict
if #errors > 0 then
    io.stderr:write(("%d PROBLEM(S) in %s:\n"):format(#errors, dataFile))
    for i, e in ipairs(errors) do
        io.stderr:write(("  %2d. %s\n"):format(i, e))
    end
    os.exit(1)
end

for ti, tree in ipairs(class.trees) do
    local sum = 0
    for _, t in ipairs(tree.talents) do sum = sum + t.max end
    print(("  tree %d %-16s %2d talents, %2d max points"):format(ti, tree.name, #tree.talents, sum))
end
print(("ALL CHECKS PASSED — %s (%d builds / %d specs)"):format(classToken, #class.builds, specCount))

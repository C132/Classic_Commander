-- Commander_Talents PvP build validator (offline, luajit).
--   luajit Harness/validate_pvp.lua [CLASSTOKEN]
-- With no argument every class is checked. Loads the real class data and the
-- real engine, then proves each PvP build is a LEGAL 61-point TBC build:
-- every talent name resolves, tier gates and prerequisites are satisfied in
-- some order, and the totals land exactly on 61. Also checks the metadata the
-- UI relies on (bracket, qmSpec, stats, notes) and that keys are unique and
-- do not collide with the PvE preset keys.

local only = ...

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
local ROOT = HERE:match("^(.*)/Harness$") or "."

dofile(ROOT .. "/CommanderTalentsData.lua")
for _, cls in ipairs({ "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
                       "Shaman", "Mage", "Warlock", "Druid" }) do
    dofile(ROOT .. "/CommanderTalentsData_" .. cls .. ".lua")
end
dofile(ROOT .. "/CommanderTalentsEngine.lua")

local pvpPath = ROOT .. "/CommanderTalentsPvP.lua"
local f = io.open(pvpPath, "r")
if not f then
    io.stderr:write("MISSING: " .. pvpPath .. "\n")
    os.exit(1)
end
f:close()
local ok, err = pcall(dofile, pvpPath)
if not ok then
    io.stderr:write("PARSE FAILED: " .. tostring(err) .. "\n")
    os.exit(1)
end

local Data = CommanderTalentsData
local E = CommanderTalentsEngine

local VALID_BRACKET = { ARENA = true, BG = true, DUEL = true, WORLD = true }
local VALID_ROLE = { TANK = true, HEALER = true, MELEE = true, CASTER = true, RANGED = true }

local problems = {}
local function fail(fmt, ...) problems[#problems + 1] = string.format(fmt, ...) end

local totalBuilds = 0
local perClass = {}

for _, token in ipairs(Data.ClassOrder) do
    if not only or only == token then
        local class = Data.Classes[token]
        if not class then
            fail("%s: class data missing", token)
        else
            local list = class.pvpBuilds
            if type(list) ~= "table" or #list == 0 then
                fail("%s: no PvP builds", token)
            else
                local seen = {}
                local pveKeys = {}
                for _, b in ipairs(class.builds or {}) do pveKeys[b.key] = true end

                for _, b in ipairs(list) do
                    local tag = ("%s/%s"):format(token, tostring(b.key))
                    totalBuilds = totalBuilds + 1

                    if type(b.key) ~= "string" or b.key == "" then
                        fail("%s: missing key", tag)
                    elseif seen[b.key] then
                        fail("%s: duplicate key", tag)
                    elseif pveKeys[b.key] then
                        fail("%s: key collides with a PvE preset", tag)
                    end
                    seen[b.key] = true

                    if type(b.name) ~= "string" or b.name == "" then
                        fail("%s: missing name", tag)
                    end
                    if not VALID_ROLE[b.role] then
                        fail("%s: bad role %s", tag, tostring(b.role))
                    end
                    if not VALID_BRACKET[b.bracket] then
                        fail("%s: bad bracket %s (ARENA|BG|DUEL|WORLD)", tag, tostring(b.bracket))
                    end
                    if b.qmSpec ~= nil then
                        local found = false
                        for _, p in ipairs(class.builds or {}) do
                            if p.key == b.qmSpec then found = true end
                        end
                        if not found then
                            fail("%s: qmSpec '%s' is not a PvE preset key of this class",
                                tag, tostring(b.qmSpec))
                        end
                    end
                    if type(b.stats) ~= "table" or #b.stats < 3 then
                        fail("%s: stats needs a real priority list", tag)
                    end
                    if type(b.notes) ~= "string" or #b.notes < 20 then
                        fail("%s: notes missing or too short", tag)
                    end

                    if type(b.points) ~= "table" then
                        fail("%s: points missing", tag)
                    else
                        local state = E.NewState(class)
                        local _, probs = E.ApplyBuild(state, b)
                        for _, p in ipairs(probs) do
                            fail("%s: %s", tag, p)
                        end
                        local spent = E.TotalSpent(state)
                        if spent ~= 61 then
                            fail("%s: totals %d points, must be exactly 61", tag, spent)
                        end
                        if #probs == 0 and spent == 61 then
                            perClass[token] = perClass[token] or {}
                            table.insert(perClass[token], ("    %-22s %-6s %s"):format(
                                b.name, b.bracket, E.Signature(state)))
                        end
                    end
                end
            end
        end
    end
end

if #problems > 0 then
    io.stderr:write(("%d PROBLEM(S):\n"):format(#problems))
    for i, p in ipairs(problems) do
        io.stderr:write(("  %2d. %s\n"):format(i, p))
    end
    os.exit(1)
end

for _, token in ipairs(Data.ClassOrder) do
    if perClass[token] then
        print(token)
        for _, line in ipairs(perClass[token]) do print(line) end
    end
end
print(("ALL PVP BUILDS VALID — %d build(s)%s"):format(
    totalBuilds, only and (" for " .. only) or ""))

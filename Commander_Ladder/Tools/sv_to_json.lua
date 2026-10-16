-- Prints one global from a Lua data file as JSON (luajit).
--
--   /opt/homebrew/bin/luajit sv_to_json.lua <file> <GlobalName>
--
-- ladder_feed.py reads two Lua files this way: the game's SavedVariables
-- (CommanderLadderWanted, the names the addon wants looked up) and the
-- previous CommanderLadderData.lua (entries carried over between runs).
--
-- The file runs in an EMPTY environment: no os, io, require or load, so a
-- damaged or hostile file can only fail, not act. Table keys become JSON
-- object keys (numbers as strings); anything that is not a string, number,
-- boolean or table is dropped. Prints "null" when the global is absent.

local path, name = arg[1], arg[2]
if not path or not name then
    io.stderr:write("usage: sv_to_json.lua <file> <GlobalName>\n")
    os.exit(2)
end

local chunk, err = loadfile(path)
if not chunk then
    io.stderr:write("cannot load: ", tostring(err), "\n")
    os.exit(1)
end
local env = {}
setfenv(chunk, env)
local ok, runErr = pcall(chunk)
if not ok then
    io.stderr:write("cannot run: ", tostring(runErr), "\n")
    os.exit(1)
end

local function quote(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

local encode
encode = function(v, depth)
    if depth > 20 then return "null" end
    local t = type(v)
    if t == "string" then return quote(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        return string.format("%.17g", v)
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "null" end
    local parts = {}
    for k, val in pairs(v) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            local inner = encode(val, depth + 1)
            if inner ~= "null" or type(val) == "boolean" then
                parts[#parts + 1] = quote(tostring(k)) .. ":" .. inner
            end
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

io.write(encode(env[name], 0), "\n")

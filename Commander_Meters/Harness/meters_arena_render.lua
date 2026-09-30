-- Commander Meters ARENA REPORT renderer (luajit)
--
--     luajit Commander_Meters/Harness/meters_arena_render.lua report.json [cursorT]
--     python3 Commander_ArenaFrames/Harness/render_svg.py report.json report.svg 2
--     qlmanage -t -s 1800 -o . report.svg
--
-- The UI smoke's mock records every SetPoint, SetSize, colour, texture,
-- font size and text. This runs the smoke and, at the moment the Arena
-- Report is up and painted on the canned 3v3, resolves every anchor to
-- an absolute rectangle and writes the lot for Arena Frames' SVG script
-- (the record shape is the same). Not the game's art; the layout code's
-- own numbers — which is the half of "does it look right" that a queue
-- is not needed for. Text widths are estimated (no font metrics here),
-- so labels can look tighter or looser than the client draws them;
-- positions, sizes and colours are exact.
--
-- The optional second argument scrubs the cursor to that many seconds
-- before the dump, so the HP strips, control tags and cooldown tags are
-- in the picture.

local out = arg and arg[1] or "meters_arena_render.json"
local cursorT = arg and arg[2] and tonumber(arg[2]) or nil
-- A third argument of "5v5" synthesizes a five-a-side match through the
-- engine and opens the replay on it: the tallest layout the window takes
local fiveVfive = arg and arg[3] == "5v5"

_G.__widgets = {}

local function AnchorOf(point, rect)
    local l, b, w, h = rect.l, rect.b, rect.w, rect.h
    local x, y
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = l + w else x = l + w / 2 end
    if point:find("TOP") then y = b + h elseif point:find("BOTTOM") then y = b else y = b + h / 2 end
    return x, y
end

local resolved = {}

local function TextWidth(widget)
    local text = widget.__text or ""
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "##")
    local size = widget.__font and widget.__font[2] or 10
    return #text * size * 0.5, size
end

local Resolve
Resolve = function(widget)
    if resolved[widget] ~= nil then return resolved[widget] or nil end
    resolved[widget] = false
    local parent = widget.__parent
    if type(parent) ~= "table" then
        if widget.__name == "UIParent" then
            resolved[widget] = { l = 0, b = 0, w = 1920, h = 1080 }
            return resolved[widget]
        end
        parent = nil
    end
    local pr = parent and Resolve(parent)
    local w, h = widget.__w, widget.__h
    if widget.__kind == "FontString" then
        local tw, size = TextWidth(widget)
        w = w or tw
        h = h or (size * 1.2)
    end
    local points = widget.__points or {}
    local all = widget.__allPoints
    if all then
        local ref = (type(all) == "table") and Resolve(all) or pr
        if ref then
            resolved[widget] = { l = ref.l, b = ref.b, w = ref.w, h = ref.h }
            return resolved[widget]
        end
    end
    if #points == 0 then
        if pr and (widget.__kind == "Texture") then
            resolved[widget] = { l = pr.l, b = pr.b, w = pr.w, h = pr.h }
        elseif pr then
            resolved[widget] = { l = pr.l, b = pr.b, w = w or pr.w, h = h or pr.h }
        else
            resolved[widget] = { l = 0, b = 0, w = w or 0, h = h or 0 }
        end
        return resolved[widget]
    end
    local left, right, cx, top, bottom, cy
    for _, p in ipairs(points) do
        local rel, relPoint, x, y = p.rel, p.relPoint, p.x, p.y
        if type(rel) == "number" then
            x, y, rel, relPoint = rel, relPoint, nil, nil
        elseif type(relPoint) == "number" then
            x, y, relPoint = relPoint, x, nil
        end
        if type(rel) ~= "table" then rel = parent end
        local rr = rel and Resolve(rel)
        if rr then
            local ax, ay = AnchorOf(relPoint or p.point, rr)
            ax, ay = ax + (x or 0), ay + (y or 0)
            local pt = p.point
            if pt:find("LEFT") then left = ax elseif pt:find("RIGHT") then right = ax else cx = ax end
            if pt:find("TOP") then top = ay elseif pt:find("BOTTOM") then bottom = ay else cy = ay end
        end
    end
    local l, ww, b, hh
    if left and right then l, ww = left, right - left
    elseif left then l, ww = left, w or 0
    elseif right then ww = w or 0; l = right - ww
    elseif cx then ww = w or 0; l = cx - ww / 2
    else l, ww = pr and pr.l or 0, w or 0 end
    if top and bottom then b, hh = bottom, top - bottom
    elseif bottom then b, hh = bottom, h or 0
    elseif top then hh = h or 0; b = top - hh
    elseif cy then hh = h or 0; b = cy - hh / 2
    else b, hh = pr and pr.b or 0, h or 0 end
    resolved[widget] = { l = l, b = b, w = ww, h = hh }
    return resolved[widget]
end

local function Visible(widget)
    local w = widget
    while type(w) == "table" do
        if w.__shown == false then return false end
        w = w.__parent
    end
    return true
end

local function Ancestor(widget, root)
    local w = widget
    while type(w) == "table" do
        if w == root then return true end
        w = w.__parent
    end
    return false
end

local function Depth(widget)
    local d, w = 0, widget
    while type(w) == "table" do d = d + 1; w = w.__parent end
    return d
end

local function JsonString(s)
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

_G.__afterArenaReport = function(report)
    if fiveVfive then
        local A = CommanderMetersArena
        local T0 = time() - 400
        local m5 = A.Begin(T0, "Blade's Edge Arena")
        local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "DRUID" }
        local us, them = {}, {}
        for i = 1, 5 do
            us[i], them[i] = "Player-0-F" .. i, "Player-1-E" .. i
            A.SetSeat("us", us[i], "Friend" .. i, classes[i], nil, i == 1 and "player" or ("party" .. (i - 1)), "Spec")
            A.SetSeat("them", them[i], "Enemy" .. i, classes[6 - i], nil, "arena" .. i)
            A.SetHealth(us[i], 7000 + i * 300, 9000, T0 + 10)
            A.SetHealth(them[i], 4000 + i * 500, 9000, T0 + 10)
            A.SetPower(us[i], 500 + i * 80, 1000, i % 2 == 0 and 0 or 3, T0 + 10)
            A.SetPower(them[i], 900 - i * 100, 1000, 0, T0 + 10)
        end
        A.OnCleu(T0 + 60, "SPELL_AURA_REMOVED", nil, us[1], "Friend1", 0x511, 0, us[1], "Friend1", 0x511, 0, 32727, "Arena Preparation", 1, "BUFF")
        for i = 1, 5 do
            A.OnCleu(T0 + 70 + i, "SPELL_DAMAGE", nil, us[i], "Friend" .. i, 0x512, 0, them[i], "Enemy" .. i, 0x548, 0,
                27072, "Frostbolt", 16, 1500, 0, 16, 0, 0, 0, false, false, false, false)
            A.OnCleu(T0 + 70 + i, "SPELL_AURA_APPLIED", nil, them[i], "Enemy" .. i, 0x548, 0, us[i], "Friend" .. i, 0x512, 0, 1715 + i, "Debuff" .. i, 1, "DEBUFF")
            A.OnCleu(T0 + 70 + i, "SPELL_AURA_APPLIED", nil, us[i], "Friend" .. i, 0x512, 0, us[i], "Friend" .. i, 0x512, 0, 2000 + i, "Buff" .. i, 1, "BUFF")
        end
        A.OnCleu(T0 + 80, "SPELL_AURA_APPLIED", nil, us[3], "Friend3", 0x512, 0, them[3], "Enemy3", 0x548, 0, 12826, "Polymorph", 1, "DEBUFF")
        A.OnCleu(T0 + 82, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, them[5], "Enemy5", 0x548, 0)
        A.Finish(T0 + 100, "WIN", 40)
        CommanderMetersArena_Open(nil, m5.id)
        CommanderMetersArena_View().t = 81
        report.__scripts.OnUpdate(report, 0.6)
    end
    if cursorT then
        CommanderMetersArena_View().t = cursorT
        report.__scripts.OnUpdate(report, 0.6)
    end
    -- The mock's GetWidth answers 0, so painters fell back to their
    -- constants; resolve real widths for the bar-style textures whose
    -- width was computed from a fraction of a 0-wide parent by re-running
    -- the repaint with GetWidth answering from the resolved rectangles
    for _, w in ipairs(_G.__widgets) do
        if Ancestor(w, report) then
            local r = Resolve(w)
            if r and r.w and r.w > 0 then
                rawset(w, "GetWidth", function() return r.w end)
                rawset(w, "GetHeight", function() return r.h end)
            end
        end
    end
    resolved = {}
    report.__scripts.OnUpdate(report, 0.6)
    resolved = {}
    local rows = {}
    for _, w in ipairs(_G.__widgets) do
        if w ~= report and Ancestor(w, report) and Visible(w) then
            local r = Resolve(w)
            if r and r.w and r.h and r.w > 0 and r.h > 0 then
                local color = w.__color or {}
                local just = "middle"
                if w.__justify == "LEFT" then just = "start"
                elseif w.__justify == "RIGHT" then just = "end" end
                rows[#rows + 1] = string.format(
                    '{"just":"' .. just .. '","kind":%s,"depth":%d,"level":%d,"layer":%s,"sub":%d,"l":%.2f,"b":%.2f,"w":%.2f,"h":%.2f,'
                    .. '"r":%.3f,"g":%.3f,"bl":%.3f,"a":%.3f,"tex":%s,"text":%s,"font":%d,"desat":false,"alpha":%.2f,"cd":null}',
                    JsonString(w.__kind), Depth(w), 0, JsonString(w.__layer or ""),
                    w.__sublevel or 0, r.l, r.b, r.w, r.h,
                    color[1] or 1, color[2] or 1, color[3] or 1, color[4] == nil and 1 or color[4],
                    JsonString(w.__texture or ""), JsonString(w.__text or ""),
                    w.__font and w.__font[2] or 10, w.__alpha or 1)
            end
        end
    end
    local rootRect = Resolve(report)
    local fh = assert(io.open(out, "w"))
    fh:write(string.format('{"root":{"l":%.2f,"b":%.2f,"w":%.2f,"h":%.2f},"widgets":[\n%s\n]}\n',
        rootRect.l, rootRect.b, rootRect.w, rootRect.h, table.concat(rows, ",\n")))
    fh:close()
    io.write("wrote ", out, " (", #rows, " widgets)\n")
end

dofile((debug.getinfo(1, "S").source:gsub("^@", ""):gsub("meters_arena_render%.lua$", "meters_ui_harness.lua")))

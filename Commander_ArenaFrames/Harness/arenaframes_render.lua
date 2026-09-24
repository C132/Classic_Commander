-- Commander Arena Frames renderer (luajit)
--
--     luajit Commander_ArenaFrames/Harness/arenaframes_render.lua [out.json]
--     python3 Commander_ArenaFrames/Harness/render_svg.py out.json out.svg
--
-- The board smoke next door loads the module over a WoW mock that RECORDS
-- every SetPoint, SetSize, colour, texture and text. That record is enough
-- to draw the board -- not with the game's art, but with the real layout
-- code's own numbers, which is the half of "does it look right" that can be
-- answered without a queue. This runs the smoke, and at the moment the test
-- board is up and painted, walks every widget, resolves its anchors to an
-- absolute rectangle, and writes the lot as JSON for render_svg.py.
--
-- Anchors are resolved the way the client does it: each SetPoint pins one
-- point of the region to a point on another region plus an offset; two
-- points on different axes fix a size, one point falls back to the recorded
-- SetSize/SetWidth/SetHeight. Regions with no points at all fill their
-- parent, which is what SetAllPoints means and what an unanchored texture
-- does in practice on this board.

local out = arg and arg[1] or "arenaframes_render.json"

-- Settings to draw under, as Lua table syntax in the second argument:
--     luajit .../arenaframes_render.lua tight.json '{ Density = "TIGHT" }'
-- and a third argument of "calm" clears the third enemy's state so a row
-- with a plain name on it is in the picture too.
local overrides = arg and arg[2] and assert(loadstring("return " .. arg[2]))() or {}
local calm = arg and arg[3] == "calm"

_G.__widgets = {}

_G.__beforeTestBoard = function()
    for key, value in pairs(overrides) do CommanderArenaFramesDB[key] = value end
    Commander.Notify(COMMANDER_ARENAFRAMES_EVENTS.UPDATE)
end

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
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local size = widget.__font and widget.__font[2] or 10
    return #text * size * 0.55, size
end

local Resolve
Resolve = function(widget)
    if resolved[widget] ~= nil then return resolved[widget] or nil end
    resolved[widget] = false   -- cycle guard
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
        -- SetPoint's three shapes: (point, x, y), (point, rel, x, y) and
        -- the full (point, rel, relPoint, x, y). The mock records them
        -- positionally, so they are told apart here by type.
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

_G.__afterTestBoard = function(Tick)
    local root = _G.CommanderArenaFramesFrame
    local restore
    if calm and Tick then
        -- The third seat, with nothing on them: the row as it looks for
        -- most of a game, name and all. Put back afterwards, so the smoke's
        -- own checks below the hook still see the board they expect.
        local row = _G.CommanderArenaFramesRow3
        local entry = row and row._entry
        if entry then
            local saved = { control = entry.control, immunity = entry.immunity,
                            drinking = entry.drinking, stealth = entry.stealth, notes = entry.notes }
            entry.control, entry.immunity, entry.drinking, entry.stealth = nil, nil, nil, nil
            entry.notes = {}
            restore = function()
                for k, v in pairs(saved) do entry[k] = v end
                Tick()
            end
        end
        Tick()
    end
    local rows = {}
    for _, w in ipairs(_G.__widgets) do
        if w ~= root and Ancestor(w, root) and Visible(w) then
            local r = Resolve(w)
            if r and r.w and r.h and r.w > 0 and r.h > 0 then
                local color = w.__color or {}
                -- Which way text grows from its anchor, from the anchor itself
                -- SetJustifyH decides where text sits in its rectangle; only
                -- a string that was never told falls back to its anchor.
                local just = "middle"
                if w.__justify == "LEFT" then just = "start"
                elseif w.__justify == "RIGHT" then just = "end"
                elseif w.__justify == nil then
                    for _, p in ipairs(w.__points or {}) do
                        if p.point:find("RIGHT") then just = "end" elseif p.point:find("LEFT") then just = "start" end
                    end
                end
                rows[#rows + 1] = string.format(
                    '{"just":"' .. just .. '","kind":%s,"depth":%d,"level":%d,"layer":%s,"sub":%d,"l":%.2f,"b":%.2f,"w":%.2f,"h":%.2f,'
                    .. '"r":%.3f,"g":%.3f,"bl":%.3f,"a":%.3f,"tex":%s,"text":%s,"font":%d,"desat":%s,"alpha":%.2f,"cd":%s}',
                    JsonString(w.__kind), Depth(w), rawget(w, "__level") or 0, JsonString(w.__layer or ""),
                    w.__sublevel or 0, r.l, r.b, r.w, r.h,
                    color[1] or 1, color[2] or 1, color[3] or 1, color[4] == nil and 1 or color[4],
                    JsonString(w.__texture or ""), JsonString(w.__text or ""),
                    w.__font and w.__font[2] or 10, tostring(w.__desat or false), w.__alpha or 1,
                    (w.__kind == "Cooldown" and w.__cdDur) and string.format('[%.2f,%.2f,%.2f]', w.__cdStart, w.__cdDur, GetTime()) or "null")
            end
        end
    end
    local rootRect = Resolve(root)
    local fh = assert(io.open(out, "w"))
    fh:write(string.format('{"root":{"l":%.2f,"b":%.2f,"w":%.2f,"h":%.2f},"widgets":[\n%s\n]}\n',
        rootRect.l, rootRect.b, rootRect.w, rootRect.h, table.concat(rows, ",\n")))
    fh:close()
    io.write("wrote ", out, " (", #rows, " widgets)\n")
    if restore then restore() end
end

dofile((debug.getinfo(1, "S").source:gsub("^@", ""):gsub("arenaframes_render%.lua$", "arenaframes_board_smoke.lua")))

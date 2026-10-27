-- Commander Spellbook renderer: the painted window's rectangles as JSON.
--
--   RENDER=book.json RENDER_TRAIN=train.json \
--     /opt/homebrew/bin/luajit Commander_Spellbook/Harness/spellbook_harness.lua
--   python3 Commander_Spellbook/Harness/render_svg.py book.json book.svg
--
-- Called by the harness once its checks are done, with the mock, the window
-- and the output path. Every visible region under the window (and every
-- shown cast button, drawn as a dashed outline) is resolved through the
-- mock's anchor resolver and written with its kind, layer, colour, texture,
-- text and the scroll frame it is clipped to. Not the game's art: what is
-- real is every position, size and string -- the layout's own numbers.

return function(M, root, out)
    local function Ancestor(w, target)
        while type(w) == "table" do
            if w == target then return true end
            w = rawget(w, "__parent")
        end
        return false
    end
    local function ClipOf(w)
        local p = rawget(w, "__parent")
        while type(p) == "table" do
            if rawget(p, "__scroller") then return p.__scroller end
            p = rawget(p, "__parent")
        end
        return nil
    end
    local function Depth(w)
        local d = 0
        while type(w) == "table" do d = d + 1 w = rawget(w, "__parent") end
        return d
    end
    local function J(s)
        return '"' .. tostring(s or ""):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    end
    local function Color(c)
        c = c or {}
        return string.format("[%.3f,%.3f,%.3f,%.3f]", c[1] or 1, c[2] or 1, c[3] or 1, c[4] == nil and 1 or c[4])
    end
    -- Draw order is the client's: frame level first (a frame is its
    -- parent's level plus one unless it was given one), then layer
    local function Level(w)
        if w.__kind == "Texture" or w.__kind == "FontString" then w = rawget(w, "__parent") end
        local chain = {}
        while type(w) == "table" do chain[#chain + 1] = w w = rawget(w, "__parent") end
        local level = 0
        for i = #chain, 1, -1 do
            local f = chain[i]
            level = rawget(f, "__level") or (level + 1)
        end
        return level
    end
    local rows = {}
    local clips, clipIds = {}, {}
    local function ClipId(scroll)
        if not scroll then return 0 end
        if not clipIds[scroll] then
            local r = M.Resolve(scroll)
            clips[#clips + 1] = string.format("[%.2f,%.2f,%.2f,%.2f]", r.l, r.b, r.w, r.h)
            clipIds[scroll] = #clips
        end
        return clipIds[scroll]
    end
    for index, w in ipairs(M.widgets) do
        local inWindow = w ~= root and Ancestor(w, root)
        local cast = w.__template and w.__template:find("Secure") and w.__shown
        if (inWindow and M.Visible(w)) or cast then
            local r = M.Resolve(w)
            if r.w > 0 and r.h > 0 then
                rows[#rows + 1] = string.format(
                    '{"i":%d,"kind":%s,"depth":%d,"layer":%s,"sub":%d,"l":%.2f,"b":%.2f,"w":%.2f,"h":%.2f,"color":%s,'
                    .. '"tex":%s,"text":%s,"font":%d,"just":%s,"desat":%s,"alpha":%.2f,"clip":%d,"backdrop":%s,"bd":%s,"bdb":%s,"cast":%s,"tmpl":%s,"fs":%s,"level":%d}',
                    index, J(w.__kind), Depth(w), J(w.__layer), w.__sublevel or 0, r.l, r.b, r.w, r.h, Color(w.__color),
                    J(w.__texture), J(w.__text), w.__font and w.__font[2] or 10, J(w.__justify),
                    tostring(w.__desat or false), w.__alpha or 1, cast and 0 or ClipId(ClipOf(w)),
                    tostring(w.__backdrop ~= nil), Color(w.__bdcolor), Color(w.__bdborder), tostring(cast and true or false),
                    J(w.__template), Color(rawget(w, "__fs") and w.__fs.__color), Level(w))
            end
        end
    end
    local rr = M.Resolve(root)
    local fh = assert(io.open(out, "w"))
    fh:write(string.format('{"root":[%.2f,%.2f,%.2f,%.2f],"clips":[%s],"widgets":[\n%s\n]}\n',
        rr.l, rr.b, rr.w, rr.h, table.concat(clips, ","), table.concat(rows, ",\n")))
    fh:close()
    io.write("wrote ", out, " (", #rows, " regions)\n")
end

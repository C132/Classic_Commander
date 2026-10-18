-- Commander.UI.GoButton: the one "Go to" button every Commander module uses.
--
-- Commander Orders 3.1 (its SPEC 1, critic D1-D3) moved every module's own
-- waypoint lookup and /way formatter into Orders' API. What is left for a
-- module is a button, and this is it, so a Go reads, clicks and refuses the
-- same way in the Quest Log, the profession windows, the TopBar and the
-- rest. It lives in Commander_Events because every module requires Events
-- and only some list Commander_Orders: without Orders a button that knows its
-- coordinates still prints a /way line, and one that needs a lookup greys
-- out saying so.
--
--   local b = Commander.UI.GoButton(parent, {
--       label = "Go" | "Go to Innkeeper",   -- "Go" on a row, "Go to <Thing>" alone
--       width = 60, height = 22,            -- optional (width follows the label)
--       spec = function(button) return { map, x, y, title [, alternatives] } end,
--       query = function(button) return { townsfolk = "Innkeeper" } end,  -- or spec
--       source = "QuestLog", key = "quest:123",   -- who owns the waypoint
--       title = "Innkeeper Farley",         -- string or function(button)
--       tooltip = "...",                    -- optional extra line(s): string or function(button)
--       icon = "QUEST",                     -- Orders' icon key for the waypoint's pin and row
--       note, persistent, temporary, clearOnArrive, setArrow, silent,  -- passed to GoTo
--       onGo = function(uid, reason) end,   -- optional, after a click
--   })
--   b:Refresh()            -- after the module's own data changed
--   Commander.UI.GoRowHint -- "Ctrl+Right-click: Go", for a list row's tooltip
--
-- spec and query may also be plain tables. A spec or query function that
-- cannot go may answer nil, reason: an Orders reason code ("instance",
-- "nowhere", ...; CommanderOrders.Reason words it) or a sentence of its own,
-- shown red in the tooltip and printed on a click. opts.source and opts.key
-- are read AFTER spec / query run, so a spec function may re-point the
-- button (b._goOpts.key = "quest:" .. id) to follow a selection.
-- Behaviour (one rule, written in Orders' DECISIONS D31 and cited by every
-- consumer):
--   click        CommanderOrders.GoTo(spec or query, opts)
--   Shift-click  the place in chat for everyone: CommanderOrders.SharePoint
--                (..., "CHAT"): your group's chat, else /say, as Orders'
--                readable line "Title - Zone 45.2, 66.8 (/way ...)"
--   Ctrl-click   the /way line in Orders' copy box
--   tooltip      "Go to: <title> - <zone> <coords>", the click hints, and
--                the reason when it cannot go
--   disabled     greyed, the reason in the tooltip, while Orders is absent
--                (a query only), turned off or loading, or the spec / query
--                answers nothing. The tooltip shows on a greyed button
--                because the button runs its motion scripts while disabled
--                (SetMotionScriptsWhileDisabled: off by default on 2.5.6,
--                where a disabled Button gets no OnEnter and no OnClick;
--                Blizzard turns it on wherever a greyed button explains
--                itself). An enabled query whose lookup answers nothing (no
--                Questie, Questie loading, none on your landmass) says
--                Orders' reason in the same red line instead of a place.
--                Greyed for Orders' own state (turned off, loading, or
--                absent for a query) the tooltip leaves out opts.tooltip:
--                a module's line says what a press does, and a greyed
--                button takes none (review-r2: three promised a chat line).
--                A reason of the spec's or query's own keeps it (the
--                module's line may explain the condition)
--   lit          "Going" ("Going to <Thing>") with the highlight locked while
--                the arrow's target belongs to (source, key):
--                CommanderOrders.IsGoing, refreshed on COMMANDER_ORDERS_EVENTS
--                CHANGED and UPDATE
--
-- A plain Button (UIPanelButtonTemplate unless opts.template says another):
-- never secure, so enabling and relabelling it is legal in combat and it
-- may sit on any frame. No glyphs in any text (suite D11). Writes no global.

Commander = Commander or {}
Commander.UI = Commander.UI or {}
local UI = Commander.UI

local type, pairs, pcall, tostring = type, pairs, pcall, tostring
local format = string.format

UI.GoRowHint = "Ctrl+Right-click: Go"

-- The words the button says without Orders (with it, CommanderOrders.Reason)
local OWN_WORDS = {
    needsorders = "Needs Commander Orders",
    nowhere = "No known location",
}

-- The reasons that grey every Go alike, Orders' own state rather than the
-- place's: the module's extra tooltip line is left out under them
local ORDERS_STATES = { disabled = true, loading = true, needsorders = true }

local buttons = setmetatable({}, { __mode = "k" })
local listening = false

local function Orders()
    local o = CommanderOrders
    if type(o) == "table" and type(o.GoTo) == "function" then return o end
    return nil
end

-- A value or what its function answers (and the reason it gives with nil)
local function Value(v, button)
    if type(v) == "function" then
        local ok, r, why = pcall(v, button)
        if ok then return r, why end
        return nil
    end
    return v
end

local function Words(why)
    local o = Orders()
    if o and type(o.Reason) == "function" then
        local text = o.Reason(why)
        if type(text) == "string" then return text end
    end
    return OWN_WORDS[why] or tostring(why)
end

local function Say(msg)
    print("Commander: " .. msg)
end

-- The first spot of a spec in either shape
local function SpotOf(spec)
    if type(spec) ~= "table" then return nil end
    local m, x, y = spec.map, spec.x, spec.y
    if type(m) ~= "number" and type(spec.alternatives) == "table" then
        local a = spec.alternatives[1]
        if type(a) == "table" then m, x, y = a.map or a[1], a.x or a[2], a.y or a[3] end
    end
    if type(m) == "number" and type(x) == "number" and type(y) == "number" then return m, x, y end
    return nil
end

-- spec, query, reason (nil when it can go)
local function Evaluate(b)
    local o = b._goOpts
    local spec, specWhy, query, queryWhy
    if o.spec ~= nil then spec, specWhy = Value(o.spec, b) end
    if type(spec) ~= "table" then spec = nil end
    if spec == nil and o.query ~= nil then query, queryWhy = Value(o.query, b) end
    if type(query) ~= "table" then query = nil end
    if not spec and not query then
        local why = queryWhy or specWhy
        if type(why) ~= "string" or why == "" then why = "nowhere" end
        return nil, nil, why
    end
    local orders = Orders()
    if not orders then
        if query then return spec, query, "needsorders" end
        return spec, nil, nil
    end
    local ok, why = orders.IsAvailable()
    if not ok then return spec, query, why or "disabled" end
    return spec, query, nil
end

local function TitleOf(b, spec, query)
    local t = Value(b._goOpts.title, b)
    if type(t) ~= "string" or t == "" then t = (spec and spec.title) or (query and query.title) end
    if type(t) ~= "string" or t == "" then return nil end
    return t
end

local function GoingLabel(label)
    if label == "Go" then return "Going" end
    local rest = label:match("^Go to (.+)$")
    if rest then return "Going to " .. rest end
    return label
end

local Listen

local function Refresh(b)
    if not b._goOpts then return end
    Listen()
    local spec, query, reason = Evaluate(b)
    b._goReason = reason
    if reason then b:Disable() else b:Enable() end
    local going = false
    local orders = Orders()
    local o = b._goOpts
    if not reason and orders and o.source ~= nil and type(orders.IsGoing) == "function" then
        going = orders.IsGoing(o.source, o.key) and true or false
    end
    if going ~= b._goGoing then
        b._goGoing = going
        b:SetText(going and GoingLabel(b._goLabel) or b._goLabel)
        if going then
            if b.LockHighlight then b:LockHighlight() end
        elseif b.UnlockHighlight then
            b:UnlockHighlight()
        end
    end
end

-- Only buttons on screen (a parent's OnShow reaches the button's own OnShow
-- hook, which refreshes it then)
local function RefreshAll()
    for b in pairs(buttons) do
        local shown
        if b.IsVisible then shown = b:IsVisible() else shown = b:IsShown() end
        if shown then
            local ok, err = pcall(Refresh, b)
            if not ok and geterrorhandler then geterrorhandler()(err) end
        end
    end
end
UI.RefreshGoButtons = RefreshAll

-- One listener for every button, added on the first refresh that finds
-- Orders' events (Commander.AddListener is defined by CommanderEvents.lua,
-- which loads after this file; and a module sorted before Commander_Orders
-- without it in OptionalDeps may build a button before Orders has loaded, so
-- a button made too early does not give up: the next refresh, at the latest
-- its OnShow, tries again)
function Listen()
    if listening or not Commander.AddListener then return end
    local events = COMMANDER_ORDERS_EVENTS
    if type(events) ~= "table" or not events.CHANGED then return end
    listening = true
    Commander.AddListener(events.CHANGED, RefreshAll)
    if events.UPDATE then Commander.AddListener(events.UPDATE, RefreshAll) end
end

-- The /way line Orders would write, for a client without Orders
local function OwnWayLine(m, x, y, title)
    return format("/way #%d %.2f %.2f%s", m, x * 100, y * 100, title and (" " .. title) or "")
end

-- The spot a Shift- or Ctrl-click uses: Orders' nearest place for a query
-- or a nearest-of-N spec, the spec's own spot otherwise
local function Place(b, spec, query, title)
    local orders = Orders()
    if orders and type(orders.PlaceFor) == "function" then
        local p, why = orders.PlaceFor(spec or query)
        if type(p) == "table" then return p.map, p.x, p.y, title or p.title end
        return nil, why
    end
    local m, x, y = SpotOf(spec)
    if m then return m, x, y, title end
    return nil, "needsorders"
end

local function Done(b, uid, why)
    local fn = b._goOpts.onGo
    if type(fn) == "function" then pcall(fn, uid, why) end
end

local function OnClick(b)
    local o = b._goOpts
    local spec, query, reason = Evaluate(b)
    if reason then
        Say(Words(reason))
        Done(b, nil, reason)
        return
    end
    local title = TitleOf(b, spec, query)
    local orders = Orders()
    local shift = IsShiftKeyDown and IsShiftKeyDown()
    local ctrl = IsControlKeyDown and IsControlKeyDown()
    if shift or ctrl then
        local m, x, y, t = Place(b, spec, query, title)
        if not m then
            Say(Words(x or "nowhere"))
            return
        end
        if not orders then
            Say(OwnWayLine(m, x, y, t) .. " (Commander Orders is not loaded)")
        elseif shift then
            local ok, why = orders.SharePoint({ map = m, x = x, y = y, title = t, silent = o.silent }, "CHAT")
            if not ok then Say("could not share: " .. Words(why)) end
        else
            orders.CopyText(orders.WayLineFor(m, x, y, t))
        end
        return
    end
    if not orders then
        -- no Orders: the line itself, to type or to hand to whatever
        -- navigation the player has
        local m, x, y = SpotOf(spec)
        if m then Say(OwnWayLine(m, x, y, title) .. " (Commander Orders is not loaded)") end
        Done(b, nil, "needsorders")
        return
    end
    local uid, why = orders.GoTo(spec or query, {
        source = o.source, key = o.key, title = title, icon = o.icon, note = o.note,
        persistent = o.persistent, temporary = o.temporary, clearOnArrive = o.clearOnArrive,
        setArrow = o.setArrow, silent = o.silent,
    })
    Done(b, uid, why)
    Refresh(b)
end

local function OnEnter(b)
    if not GameTooltip then return end
    local o = b._goOpts
    GameTooltip:SetOwner(b, o.anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(b._goLabel or "Go", 1, 1, 1)
    local spec, query, reason = Evaluate(b)
    local title = TitleOf(b, spec, query)
    local m, x, y, failWhy
    if not reason then
        -- a query with no title of the button's own is named by the place
        -- Orders found ("Nearest innkeeper")
        local ok, pm, px, py, pt = pcall(Place, b, spec, query, title)
        if ok and type(pm) == "number" then
            m, x, y = pm, px, py
            if not title and type(pt) == "string" and pt ~= "" then title = pt end
        elseif query and not spec then
            -- the lookup cannot name a place now: say why (as the TopBar's
            -- supply lines do) rather than "Go to:" and clicks that only
            -- print the same reason
            failWhy = (ok and pm == nil and px) or "nowhere"
        end
    elseif spec then
        m, x, y = SpotOf(spec)
    end
    local where
    if m then
        local orders = Orders()
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        local coords = (orders and orders.FormatCoords(x, y)) or format("%.1f, %.1f", x * 100, y * 100)
        where = ((info and info.name) and (info.name .. " ") or "") .. coords
    end
    if (title or where) and not failWhy then
        GameTooltip:AddLine("Go to: " .. (title or "") .. ((title and where) and " - " or "") .. (where or ""),
            0.9, 0.9, 0.9, true)
    end
    -- greyed by Orders' state: the module's line would describe a press the
    -- button cannot take, so only the red reason speaks
    local extra
    if not (reason and ORDERS_STATES[reason]) then extra = Value(o.tooltip, b) end
    if type(extra) == "string" and extra ~= "" then GameTooltip:AddLine(extra, 0.8, 0.8, 0.8, true) end
    if b._goGoing then GameTooltip:AddLine("The arrow points here now.", 0.3, 1, 0.36) end
    if reason or failWhy then
        GameTooltip:AddLine(Words(reason or failWhy), 1, 0.3, 0.25, true)
    else
        GameTooltip:AddLine("Shift-click: share in chat. Ctrl-click: copy a /way line.", 0.6, 0.8, 1, true)
    end
    GameTooltip:Show()
end

function UI.GoButton(parent, opts)
    opts = type(opts) == "table" and opts or {}
    local b = CreateFrame("Button", nil, parent, opts.template or "UIPanelButtonTemplate")
    -- a greyed Go still shows its tooltip, the reason in red (D31); 2.5.6
    -- gives a disabled Button no OnEnter without this (review: consistency)
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    local label = (type(opts.label) == "string" and opts.label ~= "") and opts.label or "Go"
    b._goOpts = opts
    b._goLabel = label
    b._goGoing = false
    b:SetText(label)
    local fs = b.GetFontString and b:GetFontString()
    local textW = fs and fs.GetStringWidth and fs:GetStringWidth()
    if type(textW) ~= "number" or textW <= 0 then textW = #label * 7 end
    b:SetSize(opts.width or math.max(40, textW + 24), opts.height or 22)
    b:EnableMouse(true)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp") end
    b:SetScript("OnClick", OnClick)
    b:SetScript("OnEnter", OnEnter)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:HookScript("OnShow", Refresh)
    b.Refresh = Refresh
    buttons[b] = true
    Listen()
    Refresh(b)
    return b
end

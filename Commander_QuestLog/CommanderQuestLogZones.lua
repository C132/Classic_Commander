-- Commander Quest Log: the Zones tab.
--
-- The second tab of the quest log window. Pick a zone -- or let it follow you
-- -- and see every quest it holds for this character: a completion bar
-- ("62 / 90 · 69%"), what is done, what is open, what is locked and why,
-- what has been missed for good and why, and the chains in order. With
-- nothing selected the briefing is the zone's overview and a short "what next"
-- list; with a quest selected it is that quest's briefing: where it starts and
-- ends, where it sits in its chain, what it needs. Every number and every word
-- comes from the completion engine (CommanderQuestLogCompletion.lua) over
-- facts the Questie adapter (CommanderQuestLogQuestie.lua) reads; this file
-- only draws them and answers the clicks.
--
-- Why a file of its own, building its own widgets inside the window rather
-- than reusing the Log's: the Log's rows and briefing are closures written for
-- the live log (right-click tracks, shift-click announces, objectives are
-- read off the client's selection), and threading a second mode through every
-- one of them would make every Log code path a mode switch -- the regression
-- risk this tab is not worth. So the Zones tab has its own row pool in the
-- navigator, its own block pools in the briefing, its own toolbar set and its
-- own action buttons, all built on first use and hidden whenever the Log is
-- up. It borrows the window's ink, quads and frame pieces through Q._kit, so
-- the two tabs cannot drift apart on colour (D16).
--
-- The traps, each one paid for in the engine's or the adapter's own work:
--
--   * C.Group writes entry.header onto the view's OWN entries, and BuildList
--     matches rows to their headings through it -- so the last Group call on
--     a view decides every heading. The navigator groups immediately before
--     BuildList and nothing regroups between them; the overview's "next up"
--     list uses C.NextUp, which reads the Guide's order without touching a
--     header.
--   * Group titles are fold keys. Folding is kept in ZoneCollapsed, never in
--     the Log's Collapsed: the two lists are different namespaces sharing one
--     widget, and a log heading and a chain could share a name.
--   * Dim by `counted`, not by bucket. An exclusive choice's other members
--     keep bucket AVAILABLE or LOCKED and simply do not count; a row that
--     looked counted by its bucket would promise a 100% the zone cannot reach.
--   * The breakdown line ("Done 62 · In log 4 · Open 9 · Locked 12") reads
--     totals.countedByStatus, whose four figures add up to the denominator;
--     totals.byStatus counts buckets and would not.
--   * The LEVEL and NAME groupings are flat lists in the engine's own
--     ascending order. They go through BuildList with sort "LOG" to keep that
--     order (BuildList's LEVEL sort runs highest first).
--   * One search box, two searches. The box belongs to the window; each tab
--     keeps its own text, and the window swaps it on a tab change (see
--     Q.Refresh in the UI file).
--   * The global quest-log selection is the Log's business (D2). This tab
--     touches it only through Q.ReadDetail, for a quest that is in the log,
--     which puts it back.
--   * A selected quest that a filter, a search or a fold takes off the list
--     drops the briefing to the zone's overview (D6) -- unless something asked
--     for it by name (the map drawer, CommanderQuestLog_OpenToZone), in which
--     case the search is cleared, the filter opened and its group unfolded,
--     because the caller wants that quest and not an overview.
--   * No shape glyphs in anything drawn (D11): markers are quads, states are
--     words. Every colour on the sheet goes through Paper() (D16), and pooled
--     blocks get their font and colour re-applied on every pass (D15).

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local Z = {}
Q.Zones = Z

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local CARD_H = 46            -- the zone card over the navigator column
local CARD_GAP = 4
local CARD_BAR_H = 4
local TAB_W = 58
local TAB_H = 20
local FILTER_W = 42          -- five of these end where the Log's four do
local STATE_W = 46           -- the state word's column (C.StateWord is <= 6 characters)
local TOTAL_BAR_H = 6
local CHAIN_BAR_H = 3
local MARK_SIZE = 6
local NEXT_UP_COUNT = 6
local GIVERS_SHOWN = 3
local MENU_PAGE = 20         -- zone-menu rows per level-2 list (the Classic dropdown never scrolls)
local SEP = "  \194\183  "                -- the middle dot the Log's facts line uses
local DASH = " \226\128\148 "             -- em dash
local ELLIPSIS = "\226\128\166"

local DEFAULT_FILTER_ORDER = { "ALL", "OPEN", "LOCKED", "DONE", "MISSED" }

-- Status tones, picked against a dark UI like every literal in this window
-- and put through Paper() wherever they are drawn on the sheet (D16). The
-- engine names a tone (good / open / warn / bad / faint); this is the only
-- place one becomes a colour.
local TONES = {
    good = { 0.35, 0.82, 0.35 },
    open = { 0.95, 0.80, 0.30 },
    log  = { 0.45, 0.72, 1.00 },
    warn = { 1.00, 0.56, 0.25 },
    bad  = { 0.90, 0.36, 0.30 },
}
local STATUS_TONE = { DONE = "good", LOG = "log", AVAILABLE = "open", LOCKED = "warn", MISSED = "bad" }
local OBJECTIVE_DONE = { 0.35, 0.8, 0.35 }
local OBJECTIVE_OPEN = { 0.92, 0.86, 0.6 }
local TAG_WORDS = { DUNGEON = "Dungeon", RAID = "Raid", PVP = "PvP", ELITE = "Elite" }

-- ---------------------------------------------------------------------------
-- State
--
-- S is what the last pass worked out; W is what it is drawn with. Two tables
-- rather than thirty upvalues, which keeps every function here well inside
-- what Lua 5.1 lets one close over.
-- ---------------------------------------------------------------------------

local S = {
    state = "ABSENT", reason = nil,     -- the adapter's word on Questie
    areaId = nil, areaName = nil,       -- the zone shown (an AREA id, Questie's id space)
    view = nil, err = nil,              -- the engine's view, or why there is none
    rows = {}, shown = 0,               -- BuildList's answer
    selectedId = nil, selectedEntry = nil,
    pendingSelect = nil, reveal = false,
    search = "",
    logByKey = {}, logDetail = nil,     -- the Log's scan, keyed like zone entries
    char = nil, playerPos = nil,
    detailCache = nil,
}

local W = {
    built = false,
    tabs = nil, toolbar = nil, filters = {}, groupDrop = nil, countFS = nil,
    card = nil, menu = nil, actions = nil,
    rows = {}, emptyFS = nil,
    blocks = {}, quads = {}, bands = {},
}

-- The briefing's cursor for one layout pass
local P = { y = 0, block = 1, quad = 1, band = 1, width = 0 }

-- ---------------------------------------------------------------------------
-- Reaching the rest of the module
-- ---------------------------------------------------------------------------

-- The window's kit. UI.lua loads first and publishes it; read late anyway,
-- so a load order nobody meant degrades to an absent tab rather than an error.
local function Kit()
    return Q._kit
end

local function Engine()
    local engine = Q.Completion
    if type(engine) == "table" and type(engine.Group) == "function" then return engine end
    return nil
end

local function Adapter()
    local adapter = Q.Questie
    if type(adapter) == "table" then return adapter end
    return nil
end

local function DB()
    return CommanderQuestLogDB or {}
end

local function Tip(widget, title, text, anchor)
    if Commander and Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(widget, title, text, anchor)
    end
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- "ABSENT" | "LOADING" | "READY" | "BROKEN", reason. A missing engine is
-- BROKEN: the adapter would answer READY and every view would fail.
local function AdapterState()
    local adapter = Adapter()
    if not (adapter and adapter.State) then return "ABSENT", nil end
    local ok, state, reason = pcall(adapter.State)
    if not ok then return "BROKEN", tostring(state) end
    if state == "READY" and not Engine() then return "BROKEN", "the completion engine is not loaded" end
    return state or "ABSENT", reason
end

function Z.IsActive()
    local db = DB()
    return db.ViewMode == "ZONE" and db.ShowZoneTab ~= false and db.EnableQuestLog ~= false
end

-- How far the navigator moves down for the zone card (UI.lua's AnchorNavPane).
-- Asked of the window's own predicate for which tab draws (Q.ViewMode), not
-- of Z.IsActive: that one also wants the module switched on, and a window
-- left open after unchecking Enable Quest Log still draws the Zones tab on a
-- tab switch -- with the card over the navigator's first rows.
function Z.NavTopInset()
    local mode = Q.ViewMode and Q.ViewMode()
    if mode == "ZONE" then return CARD_H + CARD_GAP end
    return 0
end

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

local function ToneRGB(key)
    local tone = TONES[key]
    if tone then return tone[1], tone[2], tone[3] end
    return Kit().Ink("faint")
end

-- A tone as a colour table, for Line(); Line puts it through Paper()
local function ToneT(key)
    return { ToneRGB(key) }
end

local function InkT(shade)
    return { Kit().Ink(shade) }
end

-- Inline markup for a word inside a longer line, already put on the paper
local function ToneMarkup(key, text)
    local r, g, b = Kit().Paper(ToneRGB(key))
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

-- The tone a quest's strip, sentence and chain mark take. Uncounted quests
-- (other choices, other faction, dailies, the ignored) are faint whatever
-- their bucket, except the missed, which are the one uncounted thing worth
-- seeing at a glance.
local function StatusToneKey(entry)
    if entry.base == "LOG" then
        if entry.ready then return "good" end
        if entry.failed then return "bad" end
    end
    if not entry.counted and entry.status ~= "MISSED" then return "faint" end
    return STATUS_TONE[entry.status] or "faint"
end

-- ---------------------------------------------------------------------------
-- Givers
-- ---------------------------------------------------------------------------

local function ZoneNameOf(record)
    local adapter = Adapter()
    local areaId = record and (record.zone or record.areaId)
    if areaId and adapter and adapter.ZoneName then return adapter.ZoneName(areaId) end
    return nil
end

-- "Force Commander Danath — Hellfire Peninsula 56.6, 66.4"
local function GiverPhrase(record)
    if record.kind == "item" then return (record.name or "An item") .. " (an item)" end
    local text = record.name or "Someone Questie has no name for"
    local zone = record.zoneName or ZoneNameOf(record)
    if zone then text = text .. DASH .. zone end
    if record.x and record.y then text = text .. string.format(" %.1f, %.1f", record.x, record.y) end
    return text
end

-- The first spawn of each distinct giver, up to cap. A patrol with eight
-- spawns is one quest giver, not eight lines.
local function DistinctGivers(records, cap)
    local out, seen = {}, {}
    for _, record in ipairs(records or {}) do
        local key = tostring(record.kind) .. ":" .. tostring(record.id or record.name)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = record
            if #out >= cap then break end
        end
    end
    return out
end

-- The first giver record with coordinates. The adapter orders spawns in the
-- viewed zone first, so this is the one standing here when there is one.
local function FirstPlaced(records)
    for _, record in ipairs(records or {}) do
        if record.x and record.y then return record end
    end
    return nil
end

-- The name to put after a quest in a short list: who hands it out, or for a
-- quest in the log who takes it back
local function GiverName(entry)
    local list = (entry.base == "LOG") and entry.finishers or entry.starters
    local giver
    for _, record in ipairs(list or {}) do
        if record.name then giver = record break end
    end
    if not giver then return nil end
    if entry.base ~= "LOG" and entry.startsHere == false and entry.startZoneName then
        return giver.name .. " in " .. entry.startZoneName
    end
    return giver.name
end

local function LogEntryFor(entry)
    return entry and S.logByKey[entry.key] or nil
end

-- Where a waypoint for this quest goes: its turn-in once it is in the log and
-- ready, else where it starts, else (in the log, no starter placed) its
-- turn-in after all. Returns record, "finisher" | "starter".
local function WaypointTarget(entry)
    local adapter = Adapter()
    if not (entry and adapter) then return nil end
    local logEntry = LogEntryFor(entry)
    local inLog = entry.base == "LOG" or logEntry ~= nil
    local ready = entry.ready or (logEntry and logEntry.isComplete)
    if inLog and ready then
        local finisher = FirstPlaced(entry.finishers)
        if finisher then return finisher, "finisher" end
    end
    local starter = adapter.BestStarter and adapter.BestStarter(entry, S.areaId)
    if starter and starter.x and starter.y then return starter, "starter" end
    if inLog then
        local finisher = FirstPlaced(entry.finishers)
        if finisher then return finisher, "finisher" end
    end
    return nil
end

local function SendWaypoint(entry)
    local adapter = Adapter()
    local target, role = WaypointTarget(entry)
    if not (target and adapter and adapter.Waypoint) then
        print("Commander Quest Log: Questie does not know where |cffffd100" ..
            tostring(entry and entry.title or "that quest") .. "|r starts.")
        return nil
    end
    -- Every spawn of that giver rides along, so the arrow takes the nearest:
    -- BestStarter packs them, a raw finisher record has them in its list
    local spawns = target.spawns
    if not spawns and role == "finisher" and adapter.SpawnsOf then
        spawns = adapter.SpawnsOf(entry.finishers, target)
    end
    return adapter.Waypoint({
        title = string.format("%s (%s)", entry.title or "Quest",
            target.name or (role == "finisher" and "turn in" or "quest giver")),
        areaId = target.areaId, uiMapId = target.uiMapId,
        zoneName = target.zoneName or ZoneNameOf(target),
        x = target.x, y = target.y, questId = entry.id, spawns = spawns,
    })
end

-- The zone's open quests as one Commander Orders route, nearest first (the
-- adapter builds it and says how it went)
local function RouteZone()
    local adapter = Adapter()
    if not (adapter and adapter.RouteOpen and S.areaId) then return nil end
    return adapter.RouteOpen(S.areaId)
end

-- How many givers a route through the shown zone would visit (0: none)
local function RouteStopCount()
    local adapter = Adapter()
    if not (adapter and adapter.RouteStops and S.view and S.areaId) then return 0 end
    return #(adapter.RouteStops(S.areaId) or {})
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

local function IsIgnored(questId)
    local charDB = CommanderQuestLogChar
    local ignored = type(charDB) == "table" and charDB.Ignored or nil
    return (type(ignored) == "table" and ignored[questId]) and true or false
end

-- The per-character ignore set, made whole first (the DB file owns the shape)
local function IgnoredSet()
    if Q.EnsureCharDB then return Q.EnsureCharDB().Ignored end
    if type(CommanderQuestLogChar) ~= "table" then CommanderQuestLogChar = {} end
    if type(CommanderQuestLogChar.Ignored) ~= "table" then CommanderQuestLogChar.Ignored = {} end
    return CommanderQuestLogChar.Ignored
end

-- Ignore is per character and leaves the quest listed (under Ignored). The
-- adapter recomputes on its debounce, so the percentage follows a quarter
-- second later; the button's own word flips at once.
local function ToggleIgnore()
    local entry = S.selectedEntry
    if not entry then return end
    local ignored = IgnoredSet()
    if ignored[entry.id] then ignored[entry.id] = nil else ignored[entry.id] = true end
    local adapter = Adapter()
    if adapter and adapter.Bump then adapter.Bump("ignore") end
    Z.UpdateActions()
end

local function MapForZone()
    local adapter = Adapter()
    if not (S.areaId and adapter and adapter.UiMapForArea) then return nil end
    return adapter.UiMapForArea(S.areaId)
end

-- Out of combat only: opening the map from addon code is the one thing here
-- that touches a Blizzard panel, and the Log refuses rather than risk it.
local function ShowOnMap()
    if InCombatLockdown and InCombatLockdown() then
        print("Commander Quest Log: the world map is not opened from here in combat. Try again once you are out of it.")
        return
    end
    local uiMapId = MapForZone()
    if not uiMapId then return end
    local map = WorldMapFrame
    if not (map and map.IsShown and map:IsShown()) then
        -- ToggleWorldMap first: it is the player's own path (and loads the
        -- map, should a client ever make it load-on-demand again)
        if ToggleWorldMap then
            ToggleWorldMap()
        elseif map and ShowUIPanel then
            ShowUIPanel(map)
        end
        map = WorldMapFrame
    end
    if not map then return end
    if map.SetMapID then map:SetMapID(uiMapId) end
    -- The zone goes along, so the drawer can move the map itself should the
    -- SetMapID above not have landed (a map that was mid-transition)
    if S.selectedEntry and Q.Map and Q.Map.Focus then Q.Map.Focus(S.selectedEntry.id, S.areaId) end
    -- A maximised map is FULLSCREEN and covers this window, which is right
    -- where it was when the map closes. A windowed map is MEDIUM, and this
    -- window (HIGH) would sit on top of it, so it steps aside.
    if map.IsMaximized and not map:IsMaximized() and CommanderQuestLog_Hide then CommanderQuestLog_Hide() end
end

-- The Log keeps its own fold, filter and search, and any of them could
-- hide the quest asked for; Q.RevealInLog opens them up for it (the Log's
-- side of D31) where a plain select would brief whatever row came first
local function OpenInLog()
    local logEntry = LogEntryFor(S.selectedEntry)
    if not logEntry then return end
    if Q.RevealInLog then
        Q.RevealInLog(logEntry.key)
        return
    end
    if Q.SetViewMode then Q.SetViewMode("LOG") end
    if Q.Select then Q.Select(logEntry.key) end
end

-- ---------------------------------------------------------------------------
-- The tabs
--
-- Two words in the title band's free top left, drawn like the filter
-- buttons: the font object first, the colour after it (swapping the font
-- re-applies the font's own grey), and an accent underline on the active one.
-- Above the drag strip's frame level, or the strip would take their clicks.
-- ---------------------------------------------------------------------------

local function StyleTab(button, active)
    local kit = Kit()
    if button.SetNormalFontObject then
        button:SetNormalFontObject(active and GameFontNormalSmall or GameFontDisableSmall)
    end
    local fs = button.GetFontString and button:GetFontString()
    if fs then
        if active then fs:SetTextColor(kit.Ink("strong")) else fs:SetTextColor(kit.Ink("faint")) end
    end
    -- A fill too goes on the paper as ink: the default accent is white, and
    -- white over cream is no underline at all
    local r, g, b = kit.InkAccent()
    button.underline:SetVertexColor(r, g, b, active and 0.95 or 0)
end

-- A hover swaps the label to the highlight font and back to the normal one,
-- and each swap puts the font's own colour back over our ink (D14's lesson),
-- leaving gold on the paper until the next refresh. So the ink goes back on
-- after a hover -- a frame later, so it lands after the client's own swap
-- whichever order the two run in.
local function ReinkAfterHover(button, restyle)
    button:HookScript("OnLeave", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, restyle) else restyle() end
    end)
    -- ...and on the paper the hovered label is ink too, not the highlight
    -- font's white over the pale strip (UI.lua's InkOnHover)
    local kit = Kit()
    if kit and kit.InkOnHover then kit.InkOnHover(button) end
end

local function MakeTab(frame, label, mode, x, tooltip)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(TAB_W, TAB_H)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -5)
    button:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
    button:SetNormalFontObject(GameFontDisableSmall)
    button:SetHighlightFontObject(GameFontHighlightSmall)
    button:SetText(label)
    button.underline = Kit().Quad(button, "ARTWORK")
    button.underline:SetHeight(2)
    button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 1)
    button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 1)
    button.mode = mode
    button:SetScript("OnClick", function()
        if Q.SetViewMode then Q.SetViewMode(mode) end
    end)
    Tip(button, label, tooltip, "ANCHOR_BOTTOM")
    ReinkAfterHover(button, function() Z.UpdateTabs() end)
    return button
end

function Z.EnsureTabs(frame)
    if W.tabs or not (frame and Kit()) then return end
    W.tabs = {
        LOG = MakeTab(frame, "Log", "LOG", 12,
            "Every quest in your log, with its objectives, rewards and actions."),
        ZONE = MakeTab(frame, "Zones", "ZONE", 12 + TAB_W + 2,
            "Every quest a zone holds for this character, read from Questie: what is done, what is open, what is locked or missed and why, and what to do next."),
    }
    Z.UpdateTabs()
end

-- Both tabs go when the Zones tab is switched off: a lone "Log" tab is noise
function Z.UpdateTabs()
    if not W.tabs then return end
    local db = DB()
    local allowed = db.ShowZoneTab ~= false
    local zone = allowed and db.ViewMode == "ZONE"
    for mode, button in pairs(W.tabs) do
        button:SetShown(allowed)
        StyleTab(button, (mode == "ZONE") == zone)
    end
end

-- ---------------------------------------------------------------------------
-- The zone menu
--
-- "Where I am" first, then Questie's own categories with each one's zones a
-- level down, a percentage beside every zone whose summary is known. Opening
-- a category asks the adapter to work out the rest in the background (one
-- zone per tick); an open dropdown cannot be redrawn in place, so they show
-- the next time it opens.
-- ---------------------------------------------------------------------------

local function FollowPlayer()
    local db = DB()
    db.ZoneFollow = true
    db.ZonePicked = false
    S.selectedId = nil
    if CloseDropDownMenus then CloseDropDownMenus() end
    Q.Refresh()
end

local function PickZone(_, areaId)
    if type(areaId) ~= "number" then return end
    local db = DB()
    db.ZoneFollow = false
    db.ZonePicked = areaId
    S.selectedId = nil
    if CloseDropDownMenus then CloseDropDownMenus() end
    Q.Refresh()
end

-- One stable callback, so a second request for the menu's summaries replaces
-- the first job in the adapter instead of queueing behind it
local function MenuSummaryArrived() end

local function ZoneMenuText(zone)
    local adapter, engine = Adapter(), Engine()
    local summary = adapter and adapter.ZoneSummary and adapter.ZoneSummary(zone.areaId, true)
    if summary and summary.pct and engine then
        return zone.name .. "  " .. engine.PercentText(summary.pct)
    end
    return zone.name
end

-- A category row: opens its zones a level down. keepShownOnClick, because a
-- click (rather than a hover) on a row with no func otherwise hides the
-- whole menu and picks nothing (UIDropDownMenuButton_OnClick).
local function AddCategoryRow(text, menuList)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.hasArrow = true
    info.notCheckable = true
    info.keepShownOnClick = true
    info.menuList = menuList
    UIDropDownMenu_AddButton(info, 1)
end

-- A zone name's first character, as a whole UTF-8 sequence: one byte of
-- "\195\150dland" (deDE) or of any ruRU or koKR name is half a character, and
-- on its own an invalid one. Only an ASCII letter is upper-cased.
local function Initial(name)
    local first = type(name) == "string" and name:match("^[%z\1-\127\194-\244][\128-\191]*") or nil
    if not first or first == "" then return "?" end
    return #first == 1 and first:upper() or first
end

-- Where the next page ends: nearest the even split, at a change of initial,
-- never past MENU_PAGE rows. Returns the last index and whether it is a
-- clean cut (false when one initial runs longer than the page can hold).
local function PageEnd(zones, first)
    local remaining = #zones - first + 1
    if remaining <= MENU_PAGE then return #zones, true end
    local pages = math.ceil(remaining / MENU_PAGE)
    local ideal = first + math.ceil(remaining / pages) - 1
    local best
    for last = first, first + MENU_PAGE - 1 do
        if Initial(zones[last].name) ~= Initial(zones[last + 1].name)
            and (not best or math.abs(last - ideal) < math.abs(best - ideal)) then
            best = last
        end
    end
    if best then return best, true end
    return ideal, false
end

-- The Classic dropdown never scrolls and is not clamped to the screen: a
-- level-2 list grows by 16 per row and, near the bottom of the screen, flips
-- to grow upward instead -- off the top. At the window's default spot on a
-- 768-unit screen 24 rows fit and the Dungeons list holds 34, so a long
-- category is cut into pages of at most MENU_PAGE rows, each a row of its
-- own named by its initials ("Dungeons  A-O", "Dungeons  R-Z"). The cuts
-- fall where the initial changes, so no two pages claim the same letter;
-- where a letter outruns a page the rows are numbered as well ("(1/2)").
local function AddCategoryPages(category)
    local zones = category.zones or {}
    if #zones <= MENU_PAGE then
        AddCategoryRow(category.text, category.key)
        return
    end
    local pages, clean, first = {}, true, 1
    while first <= #zones do
        local last, cut = PageEnd(zones, first)
        clean = clean and cut
        pages[#pages + 1] = { key = category.key, first = first, last = last }
        first = last + 1
    end
    for index, page in ipairs(pages) do
        local text = string.format("%s  %s-%s", category.text,
            Initial(zones[page.first].name), Initial(zones[page.last].name))
        if not clean then text = string.format("%s (%d/%d)", text, index, #pages) end
        AddCategoryRow(text, page)
    end
end

local function ZoneMenuInit(_, level, menuList)
    level = level or 1
    local adapter = Adapter()
    local db = DB()
    if level == 1 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Where I am"
        info.checked = db.ZoneFollow ~= false
        info.func = FollowPlayer
        UIDropDownMenu_AddButton(info, level)
        local menu = adapter and adapter.ZoneMenu and adapter.ZoneMenu() or {}
        S.menu = menu
        for _, category in ipairs(menu) do AddCategoryPages(category) end
        return
    end
    local page = type(menuList) == "table" and menuList or nil
    local key = page and page.key or menuList
    local picked = db.ZoneFollow == false and tonumber(db.ZonePicked) or nil
    for _, category in ipairs(S.menu or {}) do
        if category.key == key then
            local zones = category.zones or {}
            local ids = {}
            for index = (page and page.first or 1), (page and page.last or #zones) do
                local zone = zones[index]
                if zone then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = ZoneMenuText(zone)
                    info.checked = picked == zone.areaId
                    info.arg1 = zone.areaId
                    info.func = PickZone
                    UIDropDownMenu_AddButton(info, level)
                    ids[#ids + 1] = zone.areaId
                end
            end
            if adapter and adapter.RequestSummaries and #ids > 0 then
                adapter.RequestSummaries(ids, MenuSummaryArrived)
            end
        end
    end
end

local function OpenZoneMenu(anchor)
    if not (W.menu and ToggleDropDownMenu) then return end
    ToggleDropDownMenu(1, nil, W.menu, anchor, 0, 0)
end

-- ---------------------------------------------------------------------------
-- Building the tab's widgets (first use)
-- ---------------------------------------------------------------------------

local function PickGroup(_, mode)
    DB().ZoneGroup = mode
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(W.groupDrop, mode) end
    Q.Refresh()
end

local function GroupDropInit()
    local engine = Engine()
    if not engine then return end
    for _, mode in ipairs(engine.GROUPS) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = engine.GROUP_LABELS[mode] or mode
        info.value = mode
        info.checked = (DB().ZoneGroup or "GUIDE") == mode
        info.arg1 = mode
        info.func = PickGroup
        UIDropDownMenu_AddButton(info)
    end
end

-- The zone set of the toolbar: five filters where the Log has four (narrower,
-- so the shared search box after them does not move), the group dropdown in
-- the Log's sort slot, and a "n shown" readout at the right
local function BuildToolbar(frame)
    local kit, engine = Kit(), Engine()
    local bar = CreateFrame("Frame", nil, frame.toolbar)
    bar:SetAllPoints(frame.toolbar)
    W.toolbar = bar

    local order = engine and engine.FILTER_ORDER or DEFAULT_FILTER_ORDER
    local previous
    for _, key in ipairs(order) do
        local spec = engine and engine.FILTERS[key] or { label = key, tooltip = "" }
        local button = CreateFrame("Button", nil, bar)
        button:SetSize(FILTER_W, kit.TOOLBAR_H)
        button:SetNormalFontObject(GameFontDisableSmall)
        button:SetHighlightFontObject(GameFontHighlightSmall)
        button:SetText(spec.label)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
        button.underline = kit.Quad(button, "ARTWORK")
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 5, 2)
        button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
        button:SetScript("OnClick", function()
            DB().ZoneFilter = key
            Q.Refresh()
        end)
        Tip(button, spec.label, spec.tooltip, "ANCHOR_BOTTOM")
        ReinkAfterHover(button, function() Z.RestyleToolbar() end)
        W.filters[key] = button
        previous = button
    end

    local drop = CreateFrame("Frame", "CommanderQuestLogZoneGroupDrop", bar, "UIDropDownMenuTemplate")
    drop:SetPoint("LEFT", frame.searchBox, "RIGHT", -6, -2)
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(drop, GroupDropInit)
        UIDropDownMenu_SetWidth(drop, 118)
    end
    W.groupDrop = drop

    local hit = CreateFrame("Frame", nil, bar)
    hit:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
    hit:SetSize(110, kit.TOOLBAR_H)
    hit:EnableMouse(true)
    W.countFS = hit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    W.countFS:SetPoint("RIGHT", hit, "RIGHT", 0, 0)
    Tip(hit, "Shown",
        "How many of this zone's quests the search and the filter leave on the list. The zone card counts every quest that counts toward 100%, whatever is shown.",
        "ANCHOR_BOTTOM")
end

local function CardEnter(self)
    local engine = Engine()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.areaName or "Zones", 1, 1, 1)
    if S.view and engine then
        GameTooltip:AddLine(engine.TotalsText(S.view.totals) .. " of the quests that count here.", 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine(DB().ZoneFollow ~= false and "Following the zone you are in."
        or "Pinned to this zone.", 0.7, 0.7, 0.75)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to pick a zone, or to go back to this one's overview. Right-click to follow the zone you are standing in.",
        0.55, 0.55, 0.6, true)
    GameTooltip:Show()
end

-- The zone card: name and totals, a completion bar, and whether it follows
-- you. A Button, because it is the zone picker.
local function BuildCard(frame)
    local kit = Kit()
    local card = CreateFrame("Button", nil, frame)
    card:SetSize(kit.NAV_W, CARD_H)
    card:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    card.bg = kit.Quad(card, "BACKGROUND")
    card.bg:SetAllPoints()
    card.rule = kit.Quad(card, "ARTWORK")
    card.rule:SetHeight(1)
    card.rule:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    card.rule:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)

    card.name = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
    card.name:SetPoint("RIGHT", card, "RIGHT", -104, 0)
    card.name:SetJustifyH("LEFT")

    card.totals = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    card.totals:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    card.totals:SetJustifyH("RIGHT")

    card.barBg = kit.Quad(card, "ARTWORK", 1)
    card.barBg:SetHeight(CARD_BAR_H)
    card.barBg:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -24)
    card.barBg:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -24)
    card.bar = kit.Quad(card, "ARTWORK", 2)
    card.bar:SetHeight(CARD_BAR_H)
    card.bar:SetPoint("TOPLEFT", card.barBg, "TOPLEFT", 0, 0)

    card.note = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -32)
    card.note:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.note:SetJustifyH("LEFT")

    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(kit.QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.05)
    card:SetHighlightTexture(highlight)

    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            FollowPlayer()
            return
        end
        S.selectedId = nil
        Q.Refresh()
        OpenZoneMenu(self)
    end)
    card:SetScript("OnEnter", CardEnter)
    card:SetScript("OnLeave", HideTooltip)
    W.card = card

    -- Deliberately never anchored, like the suite's other menu frames: a MENU
    -- dropdown keeps an invisible, clickable button of its own, and one with
    -- a rect over the navigator would eat clicks meant for its first row. The
    -- list itself hangs off the card (ToggleDropDownMenu's anchor).
    local menu = CreateFrame("Frame", "CommanderQuestLogZoneMenu", frame, "UIDropDownMenuTemplate")
    if UIDropDownMenu_Initialize then UIDropDownMenu_Initialize(menu, ZoneMenuInit, "MENU") end
    W.menu = menu
end

-- The zone set of the action bar: Waypoint, Show on Map, Open in Log, Route
-- Zone (every open quest's giver as one Commander Orders route), and the
-- Ignore / Count toggle at the right where the Log keeps Abandon
local function BuildActions(frame)
    local actions = CreateFrame("Frame", nil, frame.actions)
    actions:SetAllPoints(frame.actions)
    W.actions = actions

    local function Button(label, width, tooltip, handler)
        local button = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        button:SetScript("OnClick", handler)
        Tip(button, label, tooltip, "ANCHOR_TOP")
        return button
    end

    W.waypointBtn = Button("Waypoint", 80, function()
        local where = Kit().WaypointWhere and Kit().WaypointWhere() or "the chat frame"
        return "Set a waypoint to where this quest starts or, once it is in your log and ready, to where it is handed in. Right-clicking a row does the same. Goes to "
            .. where .. "."
    end, function()
        if S.selectedEntry then SendWaypoint(S.selectedEntry) end
    end)
    W.waypointBtn:SetPoint("LEFT", actions, "LEFT", 0, 0)

    W.mapBtn = Button("Show on Map", 96,
        "Open the world map on this zone, with the selected quest's givers marked. Not from here in combat.",
        ShowOnMap)
    W.mapBtn:SetPoint("LEFT", W.waypointBtn, "RIGHT", 4, 0)

    W.logBtn = Button("Open in Log", 92,
        "Switch to the Log tab with this quest selected. Only for a quest that is in your log.",
        OpenInLog)
    W.logBtn:SetPoint("LEFT", W.mapBtn, "RIGHT", 4, 0)

    -- A zone action, not a quest one: live with nothing selected
    W.routeBtn = Button("Route Zone", 86, function()
        local adapter = Adapter()
        local path = adapter and adapter.WaypointPath and adapter.WaypointPath() or "PRINT"
        local text = "Set a Commander Orders route through every quest giver with an open quest in "
            .. (S.areaName or "this zone")
            .. ", nearest first: arriving at one points the arrow at the next. Asking again replaces the route."
        if path == "ORDERS_OFF" then
            return text .. " Commander Orders is turned off (/corder)."
        elseif path ~= "ORDERS" then
            return text .. " Needs Commander Orders, which is not loaded."
        end
        local count = RouteStopCount()
        if count == 0 then return text .. " No open quest here has a giver Questie can place." end
        return text .. string.format(" %d giver%s.", count, count == 1 and "" or "s")
    end, RouteZone)
    W.routeBtn:SetPoint("LEFT", W.logBtn, "RIGHT", 4, 0)

    W.ignoreBtn = Button("Ignore", 72, function()
        if S.selectedEntry and IsIgnored(S.selectedEntry.id) then
            return "Put this quest back into the zone's 100%."
        end
        return "Leave this quest out of the zone's 100% for this character, for a quest you will never do. It stays on the list, under Ignored, and Count puts it back."
    end, ToggleIgnore)
    W.ignoreBtn:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
end

local function EnsureBuilt(frame)
    if W.built then return end
    W.built = true
    BuildToolbar(frame)
    BuildCard(frame)
    BuildActions(frame)
end

-- ---------------------------------------------------------------------------
-- Navigator rows
-- ---------------------------------------------------------------------------

local function RowClick(self, button)
    if self.headerTitle then
        local db = DB()
        local collapsed = db.ZoneCollapsed or {}
        collapsed[self.headerTitle] = (not collapsed[self.headerTitle]) or nil
        db.ZoneCollapsed = collapsed
        Q.Refresh()
        return
    end
    local entry = self.entry
    if not entry then return end
    if button == "RightButton" then
        SendWaypoint(entry)
        return
    end
    -- Clicking the briefed quest again goes back to the zone's overview
    if S.selectedId == entry.id then
        S.selectedId = nil
    else
        S.selectedId = entry.id
        local scroll = Kit().DetailScroll()
        if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    end
    Q.Refresh()
end

local function RowEnter(self)
    local entry = self.entry
    local engine = Engine()
    if not (entry and engine) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.title, 1, 1, 1)
    GameTooltip:AddLine(engine.Reason(entry, S.char or {}, S.view), 0.85, 0.85, 0.85, true)
    local adapter = Adapter()
    local starter = adapter and adapter.BestStarter and adapter.BestStarter(entry, S.areaId)
    if not starter then
        local first = DistinctGivers(entry.starters, 1)[1]
        if first then starter = first end
    end
    if starter then GameTooltip:AddLine("Starts: " .. GiverPhrase(starter), 0.7, 0.7, 0.75, true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click for details. Right-click for a waypoint.", 0.55, 0.55, 0.6)
    GameTooltip:Show()
end

local function AcquireRow(position)
    local row = W.rows[position]
    if row then return row end
    local kit = Kit()
    row = CreateFrame("Button", nil, kit.NavChild())
    row:SetHeight(kit.QUEST_ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.selection = kit.Quad(row, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:Hide()

    -- The status strip: a quad down the left edge, tinted by the quest's state
    row.strip = kit.Quad(row, "ARTWORK", 1)
    row.strip:SetWidth(3)
    row.strip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    row.strip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    row.strip:Hide()

    row.level = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.level:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.level:SetWidth(26)
    row.level:SetJustifyH("RIGHT")

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
    row.title:SetJustifyH("LEFT")
    -- One line, cut with an ellipsis: about one title in twenty-five is wider
    -- than the column, and two 10 px lines do not fit a 24 px row. The row's
    -- tooltip carries the whole title.
    if row.title.SetWordWrap then row.title:SetWordWrap(false) end

    row.state = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.state:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.state:SetWidth(STATE_W)
    row.state:SetJustifyH("RIGHT")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(kit.QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.07)
    row:SetHighlightTexture(highlight)

    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", HideTooltip)
    W.rows[position] = row
    return row
end

local function EmptyMessage()
    local state = S.state
    if state == "ABSENT" then
        return "Questie is not loaded. The Zones tab reads Questie's quest database; the Log tab works without it."
    end
    if state == "LOADING" then return "Questie is still loading" .. ELLIPSIS end
    if state == "BROKEN" then
        return "Questie is loaded but did not answer the way this window expects"
            .. (S.reason and (" (" .. tostring(S.reason) .. ")") or "")
            .. ". The Log tab still works; /cql status has the detail."
    end
    if not S.areaId then return "No quest zone here. Pick one from the card above." end
    if S.err == "NO_QUESTS" then
        return "Questie lists no quests for " .. (S.areaName or "this zone") .. ". Pick another zone from the card above."
    end
    if not S.view then
        return "This zone could not be read (" .. tostring(S.err or "no answer") .. "). /cql status has the detail."
    end
    return "Nothing in " .. (S.areaName or "this zone") .. " matches this search and filter."
end

local function LayoutHeaderRow(row, item, ar, ag, ab)
    local kit = Kit()
    local header = item.header
    row.headerTitle = header.title
    row:SetHeight(kit.ROW_H)
    kit.PointChevron(row, not item.collapsed)
    for _, bar in ipairs(row.chevron) do
        bar:SetVertexColor(ar, ag, ab, 0.9)
        bar:Show()
    end
    row.level:SetText("")
    row.title:ClearAllPoints()
    row.title:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.title:SetPoint("RIGHT", row, "RIGHT", -(STATE_W + 8), 0)
    row.title:SetText(header.title)
    row.title:SetTextColor(kit.InkAccent())
    -- A chain heading reads done/total of its counted members; every other
    -- heading counts what it lists under the current search and filter
    if header.countMode == "RATIO" then
        row.state:SetText(string.format("%d/%d", header.complete or 0, header.quests or 0))
    else
        row.state:SetText(tostring(item.shownCount or header.quests or 0))
    end
    row.state:SetTextColor(kit.Paper(kit.Ink("secondary")))
    row.selection:SetVertexColor(ar, ag, ab, 0.08)
    row.selection:Show()
end

local function LayoutQuestRow(row, entry, ar, ag, ab)
    local kit, engine = Kit(), Engine()
    row.entry = entry
    if row.chevron then
        for _, bar in ipairs(row.chevron) do bar:Hide() end
    end
    row:SetHeight(kit.QUEST_ROW_H)

    row.strip:SetVertexColor(kit.Paper(ToneRGB(StatusToneKey(entry))))
    row.strip:Show()

    if DB().ShowLevels ~= false and (entry.level or 0) > 0 then
        row.level:SetText(tostring(entry.level))
        row.level:SetTextColor(kit.Paper(Q.DifficultyColor(entry.level, S.char and S.char.level)))
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
    else
        row.level:SetText("")
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row, "LEFT", 14, 0)
    end
    row.title:SetPoint("RIGHT", row, "RIGHT", -(STATE_W + 10), 0)
    row.title:SetText(entry.title)
    -- Dimmed by whether it COUNTS, not by its bucket: an exclusive choice's
    -- other members sit in Available or Locked and do not count
    if not entry.counted then
        row.title:SetTextColor(kit.Paper(kit.Ink("faint")))
    elseif entry.base == "LOG" and entry.ready then
        row.title:SetTextColor(kit.Paper(kit.Ink("strong")))
    else
        row.title:SetTextColor(kit.Paper(kit.Ink("primary")))
    end

    local word, toneKey = engine.StateWord(entry)
    row.state:SetText(word or "")
    row.state:SetTextColor(kit.Paper(ToneRGB(toneKey)))

    if S.selectedId and entry.id == S.selectedId then
        row.selection:SetVertexColor(ar, ag, ab, 0.22)
        row.selection:Show()
    end
end

local function LayoutRows()
    local kit = Kit()
    local navChild = kit.NavChild()
    -- The selection band, the heading wash and the chevrons are fills, and on
    -- the paper a fill is ink too (the default accent is white)
    local ar, ag, ab = kit.InkAccent()
    local y = 4
    S.selectedTop, S.selectedHeight = nil, nil

    for position, item in ipairs(S.rows) do
        local row = AcquireRow(position)
        row.entry, row.headerTitle = nil, nil
        row.selection:Hide()
        row.strip:Hide()
        if item.header then
            LayoutHeaderRow(row, item, ar, ag, ab)
        else
            LayoutQuestRow(row, item.entry, ar, ag, ab)
            if S.selectedId and item.entry.id == S.selectedId then
                S.selectedTop, S.selectedHeight = y, row:GetHeight()
            end
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)
        row:Show()
        y = y + row:GetHeight()
    end
    for position = #S.rows + 1, #W.rows do W.rows[position]:Hide() end

    if #S.rows == 0 then
        if not W.emptyFS then
            W.emptyFS = navChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            W.emptyFS:SetPoint("TOPLEFT", navChild, "TOPLEFT", 12, -16)
            W.emptyFS:SetWidth(kit.NAV_W - 30)
            W.emptyFS:SetJustifyH("LEFT")
        end
        W.emptyFS:SetText(EmptyMessage())
        W.emptyFS:SetTextColor(kit.Paper(kit.Ink("faint")))
        W.emptyFS:Show()
        y = y + 60
    elseif W.emptyFS then
        W.emptyFS:Hide()
    end
    navChild:SetHeight(math.max(y + 6, 1))
end

-- ---------------------------------------------------------------------------
-- The briefing: drawing primitives
--
-- Pooled by position like the Log's, with the font and the colour put back on
-- every pass (D15): the overview and a quest put different kinds of line at
-- the same position. Quads come from two pools, bars and marks over the text
-- layer and selection bands under it.
-- ---------------------------------------------------------------------------

local function AcquireBlock(position, template)
    local block = W.blocks[position]
    if not block then
        block = Kit().DetailChild():CreateFontString(nil, "ARTWORK", template)
        block:SetJustifyH("LEFT")
        block:SetJustifyV("TOP")
        block._template = template
        W.blocks[position] = block
        return block
    end
    if block._template ~= template then
        block._template = template
        local font = _G[template]
        if font and block.SetFontObject then block:SetFontObject(font) end
    end
    return block
end

local function AcquireQuad(pool, position, layer)
    local quad = pool[position]
    if quad then return quad end
    quad = Kit().Quad(Kit().DetailChild(), layer)
    pool[position] = quad
    return quad
end

-- One line of text at the cursor; colour is an {r, g, b} table and goes
-- through Paper() here, so no caller can forget it. Returns block, height.
local function Line(text, template, colour, indent)
    local kit = Kit()
    indent = indent or 0
    local block = AcquireBlock(P.block, template or "GameFontHighlightSmall")
    P.block = P.block + 1
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -P.y)
    block:SetWidth(P.width - indent)
    block:SetText(text or "")
    local c = colour or InkT("secondary")
    block:SetTextColor(kit.Paper(c[1], c[2], c[3]))
    block:Show()
    local height = math.max(block:GetStringHeight() or 12, 12)
    P.y = P.y + height + 3
    return block, height
end

local function Heading(text)
    return Line(text, "GameFontNormalSmall", { Kit().InkAccent() })
end

-- A bar: a ground quad and an accent fill across `fraction` of it
local function Bar(indent, height, fraction, gap)
    local kit = Kit()
    local span = P.width - indent
    local ground = AcquireQuad(W.quads, P.quad, "ARTWORK")
    P.quad = P.quad + 1
    ground:ClearAllPoints()
    ground:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -P.y)
    ground:SetSize(span, height)
    if kit.OnPaper() then ground:SetVertexColor(0, 0, 0, 0.14) else ground:SetVertexColor(1, 1, 1, 0.1) end
    ground:Show()
    if fraction and fraction > 0 then
        local fill = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", ground, "TOPLEFT", 0, 0)
        fill:SetSize(math.max(1, span * math.min(fraction, 1)), height)
        local r, g, b = kit.InkAccent()
        fill:SetVertexColor(r, g, b, 0.9)
        fill:Show()
    end
    P.y = P.y + height + (gap or 6)
end

local function Rule(spacingAbove)
    local kit = Kit()
    P.y = P.y + (spacingAbove or 6)
    local rule = AcquireQuad(W.quads, P.quad, "ARTWORK")
    P.quad = P.quad + 1
    rule:ClearAllPoints()
    rule:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD, -P.y)
    rule:SetSize(P.width, 1)
    local r, g, b = kit.InkAccent()
    rule:SetVertexColor(r, g, b, 0.25)
    rule:Show()
    P.y = P.y + 7
end

-- A small square at the cursor, for a chain member's state (a quad, never a
-- bullet glyph -- D11). It does not move the cursor; the line beside it does.
local function Mark(indent, toneKey)
    local kit = Kit()
    local mark = AcquireQuad(W.quads, P.quad, "ARTWORK")
    P.quad = P.quad + 1
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -(P.y + 3))
    mark:SetSize(MARK_SIZE, MARK_SIZE)
    local r, g, b = kit.Paper(ToneRGB(toneKey))
    mark:SetVertexColor(r, g, b, 1)
    mark:Show()
end

-- The accent band under the current quest's line in its chain
local function Band(top, height)
    local kit = Kit()
    local band = AcquireQuad(W.bands, P.band, "BACKGROUND")
    P.band = P.band + 1
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD - 2, -top)
    band:SetSize(P.width + 4, height)
    local r, g, b = kit.InkAccent()
    band:SetVertexColor(r, g, b, 0.16)
    band:Show()
end

-- ---------------------------------------------------------------------------
-- The briefing: what is drawn
-- ---------------------------------------------------------------------------

-- Everything Questie knows about the selected quest beyond its fact, read
-- lazily once per quest per adapter generation
local function DetailFor(entry)
    local adapter = Adapter()
    if not (entry and adapter and adapter.QuestDetail) then return nil end
    local generation = adapter.generation or 0
    local cached = S.detailCache
    if cached and cached.id == entry.id and cached.areaId == S.areaId and cached.generation == generation then
        return cached.detail
    end
    local detail = adapter.QuestDetail(entry.id, S.areaId)
    S.detailCache = { id = entry.id, areaId = S.areaId, generation = generation, detail = detail }
    return detail
end

local function BreakdownText(totals)
    local counted = totals.countedByStatus or {}
    return string.format("Done %d%sIn log %d%sOpen %d%sLocked %d",
        counted.DONE or 0, SEP, counted.LOG or 0, SEP, counted.AVAILABLE or 0, SEP, counted.LOCKED or 0)
end

-- The uncounted line, from byStatus. The counted buckets' extra members --
-- the other choices of an exclusive group -- are the difference between the
-- two tallies.
local function UncountedText(totals)
    local by, counted = totals.byStatus or {}, totals.countedByStatus or {}
    local parts = { "Missed " .. (by.MISSED or 0) }
    if (by.RIVAL or 0) > 0 then parts[#parts + 1] = "Other faction " .. by.RIVAL end
    parts[#parts + 1] = "Repeatable " .. (by.REPEATABLE or 0)
    parts[#parts + 1] = "Seasonal " .. (by.SEASONAL or 0)
    if (by.OPTIONAL or 0) > 0 then parts[#parts + 1] = "Optional " .. by.OPTIONAL end
    if (by.EXTRA or 0) > 0 then parts[#parts + 1] = "Starting here " .. by.EXTRA end
    if (by.IGNORED or 0) > 0 then parts[#parts + 1] = "Ignored " .. by.IGNORED end
    local choices = 0
    for _, bucket in ipairs({ "DONE", "LOG", "AVAILABLE", "LOCKED" }) do
        choices = choices + math.max(0, (by[bucket] or 0) - (counted[bucket] or 0))
    end
    if choices > 0 then parts[#parts + 1] = "Other choices " .. choices end
    return table.concat(parts, SEP) .. " (not counted)"
end

local function LayoutMessage()
    local kit = Kit()
    Line(S.areaName or "Zones", "GameFontNormalLarge", kit.InkSet().title)
    Line(EmptyMessage(), "GameFontHighlightSmall", InkT("secondary"))
end

local function LayoutOverview(view)
    local kit, engine = Kit(), Engine()
    local totals = view.totals or {}

    Line(view.name or S.areaName or "", "GameFontNormalLarge", kit.InkSet().title)
    Line(string.format("%d of %d quests done%s%s", totals.done or 0, totals.counted or 0, SEP,
        engine.PercentText(totals.pct)), "GameFontHighlight", InkT("primary"))
    Bar(0, TOTAL_BAR_H, totals.pct or 0)
    Line(BreakdownText(totals), "GameFontHighlightSmall", InkT("secondary"))
    Line(UncountedText(totals), "GameFontDisableSmall", InkT("faint"))

    Rule()
    Heading("NEXT UP")
    local nextUp = engine.NextUp(view, NEXT_UP_COUNT, { playerPos = S.playerPos })
    if #nextUp == 0 then
        local finished = (totals.counted or 0) > 0 and totals.done == totals.counted
        Line(finished and "Every quest that counts here is done." or "Nothing to pick up or hand in here right now.",
            "GameFontHighlightSmall", InkT("faint"), 4)
    end
    for _, entry in ipairs(nextUp) do
        local word, toneKey = engine.StateWord(entry)
        local giver = GiverName(entry)
        Line(ToneMarkup(toneKey, word) .. "  " .. entry.title .. (giver and (DASH .. giver) or ""),
            "GameFontHighlightSmall", InkT("primary"), 4)
    end

    local chains = {}
    for _, chain in ipairs(view.chains or {}) do
        if (chain.total or 0) > 0 then chains[#chains + 1] = chain end
    end
    if #chains > 0 then
        Rule()
        Heading("CHAINS")
        for _, chain in ipairs(chains) do
            local finished = chain.done >= chain.total
            Line(string.format("%s  %d/%d", chain.title or ("Quest " .. chain.id), chain.done, chain.total),
                "GameFontHighlightSmall", InkT(finished and "secondary" or "primary"), 4)
            Bar(4, CHAIN_BAR_H, chain.done / chain.total, 4)
        end
    end

    local missed = {}
    for _, entry in ipairs(view.entries or {}) do
        if entry.status == "MISSED" then missed[#missed + 1] = entry end
    end
    if #missed > 0 then
        Rule()
        Heading("MISSED")
        for _, entry in ipairs(missed) do
            Line(entry.title .. DASH .. engine.Reason(entry, S.char or {}, view),
                "GameFontHighlightSmall", InkT("secondary"), 4)
        end
    end
end

local function FactsFor(entry, view)
    local facts = {}
    if (entry.level or 0) > 0 then facts[#facts + 1] = "Level " .. entry.level end
    if (entry.requiredLevel or 0) > 0 then facts[#facts + 1] = "requires " .. entry.requiredLevel end
    if view.name then facts[#facts + 1] = view.name end
    if entry.tag and TAG_WORDS[entry.tag] then facts[#facts + 1] = TAG_WORDS[entry.tag] end
    if entry.startsHere == false and entry.startZoneName then
        facts[#facts + 1] = "starts in " .. entry.startZoneName
    end
    if not entry.counted then facts[#facts + 1] = "not counted" end
    return facts
end

local function LayoutWhere(entry)
    Rule(4)
    Heading("WHERE")
    local starters = DistinctGivers(entry.starters, GIVERS_SHOWN)
    if #starters == 0 then
        Line("Starts  nowhere Questie knows of", "GameFontHighlightSmall", InkT("faint"), 4)
    end
    for _, starter in ipairs(starters) do
        Line("Starts  " .. GiverPhrase(starter), "GameFontHighlightSmall", InkT("primary"), 4)
    end
    local finisher = FirstPlaced(entry.finishers) or DistinctGivers(entry.finishers, 1)[1]
    if finisher then
        Line("Ends  " .. GiverPhrase(finisher), "GameFontHighlightSmall", InkT("primary"), 4)
    end
end

local function LayoutChain(entry, view)
    local engine = Engine()
    local chain
    for _, candidate in ipairs(view.chains or {}) do
        if candidate.id == entry.chain then chain = candidate break end
    end
    if not chain then return end
    Rule()
    Heading(string.format("CHAIN%s%d of %d done", SEP, chain.done or 0, chain.total or 0))
    for _, id in ipairs(chain.members or {}) do
        local member = view.byId and view.byId[id]
        if member then
            local current = member == entry
            local top = P.y
            local word, toneKey = engine.StateWord(member)
            Mark(4, StatusToneKey(member))
            local _, height = Line(ToneMarkup(toneKey, word) .. "  " .. member.title, "GameFontHighlightSmall",
                InkT(current and "strong" or (member.counted and "primary" or "faint")), 4 + MARK_SIZE + 6)
            if current then Band(top - 1, height + 2) end
        end
    end
end

-- "done  Name (Zone)" for a prerequisite or a follow-up
local function RefLine(ref)
    local word = ref.done and ToneMarkup("good", "done") or ToneMarkup("warn", "to do")
    local text = word .. "  " .. (ref.name or ("Quest " .. tostring(ref.id)))
    if ref.zoneName then text = text .. " (" .. ref.zoneName .. ")" end
    return text
end

local function LayoutLinks(entry, detail)
    if not detail then return end
    local external = {}
    for _, id in ipairs(entry.externalPrereqs or {}) do external[id] = true end
    local shown = false
    for _, ref in ipairs(detail.prereqs or {}) do
        if external[ref.id] then
            if not shown then
                Rule()
                Heading("REQUIRES")
                shown = true
            end
            Line(RefLine(ref), "GameFontHighlightSmall", InkT("primary"), 4)
        end
    end
    if #(detail.followups or {}) > 0 then
        Rule()
        Heading("LEADS TO")
        for _, ref in ipairs(detail.followups) do
            Line(RefLine(ref), "GameFontHighlightSmall", InkT("primary"), 4)
        end
    end
end

-- In the log: the live objectives with their counts (the Log's own scan and
-- its detail read). Otherwise Questie's objective text.
local function LayoutObjectives(entry, detail)
    local logEntry = LogEntryFor(entry)
    if logEntry then
        Rule()
        Heading("OBJECTIVES")
        local logDetail = S.logDetail
        if logDetail and logDetail.objectivesText and logDetail.objectivesText ~= "" then
            Line(logDetail.objectivesText, "GameFontHighlightSmall", InkT("primary"), 4)
        end
        for _, objective in ipairs(logEntry.objectives or {}) do
            Line("\194\183 " .. (objective.text or ""), "GameFontHighlightSmall",
                objective.finished and OBJECTIVE_DONE or OBJECTIVE_OPEN, 6)
        end
        if logEntry.isComplete then
            Line("Ready to turn in.", "GameFontNormalSmall", ToneT("good"), 4)
        end
        return
    end
    local texts = detail and detail.objectivesText
    if type(texts) == "table" and #texts > 0 then
        Rule()
        Heading("OBJECTIVES")
        for _, text in ipairs(texts) do
            Line(tostring(text), "GameFontHighlightSmall", InkT("primary"), 4)
        end
    end
end

local function LayoutReputation(detail)
    local rewards = detail and detail.repRewards
    if not (type(rewards) == "table" and #rewards > 0) then return end
    Rule()
    Heading("REPUTATION")
    for _, reward in ipairs(rewards) do
        Line(string.format("%+d  %s", tonumber(reward.value) or 0, reward.factionName or "a faction"),
            "GameFontHighlightSmall", InkT("secondary"), 4)
    end
end

local function LayoutQuest(entry, view)
    local kit, engine = Kit(), Engine()
    local detail = DetailFor(entry)
    Line(entry.title, "GameFontNormalLarge", kit.InkSet().title)
    Line(table.concat(FactsFor(entry, view), SEP), "GameFontDisableSmall", InkT("secondary"))
    Line(engine.Reason(entry, S.char or {}, view), "GameFontNormalSmall", ToneT(StatusToneKey(entry)))
    LayoutWhere(entry)
    if entry.chain then LayoutChain(entry, view) end
    LayoutLinks(entry, detail)
    LayoutObjectives(entry, detail)
    LayoutReputation(detail)
end

local function LayoutBriefing()
    local kit = Kit()
    P.y, P.block, P.quad, P.band = 6, 1, 1, 1
    P.width = kit.DetailWidth() - kit.PAD
    if not S.view then
        LayoutMessage()
    elseif S.selectedEntry then
        LayoutQuest(S.selectedEntry, S.view)
    else
        LayoutOverview(S.view)
    end
    for position = P.block, #W.blocks do W.blocks[position]:Hide() end
    for position = P.quad, #W.quads do W.quads[position]:Hide() end
    for position = P.band, #W.bands do W.bands[position]:Hide() end
    kit.DetailChild():SetHeight(math.max(P.y + 10, 1))
end

-- ---------------------------------------------------------------------------
-- Toolbar, card and action bar state
-- ---------------------------------------------------------------------------

local function UpdateToolbar()
    local kit, engine = Kit(), Engine()
    local db = DB()
    local ar, ag, ab = kit.InkAccent()
    for key, button in pairs(W.filters) do
        local active = (db.ZoneFilter or "ALL") == key
        if button.SetNormalFontObject then
            button:SetNormalFontObject(active and GameFontNormalSmall or GameFontDisableSmall)
        end
        -- After the font object, never before (D14's lesson): the swap
        -- re-applies the font's own grey
        local fs = button.GetFontString and button:GetFontString()
        if fs then
            if active then fs:SetTextColor(kit.Ink("strong")) else fs:SetTextColor(kit.Ink("faint")) end
        end
        button.underline:SetVertexColor(ar, ag, ab, active and 0.95 or 0)
    end
    -- Text only. UIDropDownMenu_SetSelectedValue refreshes whatever dropdown
    -- list is OPEN, which on a refresh mid-menu would be the zone menu's; the
    -- selected value is set where the player picks it (PickGroup)
    if engine and UIDropDownMenu_SetText then
        local group = db.ZoneGroup or "GUIDE"
        UIDropDownMenu_SetText(W.groupDrop, engine.GROUP_LABELS[group] or group)
    end
    W.countFS:SetText(S.view and string.format("%d shown", S.shown or 0) or "")
    W.countFS:SetTextColor(kit.Ink("secondary"))
end

-- The filters' labels again, after a hover put a font's own colour back
function Z.RestyleToolbar()
    if W.toolbar and W.toolbar:IsShown() and Kit() then UpdateToolbar() end
end

local function UpdateCard()
    local card, kit, engine = W.card, Kit(), Engine()
    local ar, ag, ab = kit.InkAccent()
    -- The panes' own wash: a thin ink on the paper, half-black elsewhere
    if kit.OnPaper() then
        card.bg:SetVertexColor(0.30, 0.20, 0.08, 0.10)
    else
        card.bg:SetVertexColor(0, 0, 0, 0.4)
    end
    card.rule:SetVertexColor(ar, ag, ab, 0.35)

    card.name:SetText(S.areaName or "Zones")
    card.name:SetTextColor(kit.InkAccent())
    local totals = S.view and S.view.totals
    card.totals:SetText((totals and engine) and engine.TotalsText(totals) or "")
    card.totals:SetTextColor(kit.Paper(kit.Ink("primary")))

    if kit.OnPaper() then card.barBg:SetVertexColor(0, 0, 0, 0.14) else card.barBg:SetVertexColor(1, 1, 1, 0.1) end
    local span = (card:GetWidth() or 0) - 16
    if span <= 0 then span = kit.NAV_W - 16 end
    local pct = totals and totals.pct or 0
    if pct > 0 then
        card.bar:SetWidth(math.max(1, span * math.min(pct, 1)))
        local r, g, b = kit.InkAccent()
        card.bar:SetVertexColor(r, g, b, 0.9)
        card.bar:Show()
    else
        card.bar:Hide()
    end

    card.note:SetText(DB().ZoneFollow ~= false and "Following you. Click to pick a zone."
        or "Pinned. Click to change; right-click to follow you.")
    card.note:SetTextColor(kit.Paper(kit.Ink("faint")))
end

function Z.UpdateActions()
    if not W.actions then return end
    local entry = S.selectedEntry
    W.waypointBtn:SetEnabled(entry ~= nil and WaypointTarget(entry) ~= nil)
    W.mapBtn:SetEnabled(S.view ~= nil and MapForZone() ~= nil)
    W.logBtn:SetEnabled(LogEntryFor(entry) ~= nil)
    local adapter = Adapter()
    W.routeBtn:SetEnabled(adapter ~= nil and adapter.WaypointPath ~= nil and adapter.WaypointPath() == "ORDERS"
        and RouteStopCount() > 0)
    W.ignoreBtn:SetEnabled(entry ~= nil)
    W.ignoreBtn:SetText((entry and IsIgnored(entry.id)) and "Count" or "Ignore")
end

-- ---------------------------------------------------------------------------
-- The model pass
-- ---------------------------------------------------------------------------

-- The Log's scan, keyed the way zone entries are ("id:9003"), so a zone row
-- knows whether its quest is in the log and can borrow its live objectives
local function IndexLog(entries)
    local byKey = {}
    for _, entry in ipairs(entries or {}) do
        if not entry.isHeader and entry.key then byKey[entry.key] = entry end
    end
    S.logByKey = byKey
end

-- Following: wherever the player stands (nil in a spot that resolves to no
-- quest zone). Pinned: the zone picked, an AREA id.
local function ResolveZone()
    local adapter = Adapter()
    local db = DB()
    if db.ZoneFollow ~= false then
        if adapter and adapter.ZoneForPlayer then
            local areaId, name = adapter.ZoneForPlayer()
            if areaId then return areaId, name end
        end
        return nil, nil
    end
    local picked = tonumber(db.ZonePicked)
    if picked and picked ~= 0 then
        return picked, (adapter and adapter.ZoneName) and adapter.ZoneName(picked) or ("Zone " .. picked)
    end
    return nil, nil
end

-- Group, then list: nothing may regroup in between (see the file header)
local function GroupAndList(view)
    local engine, db = Engine(), DB()
    local filter = db.ZoneFilter or "ALL"
    local list = engine.Group(view, db.ZoneGroup or "GUIDE", { playerPos = S.playerPos })
    return Q.BuildList(list, {
        search = S.search,
        -- entry.header is a status group here ("Pick up now", "Done"), not
        -- a zone: "pick" would list a whole group whose titles never say it
        matchHeader = false,
        sort = "LOG",
        collapsed = db.ZoneCollapsed or {},
        predicate = function(entry) return engine.PassesFilter(entry, filter) end,
    })
end

-- The Log's detail read for a quest that is in the log (its objective
-- summary). Q.ReadDetail puts back a selection it found, but one it found
-- EMPTY it leaves on the quest it read -- harmless on the Log, which selects
-- the briefed quest anyway for its reward tooltips, and wrong here, where the
-- client's selection is not this tab's to move (D2). So an empty one is
-- emptied again.
local function ReadLogDetail(logEntry)
    if not (logEntry and logEntry.index and Q.ReadDetail) then return nil end
    local before = GetQuestLogSelection and GetQuestLogSelection() or nil
    local detail = Q.ReadDetail(logEntry.index)
    if before == 0 and SelectQuestLogEntry and GetQuestLogSelection and GetQuestLogSelection() ~= 0 then
        SelectQuestLogEntry(0)
    end
    return detail
end

local function FindSelected()
    for _, item in ipairs(S.rows) do
        if item.entry and item.entry.id == S.selectedId then return item.entry end
    end
    return nil
end

-- A quest asked for by name that the search, the filter or a fold has taken
-- off the list: clear the search, open the filter, unfold its group
local function Reveal(view)
    local entry = view.byId and view.byId[S.selectedId]
    if not entry then return end
    local db = DB()
    S.search = ""
    local frame = Kit().Frame()
    if frame and frame.searchBox then frame.searchBox:SetText("") end
    db.ZoneFilter = "ALL"
    if entry.header and type(db.ZoneCollapsed) == "table" then db.ZoneCollapsed[entry.header] = nil end
    S.rows, S.shown = GroupAndList(view)
    S.selectedEntry = FindSelected()
end

local function BuildRows()
    local adapter = Adapter()
    local areaId, name = ResolveZone()
    if areaId ~= S.areaId then
        S.areaId = areaId
        S.selectedId = nil
        S.detailCache = nil
        local scroll = Kit().NavScroll()
        if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
    end
    if S.pendingSelect then
        S.selectedId = S.pendingSelect
        S.pendingSelect = nil
    end
    S.areaName = name
    if not areaId then return end

    local view, err = adapter.ZoneView(areaId)
    S.view, S.err = view, err
    if not view then
        if adapter.ZoneName then S.areaName = adapter.ZoneName(areaId) end
        return
    end
    S.areaName = view.name or name
    S.char = adapter.Character and adapter.Character() or {}
    S.playerPos = adapter.PlayerPos and adapter.PlayerPos(areaId) or nil

    S.rows, S.shown = GroupAndList(view)
    -- The selection has to be a row that is on screen (D6). The zone's own
    -- overview is the briefing with nothing selected, so a selection that
    -- went out of view falls back to it rather than to the first row.
    if S.selectedId then
        S.selectedEntry = FindSelected()
        if not S.selectedEntry and S.reveal then Reveal(view) end
        if not S.selectedEntry then S.selectedId = nil end
    end
    S.reveal = false

    S.logDetail = ReadLogDetail(LogEntryFor(S.selectedEntry))
end

local function SetOwnWidgetsShown(shown)
    if W.toolbar then W.toolbar:SetShown(shown) end
    if W.card then W.card:SetShown(shown) end
    if W.actions then W.actions:SetShown(shown) end
end

-- The Zones tab's pass. UI.lua's Q.Refresh has scanned the log (entries) and
-- put the Log's own widgets away; this draws everything else.
function Z.Refresh(entries)
    local kit = Kit()
    local frame = kit and kit.Frame()
    if not frame then return end
    EnsureBuilt(frame)
    SetOwnWidgetsShown(true)
    IndexLog(entries)
    Z.UpdateTabs()

    S.state, S.reason = AdapterState()
    S.view, S.err, S.rows, S.shown = nil, nil, {}, 0
    S.selectedEntry, S.logDetail, S.char, S.playerPos = nil, nil, nil, nil
    -- A quest asked for by name is brought into view as well as revealed
    local scrollTo = S.reveal
    if S.state == "READY" then
        BuildRows()
    else
        S.areaName = nil
        S.reveal = false
    end

    LayoutRows()
    if scrollTo and S.selectedEntry and kit.ScrollIntoView then
        kit.ScrollIntoView(kit.NavScroll(), kit.NavChild(), S.selectedTop, S.selectedHeight)
    end
    LayoutBriefing()
    UpdateToolbar()
    UpdateCard()
    Z.UpdateActions()
end

-- Everything this tab drew, put away for the Log
function Z.HideAll()
    SetOwnWidgetsShown(false)
    for _, row in ipairs(W.rows) do row:Hide() end
    if W.emptyFS then W.emptyFS:Hide() end
    for _, block in ipairs(W.blocks) do block:Hide() end
    for _, quad in ipairs(W.quads) do quad:Hide() end
    for _, band in ipairs(W.bands) do band:Hide() end
    Z.UpdateTabs()
end

-- ---------------------------------------------------------------------------
-- Search, selection and opening from elsewhere
-- ---------------------------------------------------------------------------

function Z.SetSearch(text)
    S.search = text or ""
end

function Z.SearchText()
    return S.search
end

-- Escape clears the search; pressed again on an empty search it goes back to
-- the zone's overview
function Z.EscapeSearch()
    if S.search == "" then S.selectedId = nil end
    S.search = ""
end

-- The briefed zone quest (an engine entry), or nil on the overview
function Z.Selected()
    return S.selectedEntry
end

function Z.Select(questId)
    S.selectedId = tonumber(questId)
    Q.Refresh()
end

-- Called by CommanderQuestLog_OpenToZone before it switches tabs. areaId nil
-- follows the player. Answers false when the Zones tab is switched off.
function Z.PrepareOpen(areaId, questId)
    local db = DB()
    if db.ShowZoneTab == false then
        print("Commander Quest Log: the Zones tab is switched off (settings, Zones & Completion).")
        return false
    end
    if type(areaId) == "number" then
        db.ZoneFollow = false
        db.ZonePicked = areaId
    else
        db.ZoneFollow = true
        db.ZonePicked = false
    end
    S.pendingSelect = tonumber(questId)
    S.reveal = S.pendingSelect ~= nil
    if not S.pendingSelect then S.selectedId = nil end
    return true
end

-- ---------------------------------------------------------------------------
-- Events
--
-- The adapter's generation listener is the one signal that Questie's answer
-- changed (a turn-in, a level, a reputation tick, an Ignore, a setting); it
-- refreshes whichever tab is up, because the Log's "Turn in:" line reads
-- Questie too. Moving zone only matters to a Zones tab that follows you.
-- Both go through the window's own one-pass-per-frame queue (D10).
-- ---------------------------------------------------------------------------

local function OnGeneration()
    if Q.QueueRefresh then Q.QueueRefresh() end
end

if CreateFrame then
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            local adapter = Adapter()
            if adapter and adapter.AddListener then adapter.AddListener(OnGeneration) end
            return
        end
        if Z.IsActive() and DB().ZoneFollow ~= false and Q.QueueRefresh then Q.QueueRefresh() end
    end)
end

-- ---------------------------------------------------------------------------
-- Harness accessors. Nothing in the game reads these.
-- ---------------------------------------------------------------------------

function Z._Widgets() return W end
function Z._State() return S end

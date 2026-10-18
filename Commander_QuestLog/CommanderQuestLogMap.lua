-- Commander Quest Log: the world-map drawer and its pins.
--
-- The Zones tab answers "how much of this zone have I done?" inside the quest
-- log window -- but the question gets asked with the world map open, and with
-- the map maximized (the player's setting) the quest log window is not merely
-- elsewhere, it is underneath. So the same answer lives on the map itself: a
-- drawer docked inside the map's right edge shows the shown zone's completion
-- and its quests, a continent map lists its zones with their percentages, and
-- pins mark the quest givers Questie does NOT draw -- the locked ones, and on
-- request the done and the missed. Nothing here computes a number. The view
-- comes from the adapter (CommanderQuestLogQuestie.lua), which got it from the
-- engine (CommanderQuestLogCompletion.lua), so the drawer and the window can
-- never disagree; this file only lays it out.
--
-- The traps, each one either paid for elsewhere in the suite or read out of
-- Blizzard's map code and the two map libraries Questie ships:
--
--   * The map changes STRATA under us. Maximized it is FULLSCREEN, with a
--     blackout behind it; windowed it is MEDIUM. Blizzard flips it in
--     SynchronizeDisplayState. The drawer is parented to WorldMapFrame and
--     never has SetFrameStrata called on it, so it rides along; a strata of
--     our own would leave it behind the maximized map or floating over the
--     windowed one. It is a child of WorldMapFrame rather than of the
--     ScrollContainer because the windowed map's opacity slider fades the
--     container furthest: WorldMapFrame_SetOpacity takes the whole frame
--     down to half and the container below that, so the drawer, a child of
--     the frame, fades to half at most where the map underneath goes to a
--     fifth. (A buffered frame's alpha is applied when it is composited, so
--     SetIgnoreParentAlpha would not lift it; the half is accepted.)
--   * It is ANCHORED to the ScrollContainer, whose rectangle Blizzard re-points
--     in both modes, so an anchor on the container's right edge follows every
--     layout without knowing a single size. The top inset clears Questie's own
--     map button row, which sits in the container's top-right corner.
--   * Frame levels. The map's pins take ABSOLUTE levels from its pin-level
--     manager, from 2000 up: Questie's icons 2016 and above, ours at AREA_POI
--     (2018), and on TBC the battlefield flags, the player arrow and party
--     dots, the corpse and the area banner at 2753-2757. The container itself
--     sits far below that. So the drawer goes at the container's level plus
--     2200 or ten over the manager's topmost pin level, whichever is higher,
--     capped well under the 10000 ceiling -- over the player arrow, which a
--     fixed +2200 would have drawn on top of the list.
--   * Nothing secure ever goes near the map. A secure frame parented to or
--     anchored on WorldMapFrame pulls the map into the protected family, and
--     Blizzard's own SetSize in SynchronizeDisplayState would then be blocked
--     in combat -- and blamed on us. Every frame here is plain.
--   * WorldMapFrame's fields are never ASSIGNED. hooksecurefunc and one added
--     key under WorldMapFrame.pinPools (the HereBeDragons recipe) are the only
--     writes; an assignment to a FrameXML table is how Escape got tainted.
--   * The quest log window is HIGH strata and not a UIPanel, so the maximized
--     map covers it. "Open in the quest log" closes the map first, through
--     HideUIPanel: Questie avoids WorldMapFrame:Hide() for taint reasons. In
--     combat HideUIPanel from addon code is refused (and says so in chat), so
--     there the window opens and a line says to close the map with M.
--   * The open drawer covers the map's east quarter, so a giver it points to
--     can stand underneath it. While a quest pulses, its pins are lifted over
--     the drawer (the pin's ApplyFrameLevel), and drop back when it ends.
--   * Pins come from our own data provider. The suite ships no XML, so the pin
--     pool is built the way HereBeDragons builds it ON THIS CLIENT: 2.5.6's
--     CreateFramePool is the SECURE pool, a proxy that ignores writes to its
--     createFunc / resetFunc, so it would hand out bare frames -- no mixin, no
--     OnLoad -- and Blizzard's own map code then errors on them every frame
--     the map is open. HBD takes CreateUnsecuredRegionPoolInstance where it
--     exists (HereBeDragons-Pins-2.0.lua:33-39), and so does this file, with
--     the creation and reset functions set under both their names; where it
--     does not, CreateFramePool gets the mixin through its postCreate as well.
--     AcquirePin calls a new pin's OnLoad on this build (Blizzard_MapCanvas
--     .lua:189-191); OnLoad is idempotent and OnAcquired runs it should a
--     client not. Pins carry HBD's no-op SetPassThroughButtons (its in-combat
--     fix), and take mouse MOTION only, so a click on a pin still reaches the
--     map underneath.
--   * Two icons must never stack: a quest Questie is drawing (its
--     AvailableQuests set) gets no pin of ours, whatever its status.
--   * The id spaces. Questie speaks areaIds, the map speaks uiMapIDs, and the
--     adapter is the only bridge; every variable here says which it holds.
--   * The list is a plain stack of pooled rows scrolled by row offset, with a
--     drawn indicator. A ScrollFrame template wants a named scroll child, which
--     would be one more global for every drawer the map ever builds.
--   * A continent's percentages are computed by the adapter in the background,
--     one zone per tick. The drawer and the label pins redraw as they land, at
--     most a few times a second (SUMMARY_REDRAW_SECONDS): a redraw per landed
--     summary re-acquired every label pin twenty times a second.
--   * The pin art is Questie's own icon files -- the one borrowed art, drawn
--     only while Questie is loaded, which is the only time a pin can exist.
--     Everything else is WHITE8X8 quads and plain words (D11).
--   * Reputation (1.6.0): a quest's row tooltip and every quest in a pin's
--     tooltip carry what it is worth ("Reputation: +275 Honor Hold", "No
--     reputation") -- the adapter's one line, the same the window and the NPC
--     dialog show, never worked out here. The row also carries the number as
--     a badge with its faction's tag ("+275 HH"), but only in the maximized
--     drawer: the windowed one is 30 px narrower and a quest title is what it
--     is there to show.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local M = {}
Q.Map = M

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local QUAD = "Interface\\Buttons\\WHITE8X8"
local ICON_DIR = "Interface\\AddOns\\Questie\\Icons\\"
local PIN_TEMPLATE = "CommanderQuestLogPinTemplate"
local DRAWER_NAME = "CommanderQuestLogMapDrawer"

local DRAWER_W, DRAWER_W_MAXIMIZED = 220, 250
local INSET_RIGHT, INSET_TOP, INSET_BOTTOM = -8, -40, 8
local LEVEL_ABOVE_CONTAINER, LEVEL_CAP = 2200, 9000
local LEVEL_ABOVE_PINS = 10            -- over the map's topmost pin level (the player arrow, 2754)
local LEVEL_PULSE = 10                 -- a pulsing pin over the drawer
local SUMMARY_REDRAW_SECONDS = 0.25    -- landed continent summaries redraw at most this often
local STRIP_H = 30                     -- the header strip: all a folded drawer shows
local BREAKDOWN_H = 16
local LIST_TOP = STRIP_H + BREAKDOWN_H + 2
local PAD = 6
local SCROLL_GUTTER = 6
local ROW_H = 16
local LEVEL_W = 18
local STATE_W = 42
local WHEEL_ROWS = 2
local PULSE_SECONDS = 3
local TOOLTIP_QUEST_CAP = 8
local BADGE_GAP = 4                    -- between a row's reputation badge and its state word
local BADGE_MAX_W = 64                 -- the window's cap; RepBadgeText keeps a badge to 12 characters ("+1000 Scry")
local OBSERVED_WORDS = "seen in game"

-- The drawer's compact STATUS grouping. The titles are the fold keys in
-- CommanderQuestLogDB.MapCollapsed, so they are fixed strings.
local ZONE_GROUPS = {
    { title = "In your log", status = "LOG" },
    { title = "Open", status = "AVAILABLE" },
    { title = "Locked", status = "LOCKED" },
    { title = "Missed", status = "MISSED" },
    { title = "Done", status = "DONE" },
}
local GROUP_OF_STATUS = {}
for _, group in ipairs(ZONE_GROUPS) do GROUP_OF_STATUS[group.status] = group.title end

-- Pin looks, best first by rank: a giver with an open quest and a locked one
-- wears the open quest's look
local LOOKS = {
    AVAILABLE = { texture = ICON_DIR .. "available.blp", size = 16, rank = 4 },
    LOCKED = { texture = ICON_DIR .. "available_gray.blp", size = 16, rank = 3 },
    MISSED = { texture = ICON_DIR .. "available_gray.blp", size = 16, rank = 2,
               tint = { 0.9, 0.35, 0.3 }, alpha = 0.7 },
    DONE = { texture = ICON_DIR .. "checkmark.tga", size = 14, rank = 1 },
}
local WHITE = { 1, 1, 1 }

local MSG_LOADING = "Questie is still loading..."
-- The two error lines are one 10-pt line in 194 px (windowed) or 224 px:
-- short enough that the part a player can act on, /cql status, is not cut
local MSG_BROKEN = "Questie unreadable: /cql status"
local MSG_NO_ZONE = "No quest zone on this map."
local MSG_NO_QUESTS = "No quests are filed here."
local MSG_NO_ZONES = "No quest zones on this map."
local MSG_UNAVAILABLE = "Zone unreadable: /cql status"
local MSG_ONLY_UNCOUNTED = "Only quests outside your 100% are filed here."

local ROW_HINT = "Click: show its giver on the map. Right-click: Go. Ctrl-click: open it in the quest log."
local ZONE_HINT = "Click to open this zone's map."
local ROUTE_TIP = " Right-click for a Commander Orders route through every giver with an open quest here, nearest first."
local HEADER_TIP = "Every quest this character has done or can still do here counts toward 100%. Missed quests "
    .. "are listed but do not count; dailies, seasonal and optional quests and the other Aldor or Scryer side are "
    .. "left out here (the Zones tab lists them)."

-- ---------------------------------------------------------------------------
-- Ink
--
-- The drawer always sits on its own near-black panel, whatever skin the quest
-- log window wears, so it uses the window's dark-skin values and never the
-- parchment ones. State words come from the engine with a colour KEY; the map
-- of key to ink is this surface's business.
-- ---------------------------------------------------------------------------

local INK = {
    primary = { 0.92, 0.90, 0.86 },
    secondary = { 0.72, 0.70, 0.66 },
    faint = { 0.50, 0.50, 0.50 },
    title = { 1.00, 0.82, 0.30 },
}
local STATE_INK = {
    good = { 0.45, 0.85, 0.45 },
    open = { 1.00, 0.85, 0.35 },
    warn = { 0.95, 0.60, 0.30 },
    bad = { 0.95, 0.40, 0.35 },
    faint = INK.faint,
}
local BASE_COLOUR = { 0.04, 0.04, 0.05, 0.88 }
local FALLBACK_ACCENT = { 0.55, 0.65, 0.80 }

-- The console accent through the window's kit when the window exported one,
-- else steel. Read at draw time: the window file may load after this one in
-- a harness, and the player can change the console colour at any moment.
local function Accent()
    local kit = Q._kit
    if type(kit) == "table" and type(kit.Accent) == "function" then
        local ok, r, g, b = pcall(kit.Accent)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return FALLBACK_ACCENT[1], FALLBACK_ACCENT[2], FALLBACK_ACCENT[3]
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local EMPTY = {}

local S = {
    attached = false,
    drawer = nil, rows = {}, model = {}, offset = 0,
    width = DRAWER_W, open = false, hasContent = false,
    uiMapId = nil, areaId = nil, kind = nil, view = nil,
    headerName = nil, headerTotals = nil, headerPct = nil, breakdown = nil, message = nil, listText = nil,
    selected = nil, focusQuest = nil, pulseUntil = 0, pulseToken = 0, pendingScroll = nil,
    provider = nil, pool = nil, pinMixin = nil,
    redrawPending = false, refreshes = 0, lastError = nil,
    sessionCollapsed = nil,
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function DB()
    if type(CommanderQuestLogDB) == "table" then return CommanderQuestLogDB end
    return EMPTY
end

-- Default-true settings read as ~= false, default-false ones as == true, so a
-- saved table that predates these keys behaves exactly like the defaults
local function ModuleOn() return DB().EnableQuestLog ~= false end
local function DrawerWanted() return ModuleOn() and DB().MapDrawer ~= false end
local function DrawerOpen() return DB().MapDrawerOpen ~= false end
local function PinsWanted() return ModuleOn() and DB().MapPins ~= false end

-- The drawer's folds. A saved table that predates the key gets the default
-- (Done folded) written in, so a fold the player makes is kept.
local function Collapsed()
    local db = CommanderQuestLogDB
    if type(db) ~= "table" then
        S.sessionCollapsed = S.sessionCollapsed or { Done = true }
        return S.sessionCollapsed
    end
    if type(db.MapCollapsed) ~= "table" then db.MapCollapsed = { Done = true } end
    return db.MapCollapsed
end

local function Now()
    return (GetTime and GetTime()) or 0
end

-- An error inside a map hook must not take the map down with it: it is
-- reported (BugSack sees it) and the hook returns
local function Report(err)
    S.lastError = tostring(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
end

local function Guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then Report(err) end
    end
end

local function Adapter()
    local A = Q.Questie
    if type(A) == "table" then return A end
    return nil
end

local function Engine()
    local C = Q.Completion
    if type(C) == "table" and type(C.StateWord) == "function" then return C end
    return nil
end

-- "ABSENT" | "LOADING" | "READY" | "BROKEN", reason
local function QuestieState()
    local A = Adapter()
    if not (A and type(A.State) == "function") then return "ABSENT", nil end
    local ok, state, reason = pcall(A.State)
    if not ok then return "BROKEN", tostring(state) end
    return state, reason
end

local function MapShown()
    return (WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown()) and true or false
end

local function MapID()
    if WorldMapFrame and WorldMapFrame.GetMapID then return WorldMapFrame:GetMapID() end
    return nil
end

local function MapName(uiMapId)
    if C_Map and C_Map.GetMapInfo and type(uiMapId) == "number" then
        local ok, info = pcall(C_Map.GetMapInfo, uiMapId)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return "World Map"
end

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

local function SetIfChanged(fs, text)
    if fs._last ~= text then
        fs._last = text
        fs:SetText(text)
    end
end

local function SetInk(fs, colour, alpha)
    fs:SetTextColor(colour[1], colour[2], colour[3], alpha or 1)
end

local function Rotate(texture, angle)
    if texture.SetRotation then texture:SetRotation(angle) end
end

-- The window's chevron, drawn from two rotated bars (D11): pointing right
-- when shut, down when open. (point, x, y) place its centre. SetRotation
-- turns counter-clockwise, so +pi/4 draws "/" and -pi/4 "\": shut is "\"
-- over "/" (meeting on the right, ">"), open is "\" beside "/" ("v").
local function EnsureChevron(button)
    if button.chevron then return button.chevron end
    local chevron = { Quad(button, "OVERLAY"), Quad(button, "OVERLAY") }
    for _, bar in ipairs(chevron) do bar:SetSize(7, 2) end
    button.chevron = chevron
    return chevron
end

local function PointChevron(button, open, point, x, y)
    local chevron = EnsureChevron(button)
    local top, bottom = chevron[1], chevron[2]
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if open then
        top:SetPoint("CENTER", button, point, x - 2, y + 1.5)
        bottom:SetPoint("CENTER", button, point, x + 2.5, y + 1.5)
        Rotate(top, -math.pi / 4)
        Rotate(bottom, math.pi / 4)
    else
        top:SetPoint("CENTER", button, point, x, y + 2)
        bottom:SetPoint("CENTER", button, point, x, y - 2)
        Rotate(top, -math.pi / 4)
        Rotate(bottom, math.pi / 4)
    end
    local ink = INK.secondary
    for _, bar in ipairs(chevron) do
        bar:SetVertexColor(ink[1], ink[2], ink[3], 1)
        bar:Show()
    end
end

local function HideChevron(button)
    for _, bar in ipairs(button.chevron or EMPTY) do bar:Hide() end
end

-- "Watch Commander Relthorn \226\128\148 Hellfire Peninsula 87.4, 50.7"
local function GiverLine(label, giver)
    local where = giver.zoneName and (" \226\128\148 " .. giver.zoneName) or ""
    local coords = ""
    if type(giver.x) == "number" and type(giver.y) == "number" then
        coords = string.format(" %.1f, %.1f", giver.x, giver.y)
    end
    return label .. ": " .. (giver.name or "unknown") .. where .. coords
end

local function DifficultyInk(level)
    if type(Q.DifficultyColor) == "function" and type(level) == "number" and level > 0 then
        local r, g, b = Q.DifficultyColor(level, UnitLevel and UnitLevel("player") or nil)
        if type(r) == "number" then return { r, g, b } end
    end
    return INK.secondary
end

-- Reputation: the adapter's one line for a quest, in the words every surface
-- uses ("Reputation: +275 Honor Hold", "No reputation", and "(seen in game)"
-- when the calibration has watched it pay); nil without the rules, for a
-- quest Questie does not know, or with Show Reputation Everywhere off
local function RepText(questId)
    local A = Adapter()
    if DB().ShowRepEverywhere == false or not (A and type(A.RepLine) == "function") then return nil end
    local line, effects = A.RepLine(questId)
    if type(line) ~= "string" then return nil end
    local R = Q.Standing
    local text = (type(R) == "table" and line == R.NO_REPUTATION) and line or ("Reputation: " .. line)
    for _, effect in ipairs(type(effects) == "table" and effects or EMPTY) do
        if type(effect) == "table" and effect.observed then return text .. " (" .. OBSERVED_WORDS .. ")" end
    end
    return text
end

-- The row badge: the quest's biggest direct gain and the faction it is for
-- ("+275 HH", "0" for none or capped) and its ink, off the effects the zone
-- view's facts already carry. The tag is the Zones tab's (the catalogue's
-- RepTag, unique over the zone's factions), else the rules engine's own
-- abbreviation: "+550" alone made a Cenarion Circle quest look like the best
-- Honor Hold one. The Zones tab's row setting (ZoneRowRep) governs it too:
-- it is the same zone list.
local function RepTag(factionId)
    local catalogue = Q.Catalogue
    if type(catalogue) == "table" and type(catalogue.RepTag) == "function" then
        return catalogue.RepTag(S.view, factionId)
    end
    local R, A = Q.Standing, Adapter()
    local name = A and type(A.FactionName) == "function" and A.FactionName(factionId) or nil
    if type(R) == "table" and type(R.Abbrev) == "function" and type(name) == "string" then return R.Abbrev(name) end
    return nil
end

local function RepBadge(entry)
    local R = Q.Standing
    local effects = type(entry.fact) == "table" and entry.fact.repEffects or nil
    if DB().ShowRepEverywhere == false or DB().ZoneRowRep == false
        or not (type(R) == "table" and type(R.Primary) == "function" and type(effects) == "table") then
        return nil
    end
    local factionId, delta = R.Primary(effects)
    if not factionId or delta == 0 then return "0", INK.faint end
    local tag = RepTag(factionId)
    -- the catalogue's fit, so the drawer's 64-px badge reads whole as the tab's does
    local catalogue = Q.Catalogue
    local text
    if type(catalogue) == "table" and type(catalogue.RepBadgeText) == "function" then
        text = catalogue.RepBadgeText(R, delta, tag)
    else
        text = R.FormatRep(delta) .. (tag and (" " .. tag) or "")
    end
    if delta < 0 then return text, STATE_INK.bad end
    local r, g, b = Accent()
    return text, { r, g, b }
end

-- ---------------------------------------------------------------------------
-- The model
--
-- What the list shows, as plain rows: { kind = "HEADER" | "QUEST" | "ZONE" }.
-- Rebuilt from the view on every draw; the widgets below only paint it.
-- ---------------------------------------------------------------------------

local function ReadyFirst(a, b)
    if (a.ready and true or false) ~= (b.ready and true or false) then return a.ready and true or false end
    local la, lb = a.level or 0, b.level or 0
    if la ~= lb then return la < lb end
    local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
    if ta ~= tb then return ta < tb end
    return (a.id or 0) < (b.id or 0)
end

local function ZoneModel(view)
    local model, buckets = {}, {}
    local collapsed = Collapsed()
    -- view.entries arrive in level-then-name order from the engine
    for _, entry in ipairs(view.entries or EMPTY) do
        local status = entry.status
        if GROUP_OF_STATUS[status] then
            buckets[status] = buckets[status] or {}
            table.insert(buckets[status], entry)
        end
    end
    if buckets.LOG then table.sort(buckets.LOG, ReadyFirst) end
    for _, group in ipairs(ZONE_GROUPS) do
        local members = buckets[group.status]
        if members and #members > 0 then
            local folded = collapsed[group.title] and true or false
            model[#model + 1] = { kind = "HEADER", key = group.title, title = group.title,
                                  count = #members, collapsed = folded }
            if not folded then
                for _, entry in ipairs(members) do
                    model[#model + 1] = { kind = "QUEST", entry = entry }
                end
            end
        end
    end
    return model
end

-- "Done 62 \194\183 In log 4 \194\183 Open 9 \194\183 Locked 12": the four
-- counted buckets, which add up to the denominator
local function Breakdown(totals)
    local counts = totals.countedByStatus or totals.byStatus or EMPTY
    return table.concat({
        "Done " .. (counts.DONE or 0), "In log " .. (counts.LOG or 0),
        "Open " .. (counts.AVAILABLE or 0), "Locked " .. (counts.LOCKED or 0),
    }, " \194\183 ")
end

-- One callback identity for every request, so the adapter REPLACES the
-- running job instead of queueing a second one behind it. A summary lands
-- every 0.05 s while a continent counts; each landing redrawing the drawer
-- and re-acquiring every label pin was twenty full redraws a second, so the
-- landings are gathered into one redraw per SUMMARY_REDRAW_SECONDS.
local QueueRedraw    -- forward
local function FlushSummaries()
    S.summaryRedrawPending = false
    QueueRedraw()
end
local function OnSummary()
    if S.summaryRedrawPending then return end
    if C_Timer and C_Timer.After then
        S.summaryRedrawPending = true
        C_Timer.After(SUMMARY_REDRAW_SECONDS, Guarded(FlushSummaries))
    else
        QueueRedraw()
    end
end

local function RequestMissing(areaIds)
    local A = Adapter()
    if #areaIds > 0 and A and type(A.RequestSummaries) == "function" then
        A.RequestSummaries(areaIds, OnSummary)
    end
end

-- Each zone's last known summary, and the ids whose summary is not current
local function ContinentSummaries(A, zones)
    local summaries, missing = {}, {}
    for index, zone in ipairs(zones) do
        local current = A.ZoneSummary(zone.areaId)
        summaries[index] = current or A.ZoneSummary(zone.areaId, true)
        if not current then missing[#missing + 1] = zone.areaId end
    end
    return summaries, missing
end

local function DrawMessage(name, message)
    S.view, S.hasContent, S.model = nil, false, {}
    S.headerName, S.headerTotals, S.headerPct = name, "", nil
    S.breakdown, S.message, S.listText = nil, message, nil
end

local function DrawZone(view, areaId)
    local C, A = Engine(), Adapter()
    S.view, S.hasContent, S.message = view, true, nil
    S.headerName = view.name or (A and A.ZoneName(areaId)) or ""
    local totals = view.totals or EMPTY
    S.headerTotals = C and C.TotalsText(totals, true) or ""
    S.headerPct = totals.pct
    S.breakdown = Breakdown(totals)
    S.model = ZoneModel(view)
    S.listText = (#S.model == 0) and MSG_ONLY_UNCOUNTED or nil
end

local function DrawContinent(uiMapId)
    local C, A = Engine(), Adapter()
    local zones = A.ContinentZones(uiMapId) or EMPTY
    if #zones == 0 then return DrawMessage(MapName(uiMapId), MSG_NO_ZONES) end
    local summaries, missing = ContinentSummaries(A, zones)
    local model, counted, done = {}, 0, 0
    for index, zone in ipairs(zones) do
        local summary = summaries[index]
        if summary then
            counted = counted + (summary.counted or 0)
            done = done + (summary.done or 0)
        end
        model[#model + 1] = { kind = "ZONE", zone = zone, summary = summary }
    end
    S.view, S.hasContent, S.message, S.listText = nil, true, nil, nil
    S.headerName = MapName(uiMapId)
    local pct = counted > 0 and done / counted or nil
    S.headerTotals = C and C.TotalsText({ counted = counted, done = done, pct = pct }, true) or ""
    S.headerPct = pct
    local line = #zones .. (#zones == 1 and " zone" or " zones") .. " with quests"
    if #missing > 0 then line = line .. " \194\183 " .. #missing .. " still counting" end
    S.breakdown = line
    S.model = model
    RequestMissing(missing)
end

-- Decides what the drawer shows for the map on screen
local function DrawContent(state)
    local uiMapId = MapID()
    if uiMapId ~= S.uiMapId then S.offset = 0 end
    S.uiMapId = uiMapId
    if state ~= "READY" then
        S.kind, S.areaId = nil, nil
        return DrawMessage(MapName(uiMapId), state == "LOADING" and MSG_LOADING or MSG_BROKEN)
    end
    local A = Adapter()
    local areaId, kind = A.ZoneForMap(uiMapId)
    S.kind, S.areaId = kind, areaId
    if kind == "CONTINENT" then return DrawContinent(uiMapId) end
    if not areaId then return DrawMessage(MapName(uiMapId), MSG_NO_ZONE) end
    local view, err = A.ZoneView(areaId)
    if not view then
        return DrawMessage(A.ZoneName(areaId), err == "NO_QUESTS" and MSG_NO_QUESTS or MSG_UNAVAILABLE)
    end
    DrawZone(view, areaId)
end

-- ---------------------------------------------------------------------------
-- Layout
--
-- Every horizontal size comes from the drawer width this file chose, and the
-- list height from the container's: both are numbers already known here,
-- where the drawer's own GetHeight on two fresh anchors may not have resolved
-- yet in the frame it was re-pointed in.
-- ---------------------------------------------------------------------------

local function RowWidth()
    return S.width - 2 * PAD - SCROLL_GUTTER
end

-- The rows the open list holds, open or not: a Focus made while the drawer
-- is folded scrolls by this, so the quest is in view when it unfolds
local function ListRows()
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return 0 end
    local container = WorldMapFrame.ScrollContainer
    local height = (container.GetHeight and container:GetHeight() or 0) + INSET_TOP - INSET_BOTTOM
    local rows = math.floor((height - LIST_TOP - PAD) / ROW_H)
    return rows > 0 and rows or 0
end

local function VisibleRows()
    if not S.open then return 0 end
    return ListRows()
end

local function Relayout()
    local drawer = S.drawer
    if not (drawer and WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    local container = WorldMapFrame.ScrollContainer
    local maximized = WorldMapFrame.IsMaximized and WorldMapFrame:IsMaximized()
    S.width = maximized and DRAWER_W_MAXIMIZED or DRAWER_W
    S.open = S.hasContent and DrawerOpen()
    drawer:SetWidth(S.width)
    drawer:ClearAllPoints()
    drawer:SetPoint("TOPRIGHT", container, "TOPRIGHT", INSET_RIGHT, INSET_TOP)
    if S.open then
        drawer:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", INSET_RIGHT, INSET_BOTTOM)
    else
        drawer:SetHeight(STRIP_H)
    end
    local level = (container.GetFrameLevel and container:GetFrameLevel() or 0) + LEVEL_ABOVE_CONTAINER
    -- Over the map's own topmost pins too (the player arrow and party dots,
    -- the corpse, the flags: 2753-2757 on this build), whatever the container
    local manager = WorldMapFrame.GetPinFrameLevelsManager and WorldMapFrame:GetPinFrameLevelsManager()
    if manager and manager.GetValidFrameLevel then
        local ok, topmost = pcall(manager.GetValidFrameLevel, manager, "PIN_FRAME_LEVEL_TOPMOST")
        if ok and type(topmost) == "number" and topmost + LEVEL_ABOVE_PINS > level then
            level = topmost + LEVEL_ABOVE_PINS
        end
    end
    if level > LEVEL_CAP then level = LEVEL_CAP end
    drawer:SetFrameLevel(level)
    drawer.header:SetFrameLevel(level + 2)
    for _, row in ipairs(S.rows) do row:SetFrameLevel(level + 2) end
end

-- ---------------------------------------------------------------------------
-- Rows
--
-- One widget shape serves all three row kinds; each fill sets every region
-- it shows and hides the rest, and re-applies font colour every pass (D15),
-- because a pooled row was last something else.
-- ---------------------------------------------------------------------------

local OnRowClick, OnRowEnter    -- forward
local OnHeaderClick             -- forward (the strip is built before the actions)

local function OnRowLeave()
    if GameTooltip then GameTooltip:Hide() end
end

local function AcquireRow(index)
    local row = S.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, S.drawer)
    row:SetHeight(ROW_H)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row.band = Quad(row, "BACKGROUND")
    row.band:SetAllPoints(row)
    row.hover = Quad(row, "HIGHLIGHT")
    row.hover:SetAllPoints(row)
    row.hover:SetVertexColor(1, 1, 1, 0.06)
    row.strip = Quad(row, "ARTWORK")
    row.strip:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.strip:SetSize(3, ROW_H - 4)
    row.level = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.level:SetWidth(LEVEL_W)
    if row.level.SetJustifyH then row.level:SetJustifyH("RIGHT") end
    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    if row.title.SetJustifyH then row.title:SetJustifyH("LEFT") end
    if row.title.SetWordWrap then row.title:SetWordWrap(false) end
    row.state = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.state:SetWidth(STATE_W)
    if row.state.SetJustifyH then row.state:SetJustifyH("RIGHT") end
    row.barBg = Quad(row, "ARTWORK")
    row.barFill = Quad(row, "OVERLAY")
    row:SetScript("OnClick", Guarded(function(self, button) OnRowClick(self, button) end))
    row:SetScript("OnEnter", Guarded(function(self) OnRowEnter(self) end))
    row:SetScript("OnLeave", OnRowLeave)
    if S.drawer.GetFrameLevel then row:SetFrameLevel(S.drawer:GetFrameLevel() + 2) end
    S.rows[index] = row
    return row
end

local function PlaceTitle(row, x, y, rightReserve)
    row.title:ClearAllPoints()
    row.title:SetPoint("LEFT", row, "LEFT", x, y)
    row.title:SetWidth(math.max(10, RowWidth() - x - rightReserve))
end

local function PlaceState(row, y)
    row.state:ClearAllPoints()
    row.state:SetPoint("RIGHT", row, "RIGHT", 0, y)
end

local function HideBadge(row)
    if row.badge then row.badge:Hide() end
end

-- The reputation badge left of the state word, maximized only; returns the
-- width it takes from the title (0 without one)
local function PlaceBadge(row, entry)
    local text, ink
    if S.width == DRAWER_W_MAXIMIZED then text, ink = RepBadge(entry) end
    if not text then
        HideBadge(row)
        return 0
    end
    if not row.badge then
        row.badge = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        if row.badge.SetJustifyH then row.badge:SetJustifyH("RIGHT") end
        if row.badge.SetWordWrap then row.badge:SetWordWrap(false) end
    end
    local badge = row.badge
    -- measured unconstrained (a width of 0 is "as wide as the text"), as the
    -- catalogue measures its badges, then held to the cap
    badge:SetWidth(0)
    SetIfChanged(badge, text)
    SetInk(badge, ink)
    local natural = (badge.GetUnboundedStringWidth and badge:GetUnboundedStringWidth())
        or (badge.GetStringWidth and badge:GetStringWidth()) or 0
    local width = math.min(math.ceil(natural), BADGE_MAX_W)
    badge:SetWidth(width)
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", row, "RIGHT", -(STATE_W + BADGE_GAP), 0)
    badge:Show()
    return width + BADGE_GAP
end

local function FillQuest(row, entry)
    local C = Engine()
    local word, key = "", "faint"
    if C then word, key = C.StateWord(entry) end
    local ink = STATE_INK[key] or INK.faint
    HideChevron(row)
    row.barBg:Hide()
    row.barFill:Hide()
    row.strip:SetColorTexture(ink[1], ink[2], ink[3], 0.9)
    row.strip:Show()
    local level = tonumber(entry.level)
    SetIfChanged(row.level, (level and level > 0) and tostring(level) or "")
    SetInk(row.level, DifficultyInk(level))
    row.level:Show()
    PlaceTitle(row, 4 + LEVEL_W + 4, 0, STATE_W + 4 + PlaceBadge(row, entry))
    SetIfChanged(row.title, entry.title or "")
    -- Dimmed by counted, not by bucket: an exclusive slot's other members
    -- keep their bucket and stop counting
    SetInk(row.title, entry.counted and INK.primary or INK.faint)
    row.title:Show()
    PlaceState(row, 0)
    SetIfChanged(row.state, word or "")
    SetInk(row.state, ink)
    row.state:Show()
    if S.selected and entry.id == S.selected then
        local r, g, b = Accent()
        row.band:SetColorTexture(r, g, b, 0.22)
        row.band:Show()
    else
        row.band:Hide()
    end
end

local function FillHeader(row, item)
    HideBadge(row)
    row.strip:Hide()
    row.level:Hide()
    row.band:Hide()
    row.barBg:Hide()
    row.barFill:Hide()
    PointChevron(row, not item.collapsed, "LEFT", 6, 0)
    PlaceTitle(row, 14, 0, STATE_W + 4)
    SetIfChanged(row.title, item.title or "")
    SetInk(row.title, INK.secondary)
    row.title:Show()
    PlaceState(row, 0)
    SetIfChanged(row.state, tostring(item.count or 0))
    SetInk(row.state, INK.faint)
    row.state:Show()
end

local function FillZone(row, item)
    local C = Engine()
    local summary = item.summary
    HideChevron(row)
    HideBadge(row)
    row.strip:Hide()
    row.level:Hide()
    row.band:Hide()
    PlaceTitle(row, 4, 2, STATE_W + 4)
    SetIfChanged(row.title, item.zone.name or "")
    SetInk(row.title, INK.primary)
    row.title:Show()
    PlaceState(row, 2)
    if summary then
        SetIfChanged(row.state, C and C.PercentText(summary.pct) or "")
        SetInk(row.state, INK.primary)
    else
        SetIfChanged(row.state, "...")
        SetInk(row.state, INK.faint)
    end
    row.state:Show()
    local width = RowWidth() - 4
    row.barBg:ClearAllPoints()
    row.barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 1)
    row.barBg:SetSize(width, 3)
    row.barBg:SetColorTexture(1, 1, 1, 0.10)
    row.barBg:Show()
    local pct = summary and summary.pct
    if type(pct) == "number" and pct > 0 then
        local r, g, b = Accent()
        row.barFill:ClearAllPoints()
        row.barFill:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 1)
        row.barFill:SetSize(math.max(1, width * math.min(pct, 1)), 3)
        row.barFill:SetColorTexture(r, g, b, 0.9)
        row.barFill:Show()
    else
        row.barFill:Hide()
    end
end

local function RenderScroll(visible, total)
    local drawer = S.drawer
    local track, thumb = drawer.track, drawer.thumb
    if not S.open or visible == 0 or total <= visible then
        track:Hide()
        thumb:Hide()
        return
    end
    local listH = visible * ROW_H
    local thumbH = math.max(10, math.floor(listH * visible / total))
    local maxOffset = total - visible
    local y = math.floor((listH - thumbH) * (S.offset / maxOffset) + 0.5)
    track:ClearAllPoints()
    track:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -2, -LIST_TOP)
    track:SetSize(2, listH)
    track:SetColorTexture(1, 1, 1, 0.08)
    track:Show()
    local r, g, b = Accent()
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", -2, -(LIST_TOP + y))
    thumb:SetSize(2, thumbH)
    thumb:SetColorTexture(r, g, b, 0.8)
    thumb:Show()
end

local function RenderList()
    local drawer = S.drawer
    if not drawer then return end
    local visible = VisibleRows()
    local total = #S.model
    local maxOffset = math.max(0, total - visible)
    if S.offset > maxOffset then S.offset = maxOffset end
    if S.offset < 0 then S.offset = 0 end
    local shown = 0
    for i = 1, visible do
        local item = S.model[S.offset + i]
        if not item then break end
        local row = AcquireRow(i)
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", drawer, "TOPLEFT", PAD, -(LIST_TOP + (i - 1) * ROW_H))
        row:SetWidth(RowWidth())
        if item.kind == "QUEST" then
            FillQuest(row, item.entry)
        elseif item.kind == "HEADER" then
            FillHeader(row, item)
        else
            FillZone(row, item)
        end
        row:Show()
        shown = i
    end
    for i = shown + 1, #S.rows do
        S.rows[i]:Hide()
        S.rows[i].item = nil
    end
    RenderScroll(visible, total)
    local listMessage = drawer.listMessage
    if S.open and S.listText then
        SetIfChanged(listMessage, S.listText)
        SetInk(listMessage, INK.faint)
        listMessage:Show()
    else
        listMessage:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- The drawer
-- ---------------------------------------------------------------------------

local function Render()
    local drawer = S.drawer
    if not drawer then return end
    Relayout()
    local header = drawer.header
    local r, g, b = Accent()
    drawer.base:SetColorTexture(BASE_COLOUR[1], BASE_COLOUR[2], BASE_COLOUR[3], BASE_COLOUR[4])
    for _, edge in ipairs(drawer.edges) do edge:SetColorTexture(r, g, b, 0.35) end

    SetIfChanged(header.name, S.headerName or "")
    SetInk(header.name, INK.title)
    SetIfChanged(header.totals, S.headerTotals or "")
    SetInk(header.totals, INK.primary)
    if S.message then
        SetIfChanged(header.message, S.message)
        SetInk(header.message, INK.faint)
        header.message:Show()
        header.barBg:Hide()
        header.barFill:Hide()
        HideChevron(header)
    else
        header.message:Hide()
        local width = S.width - 16
        header.barBg:SetSize(width, 3)
        header.barBg:SetColorTexture(1, 1, 1, 0.10)
        header.barBg:Show()
        local pct = S.headerPct
        if type(pct) == "number" and pct > 0 then
            header.barFill:SetSize(math.max(1, width * math.min(pct, 1)), 3)
            header.barFill:SetColorTexture(r, g, b, 0.9)
            header.barFill:Show()
        else
            header.barFill:Hide()
        end
        PointChevron(header, S.open, "TOPLEFT", 9, -11)
    end

    local breakdown = drawer.breakdown
    if S.open and S.breakdown then
        SetIfChanged(breakdown, S.breakdown)
        SetInk(breakdown, INK.secondary)
        breakdown:Show()
    else
        breakdown:Hide()
    end
    RenderList()
end

local function ToggleOpen()
    if not S.hasContent then return end
    local db = CommanderQuestLogDB
    if type(db) ~= "table" then return end
    db.MapDrawerOpen = not DrawerOpen()
    Render()
end

local function OnWheel(_, delta)
    if not S.open or type(delta) ~= "number" then return end
    S.offset = S.offset - delta * WHEEL_ROWS
    RenderList()
end

local function BuildDrawer()
    if S.drawer then return S.drawer end
    if not (CreateFrame and WorldMapFrame and WorldMapFrame.ScrollContainer) then return nil end
    local drawer = CreateFrame("Frame", DRAWER_NAME, WorldMapFrame)
    -- A click on the panel must not fall through to the canvas (which would
    -- navigate the map), and the wheel scrolls the list, not the map zoom
    drawer:EnableMouse(true)
    if drawer.EnableMouseWheel then drawer:EnableMouseWheel(true) end
    drawer:SetScript("OnMouseWheel", Guarded(OnWheel))

    drawer.base = Quad(drawer, "BACKGROUND")
    drawer.base:SetAllPoints(drawer)
    local top, bottom = Quad(drawer, "BORDER"), Quad(drawer, "BORDER")
    local left, right = Quad(drawer, "BORDER"), Quad(drawer, "BORDER")
    top:SetPoint("TOPLEFT", drawer, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", drawer, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", drawer, "BOTTOMLEFT", 0, 0)
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", drawer, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(1)
    drawer.edges = { top, bottom, left, right }

    local header = CreateFrame("Button", nil, drawer)
    header:SetPoint("TOPLEFT", drawer, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", drawer, "TOPRIGHT", 0, 0)
    header:SetHeight(STRIP_H)
    if header.RegisterForClicks then header:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    header:SetScript("OnClick", Guarded(function(self, button) OnHeaderClick(self, button) end))
    header.totals = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    header.totals:SetPoint("TOPRIGHT", header, "TOPRIGHT", -8, -7)
    if header.totals.SetJustifyH then header.totals:SetJustifyH("RIGHT") end
    header.name = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header.name:SetPoint("TOPLEFT", header, "TOPLEFT", 18, -5)
    header.name:SetPoint("RIGHT", header.totals, "LEFT", -6, 0)
    if header.name.SetJustifyH then header.name:SetJustifyH("LEFT") end
    if header.name.SetWordWrap then header.name:SetWordWrap(false) end
    header.message = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    header.message:SetPoint("TOPLEFT", header, "TOPLEFT", 18, -18)
    header.message:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    if header.message.SetJustifyH then header.message:SetJustifyH("LEFT") end
    if header.message.SetWordWrap then header.message:SetWordWrap(false) end
    header.barBg = Quad(header, "ARTWORK")
    header.barBg:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 4)
    header.barFill = Quad(header, "OVERLAY")
    header.barFill:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 8, 4)
    EnsureChevron(header)
    if Commander and Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(header, "Zone completion", function()
            local route = (S.areaId and S.kind and S.kind ~= "CONTINENT") and ROUTE_TIP or ""
            if not S.hasContent then return HEADER_TIP .. route end
            return HEADER_TIP .. (S.open and " Click to fold the list away." or " Click to show the list.") .. route
        end, "ANCHOR_LEFT")
    end
    drawer.header = header

    drawer.breakdown = drawer:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    drawer.breakdown:SetPoint("TOPLEFT", drawer, "TOPLEFT", PAD + 2, -(STRIP_H + 2))
    drawer.breakdown:SetPoint("RIGHT", drawer, "RIGHT", -PAD, 0)
    if drawer.breakdown.SetJustifyH then drawer.breakdown:SetJustifyH("LEFT") end
    if drawer.breakdown.SetWordWrap then drawer.breakdown:SetWordWrap(false) end
    drawer.listMessage = drawer:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    drawer.listMessage:SetPoint("TOPLEFT", drawer, "TOPLEFT", PAD + 2, -(LIST_TOP + 4))
    drawer.listMessage:SetPoint("RIGHT", drawer, "RIGHT", -PAD, 0)
    if drawer.listMessage.SetJustifyH then drawer.listMessage:SetJustifyH("LEFT") end
    drawer.track = Quad(drawer, "ARTWORK")
    drawer.thumb = Quad(drawer, "OVERLAY")
    drawer.track:Hide()
    drawer.thumb:Hide()

    S.drawer = drawer
    return drawer
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

-- The finisher when the quest is ready to hand in, else the best starter
local function WaypointTo(entry)
    local A = Adapter()
    if not (A and entry) then return nil end
    local target
    if entry.status == "LOG" and entry.ready then target = A.Finisher(entry.id) end
    if not (target and target.x) then target = A.BestStarter(entry, S.areaId) or target end
    target = target or EMPTY
    return A.Waypoint({
        title = entry.title, areaId = target.areaId or S.areaId, uiMapId = target.uiMapId,
        x = target.x, y = target.y, zoneName = target.zoneName, questId = entry.id, spawns = target.spawns,
    })
end

-- Right-click on the header strip: the shown zone's open quests as one
-- Commander Orders route (the adapter builds it and says how it went). A
-- continent has no zone to route, so nothing happens there.
local function Routable()
    return S.areaId ~= nil and S.kind ~= nil and S.kind ~= "CONTINENT"
end

local function RouteZone()
    local A = Adapter()
    if not (A and A.RouteOpen and Routable()) then return nil end
    return A.RouteOpen(S.areaId)
end

function OnHeaderClick(_, button)
    if button == "RightButton" then
        RouteZone()
    else
        ToggleOpen()
    end
end

-- The window is HIGH strata and the maximized map FULLSCREEN: the map has to
-- go first or the window opens underneath it. Out of combat only: there
-- HideUIPanel from addon code is refused (CheckProtectedFunctionsAllowed) and
-- the chat says an AddOn was blocked, once. The window still opens, with a
-- line saying how to see it -- the player's own M is a secure key.
local function OpenInLog(entry)
    local areaId = S.areaId
    if InCombatLockdown and InCombatLockdown() then
        print("Commander Quest Log: the map is not closed from here in combat; close it (M) to see the quest log.")
    elseif HideUIPanel and WorldMapFrame then
        HideUIPanel(WorldMapFrame)
    end
    if type(CommanderQuestLog_OpenToZone) == "function" then
        CommanderQuestLog_OpenToZone(areaId, entry.id)
    else
        print("Commander Quest Log: the quest log window is not loaded.")
    end
end

local function ToggleGroup(key)
    local collapsed = Collapsed()
    collapsed[key] = not collapsed[key]
    if S.view then S.model = ZoneModel(S.view) end
    RenderList()
end

local function GoToZone(zone)
    if zone and zone.uiMapId and WorldMapFrame and WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(zone.uiMapId)
    end
end

local function QuestTooltip(owner, entry)
    local C, A = Engine(), Adapter()
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    local level = tonumber(entry.level)
    local title = (level and level > 0) and ("[" .. level .. "] " .. (entry.title or "")) or (entry.title or "")
    GameTooltip:SetText(title, INK.title[1], INK.title[2], INK.title[3])
    if C then
        local reason = C.Reason(entry, A and A.Character() or {}, S.view)
        if reason and reason ~= "" then
            GameTooltip:AddLine(reason, INK.primary[1], INK.primary[2], INK.primary[3], true)
        end
    end
    local giver = A and A.BestStarter(entry, S.areaId)
    if giver then
        GameTooltip:AddLine(GiverLine("Starts", giver), INK.secondary[1], INK.secondary[2], INK.secondary[3], true)
    elseif entry.startZoneName then
        GameTooltip:AddLine("Starts in " .. entry.startZoneName,
            INK.secondary[1], INK.secondary[2], INK.secondary[3], true)
    end
    local rep = RepText(entry.id)
    if rep then GameTooltip:AddLine(rep, INK.primary[1], INK.primary[2], INK.primary[3], true) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ROW_HINT, INK.faint[1], INK.faint[2], INK.faint[3], true)
    GameTooltip:Show()
end

local function ZoneTooltip(owner, item)
    local C = Engine()
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText(item.zone.name or "", INK.title[1], INK.title[2], INK.title[3])
    if item.summary and C then
        GameTooltip:AddLine(C.TotalsText(item.summary, true) .. " of the quests that count",
            INK.primary[1], INK.primary[2], INK.primary[3], true)
    else
        GameTooltip:AddLine("Still counting...", INK.faint[1], INK.faint[2], INK.faint[3], true)
    end
    GameTooltip:AddLine(ZONE_HINT, INK.faint[1], INK.faint[2], INK.faint[3], true)
    GameTooltip:Show()
end

function OnRowEnter(row)
    local item = row.item
    if not (item and GameTooltip) then return end
    if item.kind == "QUEST" then
        QuestTooltip(row, item.entry)
    elseif item.kind == "ZONE" then
        ZoneTooltip(row, item)
    end
end

function OnRowClick(row, button)
    local item = row.item
    if not item then return end
    if item.kind == "HEADER" then
        ToggleGroup(item.key)
    elseif item.kind == "ZONE" then
        GoToZone(item.zone)
    elseif item.kind == "QUEST" then
        if button == "RightButton" then
            WaypointTo(item.entry)
        elseif IsControlKeyDown and IsControlKeyDown() then
            OpenInLog(item.entry)
        else
            M.Focus(item.entry.id)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Pins
--
-- Our own MapCanvasDataProvider, built the way HereBeDragons builds Questie's.
-- The map calls the provider's RefreshAllData on every map change and every
-- show; we call it too when the numbers move. Each giver pin is ONE spot from
-- the adapter's PinsFor (spawns already merged and capped there), carrying the
-- quests at that spot whose status is switched on.
-- ---------------------------------------------------------------------------

local function PinLook(entry, db, A)
    -- Questie draws its own icon for these; ours would stack on it
    if A.IsQuestieDrawing(entry.id) then return nil end
    local status = entry.status
    if status == "LOCKED" then return db.MapPinsLocked ~= false and "LOCKED" or nil end
    if status == "AVAILABLE" then return db.MapPinsAvailable ~= false and "AVAILABLE" or nil end
    if status == "DONE" then return db.MapPinsDone == true and "DONE" or nil end
    if status == "MISSED" then return db.MapPinsMissed == true and "MISSED" or nil end
    return nil
end

-- A focused quest is drawn whatever the filters say, for as long as it pulses
local function FocusLook(entry)
    local status = entry.status
    if status == "DONE" or status == "MISSED" or status == "LOCKED" then return status end
    return "AVAILABLE"
end

local function Focusing()
    return S.focusQuest ~= nil and Now() < S.pulseUntil
end

local function AddGiverPins(map, areaId, uiMapId, A)
    local db = DB()
    local focus = Focusing() and S.focusQuest or nil
    for _, group in ipairs(A.PinsFor(areaId, uiMapId) or EMPTY) do
        local kept, best, focused = {}, nil, false
        for _, entry in ipairs(group.quests or EMPTY) do
            local look = PinLook(entry, db, A)
            if focus and entry.id == focus then
                look = look or FocusLook(entry)
                focused = true
            end
            if look then
                kept[#kept + 1] = entry
                if not best or LOOKS[look].rank > LOOKS[best].rank then best = look end
            end
        end
        if best then
            map:AcquirePin(PIN_TEMPLATE, {
                kind = "GIVER", x = group.x, y = group.y, look = best, quests = kept,
                name = group.name, areaId = areaId, focused = focused,
            })
        end
    end
end

-- One "69%" per zone with a summary, at the centre of the zone's rectangle
-- on the continent; the missing ones are asked for and arrive as a redraw
local function AddLabelPins(map, uiMapId, A)
    local C = Engine()
    local zones = A.ContinentZones(uiMapId) or EMPTY
    local summaries, missing = ContinentSummaries(A, zones)
    RequestMissing(missing)
    if not (C and C_Map and C_Map.GetMapRectOnMap) then return end
    for index, zone in ipairs(zones) do
        local summary = summaries[index]
        if summary and (summary.counted or 0) > 0 and zone.uiMapId then
            local ok, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, zone.uiMapId, uiMapId)
            if ok and type(left) == "number" and type(right) == "number"
                and type(top) == "number" and type(bottom) == "number" then
                map:AcquirePin(PIN_TEMPLATE, {
                    kind = "LABEL", x = (left + right) / 2, y = (top + bottom) / 2,
                    text = C.PercentText(summary.pct), name = zone.name, summary = summary,
                })
            end
        end
    end
end

local function RefreshProviderPins(provider)
    local map = (provider.GetMap and provider:GetMap()) or WorldMapFrame
    if not (map and map.RemoveAllPinsByTemplate and map.AcquirePin and map.GetMapID) then return end
    map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
    if not PinsWanted() or QuestieState() ~= "READY" then return end
    local A = Adapter()
    local uiMapId = map:GetMapID()
    local areaId, kind = A.ZoneForMap(uiMapId)
    if kind == "CONTINENT" then
        if DB().MapZoneLabels ~= false then AddLabelPins(map, uiMapId, A) end
    elseif areaId then
        AddGiverPins(map, areaId, uiMapId, A)
    end
end

local function RefreshPins()
    if S.provider and S.provider.RefreshAllData then S.provider:RefreshAllData() end
end

-- The focus ring: four accent bars round the pin, breathing until the pulse
-- runs out
local function StopRing(pin)
    for _, bar in ipairs(pin.ring or EMPTY) do bar:Hide() end
    if pin.SetScript then pin:SetScript("OnUpdate", nil) end
end

local function RingUpdate(pin)
    local now = Now()
    if now >= S.pulseUntil then
        StopRing(pin)
        return
    end
    local alpha = 0.35 + 0.65 * math.abs(math.sin((S.pulseUntil - now) * 5))
    for _, bar in ipairs(pin.ring or EMPTY) do bar:SetAlpha(alpha) end
end

local function StartRing(pin)
    local r, g, b = Accent()
    for _, bar in ipairs(pin.ring) do
        bar:SetColorTexture(r, g, b, 1)
        bar:SetAlpha(1)
        bar:Show()
    end
    pin:SetScript("OnUpdate", RingUpdate)
end

local function EnsurePinRegions(pin)
    if pin.icon then return end
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetAllPoints(pin)
    pin.labelBg = Quad(pin, "BACKGROUND")
    pin.labelBg:SetAllPoints(pin)
    pin.label = pin:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pin.label:SetPoint("CENTER", pin, "CENTER", 0, 0)
    local top, bottom = Quad(pin, "OVERLAY"), Quad(pin, "OVERLAY")
    local left, right = Quad(pin, "OVERLAY"), Quad(pin, "OVERLAY")
    top:SetPoint("BOTTOMLEFT", pin, "TOPLEFT", -3, 1)
    top:SetPoint("BOTTOMRIGHT", pin, "TOPRIGHT", 3, 1)
    top:SetHeight(2)
    bottom:SetPoint("TOPLEFT", pin, "BOTTOMLEFT", -3, -1)
    bottom:SetPoint("TOPRIGHT", pin, "BOTTOMRIGHT", 3, -1)
    bottom:SetHeight(2)
    left:SetPoint("TOPRIGHT", pin, "TOPLEFT", -1, 3)
    left:SetPoint("BOTTOMRIGHT", pin, "BOTTOMLEFT", -1, -3)
    left:SetWidth(2)
    right:SetPoint("TOPLEFT", pin, "TOPRIGHT", 1, 3)
    right:SetPoint("BOTTOMLEFT", pin, "BOTTOMRIGHT", 1, -3)
    right:SetWidth(2)
    pin.ring = { top, bottom, left, right }
    StopRing(pin)
end

local function PinEnter(pin) if pin.OnMouseEnter then pin:OnMouseEnter() end end
local function PinLeave(pin) if pin.OnMouseLeave then pin:OnMouseLeave() end end

-- Motion only: the tooltip shows, a click still lands on the map. When the
-- map has already wired its own OnEnter for the pin, that one stays.
local function EnsurePinMouse(pin)
    if pin._mouse then return end
    pin._mouse = true
    if pin.SetMouseMotionEnabled and pin.SetMouseClickEnabled then
        pin:SetMouseMotionEnabled(true)
        pin:SetMouseClickEnabled(false)
    elseif pin.EnableMouse then
        pin:EnableMouse(true)
    end
    if pin:GetScript("OnEnter") == nil then pin:SetScript("OnEnter", PinEnter) end
    if pin:GetScript("OnLeave") == nil then pin:SetScript("OnLeave", PinLeave) end
end

local function PinTooltip(pin)
    local data = pin.data
    if not (data and GameTooltip) then return end
    local C, A = Engine(), Adapter()
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    if data.kind == "LABEL" then
        GameTooltip:SetText(data.name or "", INK.title[1], INK.title[2], INK.title[3])
        if C and data.summary then
            GameTooltip:AddLine(C.TotalsText(data.summary, true) .. " of the quests that count",
                INK.primary[1], INK.primary[2], INK.primary[3], true)
        end
        GameTooltip:Show()
        return
    end
    GameTooltip:SetText(data.name or "Quest giver", INK.title[1], INK.title[2], INK.title[3])
    local char = A and A.Character() or {}
    local view = A and data.areaId and A.ZoneView(data.areaId) or nil
    for index, entry in ipairs(data.quests or EMPTY) do
        if index > TOOLTIP_QUEST_CAP then
            GameTooltip:AddLine(string.format("and %d more", #data.quests - TOOLTIP_QUEST_CAP),
                INK.faint[1], INK.faint[2], INK.faint[3])
            break
        end
        local word, key = "", "faint"
        if C then word, key = C.StateWord(entry) end
        local ink = STATE_INK[key] or INK.faint
        GameTooltip:AddDoubleLine(entry.title or "", word or "", INK.primary[1], INK.primary[2], INK.primary[3],
            ink[1], ink[2], ink[3])
        if C then
            local reason = C.Reason(entry, char, view)
            if reason and reason ~= "" then
                GameTooltip:AddLine(reason, INK.secondary[1], INK.secondary[2], INK.secondary[3], true)
            end
        end
        local rep = RepText(entry.id)
        if rep then GameTooltip:AddLine(rep, INK.secondary[1], INK.secondary[2], INK.secondary[3], true) end
    end
    GameTooltip:Show()
end

local function NewPinMixin()
    local mixin = CreateFromMixins(MapCanvasPinMixin)

    -- Idempotent: AcquirePin may or may not call it on this build
    function mixin:OnLoad()
        self._loaded = true
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        self:SetScalingLimits(1, 1.0, 1.2)
    end

    function mixin:OnAcquired(data)
        if not self._loaded then self:OnLoad() end
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
        EnsurePinRegions(self)
        EnsurePinMouse(self)
        self.data = data
        if data.kind == "LABEL" then
            self.icon:Hide()
            StopRing(self)
            SetIfChanged(self.label, data.text or "")
            SetInk(self.label, INK.primary)
            self.label:Show()
            self:SetSize((self.label:GetStringWidth() or 20) + 8, 14)
            self.labelBg:SetColorTexture(BASE_COLOUR[1], BASE_COLOUR[2], BASE_COLOUR[3], 0.75)
            self.labelBg:Show()
        else
            local look = LOOKS[data.look] or LOOKS.LOCKED
            self.label:Hide()
            self.labelBg:Hide()
            self:SetSize(look.size, look.size)
            self.icon:SetTexture(look.texture)
            local tint = look.tint or WHITE
            self.icon:SetVertexColor(tint[1], tint[2], tint[3])
            self.icon:SetAlpha(look.alpha or 1)
            self.icon:Show()
            if data.focused and Focusing() then StartRing(self) else StopRing(self) end
        end
        self:SetPosition(data.x, data.y)
    end

    function mixin:OnReleased()
        StopRing(self)
        self.data = nil
    end

    function mixin:OnMouseEnter() PinTooltip(self) end
    function mixin:OnMouseLeave() if GameTooltip then GameTooltip:Hide() end end

    -- A pulsing giver is drawn over the drawer for as long as it pulses: the
    -- open drawer covers the map's east quarter, and a ring pulsing under it
    -- is a click that did nothing. EndPulse re-acquires the pins, which puts
    -- this one back at its own level.
    function mixin:ApplyFrameLevel()
        if MapCanvasPinMixin.ApplyFrameLevel then MapCanvasPinMixin.ApplyFrameLevel(self) end
        local drawer = S.drawer
        if self.data and self.data.focused and Focusing() and drawer and drawer:IsShown() and drawer.GetFrameLevel then
            self:SetFrameLevel(math.min(drawer:GetFrameLevel() + LEVEL_PULSE, LEVEL_CAP + LEVEL_PULSE))
        end
    end

    -- HereBeDragons' fix for an in-combat error when the map sets pass-through
    -- buttons on its pins; whether this build protects it is unknown
    mixin.SetPassThroughButtons = function() end
    return mixin
end

local function CreatePin()
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(1, 1)
    return Mixin(pin, S.pinMixin)
end

local function ResetPin(_, pin)
    pin:Hide()
    pin:ClearAllPoints()
    if pin.OnReleased then pin:OnReleased() end
    pin.pinTemplate = nil
    pin.owningMap = nil
end

-- CreateFramePool's postCreate: the mixin for a pool that will not take our
-- creation function (2.5.6's secure pool is a proxy that ignores the write)
local function MixPin(pin)
    pin:SetSize(1, 1)
    Mixin(pin, S.pinMixin)
end

local function BuildProvider()
    if S.provider then return true end
    if not (WorldMapFrame and type(WorldMapFrame.pinPools) == "table" and WorldMapFrame.AddDataProvider
        and WorldMapFrame.GetCanvas) then
        return false
    end
    if not (type(MapCanvasDataProviderMixin) == "table" and type(MapCanvasPinMixin) == "table"
        and CreateFromMixins and Mixin and (CreateUnsecuredRegionPoolInstance or CreateFramePool)) then
        return false
    end
    S.pinMixin = NewPinMixin()
    local canvas = WorldMapFrame:GetCanvas()
    -- HBD's route on this client: the unsecured pool, whose fields are read.
    -- The secure CreateFramePool only where it is all there is, given the
    -- mixin through postCreate (its sixth argument) as well.
    local pool
    if CreateUnsecuredRegionPoolInstance then
        pool = CreateUnsecuredRegionPoolInstance(PIN_TEMPLATE)
    else
        pool = CreateFramePool("FRAME", canvas, nil, ResetPin, false, MixPin)
    end
    pool.parent = canvas
    -- Both generations of the pool's field names, as HBD sets them
    pool.createFunc, pool.creationFunc = CreatePin, CreatePin
    pool.resetFunc, pool.resetterFunc = ResetPin, ResetPin
    WorldMapFrame.pinPools[PIN_TEMPLATE] = pool

    local provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData()
        local map = self:GetMap()
        if map and map.RemoveAllPinsByTemplate then map:RemoveAllPinsByTemplate(PIN_TEMPLATE) end
    end
    function provider:RefreshAllData()
        local ok, err = pcall(RefreshProviderPins, self)
        if not ok then Report(err) end
    end
    S.provider, S.pool = provider, pool
    WorldMapFrame:AddDataProvider(provider)
    return true
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

-- Unfolds the quest's group when it is folded, and scrolls it to mid-list.
-- Answers false for a quest the drawer has no row for (a daily, an extra, the
-- other faction's: the five groups leave those to the Zones tab).
local function ScrollTo(questId)
    local view = S.view
    local entry = view and view.byId and view.byId[questId]
    if not entry then return false end
    local group = GROUP_OF_STATUS[entry.status]
    if not group then
        Render()
        return false
    end
    local collapsed = Collapsed()
    if collapsed[group] then
        collapsed[group] = false
        S.model = ZoneModel(view)
    end
    for index, item in ipairs(S.model) do
        if item.kind == "QUEST" and item.entry.id == questId then
            -- Sized by the OPEN list, folded or not, so a quest focused
            -- while the drawer is shut is in view when it opens
            S.offset = math.max(0, index - math.ceil(ListRows() / 2))
            break
        end
    end
    Render()
    return true
end

-- withPins is false only from the map-change hook: the map has already
-- handed the change to every provider (ours included) before a post-hook runs
local function RefreshAll(withPins)
    if not (S.attached and MapShown()) then return end
    local state = QuestieState()
    if state == "ABSENT" then
        if S.drawer then S.drawer:Hide() end
        return
    end
    S.refreshes = S.refreshes + 1
    local added = not S.provider and BuildProvider()
    if DrawerWanted() then
        if BuildDrawer() then
            S.drawer:Show()
            DrawContent(state)
            Render()
            -- A Focus that arrived while the map was closed
            if S.pendingScroll then
                local pending = S.pendingScroll
                S.pendingScroll = nil
                ScrollTo(pending)
            end
        end
    elseif S.drawer then
        S.drawer:Hide()
    end
    if withPins or added then RefreshPins() end
end

function M.Refresh()
    RefreshAll(true)
end

local function RunRedraw()
    S.redrawPending = false
    M.Refresh()
end

-- Many things move the numbers in one burst (a turn-in bumps the generation,
-- a summary lands, a setting flips); the drawer redraws once, next frame
function QueueRedraw()
    if S.redrawPending then return end
    S.redrawPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, Guarded(RunRedraw))
    else
        RunRedraw()
    end
end

-- ---------------------------------------------------------------------------
-- Focus
-- ---------------------------------------------------------------------------

local function EndPulse(token)
    if token ~= S.pulseToken then return end
    S.focusQuest = nil
    if MapShown() then RefreshPins() end
end

-- Selects the quest in the drawer, scrolls to it and pulses its giver pin(s).
-- areaId (optional, an addition to the spec) is the zone the quest belongs
-- to: when the map shows another one it is moved there first.
function M.Focus(questId, areaId)
    questId = tonumber(questId)
    if not (questId and S.attached) then return false end
    local A = Adapter()
    if not A or QuestieState() ~= "READY" then return false end
    if type(areaId) == "number" and WorldMapFrame and WorldMapFrame.SetMapID then
        local here = A.ZoneForMap(MapID())
        if here ~= areaId then
            local uiMapId = A.UiMapForArea(areaId)
            if uiMapId then WorldMapFrame:SetMapID(uiMapId) end
        end
    end
    S.selected = questId
    S.focusQuest = questId
    S.pulseUntil = Now() + PULSE_SECONDS
    S.pulseToken = S.pulseToken + 1
    local token = S.pulseToken
    local found = false
    if MapShown() then
        M.Refresh()
        found = ScrollTo(questId)
    else
        S.pendingScroll = questId
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(PULSE_SECONDS, Guarded(function() EndPulse(token) end))
    end
    return found
end

-- ---------------------------------------------------------------------------
-- Attachment
--
-- Blizzard_WorldMap is not load-on-demand on this client, so the map is up by
-- PLAYER_LOGIN; ADDON_LOADED "Blizzard_WorldMap" is the second chance in case
-- that ever changes (the Commander_Orders precedent). The hooks go in once.
-- Nothing is BUILT until the map is first shown with Questie present.
-- ---------------------------------------------------------------------------

-- Blizzard's own OnShow has already refreshed every registered provider
-- (MapCanvasMixin.OnShow) before this post-hook runs, so the pins are
-- redrawn here only when the provider was added just now
local function OnMapShow()
    if QuestieState() == "ABSENT" then return end
    local fresh = not S.provider
    BuildProvider()
    RefreshAll(fresh)
end

local function OnMapChanged()
    if MapShown() then RefreshAll(false) end
end

local function OnRelayout()
    if S.drawer and MapShown() and S.drawer:IsShown() then Render() end
end

local function OnNumbersMoved()
    if MapShown() then QueueRedraw() end
end

local function Attach()
    if S.attached then return true end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.HookScript
        and hooksecurefunc and Adapter()) then
        return false
    end
    S.attached = true
    WorldMapFrame:HookScript("OnShow", Guarded(OnMapShow))
    if type(WorldMapFrame.OnMapChanged) == "function" then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", Guarded(OnMapChanged))
    end
    if type(WorldMapFrame.SynchronizeDisplayState) == "function" then
        hooksecurefunc(WorldMapFrame, "SynchronizeDisplayState", Guarded(OnRelayout))
    end
    local container = WorldMapFrame.ScrollContainer
    if container.HookScript then container:HookScript("OnSizeChanged", Guarded(OnRelayout)) end
    local A = Adapter()
    if type(A.AddListener) == "function" then A.AddListener(OnNumbersMoved) end
    if Commander and Commander.AddListener and COMMANDER_QUESTLOG_EVENTS and COMMANDER_QUESTLOG_EVENTS.UPDATE then
        Commander.AddListener(COMMANDER_QUESTLOG_EVENTS.UPDATE, OnNumbersMoved)
    end
    if MapShown() then Guarded(OnMapShow)() end
    return true
end

if CreateFrame then
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:RegisterEvent("ADDON_LOADED")
    events:SetScript("OnEvent", function(self, event, addonName)
        if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and addonName == "Blizzard_WorldMap") then
            Attach()
        end
        if S.attached then
            self:UnregisterEvent("PLAYER_LOGIN")
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Public and harness accessors
-- ---------------------------------------------------------------------------

function M.IsBuilt()
    return S.drawer ~= nil
end

function M._Drawer() return S.drawer end
function M._Rows() return S.rows end
function M._Model() return S.model end
function M._Provider() return S.provider, S.pool end

function M._State()
    return {
        attached = S.attached, open = S.open, offset = S.offset, width = S.width,
        hasContent = S.hasContent, message = S.message, selected = S.selected,
        focusQuest = S.focusQuest, uiMapId = S.uiMapId, areaId = S.areaId, kind = S.kind,
        refreshes = S.refreshes, visibleRows = VisibleRows(), lastError = S.lastError,
    }
end

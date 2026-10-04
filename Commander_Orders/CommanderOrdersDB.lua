-- Commander Orders: saved settings, migrations, the settings page and /corder.
--
-- Two saved variables, and the split is the point (orders.md D2, R7):
--
--   CommanderOrdersDB    ACCOUNT-WIDE. The settings below, the named Places
--                        (the old rally points, tagged with the faction that
--                        marked them) and the saved paste pages. Nothing that
--                        says where THIS character is going lives here: the
--                        old account-wide Waypoint gave an alt the main's
--                        order on another continent, and a corpse order
--                        followed the player onto the next character.
--   CommanderOrdersChar  PER CHARACTER. The waypoint store (records, routes,
--                        the pinned target, the uid counter) and the death
--                        the corpse arrow is working from. The runtime owns
--                        it; this file only makes sure it is a table.
--
-- The schema ladder. DBVersion is kept OUT of the defaults, so Restore
-- Defaults can never re-stamp it, and every step runs once:
--   (none) a 2.x saved variable: EnableOrders, OrderSound, the one Waypoint
--          and RallyPoints[1..4]. An empty table is a fresh install and is
--          stamped current without migrating.
--   2 -> 3 drops Waypoint (account-wide and, before 1db0730a, a shape the
--          new store cannot read), moves RallyPoints to Places with the slot
--          number as the title ("Rally 1"), carries OrderSound over as
--          Sounds, and keeps the user's EnableOrders exactly as it was.
-- Places and PastePages stay out of the defaults too, so a reset keeps them.
--
-- /corder is the framework's slash (exact-match handlers, lowercased). The
-- forms that carry free text -- "/corder way 45 66 Nazgrel", "/corder go
-- Farm", "/corder mark Farm", "/corder here Camp" -- cannot go through it:
-- the framework lowercases the message and looks the whole string up. So
-- after Finalize the framework's own SlashCmdList entry is wrapped: a line
-- whose first word takes an argument goes to CommanderOrders.Command with its
-- case intact, anything else falls through to the framework untouched (its
-- usage line, "reset", the bare command opening this page). The wrap is of
-- Orders' own key, added at PLAYER_LOGIN before anything can have been typed.

CommanderOrdersDB = _G.CommanderOrdersDB or {}
CommanderOrdersChar = _G.CommanderOrdersChar or {}

COMMANDER_ORDERS_EVENTS = COMMANDER_ORDERS_EVENTS or {}
COMMANDER_ORDERS_EVENTS.UPDATE = "COMMANDER_ORDERS_UPDATE"      -- settings changed
COMMANDER_ORDERS_EVENTS.CHANGED = "COMMANDER_ORDERS_CHANGED"    -- waypoints or the arrow's target changed

CommanderOrders = CommanderOrders or {}
local O = CommanderOrders
local D = O.Data or {}
O.DB = O.DB or {}
local DBM = O.DB

local UI = Commander and Commander.UI

local DB_VERSION = 3
DBM.DB_VERSION = DB_VERSION

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
local DefaultSettings = {
    EnableOrders = true,

    -- the arrow
    ShowArrow = true,
    SmoothArrow = true,
    Units = "AUTO",
    ShowEta = true,
    HideNoTarget = true,
    HideInCombat = false,
    HideInInstances = false,
    HideWithMap = false,
    ArrowModifier = "SHIFT",

    -- behaviour
    ArriveYards = 10,
    AutoClosest = true,
    KeepMyMarks = false,
    CorpseArrow = true,
    Sounds = true,
    SoundChannel = "SFX",
    Announce = true,

    -- map and minimap (drawn by CommanderOrdersPins.lua)
    MinimapPins = true,
    MinimapEdge = true,
    WorldPins = true,
    RouteLines = true,
    MapClickModifier = "CTRL",
    MapCoords = true,

    -- sharing
    ShareAccept = "ASK",
    ListenTomTom = false,

    -- compatibility
    TomTomShim = true,
    ClaimWaySlash = true,
}
if UI and UI.HudChromeDefaults then
    for k, v in pairs(UI.HudChromeDefaults("Arrow", "NONE")) do DefaultSettings[k] = v end
end
O.Defaults = DefaultSettings

-- ---------------------------------------------------------------------------
-- Migrations
-- ---------------------------------------------------------------------------
local function ValidRally(p)
    return type(p) == "table" and type(p.mapID) == "number" and p.mapID > 0
        and type(p.x) == "number" and p.x >= 0 and p.x <= 1
        and type(p.y) == "number" and p.y >= 0 and p.y <= 1
end

local MIGRATIONS = {}

-- 2 -> 3: the one account-wide Waypoint goes, the rally slots become Places
MIGRATIONS[2] = function(db)
    db.Waypoint = nil
    local places = type(db.Places) == "table" and db.Places or {}
    if type(db.RallyPoints) == "table" then
        local stamp = (time and time()) or 0
        for slot = 1, 4 do
            local p = db.RallyPoints[slot]
            if ValidRally(p) then
                places[#places + 1] = {
                    title = "Rally " .. slot, map = p.mapID, x = p.x, y = p.y,
                    created = stamp,
                }
            end
        end
    end
    db.RallyPoints = nil
    db.Places = places
    if db.OrderSound ~= nil then
        if db.Sounds == nil then db.Sounds = db.OrderSound and true or false end
        db.OrderSound = nil
    end
end

function DBM.Migrate(db)
    if type(db) ~= "table" then return end
    local v = db.DBVersion
    if type(v) ~= "number" then
        if next(db) == nil then
            db.DBVersion = DB_VERSION
            return
        end
        v = 2
    end
    while v < DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
    end
    db.DBVersion = v
end

-- Idempotent: both this file's ADDON_LOADED and the runtime's call it, so
-- the order the client dispatches the two frames in never matters
function DBM.Init()
    if type(_G.CommanderOrdersDB) ~= "table" then _G.CommanderOrdersDB = {} end
    if type(_G.CommanderOrdersChar) ~= "table" then _G.CommanderOrdersChar = {} end
    local db = CommanderOrdersDB
    if DBM._initFor == db then return db end
    DBM.Migrate(db)
    if UI and UI.ApplyDefaults then UI.ApplyDefaults(db, DefaultSettings) end
    if type(db.Places) ~= "table" then db.Places = {} end
    if type(db.PastePages) ~= "table" then db.PastePages = {} end
    DBM._initFor = db
    return db
end

local function DB() return CommanderOrdersDB end

local function Notify()
    if Commander and Commander.Notify then Commander.Notify(COMMANDER_ORDERS_EVENTS.UPDATE) end
end
DBM.Notify = Notify

function DBM.Reset()
    if UI and UI.ResetToDefaults then UI.ResetToDefaults(DB(), DefaultSettings) end
    Notify()
    print("Commander Orders: settings restored to defaults (waypoints and places kept)")
end

-- ---------------------------------------------------------------------------
-- The settings page
-- ---------------------------------------------------------------------------
local function Command(word, rest)
    local fn = O.Command
    if type(fn) == "function" then return fn(word, rest) end
end

local function Enabled() return DB().EnableOrders and true or false end

local function Check(panel, label, key, tooltip, isEnabled)
    return panel:AddCheckbox({
        label = label, tooltip = tooltip,
        get = function() return DB()[key] end,
        set = function(value) DB()[key] = value end,
        isEnabled = isEnabled or Enabled,
    })
end

local function CheckPair(panel, left, right)
    local function Spec(t)
        if not t then return nil end
        local key = t[2]
        return {
            label = t[1], tooltip = t[3],
            get = function() return DB()[key] end,
            set = function(value) DB()[key] = value end,
            isEnabled = t[4] or Enabled,
        }
    end
    return panel:AddCheckboxPair(Spec(left), Spec(right))
end

local function Drop(key, label, options, tooltip, isEnabled)
    return {
        label = label, tooltip = tooltip, options = options,
        get = function() return DB()[key] end,
        set = function(value) DB()[key] = value end,
        isEnabled = isEnabled or Enabled,
    }
end

local SLASH_HANDLERS = {
    clear = function() Command("clear") end,
    list = function() Command("list") end,
    arrow = function() Command("arrow") end,
    unlock = function() Command("unlock") end,
    lock = function() Command("lock") end,
    manager = function() Command("manager") end,
    paste = function() Command("paste") end,
    here = function() Command("here") end,
    share = function() Command("share") end,
    next = function() Command("next") end,
    prev = function() Command("prev") end,
    closest = function() Command("closest") end,
    places = function() Command("places") end,
    guide = function() Command("guide") end,
    way = function() Command("way", "") end,
    mark = function() Command("mark", "") end,
    go = function() Command("go", "") end,
}
-- The old rally slots, kept so muscle memory still works
for slot = 1, 4 do
    SLASH_HANDLERS["set " .. slot] = function() Command("set", tostring(slot)) end
    SLASH_HANDLERS["go " .. slot] = function() Command("go", tostring(slot)) end
end

-- First words that carry free text; the framework's exact match cannot
-- hand them their argument, let alone its case
local FREE_WORDS = { way = true, mark = true, go = true, here = true, share = true }

local function WrapSlash()
    local key = "COMMANDERUI_ORDERS"
    local base = SlashCmdList and SlashCmdList[key]
    if type(base) ~= "function" then return end
    SlashCmdList[key] = function(msg)
        local text = type(msg) == "string" and msg or ""
        local word, rest = text:match("^%s*(%S+)%s*(.-)%s*$")
        word = word and word:lower()
        if word and FREE_WORDS[word] and rest ~= "" then
            -- "/corder go 1" stays the rally slot, through the same path
            Command(word, rest)
            return
        end
        return base(msg)
    end
end

local function CreatePanel()
    if not (UI and UI.NewPanel) then return end
    local panel = UI.NewPanel({
        key = "Orders",
        title = "Orders",
        addonName = "Commander_Orders",
        description = "The suite's own navigation: an on-screen arrow that points the way to any waypoint, with distance and arrival time, plus pins on the minimap and the world map. Ctrl+Right-click the world map, type /way, or press a Waypoint button anywhere in Commander, and it takes you there. Waypoints belong to whoever set them, so a quest or a corpse never wipes out your own mark, and they are kept for each character. Routes walk you from stop to stop. Questie and other addons that ask for TomTom are answered too, so TomTom is no longer needed.",
        event = COMMANDER_ORDERS_EVENTS.UPDATE,
        slash = { "/corder" },
        slashHandlers = SLASH_HANDLERS,
    })

    panel:AddCheckbox({
        label = "Enable Commander Orders",
        tooltip = "The whole module. While it is off no waypoint can be added (addons that ask are told no), the arrow and the pins are hidden, and your saved waypoints wait untouched.",
        get = function() return DB().EnableOrders end,
        set = function(value) DB().EnableOrders = value end,
    })
    panel:AddButtonRow({
        { label = "Open Manager", tooltip = "The list of every waypoint and route, with distances, where you can rename, share, reorder and remove them. Also /corder manager.",
          onClick = function() Command("manager") end, isEnabled = Enabled },
        { label = "Paste Waypoints", tooltip = "Paste any number of /way lines (with or without the /way in front) and add them as waypoints or as a route. Also /corder paste.",
          onClick = function() Command("paste") end, isEnabled = Enabled },
        { label = "Clear All", tooltip = "Remove every waypoint and route, yours and the ones other addons set. You are asked first.",
          onClick = function() Command("clearall") end, isEnabled = Enabled },
    })

    -- The arrow ---------------------------------------------------------
    panel:AddSection("Arrow", "The arrow floats on screen and lets your clicks and camera turns pass straight through it. Hold Shift (or the key chosen below) over it to use it: Shift-click opens the manager, Shift-right-click opens its menu. Because it ignores the mouse, the triple right-click unlock other HUD frames have does not reach it: unlock it here or with /corder unlock.")
    CheckPair(panel,
        { "Show the Arrow", "ShowArrow", "Draw the arrow. With it off, waypoints still arrive and clear, and the pins still show." },
        { "Smooth Turning", "SmoothArrow", "Ease the arrow round as you turn instead of snapping to each new heading." })
    CheckPair(panel,
        { "Show Arrival Time", "ShowEta", "Show an estimate of the time to arrive under the distance, from your own speed. It hides while you stand still, walk away or fly a taxi." },
        { "Hide With No Waypoint", "HideNoTarget", "Hide the arrow when there is nothing to point at. Off: it stays on screen saying so." })
    CheckPair(panel,
        { "Hide In Combat", "HideInCombat", "Hide the arrow while you are in combat. Off by default, so the screen looks the same in and out of a fight." },
        { "Hide In Instances", "HideInInstances", "Hide the arrow inside dungeons, raids and battlegrounds, where the game gives no position to point from." })
    CheckPair(panel,
        { "Hide With the World Map", "HideWithMap", "Hide the arrow while the world map is open." },
        nil)
    panel:AddDropdownPair(
        Drop("Units", "Distance Units", D.UNITS or {},
            "Yards are the game's own unit. Metres show metres and kilometres. Automatic uses yards in the US region and metres elsewhere."),
        Drop("ArrowModifier", "Use Arrow With", D.MODIFIERS or {},
            "The key you hold over the arrow to click it. Without it held, the arrow never takes a click."))
    if UI.AddHudChromeOptions then
        UI.AddHudChromeOptions(panel, DB(), "Arrow", {
            isEnabled = Enabled,
            onChanged = Notify,
        })
    end

    -- Behaviour -------------------------------------------------------------
    panel:AddSection("Behaviour", "When a waypoint counts as reached, what the arrow follows when you have not chosen, and the corpse run.")
    panel:AddSlider({
        label = "Arrival Distance",
        tooltip = "How close counts as arrived, in yards. Waypoints with a distance of their own (some addons set one) keep theirs.",
        min = 3, max = 40, step = 1, format = "%d yd",
        get = function() return DB().ArriveYards end,
        set = function(value) DB().ArriveYards = value end,
        isEnabled = Enabled,
    })
    CheckPair(panel,
        { "Follow the Closest", "AutoClosest", "When you have not picked a waypoint (or it was reached), point at the nearest one on the landmass you stand on." },
        { "Keep My Own Marks", "KeepMyMarks", "Waypoints you set yourself stay on the map after you reach them, ticked off, instead of clearing." })
    CheckPair(panel,
        { "Corpse Arrow", "CorpseArrow", "After you release, point at your corpse (or the entrance of the instance it lies in), ahead of everything else, until you are alive again. Not in battlegrounds and arenas." },
        { "Announce In Chat", "Announce", "A short chat line when you set, mark or share a waypoint yourself. Waypoints other addons set are never announced." })
    panel:AddCheckbox({
        label = "Sounds",
        tooltip = "A ping when a waypoint is set or shared with you, and a chime when you arrive.",
        get = function() return DB().Sounds end,
        set = function(value) DB().Sounds = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown(Drop("SoundChannel", "Sound Channel", D.SOUND_CHANNELS or {},
        "Which volume slider the sounds follow.",
        function() return Enabled() and DB().Sounds end))

    -- Map and minimap -------------------------------------------------------
    panel:AddSection("Map & Minimap", "Pins for your waypoints on the minimap and the world map, and adding a waypoint with a click on the map.")
    CheckPair(panel,
        { "Minimap Pins", "MinimapPins", "A pin on the minimap for every waypoint on your landmass, not just in your zone." },
        { "Pins Ride the Edge", "MinimapEdge", "A waypoint off the edge of the minimap shows as a small arrow on its rim, pointing the way." })
    CheckPair(panel,
        { "World Map Pins", "WorldPins", "Pins on the world map, on the zone and on the continent around it, with numbered badges for route stops." },
        { "Route Lines", "RouteLines", "Lines between the stops of the route you are on." })
    panel:AddDropdown(Drop("MapClickModifier", "Add With Right-Click Plus", D.MAP_MODIFIERS or {},
        "Hold this key and right-click the world map to drop a waypoint there. A click on a continent lands in the zone under the cursor. Off turns map clicks off."))
    Check(panel, "Map Coordinates", "MapCoords",
        "Your coordinates and the cursor's along the bottom of the world map, for the map you are looking at. Skipped when Questie already shows its own.")

    -- Sharing ---------------------------------------------------------------
    panel:AddSection("Sharing", "Waypoints your group sends you never take your arrow from a waypoint of your own: you choose.")
    panel:AddDropdown(Drop("ShareAccept", "Waypoints From Others", D.SHARE_ACCEPT or {},
        "Ask me: a small window offers Add, Add and go, or Ignore. Add from my group: waypoints from people in your group are added quietly; anyone else is asked. Off: shared waypoints are ignored. A share added without \"go\" is never pinned and waits behind your own waypoints; Follow the Closest points at it only when you have nothing else."))
    Check(panel, "Listen to TomTom Users", "ListenTomTom",
        "Also accept waypoints group members send from TomTom. They are handled the same way as above.")

    -- Compatibility ---------------------------------------------------------
    panel:AddSection("Compatibility", "Other addons that were written for TomTom.")
    Check(panel, "Answer TomTom Requests From Questie and Other Addons", "TomTomShim",
        "Questie's \"Set TomTom Target\", its Ctrl-click on map icons, and WhatsTraining's trainer waypoints all ask for TomTom. With this on (and TomTom not installed, and Commander Orders on) they go to Commander Orders instead. Questie still says TomTom is not installed in its own options; that is expected. A waypoint of your own at the same spot is never removed when Questie moves on.")
    Check(panel, "Claim /way", "ClaimWaySlash",
        "Answer /way, /wayb and /cway when TomTom is not installed. /corder way always works. Turning this off takes effect after a reload.")

    -- Places ----------------------------------------------------------------
    panel:AddSection("Places", "Named spots you keep for good, shared by all your characters (the old rally points are here too). Also /corder mark <name> and /corder go <name>.")
    panel:AddButtonRow({
        { label = "Mark Place Here", tooltip = "Save where you stand as a place.",
          onClick = function() Command("mark", "") end, isEnabled = Enabled },
        { label = "List Places", tooltip = "Print your places in the chat frame.",
          onClick = function() Command("places") end },
    })

    panel:Finalize({
        onDefaults = DBM.Reset,
        defaultsTooltip = "Reset every option on this page. Your waypoints, routes, places and paste pages are kept.",
    })
    WrapSlash()
    DBM.Panel = panel
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Orders" then
        DBM.Init()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        DBM.Init()
        local ok, err = pcall(CreatePanel)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end)

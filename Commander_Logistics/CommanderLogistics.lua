-- Commander Logistics: automated supply lines. When a merchant window
-- opens, gray-quality junk is sold (one item per tick, respecting server
-- responses) and equipment is repaired from the player's own gold, followed
-- by a one-line quartermaster's report.
--
-- ---------------------------------------------------------------------------
-- Repair vendors (2.2.0): learned by visiting them, offered when you need one
-- ---------------------------------------------------------------------------
-- The client keeps no list of repair vendors, but the moment a merchant
-- window opens that offers repairs (CanMerchantRepair), the player is
-- standing within interaction range of one. That moment is recorded: the npc
-- and its name, and where the VENDOR stands (2.3.0): the spawn Commander
-- Orders' locator knows for that npc within a few yards of the player, else
-- where the player stands, on the map (the waypoint) and in the world (the
-- distance). Account-wide like the rest of CommanderLogisticsDB, filed per
-- faction, because a vendor that repairs for your Horde alt is not one your
-- Alliance main can walk up to.
--
-- Supply lines (2.3.0, Commander Orders 3.1): the learned book is registered
-- with Orders' locator as a "townsfolk" resolver for Repair and Vendor (every
-- repair vendor is a vendor), so it is merged with Questie's lists wherever a
-- module asks Orders for the nearest repair or vendor. "Nearest repair"
-- (/clog repair, the settings button, Commander Adjutant's durability alert)
-- and "nearest vendor" (/clog vendor, Adjutant's bags-full alert) read that
-- merged list when the locator answers, else the learned book alone, and
-- take the nearest ON THE PLAYER'S LANDMASS: same world instance AND same UI
-- continent, because Eversong and Hellfire share instance 530 and a straight
-- line between them is nonsense (Commander Orders' D4). Distances are world
-- yards from UnitPosition's north/west pair against the place's own (Orders'
-- D1: the axes are never crossed).
--
-- The waypoint itself is Commander Orders', made through its GoTo under
-- (source "Logistics", key "repair" / "vendor"): one record each, moved by
-- every request, and removed the next time a repair merchant (or, for the
-- vendor, any merchant) opens, since standing there is what it was for. A
-- request you make is worded by Orders ("Waypoint set: Repair: Smith Argus
-- (Elwynn Forest 42.0, 66.0)", behind its Announce setting; Orders'
-- one-rule DECISIONS entry); an offer (Adjutant's) is quiet, never takes
-- over a waypoint you asked for on the same line, and its withdrawal takes
-- down only an offer (a request over an offer makes the record yours). The
-- settings page's two Go buttons are Commander.UI.GoButtons on the same
-- keys (CommanderLogistics_SupplySpec). Orders is
-- optional and looked up at the request, never captured at load; absent or
-- turned off, the place is printed with its /way line instead.
--
-- Traps:
--   * UnitPosition and GetPlayerMapPosition answer nil inside instances, so a
--     vendor met in a dungeon is not recorded (there is nowhere to point).
--   * GetPlayerMapPosition and GetWorldPosFromMapPos allocate a Vector2D:
--     they run per merchant visit and per request, never on a clock. A
--     request measures only the places on the player's landmass (the
--     landmass of a map is worked out once and kept).
--   * RepairVendors is data, not a setting: it is kept out of the defaults so
--     Restore Defaults never forgets every vendor you have met.
--   * Commander Orders loads before this file (OptionalDeps), so the resolver
--     is registered at load; without Orders' locator file it is refused and
--     nothing changes.

local SELL_TICK = 0.15
local MAX_VENDORS = 400            -- per faction; the oldest sighting goes first
local CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2

local sellTicker
local soldCount = 0
local soldValue = 0
local repairCost = 0

local function StopSelling()
    if sellTicker then
        sellTicker:Cancel()
        sellTicker = nil
    end
end

local function FormatMoney(copper)
    copper = math.floor(copper + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local rest = copper % 100
    if gold > 0 then
        return string.format("%dg %ds", gold, silver)
    elseif silver > 0 then
        return string.format("%ds %dc", silver, rest)
    end
    return string.format("%dc", rest)
end

local function Report()
    if not CommanderLogisticsDB.Report then return end
    local parts = {}
    if soldCount > 0 then
        parts[#parts + 1] = string.format("sold %d junk |4item:items; for %s", soldCount, FormatMoney(soldValue))
    end
    if repairCost > 0 then
        parts[#parts + 1] = string.format("repairs cost %s", FormatMoney(repairCost))
    end
    if #parts > 0 then
        print("|cff40c0ffLogistics:|r " .. table.concat(parts, ", "))
    end
end

-- Find the next gray item and sell it; one item per tick so the server's
-- responses (and the merchant window closing) are always respected
local function SellNextJunk()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        StopSelling()
        Report()
        return
    end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            -- hasNoValue is accurate while a merchant is open; without the
            -- check, a no-value gray would be re-attempted every tick forever
            if info and info.quality == 0 and not info.isLocked and not info.hasNoValue then
                local unitPrice = select(11, C_Item.GetItemInfo(info.itemID))
                if unitPrice and unitPrice > 0 then
                    soldValue = soldValue + unitPrice * (info.stackCount or 1)
                end
                soldCount = soldCount + 1
                C_Container.UseContainerItem(bag, slot)
                return -- one sale per tick
            end
        end
    end
    -- Nothing gray left
    StopSelling()
    Report()
end

local function RunLogistics()
    if not CommanderLogisticsDB.EnableLogistics then return end
    soldCount, soldValue, repairCost = 0, 0, 0

    if CommanderLogisticsDB.AutoRepair and CanMerchantRepair and CanMerchantRepair() then
        local cost, needed = GetRepairAllCost()
        if needed and cost and cost > 0 and GetMoney() >= cost then
            RepairAllItems()
            repairCost = cost
        end
    end

    if CommanderLogisticsDB.AutoSellJunk then
        StopSelling()
        sellTicker = C_Timer.NewTicker(SELL_TICK, SellNextJunk)
    else
        Report()
    end
end

-- ---------------------------------------------------------------------------
-- Repair vendors and the supply lines
-- ---------------------------------------------------------------------------
local VENDOR_NEAR = 40             -- yards: a known spawn this close to you is the vendor you talk to

-- What each supply line is: Orders' locator kind, the waypoint's key and
-- title, the words for a refusal, and which merchants take its waypoint down
local SUPPLY = {
    Repair = { key = "repair", title = "Repair: ", words = "repair", query = { townsfolk = "Repair" } },
    Vendor = { key = "vendor", title = "Vendor: ", words = "vendor", query = { townsfolk = "Vendor" } },
}

local function Say(msg)
    print("|cff40c0ffLogistics:|r " .. msg)
end

local function MapInfo(map)
    if type(map) ~= "number" or not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, map)
    if ok and type(info) == "table" then return info end
    return nil
end

-- The landmass a map sits on: its UI continent, or for a map with none (a
-- battleground under Azeroth) its top-most ancestor below the world map
local function Landmass(map)
    local id, top = map, nil
    for _ = 1, 12 do
        local info = MapInfo(id)
        if not info then break end
        if info.mapType == CONTINENT then return id end
        if type(info.mapType) == "number" and info.mapType <= 1 then break end
        top = id
        local parent = info.parentMapID
        if type(parent) ~= "number" or parent == 0 then break end
        id = parent
    end
    return top
end

-- Landmass per map, worked out once (maps never move)
local landOf = {}
local function LandOf(map)
    local land = landOf[map]
    if land == nil then
        land = Landmass(map) or false
        landOf[map] = land
    end
    return land or nil
end

-- A map position in the world: instance, north, west (Orders' D1 order)
local function WorldOf(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or inst == nil or (type(pos) ~= "table" and type(pos) ~= "userdata") then return nil end
    local north, west = pos.x, pos.y
    if type(north) ~= "number" and pos.GetXY then north, west = pos:GetXY() end
    if type(north) ~= "number" or type(west) ~= "number" then return nil end
    return inst, north, west
end

-- Where the player stands: { map, x, y, north, west, inst }, or nil inside
-- instances (no position) and while loading (no map)
local function PlayerSpot(withMapPosition)
    if not UnitPosition then return nil end
    local okPos, north, west, _, inst = pcall(UnitPosition, "player")
    if not okPos or type(north) ~= "number" or type(west) ~= "number" or inst == nil then return nil end
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local okMap, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not okMap or type(map) ~= "number" then return nil end
    local spot = { map = map, north = north, west = west, inst = inst }
    if withMapPosition then
        if not C_Map.GetPlayerMapPosition then return nil end
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
        if not ok or (type(pos) ~= "table" and type(pos) ~= "userdata") then return nil end
        local x, y = pos.x, pos.y
        if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
        if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
        if x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
        spot.x, spot.y = x, y
    end
    return spot
end

-- "Creature-0-4379-0-11-6123-00002B6E9A" -> 6123
local function NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
    return nil
end

local function Faction()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return type(faction) == "string" and faction or "Neutral"
end

-- Commander Orders 3.1 (GoTo and the rest of its Go-to API), or nil
local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.GoTo) == "function" then return api end
    return nil
end

-- Orders' words for a refusal code (its one vocabulary), else the code
local function Reason(why)
    local api = Orders()
    if api and type(api.Reason) == "function" then
        local ok, text = pcall(api.Reason, why)
        if ok and type(text) == "string" then return text end
    end
    return tostring(why)
end

-- The /way line for a place: Orders' own, or the same shape without it
local function WayLine(map, x, y, title)
    local api = Orders()
    if api and type(api.WayLineFor) == "function" then
        local ok, line = pcall(api.WayLineFor, map, x, y, title)
        if ok and type(line) == "string" then return line end
    end
    return string.format("/way #%d %.2f %.2f%s", map, x * 100, y * 100, title and (" " .. title) or "")
end

-- This faction's vendor book, created on first use
local function VendorBook(create)
    local db = CommanderLogisticsDB
    if type(db.RepairVendors) ~= "table" then
        if not create then return nil end
        db.RepairVendors = {}
    end
    local faction = Faction()
    local book = db.RepairVendors[faction]
    if type(book) ~= "table" then
        if not create then return nil end
        book = {}
        db.RepairVendors[faction] = book
    end
    return book
end

local function FormatYards(yards)
    if yards >= 1000 then return string.format("%.1fk yd", yards / 1000) end
    return string.format("%d yd", math.floor(yards + 0.5))
end

-- Where the vendor you are talking to stands: the spawn Orders' locator
-- knows for that npc, within VENDOR_NEAR yards of you; nil when it knows
-- none there (no Questie, an npc it lacks, a vendor that walks about)
local function VendorSpot(npc, spot)
    local api = Orders()
    if not (npc and api and type(api.Locate) == "function") then return nil end
    local ok, places = pcall(api.Locate, { npc = npc })
    if not ok or type(places) ~= "table" then return nil end
    local best, bestYards
    for _, p in ipairs(places) do
        if type(p) == "table" and type(p.map) == "number" and type(p.x) == "number" and type(p.y) == "number" then
            local inst, north, west = WorldOf(p.map, p.x, p.y)
            if inst == spot.inst then
                local dn, dw = north - spot.north, west - spot.west
                local yards = math.sqrt(dn * dn + dw * dw)
                if yards <= VENDOR_NEAR and (not bestYards or yards < bestYards) then
                    best, bestYards = { map = p.map, x = p.x, y = p.y, north = north, west = west, inst = inst }, yards
                end
            end
        end
    end
    return best
end

-- At a merchant that repairs: remember where this vendor stands
local function LearnRepairVendor()
    if not (CommanderLogisticsDB.EnableLogistics and CommanderLogisticsDB.LearnRepairVendors) then return end
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local spot = PlayerSpot(true)
    if not spot then return end
    local name = UnitName and UnitName("npc")
    local npc = NpcID(UnitGUID and UnitGUID("npc"))
    if type(name) ~= "string" or name == "" then return end
    local key = npc and tostring(npc) or (name .. "@" .. spot.map)
    local at = VendorSpot(npc, spot) or spot
    local book = VendorBook(true)
    book[key] = {
        name = name, npc = npc, map = at.map, x = at.x, y = at.y,
        north = at.north, west = at.west, inst = at.inst, land = LandOf(at.map),
        seen = time and time() or 0, spawn = at ~= spot or nil,
    }
    -- A book that only grows: past the cap, the vendor seen longest ago goes
    local count, oldestKey, oldestSeen = 0, nil, math.huge
    for k, v in pairs(book) do
        count = count + 1
        local seen = type(v) == "table" and tonumber(v.seen) or 0
        if seen < oldestSeen then oldestKey, oldestSeen = k, seen end
    end
    if count > MAX_VENDORS and oldestKey then book[oldestKey] = nil end
end

-- How many repair vendors this faction has learned
function CommanderLogistics_RepairVendorCount()
    local book = VendorBook(false)
    local n = 0
    for _ in pairs(book or {}) do n = n + 1 end
    return n
end

local function Usable(v)
    return type(v) == "table" and type(v.map) == "number" and type(v.x) == "number" and type(v.y) == "number"
        and type(v.name) == "string"
end

-- The learned book as Orders' locator wants it: every vendor of this
-- faction, for Repair and for Vendor (a repair vendor sells too). Registered
-- below as a "townsfolk" resolver; Orders merges it with Questie's lists.
local function LearnedPlaces(kind)
    if kind ~= "Repair" and kind ~= "Vendor" then return nil end
    if not (CommanderLogisticsDB and CommanderLogisticsDB.EnableLogistics) then return nil end
    local book = VendorBook(false)
    if not book then return nil end
    local out = {}
    for _, v in pairs(book) do
        if Usable(v) then out[#out + 1] = { map = v.map, x = v.x, y = v.y, title = v.name, npc = v.npc } end
    end
    return out
end

-- Every place known for a supply line, each { name, npc, map, x, y[, inst,
-- north, west, land] }: the locator's merged list when it answers (the
-- learned book is part of it), else the learned book; and the locator's
-- reason when neither knows one
local function Candidates(kind)
    local api = Orders()
    local why
    if api and type(api.Locate) == "function" then
        local ok, places, reason = pcall(api.Locate, SUPPLY[kind].query)
        if ok and type(places) == "table" and #places > 0 then
            local out = {}
            for _, p in ipairs(places) do
                if type(p) == "table" and type(p.map) == "number" and type(p.x) == "number" and type(p.y) == "number" then
                    out[#out + 1] = { name = type(p.title) == "string" and p.title or nil, npc = p.npc,
                                      map = p.map, x = p.x, y = p.y }
                end
            end
            return out
        end
        why = ok and reason or nil
    end
    local out = {}
    for _, v in pairs(VendorBook(false) or {}) do
        if Usable(v) then
            out[#out + 1] = { name = v.name, npc = v.npc, map = v.map, x = v.x, y = v.y,
                              inst = v.inst, north = v.north, west = v.west, land = v.land }
        end
    end
    return out, why
end

-- The nearest place of a supply line on the player's landmass:
-- { name, npc, map, x, y, yards, zone, kind } (a copy), or nil and a reason:
-- "none" (none known), "noposition" (the player has none: instances),
-- "elsewhere" (known ones, none on this landmass)
local function Nearest(kind)
    if not SUPPLY[kind] then return nil, "none" end
    local list = Candidates(kind)
    if #list == 0 then return nil, "none" end
    local spot = PlayerSpot(false)
    if not spot then return nil, "noposition" end
    local land = LandOf(spot.map)
    local best, bestYards
    for _, v in ipairs(list) do
        local vLand = v.land or LandOf(v.map)
        if vLand == land then
            local inst, north, west = v.inst, v.north, v.west
            if type(north) ~= "number" or type(west) ~= "number" or inst == nil then
                inst, north, west = WorldOf(v.map, v.x, v.y)
            end
            if inst ~= nil and inst == spot.inst then
                local dn, dw = north - spot.north, west - spot.west
                local yards = math.sqrt(dn * dn + dw * dw)
                if not bestYards or yards < bestYards then best, bestYards = v, yards end
            end
        end
    end
    if not best then return nil, "elsewhere" end
    local info = MapInfo(best.map)
    return {
        name = best.name or (kind == "Repair" and "a repair vendor" or "a vendor"), npc = best.npc,
        map = best.map, x = best.x, y = best.y, yards = bestYards, zone = info and info.name or nil, kind = kind,
    }
end

-- The nearest repair vendor on the player's landmass (learned, and Questie's
-- through Orders' locator): see Nearest
function CommanderLogistics_NearestRepair()
    return Nearest("Repair")
end

-- The same for any supply line: "Repair" or "Vendor" (any merchant)
function CommanderLogistics_Nearest(kind)
    return Nearest(kind)
end

-- A supply line's own refusals (Orders' reasons go through Reason)
local NEAREST_REFUSED = {
    Repair = {
        none = "no repair vendor learned yet: open one and it is remembered",
        noposition = "no position here (inside an instance), so no nearest repair",
        elsewhere = "no repair vendor learned on this continent yet",
    },
    Vendor = {
        none = "no vendor known yet: open one that repairs and it is remembered",
        noposition = "no position here (inside an instance), so no nearest vendor",
        elsewhere = "no vendor known on this continent yet",
    },
}

local function Refused(kind, why)
    local words = NEAREST_REFUSED[kind] and NEAREST_REFUSED[kind][why]
    return words or Reason(why)
end

-- A supply line's one waypoint, (Logistics, key), as Orders hands it out (a
-- copy): the record, or nil, and whether Orders could be asked at all
local function LineRecord(line)
    local api = CommanderOrders
    if type(api) ~= "table" or type(api.List) ~= "function" then return nil, false end
    local ok, list = pcall(api.List, { source = "Logistics" })
    if not ok or type(list) ~= "table" then return nil, false end
    for _, wp in ipairs(list) do
        if type(wp) == "table" and wp.key == line.key then return wp, true end
    end
    return nil, true
end

-- A Commander Orders waypoint at the nearest place of a supply line
-- ("Repair" or "Vendor"), through CommanderOrders.GoTo under (Logistics,
-- "repair" | "vendor").
-- opts.temporary: an offer (Commander Adjutant's alerts). It is added
-- WITHOUT asking for the arrow (setArrow = false). Orders refuses a temporary
-- pin over a pinned waypoint and over a running route, but an offer that
-- asked would still re-pin the arrow away from a waypoint of yours the arrow
-- was following as the closest, and out of a Clear you had just made.
-- Unasked, it sits on the map and minimap, and Orders' Follow the Closest
-- points at it only when nothing of yours is left to follow on this landmass
-- (temporary waypoints rank after every other one there). While a waypoint
-- you asked for holds the line's key, an offer is refused ("yours") and your
-- waypoint is left exactly as it is.
-- opts.quiet: no chat line (Orders' GoTo is silent too).
-- Returns true, uid, place; or false, reason[, place].
function CommanderLogistics_SupplyWaypoint(kind, opts)
    opts = type(opts) == "table" and opts or {}
    local line = SUPPLY[kind]
    if not line then return false, "unknown" end
    local v, why = Nearest(kind)
    if not v then
        if not opts.quiet then Say(Refused(kind, why)) end
        return false, why
    end
    local title = line.title .. v.name
    local way = WayLine(v.map, v.x, v.y, title)
    local api = Orders()
    if not api then
        if not opts.quiet then
            Say("nearest " .. line.words .. " is " .. v.name .. ", " .. FormatYards(v.yards) .. " -- " .. way)
        end
        return false, "absent", v
    end
    -- Turned off or still loading: the line to paste, worded once here
    local okAvail, available, notWhy = pcall(api.IsAvailable)
    if okAvail and not available then
        if not opts.quiet then Say(Reason(notWhy or "disabled") .. " -- " .. way) end
        return false, notWhy or "disabled", v
    end
    -- An offer never takes over a waypoint you asked for: on the same key it
    -- would move your record and make it an offer, which the offer's
    -- withdrawal would then take down from under you
    if opts.temporary then
        local mine = LineRecord(line)
        if mine and not mine.temporary then return false, "yours", v end
    end
    local ok, uid, refused = pcall(api.GoTo, { map = v.map, x = v.x, y = v.y, title = title }, {
        source = "Logistics", key = line.key, setArrow = not opts.temporary,
        temporary = opts.temporary and true or nil, silent = opts.quiet and true or false,
    })
    if ok and uid then return true, uid, v end
    return false, ok and refused or "error", v
end

-- The nearest place of a supply line as a Commander Orders spec, for the
-- settings page's Go buttons (Commander.UI.GoButton, which go through
-- CommanderOrders.GoTo under the same (Logistics, key) as the requests
-- above): { map, x, y, title }, or nil and the line's own sentence for why
-- there is none (the button greys out showing it)
function CommanderLogistics_SupplySpec(kind)
    local line = SUPPLY[kind]
    if not line then return nil, "unknown" end
    local v, why = Nearest(kind)
    if not v then return nil, Refused(kind, why) end
    return { map = v.map, x = v.x, y = v.y, title = line.title .. v.name }
end

-- The nearest repair vendor (see CommanderLogistics_SupplyWaypoint)
function CommanderLogistics_RepairWaypoint(opts)
    return CommanderLogistics_SupplyWaypoint("Repair", opts)
end

-- A supply line's waypoint has done its job (you are at such a merchant, or
-- the need is gone): take it down. Quiet, and a no-op when there is none.
-- opts.offerOnly: only while it is still an offer (temporary). An offer you
-- then asked for yourself (/clog vendor, the settings button: the same key,
-- so the same record, now yours) is left alone by the offer's withdrawal
-- (Commander Adjutant: a free bag slot, mended gear); a merchant still takes
-- it down.
function CommanderLogistics_ClearSupplyWaypoint(kind, opts)
    local line = SUPPLY[kind]
    local api = CommanderOrders
    if not line or type(api) ~= "table" or type(api.RemoveBy) ~= "function" then return 0 end
    if type(opts) == "table" and opts.offerOnly then
        local wp, asked = LineRecord(line)
        if asked and not (wp and wp.temporary) then return 0 end
    end
    local ok, n = pcall(api.RemoveBy, "Logistics", line.key)
    return ok and n or 0
end

function CommanderLogistics_ClearRepairWaypoint(opts)
    return CommanderLogistics_ClearSupplyWaypoint("Repair", opts)
end

function CommanderLogistics_ForgetRepairVendors()
    local n = CommanderLogistics_RepairVendorCount()
    if type(CommanderLogisticsDB.RepairVendors) == "table" then
        CommanderLogisticsDB.RepairVendors[Faction()] = nil
    end
    Say(string.format("forgot %d repair |4vendor:vendors;", n))
    return n
end

-- Shared with Commander Adjutant's banner: "Smith Argus, 340 yd"
function CommanderLogistics_FormatYards(yards)
    if type(yards) ~= "number" then return nil end
    return FormatYards(yards)
end

-- The learned book joins Orders' "nearest repair" / "nearest vendor" lists
-- (CommanderOrdersLocate.lua widens RegisterResolver to "townsfolk"; without
-- it the call is refused and nothing changes)
do
    local api = CommanderOrders
    if type(api) == "table" and type(api.RegisterResolver) == "function" then
        pcall(api.RegisterResolver, "townsfolk", LearnedPlaces)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        -- Learn first: the junk ticker and the repair do not move the player,
        -- but the learning must not depend on either succeeding
        local ok, err = pcall(LearnRepairVendor)
        if not ok and geterrorhandler then geterrorhandler()(err) end
        if CommanderLogisticsDB.EnableLogistics then
            -- At any merchant the vendor waypoint is done; at one who
            -- repairs, the repair waypoint too
            CommanderLogistics_ClearSupplyWaypoint("Vendor")
            if CanMerchantRepair and CanMerchantRepair() then CommanderLogistics_ClearRepairWaypoint() end
        end
        RunLogistics()
    elseif event == "MERCHANT_CLOSED" then
        -- A live ticker means the junk pass was cut short (Escape, walking
        -- away) — still report what was sold and repaired before the close
        if sellTicker then
            StopSelling()
            Report()
        end
    end
end)

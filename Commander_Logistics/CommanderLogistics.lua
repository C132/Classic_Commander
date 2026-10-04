-- Commander Logistics: automated supply lines. When a merchant window
-- opens, gray-quality junk is sold (one item per tick, respecting server
-- responses) and equipment is repaired from the player's own gold, followed
-- by a one-line quartermaster's report.
--
-- ---------------------------------------------------------------------------
-- Repair vendors (2.2.0): learned by visiting them, offered when you need one
-- ---------------------------------------------------------------------------
-- The client keeps no list of repair vendors and the suite ships no world
-- database of them, but the moment a merchant window opens that offers
-- repairs (CanMerchantRepair), the player is standing within interaction
-- range of one. That moment is recorded: the npc and its name, where the
-- player stands on the map (the waypoint) and in the world (the distance).
-- Account-wide like the rest of CommanderLogisticsDB, filed per faction,
-- because a vendor that repairs for your Horde alt is not one your Alliance
-- main can walk up to.
--
-- "Nearest repair" (/clog repair, the settings button, and Commander
-- Adjutant's low-durability alert) is the nearest learned vendor ON THE
-- PLAYER'S LANDMASS: same world instance AND same UI continent, because
-- Eversong and Hellfire share instance 530 and a straight-line distance
-- between them is nonsense (Commander Orders' D4). The distance is
-- UnitPosition's north/west pair against the north/west stored at the visit;
-- both come from the same call, so the axes cannot be crossed (Orders' D1).
--
-- The waypoint itself is Commander Orders', under (source "Logistics", key
-- "repair"): one record, moved by every request, and removed the next time a
-- repair merchant opens, since standing at any repair vendor is what it was
-- for. Orders is optional and looked up at the request, never captured at
-- load; absent, the /way line is printed instead.
--
-- Traps:
--   * UnitPosition and GetPlayerMapPosition answer nil inside instances, so a
--     vendor met in a dungeon is not recorded (there is nowhere to point).
--   * GetPlayerMapPosition allocates a Vector2D: it runs once per merchant
--     visit and once per request, never on a clock.
--   * RepairVendors is data, not a setting: it is kept out of the defaults so
--     Restore Defaults never forgets every vendor you have met.

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
-- Repair vendors
-- ---------------------------------------------------------------------------
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
    local book = VendorBook(true)
    book[key] = {
        name = name, npc = npc, map = spot.map, x = spot.x, y = spot.y,
        north = spot.north, west = spot.west, inst = spot.inst, land = Landmass(spot.map),
        seen = time and time() or 0,
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

-- The nearest learned repair vendor on the player's landmass:
-- { name, npc, map, x, y, yards, zone } (a copy), or nil and a reason:
-- "none" (none learned), "noposition" (the player has none: instances),
-- "elsewhere" (learned ones, none on this landmass)
function CommanderLogistics_NearestRepair()
    local book = VendorBook(false)
    if not book or next(book) == nil then return nil, "none" end
    local spot = PlayerSpot(false)
    if not spot then return nil, "noposition" end
    local land = Landmass(spot.map)
    local best, bestYards
    for _, v in pairs(book) do
        if type(v) == "table" and v.inst == spot.inst and v.land == land
            and type(v.north) == "number" and type(v.west) == "number"
            and type(v.map) == "number" and type(v.x) == "number" and type(v.y) == "number" then
            local dn, dw = v.north - spot.north, v.west - spot.west
            local yards = math.sqrt(dn * dn + dw * dw)
            if not bestYards or yards < bestYards then best, bestYards = v, yards end
        end
    end
    if not best then return nil, "elsewhere" end
    local info = MapInfo(best.map)
    return {
        name = best.name, npc = best.npc, map = best.map, x = best.x, y = best.y,
        yards = bestYards, zone = info and info.name or nil,
    }
end

local NEAREST_REFUSED = {
    none = "no repair vendor learned yet: open one and it is remembered",
    noposition = "no position here (inside an instance), so no nearest repair",
    elsewhere = "no repair vendor learned on this continent yet",
    disabled = "Commander Orders is switched off",
    loading = "Commander Orders is still loading",
}

-- A Commander Orders waypoint at the nearest learned repair vendor.
-- opts.temporary: an offer (Commander Adjutant's durability alert). It is
-- added WITHOUT asking for the arrow. Orders refuses a temporary pin only
-- over a pinned waypoint, so an offer that asked would still re-pin the
-- arrow away from a running route, from a waypoint of yours the arrow was
-- following as the closest, and out of a Clear you had just made. Unasked,
-- it sits on the map and minimap, and Orders' Follow the Closest points at
-- it only when nothing of yours is left to follow on this landmass
-- (temporary waypoints rank after every other one there).
-- opts.quiet: no chat line.
-- Returns true, uid, vendor; or false, reason[, vendor].
function CommanderLogistics_RepairWaypoint(opts)
    opts = type(opts) == "table" and opts or {}
    local v, why = CommanderLogistics_NearestRepair()
    if not v then
        if not opts.quiet then Say(NEAREST_REFUSED[why] or tostring(why)) end
        return false, why
    end
    local title = "Repair: " .. v.name
    local line = string.format("/way #%d %.2f %.2f %s", v.map, v.x * 100, v.y * 100, title)
    local O = CommanderOrders
    if type(O) ~= "table" or type(O.Add) ~= "function" then
        if not opts.quiet then Say("nearest repair is " .. v.name .. ", " .. FormatYards(v.yards) .. " -- " .. line) end
        return false, "absent", v
    end
    local ok, uid, refused = pcall(O.Add, {
        map = v.map, x = v.x, y = v.y, title = title,
        source = "Logistics", key = "repair", setArrow = not opts.temporary,
        temporary = opts.temporary and true or nil,
    })
    if ok and uid then
        if not opts.quiet then
            Say((opts.temporary and "marked " or "the arrow points to ") .. v.name .. ", " .. FormatYards(v.yards))
        end
        return true, uid, v
    end
    refused = ok and refused or "error"
    if not opts.quiet then
        Say((NEAREST_REFUSED[refused] or ("Commander Orders refused it (" .. tostring(refused) .. ")")) .. " -- " .. line)
    end
    return false, refused, v
end

-- The repair waypoint has done its job (a repair merchant is open, or the
-- gear is mended): take it down. Quiet, and a no-op when there is none.
function CommanderLogistics_ClearRepairWaypoint()
    local O = CommanderOrders
    if type(O) ~= "table" or type(O.RemoveBy) ~= "function" then return 0 end
    local ok, n = pcall(O.RemoveBy, "Logistics", "repair")
    return ok and n or 0
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

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        -- Learn first: the junk ticker and the repair do not move the player,
        -- but the learning must not depend on either succeeding
        local ok, err = pcall(LearnRepairVendor)
        if not ok and geterrorhandler then geterrorhandler()(err) end
        if CommanderLogisticsDB.EnableLogistics and CanMerchantRepair and CanMerchantRepair() then
            CommanderLogistics_ClearRepairWaypoint()
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

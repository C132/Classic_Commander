-- Commander Logistics: automated supply lines. When a merchant window
-- opens, gray-quality junk is sold (one item per tick, respecting server
-- responses) and equipment is repaired from the player's own gold, followed
-- by a one-line quartermaster's report.

local SELL_TICK = 0.15

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
            if info and info.quality == 0 and not info.isLocked then
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

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        RunLogistics()
    elseif event == "MERCHANT_CLOSED" then
        StopSelling()
    end
end)

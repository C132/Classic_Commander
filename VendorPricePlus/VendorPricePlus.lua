-- Initialize VendorPricePlus table
VendorPricePlus = {}
local VP = VendorPricePlus

-- Map container IDs to inventory IDs
local ContainerIDToInventoryID = ContainerIDToInventoryID or C_Container.ContainerIDToInventoryID

-- Constants
local SELL_PRICE_TEXT = format("%s:", SELL_PRICE)
local overridePrice

-- Identify character bags
local CharacterBags = {}
for i = CONTAINER_BAG_OFFSET + 1, 23 do
    CharacterBags[i] = true
end

-- Identify bank bags
local firstBankBag = ContainerIDToInventoryID(NUM_BAG_SLOTS + 1)
local lastBankBag = ContainerIDToInventoryID(NUM_BAG_SLOTS + NUM_BANKBAGSLOTS)
for i = firstBankBag, lastBankBag do
    CharacterBags[i] = true
end

-- First keyring inventory slot
local FIRST_KEYRING_INVSLOT = 107

-- Check if the tooltip owner is a merchant
local function IsMerchant(tt)
    if MerchantFrame:IsShown() then
        local name = tt:GetOwner():GetName()
        if name then
            return not (name:find("Character") or name:find("TradeSkill"))
        end
    end
end

-- Determine if the price should be shown in the tooltip
local function ShouldShowPrice(tt, source)
    return not IsMerchant(tt)
end

-- Check if the item is a recipe and should be priced
local function CheckRecipe(tt, classID, isOnTooltipSetItem)
    if classID == Enum.ItemClass.Recipe and isOnTooltipSetItem then
        tt.isFirstMoneyLine = not tt.isFirstMoneyLine
        return tt.isFirstMoneyLine
    end
end

-- Override SetTooltipMoney function to modify tooltip display on shift key press
local _SetTooltipMoney = SetTooltipMoney
function SetTooltipMoney(frame, money, ...)
    if IsShiftKeyDown() and overridePrice then
        _SetTooltipMoney(frame, overridePrice, ...)
    else
        _SetTooltipMoney(frame, money, ...)
        overridePrice = nil
    end
end

-- Clear overridePrice on tooltip hide
GameTooltip:HookScript("OnHide", function()
    overridePrice = nil
end)

-- Set price information in the tooltip
function VP:SetPrice(tt, hasWrathTooltip, source, count, item, isOnTooltipSetItem)
    if ShouldShowPrice(tt, source) then
        count = count or 1
        item = item or select(2, tt:GetItem())
        if item then
            local sellPrice, classID = select(11, GetItemInfo(item))
            if sellPrice and sellPrice > 0 and not CheckRecipe(tt, classID, isOnTooltipSetItem) then
                local isShift = IsShiftKeyDown() and count > 1
                local displayPrice = isShift and sellPrice or sellPrice * count
                local unitPrice = sellPrice

                -- Calculate and display unit price if count is 2 or greater
                if count >= 2 then
                    unitPrice = isShift and sellPrice / count or sellPrice
                end

		local priceString
		if count >= 2 then
		    priceString = format("%s     @%s %s",
			GetCoinTextureString(displayPrice),
		        GetCoinTextureString(unitPrice),
			"each"
		    )
		else
		    priceString = format("%s",
		        GetCoinTextureString(displayPrice)
		    )
		end

                tt:AddLine(priceString, 1, 1, 1, false)
                tt:Show()
            end
        end
    end
end


-- Define methods for setting price in various tooltips
local SetItem = {
	SetAction = function(tt, slot)
		if GetActionInfo(slot) == "item" then
			VP:SetPrice(tt, true, "SetAction", GetActionCount(slot))
		end
	end,
	SetAuctionItem = function(tt, auctionType, index)
		local _, _, count = GetAuctionItemInfo(auctionType, index)
		VP:SetPrice(tt, false, "SetAuctionItem", count)
	end,
	SetAuctionSellItem = function(tt)
		local _, _, count = GetAuctionSellItemInfo()
		VP:SetPrice(tt, true, "SetAuctionSellItem", count)
	end,
	SetBagItem = function(tt, bag, slot)
		local count
		if GetContainerItemInfo then
			count = select(2, GetContainerItemInfo(bag, slot))
		else
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				count = info.stackCount
			end
		end
		if count then
			VP:SetPrice(tt, true, "SetBagItem", count)
		end
	end,
	--SetBagItemChild
	--SetBuybackItem -- already shown
	--SetCompareItem
	SetCraftItem = function(tt, index, reagent)
		local _, _, count = GetCraftReagentInfo(index, reagent)
		 -- otherwise returns an empty link
		local itemLink = GetCraftReagentItemLink(index, reagent)
		VP:SetPrice(tt, true, "SetCraftItem", count, itemLink)
	end,
	SetCraftSpell = function(tt)
		VP:SetPrice(tt, true, "SetCraftSpell")
	end,
	--SetHyperlink -- item information is not readily available
	SetInboxItem = function(tt, messageIndex, attachIndex)
		local count, itemID
		if attachIndex then
			count = select(4, GetInboxItem(messageIndex, attachIndex))
		else
			count, itemID = select(14, GetInboxHeaderInfo(messageIndex))
		end
		VP:SetPrice(tt, false, "SetInboxItem", count, itemID)
	end,
	SetInventoryItem = function(tt, unit, slot)
		local count
		if not CharacterBags[slot] then
			count = GetInventoryItemCount(unit, slot)
		end
		if slot < FIRST_KEYRING_INVSLOT then
			VP:SetPrice(tt, VP:IsShown(BankFrame), "SetInventoryItem", count)
		end
	end,
	--SetInventoryItemByID
	--SetItemByID
	SetLootItem = function(tt, slot)
		local _, _, count = GetLootSlotInfo(slot)
		VP:SetPrice(tt, false, "SetLootItem", count)
	end,
	SetLootRollItem = function(tt, rollID)
		local _, _, count = GetLootRollItemInfo(rollID)
		VP:SetPrice(tt, false, "SetLootRollItem", count)
	end,
	--SetMerchantCostItem -- alternate currency
	--SetMerchantItem -- already shown
	SetQuestItem = function(tt, questType, index)
		local _, _, count = GetQuestItemInfo(questType, index)
		VP:SetPrice(tt, false, "SetQuestItem", count)
	end,
	SetQuestLogItem = function(tt, _, index)
		local _, _, count = GetQuestLogRewardInfo(index)
		VP:SetPrice(tt, false, "SetQuestLogItem", count)
	end,
	--SetRecipeReagentItem -- retail
	--SetRecipeResultItem -- retail
	SetSendMailItem = function(tt, index)
		local count = select(4, GetSendMailItem(index))
		VP:SetPrice(tt, true, "SetSendMailItem", count)
	end,
	SetTradePlayerItem = function(tt, index)
		local _, _, count = GetTradePlayerItemInfo(index)
		VP:SetPrice(tt, true, "SetTradePlayerItem", count)
	end,
	SetTradeSkillItem = function(tt, index, reagent)
		local count
		if reagent then
			count = select(3, GetTradeSkillReagentInfo(index, reagent))
		else -- show minimum instead of maximum count
			count = GetTradeSkillNumMade(index)
		end
		VP:SetPrice(tt, false, "SetTradeSkillItem", count)
	end,
	SetTradeTargetItem = function(tt, index)
		local _, _, count = GetTradeTargetItemInfo(index)
		VP:SetPrice(tt, false, "SetTradeTargetItem", count)
	end,
	SetTrainerService = function(tt, index)
		VP:SetPrice(tt, true, "SetTrainerService")
	end,
}

-- Hook the SetItem methods to their respective tooltip events
for method, func in pairs(SetItem) do
    hooksecurefunc(GameTooltip, method, func)
end

-- Hook the OnTooltipSetItem event for the ItemRefTooltip
ItemRefTooltip:HookScript("OnTooltipSetItem", function(tt)
    local item = select(2, tt:GetItem())
    if item then
        local sellPrice, classID = select(11, GetItemInfo(item))
        if sellPrice and sellPrice > 0 and not CheckRecipe(tt, classID, true) then
            SetTooltipMoney(tt, sellPrice, nil, SELL_PRICE_TEXT)
        end
    end
end)

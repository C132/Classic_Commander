

function AnglerAtlas:SplitGold(sourceValue)
    local gold = math.floor(sourceValue / 10000)
    local silver = math.floor((sourceValue - (gold * 10000)) / 100)
    local copper = sourceValue - (gold * 10000) - (silver * 100)
    return gold, silver, copper
end




function AnglerAtlas:Reload()
    AnglerAtlas:loadPlayerData()
    if AnglerAtlas.SKILL.hasFishing then
        local skillMod = AnglerAtlas.SKILL.skillModifier > 0 and "(|cFF00FF00+"..AnglerAtlas.SKILL.skillModifier.."|cFFFFFFFF) " or ""
        AnglerAtlas.UI.playerInfo:SetText("level "..AnglerAtlas.SKILL.level.." "..skillMod..AnglerAtlas.SKILL.rankName.." angler")
    else
        AnglerAtlas.UI.playerInfo:SetText("needs to find a fishing trainer")
    end
    AnglerAtlas.UI:UpdateFishGrid()
    AnglerAtlas.UI:UpdateFishInfo()
    AnglerAtlas.UI:UpdateZoneList()
    AnglerAtlas.UI:UpdateZoneInfo()

end

function AnglerAtlas:ReloadAll()
    AnglerAtlas:Reload()
    AnglerAtlas.UI:UpdateRecipes()
    SetPortraitTexture(AnglerAtlas.UI.characterPortrait.texture, "player");
    AnglerAtlas.UI.playerName:SetText(AnglerAtlas.PLAYER.name)
end





function AnglerAtlas:SelectZone(zoneId, anglerFrame)
    if zoneId == nil then
        AnglerAtlas.UI.selectedZoneHighlight:Hide()
        return  
    end
    
    if AnglerAtlas.STATE.selectedZone == zoneId then
        return
    end
    PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "Master");
    AnglerAtlas.STATE.selectedZone = zoneId
    
    -- print("Selected zone "..zoneId)
    AnglerAtlas.UI.selectedZoneHighlight:Show()
    AnglerAtlas.UI.selectedZoneHighlight:SetPoint("CENTER", anglerFrame, "CENTER", 0, 0)
    AnglerAtlas.UI:UpdateZoneList()
    AnglerAtlas.UI:UpdateZoneInfo()
end

function AnglerAtlas:SelectFish(fishId, anglerFrame)
    if fishId == nil then
        AnglerAtlas.UI.selectedIcon:Hide()
        return
    end
    if AnglerAtlas.STATE.selectedFish == fishId then
        return
    end
    PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN, "Master");  -- Page turn
    PlaySound(1189, "Master") -- Meaty thwack
    -- PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN, "Master");
    AnglerAtlas.STATE.selectedFish = fishId
    AnglerAtlas.STATE.selectedFishData = AnglerAtlas.DATA.fish[AnglerAtlas.STATE.selectedFish]
    AnglerAtlas.UI.selectedIcon:Show()
    AnglerAtlas.UI.selectedIcon:SetPoint("CENTER", anglerFrame, "CENTER", 0, 0)

    local zones = AnglerAtlas:GetSortedZonesForFish(AnglerAtlas.STATE.selectedFish)
    -- print("Zones for fish "..fishId)
    -- for i = 1, #zones do
    --     print(zones[i].name)
    -- end
    
    AnglerAtlas.UI:UpdateFishInfo()
    AnglerAtlas.UI:UpdateRecipes()
    AnglerAtlas:SelectZone(tostring(zones[1].id), AnglerAtlas.UI.zones.zoneButtons[1])

end







function AnglerAtlas:GetSortedZonesForFish(fishId)
    local sortedZones = {}
    for i = 1, #AnglerAtlas.DATA.fish[fishId].fishedIn do
        local zoneId = AnglerAtlas.DATA.fish[fishId].fishedIn[i]
        if AnglerAtlas.DATA.zones[zoneId] ~= nil then
            table.insert(sortedZones, AnglerAtlas.DATA.zones[zoneId])
        end
    end
    table.sort(sortedZones, function(a, b)
        local aPerct = a.fishStats[fishId].catchChance
        local bPerct = b.fishStats[fishId].catchChance
        return aPerct > bPerct
    end)
    return sortedZones
end

function AnglerAtlas:GetSortedFishByCatchLevel()
    local sortedFish = {}
    for i = 0, #AnglerAtlas.DATA.validFish do
        table.insert(sortedFish, AnglerAtlas.DATA.validFish[i])
    end
    table.sort(sortedFish, function(a, b)
        if AnglerAtlas.DATA.fish[a].avoidGetawayLevel == AnglerAtlas.DATA.fish[b].avoidGetawayLevel then
            return AnglerAtlas.DATA.fish[a].minimumFishingLevel < AnglerAtlas.DATA.fish[b].minimumFishingLevel
        end
        return AnglerAtlas.DATA.fish[a].avoidGetawayLevel < AnglerAtlas.DATA.fish[b].avoidGetawayLevel
    end)
    return sortedFish
end

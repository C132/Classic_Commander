
local LibSFDropDown = LibStub("LibSFDropDown-1.5")

function PartyPlanner.UI:CreateDungeonSelect(parent) 

    local dungSelect = CreateFrame("FRAME", "partyPlanner-dungeon-select", parent)
    local ddMenu = LibSFDropDown:CreateButton(dungSelect, 150)
    ddMenu:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -35)
    ddMenu:ddSetSelectedValue(1)

    local function dudFunction(menuButton) end

    local function selectFunction(menuButton)
        ddMenu:ddSetSelectedValue(menuButton.value)
        local inst = PartyPlanner.DATA.INSTANCES[menuButton.value]
        PartyPlanner.DATA.selectedInstance = inst
        PartyPlanner.UI:UpdatePreviewText()
    end

    ddMenu:ddInitialize(function(self, level)
        local info = {}
      
        for i = 1, #PartyPlanner.DATA.INSTANCES do
            local inst = PartyPlanner.DATA.INSTANCES[i]

            if inst.type == "Fill" then
                info.text = "___"
                info.value = i
                info.func = dudFunction
                self:ddAddButton(info, level)
            elseif inst.type == "Dungeon" then
                info.text = inst.name.." ("..inst.minLevel.."-"..inst.maxLevel..")"
                info.value = i
                info.func = selectFunction
                self:ddAddButton(info, level)
            else
                info.text = inst.name
                info.value = i
                info.func = selectFunction
                self:ddAddButton(info, level)
            end
        end
    end)

    local dungeonText = dungSelect:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dungeonText:SetPoint("RIGHT", ddMenu, "LEFT", -10, 0)
    dungeonText:SetText("Select instance: ")

    return dungSelect

end


function PartyPlanner.UI:UpdateDungeonSelect() 

end
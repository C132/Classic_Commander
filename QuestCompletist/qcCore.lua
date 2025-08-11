local TableInsert = table.insert;
local TableRemove = table.remove;
local StringFormat = string.format;
local ToString = tostring;
local BitBand = bit.band

local qcL = qcLocalize

local qcPins = {}
local qcPinFrames = {}
local qcSparePinFrames = {}

local qcCurrentCategoryID = 0
local qcCurrentCategoryQuestCount = 0
local qcCategoryQuests = {}

--[[ Vars ]]--
local qcCurrentScrollPosition = 1
local qcMapTooltip = nil
local qcQuestReputationTooltip = nil
local qcQuestInformationTooltip = nil
local qcToastTooltip = nil
local qcNewDataAlertTooltip = nil
local qcMutuallyExclusiveAlertTooltip = nil

--[[ Constants ]]--
local QCADDON_VERSION = 109.93
local QCADDON_PURGE = true
local QCDEBUG_MODE = false
local QCADDON_CHAT_TITLE = "|CFF9482C9Quest Completist:|r "


local COLOUR_DEATHKNIGHT = "|cFFC41F3B"
local COLOUR_DEMONHUNTER = "|cFFA330C9"
local COLOUR_DRUID = "|cFFFF7D0A"
local COLOUR_HUNTER = "|cFFABD473"
local COLOUR_MAGE = "|cFF69CCF0"
local COLOUR_PALADIN = "|cFFF58CBA"
local COLOUR_PRIEST = "|cFFFFFFFF"
local COLOUR_ROGUE = "|cFFFFF569"
local COLOUR_SHAMAN = "|cFF0070DE"
local COLOUR_WARLOCK = "|cFF9482C9"
local COLOUR_WARRIOR = "|cFFC79C6E"

local QC_ICON_COORDS_NORMAL = {0,0.125,0,0.25}
local QC_ICON_COORDS_REPEATABLE = {0.125,0.25,0.25,0.50}
local QC_ICON_COORDS_DAILY = {0,0.125,0.25,0.50}
local QC_ICON_COORDS_WORLD = {0,0.125,0.25,0.50}
local QC_ICON_COORDS_SPECIAL = {0,0.125,0,0.25}
local QC_ICON_COORDS_WEEKLY = {0,0.125,0,0.25}
local QC_ICON_COORDS_SEASONAL = {0,0.125,0.5,0.75}
local QC_ICON_COORDS_PROFESSION = {0.625,0.75,0,0.25}
local QC_ICON_COORDS_PROGRESS = {0.25,0.375,0.25,0.5}
local QC_ICON_COORDS_READY = {0.125,0.25,0,0.25}
local QC_ICON_COORDS_COMPLETE = {0.125,0.25,0.5,0.75}
local QC_ICON_COORDS_UNATTAINABLE = {0.25,0.375,0.5,0.75}
local QC_ICON_COORDS_ITEMDROPSTANDARD = {0.375,0.5,0,0.25}
local QC_ICON_COORDS_ITEMDROPREPEATABLE = {0.375,0.5,0.25,0.5}
local QC_ICON_COORDS_CLASS = {0.5,0.625,0,0.25}
local QC_ICON_COORDS_KILL = {0.25,0.375,0,0.25}
--
local QC_ICON_COORDS_UNAVAILABLE = {0.25,0.375,0,0.25}

local qcCategoryDropDownMenu = CreateFrame("Frame", "qcCategoryDropDownMenu")

--[[ Bitwise Values ]]--
qcFactionBits = {
	["ALLIANCE"]=1,["HORDE"]=2,["NEUTRAL"]=4,
}
qcRaceBits = {
	["HUMAN"]=1,["ORC"]=2,["DWARF"]=4,["NIGHTELF"]=8,
	["SCOURGE"]=16,["TAUREN"]=32,["GNOME"]=64,["TROLL"]=128,
	["GOBLIN"]=256,["BLOODELF"]=512,["DRAENEI"]=1024,["WORGEN"]=2048,
	["PANDAREN"]=4096,["VOIDELF"]=8192,["NIGHTBORNE"]=16384,
	["HIGHMOUNTAINTAUREN"]=32768,["LIGHTFORGEDDRAENEI"]=65536,
	["DARKIRONDWARF"]=131072,["MAGHARORC"]=262144,
	["ZANDALARITROLL"]=524288,["KULTIRAN"]=1048576,
	["VULPERA"]=2097152,["MECHAGNOME"]=4194304,["DRACTHYR"]=8388608,["EARTHENDWARF"]=16777216
}
qcClassBits = {
	["WARRIOR"]=1,["PALADIN"]=2,["HUNTER"]=4,["ROGUE"]=8,["PRIEST"]=16,
	["DEATHKNIGHT"]=32,["SHAMAN"]=64,["MAGE"]=128,["WARLOCK"]=256,["DRUID"]=512,
	["MONK"]=1024,["DEMONHUNTER"]=2048,["EVOKER"]=4096
}
qcProfessionBits = {
	[171]=1,		-- Alchemy
	[164]=2,		-- Blacksmithing
	[333]=4,		-- Enchanting
	[202]=8,		-- Engineering
	[773]=16,		-- Inscription
	[755]=32,		-- Jewelcrafting
	[165]=64,		-- Leatherworking
	[197]=128,		-- Tailoring
	[182]=256,		-- Herbalism
	[186]=512,		-- Mining
	[393]=1024,		-- Skinning
    [794]=2048,   	-- Archaeology
	[129]=4096,		-- First Aid
	[185]=8192,		-- Cooking
	[356]=16384,	-- Fishing
	[20222]=32768  	-- Gnomish Engineering
}	
local primaryProfessionBits = {
	[171]=1,		-- Alchemy
	[164]=2,		-- Blacksmithing
	[333]=4,		-- Enchanting
	[202]=8,		-- Engineering
	[773]=16,		-- Inscription
	[755]=32,		-- Jewelcrafting
	[165]=64,		-- Leatherworking
	[197]=128,		-- Tailoring
	[182]=256,		-- Herbalism
	[186]=512,		-- Mining
	[393]=1024,		-- Skinning
--	[794]=2048,		-- Archaeology
--	[129]=4096,		-- First Aid
--	[185]=8192,		-- Cooking
--	[356]=16384,	-- Fishing
}
local secondaryProfessionIDs = {
    [794] = true,   -- Archaeology
    [356] = true,   -- Fishing
    [185] = true,   -- Cooking
}
qcCovenantsBits = {
	[0]=1,		-- None
	[1]=2,		-- Kyrian
	[2]=4,		-- Venthyr
	[3]=8,		-- NightFae
	[4]=16,		-- Necrolord
}
qcSubQuestCatagoryBits = {
	["Warfront"]=1,
	["Bonus"]=2,
	["Legion Assault"]=4,
	["Assault"]=8,
}
qcQuestFactionLevelBits = {
	["Hated"]=1,
	["NEUTRAL"]=2,
	["Friendly"]=4,
	["Honored"]=8,
	["Revered"]=16,
	["Exalted"]=32,
}
local qcHolidayDates = {
	[1]={"240920","241006"},		-- Brewfest 2024
	[2]={"180425","180502"},		-- Children's Week 2018
	[4]={"181101","181103"},		-- Day of the Dead 2018
	[8]={"241216","250102"},		-- Feast of Winter Veil 2024-2025
	[16]={"241018","241101"},		-- Hallow's End 2024
	[32]={"180918","180925"},		-- Harvest Festival 2018
	[64]={"190205","190219"},		-- Love is in the Air 2019
	[128]={"190128","190211"},		-- Lunar Festival 2019
	[256]={"240621","240705"},		-- Midsummer Fire Festival 2024
	[512]={"180402","180409"},		-- Noblegarden 2018
	[1024]={"181119","181126"},		-- Pilgrim's Bounty 2018
	[2048]={"180919","180920"},		-- Pirates' Day 2018
	[4096]={"180919","180920"},		-- Trial of Styles
}

--[[ Constants for the Key Bindings & Slash Commands ]]--
BINDING_HEADER_QCQUESTCOMPLETIST = "Quest Completist";
BINDING_NAME_QCTOGGLEFRAME = "Toggle Frame";
SLASH_QUESTCOMPLETIST1 = "/qc"
SLASH_QUESTCOMPLETIST2 = "/questc"

SlashCmdList["QUESTCOMPLETIST"] = function(msg, editbox)
	ShowUIPanel(qcQuestCompletistUI)
end

function qcCopyTable(qcTable)
	if not (qcTable) then return nil end
	if not (type(qcTable) == "table") then return nil end
	local qcNewTable = {}
	for qcKey, qcValue in pairs(qcTable) do
		if (type(qcValue) == "table") then
			qcNewTable[qcKey] = qcCopyTable(qcValue)
		else
			qcNewTable[qcKey] = qcValue
		end
	end
	return qcNewTable
end

function qcUpdateCurrentCategoryText(categoryId)
	qcQuestCompletistUI.qcSelectedCategory:SetText("#")
	for i, e in pairs(qcQuestCategories) do
		if (e[1] == categoryId) then
			qcQuestCompletistUI.qcSelectedCategory:SetText(e[2])
			break
		end
	end
end

local function qcUpdateMutuallyExclusiveCompletedQuest(qcQuestID)
	if (qcMutuallyExclusive[qcQuestID]) then
		for qcMutuallyExclusiveIndex, qcMutuallyExclusiveEntry in pairs(qcMutuallyExclusive[qcQuestID]) do
			if (qcQuestDatabase[qcMutuallyExclusiveEntry]) then
				qcCompletedQuests[qcMutuallyExclusiveEntry] = {["C"]=1}
			end
		end
	end
end

local function qcUpdateSkippedBreadcrumbQuest(qcQuestID)
	if (qcBreadcrumbQuests[qcQuestID]) then
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[qcQuestID]) do
			if (qcQuestDatabase[qcBreadcrumbEntry]) then
				qcCompletedQuests[qcBreadcrumbEntry] = {["C"]=1}
			end
		end
	end
end

local function qcGetSearchQuests(searchText)
	local tableInsert = table.insert
	local stringUpper = string.upper
	local stringFind = string.find
	wipe(qcSearchQuests) -- TODO: Where is this table, and we dont seem to be returning it correctly.
	local holdingTable = {}
	for qcIndex, qcEntry in pairs(qcQuestDatabase) do
		if (stringFind(stringUpper(qcEntry[2]),searchText,1,true)) then
			tableInsert(holdingTable,qcEntry)
		end
	end
	qcSearchQuests = qcCopyTable(holdingTable)
end

local function qcGetCategoryQuests(categoryId, searchText)
    local tableInsert = table.insert
    local stringUpper = string.upper
    local tableSort = table.sort
    local holdingTable = {}
    wipe(qcCategoryQuests)

    if (searchText) then
        local stringfind = string.find
        for i, e in pairs(qcQuestDatabase) do
            if (stringfind(stringUpper(e[2]), searchText, 1, true)) then
                tableInsert(holdingTable, e)
            end
        end
        qcCategoryQuests = qcCopyTable(holdingTable)
        return nil
    end

    local tableRemove = table.remove
    local BitBand = bit.band
    for i, e in pairs(qcQuestDatabase) do
        if (e[5] == categoryId) then
            tableInsert(holdingTable, e)
        end
    end
    qcCategoryQuests = qcCopyTable(holdingTable)
	
	-- Quest Completed
	if (qcSettings.QC_L_HIDE_COMPLETED == 1) then
		for i = #qcCategoryQuests, 1, -1 do
			if (qcCompletedQuests[qcCategoryQuests[i][1]]) then
				if (qcCompletedQuests[qcCategoryQuests[i][1]]["C"] == 1) or (qcCompletedQuests[qcCategoryQuests[i][1]]["C"] == 2) then
					tableRemove(qcCategoryQuests,i)
				end
			end
		end
	end
	-- Quest Hide low level
		if (qcSettings.QC_L_HIDE_LOWLEVEL == 1) then
			local playerLevel = UnitLevel("player")
			local trivialLevelRange = UnitQuestTrivialLevelRange("player")
			local greenCutoff = playerLevel - trivialLevelRange
			
			for i = #qcCategoryQuests, 1, -1 do
				local questId = qcCategoryQuests[i][1]
				
				if qcQuestDatabase[questId] then
					local questLevel = qcQuestDatabase[questId][3] or 0
					
					if questLevel < greenCutoff then
						table.remove(qcCategoryQuests, i)
					end
				end
			end
		end
	--  Bitband Code for Hideing Daily quest
		if (qcSettings.QC_L_HIDE_DAILYQUEST == 1) then
			local questType = 4
			for i = #qcCategoryQuests, 1, -1 do
				if (BitBand(qcCategoryQuests[i][6], questType) == 4) then
					tableRemove(qcCategoryQuests,i)
			end
		end
	end
	--  Bitband Code for Hideing Repeatable quest	
		if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == 1) then
			local questType = 2
			for i = #qcCategoryQuests, 1, -1 do
				if (BitBand(qcCategoryQuests[i][6], questType) == 2) then
					tableRemove(qcCategoryQuests,i)
			end
		end
	end
	--  Bitband Code for Hideing World quest	
		if (qcSettings.QC_L_HIDE_WORLDQUEST == 1) then
			local questType = 128
			for i = #qcCategoryQuests, 1, -1 do
				if (BitBand(qcCategoryQuests[i][6], questType) == 128) then
					tableRemove(qcCategoryQuests,i)
			end
		end
	end
	-- Hide Other Professions quests
	if (qcSettings.QC_L_HIDE_PROFESSION == 1) then
		local prof1, prof2 = GetProfessions()
		local professionBitmask = 0
		if prof1 then
			local _, _, _, _, _, _, skillLine1 = GetProfessionInfo(prof1)
			professionBitmask = professionBitmask + (qcProfessionBits[skillLine1] or 0)
		end
		if prof2 then
			local _, _, _, _, _, _, skillLine2 = GetProfessionInfo(prof2)
			professionBitmask = professionBitmask + (qcProfessionBits[skillLine2] or 0)
		end
		
		for i = #qcCategoryQuests, 1, -1 do
			local professionValue = qcCategoryQuests[i][10]
			if professionValue ~= 0 and BitBand(professionValue, professionBitmask) == 0 then
				tableRemove(qcCategoryQuests, i)
			end
		end
	end
	-- Hide other Faction Quest
		if (qcSettings.QC_ML_HIDE_FACTION == 1) then
		local playerFaction, _ = UnitFactionGroup("player")
		local factionFlag = qcFactionBits[stringUpper(playerFaction)]
		for i = #qcCategoryQuests, 1, -1 do
			if (BitBand(qcCategoryQuests[i][7], factionFlag) == 0) then
				tableRemove(qcCategoryQuests,i)
			end
		end
	end
	-- Hide other Race`s and Class Quest
		if (qcSettings.QC_ML_HIDE_RACECLASS == 1) then
		local _, playerRace = UnitRace("player")
		local raceFlag = qcRaceBits[stringUpper(playerRace)]
		local _, playerClass = UnitClass("player")
		local classFlag = qcClassBits[stringUpper(playerClass)]
		for i = #qcCategoryQuests, 1, -1 do
			if ((BitBand(qcCategoryQuests[i][8], raceFlag) == 0) or (BitBand(qcCategoryQuests[i][9], classFlag) == 0)) then
				tableRemove(qcCategoryQuests,i)
			end
		end
	end
		-- Hide other Covenant Quests
	if (qcSettings.QC_ML_HIDE_COVENANTS == 1) then
		-- Apply Covenant filtering only for game version 8.x and above
		if tonumber(GetBuildInfo():match("^(%d+)")) >= 8 then
			local playerCovenantID = C_Covenants.GetActiveCovenantID()
			local playerCovenantBit = qcCovenantsBits[playerCovenantID] or 0

			for i = #qcCategoryQuests, 1, -1 do
				local questId = qcCategoryQuests[i][1] -- Get the quest ID
				local questCovenant = qcQuestDatabase[questId] and qcQuestDatabase[questId][12] -- Retrieve covenant bit from the database (index 12)

				-- Ensure questCovenant is not nil before proceeding
				if questCovenant and questCovenant ~= 0 and BitBand(questCovenant, playerCovenantBit) == 0 then
					table.remove(qcCategoryQuests, i)
				end
			end
		end
	end

		-- Hide Warband Quests
	if (qcSettings["QC_ML_HIDE_WARBANDS"] == 1) then
		-- Apply Warband filtering only for game version 11.x and above
		if tonumber(GetBuildInfo():match("^(%d+)")) >= 11 then
			for i = #qcCategoryQuests, 1, -1 do
				local questId = qcCategoryQuests[i][1]
				if C_QuestLog.IsQuestFlaggedCompletedOnAccount(questId) then
					table.remove(qcCategoryQuests, i)
				end
			end
		end
	end
	
    -- Sorting quests
	if (qcSettings.SORT == 1) then
		tableSort(qcCategoryQuests,function(a,b) return (a[3]<b[3] or (a[3] == b[3] and a[2]<b[2])) end)
	elseif (qcSettings.SORT == 2) then
		tableSort(qcCategoryQuests,function(a,b) return a[2]<b[2] end)
	else
		tableSort(qcCategoryQuests,function(a,b) return (a[3]<b[3] or (a[3] == b[3] and a[2]<b[2])) end)
	end
end

--Beta Reset Daily and Weekly Start
-- Function to reset daily quests (type 4)
function ResetDailyQuests()
    if quests == nil then
        print("No quests to reset. The quests table is nil.")
        return
    end
    
    for questID, questData in pairs(quests) do
        if questData.type == 4 then  -- Type 4 for daily quests
            questData.status = "incomplete"
        end
    end
end

-- Function to reset weekly quests (type 128)
function ResetWeeklyQuests()
    if quests == nil then
        print("No quests to reset. The quests table is nil.")
        return
    end
    
    for questID, questData in pairs(quests) do
        if questData.type == 128 then  -- Type 128 for weekly quests
            questData.status = "incomplete"
        end
    end
end


--Beta Reset Daily and Weekly End


function qcUpdateQuestList(categoryId, startIndex, searchText) -- *
	if not (qcQuestCompletistUI:IsVisible()) then return nil end

	-- 🔧 Ensure qcCompletedQuests is initialized
	qcCompletedQuests = qcCompletedQuests or {}

	local stringFormat = string.format
	if (categoryId) then
		qcQuestCompletistUI.qcSearchBox:SetText("")
		qcCurrentCategoryID = categoryId
		qcUpdateCurrentCategoryText(categoryId)
		qcGetCategoryQuests(categoryId)
		qcCurrentCategoryQuestCount = (#qcCategoryQuests)
		if (qcCurrentCategoryQuestCount < 16) then
			qcMenuSlider:SetMinMaxValues(1, 1)
		else
			qcMenuSlider:SetMinMaxValues(1, qcCurrentCategoryQuestCount - 15)
		end
		qcMenuSlider:SetValue(startIndex)
	else
		if (searchText) then
			qcGetCategoryQuests(nil, searchText)
			qcCurrentCategoryQuestCount = (#qcCategoryQuests)
			qcQuestCompletistUI.qcSelectedCategory:SetText("Search Results")
			if (qcCurrentCategoryQuestCount < 16) then
				qcMenuSlider:SetMinMaxValues(1, 1)
			else
				qcMenuSlider:SetMinMaxValues(1, qcCurrentCategoryQuestCount - 15)
			end
			qcMenuSlider:SetValue(startIndex)
		end
	end

	qcQuestCompletistUI.qcCurrentCategoryQuestCount:SetText(stringFormat("%d Quests Found", qcCurrentCategoryQuestCount))

	for i = 1, 16 do
		local offset = ((i + startIndex) - 1)
		local questRecord = _G["qcMenuButton" .. i]

		if (qcCurrentCategoryQuestCount >= offset) then
			local e = qcCategoryQuests[offset]
			local questId = e[1]
			local questType = e[6]
			local questFaction = e[7]
			local questRequired = e[15] -- Beta Code

			questRecord.QuestName:SetText(stringFormat("[%d] %s", e[3], e[2]))
			questRecord.QuestID = questId

			-- Icon & color by type
			if (questType == 1) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_NORMAL))
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 2) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_REPEATABLE))
				questRecord.QuestName:SetTextColor(0.094, 0.627, 0.941, 1.0)
			elseif (questType == 4) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_DAILY))
				questRecord.QuestName:SetTextColor(0.094, 0.627, 0.941, 1.0)
			elseif (questType == 8) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_SPECIAL))
				questRecord.QuestName:SetTextColor(1.0, 0.616, 0.086, 1.0)
			elseif (questType == 16) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_NORMAL))
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 32) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_PROFESSION))
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 64) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_SEASONAL))
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			elseif (questType == 128) then
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_WORLD)) -- Maybe change this icon
				questRecord.QuestName:SetTextColor(0.094, 0.627, 0.941, 1.0)
			else
				questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_NORMAL))
				questRecord.QuestName:SetTextColor(1.0, 1.0, 1.0, 1.0)
			end

			questRecord.QuestIcon:Show()

			-- Faction Icon
			if ((questFaction == 0) or (questFaction == 3)) then
				questRecord.FactionIcon:Hide()
			elseif (questFaction == 1) then
				questRecord.FactionIcon:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\AllianceIcon")
				questRecord.FactionIcon:Show()
			elseif (questFaction == 2) then
				questRecord.FactionIcon:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\HordeIcon")
				questRecord.FactionIcon:Show()
			else
				questRecord.FactionIcon:Hide()
			end

			-- Quest log status
			local questLogIndex = GetQuestLogIndexByID(questId)
			if questLogIndex > 0 then
				local isComplete
				_, _, _, _, _, isComplete = GetQuestLogTitle(questLogIndex)
				if isComplete == nil then
					questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_PROGRESS))
					questRecord.QuestName:SetTextColor(0.580, 0.588, 0.580, 1.0)
				elseif isComplete == 1 then
					questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_READY))
					questRecord.QuestName:SetTextColor(1.0, 0.820, 0.0, 1.0)
				elseif isComplete == -1 then
					questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_NORMAL))
					questRecord.QuestName:SetTextColor(0.937, 0.149, 0.063, 1.0)
				end
			end

			-- Completed quest status
			local questCompleteData = qcCompletedQuests[questId]
			if questCompleteData then
				if not ((questType == 2) or (questType == 4) or (questType == 128)) then
					if (questCompleteData["C"] == 1) then
						questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_COMPLETE))
						questRecord.QuestName:SetTextColor(0.0, 1.0, 0.0, 1.0)
					elseif (questCompleteData["C"] == 2) then
						questRecord.QuestIcon:SetTexCoord(unpack(QC_ICON_COORDS_UNATTAINABLE))
						questRecord.QuestName:SetTextColor(0.77, 0.12, 0.23, 1.0)
					end
				end
			end

			questRecord:Show()
			questRecord:Enable()
		else
			questRecord.QuestName:SetText("#")
			questRecord:Hide()
			questRecord:Disable()
		end
	end
end


-- Search function start

-- Function to handle when the search box gains focus
function qcSearchBox_OnEditFocusGained(self)
    if self:GetText() == "Search" then
        self:SetText("")
        self:SetTextColor(1, 1, 1)  -- Set text color to normal
    end
    if self.Instructions then
        self.Instructions:SetText("Search")
    end
end

-- Function to handle when the search box loses focus
function qcSearchBox_OnEditFocusLost(self)
    if self:GetText() == "" then
        self:SetText("Search")
        self:SetTextColor(0.5, 0.5, 0.5)  -- Set text color to grey to indicate placeholder
        if self.Instructions then
            self.Instructions:SetText("Search")
        end
    end

    local searchText = string.upper(self:GetText())
    if not (searchText == "") and searchText ~= "SEARCH" then
        qcUpdateQuestList(nil, 1, searchText)
    else
        qcUpdateQuestList(qcCurrentCategoryID, 1)
    end
end

-- Function to handle when the text in the search box changes
function qcSearchBox_OnTextChanged(self, userInput)
    if userInput == true then
        local searchText = self:GetText()
        self.Instructions:SetText("")
        -- Clear placeholder text when the user starts typing
        if searchText == "S" or searchText == "s" or searchText:sub(1, 1):upper() ~= "S" then
            if self:GetText() == "Search" then
                self:SetText("")
                self:SetTextColor(1, 1, 1)  -- Set text color to normal
                searchText = ""
            end
        end

        searchText = string.upper(self:GetText())
        if not (searchText == "") and searchText ~= "SEARCH" then
            qcUpdateQuestList(nil, 1, searchText)
        else
            qcUpdateQuestList(qcCurrentCategoryID, 1)
        end
    end
end

-- Event handler for ADDON_LOADED to initialize the search box
local function OnAddonLoaded(self, event, addonName)
    if addonName == "QuestCompletist" then
        local qcSearchBox = _G["qcSearchBox"]
        if qcSearchBox then
            qcSearchBox:SetText("Search")  -- Set default text
            qcSearchBox:SetTextColor(0.5, 0.5, 0.5)  -- Set default text color to grey
            if qcSearchBox.Instructions then
                qcSearchBox.Instructions:SetText("Search")
            end
            qcSearchBox:HookScript("OnEditFocusGained", qcSearchBox_OnEditFocusGained)
            qcSearchBox:HookScript("OnEditFocusLost", qcSearchBox_OnEditFocusLost)
            qcSearchBox:HookScript("OnTextChanged", qcSearchBox_OnTextChanged)
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end

-- Create a frame to listen for the ADDON_LOADED event
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnAddonLoaded)


-- Search function end

function qcScrollUpdate(value) -- *
	if not (qcCurrentScrollPosition == value) then
		qcCurrentScrollPosition = value
		qcUpdateQuestList(nil, value)
	end
end

function qcQueryQuestFlaggedComplete()

	local qcChecked = 0
	local qcNewFlagged = 0

	for qcIndex, qcEntry in pairs(qcQuestDatabase) do
		qcChecked = (qcChecked + 1)
		if (C_QuestLog.IsQuestFlaggedCompleted(qcIndex)) then
			if not (qcQuestDatabase[qcIndex][6] == 2) or 
				   (qcQuestDatabase[qcIndex][6] == 4) or 
				   (qcQuestDatabase[qcIndex][6] == 128) then
				if (qcCompletedQuests[qcIndex] == nil) then
					qcNewFlagged = (qcNewFlagged + 1)
				end
				qcCompletedQuests[qcIndex] = {["C"]=1}
				qcUpdateMutuallyExclusiveCompletedQuest(qcIndex)
				qcUpdateSkippedBreadcrumbQuest(qcIndex)
			end
		end
	end

	if (qcNewFlagged > 0) then
		print(string.format("%s%d quests were checked, and %d previously completed quest(s) have now been updated as such.",QCADDON_CHAT_TITLE,qcChecked,qcNewFlagged))
		qcUpdateQuestList(nil,qcMenuSlider:GetValue())
	end
	
end

local function qcQuestQueryCompleted()
    local qcCountReturned = 0
    local qcNewFlagged = 0
    local qcCompletedTable = {}

    -- Determine the API to use based on game version
    local gameVersion = tonumber(GetBuildInfo():match("^(%d+)"))
    if gameVersion >= 8 then
        -- Retail API
        C_QuestLog.GetAllCompletedQuestIDs(qcCompletedTable)
    else
        -- Classic API
        GetQuestsCompleted(qcCompletedTable)
    end

    for qcIndex, qcEntry in pairs(qcCompletedTable) do
        qcCountReturned = qcCountReturned + 1
        if qcQuestDatabase[qcIndex] then
            if qcQuestDatabase[qcIndex][6] ~= 2 or qcQuestDatabase[qcIndex][6] == 3 then
                if not qcCompletedQuests[qcIndex] then
                    qcNewFlagged = qcNewFlagged + 1
                end
                qcCompletedQuests[qcIndex] = { ["C"] = 1 }
                qcUpdateMutuallyExclusiveCompletedQuest(qcIndex)
                qcUpdateSkippedBreadcrumbQuest(qcIndex)
            end
        end
    end

    if qcCountReturned == 0 then
--     print(string.format("%sNo quests were returned from the server query. Attempting to check each quest individually...", QCADDON_CHAT_TITLE))
        qcQueryQuestFlaggedComplete()
    end

    if qcNewFlagged > 0 then
        print(string.format("%s%d previously completed quest(s) have now been updated as such.", QCADDON_CHAT_TITLE, qcNewFlagged))
        qcUpdateQuestList(nil, qcMenuSlider:GetValue())
    end

--    print(string.format("%sQuery completed.", QCADDON_CHAT_TITLE))
end

local function qcClearUpdateCache()
	wipe(qcCompletedQuests)
	print(string.format("%sCache Cleared.",QCADDON_CHAT_TITLE))
end

local function qcPurgeCollectedCache()
	if (qcCollectedQuests == nil) then qcCollectedQuests = {} end
	if (qcProgressComplete == nil) then qcProgressComplete = {} end
	wipe(qcCollectedQuests)
	wipe(qcProgressComplete)
	print(string.format("%sCollected Cache Purged.",QCADDON_CHAT_TITLE))
end

function qcMenuMouseWheel(self, delta) -- *
	local position = qcMenuSlider:GetValue()
	if (delta < 0) and (position < qcCurrentCategoryQuestCount) then
		qcMenuSlider:SetValue(position + 2)
	elseif (delta > 0) and (position > 1) then
		qcMenuSlider:SetValue(position - 2)
	end
end

function qcCategoryDropdown_Initialize(self, level, menuList)

	local stringformat = string.format
	local qcMenuData = {}
	
	if (level == 1) then
		for qcMenuIndex, qcMenuEntry in ipairs(qcCategoryMenu) do
			if (qcMenuEntry[3]) then
				qcMenuData = {text=stringformat("   %s",qcMenuEntry[2]),isTitle=false,notCheckable=true,hasArrow=true,value=qcMenuEntry[1]}
			else
				qcMenuData = {text=qcMenuEntry[2],isTitle=true,notCheckable=true,hasArrow=false}
			end
			UIDropDownMenu_AddButton(qcMenuData, level)
		end
	elseif (level == 2) then
		local qcParentValue = UIDROPDOWNMENU_MENU_VALUE
		for qcMenuIndex, qcMenuEntry in ipairs(qcCategoryMenu) do
			if (qcMenuEntry[1] == qcParentValue) then
				for qcSubmenuIndex, qcSubmenuEntry in ipairs(qcMenuEntry[3]) do
					if (qcSubmenuEntry[3]) then
						qcMenuData = {text=stringformat("   %s",qcSubmenuEntry[2]),isTitle=false,notCheckable=true,hasArrow=true,value=qcSubmenuEntry[1]}
					else
						if (tonumber(qcSubmenuEntry[1])) then
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcQuestCompletistUI.qcSearchBox:SetText("");qcUpdateQuestList(arg1,1);CloseDropDownMenus();end}
						else
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcProcessMenuAction(button,arg1);end}
						end
					end
					UIDropDownMenu_AddButton(qcMenuData, level)
				end
				break
			end
		end
	elseif (level == 3) then
		local qcParentValue = UIDROPDOWNMENU_MENU_VALUE
		for qcMenuIndex, qcMenuEntry in ipairs(qcCategoryMenu) do
			if (qcMenuEntry[3]) then
				for qcSubmenuIndex, qcSubmenuEntry in ipairs(qcMenuEntry[3]) do
					if (qcSubmenuEntry[1] == qcParentValue) then
						if (tonumber(qcSubmenuEntry[1])) then
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcQuestCompletistUI.qcSearchBox:SetText("");qcUpdateQuestList(arg1,1);CloseDropDownMenus();end}
						else
							qcMenuData = {text=qcSubmenuEntry[2],isTitle=false,notCheckable=false,hasArrow=false,value=qcSubmenuEntry[1],arg1=qcSubmenuEntry[1],func=function(button,arg1) qcProcessMenuAction(button,arg1);end}
						end
						UIDropDownMenu_AddButton(qcMenuData, level)
					end
					break
				end
			else
				qcMenuData = {text=qcMenuEntry[2],isTitle=true,notCheckable=true,hasArrow=false}
			end
		end
	end

end
-- Assuming qcMenu is defined somewhere in qccore.lua as the list of menu items
-- Function to initialize the dropdown menu
local function InitializeCategoryDropDownMenu(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    local menu = menuList or qcMenu
    
    for _, item in ipairs(menu) do
        info.text = item.text
        info.arg1 = item.arg1
        info.func = item.func
        info.notCheckable = true
        info.hasArrow = item.hasArrow
        info.menuList = item.menuList
        UIDropDownMenu_AddButton(info, level)
    end
end

-- Function to handle the dropdown button click
function qcCategoryDropdownButton_OnClick(self, button, down)
    local dropdown = CreateFrame("Frame", "qcCategoryDropDownMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(dropdown, InitializeCategoryDropDownMenu, "MENU")
    ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
end

-- Function to load the dropdown menu
function qcCategoryDropdown_OnLoad(self)
    UIDropDownMenu_Initialize(self, InitializeCategoryDropDownMenu)
end

-- Function to process menu actions
function qcProcessMenuAction(button, arg1)
    if (arg1 == "PERFORMSERVERQUERY") then
        print(string.format("%s%s", QCADDON_CHAT_TITLE, qcL.QUERYREQUESTED))
        qcQuestQueryCompleted()
        CloseDropDownMenus()
    elseif (arg1 == "CLEARUPDATECACHE") then
        print(string.format("%s%s", QCADDON_CHAT_TITLE, "Clearing your update Cache..."))
        qcClearUpdateCache()
        CloseDropDownMenus()
    elseif (arg1 == "SORTLEVEL") then
        qcSettings.SORT = 1
        qcQuestCompletistUI.qcSearchBox:SetText("")
        qcUpdateQuestList(qcCurrentCategoryID, qcMenuSlider:GetValue())
        CloseDropDownMenus()
    elseif (arg1 == "SORTALPHA") then
        qcSettings.SORT = 2
        qcQuestCompletistUI.qcSearchBox:SetText("")
        qcUpdateQuestList(qcCurrentCategoryID, qcMenuSlider:GetValue())
        CloseDropDownMenus()
    end
end

function qcProcessMenuSelection(self, arg1)
    qcQuestCompletistUI.qcSearchBox:SetText("")
    qcUpdateQuestList(arg1, 1)
    CloseDropDownMenus()
end

local function qcZoneChangedNewArea() -- *
--	SetMapToCurrentZone()
	local id = C_Map.GetBestMapForUnit("player")
	if (qcAreaIDToCategoryID[id]) then
		qcCurrentCategoryID = qcAreaIDToCategoryID[id]
		qcUpdateQuestList(qcCurrentCategoryID,1)
	end
end

-- Start Tooltip when mouse over quest name
-- Ensure the necessary tables from qcQuest.lua are loaded
local qcAreaIDToCategoryID = qcAreaIDToCategoryID or {} -- Maps zone ID to internal category ID
local qcQuestCategories = qcQuestCategories or {} -- Maps internal category ID to zone name

-- Function to get the zone name from a zone ID with enhanced handling for array-style lookup
function GetZoneNameFromZoneID(zoneId)
    -- First, check if the zoneId is present in qcAreaIDToCategoryID
    local categoryID = qcAreaIDToCategoryID[zoneId]
    if not categoryID then
        -- Fall back to a default message if the mapping is missing
        return "Unknown Zone (Invalid Area ID)"
    end

    -- Now, search through qcQuestCategories for the categoryID
    local zoneName = nil
    for _, categoryData in ipairs(qcQuestCategories) do
        if categoryData[1] == categoryID then
            zoneName = categoryData[2] -- Retrieve the zone name
            break
        end
    end

    if not zoneName or zoneName == "" then
        -- Handle cases where the zone name is missing or empty
        return "Unknown Zone (No Zone Name)"
    end

    -- Return the valid zone name if all checks passed
    return zoneName
end

-- Function to perform a topological sort on storyline quests
local function topologicalSortStorylineQuests(storylineQuests)
    local sortedQuests = {}
    local visited = {}
    local tempMarked = {}

    -- Function to visit each node (quest) recursively
    local function visit(questId)
        if tempMarked[questId] then
            return -- Detect cycles, but we assume there's no cycle in quest prerequisites
        end
        if not visited[questId] then
            tempMarked[questId] = true
            local prereqQuestId = qcQuestDatabase[questId][14] -- Get the prerequisite quest ID
            if prereqQuestId and prereqQuestId ~= 0 then
                visit(prereqQuestId) -- Recursively visit the prerequisite quest
            end
            tempMarked[questId] = false
            visited[questId] = true
            table.insert(sortedQuests, questId) -- Add to sorted list
        end
    end

    -- Visit all quests in the storyline
    for _, questData in ipairs(storylineQuests) do
        visit(questData[1]) -- questData[1] is the quest ID
    end

    return sortedQuests
end

-- Function to update the quest tooltip
function qcUpdateTooltip(index)
    local stringFormat = string.format
    local questId = _G["qcMenuButton" .. index].QuestID

    if not (questId == nil) then
        qcQuestInformationTooltip:SetOwner(qcQuestCompletistUI, "ANCHOR_BOTTOMRIGHT", -30, 500)
        qcQuestInformationTooltip:ClearLines()
        qcQuestInformationTooltip:SetHyperlink(string.format("quest:%d", questId))
        qcQuestInformationTooltip:AddLine(" ")

        if not C_AddOns.IsAddOnLoaded("AllTheThings") then
            qcQuestInformationTooltip:AddDoubleLine("Quest ID:", string.format("|cFF69CCF0%d|r", questId))
        end

        if not C_AddOns.IsAddOnLoaded("AllTheThings") then
            qcQuestInformationTooltip:AddLine(" ")
        end

        -- Storyline information
        local storylineId = qcQuestDatabase[questId][13]
        if storylineId and qcQuestLines[storylineId] then
            local storylineName = qcQuestLines[storylineId]
            qcQuestInformationTooltip:AddDoubleLine("Storyline:", string.format("%s%s", COLOUR_HUNTER, storylineName))
            qcQuestInformationTooltip:AddLine(" ")

            -- Collect all quests in this storyline
            local storylineQuests = {}
            for id, questData in pairs(qcQuestDatabase) do
                if questData[13] == storylineId then
                    table.insert(storylineQuests, questData)
                end
            end

            -- Sort the quests by prerequisite dependencies
            local sortedQuestIds = topologicalSortStorylineQuests(storylineQuests)

            -- Display each quest in the storyline with its completion status
            for _, sortedQuestId in ipairs(sortedQuestIds) do
                local questData = qcQuestDatabase[sortedQuestId]
                local questName = questData[2]
                local questStatus

                if C_QuestLog.IsOnQuest(sortedQuestId) then
                    -- Highlight the current quest's status if it's being tracked
                    questStatus = "|cFFFFFF00You are on this quest|r"
                else
                    questStatus = C_QuestLog.IsQuestFlaggedCompleted(sortedQuestId) and "|cFF00FF00Completed|r" or "|cFFFF0000Not Completed|r"
                end

                qcQuestInformationTooltip:AddDoubleLine(" - " .. questName, questStatus)
            end

            qcQuestInformationTooltip:AddLine(" ")
        end

        -- Prerequisite quest logic
        local prereqQuestId = qcQuestDatabase[questId][14]
        if prereqQuestId and prereqQuestId ~= 0 then
            local prereqQuestInfo = qcQuestDatabase[prereqQuestId]
            local prereqQuestName = prereqQuestInfo and prereqQuestInfo[2] or "Unknown Quest"
            local prereqQuestStatus = C_QuestLog.IsQuestFlaggedCompleted(prereqQuestId) and "|cFF00FF00Completed|r" or "|cFFFF0000Not Completed|r"
            qcQuestInformationTooltip:AddDoubleLine("Prerequired Completed Quest:", string.format("%s - %s", prereqQuestName, prereqQuestStatus))
            qcQuestInformationTooltip:AddLine(" ")
        end
		-- Renown and Faction requirements Start
        -- Check for game version 8.x and above before handling renown
        if tonumber(GetBuildInfo():match("^(%d+)")) >= 8 then
            local renownInfo = qcRenownLevelRequirements[questId]

            if renownInfo then
                if type(renownInfo) == "table" then
                    local factionId = renownInfo[1]
                    local requiredRenownLevel = renownInfo[2]
                    local factionName = qcFactions[factionId] or "Unknown Faction"
                    local currentRenownLevel = C_MajorFactions.GetCurrentRenownLevel(factionId)

                    qcQuestInformationTooltip:AddDoubleLine("Required Faction:", string.format("%s%s", COLOUR_DRUID, factionName))

                    if currentRenownLevel then
                        if currentRenownLevel >= requiredRenownLevel then
                            qcQuestInformationTooltip:AddDoubleLine("Required Renown Level:", string.format("|cFF00FF00%d (Requirement Fulfilled)|r", requiredRenownLevel))
                        else
                            qcQuestInformationTooltip:AddDoubleLine("Required Renown Level:", string.format("|cFFFF0000%d (Requirement Not Fulfilled)|r", requiredRenownLevel))
                        end
                    else
                        qcQuestInformationTooltip:AddDoubleLine("Required Renown Level:", "|cFFFF0000Data Unavailable|r")
                    end
                elseif type(renownInfo) == "number" then
                    local factionName = qcFactions[renownInfo] or "Unknown Faction"
                    qcQuestInformationTooltip:AddDoubleLine("Required Faction:", string.format("%s%s", COLOUR_DRUID, factionName))
                end

                qcQuestInformationTooltip:AddLine(" ")
            end
        end
		-- Renown and Faction requirements End

        -- Quest Giver Information from qcPinDB.lua
        local questGiverInfoFound = false
        for zoneId, npcs in pairs(qcPinDB) do
            -- Retrieve the zone name for the current zone ID
            local zoneName = GetZoneNameFromZoneID(zoneId)

            for _, npcData in ipairs(npcs) do
                local npcId = npcData[3]
                local npcName = npcData[4]
                local xCoord = npcData[5]
                local yCoord = npcData[6]
                local quests = npcData[7]

                if type(quests) == "table" then
                    for _, quest in ipairs(quests) do
                        if quest == questId then
                            qcQuestInformationTooltip:AddDoubleLine(
                                "Quest Giver:",
                                string.format("%s (%s, %.1f, %.1f)", npcName or "Unknown NPC", zoneName, xCoord or 0, yCoord or 0)
                            )
                            questGiverInfoFound = true
                            break
                        end
                    end
                end

                if questGiverInfoFound then break end
            end

            if questGiverInfoFound then break end
        end

        -- Handle case where quest giver information isn't found
        if not questGiverInfoFound then
            qcQuestInformationTooltip:AddDoubleLine("Quest Giver:", "Unknown or Auto-Accepted Quest")
        end

        -- Faction and reputation information
        local factionValue = qcQuestDatabase[questId][16]
        if not (factionValue == nil) then
            local factionName = qcFactions[factionValue]
            if not (factionName == nil) then
                qcQuestInformationTooltip:AddDoubleLine("Faction:", string.format("%s%s", COLOUR_DRUID, factionName))
            end
        end

        -- Reputation tooltip logic, handle both single numbers and tables
        local reputationEntries = qcQuestDatabase[questId][17]
        local hasReputation = false

        if type(reputationEntries) == "table" then
            -- If it's a table, check for any non-zero values
            for _, repValue in pairs(reputationEntries) do
                if repValue ~= 0 then
                    hasReputation = true
                    break
                end
            end
        elseif type(reputationEntries) == "number" and reputationEntries ~= 0 then
            -- If it's a single number, ensure it's non-zero
            hasReputation = true
        end

        if hasReputation then
            qcQuestReputationTooltip:SetOwner(qcQuestInformationTooltip, "ANCHOR_BOTTOMRIGHT", -qcQuestInformationTooltip:GetWidth())
            qcQuestReputationTooltip:ClearLines()
            qcQuestReputationTooltip:AddLine(GetText("COMBAT_TEXT_SHOW_REPUTATION_TEXT"))
            qcQuestReputationTooltip:AddLine(" ")

            if type(reputationEntries) == "table" then
                for qcReputationIndex, qcReputationEntry in pairs(reputationEntries) do
                    qcQuestReputationTooltip:AddDoubleLine(
                        tostring(qcFactions[qcReputationIndex] or qcReputationIndex),
                        stringFormat("%s%d rep", COLOUR_DRUID, qcReputationEntry)
                    )
                end
            elseif type(reputationEntries) == "number" then
                -- Assuming there's only one reputation entry
                qcQuestReputationTooltip:AddDoubleLine("Reputation", stringFormat("%s%d rep", COLOUR_DRUID, reputationEntries))
            end

            qcQuestReputationTooltip:Show()
        else
            qcQuestReputationTooltip:Hide()
        end

        -- Make sure the main tooltip is shown
        qcQuestInformationTooltip:Show()

    else
        qcQuestReputationTooltip:Hide()
    end
end

-- End Tooltip when mouse over quest name

function qcQuestClick(qcButtonIndex)
	local qcQuestID = _G["qcMenuButton" .. qcButtonIndex].QuestID
	if (IsLeftShiftKeyDown()) then --[[ User wants to toggle the completed status of a quest ]]--
	  --print(string.format("%sLeft shift key is down",QCADDON_CHAT_TITLE))
		if (qcCompletedQuests[qcQuestID] == nil) then
			qcCompletedQuests[qcQuestID] = {["C"] = 1}
		else
			if (qcCompletedQuests[qcQuestID]["C"] == nil) then
				qcCompletedQuests[qcQuestID]["C"] = 1
			else
				if (qcCompletedQuests[qcQuestID]["C"] == 1) then
					qcCompletedQuests[qcQuestID]["C"] = 0
				elseif (qcCompletedQuests[qcQuestID]["C"] == 0) then
					qcCompletedQuests[qcQuestID]["C"] = 1
				elseif (qcCompletedQuests[qcQuestID]["C"] == 2) then
					qcCompletedQuests[qcQuestID]["C"] = 1
				end
			end
		end
	elseif (IsLeftAltKeyDown()) then --[[ User wants to toggle the unattainable status of a quest ]]--
	  --print(string.format("%sLeft alt key is down",QCADDON_CHAT_TITLE))
		if (qcCompletedQuests[qcQuestID] == nil) then
			qcCompletedQuests[qcQuestID] = {["C"] = 2}
		else
			if (qcCompletedQuests[qcQuestID]["C"] == nil) then
				qcCompletedQuests[qcQuestID]["C"] = 2
			else
				if (qcCompletedQuests[qcQuestID]["C"] == 2) then
					qcCompletedQuests[qcQuestID]["C"] = 0
				elseif (qcCompletedQuests[qcQuestID]["C"] == 0) then
					qcCompletedQuests[qcQuestID]["C"] = 2
				elseif (qcCompletedQuests[qcQuestID]["C"] == 1) then
					qcCompletedQuests[qcQuestID]["C"] = 2
				end
			end
		end
  else
		-- print(string.format("%sLooking for Tom Tom.",QCADDON_CHAT_TITLE))
    if (C_AddOns.IsAddOnLoaded('TomTom')) then
        local addedWayPoint;
        -- print(string.format("%sLooking for quest in db.", QCADDON_CHAT_TITLE))
        for qcMapIndex, npcList in pairs(qcPinDB) do
            for _, qcInitiatorEntry in pairs(npcList) do
                for _, qcInitiatorQuestEntry in pairs(qcInitiatorEntry[7] or {}) do
                    if (qcInitiatorQuestEntry == qcQuestID) then
                        local zoneID = qcMapIndex
                        local x, y = qcInitiatorEntry[5] / 100, qcInitiatorEntry[6] / 100
                        local title = qcInitiatorEntry[4]

                        --print(string.format("%sFound quest. Zone: %s, Initiator: %s, Coordinates: %s, %s", QCADDON_CHAT_TITLE, zoneID, title, x, y)) -- Used for debuging
                        
                        TomTom:AddWaypoint(zoneID, x, y, {title = title})
                        addedWayPoint = true
                        break
                    end
                end
            end
        end
        if (addedWayPoint) then
            TomTom:SetClosestWaypoint()
        end
    end
end

  --print(string.format("%sUpdating quest list",QCADDON_CHAT_TITLE))
	qcUpdateQuestList(nil, qcMenuSlider:GetValue())

end


function qcFilterButton_OnClick(self, button, down) --TWW changed
Settings.OpenToCategory(qcInterfaceOptions.category:GetID())
end


function qcCloseTooltip()
	qcQuestInformationTooltip:Hide()
	qcQuestReputationTooltip:Hide()
end

local function qcUpdateCompletedQuest(questId) -- *
	if (qcQuestDatabase[questId]) then
		if ((qcQuestDatabase[questId][6] == 2) 
			or (qcQuestDatabase[questId][6] == 3)
			or (qcQuestDatabase[questId][6] == 4)			
			or (qcQuestDatabase[questId][6] == 128)) then
			return nil
		end
	end
	if not (qcCompletedQuests[questId]) then qcCompletedQuests[questId] = {["C"]=1} end
end

local function qcNewDataChecks(questId) -- *
	if ((questId == nil) or (questId == 0)) then return nil end
	if not (qcQuestDatabase[questId]) then
		qcNewDataAlert.New = true
		qcNewDataAlert.Faction = false
		qcNewDataAlert.Race = false
		qcNewDataAlert.Class = false
		qcNewDataAlert:Show()
	else
		qcNewDataAlert:Hide()
		qcNewDataAlert.New = false
		qcNewDataAlert.Faction = false
		qcNewDataAlert.Race = false
		qcNewDataAlert.Class = false
		local factionFlag, raceFlag, classFlag = 0, 0, 0
		local playerFaction, _ = UnitFactionGroup("player")
		local _, playerRace = UnitRace("player")
		local _, playerClass = UnitClass("player")
		factionFlag = qcFactionBits[string.upper(playerFaction)]
		if (bit.band(factionFlag,qcQuestDatabase[questId][7]) == 0) then
			qcNewDataAlert.Faction = true
		end
		raceFlag = qcRaceBits[string.upper(playerRace)]
		if (bit.band(raceFlag,qcQuestDatabase[questId][8]) == 0) then
			qcNewDataAlert.Race = true
		end
		classFlag = qcClassBits[string.upper(playerClass)]
		if (bit.band(classFlag,qcQuestDatabase[questId][9]) == 0) then
			qcNewDataAlert.Class = true
		end
		if ((qcNewDataAlert.Faction) or (qcNewDataAlert.Race) or (qcNewDataAlert.Class)) then
			qcNewDataAlert:Show()
		end
	end
end

function qcNewDataAlert_OnEnter(self) -- *
	qcNewDataAlertTooltip:SetOwner(qcNewDataAlert, "ANCHOR_CURSOR")
	qcNewDataAlertTooltip:ClearLines()
	qcNewDataAlertTooltip:AddLine("Quest Completist")
	qcNewDataAlertTooltip:AddLine(COLOUR_HUNTER .. "Quest Completist was not aware of the following information. Please help improve the accuracy of the addon by submiting a post or new issue over at curse", nil, nil, nil, true)
	if (qcNewDataAlert.New) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - Quest does not exist in the database.", nil, nil, nil, true)
		qcNewDataAlertTooltip:Show()
	end
	if (qcNewDataAlert.Faction) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - QC was not aware your FACTION could complete this quest.", nil, nil, nil, true)
	end
	if (qcNewDataAlert.Race) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - QC was not aware your RACE could complete this quest.", nil, nil, nil, true)
	end
	if (qcNewDataAlert.Class) then
		qcNewDataAlertTooltip:AddLine(COLOUR_MAGE .. " - QC was not aware your CLASS could complete this quest.", nil, nil, nil, true)
	end
	if ((qcNewDataAlert.New) or (qcNewDataAlert.Faction) or (qcNewDataAlert.Race) or (qcNewDataAlert.Class)) then
		qcNewDataAlertTooltip:Show()
	end
end

function qcNewDataAlert_OnLeave(self) -- *
	qcNewDataAlertTooltip:Hide()
end

local function qcBreadcrumbChecks(qcQuestID)

	if (qcQuestID == nil) or (qcQuestID == 0) then return nil end

	if (qcBreadcrumbQuests[qcQuestID] == nil) then
		qcToast.QuestID = nil
		qcToast:Hide()
	else
		qcToast.QuestID = qcQuestID
		local qcCount = 0
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[qcQuestID]) do
			if (qcCompletedQuests[qcBreadcrumbEntry] == nil) then
				qcCount = (qcCount + 1)
			else
				if not (qcCompletedQuests[qcBreadcrumbEntry]["C"] == 1) then
					qcCount = (qcCount + 1)
				end
			end
		end
		if (qcCount == 0) then
			qcToast.QuestID = nil
			qcToast:Hide()
		else
			if (qcCount == 1) then
				qcToastText:SetText("1 Breadcrumb Available!")
			else
				qcToastText:SetText(string.format("%d Breadcrumbs Available!",qcCount))
			end
			qcToast:Show()
		end
	end

end

local function qcMutuallyExclusiveChecks(qcQuestID)

	if (qcQuestID == nil) or (qcQuestID == 0) then return nil end

	if (qcMutuallyExclusive[qcQuestID] == nil) then
		qcMutuallyExclusiveAlert.QuestID = nil
		qcMutuallyExclusiveAlert:Hide()
	else
		qcMutuallyExclusiveAlert.QuestID = qcQuestID
		qcMutuallyExclusiveAlert:Show()
	end

end

function qcMapTooltipSetup() -- *
	qcMapTooltip = CreateFrame("GameTooltip", "qcMapTooltip", UIParent, "GameTooltipTemplate")
	qcMapTooltip:SetFrameStrata("TOOLTIP")
	WorldMapFrame:HookScript("OnSizeChanged",
		function(self)
			qcMapTooltip:SetScale(1/self:GetScale())
		end
	)
end

function qcQuestReputationTooltipSetup() -- *
	qcQuestReputationTooltip = CreateFrame("GameTooltip", "qcQuestReputationTooltip", qcQuestCompletistUI, "GameTooltipTemplate")
	qcQuestReputationTooltip:SetFrameStrata("TOOLTIP")
end

function qcQuestInformationTooltipSetup() -- *
	qcQuestInformationTooltip = CreateFrame("GameTooltip", "qcQuestInformationTooltip", qcQuestCompletistUI, "GameTooltipTemplate")
	qcQuestInformationTooltip:SetFrameStrata("TOOLTIP")
end

function qcToastTooltipSetup() -- *
	qcToastTooltip = CreateFrame("GameTooltip", "qcToastTooltip", qcToast, "GameTooltipTemplate")
	qcToastTooltip:SetFrameStrata("TOOLTIP")
end

function qcNewDataAlertTooltipSetup() -- *
	qcNewDataAlertTooltip = CreateFrame("GameTooltip", "qcNewDataAlertTooltip", qcNewDataAlert, "GameTooltipTemplate")
	qcNewDataAlertTooltip:SetFrameStrata("TOOLTIP")
end

function qcMutuallyExclusiveAlertTooltipSetup() -- *
	qcMutuallyExclusiveAlertTooltip = CreateFrame("GameTooltip", "qcMutuallyExclusiveAlertTooltip", qcMutuallyExclusiveAlert, "GameTooltipTemplate")
	qcMutuallyExclusiveAlertTooltip:SetFrameStrata("TOOLTIP")
end

function qcGetToastQuestInformation(questId) -- *
	if (questId) then
		if (qcQuestDatabase[questId]) then
			return tostring(qcQuestDatabase[questId][2] or nil)
		end
	end
end

function qcToast_OnEnter(self)

	if (self.QuestID == nil) then
		qcToastTooltip:Hide()
	else
		qcToastTooltip:SetOwner(qcToast, "ANCHOR_CURSOR")
		qcToastTooltip:ClearLines()
		qcToastTooltip:AddLine("Breadcrumb Quests")
		for qcBreadcrumbIndex, qcBreadcrumbEntry in pairs(qcBreadcrumbQuests[self.QuestID]) do
			if (qcCompletedQuests[qcBreadcrumbEntry] == nil) then
				local qcQuestName = qcGetToastQuestInformation(qcBreadcrumbEntry)
				if (qcQuestName and qcBreadcrumbEntry) then qcToastTooltip:AddLine(tostring(COLOUR_DRUID .. qcQuestName .. COLOUR_MAGE .. " [" .. qcBreadcrumbEntry .. "]")) end
			else
				if not (qcCompletedQuests[qcBreadcrumbEntry]["C"] == 1) then
				local qcQuestName = qcGetToastQuestInformation(qcBreadcrumbEntry)
				if (qcQuestName and qcBreadcrumbEntry) then qcToastTooltip:AddLine(tostring(COLOUR_DRUID .. qcQuestName .. " [" .. qcBreadcrumbEntry .. "]")) end
				end
			end
		end
		qcToastTooltip:Show()
	end

end

function qcToast_OnLeave(self) -- *
	qcToastTooltip:Hide()
end

function qcMutuallyExclusiveQuestInformation(qcQuestID)

	if (qcQuestID) then
		if (qcQuestDatabase[qcQuestID]) then
			local qcQuestName = tostring(qcQuestDatabase[qcQuestID][2] or nil)
			return qcQuestName
		end
	end

	return nil

end

function qcMutuallyExclusiveAlert_OnEnter(self)

	if (self.QuestID == nil) then
		qcMutuallyExclusiveAlertTooltip:Hide()
	else
		qcMutuallyExclusiveAlertTooltip:SetOwner(qcMutuallyExclusiveAlert, "ANCHOR_BOTTOMRIGHT")
		qcMutuallyExclusiveAlertTooltip:ClearLines()
		qcMutuallyExclusiveAlertTooltip:AddLine("Quest Completist")
		qcMutuallyExclusiveAlertTooltip:AddLine(COLOUR_MAGE .. "This quest is mutually exclusive with others, meaning you can only complete one of them. The other quests are:", nil, nil, nil, true)
		for qcMutuallyExclusiveIndex, qcMutuallyExclusiveEntry in pairs(qcMutuallyExclusive[self.QuestID]) do
			if (qcQuestDatabase[qcMutuallyExclusiveEntry] == nil) then
				qcMutuallyExclusiveAlertTooltip:AddLine(string.format("%s<Quest Not Found In DB> [%d]|r",COLOUR_DRUID,qcMutuallyExclusiveEntry))
			else
				local qcQuestName = qcMutuallyExclusiveQuestInformation(qcMutuallyExclusiveEntry)
				if (qcQuestName and qcMutuallyExclusiveEntry) then qcMutuallyExclusiveAlertTooltip:AddLine(string.format("%s%s [%d]|r",COLOUR_DRUID,qcQuestName,qcMutuallyExclusiveEntry)) end
			end
		end
		qcMutuallyExclusiveAlertTooltip:Show()
	end
end

function qcMutuallyExclusiveAlert_OnLeave(self)

	qcMutuallyExclusiveAlertTooltip:Hide()

end

--[[ ##### MAP PINS START ##### ]]--
-- Create a frame to handle events
local qcEventFrame = CreateFrame("Frame")

-- Flag to track deferred execution
local qcPendingRefresh = false

-- Function to hide all pins
local function qcHideAllPins()
    for i = #qcPinFrames, 1, -1 do
        qcPinFrames[i]:Hide()
        table.insert(qcSparePinFrames, qcPinFrames[i])
        table.remove(qcPinFrames, i)
    end
end

-- Function to get the map scale
local function qcGetMapScale()
    local canvas = WorldMapFrame:GetCanvas()
    local scaleWidth = canvas:GetWidth() / 1002 -- Reference width of the map canvas in default state
    local scaleHeight = canvas:GetHeight() / 668 -- Reference height of the map canvas in default state
    return math.min(scaleWidth, scaleHeight)
end

-- Coloured quest name function
local function qcColouredQuestName(questId)
    if not questId or not qcQuestDatabase[questId] then return nil end
    local questData = qcQuestDatabase[questId]
    local questName = questData[2]
    if questData[6] == 4 or questData[6] == 2 then
        return string.format("|cff178ed5%s|r", questName)
    elseif not qcCompletedQuests[questId] then
        return string.format("|cffffffff%s|r", questName)
    elseif qcCompletedQuests[questId]["C"] == 1 or qcCompletedQuests[questId]["C"] == 2 then
        return string.format("|cff00ff00%s|r", questName)
    else
        return string.format("|cffffffff%s [U]|r", questName)
    end
end

-- Get or create a pin
local function qcGetPin()
    local pin = nil
    if #qcSparePinFrames > 0 then
        pin = qcSparePinFrames[1]
        table.remove(qcSparePinFrames, 1)
    end
    if not pin then
        pin = CreateFrame("Frame", "qcPin", WorldMapFrame:GetCanvas())
        pin:SetSize(24, 24) -- Default size, will be scaled
        pin.Texture = pin:CreateTexture()
        pin.Texture:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\QCIcons")
        pin.Texture:SetAllPoints()
        pin:EnableMouse(true)
        pin:SetFrameLevel(2500)

        pin:HookScript("OnEnter", function(self, motion)
            local frames = GetMouseFoci()
            local relevantFrames = {}
            for _, frame in ipairs(frames) do
                while frame and frame ~= WorldMapFrame do
                    if frame:IsVisible() and not frame:IsProtected() and frame:GetName() == "qcPin" then
                        table.insert(relevantFrames, frame)
                    end
                    frame = frame:GetParent()
                end
            end

            qcMapTooltip:SetParent(self)
            
            -- Dynamic tooltip positioning
            local x, y = self:GetCenter() -- Get pin position
            local mapWidth, mapHeight = WorldMapFrame:GetCanvas():GetSize()

            -- Default anchor (Right)
            local anchorPoint = "ANCHOR_RIGHT"

            -- Adjust if near the right edge
            if x > mapWidth * 0.75 then
                anchorPoint = "ANCHOR_LEFT"
            end

            -- Adjust if near the top edge
            if y > mapHeight * 0.75 then
                anchorPoint = "ANCHOR_BOTTOM"
            end

            qcMapTooltip:SetOwner(self, anchorPoint)

            qcMapTooltip:ClearLines()

            -- Clear old icons if any
            if qcMapTooltip.qcIcons then
                for _, icon in ipairs(qcMapTooltip.qcIcons) do
                    icon:Hide()
                    icon:SetParent(nil)
                end
                wipe(qcMapTooltip.qcIcons)
            end
            qcMapTooltip.qcIcons = {}

            for _, frame in pairs(relevantFrames) do
                local initiatorsIndex = frame.PinIndex
                local initiatorData = qcPins[initiatorsIndex]
                if initiatorData then
                    -- Add initiator name line (without icon)
                    if initiatorData[3] == 0 then
                        qcMapTooltip:AddLine(initiatorData[4] or string.format("%s %s", UnitName("player"), "|cff69ccf0<Yourself>|r"))
                    else
                        qcMapTooltip:AddDoubleLine(initiatorData[4] or string.format("%s %s", UnitName("player"), "|cff69ccf0<Yourself>|r"), string.format("|cffff7d0a[%d]|r", initiatorData[3]))
                    end

                    -- Add quests under the initiator
                    for qcIndex, qcEntry in ipairs(initiatorData[7]) do
                        if #initiatorData[7] <= 10 and qcQuestDatabase[qcEntry] then
                            local questData = qcQuestDatabase[qcEntry]

                            local mapScale = qcGetMapScale()
                            local baseSize = 16
                            local scaledSize = baseSize * math.max(1, math.min(mapScale, 3))

                            local texture = qcMapTooltip:CreateTexture(nil, "OVERLAY")
                            texture:SetParent(qcMapTooltip)
                            texture:SetSize(scaledSize, scaledSize)

                            if questData[6] == 4 then
                                texture:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\DailyQuestIcon")
                            elseif questData[6] == 128 then
                                texture:SetAtlas("questlog-questtypeicon-weekly")
                            elseif questData[6] == 2 then
                                texture:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\DailyActiveQuestIcon")
                            elseif qcCompletedQuests[qcEntry] and (qcCompletedQuests[qcEntry]["C"] == 1 or qcCompletedQuests[qcEntry]["C"] == 2) then
                                texture:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\QuestCompleteIcon")
                            else
                                texture:SetTexture("Interface\\Addons\\QuestCompletist\\Images\\AvailableQuestIcon")
                            end

                            -- Add extra spacing before quest name using spaces
                            qcMapTooltip:AddDoubleLine("    " .. qcColouredQuestName(qcEntry), string.format("|cffff7d0a[%d]|r", qcEntry))

                            -- Attach the icon **after** adding the text
                            local line = _G["qcMapTooltipTextLeft" .. qcMapTooltip:NumLines()]
                            if line then
                                texture:SetPoint("LEFT", line, "LEFT", -6, 0) -- Adjusted left padding for proper spacing
                                texture:Show()
                                table.insert(qcMapTooltip.qcIcons, texture)
                            else
                                texture:Hide()
                            end
                        else
                            -- fallback if questData is missing
                            local questName = qcColouredQuestName(qcEntry) or "|cff808080Quest Missing in DB|r"
							qcMapTooltip:AddDoubleLine("    " .. questName, string.format("|cffff7d0a[%d]|r", qcEntry))
						end
                    end

                    if initiatorData[8] then
                        qcMapTooltip:AddLine(string.format("|cffabd473%s|r", initiatorData[8]), nil, nil, nil, true)
                    end
                end
            end

            -- Adjust font size scaling
            local mapScale = qcGetMapScale()
            local font, size, flags = GameFontNormal:GetFont()
            for i = 1, qcMapTooltip:NumLines() do
                local leftLine = _G["qcMapTooltipTextLeft" .. i]
                local rightLine = _G["qcMapTooltipTextRight" .. i]
                if leftLine then
                    leftLine:SetFont(font, 12 * mapScale, flags)
                end
                if rightLine then
                    rightLine:SetFont(font, 12 * mapScale, flags)
                end
            end

            qcMapTooltip:Show()
        end)

        pin:HookScript("OnLeave", function(self)
            qcMapTooltip:Hide()
            if qcMapTooltip.qcIcons then
                for _, icon in ipairs(qcMapTooltip.qcIcons) do
                    icon:Hide()
                    icon:SetParent(nil)
                end
                wipe(qcMapTooltip.qcIcons)
            end
        end)
    end

    table.insert(qcPinFrames, pin)
    return pin
end
-- Show a pin
local function qcShowPin(index, icon)
    local pin = qcGetPin()
    local canvas = WorldMapFrame:GetCanvas()
    local x = canvas:GetWidth() * qcPins[index][5] / 100
    local y = -canvas:GetHeight() * qcPins[index][6] / 100
    pin:SetPoint('CENTER', canvas, 'TOPLEFT', x, y)
    pin.PinIndex = index
    local iconCoords

    -- Initialize isGrey as true, and turn it to false if ANY quest is available
    local isGrey = true -- Assume initially that all quests are unavailable (grey)
    local playerLevel = UnitLevel("player") -- Get the player's current level

    -- Check all quests associated with this quest giver
    for _, questId in ipairs(qcPins[index][7]) do
        -- If the quest exists in the database and has a valid prereq field
        if questId and qcQuestDatabase[questId] then
            local prereqQuestId = qcQuestDatabase[questId][14]
            local requiredLevel = qcQuestDatabase[questId][3] -- Required level is stored in [3]

            -- Check if the player meets the level requirement and either the quest has no prerequisites or the prerequisite is completed
            if playerLevel >= requiredLevel then
                if prereqQuestId == 0 or (prereqQuestId and C_QuestLog.IsQuestFlaggedCompleted(prereqQuestId)) then
                    isGrey = false -- At least one quest is available and player meets the level requirement
                    break -- No need to check further if we already found one available quest
                end
            end
        end
    end

    -- Set the icon coordinates based on the icon type
    if icon == 1 then
        iconCoords = QC_ICON_COORDS_NORMAL
    elseif icon == 2 then
        iconCoords = QC_ICON_COORDS_REPEATABLE
    elseif icon == 3 then
        iconCoords = QC_ICON_COORDS_PROFESSION
    elseif icon == 4 then
        iconCoords = QC_ICON_COORDS_DAILY
    elseif icon == 5 then
        iconCoords = QC_ICON_COORDS_SEASONAL
    elseif icon == 6 then
        iconCoords = QC_ICON_COORDS_SPECIAL
    elseif icon == 7 then
        iconCoords = QC_ICON_COORDS_WEEKLY
    elseif icon == 8 then
        iconCoords = QC_ICON_COORDS_MONTHLY
    elseif icon == 9 then
        iconCoords = QC_ICON_COORDS_CLASS
    elseif icon == 10 then
        iconCoords = QC_ICON_COORDS_KILL
    elseif icon == 11 then
        iconCoords = QC_ICON_COORDS_LEGENDARY
    else
        -- Fallback in case iconCoords is nil
        iconCoords = QC_ICON_COORDS_NORMAL or {0, 0, 1, 1} -- Ensure a valid table is assigned
    end

    -- Apply the texture coordinates safely
    if iconCoords then
        pin.Texture:SetTexCoord(unpack(iconCoords))
    else
        -- Handle the case where iconCoords is nil
        print("Error: iconCoords is nil for icon type " .. tostring(icon))
    end

    local mapScale = qcGetMapScale()
    pin:SetSize(16 * mapScale, 16 * mapScale)
    pin.Texture:SetSize(16 * mapScale, 16 * mapScale)

    -- Recolor the icon based on the prerequisite quest completion status and level requirement
    if isGrey then
        pin.Texture:SetVertexColor(0.5, 0.5, 0.5) -- Apply grey color
    else
        pin.Texture:SetVertexColor(1, 1, 1) -- Set to normal color
    end

    pin:Show()
end

-- Function to refresh pins
local function qcRefreshPins(UiMapID, mapLevel)
    if not WorldMapFrame:IsVisible() then
        qcPendingRefresh = true -- Set the flag to indicate a refresh is pending
        return
    end

    qcHideAllPins()
    wipe(qcPins)

    if qcSettings.QC_M_SHOW_ICONS == 0 or not qcPinDB[UiMapID] then
        return
    end

    qcPins = qcCopyTable(qcPinDB[UiMapID])

    for i = #qcPins, 1, -1 do
        if qcPins[i][1] ~= mapLevel then
            table.remove(qcPins, i)
        end
    end
		--[[ Map Low Level ]]--	
    if qcSettings.QC_M_HIDE_LOWLEVEL == 1 then
        for i = #qcPins, 1, -1 do
            for questIndex = #qcPins[i][7], 1, -1 do
                local questId = qcPins[i][7][questIndex]
                if qcQuestDatabase[questId] then
                    local questLevel = qcQuestDatabase[questId][3] or 0
					local greenCutoff = (UnitLevel("player") -  UnitQuestTrivialLevelRange("player"))
                    if questLevel < greenCutoff then
                        table.remove(qcPins[i][7], questIndex)
                    end
                else
                    table.remove(qcPins[i][7], questIndex)
                end
            end
            if #qcPins[i][7] == 0 then
                table.remove(qcPins, i)
            end
        end
    end
		--[[ Map Completed ]]--
    if qcSettings["QC_M_HIDE_COMPLETED"] == 1 then
        for i = #qcPins, 1, -1 do
            for qcQuestIndex = #qcPins[i][7], 1, -1 do
                local qcQuestID = qcPins[i][7][qcQuestIndex]
                if qcCompletedQuests[qcQuestID] and (qcCompletedQuests[qcQuestID]["C"] == 1 or qcCompletedQuests[qcQuestID]["C"] == 2) then
                    table.remove(qcPins[i][7], qcQuestIndex)
                end
            end
            if #qcPins[i][7] == 0 then
                table.remove(qcPins, i)
            end
        end
    end
		--[[ Map and Quest Faction ]]--
	if (qcSettings["QC_ML_HIDE_FACTION"] == 1) then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local qcCurrentPlayerFaction, _S = UnitFactionGroup("player")
				local qcCurrentFaction = qcFactionBits[string.upper(qcCurrentPlayerFaction)]
				if (qcQuestDatabase[qcQuestID]) and (BitBand(qcQuestDatabase[qcQuestID][7], qcCurrentFaction) == 0) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end

		--[[ Map and Quest Covenant ]]--
	if (qcSettings["QC_ML_HIDE_COVENANT"] == 1) then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local qcCurrentPlayerFaction, _S = UnitFactionGroup("player")
				local qcCurrentFaction = qcFactionBits[string.upper(qcCurrentPlayerFaction)]
				if (qcQuestDatabase[qcQuestID]) and (BitBand(qcQuestDatabase[qcQuestID][7], qcCurrentFaction) == 0) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end

		--[[  Map and Quest Race\Class ]]--
	if (qcSettings["QC_ML_HIDE_RACECLASS"] == 1) then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local _S, qcCurrentPlayerRace = UnitRace("player")
				local qcCurrentRace = qcRaceBits[string.upper(qcCurrentPlayerRace)]
				local _S, qcCurrentPlayerClass = UnitClass("player")
				local qcCurrentClass = qcClassBits[string.upper(qcCurrentPlayerClass)]
				if (qcQuestDatabase[qcQuestID]) and (BitBand(qcQuestDatabase[qcQuestID][8], qcCurrentRace) == 0) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				elseif (qcQuestDatabase[qcQuestID]) and (BitBand(qcQuestDatabase[qcQuestID][9], qcCurrentClass) == 0) then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end
		--[[ Map Seasonal ]]--
	if (qcSettings["QC_M_HIDE_SEASONAL"] == 1) then
		local qcToday = date("%y%m%d")
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				if (qcQuestDatabase[qcQuestID]) and (qcQuestDatabase[qcQuestID][11] > 0) then
					if not ((qcToday >= qcHolidayDates[qcQuestDatabase[qcQuestID][11]][1]) and (qcToday <= qcHolidayDates[qcQuestDatabase[qcQuestID][11]][2])) then
						TableRemove(qcPins[i][7], qcQuestIndex)
					end
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end
		--[[ Map In progress ]]--
	if (qcSettings["QC_M_HIDE_INPROGRESS"] == 1) then
		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				-- Ensure the quest ID is valid and not nil
				if qcQuestID and C_QuestLog.GetLogIndexForQuestID(qcQuestID) and C_QuestLog.GetLogIndexForQuestID(qcQuestID) > 0 then
					TableRemove(qcPins[i][7], qcQuestIndex)
				end
			end
			if (#qcPins[i][7] == 0) then
				TableRemove(qcPins, i)
			end
		end
	end
		--[[ Map Covenants ]]--
	local version, build, date, tocVersion = GetBuildInfo()
	local majorVersion = tonumber(version:match("^%d+"))

	if majorVersion and majorVersion >= 11 then -- Only run in Retail
		if (qcSettings["QC_ML_HIDE_COVENANTS"] == 1) then
			local playerCovenantID = C_Covenants.GetActiveCovenantID()
			local playerCovenantBit = qcCovenantsBits[playerCovenantID] or 0

			for i = #qcPins, 1, -1 do
				for qcQuestIndex = #qcPins[i][7], 1, -1 do
					local qcQuestID = qcPins[i][7][qcQuestIndex]
					if qcQuestDatabase[qcQuestID] and qcQuestDatabase[qcQuestID][12] then
						local questCovenant = qcQuestDatabase[qcQuestID][12]
						if questCovenant > 0 and BitBand(questCovenant, playerCovenantBit) == 0 then
							TableRemove(qcPins[i][7], qcQuestIndex)
						end
					end
				end
				if #qcPins[i][7] == 0 then
					TableRemove(qcPins, i)
				end
			end
		end
	end
		--[[ Map Warbands ]]--
	local version, build, date, tocVersion = GetBuildInfo()
	local majorVersion = tonumber(version:match("^%d+"))

	if majorVersion and majorVersion >= 11 then -- Only run in Retail
		if (qcSettings["QC_ML_HIDE_WARBANDS"] == 1) then 
			for i = #qcPins, 1, -1 do
				for qcQuestIndex = #qcPins[i][7], 1, -1 do
					local qcQuestID = qcPins[i][7][qcQuestIndex]
					if C_QuestLog.IsQuestFlaggedCompletedOnAccount(qcQuestID) then
						TableRemove(qcPins[i][7], qcQuestIndex)
					end
				end
				if #qcPins[i][7] == 0 then
					TableRemove(qcPins, i)
				end
			end
		end
	end
		--[[ Map Prerequisites Not Met ]] --
	local version, build, date, tocVersion = GetBuildInfo()
	local majorVersion = tonumber(version:match("^%d+"))

	if (qcSettings["QC_M_HIDE_REQUIREMENTSNOTMET"] == 1) then
		local playerLevel = UnitLevel("player")
		local playerFaction, _ = UnitFactionGroup("player")

		for i = #qcPins, 1, -1 do
			for qcQuestIndex = #qcPins[i][7], 1, -1 do
				local qcQuestID = qcPins[i][7][qcQuestIndex]
				local questData = qcQuestDatabase[qcQuestID]

				if questData then
					local questLevel = questData[3] or 0  -- Assuming quest level is at index 3
					local prequestID = questData[14] or 0 -- Assuming prequest ID is at index 14

					-- Check if the player's level is below the required quest level
					local belowRequiredLevel = questLevel > playerLevel

					-- Check if a prerequisite quest is not completed
					local prequestNotCompleted = prequestID > 0 and not C_QuestLog.IsQuestFlaggedCompleted(prequestID)

					-- Check faction standing from qcRenownLevelRequirements (Retail only)
					local factionStandingTooLow = false
					if majorVersion and majorVersion >= 11 then -- Retail check
						local renownRequirement = qcRenownLevelRequirements[qcQuestID]
						if renownRequirement then
							local factionID = renownRequirement[1]  -- First value is faction ID
							local requiredRenown = renownRequirement[2]  -- Second value is required renown level
							local currentRenown = C_MajorFactions.GetCurrentRenownLevel(factionID)

							-- If player's renown is lower than required, mark the quest for removal
							factionStandingTooLow = currentRenown < requiredRenown
						end
					end

					-- Remove the quest if any of the requirements are not met
					if belowRequiredLevel or prequestNotCompleted or factionStandingTooLow then
						TableRemove(qcPins[i][7], qcQuestIndex)
					end
				end
			end
			if #qcPins[i][7] == 0 then
				TableRemove(qcPins, i)
			end
		end
	end
		
		--[[ Map Professions ]]--
	if qcSettings.QC_M_HIDE_PROFESSION == 1 then
		local professionBitwise = 0
		local playerProfessions = {GetProfessions()}

		-- Calculate the player's profession bitwise flag
		for _, prof in ipairs(playerProfessions) do
			if prof then
				local _, _, _, _, _, _, professionID = GetProfessionInfo(prof)
				if professionID and qcProfessionBits[professionID] then
					professionBitwise = professionBitwise + qcProfessionBits[professionID]
				end
			end
		end

    -- Iterate through pins and filter out quests based on profession bitwise flag
    for i = #qcPins, 1, -1 do
        for questIndex = #qcPins[i][7], 1, -1 do
            local questId = qcPins[i][7][questIndex]
            if qcQuestDatabase[questId] then
                local questProfessionFlag = qcQuestDatabase[questId][10]
                if questProfessionFlag and questProfessionFlag ~= 0 then                    
                    -- Check if the quest's profession flag matches any of the player's professions
                    if bit.band(questProfessionFlag, professionBitwise) == 0 then
                        -- If no match, remove the quest
                        table.remove(qcPins[i][7], questIndex)
                    end
                end
            end
        end
        -- Clean up any empty pins
        if #qcPins[i][7] == 0 then
            table.remove(qcPins, i)
        end
    end
end
 
    for pinIndex, pinData in pairs(qcPins) do
        qcShowPin(pinIndex, pinData[2])
    end
end

-- Function to handle map updates and pin anchoring
local function qcHandleMapUpdate()
    local UiMapID = WorldMapFrame:GetMapID()
    local mapLevel = 0

    if UiMapID and UiMapID ~= previousMapID then
        qcRefreshPins(UiMapID, mapLevel)
        previousMapID = UiMapID
    end
end

-- Event handler
qcEventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
        qcHandleMapUpdate()
    elseif event == "WORLD_MAP_OPEN" then
        qcHandleMapUpdate()
        qcPendingRefresh = false -- Reset the flag after the refresh
    elseif event == "Area_Pois_Updated" then
        -- Handle map updates
        qcHandleMapUpdate()
    end
end)

-- Register events
qcEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
qcEventFrame:RegisterEvent("ZONE_CHANGED")
qcEventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
qcEventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
qcEventFrame:RegisterEvent("PLAYER_LOGIN")

-- Check game version and conditionally register WORLD_MAP_OPEN for Retail
local version, build, date, tocVersion = GetBuildInfo()
local majorVersion = tonumber(version:match("^%d+"))

if majorVersion and majorVersion >= 11 then -- Only in Retail
    qcEventFrame:RegisterEvent("WORLD_MAP_OPEN")
end

-- Hook into the world map opening
WorldMapFrame:HookScript("OnShow", function()
    local UiMapID = WorldMapFrame:GetMapID()
    local mapLevel = 0
    qcRefreshPins(UiMapID, mapLevel)
end)

WorldMapFrame.ScrollContainer:HookScript("OnMouseUp", function()
    local UiMapID = WorldMapFrame:GetMapID()
    local mapLevel = 0
    qcRefreshPins(UiMapID, mapLevel)
end)
-- Ensure qcQuestCompletistUI_OnLoad is properly defined
function qcQuestCompletistUI_OnLoad(self)
    -- Your initialization code here
end
--[[ ##### MAP PINS END ##### ]]--

--[[ ##### INTERFACE OPTIONS START ##### ]]--

-- Initialize qcSettings if it is not already set
qcSettings = qcSettings or {}

-- Function to check and set default settings
function qcCheckSettings()
    qcSettings = qcSettings or {}

    if (qcSettings.SORT == nil) then
        qcSettings.SORT = 1
    end
    if (qcSettings.PURGED == nil) then
        qcSettings.PURGED = 0
    end
    if (qcSettings.QC_M_SHOW_ICONS == nil) then
        qcSettings.QC_M_SHOW_ICONS = 1
    end
    if (qcSettings.QC_M_HIDE_COMPLETED == nil) then
        qcSettings.QC_M_HIDE_COMPLETED = 0
    end
    if (qcSettings.QC_M_HIDE_LOWLEVEL == nil) then
        qcSettings.QC_M_HIDE_LOWLEVEL = 0
    end
    if (qcSettings.QC_M_HIDE_PROFESSION == nil) then
        qcSettings.QC_M_HIDE_PROFESSION = 1
    end
    if (qcSettings.QC_M_HIDE_WORLDQUEST == nil) then
        qcSettings.QC_M_HIDE_WORLDQUEST = 1
    end
    if (qcSettings.QC_M_HIDE_SEASONAL == nil) then
        qcSettings.QC_M_HIDE_SEASONAL = 1
    end
    if (qcSettings.QC_M_HIDE_INPROGRESS == nil) then
        qcSettings.QC_M_HIDE_INPROGRESS = 0
    end
    if (qcSettings.QC_L_HIDE_COMPLETED == nil) then
        qcSettings.QC_L_HIDE_COMPLETED = 0
    end
    if (qcSettings.QC_L_HIDE_LOWLEVEL == nil) then
        qcSettings.QC_L_HIDE_LOWLEVEL = 0
    end
    if (qcSettings.QC_L_HIDE_PROFESSION == nil) then
        qcSettings.QC_L_HIDE_PROFESSION = 1
    end
    if (qcSettings.QC_L_HIDE_DAILYQUEST == nil) then
        qcSettings.QC_L_HIDE_DAILYQUEST = 1
    end
    if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == nil) then
        qcSettings.QC_L_HIDE_REPEATABLEQUEST = 1
    end
    if (qcSettings.QC_L_HIDE_WORLDQUEST == nil) then
        qcSettings.QC_L_HIDE_WORLDQUEST = 1
    end
    if (qcSettings.QC_ML_HIDE_FACTION == nil) then
        qcSettings.QC_ML_HIDE_FACTION = 1
    end
    if (qcSettings.QC_ML_HIDE_RACECLASS == nil) then
        qcSettings.QC_ML_HIDE_RACECLASS = 1
    end
    if (qcSettings.QC_ML_HIDE_COVENANTS == nil) then
        qcSettings.QC_ML_HIDE_COVENANTS = 1
    end
	if (qcSettings.QC_ML_HIDE_WARBANDS == nil) then
        qcSettings.QC_ML_HIDE_WARBANDS = 1
    end    
	if (qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET == nil) then
        qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 1
    end
    if (qcSettings.QC_SERVER_QUERY_COMPLETE == nil) then
        qcSettings.QC_SERVER_QUERY_COMPLETE = 0
    end
    if (qcSettings.QC_M_HIDE_DAILYREPEATABLE == nil) then
        qcSettings.QC_M_HIDE_DAILYREPEATABLE = 0
    end
end

function qcApplySettings()
    if (qcSettings.QC_M_SHOW_ICONS == 0) then
        qcIO_M_SHOW_ICONS:SetChecked(false)
    else
        qcIO_M_SHOW_ICONS:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_COMPLETED == 0) then
        qcIO_M_HIDE_COMPLETED:SetChecked(false)
    else
        qcIO_M_HIDE_COMPLETED:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_LOWLEVEL == 0) then
        qcIO_M_HIDE_LOWLEVEL:SetChecked(false)
    else
        qcIO_M_HIDE_LOWLEVEL:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_PROFESSION == 0) then
        qcIO_M_HIDE_PROFESSION:SetChecked(false)
    else
        qcIO_M_HIDE_PROFESSION:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_SEASONAL == 0) then
        qcIO_M_HIDE_SEASONAL:SetChecked(false)
    else
        qcIO_M_HIDE_SEASONAL:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_INPROGRESS == 0) then
        qcIO_M_HIDE_INPROGRESS:SetChecked(false)
    else
        qcIO_M_HIDE_INPROGRESS:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_COMPLETED == 0) then
        qcIO_L_HIDE_COMPLETED:SetChecked(false)
    else
        qcIO_L_HIDE_COMPLETED:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_LOWLEVEL == 0) then
        qcIO_L_HIDE_LOWLEVEL:SetChecked(false)
    else
        qcIO_L_HIDE_LOWLEVEL:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_PROFESSION == 0) then
        qcIO_L_HIDE_PROFESSION:SetChecked(false)
    else
        qcIO_L_HIDE_PROFESSION:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_DAILYQUEST == 0) then
        qcIO_L_HIDE_DAILYQUEST:SetChecked(false)
    else
        qcIO_L_HIDE_DAILYQUEST:SetChecked(true)
    end
    if (qcSettings.QC_L_HIDE_REPEATABLEQUEST == 0) then
        qcIO_L_HIDE_REPEATABLEQUEST:SetChecked(false)
    else
        qcIO_L_HIDE_REPEATABLEQUEST:SetChecked(true)
    end

    -- Only handle qcIO_L_HIDE_WORLDQUEST for Legion and later
    local version, build, date, tocVersion = GetBuildInfo()
    local majorVersion = tonumber(version:match("^%d+"))
    if majorVersion and majorVersion >= 7 then
        if (qcSettings.QC_L_HIDE_WORLDQUEST == 0) then
            qcIO_L_HIDE_WORLDQUEST:SetChecked(false)
        else
            qcIO_L_HIDE_WORLDQUEST:SetChecked(true)
        end
    end

    -- Only handle qcIO_ML_HIDE_COVENANTS for Battle for Azeroth (8.x) and later
    if majorVersion and majorVersion >= 8 then
        if (qcSettings.QC_ML_HIDE_COVENANTS == 0) then
            qcIO_ML_HIDE_COVENANTS:SetChecked(false)
        else
            qcIO_ML_HIDE_COVENANTS:SetChecked(true)
        end
    end

    -- Only handle qcIO_ML_HIDE_WARBANDS for Dragonflight (11.x) and later
    if majorVersion and majorVersion >= 11 then
        if (qcSettings.QC_ML_HIDE_WARBANDS == 0) then
            qcIO_ML_HIDE_WARBANDS:SetChecked(false)
        else
            qcIO_ML_HIDE_WARBANDS:SetChecked(true)
        end
    end

    if (qcSettings.QC_ML_HIDE_FACTION == 0) then
        qcIO_ML_HIDE_FACTION:SetChecked(false)
    else
        qcIO_ML_HIDE_FACTION:SetChecked(true)
    end
    if (qcSettings.QC_ML_HIDE_RACECLASS == 0) then
        qcIO_ML_HIDE_RACECLASS:SetChecked(false)
    else
        qcIO_ML_HIDE_RACECLASS:SetChecked(true)
    end
    if (qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET == 0) then
        qcIO_M_HIDE_REQUIREMENTSNOTMET:SetChecked(false)
    else
        qcIO_M_HIDE_REQUIREMENTSNOTMET:SetChecked(true)
    end
end

function qcWelcomeMessage()
    print(string.format("%sThanks for using Quest Completist. Spot a quest inaccuracy? Please report it on Curse.", QCADDON_CHAT_TITLE))
    print(string.format("%sMap Pins are back. There are some hickups still, see bug list on CF", QCADDON_CHAT_TITLE))
end

function qcInterfaceOptions_OnLoad(self)
    self.name = "Quest Completist"
    self.okay = function(self) qcInterfaceOptions_Okay(self) end
    self.cancel = function(self) qcInterfaceOptions_Cancel(self) end

    if Settings then
        --print("Registering category with Settings API.")
        local category = Settings.RegisterCanvasLayoutCategory(self, self.name)
        Settings.RegisterAddOnCategory(category)
        self.category = category
    else
        InterfaceOptions_AddCategory(self)
        print("Error: Settings API not available, falling back to InterfaceOptions_AddCategory.")
    end
end

function qcInterfaceOptions_Okay(self)
    qcUpdateQuestList(qcCurrentCategoryID, 1)
    qcRefreshPins(C_Map.GetBestMapForUnit("player"))
end

function qcInterfaceOptions_Cancel(self)
    -- Do nothing for now
end

function qcInterfaceOptions_OnShow(self)
    local qcL = qcLocalize

    qcConfigTitle = self:CreateFontString("qcConfigTitle", "ARTWORK", "GameFontNormalLarge")
    qcConfigTitle:SetPoint("TOPLEFT", 16, -16)
    qcConfigTitle:SetText(qcL.CONFIGTITLE)

    qcConfigSubtitle = self:CreateFontString("qcConfigSubtitle", "ARTWORK", "GameFontHighlightSmall")
    qcConfigSubtitle:SetHeight(22) -- Height from top to put the checkbox in filters
    qcConfigSubtitle:SetPoint("TOPLEFT", qcConfigTitle, "BOTTOMLEFT", 0, -8)
    qcConfigSubtitle:SetPoint("RIGHT", self, -32, 0)
    qcConfigSubtitle:SetNonSpaceWrap(true)
    qcConfigSubtitle:SetJustifyH("LEFT")
    qcConfigSubtitle:SetJustifyV("TOP")
    qcConfigSubtitle:SetText(qcL.CONFIGSUBTITLE)

    qcMapFiltersTitle = self:CreateFontString("qcMapFiltersTitle", "ARTWORK", "GameFontNormal")
    qcMapFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -4)
    qcMapFiltersTitle:SetText(qcL.MAPFILTERS)

    qcIO_M_SHOW_ICONS = CreateFrame("CheckButton", "qcIO_M_SHOW_ICONS", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_SHOW_ICONS:SetPoint("TOPLEFT", qcMapFiltersTitle, "BOTTOMLEFT", 16, -6)
    _G[qcIO_M_SHOW_ICONS:GetName().."Text"]:SetText(qcL.SHOWMAPICONS)
    qcIO_M_SHOW_ICONS:SetScript("OnClick", function(self)
        if (qcIO_M_SHOW_ICONS:GetChecked() == false) then
            qcSettings.QC_M_SHOW_ICONS = 0
        else
            qcSettings.QC_M_SHOW_ICONS = 1
        end
    end)

    qcIO_M_HIDE_COMPLETED = CreateFrame("CheckButton", "qcIO_M_HIDE_COMPLETED", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_COMPLETED:SetPoint("TOPLEFT", qcIO_M_SHOW_ICONS, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_COMPLETED:GetName().."Text"]:SetText(qcL.HIDECOMPLETEDQUESTS)
    qcIO_M_HIDE_COMPLETED:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_COMPLETED:GetChecked() == false) then
            qcSettings.QC_M_HIDE_COMPLETED = 0
        else
            qcSettings.QC_M_HIDE_COMPLETED = 1
        end
    end)

    qcIO_M_HIDE_LOWLEVEL = CreateFrame("CheckButton", "qcIO_M_HIDE_LOWLEVEL", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_LOWLEVEL:SetPoint("TOPLEFT", qcIO_M_HIDE_COMPLETED, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_LOWLEVEL:GetName().."Text"]:SetText(qcL.HIDELOWLEVELQUESTS)
    qcIO_M_HIDE_LOWLEVEL:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_LOWLEVEL:GetChecked() == false) then
            qcSettings.QC_M_HIDE_LOWLEVEL = 0
        else
            qcSettings.QC_M_HIDE_LOWLEVEL = 1
        end
    end)

    qcIO_M_HIDE_PROFESSION = CreateFrame("CheckButton", "qcIO_M_HIDE_PROFESSION", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_PROFESSION:SetPoint("TOPLEFT", qcIO_M_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_PROFESSION:GetName().."Text"]:SetText(qcL.HIDEOTHERPROFESSIONQUESTS)
    qcIO_M_HIDE_PROFESSION:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_PROFESSION:GetChecked() == false) then
            qcSettings.QC_M_HIDE_PROFESSION = 0
        else
            qcSettings.QC_M_HIDE_PROFESSION = 1
        end
    end)

    qcIO_M_HIDE_SEASONAL = CreateFrame("CheckButton", "qcIO_M_HIDE_SEASONAL", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_SEASONAL:SetPoint("TOPLEFT", qcIO_M_HIDE_PROFESSION, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_SEASONAL:GetName().."Text"]:SetText(qcL.HIDENONACTIVESEASONALQUESTS)
    qcIO_M_HIDE_SEASONAL:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_SEASONAL:GetChecked() == false) then
            qcSettings.QC_M_HIDE_SEASONAL = 0
        else
            qcSettings.QC_M_HIDE_SEASONAL = 1
        end
    end)

    qcIO_M_HIDE_INPROGRESS = CreateFrame("CheckButton", "qcIO_M_HIDE_INPROGRESS", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_INPROGRESS:SetPoint("TOPLEFT", qcIO_M_HIDE_SEASONAL, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_INPROGRESS:GetName().."Text"]:SetText(qcL.HIDEINPROGRESSQUESTS)
    qcIO_M_HIDE_INPROGRESS:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_INPROGRESS:GetChecked() == false) then
            qcSettings.QC_M_HIDE_INPROGRESS = 0
        else
            qcSettings.QC_M_HIDE_INPROGRESS = 1
        end
    end)
	
    qcIO_M_HIDE_REQUIREMENTSNOTMET = CreateFrame("CheckButton", "qcIO_M_HIDE_REQUIREMENTSNOTMET", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_M_HIDE_REQUIREMENTSNOTMET:SetPoint("TOPLEFT", qcIO_M_HIDE_INPROGRESS, "BOTTOMLEFT", 0, 0)
    _G[qcIO_M_HIDE_REQUIREMENTSNOTMET:GetName().."Text"]:SetText(qcL.HIDEREQUIREMENTSNOTMET)
    qcIO_M_HIDE_REQUIREMENTSNOTMET:SetScript("OnClick", function(self)
        if (qcIO_M_HIDE_REQUIREMENTSNOTMET:GetChecked() == false) then
            qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 0
        else
            qcSettings.QC_M_HIDE_REQUIREMENTSNOTMET = 1
        end
    end)	

    --- Quest List Filters Start ---
    qcListFiltersTitle = self:CreateFontString("qcListFiltersTitle", "ARTWORK", "GameFontNormal")
    qcListFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -210)
    qcListFiltersTitle:SetText(qcL.QUESTLISTFILTERS)

    qcIO_L_HIDE_COMPLETED = CreateFrame("CheckButton", "qcIO_L_HIDE_COMPLETED", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_COMPLETED:SetPoint("TOPLEFT", qcListFiltersTitle, "BOTTOMLEFT", 16, -6)
    _G[qcIO_L_HIDE_COMPLETED:GetName().."Text"]:SetText(qcL.HIDECOMPLETEDQUESTS)
    qcIO_L_HIDE_COMPLETED:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_COMPLETED:GetChecked() == false) then
            qcSettings.QC_L_HIDE_COMPLETED = 0
        else
            qcSettings.QC_L_HIDE_COMPLETED = 1
        end
    end)

    qcIO_L_HIDE_LOWLEVEL = CreateFrame("CheckButton", "qcIO_L_HIDE_LOWLEVEL", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_LOWLEVEL:SetPoint("TOPLEFT", qcIO_L_HIDE_COMPLETED, "BOTTOMLEFT", 0, 0)
    _G[qcIO_L_HIDE_LOWLEVEL:GetName().."Text"]:SetText(qcL.HIDELOWLEVELQUESTS)
    qcIO_L_HIDE_LOWLEVEL:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_LOWLEVEL:GetChecked() == false) then
            qcSettings.QC_L_HIDE_LOWLEVEL = 0
        else
            qcSettings.QC_L_HIDE_LOWLEVEL = 1
        end
    end)

    qcIO_L_HIDE_PROFESSION = CreateFrame("CheckButton", "qcIO_L_HIDE_PROFESSION", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_PROFESSION:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, 0)
    _G[qcIO_L_HIDE_PROFESSION:GetName().."Text"]:SetText(qcL.HIDEOTHERPROFESSIONQUESTS)
    qcIO_L_HIDE_PROFESSION:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_PROFESSION:GetChecked() == false) then
            qcSettings.QC_L_HIDE_PROFESSION = 0
        else
            qcSettings.QC_L_HIDE_PROFESSION = 1
        end
    end)

    qcIO_L_HIDE_DAILYQUEST = CreateFrame("CheckButton", "qcIO_L_HIDE_DAILYQUEST", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_DAILYQUEST:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, -25)
    _G[qcIO_L_HIDE_DAILYQUEST:GetName().."Text"]:SetText(qcL.HIDEDAILYQUEST .. COLOUR_DEATHKNIGHT .. " ")
    qcIO_L_HIDE_DAILYQUEST:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_DAILYQUEST:GetChecked() == false) then
            qcSettings.QC_L_HIDE_DAILYQUEST = 0
        else
            qcSettings.QC_L_HIDE_DAILYQUEST = 1
        end
    end)

    qcIO_L_HIDE_REPEATABLEQUEST = CreateFrame("CheckButton", "qcIO_L_HIDE_REPEATABLEQUEST", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_L_HIDE_REPEATABLEQUEST:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, -50)
    _G[qcIO_L_HIDE_REPEATABLEQUEST:GetName().."Text"]:SetText(qcL.HIDEREPEATABLEQUEST .. COLOUR_DEATHKNIGHT .. " ")
    qcIO_L_HIDE_REPEATABLEQUEST:SetScript("OnClick", function(self)
        if (qcIO_L_HIDE_REPEATABLEQUEST:GetChecked() == false) then
            qcSettings.QC_L_HIDE_REPEATABLEQUEST = 0
        else
            qcSettings.QC_L_HIDE_REPEATABLEQUEST = 1
        end
    end)

	-- Only create the checkbox if the expansion is Legion or later
	if majorVersion and majorVersion >= 7 then
		qcIO_L_HIDE_WORLDQUEST = CreateFrame("CheckButton", "qcIO_L_HIDE_WORLDQUEST", self, "InterfaceOptionsCheckButtonTemplate")
		qcIO_L_HIDE_WORLDQUEST:SetPoint("TOPLEFT", qcIO_L_HIDE_LOWLEVEL, "BOTTOMLEFT", 0, -75)
		_G[qcIO_L_HIDE_WORLDQUEST:GetName().."Text"]:SetText(qcL.HIDEWORLDQUEST .. COLOUR_DEATHKNIGHT .. " ")
		qcIO_L_HIDE_WORLDQUEST:SetScript("OnClick", function(self)
			if (qcIO_L_HIDE_WORLDQUEST:GetChecked() == false) then
				qcSettings.QC_L_HIDE_WORLDQUEST = 0
			else
				qcSettings.QC_L_HIDE_WORLDQUEST = 1
			end
		end)
	end

    qcCombinedFiltersTitle = self:CreateFontString("qcCombinedFiltersTitle", "ARTWORK", "GameFontNormal")
    qcCombinedFiltersTitle:SetPoint("TOPLEFT", qcConfigSubtitle, "BOTTOMLEFT", 16, -400)
    qcCombinedFiltersTitle:SetText(qcL.COMBINEDMAPANDQUESTFILTERS)

    qcIO_ML_HIDE_FACTION = CreateFrame("CheckButton", "qcIO_ML_HIDE_FACTION", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_ML_HIDE_FACTION:SetPoint("TOPLEFT", qcCombinedFiltersTitle, "BOTTOMLEFT", 16, -6)
    _G[qcIO_ML_HIDE_FACTION:GetName().."Text"]:SetText(qcL.HIDEOTHERFACTIONQUESTS)
    qcIO_ML_HIDE_FACTION:SetScript("OnClick", function(self)
        if (qcIO_ML_HIDE_FACTION:GetChecked() == false) then
            qcSettings.QC_ML_HIDE_FACTION = 0
        else
            qcSettings.QC_ML_HIDE_FACTION = 1
        end
    end)

    qcIO_ML_HIDE_RACECLASS = CreateFrame("CheckButton", "qcIO_ML_HIDE_RACECLASS", self, "InterfaceOptionsCheckButtonTemplate")
    qcIO_ML_HIDE_RACECLASS:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, 0)
    _G[qcIO_ML_HIDE_RACECLASS:GetName().."Text"]:SetText(qcL.HIDEOTHERRACEANDCLASSQUESTS)
    qcIO_ML_HIDE_RACECLASS:SetScript("OnClick", function(self)
        if (qcIO_ML_HIDE_RACECLASS:GetChecked() == false) then
            qcSettings.QC_ML_HIDE_RACECLASS = 0
        else
            qcSettings.QC_ML_HIDE_RACECLASS = 1
        end
    end)

	local version, build, date, tocVersion = GetBuildInfo()
	local majorVersion = tonumber(version:match("^%d+"))

	-- Create Covenant Checkbox (for Battle for Azeroth (8.x) and later)
	if majorVersion and majorVersion >= 8 then
		qcIO_ML_HIDE_COVENANTS = CreateFrame("CheckButton", "qcIO_ML_HIDE_COVENANTS", self, "InterfaceOptionsCheckButtonTemplate")
		qcIO_ML_HIDE_COVENANTS:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, -25)
		_G[qcIO_ML_HIDE_COVENANTS:GetName().."Text"]:SetText(qcL.HIDEOTHERCOVENANTQUESTS)
		qcIO_ML_HIDE_COVENANTS:SetScript("OnClick", function(self)
			if (qcIO_ML_HIDE_COVENANTS:GetChecked() == false) then
				qcSettings.QC_ML_HIDE_COVENANTS = 0
			else
				qcSettings.QC_ML_HIDE_COVENANTS = 1
			end
		end)
	end

	-- Create Warband Checkbox (for Dragonflight (11.x) and later)
	if majorVersion and majorVersion >= 11 then
		qcIO_ML_HIDE_WARBANDS = CreateFrame("CheckButton", "qcIO_ML_HIDE_WARBANDS", self, "InterfaceOptionsCheckButtonTemplate")
		qcIO_ML_HIDE_WARBANDS:SetPoint("TOPLEFT", qcIO_ML_HIDE_FACTION, "BOTTOMLEFT", 0, -50)
		_G[qcIO_ML_HIDE_WARBANDS:GetName().."Text"]:SetText(qcL.HIDEWARBANDS)
		qcIO_ML_HIDE_WARBANDS:SetScript("OnClick", function(self)
			if (qcIO_ML_HIDE_WARBANDS:GetChecked() == false) then
				qcSettings.QC_ML_HIDE_WARBANDS = 0
			else
				qcSettings.QC_ML_HIDE_WARBANDS = 1
			end
		end)
	end
	
    self:SetScript("OnShow", qcConfigRefresh)
    qcConfigRefresh(self)
end

function qcConfigRefresh(self)
    if not (self:IsVisible()) then return end
    -- Set control values here
    qcApplySettings()
end
-- Initialize settings when the addon is loaded
qcCheckSettings()

local function qcEventHandler(self, event, ...)
	if (event == "ADVENTURE_MAP_OPEN") then
		qcRefreshPins(C_Map.GetBestMapForUnit("player"))
	elseif (event == "UNIT_QUEST_LOG_CHANGED") then
		if (... == "player") then qcUpdateQuestList(nil, qcMenuSlider:GetValue()) end
	elseif (event == "ZONE_CHANGED_NEW_AREA") then
		qcZoneChangedNewArea()		--				
	elseif (event == "ZONE_CHANGED") then
		qcZoneChangedNewArea()
	elseif (event == "QUEST_ITEM_UPDATE") then
--		if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
--		if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end  9.xx Soltion
		if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
	elseif (event == "QUEST_DETAIL") then
		local qcQuestID = GetQuestID()
--		if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
--		if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 9.xx Soltion
		if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
		qcBreadcrumbChecks(qcQuestID)
		qcNewDataChecks(qcQuestID)
		qcMutuallyExclusiveChecks(qcQuestID)
		if (QCDEBUG_MODE) then qcVerifyMapDataExists() end
	elseif (event == "QUEST_ACCEPTED") then
		qcUpdateQuestList(nil, qcMenuSlider:GetValue())
	elseif (event == "QUEST_PROGRESS") then
		local qcQuestID = GetQuestID()
--		if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
--		if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 9.xx Soltion
		if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
		if not (qcQuestID == 0) then
			qcBreadcrumbChecks(qcQuestID)
			qcNewDataChecks(qcQuestID)
			qcMutuallyExclusiveChecks(qcQuestID)
		end
	elseif (event == "QUEST_LOG_UPDATE") then --  trying instead of QUEST_COMPLETE
		local qcQuestID = GetQuestID()
	--	if (QuestFrame:IsShown() and QuestFrame.TopTileStreaks) then QuestFrame.TopTileStreaks:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 10.X replacemnt from beta?
	--	if (QuestFrame:IsShown()) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end 9.xx Soltion
	if (QuestFrame:IsShown() and QuestFrameNpcNameText) then QuestFrameNpcNameText:SetText(string.format("%s [%d]",UnitName("questnpc") or "nil",GetQuestID())) end
		if not (qcQuestID == 0) then
			qcBreadcrumbChecks(qcQuestID)
			qcNewDataChecks(qcQuestID)
			qcMutuallyExclusiveChecks(qcQuestID)
			qcUpdateCompletedQuest(qcQuestID)
			qcUpdateMutuallyExclusiveCompletedQuest(qcQuestID)
			qcUpdateSkippedBreadcrumbQuest(qcQuestID)
			qcUpdateQuestList(nil, qcMenuSlider:GetValue())
			
		end
	elseif (event == "PLAYER_ENTERING_WORLD") then
			qcQuestQueryCompleted()
			qcZoneChangedNewArea()
	elseif (event == "ADDON_LOADED") then
		if (... == "QuestCompletist") then
			if not (qcCompletedQuests) then qcCompletedQuests = {} end
			if not (qcWorkingDB) then qcWorkingDB = {} end
			if not (qcWorkingLog) then qcWorkingLog = {} end
			qcCheckSettings()
			qcApplySettings()
			qcWelcomeMessage()
			qcZoneChangedNewArea()
			qcMenuSlider:SetValueStep(1);
			qcMenuSlider:SetObeyStepOnDrag(true);
		end
	end

end

function qcQuestCompletistUI_OnShow(self)
	if (qcSettings) then
		qcUpdateQuestList(qcCurrentCategoryID,qcMenuSlider:GetValue())
	end
end

function qcQuestCompletistUI_OnLoad(self)
	SetPortraitToTexture(self.qcPortrait, "Interface\\Addons\\QuestCompletist\\Images\\Trade_archaeology_draenei_tome")
	self.qcTitleText:SetText(string.format("Quest Completist v%s", QCADDON_VERSION))
	self.qcCategoryDropdownButton:SetText(GetText("CATEGORIES"))
	self.qcOptionsButton:SetText(GetText("FILTERS"))
	self:RegisterForDrag("LeftButton")
	self:RegisterEvent("QUEST_COMPLETE")
	--self:RegisterEvent("QUEST_FINISHED") -- Cant be used for marking quest complette sinze it marks it done before its turned in 
	self:RegisterEvent("QUEST_TURNED_IN")  -- Use this instead of QUEST_COMPLETE to fix issues whit some quest not getting marked as completted??
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_ITEM_UPDATE")
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- 
	self:RegisterEvent("ZONE_CHANGED")
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("ADVENTURE_MAP_OPEN")
	self:SetScript("OnEvent", qcEventHandler)
	qcQuestInformationTooltipSetup()
	qcQuestReputationTooltipSetup()
	qcMapTooltipSetup()
	qcToastTooltipSetup()
	qcNewDataAlertTooltipSetup()
	qcMutuallyExclusiveAlertTooltipSetup()
end
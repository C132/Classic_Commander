local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("WHO_LIST_UPDATE")
frame:RegisterEvent("FRIENDLIST_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

local loaded = false
local whoList = {}  -- Store current who list results
local checkboxes = {}  -- Store checkbox references

-- Create the mass whisper button
local massWhisperButton = CreateFrame("Button", "CommanderWhoMassWhisperButton", WhoFrame, "UIPanelButtonTemplate")
massWhisperButton:SetSize(120, 22)
massWhisperButton:SetPoint("TOPRIGHT", WhoFrame, "TOPRIGHT", -10, -25)
massWhisperButton:SetText("Mass Whisper")

-- Class color table
local RAID_CLASS_COLORS = {
    ["WARRIOR"] = "FFC79C6E",
    ["PALADIN"] = "FFF58CBA",
    ["HUNTER"] = "FFABD473",
    ["ROGUE"] = "FFFFF569",
    ["PRIEST"] = "FFFFFFFF",
    ["DEATHKNIGHT"] = "FFC41F3B",
    ["SHAMAN"] = "FF0070DE",
    ["MAGE"] = "FF69CCF0",
    ["WARLOCK"] = "FF9482C9",
    ["DRUID"] = "FFFF7D0A"
}

-- Create the Mass Whisper Frame
local function CreateMassWhisperFrame()
    local whisperFrame = CreateFrame("Frame", "CommanderWhoMassWhisperFrame", UIParent, "BasicFrameTemplateWithInset")
    whisperFrame:SetSize(400, 500)
    whisperFrame:SetPoint("CENTER")
    whisperFrame:SetMovable(true)
    whisperFrame:EnableMouse(true)
    whisperFrame:RegisterForDrag("LeftButton")
    whisperFrame:SetScript("OnDragStart", whisperFrame.StartMoving)
    whisperFrame:SetScript("OnDragStop", whisperFrame.StopMovingOrSizing)
    whisperFrame:Hide()

    -- Title
    whisperFrame.title = whisperFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    whisperFrame.title:SetPoint("TOP", whisperFrame, "TOP", 0, -5)
    whisperFrame.title:SetText("Mass Whisper")

    -- Create the scroll frame for the player list
    local scrollFrame = CreateFrame("ScrollFrame", nil, whisperFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 60)

    local scrollChild = CreateFrame("Frame")
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(370, 500)
    whisperFrame.scrollChild = scrollChild

    -- Message input box
    local messageBox = CreateFrame("EditBox", nil, whisperFrame, "InputBoxTemplate")
    messageBox:SetSize(280, 20)
    messageBox:SetPoint("BOTTOMLEFT", 15, 15)
    messageBox:SetAutoFocus(false)
    messageBox:SetMaxLetters(255)
    whisperFrame.messageBox = messageBox

    -- Send button
    local sendButton = CreateFrame("Button", nil, whisperFrame, "UIPanelButtonTemplate")
    sendButton:SetSize(80, 22)
    sendButton:SetPoint("BOTTOMRIGHT", -10, 15)
    sendButton:SetText("Send")
    whisperFrame.sendButton = sendButton

    -- Progress text
    local progressText = whisperFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressText:SetPoint("BOTTOMLEFT", messageBox, "TOPLEFT", 0, 5)
    progressText:SetText("")
    whisperFrame.progressText = progressText

    return whisperFrame
end

-- Function to update the player list in the mass whisper frame
local function UpdatePlayerList(frame)
    local scrollChild = frame.scrollChild
    -- Clear existing entries
    for _, child in pairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local previousButton
    local numResults = C_FriendList.GetNumWhoResults()
    
    for i = 1, numResults do
        local whoInfo = C_FriendList.GetWhoInfo(i)
        if whoInfo then
            local button = CreateFrame("Frame", nil, scrollChild)
            button:SetSize(350, 20)
            
            if previousButton then
                button:SetPoint("TOPLEFT", previousButton, "BOTTOMLEFT", 0, 0)
            else
                button:SetPoint("TOPLEFT", 0, 0)
            end

            -- Checkbox
            local checkbox = CreateFrame("CheckButton", nil, button, "UICheckButtonTemplate")
            checkbox:SetPoint("LEFT", 2, 0)
            checkbox:SetSize(14, 14)
            checkbox:SetChecked(true)
            button.checkbox = checkbox

            -- Player info text
            local infoText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoText:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
            
            -- Get proper class name and color
            local englishClass = whoInfo.classFileName or whoInfo.filename -- Try both possible properties
            if not englishClass then
                -- Extract class from className if filename is not available
                local className = whoInfo.className or ""
                className = className:upper()
                for class, _ in pairs(RAID_CLASS_COLORS) do
                    if className:find(class) then
                        englishClass = class
                        break
                    end
                end
            end
            englishClass = englishClass or "WARRIOR" -- Fallback
            
            local classColor = RAID_CLASS_COLORS[englishClass] or "FFFFFFFF"
            local displayName = whoInfo.fullName and whoInfo.fullName:match("([^-]+)") or "Unknown"
            
            -- Format the text with class coloring and cleaned up name
            infoText:SetText(string.format(
                "|cff%s%s|r %d %s %s",
                classColor,
                displayName,
                whoInfo.level or 0,
                whoInfo.className or "",
                whoInfo.area or ""
            ))
            button.infoText = infoText
            button.playerName = displayName -- Store clean name for whispers
            
            -- Status text (for whisper progress)
            local statusText = button:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
            statusText:SetPoint("RIGHT", -2, 0)
            statusText:SetText("")
            button.statusText = statusText

            previousButton = button
        end
    end

    -- Update scroll child height
    if previousButton then
        scrollChild:SetHeight(previousButton:GetBottom() * -1)
    end
end

local massWhisperFrame = CreateMassWhisperFrame()

-- Send whispers function
local function SendMassWhispers(message)
    local selectedPlayers = {}
    for _, child in pairs({massWhisperFrame.scrollChild:GetChildren()}) do
        if child.checkbox and child.checkbox:GetChecked() then
            table.insert(selectedPlayers, {
                frame = child,
                name = child.playerName -- Use stored clean name
            })
        end
    end

    if #selectedPlayers == 0 then
        massWhisperFrame.progressText:SetText("No players selected!")
        return
    end

    local count = 0
    local whisperTimer = C_Timer.NewTicker(CommanderWhoDB.WhisperDelay, function()
        count = count + 1
        if count > #selectedPlayers or count > CommanderWhoDB.MaxWhisperCount then
            massWhisperFrame.progressText:SetText("Whispers complete!")
            whisperTimer:Cancel()
            return
        end

        local player = selectedPlayers[count]
        if player and player.name then
            SendChatMessage(message, "WHISPER", nil, player.name:trim())
            player.frame.statusText:SetText("Sent")
            massWhisperFrame.progressText:SetText(string.format("Sending %d/%d", count, #selectedPlayers))
        end
    end, math.min(#selectedPlayers, CommanderWhoDB.MaxWhisperCount))
end

-- Button handlers
massWhisperButton:SetScript("OnClick", function()
    if massWhisperFrame:IsShown() then
        massWhisperFrame:Hide()
    else
        if C_FriendList.GetNumWhoResults() > 0 then
            UpdatePlayerList(massWhisperFrame)
            massWhisperFrame:Show()
        else
            print("No players found in Who results!")
        end
    end
end)

-- Add hide handler to update when reopening
massWhisperFrame:SetScript("OnShow", function()
    UpdatePlayerList(massWhisperFrame)
    massWhisperFrame.messageBox:SetText("")
    massWhisperFrame.progressText:SetText("")
end)

massWhisperFrame.sendButton:SetScript("OnClick", function()
    local message = massWhisperFrame.messageBox:GetText()
    if message and message ~= "" then
        SendMassWhispers(message)
    else
        massWhisperFrame.progressText:SetText("Please enter a message!")
    end
end)

-- Forward declaration so HookWhoScroll can see the function defined below
local UpdateWhoCheckboxes

-- Hook the scroll frame update to maintain checkboxes
local function HookWhoScroll()
    -- Wait for WhoFrame components to be available
    if not WhoFrame or not WhoListScrollFrame then
        C_Timer.After(0.1, HookWhoScroll)
        return
    end

    -- Hook the WhoFrame's update function
    if WhoList_Update then
        hooksecurefunc("WhoList_Update", function()
            C_Timer.After(0, UpdateWhoCheckboxes)
        end)
    end

    -- Hook the scroll event
    if WhoListScrollFrame then
        WhoListScrollFrame:HookScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, FRIENDS_FRAME_WHO_HEIGHT, WhoList_Update)
        end)
    end
end

-- Function to create or update checkboxes for each who result
function UpdateWhoCheckboxes()
    if not WhoFrame or not WhoListScrollFrame then return end

    local numResults = C_FriendList.GetNumWhoResults()
    local offset = FauxScrollFrame_GetOffset(WhoListScrollFrame)
    
    -- Hide all existing checkboxes
    for _, checkbox in pairs(checkboxes) do
        checkbox:Hide()
    end
    
    -- Update checkboxes for visible buttons
    for i = 1, WHOS_TO_DISPLAY do
        local button = _G["WhoFrameButton"..i]
        if not button then break end
        
        local index = i + offset
        
        -- Create checkbox if it doesn't exist
        if not checkboxes[button] then
            local checkbox = CreateFrame("CheckButton", nil, button, "UICheckButtonTemplate")
            checkbox:SetSize(16, 16)
            -- Position checkbox to the left of the name column
            checkbox:SetPoint("LEFT", button, "LEFT", 10, 0)
            
            -- Adjust the name text position
            local nameText = _G[button:GetName().."Name"]
            if nameText then
                local origPoint, relativeTo, relativePoint, xOfs, yOfs = nameText:GetPoint(1)
                nameText:ClearAllPoints()
                nameText:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
            end
            
            checkboxes[button] = checkbox
            checkbox:SetChecked(true)  -- Default to checked
        end
        
        local checkbox = checkboxes[button]
        checkbox.index = index
        
        -- Only show checkbox if there's a valid who result at this index
        if index <= numResults then
            checkbox:Show()
        else
            checkbox:Hide()
        end
    end
end

-- Add select all/none buttons
local selectAllButton = CreateFrame("Button", "CommanderWhoSelectAllButton", WhoFrame, "UIPanelButtonTemplate")
selectAllButton:SetSize(80, 22)
selectAllButton:SetPoint("TOPRIGHT", massWhisperButton, "TOPLEFT", -5, 0)
selectAllButton:SetText("Select All")
selectAllButton:SetScript("OnClick", function()
    for _, checkbox in pairs(checkboxes) do
        if checkbox:IsShown() then
            checkbox:SetChecked(true)
        end
    end
end)

local selectNoneButton = CreateFrame("Button", "CommanderWhoSelectNoneButton", WhoFrame, "UIPanelButtonTemplate")
selectNoneButton:SetSize(80, 22)
selectNoneButton:SetPoint("TOPRIGHT", selectAllButton, "TOPLEFT", -5, 0)
selectNoneButton:SetText("Select None")
selectNoneButton:SetScript("OnClick", function()
    for _, checkbox in pairs(checkboxes) do
        if checkbox:IsShown() then
            checkbox:SetChecked(false)
        end
    end
end)

-- Note: FriendsFrameWhoButton does not exist on this client; a nil entry
-- here would stop ipairs early and skip the buttons after it
local whoElements = {
    WhoFrameColumnHeader1,
    WhoFrameColumnHeader2,
    WhoFrameColumnHeader3,
    WhoFrameColumnHeader4,
    WhoFrameColumnHeader5,
    massWhisperButton,
    selectAllButton,
    selectNoneButton
}

local function UpdateWhoVisibility()
    local isVisible = CommanderWhoDB.ShowWhoButton
    for _, element in ipairs(whoElements) do
        if element then
            element:SetShown(isVisible)
            element:SetAlpha(isVisible and 1 or 0)
        end
    end

    isVisible = CommanderWhoDB.ShowWhoWindow
    if WhoFrame then
        WhoFrame:SetShown(isVisible)
        WhoFrame:SetAlpha(isVisible and 1 or 0)
    end
end

local function OnDestroy() end

local function OnUpdate()
    UpdateWhoVisibility()
end

-- Update OnAwake to ensure WhoFrame exists
local function OnAwake()
    -- Wait for WhoFrame to be available
    C_Timer.After(1, function()  -- Increased delay to ensure frames are loaded
        if WhoFrame then
            AddListener(COMMANDER_WHO_EVENTS.UPDATE, OnUpdate)
            HookWhoScroll()
            UpdateWhoCheckboxes()
            Notify(COMMANDER_WHO_EVENTS.UPDATE)
        else
            -- Try again if WhoFrame isn't loaded yet
            C_Timer.After(0.5, OnAwake)
        end
    end)
end

-- Update the frame event handler
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        loaded = true
        C_Timer.After(0.5, OnAwake)  -- Delay initialization
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "WHO_LIST_UPDATE" then
        -- Cache who results
        whoList = {}
        local numResults = C_FriendList.GetNumWhoResults()
        for i = 1, numResults do
            local whoInfo = C_FriendList.GetWhoInfo(i)
            if whoInfo and whoInfo.fullName then
                table.insert(whoList, whoInfo.fullName)
            end
        end
        -- Update checkboxes after who list updates
        C_Timer.After(0.1, UpdateWhoCheckboxes)  -- Small delay to ensure WHO_LIST_UPDATE is complete
    elseif loaded and CommanderWhoDB.ShowWhoWindow == false then
        OnUpdate()
    end
end)

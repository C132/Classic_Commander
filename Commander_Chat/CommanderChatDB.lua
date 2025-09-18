CommanderChatDB = _G.CommanderChatDB or {}

local showChatWindowCheckbox
local showChatButtonCheckbox
local soundPingWhisperCheckbox
local soundPingPartyCheckbox
local soundVolumeSlider
local whisperSoundDropdown
local partySoundDropdown
local soundChannelDropdown
local testWhisperButton
local testPartyButton

COMMANDER_CHAT_EVENTS = {
    UPDATE = "COMMANDER_CHAT_UPDATE"
}

local DefaultSettings = {
    ShowChatWindow = true,
    ShowChatButton = true,
    SoundPingWhisper = false,
    SoundPingParty = false,
    SoundVolume = 1.0,
    WhisperSound = "IG_CHARACTER_INFO_TAB",
    PartySound = "IG_CHARACTER_INFO_TAB",
    SoundChannel = "Master",
}

for key, value in pairs(DefaultSettings) do
    if CommanderChatDB[key] == nil then
        CommanderChatDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Chat")
    for key, value in pairs(DefaultSettings) do
        CommanderChatDB[key] = value
    end
    Notify(COMMANDER_CHAT_EVENTS.UPDATE)
end

-- Available sounds for selection
local AvailableSounds = {
    {text = "Character Info Tab", value = "IG_CHARACTER_INFO_TAB"},
    {text = "Quest Complete", value = "UI_QUEST_COMPLETE"},
    {text = "Level Up", value = "LEVELUP"},
    {text = "Achievement", value = "ACHIEVEMENT"},
    {text = "Loot Window Open", value = "LOOT_WINDOW_OPEN"},
    {text = "Raid Warning", value = "RAID_WARNING"},
    {text = "Ready Check", value = "READY_CHECK"},
    {text = "PvP Flag", value = "PVP_THROUGH_QUEUE"},
    {text = "Error Message", value = "UI_ERROR_MESSAGE"},
    {text = "Quest Log Open", value = "UI_QUEST_LOG_OPEN"},
    {text = "Spell Book Open", value = "UI_SPELLBOOK_OPEN"},
    {text = "Talent Open", value = "UI_TALENT_OPEN"},
    {text = "Trade Window Open", value = "UI_TRADE_WINDOW_OPEN"},
    {text = "Guild Bank Open", value = "UI_GUILD_BANK_OPEN"},
    {text = "Auction House Open", value = "UI_AUCTION_WINDOW_OPEN"},
}

local AvailableChannels = {
    {text = "Master", value = "Master"},
    {text = "SFX", value = "SFX"},
    {text = "Music", value = "Music"},
    {text = "Ambience", value = "Ambience"},
    {text = "Dialog", value = "Dialog"},
}

local function PlayTestSound(soundType)
    local soundKit, channel
    
    if soundType == "whisper" then
        soundKit = SOUNDKIT[CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB"]
        channel = CommanderChatDB.SoundChannel or "Master"
    elseif soundType == "party" then
        soundKit = SOUNDKIT[CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB"]
        channel = CommanderChatDB.SoundChannel or "Master"
    end
    
    if soundKit and channel then
        PlaySound(soundKit, channel)
        
        -- For louder sounds, play multiple times based on volume setting
        local volume = CommanderChatDB.SoundVolume or 1.0
        if volume > 1.0 then
            local extraPlays = math.floor(volume)
            for i = 1, extraPlays - 1 do
                C_Timer.After(i * 0.1, function()
                    PlaySound(soundKit, channel)
                end)
            end
        end
    end
end

local function InitializeDropdown(dropdown, items, currentValue, callback, soundType)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                UIDropDownMenu_SetText(dropdown, item.text)
                callback(item.value)
                -- Play test sound when selection changes
                if soundType then
                    C_Timer.After(0.1, function()
                        PlayTestSound(soundType)
                    end)
                end
            end
            if item.value == currentValue then
                info.checked = true
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedValue(dropdown, currentValue)
end

local function InitializeSlashCommands(categoryID)
    SLASH_COMMANDERCHAT1 = "/commanderchat"
    SLASH_COMMANDERCHAT2 = "/cchat"
    SlashCmdList["COMMANDERCHAT"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Chat Reset")
        elseif msg == "test whisper" then
            if CommanderChatDB.SoundPingWhisper then
                local soundKit = SOUNDKIT[CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB"]
                local channel = CommanderChatDB.SoundChannel or "Master"
                print("Commander Chat: Testing whisper sound: " .. (CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB") .. " on channel: " .. channel)
                PlaySound(soundKit, channel)
            else
                print("Commander Chat: Whisper sound pings are disabled. Enable them in settings first.")
            end
        elseif msg == "test party" then
            if CommanderChatDB.SoundPingParty then
                local soundKit = SOUNDKIT[CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB"]
                local channel = CommanderChatDB.SoundChannel or "Master"
                print("Commander Chat: Testing party sound: " .. (CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB") .. " on channel: " .. channel)
                PlaySound(soundKit, channel)
            else
                print("Commander Chat: Party sound pings are disabled. Enable them in settings first.")
            end
        else
            print("Usage: /commanderchat or /cchat [reset|test whisper|test party]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Chat"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Chat Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Chat options below.")

    showChatWindowCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showChatWindowCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showChatWindowCheckbox.Text:SetText("Show Chat Window")
    showChatWindowCheckbox:SetChecked(CommanderChatDB.ShowChatWindow)
    showChatWindowCheckbox:SetScript("OnClick", function(self)
        CommanderChatDB.ShowChatWindow = self:GetChecked()
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    showChatButtonCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate") 
    showChatButtonCheckbox:SetPoint("TOPLEFT", showChatWindowCheckbox, "BOTTOMLEFT", 0, -8)
    showChatButtonCheckbox.Text:SetText("Show Chat Button")
    showChatButtonCheckbox:SetChecked(CommanderChatDB.ShowChatButton)
    showChatButtonCheckbox:SetScript("OnClick", function(self)
        CommanderChatDB.ShowChatButton = self:GetChecked()
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    soundPingWhisperCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    soundPingWhisperCheckbox:SetPoint("TOPLEFT", showChatButtonCheckbox, "BOTTOMLEFT", 0, -8)
    soundPingWhisperCheckbox.Text:SetText("Sound Ping for Whispers")
    soundPingWhisperCheckbox:SetChecked(CommanderChatDB.SoundPingWhisper)
    soundPingWhisperCheckbox:SetScript("OnClick", function(self)
        CommanderChatDB.SoundPingWhisper = self:GetChecked()
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    soundPingPartyCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    soundPingPartyCheckbox:SetPoint("TOPLEFT", soundPingWhisperCheckbox, "BOTTOMLEFT", 0, -8)
    soundPingPartyCheckbox.Text:SetText("Sound Ping for Party Messages")
    soundPingPartyCheckbox:SetChecked(CommanderChatDB.SoundPingParty)
    soundPingPartyCheckbox:SetScript("OnClick", function(self)
        CommanderChatDB.SoundPingParty = self:GetChecked()
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    -- Sound Volume Slider
    local volumeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    volumeLabel:SetPoint("TOPLEFT", soundPingPartyCheckbox, "BOTTOMLEFT", 0, -16)
    volumeLabel:SetText("Sound Volume")

    soundVolumeSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    soundVolumeSlider:SetPoint("TOPLEFT", volumeLabel, "BOTTOMLEFT", 0, -8)
    soundVolumeSlider:SetMinMaxValues(0.1, 5.0)
    soundVolumeSlider:SetValueStep(0.1)
    soundVolumeSlider:SetObeyStepOnDrag(true)
    soundVolumeSlider.Low:SetText("0.1")
    soundVolumeSlider.High:SetText("5.0")
    
    -- Ensure we have a valid volume value
    local volumeValue = CommanderChatDB.SoundVolume or 1.0
    soundVolumeSlider:SetValue(volumeValue)
    soundVolumeSlider.Text:SetText(string.format("%.1f", volumeValue))
    
    soundVolumeSlider:SetScript("OnValueChanged", function(self, value)
        CommanderChatDB.SoundVolume = value
        self.Text:SetText(string.format("%.1f", value))
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
        -- Play test sound when volume changes (with a small delay to avoid spam)
        if not soundVolumeSlider.testTimer then
            soundVolumeSlider.testTimer = C_Timer.NewTimer(0.5, function()
                PlayTestSound("whisper")
                soundVolumeSlider.testTimer = nil
            end)
        end
    end)

    -- Whisper Sound Dropdown
    local whisperSoundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    whisperSoundLabel:SetPoint("TOPLEFT", soundVolumeSlider, "BOTTOMLEFT", 0, -16)
    whisperSoundLabel:SetText("Whisper Sound")

    whisperSoundDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    whisperSoundDropdown:SetPoint("TOPLEFT", whisperSoundLabel, "BOTTOMLEFT", -16, -8)
    UIDropDownMenu_SetWidth(whisperSoundDropdown, 200)
    UIDropDownMenu_SetText(whisperSoundDropdown, CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB")

    -- Party Sound Dropdown
    local partySoundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    partySoundLabel:SetPoint("TOPLEFT", whisperSoundDropdown, "BOTTOMLEFT", 16, -16)
    partySoundLabel:SetText("Party Sound")

    partySoundDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    partySoundDropdown:SetPoint("TOPLEFT", partySoundLabel, "BOTTOMLEFT", -16, -8)
    UIDropDownMenu_SetWidth(partySoundDropdown, 200)
    UIDropDownMenu_SetText(partySoundDropdown, CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB")

    -- Sound Channel Dropdown
    local soundChannelLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    soundChannelLabel:SetPoint("TOPLEFT", partySoundDropdown, "BOTTOMLEFT", 16, -16)
    soundChannelLabel:SetText("Sound Channel")

    soundChannelDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    soundChannelDropdown:SetPoint("TOPLEFT", soundChannelLabel, "BOTTOMLEFT", -16, -8)
    UIDropDownMenu_SetWidth(soundChannelDropdown, 200)
    UIDropDownMenu_SetText(soundChannelDropdown, CommanderChatDB.SoundChannel or "Master")

    -- Test Buttons
    local testButtonsLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    testButtonsLabel:SetPoint("TOPLEFT", soundChannelDropdown, "BOTTOMLEFT", 16, -16)
    testButtonsLabel:SetText("Test Sounds")

    testWhisperButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testWhisperButton:SetPoint("TOPLEFT", testButtonsLabel, "BOTTOMLEFT", 0, -8)
    testWhisperButton:SetSize(120, 22)
    testWhisperButton:SetText("Test Whisper")
    testWhisperButton:SetScript("OnClick", function()
        PlayTestSound("whisper")
    end)

    testPartyButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testPartyButton:SetPoint("LEFT", testWhisperButton, "RIGHT", 10, 0)
    testPartyButton:SetSize(120, 22)
    testPartyButton:SetText("Test Party")
    testPartyButton:SetScript("OnClick", function()
        PlayTestSound("party")
    end)

    -- Initialize dropdowns
    InitializeDropdown(whisperSoundDropdown, AvailableSounds, CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB", function(value)
        CommanderChatDB.WhisperSound = value
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end, "whisper")
    
    InitializeDropdown(partySoundDropdown, AvailableSounds, CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB", function(value)
        CommanderChatDB.PartySound = value
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end, "party")
    
    InitializeDropdown(soundChannelDropdown, AvailableChannels, CommanderChatDB.SoundChannel or "Master", function(value)
        CommanderChatDB.SoundChannel = value
        Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if showChatWindowCheckbox then
        showChatWindowCheckbox:SetChecked(CommanderChatDB.ShowChatWindow)
    end
    if showChatButtonCheckbox then
        showChatButtonCheckbox:SetChecked(CommanderChatDB.ShowChatButton)
    end
    if soundPingWhisperCheckbox then
        soundPingWhisperCheckbox:SetChecked(CommanderChatDB.SoundPingWhisper)
    end
    if soundPingPartyCheckbox then
        soundPingPartyCheckbox:SetChecked(CommanderChatDB.SoundPingParty)
    end
    if soundVolumeSlider then
        local volumeValue = CommanderChatDB.SoundVolume or 1.0
        soundVolumeSlider:SetValue(volumeValue)
        soundVolumeSlider.Text:SetText(string.format("%.1f", volumeValue))
    end
    if whisperSoundDropdown then
        local whisperSound = CommanderChatDB.WhisperSound or "IG_CHARACTER_INFO_TAB"
        UIDropDownMenu_SetSelectedValue(whisperSoundDropdown, whisperSound)
        for _, sound in ipairs(AvailableSounds) do
            if sound.value == whisperSound then
                UIDropDownMenu_SetText(whisperSoundDropdown, sound.text)
                break
            end
        end
    end
    if partySoundDropdown then
        local partySound = CommanderChatDB.PartySound or "IG_CHARACTER_INFO_TAB"
        UIDropDownMenu_SetSelectedValue(partySoundDropdown, partySound)
        for _, sound in ipairs(AvailableSounds) do
            if sound.value == partySound then
                UIDropDownMenu_SetText(partySoundDropdown, sound.text)
                break
            end
        end
    end
    if soundChannelDropdown then
        local soundChannel = CommanderChatDB.SoundChannel or "Master"
        UIDropDownMenu_SetSelectedValue(soundChannelDropdown, soundChannel)
        for _, channel in ipairs(AvailableChannels) do
            if channel.value == soundChannel then
                UIDropDownMenu_SetText(soundChannelDropdown, channel.text)
                break
            end
        end
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Chat")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_CHAT_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy() end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)
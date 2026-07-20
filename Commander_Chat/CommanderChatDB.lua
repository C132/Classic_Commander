CommanderChatDB = _G.CommanderChatDB or {}

COMMANDER_CHAT_EVENTS = {
    UPDATE = "COMMANDER_CHAT_UPDATE"
}

local DefaultSettings = {
    ShowChatWindow = true,
    ShowChatButton = true,
    SoundPingWhisper = false,
    SoundPingParty = false,
    WhisperSound = "IG_CHARACTER_INFO_TAB",
    PartySound = "IG_CHARACTER_INFO_TAB",
    SoundChannel = "Master",
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderChatDB, DefaultSettings)
    Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
    print("Commander Chat: settings restored to defaults")
end

-- Available sounds for selection (keys verified against the 2.5.5 client's SOUNDKIT table)
local AvailableSounds = {
    {text = "Character Info Tab", value = "IG_CHARACTER_INFO_TAB"},
    {text = "Quest Complete", value = "IG_QUEST_LIST_COMPLETE"},
    {text = "Whisper Tell", value = "TELL_MESSAGE"},
    {text = "Raid Boss Emote", value = "RAID_BOSS_EMOTE_WARNING"},
    {text = "Loot Coins", value = "LOOT_WINDOW_COIN_SOUND"},
    {text = "Raid Warning", value = "RAID_WARNING"},
    {text = "Ready Check", value = "READY_CHECK"},
    {text = "PvP Flag", value = "PVP_THROUGH_QUEUE"},
    {text = "Player Invite", value = "IG_PLAYER_INVITE"},
    {text = "Quest Log Open", value = "IG_QUEST_LOG_OPEN"},
    {text = "Spell Book Open", value = "IG_SPELLBOOK_OPEN"},
    {text = "Talent Open", value = "TALENT_SCREEN_OPEN"},
    {text = "Character Info Open", value = "IG_CHARACTER_INFO_OPEN"},
    {text = "Guild Bank Open", value = "GUILD_BANK_OPEN_BAG"},
    {text = "Auction House Open", value = "AUCTION_WINDOW_OPEN"},
}

local AvailableChannels = {
    {text = "Master", value = "Master"},
    {text = "SFX", value = "SFX"},
    {text = "Music", value = "Music"},
    {text = "Ambience", value = "Ambience"},
    {text = "Dialog", value = "Dialog"},
}

-- Preview an alert sound. With announce=true (test buttons, slash commands)
-- it prints what played and warns when the corresponding alert toggle is off,
-- so a successful preview is never mistaken for an armed alert. The silent
-- form is used by the dropdowns' auto-preview on selection.
local function PlayTestSound(soundType, announce)
    local soundName, enabled, label
    if soundType == "whisper" then
        soundName = CommanderChatDB.WhisperSound
        enabled = CommanderChatDB.SoundPingWhisper
        label = "whisper"
    else
        soundName = CommanderChatDB.PartySound
        enabled = CommanderChatDB.SoundPingParty
        label = "party"
    end

    soundName = soundName or "IG_CHARACTER_INFO_TAB"
    local soundKit = SOUNDKIT[soundName]
    local channel = CommanderChatDB.SoundChannel or "Master"
    if soundKit then
        PlaySound(soundKit, channel)
    end

    if announce then
        print(string.format("Commander Chat: playing %s sound '%s' on the %s channel", label, soundName, channel))
        if not enabled then
            print(string.format("Commander Chat: note - %s sound alerts are currently disabled, so real messages will not play this sound", label))
        end
    end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Chat",
        title = "Chat",
        addonName = "Commander_Chat",
        description = "Keeps chat on your terms: hide the chat frame entirely for a clean battlefield view, and add distinct alert sounds for whispers and party chat so nothing slips past you.",
        event = COMMANDER_CHAT_EVENTS.UPDATE,
        slash = { "/cchat", "/commanderchat" },
        slashHandlers = {
            ["test whisper"] = function() PlayTestSound("whisper", true) end,
            ["test party"] = function() PlayTestSound("party", true) end,
        },
    })

    panel:AddSection("Chat Frame")
    panel:AddCheckbox({
        label = "Show Chat Window",
        tooltip = "Show the main chat window and its tabs. Uncheck for a fully clean screen.",
        get = function() return CommanderChatDB.ShowChatWindow end,
        set = function(value) CommanderChatDB.ShowChatWindow = value end,
    })
    panel:AddCheckbox({
        label = "Show Chat Buttons",
        tooltip = "Show the chat menu, channel, and social buttons next to the chat window.",
        get = function() return CommanderChatDB.ShowChatButton end,
        set = function(value) CommanderChatDB.ShowChatButton = value end,
    })

    panel:AddSection("Sound Alerts", "Selecting a sound previews it; /cchat test whisper (or test party) prints exactly what plays.")
    panel:AddCheckbox({
        label = "Play Sound on Whisper",
        tooltip = "Play an alert sound whenever you receive a whisper.",
        get = function() return CommanderChatDB.SoundPingWhisper end,
        set = function(value) CommanderChatDB.SoundPingWhisper = value end,
    })
    panel:AddDropdown({
        label = "Whisper Sound",
        tooltip = "The sound played when a whisper arrives. Selecting a sound previews it.",
        options = AvailableSounds,
        get = function() return CommanderChatDB.WhisperSound end,
        set = function(value) CommanderChatDB.WhisperSound = value end,
        isEnabled = function() return CommanderChatDB.SoundPingWhisper end,
        onSelect = function() C_Timer.After(0.1, function() PlayTestSound("whisper") end) end,
    })
    panel:AddCheckbox({
        label = "Play Sound on Party Chat",
        tooltip = "Play an alert sound whenever a party message arrives.",
        get = function() return CommanderChatDB.SoundPingParty end,
        set = function(value) CommanderChatDB.SoundPingParty = value end,
    })
    panel:AddDropdown({
        label = "Party Sound",
        tooltip = "The sound played when a party message arrives. Selecting a sound previews it.",
        options = AvailableSounds,
        get = function() return CommanderChatDB.PartySound end,
        set = function(value) CommanderChatDB.PartySound = value end,
        isEnabled = function() return CommanderChatDB.SoundPingParty end,
        onSelect = function() C_Timer.After(0.1, function() PlayTestSound("party") end) end,
    })
    panel:AddDropdown({
        label = "Sound Channel",
        tooltip = "Which audio channel alert sounds play through. Master ignores the SFX volume slider, so alerts stay audible even with game sounds muted.",
        options = AvailableChannels,
        width = 120,
        get = function() return CommanderChatDB.SoundChannel end,
        set = function(value) CommanderChatDB.SoundChannel = value end,
        isEnabled = function() return CommanderChatDB.SoundPingWhisper or CommanderChatDB.SoundPingParty end,
    })
    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        if arg1 == "Commander_Chat" then
            Commander.UI.ApplyDefaults(CommanderChatDB, DefaultSettings)
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

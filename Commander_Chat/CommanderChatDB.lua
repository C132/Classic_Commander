CommanderChatDB = _G.CommanderChatDB or {}

COMMANDER_CHAT_EVENTS = {
    UPDATE = "COMMANDER_CHAT_UPDATE"
}

local DefaultSettings = {
    -- Master switch. Off makes the whole module inert and hands Blizzard's
    -- chat back exactly as it was.
    Enabled = true,
    -- Opt-in: the replacement window, off until asked for
    ReplaceChatFrame = false,
    ShowChatWindow = true,
    ShowChatButton = true,
    SoundPingWhisper = false,
    SoundPingParty = false,
    WhisperSound = "IG_CHARACTER_INFO_TAB",
    PartySound = "IG_CHARACTER_INFO_TAB",
    SoundChannel = "Master",
    Timestamps = false,
    ShortChannels = false,
    CombatQuiet = false,
    CombatQuietAlpha = 0.15,
    KeepChatVisible = false,
    -- Footprint
    ResizeChat = false,
    ChatWidth = 430,
    ChatHeight = 120,
    ChatScale = 1.0,
    FontSize = 0,
    -- Fade & focus
    MouseoverOnly = false,
    IdleAlpha = 0.2,
    FadeDelay = 120,
    BackgroundAlpha = 0.25,
    -- Channel noise
    MuteWorldChannels = false,
    MutedChannels = {},
}

-- Shared HUD chrome (style / scale / lock / position) for the replacement
-- window, same treatment every other Commander on-screen frame gets
for key, value in pairs(Commander.UI.HudChromeDefaults("Window", "DARK")) do
    DefaultSettings[key] = value
end

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

-- ---------------------------------------------------------------------------
-- Channel picker: the joined-channel list is live, so its dropdown options are
-- rebuilt on every panel refresh rather than baked in at construction
-- ---------------------------------------------------------------------------
local channelOptions = {}
local selectedChannel = ""

local function RefreshChannelOptions()
    wipe(channelOptions)
    local muted = CommanderChatDB.MutedChannels or {}
    local seen = {}

    local joined = CommanderChat_JoinedChannels and CommanderChat_JoinedChannels() or {}
    for _, channel in ipairs(joined) do
        local key = channel.name:lower()
        seen[key] = true
        channelOptions[#channelOptions + 1] = {
            text = string.format("%d. %s%s", channel.id, channel.name, muted[key] and " (muted)" or ""),
            value = channel.name,
        }
    end
    -- A channel muted and then left stays listed, so the mute can be lifted
    -- without having to rejoin the channel first just to find it here
    for key in pairs(muted) do
        if not seen[key] then
            channelOptions[#channelOptions + 1] = { text = key .. " (muted, not joined)", value = key }
        end
    end
    if #channelOptions == 0 then
        channelOptions[1] = { text = "No channels joined", value = "" }
    end

    local stillListed = false
    for _, option in ipairs(channelOptions) do
        if option.value == selectedChannel then
            stillListed = true
            break
        end
    end
    if not stillListed then
        selectedChannel = channelOptions[1].value
    end
end

local function MutedChannelSummary()
    local muted = CommanderChatDB.MutedChannels or {}
    local names = {}
    for key in pairs(muted) do
        names[#names + 1] = key
    end
    table.sort(names)
    if CommanderChatDB.MuteWorldChannels then
        table.insert(names, 1, "all world channels")
    end
    if #names == 0 then
        return "|cff909090Nothing muted — every channel you have joined prints in full.|r"
    end
    return "|cffffd100Muted:|r " .. table.concat(names, ", ")
end

local function FormatPixels(value)
    return string.format("%d", value)
end

local function FormatSeconds(value)
    return string.format("%ds", value)
end

local function FormatFontSize(value)
    if value == 0 then return "Default" end
    return string.format("%d", value)
end

-- Every control on the page answers to the master flag, so a disabled module
-- reads as disabled instead of looking live while doing nothing
local function On()
    return CommanderChatDB.Enabled
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Chat",
        title = "Chat",
        addonName = "Commander_Chat",
        description = "Chat on your terms, and no larger than you want it: quick layouts that shrink the window to a footnote, size/scale/font controls, mouseover-only fading so idle chat all but disappears, world-channel muting that keeps you able to post, plus timestamps, compact tags, combat quiet, and alert sounds for whispers and party.",
        event = COMMANDER_CHAT_EVENTS.UPDATE,
        slash = { "/cchat", "/commanderchat" },
        slashHandlers = {
            ["test whisper"] = function() PlayTestSound("whisper", true) end,
            ["test party"] = function() PlayTestSound("party", true) end,
            mini = function() CommanderChat_ApplyPreset("MINIMAL") end,
            full = function() CommanderChat_ApplyPreset("STANDARD") end,
            channels = function() CommanderChat_ReportChannels() end,
            off = function()
                if CommanderChatDB.Enabled then CommanderChat_ToggleEnabled() end
            end,
            on = function()
                if not CommanderChatDB.Enabled then CommanderChat_ToggleEnabled() end
            end,
        },
    })

    -- Far taller than the Settings canvas, so flow the rows into a scroll
    -- frame. NewPanel's header stays fixed above; AddRow is overridden on THIS
    -- panel instance only, so the shared framework is untouched.
    local scroll = CreateFrame("ScrollFrame", "CommanderChatScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel._anchor, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 28
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnSizeChanged", function(_, w) scrollChild:SetWidth(w) end)

    local seed = CreateFrame("Frame", nil, scrollChild)
    seed:SetHeight(1)
    seed:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    seed:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    panel._anchor = seed
    panel._contentHeight = 0
    panel.AddRow = function(self, height, spacing)
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(height)
        row:SetPoint("TOPLEFT", self._anchor, "BOTTOMLEFT", 0, -(spacing or 8))
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        self._anchor = row
        self._contentHeight = self._contentHeight + height + (spacing or 8)
        return row
    end

    panel:AddSection("Module", "The master switch. Turned off, this addon touches nothing — Blizzard's chat window, fonts, opacity, and channels all go back to how they were, and nothing here does anything until you turn it on again.")
    panel:AddCheckboxPair({
        label = "Enable Commander Chat",
        tooltip = "Master switch for everything on this page. Off restores Blizzard's chat completely and leaves it alone — the fastest way to rule this addon out while chasing a problem. Same as /cchat off.",
        get = function() return CommanderChatDB.Enabled end,
        set = function(value) CommanderChatDB.Enabled = value end,
    }, {
        label = "Replacement Window",
        tooltip = "Swap Blizzard's chat window for a Commander one: our own frame, our own fading, drag and scale like every other Commander HUD frame. Blizzard's window is parked out of sight but keeps doing all the message formatting, so colors, links, and channels are identical. Typing still works exactly as it does now — press Enter. Two limits worth knowing: it starts empty rather than inheriting your scrollback, and it mirrors your main chat window only — any other docked window, the combat log included, is parked along with its tab until you switch this back off.",
        get = function() return CommanderChatDB.ReplaceChatFrame end,
        set = function(value) CommanderChatDB.ReplaceChatFrame = value end,
        isEnabled = On,
    })

    panel:AddSection("Quick Layouts", "Two presets that move every footprint setting below at once. Minimal shrinks and dims chat to a corner footnote; Standard hands the screen back.")
    panel:AddButtonRow({
        {
            label = "Minimal Chat",
            width = 150,
            tooltip = "Small, scaled down, mouseover-only, no tabs or buttons, no background, world channels muted, lines fading after 20 seconds. Same as /cchat mini.",
            onClick = function() CommanderChat_ApplyPreset("MINIMAL") end,
        },
        {
            label = "Standard Chat",
            width = 150,
            tooltip = "Blizzard's footprint back: default size and font, always visible, tabs and buttons shown, nothing muted. Same as /cchat full.",
            onClick = function() CommanderChat_ApplyPreset("STANDARD") end,
        },
    })

    panel:AddSection("Chat Frame")
    panel:AddCheckboxPair({
        label = "Show Chat Window",
        tooltip = "Show the main chat window and its tabs. Uncheck for a fully clean screen.",
        get = function() return CommanderChatDB.ShowChatWindow end,
        set = function(value) CommanderChatDB.ShowChatWindow = value end,
        isEnabled = On,
    }, {
        label = "Show Chat Buttons",
        tooltip = "Show the chat menu, channel, and social buttons next to the chat window.",
        get = function() return CommanderChatDB.ShowChatButton end,
        set = function(value) CommanderChatDB.ShowChatButton = value end,
        isEnabled = On,
    })
    panel:AddCheckboxPair({
        label = "Short Channel Tags",
        tooltip = "Compact channel prefixes, RTS-brief: [Party] becomes [P], [Guild] [G], [Raid Leader] [RL], numbered channels just [2].",
        get = function() return CommanderChatDB.ShortChannels end,
        set = function(value) CommanderChatDB.ShortChannels = value end,
        isEnabled = On,
    }, {
        label = "Timestamps",
        tooltip = "Prefix every chat line with a 24-hour timestamp (sets the client's timestamp option; unchecking turns timestamps off).",
        get = function() return CommanderChatDB.Timestamps end,
        set = function(value) CommanderChatDB.Timestamps = value end,
        isEnabled = On,
    })
    panel:AddCheckbox({
        label = "Keep Chat Visible",
        tooltip = "Stop chat lines from fading out over time; every window keeps its full history on screen. Overrides the fade delay below.",
        get = function() return CommanderChatDB.KeepChatVisible end,
        set = function(value) CommanderChatDB.KeepChatVisible = value end,
        isEnabled = On,
    })

    panel:AddSection("Footprint", "How much screen the window itself claims. Size is re-applied after Edit Mode or a layout change puts Blizzard's back.")
    panel:AddCheckbox({
        label = "Resize Chat Frame",
        tooltip = "Take over the chat window's width and height with the sliders below. Unchecking restores the size it had when you logged in.",
        get = function() return CommanderChatDB.ResizeChat end,
        set = function(value) CommanderChatDB.ResizeChat = value end,
        isEnabled = On,
    })
    panel:AddSliderPair({
        label = "Width",
        tooltip = "Chat window width in pixels. Blizzard's own minimum is 296 — going below that is allowed here and simply gives you a narrower column.",
        min = 200, max = 800, step = 10,
        format = FormatPixels,
        get = function() return CommanderChatDB.ChatWidth end,
        set = function(value) CommanderChatDB.ChatWidth = value end,
        isEnabled = function() return On() and (CommanderChatDB.ResizeChat) end,
    }, {
        label = "Height",
        tooltip = "Chat window height in pixels. Around 100 shows roughly four lines at the default font — enough to catch a whisper without owning the corner.",
        min = 60, max = 500, step = 10,
        format = FormatPixels,
        get = function() return CommanderChatDB.ChatHeight end,
        set = function(value) CommanderChatDB.ChatHeight = value end,
        isEnabled = function() return On() and (CommanderChatDB.ResizeChat) end,
    })
    panel:AddSliderPair({
        label = "Scale",
        tooltip = "Shrinks the whole window — text, tabs, and edit box together — while keeping it anchored where it is. The cheapest way to take back screen without losing any lines.",
        min = 0.6, max = 1.2, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderChatDB.ChatScale end,
        set = function(value) CommanderChatDB.ChatScale = value end,
        isEnabled = On,
    }, {
        label = "Font Size",
        tooltip = "Chat font size for every window. Default leaves each window on whatever Blizzard has saved for it; a smaller size fits more lines into less height.",
        min = 0, max = 20, step = 1,
        format = FormatFontSize,
        get = function() return CommanderChatDB.FontSize end,
        set = function(value) CommanderChatDB.FontSize = value end,
        isEnabled = On,
    })

    panel:AddSection("Fade & Focus", "What chat looks like when you are not reading it — the difference between a window you own and one that owns your screen.")
    panel:AddCheckboxPair({
        label = "Mouseover Only",
        tooltip = "Chat drops to the idle opacity below and only comes back to full when you hover it or start typing. Messages still arrive and still ping; they just stop competing for your attention.",
        get = function() return CommanderChatDB.MouseoverOnly end,
        set = function(value) CommanderChatDB.MouseoverOnly = value end,
        isEnabled = function() return On() and (CommanderChatDB.ShowChatWindow) end,
    }, {
        label = "Combat Quiet",
        tooltip = "Fade the chat window while you are in combat — full focus on the fight, chat returns when it ends.",
        get = function() return CommanderChatDB.CombatQuiet end,
        set = function(value) CommanderChatDB.CombatQuiet = value end,
        isEnabled = function() return On() and (CommanderChatDB.ShowChatWindow) end,
    })
    panel:AddSliderPair({
        label = "Idle Opacity",
        tooltip = "How visible chat stays while you are not hovering it. 0% is invisible until you reach for it; 20% leaves a readable ghost.",
        min = 0, max = 0.8, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderChatDB.IdleAlpha end,
        set = function(value) CommanderChatDB.IdleAlpha = value end,
        isEnabled = function() return On() and (CommanderChatDB.MouseoverOnly) end,
    }, {
        label = "Combat Quiet Opacity",
        tooltip = "How visible chat remains during combat: 0% is fully invisible, higher values keep a readable ghost of it.",
        min = 0, max = 0.6, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderChatDB.CombatQuietAlpha end,
        set = function(value) CommanderChatDB.CombatQuietAlpha = value end,
        isEnabled = function() return On() and (CommanderChatDB.CombatQuiet) end,
    })
    panel:AddSliderPair({
        label = "Fade Delay",
        tooltip = "How long a line stays on screen before it fades away. Blizzard's default is 120 seconds; 15-30 keeps only the live conversation visible and lets the rest of the window empty itself out.",
        min = 5, max = 120, step = 5,
        format = FormatSeconds,
        get = function() return CommanderChatDB.FadeDelay end,
        set = function(value) CommanderChatDB.FadeDelay = value end,
        isEnabled = function() return On() and (not CommanderChatDB.KeepChatVisible) end,
    }, {
        label = "Background Opacity",
        tooltip = "The window's boxed background and border. 0% leaves text floating on the world with no frame around it. Blizzard's saved value is left untouched underneath, so this is fully reversible.",
        min = 0, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderChatDB.BackgroundAlpha end,
        set = function(value) CommanderChatDB.BackgroundAlpha = value end,
        isEnabled = On,
    })

    panel:AddSection("Replacement Window", "Framing, scale, and placement for the Commander chat window. Only does anything while Replacement Window is on above.")
    Commander.UI.AddHudChromeOptions(panel, CommanderChatDB, "Window", {
        isEnabled = function() return On() and CommanderChatDB.ReplaceChatFrame end,
    })

    panel:AddSection("Channel Noise", "Muting hides a channel's traffic from every window while leaving you joined — you can still post to it, and the chat frame stops scrolling with other people's business.")
    panel:AddCheckbox({
        label = "Mute World Channels",
        tooltip = "Silence every server zone channel at once — General, Trade, LocalDefense, LookingForGroup and the rest. Channels you joined by name are untouched. Detected by the server's zone-channel id, so it works in any locale.",
        get = function() return CommanderChatDB.MuteWorldChannels end,
        set = function(value) CommanderChatDB.MuteWorldChannels = value end,
        isEnabled = On,
    })

    -- Options rebuilt before the dropdown's own refresher runs, so the list
    -- and its selected label are always drawn from the same snapshot
    panel:AddRefresher(RefreshChannelOptions)
    panel:AddDropdown({
        label = "Channel",
        tooltip = "The channels you are currently in. Pick one to mute, unmute, or leave outright.",
        options = channelOptions,
        width = 220,
        get = function() return selectedChannel end,
        set = function(value) selectedChannel = value end,
    })
    panel:AddButtonRow({
        {
            label = "Mute",
            width = 110,
            tooltip = "Hide this channel's messages. You stay joined and can still post to it.",
            onClick = function()
                CommanderChat_SetChannelMuted(selectedChannel, true)
                Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
            end,
            isEnabled = function() return selectedChannel ~= "" end,
        },
        {
            label = "Unmute",
            width = 110,
            tooltip = "Let this channel's messages through again.",
            onClick = function()
                CommanderChat_SetChannelMuted(selectedChannel, false)
                Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
            end,
            isEnabled = function() return selectedChannel ~= "" end,
        },
        {
            label = "Leave Channel",
            width = 130,
            tooltip = "Leave the channel entirely. Stronger than muting: you can no longer post to it, and zone channels will rejoin themselves the next time you change zone.",
            onClick = function()
                CommanderChat_LeaveChannel(selectedChannel)
                Commander.Notify(COMMANDER_CHAT_EVENTS.UPDATE)
            end,
            isEnabled = function() return selectedChannel ~= "" end,
        },
    })

    local statusRow = panel:AddRow(20, 6)
    local status = statusRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", statusRow, "TOPLEFT", 2, 0)
    status:SetPoint("RIGHT", statusRow, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    panel:AddRefresher(function()
        status:SetText(MutedChannelSummary())
    end)

    panel:AddSection("Sound Alerts", "Selecting a sound previews it; /cchat test whisper (or test party) prints exactly what plays.")
    panel:AddCheckboxPair({
        label = "Play Sound on Whisper",
        tooltip = "Play an alert sound whenever you receive a whisper.",
        get = function() return CommanderChatDB.SoundPingWhisper end,
        set = function(value) CommanderChatDB.SoundPingWhisper = value end,
        isEnabled = On,
    }, {
        label = "Play Sound on Party Chat",
        tooltip = "Play an alert sound whenever a party message arrives.",
        get = function() return CommanderChatDB.SoundPingParty end,
        set = function(value) CommanderChatDB.SoundPingParty = value end,
        isEnabled = On,
    })
    panel:AddDropdownPair({
        label = "Whisper Sound",
        tooltip = "The sound played when a whisper arrives. Selecting a sound previews it.",
        options = AvailableSounds,
        get = function() return CommanderChatDB.WhisperSound end,
        set = function(value) CommanderChatDB.WhisperSound = value end,
        isEnabled = function() return On() and (CommanderChatDB.SoundPingWhisper) end,
        onSelect = function() C_Timer.After(0.1, function() PlayTestSound("whisper") end) end,
    }, {
        label = "Party Sound",
        tooltip = "The sound played when a party message arrives. Selecting a sound previews it.",
        options = AvailableSounds,
        get = function() return CommanderChatDB.PartySound end,
        set = function(value) CommanderChatDB.PartySound = value end,
        isEnabled = function() return On() and (CommanderChatDB.SoundPingParty) end,
        onSelect = function() C_Timer.After(0.1, function() PlayTestSound("party") end) end,
    })
    panel:AddDropdown({
        label = "Sound Channel",
        tooltip = "Which audio channel alert sounds play through. Master ignores the SFX volume slider, so alerts stay audible even with game sounds muted.",
        options = AvailableChannels,
        width = 120,
        get = function() return CommanderChatDB.SoundChannel end,
        set = function(value) CommanderChatDB.SoundChannel = value end,
        isEnabled = function() return On() and (CommanderChatDB.SoundPingWhisper or CommanderChatDB.SoundPingParty) end,
    })
    panel:Finalize({ onDefaults = Reset })
    scrollChild:SetHeight(panel._contentHeight + 24)
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

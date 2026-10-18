-- Commander Guide — saved settings and the settings page
--
-- Settings only. The guide text lives in CommanderGuideData.lua and is never
-- saved; the window position and the banner's chrome keys are the only
-- layout state (DECISIONS D5).

CommanderGuideDB = _G.CommanderGuideDB or {}

COMMANDER_GUIDE_EVENTS = { UPDATE = "COMMANDER_GUIDE_UPDATE" }

local UI = Commander and Commander.UI

local DefaultSettings = {
    Enable = true,
    Role = "HEALER",

    -- the voice
    Voice = true,               -- speak callouts and briefs
    VoiceID = false,            -- false = the client's own Standard TTS voice
    Rate = 0,                   -- -10..10, the client's scale
    Volume = 100,               -- 0..100
    Interrupt = true,           -- an urgent line cuts off the current one
    BriefOnTarget = true,       -- targeting a boss out of combat reads the brief
    BriefFull = false,          -- the brief includes the phase-by-phase
    BriefRepeat = 180,          -- seconds before the same boss is briefed again

    -- the banner (the spoken line, written on screen too)
    Banner = true,
    BannerSeconds = 4,
    BannerSize = 20,

    -- echoes
    Chat = false,               -- print callouts to the chat frame

    -- window
    AutoOpen = false,           -- open the guide on the boss page when you target a boss
    WindowPos = false,
}
if UI and UI.HudChromeDefaults then
    for k, v in pairs(UI.HudChromeDefaults("Banner", "NONE")) do DefaultSettings[k] = v end
end
CommanderGuide_Defaults = DefaultSettings

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Notify()
    if Commander and Commander.Notify then Commander.Notify(COMMANDER_GUIDE_EVENTS.UPDATE) end
end

local function Reset()
    UI.ResetToDefaults(CommanderGuideDB, DefaultSettings)
    Notify()
    print("Commander Guide: settings restored to defaults")
end

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

local function Enabled() return CommanderGuideDB.Enable end
local function VoiceOn() return CommanderGuideDB.Enable and CommanderGuideDB.Voice end

-- The client's voices, as dropdown options; the first option follows the
-- Standard voice picked in Blizzard's own Text to Speech settings.
-- The dropdown builder walks a plain table, so these two are refilled in
-- place from the getters (the framework calls get() before it reads the
-- options), which keeps the voice list live: the client reports its voices
-- some time after login.
local voiceOptions, roleOptions = {}, {}

local function VoiceOptions()
    local options = voiceOptions
    for i = #options, 1, -1 do options[i] = nil end
    options[1] = { text = "Client default", value = false }
    local ok, voices = pcall(function()
        return C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
    end)
    if ok and type(voices) == "table" then
        for _, v in ipairs(voices) do
            if type(v) == "table" and v.voiceID ~= nil then
                options[#options + 1] = { text = tostring(v.name or v.voiceID), value = v.voiceID }
            end
        end
    end
    local chosen = CommanderGuideDB.VoiceID
    if chosen ~= false and chosen ~= nil then
        local present = false
        for _, o in ipairs(options) do if o.value == chosen then present = true end end
        if not present then options[#options + 1] = { text = "Voice " .. tostring(chosen) .. " (missing)", value = chosen } end
    end
    return options
end

local function RoleOptions()
    local options = roleOptions
    for i = #options, 1, -1 do options[i] = nil end
    local D = CommanderGuide_Data
    for _, role in ipairs(D and D.ROLES or {}) do
        options[#options + 1] = {
            text = role.ready and role.title or (role.title .. " (coming)"),
            value = role.key,
        }
    end
    return options
end

local function CreatePanel()
    local panel = UI.NewPanel({
        key = "Guide",
        title = "Guide",
        addonName = "Commander_Guide",
        description = "A raid guide in the game, boss by boss, written for the seat you are in. Open it and read the healer's page for the boss in front of you: the fight in one line, your job, the phases, the debuffs to dispel. Then let it talk: the voice reads the brief when you target the boss, and during the pull it tells you what to do the moment the combat log says it matters -- Garrote on you, Flame Wreath, don't move, Evocation, twenty seconds, top everyone. Karazhan, healer's seat, first.",
        event = COMMANDER_GUIDE_EVENTS.UPDATE,
        slash = { "/cguide", "/cgu" },
        slashHandlers = {
            [""] = function() Call("CommanderGuide_Toggle") end,
            brief = function() Call("CommanderGuide_Brief") end,
            stop = function() Call("CommanderGuide_Stop") end,
            test = function() Call("CommanderGuide_Test") end,
            validate = function() Call("CommanderGuide_Validate") end,
            entrance = function() Call("CommanderGuide_Entrance") end,
            unlock = function() CommanderGuideDB.BannerLocked = false; Notify() end,
            lock = function() CommanderGuideDB.BannerLocked = true; Notify() end,
        },
    })

    panel:AddCheckbox({
        label = "Enable Guide",
        tooltip = "The whole module: the window, the voice and the banner.",
        get = function() return CommanderGuideDB.Enable end,
        set = function(value) CommanderGuideDB.Enable = value end,
    })
    panel:AddDropdown({
        label = "Your seat",
        tooltip = "Which role's page you read and hear. Only the healer's seat is written so far; the others are listed so the shape is visible.",
        options = roleOptions,
        get = function() RoleOptions(); return CommanderGuideDB.Role end,
        set = function(value)
            local D = CommanderGuide_Data
            for _, role in ipairs(D and D.ROLES or {}) do
                if role.key == value and role.ready then CommanderGuideDB.Role = value end
            end
        end,
        isEnabled = Enabled,
    })
    panel:AddButtonRow({
        { label = "Open Guide", tooltip = "Open the guide window on the boss you are targeting, or the first boss of the raid you are in.", onClick = function() Call("CommanderGuide_Toggle") end, isEnabled = Enabled },
        { label = "Read Brief", tooltip = "Read the current boss's brief out loud.", onClick = function() Call("CommanderGuide_Brief") end, isEnabled = VoiceOn },
        { label = "Stop Talking", tooltip = "Cut the voice off and drop anything queued.", onClick = function() Call("CommanderGuide_Stop") end, isEnabled = VoiceOn },
        { label = "Test Voice", tooltip = "Say one line with the voice, rate and volume below.", onClick = function() Call("CommanderGuide_Test") end, isEnabled = VoiceOn },
    })

    panel:AddSection("Getting there", "The raid's door as a Commander Orders waypoint: the arrow walks you to it and the waypoint clears itself when you arrive. Without Commander Orders the button prints the /way line instead. Also /cguide entrance, a key binding, and Go to Entrance under the boss list in the guide window.")
    panel:AddButtonRow({
        { label = "Go to Entrance", width = 170, tooltip = "Point the Commander Orders arrow at the entrance of the raid the guide is showing (Karazhan's doors in Deadwind Pass for now; the arrow takes the nearer one). The window's button is greyed out while you are inside that raid, and its Shift-click shares the door in chat.", onClick = function() Call("CommanderGuide_Entrance") end, isEnabled = Enabled },
    })

    panel:AddSection("The voice", "Callouts are spoken through the client's own text-to-speech, the same engine that reads chat.")
    panel:AddCheckbox({
        label = "Speak callouts",
        tooltip = "Off, nothing is spoken; the banner and the window still work.",
        get = function() return CommanderGuideDB.Voice end,
        set = function(value) CommanderGuideDB.Voice = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Voice",
        tooltip = "One of the voices installed on this machine. Client default follows the Standard voice in Blizzard's Text to Speech options.",
        options = voiceOptions,
        get = function() VoiceOptions(); return CommanderGuideDB.VoiceID end,
        set = function(value) CommanderGuideDB.VoiceID = value end,
        isEnabled = VoiceOn,
        onSelect = function() Call("CommanderGuide_Test") end,
    })
    panel:AddSliderPair({
        label = "Rate",
        tooltip = "Speech rate on the client's scale. Zero is the voice's natural pace; combat lines are short, so faster is fine.",
        min = -10, max = 10, step = 1, format = "%d",
        get = function() return CommanderGuideDB.Rate end,
        set = function(value) CommanderGuideDB.Rate = value end,
        isEnabled = VoiceOn,
    }, {
        label = "Volume",
        tooltip = "Speech volume, 0 to 100.",
        min = 0, max = 100, step = 5, format = "%d",
        get = function() return CommanderGuideDB.Volume end,
        set = function(value) CommanderGuideDB.Volume = value end,
        isEnabled = VoiceOn,
    })
    panel:AddCheckboxPair({
        label = "Urgent lines interrupt",
        tooltip = "A priority line (Flame Wreath, Enfeebled, run) cuts off whatever is being said and clears the routine lines behind it. Off, everything waits its turn.",
        get = function() return CommanderGuideDB.Interrupt end,
        set = function(value) CommanderGuideDB.Interrupt = value end,
        isEnabled = VoiceOn,
    }, {
        label = "Brief on target",
        tooltip = "Targeting a boss out of combat reads its brief: the one line and your job. Once per boss every few minutes.",
        get = function() return CommanderGuideDB.BriefOnTarget end,
        set = function(value) CommanderGuideDB.BriefOnTarget = value end,
        isEnabled = VoiceOn,
    })
    panel:AddCheckbox({
        label = "Brief includes the phases",
        tooltip = "The spoken brief also reads the phase-by-phase section. Longer; better for a first kill.",
        get = function() return CommanderGuideDB.BriefFull end,
        set = function(value) CommanderGuideDB.BriefFull = value end,
        isEnabled = VoiceOn,
    })

    panel:AddSection("The banner", "Every spoken line is also written on screen for a few seconds.")
    panel:AddCheckbox({
        label = "Show the banner",
        get = function() return CommanderGuideDB.Banner end,
        set = function(value) CommanderGuideDB.Banner = value end,
        isEnabled = Enabled,
    })
    panel:AddSliderPair({
        label = "Seconds on screen",
        min = 2, max = 10, step = 1, format = "%d s",
        get = function() return CommanderGuideDB.BannerSeconds end,
        set = function(value) CommanderGuideDB.BannerSeconds = value end,
        isEnabled = function() return Enabled() and CommanderGuideDB.Banner end,
    }, {
        label = "Text size",
        min = 12, max = 32, step = 1, format = "%d",
        get = function() return CommanderGuideDB.BannerSize end,
        set = function(value) CommanderGuideDB.BannerSize = value end,
        isEnabled = function() return Enabled() and CommanderGuideDB.Banner end,
    })
    if UI.AddHudChromeOptions then
        UI.AddHudChromeOptions(panel, CommanderGuideDB, "Banner", {
            isEnabled = function() return Enabled() and CommanderGuideDB.Banner end,
        })
    end
    panel:AddCheckboxPair({
        label = "Echo to chat",
        tooltip = "Print each callout to the chat frame as well.",
        get = function() return CommanderGuideDB.Chat end,
        set = function(value) CommanderGuideDB.Chat = value end,
        isEnabled = Enabled,
    }, {
        label = "Open the guide on target",
        tooltip = "Targeting a boss out of combat opens the window on that boss's page. Off, the window only follows the boss when it is already open.",
        get = function() return CommanderGuideDB.AutoOpen end,
        set = function(value) CommanderGuideDB.AutoOpen = value end,
        isEnabled = Enabled,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Guide" then
        UI.ApplyDefaults(CommanderGuideDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end
frame:SetScript("OnEvent", OnEvent)

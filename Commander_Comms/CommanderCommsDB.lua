CommanderCommsDB = _G.CommanderCommsDB or {}

COMMANDER_COMMS_EVENTS = {
    UPDATE = "COMMANDER_COMMS_UPDATE"
}

local DefaultSettings = {
    EnableComms = true,
    IncludeTarget = true,
    CommsSound = true,
    UseEmotes = true,
    AutoEmote = false,
    AutoHealThreshold = 0.3,
    AutoOOMThreshold = 0.2,
    AutoEmoteCooldown = 30,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderCommsDB, DefaultSettings)
    Commander.Notify(COMMANDER_COMMS_EVENTS.UPDATE)
    print("Commander Comms: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Comms",
        title = "Comms",
        addonName = "Commander_Comms",
        description = "Battle comms on a radial wheel, like pinging in an RTS or MOBA. One keybind opens eight quick calls — on my way, need healing, attack, fall back — sent to raid, party, or say automatically depending on your group. Bind the wheel under Key Bindings > AddOns > Commander Comms.",
        event = COMMANDER_COMMS_EVENTS.UPDATE,
        slash = { "/ccomms" },
        slashHandlers = {
            toggle = function()
                if CommanderComms_Toggle then CommanderComms_Toggle() end
            end,
        },
    })

    panel:AddSection("Comms Wheel")
    panel:AddCheckbox({
        label = "Enable Comms",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderCommsDB.EnableComms end,
        set = function(value) CommanderCommsDB.EnableComms = value end,
    })
    panel:AddCheckboxPair({
        label = "Include Target Names",
        tooltip = "Calls like Attack and Focus name your current target when you have one.",
        get = function() return CommanderCommsDB.IncludeTarget end,
        set = function(value) CommanderCommsDB.IncludeTarget = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "Comms Sound",
        tooltip = "Play a click when the wheel opens and when a call is sent.",
        get = function() return CommanderCommsDB.CommsSound end,
        set = function(value) CommanderCommsDB.CommsSound = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddButtonRow({
        {
            label = "Open Wheel",
            width = 120,
            tooltip = "Preview the comms wheel (also: /ccomms toggle, or the keybind).",
            onClick = function()
                if CommanderComms_Toggle then CommanderComms_Toggle() end
            end,
        },
    })

    panel:AddSection("Voice", "The classic voiced emotes (/incoming, /healme, /oom...) — manually from the wheel, or automatically when the fight calls for them.")
    panel:AddCheckboxPair({
        label = "Use Voice Emotes",
        tooltip = "Wheel calls with a matching voiced emote (Incoming, Charge, Need Healing, Out of Mana, Fall Back, Help, Attack) play your character's voice line via the real emote.",
        get = function() return CommanderCommsDB.UseEmotes end,
        set = function(value) CommanderCommsDB.UseEmotes = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "Auto-Emote",
        tooltip = "Automatically call out /healme (low health, in a group) and /oom (low mana, mana users) during combat. Thresholds and spam protection below.",
        get = function() return CommanderCommsDB.AutoEmote end,
        set = function(value) CommanderCommsDB.AutoEmote = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddSlider({
        label = "Heal Me Below",
        tooltip = "Auto /healme when your health drops to this percentage in combat (re-arms only after you recover 15% above it).",
        min = 0.1, max = 0.6, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderCommsDB.AutoHealThreshold end,
        set = function(value) CommanderCommsDB.AutoHealThreshold = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoEmote end,
    })
    panel:AddSlider({
        label = "Out of Mana Below",
        tooltip = "Auto /oom when your mana drops to this percentage in combat (mana users only; same re-arm rule).",
        min = 0.05, max = 0.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderCommsDB.AutoOOMThreshold end,
        set = function(value) CommanderCommsDB.AutoOOMThreshold = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoEmote end,
    })
    panel:AddSlider({
        label = "Auto-Emote Cooldown",
        tooltip = "Minimum time between automatic emotes of the same kind — the spam guard.",
        min = 10, max = 120, step = 5,
        format = "%.0fs",
        get = function() return CommanderCommsDB.AutoEmoteCooldown end,
        set = function(value) CommanderCommsDB.AutoEmoteCooldown = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoEmote end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Comms" then
        Commander.UI.ApplyDefaults(CommanderCommsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

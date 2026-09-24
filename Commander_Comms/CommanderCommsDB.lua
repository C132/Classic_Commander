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
    InterruptSilence = true,
    KickedCallouts = true,
    AutoHealThreshold = 0.3,
    AutoOOMThreshold = 0.2,
    AutoEmoteCooldown = 30,
    AutoCharge = false,
    AutoChargeThreshold = 8,
    DispelCallouts = true,
    CCBreakCallouts = true,
    CCBreakAll = false,
    ManaBurnCallouts = true,
    ManaBurnMinPercent = 0.05,
    ManaBurnCooldown = 8,
    BattlegroundCallouts = false,
    BattlegroundToParty = false,
    RangeWhisper = false,
    SightWhisper = false,
    RangeWhisperStreak = 4,
    RangeWhisperCooldown = 45,
    PowerCallouts = false,
    ControlCallouts = false,
    SupportWhisper = true,
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
        description = "Battle comms on a radial wheel, like pinging in an RTS or MOBA. One keybind opens ten quick calls — on my way, need healing, attack, fall back — voiced calls play your character's real voice line, the rest go to raid, party, or say depending on your group. Hover a call to preview exactly what it sends. Bind the wheel under Key Bindings > AddOns > Commander Comms.",
        event = COMMANDER_COMMS_EVENTS.UPDATE,
        slash = { "/ccomms" },
        slashHandlers = {
            toggle = function()
                if CommanderComms_Toggle then CommanderComms_Toggle() end
            end,
        },
    })

    panel:AddSection("Comms Wheel")
    panel:AddCheckboxPair({
        label = "Enable Comms",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderCommsDB.EnableComms end,
        set = function(value) CommanderCommsDB.EnableComms = value end,
    }, {
        label = "Interrupt Callouts",
        tooltip = "Announce your successful interrupts to the group automatically: who you kicked, which spell you stopped, and with what ability — both spells as clickable links (\"Interrupted Pillager's [Frostbolt] with [Pummel].\"). Channels count: a kicked Drain Life, Mind Flay or Evocation is called out the same way, even though the combat log never reports one. Group chat only; never fires solo.",
        get = function() return CommanderCommsDB.InterruptSilence end,
        set = function(value) CommanderCommsDB.InterruptSilence = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddCheckboxPair({
        label = "Kicked On Me",
        tooltip = "Announce it to the group when an interrupt lands on YOU: which of your spells died, which school went down and for how long, who did it (with their class when it can be read off a unit frame or nameplate), and what they used (\"Interrupted on [Frostbolt] by Levira (Mage) with [Counterspell] — Frost locked 8s.\"). The lockout is the part that matters to the team: it says how long you are off that school. Channels count here too. Group chat only; never fires solo.",
        get = function() return CommanderCommsDB.KickedCallouts end,
        set = function(value) CommanderCommsDB.KickedCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
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
        tooltip = "Wheel calls with a matching voiced emote (marked with a speaker on the wheel) play your character's voice line via the real emote INSTEAD of a chat message — the voice and its emote text are the announcement. Off, every call goes to chat.",
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
    panel:AddSliderPair({
        label = "Heal Me Below",
        tooltip = "Auto /healme when your health drops to this percentage in combat (re-arms only after you recover 15% above it).",
        min = 0.1, max = 0.6, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderCommsDB.AutoHealThreshold end,
        set = function(value) CommanderCommsDB.AutoHealThreshold = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoEmote end,
    }, {
        label = "Out of Mana Below",
        tooltip = "Auto /oom when your mana drops to this percentage in combat (mana users only; same re-arm rule).",
        min = 0.05, max = 0.5, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderCommsDB.AutoOOMThreshold end,
        set = function(value) CommanderCommsDB.AutoOOMThreshold = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoEmote end,
    })
    panel:AddSliderPair({
        label = "Auto-Emote Cooldown",
        tooltip = "Minimum time between automatic emotes of the same kind — the spam guard.",
        min = 10, max = 120, step = 5,
        format = "%.0fs",
        get = function() return CommanderCommsDB.AutoEmoteCooldown end,
        set = function(value) CommanderCommsDB.AutoEmoteCooldown = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoEmote end,
    }, {
        label = "Charge Rally Under",
        tooltip = "When your Commander Momentum streak clock drops below this many seconds, the Charge com fires automatically to rally the pace. Once per stall, 20s cooldown.",
        min = 3, max = 15, step = 1,
        format = "%.0fs",
        get = function() return CommanderCommsDB.AutoChargeThreshold end,
        set = function(value) CommanderCommsDB.AutoChargeThreshold = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.AutoCharge end,
    })
    panel:AddCheckboxPair({
        label = "Auto Charge Rally",
        tooltip = "Automatically issue the Charge com when a live Momentum kill streak is about to run out of clock — keep the group motivated and the chain alive. Requires Commander Momentum.",
        get = function() return CommanderCommsDB.AutoCharge end,
        set = function(value) CommanderCommsDB.AutoCharge = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "Cleanse Callouts",
        tooltip = "Announce your dispels to the group automatically: who you cleansed and what came off, both spells as clickable links (\"Removed [Curse of Tongues] from Healbot ([Remove Curse]).\"). Debuff removals only — offensive purges stay quiet. Group chat only; never fires solo.",
        get = function() return CommanderCommsDB.DispelCallouts end,
        set = function(value) CommanderCommsDB.DispelCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })

    panel:AddSection("Crowd Control", "The \"who broke my sheep?\" alarm. Polymorphs, blinds, traps, saps, fears and friends are watched in the combat log, and an early break is announced with the breaker named — including which group member's pet did it.")
    panel:AddCheckboxPair({
        label = "CC Break Callouts",
        tooltip = "Announce when your group's crowd control is broken early — your own and your teammates' (\"Levira broke my [Polymorph] on Pillager ([Cleave]).\", \"Levira broke Shivs's [Blind] on Pillager ([Cleave]).\"): who broke it, on which target, and with what, both spells as clickable links. Melee breaks say (melee); a pet's CC counts as its owner's. Group chat only; never fires solo.",
        get = function() return CommanderCommsDB.CCBreakCallouts end,
        set = function(value) CommanderCommsDB.CCBreakCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "All CC Breaks",
        tooltip = "Widen the watch from your group's CC to any crowd control broken near you (combat-log range) — a stranger's sheep in world PvP, an unpartied dungeon helper's trap — with the owner named when known (\"Levira broke Moonkin's [Polymorph] on Pillager ([Cleave]).\"). Off, only your own and your group's CC is announced.",
        get = function() return CommanderCommsDB.CCBreakAll end,
        set = function(value) CommanderCommsDB.CCBreakAll = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.CCBreakCallouts end,
    })

    panel:AddSection("Mana Burn", "The arena's quietest kill: nobody dies, the healer just runs dry. A priest's Mana Burn takes a tenth of a mana bar per cast and says nothing in your chat while it does it, so every drain that lands on a group member's mana — Mana Burn, a mob's version of it, a Drain Mana or Viper Sting that has added up — is announced with how much came off and how much is left.")
    panel:AddCheckboxPair({
        label = "Mana Burn Callouts",
        tooltip = "Announce it to the group when a group member (you included) has mana drained off them: who, how much, by whom and with what, and the number that decides the game — how much they have left (\"Healbot mana burned for 1,050 by Levira (Priest) with [Mana Burn] — 43% mana left.\"). Small ticks are added up and reported once they amount to something, so a Viper Sting is one line, not four. Group chat only; never fires solo, and it follows the battleground rule below.",
        get = function() return CommanderCommsDB.ManaBurnCallouts end,
        set = function(value) CommanderCommsDB.ManaBurnCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddSliderPair({
        label = "Ignore Burns Under",
        tooltip = "Drains smaller than this share of the victim's mana bar are not worth a line on their own; they are added up, and the sum is announced once it clears the bar. Five percent lets a real Mana Burn through on the first cast and holds a single Viper Sting tick back.",
        min = 0.01, max = 0.25, step = 0.01,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderCommsDB.ManaBurnMinPercent end,
        set = function(value) CommanderCommsDB.ManaBurnMinPercent = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.ManaBurnCallouts end,
    }, {
        label = "One Line Per",
        tooltip = "Minimum time between callouts about the SAME victim. A priest chaining burns every three seconds is reported as one line per this interval carrying the total of everything burned since the last one, so the channel hears the trend without hearing every cast.",
        min = 4, max = 30, step = 1,
        format = "%.0fs",
        get = function() return CommanderCommsDB.ManaBurnCooldown end,
        set = function(value) CommanderCommsDB.ManaBurnCooldown = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms and CommanderCommsDB.ManaBurnCallouts end,
    })

    panel:AddSection("Failed Casts", "The red text at the top of your screen, said out loud to whoever can act on it. Who that is depends on whose problem it is: out of range and out of sight are the ALLY's, so those whisper the one person who can move, and only after a run of them. Out of mana and crowd controlled are YOURS, so those go to the group like every other callout here.")
    panel:AddCheckboxPair({
        label = "Whisper Out-of-Range",
        tooltip = "Whisper an ally when a run of your heals fails on them for range — four presses in a row by default, with no heal landing on them in between (\"Out of healing range — 4 casts didn't reach you (last: [Flash Heal]). Move closer!\"). Only heals you actually know count, only group members are whispered, and the ally has to be one the client itself reports as out of range. Unlike the group callouts this one speaks in a battleground too: a whisper costs the channel nothing, and a flag carrier drifting out of your range is exactly the case worth a private line.",
        get = function() return CommanderCommsDB.RangeWhisper end,
        set = function(value) CommanderCommsDB.RangeWhisper = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "Whisper Line of Sight",
        tooltip = "The same run, for the other thing an ally does to your heals: standing where you cannot see them (\"No line of sight — 4 casts blocked (last: [Flash Heal]). I can't see you!\"). The pillar that breaks the enemy's casts breaks yours too, and the person behind it is usually the last to notice. Nothing in the game can be asked whether you can see a unit, so this one rests on the client's own error and on the target being someone in your group.",
        get = function() return CommanderCommsDB.SightWhisper end,
        set = function(value) CommanderCommsDB.SightWhisper = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })
    panel:AddSliderPair({
        label = "Failures Before Whisper",
        tooltip = "How many casts in a row have to fail on the same ally, for the same reason, before they hear about it. One miss while somebody rounds a pillar is normal and two is a bad angle; the default of four is a person who has not noticed. The run resets the moment a heal of yours lands on them, or after twenty quiet seconds.",
        min = 2, max = 10, step = 1,
        format = "%.0f",
        get = function() return CommanderCommsDB.RangeWhisperStreak end,
        set = function(value) CommanderCommsDB.RangeWhisperStreak = value end,
        isEnabled = function()
            return CommanderCommsDB.EnableComms
                and (CommanderCommsDB.RangeWhisper or CommanderCommsDB.SightWhisper)
        end,
    }, {
        label = "Whisper Cooldown",
        tooltip = "Minimum time between whispers to the SAME ally — the anti-nag guard. Someone who stays out of range for a whole fight is told once, not once per four presses.",
        min = 15, max = 180, step = 5,
        format = "%.0fs",
        get = function() return CommanderCommsDB.RangeWhisperCooldown end,
        set = function(value) CommanderCommsDB.RangeWhisperCooldown = value end,
        isEnabled = function()
            return CommanderCommsDB.EnableComms
                and (CommanderCommsDB.RangeWhisper or CommanderCommsDB.SightWhisper)
        end,
    })
    panel:AddCheckboxPair({
        label = "Call Out of Mana",
        tooltip = "A cast refused for mana is the ground truth the percentage trigger above is only guessing at, so it makes the same /oom call — your character's voice line with Use Voice Emotes on, the chat line without it. It shares the auto-emote's cooldown and its re-arm, so an empty bar is announced once however it was noticed, and only mana users ever fire it: a rogue is out of energy every few seconds and a warrior lives there.",
        get = function() return CommanderCommsDB.PowerCallouts end,
        set = function(value) CommanderCommsDB.PowerCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "Call Crowd Controlled",
        tooltip = "Tell the group when a cast is refused because you are stunned, feared, confused or charmed — named, because \"peel me\" and \"dispel me\" are different requests (\"Can't cast — I'm feared. Peel!\"). Silence is deliberately not here: the Kicked On Me callout already reports it with the school and how long you are locked out, which is more than this could say. Group chat only, 15s between calls, and it follows the battleground rule below.",
        get = function() return CommanderCommsDB.ControlCallouts end,
        set = function(value) CommanderCommsDB.ControlCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })

    panel:AddSection("Support Calls", "The other direction: not what went wrong, but something you did FOR one person that only works if they notice. Power Infusion is twenty seconds of haste wasted on a mage who is drinking; Innervate is mana handed to someone who stopped casting because they had none. Spells like these are spent on one named ally and are useless unless that ally acts, which is why this is the one whisper that ships switched on.")
    panel:AddCheckboxPair({
        label = "Whisper Support Cooldowns",
        tooltip = "Whisper an ally the moment you spend a support cooldown on them, saying what they have to DO rather than just naming the spell (\"[Power Infusion] on you — burn it now!\", \"[Blessing of Protection] on you — physical immune, stop attacking.\"). The spell goes out as a link so they can hover it. Watched: Power Infusion, Pain Suppression, Fear Ward, Innervate, Intervene, Blessing of Protection / Freedom / Sacrifice, Divine Intervention, Lay on Hands, Misdirection and Soulstone Resurrection — drawn from your OWN spellbook, so a priest never carries the paladin lines. Group members only, never yourself, and the same spell on the same ally is one whisper per 20 seconds. Like the other whispers it speaks in a battleground too.",
        get = function() return CommanderCommsDB.SupportWhisper end,
        set = function(value) CommanderCommsDB.SupportWhisper = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    })

    panel:AddSection("Battlegrounds", "Forty people and one chat window: the automatic GROUP callouts — interrupt, kicked-on-me, cleanse, CC break and mana burn — stay quiet inside a battleground, where nobody is coordinating off your kicks anyway. The whispers above are not among them: they speak to one person, so they speak everywhere. Arenas, dungeons and world groups are untouched.")
    panel:AddCheckboxPair({
        label = "Callouts in Battlegrounds",
        tooltip = "Off (the default), the automatic callouts — interrupt, kicked-on-me, cleanse, CC break and mana burn — say nothing at all while you are in a battleground. On, they announce there like anywhere else. The comms wheel and its voice emotes are a keypress you asked for, so they are never affected.",
        get = function() return CommanderCommsDB.BattlegroundCallouts end,
        set = function(value) CommanderCommsDB.BattlegroundCallouts = value end,
        isEnabled = function() return CommanderCommsDB.EnableComms end,
    }, {
        label = "To Party Only",
        tooltip = "Send those battleground callouts to the party you queued with instead of the whole battleground chat — the four people who can actually act on your kick. Queued in alone there is no party to tell, so the callouts stay quiet.",
        get = function() return CommanderCommsDB.BattlegroundToParty end,
        set = function(value) CommanderCommsDB.BattlegroundToParty = value end,
        isEnabled = function()
            return CommanderCommsDB.EnableComms and CommanderCommsDB.BattlegroundCallouts
        end,
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

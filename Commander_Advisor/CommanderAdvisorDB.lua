CommanderAdvisorDB = _G.CommanderAdvisorDB or {}

COMMANDER_ADVISOR_EVENTS = {
    UPDATE = "COMMANDER_ADVISOR_UPDATE",
}

local D = CommanderAdvisor_Data

-- Tier colours the settings page offers. "CLASS" is resolved at paint time.
local COLOR_OPTIONS = {
    { text = "Red",     value = "RED",    rgb = { 1.00, 0.20, 0.20 } },
    { text = "Orange",  value = "ORANGE", rgb = { 1.00, 0.50, 0.10 } },
    { text = "Gold",    value = "GOLD",   rgb = { 1.00, 0.78, 0.20 } },
    { text = "Yellow",  value = "YELLOW", rgb = { 1.00, 1.00, 0.30 } },
    { text = "Green",   value = "GREEN",  rgb = { 0.30, 1.00, 0.40 } },
    { text = "Cyan",    value = "CYAN",   rgb = { 0.30, 0.95, 1.00 } },
    { text = "Blue",    value = "BLUE",   rgb = { 0.45, 0.65, 1.00 } },
    { text = "Violet",  value = "VIOLET", rgb = { 0.75, 0.45, 1.00 } },
    { text = "White",   value = "WHITE",  rgb = { 1.00, 1.00, 1.00 } },
    { text = "Class colour", value = "CLASS" },
}

local SOUND_OPTIONS = {
    { text = "Silent",        value = "NONE" },
    { text = "Raid Warning",  value = "RAID_WARNING",   kit = "RAID_WARNING", id = 8959 },
    { text = "Ready Check",   value = "READY_CHECK",    kit = "READY_CHECK", id = 8960 },
    { text = "Boss Emote",    value = "BOSS_EMOTE",     kit = "RAID_BOSS_EMOTE_WARNING", id = 37666 },
    { text = "Quest Chime",   value = "QUEST",          kit = "IG_QUEST_LIST_COMPLETE", id = 883 },
    { text = "Map Ping",      value = "PING",           file = "Sound\\Interface\\MapPing.wav" },
    { text = "Bell — High",   value = "TOLL_HI",        file = "Sound\\Doodad\\BellTollAlliance.wav" },
    { text = "Bell — Low",    value = "TOLL_LO",        file = "Sound\\Doodad\\BellTollHorde.wav" },
    { text = "Docking Bell",  value = "DOCK",           file = "Sound\\Doodad\\BoatDockedWarning.wav" },
}

local PULSE_OPTIONS = {
    { text = "Steady", value = "NONE" },
    { text = "Slow", value = "SLOW" },
    { text = "Medium", value = "MEDIUM" },
    { text = "Fast", value = "FAST" },
}

local CAUTION_OPTIONS = {
    { text = "Eager", value = "EAGER" },
    { text = "Balanced", value = "BALANCED" },
    { text = "Conservative", value = "CONSERVATIVE" },
    { text = "Very conservative", value = "VERY" },
}

local MODE_OPTIONS = {
    { text = "As written", value = "AUTO" },
    { text = "Off", value = "OFF" },
    { text = "Always low", value = "LOW" },
    { text = "Always medium", value = "MEDIUM" },
    { text = "Always high", value = "HIGH" },
}

local DefaultSettings = {
    EnableAdvisor = true,

    -- Judgement
    Caution = "CONSERVATIVE",     -- EAGER | BALANCED | CONSERVATIVE | VERY
    MaxSignals = 3,
    HoldSeconds = 1.0,
    RiseLow = 1.0,
    RiseMedium = 0.4,
    CastGrace = 2.0,
    TTLCeiling = 75,              -- percent; a time-to-die rung is ignored above this

    -- Missing buffs
    RemindOutOfCombat = true,
    RemindInCombat = true,
    QuietWhileResting = false,
    QuietInStealth = true,
    RemindWhileMounted = false,
    MissingGrace = 3,             -- seconds a buff must be missing before it is mentioned
    ExpiringSoon = 20,            -- seconds left that counts as "about to expire"

    -- Tiers
    Tier3Enabled = true, Tier3Color = "RED",   Tier3Intensity = 100, Tier3Pulse = "FAST",   Tier3Sound = "RAID_WARNING",
    Tier2Enabled = true, Tier2Color = "GOLD",  Tier2Intensity = 85,  Tier2Pulse = "MEDIUM", Tier2Sound = "NONE",
    Tier1Enabled = true, Tier1Color = "BLUE",  Tier1Intensity = 60,  Tier1Pulse = "SLOW",   Tier1Sound = "NONE",
    SoundOnlyInCombat = false,
    SoundCooldown = 4,            -- seconds between two sounds of the same tier

    -- Appearance
    GlowStyle = "PROC",           -- PROC | BORDER
    GlowScale = 100,              -- percent of the button
    StartBurst = true,            -- the proc "birth" flash on a new high signal
    ShowPips = true,
    PipSize = 5,
    ShowTooltip = true,

    -- Disc priest: what the Shield and Mending buttons say about the unit
    -- they would land on (see the overlay block in CommanderAdvisor.lua)
    ShieldWatch = true,           -- Weakened Soul as a clock across the Shield button
    TeamPips = true,              -- one pip per teammate along its bottom edge
    MendingWatch = true,          -- where your Mending is, its charges, its bounce range
    WatchNames = true,            -- the name of who the button is about, across its top

    -- Per-rule modes, keyed by rule key. Missing = the rule's shipped default.
    RuleModes = {},
}

CommanderAdvisor = _G.CommanderAdvisor or {}
CommanderAdvisor.Defaults = DefaultSettings
CommanderAdvisor.COLOR_OPTIONS = COLOR_OPTIONS
CommanderAdvisor.SOUND_OPTIONS = SOUND_OPTIONS

function CommanderAdvisor.ColorFor(key)
    for _, option in ipairs(COLOR_OPTIONS) do
        if option.value == key then
            if option.rgb then return option.rgb end
            local info = Commander.GetClassInfo and Commander.GetClassInfo()
            return info and info.color or { 1, 1, 1 }
        end
    end
    return { 1, 1, 1 }
end

function CommanderAdvisor.SoundFor(key)
    for _, option in ipairs(SOUND_OPTIONS) do
        if option.value == key then return option end
    end
    return nil
end

function CommanderAdvisor.PlaySoundOption(option)
    if not option or option.value == "NONE" then return end
    if option.kit or option.id then
        local id = (SOUNDKIT and option.kit and SOUNDKIT[option.kit]) or option.id
        if id and PlaySound then
            local ok, played = pcall(PlaySound, id, "Master")
            if ok and played ~= false then return end
        end
    end
    if option.file and PlaySoundFile then
        pcall(PlaySoundFile, option.file, "Master")
    end
end

-- The reticence the engine scales thresholds by, from the Caution setting
function CommanderAdvisor.Reticence()
    local c = CommanderAdvisorDB.Caution
    if c == "EAGER" then return -0.25 end
    if c == "BALANCED" then return 0 end
    if c == "VERY" then return 0.4 end
    return 0.2
end

-- The rule mode as saved, falling back to the rule's shipped default
function CommanderAdvisor.RuleMode(rule)
    local saved = CommanderAdvisorDB.RuleModes and CommanderAdvisorDB.RuleModes[rule.key]
    if saved then return saved end
    return rule.default or "AUTO"
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderAdvisorDB, DefaultSettings)
    CommanderAdvisorDB.RuleModes = {}
    Commander.Notify(COMMANDER_ADVISOR_EVENTS.UPDATE)
    print("Commander Advisor: settings restored to defaults")
end

local function IsOn() return CommanderAdvisorDB.EnableAdvisor end

local function AddTierSection(panel, tier, title, blurb)
    local prefix = "Tier" .. tier
    panel:AddSection(title, blurb)
    panel:AddCheckboxPair({
        label = "Enable " .. D.TIER_NAMES[tier] .. " Signals",
        tooltip = "Off hides every signal at this tier. Rules that would have reached it stay silent rather than dropping to a lower tier.",
        get = function() return CommanderAdvisorDB[prefix .. "Enabled"] end,
        set = function(value) CommanderAdvisorDB[prefix .. "Enabled"] = value end,
        isEnabled = IsOn,
    })
    panel:AddDropdownPair({
        label = "Colour",
        tooltip = "The glow's tint at this tier.",
        options = COLOR_OPTIONS,
        get = function() return CommanderAdvisorDB[prefix .. "Color"] end,
        set = function(value) CommanderAdvisorDB[prefix .. "Color"] = value end,
        isEnabled = function() return IsOn() and CommanderAdvisorDB[prefix .. "Enabled"] end,
    }, {
        label = "Pulse",
        tooltip = "How the glow breathes. Steady never changes brightness.",
        options = PULSE_OPTIONS,
        get = function() return CommanderAdvisorDB[prefix .. "Pulse"] end,
        set = function(value) CommanderAdvisorDB[prefix .. "Pulse"] = value end,
        isEnabled = function() return IsOn() and CommanderAdvisorDB[prefix .. "Enabled"] end,
    })
    panel:AddSliderPair({
        label = "Intensity",
        tooltip = "Peak brightness of the glow at this tier.",
        min = 20, max = 100, step = 5,
        format = "%.0f%%",
        get = function() return CommanderAdvisorDB[prefix .. "Intensity"] end,
        set = function(value) CommanderAdvisorDB[prefix .. "Intensity"] = value end,
        isEnabled = function() return IsOn() and CommanderAdvisorDB[prefix .. "Enabled"] end,
    }, nil)
    panel:AddDropdown({
        label = "Sound On New Signal",
        tooltip = "Played once when a signal first reaches this tier. Two signals of the same tier inside the sound cooldown share one sound.",
        options = SOUND_OPTIONS,
        get = function() return CommanderAdvisorDB[prefix .. "Sound"] end,
        set = function(value) CommanderAdvisorDB[prefix .. "Sound"] = value end,
        onSelect = function(value) CommanderAdvisor.PlaySoundOption(CommanderAdvisor.SoundFor(value)) end,
        isEnabled = function() return IsOn() and CommanderAdvisorDB[prefix .. "Enabled"] end,
    })
end

local ROLE_TITLES = {
    maintain = "Buffs to keep up",
    react = "Defensive buttons",
    escape = "Ways out",
    cure = "Things to remove",
}
local ROLE_ORDER = { "maintain", "react", "escape", "cure" }

local function AddRuleSections(panel)
    local _, classToken = UnitClass("player")
    local rules = D.RulesForClass(classToken or "")
    local info = Commander.GetClassInfo and Commander.GetClassInfo() or nil
    local title = info and info.title or "your class"

    panel:AddSection("Rules for the " .. title,
        "Every signal this character can be given, grouped by what it is for. As written lets the rule climb its own ladder of tiers; Always pins whatever it raises to one tier; Off silences it. A rule for a spell you have not trained never fires, whatever it is set to.")

    for _, role in ipairs(ROLE_ORDER) do
        local group = {}
        for _, rule in ipairs(rules) do
            if (rule.role or "react") == role then group[#group + 1] = rule end
        end
        if #group > 0 then
            panel:AddSection(ROLE_TITLES[role])
            local i = 1
            while i <= #group do
                local left, right = group[i], group[i + 1]
                local function Spec(rule)
                    local label = rule.item and (rule.key == "ALL_HEALTH_ITEM" and "Potion / Healthstone"
                        or rule.key == "ALL_PVP_TRINKET" and "PvP Trinket" or "Bandage")
                        or (type(rule.spell) == "table" and rule.spell[1] or rule.spell)
                    return {
                        label = label,
                        tooltip = rule.desc .. (rule.default == "OFF" and "  (Ships off.)" or ""),
                        options = MODE_OPTIONS,
                        get = function() return CommanderAdvisor.RuleMode(rule) end,
                        set = function(value)
                            CommanderAdvisorDB.RuleModes = CommanderAdvisorDB.RuleModes or {}
                            if value == (rule.default or "AUTO") then
                                CommanderAdvisorDB.RuleModes[rule.key] = nil
                            else
                                CommanderAdvisorDB.RuleModes[rule.key] = value
                            end
                        end,
                        isEnabled = IsOn,
                    }
                end
                panel:AddDropdownPair(Spec(left), right and Spec(right) or nil)
                i = i + 2
            end
        end
    end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Advisor",
        title = "Advisor",
        addonName = "Commander_Advisor",
        description = "Glows the button you should be pressing. A rules engine — not a language model — that watches your health, what is hitting you and how fast, who is on you, what is being cast at you, what is on you and what is not, and your cooldowns, and lights the action button for the defensive answer at one of three tiers: a low note, a medium prompt, a high alarm. Missing self-buffs (Inner Fire, an armour, a shield, a blessing, an aspect) are on the same ladder. It is deliberately conservative: a time-to-die is only ever claimed while something is actually hitting you and only from a rate measured over the whole recent window, a single crit is not a burst, a signal has to hold for a moment before it shows and casting the spell clears it at once. Hover any glowing button for the reason; /cadv report prints every rule and why it is or is not speaking.",
        event = COMMANDER_ADVISOR_EVENTS.UPDATE,
        slash = { "/cadvisor", "/cadv" },
        slashHandlers = {
            report = function() if CommanderAdvisor_Report then CommanderAdvisor_Report() end end,
            why = function() if CommanderAdvisor_Report then CommanderAdvisor_Report() end end,
            test = function() if CommanderAdvisor_Test then CommanderAdvisor_Test() end end,
            range = function() if CommanderAdvisor_RangeReport then CommanderAdvisor_RangeReport() end end,
        },
    })

    -- What it sees right now: refreshed on show and on every change, and
    -- once a second while the page is open so it reads as live
    do
        local row = panel:AddRow(64, 10)
        local situation = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        situation:SetPoint("TOPLEFT", row, "TOPLEFT", 2, 0)
        situation:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        situation:SetJustifyH("LEFT")
        local signals = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        signals:SetPoint("TOPLEFT", situation, "BOTTOMLEFT", 0, -4)
        signals:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        signals:SetJustifyH("LEFT")
        local function Paint()
            if not CommanderAdvisor.Status then return end
            local a, b = CommanderAdvisor.Status()
            situation:SetText("|cffffd100Right now:|r " .. a)
            signals:SetText(b)
            if signals.GetStringHeight then
                local h = (situation:GetStringHeight() or 12) + 4 + (signals:GetStringHeight() or 12)
                panel:GrowRow(row, math.ceil(h) + 8)
            end
        end
        panel:AddRefresher(Paint)
        C_Timer.NewTicker(1, function()
            if panel:IsVisible() then Paint() end
        end)
    end

    panel:AddSection("Advisor")
    panel:AddCheckboxPair({
        label = "Enable Advisor",
        tooltip = "Master switch. Off clears every glow and stops watching.",
        get = function() return CommanderAdvisorDB.EnableAdvisor end,
        set = function(value) CommanderAdvisorDB.EnableAdvisor = value end,
    }, {
        label = "Reason On Tooltip",
        tooltip = "Add the signal's tier and reason to a glowing button's tooltip.",
        get = function() return CommanderAdvisorDB.ShowTooltip end,
        set = function(value) CommanderAdvisorDB.ShowTooltip = value end,
        isEnabled = IsOn,
    })
    panel:AddDropdownPair({
        label = "Caution",
        tooltip = "How sure the advisor has to be. Eager raises every threshold by a quarter; Conservative lowers them by a fifth; Very conservative by two fifths — so a rung written for 35% health fires at 44%, 35%, 28% or 21%.",
        options = CAUTION_OPTIONS,
        get = function() return CommanderAdvisorDB.Caution end,
        set = function(value) CommanderAdvisorDB.Caution = value end,
        isEnabled = IsOn,
    }, nil)
    panel:AddSliderPair({
        label = "Glows At Once",
        tooltip = "At most this many buttons glow at the same time — the highest tier first, then the rule the book ranks higher. Everything else waits its turn.",
        min = 1, max = 8, step = 1,
        format = "%.0f",
        get = function() return CommanderAdvisorDB.MaxSignals end,
        set = function(value) CommanderAdvisorDB.MaxSignals = value end,
        isEnabled = IsOn,
    }, {
        label = "Hold",
        tooltip = "How long a glow lingers after the reason for it has passed, so a health bar hovering around a threshold does not flicker the button.",
        min = 0, max = 4, step = 0.25,
        format = "%.2fs",
        get = function() return CommanderAdvisorDB.HoldSeconds end,
        set = function(value) CommanderAdvisorDB.HoldSeconds = value end,
        isEnabled = IsOn,
    })
    panel:AddSliderPair({
        label = "Low Must Hold For",
        tooltip = "A low signal has to stay true this long before it shows. High signals always show at once.",
        min = 0, max = 5, step = 0.25,
        format = "%.2fs",
        get = function() return CommanderAdvisorDB.RiseLow end,
        set = function(value) CommanderAdvisorDB.RiseLow = value end,
        isEnabled = IsOn,
    }, {
        label = "Medium Must Hold For",
        tooltip = "A medium signal has to stay true this long before it shows.",
        min = 0, max = 3, step = 0.1,
        format = "%.1fs",
        get = function() return CommanderAdvisorDB.RiseMedium end,
        set = function(value) CommanderAdvisorDB.RiseMedium = value end,
        isEnabled = IsOn,
    })
    panel:AddSliderPair({
        label = "Quiet After Casting",
        tooltip = "After you cast a spell, its signal stays down this long — long enough for the aura or the heal to land before the advisor looks again.",
        min = 0.5, max = 6, step = 0.5,
        format = "%.1fs",
        get = function() return CommanderAdvisorDB.CastGrace end,
        set = function(value) CommanderAdvisorDB.CastGrace = value end,
        isEnabled = IsOn,
    }, {
        label = "Time-To-Die Ceiling",
        tooltip = "A 'dying within N seconds' rung is ignored while your health is above this. A fast rate on a full bar is a number, not an emergency yet.",
        min = 40, max = 100, step = 5,
        format = "%.0f%%",
        get = function() return CommanderAdvisorDB.TTLCeiling end,
        set = function(value) CommanderAdvisorDB.TTLCeiling = value end,
        isEnabled = IsOn,
    })

    panel:AddSection("Missing buffs",
        "Self-buffs on the ladder: out of combat a missing one is a low note; in combat, with something hitting you, the same buff is a medium prompt.")
    panel:AddCheckboxPair({
        label = "Remind Out Of Combat",
        get = function() return CommanderAdvisorDB.RemindOutOfCombat end,
        set = function(value) CommanderAdvisorDB.RemindOutOfCombat = value end,
        isEnabled = IsOn,
    }, {
        label = "Remind In Combat",
        get = function() return CommanderAdvisorDB.RemindInCombat end,
        set = function(value) CommanderAdvisorDB.RemindInCombat = value end,
        isEnabled = IsOn,
    })
    panel:AddCheckboxPair({
        label = "Quiet While Resting",
        tooltip = "Say nothing about buffs in an inn or a city. Defensive signals still fire if something hits you there.",
        get = function() return CommanderAdvisorDB.QuietWhileResting end,
        set = function(value) CommanderAdvisorDB.QuietWhileResting = value end,
        isEnabled = IsOn,
    }, {
        label = "Quiet In Stealth",
        tooltip = "Say nothing about buffs while stealthed or prowling.",
        get = function() return CommanderAdvisorDB.QuietInStealth end,
        set = function(value) CommanderAdvisorDB.QuietInStealth = value end,
        isEnabled = IsOn,
    })
    panel:AddCheckboxPair({
        label = "Remind While Mounted",
        tooltip = "Buff reminders while riding. Off by default — you will dismount before it matters.",
        get = function() return CommanderAdvisorDB.RemindWhileMounted end,
        set = function(value) CommanderAdvisorDB.RemindWhileMounted = value end,
        isEnabled = IsOn,
    }, nil)
    panel:AddSliderPair({
        label = "Missing For At Least",
        tooltip = "A buff has to have been missing this long before it is mentioned, so the seconds between a buff dropping and you recasting it are not a glow.",
        min = 0, max = 15, step = 1,
        format = "%.0fs",
        get = function() return CommanderAdvisorDB.MissingGrace end,
        set = function(value) CommanderAdvisorDB.MissingGrace = value end,
        isEnabled = IsOn,
    }, {
        label = "Expiring Soon",
        tooltip = "A buff with less than this left is a low note even though it is still up. Zero never mentions an expiring buff.",
        min = 0, max = 120, step = 5,
        format = "%.0fs",
        get = function() return CommanderAdvisorDB.ExpiringSoon end,
        set = function(value) CommanderAdvisorDB.ExpiringSoon = value end,
        isEnabled = IsOn,
    })

    AddTierSection(panel, 3, "High — the alarm",
        "You are about to die, a fear is being cast at you, or you are held with a trinket ready. Meant to be impossible to miss.")
    AddTierSection(panel, 2, "Medium — the prompt",
        "You are being hit and losing, melee are on you, a cast is aimed at you, a magic debuff is on you.")
    AddTierSection(panel, 1, "Low — the note",
        "A buff is missing out of combat, a heal-over-time would not hurt, a caster is working on you.")
    panel:AddCheckboxPair({
        label = "Sounds Only In Combat",
        get = function() return CommanderAdvisorDB.SoundOnlyInCombat end,
        set = function(value) CommanderAdvisorDB.SoundOnlyInCombat = value end,
        isEnabled = IsOn,
    }, nil)
    panel:AddSliderPair({
        label = "Sound Cooldown",
        tooltip = "Two signals of the same tier arriving inside this window make one sound, not two.",
        min = 0, max = 15, step = 1,
        format = "%.0fs",
        get = function() return CommanderAdvisorDB.SoundCooldown end,
        set = function(value) CommanderAdvisorDB.SoundCooldown = value end,
        isEnabled = IsOn,
    }, nil)

    panel:AddSection("Appearance")
    panel:AddDropdownPair({
        label = "Glow Style",
        tooltip = "Proc uses the client's own animated spell-alert art, tinted per tier. Border is a plain glowing rim for a quieter bar.",
        options = {
            { text = "Proc (animated)", value = "PROC" },
            { text = "Border", value = "BORDER" },
        },
        get = function() return CommanderAdvisorDB.GlowStyle end,
        set = function(value) CommanderAdvisorDB.GlowStyle = value end,
        isEnabled = IsOn,
    }, nil)
    panel:AddSliderPair({
        label = "Glow Size",
        min = 70, max = 160, step = 5,
        format = "%.0f%%",
        get = function() return CommanderAdvisorDB.GlowScale end,
        set = function(value) CommanderAdvisorDB.GlowScale = value end,
        isEnabled = IsOn,
    }, {
        label = "Tier Pip Size",
        tooltip = "The small dots in the button's corner that count the tier — one, two or three — for when colour alone is not enough.",
        min = 3, max = 10, step = 1,
        format = "%.0f px",
        get = function() return CommanderAdvisorDB.PipSize end,
        set = function(value) CommanderAdvisorDB.PipSize = value end,
        isEnabled = function() return IsOn() and CommanderAdvisorDB.ShowPips end,
    })
    panel:AddCheckboxPair({
        label = "Show Tier Pips",
        get = function() return CommanderAdvisorDB.ShowPips end,
        set = function(value) CommanderAdvisorDB.ShowPips = value end,
        isEnabled = IsOn,
    }, {
        label = "Flash On New High Signal",
        tooltip = "Play the client's proc 'birth' burst the moment a high signal appears.",
        get = function() return CommanderAdvisorDB.StartBurst end,
        set = function(value) CommanderAdvisorDB.StartBurst = value end,
        isEnabled = IsOn,
    })

    -- The priest's two buttons that are always about somebody else
    local _, classToken = UnitClass("player")
    if classToken == "PRIEST" then
        panel:AddSection("Shield & Mending",
            "What your Power Word: Shield and Prayer of Mending buttons say about whoever they would land on right now — a macro's @mouseover or @focus when it picks one, else your friendly target, else you. The Shield button carries Weakened Soul as a dark red clock across its face with the seconds written on it (red when they have no shield, pale while one still holds) and a red rim when they are bare and locked; a pip per teammate along its bottom edge says who can take a shield (yellow), who has one (blue) and who cannot (red), and the one the Advisor wants shielded stands taller. The Mending button names who is holding yours, shows its charges, and wears a rim for whether it can bounce on from them: green, somebody is within twenty yards; red, nobody is, so their next hit spends the heal and wastes the rest; no rim where the client gives no positions (/cadv range shows what it can see). Hover either button for the same in words.")
        local function WatchOn() return IsOn() end
        panel:AddCheckboxPair({
            label = "Weakened Soul On Shield",
            tooltip = "Draw the target's Weakened Soul across your Power Word: Shield buttons as a clock with its seconds, and a red rim while they have no shield to show for it.",
            get = function() return CommanderAdvisorDB.ShieldWatch end,
            set = function(value) CommanderAdvisorDB.ShieldWatch = value end,
            isEnabled = WatchOn,
        }, {
            label = "Team Pips",
            tooltip = "One pip per teammate along the Shield button's bottom edge: yellow can take a shield, blue has one, red is bare and locked by Weakened Soul, grey is dead. Faded when your shield cannot reach them.",
            get = function() return CommanderAdvisorDB.TeamPips end,
            set = function(value) CommanderAdvisorDB.TeamPips = value end,
            isEnabled = function() return IsOn() and CommanderAdvisorDB.ShieldWatch end,
        })
        panel:AddCheckboxPair({
            label = "Mending Bounce Range",
            tooltip = "Name who is holding your Prayer of Mending on its button, show its charges, and rim it green while somebody is within twenty yards of them to bounce to — red when nobody is.",
            get = function() return CommanderAdvisorDB.MendingWatch end,
            set = function(value) CommanderAdvisorDB.MendingWatch = value end,
            isEnabled = WatchOn,
        }, {
            label = "Names On Buttons",
            tooltip = "Write who the button is about across its top, in their class colour, whenever it is not you.",
            get = function() return CommanderAdvisorDB.WatchNames end,
            set = function(value) CommanderAdvisorDB.WatchNames = value end,
            isEnabled = function() return IsOn() and (CommanderAdvisorDB.ShieldWatch or CommanderAdvisorDB.MendingWatch) end,
        })
    end

    AddRuleSections(panel)

    panel:AddButtonRow({
        {
            label = "Report",
            width = 110,
            tooltip = "Print every rule for this character with what it is doing right now and why (also: /cadv report).",
            onClick = function() if CommanderAdvisor_Report then CommanderAdvisor_Report() end end,
        },
        {
            label = "Test Glows",
            width = 110,
            tooltip = "Light three buttons on your bars at low, medium and high for a few seconds (also: /cadv test).",
            onClick = function() if CommanderAdvisor_Test then CommanderAdvisor_Test() end end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Advisor" then
        Commander.UI.ApplyDefaults(CommanderAdvisorDB, DefaultSettings)
        if type(CommanderAdvisorDB.RuleModes) ~= "table" then CommanderAdvisorDB.RuleModes = {} end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

CommanderKicksDB = _G.CommanderKicksDB or {}

COMMANDER_KICKS_EVENTS = {
    UPDATE = "COMMANDER_KICKS_UPDATE"
}

-- Defaults are the opinionated part of this file, and the opinion is that an
-- interrupt bar answers one question -- "can I cast right now?" -- and should
-- be readable by POSITION: every enemy's kicks laid out from the gates, in a
-- fixed order, lit while they are up and grey while they are down. The
-- classic bar (icons that appear only when spent) is one checkbox away.
local DefaultSettings = {
    Enable = true,

    -- Where it draws. Arena and battleground on, the world off: outdoors
    -- this would light up on every shaman's Earth Shock at a mob.
    ShowInArena = true,
    ShowInBattleground = true,
    ShowInWorld = false,
    CombatOnly = false,

    -- Whose kicks. Arena seats are the arena answer; target and focus are
    -- the battleground one, where no enemy unit tokens exist.
    ShowArena = true,
    ShowTarget = true,
    ShowFocus = true,

    -- What gets an icon. ShowReady is the whole character of the bar: on,
    -- the bar has a fixed shape and a ready kick is a visible threat; off,
    -- only what is on cooldown is drawn -- the classic InterruptBar look.
    ShowReady = true,
    ReadyFlash = 1.5,           -- seconds a finished cooldown glows "back up"
    ReadySound = false,         -- ...and says so
    ReadyAlpha = 1.0,           -- how bright a ready icon sits

    -- Layout
    Orientation = "HORIZONTAL", -- HORIZONTAL | VERTICAL
    IconSize = 30,
    IconSpacing = 3,
    GroupSpacing = 10,          -- between one enemy's icons and the next's
    ShowName = false,
    NameMaxChars = 8,
    NameSize = 10,
    ShowSeat = true,            -- the 1/2/3 (or initial) badge on each icon

    -- On each icon
    ShowTimer = true,
    ShowSwipe = true,
    TimerSize = 12,
    DesaturateDown = true,      -- grey an icon while it is on cooldown
    LockoutTint = true,         -- red timer for the lockout's length
}

for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderKicksDB, DefaultSettings)
    Commander.Notify(COMMANDER_KICKS_EVENTS.UPDATE)
    print("Commander Kicks: settings restored to defaults")
end

local function Enabled()
    return CommanderKicksDB.Enable
end

-- ---------------------------------------------------------------------------
-- Sections
-- ---------------------------------------------------------------------------

local function AddWhereSection(panel)
    panel:AddSection("Where It Draws",
        "Arena and battlegrounds, which is where an enemy's kick being down decides whether you cast. The world is off by default: outdoors the bar would light up on every shaman shocking a boar.")

    panel:AddCheckboxPair({
        label = "Arenas",
        tooltip = "Draw in arena. The seats are read from the arena unit tokens, so every enemy's interrupts are on the bar from the gates -- before anybody has pressed anything.",
        get = function() return CommanderKicksDB.ShowInArena end,
        set = function(value) CommanderKicksDB.ShowInArena = value end,
        isEnabled = Enabled,
    }, {
        label = "Battlegrounds",
        tooltip = "Draw in battlegrounds. There are no arena unit tokens here, so the bar follows your target and focus, plus anyone whose kick was actually seen in the combat log.",
        get = function() return CommanderKicksDB.ShowInBattleground end,
        set = function(value) CommanderKicksDB.ShowInBattleground = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Out in the world",
        tooltip = "Draw everywhere else -- duels, world PvP. Off by default because a bar that reacts to every mob fight stops being glanceable.",
        get = function() return CommanderKicksDB.ShowInWorld end,
        set = function(value) CommanderKicksDB.ShowInWorld = value end,
        isEnabled = Enabled,
    }, {
        label = "Only in combat",
        tooltip = "Hide the bar out of combat. The cooldowns keep running underneath -- this hides the display, it does not stop the tracking, so a bar that comes back mid-fight is still right.",
        get = function() return CommanderKicksDB.CombatOnly end,
        set = function(value) CommanderKicksDB.CombatOnly = value end,
        isEnabled = Enabled,
    })
end

local function AddWhoSection(panel)
    panel:AddSection("Whose Kicks",
        "Enemies the bar can NAME get their whole book -- every interrupt their class and race carries, ready or not. Everyone else gets an icon only for a kick they were actually seen to spend, which is the honest answer for a battleground stranger whose class the client has not told us yet.")

    panel:AddCheckboxPair({
        label = "Arena opponents",
        tooltip = "One group of icons per arena seat, in seat order, from the arena unit tokens. A felhunter's Spell Lock is credited to its warlock.",
        get = function() return CommanderKicksDB.ShowArena end,
        set = function(value) CommanderKicksDB.ShowArena = value end,
        isEnabled = Enabled,
    }, {
        label = "Your target",
        tooltip = "A group for whoever you have targeted, when they are a hostile player. The battleground answer.",
        get = function() return CommanderKicksDB.ShowTarget end,
        set = function(value) CommanderKicksDB.ShowTarget = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckbox({
        label = "Your focus",
        tooltip = "The same for your focus. Focus the enemy healer's kicker and keep their Counterspell on screen while you fight somebody else.",
        get = function() return CommanderKicksDB.ShowFocus end,
        set = function(value) CommanderKicksDB.ShowFocus = value end,
        isEnabled = Enabled,
    })
end

local function AddWhatSection(panel)
    panel:AddSection("Ready Kicks",
        "The one setting that decides what kind of bar this is. Drawn while ready, the bar has a fixed shape you read by position: a lit icon is a kick that is UP, a grey one is a kick you can cast into. Hidden while ready, an icon appears the moment a kick is spent and leaves when it is back -- the classic interrupt bar, quieter, and blank at exactly the moment every kick is up.")

    panel:AddCheckbox({
        label = "Draw an interrupt while it is ready",
        tooltip = "On: every kick an enemy owns is on the bar from the start, lit while ready and grey with a clock while down. Off: only kicks that are on cooldown are drawn.",
        get = function() return CommanderKicksDB.ShowReady end,
        set = function(value) CommanderKicksDB.ShowReady = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Back-up flash",
        tooltip = "Seconds an icon glows when its cooldown ends -- the moment the kick is a threat again. With ready icons hidden, this is how long the icon lingers to say so before it leaves. Zero turns it off.",
        min = 0, max = 5, step = 0.5, format = "%.1fs",
        get = function() return CommanderKicksDB.ReadyFlash end,
        set = function(value) CommanderKicksDB.ReadyFlash = value end,
        isEnabled = Enabled,
    }, {
        label = "Ready brightness",
        tooltip = "How bright a ready icon sits. Full is the honest default -- a ready kick is the dangerous state -- but a dimmer bar is easier to keep at the edge of your attention.",
        min = 0.3, max = 1, step = 0.05, format = "%.2f",
        get = function() return CommanderKicksDB.ReadyAlpha end,
        set = function(value) CommanderKicksDB.ReadyAlpha = value end,
        isEnabled = function() return Enabled() and CommanderKicksDB.ShowReady end,
    })

    panel:AddCheckbox({
        label = "Sound when a kick comes back",
        tooltip = "A short alert the moment an enemy interrupt is off cooldown. Off by default -- in a 3v3 with three kickers it is a lot of noise -- but on for anyone who casts by ear.",
        get = function() return CommanderKicksDB.ReadySound end,
        set = function(value) CommanderKicksDB.ReadySound = value end,
        isEnabled = Enabled,
    })
end

local function AddLayoutSection(panel)
    panel:AddSection("Layout",
        "A HUD, not a window. One group of icons per enemy, groups separated by a wider gap so a double-rogue team still reads as two people.")

    panel:AddDropdownPair({
        label = "Direction",
        tooltip = "Icons in a row, or in a column.",
        options = {
            { text = "Horizontal", value = "HORIZONTAL" },
            { text = "Vertical", value = "VERTICAL" },
        },
        get = function() return CommanderKicksDB.Orientation end,
        set = function(value) CommanderKicksDB.Orientation = value end,
        isEnabled = Enabled,
    }, nil)

    panel:AddSliderPair({
        label = "Icon size",
        tooltip = "Bigger than you think. This is read peripherally.",
        min = 16, max = 56, step = 1, format = "%d",
        get = function() return CommanderKicksDB.IconSize end,
        set = function(value) CommanderKicksDB.IconSize = value end,
        isEnabled = Enabled,
    }, {
        label = "Between icons",
        tooltip = "Gap between one enemy's interrupts.",
        min = 0, max = 12, step = 1, format = "%d",
        get = function() return CommanderKicksDB.IconSpacing end,
        set = function(value) CommanderKicksDB.IconSpacing = value end,
        isEnabled = Enabled,
    })

    panel:AddSliderPair({
        label = "Between enemies",
        tooltip = "The wider gap between one enemy's group and the next's.",
        min = 0, max = 30, step = 1, format = "%d",
        get = function() return CommanderKicksDB.GroupSpacing end,
        set = function(value) CommanderKicksDB.GroupSpacing = value end,
        isEnabled = Enabled,
    }, {
        label = "Name size",
        tooltip = "Point size of the name over each group.",
        min = 8, max = 18, step = 1, format = "%d",
        get = function() return CommanderKicksDB.NameSize end,
        set = function(value) CommanderKicksDB.NameSize = value end,
        isEnabled = function() return Enabled() and CommanderKicksDB.ShowName end,
    })

    panel:AddCheckboxPair({
        label = "Name each enemy",
        tooltip = "Their name over the group, in class colour. Off by default: the seat badge on each icon says the same thing in less space.",
        get = function() return CommanderKicksDB.ShowName end,
        set = function(value) CommanderKicksDB.ShowName = value end,
        isEnabled = Enabled,
    }, {
        label = "Seat badge",
        tooltip = "A small 1, 2, 3 in the corner of each icon -- the arena seat -- or the first letter of the name outside arena. With two enemies of one class it is the only way to know whose Kick you are looking at.",
        get = function() return CommanderKicksDB.ShowSeat end,
        set = function(value) CommanderKicksDB.ShowSeat = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Name length",
        tooltip = "Names are cut to this many characters.",
        min = 3, max = 16, step = 1, format = "%d",
        get = function() return CommanderKicksDB.NameMaxChars end,
        set = function(value) CommanderKicksDB.NameMaxChars = value end,
        isEnabled = function() return Enabled() and CommanderKicksDB.ShowName end,
    })
end

local function AddCellSection(panel)
    panel:AddSection("On Each Icon",
        "A clock, a sweep, and a colour. The clock goes red for the opening stretch of each cooldown -- the length of the lockout the kick just inflicted -- because for those seconds the kick is still doing its work, and after them the only thing left to fear is the cooldown ending.")

    panel:AddCheckboxPair({
        label = "Cooldown clock",
        tooltip = "Seconds until the kick is back, written on the icon.",
        get = function() return CommanderKicksDB.ShowTimer end,
        set = function(value) CommanderKicksDB.ShowTimer = value end,
        isEnabled = Enabled,
    }, {
        label = "Clock sweep",
        tooltip = "The sweep under the icon, running out with the cooldown. Reads faster than the number at a glance and costs nothing to have both.",
        get = function() return CommanderKicksDB.ShowSwipe end,
        set = function(value) CommanderKicksDB.ShowSwipe = value end,
        isEnabled = Enabled,
    })

    panel:AddCheckboxPair({
        label = "Grey while down",
        tooltip = "Desaturate an icon while its kick is on cooldown, so the lit ones -- the kicks that are UP -- are the ones your eye lands on.",
        get = function() return CommanderKicksDB.DesaturateDown end,
        set = function(value) CommanderKicksDB.DesaturateDown = value end,
        isEnabled = Enabled,
    }, {
        label = "Red for the lockout",
        tooltip = "Paint the clock red for the first seconds of each cooldown -- as long as the lockout that kick inflicts. Somebody on your side cannot cast that school right now.",
        get = function() return CommanderKicksDB.LockoutTint end,
        set = function(value) CommanderKicksDB.LockoutTint = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Clock size",
        tooltip = "Point size of the cooldown clock on each icon.",
        min = 8, max = 20, step = 1, format = "%d",
        get = function() return CommanderKicksDB.TimerSize end,
        set = function(value) CommanderKicksDB.TimerSize = value end,
        isEnabled = function() return Enabled() and CommanderKicksDB.ShowTimer end,
    })
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "Kicks",
        title = "Kicks",
        addonName = "Commander_Kicks",
        description = "An interrupt bar for arena and battlegrounds: every enemy's kicks -- Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Spell Lock, Silencing Shot, Silence, Feral Charge, Arcane Torrent -- laid out in a fixed order per enemy, lit while ready and grey with a clock while down, so 'can I cast right now?' is answered by glancing rather than reading. Arena seats get their whole book from the gates; a battleground stranger gets an icon for whatever they were seen to spend. Ranks matched by name, the three shocks sharing one cooldown, a felhunter's Spell Lock credited to its warlock, and the clock red for exactly as long as the lockout that kick inflicted.",
        event = COMMANDER_KICKS_EVENTS.UPDATE,
        slash = { "/ckicks", "/ckick" },
        slashHandlers = {
            test = function() if CommanderKicks_Test then CommanderKicks_Test() end end,
            report = function() if CommanderKicks_Report then CommanderKicks_Report() end end,
            lock = function()
                CommanderKicksDB.HudLocked = not CommanderKicksDB.HudLocked
                Commander.Notify(COMMANDER_KICKS_EVENTS.UPDATE)
                print("Commander Kicks: bar "
                    .. (CommanderKicksDB.HudLocked and "locked" or "unlocked -- drag it, right-click to lock"))
            end,
        },
    })

    panel:AddCheckbox({
        label = "Enable Kicks",
        tooltip = "The whole module.",
        get = function() return CommanderKicksDB.Enable end,
        set = function(value) CommanderKicksDB.Enable = value end,
    })

    panel:AddButtonRow({
        {
            label = "Test Bar",
            tooltip = "Draw a bar for a fabricated mage, rogue and blood-elf shaman -- some kicks down, some up, one just back -- so it can be placed and sized without queueing. Works anywhere; clears itself after a few seconds.",
            onClick = function() if CommanderKicks_Test then CommanderKicks_Test() end end,
            isEnabled = Enabled,
        },
        {
            label = "What Is Tracked?",
            tooltip = "Print the interrupt book -- every spell the bar watches, with its cooldown and lockout -- and who the bar is tracking right now.",
            onClick = function() if CommanderKicks_Report then CommanderKicks_Report() end end,
            isEnabled = Enabled,
        },
        {
            label = "Unlock & Move",
            tooltip = "Unlock the bar so it can be dragged. Right-click it to lock again, or triple right-click a locked one to unlock it without coming back here.",
            onClick = function()
                CommanderKicksDB.HudLocked = false
                Commander.Notify(COMMANDER_KICKS_EVENTS.UPDATE)
            end,
            isEnabled = Enabled,
        },
    })

    AddWhereSection(panel)
    AddWhoSection(panel)
    AddWhatSection(panel)
    AddLayoutSection(panel)
    AddCellSection(panel)

    -- Chrome last, per the suite convention
    Commander.UI.AddHudChromeOptions(panel, CommanderKicksDB, "Hud", {
        isEnabled = Enabled,
        onChanged = function() Commander.Notify(COMMANDER_KICKS_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Kicks" then
        Commander.UI.ApplyDefaults(CommanderKicksDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

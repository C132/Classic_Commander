CommanderPartyFramesDB = _G.CommanderPartyFramesDB or {}

COMMANDER_PARTYFRAMES_EVENTS = {
    UPDATE = "COMMANDER_PARTYFRAMES_UPDATE"
}

local DefaultSettings = {
    EnableShield = true,
    Scope = "PARTY",         -- PARTY (you + party) or RAID (you + raid)
    IncludeSelf = true,
    SelfFirst = false,       -- pin yourself to the top instead of sorting by urgency
    ShowHeader = true,       -- PW:S cooldown + your nominal shield value strip
    OnlyAlerts = false,      -- hide healthy SHIELDED/OTHER rows, keep the ones needing a decision
    AlwaysShow = false,
    FixedHeight = false,
    MaxRows = 6,
    FrameWidth = 214,
    LowAbsorbPct = 25,       -- absorb at/under this % of capacity counts as "low"
    LowTimeSecs = 5,         -- shield with this many seconds left counts as "expiring"

    -- Identity & icons (defaults are icon-first, minimal text)
    ShowSpellIcon = true,
    UnitDisplay = "CLASS_ICON", -- CLASS_ICON | PORTRAIT | NAME | ICON_NAME | ICON_PORTRAIT
    ColorShieldTypes = true,    -- tint embedded shield segments per type (off = one cream)
    NameMaxChars = 6,
    ShowTargeters = true,       -- enemy-NPCs-targeting count over the class icon

    -- Ten flagged features (all neutral defaults, so current behavior is kept)
    ClickCast = false,          -- rows become secure mouseover/click unit buttons
    -- Per-button click-cast bindings (spell ID, or "TARGET" / "NONE")
    ClickLeft = 17,             -- left-click   = Power Word: Shield ("bubble")
    ClickRight = 139,           -- right-click  = Renew
    ClickMiddle = 2061,         -- middle-click = Flash Heal
    ClickModLeft = 2060,        -- modifier + left-click = Greater Heal
    ClickModifier = "shift",    -- modifier key for the mod binding: shift | ctrl | alt
    ShowHealth = false,         -- thin health underlay per row
    RangeFade = false,          -- dim units out of shield range
    ShieldSwipe = false,        -- radial 30s shield-duration sweep on the spell icon
    WSReadyGlow = false,        -- glow rows whose reshield window is open
    Grow = "DOWN",             -- board growth direction (DOWN | UP)
    CombatOnly = false,         -- only show the board in combat
    PinFocus = false,           -- pin your focus unit to the top
    TrackUptime = false,        -- track session shield coverage (+/cpf report)
    ExposeAlert = false,        -- flash a row when your shield breaks off an ally
    ExposeAlertSound = false,   -- also play a sound with the expose flash
    RenewTrack = false,         -- per-row Renew HoT indicator (pairs with the shield)
    RenewFlash = true,          -- pulse the Renew icon when it is about to expire
    RenewRefreshAt = 4,         -- seconds left at/under which Renew counts as expiring

    -- Mage layer: Int/Brilliance upkeep, mage click bindings (their own keys —
    -- the DB is account-wide, so priest bindings must survive untouched), and
    -- the opt-in self-shield extra
    ShowSettingsButton = true,  -- small gear on the header opening this settings page
    IntRefreshAt = 300,         -- Int seconds left at/under which the rebuff window opens
    ShowManaBar = true,         -- blue mana strip under each mana user's health bar
    MageClickLeft = 1459,       -- mage row left-click   = Arcane Intellect
    MageClickRight = 475,       -- mage row right-click  = Remove Curse
    MageClickMiddle = "TARGET", -- mage row middle-click = target the ally
    MageClickModLeft = 1008,    -- mage row mod+left     = Amplify Magic
    SelfShieldRows = true,      -- append your own shields under the ally rows

    -- Party Ability Bar (engine lands in phases; keys reserved now)
    ShowAbilityBar = true,      -- cooldown strip under every player row
    AbilityMaxIcons = 6,        -- most ability icons per strip (3-8)
    AbilityBarSelf = true,      -- include your own row's strip
    AbilityCdText = true,       -- remaining-time text on cooling icons
    TrackManaShield = true,     -- Mana Shield row in the self-shield extra
    TrackWards = true,          -- Fire Ward / Frost Ward rows in the extra

    -- Dispellable-debuff strip (right of the frame)
    ShowDispels = false,        -- master switch for the strip
    DispelShowAll = false,      -- show every debuff, not just ones you can dispel
    DispelShowImportant = true, -- include healer-relevant undispellables (Mortal Strike, Blind...)
    DispelCCGlow = true,        -- pulse a glow on crowd-control debuffs
    DispelHealGlow = true,      -- red pulse on healing-reduction debuffs
    DispelSweep = true,         -- radial duration sweep on each debuff icon
    DispelMaxIcons = 3,         -- icons per row (1-5)
    DispelIconSize = 16,        -- icon size in pixels
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderPartyFramesDB, DefaultSettings)
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    print("Commander Party Frames: settings restored to defaults")
end

-- Options that do nothing in secure Click-Cast mode (it uses a fixed roster
-- order so unit attributes never change in combat)
local function SortableMode()
    return CommanderPartyFramesDB.EnableShield and not CommanderPartyFramesDB.ClickCast
end

-- Spells offered for each click binding (value = spell ID, cast by highest
-- known rank; TARGET / NONE are the non-spell actions). Priest healing + utility.
local CLICK_SPELLS = {
    { text = "None", value = "NONE" },
    { text = "Target", value = "TARGET" },
    { text = "Power Word: Shield", value = 17 },
    { text = "Renew", value = 139 },
    { text = "Flash Heal", value = 2061 },
    { text = "Greater Heal", value = 2060 },
    { text = "Heal", value = 2054 },
    { text = "Lesser Heal", value = 2050 },
    { text = "Binding Heal", value = 32546 },
    { text = "Prayer of Healing", value = 596 },
    { text = "Prayer of Mending", value = 33076 },
    { text = "Dispel Magic", value = 527 },
    { text = "Abolish Disease", value = 552 },
    { text = "Cure Disease", value = 528 },
    { text = "Power Word: Fortitude", value = 1243 },
    { text = "Divine Spirit", value = 14752 },
    { text = "Shadow Protection", value = 976 },
    { text = "Fear Ward", value = 6346 },
    { text = "Resurrection", value = 2006 },
}
-- Same idea for the mage layer: group utility a mage actually casts on allies.
local MAGE_CLICK_SPELLS = {
    { text = "None", value = "NONE" },
    { text = "Target", value = "TARGET" },
    { text = "Arcane Intellect", value = 1459 },
    { text = "Arcane Brilliance", value = 23028 },
    { text = "Remove Curse", value = 475 },
    { text = "Amplify Magic", value = 1008 },
    { text = "Dampen Magic", value = 604 },
    { text = "Slow Fall", value = 130 },
}
local CLICK_MODIFIERS = {
    { text = "Shift", value = "shift" },
    { text = "Ctrl", value = "ctrl" },
    { text = "Alt", value = "alt" },
}

-- The whole module on one scrollable page, built for the class that is logged
-- in: the Priest reshield board, the Mage party frames, or a dormant-class note.
local function CreateCorePanel()
    -- Ask the engine which class layer this character gets (nil = none)
    local layerMode, classToken
    if CommanderPartyFrames_GetProfileMode then layerMode, classToken = CommanderPartyFrames_GetProfileMode() end
    local mageMode = layerMode == "INT"
    local unsupported = not layerMode

    local description
    if unsupported then
        local localizedClass = UnitClass("player")
        description = string.format(
            "Swiss-army-knife party frames with a class layer. Priests get the reshield board (Power Word: Shield, Weakened Soul, dispels); Mages get buff-upkeep frames (Arcane Intellect, decursing, an optional self-shield strip). %s has no layer yet, so the module stays dormant on this character. Settings here are shared account-wide — boards on your Priest or Mage characters are unaffected.",
            localizedClass or "This class")
    elseif mageMode then
        description = "Arena-grade party frames with a mage's brain — built to win the information war. One row per teammate: health with a mana strip, who the enemies are targeting, their TOTAL shielding (Power Word: Shield + Ice Barrier + Mana Shield + wards, whoever cast them) drained live by real absorb events, and status icons for Int and their biggest shield. A removable curse turns the row purple (Remove Curse NOW); a teammate in crowd control turns it orange with the CC's name and time left. The banner on top is YOUR management: armor with a switch popout, shield uptime, team alerts, and conjure/consume buttons; below the board sit the Water Elemental's row (lifespan, health, and the gold double-Freeze tick) and your own shield rows. Mouseover click-casting throughout."
    else
        description = "Everything about Power Word: Shield on one board — for you and every ally. Each row is the ally's health bar with every absorb on them embedded as colored segments (cream PW:S, vibrant blue Ice Barrier, blue-grey Mana Shield, dark grey Sacrifice) on a shared scale, plus your shield's remaining absorb as the row's number, the Weakened Soul lockout that blocks a reshield, and a readiness state so you know at a glance who to shield next. Sorted most-urgent first; built for Priests. Scroll down for icons, mouseover-cast, the decision aids, dispellable debuffs, and Renew tracking."
    end

    local panel = Commander.UI.NewPanel({
        key = "PartyFrames",
        title = "Party Frames",
        addonName = "Commander_PartyFrames",
        description = description,
        event = COMMANDER_PARTYFRAMES_EVENTS.UPDATE,
        slash = { "/cpf", "/cpframes" },
        slashHandlers = {
            test = function() if CommanderPartyFrames_Test then CommanderPartyFrames_Test() end end,
            report = function() if CommanderPartyFrames_Report then CommanderPartyFrames_Report() end end,
            debug = function() if CommanderPartyFrames_Debug then CommanderPartyFrames_Debug() end end,
        },
    })

    -- This page carries the whole module and is far taller than the Settings
    -- canvas, so flow its rows into a scroll frame. NewPanel's header stays
    -- fixed above; AddRow is overridden on THIS panel instance only, so the
    -- shared framework (and every other panel) is untouched.
    local scroll = CreateFrame("ScrollFrame", "CommanderPartyFramesScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel._anchor, "TOPLEFT", 0, 0)   -- panel._anchor = content top (below header)
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

    -- Re-seat the flow anchor inside the scroll child and route every row there
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

    -- Dormant class: the description above says everything — no controls that
    -- would silently do nothing (and, DB being account-wide, nothing to safely
    -- toggle from here anyway).
    if unsupported then
        panel:Finalize({ onDefaults = Reset })
        scrollChild:SetHeight(panel._contentHeight + 24)
        return
    end

    -- ---- Mage party frames: buff upkeep + decursing on the ally chassis ----
    if mageMode then
        panel:AddCheckboxPair({
            label = "Enable Shield",
            tooltip = "Master switch for the whole module.",
            get = function() return CommanderPartyFramesDB.EnableShield end,
            set = function(value) CommanderPartyFramesDB.EnableShield = value end,
        }, {
            label = "Show Header",
            tooltip = "Show your management banner at the top: your armor with time left (a red OFF when you have none) with the click-to-switch popout, session shield uptime when tracked, team alerts (curses to remove, teammates in CC), and the conjure/consume/settings buttons. Live shield tracking lives on the My Shields rows below the board.",
            get = function() return CommanderPartyFramesDB.ShowHeader end,
            set = function(value) CommanderPartyFramesDB.ShowHeader = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Include Self",
            tooltip = "Add your own row to the board — your Int upkeep and any curses on you, alongside your allies'.",
            get = function() return CommanderPartyFramesDB.IncludeSelf end,
            set = function(value) CommanderPartyFramesDB.IncludeSelf = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Self First",
            tooltip = "Pin your own row to the top instead of sorting it in by urgency. No effect in Click-Cast mode (fixed roster order).",
            get = function() return CommanderPartyFramesDB.SelfFirst end,
            set = function(value) CommanderPartyFramesDB.SelfFirst = value end,
            isEnabled = function() return SortableMode() and CommanderPartyFramesDB.IncludeSelf end,
        })
        panel:AddCheckboxPair({
            label = "Only Show Alerts",
            tooltip = "Hide the quiet rows and keep only the ones that want attention — cursed or CC'd teammates (you always stay visible). No effect in Click-Cast mode (fixed roster order).",
            get = function() return CommanderPartyFramesDB.OnlyAlerts end,
            set = function(value) CommanderPartyFramesDB.OnlyAlerts = value end,
            isEnabled = SortableMode,
        }, {
            label = "Always Show",
            tooltip = "Keep the board frame on screen even when there is nothing to report.",
            get = function() return CommanderPartyFramesDB.AlwaysShow end,
            set = function(value) CommanderPartyFramesDB.AlwaysShow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Fixed Frame Size",
            tooltip = "Keep the frame (and its styled backdrop) sized for the full board length instead of shrinking to what is currently shown.",
            get = function() return CommanderPartyFramesDB.FixedHeight end,
            set = function(value) CommanderPartyFramesDB.FixedHeight = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Settings Button",
            tooltip = "Show a small gear at the header's right edge that opens this settings page.",
            get = function() return CommanderPartyFramesDB.ShowSettingsButton end,
            set = function(value) CommanderPartyFramesDB.ShowSettingsButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })
        panel:AddDropdown({
            label = "Watch",
            tooltip = "Which allies to put on the board. Party watches you and your party; Raid watches you and your raid group (use Max Rows and Only Show Alerts to keep a large raid readable).",
            options = {
                { text = "Party", value = "PARTY" },
                { text = "Raid", value = "RAID" },
            },
            get = function() return CommanderPartyFramesDB.Scope end,
            set = function(value) CommanderPartyFramesDB.Scope = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSliderPair({
            label = "Max Rows",
            tooltip = "Most ALLY rows shown at once (most urgent first). Your own rows — the elemental and My Shields — always fit below the cap.",
            min = 1, max = 40, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.MaxRows end,
            set = function(value) CommanderPartyFramesDB.MaxRows = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Frame Width",
            tooltip = "Overall width of the board — widen until names and numbers sit comfortably.",
            min = 180, max = 340, step = 2,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.FrameWidth end,
            set = function(value) CommanderPartyFramesDB.FrameWidth = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Rebuff Window",
            tooltip = "Treat an ally's Arcane Intellect as due when this much time or less remains — their Int status icon turns amber so you can rebuff before it drops.",
            min = 60, max = 900, step = 30,
            format = function(value) return string.format("%dm", math.floor((value or 0) / 60 + 0.5)) end,
            get = function() return CommanderPartyFramesDB.IntRefreshAt end,
            set = function(value) CommanderPartyFramesDB.IntRefreshAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddButtonRow({
            {
                label = "Test Board",
                width = 110,
                tooltip = "Fill the board with sample rows in every state so you can see and position it without a group (also: /cpf test).",
                onClick = function() if CommanderPartyFrames_Test then CommanderPartyFrames_Test() end end,
            },
        })

        panel:AddSection("Identity & Icons")
        panel:AddDropdownPair({
            label = "Show Unit As",
            tooltip = "How each ally is labelled. Class Icon is the most compact (no name); Portrait shows their 2D model (class icon when off-screen); Name is text only; Icon + Name shows icon and name; Icon + Portrait shows the class icon beside the live portrait; the Specialization modes swap in the talent-tree icon once a player's spec has been learned from their casts (class icon until then).",
            options = {
                { text = "Class Icon", value = "CLASS_ICON" },
                { text = "Portrait", value = "PORTRAIT" },
                { text = "Name", value = "NAME" },
                { text = "Icon + Name", value = "ICON_NAME" },
                { text = "Icon + Portrait", value = "ICON_PORTRAIT" },
                { text = "Specialization", value = "SPEC" },
                { text = "Spec + Portrait", value = "SPEC_PORTRAIT" },
            },
            get = function() return CommanderPartyFramesDB.UnitDisplay end,
            set = function(value) CommanderPartyFramesDB.UnitDisplay = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Grow",
            tooltip = "Direction the board grows from its anchor.",
            options = {
                { text = "Down", value = "DOWN" },
                { text = "Up", value = "UP" },
            },
            get = function() return CommanderPartyFramesDB.Grow end,
            set = function(value) CommanderPartyFramesDB.Grow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Status Icons",
            tooltip = "Show the two team-synergy icons on the left of each row: Arcane Intellect state (lit / amber when a rebuff is due / ghost when missing; hidden for rage and energy classes) and the ally's biggest shield with a sweep for its remaining time. The row's number is their TOTAL shielding — Power Word: Shield, Ice Barrier, Mana Shield, wards, Sacrifice, whoever cast them.",
            get = function() return CommanderPartyFramesDB.ShowSpellIcon end,
            set = function(value) CommanderPartyFramesDB.ShowSpellIcon = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "NPC Target Counter",
            tooltip = "Show, over each unit's class icon or portrait, how many enemy NPCs are currently targeting them — white 1, amber 2, red 3+. Reads the visible enemy nameplates, so turn enemy nameplates on (default V) for full coverage; needs an icon to sit on, so it hides in Name-only display.",
            get = function() return CommanderPartyFramesDB.ShowTargeters end,
            set = function(value) CommanderPartyFramesDB.ShowTargeters = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.UnitDisplay ~= "NAME"
            end,
        })
        panel:AddSlider({
            label = "Name Length",
            tooltip = "Trim ally names to this many characters (keeps rows compact). Applies when Show Unit As includes a name.",
            min = 3, max = 12, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.NameMaxChars end,
            set = function(value) CommanderPartyFramesDB.NameMaxChars = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and (CommanderPartyFramesDB.UnitDisplay == "NAME" or CommanderPartyFramesDB.UnitDisplay == "ICON_NAME")
            end,
        })
        panel:AddCheckbox({
            label = "Color Shield Types",
            tooltip = "Tint each embedded shield segment by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
            get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
            set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })

        panel:AddSection("Mouseover & Click", "Turn rows into secure unit buttons: hovering feeds your @mouseover macros and each mouse button casts its bound spell. Enabling needs a /reload; uses a fixed roster order.")
        panel:AddCheckbox({
            label = "Enable Row Clicks",
            tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each mouse button casts the spell you bind below. Because secure frames can't change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
            get = function() return CommanderPartyFramesDB.ClickCast end,
            set = function(value) CommanderPartyFramesDB.ClickCast = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        local function MageClickEnabled() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end
        local function MageBindingDropdown(label, tooltip, key)
            panel:AddDropdown({
                label = label, tooltip = tooltip, options = MAGE_CLICK_SPELLS,
                get = function() return CommanderPartyFramesDB[key] end,
                set = function(value) CommanderPartyFramesDB[key] = value end,
                isEnabled = MageClickEnabled,
            })
        end
        MageBindingDropdown("Left-Click",
            "Spell cast when you left-click an ally's row. Choose Target to just target them, or None to free the button. Casts your highest known rank; @mouseover macros keep working too.",
            "MageClickLeft")
        MageBindingDropdown("Right-Click", "Spell cast when you right-click an ally's row (replaces the right-click menu).", "MageClickRight")
        MageBindingDropdown("Middle-Click", "Spell cast when you middle-click an ally's row.", "MageClickMiddle")
        MageBindingDropdown("Modifier + Left-Click", "Spell cast when you hold the Modifier Key (below) and left-click an ally's row.", "MageClickModLeft")
        panel:AddDropdown({
            label = "Modifier Key",
            tooltip = "Which held key triggers the Modifier + Left-Click binding.",
            options = CLICK_MODIFIERS,
            get = function() return CommanderPartyFramesDB.ClickModifier end,
            set = function(value) CommanderPartyFramesDB.ClickModifier = value end,
            isEnabled = MageClickEnabled,
        })

        panel:AddSection("Decision Aids")
        panel:AddCheckboxPair({
            label = "Mana Bar",
            tooltip = "Show a blue mana strip under each mana user's health bar — the health bar itself is always on (it IS the row's main bar).",
            get = function() return CommanderPartyFramesDB.ShowManaBar end,
            set = function(value) CommanderPartyFramesDB.ShowManaBar = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Range Fade",
            tooltip = "Dim allies who are out of range, so you only act on the ones you can actually reach.",
            get = function() return CommanderPartyFramesDB.RangeFade end,
            set = function(value) CommanderPartyFramesDB.RangeFade = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Action Glow",
            tooltip = "Softly glow any row with an open action — a curse to remove, a missing Int, or a rebuff window — so the next cast jumps out.",
            get = function() return CommanderPartyFramesDB.WSReadyGlow end,
            set = function(value) CommanderPartyFramesDB.WSReadyGlow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Pin Focus",
            tooltip = "Keep your focus unit's row at the top of the board. No effect in Click-Cast mode (fixed roster order).",
            get = function() return CommanderPartyFramesDB.PinFocus end,
            set = function(value) CommanderPartyFramesDB.PinFocus = value end,
            isEnabled = SortableMode,
        })
        panel:AddCheckboxPair({
            label = "Combat Only",
            tooltip = "Only show the board while you are in combat.",
            get = function() return CommanderPartyFramesDB.CombatOnly end,
            set = function(value) CommanderPartyFramesDB.CombatOnly = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Track Uptime",
            tooltip = "Track your SHIELD uptime — the share of the session you keep an absorb up on yourself (Mana Shield, Ice Barrier, a priest's bubble). Shown in the banner; detailed by /cpf report.",
            get = function() return CommanderPartyFramesDB.TrackUptime end,
            set = function(value) CommanderPartyFramesDB.TrackUptime = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Shield Broke Flash",
            tooltip = "Flash a row red the moment a teammate's LAST shield breaks — that is exactly when the enemy team commits. Also flashes a self-shield row when that shield breaks.",
            get = function() return CommanderPartyFramesDB.ExposeAlert end,
            set = function(value) CommanderPartyFramesDB.ExposeAlert = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Break Sound",
            tooltip = "Also play an alert sound with the flash.",
            get = function() return CommanderPartyFramesDB.ExposeAlertSound end,
            set = function(value) CommanderPartyFramesDB.ExposeAlertSound = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ExposeAlert end,
        })

        panel:AddSection("Dispellable Debuffs", "A strip of icons to the right of each row showing debuffs you can remove — Curses, purple rim — with a glow on crowd control. Curses also turn the whole row purple, whatever is shown here.")
        panel:AddCheckboxPair({
            label = "Show Dispellable Debuffs",
            tooltip = "Show, to the right of each ally's row, the Curses you can remove (purple rim, countdown sweep). The CURSED row state works even with this strip off; the strip tells you WHICH curse it is.",
            get = function() return CommanderPartyFramesDB.ShowDispels end,
            set = function(value) CommanderPartyFramesDB.ShowDispels = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "CC Glow",
            tooltip = "Pulse a bright glow behind crowd-control debuffs so the one that needs removing first jumps out of a busy strip.",
            get = function() return CommanderPartyFramesDB.DispelCCGlow end,
            set = function(value) CommanderPartyFramesDB.DispelCCGlow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        })
        panel:AddCheckboxPair({
            label = "Important Debuffs",
            tooltip = "Also show debuffs worth knowing about even though you cannot remove them: healing reductions, undispellable crowd control and stuns, and silences. These get a category-colored rim and sort to the front of the strip.",
            get = function() return CommanderPartyFramesDB.DispelShowImportant end,
            set = function(value) CommanderPartyFramesDB.DispelShowImportant = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        }, {
            label = "Duration Sweep",
            tooltip = "Draw a radial countdown over each debuff icon showing how long it has left.",
            get = function() return CommanderPartyFramesDB.DispelSweep end,
            set = function(value) CommanderPartyFramesDB.DispelSweep = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        })
        panel:AddSliderPair({
            label = "Debuff Icons",
            tooltip = "How many debuff icons to show per row.",
            min = 1, max = 5, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.DispelMaxIcons end,
            set = function(value) CommanderPartyFramesDB.DispelMaxIcons = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        }, {
            label = "Debuff Icon Size",
            tooltip = "Size of each debuff icon in the strip.",
            min = 10, max = 24, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.DispelIconSize end,
            set = function(value) CommanderPartyFramesDB.DispelIconSize = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        })

        panel:AddSection("My Shields", "Your own Ice Barrier, Mana Shield, and wards as rows under the ally board — absorb remaining as the bar, each spell's cooldown as the red drain. Works on both the sorted and the Click-Cast boards; the Water Elemental's row appears just above these whenever it is in play.")
        panel:AddCheckboxPair({
            label = "Show My Shields",
            tooltip = "Append a row for each self-shield you know beneath the ally rows: READY to cast, on cooldown (EXPOSED, drain shows time left), running low (REFRESH), or holding (with absorb remaining).",
            get = function() return CommanderPartyFramesDB.SelfShieldRows end,
            set = function(value) CommanderPartyFramesDB.SelfShieldRows = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Track Mana Shield",
            tooltip = "Give Mana Shield its own row in the extra. No cooldown, so its row only ever asks: is it up, and how much is left?",
            get = function() return CommanderPartyFramesDB.TrackManaShield end,
            set = function(value) CommanderPartyFramesDB.TrackManaShield = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.SelfShieldRows end,
        })
        panel:AddCheckbox({
            label = "Track Wards",
            tooltip = "Give Fire Ward and Frost Ward rows in the extra (only the ones you know). Their 30s cooldown shows as the red drain, so you can pre-ward the moment it matters.",
            get = function() return CommanderPartyFramesDB.TrackWards end,
            set = function(value) CommanderPartyFramesDB.TrackWards = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.SelfShieldRows end,
        })

        Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
            onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
        })

        panel:Finalize({ onDefaults = Reset })
        scrollChild:SetHeight(panel._contentHeight + 24)
        return
    end

    -- ---- Priest ally board (the original page, unchanged) ----
    panel:AddCheckboxPair({
        label = "Enable Shield",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderPartyFramesDB.EnableShield end,
        set = function(value) CommanderPartyFramesDB.EnableShield = value end,
    }, {
        label = "Show Header",
        tooltip = "Show the strip at the top: your live Power Word: Shield cooldown and your current nominal shield value (and session coverage, when Track Uptime is on).",
        get = function() return CommanderPartyFramesDB.ShowHeader end,
        set = function(value) CommanderPartyFramesDB.ShowHeader = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckboxPair({
        label = "Include Self",
        tooltip = "Add your own row to the board — track your own shield and Weakened Soul alongside your allies'.",
        get = function() return CommanderPartyFramesDB.IncludeSelf end,
        set = function(value) CommanderPartyFramesDB.IncludeSelf = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Self First",
        tooltip = "Pin your own row to the top instead of sorting it in by urgency. No effect in Click-Cast mode (fixed roster order).",
        get = function() return CommanderPartyFramesDB.SelfFirst end,
        set = function(value) CommanderPartyFramesDB.SelfFirst = value end,
        isEnabled = function() return SortableMode() and CommanderPartyFramesDB.IncludeSelf end,
    })
    panel:AddCheckboxPair({
        label = "Only Show Alerts",
        tooltip = "Hide the healthy rows and keep only the ones that want a decision: exposed, expiring, or ready to shield. No effect in Click-Cast mode (fixed roster order).",
        get = function() return CommanderPartyFramesDB.OnlyAlerts end,
        set = function(value) CommanderPartyFramesDB.OnlyAlerts = value end,
        isEnabled = SortableMode,
    }, {
        label = "Always Show",
        tooltip = "Keep the board frame on screen even when there is nothing to report.",
        get = function() return CommanderPartyFramesDB.AlwaysShow end,
        set = function(value) CommanderPartyFramesDB.AlwaysShow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckboxPair({
        label = "Fixed Frame Size",
        tooltip = "Keep the frame (and its styled backdrop) sized for the full board length instead of shrinking to what is currently shown.",
        get = function() return CommanderPartyFramesDB.FixedHeight end,
        set = function(value) CommanderPartyFramesDB.FixedHeight = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Settings Button",
        tooltip = "Show a small gear at the header's right edge that opens this settings page.",
        get = function() return CommanderPartyFramesDB.ShowSettingsButton end,
        set = function(value) CommanderPartyFramesDB.ShowSettingsButton = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
    })
    panel:AddDropdown({
        label = "Watch",
        tooltip = "Which allies to put on the board. Party watches you and your party; Raid watches you and your raid group (use Max Rows and Only Show Alerts to keep a large raid readable).",
        options = {
            { text = "Party", value = "PARTY" },
            { text = "Raid", value = "RAID" },
        },
        get = function() return CommanderPartyFramesDB.Scope end,
        set = function(value) CommanderPartyFramesDB.Scope = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddSliderPair({
        label = "Max Rows",
        tooltip = "Most rows shown at once (most urgent first).",
        min = 1, max = 40, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.MaxRows end,
        set = function(value) CommanderPartyFramesDB.MaxRows = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Frame Width",
        tooltip = "Overall width of the board — widen until names and numbers sit comfortably.",
        min = 180, max = 340, step = 2,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.FrameWidth end,
        set = function(value) CommanderPartyFramesDB.FrameWidth = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddSliderPair({
        label = "Low Absorb",
        tooltip = "A shield holding at or below this share of its capacity is treated as low — flagged to top off (or as fading if you cannot reshield yet).",
        min = 5, max = 60, step = 5,
        format = function(value) return string.format("%d%%", value or 0) end,
        get = function() return CommanderPartyFramesDB.LowAbsorbPct end,
        set = function(value) CommanderPartyFramesDB.LowAbsorbPct = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Expiring At",
        tooltip = "A shield with this many seconds or fewer remaining is treated as expiring, the same as running low on absorb.",
        min = 1, max = 15, step = 1,
        format = function(value) return string.format("%ds", value or 0) end,
        get = function() return CommanderPartyFramesDB.LowTimeSecs end,
        set = function(value) CommanderPartyFramesDB.LowTimeSecs = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddButtonRow({
        {
            label = "Test Board",
            width = 110,
            tooltip = "Fill the board with sample rows in every state so you can see and position it without a group (also: /cpf test).",
            onClick = function() if CommanderPartyFrames_Test then CommanderPartyFrames_Test() end end,
        },
    })

    panel:AddSection("Identity & Icons")
    panel:AddDropdownPair({
        label = "Show Unit As",
        tooltip = "How each ally is labelled. Class Icon is the most compact (no name); Portrait shows their 2D model (class icon when off-screen); Name is text only; Icon + Name shows icon and name; Icon + Portrait shows the class icon beside the live portrait; the Specialization modes swap in the talent-tree icon once a player's spec has been learned from their casts (class icon until then).",
        options = {
            { text = "Class Icon", value = "CLASS_ICON" },
            { text = "Portrait", value = "PORTRAIT" },
            { text = "Name", value = "NAME" },
            { text = "Icon + Name", value = "ICON_NAME" },
            { text = "Icon + Portrait", value = "ICON_PORTRAIT" },
            { text = "Specialization", value = "SPEC" },
            { text = "Spec + Portrait", value = "SPEC_PORTRAIT" },
        },
        get = function() return CommanderPartyFramesDB.UnitDisplay end,
        set = function(value) CommanderPartyFramesDB.UnitDisplay = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Grow",
        tooltip = "Direction the board grows from its anchor.",
        options = {
            { text = "Down", value = "DOWN" },
            { text = "Up", value = "UP" },
        },
        get = function() return CommanderPartyFramesDB.Grow end,
        set = function(value) CommanderPartyFramesDB.Grow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckboxPair({
        label = "Spell Icon",
        tooltip = "Show the Power Word: Shield icon at the start of each row (dimmed when no shield of yours is up).",
        get = function() return CommanderPartyFramesDB.ShowSpellIcon end,
        set = function(value) CommanderPartyFramesDB.ShowSpellIcon = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Shield Duration Sweep",
        tooltip = "Draw a radial 30-second sweep over the spell icon showing the shield's remaining duration. Requires Spell Icon.",
        get = function() return CommanderPartyFramesDB.ShieldSwipe end,
        set = function(value) CommanderPartyFramesDB.ShieldSwipe = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowSpellIcon end,
    })
    panel:AddCheckboxPair({
        label = "NPC Target Counter",
        tooltip = "Show, over each unit's class icon or portrait, how many enemy NPCs are currently targeting them — white 1, amber 2, red 3+. Reads the visible enemy nameplates, so turn enemy nameplates on (default V) for full coverage; needs an icon to sit on, so it hides in Name-only display.",
        get = function() return CommanderPartyFramesDB.ShowTargeters end,
        set = function(value) CommanderPartyFramesDB.ShowTargeters = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.UnitDisplay ~= "NAME"
        end,
    }, {
        label = "Color Shield Types",
        tooltip = "Tint each embedded shield segment by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
        get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
        set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddSlider({
        label = "Name Length",
        tooltip = "Trim ally names to this many characters (keeps rows compact). Applies when Show Unit As includes a name.",
        min = 3, max = 12, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.NameMaxChars end,
        set = function(value) CommanderPartyFramesDB.NameMaxChars = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and (CommanderPartyFramesDB.UnitDisplay == "NAME" or CommanderPartyFramesDB.UnitDisplay == "ICON_NAME")
        end,
    })

    panel:AddSection("Mouseover & Click", "Turn rows into secure unit buttons: hovering feeds your @mouseover macros and each mouse button casts its bound spell. Enabling needs a /reload; uses a fixed roster order.")
    panel:AddCheckbox({
        label = "Enable Row Clicks",
        tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each mouse button casts the spell you bind below. Because secure frames can't change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
        get = function() return CommanderPartyFramesDB.ClickCast end,
        set = function(value) CommanderPartyFramesDB.ClickCast = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    local function ClickEnabled() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end
    local function BindingDropdown(label, tooltip, key)
        panel:AddDropdown({
            label = label, tooltip = tooltip, options = CLICK_SPELLS,
            get = function() return CommanderPartyFramesDB[key] end,
            set = function(value) CommanderPartyFramesDB[key] = value end,
            isEnabled = ClickEnabled,
        })
    end
    BindingDropdown("Left-Click",
        "Spell cast when you left-click an ally's row (\"bubble\" = Power Word: Shield). Choose Target to just target them, or None to free the button. Casts your highest known rank; @mouseover macros keep working too.",
        "ClickLeft")
    BindingDropdown("Right-Click", "Spell cast when you right-click an ally's row (replaces the right-click menu).", "ClickRight")
    BindingDropdown("Middle-Click", "Spell cast when you middle-click an ally's row.", "ClickMiddle")
    BindingDropdown("Modifier + Left-Click", "Spell cast when you hold the Modifier Key (below) and left-click an ally's row.", "ClickModLeft")
    panel:AddDropdown({
        label = "Modifier Key",
        tooltip = "Which held key triggers the Modifier + Left-Click binding.",
        options = CLICK_MODIFIERS,
        get = function() return CommanderPartyFramesDB.ClickModifier end,
        set = function(value) CommanderPartyFramesDB.ClickModifier = value end,
        isEnabled = ClickEnabled,
    })

    panel:AddSection("Decision Aids")
    panel:AddCheckbox({
        label = "Range Fade",
        tooltip = "Dim allies who are out of your shield range, so you only act on the ones you can actually reach. (Each row's bar is the ally's health with their absorbs embedded — always on.)",
        get = function() return CommanderPartyFramesDB.RangeFade end,
        set = function(value) CommanderPartyFramesDB.RangeFade = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckboxPair({
        label = "Reshield Glow",
        tooltip = "Softly glow any row whose reshield window is open — no shield and no Weakened Soul (or a low shield you can top off) — so the next cast jumps out.",
        get = function() return CommanderPartyFramesDB.WSReadyGlow end,
        set = function(value) CommanderPartyFramesDB.WSReadyGlow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Pin Focus",
        tooltip = "Keep your focus unit's row at the top of the board. No effect in Click-Cast mode (fixed roster order).",
        get = function() return CommanderPartyFramesDB.PinFocus end,
        set = function(value) CommanderPartyFramesDB.PinFocus = value end,
        isEnabled = SortableMode,
    })
    panel:AddCheckboxPair({
        label = "Combat Only",
        tooltip = "Only show the board while you are in combat.",
        get = function() return CommanderPartyFramesDB.CombatOnly end,
        set = function(value) CommanderPartyFramesDB.CombatOnly = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Track Uptime",
        tooltip = "Track how much of your group is carrying your shield over the session (shown in the header, detailed by /cpf report).",
        get = function() return CommanderPartyFramesDB.TrackUptime end,
        set = function(value) CommanderPartyFramesDB.TrackUptime = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckboxPair({
        label = "Expose Alert",
        tooltip = "Flash a row red the moment your shield breaks off a living ally — they need a reshield now.",
        get = function() return CommanderPartyFramesDB.ExposeAlert end,
        set = function(value) CommanderPartyFramesDB.ExposeAlert = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Expose Sound",
        tooltip = "Also play an alert sound with the expose flash.",
        get = function() return CommanderPartyFramesDB.ExposeAlertSound end,
        set = function(value) CommanderPartyFramesDB.ExposeAlertSound = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ExposeAlert end,
    })
    panel:AddSection("Dispellable Debuffs", "A strip of icons to the right of each row showing debuffs your class can remove, color-coded by school, with a glow on crowd control.")
    panel:AddCheckboxPair({
        label = "Show Dispellable Debuffs",
        tooltip = "Show, to the right of each ally's row, the debuffs your class can actually dispel — Priests see Magic and Disease, Paladins Magic/Poison/Disease, Druids Curse/Poison, Mages Curse, Shamans Poison/Disease. Each icon's rim is colored by school (blue Magic, purple Curse, brown Disease, green Poison) and carries a countdown sweep.",
        get = function() return CommanderPartyFramesDB.ShowDispels end,
        set = function(value) CommanderPartyFramesDB.ShowDispels = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "CC Glow",
        tooltip = "Pulse a bright glow behind crowd-control debuffs (Polymorph, Fear, Sap-likes, roots, stuns, Mind Control...) so the one that needs dispelling first jumps out of a busy strip.",
        get = function() return CommanderPartyFramesDB.DispelCCGlow end,
        set = function(value) CommanderPartyFramesDB.DispelCCGlow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    })
    panel:AddCheckboxPair({
        label = "Important Debuffs",
        tooltip = "Also show debuffs that matter to a healer even though you cannot dispel them: healing reductions (Mortal Strike, Aimed Shot, Wound Poison), undispellable crowd control and stuns (Blind, Sap, Gouge, Kidney Shot, Cyclone, Intimidating Shout...), and silences. These get a category-colored rim — red for healing reduction, orange for crowd control — and are sorted to the front of the strip.",
        get = function() return CommanderPartyFramesDB.DispelShowImportant end,
        set = function(value) CommanderPartyFramesDB.DispelShowImportant = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    }, {
        label = "Heal-Reduction Glow",
        tooltip = "Pulse a red glow on debuffs that cut healing received. Worth acting on: absorbs ignore Mortal Strike effects, so a shield lands at full value where a heal does not.",
        get = function() return CommanderPartyFramesDB.DispelHealGlow end,
        set = function(value) CommanderPartyFramesDB.DispelHealGlow = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels
            and CommanderPartyFramesDB.DispelShowImportant end,
    })
    panel:AddCheckboxPair({
        label = "Show All Debuffs",
        tooltip = "Also show debuffs you cannot dispel. Off (default) keeps the strip strictly actionable — only what you can actually remove.",
        get = function() return CommanderPartyFramesDB.DispelShowAll end,
        set = function(value) CommanderPartyFramesDB.DispelShowAll = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    }, {
        label = "Duration Sweep",
        tooltip = "Draw a radial countdown over each debuff icon showing how long it has left.",
        get = function() return CommanderPartyFramesDB.DispelSweep end,
        set = function(value) CommanderPartyFramesDB.DispelSweep = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    })
    panel:AddSliderPair({
        label = "Debuff Icons",
        tooltip = "How many debuff icons to show per row.",
        min = 1, max = 5, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.DispelMaxIcons end,
        set = function(value) CommanderPartyFramesDB.DispelMaxIcons = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    }, {
        label = "Debuff Icon Size",
        tooltip = "Size of each debuff icon in the strip.",
        min = 10, max = 24, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.DispelIconSize end,
        set = function(value) CommanderPartyFramesDB.DispelIconSize = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
    })

    panel:AddSection("Renew")
    panel:AddCheckboxPair({
        label = "Track Renew",
        tooltip = "Show a Renew indicator at the right of each row, pairing your other maintenance HoT with the shield board: bright with a radial sweep while your Renew ticks, a red pulse when it is about to fall off, and a dim ghost icon when it is missing — so you can keep Renew rolling on the same allies you shield.",
        get = function() return CommanderPartyFramesDB.RenewTrack end,
        set = function(value) CommanderPartyFramesDB.RenewTrack = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Renew Refresh Flash",
        tooltip = "Pulse the Renew icon when it is inside the refresh window below, so an about-to-drop Renew catches your eye. Requires Track Renew.",
        get = function() return CommanderPartyFramesDB.RenewFlash end,
        set = function(value) CommanderPartyFramesDB.RenewFlash = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.RenewTrack end,
    })
    panel:AddSlider({
        label = "Renew Refresh At",
        tooltip = "Treat your Renew as expiring when this many seconds or fewer remain (tints, and pulses if Renew Refresh Flash is on).",
        min = 1, max = 10, step = 1,
        format = function(value) return string.format("%ds", value or 0) end,
        get = function() return CommanderPartyFramesDB.RenewRefreshAt end,
        set = function(value) CommanderPartyFramesDB.RenewRefreshAt = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.RenewTrack end,
    })

    -- Chrome last, per the suite convention
    Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })

    -- Size the scroll child to the built content so the scrollbar has range
    scrollChild:SetHeight(panel._contentHeight + 24)
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_PartyFrames" then
        -- One-time repairs, keyed by a revision OUTSIDE DefaultSettings so
        -- Restore Defaults can never un-migrate. Rev 2: the rename-era
        -- default seeded SelfShieldRows=false before the default flipped on.
        if (CommanderPartyFramesDB.PFRev or 0) < 2 then
            CommanderPartyFramesDB.SelfShieldRows = true
            CommanderPartyFramesDB.PFRev = 2
        end
        Commander.UI.ApplyDefaults(CommanderPartyFramesDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

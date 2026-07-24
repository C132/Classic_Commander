CommanderReticleDB = _G.CommanderReticleDB or {}

COMMANDER_RETICLE_EVENTS = {
    UPDATE = "COMMANDER_RETICLE_UPDATE"
}

-- Named colors shared by the engine and every color dropdown on the panels.
-- A cursor-sized ring has no room for a color picker, and named colors keep
-- the module's palette consistent with the rest of the suite's art.
COMMANDER_RETICLE_COLORS = {
    GOLD    = { 1.00, 0.82, 0.25 },
    EMBER   = { 1.00, 0.35, 0.10 },
    BLOOD   = { 1.00, 0.15, 0.20 },
    ICE     = { 0.35, 0.80, 1.00 },
    VERDANT = { 0.35, 1.00, 0.45 },
    VOID    = { 0.70, 0.40, 1.00 },
    ARCANE  = { 1.00, 0.40, 1.00 },
    BONE    = { 0.95, 0.93, 0.85 },
    STEEL   = { 0.65, 0.72, 0.80 },
}

local COLOR_OPTIONS = {
    { text = "Gold", value = "GOLD" },
    { text = "Ember", value = "EMBER" },
    { text = "Blood", value = "BLOOD" },
    { text = "Ice", value = "ICE" },
    { text = "Verdant", value = "VERDANT" },
    { text = "Void", value = "VOID" },
    { text = "Arcane", value = "ARCANE" },
    { text = "Bone", value = "BONE" },
    { text = "Steel", value = "STEEL" },
}

local DefaultSettings = {
    EnableReticle = true,

    -- When the reticle is on screen at all
    ShowWhen = "CASTING_OR_UNIT",  -- ALWAYS | CASTING | CASTING_OR_UNIT | UNIT
    CombatOnly = false,
    HideMouselooking = true,       -- the pointer is hidden while turning; so is this

    -- Ring geometry. The default is deliberately cursor-sized: a 38px ring
    -- with a ~27px hole is the footprint of the arrow it stands in for.
    RingSize = 38,
    RingThickness = 5,
    Opacity = 0.95,

    -- Cast arc
    ShowCastArc = true,
    CastFill = true,               -- casts fill clockwise
    ChannelFill = false,           -- channels drain, so the two never read alike
    CastColorMode = "SCHOOL",      -- SCHOOL | CLASS | HOSTILITY | FIXED
    CastColor = "GOLD",            -- used by FIXED
    CastEdge = true,               -- bright leading edge on the sweep

    -- Center of the ring. Empty by default: every pixel drawn here is a pixel
    -- of the unit frame underneath that you cannot see.
    Aperture = "NONE",             -- NONE | ICON | TIME | HEALTH
    ApertureOpacity = 0.85,
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderReticleDB, DefaultSettings)
    Commander.Notify(COMMANDER_RETICLE_EVENTS.UPDATE)
    print("Commander Reticle: settings restored to defaults")
end

local function Enabled()
    return CommanderReticleDB.EnableReticle
end

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "Reticle",
        title = "Reticle",
        addonName = "Commander_Reticle",
        description = "Turns the mouse pointer into a cast bar. A hollow ring the size of the cursor follows the pointer and sweeps as you cast, so mouseover casting no longer parks an opaque arrow on top of the health bar you are aiming at — the middle of the ring stays empty, and the ring reports the cast where your eyes already are. See Reticle Extras for the global cooldown ring, cursor replacement, and feedback flashes.",
        event = COMMANDER_RETICLE_EVENTS.UPDATE,
        slash = { "/creticle", "/cret" },
        slashHandlers = {
            test = function() if CommanderReticle_Test then CommanderReticle_Test() end end,
        },
    })

    panel:AddCheckboxPair({
        label = "Enable Reticle",
        tooltip = "Master switch. Off leaves nothing on screen and stops the follow loop entirely.",
        get = function() return CommanderReticleDB.EnableReticle end,
        set = function(value) CommanderReticleDB.EnableReticle = value end,
    }, {
        label = "Only in Combat",
        tooltip = "Keep the reticle hidden until you are in combat.",
        get = function() return CommanderReticleDB.CombatOnly end,
        set = function(value) CommanderReticleDB.CombatOnly = value end,
        isEnabled = Enabled,
    })

    panel:AddDropdownPair({
        label = "Show When",
        tooltip = "Always keeps a ring on the pointer at all times; While Casting only appears for the length of a cast; Casting or Hovering also appears whenever the pointer is over a unit, which is the mouseover-casting case this module was built for.",
        options = {
            { text = "Casting or Hovering", value = "CASTING_OR_UNIT" },
            { text = "While Casting", value = "CASTING" },
            { text = "While Hovering", value = "UNIT" },
            { text = "Always", value = "ALWAYS" },
        },
        width = 150,
        get = function() return CommanderReticleDB.ShowWhen end,
        set = function(value) CommanderReticleDB.ShowWhen = value end,
        isEnabled = Enabled,
    }, nil)

    panel:AddSection("Ring", "The ring is drawn around the pointer's hotspot and left hollow in the middle, so it adds no occlusion of its own.")
    panel:AddSliderPair({
        label = "Ring Size",
        tooltip = "Outer diameter of the ring in pixels. The default matches the footprint of the system cursor it stands in for.",
        min = 18, max = 96, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.RingSize end,
        set = function(value) CommanderReticleDB.RingSize = value end,
        isEnabled = Enabled,
    }, {
        label = "Ring Thickness",
        tooltip = "Weight of the arc in pixels. Thin reads as a hairline at a glance; thick is easier to catch in peripheral vision.",
        min = 2, max = 14, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.RingThickness end,
        set = function(value) CommanderReticleDB.RingThickness = value end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Opacity",
        tooltip = "Overall opacity of the reticle.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderReticleDB.Opacity end,
        set = function(value) CommanderReticleDB.Opacity = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Cast Arc", "The sweep itself: how it moves, and what its color is telling you.")
    panel:AddCheckboxPair({
        label = "Show Cast Arc",
        tooltip = "Sweep the ring while you cast or channel.",
        get = function() return CommanderReticleDB.ShowCastArc end,
        set = function(value) CommanderReticleDB.ShowCastArc = value end,
        isEnabled = Enabled,
    }, {
        label = "Leading Edge",
        tooltip = "Draw a bright line at the head of the sweep — the easiest part of the ring to track out of the corner of your eye.",
        get = function() return CommanderReticleDB.CastEdge end,
        set = function(value) CommanderReticleDB.CastEdge = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowCastArc end,
    })
    panel:AddCheckboxPair({
        label = "Casts Fill",
        tooltip = "Casts sweep the ring closed as they progress. Off drains it instead.",
        get = function() return CommanderReticleDB.CastFill end,
        set = function(value) CommanderReticleDB.CastFill = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowCastArc end,
    }, {
        label = "Channels Fill",
        tooltip = "Channels sweep the ring closed too. Off (the default) drains them, so a channel never looks like a cast.",
        get = function() return CommanderReticleDB.ChannelFill end,
        set = function(value) CommanderReticleDB.ChannelFill = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowCastArc end,
    })
    panel:AddDropdownPair({
        label = "Arc Color",
        tooltip = "School colors the arc by the spell's school (Frost blue, Fire red, and so on). Hostility is the healer's read: green when the spell is landing on a friend, red when it is landing on an enemy. Class uses your class color; Fixed uses the color beside it.",
        options = {
            { text = "Spell School", value = "SCHOOL" },
            { text = "Hostility", value = "HOSTILITY" },
            { text = "Class Color", value = "CLASS" },
            { text = "Fixed", value = "FIXED" },
        },
        get = function() return CommanderReticleDB.CastColorMode end,
        set = function(value) CommanderReticleDB.CastColorMode = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowCastArc end,
    }, {
        label = "Fixed Color",
        tooltip = "The arc color used when Arc Color is set to Fixed.",
        options = COLOR_OPTIONS,
        get = function() return CommanderReticleDB.CastColor end,
        set = function(value) CommanderReticleDB.CastColor = value end,
        isEnabled = function()
            return Enabled() and CommanderReticleDB.ShowCastArc
                and CommanderReticleDB.CastColorMode == "FIXED"
        end,
    })

    panel:AddSection("Center", "What sits in the hole. Empty is the default for a reason: anything drawn here is a piece of the unit frame you can no longer see.")
    panel:AddDropdownPair({
        label = "Center Shows",
        tooltip = "Empty keeps the ring completely see-through. Spell Icon shows what you are casting, Time Left counts the cast down, and Target Health puts the hovered unit's health percentage under the pointer.",
        options = {
            { text = "Empty", value = "NONE" },
            { text = "Spell Icon", value = "ICON" },
            { text = "Time Left", value = "TIME" },
            { text = "Target Health", value = "HEALTH" },
        },
        get = function() return CommanderReticleDB.Aperture end,
        set = function(value) CommanderReticleDB.Aperture = value end,
        isEnabled = Enabled,
    }, nil)
    panel:AddSlider({
        label = "Center Opacity",
        tooltip = "How solid the center content is. Low values keep the unit frame underneath readable through it.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderReticleDB.ApertureOpacity end,
        set = function(value) CommanderReticleDB.ApertureOpacity = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.Aperture ~= "NONE" end,
    })

    panel:AddButtonRow({
        {
            label = "Test Reticle",
            width = 120,
            tooltip = "Run a two and a half second pretend cast through the reticle without casting anything (also: /creticle test).",
            onClick = function() if CommanderReticle_Test then CommanderReticle_Test() end end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so
        -- apply defaults here
        if addonName == "Commander_Reticle" then
            CommanderReticleDB = CommanderReticleDB or {}
            Commander.UI.ApplyDefaults(CommanderReticleDB, DefaultSettings)
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        CreateCorePanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

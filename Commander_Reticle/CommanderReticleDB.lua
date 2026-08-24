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

    -- Unit dial: the hovered unit's health, drawn as pips around the arc.
    -- The pointer covering a health bar stops mattering once the pointer is
    -- reporting that health bar.
    ShowUnitDial = true,
    DialSource = "SMART",          -- MOUSEOVER | TARGET | CAST_TARGET | SMART
    DialStyle = "SEGMENTED",       -- SEGMENTED (pips) | SOLID (continuous band)
    DialPlacement = "OUTSIDE",     -- OUTSIDE the arc | INSIDE the hole
    DialSegments = 20,
    DialLength = 5,
    DialWidth = 3,
    DialGap = 2,
    DialClassColor = false,        -- lit pips take class / reaction color
    DialRangeDim = true,           -- dim the dial when the unit is out of reach

    -- Smart dodge: step the ring off whatever it is hovering
    DodgeMode = "OFF",             -- OFF | AUTO | UP | DOWN | LEFT | RIGHT
    DodgeDistance = 26,

    -- Center of the ring. Empty by default: every pixel drawn here is a pixel
    -- of the unit frame underneath that you cannot see.
    Aperture = "NONE",             -- NONE | ICON | TIME | HEALTH
    ApertureOpacity = 0.85,
    ApertureIconSize = 0.85,       -- share of the hole; over 100% spills over the arc

    -- Global cooldown ring, on its own radius
    ShowGCD = false,
    GCDColor = "STEEL",
    GCDPlacement = "INSIDE",       -- INSIDE (in the hole) | OUTSIDE (past the dial)
    GCDThickness = 3,

    -- Timing markers on the arc
    ShowLatency = false,

    -- Feedback flashes
    SuccessPop = true,
    FailFlash = true,
    FailShake = false,
    PushbackFlash = true,
    ErrorFlash = false,

    -- The pointer itself. Hiding the system cursor is the literal reading of
    -- "replace the cursor": the arrow is the occluder, so it goes, and a few
    -- pixels of hotspot take its place.
    HotspotStyle = "NONE",         -- NONE | DOT | CROSS | PLUS
    HotspotSize = 10,
    HotspotColor = "BONE",
    -- Take the arrow away over the interface (a non-existent cursor path, the
    -- documented way to hide it, re-applied every frame). The engine keeps the
    -- world cursor no matter what, but unit frames are interface, so the case
    -- this module exists for is covered.
    HideSystemCursor = false,
    -- The cast shim: for the length of a cast, stand a transparent interface
    -- frame between the pointer and the world so the swap above is allowed to
    -- land there too. OFF | HOVER (motion only, clicks fall through) | FULL
    -- (real mouse input, guaranteed focus, eats world left-clicks).
    CastCursorShim = "OFF",

    -- Outside the ring
    ShowSpellName = false,
    SpellNamePlace = "BELOW",      -- BELOW | ABOVE
    SpellNameMax = 14,
    ShowComboPips = false,

    -- Motion and layering
    Smoothing = 0,                 -- 0 = locked to the pointer
    OffsetX = 0,
    OffsetY = 0,
    FadeSpeed = 14,
    Layer = "TOOLTIP",
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

-- This module's pages carry more options than the Settings canvas is tall, so
-- their rows flow into a scroll frame. AddRow is overridden on the panel
-- INSTANCE only -- the shared framework and every other module's page are
-- untouched. Same pattern as Commander_PartyFrames' extras page. Returns the
-- function to call once Finalize has added the footer.
local function MakeScrollable(panel, frameName)
    local scroll = CreateFrame("ScrollFrame", frameName, panel, "UIPanelScrollFrameTemplate")
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
    scroll:SetScript("OnSizeChanged", function(_, width) scrollChild:SetWidth(width) end)

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

    return function()
        scrollChild:SetHeight(panel._contentHeight + 24)
    end
end

local function CreateCorePanel()
    local panel = Commander.UI.NewPanel({
        key = "Reticle",
        title = "Reticle",
        addonName = "Commander_Reticle",
        description = "Turns the mouse pointer into a cast bar. A hollow ring the size of the cursor follows the pointer and sweeps as you cast, so mouseover casting no longer parks an opaque arrow on top of the health bar you are aiming at — the middle of the ring stays empty, and the ring reports the cast, the hovered unit's health, the global cooldown, and how the cast ended, all where your eyes already are.",
        event = COMMANDER_RETICLE_EVENTS.UPDATE,
        slash = { "/creticle", "/cret" },
        slashHandlers = {
            test = function() if CommanderReticle_Test then CommanderReticle_Test() end end,
            demo = function() if CommanderReticle_Demo then CommanderReticle_Demo() end end,
        },
    })
    local finishScroll = MakeScrollable(panel, "CommanderReticleCoreScroll")

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

    panel:AddSection("Unit Dial", "The hovered unit's health, drawn as pips just outside the arc. Segmented on purpose: it can never be mistaken for the sweep it surrounds. This is what makes the pointer covering a health bar stop costing you anything.")
    panel:AddCheckboxPair({
        label = "Show Unit Dial",
        tooltip = "Ring the reticle with the unit's health, so you can read it without seeing the health bar under the pointer.",
        get = function() return CommanderReticleDB.ShowUnitDial end,
        set = function(value) CommanderReticleDB.ShowUnitDial = value end,
        isEnabled = Enabled,
    }, {
        label = "Class Colored",
        tooltip = "Color the lit pips by the unit's class (or red and green by reaction, for anything that is not a player) instead of by how much health is left.",
        get = function() return CommanderReticleDB.DialClassColor end,
        set = function(value) CommanderReticleDB.DialClassColor = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    })
    panel:AddCheckboxPair({
        label = "Dim Out of Range",
        tooltip = "Fade the dial when the unit is out of reach — of the spell you are casting, or of the 40 yard party range when you are not.",
        get = function() return CommanderReticleDB.DialRangeDim end,
        set = function(value) CommanderReticleDB.DialRangeDim = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    }, nil)
    panel:AddDropdownPair({
        label = "Dial Reports On",
        tooltip = "Smart follows the pointer, falls back to whoever the current cast is aimed at, then to your target — the right answer for mouseover casting. The others pin the dial to one source. The center readout and the Hostility arc color follow this setting too.",
        options = {
            { text = "Smart", value = "SMART" },
            { text = "Mouseover", value = "MOUSEOVER" },
            { text = "Target", value = "TARGET" },
            { text = "Cast Target", value = "CAST_TARGET" },
        },
        width = 130,
        get = function() return CommanderReticleDB.DialSource end,
        set = function(value) CommanderReticleDB.DialSource = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    }, nil)
    panel:AddDropdownPair({
        label = "Dial Style",
        tooltip = "Segmented draws the health as discrete pips, which cannot be confused with the continuous cast sweep inside it. Solid closes the gaps into one band — easier to read as a level, harder to tell apart from the arc.",
        options = {
            { text = "Segmented", value = "SEGMENTED" },
            { text = "Solid", value = "SOLID" },
        },
        get = function() return CommanderReticleDB.DialStyle end,
        set = function(value) CommanderReticleDB.DialStyle = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    }, {
        label = "Dial Placement",
        tooltip = "Outside rings the cast arc. Inside tucks the dial into the hole in the middle, keeping the whole reticle inside the cursor's own footprint — smaller, but it costs you the empty center.",
        options = {
            { text = "Outside", value = "OUTSIDE" },
            { text = "Inside", value = "INSIDE" },
        },
        get = function() return CommanderReticleDB.DialPlacement end,
        set = function(value) CommanderReticleDB.DialPlacement = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    })
    panel:AddSliderPair({
        label = "Dial Segments",
        tooltip = "How many pips make up the dial. Fewer reads faster at a glance; more is finer grained.",
        min = 4, max = 36, step = 1,
        format = "%d",
        get = function() return CommanderReticleDB.DialSegments end,
        set = function(value) CommanderReticleDB.DialSegments = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    }, {
        label = "Dial Gap",
        tooltip = "Space between the cast arc and the dial.",
        min = 0, max = 12, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.DialGap end,
        set = function(value) CommanderReticleDB.DialGap = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    })
    panel:AddSliderPair({
        label = "Pip Length",
        tooltip = "How far each pip reaches outward.",
        min = 2, max = 16, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.DialLength end,
        set = function(value) CommanderReticleDB.DialLength = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    }, {
        label = "Pip Width",
        tooltip = "How wide each pip is.",
        min = 1, max = 10, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.DialWidth end,
        set = function(value) CommanderReticleDB.DialWidth = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowUnitDial end,
    })

    panel:AddSection("Smart Dodge", "For the last of the occlusion: when the pointer is over a unit, the ring can step aside so even its rim is off the frame. Your aim never moves — only the ring does.")
    panel:AddDropdown({
        label = "Dodge",
        tooltip = "Auto leaves by the nearest edge of the frame under the pointer, which is usually the shortest way off a health bar. The fixed directions always step the same way. Off keeps the ring centered on the pointer.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Auto", value = "AUTO" },
            { text = "Up", value = "UP" },
            { text = "Down", value = "DOWN" },
            { text = "Left", value = "LEFT" },
            { text = "Right", value = "RIGHT" },
        },
        get = function() return CommanderReticleDB.DodgeMode end,
        set = function(value) CommanderReticleDB.DodgeMode = value end,
        isEnabled = Enabled,
    })
    panel:AddSlider({
        label = "Dodge Distance",
        tooltip = "How far the ring steps aside — and, in Auto, the furthest it is ever allowed to travel.",
        min = 8, max = 80, step = 2,
        format = "%d px",
        get = function() return CommanderReticleDB.DodgeDistance end,
        set = function(value) CommanderReticleDB.DodgeDistance = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.DodgeMode ~= "OFF" end,
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
    panel:AddSliderPair({
        label = "Center Opacity",
        tooltip = "How solid the center content is. Low values keep the unit frame underneath readable through it.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderReticleDB.ApertureOpacity end,
        set = function(value) CommanderReticleDB.ApertureOpacity = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.Aperture ~= "NONE" end,
    }, {
        label = "Spell Icon Size",
        tooltip = "Size of the spell icon, as a share of the hole in the middle of the ring — so it keeps its proportions when you resize the reticle. At 100% it exactly fills the hole; past that it deliberately spills over the arc, for when you want the icon to be the reticle.",
        min = 0.4, max = 2, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderReticleDB.ApertureIconSize end,
        set = function(value) CommanderReticleDB.ApertureIconSize = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.Aperture == "ICON" end,
    })

    panel:AddButtonRow({
        {
            label = "Test Reticle",
            width = 120,
            tooltip = "Run a two and a half second pretend cast through the reticle without casting anything (also: /creticle test).",
            onClick = function() if CommanderReticle_Test then CommanderReticle_Test() end end,
        },
        {
            label = "Demo (20s)",
            width = 120,
            tooltip = "Hold everything on screen for twenty seconds: a looping pretend cast, a pretend target draining from full to nearly dead, and combo points cycling. Change any setting further down the page while it runs and watch it take effect — no target and no fight needed (also: /creticle demo).",
            onClick = function() if CommanderReticle_Demo then CommanderReticle_Demo() end end,
        },
    })

    panel:AddSection("Global Cooldown", "A second, thinner ring answering a different question: not how far along this cast is, but whether you can act at all yet. With this on, the reticle stays up for the length of the cooldown in the casting-only display modes.")
    panel:AddCheckbox({
        label = "Show Global Cooldown Ring",
        tooltip = "Sweep a thin ring for the global cooldown after every spell.",
        get = function() return CommanderReticleDB.ShowGCD end,
        set = function(value) CommanderReticleDB.ShowGCD = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdownPair({
        label = "Placement",
        tooltip = "Inside puts it in the hole in the middle, which costs no extra footprint; Outside puts it beyond everything else, including the unit dial.",
        options = {
            { text = "Inside", value = "INSIDE" },
            { text = "Outside", value = "OUTSIDE" },
        },
        get = function() return CommanderReticleDB.GCDPlacement end,
        set = function(value) CommanderReticleDB.GCDPlacement = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowGCD end,
    }, {
        label = "Ring Color",
        tooltip = "Color of the global cooldown sweep. Keep it away from your cast arc color so the two never read as one thing.",
        options = COLOR_OPTIONS,
        get = function() return CommanderReticleDB.GCDColor end,
        set = function(value) CommanderReticleDB.GCDColor = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowGCD end,
    })
    panel:AddSlider({
        label = "Cooldown Thickness",
        tooltip = "Weight of the global cooldown ring. Thinner than the cast arc keeps the hierarchy obvious.",
        min = 1, max = 10, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.GCDThickness end,
        set = function(value) CommanderReticleDB.GCDThickness = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowGCD end,
    })

    panel:AddSection("Timing", "Marks on the arc itself.")
    panel:AddCheckbox({
        label = "Latency Marker",
        tooltip = "Put a tick on the arc where your world latency says the next cast can already be queued — once the sweep passes it, pressing the next spell loses nothing.",
        get = function() return CommanderReticleDB.ShowLatency end,
        set = function(value) CommanderReticleDB.ShowLatency = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Feedback", "How the cast ended, said in one flash of the ring. The reticle stays visible for the length of a flash even in the casting-only display modes, so the message is never cut off.")
    panel:AddCheckboxPair({
        label = "Success Pop",
        tooltip = "Green halo when the cast lands.",
        get = function() return CommanderReticleDB.SuccessPop end,
        set = function(value) CommanderReticleDB.SuccessPop = value end,
        isEnabled = Enabled,
    }, {
        label = "Failure Flash",
        tooltip = "Red halo when the cast is interrupted or fails.",
        get = function() return CommanderReticleDB.FailFlash end,
        set = function(value) CommanderReticleDB.FailFlash = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Pushback Flash",
        tooltip = "Amber halo when a hit pushes your cast back — the arc visibly retreats at the same moment.",
        get = function() return CommanderReticleDB.PushbackFlash end,
        set = function(value) CommanderReticleDB.PushbackFlash = value end,
        isEnabled = Enabled,
    }, {
        label = "Error Flash",
        tooltip = "Flash on the cast errors that come from the game itself: out of range, out of line of sight, facing the wrong way, out of power.",
        get = function() return CommanderReticleDB.ErrorFlash end,
        set = function(value) CommanderReticleDB.ErrorFlash = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckbox({
        label = "Shake on Failure",
        tooltip = "Let a failed cast shove the ring around for a moment. Off keeps the pointer perfectly still.",
        get = function() return CommanderReticleDB.FailShake end,
        set = function(value) CommanderReticleDB.FailShake = value end,
        isEnabled = function()
            return Enabled() and (CommanderReticleDB.FailFlash or CommanderReticleDB.ErrorFlash)
        end,
    })

    panel:AddSection("The Pointer", "The arrow is the thing covering the health bar. This is where you can take it off the screen and leave a few pixels of hotspot in its place — the literal version of replacing the cursor with a cast bar.")
    panel:AddDropdownPair({
        label = "Hotspot",
        tooltip = "A small mark drawn at the exact click point, under the middle of the ring. Unlike the ring it never smooths, offsets, or dodges — it is your aim.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Dot", value = "DOT" },
            { text = "Cross", value = "CROSS" },
            { text = "Plus", value = "PLUS" },
        },
        get = function() return CommanderReticleDB.HotspotStyle end,
        set = function(value) CommanderReticleDB.HotspotStyle = value end,
        isEnabled = Enabled,
    }, {
        label = "Hotspot Color",
        tooltip = "Color of the hotspot mark. Every shape is drawn with a dark outline, so it stays readable on snow and in shadow alike.",
        options = COLOR_OPTIONS,
        get = function() return CommanderReticleDB.HotspotColor end,
        set = function(value) CommanderReticleDB.HotspotColor = value end,
        isEnabled = function()
            return Enabled() and (CommanderReticleDB.HotspotStyle ~= "NONE"
                or CommanderReticleDB.HideSystemCursor)
        end,
    })
    panel:AddSlider({
        label = "Hotspot Size",
        tooltip = "Size of the hotspot mark in pixels. Small is the point: a three pixel dot occludes nothing.",
        min = 4, max = 32, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.HotspotSize end,
        set = function(value) CommanderReticleDB.HotspotSize = value end,
        isEnabled = function()
            return Enabled() and (CommanderReticleDB.HotspotStyle ~= "NONE"
                or CommanderReticleDB.HideSystemCursor)
        end,
    })
    panel:AddCheckbox({
        label = "Hide System Cursor",
        tooltip = "Take the game's arrow away over the interface, so the hotspot is your whole pointer and nothing opaque sits on the health bar. It comes back over the 3D world — the engine locks the world cursor to whatever you are pointing at and no addon can override that — but unit frames are interface, so the case this module exists for is covered. The hotspot is forced on wherever the arrow is hidden, so you are never left with no pointer at all.",
        get = function() return CommanderReticleDB.HideSystemCursor end,
        set = function(value) CommanderReticleDB.HideSystemCursor = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Hide While Casting",
        tooltip = "The engine only locks the cursor because the pointer is over the 3D world — so for the length of a cast, put a transparent interface frame there instead, and the arrow can be taken away over the world too. Hover puts the frame in the pointer's way for hover only and leaves clicking alone; if your client will not resolve the cursor from a hover-only frame, the option quietly does nothing and you should try Full. Full takes real mouse input for the length of the cast: the hide is guaranteed, right-drag still turns the camera, but a left-click on the world is swallowed until the cast ends. Independent of Hide System Cursor, and never armed during a test cast or while something is riding on the cursor.",
        options = {
            { text = "Off", value = "OFF" },
            { text = "Hover (clicks pass through)", value = "HOVER" },
            { text = "Full (blocks world clicks)", value = "FULL" },
        },
        get = function() return CommanderReticleDB.CastCursorShim end,
        set = function(value) CommanderReticleDB.CastCursorShim = value end,
        isEnabled = Enabled,
    })

    panel:AddSection("Outside the Ring", "Two readouts that live just beyond the reticle, for when the ring itself has run out of room.")
    panel:AddCheckboxPair({
        label = "Show Spell Name",
        tooltip = "Put the name of the spell being cast under the ring, colored to match the arc. Costs screen real estate right where you are looking, which is why it is off by default.",
        get = function() return CommanderReticleDB.ShowSpellName end,
        set = function(value) CommanderReticleDB.ShowSpellName = value end,
        isEnabled = Enabled,
    }, {
        label = "Combo Points",
        tooltip = "A row of dots under the ring for your combo points, cool at one and hot at five. Rogues and cat-form Druids only.",
        get = function() return CommanderReticleDB.ShowComboPips end,
        set = function(value) CommanderReticleDB.ShowComboPips = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdownPair({
        label = "Name Position",
        tooltip = "Which side of the ring the spell name sits on. Below leaves room for the combo points when those are on.",
        options = {
            { text = "Below", value = "BELOW" },
            { text = "Above", value = "ABOVE" },
        },
        get = function() return CommanderReticleDB.SpellNamePlace end,
        set = function(value) CommanderReticleDB.SpellNamePlace = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowSpellName end,
    }, nil)
    panel:AddSlider({
        label = "Name Length",
        tooltip = "Trim the spell name to this many characters, so a long name does not stretch halfway across the screen.",
        min = 4, max = 30, step = 1,
        format = "%d",
        get = function() return CommanderReticleDB.SpellNameMax end,
        set = function(value) CommanderReticleDB.SpellNameMax = value end,
        isEnabled = function() return Enabled() and CommanderReticleDB.ShowSpellName end,
    })

    panel:AddSection("Motion", "How the ring travels, and what it draws over.")
    panel:AddSliderPair({
        label = "Smoothing",
        tooltip = "Let the ring trail the pointer instead of being welded to it. Zero is locked. The hotspot never smooths, so your aim is exact either way.",
        min = 0, max = 0.9, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderReticleDB.Smoothing end,
        set = function(value) CommanderReticleDB.Smoothing = value end,
        isEnabled = Enabled,
    }, {
        label = "Fade Speed",
        tooltip = "How quickly the reticle fades in and out.",
        min = 2, max = 30, step = 1,
        format = "%d",
        get = function() return CommanderReticleDB.FadeSpeed end,
        set = function(value) CommanderReticleDB.FadeSpeed = value end,
        isEnabled = Enabled,
    })
    panel:AddSliderPair({
        label = "Offset X",
        tooltip = "Shift the ring sideways from the pointer. A permanent version of Smart Dodge, for a fixed preference.",
        min = -60, max = 60, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.OffsetX end,
        set = function(value) CommanderReticleDB.OffsetX = value end,
        isEnabled = Enabled,
    }, {
        label = "Offset Y",
        tooltip = "Shift the ring up or down from the pointer.",
        min = -60, max = 60, step = 1,
        format = "%d px",
        get = function() return CommanderReticleDB.OffsetY end,
        set = function(value) CommanderReticleDB.OffsetY = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Layer",
        tooltip = "Which layer the reticle draws on. Tooltip is the top of the stack, which is what a cursor should be; drop it lower if you would rather tooltips and dialogs cover it.",
        options = {
            { text = "Tooltip (top)", value = "TOOLTIP" },
            { text = "Fullscreen Dialog", value = "FULLSCREEN_DIALOG" },
            { text = "Dialog", value = "DIALOG" },
            { text = "High", value = "HIGH" },
        },
        get = function() return CommanderReticleDB.Layer end,
        set = function(value) CommanderReticleDB.Layer = value end,
        isEnabled = Enabled,
    })

    panel:Finalize({ onDefaults = Reset })
    finishScroll()
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

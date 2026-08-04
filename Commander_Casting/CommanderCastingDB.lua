CommanderCastingDB = _G.CommanderCastingDB or {}

COMMANDER_CASTING_EVENTS = {
    UPDATE = "COMMANDER_CASTING_UPDATE"
}

-- ---------------------------------------------------------------------------
-- Shared palette. The portrait rings are a few pixels of arc, which leaves no
-- room for a color picker, so colors are named -- and naming them keeps the
-- module's art in step with the rest of the suite's.
-- ---------------------------------------------------------------------------

COMMANDER_CASTING_COLORS = {
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

-- ---------------------------------------------------------------------------
-- Spell school. No TBC API reports a casting spell's school, so it is parsed
-- from the spell's name. Shared here because both displays this module ships --
-- the fullscreen glow and the portrait rings -- color themselves by school, and
-- two copies of the keyword list would eventually disagree.
-- ---------------------------------------------------------------------------

-- A spell that says its own school in its name is taken at its word first,
-- because the keyword lists below are greedy across schools -- "bolt" belongs
-- to Nature, which would otherwise paint Shadow Bolt green. Failing that, the
-- keyword pass runs in table order and the first match wins.
COMMANDER_CASTING_SCHOOLS = {
    { "Frost",  { "frost", "ice", "freeze", "blizzard", "frostbolt", "cone of cold" } },
    { "Nature", { "nature", "lightning", "wrath", "bolt", "starfire", "hurricane", "tranquility", "healing", "touch" } },
    { "Holy",   { "holy", "light", "heal", "smite", "flash", "prayer", "resurrection", "exorcism", "consecration" } },
    { "Fire",   { "fire", "flame", "immolate", "scorch", "pyroblast", "blast wave", "flamestrike", "searing", "incinerate" } },
    { "Shadow", { "shadow", "mind", "psychic", "flay", "blast", "mana burn", "devouring plague" } },
    { "Arcane", { "arcane", "mana", "magic", "polymorph", "missiles", "explosion", "conjure", "evocation", "counterspell" } },
}

local schoolCache = {}

-- Returns "Frost" / "Nature" / "Holy" / "Fire" / "Shadow" / "Arcane", or
-- "Unknown". Memoized: this sits on a cast-start path that can fire several
-- times a second, and the answer for a given spell never changes.
function CommanderCasting_SchoolOf(spellName)
    if not spellName then return "Unknown" end
    local cached = schoolCache[spellName]
    if cached then return cached end
    local lowered = spellName:lower()
    local found = "Unknown"
    for i = 1, #COMMANDER_CASTING_SCHOOLS do
        if lowered:find(COMMANDER_CASTING_SCHOOLS[i][1]:lower(), 1, true) then
            found = COMMANDER_CASTING_SCHOOLS[i][1]
            break
        end
    end
    if found == "Unknown" then
        for i = 1, #COMMANDER_CASTING_SCHOOLS do
            local entry = COMMANDER_CASTING_SCHOOLS[i]
            local keywords = entry[2]
            for k = 1, #keywords do
                if lowered:find(keywords[k], 1, true) then
                    found = entry[1]
                    break
                end
            end
            if found ~= "Unknown" then break end
        end
    end
    schoolCache[spellName] = found
    return found
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local TEXTURE_PATH = "Interface\\AddOns\\Commander_Casting\\Textures\\"
local TEXTURE_FILES = {
    "Glow1.png",
    "Glow2.png",
    "Glow3.png",
    "Glow4.png",
    "Glow5.png",
    "Glow6.png",
    "Glow7.png",
}

local DefaultSettings = {
    ShowFullscreenEffect = true,
    ColorBySpellSchool = true,
    EffectIntensity = 0.5,
    EffectTexture = TEXTURE_PATH .. TEXTURE_FILES[1],

    -- Portrait rings: the cast drawn as an arc around the trim of a unit
    -- frame's portrait, so the cast bar lives on the face it belongs to.
    EnablePortraitRings = true,

    -- Your own portrait
    PlayerRingEnabled = true,
    PlayerRingShowWhen = "CASTING",     -- CASTING | ALWAYS (empty track always up)
    PlayerRingScale = 1.14,             -- ring diameter as a share of the portrait
    PlayerRingThickness = 5,
    PlayerRingOffsetX = 0,
    PlayerRingOffsetY = 0,
    PlayerRingOpacity = 1,
    PlayerRingColorMode = "SCHOOL",     -- SCHOOL | CLASS | FIXED
    PlayerRingColor = "GOLD",
    PlayerRingCastFill = true,          -- casts fill clockwise
    PlayerRingChannelFill = false,      -- channels drain, so the two never read alike
    PlayerRingEdge = true,              -- bright leading edge on the sweep
    PlayerRingTrack = true,             -- dim full circle behind the arc
    PlayerRingTrackOpacity = 0.25,
    PlayerRingTint = false,             -- wash the portrait in the cast's color
    PlayerRingTintStrength = 0.25,
    PlayerRingText = "NONE",            -- NONE | TIME | NAME
    PlayerRingTextPlace = "BELOW",      -- CENTER | ABOVE | BELOW
    PlayerRingTextSize = 12,
    PlayerRingLatency = false,          -- tick where the next cast can be queued
    PlayerRingGCD = false,
    PlayerRingGCDColor = "STEEL",
    PlayerRingGCDPlacement = "INSIDE",  -- INSIDE the arc | OUTSIDE it
    PlayerRingGCDThickness = 3,
    PlayerRingSuccessFlash = true,
    PlayerRingFailFlash = true,
    PlayerRingPushbackFlash = true,

    -- Your target's portrait
    TargetRingEnabled = true,
    TargetRingShowWhen = "CASTING",
    TargetRingScale = 1.14,
    TargetRingThickness = 5,
    TargetRingOffsetX = 0,
    TargetRingOffsetY = 0,
    TargetRingOpacity = 1,
    TargetRingColorMode = "SCHOOL",     -- SCHOOL | CLASS | REACTION | FIXED
    TargetRingColor = "EMBER",
    TargetRingCastFill = true,
    TargetRingChannelFill = false,
    TargetRingEdge = true,
    TargetRingTrack = true,
    TargetRingTrackOpacity = 0.25,
    TargetRingTint = false,
    TargetRingTintStrength = 0.25,
    TargetRingText = "TIME",            -- what is left to kick, on the face casting it
    TargetRingTextPlace = "BELOW",
    TargetRingTextSize = 12,
    TargetRingSuccessFlash = false,
    TargetRingFailFlash = true,         -- their cast died: that is worth a flash
    TargetRingPushbackFlash = false,

    -- The bars the rings replace
    HidePlayerCastBar = false,
    HideTargetCastBar = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderCastingDB, DefaultSettings)
    Commander.Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    print("Commander Casting: settings restored to defaults")
end

local function GetTextureDisplayName(filename)
    return filename:gsub("%.png$", "")
end

local function BuildTextureOptions()
    local options = {}
    for _, filename in ipairs(TEXTURE_FILES) do
        options[#options + 1] = {
            text = GetTextureDisplayName(filename),
            value = TEXTURE_PATH .. filename,
        }
    end
    return options
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Casting",
        title = "Casting",
        addonName = "Commander_Casting",
        description = "Wraps the screen in a rising glow while you cast: the edges of the world brighten as the cast completes, so you can track progress without staring at a cast bar. The companion page, Casting Rings, puts the cast around the trim of the portraits instead.",
        event = COMMANDER_CASTING_EVENTS.UPDATE,
        slash = { "/ccast" },
        slashHandlers = {
            test = function()
                if CommanderCasting_Test then CommanderCasting_Test() end
            end,
        },
    })

    panel:AddSection("Fullscreen Effect", "The glow builds from nothing to full intensity across the length of the cast.")
    panel:AddCheckbox({
        label = "Show Fullscreen Casting Effect",
        tooltip = "Enable the glow effect while casting or channeling.",
        get = function() return CommanderCastingDB.ShowFullscreenEffect end,
        set = function(value) CommanderCastingDB.ShowFullscreenEffect = value end,
    })
    panel:AddCheckbox({
        label = "Color Effect by Spell School",
        tooltip = "Tint the glow to match the school of the spell being cast: blue for Frost, red for Fire, purple for Shadow, and so on.",
        get = function() return CommanderCastingDB.ColorBySpellSchool end,
        set = function(value) CommanderCastingDB.ColorBySpellSchool = value end,
        isEnabled = function() return CommanderCastingDB.ShowFullscreenEffect end,
    })
    panel:AddSlider({
        label = "Effect Intensity",
        tooltip = "Maximum brightness the glow reaches as the cast completes.",
        min = 0, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderCastingDB.EffectIntensity end,
        set = function(value) CommanderCastingDB.EffectIntensity = value end,
        isEnabled = function() return CommanderCastingDB.ShowFullscreenEffect end,
    })

    panel:AddSection("Effect Texture", "Choose the glow's shape; the preview beside the menu shows the selected texture.")
    local dropdown = panel:AddDropdown({
        label = "Glow Texture",
        tooltip = "The texture used for the fullscreen glow. The preview to the right shows the selected texture.",
        options = BuildTextureOptions(),
        width = 160,
        get = function() return CommanderCastingDB.EffectTexture end,
        set = function(value) CommanderCastingDB.EffectTexture = value end,
        isEnabled = function() return CommanderCastingDB.ShowFullscreenEffect end,
    })

    -- Live preview of the selected glow texture, anchored beside the dropdown
    local previewFrame = CreateFrame("Frame", nil, panel)
    previewFrame:SetSize(64, 64)
    previewFrame:SetPoint("LEFT", dropdown, "RIGHT", 24, 8)

    local previewBackground = previewFrame:CreateTexture(nil, "BACKGROUND")
    previewBackground:SetAllPoints()
    previewBackground:SetColorTexture(0, 0, 0, 0.6)

    local texturePreview = previewFrame:CreateTexture(nil, "ARTWORK")
    texturePreview:SetPoint("TOPLEFT", 2, -2)
    texturePreview:SetPoint("BOTTOMRIGHT", -2, 2)
    texturePreview:SetBlendMode("ADD")

    panel:AddRefresher(function()
        texturePreview:SetTexture(CommanderCastingDB.EffectTexture)
        previewFrame:SetAlpha(CommanderCastingDB.ShowFullscreenEffect and 1 or 0.4)
    end)

    panel:AddButtonRow({
        {
            label = "Test Glow",
            width = 110,
            tooltip = "Preview the casting glow without casting: a three-second ramp, cycling a school color per press when school coloring is on (also: /ccast test).",
            onClick = function()
                if CommanderCasting_Test then CommanderCasting_Test() end
            end,
        },
        {
            label = "Ring Settings",
            width = 130,
            tooltip = "Jump to the Casting Rings page: the radial cast bars drawn around the player and target portraits.",
            onClick = function()
                if Commander.OpenModuleSettings then
                    Commander.OpenModuleSettings("CastingRings")
                end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

-- ---------------------------------------------------------------------------
-- Casting Rings page
-- ---------------------------------------------------------------------------

-- This page carries two full ring configurations and is far taller than the
-- Settings canvas, so its rows flow into a scroll frame. NewPanel's header
-- stays fixed above; AddRow is overridden on THIS panel instance only, so the
-- shared framework (and every other module's page) is untouched. Same pattern
-- as Commander_PartyFrames and Commander_Reticle. Returns the function to call
-- once Finalize has added the footer.
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

local function RingsOn()
    return CommanderCastingDB.EnablePortraitRings
end

-- Both rings offer the same controls, so they are built from one description
-- keyed by the setting prefix -- there is no way for the two halves of the page
-- to drift apart, and a new option lands on both at once.
local function AddRingOptions(panel, prefix, opts)
    local function Get(key) return CommanderCastingDB[prefix .. key] end
    local function Set(key) return function(value) CommanderCastingDB[prefix .. key] = value end end
    local function On() return RingsOn() and Get("Enabled") end

    panel:AddCheckboxPair({
        label = "Show " .. opts.label .. " Ring",
        tooltip = opts.enableTooltip,
        get = function() return Get("Enabled") end,
        set = Set("Enabled"),
        isEnabled = RingsOn,
    }, {
        label = "Empty Track",
        tooltip = "Draw the full circle dimly behind the arc, so the sweep reads against something instead of hanging in space.",
        get = function() return Get("Track") end,
        set = Set("Track"),
        isEnabled = On,
    })

    panel:AddDropdownPair({
        label = "Show When",
        tooltip = "While Casting keeps the portrait clean until something is actually being cast. Always leaves the empty track around the portrait at all times, so the ring reads as part of the frame.",
        options = {
            { text = "While Casting", value = "CASTING" },
            { text = "Always", value = "ALWAYS" },
        },
        width = 130,
        get = function() return Get("ShowWhen") end,
        set = Set("ShowWhen"),
        isEnabled = On,
    }, {
        label = "Arc Color",
        tooltip = opts.colorTooltip,
        options = opts.colorModes,
        width = 130,
        get = function() return Get("ColorMode") end,
        set = Set("ColorMode"),
        isEnabled = On,
    })

    panel:AddDropdownPair({
        label = "Fixed Color",
        tooltip = "The color used when Arc Color is set to Fixed.",
        options = COLOR_OPTIONS,
        width = 130,
        get = function() return Get("Color") end,
        set = Set("Color"),
        isEnabled = function() return On() and Get("ColorMode") == "FIXED" end,
    }, nil)

    panel:AddSliderPair({
        label = "Ring Size",
        tooltip = "Diameter of the ring as a share of the portrait. At 100% the arc sits on the portrait's own edge; larger values ride the frame's metal trim.",
        min = 0.7, max = 2, step = 0.02,
        format = Commander.UI.FormatPercent,
        get = function() return Get("Scale") end,
        set = Set("Scale"),
        isEnabled = On,
    }, {
        label = "Ring Thickness",
        tooltip = "Weight of the arc in pixels. Thin reads as a hairline up close; thick is what you catch out of the corner of your eye.",
        min = 2, max = 16, step = 1,
        format = "%d px",
        get = function() return Get("Thickness") end,
        set = Set("Thickness"),
        isEnabled = On,
    })

    panel:AddSliderPair({
        label = "Horizontal Offset",
        tooltip = "Nudge the ring sideways from the portrait's center.",
        min = -30, max = 30, step = 1,
        format = "%d px",
        get = function() return Get("OffsetX") end,
        set = Set("OffsetX"),
        isEnabled = On,
    }, {
        label = "Vertical Offset",
        tooltip = "Nudge the ring up or down from the portrait's center.",
        min = -30, max = 30, step = 1,
        format = "%d px",
        get = function() return Get("OffsetY") end,
        set = Set("OffsetY"),
        isEnabled = On,
    })

    panel:AddSliderPair({
        label = "Ring Opacity",
        tooltip = "Overall opacity of the whole ring assembly.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return Get("Opacity") end,
        set = Set("Opacity"),
        isEnabled = On,
    }, {
        label = "Track Opacity",
        tooltip = "How visible the empty track is behind the arc.",
        min = 0.05, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return Get("TrackOpacity") end,
        set = Set("TrackOpacity"),
        isEnabled = function() return On() and Get("Track") end,
    })

    panel:AddCheckboxPair({
        label = "Casts Fill Clockwise",
        tooltip = "On, a cast grows from nothing to a full circle. Off, it starts full and unwinds like a cooldown.",
        get = function() return Get("CastFill") end,
        set = Set("CastFill"),
        isEnabled = On,
    }, {
        label = "Channels Fill Clockwise",
        tooltip = "Channels default to the opposite of casts, so a drain and a cast can never be mistaken for one another at a glance.",
        get = function() return Get("ChannelFill") end,
        set = Set("ChannelFill"),
        isEnabled = On,
    })

    panel:AddCheckboxPair({
        label = "Leading Edge",
        tooltip = "Draw a bright line at the head of the sweep — the radial equivalent of a cast bar's spark.",
        get = function() return Get("Edge") end,
        set = Set("Edge"),
        isEnabled = On,
    }, {
        label = "Tint Portrait",
        tooltip = "Wash the portrait itself in the arc's color while the cast runs, so the face carries the school too.",
        get = function() return Get("Tint") end,
        set = Set("Tint"),
        isEnabled = On,
    })

    panel:AddSliderPair({
        label = "Tint Strength",
        tooltip = "How strongly the portrait takes the cast's color.",
        min = 0.05, max = 0.8, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return Get("TintStrength") end,
        set = Set("TintStrength"),
        isEnabled = function() return On() and Get("Tint") end,
    }, {
        label = "Text Size",
        tooltip = "Font size of the label beside the ring.",
        min = 8, max = 20, step = 1,
        format = "%d pt",
        get = function() return Get("TextSize") end,
        set = Set("TextSize"),
        isEnabled = function() return On() and Get("Text") ~= "NONE" end,
    })

    panel:AddDropdownPair({
        label = "Label",
        tooltip = "What to write beside the ring: nothing, the seconds left on the cast, or the spell's name.",
        options = {
            { text = "None", value = "NONE" },
            { text = "Time Left", value = "TIME" },
            { text = "Spell Name", value = "NAME" },
        },
        width = 130,
        get = function() return Get("Text") end,
        set = Set("Text"),
        isEnabled = On,
    }, {
        label = "Label Position",
        tooltip = "Where the label sits. Center puts it over the portrait, which is the most readable and the most occluding.",
        options = {
            { text = "Below", value = "BELOW" },
            { text = "Above", value = "ABOVE" },
            { text = "Center", value = "CENTER" },
        },
        width = 130,
        get = function() return Get("TextPlace") end,
        set = Set("TextPlace"),
        isEnabled = function() return On() and Get("Text") ~= "NONE" end,
    })

    panel:AddCheckboxPair({
        label = "Flash on Success",
        tooltip = opts.successTooltip,
        get = function() return Get("SuccessFlash") end,
        set = Set("SuccessFlash"),
        isEnabled = On,
    }, {
        label = "Flash on Interrupt",
        tooltip = opts.failTooltip,
        get = function() return Get("FailFlash") end,
        set = Set("FailFlash"),
        isEnabled = On,
    })

    panel:AddCheckboxPair({
        label = "Flash on Pushback",
        tooltip = "Flash amber when damage pushes the cast back and the arc retreats.",
        get = function() return Get("PushbackFlash") end,
        set = Set("PushbackFlash"),
        isEnabled = On,
    }, nil)
end

local function CreateRingsPanel()
    local panel = Commander.UI.NewPanel({
        key = "CastingRings",
        title = "Casting Rings",
        addonName = "Commander_Casting",
        description = "Puts the cast where the cast belongs: an arc sweeping around the trim of the portrait, on your own frame and on your target's. Your eyes stay on the unit instead of dropping to a bar at the bottom of the screen — and since the arc rides the portrait's rim, it costs no new screen real estate. Color by spell school, fill or unwind, label it with the seconds left, and switch the original Blizzard cast bars off entirely at the bottom of this page.",
        event = COMMANDER_CASTING_EVENTS.UPDATE,
        slash = { "/cring", "/crings" },
        slashHandlers = {
            test = function()
                if CommanderCasting_TestRings then CommanderCasting_TestRings() end
            end,
        },
    })
    local finishScroll = MakeScrollable(panel, "CommanderCastingRingsScroll")

    panel:AddCheckbox({
        label = "Enable Portrait Rings",
        tooltip = "Master switch for both rings. Off removes them entirely and stops all of their work; the Blizzard cast bars are left exactly as this page's last section set them.",
        get = function() return CommanderCastingDB.EnablePortraitRings end,
        set = function(value) CommanderCastingDB.EnablePortraitRings = value end,
    })

    panel:AddButtonRow({
        {
            label = "Test Rings",
            width = 110,
            tooltip = "Run a three-second pretend cast on both rings so every option on this page can be judged without waiting for a real one (also: /cring test). The target ring needs a target to draw on.",
            onClick = function()
                if CommanderCasting_TestRings then CommanderCasting_TestRings() end
            end,
        },
    })

    panel:AddSection("Player Ring", "The arc around your own portrait. It reports what you are casting and how far along it is.")
    AddRingOptions(panel, "PlayerRing", {
        label = "Player",
        enableTooltip = "Draw the cast arc around your own portrait.",
        colorTooltip = "Spell School colors the arc by what you are casting (Frost blue, Fire red, Shadow purple...). Class uses your class color. Fixed uses the color chosen below.",
        colorModes = {
            { text = "Spell School", value = "SCHOOL" },
            { text = "Class Color", value = "CLASS" },
            { text = "Fixed", value = "FIXED" },
        },
        successTooltip = "Flash green around the portrait when a cast lands. Instants and channels are excluded — only casts that had an arc to finish.",
        failTooltip = "Flash red when a cast is interrupted or fails.",
    })

    panel:AddSection("Player Extras", "Two more channels the player's ring can carry, each on its own radius so they never read as the same thing as the cast.")
    panel:AddCheckboxPair({
        label = "Show Latency Tick",
        tooltip = "Mark the point on the arc where the next cast can already be queued, taken from your world latency (GetNetStats). Casts only — a channel has no queue window.",
        get = function() return CommanderCastingDB.PlayerRingLatency end,
        set = function(value) CommanderCastingDB.PlayerRingLatency = value end,
        isEnabled = function() return RingsOn() and CommanderCastingDB.PlayerRingEnabled end,
    }, {
        label = "Show Global Cooldown Ring",
        tooltip = "A second, thinner ring answering a different question: not how far along this cast is, but whether you can act at all yet.",
        get = function() return CommanderCastingDB.PlayerRingGCD end,
        set = function(value) CommanderCastingDB.PlayerRingGCD = value end,
        isEnabled = function() return RingsOn() and CommanderCastingDB.PlayerRingEnabled end,
    })

    local function GCDOn()
        return RingsOn() and CommanderCastingDB.PlayerRingEnabled and CommanderCastingDB.PlayerRingGCD
    end

    panel:AddDropdownPair({
        label = "Cooldown Ring Color",
        tooltip = "Color of the global cooldown ring. Keep it plain: it is a background question, not the headline.",
        options = COLOR_OPTIONS,
        width = 130,
        get = function() return CommanderCastingDB.PlayerRingGCDColor end,
        set = function(value) CommanderCastingDB.PlayerRingGCDColor = value end,
        isEnabled = GCDOn,
    }, {
        label = "Cooldown Ring Place",
        tooltip = "Inside tucks the cooldown ring within the cast arc, over the portrait's edge; Outside puts it beyond the arc, on the frame's trim.",
        options = {
            { text = "Inside", value = "INSIDE" },
            { text = "Outside", value = "OUTSIDE" },
        },
        width = 130,
        get = function() return CommanderCastingDB.PlayerRingGCDPlacement end,
        set = function(value) CommanderCastingDB.PlayerRingGCDPlacement = value end,
        isEnabled = GCDOn,
    })

    panel:AddSlider({
        label = "Cooldown Ring Thickness",
        tooltip = "Weight of the global cooldown ring in pixels. Keep it thinner than the cast arc so the two never compete.",
        min = 1, max = 10, step = 1,
        format = "%d px",
        get = function() return CommanderCastingDB.PlayerRingGCDThickness end,
        set = function(value) CommanderCastingDB.PlayerRingGCDThickness = value end,
        isEnabled = GCDOn,
    })

    panel:AddSection("Target Ring", "The arc around your target's portrait. This is the one that matters for interrupts: the cast you need to kick, drawn on the face casting it.")
    AddRingOptions(panel, "TargetRing", {
        label = "Target",
        enableTooltip = "Draw your target's cast arc around their portrait.",
        colorTooltip = "Spell School colors the arc by what they are casting. Reaction is red for anything you can attack and green for anything friendly. Class uses their class color (players only; anything else falls back to reaction). Fixed uses the color chosen below.",
        colorModes = {
            { text = "Spell School", value = "SCHOOL" },
            { text = "Reaction", value = "REACTION" },
            { text = "Class Color", value = "CLASS" },
            { text = "Fixed", value = "FIXED" },
        },
        successTooltip = "Flash green when your target's cast completes. Off by default — a landed enemy cast is rarely worth celebrating.",
        failTooltip = "Flash red when your target's cast is interrupted. This is the kick landing, confirmed on their portrait.",
    })

    panel:AddSection("Original Cast Bars", "With the rings carrying the cast, Blizzard's own bars are duplicate information taking up the middle of the screen.")
    panel:AddCheckboxPair({
        label = "Hide Blizzard Player Cast Bar",
        tooltip = "Hide the default cast bar (and the centered overlay version) while you cast. Turning this back off returns the bar on your next cast.",
        get = function() return CommanderCastingDB.HidePlayerCastBar end,
        set = function(value) CommanderCastingDB.HidePlayerCastBar = value end,
    }, {
        label = "Hide Blizzard Target Cast Bar",
        tooltip = "Hide the cast bar that appears under the target frame. Turning this back off returns the bar on your target's next cast.",
        get = function() return CommanderCastingDB.HideTargetCastBar end,
        set = function(value) CommanderCastingDB.HideTargetCastBar = value end,
    })

    panel:Finalize({ onDefaults = Reset })
    finishScroll()
end

local function OnAwake()
    CreateOptionsPanel()
    CreateRingsPanel()
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        if addonName == "Commander_Casting" then
            CommanderCastingDB = CommanderCastingDB or {}
            Commander.UI.ApplyDefaults(CommanderCastingDB, DefaultSettings)
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
    end
end

frame:SetScript("OnEvent", OnEvent)

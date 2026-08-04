CommanderBuffsDB = _G.CommanderBuffsDB or {}

COMMANDER_BUFFS_EVENTS = {
    UPDATE = "COMMANDER_BUFFS_UPDATE"
}

-- ---------------------------------------------------------------------------
-- Schema versioning (the Meters ladder). v1 was a DIFFERENT module wearing
-- this name — the 2026-07-06 retired addon that made Blizzard's buff frame
-- draggable. Its keys describe a feature that no longer exists, so the first
-- migration clears them instead of leaving dead weight in the file forever.
-- ---------------------------------------------------------------------------

local DB_VERSION = 2
local MIGRATIONS = {
    [1] = function(db)
        for _, key in ipairs({ "BuffScale", "LockBuffFrames", "BuffFramePoint",
            "BuffFrameX", "BuffFrameY", "ShowAnchorInCombat", "BuffsPerRow" }) do
            db[key] = nil
        end
    end,
}

local function Migrate(db)
    -- A file with no version that already carries settings is the retired
    -- module's; a genuinely empty file is a fresh install and starts current.
    local v = tonumber(db.DBVersion)
    if not v then
        v = next(db) ~= nil and 1 or DB_VERSION
    end
    while v < DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
    end
    db.DBVersion = DB_VERSION
end

-- Rules are deliberately NOT in DefaultSettings: hand-authored priority
-- rules are prized state (the Orders rally-point / Quartermaster watchlist
-- precedent), so Restore Defaults can never destroy them. The editor has its
-- own explicit Restore Default Rules button.
local DefaultSettings = {
    EnableBuffs = true,

    -- The block
    EnableBlock = true,
    HideDefaultAuras = true,
    HideTempEnchants = false,
    BuffsOnTopMode = "MIRROR_TARGET",  -- MIRROR_TARGET | ON | OFF
    Placement = "BELOW",               -- BELOW | ABOVE the player frame
    GrowLeft = false,
    IconsPerRow = 8,
    BuffSize = 21,                     -- the client's own LARGE_AURA_SIZE
    DebuffSize = 21,
    IconGap = 3,                       -- the client's own AURA_OFFSET_Y
    OffsetX = 8,
    OffsetY = -4,
    ShowTimers = true,
    IconSweep = false,
    MineRim = true,
    RoundBlockIcons = false,
    BlockOpacity = 1,
    BlockFilter = "ALL",               -- ALL | RULES | SCORED
    RightClickCancel = true,

    -- The portrait sentinel
    EnablePortrait = true,
    Slots = 1,
    PortraitSize = 26,
    PortraitAnchor = "CENTER",         -- CENTER | TOP | BOTTOM | LEFT | RIGHT
    PortraitX = 0,
    PortraitY = 0,
    SlotSpacing = 3,
    SweepStyle = "RING",               -- RING | WEDGE
    RoundSentinel = true,              -- circular alpha mask on the icon
    PortraitOpacity = 1,
    PortraitStacks = true,
    PortraitTimer = false,
    PulseUnder = 3,
    MinScore = 40,
    FallbackMode = "IGNORE",           -- IGNORE | DEBUFFS | ALL

    -- Editor window chrome
    EditorStyle = "WINDOW",
    EditorScale = 1,
    EditorPos = false,
}

CommanderBuffs_DefaultSettings = DefaultSettings

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderBuffsDB, DefaultSettings)
    Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
    print("Commander Buffs: settings restored to defaults (priority rules kept)")
end

local function Enabled()
    return CommanderBuffsDB.EnableBuffs
end

local function BlockOn()
    return CommanderBuffsDB.EnableBuffs and CommanderBuffsDB.EnableBlock
end

local function PortraitOn()
    return CommanderBuffsDB.EnableBuffs and CommanderBuffsDB.EnablePortrait
end

-- This page is far past the Settings canvas, so its rows flow into a scroll
-- frame — AddRow overridden on the panel INSTANCE only (the Reticle /
-- Quartermaster / Meters pattern).
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

local function CreatePanel()
    local panel = Commander.UI.NewPanel({
        key = "Buffs",
        title = "Buffs",
        addonName = "Commander_Buffs",
        description = "Your buffs and debuffs move to your unit frame and wear the TARGET frame's layout — the same tight grid, the same dispel-school rims — with Blizzard's own buff frame hidden. On the portrait, a priority engine picks the one aura that matters this second and draws it with a radial duration ring. Open the editor to shape that policy: /cbuffs.",
        event = COMMANDER_BUFFS_EVENTS.UPDATE,
        slash = { "/cbuffs", "/cbuff" },
        slashHandlers = {
            [""] = function()
                if CommanderBuffs_ToggleEditor then CommanderBuffs_ToggleEditor() end
            end,
            editor = function()
                if CommanderBuffs_ToggleEditor then CommanderBuffs_ToggleEditor() end
            end,
            test = function()
                if CommanderBuffs_Test then CommanderBuffs_Test() end
            end,
        },
    })
    local finishScroll = MakeScrollable(panel, "CommanderBuffsPanelScroll")

    panel:AddSection("Buffs")

    panel:AddCheckbox({
        label = "Enable Buffs",
        tooltip = "Master switch. Off restores Blizzard's own buff frame and removes both the block and the portrait sentinel.",
        get = function() return CommanderBuffsDB.EnableBuffs end,
        set = function(value) CommanderBuffsDB.EnableBuffs = value end,
    })

    panel:AddButtonRow({
        {
            label = "Open Rule Editor",
            tooltip = "The priority editor: the ordered rule list, an inspector for every field, and a live trace showing what each of your CURRENT auras scores and which rule claimed it. Same as /cbuffs.",
            onClick = function()
                if CommanderBuffs_ToggleEditor then CommanderBuffs_ToggleEditor() end
            end,
        },
        {
            label = "Test Stack",
            tooltip = "Seed a fake aura stack for 15 seconds — a mix of buffs, debuffs of every school, a stacking debuff, and one about to expire — so you can see the block and the sentinel without a fight. Same as /cbuffs test.",
            onClick = function()
                if CommanderBuffs_Test then CommanderBuffs_Test() end
            end,
        },
    })

    panel:AddSection("The Block",
        "Player auras drawn beside the player unit frame in the target frame's layout language: a wrapping grid of small icons, debuffs rimmed by dispel school.")

    panel:AddCheckboxPair({
        label = "Show Block",
        tooltip = "Draw the aura block next to the player frame.",
        get = function() return CommanderBuffsDB.EnableBlock end,
        set = function(value) CommanderBuffsDB.EnableBlock = value end,
        isEnabled = Enabled,
    }, {
        label = "Hide Default Auras",
        tooltip = "Hide Blizzard's buff and debuff frames, since the block replaces them. Only honored while the block is on, so this can never leave you with no auras at all. Hiding waits until you leave combat.",
        get = function() return CommanderBuffsDB.HideDefaultAuras end,
        set = function(value) CommanderBuffsDB.HideDefaultAuras = value end,
        isEnabled = BlockOn,
    })

    panel:AddCheckboxPair({
        label = "Hide Weapon Enchants",
        tooltip = "Also hide the temporary weapon-enchant icons (poisons, sharpening stones, shaman imbues). The block does not render them, so this is off by default — turning it on means giving them up.",
        get = function() return CommanderBuffsDB.HideTempEnchants end,
        set = function(value) CommanderBuffsDB.HideTempEnchants = value end,
        isEnabled = BlockOn,
    }, {
        label = "Right-Click to Cancel",
        tooltip = "Right-click a buff in the block to cancel it. Best effort only: the block is insecure by design (a secure aura button could not re-lay-out in combat), and this client may refuse the cancel from addon code — a refusal is a silent no-op, and Blizzard's own frames remain the supported way to cancel.",
        get = function() return CommanderBuffsDB.RightClickCancel end,
        set = function(value) CommanderBuffsDB.RightClickCancel = value end,
        isEnabled = BlockOn,
    })

    panel:AddDropdown({
        label = "Buffs On Top",
        tooltip = "Which group sits above the other — the same property Edit Mode puts on the target frame. Mirror Target reads the target frame's live setting and follows it, so both frames read the same way without setting it twice. If the client will not answer, mirroring falls back to buffs on the bottom and the note under this dropdown says so.",
        options = {
            { text = "Mirror Target", value = "MIRROR_TARGET" },
            { text = "Buffs On Top", value = "ON" },
            { text = "Debuffs On Top", value = "OFF" },
        },
        get = function() return CommanderBuffsDB.BuffsOnTopMode end,
        set = function(value) CommanderBuffsDB.BuffsOnTopMode = value end,
        isEnabled = BlockOn,
    })

    do
        local row = panel:AddRow(14, 2)
        local note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        note:SetPoint("LEFT", row, "LEFT", 4, 0)
        panel:AddRefresher(function()
            if CommanderBuffsDB.BuffsOnTopMode ~= "MIRROR_TARGET" then
                note:SetText("")
                return
            end
            if CommanderBuffs_MirrorAvailable and CommanderBuffs_MirrorAvailable() then
                local on = CommanderBuffs_BuffsOnTop and CommanderBuffs_BuffsOnTop()
                note:SetText("Target frame currently says: buffs on " .. (on and "top" or "bottom") .. ".")
            else
                note:SetText("Target frame is not answering — mirroring is showing debuffs on top.")
            end
        end)
    end

    panel:AddDropdownPair({
        label = "Placement",
        tooltip = "Whether the block hangs below the player frame or sits above it. Rows always grow away from the frame.",
        options = {
            { text = "Below Frame", value = "BELOW" },
            { text = "Above Frame", value = "ABOVE" },
        },
        get = function() return CommanderBuffsDB.Placement end,
        set = function(value) CommanderBuffsDB.Placement = value end,
        isEnabled = BlockOn,
    }, {
        label = "Block Contents",
        tooltip = "Everything shows the whole stack in the client's own order — the faithful mirror of the default frames. Rules Applied borrows only the priority policy's HIDE rules, so what you told the sentinel to ignore leaves the block too. By Priority additionally sorts the block most-interesting-first.",
        options = {
            { text = "Everything", value = "ALL" },
            { text = "Rules Applied", value = "RULES" },
            { text = "By Priority", value = "SCORED" },
        },
        get = function() return CommanderBuffsDB.BlockFilter end,
        set = function(value) CommanderBuffsDB.BlockFilter = value end,
        isEnabled = BlockOn,
    })

    panel:AddCheckboxPair({
        label = "Grow Left",
        tooltip = "Fill rows right-to-left instead of left-to-right, for a player frame parked on the right side of the screen.",
        get = function() return CommanderBuffsDB.GrowLeft end,
        set = function(value) CommanderBuffsDB.GrowLeft = value end,
        isEnabled = BlockOn,
    }, {
        label = "My Buffs Rimmed",
        tooltip = "Give buffs you cast a faint gold rim, so your own upkeep is separable from what the raid put on you at a glance. Debuffs always wear their dispel-school rim instead.",
        get = function() return CommanderBuffsDB.MineRim end,
        set = function(value) CommanderBuffsDB.MineRim = value end,
        isEnabled = BlockOn,
    })

    panel:AddCheckboxPair({
        label = "Show Timers",
        tooltip = "Remaining time in text under each icon.",
        get = function() return CommanderBuffsDB.ShowTimers end,
        set = function(value) CommanderBuffsDB.ShowTimers = value end,
        isEnabled = BlockOn,
    }, {
        label = "Icon Sweep",
        tooltip = "A radial cooldown sweep on each block icon as well. The client animates it for free, but on a grid of 20 icons it reads as motion — off by default.",
        get = function() return CommanderBuffsDB.IconSweep end,
        set = function(value) CommanderBuffsDB.IconSweep = value end,
        isEnabled = BlockOn,
    })

    panel:AddCheckbox({
        label = "Round Icons",
        tooltip = "Cut every block icon into a disc with a circular alpha mask, with a matching circular rim. Off by default because the square grid is what mirrors the target frame — but if you turn Icon Sweep on, round icons make the sweep read as a real radial timer instead of a wedge across a square.",
        get = function() return CommanderBuffsDB.RoundBlockIcons end,
        set = function(value) CommanderBuffsDB.RoundBlockIcons = value end,
        isEnabled = BlockOn,
    })

    panel:AddSliderPair({
        label = "Icons Per Row",
        tooltip = "How many icons before the block wraps to the next row.",
        min = 3, max = 16, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.IconsPerRow end,
        set = function(value) CommanderBuffsDB.IconsPerRow = value end,
        isEnabled = BlockOn,
    }, {
        label = "Icon Spacing",
        tooltip = "Pixels between icons. The client's own target-frame spacing is 3.",
        min = 0, max = 10, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.IconGap end,
        set = function(value) CommanderBuffsDB.IconGap = value end,
        isEnabled = BlockOn,
    })

    panel:AddSliderPair({
        label = "Buff Size",
        tooltip = "Buff icon size in pixels. The target frame's own large aura size is 21.",
        min = 12, max = 40, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.BuffSize end,
        set = function(value) CommanderBuffsDB.BuffSize = value end,
        isEnabled = BlockOn,
    }, {
        label = "Debuff Size",
        tooltip = "Debuff icon size in pixels. Raising it above the buff size is the cheapest way to make incoming harm louder than upkeep.",
        min = 12, max = 40, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.DebuffSize end,
        set = function(value) CommanderBuffsDB.DebuffSize = value end,
        isEnabled = BlockOn,
    })

    panel:AddSlider({
        label = "Block Opacity",
        tooltip = "How solid the whole block is. Icons, rims, counts, and timers fade together — the block is meant to be readable at a glance and invisible the rest of the time, and this is the dial for that.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderBuffsDB.BlockOpacity end,
        set = function(value) CommanderBuffsDB.BlockOpacity = value end,
        isEnabled = BlockOn,
    })

    panel:AddSliderPair({
        label = "Offset X",
        tooltip = "Nudge the whole block horizontally from the player frame.",
        min = -200, max = 200, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.OffsetX end,
        set = function(value) CommanderBuffsDB.OffsetX = value end,
        isEnabled = BlockOn,
    }, {
        label = "Offset Y",
        tooltip = "Nudge the whole block vertically from the player frame.",
        min = -200, max = 200, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.OffsetY end,
        set = function(value) CommanderBuffsDB.OffsetY = value end,
        isEnabled = BlockOn,
    })

    panel:AddSection("The Portrait Sentinel",
        "One icon on your portrait showing the most interesting aura in your stack, with a radial duration ring. What counts as interesting is the rule editor's job; these options are only how it looks.")

    panel:AddCheckboxPair({
        label = "Show Sentinel",
        tooltip = "Draw the priority icon on the player portrait.",
        get = function() return CommanderBuffsDB.EnablePortrait end,
        set = function(value) CommanderBuffsDB.EnablePortrait = value end,
        isEnabled = Enabled,
    }, {
        label = "Show Stacks",
        tooltip = "Stack count in the icon's corner.",
        get = function() return CommanderBuffsDB.PortraitStacks end,
        set = function(value) CommanderBuffsDB.PortraitStacks = value end,
        isEnabled = PortraitOn,
    })

    panel:AddCheckboxPair({
        label = "Show Remaining Time",
        tooltip = "Remaining time in text under the sentinel as well as the ring. The ring already carries it — text is for people who want the number.",
        get = function() return CommanderBuffsDB.PortraitTimer end,
        set = function(value) CommanderBuffsDB.PortraitTimer = value end,
        isEnabled = PortraitOn,
    }, {
        label = "Round Icon",
        tooltip = "Cut the icon into a disc with a circular alpha mask so it reads as one shape with the ring around it, and give it a circular rim to match. A square icon inside a round timer is two objects fighting over the same few pixels. Clients without mask textures quietly keep square icons.",
        get = function() return CommanderBuffsDB.RoundSentinel end,
        set = function(value) CommanderBuffsDB.RoundSentinel = value end,
        isEnabled = PortraitOn,
    })

    panel:AddSlider({
        label = "Sentinel Opacity",
        tooltip = "How solid the sentinel is. The icon, its ring, its rim, and the expiry pulse all fade together, so a low value gives you a ghost that only announces itself when something is about to run out.",
        min = 0.1, max = 1, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderBuffsDB.PortraitOpacity end,
        set = function(value) CommanderBuffsDB.PortraitOpacity = value end,
        isEnabled = PortraitOn,
    })

    panel:AddDropdownPair({
        label = "Duration Style",
        tooltip = "Ring draws the duration as a shrinking circle AROUND the icon, so the art stays readable. Wedge is the classic cooldown sweep across the face.",
        options = {
            { text = "Ring", value = "RING" },
            { text = "Wedge", value = "WEDGE" },
        },
        get = function() return CommanderBuffsDB.SweepStyle end,
        set = function(value) CommanderBuffsDB.SweepStyle = value end,
        isEnabled = PortraitOn,
    }, {
        label = "Anchor",
        tooltip = "Where the sentinel sits relative to the portrait. Center is the default; the edges exist so it can coexist with anything else drawing on the portrait — Commander Momentum's streak ring, for one.",
        options = {
            { text = "Center", value = "CENTER" },
            { text = "Above", value = "TOP" },
            { text = "Below", value = "BOTTOM" },
            { text = "Left", value = "LEFT" },
            { text = "Right", value = "RIGHT" },
        },
        get = function() return CommanderBuffsDB.PortraitAnchor end,
        set = function(value) CommanderBuffsDB.PortraitAnchor = value end,
        isEnabled = PortraitOn,
    })

    panel:AddSliderPair({
        label = "Slots",
        tooltip = "How many priority icons to show. One is the point of the feature; two and three trail beside it for people who want the runners-up.",
        min = 1, max = 3, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.Slots end,
        set = function(value) CommanderBuffsDB.Slots = value end,
        isEnabled = PortraitOn,
    }, {
        label = "Icon Size",
        tooltip = "Sentinel icon size in pixels.",
        min = 14, max = 48, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.PortraitSize end,
        set = function(value) CommanderBuffsDB.PortraitSize = value end,
        isEnabled = PortraitOn,
    })

    panel:AddSliderPair({
        label = "Sentinel X",
        tooltip = "Nudge the sentinel horizontally from its anchor.",
        min = -80, max = 80, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.PortraitX end,
        set = function(value) CommanderBuffsDB.PortraitX = value end,
        isEnabled = PortraitOn,
    }, {
        label = "Sentinel Y",
        tooltip = "Nudge the sentinel vertically from its anchor.",
        min = -80, max = 80, step = 1, format = "%d",
        get = function() return CommanderBuffsDB.PortraitY end,
        set = function(value) CommanderBuffsDB.PortraitY = value end,
        isEnabled = PortraitOn,
    })

    panel:AddSliderPair({
        label = "Pulse Under",
        tooltip = "Pulse the sentinel when the aura has this many seconds left. Zero turns the pulse off.",
        min = 0, max = 10, step = 1, format = "%ds",
        get = function() return CommanderBuffsDB.PulseUnder end,
        set = function(value) CommanderBuffsDB.PulseUnder = value end,
        isEnabled = PortraitOn,
    }, {
        label = "Minimum Score",
        tooltip = "How interesting an aura must be to occupy your portrait. This one number is the quiet/chatty dial: raise it and only emergencies show, drop it to zero and the sentinel is never empty. The editor's live trace shows what each of your auras currently scores.",
        min = 0, max = 120, step = 5, format = "%d",
        get = function() return CommanderBuffsDB.MinScore end,
        set = function(value) CommanderBuffsDB.MinScore = value end,
        isEnabled = PortraitOn,
    })

    panel:AddDropdown({
        label = "Unmatched Auras",
        tooltip = "What happens to an aura no rule claims. Ignore keeps the sentinel strictly rule-driven. Score Debuffs gives every unclaimed harmful aura a floor of 10, so a new debuff can never be silently invisible. Score Everything gives all of them 5.",
        options = {
            { text = "Ignore", value = "IGNORE" },
            { text = "Score Debuffs", value = "DEBUFFS" },
            { text = "Score Everything", value = "ALL" },
        },
        get = function() return CommanderBuffsDB.FallbackMode end,
        set = function(value) CommanderBuffsDB.FallbackMode = value end,
        isEnabled = PortraitOn,
    })

    -- Chrome last, per the suite convention. The editor is a window rather
    -- than a HUD element, so it wears the Quartermaster/Talents framing
    -- toggle instead of the HudChrome block.
    panel:AddSection("Editor Window")

    panel:AddDropdown({
        label = "Window Style",
        tooltip = "Window uses the client's own panel art. Dark and Classic replace it with the suite's flat backdrops (and drop the title bar's close button — Escape still closes the window).",
        options = {
            { text = "Window", value = "WINDOW" },
            { text = "Dark", value = "DARK" },
            { text = "Classic", value = "CLASSIC" },
        },
        get = function() return CommanderBuffsDB.EditorStyle end,
        set = function(value) CommanderBuffsDB.EditorStyle = value end,
        isEnabled = Enabled,
    })

    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Scale of the priority editor window.",
        min = 0.7, max = 1.4, step = 0.05, format = "%.2f",
        get = function() return CommanderBuffsDB.EditorScale end,
        set = function(value) CommanderBuffsDB.EditorScale = value end,
        isEnabled = Enabled,
    })

    panel:AddButtonRow({
        {
            label = "Reset Editor Position",
            tooltip = "Put the editor window back in the middle of the screen.",
            onClick = function()
                CommanderBuffsDB.EditorPos = false
                Commander.Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
                print("Commander Buffs: editor window position reset")
            end,
        },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page to its default value. Your priority rules are kept — only the editor's own Restore Default Rules button replaces those.",
    })
    finishScroll()
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Commander_Buffs" then
        Migrate(CommanderBuffsDB)
        Commander.UI.ApplyDefaults(CommanderBuffsDB, DefaultSettings)
        if type(CommanderBuffsDB.Rules) ~= "table" or #CommanderBuffsDB.Rules == 0 then
            CommanderBuffsDB.Rules = CommanderBuffsEngine.DefaultRules()
        end
        frame:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreatePanel()
    end
end)

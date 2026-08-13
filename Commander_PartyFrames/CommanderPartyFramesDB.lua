CommanderPartyFramesDB = _G.CommanderPartyFramesDB or {}

COMMANDER_PARTYFRAMES_EVENTS = {
    UPDATE = "COMMANDER_PARTYFRAMES_UPDATE"
}

local DefaultSettings = {
    EnableShield = true,
    Scope = "PARTY",         -- PARTY (you + party) or RAID (you + raid)
    IncludeSelf = true,
    IncludePets = true,      -- allies' pets get ally rows too (buffable, healable)
    SelfFirst = false,       -- pin yourself to the top instead of sorting by urgency
    ShowHeader = true,       -- PW:S cooldown + your nominal shield value strip
    HeaderBackdrop = true,   -- dark panel behind the top bar
    HideBlizzardParty = false, -- hide Blizzard's own party frames (header button toggles it)
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
    BarTexture = "FLAT",        -- FLAT | BLIZZARD | GLOSS | BEVEL | RIDGE | GLASS
    IconRecess = "SOFT",        -- icon shading: OFF | SOFT | DEEP | CARVED
    SweepEdge = false,          -- leading-edge spark on the aura duration sweeps
    NameMaxChars = 6,
    ShowTargeters = true,       -- enemy-NPCs-targeting count over the class icon
    ShowTargetMarks = true,     -- raid mark of the unit each ally is targeting

    -- Ten flagged features (all neutral defaults, so current behavior is kept)
    ClickCast = false,          -- rows become secure mouseover/click unit buttons
    -- Click bindings: the full modifier x button matrix, per talent build.
    -- ClickBinds[profileKey][modPrefix .. button] = spellID | "TARGET" |
    -- "TARGETTARGET" | false (deliberately cleared). Absent = the layer
    -- default, until the profile is first edited.
    ClickBinds = {},
    ClickBindsMigrated = false, -- one-time seed from the old flat keys
    ClickProfileMode = "TALENT",-- TALENT (follow the build) | FIXED
    ClickProfileFixed = "",     -- which profile when FIXED
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
    -- The priest's own hots (Renew, Prayer of Mending) ride the shared strip
    -- now, so WHICH of them get a slot lives in BuffTrack with everyone
    -- else's. RenewTrack is gone with the right-edge icon it switched on.
    RenewFlash = true,          -- pulse a hot's slot when it is about to expire
    RenewRefreshAt = 4,         -- seconds left at/under which a hot counts as expiring
    PriestBannerCooldowns = true, -- Pain Suppression/PI/Fear Ward/... segments on the banner

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
    MageBannerCooldowns = true, -- Ice Block/Cold Snap/Evocation/... segments on the banner

    -- Druid layer: the hot board. Its own click keys for the same reason the
    -- mage's are separate — the DB is account-wide, so a priest's and a
    -- mage's bindings have to survive a druid touching these.
    -- Ally-buff strip. BuffTrack/BuffAdvise are per-buff overrides keyed
    -- "LAYER:KEY" (absent = the registry's own default), the same shape the
    -- ability book uses, so the DB never carries a row for a buff you have
    -- not touched.
    BuffTrack = {},             -- which buffs get a slot
    BuffAdvisor = true,         -- master switch for the urgency (dark red) read
    BuffAdvise = {},            -- per-buff urgency overrides
    HotRefreshAt = 4,           -- seconds left at/under which a hot counts as expiring
    HotReadyAt = 90,            -- health % at/under which a hotless ally goes READY
    HotBannerCooldowns = true,  -- Innervate/NS/Rebirth/Barkskin segments on the banner
    DruidClickLeft = 774,       -- druid row left-click   = Rejuvenation
    DruidClickRight = 33763,    -- druid row right-click  = Lifebloom
    DruidClickMiddle = "TARGET",-- druid row middle-click = target the ally
    DruidClickModLeft = 8936,   -- druid row mod+left     = Regrowth

    -- Paladin layer: the blessing board. Its own click keys for the same
    -- reason every other layer's are separate — the DB is account-wide.
    -- The Hands are emergency cooldowns rather than upkeep, so the READY bar
    -- sits far lower than the druid's: an ally at 89% does not want a BoP.
    BlessRefreshAt = 3,         -- seconds left at/under which a Hand counts as expiring
    BlessReadyAt = 50,          -- health % at/under which an unhanded ally goes READY
    BlessBannerCooldowns = true,-- Lay on Hands / bubble / wings segments on the banner
    -- No legacy PalaClick* keys: the paladin layer was born after click
    -- bindings moved into per-talent-profile stores, so its starting bindings
    -- live in the engine's SDATA.BIND_DEFAULTS with everyone else's and there
    -- is nothing here to migrate off.

    -- Banner utility buttons. Bandage is chassis (every class); the rest ride
    -- the mage layer alongside the armor switcher.
    ShowUtilityCounts = true,   -- inventory tallies over the water/food/gem/bandage icons
    ShowPortalButton = true,    -- portals & teleports popout
    ShowGemButton = true,       -- mana gem: use / conjure
    ShowBandageButton = true,   -- First Aid: bandage, lockout, open the window

    -- Party Ability Bar (engine lands in phases; keys reserved now)
    ShowAbilityBar = true,      -- cooldown strip under every player row
    AbilityMaxIcons = 6,        -- most ability icons per strip (3-8)
    AbilityBarSelf = true,      -- include your own row's strip
    AbilityBarOnlySelf = false, -- ...and ONLY your own row's
    AbilityCdText = true,       -- remaining-time text on cooling icons
    AbilityBarBackdrop = true,  -- dark panel behind each strip, hugging its icons
    AbilityTrack = {},          -- per-ability overrides ("CLASS:KEY" -> bool; absent = book default)
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

-- The per-layer click dropdown lists, and the single "which modifier?" picker
-- they went with, are gone: the binding grid builds its picker from the live
-- spellbook instead (see AddClickMatrix). That is both a bigger surface — every
-- modifier combination the client delivers, not one — and an honest one, since
-- it cannot offer a spell this character has never trained.

-- One definition, added to both class layers' Identity sections: the bar art
-- is chassis, not a class choice.
-- Shared with the rest of the suite: the art and the styles both come from
-- Commander_Events, so an icon on this board and an icon on any other
-- Commander board are shaded the same way at the same setting.
local ICON_STYLE_OPTION = {
    label = "Icon Recess",
    tooltip = "Shading laid over every spell icon on the board — the ability strip, dispel slots, consumables, class icons and portraits. Flat leaves them as Blizzard drew them. The other three shade the icon's rim so it reads as set into the row rather than pasted on it: Soft is a shallow press (what small icons want), Deep drives it harder, Carved is a hard narrow bevel.",
    options = Commander.ICON_STYLES,
    get = function() return CommanderPartyFramesDB.IconRecess end,
    set = function(value) CommanderPartyFramesDB.IconRecess = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

-- Also defined once and added to all three layers: the tracker strips are
-- chassis, so the spark is not a class decision either.
local SWEEP_EDGE_OPTION = {
    label = "Sweep Edge",
    tooltip = "Put a bright spark on the leading edge of the radial duration timers, so where a sweep IS reads at a glance instead of only how much shadow it has eaten. Affects the aura timers on the tracker strips: the own-aura strip, the ally-buff icons, and the dispellable-debuff icons. The party ability bar is deliberately left plain — those sweeps count down a cooldown, where the only question is ready or not, and a spark orbiting every one of them is motion you would have to learn to ignore.",
    get = function() return CommanderPartyFramesDB.SweepEdge end,
    set = function(value) CommanderPartyFramesDB.SweepEdge = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

local BAR_TEXTURE_OPTION = {
    label = "Bar Texture",
    tooltip = "What every bar on a row is drawn with — the health/absorb fill, the shield segments riding it, the mana strip and the lockout drain. Flat is a solid block, which reads fastest at a glance and stays crisp on the half-height personal rows. Blizzard is the gloss the default unit frames have always worn. The last four are the board's own art: Gloss is lit from above and falls away, Bevel is flat with a lit top edge, Ridge adds a brushed grain, and Glass cuts hard across the middle — each of them also grooves the empty part of the bar, so a track reads even when it is empty. Colors are unchanged whichever you pick.",
    options = {
        { text = "Flat", value = "FLAT" },
        { text = "Blizzard", value = "BLIZZARD" },
        { text = "Gloss", value = "GLOSS" },
        { text = "Bevel", value = "BEVEL" },
        { text = "Ridge", value = "RIDGE" },
        { text = "Glass", value = "GLASS" },
    },
    get = function() return CommanderPartyFramesDB.BarTexture end,
    set = function(value) CommanderPartyFramesDB.BarTexture = value end,
    isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
}

-- ---------------------------------------------------------------------------
-- Tracked Abilities window: one row per class (plus the shared racials and
-- trinket), each with a dropdown of that class's ability book — check an
-- ability to let it on the strip, uncheck to hide it. Overrides live in
-- CommanderPartyFramesDB.AbilityTrack ("CLASS:KEY" -> bool, "*:KEY" for
-- shared); absent means the book default, so `off` entries ship untracked
-- and the curated default strip is unchanged until you opt in.
-- ---------------------------------------------------------------------------
local ABILITY_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ABILITY_KIND_LABELS = { DEF = "Defensive", CC = "Crowd control", KICK = "Interrupt", OFF = "Offensive", UTIL = "Utility" }
local ABILITY_ROW_H = 30
local abilityWindow

-- ---------------------------------------------------------------------------
-- Ally-buff controls. One pair of checkboxes per buff the class maintains on
-- other people: whether it gets a slot at all, and whether that slot is
-- allowed to judge how badly it is missed. Both store only DEVIATIONS from the
-- registry's own defaults, so SavedVariables stay small and a buff you never
-- touched follows any later re-tuning of the registry.
-- ---------------------------------------------------------------------------
local function BuffOverride(field, def, value, fallback)
    local t = CommanderPartyFramesDB[field]
    if not t then t = {}; CommanderPartyFramesDB[field] = t end
    if value == fallback then t[def.dbKey] = nil else t[def.dbKey] = value end
end

local function BuffFlag(field, def, fallback)
    local t = CommanderPartyFramesDB[field]
    local v = t and t[def.dbKey]
    if v == nil then return fallback end
    return v
end

local BUFF_ADVICE_TEXT = {
    ALWAYS = "always — there is no fight where you would rather not have it",
    VS_MELEE = "when an enemy melee is parked on them, or a wounded melee ally is trading hits",
    VS_SHADOW = "only against a team that actually deals shadow damage",
    VS_PHYSICAL = "only against an all-physical team, where the extra magic damage taken costs nothing",
    VS_CASTER = "only against a caster team worth blunting",
}

-- Everything this class can put on somebody else, as a grid of the spells'
-- own icons — the icon IS the switch. A list of twelve checkboxes reading
-- "Track Prayer of Fortitude" is a worse way to answer "what am I watching"
-- than twelve icons where the lit ones are the answer.
--
--   left click   track / untrack (lit vs drained)
--   right click  let this slot judge urgency, or hush it (the gold pip)
--
-- Spells this character has not TRAINED are drawn struck through and refuse
-- both clicks. That is the honest version of "why is there no Lifebloom
-- slot": not silence, but the icon saying so.
-- Pitch, not gap: the cell is 30 wide but the LABEL under it needs room, and
-- at a 36px pitch every name past five characters clipped to "Aboli...". A
-- label you cannot read is worse than no label, so the pitch is set by the
-- text and the icon sits centred in it.
local BUFF_ICON_SIZE, BUFF_PITCH, BUFF_PER_ROW = 30, 54, 7
local BUFF_LABEL_H = 22       -- two short lines of GameFontHighlightSmall

local BUFF_ADVICE_TEXT = {
    ALWAYS = "always — there is no fight where you would rather not have it",
    VS_MELEE = "when an enemy melee is parked on them, or a wounded melee ally is trading hits",
    VS_SHADOW = "only against a team that actually deals shadow damage",
    VS_PHYSICAL = "only against an all-physical team, where the extra magic damage taken costs nothing",
    VS_CASTER = "only against a caster team worth blunting",
    VS_FEAR = "only against a team that brings a fear",
}

local function BuffFlag(field, def, fallback)
    local tbl = CommanderPartyFramesDB[field]
    local v = tbl and tbl[def.dbKey]
    if v == nil then return fallback end
    return v
end

local function BuffOverride(field, def, value, fallback)
    local tbl = CommanderPartyFramesDB[field]
    if not tbl then tbl = {}; CommanderPartyFramesDB[field] = tbl end
    if value == fallback then tbl[def.dbKey] = nil else tbl[def.dbKey] = value end
end

local function BuffTrackedUI(def) return BuffFlag("BuffTrack", def, def.default and true or false) end
local function BuffAdvisedUI(def) return BuffFlag("BuffAdvise", def, def.advise and true or false) end

local function BuffCellTooltip(self)
    local def = self.def
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(def.spellName or def.label, 1, 1, 1)
    if not def.known then
        GameTooltip:AddLine("Not trained on this character.", 1, 0.4, 0.4, true)
        GameTooltip:AddLine("It cannot take a slot, so the board will not show it.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
        return
    end
    if def.isHot then
        GameTooltip:AddLine("Your own, on that ally — the slot carries its remaining time as a sweep.",
            0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine("Any caster's counts as covered; the group version fills the same slot.",
            0.7, 0.7, 0.7, true)
    end
    if def.targets == "MANA" then
        GameTooltip:AddLine("Only appears on mana users.", 0.7, 0.7, 0.7, true)
    elseif def.targets == "MELEE" then
        GameTooltip:AddLine("Only appears on allies who swing a weapon (and on pets).",
            0.7, 0.7, 0.7, true)
    end
    if def.oneOf then
        GameTooltip:AddLine("One per ally: another of these already on them means this one is not missing.",
            0.7, 0.7, 0.7, true)
    end
    GameTooltip:AddLine(" ")
    if BuffTrackedUI(def) then
        GameTooltip:AddLine("Tracked — click to drop its slot", 0.4, 0.9, 0.4)
    else
        GameTooltip:AddLine("Not tracked — click to give it a slot", 0.8, 0.8, 0.8)
    end
    if def.advise then
        local how = BUFF_ADVICE_TEXT[def.advise] or "when the situation calls for it"
        if BuffAdvisedUI(def) then
            GameTooltip:AddLine("Advises: turns dark red " .. how, 1, 0.82, 0.25, true)
            GameTooltip:AddLine("Right-click to hush it", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("Hushed — tracks, never reddens", 0.6, 0.6, 0.6, true)
            GameTooltip:AddLine("Right-click to let it advise " .. how, 0.6, 0.6, 0.6, true)
        end
    else
        GameTooltip:AddLine("No urgency rule — this one never reddens.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function BuffCellClick(self, button)
    local def = self.def
    if not def.known then return end
    if button == "RightButton" then
        if not def.advise then return end
        BuffOverride("BuffAdvise", def, not BuffAdvisedUI(def), def.advise and true or false)
    else
        BuffOverride("BuffTrack", def, not BuffTrackedUI(def), def.default and true or false)
    end
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    if self.owner and self.owner.Refresh then self.owner:Refresh() end
    BuffCellTooltip(self)
end

-- ---------------------------------------------------------------------------
-- The click matrix: every modifier x every mouse button, as a grid of the
-- bound spells' own icons.
--
-- The old shape was four dropdowns and a "which modifier?" picker, which could
-- express exactly one modified click out of the twenty-four the client will
-- actually deliver. This is the whole surface: a row per modifier combination
-- in the order the secure code itself uses (alt, ctrl, shift), a column per
-- button, and each cell a click-to-open picker filtered to the spells this
-- character has really trained.
-- ---------------------------------------------------------------------------
local CLICK_CELL, CLICK_CELL_GAP, CLICK_LABEL_W = 28, 4, 104
local BIND_BOOK_CHUNK = 20      -- spells per alphabetical submenu

local bindMenu, bindMenuCell

local function ClickCellTooltip(self)
    local icon, label, missing = CommanderPartyFrames_BindDisplay(self.bindValue)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.modLabel .. " + " .. self.btnLabel, 1, 1, 1)
    if label == "Unbound" then
        GameTooltip:AddLine("Nothing bound — the click falls through.", 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(label, 0.4, 0.9, 0.4)
    end
    if missing then
        GameTooltip:AddLine("This character cannot cast that — the click will do nothing.",
            1, 0.4, 0.4, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to rebind, right-click to clear.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function ClickCellPick(value)
    if not bindMenuCell then return end
    CommanderPartyFrames_SetBind(bindMenuCell.bindKey, value)
    Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
    if bindMenuCell.owner then bindMenuCell.owner:Refresh() end
end

local function ClickMenuInit(_, level)
    level = level or 1
    local info
    if level == 1 then
        info = UIDropDownMenu_CreateInfo()
        info.text, info.isTitle, info.notCheckable = "Bind to", true, true
        UIDropDownMenu_AddButton(info, level)

        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable = "Clear this binding", true
        info.func = function() ClickCellPick(nil); CloseDropDownMenus() end
        UIDropDownMenu_AddButton(info, level)

        for _, a in ipairs(CommanderPartyFrames_GetClickActions()) do
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.icon = a.label, true, a.icon
            info.func = function() ClickCellPick(a.value); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end

        -- The curated groups first: what this class actually casts at a
        -- friendly unit, which is the answer nineteen times in twenty
        local byGroup, groups = CommanderPartyFrames_GetBindables()
        for _, g in ipairs(groups) do
            if byGroup[g] then
                info = UIDropDownMenu_CreateInfo()
                info.text, info.notCheckable, info.hasArrow = g, true, true
                info.menuList = g
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- ...then the whole spellbook, for the twentieth. Alphabetical
        -- buckets, because a single flat list of everything a level 70 knows
        -- is not a menu you can find anything in.
        local book = CommanderPartyFrames_GetSpellBook()
        if #book > 0 then
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.isTitle = " ", true, true
            UIDropDownMenu_AddButton(info, level)
            for first = 1, #book, BIND_BOOK_CHUNK do
                local last = math.min(first + BIND_BOOK_CHUNK - 1, #book)
                info = UIDropDownMenu_CreateInfo()
                info.text = string.format("All spells: %s - %s",
                    book[first].name:sub(1, 8), book[last].name:sub(1, 8))
                info.notCheckable, info.hasArrow = true, true
                info.menuList = "BOOK:" .. first
                UIDropDownMenu_AddButton(info, level)
            end
        end
    elseif level == 2 then
        local menuList = UIDROPDOWNMENU_MENU_VALUE
        local first = type(menuList) == "string" and menuList:match("^BOOK:(%d+)$")
        if first then
            local book = CommanderPartyFrames_GetSpellBook()
            first = tonumber(first)
            for i = first, math.min(first + BIND_BOOK_CHUNK - 1, #book) do
                local sp = book[i]
                info = UIDropDownMenu_CreateInfo()
                info.text, info.notCheckable, info.icon = sp.name, true, sp.icon
                -- Bound by name via the id; the client casts the highest rank
                info.func = function() ClickCellPick(sp.id); CloseDropDownMenus() end
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end
        local byGroup = CommanderPartyFrames_GetBindables()
        for _, sp in ipairs(byGroup[menuList] or {}) do
            info = UIDropDownMenu_CreateInfo()
            info.text, info.notCheckable, info.icon = sp.name, true, sp.icon
            info.func = function() ClickCellPick(sp.id); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end
    end
end

local function ClickCellClick(self, button)
    if button == "RightButton" then
        CommanderPartyFrames_SetBind(self.bindKey, nil)
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        if self.owner then self.owner:Refresh() end
        ClickCellTooltip(self)
        return
    end
    bindMenuCell = self
    if not bindMenu then
        bindMenu = CreateFrame("Frame", "CommanderPartyFramesBindMenu", UIParent,
            "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(bindMenu, ClickMenuInit, "MENU")
    ToggleDropDownMenu(1, nil, bindMenu, self, 0, 0)
end

-- Copy-from / reset, driven off the profile list. Both are destructive to the
-- profile you are looking at, which is exactly why the header above says which
-- one that is before you reach these.
local profileScratch = {}
local copyMenu

local function CopyMenuInit(_, level)
    local active = CommanderPartyFrames_ActiveProfile()
    CommanderPartyFrames_ListProfiles(profileScratch)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.isTitle, info.notCheckable = "Copy bindings from", true, true
    UIDropDownMenu_AddButton(info, level or 1)
    local any = false
    for _, key in ipairs(profileScratch) do
        if key ~= active then
            any = true
            info = UIDropDownMenu_CreateInfo()
            info.text = CommanderPartyFrames_ProfileLabel(key)
            info.notCheckable = true
            info.func = function()
                CommanderPartyFrames_CopyProfile(key, active)
                Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level or 1)
        end
    end
    if not any then
        info = UIDropDownMenu_CreateInfo()
        info.text, info.notCheckable, info.disabled = "No other profile yet", true, true
        UIDropDownMenu_AddButton(info, level or 1)
    end
end

local function AddClickMatrix(panel)
    local cells = {}
    local mods = CommanderPartyFrames_GetClickMods()
    local btns = CommanderPartyFrames_GetClickButtons()

    -- Which profile am I editing? Destructive controls sit below this line,
    -- so it has to be answered before the player reaches them.
    -- 22, not 18: the buttons in here are 20 tall, and a row shorter than its
    -- own contents is exactly how the section notes ended up drawing over the
    -- next control. Tagged so the harness can hold every custom row to that.
    local hdr = panel:AddRow(22, 8)
    hdr.probeChildren = {}
    local hdrText = hdr:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdrText:SetPoint("LEFT", hdr, "LEFT", 0, 0)
    local copyBtn = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    copyBtn:SetSize(96, 20)
    hdr.probeChildren[#hdr.probeChildren + 1] = copyBtn
    copyBtn:SetPoint("RIGHT", hdr, "RIGHT", -84, 0)
    copyBtn:SetText("Copy from...")
    copyBtn:SetScript("OnClick", function(self)
        if not copyMenu then
            copyMenu = CreateFrame("Frame", "CommanderPartyFramesCopyMenu", UIParent,
                "UIDropDownMenuTemplate")
        end
        UIDropDownMenu_Initialize(copyMenu, CopyMenuInit, "MENU")
        ToggleDropDownMenu(1, nil, copyMenu, self, 0, 0)
    end)
    local resetBtn = CreateFrame("Button", nil, hdr, "UIPanelButtonTemplate")
    resetBtn:SetSize(80, 20)
    hdr.probeChildren[#hdr.probeChildren + 1] = resetBtn
    resetBtn:SetPoint("RIGHT", hdr, "RIGHT", 0, 0)
    resetBtn:SetText("Defaults")
    resetBtn:SetScript("OnClick", function()
        CommanderPartyFrames_ResetProfile()
        Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
        panel:Refresh()
    end)
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reset this profile", 1, 1, 1)
        GameTooltip:AddLine("Drops every binding in the profile shown above and goes back to this class's starting set. The other profiles are untouched.",
            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Column headers
    local head = panel:AddRow(16, 10)
    for c, btn in ipairs(btns) do
        local fs = head:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("LEFT", head, "LEFT",
            CLICK_LABEL_W + (c - 1) * (CLICK_CELL + CLICK_CELL_GAP) - 6, 0)
        fs:SetWidth(CLICK_CELL + CLICK_CELL_GAP + 8)
        fs:SetText(btn.label)
    end
    for _, mod in ipairs(mods) do
        local row = panel:AddRow(CLICK_CELL + 2, 3)
        row.probeChildren = {}
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetWidth(CLICK_LABEL_W - 6)
        label:SetJustifyH("LEFT")
        label:SetText(mod.label)
        for c, btn in ipairs(btns) do
            local cell = CreateFrame("Button", nil, row)
            cell:SetSize(CLICK_CELL, CLICK_CELL)
            cell:SetPoint("LEFT", row, "LEFT",
                CLICK_LABEL_W + (c - 1) * (CLICK_CELL + CLICK_CELL_GAP), 0)
            cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            cell.bindKey = mod.key .. btn.key
            cell.modLabel, cell.btnLabel, cell.owner = mod.label, btn.label, panel
            cell.bg = cell:CreateTexture(nil, "BACKGROUND")
            cell.bg:SetAllPoints(cell)
            cell.bg:SetColorTexture(1, 1, 1, 0.07)
            cell.icon = cell:CreateTexture(nil, "ARTWORK")
            cell.icon:SetAllPoints(cell)
            cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            cell.icon:Hide()
            -- Red rim: bound to something this character cannot cast, which
            -- is a click that saves fine and then silently does nothing
            cell.warn = cell:CreateTexture(nil, "OVERLAY")
            cell.warn:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
            cell.warn:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
            cell.warn:SetColorTexture(0.95, 0.25, 0.25, 0.8)
            cell.warn:Hide()
            cell:SetScript("OnClick", ClickCellClick)
            cell:SetScript("OnEnter", ClickCellTooltip)
            cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.probeChildren[#row.probeChildren + 1] = cell
            cells[#cells + 1] = cell
        end
    end
    panel:AddRefresher(function()
        local on = CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast
        local active = CommanderPartyFrames_ActiveProfile()
        local auto = CommanderPartyFramesDB.ClickProfileMode ~= "FIXED"
        hdrText:SetText(string.format("Editing profile: |cffffd100%s|r %s",
            CommanderPartyFrames_ProfileLabel(active),
            auto and "|cff888888(follows your talent build)|r" or "|cff888888(single set)|r"))
        copyBtn:SetEnabled(on and true or false)
        resetBtn:SetEnabled(on and true or false)
        for _, cell in ipairs(cells) do
            cell.bindValue = CommanderPartyFrames_GetBind(cell.bindKey)
            local icon, _, missing = CommanderPartyFrames_BindDisplay(cell.bindValue)
            if icon then
                cell.icon:SetTexture(icon)
                cell.icon:SetDesaturated(not on)
                cell.icon:SetVertexColor(1, 1, 1, on and 1 or 0.5)
                cell.icon:Show()
            else
                cell.icon:Hide()
            end
            if missing then cell.warn:Show() else cell.warn:Hide() end
            cell:SetEnabled(on and true or false)
            cell.bg:SetColorTexture(1, 1, 1, on and 0.07 or 0.03)
        end
    end)
end

local function AddBuffSection(panel, layerMode)
    local defs = {}
    local book = CommanderPartyFrames_GetBuffBook and CommanderPartyFrames_GetBuffBook(layerMode)
    if book then for _, d in ipairs(book) do defs[#defs + 1] = d end end
    -- The druid's hots answer the same two questions and belong in the same
    -- grid: they are things you put on an ally and watch a slot for.
    local hots = CommanderPartyFrames_GetStripBook and CommanderPartyFrames_GetStripBook(layerMode)
    if hots then for _, d in ipairs(hots) do defs[#defs + 1] = d end end
    if #defs == 0 then return end

    panel:AddSection("Ally Buffs", "One slot per buff on the left of every row. The icon is the switch: left-click to track, right-click to let it judge urgency. Hover any icon for what it does.")
    panel:AddCheckbox({
        label = "Urgency Advisor",
        tooltip = "Master switch for the dark-red read. With it off every slot still tracks its buff, it just stops judging. Nothing reddens on an ally you cannot reach, on a spell that is genuinely cooling down, or while a druid is shifted out of caster form — urgency you cannot act on is not urgency — and two buffs that overwrite each other never both ask at once. |cffffd100/cpf buffs|r prints each slot's current verdict in the rule's own words.",
        get = function() return CommanderPartyFramesDB.BuffAdvisor end,
        set = function(value) CommanderPartyFramesDB.BuffAdvisor = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })

    local lines = math.ceil(#defs / BUFF_PER_ROW)
    local grid = panel:AddRow(lines * (BUFF_ICON_SIZE + BUFF_LABEL_H + 8) + 4, 10)
    grid.buffCells = {}
    -- Row height has to cover the label under the last line of icons, not just
    -- the icons: getting that wrong is what clipped the names to "Aboli..."
    grid.probeReach = lines * (BUFF_ICON_SIZE + BUFF_LABEL_H + 8)
    for i, def in ipairs(defs) do
        local col, line = (i - 1) % BUFF_PER_ROW, math.floor((i - 1) / BUFF_PER_ROW)
        local cell = CreateFrame("Button", nil, grid)
        cell:SetSize(BUFF_ICON_SIZE, BUFF_ICON_SIZE)
        cell:SetPoint("TOPLEFT", grid, "TOPLEFT",
            col * BUFF_PITCH + (BUFF_PITCH - BUFF_ICON_SIZE) / 2,
            -line * (BUFF_ICON_SIZE + BUFF_LABEL_H + 8))
        cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        cell.def, cell.owner = def, panel
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetAllPoints(cell)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Lit border on the tracked ones, so "what am I watching" is legible
        -- from across the page rather than needing a squint at saturation
        cell.border = cell:CreateTexture(nil, "BACKGROUND")
        cell.border:SetPoint("TOPLEFT", cell, "TOPLEFT", -2, 2)
        cell.border:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 2, -2)
        cell.border:SetColorTexture(1, 0.82, 0.25, 0.85)
        cell.border:Hide()
        -- Gold corner pip: this slot is allowed to judge
        cell.pip = cell:CreateTexture(nil, "OVERLAY")
        cell.pip:SetColorTexture(1, 0.82, 0.25, 1)
        cell.pip:SetSize(6, 6)
        cell.pip:SetPoint("TOPRIGHT", cell, "TOPRIGHT", 1, 1)
        cell.pip:Hide()
        -- Struck through: not in the spellbook, not a choice
        cell.slash = cell:CreateTexture(nil, "OVERLAY")
        cell.slash:SetColorTexture(0.95, 0.25, 0.25, 0.9)
        cell.slash:SetHeight(2)
        cell.slash:SetPoint("LEFT", cell, "LEFT", 2, 0)
        cell.slash:SetPoint("RIGHT", cell, "RIGHT", -2, 0)
        cell.slash:Hide()
        cell.label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cell.label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
        cell.label:SetWidth(BUFF_PITCH - 2)
        cell.label:SetHeight(BUFF_LABEL_H)
        cell.label:SetJustifyH("CENTER")
        cell.label:SetJustifyV("TOP")
        cell.label:SetMaxLines(2)
        cell:SetScript("OnClick", BuffCellClick)
        cell:SetScript("OnEnter", BuffCellTooltip)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
        grid.buffCells[i] = cell
    end

    panel:AddRefresher(function()
        for _, cell in ipairs(grid.buffCells) do
            local def = cell.def
            -- Live spell data: the icon and name only exist after login, and
            -- `known` changes with training and respecs
            local id = def.id or def.baseId
            if GetSpellInfo and id then
                local n, _, icon = GetSpellInfo(id)
                def.spellName = n or def.label
                if icon then def.icon = icon end
            end
            cell.icon:SetTexture(def.icon)
            local tracked = BuffTrackedUI(def)
            if not def.known then
                -- Readable, but plainly unavailable. Sunk any darker and the
                -- icon vanished into the page, leaving the red strike drawn
                -- across nothing at all.
                cell.icon:SetDesaturated(true)
                cell.icon:SetVertexColor(0.6, 0.6, 0.6, 0.85)
                cell.border:Hide(); cell.pip:Hide(); cell.slash:Show()
                cell.label:SetTextColor(0.75, 0.4, 0.4)
            else
                cell.slash:Hide()
                cell.icon:SetDesaturated(not tracked)
                if tracked then
                    cell.icon:SetVertexColor(1, 1, 1, 1)
                    cell.border:Show()
                    cell.label:SetTextColor(1, 0.82, 0.25)
                else
                    cell.icon:SetVertexColor(0.45, 0.45, 0.5, 0.85)
                    cell.border:Hide()
                    cell.label:SetTextColor(0.55, 0.55, 0.55)
                end
                if tracked and def.advise and BuffAdvisedUI(def)
                    and CommanderPartyFramesDB.BuffAdvisor then
                    cell.pip:Show()
                else
                    cell.pip:Hide()
                end
            end
            cell.label:SetText(def.label)
        end
    end)
end

local function AbilityList(classToken)
    if not CommanderPartyFrames_GetAbilityBook then return nil end
    local book, shared = CommanderPartyFrames_GetAbilityBook()
    if classToken == "SHARED" then return shared end
    return book[classToken]
end

local function AbilityTok(classToken, entry)
    return (classToken == "SHARED" and "*" or classToken) .. ":" .. entry.key
end

local function AbilityTracked(classToken, entry)
    local overrides = CommanderPartyFramesDB.AbilityTrack
    local value = overrides and overrides[AbilityTok(classToken, entry)]
    if value == nil then return not entry.off end
    return value
end

-- Store only deviations from the book default, so SavedVariables stay small
-- and untouched abilities follow any later re-curation of the book
local function WriteAbilityOverride(classToken, entry, tracked)
    local overrides = CommanderPartyFramesDB.AbilityTrack
    if not overrides then
        overrides = {}
        CommanderPartyFramesDB.AbilityTrack = overrides
    end
    if tracked == (not entry.off) then
        overrides[AbilityTok(classToken, entry)] = nil
    else
        overrides[AbilityTok(classToken, entry)] = tracked
    end
end

local function AbilityCounts(classToken)
    local list = AbilityList(classToken)
    if not list then return 0, 0 end
    local tracked = 0
    for _, entry in ipairs(list) do
        if AbilityTracked(classToken, entry) then tracked = tracked + 1 end
    end
    return tracked, #list
end

local function FormatAbilityCd(cd)
    if cd >= 60 then return string.format("%dm", math.floor(cd / 60 + 0.5)) end
    return string.format("%ds", cd)
end

local function RefreshAbilityWindow()
    if not (abilityWindow and abilityWindow:IsShown()) then return end
    for _, row in ipairs(abilityWindow.rows) do
        local tracked, total = AbilityCounts(row.classToken)
        row.count:SetText(string.format("%d of %d", tracked, total))
        local c = tracked > 0 and 0.85 or 0.5
        row.count:SetTextColor(c, c, c)
    end
end

local function AbilityMenuInit(menu)
    local classToken = menu.classToken
    local list = AbilityList(classToken)
    if not list then return end

    local title = UIDropDownMenu_CreateInfo()
    title.isTitle = true
    title.notCheckable = true
    title.text = menu.classLabel or classToken
    UIDropDownMenu_AddButton(title)

    for _, entry in ipairs(list) do
        local info = UIDropDownMenu_CreateInfo()
        local name = entry.dispName or entry.name
        info.text = string.format("|T%s:16|t %s  |cff8a8a8a%s|r",
            entry.dispIcon or entry.icon, name, FormatAbilityCd(entry.cd))
        info.isNotRadio = true
        info.keepShownOnClick = true
        info.checked = function() return AbilityTracked(classToken, entry) end
        info.func = function(_, _, _, checked)
            WriteAbilityOverride(classToken, entry, checked and true or false)
            Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
            RefreshAbilityWindow()
        end
        local detail = (ABILITY_KIND_LABELS[entry.kind] or entry.kind)
            .. (entry.tier == 1 and " — always on the strip while tracked."
                or " — shows only while cooling down.")
        if entry.spec then
            detail = detail .. "  " .. entry.spec:sub(1, 1) .. entry.spec:sub(2):lower() .. " only."
        end
        info.tooltipTitle = name
        info.tooltipText = detail
        info.tooltipOnButton = 1
        UIDropDownMenu_AddButton(info)
    end

    local function QuickSet(label, value)
        local info = UIDropDownMenu_CreateInfo()
        info.text = label
        info.notCheckable = true
        info.keepShownOnClick = true
        info.func = function()
            for _, entry in ipairs(list) do
                WriteAbilityOverride(classToken, entry, value == nil and (not entry.off) or value)
            end
            Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE)
            RefreshAbilityWindow()
            -- Repaint the open menu's checkmarks (only the clicked button
            -- refreshes itself)
            if UIDropDownMenu_Refresh then UIDropDownMenu_Refresh(menu, nil, 1) end
        end
        UIDropDownMenu_AddButton(info)
    end
    QuickSet("Track all", true)
    QuickSet("Track none", false)
    QuickSet("Book defaults", nil)
end

local function BuildAbilityWindow()
    local rowTokens = {}
    for i, token in ipairs(ABILITY_CLASSES) do rowTokens[i] = token end
    rowTokens[#rowTokens + 1] = "SHARED"

    local window = CreateFrame("Frame", "CommanderPartyFramesAbilityWindow", UIParent)
    window:SetSize(348, 74 + #rowTokens * ABILITY_ROW_H + 12)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function(self) self:StartMoving() end)
    window:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    window:SetClampedToScreen(true)
    Commander.UI.ApplyStyleBackdrop(window, "DARK")
    if UISpecialFrames then
        table.insert(UISpecialFrames, "CommanderPartyFramesAbilityWindow")
    end

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Party Ability Bar — Tracked Abilities")
    local closeButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", 2, 2)
    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    hint:SetPoint("RIGHT", window, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Choose what each class's strip may show. New options ship unchecked — the curated default holds until you opt in.")

    local menu = CreateFrame("Frame", "CommanderPartyFramesAbilityMenu", window, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, function() AbilityMenuInit(menu) end, "MENU")

    window.rows = {}
    for index, classToken in ipairs(rowTokens) do
        local row = CreateFrame("Frame", nil, window)
        row:SetHeight(ABILITY_ROW_H)
        row:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -66 - (index - 1) * ABILITY_ROW_H)
        row:SetPoint("RIGHT", window, "RIGHT", -12, 0)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        if classToken == "SHARED" then
            icon:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_01")
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            label:SetText("Everyone — racials & trinket")
        else
            local info = Commander.GetClassInfo(classToken)
            icon:SetTexture(info.icon)
            if info.iconCoords then icon:SetTexCoord(unpack(info.iconCoords)) end
            label:SetText(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken)
            label:SetTextColor(info.color[1], info.color[2], info.color[3])
        end

        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        button:SetSize(90, 22)
        button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        button:SetText("Choose…")
        button:SetScript("OnClick", function(self)
            menu.classToken = classToken
            menu.classLabel = label:GetText()
            ToggleDropDownMenu(1, nil, menu, self, 0, 0)
        end)

        local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        count:SetPoint("RIGHT", button, "LEFT", -10, 0)

        row.classToken, row.count = classToken, count
        window.rows[#window.rows + 1] = row
    end

    window:SetScript("OnShow", RefreshAbilityWindow)
    window:Hide()
    return window
end

function CommanderPartyFrames_ToggleAbilityWindow()
    if not CommanderPartyFrames_GetAbilityBook then
        print("Commander Party Frames: ability book unavailable")
        return
    end
    if not abilityWindow then abilityWindow = BuildAbilityWindow() end
    abilityWindow:SetShown(not abilityWindow:IsShown())
end

-- The whole module on one scrollable page, built for the class that is logged
-- in: the Priest reshield board, the Mage party frames, or a dormant-class note.
local function CreateCorePanel()
    -- Ask the engine which class layer this character gets (nil = none)
    local layerMode, classToken
    if CommanderPartyFrames_GetProfileMode then layerMode, classToken = CommanderPartyFrames_GetProfileMode() end
    local mageMode = layerMode == "INT"
    local druidMode = layerMode == "HOT"
    local palaMode = layerMode == "BLESS"
    local unsupported = not layerMode

    local description
    if unsupported then
        local localizedClass = UnitClass("player")
        description = string.format(
            "Swiss-army-knife party frames with a class layer. Priests get the reshield board (Power Word: Shield, Weakened Soul, dispels); Mages get buff-upkeep frames (Arcane Intellect, decursing, an optional self-shield strip); Druids get the hot board (Rejuvenation, Regrowth, Lifebloom stacks, curses and poisons); Paladins get the blessing board (blessings, the Hands, Forbearance). %s has no layer yet, so the module stays dormant on this character. Settings here are shared account-wide — boards on your Priest, Mage, Druid or Paladin characters are unaffected.",
            localizedClass or "This class")
    elseif palaMode then
        description = "Arena party frames with a paladin's brain. Health and mana per ally, absorbs embedded in the bar, and — leading each row — the blessings you keep up and the Hands you have spent there: Freedom, Protection and Sacrifice, each in a fixed slot timed by a radial sweep. Forbearance draws the red drain under the bar, because a target who cannot be Protected is a target you plan around. A removable debuff turns the row purple or green, crowd control orange. The banner on top is your own upkeep: aura, seal, cooldowns, blessing uptime, team alerts. Allies' pets get full rows too."
    elseif druidMode then
        description = "Arena party frames with a resto druid's brain. Health and mana per ally, absorbs embedded in the bar, and — leading each row — your ally buffs and the hots you have rolling there, each in a fixed slot timed by a radial sweep. A removable Curse turns the row purple, a Poison green, crowd control orange. The banner on top is your own upkeep: form, cooldowns, hot uptime, team alerts. Allies' pets get full rows too."
    elseif mageMode then
        description = "Arena party frames with a mage's brain. Health and mana per ally, their TOTAL shielding — every absorb from any caster — drained live by real absorb events, and an ally-buff strip leading each row. A removable curse turns the row purple; a teammate in crowd control turns it orange with the CC and time left. The banner is your own management: armor, shield uptime, alerts, and the conjure/consume cluster."
    else
        description = "Every absorb on the board at once, yours and everyone else's, embedded in each ally's health bar — with your own shield's remaining absorb as the row's number and the Weakened Soul lockout that blocks a reshield. Sorted most-urgent first, with an ally-buff strip leading each row. Built for Priests."
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
            buffs = function() if CommanderPartyFrames_Buffs then CommanderPartyFrames_Buffs() end end,
            binds = function() if CommanderPartyFrames_Binds then CommanderPartyFrames_Binds() end end,
            abilities = function() CommanderPartyFrames_ToggleAbilityWindow() end,
            -- Always-available twin of the header button: the board is
            -- Priest/Mage/Druid/Paladin only, and it can hide itself
            blizzard = function()
                if CommanderPartyFrames_ToggleBlizzardParty then
                    CommanderPartyFrames_ToggleBlizzardParty()
                end
            end,
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
        -- Re-synced on every refresh, not just at build: sections measure
        -- their own wrapped subtext on first show and grow, and a scroll
        -- child frozen at the build-time total would clip the last rows off.
        panel:AddRefresher(function()
            scrollChild:SetHeight(panel._contentHeight + 24)
        end)
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
            tooltip = "Show your management banner at the top: your armor with time left (a red OFF when you have none) with the click-to-switch popout, your Ice Block / Cold Snap / Evocation / Counterspell / Icy Veins / Presence of Mind / Arcane Power / Combustion / Invisibility / Frost Nova cooldowns, session shield uptime when tracked, team alerts (curses to remove, teammates in CC), and the conjure/consume/settings buttons. Live shield tracking lives on the My Shields rows below the board.",
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
        panel:AddCheckbox({
            label = "Include Pets",
            tooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, curse and CC colors, dispel strip and click-casting every ally row gets, so they can be buffed and healed like anyone else. Mana pets take the mana strip and the Arcane Intellect slot; a pet's portrait stands in for the class icon, and its name is tinted with its owner's class color. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort — but a cursed pet still outranks a quiet teammate. They count against Max Rows. Your own Water Elemental is not listed here: it already has its richer row below the board.",
            get = function() return CommanderPartyFramesDB.IncludePets end,
            set = function(value) CommanderPartyFramesDB.IncludePets = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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
        panel:AddCheckbox({
            label = "Header Backdrop",
            tooltip = "Dark panel behind the banner across the top of the board, so the icons and text read against it instead of against the world. Independent of the frame's own styled backdrop.",
            get = function() return CommanderPartyFramesDB.HeaderBackdrop end,
            set = function(value) CommanderPartyFramesDB.HeaderBackdrop = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })
        panel:AddCheckbox({
            label = "Hide Default Party Frames",
            tooltip = "Hide Blizzard's own party frames and run on this board alone. The header's stacked-rows button toggles the same setting, and |cffffd100/cpf blizzard|r works from anywhere — worth knowing, because this board is Priest/Mage/Druid/Paladin only and can hide itself. Changes apply out of combat; switching the module off gives the default frames back.",
            get = function() return CommanderPartyFramesDB.HideBlizzardParty end,
            set = function(value) CommanderPartyFramesDB.HideBlizzardParty = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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

        AddBuffSection(panel, "INT")

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
            tooltip = "Show the two team-synergy icons on the left of each row: Arcane Intellect only when it needs you (ghost when missing, amber inside the rebuff window — hidden while healthy) and the ally's biggest shield with a sweep for its remaining time. The row's number is their TOTAL shielding — Power Word: Shield, Ice Barrier, Mana Shield, wards, Sacrifice, whoever cast them.",
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
        panel:AddCheckbox({
            label = "Target Marks",
            tooltip = "Show, at each row's right edge, the raid mark of the unit that ally is CURRENTLY targeting — watch your tank hold skull (or drift off it), and pair with the Assist click binding to jump onto their target.",
            get = function() return CommanderPartyFramesDB.ShowTargetMarks end,
            set = function(value) CommanderPartyFramesDB.ShowTargetMarks = value end,
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
        panel:AddCheckbox({
            label = "Color Shield Types",
            tooltip = "Tint each embedded shield segment by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
            get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
            set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown(BAR_TEXTURE_OPTION)
        panel:AddDropdown(ICON_STYLE_OPTION)
        panel:AddCheckbox(SWEEP_EDGE_OPTION)

        panel:AddSection("Mouseover & Click", "Every modifier and button the client delivers. Click a cell to bind it, right-click to clear. Enabling needs a /reload and fixes the roster order.")
        panel:AddCheckbox({
            label = "Enable Row Clicks",
            tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each bound click casts its spell. Because secure frames cannot change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
            get = function() return CommanderPartyFramesDB.ClickCast end,
            set = function(value) CommanderPartyFramesDB.ClickCast = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown({
            label = "Binding Profile",
            tooltip = "Which set of bindings is live. Follow Talent Build keys them to the tree you have most points in, so respeccing from your arena build to your PvE one brings back the bindings you left for it — this is a TBC client, so the talent build is what stands in for dual spec. Single Set keeps one profile whatever you respec into.",
            options = {
                { text = "Follow Talent Build", value = "TALENT" },
                { text = "Single Set", value = "FIXED" },
            },
            get = function() return CommanderPartyFramesDB.ClickProfileMode end,
            set = function(value)
                CommanderPartyFramesDB.ClickProfileMode = value
                if value == "FIXED" and (CommanderPartyFramesDB.ClickProfileFixed or "") == "" then
                    CommanderPartyFramesDB.ClickProfileFixed =
                        CommanderPartyFrames_ActiveProfile and CommanderPartyFrames_ActiveProfile() or ""
                end
            end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end,
        })
        AddClickMatrix(panel)

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

        panel:AddCheckbox({
            label = "Banner Cooldowns",
            tooltip = "Show Ice Block, Cold Snap, Evocation, Counterspell, Icy Veins, Presence of Mind, Arcane Power, Combustion, Invisibility and Frost Nova on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so an arcane mage never sees a Cold Snap slot. Ice Barrier and the Water Elemental are deliberately absent: both already have their own row below the board, saying more than a segment could.",
            get = function() return CommanderPartyFramesDB.MageBannerCooldowns end,
            set = function(value) CommanderPartyFramesDB.MageBannerCooldowns = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })

        panel:AddSection("Banner Buttons", "The management cluster at the banner's right edge. Conjure and Consume are always there — Consume drinks on left-click and eats on right-click, so pressing both is the full sit-down. The rest are optional below.")
        panel:AddCheckboxPair({
            label = "Portals & Teleports",
            tooltip = "Add a button opening a two-row popout of every teleport (top) and portal (bottom) you have trained — the armor switcher's pattern, for travel. Hidden until you learn your first teleport.",
            get = function() return CommanderPartyFramesDB.ShowPortalButton end,
            set = function(value) CommanderPartyFramesDB.ShowPortalButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Mana Gem",
            tooltip = "Add a mana gem button: left-click uses the best gem in your bags, right-click (or holding your modifier and left-clicking) steps a castsequence through every gem you know — Ruby, Citrine, Jade, Agate — so four presses leave you carrying one of each. Ten seconds off the button restarts the sequence at the top rank. Counter over the icon shows how many gems you are carrying.",
            get = function() return CommanderPartyFramesDB.ShowGemButton end,
            set = function(value) CommanderPartyFramesDB.ShowGemButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Bandage",
            tooltip = "Add a First Aid button: left or right-click bandages a living friendly target (or yourself when you have none), the icon reddens with a countdown while Recently Bandaged blocks another, and middle-click opens the First Aid window.",
            get = function() return CommanderPartyFramesDB.ShowBandageButton end,
            set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Inventory Counters",
            tooltip = "Show how many you are carrying over each button — water on Conjure, food on Consume, gems on Mana Gem, bandages on Bandage. These keep counting during a fight, when the buttons' bindings themselves cannot be re-aimed.",
            get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
            set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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

        panel:AddSection("Party Ability Bar", "A curated cooldown strip under every player: match-deciders always visible (lit = ready, swept = cooling), trinkets/racials surfacing only once spent, a red rim for lockouts (Hypothermia, Forbearance), and a gold pip when Cold Snap or Preparation can refund a cooldown. Learned from the combat log; spec-gated abilities appear once the spec is known.")
        panel:AddCheckboxPair({
            label = "Show Ability Bar",
            tooltip = "Master switch for the per-player cooldown strips.",
            get = function() return CommanderPartyFramesDB.ShowAbilityBar end,
            set = function(value) CommanderPartyFramesDB.ShowAbilityBar = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Include Your Row",
            tooltip = "Also show the strip under your own row — you know your cooldowns, but under pressure the sanity check is free.",
            get = function() return CommanderPartyFramesDB.AbilityBarSelf end,
            set = function(value) CommanderPartyFramesDB.AbilityBarSelf = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Mine Only",
            tooltip = "Show the strip under YOUR row and nobody else's. The narrowest the ability bar goes without switching it off — the reminder of your own cooldowns, without a wall of everyone else's. Needs Include Your Row on, or there would be nothing left to draw.",
            get = function() return CommanderPartyFramesDB.AbilityBarOnlySelf end,
            set = function(value) CommanderPartyFramesDB.AbilityBarOnlySelf = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.ShowAbilityBar
                    and CommanderPartyFramesDB.AbilityBarSelf
            end,
        })
        panel:AddSlider({
            label = "Max Ability Icons",
            tooltip = "Most icons per strip; overflow evicts utility first, defensives last.",
            min = 3, max = 8, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.AbilityMaxIcons end,
            set = function(value) CommanderPartyFramesDB.AbilityMaxIcons = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Cooldown Text",
            tooltip = "Show remaining time on cooling icons (hidden under 10s — the sweep carries it).",
            get = function() return CommanderPartyFramesDB.AbilityCdText end,
            set = function(value) CommanderPartyFramesDB.AbilityCdText = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Bar Backdrop",
            tooltip = "Dark panel behind each strip, sized to the icons actually shown — so a short strip leaves no bar hanging under the row, and an empty one draws nothing.",
            get = function() return CommanderPartyFramesDB.AbilityBarBackdrop end,
            set = function(value) CommanderPartyFramesDB.AbilityBarBackdrop = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddButtonRow({
            {
                label = "Tracked Abilities…",
                width = 150,
                tooltip = "Open the tracked-abilities window — a dropdown per class choosing exactly which cooldowns its strip may show (also: /cpf abilities). New options ship unchecked, so the default strip is unchanged until you opt in.",
                onClick = function() CommanderPartyFrames_ToggleAbilityWindow() end,
                isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
            },
        })

        Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
            onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
        })

        panel:Finalize({ onDefaults = Reset })
        -- Re-synced on every refresh, not just at build: sections measure
        -- their own wrapped subtext on first show and grow, and a scroll
        -- child frozen at the build-time total would clip the last rows off.
        panel:AddRefresher(function()
            scrollChild:SetHeight(panel._contentHeight + 24)
        end)
        scrollChild:SetHeight(panel._contentHeight + 24)
        return
    end

    -- ---- Druid party frames: rolling hots + two schools of removal ----
    if druidMode then
        panel:AddCheckboxPair({
            label = "Enable Shield",
            tooltip = "Master switch for the whole module.",
            get = function() return CommanderPartyFramesDB.EnableShield end,
            set = function(value) CommanderPartyFramesDB.EnableShield = value end,
        }, {
            label = "Show Header",
            tooltip = "Show your upkeep banner at the top: the form you are in (red when it blocks healing — every other piece of advice on this board is unreachable until you shift out), your Innervate / Nature's Swiftness / Rebirth / Barkskin cooldowns, session hot uptime when tracked, team alerts (what you can remove, who is in CC), and the bandage/settings buttons.",
            get = function() return CommanderPartyFramesDB.ShowHeader end,
            set = function(value) CommanderPartyFramesDB.ShowHeader = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Include Self",
            tooltip = "Add your own row to the board — hots you have on yourself, and anything on you that you can remove.",
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
        panel:AddCheckbox({
            label = "Include Pets",
            tooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, curse and poison colors, dispel strip and click-casting every ally row gets, so your hots land on them like anyone else. Mark of the Wild applies whatever a pet runs on, so the buff slot is there even without a mana strip. A pet's portrait stands in for the class icon, and its name is tinted with its owner's class color. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort — but a poisoned pet still outranks a quiet teammate. They count against Max Rows.",
            get = function() return CommanderPartyFramesDB.IncludePets end,
            set = function(value) CommanderPartyFramesDB.IncludePets = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Only Show Alerts",
            tooltip = "Hide the quiet rows and keep only the ones that want a global — hots about to fall off, hurt allies carrying none, and anyone cursed, poisoned or in CC (you always stay visible). No effect in Click-Cast mode (fixed roster order).",
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
        panel:AddCheckbox({
            label = "Header Backdrop",
            tooltip = "Dark panel behind the banner across the top of the board, so the icons and text read against it instead of against the world. Independent of the frame's own styled backdrop.",
            get = function() return CommanderPartyFramesDB.HeaderBackdrop end,
            set = function(value) CommanderPartyFramesDB.HeaderBackdrop = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })
        panel:AddCheckbox({
            label = "Hide Default Party Frames",
            tooltip = "Hide Blizzard's own party frames and run on this board alone. The header's stacked-rows button toggles the same setting, and |cffffd100/cpf blizzard|r works from anywhere — worth knowing, because this board is Priest/Mage/Druid/Paladin only and can hide itself. Changes apply out of combat; switching the module off gives the default frames back.",
            get = function() return CommanderPartyFramesDB.HideBlizzardParty end,
            set = function(value) CommanderPartyFramesDB.HideBlizzardParty = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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
            tooltip = "Most ally rows shown at once (most urgent first).",
            min = 1, max = 40, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.MaxRows end,
            set = function(value) CommanderPartyFramesDB.MaxRows = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Frame Width",
            tooltip = "Overall width of the board — widen until the hot strip, names and numbers sit comfortably.",
            min = 180, max = 340, step = 2,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.FrameWidth end,
            set = function(value) CommanderPartyFramesDB.FrameWidth = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Rebuff Window",
            tooltip = "Treat an ally's Mark of the Wild as due when this much time or less remains — their status icon turns amber so you can rebuff before it drops.",
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

        AddBuffSection(panel, "HOT")

        panel:AddSection("Hots", "Your own hots on each ally, one fixed slot each, timed by a radial sweep. The row's number is whichever falls off first.")
        panel:AddSlider({
            label = "Refresh Window",
            tooltip = "Seconds left at or under which a hot counts as expiring — the row turns cyan (REFRESH) and sorts up by how long is actually left. This is also what catches a Lifebloom about to bloom, so set it to the reaction time you actually want.",
            min = 1, max = 10, step = 1,
            format = "%.0fs",
            get = function() return CommanderPartyFramesDB.HotRefreshAt end,
            set = function(value) CommanderPartyFramesDB.HotRefreshAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Hot Me At",
            tooltip = "Health at or under which an ally carrying none of your hots turns yellow (READY — start one now). Above it they stay quiet, so a full-health party does not light the whole board up. Set it to 100% to flag every hotless ally.",
            min = 30, max = 100, step = 5,
            format = "%.0f%%",
            get = function() return CommanderPartyFramesDB.HotReadyAt end,
            set = function(value) CommanderPartyFramesDB.HotReadyAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckbox({
            label = "Banner Cooldowns",
            tooltip = "Show Innervate, Nature's Swiftness, Rebirth and Barkskin on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so a feral never sees a Nature's Swiftness slot.",
            get = function() return CommanderPartyFramesDB.HotBannerCooldowns end,
            set = function(value) CommanderPartyFramesDB.HotBannerCooldowns = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
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
            tooltip = "Show the left status slot and the hot strip beside it. The status slot carries Mark of the Wild only when it needs you — ghost when missing, amber inside the rebuff window, hidden while healthy — and unlike Arcane Intellect it applies to your rage and energy allies too.",
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
        panel:AddCheckbox({
            label = "Target Marks",
            tooltip = "Show, at each row's right edge, the raid mark of the unit that ally is CURRENTLY targeting — watch your tank hold skull (or drift off it), and pair with the Assist click binding to jump onto their target.",
            get = function() return CommanderPartyFramesDB.ShowTargetMarks end,
            set = function(value) CommanderPartyFramesDB.ShowTargetMarks = value end,
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
        panel:AddCheckbox({
            label = "Color Shield Types",
            tooltip = "Tint each absorb embedded in an ally's health bar by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
            get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
            set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown(BAR_TEXTURE_OPTION)
        panel:AddDropdown(ICON_STYLE_OPTION)
        panel:AddCheckbox(SWEEP_EDGE_OPTION)

        panel:AddSection("Mouseover & Click", "Every modifier and button the client delivers. Click a cell to bind it, right-click to clear. Enabling needs a /reload and fixes the roster order.")
        panel:AddCheckbox({
            label = "Enable Row Clicks",
            tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each bound click casts its spell. Because secure frames cannot change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
            get = function() return CommanderPartyFramesDB.ClickCast end,
            set = function(value) CommanderPartyFramesDB.ClickCast = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown({
            label = "Binding Profile",
            tooltip = "Which set of bindings is live. Follow Talent Build keys them to the tree you have most points in, so respeccing from your arena build to your PvE one brings back the bindings you left for it — this is a TBC client, so the talent build is what stands in for dual spec. Single Set keeps one profile whatever you respec into.",
            options = {
                { text = "Follow Talent Build", value = "TALENT" },
                { text = "Single Set", value = "FIXED" },
            },
            get = function() return CommanderPartyFramesDB.ClickProfileMode end,
            set = function(value)
                CommanderPartyFramesDB.ClickProfileMode = value
                if value == "FIXED" and (CommanderPartyFramesDB.ClickProfileFixed or "") == "" then
                    CommanderPartyFramesDB.ClickProfileFixed =
                        CommanderPartyFrames_ActiveProfile and CommanderPartyFrames_ActiveProfile() or ""
                end
            end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end,
        })
        AddClickMatrix(panel)

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
            tooltip = "Softly glow any row with an open action — something to remove, a hot to start or refresh, or a missing Mark — so the next global jumps out.",
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
            tooltip = "Track your HOT uptime — the share of the session your living teammates were carrying at least one hot of yours. Shown in the banner; detailed by /cpf report.",
            get = function() return CommanderPartyFramesDB.TrackUptime end,
            set = function(value) CommanderPartyFramesDB.TrackUptime = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Shield Broke Flash",
            tooltip = "Flash a row red the moment a teammate's LAST absorb breaks — that is exactly when the enemy team commits, and on this board it is the cue to pre-hot before the damage lands.",
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

        panel:AddSection("Banner Buttons", "First Aid is not a class layer, so the bandage control rides this banner too.")
        panel:AddCheckboxPair({
            label = "Bandage Button",
            tooltip = "Show the First Aid control: left or right-click bandages your friendly target (or you), middle-click opens the First Aid window. The icon carries a count of the bandages in your bags and sweeps while the target is locked out by Recently Bandaged.",
            get = function() return CommanderPartyFramesDB.ShowBandageButton end,
            set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        }, {
            label = "Inventory Counts",
            tooltip = "Show the live tally of what is in your bags over the button icon.",
            get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
            set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })

        panel:AddSection("Dispellable Debuffs", "A strip of icons to the right of each row showing debuffs you can remove — Curses with a purple rim, Poisons with a green one — and a glow on crowd control. Both schools also color the whole row, whatever is shown here.")
        panel:AddCheckboxPair({
            label = "Show Dispellable Debuffs",
            tooltip = "Show, to the right of each ally's row, the Curses and Poisons you can remove (rim colored by school, countdown sweep). The CURSED and POISONED row states work even with this strip off; the strip tells you WHICH debuff it is.",
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
            label = "Heal Reduction Glow",
            tooltip = "Red pulse on debuffs that cut healing received (Mortal Strike, Wound Poison). On a hot board that is the cue to stop topping and start pre-hotting through it.",
            get = function() return CommanderPartyFramesDB.DispelHealGlow end,
            set = function(value) CommanderPartyFramesDB.DispelHealGlow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        })
        panel:AddCheckbox({
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

        panel:AddSection("Party Ability Bar", "A curated cooldown strip under every player: match-deciders always visible (lit = ready, swept = cooling), trinkets/racials surfacing only once spent, a red rim for lockouts (Hypothermia, Forbearance), and a gold pip when Cold Snap or Preparation can refund a cooldown. Learned from the combat log; spec-gated abilities appear once the spec is known.")
        panel:AddCheckboxPair({
            label = "Show Ability Bar",
            tooltip = "Master switch for the per-player cooldown strips.",
            get = function() return CommanderPartyFramesDB.ShowAbilityBar end,
            set = function(value) CommanderPartyFramesDB.ShowAbilityBar = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Include Your Row",
            tooltip = "Also show the strip under your own row — you know your cooldowns, but under pressure the sanity check is free.",
            get = function() return CommanderPartyFramesDB.AbilityBarSelf end,
            set = function(value) CommanderPartyFramesDB.AbilityBarSelf = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Mine Only",
            tooltip = "Show the strip under YOUR row and nobody else's. The narrowest the ability bar goes without switching it off — the reminder of your own cooldowns, without a wall of everyone else's. Needs Include Your Row on, or there would be nothing left to draw.",
            get = function() return CommanderPartyFramesDB.AbilityBarOnlySelf end,
            set = function(value) CommanderPartyFramesDB.AbilityBarOnlySelf = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.ShowAbilityBar
                    and CommanderPartyFramesDB.AbilityBarSelf
            end,
        })
        panel:AddSlider({
            label = "Max Ability Icons",
            tooltip = "Most icons per strip; overflow evicts utility first, defensives last.",
            min = 3, max = 8, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.AbilityMaxIcons end,
            set = function(value) CommanderPartyFramesDB.AbilityMaxIcons = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Cooldown Text",
            tooltip = "Show remaining time on cooling icons (hidden under 10s — the sweep carries it).",
            get = function() return CommanderPartyFramesDB.AbilityCdText end,
            set = function(value) CommanderPartyFramesDB.AbilityCdText = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Bar Backdrop",
            tooltip = "Dark panel behind each strip, sized to the icons actually shown — so a short strip leaves no bar hanging under the row, and an empty one draws nothing.",
            get = function() return CommanderPartyFramesDB.AbilityBarBackdrop end,
            set = function(value) CommanderPartyFramesDB.AbilityBarBackdrop = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddButtonRow({
            {
                label = "Tracked Abilities…",
                width = 150,
                tooltip = "Open the tracked-abilities window — a dropdown per class choosing exactly which cooldowns its strip may show (also: /cpf abilities). New options ship unchecked, so the default strip is unchanged until you opt in.",
                onClick = function() CommanderPartyFrames_ToggleAbilityWindow() end,
                isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
            },
        })

        Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
            onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
        })

        panel:Finalize({ onDefaults = Reset })
        -- Re-synced on every refresh, not just at build: sections measure
        -- their own wrapped subtext on first show and grow, and a scroll
        -- child frozen at the build-time total would clip the last rows off.
        panel:AddRefresher(function()
            scrollChild:SetHeight(panel._contentHeight + 24)
        end)
        scrollChild:SetHeight(panel._contentHeight + 24)
        return
    end

    -- ---- Paladin party frames: blessings, the Hands, and Forbearance ----
    if palaMode then
        panel:AddCheckboxPair({
            label = "Enable Shield",
            tooltip = "Master switch for the whole module.",
            get = function() return CommanderPartyFramesDB.EnableShield end,
            set = function(value) CommanderPartyFramesDB.EnableShield = value end,
        }, {
            label = "Show Header",
            tooltip = "Show your upkeep banner at the top: the aura you are running and the seal you are holding (both red when you have none — a paladin is always meant to be running both), your Lay on Hands / bubble / Hands / wings cooldowns, session blessing uptime when tracked, team alerts (what you can cleanse, who is in CC), and the bandage/settings buttons.",
            get = function() return CommanderPartyFramesDB.ShowHeader end,
            set = function(value) CommanderPartyFramesDB.ShowHeader = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Include Self",
            tooltip = "Add your own row to the board — the Hands you have on yourself, your own Forbearance, and anything on you that you can cleanse.",
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
        panel:AddCheckbox({
            label = "Include Pets",
            tooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, magic and poison colors, dispel strip and click-casting every ally row gets, so a Freedom or a blessing lands on them like anyone else. Blessing of Might applies to anything that swings, so a pet keeps that slot even without a mana strip. A pet's portrait stands in for the class icon, and its name is tinted with its owner's class color. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort — but a poisoned pet still outranks a quiet teammate. They count against Max Rows.",
            get = function() return CommanderPartyFramesDB.IncludePets end,
            set = function(value) CommanderPartyFramesDB.IncludePets = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Only Show Alerts",
            tooltip = "Hide the quiet rows and keep only the ones that want a global — Hands about to fall off, allies in real trouble with none, anyone Forbearance-locked, and anyone with something you can cleanse or in CC (you always stay visible). No effect in Click-Cast mode (fixed roster order).",
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
        panel:AddCheckbox({
            label = "Header Backdrop",
            tooltip = "Dark panel behind the banner across the top of the board, so the icons and text read against it instead of against the world. Independent of the frame's own styled backdrop.",
            get = function() return CommanderPartyFramesDB.HeaderBackdrop end,
            set = function(value) CommanderPartyFramesDB.HeaderBackdrop = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })
        panel:AddCheckbox({
            label = "Hide Default Party Frames",
            tooltip = "Hide Blizzard's own party frames and run on this board alone. The header's stacked-rows button toggles the same setting, and |cffffd100/cpf blizzard|r works from anywhere — worth knowing, because this board is Priest/Mage/Druid/Paladin only and can hide itself. Changes apply out of combat; switching the module off gives the default frames back.",
            get = function() return CommanderPartyFramesDB.HideBlizzardParty end,
            set = function(value) CommanderPartyFramesDB.HideBlizzardParty = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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
            tooltip = "Most ally rows shown at once (most urgent first).",
            min = 1, max = 40, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.MaxRows end,
            set = function(value) CommanderPartyFramesDB.MaxRows = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Frame Width",
            tooltip = "Overall width of the board — widen until the blessing slots, the Hand strip, names and numbers sit comfortably.",
            min = 180, max = 340, step = 2,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.FrameWidth end,
            set = function(value) CommanderPartyFramesDB.FrameWidth = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Rebuff Window",
            tooltip = "Treat an ally's blessing as due when this much time or less remains — its slot turns amber so you can rebless before it drops. Greater blessings run thirty minutes and singles ten, so this is the one number that decides how often the strip asks you for anything.",
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

        AddBuffSection(panel, "BLESS")

        panel:AddSection("Hands", "Your own Blessing of Freedom, Protection and Sacrifice on each ally, one fixed slot each, timed by a radial sweep. The row's number is whichever falls off first — and when a target is carrying Forbearance, the red drain under the bar is the minute you cannot Protect them for.")
        panel:AddSlider({
            label = "Refresh Window",
            tooltip = "Seconds left at or under which a Hand counts as expiring — the row turns cyan (REFRESH) and sorts up by how long is actually left, or orange (FADING) when Forbearance means you cannot replace it. Ten seconds of Freedom goes fast, so set this to the reaction time you actually want.",
            min = 1, max = 10, step = 1,
            format = "%.0fs",
            get = function() return CommanderPartyFramesDB.BlessRefreshAt end,
            set = function(value) CommanderPartyFramesDB.BlessRefreshAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddSlider({
            label = "Hand Me At",
            tooltip = "Health at or under which an ally carrying none of your Hands turns yellow (READY — this is the one to Protect or Free). A Hand is a cooldown you get once a fight, so this sits far lower than a hot board's: an ally at 89% is not a decision. An ally with an enemy melee parked on them qualifies at 85% whatever this says.",
            min = 30, max = 100, step = 5,
            format = "%.0f%%",
            get = function() return CommanderPartyFramesDB.BlessReadyAt end,
            set = function(value) CommanderPartyFramesDB.BlessReadyAt = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckbox({
            label = "Banner Cooldowns",
            tooltip = "Show Lay on Hands, Divine Shield, Divine Protection, the three Hands, Divine Favor, Avenging Wrath, Hammer of Justice, Divine Illumination and Repentance on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so a holy paladin never sees a Repentance slot.",
            get = function() return CommanderPartyFramesDB.BlessBannerCooldowns end,
            set = function(value) CommanderPartyFramesDB.BlessBannerCooldowns = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
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
            tooltip = "Show the blessing slots and the Hand strip beside them. A blessing slot is ghosted when missing, amber inside the rebuff window, and dark-red only when the advisor says its absence is actually costing you — never when the ally already carries another of your blessings, because the game only allows them one.",
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
        panel:AddCheckbox({
            label = "Target Marks",
            tooltip = "Show, at each row's right edge, the raid mark of the unit that ally is CURRENTLY targeting — watch your tank hold skull (or drift off it), and pair with the Assist click binding to jump onto their target.",
            get = function() return CommanderPartyFramesDB.ShowTargetMarks end,
            set = function(value) CommanderPartyFramesDB.ShowTargetMarks = value end,
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
        panel:AddCheckbox({
            label = "Color Shield Types",
            tooltip = "Tint each absorb embedded in an ally's health bar by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
            get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
            set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown(BAR_TEXTURE_OPTION)
        panel:AddDropdown(ICON_STYLE_OPTION)
        panel:AddCheckbox(SWEEP_EDGE_OPTION)

        panel:AddSection("Mouseover & Click", "Every modifier and button the client delivers. Click a cell to bind it, right-click to clear. Enabling needs a /reload and fixes the roster order.")
        panel:AddCheckbox({
            label = "Enable Row Clicks",
            tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each bound click casts its spell. Because secure frames cannot change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
            get = function() return CommanderPartyFramesDB.ClickCast end,
            set = function(value) CommanderPartyFramesDB.ClickCast = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddDropdown({
            label = "Binding Profile",
            tooltip = "Which set of bindings is live. Follow Talent Build keys them to the tree you have most points in, so respeccing from your arena build to your PvE one brings back the bindings you left for it — this is a TBC client, so the talent build is what stands in for dual spec. Single Set keeps one profile whatever you respec into.",
            options = {
                { text = "Follow Talent Build", value = "TALENT" },
                { text = "Single Set", value = "FIXED" },
            },
            get = function() return CommanderPartyFramesDB.ClickProfileMode end,
            set = function(value)
                CommanderPartyFramesDB.ClickProfileMode = value
                if value == "FIXED" and (CommanderPartyFramesDB.ClickProfileFixed or "") == "" then
                    CommanderPartyFramesDB.ClickProfileFixed =
                        CommanderPartyFrames_ActiveProfile and CommanderPartyFrames_ActiveProfile() or ""
                end
            end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end,
        })
        AddClickMatrix(panel)

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
            tooltip = "Softly glow any row with an open action — something to cleanse, a Hand to give or refresh, or a missing blessing — so the next global jumps out.",
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
            tooltip = "Track your BLESSING uptime — the share of the session your living teammates were carrying at least one blessing of yours. Hands are deliberately not counted: they are emergencies, and a number near zero would mean nothing. Shown in the banner; detailed by /cpf report.",
            get = function() return CommanderPartyFramesDB.TrackUptime end,
            set = function(value) CommanderPartyFramesDB.TrackUptime = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        })
        panel:AddCheckboxPair({
            label = "Shield Broke Flash",
            tooltip = "Flash a row red the moment a teammate's LAST absorb breaks — that is exactly when the enemy team commits, and on this board it is the cue to have a Hand ready before the damage lands.",
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

        panel:AddSection("Banner Buttons", "First Aid is not a class layer, so the bandage control rides this banner too.")
        panel:AddCheckboxPair({
            label = "Bandage Button",
            tooltip = "Show the First Aid control: left or right-click bandages your friendly target (or you), middle-click opens the First Aid window. The icon carries a count of the bandages in your bags and sweeps while the target is locked out by Recently Bandaged.",
            get = function() return CommanderPartyFramesDB.ShowBandageButton end,
            set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        }, {
            label = "Inventory Counts",
            tooltip = "Show the live tally of what is in your bags over the button icon.",
            get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
            set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
        })

        panel:AddSection("Dispellable Debuffs", "A strip of icons to the right of each row showing debuffs you can remove — a paladin cleanses Magic, Poison and Disease, which is more schools than anyone else on this board — and a glow on crowd control. A removable debuff also colors the whole row, whatever is shown here.")
        panel:AddCheckboxPair({
            label = "Show Dispellable Debuffs",
            tooltip = "Show, to the right of each ally's row, the Magic, Poison and Disease debuffs you can cleanse (rim colored by school, countdown sweep). The row states work even with this strip off; the strip tells you WHICH debuff it is.",
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
            label = "Heal Reduction Glow",
            tooltip = "Red pulse on debuffs that cut healing received (Mortal Strike, Wound Poison). On a paladin board that is the cue to stop trading Flash of Light against it and spend a cooldown instead.",
            get = function() return CommanderPartyFramesDB.DispelHealGlow end,
            set = function(value) CommanderPartyFramesDB.DispelHealGlow = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowDispels end,
        })
        panel:AddCheckbox({
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

        panel:AddSection("Party Ability Bar", "A curated cooldown strip under every player: match-deciders always visible (lit = ready, swept = cooling), trinkets/racials surfacing only once spent, a red rim for lockouts (Hypothermia, Forbearance), and a gold pip when Cold Snap or Preparation can refund a cooldown. Learned from the combat log; spec-gated abilities appear once the spec is known.")
        panel:AddCheckboxPair({
            label = "Show Ability Bar",
            tooltip = "Master switch for the per-player cooldown strips.",
            get = function() return CommanderPartyFramesDB.ShowAbilityBar end,
            set = function(value) CommanderPartyFramesDB.ShowAbilityBar = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        }, {
            label = "Include Your Row",
            tooltip = "Also show the strip under your own row — you know your cooldowns, but under pressure the sanity check is free.",
            get = function() return CommanderPartyFramesDB.AbilityBarSelf end,
            set = function(value) CommanderPartyFramesDB.AbilityBarSelf = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Mine Only",
            tooltip = "Show the strip under YOUR row and nobody else's. The narrowest the ability bar goes without switching it off — the reminder of your own cooldowns, without a wall of everyone else's. Needs Include Your Row on, or there would be nothing left to draw.",
            get = function() return CommanderPartyFramesDB.AbilityBarOnlySelf end,
            set = function(value) CommanderPartyFramesDB.AbilityBarOnlySelf = value end,
            isEnabled = function()
                return CommanderPartyFramesDB.EnableShield
                    and CommanderPartyFramesDB.ShowAbilityBar
                    and CommanderPartyFramesDB.AbilityBarSelf
            end,
        })
        panel:AddSlider({
            label = "Max Ability Icons",
            tooltip = "Most icons per strip; overflow evicts utility first, defensives last.",
            min = 3, max = 8, step = 1,
            format = "%.0f",
            get = function() return CommanderPartyFramesDB.AbilityMaxIcons end,
            set = function(value) CommanderPartyFramesDB.AbilityMaxIcons = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Cooldown Text",
            tooltip = "Show remaining time on cooling icons (hidden under 10s — the sweep carries it).",
            get = function() return CommanderPartyFramesDB.AbilityCdText end,
            set = function(value) CommanderPartyFramesDB.AbilityCdText = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddCheckbox({
            label = "Bar Backdrop",
            tooltip = "Dark panel behind each strip, sized to the icons actually shown — so a short strip leaves no bar hanging under the row, and an empty one draws nothing.",
            get = function() return CommanderPartyFramesDB.AbilityBarBackdrop end,
            set = function(value) CommanderPartyFramesDB.AbilityBarBackdrop = value end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        })
        panel:AddButtonRow({
            {
                label = "Tracked Abilities…",
                width = 150,
                tooltip = "Open the tracked-abilities window — a dropdown per class choosing exactly which cooldowns its strip may show (also: /cpf abilities). New options ship unchecked, so the default strip is unchanged until you opt in.",
                onClick = function() CommanderPartyFrames_ToggleAbilityWindow() end,
                isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
            },
        })

        Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
            isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
            onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
        })

        panel:Finalize({ onDefaults = Reset })
        -- Re-synced on every refresh, not just at build: sections measure
        -- their own wrapped subtext on first show and grow, and a scroll
        -- child frozen at the build-time total would clip the last rows off.
        panel:AddRefresher(function()
            scrollChild:SetHeight(panel._contentHeight + 24)
        end)
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
        tooltip = "Show your upkeep banner at the top: Inner Fire (red when it has fallen off), your Power Word: Shield cooldown — or its current absorb estimate once it is back — your Pain Suppression / Power Infusion / Fear Ward / Psychic Scream / Silence / Inner Focus / Shadowfiend / Mass Dispel / Desperate Prayer cooldowns, session shield uptime when tracked, team alerts (what you can dispel, who is in CC), and the bandage/settings buttons.",
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
    panel:AddCheckbox({
        label = "Include Pets",
        tooltip = "Give your allies' pets their own rows — a warlock's demon, a hunter's pet — with the same health bar, embedded absorbs, Weakened Soul lockout, dispel strip and click-casting every ally row gets, so a pet can be shielded and healed like anyone else. A pet's portrait stands in for the class icon, and its name is tinted with its owner's class color. Pets carry no ability strip (the book is a class's cooldowns, and a pet has none) and give way to an equally urgent player in the sort. They count against Max Rows.",
        get = function() return CommanderPartyFramesDB.IncludePets end,
        set = function(value) CommanderPartyFramesDB.IncludePets = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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
    panel:AddCheckbox({
        label = "Header Backdrop",
        tooltip = "Dark panel behind the strip across the top of the board, so the cooldown and shield value read against it instead of against the world. Independent of the frame's own styled backdrop.",
        get = function() return CommanderPartyFramesDB.HeaderBackdrop end,
        set = function(value) CommanderPartyFramesDB.HeaderBackdrop = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
    })
    panel:AddCheckbox({
        label = "Hide Default Party Frames",
        tooltip = "Hide Blizzard's own party frames and run on this board alone. The header's stacked-rows button toggles the same setting, and |cffffd100/cpf blizzard|r works from anywhere — worth knowing, because this board is Priest/Mage/Druid/Paladin only and can hide itself. Changes apply out of combat; switching the module off gives the default frames back.",
        get = function() return CommanderPartyFramesDB.HideBlizzardParty end,
        set = function(value) CommanderPartyFramesDB.HideBlizzardParty = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
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

    AddBuffSection(panel, "PWS")

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
        label = "Target Marks",
        tooltip = "Show, at each row's right edge, the raid mark of the unit that ally is CURRENTLY targeting — watch your tank hold skull (or drift off it), and pair with the Assist click binding to jump onto their target.",
        get = function() return CommanderPartyFramesDB.ShowTargetMarks end,
        set = function(value) CommanderPartyFramesDB.ShowTargetMarks = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddCheckbox({
        label = "Color Shield Types",
        tooltip = "Tint each embedded shield segment by what it is — cream Power Word: Shield, vibrant blue Ice Barrier, blue-grey Mana Shield, ember/ice wards, dark grey Sacrifice. Off shows every shield as one classic cream overlay for a quieter bar.",
        get = function() return CommanderPartyFramesDB.ColorShieldTypes end,
        set = function(value) CommanderPartyFramesDB.ColorShieldTypes = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddDropdown(BAR_TEXTURE_OPTION)
    panel:AddDropdown(ICON_STYLE_OPTION)
    panel:AddCheckbox(SWEEP_EDGE_OPTION)
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

    panel:AddSection("Mouseover & Click", "Every modifier and button the client delivers. Click a cell to bind it, right-click to clear. Enabling needs a /reload and fixes the roster order.")
    panel:AddCheckbox({
        label = "Enable Row Clicks",
        tooltip = "Make each row a secure unit button bound to a fixed roster slot: hovering it targets that ally for your @mouseover cast macros, and each bound click casts its spell. Because secure frames cannot change in combat, the board uses a fixed roster order (no urgency sort) while this is on. Takes effect after a /reload.",
        get = function() return CommanderPartyFramesDB.ClickCast end,
        set = function(value) CommanderPartyFramesDB.ClickCast = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddDropdown({
        label = "Binding Profile",
        tooltip = "Which set of bindings is live. Follow Talent Build keys them to the tree you have most points in, so respeccing from your arena build to your PvE one brings back the bindings you left for it — this is a TBC client, so the talent build is what stands in for dual spec. Single Set keeps one profile whatever you respec into.",
        options = {
            { text = "Follow Talent Build", value = "TALENT" },
            { text = "Single Set", value = "FIXED" },
        },
        get = function() return CommanderPartyFramesDB.ClickProfileMode end,
        set = function(value)
            CommanderPartyFramesDB.ClickProfileMode = value
            if value == "FIXED" and (CommanderPartyFramesDB.ClickProfileFixed or "") == "" then
                CommanderPartyFramesDB.ClickProfileFixed =
                    CommanderPartyFrames_ActiveProfile and CommanderPartyFrames_ActiveProfile() or ""
            end
        end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ClickCast end,
    })
    AddClickMatrix(panel)

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
    panel:AddSection("Banner Buttons", "First Aid is not a class layer, so the bandage control rides this banner too.")
    panel:AddCheckboxPair({
        label = "Bandage",
        tooltip = "Add a First Aid button at the banner's right edge: left or right-click bandages a living friendly target (or yourself when you have none), the icon reddens with a countdown while Recently Bandaged blocks another, and middle-click opens the First Aid window.",
        get = function() return CommanderPartyFramesDB.ShowBandageButton end,
        set = function(value) CommanderPartyFramesDB.ShowBandageButton = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
        label = "Inventory Counters",
        tooltip = "Show how many bandages you are carrying over the button. The count keeps updating during a fight, when the button's binding itself cannot be re-aimed.",
        get = function() return CommanderPartyFramesDB.ShowUtilityCounts end,
        set = function(value) CommanderPartyFramesDB.ShowUtilityCounts = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield
            and CommanderPartyFramesDB.ShowBandageButton end,
    })

    panel:AddSection("Dispellable Debuffs", "A strip of icons to the right of each row showing debuffs you can remove — a priest dispels Magic and Disease — color-coded by school, with a glow on crowd control. A removable debuff also colors the whole row, and a teammate in crowd control turns it orange.")
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

    panel:AddCheckbox({
        label = "Banner Cooldowns",
        tooltip = "Show Pain Suppression, Power Infusion, Fear Ward, Psychic Scream, Silence, Inner Focus, Shadowfiend, Mass Dispel and Desperate Prayer on the banner — lit when ready, dimmed with the time left when not. Only the ones you have actually trained appear, so a holy priest never sees a Pain Suppression slot.",
        get = function() return CommanderPartyFramesDB.PriestBannerCooldowns end,
        set = function(value) CommanderPartyFramesDB.PriestBannerCooldowns = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowHeader end,
    })

    panel:AddSection("Your Hots", "Renew and Prayer of Mending on each ally, one fixed slot each on the left of the row, timed by a radial sweep — the same strip a druid's hots and a paladin's Hands ride. Which of them get a slot is set in the Ally Buffs grid above. The row's state stays what it has always been: the shield and the Weakened Soul lockout, because no hot outranks those on this board.")
    panel:AddCheckbox({
        label = "Refresh Flash",
        tooltip = "Pulse a hot's slot red while it is inside the refresh window below, so an about-to-drop Renew catches your eye. With this off the slot still tints amber — it just stops pulsing. This is the only warning the priest board gives about an expiring hot: on the druid and paladin boards the whole row changes colour, but here the row is busy saying something about the shield.",
        get = function() return CommanderPartyFramesDB.RenewFlash end,
        set = function(value) CommanderPartyFramesDB.RenewFlash = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })
    panel:AddSlider({
        label = "Refresh At",
        tooltip = "Treat one of your hots as expiring when this many seconds or fewer remain — its slot tints, and pulses if Refresh Flash is on.",
        min = 1, max = 10, step = 1,
        format = function(value) return string.format("%ds", value or 0) end,
        get = function() return CommanderPartyFramesDB.RenewRefreshAt end,
        set = function(value) CommanderPartyFramesDB.RenewRefreshAt = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    })

    panel:AddSection("Party Ability Bar", "A curated cooldown strip under every player: match-deciders always visible (lit = ready, swept = cooling), trinkets/racials surfacing only once spent, a red rim for lockouts (Hypothermia, Forbearance), and a gold pip when Cold Snap or Preparation can refund a cooldown. Learned from the combat log; spec-gated abilities appear once the spec is known.")
    panel:AddCheckboxPair({
        label = "Show Ability Bar",
        tooltip = "Master switch for the per-player cooldown strips.",
        get = function() return CommanderPartyFramesDB.ShowAbilityBar end,
        set = function(value) CommanderPartyFramesDB.ShowAbilityBar = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
    }, {
            label = "Include Your Row",
        tooltip = "Also show the strip under your own row — you know your cooldowns, but under pressure the sanity check is free.",
        get = function() return CommanderPartyFramesDB.AbilityBarSelf end,
        set = function(value) CommanderPartyFramesDB.AbilityBarSelf = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddCheckbox({
        label = "Mine Only",
        tooltip = "Show the strip under YOUR row and nobody else's. The narrowest the ability bar goes without switching it off — the reminder of your own cooldowns, without a wall of everyone else's. Needs Include Your Row on, or there would be nothing left to draw.",
        get = function() return CommanderPartyFramesDB.AbilityBarOnlySelf end,
        set = function(value) CommanderPartyFramesDB.AbilityBarOnlySelf = value end,
        isEnabled = function()
            return CommanderPartyFramesDB.EnableShield
                and CommanderPartyFramesDB.ShowAbilityBar
                and CommanderPartyFramesDB.AbilityBarSelf
        end,
    })
    panel:AddSlider({
        label = "Max Ability Icons",
        tooltip = "Most icons per strip; overflow evicts utility first, defensives last.",
        min = 3, max = 8, step = 1,
        format = "%.0f",
        get = function() return CommanderPartyFramesDB.AbilityMaxIcons end,
        set = function(value) CommanderPartyFramesDB.AbilityMaxIcons = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddCheckbox({
        label = "Cooldown Text",
        tooltip = "Show remaining time on cooling icons (hidden under 10s — the sweep carries it).",
        get = function() return CommanderPartyFramesDB.AbilityCdText end,
        set = function(value) CommanderPartyFramesDB.AbilityCdText = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddCheckbox({
        label = "Bar Backdrop",
        tooltip = "Dark panel behind each strip, sized to the icons actually shown — so a short strip leaves no bar hanging under the row, and an empty one draws nothing.",
        get = function() return CommanderPartyFramesDB.AbilityBarBackdrop end,
        set = function(value) CommanderPartyFramesDB.AbilityBarBackdrop = value end,
        isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
    })
    panel:AddButtonRow({
        {
            label = "Tracked Abilities…",
            width = 150,
            tooltip = "Open the tracked-abilities window — a dropdown per class choosing exactly which cooldowns its strip may show (also: /cpf abilities). New options ship unchecked, so the default strip is unchanged until you opt in.",
            onClick = function() CommanderPartyFrames_ToggleAbilityWindow() end,
            isEnabled = function() return CommanderPartyFramesDB.EnableShield and CommanderPartyFramesDB.ShowAbilityBar end,
        },
    })

    -- Chrome last, per the suite convention
    Commander.UI.AddHudChromeOptions(panel, CommanderPartyFramesDB, "Hud", {
        isEnabled = function() return CommanderPartyFramesDB.EnableShield end,
        onChanged = function() Commander.Notify(COMMANDER_PARTYFRAMES_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })

    -- Size the scroll child to the built content so the scrollbar has range
    panel:AddRefresher(function()
        scrollChild:SetHeight(panel._contentHeight + 24)
    end)
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

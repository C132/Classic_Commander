Commander = Commander or {}

local callbacks = {}

function Commander.AddListener(event, func)
    if not event then
        error("Event cannot be nil")
        return
    end

    if not func then
        error("Callback function cannot be nil")
        return
    end

    if not callbacks[event] then
        callbacks[event] = {}
    end

    for _, existing in ipairs(callbacks[event]) do
        if existing == func then
            return
        end
    end

    table.insert(callbacks[event], func)
end

function Commander.Notify(event, ...)
    if event and callbacks[event] then
        for _, func in ipairs(callbacks[event]) do
            local ok, err = pcall(func, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end

-- Legacy aliases so existing call sites keep working
AddListener = Commander.AddListener
Notify = Commander.Notify

local function CreateMainPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander"

    -- Same header the module pages get from UI.NewPanel
    local divider = Commander.UI.BuildPanelHeader(panel, {
        titleText = "Commander",
        addonName = "Commander_Events",
        description = "A modular, RTS-inspired command layer for the whole game, built on five pillars: Command & Control (comms, orders, rally points), Battle HUD (production, afflictions, vitals), Feedback & Alerts (momentum, impact, ceremony), Operations (economy, logistics, the mission board), and Interface (command card, bags, map, chat). Every module stands alone behind its own master switch and settings page in the list on the left; open this page any time with /commander.",
    })
    panel.ContentAnchor = divider

    return panel
end

-- Extension point for suite-level addons (Commander_Suite) to draw content on
-- the root Commander page. Builders run once, on the panel's first OnShow, so
-- they can rely on every module having registered by then; buildFn receives
-- (panel, anchor) where anchor is the header divider to build below.
local mainPanelBuilders = {}
local mainPanelBuilt = false

function Commander.AddMainPanelContent(buildFn)
    if type(buildFn) ~= "function" then
        error("Commander.AddMainPanelContent expects a function")
        return
    end
    table.insert(mainPanelBuilders, buildFn)
end

local function RunMainPanelBuilders()
    if mainPanelBuilt then return end
    mainPanelBuilt = true
    for _, buildFn in ipairs(mainPanelBuilders) do
        local ok, err = pcall(buildFn, Commander.MainPanel, Commander.MainPanel.ContentAnchor)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

Commander.MainPanel = CreateMainPanel()
Commander.MainPanel:HookScript("OnShow", RunMainPanelBuilders)
Commander.MainCategory = Settings.RegisterCanvasLayoutCategory(Commander.MainPanel, "Commander")
Commander.MainCategoryID = Commander.MainCategory:GetID()
Settings.RegisterAddOnCategory(Commander.MainCategory)

-- Legacy aliases so existing call sites keep working
MainPanel = Commander.MainPanel
MainCategory = Commander.MainCategory
MainCategoryID = Commander.MainCategoryID

-- ---------------------------------------------------------------------------
-- Reload-resilient session state. A module keeps its session-scoped
-- counters in db.Session and restores them through here: a brief
-- interruption (/reload, a quick relog) resumes the same session, a real
-- break starts fresh. Timestamps stored inside MUST be epoch time() —
-- GetTime() resets on client restart; convert at the call site. The hub
-- stamps every registered table at PLAYER_LOGOUT (which fires on /reload
-- too) and once a minute as a crash guard.
-- ---------------------------------------------------------------------------
local SESSION_RESUME_WINDOW = 600
local sessionTables = {}

local function StampSessions()
    local now = time()
    for _, db in ipairs(sessionTables) do
        if db.Session then
            db.Session.savedAt = now
        end
    end
end

-- Returns (session, fresh). fresh is true when a new session block was
-- started; false means the previous session resumed. defaults fills any
-- missing keys either way, so adding fields later is safe.
function Commander.RestoreSession(db, defaults)
    local session = db.Session
    local fresh = not (type(session) == "table" and session.savedAt
        and (time() - session.savedAt) < SESSION_RESUME_WINDOW)
    if fresh then
        session = {}
        db.Session = session
    end
    for key, value in pairs(defaults) do
        if session[key] == nil then
            session[key] = Commander.UI.CopyValue(value)
        end
    end
    session.savedAt = time()
    sessionTables[#sessionTables + 1] = db
    return session, fresh
end

local sessionStamper = CreateFrame("Frame")
sessionStamper:RegisterEvent("PLAYER_LOGOUT")
sessionStamper:SetScript("OnEvent", StampSessions)
C_Timer.NewTicker(60, StampSessions)

-- ---------------------------------------------------------------------------
-- Class identity: a shared per-class flavor layer so every module can give
-- each class its own colors, an RTS/RP unit title, a signature emote, and a
-- line of flavor — the throughline that makes each class feel like a distinct
-- unit across the suite. Commander.GetClassInfo() defaults to the player's
-- class and always returns a table (a neutral "Commander" fallback for
-- unknown tokens), memoized so callers on hot paths do not churn.
-- ---------------------------------------------------------------------------
local CLASS_IDENTITY = {
    WARRIOR = { title = "Vanguard",    emote = "FLEX",     line = "The Vanguard leans on his blade, itching for the horn of battle." },
    PALADIN = { title = "Templar",     emote = "SALUTE",   line = "The Templar keeps a silent vigil, armor gleaming, awaiting the call." },
    HUNTER  = { title = "Ranger",      emote = "WHISTLE",  line = "The Ranger checks her snares and scans the treeline for movement." },
    ROGUE   = { title = "Shadowblade", emote = "SHIFTY",   line = "The Shadowblade melts into the corner, coin and dagger in hand." },
    PRIEST  = { title = "Confessor",   emote = "PRAY",     line = "The Confessor bows her head, murmuring for those not yet fallen." },
    SHAMAN  = { title = "Farseer",     emote = "MEDITATE", line = "The Farseer listens to the elements whispering of distant storms." },
    MAGE    = { title = "Arcanist",    emote = "PONDER",   line = "The Arcanist traces idle runes, the weave humming at his fingertips." },
    WARLOCK = { title = "Diabolist",   emote = "CACKLE",   line = "The Diabolist trades whispers with something unseen, and it laughs." },
    DRUID   = { title = "Keeper",      emote = "ROAR",     line = "The Keeper breathes with the wilds, half-dreaming of fang and bark." },
}

local CLASS_ICON_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local classInfoCache = {}

-- Returns a table for the given class token (defaults to the player's class):
--   token, title, color {r,g,b}, colorMixin, emote (DoEmote token or nil),
--   line (RP flavor), icon (class-sheet path), iconCoords (CLASS_ICON_TCOORDS
--   entry or nil). Safe to call from PLAYER_LOGIN onward.
function Commander.GetClassInfo(classToken)
    if not classToken then
        local _, token = UnitClass("player")
        classToken = token or "UNKNOWN"
    end
    local cached = classInfoCache[classToken]
    if cached then return cached end
    local identity = CLASS_IDENTITY[classToken]
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    local info = {
        token = classToken,
        title = identity and identity.title or "Commander",
        emote = identity and identity.emote,
        line = identity and identity.line or "Awaiting orders, commander.",
        color = color and { color.r, color.g, color.b } or { 1, 1, 1 },
        colorMixin = color,
        icon = CLASS_ICON_SHEET,
        iconCoords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken],
    }
    classInfoCache[classToken] = info
    return info
end

-- ---------------------------------------------------------------------------
-- Shared icon art. Every Commander addon lists this one as a RequiredDep, so
-- the suite's icon shading lives here: one copy of the art, loaded before
-- anything that draws with it, rather than the same files in forty folders.
--
-- The shading is drawn OVER an icon at the icon's own size -- transparent
-- through the middle, dark where a recess blocks the light and bright where it
-- catches -- so a flat spell icon reads as set into the frame it sits in.
-- Squares for spell icons, discs for anything standing in for a portrait.
-- ---------------------------------------------------------------------------

local ICON_TEXTURES = "Interface\\AddOns\\Commander_Events\\Textures\\"

local DEBOSS_FILES = {
    SOFT   = ICON_TEXTURES .. "IconDebossSoft.png",
    DEEP   = ICON_TEXTURES .. "IconDebossDeep.png",
    CARVED = ICON_TEXTURES .. "IconDebossCarved.png",
}
local DEBOSS_ROUND_FILES = {
    SOFT   = ICON_TEXTURES .. "IconWellSoft.png",
    DEEP   = ICON_TEXTURES .. "IconWellDeep.png",
    CARVED = ICON_TEXTURES .. "IconWellCarved.png",
}
Commander.ICON_MASK = ICON_TEXTURES .. "IconCircleMask.png"

-- The styles offered, in the order a settings dropdown should list them
Commander.ICON_STYLES = {
    { text = "Flat", value = "OFF" },
    { text = "Soft", value = "SOFT" },
    { text = "Deep", value = "DEEP" },
    { text = "Carved", value = "CARVED" },
}

-- On screen only where BOTH are true: a style asked for it, and the icon it
-- shades is actually showing. The second half is the whole reason the wrapping
-- below exists.
local function SyncShade(icon)
    local shade = icon.commanderDeboss
    if not shade then return end
    if shade.commanderShadeOn and icon:IsShown() then shade:Show() else shade:Hide() end
end

-- Shade `icon` so it reads as recessed. Style is one of the values above (nil
-- or "OFF" takes the shading back off); `round` picks the disc art.
--
-- The shading texture is cached on the icon itself and tracks it with
-- SetAllPoints, so a caller may re-anchor or resize the icon freely and call
-- this again with the same style for free. Returns the texture, or nil if the
-- icon has no parent to draw on.
--
-- `manual` is for icons the addon does NOT own -- Blizzard's action button
-- art, most of all. Normally the icon's Show/Hide are wrapped so the shading
-- follows it; on a Blizzard texture that would mean Blizzard's own code
-- running an addon closure, and a tainted execution path through an action
-- button is how "Interface action failed because of an AddOn" happens. With
-- `manual` the wrapping is skipped and the CALLER owns the returned texture's
-- visibility.
function Commander.DebossIcon(icon, style, round, manual)
    if not (icon and icon.GetParent) then return nil end
    local file = style and (round and DEBOSS_ROUND_FILES or DEBOSS_FILES)[style]
    local shade = icon.commanderDeboss

    if not file then
        if shade then
            shade.commanderShadeOn = false
            shade:Hide()
        end
        return shade
    end

    if not shade then
        local parent = icon:GetParent()
        if not (parent and parent.CreateTexture) then return nil end
        -- One sublevel above the icon on the icon's own frame: over the art,
        -- under anything the frame draws on top of it
        local layer, sublevel = "ARTWORK", 0
        if icon.GetDrawLayer then
            local iconLayer, iconSublevel = icon:GetDrawLayer()
            layer = iconLayer or layer
            sublevel = iconSublevel or 0
        end
        shade = parent:CreateTexture(nil, layer, nil, sublevel + 1)
        shade:SetAllPoints(icon)
        icon.commanderDeboss = shade

        -- A texture has no OnShow to hook, and the icons this gets laid over
        -- are hidden and shown constantly -- an empty dispel slot, a row with
        -- no renew on it. Left to itself the shading would stay up over
        -- nothing, which is a row of lit rectangles hanging off an empty
        -- board. Wrapping the three visibility calls is what keeps the recess
        -- with the art it belongs to.
        shade.commanderManual = manual and true or false
        if not manual then
            local rawShow, rawHide, rawSetShown = icon.Show, icon.Hide, icon.SetShown
            icon.Show = function(self, ...)
                rawShow(self, ...)
                SyncShade(self)
            end
            icon.Hide = function(self, ...)
                rawHide(self, ...)
                SyncShade(self)
            end
            if rawSetShown then
                icon.SetShown = function(self, shown, ...)
                    rawSetShown(self, shown, ...)
                    SyncShade(self)
                end
            end
        end
    end

    if shade.commanderShadeFile ~= file then
        shade.commanderShadeFile = file
        shade:SetTexture(file)
    end
    shade.commanderShadeOn = true
    -- A manual shade belongs to the caller: this must not decide it is visible
    -- on their behalf, only hand it back
    if not shade.commanderManual then SyncShade(icon) end
    return shade
end

-- Round an icon off into a disc. Guarded and pcall-wrapped: a client without
-- mask textures keeps a square icon rather than losing it. Returns true if the
-- mask took.
function Commander.RoundIcon(icon)
    if not (icon and icon.AddMaskTexture and icon.GetParent) then return false end
    if icon.commanderRounded then return true end
    local parent = icon:GetParent()
    if not (parent and parent.CreateMaskTexture) then return false end
    local ok = pcall(function()
        local mask = parent:CreateMaskTexture()
        mask:SetTexture(Commander.ICON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end)
    icon.commanderRounded = ok
    return ok
end

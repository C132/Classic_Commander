-- Commander Bags harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- and the three Commander_Bags files under a permissive WoW mock, then drives
-- login and asserts what the bag grid actually draws: the quality ring, its
-- halo and thickness, the bind padlocks, and — the whole point of owning the
-- art — that a Blizzard container repaint cannot wash any of it out.
--
--   luajit bags_harness.lua
--
-- Mock notes: the scanning tooltip's TextLeftN font strings are globals the
-- addon reads by name, so SetBagItem has to publish them; C_Timer.NewTimer
-- feeds a cancellable queue because the refresh burst reschedules itself ten
-- times; textures record their vertex color and shown state, which is the only
-- way to see what the player would be looking at.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

function GetTime() return 1000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local caughtErrors = {}
local errorHandler = function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
function geterrorhandler() return errorHandler end
function seterrorhandler(fn) errorHandler = fn end

local frames = {}
local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetWidth = 0, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1,
}

local METHOD_PREFIXES = {
    "Set", "Enable", "Disable", "Register", "Unregister", "Clear",
    "Start", "Stop", "Raise", "Lower", "Lock", "Play", "Add", "Highlight",
}

local function IsAutoMethod(key)
    for _, prefix in ipairs(METHOD_PREFIXES) do
        if key:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateTexture" then
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "CreateFontString" then
        local fn = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn); return fn
    end
    if key == "HookScript" then
        local fn = function(s, name, handler)
            local prev = s.__scripts[name]
            if prev then
                s.__scripts[name] = function(...) prev(...) handler(...) end
            else
                s.__scripts[name] = handler
            end
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn); return fn
    end
    if key == "RegisterEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn); return fn
    end
    if key == "UnregisterEvent" then
        local fn = function(s, event)
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end
        rawset(self, key, fn); return fn
    end
    if key == "Show" then
        local fn = function(s)
            s.__shown = true
            if s.__scripts.OnShow then s.__scripts.OnShow(s) end
        end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s)
            s.__shown = false
            if s.__scripts.OnHide then s.__scripts.OnHide(s) end
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetShown" then
        local fn = function(s, v) if v then s:Show() else s:Hide() end end
        rawset(self, key, fn); return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn); return fn
    end
    -- The three writes worth remembering: what color a texture was tinted,
    -- where it was anchored, and how thick it was made
    if key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a or 1 } end
        rawset(self, key, fn); return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[point] = { rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
        end
        rawset(self, key, fn); return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = {} end
        rawset(self, key, fn); return fn
    end
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn); return fn
    end
    if key == "SetHeight" then
        local fn = function(s, h) s.__h = h end
        rawset(self, key, fn); return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
        rawset(self, key, fn); return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn); return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text end
        rawset(self, key, fn); return fn
    end
    if key == "SetChecked" then
        local fn = function(s, v) s.__checked = v and true or false end
        rawset(self, key, fn); return fn
    end
    if key == "GetChecked" then
        local fn = function(s) return s.__checked end
        rawset(self, key, fn); return fn
    end
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn); return fn
    end
    if key == "GetThumbTexture" then
        local fn = function() return NewWidget("Texture") end
        rawset(self, key, fn); return fn
    end
    if key == "GetName" then
        local fn = function(s) return s.__name end
        rawset(self, key, fn); return fn
    end
    if key == "GetParent" then
        local fn = function(s) return s.__parent end
        rawset(self, key, fn); return fn
    end
    if key == "GetFont" then
        local fn = function() return "Fonts\\FRIZQT__.TTF", 12, "" end
        rawset(self, key, fn); return fn
    end
    if key:sub(1, 2) == "Is" or key:sub(1, 3) == "Get" or key:sub(1, 3) == "Can"
        or key:sub(1, 4) == "Hook" then
        local fn = function() return nil end
        rawset(self, key, fn); return fn
    end
    if IsAutoMethod(key) then
        local fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({
        __kind = kind, __name = name, __scripts = {}, __shown = true,
    }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        f.TitleText = NewWidget("FontString")
        f.CloseButton = NewWidget("Button")
        f.NineSlice = NewWidget("Frame")
        f.Bg = NewWidget("Texture")
        f.TitleBg = NewWidget("Texture")
        f.Inset = NewWidget("Frame")
    end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
WorldFrame = NewWidget("Frame", "WorldFrame")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")

tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalHuge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}
UISpecialFrames = {}
SlashCmdList = {}
CANCEL, YES, NO = "Cancel", "Yes", "No"

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}

C_AddOns = { GetAddOnMetadata = function() return "2.2.0" end }

local timerQueue = {}
C_Timer = {
    After = function(_, fn) timerQueue[#timerQueue + 1] = { fn = fn } end,
    NewTicker = function() return { Cancel = function() end } end,
    NewTimer = function(_, fn)
        local entry = { fn = fn }
        entry.Cancel = function(self) (self or entry).cancelled = true end
        timerQueue[#timerQueue + 1] = entry
        return entry
    end,
}
local function FlushTimers()
    for _ = 1, 20 do
        if #timerQueue == 0 then return end
        local batch = timerQueue
        timerQueue = {}
        for _, entry in ipairs(batch) do
            if not entry.cancelled then entry.fn() end
        end
    end
end

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu() end
StaticPopupDialogs = {}
function StaticPopup_Show() return {} end
function IsShiftKeyDown() return false end
function InCombatLockdown() return false end
function hooksecurefunc(name, hook)
    local orig = _G[name]
    _G[name] = function(...)
        local r1, r2, r3 = orig(...)
        hook(...)
        return r1, r2, r3
    end
end

function GetRealmName() return "Aleria" end
function UnitName(unit) if unit == "player" then return "Devinq" end return nil end
function UnitClass(unit) if unit == "player" then return "Warrior", "WARRIOR" end return nil end
function UnitLevel() return 70 end
function UnitFactionGroup() return "Alliance" end
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior" }

ITEM_SOULBOUND = "Soulbound"
ITEM_BIND_ON_EQUIP = "Binds when equipped"
ITEM_BIND_ON_USE = "Binds when used"
ITEM_BIND_ON_PICKUP = "Binds when picked up"

NUM_BAG_SLOTS = 4
NUM_BAG_FRAMES = 4
NUM_CONTAINER_FRAMES = 13
function UpdateContainerFrameAnchors() end

-- ---------------------------------------------------------------------------
-- The world: two bags of fixtures covering every branch the painter has
-- ---------------------------------------------------------------------------

-- quality: 0 poor … 4 epic. bind: 0 none, 1 BoP, 2 BoE, 3 BoU, 4 quest.
-- bound: what the tooltip says for a BoE/BoU item sitting in the bag.
local ITEMS = {
    [101] = { quality = 4, bind = 1, name = "Epic Soulbound Helm" },
    [102] = { quality = 3, bind = 2, bound = false, name = "Rare BoE Shoulders" },
    [103] = { quality = 3, bind = 2, bound = true, name = "Rare BoE Already Worn" },
    [104] = { quality = 1, bind = 0, name = "Linen Cloth" },
    [105] = { quality = 0, bind = 0, name = "Broken Fang" },
    [106] = { quality = 1, bind = 0, use = true, name = "Healing Potion" },
    [107] = { quality = 1, bind = 4, quest = true, name = "Sealed Orders" },
    [108] = { quality = 2, bind = 3, bound = false, name = "Uncommon BoU Trinket" },
}

-- bagID -> slot -> itemID
local world = {
    [0] = { 101, 102, 103, 104, 105, 106, 107, 108 },
    [1] = { 101, nil, 102 },
}

local uncached = {}   -- itemIDs the client has not resolved yet

C_Container = {
    GetContainerNumSlots = function(bag) return world[bag] and 8 or 0 end,
    GetContainerItemID = function(bag, slot) return world[bag] and world[bag][slot] or nil end,
    GetContainerItemLink = function(bag, slot)
        local id = world[bag] and world[bag][slot]
        return id and ("|Hitem:" .. id .. ":0|h[x]|h") or nil
    end,
    GetContainerItemInfo = function(bag, slot)
        local id = world[bag] and world[bag][slot]
        if not id then return nil end
        local it = ITEMS[id]
        -- No isBound field: this client's struct may not carry it, so the
        -- tooltip fallback is what the harness exercises
        return { itemID = id, quality = it.quality, hyperlink = "|Hitem:" .. id .. ":0|h[x]|h" }
    end,
    GetContainerNumFreeSlots = function() return 0, 0 end,
    PickupContainerItem = function() end,
}

local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 },
}

C_Item = {
    GetItemInfo = function(id)
        local it = ITEMS[id]
        if not it or uncached[id] then return nil end
        return it.name, "|Hitem:" .. id .. ":0|h[x]|h", it.quality, 100,
            1, "Armor", "Cloth", 1, "INVTYPE_HEAD", 134400, 100, 4, 0, it.bind
    end,
    GetItemInfoInstant = function(id) return id, "Armor", "Cloth", "INVTYPE_HEAD", 134400, 4, 0 end,
    GetItemQualityColor = function(q)
        local c = QUALITY_COLORS[q] or QUALITY_COLORS[1]
        return c[1], c[2], c[3]
    end,
    GetItemCount = function() return 1 end,
}

-- Blizzard's own quality border, and the pass that repaints it. The real
-- ContainerFrame_Update calls this on every bag event; the harness calls it
-- directly to prove the drawn ring survives.
function SetItemButtonQuality(button, quality, link)
    if not button.IconBorder then return end
    if quality and quality > 1 then
        button.IconBorder:Show()
        button.IconBorder:SetVertexColor(C_Item.GetItemQualityColor(quality))
    else
        button.IconBorder:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Container frames, built the way ContainerFrame_GenerateFrame builds them
-- ---------------------------------------------------------------------------

local function BuildContainerFrame(index, bagID, size)
    local name = "ContainerFrame" .. index
    local f = CreateFrame("Frame", name, UIParent)
    f.size = size
    rawset(f, "GetID", function() return bagID end)
    f.__shown = true
    for slot = 1, size do
        local button = CreateFrame("Button", name .. "Item" .. slot, f)
        rawset(button, "GetID", function() return slot end)
        button.icon = button:CreateTexture()
        button.IconBorder = button:CreateTexture()
        button.IconBorder.__shown = false
    end
    return f
end

BuildContainerFrame(1, 0, 8)
BuildContainerFrame(2, 1, 8)

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Class Color", value = "CLASS" },
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Bags/CommanderBagsDB.lua")
Load(ADDONS .. "/Commander_Bags/CommanderBagsSort.lua")
Load(ADDONS .. "/Commander_Bags/CommanderBags.lua")

-- The scanning tooltip is created by the addon itself; wire its bind lines up
-- now that it exists. The addon reads TextLeftN by global name, so publish
-- them the same way the client does.
local scanLines = {}
for i = 1, 12 do
    scanLines[i] = NewWidget("FontString")
    _G["CommanderBagsScanningTooltipTextLeft" .. i] = scanLines[i]
end

local scanCount = 0
local st = _G.CommanderBagsScanningTooltip
assert(st, "the addon never created its scanning tooltip")
local scanNumLines = 0
rawset(st, "ClearLines", function()
    for i = 1, 12 do scanLines[i]:SetText(nil) end
    scanNumLines = 0
end)
rawset(st, "NumLines", function() return scanNumLines end)
rawset(st, "SetBagItem", function(_, bag, slot)
    scanCount = scanCount + 1
    local id = world[bag] and world[bag][slot]
    local it = id and ITEMS[id]
    if not it then scanNumLines = 0 return end
    local lines = { it.name }
    if it.bind == 1 then
        lines[#lines + 1] = ITEM_SOULBOUND
    elseif it.bind == 2 then
        lines[#lines + 1] = it.bound and ITEM_SOULBOUND or ITEM_BIND_ON_EQUIP
    elseif it.bind == 3 then
        lines[#lines + 1] = it.bound and ITEM_SOULBOUND or ITEM_BIND_ON_USE
    elseif it.bind == 4 then
        lines[#lines + 1] = "Quest Item"
    end
    if it.use then lines[#lines + 1] = "Use: Restores health." end
    for i, text in ipairs(lines) do scanLines[i]:SetText(text) end
    scanNumLines = #lines
end)

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snapshot = {}
    for i, frame in ipairs(list) do snapshot[i] = frame end
    for _, frame in ipairs(snapshot) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- ===========================================================================
-- Helpers
-- ===========================================================================

local function Button(frameIndex, slot)
    return _G["ContainerFrame" .. frameIndex .. "Item" .. slot]
end

local function RingColor(button)
    local ring = button.cbRing
    if not (ring and ring[1].__shown) then return nil end
    return ring[1].__color
end

local function ColorIs(color, r, g, b)
    if not color then return false end
    local function near(a, x) return math.abs(a - x) < 0.001 end
    return near(color[1], r) and near(color[2], g) and near(color[3], b)
end

local function BadgeState(button)
    local badge = button.cbBadge
    if not (badge and badge.plate.__shown) then return "none" end
    return badge.postR.__shown and "closed" or "open"
end

local function Settle()
    Fire("BAG_UPDATE")
    FlushTimers()
end

-- ===========================================================================
-- Login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Bags")
Fire("PLAYER_LOGIN")
FlushTimers()

CHECK(#caughtErrors == 0, "login raised no errors", caughtErrors[1])

-- ---------------------------------------------------------------------------
-- The ring: drawn, opaque, and in the item's own quality color
-- ---------------------------------------------------------------------------

local epic = Button(1, 1)
CHECK(ColorIs(RingColor(epic), 0.64, 0.21, 0.93), "epic slot draws the epic ring")
CHECK(RingColor(epic)[4] == 1, "the ring is fully opaque, not a fade")
CHECK(epic.cbRing[5].__shown, "the halo ring is drawn alongside it")
CHECK(math.abs(epic.cbRing[5].__color[4] - 0.4) < 0.001, "the halo is the faint one")
CHECK(epic.IconBorder.__shown == false, "Blizzard's soft border is put away")

local rare = Button(1, 2)
CHECK(ColorIs(RingColor(rare), 0, 0.44, 0.87), "rare slot draws the rare ring")

local white = Button(1, 4)
CHECK(RingColor(white) == nil, "common items stay unringed")

local junk = Button(1, 5)
CHECK(ColorIs(RingColor(junk), 1, 0.1, 0.1), "gray junk rings red")

local potion = Button(1, 6)
CHECK(ColorIs(RingColor(potion), 0, 0.8, 1), "consumables ring cyan")

local quest = Button(1, 7)
CHECK(ColorIs(RingColor(quest), 1, 0.82, 0), "quest items ring yellow")

CHECK(epic.cbThickness == 2, "the default ring is two pixels")
CHECK(epic.cbRing[1].__h == 2, "the top quad is laid out at that thickness")

-- ---------------------------------------------------------------------------
-- The whole point: a Blizzard repaint cannot wash the ring out
-- ---------------------------------------------------------------------------

SetItemButtonQuality(epic, 4, "|Hitem:101:0|h[x]|h")
CHECK(ColorIs(RingColor(epic), 0.64, 0.21, 0.93), "the ring survives a Blizzard repaint")
CHECK(epic.IconBorder.__shown == false, "and Blizzard's border is hidden again on the way past")

-- A settled slot must not silently keep a stomped color either: run the whole
-- refresh burst again and confirm nothing drifted
Settle()
CHECK(ColorIs(RingColor(epic), 0.64, 0.21, 0.93), "and after a full refresh burst")

-- ---------------------------------------------------------------------------
-- Bind badges
-- ---------------------------------------------------------------------------

CHECK(BadgeState(epic) == "closed", "a bind-on-pickup item reads as soulbound")
CHECK(BadgeState(rare) == "open", "an unbound BoE reads as open")
CHECK(BadgeState(Button(1, 3)) == "closed", "a BoE that has already bound reads as closed")
CHECK(BadgeState(Button(1, 8)) == "open", "an unbound bind-on-use reads as open")
CHECK(BadgeState(white) == "none", "a trade good that never binds gets no padlock")
CHECK(BadgeState(potion) == "none", "and neither does a plain consumable")

local openColor = rare.cbBadge.body.__color
CHECK(openColor[1] == 1 and openColor[2] == 0.84, "the open padlock is gold")
local closedColor = epic.cbBadge.body.__color
CHECK(closedColor[1] < 0.9, "the closed padlock is the quieter steel")

CHECK(rare.cbBindUnstable == true, "a BoE slot stays watched for binding in place")
CHECK(epic.cbBindUnstable == false, "a bind-on-pickup slot does not")

-- Bind it where it sits; the watched slot must notice without the item changing
ITEMS[102].bound = true
Settle()
CHECK(BadgeState(rare) == "closed", "a BoE that binds in place flips to closed")
ITEMS[102].bound = false
Settle()

-- ---------------------------------------------------------------------------
-- Settings reach the art
-- ---------------------------------------------------------------------------

CommanderBagsDB.BindBadges = "BOE"
Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
FlushTimers()
CHECK(BadgeState(rare) == "open", "BoE-only keeps the badge that matters")
CHECK(BadgeState(epic) == "none", "and drops the soulbound one")

CommanderBagsDB.BindBadges = "OFF"
Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
FlushTimers()
CHECK(BadgeState(rare) == "none", "off means off")

CommanderBagsDB.BindBadges = "BOTH"
CommanderBagsDB.BorderThickness = 4
CommanderBagsDB.RarityHalo = false
Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
FlushTimers()
CHECK(epic.cbThickness == 4, "a thicker border is re-laid out, not just re-tinted")
CHECK(epic.cbRing[1].__h == 4, "the quad grew with it")
CHECK(epic.cbRing[5].__shown == false, "the halo can be turned off")
CHECK(BadgeState(epic) == "closed", "and the badges come back")

CommanderBagsDB.BorderThickness = 2
CommanderBagsDB.RarityHalo = true
CommanderBagsDB.ColorCodeItems = false
Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
FlushTimers()
CHECK(RingColor(epic) == nil, "turning coloring off takes the ring down")
CHECK(BadgeState(epic) == "none", "and the badge with it")
CHECK(epic.IconBorder.__shown == true, "and hands the slot back to Blizzard's own border")

CommanderBagsDB.ColorCodeItems = true
Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
FlushTimers()
CHECK(ColorIs(RingColor(epic), 0.64, 0.21, 0.93), "turning it back on repaints everything")

-- ---------------------------------------------------------------------------
-- Empty slots, uncached items, and the cost of it all
-- ---------------------------------------------------------------------------

CHECK(RingColor(Button(2, 2)) == nil, "an empty slot draws nothing")
CHECK(BadgeState(Button(2, 2)) == "none", "and carries no badge")

world[0][1] = nil
Settle()
CHECK(RingColor(epic) == nil, "emptying a slot clears its ring")
CHECK(BadgeState(epic) == "none", "and its badge")
world[0][1] = 101
Settle()
CHECK(ColorIs(RingColor(epic), 0.64, 0.21, 0.93), "and refilling it paints again")

-- An item the client has not cached yet must be left unmemoized so the
-- refresh window comes back for it
uncached[104] = true
world[0][4] = nil
Settle()
world[0][4] = 104
Settle()
CHECK(Button(1, 4).cbItemID == nil, "an uncached item is not memoized")
uncached[104] = nil
Settle()
CHECK(Button(1, 4).cbItemID == 104, "and is picked up once its data lands")

-- Tooltip scans are the expensive part; only bind-on-equip slots may pay per
-- pass, and there are three of those across both bags
local before = scanCount
Settle()
local perBurst = scanCount - before
CHECK(perBurst <= 8, "a settled refresh burst scans each BoE slot once, not once per pass", perBurst)
io.write(("  (settled burst cost: %d tooltip scans across 16 slots)\n"):format(perBurst))

CHECK(#caughtErrors == 0, "nothing errored across the whole run", caughtErrors[1])

io.write(("\n%d checks, %d failures\n"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)

-- Commander Spellbook: the cast buttons.
--
-- Casting is protected: only a SecureActionButton may cast a spell for a
-- click. But every ANCESTOR of a secure button, and every frame one is
-- anchored to, joins its protected family and is locked in combat — Show,
-- Hide, SetSize, SetPoint all blocked (the suite's field record:
-- Tradecraft's holders, Commander_Buffs' icons, Party Frames' banner). A
-- spellbook is opened, scrolled and searched mid-fight, so the window must
-- never be in that family. The rules Tradecraft 1.0.1 settled, applied here:
--
--   * The cast buttons are SIBLINGS of the window, parented to UIParent and
--     PINNED TO THE SCREEN over the region they cast for (a row's icon, a
--     rank chip, the Cast button). Never anchored to it: placed at its
--     absolute rect, scaled to its effective scale, re-placed when the window
--     moves, scrolls or rescales.
--   * They are only placed, shown, hidden or re-aimed OUT of combat. As
--     combat starts they are all put away (PLAYER_REGEN_DISABLED is
--     dispatched before the lockdown lands), a combat repaint never touches
--     them, and PLAYER_REGEN_ENABLED lays them out again. In combat the book
--     still opens, scrolls, searches and drags; it does not cast.
--
-- A button casts on the mouse's UP stroke whatever the ActionButtonUseKeyDown
-- CVar says (the useOnKeyDown attribute, SecureTemplates.lua): a press that
-- turns into a drag must not cast first. Left-click casts; right-click on a
-- pet ability toggles its autocast (/petautocasttoggle is a secure command,
-- so it goes through a macro), and does nothing secure on anything else;
-- shift-click casts nothing and links. The module's own right-click (select)
-- and the link run from a post-hook.

CommanderSpellbook = CommanderSpellbook or {}
local S = CommanderSpellbook

S.Cast = S.Cast or {}
local C = S.Cast

local pool = {}
local host          -- the window
local placedFor     -- the window's corner and scale the current placement used

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

C.InCombat = InCombat

local function Acquire(i)
    if pool[i] then return pool[i] end
    if InCombat() then return nil end
    local b = CreateFrame("Button", "CommanderSpellbookCast" .. i, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnEnter", function(self)
        local t = self.target
        if t and t.onEnter then t.onEnter(self, t) end
    end)
    b:SetScript("OnLeave", function(self)
        local t = self.target
        if t and t.onLeave then t.onLeave(self, t) end
    end)
    b:SetScript("OnDragStart", function(self)
        local t = self.target
        if t and t.onDrag then t.onDrag(self, t) end
    end)
    -- Shift-click links, as it does in the stock book: the shift attributes
    -- below cast nothing, and the link is put in the chat box from here
    b:HookScript("OnClick", function(self, button)
        local t = self.target
        if not t then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            if t.onLink then t.onLink(self, t) end
            return
        end
        if t.onClick then t.onClick(self, button, t) end
    end)
    b:Hide()
    pool[i] = b
    return b
end

-- Attributes are written only when they change: a placement pass runs on
-- every scroll, and most rows keep their spell
local function SetAttr(b, key, value)
    if b._attr == nil then b._attr = {} end
    if b._attr[key] ~= value then
        b._attr[key] = value
        b:SetAttribute(key, value)
    end
end

local function Bind(b, t)
    SetAttr(b, "shift-type1", "")
    SetAttr(b, "shift-type2", "")
    if t.pet then
        SetAttr(b, "type", "spell")
        SetAttr(b, "spell", t.pet)
        if t.autocast then
            SetAttr(b, "type2", "macro")
            SetAttr(b, "macrotext2", "/petautocasttoggle " .. t.pet)
        else
            SetAttr(b, "type2", "")
            SetAttr(b, "macrotext2", nil)
        end
    else
        SetAttr(b, "type", "spell")
        SetAttr(b, "spell", t.spell)
        SetAttr(b, "type2", "")
        SetAttr(b, "macrotext2", nil)
    end
end

-- The region's rect, if all of it is inside the clip frame (a scroll
-- frame's viewport). A row half scrolled out of view gets no button: one
-- there would catch clicks meant for the toolbar above it.
local function Rect(region, clip)
    if not (region and region.IsVisible and region:IsVisible()) then return nil end
    local left, top = region:GetLeft(), region:GetTop()
    local width, height = region:GetWidth(), region:GetHeight()
    if not (left and top and width and height) or width <= 0 or height <= 0 then return nil end
    if clip then
        local cl, ct, cb, cr = clip:GetLeft(), clip:GetTop(), clip:GetBottom(), clip:GetRight()
        if not (cl and ct and cb and cr) then return nil end
        local slack = 0.5
        if top > ct + slack or top - height < cb - slack then return nil end
        if left < cl - slack or left + width > cr + slack then return nil end
    end
    return left, top, width, height
end

local function Pin(b, region, left, top, width, height)
    local ui = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    local scale = ((region.GetEffectiveScale and region:GetEffectiveScale()) or ui) / ui
    local p = b._pinned
    if p and p[1] == left and p[2] == top and p[3] == width and p[4] == height and p[5] == scale then return end
    b._pinned = { left, top, width, height, scale }
    b:SetScale(scale)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    b:SetSize(width, height)
end

-- What a placement depends on besides the rows: the window's corner, its
-- scale, and its frame level (a click raises a toplevel window, and buttons
-- left at the old level would end up under the icons they cast for)
local function HostCorner()
    if not host then return nil end
    return { host:GetLeft(), host:GetTop(), host:GetEffectiveScale(), host:GetFrameLevel() }
end

-- Place one button over each target that is on screen, and put the rest
-- away. targets: { region = frame, clip = scroll frame or nil, spell = id |
-- pet = name, autocast, onEnter/onLeave/onDrag/onClick(button, ..., target) }.
-- Out of combat only; in combat the buttons are already away and stay so.
-- Returns how many were placed.
function C.Place(targets)
    if InCombat() then return 0 end
    local strata = host and host:GetFrameStrata() or "HIGH"
    local level = ((host and host:GetFrameLevel()) or 1) + 30
    local n = 0
    for _, t in ipairs(targets or {}) do
        if t.spell or t.pet then
            local left, top, width, height = Rect(t.region, t.clip)
            if left then
                local b = Acquire(n + 1)
                if not b then break end
                n = n + 1
                b.target = t
                if b:GetFrameStrata() ~= strata then b:SetFrameStrata(strata) end
                if b:GetFrameLevel() ~= level then b:SetFrameLevel(level) end
                Bind(b, t)
                Pin(b, t.region, left, top, width, height)
                if not b:IsShown() then b:Show() end
            end
        end
    end
    for i = n + 1, #pool do
        local b = pool[i]
        b.target = nil
        if b:IsShown() then b:Hide() end
    end
    placedFor = HostCorner()
    return n
end

-- Every button away. Safe out of combat and inside the PLAYER_REGEN_DISABLED
-- handler; a no-op once the lockdown is up (they were put away as it began).
function C.Withdraw()
    if InCombat() then return end
    for _, b in ipairs(pool) do
        b.target = nil
        if b:IsShown() then b:Hide() end
    end
    placedFor = nil
end

-- The window the buttons follow, and what to call when they need placing
-- again: onLayout() after combat, after the window moved or rescaled
function C.Attach(window, onLayout)
    host = window
    C.onLayout = onLayout
    if window and window.SetScale then
        pcall(hooksecurefunc, window, "SetScale", function()
            if C.onLayout and not InCombat() then C.onLayout() end
        end)
    end
end

function C.Shown()
    local n = 0
    for _, b in ipairs(pool) do if b:IsShown() then n = n + 1 end end
    return n
end

function C._Pool() return pool end

-- A drag of the window moves it with StartMoving (no SetPoint to hook), a
-- click raises it, and the buttons are pinned to the screen: watch the
-- corner and the level ten times a second while anything is placed
local watch = CreateFrame("Frame")
local elapsedSince = 0
watch:SetScript("OnUpdate", function(_, elapsed)
    elapsedSince = elapsedSince + (elapsed or 0)
    if elapsedSince < 0.1 then return end
    elapsedSince = 0
    if not (host and placedFor and host:IsShown()) or InCombat() then return end
    local left, top, scale = host:GetLeft(), host:GetTop(), host:GetEffectiveScale()
    if left ~= placedFor[1] or top ~= placedFor[2] or scale ~= placedFor[3]
        or host:GetFrameLevel() ~= placedFor[4] then
        if C.onLayout then C.onLayout() end
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Synchronously: this handler runs before the lockdown lands, and a
        -- C_Timer.After(0) would already be too late
        C.Withdraw()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if C.onLayout and host and host:IsShown() then C.onLayout() end
    end
end)

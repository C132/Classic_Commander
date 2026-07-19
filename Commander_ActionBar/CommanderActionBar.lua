local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_STARTED_MOVING")
frame:RegisterEvent("PLAYER_STOPPED_MOVING")
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Re-apply deferred layout after combat (protected frames are locked in combat)
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
local loaded = false
local inCombat = false

local backdrop
-- Set when a layout pass is skipped due to combat lockdown; applied on PLAYER_REGEN_ENABLED
local pendingUpdate = false

local function DB()
    return CommanderActionBarDB
end

-- ---------------------------------------------------------------------------
-- Default-UI suppression
-- ---------------------------------------------------------------------------
-- Frame names for the 2.5.5 (Anniversary) client; looked up by name so a missing
-- frame is skipped instead of truncating the list.
-- NOTE: everything here must be a plain (insecure) frame whose Hide() is the raw
-- widget method. StanceBar must NOT go in this list -- see SuppressStanceBar below.
local elementsToHide = {
    "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarTexture0", "MainMenuBarTexture1", "MainMenuBarTexture2", "MainMenuBarTexture3",
    "MainMenuMaxLevelBar0", "MainMenuMaxLevelBar1", "MainMenuMaxLevelBar2", "MainMenuMaxLevelBar3",
    "StatusTrackingBarManager",
    "MainMenuBarBackpackButton", "MainMenuBarPerformanceBarFrame",
}

local microButtons = {
    "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
    "GuildMicroButton", "WorldMapMicroButton", "SocialsMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}

-- StanceBar can't be hidden with Hide(): it inherits EditModeActionBarTemplate, so
-- Hide() is really EditModeActionBarMixin:HideOverride, which writes
-- StanceBar.isShownExternal and re-runs UpdateVisibility -> SetShownBase
-- (Blizzard_ActionBar/Shared/ActionBar.lua). Calling that from addon code taints
-- isShownExternal; StanceBar's own PLAYER_REGEN_ENABLED/DISABLED handler then reads
-- it inside UpdateVisibility during combat and trips ADDON_ACTION_BLOCKED
-- ("StanceBar:SetShownBase()") even when our call happened out of combat. Instead,
-- park the bar under a permanently hidden holder: SetParent is not overridden by the
-- Edit Mode mixin and writes no Lua state on the bar, so Blizzard's visibility code
-- stays untainted and the bar (with its secure stance buttons) renders and clicks
-- nothing. The Show Stance Bar feature reverses the parking the same taint-free way.
local hiddenHolder = CreateFrame("Frame", nil, UIParent)
hiddenHolder:Hide()

local function ApplyStanceBar()
    if not StanceBar then return end
    if DB().showStanceBar then
        if StanceBar:GetParent() == hiddenHolder then
            StanceBar:SetParent(UIParent)
        end
        if backdrop then
            StanceBar:ClearAllPoints()
            StanceBar:SetPoint("BOTTOMLEFT", backdrop, "TOPLEFT", 0, 30)
            StanceBar:SetScale(0.8)
        end
    elseif StanceBar:GetParent() ~= hiddenHolder then
        StanceBar:SetParent(hiddenHolder)
    end
end

local function ApplyMicroMenu()
    if DB().showMicroMenu then
        local previous
        for _, name in ipairs(microButtons) do
            local button = _G[name]
            if button then
                button:Show()
                button:SetScale(DB().microMenuScale or 0.9)
                button:ClearAllPoints()
                if previous then
                    button:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 1, 0)
                else
                    button:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -120, 2)
                end
                previous = button
            end
        end
    else
        for _, name in ipairs(microButtons) do
            local button = _G[name]
            if button then button:Hide() end
        end
    end
end

local function ApplyBagButtons()
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:SetShown(DB().showBagButtons)
            if bagButton:IsShown() then
                bagButton:SetScale(DB().bagButtonScale or 1)
                bagButton:ClearAllPoints()
                local mode = DB().bagPosition or "BOTTOMRIGHT"
                local step = DB().bagVertical and (i * 42) or 0
                local slide = DB().bagVertical and 0 or (i * 42)
                if mode == "BOTTOMLEFT" then
                    bagButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 300 + slide, 8 + step)
                elseif mode == "CARD" and backdrop then
                    bagButton:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMRIGHT", 6 + slide, 4 + step)
                else
                    bagButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300 - slide, 8 + step)
                end
            end
        end
    end
    local keyring = _G["KeyRingButton"]
    if keyring then
        keyring:SetShown(DB().showKeyring)
        if keyring:IsShown() then
            keyring:ClearAllPoints()
            keyring:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -300, 178)
        end
    end
end

local function HideDefaults()
    -- StanceBar reparenting and the bag slots are blocked in combat; defer
    -- the whole pass to PLAYER_REGEN_ENABLED while in lockdown
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    ApplyStanceBar()
    for _, name in ipairs(elementsToHide) do
        local element = _G[name]
        if element then
            element:Hide()
        end
    end
    -- Page number and up/down arrows live on MainActionBar now
    if MainActionBar and MainActionBar.ActionBarPageNumber then
        MainActionBar.ActionBarPageNumber:Hide()
    end
    ApplyMicroMenu()
    ApplyBagButtons()
end

-- ---------------------------------------------------------------------------
-- The card: framing, tint, fade
-- ---------------------------------------------------------------------------
local CARD_STYLES = {
    CLASSIC = {
        bgFile = "Interface\\BankFrame\\Bank-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    DARK = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
}

local BORDER_TINTS = {
    WHITE = { 1, 1, 1 },
    GOLD = { 1, 0.82, 0.15 },
    GREEN = { 0.3, 1, 0.4 },
}

local function BorderColor()
    if DB().combatGlow and inCombat then
        return 1, 0.25, 0.2
    end
    local tint = DB().borderTint or "WHITE"
    if tint == "CLASS" then
        local _, classToken = UnitClass("player")
        local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if color then return color.r, color.g, color.b end
    end
    local rgb = BORDER_TINTS[tint] or BORDER_TINTS.WHITE
    return rgb[1], rgb[2], rgb[3]
end

local function ApplyCardStyle()
    if not backdrop then return end
    local style = CARD_STYLES[DB().cardStyle or "CLASSIC"]
    if backdrop._appliedStyle ~= (DB().cardStyle or "CLASSIC") then
        backdrop._appliedStyle = DB().cardStyle or "CLASSIC"
        backdrop:SetBackdrop(style)  -- nil clears for NONE
    end
    if style then
        local opacity = DB().cardOpacity or 1
        if backdrop._appliedStyle == "DARK" then
            backdrop:SetBackdropColor(0, 0, 0, 0.7 * opacity)
        else
            backdrop:SetBackdropColor(0.5, 0.5, 0.5, opacity)
        end
        local r, g, b = BorderColor()
        backdrop:SetBackdropBorderColor(r, g, b, opacity)
    end
end

local function SetLockState()
    if not DB().locked then
        backdrop:SetMovable(true)
        backdrop:EnableMouse(true)
        backdrop:RegisterForDrag("LeftButton")
        backdrop:SetScript("OnDragStart", backdrop.StartMoving)
        backdrop:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
            DB().position = {point = point, relativePoint = relativePoint, xOfs = xOfs, yOfs = yOfs}
            Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
        end)
    else
        backdrop:SetMovable(false)
        backdrop:EnableMouse(false)
    end
end

-- Anchor the backdrop from the saved position so Reset visually restores the
-- default position without a reload
local function ApplyPosition()
    if not backdrop then return end
    backdrop:ClearAllPoints()
    if DB().position and DB().position.point then
        backdrop:SetPoint(
            DB().position.point,
            UIParent,
            DB().position.relativePoint,
            DB().position.xOfs,
            DB().position.yOfs
        )
    else
        backdrop:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function CreateRTSBackdrop()
    if backdrop then return backdrop end
    backdrop = CreateFrame("Frame", "RTSActionBarBackdrop", UIParent, "BackdropTemplate")
    backdrop:SetFrameStrata("BACKGROUND")
    ApplyPosition()
    backdrop:SetSize(274, 190)
    ApplyCardStyle()
    SetLockState()
    return backdrop
end

-- ---------------------------------------------------------------------------
-- Button grid
-- ---------------------------------------------------------------------------
local managedButtons = {}

local function CollectButtons()
    wipe(managedButtons)
    for i = 1, 12 do
        managedButtons[#managedButtons + 1] = _G["ActionButton" .. i]
    end
    if DB().includeBottomLeft ~= false then
        for i = 1, 12 do
            managedButtons[#managedButtons + 1] = _G["MultiBarBottomLeftButton" .. i]
        end
    end
    if DB().includeRightBars then
        for i = 1, 12 do
            managedButtons[#managedButtons + 1] = _G["MultiBarRightButton" .. i]
        end
        for i = 1, 12 do
            managedButtons[#managedButtons + 1] = _G["MultiBarLeftButton" .. i]
        end
    end
end

local PUSHED_COLORS = {
    CYAN = { 0, 1, 1, 0.3 },
    GOLD = { 1, 0.82, 0.15, 0.35 },
    GREEN = { 0.3, 1, 0.4, 0.3 },
    RED = { 1, 0.25, 0.2, 0.35 },
}

local function MoveActionButtons()
    -- Action buttons are protected; Show/SetPoint on them is blocked in combat
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    CollectButtons()
    local buttonSize = DB().buttonSize or 32
    local spacing = DB().buttonSpacing or 10
    local perRow = DB().buttonsPerRow or 6
    local pad = DB().gridPadding or 14
    local cardScale = DB().cardScale or 1
    local reverse = DB().reverseRows

    local count = 0
    for _, button in ipairs(managedButtons) do
        if button then count = count + 1 end
    end
    local rows = math.max(math.ceil(count / perRow), 1)

    backdrop:SetScale(cardScale)
    backdrop:SetSize(
        perRow * (buttonSize + spacing) - spacing + pad * 2,
        rows * (buttonSize + spacing) - spacing + pad * 2)

    local index = 0
    for _, button in ipairs(managedButtons) do
        if button then
            index = index + 1
            button:ClearAllPoints()
            button:SetScale(cardScale)
            button:SetSize(buttonSize, buttonSize)
            local row = math.ceil(index / perRow)
            if reverse then
                row = rows - row + 1
            end
            local col = (index - 1) % perRow + 1
            local xOffset = (col - 1) * (buttonSize + spacing) + pad
            local yOffset = (row - 1) * (buttonSize + spacing) + pad
            button:SetPoint("TOPLEFT", backdrop, "TOPLEFT", xOffset, -yOffset)
            button:Show()
            local pushedTexture = button:GetPushedTexture()
            if pushedTexture then
                local flash = PUSHED_COLORS[DB().pushedFlash or "CYAN"]
                if flash then
                    pushedTexture:SetColorTexture(flash[1], flash[2], flash[3], flash[4])
                end
            end
        end
    end
end

local function MovePetBar()
    -- PetActionBar is EditMode-managed and protected in combat
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    if not PetActionBar then return end
    local mode = DB().petBarPosition or "ABOVE"
    if mode == "HIDDEN" then
        PetActionBar:Hide()
        return
    end
    if PetActionBar:IsShown() then
        PetActionBar:ClearAllPoints()
        if mode == "LEFT" then
            PetActionBar:SetPoint("RIGHT", backdrop, "LEFT", -6, 0)
        else
            PetActionBar:SetPoint("BOTTOM", backdrop, "TOP", 10, 5)
        end
        PetActionBar:SetScale(DB().petBarScale or 0.7)
    end
end

-- ---------------------------------------------------------------------------
-- Button cosmetics: all combat-safe (text, alpha, vertex color) so they run
-- from the poll even during lockdown
-- ---------------------------------------------------------------------------
local cooldownTexts = {}   -- button -> fontstring
local readyAt = {}         -- button -> cooldown expiry we are watching
local flashTextures = {}   -- button -> additive flash overlay

local function CooldownTextFor(button)
    local text = cooldownTexts[button]
    if not text then
        local holder = CreateFrame("Frame", nil, button)
        holder:SetAllPoints(button)
        holder:SetFrameLevel((button:GetFrameLevel() or 1) + 5)
        text = holder:CreateFontString(nil, "OVERLAY")
        text:SetFontObject(GameFontHighlightSmall)
        local fontPath, fontSize = text:GetFont()
        if fontPath then
            text:SetFont(fontPath, fontSize or 10, "OUTLINE")
        end
        text:SetPoint("CENTER", button, "CENTER", 0, 0)
        cooldownTexts[button] = text
    end
    return text
end

local function FlashFor(button)
    local flash = flashTextures[button]
    if not flash then
        flash = button:CreateTexture(nil, "OVERLAY")
        flash:SetTexture("Interface\\Buttons\\WHITE8X8")
        flash:SetBlendMode("ADD")
        flash:SetAllPoints(button)
        flash:SetVertexColor(1, 1, 0.6, 0.55)
        flash:Hide()
        flashTextures[button] = flash
    end
    return flash
end

local function FormatCooldown(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    end
    return string.format("%d", math.ceil(seconds))
end

local function AbbreviateHotkey(text)
    if not text then return text end
    text = text:gsub("SHIFT%-", "S"):gsub("Shift%-", "S")
    text = text:gsub("CTRL%-", "C"):gsub("Ctrl%-", "C")
    text = text:gsub("ALT%-", "A"):gsub("Alt%-", "A")
    return text
end

local function ApplyButtonCosmetics()
    local db = DB()
    local now = GetTime()
    for _, button in ipairs(managedButtons) do
        if button then
            local name = button:GetName()
            -- Macro name and hotkey text
            local macroText = button.Name or (name and _G[name .. "Name"])
            if macroText then
                macroText:SetShown(not db.hideMacroText)
            end
            local hotkey = button.HotKey or (name and _G[name .. "HotKey"])
            if hotkey then
                if db.hideHotkeys then
                    hotkey:Hide()
                else
                    hotkey:Show()
                    if db.abbrevHotkeys then
                        local current = hotkey:GetText()
                        local shortened = AbbreviateHotkey(current)
                        if shortened ~= current then
                            hotkey:SetText(shortened)
                        end
                    end
                end
            end

            local slot = button.action
            local icon = button.icon or (name and _G[name .. "Icon"])
            -- Empty slot fading
            local hasAction = slot and HasAction and HasAction(slot)
            if db.hideEmptySlots and slot and HasAction then
                button:SetAlpha(hasAction and 1 or 0.15)
            end

            -- Range / mana tinting, restored to white when off or fine
            if icon and slot then
                local r, g, b = 1, 1, 1
                if hasAction then
                    if db.manaTint and IsUsableAction then
                        local usable, noMana = IsUsableAction(slot)
                        if noMana then
                            r, g, b = 0.35, 0.5, 1
                        elseif not usable then
                            r, g, b = 0.45, 0.45, 0.45
                        end
                    end
                    if db.rangeTint and IsActionInRange and IsActionInRange(slot) == false then
                        r, g, b = 1, 0.3, 0.25
                    end
                end
                icon:SetVertexColor(r, g, b)
            end

            -- Cooldown countdown text + ready flash
            if slot and GetActionCooldown then
                local start, duration = GetActionCooldown(slot)
                local remaining = (start and duration and duration > 1.5)
                    and (start + duration - now) or 0
                if db.cooldownText and remaining > 0 then
                    local text = CooldownTextFor(button)
                    text:SetText(FormatCooldown(remaining))
                    text:Show()
                elseif cooldownTexts[button] then
                    cooldownTexts[button]:Hide()
                end
                if db.readyFlash then
                    if remaining > 0.5 then
                        readyAt[button] = true
                    elseif readyAt[button] and remaining <= 0 then
                        readyAt[button] = nil
                        local flash = FlashFor(button)
                        flash:Show()
                        C_Timer.After(0.35, function() flash:Hide() end)
                    end
                end
            end
        end
    end
end

-- Out-of-combat fade: alpha is not a protected attribute, so the whole
-- card (backdrop + buttons) can fade even during lockdown
local function ApplyFade()
    if not backdrop then return end
    local db = DB()
    local alpha = 1
    if db.oocFade and not inCombat then
        alpha = db.fadeOpacity or 0.4
        if db.mouseoverReveal and MouseIsOver and MouseIsOver(backdrop) then
            alpha = 1
        end
    end
    backdrop:SetAlpha(alpha)
    for _, button in ipairs(managedButtons) do
        if button then
            button:SetAlpha((db.hideEmptySlots and button.action and HasAction and not HasAction(button.action))
                and math.min(alpha, 0.15) or alpha)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Update loop
-- ---------------------------------------------------------------------------
local function OnUpdate()
    -- Cosmetics are combat-safe and always run
    ApplyButtonCosmetics()
    ApplyFade()
    ApplyCardStyle()
    -- Protected frames can't be shown/hidden/moved in combat; retried on PLAYER_REGEN_ENABLED
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    HideDefaults()
    MovePetBar()
    for _, button in ipairs(managedButtons) do
        if button then button:Show() end
    end
end

-- Throttle so the hide/reposition work doesn't run every single frame
local UPDATE_INTERVAL = 0.25
local timeSinceUpdate = 0
local function OnUpdateThrottled(self, elapsed)
    timeSinceUpdate = timeSinceUpdate + elapsed
    if timeSinceUpdate < UPDATE_INTERVAL then return end
    timeSinceUpdate = 0
    OnUpdate()
end

local function OnSettingsUpdate()
    SetLockState()
    -- Re-anchoring the backdrop also moves the protected buttons anchored to it,
    -- so defer during combat lockdown
    if InCombatLockdown() then
        pendingUpdate = true
        return
    end
    ApplyPosition()
    MoveActionButtons()
    ApplyCardStyle()
    OnUpdate()
end

local function OnAwake()
    CreateRTSBackdrop()
    MoveActionButtons()
    frame:SetScript("OnUpdate", OnUpdateThrottled)
    Commander.AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnSettingsUpdate)
end

local function OnDestroy()
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        -- Apply any layout work that was deferred during combat lockdown
        if loaded and pendingUpdate then
            pendingUpdate = false
            ApplyPosition()
            MoveActionButtons()
            OnUpdate()
        end
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)

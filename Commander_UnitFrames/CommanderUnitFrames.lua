-- Applies the Commander Unit Frames settings to the default unit frames.
-- The options panel lives in CommanderUnitFramesDB.lua.

local frame = CreateFrame("FRAME")
frame:RegisterEvent("PLAYER_LOGIN")
local loaded = false

-- PlayerFrame/TargetFrame are protected; SetScale on them during combat
-- lockdown is blocked, so defer to PLAYER_REGEN_ENABLED
local pendingScaleUpdate = false

local function ApplyFrameScale()
    if InCombatLockdown() then
        pendingScaleUpdate = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    local scale = CommanderUnitFramesDB.scale or 1.0
    if PlayerFrame then
        PlayerFrame:SetScale(scale)
    end
    if TargetFrame then
        TargetFrame:SetScale(scale)
    end
end

-- statusTextDisplay is the game's "Status Text" option; PERCENT/NONE map the
-- checkbox onto it so the change shows up immediately on every status bar.
-- pcall in case a future patch renames the CVar (SetCVar errors on unknown names).
local function ApplyStatusText()
    local value = CommanderUnitFramesDB.showPercentage and "PERCENT" or "NONE"
    pcall(SetCVar, "statusTextDisplay", value)
end

local function OnUpdate()
    ApplyFrameScale()
    ApplyStatusText()
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_UNIT_FRAMES_EVENTS.UPDATE, OnUpdate)
        OnUpdate()
        loaded = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if loaded and pendingScaleUpdate then
            pendingScaleUpdate = false
            ApplyFrameScale()
        end
    end
end)

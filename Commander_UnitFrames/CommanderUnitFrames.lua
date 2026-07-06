-- Applies the Commander Unit Frames settings to the default unit frames.
-- The options panel lives in CommanderUnitFramesDB.lua. The percentage
-- toggle writes the statusTextDisplay CVar directly from the panel (the game
-- persists it), so the only setting applied here is the frame scale.

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

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_UNIT_FRAMES_EVENTS.UPDATE, ApplyFrameScale)
        ApplyFrameScale()
        loaded = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if loaded and pendingScaleUpdate then
            pendingScaleUpdate = false
            ApplyFrameScale()
        end
    end
end)

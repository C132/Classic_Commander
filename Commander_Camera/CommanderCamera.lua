-- Commander Camera: RTS camera location hotkeys built on the engine's own
-- SaveView/SetView slots (2-5; slot 1 is the client's default view). The
-- functions below back the Bindings.xml entries, the settings-page buttons,
-- and can be macroed. Engine view slots persist across sessions on their
-- own, so there is nothing to store beyond the user's toggles.

-- Binding UI labels (referenced by Bindings.xml)
BINDING_HEADER_COMMANDERCAMERA = "Commander Camera"
BINDING_NAME_COMMANDERCAMERA_RECALL2 = "Recall Camera View 1"
BINDING_NAME_COMMANDERCAMERA_RECALL3 = "Recall Camera View 2"
BINDING_NAME_COMMANDERCAMERA_RECALL4 = "Recall Camera View 3"
BINDING_NAME_COMMANDERCAMERA_RECALL5 = "Recall Camera View 4"
BINDING_NAME_COMMANDERCAMERA_SAVE2 = "Save Camera View 1"
BINDING_NAME_COMMANDERCAMERA_SAVE3 = "Save Camera View 2"
BINDING_NAME_COMMANDERCAMERA_SAVE4 = "Save Camera View 3"
BINDING_NAME_COMMANDERCAMERA_SAVE5 = "Save Camera View 4"
BINDING_NAME_COMMANDERCAMERA_ZOOM1 = "Recall Zoom Preset 1"
BINDING_NAME_COMMANDERCAMERA_ZOOM2 = "Recall Zoom Preset 2"
BINDING_NAME_COMMANDERCAMERA_ZOOM3 = "Recall Zoom Preset 3"
BINDING_NAME_COMMANDERCAMERA_ZOOM4 = "Recall Zoom Preset 4"
BINDING_NAME_COMMANDERCAMERA_ZOOM5 = "Recall Zoom Preset 5"

local function Click()
    if CommanderCameraDB and CommanderCameraDB.CameraSound then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
end

-- Slots 2-5 map to user-facing views 1-4
function CommanderCamera_Save(slot)
    if not (CommanderCameraDB and CommanderCameraDB.EnableCamera) then return end
    if slot < 2 or slot > 5 then return end
    SaveView(slot)
    Click()
    print(string.format("Commander Camera: view %d saved", slot - 1))
end

function CommanderCamera_Recall(slot)
    if not (CommanderCameraDB and CommanderCameraDB.EnableCamera) then return end
    if slot < 2 or slot > 5 then return end
    SetView(slot)
    Click()
end

-- ---------------------------------------------------------------------------
-- Zoom presets: the engine has only view slots 2-5, so the five extra
-- presets are honest zoom-distance memories — saved from GetCameraZoom and
-- restored by zooming the delta. No angle, just distance, which covers the
-- real use (melee close-up, standard, overview, screenshot pullback...).
-- ---------------------------------------------------------------------------
function CommanderCamera_SaveZoom(slot)
    if not (CommanderCameraDB and CommanderCameraDB.EnableCamera) then return end
    if slot < 1 or slot > 5 then return end
    CommanderCameraDB.ZoomPresets = CommanderCameraDB.ZoomPresets or {}
    CommanderCameraDB.ZoomPresets[slot] = GetCameraZoom()
    Click()
    print(string.format("Commander Camera: zoom preset %d saved (%.1f yd)", slot, GetCameraZoom()))
end

local lastZoomRecall = -math.huge

function CommanderCamera_Zoom(slot)
    if not (CommanderCameraDB and CommanderCameraDB.EnableCamera) then return end
    if slot < 1 or slot > 5 then return end
    local target = CommanderCameraDB.ZoomPresets and CommanderCameraDB.ZoomPresets[slot]
    if not target then
        print(string.format("Commander Camera: zoom preset %d is empty (Shift-click its button to save the current zoom)", slot))
        return
    end
    -- Zoom requests are queued distances, not absolute targets: a second
    -- recall while the camera is still gliding would stack deltas and
    -- overshoot. Debounce until the previous glide has finished.
    if GetTime() - lastZoomRecall < 0.8 then return end
    lastZoomRecall = GetTime()
    local delta = target - GetCameraZoom()
    if delta > 0 then
        CameraZoomOut(delta)
    elseif delta < 0 then
        CameraZoomIn(-delta)
    end
    Click()
end

-- ---------------------------------------------------------------------------
-- Experimental: RTS camera lock + click-to-move, via two CVars —
-- autointeract (the engine's own click-to-move) and cameraSmoothStyle 2
-- (camera continually settles behind the character). Prior values are
-- saved on enable and restored exactly on disable.
-- ---------------------------------------------------------------------------
function CommanderCamera_ApplyLock()
    if not CommanderCameraDB then return end
    local wantLock = CommanderCameraDB.EnableCamera and CommanderCameraDB.CameraLock
    if wantLock and not CommanderCameraDB.PriorCVars then
        CommanderCameraDB.PriorCVars = {
            autointeract = GetCVar("autointeract"),
            cameraSmoothStyle = GetCVar("cameraSmoothStyle"),
        }
        SetCVar("autointeract", "1")
        SetCVar("cameraSmoothStyle", "2")
        print("Commander Camera: RTS camera lock engaged (click terrain to move)")
    elseif not wantLock and CommanderCameraDB.PriorCVars then
        SetCVar("autointeract", CommanderCameraDB.PriorCVars.autointeract or "0")
        SetCVar("cameraSmoothStyle", CommanderCameraDB.PriorCVars.cameraSmoothStyle or "0")
        CommanderCameraDB.PriorCVars = nil
        print("Commander Camera: RTS camera lock released")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    Commander.AddListener(COMMANDER_CAMERA_EVENTS.UPDATE, CommanderCamera_ApplyLock)
    CommanderCamera_ApplyLock()
end)

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

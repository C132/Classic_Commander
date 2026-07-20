CommanderCameraDB = _G.CommanderCameraDB or {}

COMMANDER_CAMERA_EVENTS = {
    UPDATE = "COMMANDER_CAMERA_UPDATE"
}

local DefaultSettings = {
    EnableCamera = true,
    CameraSound = true,
    CameraLock = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderCameraDB, DefaultSettings)
    Commander.Notify(COMMANDER_CAMERA_EVENTS.UPDATE)
    print("Commander Camera: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Camera",
        title = "Camera",
        addonName = "Commander_Camera",
        description = "RTS camera hotkeys, powered by the engine's own view slots: save up to four camera positions (angle, zoom, pitch) and snap back to them instantly — your dedicated fight view, screenshot view, and city view, one keypress apart.",
        event = COMMANDER_CAMERA_EVENTS.UPDATE,
        slash = { "/ccam" },
        slashHandlers = {},
    })

    panel:AddSection("Camera Views", "Bind keys under Key Bindings > AddOns > Commander Camera, or use the buttons below.")
    panel:AddCheckbox({
        label = "Enable Camera Views",
        tooltip = "Master switch for the whole module (keybinds and buttons stand down when off).",
        get = function() return CommanderCameraDB.EnableCamera end,
        set = function(value) CommanderCameraDB.EnableCamera = value end,
    })
    panel:AddCheckbox({
        label = "Confirmation Sound",
        tooltip = "Play a soft click when a view is saved or recalled.",
        get = function() return CommanderCameraDB.CameraSound end,
        set = function(value) CommanderCameraDB.CameraSound = value end,
        isEnabled = function() return CommanderCameraDB.EnableCamera end,
    })
    local enabled = function() return CommanderCameraDB.EnableCamera end
    panel:AddButtonRow({
        { label = "Save View 1", width = 105, tooltip = "Store the current camera in slot 1.", onClick = function() CommanderCamera_Save(2) end, isEnabled = enabled },
        { label = "Save View 2", width = 105, tooltip = "Store the current camera in slot 2.", onClick = function() CommanderCamera_Save(3) end, isEnabled = enabled },
        { label = "Save View 3", width = 105, tooltip = "Store the current camera in slot 3.", onClick = function() CommanderCamera_Save(4) end, isEnabled = enabled },
        { label = "Save View 4", width = 105, tooltip = "Store the current camera in slot 4.", onClick = function() CommanderCamera_Save(5) end, isEnabled = enabled },
    })
    panel:AddButtonRow({
        { label = "Recall 1", width = 105, tooltip = "Snap the camera to saved view 1.", onClick = function() CommanderCamera_Recall(2) end, isEnabled = enabled },
        { label = "Recall 2", width = 105, tooltip = "Snap the camera to saved view 2.", onClick = function() CommanderCamera_Recall(3) end, isEnabled = enabled },
        { label = "Recall 3", width = 105, tooltip = "Snap the camera to saved view 3.", onClick = function() CommanderCamera_Recall(4) end, isEnabled = enabled },
        { label = "Recall 4", width = 105, tooltip = "Snap the camera to saved view 4.", onClick = function() CommanderCamera_Recall(5) end, isEnabled = enabled },
    })

    local function ZoomTooltip(slot)
        return function()
            local presets = CommanderCameraDB.ZoomPresets
            local saved = presets and presets[slot]
            if saved then
                return string.format("Click: zoom to %.1f yd. Shift-click: overwrite with the current zoom.", saved)
            end
            return "Empty. Shift-click to save the current camera zoom distance."
        end
    end
    panel:AddSection("Zoom Presets", "Five zoom-distance memories (the engine's four view slots above store full angles; these store distance only). Click recalls, Shift-click saves.")
    panel:AddButtonRow({
        { label = "Zoom 1", width = 84, tooltip = ZoomTooltip(1), onClick = function() if IsShiftKeyDown() then CommanderCamera_SaveZoom(1) else CommanderCamera_Zoom(1) end end, isEnabled = enabled },
        { label = "Zoom 2", width = 84, tooltip = ZoomTooltip(2), onClick = function() if IsShiftKeyDown() then CommanderCamera_SaveZoom(2) else CommanderCamera_Zoom(2) end end, isEnabled = enabled },
        { label = "Zoom 3", width = 84, tooltip = ZoomTooltip(3), onClick = function() if IsShiftKeyDown() then CommanderCamera_SaveZoom(3) else CommanderCamera_Zoom(3) end end, isEnabled = enabled },
        { label = "Zoom 4", width = 84, tooltip = ZoomTooltip(4), onClick = function() if IsShiftKeyDown() then CommanderCamera_SaveZoom(4) else CommanderCamera_Zoom(4) end end, isEnabled = enabled },
        { label = "Zoom 5", width = 84, tooltip = ZoomTooltip(5), onClick = function() if IsShiftKeyDown() then CommanderCamera_SaveZoom(5) else CommanderCamera_Zoom(5) end end, isEnabled = enabled },
    })

    panel:AddSection("Experimental")
    panel:AddCheckbox({
        label = "RTS Camera Lock + Click-to-Move",
        tooltip = "Experimental: engages the engine's click-to-move (autointeract) and keeps the camera settling behind your character (cameraSmoothStyle), for a played-from-above RTS feel. Your previous CVar values are saved and restored exactly when you turn this off.",
        get = function() return CommanderCameraDB.CameraLock end,
        set = function(value) CommanderCameraDB.CameraLock = value end,
        isEnabled = enabled,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Camera" then
        Commander.UI.ApplyDefaults(CommanderCameraDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

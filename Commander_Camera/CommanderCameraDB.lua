CommanderCameraDB = _G.CommanderCameraDB or {}

COMMANDER_CAMERA_EVENTS = {
    UPDATE = "COMMANDER_CAMERA_UPDATE"
}

local DefaultSettings = {
    EnableCamera = true,
    CameraSound = true,
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
    panel:AddButtonRow({
        { label = "Save View 1", width = 105, tooltip = "Store the current camera in slot 1.", onClick = function() CommanderCamera_Save(2) end },
        { label = "Save View 2", width = 105, tooltip = "Store the current camera in slot 2.", onClick = function() CommanderCamera_Save(3) end },
        { label = "Save View 3", width = 105, tooltip = "Store the current camera in slot 3.", onClick = function() CommanderCamera_Save(4) end },
        { label = "Save View 4", width = 105, tooltip = "Store the current camera in slot 4.", onClick = function() CommanderCamera_Save(5) end },
    })
    panel:AddButtonRow({
        { label = "Recall 1", width = 105, tooltip = "Snap the camera to saved view 1.", onClick = function() CommanderCamera_Recall(2) end },
        { label = "Recall 2", width = 105, tooltip = "Snap the camera to saved view 2.", onClick = function() CommanderCamera_Recall(3) end },
        { label = "Recall 3", width = 105, tooltip = "Snap the camera to saved view 3.", onClick = function() CommanderCamera_Recall(4) end },
        { label = "Recall 4", width = 105, tooltip = "Snap the camera to saved view 4.", onClick = function() CommanderCamera_Recall(5) end },
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

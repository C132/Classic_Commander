CommanderBagsDB = _G.CommanderBagsDB or {}

COMMANDER_BAGS_EVENTS = {
    UPDATE = "COMMANDER_BAGS_UPDATE"
}

local DefaultSettings = {
    ColorCodeItems = true,
    BagPositions = {},
    FadeBagsWhileMoving = true,
    FadeOpacity = 0.5,
}

local function ApplyDefaultSettings()
    for key, value in pairs(DefaultSettings) do
        if CommanderBagsDB[key] == nil then
            if key == "BagPositions" then
                CommanderBagsDB[key] = {}
            else
                CommanderBagsDB[key] = value
            end
        end
    end
end

ApplyDefaultSettings()

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
local loaded = false

-- Container frames are unprotected, so relaying them out is legal even in
-- combat; deferring the direct (insecure) UpdateContainerFrameAnchors call to
-- after combat just avoids a gratuitously tainted layout pass while the UI is
-- in lockdown
local relayoutWatcher = CreateFrame("Frame")
relayoutWatcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        UpdateContainerFrameAnchors()
    end
end)

local function RequestContainerRelayout()
    if InCombatLockdown() then
        relayoutWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        UpdateContainerFrameAnchors()
    end
end

-- Drop any custom anchors (hidden frames included, so stale points cannot
-- combine with Blizzard's later SetPoint), then let Blizzard lay the shown
-- bags back out in the stock layout.
local function ResetBagPositions()
    CommanderBagsDB.BagPositions = {}
    -- NUM_CONTAINER_FRAMES is Blizzard's global; fall back to 13 (this client's
    -- count) in case a future patch drops it
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local containerFrame = _G["ContainerFrame"..i]
        if containerFrame then
            containerFrame:ClearAllPoints()
        end
    end
    RequestContainerRelayout()
    Commander.Notify(COMMANDER_BAGS_EVENTS.UPDATE)
end

local function Reset()
    CommanderBagsDB.ColorCodeItems = DefaultSettings.ColorCodeItems
    CommanderBagsDB.FadeBagsWhileMoving = DefaultSettings.FadeBagsWhileMoving
    CommanderBagsDB.FadeOpacity = DefaultSettings.FadeOpacity
    ResetBagPositions()
    print("Commander Bags: settings restored to defaults")
end

-- Exposed for the /cbags slash command registered in CommanderBags.lua
CommanderBags_Reset = Reset

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Bags",
        title = "Bags",
        addonName = "Commander_Bags",
        description = "Color-codes bag items by quality and type, makes bag windows freely draggable, and fades them out of the way while you travel.",
        event = COMMANDER_BAGS_EVENTS.UPDATE,
        slash = { "/cb" },
        slashHandlers = {
            reset = Reset,
        },
    })

    panel:AddSection("Item Highlighting")
    panel:AddCheckbox({
        label = "Color Code Item Borders",
        tooltip = "Draw a colored border around bag items: quality colors for gear, yellow for quest items, cyan for consumables, and red for gray junk.",
        get = function() return CommanderBagsDB.ColorCodeItems end,
        set = function(value) CommanderBagsDB.ColorCodeItems = value end,
    })

    panel:AddSection("Movement Fade")
    panel:AddCheckbox({
        label = "Fade Bags While Moving",
        tooltip = "Make open bag windows translucent while your character is moving, so they block less of the world.",
        get = function() return CommanderBagsDB.FadeBagsWhileMoving end,
        set = function(value) CommanderBagsDB.FadeBagsWhileMoving = value end,
    })
    panel:AddSlider({
        label = "Faded Opacity",
        tooltip = "How visible bag windows remain while you are moving. Lower values make them more transparent.",
        min = 0.1, max = 1.0, step = 0.05,
        format = function(value) return string.format("%d%%", value * 100 + 0.5) end,
        get = function() return CommanderBagsDB.FadeOpacity end,
        set = function(value) CommanderBagsDB.FadeOpacity = value end,
        isEnabled = function() return CommanderBagsDB.FadeBagsWhileMoving end,
    })

    panel:AddSection("Bag Positions")
    panel:AddButtonRow({
        {
            label = "Reset Bag Positions",
            tooltip = "Forget every dragged bag position and return all bag windows to the standard layout.",
            onClick = function()
                ResetBagPositions()
                print("Commander Bags: bag positions reset")
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnAwake()
    -- Re-apply defaults here: SavedVariables replace the global CommanderBagsDB
    -- after this file runs, so the top-of-file merge is lost for existing saves
    ApplyDefaultSettings()
    CreateOptionsPanel()
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName == "Commander_Bags" then
            CommanderBagsDB = CommanderBagsDB or {}
            ApplyDefaultSettings()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    end
end

frame:SetScript("OnEvent", OnEvent)

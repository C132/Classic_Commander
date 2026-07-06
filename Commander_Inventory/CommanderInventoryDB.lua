CommanderInventoryDB = _G.CommanderInventoryDB or {}

COMMANDER_INVENTORY_EVENTS = {
    COMMANDER_INVENTORY = "COMMANDER_INVENTORY",
}

local defaultSettings = {
    columns = 4,
    scale = 1,
    locked = false,
    tooltips = true,
    showFrame = true,
}

local function ApplyDefaults()
    for key, value in pairs(defaultSettings) do
        if CommanderInventoryDB[key] == nil then
            CommanderInventoryDB[key] = value
        end
    end
end

ApplyDefaults()

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    for key, value in pairs(defaultSettings) do
        CommanderInventoryDB[key] = value
    end
    Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    print("Commander Inventory: settings restored to defaults")
end

-- Center the item grid; its position lives in the client's layout cache, not
-- in the saved variables, so this is the only way to recover an off-screen grid
local function ResetPosition()
    if CIItemGrid then
        CIItemGrid:ClearAllPoints()
        CIItemGrid:SetPoint("CENTER", UIParent, "CENTER")
        Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    end
end

local function ToggleFrame()
    CommanderInventoryDB.showFrame = not CommanderInventoryDB.showFrame
    Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Inventory",
        title = "Inventory",
        addonName = "Commander_Inventory",
        description = "Collects every usable item you are carrying or wearing into one clickable grid, with live cooldowns and stack counts.",
        event = COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY,
        slash = { "/ci" },
        slashHandlers = {
            toggle = ToggleFrame,
            reset = Reset,
            center = ResetPosition,
        },
    })

    panel:AddSection("Item Grid")
    panel:AddCheckbox({
        label = "Show Item Grid",
        tooltip = "Show the usable-items grid. You can also toggle it with /ci toggle.",
        get = function() return CommanderInventoryDB.showFrame end,
        set = function(value) CommanderInventoryDB.showFrame = value end,
    })
    panel:AddCheckbox({
        label = "Lock Grid Position",
        tooltip = "Prevent the grid from being dragged.",
        get = function() return CommanderInventoryDB.locked end,
        set = function(value) CommanderInventoryDB.locked = value end,
    })
    panel:AddCheckbox({
        label = "Show Item Tooltips",
        tooltip = "Show the item tooltip when hovering over a button in the grid.",
        get = function() return CommanderInventoryDB.tooltips end,
        set = function(value) CommanderInventoryDB.tooltips = value end,
    })
    panel:AddButtonRow({
        {
            label = "Reset Position",
            tooltip = "Move the item grid back to the center of the screen.",
            onClick = ResetPosition,
        },
    })

    panel:AddSection("Layout")
    panel:AddSlider({
        label = "Columns",
        tooltip = "Number of item buttons per row.",
        min = 1, max = 12, step = 1,
        format = "%d",
        get = function() return CommanderInventoryDB.columns end,
        set = function(value) CommanderInventoryDB.columns = value end,
    })
    panel:AddSlider({
        label = "Grid Scale",
        tooltip = "Overall size of the item grid.",
        min = 0.5, max = 2.0, step = 0.05,
        format = function(value) return string.format("%d%%", value * 100 + 0.5) end,
        get = function() return CommanderInventoryDB.scale end,
        set = function(value) CommanderInventoryDB.scale = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Saved variables replace the table created at file load, so re-apply defaults
        -- here for any keys missing from the saved data
        ApplyDefaults()
        _G.CommanderInventoryDB = CommanderInventoryDB
        CreateOptionsPanel()
    end
end)

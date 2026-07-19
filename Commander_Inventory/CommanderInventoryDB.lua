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
    frameStyle = "WINDOW",
    -- false (not nil) so Restore Defaults clears a saved drag position
    position = false,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderInventoryDB, defaultSettings)
    Commander.Notify(COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY)
    print("Commander Inventory: settings restored to defaults")
end

local function ResetPosition()
    CommanderInventoryDB.position = false
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
        description = "A quick bar that builds itself: every usable item you carry or wear — potions, trinkets, bombs, on-use gear — collected into one clickable grid with live cooldowns and stack counts.",
        event = COMMANDER_INVENTORY_EVENTS.COMMANDER_INVENTORY,
        slash = { "/ci" },
        slashHandlers = {
            -- Bare /ci keeps its long-standing meaning: toggle the item grid.
            -- The framework auto-adds "/ci settings" to open this panel.
            [""] = ToggleFrame,
            toggle = ToggleFrame,
            center = ResetPosition,
        },
    })

    panel:AddSection("Item Grid", "The grid rebuilds itself automatically as your inventory changes.")
    panel:AddCheckboxPair({
        label = "Show Item Grid",
        tooltip = "Show the usable-items grid. You can also toggle it with /ci.",
        get = function() return CommanderInventoryDB.showFrame end,
        set = function(value) CommanderInventoryDB.showFrame = value end,
    }, {
        label = "Lock Grid Position",
        tooltip = "Prevent the grid from being dragged. Its position now saves with your settings like every other Commander frame.",
        get = function() return CommanderInventoryDB.locked end,
        set = function(value) CommanderInventoryDB.locked = value end,
    })
    panel:AddCheckbox({
        label = "Show Item Tooltips",
        tooltip = "Show the item tooltip when hovering over a button in the grid.",
        get = function() return CommanderInventoryDB.tooltips end,
        set = function(value) CommanderInventoryDB.tooltips = value end,
    })
    panel:AddDropdown({
        label = "Frame Style",
        tooltip = "Window keeps the title bar and close button. Classic Panel and Dark Panel match the framing options on the other Commander frames; None is just the buttons.",
        options = {
            { text = "Window", value = "WINDOW" },
            { text = "Classic Panel", value = "CLASSIC" },
            { text = "Dark Panel", value = "DARK" },
            { text = "None", value = "NONE" },
        },
        width = 140,
        get = function() return CommanderInventoryDB.frameStyle or "WINDOW" end,
        set = function(value) CommanderInventoryDB.frameStyle = value end,
    })
    panel:AddButtonRow({
        {
            label = "Reset Position",
            tooltip = "Move the item grid back to the center of the screen and clear the saved position.",
            onClick = ResetPosition,
        },
    })

    panel:AddSection("Layout")
    panel:AddSliderPair({
        label = "Columns",
        tooltip = "Number of item buttons per row.",
        min = 1, max = 12, step = 1,
        format = "%d",
        get = function() return CommanderInventoryDB.columns end,
        set = function(value) CommanderInventoryDB.columns = value end,
    }, {
        label = "Grid Scale",
        tooltip = "Overall size of the item grid.",
        min = 0.5, max = 2.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderInventoryDB.scale end,
        set = function(value) CommanderInventoryDB.scale = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Saved variables replace the table created at file load, so apply
        -- defaults here for any keys missing from the saved data
        Commander.UI.ApplyDefaults(CommanderInventoryDB, defaultSettings)
        CreateOptionsPanel()
    end
end)

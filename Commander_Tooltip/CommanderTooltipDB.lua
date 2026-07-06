CommanderTooltipDB = _G.CommanderTooltipDB or {}

COMMANDER_TOOLTIP_EVENTS = {
    UPDATE = "COMMANDER_TOOLTIP_UPDATE"
}

local DefaultSettings = {
    ShowItemLevel = true,
    ShowVendorPrice = true,
    AnchorToCursor = true,
    xOffset = 0,
    yOffset = 0,
    Scale = 1.0,
    Anchor = "BOTTOMLEFT"
}

local ANCHOR_OPTIONS = {
    {text = "Top Left", value = "TOPLEFT"},
    {text = "Top", value = "TOP"},
    {text = "Top Right", value = "TOPRIGHT"},
    {text = "Left", value = "LEFT"},
    {text = "Center", value = "CENTER"},
    {text = "Right", value = "RIGHT"},
    {text = "Bottom Left", value = "BOTTOMLEFT"},
    {text = "Bottom", value = "BOTTOM"},
    {text = "Bottom Right", value = "BOTTOMRIGHT"},
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderTooltipDB, DefaultSettings)
    Commander.Notify(COMMANDER_TOOLTIP_EVENTS.UPDATE)
    print("Commander Tooltip: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Tooltip",
        title = "Tooltip",
        addonName = "Commander_Tooltip",
        description = "Extends game tooltips with item levels and vendor prices, and controls where the default tooltip appears on screen.",
        event = COMMANDER_TOOLTIP_EVENTS.UPDATE,
        slash = { "/ctooltip" },
    })

    panel:AddSection("Appearance")
    panel:AddCheckbox({
        label = "Show Item Level",
        tooltip = "Add the item's level to item tooltips.",
        get = function() return CommanderTooltipDB.ShowItemLevel end,
        set = function(value) CommanderTooltipDB.ShowItemLevel = value end,
    })
    panel:AddCheckbox({
        label = "Show Vendor Price",
        tooltip = "Add the vendor sell price to item tooltips, even when you are not at a merchant.",
        get = function() return CommanderTooltipDB.ShowVendorPrice end,
        set = function(value) CommanderTooltipDB.ShowVendorPrice = value end,
    })
    panel:AddSlider({
        label = "Tooltip Scale",
        tooltip = "Overall size of game tooltips.",
        min = 0.5, max = 2.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderTooltipDB.Scale end,
        set = function(value) CommanderTooltipDB.Scale = value end,
    })

    panel:AddSection("Position")
    panel:AddCheckbox({
        label = "Anchor to Cursor",
        tooltip = "Make the tooltip follow the mouse cursor. Uncheck to pin it to a fixed corner of the screen instead.",
        get = function() return CommanderTooltipDB.AnchorToCursor end,
        set = function(value) CommanderTooltipDB.AnchorToCursor = value end,
    })
    panel:AddDropdown({
        label = "Screen Anchor",
        tooltip = "Where the tooltip is pinned when it is not following the cursor.",
        options = ANCHOR_OPTIONS,
        width = 140,
        get = function() return CommanderTooltipDB.Anchor end,
        set = function(value) CommanderTooltipDB.Anchor = value end,
        isEnabled = function() return not CommanderTooltipDB.AnchorToCursor end,
    })
    panel:AddSlider({
        label = "Horizontal Offset",
        tooltip = "Nudge the tooltip left or right from its anchor point.",
        min = -50, max = 50, step = 1,
        format = "%d",
        get = function() return CommanderTooltipDB.xOffset end,
        set = function(value) CommanderTooltipDB.xOffset = value end,
    })
    panel:AddSlider({
        label = "Vertical Offset",
        tooltip = "Nudge the tooltip up or down from its anchor point.",
        min = -50, max = 50, step = 1,
        format = "%d",
        get = function() return CommanderTooltipDB.yOffset end,
        set = function(value) CommanderTooltipDB.yOffset = value end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        Commander.UI.ApplyDefaults(CommanderTooltipDB, DefaultSettings)
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

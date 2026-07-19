CommanderBagsDB = _G.CommanderBagsDB or {}

COMMANDER_BAGS_EVENTS = {
    UPDATE = "COMMANDER_BAGS_UPDATE"
}

local DefaultSettings = {
    ColorCodeItems = true,
    BagPositions = {},
    FadeBagsWhileMoving = true,
    FadeOpacity = 0.5,
    SortOrder = "QUALITY",
    PortraitSortClick = true,
}

local SORT_ORDERS = {
    { text = "Quality", value = "QUALITY" },
    { text = "Item Level", value = "ILVL" },
    { text = "Category", value = "CATEGORY" },
    { text = "Name (A-Z)", value = "NAME" },
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

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
    Commander.UI.ResetToDefaults(CommanderBagsDB, DefaultSettings)
    ResetBagPositions()
    print("Commander Bags: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Bags",
        title = "Bags",
        addonName = "Commander_Bags",
        description = "Your quartermaster: bag items get color-coded borders so loot reads at a glance, bag windows drag freely and remember where you put them, and everything fades out of your way while you travel.",
        event = COMMANDER_BAGS_EVENTS.UPDATE,
        slash = { "/cbags", "/cb" },
        slashHandlers = {
            sort = function()
                if CommanderBags_SortBags then
                    CommanderBags_SortBags()
                end
            end,
            diag = function()
                -- Defined in CommanderBags.lua, which loads after this file
                if CommanderBags_PrintDiagnostics then
                    CommanderBags_PrintDiagnostics()
                end
            end,
        },
    })

    panel:AddSection("Item Highlighting", "Quest items glow yellow, consumables cyan, gray junk red, and gear keeps its quality color.")
    panel:AddCheckbox({
        label = "Color Code Item Borders",
        tooltip = "Draw a colored border around bag items: quality colors for gear, yellow for quest items, cyan for consumables, and red for gray junk.",
        get = function() return CommanderBagsDB.ColorCodeItems end,
        set = function(value) CommanderBagsDB.ColorCodeItems = value end,
    })

    panel:AddSection("Movement Fade", "Open bags turn translucent while you move and snap back to full opacity when you stop.")
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
        format = Commander.UI.FormatPercent,
        get = function() return CommanderBagsDB.FadeOpacity end,
        set = function(value) CommanderBagsDB.FadeOpacity = value end,
        isEnabled = function() return CommanderBagsDB.FadeBagsWhileMoving end,
    })

    panel:AddSection("Sorting", "Click any bag's icon to sort. Special bags (quivers, soul bags) are never touched.")
    panel:AddDropdown({
        label = "Sort Order",
        tooltip = "Quality: epics first, junk last. Item Level: strongest gear first. Category: weapons, armor, consumables, trade goods grouped. Name: alphabetical.",
        options = SORT_ORDERS,
        width = 140,
        get = function() return CommanderBagsDB.SortOrder end,
        set = function(value) CommanderBagsDB.SortOrder = value end,
    })
    panel:AddCheckbox({
        label = "Bag Icon Click Sorts",
        tooltip = "Left-clicking a bag window's icon runs the sort (right-click keeps the normal bag menu). Uncheck to restore the default left-click behavior; /cb sort always works.",
        get = function() return CommanderBagsDB.PortraitSortClick end,
        set = function(value) CommanderBagsDB.PortraitSortClick = value end,
    })
    panel:AddButtonRow({
        {
            label = "Sort Now",
            width = 100,
            tooltip = "Sort the general-purpose bags using the selected order.",
            onClick = function()
                if CommanderBags_SortBags then
                    CommanderBags_SortBags()
                end
            end,
        },
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

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        if addonName == "Commander_Bags" then
            CommanderBagsDB = CommanderBagsDB or {}
            Commander.UI.ApplyDefaults(CommanderBagsDB, DefaultSettings)
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

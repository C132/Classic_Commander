CommanderTopBarDB = _G.CommanderTopBarDB or {}

COMMANDER_TOPBAR_EVENTS = {
    UPDATE = "COMMANDER_TOPBAR_UPDATE"
}

local DefaultSettings = {
    EnableTopBar = true,
    ShowGold = true,
    ShowBags = true,
    ShowDurability = true,
    ShowXP = true,
    ShowPerformance = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderTopBarDB, DefaultSettings)
    Commander.Notify(COMMANDER_TOPBAR_EVENTS.UPDATE)
    print("Commander Top Bar: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "TopBar",
        title = "Top Bar",
        addonName = "Commander_TopBar",
        description = "A command bar across the top of the screen, RTS-style: your resources at a glance — gold, bag supply, armor condition, XP income, and connection health — without opening a single window.",
        event = COMMANDER_TOPBAR_EVENTS.UPDATE,
        slash = { "/ctb" },
        slashHandlers = {
            toggle = function()
                CommanderTopBarDB.EnableTopBar = not CommanderTopBarDB.EnableTopBar
                Commander.Notify(COMMANDER_TOPBAR_EVENTS.UPDATE)
            end,
        },
    })

    panel:AddSection("Command Bar", "The master switch; turn it off and the whole bar is gone.")
    panel:AddCheckbox({
        label = "Enable Top Bar",
        tooltip = "Show the resource strip across the top of the screen.",
        get = function() return CommanderTopBarDB.EnableTopBar end,
        set = function(value) CommanderTopBarDB.EnableTopBar = value end,
    })

    panel:AddSection("Readouts", "Pick which resources report in. Supply counts your used and total bag slots.")
    local function SegmentCheckbox(key, label, tooltip)
        panel:AddCheckbox({
            label = label,
            tooltip = tooltip,
            get = function() return CommanderTopBarDB[key] end,
            set = function(value) CommanderTopBarDB[key] = value end,
            isEnabled = function() return CommanderTopBarDB.EnableTopBar end,
        })
    end
    SegmentCheckbox("ShowGold", "Gold", "Your current money.")
    SegmentCheckbox("ShowBags", "Supply (Bag Slots)", "Used / total bag slots, like an RTS supply counter. Turns red when you are nearly full.")
    SegmentCheckbox("ShowDurability", "Durability", "Lowest equipment durability. Turns red when your gear needs repair.")
    SegmentCheckbox("ShowXP", "XP Rate", "XP gained per hour this session and estimated time to level. Hidden at max level.")
    SegmentCheckbox("ShowPerformance", "Performance", "Framerate and home latency.")

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_TopBar" then
        -- SavedVariables replace the global table after the file runs, so apply defaults here
        Commander.UI.ApplyDefaults(CommanderTopBarDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

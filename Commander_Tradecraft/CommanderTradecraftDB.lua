-- Commander Tradecraft: defaults, the settings page, and the load lifecycle.
--
-- Two saved tables. CommanderTradecraftDB is account-wide and holds only
-- settings, so Restore Defaults can rewrite all of it. CommanderTradecraftChar
-- is per character and holds progress — which alternative paths were chosen,
-- which steps were skipped, which recipes the craft window has been seen to
-- contain — and nothing on the options page can touch it. A character's
-- route through a profession is theirs; the enchanter alt should not lose
-- their Moonglade decision because the main pressed a button.

CommanderTradecraftDB = _G.CommanderTradecraftDB or {}
CommanderTradecraftChar = _G.CommanderTradecraftChar or {}

COMMANDER_TRADECRAFT_EVENTS = {
    UPDATE = "COMMANDER_TRADECRAFT_UPDATE",
}

local DefaultSettings = {
    EnableTradecraft = true,

    -- The guide window
    ShowGuide = true,
    AutoOpenWithCraft = true,
    HideWhenFinished = true,
    PreviewSteps = 2,
    ShowTips = true,

    -- Counting
    CountBank = true,
    Margin = 0.10,

    -- Crafting
    AutoTargetGear = true,
    AutoConfirmReplace = true,

    -- Chatter
    AnnounceSteps = true,
    StepSound = true,
    UseWaypoints = true,
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Guide", "DARK")) do
    DefaultSettings[key] = value
end

CommanderTradecraft_Defaults = DefaultSettings

local PREVIEW_OPTIONS = {
    { text = "None", value = 0 },
    { text = "One", value = 1 },
    { text = "Two", value = 2 },
    { text = "Three", value = 3 },
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderTradecraftDB, DefaultSettings)
    Commander.Notify(COMMANDER_TRADECRAFT_EVENTS.UPDATE)
    print("Commander Tradecraft: settings restored to defaults. Your route choices were not touched.")
end

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Tradecraft",
        title = "Tradecraft",
        addonName = "Commander_Tradecraft",
        description = "Guided profession leveling, the way the leveling guides do it: one step on screen at a time. The guide window shows the recipe to craft now, how many more it will take, what you hold against what it needs, and a Craft button that casts it on your own gear. Formula steps name the vendor, the zone and the coordinates; a banner tells you when a trainer has a new rank for you. The shopping list is the whole rest of the route, less what is already in your bags and bank. Enchanting 1 to 375 for now.",
        event = COMMANDER_TRADECRAFT_EVENTS.UPDATE,
        slash = { "/ctc", "/ctradecraft" },
        slashHandlers = {
            [""] = function() Call("CommanderTradecraft_Toggle") end,
            show = function() Call("CommanderTradecraft_Show") end,
            hide = function() Call("CommanderTradecraft_Hide") end,
            route = function() Call("CommanderTradecraft_Route") end,
            shop = function() Call("CommanderTradecraft_Shopping") end,
            ah = function(arg) Call("CommanderTradecraft_AuctionatorList", arg) end,
            skip = function() Call("CommanderTradecraft_Skip") end,
            back = function() Call("CommanderTradecraft_Unskip") end,
            alt = function(arg) Call("CommanderTradecraft_Alternative", arg) end,
            craft = function() Call("CommanderTradecraft_Craft") end,
            reset = function() Call("CommanderTradecraft_ResetProgress") end,
            status = function() Call("CommanderTradecraft_Status") end,
        },
    })

    panel:AddSection("Tradecraft")
    panel:AddCheckbox({
        label = "Enable Tradecraft",
        tooltip = "Master switch. Your route choices are kept either way — turning this off only puts the guide away.",
        get = function() return CommanderTradecraftDB.EnableTradecraft end,
        set = function(value) CommanderTradecraftDB.EnableTradecraft = value end,
    })

    panel:AddSection("The Guide Window",
        "The step you are on, the reagents it wants, and the button that crafts it.")
    panel:AddCheckboxPair({
        label = "Open With The Craft Window",
        tooltip = "Show the guide whenever your Enchanting window opens, even if you had closed it. The guide is most use when the craft list is on screen beside it.",
        get = function() return CommanderTradecraftDB.AutoOpenWithCraft end,
        set = function(value) CommanderTradecraftDB.AutoOpenWithCraft = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    }, {
        label = "Hide When Finished",
        tooltip = "Put the guide away once the profession is at 375. It still opens from /ctc.",
        get = function() return CommanderTradecraftDB.HideWhenFinished end,
        set = function(value) CommanderTradecraftDB.HideWhenFinished = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })
    panel:AddDropdown({
        label = "Preview Next Steps",
        tooltip = "How many upcoming steps to list under the current one, dimmed. Formula trips show up here early enough to plan the flight.",
        options = PREVIEW_OPTIONS,
        get = function() return CommanderTradecraftDB.PreviewSteps end,
        set = function(value) CommanderTradecraftDB.PreviewSteps = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })
    panel:AddCheckbox({
        label = "Show The Guide's Notes",
        tooltip = "A line of advice from the guide under the step, when it has one for the path you are on — why this recipe, what to watch the price of.",
        get = function() return CommanderTradecraftDB.ShowTips end,
        set = function(value) CommanderTradecraftDB.ShowTips = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })

    panel:AddSection("Counting",
        "How the reagent numbers and the shopping list are worked out.")
    panel:AddCheckbox({
        label = "Count The Bank",
        tooltip = "Treat reagents in your bank as reachable: the shopping list will not tell you to buy Vision Dust you already own, and a step's reagent line shows the bank's share in brackets. Bank counts are as of your last visit to a banker.",
        get = function() return CommanderTradecraftDB.CountBank end,
        set = function(value) CommanderTradecraftDB.CountBank = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })
    panel:AddSlider({
        label = "Safety Margin",
        tooltip = "Skill-ups on yellow and green recipes are a roll of the dice. The guide plans for the expected number of crafts plus this much on top, so a run of bad luck does not leave you a few dust short. Orange crafts are certain and get no margin. The published guides use about ten percent.",
        min = 0, max = 0.4, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderTradecraftDB.Margin end,
        set = function(value) CommanderTradecraftDB.Margin = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })

    panel:AddSection("Crafting",
        "What the Craft button does beyond pressing Create for you.")
    panel:AddCheckboxPair({
        label = "Cast On My Own Gear",
        tooltip = "Enchants need something to land on. With this on, the Craft button casts the enchant straight onto the matching piece you are wearing (bracers, cloak, chest, gloves, boots, shield, ring), or the first one in your bags. Off, it leaves the glowing cursor for you to click a target with.",
        get = function() return CommanderTradecraftDB.AutoTargetGear end,
        set = function(value) CommanderTradecraftDB.AutoTargetGear = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    }, {
        label = "Confirm Replacing An Enchant",
        tooltip = "Enchanting a piece that is already enchanted asks you to confirm. Leveling means enchanting the same bracers a hundred times, so with this on the guide answers yes for you — but only for casts it started itself.",
        get = function() return CommanderTradecraftDB.AutoConfirmReplace end,
        set = function(value) CommanderTradecraftDB.AutoConfirmReplace = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })

    panel:AddSection("Chatter")
    panel:AddCheckboxPair({
        label = "Announce Steps",
        tooltip = "A line in chat when a step is finished and the next one begins.",
        get = function() return CommanderTradecraftDB.AnnounceSteps end,
        set = function(value) CommanderTradecraftDB.AnnounceSteps = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    }, {
        label = "Step Sound",
        tooltip = "A quiet chime when a step completes.",
        get = function() return CommanderTradecraftDB.StepSound end,
        set = function(value) CommanderTradecraftDB.StepSound = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })
    panel:AddCheckbox({
        label = "Set Waypoints Through TomTom",
        tooltip = "When TomTom is installed, the Waypoint button on a formula step hands it the vendor's coordinates. Without TomTom the button prints the coordinates to chat instead.",
        get = function() return CommanderTradecraftDB.UseWaypoints end,
        set = function(value) CommanderTradecraftDB.UseWaypoints = value end,
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
    })

    panel:AddSection("Frame")
    Commander.UI.AddHudChromeOptions(panel, CommanderTradecraftDB, "Guide", {
        isEnabled = function() return CommanderTradecraftDB.EnableTradecraft end,
        onChanged = function() Commander.Notify(COMMANDER_TRADECRAFT_EVENTS.UPDATE) end,
    })

    panel:AddButtonRow({
        {
            label = "Open Guide",
            width = 110,
            tooltip = "Show the guide window (also: /ctc).",
            onClick = function() Call("CommanderTradecraft_Show") end,
        },
        {
            label = "Route",
            width = 90,
            tooltip = "The whole route with the alternatives, and where you are on it (also: /ctc route).",
            onClick = function() Call("CommanderTradecraft_Route") end,
        },
        {
            label = "Shopping List",
            width = 120,
            tooltip = "What each trainer bracket needs, less what you hold, then the whole route (also: /ctc shop; /ctc ah sends the current bracket to Auctionator, /ctc ah all the lot).",
            onClick = function() Call("CommanderTradecraft_Shopping") end,
        },
        {
            label = "Reset Progress",
            width = 120,
            tooltip = "Forget this character's path choices and skipped steps. Skill is skill; the guide simply re-reads it.",
            onClick = function() Call("CommanderTradecraft_ResetProgress") end,
        },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page. Route choices and skipped steps are per character and are not touched.",
    })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Tradecraft" then
        Commander.UI.ApplyDefaults(CommanderTradecraftDB, DefaultSettings)
        local char = CommanderTradecraftChar
        char.choices = type(char.choices) == "table" and char.choices or {}
        char.skipped = type(char.skipped) == "table" and char.skipped or {}
        char.knownRecipes = type(char.knownRecipes) == "table" and char.knownRecipes or {}
        char.guide = char.guide or "ENCHANTING"
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
        Call("CommanderTradecraft_OnLogin")
    end
end

frame:SetScript("OnEvent", OnEvent)

CommanderMusterDB = _G.CommanderMusterDB or {}

COMMANDER_MUSTER_EVENTS = {
    UPDATE = "COMMANDER_MUSTER_UPDATE",
    -- Fired with (guid) whenever a player's record changes: a fresh inspect,
    -- an item that finished loading, an arena answer. Own GUID included.
    RECORD = "COMMANDER_MUSTER_RECORD",
}

local DefaultSettings = {
    EnableMuster = true,

    -- Where the readout is drawn
    ShowOnCharacter = true,
    ShowOnInspect = true,

    -- What goes on a player's tooltip
    TooltipGearScore = true,
    TooltipItemLevel = true,
    TooltipArena = true,
    -- Look up players the tooltip does not already know by inspecting them
    -- quietly. Off, the tooltip only knows you and whoever you have opened
    -- the inspect window on.
    InspectOnMouseover = true,
    -- Hold off on the mouseover inspect while in combat: the request is
    -- harmless, but the answer costs a server round trip per new player
    -- under the cursor, and a battleground is the wrong place to spend it.
    InspectInCombat = false,

    -- Readout composition
    ShowAverageItemLevel = true,
    ShowArenaOnReadout = true,
}

CommanderMuster = _G.CommanderMuster or {}
CommanderMuster.Defaults = DefaultSettings

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderMusterDB, DefaultSettings)
    Commander.Notify(COMMANDER_MUSTER_EVENTS.UPDATE)
    print("Commander Muster: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Muster",
        title = "Muster",
        addonName = "Commander_Muster",
        description = "Every player's kit and record at a glance: a gear score and average item level on your character panel, on the inspect window, and on the tooltip of any player you mouse over, with their arena ratings beside it. The score is TacoTip's TBC GearScore, so it reads the same as the number everyone else is quoting; the tooltip fills in from a quiet background inspect of anyone you can inspect and remembers them for the session.",
        event = COMMANDER_MUSTER_EVENTS.UPDATE,
        slash = { "/cmuster", "/gs" },
        slashHandlers = {
            report = function()
                if CommanderMuster_Report then CommanderMuster_Report() end
            end,
            forget = function()
                if CommanderMuster_Forget then CommanderMuster_Forget() end
            end,
        },
    })

    panel:AddSection("Muster")
    panel:AddCheckbox({
        label = "Enable Muster",
        tooltip = "Master switch. Off removes the readouts, stops the tooltip lines, and never inspects anyone on your behalf.",
        get = function() return CommanderMusterDB.EnableMuster end,
        set = function(value) CommanderMusterDB.EnableMuster = value end,
    })

    panel:AddSection("Readout", "The two lines drawn in the top-right corner of the character model.")
    panel:AddCheckboxPair({
        label = "On The Character Panel",
        tooltip = "Draw your own gear score, average item level and arena ratings on the Character tab.",
        get = function() return CommanderMusterDB.ShowOnCharacter end,
        set = function(value) CommanderMusterDB.ShowOnCharacter = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    }, {
        label = "On The Inspect Window",
        tooltip = "Draw the same readout for whoever you inspect, as soon as their gear arrives.",
        get = function() return CommanderMusterDB.ShowOnInspect end,
        set = function(value) CommanderMusterDB.ShowOnInspect = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    })
    panel:AddCheckboxPair({
        label = "Average Item Level",
        tooltip = "Print the average item level beside the score. The score is a weighted ranking; the item level is the plain mean, and needs no formula to trust.",
        get = function() return CommanderMusterDB.ShowAverageItemLevel end,
        set = function(value) CommanderMusterDB.ShowAverageItemLevel = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    }, {
        label = "Arena Ratings",
        tooltip = "Add a second line with the 2v2, 3v3 and 5v5 ratings that are rated this season.",
        get = function() return CommanderMusterDB.ShowArenaOnReadout end,
        set = function(value) CommanderMusterDB.ShowArenaOnReadout = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    })

    panel:AddSection("Player Tooltips", "Lines added to the tooltip of any player you mouse over.")
    panel:AddCheckboxPair({
        label = "Gear Score",
        tooltip = "A Gear score line, coloured by band: grey, white, green, blue, purple and orange, 400 points a band.",
        get = function() return CommanderMusterDB.TooltipGearScore end,
        set = function(value) CommanderMusterDB.TooltipGearScore = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    }, {
        label = "Item Level",
        tooltip = "Print the average item level after the score on the same line.",
        get = function() return CommanderMusterDB.TooltipItemLevel end,
        set = function(value) CommanderMusterDB.TooltipItemLevel = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster and CommanderMusterDB.TooltipGearScore end,
    })
    panel:AddCheckbox({
        label = "Arena Ratings",
        tooltip = "An Arena line with every bracket the player is rated in this season.",
        get = function() return CommanderMusterDB.TooltipArena end,
        set = function(value) CommanderMusterDB.TooltipArena = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    })
    panel:AddCheckboxPair({
        label = "Inspect On Mouseover",
        tooltip = "Look players up as you mouse over them, with a quiet inspect that never opens a window. Only players you could inspect anyway — your own faction, within about 28 yards — and never while you have the inspect window open on somebody else. Off, the tooltip knows only you and whoever you have inspected by hand.",
        get = function() return CommanderMusterDB.InspectOnMouseover end,
        set = function(value) CommanderMusterDB.InspectOnMouseover = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster end,
    }, {
        label = "Even In Combat",
        tooltip = "Keep looking players up while you are in combat. Each new player under the cursor is a server round trip; leaving this off spends none of them in a fight.",
        get = function() return CommanderMusterDB.InspectInCombat end,
        set = function(value) CommanderMusterDB.InspectInCombat = value end,
        isEnabled = function() return CommanderMusterDB.EnableMuster and CommanderMusterDB.InspectOnMouseover end,
    })

    panel:AddButtonRow({
        {
            label = "Report",
            width = 110,
            tooltip = "Print your own score, slot by slot, to the chat frame (also: /gs report).",
            onClick = function()
                if CommanderMuster_Report then CommanderMuster_Report() end
            end,
        },
        {
            label = "Forget All",
            width = 110,
            tooltip = "Drop every player remembered this session so the next mouseover inspects afresh (also: /gs forget).",
            onClick = function()
                if CommanderMuster_Forget then CommanderMuster_Forget() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Muster" then
        Commander.UI.ApplyDefaults(CommanderMusterDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

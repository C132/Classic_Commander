CommanderObjectivesDB = _G.CommanderObjectivesDB or {}

COMMANDER_OBJECTIVES_EVENTS = {
    UPDATE = "COMMANDER_OBJECTIVES_UPDATE"
}

local DefaultSettings = {
    EnableObjectives = true,
    ProgressToasts = true,
    MissionBanner = true,
    ObjectiveSound = true,
    DungeonMissions = true,
    HoldTime = 2.5,
    BoardAlwaysVisible = false,
    BoardHold = 6,
    CompleteEmotes = false,
    EnabledObjectives = {},
}
for key, value in pairs(Commander.UI.HudChromeDefaults("Board", "DARK")) do
    DefaultSettings[key] = value
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderObjectivesDB, DefaultSettings)
    Commander.Notify(COMMANDER_OBJECTIVES_EVENTS.UPDATE)
    print("Commander Objectives: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Objectives",
        title = "Objectives",
        addonName = "Commander_Objectives",
        description = "Mission-objective announcements, RTS campaign style. Quest progress flashes as a toast at the top of the screen as you work (kills, gathers), a green OBJECTIVE SECURED line when a requirement is filled, and a MISSION ACCOMPLISHED banner when a quest is turned in.",
        event = COMMANDER_OBJECTIVES_EVENTS.UPDATE,
        slash = { "/cobj" },
        slashHandlers = {
            test = function()
                if CommanderObjectives_Test then CommanderObjectives_Test() end
            end,
        },
    })

    panel:AddSection("Mission Objectives")
    panel:AddCheckbox({
        label = "Enable Objectives",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderObjectivesDB.EnableObjectives end,
        set = function(value) CommanderObjectivesDB.EnableObjectives = value end,
    })
    panel:AddCheckbox({
        label = "Progress Toasts",
        tooltip = "Show partial quest objective progress (kills, gathers) as a toast at the top of the screen. OBJECTIVE SECURED lines for filled objectives always show while the module is enabled.",
        get = function() return CommanderObjectivesDB.ProgressToasts end,
        set = function(value) CommanderObjectivesDB.ProgressToasts = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddCheckbox({
        label = "Mission Accomplished Banner",
        tooltip = "Show a banner when a quest is turned in.",
        get = function() return CommanderObjectivesDB.MissionBanner end,
        set = function(value) CommanderObjectivesDB.MissionBanner = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddCheckbox({
        label = "Objective Sound",
        tooltip = "Play a chime when an objective is secured or a mission is accomplished.",
        get = function() return CommanderObjectivesDB.ObjectiveSound end,
        set = function(value) CommanderObjectivesDB.ObjectiveSound = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddCheckbox({
        label = "Dungeon Missions",
        tooltip = "In dungeons and raids, run the instance as a mission: MISSION START on entry, banners at kill-count milestones (10, 25, 50...), PRIMARY TARGET ELIMINATED on boss kills, and a run tally when you leave. Feedback the quest system never gives a dungeon group.",
        get = function() return CommanderObjectivesDB.DungeonMissions end,
        set = function(value) CommanderObjectivesDB.DungeonMissions = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddSlider({
        label = "Display Time",
        tooltip = "How long toasts and banners stay on screen.",
        min = 1, max = 5, step = 0.5,
        format = "%.1fs",
        get = function() return CommanderObjectivesDB.HoldTime end,
        set = function(value) CommanderObjectivesDB.HoldTime = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddButtonRow({
        {
            label = "Test Banner",
            width = 120,
            tooltip = "Preview the objective toast and banner (also: /cobj test).",
            onClick = function()
                if CommanderObjectives_Test then CommanderObjectives_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

-- Second subcategory: the mission board and its objective roster. Kept
-- separate from the announcements panel — together they would blow the
-- no-scroll height budget several times over.
local function CreateBoardPanel()
    local panel = Commander.UI.NewPanel({
        key = "ObjectivesBoard",
        title = "Objectives Board",
        addonName = "Commander_Objectives",
        description = "The standing mission board, SC2 style: algorithm-generated grind objectives — kills, primary targets, experience, supplies, quests, honor, survival — tick off as you play, whatever your role. Pick your roster below; the board rerolls fresh for every dungeon run.",
        event = COMMANDER_OBJECTIVES_EVENTS.UPDATE,
    })

    panel:AddCheckboxPair({
        label = "Always Visible",
        tooltip = "Keep the board on screen at all times. Off, it surfaces when an objective progresses and fades again after the linger time.",
        get = function() return CommanderObjectivesDB.BoardAlwaysVisible end,
        set = function(value) CommanderObjectivesDB.BoardAlwaysVisible = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    }, {
        label = "Objective Emotes",
        tooltip = "Announce each completed board objective to everyone nearby as a custom emote, with your running board tally (\"...completes a mission objective — Head Count! (3 of 18 on the board)\"). Public bragging; off by default.",
        get = function() return CommanderObjectivesDB.CompleteEmotes end,
        set = function(value) CommanderObjectivesDB.CompleteEmotes = value end,
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
    })
    panel:AddSlider({
        label = "Linger Time",
        tooltip = "How long the board stays up after the last objective progress before fading.",
        min = 2, max = 20, step = 1,
        format = "%.0fs",
        get = function() return CommanderObjectivesDB.BoardHold end,
        set = function(value) CommanderObjectivesDB.BoardHold = value end,
        isEnabled = function()
            return CommanderObjectivesDB.EnableObjectives and not CommanderObjectivesDB.BoardAlwaysVisible
        end,
    })

    panel:AddSection("Objective Roster")
    local row = panel:AddRow(108, 8)
    local scroll = CreateFrame("ScrollFrame", "CommanderObjectivesRosterScroll", row, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    scroll:SetPoint("RIGHT", row, "RIGHT", -28, 0)
    scroll:SetHeight(100)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 10)
    scroll:SetScrollChild(content)

    local checks = {}
    local offsetY = 0
    for _, def in ipairs(CommanderObjectives_GetRoster()) do
        local check = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
        check:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -offsetY)
        check.Text:SetText(string.format("|cffffd100%s|r  %s", def.category, def.label))
        check:SetScript("OnClick", function(self)
            CommanderObjectivesDB.EnabledObjectives[def.key] = self:GetChecked() and true or false
            Commander.Notify(COMMANDER_OBJECTIVES_EVENTS.UPDATE)
        end)
        checks[def.key] = check
        offsetY = offsetY + 24
    end
    content:SetHeight(offsetY + 4)

    panel:AddRefresher(function()
        for key, check in pairs(checks) do
            check:SetChecked(CommanderObjectivesDB.EnabledObjectives[key] ~= false)
        end
    end)

    Commander.UI.AddHudChromeOptions(panel, CommanderObjectivesDB, "Board", {
        isEnabled = function() return CommanderObjectivesDB.EnableObjectives end,
        onChanged = function() Commander.Notify(COMMANDER_OBJECTIVES_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Objectives" then
        Commander.UI.ApplyDefaults(CommanderObjectivesDB, DefaultSettings)
        if type(CommanderObjectivesDB.EnabledObjectives) ~= "table" then
            CommanderObjectivesDB.EnabledObjectives = {}
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
        CreateBoardPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

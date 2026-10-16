CommanderLadderDB = _G.CommanderLadderDB or {}

COMMANDER_LADDER_EVENTS = {
    UPDATE = "COMMANDER_LADDER_UPDATE",
}

local DefaultSettings = {
    -- Off: Lookup answers nil and no names are saved for the feed
    EnableLadder = true,
}

CommanderLadder.Defaults = DefaultSettings

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderLadderDB, DefaultSettings)
    Commander.Notify(COMMANDER_LADDER_EVENTS.UPDATE)
    print("Commander Ladder: settings restored to defaults")
end

local function Report()
    print("Commander Ladder: " .. CommanderLadder.Status())
    print(string.format("Commander Ladder: %d names waiting for the next feed run", CommanderLadder.WantedCount()))
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Ladder",
        title = "Ladder",
        addonName = "Commander_Ladder",
        description = "Arena ratings for players nobody has inspected. A script on your Mac pulls the 2v2, 3v3 and 5v5 ladders from Blizzard's web API into a file this addon loads at login, and Commander Muster shows those numbers wherever a player's name appears, with their age. Names you meet that the feed lacks are saved for its next run. Run it with: python3 -I Tools/ladder_feed.py run",
        event = COMMANDER_LADDER_EVENTS.UPDATE,
        slash = { "/cladder" },
        slashHandlers = {
            status = Report,
            clear = function()
                CommanderLadder.ClearWanted()
                print("Commander Ladder: names waiting cleared")
            end,
        },
    })

    panel:AddSection("Ladder")
    panel:AddCheckbox({
        label = "Use The Ladder Feed",
        tooltip = "Master switch. Off, Muster shows only ratings it has seen in game, and no names are saved for the feed.",
        get = function() return CommanderLadderDB.EnableLadder end,
        set = function(value) CommanderLadderDB.EnableLadder = value end,
    })

    panel:AddSection("Feed", "The data file is read once, at login or /reload. Run the script again for fresher numbers.")
    local row = panel:AddRow(36, 6)
    local status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    status:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    status:SetJustifyH("LEFT")
    local waiting = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    waiting:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -4)
    waiting:SetJustifyH("LEFT")
    waiting:SetTextColor(0.75, 0.75, 0.75)
    panel:AddRefresher(function()
        status:SetText(CommanderLadder.Status())
        waiting:SetText(string.format("%d names waiting for the next run", CommanderLadder.WantedCount()))
    end)

    panel:AddButtonRow({
        {
            label = "Status",
            width = 110,
            tooltip = "Print the feed's size and age to the chat frame (also: /cladder status).",
            onClick = Report,
        },
        {
            label = "Clear Waiting",
            width = 110,
            tooltip = "Forget every name saved for the next feed run (also: /cladder clear).",
            onClick = function()
                CommanderLadder.ClearWanted()
                panel:Refresh()
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Ladder" then
        Commander.UI.ApplyDefaults(CommanderLadderDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

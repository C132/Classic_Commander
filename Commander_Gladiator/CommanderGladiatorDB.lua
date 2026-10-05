-- Commander Gladiator: what is remembered between sessions, and the settings
-- page.
--
-- Two kinds of thing live in the saved table and they are kept apart on
-- purpose:
--
--   SETTINGS  how the game is shown: the switch and the speed, which have
--             a control each on the page, and two flags that have none --
--             whether the player has ever pinned an enemy and ever tapped a
--             spell, which is all the window's hint waits for. Restore
--             Defaults puts all four back, so it brings the hint back too.
--             None of them changes how a match plays.
--   THE BOOK  what has happened: the record, and the seed the next match
--             will be dealt from. Restore Defaults does NOT touch these --
--             somebody tidying their settings has not asked to lose forty
--             wins -- so they are filled in once, when missing, and only the
--             window ever writes them after that.
--
-- The seed is in the book rather than in the window's head so that a reload
-- carries on down the sequence. Kept only in memory, every session would
-- open on the same seed and play the same first match for ever.
--
-- The window's place on screen is saved here too (`Pos`), by the window, and
-- has no default: until it has been dragged somewhere it opens in the middle.

CommanderGladiatorDB = _G.CommanderGladiatorDB or {}

COMMANDER_GLADIATOR_EVENTS = {
    UPDATE = "COMMANDER_GLADIATOR_UPDATE"
}

local DefaultSettings = {
    Enabled = true,
    Speed = 1,
    Pinned = false,
    Tapped = false,
}

local DefaultBook = {
    Wins = 0,
    Losses = 0,
    Draws = 0,
    -- Where a fresh install starts dealing from, and deliberately not 1.
    -- Every new book plays the same seeds in the same order; the balance is
    -- even over hundreds of them and says nothing about the first dozen,
    -- which are the whole of somebody's first impression. Seeds 104 to 115,
    -- played with the data and engine as they ship, go
    --
    --     won lost lost won won lost won lost lost won won lost
    --
    -- a win to open on, six of each, never three of either running; thirty
    -- in it is fifteen wins and no run past three. (Seed 1 opens on a
    -- defeat.)
    --
    -- The number is only good for the tuning it was measured on: change
    -- anything in the data file or the rules and every seed plays a
    -- different match.
    -- Section A of the UI smoke plays these twelve on every run and goes red
    -- when they stop being a fair opening; that is the time to pick another.
    Seed = 104,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderGladiatorDB, DefaultSettings)
    Commander.Notify(COMMANDER_GLADIATOR_EVENTS.UPDATE)
    print("Commander Gladiator: settings restored to defaults (your record is kept)")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Gladiator",
        title = "Gladiator",
        addonName = "Commander_Gladiator",
        description = "A little 3v3 arena that plays itself while you wait in queue. Your Subtlety Rogue, Frost Mage and Discipline Priest start on the left; an Arms Warrior, Affliction Warlock and Restoration Druid start on the right. Open it with /cglad and watch, or reach in: click an enemy to make it your team's kill target (click it again to let go), and tap a glowing spell under the floor to fire it now. It keeps the score. A match runs about thirty seconds, pauses whenever the window is closed, and the next one starts by itself.",
        event = COMMANDER_GLADIATOR_EVENTS.UPDATE,
        slash = { "/cglad" },
        slashHandlers = {
            -- The bare command is the game, not its settings page: this is a
            -- thing you open between queue pops, and "/cglad settings" (which
            -- the framework adds when the bare command is taken) is one word
            -- away for the two controls there are.
            [""] = function()
                if CommanderGladiator and CommanderGladiator.Toggle then CommanderGladiator.Toggle() end
            end,
        },
    })

    panel:AddSection("Gladiator")
    panel:AddCheckbox({
        label = "Enable Gladiator",
        tooltip = "Master switch. While off, /cglad does not open the arena, and an arena that is open closes.",
        get = function() return CommanderGladiatorDB.Enabled end,
        set = function(value) CommanderGladiatorDB.Enabled = value end,
    })
    panel:AddDropdown({
        label = "Match Speed",
        tooltip = "How fast a match plays. The button in the arena's header flips the same setting.",
        options = {
            { text = "Normal (1x)", value = 1 },
            { text = "Fast (2x)", value = 2 },
        },
        get = function() return CommanderGladiatorDB.Speed end,
        set = function(value) CommanderGladiatorDB.Speed = value end,
        isEnabled = function() return CommanderGladiatorDB.Enabled end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Gladiator" then
        Commander.UI.ApplyDefaults(CommanderGladiatorDB, DefaultSettings)
        Commander.UI.ApplyDefaults(CommanderGladiatorDB, DefaultBook)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

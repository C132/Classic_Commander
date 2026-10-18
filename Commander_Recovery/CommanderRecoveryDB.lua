-- Commander Recovery: settings, the settings page, and the one migration.
--
-- The corpse arrow belongs to Commander Orders since Orders 3.0 (Recovery
-- 2.3.0). Recovery's old "Corpse Run Order" option (CorpseOrder) is gone from
-- the defaults; the checkbox in its place reads and writes Orders' own
-- CorpseArrow setting through Orders' public API, so the two pages can never
-- disagree, and it is greyed out without Orders. A player who had switched
-- the old option OFF keeps the corpse run off: at login the "off" is handed
-- to Orders once and the old key dropped. If Orders is not loaded at that
-- login the key is kept until a login where it is, rather than the choice
-- being lost. IssuedOrder -- the account-wide handle of the order Recovery
-- used to issue -- is dropped outright. Nothing else in Orders' saved
-- variables is read or written from here.

CommanderRecoveryDB = _G.CommanderRecoveryDB or {}

COMMANDER_RECOVERY_EVENTS = {
    UPDATE = "COMMANDER_RECOVERY_UPDATE"
}

local DefaultSettings = {
    EnableRecovery = true,
    DeathReport = true,
    RecoverySound = true,
    AutoRelease = true,
    AutoReleaseArena = false,
    AutoReleaseDelay = 1,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

-- Commander Orders' public table, when loaded (its functions never raise)
local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.CorpseArrow) == "function" and type(api.SetCorpseArrow) == "function" then
        return api
    end
    return nil
end

local function OrdersCorpseArrow()
    local api = Orders()
    if not api then return false end
    local ok, on = pcall(api.CorpseArrow)
    return ok and on and true or false
end

-- 2.2 -> 2.3 (see the header). Idempotent: run at every login.
local function MigrateCorpseOrder()
    local db = CommanderRecoveryDB
    db.IssuedOrder = nil
    if db.CorpseOrder == nil then return end
    if db.CorpseOrder == false then
        local api = Orders()
        if not api then return end
        pcall(api.SetCorpseArrow, false)
    end
    db.CorpseOrder = nil
end

local function Reset()
    Commander.UI.ResetToDefaults(CommanderRecoveryDB, DefaultSettings)
    Commander.Notify(COMMANDER_RECOVERY_EVENTS.UPDATE)
    print("Commander Recovery: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Recovery",
        title = "Recovery",
        addonName = "Commander_Recovery",
        description = "Casualty response, RTS style. When your unit falls, Recovery logs where and when, keeps a session casualty count, and confirms the recovery when you are back on your feet. The run back is Commander Orders' corpse arrow, which points your ghost at the corpse itself (or the dungeon's entrance) and hands the arrow back to whatever you were following once you live. In a battleground, where no one walks back to a corpse, Recovery releases your spirit for you instead.",
        event = COMMANDER_RECOVERY_EVENTS.UPDATE,
        slash = { "/crec" },
        slashHandlers = {
            report = function()
                if CommanderRecovery_Report then CommanderRecovery_Report() end
            end,
            test = function()
                if CommanderRecovery_Test then CommanderRecovery_Test() end
            end,
        },
    })

    panel:AddSection("Casualty Response")
    panel:AddCheckbox({
        label = "Enable Recovery",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderRecoveryDB.EnableRecovery end,
        set = function(value) CommanderRecoveryDB.EnableRecovery = value end,
    })
    panel:AddCheckbox({
        label = "Death Report",
        tooltip = "Print a short casualty report in chat when you die: location and session death count. With Commander Orders the line ends in a [Go] link to the spot: click it for a waypoint there, Shift-click to share it, Ctrl-click to copy its /way line.",
        get = function() return CommanderRecoveryDB.DeathReport end,
        set = function(value) CommanderRecoveryDB.DeathReport = value end,
        isEnabled = function() return CommanderRecoveryDB.EnableRecovery end,
    })
    panel:AddCheckbox({
        label = "Corpse Arrow (Commander Orders)",
        tooltip = "After you release your spirit, point the Commander Orders arrow at your corpse, or at the entrance after a death inside a dungeon, and give the arrow back to what you were following once you live. Battlegrounds and arenas are left alone. This is Commander Orders' own Corpse Arrow setting, shown here too; greyed out without Commander Orders.",
        get = OrdersCorpseArrow,
        set = function(value)
            local api = Orders()
            if api then pcall(api.SetCorpseArrow, value and true or false) end
        end,
        isEnabled = function() return Orders() ~= nil end,
    })
    panel:AddCheckbox({
        label = "Recovery Sound",
        tooltip = "Play a short confirmation when your unit is recovered (back to life).",
        get = function() return CommanderRecoveryDB.RecoverySound end,
        set = function(value) CommanderRecoveryDB.RecoverySound = value end,
        isEnabled = function() return CommanderRecoveryDB.EnableRecovery end,
    })
    panel:AddSection("Battleground Auto-Release",
        "Presses the release button for you when you fall in a battleground — and nowhere else.")
    panel:AddCheckbox({
        label = "Auto-Release in Battlegrounds",
        tooltip = "Release your spirit automatically when you die in a battleground, instead of waiting on the popup — the graveyard's resurrection cycle only starts counting once you are out. Held back whenever a soulstone, reincarnation or incoming resurrection is on offer, and once the match has been decided.",
        get = function() return CommanderRecoveryDB.AutoRelease end,
        set = function(value) CommanderRecoveryDB.AutoRelease = value end,
        isEnabled = function() return CommanderRecoveryDB.EnableRecovery end,
    })
    panel:AddCheckbox({
        label = "Also in Arenas",
        tooltip = "Extend auto-release to arena matches. Off by default: a dead arena player is usually watching the rest of the match, not going anywhere.",
        get = function() return CommanderRecoveryDB.AutoReleaseArena end,
        set = function(value) CommanderRecoveryDB.AutoReleaseArena = value end,
        isEnabled = function()
            return CommanderRecoveryDB.EnableRecovery and CommanderRecoveryDB.AutoRelease
        end,
    })
    panel:AddSlider({
        label = "Release Delay",
        tooltip = "How long to wait after falling before releasing. A short delay leaves room for a healer's resurrection to land — once it is offered, auto-release stands down on its own.",
        min = 0, max = 5, step = 0.5,
        format = function(value)
            if value <= 0 then return "Instant" end
            return string.format("%.1fs", value)
        end,
        get = function() return CommanderRecoveryDB.AutoReleaseDelay end,
        set = function(value) CommanderRecoveryDB.AutoReleaseDelay = value end,
        isEnabled = function()
            return CommanderRecoveryDB.EnableRecovery and CommanderRecoveryDB.AutoRelease
        end,
    })

    panel:AddButtonRow({
        {
            label = "Casualty Report",
            width = 140,
            tooltip = "Print this session's casualty report in chat (also: /crec report).",
            onClick = function()
                if CommanderRecovery_Report then CommanderRecovery_Report() end
            end,
        },
        {
            label = "Test Casualty",
            width = 130,
            tooltip = "Preview the casualty flow: the death report line for your current position, whether the Commander Orders corpse arrow would follow a release, whether auto-release would fire where you are standing, and the recovery sound. No session numbers change (also: /crec test).",
            onClick = function()
                if CommanderRecovery_Test then CommanderRecovery_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Recovery" then
        Commander.UI.ApplyDefaults(CommanderRecoveryDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        -- Orders (an OptionalDep) has loaded its saved variables by now
        MigrateCorpseOrder()
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

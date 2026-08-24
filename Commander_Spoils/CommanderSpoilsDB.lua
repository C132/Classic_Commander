-- Commander Spoils — settings, schema, and the Blizzard-takeover safety layer.
--
-- This file loads FIRST and depends on nothing but Commander.UI. That is
-- deliberate (DECISIONS D5): the suppression module and the `/cspoils restore`
-- panic path live here so that if the engine or the frame file errors at
-- login, the player can still get Blizzard's loot UI back.

CommanderSpoilsDB = _G.CommanderSpoilsDB or {}
-- Second SavedVariables: the ledger. Kept apart from settings so Restore
-- Defaults can never wipe a season of history (and so a history wipe can
-- never reset the player's setup).
CommanderSpoilsData = _G.CommanderSpoilsData or {}

COMMANDER_SPOILS_EVENTS = {
    UPDATE  = "COMMANDER_SPOILS_UPDATE",   -- settings changed
    LOOT    = "COMMANDER_SPOILS_LOOT",     -- (entry) one acquisition, POOLED table
    OUTFLOW = "COMMANDER_SPOILS_OUTFLOW",  -- (entry, reason) one departure, POOLED
    MONEY   = "COMMANDER_SPOILS_MONEY",    -- (copper, isSplit)
    CENSUS  = "COMMANDER_SPOILS_CENSUS",   -- (census) bags settled
    ROLL    = "COMMANDER_SPOILS_ROLL",     -- (roll, phase) "start"|"update"|"resolved"
    SEGMENT = "COMMANDER_SPOILS_SEGMENT",  -- (segment) a segment closed
}

-- ---------------------------------------------------------------------------
-- Schema versioning. MIGRATIONS[n] migrates version n -> n+1.
-- ---------------------------------------------------------------------------
local DB_VERSION = 2
local MIGRATIONS = {
    -- v1 is the pre-v3 toast addon, which had no version stamp at all. Two of
    -- its keys survive into v3 with CHANGED MEANING and must not be inherited:
    -- MinQuality was "what raises a toast" and is now the bottom rule of the
    -- interest model (a saved 0 would announce every grey), and the old sound
    -- flag is gone. The per-surface chrome blocks go too — v3 has one frame.
    [1] = function(db)
        db.MinQuality = nil
        db.SpoilsSound = nil
        db.SoundRollWon = nil
        for _, prefix in ipairs({ "Contest", "Salvage", "Wire", "Docket", "Take" }) do
            for _, suffix in ipairs({ "Style", "Scale", "Locked", "Pos" }) do
                db[prefix .. suffix] = nil
            end
        end
    end,
}

local function Migrate(db)
    -- `or 1`, not `or DB_VERSION`: an unstamped table is the old addon's, and
    -- defaulting it to current would skip the migration that exists for it.
    local v = tonumber(db.DBVersion) or 1
    while v < DB_VERSION do
        local step = MIGRATIONS[v]
        if step then step(db) end
        v = v + 1
    end
    db.DBVersion = DB_VERSION
end

-- ---------------------------------------------------------------------------
-- Defaults
--
-- The preference count is derived, not accumulated (D20). Suppressions are
-- exempt from the ceiling: they are a safety surface, not preferences, and
-- every one of them must be individually reversible.
-- ---------------------------------------------------------------------------
local DefaultSettings = {
    EnableSpoils = true,

    -- Blizzard takeover. All nine are runtime-only: a replaced function
    -- pointer, an event registration, a chat filter. Nothing is written
    -- anywhere that outlives the addon.
    --
    -- Every one of them DEFAULTS OFF. Taking over the loot interface is a
    -- decision, and "Restore Defaults" has to mean what it says — with these
    -- defaulting on, that button performed a full takeover on a player who
    -- clicked it to get back to a clean state.
    SuppressLootWindow  = false,
    SuppressRollPopups  = false,
    SuppressChatLoot    = false,
    SuppressChatMoney   = false,
    SuppressChatCurrency = false,
    SuppressLootHistory = false,
    SuppressBindConfirm = false,
    SuppressChatGuildLoot = false, -- "X has looted [Epic]" rides the GUILD group
    SuppressItemPush    = false,   -- ambient feedback nobody complains about (D4)

    -- Appearance (baked into the window at login, /reload to apply)
    AccentColor = "AMBER",
    IconRecess = "SOFT",     -- shared suite icon shading: OFF|SOFT|DEEP|CARVED

    -- Window geometry
    FrameWidth = 350,
    MaxRows    = 12,
    -- Caps every band so the frame's height is bounded and predictable instead
    -- of jumping every time a roll opens or a corpse is bigger than the last.
    FixedSize  = true,
    MaxRollRows = 3,
    MaxSlotRows = 8,

    -- Keeps the window parked on screen even with nothing happening and the
    -- panes closed — the header alone is a one-line value/items/bags readout.
    AlwaysShow = false,

    -- Live relative ages ("2m ago") are the only thing that forces a repaint
    -- on a clock rather than on a change. Off, the feed shows a fixed clock
    -- time and the window repaints only when something actually happens.
    LiveAges = true,

    -- Persisted view state (written by the window chrome, no panel widget)
    SeenIntro  = false,
    ViewMode   = "FEED",     -- FEED | HAUL | ROLLS | BAGS | PARTY
    ViewScope  = "SESSION",  -- SESSION | RUN | HOUR
    FeedFilter = "ALL",      -- ALL | MINE | NOTABLE
    HaulSort   = "VALUE",    -- VALUE | QTY | NAME

    -- The interest model (D16): pins beat class switches beat the floor.
    MinQuality        = 3,     -- bottom rule: unmatched items toast at rare+
    FilterArmor       = true,  -- gear for my armor type
    FilterRecipes     = true,
    FilterTradeGoods  = true,  -- "did I loot some cloth"
    FilterConsumables = false,
    FilterQuest       = true,
    FilterBoP         = true,
    PinnedItems       = {},    -- [itemID] = true (always) | false (never)

    -- Notifications
    WireQuietWhenOpen = true,
    SoundRollOpen     = true,   -- the one aggressive default; the brief asks for it
    -- On by default: "know I actually won" is the requirement, and a text line
    -- on a strip you may not be looking at is not an answer to it.
    SoundRollWon      = true,
    SoundToast        = false,
    EpicFlash         = true,

    -- Rolls
    RollWarnAt          = 15,
    RollCriticalAt      = 5,
    RollEdgeGlow        = true,
    RollEdgeGlowMinQuality = 2,
    AutoPassBelowQuality = 0,   -- 0 = off. Never silent: leaves a ghost row.
    CollapseIneligible  = true,
    RollGuardMs         = 300,

    -- Loot window
    SalvageAnchor = "CURSOR",   -- CURSOR | FIXED — only while collapsed
    Expanded = false,           -- the browsing panes, vs the live bands alone

    -- Ledger
    ValueMode    = "VENDOR",    -- VENDOR | MARKET (never blended, D13)
    TrackHistory = true,
    HistoryDays  = 60,
    JunkWarnSlots = 6,
}
-- One frame, one chrome block. Every surface that used to carry its own
-- position, scale and lock is now a band inside it (D1).
for key, value in pairs(Commander.UI.HudChromeDefaults("Hud", "DARK")) do
    DefaultSettings[key] = value
end

-- ===========================================================================
-- Suppression — the safety layer
--
-- Restore is EXACT, not approximate. There is no event-enumeration API on
-- 2.5.6, so each frame's FrameXML event list is hardcoded, each event is
-- probed with IsEventRegistered before being unregistered, and only the set
-- that was actually on is restored. Approximating this is the failure mode
-- where restore silently leaves one event dead and the bug surfaces weeks
-- later at a vendor.
-- ===========================================================================
CommanderSpoils_Suppression = {}
local Suppression = CommanderSpoils_Suppression

-- FrameXML's own registrations, from Blizzard_UIPanels_Game/Classic/LootFrame.lua
local LOOT_FRAME_EVENTS = {
    "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED", "LOOT_CLOSED",
    "LOOT_READY", "OPEN_MASTER_LOOT_LIST", "UPDATE_MASTER_LOOT_LIST",
}
local LOOT_HISTORY_EVENTS = {
    "LOOT_HISTORY_FULL_UPDATE", "LOOT_HISTORY_ROLL_CHANGED",
    "LOOT_HISTORY_ROLL_COMPLETE", "LOOT_HISTORY_AUTO_SHOW",
}
local BAG_BUTTONS = {
    "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
}

-- What was on before we touched it. Keyed by frame name -> { event = true }.
local savedEvents = {}
local savedOpenNewFrame = nil
local chatFilters = {}
local active = {}   -- [switchKey] = true while suppressed

local function SilenceFrame(name, events)
    local frame = _G[name]
    if not frame or savedEvents[name] then return end
    local saved = {}
    for _, event in ipairs(events) do
        local ok, registered = pcall(frame.IsEventRegistered, frame, event)
        if ok and registered then
            saved[event] = true
            pcall(frame.UnregisterEvent, frame, event)
        end
    end
    savedEvents[name] = saved
end

local function RestoreFrame(name)
    local saved = savedEvents[name]
    if not saved then return end
    local frame = _G[name]
    if frame then
        for event in pairs(saved) do
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    savedEvents[name] = nil
end

-- Chat suppression uses message-event FILTERS, never RemoveMessageGroup:
-- the latter writes the character's saved chat settings and is not cleanly
-- reversible. Filters also leave our own event registrations firing.
local function AddFilter(event)
    if chatFilters[event] then return end
    local filter = function() return true end
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
        or _G.ChatFrame_AddMessageEventFilter
    if not add then return end
    if pcall(add, event, filter) then
        chatFilters[event] = filter
    end
end

local function RemoveFilter(event)
    local filter = chatFilters[event]
    if not filter then return end
    local remove = (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter)
        or _G.ChatFrame_RemoveMessageEventFilter
    if remove then pcall(remove, event, filter) end
    chatFilters[event] = nil
end

local NOOP = function() end

local Switches   -- forward: [key] = { label, on, off }
Switches = {
    SuppressLootWindow = {
        label = "Blizzard loot window",
        -- Never :Hide() LootFrame while it is shown — LootFrame_OnHide calls
        -- CloseLoot(), which would end the server-side loot session. With its
        -- events unregistered it never shows, so OnHide never fires.
        on = function()
            SilenceFrame("LootFrame", LOOT_FRAME_EVENTS)
            if MasterLooterFrame then pcall(MasterLooterFrame.Hide, MasterLooterFrame) end
            if BonusRollFrame then
                SilenceFrame("BonusRollFrame", { "BONUS_ROLL_ACTIVATE", "BONUS_ROLL_DEACTIVATE",
                    "BONUS_ROLL_RESULT", "PLAYER_LOOT_SPEC_UPDATED" })
            end
        end,
        off = function()
            RestoreFrame("LootFrame")
            RestoreFrame("BonusRollFrame")
        end,
    },
    SuppressRollPopups = {
        label = "Blizzard roll pop-ups",
        -- UIParent (not the roll frames) handles START_LOOT_ROLL and calls the
        -- plain global GroupLootFrame_OpenNewFrame. Replacing that global is
        -- the clean cut; UIParent:UnregisterEvent is a known taint vector and
        -- is never touched.
        on = function()
            if savedOpenNewFrame == nil and type(_G.GroupLootFrame_OpenNewFrame) == "function" then
                savedOpenNewFrame = _G.GroupLootFrame_OpenNewFrame
                _G.GroupLootFrame_OpenNewFrame = NOOP
            end
            for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
                local frame = _G["GroupLootFrame" .. i]
                if frame then
                    SilenceFrame("GroupLootFrame" .. i, { "CANCEL_LOOT_ROLL" })
                    pcall(frame.Hide, frame)
                end
            end
            if GroupLootContainer then pcall(GroupLootContainer.Hide, GroupLootContainer) end
        end,
        off = function()
            if savedOpenNewFrame then
                _G.GroupLootFrame_OpenNewFrame = savedOpenNewFrame
                savedOpenNewFrame = nil
            end
            for i = 1, (NUM_GROUP_LOOT_FRAMES or 4) do
                RestoreFrame("GroupLootFrame" .. i)
            end
        end,
    },
    SuppressChatLoot = {
        label = "Loot lines in chat",
        on  = function() AddFilter("CHAT_MSG_LOOT") end,
        off = function() RemoveFilter("CHAT_MSG_LOOT") end,
    },
    SuppressChatMoney = {
        label = "Money lines in chat",
        on  = function() AddFilter("CHAT_MSG_MONEY") end,
        off = function() RemoveFilter("CHAT_MSG_MONEY") end,
    },
    SuppressChatCurrency = {
        label = "Currency lines in chat",
        on  = function() AddFilter("CHAT_MSG_CURRENCY") end,
        off = function() RemoveFilter("CHAT_MSG_CURRENCY") end,
    },
    SuppressLootHistory = {
        label = "Blizzard loot history window",
        on = function()
            SilenceFrame("LootHistoryFrame", LOOT_HISTORY_EVENTS)
            if LootHistoryFrame then pcall(LootHistoryFrame.Hide, LootHistoryFrame) end
        end,
        off = function() RestoreFrame("LootHistoryFrame") end,
    },
    SuppressChatGuildLoot = {
        label = "Guild loot lines in chat",
        -- CHAT_MSG_GUILD_ITEM_LOOTED lives in the GUILD message group, not
        -- LOOT, so "remove all loot lines" needs it named separately.
        on  = function() AddFilter("CHAT_MSG_GUILD_ITEM_LOOTED") end,
        off = function() RemoveFilter("CHAT_MSG_GUILD_ITEM_LOOTED") end,
    },
    SuppressBindConfirm = {
        -- No frame work: the engine reads this flag and hides the StaticPopup
        -- itself, driving ConfirmLootSlot/ConfirmLootRoll from our own rows.
        -- Tracked here anyway so one status line can answer "what is off".
        label = "Bind-on-pickup confirmations",
        on = NOOP, off = NOOP,
    },
    SuppressItemPush = {
        label = "Flying item icon to your bags",
        on = function()
            for _, name in ipairs(BAG_BUTTONS) do
                SilenceFrame(name, { "ITEM_PUSH" })
            end
        end,
        off = function()
            for _, name in ipairs(BAG_BUTTONS) do RestoreFrame(name) end
        end,
    },
}
Suppression.Switches = Switches

-- The eight the takeover button turns on. ItemPush is deliberately not one of
-- them: it is the only surface the player never asked us to touch.
-- Deterministic order for the settings page and the status line.
Suppression.Order = {
    "SuppressLootWindow", "SuppressRollPopups", "SuppressChatLoot",
    "SuppressChatMoney", "SuppressChatCurrency", "SuppressChatGuildLoot",
    "SuppressLootHistory", "SuppressBindConfirm", "SuppressItemPush",
}

function Suppression.IsActive(key)
    return active[key] == true
end

-- Brings the live state in line with the settings. Idempotent — safe to call
-- from Apply() on every settings notify.
-- Set by the watchdog. Once the UI has been declared dead, no settings write
-- and no /cspoils takeover may re-suppress anything — otherwise a player
-- investigating the warning re-breaks their own loot UI with one checkbox.
local blocked = false

function Suppression.Block() blocked = true end

function Suppression.Sync()
    local master = CommanderSpoilsDB.EnableSpoils and not blocked
    for _, key in ipairs(Suppression.Order) do
        local want = master and CommanderSpoilsDB[key] and true or false
        if want ~= (active[key] == true) then
            local switch = Switches[key]
            local ok, err = pcall(want and switch.on or switch.off)
            if ok then
                active[key] = want or nil
            else
                geterrorhandler()(err)
            end
        end
    end
end

-- Hands every live suppression back WITHOUT touching the settings, so a
-- transient failure never permanently unticks a switch the player chose.
-- Returns the labels it restored.
function Suppression.Undo()
    local restored = {}
    for _, key in ipairs(Suppression.Order) do
        if active[key] then
            local ok, err = pcall(Switches[key].off)
            if not ok then geterrorhandler()(err) end
            restored[#restored + 1] = Switches[key].label
        end
        active[key] = nil
    end
    return restored
end

-- The panic path. Undo, AND untick every toggle so the next Sync() cannot
-- silently re-apply them.
function Suppression.RestoreAll(quiet)
    blocked = false
    local restored = Suppression.Undo()
    for _, key in ipairs(Suppression.Order) do
        CommanderSpoilsDB[key] = false
    end
    if not quiet then
        if #restored == 0 then
            print("|cff66ccffCommander Spoils|r: nothing was suppressed — Blizzard's UI is intact")
        else
            print("|cff66ccffCommander Spoils|r: restored " .. table.concat(restored, ", "))
        end
    end
    if Commander and Commander.Notify then
        Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    end
    return restored
end

function Suppression.TakeOverAll()
    for _, key in ipairs(Suppression.Order) do
        -- ItemPush stays opt-in even here: it is the one surface the player
        -- never asked us to touch.
        if key ~= "SuppressItemPush" then CommanderSpoilsDB[key] = true end
    end
    CommanderSpoilsDB.EnableSpoils = true
    Suppression.Sync()
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    print("|cff66ccffCommander Spoils|r: Blizzard's loot interface is now handled by Spoils (/cspoils restore undoes this)")
end

-- Human-readable "what is off right now", for the settings status line.
function Suppression.StatusText()
    local parts = {}
    for _, key in ipairs(Suppression.Order) do
        if active[key] then parts[#parts + 1] = Switches[key].label:upper() end
    end
    if #parts == 0 then
        return "NOTHING SUPPRESSED — BLIZZARD'S UI IS INTACT"
    end
    return "CURRENTLY SUPPRESSED: " .. table.concat(parts, " · ")
end

-- ===========================================================================
-- Settings panel
-- ===========================================================================
local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Enabled()
    return CommanderSpoilsDB.EnableSpoils
end

local function Reset()
    Commander.UI.ResetToDefaults(CommanderSpoilsDB, DefaultSettings)
    Suppression.Sync()
    Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE)
    print("Commander Spoils: settings restored to defaults — Blizzard's loot interface is back, and your history is untouched (/cspoils wipe clears that).")
end

-- The page carries a safety block, five feature blocks and four chrome
-- blocks, so its rows flow into a scroll frame. AddRow is overridden on the
-- panel INSTANCE only — the shared framework is untouched (the
-- Meters/Reticle/Quartermaster pattern).
local function MakeScrollable(panel, frameName)
    local scroll = CreateFrame("ScrollFrame", frameName, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel._anchor, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 12)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 28
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:SetScript("OnSizeChanged", function(_, width) scrollChild:SetWidth(width) end)

    local seed = CreateFrame("Frame", nil, scrollChild)
    seed:SetHeight(1)
    seed:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    seed:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    panel._anchor = seed
    panel._contentHeight = 0
    panel.AddRow = function(self, height, spacing)
        local row = CreateFrame("Frame", nil, scrollChild)
        row:SetHeight(height)
        row:SetPoint("TOPLEFT", self._anchor, "BOTTOMLEFT", 0, -(spacing or 8))
        row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
        self._anchor = row
        self._contentHeight = self._contentHeight + height + (spacing or 8)
        return row
    end

    return function()
        scrollChild:SetHeight(panel._contentHeight + 24)
    end
end

-- Every suppression tooltip names three things: what is hidden, what replaces
-- it, and what happens when the switch is OFF. That third clause is what kills
-- the support question.
local SUPPRESS_TOOLTIPS = {
    SuppressLootWindow = "Hides Blizzard's loot window; the Salvage panel opens at the corpse instead, with every slot on one page.|n|nOff: Blizzard's loot window opens as well as ours.",
    SuppressRollPopups = "Hides the Need/Greed/Pass pop-ups; rolls appear in the Contest strip with a timer, a bind warning and the live roster.|n|nOff: both sets of roll buttons appear.",
    SuppressChatLoot = "Removes loot lines from chat. They appear in the FEED instead, permanently, with a filter.|n|nOff: chat keeps its loot lines and the FEED fills too.",
    SuppressChatMoney = "Removes money lines from chat. Coin still lands in the FEED and the header total.|n|nOff: chat keeps its money lines.",
    SuppressChatCurrency = "Removes currency lines (badges, marks) from chat. They appear in the FEED.|n|nOff: chat keeps its currency lines.",
    SuppressChatGuildLoot = "Removes guild 'has looted' lines from chat. They still reach the FEED.|n|nOff: guild loot announcements stay in chat.",
    SuppressLootHistory = "Hides Blizzard's loot history window; the ROLLS pane holds the same information and keeps it after the server forgets.|n|nOff: Blizzard's history window opens on its own again.",
    SuppressBindConfirm = "Replaces the centre-screen 'this will bind to you' dialog with an inline confirm on the item's own row, so you can still see what else is on the corpse.|n|nOff: Blizzard's dialog appears.",
    SuppressItemPush = "Stops the item icon flying to your bag button on every pickup.|n|nOff (default): the flying icon is left alone. This is the one surface Spoils does not touch unless you ask.",
}

-- Local presets first, then every Commander_Console tint. Console is optional,
-- so its table is read live with `or {}` and its parentheticals stripped; a
-- saved value with no matching option gets an orphan entry rather than
-- rendering the dropdown blank.
local BUILTIN_ACCENTS = {
    { text = "Amber", value = "AMBER" },
    { text = "Cyan", value = "CYAN" },
    { text = "Green", value = "GREEN" },
    { text = "White", value = "WHITE" },
}

local function AccentOptions()
    local options = {}
    local seen = {}
    for _, entry in ipairs(BUILTIN_ACCENTS) do
        options[#options + 1] = { text = entry.text, value = entry.value }
        seen[entry.value] = true
    end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value and not seen[color.value] then
            seen[color.value] = true
            options[#options + 1] = {
                text = (color.text or color.value):gsub("%s*%(.-%)$", ""),
                value = color.value,
            }
        end
    end
    local current = CommanderSpoilsDB.AccentColor
    if current and not seen[current] then
        options[#options + 1] = {
            text = current .. " (Commander_Console missing — shown as Amber)",
            value = current,
        }
    end
    return options
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Spoils",
        title = "Spoils",
        addonName = "Commander_Spoils",
        description = "Spoils replaces Blizzard's loot interface — the loot window, the roll pop-ups and the loot lines in chat — with one window that keeps all of it. Nothing is deleted; it moves. Every pickup, every roll and every copper becomes a row you can still read an hour later, and the takeover is eight independent switches you can undo at any time with /cspoils restore.",
        event = COMMANDER_SPOILS_EVENTS.UPDATE,
        slash = { "/cspoils", "/cloot" },
        slashHandlers = {
            [""] = function()
                if CommanderSpoils_Toggle then CommanderSpoils_Toggle() end
            end,
            settings = function() Commander.OpenModuleSettings("Spoils") end,
            restore = function() Suppression.RestoreAll() end,
            takeover = function() Suppression.TakeOverAll() end,
            report = function()
                if CommanderSpoils_Report then CommanderSpoils_Report() end
            end,
            wipe = function()
                if CommanderSpoils_Wipe then CommanderSpoils_Wipe() end
            end,
            farm = function()
                if CommanderSpoils_ToggleFarm then CommanderSpoils_ToggleFarm() end
            end,
            test = function() if CommanderSpoils_Test then CommanderSpoils_Test("pickup") end end,
            ["test pickup"] = function() CommanderSpoils_Test("pickup") end,
            ["test roll"]   = function() CommanderSpoils_Test("roll") end,
            ["test wave"]   = function() CommanderSpoils_Test("wave") end,
            ["test win"]    = function() CommanderSpoils_Test("win") end,
            ["test corpse"] = function() CommanderSpoils_Test("corpse") end,
            ["test clear"]  = function() CommanderSpoils_Test("clear") end,
            size = function()
                if CommanderSpoils_PrintSize then CommanderSpoils_PrintSize() end
            end,
        },
    })
    local FinishScroll = MakeScrollable(panel, "CommanderSpoilsSettingsScroll")

    -- ---- Blizzard takeover comes FIRST. Honesty in sentence one. ----------
    panel:AddSection("Blizzard Takeover",
        "Each switch is runtime-only — a hidden frame, an unregistered event, a chat filter. Nothing is written that outlives the addon, so disabling Commander Spoils in the addon list gives you Blizzard's loot UI back on its own.")

    local statusRow = panel:AddRow(16, 2)
    local statusText = statusRow:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("LEFT", statusRow, "LEFT", 16, 0)
    statusText:SetPoint("RIGHT", statusRow, "RIGHT", -16, 0)
    statusText:SetJustifyH("LEFT")
    panel:AddRefresher(function()
        local text = Suppression.StatusText()
        statusText:SetText(text)
        if text:find("NOTHING") then
            statusText:SetTextColor(0.5, 0.85, 0.5)
        else
            statusText:SetTextColor(1, 0.75, 0.35)
        end
    end)

    local function SuppressBox(key)
        return {
            label = Suppression.Switches[key].label,
            tooltip = SUPPRESS_TOOLTIPS[key],
            get = function() return CommanderSpoilsDB[key] end,
            set = function(value)
                CommanderSpoilsDB[key] = value
                Suppression.Sync()
            end,
            isEnabled = Enabled,
        }
    end
    local order = Suppression.Order
    for i = 1, #order, 2 do
        panel:AddCheckboxPair(SuppressBox(order[i]), order[i + 1] and SuppressBox(order[i + 1]))
    end

    panel:AddButtonRow({
        {
            label = "Restore Everything Blizzard",
            width = 190,
            tooltip = "Unticks every switch above and hands the loot window, the roll pop-ups and the chat lines straight back. Also available as /cspoils restore, which works even if the rest of the addon failed to load.",
            onClick = function() Suppression.RestoreAll() end,
        },
        {
            label = "Take Over Everything",
            width = 170,
            tooltip = "Ticks every switch except the flying bag icon.",
            onClick = function() Suppression.TakeOverAll() end,
        },
    })

    -- ---- The window ------------------------------------------------------
    panel:AddSection("Window")
    panel:AddCheckboxPair({
        label = "Enable Spoils",
        tooltip = "Master switch. Turning this off restores every Blizzard surface immediately — no /reload needed.",
        get = function() return CommanderSpoilsDB.EnableSpoils end,
        set = function(value)
            CommanderSpoilsDB.EnableSpoils = value
            Suppression.Sync()
        end,
    }, {
        label = "Quiet toasts while the window is open",
        tooltip = "A pickup you can already see in the FEED does not also need a toast.",
        get = function() return CommanderSpoilsDB.WireQuietWhenOpen end,
        set = function(value) CommanderSpoilsDB.WireQuietWhenOpen = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Accent Color",
        tooltip = "Colours live rolls, the selected pane and new rows. Takes effect after /reload (baked into the window at login).|n|nThe suite tints come from Commander_Console; without it the four built-ins remain.",
        options = AccentOptions(),
        width = 220,
        get = function() return CommanderSpoilsDB.AccentColor end,
        set = function(value)
            CommanderSpoilsDB.AccentColor = value
            print("|cff66ccffCommander Spoils|r: accent applies after /reload")
        end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Icon Recess",
        tooltip = "Shading laid over every item icon in the window so it reads as set into the row rather than pasted on it. The art is the suite's shared set, so an icon here is cut the same way as one on any other Commander board.|n|nSoft is a shallow press, which is what a small row icon wants; Deep and Carved drive it harder.",
        options = Commander.ICON_STYLES,
        width = 220,
        get = function() return CommanderSpoilsDB.IconRecess end,
        set = function(value) CommanderSpoilsDB.IconRecess = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Always show the window",
        tooltip = "Keeps Spoils on screen with nothing happening. Collapsed and idle that is just the header — value, item count and bag space — so it reads as a small status line rather than a window.|n|nOff, it appears for a pickup, a corpse or a roll and leaves again.",
        get = function() return CommanderSpoilsDB.AlwaysShow end,
        set = function(value) CommanderSpoilsDB.AlwaysShow = value end,
        isEnabled = Enabled,
    }, {
        label = "Fixed size",
        tooltip = "Caps each band so the window's height stops changing every time a roll opens or a corpse is larger than the last. Overflow is stated rather than hidden.",
        get = function() return CommanderSpoilsDB.FixedSize end,
        set = function(value) CommanderSpoilsDB.FixedSize = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Live ages in the feed",
        tooltip = "Shows how long ago each row happened, counting up. This is the only thing that makes the window repaint on a clock instead of when something happens — turn it off if the window costs you frames.",
        get = function() return CommanderSpoilsDB.LiveAges end,
        set = function(value) CommanderSpoilsDB.LiveAges = value end,
        isEnabled = Enabled,
    }, nil)
    panel:AddSliderPair({
        label = "Rows in the roll band",
        tooltip = "How many live rolls the band shows before it says how many more there are.",
        min = 1, max = 8, step = 1, format = "%d",
        get = function() return CommanderSpoilsDB.MaxRollRows end,
        set = function(value) CommanderSpoilsDB.MaxRollRows = value end,
        isEnabled = function() return Enabled() and CommanderSpoilsDB.FixedSize end,
    }, {
        label = "Rows on a corpse",
        tooltip = "How many loot slots the corpse band shows at once.",
        min = 4, max = 20, step = 1, format = "%d",
        get = function() return CommanderSpoilsDB.MaxSlotRows end,
        set = function(value) CommanderSpoilsDB.MaxSlotRows = value end,
        isEnabled = function() return Enabled() and CommanderSpoilsDB.FixedSize end,
    })
    panel:AddSliderPair({
        label = "Frame Width",
        tooltip = "Width of the Spoils window.",
        min = 280, max = 520, step = 10, format = "%d",
        get = function() return CommanderSpoilsDB.FrameWidth end,
        set = function(value) CommanderSpoilsDB.FrameWidth = value end,
        isEnabled = Enabled,
    }, {
        label = "Rows",
        tooltip = "How many rows the body shows before it scrolls.",
        min = 6, max = 24, step = 1, format = "%d",
        get = function() return CommanderSpoilsDB.MaxRows end,
        set = function(value) CommanderSpoilsDB.MaxRows = value end,
        isEnabled = Enabled,
    })

    -- ---- Rolls -----------------------------------------------------------
    panel:AddSection("Rolls",
        "The Contest strip is the only thing in Spoils that appears on its own, because a roll is the only loot event with a deadline.")
    panel:AddCheckboxPair({
        label = "Chime when a roll opens",
        tooltip = "One sound per batch, not one per item — six greens in the same second is one chime.",
        get = function() return CommanderSpoilsDB.SoundRollOpen end,
        set = function(value) CommanderSpoilsDB.SoundRollOpen = value end,
        isEnabled = Enabled,
    }, {
        label = "Fanfare when you win",
        tooltip = "A separate sound for a roll you actually won.",
        get = function() return CommanderSpoilsDB.SoundRollWon end,
        set = function(value) CommanderSpoilsDB.SoundRollWon = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Screen edge glow when time is short",
        tooltip = "The edges of the screen warm up as a roll runs down. Computed across every pending roll at once, so a wave pull glows once.",
        get = function() return CommanderSpoilsDB.RollEdgeGlow end,
        set = function(value) CommanderSpoilsDB.RollEdgeGlow = value end,
        isEnabled = Enabled,
    }, {
        label = "Collapse rolls you cannot enter",
        tooltip = "When you can neither Need nor Greed there is nothing to do — the row shrinks to one line with the reason and still goes in the log.",
        get = function() return CommanderSpoilsDB.CollapseIneligible end,
        set = function(value) CommanderSpoilsDB.CollapseIneligible = value end,
        isEnabled = Enabled,
    })
    panel:AddSliderPair({
        label = "Warn at",
        tooltip = "Seconds left when a roll starts pressing for an answer.",
        min = 5, max = 40, step = 1, format = "%d sec",
        get = function() return CommanderSpoilsDB.RollWarnAt end,
        set = function(value) CommanderSpoilsDB.RollWarnAt = value end,
        isEnabled = Enabled,
    }, {
        label = "Critical at",
        tooltip = "Seconds left when the bar gives way to a plain countdown.",
        min = 2, max = 15, step = 1, format = "%d sec",
        get = function() return CommanderSpoilsDB.RollCriticalAt end,
        set = function(value) CommanderSpoilsDB.RollCriticalAt = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Auto-pass below",
        tooltip = "Passes low-quality rolls for you after a two-second grace. It is never silent: the row stays as a grey ghost saying what it passed, so a setting can never quietly cost you an item.|n|nThere is deliberately no auto-need at any quality.",
        options = {
            { text = "Off — decide everything yourself", value = 0 },
            { text = "Poor", value = 1 },
            { text = "Poor and common", value = 2 },
            { text = "Below rare", value = 3 },
        },
        width = 220,
        get = function() return CommanderSpoilsDB.AutoPassBelowQuality end,
        set = function(value) CommanderSpoilsDB.AutoPassBelowQuality = value end,
        isEnabled = Enabled,
    })

    -- ---- What gets announced --------------------------------------------
    panel:AddSection("What Gets Announced",
        "Rules run top down and the first match wins: items you pinned with a right-click, then these classes, then the quality floor for everything else.")
    panel:AddCheckboxPair({
        label = "Gear for my armor type",
        tooltip = "Armor that matches the class's proficiency. Named for what it can actually tell — weapon usability is not reliably derivable on this client, so it is not claimed.",
        get = function() return CommanderSpoilsDB.FilterArmor end,
        set = function(value) CommanderSpoilsDB.FilterArmor = value end,
        isEnabled = Enabled,
    }, {
        label = "Recipes and patterns",
        tooltip = "Anything in the recipe class, at any quality.",
        get = function() return CommanderSpoilsDB.FilterRecipes end,
        set = function(value) CommanderSpoilsDB.FilterRecipes = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Trade goods",
        tooltip = "Cloth, leather, ore, herbs, motes, enchanting materials — the farming loop.",
        get = function() return CommanderSpoilsDB.FilterTradeGoods end,
        set = function(value) CommanderSpoilsDB.FilterTradeGoods = value end,
        isEnabled = Enabled,
    }, {
        label = "Consumables",
        tooltip = "Potions, elixirs, food, scrolls.",
        get = function() return CommanderSpoilsDB.FilterConsumables end,
        set = function(value) CommanderSpoilsDB.FilterConsumables = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Quest items",
        tooltip = "Anything in the quest class.",
        get = function() return CommanderSpoilsDB.FilterQuest end,
        set = function(value) CommanderSpoilsDB.FilterQuest = value end,
        isEnabled = Enabled,
    }, {
        label = "Anything bind-on-pickup",
        tooltip = "If it bound the moment you took it, it was worth telling you about.",
        get = function() return CommanderSpoilsDB.FilterBoP end,
        set = function(value) CommanderSpoilsDB.FilterBoP = value end,
        isEnabled = Enabled,
    })
    panel:AddDropdown({
        label = "Everything else, from",
        tooltip = "The bottom rule. It only decides items no rule above matched.",
        options = {
            { text = "Poor and up (everything)", value = 0 },
            { text = "Common and up", value = 1 },
            { text = "Uncommon and up", value = 2 },
            { text = "Rare and up", value = 3 },
            { text = "Epic and up", value = 4 },
            { text = "Nothing else", value = 6 },
        },
        width = 200,
        get = function() return CommanderSpoilsDB.MinQuality end,
        set = function(value) CommanderSpoilsDB.MinQuality = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Chime on a toast",
        tooltip = "A sound for anything that raises a toast.",
        get = function() return CommanderSpoilsDB.SoundToast end,
        set = function(value) CommanderSpoilsDB.SoundToast = value end,
        isEnabled = Enabled,
    }, {
        label = "Epic screen flash",
        tooltip = "Epic or better flashes the screen edge purple. You earned it.",
        get = function() return CommanderSpoilsDB.EpicFlash end,
        set = function(value) CommanderSpoilsDB.EpicFlash = value end,
        isEnabled = Enabled,
    })

    -- ---- Ledger ----------------------------------------------------------
    panel:AddSection("Ledger",
        "Vendor price is the floor and is always exact. Market price comes from Auctionator when it is installed and its scan is fresh; it is never mixed into the vendor number.")
    panel:AddDropdown({
        label = "Value shown as",
        tooltip = "Which price drives the headline number and the per-hour rate. The label on screen changes with it, so the two are never confused.",
        options = {
            { text = "Vendor price", value = "VENDOR" },
            { text = "Market price (Auctionator)", value = "MARKET" },
        },
        width = 220,
        get = function() return CommanderSpoilsDB.ValueMode end,
        set = function(value) CommanderSpoilsDB.ValueMode = value end,
        isEnabled = Enabled,
    })
    panel:AddCheckboxPair({
        label = "Keep history between sessions",
        tooltip = "Rolls, hauls and per-zone totals survive logout. Turning this off keeps the current session only.",
        get = function() return CommanderSpoilsDB.TrackHistory end,
        set = function(value) CommanderSpoilsDB.TrackHistory = value end,
        isEnabled = Enabled,
    }, nil)
    panel:AddSliderPair({
        label = "Keep history for",
        tooltip = "Older entries are pruned at login and at logout.",
        min = 7, max = 180, step = 1, format = "%d days",
        get = function() return CommanderSpoilsDB.HistoryDays end,
        set = function(value) CommanderSpoilsDB.HistoryDays = value end,
        isEnabled = function() return Enabled() and CommanderSpoilsDB.TrackHistory end,
    }, {
        label = "Warn when bags drop below",
        tooltip = "The bag readout turns red under this many free slots.",
        min = 0, max = 20, step = 1, format = "%d slots",
        get = function() return CommanderSpoilsDB.JunkWarnSlots end,
        set = function(value) CommanderSpoilsDB.JunkWarnSlots = value end,
        isEnabled = Enabled,
    })
    panel:AddButtonRow({
        {
            label = "Session Report",
            width = 130,
            tooltip = "Print this session's haul (also: /cspoils report).",
            onClick = function()
                if CommanderSpoils_Report then CommanderSpoils_Report() end
            end,
        },
        {
            label = "Storage Used",
            width = 120,
            tooltip = "Print how many rows each history tier is holding (also: /cspoils size).",
            onClick = function()
                if CommanderSpoils_PrintSize then CommanderSpoils_PrintSize() end
            end,
        },
        {
            label = "Wipe History",
            width = 120,
            tooltip = "Clears the ledger. Settings are untouched (also: /cspoils wipe).",
            onClick = function()
                if CommanderSpoils_Wipe then CommanderSpoils_Wipe() end
            end,
        },
    })

    -- ---- Try it -----------------------------------------------------------
    panel:AddSection("Try It",
        "Each button drives the real code path with fake data, so you can see and place every band without waiting for a raid. Nothing is ever sent to the server.")
    panel:AddButtonRow({
        {
            label = "Test Pickup",
            width = 110,
            tooltip = "Raises a pickup notice for an epic (also: /cspoils test pickup).",
            onClick = function() if CommanderSpoils_Test then CommanderSpoils_Test("pickup") end end,
        },
        {
            label = "Test Roll",
            width = 100,
            tooltip = "Opens a fake 30-second Need/Greed/Pass roll you can actually click (also: /cspoils test roll).",
            onClick = function() if CommanderSpoils_Test then CommanderSpoils_Test("roll") end end,
        },
        {
            label = "Test Corpse",
            width = 110,
            tooltip = "Shows the corpse band with fake slots, including a bind-on-pickup row (also: /cspoils test corpse).",
            onClick = function() if CommanderSpoils_Test then CommanderSpoils_Test("corpse") end end,
        },
    })
    panel:AddButtonRow({
        {
            label = "Test Win",
            width = 100,
            tooltip = "Resolves the fake roll as a win, with the fanfare (also: /cspoils test win).",
            onClick = function() if CommanderSpoils_Test then CommanderSpoils_Test("win") end end,
        },
        {
            label = "Test Wave",
            width = 105,
            tooltip = "Six simultaneous rolls, so you can see dense mode, the aggregate chime and PASS ALL (also: /cspoils test wave).",
            onClick = function() if CommanderSpoils_Test then CommanderSpoils_Test("wave") end end,
        },
        {
            label = "Clear Tests",
            width = 110,
            tooltip = "Removes every fake roll and closes the fake corpse (also: /cspoils test clear).",
            onClick = function() if CommanderSpoils_Test then CommanderSpoils_Test("clear") end end,
        },
    })

    -- ---- Chrome LAST per suite convention. One frame, one block. ---------
    panel:AddSection("Frame")
    panel:AddCheckboxPair({
        label = "Follow the cursor at a corpse",
        tooltip = "Looting is a spatial act at a corpse, so while the browsing panes are closed the window jumps to the cursor and returns to its own place afterwards. It never moves while the panes are open.",
        get = function() return CommanderSpoilsDB.SalvageAnchor == "CURSOR" end,
        set = function(value) CommanderSpoilsDB.SalvageAnchor = value and "CURSOR" or "FIXED" end,
        isEnabled = Enabled,
    }, nil)
    Commander.UI.AddHudChromeOptions(panel, CommanderSpoilsDB, "Hud", {
        isEnabled = Enabled,
        defaultPoint = { point = "CENTER", x = 0, y = 0 },
        onChanged = function() Commander.Notify(COMMANDER_SPOILS_EVENTS.UPDATE) end,
    })

    panel:Finalize({ onDefaults = Reset })
    FinishScroll()
end

-- ===========================================================================
-- Watchdog: a player must never end up with Blizzard's loot UI dead and no
-- replacement. The frame file sets CommanderSpoils_Ready at the end of its
-- login handler; if it never got there, everything comes back.
-- ===========================================================================
-- It deliberately does NOT untick the switches: a transient failure should
-- not permanently disable a takeover the player asked for. Each session tries,
-- and each failed session hands the UI back.
local function Watchdog()
    if CommanderSpoils_Ready then return end
    Suppression.Block()
    local restored = Suppression.Undo()
    if #restored > 0 then
        print("|cffff5555Commander Spoils|r: the window failed to load, so Blizzard's loot interface has been handed back and will stay that way this session. Please report this; |cffffffff/cspoils restore|r clears the block.")
    else
        print("|cffff5555Commander Spoils|r: the window failed to load. Blizzard's loot interface is untouched.")
    end
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Spoils" then
        Migrate(CommanderSpoilsDB)
        Commander.UI.ApplyDefaults(CommanderSpoilsDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
        C_Timer.After(2, Watchdog)
    end
end
-- No PLAYER_LOGOUT restore: every suppression is a live function pointer, a
-- live event registration or a live chat filter, none of which survive the
-- session. There is nothing to hand back at logout, and pretending otherwise
-- would only invite a future edit that persists something.

frame:SetScript("OnEvent", OnEvent)

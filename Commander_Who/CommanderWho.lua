-- CommanderWho.lua — the host.
--
-- Owns the integration with Blizzard's Who tab (the per-row tick boxes and the
-- toolbar beside it), the one selection set both views read and write, and the
-- throttled send run. It draws no window of its own; CommanderWhoUI.lua does
-- that, and is optional -- everything here works with that file absent.
--
-- Two rules shaped this file.
--
-- 1. **Row widgets are a view, never a model.** WhoFrameButton1..N are a fixed
--    pool of seventeen buttons scrolled over an arbitrarily long result set.
--    Anything stored on a button belongs to whichever player happens to be in
--    that slot right now, which is why the 2.1 build's tick marks appeared to
--    jump around while scrolling: they never moved at all, the players under
--    them did. Every paint rebinds every box from the selection set.
--
-- 2. **Nothing we do to Blizzard's frames is one-way.** The name font strings
--    we shift to make room remember where they were, and turning the feature
--    off puts them back. The 2.1 build re-anchored them permanently, so the
--    only way out was a reload.

local E = CommanderWhoEngine

CommanderWho = {}
local API = CommanderWho

-- Always read the live saved-variables table: SavedVariables replace the
-- global after the files run, so a local captured at load time is a different
-- table from the one the settings page writes to.
local function DB()
    return _G.CommanderWhoDB or {}
end

local EV = COMMANDER_WHO_EVENTS

local selection = E.NewSelection()
local records = {}
local recordByKey = {}
local rowEntries = {}
local rangeAnchor          -- last index clicked, for shift-click ranges
local toolbar
local run, ticker
local initialized = false
-- What GetNumWhoResults said the last time records were built. Compared
-- against, rather than #records, because BuildRecords drops duplicate keys and
-- a permanent mismatch would make every paint rebuild.
local builtFrom = -1
-- Bumped on every rebuild. Views compare it to know that row indices they were
-- holding (a shift-click anchor, a per-row send status) no longer mean
-- anything, without having to diff the list themselves.
local generation = 0

local CHECK_SIZE = 13
local NAME_SHIFT = 15

-- ---------------------------------------------------------------------------
-- Result set
-- ---------------------------------------------------------------------------

local function NumResults()
    if C_FriendList and C_FriendList.GetNumWhoResults then
        return C_FriendList.GetNumWhoResults() or 0
    end
    return 0
end

local function GetWhoInfo(index)
    if C_FriendList and C_FriendList.GetWhoInfo then
        return C_FriendList.GetWhoInfo(index)
    end
    return nil
end

local function SelfKey()
    local name = UnitName and UnitName("player")
    return name and E.Key(name) or nil
end

-- Rebuilds the record list and reconciles the selection against it. Called on
-- WHO_LIST_UPDATE and whenever a paint notices the result count has moved
-- under us, so a dropped event costs a stale paint rather than a wrong send.
local function RebuildRecords()
    generation = generation + 1
    builtFrom = NumResults()
    records = E.BuildRecords(builtFrom, GetWhoInfo)
    recordByKey = {}
    for i = 1, #records do
        recordByKey[records[i].key] = records[i]
    end

    local valid = E.KeySet(records)
    -- Ticks are kept for anyone still in the list -- re-running the same
    -- search does not cost you the set you had built up -- and dropped for
    -- everyone who is gone, so the count never promises a send it cannot make.
    selection:Prune(valid)
    if DB().SelectNewResults then
        selection:SetRecords(records, true)
    end
    rangeAnchor = nil
    return records
end

-- ---------------------------------------------------------------------------
-- Who row tick boxes
-- ---------------------------------------------------------------------------

local function CollectRows()
    if #rowEntries > 0 then return rowEntries end
    for i = 1, 64 do
        local button = _G["WhoFrameButton" .. i]
        if not button then break end
        local name = button.GetName and button:GetName()
        rowEntries[i] = {
            button = button,
            nameText = name and _G[name .. "Name"] or nil,
        }
    end
    return rowEntries
end

-- Reversible. The original anchor and width are captured on the first shift
-- and restored verbatim when the option is turned off.
local function ShiftName(entry, on)
    local nameText = entry.nameText
    if not nameText then return end
    if on then
        if entry.shifted then return end
        local point, relativeTo, relativePoint, x, y = nameText:GetPoint(1)
        if not point then return end
        entry.origin = { point, relativeTo or entry.button, relativePoint, x or 0, y or 0 }
        -- Only narrow a font string that actually carries a column width. A
        -- font string with no width set reports its own text width, and
        -- pinning that would clip every name from here on.
        local width = nameText.GetWidth and nameText:GetWidth() or 0
        local textWidth = nameText.GetStringWidth and nameText:GetStringWidth() or width
        if width > textWidth + 0.5 and width > NAME_SHIFT + 24 then
            entry.origWidth = width
            nameText:SetWidth(width - NAME_SHIFT)
        end
        local o = entry.origin
        nameText:ClearAllPoints()
        nameText:SetPoint(o[1], o[2], o[3], o[4] + NAME_SHIFT, o[5])
        entry.shifted = true
    else
        if not entry.shifted then return end
        local o = entry.origin
        nameText:ClearAllPoints()
        nameText:SetPoint(o[1], o[2], o[3], o[4], o[5])
        if entry.origWidth then
            nameText:SetWidth(entry.origWidth)
            entry.origWidth = nil
        end
        entry.shifted = false
    end
end

local RefreshRows   -- forward: the click handler repaints

local function OnRowCheckClick(check)
    local index = check.recordIndex
    local record = index and records[index]
    if not record then
        check:SetChecked(false)
        return
    end
    local wanted = check:GetChecked() and true or false

    if IsShiftKeyDown and IsShiftKeyDown() and rangeAnchor and records[rangeAnchor] then
        -- Range fill takes the state of the box that was just clicked and
        -- applies it to everything between here and the anchor.
        selection:SetMany(E.RangeKeys(records, rangeAnchor, index), wanted)
    else
        selection:Set(record.key, wanted)
    end
    rangeAnchor = index

    Commander.Notify(EV.SELECTION)
end

local function EnsureRowCheck(entry)
    if entry.check then return entry.check end
    local check = CreateFrame("CheckButton", nil, entry.button, "UICheckButtonTemplate")
    check:SetSize(CHECK_SIZE, CHECK_SIZE)
    check:SetPoint("LEFT", entry.button, "LEFT", 1, 0)
    check:SetFrameLevel((entry.button:GetFrameLevel() or 1) + 2)
    check:SetScript("OnClick", function(self) OnRowCheckClick(self) end)
    check:SetScript("OnEnter", function(self)
        if not self.recordIndex then return end
        local record = records[self.recordIndex]
        if not record then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(record.fullName, E.ClassColor(record.classToken))
        if record.guild ~= "" then
            GameTooltip:AddLine("<" .. record.guild .. ">", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Tick to include in the next mass whisper.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift-click selects everything back to the last box you clicked.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    entry.check = check
    return check
end

function RefreshRows()
    if not WhoFrame or not WhoListScrollFrame then return end
    local show = DB().ShowRowCheckboxes and true or false
    local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(WhoListScrollFrame)) or 0

    for i, entry in ipairs(CollectRows()) do
        if not show then
            if entry.check then
                entry.check.recordIndex = nil
                entry.check:Hide()
            end
            ShiftName(entry, false)
        else
            local index = offset + i
            local record = records[index]
            local check = EnsureRowCheck(entry)
            ShiftName(entry, true)
            if record then
                check.recordIndex = index
                check:SetChecked(selection:Get(record.key))
                check:Show()
            else
                check.recordIndex = nil
                check:Hide()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Toolbar
-- ---------------------------------------------------------------------------

local function BuildToolbar()
    if toolbar then return toolbar end
    if not WhoFrame then return nil end

    local bar = CreateFrame("Frame", "CommanderWhoToolbar", WhoFrame)
    toolbar = bar
    bar:SetSize(112, 146)
    -- Hung off the outside edge of the friends window rather than squeezed
    -- into the Who tab: there is no free space inside it that does not belong
    -- to a column header or a Blizzard button (D4).
    local anchor = _G.FriendsFrame or WhoFrame
    bar:SetPoint("TOPLEFT", anchor, "TOPRIGHT", -4, -56)
    bar:SetFrameLevel((WhoFrame:GetFrameLevel() or 1) + 5)
    if Commander.UI.ApplyStyleBackdrop then
        Commander.UI.ApplyStyleBackdrop(bar, "DARK")
    end

    local heading = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heading:SetPoint("TOP", bar, "TOP", 0, -8)
    heading:SetText("Selected")
    heading:SetTextColor(0.62, 0.68, 0.72)

    local count = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    count:SetPoint("TOP", heading, "BOTTOM", 0, -2)
    bar.count = count

    local function MakeButton(label, width, tooltip, onClick)
        local button = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        button:SetSize(width, 20)
        button:SetText(label)
        button:SetScript("OnClick", onClick)
        Commander.UI.AttachTooltip(button, label, tooltip)
        return button
    end

    local all = MakeButton("All", 48, "Tick every player in the current search results.", function() API.SelectAll() end)
    all:SetPoint("TOPLEFT", bar, "TOPLEFT", 6, -46)

    local none = MakeButton("None", 48, "Clear every tick.", function() API.SelectNone() end)
    none:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -6, -46)

    local invert = MakeButton("Invert", 100, "Tick everything that is not ticked, and untick everything that is.", function() API.SelectInvert() end)
    invert:SetPoint("TOPLEFT", all, "BOTTOMLEFT", 0, -4)

    local whisper = MakeButton("Mass Whisper", 100,
        "Open the mass whisper window for the players you have ticked.",
        function() API.OpenWhisperWindow() end)
    whisper:SetPoint("TOPLEFT", invert, "BOTTOMLEFT", 0, -6)
    bar.whisperButton = whisper

    local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", whisper, "BOTTOM", 0, -4)
    hint:SetText("/cwho")

    return bar
end

local function RefreshToolbar()
    local bar = toolbar
    if not bar then return end
    local show = DB().ShowToolbar and true or false
    bar:SetShown(show)
    if not show then return end

    local selected = selection:CountIn(records)
    local total = #records
    bar.count:SetText(string.format("%d / %d", selected, total))
    if selected > 0 then
        bar.count:SetTextColor(0.40, 0.85, 0.45)
    else
        bar.count:SetTextColor(0.62, 0.68, 0.72)
    end
    bar.whisperButton:SetEnabled(total > 0)
end

-- ---------------------------------------------------------------------------
-- Public selection API
-- ---------------------------------------------------------------------------

function API.Records()
    return records
end

function API.Generation()
    return generation
end

function API.RecordByKey(key)
    return recordByKey[key]
end

function API.Selection()
    return selection
end

function API.IsSelected(key)
    return selection:Get(key)
end

function API.SetSelected(key, on)
    if selection:Set(key, on) then
        Commander.Notify(EV.SELECTION)
    end
end

function API.ToggleSelected(key)
    selection:Toggle(key)
    Commander.Notify(EV.SELECTION)
end

function API.SelectAll()
    selection:SetRecords(records, true)
    Commander.Notify(EV.SELECTION)
end

function API.SelectNone()
    selection:SetRecords(records, false)
    Commander.Notify(EV.SELECTION)
end

function API.SelectInvert()
    selection:InvertRecords(records)
    Commander.Notify(EV.SELECTION)
end

function API.SelectedCount()
    return selection:CountIn(records)
end

-- ---------------------------------------------------------------------------
-- The send run
-- ---------------------------------------------------------------------------

function API.BuildPlan()
    return E.PlanWhispers(records, selection, {
        maxTargets = DB().MaxWhisperCount,
        excludeKey = SelfKey(),
    })
end

function API.IsRunning()
    return run ~= nil and run:IsActive()
end

function API.CurrentRun()
    return run
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Step()
    if not run then
        StopTicker()
        return
    end
    local target = run:Next()
    if not target then
        StopTicker()
        Commander.Notify(EV.RUN, run, nil)
        return
    end
    SendChatMessage(run.message, "WHISPER", nil, target.fullName)
    -- Finish on the last send rather than on the tick after it. The 2.1 build
    -- relied on a ticker iteration that its own iteration limit had already
    -- cancelled, so a completed run never said so.
    if run.sent >= run.total then
        run.done = true
        StopTicker()
    end
    Commander.Notify(EV.RUN, run, target)
end

function API.StopRun()
    if not run or not run:IsActive() then return false end
    run:Cancel()
    StopTicker()
    Commander.Notify(EV.RUN, run, nil)
    return true
end

local function BeginRun(plan, message)
    run = E.NewRun(plan, message)
    Commander.Notify(EV.RUN, run, nil)
    -- The first whisper goes out immediately; the ticker paces the rest.
    Step()
    if run:IsActive() then
        local delay = tonumber(DB().WhisperDelay) or 1
        if delay < 0.3 then delay = 0.3 end
        ticker = C_Timer.NewTicker(delay, Step)
    end
end

-- Add our key to Blizzard's table; never ASSIGN the global. `StaticPopupDialogs =
-- StaticPopupDialogs or {}` looks like a harmless guard, but assigning a global
-- from addon code taints that global variable for the rest of the session, and
-- every piece of Blizzard code that later reads it inherits the taint.
--
-- What that cost: every Escape-menu button runs the same three-line closure --
-- PlaySound, HideUIPanel(GameMenuFrame), callback() (Blizzard_GameMenu/Shared/
-- GameMenuFrame.lua). HideUIPanel drags in the panel-position pass, which reads
-- widely across FrameXML globals; once it touched our tainted one the execution
-- was tainted, and Log Out / Exit Game -- protected functions reached through
-- that local `callback` -- died with ADDON_ACTION_FORBIDDEN blamed on
-- Commander_Who. The player could not leave the game without a reload.
-- Commander_Dossier was named in the same report for the same line and carries
-- the same note.
--
-- Writing one new KEY into the table taints only that key, which nothing but
-- our own popup ever reads. FrameXML always defines the table; the guard is for
-- the offline harness.
if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_WHO_CONFIRM_SEND"] = {
        text = "%s",
        button1 = "Send",
        button2 = CANCEL or "Cancel",
        OnAccept = function(self, data)
            if data then BeginRun(data.plan, data.message) end
        end,
        -- Declining leaves the window showing "waiting for confirmation" unless
        -- something tells it to repaint.
        OnCancel = function()
            Commander.Notify(EV.SELECTION)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

-- Returns false plus a reason the caller can show; never prints on its own, so
-- the window can put the reason where the user is already looking.
function API.StartRun(message)
    if API.IsRunning() then
        return false, "A mass whisper is already running."
    end
    local text, err = E.ValidateMessage(message)
    if not text then return false, err end

    -- Rebuild first: the plan must be made from what /who says right now, not
    -- from a result set that went stale while the message was being typed.
    if builtFrom ~= NumResults() then RebuildRecords() end

    local plan = API.BuildPlan()
    if not plan.ok then return false, plan.reason end

    if DB().ConfirmBeforeSending then
        local seconds = E.EstimateSeconds(plan.count, tonumber(DB().WhisperDelay) or 1)
        local prompt = string.format("%s\n\nThis takes about %d %s and cannot be undone.",
            E.DescribePlan(plan), math.max(seconds, 1),
            math.max(seconds, 1) == 1 and "second" or "seconds")
        StaticPopup_Show("COMMANDER_WHO_CONFIRM_SEND", prompt, nil,
            { plan = plan, message = text })
        return true, "Waiting for confirmation."
    end

    BeginRun(plan, text)
    return true, E.DescribePlan(plan)
end

-- ---------------------------------------------------------------------------
-- Window handoff
-- ---------------------------------------------------------------------------

function API.OpenWhisperWindow()
    local ui = _G.CommanderWhoUI
    if ui and ui.Toggle then
        ui.Toggle()
    else
        print("Commander Who: the mass whisper window failed to load.")
    end
end

-- ---------------------------------------------------------------------------
-- Paint + wiring
-- ---------------------------------------------------------------------------

function API.Refresh()
    if not initialized then return end
    -- A paint that finds the result count has moved rebuilds rather than
    -- drawing ticks against indices that no longer mean anything.
    if builtFrom ~= NumResults() then RebuildRecords() end
    RefreshRows()
    RefreshToolbar()
end

local function OnSettingsChanged()
    if not initialized then return end
    RefreshRows()
    RefreshToolbar()
end

local function OnSelectionChanged()
    if not initialized then return end
    RefreshRows()
    RefreshToolbar()
end

local function HookWhoFrame()
    -- Primary: Blizzard repaints the list through this on scroll, on sort and
    -- on every result update, so one hook covers all three. Synchronous on
    -- purpose -- the 2.1 build deferred the repaint a frame with
    -- C_Timer.After(0), which is exactly long enough to show the previous
    -- player's tick under the new one while scrolling.
    if type(_G.WhoList_Update) == "function" then
        hooksecurefunc("WhoList_Update", function()
            RefreshRows()
            RefreshToolbar()
        end)
    end
    -- Belt: a scroll that somehow does not reach WhoList_Update still repaints.
    if WhoListScrollFrame and WhoListScrollFrame.HookScript then
        WhoListScrollFrame:HookScript("OnVerticalScroll", function()
            RefreshRows()
        end)
    end
    -- Braces: opening the tab always paints from current truth.
    if WhoFrame.HookScript then
        WhoFrame:HookScript("OnShow", function() API.Refresh() end)
    end
end

local function BuildClassNameMap()
    local map = {}
    for _, source in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
        if type(source) == "table" then
            for token, localised in pairs(source) do
                map[localised] = token
            end
        end
    end
    E.SetClassNameMap(map)
end

local attempts = 0

local function Initialize()
    if initialized then return end
    if not WhoFrame or not WhoListScrollFrame then
        attempts = attempts + 1
        if attempts <= 20 then
            C_Timer.After(0.5, Initialize)
        else
            print("Commander Who: the Who window never appeared; the module is inactive this session.")
        end
        return
    end

    initialized = true
    BuildClassNameMap()
    CollectRows()
    BuildToolbar()
    HookWhoFrame()

    Commander.AddListener(EV.UPDATE, OnSettingsChanged)
    Commander.AddListener(EV.SELECTION, OnSelectionChanged)

    RebuildRecords()
    API.Refresh()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("WHO_LIST_UPDATE")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        Initialize()
    elseif event == "WHO_LIST_UPDATE" then
        if not initialized then return end
        RebuildRecords()
        -- One notify: both views repaint off the SELECTION listener, so the
        -- window stays in step with the Who tab without either knowing about
        -- the other.
        Commander.Notify(EV.SELECTION)
    end
end)

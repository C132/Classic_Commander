-- CommanderWhoUI.lua — the mass whisper window.
--
-- A second view onto the *same* selection set the Who tab draws. It owns no
-- selection state of its own: every tick box here reads CommanderWho's
-- selection and writes back through its API, so ticking a row in this window
-- moves the tick on the Who row behind it and vice versa. That is the whole
-- point -- the 2.1 build kept a private list here that it re-ticked from
-- scratch on every open, which is why the mass whisper ignored what you had
-- selected in the Who tab and messaged everybody.
--
-- Loads last and is optional: the host prints a soft failure and keeps the Who
-- tab working if this file is missing.

CommanderWhoUI = {}
local UIMod = CommanderWhoUI

local E = CommanderWhoEngine
local EV = COMMANDER_WHO_EVENTS
local CHROME = COMMANDER_WHO_CHROME

local function DB()
    return _G.CommanderWhoDB or {}
end

local function Host()
    return _G.CommanderWho
end

local ROW_HEIGHT = 18
local ROW_COUNT = 14
local ROW_WIDTH = 344
local FRAME_WIDTH = 400
local FRAME_HEIGHT = 340

local frame, scrollFrame, rows, header, progress, messageBox, sendButton
local selectAllButton, selectNoneButton, emptyText
local rangeAnchor
-- Per-key send outcome for the current run, so a row can say "sent" without
-- the run having to know anything about widgets.
local rowStatus = {}
-- The host's record generation these two were computed against. A new /who
-- invalidates both: the anchor is an index into an order that no longer
-- exists, and the statuses describe a run against a different result set.
local seenGeneration = -1
-- A finished run's summary stays on screen until the selection moves, at which
-- point what Send would do next is the more useful thing to be reading.
local summaryStale = false

local COLOR_OK   = { 0.40, 0.85, 0.45 }
local COLOR_WARN = { 1.00, 0.82, 0.20 }
local COLOR_BAD  = { 0.90, 0.24, 0.20 }
local COLOR_DIM  = { 0.55, 0.60, 0.64 }

local Repaint   -- forward

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function ToggleRecord(record, index, wanted)
    local host = Host()
    if not host or not record then return end
    if IsShiftKeyDown and IsShiftKeyDown() and rangeAnchor then
        local records = host.Records()
        local keys = E.RangeKeys(records, rangeAnchor, index)
        for i = 1, #keys do
            host.Selection():Set(keys[i], wanted)
        end
        Commander.Notify(EV.SELECTION)
    else
        host.SetSelected(record.key, wanted)
    end
    rangeAnchor = index
end

local function BuildRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(13, 13)
    check:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.check = check

    local function Field(width, justify, font)
        local text = row:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
        text:SetWidth(width)
        text:SetJustifyH(justify or "LEFT")
        text:SetHeight(ROW_HEIGHT)
        return text
    end

    row.name = Field(104)
    row.name:SetPoint("LEFT", check, "RIGHT", 4, 0)

    row.level = Field(22, "CENTER")
    row.level:SetPoint("LEFT", row.name, "RIGHT", 2, 0)

    row.class = Field(64)
    row.class:SetPoint("LEFT", row.level, "RIGHT", 2, 0)

    row.status = Field(52, "RIGHT")
    row.status:SetPoint("RIGHT", row, "RIGHT", -4, 0)

    row.zone = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.zone:SetJustifyH("LEFT")
    row.zone:SetHeight(ROW_HEIGHT)
    row.zone:SetPoint("LEFT", row.class, "RIGHT", 2, 0)
    row.zone:SetPoint("RIGHT", row.status, "LEFT", -4, 0)

    local function Clicked(wanted)
        ToggleRecord(row.record, row.recordIndex, wanted)
    end

    check:SetScript("OnClick", function(self) Clicked(self:GetChecked() and true or false) end)
    row:SetScript("OnClick", function()
        local wanted = not check:GetChecked()
        check:SetChecked(wanted)
        Clicked(wanted)
    end)
    row:SetScript("OnEnter", function(self)
        if not self.record then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.record.fullName, E.ClassColor(self.record.classToken))
        if self.record.guild ~= "" then
            GameTooltip:AddLine("<" .. self.record.guild .. ">", 0.7, 0.7, 0.7)
        end
        if self.record.race ~= "" then
            GameTooltip:AddLine(self.record.race, 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Shift-click selects everything back to the last row you clicked.", 0.55, 0.6, 0.64, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function ApplyChrome()
    if not frame then return end
    Commander.UI.ApplyHudChrome(frame, DB(), CHROME, {
        title = "Mass Whisper",
        defaultPoint = { point = "CENTER", x = 0, y = 0 },
    })
    -- The shared window chrome treats its X as "closed for the session", which
    -- is right for a persistent HUD and wrong for a window you open on demand:
    -- it would take a trip to Reset Position to get this one back. Replace the
    -- handler once with a plain hide.
    local win = frame._hudWindow
    if win and win.CloseButton and not frame._closeRewired then
        frame._closeRewired = true
        win.CloseButton:SetScript("OnClick", function() frame:Hide() end)
    end
end

local function SetProgress(text, color)
    if not progress then return end
    progress:SetText(text or "")
    local c = color or COLOR_DIM
    progress:SetTextColor(c[1], c[2], c[3])
end

local function OnSend()
    local host = Host()
    if not host then return end
    if host.IsRunning() then
        host.StopRun()
        return
    end
    local ok, message = host.StartRun(messageBox:GetText())
    if not ok then
        SetProgress(message, COLOR_BAD)
    else
        SetProgress(message, COLOR_DIM)
    end
end

local function Build()
    if frame then return frame end

    frame = CreateFrame("Frame", "CommanderWhoWhisperFrame", UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:Hide()
    -- Escape closes, like every other on-demand window in the game.
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "CommanderWhoWhisperFrame")
    end

    header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -6)
    header:SetJustifyH("LEFT")

    selectNoneButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectNoneButton:SetSize(46, 18)
    selectNoneButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -4)
    selectNoneButton:SetText("None")
    selectNoneButton:SetScript("OnClick", function()
        local host = Host(); if host then host.SelectNone() end
    end)
    Commander.UI.AttachTooltip(selectNoneButton, "Select None", "Clear every tick, here and on the Who tab.")

    selectAllButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectAllButton:SetSize(46, 18)
    selectAllButton:SetPoint("RIGHT", selectNoneButton, "LEFT", -4, 0)
    selectAllButton:SetText("All")
    selectAllButton:SetScript("OnClick", function()
        local host = Host(); if host then host.SelectAll() end
    end)
    Commander.UI.AttachTooltip(selectAllButton, "Select All", "Tick every player in the current search results.")

    -- The list is a faux scroll frame -- the same widget Blizzard's own Who
    -- list uses -- so a long result set costs fourteen row widgets, not one
    -- per player, and the scroll maths is the client's rather than ours. The
    -- 2.1 build sized its scroll child from GetBottom(), a screen coordinate,
    -- which produced a nonsense height and a list that would not scroll.
    scrollFrame = CreateFrame("ScrollFrame", "CommanderWhoWhisperScroll", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -26)
    scrollFrame:SetSize(ROW_WIDTH + 4, ROW_HEIGHT * ROW_COUNT)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, Repaint)
    end)

    rows = {}
    for i = 1, ROW_COUNT do
        local row = BuildRow(frame, i)
        if i == 1 then
            row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0)
        end
        rows[i] = row
    end

    emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableLarge")
    emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyText:SetText("No search results.\nRun a /who first.")
    emptyText:SetJustifyH("CENTER")
    emptyText:Hide()

    progress = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    progress:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 4, -6)
    progress:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    progress:SetJustifyH("LEFT")

    sendButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendButton:SetSize(92, 22)
    sendButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    sendButton:SetText("Send")
    sendButton:SetScript("OnClick", OnSend)

    messageBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    messageBox:SetHeight(22)
    messageBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 8)
    messageBox:SetPoint("RIGHT", sendButton, "LEFT", -10, 0)
    messageBox:SetAutoFocus(false)
    messageBox:SetMaxLetters(E.MAX_WHISPER_LENGTH)
    messageBox:SetScript("OnEnterPressed", OnSend)
    messageBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    ApplyChrome()
    return frame
end

-- ---------------------------------------------------------------------------
-- Paint
-- ---------------------------------------------------------------------------

function Repaint()
    if not frame or not frame:IsShown() then return end
    local host = Host()
    local records = host and host.Records() or {}
    local selection = host and host.Selection()
    local total = #records

    FauxScrollFrame_Update(scrollFrame, total, ROW_COUNT, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    for i = 1, ROW_COUNT do
        local row = rows[i]
        local index = offset + i
        local record = records[index]
        if record then
            row.record = record
            row.recordIndex = index
            row.check:SetChecked(selection and selection:Get(record.key))
            local r, g, b = E.ClassColor(record.classToken)
            row.name:SetText(record.name or record.fullName)
            row.name:SetTextColor(r, g, b)
            row.level:SetText(record.level > 0 and tostring(record.level) or "")
            row.class:SetText(record.classText)
            row.zone:SetText(record.zone)

            local status = rowStatus[record.key]
            if status == "sent" then
                row.status:SetText("sent")
                row.status:SetTextColor(COLOR_OK[1], COLOR_OK[2], COLOR_OK[3])
            elseif status == "queued" then
                row.status:SetText("queued")
                row.status:SetTextColor(COLOR_WARN[1], COLOR_WARN[2], COLOR_WARN[3])
            elseif status == "capped" then
                row.status:SetText("over cap")
                row.status:SetTextColor(COLOR_BAD[1], COLOR_BAD[2], COLOR_BAD[3])
            else
                row.status:SetText("")
            end
            row:Show()
        else
            row.record, row.recordIndex = nil, nil
            row:Hide()
        end
    end

    emptyText:SetShown(total == 0)

    local selected = (host and host.SelectedCount()) or 0
    header:SetText(string.format("|cffffd100%d|r of %d selected", selected, total))

    local running = host and host.IsRunning()
    sendButton:SetText(running and "Stop" or "Send")
    sendButton:SetEnabled(running or (total > 0))
    selectAllButton:SetEnabled(not running and total > 0)
    selectNoneButton:SetEnabled(not running and selected > 0)
    -- EditBox predates SetEnabled; Enable/Disable is the pair it actually has.
    if running then messageBox:Disable() else messageBox:Enable() end

    if not running and host then
        -- Idle: say what Send would do right now, so the cap and the
        -- skipped-yourself rule are visible before the click, not after.
        local currentRun = host.CurrentRun()
        if currentRun and not summaryStale then
            SetProgress(currentRun:Progress(),
                currentRun.cancelled and COLOR_WARN or COLOR_OK)
        elseif selected > 0 then
            SetProgress(E.DescribePlan(host.BuildPlan()), COLOR_DIM)
        else
            SetProgress("", COLOR_DIM)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Run feedback
-- ---------------------------------------------------------------------------

local function OnRun(currentRun, target)
    if not currentRun then return end
    summaryStale = false
    if currentRun.sent == 0 and not currentRun.cancelled and not currentRun.done then
        -- Run just started: mark everybody it intends to message.
        rowStatus = {}
        for i = 1, #currentRun.targets do
            rowStatus[currentRun.targets[i].key] = "queued"
        end
        local host = Host()
        if host then
            -- Anything selected that the plan refused is flagged so the reason
            -- is visible on the row rather than only in the summary line.
            local records = host.Records()
            local selection = host.Selection()
            for i = 1, #records do
                local key = records[i].key
                if selection:Get(key) and not rowStatus[key] then
                    rowStatus[key] = "capped"
                end
            end
        end
    end
    if target then
        rowStatus[target.key] = "sent"
    end
    if not frame or not frame:IsShown() then return end
    SetProgress(currentRun:Progress(),
        currentRun.cancelled and COLOR_WARN or (currentRun.done and COLOR_OK or COLOR_DIM))
    Repaint()
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function UIMod.Open()
    Build()
    ApplyChrome()
    frame:Show()
    Repaint()
    messageBox:SetFocus()
end

function UIMod.Close()
    if frame then frame:Hide() end
end

function UIMod.Toggle()
    Build()
    if frame:IsShown() then
        UIMod.Close()
    else
        UIMod.Open()
    end
end

function UIMod.Frame()
    return frame
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    Build()
    Commander.AddListener(EV.UPDATE, function()
        ApplyChrome()
        Repaint()
    end)
    Commander.AddListener(EV.SELECTION, function()
        local host = Host()
        local gen = host and host.Generation() or 0
        if gen ~= seenGeneration then
            seenGeneration = gen
            rangeAnchor = nil
            rowStatus = {}
        end
        summaryStale = true
        Repaint()
    end)
    Commander.AddListener(EV.RUN, OnRun)
end)

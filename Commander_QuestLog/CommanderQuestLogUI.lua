-- Commander Quest Log: the window.
--
-- Double wide, split down the middle. The left half is the navigator: every
-- quest in the log under its zone heading, searchable, filterable, sortable,
-- with its level, its state and how far through it you are. The right half is
-- the briefing: objectives, description, rewards, and the four things you can
-- actually do to a quest — track it, share it, announce it, drop it.
--
-- Chrome is drawn, not borrowed. The selection bar, the collapse chevrons,
-- the progress bars and the reward quality rings are all quads cut from
-- WHITE8X8 and tinted from the Console palette, for the reasons Meters and
-- Bags document: ARIALN renders shape glyphs as missing-glyph boxes, icon
-- FILES move across client patches, and IconBorder writes do not stick.
--
-- The one Blizzard region deliberately kept is the sheet behind the window --
-- the dialog border and header plate that are the quest log's own and are what
-- make this read as a quest log rather than as a generic browser. The sheet
-- comes in two materials: dark stone (the default, and the rest of the suite's
-- weight) and the parchment of the stock log.
--
-- The window has two tabs. The Log is this file. The Zones tab -- a zone's
-- every quest from Questie, with its completion -- is CommanderQuestLogZones.lua,
-- which builds its own widgets in the same frame and draws with this file's
-- ink through Q._kit. This file only dispatches: Q.Refresh scans the log in
-- either tab (the Zones tab and the Questie adapter both read the scan), then
-- hands the frame to whichever tab is up and puts the other one's widgets
-- away. The Log's code path is otherwise the one it always was, which is the
-- point of keeping the Zones tab out of it.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

BINDING_HEADER_COMMANDERQUESTLOG = "Commander Quest Log"
BINDING_NAME_COMMANDERQUESTLOG_TOGGLE = "Open the Quest Log"
BINDING_NAME_COMMANDERQUESTLOG_SEARCH = "Search the Quest Log"

local QUAD = "Interface\\Buttons\\WHITE8X8"
local PAD = 10
local NAV_W = 296
local TOOLBAR_H = 24
local ACTIONS_H = 26
local ROW_H = 20
local QUEST_ROW_H = 24
local QUEST_ROW_H_BAR = 30
local REWARD_SIZE = 34
local FRAME_W, FRAME_H = 792, 528

local frame, navScroll, navChild, detailScroll, detailChild
local navRows, rewardButtons, detailBlocks = {}, {}, {}
local entries, rows, numQuests = {}, {}, 0
local selectedKey, selectedEntry, selectedDetail
-- A quest asked for from outside (Open in Log, a quest link): its row is
-- brought into view after the next layout, at selectedTop in the navigator
local revealSelection, selectedTop, selectedHeight = false, nil, nil
-- Where the briefed quest is handed in, when Questie knows (nil without it)
local selectedFinisher
local searchText = ""
local pendingRefresh = false
local ApplyFraming

local function DB()
    return CommanderQuestLogDB or {}
end

local function Enabled()
    return DB().EnableQuestLog ~= false
end

-- ---------------------------------------------------------------------------
-- Tint
--
-- The TopBar pattern: read Commander_Console's palette live and soft-fail to
-- steel when Console is not installed. Nothing here hard-depends on it.
-- ---------------------------------------------------------------------------

local function Accent()
    local key = (CommanderConsoleDB and CommanderConsoleDB.ConsoleColor) or "STEEL"
    if key == "CLASS" then
        local _, class = UnitClass("player")
        local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key then
            return color.r or 1, color.g or 1, color.b or 1
        end
    end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Ink
--
-- This window has two backgrounds and they are opposites: the parchment is
-- pale paper, the dark panel is near-black. Every neutral in this file used to
-- be a light literal, which is invisible on paper -- and that went unnoticed
-- for as long as the parchment did not actually render. It did not: the
-- template dressing was being hidden by four guessed parentKeys, three of
-- which do not exist on this client, so the template's dark Bg sat on top of
-- the parchment and the light text read fine against it. With the dressing
-- fixed the paper is finally visible, and the ink has to follow it.
--
-- Only the NEUTRALS live here. Difficulty and quality colours are semantic --
-- they mean the same thing on any background and are deliberately untouched.
-- ---------------------------------------------------------------------------

local INK = {
    PARCHMENT = {
        primary   = { 0.16, 0.10, 0.04 },
        secondary = { 0.34, 0.26, 0.16 },
        faint     = { 0.48, 0.40, 0.30 },
        strong    = { 0.36, 0.16, 0.02 },
        title     = { 0.30, 0.13, 0.02 },
        countDone = "6b5a40", countAll = "1a1005",
    },
    DARK = {
        primary   = { 0.86, 0.86, 0.90 },
        secondary = { 0.72, 0.72, 0.76 },
        faint     = { 0.66, 0.66, 0.70 },
        strong    = { 1.00, 0.95, 0.80 },
        title     = { 1.00, 0.82, 0.30 },
        countDone = "808080", countAll = "ffffff",
    },
}

-- Only the parchment is pale. Stone, Window and Dark are all dark grounds
-- and share the one light ink.
local function InkSet()
    if (DB().FrameStyle or "STONE") == "PARCHMENT" then return INK.PARCHMENT end
    return INK.DARK
end

local function OnPaper()
    return (DB().FrameStyle or "STONE") == "PARCHMENT"
end

-- Paper
--
-- The neutrals above are the only colours that were ever picked for the
-- paper. Everything else -- difficulty, item quality, the objective lines,
-- "ready", the daily D, the money line, the console accent -- is a colour
-- picked against a DARK ui, which means it is bright: quest-level yellow is
-- (1,1,0), a green item is (0.12,1,0), an objective still to do is (0.92,
-- 0.86,0.6). On a near-black panel those glow; on a tan sheet they are within
-- a shade of the paper and the log is unreadable, which was the in-game
-- report. Every colour written on the paper goes through here: it keeps the
-- hue (yellow stays a yellow, a green item stays green) and scales it down
-- until its luminance sits at a level that reads as ink. Colours already that
-- dark pass untouched, and so does everything when the window is not paper.
local PAPER_LUM = 0.34

local function Paper(r, g, b)
    if not OnPaper() then return r, g, b end
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum <= PAPER_LUM then return r, g, b end
    local k = PAPER_LUM / lum
    return r * k, g * k, b * k
end

-- The same for an inline |cff colour, since the row states and the count
-- are written as markup
local function PaperHex(hex)
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    r, g, b = Paper(r, g, b)
    return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- The console accent is picked against a dark UI, and the default one is
-- STEEL -- pure white. As TEXT on parchment it IS the paper, and so is a
-- white fill: a selection band, a rule, an underline or a chevron in white
-- over cream is no mark at all. So anything drawn ON the sheet takes the
-- accent put on the paper -- text and fills alike. Off paper this is Accent()
-- itself, and a coloured accent keeps its hue on paper. Accent() is left for
-- what never sits on the sheet (the drawer on the map); the hairline under
-- the toolbar is on the sheet and takes this one.
local function InkAccent()
    return Paper(Accent())
end

local function Ink(shade)
    local color = InkSet()[shade] or InkSet().primary
    return color[1], color[2], color[3]
end

local QUALITY = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
    [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

local function QualityColor(quality)
    local color = QUALITY[quality or 1] or QUALITY[1]
    return Paper(color[1], color[2], color[3])
end

-- ---------------------------------------------------------------------------
-- Small drawing helpers
-- ---------------------------------------------------------------------------

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

-- A chevron drawn from two rotated bars: pointing right when shut, down when
-- open. Drawn rather than a texture file or a glyph, per the suite's rule.
-- SetRotation turns counter-clockwise, so +pi/4 is "/" and -pi/4 is "\":
-- shut is "\" over "/", meeting on the right (">"); open is "\" beside "/"
-- ("v").
local function EnsureChevron(button)
    if button.chevron then return button.chevron end
    local chevron = { Quad(button, "OVERLAY"), Quad(button, "OVERLAY") }
    for _, bar in ipairs(chevron) do bar:SetSize(7, 2) end
    button.chevron = chevron
    return chevron
end

local function PointChevron(button, open)
    local chevron = EnsureChevron(button)
    local top, bottom = chevron[1], chevron[2]
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if open then
        top:SetPoint("CENTER", button, "LEFT", 8, 1.5)
        bottom:SetPoint("CENTER", button, "LEFT", 12.5, 1.5)
        top:SetRotation(-math.pi / 4)
        bottom:SetRotation(math.pi / 4)
    else
        top:SetPoint("CENTER", button, "LEFT", 9, 2)
        bottom:SetPoint("CENTER", button, "LEFT", 9, -2)
        top:SetRotation(-math.pi / 4)
        bottom:SetRotation(math.pi / 4)
    end
end

-- On the paper a hovered tab or filter wears the highlight font's own white,
-- which over the pale toolbar wash reads at about 1.6:1: the word fades out
-- under the pointer. So on paper the hovered label is inked as well -- at
-- once, and again a frame later so it lands after the client's own swap to
-- the highlight font whichever runs first (the OnLeave re-ink's reasoning).
-- Off the paper the white is the right hover and is left alone.
local function InkOnHover(button)
    if not (button and button.HookScript) then return end
    local function InkLabel()
        if not OnPaper() then return end
        local fs = button.GetFontString and button:GetFontString()
        if fs then fs:SetTextColor(Ink("strong")) end
    end
    button:HookScript("OnEnter", function()
        InkLabel()
        if C_Timer and C_Timer.After then C_Timer.After(0, InkLabel) end
    end)
end

-- Bring a navigator row (top and height in the scroll child's units) into
-- view, for a quest asked for from outside: a selection band forty rows below
-- the fold briefs the right quest and shows the player nothing. Only when the
-- row is off screen, with a third of the pane above it for context. A scroll
-- frame learns a new range only when it next lays out, and its scrollbar
-- clamps an offset past the old one, so the range is also worked out from
-- the child's height and the offset is set once more a frame later -- unless
-- something scrolled it for another reason in between (the serial).
local function ScrollIntoView(scroll, child, top, height)
    if not (scroll and top and scroll.SetVerticalScroll and scroll.GetHeight) then return end
    local serial = (scroll.cqlRevealSerial or 0) + 1
    scroll.cqlRevealSerial = serial
    local function Apply()
        if scroll.cqlRevealSerial ~= serial then return end
        local view = scroll:GetHeight() or 0
        if view <= 0 then return end
        local offset = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
        if top >= offset and top + (height or 0) <= offset + view then return end
        local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
        local content = child and child.GetHeight and child:GetHeight() or 0
        range = math.max(range or 0, content - view, 0)
        scroll:SetVerticalScroll(math.max(0, math.min(top - math.floor(view / 3), range)))
    end
    Apply()
    if C_Timer and C_Timer.After then C_Timer.After(0, Apply) end
end

-- A scroll reset (a tab change) cancels a reveal still waiting on its frame
local function CancelReveal(scroll)
    if scroll then scroll.cqlRevealSerial = (scroll.cqlRevealSerial or 0) + 1 end
end

-- ---------------------------------------------------------------------------
-- Channel resolution for Announce
-- ---------------------------------------------------------------------------

local function AnnounceTarget()
    local choice = DB().AnnounceChannel or "AUTO"
    if choice == "SELF" then return nil end
    if choice == "SAY" then return "SAY" end
    if choice == "GUILD" then return IsInGuild and IsInGuild() and "GUILD" or nil end
    local inRaid = IsInRaid and IsInRaid()
    local inParty = IsInGroup and IsInGroup()
    if choice == "GROUP" or choice == "AUTO" then
        if inRaid then return "RAID" end
        if inParty then return "PARTY" end
        return nil
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Actions
--
-- Every one of these re-derives the log index from the selected entry at the
-- moment it runs. A log index is invalidated by any quest being accepted or
-- turned in, so a button that captured one when the row was drawn would act
-- on whatever quest had since slid into that slot.
-- ---------------------------------------------------------------------------

local function CurrentIndex()
    if not selectedEntry then return nil end
    local index = selectedEntry.index
    if not (index and GetQuestLogTitle) then return nil end
    local title, _, _, isHeader = GetQuestLogTitle(index)
    -- The guard, not a formality: if the log moved under us the title no
    -- longer matches and the action is refused rather than misapplied.
    if isHeader or title ~= selectedEntry.title then return nil end
    return index
end

function Q.ToggleTrack()
    local index = CurrentIndex()
    if not index then return end
    if IsQuestWatched and IsQuestWatched(index) then
        if RemoveQuestWatch then RemoveQuestWatch(index) end
    else
        if (GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(index) or 0) == 0 then
            print("Commander Quest Log: |cffffd100" .. (selectedEntry.title or "that quest") ..
                "|r has no objectives to track.")
            return
        end
        if AddQuestWatch then AddQuestWatch(index) end
        -- The era caps the tracker at five and simply declines past that,
        -- silently, which reads as the button being broken
        if IsQuestWatched and not IsQuestWatched(index) then
            print("Commander Quest Log: the objective tracker is full — untrack something first.")
        end
    end
    if QuestWatch_Update then QuestWatch_Update() end
    Q.Refresh()
end

function Q.Share()
    local index = CurrentIndex()
    if not index then return end
    if SelectQuestLogEntry then SelectQuestLogEntry(index) end
    if GetQuestLogPushable and not GetQuestLogPushable() then
        print("Commander Quest Log: |cffffd100" .. (selectedEntry.title or "that quest") .. "|r cannot be shared.")
        return
    end
    if QuestLogPushQuery then QuestLogPushQuery(index) end
end

function Q.Announce()
    if not selectedEntry then return end
    local entry = selectedEntry
    local head = string.format("[%s]%s", entry.title or "?",
        entry.isComplete and " — ready to turn in" or "")
    local lines = { head }
    if not entry.isComplete then
        for _, objective in ipairs(entry.objectives) do
            lines[#lines + 1] = "  " .. (objective.text or "")
        end
    end
    local channel = AnnounceTarget()
    for _, line in ipairs(lines) do
        if channel and SendChatMessage then
            SendChatMessage(line, channel)
        else
            print("|cff88bbffCommander|r " .. line)
        end
    end
end

if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_QUESTLOG_ABANDON"] = {
        text = "Abandon %s?",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(self, data)
            Q.AbandonConfirmed(data)
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        showAlert = 1,
    }
end

-- Takes the remembered title rather than an index, and refuses if the log has
-- moved since the dialog went up. The stock flow re-reads the selection at
-- accept time and will happily drop whatever is selected by then.
function Q.AbandonConfirmed(title)
    if not (SetAbandonQuest and AbandonQuest and GetQuestLogTitle) then return end
    local index
    for candidate = 1, (GetNumQuestLogEntries and GetNumQuestLogEntries() or 0) do
        local name, _, _, isHeader = GetQuestLogTitle(candidate)
        if not name then break end
        if not isHeader and name == title then index = candidate break end
    end
    if not index then
        print("Commander Quest Log: |cffffd100" .. tostring(title) ..
            "|r is no longer in the log — nothing abandoned.")
        return
    end
    SelectQuestLogEntry(index)
    SetAbandonQuest()
    AbandonQuest()
    print("Commander Quest Log: abandoned |cffffd100" .. tostring(title) .. "|r.")
    Q.Refresh()
end

function Q.Abandon()
    local index = CurrentIndex()
    if not index then return end
    local title = selectedEntry.title
    if DB().ConfirmAbandon == false or not StaticPopup_Show then
        Q.AbandonConfirmed(title)
        return
    end
    local dialog = StaticPopup_Show("COMMANDER_QUESTLOG_ABANDON", title)
    if dialog then dialog.data = title end
end

-- ---------------------------------------------------------------------------
-- Questie, when it is there
--
-- The Log is the live log and works without Questie (D13 still holds for
-- everything the client can answer). What the client cannot answer is where
-- a quest is handed in, and Questie can: with it loaded and ready, the
-- briefing gains a "Turn in:" line and the action bar a Waypoint button. All
-- of it goes through the adapter (Q.Questie), which is the only file that
-- names Questie, and every answer is optional.
-- ---------------------------------------------------------------------------

local function QuestieReady()
    local adapter = Q.Questie
    if not (adapter and adapter.State) then return false end
    local ok, state = pcall(adapter.State)
    return ok and state == "READY"
end

-- One lookup per quest per adapter generation. A refresh runs on every
-- objective tick; the answer changes only when Questie's does.
local finisherCache = { generation = -1 }

local function LogFinisher(entry)
    local adapter = Q.Questie
    if not (entry and adapter and adapter.Finisher) then return nil end
    local questID = entry.questID
    if type(questID) ~= "number" or questID <= 0 or not QuestieReady() then return nil end
    local generation = adapter.generation or 0
    if finisherCache.generation ~= generation then finisherCache = { generation = generation } end
    local found = finisherCache[questID]
    if found == nil then
        found = adapter.Finisher(questID) or false
        finisherCache[questID] = found
    end
    return found or nil
end

-- "Turn in: Force Commander Danath — Hellfire Peninsula (56.6, 66.4)"
local function FinisherLine(finisher)
    local text = "Turn in: " .. (finisher.name or "the quest giver")
    if finisher.zoneName then text = text .. " \226\128\148 " .. finisher.zoneName end
    if finisher.x and finisher.y then
        text = text .. string.format(" (%.1f, %.1f)", finisher.x, finisher.y)
    end
    return text
end

-- Which way a Waypoint press will go, for the tooltips: they say so rather
-- than leaving the player to find out by pressing it
local WAYPOINT_WORDS = {
    ORDERS = "the Commander Orders arrow, which picks the nearest spawn when there are several",
    ORDERS_OFF = "the chat frame, as coordinates and a /way line (Commander Orders is turned off)",
    PRINT = "the chat frame, as coordinates and a /way line (Commander Orders is not loaded)",
}

local function WaypointWhere()
    local adapter = Q.Questie
    local path = adapter and adapter.WaypointPath and adapter.WaypointPath() or "PRINT"
    return WAYPOINT_WORDS[path] or WAYPOINT_WORDS.PRINT
end

function Q.LogWaypoint()
    local finisher = selectedFinisher
    local adapter = Q.Questie
    if not (selectedEntry and finisher and finisher.x and adapter and adapter.Waypoint) then return end
    adapter.Waypoint({
        title = string.format("%s (%s)", selectedEntry.title or "Quest", finisher.name or "turn in"),
        areaId = finisher.areaId, uiMapId = finisher.uiMapId, zoneName = finisher.zoneName,
        x = finisher.x, y = finisher.y, questId = selectedEntry.questID, spawns = finisher.spawns,
    })
end

-- ---------------------------------------------------------------------------
-- Navigator rows
-- ---------------------------------------------------------------------------

local function AcquireNavRow(position)
    local row = navRows[position]
    if row then return row end

    row = CreateFrame("Button", nil, navChild)
    row:SetPoint("LEFT", navChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)
    row:SetHeight(QUEST_ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.selection = Quad(row, "BACKGROUND")
    row.selection:SetAllPoints()
    row.selection:Hide()

    row.pip = Quad(row, "ARTWORK", 1)
    row.pip:SetWidth(3)
    row.pip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    row.pip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    row.pip:Hide()

    row.level = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.level:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.level:SetWidth(26)
    row.level:SetJustifyH("RIGHT")

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
    row.title:SetJustifyH("LEFT")
    -- One line, ending in an ellipsis when long: a wrapped title fills the
    -- row and runs into the next. The row's tooltip has the whole title.
    if row.title.SetWordWrap then row.title:SetWordWrap(false) end

    row.state = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.state:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.state:SetJustifyH("RIGHT")

    row.barBg = Quad(row, "ARTWORK", 1)
    row.barBg:SetHeight(2)
    row.barBg:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 3)
    row.barBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 3)
    row.barBg:SetVertexColor(1, 1, 1, 0.1)
    row.barBg:Hide()

    row.bar = Quad(row, "ARTWORK", 2)
    row.bar:SetHeight(2)
    row.bar:SetPoint("BOTTOMLEFT", row.barBg, "BOTTOMLEFT", 0, 0)
    row.bar:Hide()

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.07)
    row:SetHighlightTexture(highlight)

    row:SetScript("OnClick", function(self, button)
        if self.headerTitle then
            local collapsed = DB().Collapsed or {}
            collapsed[self.headerTitle] = (not collapsed[self.headerTitle]) or nil
            DB().Collapsed = collapsed
            Q.Refresh()
            return
        end
        if not self.entry then return end
        if button == "RightButton" then
            selectedKey = self.entry.key
            selectedEntry = self.entry
            Q.ToggleTrack()
            return
        end
        if IsShiftKeyDown and IsShiftKeyDown() then
            selectedKey = self.entry.key
            selectedEntry = self.entry
            Q.Announce()
            return
        end
        selectedKey = self.entry.key
        Q.Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.entry.title, 1, 1, 1)
        if self.entry.header then
            GameTooltip:AddLine(self.entry.header, 0.7, 0.7, 0.75)
        end
        for _, objective in ipairs(self.entry.objectives) do
            if objective.finished then
                GameTooltip:AddLine(objective.text, 0.4, 0.8, 0.4)
            else
                GameTooltip:AddLine(objective.text, 0.85, 0.85, 0.85)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Right-click to track. Shift-click to announce.", 0.55, 0.55, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    navRows[position] = row
    return row
end

local function LayoutNav()
    local db = DB()
    local showLevels = db.ShowLevels ~= false
    local showProgress = db.ShowProgress ~= false
    local showCounts = db.ShowZoneCounts ~= false
    -- Selection, heading wash, chevrons, pips and bars all sit on the sheet
    local ar, ag, ab = InkAccent()
    local y = 4
    selectedTop, selectedHeight = nil, nil

    for position, item in ipairs(rows) do
        local row = AcquireNavRow(position)
        row.entry, row.headerTitle = nil, nil
        row.selection:Hide()
        row.pip:Hide()
        row.barBg:Hide()
        row.bar:Hide()

        if item.header then
            row.headerTitle = item.header.title
            row:SetHeight(ROW_H)
            PointChevron(row, not item.collapsed)
            for _, bar in ipairs(row.chevron) do
                bar:SetVertexColor(ar, ag, ab, 0.9)
                bar:Show()
            end
            row.level:SetText("")
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", row, "LEFT", 20, 0)
            row.title:SetText(item.header.title)
            row.title:SetTextColor(InkAccent())
            if showCounts then
                local set = InkSet()
                row.state:SetText(string.format("|cff%s%d|r/|cff%s%d|r",
                    set.countDone, item.header.complete,
                    set.countAll, item.header.quests))
            else
                row.state:SetText("")
            end
            row.state:SetTextColor(Ink("secondary"))
            -- A zone heading gets a hairline of the accent under it so the
            -- list reads as grouped even with counts turned off
            row.selection:SetVertexColor(ar, ag, ab, 0.08)
            row.selection:Show()
        else
            local entry = item.entry
            row.entry = entry
            if row.chevron then
                for _, bar in ipairs(row.chevron) do bar:Hide() end
            end
            row:SetHeight(showProgress and QUEST_ROW_H_BAR or QUEST_ROW_H)

            if showLevels then
                row.level:SetText(tostring(entry.level or ""))
                row.level:SetTextColor(Paper(Q.DifficultyColor(entry.level)))
                row.title:ClearAllPoints()
                row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
            else
                row.level:SetText("")
                row.title:ClearAllPoints()
                row.title:SetPoint("LEFT", row, "LEFT", 14, 0)
            end
            row.title:SetPoint("RIGHT", row, "RIGHT", -46, 0)
            row.title:SetText(entry.title)

            if entry.isFailed then
                row.title:SetTextColor(Paper(0.7, 0.3, 0.3))
                row.state:SetText("|cff" .. PaperHex("cc4444") .. "failed|r")
            elseif entry.isComplete then
                row.title:SetTextColor(Ink("strong"))
                row.state:SetText("|cff" .. PaperHex("40d040") .. "ready|r")
            else
                row.title:SetTextColor(Ink("primary"))
                row.state:SetText("")
            end
            if entry.daily then
                row.state:SetText((row.state:GetText() or "") .. " |cff" .. PaperHex("40b0ff") .. "D|r")
            end
            if entry.watched then
                row.pip:SetVertexColor(ar, ag, ab, 1)
                row.pip:Show()
            end

            if showProgress then
                local progress = Q.Progress(entry)
                row.barBg:Show()
                if progress > 0 then
                    local span = (navChild:GetWidth() or 0)
                    if span <= 0 then span = NAV_W - 40 end
                    local width = math.max(1, (span - 16) * progress)
                    row.bar:SetWidth(width)
                    if entry.isComplete then
                        row.bar:SetVertexColor(0.25, 0.82, 0.25, 0.95)
                    else
                        row.bar:SetVertexColor(ar, ag, ab, 0.8)
                    end
                    row.bar:Show()
                end
            end

            if selectedKey and entry.key == selectedKey then
                row.selection:SetVertexColor(ar, ag, ab, 0.22)
                row.selection:Show()
                selectedTop, selectedHeight = y, row:GetHeight()
            end
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)
        row:Show()
        y = y + row:GetHeight()
    end

    for position = #rows + 1, #navRows do navRows[position]:Hide() end

    if #rows == 0 then
        if not navChild.emptyFS then
            navChild.emptyFS = navChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
            navChild.emptyFS:SetPoint("TOPLEFT", navChild, "TOPLEFT", 12, -16)
            navChild.emptyFS:SetWidth(NAV_W - 30)
            navChild.emptyFS:SetJustifyH("LEFT")
        end
        navChild.emptyFS:SetText(numQuests == 0
            and "Your quest log is empty. Go and find someone with an exclamation mark over their head."
            or "Nothing in the log matches this search and filter.")
        navChild.emptyFS:SetTextColor(Ink("faint"))
        navChild.emptyFS:Show()
        y = y + 40
    elseif navChild.emptyFS then
        navChild.emptyFS:Hide()
    end

    navChild:SetHeight(math.max(y + 6, 1))
end

-- ---------------------------------------------------------------------------
-- The briefing
--
-- Blocks are recycled by KIND and index rather than rebuilt, and laid out
-- top-down by measuring each wrapped string. There is no other way to stack
-- variable-height text in this UI toolkit, and a briefing that guessed at
-- heights would either clip a long description or leave a hole after a short
-- one.
-- ---------------------------------------------------------------------------

-- Pooled by position, but the font is re-applied on every pass. Position 3 is
-- the timer line on a timed quest and the OBJECTIVES heading on every other
-- one, so a block created large and reused small would render an ordinary
-- body line in the title's font for the rest of the session.
local function AcquireBlock(kind, position, template)
    detailBlocks[kind] = detailBlocks[kind] or {}
    local pool = detailBlocks[kind]
    local block = pool[position]
    if not block then
        block = detailChild:CreateFontString(nil, "ARTWORK", template)
        block:SetJustifyH("LEFT")
        block:SetJustifyV("TOP")
        block._template = template
        pool[position] = block
        return block
    end
    if block._template ~= template then
        block._template = template
        local font = _G[template]
        if font and block.SetFontObject then block:SetFontObject(font) end
    end
    return block
end

local function HideFrom(kind, from)
    local pool = detailBlocks[kind]
    if not pool then return end
    for position = from, #pool do pool[position]:Hide() end
end

local function AcquireRule(position)
    detailBlocks.rules = detailBlocks.rules or {}
    local rule = detailBlocks.rules[position]
    if rule then return rule end
    rule = Quad(detailChild, "ARTWORK")
    rule:SetHeight(1)
    detailBlocks.rules[position] = rule
    return rule
end

local function AcquireRewardButton(position)
    local button = rewardButtons[position]
    if button then return button end
    button = CreateFrame("Button", "CommanderQuestLogReward" .. position, detailChild)
    button:SetSize(REWARD_SIZE, REWARD_SIZE)
    button.icon = button:CreateTexture(nil, "BACKGROUND")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- The quality ring, drawn: four quads round the icon. IconBorder writes do
    -- not stick on this client, which is why nothing here goes near it.
    button.ring = {}
    for edge = 1, 4 do button.ring[edge] = Quad(button, "OVERLAY", 3) end
    button.ring[1]:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    button.ring[1]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    button.ring[1]:SetHeight(1)
    button.ring[2]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    button.ring[2]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    button.ring[2]:SetHeight(1)
    button.ring[3]:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -1)
    button.ring[3]:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 1)
    button.ring[3]:SetWidth(1)
    button.ring[4]:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, -1)
    button.ring[4]:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 1)
    button.ring[4]:SetWidth(1)

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.2)
    button:SetHighlightTexture(highlight)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local filled = false
        if GameTooltip.SetQuestLogItem and self.rewardKind and self.slot then
            -- Only meaningful while OUR quest is the selected entry, which
            -- LayoutDetail guarantees by selecting before it draws
            GameTooltip:SetQuestLogItem(self.rewardKind, self.slot)
            filled = (GameTooltip.NumLines and GameTooltip:NumLines() or 0) > 0
        end
        if not filled and self.link and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(self.link)
            filled = (GameTooltip.NumLines and GameTooltip:NumLines() or 0) > 0
        end
        if not filled then
            GameTooltip:SetText(self.rewardName or "", QualityColor(self.quality))
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", function(self)
        if self.link and IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
            ChatEdit_InsertLink(self.link)
        end
    end)
    rewardButtons[position] = button
    return button
end

local function DetailWidth()
    return FRAME_W - NAV_W - PAD * 3 - 30
end

-- ---------------------------------------------------------------------------
-- The kit
--
-- The Zones tab (CommanderQuestLogZones.lua) and the world-map drawer draw
-- with the same ink, the same quads and the same panes as this file, and get
-- them here rather than each growing a copy: a second Paper() that drifted
-- from this one is exactly how D16 would quietly come undone. They are
-- separate files because threading a second mode through AcquireNavRow and
-- LayoutDetail would have turned every Log code path into a mode switch --
-- and because Lua 5.1 caps a function at 60 upvalues and a file's main chunk
-- at 200 locals, a budget this file should not spend on another tab.
--
-- Frame pieces are handed over as accessors, not values: the window is built
-- lazily on its first show, long after this table is made.
-- ---------------------------------------------------------------------------

Q._kit = {
    QUAD = QUAD, PAD = PAD, NAV_W = NAV_W, TOOLBAR_H = TOOLBAR_H, ACTIONS_H = ACTIONS_H,
    ROW_H = ROW_H, QUEST_ROW_H = QUEST_ROW_H, QUEST_ROW_H_BAR = QUEST_ROW_H_BAR,
    REWARD_SIZE = REWARD_SIZE, FRAME_W = FRAME_W, FRAME_H = FRAME_H,
    Accent = Accent, Paper = Paper, PaperHex = PaperHex, Ink = Ink, InkAccent = InkAccent,
    InkSet = InkSet, OnPaper = OnPaper, Quad = Quad, EnsureChevron = EnsureChevron,
    PointChevron = PointChevron, QualityColor = QualityColor, DB = DB,
    AcquireRewardButton = AcquireRewardButton, DetailWidth = DetailWidth,
    WaypointWhere = WaypointWhere, InkOnHover = InkOnHover,
    ScrollIntoView = ScrollIntoView, CancelReveal = CancelReveal,
    Frame = function() return frame end,
    NavChild = function() return navChild end,
    DetailChild = function() return detailChild end,
    NavScroll = function() return navScroll end,
    DetailScroll = function() return detailScroll end,
}

local function LayoutDetail()
    local width = DetailWidth()
    local ar, ag, ab = InkAccent()
    local y = 6
    local blocks, rules, rewards = 1, 1, 1

    local DEFAULT_TEXT = { Ink("secondary") }
    local function Body(text, template, color, indent)
        local block = AcquireBlock("body", blocks, template or "GameFontHighlightSmall")
        blocks = blocks + 1
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", detailChild, "TOPLEFT", PAD + (indent or 0), -y)
        block:SetWidth(width - (indent or 0))
        block:SetText(text or "")
        color = color or DEFAULT_TEXT
        block:SetTextColor(Paper(color[1], color[2], color[3]))
        block:Show()
        y = y + math.max(block:GetStringHeight() or 12, 12) + 3
        return block
    end

    local function Rule(spacingAbove)
        y = y + (spacingAbove or 6)
        local rule = AcquireRule(rules)
        rules = rules + 1
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", detailChild, "TOPLEFT", PAD, -y)
        rule:SetPoint("RIGHT", detailChild, "RIGHT", -PAD, 0)
        rule:SetVertexColor(ar, ag, ab, 0.25)
        rule:Show()
        y = y + 7
    end

    if not selectedEntry then
        Body(numQuests == 0
            and "Nothing to brief. The log is empty."
            or "Pick a quest on the left and its briefing appears here.",
            "GameFontDisableSmall")
        HideFrom("body", blocks)
        HideFrom("rules", rules)
        for position = rewards, #rewardButtons do rewardButtons[position]:Hide() end
        detailChild:SetHeight(math.max(y + 8, 1))
        return
    end

    local entry = selectedEntry
    local detail = selectedDetail or {}

    Body(entry.title, "GameFontNormalLarge", InkSet().title)

    local facts = {}
    if entry.level then facts[#facts + 1] = "Level " .. entry.level end
    if entry.header then facts[#facts + 1] = entry.header end
    if entry.group then facts[#facts + 1] = "Suggested group of " .. entry.group end
    if entry.tag then facts[#facts + 1] = entry.tag end
    if entry.daily then facts[#facts + 1] = "Daily" end
    if entry.watched then facts[#facts + 1] = "Tracked" end
    Body(table.concat(facts, "  \194\183  "), "GameFontDisableSmall")
    -- Where it is handed in, when Questie knows. The refresh looked it up;
    -- this only draws it (D2).
    if selectedFinisher then
        Body(FinisherLine(selectedFinisher), "GameFontHighlightSmall", { Ink("secondary") })
    end

    if detail.timeLeft then
        local minutes = math.floor(detail.timeLeft / 60)
        Body(string.format("Time remaining: %d:%02d", minutes, detail.timeLeft % 60),
            "GameFontNormalSmall", { 1, 0.5, 0.2 })
    end
    if entry.isFailed then
        Body("This quest has failed. Abandon it and pick it up again.",
            "GameFontNormalSmall", { 0.85, 0.3, 0.3 })
    end

    Rule(4)

    Body("OBJECTIVES", "GameFontNormalSmall", { InkAccent() })
    if detail.objectivesText and detail.objectivesText ~= "" then
        Body(detail.objectivesText, "GameFontHighlightSmall", { Ink("primary") }, 4)
    end
    if #entry.objectives == 0 then
        Body(entry.isComplete and "Return to the quest giver." or "No countable objectives.",
            "GameFontHighlightSmall", { 0.7, 0.7, 0.75 }, 4)
    end
    for _, objective in ipairs(entry.objectives) do
        local color = objective.finished and { 0.35, 0.8, 0.35 } or { 0.92, 0.86, 0.6 }
        local mark = objective.finished and "\194\183 " or "\194\183 "
        Body(mark .. (objective.text or ""), "GameFontHighlightSmall", color, 6)
    end
    if entry.isComplete then
        Body("Ready to turn in.", "GameFontNormalSmall", { 0.35, 0.85, 0.35 }, 4)
    end

    if detail.description and detail.description ~= "" then
        Rule()
        Body("DESCRIPTION", "GameFontNormalSmall", { InkAccent() })
        Body(detail.description, "GameFontHighlightSmall", { Ink("primary") }, 4)
    end

    local showRewards = DB().ShowRewards ~= false
    local hasRewards = showRewards and (#(detail.choices or {}) > 0 or #(detail.rewards or {}) > 0
        or detail.spell or (detail.money or 0) > 0)

    if hasRewards then
        Rule()
        Body("REWARDS", "GameFontNormalSmall", { InkAccent() })

        local function Grid(list, caption)
            if #list == 0 then return end
            Body(caption, "GameFontDisableSmall", nil, 4)
            local perRow = math.max(1, math.floor((width - 8) / (REWARD_SIZE + 78)))
            local column, rowTop = 0, y
            for _, item in ipairs(list) do
                local slot = rewards
                rewards = rewards + 1
                local button = AcquireRewardButton(slot)
                button.rewardKind = item.kind
                button.slot = item.slot
                button.link = item.link
                button.rewardName = item.name
                button.quality = item.quality
                button.icon:SetTexture(item.texture)
                button.count:SetText((item.count or 1) > 1 and item.count or "")
                local qr, qg, qb = QualityColor(item.quality)
                for _, edge in ipairs(button.ring) do edge:SetVertexColor(qr, qg, qb, 1) end
                button.icon:SetDesaturated(not item.usable)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", detailChild, "TOPLEFT",
                    PAD + 6 + column * (REWARD_SIZE + 78), -rowTop)
                button:Show()

                local label = AcquireBlock("rewardName", slot, "GameFontHighlightSmall")
                label:ClearAllPoints()
                label:SetPoint("LEFT", button, "RIGHT", 4, 0)
                label:SetWidth(72)
                label:SetText(item.name or "")
                label:SetTextColor(qr, qg, qb)
                label:Show()

                column = column + 1
                if column >= perRow then
                    column = 0
                    rowTop = rowTop + REWARD_SIZE + 6
                end
            end
            y = rowTop + REWARD_SIZE + 8
        end

        Grid(detail.choices or {}, "Choose one of:")
        Grid(detail.rewards or {}, "You will also receive:")

        if detail.spell then
            Body("Learn: " .. detail.spell.name, "GameFontHighlightSmall", { 0.7, 0.85, 1 }, 6)
        end
        if (detail.money or 0) > 0 then
            local money = GetCoinTextureString and GetCoinTextureString(detail.money)
                or tostring(math.floor(detail.money / 10000)) .. "g"
            Body("Money: " .. money, "GameFontHighlightSmall", { 0.9, 0.85, 0.6 }, 6)
        end
        if (detail.requiredMoney or 0) > 0 then
            local money = GetCoinTextureString and GetCoinTextureString(detail.requiredMoney)
                or tostring(detail.requiredMoney)
            Body("Required: " .. money, "GameFontHighlightSmall", { 0.9, 0.5, 0.4 }, 6)
        end
    end

    HideFrom("body", blocks)
    HideFrom("rewardName", rewards)
    HideFrom("rules", rules)
    for position = rewards, #rewardButtons do rewardButtons[position]:Hide() end
    detailChild:SetHeight(math.max(y + 10, 1))
end

-- ---------------------------------------------------------------------------
-- Toolbar state
-- ---------------------------------------------------------------------------

local FILTER_ORDER = { "ALL", "ACTIVE", "COMPLETE", "TRACKED" }

-- The Log's filter labels and underlines. Its own function because a hover
-- swaps each label to the highlight font and back, and the swap puts the
-- font's own colour back over the ink; the filters' OnLeave calls this again.
local function StyleLogFilters()
    if not frame then return end
    local db = DB()
    local ar, ag, ab = InkAccent()
    for _, key in ipairs(FILTER_ORDER) do
        local button = frame.filters[key]
        local active = (db.Filter or "ALL") == key
        if button.SetNormalFontObject then
            button:SetNormalFontObject(active and GameFontNormalSmall or GameFontDisableSmall)
        end
        -- After the font object, never before: swapping it re-applies the
        -- font's own colour and would wash out anything set at build time.
        -- Blizzard's disabled grey is what this is here to avoid.
        if button.GetFontString then
            local fs = button:GetFontString()
            if fs then
                if active then
                    fs:SetTextColor(Ink("strong"))
                else
                    fs:SetTextColor(Ink("faint"))
                end
            end
        end
        button.underline:SetVertexColor(ar, ag, ab, active and 0.95 or 0)
    end
end

local function UpdateToolbar(shown)
    if not frame then return end
    local ar, ag, ab = InkAccent()
    StyleLogFilters()

    local cap = Q.MAX_QUESTS or 25
    local color = "88cc88"
    if numQuests >= cap then
        color = "ff5555"
    elseif numQuests >= cap - 3 then
        color = "ffcc55"
    end
    color = "|cff" .. PaperHex(color)
    local text = string.format("%s%d|r/%d", color, numQuests, cap)
    if shown and shown ~= numQuests then
        text = string.format("%d shown  \194\183  %s", shown, text)
    end
    frame.countFS:SetText(text)
    frame.countFS:SetTextColor(Ink("secondary"))

    local hasSelection = selectedEntry ~= nil
    frame.trackBtn:SetEnabled(hasSelection)
    frame.shareBtn:SetEnabled(hasSelection and (selectedDetail == nil or selectedDetail.pushable))
    frame.announceBtn:SetEnabled(hasSelection)
    frame.abandonBtn:SetEnabled(hasSelection)
    frame.waypointBtn:SetEnabled(hasSelection and selectedFinisher ~= nil and selectedFinisher.x ~= nil)
    frame.trackBtn:SetText(hasSelection and selectedEntry.watched and "Untrack" or "Track")

    if frame.titleAccent then
        frame.titleAccent:SetVertexColor(ar, ag, ab, 0.5)
    end
end

-- ---------------------------------------------------------------------------
-- The reset footer
--
-- Two countdowns under the navigator: the daily reset, when the dailies come
-- back, and the weekly reset, when arena points are paid and raid lockouts
-- clear. The model reads the clocks (and decides which weekly figure to
-- believe); this only draws them, once a second, and only writes a string
-- when it has changed.
-- ---------------------------------------------------------------------------

local function ShowingResets()
    return DB().ShowResetTimers ~= false
end

-- The navigator's bottom edge: down to the sheet when the footer is off,
-- level with the briefing's when the footer sits under it
local function AnchorNavPane()
    if not (frame and frame.navPane) then return end
    local pane = frame.navPane
    -- On the Zones tab the zone card sits over the navigator column and the
    -- pane moves down to make room for it; the Log has nothing there
    local inset = (Q.Zones and Q.Zones.NavTopInset and Q.Zones.NavTopInset()) or 0
    pane:ClearAllPoints()
    pane:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8 - inset)
    pane:SetWidth(NAV_W)
    if ShowingResets() then
        pane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + 4 + ACTIONS_H + 4)
    else
        pane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD + 4)
    end
    if frame.resets then frame.resets:SetShown(ShowingResets()) end
end

local function SetIfChanged(fs, text)
    if fs._last ~= text then
        fs._last = text
        fs:SetText(text)
    end
end

-- Under a quarter hour the value warms up: a daily you meant to do is about
-- to be gone, a lockout you were waiting on is about to open
local SOON = 15 * 60

function Q.UpdateResets()
    if not (frame and frame.resets and ShowingResets()) then return end
    local resets = Q.ReadResets()
    frame._resets = resets
    local lr, lg, lb = InkAccent()
    for _, segment in ipairs({ frame.resetDaily, frame.resetWeekly }) do
        segment.label:SetTextColor(lr, lg, lb)
    end

    local function Paint(segment, seconds)
        SetIfChanged(segment.value, Q.FormatCountdown(seconds))
        if type(seconds) ~= "number" then
            segment.value:SetTextColor(Ink("faint"))
        elseif seconds <= SOON then
            segment.value:SetTextColor(Paper(1, 0.62, 0.25))
        else
            segment.value:SetTextColor(Ink("primary"))
        end
    end
    Paint(frame.resetDaily, resets.daily)
    Paint(frame.resetWeekly, resets.weekly)
end

function Q.ResetTooltip(owner, which)
    local resets = frame and frame._resets or Q.ReadResets()
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    if which == "daily" then
        GameTooltip:SetText("Daily reset", 1, 1, 1)
        if resets.daily then
            GameTooltip:AddLine(string.format("Daily quests reset in %s.", Q.FormatCountdown(resets.daily)),
                0.85, 0.85, 0.85, true)
            local moment = Q.FormatResetMoment(resets.daily, resets.now, resets.offset)
            if moment then GameTooltip:AddLine(moment .. ", server time.", 0.7, 0.7, 0.75) end
        else
            GameTooltip:AddLine("The client has not said when the dailies reset.", 0.7, 0.7, 0.75, true)
        end
        if resets.dailyDone and resets.dailyMax and resets.dailyMax > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(string.format("%d of %d daily quests done today.", resets.dailyDone, resets.dailyMax),
                0.4, 0.75, 1)
        end
    else
        GameTooltip:SetText("Weekly reset", 1, 1, 1)
        if resets.weekly then
            GameTooltip:AddLine(string.format("Arena points are paid and raid lockouts clear in %s.",
                Q.FormatCountdown(resets.weekly)), 0.85, 0.85, 0.85, true)
            local moment = Q.FormatResetMoment(resets.weekly, resets.now, resets.offset)
            if moment then GameTooltip:AddLine(moment .. ", server time.", 0.7, 0.7, 0.75) end
            if resets.weeklySource == "computed" then
                GameTooltip:AddLine("Worked out from the daily reset and your region's reset day.",
                    0.55, 0.55, 0.6, true)
            end
        else
            GameTooltip:AddLine("The client has not said when the week resets.", 0.7, 0.7, 0.75, true)
        end
        local lockouts = Q.ReadLockouts()
        if #lockouts > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Your lockouts", 1, 0.82, 0.3)
            for _, lock in ipairs(lockouts) do
                local name = lock.name
                if lock.extended then name = name .. " (extended)" end
                GameTooltip:AddDoubleLine(name, Q.FormatCountdown(lock.reset),
                    lock.isRaid and 0.9 or 0.7, lock.isRaid and 0.9 or 0.7, lock.isRaid and 0.9 or 0.75,
                    0.85, 0.85, 0.85)
            end
        end
    end
    GameTooltip:Show()
end

Q.AnchorNavPane = AnchorNavPane

-- ---------------------------------------------------------------------------
-- Refresh
--
-- One scan either way, then one tab draws. The Zones tab is up only when it
-- is switched on and its file is loaded; a ViewMode of "ZONE" left over from
-- a session where it was, or a Zones tab turned off in the settings, is the
-- Log, with nothing else to clean up.
-- ---------------------------------------------------------------------------

local function ZoneMode()
    local db = DB()
    return db.ViewMode == "ZONE" and db.ShowZoneTab ~= false
        and Q.Zones ~= nil and Q.Zones.Refresh ~= nil
end

local LOG_ACTIONS = { "trackBtn", "shareBtn", "announceBtn", "waypointBtn", "abandonBtn" }

-- The Log's toolbar set and action bar, shown on the Log and put away while
-- the Zones tab draws in the same space. Navigator rows and briefing blocks
-- only ever need hiding here: the next Log pass shows what it uses.
local function SetLogWidgetsShown(shown)
    if not frame then return end
    for _, key in ipairs(FILTER_ORDER) do frame.filters[key]:SetShown(shown) end
    frame.sortDrop:SetShown(shown)
    frame.countHit:SetShown(shown)
    for _, name in ipairs(LOG_ACTIONS) do
        if frame[name] then frame[name]:SetShown(shown) end
    end
    if shown then return end
    for _, row in ipairs(navRows) do row:Hide() end
    for _, pool in pairs(detailBlocks) do
        for _, block in ipairs(pool) do block:Hide() end
    end
    for _, button in ipairs(rewardButtons) do button:Hide() end
    if navChild and navChild.emptyFS then navChild.emptyFS:Hide() end
end

function Q.Refresh()
    if not frame or not frame:IsShown() then return end
    local db = DB()

    entries, numQuests = Q.Scan()
    -- The adapter reads "ready to turn in" off the live log for both tabs,
    -- so it hears every scan whichever tab is up
    if Q.Questie and Q.Questie.SetLogEntries then Q.Questie.SetLogEntries(entries) end

    local mode = ZoneMode() and "ZONE" or "LOG"
    if frame._mode ~= mode then
        frame._mode = mode
        AnchorNavPane()
        -- Both tabs draw into the same two scroll frames, so the offset the
        -- other tab left would otherwise open this one part-way down (clamped
        -- to the new range): the top of the log off screen. Each tab starts
        -- at its top.
        if navScroll and navScroll.SetVerticalScroll then navScroll:SetVerticalScroll(0) end
        if detailScroll and detailScroll.SetVerticalScroll then detailScroll:SetVerticalScroll(0) end
        CancelReveal(navScroll)
        -- Each tab keeps its own search. The box is shared, so a tab change
        -- puts that tab's text in it; SetText arrives at OnTextChanged as NOT
        -- user input, which is what keeps it out of the other tab's search.
        if frame.searchBox then
            local text = searchText
            if mode == "ZONE" and Q.Zones.SearchText then text = Q.Zones.SearchText() or "" end
            frame.searchBox:SetText(text)
        end
    end
    -- A reveal asked for (RevealInLog, OpenToQuest) is this pass's to do
    local reveal = revealSelection
    revealSelection = false
    if mode == "ZONE" then
        SetLogWidgetsShown(false)
        Q.Zones.Refresh(entries)
        Q.UpdateResets()
        return
    end
    if Q.Zones and Q.Zones.HideAll then Q.Zones.HideAll() end
    SetLogWidgetsShown(true)

    -- Re-find the selection by key. The index it had is meaningless after any
    -- accept or turn-in; the key survives both.
    selectedEntry = nil
    if selectedKey then
        for _, entry in ipairs(entries) do
            if not entry.isHeader and entry.key == selectedKey then
                selectedEntry = entry
                break
            end
        end
    end

    local shown
    rows, shown = Q.BuildList(entries, {
        search = searchText,
        filter = db.Filter or "ALL",
        sort = db.Sort or "LOG",
        collapsed = db.Collapsed or {},
    })

    -- The selection has to be a row that is actually on screen. Finding it in
    -- the scan is not enough: narrowing the filter past it, or folding its
    -- zone shut, would leave the briefing showing a quest the navigator no
    -- longer lists. Nothing selected at all (first open, or it was turned in)
    -- lands here too.
    local onScreen = false
    for _, item in ipairs(rows) do
        if item.entry and item.entry == selectedEntry then onScreen = true break end
    end
    if not onScreen then
        selectedEntry, selectedKey = nil, nil
        for _, item in ipairs(rows) do
            if item.entry then
                selectedEntry = item.entry
                selectedKey = item.entry.key
                break
            end
        end
    end

    selectedDetail = selectedEntry and Q.ReadDetail(selectedEntry.index) or nil
    selectedFinisher = LogFinisher(selectedEntry)
    -- The reward tooltips read from the SELECTED log entry, so it is left
    -- pointing at the briefed quest for as long as the window is up
    if selectedEntry and SelectQuestLogEntry then
        SelectQuestLogEntry(selectedEntry.index)
    end

    LayoutNav()
    if reveal then ScrollIntoView(navScroll, navChild, selectedTop, selectedHeight) end
    LayoutDetail()
    UpdateToolbar(shown)
    Q.UpdateResets()
end

local function QueueRefresh()
    if pendingRefresh or not (frame and frame:IsShown()) then return end
    pendingRefresh = true
    -- QUEST_LOG_UPDATE fires in bursts — several per accepted quest, and again
    -- on every objective tick. One pass per frame is plenty and keeps a busy
    -- grind from relaying the whole window a dozen times a second.
    local function Run()
        pendingRefresh = false
        Q.Refresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.05, Run) else Run() end
end

Q.QueueRefresh = QueueRefresh

-- ---------------------------------------------------------------------------
-- Position and framing
-- ---------------------------------------------------------------------------

local function SavePosition()
    if not frame then return end
    local point, _, _, x, y = frame:GetPoint(1)
    if point then
        local scale = frame:GetScale() or 1
        DB().FramePos = { point = point, x = x * scale, y = y * scale }
    end
end

function Q.ApplyPosition()
    if not frame then return end
    local db = DB()
    local scale = db.FrameScale or 1
    frame:SetScale(scale)
    if frame._dragging then return end
    frame:ClearAllPoints()
    local pos = db.FramePos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

-- The sheet's two materials share the dialog border and differ in the fill:
-- the stock log's paper, or the dark stone of Blizzard's own dialog boxes
-- (the "Dark Stone" the Console offers, and the weight the rest of the suite
-- carries). Both fills are tinted quads UNDER the backdrop as well -- see
-- EnsureSheet for why.
local SHEET_BACKDROP = {
    PARCHMENT = {
        bgFile = "Interface\\QuestFrame\\QuestBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 256, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
    STONE = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    },
}
local SHEET_BASE = {
    -- Cream, not tan: the sheet used to be (0.83, 0.72, 0.53), a mid-tone
    -- that left dark ink and bright colour alike within a shade of it.
    PARCHMENT = { 0.91, 0.85, 0.70 },
    STONE = { 0.09, 0.09, 0.10 },
}

local INSET_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function EnsureSheet(material)
    local art = frame.parchment
    if not art then
        art = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        art:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
        frame.parchment = art
    end
    if art._material ~= material then
        art._material = material
        if art.SetBackdrop then
            art:SetBackdrop(SHEET_BACKDROP[material] or SHEET_BACKDROP.STONE)
            art:SetBackdropColor(1, 1, 1, 1)
            art:SetBackdropBorderColor(1, 1, 1, 1)
        end
        if frame.paperBase then
            local base = SHEET_BASE[material] or SHEET_BASE.STONE
            frame.paperBase:SetColorTexture(base[1], base[2], base[3], 1)
        end
    end
    if frame.headerPlate then return art end

    -- The paper itself is DRAWN, not borrowed.
    --
    -- A backdrop whose bgFile fails to resolve still draws its EDGE and paints
    -- no background at all -- which is exactly what this window was doing. It
    -- went unnoticed for as long as the template's own Bg sat on top of the
    -- parchment; the moment the dressing was correctly hidden, the window
    -- became a hole in the screen with the world showing through it.
    --
    -- So the fill is a tinted quad cut from WHITE8X8, which is the one texture
    -- this suite treats as always present (Bags and Meters document why art
    -- FILES are not). The backdrop above still gets to draw its parchment over
    -- this if it resolves; if it does not, the window is still a window.
    local base = art:CreateTexture(nil, "BACKGROUND", nil, -8)
    local fill = SHEET_BASE[material] or SHEET_BASE.STONE
    base:SetColorTexture(fill[1], fill[2], fill[3], 1)
    base:SetPoint("TOPLEFT", art, "TOPLEFT", 10, -10)
    base:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -10, 10)
    frame.paperBase = base

    local plate = art:CreateTexture(nil, "ARTWORK")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(256, 64)
    plate:SetPoint("TOP", frame, "TOP", 0, 12)
    frame.headerPlate = plate

    local title = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", plate, "TOP", 0, -14)
    title:SetText("Quest Log")
    frame.plateTitle = title
    return art
end

function ApplyFraming(force)
    if not frame then return end
    local style = DB().FrameStyle or "STONE"
    if not force and frame._framedAs == style then return end
    frame._framedAs = style
    local parchment = (style == "PARCHMENT")
    local sheet = parchment or style == "STONE"

    -- The template's own dressing steps aside for the parchment -- ALL of it.
    -- This was four guessed names and three of them do not exist on this
    -- client, so the template's steel frame never went away: the parchment sat
    -- stranded behind it (the art frame is a level below, which is exactly
    -- what lets the template's Bg cover it), the title bar was doubled, and
    -- the quest text was coloured for a background nobody could see. The
    -- verified list lives in the shared framework because three windows had
    -- this same bug.
    Commander.UI.SetTemplateDressing(frame, not sheet)

    if sheet then
        EnsureSheet(style)
        frame.parchment:Show()
        frame.headerPlate:Show()
        frame.plateTitle:Show()
    elseif frame.parchment then
        frame.parchment:Hide()
        frame.headerPlate:Hide()
        frame.plateTitle:Hide()
    end
    Commander.UI.ApplyStyleBackdrop(frame, (style == "DARK") and "DARK" or "NONE")

    -- The two inset panes were built half-black, which is right over the
    -- suite's dark panels and turns paper to mud. On the sheet they take a
    -- thin wash of ink instead: enough to read as inset, not enough to darken
    -- what is written on them.
    for _, pane in ipairs({ frame.navPane, frame.detailPane }) do
        if pane and pane.SetBackdropColor then
            if parchment then
                pane:SetBackdropColor(0.30, 0.20, 0.08, 0.10)
                pane:SetBackdropBorderColor(0.50, 0.38, 0.22, 1)
            else
                pane:SetBackdropColor(0, 0, 0, 0.5)
                pane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
            end
        end
    end
    -- The toolbar strip follows the panes: the filter labels and the count on
    -- it are ink on the paper (faint 3.3:1, secondary 5.7:1 against the wash)
    if frame.toolbarBg then
        if parchment then
            frame.toolbarBg:SetVertexColor(0.30, 0.20, 0.08, 0.10)
        else
            frame.toolbarBg:SetVertexColor(0, 0, 0, 0.45)
        end
    end
end

Q.ApplyFraming = ApplyFraming

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "CommanderQuestLogFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Quest Log") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderQuestLogFrame") end

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        frame._dragging = true
        frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame._dragging = false
        SavePosition()
    end)

    -- Toolbar: filters, search, sort, and how full the log is
    local toolbar = CreateFrame("Frame", nil, frame)
    frame.toolbar = toolbar
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
    toolbar:SetHeight(TOOLBAR_H)

    -- A strip under the toolbar, tinted by ApplyFraming like the two panes:
    -- dark on the dark skins, a thin wash of ink on the paper. It was dark on
    -- every skin once (D14), when the labels were light; since D16 they are
    -- ink on the paper, and ink on a 45%-black strip over cream reads at about
    -- 1.2:1 -- the filters all but vanished.
    frame.toolbarBg = Quad(frame, "BACKGROUND")
    frame.toolbarBg:SetPoint("TOPLEFT", toolbar, "TOPLEFT", -4, 3)
    frame.toolbarBg:SetPoint("BOTTOMRIGHT", toolbar, "BOTTOMRIGHT", 4, -3)
    frame.toolbarBg:SetVertexColor(0, 0, 0, 0.45)

    frame.filters = {}
    local previous
    for _, key in ipairs(FILTER_ORDER) do
        local spec = Q.FILTERS[key]
        local button = CreateFrame("Button", nil, toolbar)
        button:SetSize(52, TOOLBAR_H)
        button:SetNormalFontObject(GameFontDisableSmall)
        button:SetHighlightFontObject(GameFontHighlightSmall)
        button:SetText(spec.label)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
        end
        if button.GetFontString then
            local fs = button:GetFontString()
            if fs then fs:SetTextColor(Ink("secondary")) end
        end
        button.underline = Quad(button, "ARTWORK")
        button.underline:SetHeight(2)
        button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 2)
        button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 2)
        button:SetScript("OnClick", function()
            DB().Filter = key
            Q.Refresh()
        end)
        Commander.UI.AttachTooltip(button, spec.label, spec.tooltip, "ANCHOR_BOTTOM")
        -- Re-ink after a hover, a frame later so it lands after the client's
        -- own font swap whichever runs first; and on paper, during it
        button:HookScript("OnLeave", function()
            if C_Timer and C_Timer.After then C_Timer.After(0, StyleLogFilters) else StyleLogFilters() end
        end)
        InkOnHover(button)
        frame.filters[key] = button
        previous = button
    end

    frame.searchBox = CreateFrame("EditBox", "CommanderQuestLogSearchBox", toolbar, "InputBoxTemplate")
    frame.searchBox:SetSize(150, 20)
    frame.searchBox:SetPoint("LEFT", previous, "RIGHT", 14, 0)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetMaxLetters(60)
    -- One box, two searches: the text typed here belongs to whichever tab is
    -- up. A tab change swaps the box's text with SetText, which this handler
    -- sees as not user input and leaves alone.
    frame.searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local text = self:GetText() or ""
        if ZoneMode() then Q.Zones.SetSearch(text) else searchText = text end
        Q.Refresh()
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        if ZoneMode() then Q.Zones.EscapeSearch() else searchText = "" end
        self:ClearFocus()
        Q.Refresh()
    end)
    frame.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local ghost = frame.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ghost:SetPoint("LEFT", frame.searchBox, "LEFT", 4, 0)
    ghost:SetText("Search quests")
    frame.searchBox:HookScript("OnTextChanged", function(self)
        ghost:SetShown((self:GetText() or "") == "")
    end)
    -- One box, two searches, two answers: the Zones tab matches names only
    -- (its headings are status groups, not zones)
    Commander.UI.AttachTooltip(frame.searchBox, "Search", function()
        if ZoneMode() then return "Matches a quest's name, in the zone on the card." end
        return "Matches a quest's name, its zone, and the text of its objectives."
    end, "ANCHOR_BOTTOM")

    frame.sortDrop = CreateFrame("Frame", "CommanderQuestLogSortDrop", toolbar, "UIDropDownMenuTemplate")
    frame.sortDrop:SetPoint("LEFT", frame.searchBox, "RIGHT", -6, -2)
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(frame.sortDrop, function()
            for _, option in ipairs(Q.SORTS) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = option.text
                info.value = option.value
                info.checked = (DB().Sort or "LOG") == option.value
                info.func = function()
                    DB().Sort = option.value
                    UIDropDownMenu_SetSelectedValue(frame.sortDrop, option.value)
                    UIDropDownMenu_SetText(frame.sortDrop, option.text)
                    Q.Refresh()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        UIDropDownMenu_SetWidth(frame.sortDrop, 118)
    end

    -- A FontString cannot carry a script, so the readout's tooltip lives on a
    -- mouse frame laid over it rather than on the text itself
    frame.countHit = CreateFrame("Frame", nil, toolbar)
    frame.countHit:SetPoint("RIGHT", toolbar, "RIGHT", -2, 0)
    frame.countHit:SetSize(110, TOOLBAR_H)
    frame.countHit:EnableMouse(true)
    frame.countFS = frame.countHit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    frame.countFS:SetPoint("RIGHT", frame.countHit, "RIGHT", 0, 0)
    Commander.UI.AttachTooltip(frame.countHit, "Quest log",
        function()
            return string.format("%d of %d quest slots used. The log will not take another quest once it is full.",
                numQuests, Q.MAX_QUESTS or 25)
        end, "ANCHOR_BOTTOM")

    frame.titleAccent = Quad(frame, "ARTWORK")
    frame.titleAccent:SetHeight(1)
    frame.titleAccent:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    frame.titleAccent:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)

    -- The navigator
    local navPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.navPane = navPane
    navPane:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
    navPane:SetWidth(NAV_W)
    -- Its bottom edge depends on whether the reset footer is under it, so it
    -- is anchored by AnchorNavPane and re-anchored when the setting changes
    if navPane.SetBackdrop then
        navPane:SetBackdrop(INSET_BACKDROP)
        navPane:SetBackdropColor(0, 0, 0, 0.5)
        navPane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
    end

    navScroll = CreateFrame("ScrollFrame", "CommanderQuestLogNavScroll", navPane, "UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT", navPane, "TOPLEFT", 6, -6)
    navScroll:SetPoint("BOTTOMRIGHT", navPane, "BOTTOMRIGHT", -16, 6)
    navScroll:EnableMouseWheel(true)
    navScroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 40
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)
    navChild = CreateFrame("Frame", nil, navScroll)
    navChild:SetSize(NAV_W - 34, 1)
    navScroll:SetScrollChild(navChild)
    navScroll:SetScript("OnSizeChanged", function(_, width) navChild:SetWidth(width) end)

    -- The briefing
    local detailPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.detailPane = detailPane
    -- Hung off the toolbar, not off the navigator's top right: on the Zones
    -- tab the navigator moves down under the zone card, and the briefing
    -- keeps its full height. On the Log the two anchors are the same place.
    detailPane:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", NAV_W + 8, -8)
    detailPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 4 + ACTIONS_H + 4)
    if detailPane.SetBackdrop then
        detailPane:SetBackdrop(INSET_BACKDROP)
        detailPane:SetBackdropColor(0, 0, 0, 0.5)
        detailPane:SetBackdropBorderColor(0.45, 0.4, 0.32, 1)
    end

    detailScroll = CreateFrame("ScrollFrame", "CommanderQuestLogDetailScroll", detailPane, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailPane, "TOPLEFT", 6, -6)
    detailScroll:SetPoint("BOTTOMRIGHT", detailPane, "BOTTOMRIGHT", -16, 6)
    detailScroll:EnableMouseWheel(true)
    detailScroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 40
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)
    detailChild = CreateFrame("Frame", nil, detailScroll)
    detailChild:SetSize(DetailWidth(), 1)
    detailScroll:SetScrollChild(detailChild)
    detailScroll:SetScript("OnSizeChanged", function(_, width) detailChild:SetWidth(width) end)

    -- The action bar, under the briefing and never inside it: the buttons
    -- must not scroll away from the quest they act on
    Commander.UI.SlimScrollBar("CommanderQuestLogNavScroll", 2, 2)
    Commander.UI.SlimScrollBar("CommanderQuestLogDetailScroll", 2, 2)

    local actions = CreateFrame("Frame", nil, frame)
    frame.actions = actions
    actions:SetPoint("TOPLEFT", detailPane, "BOTTOMLEFT", 0, -4)
    actions:SetPoint("TOPRIGHT", detailPane, "BOTTOMRIGHT", 0, -4)
    actions:SetHeight(ACTIONS_H)

    local function ActionButton(name, label, width, tooltip, handler)
        local button = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(label)
        button:SetScript("OnClick", handler)
        Commander.UI.AttachTooltip(button, label, tooltip, "ANCHOR_TOP")
        frame[name] = button
        return button
    end

    ActionButton("trackBtn", "Track", 72,
        "Put this quest on the objective tracker, or take it off. Right-clicking a row in the list does the same.",
        function() Q.ToggleTrack() end)
    frame.trackBtn:SetPoint("LEFT", actions, "LEFT", 0, 0)

    ActionButton("shareBtn", "Share", 72,
        "Offer this quest to your party. Greyed out for a quest the game will not let you share.",
        function() Q.Share() end)
    frame.shareBtn:SetPoint("LEFT", frame.trackBtn, "RIGHT", 4, 0)

    ActionButton("announceBtn", "Announce", 88,
        "Post this quest and its remaining objectives to your group. Shift-clicking a row in the list does the same.",
        function() Q.Announce() end)
    frame.announceBtn:SetPoint("LEFT", frame.shareBtn, "RIGHT", 4, 0)

    ActionButton("waypointBtn", "Waypoint", 80,
        function()
            return "Set a waypoint to where this quest is handed in. Needs Questie, which knows where the quest giver stands; greyed out without it. Goes to "
                .. WaypointWhere() .. "."
        end,
        function() Q.LogWaypoint() end)
    frame.waypointBtn:SetPoint("LEFT", frame.announceBtn, "RIGHT", 4, 0)

    ActionButton("abandonBtn", "Abandon", 82,
        "Drop this quest. Asks first unless you have turned the confirmation off.",
        function() Q.Abandon() end)
    frame.abandonBtn:SetPoint("RIGHT", actions, "RIGHT", 0, 0)

    -- The reset footer, under the navigator and level with the action bar:
    -- the daily clock on the left, the weekly clock on the right. Two mouse
    -- frames because a FontString cannot carry a tooltip, and two rather
    -- than one because each clock says something different on hover.
    local resets = CreateFrame("Frame", nil, frame)
    frame.resets = resets
    resets:SetPoint("TOPLEFT", navPane, "BOTTOMLEFT", 0, -4)
    resets:SetPoint("TOPRIGHT", navPane, "BOTTOMRIGHT", 0, -4)
    resets:SetHeight(ACTIONS_H)

    local function ResetSegment(name, side, label)
        local hit = CreateFrame("Frame", nil, resets)
        hit:SetHeight(ACTIONS_H)
        hit:SetWidth(math.floor(NAV_W / 2))
        hit:SetPoint(side, resets, side, 0, 0)
        hit:EnableMouse(true)
        hit.label = hit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        hit.label:SetPoint("LEFT", hit, "LEFT", side == "LEFT" and 4 or 8, 0)
        hit.label:SetText(label)
        hit.value = hit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        hit.value:SetPoint("LEFT", hit.label, "RIGHT", 5, 0)
        hit.value:SetJustifyH("LEFT")
        hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame[name] = hit
        return hit
    end
    ResetSegment("resetDaily", "LEFT", "Dailies")
    ResetSegment("resetWeekly", "RIGHT", "Weekly")
    frame.resetDaily:SetScript("OnEnter", function(self) Q.ResetTooltip(self, "daily") end)
    frame.resetWeekly:SetScript("OnEnter", function(self) Q.ResetTooltip(self, "weekly") end)

    -- One tick a second while the window is up. The footer is a child of the
    -- window, so a hidden window stops the clock for free.
    resets._elapsed = 0
    resets:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = self._elapsed + (elapsed or 0)
        if self._elapsed < 1 then return end
        self._elapsed = 0
        Q.UpdateResets()
    end)
    AnchorNavPane()

    -- Scale grip, matching the shared window chrome's
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 25)
    grip.tex = grip:CreateTexture(nil, "ARTWORK")
    grip.tex:SetAllPoints()
    grip.tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function()
        frame._dragging = true
        local startX, startY = GetCursorPosition()
        local startScale = DB().FrameScale or 1
        local uiScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        grip:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local delta = ((x - startX) - (y - startY)) / 2 / uiScale
            local newScale = math.max(0.6, math.min(1.6, startScale + delta / 160))
            DB().FrameScale = math.floor(newScale * 100 + 0.5) / 100
            frame:SetScale(DB().FrameScale)
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        frame._dragging = false
        SavePosition()
        Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    end)
    Commander.UI.AttachTooltip(grip, "Resize", "Drag to resize the window.", "ANCHOR_LEFT")

    -- The Log / Zones tabs, in the title band's free top left. Zones builds
    -- them (and everything else of its own) so this file need not know them.
    if Q.Zones and Q.Zones.EnsureTabs then Q.Zones.EnsureTabs(frame) end

    frame:SetScript("OnShow", function()
        ApplyFraming(true)
        Q.ApplyPosition()
        -- A Restore Defaults made while the window was shut may have put the
        -- reset footer back; the navigator's anchors follow it here
        AnchorNavPane()
        -- The lockout list is what the client last heard; ask for it fresh so
        -- the weekly tooltip is not a login-old answer
        if RequestRaidInfo then RequestRaidInfo() end
        if UIDropDownMenu_SetSelectedValue then
            local sort = DB().Sort or "LOG"
            UIDropDownMenu_SetSelectedValue(frame.sortDrop, sort)
            for _, option in ipairs(Q.SORTS) do
                if option.value == sort then
                    UIDropDownMenu_SetText(frame.sortDrop, option.text)
                end
            end
        end
        Q.Refresh()
    end)
    frame:SetScript("OnHide", function()
        -- The window took the log selection while it was up; a closed window
        -- has no business holding it
        if selectedEntry and SelectQuestLogEntry and GetQuestLogSelection then
            SelectQuestLogEntry(0)
        end
    end)

    ApplyFraming(true)
    Q.ApplyPosition()
    return frame
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

function CommanderQuestLog_Show()
    if not Enabled() then
        print("Commander Quest Log: the module is switched off in its settings.")
        return
    end
    EnsureFrame()
    frame:Show()
    -- Never take keyboard focus on open: the window is opened with a key, and
    -- an autofocused search box turns WASD into typing (the trap Vault paid
    -- for at the banker)
    if frame.searchBox then frame.searchBox:ClearFocus() end
end

function CommanderQuestLog_Hide()
    if frame then frame:Hide() end
end

function CommanderQuestLog_Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        CommanderQuestLog_Show()
    end
end

function CommanderQuestLog_FocusSearch()
    CommanderQuestLog_Show()
    if frame and frame.searchBox then frame.searchBox:SetFocus() end
end

Q.Toggle = CommanderQuestLog_Toggle
Q.Show = CommanderQuestLog_Show

-- The quest currently briefed, or nil
function Q.Selected() return selectedEntry end

-- Drawn state, for the harness. Nothing in the game reads these; they exist
-- so a check can ask what the window actually PUT ON SCREEN rather than
-- trusting that the layout pass ran.
function Q._NavRows() return navRows end
function Q._DetailStrings()
    local out = {}
    for _, pool in pairs(detailBlocks) do
        for _, block in ipairs(pool) do out[#out + 1] = block end
    end
    return out
end

-- Point the ledger at a quest by name (or by the model's own key). Returns
-- whether it found one; a quest hidden by the current filter is selected all
-- the same and the refresh re-picks, which is the honest outcome.
function Q.Select(titleOrKey)
    if #entries == 0 then entries, numQuests = Q.Scan() end
    for _, entry in ipairs(entries) do
        if not entry.isHeader and (entry.key == titleOrKey or entry.title == titleOrKey) then
            selectedKey = entry.key
            Q.Refresh()
            return true
        end
    end
    return false
end

-- Open the window with a named quest selected, for other modules and for the
-- takeover path (a quest link, an objective tracker click). A quest in the
-- log is a Log question, so it lands on the Log whichever tab was up.
--
-- It refreshes whatever the index turns out to be. Show() on a window that is
-- already up fires no OnShow, so a header or a stale index used to leave the
-- Zones tab's widgets drawn under a Log ViewMode until the next event.
function CommanderQuestLog_OpenToQuest(index)
    if DB().ViewMode == "ZONE" then DB().ViewMode = "LOG" end
    CommanderQuestLog_Show()
    if index and GetQuestLogTitle then
        local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
        if title and not isHeader then
            selectedKey = Q.KeyFor({ questID = questID, title = title })
            -- ...and its row in view, not wherever the list was scrolled
            revealSelection = true
        end
    end
    Q.Refresh()
end

-- ---------------------------------------------------------------------------
-- The two tabs
-- ---------------------------------------------------------------------------

-- "LOG" or "ZONE". Only the setting moves here; the next refresh re-anchors
-- the navigator and swaps the search box's text (see Q.Refresh).
local function SwitchMode(mode)
    local db = DB()
    if mode == "ZONE" and not (Q.Zones and db.ShowZoneTab ~= false) then mode = "LOG" end
    db.ViewMode = mode
end

function Q.SetViewMode(mode)
    SwitchMode(mode)
    Q.Refresh()
end

-- The Log on a quest asked for by name (the Zones tab's Open in Log), whatever
-- the Log's own fold, filter or search was hiding: the search is cleared, the
-- filter opened when it would hide the quest, and its zone unfolded, so the
-- re-pick in Q.Refresh (D6) finds it on screen instead of briefing the first
-- row, or nothing. The Log's side of D31.
function Q.RevealInLog(key)
    local db = DB()
    if #entries == 0 then entries, numQuests = Q.Scan() end
    for _, entry in ipairs(entries) do
        if not entry.isHeader and entry.key == key then
            searchText = ""
            if frame and frame.searchBox then frame.searchBox:SetText("") end
            if type(db.Collapsed) == "table" and entry.header then db.Collapsed[entry.header] = nil end
            local filter = db.Filter or "ALL"
            if (filter == "ACTIVE" and entry.isComplete) or (filter == "COMPLETE" and not entry.isComplete)
                or (filter == "TRACKED" and not entry.watched) then
                db.Filter = "ALL"
            end
            break
        end
    end
    SwitchMode("LOG")
    -- The row brought into view too: the quest may sit far below the fold
    revealSelection = true
    local found = Q.Select(key)
    if not found then revealSelection = false end
    return found
end

function Q.ViewMode()
    return ZoneMode() and "ZONE" or "LOG"
end

-- The Zones tab on a zone, for the map drawer and /cql zone. areaId is
-- Questie's AREA id (not a uiMapID); nil follows the zone the player stands
-- in. questId, when given, is selected and brought into view.
function CommanderQuestLog_OpenToZone(areaId, questId)
    if not Enabled() then
        print("Commander Quest Log: the module is switched off in its settings.")
        return
    end
    local zones = Q.Zones
    if not (zones and zones.PrepareOpen and zones.PrepareOpen(areaId, questId)) then
        CommanderQuestLog_Show()
        return
    end
    SwitchMode("ZONE")
    if frame and frame:IsShown() then
        Q.Refresh()
    else
        CommanderQuestLog_Show()
    end
end

-- ---------------------------------------------------------------------------
-- Taking over the stock quest log
--
-- Two doors, both needed. Replacing ToggleQuestLog catches the key binding
-- and the micro button; hooking the frame's OnShow catches every other path
-- (QuestLog_OpenToQuest, a quest link, another addon). Neither is a one-way
-- door: both consult the setting live, so turning the takeover off hands
-- Blizzard's window straight back with no reload.
-- ---------------------------------------------------------------------------

local function TakingOver()
    return Enabled() and DB().TakeOverQuestLog ~= false
end

local function InstallTakeover()
    if Q._takeoverInstalled then return end
    Q._takeoverInstalled = true

    local blizzardToggle = ToggleQuestLog
    ToggleQuestLog = function(...)
        if TakingOver() then
            CommanderQuestLog_Toggle()
            return
        end
        if blizzardToggle then return blizzardToggle(...) end
    end

    if QuestLogFrame and QuestLogFrame.HookScript then
        QuestLogFrame:HookScript("OnShow", function(self)
            if not TakingOver() then return end
            if HideUIPanel then HideUIPanel(self) else self:Hide() end
            local selection = GetQuestLogSelection and GetQuestLogSelection() or nil
            if selection and selection > 0 then
                CommanderQuestLog_OpenToQuest(selection)
            else
                CommanderQuestLog_Show()
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_UPDATE")
events:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("PLAYER_LEVEL_UP")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InstallTakeover()
        -- The adapter also starts itself at login; asking twice is harmless
        if Q.Questie and Q.Questie.Init then Q.Questie.Init() end
        Commander.AddListener(COMMANDER_QUESTLOG_EVENTS.UPDATE, function()
            if frame and frame:IsShown() then
                ApplyFraming(true)
                Q.ApplyPosition()
                -- Restore Defaults rewrites ShowResetTimers without going
                -- through the checkbox's setter, so the footer and the
                -- navigator's bottom edge are put right here too
                AnchorNavPane()
                Q.Refresh()
            end
        end)
        return
    end
    if event == "QUEST_LOG_UPDATE" and Q.IsExpanding() then
        -- Our own ExpandQuestHeader provoked this. Re-entering the scan here
        -- is a loop, not an update.
        return
    end
    QueueRefresh()
end)

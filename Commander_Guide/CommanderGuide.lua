-- Commander Guide — runtime
--
-- The client's events in; the voice, the banner and the window out. All the
-- deciding is in CommanderGuideEngine.lua; this file only translates:
-- combat-log rows into the engine's plain events, the engine's lines into
-- C_VoiceChat.SpeakText and a banner, and a boss page into fontstrings.
--
-- Since 1.1.0 it also gets you to the raid (DECISIONS D11): "Waypoint to
-- Entrance" hands Commander Orders the raid's door. Orders is optional and is
-- looked up when the button is pressed, never captured at load, so the guide
-- works the same with Orders absent (it prints the /way line instead) or
-- switched off (it says so and prints the line). Nothing here holds a
-- waypoint of its own: Orders owns the record under (source "Guide",
-- key "entrance:<raid>"), so pressing it twice moves one waypoint, never
-- stacks two.

local D = CommanderGuide_Data
local E = CommanderGuide_Engine
local UI = Commander and Commander.UI

BINDING_HEADER_COMMANDERGUIDE = "Commander Guide"
BINDING_NAME_COMMANDERGUIDE_TOGGLE = "Open the Guide"
BINDING_NAME_COMMANDERGUIDE_BRIEF = "Read the brief for the boss in front of you"
BINDING_NAME_COMMANDERGUIDE_STOP = "Stop the voice"
BINDING_NAME_COMMANDERGUIDE_ENTRANCE = "Waypoint to the raid's entrance"

local db
local ctx
local playerGUID
local inRaidMap = false
local currentRaid          -- the raid whose map we stand in, if any
local targetBoss           -- the boss we last targeted out of combat
local briefedAt = {}       -- boss -> GetTime() of the last spoken brief
local healthAt = {}        -- npc -> last UNIT_HEALTH we fed

local function DB() return db or CommanderGuideDB or {} end
local function Enabled() return DB().Enable ~= false end
local function VoiceOn() return Enabled() and DB().Voice ~= false end

-- ---------------------------------------------------------------------------
-- suite tint (the TopBar pattern; Console optional)
-- ---------------------------------------------------------------------------

local FALLBACK_COLORS = { STEEL = { r = 0.62, g = 0.72, b = 0.85 } }
local function ConsoleTint()
    local key = (CommanderConsoleDB and CommanderConsoleDB.ConsoleColor) or "STEEL"
    if key == "CLASS" then
        local _, class = UnitClass("player")
        local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
    end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then return color.r, color.g, color.b end
    end
    local f = FALLBACK_COLORS[key] or FALLBACK_COLORS.STEEL
    return f.r, f.g, f.b
end

-- ---------------------------------------------------------------------------
-- the voice
-- ---------------------------------------------------------------------------

local speaking = false
local speakingUntil = 0
local Pump -- forward

local function CanSpeak()
    return C_VoiceChat ~= nil and type(C_VoiceChat.SpeakText) == "function"
end

-- The voice to use: the chosen one if the client still has it, else the
-- Standard voice from Blizzard's own TTS options, else the first voice.
local function VoiceID()
    local chosen = DB().VoiceID
    local voices
    local ok, list = pcall(function() return C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices() end)
    if ok and type(list) == "table" then voices = list end
    if type(chosen) == "number" then
        if not voices then return chosen end
        for _, v in ipairs(voices) do if v.voiceID == chosen then return chosen end end
    end
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
        local ok2, id = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Standard)
        if ok2 and type(id) == "number" then
            if not voices then return id end
            for _, v in ipairs(voices) do if v.voiceID == id then return id end end
        end
    end
    if voices and voices[1] and voices[1].voiceID ~= nil then return voices[1].voiceID end
    return 0
end

local function StopSpeaking()
    if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
    speaking = false
    speakingUntil = 0
end

local function SayNow(text)
    if not (VoiceOn() and CanSpeak()) then return false end
    local rate = tonumber(DB().Rate) or 0
    local volume = tonumber(DB().Volume) or 100
    local ok = pcall(C_VoiceChat.SpeakText, VoiceID(), text, rate, volume, false)
    if not ok then return false end
    local seconds = E.Estimate(text, rate) + 1
    speaking = true
    speakingUntil = GetTime() + seconds
    -- the playback-finished event advances the queue; this is the net under
    -- it for a voice that never reports back (ASSUMPTIONS A5)
    if C_Timer and C_Timer.After then
        local mine = speakingUntil
        C_Timer.After(seconds, function()
            if speaking and speakingUntil == mine then
                speaking = false
                Pump()
            end
        end)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- the banner
-- ---------------------------------------------------------------------------

local banner

local function EnsureBanner()
    if banner then return banner end
    banner = CreateFrame("Frame", "CommanderGuideBanner", UIParent)
    banner:SetSize(640, 44)
    banner:SetFrameStrata("HIGH")
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    banner.text:SetPoint("CENTER", banner, "CENTER", 0, 0)
    banner.text:SetWidth(620)
    banner.text:SetJustifyH("CENTER")
    banner.shownAt = nil
    banner:SetScript("OnUpdate", function(self)
        if not self.shownAt then return end
        local hold = tonumber(DB().BannerSeconds) or 4
        local age = GetTime() - self.shownAt
        if age >= hold then
            self.shownAt = nil
            self.text:SetText("")
            self.text:SetAlpha(1)
            if not (UI and UI.HudUnlocked and UI.HudUnlocked(DB(), "Banner")) then self:Hide() end
        elseif age > hold - 0.8 then
            self.text:SetAlpha((hold - age) / 0.8)
        else
            self.text:SetAlpha(1)
        end
    end)
    banner:Hide()
    return banner
end

local function ApplyBanner()
    local b = EnsureBanner()
    local font = b.text:GetFont()
    local size = tonumber(DB().BannerSize) or 20
    if font then b.text:SetFont(font, size, "OUTLINE") end
    local r, g, bl = ConsoleTint()
    b.text:SetTextColor(math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, bl + 0.25))
    if UI and UI.ApplyHudChrome then
        UI.ApplyHudChrome(b, DB(), "Banner", { defaultPoint = { point = "CENTER", x = 0, y = 220 }, title = "Guide" })
    end
    if UI and UI.HudUnlocked and UI.HudUnlocked(DB(), "Banner") then
        b.text:SetText("Garrote on you. Heal yourself between casts.")
        b.text:SetAlpha(1)
        b:Show()
    elseif not b.shownAt then
        b.text:SetText("")
        b:Hide()
    end
end

local function ShowBanner(text)
    if not (Enabled() and DB().Banner ~= false) then return end
    local b = EnsureBanner()
    b.text:SetText(text or "")
    b.text:SetAlpha(1)
    b.shownAt = GetTime()
    b:Show()
end

-- ---------------------------------------------------------------------------
-- delivery: engine lines -> banner, chat, voice
-- ---------------------------------------------------------------------------

local function Present(item)
    ShowBanner(item.text)
    if DB().Chat then print("|cff9ecbffGuide:|r " .. tostring(item.text)) end
    SayNow(item.say)
end

function Pump()
    if speaking or not ctx then return end
    local item = E.Next(ctx, GetTime())
    if item then Present(item) end
end

local function Deliver(items)
    if not ctx or not items or #items == 0 or not Enabled() then return end
    local interrupt = E.Enqueue(ctx, items, GetTime())
    if interrupt and DB().Interrupt ~= false and speaking then StopSpeaking() end
    Pump()
end

-- ---------------------------------------------------------------------------
-- briefs
-- ---------------------------------------------------------------------------

local selectedBoss -- the window's page
local ShowBoss      -- forward

local function BossInFront()
    if ctx and ctx.boss then return ctx.boss end
    if UnitExists and UnitExists("target") then
        local boss = E.BossForNpc(D, E.NpcFromGUID(UnitGUID("target")))
        if boss then return boss end
    end
    if targetBoss then return targetBoss end
    if selectedBoss then return selectedBoss end
    if currentRaid and currentRaid.bosses[1] then return currentRaid.bosses[1] end
    return nil
end

local function SpeakBrief(boss, force)
    if not boss then return false end
    local role = DB().Role or "HEALER"
    local text = E.Brief(boss, role, { full = DB().BriefFull })
    if not text then return false end
    if not force then
        local last = briefedAt[boss]
        if last and (GetTime() - last) < (tonumber(DB().BriefRepeat) or 180) then return false end
    end
    briefedAt[boss] = GetTime()
    if ctx then E.Clear(ctx) end
    StopSpeaking()
    ShowBanner(boss.title .. ": " .. (E.Role(boss, role) and E.Role(boss, role).oneLiner or ""))
    return SayNow(text)
end

-- ---------------------------------------------------------------------------
-- the window
-- ---------------------------------------------------------------------------

local frame
local FRAME_W, FRAME_H, LIST_W, PAD = 840, 580, 210, 10
local KIND_COLOR = {
    MAGIC = { 0.35, 0.65, 1 }, CURSE = { 0.7, 0.4, 1 }, POISON = { 0.4, 0.85, 0.3 },
    DISEASE = { 0.75, 0.55, 0.25 }, BLEED = { 0.95, 0.35, 0.35 }, STUN = { 0.95, 0.8, 0.3 },
    SILENCE = { 0.95, 0.8, 0.3 }, FEAR = { 0.95, 0.6, 0.2 }, NONE = { 0.6, 0.6, 0.6 },
}

local function SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok and n then return n end
    end
    if GetSpellInfo then
        local n = GetSpellInfo(id)
        if n then return n end
    end
    return nil
end

local function SpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok and t then return t end
    end
    if GetSpellTexture then return GetSpellTexture(id) end
    return nil
end

local function SavePosition()
    if not frame then return end
    local point, _, _, x, y = frame:GetPoint(1)
    if point then DB().WindowPos = { point = point, x = x, y = y } end
end

local function RestorePosition()
    frame:ClearAllPoints()
    local pos = DB().WindowPos
    if type(pos) == "table" and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

-- pooled page widgets
local function Pool(parent, make)
    local items, used = {}, 0
    return {
        take = function()
            used = used + 1
            local it = items[used]
            if not it then it = make(parent); items[used] = it end
            it:Show()
            return it
        end,
        reset = function()
            for i = used + 1, #items do items[i]:Hide() end
            used = 0
        end,
        trim = function()
            for i = used + 1, #items do items[i]:Hide() end
        end,
    }
end

local function RenderPage(boss)
    if not frame then return end
    local content = frame.content
    local role = DB().Role or "HEALER"
    local page = E.Page(boss, role)
    frame.strings.reset()
    frame.icons.reset()
    local width = content:GetWidth()
    if not width or width < 100 then width = FRAME_W - LIST_W - PAD * 4 - 24 end
    local y = -PAD
    local r, g, b = ConsoleTint()

    local function Line(text, template, indent, color)
        local fs = frame.strings.take()
        fs:SetFontObject(template or "GameFontHighlight")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + (indent or 0), y)
        fs:SetWidth(width - PAD * 2 - (indent or 0))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(text or "")
        if color then fs:SetTextColor(color[1], color[2], color[3]) else fs:SetTextColor(1, 1, 1) end
        local h = fs:GetStringHeight()
        if not h or h == 0 then h = 14 end
        y = y - h - 4
        return fs
    end
    local function Header(text)
        y = y - 8
        local fs = Line(text, "GameFontNormalLarge", 0, { r, g, b })
        return fs
    end

    frame.title:SetText(boss.title)
    frame.subtitle:SetText((boss.raid and boss.raid.title or "") .. "  |  " .. (E.Role(boss, role) and (role:sub(1, 1) .. role:sub(2):lower()) or role) .. "'s seat")

    if not page then
        Line("No page for this seat yet.", "GameFontDisable")
    else
        for _, section in ipairs(page) do
            Header(section.title)
            if section.kind == "lead" then
                Line(section.text, "GameFontHighlightLarge")
            elseif section.kind == "bullets" then
                for _, l in ipairs(section.lines) do Line("\226\128\162  " .. l, "GameFontHighlight", 6) end
            elseif section.kind == "phases" then
                for _, phase in ipairs(section.phases) do
                    Line(phase.title, "GameFontNormal", 6, { 1, 0.85, 0.45 })
                    for _, l in ipairs(phase.lines or {}) do Line("\226\128\162  " .. l, "GameFontHighlight", 18) end
                end
            elseif section.kind == "watch" then
                for _, row in ipairs(section.rows) do
                    local icon = frame.icons.take()
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 6, y)
                    icon:SetTexture(SpellIcon(row.spell) or "Interface\\Icons\\INV_Misc_QuestionMark")
                    local kindLabel = E.KIND_LABEL[row.kind or "NONE"] or ""
                    local c = KIND_COLOR[row.kind or "NONE"] or KIND_COLOR.NONE
                    local head = row.name
                    if kindLabel ~= "" then
                        head = ("%s  |cff%02x%02x%02x%s|r"):format(row.name, c[1] * 255, c[2] * 255, c[3] * 255, kindLabel)
                    end
                    Line(head, "GameFontNormal", 34)
                    Line(row.note or "", "GameFontHighlightSmall", 34, { 0.85, 0.85, 0.85 })
                    y = y - 2
                end
            elseif section.kind == "callouts" then
                for _, c in ipairs(section.rows) do
                    if c.spell and not c.spellName then c.spellName = SpellName(c.spell) end
                    Line(E.When(c), "GameFontHighlightSmall", 6, { 0.6, 0.7, 0.8 })
                    Line("\"" .. E.Format(c.say, nil) .. "\"", "GameFontHighlight", 18)
                    if c.sayMe then Line("on you: \"" .. c.sayMe .. "\"", "GameFontHighlight", 18, { 1, 0.85, 0.45 }) end
                end
            end
        end
    end
    frame.strings.trim()
    frame.icons.trim()
    content:SetHeight(math.max(-y + PAD, 10))
    frame.scroll:SetVerticalScroll(0)
end

-- ---------------------------------------------------------------------------
-- the way in (DECISIONS D11)
-- ---------------------------------------------------------------------------

-- The raid the window is about: the page's, else the one we stand in, else
-- the first one written
local function PageRaid()
    return (selectedBoss and selectedBoss.raid) or currentRaid or D.RAIDS[1]
end

local function RaidByKey(key)
    for _, raid in ipairs(D.RAIDS) do
        if raid.key == key then return raid end
    end
    return nil
end

-- Inside, the door is behind you and the arrow has no position to work with
local function InsideRaid(raid)
    return inRaidMap and raid ~= nil and currentRaid == raid
end

-- Commander Orders when it is loaded. Looked up per call: OptionalDeps only
-- orders the loading, and a table captured at load would miss a later one.
local function Orders()
    local O = CommanderOrders
    if type(O) == "table" and type(O.Add) == "function" then return O end
    return nil
end

-- The door as an Add spec: Orders' own entrance resolvers first (asked for
-- the raid's uiMap), then the table in the data file
local function EntranceFor(raid)
    if not raid then return nil end
    local row = D.ENTRANCES and D.ENTRANCES[raid.instanceMapID]
    local O = Orders()
    local resolved
    if O and type(O.Entrance) == "function" and row and row.raidMap then
        local ok, e = pcall(O.Entrance, row.raidMap)
        if ok then resolved = e end
    end
    return E.EntranceSpec(D, raid, resolved)
end

-- Orders' refusal reasons, in words
local REFUSED = {
    disabled = "Commander Orders is switched off",
    loading = "Commander Orders is still loading",
}

local function EntranceTooltip()
    local raid = PageRaid()
    if not raid then return "No raid to go to." end
    if InsideRaid(raid) then return "You are inside " .. raid.title .. ": the door is behind you." end
    local row = D.ENTRANCES and D.ENTRANCES[raid.instanceMapID]
    local where = (row and row.zone) and (" in " .. row.zone) or ""
    local O = Orders()
    if not O then
        return "Commander Orders is not loaded, so this prints the /way line for "
            .. raid.title .. "'s entrance" .. where .. " instead."
    end
    local ok, arrow = pcall(function() return O.Describe and O.Describe() end)
    arrow = (ok and type(arrow) == "string") and arrow or "Commander Orders arrow"
    return "Points the " .. arrow .. " at " .. raid.title .. "'s entrance" .. where
        .. ". Pressing it again moves the same waypoint; it clears itself when you arrive."
end

local function RenderList()
    if not frame then return end
    local raid = (selectedBoss and selectedBoss.raid) or currentRaid or D.RAIDS[1]
    frame.raidTitle:SetText(raid and raid.title or "")
    for i, btn in ipairs(frame.bossButtons) do
        local boss = raid and raid.bosses[i]
        if boss then
            btn.boss = boss
            btn.label:SetText(("%d.  %s"):format(i, boss.title))
            btn.selected:SetShown(boss == selectedBoss)
            btn:Show()
        else
            btn.boss = nil
            btn:Hide()
        end
    end
    if frame.entrance then frame.entrance:SetEnabled(raid ~= nil and not InsideRaid(raid)) end
end

function ShowBoss(boss)
    if not boss then return end
    selectedBoss = boss
    if frame then
        RenderList()
        RenderPage(boss)
    end
end

local function MakeBossButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(24)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -28 - (index - 1) * 25)
    btn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -28 - (index - 1) * 25)
    btn.selected = btn:CreateTexture(nil, "BACKGROUND")
    btn.selected:SetAllPoints()
    btn.selected:SetColorTexture(1, 1, 1, 0.12)
    btn.selected:Hide()
    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.label:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
    btn.label:SetJustifyH("LEFT")
    btn:SetScript("OnClick", function(self) if self.boss then ShowBoss(self.boss) end end)
    return btn
end

local function EnsureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "CommanderGuideFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Guide") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderGuideFrame") end
    RestorePosition()

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); SavePosition() end)

    -- left: the raid's bosses
    local list = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
    list:SetWidth(LIST_W)
    frame.list = list
    frame.raidTitle = list:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.raidTitle:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -4)
    frame.bossButtons = {}
    for i = 1, 16 do frame.bossButtons[i] = MakeBossButton(list, i) end
    -- The way in sits under the boss list: it is the raid's, not a boss's
    local entrance = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    entrance:SetHeight(22)
    entrance:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 4, 4)
    entrance:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)
    entrance:SetText("Waypoint to Entrance")
    entrance:SetScript("OnClick", function() CommanderGuide_Entrance() end)
    if UI and UI.AttachTooltip then UI.AttachTooltip(entrance, "Waypoint to Entrance", EntranceTooltip) end
    frame.entrance = entrance

    -- right: toolbar + page
    local tb = CreateFrame("Frame", nil, frame)
    tb:SetPoint("TOPLEFT", list, "TOPRIGHT", PAD, 0)
    tb:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
    tb:SetHeight(44)
    frame.title = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.title:SetPoint("TOPLEFT", tb, "TOPLEFT", 4, -2)
    frame.subtitle = tb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 1, -2)
    frame.subtitle:SetTextColor(0.7, 0.75, 0.8)

    local stop = CreateFrame("Button", nil, tb, "UIPanelButtonTemplate")
    stop:SetSize(64, 22)
    stop:SetPoint("TOPRIGHT", tb, "TOPRIGHT", 0, -4)
    stop:SetText("Stop")
    stop:SetScript("OnClick", function() CommanderGuide_Stop() end)
    local brief = CreateFrame("Button", nil, tb, "UIPanelButtonTemplate")
    brief:SetSize(104, 22)
    brief:SetPoint("RIGHT", stop, "LEFT", -4, 0)
    brief:SetText("Read Brief")
    brief:SetScript("OnClick", function() if selectedBoss then SpeakBrief(selectedBoss, true) end end)
    frame.briefButton = brief
    local voice = CreateFrame("CheckButton", nil, tb, "UICheckButtonTemplate")
    voice:SetSize(24, 24)
    voice:SetPoint("RIGHT", brief, "LEFT", -64, 0)
    voice.label = voice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    voice.label:SetPoint("LEFT", voice, "RIGHT", 2, 0)
    voice.label:SetText("Voice")
    voice:SetScript("OnClick", function(self)
        DB().Voice = self:GetChecked() and true or false
        if not DB().Voice then StopSpeaking() end
        if Commander and Commander.Notify then Commander.Notify(COMMANDER_GUIDE_EVENTS.UPDATE) end
    end)
    frame.voiceCheck = voice
    if UI and UI.AttachTooltip then
        UI.AttachTooltip(brief, "Read Brief", "Read this boss's page out loud: the one line and your job. Tick 'Brief includes the phases' in settings for the long version.")
        UI.AttachTooltip(stop, "Stop", "Cut the voice off and drop anything queued.")
        UI.AttachTooltip(voice, "Voice", "Speak callouts and briefs.")
    end

    local scroll = CreateFrame("ScrollFrame", "CommanderGuidePageScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", tb, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 22, PAD)
    frame.scroll = scroll
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(FRAME_W - LIST_W - PAD * 4 - 22, 10)
    scroll:SetScrollChild(content)
    frame.content = content
    scroll:SetScript("OnSizeChanged", function(self, w)
        if w and w > 0 then content:SetWidth(w) end
        if selectedBoss then RenderPage(selectedBoss) end
    end)
    if UI and UI.SlimScrollBar then UI.SlimScrollBar("CommanderGuidePageScroll", 2, 2) end

    frame.strings = Pool(content, function(p) return p:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end)
    frame.icons = Pool(content, function(p)
        local t = p:CreateTexture(nil, "ARTWORK")
        t:SetSize(24, 24)
        if t.SetTexCoord then t:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
        return t
    end)

    frame:SetScript("OnShow", function()
        frame.voiceCheck:SetChecked(DB().Voice ~= false)
        if not selectedBoss then selectedBoss = BossInFront() or (D.RAIDS[1] and D.RAIDS[1].bosses[1]) end
        RenderList()
        if selectedBoss then RenderPage(selectedBoss) end
    end)
    return frame
end

-- ---------------------------------------------------------------------------
-- public
-- ---------------------------------------------------------------------------

function CommanderGuide_Toggle()
    if not Enabled() then print("Commander Guide is disabled in its settings") return end
    local f = EnsureFrame()
    if f:IsShown() then f:Hide() return end
    local boss = BossInFront()
    if boss then selectedBoss = boss end
    f:Show()
end

function CommanderGuide_Show(raidKey, bossKey)
    local boss = E.BossByKey(D, raidKey, bossKey)
    if not boss then return false end
    EnsureFrame()
    ShowBoss(boss)
    frame:Show()
    return true
end

function CommanderGuide_Brief()
    if not Enabled() then return false end
    local boss = BossInFront()
    if not boss then print("Commander Guide: target a boss, or open the guide and pick one") return false end
    if not CanSpeak() then print("Commander Guide: this client has no text-to-speech") return false end
    return SpeakBrief(boss, true)
end

function CommanderGuide_Stop()
    if ctx then E.Clear(ctx) end
    StopSpeaking()
    if banner and banner.shownAt then banner.shownAt = nil; banner.text:SetText(""); banner:Hide() end
end

function CommanderGuide_Test()
    if not CanSpeak() then print("Commander Guide: this client has no text-to-speech") return false end
    local line = "Garrote on you. Heal yourself between casts."
    ShowBanner(line)
    StopSpeaking()
    local ok = SayNow(line)
    if not ok then print("Commander Guide: the voice did not answer -- is Speak callouts on?") end
    return ok
end

-- A Commander Orders waypoint at the raid's door: raidKey's raid, else the
-- page's. Returns true, uid when Orders took it; false, reason otherwise
-- (the /way line has been printed then, so the press never does nothing).
function CommanderGuide_Entrance(raidKey)
    if not Enabled() then print("Commander Guide is disabled in its settings") return false, "disabled" end
    local raid = raidKey and RaidByKey(raidKey) or PageRaid()
    if not raid then print("Commander Guide: no raid to go to") return false, "noraid" end
    if InsideRaid(raid) then
        print("Commander Guide: you are already inside " .. raid.title)
        return false, "inside"
    end
    local spec = EntranceFor(raid)
    if not spec then
        print("Commander Guide: no entrance is known for " .. raid.title)
        return false, "unknown"
    end
    local line = E.WayLine(spec) or ""
    local O = Orders()
    if not O then
        print("Commander Guide: " .. spec.title .. " -- " .. line)
        return false, "absent"
    end
    local ok, uid, why = pcall(O.Add, spec)
    if ok and uid then
        local row = D.ENTRANCES and D.ENTRANCES[raid.instanceMapID]
        local where = (row and row.zone) and (" in " .. row.zone) or ""
        print("Commander Guide: the arrow points to the " .. spec.title .. where)
        return true, uid
    end
    why = ok and why or "error"
    print("Commander Guide: " .. (REFUSED[why] or ("Commander Orders refused it (" .. tostring(why) .. ")"))
        .. " -- " .. line)
    return false, why
end

function CommanderGuide_Validate()
    local problems = E.Validate(D)
    if #problems == 0 then print("Commander Guide: the guide validates clean") return true end
    print(("Commander Guide: %d problem(s)"):format(#problems))
    for i = 1, math.min(#problems, 20) do print("  " .. problems[i]) end
    return false
end

-- Harness hooks (Harness/guide_ui_smoke.lua): the live session and the
-- window, so a test can read state the public functions do not return.
function CommanderGuide_Debug()
    return { ctx = ctx, frame = frame, banner = banner, selected = selectedBoss, speaking = speaking, inRaidMap = inRaidMap }
end

-- ---------------------------------------------------------------------------
-- events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
local OnEvent

local CLEU_KIND = {
    SPELL_AURA_APPLIED = "AURA_APPLIED",
    SPELL_AURA_REMOVED = "AURA_REMOVED",
    SPELL_AURA_APPLIED_DOSE = "DOSE",
    SPELL_CAST_START = "CAST_START",
    SPELL_CAST_SUCCESS = "CAST_SUCCESS",
    SPELL_DAMAGE = "DAMAGE",
    SPELL_PERIODIC_DAMAGE = "DAMAGE",
    SPELL_SUMMON = "SUMMON",
    UNIT_DIED = "UNIT_DIED",
}
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local REACTION_FRIENDLY = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x10
local band = bit and bit.band or function(a, b)
    local r, m = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + m end
        a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
    end
    return r
end

local function FriendlyPlayer(flags)
    flags = tonumber(flags) or 0
    return band(flags, TYPE_PLAYER) ~= 0 and band(flags, REACTION_FRIENDLY) ~= 0
end

local function OnCombatLog()
    local _, sub, _, srcGUID, srcName, _, _, dstGUID, dstName, dstFlags, _, spellId, spellName, _, a15, a16 = CombatLogGetCurrentEventInfo()
    local kind = CLEU_KIND[sub]
    if not kind then return end
    local ev = {
        kind = kind,
        spell = tonumber(spellId), spellName = spellName,
        srcNpc = E.NpcFromGUID(srcGUID), dstNpc = E.NpcFromGUID(dstGUID),
        srcName = srcName, dstName = dstName,
        dstIsMe = (dstGUID ~= nil and dstGUID == playerGUID),
        dstIsFriendly = FriendlyPlayer(dstFlags),
    }
    if kind == "DOSE" then ev.stacks = tonumber(a16) end
    if kind == "UNIT_DIED" then ev.npc = ev.dstNpc end
    Deliver(E.Feed(ctx, ev, GetTime()))
end

local function OnUnitHealth(unit)
    if not (ctx and ctx.boss) then return end
    local npc = E.NpcFromGUID(UnitGUID(unit))
    if not npc then return end
    local now = GetTime()
    if healthAt[npc] and (now - healthAt[npc]) < 0.5 then return end
    healthAt[npc] = now
    local max = UnitHealthMax(unit)
    if not max or max <= 0 then return end
    local pct = UnitHealth(unit) / max * 100
    Deliver(E.Feed(ctx, { kind = "HEALTH", npc = npc, pct = pct }, now))
end

local function RefreshZone()
    currentRaid = nil
    inRaidMap = false
    if not GetInstanceInfo then return end
    local _, _, _, _, _, _, _, instanceMapID = GetInstanceInfo()
    for _, raid in ipairs(D.RAIDS) do
        if raid.instanceMapID == instanceMapID then currentRaid = raid; inRaidMap = true end
    end
end

local function OnTargetChanged()
    if not Enabled() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if ctx and ctx.boss then return end
    if not (UnitExists and UnitExists("target")) then return end
    local boss = E.BossForNpc(D, E.NpcFromGUID(UnitGUID("target")))
    if not boss then return end
    targetBoss = boss
    if frame and frame:IsShown() then ShowBoss(boss)
    elseif DB().AutoOpen then EnsureFrame(); ShowBoss(boss); frame:Show() end
    if DB().BriefOnTarget then SpeakBrief(boss, false) end
end

local finishTimer
local function ScheduleFinish(seconds)
    if not (C_Timer and C_Timer.After) then
        Deliver(E.Finish(ctx, GetTime(), nil))
        return
    end
    local mine = {}
    finishTimer = mine
    C_Timer.After(seconds, function()
        if finishTimer ~= mine then return end
        if ctx and ctx.boss and not ctx.inCombat then Deliver(E.Finish(ctx, GetTime(), nil)) end
    end)
end

local function Apply()
    db = CommanderGuideDB
    ApplyBanner()
    if frame and frame:IsShown() then
        frame.voiceCheck:SetChecked(DB().Voice ~= false)
        if selectedBoss then RenderPage(selectedBoss) end
    end
    if not Enabled() then CommanderGuide_Stop() end
end

local ticker
local function EnsureTicker()
    if ticker or not (C_Timer and C_Timer.NewTicker) then return end
    ticker = C_Timer.NewTicker(0.5, function()
        if not ctx then return end
        if E.Tick(ctx, GetTime()) and DB().Interrupt ~= false and speaking then StopSpeaking() end
        Pump()
    end)
end

function OnEvent(self, event, ...)
    if event == "PLAYER_LOGIN" then
        db = CommanderGuideDB
        playerGUID = UnitGUID("player")
        ctx = E.NewSession(D, DB().Role or "HEALER")
        RefreshZone()
        ApplyBanner()
        EnsureTicker()
        if Commander and Commander.AddListener then Commander.AddListener(COMMANDER_GUIDE_EVENTS.UPDATE, Apply) end
        return
    end
    if not ctx then return end
    ctx.role = DB().Role or "HEALER"
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RefreshZone()
        -- the entrance button greys out inside the raid it points at
        if frame and frame:IsShown() then RenderList() end
    elseif event == "ENCOUNTER_START" then
        if not Enabled() then return end
        local id = ...
        local boss = E.BossForEncounter(D, id)
        if boss then
            ctx.inCombat = true
            Deliver(E.Begin(ctx, boss, GetTime(), "encounter"))
            if frame and frame:IsShown() then ShowBoss(boss) end
        end
    elseif event == "ENCOUNTER_END" then
        local _, _, _, _, success = ...
        if ctx.boss then Deliver(E.Finish(ctx, GetTime(), success == 1)) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ctx.inCombat = true
        finishTimer = nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        ctx.inCombat = false
        if ctx.boss then ScheduleFinish(ctx.source == "encounter" and 30 or 6) end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if Enabled() and (inRaidMap or ctx.boss) then OnCombatLog() end
    elseif event == "UNIT_HEALTH" then
        if Enabled() then OnUnitHealth((...)) end
    elseif event == "CHAT_MSG_MONSTER_YELL" then
        if Enabled() and ctx.boss then
            local text, name = ...
            Deliver(E.Feed(ctx, { kind = "YELL", text = text, srcName = name }, GetTime()))
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()
    elseif event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED" or event == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
        speaking = false
        Pump()
    end
end

events:SetScript("OnEvent", OnEvent)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("UNIT_HEALTH")
events:RegisterEvent("CHAT_MSG_MONSTER_YELL")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
for _, ev in ipairs({ "ENCOUNTER_START", "ENCOUNTER_END", "VOICE_CHAT_TTS_PLAYBACK_FINISHED", "VOICE_CHAT_TTS_PLAYBACK_FAILED" }) do
    pcall(events.RegisterEvent, events, ev)
end

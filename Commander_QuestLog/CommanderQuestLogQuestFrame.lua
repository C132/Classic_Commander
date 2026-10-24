-- Commander Quest Log: the NPC's quest dialog says what a quest is worth.
--
-- The moment a player decides whether a quest is worth the walk is at the
-- quest giver, and the stock dialog lists the items and the gold but never
-- the standing. So when the dialog shows a quest's offer (the detail panel,
-- Accept) or its turn-in (the reward panel, Complete Quest), a line under its
-- rewards says what it pays in reputation to this character, now:
-- "Reputation: +275 Honor Hold", "No reputation", with "(seen in game)" once
-- the calibration has watched it pay. It is the adapter's one line (the rules
-- engine's, CommanderQuestLogStanding.lua), the same the Log, the Zones and
-- Reputations tabs, the map drawer and a waypoint's note show; nothing is
-- worked out here.
--
-- How the 2.5.6 dialog is built (Blizzard_UIPanels_Game: Classic/QuestFrame
-- .lua with TBC/QuestFrame.xml, TBC/QuestInfo.lua and .xml -- the TBC build
-- loads those, per Blizzard_UIPanels_Game_Classic.toc):
--
--   * QuestFrameDetailPanel_OnShow and QuestFrameRewardPanel_OnShow both lay
--     their panel out through QuestInfo_Display(template, parentFrame,
--     acceptButton, material): QUEST_TEMPLATE_DETAIL into
--     QuestDetailScrollChildFrame, QUEST_TEMPLATE_REWARD into
--     QuestRewardScrollChildFrame. Display re-parents each shown element to
--     that scroll child and chains it under the last one; the rewards are
--     QuestInfoRewardsFrame (hidden when a quest has none), and the chain
--     always ends with QuestInfoSpacerFrame, a 5x5 frame anchored under the
--     last shown element.
--   * Nothing else on this build lays itself out through QuestInfo_Display
--     (the TBC quest log, TBC/QuestLogFrame.lua, draws its own briefing),
--     but the function and its shared frames are anyone's to call into
--     another scroll child. So the line is drawn only for the two dialog
--     templates, and hidden on any other Display.
--   * QUEST_ITEM_UPDATE re-lays the rewards (QuestInfo_ShowRewards) without a
--     Display; the line is anchored to the rewards frame and follows it, and
--     a ShowRewards post-hook re-places it should the rewards appear late.
--   * The detail panel hides its objectives and rewards (alpha 0) until the
--     description has typed itself out, then fades them in. The line copies
--     the alpha of the element it hangs under, frame by frame while it is
--     shown, so it never arrives before the rewards it belongs to.
--   * GetQuestID() names the dialog's quest on this build (the binary has it,
--     and Blizzard's own TBC QuestInfo.lua and Questie call it on both
--     panels). Should it answer 0, a turn-in is found in the log by its title
--     (GetTitleText); an offer, not in the log yet, gets no line.
--
-- No taint: the line is a plain, nameless frame of our own with one
-- FontString, parented to the scroll child the dialog is drawing into. The
-- dialog is joined through hooksecurefunc on three global functions and
-- HookScript on two panels -- post-hooks only, nothing replaced -- and no
-- field of any Blizzard frame or table is ever written by this file's code.
-- Colours are the dialog's own: GetMaterialTextColors for the material it
-- was drawn with, dark ink on the parchment. No glyphs (D11).
--
-- The third hook keeps the dialog standing when another addon asks for a
-- reward button out of turn (D47). QuestInfo_GetRewardButton(rewardsFrame,
-- index) makes the button an index asks for and files it at that index in
-- RewardButtons; QuestInfo_ShowRewards then hides every slot above the
-- quest's count, `for i = count + 1, #RewardButtons` (TBC/QuestInfo.lua:512).
-- Blizzard asks for 1, 2, 3 in turn. RXPGuides (4.11, its best-reward marks)
-- asks for its pick outright: a quest-log choice number (4, while the dialog
-- had only ever made 1 and 2) and -1 for "no pick". That leaves a hole (1, 2,
-- 4), # may answer 4, and the next dialog dies on slot 3: "attempt to index
-- field '?' (a nil value)" at QuestInfo.lua:513 (field report, 2026-10-24).
-- So after every call, any slot missing under the one asked for is asked of
-- Blizzard's own function, and what it makes stays hidden until the dialog
-- lays it out. Blizzard's own calls never leave a hole, so on them the hook
-- only reads. A slot under 1, a fraction or one past MAX_NUM_ITEMS is no
-- reward slot and is left alone (# never lands on it). The buttons it adds
-- carry this addon's taint as the one above them carries the other addon's;
-- the dialog reads both in the same pass, and nothing it does there is
-- protected. It runs whatever the settings say: it draws nothing.
--
-- Settings: EnableQuestLog, ShowRepEverywhere and RepInQuestDialog, all read
-- as "~= false", so a saved table from before they existed shows the line.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local F = {}
Q.QuestFrame = F

local GAP = 10                       -- under the element it hangs from, as QuestInfo's sections are spaced
local WIDTH = 275                    -- QUEST_TEMPLATE_DETAIL's contentWidth (the reward template's is 285)
local MIN_HEIGHT = 12
local OBSERVED_WORDS = "seen in game"
-- The most reward buttons a quest uses (Blizzard's MAX_NUM_ITEMS, Classic/QuestFrame.lua)
local MAX_REWARD_SLOTS = tonumber(MAX_NUM_ITEMS) or 10
-- The parchment's text colour, for a client without GetMaterialTextColors
local FALLBACK_INK = { 0.18, 0.12, 0.06 }

local S = {
    hooked = false,
    holder = nil, text = nil,
    -- The dialog panel up now, "DETAIL" | "REWARD" (nil: neither), with the
    -- scroll child and material it was drawn with -- kept while the line is
    -- not shown too, so a setting turned on or Questie getting ready while
    -- the dialog is open can put the line up
    panel = nil, parent = nil, material = nil,
    questId = nil, alphaSource = nil,
    lastError = nil,
    -- Reward buttons made to fill a hole another addon left (D47)
    filled = 0,
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function DB()
    if type(CommanderQuestLogDB) == "table" then return CommanderQuestLogDB end
    return {}
end

local function Wanted()
    local db = DB()
    return db.EnableQuestLog ~= false and db.ShowRepEverywhere ~= false and db.RepInQuestDialog ~= false
end

local function Adapter()
    local A = Q.Questie
    if type(A) == "table" then return A end
    return nil
end

-- A hook's error is reported (BugSack sees it) and the dialog carries on
local function Guarded(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            S.lastError = tostring(err)
            local handler = geterrorhandler and geterrorhandler()
            if handler then handler(err) end
        end
    end
end

-- The dialog's quest: GetQuestID(), else (a turn-in) the log entry whose
-- title is the dialog's, when exactly one is
local function DialogQuestId(panel)
    if GetQuestID then
        local ok, questId = pcall(GetQuestID)
        if ok and type(questId) == "number" and questId > 0 then return questId end
    end
    if panel ~= "REWARD" or not (GetTitleText and GetNumQuestLogEntries and GetQuestLogTitle) then return nil end
    local title = GetTitleText()
    if type(title) ~= "string" or title == "" then return nil end
    local found
    for index = 1, (GetNumQuestLogEntries()) or 0 do
        local name, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(index)
        if not isHeader and name == title and type(questId) == "number" then
            if found and found ~= questId then return nil end
            found = questId
        end
    end
    return found
end

-- "Reputation: +275 Honor Hold" | "No reputation" (+ " (seen in game)";
-- "Reputation (seen in game):" heads the several-faction form), or nil
-- without an answer: Questie not ready, no rules, a quest it does not know.
-- A quest that moves more than one faction gets one per line under
-- "Reputation:" -- in 275 px a single line wraps at whatever space comes,
-- most of them inside an effect ("+385" at one line's end, "Honor Hold" at
-- the next one's start). The same words as the adapter's one line, which
-- joins its effects with two spaces.
local function LineFor(questId)
    local A = Adapter()
    if not (questId and A and type(A.RepLine) == "function") then return nil end
    local line, effects = A.RepLine(questId)
    if type(line) ~= "string" then return nil end
    local R = Q.Standing
    local observed = false
    for _, effect in ipairs(type(effects) == "table" and effects or {}) do
        if type(effect) == "table" and effect.observed then observed = true break end
    end
    local seen = observed and (" (" .. OBSERVED_WORDS .. ")") or ""
    if type(R) == "table" and line == R.NO_REPUTATION then
        return line .. seen
    elseif line:find("  ", 1, true) then
        -- the word on the heading, which speaks for every line under it:
        -- at the end it would sit on the last faction's line alone and
        -- read as if only that figure had been seen
        return "Reputation" .. seen .. ":\n" .. (line:gsub("  ", "\n"))
    end
    return "Reputation: " .. line .. seen
end

local function TextColour(material)
    if type(GetMaterialTextColors) == "function" then
        local ok, colour = pcall(GetMaterialTextColors, material or "Parchment")
        if ok and type(colour) == "table" and type(colour[1]) == "number" then return colour end
    end
    return FALLBACK_INK
end

-- ---------------------------------------------------------------------------
-- The line
-- ---------------------------------------------------------------------------

-- The line away (the panel it was for may still be up)
local function Hide()
    S.questId, S.alphaSource = nil, nil
    if S.holder then
        S.holder:SetScript("OnUpdate", nil)
        S.holder:Hide()
    end
end

-- The panel gone: nothing to put a line on until the next Display
local function Forget()
    S.panel, S.parent, S.material = nil, nil, nil
    Hide()
end

-- Copies the alpha of the element the line hangs under (the detail panel's
-- fade-in of its objectives and rewards)
local function FollowAlpha(self)
    local source = S.alphaSource
    if source and source.GetAlpha then self:SetAlpha(source:GetAlpha() or 1) end
end

local function Ensure(parent)
    if S.holder then
        S.holder:SetParent(parent)
        return S.holder
    end
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(WIDTH, MIN_HEIGHT)
    local template = _G.QuestFont and "QuestFont" or "GameFontNormal"
    local text = holder:CreateFontString(nil, "ARTWORK", template)
    text:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
    text:SetWidth(WIDTH)
    text:SetJustifyH("LEFT")
    if text.SetJustifyV then text:SetJustifyV("TOP") end
    S.holder, S.text = holder, text
    return holder
end

-- Under the rewards when the quest has any, else under the last element the
-- dialog chained (what its spacer hangs from). Returns that element.
local function Anchor(holder, parent)
    holder:ClearAllPoints()
    local rewards = _G.QuestInfoRewardsFrame
    if rewards and rewards:IsShown() and rewards.GetParent and rewards:GetParent() == parent then
        holder:SetPoint("TOPLEFT", rewards, "BOTTOMLEFT", 0, -GAP)
        return rewards
    end
    local spacer = _G.QuestInfoSpacerFrame
    if spacer and spacer.GetPoint then
        local _, relativeTo = spacer:GetPoint(1)
        if type(relativeTo) == "table" and relativeTo ~= parent then
            holder:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, -GAP)
            return relativeTo
        end
        holder:SetPoint("TOPLEFT", spacer, "TOPLEFT", 0, 0)
        return spacer
    end
    holder:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -10)
    return nil
end

-- Which dialog panel a Display is drawing, by the scroll child it draws into
local function PanelOf(template, parent)
    if parent ~= nil and parent == _G.QuestDetailScrollChildFrame
        and (template == nil or _G.QUEST_TEMPLATE_DETAIL == nil or template == _G.QUEST_TEMPLATE_DETAIL) then
        return "DETAIL"
    end
    if parent ~= nil and parent == _G.QuestRewardScrollChildFrame
        and (template == nil or _G.QUEST_TEMPLATE_REWARD == nil or template == _G.QUEST_TEMPLATE_REWARD) then
        return "REWARD"
    end
    return nil
end

-- The line for the panel that is up (S.panel), or none when it is not wanted
-- or has no answer
local function Show()
    local panel, parent, material = S.panel, S.parent, S.material
    if not (panel and parent and Wanted()) then return Hide() end
    local questId = DialogQuestId(panel)
    local line = LineFor(questId)
    if not line then return Hide() end
    local holder = Ensure(parent)
    local under = Anchor(holder, parent)
    local text = S.text
    text:SetText(line)
    local colour = TextColour(material)
    text:SetTextColor(colour[1], colour[2], colour[3])
    holder:SetHeight(math.max(MIN_HEIGHT, math.ceil((text:GetStringHeight() or 0) + 2)))
    S.questId = questId
    -- the detail panel fades its rewards in after the description: follow
    -- the element the line hangs under (the rewards, else the objectives)
    if panel == "DETAIL" then
        S.alphaSource = (under == _G.QuestInfoRewardsFrame) and under or (_G.QuestInfoObjectivesText or under)
        FollowAlpha(holder)
        holder:SetScript("OnUpdate", FollowAlpha)
    else
        S.alphaSource = nil
        holder:SetScript("OnUpdate", nil)
        holder:SetAlpha(1)
    end
    holder:Show()
end

-- ---------------------------------------------------------------------------
-- The reward buttons: no hole under a slot another addon asked for (D47)
-- ---------------------------------------------------------------------------

-- After QuestInfo_GetRewardButton(rewardsFrame, index): every slot under
-- index is a button, made by the same function when one is missing
local function FillRewardGaps(rewardsFrame, index)
    if type(index) ~= "number" or index <= 1 or index > MAX_REWARD_SLOTS or index % 1 ~= 0 then return end
    local buttons = type(rewardsFrame) == "table" and rewardsFrame.RewardButtons
    if type(buttons) ~= "table" then return end
    for slot = 1, index - 1 do
        if buttons[slot] == nil then
            local button = QuestInfo_GetRewardButton(rewardsFrame, slot)
            if button and button.Hide then button:Hide() end
            S.filled = S.filled + 1
        end
    end
end

-- ---------------------------------------------------------------------------
-- Hooks
-- ---------------------------------------------------------------------------

local function OnDisplay(template, parentFrame, _, material)
    local panel = PanelOf(template, parentFrame)
    if not panel then return Forget() end
    S.panel, S.parent, S.material = panel, parentFrame, material
    Show()
end

-- The rewards re-laid (QUEST_ITEM_UPDATE): the line follows them
local function OnShowRewards()
    if S.panel then Show() end
end

local function OnPanelHide(panel)
    return function()
        if S.panel == panel then Forget() end
    end
end

-- A setting flipped, or the adapter's answer moved (Questie ready, a
-- standing changed, a sample seen): the panel that is up is asked again.
-- (S.panel is cleared by the panel's own OnHide, so a closed dialog is
-- never asked.)
local function Redraw()
    if S.panel then Show() end
end

local function Install()
    if S.hooked then return true end
    if not (hooksecurefunc and type(_G.QuestInfo_Display) == "function") then return false end
    S.hooked = true
    hooksecurefunc("QuestInfo_Display", Guarded(OnDisplay))
    if type(_G.QuestInfo_ShowRewards) == "function" then
        hooksecurefunc("QuestInfo_ShowRewards", Guarded(OnShowRewards))
    end
    if type(_G.QuestInfo_GetRewardButton) == "function" then
        hooksecurefunc("QuestInfo_GetRewardButton", Guarded(FillRewardGaps))
    end
    local detail, reward = _G.QuestFrameDetailPanel, _G.QuestFrameRewardPanel
    if detail and detail.HookScript then detail:HookScript("OnHide", Guarded(OnPanelHide("DETAIL"))) end
    if reward and reward.HookScript then reward:HookScript("OnHide", Guarded(OnPanelHide("REWARD"))) end
    return true
end

-- Blizzard_UIPanels_Game loads before every addon, so the dialog is there at
-- load; PLAYER_LOGIN is the second chance, and where the listeners go in
Install()
if CreateFrame then
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:SetScript("OnEvent", function(self)
        Install()
        local A = Adapter()
        if A and type(A.AddListener) == "function" then A.AddListener(Guarded(Redraw)) end
        if Commander and Commander.AddListener and COMMANDER_QUESTLOG_EVENTS and COMMANDER_QUESTLOG_EVENTS.UPDATE then
            Commander.AddListener(COMMANDER_QUESTLOG_EVENTS.UPDATE, Guarded(Redraw))
        end
        self:UnregisterEvent("PLAYER_LOGIN")
    end)
end

-- ---------------------------------------------------------------------------
-- Harness accessors. Nothing in the game reads these.
-- ---------------------------------------------------------------------------

function F._State()
    return { hooked = S.hooked, panel = S.panel, questId = S.questId, parent = S.parent,
             alphaSource = S.alphaSource, lastError = S.lastError, filled = S.filled }
end

function F._Holder() return S.holder, S.text end

-- Commander Quest Log: the NPC's quest dialog of 2.5.6, as a mock (luajit).
--
-- Not a harness: the stock QuestFrame that CommanderQuestLogQuestFrame.lua
-- hangs its reputation line on, for questframe_harness.lua and
-- questlog_rep_everywhere_harness.lua. It stands on questlog_mock.lua's
-- widgets (load that first) and is built from Blizzard's own source for this
-- build -- Blizzard_UIPanels_Game_Classic.toc loads Classic\QuestFrame.lua
-- with TBC\QuestFrame.xml, TBC\QuestInfo.lua and TBC\QuestInfo.xml for tbc --
-- cut down to what the module touches:
--
--   local QF = dofile(mock.ADDONS .. "/Commander_QuestLog/Harness/questframe_mock.lua")
--   local dialog = QF.Install(mock)          -- BEFORE the module loads, as in game
--   dialog.Offer({ id = 9355, title = "...", money = 1200 })   -- QUEST_DETAIL
--   dialog.TurnIn({ id = 9355, title = "...", items = 1 })     -- QUEST_COMPLETE
--   dialog.Progress() / dialog.Greeting() / dialog.Close()     -- the other panels, QUEST_FINISHED
--   dialog.ItemsArrive({ money = 500 })                        -- QUEST_ITEM_UPDATE
--   dialog.LogDisplay()                                        -- another caller's Display (QUEST_TEMPLATE_LOG)
--   dialog.FinishFade()                                        -- the detail panel's text finished typing
--   dialog.writes                                              -- every field the MODULE wrote on a Blizzard table
--
-- What is faithful, and why it matters to the module:
--
--   * QuestFrameDetailPanel / QuestFrameRewardPanel lay themselves out in
--     their OnShow through QuestInfo_Display(template, parentFrame,
--     acceptButton, material): QUEST_TEMPLATE_DETAIL into
--     QuestDetailScrollChildFrame, QUEST_TEMPLATE_REWARD into
--     QuestRewardScrollChildFrame. Display re-parents each shown element to
--     the scroll child and chains it TOPLEFT under the last one, with the
--     template's offsets (TBC/QuestInfo.lua:48-124). The chain ends with
--     QuestInfoSpacerFrame (5x5).
--   * QuestInfo_ShowRewards hides QuestInfoRewardsFrame and returns nil for a
--     quest with no rewards; otherwise it shows it, sets its height, and
--     returns it and its last inner element. The template tables hold the
--     ORIGINAL element functions, so a hooksecurefunc on the global
--     QuestInfo_ShowRewards fires only for Blizzard's direct calls
--     (QUEST_ITEM_UPDATE), never inside a Display -- as in game.
--   * The detail panel hides its alpha-dependent text (objectives, rewards)
--     and fades it in once the description has typed out (FinishFade here).
--   * Each panel's OnShow hides the others; QuestFrame's OnHide hides all four.
--   * Another caller's Display: the 2.5.6 TBC quest log does NOT draw
--     through QuestInfo_Display (TBC/QuestLogFrame.lua has its own
--     briefing), but the function and its shared element frames are
--     anyone's to call into another scroll child. LogDisplay is such a
--     Display (QUEST_TEMPLATE_LOG into a scroll child of its own), so "the
--     line is hidden on any other Display" stays a real check.
--   * Every Blizzard frame and template table is a proxy that records a field
--     written to it from outside Blizzard's own (mock) code: the module must
--     write none.
--   * hooksecurefunc replaces the global with a wrapper that runs the original
--     first, then the hook, the way the client's does.
--
-- The quest the dialog shows is { id, title, money, items, groupSize, text };
-- GetQuestID() answers dialog.questIdOverride when it is set (0: the client
-- has no id for it), else the quest's id.

local QF = {}

function QF.Install(mock, opts)
    opts = opts or {}
    local NewWidget = mock.NewWidget
    local unpackAll = unpack or table.unpack
    local handle = { writes = {}, quest = nil, questIdOverride = nil, material = "Parchment" }
    local depth = 0      -- > 0 while Blizzard's own (mock) code runs

    -- SetParent / GetParent on every widget of questlog_mock (it has neither:
    -- an unknown Set is a no-op there and an unknown Get answers nil), and
    -- RegisterUnitEvent, which the adapter's aura watcher uses where the
    -- client has it: there it is a no-op, so UNIT_AURA never arrived. The
    -- unit filter is not kept; a harness fires UNIT_AURA for "player".
    local mt = getmetatable(NewWidget("Frame"))
    if not mt.__questframeParent then
        local index = mt.__index
        mt.__index = function(self, key)
            if key == "SetParent" then return function(s, parent) s.__parent = parent end end
            if key == "GetParent" then return function(s) return s.__parent end end
            if key == "RegisterUnitEvent" then
                return function(s, event)
                    local registry = mock.eventRegistry
                    registry[event] = registry[event] or {}
                    table.insert(registry[event], s)
                end
            end
            return index(self, key)
        end
        mt.__questframeParent = true
    end

    local function Blizzard(fn)
        return function(...)
            depth = depth + 1
            local results = { pcall(fn, ...) }
            depth = depth - 1
            if not results[1] then error(results[2], 0) end
            return unpackAll(results, 2, table.maxn(results))
        end
    end
    handle.Blizzard = Blizzard

    -- A hook of the module's runs as the module, whoever's code triggered it:
    -- its writes are recorded even when Blizzard's own code fired the script
    local function AsModule(fn)
        return function(...)
            local saved = depth
            depth = 0
            local results = { pcall(fn, ...) }
            depth = saved
            if not results[1] then error(results[2], 0) end
            return unpackAll(results, 2, table.maxn(results))
        end
    end
    handle.AsModule = AsModule

    local function Proxy(name, real)
        return setmetatable({}, {
            __index = function(_, key)
                if key == "HookScript" then
                    return function(self, script, handler)
                        return real.HookScript(self, script, AsModule(handler))
                    end
                end
                return real[key]
            end,
            __newindex = function(_, key, value)
                if depth == 0 and not (type(key) == "string" and key:sub(1, 2) == "__") then
                    handle.writes[#handle.writes + 1] = name .. "." .. tostring(key)
                end
                real[key] = value
            end,
        })
    end

    local function Widget(kind, name, parent, shown)
        local real = NewWidget(kind, name)
        real.__parent = parent
        real.__shown = shown and true or false
        local proxy = Proxy(name, real)
        _G[name] = proxy
        return proxy
    end

    -- ---- the frames (QuestFrame.xml, QuestInfo.xml) ------------------------

    local frames = {}
    Blizzard(function()
        frames.QuestFrame = Widget("Frame", "QuestFrame", UIParent, false)
        for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameRewardPanel", "QuestFrameProgressPanel",
            "QuestFrameGreetingPanel" }) do
            frames[name] = Widget("Frame", name, frames.QuestFrame, false)
        end
        frames.QuestDetailScrollChildFrame = Widget("Frame", "QuestDetailScrollChildFrame", frames.QuestFrameDetailPanel, true)
        frames.QuestRewardScrollChildFrame = Widget("Frame", "QuestRewardScrollChildFrame", frames.QuestFrameRewardPanel, true)
        frames.QuestFrameAcceptButton = Widget("Button", "QuestFrameAcceptButton", frames.QuestFrameDetailPanel, true)
        frames.QuestFrameCompleteQuestButton = Widget("Button", "QuestFrameCompleteQuestButton", frames.QuestFrameRewardPanel, true)
        -- another caller's scroll child (QUEST_TEMPLATE_LOG), sharing the element frames
        frames.QuestLogDetailScrollChildFrame = Widget("Frame", "QuestLogDetailScrollChildFrame", UIParent, true)
        frames.QuestInfoFrame = Widget("Frame", "QuestInfoFrame", UIParent, false)
        for _, name in ipairs({ "QuestInfoTitleHeader", "QuestInfoDescriptionText", "QuestInfoObjectivesHeader",
            "QuestInfoObjectivesText", "QuestInfoGroupSize", "QuestInfoRewardText" }) do
            frames[name] = Widget("FontString", name, frames.QuestInfoFrame, true)
        end
        frames.QuestInfoRewardsFrame = Widget("Frame", "QuestInfoRewardsFrame", frames.QuestInfoFrame, false)
        frames.QuestInfoRewardsFrame:SetSize(285, 10)
        local rewards = frames.QuestInfoRewardsFrame
        rewards.Header = NewWidget("FontString")
        rewards.ItemReceiveText = NewWidget("FontString")
        rewards.MoneyFrame = NewWidget("Frame")
        rewards.MoneyFrame.__parent = rewards
        rewards.ItemReceiveText.__parent = rewards
        frames.QuestInfoSpacerFrame = Widget("Frame", "QuestInfoSpacerFrame", frames.QuestInfoFrame, true)
        frames.QuestInfoSpacerFrame:SetSize(5, 5)
    end)()
    handle.frames = frames

    -- ---- the API the dialog reads ------------------------------------------

    function GetQuestID()
        if handle.questIdOverride ~= nil then return handle.questIdOverride end
        return handle.quest and handle.quest.id or 0
    end
    function GetTitleText() return handle.quest and handle.quest.title or "" end
    function GetQuestText() return handle.quest and handle.quest.text or "" end
    function GetObjectiveText() return "" end
    function GetRewardText() return "Thank you." end
    function GetSuggestedGroupNum() return handle.quest and handle.quest.groupSize or 0 end
    function GetRewardMoney() return handle.quest and handle.quest.money or 0 end
    function GetNumQuestRewards() return handle.quest and handle.quest.items or 0 end
    function GetNumQuestChoices() return 0 end
    function GetQuestBackgroundMaterial() return handle.material end
    -- MATERIAL_TEXT_COLOR_TABLE: text, then title colour
    function GetMaterialTextColors(material)
        if material == "Stone" then return { 1, 1, 1 }, { 1, 0.82, 0 } end
        return { 0.18, 0.12, 0.06 }, { 0, 0, 0 }
    end
    QuestFrame_GetMaterial = Blizzard(function() return GetQuestBackgroundMaterial() or "Parchment" end)

    -- ---- QuestInfo (TBC/QuestInfo.lua) -------------------------------------

    local function ShowTitle()
        frames.QuestInfoTitleHeader:SetText(GetTitleText())
        return frames.QuestInfoTitleHeader
    end
    local function ShowDescriptionText()
        frames.QuestInfoDescriptionText:SetText(GetQuestText())
        return frames.QuestInfoDescriptionText
    end
    local function ShowObjectivesHeader() return frames.QuestInfoObjectivesHeader end
    local function ShowObjectivesText()
        frames.QuestInfoObjectivesText:SetText(GetObjectiveText())
        return frames.QuestInfoObjectivesText
    end
    local function ShowGroupSize()
        local group = GetSuggestedGroupNum()
        if group > 0 then
            frames.QuestInfoGroupSize:SetText("Suggested Players: " .. group)
            frames.QuestInfoGroupSize:Show()
            return frames.QuestInfoGroupSize
        end
        frames.QuestInfoGroupSize:Hide()
        return nil
    end
    local function ShowRewards()
        local rewards = frames.QuestInfoRewardsFrame
        local money, items = GetRewardMoney(), GetNumQuestRewards()
        if money == 0 and items == 0 then
            rewards:Hide()
            return nil
        end
        local last = rewards.ItemReceiveText
        if money > 0 then last = rewards.MoneyFrame end
        rewards:Show()
        rewards:SetHeight(20 + items * 40 + (money > 0 and 20 or 0))
        return rewards, last
    end
    local function ShowRewardText()
        frames.QuestInfoRewardText:SetText(GetRewardText())
        return frames.QuestInfoRewardText
    end
    local function ShowSpacer() return frames.QuestInfoSpacerFrame end

    QUEST_TEMPLATE_DETAIL = Proxy("QUEST_TEMPLATE_DETAIL", { questLog = nil, chooseItems = nil, contentWidth = 275,
        elements = {
            ShowTitle, 5, -10, ShowDescriptionText, 0, -5, ShowObjectivesHeader, 0, -15, ShowObjectivesText, 0, -5,
            ShowGroupSize, 0, -10, ShowRewards, 0, -15, ShowSpacer, 0, -15,
        } })
    QUEST_TEMPLATE_REWARD = Proxy("QUEST_TEMPLATE_REWARD", { questLog = nil, chooseItems = true, contentWidth = 285,
        elements = { ShowTitle, 5, -10, ShowRewardText, 0, -5, ShowRewards, 0, -10, ShowSpacer, 0, -10 } })
    QUEST_TEMPLATE_LOG = Proxy("QUEST_TEMPLATE_LOG", { questLog = true, chooseItems = nil, contentWidth = 285,
        elements = { ShowTitle, 5, -5, ShowObjectivesText, 0, -5, ShowGroupSize, 0, -10, ShowDescriptionText, 0, -5,
                     ShowRewards, 0, -10, ShowSpacer, 0, -10 } })

    QuestInfo_Display = Blizzard(function(template, parentFrame, acceptButton, material)
        local info = frames.QuestInfoFrame
        info.questLog = template.questLog
        info.chooseItems = template.chooseItems
        info.acceptButton = acceptButton
        info.material = material
        local elements = template.elements
        local lastFrame
        for i = 1, #elements, 3 do
            local shownFrame, bottomShownFrame = elements[i](parentFrame)
            if shownFrame then
                shownFrame:SetParent(parentFrame)
                shownFrame:ClearAllPoints()
                if lastFrame then
                    shownFrame:SetPoint("TOPLEFT", lastFrame, "BOTTOMLEFT", elements[i + 1], elements[i + 2])
                else
                    shownFrame:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", elements[i + 1], elements[i + 2])
                end
                lastFrame = bottomShownFrame or shownFrame
            end
        end
        handle.displays = (handle.displays or 0) + 1
    end)
    QuestInfo_ShowRewards = Blizzard(ShowRewards)

    local ALPHA_DEPENDENT = { "QuestInfoObjectivesText", "QuestInfoRewardsFrame", "QuestInfoRewardText",
        "QuestInfoGroupSize", "QuestInfoObjectivesHeader" }
    QuestInfo_HideAlphaDependentText = Blizzard(function()
        for _, name in ipairs(ALPHA_DEPENDENT) do frames[name]:SetAlpha(0) end
    end)
    QuestInfo_ShowAlphaDependentText = Blizzard(function()
        for _, name in ipairs(ALPHA_DEPENDENT) do frames[name]:SetAlpha(1) end
    end)

    -- ---- the panels (Classic/QuestFrame.lua) --------------------------------

    local function HideOthers(keep)
        for _, name in ipairs({ "QuestFrameDetailPanel", "QuestFrameRewardPanel", "QuestFrameProgressPanel",
            "QuestFrameGreetingPanel" }) do
            if name ~= keep then frames[name]:Hide() end
        end
    end

    frames.QuestFrameDetailPanel:SetScript("OnShow", Blizzard(function()
        HideOthers("QuestFrameDetailPanel")
        QuestInfo_Display(QUEST_TEMPLATE_DETAIL, frames.QuestDetailScrollChildFrame, frames.QuestFrameAcceptButton,
            QuestFrame_GetMaterial())
        QuestInfo_HideAlphaDependentText(frames.QuestDetailScrollChildFrame)
        handle.fading = true
    end))
    frames.QuestFrameDetailPanel:SetScript("OnHide", Blizzard(function()
        QuestInfo_ShowAlphaDependentText(frames.QuestDetailScrollChildFrame)
        handle.fading = false
    end))
    frames.QuestFrameRewardPanel:SetScript("OnShow", Blizzard(function()
        HideOthers("QuestFrameRewardPanel")
        QuestInfo_Display(QUEST_TEMPLATE_REWARD, frames.QuestRewardScrollChildFrame,
            frames.QuestFrameCompleteQuestButton, QuestFrame_GetMaterial())
    end))
    frames.QuestFrameProgressPanel:SetScript("OnShow", Blizzard(function() HideOthers("QuestFrameProgressPanel") end))
    frames.QuestFrameGreetingPanel:SetScript("OnShow", Blizzard(function() HideOthers("QuestFrameGreetingPanel") end))
    frames.QuestFrame:SetScript("OnHide", Blizzard(function() HideOthers(nil) end))

    local function Panel(name)
        frames[name]:Hide()
        frames[name]:Show()
        frames.QuestFrame:Show()
    end
    frames.QuestFrame:SetScript("OnEvent", Blizzard(function(_, event)
        if event == "QUEST_FINISHED" then frames.QuestFrame:Hide() return end
        if event == "QUEST_DETAIL" then Panel("QuestFrameDetailPanel")
        elseif event == "QUEST_COMPLETE" then Panel("QuestFrameRewardPanel")
        elseif event == "QUEST_PROGRESS" then Panel("QuestFrameProgressPanel")
        elseif event == "QUEST_GREETING" then Panel("QuestFrameGreetingPanel")
        elseif event == "QUEST_ITEM_UPDATE" then
            if frames.QuestFrameDetailPanel:IsShown() or frames.QuestFrameRewardPanel:IsShown() then
                QuestInfo_ShowRewards()
            end
        end
    end))
    for _, event in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_PROGRESS", "QUEST_GREETING",
        "QUEST_FINISHED", "QUEST_ITEM_UPDATE" }) do
        frames.QuestFrame:RegisterEvent(event)
    end

    -- ---- hooksecurefunc ------------------------------------------------------

    if opts.hooksecurefunc ~= false and not rawget(_G, "hooksecurefunc") then
        function hooksecurefunc(target, name, post)
            if type(target) == "string" then target, name, post = _G, target, name end
            local original = target[name]
            assert(type(original) == "function", "hooksecurefunc on a missing function " .. tostring(name))
            local hook = AsModule(post)
            rawset(target, name, function(...)
                local results = { original(...) }
                hook(...)
                return unpackAll(results, 1, table.maxn(results))
            end)
        end
    end

    -- ---- driving it -----------------------------------------------------------

    local function Quest(quest)
        handle.quest = quest
        handle.questIdOverride = quest and quest.questIdOverride or nil
    end
    function handle.Offer(quest) Quest(quest); mock.Fire("QUEST_DETAIL") end
    function handle.TurnIn(quest) Quest(quest); mock.Fire("QUEST_COMPLETE") end
    function handle.Progress() mock.Fire("QUEST_PROGRESS") end
    function handle.Greeting() mock.Fire("QUEST_GREETING") end
    function handle.Close() mock.Fire("QUEST_FINISHED") end
    function handle.ItemsArrive(more)
        for key, value in pairs(more or {}) do handle.quest[key] = value end
        mock.Fire("QUEST_ITEM_UPDATE")
    end
    function handle.FinishFade()
        if handle.fading then Blizzard(function() QuestInfo_ShowAlphaDependentText(frames.QuestDetailScrollChildFrame) end)() end
        handle.fading = false
    end
    -- Another caller's Display of a quest: the shared frames go to its child
    function handle.LogDisplay(quest)
        Quest(quest or handle.quest)
        QuestInfo_Display(QUEST_TEMPLATE_LOG, frames.QuestLogDetailScrollChildFrame, nil, "Parchment")
    end
    -- Shown, and every parent up the chain shown
    function handle.Visible(widget)
        local w = widget
        while w do
            if w.__shown == false then return false end
            w = w.__parent
        end
        return true
    end
    return handle
end

return QF

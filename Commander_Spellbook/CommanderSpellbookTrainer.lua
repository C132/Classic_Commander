-- Commander Spellbook: at the trainer.
--
-- While a trainer's window is open the Training view knows what that trainer
-- lists, and can buy it (DECISIONS D15):
--
--   * Train All buys every rank on Train Now that this trainer lists, one at
--     a time: a purchase, the trainer's own TRAINER_UPDATE, then the next (a
--     chained rank turns available only once the rank before it is bought).
--     Ignored ranks stay unbought, and so does anything the trainer lists
--     that Train Now does not (a pet trainer's lines, a gap in the data):
--     those are the player's to pick in the trainer's window. A confirmation
--     names the count and the trainer's own price first. A trainer list that
--     hides lines (Available unticked in its filter, a folded header) is
--     opened up first, the one change made to the trainer's own state.
--   * Train buys the selected rank or weapon skill when the open trainer
--     lists it as available, as the stock Train button does.
--   * Opening a class trainer opens the Training view (the Open at the
--     Trainer setting), and closing the trainer closes it again if that is
--     how it was opened.
--
-- Blizzard's trainer window is not touched: it has no room for a button
-- between its money and its Train button, and its list is the player's.

CommanderSpellbook = CommanderSpellbook or {}
local S = CommanderSpellbook

local T = { open = false, tradeskill = false, services = {}, byName = {} }
S.Trainer = T

-- How long a purchase may go unanswered before Train All gives up
local STEP_TIMEOUT = 3

local function RankOf(text)
    return tonumber(tostring(text or ""):match("(%d+)"))
end

local function Say(words)
    print("Commander Spellbook: " .. words)
end

-- What the open trainer lists, as read now. Headers are skipped; a folded
-- header hides its lines from GetNumTrainerServices (T.Hiding)
function T.Read()
    T.services, T.byName, T.folded = {}, {}, false
    if not (T.open and GetNumTrainerServices and GetTrainerServiceInfo) then return T.services end
    for index = 1, GetNumTrainerServices() or 0 do
        local name, subText, kind, expanded = GetTrainerServiceInfo(index)
        if kind == "header" and not expanded then T.folded = true end
        if name and kind and kind ~= "header" then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(index) or 0
            local service = { index = index, name = name, rank = RankOf(subText), kind = kind, cost = cost or 0 }
            T.services[#T.services + 1] = service
            local list = T.byName[name]
            if not list then
                list = {}
                T.byName[name] = list
            end
            list[#list + 1] = service
        end
    end
    return T.services
end

-- The trainer's line for one Training item: the same name and rank (a spell
-- of one rank may be listed with no rank, or as Rank 1)
function T.ServiceFor(item)
    if not (T.open and item and item.family) then return nil end
    local list = T.byName[item.family.name or ""]
    if not list then return nil end
    local want = item.entry and item.entry.rank
    for _, service in ipairs(list) do
        if service.rank == want then return service end
    end
    if #(item.family.ranks or {}) <= 1 then
        for _, service in ipairs(list) do
            if service.rank == nil or service.rank == 1 then return service end
        end
    end
    return nil
end

-- The Training list as it stands, for a decision taken outside the window
function T.Current()
    local db = CommanderSpellbookDB or {}
    return S.Training(S.Scan({}), { soon = db.SoonLevels })
end

-- Whether the trainer's list is hiding lines: Available unticked in its
-- filter, or a header folded
function T.Hiding()
    if not T.open then return false end
    if GetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter("available") then return true end
    return T.folded and true or false
end

-- Open the list up: tick Available, unfold every header. True when that
-- changed anything (the trainer answers with a TRAINER_UPDATE).
function T.Reveal()
    local changed = false
    if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter("available") then
        SetTrainerServiceTypeFilter("available", true)
        changed = true
    end
    if T.folded and ExpandTrainerSkillLine then
        ExpandTrainerSkillLine(0)
        changed = true
    end
    return changed
end

-- What Train All would buy here: the Train Now ranks this trainer lists,
-- and the next rank of each (a filter may hide a chained rank until the one
-- before is bought), at its own prices where it lists them (a trainer of a
-- faction you are Honored with asks less). A Train Now rank it does not list
-- is not its to teach, and is neither counted nor priced. Offered at a class
-- trainer, or where the list is hiding lines and nothing in view is a weapon
-- master's (the list is opened up before anything is bought). `extra`
-- counts what it lists as available that no Training row is: the player's
-- to pick in its own window.
function T.Plan(training)
    local plan = { items = {}, cost = 0, count = 0, extra = 0, offer = false }
    if not T.open or T.tradeskill then return plan end
    local mapped, weapons = {}, false
    for _, group in pairs(training and training.groups or {}) do
        for _, item in ipairs(group.items) do
            local service = T.ServiceFor(item)
            if service then
                mapped[service] = true
                if item.weapon then weapons = true end
            end
        end
    end
    -- Train Now is in level order, so a rank comes after the one before it
    local listed = {}
    local now = training and training.groups and training.groups.NOW
    for _, item in ipairs(now and now.items or {}) do
        local service = T.ServiceFor(item)
        if service or listed[item.family] then
            listed[item.family] = true
            plan.items[#plan.items + 1] = item
            plan.cost = plan.cost + ((service and service.cost) or item.cost or 0)
        end
    end
    plan.count = #plan.items
    for _, service in ipairs(T.services) do
        if service.kind == "available" and not mapped[service] then plan.extra = plan.extra + 1 end
    end
    plan.hiding = T.Hiding()
    plan.offer = (plan.count > 0 and T.IsClassTrainer(training)) or (plan.hiding and not weapons)
    return plan
end

-- A class trainer, as opposed to a weapon master or a pet trainer: it lists
-- some rank of a class spell, available now or not
function T.IsClassTrainer(training)
    if not T.open or T.tradeskill then return false end
    for _, group in pairs(training and training.groups or {}) do
        for _, item in ipairs(group.items) do
            if not item.weapon and T.ServiceFor(item) then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Buying
-- ---------------------------------------------------------------------------

local run

function T.Running() return run ~= nil end

local function Finish(words)
    local done = run
    run = nil
    -- Only purchases the trainer answered are counted (`pending` is one it
    -- never did)
    if done and done.bought > 0 then
        Say(string.format("trained %d rank%s for %s.", done.bought, done.bought == 1 and "" or "s", S.Money(done.spent)))
    end
    if words then Say(words) end
    if S.QueueRefresh then S.QueueRefresh() end
end

-- Wait for the trainer's next TRAINER_UPDATE; if it never comes, `onTimeout`
local function Wait(onTimeout)
    local token = {}
    run.token, run.waiting = token, true
    if C_Timer and C_Timer.After then
        C_Timer.After(STEP_TIMEOUT, function()
            if run and run.token == token and run.waiting then
                run.waiting = false
                onTimeout()
            end
        end)
    end
end

local function Label(item)
    local rank = item.entry and item.entry.rank
    return (item.family.name or "?") .. (rank and (" (Rank " .. rank .. ")") or "")
end

-- Whether the trainer has answered a purchase: the rank is known, or its
-- line is no longer on offer. An update that comes before that (a second
-- update, the player ticking the filter) is not the answer.
local function Answered(pending)
    if S.IsKnown and S.IsKnown(pending.item.id) then return true end
    local line = T.ServiceFor(pending.item)
    return not (line and line.kind == "available")
end

local function Step()
    if not run then return end
    if not T.open then return Finish("the trainer closed, so Train All stopped.") end
    T.Read()
    local item, service
    for _, candidate in ipairs(run.items) do
        if not run.done[candidate] then
            local line = T.ServiceFor(candidate)
            if line and line.kind == "available" then
                item, service = candidate, line
                break
            end
        end
    end
    if not item then
        local left = 0
        for _, candidate in ipairs(run.items) do
            if not run.done[candidate] then left = left + 1 end
        end
        return Finish(left > 0 and string.format("%d rank%s left that this trainer will not teach yet.",
            left, left == 1 and "" or "s") or nil)
    end
    if GetMoney and GetMoney() < (service.cost or 0) then
        return Finish("not enough money for " .. Label(item) .. ", so Train All stopped.")
    end
    run.done[item] = true
    run.pending = { item = item, cost = service.cost or 0 }
    Wait(function() Finish("the trainer did not answer for " .. Label(item) .. ", so Train All stopped.") end)
    BuyTrainerService(service.index)
end

-- `expected` is what the confirmation showed ({ count, cost }): a list that
-- has changed since (a rank unignored, a level gained, another trainer) is
-- not bought on that say-so
function T.TrainAll(training, expected)
    if run or not T.open or T.tradeskill or not BuyTrainerService then return false end
    local plan = T.Plan(training or T.Current())
    if not plan.offer or plan.count == 0 then return false end
    if expected and (expected.count ~= plan.count or expected.cost ~= plan.cost) then
        Say("the list changed since you were asked, so nothing was bought. Press Train All again.")
        return false
    end
    run = { items = plan.items, done = {}, bought = 0, spent = 0 }
    -- The window greys its buttons now, not after the first answer
    if S.IsShown and S.IsShown() and S.Refresh then S.Refresh() end
    Step()
    return true
end

-- One rank, as the stock Train button buys it
function T.TrainOne(item)
    if run or not BuyTrainerService then return false end
    local service = T.ServiceFor(item)
    if not (service and service.kind == "available") then return false end
    if GetMoney and GetMoney() < (service.cost or 0) then
        Say("not enough money for " .. Label(item) .. ".")
        return false
    end
    BuyTrainerService(service.index)
    return true
end

if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_SPELLBOOK_TRAIN_ALL"] = {
        text = "Train %s?",
        button1 = "Train All",
        button2 = "Cancel",
        OnAccept = function(_, data) T.TrainAll(nil, data or { count = -1 }) end,
        timeout = 0,
        whileDead = false,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end

-- Train All's button: open the list up if it is hiding lines (then come
-- back once the trainer has answered), then ask
local revealing
function T.ConfirmTrainAll(training)
    if run or revealing or not T.open then return end
    if T.Hiding() and T.Reveal() then
        local token = {}
        revealing = token
        if C_Timer and C_Timer.After then
            C_Timer.After(STEP_TIMEOUT, function()
                if revealing == token then
                    revealing = nil
                    T.Read()
                    T.ConfirmTrainAll()
                end
            end)
        end
        return
    end
    local plan = T.Plan(training or T.Current())
    if not (plan.offer and plan.count > 0) then
        Say("this trainer teaches nothing on your Train Now list.")
        return
    end
    local words = string.format("%d rank%s for %s", plan.count, plan.count == 1 and "" or "s", S.Money(plan.cost))
    if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs["COMMANDER_SPELLBOOK_TRAIN_ALL"] then
        StaticPopup_Show("COMMANDER_SPELLBOOK_TRAIN_ALL", words, nil, { count = plan.count, cost = plan.cost })
    else
        T.TrainAll(training)
    end
end

-- ---------------------------------------------------------------------------
-- The trainer's events
-- ---------------------------------------------------------------------------

local function WindowShown()
    return S.IsShown and S.IsShown() or false
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_CLOSED", "TRAINER_UPDATE" }) do
    pcall(events.RegisterEvent, events, event)
end

events:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        T.open = true
        T.tradeskill = (IsTradeskillTrainer and IsTradeskillTrainer()) and true or false
        T.Read()
        local db = CommanderSpellbookDB or {}
        if db.EnableSpellbook ~= false and db.OpenAtTrainer ~= false and not WindowShown()
            and T.IsClassTrainer(T.Current()) and CommanderSpellbook_Open then
            -- The view the window was left on, put back when it closes
            T.openedFrom = db.Filter
            CommanderSpellbook_Open("TRAIN")
            T.openedWindow = WindowShown()
        elseif S.QueueRefresh then
            S.QueueRefresh()
        end
    elseif event == "TRAINER_CLOSED" then
        T.open = false
        revealing = nil
        T.services, T.byName, T.folded = {}, {}, false
        -- A question about a trainer that is gone is not answered later
        if StaticPopup_Hide then StaticPopup_Hide("COMMANDER_SPELLBOOK_TRAIN_ALL") end
        if run then Finish("the trainer closed, so Train All stopped.") end
        if T.openedWindow and WindowShown() and (CommanderSpellbookDB or {}).Filter == "TRAIN"
            and CommanderSpellbook_Hide then
            CommanderSpellbook_Hide()
            if CommanderSpellbookDB and T.openedFrom then CommanderSpellbookDB.Filter = T.openedFrom end
        elseif S.QueueRefresh then
            S.QueueRefresh()
        end
        T.openedWindow, T.openedFrom = false, nil
    elseif event == "TRAINER_UPDATE" then
        if not T.open then return end
        T.Read()
        if revealing then
            revealing = nil
            if C_Timer and C_Timer.After then C_Timer.After(0, T.ConfirmTrainAll) else T.ConfirmTrainAll() end
        elseif run and run.waiting then
            local pending = run.pending
            if pending then
                if not Answered(pending) then return end
                run.bought = run.bought + 1
                run.spent = run.spent + pending.cost
                run.pending = nil
            end
            run.waiting = false
            -- A frame on: the stock window repaints its own list on this
            -- same event, and the next purchase should not race it
            if C_Timer and C_Timer.After then C_Timer.After(0, Step) else Step() end
        elseif S.QueueRefresh then
            S.QueueRefresh()
        end
    end
end)

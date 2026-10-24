-- Commander Quest Log: the NPC quest dialog's reputation line (luajit).
--
-- Drives CommanderQuestLogQuestFrame.lua over the 2.5.6 quest dialog as
-- Blizzard builds it (questframe_mock.lua: Classic\QuestFrame.lua with the
-- TBC QuestFrame and QuestInfo files), on the window harnesses' client
-- (questlog_mock.lua), with the fake Questie's reputation world
-- (Fake.RepWorld(): a level-70 Human paladin, real quest ids and Questie's
-- real rows) and the REAL rules engine and generated data behind the
-- adapter. What it asserts is what the player would see at the quest giver:
--
--   A  loading: the hooks go in at load (post-hooks only), no global, no
--      field written on any Blizzard frame or table, ever (checked again at
--      the end of the run);
--   B  the offer (detail panel): "Reputation: +275 Honor Hold" for a Human on
--      a 250 quest, under the rewards, in the dialog's own ink and font, in
--      the scroll child the dialog draws into, arriving with the rewards'
--      fade and not before;
--   C  the turn-in (reward panel): the same line, moved to that panel;
--   D  "No reputation", and a quest with no rewards (the line hangs under
--      what the spacer hangs under); several factions one per line under
--      "Reputation:" (in 275 px one line wraps inside an effect);
--   E  every other panel, another caller's Display (the TBC quest log has
--      none, but the shared frames are anyone's) and the dialog closing take
--      it away;
--   F  the rewards arriving late (QUEST_ITEM_UPDATE) move it under them;
--   G  no quest id from the client: a turn-in found in the log by its title,
--      an offer gets nothing, two log quests with the title get nothing;
--   H  the settings (and a flip while the dialog is up), Questie still
--      loading (the line arrives when it is ready), the Wickerman and a
--      calibration sample changing what the open dialog says;
--   I  what cannot be answered gets no line: a quest Questie does not know,
--      no rules, no Questie; an error in the line's code is reported and
--      the dialog is drawn all the same; a client without the dialog at
--      load is hooked at PLAYER_LOGIN;
--   J  another addon asking for a reward button out of turn (RXPGuides'
--      marks: a quest-log choice number, -1 for no pick): without the hook
--      the next dialog dies on the hole, as in the 2026-10-24 report; with
--      it the hole is filled with hidden buttons, Blizzard's own calls fill
--      nothing, no reward slot is invented, and the next dialog draws (D47).
--
--   luajit Commander_QuestLog/Harness/questframe_harness.lua
--   CQL_QUESTFRAME=/path/copy.lua luajit .../questframe_harness.lua   -- a mutated copy

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local MODULE = ADDONS .. "/Commander_QuestLog/"
local QUESTFRAME_FILE = os.getenv("CQL_QUESTFRAME") or (MODULE .. "CommanderQuestLogQuestFrame.lua")

local mock = dofile(MODULE .. "Harness/questlog_mock.lua")
local Fake = dofile(MODULE .. "Harness/fake_questie.lua")
local QF = dofile(MODULE .. "Harness/questframe_mock.lua")
local CHECK, Done = mock.Checker()

-- The client's own quest log calls; the fake's InstallClient (forced, so
-- each boot's world is the one the stubs read) would replace them
local mockLog = { GetQuestLogTitle = GetQuestLogTitle, GetQuestLogIndexByID = GetQuestLogIndexByID }

mock.LoadFramework()

local Q, A, dialog, fake, world, frames
local loadErrors = {}

local function Settle()
    for _ = 1, 8 do mock.RunTimers(1) end
end

-- A fresh module over a fresh reputation world. opts: edit(world), absent
-- (no Questie), noDialog (no QuestInfo_Display at load), noRules, db
local function Boot(opts)
    opts = opts or {}
    for event in pairs(mock.eventRegistry) do mock.eventRegistry[event] = nil end
    for i = #mock.timers, 1, -1 do mock.timers[i] = nil end
    CommanderQuestLog = nil
    CommanderQuestLogReputationData = nil
    CommanderQuestLogDB = opts.db or {}
    CommanderQuestLogChar = { Ignored = {} }
    world = Fake.RepWorld()
    if opts.edit then opts.edit(world) end
    if opts.absent then
        Questie, QuestieLoader = nil, nil
        fake = nil
    else
        fake = Fake.Install(world)
    end
    Fake.InstallClient(world, { force = true })
    GetQuestLogTitle, GetQuestLogIndexByID = mockLog.GetQuestLogTitle, mockLog.GetQuestLogIndexByID
    mock.state.log = {}
    if opts.noDialog then
        QuestInfo_Display, QuestInfo_ShowRewards, QuestFrameDetailPanel, QuestFrameRewardPanel = nil, nil, nil, nil
        QuestInfo_GetRewardButton = nil
        dialog = nil
    else
        dialog = QF.Install(mock)
        frames = dialog.frames
    end
    local files = { "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua" }
    if not opts.noRules then files[#files + 1] = "CommanderQuestLogReputationData.lua" end
    files[#files + 1] = "CommanderQuestLogCompletion.lua"
    if not opts.noRules then files[#files + 1] = "CommanderQuestLogStanding.lua" end
    files[#files + 1] = "CommanderQuestLogQuestie.lua"
    for _, file in ipairs(files) do mock.Load(MODULE .. file) end
    local before = {}
    for key in pairs(_G) do before[key] = true end
    local ok, err = pcall(mock.Load, QUESTFRAME_FILE)
    if not ok then loadErrors[#loadErrors + 1] = tostring(err) end
    local added = {}
    for key in pairs(_G) do if not before[key] then added[#added + 1] = tostring(key) end end
    mock.Login()
    Settle()
    Q = CommanderQuestLog
    A = Q.Questie
    return added
end

local function Holder()
    local holder, text = Q.QuestFrame._Holder()
    return holder, text
end

-- The line as the player sees it: its text when it is up and every parent
-- up the chain is shown, else nil
local function Seen()
    local holder, text = Holder()
    if not (holder and dialog and dialog.Visible(holder)) then return nil end
    return text:GetText()
end

local function Anchor(widget)
    local points = widget and widget.__points or {}
    return points[1]
end

local function GlyphFree(text)
    local stripped = tostring(text):gsub("\194\183", ""):gsub("\226\128\148", "")
    return not stripped:find("[\128-\255]")
end

local drawn = {}
local function Note(text) if text then drawn[#drawn + 1] = text end end

local JOB = { id = 9355, title = "A Job for an Intelligent Man", money = 1200, text = "Danath needs a scout." }
local NOTHING = { id = 91001, title = "Scout the Perimeter", money = 300 }
local MARKS = { id = 10326, title = "More Marks of Kil'jaeden", items = 0 }
local BARE = { id = 91001, title = "Scout the Perimeter" }              -- no money, no items: no rewards frame

-- ===========================================================================
-- A. Loading
-- ===========================================================================

local added = Boot()
CHECK(#loadErrors == 0, "A: the file loads", loadErrors[1])
CHECK(#added == 0, "A: it adds no global", table.concat(added, ","))
CHECK(type(Q.QuestFrame) == "table" and Q.QuestFrame._State().hooked == true,
    "A: the dialog is hooked at load (Blizzard's panels load before every addon)")
CHECK(A.State() == "READY", "A: the fake Questie is ready", A.State())
CHECK(Holder() == nil, "A: nothing is built before the dialog first shows")

-- ===========================================================================
-- B. The offer
-- ===========================================================================

dialog.Offer(JOB)
local holder, text = Holder()
CHECK(holder ~= nil and text ~= nil, "B: the line is built on the first offer")
CHECK(Seen() == "Reputation: +275 Honor Hold", "B: a Human sees 250 Honor Hold as +275 (Diplomacy)", Seen())
CHECK(Seen() == "Reputation: " .. A.RepLine(9355), "B: ...the adapter's one line, word for word")
Note(Seen())
CHECK(holder:GetParent() == frames.QuestDetailScrollChildFrame,
    "B: it is a child of the scroll child the dialog draws into")
local point = Anchor(holder)
CHECK(point and point.point == "TOPLEFT" and point.rel == frames.QuestInfoRewardsFrame and point.relPoint == "BOTTOMLEFT"
    and point.x == 0 and point.y == -10, "B: under the rewards, 10 px down, at their left edge",
    point and (tostring(point.rel and point.rel.__name) .. " " .. tostring(point.y)))
CHECK(holder.__name == nil and text.__name == nil, "B: nameless: no global frame")
CHECK(text.__template == "GameFontNormal" or text.__template == "QuestFont", "B: the dialog's own font where it has one",
    text.__template)
local c = text.__color or {}
CHECK(c[1] == 0.18 and c[2] == 0.12 and c[3] == 0.06, "B: the parchment's own ink (GetMaterialTextColors)",
    table.concat(c, ","))
CHECK(text:GetWidth() == 275, "B: as wide as the detail template's content", text:GetWidth())
CHECK(holder:GetHeight() >= 12, "B: the frame is as tall as its text, so the scroll reaches it", holder:GetHeight())
-- the detail panel holds its rewards back until the description has typed out
local onUpdate = holder.__scripts.OnUpdate
CHECK(type(onUpdate) == "function", "B: while the description types out, the line follows the fade")
onUpdate(holder, 0.016)
CHECK(holder:GetAlpha() == 0, "B: ...hidden with the rewards", holder:GetAlpha())
dialog.FinishFade()
onUpdate(holder, 0.016)
CHECK(holder:GetAlpha() == 1, "B: ...and in with them", holder:GetAlpha())
CHECK(Q.QuestFrame._State().panel == "DETAIL" and Q.QuestFrame._State().questId == 9355, "B: state: the detail panel, 9355")

-- ===========================================================================
-- C. The turn-in
-- ===========================================================================

dialog.TurnIn(JOB)
CHECK(not dialog.Visible(frames.QuestFrameDetailPanel) and dialog.Visible(frames.QuestFrameRewardPanel),
    "C: the dialog moved to its reward panel")
CHECK(Seen() == "Reputation: +275 Honor Hold", "C: the turn-in says the same", Seen())
CHECK(holder:GetParent() == frames.QuestRewardScrollChildFrame, "C: ...in the reward panel's scroll child")
point = Anchor(holder)
CHECK(point and point.rel == frames.QuestInfoRewardsFrame, "C: ...under its rewards")
CHECK(holder.__scripts.OnUpdate == nil and holder:GetAlpha() == 1, "C: no fade to follow on the reward panel")
CHECK(Q.QuestFrame._State().panel == "REWARD", "C: state: the reward panel")

-- ===========================================================================
-- D. What it says
-- ===========================================================================

dialog.Offer(NOTHING)
CHECK(Seen() == "No reputation", "D: a quest that pays nothing says so", Seen())
Note(Seen())
dialog.Offer(MARKS)
CHECK(Seen() == "Reputation:\n+275 The Aldor\n-302 The Scryers\n+137 The Sha'tar",
    "D: every faction it moves, the rival's loss and the spillover included, one per line", Seen())
CHECK(Seen():gsub("^Reputation:\n", "Reputation: "):gsub("\n", "  ") == "Reputation: " .. A.RepLine(10325),
    "D: ...the adapter's one line word for word, never a gain wrapped away from its faction in 275 px", Seen())
Note(Seen())
point = Anchor(holder)
CHECK(point and point.rel == frames.QuestInfoObjectivesText and point.relPoint == "BOTTOMLEFT" and point.y == -10,
    "D: no rewards frame: under the last element the dialog chained (the spacer's anchor)",
    point and point.rel and point.rel.__name)
dialog.Offer(BARE)
CHECK(Seen() == "No reputation" and not frames.QuestInfoRewardsFrame:IsShown(), "D: ...a quest with no rewards at all too")
dialog.Offer({ id = 10871, title = "Ally of the Netherwing", money = 0, items = 1 })
CHECK(Seen() == "Reputation: +42,000 Netherwing", "D: Ally of the Netherwing: the audited row, from Hated to 0", Seen())
Note(Seen())

-- ===========================================================================
-- E. Taken away
-- ===========================================================================

dialog.Offer(JOB)
CHECK(Seen() ~= nil, "E: up on the offer")
dialog.Progress()
CHECK(Seen() == nil and Q.QuestFrame._State().panel == nil, "E: the progress panel takes it away")
dialog.TurnIn(JOB)
CHECK(Seen() ~= nil, "E: back on the turn-in")
dialog.Greeting()
CHECK(Seen() == nil, "E: the greeting panel takes it away")
dialog.Offer(JOB)
dialog.LogDisplay()
CHECK(not holder:IsShown() and Q.QuestFrame._State().panel == nil,
    "E: another caller's Display (the same shared frames, its own scroll child) takes it away")
dialog.Offer(JOB)
CHECK(Seen() == "Reputation: +275 Honor Hold" and holder:GetParent() == frames.QuestDetailScrollChildFrame,
    "E: ...and the next offer puts it back where it belongs")
dialog.Close()
CHECK(Seen() == nil and not holder:IsShown(), "E: closing the dialog takes it away")

-- ===========================================================================
-- F. The rewards arriving late
-- ===========================================================================

dialog.Offer({ id = 9355, title = JOB.title })
point = Anchor(holder)
CHECK(point and point.rel ~= frames.QuestInfoRewardsFrame, "F: no rewards yet: under the objectives")
dialog.ItemsArrive({ money = 1200 })
point = Anchor(holder)
CHECK(frames.QuestInfoRewardsFrame:IsShown() and point and point.rel == frames.QuestInfoRewardsFrame,
    "F: QUEST_ITEM_UPDATE lays out the rewards and the line moves under them")
CHECK(Seen() == "Reputation: +275 Honor Hold", "F: ...saying the same")

-- ===========================================================================
-- G. No quest id from the client
-- ===========================================================================

mock.state.log = {
    mock.Header("Hellfire Peninsula"),
    mock.Quest({ title = JOB.title, level = 61, questID = 9355, objectives = {} }),
    mock.Quest({ title = "Scout the Perimeter", level = 61, questID = 91001, objectives = {} }),
}
dialog.TurnIn({ id = 9355, title = JOB.title, money = 1200, questIdOverride = 0 })
CHECK(Seen() == "Reputation: +275 Honor Hold" and Q.QuestFrame._State().questId == 9355,
    "G: a turn-in with no id from the client is found in the log by its title")
dialog.Offer({ id = 9355, title = JOB.title, money = 1200, questIdOverride = 0 })
CHECK(Seen() == nil, "G: an offer with no id gets no line (it is not in the log to be found)")
-- a second quest of that title that pays something else (the Aldor's)
table.insert(mock.state.log, mock.Quest({ title = JOB.title, level = 65, questID = 10325, objectives = {} }))
dialog.TurnIn({ id = 9355, title = JOB.title, money = 1200, questIdOverride = 0 })
CHECK(Seen() == nil, "G: two quests in the log with that title: no guess", Seen())
mock.state.log = {}
dialog.Close()

-- ===========================================================================
-- H. Settings, Questie's readiness, the multiplier, what was seen
-- ===========================================================================

CommanderQuestLogDB.RepInQuestDialog = false
dialog.Offer(JOB)
CHECK(Seen() == nil, "H: Reputation in the Quest Dialog off: no line")
CommanderQuestLogDB.RepInQuestDialog = true
Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
CHECK(Seen() == "Reputation: +275 Honor Hold", "H: turned back on while the dialog is up, the line arrives", Seen())
CommanderQuestLogDB.ShowRepEverywhere = false
Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
CHECK(Seen() == nil, "H: Reputation on Every Quest off: gone at once")
CommanderQuestLogDB.ShowRepEverywhere = nil
CommanderQuestLogDB.EnableQuestLog = false
dialog.Offer(JOB)
CHECK(Seen() == nil, "H: the module switched off: no line")
CommanderQuestLogDB.EnableQuestLog = nil
dialog.Offer(JOB)
CHECK(Seen() ~= nil, "H: ...and back")

-- Invocation of the Wickerman: +10 more, read when it is asked
world.player.auras[24705] = true
mock.Fire("UNIT_AURA", "player")
Settle()
CHECK(Seen() == "Reputation: +300 Honor Hold", "H: the Wickerman on a Human: 120%, and the open dialog says so", Seen())
Note(Seen())
world.player.auras[24705] = nil
mock.Fire("UNIT_AURA", "player")
Settle()
CHECK(Seen() == "Reputation: +275 Honor Hold", "H: ...and back when it fades", Seen())

-- What the calibration saw replaces the data, and says so
CommanderQuestLogChar.RepObserved = { [9355] = { [946] = { raw = 200, n = 1, delta = 220, pct = 110, kind = "DIRECT" } } }
A.Bump("test")
Settle()
CHECK(Seen() == "Reputation: +220 Honor Hold (seen in game)", "H: a sample seen in game overrides the data, and says so",
    Seen())
Note(Seen())
-- Several factions: the word goes on the heading, which speaks for every
-- line under it; at the end it sat on the last faction's line alone (the
-- Sha'tar's), as if only that figure had been seen (2026-10-05 review)
CommanderQuestLogChar.RepObserved = { [10326] = { [932] = { raw = 250, n = 1, delta = 275, pct = 110, kind = "DIRECT" } } }
A.Bump("test")
Settle()
dialog.Offer(MARKS)
CHECK(Seen() == "Reputation (seen in game):\n+275 The Aldor\n-302 The Scryers\n+137 The Sha'tar",
    "H: several factions seen in game: \"(seen in game)\" heads the lines", Seen())
Note(Seen())
CommanderQuestLogChar.RepObserved = nil
A.Bump("test")
Settle()
dialog.Close()

-- Questie still loading when the dialog opens: the line comes when it is ready
Boot({ edit = function(w) w.ready = false end })
CHECK(A.State() == "LOADING", "H: a boot with Questie still loading")
dialog.Offer(JOB)
CHECK(Seen() == nil and Holder() == nil, "H: no line while Questie loads")
fake.SetReady()
Settle()
CHECK(A.State() == "READY" and Seen() == "Reputation: +275 Honor Hold",
    "H: ...and the open dialog gains it once Questie is ready", Seen())
dialog.Close()

-- ===========================================================================
-- I. What cannot be answered
-- ===========================================================================

Boot()
dialog.Offer({ id = 77777, title = "Not a Quest", money = 10 })
CHECK(Seen() == nil, "I: a quest Questie does not know: no line")
dialog.Offer({ id = 0, title = "Nothing", money = 10 })
CHECK(Seen() == nil, "I: no id at all: no line")
-- An error in the line's own code is reported, and the dialog is drawn anyway
local caught = #mock.caughtErrors
local realLine = A.RepLine
A.RepLine = function() error("harness: a broken line") end
dialog.Offer(JOB)
CHECK(#mock.caughtErrors == caught + 1 and tostring(mock.caughtErrors[#mock.caughtErrors]):find("broken line", 1, true),
    "I: an error in the hook is reported to the error handler", mock.caughtErrors[#mock.caughtErrors])
CHECK(frames.QuestInfoTitleHeader:GetText() == JOB.title and dialog.Visible(frames.QuestFrameDetailPanel),
    "I: ...and the dialog is drawn all the same")
CHECK(Q.QuestFrame._State().lastError ~= nil, "I: ...and kept for the record")
A.RepLine = realLine
for i = #mock.caughtErrors, caught + 1, -1 do table.remove(mock.caughtErrors, i) end
dialog.Close()

Boot({ noRules = true })
dialog.Offer(JOB)
CHECK(Seen() == nil and Holder() == nil, "I: without the rules (no data, no engine) there is no number, so no line")
dialog.Close()

Boot({ absent = true })
CHECK(A.State() == "ABSENT", "I: a boot with no Questie")
dialog.Offer(JOB)
CHECK(Seen() == nil and Holder() == nil, "I: no Questie: no line, no error")
CHECK(frames.QuestInfoTitleHeader:GetText() == JOB.title, "I: ...and the dialog itself untouched")
dialog.Close()

-- A client whose dialog is not there at load: hooked at PLAYER_LOGIN
for event in pairs(mock.eventRegistry) do mock.eventRegistry[event] = nil end
CommanderQuestLog = nil
QuestInfo_Display, QuestInfo_ShowRewards, QuestFrameDetailPanel, QuestFrameRewardPanel = nil, nil, nil, nil
QuestInfo_GetRewardButton = nil
local lateOk = pcall(mock.Load, MODULE .. "CommanderQuestLogDB.lua")
lateOk = lateOk and pcall(mock.Load, QUESTFRAME_FILE)
local late = CommanderQuestLog
CHECK(lateOk and late.QuestFrame._State().hooked == false, "I: no dialog at load: the file loads and waits")
dialog = QF.Install(mock)
frames = dialog.frames
mock.Fire("PLAYER_LOGIN")
CHECK(late.QuestFrame._State().hooked == true, "I: ...and hooks it at PLAYER_LOGIN")
QuestInfo_GetRewardButton(frames.QuestInfoRewardsFrame, 3)
CHECK(late.QuestFrame._State().filled == 1 and frames.QuestInfoRewardsFrame.RewardButtons[2] ~= nil,
    "I: ...the reward-button hook with it", late.QuestFrame._State().filled)

-- ===========================================================================
-- J. Another addon's reward button, asked for out of turn (D47)
-- ===========================================================================

-- The slots in a rewards frame's list, in order: "-1,1,2,4"
local function Slots(rewards)
    local keys = {}
    for key in pairs(rewards.RewardButtons) do keys[#keys + 1] = key end
    table.sort(keys)
    for i, key in ipairs(keys) do keys[i] = tostring(key) end
    return table.concat(keys, ",")
end

-- What RXPGuides 4.11 does from its quest-log hook (SelectQuestLogEntry, which
-- the window's model calls on every read): asks the dialog's factory for its
-- gold pick, a log choice number, and for -1 when it has no upgrade pick
local function TheirMarks(rewards)
    QuestInfo_GetRewardButton(rewards, 4)
    QuestInfo_GetRewardButton(rewards, -1)
end

local TWO = { id = 10326, title = "More Marks of Kil'jaeden", money = 500, items = 2 }
local WANTED = { id = 9355, title = JOB.title, money = 163900, items = 1 }      -- the report's shape: one item, 16g 39s

-- Without the hook: the stock dialog alone, the hole, and the report's error
for event in pairs(mock.eventRegistry) do mock.eventRegistry[event] = nil end
local bare = QF.Install(mock)
bare.TurnIn(TWO)
TheirMarks(bare.frames.QuestInfoRewardsFrame)
CHECK(Slots(bare.frames.QuestInfoRewardsFrame) == "-1,1,2,4", "J: unguarded, their marks leave the report's list",
    Slots(bare.frames.QuestInfoRewardsFrame))
local bareOk, bareErr = pcall(bare.Offer, WANTED)
CHECK(not bareOk and tostring(bareErr):find("index", 1, true),
    "J: ...and the next dialog dies on slot 3 (the mock breaks as the client did)", bareErr)

Boot()
local rewards = frames.QuestInfoRewardsFrame
dialog.TurnIn(TWO)
CHECK(Slots(rewards) == "1,2" and Q.QuestFrame._State().filled == 0,
    "J: Blizzard's own calls (1, 2 in turn) fill nothing", Slots(rewards))
TheirMarks(rewards)
CHECK(Slots(rewards) == "-1,1,2,3,4", "J: their marks: the hole under 4 is filled, -1 is left where it is", Slots(rewards))
CHECK(Q.QuestFrame._State().filled == 1, "J: ...one button made", Q.QuestFrame._State().filled)
local third = rewards.RewardButtons[3]
CHECK(third and third.__name == "QuestInfoRewardsFrameQuestInfoItem3" and third.__shown == false,
    "J: ...by Blizzard's own factory, under its own name, hidden until the dialog lays it out")
dialog.Close()
local ok, err = pcall(dialog.Offer, WANTED)
CHECK(ok, "J: the next dialog draws (one reward, as in the report)", err)
local function SlotShown(slot)
    local button = rewards.RewardButtons[slot]
    return button ~= nil and button.__shown
end
CHECK(SlotShown(1) and not SlotShown(2) and not SlotShown(3) and not SlotShown(4),
    "J: ...its one reward shown, every slot above hidden")
CHECK(Seen() == "Reputation: +275 Honor Hold", "J: ...and the line under it", Seen())
dialog.Close()
ok, err = pcall(dialog.TurnIn, { id = 10326, title = TWO.title, items = 3, choices = 2 })
CHECK(ok and Slots(rewards) == "-1,1,2,3,4,5" and Q.QuestFrame._State().filled == 1,
    "J: a quest with five rewards uses the filled slot and makes the fifth itself", Slots(rewards))
dialog.Close()

-- No reward slot is invented: a fraction, 0, and past the most a quest has
QuestInfo_GetRewardButton(rewards, 7.5)
QuestInfo_GetRewardButton(rewards, 0)
QuestInfo_GetRewardButton(rewards, 12)
CHECK(Q.QuestFrame._State().filled == 1 and rewards.RewardButtons[6] == nil,
    "J: a fraction, 0 and slot 12 (past MAX_NUM_ITEMS) fill nothing", Q.QuestFrame._State().filled)
CHECK(#dialog.writes == 0, "J: no field written by the module's own code", table.concat(dialog.writes, ","))
CHECK(#mock.caughtErrors == 0, "J: no error reported", mock.caughtErrors[1])

-- ===========================================================================
-- Hygiene
-- ===========================================================================

Boot()
dialog.Offer(JOB)
dialog.TurnIn(JOB)
dialog.ItemsArrive({ items = 2 })
dialog.Progress()
dialog.Close()
CHECK(#dialog.writes == 0, "no field written on any Blizzard frame or template", table.concat(dialog.writes, ","))
local bad = {}
for _, line in ipairs(drawn) do if not GlyphFree(line) then bad[#bad + 1] = line end end
CHECK(#bad == 0, "no shape glyph in any line drawn", bad[1])
CHECK(#loadErrors == 0, "no load error", loadErrors[1])
CHECK(#mock.caughtErrors == 0, "no error reported", mock.caughtErrors[1])
CHECK(fake and #fake.forbidden == 0, "no forbidden Questie call", fake and table.concat(fake.forbidden, ","))

Done()

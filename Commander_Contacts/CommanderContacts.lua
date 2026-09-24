-- Commander Contacts: the host.
--
-- The store keeps the record and the window shows it; this file is the part
-- that talks to the client. It listens to the chat events and files every
-- whisper and party line into the right thread, keeps a "party session"
-- open for as long as you are in a group so its lines land in one place,
-- and wraps the friends, ignore and Battle.net lists behind small functions
-- the window can call without caring which of three API generations this
-- client ships.
--
-- Every client call is guarded. A function this client turns out not to
-- have costs a feature -- no Battle.net column, no invite button -- never a
-- window that fails to open. Every event registration is its own pcall
-- because a throw inside a registration loop silently drops every event
-- after it (Tradecraft learned that one the hard way).

CommanderContacts = CommanderContacts or {}
local H = CommanderContacts
local S = CommanderContactsStore
local T = CommanderContactsScout

local frame = CreateFrame("Frame")

local function DB()
    return CommanderContactsDB or {}
end

local function Enabled()
    return DB().EnableContacts ~= false
end

local function Ready()
    return S and S.Attached and S.Attached()
end

local function Notify(event, ...)
    if Commander and Commander.Notify and COMMANDER_CONTACTS_EVENTS then
        Commander.Notify(event, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

local ownRealm, ownName

function H.OwnRealm()
    if ownRealm then return ownRealm end
    local realm
    if GetNormalizedRealmName then
        local ok, value = pcall(GetNormalizedRealmName)
        if ok and type(value) == "string" and value ~= "" then realm = value end
    end
    if not realm and GetRealmName then
        local ok, value = pcall(GetRealmName)
        if ok and type(value) == "string" then realm = value:gsub("[%s%-]", "") end
    end
    ownRealm = realm or ""
    return ownRealm
end

function H.OwnName()
    if ownName then return ownName end
    local name = UnitName and UnitName("player")
    if type(name) == "string" and name ~= "" then ownName = name end
    return ownName or "You"
end

-- "Name-Realm" -> "Name" for people on this realm, untouched for anyone
-- else. Ambiguate is the client's own answer to exactly this question; the
-- store's version is the fallback for a client without it.
function H.Shorten(fullName)
    if type(fullName) ~= "string" then return "" end
    if Ambiguate then
        local ok, short = pcall(Ambiguate, fullName, "none")
        if ok and type(short) == "string" and short ~= "" then return short end
    end
    return S.Shorten(fullName, H.OwnRealm())
end

function H.IsSelf(name)
    if type(name) ~= "string" then return false end
    return H.Shorten(name) == H.OwnName()
end

-- Localised class name -> class token, for the friends list, which only
-- answers "Mage" in the client's language. Built once from the two tables
-- the client provides; a name that matches neither is upper-cased, which is
-- right for English and harmless elsewhere.
local classTokens

local function TokenForClassName(className)
    if type(className) ~= "string" or className == "" then return nil end
    if not classTokens then
        classTokens = {}
        for _, tableName in ipairs({ "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE" }) do
            local map = _G[tableName]
            if type(map) == "table" then
                for token, localised in pairs(map) do classTokens[localised] = token end
            end
        end
    end
    return classTokens[className] or className:upper():gsub("%s", "")
end
H.TokenForClassName = TokenForClassName

function H.ClassOf(guid)
    if not (guid and guid ~= "" and GetPlayerInfoByGUID) then return nil end
    local ok, _, token = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(token) == "string" and token ~= "" then return token end
    return nil
end

-- ---------------------------------------------------------------------------
-- Friends, ignores and Battle.net, read live
-- ---------------------------------------------------------------------------

local friendSet, ignoreSet = nil, nil

function H.Friends()
    local list = {}
    if not (C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex) then
        return list
    end
    local ok, count = pcall(C_FriendList.GetNumFriends)
    if not ok then return list end
    for index = 1, (count or 0) do
        local okInfo, info = pcall(C_FriendList.GetFriendInfoByIndex, index)
        if okInfo and type(info) == "table" and info.name then
            list[#list + 1] = {
                name = info.name,
                connected = info.connected and true or false,
                className = info.className,
                class = TokenForClassName(info.className),
                level = tonumber(info.level) or 0,
                area = info.area,
                notes = info.notes,
                guid = info.guid,
                afk = info.afk and true or false,
                dnd = info.dnd and true or false,
            }
        end
    end
    return list
end

function H.BNFriends()
    local list = {}
    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
        return list
    end
    local ok, total = pcall(BNGetNumFriends)
    if not ok then return list end
    for index = 1, (total or 0) do
        local okInfo, account = pcall(C_BattleNet.GetFriendAccountInfo, index)
        if okInfo and type(account) == "table" then
            local game = type(account.gameAccountInfo) == "table" and account.gameAccountInfo or {}
            list[#list + 1] = {
                bnetID = account.bnetAccountID,
                name = account.accountName or account.battleTag or ("Battle.net " .. tostring(account.bnetAccountID)),
                battleTag = account.battleTag,
                note = account.note,
                afk = account.isAFK and true or false,
                dnd = account.isDND and true or false,
                custom = account.customMessage,
                online = game.isOnline and true or false,
                character = game.characterName,
                className = game.className,
                class = TokenForClassName(game.className),
                level = tonumber(game.characterLevel) or 0,
                area = game.areaName,
                client = game.clientProgram,
                realm = game.realmDisplayName or game.realmName,
                gameAccountID = game.gameAccountID,
            }
        end
    end
    return list
end

function H.Ignores()
    local list = {}
    if not (C_FriendList and C_FriendList.GetNumIgnores and C_FriendList.GetIgnoreName) then
        return list
    end
    local ok, count = pcall(C_FriendList.GetNumIgnores)
    if not ok then return list end
    for index = 1, (count or 0) do
        local okName, name = pcall(C_FriendList.GetIgnoreName, index)
        if okName and type(name) == "string" and name ~= "" then
            list[#list + 1] = { name = name, short = H.Shorten(name) }
        end
    end
    return list
end

local function RebuildSets()
    friendSet, ignoreSet = {}, {}
    for _, friend in ipairs(H.Friends()) do friendSet[H.Shorten(friend.name)] = true end
    for _, entry in ipairs(H.Ignores()) do ignoreSet[entry.short] = true end
end

function H.FriendSet()
    if not friendSet then RebuildSets() end
    return friendSet
end

function H.IsFriend(name)
    return H.FriendSet()[H.Shorten(name)] and true or false
end

function H.IsIgnored(name)
    if not ignoreSet then RebuildSets() end
    return ignoreSet[H.Shorten(name)] and true or false
end

-- Ask the server for a fresh friends list. Blizzard's own frame does this
-- when it opens; the list is otherwise only pushed at login.
function H.RequestFriends()
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end

-- ----- verbs ------------------------------------------------------------

local function Say(text)
    print("Commander Contacts: " .. text)
end

function H.AddFriend(name, notes)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return false, "type a name first." end
    if H.IsSelf(name) then return false, "that is you." end
    if not (C_FriendList and C_FriendList.AddFriend) then return false, "this client has no friends API." end
    local ok = pcall(C_FriendList.AddFriend, name, notes)
    return ok, ok and nil or "the client refused that name."
end

function H.RemoveFriend(name)
    if not (C_FriendList and C_FriendList.RemoveFriend) then return false end
    local ok, removed = pcall(C_FriendList.RemoveFriend, name)
    return ok and removed ~= false
end

function H.SetFriendNotes(name, notes)
    if not (C_FriendList and C_FriendList.SetFriendNotes) then return false end
    local ok, found = pcall(C_FriendList.SetFriendNotes, name, notes or "")
    return ok and found ~= false
end

function H.AddIgnore(name)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if name == "" then return false, "type a name first." end
    if H.IsSelf(name) then return false, "that is you." end
    if not (C_FriendList and C_FriendList.AddIgnore) then return false, "this client has no ignore API." end
    local ok, added = pcall(C_FriendList.AddIgnore, name)
    if not ok then return false, "the client refused that name." end
    return added ~= false, added == false and "already ignored, or the name is unknown." or nil
end

function H.RemoveIgnore(name)
    if not (C_FriendList and C_FriendList.DelIgnore) then return false end
    local ok, removed = pcall(C_FriendList.DelIgnore, name)
    return ok and removed ~= false
end

function H.Invite(conv)
    if not conv then return false end
    if conv.kind == "bn" then
        local id = conv.gameAccountID
        if not id then
            for _, friend in ipairs(H.BNFriends()) do
                if friend.bnetID == conv.target then id = friend.gameAccountID break end
            end
        end
        if id and C_BattleNet and C_BattleNet.InviteFriend then
            return pcall(C_BattleNet.InviteFriend, id)
        end
        return false
    end
    local name = conv.target or conv.name
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        return pcall(C_PartyInfo.InviteUnit, name)
    elseif InviteUnit then
        return pcall(InviteUnit, name)
    end
    return false
end

-- Put "/w Name " in the chat box, for people who would rather type there.
function H.OpenChatTo(conv)
    if not conv or conv.kind == "group" then return false end
    if conv.kind == "bn" then
        -- The chat box wants a tokenised Battle.net name we do not hold; the
        -- window's own compose box is the way to reach an account.
        return false
    end
    local name = conv.target or conv.name
    local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if sendTell then return pcall(sendTell, name) end
    return false
end

-- What channel the live group speaks on.
local function GroupType()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE"
    end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end
H.GroupType = GroupType

-- Send a line to a thread. Nothing is written to the store here: the client
-- echoes what you sent back as CHAT_MSG_WHISPER_INFORM (or, for a group,
-- as the same party event everyone else gets), and that echo is the record.
-- Logging here as well would print every line twice.
function H.Send(conv, text)
    text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if not conv or text == "" then return false end
    if conv.kind == "dm" then
        if not SendChatMessage then return false, "this client cannot send from an addon." end
        local ok = pcall(SendChatMessage, text, "WHISPER", nil, conv.target or conv.name)
        return ok, ok and nil or "the whisper was refused."
    elseif conv.kind == "bn" then
        local id = tonumber(conv.target)
        if not id then return false, "no Battle.net account on this thread." end
        if C_BattleNet and C_BattleNet.SendWhisper then
            local ok, sent = pcall(C_BattleNet.SendWhisper, id, text)
            return ok and sent ~= false, (ok and sent ~= false) and nil or "Battle.net refused the whisper."
        elseif BNSendWhisper then
            local ok = pcall(BNSendWhisper, id, text)
            return ok, ok and nil or "Battle.net refused the whisper."
        end
        return false, "this client has no Battle.net whisper."
    elseif conv.kind == "group" then
        local active = S.ActiveGroup()
        if not active or active.key ~= conv.key then return false, "this party has ended." end
        local groupType = GroupType()
        if not groupType then return false, "you are not in a group." end
        local channel = groupType == "INSTANCE" and "INSTANCE_CHAT" or groupType == "RAID" and "RAID" or "PARTY"
        local ok = pcall(SendChatMessage, text, channel)
        return ok, ok and nil or "the message was refused."
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Party sessions
--
-- A group thread opens the moment the roster says you are in a group and
-- closes when it says you are not. Everything said on party, raid,
-- battleground or raid-warning in between is one conversation, the way a
-- Slack channel is one conversation. The active key is in the DB so a
-- /reload mid-dungeon continues the same thread rather than starting a
-- second one.
-- ---------------------------------------------------------------------------

local function RosterNames()
    local names = {}
    if not GetNumGroupMembers then return names end
    local count = GetNumGroupMembers() or 0
    local me = H.OwnName()
    if IsInRaid and IsInRaid() then
        for index = 1, count do
            local name = UnitName and UnitName("raid" .. index)
            if type(name) == "string" and name ~= "" and name ~= me and name ~= UNKNOWNOBJECT then
                names[#names + 1] = H.Shorten(name)
            end
        end
    else
        for index = 1, math.max(count - 1, 0) do
            local name = UnitName and UnitName("party" .. index)
            if type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT then
                names[#names + 1] = H.Shorten(name)
            end
        end
    end
    return names
end

function H.SyncGroup()
    if not Ready() then return end
    local groupType = GroupType()
    local active = S.ActiveGroup()
    if groupType then
        if not active then
            if DB().LogGroups == false then return end
            active = S.StartGroup(groupType, RosterNames())
            Notify(COMMANDER_CONTACTS_EVENTS.ROSTER, active.key)
        else
            local changed = S.SetGroupType(active.key, groupType)
            local added = S.AddMembers(active.key, RosterNames())
            if changed or added > 0 then Notify(COMMANDER_CONTACTS_EVENTS.ROSTER, active.key) end
        end
    elseif active then
        S.CloseGroup(active.key)
        Notify(COMMANDER_CONTACTS_EVENTS.ROSTER, active.key)
    end
end

-- ---------------------------------------------------------------------------
-- Filing chat
-- ---------------------------------------------------------------------------

local GROUP_CHANNELS = {
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "LEADER",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID_LEADER",
    CHAT_MSG_RAID_WARNING = "RAID_WARNING",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_LEADER",
}

local function FileWhisper(text, who, guid, outgoing)
    if not Ready() or not Enabled() then return end
    if DB().LogWhispers == false then return end
    if outgoing and DB().LogOutgoing == false then return end
    if type(who) ~= "string" or who == "" then return end
    local short = H.Shorten(who)
    local class = H.ClassOf(guid)
    local conv = S.EnsureDM(short, { target = who, guid = guid, class = class })
    if not conv then return end
    local entry = S.Append(conv.key, {
        from = outgoing and H.OwnName() or short,
        text = text,
        out = outgoing or nil,
        cls = outgoing and H.ClassOf(UnitGUID and UnitGUID("player")) or class,
        ch = "WHISPER",
    })
    if entry then Notify(COMMANDER_CONTACTS_EVENTS.MESSAGE, conv.key, entry) end
end

local function FileBattleNet(text, who, bnetID, outgoing)
    if not Ready() or not Enabled() then return end
    if DB().LogBattleNet == false then return end
    if outgoing and DB().LogOutgoing == false then return end
    bnetID = tonumber(bnetID)
    if not bnetID then return end
    -- The name in the event is a tokenised "|Kq12|k...|k" string that only a
    -- FontString can render; the account record has the real name. The
    -- token is kept as the fallback because it still draws correctly.
    local name = S.PlainText(who)
    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local ok, account = pcall(C_BattleNet.GetAccountInfoByID, bnetID)
        if ok and type(account) == "table" then
            local real = account.accountName or account.battleTag
            if type(real) == "string" and real ~= "" then name = real end
        end
    end
    local conv = S.EnsureBN(bnetID, name)
    if not conv then return end
    local entry = S.Append(conv.key, {
        from = outgoing and H.OwnName() or conv.name,
        text = text,
        out = outgoing or nil,
        ch = "BN",
    })
    if entry then Notify(COMMANDER_CONTACTS_EVENTS.MESSAGE, conv.key, entry) end
end

local function FileGroup(channel, text, who, guid)
    if not Ready() or not Enabled() then return end
    if DB().LogGroups == false then return end
    if type(who) ~= "string" or who == "" then return end
    local conv = S.ActiveGroup()
    if not conv then
        -- A line arrived before the roster event did. Open the session from
        -- the line itself rather than lose it.
        conv = S.StartGroup(GroupType() or "PARTY", RosterNames())
        Notify(COMMANDER_CONTACTS_EVENTS.ROSTER, conv.key)
    end
    local short = H.Shorten(who)
    local outgoing = H.IsSelf(who)
    if not outgoing then S.AddMembers(conv.key, { short }) end
    local entry = S.Append(conv.key, {
        from = short,
        text = text,
        out = outgoing or nil,
        cls = H.ClassOf(guid),
        ch = channel,
    })
    if entry then Notify(COMMANDER_CONTACTS_EVENTS.MESSAGE, conv.key, entry) end
end

-- ---------------------------------------------------------------------------
-- Scouting battlegrounds
--
-- Three feeds into the scout. The scoreboard, read once per battleground
-- the moment a winner is declared (UPDATE_BATTLEFIELD_SCORE fires for
-- Blizzard's own board, so nothing has to be asked for). The titles of
-- the people on your side, read off UnitPVPName on every roster change
-- inside a battleground. And, when Commander_Muster is installed, the arena
-- ratings it reads by inspecting whoever you mouse over -- its RECORD
-- event names the GUID and RecordFor hands back the ratings.
-- ---------------------------------------------------------------------------

local matchRecorded = false

local function InBattleground()
    if not IsInInstance then return false end
    local _, instanceType = IsInInstance()
    return instanceType == "pvp"
end
H.InBattleground = InBattleground

local function OwnFaction()
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if faction == "Horde" then return "HORDE" end
    if faction == "Alliance" then return "ALLIANCE" end
    return nil
end

local function ScoutContext()
    return {
        own = H.OwnName(),
        ownRealm = H.OwnRealm(),
        ownFaction = OwnFaction(),
        friends = H.FriendSet(),
        map = GetRealZoneText and GetRealZoneText() or nil,
        now = time(),
    }
end

local function Scouting()
    return Ready() and Enabled() and DB().SuggestFriends ~= false and T and T.Attached and T.Attached()
end

-- Read the whole board. Returns the number of rows read, or nil if the
-- board is not available on this client.
function H.ReadScoreboard()
    if not (GetNumBattlefieldScores and GetBattlefieldScore) then return nil end
    local ok, count = pcall(GetNumBattlefieldScores)
    if not ok or (count or 0) <= 0 then return 0 end
    local rows = {}
    for index = 1, count do
        -- name, killingBlows, honorableKills, deaths, honorGained, faction,
        -- rank, race, class, classToken, damageDone, healingDone -- the order
        -- Blizzard's own TBC WorldStateFrame reads them in. faction 0 is
        -- Horde and 1 is Alliance.
        local okRow, name, killingBlows, _, _, _, faction, _, _, _, classToken, damageDone, healingDone =
            pcall(GetBattlefieldScore, index)
        if okRow and name then
            rows[#rows + 1] = {
                name = name,
                faction = faction == 1 and "ALLIANCE" or (faction == 0 and "HORDE" or nil),
                class = classToken,
                dmg = tonumber(damageDone) or 0,
                heal = tonumber(healingDone) or 0,
                kb = tonumber(killingBlows) or 0,
            }
        end
    end
    return #rows, rows
end

local function OnScoreboard()
    if not Scouting() or matchRecorded then return end
    if not (GetBattlefieldWinner and GetBattlefieldWinner()) then return end
    if not InBattleground() then return end
    local count, rows = H.ReadScoreboard()
    if not rows or count == 0 then return end
    matchRecorded = true
    local touched = T.RecordMatch(rows, ScoutContext())
    if touched > 0 then Notify(COMMANDER_CONTACTS_EVENTS.ROSTER) end
end

-- "Gladiator Bob" -> "Gladiator". Titles are only ever learned: an empty
-- prefix is a player hiding a title they may still hold.
local function TitleOf(unit)
    if not (UnitPVPName and UnitName) then return nil, nil end
    local okName, name = pcall(UnitName, unit)
    local okTitle, pvpName = pcall(UnitPVPName, unit)
    if not (okName and okTitle) or type(name) ~= "string" or type(pvpName) ~= "string" then return nil, nil end
    if name == "" or name == UNKNOWNOBJECT then return nil, nil end
    local prefix = pvpName:sub(1, #pvpName - #name)
    if pvpName:sub(-#name) ~= name then return name, nil end
    prefix = prefix:gsub("[%s,]+$", "")
    return name, prefix ~= "" and prefix or nil
end

function H.ScoutTitles()
    if not Scouting() or not InBattleground() then return 0 end
    if not (IsInRaid and IsInRaid() and GetNumGroupMembers) then return 0 end
    local ctx = ScoutContext()
    local noted = 0
    for index = 1, (GetNumGroupMembers() or 0) do
        local unit = "raid" .. index
        local name, title = TitleOf(unit)
        if name and title then
            local _, class = UnitClass(unit)
            ctx.class = class
            if T.NoteTitle(name, title, ctx) then noted = noted + 1 end
        end
    end
    if noted > 0 then Notify(COMMANDER_CONTACTS_EVENTS.ROSTER) end
    return noted
end

-- Commander_Muster's record for a GUID: ratings per team size when its
-- inspect has read the honor page.
local function OnMusterRecord(guid)
    if not Scouting() or not guid then return end
    local muster = _G.CommanderMuster
    if not (muster and type(muster.RecordFor) == "function") then return end
    local ok, record = pcall(muster.RecordFor, guid)
    if not (ok and type(record) == "table" and type(record.name) == "string") then return end
    if type(record.arena) ~= "table" then return end
    local ratings = {}
    local any = false
    for size, entry in pairs(record.arena) do
        if type(size) == "number" and type(entry) == "table" and (tonumber(entry.rating) or 0) > 0 then
            ratings[size] = tonumber(entry.rating)
            any = true
        end
    end
    if not any then return end
    local ctx = ScoutContext()
    ctx.class = record.class
    if T.NoteRatings(record.name, ratings, ctx) then Notify(COMMANDER_CONTACTS_EVENTS.ROSTER) end
end
H.OnMusterRecord = OnMusterRecord

function H.Suggestions()
    if not Scouting() then return {} end
    return T.Suggestions(DB().SuggestCount or 10, { friends = H.FriendSet(), now = time() })
end

function H.DismissSuggestion(name)
    if not (T and T.Attached and T.Attached()) then return false end
    local ok = T.Dismiss(name)
    if ok then Notify(COMMANDER_CONTACTS_EVENTS.ROSTER) end
    return ok
end

function H.ForgetSuggestions()
    if not (T and T.Attached and T.Attached()) then return 0 end
    local count = T.ForgetAll()
    Say(string.format("forgot %d performer record%s.", count, count == 1 and "" or "s"))
    Notify(COMMANDER_CONTACTS_EVENTS.ROSTER)
    return count
end

-- ---------------------------------------------------------------------------
-- A way in from Blizzard's own window
--
-- The Classic friends window is 384 wide and both its Friends and Ignore
-- tabs put one 131px button in each bottom corner, leaving a gap of about
-- 110px between them that nothing uses. One "Contacts" button goes in that
-- gap on each tab, parented to the tab's own sub-frame so it appears and
-- disappears with the tab and never has to be told which one is showing.
-- Nothing protected is touched: a plain button on a Blizzard frame that
-- opens ours on the matching tab.
-- ---------------------------------------------------------------------------

local friendsButtons = {}

local function MakeFriendsFrameButton(parent, leftOf, rightOf, tab, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetHeight(21)
    button:SetPoint("LEFT", leftOf, "RIGHT", 4, 0)
    button:SetPoint("RIGHT", rightOf, "LEFT", -4, 0)
    button:SetText("Contacts")
    button:SetScript("OnClick", function()
        local fn = _G.CommanderContacts_ShowTab
        if type(fn) == "function" then fn(tab) end
    end)
    if Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(button, "Commander Contacts", tooltip, "ANCHOR_TOP")
    end
    return button
end

function H.RefreshFriendsFrameButtons()
    local shown = Enabled() and DB().FriendsFrameButton ~= false
    for _, button in pairs(friendsButtons) do
        button:SetShown(shown)
    end
end

function H.InstallFriendsFrameButtons()
    if next(friendsButtons) then return friendsButtons end
    if FriendsListFrame and FriendsFrameAddFriendButton and FriendsFrameSendMessageButton then
        friendsButtons.friends = MakeFriendsFrameButton(FriendsListFrame,
            FriendsFrameAddFriendButton, FriendsFrameSendMessageButton, "friends",
            "Open the Contacts window on its Friends tab (also: /cfriends).")
    end
    if IgnoreListFrame and FriendsFrameIgnorePlayerButton and FriendsFrameUnsquelchButton then
        friendsButtons.ignore = MakeFriendsFrameButton(IgnoreListFrame,
            FriendsFrameIgnorePlayerButton, FriendsFrameUnsquelchButton, "ignore",
            "Open the Contacts window on its Ignore tab.")
    end
    H.RefreshFriendsFrameButtons()
    return friendsButtons
end

function H.FriendsFrameButtons()
    return friendsButtons
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local EVENTS = {
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT",
    "FRIENDLIST_UPDATE", "IGNORELIST_UPDATE",
    "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE",
    "BN_FRIEND_LIST_SIZE_CHANGED",
    "UPDATE_BATTLEFIELD_SCORE",
}

for _, event in ipairs(EVENTS) do
    pcall(frame.RegisterEvent, frame, event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ownName, ownRealm = nil, nil
        H.OwnName()
        H.OwnRealm()
        H.RequestFriends()
        H.SyncGroup()
        H.InstallFriendsFrameButtons()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE"
        or event == "GROUP_JOINED" or event == "GROUP_LEFT" then
        H.SyncGroup()
        -- Idempotent: a second chance for the friends-window buttons in case
        -- Blizzard's window was not built yet at PLAYER_LOGIN.
        if event == "PLAYER_ENTERING_WORLD" then
            H.InstallFriendsFrameButtons()
            -- A new battleground is a new board
            if not InBattleground() then matchRecorded = false end
        end
        if event == "GROUP_ROSTER_UPDATE" then H.ScoutTitles() end
    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        OnScoreboard()
    elseif event == "CHAT_MSG_WHISPER" then
        local text, who, _, _, _, _, _, _, _, _, _, guid = ...
        FileWhisper(text, who, guid, false)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local text, who, _, _, _, _, _, _, _, _, _, guid = ...
        FileWhisper(text, who, guid, true)
    elseif event == "CHAT_MSG_BN_WHISPER" then
        local text, who, _, _, _, _, _, _, _, _, _, _, bnetID = ...
        FileBattleNet(text, who, bnetID, false)
    elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
        local text, who, _, _, _, _, _, _, _, _, _, _, bnetID = ...
        FileBattleNet(text, who, bnetID, true)
    elseif GROUP_CHANNELS[event] then
        local text, who, _, _, _, _, _, _, _, _, _, guid = ...
        FileGroup(GROUP_CHANNELS[event], text, who, guid)
    elseif event == "FRIENDLIST_UPDATE" or event == "IGNORELIST_UPDATE"
        or event == "BN_FRIEND_INFO_CHANGED" or event == "BN_FRIEND_ACCOUNT_ONLINE"
        or event == "BN_FRIEND_ACCOUNT_OFFLINE" or event == "BN_FRIEND_LIST_SIZE_CHANGED" then
        RebuildSets()
        Notify(COMMANDER_CONTACTS_EVENTS.ROSTER)
    end
end)

if Commander and Commander.AddListener and COMMANDER_CONTACTS_EVENTS then
    Commander.AddListener(COMMANDER_CONTACTS_EVENTS.UPDATE, H.RefreshFriendsFrameButtons)
    -- Muster is optional: its event table only exists when it is installed
    -- and, thanks to OptionalDeps, loaded before this file.
    local musterEvents = _G.COMMANDER_MUSTER_EVENTS
    if type(musterEvents) == "table" and musterEvents.RECORD then
        Commander.AddListener(musterEvents.RECORD, OnMusterRecord)
    end
end

-- Exposed for the harness and for anything that wants to file a line by
-- hand (a future Comms hook, say).
H.FileWhisper = FileWhisper
H.FileBattleNet = FileBattleNet
H.FileGroup = FileGroup
H.RosterNames = RosterNames
H.Say = Say

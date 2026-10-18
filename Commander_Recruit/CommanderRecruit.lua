-- Commander Recruit — rated players online right now, by bracket.
--
-- The judgement is in CommanderRecruitEngine.lua; this file is the client
-- half: where sightings come from, the sweep's /who traffic, and the window.
--
-- Where "online" comes from. Nothing in the client lists everyone logged in,
-- so the book is filled from every place a player can only appear while they
-- are on, each its own switch: /who results (a sweep's or your own), the
-- group finder's listings, chat channel lines, the guild roster's and the
-- friends list's online flags, and friendly players under your cursor, on
-- your target or on a nameplate. All of them are your faction already, bar
-- say and yell, which are filtered by race.
--
-- Ratings are Commander Muster's (its RatingsFor merges what it has seen in
-- game with Commander Ladder's web feed); without Muster, Ladder is read
-- directly. A player Muster cannot rate is handed to the feed by Muster
-- itself, so tomorrow's run looks them up.
--
-- The sweep is aimed by Commander Ladder's roster of the realm's rated
-- players when the feed has described them (R20): arena zones, their guilds,
-- their class/race pairs, whichever should turn up the most not yet seen.
-- Without it, the fixed plan: every class, split by race past the cap.

local E = CommanderRecruit_Engine

local db
local book = E.NewBook()
local homeRealm, faction
local sweep, awaiting
local learned = E.NewLearned()  -- what /who has taught this session (R20), kept across sweeps
local lastSend = -100
local friendsWasShown
local frame = CreateFrame("Frame")
local window
local dirty = true

local WHO_GAP = 5           -- seconds between two /who queries
local WHO_TIMEOUT = 8       -- an answer this late is given up on
local KEEP = 3 * 3600       -- a sighting is forgotten after this
local ROW_H = 16
local COLUMN_W = 250

local function IsOn() return db and db.EnableRecruit end
local function Say(text) print("|cff66ccffCommander Recruit|r: " .. text) end

-- Race tokens to faction, for the two chat types the other faction can
-- reach you on (say and yell)
local RACE_FACTION = {
    Human = "Alliance", Dwarf = "Alliance", NightElf = "Alliance", Gnome = "Alliance", Draenei = "Alliance",
    Orc = "Horde", Scourge = "Horde", Tauren = "Horde", Troll = "Horde", BloodElf = "Horde",
}
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6,
    Gnome = 7, Troll = 8, BloodElf = 10, Draenei = 11 }
local RACE_FALLBACK = { Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "Night Elf",
    Scourge = "Undead", Tauren = "Tauren", Gnome = "Gnome", Troll = "Troll", BloodElf = "Blood Elf",
    Draenei = "Draenei" }

-- The names /who understands for every class and race token, localized
local function WhoNames()
    local names = {}
    for _, class in ipairs(E.CLASS_ORDER) do
        names[class] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class])
            or (class:sub(1, 1) .. class:sub(2):lower())
    end
    for token, id in pairs(RACE_IDS) do
        local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetRaceInfo(id)
        names[token] = (info and info.raceName) or RACE_FALLBACK[token]
    end
    return names
end

local function MarkDirty() dirty = true end

local function Note(s, source)
    if not IsOn() then return end
    if E.Note(book, s, time(), source, homeRealm) then MarkDirty() end
end

local function ClassOfGUID(guid)
    if not (guid and GetPlayerInfoByGUID) then return nil end
    local ok, _, class, _, race = pcall(GetPlayerInfoByGUID, guid)
    if ok then return class, race end
    return nil
end

-- ---------------------------------------------------------------------------
-- Ratings
-- ---------------------------------------------------------------------------

local function RatingsFor(p)
    local who = p.bare and p.name or p.key
    if CommanderMuster and CommanderMuster.RatingsFor then
        local ok, ratings = pcall(CommanderMuster.RatingsFor, who)
        if ok then return ratings end
    end
    if CommanderLadder and CommanderLadder.Lookup then
        local ok, entry = pcall(CommanderLadder.Lookup, who, nil, p.bare)
        if ok and type(entry) == "table" then
            local out
            for _, size in ipairs(E.BRACKETS) do
                local b = entry[size]
                if type(b) == "table" and b[1] then
                    out = out or {}
                    out[size] = { rating = b[1], wins = b[2] or 0, played = (b[2] or 0) + (b[3] or 0),
                        at = entry.t, source = "feed" }
                end
            end
            return out
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------

-- Returns how many /who listed, how many matched, and the listed keys (the
-- steered sweep counts its finds from them, whatever the /who switch says)
local function ReadWho()
    local keys = {}
    if not (C_FriendList and C_FriendList.GetNumWhoResults) then return 0, 0, keys end
    local shown, total = C_FriendList.GetNumWhoResults()
    shown = tonumber(shown) or 0
    for i = 1, shown do
        local info = C_FriendList.GetWhoInfo(i)
        if type(info) == "table" then
            local fullName = info.fullName or info.name
            local key = E.Key(fullName, homeRealm)
            if key then keys[key] = true end
            if db.UseWho then
                Note({ fullName = fullName, level = info.level,
                    class = info.filename or info.classFileName, zone = info.area,
                    guild = info.fullGuildName or "" }, "who")
            end
        end
    end
    return shown, tonumber(total) or shown, keys
end

local function ReadLFG()
    if not (db.UseLFG and C_LFGList and C_LFGList.GetSearchResults) then return end
    local ok, _, results = pcall(C_LFGList.GetSearchResults)
    if not ok or type(results) ~= "table" then return end
    for _, id in ipairs(results) do
        local okInfo, info = pcall(C_LFGList.GetSearchResultInfo, id)
        if okInfo and type(info) == "table" and not info.isDelisted then
            for i = 1, math.max(info.numMembers or 1, 1) do
                local okMember, member = pcall(C_LFGList.GetSearchResultPlayerInfo, id, i)
                if okMember and type(member) == "table" and member.name then
                    Note({ fullName = member.name, class = member.classFilename, level = member.level }, "lfg")
                end
            end
        end
    end
end

local CHAT_EVENTS = {
    CHAT_MSG_CHANNEL = true, CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true,
    CHAT_MSG_WHISPER = true, CHAT_MSG_SAY = "race", CHAT_MSG_YELL = "race",
}

local function OnChat(event, sender, guid)
    if not db.UseChat or type(sender) ~= "string" or sender == "" then return end
    local class, race = ClassOfGUID(guid)
    if CHAT_EVENTS[event] == "race" and not (race and RACE_FACTION[race] == faction) then return end
    if guid and guid == UnitGUID("player") then return end
    Note({ fullName = sender, class = class, guid = guid }, "chat")
end

local function ReadGuild()
    if not (db.UseGuild and IsInGuild and IsInGuild() and GetNumGuildMembers) then return end
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, level, _, zone, _, _, online, _, class = GetGuildRosterInfo(i)
        if name then
            if online then
                Note({ fullName = name, level = level, class = class, zone = zone }, "guild")
            else
                E.Gone(book, name, homeRealm)
            end
        end
    end
    MarkDirty()
end

-- ---------------------------------------------------------------------------
-- The watch list (W1): players kept on your friends list so the server tells
-- you when they are on. Per character, as the friends list is. Each entry
-- remembers whether Recruit put them there: un-watching removes only those,
-- never a friend you already had.
-- ---------------------------------------------------------------------------

local WATCH_NOTE = "Recruit watch"
local ADD_TIMEOUT = 10      -- an add that has not shown up on the list by now failed
local friendSet = {}        -- key -> the friend's row, from the last list the server sent

local function Watch()
    if type(CommanderRecruitWatch) ~= "table" then CommanderRecruitWatch = {} end
    return CommanderRecruitWatch
end

-- Probe Ladder is gone (R17). A probe friend that a crash or a /reload left on
-- the list still comes off, once: by the list's own spelling, only while it
-- carries Recruit's exact note, never a watched one. CommanderRecruitProbe
-- names those; it empties itself and then goes away.
local PROBE_NOTE = "Recruit probe"
local friendsLoaded = false -- this session's friends list is known
local friendsAskedAt        -- when Recruit last asked the server for it
local FRIENDS_SETTLE = 8    -- asked this long ago and still none: the list is empty

local function CleanLeftoverProbes()
    local left = CommanderRecruitProbe
    if type(left) ~= "table" or not (C_FriendList and C_FriendList.RemoveFriend) then return 0 end
    local removed = 0
    for key, rec in pairs(left) do
        local info = friendSet[key]
        local n = info and info.notes
        if info and n == PROBE_NOTE and not Watch()[key] then
            C_FriendList.RemoveFriend(info.name)
            removed = removed + 1
            left[key] = nil
        elseif info and ((n ~= nil and n ~= "") or Watch()[key]) then
            left[key] = nil -- a note of yours, or watched: yours now
        elseif type(rec) ~= "table" or time() - (tonumber(rec.at) or 0) > 86400 then
            -- not on the list, or its note never came back: let it go
            left[key] = nil
        end
    end
    if next(left) == nil then CommanderRecruitProbe = nil end
    return removed
end
CommanderRecruit.CleanLeftoverProbes = CleanLeftoverProbes

function CommanderRecruit.IsWatched(p) return p and Watch()[p.key] ~= nil or false end

-- Watched players, and how many of them are on
function CommanderRecruit.WatchCounts()
    local n, on = 0, 0
    for key in pairs(Watch()) do
        n = n + 1
        local f = friendSet[key]
        if f and f.connected then on = on + 1 end
    end
    return n, on
end

-- A friend just added can be listed before the server has filled them in:
-- name "", level 0, class "Unknown", though the GUID and the note are already
-- there (in game 2026-10-17). Such a row is nobody yet:
-- skipped, and the list read again each second until every row has a name.
local friendsPartial = false

local function ReadFriends()
    if not (C_FriendList and C_FriendList.GetNumFriends) then return end
    wipe(friendSet)
    friendsPartial = false
    local watch = Watch()
    for i = 1, C_FriendList.GetNumFriends() or 0 do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        local key = type(info) == "table" and E.Key(info.name, homeRealm)
        if type(info) == "table" and not key then friendsPartial = true end
        if key then
            friendSet[key] = info
            local w = watch[key]
            if w then
                -- Removed later by the name the list itself uses
                w.confirmed, w.pendingAt, w.friendName = true, nil, info.name
                -- A note you rewrote makes them yours: Recruit never removes them
                if w.byUs and type(info.notes) == "string" and info.notes ~= "" and info.notes ~= WATCH_NOTE then
                    w.byUs = false
                end
            end
            if db.UseFriends or w then
                if info.connected then
                    Note({ fullName = info.name, level = info.level, class = ClassOfGUID(info.guid),
                        zone = info.area, guid = info.guid }, "friend")
                else
                    E.Gone(book, info.name, homeRealm)
                end
            end
        end
    end
    friendsLoaded = true
    CleanLeftoverProbes()
    -- A watched friend you took off the list yourself is no longer watched.
    -- An empty list is not evidence of that: at login it can arrive empty;
    -- nor is one with a row not filled in yet, which may be them.
    if next(friendSet) and not friendsPartial then
        for key, w in pairs(watch) do
            if w.confirmed and not friendSet[key] then watch[key] = nil end
        end
    end
    MarkDirty()
end

-- An add that never landed: not found, another realm, or a full list
local function CheckPendingAdds()
    local now = GetTime()
    for key, w in pairs(Watch()) do
        if w.pendingAt and now - w.pendingAt > ADD_TIMEOUT then
            Watch()[key] = nil
            Say(string.format("could not add %s to your friends list (not found, another realm, or the list is full), so they are not watched.", w.name))
            MarkDirty()
        end
    end
end

-- From a click: AddFriend has restrictions, like SendWho
-- Can this player be friended at all? Not from another realm: Devin confirmed
-- on 2026-10-17 that a Dreamscythe character cannot friend a Nightslayer one
-- (R11). A bare name is the game's own realm-less name and is tried as such.
function CommanderRecruit.CanFriend(p)
    return p and (p.bare or not p.realm or p.realm == homeRealm) and true or false
end

function CommanderRecruit.ToggleWatch(p)
    if not (IsOn() and p) then return end
    if not CommanderRecruit.CanFriend(p) and not Watch()[p.key] then return end
    local watch = Watch()
    local given = p.bare and p.name or p.key
    local w = watch[p.key]
    if w then
        watch[p.key] = nil
        if w.byUs and C_FriendList and C_FriendList.RemoveFriend then
            C_FriendList.RemoveFriend(w.friendName or w.name)
            Say(string.format("stopped watching %s and took them off your friends list.", w.name))
        else
            Say(string.format("stopped watching %s (still your friend: they were before).", w.name))
        end
    elseif friendSet[p.key] then
        watch[p.key] = { name = given, byUs = false, at = time(), confirmed = true }
        Say(string.format("%s is already your friend: watching them, and they stay your friend.", given))
    elseif C_FriendList and C_FriendList.AddFriend then
        C_FriendList.AddFriend(given, WATCH_NOTE)
        watch[p.key] = { name = given, byUs = true, at = time(), pendingAt = GetTime() }
        Say(string.format("watching %s: added to your friends list, and taken off again when you stop.", given))
    end
    MarkDirty()
end

-- Ask for the friends list. The server sends it once at login, which can be
-- before Recruit is listening, and asking again does not always fire a fresh
-- FRIENDLIST_UPDATE -- so the client's own copy is read too (CheckFriends).
local function RequestFriends()
    friendsAskedAt = GetTime()
    if C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
end

-- Once a second until the list is known: the client already holding friends
-- means the list is here; asked a while ago and still none means it is empty
local function CheckFriends()
    if friendsLoaded and friendsPartial then
        ReadFriends()
        return
    end
    if friendsLoaded or not (C_FriendList and C_FriendList.GetNumFriends) then return end
    if (C_FriendList.GetNumFriends() or 0) > 0 then
        ReadFriends()
    elseif friendsAskedAt and GetTime() - friendsAskedAt > FRIENDS_SETTLE then
        ReadFriends()
    end
end

-- Stop watching everyone; only the friends Recruit added come off the list
function CommanderRecruit.UnwatchAll()
    local removed, kept = 0, 0
    for key, w in pairs(Watch()) do
        if w.byUs and C_FriendList and C_FriendList.RemoveFriend then
            C_FriendList.RemoveFriend(w.friendName or w.name)
            removed = removed + 1
        else
            kept = kept + 1
        end
        Watch()[key] = nil
    end
    MarkDirty()
    return removed, kept
end

local function ReadUnit(unit)
    if not (db.UseSeen and unit and UnitExists(unit) and UnitIsPlayer(unit)) then return end
    if UnitIsUnit(unit, "player") or UnitFactionGroup(unit) ~= faction then return end
    local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
    local _, class = UnitClass(unit)
    Note({ fullName = name, class = class, level = UnitLevel(unit), guid = UnitGUID(unit) }, "seen")
end

-- ---------------------------------------------------------------------------
-- The sweep: one /who per press
-- ---------------------------------------------------------------------------

-- Commander Ladder's roster of our realm's rated players (Ladder L9), or nil
local function LadderRoster()
    if not (CommanderLadder and CommanderLadder.Roster) then return nil end
    local ok, roster = pcall(CommanderLadder.Roster, homeRealm)
    if ok and type(roster) == "table" then return roster end
    return nil
end

-- The player's search order (R21), from the window's class list: the
-- order, the classes switched off, whether to ask down the order
local function SearchOptions()
    local off = {}
    if type(db.SweepOff) == "table" then
        for class, isOff in pairs(db.SweepOff) do
            if isOff and E.CLASS_RACES[class] then off[class] = true end
        end
    end
    return { order = E.ClassOrder(db.SweepOrder), off = off, inOrder = db.SweepInOrder and true or false }
end
CommanderRecruit.SearchOptions = SearchOptions

-- A new sweep: steered by the roster when it describes anyone of our
-- faction (R20), the fixed class plan otherwise; both in the player's order
local function NewPlan()
    local names, search = WhoNames(), SearchOptions()
    return E.NewSteeredSweep(LadderRoster(), { faction = faction, names = names, minRating = db.MinRating,
        now = time(), learned = learned, order = search.order, off = search.off, inOrder = search.inOrder })
        or E.NewSweep(faction, names, nil, search)
end

-- Everyone on the board: a steered sweep looks for the rest
local function SeenSet()
    local set = {}
    for _, p in ipairs(E.Fresh(book, time(), (db.FreshMinutes or 15) * 60)) do set[p.key] = true end
    return set
end

-- A /who that never answered: counted as answered with nobody, so the plan
-- moves on. Asking it again was a loop -- a query with no matches can send
-- no WHO_LIST_UPDATE, and then never would.
local function SettleUnanswered()
    if awaiting and GetTime() - awaiting.at >= WHO_TIMEOUT then
        awaiting = nil
        if sweep then E.SweepResult(sweep, 0, 0, true) end
        if C_FriendList and C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(false) end
        MarkDirty()
    end
end

-- What a query is, for the bar and chat: "guild <Gank Squad> (~2.1 rated)",
-- "arena matches (~3.0 rated)", "Blood Elf Rogue (~0.8 rated)", "Warrior"
local function Describe(q)
    if not q then return "" end
    local text = (q.kind == "guild" and "guild " or "") .. (q.label or q.text)
    if q.expect then
        text = text .. string.format(" (~%s rated)", q.expect >= 10 and string.format("%d", math.floor(q.expect + 0.5))
            or string.format("%.1f", q.expect))
    end
    return text
end

-- What the next press would start with, while no sweep is under way: built
-- at most every few seconds (the roster is ~800 players of a faction)
local preview, previewAt = nil, -100
local PREVIEW_EVERY = 5

local function Preview()
    if not preview or GetTime() - previewAt >= PREVIEW_EVERY then
        preview = NewPlan()
        preview.peek = E.SweepNext(preview, SeenSet(), time())
        previewAt = GetTime()
    end
    return preview
end

-- The query the bar last named as next, and the sweep it belongs to: the
-- class list marks the class it is searching for
local nextQuery, nextSweep

-- The sweep bar (R12): what it is doing, what it asks next, whether a press
-- would act, how far
local function SweepState()
    SettleUnanswered()
    nextQuery, nextSweep = nil, nil
    local wait = WHO_GAP - (GetTime() - lastSend)
    local ready = wait <= 0
    local when = ready and "ready" or string.format("in %ds", math.ceil(wait))
    local steered = sweep and sweep.mode == "steered"
    local function Count()
        local done, total = E.SweepProgress(sweep)
        return done, (steered and "~" or "") .. total, total > 0 and done / total or 1
    end
    if awaiting then
        local done, of, fraction = Count()
        return string.format("Sweep: %d of %s queries · waiting for /who to answer: %s...", done, of,
            Describe(awaiting.q)), false, fraction
    end
    -- Under way: the next query is chosen now, and none left means done
    local q = sweep and not E.SweepFinished(sweep) and E.SweepNext(sweep, SeenSet(), time()) or nil
    if q then
        nextQuery, nextSweep = q, sweep
        local done, of, fraction = Count()
        return string.format("Sweep: %d of %s queries · next: %s · %s", done, of, Describe(q), when), ready, fraction
    end
    -- Not started, or done: what the next press starts with
    local plan = Preview()
    nextQuery, nextSweep = plan.peek, plan
    local allOff = next(E.ClassRanks(db.SweepOrder, SearchOptions().off)) == nil
    local first = plan.peek and string.format("%s · %s", Describe(plan.peek), when)
        or (allOff and "every class is unchecked in the search order: check one to sweep")
        or "nothing worth a /who now: the rest are on the board, proved offline or long inactive"
    if not sweep then
        local how = plan.mode == "steered"
            and string.format("aimed by the ladder at %d rated %s here", plan.rated, faction or "")
            or "each press asks /who for the next class at level 70"
        return string.format("Sweep: not started · %s · first: %s", how, first), ready and plan.peek ~= nil, 0
    end
    local partial, lost = #sweep.partial, #sweep.unanswered
    return string.format("Sweep: done, %d queries%s%s%s · again from: %s", sweep.done,
        steered and string.format(", %d rated found", sweep.found) or "",
        partial > 0 and string.format(" (%d still past /who's 50)", partial) or "",
        lost > 0 and string.format(" (%d unanswered)", lost) or "", first), ready and plan.peek ~= nil, 1
end
CommanderRecruit.SweepState = SweepState

-- Bound to a key and to the window's button: both are a press, which is the
-- only thing SendWho answers to
function CommanderRecruit_SweepStep()
    if not IsOn() then return end
    if not (C_FriendList and C_FriendList.SendWho) then Say("this client has no /who for addons.") return end
    local now = GetTime()
    SettleUnanswered()
    if awaiting then return end
    if now - lastSend < WHO_GAP then return end
    local seen, epoch = SeenSet(), time()
    local q = sweep and not E.SweepFinished(sweep) and E.SweepNext(sweep, seen, epoch) or nil
    preview = nil
    if not q then
        -- None under way, or it just ran out: this press starts the next,
        -- unless it has nothing worth a /who (the bar says why), and then the
        -- last sweep's count stays on the bar
        local fresh = NewPlan()
        q = E.SweepNext(fresh, seen, epoch)
        if not q then MarkDirty() return end
        sweep = fresh
    end
    friendsWasShown = FriendsFrame and FriendsFrame:IsShown()
    -- To the list, quietly: not a page of /who lines in chat, not the window
    if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(true) end
    local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    C_FriendList.SendWho(q.text, origin)
    E.SweepSent(sweep, q, epoch, seen)
    awaiting = { at = now, q = q }
    lastSend = now
    MarkDirty()
end

-- The key binding (R9, R17). Once it chose between the sweep and a probe;
-- with the probe gone it is the sweep, kept under its old binding name so a
-- key already bound to it keeps working.
function CommanderRecruit_NextStep()
    CommanderRecruit_SweepStep()
end

local function OnWhoList()
    local shown, total, keys = ReadWho()
    if awaiting then
        -- A steered pair answered under the cap proves the rest of its rated
        -- players offline: off the board now, as a roster's "offline" does
        local gone = E.SweepResult(sweep, shown, total, nil, keys)
        if db.UseWho then
            for _, key in ipairs(gone or {}) do E.Gone(book, key, homeRealm) end
        end
        awaiting = nil
        if C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(false) end
        if FriendsFrame and FriendsFrame:IsShown() and not friendsWasShown and HideUIPanel then
            HideUIPanel(FriendsFrame)
        end
        if not E.SweepNext(sweep, SeenSet(), time()) then
            local partial, lost = #sweep.partial, #sweep.unanswered
            Say(string.format("sweep done: %d queries%s%s%s.", sweep.done,
                sweep.mode == "steered" and string.format(", %d rated player%s found", sweep.found,
                    sweep.found == 1 and "" or "s") or "",
                partial > 0 and string.format(", %d still past /who's 50 a query (partial)", partial) or "",
                lost > 0 and string.format(", %d had no answer from the server", lost) or ""))
        end
    end
    MarkDirty()
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.85
end

-- The suite's tier colours for a number, by rating
local function RatingColor(rating)
    if rating >= 2200 then return 1.00, 0.50, 0.00 end
    if rating >= 2000 then return 0.64, 0.21, 0.93 end
    if rating >= 1800 then return 0.00, 0.44, 0.87 end
    if rating >= 1600 then return 0.12, 1.00, 0.00 end
    return 0.85, 0.85, 0.85
end

local function AgeText(seconds)
    if seconds < 60 then return "now" end
    return math.floor(seconds / 60) .. "m"
end

-- Left-click (R14): the conversation with them in Commander Contacts, so the
-- whispers you have already traded are right there above the box you type
-- in -- a thread is made if there is none. A plain chat whisper when
-- Contacts is not loaded, or is switched off.
local function Whisper(p)
    local target = p.bare and p.name or p.key
    if CommanderContacts_OpenWhisper then
        local ok, opened = pcall(CommanderContacts_OpenWhisper, target, { class = p.class, guid = p.guid })
        if ok and opened then return end
    end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(target)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(target)
    elseif ChatFrameUtil and ChatFrameUtil.OpenChat then
        ChatFrameUtil.OpenChat("/w " .. target .. " ")
    elseif ChatFrame_OpenChat then
        ChatFrame_OpenChat("/w " .. target .. " ")
    end
end

local function Invite(p)
    local target = p.bare and p.name or p.key
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(target)
    elseif InviteUnit then
        InviteUnit(target)
    end
end

local function RowTooltip(row)
    local entry = row.entry
    if not entry then return end
    local p = entry.player
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(p.bare and p.name or p.key, ClassColor(p.class))
    local facts = {}
    if p.level then facts[#facts + 1] = "Level " .. p.level end
    if p.class and LOCALIZED_CLASS_NAMES_MALE then facts[#facts + 1] = LOCALIZED_CLASS_NAMES_MALE[p.class] end
    if #facts > 0 then GameTooltip:AddLine(table.concat(facts, " "), 1, 1, 1) end
    if p.guild then GameTooltip:AddLine("<" .. p.guild .. ">", 0.25, 1, 0.25) end
    if p.zone then GameTooltip:AddLine(p.zone, 0.8, 0.8, 0.8) end
    if CommanderRecruit.IsWatched(p) then GameTooltip:AddLine("Watching (on your friends list)", 0.4, 0.8, 1) end
    local age = AgeText(time() - (p.at or 0))
    GameTooltip:AddLine(string.format("Seen %s, via %s", age == "now" and "just now" or (age .. " ago"),
        E.SOURCE_LABEL[p.source] or p.source or "?"), 0.6, 0.6, 0.6)
    local ratings = RatingsFor(p)
    if ratings then
        GameTooltip:AddLine(" ")
        for _, size in ipairs(E.BRACKETS) do
            local b = ratings[size]
            if b and (b.rating or 0) > 0 then
                local lost = math.max((b.played or 0) - (b.wins or 0), 0)
                GameTooltip:AddDoubleLine(size .. "v" .. size,
                    string.format("%d  (%d-%d)%s", b.rating, b.wins or 0, lost,
                        (b.best and b.best > b.rating) and string.format(", best %d", b.best) or ""),
                    0.8, 0.8, 0.8, RatingColor(b.rating))
            end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(CommanderContacts_OpenWhisper and "Left-click: conversation in Contacts   Right-click: invite   Dot: watch"
        or "Left-click: whisper   Right-click: invite   Dot: watch", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- The watch mark: a small dot, faint until someone is watched. An icon on
-- every row (the first version's owl) was the busiest thing on the board
-- for the control used least.
local DOT_ON = { 0.30, 0.80, 1.00, 1 }
local DOT_OFF = { 0.55, 0.55, 0.55, 0.25 }

local function PaintEye(eye, watched)
    local c = watched and DOT_ON or DOT_OFF
    eye.dot:SetVertexColor(c[1], c[2], c[3], c[4])
    eye.watched = watched and true or false
end

-- One line, never wrapped: a fixed-width string that wraps grows into the
-- row below (the win-loss did, at "165-126")
local function Cell(row, font, justify, width)
    local fs = row:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH(justify)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    if width then fs:SetWidth(width) end
    return fs
end

-- A row is laid out from BOTH ends: the dot and rank from the left, the age,
-- win-loss and rating from the right, and the name takes whatever is between
-- (cut short with an ellipsis rather than pushed into the numbers). Nothing
-- depends on a guessed font width, so a larger UI scale cannot make two
-- cells overlap.
local AGE_W, RECORD_W, RATING_W, RANK_W = 30, 56, 38, 20

local function NewRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)
    -- The watch toggle: lit while they are kept on your friends list
    row.eye = CreateFrame("Button", nil, row)
    row.eye:SetSize(12, ROW_H)
    row.eye:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.eye.dot = row.eye:CreateTexture(nil, "ARTWORK")
    row.eye.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.eye.dot:SetSize(6, 6)
    row.eye.dot:SetPoint("CENTER", row.eye, "CENTER", 0, 0)
    row.eye:SetScript("OnClick", function()
        if row.entry then
            CommanderRecruit.ToggleWatch(row.entry.player)
            PaintEye(row.eye, CommanderRecruit.IsWatched(row.entry.player))
        end
    end)
    row.eye:SetScript("OnEnter", function(self)
        if not self.watched then self.dot:SetVertexColor(0.85, 0.85, 0.85, 0.9) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local watched = row.entry and CommanderRecruit.IsWatched(row.entry.player)
        GameTooltip:SetText(watched and "Watching" or "Watch", 1, 0.82, 0)
        GameTooltip:AddLine(watched
            and "Click to stop. A friend Recruit added comes off your friends list; one you already had stays."
            or "Click to keep them on your friends list, so you see when they come online without a sweep. Recruit takes them off again when you stop watching.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.eye:SetScript("OnLeave", function(self)
        PaintEye(self, self.watched)
        GameTooltip:Hide()
    end)
    row.rank = Cell(row, "GameFontDisableSmall", "RIGHT", RANK_W)
    row.rank:SetPoint("LEFT", row.eye, "RIGHT", 0, 0)
    row.age = Cell(row, "GameFontDisableSmall", "RIGHT", AGE_W)
    row.age:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.record = Cell(row, "GameFontDisableSmall", "RIGHT", RECORD_W)
    row.record:SetPoint("RIGHT", row.age, "LEFT", -4, 0)
    row.rating = Cell(row, "GameFontHighlightSmall", "RIGHT", RATING_W)
    row.rating:SetPoint("RIGHT", row.record, "LEFT", -6, 0)
    row.name = Cell(row, "GameFontHighlightSmall", "LEFT")
    row.name:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.rating, "LEFT", -6, 0)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
        local entry = self.entry
        if not entry then return end
        if button == "RightButton" then Invite(entry.player) else Whisper(entry.player) end
    end)
    return row
end

local function PaintColumn(col, list)
    local now = time()
    local visible = #col.rows
    local maxOffset = math.max(#list - visible, 0)
    if col.offset > maxOffset then col.offset = maxOffset end
    for i, row in ipairs(col.rows) do
        local entry = list[i + col.offset]
        row.entry = entry
        if entry then
            local p = entry.player
            row.rank:SetText(i + col.offset)
            local label = p.name or p.key
            if p.realm and p.realm ~= homeRealm and not p.bare then label = label .. "|cff888888*|r" end
            row.name:SetText(label)
            row.name:SetTextColor(ClassColor(p.class))
            row.rating:SetText(entry.rating)
            row.rating:SetTextColor(RatingColor(entry.rating))
            row.record:SetText(entry.wins .. "-" .. entry.lost)
            row.age:SetText(AgeText(now - (p.at or 0)))
            PaintEye(row.eye, CommanderRecruit.IsWatched(p))
            -- Watching is friending, and another realm cannot be friended
            row.eye:SetShown(CommanderRecruit.CanFriend(p) or CommanderRecruit.IsWatched(p))
            row:Show()
        else
            row:Hide()
        end
    end
    col.count:SetText(#list > 0 and string.format("%d online", #list) or "nobody yet")
end

-- The board last built. A build looks up every online player's ratings and
-- sorts three lists, so it happens when something changed (at most once a
-- second, on the ticker) or every few seconds as sightings age; scrolling
-- and the ticking ages only repaint rows from it (R18).
local board
local builtAt = -100
local REBUILD_EVERY = 5

-- Ratings by player, kept a few minutes: the lookup through Muster and the
-- ladder data is the costly part of a build, and a rating does not change
-- between two sweeps. "No rating" is kept a minute only: Muster can learn one
-- (an inspect, an arena) at any time.
local ratingsCache, ratingsPrunedAt = {}, -1000
local RATINGS_KEEP, UNRATED_KEEP = 300, 60

local function CachedRatings(p)
    local now = GetTime()
    local hit = ratingsCache[p.key]
    if not hit or now - hit.at > (hit.r and RATINGS_KEEP or UNRATED_KEEP) then
        hit = { at = now, r = RatingsFor(p) or false }
        ratingsCache[p.key] = hit
    end
    return hit.r or nil
end

local function BuildBoard(settings)
    local now = GetTime()
    if now - ratingsPrunedAt > RATINGS_KEEP then
        for key, hit in pairs(ratingsCache) do
            if now - hit.at > RATINGS_KEEP then ratingsCache[key] = nil end
        end
        ratingsPrunedAt = now
    end
    local fresh = E.Fresh(book, time(), (settings.FreshMinutes or 15) * 60, KEEP)
    return E.Board(fresh, CachedRatings, { minRating = settings.MinRating })
end

local function PaintRows()
    if not (board and window) then return end
    for _, col in ipairs(window.columns) do PaintColumn(col, board[col.size]) end
end

-- Rated players on the board by class, before any are hidden: the search
-- list's "online" counts
local onByClass = {}

local function Rebuild()
    dirty = false
    builtAt = GetTime()
    board = BuildBoard(db)
    wipe(onByClass)
    local all = {}
    for _, size in ipairs(E.BRACKETS) do
        for _, row in ipairs(board[size]) do
            local p = row.player
            if not all[p.key] then
                all[p.key] = true
                if p.class then onByClass[p.class] = (onByClass[p.class] or 0) + 1 end
            end
        end
    end
    -- Only the classes searched, when the list says so (R21). A player whose
    -- class is not known yet stays.
    local off = db.SweepHideOff and SearchOptions().off
    if off and next(off) then
        for _, size in ipairs(E.BRACKETS) do
            local kept = {}
            for _, row in ipairs(board[size]) do
                if not (row.player.class and off[row.player.class]) then kept[#kept + 1] = row end
            end
            board[size] = kept
        end
    end
    local rated, n, hidden = {}, 0, 0
    for _, size in ipairs(E.BRACKETS) do
        for _, row in ipairs(board[size]) do rated[row.player.key] = true end
    end
    for key in pairs(all) do
        if rated[key] then n = n + 1 else hidden = hidden + 1 end
    end
    local watched, watchedOn = CommanderRecruit.WatchCounts()
    window.status:SetText(string.format("%d rated players online, of %d seen in the last %d min%s%s",
        n, board.online, db.FreshMinutes or 15,
        hidden > 0 and string.format(" · %d of unchecked classes hidden", hidden) or "",
        watched > 0 and string.format(" · watching %d, %d on", watched, watchedOn) or ""))
    local partial = sweep and E.SweepFinished(sweep) and #sweep.partial > 0
    window.foot:SetText(string.format("%d online with no rating known yet (they are looked up at the next feed run)%s",
        board.unrated, partial and " · the last sweep was partial: some queries past /who's 50" or ""))
end

-- ---------------------------------------------------------------------------
-- The search order (R21): the classes the sweep looks for, top first, as a
-- list beside the board. Drag a row to move it; click it, or its box, to
-- search that class or not. Saved account-wide: SweepOrder (class tokens),
-- SweepOff ({ [class] = true }), SweepInOrder, SweepHideOff.
-- ---------------------------------------------------------------------------

local SIDE_W = 176          -- the list's width, left of the columns
local Paint                 -- below; the list's clicks repaint at once
local CLASS_ROW_H = 22
local CLASS_TOP = -24       -- the first row, below the list's title

-- Rated players of our faction per class in the ladder roster (at the
-- board's lowest rating), or nil without one; worked out again only when the
-- roster or that rating changes
local ratedByClass, ratedByClassKey
local function RatedByClass()
    local roster = LadderRoster()
    local letter = E.FACTION_LETTER[faction or ""]
    if not (roster and letter) then return nil end
    local key = tostring(roster) .. ":" .. tostring(db.MinRating) .. ":" .. letter
    if ratedByClassKey ~= key then
        ratedByClassKey = key
        local counts, any, minRating = {}, false, tonumber(db.MinRating) or 0
        for _, r in ipairs(roster) do
            if r.faction == letter and r.class and (tonumber(r.best) or 0) >= minRating then
                counts[r.class] = (counts[r.class] or 0) + 1
                any = true
            end
        end
        ratedByClass = any and counts or nil
    end
    return ratedByClass
end

local function PaintSearch()
    local list = window and window.search
    if not list then return end
    local search = SearchOptions()
    local rated = RatedByClass()
    local nextClass = E.QueryClass(nextSweep, nextQuery)
    for i, class in ipairs(search.order) do
        local row = list.rows[i]
        row.class, row.index = class, i
        local on = not search.off[class]
        row.check:SetChecked(on)
        row.name:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class)
        row.name:SetTextColor(ClassColor(class))
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then row.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) end
        row.icon:SetShown(coords ~= nil)
        local found = onByClass[class] or 0
        row.count:SetText(rated and string.format("%d/%d", found, rated[class] or 0) or string.format("%d on", found))
        local alpha = on and 1 or 0.35
        row.icon:SetAlpha(alpha)
        row.name:SetAlpha(alpha)
        row.count:SetAlpha(alpha)
        row.next:SetShown(on and class == nextClass)
    end
    list.inOrder:SetChecked(search.inOrder)
    list.hideOff:SetChecked(db.SweepHideOff and true or false)
end

-- Every change to the list: a steered sweep under way takes it on the next
-- press; the fixed plan (no ladder roster) starts again in the new order
local function OnSearchChanged()
    preview = nil
    if sweep and sweep.mode == "steered" then
        E.SteerOptions(sweep, SearchOptions())
    elseif sweep and not awaiting then
        sweep = nil
    end
    MarkDirty()
    Paint(true)
end

function CommanderRecruit.ToggleClass(class)
    if not E.CLASS_RACES[class] then return end
    local off = type(db.SweepOff) == "table" and db.SweepOff or {}
    off[class] = not off[class] or nil
    db.SweepOff = off
    OnSearchChanged()
end

-- Dragging a row is saying the order matters, so it also turns on
-- "Search in this order"
function CommanderRecruit.MoveClass(from, to)
    db.SweepOrder = E.MoveClass(db.SweepOrder, from, to)
    db.SweepInOrder = true
    OnSearchChanged()
end

function CommanderRecruit.ResetSearch()
    db.SweepOrder, db.SweepOff, db.SweepInOrder = false, false, false
    OnSearchChanged()
end

-- `force`: build now (the window opening, a setting changed)
Paint = function(force)
    if not (window and window:IsShown()) then return end
    local sweepText, sweepReady, sweepFill = SweepState()
    window.sweep:SetEnabled(sweepReady)
    window.SetBar(window.sweepBar, sweepText, sweepFill)
    if force or dirty or not board or GetTime() - builtAt >= REBUILD_EVERY then Rebuild() end
    PaintRows()
    PaintSearch()
end

local function SavePosition(self)
    local point, _, _, x, y = self:GetPoint(1)
    if point then db.Pos = { point = point, x = x, y = y } end
end

-- The window's vertical layout: the header row, the sweep's bar (R12),
-- then the three columns down to the footer
local WIN_H = 508
local BAR_H, BAR_TOP = 15, -58
local COLUMNS_TOP = -78

-- One progress bar: a dark track, a fill as wide as the fraction, and its
-- line of text across the whole width, so nothing has to fit in a button
local function NewBar(parent, r, g, b)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(BAR_H)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints(bar)
    bar.track:SetColorTexture(0, 0, 0, 0.45)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
    bar.fill:SetColorTexture(r, g, b, 0.55)
    bar.fill:SetWidth(1)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("LEFT", bar, "LEFT", 6, 0)
    bar.text:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    bar.text:SetJustifyH("LEFT")
    if bar.text.SetWordWrap then bar.text:SetWordWrap(false) end
    return bar
end

-- Where a drag would drop: the gap between rows nearest the cursor, 1 (above
-- the first) to n + 1 (below the last)
local function DropGap(list)
    local top = list:GetTop()
    if not top then return nil end
    local _, y = GetCursorPosition()
    y = y / math.max(list:GetEffectiveScale() or 1, 0.01)
    local gap = math.floor((top + CLASS_TOP - y) / CLASS_ROW_H + 0.5) + 1
    return math.max(1, math.min(#E.CLASS_ORDER + 1, gap))
end

local function TrackDrag(list)
    local drag = list.drag
    if not drag then return end
    drag.gap = DropGap(list)
    if drag.gap then
        list.marker:ClearAllPoints()
        list.marker:SetPoint("TOPLEFT", list, "TOPLEFT", 4, CLASS_TOP - (drag.gap - 1) * CLASS_ROW_H + 1)
        list.marker:SetPoint("RIGHT", list, "RIGHT", -4, 0)
        list.marker:Show()
    end
end

local function ClassRowTooltip(row)
    if not row.class then return end
    local rated = RatedByClass()
    local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[row.class]) or row.class
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(name, ClassColor(row.class))
    GameTooltip:AddLine(string.format("%d on the board now%s.", onByClass[row.class] or 0,
        rated and string.format(", of %d rated %s players in the ladder data", rated[row.class] or 0, faction or "") or ""),
        1, 1, 1, true)
    local off = SearchOptions().off[row.class]
    GameTooltip:AddLine(off and "Not searched: click to search this class again."
        or "Searched. Click to skip this class; drag to move it up or down the order.", 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

-- The list itself: a title, one row per class, then the two switches
local function BuildSearchList(f)
    local list = CreateFrame("Frame", nil, f)
    f.search = list
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 12, COLUMNS_TOP)
    list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 30)
    list:SetWidth(SIDE_W)
    local back = list:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(list)
    back:SetColorTexture(0, 0, 0, 0.25)
    list.title = list:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    list.title:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -4)
    list.title:SetText("Search order")
    list.hint = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    list.hint:SetPoint("TOPRIGHT", list, "TOPRIGHT", -6, -6)
    list.hint:SetText("on/rated")
    -- Where a dragged row would land
    list.marker = list:CreateTexture(nil, "OVERLAY")
    list.marker:SetHeight(2)
    list.marker:SetColorTexture(0.85, 0.65, 0.15, 0.9)
    list.marker:Hide()
    list.rows = {}
    for i = 1, #E.CLASS_ORDER do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(CLASS_ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, CLASS_TOP - (i - 1) * CLASS_ROW_H)
        row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        row:RegisterForClicks("LeftButtonUp")
        row:RegisterForDrag("LeftButton")
        -- The class the next press searches for
        row.next = row:CreateTexture(nil, "BACKGROUND")
        row.next:SetAllPoints(row)
        row.next:SetColorTexture(0.85, 0.65, 0.15, 0.2)
        row.next:Hide()
        -- A grip of six dots, drawn from quads
        for gx = 0, 1 do
            for gy = -1, 1 do
                local dot = row:CreateTexture(nil, "ARTWORK")
                dot:SetSize(2, 2)
                dot:SetColorTexture(0.6, 0.6, 0.6, 0.8)
                dot:SetPoint("LEFT", row, "LEFT", 5 + gx * 4, gy * 4)
            end
        end
        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(20, 20)
        row.check:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
        row.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        row.count = Cell(row, "GameFontDisableSmall", "RIGHT", 46)
        row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.name = Cell(row, "GameFontHighlightSmall", "LEFT")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.name:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        local function Toggle() CommanderRecruit.ToggleClass(row.class) end
        row:SetScript("OnClick", Toggle)
        row.check:SetScript("OnClick", Toggle)
        row:SetScript("OnEnter", ClassRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnDragStart", function(self)
            list.drag = { from = self.index }
            self:SetAlpha(0.4)
            list:SetScript("OnUpdate", TrackDrag)
        end)
        row:SetScript("OnDragStop", function(self)
            list:SetScript("OnUpdate", nil)
            TrackDrag(list)
            self:SetAlpha(1)
            list.marker:Hide()
            local drag = list.drag
            list.drag = nil
            if not (drag and drag.from and drag.gap) then return end
            -- A gap below the row's own place is one place less once it is lifted out
            local to = drag.gap > drag.from and drag.gap - 1 or drag.gap
            if to ~= drag.from then CommanderRecruit.MoveClass(drag.from, to) end
        end)
        list.rows[i] = row
    end
    local below = CLASS_TOP - #E.CLASS_ORDER * CLASS_ROW_H - 6
    local function Switch(label, y, tip, onClick)
        local check = CreateFrame("CheckButton", nil, list, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", list, "TOPLEFT", 10, y)
        check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        check.label:SetText(label)
        check:SetScript("OnClick", onClick)
        Commander.UI.AttachTooltip(check, label, tip)
        return check
    end
    list.inOrder = Switch("Search in this order", below,
        "On: every press goes to the highest class in the list that still has rated players worth a /who, before any class below it (the arena zones still go first: they list every class at once). Off: the sweep asks wherever the most unfound rated players should be, and the list only says which classes to look for. Dragging a row turns this on.",
        function()
            db.SweepInOrder = not db.SweepInOrder
            OnSearchChanged()
        end)
    list.hideOff = Switch("Hide unchecked classes", below - 24,
        "On the board, show only the classes checked above. Players whose class is not known yet stay.",
        function()
            db.SweepHideOff = not db.SweepHideOff
            MarkDirty()
            Paint(true)
        end)
    list.reset = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    list.reset:SetSize(64, 20)
    list.reset:SetPoint("TOPLEFT", list, "TOPLEFT", 12, below - 52)
    list.reset:SetText("Reset")
    list.reset:SetScript("OnClick", CommanderRecruit.ResetSearch)
    Commander.UI.AttachTooltip(list.reset, "Reset",
        "Every class searched, in the default order, and Search in this order off.")
    return list
end

local function BuildWindow()
    if window then return window end
    local f = CreateFrame("Frame", "CommanderRecruitFrame", UIParent, "BasicFrameTemplateWithInset")
    window = f
    f:SetSize(SIDE_W + 8 + COLUMN_W * 3 + 40, WIN_H)
    -- The suite's window layer (Contacts, Notebook, Vault, Orders...): above
    -- the action bars and HUD frames, and to the front when clicked
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    local pos = db.Pos
    if type(pos) == "table" and pos.point then
        f:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
    else
        f:SetPoint("CENTER")
    end
    if f.TitleText then f.TitleText:SetText("Recruit — rated players online") end
    tinsert(UISpecialFrames, "CommanderRecruitFrame")

    f.status = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    f.status:SetJustifyH("LEFT")
    if f.status.SetWordWrap then f.status:SetWordWrap(false) end

    f.sweep = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.sweep:SetSize(96, 22)
    f.sweep:SetText("Sweep")
    f.sweep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -29)
    f.sweep:SetScript("OnClick", CommanderRecruit_SweepStep)
    Commander.UI.AttachTooltip(f.sweep, "Sweep",
        "One /who per press. With the Commander Ladder feed's roster of the realm's rated players, each press asks where the most of them not yet on the board should be: the arena zones, their guilds, their class and race. Without it, every class at level 70, split by race past /who's 50 names. The Search order list on the left says which classes to look for, and with Search in this order, in what order. The bar says what comes next. Easiest with a key: Key Bindings > AddOns > Commander Recruit > \"Sweep: Next /who\".")
    f.status:SetPoint("RIGHT", f.sweep, "LEFT", -8, 0)

    -- The sweep's bar, full width, so a count never has to squeeze into a button
    f.sweepBar = NewBar(f, 0.85, 0.65, 0.15)
    f.sweepBar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, BAR_TOP)
    f.sweepBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, BAR_TOP)
    function f.SetBar(bar, text, fraction)
        bar.text:SetText(text)
        local width = bar:GetWidth()
        if not width or width <= 0 then width = SIDE_W + 8 + COLUMN_W * 3 + 16 end
        fraction = math.max(0, math.min(1, fraction or 0))
        bar.fill:SetWidth(math.max(1, width * fraction))
        bar.fill:SetShown(fraction > 0)
        bar.fraction = fraction
    end

    BuildSearchList(f)

    f.columns = {}
    for i, size in ipairs(E.BRACKETS) do
        local col = CreateFrame("Frame", nil, f)
        local x = 12 + SIDE_W + 8 + (i - 1) * (COLUMN_W + 8)
        col:SetPoint("TOPLEFT", f, "TOPLEFT", x, COLUMNS_TOP)
        col:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 30)
        col:SetWidth(COLUMN_W)
        col.size, col.offset = size, 0
        local back = col:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(col)
        back:SetColorTexture(0, 0, 0, 0.25)
        col.title = col:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        col.title:SetPoint("TOPLEFT", col, "TOPLEFT", 6, -4)
        col.title:SetText(size .. "v" .. size)
        col.count = col:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        col.count:SetPoint("TOPRIGHT", col, "TOPRIGHT", -6, -6)
        col.rows = {}
        local rows = math.floor((WIN_H + COLUMNS_TOP - 30 - 24) / ROW_H)
        for r = 1, rows do
            local row = NewRow(col)
            row:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -22 - (r - 1) * ROW_H)
            row:SetPoint("RIGHT", col, "RIGHT", 0, 0)
            col.rows[r] = row
        end
        col:EnableMouseWheel(true)
        col:SetScript("OnMouseWheel", function(self, delta)
            self.offset = math.max(0, self.offset - delta * 3)
            -- The rows only: the board itself has not changed
            if board then PaintColumn(self, board[self.size]) end
        end)
        f.columns[i] = col
    end

    f.foot = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    f.foot:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.foot:SetJustifyH("LEFT")

    f:SetScript("OnShow", function(self)
        self:Raise()
        -- What the server will tell us for free: the roster and the friends
        if db.UseGuild and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        if db.UseFriends and C_FriendList and C_FriendList.ShowFriends then pcall(C_FriendList.ShowFriends) end
        ReadLFG()
        Paint(true)
    end)
    f:Hide()
    return f
end

function CommanderRecruit_Toggle()
    if not IsOn() then Say("off (switch it on in the settings).") return end
    local f = BuildWindow()
    f:SetShown(not f:IsShown())
end

-- ---------------------------------------------------------------------------
-- A way in from the Social window (O)
--
-- An icon in its title bar, left of the close button, so it is there on
-- every tab: the Friends tab's spare gap between its corner buttons is
-- Commander Contacts' already, and the Who tab's bottom row is full. Parented
-- to Blizzard's FriendsFrame, which is a plain panel: nothing protected is
-- touched, and the icon comes and goes with the window.
-- ---------------------------------------------------------------------------

local socialButton

function CommanderRecruit.RefreshSocialButton()
    if socialButton then socialButton:SetShown(IsOn() and db.SocialButton ~= false) end
end

local function InstallSocialButton()
    if socialButton or not FriendsFrame then return socialButton end
    local b = CreateFrame("Button", nil, FriendsFrame)
    b:SetSize(20, 20)
    b:SetFrameLevel((FriendsFrame:GetFrameLevel() or 1) + 10)
    local close = FriendsFrame.CloseButton or FriendsFrameCloseButton
    if close then
        b:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        b:SetPoint("TOPRIGHT", FriendsFrame, "TOPRIGHT", -26, -3)
    end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexture("Interface\\Icons\\INV_BannerPVP_02")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.25)
    b:SetScript("OnClick", function() CommanderRecruit_Toggle() end)
    Commander.UI.AttachTooltip(b, "Commander Recruit",
        "Rated players of your faction online right now, one ladder per bracket (also: /crecruit).", "ANCHOR_TOP")
    socialButton = b
    CommanderRecruit.RefreshSocialButton()
    return b
end
CommanderRecruit.SocialButton = function() return socialButton end

-- For the settings page and the slash command. The page is built on the
-- same PLAYER_LOGIN as this file's own handler and may ask first, so it
-- reads the saved table itself rather than the copy taken at login.
function CommanderRecruit.Status()
    local settings = db or CommanderRecruitDB
    local minutes = settings.FreshMinutes or 15
    local b = BuildBoard(settings)
    return string.format("%d seen online in the last %d min; rated: %d in 2v2, %d in 3v3, %d in 5v5.",
        b.online, minutes, #b[2], #b[3], #b[5])
end

function CommanderRecruit.Clear()
    book = E.NewBook()
    sweep, awaiting, board, preview = nil, nil, nil, nil
    wipe(ratingsCache)
    Paint(true)
end

-- For the harness
function CommanderRecruit.Book() return book end
function CommanderRecruit.Sweep() return sweep end
function CommanderRecruit.Learned() return learned end
function CommanderRecruit.Window() return window end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

BINDING_HEADER_COMMANDERRECRUIT = "Commander Recruit"
BINDING_NAME_COMMANDERRECRUIT_NEXT = "Sweep: Next /who"
BINDING_NAME_COMMANDERRECRUIT_TOGGLE = "Show Recruit"

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        db = CommanderRecruitDB
        homeRealm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and (GetRealmName() or ""):gsub("%s", ""))
        faction = UnitFactionGroup("player")
        for _, name in ipairs({ "WHO_LIST_UPDATE", "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED",
            "GUILD_ROSTER_UPDATE", "FRIENDLIST_UPDATE", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED",
            "NAME_PLATE_UNIT_ADDED" }) do
            pcall(frame.RegisterEvent, frame, name)
        end
        for name in pairs(CHAT_EVENTS) do pcall(frame.RegisterEvent, frame, name) end
        InstallSocialButton()
        -- A second chance in case Blizzard's window was not built at login
        pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
        Commander.AddListener(COMMANDER_RECRUIT_EVENTS.UPDATE, function()
            MarkDirty()
            if window and not IsOn() then window:Hide() end
            CommanderRecruit.RefreshSocialButton()
            Paint(true)
        end)
        -- The ages tick, the sweep button counts down, failed adds settle
        C_Timer.NewTicker(1, function()
            CheckFriends()
            CheckPendingAdds()
            Paint()
        end)
        RequestFriends()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        InstallSocialButton()
        return
    end
    if not IsOn() then return end
    if event == "WHO_LIST_UPDATE" then
        OnWhoList()
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        ReadLFG()
    elseif CHAT_EVENTS[event] then
        local _, sender, _, _, _, _, _, _, _, _, _, guid = ...
        OnChat(event, sender, guid)
    elseif event == "GUILD_ROSTER_UPDATE" then
        ReadGuild()
    elseif event == "FRIENDLIST_UPDATE" then
        ReadFriends()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        ReadUnit("mouseover")
    elseif event == "PLAYER_TARGET_CHANGED" then
        ReadUnit("target")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        ReadUnit((...))
    end
end)

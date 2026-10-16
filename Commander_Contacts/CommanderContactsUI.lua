-- Commander Contacts: the window.
--
-- Slack's shape, because it is the shape every messaging client has settled
-- on: a navigator down the left, the thing you picked filling the right, a
-- box at the bottom to answer from. Three tabs across the top choose what
-- the navigator lists -- Friends, Ignore, Activity -- and the right-hand
-- pane keeps one layout for all three: a header card naming who or what
-- this is with the verbs that apply, the conversation under it, the compose
-- box at the foot.
--
-- Friends and Ignore are the game's own lists read live through the host,
-- so they are never stale and never a second copy to keep in step. Activity
-- is the store: every thread, sorted, searched, with unread counts.
--
-- Chrome is drawn, not borrowed: tab underlines, selection bars, the unread
-- pill, rules and markers are quads cut from WHITE8X8 and tinted, for the
-- reasons Quest Log and Bags document -- ARIALN renders shape glyphs as
-- missing-glyph boxes and icon FILES move between client patches.
--
-- Commander Orders 3.1 (1.1.0, DECISIONS D12). Three things, each looked up
-- at the moment it is needed, so the window works the same without Orders:
--   * "Arrow To Them" in a person's menu while they are in your party or
--     raid: Orders follows them (a unit follow named by GUID, source
--     "Contacts", key "follow", so asking for someone else moves the one
--     follow). Somebody who is not grouped offers nothing: a zone name from
--     the friends list is not a place (Orders' DECISIONS; "go to their zone"
--     is not offered).
--   * Logged lines are run through CommanderOrders.Linkify when they are
--     drawn, so a "/way ..." or "Zone 45.2, 66.8" a friend sent carries a
--     [Go] like it does in chat. A line from the log has no live context
--     (where the sender was then is not where anybody is now), so a bare
--     "/way 45 66" stays text; one naming its zone or map does not.
--   * Hovering an Orders [Go] link fires EventRegistry's
--     "ChatFrame.OnHyperlinkEnter" / "...Leave", the way a chat frame does,
--     so Orders' tooltip shows; GameTooltip:SetHyperlink cannot show an
--     addon link. Clicks already reach Orders through SetItemRef.

CommanderContacts = CommanderContacts or {}
local H = CommanderContacts
local S = CommanderContactsStore
local T = CommanderContactsScout

BINDING_HEADER_COMMANDERCONTACTS = "Commander Contacts"
BINDING_NAME_COMMANDERCONTACTS_TOGGLE = "Open Contacts"
BINDING_NAME_COMMANDERCONTACTS_ACTIVITY = "Open Activity"

local QUAD = "Interface\\Buttons\\WHITE8X8"
local PAD = 10
local FRAME_W, FRAME_H = 900, 580
local TOOLBAR_H = 26
local SIDEBAR_W = 250
local SIDE_ROW_H = 36
local SIDE_HEADER_H = 22
local SIDE_TOP_H = 30
local COMPOSE_H = 24
local GROUP_GAP = 300          -- seconds before a new author header is forced

local TABS = {
    { id = "friends", label = "Friends" },
    { id = "ignore", label = "Ignore" },
    { id = "activity", label = "Activity" },
}

local FILTERS = {
    { text = "Everyone", value = "all" },
    { text = "People", value = "people" },
    { text = "Groups", value = "groups" },
    { text = "Friends Only", value = "friends" },
    { text = "Strangers", value = "others" },
}

local frame
local sideScroll, sideChild, lineScroll, lineChild
local composeBox, notesBox
local sideRows, lineRows, actionButtons = {}, {}, {}
local sideEntries = {}

-- Session state. Where the reader is, not what the reader chose: it lives
-- in the DB so the window opens where it was left, but outside
-- DefaultSettings so Restore Defaults does not reach it.
local state = {
    tab = "activity",
    selected = { friends = nil, ignore = nil, activity = nil },
    search = "",
    filter = "all",
}

local scrollBottomPending = false
local RefreshAll, RefreshSidebar, RefreshMain, RefreshTranscript, RefreshTabs
local Select, ApplyStyle, EnsureFrame, ResolveSelection

local function DB()
    return CommanderContactsDB or {}
end

local function Enabled()
    return DB().EnableContacts ~= false
end

local function Ready()
    return S and S.Attached and S.Attached()
end

local function Say(text)
    print("Commander Contacts: " .. text)
end

-- ---------------------------------------------------------------------------
-- Tint and skin (the TopBar soft-fail: Console owns the palette)
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

local SKIN = {
    pane      = { 0, 0, 0, 0.55 },
    paneEdge  = { 0.26, 0.26, 0.30, 0.90 },
    ink       = { 0.92, 0.92, 0.92 },
    inkDim    = { 0.68, 0.68, 0.70 },
    inkFaint  = { 0.48, 0.48, 0.52 },
    rule      = { 1, 1, 1, 0.15 },
    header    = { 0.62, 0.62, 0.68 },
    online    = { 0.45, 0.85, 0.45 },
    warn      = { 1.0, 0.45, 0.2 },
    selection = 0.30,
    hover     = 0.12,
}

local function Ink(fontString, shade)
    local color = SKIN[shade or "ink"] or SKIN.ink
    fontString:SetTextColor(color[1], color[2], color[3])
end

local function ClassColor(token)
    if not (token and DB().ClassColors ~= false) then return nil end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if color then return color.r, color.g, color.b end
    return nil
end

local function NameColor(fontString, token, fallbackShade)
    local r, g, b = ClassColor(token)
    if r then fontString:SetTextColor(r, g, b) else Ink(fontString, fallbackShade or "ink") end
end

-- ---------------------------------------------------------------------------
-- Small drawing helpers
-- ---------------------------------------------------------------------------

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

local function NoWrap(fontString)
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end
end

local function Rule(parent)
    local tex = Quad(parent, "ARTWORK")
    tex:SetHeight(1)
    tex:SetColorTexture(SKIN.rule[1], SKIN.rule[2], SKIN.rule[3], SKIN.rule[4])
    return tex
end

-- A chevron drawn from two bars, for a heading that folds.
local function EnsureChevron(button)
    if button.chevron then return button.chevron end
    local chevron = { Quad(button, "OVERLAY"), Quad(button, "OVERLAY") }
    for _, bar in ipairs(chevron) do bar:SetSize(6, 2) end
    button.chevron = chevron
    return chevron
end

local function PointChevron(button, open)
    local chevron = EnsureChevron(button)
    local top, bottom = chevron[1], chevron[2]
    for _, bar in ipairs(chevron) do
        bar:SetColorTexture(SKIN.header[1], SKIN.header[2], SKIN.header[3], 0.9)
        bar:Show()
    end
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if open then
        top:SetPoint("CENTER", button, "LEFT", 7, 0)
        bottom:SetPoint("CENTER", button, "LEFT", 11, 0)
        top:SetRotation(-math.pi / 4)
        bottom:SetRotation(math.pi / 4)
    else
        top:SetPoint("CENTER", button, "LEFT", 8, 1)
        bottom:SetPoint("CENTER", button, "LEFT", 8, -3)
        top:SetRotation(math.pi / 4)
        bottom:SetRotation(-math.pi / 4)
    end
end

local function HideChevron(button)
    if not button.chevron then return end
    button.chevron[1]:Hide()
    button.chevron[2]:Hide()
end

local function SetBoxEnabled(box, enabled)
    if not box then return end
    if enabled then
        if box.Enable then box:Enable() end
    else
        box:ClearFocus()
        if box.Disable then box:Disable() end
    end
end

local function Trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------------
-- Dates
-- ---------------------------------------------------------------------------

local function TimeText(stamp)
    if DB().Clock24 then return date("%H:%M", stamp) end
    return (date("%I:%M %p", stamp):gsub("^0", ""))
end

local function DayKey(stamp)
    return date("%Y-%j", stamp)
end

local function DayText(stamp)
    local now = time()
    if DayKey(stamp) == DayKey(now) then return "Today" end
    if DayKey(stamp) == DayKey(now - 86400) then return "Yesterday" end
    local today, that = date("*t", now), date("*t", stamp)
    if today.year == that.year then return date("%A, %d %B", stamp) end
    return date("%d %b %Y", stamp)
end

local function DateText(stamp)
    if not stamp or stamp <= 0 then return "" end
    local now = time()
    local diff = now - stamp
    if diff < 60 then return "now" end
    if diff < 3600 then return math.floor(diff / 60) .. "m" end
    if DayKey(stamp) == DayKey(now) then return TimeText(stamp) end
    if DayKey(stamp) == DayKey(now - 86400) then return "Yesterday" end
    if diff < 6 * 86400 then return date("%a", stamp) end
    local today, that = date("*t", now), date("*t", stamp)
    if today.year == that.year then return date("%d %b", stamp) end
    return date("%d %b %Y", stamp)
end

local function Ago(stamp)
    if not stamp or stamp <= 0 then return "never" end
    local diff = time() - stamp
    if diff < 60 then return "just now" end
    if diff < 3600 then
        local minutes = math.floor(diff / 60)
        return minutes .. (minutes == 1 and " minute ago" or " minutes ago")
    end
    if diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. (hours == 1 and " hour ago" or " hours ago")
    end
    local days = math.floor(diff / 86400)
    if days < 30 then return days .. (days == 1 and " day ago" or " days ago") end
    return date("%d %b %Y", stamp)
end

-- ---------------------------------------------------------------------------
-- Context menus and dialogs
-- ---------------------------------------------------------------------------

local menuFrame

local function ShowMenu(entries)
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "CommanderContactsContextMenu", UIParent, "UIDropDownMenuTemplate")
    end
    UIDropDownMenu_Initialize(menuFrame, function()
        for _, entry in ipairs(entries) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = entry.text
            info.notCheckable = true
            info.isTitle = entry.isTitle
            info.disabled = entry.disabled
            info.func = entry.func
            if entry.isTitle then info.notClickable = true end
            UIDropDownMenu_AddButton(info)
        end
    end, "MENU")
    ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

local function PopupBox(self)
    return self.editBox or (self.GetEditBox and self:GetEditBox())
end

-- FrameXML owns StaticPopupDialogs; keys are added to it, the global is
-- never assigned (assigning taints it, and the game menu's own
-- confirmations then start refusing protected calls).
StaticPopupDialogs["COMMANDER_CONTACTS_ADDFRIEND"] = {
    text = "Add a friend by name:",
    button1 = "Add", button2 = "Cancel",
    hasEditBox = true, maxLetters = 48,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self)
        local box = PopupBox(self)
        if box then box:SetText("") box:SetFocus() end
    end,
    OnAccept = function(self)
        local box = PopupBox(self)
        H.AddFriendByName(box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["COMMANDER_CONTACTS_ADDFRIEND"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["COMMANDER_CONTACTS_ADDIGNORE"] = {
    text = "Ignore a player by name:",
    button1 = "Ignore", button2 = "Cancel",
    hasEditBox = true, maxLetters = 48,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self)
        local box = PopupBox(self)
        if box then box:SetText("") box:SetFocus() end
    end,
    OnAccept = function(self)
        local box = PopupBox(self)
        H.IgnoreByName(box and box:GetText() or "")
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["COMMANDER_CONTACTS_ADDIGNORE"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["COMMANDER_CONTACTS_REMOVEFRIEND"] = {
    text = "Remove %s from your friends list?",
    button1 = "Remove", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(self, data)
        if data and H.RemoveFriend(data) then
            Say("removed " .. data .. " from your friends.")
            H.RequestFriends()
            RefreshAll()
        end
    end,
}

StaticPopupDialogs["COMMANDER_CONTACTS_IGNORE"] = {
    text = "Ignore %s? Their whispers will stop reaching you.",
    button1 = "Ignore", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(self, data)
        if data then H.IgnoreByName(data) end
    end,
}

StaticPopupDialogs["COMMANDER_CONTACTS_RENAME"] = {
    text = "Rename \"%s\" to:",
    button1 = "Rename", button2 = "Cancel",
    hasEditBox = true, maxLetters = 48,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
        local box = PopupBox(self)
        local conv = S.Conversation(data)
        if box then
            box:SetText(conv and conv.name or "")
            box:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        local box = PopupBox(self)
        if S.Rename(data, box and box:GetText() or "") then RefreshAll() end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["COMMANDER_CONTACTS_RENAME"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["COMMANDER_CONTACTS_CLEAR"] = {
    text = "Clear every line kept for %s? The thread stays; its history goes.",
    button1 = "Clear", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(self, data)
        if S.Clear(data) then RefreshAll() end
    end,
}

StaticPopupDialogs["COMMANDER_CONTACTS_DELETE"] = {
    text = "Delete the thread with %s and everything in it?",
    button1 = "Delete", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(self, data)
        if S.Delete(data) then
            if state.selected.activity == data then state.selected.activity = nil end
            RefreshAll()
        end
    end,
}

-- ---------------------------------------------------------------------------
-- Verbs the window and the menus share
-- ---------------------------------------------------------------------------

function H.AddFriendByName(name)
    local ok, err = H.AddFriend(Trim(name))
    if ok then
        Say("asked to add " .. Trim(name) .. " as a friend.")
        H.RequestFriends()
        RefreshAll()
    else
        Say(err or "could not add that friend.")
    end
end

function H.IgnoreByName(name)
    local ok, err = H.AddIgnore(Trim(name))
    if ok then
        Say("now ignoring " .. Trim(name) .. ".")
        RefreshAll()
    else
        Say(err or "could not ignore that player.")
    end
end

local function ConfirmRemoveFriend(name)
    StaticPopup_Show("COMMANDER_CONTACTS_REMOVEFRIEND", name, nil, name)
end

local function ConfirmIgnore(name)
    StaticPopup_Show("COMMANDER_CONTACTS_IGNORE", name, nil, name)
end

local function StopIgnoring(name)
    if H.RemoveIgnore(name) then
        Say("no longer ignoring " .. name .. ".")
        if state.selected.ignore == "ignore:" .. name then state.selected.ignore = nil end
        RefreshAll()
    else
        Say("could not remove " .. name .. " from the ignore list.")
    end
end

local function WhisperInChat(conv)
    if not H.OpenChatTo(conv) then
        if composeBox then composeBox:SetFocus() end
    end
end

local function Invite(conv)
    if not H.Invite(conv) then Say("could not invite " .. (conv and conv.name or "them") .. ".") end
end

-- ---------------------------------------------------------------------------
-- The sidebar
-- ---------------------------------------------------------------------------

local function FriendSortFn()
    local mode = DB().FriendSort or "status"
    return function(a, b)
        if mode == "level" and a.level ~= b.level then return a.level > b.level end
        return a.name:lower() < b.name:lower()
    end
end

local function BuildFriendEntries(needle)
    local entries = {}
    local online, offline = {}, {}
    for _, friend in ipairs(H.Friends()) do
        local haystack = (friend.name .. " " .. (friend.notes or "") .. " " .. (friend.area or "")
            .. " " .. (friend.className or "")):lower()
        if needle == "" or haystack:find(needle, 1, true) then
            if friend.connected then online[#online + 1] = friend else offline[#offline + 1] = friend end
        end
    end
    local sorter = FriendSortFn()
    table.sort(online, sorter)
    table.sort(offline, sorter)

    local function Add(entry) entries[#entries + 1] = entry end
    Add({ kind = "header", label = "ONLINE", count = #online })
    for _, friend in ipairs(online) do
        local short = H.Shorten(friend.name)
        local conv = S.Conversation(S.DMKey(short))
        local sub = string.format("Level %d %s", friend.level, friend.className or "")
        if friend.area and friend.area ~= "" then sub = sub .. " · " .. friend.area end
        if friend.afk then sub = "Away · " .. sub elseif friend.dnd then sub = "Busy · " .. sub end
        Add({ kind = "friend", id = "friend:" .. friend.name, label = short, sub = sub,
            class = friend.class, online = true, unread = conv and conv.unread or 0,
            friend = friend })
    end
    if DB().ShowOffline ~= false then
        Add({ kind = "header", label = "OFFLINE", count = #offline })
        for _, friend in ipairs(offline) do
            local short = H.Shorten(friend.name)
            local conv = S.Conversation(S.DMKey(short))
            local sub = friend.notes and friend.notes ~= "" and friend.notes or "Offline"
            Add({ kind = "friend", id = "friend:" .. friend.name, label = short, sub = sub,
                class = friend.class, online = false, unread = conv and conv.unread or 0,
                friend = friend })
        end
    end
    local bn = {}
    if DB().ShowBattleNet ~= false then
        for _, friend in ipairs(H.BNFriends()) do
            local haystack = (friend.name .. " " .. (friend.character or "") .. " " .. (friend.note or "")):lower()
            if needle == "" or haystack:find(needle, 1, true) then bn[#bn + 1] = friend end
        end
    end
    if #bn > 0 then
        table.sort(bn, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.name:lower() < b.name:lower()
        end)
        -- The one heading that folds: Battle.net friends are their own
        -- folder, and a search unfolds it because a hit you cannot see is
        -- worse than a fold you did not ask for.
        local folded = DB().FoldBattleNet and needle == ""
        Add({ kind = "header", label = "BATTLE.NET", count = #bn, fold = "FoldBattleNet", folded = folded })
        for _, friend in ipairs(bn) do
            if folded then break end
            local conv = S.Conversation(S.BNKey(friend.bnetID))
            local sub
            if friend.online then
                if friend.character and friend.character ~= "" then
                    sub = friend.character
                    if friend.level > 0 then sub = sub .. " · " .. friend.level end
                    if friend.className then sub = sub .. " " .. friend.className end
                    if friend.area and friend.area ~= "" then sub = sub .. " · " .. friend.area end
                else
                    sub = "Online" .. (friend.client and (" in " .. friend.client) or "")
                end
            else
                sub = "Offline"
            end
            Add({ kind = "bn", id = "bn:" .. tostring(friend.bnetID), label = friend.name, sub = sub,
                class = friend.online and friend.class or nil, online = friend.online,
                unread = conv and conv.unread or 0, friend = friend })
        end
    end
    -- Suggested: the scout's list, with the reason as the second line
    if DB().SuggestFriends ~= false then
        local suggested = {}
        for _, entry in ipairs(H.Suggestions()) do
            local haystack = (entry.name .. " " .. (entry.reason or "")):lower()
            if needle == "" or haystack:find(needle, 1, true) then suggested[#suggested + 1] = entry end
        end
        local folded = DB().FoldSuggested and needle == ""
        Add({ kind = "header", label = "SUGGESTED", count = #suggested, fold = "FoldSuggested", folded = folded })
        if not folded then
            for _, entry in ipairs(suggested) do
                Add({ kind = "suggest", id = "suggest:" .. entry.name, label = entry.name, sub = entry.reason,
                    class = entry.class, suggestion = entry })
            end
        end
    end
    return entries
end

local function BuildIgnoreEntries(needle)
    local entries = {}
    local list = {}
    for _, entry in ipairs(H.Ignores()) do
        if needle == "" or entry.short:lower():find(needle, 1, true) then list[#list + 1] = entry end
    end
    table.sort(list, function(a, b) return a.short:lower() < b.short:lower() end)
    entries[#entries + 1] = { kind = "header", label = "IGNORED", count = #list }
    for _, entry in ipairs(list) do
        local conv = S.Conversation(S.DMKey(entry.short))
        local sub = "Ignored"
        if conv and #conv.messages > 0 then
            sub = "Ignored · last heard " .. DateText(conv.updated)
        end
        entries[#entries + 1] = { kind = "ignore", id = "ignore:" .. entry.name, label = entry.short,
            sub = sub, name = entry.name }
    end
    return entries
end

local function BuildActivityEntries(needle)
    local entries = {}
    local filter = state.filter or "all"
    local query = {
        search = needle,
        sort = DB().ActivitySort or "recent",
        friends = H.FriendSet(),
    }
    local people, groups = {}, {}
    if filter ~= "groups" then
        query.kind = "people"
        query.filter = (filter == "friends" or filter == "others") and filter or "all"
        people = S.List(query)
    end
    if filter == "all" or filter == "groups" then
        query.kind = "group"
        query.filter = "all"
        groups = S.List(query)
    end
    local friends = H.FriendSet()
    local function Add(entry) entries[#entries + 1] = entry end
    if filter ~= "groups" then
        Add({ kind = "header", label = "PEOPLE", count = #people })
        for _, conv in ipairs(people) do
            Add({ kind = "conv", id = conv.key, label = conv.name, sub = S.PreviewFor(conv, 48),
                class = conv.class, time = DateText(conv.updated), unread = conv.unread or 0,
                marked = conv.kind == "bn" or (friends[conv.name] and true or false),
                pinned = conv.pinned, conv = conv })
        end
    end
    if filter == "all" or filter == "groups" then
        Add({ kind = "header", label = "GROUPS", count = #groups })
        local active = S.ActiveGroup()
        for _, conv in ipairs(groups) do
            Add({ kind = "conv", id = conv.key, label = conv.name, sub = S.PreviewFor(conv, 48),
                time = DateText(conv.updated), unread = conv.unread or 0,
                live = active and active.key == conv.key, pinned = conv.pinned, conv = conv })
        end
    end
    return entries
end

-- ---------------------------------------------------------------------------
-- Commander Orders 3.1: "Arrow To Them" and [Go] links (see the header)
-- ---------------------------------------------------------------------------
local Go = { links = setmetatable({}, { __mode = "k" }) }

-- The party or raid token a person stands on right now (by GUID when the
-- thread knows one, else by name), never yourself; nil when not grouped
function Go.Token(name, guid)
    if not (UnitExists and UnitGUID) then return nil end
    local short = type(name) == "string" and (name:match("^([^%-]+)") or name) or nil
    local raid = IsInRaid and IsInRaid()
    for i = 1, raid and 40 or 4 do
        local token = (raid and "raid" or "party") .. i
        if UnitExists(token) and not (UnitIsUnit and UnitIsUnit(token, "player")) then
            if guid and UnitGUID(token) == guid then return token end
            if short and UnitName and UnitName(token) == short then return token end
        end
    end
    return nil
end

-- The menu entry, or nil when it has nothing to offer (Orders absent, the
-- person not in your group)
function Go.Entry(name, guid)
    local api = CommanderOrders
    if not (type(api) == "table" and type(api.GoTo) == "function") then return nil end
    if not Go.Token(name, guid) then return nil end
    return { text = "Arrow To Them", func = function()
        local token = Go.Token(name, guid)
        if not token then
            Say((name or "they") .. " is no longer in your group.")
            return
        end
        -- Not silent: Orders says "Waypoint set" or its one refusal line
        api.GoTo({ kind = "unit", unit = token, guid = UnitGUID(token) }, {
            title = (name and name:match("^([^%-]+)")) or name, source = "Contacts", key = "follow", icon = "UNIT",
        })
    end }
end

-- A logged line with Orders' [Go] links, kept per message until its text or
-- the Chat Links setting changes
function Go.Linked(message)
    local text = message.text
    local api = CommanderOrders
    if not (type(api) == "table" and type(api.Linkify) == "function") then return text end
    local on = not (type(CommanderOrdersDB) == "table" and CommanderOrdersDB.ChatLinks == false)
    local hit = Go.links[message]
    if hit and hit.src == text and hit.on == on then return hit.out end
    local ok, out = pcall(api.Linkify, text, {})
    if not ok or type(out) ~= "string" then out = text end
    Go.links[message] = { src = text, on = on, out = out }
    return out
end

-- An Orders link's hover, as a chat frame fires it (Orders shows the tooltip)
function Go.Hover(event, row, link, text)
    local reg = EventRegistry
    if type(reg) == "table" and type(reg.TriggerEvent) == "function" then
        pcall(reg.TriggerEvent, reg, event, row, link, text)
    end
end

local function RowMenu(entry)
    if entry.kind == "friend" then
        local short = entry.label
        local conv = S.EnsureDM(short, { class = entry.class })
        local items = {
            { text = short, isTitle = true },
            { text = "Whisper In Chat", func = function() WhisperInChat(conv) end },
            { text = "Invite To Group", func = function() Invite(conv) end },
        }
        local arrow = Go.Entry(short, conv.guid)
        if arrow then items[#items + 1] = arrow end
        items[#items + 1] = { text = "Open In Activity", func = function() H.OpenConversation(conv.key) end }
        items[#items + 1] = { text = "Ignore...", func = function() ConfirmIgnore(entry.friend.name) end }
        items[#items + 1] = { text = "Remove Friend...", func = function() ConfirmRemoveFriend(entry.friend.name) end }
        ShowMenu(items)
    elseif entry.kind == "bn" then
        local conv = S.EnsureBN(entry.friend.bnetID, entry.label)
        conv.gameAccountID = entry.friend.gameAccountID
        ShowMenu({
            { text = entry.label, isTitle = true },
            { text = "Invite To Group", disabled = not entry.online, func = function() Invite(conv) end },
            { text = "Open In Activity", func = function() H.OpenConversation(conv.key) end },
        })
    elseif entry.kind == "ignore" then
        ShowMenu({
            { text = entry.label, isTitle = true },
            { text = "Stop Ignoring", func = function() StopIgnoring(entry.name) end },
        })
    elseif entry.kind == "suggest" then
        local conv = S.EnsureDM(entry.label, { class = entry.class })
        ShowMenu({
            { text = entry.label, isTitle = true },
            { text = "Add Friend", func = function() H.AddFriendByName(entry.label) end },
            { text = "Whisper In Chat", func = function() WhisperInChat(conv) end },
            { text = "Invite To Group", func = function() Invite(conv) end },
            { text = "Not Interested", func = function() H.DismissSuggestion(entry.label) RefreshAll(false) end },
        })
    elseif entry.kind == "conv" then
        local conv = entry.conv
        local items = { { text = conv.name, isTitle = true } }
        if conv.kind == "dm" then
            local isFriend = H.IsFriend(conv.name)
            items[#items + 1] = { text = "Whisper In Chat", func = function() WhisperInChat(conv) end }
            items[#items + 1] = { text = "Invite To Group", func = function() Invite(conv) end }
            local arrow = Go.Entry(conv.name, conv.guid)
            if arrow then items[#items + 1] = arrow end
            if isFriend then
                items[#items + 1] = { text = "Remove Friend...", func = function() ConfirmRemoveFriend(conv.target or conv.name) end }
            else
                items[#items + 1] = { text = "Add Friend", func = function() H.AddFriendByName(conv.target or conv.name) end }
            end
            if H.IsIgnored(conv.name) then
                items[#items + 1] = { text = "Stop Ignoring", func = function() StopIgnoring(conv.target or conv.name) end }
            else
                items[#items + 1] = { text = "Ignore...", func = function() ConfirmIgnore(conv.target or conv.name) end }
            end
        elseif conv.kind == "group" then
            items[#items + 1] = { text = "Rename...", func = function()
                StaticPopup_Show("COMMANDER_CONTACTS_RENAME", conv.name, nil, conv.key)
            end }
        end
        items[#items + 1] = { text = conv.pinned and "Unpin" or "Pin To Top", func = function()
            S.SetPinned(conv.key, not conv.pinned)
            RefreshSidebar()
        end }
        items[#items + 1] = { text = (conv.unread or 0) > 0 and "Mark As Read" or "Mark As Unread", func = function()
            if (conv.unread or 0) > 0 then S.MarkRead(conv.key) else conv.unread = 1 end
            RefreshAll()
        end }
        items[#items + 1] = { text = "Clear History...", func = function()
            StaticPopup_Show("COMMANDER_CONTACTS_CLEAR", conv.name, nil, conv.key)
        end }
        items[#items + 1] = { text = "Delete Thread...", func = function()
            StaticPopup_Show("COMMANDER_CONTACTS_DELETE", conv.name, nil, conv.key)
        end }
        ShowMenu(items)
    end
end

local function BuildSideRow(index)
    if sideRows[index] then return sideRows[index] end
    local row = CreateFrame("Button", nil, sideChild)
    row:SetHeight(SIDE_ROW_H)
    row:SetPoint("LEFT", sideChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", sideChild, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = Quad(row, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.bar = Quad(row, "ARTWORK")
    row.bar:SetWidth(3)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    row.bar:Hide()

    -- The marker: online for a friend, "on your list" for a thread, live
    -- for the party you are in. A 6px square, tinted per meaning.
    row.dot = Quad(row, "ARTWORK")
    row.dot:SetSize(6, 6)
    row.dot:SetPoint("LEFT", row, "LEFT", 9, 6)
    row.dot:Hide()

    row.time = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.time:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
    row.time:SetJustifyH("RIGHT")

    -- The unread pill: a tinted quad with a number on it
    row.pill = Quad(row, "ARTWORK")
    row.pill:SetHeight(14)
    row.pill:SetPoint("RIGHT", row, "RIGHT", -8, -6)
    row.pill:Hide()
    row.pillText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.pillText:SetPoint("CENTER", row.pill, "CENTER", 0, 0)
    row.pillText:Hide()

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -5)
    row.label:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
    row.label:SetJustifyH("LEFT")
    NoWrap(row.label)

    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sub:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.sub:SetJustifyH("LEFT")
    NoWrap(row.sub)

    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.count:SetJustifyH("RIGHT")

    row:SetScript("OnEnter", function(self)
        if not self.selected and self.entry and self.entry.kind ~= "header" then
            local r, g, b = Accent()
            self.highlight:SetColorTexture(r, g, b, SKIN.hover)
            self.highlight:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.selected then self.highlight:Hide() end
    end)
    row:SetScript("OnClick", function(self, button)
        local entry = self.entry
        if not entry then return end
        if entry.kind == "header" then
            if entry.fold then
                CommanderContactsDB[entry.fold] = not CommanderContactsDB[entry.fold]
                RefreshSidebar()
            end
            return
        end
        if button == "RightButton" then
            RowMenu(entry)
            return
        end
        Select(entry.id)
    end)

    sideRows[index] = row
    return row
end

function RefreshSidebar()
    if not sideChild then return end
    local needle = Trim(state.search):lower()
    if state.tab == "friends" then
        sideEntries = BuildFriendEntries(needle)
    elseif state.tab == "ignore" then
        sideEntries = BuildIgnoreEntries(needle)
    else
        sideEntries = BuildActivityEntries(needle)
    end

    local r, g, b = Accent()
    local selectedID = state.selected[state.tab]
    local offset = 0
    for index, entry in ipairs(sideEntries) do
        local row = BuildSideRow(index)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, -offset)
        row:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, -offset)
        row.pill:Hide()
        row.pillText:Hide()
        row.dot:Hide()
        row.bar:Hide()
        row.highlight:Hide()
        row.selected = false

        if entry.kind == "header" then
            row:SetHeight(SIDE_HEADER_H)
            row:EnableMouse(entry.fold ~= nil)
            row.label:ClearAllPoints()
            if entry.fold then
                PointChevron(row, not entry.folded)
                row.label:SetPoint("LEFT", row, "LEFT", 18, -2)
            else
                HideChevron(row)
                row.label:SetPoint("LEFT", row, "LEFT", 8, -2)
            end
            row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
            row.label:SetText(entry.label)
            row.label:SetTextColor(SKIN.header[1], SKIN.header[2], SKIN.header[3])
            row.sub:SetText("")
            row.time:SetText("")
            row.count:SetText(tostring(entry.count or ""))
            Ink(row.count, "inkFaint")
        else
            row:SetHeight(SIDE_ROW_H)
            row:EnableMouse(true)
            HideChevron(row)
            row.label:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 20, -5)
            row.label:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
            row.label:SetText(entry.label)
            row.sub:SetText(entry.sub or "")
            row.time:SetText(entry.time or "")
            row.count:SetText("")
            Ink(row.time, "inkFaint")

            local unread = entry.unread or 0
            if unread > 0 then
                row.pillText:SetText(unread > 99 and "99+" or tostring(unread))
                row.pillText:SetTextColor(0.05, 0.05, 0.05)
                local width = (row.pillText.GetStringWidth and row.pillText:GetStringWidth() or 8) + 10
                row.pill:SetWidth(math.max(width, 18))
                row.pill:SetColorTexture(r, g, b, 0.95)
                row.pill:Show()
                row.pillText:Show()
                row.time:SetText("")
                Ink(row.sub, "ink")
            else
                Ink(row.sub, "inkFaint")
            end

            if entry.kind == "friend" or entry.kind == "bn" then
                if entry.online then
                    row.dot:SetColorTexture(SKIN.online[1], SKIN.online[2], SKIN.online[3], 1)
                    row.dot:Show()
                    NameColor(row.label, entry.class, "ink")
                else
                    Ink(row.label, "inkDim")
                end
            elseif entry.kind == "ignore" then
                Ink(row.label, "inkDim")
            elseif entry.kind == "suggest" then
                NameColor(row.label, entry.class, "ink")
            else
                if entry.live then
                    row.dot:SetColorTexture(SKIN.online[1], SKIN.online[2], SKIN.online[3], 1)
                    row.dot:Show()
                elseif entry.marked then
                    row.dot:SetColorTexture(r, g, b, 0.9)
                    row.dot:Show()
                end
                NameColor(row.label, entry.class, unread > 0 and "ink" or "inkDim")
                if entry.pinned then row.time:SetText("pinned" .. (entry.time ~= "" and (" · " .. entry.time) or "")) end
            end

            if entry.id == selectedID then
                row.selected = true
                row.highlight:SetColorTexture(r, g, b, SKIN.selection)
                row.highlight:Show()
                row.bar:SetColorTexture(r, g, b, 1)
                row.bar:Show()
                Ink(row.label, "ink")
                NameColor(row.label, entry.class, "ink")
            end
        end
        row:Show()
        offset = offset + row:GetHeight()
    end
    for index = #sideEntries + 1, #sideRows do
        sideRows[index]:Hide()
    end
    sideChild:SetHeight(math.max(offset, 1))

    if frame.sideEmpty then
        local anyRow = false
        for _, entry in ipairs(sideEntries) do
            if entry.kind ~= "header" then anyRow = true break end
        end
        if anyRow then
            frame.sideEmpty:Hide()
        else
            if state.tab == "friends" then
                frame.sideEmpty:SetText(needle ~= "" and "No friend matches that." or "No friends yet.\n\nAdd one with the button above, or right-click a thread in Activity.")
            elseif state.tab == "ignore" then
                frame.sideEmpty:SetText(needle ~= "" and "No ignored player matches that." or "You are not ignoring anyone.")
            else
                frame.sideEmpty:SetText(needle ~= "" and "Nothing matches that." or "Nothing kept yet.\n\nWhispers and party chat will appear here as they arrive.")
            end
            Ink(frame.sideEmpty, "inkFaint")
            frame.sideEmpty:Show()
        end
    end
end

-- ---------------------------------------------------------------------------
-- The transcript
-- ---------------------------------------------------------------------------

local function BuildLineRow(index)
    if lineRows[index] then return lineRows[index] end
    local row = CreateFrame("Frame", nil, lineChild)
    row:SetPoint("LEFT", lineChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", lineChild, "RIGHT", 0, 0)

    row.author = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.author:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -2)
    row.author:SetJustifyH("LEFT")
    NoWrap(row.author)

    row.time = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.time:SetPoint("LEFT", row.author, "RIGHT", 6, 0)
    row.time:SetJustifyH("LEFT")

    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -2)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(true) end
    if row.text.SetNonSpaceWrap then row.text:SetNonSpaceWrap(true) end

    row.rule = Rule(row)
    row.rule:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.rule:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.rule:Hide()

    row.day = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.day:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.dayBg = Quad(row, "ARTWORK", 1)
    row.dayBg:SetPoint("TOPLEFT", row.day, "TOPLEFT", -8, 2)
    row.dayBg:SetPoint("BOTTOMRIGHT", row.day, "BOTTOMRIGHT", 8, -2)
    row.dayBg:Hide()
    row.day:Hide()

    -- Item and spell links in a line are real links: hover for the tooltip,
    -- click for what the client does with that link type. The frame owns the
    -- FontString, so the hyperlink scripts land here.
    if row.SetHyperlinksEnabled then row:SetHyperlinksEnabled(true) end
    row:SetScript("OnHyperlinkClick", function(_, link, text, button)
        if SetItemRef then SetItemRef(link, text, button) end
    end)
    row:SetScript("OnHyperlinkEnter", function(self, link, text)
        if type(link) == "string" and link:sub(1, 6) == "addon:" then
            Go.Hover("ChatFrame.OnHyperlinkEnter", self, link, text)
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then GameTooltip:Show() end
    end)
    -- Leave: Orders hides a tooltip of its own (whatever the client passes
    -- here), and this row hides whatever it showed
    row:SetScript("OnHyperlinkLeave", function(self, link, text)
        Go.Hover("ChatFrame.OnHyperlinkLeave", self, link, text)
        GameTooltip:Hide()
    end)

    lineRows[index] = row
    return row
end

local CHANNEL_TAGS = {
    LEADER = "|cffffc864[Leader]|r ",
    RAID_LEADER = "|cffff7d00[Raid Leader]|r ",
    RAID_WARNING = "|cffff4800[Warning]|r ",
    INSTANCE_LEADER = "|cffff7d00[Leader]|r ",
}

local function TextHeight(fontString)
    local height = fontString.GetStringHeight and fontString:GetStringHeight()
    if type(height) ~= "number" or height <= 0 then height = 14 end
    return height
end

local function ScrollToBottom()
    if not lineScroll then return end
    if lineScroll.UpdateScrollChildRect then lineScroll:UpdateScrollChildRect() end
    local range = lineScroll:GetVerticalScrollRange() or 0
    lineScroll:SetVerticalScroll(math.max(range, 0))
end

-- Draws conv's lines. `stick` keeps the view at the bottom; a refresh
-- caused by a new line only sticks when the reader was already there.
function RefreshTranscript(conv, stick)
    if not lineChild then return end
    local messages = conv and conv.messages or {}
    local width = (lineScroll:GetWidth() or 300) - 8
    if width < 100 then width = 100 end
    lineChild:SetWidth(width)

    local wasAtBottom = true
    if lineScroll then
        local range = lineScroll:GetVerticalScrollRange() or 0
        local at = lineScroll:GetVerticalScroll() or 0
        wasAtBottom = (range - at) < 40
    end

    local r, g, b = Accent()
    local showTime = DB().ShowTimestamps ~= false
    local dividers = DB().DayDividers ~= false
    local used, offset = 0, 4
    local lastFrom, lastT, lastDay = nil, nil, nil

    local function NextRow()
        used = used + 1
        local row = BuildLineRow(used)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", lineChild, "TOPLEFT", 0, -offset)
        row:SetPoint("TOPRIGHT", lineChild, "TOPRIGHT", 0, -offset)
        row.author:Hide()
        row.time:Hide()
        row.text:Hide()
        row.rule:Hide()
        row.day:Hide()
        row.dayBg:Hide()
        row:Show()
        return row
    end

    for _, message in ipairs(messages) do
        local day = DayKey(message.t)
        if dividers and day ~= lastDay then
            local row = NextRow()
            row:SetHeight(22)
            row.rule:ClearAllPoints()
            row.rule:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.rule:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.rule:Show()
            row.day:SetText(DayText(message.t))
            Ink(row.day, "inkFaint")
            row.dayBg:SetColorTexture(0.08, 0.08, 0.09, 1)
            row.day:Show()
            row.dayBg:Show()
            offset = offset + 22
            lastFrom = nil
        end
        lastDay = day

        local row = NextRow()
        local header = (message.from ~= lastFrom) or (lastT and (message.t - lastT) > GROUP_GAP)
        local top = 2
        if header then
            row.author:SetText(message.out and "You" or message.from)
            if message.out then
                row.author:SetTextColor(r, g, b)
            else
                NameColor(row.author, message.cls, "ink")
            end
            row.author:Show()
            if showTime then
                row.time:SetText(TimeText(message.t))
                Ink(row.time, "inkFaint")
                row.time:Show()
            end
            top = 16
        end
        local text = Go.Linked(message)
        local tag = CHANNEL_TAGS[message.ch or ""]
        if tag then text = tag .. text end
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -top)
        row.text:SetWidth(width - 16)
        row.text:SetText(text)
        Ink(row.text, "ink")
        row.text:Show()
        local height = top + TextHeight(row.text) + (header and 6 or 3)
        row:SetHeight(height)
        offset = offset + height
        lastFrom, lastT = message.from, message.t
    end

    for index = used + 1, #lineRows do
        lineRows[index]:Hide()
    end
    lineChild:SetHeight(math.max(offset + 4, 1))

    if frame.lineEmpty then
        if #messages == 0 then
            frame.lineEmpty:SetText(frame.lineEmptyText or "No messages yet.")
            Ink(frame.lineEmpty, "inkFaint")
            frame.lineEmpty:Show()
        else
            frame.lineEmpty:Hide()
        end
    end

    if stick or wasAtBottom then
        ScrollToBottom()
        scrollBottomPending = true
    end
end

-- ---------------------------------------------------------------------------
-- The main pane
--
-- One layout, three tabs. ResolveSelection turns whatever is selected into
-- a view: a title, a subtitle, the verbs that apply, the thread to draw and
-- whether the compose box may send. RefreshMain only draws it.
-- ---------------------------------------------------------------------------

local function FriendRecord(name)
    for _, friend in ipairs(H.Friends()) do
        if friend.name == name or H.Shorten(friend.name) == name then return friend end
    end
    return nil
end

local function BNRecord(bnetID)
    bnetID = tonumber(bnetID)
    for _, friend in ipairs(H.BNFriends()) do
        if friend.bnetID == bnetID then return friend end
    end
    return nil
end

local function FriendStatus(friend)
    if not friend then return "Not on your friends list" end
    if not friend.connected then return "Offline" end
    local pieces = { string.format("Online · Level %d %s", friend.level, friend.className or "") }
    if friend.area and friend.area ~= "" then pieces[#pieces + 1] = friend.area end
    if friend.afk then pieces[#pieces + 1] = "Away" elseif friend.dnd then pieces[#pieces + 1] = "Busy" end
    return table.concat(pieces, " · ")
end

function ResolveSelection()
    local id = state.selected[state.tab]
    if not id then return nil end
    local view = { id = id, actions = {}, canCompose = false }

    if state.tab == "friends" then
        if id:match("^friend:") then
            local name = id:sub(8)
            local friend = FriendRecord(name)
            if not friend then return nil end
            local short = H.Shorten(friend.name)
            local conv = S.Conversation(S.DMKey(short))
            view.title = short
            view.class = friend.connected and friend.class or (conv and conv.class)
            view.subtitle = FriendStatus(friend)
            view.notes = friend.notes or ""
            view.notesName = friend.name
            view.conv = conv
            view.emptyText = "No whispers with " .. short .. " yet. Say hello below."
            view.canCompose = true
            view.composeHint = "Message " .. short
            -- A thread a whisper already created knows the full Name-Realm
            -- it came from; the friends list only knows the short name. The
            -- fuller one is kept, so only the class and GUID are refreshed.
            view.send = function(text)
                local target = S.EnsureDM(short, { class = friend.class, guid = friend.guid })
                return H.Send(target, text)
            end
            view.actions = {
                { label = "Whisper", width = 80, tooltip = "Put /w " .. short .. " in the chat box.",
                    onClick = function() WhisperInChat(S.EnsureDM(short)) end },
                { label = "Invite", width = 70, tooltip = "Invite " .. short .. " to your group.",
                    onClick = function() Invite(S.EnsureDM(short)) end },
                { label = "Ignore", width = 70, tooltip = "Move " .. short .. " to the ignore list.",
                    onClick = function() ConfirmIgnore(friend.name) end },
                { label = "Remove", width = 80, tooltip = "Remove " .. short .. " from your friends.",
                    onClick = function() ConfirmRemoveFriend(friend.name) end },
            }
        elseif id:match("^bn:") then
            local bnetID = tonumber(id:sub(4))
            local friend = BNRecord(bnetID)
            if not friend then return nil end
            local conv = S.Conversation(S.BNKey(bnetID))
            view.title = friend.name
            view.class = friend.online and friend.class or nil
            if friend.online then
                local pieces = { "Online" }
                if friend.character and friend.character ~= "" then
                    local who = friend.character
                    if friend.level > 0 then who = who .. ", level " .. friend.level end
                    if friend.className then who = who .. " " .. friend.className end
                    if friend.realm and friend.realm ~= "" then who = who .. " on " .. friend.realm end
                    pieces[#pieces + 1] = who
                elseif friend.client then
                    pieces[#pieces + 1] = "in " .. friend.client
                end
                if friend.area and friend.area ~= "" then pieces[#pieces + 1] = friend.area end
                view.subtitle = table.concat(pieces, " · ")
            else
                view.subtitle = "Offline"
            end
            if friend.custom and friend.custom ~= "" then
                view.subtitle = view.subtitle .. "\n\"" .. friend.custom .. "\""
            end
            if friend.battleTag and friend.battleTag ~= "" then view.notes = friend.battleTag end
            view.notesReadOnly = true
            view.conv = conv
            view.emptyText = "No Battle.net whispers with " .. friend.name .. " yet."
            view.canCompose = true
            view.composeHint = "Message " .. friend.name
            view.send = function(text)
                local target = S.EnsureBN(bnetID, friend.name)
                target.gameAccountID = friend.gameAccountID
                return H.Send(target, text)
            end
            view.actions = {
                { label = "Invite", width = 70, tooltip = "Invite this friend's character to your group.",
                    onClick = function()
                        local target = S.EnsureBN(bnetID, friend.name)
                        target.gameAccountID = friend.gameAccountID
                        Invite(target)
                    end },
            }
        elseif id:match("^suggest:") then
            local name = id:sub(9)
            local suggestion
            for _, entry in ipairs(H.Suggestions()) do
                if entry.name == name then suggestion = entry break end
            end
            if not suggestion then return nil end
            local conv = S.Conversation(S.DMKey(name))
            view.title = name
            view.class = suggestion.class
            view.subtitle = suggestion.reason .. "\n" .. (suggestion.detail or "")
            view.conv = conv
            view.emptyText = "No whispers with " .. name .. " yet. Say hello below."
            view.canCompose = true
            view.composeHint = "Message " .. name
            view.send = function(text)
                return H.Send(S.EnsureDM(name, { class = suggestion.class }), text)
            end
            view.actions = {
                { label = "Add Friend", width = 90, tooltip = "Add " .. name .. " to your friends.",
                    onClick = function() H.AddFriendByName(name) end },
                { label = "Whisper", width = 80, tooltip = "Put /w " .. name .. " in the chat box.",
                    onClick = function() WhisperInChat(S.EnsureDM(name, { class = suggestion.class })) end },
                { label = "Invite", width = 70, tooltip = "Invite " .. name .. " to your group.",
                    onClick = function() Invite(S.EnsureDM(name, { class = suggestion.class })) end },
                { label = "Not Interested", width = 110, tooltip = "Take " .. name .. " off the list for good.",
                    onClick = function()
                        H.DismissSuggestion(name)
                        state.selected.friends = nil
                        RefreshAll(false)
                    end },
            }
        end
    elseif state.tab == "ignore" then
        local name = id:sub(8)
        local short = H.Shorten(name)
        local conv = S.Conversation(S.DMKey(short))
        view.title = short
        view.subtitle = "On your ignore list"
        if conv and #conv.messages > 0 then
            view.subtitle = view.subtitle .. " · last heard " .. Ago(conv.updated)
        end
        view.conv = conv
        view.emptyText = "Nothing kept from " .. short .. "."
        view.canCompose = false
        view.composeHint = "You are ignoring " .. short .. "."
        view.actions = {
            { label = "Stop Ignoring", width = 110, tooltip = "Take " .. short .. " off the ignore list.",
                onClick = function() StopIgnoring(name) end },
        }
    else
        local conv = S.Conversation(id)
        if not conv then return nil end
        view.conv = conv
        view.title = conv.name
        view.emptyText = "Nothing here yet."
        if conv.kind == "dm" then
            local friend = FriendRecord(conv.name)
            local isFriend = friend ~= nil or H.IsFriend(conv.name)
            local ignored = H.IsIgnored(conv.name)
            view.class = (friend and friend.connected and friend.class) or conv.class
            local pieces = {}
            if ignored then pieces[#pieces + 1] = "Ignored"
            elseif friend then pieces[#pieces + 1] = friend.connected and "Friend · online" or "Friend · offline"
            else pieces[#pieces + 1] = "Not on your friends list" end
            if friend and friend.connected then
                pieces[#pieces + 1] = string.format("Level %d %s", friend.level, friend.className or "")
                if friend.area and friend.area ~= "" then pieces[#pieces + 1] = friend.area end
            end
            pieces[#pieces + 1] = "last " .. Ago(conv.updated)
            view.subtitle = table.concat(pieces, " · ")
            view.canCompose = not ignored
            view.composeHint = ignored and ("You are ignoring " .. conv.name .. ".") or ("Message " .. conv.name)
            view.send = function(text) return H.Send(conv, text) end
            view.actions = {
                { label = "Whisper", width = 80, tooltip = "Put /w " .. conv.name .. " in the chat box.",
                    onClick = function() WhisperInChat(conv) end },
                { label = "Invite", width = 70, tooltip = "Invite " .. conv.name .. " to your group.",
                    onClick = function() Invite(conv) end },
            }
            if isFriend then
                view.actions[#view.actions + 1] = { label = "Remove Friend", width = 110,
                    tooltip = "Remove " .. conv.name .. " from your friends.",
                    onClick = function() ConfirmRemoveFriend(conv.target or conv.name) end }
            else
                view.actions[#view.actions + 1] = { label = "Add Friend", width = 90,
                    tooltip = "Add " .. conv.name .. " to your friends.",
                    onClick = function() H.AddFriendByName(conv.target or conv.name) end }
            end
            if ignored then
                view.actions[#view.actions + 1] = { label = "Stop Ignoring", width = 110,
                    onClick = function() StopIgnoring(conv.target or conv.name) end }
            else
                view.actions[#view.actions + 1] = { label = "Ignore", width = 70,
                    tooltip = "Move " .. conv.name .. " to the ignore list.",
                    onClick = function() ConfirmIgnore(conv.target or conv.name) end }
            end
        elseif conv.kind == "bn" then
            local friend = BNRecord(conv.target)
            view.class = friend and friend.online and friend.class or nil
            view.subtitle = "Battle.net · " .. (friend and (friend.online and "online" or "offline") or "no longer a friend")
                .. " · last " .. Ago(conv.updated)
            view.canCompose = friend ~= nil
            view.composeHint = friend and ("Message " .. conv.name) or "No longer on your Battle.net friends."
            view.send = function(text) return H.Send(conv, text) end
            if friend then
                conv.gameAccountID = friend.gameAccountID
                view.actions = {
                    { label = "Invite", width = 70, onClick = function() Invite(conv) end },
                }
            end
        else
            local active = S.ActiveGroup()
            local live = active and active.key == conv.key
            local pieces = { S.GroupLabel(conv.groupType) .. " with " .. S.MemberSummary(conv, 4) }
            if live then
                pieces[#pieces + 1] = "in progress since " .. TimeText(conv.started)
            elseif conv.ended then
                pieces[#pieces + 1] = "ended " .. Ago(conv.ended)
            end
            view.subtitle = table.concat(pieces, " · ")
            view.canCompose = live and true or false
            view.composeHint = live and ("Message the " .. S.GroupLabel(conv.groupType):lower()) or "This group has ended."
            view.send = function(text) return H.Send(conv, text) end
            view.actions = {
                { label = "Rename", width = 76, tooltip = "Give this thread a name you will recognise.",
                    onClick = function() StaticPopup_Show("COMMANDER_CONTACTS_RENAME", conv.name, nil, conv.key) end },
            }
        end
        view.actions[#view.actions + 1] = { label = "Clear", width = 64,
            tooltip = "Drop every line kept here. The thread stays.",
            onClick = function() StaticPopup_Show("COMMANDER_CONTACTS_CLEAR", conv.name, nil, conv.key) end }
        view.actions[#view.actions + 1] = { label = "Delete", width = 70,
            tooltip = "Delete this thread and everything in it.",
            onClick = function() StaticPopup_Show("COMMANDER_CONTACTS_DELETE", conv.name, nil, conv.key) end }
    end
    return view
end

local function LayoutActions(specs)
    local previous
    for index, spec in ipairs(specs) do
        local button = actionButtons[index]
        if not button then
            button = CreateFrame("Button", nil, frame.headerCard, "UIPanelButtonTemplate")
            button:SetHeight(21)
            button:SetScript("OnClick", function(self)
                if self.onClick then self.onClick() end
            end)
            button:SetScript("OnEnter", function(self)
                if not self.tooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            actionButtons[index] = button
        end
        button:SetWidth(spec.width or 80)
        button:SetText(spec.label)
        button.onClick = spec.onClick
        button.tooltip = spec.tooltip
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("BOTTOMLEFT", frame.headerCard, "BOTTOMLEFT", 10, 6)
        end
        button:Show()
        previous = button
    end
    for index = #specs + 1, #actionButtons do
        actionButtons[index]:Hide()
    end
end

-- `stick` pins the transcript to its newest line. A selection or tab change
-- passes true; a roster or settings refresh passes false, because a friend
-- coming online must not yank a thread you are reading back to the bottom.
function RefreshMain(stick)
    if not frame then return end
    local view = ResolveSelection()
    frame.currentView = view
    local card = frame.headerCard

    if not view then
        card:Hide()
        lineScroll:Hide()
        composeBox:Hide()
        frame.composeHint:Hide()
        frame.lineEmpty:Hide()
        if state.tab == "friends" then
            frame.mainEmpty:SetText("Pick a friend on the left.\n\nWhat they are doing, your notes on them, and every whisper between you. Under the list: people from your battlegrounds worth adding.")
        elseif state.tab == "ignore" then
            frame.mainEmpty:SetText("Pick a name on the left.")
        else
            frame.mainEmpty:SetText("Pick a thread on the left.\n\nPeople are everyone who has whispered you; groups are every party you have been in.")
        end
        Ink(frame.mainEmpty, "inkFaint")
        frame.mainEmpty:Show()
        return
    end

    frame.mainEmpty:Hide()
    card:Show()
    lineScroll:Show()

    card.title:SetText(view.title or "")
    NameColor(card.title, view.class, "ink")
    card.subtitle:SetText(view.subtitle or "")
    Ink(card.subtitle, "inkDim")

    local height = 30 + 16
    if view.subtitle and view.subtitle:find("\n") then height = height + 12 end
    if view.notes ~= nil then
        frame.notesLabel:Show()
        notesBox:Show()
        notesBox:SetText(view.notes or "")
        notesBox:SetCursorPosition(0)
        notesBox.friendName = view.notesName
        SetBoxEnabled(notesBox, not view.notesReadOnly)
        frame.notesLabel:SetText(view.notesReadOnly and "BattleTag" or "Notes")
        Ink(frame.notesLabel, "inkFaint")
        frame.notesLabel:ClearAllPoints()
        frame.notesLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -height - 2)
        height = height + 24
    else
        frame.notesLabel:Hide()
        notesBox:Hide()
        notesBox.friendName = nil
    end
    height = height + 30
    card:SetHeight(height)
    LayoutActions(view.actions or {})

    frame.lineEmptyText = view.emptyText
    RefreshTranscript(view.conv, stick ~= false)

    composeBox:Show()
    SetBoxEnabled(composeBox, view.canCompose)
    composeBox.send = view.send
    frame.composeHint:SetText(view.composeHint or "")
    Ink(frame.composeHint, view.canCompose and "inkFaint" or "inkDim")
    frame.composeHint:SetShown(not view.canCompose or (composeBox:GetText() or "") == "")
end

-- ---------------------------------------------------------------------------
-- Tabs, title and selection
-- ---------------------------------------------------------------------------

function RefreshTabs()
    if not frame then return end
    local r, g, b = Accent()
    local unread = Ready() and S.TotalUnread() or 0
    for _, tab in ipairs(frame.tabs) do
        local active = tab.id == state.tab
        tab.underline:SetShown(active)
        tab.underline:SetColorTexture(r, g, b, 1)
        local label = tab.text
        if tab.id == "activity" and unread > 0 and DB().UnreadOnTitle ~= false then
            label = string.format("%s (%d)", label, unread)
        end
        tab.label:SetText(label)
        Ink(tab.label, active and "ink" or "inkDim")
    end
    local title = "Contacts"
    if unread > 0 and DB().UnreadOnTitle ~= false then title = string.format("Contacts (%d)", unread) end
    if frame.TitleText then frame.TitleText:SetText(title) end

    frame.addFriend:SetShown(state.tab == "friends")
    frame.addIgnore:SetShown(state.tab == "ignore")
    frame.filterDrop:SetShown(state.tab == "activity")
    if frame.SetFilterText then frame.SetFilterText(state.filter) end
end

function RefreshAll(stick)
    if not frame then return end
    RefreshTabs()
    RefreshSidebar()
    RefreshMain(stick)
end

local function MarkSelectionRead()
    local view = frame and frame.currentView
    if view and view.conv and (view.conv.unread or 0) > 0 then
        S.MarkRead(view.conv.key)
        return true
    end
    return false
end

function Select(id)
    state.selected[state.tab] = id
    CommanderContactsDB.LastSelected = CommanderContactsDB.LastSelected or {}
    CommanderContactsDB.LastSelected[state.tab] = id
    if composeBox then composeBox:SetText("") end
    RefreshMain()
    if MarkSelectionRead() then RefreshTabs() end
    RefreshSidebar()
end

local function SetTab(id)
    local known = false
    for _, tab in ipairs(TABS) do if tab.id == id then known = true end end
    if not known then return end
    state.tab = id
    CommanderContactsDB.LastTab = id
    if frame and frame.searchBox then
        frame.searchBox:SetText("")
        state.search = ""
    end
    RefreshAll()
    if MarkSelectionRead() then RefreshTabs() RefreshSidebar() end
end

-- ---------------------------------------------------------------------------
-- Style and position
-- ---------------------------------------------------------------------------

local PANE_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function SavePosition()
    if not frame then return end
    local point, _, _, x, y = frame:GetPoint()
    if not point then return end
    local scale = frame:GetScale() or 1
    CommanderContactsDB.FramePos = { point = point, x = x * scale, y = y * scale }
end

local function ApplyPosition()
    if not frame then return end
    local scale = frame:GetScale() or 1
    frame:ClearAllPoints()
    local pos = DB().FramePos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.point, (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

function ApplyStyle()
    if not frame then return end
    local dark = (DB().FrameStyle or "DARK") ~= "WINDOW"
    Commander.UI.SetTemplateDressing(frame, true)
    if Commander.UI.ApplyStyleBackdrop then
        Commander.UI.ApplyStyleBackdrop(frame, dark and "DARK" or "WINDOW")
    end
    for _, pane in ipairs(frame.panes or {}) do
        if pane.SetBackdropColor then
            pane:SetBackdropColor(SKIN.pane[1], SKIN.pane[2], SKIN.pane[3], SKIN.pane[4])
            pane:SetBackdropBorderColor(SKIN.paneEdge[1], SKIN.paneEdge[2], SKIN.paneEdge[3], SKIN.paneEdge[4])
        end
    end
    frame:SetScale(tonumber(DB().FrameScale) or 1)
    Ink(frame.searchHint, "inkFaint")
    Ink(frame.composeHint, "inkFaint")
    frame.searchBox:SetTextColor(SKIN.ink[1], SKIN.ink[2], SKIN.ink[3])
    composeBox:SetTextColor(SKIN.ink[1], SKIN.ink[2], SKIN.ink[3])
    notesBox:SetTextColor(SKIN.ink[1], SKIN.ink[2], SKIN.ink[3])
    for _, rule in ipairs(frame.rules or {}) do
        rule:SetColorTexture(SKIN.rule[1], SKIN.rule[2], SKIN.rule[3], SKIN.rule[4])
    end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function MakePane(parent)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if pane.SetBackdrop then pane:SetBackdrop(PANE_BACKDROP) end
    frame.panes[#frame.panes + 1] = pane
    return pane
end

local function WheelScroll(scroll, step)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * (step or 30)
        local limit = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > limit then target = limit end
        self:SetVerticalScroll(target)
    end)
end

local function SendFromCompose()
    local view = frame.currentView
    local text = Trim(composeBox:GetText())
    if not (view and view.canCompose and view.send) or text == "" then return end
    local ok, err = view.send(text)
    if ok then
        composeBox:SetText("")
        frame.composeHint:Show()
    else
        Say(err or "could not send that.")
    end
end

function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "CommanderContactsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame.panes, frame.rules, frame.tabs = {}, {}, {}
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Contacts") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderContactsFrame") end

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() frame:StartMoving() end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
    end)

    -- ----- toolbar: tabs on the left, search on the right --------------
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
    toolbar:SetHeight(TOOLBAR_H)

    local previous
    for _, spec in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, toolbar)
        tab:SetSize(96, TOOLBAR_H)
        tab.id = spec.id
        tab.text = spec.label
        tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        tab.label:SetPoint("CENTER", tab, "CENTER", 0, 1)
        tab.underline = Quad(tab, "ARTWORK")
        tab.underline:SetHeight(2)
        tab.underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 6, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
        tab.hover = Quad(tab, "BACKGROUND")
        tab.hover:SetAllPoints()
        tab.hover:Hide()
        tab:SetScript("OnEnter", function(self)
            local r, g, b = Accent()
            self.hover:SetColorTexture(r, g, b, SKIN.hover)
            self.hover:Show()
        end)
        tab:SetScript("OnLeave", function(self) self.hover:Hide() end)
        tab:SetScript("OnClick", function(self) SetTab(self.id) end)
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            tab:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
        end
        previous = tab
        frame.tabs[#frame.tabs + 1] = tab
    end

    local searchBox = CreateFrame("EditBox", "CommanderContactsSearchBox", toolbar, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("RIGHT", toolbar, "RIGHT", -4, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(80)
    frame.searchBox = searchBox
    local searchHint = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchHint:SetText("Search")
    frame.searchHint = searchHint
    searchBox:SetScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        searchHint:SetShown(state.search == "" and not self:HasFocus())
        RefreshSidebar()
    end)
    searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        searchHint:SetShown((self:GetText() or "") == "")
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local toolbarRule = Rule(frame)
    toolbarRule:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -2)
    toolbarRule:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -2)
    frame.rules[#frame.rules + 1] = toolbarRule

    -- ----- sidebar -------------------------------------------------------
    local sidePane = MakePane(frame)
    sidePane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -64)
    sidePane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
    sidePane:SetWidth(SIDEBAR_W)
    frame.sidePane = sidePane

    local addFriend = CreateFrame("Button", nil, sidePane, "UIPanelButtonTemplate")
    addFriend:SetSize(SIDEBAR_W - 16, 21)
    addFriend:SetPoint("TOP", sidePane, "TOP", 0, -6)
    addFriend:SetText("Add Friend")
    addFriend:SetScript("OnClick", function() StaticPopup_Show("COMMANDER_CONTACTS_ADDFRIEND") end)
    frame.addFriend = addFriend

    local addIgnore = CreateFrame("Button", nil, sidePane, "UIPanelButtonTemplate")
    addIgnore:SetSize(SIDEBAR_W - 16, 21)
    addIgnore:SetPoint("TOP", sidePane, "TOP", 0, -6)
    addIgnore:SetText("Ignore Someone")
    addIgnore:SetScript("OnClick", function() StaticPopup_Show("COMMANDER_CONTACTS_ADDIGNORE") end)
    frame.addIgnore = addIgnore

    local filterDrop = CreateFrame("Frame", "CommanderContactsFilterDrop", sidePane, "UIDropDownMenuTemplate")
    filterDrop:SetPoint("TOP", sidePane, "TOP", 0, -2)
    UIDropDownMenu_SetWidth(filterDrop, SIDEBAR_W - 60)
    local function FilterText(value)
        for _, option in ipairs(FILTERS) do
            if option.value == value then return option.text end
        end
        return "Everyone"
    end
    UIDropDownMenu_Initialize(filterDrop, function()
        for _, option in ipairs(FILTERS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (option.value == state.filter)
            info.func = function(button)
                state.filter = button.value
                CommanderContactsDB.LastFilter = button.value
                UIDropDownMenu_SetSelectedValue(filterDrop, button.value)
                UIDropDownMenu_SetText(filterDrop, FilterText(button.value))
                RefreshSidebar()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    frame.filterDrop = filterDrop
    frame.SetFilterText = function(value)
        UIDropDownMenu_SetSelectedValue(filterDrop, value)
        UIDropDownMenu_SetText(filterDrop, FilterText(value))
    end

    local sideRule = Rule(sidePane)
    sideRule:SetPoint("TOPLEFT", sidePane, "TOPLEFT", 6, -SIDE_TOP_H - 2)
    sideRule:SetPoint("TOPRIGHT", sidePane, "TOPRIGHT", -6, -SIDE_TOP_H - 2)
    frame.rules[#frame.rules + 1] = sideRule

    sideScroll = CreateFrame("ScrollFrame", "CommanderContactsSideScroll", sidePane, "UIPanelScrollFrameTemplate")
    sideScroll:SetPoint("TOPLEFT", sidePane, "TOPLEFT", 4, -SIDE_TOP_H - 5)
    sideScroll:SetPoint("BOTTOMRIGHT", sidePane, "BOTTOMRIGHT", -14, 6)
    WheelScroll(sideScroll, 36)
    sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetSize(SIDEBAR_W - 28, 1)
    sideScroll:SetScrollChild(sideChild)
    sideScroll:SetScript("OnSizeChanged", function(_, width) sideChild:SetWidth(width) end)

    frame.sideEmpty = sidePane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.sideEmpty:SetPoint("CENTER", sidePane, "CENTER", 0, 10)
    frame.sideEmpty:SetWidth(SIDEBAR_W - 40)
    frame.sideEmpty:SetJustifyH("CENTER")
    frame.sideEmpty:Hide()

    -- ----- main pane -----------------------------------------------------
    local mainPane = MakePane(frame)
    mainPane:SetPoint("TOPLEFT", sidePane, "TOPRIGHT", 6, 0)
    mainPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    frame.mainPane = mainPane

    local card = CreateFrame("Frame", nil, mainPane)
    card:SetPoint("TOPLEFT", mainPane, "TOPLEFT", 0, 0)
    card:SetPoint("TOPRIGHT", mainPane, "TOPRIGHT", 0, 0)
    card:SetHeight(76)
    frame.headerCard = card

    card.title = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    card.title:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.title:SetJustifyH("LEFT")
    NoWrap(card.title)

    card.subtitle = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -3)
    card.subtitle:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.subtitle:SetJustifyH("LEFT")

    frame.notesLabel = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.notesLabel:SetText("Notes")
    frame.notesLabel:Hide()

    notesBox = CreateFrame("EditBox", "CommanderContactsNotesBox", card, "InputBoxTemplate")
    notesBox:SetHeight(20)
    notesBox:SetPoint("LEFT", frame.notesLabel, "RIGHT", 10, 0)
    notesBox:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    notesBox:SetAutoFocus(false)
    notesBox:SetMaxLetters(120)
    notesBox:Hide()
    local function SaveNotes(self)
        if not self.friendName then return end
        local text = Trim(self:GetText())
        local friend = FriendRecord(self.friendName)
        if friend and Trim(friend.notes) ~= text then
            H.SetFriendNotes(self.friendName, text)
        end
    end
    notesBox:SetScript("OnEnterPressed", function(self)
        SaveNotes(self)
        self:ClearFocus()
    end)
    notesBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    notesBox:SetScript("OnEditFocusLost", SaveNotes)

    local cardRule = Rule(mainPane)
    cardRule:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 8, 0)
    cardRule:SetPoint("TOPRIGHT", card, "BOTTOMRIGHT", -8, 0)
    frame.rules[#frame.rules + 1] = cardRule

    composeBox = CreateFrame("EditBox", "CommanderContactsComposeBox", mainPane, "InputBoxTemplate")
    composeBox:SetHeight(COMPOSE_H)
    composeBox:SetPoint("BOTTOMLEFT", mainPane, "BOTTOMLEFT", 16, 8)
    composeBox:SetPoint("BOTTOMRIGHT", mainPane, "BOTTOMRIGHT", -12, 8)
    composeBox:SetAutoFocus(false)
    composeBox:SetMaxLetters(255)
    composeBox:Hide()
    frame.composeHint = composeBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.composeHint:SetPoint("LEFT", composeBox, "LEFT", 2, 0)
    frame.composeHint:SetPoint("RIGHT", composeBox, "RIGHT", -2, 0)
    frame.composeHint:SetJustifyH("LEFT")
    NoWrap(frame.composeHint)
    composeBox:SetScript("OnEnterPressed", SendFromCompose)
    composeBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    composeBox:SetScript("OnTextChanged", function(self)
        local view = frame.currentView
        frame.composeHint:SetShown((not (view and view.canCompose)) or ((self:GetText() or "") == "" and not self:HasFocus()))
    end)
    composeBox:SetScript("OnEditFocusGained", function(self)
        local view = frame.currentView
        if view and view.canCompose then frame.composeHint:Hide() end
    end)
    composeBox:SetScript("OnEditFocusLost", function(self)
        frame.composeHint:SetShown((self:GetText() or "") == "")
    end)
    frame.composeBox = composeBox

    lineScroll = CreateFrame("ScrollFrame", "CommanderContactsLineScroll", mainPane, "UIPanelScrollFrameTemplate")
    lineScroll:SetPoint("TOPLEFT", cardRule, "BOTTOMLEFT", -4, -4)
    lineScroll:SetPoint("TOPRIGHT", cardRule, "BOTTOMRIGHT", -12, -4)
    lineScroll:SetPoint("BOTTOM", composeBox, "TOP", 0, 6)
    WheelScroll(lineScroll, 40)
    lineChild = CreateFrame("Frame", nil, lineScroll)
    lineChild:SetSize(FRAME_W - SIDEBAR_W - 60, 1)
    lineScroll:SetScrollChild(lineChild)
    lineScroll:SetScript("OnSizeChanged", function()
        local view = frame.currentView
        if view then RefreshTranscript(view.conv, false) end
    end)

    frame.lineEmpty = mainPane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.lineEmpty:SetPoint("CENTER", lineScroll, "CENTER", 0, 0)
    frame.lineEmpty:SetWidth(300)
    frame.lineEmpty:SetJustifyH("CENTER")
    frame.lineEmpty:Hide()

    frame.mainEmpty = mainPane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.mainEmpty:SetPoint("CENTER", mainPane, "CENTER", 0, 20)
    frame.mainEmpty:SetWidth(320)
    frame.mainEmpty:SetJustifyH("CENTER")

    frame:SetScript("OnHide", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:SetScript("OnShow", function()
        H.RequestFriends()
        RefreshAll()
    end)
    -- The scroll range of a freshly laid-out child is only right on the
    -- next frame, so a "stick to the bottom" is finished here.
    frame:SetScript("OnUpdate", function()
        if scrollBottomPending then
            scrollBottomPending = false
            ScrollToBottom()
        end
    end)

    for _, name in ipairs({ "CommanderContactsSideScroll", "CommanderContactsLineScroll" }) do
        Commander.UI.SlimScrollBar(name, 2, 2)
    end

    ApplyPosition()
    ApplyStyle()
    return frame
end

-- ---------------------------------------------------------------------------
-- Live updates
-- ---------------------------------------------------------------------------

local function OnMessage(key)
    if not (frame and frame:IsShown()) then return end
    local view = frame.currentView
    if view and view.conv and view.conv.key == key then
        S.MarkRead(key)
        RefreshTranscript(view.conv, false)
    elseif view and not view.conv then
        -- A friend with no thread yet just got one: pick it up.
        RefreshMain()
        MarkSelectionRead()
    end
    RefreshTabs()
    RefreshSidebar()
end

local function OnRoster()
    if frame and frame:IsShown() then RefreshAll(false) end
end

local function OnSettings()
    if Ready() and S.SetMaxMessages then S.SetMaxMessages(DB().MaxMessages) end
    if not frame then return end
    ApplyStyle()
    if frame:IsShown() then
        if not Enabled() then frame:Hide() else RefreshAll(false) end
    end
end

if Commander and Commander.AddListener and COMMANDER_CONTACTS_EVENTS then
    Commander.AddListener(COMMANDER_CONTACTS_EVENTS.MESSAGE, OnMessage)
    Commander.AddListener(COMMANDER_CONTACTS_EVENTS.ROSTER, OnRoster)
    Commander.AddListener(COMMANDER_CONTACTS_EVENTS.UPDATE, OnSettings)
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

local function RestoreView()
    local db = DB()
    local open = db.OpenTab or "LAST"
    if open == "FRIENDS" then state.tab = "friends"
    elseif open == "ACTIVITY" then state.tab = "activity"
    elseif db.LastTab then state.tab = db.LastTab end
    if type(db.LastSelected) == "table" then
        for tab, id in pairs(db.LastSelected) do state.selected[tab] = id end
    end
    state.filter = db.LastFilter or "all"
end

function H.Show()
    if not Enabled() then
        Say("Contacts is switched off. Turn it on with /ccontacts settings.")
        return
    end
    if not Ready() then return end
    local first = frame == nil
    EnsureFrame()
    if first then RestoreView() end
    if frame:IsShown() then return end
    ApplyStyle()
    ApplyPosition()
    frame:Show()
    if MarkSelectionRead() then RefreshTabs() RefreshSidebar() end
end

function H.Hide()
    if frame and frame:IsShown() then frame:Hide() end
end

function H.Toggle()
    if frame and frame:IsShown() then H.Hide() else H.Show() end
end

function H.ShowTab(tab)
    tab = tostring(tab or ""):lower()
    if not Ready() then return end
    local first = frame == nil
    EnsureFrame()
    if first then RestoreView() end
    if not frame:IsShown() then H.Show() end
    SetTab(tab)
end

function H.OpenConversation(key)
    if not (Ready() and S.Conversation(key)) then return false end
    local first = frame == nil
    EnsureFrame()
    if first then RestoreView() end
    if not frame:IsShown() then H.Show() end
    state.tab = "activity"
    CommanderContactsDB.LastTab = "activity"
    Select(key)
    RefreshTabs()
    return true
end

function H.PrintStats()
    if not Ready() then return end
    local stats = S.Stats()
    Say(string.format("%d %s, %d Battle.net %s, %d %s, %d %s kept, %d unread.",
        stats.people, stats.people == 1 and "person" or "people",
        stats.bn, stats.bn == 1 and "account" or "accounts",
        stats.groups, stats.groups == 1 and "group" or "groups",
        stats.lines, stats.lines == 1 and "line" or "lines",
        stats.unread))
end

-- For the harness: the window's state without reaching into locals.
function H.State()
    return state, frame
end

CommanderContacts_Toggle = H.Toggle
CommanderContacts_Show = H.Show
CommanderContacts_Hide = H.Hide
CommanderContacts_ShowTab = H.ShowTab
CommanderContacts_OpenConversation = H.OpenConversation
CommanderContacts_PrintStats = H.PrintStats
CommanderContacts_ForgetSuggestions = function()
    H.ForgetSuggestions()
    if frame and frame:IsShown() then RefreshAll(false) end
end

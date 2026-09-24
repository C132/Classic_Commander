-- Commander Contacts store smoke (luajit).
--
-- No mock at all. CommanderContactsStore is pure Lua, so this loads that one
-- file and drives hand-built SavedVariables tables through the real calls.
-- A failure here is always a real logic bug, never a mock artefact. The
-- clock is frozen and advanced by hand, because every "did this restamp
-- updated" assertion would otherwise race a one-second tick.
--
--   /opt/homebrew/bin/luajit contacts_store_smoke.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ROOT = HERE:match("^(.*)/Harness$") or HERE

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end

local now = 1786000000  -- a real epoch, so date() and the prune cutoff behave
function time() return now end
-- The client has a global date(); plain luajit does not.
function date(fmt, t) return os.date(fmt or "%c", t or now) end
local function TICK(seconds) now = now + (seconds or 1) end

assert(loadfile(ROOT .. "/CommanderContactsStore.lua"))()
local S = CommanderContactsStore

-- ===========================================================================
-- A. Helpers that need no store
-- ===========================================================================

EQ(S.Shorten("Bob-TestRealm", "TestRealm"), "Bob", "A1 own realm is stripped")
EQ(S.Shorten("Bob-Test Realm", "TestRealm"), "Bob", "A1 realm compared without spaces")
EQ(S.Shorten("Bob-Other", "TestRealm"), "Bob-Other", "A1 another realm is kept")
EQ(S.Shorten("Bob", "TestRealm"), "Bob", "A1 a bare name passes through")
EQ(S.Shorten("  Bob  ", nil), "Bob", "A1 trimmed")

EQ(S.PlainText("look |cff0070dd|Hitem:2589::::::::70:::::|h[Thunderfury]|h|r ok"),
    "look [Thunderfury] ok", "A2 links reduce to their label, colours stripped")
EQ(S.PlainText("|TInterface\\Icons\\x:16|t hi"), " hi", "A2 texture escapes removed")
EQ(S.Preview("a  b\n c", 60), "a b c", "A3 preview collapses whitespace")
EQ(#S.Preview(string.rep("x", 100), 20), 20 + 2, "A3 preview truncates with an ellipsis")
EQ(S.DMKey(" Bob "), "dm:Bob", "A4 dm key")
EQ(S.BNKey(42), "bn:42", "A4 bn key")

-- ===========================================================================
-- B. Attach against a fresh table and a damaged one
-- ===========================================================================

do
    local db = {}
    S.Attach(db)
    CHECK(S.Attached(), "B1 attached")
    CHECK(type(db.Conversations) == "table", "B1 fresh table gets a conversations map")
    EQ(db.NextID, 1, "B1 NextID starts at 1")
    EQ(S.Count(), 0, "B1 nothing kept")
end

do
    local db = {
        NextID = 2,
        ActiveGroup = "group:7",
        Conversations = {
            ["dm:Bob"] = { messages = { { t = 5, from = "Bob", text = "hi" }, "junk", { t = "x" } } },
            ["group:7"] = { kind = "group", name = "", members = { "A", "A", " ", "B" }, ended = 9,
                messages = {}, unread = -3 },
            ["group:9"] = { messages = {} },
            ["bn:5"] = "not a table",
            [12] = { messages = {} },
        },
    }
    S.Attach(db)
    local bob = db.Conversations["dm:Bob"]
    EQ(bob.kind, "dm", "B2 kind inferred from the key")
    EQ(bob.name, "Bob", "B2 name inferred from the key")
    EQ(#bob.messages, 1, "B2 junk lines dropped, real ones kept")
    EQ(bob.unread, 0, "B2 unread filled in")
    EQ(bob.lastRead, 0, "B2 lastRead filled in")
    local g7 = db.Conversations["group:7"]
    EQ(#g7.members, 2, "B3 members deduped and blanks dropped")
    EQ(g7.unread, 0, "B3 negative unread clamped")
    EQ(g7.name, "Party", "B3 empty group name defaulted")
    EQ(g7.groupType, "PARTY", "B3 group type defaulted")
    EQ(db.Conversations["group:9"].kind, "group", "B4 kind from key for a bare group")
    CHECK(db.Conversations["group:9"].members ~= nil, "B4 group gets a members array")
    EQ(db.Conversations["bn:5"], nil, "B5 a non-table entry is dropped")
    EQ(db.Conversations[12], nil, "B5 a non-string key is dropped")
    EQ(db.NextID, 10, "B6 NextID moved past the highest group id in use")
    EQ(db.ActiveGroup, nil, "B7 an ended group cannot stay active")
end

-- ===========================================================================
-- C. Threads with people
-- ===========================================================================

local db = {}
S.Attach(db)

local bob = S.EnsureDM("Bob", { target = "Bob-TestRealm", guid = "G1", class = "MAGE" })
CHECK(bob ~= nil and bob.key == "dm:Bob", "C1 EnsureDM creates a thread")
EQ(bob.kind, "dm", "C1 kind dm")
EQ(bob.target, "Bob-TestRealm", "C1 target kept for whispering back")
EQ(bob.class, "MAGE", "C1 class kept")
local again = S.EnsureDM("Bob", { class = "" })
CHECK(again == bob, "C2 EnsureDM is idempotent")
EQ(bob.class, "MAGE", "C2 an empty class does not overwrite a known one")
S.EnsureDM("Bob", { class = "PRIEST" })
EQ(bob.class, "PRIEST", "C2 a newer class does")
EQ(S.EnsureDM("  "), nil, "C3 a blank name makes nothing")

local acct = S.EnsureBN(77, "Jordan")
EQ(acct.key, "bn:77", "C4 EnsureBN creates a thread keyed by account")
EQ(acct.kind, "bn", "C4 kind bn")
EQ(acct.target, 77, "C4 target is the account id")
S.EnsureBN(77, "Jordan Renamed")
EQ(acct.name, "Jordan Renamed", "C4 the account name follows the latest event")
EQ(S.EnsureBN("nope"), nil, "C4 a non-numeric id makes nothing")

-- ===========================================================================
-- D. Group sessions
-- ===========================================================================

EQ(S.ActiveGroup(), nil, "D1 no active group to begin with")
local party = S.StartGroup("PARTY", { "Alice", "Carl", "Alice" })
CHECK(party ~= nil and party.key == "group:1", "D2 StartGroup makes group:1")
EQ(S.ActiveGroup(), party, "D2 it is the active group")
EQ(#party.members, 2, "D2 members deduped at start")
CHECK(party.name:match("^Party · %d+ %a+$") ~= nil, "D2 default name is Party · day month", party.name)
EQ(S.AddMembers(party.key, { "Carl", "Dina" }), 1, "D3 AddMembers reports only new names")
EQ(#party.members, 3, "D3 member count")
CHECK(S.IsMember(party.key, "Dina"), "D3 IsMember")
EQ(S.MemberSummary(party, 2), "Alice, Carl and 1 other", "D4 member summary")
EQ(S.MemberSummary(party, 3), "Alice, Carl, Dina", "D4 member summary with room")
CHECK(S.SetGroupType(party.key, "RAID"), "D5 party becomes a raid")
CHECK(party.name:match("^Raid · ") ~= nil, "D5 the default name follows the type", party.name)
CHECK(S.Rename(party.key, "Kara Tuesday"), "D6 rename")
CHECK(not S.Rename(party.key, "Kara Tuesday"), "D6 renaming to the same name is a no-op")
CHECK(not S.Rename(party.key, "   "), "D6 blank rename refused")
S.SetGroupType(party.key, "PARTY")
EQ(party.name, "Kara Tuesday", "D6 a user name survives a type change")
CHECK(S.CloseGroup(party.key), "D7 close")
CHECK(party.ended ~= nil, "D7 ended stamped")
EQ(S.ActiveGroup(), nil, "D7 nothing active after close")
CHECK(not S.CloseGroup("dm:Bob"), "D7 a person cannot be closed")
local second = S.StartGroup("INSTANCE", {})
EQ(second.key, "group:2", "D8 the next group gets the next id")
CHECK(second.name:match("^Battleground") ~= nil, "D8 instance groups are battlegrounds", second.name)
EQ(S.GroupLabel("RAID"), "Raid", "D8 labels")

-- ===========================================================================
-- E. Lines
-- ===========================================================================

TICK(10)
local line = S.Append(bob.key, { from = "Bob", text = "hello there", ch = "WHISPER", cls = "PRIEST" })
CHECK(line ~= nil, "E1 append returns the entry")
EQ(line.t, now, "E1 stamped now")
EQ(bob.unread, 1, "E1 an incoming line is unread")
EQ(bob.updated, now, "E1 updated restamped")
TICK(5)
S.Append(bob.key, { from = "Me", text = "hi bob", out = true })
EQ(bob.unread, 1, "E2 an outgoing line is not unread")
EQ(S.PreviewFor(bob), "You: hi bob", "E2 preview names you for your own line")
EQ(S.Append(bob.key, { from = "Bob", text = "" }), nil, "E3 an empty line is refused")
EQ(S.Append("dm:Nobody", { from = "x", text = "y" }), nil, "E3 an unknown thread is refused")
EQ(#S.Messages(bob.key), 2, "E3 two lines kept")
EQ(S.LastMessage(bob.key).text, "hi bob", "E3 last message")
S.Append(second.key, { from = "Zed", text = "inc left" })
EQ(S.PreviewFor(second), "Zed: inc left", "E4 group preview names the speaker")
EQ(S.PreviewFor(party), "Alice, Carl, Dina", "E4 an empty group previews its members")
EQ(S.PreviewFor(acct), "No messages yet", "E4 an empty person previews as such")

-- trimming
S.SetMaxMessages(25)
EQ(S.MaxMessages(), 25, "E5 max applied")
for index = 1, 40 do S.Append(bob.key, { from = "Bob", text = "line " .. index }) end
EQ(#bob.messages, 25, "E5 a thread keeps only the newest max lines")
EQ(bob.messages[1].text, "line 16", "E5 the oldest went first")
EQ(bob.messages[25].text, "line 40", "E5 the newest is last")
S.SetMaxMessages(5)
EQ(S.MaxMessages(), 20, "E5 max floors at 20")
S.SetMaxMessages(400)

-- ===========================================================================
-- F. Read state
-- ===========================================================================

EQ(S.Unread(bob.key), 41, "F1 unread counted")
EQ(S.TotalUnread(), 42, "F1 total unread across threads")
EQ(S.TotalUnread("dm"), 41, "F1 total by kind")
CHECK(S.MarkRead(bob.key), "F2 mark read reports a change")
EQ(bob.unread, 0, "F2 cleared")
EQ(bob.lastRead, now, "F2 lastRead stamped")
CHECK(not S.MarkRead(bob.key), "F2 marking read twice reports no change")
local stats = S.Stats()
EQ(stats.people, 1, "F3 stats people")
EQ(stats.bn, 1, "F3 stats accounts")
EQ(stats.groups, 2, "F3 stats groups")
EQ(stats.lines, 26, "F3 stats lines")
EQ(stats.unread, 1, "F3 stats unread")

-- ===========================================================================
-- G. Listing
-- ===========================================================================

local carol = S.EnsureDM("Carol")
TICK(1)
S.Append(carol.key, { from = "Carol", text = "want |Hitem:1:::|h[Thunderfury]|h?" })

local all = S.List({})
EQ(#all, 5, "G1 everything listed")
EQ(all[1].key, carol.key, "G1 most recent first")
local people = S.List({ kind = "people" })
EQ(#people, 3, "G2 people = dm + bn")
local groups = S.List({ kind = "group" })
EQ(#groups, 2, "G2 groups")
EQ(groups[1].key, second.key, "G2 most recent group first")
local friends = S.List({ kind = "people", filter = "friends", friends = { Bob = true } })
EQ(#friends, 2, "G3 friends filter keeps Bob and the Battle.net account")
local others = S.List({ kind = "people", filter = "others", friends = { Bob = true } })
EQ(#others, 1, "G3 others filter keeps Carol only")
EQ(others[1].key, carol.key, "G3 others is Carol")
local hit = S.List({ search = "thunderfury" })
EQ(#hit, 1, "G4 search matches inside a link label")
EQ(hit[1].key, carol.key, "G4 search hit")
local byMember = S.List({ search = "dina" })
EQ(#byMember, 1, "G4 search matches a group member")
EQ(byMember[1].key, party.key, "G4 member hit")
local byName = S.List({ search = "KARA" })
EQ(#byName, 1, "G4 search is case-insensitive on names")
local named = S.List({ sort = "name" })
EQ(named[1].name, "Battleground" == named[1].name:sub(1, 12) and named[1].name or named[1].name, "G5 name sort runs")
CHECK(named[1].name:lower() <= named[2].name:lower(), "G5 name sort ascending")
S.SetPinned(party.key, true)
local pinned = S.List({ sort = "name" })
EQ(pinned[1].key, party.key, "G6 pinned first whatever the sort")
S.SetPinned(party.key, false)
local unread = S.List({ sort = "unread" })
CHECK((unread[1].unread or 0) >= 1, "G7 unread sort puts an unread thread first")
EQ(unread[#unread].unread, 0, "G7 a read thread lands last")

-- stability: many threads in one second, listed twice, same order
for index = 1, 8 do S.EnsureDM("Same" .. index) end
local first = S.List({ kind = "dm" })
local secondPass = S.List({ kind = "dm" })
local stable = true
for index = 1, #first do
    if first[index].key ~= secondPass[index].key then stable = false end
end
CHECK(stable, "G8 an unchanged list lists in the same order twice")

-- ===========================================================================
-- H. Clearing, deleting, pruning
-- ===========================================================================

CHECK(S.Clear(carol.key), "H1 clear reports a change")
EQ(#carol.messages, 0, "H1 cleared")
EQ(carol.unread, 0, "H1 unread cleared with it")
CHECK(not S.Clear(carol.key), "H1 clearing an empty thread is a no-op")
CHECK(S.Delete(carol.key), "H2 delete")
EQ(S.Conversation(carol.key), nil, "H2 gone")
CHECK(not S.Delete(carol.key), "H2 deleting twice is a no-op")

-- The active group survives a prune; empty old threads do not
local live = S.ActiveGroup()
EQ(live, second, "H3 the battleground is still live")
TICK(100 * 86400)
S.Append(bob.key, { from = "Bob", text = "fresh" })
S.SetPinned("dm:Same1", true)
local lines, threads = S.Prune(90)
CHECK(lines >= 26, "H4 old lines dropped", lines)
EQ(#bob.messages, 1, "H4 Bob keeps only the fresh line")
CHECK(S.Conversation(second.key) ~= nil, "H4 the live group is kept even though empty")
CHECK(S.Conversation("dm:Same1") ~= nil, "H4 a pinned empty thread is kept")
EQ(S.Conversation("dm:Same2"), nil, "H4 an old empty unpinned thread is dropped")
CHECK(threads >= 7, "H4 threads dropped", threads)
local keepAll = { Conversations = { ["dm:Old"] = { messages = { { t = 1, from = "Old", text = "x" } } } } }
S.Attach(keepAll)
local l2, t2 = S.Prune(0)
EQ(l2, 0, "H5 zero days keeps every line")
EQ(t2, 0, "H5 zero days keeps every thread")

if fails > 0 then
    io.write(string.format("contacts store smoke: %d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("contacts store smoke: %d checks passed\n", checks))

-- Commander Notebook store harness (luajit).
--
-- The store is pure Lua, so there is no mock here at all: only the real
-- CommanderNotebookStore.lua, loaded with loadfile and driven against
-- hand-built SavedVariables tables. A failure below is always a real logic
-- bug, never a mock artefact.
--
-- It covers the normalising Attach contract (including tables damaged the way
-- a hand edit or an older build damages them), the notebook and tag models,
-- every mutator's no-op guard, the two-stage trash, the search grammar, and
-- the ordering rules the note list depends on.
--
--   /opt/homebrew/bin/luajit notebook_harness.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

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

assert(loadfile(ADDONS .. "/Commander_Notebook/CommanderNotebookStore.lua"))()
local S = CommanderNotebookStore

-- A frozen, advanceable clock. Real time() would make every "updated changed"
-- assertion below a race against a one-second tick.
local CLOCK = 1000000
S.Now = function() return CLOCK end
local function TICK(seconds) CLOCK = CLOCK + (seconds or 1) end

local function Fresh()
    CLOCK = 1000000
    local db = {}
    S.Attach(db)
    return db
end

local function IDs(list)
    local out = {}
    for index, note in ipairs(list) do out[index] = note.id end
    return table.concat(out, ",")
end

-- ===========================================================================
-- A. Attach: the normalising contract
-- ===========================================================================

do
    local db = Fresh()
    CHECK(type(db.Notes) == "table", "A1 Notes table created")
    CHECK(type(db.Notebooks) == "table", "A1 Notebooks table created")
    EQ(db.NextID, 1, "A1 NextID seeded")
    local default = db.Notebooks[S.DefaultNotebookID()]
    CHECK(default ~= nil, "A2 default notebook exists")
    EQ(default.name, "Field Notes", "A2 default notebook named")
    CHECK(default.builtin == true, "A2 default notebook flagged builtin")
end

do
    -- The damaged table: a non-table note, a note with no fields at all, a
    -- note pointing at a notebook that no longer exists, junk in Notebooks,
    -- and a NextID that has fallen behind the ids actually in use.
    local db = {
        NextID = 2,
        Notebooks = { ["nb7"] = { name = "  Raids  " }, ["nbjunk"] = "not a table" },
        Notes = {
            ["nbroken"] = "not a table",
            ["n5"] = {},
            ["n9"] = { title = "Kept", notebook = "nb-gone", tags = { "Raid", "raid", "", "keys" } },
        },
    }
    S.Attach(db)
    CHECK(db.Notes["nbroken"] == nil, "A3 non-table note dropped")
    CHECK(db.Notebooks["nbjunk"] == nil, "A3 non-table notebook dropped")
    EQ(db.Notebooks["nb7"].name, "Raids", "A3 notebook name trimmed")
    EQ(db.Notebooks["nb7"].id, "nb7", "A3 notebook id backfilled from key")
    EQ(db.Notes["n5"].title, "", "A4 missing title defaulted")
    EQ(db.Notes["n5"].body, "", "A4 missing body defaulted")
    EQ(db.Notes["n5"].notebook, S.DefaultNotebookID(), "A4 missing notebook defaulted")
    EQ(db.Notes["n5"].created, db.Notes["n5"].updated, "A4 updated seeded from created")
    EQ(db.Notes["n9"].notebook, S.DefaultNotebookID(), "A5 dangling notebook re-homed, note kept")
    EQ(table.concat(db.Notes["n9"].tags, ","), "raid,keys", "A5 tags lowercased, deduped, blanks dropped")
    EQ(db.NextID, 10, "A6 NextID lifted above every id in use")

    -- The point of A6: the next created note must not collide with n9.
    local made = S.CreateNote({ title = "After" })
    EQ(made.id, "n10", "A6 next id does not collide")
    CHECK(db.Notes["n9"].title == "Kept", "A6 existing note not overwritten")
end

do
    -- Attach must be idempotent: a second login on an already-good table
    -- changes nothing.
    local db = Fresh()
    local note = S.CreateNote({ title = "Stable", body = "x" })
    local before = { note.id, note.created, note.updated, db.NextID }
    S.Attach(db)
    EQ(db.Notes[before[1]].created, before[2], "A7 attach is idempotent (created)")
    EQ(db.Notes[before[1]].updated, before[3], "A7 attach is idempotent (updated)")
    EQ(db.NextID, before[4], "A7 attach is idempotent (NextID)")
end

-- ===========================================================================
-- B. Text: plain text, snippets, titles, word count
-- ===========================================================================

do
    Fresh()
    local link = "|cffa335ee|Hitem:19019::::::::70::::::::::|h[Thunderfury]|h|r"
    EQ(S.PlainText(link), "Thunderfury", "B1 hyperlink reduces to its label")
    EQ(S.PlainText("|cff00ff00green|r"), "green", "B1 colour codes stripped")
    EQ(S.PlainText("a|TInterface\\Icons\\X:16|tb"), "a b", "B1 inline texture stripped")
    EQ(S.PlainText("100|| damage"), "100| damage", "B1 escaped pipe survives as one pipe")

    local note = S.CreateNote({ body = "  first line\nsecond line  " })
    EQ(S.Snippet(note), "first line second line", "B2 snippet is one collapsed line")
    EQ(S.TitleFor(note), "first line", "B3 untitled note titled from its first line")

    S.SetTitle(note.id, "Real Title")
    EQ(S.TitleFor(note), "Real Title", "B3 explicit title wins")

    local empty = S.CreateNote({})
    EQ(S.TitleFor(empty), "Untitled note", "B3 wholly empty note has a fallback title")
    EQ(S.Snippet(empty), "", "B2 empty body snippets to empty string")

    local long = S.CreateNote({ body = string.rep("word ", 60) })
    CHECK(#S.Snippet(long, 40) <= 43, "B2 snippet respects its limit", #S.Snippet(long, 40))
    CHECK(S.Snippet(long, 40):sub(-3) == "...", "B2 truncated snippet is elided")

    local counted = S.CreateNote({ body = "one two three " .. link })
    EQ(S.WordCount(counted), 4, "B4 word count counts the link's label, not its payload")
end

-- ===========================================================================
-- C. Notebooks
-- ===========================================================================

do
    local db = Fresh()
    local id = S.CreateNotebook("Raids")
    CHECK(id ~= nil, "C1 notebook created")
    local dup, err = S.CreateNotebook(" raids ")
    CHECK(dup == nil and err ~= nil, "C1 duplicate name refused, case and space insensitive")
    CHECK(S.CreateNotebook("   ") == nil, "C1 blank name refused")

    EQ(S.NotebookByName("RAIDS"), id, "C2 lookup by name is case insensitive")
    EQ(S.NotebookName("nb-nope"), "Unfiled", "C2 unknown notebook names as Unfiled")

    CHECK(S.RenameNotebook(id, "Raid Prep"), "C3 rename")
    CHECK(not S.RenameNotebook(id, "Field Notes"), "C3 rename onto another notebook refused")
    CHECK(S.RenameNotebook(id, "Raid Prep"), "C3 rename to its own current name allowed")

    -- Deleting moves notes; it never deletes them.
    local a = S.CreateNote({ title = "one", notebook = id })
    local b = S.CreateNote({ title = "two", notebook = id })
    local target = S.CreateNotebook("Archive")
    local ok, moved = S.DeleteNotebook(id, target)
    CHECK(ok, "C4 notebook deleted")
    EQ(moved, 2, "C4 both notes moved")
    EQ(db.Notes[a.id].notebook, target, "C4 note followed the move target")
    EQ(db.Notes[b.id].notebook, target, "C4 second note followed too")
    CHECK(db.Notes[a.id] ~= nil, "C4 deleting a notebook does not delete writing")

    -- Without a valid target they land in the default rather than nowhere.
    local orphanBook = S.CreateNotebook("Temp")
    local orphan = S.CreateNote({ title = "orphan", notebook = orphanBook })
    S.DeleteNotebook(orphanBook, "nb-does-not-exist")
    EQ(db.Notes[orphan.id].notebook, S.DefaultNotebookID(), "C5 no target falls back to the default")

    CHECK(not S.DeleteNotebook(S.DefaultNotebookID()), "C6 the default notebook cannot be deleted")
    CHECK(not S.DeleteNotebook("nb-nope"), "C6 deleting an unknown notebook refused")
end

do
    local db = Fresh()
    local zed = S.CreateNotebook("Zones")
    local alpha = S.CreateNotebook("Alchemy")
    S.CreateNote({ notebook = alpha })
    S.CreateNote({ notebook = alpha })
    local trashed = S.CreateNote({ notebook = zed })
    S.Trash(trashed.id)

    local list = S.Notebooks()
    EQ(list[1].id, S.DefaultNotebookID(), "C7 default notebook leads the sidebar")
    EQ(list[2].name, "Alchemy", "C7 the rest sort alphabetically")
    EQ(list[3].name, "Zones", "C7 alphabetical, continued")
    EQ(list[2].count, 2, "C8 notebook counts are live")
    EQ(list[3].count, 0, "C8 a trashed note is not counted under its notebook")
    local _ = db
end

-- ===========================================================================
-- D. Tags
-- ===========================================================================

do
    Fresh()
    local parsed = S.ParseTags(" Raid , keys ,, RAID , pvp ")
    EQ(table.concat(parsed, ","), "raid,keys,pvp", "D1 tag line parses, trims, lowercases, dedupes")

    local note = S.CreateNote({ title = "n", tags = { "raid", "keys" } })
    EQ(S.TagString(note), "raid, keys", "D1 tag line round-trips for the editor")

    CHECK(not S.SetTags(note.id, "raid, keys"), "D2 setting the same tags is a no-op")
    CHECK(S.SetTags(note.id, "raid, keys, new"), "D2 a real change reports true")

    CHECK(S.AddTag(note.id, "Fresh"), "D3 add tag")
    CHECK(not S.AddTag(note.id, "fresh"), "D3 adding an existing tag is a no-op")
    CHECK(S.HasTag(note, "fresh"), "D3 tag stored lowercased")
    CHECK(S.RemoveTag(note.id, "fresh"), "D3 remove tag")
    CHECK(not S.RemoveTag(note.id, "fresh"), "D3 removing an absent tag is a no-op")

    S.CreateNote({ tags = { "raid" } })
    S.CreateNote({ tags = { "raid", "keys" } })
    local tags = S.Tags()
    EQ(tags[1].name, "raid", "D4 tag list sorts by count")
    EQ(tags[1].count, 3, "D4 counts across notes")

    EQ(S.RenameTag("raid", "raiding"), 3, "D5 rename touches every note carrying the tag")
    EQ(S.Tags()[1].name, "raiding", "D5 renamed tag is what shows")
    EQ(S.RenameTag("raiding", "keys"), 3, "D6 renaming onto an existing tag merges")
    for _, entry in ipairs(S.Tags()) do
        CHECK(entry.name ~= "raiding", "D6 the old tag name is gone")
    end
end

do
    -- A merge must not leave a duplicate behind on a note that held both.
    Fresh()
    local note = S.CreateNote({ tags = { "alpha", "beta" } })
    S.RenameTag("alpha", "beta")
    EQ(table.concat(note.tags, ","), "beta", "D7 merging two tags on one note leaves one")
end

-- ===========================================================================
-- E. Mutators and their no-op guards
-- ===========================================================================

do
    Fresh()
    local note = S.CreateNote({ title = "Title", body = "Body" })
    local created = note.updated

    TICK(60)
    CHECK(not S.SetTitle(note.id, "Title"), "E1 rewriting the same title is a no-op")
    EQ(note.updated, created, "E1 a no-op does not touch updated")
    CHECK(not S.SetBody(note.id, "Body"), "E1 rewriting the same body is a no-op")
    EQ(note.updated, created, "E1 no-op body leaves updated alone")

    -- This is the whole reason the guard exists: loading a note into the
    -- editor fires OnTextChanged with the note's own text, and without the
    -- guard merely *reading* a note would reorder a recently-updated list.
    CHECK(S.SetBody(note.id, "Body changed"), "E2 a real edit reports true")
    EQ(note.updated, created + 60, "E2 a real edit stamps updated")

    CHECK(S.SetTitle(note.id, "  Padded  "), "E3 title trims")
    EQ(note.title, "Padded", "E3 title stored trimmed")

    TICK(10)
    local before = note.updated
    CHECK(S.AppendBody(note.id, "appended"), "E4 append")
    CHECK(note.body:match("\nappended$") ~= nil, "E4 append starts a new line")
    CHECK(not S.AppendBody(note.id, ""), "E4 appending nothing is a no-op")
    EQ(note.updated, before + 10, "E4 append stamps updated")

    local book = S.CreateNotebook("Other")
    CHECK(S.SetNotebook(note.id, book), "E5 move to notebook")
    CHECK(not S.SetNotebook(note.id, book), "E5 moving where it already is is a no-op")
    CHECK(not S.SetNotebook(note.id, "nb-nope"), "E5 moving to an unknown notebook refused")
    EQ(note.notebook, book, "E5 note stayed where it legitimately moved")

    CHECK(not S.SetTitle("n-nope", "x"), "E6 mutating an unknown note is refused, not an error")
    CHECK(not S.SetBody("n-nope", "x"), "E6 body on unknown note refused")
    CHECK(not S.TogglePin("n-nope"), "E6 pin on unknown note refused")
end

do
    Fresh()
    local note = S.CreateNote({ title = "Pin me" })
    local stamp = note.updated
    TICK(120)
    CHECK(S.TogglePin(note.id), "E7 pin on")
    EQ(note.updated, stamp, "E7 pinning is a shelf, not an edit: updated untouched")
    CHECK(not S.TogglePin(note.id), "E7 pin off")
    EQ(note.pinned, nil, "E7 unpinned stores nil, not false")
end

do
    Fresh()
    local book = S.CreateNotebook("Src")
    local note = S.CreateNote({
        title = "Original", body = "text", notebook = book,
        tags = { "a", "b" }, context = { zone = "Nagrand", x = 0.5 },
    })
    local copy = S.Duplicate(note.id)
    CHECK(copy ~= nil and copy.id ~= note.id, "E8 duplicate is a new note")
    EQ(copy.title, "Original (copy)", "E8 duplicate is marked")
    EQ(copy.notebook, book, "E8 duplicate stays in its notebook")
    EQ(table.concat(copy.tags, ","), "a,b", "E8 duplicate carries the tags")
    CHECK(copy.tags ~= note.tags, "E8 tags are copied, not aliased")
    CHECK(copy.context ~= note.context, "E8 context is copied, not aliased")
    EQ(copy.context.zone, "Nagrand", "E8 context values carried")
    copy.tags[1] = "changed"
    EQ(note.tags[1], "a", "E8 writing the copy cannot reach the original")
    CHECK(S.Duplicate("n-nope") == nil, "E8 duplicating an unknown note returns nil")
end

-- ===========================================================================
-- F. The trash
-- ===========================================================================

do
    local db = Fresh()
    local note = S.CreateNote({ title = "Doomed", tags = { "raid" } })
    S.TogglePin(note.id)

    CHECK(S.Trash(note.id), "F1 trash")
    CHECK(note.trashed ~= nil, "F1 trashed carries a timestamp")
    EQ(note.pinned, nil, "F1 trashing unpins")
    CHECK(db.Notes[note.id] ~= nil, "F1 trash does not remove the note")
    CHECK(not S.Trash(note.id), "F1 trashing twice is a no-op")

    -- The invariant: the trash is a place, not a filter.
    EQ(#S.List({ scope = "all" }), 0, "F2 a trashed note leaves the all-notes view")
    EQ(#S.List({ scope = "tag", key = "raid" }), 0, "F2 and leaves its tag view")
    EQ(#S.List({ scope = "notebook", key = S.DefaultNotebookID() }), 0, "F2 and its notebook view")
    EQ(#S.List({ scope = "trash" }), 1, "F2 and appears only in the trash")
    EQ(S.TrashCount(), 1, "F2 trash count")

    CHECK(S.Restore(note.id), "F3 restore")
    EQ(note.trashed, nil, "F3 restore clears the stamp")
    EQ(#S.List({ scope = "all" }), 1, "F3 restored note is visible again")
    CHECK(not S.Restore(note.id), "F3 restoring a live note is a no-op")

    S.Trash(note.id)
    CHECK(S.Destroy(note.id), "F4 destroy")
    CHECK(db.Notes[note.id] == nil, "F4 destroy really forgets")
    CHECK(not S.Destroy(note.id), "F4 destroying twice is a no-op")
end

do
    Fresh()
    local keep = S.CreateNote({ title = "keep" })
    for index = 1, 3 do
        local doomed = S.CreateNote({ title = "gone" .. index })
        S.Trash(doomed.id)
    end
    EQ(S.EmptyTrash(), 3, "F5 empty trash reports what it removed")
    EQ(S.TrashCount(), 0, "F5 trash is empty")
    CHECK(S.Note(keep.id) ~= nil, "F5 emptying the trash spares live notes")
end

do
    Fresh()
    local old = S.CreateNote({ title = "old" })
    S.Trash(old.id)
    TICK(40 * 86400)
    local recent = S.CreateNote({ title = "recent" })
    S.Trash(recent.id)

    EQ(S.PurgeExpired(0), 0, "F6 a window of zero keeps the trash forever")
    EQ(S.PurgeExpired(30), 1, "F6 only the note past the window is purged")
    CHECK(S.Note(recent.id) ~= nil, "F6 the recent one survives")
    CHECK(S.Note(old.id) == nil, "F6 the expired one is gone")
end

do
    -- Restoring a note whose notebook was deleted while it sat in the trash
    -- must land somewhere real.
    Fresh()
    local book = S.CreateNotebook("Temporary")
    local note = S.CreateNote({ title = "stranded", notebook = book })
    S.Trash(note.id)
    S.DeleteNotebook(book)
    EQ(note.notebook, S.DefaultNotebookID(), "F7 trashed notes follow a notebook deletion too")
    S.Restore(note.id)
    CHECK(S.Notebook(note.notebook) ~= nil, "F7 restore always lands in a real notebook")
end

-- ===========================================================================
-- G. Search
-- ===========================================================================

do
    Fresh()
    local raids = S.CreateNotebook("Raid Prep")
    local link = "|cffa335ee|Hitem:19019::::::::70::::::::::|h[Thunderfury]|h|r"

    -- Separated in time on purpose: with three notes born in the same second
    -- the id tiebreaker would decide the order below, and these assertions are
    -- about recency.
    local a = S.CreateNote({ title = "Kara trash", body = "pull order and " .. link,
        notebook = raids, tags = { "raid", "kara" } })
    TICK(5)
    local b = S.CreateNote({ title = "Arena comp", body = "RMP opener", tags = { "pvp" } })
    TICK(5)
    local c = S.CreateNote({ title = "Shopping", body = "primal fire x40" })
    S.TogglePin(c.id)

    local function Hits(text) return IDs(S.List({ search = text, sort = "created" })) end

    EQ(Hits(""), IDs({ c, b, a }), "G1 an empty search returns everything")
    EQ(Hits("kara"), a.id, "G2 bare term matches the title")
    EQ(Hits("opener"), b.id, "G2 bare term matches the body")
    EQ(Hits("thunderfury"), a.id, "G3 search reaches inside a hyperlink label")
    EQ(Hits("KARA"), a.id, "G4 search is case insensitive")

    EQ(Hits("primal fire"), c.id, "G5 two bare terms are ANDed")
    EQ(Hits("primal arena"), "", "G5 AND across notes matches nothing")
    EQ(Hits('"primal fire"'), c.id, "G6 quoted phrase matches in order")
    EQ(Hits('"fire primal"'), "", "G6 quoted phrase respects order")

    EQ(Hits("tag:pvp"), b.id, "G7 tag: prefix")
    EQ(Hits("tag:ra"), a.id, "G7 tag: is a prefix match, not exact")
    EQ(Hits("tag:pvp tag:raid"), "", "G7 two tag: terms are ANDed")
    EQ(Hits("notebook:raid"), a.id, "G8 notebook: prefix")
    EQ(Hits("book:raid"), a.id, "G8 book: is the same thing")
    EQ(Hits("is:pinned"), c.id, "G9 is:pinned")
    EQ(Hits("is:untagged"), c.id, "G9 is:untagged")
    EQ(Hits("is:tagged"), IDs({ b, a }), "G9 is:tagged")
    EQ(Hits("tag:raid order"), a.id, "G10 a prefix term and a bare term combine")
    EQ(Hits("tag:raid arena"), "", "G10 and the combination can fail")

    -- Searching a notebook's name as a bare word finds its notes, which is
    -- what someone typing "raid" into the box actually wants.
    EQ(Hits("prep"), a.id, "G11 bare terms also see the notebook name")

    S.Trash(b.id)
    EQ(Hits("opener"), "", "G12 search never returns from the trash by accident")
    EQ(IDs(S.List({ scope = "trash", search = "opener" })), b.id, "G12 but does inside it")
end

do
    Fresh()
    local parsed = S.ParseSearch("  ")
    CHECK(S.IsEmptyQuery(parsed), "G13 whitespace is an empty query")
    CHECK(not S.IsEmptyQuery(S.ParseSearch("tag:x")), "G13 a lone prefix is not empty")
end

-- ===========================================================================
-- H. Listing and order
-- ===========================================================================

do
    Fresh()
    local first = S.CreateNote({ title = "Bravo" })
    TICK(10)
    local second = S.CreateNote({ title = "alpha" })
    TICK(10)
    local third = S.CreateNote({ title = "Charlie" })
    TICK(10)
    S.SetBody(first.id, "edited last")

    EQ(IDs(S.List({ sort = "updated" })), IDs({ first, third, second }), "H1 updated sorts by last edit")
    EQ(IDs(S.List({ sort = "created" })), IDs({ third, second, first }), "H2 created sorts by birth")
    EQ(IDs(S.List({ sort = "title" })), IDs({ second, first, third }), "H3 title sorts case insensitively")

    S.TogglePin(second.id)
    EQ(IDs(S.List({ sort = "updated" })), IDs({ second, first, third }), "H4 pinned notes lead")
    EQ(IDs(S.List({ sort = "updated", pinFirst = false })), IDs({ first, third, second }),
        "H4 unless pin-first is off")

    EQ(#S.List({ limit = 2 }), 2, "H5 limit truncates")
    EQ(IDs(S.List({ sort = "updated", limit = 1 })), second.id, "H5 limit keeps the top of the order")
end

do
    -- Two notes written in the same second must not swap places between two
    -- refreshes of an unchanged list. table.sort is not stable, so the id is
    -- the tiebreaker.
    Fresh()
    local made = {}
    for index = 1, 8 do made[index] = S.CreateNote({ title = "same second " .. index }) end
    local baseline = IDs(S.List({ sort = "updated" }))
    for _ = 1, 5 do
        EQ(IDs(S.List({ sort = "updated" })), baseline, "H6 identical timestamps sort deterministically")
    end
    local _ = made
end

do
    Fresh()
    local book = S.CreateNotebook("Alpha Book")
    local inBook = S.CreateNote({ title = "in", notebook = book, tags = { "x" } })
    local outBook = S.CreateNote({ title = "out" })
    EQ(IDs(S.List({ scope = "notebook", key = book })), inBook.id, "H7 notebook scope")
    EQ(IDs(S.List({ scope = "tag", key = "x" })), inBook.id, "H7 tag scope")
    EQ(IDs(S.List({ scope = "untagged" })), outBook.id, "H7 untagged scope")
    S.TogglePin(outBook.id)
    EQ(IDs(S.List({ scope = "pinned" })), outBook.id, "H7 pinned scope")
    EQ(#S.List({ scope = "notebook", key = "nb-nope" }), 0, "H8 an unknown notebook scope is empty, not everything")
    EQ(#S.List({ scope = "tag", key = "nope" }), 0, "H8 an unknown tag scope is empty")

    EQ(S.Count({ scope = "all" }), 2, "H9 count")
end

do
    Fresh()
    local sortBook = S.CreateNotebook("Zeta")
    local one = S.CreateNote({ title = "z", notebook = sortBook })
    local two = S.CreateNote({ title = "a" })
    EQ(IDs(S.List({ sort = "notebook" })), IDs({ two, one }),
        "H10 notebook sort orders by notebook name (Field Notes before Zeta)")
end

-- ===========================================================================
-- I. Stats
-- ===========================================================================

do
    Fresh()
    S.CreateNotebook("Second")
    local a = S.CreateNote({ title = "one two", body = "three four five", tags = { "x" } })
    local b = S.CreateNote({ body = "six", tags = { "x", "y" } })
    local gone = S.CreateNote({ body = "not counted", tags = { "z" } })
    S.Trash(gone.id)
    S.TogglePin(a.id)

    local stats = S.Stats()
    EQ(stats.notes, 2, "I1 live notes counted")
    EQ(stats.trashed, 1, "I1 trashed counted separately")
    EQ(stats.pinned, 1, "I1 pinned counted")
    EQ(stats.notebooks, 2, "I1 notebooks counted")
    EQ(stats.tags, 2, "I2 tags counted from live notes only")
    EQ(stats.words, 4, "I3 words counted from bodies only")
    local _ = b
end

-- ===========================================================================
-- J. Links (the attachment strip)
-- ===========================================================================

do
    Fresh()
    local item = "|cffa335ee|Hitem:19019::::::::70::::::::::|h[Thunderfury]|h|r"
    local spell = "|cff71d5ff|Hspell:25289|h[Battle Shout]|h|r"
    local quest = "|cffffff00|Hquest:9999:70|h[A Terrible Purpose]|h|r"

    local note = S.CreateNote({ body = "before " .. item .. " middle " .. spell .. "\nthen " .. quest })
    local links = S.Links(note)
    EQ(#links, 3, "J1 every link in the body is found")
    EQ(links[1].label, "Thunderfury", "J1 label stripped of colour and brackets")
    EQ(links[1].kind, "item", "J1 kind read from the payload")
    EQ(links[1].id, 19019, "J1 numeric id read from the payload")
    EQ(links[2].kind, "spell", "J1 spell link")
    EQ(links[2].id, 25289, "J1 spell id")
    EQ(links[3].kind, "quest", "J1 quest link")
    -- The payload is what goes back to SetHyperlink, so it must come out
    -- whole -- colour and brackets are display, the payload is identity.
    EQ(links[1].payload, "item:19019::::::::70::::::::::", "J2 payload preserved verbatim")

    local twice = S.CreateNote({ body = item .. " and again " .. item })
    EQ(#S.Links(twice), 1, "J3 the same link twice is one attachment")

    EQ(#S.Links(S.CreateNote({ body = "no links here" })), 0, "J4 plain text has no attachments")
    EQ(#S.Links(nil), 0, "J4 a nil note has no attachments, and does not error")
    EQ(S.LinkCount(note), 3, "J5 link count")
end

-- ===========================================================================

if fails > 0 then
    io.write(string.format("\n%d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("notebook_harness: %d checks passed\n", checks))

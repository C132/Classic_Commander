-- Commander Notebook: the store.
--
-- Everything the notebook knows lives in one SavedVariables table and this
-- file is the only thing allowed to write it. No widgets are touched here, on
-- purpose: the store is plain Lua, so the harness drives the real functions
-- against real fixtures and a failure is always a logic bug rather than a mock
-- artefact -- the same split Armory documents.
--
-- The shape on disk:
--
--   CommanderNotebookDB = {
--     <settings keys, flat, per the suite convention>
--     Notes     = { [id] = note },
--     Notebooks = { [id] = { id, name, created, builtin } },
--     NextID    = 41,
--   }
--
--   note = {
--     id, title, body,
--     notebook,                 -- notebook id, never nil, never dangling
--     tags     = { "raid", "keys" },   -- ordered, lowercased, deduped
--     created, updated,         -- epoch seconds
--     pinned   = true|nil,
--     trashed  = <epoch>|nil,   -- set means "in the trash since"
--     context  = { who, class, level, zone, subzone, map, x, y, target },
--   }
--
-- context is where the note was last stamped WITH a position (1.1.0): map
-- is the uiMapID the coordinates are on, x and y are 0..1. A stamp written
-- where the map has no position (inside an instance) leaves it alone, so it
-- always names the latest place the note can lead back to. Stamps written
-- before 1.1.0 are text only; S.Location reads the newest of those lines
-- instead, and its zone NAME is all there is to go on.
--
-- Notes are a map rather than an array because a note id has to survive the
-- disappearance of every note around it: the UI holds a selection across a
-- refresh, the trash restores into the middle of a list, and array indices do
-- neither. Order is a property of a *query*, not of storage.

CommanderNotebookStore = CommanderNotebookStore or {}
local S = CommanderNotebookStore

local DEFAULT_NOTEBOOK = "nb-default"
local UNTITLED = "Untitled note"

-- ---------------------------------------------------------------------------
-- Injection points
--
-- The clock and the identity are functions rather than direct calls so the
-- harness can freeze time and play a named character without a client. Live,
-- these are replaced at load by the addon.
-- ---------------------------------------------------------------------------

function S.Now()
    return (type(time) == "function" and time()) or 0
end

function S.Who()
    return "player"
end

local db

-- ---------------------------------------------------------------------------
-- Attach / normalise
--
-- Attach is the ONLY entry point that may see a malformed table, and it must
-- survive anything: a fresh account, a table hand-edited between sessions, a
-- note whose notebook was deleted by an older build. Every later function may
-- then assume the invariants below hold.
--
-- Invariants after Attach:
--   * db.Notes, db.Notebooks are tables
--   * at least one notebook exists, and DEFAULT_NOTEBOOK is it
--   * every note has a string id matching its key, a title and body string,
--     an ordered tag array, created/updated numbers, and a notebook id that
--     resolves
--   * db.NextID is greater than every numeric id in use
-- ---------------------------------------------------------------------------

local function TrimString(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NormaliseTagList(tags)
    local seen, out = {}, {}
    if type(tags) ~= "table" then return out end
    for _, tag in ipairs(tags) do
        local name = TrimString(tag):lower()
        if name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Where a note was written
-- ---------------------------------------------------------------------------

local CONTEXT_KEYS = { "who", "class", "level", "zone", "subzone", "map", "x", "y", "target" }

local function Fraction(v)
    return type(v) == "number" and v == v and v >= 0 and v <= 1
end

-- A context table made safe in place: a position is a whole positive map id
-- with both coordinates in 0..1, or it is not there at all
function S.CleanContext(context)
    if type(context) ~= "table" then return nil end
    local map = context.map
    if type(map) ~= "number" or map <= 0 or map ~= math.floor(map) then context.map = nil end
    if not (Fraction(context.x) and Fraction(context.y)) then
        context.x, context.y, context.map = nil, nil, nil
    end
    return context
end

-- A detached copy of the known fields
function S.CopyContext(context)
    if type(context) ~= "table" then return nil end
    local copy = {}
    for _, key in ipairs(CONTEXT_KEYS) do copy[key] = context[key] end
    return S.CleanContext(copy)
end

-- The newest pre-1.1.0 stamp line that carries a place and coordinates:
-- "-- Name (70) | Subzone, Zone 45.2, 63.1 | target: X | 04 Oct 2026, 13:50"
-- -> { zone, subzone, x, y } with x, y in 0..1, or nil.
function S.StampLocation(text)
    local found
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        if line:sub(1, 3) == "-- " then
            for piece in (line:sub(4) .. " | "):gmatch("(.-) | ") do
                if piece:sub(1, 8) ~= "target: " then
                    local place, xs, ys = piece:match("^(.-) (%d+%.?%d*), (%d+%.?%d*)$")
                    local x, y = tonumber(xs), tonumber(ys)
                    if place and place ~= "" and x and y and x <= 100 and y <= 100 then
                        local subzone, zone = place:match("^(.*), ([^,]+)$")
                        found = { zone = TrimString(zone or place), subzone = subzone and TrimString(subzone) or nil,
                                  x = x / 100, y = y / 100 }
                    end
                end
            end
        end
    end
    return found
end

-- Where "Waypoint to this note" goes: the stored context when it has a map
-- (from = "context"), else the newest old-style stamp line (from = "stamp",
-- zone name only). nil when the note has neither.
function S.Location(note)
    if not note then return nil end
    local c = note.context
    if type(c) == "table" and c.map and Fraction(c.x) and Fraction(c.y) then
        return { map = c.map, x = c.x, y = c.y, zone = c.zone, subzone = c.subzone, from = "context" }
    end
    local stamp = S.StampLocation(note.body)
    if stamp then stamp.from = "stamp" end
    return stamp
end

-- Remember where a stamp was written. Only a context with a position is
-- kept (see the schema note at the top); the stamp's own text is written by
-- AppendBody, which is what marks the note updated.
function S.SetContext(id, context)
    local note = db.Notes[id]
    if not note then return false end
    local copy = S.CopyContext(context)
    if not (copy and copy.map) then return false end
    note.context = copy
    return true
end

function S.Attach(target)
    db = target or {}
    db.Notes = type(db.Notes) == "table" and db.Notes or {}
    db.Notebooks = type(db.Notebooks) == "table" and db.Notebooks or {}
    db.NextID = tonumber(db.NextID) or 1

    if not db.Notebooks[DEFAULT_NOTEBOOK] then
        db.Notebooks[DEFAULT_NOTEBOOK] = {
            id = DEFAULT_NOTEBOOK,
            name = "Field Notes",
            created = S.Now(),
            builtin = true,
        }
    end

    for id, book in pairs(db.Notebooks) do
        if type(book) ~= "table" then
            db.Notebooks[id] = nil
        else
            book.id = id
            book.name = TrimString(book.name)
            if book.name == "" then book.name = "Notebook" end
            book.created = tonumber(book.created) or S.Now()
        end
    end

    local highest = 0
    for id, note in pairs(db.Notes) do
        if type(note) ~= "table" then
            db.Notes[id] = nil
        else
            note.id = id
            note.title = tostring(note.title or "")
            note.body = tostring(note.body or "")
            note.tags = NormaliseTagList(note.tags)
            note.created = tonumber(note.created) or S.Now()
            note.updated = tonumber(note.updated) or note.created
            note.trashed = tonumber(note.trashed) or nil
            note.pinned = note.pinned and true or nil
            if type(note.context) ~= "table" then note.context = nil end
            if note.context then S.CleanContext(note.context) end
            -- A note whose notebook was deleted out from under it lands back
            -- in the default rather than vanishing from every view at once.
            if type(note.notebook) ~= "string" or not db.Notebooks[note.notebook] then
                note.notebook = DEFAULT_NOTEBOOK
            end
            local numeric = tonumber(tostring(id):match("^n(%d+)$") or "")
            if numeric and numeric > highest then highest = numeric end
        end
    end
    if db.NextID <= highest then db.NextID = highest + 1 end

    return db
end

function S.DB()
    return db
end

function S.Attached()
    return db ~= nil
end

function S.DefaultNotebookID()
    return DEFAULT_NOTEBOOK
end

-- ---------------------------------------------------------------------------
-- Text
--
-- A note body is allowed to contain the game's own escape sequences, because
-- shift-clicking an item into a note is the whole point of writing notes in a
-- game client rather than in a text file. That makes every read of a body for
-- any purpose other than display go through PlainText first: a search for
-- "thunderfury" has to match the label inside the hyperlink, and a snippet
-- that pasted a raw |cff colour code into a list row would leak that colour
-- across the rest of the row.
-- ---------------------------------------------------------------------------

function S.PlainText(text)
    text = tostring(text or "")
    -- Inline textures carry no readable text at all
    text = text:gsub("|T.-|t", " ")
    text = text:gsub("|A.-|a", " ")
    -- A hyperlink keeps its label and loses its payload: |Hitem:...|h[Foo]|h
    text = text:gsub("|H.-|h(.-)|h", "%1")
    -- Brackets are the link convention, not part of the word
    text = text:gsub("%[(.-)%]", "%1")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("||", "|")
    text = text:gsub("|n", " ")
    return text
end

-- One line, no newlines, collapsed whitespace -- the note list's second row.
function S.Snippet(note, limit)
    if not note then return "" end
    local plain = S.PlainText(note.body)
    plain = plain:gsub("[\r\n]+", " "):gsub("%s+", " ")
    plain = TrimString(plain)
    limit = limit or 90
    if plain == "" then return "" end
    if #plain > limit then
        -- Cut on a space when there is one near the end, so the snippet does
        -- not stop mid-word
        local cut = plain:sub(1, limit)
        local space = cut:match("^.*()%s")
        if space and space > limit - 18 then cut = cut:sub(1, space - 1) end
        return cut .. "..."
    end
    return plain
end

function S.TitleFor(note)
    if not note then return UNTITLED end
    local title = TrimString(note.title)
    if title ~= "" then return title end
    -- Evernote titled an untitled note from its first line as you typed. The
    -- same trick here means a note captured with a keybind and never named
    -- still reads as something in the list.
    local firstLine = S.PlainText(note.body):match("^%s*([^\r\n]+)")
    firstLine = TrimString(firstLine)
    if firstLine ~= "" then
        if #firstLine > 60 then firstLine = firstLine:sub(1, 60) .. "..." end
        return firstLine
    end
    return UNTITLED
end

function S.WordCount(note)
    if not note then return 0 end
    local count = 0
    for _ in S.PlainText(note.body):gmatch("[%w'\128-\255]+") do
        count = count + 1
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Notebooks
-- ---------------------------------------------------------------------------

local function NextID(prefix)
    local id = prefix .. tostring(db.NextID)
    db.NextID = db.NextID + 1
    return id
end

function S.Notebook(id)
    return db.Notebooks[id]
end

function S.NotebookName(id)
    local book = db.Notebooks[id]
    return book and book.name or "Unfiled"
end

function S.NotebookByName(name)
    name = TrimString(name):lower()
    for id, book in pairs(db.Notebooks) do
        if book.name:lower() == name then return id end
    end
    return nil
end

function S.CreateNotebook(name)
    name = TrimString(name)
    if name == "" then return nil, "A notebook needs a name." end
    if S.NotebookByName(name) then return nil, "There is already a notebook called " .. name .. "." end
    local id = NextID("nb")
    db.Notebooks[id] = { id = id, name = name, created = S.Now() }
    return id
end

function S.RenameNotebook(id, name)
    local book = db.Notebooks[id]
    if not book then return false, "No such notebook." end
    name = TrimString(name)
    if name == "" then return false, "A notebook needs a name." end
    local clash = S.NotebookByName(name)
    if clash and clash ~= id then return false, "There is already a notebook called " .. name .. "." end
    book.name = name
    return true
end

-- Deleting a notebook never deletes notes. They move -- to `moveTo` when it
-- resolves, otherwise to the default. Losing a folder should not lose the
-- writing that was in it, and a confirm dialog is a worse guarantee than an
-- invariant.
function S.DeleteNotebook(id, moveTo)
    if id == DEFAULT_NOTEBOOK then return false, "The default notebook cannot be deleted." end
    if not db.Notebooks[id] then return false, "No such notebook." end
    if not moveTo or not db.Notebooks[moveTo] or moveTo == id then
        moveTo = DEFAULT_NOTEBOOK
    end
    local moved = 0
    for _, note in pairs(db.Notes) do
        if note.notebook == id then
            note.notebook = moveTo
            moved = moved + 1
        end
    end
    db.Notebooks[id] = nil
    return true, moved
end

-- Sorted for display: the default notebook leads, the rest alphabetical, with
-- live counts of the notes that are not in the trash.
function S.Notebooks()
    local counts = {}
    for _, note in pairs(db.Notes) do
        if not note.trashed then
            counts[note.notebook] = (counts[note.notebook] or 0) + 1
        end
    end
    local list = {}
    for id, book in pairs(db.Notebooks) do
        list[#list + 1] = {
            id = id,
            name = book.name,
            builtin = book.builtin,
            created = book.created,
            count = counts[id] or 0,
        }
    end
    table.sort(list, function(a, b)
        if a.builtin ~= b.builtin then return a.builtin and true or false end
        local an, bn = a.name:lower(), b.name:lower()
        if an ~= bn then return an < bn end
        return a.id < b.id
    end)
    return list
end

-- ---------------------------------------------------------------------------
-- Tags
-- ---------------------------------------------------------------------------

-- Tags are typed as one comma-separated line, the way Evernote's tag field
-- worked, and stored lowercased so "Raid" and "raid" are one tag rather than
-- two rows in the sidebar that can never be merged.
function S.ParseTags(text)
    local out = {}
    for piece in tostring(text or ""):gmatch("[^,]+") do
        out[#out + 1] = piece
    end
    return NormaliseTagList(out)
end

function S.TagString(note)
    if not note or not note.tags then return "" end
    return table.concat(note.tags, ", ")
end

function S.Tags()
    local counts = {}
    for _, note in pairs(db.Notes) do
        if not note.trashed then
            for _, tag in ipairs(note.tags) do
                counts[tag] = (counts[tag] or 0) + 1
            end
        end
    end
    local list = {}
    for tag, count in pairs(counts) do
        list[#list + 1] = { name = tag, count = count }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    return list
end

function S.HasTag(note, tag)
    if not note or not tag then return false end
    for _, existing in ipairs(note.tags) do
        if existing == tag then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------------

function S.Note(id)
    local note = id and db.Notes[id]
    return note
end

function S.CreateNote(opts)
    opts = opts or {}
    local now = S.Now()
    local id = NextID("n")
    local notebook = opts.notebook
    if not notebook or not db.Notebooks[notebook] then notebook = DEFAULT_NOTEBOOK end
    local note = {
        id = id,
        title = TrimString(opts.title),
        body = tostring(opts.body or ""),
        notebook = notebook,
        tags = NormaliseTagList(opts.tags),
        created = now,
        updated = now,
        context = opts.context,
    }
    db.Notes[id] = note
    return note
end

-- Every mutator funnels through Touch so "updated" cannot drift from what was
-- actually changed, and so a no-op write (the editor firing OnTextChanged
-- because the note was loaded into it) does not reorder the whole list under
-- the reader's cursor. That guard is why every setter returns whether it
-- changed anything.
local function Touch(note)
    note.updated = S.Now()
end

function S.SetTitle(id, text)
    local note = db.Notes[id]
    if not note then return false end
    text = TrimString(text)
    if note.title == text then return false end
    note.title = text
    Touch(note)
    return true
end

function S.SetBody(id, text)
    local note = db.Notes[id]
    if not note then return false end
    text = tostring(text or "")
    if note.body == text then return false end
    note.body = text
    Touch(note)
    return true
end

function S.AppendBody(id, text)
    local note = db.Notes[id]
    if not note then return false end
    text = tostring(text or "")
    if text == "" then return false end
    if note.body ~= "" and not note.body:match("\n$") then
        note.body = note.body .. "\n"
    end
    note.body = note.body .. text
    Touch(note)
    return true
end

function S.SetNotebook(id, notebookId)
    local note = db.Notes[id]
    if not note then return false end
    if not db.Notebooks[notebookId] then return false end
    if note.notebook == notebookId then return false end
    note.notebook = notebookId
    Touch(note)
    return true
end

function S.SetTags(id, text)
    local note = db.Notes[id]
    if not note then return false end
    local tags = type(text) == "table" and NormaliseTagList(text) or S.ParseTags(text)
    if table.concat(note.tags, ",") == table.concat(tags, ",") then return false end
    note.tags = tags
    Touch(note)
    return true
end

function S.AddTag(id, tag)
    local note = db.Notes[id]
    if not note then return false end
    tag = TrimString(tag):lower()
    if tag == "" or S.HasTag(note, tag) then return false end
    note.tags[#note.tags + 1] = tag
    Touch(note)
    return true
end

function S.RemoveTag(id, tag)
    local note = db.Notes[id]
    if not note then return false end
    tag = TrimString(tag):lower()
    for index, existing in ipairs(note.tags) do
        if existing == tag then
            table.remove(note.tags, index)
            Touch(note)
            return true
        end
    end
    return false
end

-- Renaming a tag everywhere is the one tag operation the sidebar cannot fake
-- by editing notes one at a time, so it lives here.
function S.RenameTag(from, to)
    from, to = TrimString(from):lower(), TrimString(to):lower()
    if from == "" or to == "" or from == to then return 0 end
    local touched = 0
    for _, note in pairs(db.Notes) do
        local hit = false
        for index, tag in ipairs(note.tags) do
            if tag == from then
                note.tags[index] = to
                hit = true
            end
        end
        if hit then
            note.tags = NormaliseTagList(note.tags)
            Touch(note)
            touched = touched + 1
        end
    end
    return touched
end

function S.DeleteTag(tag)
    tag = TrimString(tag):lower()
    local touched = 0
    for id, note in pairs(db.Notes) do
        if S.RemoveTag(id, tag) then touched = touched + 1 end
        local _ = note
    end
    return touched
end

function S.TogglePin(id)
    local note = db.Notes[id]
    if not note then return false end
    note.pinned = (not note.pinned) or nil
    -- Pinning is a shelf, not an edit: it deliberately does not touch
    -- "updated", or pinning a note would jump it to the top of a
    -- recently-updated sort for a reason that has nothing to do with writing.
    return note.pinned and true or false
end

function S.Duplicate(id)
    local note = db.Notes[id]
    if not note then return nil end
    local copy = S.CreateNote({
        title = note.title ~= "" and (note.title .. " (copy)") or "",
        body = note.body,
        notebook = note.notebook,
        tags = note.tags,
        context = S.CopyContext(note.context),
    })
    return copy
end

-- ---------------------------------------------------------------------------
-- Trash
--
-- Deleting is two-stage on purpose. A note is a piece of writing and the only
-- copy of it is in one SavedVariables file, so nothing in this module removes
-- text on a single click: Trash sets a timestamp, the note leaves every view
-- except the trash, and Destroy is the only function that actually forgets.
-- ---------------------------------------------------------------------------

function S.Trash(id)
    local note = db.Notes[id]
    if not note or note.trashed then return false end
    note.trashed = S.Now()
    note.pinned = nil
    return true
end

function S.Restore(id)
    local note = db.Notes[id]
    if not note or not note.trashed then return false end
    note.trashed = nil
    if not db.Notebooks[note.notebook] then note.notebook = DEFAULT_NOTEBOOK end
    return true
end

function S.Destroy(id)
    if not db.Notes[id] then return false end
    db.Notes[id] = nil
    return true
end

function S.EmptyTrash()
    local removed = 0
    for id, note in pairs(db.Notes) do
        if note.trashed then
            db.Notes[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- Age out the trash. Called at login with the configured window; a window of
-- zero means "keep the trash forever", which is the safe reading of 0.
function S.PurgeExpired(days)
    days = tonumber(days) or 0
    if days <= 0 then return 0 end
    local cutoff = S.Now() - days * 86400
    local removed = 0
    for id, note in pairs(db.Notes) do
        if note.trashed and note.trashed < cutoff then
            db.Notes[id] = nil
            removed = removed + 1
        end
    end
    return removed
end

function S.TrashCount()
    local count = 0
    for _, note in pairs(db.Notes) do
        if note.trashed then count = count + 1 end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Search
--
-- Evernote's search bar took a small grammar rather than a plain substring,
-- and the two prefixes that carried it were `tag:` and `notebook:`. Those are
-- here, plus `is:` for the flags, plus quoted phrases. Everything else is a
-- bare term, and bare terms are ANDed: typing two words narrows, which is what
-- everyone expects a search box to do.
--
-- ParseSearch is separated from Matches so the parse happens once per query
-- rather than once per note. With a few hundred notes that is the difference
-- between a search box that filters as you type and one that stutters.
-- ---------------------------------------------------------------------------

function S.ParseSearch(text)
    local parsed = { terms = {}, tags = {}, books = {}, flags = {}, raw = TrimString(text) }
    local query = parsed.raw:lower()
    if query == "" then return parsed end

    -- Quoted phrases first, so their spaces survive the word split
    query = query:gsub('"(.-)"', function(phrase)
        phrase = TrimString(phrase)
        if phrase ~= "" then parsed.terms[#parsed.terms + 1] = phrase end
        return " "
    end)

    for word in query:gmatch("%S+") do
        local prefix, value = word:match("^(%a+):(.+)$")
        if prefix == "tag" then
            parsed.tags[#parsed.tags + 1] = value
        elseif prefix == "notebook" or prefix == "book" or prefix == "in" then
            parsed.books[#parsed.books + 1] = value
        elseif prefix == "is" then
            parsed.flags[value] = true
        else
            parsed.terms[#parsed.terms + 1] = word
        end
    end
    return parsed
end

function S.IsEmptyQuery(parsed)
    return not parsed or (#parsed.terms == 0 and #parsed.tags == 0
        and #parsed.books == 0 and next(parsed.flags) == nil)
end

local function Contains(haystack, needle)
    return haystack:find(needle, 1, true) ~= nil
end

function S.Matches(note, parsed)
    if S.IsEmptyQuery(parsed) then return true end

    for _, want in ipairs(parsed.tags) do
        local hit = false
        for _, tag in ipairs(note.tags) do
            if Contains(tag, want) then hit = true break end
        end
        if not hit then return false end
    end

    for _, want in ipairs(parsed.books) do
        if not Contains(S.NotebookName(note.notebook):lower(), want) then return false end
    end

    if parsed.flags.pinned and not note.pinned then return false end
    if parsed.flags.tagged and #note.tags == 0 then return false end
    if parsed.flags.untagged and #note.tags > 0 then return false end
    if parsed.flags.trashed and not note.trashed then return false end

    if #parsed.terms > 0 then
        local hay = (S.PlainText(note.title) .. " \n " .. S.PlainText(note.body)
            .. " \n " .. table.concat(note.tags, " ")
            .. " \n " .. S.NotebookName(note.notebook)):lower()
        for _, term in ipairs(parsed.terms) do
            if not Contains(hay, term) then return false end
        end
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Listing
--
-- query = {
--   scope = "all" | "notebook" | "tag" | "trash" | "pinned" | "recent",
--   key      = notebook id or tag name, for the scopes that need one,
--   search   = raw search text,
--   sort     = "updated" | "created" | "title" | "notebook",
--   pinFirst = bool,
--   limit    = n,
-- }
--
-- One rule runs through every scope: the trash is a place, not a filter. A
-- trashed note appears in the trash scope and nowhere else, so a delete never
-- silently leaves a note visible under its tag.
-- ---------------------------------------------------------------------------

local SORTERS = {
    updated = function(a, b) return a.updated > b.updated end,
    created = function(a, b) return a.created > b.created end,
    title = function(a, b) return S.TitleFor(a):lower() < S.TitleFor(b):lower() end,
    notebook = function(a, b)
        local an, bn = S.NotebookName(a.notebook):lower(), S.NotebookName(b.notebook):lower()
        if an ~= bn then return an < bn end
        return a.updated > b.updated
    end,
}

function S.List(query)
    query = query or {}
    local scope = query.scope or "all"
    local parsed = S.ParseSearch(query.search)
    local out = {}

    for _, note in pairs(db.Notes) do
        local keep
        if scope == "trash" then
            keep = note.trashed ~= nil
        elseif note.trashed then
            keep = false
        elseif scope == "notebook" then
            keep = note.notebook == query.key
        elseif scope == "tag" then
            keep = S.HasTag(note, query.key)
        elseif scope == "pinned" then
            keep = note.pinned and true or false
        elseif scope == "untagged" then
            keep = #note.tags == 0
        else
            keep = true
        end
        if keep and S.Matches(note, parsed) then
            out[#out + 1] = note
        end
    end

    local sorter = SORTERS[query.sort or "updated"] or SORTERS.updated
    local pinFirst = query.pinFirst
    if pinFirst == nil then pinFirst = true end
    -- table.sort is not stable, so every comparator ends on the id. Without
    -- that tiebreaker two notes written in the same second can swap places
    -- between two refreshes of an unchanged list, which reads as a flicker.
    table.sort(out, function(a, b)
        if pinFirst and (a.pinned and true or false) ~= (b.pinned and true or false) then
            return a.pinned and true or false
        end
        if sorter(a, b) then return true end
        if sorter(b, a) then return false end
        return a.id < b.id
    end)

    if query.limit and #out > query.limit then
        for index = #out, query.limit + 1, -1 do out[index] = nil end
    end
    return out
end

function S.Count(query)
    return #S.List(query)
end

function S.Stats()
    local stats = { notes = 0, trashed = 0, pinned = 0, words = 0, notebooks = 0, tags = 0 }
    local tags = {}
    for _, note in pairs(db.Notes) do
        if note.trashed then
            stats.trashed = stats.trashed + 1
        else
            stats.notes = stats.notes + 1
            stats.words = stats.words + S.WordCount(note)
            if note.pinned then stats.pinned = stats.pinned + 1 end
            for _, tag in ipairs(note.tags) do tags[tag] = true end
        end
    end
    for _ in pairs(db.Notebooks) do stats.notebooks = stats.notebooks + 1 end
    for _ in pairs(tags) do stats.tags = stats.tags + 1 end
    return stats
end

-- ---------------------------------------------------------------------------
-- Links
--
-- Evernote's notes carried attachments. A note written inside the game carries
-- hyperlinks instead -- an item shift-clicked out of a bag, a spell dragged
-- from the book, a quest, a player -- and those are the closest thing this
-- client has to an attachment: they survive as text in SavedVariables, and
-- they can be handed straight back to GameTooltip:SetHyperlink to become the
-- real thing again.
--
-- The parse is here rather than in the UI so the attachment strip has no logic
-- of its own to get wrong, and so the harness can prove it against links this
-- client really writes.
-- ---------------------------------------------------------------------------

function S.Links(note)
    local out, seen = {}, {}
    if not note then return out end
    for payload, label in tostring(note.body or ""):gmatch("|H(.-)|h(.-)|h") do
        if payload ~= "" and not seen[payload] then
            seen[payload] = true
            local clean = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            clean = clean:gsub("^%[(.*)%]$", "%1")
            clean = TrimString(clean)
            out[#out + 1] = {
                payload = payload,
                label = clean ~= "" and clean or payload,
                kind = payload:match("^(%a+):") or "link",
                id = tonumber(payload:match("^%a+:(%d+)") or ""),
            }
        end
    end
    return out
end

function S.LinkCount(note)
    return #S.Links(note)
end

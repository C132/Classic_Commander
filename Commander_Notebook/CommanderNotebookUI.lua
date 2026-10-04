-- Commander Notebook: the window.
--
-- The old Evernote desktop client had one shape and everything else followed
-- from it: three columns, left to right, each narrowing what the next one
-- shows. A sidebar of sources -- all notes, your notebooks, your tags, the
-- trash. A list of the notes in whichever source is selected, one row each
-- with its title, the first line of its text and when you last touched it.
-- And the note itself, open and editable, with no save button anywhere on
-- screen because notes saved themselves as you typed.
--
-- That is what this is. The parts that are not Evernote are the parts that
-- only make sense in a game client: an item shift-clicked into a note stays a
-- real hyperlink, the attachment strip under the page is built from those
-- links, and a note can stamp where you were standing when you wrote it.
--
-- A stamp is also a way back (1.1.0). Since this version a stamp written
-- where the map has a position keeps the map id with it (note.context, see
-- the store), and a note that has one offers Go and "Waypoint To This Note":
-- Commander Orders' arrow to that exact spot. Stamps written before 1.1.0
-- are text only, "Subzone, Zone 45.2, 63.1", and carry no map id; those go
-- through Orders' /way zone resolver by name (CommanderOrders.Import), the
-- same one /way uses, so an ambiguous name is listed rather than guessed.
-- Without Commander Orders the spot is printed as a /way line, so the button
-- never silently does nothing.
--
-- Chrome is drawn, not borrowed: selection bars, chevrons, rules and the pin
-- are quads cut from WHITE8X8 and tinted, for the reasons Quest Log and Bags
-- document -- ARIALN renders shape glyphs as missing-glyph boxes and icon
-- FILES move between client patches. The one Blizzard region kept on purpose
-- is the quest parchment behind the page, which is what makes the writing
-- area read as paper rather than as a text field.

CommanderNotebook = CommanderNotebook or {}
local N = CommanderNotebook
local S = CommanderNotebookStore

BINDING_HEADER_COMMANDERNOTEBOOK = "Commander Notebook"
BINDING_NAME_COMMANDERNOTEBOOK_TOGGLE = "Open the Notebook"
BINDING_NAME_COMMANDERNOTEBOOK_NEW = "New Note"
BINDING_NAME_COMMANDERNOTEBOOK_SEARCH = "Search Notes"

local QUAD = "Interface\\Buttons\\WHITE8X8"
local PAD = 10
local FRAME_W, FRAME_H = 900, 566
local TOOLBAR_H = 26
local SIDEBAR_W = 156
local LIST_W = 236
local SIDE_ROW_H = 18
local SIDE_HEADER_H = 22
local ACTION_H = 26
local ATTACH_H = 26
local UNTITLED = "Untitled note"

local frame
local sidebarScroll, sidebarChild, listScroll, listChild
local titleBox, tagBox, bodyScroll, body, infoText
local attachStrip, actionRow
local sideRows, listRows, attachButtons = {}, {}, {}
local sideEntries, listEntries = {}, {}

-- Session state. Where the reader is, not what the reader chose: this lives
-- in the DB so the window opens where it was left, but deliberately outside
-- DefaultSettings so Restore Defaults does not reach it.
local state = {
    scope = "all",
    key = nil,
    search = "",
    sort = "updated",
    selected = nil,
}

local loading = false      -- true while widgets are being filled programmatically
local dirty = false        -- the open note has unsaved keystrokes
local saveAt = nil         -- when the debounce fires
local listStale = false    -- a refresh was wanted but the writer is mid-sentence
local scrollToSelection = false  -- the selection moved, so the list should follow it
local ApplyStyle, RefreshAll, RefreshSidebar, RefreshList, RefreshEditor
local LoadNote, SelectNote, Flush

local function DB()
    return CommanderNotebookDB or {}
end

local function Enabled()
    return DB().EnableNotebook ~= false
end

local function Ready()
    return S and S.Attached and S.Attached()
end

-- ---------------------------------------------------------------------------
-- Tint and skin
--
-- The TopBar soft-fail: Commander_Console owns the palette, so it is read
-- through ipairs(x or {}) and falls back to steel. A missing Console degrades
-- the accent, never the module.
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

-- Two complete schemes rather than one scheme with exceptions. Parchment puts
-- dark ink on the game's own paper, which is the whole reason that style
-- exists; dark is the suite's usual panel. Every piece of text and every rule
-- in this file reads its colour from here, so neither style can end up with
-- one stray unreadable label.
local SKINS = {
    PARCHMENT = {
        pane      = { 0.32, 0.24, 0.14, 0.20 },
        paneEdge  = { 0.42, 0.34, 0.22, 0.90 },
        ink       = { 0.16, 0.10, 0.04 },
        inkDim    = { 0.36, 0.28, 0.18 },
        inkFaint  = { 0.50, 0.43, 0.33 },
        rule      = { 0.40, 0.32, 0.22, 0.45 },
        header    = { 0.45, 0.33, 0.16 },
        -- Low on purpose: this is a wash over paper, and the accent it is
        -- tinted with can be fully saturated (a Fel or Frost console turns a
        -- 0.4 wash into a slab of colour with unreadable ink on it).
        selection = 0.26,
        hover     = 0.12,
    },
    DARK = {
        pane      = { 0, 0, 0, 0.55 },
        paneEdge  = { 0.26, 0.26, 0.30, 0.90 },
        ink       = { 0.92, 0.92, 0.92 },
        inkDim    = { 0.68, 0.68, 0.70 },
        inkFaint  = { 0.48, 0.48, 0.52 },
        rule      = { 1, 1, 1, 0.15 },
        header    = { 0.62, 0.62, 0.68 },
        selection = 0.30,
        hover     = 0.12,
    },
}

local function Skin()
    return SKINS[DB().FrameStyle or "PARCHMENT"] or SKINS.PARCHMENT
end

local function Ink(fontString, shade)
    local skin = Skin()
    local color = skin[shade or "ink"] or skin.ink
    fontString:SetTextColor(color[1], color[2], color[3])
end

local BODY_FONTS = {
    SMALL = "GameFontHighlightSmall",
    NORMAL = "GameFontHighlight",
    LARGE = "GameFontHighlightLarge",
}

local function BodyFont()
    return BODY_FONTS[DB().EditorFontSize or "NORMAL"] or BODY_FONTS.NORMAL
end

-- ---------------------------------------------------------------------------
-- Small drawing helpers
-- ---------------------------------------------------------------------------

-- EditBox carries Enable/Disable rather than SetEnabled on this client, and a
-- disabled box must also give up focus or the cursor stays blinking in text
-- that no longer accepts keys.
local function SetBoxEnabled(box, enabled)
    if not box then return end
    if enabled then
        if box.Enable then box:Enable() end
    else
        box:ClearFocus()
        if box.Disable then box:Disable() end
    end
end

local function Quad(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(QUAD)
    return tex
end

-- SetWordWrap is not used anywhere else in the suite, so it is called through
-- a guard: a client without it gets a wrapping label rather than an error.
local function NoWrap(fontString)
    if fontString.SetWordWrap then fontString:SetWordWrap(false) end
end

local function Rule(parent)
    local tex = Quad(parent, "ARTWORK")
    tex:SetHeight(1)
    return tex
end

-- A pin drawn from two quads: a head and a shaft, leaning. Cheaper than an
-- icon file and it cannot go missing in a patch.
local function EnsurePin(parent)
    if parent.pin then return parent.pin end
    local head = Quad(parent, "OVERLAY")
    head:SetSize(5, 5)
    local shaft = Quad(parent, "OVERLAY")
    shaft:SetSize(2, 6)
    parent.pin = { head = head, shaft = shaft }
    return parent.pin
end

local function PlacePin(parent, anchorX, anchorY)
    local pin = EnsurePin(parent)
    pin.head:ClearAllPoints()
    pin.shaft:ClearAllPoints()
    pin.head:SetPoint("CENTER", parent, "TOPRIGHT", anchorX, anchorY)
    pin.shaft:SetPoint("TOP", pin.head, "BOTTOM", 0, 1)
    pin.shaft:SetRotation(0.3)
end

local function ShowPin(parent, shown)
    local pin = EnsurePin(parent)
    local r, g, b = Accent()
    pin.head:SetColorTexture(r, g, b, 1)
    pin.shaft:SetColorTexture(r, g, b, 0.8)
    pin.head:SetShown(shown)
    pin.shaft:SetShown(shown)
end

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
    local skin = Skin()
    for _, bar in ipairs(chevron) do
        bar:SetColorTexture(skin.header[1], skin.header[2], skin.header[3], 0.9)
    end
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if open then
        top:SetPoint("CENTER", button, "LEFT", 5, 1)
        bottom:SetPoint("CENTER", button, "LEFT", 9, 1)
        top:SetRotation(-math.pi / 4)
        bottom:SetRotation(math.pi / 4)
    else
        top:SetPoint("CENTER", button, "LEFT", 6, 2)
        bottom:SetPoint("CENTER", button, "LEFT", 6, -2)
        top:SetRotation(math.pi / 4)
        bottom:SetRotation(-math.pi / 4)
    end
end

-- ---------------------------------------------------------------------------
-- Dates
--
-- The list column is narrow, so the rule is the one every mail client landed
-- on: today is a time, yesterday is a word, this year is a day and a month,
-- and anything older carries its year.
-- ---------------------------------------------------------------------------

local function DateText(stamp)
    if not stamp or stamp <= 0 then return "" end
    local now = time()
    local diff = now - stamp
    if diff < 60 then return "just now" end
    if diff < 3600 then
        local minutes = math.floor(diff / 60)
        return minutes .. (minutes == 1 and " min ago" or " mins ago")
    end
    local today, that = date("*t", now), date("*t", stamp)
    if today.year == that.year and today.yday == that.yday then
        return (date("%I:%M %p", stamp):gsub("^0", ""))
    end
    if diff < 172800 and (today.yday - that.yday == 1 or (today.year ~= that.year and that.yday > 300)) then
        return "Yesterday"
    end
    if today.year == that.year then
        return date("%d %b", stamp)
    end
    return date("%d %b %Y", stamp)
end

local function LongDate(stamp)
    if not stamp or stamp <= 0 then return "unknown" end
    return (date("%d %b %Y, %I:%M %p", stamp):gsub(", 0", ", "))
end

-- ---------------------------------------------------------------------------
-- Where you were standing
--
-- Every call here is optional. The map API moved between expansions and this
-- module refuses to be the reason a note cannot be written, so a missing
-- function costs a field and nothing else.
-- ---------------------------------------------------------------------------

local function CurrentContext()
    local context = {}
    context.who = UnitName and UnitName("player") or nil
    local _, class = UnitClass and UnitClass("player")
    context.class = class
    context.level = UnitLevel and UnitLevel("player") or nil
    context.zone = GetRealZoneText and GetRealZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or ""
    context.subzone = subzone ~= "" and subzone or nil
    if UnitExists and UnitExists("target") then
        context.target = UnitName("target")
    end
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
        local map = C_Map.GetBestMapForUnit("player")
        local position = map and C_Map.GetPlayerMapPosition(map, "player")
        if position and position.GetXY then
            local x, y = position:GetXY()
            if x and y and x > 0 and y > 0 then
                -- the map the coordinates are on: what makes a stamp a
                -- place you can be led back to
                context.x, context.y, context.map = x, y, map
            end
        end
    end
    return context
end

local function StampLine(context)
    context = context or CurrentContext()
    local pieces = {}
    if context.who then
        pieces[#pieces + 1] = context.who ..
            (context.level and (" (" .. context.level .. ")") or "")
    end
    local place = context.zone
    if place and context.subzone then place = context.subzone .. ", " .. place end
    if place then
        if context.x and context.y then
            place = string.format("%s %.1f, %.1f", place, context.x * 100, context.y * 100)
        end
        pieces[#pieces + 1] = place
    end
    if context.target then pieces[#pieces + 1] = "target: " .. context.target end
    pieces[#pieces + 1] = date("%d %b %Y, %H:%M")
    return "-- " .. table.concat(pieces, " | ")
end

-- Stamp a note: the line in the body, and where it was in the note's context
local function Stamp(id)
    local context = CurrentContext()
    S.AppendBody(id, StampLine(context))
    S.SetContext(id, context)
end

-- ---------------------------------------------------------------------------
-- Waypoint to this note (Commander Orders)
-- ---------------------------------------------------------------------------

local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.Add) == "function" then return api end
    return nil
end

local ORDERS_REASONS = {
    disabled = "Commander Orders is turned off (/corder to turn it on)",
    loading = "Commander Orders is still loading",
}

local function Place(loc)
    local place = loc.zone or "?"
    if loc.subzone and loc.subzone ~= loc.zone then place = loc.subzone .. ", " .. place end
    return string.format("%s %.1f, %.1f", place, loc.x * 100, loc.y * 100)
end

-- The /way line a note's location stands for: by map id when the stamp kept
-- one, by zone name for an old stamp
local function WayLine(loc, title)
    title = tostring(title or ""):gsub("[%c]+", " ")
    if loc.map then
        return string.format("/way #%d %.2f %.2f %s", loc.map, loc.x * 100, loc.y * 100, title)
    end
    return string.format("/way %s %.1f %.1f %s", loc.zone or "", loc.x * 100, loc.y * 100, title)
end

local function NoteWaypoint(note)
    local loc = note and S.Location(note)
    if not loc then
        print("Commander Notebook: this note has no stamp with a place in it")
        return false
    end
    local title = S.TitleFor(note)
    local line = WayLine(loc, title)
    local api = Orders()
    if not api then
        print("Commander Notebook: Commander Orders is not loaded; the spot is " .. line)
        return false
    end
    if loc.map then
        local uid, why = api.Add({
            map = loc.map, x = loc.x, y = loc.y, title = title,
            source = "Notebook", key = "note:" .. note.id, setArrow = true,
        })
        if not uid then
            print("Commander Notebook: no waypoint: " .. (ORDERS_REASONS[why] or tostring(why)))
            return false
        end
    else
        -- An old stamp knows its zone only by name: Orders' /way resolver
        -- reads it, and lists the candidates when the name is not one zone
        if not api.Import then
            print("Commander Notebook: no waypoint; the spot is " .. line)
            return false
        end
        local added, errors = api.Import(line, { source = "Notebook" })
        if not (added and added > 0) then
            local err = type(errors) == "table" and errors[1] or {}
            print("Commander Notebook: no waypoint for \"" .. (loc.zone or "?") .. "\": "
                .. (ORDERS_REASONS[err.message] or tostring(err.message or "the zone was not recognised")))
            for i, candidate in ipairs(type(err.candidates) == "table" and err.candidates or {}) do
                if i > 6 then break end
                print("  " .. tostring(candidate.line))
            end
            return false
        end
    end
    print("Commander Notebook: waypoint to " .. title .. " (" .. Place(loc) .. ")")
    return true
end

N.NoteWaypoint = NoteWaypoint

-- ---------------------------------------------------------------------------
-- Context menus
--
-- One hidden dropdown frame, re-initialised per use. UIDropDownMenu resolves
-- its child regions through _G[name..suffix], so the frame needs a real global
-- name -- the same constraint the shared settings dropdowns document.
-- ---------------------------------------------------------------------------

local menuFrame

local function ShowMenu(entries)
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "CommanderNotebookContextMenu", UIParent, "UIDropDownMenuTemplate")
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

-- ---------------------------------------------------------------------------
-- Saving
--
-- There is no save button, so this is the contract instead: the editor is the
-- truth for as long as it has focus, and Flush is the only thing that moves
-- that truth into the store. Everything that could lose it -- switching notes,
-- closing the window, hiding it, logging out -- calls Flush first.
-- ---------------------------------------------------------------------------

function Flush()
    if not (dirty and state.selected and Ready()) then
        dirty, saveAt = false, nil
        return false
    end
    local id = state.selected
    local changed = false
    if titleBox then changed = S.SetTitle(id, titleBox:GetText()) or changed end
    if body then changed = S.SetBody(id, body:GetText()) or changed end
    if tagBox then changed = S.SetTags(id, tagBox:GetText()) or changed end
    dirty, saveAt = false, nil
    if changed then
        -- Reordering the list under a cursor that is still in the text is the
        -- one thing a save must not do. The row's own text was already kept
        -- current in place; the re-sort waits for the writer to look away.
        if titleBox:HasFocus() or body:HasFocus() or tagBox:HasFocus() then
            listStale = true
        else
            RefreshList()
        end
        RefreshEditor(true)
    end
    return changed
end

local function MarkDirty()
    if loading then return end
    dirty = true
    saveAt = GetTime() + (tonumber(DB().AutoSaveDelay) or 1.0)
end

-- The selected row's title and snippet are rewritten in place on every
-- keystroke. It is what makes the list feel live without the row moving.
local function UpdateSelectedRow()
    if not state.selected then return end
    for _, row in ipairs(listRows) do
        if row:IsShown() and row.noteID == state.selected then
            local title = titleBox and titleBox:GetText() or ""
            title = title:gsub("^%s+", ""):gsub("%s+$", "")
            if title == "" then
                local first = S.PlainText(body and body:GetText() or ""):match("^%s*([^\r\n]+)")
                title = first and first:gsub("^%s+", ""):gsub("%s+$", "") or ""
                if title == "" then title = UNTITLED end
            end
            row.title:SetText(title)
            if row.snippet:IsShown() then
                row.snippet:SetText(S.Snippet({ body = body and body:GetText() or "" }, 90))
            end
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- The sidebar
-- ---------------------------------------------------------------------------

local function Collapsed(section)
    return DB()["Collapse" .. section] and true or false
end

local function ToggleSection(section)
    CommanderNotebookDB["Collapse" .. section] = not Collapsed(section)
    RefreshSidebar()
end

local function SelectSource(scope, key)
    Flush()
    state.scope, state.key = scope, key
    CommanderNotebookDB.LastScope, CommanderNotebookDB.LastKey = scope, key
    state.selected = nil
    RefreshSidebar()
    RefreshList()
    -- Opening a source selects its first note, the way the client did. An
    -- empty source clears the page rather than leaving the last note stranded
    -- in a list it is not in.
    if listEntries[1] then
        scrollToSelection = true
        SelectNote(listEntries[1].id)
    else
        LoadNote(nil)
    end
end

local function NotebookMenu(book)
    ShowMenu({
        { text = book.name, isTitle = true },
        { text = "Rename Notebook...", func = function()
            StaticPopup_Show("COMMANDER_NOTEBOOK_RENAMEBOOK", book.name, nil, book.id)
        end },
        { text = "New Note Here", func = function()
            SelectSource("notebook", book.id)
            N.NewNote(book.id)
        end },
        { text = "Delete Notebook...", disabled = book.builtin, func = function()
            StaticPopup_Show("COMMANDER_NOTEBOOK_DELETEBOOK", book.name, nil, book.id)
        end },
    })
end

local function TagMenu(tag)
    ShowMenu({
        { text = tag.name, isTitle = true },
        { text = "Rename Tag...", func = function()
            StaticPopup_Show("COMMANDER_NOTEBOOK_RENAMETAG", tag.name, nil, tag.name)
        end },
        { text = "Remove Tag From Every Note", func = function()
            local touched = S.DeleteTag(tag.name)
            if state.scope == "tag" and state.key == tag.name then
                SelectSource("all")
            else
                RefreshAll()
            end
            print(string.format("Commander Notebook: removed \"%s\" from %d note%s.",
                tag.name, touched, touched == 1 and "" or "s"))
        end },
    })
end

local function BuildSideRow(index)
    if sideRows[index] then return sideRows[index] end
    local row = CreateFrame("Button", nil, sidebarChild)
    row:SetHeight(SIDE_ROW_H)
    row:SetPoint("LEFT", sidebarChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", sidebarChild, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = Quad(row, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.bar = Quad(row, "ARTWORK")
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.bar:Hide()

    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.label:SetJustifyH("LEFT")

    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.count:SetJustifyH("RIGHT")

    row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
    NoWrap(row.label)

    row:SetScript("OnEnter", function(self)
        if not self.selected then
            local skin = Skin()
            local r, g, b = Accent()
            self.highlight:SetColorTexture(r, g, b, skin.hover)
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
            ToggleSection(entry.section)
            return
        end
        if button == "RightButton" then
            if entry.kind == "notebook" then NotebookMenu(entry.book) return end
            if entry.kind == "tag" then TagMenu(entry.tag) return end
        end
        SelectSource(entry.scope, entry.key)
    end)

    sideRows[index] = row
    return row
end

function RefreshSidebar()
    if not sidebarChild then return end
    local skin = Skin()
    local r, g, b = Accent()

    sideEntries = {}
    local function Add(entry) sideEntries[#sideEntries + 1] = entry end

    Add({ kind = "scope", scope = "all", label = "All Notes",
        count = S.Count({ scope = "all" }) })
    local pinned = S.Count({ scope = "pinned" })
    if pinned > 0 then
        Add({ kind = "scope", scope = "pinned", label = "Pinned", count = pinned })
    end

    Add({ kind = "header", label = "NOTEBOOKS", section = "Books" })
    if not Collapsed("Books") then
        for _, book in ipairs(S.Notebooks()) do
            Add({ kind = "notebook", scope = "notebook", key = book.id,
                label = book.name, count = book.count, book = book })
        end
    end

    local tags = S.Tags()
    Add({ kind = "header", label = "TAGS", section = "Tags" })
    if not Collapsed("Tags") then
        if #tags == 0 then
            Add({ kind = "note", label = "no tags yet", count = "" })
        end
        for _, tag in ipairs(tags) do
            Add({ kind = "tag", scope = "tag", key = tag.name,
                label = tag.name, count = tag.count, tag = tag })
        end
        local untagged = S.Count({ scope = "untagged" })
        if untagged > 0 then
            Add({ kind = "scope", scope = "untagged", label = "Untagged", count = untagged })
        end
    end

    Add({ kind = "spacer" })
    Add({ kind = "scope", scope = "trash", label = "Trash", count = S.TrashCount() })

    local offset = 0
    for index, entry in ipairs(sideEntries) do
        local row = BuildSideRow(index)
        row.entry = entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", sidebarChild, "TOPLEFT", 0, -offset)
        row:SetPoint("TOPRIGHT", sidebarChild, "TOPRIGHT", 0, -offset)

        if entry.kind == "spacer" then
            row:SetHeight(8)
            row.label:SetText("")
            row.count:SetText("")
            row.highlight:Hide()
            row.bar:Hide()
            row:EnableMouse(false)
            if row.chevron then
                row.chevron[1]:Hide()
                row.chevron[2]:Hide()
            end
        elseif entry.kind == "header" then
            row:SetHeight(SIDE_HEADER_H)
            row:EnableMouse(true)
            row.label:SetText(entry.label)
            row.label:SetTextColor(skin.header[1], skin.header[2], skin.header[3])
            row.count:SetText("")
            row.highlight:Hide()
            row.bar:Hide()
            PointChevron(row, not Collapsed(entry.section))
            row.chevron[1]:Show()
            row.chevron[2]:Show()
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", 16, 0)
            row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
        else
            row:SetHeight(SIDE_ROW_H)
            row:EnableMouse(entry.kind ~= "note")
            row.label:SetText(entry.label)
            row.count:SetText(entry.count ~= "" and tostring(entry.count) or "")
            if row.chevron then
                row.chevron[1]:Hide()
                row.chevron[2]:Hide()
            end
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", row, "LEFT", entry.kind == "scope" and 8 or 16, 0)
            row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)

            local selected = (entry.scope == state.scope) and (entry.key == state.key)
            row.selected = selected
            if selected then
                row.highlight:SetColorTexture(r, g, b, skin.selection)
                row.highlight:Show()
                row.bar:SetColorTexture(r, g, b, 1)
                row.bar:Show()
                Ink(row.label, "ink")
            else
                row.highlight:Hide()
                row.bar:Hide()
                Ink(row.label, entry.kind == "note" and "inkFaint" or "inkDim")
            end
            Ink(row.count, "inkFaint")
        end
        row:Show()
        offset = offset + row:GetHeight()
    end

    for index = #sideEntries + 1, #sideRows do
        sideRows[index]:Hide()
    end
    sidebarChild:SetHeight(math.max(offset, 1))
end

-- ---------------------------------------------------------------------------
-- The note list
-- ---------------------------------------------------------------------------

local function RowHeight()
    local height = 20
    if DB().ShowSnippets ~= false then height = height + 13 end
    if DB().ShowListTags ~= false then height = height + 11 end
    return height + 6
end

local function NoteMenu(note)
    local books = {}
    for _, book in ipairs(S.Notebooks()) do
        if book.id ~= note.notebook then
            books[#books + 1] = { text = "  " .. book.name, func = function()
                S.SetNotebook(note.id, book.id)
                RefreshAll()
            end }
        end
    end
    local entries = {
        { text = S.TitleFor(note), isTitle = true },
        { text = note.pinned and "Unpin" or "Pin To Top", func = function()
            S.TogglePin(note.id)
            RefreshAll()
        end },
    }
    if S.Location(note) then
        entries[#entries + 1] = { text = "Waypoint To This Note", func = function() NoteWaypoint(note) end }
    end
    local more = {
        { text = "Duplicate", func = function()
            local copy = S.Duplicate(note.id)
            RefreshAll()
            if copy then SelectNote(copy.id) end
        end },
    }
    for _, entry in ipairs(more) do entries[#entries + 1] = entry end
    if #books > 0 then
        entries[#entries + 1] = { text = "Move To Notebook", isTitle = true }
        for _, book in ipairs(books) do entries[#entries + 1] = book end
    end
    entries[#entries + 1] = { text = "Move To Trash", func = function()
        S.Trash(note.id)
        RefreshAll()
        SelectSource(state.scope, state.key)
    end }
    ShowMenu(entries)
end

local function TrashMenu(note)
    ShowMenu({
        { text = S.TitleFor(note), isTitle = true },
        { text = "Restore", func = function()
            S.Restore(note.id)
            RefreshAll()
            SelectSource(state.scope, state.key)
        end },
        { text = "Delete Forever...", func = function()
            if DB().ConfirmDestroy == false then
                S.Destroy(note.id)
                RefreshAll()
                SelectSource(state.scope, state.key)
            else
                StaticPopup_Show("COMMANDER_NOTEBOOK_DESTROY", S.TitleFor(note), nil, note.id)
            end
        end },
    })
end

local function BuildListRow(index)
    if listRows[index] then return listRows[index] end
    local row = CreateFrame("Button", nil, listChild)
    row:SetPoint("LEFT", listChild, "LEFT", 0, 0)
    row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.highlight = Quad(row, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:Hide()

    row.bar = Quad(row, "ARTWORK")
    row.bar:SetWidth(3)
    row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    row.bar:Hide()

    row.separator = Rule(row)
    row.separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 6, 0)
    row.separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -6, 0)

    row.date = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.date:SetPoint("TOPRIGHT", row, "TOPRIGHT", -7, -4)
    row.date:SetJustifyH("RIGHT")

    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 9, -4)
    row.title:SetPoint("RIGHT", row.date, "LEFT", -6, 0)
    row.title:SetJustifyH("LEFT")
    NoWrap(row.title)

    row.snippet = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.snippet:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.snippet:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    row.snippet:SetJustifyH("LEFT")
    NoWrap(row.snippet)

    row.tags = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.tags:SetPoint("TOPLEFT", row.snippet, "BOTTOMLEFT", 0, -1)
    row.tags:SetPoint("RIGHT", row, "RIGHT", -7, 0)
    row.tags:SetJustifyH("LEFT")
    NoWrap(row.tags)

    PlacePin(row, -6, -8)

    row:SetScript("OnEnter", function(self)
        if not self.selected then
            local skin = Skin()
            local r, g, b = Accent()
            self.highlight:SetColorTexture(r, g, b, skin.hover)
            self.highlight:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if not self.selected then self.highlight:Hide() end
    end)
    row:SetScript("OnClick", function(self, button)
        local note = self.noteID and S.Note(self.noteID)
        if not note then return end
        if button == "RightButton" then
            if note.trashed then TrashMenu(note) else NoteMenu(note) end
            return
        end
        SelectNote(note.id)
    end)

    listRows[index] = row
    return row
end

function RefreshList()
    if not listChild then return end
    listStale = false
    local skin = Skin()
    local r, g, b = Accent()
    local showSnippet = DB().ShowSnippets ~= false
    local showTags = DB().ShowListTags ~= false
    local height = RowHeight()

    listEntries = S.List({
        scope = state.scope,
        key = state.key,
        search = state.search,
        sort = state.sort,
        pinFirst = DB().PinFirst ~= false,
    })

    local offset, selectedOffset = 0, nil
    for index, note in ipairs(listEntries) do
        local row = BuildListRow(index)
        row.noteID = note.id
        row:SetHeight(height)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", listChild, "TOPLEFT", 0, -offset)
        row:SetPoint("TOPRIGHT", listChild, "TOPRIGHT", 0, -offset)

        row.title:SetText(S.TitleFor(note))
        row.date:SetText(DateText(note.trashed or note.updated))
        row.snippet:SetShown(showSnippet)
        if showSnippet then row.snippet:SetText(S.Snippet(note, 90)) end
        row.tags:SetShown(showTags)
        if showTags then
            local label = ""
            if #note.tags > 0 then label = table.concat(note.tags, "  ") end
            local links = S.LinkCount(note)
            if links > 0 then
                label = (label ~= "" and (label .. "   ") or "") ..
                    links .. (links == 1 and " link" or " links")
            end
            row.tags:SetText(label)
        end
        ShowPin(row, note.pinned and true or false)

        local selected = (note.id == state.selected)
        row.selected = selected
        if selected then
            selectedOffset = offset
            row.highlight:SetColorTexture(r, g, b, skin.selection)
            row.highlight:Show()
            row.bar:SetColorTexture(r, g, b, 1)
            row.bar:Show()
        else
            row.highlight:Hide()
            row.bar:Hide()
        end
        Ink(row.title, "ink")
        Ink(row.date, "inkFaint")
        Ink(row.snippet, "inkDim")
        Ink(row.tags, "inkFaint")
        row.separator:SetColorTexture(skin.rule[1], skin.rule[2], skin.rule[3], skin.rule[4])
        row:Show()
        offset = offset + height
    end

    for index = #listEntries + 1, #listRows do
        listRows[index]:Hide()
    end
    listChild:SetHeight(math.max(offset, 1))

    -- Bring the selected note into view, but only when the selection moved.
    -- Doing it on every refresh would yank the list while someone is reading
    -- it, because typing refreshes the list too.
    if scrollToSelection and selectedOffset and listScroll then
        scrollToSelection = false
        local visible = listScroll:GetHeight() or 0
        local range = listScroll:GetVerticalScrollRange() or 0
        local top = listScroll:GetVerticalScroll() or 0
        if selectedOffset < top then
            listScroll:SetVerticalScroll(math.max(selectedOffset, 0))
        elseif selectedOffset + height > top + visible then
            listScroll:SetVerticalScroll(math.min(selectedOffset + height - visible, range))
        end
    end

    if frame and frame.trashButton then
        frame.trashButton:SetShown(state.scope == "trash")
    end
    if frame and frame.listCount then
        local total = #listEntries
        frame.listCount:SetText(total .. (total == 1 and " note" or " notes"))
        Ink(frame.listCount, "inkFaint")
    end
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------

-- A multi-line EditBox used as a ScrollChild sizes its own height to its text,
-- but only if its WIDTH is pinned -- an unpinned one lays out on one endless
-- line and the scrollbar never appears. Commander_Debug and the Quartermaster
-- both ship this same pattern against this client, so the width is set here
-- and the height is deliberately never touched.
local function SyncBodyWidth()
    if not (body and bodyScroll) then return end
    local width = bodyScroll:GetWidth()
    if width and width > 0 then
        body:SetWidth(width - 4)
    end
end

local function ScrollToCursor(_, _, cursorY, _, cursorHeight)
    if not bodyScroll then return end
    local top = -(cursorY or 0)
    local bottom = top + (cursorHeight or 14)
    local scroll = bodyScroll:GetVerticalScroll()
    local visible = bodyScroll:GetHeight()
    local range = bodyScroll:GetVerticalScrollRange()
    if top < scroll then
        bodyScroll:SetVerticalScroll(math.max(top - 4, 0))
    elseif bottom > scroll + visible then
        bodyScroll:SetVerticalScroll(math.min(bottom - visible + 4, range))
    end
end

local function RefreshAttachments()
    if not attachStrip then return end
    local note = state.selected and S.Note(state.selected)
    local links = (DB().ShowAttachments ~= false) and note and S.Links(note) or {}
    local previous
    for index, link in ipairs(links) do
        local button = attachButtons[index]
        if not button then
            button = CreateFrame("Button", nil, attachStrip)
            button:SetHeight(18)
            button.bg = Quad(button, "BACKGROUND")
            button.bg:SetAllPoints()
            button.label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            button.label:SetPoint("LEFT", button, "LEFT", 5, 0)
            button.label:SetPoint("RIGHT", button, "RIGHT", -5, 0)
            NoWrap(button.label)
            button:SetScript("OnEnter", function(self)
                if not self.payload then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
                -- SetHyperlink is given the payload the note stored, which is
                -- why the store keeps it verbatim rather than prettied up.
                local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.payload)
                if not ok then
                    GameTooltip:SetText(self.label:GetText() or "")
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button:SetScript("OnClick", function(self)
                if not self.payload then return end
                -- The client's own handler: shift-click puts it in chat, a
                -- plain click does whatever that link type does.
                if SetItemRef then
                    SetItemRef(self.payload,
                        "|H" .. self.payload .. "|h[" .. (self.linkLabel or "link") .. "]|h",
                        "LeftButton")
                end
            end)
            attachButtons[index] = button
        end
        button.payload = link.payload
        button.linkLabel = link.label
        button.label:SetText(link.label)
        local width = math.min(math.max(button.label:GetStringWidth() + 14, 40), 150)
        button:SetWidth(width)
        button:ClearAllPoints()
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("LEFT", attachStrip, "LEFT", 0, 0)
        end
        local r, g, b = Accent()
        button.bg:SetColorTexture(r, g, b, Skin().hover + 0.06)
        Ink(button.label, "inkDim")
        button:Show()
        previous = button
    end
    for index = #links + 1, #attachButtons do
        attachButtons[index]:Hide()
    end

    -- A hidden frame keeps its layout slot, so hiding the strip on its own
    -- would leave its height as dead space at the bottom of every note that
    -- has no links in it. The page reclaims the room instead.
    local shown = #links > 0
    attachStrip:SetShown(shown)
    bodyScroll:SetPoint("BOTTOM", shown and attachStrip or actionRow, "TOP", 0, 4)
end

function LoadNote(id)
    local note = id and S.Note(id)
    state.selected = note and note.id or nil
    CommanderNotebookDB.LastNote = state.selected

    loading = true
    if note then
        titleBox:SetText(note.title or "")
        titleBox:SetCursorPosition(0)
        tagBox:SetText(S.TagString(note))
        tagBox:SetCursorPosition(0)
        body:SetText(note.body or "")
        body:SetCursorPosition(0)
    else
        titleBox:SetText("")
        tagBox:SetText("")
        body:SetText("")
    end
    loading = false
    dirty, saveAt = false, nil

    bodyScroll:SetVerticalScroll(0)
    SyncBodyWidth()
    RefreshEditor(true)
end

function SelectNote(id)
    if state.selected == id then return end
    Flush()
    LoadNote(id)
    scrollToSelection = true
    RefreshList()
end

function RefreshEditor(keepText)
    if not frame then return end
    local note = state.selected and S.Note(state.selected)
    local hasNote = note ~= nil
    local trashed = hasNote and note.trashed ~= nil

    titleBox:SetShown(hasNote)
    tagBox:SetShown(hasNote and not trashed)
    frame.tagLabel:SetShown(hasNote and not trashed)
    bodyScroll:SetShown(hasNote)
    frame.emptyText:SetShown(not hasNote)
    frame.editRule:SetShown(hasNote)

    if not hasNote then
        infoText:SetText("")
        attachStrip:Hide()
        for _, button in ipairs(actionRow.buttons) do button:Hide() end
        frame.emptyText:SetText(state.scope == "trash"
            and "The trash is empty."
            or "No note selected.\n\nPick one from the list, or press New Note.")
        Ink(frame.emptyText, "inkFaint")
        return
    end

    -- Read-only in the trash: a note you have deleted is a record of what you
    -- wrote, and typing into it would quietly resurrect an edit you cannot see
    -- from any list.
    SetBoxEnabled(titleBox, not trashed)
    SetBoxEnabled(body, not trashed)

    if DB().ShowNoteInfo ~= false then
        local words = S.WordCount(note)
        local pieces = { S.NotebookName(note.notebook) }
        if trashed then
            pieces[#pieces + 1] = "in the trash since " .. DateText(note.trashed)
        else
            pieces[#pieces + 1] = "created " .. DateText(note.created)
            pieces[#pieces + 1] = "edited " .. DateText(note.updated)
        end
        pieces[#pieces + 1] = words .. (words == 1 and " word" or " words")
        infoText:SetText(table.concat(pieces, "  ·  "))
    else
        infoText:SetText("")
    end
    Ink(infoText, "inkFaint")

    -- A repaint must never overwrite keystrokes that have not been written
    -- yet. RefreshAll runs from menu actions -- pinning, moving, duplicating --
    -- and a click on a dropdown does not take focus off the editor, so without
    -- this guard pinning a note mid-sentence would silently roll the sentence
    -- back to whatever the store last saw.
    if not keepText and not dirty then
        loading = true
        titleBox:SetText(note.title or "")
        tagBox:SetText(S.TagString(note))
        body:SetText(note.body or "")
        loading = false
    end

    RefreshAttachments()

    -- The action row is rebuilt per note because the trash offers two
    -- different verbs and nothing else.
    local specs
    if trashed then
        specs = {
            { label = "Restore", width = 90, onClick = function()
                S.Restore(note.id)
                RefreshAll()
                SelectSource(state.scope, state.key)
            end },
            { label = "Delete Forever", width = 120, onClick = function()
                if DB().ConfirmDestroy == false then
                    S.Destroy(note.id)
                    RefreshAll()
                    SelectSource(state.scope, state.key)
                else
                    StaticPopup_Show("COMMANDER_NOTEBOOK_DESTROY", S.TitleFor(note), nil, note.id)
                end
            end },
        }
    else
        specs = {
            { label = note.pinned and "Unpin" or "Pin", width = 62, onClick = function()
                S.TogglePin(note.id)
                RefreshAll()
            end },
            { label = "Stamp", width = 70, tooltip =
                "Add a line saying who you are, where you are standing and what time it is.",
                onClick = function()
                    Flush()
                    Stamp(note.id)
                    LoadNote(note.id)
                    RefreshList()
                end },
            { label = "Duplicate", width = 84, onClick = function()
                Flush()
                local copy = S.Duplicate(note.id)
                RefreshAll()
                if copy then SelectNote(copy.id) end
            end },
            { label = "Move To...", width = 90, onClick = function()
                NoteMenu(note)
            end },
            { label = "Delete", width = 74, onClick = function()
                Flush()
                S.Trash(note.id)
                RefreshAll()
                SelectSource(state.scope, state.key)
            end },
        }
        -- Only for a note that has somewhere to go, right after Stamp. The
        -- row has room for one short verb (456 px less 400 used), and Go is
        -- the suite's word for a waypoint button.
        local loc = S.Location(note)
        if loc then
            table.insert(specs, 3, { label = "Go", width = 44, tooltip =
                "Waypoint to where this note was stamped: " .. Place(loc)
                .. ". The arrow is Commander Orders'; without it the spot is printed as a /way line.",
                onClick = function()
                    Flush()
                    NoteWaypoint(S.Note(note.id) or note)
                end })
        end
    end

    for index, spec in ipairs(specs) do
        local button = actionRow.buttons[index]
        if not button then
            button = CreateFrame("Button", nil, actionRow, "UIPanelButtonTemplate")
            button:SetHeight(21)
            actionRow.buttons[index] = button
        end
        button:SetText(spec.label)
        button:SetWidth(spec.width)
        button:ClearAllPoints()
        if index == 1 then
            button:SetPoint("LEFT", actionRow, "LEFT", 0, 0)
        else
            button:SetPoint("LEFT", actionRow.buttons[index - 1], "RIGHT", 5, 0)
        end
        button:SetScript("OnClick", spec.onClick)
        button:SetScript("OnEnter", spec.tooltip and function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(spec.label, 1, 1, 1)
            GameTooltip:AddLine(spec.tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end or nil)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:Show()
    end
    for index = #specs + 1, #actionRow.buttons do
        actionRow.buttons[index]:Hide()
    end
end

function RefreshAll()
    if not frame then return end
    RefreshSidebar()
    RefreshList()
    RefreshEditor()
end

N.RefreshAll = RefreshAll

-- ---------------------------------------------------------------------------
-- Popups
--
-- The four operations that need a word or a confirmation before they run.
-- Naming a notebook is a StaticPopup with an edit box because that is the
-- client's own answer to "type something", and it survives being opened from
-- a dropdown, which a custom frame parented to the menu would not.
-- ---------------------------------------------------------------------------

-- FrameXML owns this table. We add keys to it and NEVER assign the global:
-- assigning it from addon code taints the global itself, and every later read
-- by secure code -- the game menu's own confirmations among them -- inherits
-- that taint and starts refusing protected calls. That is what
-- ADDON_ACTION_FORBIDDEN 'callback()' out of GameMenuFrame was.
StaticPopupDialogs["COMMANDER_NOTEBOOK_NEWBOOK"] = {
    text = "Name the new notebook:",
    button1 = "Create", button2 = "Cancel",
    hasEditBox = true, maxLetters = 40,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        if box then
            box:SetText("")
            box:SetFocus()
        end
    end,
    OnAccept = function(self)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        local id, err = S.CreateNotebook(box and box:GetText() or "")
        if not id then
            print("Commander Notebook: " .. (err or "could not create that notebook."))
            return
        end
        N.SelectSource("notebook", id)
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["COMMANDER_NOTEBOOK_NEWBOOK"].OnAccept(parent)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["COMMANDER_NOTEBOOK_RENAMEBOOK"] = {
    text = "Rename \"%s\" to:",
    button1 = "Rename", button2 = "Cancel",
    hasEditBox = true, maxLetters = 40,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        if box then
            box:SetText(S.NotebookName(data))
            box:HighlightText()
            box:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        local ok, err = S.RenameNotebook(data, box and box:GetText() or "")
        if not ok then print("Commander Notebook: " .. (err or "could not rename that notebook.")) end
        N.RefreshAll()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["COMMANDER_NOTEBOOK_RENAMEBOOK"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["COMMANDER_NOTEBOOK_RENAMETAG"] = {
    text = "Rename the tag \"%s\" to:",
    button1 = "Rename", button2 = "Cancel",
    hasEditBox = true, maxLetters = 40,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        if box then
            box:SetText(data or "")
            box:HighlightText()
            box:SetFocus()
        end
    end,
    OnAccept = function(self, data)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        local newName = box and box:GetText() or ""
        local touched = S.RenameTag(data, newName)
        N.SelectSource("tag", (newName:gsub("^%s+", ""):gsub("%s+$", "")):lower())
        print(string.format("Commander Notebook: retagged %d note%s.", touched, touched == 1 and "" or "s"))
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        StaticPopupDialogs["COMMANDER_NOTEBOOK_RENAMETAG"].OnAccept(parent, parent.data)
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["COMMANDER_NOTEBOOK_DELETEBOOK"] = {
    -- Deliberately explicit that the notes survive: the fear this dialog has
    -- to answer is "am I about to lose everything I wrote in here".
    text = "Delete the notebook \"%s\"?\n\nIts notes are not deleted. They move to Field Notes.",
    button1 = "Delete Notebook", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, data)
        local ok, moved = S.DeleteNotebook(data)
        if ok then
            print(string.format("Commander Notebook: notebook deleted, %d note%s moved to Field Notes.",
                moved or 0, (moved == 1) and "" or "s"))
        end
        N.SelectSource("all")
    end,
}

StaticPopupDialogs["COMMANDER_NOTEBOOK_DESTROY"] = {
    text = "Delete \"%s\" for good?\n\nThis cannot be undone.",
    button1 = "Delete Forever", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function(_, data)
        S.Destroy(data)
        N.SelectSource("trash")
    end,
}

StaticPopupDialogs["COMMANDER_NOTEBOOK_EMPTYTRASH"] = {
    text = "Empty the trash?\n\n%s will be deleted for good. This cannot be undone.",
    button1 = "Empty Trash", button2 = "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnAccept = function()
        local removed = S.EmptyTrash()
        print(string.format("Commander Notebook: deleted %d note%s.", removed, removed == 1 and "" or "s"))
        N.SelectSource("trash")
    end,
}

-- ---------------------------------------------------------------------------
-- Framing
-- ---------------------------------------------------------------------------

local PARCHMENT_BACKDROP = {
    bgFile = "Interface\\QuestFrame\\QuestBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 256, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

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
    CommanderNotebookDB.FramePos = { point = point, x = x * scale, y = y * scale }
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

local function EnsureParchment()
    if frame.parchment then return frame.parchment end
    local art = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    art:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
    if art.SetBackdrop then
        art:SetBackdrop(PARCHMENT_BACKDROP)
        art:SetBackdropColor(1, 1, 1, 1)
        art:SetBackdropBorderColor(1, 1, 1, 1)
    end
    frame.parchment = art

    -- The paper itself is DRAWN, not borrowed.
    --
    -- A backdrop whose bgFile fails to resolve still draws its EDGE and paints
    -- no background at all -- which is exactly what this window was doing. It
    -- went unnoticed for as long as the template's own Bg sat on top of the
    -- parchment; the moment the dressing was correctly hidden, the window
    -- became a hole in the screen with the world showing through it.
    --
    -- So the fill is a tinted quad cut from WHITE8X8, which is the one texture
    -- this suite treats as always present (Bags and Meters document why art
    -- FILES are not). The backdrop above still gets to draw its parchment over
    -- this if it resolves; if it does not, the window is still a window.
    local base = art:CreateTexture(nil, "BACKGROUND", nil, -8)
    base:SetColorTexture(0.83, 0.72, 0.53, 1)
    base:SetPoint("TOPLEFT", art, "TOPLEFT", 10, -10)
    base:SetPoint("BOTTOMRIGHT", art, "BOTTOMRIGHT", -10, 10)
    frame.paperBase = base

    local plate = art:CreateTexture(nil, "ARTWORK")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(256, 64)
    plate:SetPoint("TOP", frame, "TOP", 0, 12)
    frame.headerPlate = plate

    local title = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", plate, "TOP", 0, -14)
    title:SetText("Notebook")
    frame.plateTitle = title
    return art
end

function ApplyStyle()
    if not frame then return end
    local skin = Skin()
    local parchment = (DB().FrameStyle or "PARCHMENT") == "PARCHMENT"

    -- The template's own dressing steps aside for the parchment -- ALL of it.
    -- This used to be four guessed names and three of them do not exist on
    -- this client, so the steel frame never went away and the parchment stayed
    -- stranded behind it. The verified list lives in the shared framework now
    -- (Commander.UI.TEMPLATE_REGIONS) because three windows had the same bug.
    Commander.UI.SetTemplateDressing(frame, not parchment)

    if parchment then
        EnsureParchment()
        frame.parchment:Show()
        frame.headerPlate:Show()
        frame.plateTitle:Show()
    elseif frame.parchment then
        frame.parchment:Hide()
        frame.headerPlate:Hide()
        frame.plateTitle:Hide()
    end
    if Commander.UI and Commander.UI.ApplyStyleBackdrop then
        Commander.UI.ApplyStyleBackdrop(frame, parchment and "NONE" or "DARK")
    end

    for _, pane in ipairs(frame.panes or {}) do
        if pane.SetBackdropColor then
            pane:SetBackdropColor(skin.pane[1], skin.pane[2], skin.pane[3], skin.pane[4])
            pane:SetBackdropBorderColor(skin.paneEdge[1], skin.paneEdge[2],
                skin.paneEdge[3], skin.paneEdge[4])
        end
    end

    frame:SetScale(tonumber(DB().FrameScale) or 1)
    frame.sidebarPane:SetShown(DB().ShowSidebar ~= false)
    frame.listPane:ClearAllPoints()
    if DB().ShowSidebar ~= false then
        frame.listPane:SetPoint("TOPLEFT", frame.sidebarPane, "TOPRIGHT", 6, 0)
    else
        frame.listPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -62)
    end
    frame.listPane:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD)
    frame.listPane:SetWidth(LIST_W)

    local fontObject = _G[BodyFont()] or GameFontHighlight
    body:SetFontObject(fontObject)
    local ink = skin.ink
    body:SetTextColor(ink[1], ink[2], ink[3])
    titleBox:SetTextColor(ink[1], ink[2], ink[3])
    tagBox:SetTextColor(skin.inkDim[1], skin.inkDim[2], skin.inkDim[3])
    Ink(frame.tagLabel, "inkFaint")
    Ink(frame.searchHint, "inkFaint")
    frame.searchBox:SetTextColor(ink[1], ink[2], ink[3])

    for _, rule in ipairs(frame.rules or {}) do
        rule:SetColorTexture(skin.rule[1], skin.rule[2], skin.rule[3], skin.rule[4])
    end
    SyncBodyWidth()
end

N.ApplyStyle = ApplyStyle

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

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "CommanderNotebookFrame", UIParent, "BasicFrameTemplateWithInset")
    frame.panes, frame.rules = {}, {}
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Notebook") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderNotebookFrame") end

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

    -- ----- toolbar -------------------------------------------------------
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -30)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -30)
    toolbar:SetHeight(TOOLBAR_H)

    local newNote = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    newNote:SetSize(96, 22)
    newNote:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    newNote:SetText("New Note")
    newNote:SetScript("OnClick", function() N.NewNote() end)

    local newBook = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    newBook:SetSize(104, 22)
    newBook:SetPoint("LEFT", newNote, "RIGHT", 5, 0)
    newBook:SetText("New Notebook")
    newBook:SetScript("OnClick", function() StaticPopup_Show("COMMANDER_NOTEBOOK_NEWBOOK") end)

    frame.trashButton = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.trashButton:SetSize(100, 22)
    frame.trashButton:SetPoint("LEFT", newBook, "RIGHT", 5, 0)
    frame.trashButton:SetText("Empty Trash")
    frame.trashButton:SetScript("OnClick", function()
        local count = S.TrashCount()
        if count == 0 then
            print("Commander Notebook: the trash is already empty.")
            return
        end
        StaticPopup_Show("COMMANDER_NOTEBOOK_EMPTYTRASH",
            count .. (count == 1 and " note" or " notes"))
    end)

    local searchBox = CreateFrame("EditBox", "CommanderNotebookSearchBox", toolbar, "InputBoxTemplate")
    searchBox:SetSize(196, 20)
    searchBox:SetPoint("RIGHT", toolbar, "RIGHT", -4, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(120)
    frame.searchBox = searchBox

    local searchHint = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
    searchHint:SetText("Search notes")
    frame.searchHint = searchHint

    searchBox:SetScript("OnTextChanged", function(self)
        state.search = self:GetText() or ""
        searchHint:SetShown(state.search == "" and not self:HasFocus())
        RefreshList()
        -- Searching never leaves the page showing a note the list no longer
        -- offers: the first hit opens, and no hits clears the page.
        local first = listEntries[1]
        if first then
            if state.selected ~= first.id then
                local stillListed = false
                for _, note in ipairs(listEntries) do
                    if note.id == state.selected then stillListed = true break end
                end
                if not stillListed then SelectNote(first.id) end
            end
        elseif state.selected then
            Flush()
            LoadNote(nil)
        end
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

    local sortDrop = CreateFrame("Frame", "CommanderNotebookSortDrop", toolbar, "UIDropDownMenuTemplate")
    sortDrop:SetPoint("RIGHT", searchBox, "LEFT", -14, -2)
    UIDropDownMenu_SetWidth(sortDrop, 96)
    local SORTS = {
        { text = "Date Updated", value = "updated" },
        { text = "Date Created", value = "created" },
        { text = "Title", value = "title" },
        { text = "Notebook", value = "notebook" },
    }
    local function SortText(value)
        for _, option in ipairs(SORTS) do
            if option.value == value then return option.text end
        end
        return "Date Updated"
    end
    UIDropDownMenu_Initialize(sortDrop, function()
        for _, option in ipairs(SORTS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.text
            info.value = option.value
            info.checked = (option.value == state.sort)
            info.func = function(button)
                state.sort = button.value
                UIDropDownMenu_SetSelectedValue(sortDrop, button.value)
                UIDropDownMenu_SetText(sortDrop, SortText(button.value))
                RefreshList()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    frame.sortDrop = sortDrop
    frame.SetSortText = function(value)
        UIDropDownMenu_SetSelectedValue(sortDrop, value)
        UIDropDownMenu_SetText(sortDrop, SortText(value))
    end

    -- ----- sidebar -------------------------------------------------------
    local sidebarPane = MakePane(frame)
    sidebarPane:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -62)
    sidebarPane:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD)
    sidebarPane:SetWidth(SIDEBAR_W)
    frame.sidebarPane = sidebarPane

    sidebarScroll = CreateFrame("ScrollFrame", "CommanderNotebookSidebarScroll", sidebarPane,
        "UIPanelScrollFrameTemplate")
    sidebarScroll:SetPoint("TOPLEFT", sidebarPane, "TOPLEFT", 6, -6)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebarPane, "BOTTOMRIGHT", -14, 6)
    WheelScroll(sidebarScroll, 24)
    sidebarChild = CreateFrame("Frame", nil, sidebarScroll)
    sidebarChild:SetSize(SIDEBAR_W - 30, 1)
    sidebarScroll:SetScrollChild(sidebarChild)
    sidebarScroll:SetScript("OnSizeChanged", function(_, width)
        sidebarChild:SetWidth(width)
    end)

    -- ----- note list -----------------------------------------------------
    local listPane = MakePane(frame)
    listPane:SetPoint("TOPLEFT", sidebarPane, "TOPRIGHT", 6, 0)
    listPane:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD)
    listPane:SetWidth(LIST_W)
    frame.listPane = listPane

    frame.listCount = listPane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.listCount:SetPoint("TOPLEFT", listPane, "TOPLEFT", 9, -7)
    frame.listCount:SetJustifyH("LEFT")

    local listRule = Rule(listPane)
    listRule:SetPoint("TOPLEFT", listPane, "TOPLEFT", 6, -21)
    listRule:SetPoint("TOPRIGHT", listPane, "TOPRIGHT", -6, -21)
    frame.rules[#frame.rules + 1] = listRule

    listScroll = CreateFrame("ScrollFrame", "CommanderNotebookListScroll", listPane,
        "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", listPane, "TOPLEFT", 4, -24)
    listScroll:SetPoint("BOTTOMRIGHT", listPane, "BOTTOMRIGHT", -14, 6)
    WheelScroll(listScroll, 40)
    listChild = CreateFrame("Frame", nil, listScroll)
    listChild:SetSize(LIST_W - 28, 1)
    listScroll:SetScrollChild(listChild)
    listScroll:SetScript("OnSizeChanged", function(_, width)
        listChild:SetWidth(width)
    end)

    -- ----- the page ------------------------------------------------------
    local page = MakePane(frame)
    page:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 6, 0)
    page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    frame.page = page

    titleBox = CreateFrame("EditBox", "CommanderNotebookTitleBox", page)
    titleBox:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -8)
    titleBox:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, -8)
    titleBox:SetHeight(22)
    titleBox:SetAutoFocus(false)
    titleBox:SetMaxLetters(180)
    titleBox:SetFontObject(GameFontNormalLarge)
    titleBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        Flush()
        body:SetFocus()
    end)
    titleBox:SetScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        MarkDirty()
        UpdateSelectedRow()
    end)
    titleBox:SetScript("OnEditFocusLost", function()
        Flush()
        if listStale then RefreshList() end
    end)

    frame.tagLabel = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.tagLabel:SetPoint("TOPLEFT", titleBox, "BOTTOMLEFT", 2, -2)
    frame.tagLabel:SetText("Tags:")

    tagBox = CreateFrame("EditBox", "CommanderNotebookTagBox", page)
    tagBox:SetPoint("LEFT", frame.tagLabel, "RIGHT", 6, 0)
    tagBox:SetPoint("RIGHT", page, "RIGHT", -10, 0)
    tagBox:SetHeight(16)
    tagBox:SetAutoFocus(false)
    tagBox:SetMaxLetters(200)
    tagBox:SetFontObject(GameFontHighlightSmall)
    tagBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    tagBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    tagBox:SetScript("OnTextChanged", function(_, userInput)
        if userInput then MarkDirty() end
    end)
    tagBox:SetScript("OnEditFocusLost", function()
        Flush()
        -- A tag edit changes the sidebar, which a plain list refresh does not
        -- touch: a brand new tag has to appear under TAGS the moment it is
        -- typed, or it looks as though the tag did not take.
        RefreshSidebar()
        RefreshList()
    end)

    infoText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", frame.tagLabel, "BOTTOMLEFT", 0, -4)
    infoText:SetPoint("RIGHT", page, "RIGHT", -10, 0)
    infoText:SetJustifyH("LEFT")

    frame.editRule = Rule(page)
    frame.editRule:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -5)
    frame.editRule:SetPoint("TOPRIGHT", page, "TOPRIGHT", -10, 0)
    frame.rules[#frame.rules + 1] = frame.editRule

    actionRow = CreateFrame("Frame", nil, page)
    actionRow.buttons = {}
    actionRow:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 10, 8)
    actionRow:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -10, 8)
    actionRow:SetHeight(ACTION_H - 4)

    attachStrip = CreateFrame("Frame", nil, page)
    attachStrip:SetPoint("BOTTOMLEFT", actionRow, "TOPLEFT", 0, 6)
    attachStrip:SetPoint("BOTTOMRIGHT", actionRow, "TOPRIGHT", 0, 6)
    attachStrip:SetHeight(18)
    attachStrip:Hide()

    bodyScroll = CreateFrame("ScrollFrame", "CommanderNotebookBodyScroll", page,
        "UIPanelScrollFrameTemplate")
    bodyScroll:SetPoint("TOPLEFT", frame.editRule, "BOTTOMLEFT", 0, -6)
    bodyScroll:SetPoint("TOPRIGHT", frame.editRule, "BOTTOMRIGHT", 0, -6)
    bodyScroll:SetPoint("BOTTOM", attachStrip, "TOP", 0, 4)
    -- The scrollbar of UIPanelScrollFrameTemplate hangs outside the frame's
    -- right edge, so the right anchor above is pulled in by the page padding
    -- rather than by the bar's own width.
    WheelScroll(bodyScroll, 30)

    body = CreateFrame("EditBox", "CommanderNotebookBody", bodyScroll)
    body:SetMultiLine(true)
    body:SetAutoFocus(false)
    body:SetMaxLetters(0)
    body:SetFontObject(GameFontHighlight)
    body:SetWidth(FRAME_W - SIDEBAR_W - LIST_W - 80)
    body:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    body:SetScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        MarkDirty()
        UpdateSelectedRow()
    end)
    body:SetScript("OnCursorChanged", ScrollToCursor)
    body:SetScript("OnEditFocusLost", function()
        Flush()
        if listStale then RefreshList() end
        RefreshAttachments()
    end)
    bodyScroll:SetScrollChild(body)
    bodyScroll:SetScript("OnSizeChanged", function() SyncBodyWidth() end)

    -- Clicking the empty paper below the last line puts the cursor at the end,
    -- the way clicking under the text in any editor does. The EditBox itself
    -- is only as tall as its text, so this catcher sits behind it.
    local paper = CreateFrame("Button", nil, page)
    paper:SetPoint("TOPLEFT", bodyScroll, "TOPLEFT", 0, 0)
    paper:SetPoint("BOTTOMRIGHT", bodyScroll, "BOTTOMRIGHT", 0, 0)
    paper:SetFrameLevel(math.max((bodyScroll:GetFrameLevel() or 1) - 1, 0))
    paper:SetScript("OnClick", function()
        local note = state.selected and S.Note(state.selected)
        if note and not note.trashed then
            body:SetFocus()
            body:SetCursorPosition(#(body:GetText() or ""))
        end
    end)

    frame.emptyText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.emptyText:SetPoint("CENTER", page, "CENTER", 0, 20)
    frame.emptyText:SetWidth(240)
    frame.emptyText:SetJustifyH("CENTER")

    frame:SetScript("OnHide", function()
        Flush()
        if GameTooltip then GameTooltip:Hide() end
    end)
    frame:SetScript("OnShow", function()
        RefreshAll()
    end)

    -- The save debounce. One OnUpdate for the whole window, doing nothing at
    -- all until a keystroke has actually set a deadline.
    frame:SetScript("OnUpdate", function()
        if saveAt and GetTime() >= saveAt then
            Flush()
        end
    end)

    for _, name in ipairs({
        "CommanderNotebookSidebarScroll",
        "CommanderNotebookListScroll",
        "CommanderNotebookBodyScroll",
    }) do
        Commander.UI.SlimScrollBar(name, 2, 2)
    end

    frame.SetSortText(state.sort)
    ApplyPosition()
    ApplyStyle()
    return frame
end

N.ApplyPosition = ApplyPosition

-- ---------------------------------------------------------------------------
-- Shift-clicking things into a note
--
-- The client routes every shift-click of an item, spell or quest through
-- ChatEdit_InsertLink, which walks the chat frames looking for one with focus.
-- Wrapping it is how a non-chat edit box gets a share: if one of ours has
-- focus the link goes there and the wrapper reports that it was handled, and
-- otherwise the original runs untouched. This is the only path -- there is no
-- event for "a link was shift-clicked".
-- ---------------------------------------------------------------------------

local function InstallLinkCapture()
    if N._linkHooked then return end
    N._linkHooked = true
    local original = ChatEdit_InsertLink
    ChatEdit_InsertLink = function(text, ...)
        if text and text ~= "" and frame and frame:IsShown() then
            for _, box in ipairs({ body, titleBox, tagBox }) do
                if box and box:IsVisible() and box:HasFocus() then
                    box:Insert(text)
                    MarkDirty()
                    if box == body then RefreshAttachments() end
                    return true
                end
            end
        end
        if original then return original(text, ...) end
        return false
    end
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

function N.SelectSource(scope, key)
    EnsureFrame()
    SelectSource(scope, key)
end

function N.NewNote(notebookID)
    if not Ready() then return end
    EnsureFrame()
    Flush()

    -- A new note belongs in the notebook you are looking at. Starting one from
    -- a tag or from the trash would otherwise have no sensible home, so those
    -- fall back to the default and the sidebar follows the note rather than
    -- the note being filed somewhere the reader cannot see.
    local target = notebookID
    if not target then
        if state.scope == "notebook" and state.key then
            target = state.key
        else
            target = S.DefaultNotebookID()
        end
    end

    local note = S.CreateNote({ notebook = target })
    if state.scope == "tag" and state.key then
        S.AddTag(note.id, state.key)
    end
    if DB().StampNewNotes then
        Stamp(note.id)
    end

    if state.scope == "trash" or (state.scope == "notebook" and state.key ~= target) then
        state.scope, state.key = "notebook", target
    end
    state.search = ""
    if frame.searchBox then frame.searchBox:SetText("") end

    LoadNote(note.id)
    RefreshAll()
    N.Show()
    titleBox:SetFocus()
    return note
end

function N.Show()
    if not Enabled() then
        print("Commander Notebook is switched off. Turn it on with /cnote settings.")
        return
    end
    if not Ready() then return end
    EnsureFrame()
    if frame:IsShown() then return end
    ApplyStyle()
    ApplyPosition()
    frame:Show()
    RefreshAll()
end

function N.Hide()
    if frame and frame:IsShown() then
        Flush()
        frame:Hide()
    end
end

function N.Toggle()
    if frame and frame:IsShown() then N.Hide() else N.Show() end
end

function N.OpenToNote(id)
    if not (Ready() and S.Note(id)) then return false end
    N.Show()
    local note = S.Note(id)
    SelectSource(note.trashed and "trash" or "notebook", note.trashed and nil or note.notebook)
    SelectNote(id)
    return true
end

-- Quick capture. The point of it is that it works without the window: a line
-- typed mid-fight lands in a dated note in the capture notebook and nothing
-- appears on screen except one confirmation.
function N.Capture(text)
    if not Ready() then return end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        print("Commander Notebook: /cnb <text> writes a line into today's notes.")
        return
    end

    local bookName = DB().CaptureNotebook
    if not bookName or bookName == "" then bookName = "Quick Notes" end
    local bookID = S.NotebookByName(bookName) or S.CreateNotebook(bookName) or S.DefaultNotebookID()

    local today = date("%d %b %Y")
    local existing
    for _, note in ipairs(S.List({ scope = "notebook", key = bookID })) do
        if note.title == today then existing = note break end
    end
    if not existing then
        existing = S.CreateNote({ title = today, notebook = bookID })
    end

    Flush()
    S.AppendBody(existing.id, date("%H:%M") .. "  " .. text)
    if DB().CaptureSound ~= false and PlaySound then
        -- A soft, short, unmistakably-not-an-error sound.
        pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 846)
    end
    print("Commander Notebook: noted.")
    if frame and frame:IsShown() then
        if state.selected == existing.id then LoadNote(existing.id) end
        RefreshAll()
    end
    return existing
end

-- The client shipped one note explaining itself, and an empty notebook is a
-- worse first impression than a full one. Written once ever: the flag is kept
-- out of DefaultSettings so Restore Defaults cannot bring it back from the
-- dead in a notebook the user has since filled and tidied.
local WELCOME = table.concat({
    "This is your notebook. It works the way the old Evernote client did.",
    "",
    "Down the left are your sources: every note, your notebooks, your tags, and the trash. In the middle is the list of whatever source you picked. On the right is the note itself.",
    "",
    "There is no save button. Notes save themselves a moment after you stop typing, and again whenever you switch notes, close the window or log out.",
    "",
    "Things worth knowing:",
    "",
    "Shift-click an item, spell or quest while the cursor is in a note and it goes in as a real link. Everything you have linked into a note is listed along the bottom of the page - hover one for its tooltip, click one to do whatever clicking that link normally does.",
    "",
    "Tags go in the line under the title, separated by commas. They show up in the sidebar as soon as you type them. Right-click one there to rename it everywhere at once.",
    "",
    "The search box takes more than words: tag:raid, notebook:keys, is:pinned, is:untagged, or \"an exact phrase\" in quotes. Two words means both.",
    "",
    "Stamp writes down who you are, where you are standing and what time it is. With Commander Orders installed, a stamped note gets a Go button that points the arrow back to that spot.",
    "",
    "/cnb <text> writes a line into today's notes without opening anything. It works mid-fight.",
    "",
    "Deleting a note puts it in the trash, where you can still read it and put it back. Deleting a notebook never deletes the notes in it - they move to Field Notes.",
    "",
    "Slash commands: /cnote to open this, /cnote new, /cnote search, /cnote stats, /cnote settings. Bindings for opening the notebook, starting a note and jumping to the search box are under Key Bindings, in the Commander Notebook section.",
    "",
    "Delete this note whenever you like. Everything in it is in the settings page too.",
}, "\n")

function N.EnsureWelcomeNote()
    if not Ready() then return end
    if CommanderNotebookDB.WelcomeWritten then return end
    CommanderNotebookDB.WelcomeWritten = true
    if S.Stats().notes > 0 then return end
    local note = S.CreateNote({
        title = "Welcome to your notebook",
        body = WELCOME,
    })
    S.TogglePin(note.id)
    return note
end

function N.FocusSearch()
    N.Show()
    if frame and frame.searchBox then
        frame.searchBox:SetFocus()
        frame.searchBox:HighlightText()
    end
end

function N.ShowTrash()
    N.Show()
    N.SelectSource("trash")
end

function N.PrintStats()
    if not Ready() then return end
    local stats = S.Stats()
    print(string.format(
        "Commander Notebook: %d note%s in %d notebook%s, %d tag%s, %d word%s written. %d in the trash.",
        stats.notes, stats.notes == 1 and "" or "s",
        stats.notebooks, stats.notebooks == 1 and "" or "s",
        stats.tags, stats.tags == 1 and "" or "s",
        stats.words, stats.words == 1 and "" or "s",
        stats.trashed))
end

-- Globals the settings page, the bindings and the rest of the suite call.
function CommanderNotebook_Toggle() N.Toggle() end
function CommanderNotebook_Show() N.Show() end
function CommanderNotebook_Hide() N.Hide() end
function CommanderNotebook_NewNote() N.NewNote() end
function CommanderNotebook_FocusSearch() N.FocusSearch() end
function CommanderNotebook_ShowTrash() N.ShowTrash() end
function CommanderNotebook_PrintStats() N.PrintStats() end
function CommanderNotebook_Capture(text) N.Capture(text) end
function CommanderNotebook_OpenToNote(id) return N.OpenToNote(id) end
function CommanderNotebook_Flush() return Flush() end

-- Quick capture takes free text, which the shared slash dispatcher does not:
-- it matches whole words against a handler table. So it gets its own command.
SLASH_COMMANDERNOTEBOOKCAPTURE1 = "/cnb"
SLASH_COMMANDERNOTEBOOKCAPTURE2 = "/capture"
SlashCmdList["COMMANDERNOTEBOOKCAPTURE"] = function(msg)
    N.Capture(msg)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event)
    if event ~= "PLAYER_LOGIN" then return end

    S.Now = function() return time() end
    S.Who = function()
        local name = UnitName and UnitName("player") or "player"
        local realm = GetRealmName and GetRealmName() or nil
        return realm and (name .. "-" .. realm) or name
    end

    state.sort = DB().SortMode or "updated"
    state.scope = DB().LastScope or "all"
    state.key = DB().LastKey
    -- The remembered source may have been a notebook or tag that no longer
    -- exists, in which case falling back to All Notes is the only view that
    -- is certain to have something in it.
    if state.scope == "notebook" and not (state.key and S.Notebook(state.key)) then
        state.scope, state.key = "all", nil
    elseif state.scope == "tag" and not state.key then
        state.scope, state.key = "all", nil
    end

    InstallLinkCapture()
    N.EnsureWelcomeNote()

    Commander.AddListener(COMMANDER_NOTEBOOK_EVENTS.UPDATE, function()
        if not frame then return end
        state.sort = DB().SortMode or state.sort
        if frame.SetSortText then frame.SetSortText(state.sort) end
        ApplyStyle()
        ApplyPosition()
        RefreshAll()
        if not Enabled() then N.Hide() end
    end)
end)

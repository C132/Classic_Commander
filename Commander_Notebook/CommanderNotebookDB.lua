-- Commander Notebook: defaults, the settings page, and the load lifecycle.
--
-- One thing about this file matters more than the rest of it put together:
-- the notes are in the same SavedVariables table as the settings, and
-- Commander.UI.ResetToDefaults iterates the DEFAULTS table rather than the
-- saved one. Restore Defaults therefore rewrites exactly the keys listed in
-- DefaultSettings below and cannot touch Notes, Notebooks or NextID. Do not
-- "tidy" that by adding Notes = {} to the defaults: it would turn the
-- Restore Defaults button into a delete-everything button.
--
-- The view state (which source is selected, which note was open) is
-- deliberately kept out of DefaultSettings for the same reason it is kept out
-- of the options page: it is where the user was, not what the user chose.

CommanderNotebookDB = _G.CommanderNotebookDB or {}

COMMANDER_NOTEBOOK_EVENTS = {
    UPDATE = "COMMANDER_NOTEBOOK_UPDATE"
}

local DefaultSettings = {
    EnableNotebook = true,

    -- The window
    FrameStyle = "PARCHMENT",
    FrameScale = 1.0,
    ShowSidebar = true,

    -- The note list
    SortMode = "updated",
    PinFirst = true,
    ShowSnippets = true,
    ShowListTags = true,

    -- The editor
    EditorFontSize = "NORMAL",
    AutoSaveDelay = 1.0,
    ShowAttachments = true,
    ShowNoteInfo = true,

    -- Capture
    CaptureNotebook = "Quick Notes",
    StampNewNotes = false,
    CaptureSound = true,

    -- The trash
    TrashDays = 30,
    ConfirmDestroy = true,
}

CommanderNotebook_Defaults = DefaultSettings

local SORT_OPTIONS = {
    { text = "Date Updated", value = "updated" },
    { text = "Date Created", value = "created" },
    { text = "Title", value = "title" },
    { text = "Notebook", value = "notebook" },
}

local FONT_OPTIONS = {
    { text = "Small", value = "SMALL" },
    { text = "Normal", value = "NORMAL" },
    { text = "Large", value = "LARGE" },
}

local STYLE_OPTIONS = {
    { text = "Parchment", value = "PARCHMENT" },
    { text = "Dark Panel", value = "DARK" },
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderNotebookDB, DefaultSettings)
    Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
    print("Commander Notebook: settings restored to defaults. Your notes were not touched.")
end

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Notebook",
        title = "Notebook",
        addonName = "Commander_Notebook",
        description = "Your notes, in the game, in the shape the old Evernote client had them: a sidebar of notebooks and tags down the left, the list of notes in the middle, and the note you are writing on the right. Notes save themselves as you type, keep the items and spells you shift-click into them as real links, and remember where you were standing when you wrote them.",
        event = COMMANDER_NOTEBOOK_EVENTS.UPDATE,
        slash = { "/cnote", "/cnotebook" },
        slashHandlers = {
            [""] = function() Call("CommanderNotebook_Toggle") end,
            new = function() Call("CommanderNotebook_NewNote") end,
            search = function() Call("CommanderNotebook_FocusSearch") end,
            stats = function() Call("CommanderNotebook_PrintStats") end,
            trash = function() Call("CommanderNotebook_ShowTrash") end,
        },
    })

    panel:AddSection("Notebook")
    panel:AddCheckbox({
        label = "Enable the Notebook",
        tooltip = "Master switch. Your notes are kept either way — turning this off only puts the window away.",
        get = function() return CommanderNotebookDB.EnableNotebook end,
        set = function(value) CommanderNotebookDB.EnableNotebook = value end,
    })
    panel:AddDropdownPair({
        label = "Window Style",
        tooltip = "Parchment is the game's own paper, which is what makes the writing area read as a page. Dark Panel matches the rest of the suite's windows.",
        options = STYLE_OPTIONS,
        get = function() return CommanderNotebookDB.FrameStyle end,
        set = function(value) CommanderNotebookDB.FrameStyle = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    }, {
        label = "Note Font",
        tooltip = "The size of the text in the writing area. Titles and the list are unaffected.",
        options = FONT_OPTIONS,
        get = function() return CommanderNotebookDB.EditorFontSize end,
        set = function(value) CommanderNotebookDB.EditorFontSize = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Size of the whole notebook window.",
        min = 0.7, max = 1.4, step = 0.05,
        format = "%.2f",
        get = function() return CommanderNotebookDB.FrameScale end,
        set = function(value) CommanderNotebookDB.FrameScale = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })
    panel:AddCheckbox({
        label = "Show the Sidebar",
        tooltip = "The left column of notebooks and tags. Hiding it gives the list and the page more room; every source is still reachable from the search box (tag:raid, notebook:keys).",
        get = function() return CommanderNotebookDB.ShowSidebar end,
        set = function(value) CommanderNotebookDB.ShowSidebar = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })

    panel:AddSection("The Note List",
        "The middle column: one row per note, newest first.")
    panel:AddDropdown({
        label = "Sort Notes By",
        tooltip = "The order the list opens in. The sort button above the list changes it for the session; this is what it goes back to.",
        options = SORT_OPTIONS,
        get = function() return CommanderNotebookDB.SortMode end,
        set = function(value) CommanderNotebookDB.SortMode = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })
    panel:AddCheckboxPair({
        label = "Pinned Notes First",
        tooltip = "Keep pinned notes at the top of every list regardless of the sort.",
        get = function() return CommanderNotebookDB.PinFirst end,
        set = function(value) CommanderNotebookDB.PinFirst = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    }, {
        label = "Show Snippets",
        tooltip = "The second line of each row: the first words of the note. Off gives you twice as many rows on screen.",
        get = function() return CommanderNotebookDB.ShowSnippets end,
        set = function(value) CommanderNotebookDB.ShowSnippets = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })
    panel:AddCheckbox({
        label = "Show Tags In The List",
        tooltip = "Print a note's tags along the bottom of its row.",
        get = function() return CommanderNotebookDB.ShowListTags end,
        set = function(value) CommanderNotebookDB.ShowListTags = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })

    panel:AddSection("Writing",
        "There is no save button. There was not one in Evernote either.")
    panel:AddSlider({
        label = "Save After",
        tooltip = "How long you have to stop typing before the note is written to disk. Switching notes, closing the window and logging out always save immediately, whatever this says.",
        min = 0.25, max = 3.0, step = 0.25,
        format = "%.2f sec",
        get = function() return CommanderNotebookDB.AutoSaveDelay end,
        set = function(value) CommanderNotebookDB.AutoSaveDelay = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })
    panel:AddCheckboxPair({
        label = "Show Attachments",
        tooltip = "The strip under the page listing every item, spell and quest you have linked into this note — hover one for its tooltip, click one to put it back on your cursor.",
        get = function() return CommanderNotebookDB.ShowAttachments end,
        set = function(value) CommanderNotebookDB.ShowAttachments = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    }, {
        label = "Show Note Info",
        tooltip = "The line above the page: which notebook, when it was created and last changed, and how many words are in it.",
        get = function() return CommanderNotebookDB.ShowNoteInfo end,
        set = function(value) CommanderNotebookDB.ShowNoteInfo = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })

    panel:AddSection("Quick Capture",
        "/cnb <text> writes a line without opening anything, from anywhere, including mid-fight.")
    panel:AddCheckboxPair({
        label = "Stamp New Notes",
        tooltip = "Put a line at the top of every new note saying who you were, where you were standing and when. You can always add one by hand with the Stamp button.",
        get = function() return CommanderNotebookDB.StampNewNotes end,
        set = function(value) CommanderNotebookDB.StampNewNotes = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    }, {
        label = "Capture Sound",
        tooltip = "A soft click when /cnb files a line away, so you know it landed without looking.",
        get = function() return CommanderNotebookDB.CaptureSound end,
        set = function(value) CommanderNotebookDB.CaptureSound = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })

    panel:AddSection("The Trash",
        "Deleting a note puts it here. Nothing else in this addon removes writing.")
    panel:AddSlider({
        label = "Empty Trash After",
        tooltip = "Notes older than this are dropped for good at login. Slide it to zero to keep the trash forever.",
        min = 0, max = 180, step = 5,
        format = "%d days",
        get = function() return CommanderNotebookDB.TrashDays end,
        set = function(value) CommanderNotebookDB.TrashDays = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })
    panel:AddCheckbox({
        label = "Ask Before Deleting For Good",
        tooltip = "Confirm before a note is removed from the trash permanently. Leave this on.",
        get = function() return CommanderNotebookDB.ConfirmDestroy end,
        set = function(value) CommanderNotebookDB.ConfirmDestroy = value end,
        isEnabled = function() return CommanderNotebookDB.EnableNotebook end,
    })

    panel:AddButtonRow({
        {
            label = "Open Notebook",
            width = 130,
            tooltip = "Open the notebook window (also: /cnote).",
            onClick = function() Call("CommanderNotebook_Show") end,
        },
        {
            label = "New Note",
            width = 110,
            tooltip = "Start a new note in the current notebook (also: /cnote new).",
            onClick = function() Call("CommanderNotebook_NewNote") end,
        },
        {
            label = "What's In There?",
            width = 140,
            tooltip = "Print a count of notes, notebooks, tags and words to chat (also: /cnote stats).",
            onClick = function() Call("CommanderNotebook_PrintStats") end,
        },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page. Your notes, notebooks and tags are not touched — this button cannot delete writing.",
    })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Notebook" then
        Commander.UI.ApplyDefaults(CommanderNotebookDB, DefaultSettings)
        -- The store normalises whatever came off disk before anything reads
        -- it, so every later caller may assume the invariants hold.
        CommanderNotebookStore.Attach(CommanderNotebookDB)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
        local purged = CommanderNotebookStore.PurgeExpired(CommanderNotebookDB.TrashDays)
        if purged > 0 then
            print(string.format("Commander Notebook: emptied %d note%s from the trash.",
                purged, purged == 1 and "" or "s"))
        end
    elseif event == "PLAYER_LOGOUT" then
        -- The last line typed has to reach disk even if the save timer had not
        -- fired yet. This is the only moment left to do it.
        Call("CommanderNotebook_Flush")
    end
end

frame:SetScript("OnEvent", OnEvent)

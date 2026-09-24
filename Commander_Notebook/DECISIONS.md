# Commander_Notebook — decisions

Numbered so code comments and future sessions can cite them.

## D1 — The notes live in the settings table, and Restore Defaults is made safe by construction

`CommanderNotebookDB` is one SavedVariables table holding both the options and every word the user
has ever written. That is a deliberate choice — a second SavedVariables file would mean a second
thing to keep in step, and the TOC's `## SavedVariables` line is the only migration tool this
client has — but it puts the writing one careless line away from the Restore Defaults button.

The safety is structural rather than remembered. `Commander.UI.ResetToDefaults` iterates the
**defaults** table, not the saved one, so it can only rewrite keys that appear in
`DefaultSettings`. `Notes`, `Notebooks` and `NextID` deliberately do not appear there, and neither
does the view state (`LastScope`, `LastKey`, `LastNote`), which is where the reader was rather than
what the reader chose.

This is checked twice in the harness — once as a property of the defaults table (R1) and once by
running the real `/cnote reset` path and counting the notes afterwards (R2) — because it is the one
mistake in this module that a user could not recover from.

## D2 — Notes are a map keyed by id, and order is a property of a query

Storage is `Notes[id] = note`, never an array. A note id has to survive the disappearance of every
note around it: the window holds a selection across a refresh, the trash restores into the middle
of a list, and a search reorders everything. Array indices do none of that.

Nothing is stored sorted. `S.List(query)` filters and sorts on demand, which is what makes the same
store answer "this notebook, newest first", "this tag, by title" and "everything matching
thunderfury" without keeping three indexes in step.

Every comparator ends on the id. `table.sort` is not stable, so two notes written in the same second
would otherwise swap places between two refreshes of an unchanged list, which reads as a flicker
(harness H6).

## D3 — Deleting is two stages, and only one function forgets

`Trash` sets a timestamp. `Destroy` is the only function in the module that removes text. Between
them the note leaves every view except the trash, which is enforced in one place — the scope filter
in `S.List` — rather than by remembering to exclude trashed notes at each call site (harness F2).

Deleting a **notebook** never deletes notes. They move, to the requested target if it resolves and
to the default otherwise. A confirm dialog is a worse guarantee than an invariant, and the dialog
says so in as many words, because the fear it has to answer is "am I about to lose everything I
wrote in here".

The same invariant covers a case that only shows up later: `Attach` re-homes any note whose notebook
has gone missing, so a table damaged by an older build or a hand edit loses a folder, never a note.

## D4 — There is no save button, and Flush is the whole contract

Evernote had no save button and neither does this. The rule is: the editor is the truth while it
has focus, and `Flush` is the only thing that moves that truth into the store. Everything that could
lose keystrokes calls it first — switching notes, closing the window, hiding it, a menu action, and
`PLAYER_LOGOUT`, which is the last moment that exists.

Two consequences are load bearing:

- **Every store setter returns whether it changed anything.** Loading a note into the editor fires
  `OnTextChanged` with the note's own text; without the no-op guard, merely *reading* a note would
  restamp `updated` and reorder every recently-updated list (harness E1, C9).
- **A repaint never overwrites unsaved text.** `RefreshEditor` treats a dirty editor as
  "keep what is on screen". Clicking a dropdown does not take focus off the edit box, so without
  this, pinning a note mid-sentence would roll the sentence back (harness C10).

## D5 — The list updates in place while you type; it re-sorts when you look away

Typing changes `updated`, and the default sort is by `updated`, so a literal implementation would
move the row you are editing to the top of the list on every keystroke.

Instead the selected row's title and snippet are rewritten in place on each keystroke, and the
re-sort is deferred (`listStale`) until focus leaves the editor. The list feels live; the row does
not move out from under the cursor.

Pinning deliberately does **not** touch `updated`. Pinning is a shelf, not an edit, and stamping it
would jump the note to the top of a recency sort for a reason that has nothing to do with writing.

## D6 — Links are the attachments, and the payload is kept verbatim

An item shift-clicked out of a bag is the closest thing this client has to Evernote's attachments:
it survives in SavedVariables as text, and it can be handed straight back to
`GameTooltip:SetHyperlink` to become the real thing again. So the store keeps the link payload
exactly as the client wrote it, and only the *display* label is stripped of colour and brackets.

Everything that reads a body for a purpose other than display goes through `S.PlainText` first. A
search for "thunderfury" has to match the label inside the hyperlink, and a snippet that pasted a
raw `|cff` code into a list row would leak that colour across the rest of the row.

Getting a link *into* a note has exactly one path: the client routes every shift-click through
`ChatEdit_InsertLink`, which walks the chat frames looking for one with focus. Wrapping that
function is how a non-chat edit box gets a share. There is no event for "a link was shift-clicked",
so there is no alternative to the wrapper; it claims the link only when one of our boxes actually
has focus and otherwise calls the original untouched (harness H1, H3).

## D7 — Two complete skins, not one skin with exceptions

`FrameStyle` picks between parchment (dark ink on the game's own paper) and the suite's dark panel.
Every piece of text and every rule reads its colour from the `SKINS` table, so neither style can end
up with one stray unreadable label — which is exactly what happens when a light background is added
to a UI whose colours were written for a dark one.

Parchment is the default because it is the only thing this client has that makes a writing area
read as a page rather than as a text field, and that was the point of the exercise.

The accent follows Commander_Console through the TopBar soft-fail pattern: read
`CommanderConsole_Colors` through `ipairs(x or {})` and fall back to steel. A missing Console
degrades the accent, never the module.

## D8 — Quick capture gets its own slash command

The shared slash dispatcher matches whole words against a handler table, which is right for
`/cnote new` and useless for free text. So `/cnb <text>` is registered separately.

It appends to a note titled with today's date in the capture notebook, creating either if missing.
The point of it is that it opens nothing: a line typed mid-fight lands somewhere findable and the
only feedback is one chat line and a soft sound.

## D9 — Chrome is drawn, not borrowed

Selection bars, chevrons, rules and the pin are quads cut from `WHITE8X8` and tinted, for the
reasons Quest Log and Bags already document: `ARIALN` renders shape glyphs as missing-glyph boxes,
and icon *files* move between client patches.

The one Blizzard region kept on purpose is the quest parchment behind the page, which is what makes
the parchment style work at all.

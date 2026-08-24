# Commander Debug — assumptions

Everything this module does rests on someone else's error hook, so the
assumptions are worth writing down. Verified against `!BugGrabber` v12.0.20
and the 2.5.5 Anniversary client (interface 20506, build 68101).

## BugGrabber

- **The global is `BugGrabber`**, a read-only proxy table
  (`__newindex` is a no-op, `__metatable` is false). Do not try to extend it.
- **`BugGrabber:GetDB()`** returns the live array of error objects — the same
  table BugSack draws from. Treat it as read-only: we normalize into fresh
  tables rather than annotating theirs.
- **An error object is** `{ message, stack, locals, counter, time, session }`.
  `message` is a string; historically it could be a table, and BugGrabber
  still sanitizes those out, so we skip any entry whose message is not a
  string. `stack` and `locals` are newline-joined strings and may be absent
  (simple errors are stored without them).
- **`session` is a login counter**, incremented once in BugGrabber's
  `ADDON_LOADED`. So `err.session == BugGrabber:GetSessionId()` means "since
  the last login *or* `/reload`" — a `/reload` starts a new session, which is
  what our SESSION scope means and why the settings say so.
- **Repeats update in place**: an error seen again in a later session has its
  `session` and `time` rewritten and its `counter` bumped, and it is moved to
  the end of the DB. Session filtering therefore stays accurate for anything
  still firing, and the DB is roughly, but not exactly, chronological — we
  sort by `time` rather than trusting order.
- **The DB holds 500 unique errors**, oldest dropped first
  (`MAX_BUGGRABBER_ERRORS`).
- **`BugGrabber:Reset()`** empties the database and resets the session counter
  to 1. It is shared state: clearing here empties BugSack too.
- **`EventRegistry:TriggerEvent("BugGrabber.BugGrabbed", tableID)`** fires per
  capture, and `BugGrabber:GetErrorByID(tableID)` resolves the object. That is
  how the announce option hears about new errors without polling.
- **`seterrorhandler` is neutered** once BugGrabber loads — it replaces the
  function with an empty one after installing its own handler. Any attempt of
  ours to install a handler alongside it would be silently swallowed, so we do
  not try: the presence check comes first.
- **We do not register as a BugGrabber display.** BugGrabber picks the first
  enabled addon carrying `X-BugGrabber-Display` metadata, and that should stay
  BugSack. This module is a copy path, not a viewer.

## Native fallback

- Used only when BugGrabber is absent. `seterrorhandler` is real then, and we
  chain to whatever `geterrorhandler()` returned first so the client's own
  error display is unaffected.
- `debugstack(3, 20, 20)` and, where the client provides it, `debuglocals(3)`
  supply the stack and locals — both guarded, both inside a `pcall`, since an
  error raised inside an error handler is how a client freezes.
- The store is in-memory and session-only: 250 unique messages, deduped, ring
  buffer. Nothing is saved, so SESSION and ALL scope are the same thing here.
- `LUA_WARNING` and `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` arrive as
  events rather than through the handler. Blocked-action lines are recorded
  once per addon — a tainted addon fires them by the hundred.

## Copying

- **The client exposes no clipboard API.** "Copy to clipboard" is a multiline
  `EditBox` holding the text, focused and highlighted; the user presses the
  copy key. `IsMacClient()` decides whether the hint says Cmd+C or Ctrl+C.
- An `EditBox` renders `|cff…` colour codes and `|H…|h` links rather than
  showing them as text, so anything pasted would silently lose them. Error
  text is stripped of escape sequences before it goes in the box.
- Long reports are split at error boundaries with the full header repeated,
  because a single paste has practical limits at both ends — the box and the
  prompt.

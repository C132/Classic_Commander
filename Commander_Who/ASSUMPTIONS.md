# Commander_Who — assumptions

What this module believes about the 2.5.5 Anniversary client, how confident it
is, and what happens if the belief turns out to be wrong. Anything marked
**unverified** is guarded in code so a wrong answer costs a feature, never an
error.

## A1 — `WhoFrameButton1..N` is a fixed, recycled row pool

**Confidence: high.** It is how every Blizzard faux-scroll list works, it is how
`WhoList_Update` is written, and the reported bug is only explicable this way.

The module does **not** depend on `WHOS_TO_DISPLAY`. It walks `_G["WhoFrameButton"..i]`
from 1 until the first nil (cap 64) and works with however many it finds. A
client that changed the count, or renamed the constant, changes nothing here.

## A2 — `C_FriendList.GetWhoInfo` returns `fullName`, `level`, `classStr`, `filename`, `area`, `fullGuildName`, `raceStr`

**Confidence: high for `classStr`/`filename`/`area`; the 2.1 build's use of
`className` is the counter-evidence** — that field read nil in the live client,
which is exactly the blank class column and warrior-brown colouring the module
shipped with.

Guarded anyway: `E.Normalize` reads a short alias list per field
(`fullName`/`name`, `classStr`/`className`/`class`, `filename`/`classFileName`,
`area`/`zone`, `fullGuildName`/`guild`), and a field it cannot find normalises
to `""` or `0`. A name is the only field it requires.

## A3 — The class token is one of nine

**Confidence: certain.** TBC has no death knights. `E.CLASS_COLORS` carries the
nine and nothing else; an unrecognised token colours **white** rather than
guessing (D12).

## A4 — `/who` results carry no realm suffix

**Confidence: high** — there is no cross-realm `/who` on this client.

Guarded anyway: identity keys are the whole trimmed, case-folded name including
any realm, so `Alaric-Whitemane` and `Alaric-Doomhammer` are two players. The
realm is split off only for display.

## A5 — `WhoList_Update` is a global function that Blizzard calls on scroll, on sort and on result update

**Confidence: high.** `hooksecurefunc("WhoList_Update", …)` is the primary
repaint trigger.

Guarded three ways, because a missed repaint is a visibly wrong tick:

1. `hooksecurefunc("WhoList_Update", …)` — only if the global exists;
2. `WhoListScrollFrame:HookScript("OnVerticalScroll", …)` — catches a scroll
   that somehow does not reach (1);
3. `WHO_LIST_UPDATE` and `WhoFrame:HookScript("OnShow", …)` — catch a result
   set or a tab change that reaches neither.

Any one of the three alone is enough for correctness; all three together mean a
wrong client assumption costs a redundant repaint rather than a wrong tick.

## A6 — `SendChatMessage(msg, "WHISPER", nil, name)` works from an addon on this client

**Confidence: high.** The 2.1 build did exactly this and the user's complaint
was about *who* it messaged, not that it failed to. Retail's hardware-event
restrictions on chat do not apply to 2.5.5.

If it ever stops working the failure is visible immediately — the run advances
and no whisper appears — rather than silent.

## A7 — 255 characters is the whisper ceiling

**Confidence: high.** The edit box enforces it with `SetMaxLetters`, and
`E.ValidateMessage` refuses an over-length message with the overage named rather
than truncating it. Truncation would send half a recruitment pitch to fifty
people.

## A8 — The server's chat throttle disconnects rather than warns

**Confidence: high**, from long-standing community experience rather than from
anything documented. The exact rate is **unverified**, which is why the defaults
are conservative (1.0s apart, 25 recipients) and why both are user-adjustable
rather than hard-coded.

## A9 — `WhoFrameButton%dName` is the row's name font string

**Confidence: medium.** It is the FrameXML naming convention and the 2.1 build
used it, but nothing here proves it against the shipped file.

Guarded: if `_G[name .. "Name"]` is nil, `ShiftName` no-ops. The tick box still
appears and still works; it just sits closer to the name text than intended.
Cosmetic degradation, never an error.

## A10 — `FriendsFrame` exists and `WhoFrame` is parented inside it

**Confidence: high.** The toolbar anchors to `FriendsFrame`'s outside right edge
and falls back to `WhoFrame` if the former is missing, so the worst case is a
toolbar 20px further left than intended.

## A11 — `UICheckButtonTemplate`, `FauxScrollFrameTemplate`, `InputBoxTemplate`, `UIPanelButtonTemplate` and `BackdropTemplate` all exist

**Confidence: certain.** All five are used elsewhere in the suite on this
client.

## A12 — The chat edit box's command matching can confuse `/cw` with the whisper family

**Unverified as to mechanism.** What is established: `/cw` was registered only
by this module, it is the only source of that string in the entire suite, and
the user sees `/cw` where they expect `/w` when whispering. Whether the client
reaches it through slash-command tab completion, a partial-match fallback, or
something else has not been reproduced headless.

The fix does not depend on knowing which: the alias is removed (D6). Nothing in
this module now registers a command shorter than five characters.

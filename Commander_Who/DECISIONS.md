# Commander_Who — decisions

Numbered so code comments and future sessions can cite them. This is a 3.0
rewrite of a 2.1 module that had four user-visible faults; every decision below
either fixes one of them or is a consequence of the fix.

## D1 — Selection is keyed by the player. Row widgets own nothing.

This is the whole module.

Blizzard's Who list is `WhoFrameButton1..17`: a **fixed pool of seventeen
buttons** scrolled over a result set that can be much longer. Scrolling does not
create or destroy rows, it changes an offset and repaints the same seventeen
widgets with different players.

The 2.1 build stored the tick on the widget — `checkboxes[button] = checkbox`,
keyed by button, state read straight off `checkbox:GetChecked()`. Nothing ever
rebound them. So scrolling down four rows moved the first player's tick onto the
fifth player's name, and scrolling back moved it onto someone else again. The
ticks looked like they were jumping around at random. They were not moving at
all; the players underneath them were.

3.0 keeps one `Selection` set keyed by case-folded full name. Every paint —
scroll, sort, re-search, window open — rebinds every visible box from that set:

```lua
check.recordIndex = index
check:SetChecked(selection:Get(record.key))
```

A widget can therefore never be wrong, because it is never asked to remember
anything. The harness proves it by scrolling a fixture list under a deliberately
tiny row pool and asserting the ticks land on the right players.

The corollary is that **row index is not identity**. `record.index` exists
purely so shift-click has something to count with, and it is invalidated
(alongside the shift anchor and the per-row send statuses) every time the record
generation bumps.

## D2 — One selection, two views, no copies

The mass whisper window does not have a list of its own. It reads
`CommanderWho.Selection()` and writes back through `CommanderWho.SetSelected`,
so ticking a row in the window moves the tick on the Who row behind it and vice
versa, and both repaint off the same `COMMANDER_WHO_SELECTION` notify.

The 2.1 build kept a private list here and rebuilt it on every open with
`button.checkbox:SetChecked(true)` — unconditionally, for every result. That
single line is the reported "mass whisper doesn't respect the check marks":
whatever you had ticked in the Who tab, the window arrived with everybody ticked
and sent to everybody.

A shared model rather than a synchronised copy is the only version of this that
cannot drift, and it is why the window is a thin view with no state beyond
scroll offset and per-row send status.

## D3 — The plan is the only thing that decides who gets a message

`E.PlanWhispers(records, selection, opts)` is a pure function and the single
source of "who is about to be whispered". It walks the records **in list order**
and takes the ones the selection says to take.

Everything it refuses, it **counts**:

- `overCap` — selected, but beyond `MaxWhisperCount`
- `skippedSelf` — you
- `selected` — the honest total, so the UI can say "42 selected, 6 over the 50
  cap" rather than quietly messaging the first 50 and saying nothing.

Silent truncation was the 2.1 behaviour and it is the worst option available:
the run looks complete, and the players who were dropped are exactly the ones
you never find out about.

## D4 — The toolbar hangs off the outside of the friends window

There is no free space inside the Who tab. Every pixel belongs to a column
header, a row, the totals line, or Blizzard's own three buttons along the
bottom. The 2.1 build anchored its buttons at `WhoFrame TOPRIGHT (-10, -25)`,
which is the tab strip and title area, and hid `WhoFrameColumnHeader1..5` as
part of its own show/hide toggle — so turning the Commander toolbar off took
Blizzard's Name/Level/Class/Zone headers with it.

3.0 puts a 112px strip on the **outside** right edge of `FriendsFrame`,
parented to `WhoFrame` so it appears and disappears with the tab on its own. It
shows the selected count, All / None / Invert, and Mass Whisper. Nothing
Blizzard drew is hidden, moved, or re-coloured by it.

## D5 — `ShowWhoWindow` is deleted, not carried forward

The 2.1 setting called `WhoFrame:SetShown(value)` from a timer and from four
roster events. `WhoFrame` is a tab child of `FriendsFrame` and its visibility
belongs to the tab system, so this fought that system in **both** directions: it
force-showed the Who panel at login over whatever tab was actually selected, and
force-hid it out from under the tab that owns it.

There is no replacement because there was no working feature. The migration
deletes the key. `ShowWhoButton` — which really did just toggle our own widgets —
becomes `ShowToolbar` and keeps its value.

## D6 — `/cw` is gone and is not coming back

2.1 registered `/cwho` **and** `/cw`. `/cw` is two characters from `/w`, sits in
the same command space the chat edit box matches whisper commands out of, and is
the only source of the string `/cw` anywhere in the suite — which is what the
user was seeing land in the edit box when they meant to whisper someone.

The suite has other short aliases (`/cb`, `/ci`, `/cm`, `/ct`), and none of them
is worth the risk this one carries: `/w` is the most-typed command in the game
and a module that makes it unreliable is worse than no module. Commander_Who now
registers exactly one command, `/cwho`, with `whisper`, `all` and `none`
subcommands.

## D7 — New results arrive unticked

The 2.1 default was everything ticked. Combined with D2 that meant one click on
Mass Whisper and one Enter sent a message to fifty strangers you had not looked
at, and there was no confirmation step.

3.0 arrives unticked, with **Select All one click away** on the toolbar, and
keeps a `SelectNewResults` option for anyone who wants the old default. Ticks
you have already made survive a re-search: `Selection:Prune` keeps everyone
still in the results and drops everyone who is not, so building a list across
several searches works while the count never promises a send it cannot make.

## D8 — The run is a state machine, and it finishes

2.1 asked `C_Timer.NewTicker` to stop after `min(#selected, MaxWhisperCount)`
iterations, and then wrote its "Whispers complete!" message inside the branch
that runs on iteration N+1 — which the ticker's own iteration limit had already
cancelled. A completed run therefore never said it had completed; the progress
text simply froze at the last count.

`E.Run` knows its own size and marks itself done on the last send rather than on
the tick after it. It also has `Cancel`, which is why there is a Stop button —
2.1 had no way to abort a 50-recipient run once started.

One run at a time, enforced in `API.StartRun`: 2.1 started a second independent
ticker on every click of Send.

## D9 — Confirmation names the count and the duration

On by default. A mass whisper cannot be recalled, and the two facts that matter
before it starts are how many people will get it and how long the client will
spend sending. `E.EstimateSeconds` supplies the second; a 25-recipient run at
the default one-second delay is 24 seconds during which you cannot type.

The delay default moved from 0.5s to 1.0s and the slider floor from 0.2s to
0.3s. The server's chat throttle does not warn, it disconnects, and a saved 0.2
from 2.1 is clamped on migration so the stored value and the widget agree.

## D10 — Everything we do to Blizzard's frames is reversible

The tick boxes need horizontal room, so each row's `$parentName` font string is
shifted right by 15px and narrowed by the same amount. 2.1 did the shift too —
permanently, with no record of the original anchor, so the only way back was a
reload.

3.0 captures the original point and width on the first shift and restores both
verbatim when `ShowRowCheckboxes` is turned off. The narrowing is also
conditional: a font string whose reported width equals its own string width has
no column width set, and pinning that would clip every name from then on, so
that case is shifted but not narrowed.

## D11 — Four files, and the engine has no client in it

`CommanderWhoEngine.lua` is pure Lua — identity, normalisation, the selection
set, the plan, message validation, the run. It reads no WoW global, not even for
class colours: the host builds a localised-class-name map out of the client's
own `LOCALIZED_CLASS_NAMES_*` and hands it in.

That is what makes `who_harness.lua` a real test rather than a mock exercise,
and it is why the scroll bug and the mass-whisper bug both have failing
reproductions in the harness that pass only against the fixed code.

## D12 — Unknown class is white, not warrior

`C_FriendList.GetWhoInfo` returns `classStr` and `filename` on this client
(ASSUMPTIONS A2). 2.1 read `className`, which does not exist here — so the class
column was blank on every row, and the colour lookup fell through to a hard
`englishClass = englishClass or "WARRIOR"` default that painted every name
warrior-brown.

3.0 reads a short alias list for each field and returns **white** for a class it
cannot resolve. A wrong colour is worse than no colour: it is a fact the player
will act on.

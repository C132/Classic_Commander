# Commander_Vault harness

One luajit check. Run it before any change to the model, the search language,
the advisor, the sort, or the window.

```bash
/opt/homebrew/bin/luajit vault_harness.lua   # 365 checks
```

It resolves the AddOns root from its own file location, so it works in a git
worktree as well as in the live AddOns directory, and exits non-zero if any
check fails.

## What it covers

The harness loads the real `CommanderSettingsUI.lua` and `CommanderEvents.lua`
alongside all six `Commander_Vault` files under a permissive WoW mock, builds a
bank of thirteen fixture stacks across the base container and one bank bag,
fires login, and then drives a whole bank visit.

- **A — containers and the model.** Bank bags resolve to 5..11 and not the
  mainline enum's 6..12; a scan with the bank shut reads nothing rather than
  clobbering a good snapshot; every stack, empty slot and section lands where
  it should. Grey beats quality, quest beats item class.
- **B — the cache and dwell history.** The live scan writes through to the
  SavedVariable, the cached snapshot reproduces it container-for-container, and
  an item that leaves the vault forgets when it arrived — so a withdrawn and
  redeposited stack does not read as ancient.
- **C — the search language.** Free text over name, type and subtype; quoted
  phrases; negation; `q:`, `ilvl:`, `t:`, `s:`, `old:`; the bind and usability
  flags; and the two rules that matter most — terms narrow rather than widen,
  and an unknown field degrades to a text search instead of erroring.
- **D — the advisor.** Each rule fires on the fixture designed for it, with the
  counts and the vendor value it claims, and the report is ordered worst-first.
  The Armory hand-off gets its own run: with a saved set claiming two of the
  fixtures, they drop out of every clutter rule, stop being called stale, and
  get a finding of their own saying why — and with Armory gone the rules go
  back to exactly what they said before.
  A vault filled to the last slot raises the space finding as a warning, and
  the Quartermaster hand-off stays silent with that module absent while
  raising exactly the BANKED slots when it is present.
- **E — the sort.** Run against a genuinely **mutable** world with a properly
  modelled cursor (pick up / place / merge / swap), because a sort test against
  an immutable world proves nothing. Three cloth stacks fold into one, two
  slots come back, the survivors end up in quality order compacted to the
  front, the cursor ends empty — and combat stops it on the very next tick.
- **F — transfers.** A deposit moves exactly the predicate's items and nothing
  else, and a deposit with the bank shut is refused outright. That refusal is
  the important one: the same `UseContainerItem` call with the bank closed
  *uses* the item.
- **G — the window.** Visiting a banker opens the vault and puts the stock
  frame away **without hiding it** (hiding it would end the banker's session);
  the grid draws one button per stack, or every slot with free space shown;
  Hide-the-rest and Dim-the-rest do what they say; closing the bank takes the
  final snapshot *before* the flag flips, and puts Blizzard's frame back
  exactly as it was.
- **H — the roster.** Two fabricated alts go into the cache. The played
  character always reads live (`GetItemCount` answers for the bank with the
  bank shut); alts read from the cache and only from the cache. An alt's vault
  rebuilds into the same model rows, so the same search language reaches it —
  and selecting one in the window takes the Sort and Deposit buttons *away*
  rather than leaving them inert. Dropping an item on the window puts it in the
  first free slot and no other, and is refused outright away from a banker.
- **I — the tooltip line.** Hovering an item you have banked says how many and
  which alt holds the rest; a repeated hook call on the same item writes
  nothing twice (this client fires `OnTooltipSetItem` more than once per
  hover); clearing the tooltip lets the next item speak; each of the three
  modes does what it says; and an item you own none of anywhere gets no lines
  at all.
- **J — framing and the item tooltip.** Bank style draws the stock dressing and
  the template's own steps aside (including its title, so the name is not drawn
  twice); Window hands it back. The tooltip half is a regression test with
  teeth. The fake client breaks `SetBagItem` the way the real one does: the
  call still **fires `OnTooltipSetItem`** while filling nothing, so a
  third-party addon on that hook (the harness runs one, like the auction addons
  people actually have) lands its lines on an empty tooltip. A line count
  therefore says "filled" while the item's own name is nowhere on it — which is
  the bug, twice. The module must fall through to the link anyway, must not be
  fooled by the *previous* hover's item still answering `GetItem`, and with all
  three sources dead must draw what it already knows rather than a stub. It also proves a vault slot writes ONE count block
  rather than collecting the global layer's on top of its own, while an
  ordinary tooltip elsewhere in the game still gets its counts.
- **K — sections you named yourself.** An authored assignment beats every
  built-in rule including the grey verdict, outranks every built-in section,
  survives Restore Defaults (it is data, not an option), and is reachable from
  the grid by ctrl+right-click — while plain right-click still withdraws,
  which the harness checks explicitly because stealing the common gesture
  would be the obvious way to get this wrong. Dissolving a section files its
  items back rather than destroying anything.
- **L — cost, and the report with nothing to say.** Forty
  `GET_ITEM_INFO_RECEIVED` events for items the grid is not waiting on must
  cost *nothing*; the one item it is waiting on must wake it, exactly once.
  (Verified to bite: with the old open-window-is-enough handler, all three
  checks fail.) The junk finding offers to carry the junk out, because the
  auto-seller works on your bags and junk in the vault is stuck there. And a
  tidy vault says so instead of rendering an empty panel.
- **M — the guild bank.** Read-only and passive: opening a tab records it, a
  tab your rank cannot see records as *unreadable* rather than as empty (which
  is not the same claim), and an unopened tab is never guessed at. The full
  sweep is opt-in, queries every tab, and puts the tab you were looking at
  back — the mock's `QueryGuildBankTab` moves the selection exactly as the
  real one does, which is the whole reason the module refuses to sweep unasked.
  Counts reach the tooltip; a guild bank browses like any other remembered
  vault and can be forgotten.
- **N — acting on the wrong vault.** The section exists for one bug: while
  browsing an alt's vault the buttons carry *that record's* coordinates, and
  your own bank is very likely open, because you are standing at a banker
  looking up what the alt has. Gating the click on "is the bank open" therefore
  moved YOUR item at those coordinates. Every mutation path — click, withdraw,
  drag out, drop in, split — is checked against a fingerprint of the whole
  world, while ctrl+right-click filing still works (it is a judgement about the
  item, not the slot). Verified to bite: under the old gate, four of these fail.
  Also here: a vault that opens because you walked up to a banker must never
  take keyboard focus, or WASD types into the search box instead of moving you.
- **S — the global footprint.** The module publishes its entry points, its two
  key bindings and its named frames, and nothing else. `Bindings.xml` is read
  as *text* (the client parses it, not Lua): every binding it declares must
  have a `BINDING_NAME_` the addon publishes and must call a function that
  exists, and no comment may contain a double hyphen — that is illegal XML and
  voids the whole file, registering zero bindings with only a `LUA_WARNING` to
  say so.
- **O — the bag rack and buying a slot.** Seven sockets; the ones you own read
  as owned and the next one to buy knows that it is next; an unbought slot is
  tinted the red the stock window uses. The purchase row is offered at a banker
  and prices the next slot from `GetBankSlotCost`, is *removed* once every slot
  is bought, and is removed again — rack and all — while browsing an alt's
  vault, because offering to spend your gold on a grid you are only looking at
  is the D31 mistake in another costume. Buying primes `BankFrame.nextSlotCost`
  before raising `CONFIRM_BUY_BANK_SLOT`, which is the whole of D42, and away
  from a banker the click reaches no dialog at all. Clicking a bought slot
  isolates that bag through the search box and clicking it again lets go.
- **P — resizing.** An undragged window is exactly as wide as the Columns
  slider asks; dragging it narrower drops columns; the size is clamped at both
  ends on both axes rather than trusted; clearing the dragged size restores the
  slider's.
- **Q — an empty grid says which KIND of empty.** A blank pane reads as
  broken. `V.gridEmpty` names the three: nothing matches the search, the vault
  is empty, or nobody ever recorded one — and only the last is a problem.
- **R — an item says which container it is in.** The base slots are not "bag
  -1" and the first bank bag is called 1 rather than 5; hovering anything in
  the grid names where it actually is.

## Mock notes

Lessons already paid for, so the next run does not re-learn them:

- **The shared framework starts a ticker of its own.** `CommanderEvents.lua`
  runs a session-stamp ticker at load and never cancels it, so "is the job
  still running" has to mean "is a ticker created *after* the addon loaded
  still running" — otherwise every run-to-completion loop spins on the stamper
  forever. `preloadTickers` is that baseline.
- `C_Timer.NewTicker` hands the callback back rather than firing it, so the
  sort can be stepped one move at a time. `VAULT_TRACE=1` prints the bank's
  first twenty slots after every step, which is how the convergence bug above
  was found.
- The mock character is a **mage**. The "gear you cannot wear" rule is only
  reachable for a class something can out-armour; on the warrior the bag
  harness uses, nothing is ever unusable.
- `GetContainerItemInfo` returns an `isBound` field only where the fixture sets
  one, matching a client that may or may not carry it.
- `UseContainerItem` moves an item to the other side, which is what it does
  with the bank frame open and is the entire basis of the transfer code.
- **A widget remembers the size it was given.** `GetWidth`/`GetHeight` were
  constants returning 0, which made everything derived from a size — the
  grid's column count, the resize clamps — untestable and, worse, quietly
  *passing*: `V.GridColumns` falls back to the Columns setting when the window
  has no width, so a broken derivation looked correct.
- `GetNumBankSlots` returns two bought of seven plus Blizzard's "nothing left
  to buy" flag, and both are writable from a test (`bankSlotsOwned`,
  `bankSlotsFull`) so the full and not-full paths are both reachable.
  `popupsShown` records what was raised, because "did the purchase dialog
  open" is the question the rack's whole point rests on.

## Go to Bank (1.2.0, Commander Orders 3.1, DECISIONS D48)

The harness loads `Commander_Events/CommanderGoButton.lua` in its TOC slot and, in the window
section, checks the footer's **Go to Bank**: hidden at the bank, shown on your own vault reopened
away from it, in the suite's words, as Commander Orders' Go button asking the locator for the
nearest banker under (Vault, bank) in the BANK tint, a click handing Orders exactly that, and
hidden on an alt's vault (not yours to open). `VAULT_UI=/path` loads a copy of
`CommanderVaultUI.lua` (added for this round). Mutants: showing it on an alt's vault and the wrong
source are killed; dropping the "remembered" test is equivalent (your own vault is remembered
exactly when the bank is shut).


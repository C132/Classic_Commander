# Commander_Vault — decisions

Numbered so later work can argue with them by name.

**D1 — A new module, not more of Commander_Bags.** Bags decorates Blizzard's
container frames in place; the vault replaces a window and adds a model, a
query language and an advisor behind it. Sharing a settings page would have
made both of them worse. The item art (quality ring, bind padlock) is
deliberately *duplicated* from Bags rather than shared: the suite has no
common item-art layer, both copies are ~80 lines, and inventing a shared one
would have meant touching a module the player uses every session.

**D2 — Own the item buttons; do not use ContainerFrameItemButtonTemplate.**
That template reads its bag id off its *parent* frame, which is the one
assumption a unified grid breaks — here a single parent holds slots from eight
different containers. Container items are not protected on this client, so a
plain `Button` can pick up, split, use and link them.

**D3 — Never hide BankFrame.** Its `OnHide` calls `CloseBankFrame()`, so
hiding it would shut the banker's session the instant the vault opened. The
takeover moves it off-screen at alpha 0 and puts it back, point for point, on
`BANKFRAME_CLOSED`.

**D4 — Transfers borrow `UseContainerItem` rather than reimplementing a swap
dance.** With the bank frame open that call already means "put this where it
belongs", and it handles partial-stack merging on the way. The cost is that
the *same call with the bank closed uses the item*, so `BankIsUsable()` is
re-checked on every tick, not merely at the start.

**D5 — The snapshot is written through to a SavedVariable.** The container API
answers for bank containers only between `BANKFRAME_OPENED` and
`BANKFRAME_CLOSED`; without a cache, "in your bank" and "gone" are the same
answer, and a vault you can only read while standing in it is the window the
client already ships.

**D6 — The final scan happens BEFORE the open flag flips.** Container caches
are still readable during the `BANKFRAME_CLOSED` dispatch. Flipping first and
scanning after would overwrite a good snapshot with the empty reads that
follow. (Same trap Commander_Quartermaster documents for its mail scan.)

**D7 — Dwell time is stamped per itemID and cleared when the item leaves.** An
item that is withdrawn and put back starts its clock again rather than reading
as ancient, which is what makes "untouched for 60 days" a claim worth acting
on.

**D8 — Search terms AND, never OR.** A bank search is a narrowing search; an
OR would make the second word widen the result set, which is the opposite of
what typing a second word feels like it should do.

**D9 — Display order is the sort order, whether or not the sort has run.** The
grid always reads as organized; running the sort is what makes the underlying
bank agree with what you were already looking at.

**D10 — Every comparator carries an itemID+count tail.** `table.sort` is
unstable and the plan is recomputed every tick; under a partial order two tied
stacks flip between arrangements and the executor ping-pongs them forever.
Ties may only happen between literally identical stacks, which the executor
reads as already in place. (Learned in Commander_Bags. Do not remove it.)

**D11 — Findings carry a search string, not just prose.** Clicking a line
filters the grid to exactly the items it named, so the report is never advice
you then have to go and act on by hand.

**D12 — The Quartermaster hand-off is one function, read-only, one-directional.**
`CommanderQuartermaster_LoadoutState()` was added to that module (it returns
the readiness table its `/cqm ready` was already printing) rather than having
the vault reach into its internals. With Quartermaster absent the rule simply
does not fire.

**D13 — The tooltip line hooks `OnTooltipSetItem`, with a stamp.** That hook is
what Commander_Tooltip has used in production on this client since 2.1.0. It
fires more than once per hover, so the lines are stamped with the link they
were written for and skipped on a repeat; the stamp is cleared on both
`OnTooltipCleared` and `OnHide`, because either can be how a tooltip goes away
and a stale stamp silences the *next* item. Where the client offers
`TooltipDataProcessor` that path is preferred instead — on clients that ship
it, `OnTooltipSetItem` runs before the data is settled.

**D14 — An alt's vault is read-only, and says so by subtraction.** Selecting a
character in the Roster swaps the grid to their remembered vault; the Sort and
Deposit buttons are *removed*, not disabled, because a greyed button invites
the question of what would un-grey it. The played character is never read from
the cache — `GetItemCount` answers for your own bank even with the bank shut,
and the cache is only ever the right source for somebody who is not logged in.

**D15 — A drop on the window goes to the first free slot and nowhere else.**
Dropping onto a window is a coarse gesture; a drop that displaced something
would be a coarse gesture with consequences.

**D16 — The clutter rules ask Commander_Armory what it is keeping.** A bank
full of gear the advisor would call "outclassed" is, more often than not, a PvP
set — and telling somebody to disenchant their arena shoulders is the single
worst thing this module could do. `CommanderArmory_SetItemIDs()` was added to
that module (itemID -> the set that wants it) rather than having the vault read
its SavedVariables; the unusable, outclassed, tradeable and stale rules all
step around set members, and a finding of its own says so out loud, so their
absence from the clutter list is legible rather than mysterious. Set members
also carry a small gold flag on the grid and a line on the tooltip: the answer
is given on the shoulders themselves, not only in the report. With Armory
absent, membership is empty and every rule behaves exactly as before.

**D17 — Withdraw takes a predicate, and its first offer is the search.** "Take
out everything I am looking at" is the transfer people actually want, and it
means the search language doubles as the selection language for bulk moves.
The Quartermaster's BANKED set is the second offer, shared with the report's
finding through one accessor so the button and the sentence can never disagree.

**D18 (superseded by D34) — A tooltip source is judged by whether it produced
lines, never by `pcall`.** Filling a tooltip from a slot can fail *quietly*: the call does not
error, it simply yields nothing. `pcall` answers "did it error", which is a
different question, so a quiet failure read as success and the fallback never
ran — an empty tooltip box. Every attempt now checks `NumLines()` and tries the
next source (slot, then link, then item id), and with all three dead it says
the client has not sent the details rather than showing nothing.

**D19 — The vault's own slots suppress the global counts layer.** That layer
hooks `OnTooltipSetItem`, which the vault's own `SetBagItem` fires, so its
Vault/Bags/Alts block landed *inside* the item text and the slot's own lines
landed after it. On a unique helm that is invisible; on a stack of cloth it is
two overlapping walls of numbers, which is what "weird tooltips for anything
that isn't equipment" turned out to mean. The flag is set around the fill only,
so tooltips everywhere else in the game keep their counts.

**D20 — Bank is the default frame style.** The module replaces the bank window,
so it should look like one: the stock stone background
(`Interface\BankFrame\Bank-Background`, the same file Blizzard tiles behind the
real thing), the era's gold dialog border, its carved header plate, and a stone
socket behind every item. Window and Dark Panel remain for anyone who prefers
the suite's newer chrome.

**D21 — A section you named beats every rule the module has, greys included.**
The item class is a decent guess and a poor filing system: "Raid Consumables"
is not a thing the client can infer, and it is how people actually think about
a bank. An override is somebody saying they know better, which about their own
bank they do.

**D22 — Sections are created by use and dissolve when empty.** There is no
section list to keep in step with the assignments, and no way to end up with an
empty heading nobody can get rid of. Dissolving one clears its assignments and
the items file themselves back under their item class — tidying a heading never
destroys anything.

**D23 — Filing is ctrl+right-click; plain right-click stays "move it".**
Withdrawing is the more common gesture by a wide margin and it keeps the
unmodified click. Filing works on a remembered vault and on an alt's, because
it is a judgement about the item rather than about the slot.

**D24 — Authored data lives outside `DefaultSettings`.** `ItemSection` and
`SectionOrder` are initialised in `ADDON_LOADED` rather than declared as
defaults, so Restore Defaults resets options and keeps what the player wrote.
(The Quartermaster watchlist precedent.)

**D25 — An open window is not reason enough to redraw.**
`GET_ITEM_INFO_RECEIVED` fires city-wide and constantly — every inspect, every
auction page, every passer-by's gear. The handler now checks the received
itemID against the set the last drawn snapshot was actually still waiting on,
so a capital city costs nothing instead of a full rescan and relayout every
coalescing window for as long as the vault is open. (The trap
Commander_Quartermaster documents; this module fell into it too.)

**D26 — The junk finding offers the step that is actually missing.**
Commander_Logistics already sells greys automatically at any vendor — from your
*bags*. So junk in the vault is stuck there, and "withdraw it" is the whole
remaining distance between the finding and the gold. Saying "worth 4g" without
offering that is a report rather than a tool.

**D27 — A report with no findings says so.** An empty panel reads as broken;
"Nothing to report — no junk, no split stacks, nothing gathering dust" reads as
the good news it is.

**D28 — The guild bank is read-only, and passive by default.** Reading a tab
means `QueryGuildBankTab(tab)`, and that call also moves which tab is
*selected* — so an addon that sweeps all six whenever the frame opens yanks the
view out from under anyone trying to use it. Instead: whatever tab you open is
recorded as a side effect of browsing normally, and a full sweep exists only
when asked for, restoring the tab you were on. Nothing here ever deposits or
withdraws: a guild bank has withdrawal limits and a log with your name on it,
and automating that is somebody else's module.

**D29 — A tab your rank cannot see is recorded as unreadable, never as
empty.** They are different claims, and only one of them is true. Recording
"empty" would have the tooltip confidently tell you the guild has none.

**D30 — Guild banks wear the character-record shape.** The roster, the
read-only browser and `RecordSnapshot` then need to know nothing about guild
banks at all — one extra source, no new rendering path.

**D31 — A button is actionable because of the snapshot it was painted from,
never because a bank happens to be open.** This was a real bug, and a nasty
one: browsing an alt's vault or a guild bank, the button carries *that*
record's (bag, slot), and your own bank is very likely open — you are standing
at a banker looking up what the alt has. Gating on `IsBankOpen()` meant a click
moved, withdrew, used or split YOUR item at those coordinates, an item you
never touched. `button.actionable` is stamped at paint time by the code that
knows which snapshot it is drawing. Filing stays exempt: it is a judgement
about the item, not the slot.

**D32 — Focus is only taken when the player asked for the window.** A vault
that opens because you walked up to a banker must not put the cursor in a text
box: with an edit box focused, WASD types letters instead of moving you.
`_openedDeliberately` is set by the toggle, the search keybind and the slash
command — never by `BANKFRAME_OPENED`.

**D33 — A deposit rule may build its predicate once.** `Anything Already Here`
was re-reading the whole vault per bag slot per tick, and `V.CurrentBank()`
rebuilds a snapshot outright when the bank is not open. Rules now offer either
a plain `wants` or a `build` that returns one, and `V.DepositPredicate` picks.

**D34 — A fill is verified by the tooltip's own item, not by its line count.**
D18 was right that `pcall` answers the wrong question and wrong about the
replacement. On this client `SetBagItem` does not fill for bank containers *and
still fires `OnTooltipSetItem`* — so every other addon hooked there appends to
an empty tooltip, and the line count says "filled" while the item's name is
nowhere on it. That is the reported bug, and it survived D18 untouched.
`GameTooltip:GetItem()`, matched against the itemID we asked for, is the only
signal a foreign addon cannot forge. Between attempts the reset is `SetOwner`,
not `ClearLines`: the latter empties the text but leaves the item, so a failed
fill would answer with the previous hover's — and hovering two stacks of the
same thing in a row is the common case in a bank, not a corner one.

**D35 — With every source dead, draw what the module already knows.** Name in
its quality colour, stack size, type, slot, item level, requirement, bind
state — all of it is in the model already. A stub reading "not loaded" is a
worse answer than the one that can be given.

**D36 — Price the stack, not the unit.** Unit vendor price is already on the
tooltip from Commander_Tooltip and from every auction addon; repeating it on a
single item is a third identical line. The multiplied total for a real stack is
the part nobody else works out, so that is the only case that gets a line.

**D37 — Detailed is the default, and the old default is moved once.** Grouping
shipped defaulting to `SECTION` — ten broad headings — with `DETAIL` sitting one
dropdown away, splitting equipment by the slot it goes in. That is the more
useful view for the biggest pile in most banks: "Equipment" cannot answer *have
I got a spare helm*, and "Head" answers it without being read. It was also
completely undiscoverable, because the only signpost to it was a dropdown
already displaying a perfectly reasonable answer, so nobody had cause to open
it. A better view nobody finds is not a feature, it is a rumour.

Moving the default is not enough on its own, and this is the part worth
recording. `ApplyDefaults` fills missing keys and never overwrites, so a new
default only ever reaches a *new* database; every existing install keeps
carrying the old one. That is exactly right for a value someone chose and
exactly wrong for one nobody ever saw, and the two are indistinguishable in the
saved variables — both are just `Grouping = "SECTION"`.

So the move is one-time and narrow: it fires once, only from the specific value
that used to be the default, and it writes a flag before it acts. Someone who
genuinely prefers Sections sets it back and it stays back, because the flag is
already written and the move never runs again. The flag is deliberately kept out
of `DefaultSettings` — Restore Defaults iterates that table, and a reset that
cleared the flag would re-run the move and quietly overrule the same preference
a second time.

**D38 — The bank's stone is reproduced, not borrowed.** The window claimed to
wear the stock bank's dressing and did not, and the reason is worth writing
down because the obvious fix is also wrong. `Interface\BankFrame\Bank-Background`
looks like the right file from its name and is not: it is the dark tile the
*modern* bank uses. The 2.5 bank window is one 384x512 sheet,
`Interface\BankFrame\UI-BankFrame`, with the border, the title bar, the sockets
and the stone all baked into it — which a window that resizes cannot wear.

The substitutes were measured rather than guessed. That sheet's open stone
averages 106/99/93; `Bank-Background` is 69/65/52 and distinctly olive,
`UI-Background-Rock` is 52/47/43, and `UI-Background-Marble` — despite the name,
and it was the first choice — is 13/13/13, very nearly black. A backdrop colour
*multiplies*, so no amount of tinting lifts any of them to the right tone.

Cutting a tile out of the real sheet does not work either. Its scratches were
cut for a window shown once; mirrored they read as a ribbon, cross-faded they
still read as wallpaper by the third repeat. So `Textures/BankStone.png`
reproduces the material instead of the pixels — the sheet's measured palette,
spread and grain rebuilt as periodic noise, seamless at any size with no motif
to repeat. `Textures/make_bank_stone.py` is the generator, kept beside it so the
tile is derived rather than magic.

The *sockets* are the real thing, because a socket is a fixed size: `Bank-Slot-BG`
out of `Interface\BankFrame\Bank-Parts`, at the TexCoords `BankFrame.xml` gives
it, drawn at the offsets `BankSlotsFrame_OnLoad` uses. A slot in this window is
pixel-for-pixel a slot in the window it replaces. They overhang the button they
sit behind, which is why the grid's gap widens in BANK and nowhere else.

**D39 — Hide every region the template draws, by name, from the template's own
source.** The list used to be four guessed names and three of them do not exist
on this client: `BasicFrameTemplate` here has no `NineSlice` and no `Inset`
frame. What it has is nine border pieces, a tiled title bar, a streak layer and
a marble inset — none of which were being hidden. So the "bank" window was
wearing the template's steel frame, and the two horizontal bars either side of
its title were `TopTileStreaks` showing past the header plate. `TEMPLATE_REGIONS`
is now taken from the client's `UIPanelTemplates.xml` verbatim, still guarded
per region, and `CloseButton` is deliberately kept: the bank window needs one
too, and it is the single piece of the template worth having.

**D40 — Columns are read off the window, never dictated to it.** The window
resizes from a corner grip, and the grid takes as many columns as the width
allows. A `Columns` setting that also claimed authority would spend the whole
drag fighting the grip, so it decides the width of a window that has never been
dragged and nothing else; Reset Size (or shift-clicking the grip) clears the
dragged size and hands the decision back. The relayout is gated on the column
count actually changing rather than run per frame — with the bank shut,
`CurrentBank` rebuilds a snapshot outright, and nothing on screen moves until a
column is gained or lost anyway.

Sizing is done by hand rather than with `StartSizing`, because the window is
anchored by whichever point it was last dropped on and `StartSizing` on a
CENTRE-anchored frame grows it in both directions at once — the corner under
the cursor runs away from the cursor. The drag re-anchors to TOPLEFT first,
which is also why `FramePos` now stores the *relative* point: restoring a
TOPLEFT-anchored window against relativePoint = TOPLEFT would put it a screen
away. Positions saved before this fall back to the old behaviour, which was
right for how they were made.

**D41 — The bag rack is the stock window's, and a slot you have not bought says
so in red.** Seven 26px squares carrying a dark red plus sign, overlapping the
footer text, was neither a statement of what the slots were nor a way to buy
one. The rack now carries a real socket per slot, the empty-bag art the client
ships, the stock red tint on what you have not bought, the free-slot count on
what you have, and Blizzard's own purchase row — label, running price, button —
beside it. The price turns red when you cannot afford it, which means its own
formatting rather than a wrapper: `V.Money` paints its own colour codes and an
embedded code cannot be overruled from outside.

Purchase is *removed* rather than greyed when every slot is bought, and removed
again while browsing an alt: offering to spend your gold on a bag slot for a
grid you are only looking at is the same class of mistake as withdrawing from
it (D14, D31).

**D42 — `CONFIRM_BUY_BANK_SLOT` is primed before it is raised.** That dialog's
`OnShow` does not ask the API for the price: it reads `BankFrame.nextSlotCost`,
a field only `BankFrame`'s own `PLAYER_MONEY` handler ever writes. Raised from
anywhere else it can arrive holding nil and take `MoneyFrame_Update` down with
it. The takeover leaves `BankFrame` shown, so that handler usually *has* run —
"usually" is not a guarantee worth shipping an error for, and writing the field
first costs one API call.

**D43 — Clicking a bag slot isolates that bag, and it does it through the
search box.** Every bag is already on screen, so "open the bag" has to mean
something else here, and "show me only this one" is what it wants to mean. It
sets `bag:N` in the box rather than keeping a private flag: that term is already
part of the query language, so it composes with everything else you might be
looking for, it is visible in the control that caused it, and clicking the slot
again lets go. The isolated slot wears a ring, so "why am I only seeing six
things" always has an answer on screen.

**D44 — An empty grid says which KIND of empty it is.** A blank pane reads as
broken, and there are three quite different reasons for one: the search
excluded everything, the vault genuinely holds nothing, or nobody has ever
recorded a vault for this character. Only the last is a problem, and it is the
one a new player hits first — opening the window before their first trip to a
banker and finding nothing, with nothing to say what to do about it. The state
is *named* (`V.gridEmpty`) rather than merely drawn, on the same reasoning as
`V.reportEmpty` (D27): "the grid drew nothing" and "the grid is showing good
news" are different claims and the difference is testable.

**D45 — An item's tooltip names the container it is in.** The vault runs to 28
slots plus up to seven bags, and the grid deliberately does not draw the
containers in order — that is the whole point of the grouping. So "I can see
it, where actually is it" became a question the window could not answer, and
`V.ContainerName` answers it in the player's terms: the base slots are not
"bag -1", and the first bank bag is Bank Bag 1, not Bank Bag 5.

**D46 — The search box is anchored on both sides, not given a width.** Once the
window resizes, a fixed 180px search box means the view tabs and the Sort
button climb over each other the first time it is dragged narrow. The search is
the only control on that row that is happy to be any size, so it absorbs the
slack; `MIN_W` is then set by the width at which the *rest* of the toolbar stops
colliding, which is a tighter floor than the grid's.

**D47 — Mats get their own button, and "mat" is decided by item class with a
short list of exceptions.** "Put my materials away" is what most trips to the
bank are for, so it is one click on the toolbar rather than an entry in the
Deposit menu (where it also appears, for completeness). The rule is keyed on
item class rather than on the grid section, because a stack the player filed
under a section of their own ("Enchanting") leaves the `TRADE` section and
the older Trade Goods rule stops seeing it, which is exactly the stack they
meant. Class 7 and class 3 are mats; class 5 is not, because on this
expansion Reagent means spell reagents — a priest's candles and a mage's
runes belong in the bag they are cast from. Inside class 7, Explosives and
Devices are finished goods (sapper charges, the engineer's and jeweler's
tools) and are left alone; the tools that share a subclass with their mats —
the runed rods, the Arclight Spanner, Flint and Tinder — are named, with the
rods also read from the Formulary's recipe data so a rod added there is
protected here. Anything the Quartermaster's loadout names is skipped
whatever its class: a bulk deposit must never undo a "carry this". The button
widened the toolbar's fixed content, so `MIN_W` moved from 600 to 680 by the
D46 rule.

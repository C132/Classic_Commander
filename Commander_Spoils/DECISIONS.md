# Commander Spoils — decisions

Synthesis of the v3 design study (three independent proposals: group-loot
mechanics, loot economics, information architecture). Where they disagreed, the
call and its reason are recorded here. `FINDINGS.md` holds the client facts
these decisions rest on.

---

## D1 — One frame, built out of bands

**Superseded the original four-surface split, on Devin's direct instruction:**
"why there is so many frames involved when the whole point of the design was a
single unified solution." He is right, and the earlier argument was weaker than
it looked.

Everything lives inside `CommanderSpoilsFrame`. Each thing that has something
to say is a **band** — a plain child frame that stacks under the header and
contributes zero height when it has nothing to show:

| Band | Appears when | Contains |
| --- | --- | --- |
| header | always | the at-a-glance numbers and the four chrome glyphs |
| pickups | an item worth naming was acquired | up to 4 merged notices, 5s each |
| corpse | `LOOT_OPENED` → `LOOT_CLOSED` | one row per slot, inline bind confirm, master-loot candidates |
| rolls | any roll is pending or just resolved | one row per roll, timer, N/G/P |
| panes | the player opens them | mode strip, the five panes, status line |

One position, one scale, one lock, one Escape, one chrome block in settings.
The detail popup became an overlay over the pane body rather than a fifth
frame.

**What the original split was actually protecting, and how the band handles it
instead.** The load-bearing claim was FrameXML's `LootFrame_OnHide` → 
`CloseLoot()`: a corpse surface's visibility *is* a server session, so a
browsing window that also holds the corpse would abort a live loot session when
closed. That hazard is real, but it is Blizzard's frame doing it to itself — we
control our own `OnHide`, and the correct fix is a guard, not a second window.
The frame's `OnHide` ends the loot session **only** when the corpse band is up,
the session is genuinely open, and `UIParent` is still visible (so Alt-Z, a
cinematic, or a restyle never do it).

The second claim was position: looting is a spatial act at a corpse, reading a
ledger is not. That one survives as a rule rather than a frame — collapsed, the
frame follows the cursor to the corpse and returns to its saved point
afterwards; with the panes open it never moves.

The third was frequency, and it dissolves entirely: the frame is exactly as
tall as what it currently has to tell you, so a corpse with three slots is a
three-row window.

## D2 — The two coherence rules

**R1. The bands open the frame; the panes never do.** A roll has a deadline and
has earned an interruption. A ledger has not, and a full window appearing over
the action bars mid-pull is a wipe. So the frame shows itself for a pickup, a
corpse or a roll, and the panes only ever open because the player asked.

**R2. Every transient has a permanent home.** Every pickup notice, every roll,
every loot session becomes a FEED row and a HAUL entry. This is the promise
that makes suppressing chat safe: the information did not get deleted, it
moved. Pickup notices suppress themselves while the panes are open **on FEED
and at scroll-top** — all three clauses, because the scroll lock (D19) means a
scrolled-back player would otherwise get neither the notice nor a visible row.

## D2b — Field report, 2026-08-05

Devin ran it. Six things came back, and four of them were defects rather than
preferences.

**The chrome did not fit the frame.** The header and the mode strip used
offsets hardcoded for a 420px window; at 350 the elastic best-find field's left
edge sat to the *right* of its own right edge, and five 62px mode buttons plus
a 90px scope needed 418px of a 350px strip. Everything is now derived from the
real width — fixed fields keep their size, the elastic one hides below the
width where it would collide rather than rendering on top of a neighbour, and
the body's own columns scale too. Default width is 350.

**Roll rows overlapped.** The note shared the bottom line with the buttons and
the timer strip ran under both. A roll row is now three lines that never share
space — title + countdown, slot + timer strip, buttons + who has decided — and
dense mode drops the *timer strip*, not the buttons.

**Fixed size.** `FixedSize` (default on) caps every band, so the window stops
resizing every time a roll opens or a corpse is bigger than the last. Overflow
is stated (`+3 MORE`, `8 of 14 — take some to see the rest`), never silent.

**HAUL showed an item twice.** The fold pooled its per-item rows *by index*, so
a row held across two folds could come back pointing at a different item. The
pool is now keyed by itemID — a given table is only ever that item's, which is
alias-safe and still allocation-free. The same pass found that the fold cache
had stopped being invalidated on a normal record.

**ROLLS did not show what it exists to show.** Every participant is now an
inline row under its contest — name, class colour, Need/Greed/Pass, the number
they rolled, the winner starred — for the whole session, rather than hidden
behind a click-through popup. That popup is gone entirely, which also removes
the last thing that drew over something else.

**FEED was noise.** Consecutive pickups of the same item merge into one row
with a running total, and consecutive coin merges the same way. Twenty rows of
"Netherweave Cloth x5" is not a feed.

## D2c — Repainting is dirty-driven

The window used to rebuild five list buffers twice a second, forever, whether
or not anything had happened — with a 300-entry feed scanned every pass. That
is what a loot window has no business costing, and it was the reported lag.

Repaints now happen when something actually changes. The only thing that
genuinely wants a clock is the relative-age column, so that became its own
pass: one `SetText` per visible row, once a second, and a `LiveAges` setting
that turns it into a fixed clock time and stops the periodic work entirely.
The roll ticker dropped from 10 Hz to 5 Hz and still runs only while a roll is
on screen. With nothing pending, nothing dirty and no glow settling, the
`OnUpdate` is one comparison and a return.

## D3 — Five modes, one shared scope

`FEED · HAUL · ROLLS · BAGS · PARTY`, a labelled button strip, not a dropdown
and not Blizzard tabs.

Meters is right to use a dropdown — nine modes in a 240px window degrade to
cryptic glyphs in a strip. Spoils has five modes in a 420px window where full
labels fit. Two things a dropdown cannot do and this product needs: carry a
badge (FEED needs an unread count, ROLLS a live pip, BAGS a full-bags warning —
a menu item that is off screen cannot signal), and act as a visible table of
contents so a player arriving with a question sees that the product has an
answer without clicking.

Scope (`SESSION · RUN · HOUR`) is shared across every pane, exactly as Meters
shares one segment across two panes. BAGS has no time dimension: its scope
button dims and reads `NOW` rather than silently doing nothing.

Default mode is FEED. It is the chat-frame replacement, and the chat frame is
what we deleted.

**PARTY stays** despite the IA proposal to cut it — understanding party income
is an explicit requirement, not an inferred one. It ships with its ceiling
stated on the pane (D9).

## D4 — Suppression is a safety surface, and restore must be exact

Nine independent switches, all runtime-only — a replaced function pointer, an
event registration, a chat filter. **Nothing is written anywhere that outlives
the addon**, so disabling Commander_Spoils in the addon list restores Blizzard
by construction. That happens to be true and it goes in the settings panel
verbatim.

`SuppressItemPush` defaults **off**. The flying bag icon is ambient feedback
nobody complains about; turning off something the user never asked us to touch
is how a takeover becomes a violation.

There is no event-enumeration API on 2.5.6. So restore is not approximated:
each suppressed frame's FrameXML event list is hardcoded, each event is probed
with `IsEventRegistered` before unregistering, and the exact set that was on is
stored and re-registered on restore. Approximating this is the failure mode
where restore silently leaves one event dead and the bug surfaces weeks later.

Chat is suppressed with `ChatFrameUtil.AddMessageEventFilter` only. Never
`chatFrame:RemoveMessageGroup("LOOT")` — that writes the character's saved chat
settings and is not reversible in the sense that matters.

**Three exit paths, all restore**: the master switch off, the addon disabled
in the addon list, and `/cspoils restore`. There is deliberately no
`PLAYER_LOGOUT` handler — every suppression is a live function pointer, a live
event registration or a live chat filter, none of which survive the session, so
there is nothing to hand back at logout and a handler there would only invite a
future edit that persists something.

## D5 — The panic button lives in the file that cannot fail

`CommanderSpoils_Suppression` and the `restore` slash handler live in
`CommanderSpoilsDB.lua`, which loads first and depends on nothing but
`Commander.UI`. If the engine or the frame file errors at login, the panic
button still works.

And the automatic version: the frame file sets `CommanderSpoils_Ready` at the
end of its login handler; the DB file checks it two seconds later and, if
unset, **restores everything and prints a warning**. A player must never end up
with Blizzard's loot UI dead and no replacement. This is the most important
idea in the whole module.

The watchdog also **blocks** the suppression layer for the rest of the session
rather than merely undoing it once. Undoing without blocking left an obvious
hole: the settings page lives in the file that *did* load, so a player opening
it to investigate the warning would re-break their own loot UI with a single
checkbox. `/cspoils restore` clears the block. The watchdog deliberately does
not untick the switches — a transient failure should not permanently disable a
takeover the player chose.

## D6 — Two ledgers, one reconciler

Chat is the event stream; bags are the balance sheet. They fail in opposite
directions and the design needs both — as two ledgers with one reconciler, not
as one merged truth.

Chat sees what bag-diffing structurally cannot: **attribution** (looted vs
pushed vs crafted — a bag diff cannot tell 20 cloth from a corpse from 20 from
the mail), **granularity** (five pulls of 5 cloth is five events and one `+25`),
and things that arrive and leave inside one settle window.

Bag-diffing sees what chat structurally cannot: **every removal**. There is no
"you lost X" chat line at all — crafting, consuming, vendoring, mailing,
trading, destroying are all invisible to chat.

So: `residual = observedBagDelta − expectedDeltaFromChatEvents`. A positive
residual with no chat event is an acquisition off a non-loot path, filed as
`OTHER`. A negative residual is consumption, attributed **from context flags,
not from the item** — which window is open at the settle tick decides it
(merchant → vendored, trade → traded, mail → mailed, a `QUEST_TURNED_IN` this
tick → quest, a create line this tick → crafted, else used).

**Bank-open suppresses the reconciler entirely.** Bank bags are only readable
while the bank is open, so to a bags-only census a deposit is indistinguishable
from destroying the item. Same suppression for an equipment change in the same
tick.

Precedence: the census wins for *how much*, chat wins for *where from*. The
reconciler may only add `OTHER` and outflow rows; it never rewrites a
chat-attributed row.

`ITEM_PUSH` is **not** a data source — its payload is a bag *button* id and an
icon, with no itemID and no count. It is a suppression target only.

## D7 — One debounced settle tick

`BAG_UPDATE_DELAYED` can beat the chat line for the same loot. Arm
`C_Timer.After(0.3, Settle)`, re-arm on every loot chat line, hard-cap at 1.5s
so a long autoloot burst still settles. One settle → census rebuild →
reconcile → one notify.

The census is keyed `itemID → count`, never a slot map. Slot-keyed diffing
emits phantom move events on every bag sort, and Commander_Bags ships a sort
engine that will fire it.

Never raw `BAG_UPDATE`: Inventory and Bags already take it, and a loot burst is
the suite's worst CPU case in the whole suite.

## D8 — Classify from the integer class pair, never the name

`Armor/Cloth` is `4/1`. `Tradegoods/Cloth` is `7/5`. A Netherweave Robe and
Netherweave Cloth both return the string `"Cloth"` as `itemSubType`, which is
the third and most tempting return of `GetItemInfoInstant`. Any name-keyed
classifier files gear as materials and the bug is invisible until someone farms
a humanoid zone.

So buckets key off `(classID, subClassID)` integers from
`C_Item.GetItemInfoInstant` — synchronous, never nil for a real itemID, no
`GET_ITEM_INFO_RECEIVED` dependency. Display names come from
`C_Item.GetItemSubClassInfo`, which is locale-correct and ships no strings.

Motes and Primals share subclass `7/10` and no cheap heuristic separates them
honestly. We do not try — the bucket reads "Elemental" and item rows carry the
names.

Profession detection is cut. TBC has no `GetProfessions()`; it is skill-line
scanning for the payoff of a highlight color, and the player knows their own
professions. A settings multi-select is three clicks and always correct.

## D9 — Say what the sensors cannot see, on the surface

There is no addon-message channel anywhere in this suite, so party awareness is
bounded by what the client tells us directly: other players' `LOOT_ITEM` chat
lines (range-limited outdoors), `C_LootHistory`, the loot method, and the
roster. Other players' gold, bags, and gear are **not knowable**.

The PARTY pane therefore carries its ceiling inline, always visible, never
buried in a tooltip: *derived from loot messages in range; gold is yours only.*
Every addon that quietly presents inferred data as fact eventually gets caught
being wrong. Stating the limit is a quality signal, not an apology.

For the same reason the live roll row reads `3 rolled`, never `3/5`.
`numPlayers` counts players who have *decided*; there is no reliable count of
eligible-but-undecided players, because group size is not eligibility.
Fabricating a denominator is the kind of small lie that surfaces later as a bug.

## D10 — Never miss a roll: aggregate urgency, and no auto-need

A 10Hz ticker runs **only while a roll is pending**. Sound and screen-edge glow
are computed across the whole Contest strip, once per stage transition — never
per row. Six greens expiring in the same second must produce one chime, not six.
Per-row audio in a wave pull is unusable and is the fastest way to make the
feature hated.

Rows are ordered by insertion and **never re-sorted** — oldest is also
soonest-to-expire, so the stable order is the urgent order, and any re-sort
moves a row under a moving cursor. A 300ms misclick guard arms each new row and
re-arms on any row that moves more than 8px during a collapse.

An expired unactioned roll is marked `MISSED` and logged. The honest half of
"never miss a roll" is that the addon must also be able to tell you it failed
you.

Automation ships as exactly two rules — `AutoPassBelowQuality` (default off,
and always leaves a visible ghost row so the player can never be quietly robbed
by their own settings) and `CollapseIneligible` (default on, because in 25s you
are ineligible for half of every drop).

**No auto-need. Ever. Not as a setting.** There is no configuration of that
feature which is not a griefing tool.

Two details the first implementation got wrong and the harness now pins. The
open chime fires from the roll's `start` phase, not from the urgency ladder:
the ladder's first stage is the 15-second warning, so chiming from there
arrived 45 seconds late on a 60-second roll — worse than no alert. And a roll
the player was never eligible for is **not** marked MISSED; a mage accumulating
a miss for every plate drop in Karazhan turns the one metric that matters into
noise.

## D11 — Master loot is not a feature, it is the cost of suppression

Suppressing `LootFrame` removes the only place master loot can be initiated. An
ML running Spoils without a candidate pane cannot distribute loot at all, and
there is no graceful degradation. The alternative — leave Blizzard's loot window
alive when the method is master loot — is worse: a UI that is sometimes ours and
sometimes Blizzard's is more confusing than one that is always ours.

So the minimum ships and nothing more: sparse candidate probe `1..40` (the raw
probe index is what `GiveMasterLoot` takes — **not** a position in the sorted
display list, which is the most likely bug in this module), class colors,
online/dead state, and a two-step arm-then-confirm. The arm step is not
redundant UX: it is the replacement for the `CONFIRM_LOOT_DISTRIBUTION` popup we
suppressed.

Cut hard: loot council, voting, DKP/EPGP, MS/OS response collection, whispering
candidates, session export. That is a different addon and most of it is
unbuildable without the comms channel this suite deliberately lacks.

## D12 — Positional history rows

SavedVariables is serialized as Lua source, and **key names are repeated on
every row** — they dominate the file, not the values. A named row costs ~200
bytes; the same row positional costs ~55.

```lua
-- events[i] = { t, itemID, count, quality, bucket, unitValue, srcKind, srcID, mapID, seg }
events[i] = { 1754400000, 21877, 5, 1, 3, 300, 1, 18692, 1951, 3 }
```

Four times the retention for one comment documenting field order. Every string
is interned — `names[creatureID]`, `zones[mapID]` — so rows carry integers only.

Retention: raw events ring-capped at 2000, segment summaries 200, roll log 400
(with per-player detail as **packed strings** rather than nested tables, kept
only for the newest 100), lifetime item totals 1200. Rollup runs on segment
close and on `PLAYER_LOGOUT` — never on a ticker — because logout is exactly
when the file is written, so compaction never costs anything during play.

Migration policy: `Data.v` is stamped, and on mismatch the data is wiped with
one printed line. Writing migration code for a personal addon's telemetry buys a
bug surface against data that is not precious enough to justify it.

## D13 — Value has three tiers and they are never blended

**Vendor** is the floor and the headline, always labelled VENDOR, never "gold".
`nil` and `0` are different facts — nil means retry, zero means genuinely
unsellable — and conflating them silently zeroes the totals.

**Market** appears only when Auctionator answers, soft-probed through a single
`pcall` (its API `error()`s on a bad caller id), lazily on first valuation and
re-armed by `RegisterForDBUpdate` because it returns nil until its database
initializes. Gated on freshness: ≤1d normal, ≤3d amber with a `~`, older dimmed,
never-seen shows **nothing rather than zero**. The tile carries a coverage
percent — that one number is the entire credibility of the tile.

**Nothing** renders an em-dash. `ValueMode` chooses which drives the rate, and
the metric's label changes with it. Never a silent blend.

## D14 — Segments are index ranges, not counters

Three concurrent segments over one event log: **session** (auto,
`Commander.RestoreSession`, 600s resume), **run** (auto, instance with a 180s
exit grace — Commander_Economy's rule, deliberately duplicated with a comment
pointing at it until Economy publishes its segment on the bus), and **farm**
(manual, because no heuristic knows when a player started farming).

Every segment stat is a fold over its index range, computed on demand and
cached. Zero duplicated counters means there is no counter-sync bug to have,
and reload-resilience is free because the log is persisted anyway. The farm
segment lives outside `db.Session` deliberately — a farm can span a client
restart and must not die to the 600s resume window.

Live rate is a **5-minute trailing window** off a 60-slot per-minute ring, shown
against the session average. "Since session start" lags reality badly forty
minutes in, and the gap between the two numbers is itself information.

## D15 — Rejected metrics

Per-source attribution runs off `GetLootSourceInfo`'s per-slot GUID, with the
`UnitName("target")` heuristic only as a fallback and only when the target is
actually dead — a live retargeted mob is not a credible loot source, and
crediting it puts the drop on the wrong creature in exactly the AoE-farming
case the per-slot API exists for. The probe memoizes only a *positive* result,
because probing an already-autolooted corpse returns nothing and latching that
would disable attribution for the session.

The per-source drop table is collected but not yet surfaced in the UI; that is
recorded in BACKLOG.md rather than claimed here.

**Global rare-drop-rate as `rares / total`** is meaningless — it is dominated by
how many greys a mob type drops, so a cloth farm and a boss run produce
incomparable numbers. The honest version is per-source (`times this creature
dropped this item / times you looted this creature`), which
`GetLootSourceInfo` makes computable now that it is verified present.

**Lifetime rates** average AFK time into the denominator. Lifetime gets totals
and bests only.

**XP/hour, kills, deaths** are Commander_Economy's job.

## D16 — Interest model: pins, six switches, and a floor

Replacing `MinQuality` with a quality × class matrix would be 136 cells nobody
fills. Instead a rule list, first match wins:

1. **Pins** — right-click any row → always/never toast this item. The
   expressive part of the model is built *by using the product*, at the exact
   moment of annoyance or delight, and costs one context-menu entry.
2. **Six class switches** named the way players talk: gear for my armor type,
   recipes, trade goods, consumables, quest items, anything BoP. Honest naming —
   "gear for my armor type", not "gear I can use", because weapon usability is
   not cleanly derivable here and a filter that claims more precision than it
   has is worse than one that names its limit.
3. **Quality floor** — kept, demoted to the bottom rule, deciding only the
   unmatched case.

The FEED's own filter is **not** configurable: three positions, `ALL / MINE /
NOTABLE`, on the status line. No search box, ever — a text field in a HUD frame
is a keyboard trap in combat.

## D17 — Notification tiers

**Alert** (sound + motion): a roll you are eligible for, and a roll you won.
That is the complete list — rolls are the only loot event with a deadline, and a
deadline is what earns an interruption.

**Toast**: an item passing the interest model. **Not money** — money is the
highest-frequency loot event in the game and toasting it recreates exactly the
spam we deleted. One exception: a loot split ≥ 1g.

**Quiet**: a FEED row. Everything else.

There is no fourth tier. Nothing is ever silently dropped: the FEED filter can
*hide* rows, but the data keeps everything and the status line always reads
`N FILTERED`.

## D18 — Color has four exhaustive jurisdictions

```
item quality  →  item names.    Only item names.
class color   →  player names.  Only player names.
gold/silver   →  money.         Only money.
the accent    →  live / selected / active / new.  Only state.
```

Nothing else gets a color without a written justification here, no color fills
more than 40% alpha behind text, and **quality color may never touch a
background**. It colors thirteen characters of text or it does not exist. The
pull toward quality-tinted row backgrounds and gradient timer bars is the
slot-machine look every loot addon eventually acquires.

One moving element in the whole product: the roll timer bar, because there the
motion *is* the information.

## D19 — The scroll-lock pill

New rows never move a scrolled view. `▲ 3 NEW` appears on the status line;
clicking it jumps to top. This single behavior is the entire difference between
a feed and a chat log that fights you.

## D20 — Growth ceilings, written down so they are not re-litigated

**Five modes is the ceiling.** Loot addons accrete — Rares, BoEs, Wishlist,
Attendance, Loot Council. A new question becomes a detail popup off an existing
row or a scope option, never a new mode button. The enforcement is physical: at
420px six labels do not fit, and `FrameWidth` may not grow to make room.

**A toast must be actionable within its four-second life.** Money already
landed; there is nothing to do; it gets a feed line. Every future feature is
tested against this rule.

**Preference ceiling is twenty-five**, plus one HudChrome block — the
unification (D1) removed three of the four chrome blocks outright.
This started at ten, derived for a narrower cut of the design that dropped the
PARTY pane and the interest model's class switches. Both came back as explicit
requirements, and the count is what it is: 1 master + 1 appearance + 2 geometry
+ 5 rolls + 8 interest/notification + 1 loot anchor + 4 ledger + 3 sounds. Each
block is one coherent question, which is the property that actually matters —
but the number is recorded honestly rather than quietly exceeded. The nine
suppressions are exempt: they are a safety surface, not preferences.

## D22 — Reconciled acquisitions are logged but are not income

The reconciler files any unexplained bag gain as `OTHER` (D6), which is right —
a mail collection or a vendor purchase really did enter the player's
possession. But nothing downstream may treat it as *income*: buying forty
Netherweave must not raise a toast, must not flash the screen, must not enter
the per-hour rate, and must not become the session's "best find". `E.Fold`
totals it into a separate `otherValue` that the header tooltip discloses, and
the toast path drops it outright.

The same reasoning applies in reverse to gold: there is exactly one gold
counter, a persisted log of coin events, and every scope folds it out by
timestamp. Per-segment gold counters meant HOUR silently reported zero coin
under the same VENDOR label, and a `/reload` zeroed the session total while
item totals survived.

## D21 — Spoils becomes the suite's single loot parser

Three modules currently run near-identical `CHAT_MSG_LOOT` regexes
(Spoils, Economy `:735`, Objectives `:487`) with three quality-color tables
that will drift. Spoils publishes `COMMANDER_SPOILS_LOOT` and the others can
subscribe.

The published entry table is **pooled and recycled**. `Commander.Notify` is a
synchronous in-process fanout, so subscribers may read it inside the callback
and must not retain it. With three modules subscribing, a shared mutable table
across a pcall'd fanout is exactly the bug that takes a week to find — so it is
documented loudly at the definition.

Spoils publishes its loot-money subtotal; Economy keeps the master earned/spent
pair off `PLAYER_MONEY`. Two ledgers, one owner each.

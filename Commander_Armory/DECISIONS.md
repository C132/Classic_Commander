# Commander_Armory — decisions

Numbered so code comments and future sessions can cite them.

## D1 — We own the set storage. `C_EquipmentSet` is not used.

The `C_EquipmentSet` namespace does exist on this client — proved by a TBC-loaded call site in
Blizzard's own `SecureTemplates.lua`, which calls `GetEquipmentSetID`/`UseEquipmentSet`. What is
*not* provable from source is whether the **server** enables equipment sets for the TBC game type.
`CanUseEquipmentSets()` is the client's own capability gate and it is never called anywhere in the
shipped UI, so nothing in the source says what it returns here. Equipment Manager was a 3.1
feature; "the namespace is present but the realm returns nothing" is an entirely plausible outcome.

The obvious response is a storage interface with two adapters. We are not doing that either, and
the reason is that the native path buys us almost nothing while costing us a second implementation
of everything:

- Our own sequencer is needed regardless, for the single-slot flyout swaps that are the module's
  headline feature. `UseEquipmentSet` cannot express "put this one ring on".
- Per-slot exclusion has to behave the way D3 describes, and Blizzard's own API is documented as
  unable to tell an ignored slot from an unequippable one.
- Server sets are capped in number and are invisible to an alt.
- The pre-flight verdict (D8) requires us to model the swap before running it, which means we own
  the plan whether or not something else executes it.

There is a further fact that settles it even if the server *does* support sets:
`MAX_EQUIPMENT_SETS_PER_PLAYER = 10` is defined in the constants file this client loads on TBC.
Ten. Our own storage has no cap, and "unlimited sets" is not a nicety on a client where a hybrid
keeps separate healing, damage, tanking, resilience and hit-swap kits and then wants a fishing
outfit as well.

So there is one path. It always works, it is fully testable headless, and it does not depend on an
answer we cannot get without logging in. The module still probes `CanUseEquipmentSets()` once at
login and records the result, because it is a fact worth knowing (ASSUMPTIONS A1) — but nothing
branches on it.

Worth recording for whoever revisits this: the evidence that the native path works is stronger than
"the symbol exists". The client binary carries the *network* type for equipment-set data, not just
the Lua bindings; a published addon consumes the API with no fallback at all and ships screenshots
of a populated set list; and an unrelated addon's bug report contains a working create-and-use repro
on 2.5.5. Against that, Classic Era exposes the identical symbol surface while having no such game
feature — so presence alone proves nothing, and the case rests on the behavioural reports. None of
which changes the decision, because the cap and the per-slot-exclusion requirement would rule it out
regardless.

## D2 — Sets are per character, in a second SavedVariable

`CommanderArmoryDB` holds settings; `CommanderArmorySets` holds the sets, the bank cache and the
per-slot hidden-item list. The Dossier and Quartermaster precedent: restoring settings to defaults
must never cost a player their gear sets, and the two have completely different lifetimes. Restore
Defaults says so in its tooltip; only `/cgear wipe`, which asks first, can empty the sets.

Sets are keyed by `realm .. "\001" .. name` inside an account-wide file rather than living in a
per-character SavedVariables file. That is the suite's uniform approach — there are no
`SavedVariablesPerCharacter` files anywhere in it — and it has a concrete payoff here: an alt can
be shown the sets it does not own, which is what makes import/export and "copy from" possible
later without a schema change.

## D3 — A slot entry has three states, and IGNORED is not EMPTY

This is the most important invariant in the module.

- **ITEM** — put this item here.
- **IGNORED** — do not touch this slot. Nothing equipped, nothing removed.
- **EMPTY** — this slot should be bare. Whatever is there is moved to a bag.

Blizzard's own API conflates the last two — the wiki admits `GetItemLocations` "does not
differentiate between slots that cannot be equipped and slots that you have chosen to ignore" —
and the resulting bug, ignore *stripping* the slot instead of leaving it, is the single most
reported complaint about the retail Equipment Manager. A player who ignores their tabard slot
means "leave my guild tabard alone", never "take it off".

**A slot with no entry at all is IGNORED**, not EMPTY. That makes a partially authored set safe by
default, and it means that if a future patch adds a slot to the canon, every existing set does not
suddenly start stripping it.

**One honest exception**, stated here rather than hidden in a comment: when a set puts a two-handed
weapon in the main hand, the client displaces whatever is in the off-hand into your bags — whether
or not the off-hand is ignored. There is no way to plan around that; it is what the client does. So
a plan involving a two-hander reserves a bag slot for slot 17 even when slot 17 is ignored, and the
off-hand does come off. Pretending the invariant is absolute would mean a set that fails when bags
are full, which is exactly the half-applied outcome the module exists to prevent.

The exception is narrower than "a two-hander touches slot 17", and the narrowness is the point. It
applies **only when the set is silent about the off-hand.** If the set says `EMPTY`, the player has
already consented to that slot being cleared. If the set names an off-hand item, we refuse the plan
outright, because a set asking for both a two-hander and an off-hand is incoherent and equipping it
half-way would be worse than saying so. So the invariant is overridden in exactly one case: where
the player expressed no preference and the client leaves us no choice.

And in that case we **warn rather than refuse**. The swap is legal and the player asked for it; they
just need to be told before anything moves, naming the off-hand that is about to come off and the
two-hander causing it. Refusing would be the false-refusal failure of D3a; staying silent would make
the invariant a lie. A warning is the only honest third option — which is why `plan.reasons` entries
now carry a `warning` flag, and why callers must key "is this blocked" off `plan.ok` rather than off
the presence of any reason at all.

## D3a — A conflict we cannot prove is a conflict we attempt

The pre-flight refuses only what it *knows* will fail. The first draft of the gem-conflict rule
flagged any two target items sharing a gem id, and that was wrong: in TBC, cutting several pieces
with the same Living Ruby is not an edge case, it is how everyone gems. The rule would have refused
a large share of perfectly legal sets.

That is worse than the bug it prevents. D8's principle is "never start what you cannot finish", not
"refuse anything that might not work". A false refusal blocks a working set with no recourse and
makes the module look broken; a rare unproven conflict costs one refused action, which the runner
reports and recovers from. So the rule now fires only on gems actually known to be unique-equipped,
and an unknown gem is attempted — with the server's own `ERR_ITEM_UNIQUE_EQUIPPABLE` as the
backstop, which is why that watcher exists.

The general form, worth keeping in mind anywhere else this comes up: **certainty refuses,
uncertainty attempts.**

## D4 — Ammo is outside the set model

Slot 0 is not in `D.Slots`, never appears in a snapshot, never appears in a plan, and has no
flyout. Four independent reasons, any one of which would be enough:

- It is a depleting consumable. "Restore exactly this" is the wrong verb for something that runs
  out mid-raid.
- `PickupInventoryItem(0)` does not work. ItemRack carries an explicit workaround that targets slot
  18 instead and lets the client route the ammo.
- Its character-panel button does not inherit `PaperDollItemSlotButtonTemplate`, so none of the
  `PaperDollItemSlotButton_*` hooks the flyout is built on reach it.
- Blizzard hides it outright for classes with a relic slot, and excludes it from its own flyouts.

## D5 — Cosmetic slots are ignored by default when capturing a set

Shirt and tabard carry no stats. A player saving a PvP set means "this is my resilience gear", not
"and also put my guild tabard back on". Blizzard's silent stripping of shirt and tabard on every
set swap is a documented, long-running complaint. The default is overridable per capture
(`CaptureCosmetic`), because someone with a transmog-ish habit of matching tabards to sets exists
and is not wrong.

## D6 — The identity key keeps the decoration and drops the instance seed

A saved entry stores `itemID:suffixID:enchant:gem1:gem2:gem3:gem4`, plus a base key of
`itemID:suffixID` for loose matching.

- **suffixID stays** because "of the Bear" and "of the Owl" are genuinely different items to the
  player, and a set that asks for the stamina version must not equip the spirit one.
- **enchant and gems stay** because a player holding an enchanted and an unenchanted copy of the
  same sword means the enchanted one, and because TBC's unique-equipped meta gems make two
  identically-named pieces behave differently.
- **`uniqueID` is dropped**, and the usual reason given for dropping it is wrong in a way worth
  correcting here, because the wrong reason would lead someone to put it back. It is *not* simply
  "a per-instance value that differs between copies". It decomposes into two halves and neither
  carries identity: the low 16 bits are the suffix factor, which the server generates as a pure
  function of the item template — same item, same value, every time, on every copy — and the high
  16 bits are documented as random noise. So the meaningful half is redundant with `itemID` and the
  other half is unusable. Keeping it makes every saved key unmatchable, every set reports every
  item missing, and the failure is completely silent.
- **`linkLevel` is dropped** — it describes the viewer, not the item. This is the field that breaks
  the incumbent addon: it stores the raw payload including the level, its repair function silently
  stopped working on this client's link format, and so after any level-up every exact match fails
  and degrades to bare-itemID matching, ignoring enchant, gems and suffix alike. Invisible at 70,
  broken the whole way up. Normalizing at write time is what makes that class impossible.

Real links on this client carry **19 fields** and emit empty fields as **empty strings, not zeros**
(`25059::::::-36:1830748181:60::::::::::`), so the parser normalizes empties to `0` and tolerates
negative suffix ids. A pleasant side effect: legacy 10-field strings collapse to the same key, so
any older saved data migrates for free.

Matching is exact-first, then loose, and the UI says which it used. A loose match is usually right
(you re-enchanted the sword) and occasionally wrong (you have two), so it is reported rather than
hidden. The loose key keeps `suffixID` — the incumbent's loose match is itemID only, which will
cheerfully equip an "of the Owl" when the set asked for "of the Bear".

## D6a — Telling two identical items apart is an allocation problem, not an identity problem

Two unenchanted copies of the same ring produce byte-identical links. Nothing in the data
distinguishes them, and nothing should: they are interchangeable, and a set that names one means
"a ring like this".

The case that actually needs solving is a set naming that ring in *both* finger slots. The answer
is not a per-instance identifier — it is a **pass-local reservation ledger** in the planner. Slot 11
claims the copy in bag 2 slot 5; slot 12, asking for the same key, skips the claimed copy and takes
the next. Free bag slots are reserved the same way. The ledger is cleared at the start of every
planning pass.

This is worth stating as a decision because the instinct is to reach for `C_Item.GetItemGUID`, and
that instinct is a trap: there is no reverse lookup from a GUID to an item, so using one means
scanning every bag slot anyway; a GUID renders nothing for an item sitting in the bank, so a set
could not draw its own icons at login; and replacing a ring with an identical one would break the
set permanently with no way to diagnose it. Blizzard stores no GUIDs in any version of its own
equipment manager either.

## D7 — There are two equip channels and they are not interchangeable

The *game* permits swapping slots 16/17/18 in combat. The *client API* does not: cursor-based
swapping is blocked under `InCombatLockdown()` for every slot, weapons included, and
`C_Item.EquipItemByName` in combat picks the item up instead of equipping it — leaving it stuck on
the cursor, which then blocks every subsequent swap.

So:

1. **Out of combat** — the cursor state machine. Handles everything, and is the only path that can
   move armor.
2. **In combat, weapons only** — a `SecureActionButtonTemplate` carrying
   `/equipslot [combat] 16 <item>` macrotext, fired by a **hardware keypress**. Nothing scripted
   works, so this cannot be triggered from a button click in our own UI; it has to be a keybind.

Everything else queues and flushes on `PLAYER_REGEN_ENABLED`. That queue is not a consolation
prize: on this client "I pressed the button and nothing happened" is the most common failure a
gear addon produces, and turning it into a scheduled, announced, cancellable action is the
cheapest large improvement available.

One consequence worth stating: every in-combat weapon swap costs a global cooldown (1.5s, 1.0s for
rogues) and resets both auto-attack swing timers. It is a DPS loss, never a neutral action, so
nothing in this module swaps weapons in combat unless the player pressed a key meaning exactly
that.

## D8 — Refuse before mutating

If a set cannot be fully applied, the plan comes back with **zero actions** and a reason list
naming the slot, the item and the problem. We never half-apply.

Every competitor on this client — and Blizzard's own implementation on the flavors that have one —
starts the swap and discovers the problem at slot 14 of 18, leaving the player in a state that is
neither set. The failure vocabulary they offer is a red set name.

Being the addon that says *"can't equip Arena: Vengeful Gladiator's Chestpiece is in your bank,
and you need 2 free bag slots"* **before touching anything** is a better product than being the
addon with the most features. This is the thesis; when something else in the design conflicts with
it, this wins.

## D9 — "In your bank" is a different answer from "missing"

The client returns nothing for bank containers once `BANKFRAME_CLOSED` has fired. Without a cache,
a set whose gear is banked is indistinguishable from a set whose gear was disenchanted — and the
player gets the same useless "could not find" either way.

So we snapshot the bank on `BANKFRAME_OPENED` and keep it. The cache is never used for *planning*
(a stale row is not a promise), only for *reporting*, and a banked row is marked stale so the UI
can be honest about when it last looked. Nothing else on this client does this, and it converts a
dead end into an instruction.

## D10 — The Character panel is enhanced, never replaced

Two additive surfaces: a popout on each of the nineteen existing paperdoll slot buttons, and a
sixth Character-frame tab. We `hooksecurefunc` Blizzard's slot handlers and never replace a script,
we add a tab rather than reskinning the frame, and if `CharacterFrame` is absent the whole thing
declines to build rather than erroring.

The alternative — our own standalone gear window — was rejected because the request was explicitly
an *enhancement to the default UI's Character Panel*, and because the paperdoll is already the
mental model every player has for "where my gear is". A second window would have to re-teach it.

## D11 — Ignore markers are visible whenever a set is selected

Retail shows them only while the Equipment Manager pane is open, which means you cannot tell what
a set will actually touch without entering edit mode. Since the marker is the only visible
difference between "this set leaves my trinkets alone" and "this set has no trinkets", hiding it
outside edit mode hides the answer to the question the player is asking.

The ignore *toggle* stays where it has always been — inside the flyout, as "Ignore This Slot" /
"Include This Slot". It has never been a right-click on the slot, in any version of the game, and
inventing a second convention would be worse than following the one people know.

## D12 — A merchant window refuses a swap

Running a gear swap with a vendor frame open can sell items. The hazard is old and well
documented, the guard is one condition, and the cost of being wrong is unrecoverable.

## D13 — No stat weights of our own

The flyout sorts by item level, and by a Pawn score when Pawn is present. We ship no weights.

TBC theorycrafting is genuinely contested — hit and defense caps, the +healing versus +spelldamage
split that exists only in this expansion, resilience breakpoints — and a scoring model that is
wrong for half the specs is worse than no scoring model, because it is wrong *authoritatively*.
Item level is a dumb sort that nobody will mistake for advice.

## D14 — No queues and no event rules in v1

ItemRack's per-slot priority queues are the best idea in the ecosystem and its event/rule system
(Mounted, Stealth, Shadowform, zone triggers, with an unequip-on-end flag) is the second best.
Both are whole subsystems, both are orthogonal to sets, and both would double the surface area
before the core is proven. BACKLOG, deliberately, not by oversight.

The related decision is that if event rules are ever built, they ship as a curated, class-gated
library and **not** as a Lua script editor. Outfitter shipped the editor and it is the reason
Outfitter is hard to explain.

## D15 — The engine is pure and takes snapshots

`CommanderArmoryEngine.lua` calls no WoW function and touches no frame. The host assembles a flat
snapshot table, the engine returns plans and verdicts, the host executes one action per tick and
reports results back.

The sequencer is the part of this module most likely to harbour a subtle bug — cross-slot
shuffles, two-hander ordering, unique-equipped conflicts, peak bag occupancy — and every one of
those is a pure function of state. Making them pure means the harness can construct the exact
adversarial arrangement (bags full *and* a ring swap *and* a 2H) with a table literal, which no
amount of in-game testing would reliably reproduce.

## D15a — A new set is naked, not empty

"New" used to build a set with no entries at all and then immediately capture
whatever the player had on. Two things were wrong with that, and they compound.

The first is that a set with no entries is not a blank set, it is a set that
**ignores every slot** — D3's "a slot with no entry is IGNORED" rule read
backwards. That rule exists to make a *half-authored* set safe; applied to a set
nobody has authored yet it says "touch nothing", forever, silently. The capture
hid the problem by filling the set in before anyone could look at it, which is
the second thing: **New** silently meant **Save**, and there was no way to
express "a set that specifies nothing worn at all."

So `E.NakedSet` writes nineteen real entries: every slot `EMPTY` — *this slot
should be bare*, so equipping the set strips you — with **shirt and tabard
`IGNORED`**. The cosmetic exception is D5's reasoning applied at creation rather
than at capture: they carry no stats, and a set that yanks your guild tabard is
the complaint D5 exists to prevent. It is also the clearest possible statement
of the D3 invariant, because the two states sit side by side in the same set and
do visibly different things.

`E.NewSet` is unchanged and still returns the bare table. It is the constructor;
`E.NakedSet` is what the *player's* "New" means, and the two are different
questions. The host's `NewSet` — the one the dialog and `/cgear save <newname>`
both go through — uses the naked one.

The knock-on that needed care: `LoadIgnoreScratch` has a special case returning
an empty scratch for a set with no entries, which is the fix that made
`/cgear save <newname>` work at all. A naked set *has* entries, so it no longer
takes that path — it falls through to the normal loop, which reports exactly
shirt and tabard. The guard stays for entryless sets in older saved files, where
it is still the only honest reading.

## D15b — One flyout, two verbs, decided by where it was opened

With naked sets, wearing the gear and pressing Save is no longer the only way a
set gets filled in — it cannot be, since the point is to author a set you are
not wearing. The slot grid in the pane already opened the candidate flyout; what
was missing was what a click in it *meant*.

- Opened from the **paperdoll** arrows: a click **wears** the item. Unchanged.
- Opened from the **pane's slot grid with a set selected**: a click **authors**
  it into that set's entry for the slot, and equips nothing.
- Pane with **no set selected**: wear, because there is nothing to author.

The alternative — a separate "edit mode" toggle — was rejected because it adds a
mode nobody can see from outside it, and because the surface you clicked already
carries the intent unambiguously: the paperdoll is your body, the grid is a
description of a set. The cost is that one list has two meanings, so the flyout
says which one is live in its own header, the row tooltip spells out both, and
**shift-click on a candidate wears it now** so the pane is not a dead end.

Three consequences worth writing down:

- **Authoring writes are immediate and persistent.** They are explicit edits,
  not staged ones; there is no second confirmation and Save is not it.
- **Save is now destructive.** It has always meant "replace this set with what I
  am wearing", but until slots could be authored one at a time there was nothing
  in a set for it to destroy. Its tooltip now says *replaces, does not merge*,
  because that tooltip is the only place the warning can reach anyone.
- **Authoring a slot clears its hands-off flag.** Otherwise the next Save writes
  `IGNORED` back over the entry that was just authored and the edit undoes
  itself with no error.

The entry an authored slot writes is built by `E.AuthorEntry`, which copies
field-for-field what `E.CaptureSet` writes — including `baseKey`, whose absence
would silently disable loose matching (D6) — and which returns a **fresh table**
every time. Candidate rows are pooled scratch that the next `E.Candidates` call
overwrites; storing one has already cost this module a bug, and a constructor
that copies is the fix that cannot be forgotten at a call site.

## D16 — Multi-pass is the normal path

A fifteen-slot swap cannot complete in one pass; items lock while in flight. The run waits on
`ITEM_LOCK_CHANGED`, re-plans the remainder, and re-enters waiting if the second pass created new
locks. A five-second watchdog force-clears the run, because the lock-change event genuinely does
not always arrive — ItemRack carries the same watchdog for the same reason, and a gear addon that
can wedge itself until reload is one nobody trusts twice.

## D17 — The tooltip answers "or not"

The item tooltip named the sets that want a piece and said nothing at all when
no set wanted it. That silence is indistinguishable from four other things: the
option being off, the addon not having loaded, the tooltip not having refreshed,
and the item simply not being gear. The question a player is asking when they
hover a piece they are about to vendor is *"is this in a loadout or not"*, and
half of that answer was missing.

So an item no set names says `Armory: not in any set`, in dim grey rather than
the accent, because it reports an absence and not a warning.

Two gates decide whether that is useful or noise, and both are load-bearing:

- **Only for gear.** The line appears only when `GetItemInfoInstant`'s equip
  location maps through `D.EquipLocSlots` to a real slot. Without that, every
  reagent, potion and quest item in the game grows an Armory line, and the
  useful case disappears into the noise it created.
- **Never for ammo.** Slot 0 is outside the set model entirely (D4), so "not in
  any set" would be a true sentence that implies a false thing — that it could
  have been.

A naked set contributes nothing to the positive line, which is correct: it names
no items, and a set that specifies bare slots does not "use" anything. The scan
keys off `state == "ITEM"` with a key, so `EMPTY` and `IGNORED` entries can never
make an item look claimed.

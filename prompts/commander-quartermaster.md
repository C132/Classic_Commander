# Prompt — Commander Quartermaster: the supply ledger

> Feature brief for a new Commander suite module. Written before implementation so the
> intent, the constraints, and the full configuration surface are settled up front.

## The request

Create a new Commander addon that is kind of like AtlasLoot, but a database for all
consumable-type items in the game, with recommendations broken down by
class/specialization. It should be an item browser and tracker that looks across all of
your bags, banks, and alts for complete information on your consumables — from water, to
potions, to one-time consumes, whatever it may be. The majority of the items are expected
to be available via the AH, but others are included too. This is for WoW TBC.

## The root problem

Raid preparation in TBC is a supply-chain problem spread across characters. The flasks
are on the bank alt, the food is on the main, the sharpening stones were mailed somewhere
last week, and the only way to answer "am I ready for Wednesday?" is to log through every
character opening every bag and bank tab. Meanwhile *knowing what to buy* is its own
research project: which of the game's hundreds of consumables matter for a Fury warrior
versus a Resto shaman is tribal knowledge scattered across forums.

Two problems, one module: a **catalogue** (what exists, what it does, what my spec
wants) married to a **ledger** (what I actually hold, and where).

## The insight

AtlasLoot proved the shape: a browsable, tooltip-rich database beats a wiki because it
lives in the game, speaks item links, and knows who you are. Apply that shape to
consumables — but where AtlasLoot answers "what could drop," Quartermaster answers two
better questions at once: **"what should I carry?"** (recommendations keyed to your
class and spec) and **"what do I already own?"** (live counts across bags, bank, mail,
and every alt, on every row). The browse list *is* the shopping list.

## Design principles

- **The database is curated, not scraped.** Every item is hand-classified into a
  category, annotated with what it does, how you get it, and what restricts it. Wrong
  item IDs are worse than missing ones — every ID is verified against the TBC database.
- **Counts everywhere.** Any place an item is named, the ledger says how many you hold
  and where. A recommendation without a count is a to-do; with a count it is a status.
- **Alts report in absentia.** Each character files its inventory as it plays (bags on
  every change, bank and mail when opened). The browser reads the ledger — no logging
  around, and no pretending: data is stamped with when it was last true.
- **Recommendations are opinions, labeled as such.** Per spec, slot by slot (flask,
  elixirs, food, weapon, potions, extras), ranked with alternatives and one-line
  reasons. They are a starting loadout, not law.
- **Zero interference.** Scanning is event-driven and debounced; the browser is an
  insecure frame that never touches combat paths; tooltip integration is read-only.

## Information model

| Channel | Where | Encoding |
| --- | --- | --- |
| What exists | category list | ~17 curated categories, flasks → ammunition |
| What it does | item row + tooltip | one-line effect note; full game tooltip on hover |
| How you get it | item row tag | AH / vendor / drop / quest / conjured / BoP / seasonal |
| Who can use it | item row | restriction note (class, profession, level) |
| What you hold | count columns | Bags, Bank, Alts, Total per row |
| Where the alts hold it | Alts cell tooltip | per-character breakdown, class-colored, bags/bank/mail |
| What your spec wants | Loadout view | slot-by-slot picks with ranked alternatives and reasons |
| Whether you are ready | Loadout counts | the same count columns on every recommended item |
| Data freshness | character breakdown | "last seen" stamps; bank/mail age separately from bags |

## The two views

**Browse** — the AtlasLoot experience. Category list down the left (Flasks, Battle
Elixirs, Guardian Elixirs, Recovery Potions, Combat Potions, Buff Food, Basic Food &
Drink, Weapon Oils & Stones, Poisons, Scrolls, Bandages, Explosives, Runes & Battle
Items, Drums, Ammunition, Pet Food, Seasonal). Item rows on the right: icon, name in
quality color, effect note, source tag, and the four count columns. Search box filters
across every category at once. Hover for the real tooltip; shift-click links to chat.

**Loadout** — the recommendation experience. Pick a class and spec (defaults to your
own), get the slot-by-slot raid loadout: Flask (with the elixir-pair alternative),
Battle Elixir, Guardian Elixir, Food, Weapon, Combat Potion, Recovery Potion, Extras.
Every recommended item is a full row with the same counts, so the view doubles as a
readiness checklist — and because alternatives are ranked, it degrades gracefully from
"best in slot" to "what the AH has tonight."

## The ledger

- Account-wide SavedVariables (`CommanderQuartermasterLedger`), separate from settings
  so a settings reset never destroys inventory history.
- Keyed realm → character; each character stores class (for coloring), level, faction,
  a last-seen stamp, and per-location item-count maps: `bags`, `bank`, `mail`.
- Bags rescan on `BAG_UPDATE_DELAYED` (coalesced), bank on open and on
  `PLAYERBANKSLOTS_CHANGED`, mail inbox on `MAIL_INBOX_UPDATE`. Each location stamps
  its own scan time — bag data is live, bank data is "as of last visit."
- Only consumable-shaped items are recorded: anything in the curated database, plus
  anything whose item class is Consumable or Projectile. Zero counts are pruned.
- The current character always reads live from the client; the ledger is for everyone
  else.

## Configuration surface

One settings page ("Quartermaster", `/cquartermaster`, `/cqm`).

- Master enable; Track Bank / Track Mail; Include This Character (a bank-alt opt-out).
- Tooltip counts: append "Carried / Bank / Alts" lines to consumable tooltips,
  with an optional per-character breakdown.
- Current Realm Only (default on) vs all realms.
- Browser: style (Dark / Classic / Window), scale, Reset Position.
- Ledger hygiene: a character dropdown + Forget button for deleted alts.
- Slash: bare `/cqm` opens the browser; `scan`, `report` (chat summary of key
  loadout counts), `settings`.

## Technical constraints (TBC Anniversary 2.5.5 / 2.5.6)

- `C_Container.*` for all bag/bank iteration (unchanged from 11506); bank is
  `BANK_CONTAINER` plus bag slots 5–11. `C_Item.*` for item info — `GetItemInfo`
  returns nil until the item is cached, so rows render from curated names and refresh
  on `GET_ITEM_INFO_RECEIVED`.
- Tooltip hook must handle both worlds: `TooltipDataProcessor.AddTooltipPostCall` if
  this framework ships it, else `GameTooltip:HookScript("OnTooltipSetItem")` — guarded,
  fail-safe.
- Browser window follows the Economy AAR pattern: `ApplyStyleBackdrop`, drag overlay
  with screen-space position save, scale from settings, never parented to WorldFrame.
- Settings panel on `Commander.UI` as always; module registered in the Suite Operations
  pillar; slash dispatch is exact-match so subcommands are literal keys.
- The database file is generated offline (curated + web-verified), shipped as a plain
  Lua table — no runtime scraping, no server calls, no dependencies.

## Non-goals

- No auction-house price data (Auctionator's job; Quartermaster says *what* to buy).
- No crafting-material tracking or reagent math (a different database).
- No automatic purchasing, mailing, or restock actions — this is a ledger and an
  advisor, not a robot.
- No guild bank scanning in v1 (a shared ledger is a different trust model).

## Acceptance criteria

1. Opening the browser on any character shows every category, every item resolves to a
   real tooltip, and the counts match what the characters actually hold.
2. A consumable bought on an alt appears in the main's Alts column after nothing more
   than the alt's normal play (no manual scan).
3. The Loadout view for every class/spec shows a complete, sensible TBC raid loadout
   with working item links and live counts.
4. Search finds "healing potion" across categories instantly, at every rank.
5. Turning the master switch off stops all scanning and tooltip additions; the ledger
   survives untouched.

---

# Batch 2 — from ledger to quartermaster (2026-08-03)

v1 answers "what exists" and "what do I hold." Batch 2 makes the module earn its rank:
a quartermaster doesn't just count supplies, he tells you whether you're ready to march,
what to buy, and where the convoy is. Ten majors, plus one piece of suite integration.

## The ten

1. **Readiness engine.** The Loadout view stops being a list and becomes a verdict.
   Every slot is graded from the ranked picks: **CARRIED** (a pick is in your bags),
   **IN BANK** (reachable, go withdraw), **ON ALTS** (somewhere in the ledger — mail,
   transit, or another character), **MISSING** (buy it). The grade rides the slot
   header; a summary row tops the view ("Readiness: 5/8 carried · 1 in bank · 2
   missing"). `/cqm ready` prints the same verdict to chat. Readiness for reports and
   warnings always grades **your own class**, with your manual spec pick honored only
   when it belongs to your class — browsing a Mage loadout on your Warrior never
   changes what "ready" means.
2. **Raid-entry supply check.** Zoning into a raid instance runs the readiness check
   automatically: one chat summary (green confirmation or a list of gaps), a warning
   sound when something's missing, once per instance per half hour (ghost releases and
   corpse runs don't re-trigger it). Off-switch and sound toggle in settings.
3. **Watchlist with restock targets.** Right-click any item row to set "keep N on this
   character" (bags + bank). A Watchlist entry pins to the top of the Browse sidebar
   with a short-count badge; its view lists watched items deficit-first with have/want
   in the note column. Watched rows wear a gold `*` everywhere (red when short), and
   the item tooltip gains a "Restock: have/target" line. Targets are per-character
   (keyed like UntrackedChars), live outside the defaults table so Restore Defaults
   keeps them, and export as macro-friendly globals
   (`CommanderQuartermaster_SetWatchTarget/GetWatchTarget`).
4. **Shopping list.** One button (and `/cqm shop`) turns gaps into an errand list in a
   copyable export window: loadout slots graded BUY / move-from-bank / mail-from-alt
   with the top pick named, then watchlist deficits with exact buy counts. Refresh and
   Select All buttons; escape closes.
5. **Roster view.** A third view alongside Browse and Loadout: every ledger character —
   class-colored, level, gold, tracked-item totals per location (Bags/Bank/Mail/Total
   columns), "seen 2h ago", and per-location freshness stamps in the tooltip — the
   brief's "data is stamped with when it was last true" finally rendered. Click a row
   to hide/unhide a character from counts (the UntrackedChars map, immediate); right-
   click to Forget (confirm popup; the character you're on can only be hidden).
   Sidebar filters by realm.
6. **Deep search.** The search box tokenizes on whitespace and every token must match
   across name, effect note, category, source tag, and restriction text — "spell
   damage food" finds the Blackened Basilisk row, "level 65 vendor" finds the
   Shattrath flasks.
7. **Filters.** A Filter menu on the Browse toolbar: era (All / TBC / Vanilla) and
   source (All / AH / Vendor / Created / Quest / Drop / BoP / Event), single-level
   menu, persisted, button label flags the active state. Composes with search and
   Owned Only.
8. **Sortable columns.** The Bags/Bank/Alts/Total column headers are buttons: click
   sorts descending, again ascending, a third time restores curated order. Sorting
   flattens category headers (it's a leaderboard now); the Roster view sorts by the
   same columns re-labeled Bags/Bank/Mail/Total.
9. **Mail in transit.** The classic ledger hole: flasks mailed to the raid main vanish
   from every count until the recipient logs in. Now sending mail snapshots the
   attachments (hooked fail-safe, committed on MAIL_SEND_SUCCESS) and credits them to
   the recipient's ledger record as a `transit` layer — counted in Alts/mail totals
   and the breakdown tooltip — until the recipient's own mailbox scan supersedes it
   (or 31 days expire it). Recipients are matched case-insensitively against existing
   ledger characters on this realm; strangers are simply not tracked.
10. **Spec auto-detection.** The Loadout view defaults to what your talents actually
    say (deepest tab, both classic and retail `GetTalentTabInfo` shapes handled,
    re-checked on talent changes) instead of the first spec in the file. A manual
    spec pick still wins; Feral defaults to Cat (tab 2 can't tell Bear from Cat —
    tanks pick by hand); tab-3 Rogues get Assassination's list. Roster gold comes
    from the same batch: `GetMoney()` recorded at scan time and on PLAYER_MONEY.

## Suite integration

Commander_Inventory gets a Quartermaster button: a crate icon in the item grid's title
bar (WINDOW style) or a small tab above the top-right corner (backdrop styles), shown
only when Commander_Quartermaster is installed (the TopBar soft-fail pattern — probe
the toggle global, never a hard dep). One click opens the browser.

## Non-goals (still)

Prices, crafting math, and any automation that buys, mails, or moves items. The
shopping list is text you carry to the AH, not a bot.

## Verification

The offline harness moves in-repo to `Commander_Quartermaster/Harness/` (the
Meters/Momentum convention) and grows checks for every feature above, including the
bank/mail close-race flushes from v1's review, the transit commit/supersede/discard
paths, both talent-API shapes, and the Inventory button's installed/absent gate.

## Batch 2 follow-ups (same day)

**Fringe loadouts.** The generated database stays generated; a new hand-curated
`CommanderQuartermasterFringe.lua` appends off-meta specs at load. Every class
fields one: Prot PvP (Warrior — the Season 1 shield-slam cheese), Shockadin
(Paladin), Melee (Hunter — the forbidden spec, Bogling Root included), Subtlety
(Rogue, PvP), Smite (Priest), Tank (Shaman — no taunt, all heart, plus a
Masterwork Target Dummy), Krosh Tank (Mage — the Gruul's Lair Spellsteal
contract), Demo Tank + SL/SL (Warlock — the Leotheras/Illidan niche and the arena
drain-tank), and Dreamstate (Druid, the int-regen arena battery). House rule,
harness-enforced: fringe picks may only reference item IDs that already exist in
the verified database, so hand curation never dilutes the generator's ID
guarantees. A slot may carry a note and NO entries (Tank Shaman's weapon slot:
Rockbiter is the consumable) — it renders as advice and stays out of the
readiness denominator. Tab-3 Rogues now auto-detect into the real Subtlety
loadout; fringe specs sharing a tree with a mainstream spec (Shockadin/Holy,
Smite/Holy, Demo Tank/Demonology, Dreamstate/Balance, Prot PvP/Protection, Tank
Shaman/Enhancement-adjacent) keep the mainstream auto-detect default and are
picked by hand.

**Item level column.** A fifth sortable column, Lvl, left of the counts (a property,
not a holding — the window widened 800→850 to pay for it honestly). Values come from
the client item cache, memoized, dash until known; while sorted by Lvl an item-info
arrival triggers a full rebuild so the order corrects itself. In the Roster view the
same column shows and sorts character level.

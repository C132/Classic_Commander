# Commander_Spellbook — decisions

Numbered so code comments and future sessions can cite them. 1.0.0, 2026-10-26.

## D1 — One window, the Quest Log's shape, no tabs

Devin asked for "a modern UI, not tabbed, just clean, searchable", and named Commander Quest Log as
the example of a clean UI. So the window is the Quest Log's: double wide, the navigator on the left
(every spell, one row each, in foldouts), the briefing on the right (the selected spell), a toolbar
with a search box, an action bar under the briefing, a footer under the navigator, the dialog border
and header plate on dark stone, the same ink rules for the parchment sheet, the same scale grip.
Nothing is borrowed from the stock book's art.

The stock book has two rows of tabs: Spellbook / Pet along the bottom, General and the three trees
down the side, and pages inside each. All of that is one scrolling list here. The pet's abilities are
a foldout of the same list (D6). The toolbar's three filters — Spells, Training, Rank Check — change
what the navigator lists, the Quest Log's All / Active / Complete / Tracked strip, not separate
windows.

## D2 — One row per spell; the ranks are in the briefing

The stock book lists every rank as a button: Flash Heal 1 to 9 is nine buttons over two pages, or,
with "Show all spell ranks" unticked, only rank 9 and no way to reach the others. Here a spell is
one FAMILY row, carrying `highest/total` on its right ("2/9") and badges (D7). Selecting it lays the
ranks out in the briefing one per line — rank, the level it comes at, and its state: Known, Replaced
by a higher rank, Train now with the price, At level N with the price, Talent, Quest reward, Not for
your race. Each known rank's chip casts THAT rank and drags it to a bar (down-ranking was the whole
reason to keep lower ranks). Clicking a line shows that rank's own tooltip below the ladder — the
client's tooltip, embedded as the Formulary does (its D7), so two ranks' mana and numbers are one
click apart.

Families are built from the generated class data's rank chains (D5), not from the book: with the
client's Show-all-ranks box unticked the book reports only the highest rank, and the lower ones
would not exist. `IsPlayerSpell` answers for each rank whether the character has it. A rank's number
is its place in the chain, so nothing waits on the client's asynchronous subtext (the bug Commander
Rank Check's harness exists for); a spell the data does not chain (a racial, a profession) falls
back to the subtext and repaints when it loads.

## D3 — Foldouts by role, or by talent tree

The default grouping files every spell under what it does: Healing, Damage, Crowd Control,
Defensive, Buffs, the class's Stances / Auras / Aspects / Forms, Utility, Travel (teleports, portals and the
mounts you summon, apart so a mage's twenty-four do not bury the conjures), Pet, then the stock book's
General tab split three ways — Racial, Professions, General — and Passives last, folded shut. The
role of every rank chain comes from the generated data (heuristics over the client's spell effects,
corrected by hand per spell in the generator's `MANUAL_ROLE`). "By talent tree" in the toolbar's
dropdown keeps the stock book's tabs, General and the three trees, as foldouts, for anyone who reads
the book that way; a spell you have never learned is on no tab, so it gets a "Not Learned Yet"
foldout of its own in that mode.

A search matches spell names and group names ("heal" lists every Healing spell), opens every fold it
found something in, and also finds class spells you have not learned yet (dim, with the level they
come at). It never offers another race's spell.

## D4 — Training is the suite's own What's Training

WhatsTraining added a tab to the stock book listing what the class trainer would teach. Here it is
the Training view of the same window (`/csb train`, its own key binding), and it is
uninstalled. Every row a class trainer teaches this class, filed by what stands between you and it:

- **Train Now** — the level is reached and every rank before it is learned or trainable in the same
  visit. A trainer teaches rank 4 and then rank 5 on one trip, so both are listed here with one total
  (WhatsTraining put rank 5 under "missing requirements", which hid what the trip costs).
- **Weapon Skills** — what a weapon master would teach your class now.
- **Coming Up** — within the next N levels (setting, default 2, WhatsTraining's figure).
- **Needs an Earlier Rank** — the level is reached but an earlier rank no trainer teaches is missing
  (a quest reward, or skipped).
- **Needs a Talent**, **Later**, **Ignored** — folded shut by default.

"Learned" means known OR replaced: several warrior and rogue ranks leave the book when a higher rank
is learned, and nobody trains them again. A row for another race is never listed. Prices are the
trainer's base price; the row tooltip says a trainer of a faction you are Honored or better with asks
less, rather than guessing at the discount. The header of Train Now carries the count and the gold,
red when you cannot afford it. Ignore is per character (an alt's choices are not a main's).

Go to Trainer is the suite's one Go button (Commander Orders D31): the class trainer through Orders'
locator (`{ townsfolk = "Class Trainer" }`, Questie knows where they stand), or for a weapon skill
every weapon master of your faction who teaches it as one place with alternatives, the arrow on the
nearest.

Not carried over from WhatsTraining: warlock demon grimoires and hunter pet abilities (both need
the pet summoned to know what it has learned, which is why WhatsTraining keeps its own per-character
ledger of them), and its LibDataBroker launcher.

## D5 — The data is generated, never typed

`Harness/make_spellbook_data.py` writes `CommanderSpellbookData.lua` from the client's DB2 tables
(SkillLineAbility's SupercedesSpell links make the rank chains, its RaceMask the race limits, the
spell effects the roles, Talent.db2 the talent-learned first ranks) and the CMaNGOS TBC world DB
(every spawned class trainer's and weapon master's list, with prices and levels; quest rewards for
quest-learned first ranks; spawn points for the weapon masters). The generator prints a cross-check
against WhatsTraining's hand-curated per-class tables, the practical check on a systematic world-DB
hole; see the Harness README for the run and the last result.

What the 1.0.0 data settles, and leaves open (2026-10-26, build 2.5.6.68941):

- A chain's role is decided on its HIGHEST rank's effects; 95 `MANUAL_ROLE` rows (totems, seals,
  traps, dummy-effect spells, next-cast cooldowns, threat drops) say what effects cannot. Judgement
  calls a player may read differently: Earth Shock, Charge, Intercept, Hamstring and Wing Clip are
  Crowd Control; Garrote, Mana Burn, Drain Mana and Viper Sting are Damage; Desperate Prayer, Holy
  Nova and Vampiric Embrace are Healing; Stealth, Prowl, taunts and the non-damage curses are
  Utility; Blessing of Freedom and Blessing of Sacrifice are Defensive.
- Ranks that only a book teaches (Prayer of Fortitude 3, Prayer of Shadow Protection 2, Conjure
  Water 9, Conjure Food 8, Arcane Brilliance 2, Gift of the Wild 3, Heroic Strike 11) are in their
  chains but not in `train`: the ladder says "Not from a trainer", and a trained rank after one
  waits under Needs an Earlier Rank.
- Trainer rows that are not spells of the book — armour proficiencies (Plate Mail, Mail) and the
  rogue's poison recipes — have no chain; Training lists each as a family of one.
- A book spell the data does not chain but whose name it knows joins that chain (the paladin's
  starting Seal of Righteousness 20154, replaced at level 4 by the 21084 the chain starts from).
- 48 prices differ from WhatsTraining's, the largest on TBC-era ranks of talent spells (Mind Flay 7,
  Holy Nova 7, Vampiric Touch 3, Dragon's Breath 3/4, Hemorrhage 4, Trueshot Aura 4) where CMaNGOS
  charges full price and WhatsTraining a tenth to a twentieth. Left as CMaNGOS has them for want of a
  citable source (ASSUMPTIONS A9). Polearms' class mask is the DB2's (Warrior, Paladin, Hunter);
  WhatsTraining adds Druid.

## D6 — The pet's abilities are a foldout of the same list

The pet book key (Shift-P) and the stock book's Pet tab open this window on the pet's foldout
("Demon Abilities", "Pet Abilities"), in view. A pet ability casts by name, drags from its pet book
slot, and right-click toggles its autocast. `/petautocasttoggle` is a secure command on this client
(SlashCommandsOverrides.lua), so the right-click is a macro on the cast button, not a call.

## D7 — Badges: what to train, what is stale

A family's row carries a green `+N` when N higher ranks can be trained now, and an amber `!` when a
bar slot or macro still casts an older rank than you know (Commander Rank Check, D9). One look down
the list after a level-up says what to buy and what to re-drag. The setting Rank Badges on Rows turns
both off.

## D8 — Casting is a sibling, never a child

Casting is protected, so a click that casts goes through a SecureActionButton. Every ancestor of a
secure button and every frame one is anchored to joins its protected family and is locked in combat
(the suite's field record: Tradecraft's holders, Commander_Buffs' icons, Party Frames' banner). A
spellbook is opened, scrolled and searched mid-fight, so the window must never be in that family.
`CommanderSpellbookSecure.lua` applies the rules Tradecraft 1.0.1 settled:

- The cast buttons are siblings of the window under UIParent, PINNED TO THE SCREEN over the region
  they cast for (a row's icon, a rank chip, the big icon, the Cast button), at its absolute rect and
  effective scale. Never anchored to it.
- They are only placed, shown, hidden or re-aimed out of combat. They are put away in the
  PLAYER_REGEN_DISABLED handler (dispatched before the lockdown lands), a combat repaint never
  touches them, and PLAYER_REGEN_ENABLED lays them out again. Every scroll, move, rescale and raise
  re-places them (the scroll hooks, a SetScale hook and a 10 Hz watch on the window's corner, scale
  and frame level — a click raises a toplevel window above buttons left at the old level).
- A row half scrolled out of the viewport gets no button: one there would catch clicks meant for the
  toolbar.
- A button casts on the mouse's UP stroke whatever ActionButtonUseKeyDown says (the `useOnKeyDown`
  attribute, SecureTemplates.lua), so a press that becomes a drag never casts first. Left-click
  casts the exact rank by id; right-click casts nothing on a player spell (`type2 = ""`) and toggles
  autocast on a pet ability; shift-click casts nothing (`shift-type1/2 = ""`, else SecureTemplates
  falls back to the plain `type` and casts) and links the rank from the post-hook, as the stock book
  does. The Cast button in the action bar is a plain button with one of these pinned over it. A pet
  command in the pet book (Attack, Follow, Stay, the stances) gets none: it is no spell to cast by
  name; it still drags from its slot.

So in combat the book still opens, scrolls, searches and drags; it does not cast, the Cast button is
greyed and the tooltips say why. That is the price of a window that never throws
ADDON_ACTION_BLOCKED.

## D9 — Rank Check is a view of this window, and can now fix what it finds

Commander Rank Check 3.0 split its scan from its chat report (`CommanderRankCheck.Scan` hands back
every ranked reference, stale or not, and broadcasts it), so the book carries it:

- the **Rank Check** filter lists Out of Date, Kept on Purpose and Up to Date (folded) references;
- the footer under the navigator says PASS / N out of date and opens that view;
- every spell's briefing has an **On Your Bars** section listing where your bars and macros cast it;
- the book asks for a quiet re-scan (no chat) whenever it opens and whenever a bar, a macro or the
  book changes while it is open.

Two actions are new, both explicit button presses, never automatic. Either one that cannot act says
why in chat (the cursor is holding something, the slot or macro changed since the check, the macro
would pass 255 characters), and Update All ends with "updated N of M":

- **Update** puts the best rank where the old one is. A bar slot gets the spell by PickupSpell +
  PlaceAction, out of combat, only if the slot still holds the rank the scan saw, only with an empty
  cursor, and only if the pickup actually put a spell on the cursor — PlaceAction swaps, and the old
  spell that comes back is dropped, so a failed pickup must never reach it (it would lift the old
  spell off the bar and delete it). A macro gets its `(Rank N)` rewritten for that spell at that rank
  only — the `#showtooltip` line with the `/cast` line — the rest of the body byte for byte, saved
  the way Blizzard's macro window saves one (`EditMacro(index, nil, nil, body)`, which keeps the name
  and the icon, a dynamic "?" icon included). An account macro and a character macro may share a
  name, so a reference remembers which list it came from and its index, and a keep keys on the list
  too. Update All does every issue.
- **Keep** leaves a reference on its rank on purpose (a down-ranked heal, a rank-1 Frostbolt for the
  slow): it stops failing the check, at login too. Per character. A bar keep is tied to the exact
  spell id in the slot, so putting another rank there brings the check back.

Rank Check's button inside Blizzard's book stays for when Blizzard's book is the one in use, and
stands down while this book takes over. Its chat line lost the arrow glyph (the client's fonts draw
arrows as boxes, Commander_Formulary D10): "Frostbolt (Rank 7), Rank 11 available".

## D10 — Taking over the stock book without replacing a Blizzard function

`ToggleSpellBook` is called from secure code (the key binding), and an addon's replacement would
taint `SpellBookFrame.bookType` and through it the stock spell buttons that read it. So nothing is
replaced. Two doors instead:

- **The keys.** Every key bound to TOGGLESPELLBOOK or TOGGLEPETBOOK gets an override binding to this
  window's own binding, set out of combat and re-set on UPDATE_BINDINGS (a signature check stops the
  loop SetOverrideBinding's own UPDATE_BINDINGS would start). A key press never reaches Blizzard's
  book, so it works mid-fight.
- **Everything else** that shows the stock book (the micro button, another addon) is caught on its
  OnShow and handed over: `HideUIPanel` on the stock book, this window opened (on the pet's foldout
  for the pet book) — the Quest Log's takeover pattern. Out of combat only: the stock book has secure
  spell buttons and cannot be hidden by an addon mid-fight, so a micro-button click in combat gets
  Blizzard's book, as it always did.

The OnShow door is a toggle, as the micro button is: with this window already up, the click that
would have opened the stock book closes it.

Both consult the setting live; turning Replace the Stock Spellbook off clears the override bindings
and hands the book back with no reload. Commander Minimap's menu entry now opens this window directly
when it has taken over, rather than showing Blizzard's to have it put away.

## D11 — What the character knows comes from C_SpellBook

On this client `IsPlayerSpell` and `IsSpellKnown` are not real globals: they are wrappers in
`Blizzard_DeprecatedSpellBook`, defined only while the `loadDeprecationFallbacks` CVar is on
(Deprecated_SpellBook.lua, classic_anniversary). With it off, every rank the book does not list would
read unknown, and the ladder and Training would offer to sell the character ranks it has. So "known"
asks `C_SpellBook.IsSpellKnown(id)` (what IsPlayerSpell wrapped) and
`C_SpellBook.IsSpellInSpellBook(id)` first, and the old globals only after (found by the 2026-10-26
review; the harness defines only the C_SpellBook calls, so it would fail on the old ones).

## D12 — The selection stays where the player put it

The Quest Log re-picks its selection whenever the row is not on screen (its D6). Here that read
badly: folding the group the briefed spell is in, or pressing Ignore (which moves the rank into the
folded Ignored group), moved the briefing to another spell for good, and Unignore could not be pressed
straight after Ignore. So the selection holds while its spell, trainer row or reference still exists,
folded or not, and only a search that hides it re-picks (typing to find a spell briefs the first one
it finds).


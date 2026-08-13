# Commander

**Commander turns World of Warcraft into your own strategy game.**

You know how in games like StarCraft you feel like a general — with a command
center, radar, rally points, and a voice announcing every victory? Commander
brings that feeling into WoW. Your cooldowns look like a build queue. Your
kills flash on screen like TARGET ELIMINATED. Your map can give you move
orders with a big green arrow. Your bags, chat, buttons, and tooltips all get
smarter and cleaner.

Commander is not one giant addon. It is **42 small addons** that each do one
job well. You can install all of them, or just the ones you like. Every single
one can be turned on or off with one checkbox.

Made for **World of Warcraft: TBC Classic Anniversary** (Interface 20506).
Each module carries its own version in its `.toc`, so a module can move
forward without dragging the rest of the suite with it.

---

## How to install it (3 steps)

1. **Download this repo** (green "Code" button → Download ZIP, then unzip it).
2. **Copy the folders that start with `Commander_`** into your game's addon
   folder: `World of Warcraft/_anniversary_/Interface/AddOns/`
   ⚠️ **Always include `Commander_Events`** — it is the brain that all the
   other pieces need to talk to each other.
3. **Start the game.** At the character screen, click "AddOns" and make sure
   the Commander addons are checked.

That's it. In the game, type `/commander` and press Enter — the Commander
control room opens.

---

## Your first five minutes

- **Type `/commander`.** This opens the dashboard: a list of every Commander
  module, sorted into five groups, each with a Settings button. Hover over a
  module's name to read what it does. Suite addons that are installed but
  didn't load (disabled, out of date, missing a dependency) get called out at
  the bottom, so nothing ever quietly goes missing.
- **Every module has a Test button.** Want to see what a level-up ceremony
  looks like without leveling up? Open Promotion's settings and press Test.
  Same for kill flashes, loot toasts, idle alerts, the casting glow — you can
  preview everything safely from your chair.
- **Moving things around:** many Commander windows can be unlocked in their
  settings. When unlocked, a green DRAG strip appears — drag the window
  wherever you want. **Right-click locks it** in place. If it's locked and you
  want to move it again, **triple-right-click it** to unlock (or use the
  checkbox in settings).
- **Choosing a look:** most Commander windows have a Style menu — **None**
  (invisible frame), **Classic** (gold border), **Dark** (sleek), or
  **Window** (a real little window with a title bar, lock button, close
  button, and a corner you can drag to resize).
- **Typing commands:** every module has its own slash command (listed below).
  Typing just the command opens its settings. Most also understand extra
  words, like `/cmom test`, `/corder set 1`, or `/cqm shop`. Typing `reset`
  after any command (like `/cbags reset`) puts that module back to factory
  settings.

---

## The five families

Commander's modules are organized into five families — the same order the
dashboard lists them in. Here is every module, its command, and what it does.

### 🎖️ Command & Control — how you give orders

| Module | Command | What it does |
|---|---|---|
| Commander_Comms | `/ccomms` | A wheel of ten quick battle calls ("On my way", "Need healing!", "Attack!", "Fall back") on one keybind. Voiced calls use your character's real voice line; the rest route to raid, party, or say automatically. Hover a call to preview exactly what it sends. It can also announce your interrupts, your cleanses, and broken crowd control to the group. |
| Commander_Orders | `/corder` | Ctrl+Right-click the world map and a big arrow guides you there with a live distance readout, like a move order in an RTS. The order completes when you arrive and survives reloads until you do. Also remembers up to 4 rally points (`/corder set 1`, `/corder go 1`) so you can always march back to your favorite spots. |
| Commander_Ping | `/cping` | When a group member pings the minimap, you get a sound, a bright expanding flash on the spot, and a chat callout naming who pinged. Never miss a ping again. |
| Commander_Camera | `/ccam` | Save up to four camera positions (angle, zoom, pitch) and jump between them with hotkeys, like camera hotkeys in StarCraft. Uses the engine's own view slots. |
| Commander_Radar | `/cradar` | Turns the minimap into an early-warning system: the radar sweep turns amber when hostile mobs are near and red (with a klaxon!) for enemy players. Enemy nameplates must be shown for contacts to register. |
| Commander_Dossier | `/cdossier`, `/cdoss` | Intelligence on the enemy — the only module that faces outward. A live **diminishing-returns board**: one row per player, one pip per DR category, each saying what your *next* crowd control will land at and when the window resets. Plus a persistent file on every enemy you meet — class, race, guild, the spells you've watched them use, the spec that implies, and your record against them. Nothing leaves your client. |

### ⚔️ Battle HUD — what you see while fighting

| Module | Command | What it does |
|---|---|---|
| Commander_Production | `/cprod` | Your cooldowns become a production queue — bars draining toward "ready," longest waits at the bottom, just like building units. Can ping you the moment something is ready. |
| Commander_Afflictions | `/caff` | A live board of every curse, disease, and DoT **you** put on enemies, with draining timers. Dispels, immunities, and deaths clear a bar the instant they happen. Can also track the buffs you cast on allies. |
| Commander_Buffs | `/cbuffs`, `/cbuff` | Moves your buffs and debuffs onto your unit frame wearing Blizzard's own aura art, with the client's aura frames hidden. On the portrait sits a **loss-of-control light**: stunned, silenced, feared, rooted — named in one word, in that category's color, with a radial duration ring, the instant it lands. The whole policy is editable in a live rule editor. |
| Commander_PartyFrames | `/cpf`, `/cpframes` | Combat-first party frames built for arena, with per-class layers. **Priests** get the Power Word: Shield board — every ally's health with each absorb embedded as a colored segment, your shield's remaining absorb, the Weakened Soul lockout, and a readiness sort so you always know who to shield next. **Mages** get health/mana rows with total-absorb tracking, decurse and CC alarms, a Water Elemental row with the Freeze planner, and a personal upkeep banner with conjure/consume/gem/portal/bandage buttons that carry live bag counts. Mouseover click-casting throughout. |
| Commander_Vitals | `/cvitals` | A little wireframe of your armor, like a damaged unit picture in an RTS. Per-slot condition bars fade green to red as your gear wears down, and stay out of the way until something needs attention. |
| Commander_Nameplate | `/cplate`, `/cnp` | A personal plate near your character with your health, mana, and cast bar. It appears when something is happening and melts away when you are topped off. |
| Commander_Casting | `/ccast` | A fullscreen glow that rises with your cast: the edges of the world brighten as it completes, so you can feel it finish without staring at a bar. |
| Commander_Casting Rings | `/cring`, `/crings` | The same cast drawn as an arc around the trim of the portraits — yours on the player frame, your target's on theirs, which is the one you watch when you are holding an interrupt. Colored by spell school, fill or unwind, labeled with seconds left or the spell's icon, and a switch to hide Blizzard's own cast bars entirely. |
| Commander_Reticle | `/creticle`, `/cret` | Your mouse pointer becomes the cast bar. A hollow, cursor-sized ring sweeps around the pointer as you cast — and rings itself with the health of whatever you are hovering, so mouseover casting stops hiding the health bar you are aiming at. Adds a global cooldown ring, a latency mark for queueing the next cast, smart dodge, and an option to take the arrow off the screen entirely. |
| Commander_Resources | `/cres` | For mana users: tracks the "five-second rule" so you know exactly when your mana starts flowing back, then shows your estimated mana per tick until you are full. |
| Commander_Meters | `/cmeters`, `/cm` | The battle report — live damage, healing, damage-taken, utility, and death meters with per-fight segments. Split the window for two stats at once, click a bar for its ability/target breakdown and pie chart, open the graph for throughput over the fight, and check the death log for the last ten hits before anyone dropped. Pets and totems always count under their owner. |
| Commander_Threat | `/cthreat`, `/ct` | Role-adaptive threat meter. Pick Tank, Damage, or Healer and the board reshapes: distance-to-pull bars and aggro warnings for damage and healers (full bar width **is** the pull point — the 110%/130% thresholds are folded in), grip and chaser watch with loose-mob counts for tanks. Draw it full, compact, on your target frame, inside Commander Meters, or not at all. |

### 🎉 Feedback & Alerts — the game celebrates you

| Module | Command | What it does |
|---|---|---|
| Commander_Momentum | `/cmom` | A kill-streak combo meter! Chain kills before the timer runs out and watch the multiplier climb through hotter and hotter colors. Can live on your player portrait as a glowing ring. Best chains are remembered per zone and instance forever. Breaks a big streak? Your character can publicly mourn it (chains over x10) — and over x15, they actually `/cry`. |
| Commander_Impact | `/cimpact` | Killing blows pulse the screen gold with TARGET ELIMINATED. Huge crits slam a red-orange pulse sized to the damage. Honorable kills in PvP flash crimson and feed a session war record (`/cimpact report`). |
| Commander_Spoils | `/cspoils`, `/cloot` | One window for every piece of loot. Spoils replaces Blizzard's loot frame, the roll pop-ups, and the loot lines in chat with a single window that keeps all of it: a live feed, a haul ledger, a roll log, a bag census, and party income. Nothing is deleted — it moves. The takeover is eight independent switches, and `/cspoils restore` puts every one of them back. |
| Commander_Promotion | `/cpromo` | Levels are promotions, and promotions deserve a ceremony: full-screen gold burst, a PROMOTION banner, your stat gains on parade, and a fanfare. |
| Commander_Adjutant | `/cadj` | Your personal battle announcer: dramatic banners and alert sounds when you come under attack, hit critical health, need repairs, run out of bag space, or receive reinforcements. |
| Commander_Idle | `/cidle` | The classic RTS "idle worker" alert, for you: stand around doing nothing and a pulsing pocket watch appears. Click it to check your orders (the quest log). |

### 📦 Operations — the campaign around the fighting

| Module | Command | What it does |
|---|---|---|
| Commander_Economy | `/ceco` | Quietly tracks your gold, XP per hour, loot, quests, and deaths, then shows an end-of-mission report window — like the score screen after an RTS match. |
| Commander_Logistics | `/clog` | Your supply line: visit any vendor and your junk sells itself while your gear gets repaired, with a neat quartermaster's report of what it cost and earned. |
| Commander_Quartermaster | `/cquartermaster`, `/cqm` | The supply ledger — a browsable database of every TBC consumable, from flasks to bandages to ammunition, with loadout recommendations per class and spec. Live counts of what you hold across bags, bank, mail, and **every alt** (bags are live; bank and mail are as of the last visit, and mail in transit stays counted). `/cqm ready` grades your raid loadout; `/cqm shop` builds the shopping list. The Gear page audits what your equipped gear is actually enchanted and gemmed with — read off the item link, not guessed — and gives every slot its shelf: all 629 enchants, glyphs, arcanums, inscriptions, kits, leg armors, spellthreads, scopes and gems TBC has, ranked for your spec, each with every way to obtain it (vendor, standing, price, token cost, boss, drop chance, profession, reagents, and where the recipe comes from). `/cqm gear` says the same in chat. |
| Commander_Talents | `/ctalents`, `/ctal` | The war academy — a full TBC talent calculator for all nine classes, every tree on its proper art with working prerequisites, tier gates, and the 61-point budget. Preset PvE and PvP loadouts mirror Quartermaster's specializations, with stat priorities and consumable recommendations alongside. Your own builds save account-wide, and builds import/export as Wowhead-style talent strings. |
| Commander_Objectives | `/cobj` | Quest progress announced like an RTS campaign: toasts as you work, OBJECTIVE SECURED when a requirement fills, MISSION ACCOMPLISHED on turn-in. Dungeons become missions with kill-count milestones and boss banners. |
| — the Mission Board | (same addon) | A standing SC2-style board of grind objectives — kills, primary targets, XP, supplies, quests, honor, survival — that tick off as you play, whatever your role. Reshuffles fresh for every dungeon run. |
| Commander_Recovery | `/crec` | When you die, Recovery logs where, keeps a casualty count, and (with Orders installed) points an arrow back at your corpse the moment you release. |
| Commander_Who | `/cwho`, `/cw` | Turns `/who` into a recruiting tool: tick the players you want and whisper them all at once, with a polite delay between sends. |

### 🖥️ Interface — the game's screens, upgraded

| Module | Command | What it does |
|---|---|---|
| Commander_ActionBar | `/cab` | Replaces the sprawling default bars with one compact command card — an RTS-style grid on a movable armored plate. A second page, **Action Bar Buttons**, handles button behavior: text, tints, cooldown feedback, ready flashes, fading, and homes for the bag/micro/pet/keyring/stance bars. |
| Commander_RankCheck | `/crank` | A unit test for your loadout: scans every action bar slot and every macro for spells cast at an out-of-date rank, then reports the ones a higher rank in your spellbook could replace. The classic post-training chore, automated. Also runs from a button in the spellbook window. |
| Commander_Bags | `/cbags`, `/cb` | Bag items get color-coded borders (gray = junk, cyan = consumable, yellow = quest item), bags drag freely and remember where you put them, fade while you travel, and sort on demand. |
| Commander_Inventory | `/cinv`, `/ci` | A quick bar that builds itself from every usable item you carry or wear — potions, trinkets, bombs, on-use gear — with live cooldowns and stack counts. |
| Commander_Chat | `/cchat` | Chat on your terms: quick layouts that shrink the window to a footnote, size/scale/font controls, mouseover-only fading, world-channel muting that still lets you post, timestamps, compact tags like [P] and [G], combat quiet, and alert sounds. |
| Commander_Minimap | `/cmap` | Reshapes the minimap into a square, movable RTS-style map: scroll to zoom, drag to move, clock tucked in neatly, and an info button that answers "how far to the next level?" |
| Commander_TopBar | `/ctopbar`, `/ctb` | A readout along the top of the screen, SC2-style: gold, income, bag supply, ammo, durability, XP rate, and performance — floating numbers, no clutter. |
| Commander_Tooltip | `/ctooltip` | Puts tooltips where you want them and tells you more — item level and vendor price on every item, cursor-anchored or pinned to a screen corner. |
| Commander_Console | `/cconsole`, `/cc` | Frames the whole game like a classic RTS: the viewport rises and an armored command console fills the bottom of the screen, docking under the action bar, minimap, and bags. (Off by default — it's a big look!) |

### 🔧 The plumbing

| Module | Command | What it does |
|---|---|---|
| Commander_Suite | `/commander` | The dashboard itself: the module directory you saw in your first five minutes, plus a Reload UI button and the Telemetry button. |
| Commander_Events | (no command) | The brain. It has no buttons of its own, but every other module needs it to talk to the rest. It also owns the shared settings framework and Telemetry. **Never delete this one.** |
| Commander_Debug | `/cdebug`, `/cbug` | Collects every Lua error raised since login — read out of BugGrabber when it's installed, captured by its own error hook when it isn't — and hands the whole pile over as one markdown prompt. Open the window, Select All, copy, paste into Claude. |

---

## The doctor's office: Telemetry 🩺

Commander watches its own health so it never slows your game down. Type
`/ctelemetry` (or press the **Telemetry** button on the Commander page) to
open a live checkup window showing how much memory and CPU every module uses
and which internal events are busiest.

Even better, `/ctelemetry report` builds a full **report card** you can copy
and paste: memory per module, CPU, event traffic, your last 20 play sessions,
and an INSIGHTS section that explains problems in plain words (like "this
module keeps growing — something might be leaking"). The **GC Probe** button
tells the difference between memory that's really being kept and memory that's
just waiting to be swept up.

Fun fact: this report card was used to find and fix the suite's own
performance bugs before going public. The tools are still there for you.

---

## Good to know

- **Everything is off-switchable.** Every module has a master checkbox, and
  most features inside a module have their own checkbox too. Don't like
  something? Un-check it.
- **Commander is polite in public.** Anything that *brags* on your behalf in
  front of other players (streak announcements, objective bragging) is **off
  by default** — you opt in. Helpful team callouts (like "Interrupted the
  healer's cast!") are on, because your group wants to know.
- **Nothing phones home.** Dossier's enemy files, Quartermaster's alt
  inventories, and every other record stay in your own SavedVariables.
- **Your settings survive.** Positions, styles, and toggles are saved per
  account, and session numbers (kill counts, war records, casualty logs)
  survive a `/reload`.
- **Keybinds:** set the Comms wheel and Camera views under
  Key Bindings → AddOns.
- **Resetting:** any module's slash command + `reset` (like `/cprod reset`)
  restores its factory settings. Saved rally points survive resets on purpose.

### What else is in this repo?

Everything starting with `Commander_` is the suite. The `prompts/` folder
holds the design briefs the newer modules were built from. Third-party addons
that happen to share the AddOns folder are ignored by the repo.

---

## For grown-up programmers 🔧

Modules communicate through the global `Commander` namespace defined by
Commander_Events:

```lua
Commander.AddListener(eventKey, fn) -- register a callback (duplicate-safe)
Commander.Notify(eventKey, ...)     -- fire a callback event (error-isolated)
Commander.MainCategory              -- the root settings category
Commander.GetModules()              -- registered modules (title, version, categoryID, slash)
Commander.RestoreSession(db, defaults) -- reload-resilient session state (10-min resume window)
Commander.Telemetry                 -- dispatch metrics + stats reset
```

Settings panels are built with the shared `Commander.UI` framework
(`Commander_Events/CommanderSettingsUI.lua`):

```lua
local panel = Commander.UI.NewPanel({
    key = "Bags", title = "Bags", addonName = "Commander_Bags",
    description = "...", event = COMMANDER_BAGS_EVENTS.UPDATE,
    slash = { "/cbags", "/cb" },
})
panel:AddSection("Item Highlighting")
panel:AddCheckbox({ label = ..., tooltip = ..., get = ..., set = ..., isEnabled = ... })
panel:AddCheckboxPair(left, right)   -- two compact checkboxes on one row
panel:AddSlider({ label = ..., min = ..., max = ..., step = ..., format = ..., get = ..., set = ... })
panel:AddSliderPair(left, right)     -- two compact sliders on one row
panel:AddDropdown({ label = ..., options = ..., get = ..., set = ... })
panel:AddDropdownPair(left, right)   -- two compact dropdowns on one row
panel:AddButtonRow({ { label = ..., onClick = ... } })
panel:AddRefresher(function() ... end) -- custom widgets re-sync here
panel:Finalize({ onDefaults = Reset })
```

Widgets read through `get` and write through `set`; after any write the panel
fires the module's update event (slider drags are throttled to a trailing
notify), and every panel re-syncs whenever that event fires or the panel is
shown. `Finalize` registers the subcategory under **Commander**, the slash
commands (bare command opens the panel; `reset` wires to `onDefaults`; other
subcommands are exact-match literal keys, including multi-word ones like
`"set 1"`), and the registry entry that Commander_Suite's dashboard reads.
A few modules own more than one panel — ActionBar/ActionBarButtons,
Casting/CastingRings, Objectives/ObjectivesBoard — and the dashboard's pillar
table lists them individually; anything the table doesn't know yet falls
through to **Other Modules** rather than disappearing.

Shared helpers: `Commander.UI.ApplyDefaults` / `ResetToDefaults` / `CopyValue`
for SavedVariables handling, `FormatPercent`, `AttachTooltip`, the HUD chrome
system (`HudChromeDefaults` / `ApplyHudChrome` / `AddHudChromeOptions` /
`HudUnlocked` — styles, scale, drag overlay, saved screen-space positions,
right-click lock and triple-right-click unlock), `ApplyStyleBackdrop` for
frames with their own window art, and `Commander.OpenModuleSettings(key)` /
`Commander.AddMainPanelContent(fn)` for suite-level integration.

House rules the codebase follows:

- Every module is fully feature-flagged behind a master enable.
- Hot paths must not allocate at steady state — dirty-check before
  formatting, pool and `wipe()` scratch tables, hoist closures. The
  telemetry GC probe is the referee.
- Game logic never rides a frame's `OnUpdate` alone (hidden frames don't
  tick) — anything that must fire uses a real timer.
- Settings panels stay under the no-scroll height budget; pair widgets
  before adding rows. (The few pages that outgrew it — Quartermaster,
  PartyFrames — scroll explicitly.)
- Public-output defaults: informational callouts on, bragging off.

Changes are gated by a Lua parse check over every file plus headless harnesses
that stub the WoW API and run outside the client. Each substantial module
carries its own `Harness/` directory beside the source: smoke passes that
build the settings panel and drive its slash commands and widgets
(Afflictions, Chat, Casting, Production, PartyFrames), engine harnesses for
the state machines (Meters, Threat, Dossier, Spoils, Buffs, Quartermaster,
Talents, RankCheck, Momentum), and separate UI harnesses where the drawing is
worth testing on its own (Meters, Threat, Dossier, Buffs, Talents).
Commander_Talents
also ships crosscheck scripts that validate its talent data against archived
external sources, and several modules include a `globals_lint.lua` pass to
catch accidental global leaks.

Suite history: Commander_Honor merged into Commander_Impact and
Commander_Rally merged into Commander_Orders during the 2.1 cleanup.
Commander_Buffs was retired when Edit Mode covered the basics, then rebuilt
from scratch when it turned out Edit Mode didn't cover the loss-of-control
readout that PvP actually needs. Commander_UnitFrames stayed retired — its
job now belongs to Commander_PartyFrames.

Have fun out there, Commander. 🫡

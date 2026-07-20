# Commander

**Commander turns World of Warcraft into your own strategy game.**

You know how in games like StarCraft you feel like a general — with a command
center, radar, rally points, and a voice announcing every victory? Commander
brings that feeling into WoW. Your cooldowns look like a build queue. Your
kills flash on screen like TARGET ELIMINATED. Your map can give you move
orders with a big green arrow. Your bags, chat, buttons, and tooltips all get
smarter and cleaner.

Commander is not one giant addon. It is **31 small addons** that each do one
job well. You can install all of them, or just the ones you like. Every single
one can be turned on or off with one checkbox.

Made for **World of Warcraft: TBC Classic Anniversary** (Interface 20506).
Current version: **2.1.0**.

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
  module's name to read what it does.
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
  words, like `/cmom test` or `/corder set 1`. Typing `reset` after any
  command (like `/cbags reset`) puts that module back to factory settings.

---

## The five families

Commander's modules are organized into five families. Here is every module,
its command, and what it does.

### 🎖️ Command & Control — how you give orders

| Module | Command | What it does |
|---|---|---|
| Commander_Comms | `/ccomms` | A wheel of ten quick battle calls ("Attack!", "Need healing!", "Thank you!") on one keybind. Voiced calls use your character's real voice. It can also announce your interrupts and cleanses to the group automatically. |
| Commander_Orders | `/corder` | Ctrl+Right-click the world map and a big arrow guides you there, like a move order in an RTS. Also remembers up to 4 rally points (`/corder set 1`, `/corder go 1`) so you can always march back to your favorite spots. |
| Commander_Ping | `/cping` | When a group member pings the minimap, you get a sound, a bright flash, and a chat callout naming who pinged. Never miss a ping again. |
| Commander_Camera | `/ccam` | Save up to four camera positions and jump between them with hotkeys, like camera hotkeys in StarCraft. |
| Commander_Radar | `/cradar` | Turns the minimap into an early-warning system: the radar sweep turns amber when hostile mobs are near and red (with a klaxon!) for enemy players. |

### ⚔️ Battle HUD — what you see while fighting

| Module | Command | What it does |
|---|---|---|
| Commander_Production | `/cprod` | Your cooldowns become a production queue — bars filling up toward "ready," just like building units. Can ping you the moment something is ready, and even keep finished spells on screen as green READY entries. |
| Commander_Afflictions | `/caff` | A live board of every curse, disease, and DoT **you** put on enemies, with timers. It even notices when your debuff gets dispelled. |
| Commander_Vitals | `/cvitals` | A little wireframe of your armor, like a damaged unit picture in an RTS. Slots turn yellow, then red, as your gear wears down. |
| Commander_Nameplate | `/cplate` | A personal plate near your character with your health, mana, and cast bar — so you never have to look at the corner of the screen mid-fight. |
| Commander_Casting | `/ccast` | The edges of the screen glow brighter as your spell cast completes — you can feel the cast finish without staring at a bar. Can color the glow by spell school (frost = blue, fire = red...). |
| Commander_Resources | `/cres` | For mana users: tracks the "five-second rule" so you know exactly when your mana starts flowing back. |

### 🎉 Feedback & Alerts — the game celebrates you

| Module | Command | What it does |
|---|---|---|
| Commander_Momentum | `/cmom` | A kill-streak combo meter! Chain kills before the timer runs out and watch the multiplier climb through hotter and hotter colors. Can live on your player portrait as a glowing blue ring. Breaks a big streak? Your character can publicly mourn it (chains over x10) — and over x15, they actually `/cry`. |
| Commander_Impact | `/cimpact` | Killing blows pulse the screen gold with TARGET ELIMINATED. Huge crits slam a red-orange pulse sized to the damage. Honorable kills in PvP flash crimson and feed a session war record (`/cimpact report`). |
| Commander_Spoils | `/cspoils` | Every worthwhile pickup gets a SUPPLY ACQUIRED toast with the item's icon and quality color. Epics get extra fireworks. |
| Commander_Promotion | `/cpromo` | Levels are promotions, and promotions deserve a ceremony: full-screen gold burst, a PROMOTION banner, your stat gains, and a fanfare. |
| Commander_Adjutant | `/cadj` | Your personal battle announcer: dramatic banners and alert sounds when you come under attack. |
| Commander_Idle | `/cidle` | The classic RTS "idle worker" alert, for you: stand around doing nothing and a pulsing pocket watch appears. Click it to check your orders (the quest log). |

### 📦 Operations — the campaign around the fighting

| Module | Command | What it does |
|---|---|---|
| Commander_Economy | `/ceco` | Quietly tracks your gold, XP per hour, loot, quests, and deaths, then shows an end-of-mission report window — like the score screen after an RTS match. You can share it with your party, and new loot can glow in your bags until you look at it. |
| Commander_Logistics | `/clog` | Your quartermaster: visit any vendor and your junk sells itself while your gear gets repaired, with a neat report of what it earned. |
| Commander_Objectives | `/cobj` | Quest progress announced like an RTS campaign: toasts as you work, OBJECTIVE SECURED when a requirement fills, MISSION ACCOMPLISHED on turn-in. Dungeons become missions with kill-count milestones and boss banners. |
| — the Mission Board | (same addon) | A standing SC2-style board of grind objectives — kills, bosses, XP, loot, survival — that tick off as you play, whatever your role. Reshuffles fresh for every dungeon run. |
| Commander_Recovery | `/crec` | When you die, Recovery logs where, keeps a casualty count, and (with Orders installed) points an arrow back at your corpse the moment you release. |
| Commander_Who | `/cwho` | Turns `/who` into a recruiting tool: tick the players you want and message them all at once. |

### 🖥️ Interface — the game's screens, upgraded

| Module | Command | What it does |
|---|---|---|
| Commander_ActionBar | `/cab` | Replaces the sprawling default bars with one compact command card — an RTS-style grid — with **33 options**: sizes, rows, tints, cooldown text, ready flashes, fading, and homes for the bag/micro/pet/stance bars. |
| Commander_Bags | `/cbags` | Bag items get color-coded borders (gray = junk, cyan = consumable, yellow = quest item), bags drag freely, fade while you move, and sort themselves on demand. |
| Commander_Inventory | `/cinv` | A quick bar that builds itself from every usable item you carry — potions, trinkets, bombs — so the good stuff is always one click away. |
| Commander_Chat | `/cchat` | Chat on your terms: hide it for a clean view, timestamps, compact channel tags like [P] and [G], and quiet-in-combat fading. |
| Commander_Minimap | `/cmap` | Reshapes the minimap into a square, movable RTS-style map: scroll to zoom, drag to move, clock tucked in neatly. |
| Commander_TopBar | `/ctopbar` | A readout along the top of the screen, SC2-style: gold, bag space, durability, XP rate — floating numbers, no clutter. |
| Commander_Tooltip | `/ctooltip` | Puts tooltips where you want them and tells you more — item level and vendor price on every item. |
| Commander_Console | `/cconsole` | Frames the whole game like a classic RTS: the viewport rises and an armored command console fills the bottom of the screen. (Off by default — it's a big look!) |
| Commander_Suite | `/commander` | The dashboard itself: the module directory you saw in your first five minutes, plus a Reload UI button and the Telemetry button. |
| Commander_Events | (no command) | The brain. It has no buttons of its own, but every other module needs it to talk to the rest. **Never delete this one.** |

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
- **Your settings survive.** Positions, styles, and toggles are saved per
  account, and session numbers (kill counts, war records, casualty logs)
  survive a `/reload`.
- **Keybinds:** set the Comms wheel and Camera views under
  Key Bindings → AddOns.
- **Resetting:** any module's slash command + `reset` (like `/cprod reset`)
  restores its factory settings. Saved rally points survive resets on purpose.

### What else is in this repo?

Everything starting with `Commander_` is the suite. `QuestCompletist` is a
separate third-party addon kept here with some local fixes — it is not part
of Commander. Other third-party addons are ignored by the repo.

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
  before adding rows.
- Public-output defaults: informational callouts on, bragging off.

Changes are gated by a Lua parse check over every file plus a headless smoke
harness that stubs the WoW API, builds all 32 settings panels, drives the
slash commands and widgets, and enforces the height budgets.

Buff-frame and unit-frame adjustments that earlier versions shipped as
Commander_Buffs and Commander_UnitFrames are covered natively by the client's
Edit Mode, so those modules were retired. Commander_Honor merged into
Commander_Impact, and Commander_Rally merged into Commander_Orders, during the
2.1 cleanup.

Have fun out there, Commander. 🫡

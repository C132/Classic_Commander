# Commander

A modular UI suite for World of Warcraft: TBC Classic Anniversary (Interface 20506).

Each module is a standalone addon that can be enabled or disabled independently. All modules require **Commander_Events**, the shared hub that provides the event bus and the unified "Commander" settings category (Options → AddOns → Commander).

## Modules

| Module | What it does |
|---|---|
| Commander_Events | Shared hub: event bus + root settings category (required by all) |
| Commander_ActionBar | Action bar cleanup and repositioning |
| Commander_Adjutant | RTS announcer: banners and sounds for attacks, repairs, level-ups |
| Commander_Bags | Bag positioning, item coloring, fading, on-demand sorting |
| Commander_Camera | RTS camera hotkeys: save and recall up to four camera views |
| Commander_Casting | Cast bar glow effects |
| Commander_Chat | Chat window visibility and message sound pings |
| Commander_Comms | Radial quick-message wheel: eight battle calls on a keybind |
| Commander_Console | Optional bottom console viewport (off by default) |
| Commander_Economy | Session mission summary: gold, XP rate, quests, casualties |
| Commander_Idle | RTS idle-worker alert when your character stands around |
| Commander_Inventory | Equipment/inventory quick-access button grid |
| Commander_Logistics | Auto-sell junk and auto-repair with a quartermaster report |
| Commander_Minimap | Minimap cleanup, zone text, XP tracker, minimap button |
| Commander_Nameplate | Personal nameplate with cast bar |
| Commander_Objectives | RTS mission announcements for quest progress and turn-ins |
| Commander_Orders | RTS move orders: Ctrl+Right-click the map, follow the arrow |
| Commander_Ping | Loud minimap ping alerts with flash and callout |
| Commander_Production | Cooldowns as an RTS production queue with ready alerts |
| Commander_Radar | Cosmetic minimap radar sweep and crosshair overlay |
| Commander_Rally | Four persistent rally points re-issued as Orders arrows |
| Commander_Recovery | Death report, session casualty count, auto corpse-run order |
| Commander_Resources | Five-second-rule mana tick tracker |
| Commander_Tooltip | Tooltip anchoring, scale, item level and vendor price |
| Commander_TopBar | RTS resource strip: gold, bag supply, durability, XP rate |
| Commander_Vitals | Per-slot equipment condition wireframe, shows when gear runs low |
| Commander_Who | /who window enhancements and mass whisper |
| Commander_Suite | Suite dashboard on the root settings page: module directory, quick settings access (`/commander`) |

## Installation

Copy the module folders you want into `Interface/AddOns/`. Always include `Commander_Events`.

Buff-frame and unit-frame adjustments that earlier versions shipped as Commander_Buffs and Commander_UnitFrames are covered natively by the client's Edit Mode, so those modules were retired.

## For developers

Modules communicate through the global `Commander` namespace defined by Commander_Events:

```lua
Commander.AddListener(eventKey, fn) -- register a callback (duplicate-safe)
Commander.Notify(eventKey, ...)     -- fire a callback event (error-isolated)
Commander.MainCategory              -- the root settings category
Commander.GetModules()              -- registered modules (title, version, categoryID, slash)
```

Settings panels are built with the shared `Commander.UI` framework (Commander_Events/CommanderSettingsUI.lua):

```lua
local panel = Commander.UI.NewPanel({
    key = "Bags", title = "Bags", addonName = "Commander_Bags",
    description = "...", event = COMMANDER_BAGS_EVENTS.UPDATE,
    slash = { "/cb" },
})
panel:AddSection("Item Highlighting")
panel:AddCheckbox({ label = ..., tooltip = ..., get = ..., set = ..., isEnabled = ... })
panel:AddSlider({ label = ..., min = ..., max = ..., step = ..., format = ..., get = ..., set = ... })
panel:AddDropdown({ label = ..., options = ..., get = ..., set = ... })
panel:AddButtonRow({ { label = ..., onClick = ... } })
panel:AddRefresher(function() ... end) -- custom widgets re-sync here
panel:Finalize({ onDefaults = Reset })
```

Widgets read through `get` and write through `set`; after any write the panel fires the module's update event (slider drags are throttled to a trailing notify), and every panel re-syncs its widgets whenever that event fires or the panel is shown. `Finalize` registers the canvas subcategory under **Commander**, standard slash commands (bare command opens the panel unless the module overrides it with a `[""]` handler; `reset` is wired to `onDefaults` automatically), and the module registry entry consumed by Commander_Suite's dashboard. Shared helpers: `Commander.UI.ApplyDefaults`/`ResetToDefaults`/`CopyValue` for SavedVariables handling, `Commander.UI.FormatPercent` for percent sliders, `Commander.UI.AttachTooltip`, and `Commander.OpenModuleSettings(key)` / `Commander.AddMainPanelContent(fn)` for suite-level integration.

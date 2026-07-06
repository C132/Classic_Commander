# Commander

A modular UI suite for World of Warcraft: TBC Classic Anniversary (Interface 20505).

Each module is a standalone addon that can be enabled or disabled independently. All modules require **Commander_Events**, the shared hub that provides the event bus and the unified "Commander" settings category (Options → AddOns → Commander).

## Modules

| Module | What it does |
|---|---|
| Commander_Events | Shared hub: event bus + root settings category (required by all) |
| Commander_ActionBar | Action bar cleanup and repositioning |
| Commander_Bags | Bag frame positioning, item quality coloring, fading |
| Commander_Casting | Cast bar glow effects |
| Commander_Chat | Chat window visibility and message sound pings |
| Commander_Console | Optional bottom console viewport (off by default) |
| Commander_Inventory | Equipment/inventory quick-access button grid |
| Commander_Minimap | Minimap cleanup, zone text, XP tracker, minimap button |
| Commander_Nameplate | Personal nameplate with cast bar |
| Commander_Resources | Five-second-rule mana tick tracker |
| Commander_Tooltip | Tooltip anchoring, scale, item level and vendor price |
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

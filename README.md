# Commander

A modular UI suite for World of Warcraft: TBC Classic Anniversary (Interface 20505).

Each module is a standalone addon that can be enabled or disabled independently. All modules require **Commander_Events**, the shared hub that provides the event bus and the unified "Commander" settings category (Options → AddOns → Commander).

## Modules

| Module | What it does |
|---|---|
| Commander_Events | Shared hub: event bus + root settings category (required by all) |
| Commander_ActionBar | Action bar cleanup and repositioning |
| Commander_Bags | Bag frame positioning, item quality coloring, fading |
| Commander_Buffs | Buff frame position, scale, and layout |
| Commander_Casting | Cast bar glow effects |
| Commander_Chat | Chat window visibility and message sound pings |
| Commander_Console | Optional bottom console viewport (off by default) |
| Commander_Inventory | Equipment/inventory quick-access button grid |
| Commander_Minimap | Minimap cleanup, zone text, XP tracker, minimap button |
| Commander_Nameplate | Personal nameplate with cast bar |
| Commander_Resources | Five-second-rule mana tick tracker |
| Commander_Tooltip | Tooltip anchoring, scale, item level and vendor price |
| Commander_UnitFrames | Unit frame settings (experimental) |
| Commander_Who | /who window enhancements and mass whisper |
| MyClassicAddon | Legacy settings panel mirroring common toggles (optional) |

## Installation

Copy the module folders you want into `Interface/AddOns/`. Always include `Commander_Events`.

## For developers

Modules communicate through the global `Commander` namespace defined by Commander_Events:

```lua
Commander.AddListener(eventKey, fn) -- register a callback (duplicate-safe)
Commander.Notify(eventKey, ...)     -- fire a callback event (error-isolated)
Commander.MainCategory              -- the root settings category
```

Settings panels register as canvas subcategories of `Commander.MainCategory` so every module appears under the single **Commander** group in the options UI.

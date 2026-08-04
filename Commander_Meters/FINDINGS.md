# Commander Meters — Findings

What the pre-build investigation established. Three questions: what does the
suite already provide, why is Recount broken on this client, and where did
Epic Damage Meter go wrong.

## 1. Suite inventory

**Client**: TBC Classic Anniversary 2.5.6 build 68502, `## Interface: 20506`
(read from the existing Commander TOCs — every suite TOC carries 20506 and
`## Version: 2.1.0`). The client runs the retail-style (Edit-Mode era) UI
framework over the TBC game; most third-party breakage here is FrameXML-level,
not the C API.

**Must consume (and this addon does)** — all in `Commander_Events`:

- `Commander.UI.NewPanel` + `AddSection/AddCheckbox(Pair)/AddSlider(Pair)/
  AddDropdown(Pair)/AddButtonRow/AddRefresher/Finalize` — the whole settings
  page, including hand-rolled sliders (OptionsSliderTemplate's atlas is broken
  on this client) and standardized slash dispatch (exact-match subcommands,
  `[""]` override for the bare command, auto-wired `reset`/`settings`).
- `Commander.UI.HudChromeDefaults/ApplyHudChrome/AddHudChromeOptions/
  HudUnlocked` — frame style (None/Classic/Dark/Window), scale, lock/drag with
  screen-space position saving, reset-position. The meter's window is a
  standard HUD chrome consumer; none of that is reimplemented.
- `Commander.UI.ApplyDefaults/ResetToDefaults/CopyValue/AttachTooltip/
  FormatPercent`.
- `Commander.GetClassInfo(token)` — memoized class colors (the bars' primary
  encoding) plus RTS titles.
- `Commander.AddListener/Notify` — settings-change event only.
  **Notify is telemetry-instrumented** (CommanderTelemetry wraps it at hub
  load; every dispatch is timed and counted forever). The combat-log hot path
  must never touch it — this meter notifies only from the settings panel.
- Registration: `## Category: Commander`, `## RequiredDeps: Commander_Events`,
  suite icon field, and a `Meters` key in Commander_Suite's PILLARS
  (Battle HUD pillar).

**Does not exist — owned locally, following local precedent**: no shared
number-abbreviation helper (only `FormatPercent`), no table/frame pooling
helpers (each module hand-rolls; Shield's row pool is the pattern), no GUID
parsing/unit resolution helpers, no combat-log dispatcher, no shared bar
texture or fonts (flat art is `WHITE8X8` everywhere; no font files ship in the
suite — Blizzard font objects or raw `Fonts\ARIALN.TTF`), no timer wrappers,
no localization layer (English literals; IDs via `GetSpellInfo` where locale
safety matters), zero Ace/LibStub anywhere.

**Suite gotchas honored**: `SetFont` with an invalid flags string hard-errors
(`""` is the no-flag value); never hook ChatFrame2 (the Commander_Chat
phantom-retention lesson); positions saved in screen space (offset × scale);
mouse-enabled children swallow drags (HudChrome's overlay handles it);
`pcall` RegisterEvent for events with restriction flags (the MINIMAP_PING
lesson); testers inject through the live data path and are cleaned by the
normal lifecycle; panels are built at PLAYER_LOGIN, never file scope.

## 2. Why Recount breaks here

The bundled snapshot is v2.5.3c (`## Interface: 20503`, "maintained by Resike
from 5.4") — a Wrath/MoP-era frame layer with a modern CLEU parser bolted on.
It dies during `OnInitialize` and would keep dying layer by layer:

1. **Bundled Ace3 predates the Settings API** — AceConfigDialog's
   `AddToBlizOptions` calls the removed `InterfaceOptions_AddCategory` path.
   Hard error before any window exists.
2. **`SetMinResize`/`SetMaxResize` removed** (now `SetResizeBounds`) — called
   in GUI_Main, GUI_Realtime, and three bundled AceGUI containers.
3. **`OptionsButtonTemplate` removed** — 15 CreateFrame sites across
   GUI_Config/GUI_Reset.
4. **`OptionsSliderTemplate` atlas broken** on this client — config sliders
   render blank even where they don't error.
5. **`InterfaceOptionsFrame` global removed** (SettingsPanel era).
6. **FauxScrollFrameTemplate machinery** — used pervasively, and Recount's
   scrollbar reskin fetches legacy named child regions
   (`<name>ScrollBarThumbTexture`) that the modern template doesn't have.
7. **`GetMouseButtonClicked()` removed** — graph click handlers.
8. Stale roster aliases (`GetNumPartyMembers`), an O(80)/sec
   UnitAffectingCombat poll loop for combat-exit, and name-mangled pet
   identity ("Pet <Owner>") resolved partly by tooltip scraping — all
   pre-modern-GUID techniques.

**The stale assumptions became this meter's requirements list**: payloads read
positionally from `CombatLogGetCurrentEventInfo` with the field orders
verified against Blizzard's own `Blizzard_CombatLogProcessor` for this exact
branch; absorbs from `SPELL_ABSORBED` only (never polled —
`UnitGetTotalAbsorbs` does not exist here); pets keyed by GUID with ownership
from `SPELL_SUMMON`/`UNIT_PET`, never display names or tooltips; combat exit
from PLAYER_REGEN + an event-idle timeout, not group polling; every frame
template usage checked against the Edit-Mode framework; feign-death guard on
UNIT_DIED (mandatory here — feign emits a real UNIT_DIED).

**Worth preserving from Recount** (and preserved): the permanent segment
selector, dense class-colored bar rows, one-click detail with ability +
target breakdowns, the death log's "last events with HP" design, per-fight
segment ring with a hard cap, and Arial Narrow as the number font.

## 3. Where Epic DM went wrong

~35,000 lines of addon code for a damage meter (16k of which is Recount, for
scale). The catalog, so each item could be avoided by name:

- **A forked, renamed Ace3 suite** ("-EDM") vendored to power one addon
  object; AceConfig registered with a literally empty options table while a
  6,800-line bespoke config panel (with a setup wizard, a snake game, and a
  1,000-line credits tab) does the real work.
- **Dead parallel engines**: a second complete bar implementation (UI/Bars.lua,
  zero callers), a 17-constructor widget factory (zero callers), a pub/sub
  event registry whose `Fire` is never called, five facade "Modules" with
  no-op `Initialize`s.
- **Dual runtime cores shipped everywhere**: Core_Retail + Parser_Retail +
  BroadcasterTools (4,176 lines) load and parse on TBC just to early-return.
- **The theming layer**: 3,277 lines, 31 skins × ~8 sub-tables, each skin
  defined in two places; applying a skin copies ~90 fields into seven profile
  subtables (clobbering user settings), then ApplySettings re-reads them with
  per-property three-way precedence and a lossy font path→name→path round
  trip, while ApplyBar separately re-reads the *original* skin table — two
  competing sources of truth for one bar. Plus a second, unrelated theme
  system for the config panel that mutates shared palette tables in place.
- **~6 dispatch hops** from a combat event to a painted bar, with
  `CombatLogGetCurrentEventInfo()` re-called 2–3× per event inside branches.
- Armor against retail-12.0 "secret values" on a TBC client; 4,600 lines of
  locale machinery for a personal addon.

**Commander Meters' answers, by the numbers**: 3 files (~2,300 lines total);
theme = one flat `THEME` table read directly by widgets; 2 hops from CLEU to
data (`OnCleu` → credit helpers) and one 2 Hz repaint pass from data to
pixels; payload captured once per event as plain arguments; zero vendored
libraries; zero dead files; modes are five table entries.

What EDM did right was noted and kept: damage = amount + absorbed with the
rationale written down, one chokepoint for pet source rewriting, a fixed-size
recent-events ring for death recap, and poll-don't-push repaints.

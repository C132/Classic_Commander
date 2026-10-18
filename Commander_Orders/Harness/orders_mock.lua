-- Commander Orders: the WoW client mock the runtime harnesses share (luajit).
--
--     local M = dofile(<AddOns>/Commander_Orders/Harness/orders_mock.lua)
--     local W = M.Boot({ ... })        -- a fresh client, Orders loaded and logged in
--
-- Written for orders_harness.lua (the runtime) and meant to be reused as is
-- by orders_pins_harness.lua and orders_ui_harness.lua. It loads the REAL
-- Commander_Events/CommanderSettingsUI.lua and CommanderEvents.lua (so the
-- settings page and the HUD chrome are the suite's own code, not a stand-in)
-- and then every Commander_Orders file in TOC order that exists on disk.
--
-- Every Boot is a FRESH PROCESS as far as the addon can tell: every global
-- written since the mock was loaded is removed, the client is rebuilt, the
-- files run again. That is what makes a /reload testable: M.Reload() writes
-- the saved variables out the way the client's writer does (numbers with 16
-- significant digits, functions and userdata dropped), boots again and hands
-- the read-back copies to the new session before ADDON_LOADED, exactly where
-- the client assigns them.
--
-- ---------------------------------------------------------------------------
-- API (M = the module; W = the world of the current boot, also M.W)
-- ---------------------------------------------------------------------------
-- Boot and reload
--   M.Boot(opts) -> W     opts (all optional):
--       saved = { CommanderOrdersDB = t, CommanderOrdersChar = t, CommanderUIDB = t }
--       loaded = { TomTom = true, Questie = true }   C_AddOns.IsAddOnLoaded answers
--       before = function(M, W)   runs after the mock is installed, before any
--                                 addon file (e.g. rawset(_G, "TomTom", {...}))
--       afterFiles = function(M, W)  after Orders' files ran, before ADDON_LOADED
--       combat = true             log in while InCombatLockdown() is true
--       player = { map, x, y }    where the player stands at login (default
--                                 Elwynn Forest, Goldshire)
--       faction = "Horde"         (default "Horde")
--       files = { "Data", ... }   Orders files to load (default: the TOC's, the
--                                 ones that exist; Pins and UI included when present)
--       skipFiles = { CommanderOrdersPins = true }   leave some out
--       addons = { "Commander_TopBar", { name = "Commander_X", files = { "A.lua" } } }
--                                 (3.1) consumer addons loaded AFTER Orders'
--                                 files: each one's TOC .lua files that exist
--                                 (or the files named, relative to its folder),
--                                 then ADDON_LOADED fired for each after
--                                 Orders' own (the hook-frame workaround the
--                                 contract harnesses used is no longer needed)
--     Environment overrides for mutation runs: ORDERS_RUNTIME, ORDERS_DB,
--     ORDERS_DATA, ORDERS_STORE, ORDERS_GEO, ORDERS_PINS, ORDERS_UI = path of
--     a copy to load instead (the pins and manager harnesses load their own
--     file themselves; these two reach the full-TOC boots: runtime section P,
--     the consumers' contract harnesses).
--   M.Reload(opts) -> W   PLAYER_LOGOUT, write the SVs through M.Serialize,
--                         Boot again with them (opts merged; opts.extraSaved =
--                         { name = value } round-trips other values too and
--                         returns them in W.restored[name])
--   M.Serialize(v) -> text, M.Deserialize(text) -> v   the SV writer and reader
--   M.loadErrors          errors raised while loading files (should be empty)
--
-- Time and events
--   M.Now()               seconds (GetTime)
--   M.Frame(dt)           one frame: timers due, then OnUpdate of every VISIBLE
--                         frame (shown, and every parent shown), then map hooks
--   M.Advance(seconds, step)   frames of `step` (default 1/30 s)
--   M.Fire(event, ...)    dispatch to every frame that registered it
--
-- 3.1 additions (additive: nothing above changed meaning)
--   Commander_Events/CommanderGoButton.lua is loaded between the settings
--   framework and CommanderEvents.lua, as its TOC orders it (when present;
--   ORDERS_GOBUTTON=<path> loads that copy instead).
--   C_ChatInfo.SendChatMessage records into M.chat like SendChatMessage.
--   StaticPopup_Show applies a dialog's maxLetters to its edit box (2.5.6
--   GameDialog.lua 210-213), so box.__maxLetters can be checked.
--   UnitGUID answers for group members ("Player-1-<name>").
--   EventRegistry: RegisterCallback(event, fn, owner) / UnregisterCallback /
--   TriggerEvent, calling fn(owner, ...) as CallbackRegistryMixin does
--   (errors caught into M.errors). SetItemRef(link, text, button, frame): an
--   "addon:" link fires EventRegistry "SetItemRef" (LinkUtil's AddOn
--   handler); others are recorded in M.itemRefs. M.ClickLink(text, button)
--   finds the first |H...|h link in a string and clicks it.
--   ChatFrameUtil.AddMessageEventFilter / RemoveMessageEventFilter (and the
--   ChatFrame_* names): M.RunChatFilters(event, arg1..arg14) runs them the
--   way ChatFrameFilters.lua ProcessFilters does and returns discard and the
--   14 args; M.filterCalls counts calls.

-- What came out
--   M.prints, M.errors (geterrorhandler and caught script errors), M.sounds
--   ({ id, channel }), M.sent (addon messages { prefix, text, channel, target }),
--   M.chat (SendChatMessage { text, chatType }), M.popups ({ which, a1, a2,
--   data }), M.menu (the entries of the last ToggleDropDownMenu, each the info
--   table the code built), M.menuAnchor, M.tooltip (lines of GameTooltip),
--   M.blocked (protected calls refused in combat), M.settingsOpened,
--   M.writes (every NEW global written: { name, phase }), M.ClearLog()
--   M.Has(list, needle)   any string in the list contains needle
--
-- The player and the client
--   M.SetPlayer(map, x, y)          stand at a zone position (world from the
--                                   DB2 rows; best map = map)
--   M.SetPlayerWorld(inst, north, west, map)
--   M.SetFacing(radians | nil), M.SetSpeed(yd/s), M.SetTaxi(bool),
--   M.SetIndoors(bool), M.SetNoPosition(bool) (UnitPosition and the map
--   position answer nil, as inside instances)
--   M.SetLife("ALIVE" | "DEAD" | "GHOST" | "FEIGN")
--   M.SetInstance(kind | nil, id)   "party" | "raid" | "pvp" | "arena"; id is
--                                   GetInstanceInfo's 8th value (the instance
--                                   map id, 585 Magisters' Terrace) while inside
--   M.SetNoMap(bool)                GetBestMapForUnit("player") answers nil
--                                   (a dungeon with no uiMap: Magisters' Terrace)
--   M.SetCombat(bool)               fires PLAYER_REGEN_DISABLED / _ENABLED
--   M.SetModifier("SHIFT" | "CTRL" | "ALT", down)   fires MODIFIER_STATE_CHANGED
--   M.SetGroup(kind, members)       kind nil | "party" | "raid" | "instance";
--                                   members = { "Name", ... } (party1.. units)
--   M.SetUnit(unit, map, x, y)      a group member's position (nil map: none)
--   M.SetUnitNoWorld(unit, bool)    UnitPosition blind for that member, its
--                                   map position kept (SetUnit clears it)
--   M.SetCorpse(map, x, y)          C_DeathInfo.GetCorpseMapPosition answers on
--                                   that map and its ancestors
--   M.SetEntrances(zoneMap, list)   C_EncounterJournal.GetDungeonEntrancesForMap
--   M.SetMinimapShape(shape | nil)  defines (or removes) GetMinimapShape
--   M.SetZoom(z)                    Minimap:GetZoom()
--   W.cvars                         GetCVar / C_CVar values
--   W.sendResult                    what SendAddonMessage returns (default 0)
--   M.Receive(prefix, text, channel, sender)   fires CHAT_MSG_ADDON
--
-- Maps (this build's UiMap / UiMapAssignment DB2 rows, as Geo's smoke uses)
--   M.MAPS, M.ROWS, M.World(map, x, y) -> inst, north, west
--   M.MapPos(map, inst, north, west) -> x, y on that map, or nil
--   C_Map: GetMapInfo, GetWorldPosFromMapPos, GetMapRectOnMap,
--   GetMapInfoAtPosition, GetMapChildrenInfo, GetBestMapForUnit,
--   GetPlayerMapPosition; CreateVector2D
--
-- The world map (QuestLog's recipe, Blizzard_MapCanvas order)
--   W.map.frame = WorldMapFrame: a PROXY that records every field write in
--   W.map.writes (none is allowed but hooksecurefunc and pinPools keys);
--   W.map.providers, W.map.canvas, W.map.container (ScrollContainer),
--   M.ShowMap(mapID), M.HideMap(), M.SetMapID(mapID), M.SetMapCursor(nx, ny),
--   M.SetMapMaximized(on) (FULLSCREEN strata, as TBC's default map; windowed
--   MEDIUM), M.STRATA and M.StrataOver(a, b) (the client's strata order),
--   MapCanvasDataProviderMixin, MapCanvasPinMixin, CreateUnsecuredRegionPoolInstance,
--   CreateFramePool (2.5.6's SECURE proxy), Mixin, CreateFromMixins,
--   hooksecurefunc; AcquirePin wires the mouse as Blizzard_MapCanvas.lua
--   does for a pin created click/motion-enabled: OnMouseUp(pin, button,
--   upInside) calls pin:OnMouseUp(button) and then, only when upInside,
--   pin:OnClick(button); OnMouseDown is pin.OnMouseDown; OnEnter/OnLeave go
--   to OnMouseEnter/OnMouseLeave.
--
-- Widgets (permissive: any Set*/Enable*/... is a recording no-op)
--   region.__text, __points ({ point, rel, relPoint, x, y }), __w, __h,
--   __shown, __alpha, __rotation, __vertex ({ r, g, b, a }), __texture,
--   __textColor, __mouse, __level, __strata, __scripts, __children
--   M.Visible(frame)      shown and every parent shown
--   M.Click(frame, button)    delivers OnClick only when the frame is
--                         visible and mouse-enabled and (a Button) enabled,
--                         like the client; returns whether it was delivered
--   M.Hover(frame)        OnEnter; a disabled Button only with
--                         SetMotionScriptsWhileDisabled(true), as the client
--   M.ClickMenu(text)     runs the func of the M.menu entry with that text
--   M.ClickPopup(which, index)   the dialog's button handler (1, 2, 3)
--   StaticPopup_Show parents the dialog to UIParent at DIALOG strata before
--   its OnShow, as StaticPopup_SetUpPosition does (M.popups[i].dialog).
--   FontString:SetText errors when the string has no font, as the client does.
--   SetPassThroughButtons is protected: refused in combat (recorded in
--   M.blocked, no error, as the client refuses it).

local M = {}

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
M.ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
M.ORDERS = M.ADDONS .. "/Commander_Orders"

local unpack = unpack or table.unpack
local realPrint = print

-- Everything Lua itself put in _G; a Boot removes every other global
local BASELINE = {}
for k, v in pairs(_G) do BASELINE[k] = v end

-- ===========================================================================
-- The world: UiMap + UiMapAssignment rows of build 2.5.6.69795 (wago.tools)
-- ===========================================================================
-- MAPS: id = { name, Enum.UIMapType, parentUiMapID }
local MAPS = {
    [233] = { "Zul'Gurub", 6, 1434 }, [234] = { "Dire Maul", 6, 1444 }, [235] = { "Dire Maul", 4, 1444 },
    [274] = { "Old Hillsbrad Foothills", 6, 1446 }, [332] = { "Serpentshrine Cavern", 4, 1946 },
    [334] = { "Tempest Keep", 4, 1953 }, [337] = { "Zul'Gurub", 6, 1434 },
    [347] = { "Hellfire Ramparts", 4, 1944 }, [350] = { "Karazhan", 4, 1430 },
    [946] = { "Cosmic", 0, 0 }, [947] = { "Azeroth", 1, 946 }, [987] = { "Outland", 2, 0 },
    [1411] = { "Durotar", 3, 1414 }, [1412] = { "Mulgore", 3, 1414 }, [1413] = { "The Barrens", 3, 1414 },
    [1414] = { "Kalimdor", 2, 947 }, [1415] = { "Eastern Kingdoms", 2, 947 },
    [1416] = { "Alterac Mountains", 3, 1415 }, [1417] = { "Arathi Highlands", 3, 1415 },
    [1418] = { "Badlands", 3, 1415 }, [1419] = { "Blasted Lands", 3, 1415 },
    [1420] = { "Tirisfal Glades", 3, 1415 }, [1421] = { "Silverpine Forest", 3, 1415 },
    [1422] = { "Western Plaguelands", 3, 1415 }, [1423] = { "Eastern Plaguelands", 3, 1415 },
    [1424] = { "Hillsbrad Foothills", 3, 1415 }, [1425] = { "The Hinterlands", 3, 1415 },
    [1426] = { "Dun Morogh", 3, 1415 }, [1427] = { "Searing Gorge", 3, 1415 },
    [1428] = { "Burning Steppes", 3, 1415 }, [1429] = { "Elwynn Forest", 3, 1415 },
    [1430] = { "Deadwind Pass", 3, 1415 }, [1431] = { "Duskwood", 3, 1415 },
    [1432] = { "Loch Modan", 3, 1415 }, [1433] = { "Redridge Mountains", 3, 1415 },
    [1434] = { "Stranglethorn Vale", 3, 1415 }, [1435] = { "Swamp of Sorrows", 3, 1415 },
    [1436] = { "Westfall", 3, 1415 }, [1437] = { "Wetlands", 3, 1415 },
    [1438] = { "Teldrassil", 3, 1414 }, [1439] = { "Darkshore", 3, 1414 }, [1440] = { "Ashenvale", 3, 1414 },
    [1441] = { "Thousand Needles", 3, 1414 }, [1442] = { "Stonetalon Mountains", 3, 1414 },
    [1443] = { "Desolace", 3, 1414 }, [1444] = { "Feralas", 3, 1414 }, [1445] = { "Dustwallow Marsh", 3, 1414 },
    [1446] = { "Tanaris", 3, 1414 }, [1447] = { "Azshara", 3, 1414 }, [1448] = { "Felwood", 3, 1414 },
    [1449] = { "Un'Goro Crater", 3, 1414 }, [1450] = { "Moonglade", 3, 1414 }, [1451] = { "Silithus", 3, 1414 },
    [1452] = { "Winterspring", 3, 1414 }, [1453] = { "Stormwind City", 3, 1415 },
    [1454] = { "Orgrimmar", 3, 1414 }, [1455] = { "Ironforge", 3, 1415 }, [1456] = { "Thunder Bluff", 3, 1414 },
    [1457] = { "Darnassus", 3, 1414 }, [1458] = { "Undercity", 3, 1415 },
    [1459] = { "Alterac Valley", 3, 947 }, [1460] = { "Warsong Gulch", 3, 947 }, [1461] = { "Arathi Basin", 3, 947 },
    [1463] = { "Eastern Kingdoms", 2, 0 }, [1464] = { "Kalimdor", 2, 0 },
    [1554] = { "Serpentshrine Cavern", 4, 1946 }, [1555] = { "Tempest Keep", 4, 1953 },
    [1941] = { "Eversong Woods", 3, 1415 }, [1942] = { "Ghostlands", 3, 1415 },
    [1943] = { "Azuremyst Isle", 3, 1414 }, [1944] = { "Hellfire Peninsula", 3, 1945 },
    [1945] = { "Outland", 2, 946 }, [1946] = { "Zangarmarsh", 3, 1945 }, [1947] = { "The Exodar", 3, 1414 },
    [1948] = { "Shadowmoon Valley", 3, 1945 }, [1949] = { "Blade's Edge Mountains", 3, 1945 },
    [1950] = { "Bloodmyst Isle", 3, 1414 }, [1951] = { "Nagrand", 3, 1945 }, [1952] = { "Terokkar Forest", 3, 1945 },
    [1953] = { "Netherstorm", 3, 1945 }, [1954] = { "Silvermoon City", 3, 1415 },
    [1955] = { "Shattrath City", 3, 1945 }, [1956] = { "Eye of the Storm", 3, 1953 },
    [1957] = { "Isle of Quel'Danas", 3, 1415 },
}
-- uiMap = { { instance, Nmin, Wmin, Nmax, Wmax, u0, v0, u1, v1 }, ... } in OrderIndex order
local ROWS = {
    [233] = { { 309, -12560.416, -2570.833, -11308.333, -693.75, 0, 0, 1, 1 } },
    [234] = { { 429, 0, 0, 0, 0, 0, 0, 1, 1 } },
    [235] = { { 429, 200, -387.5, 1050, 887.5, 0, 0, 1, 1 } },
    [274] = { { 560, 1572.917, -477.083, 3127.083, 1854.167, 0, 0, 1, 1 } },
    [332] = { { 548, -400, -1362.5, 650.002, 212.502, 0, 0, 1, 1 } },
    [334] = { { 550, -100, -787.5, 950, 787.5, 0, 0, 1, 1 } },
    [347] = { { 543, -1492.48, 1294.72, -1029.44, 1989.28, 0, 0, 1, 1 } },
    [350] = { { 532, -11189.6, -2225.024, -10822.9, -1674.976, 0, 0, 1, 1 } },
    [947] = { { 1, -12800, -9600, 12266.7, 6933.3, 0.0399, 0.0855, 0.4083, 0.9234 },
              { 0, -16000, -7466.7, 6933.3, 8000, 0.5523, 0.1526, 0.8984, 0.9224 },
              { 530, -6933.3, -15466.7, 533.3, -9066.7, 0.0502, 0.3398, 0.1422, 0.4756 },
              { 530, 4800, -11200, 13866.7, -4266.7, 0.8714, 0.2439, 0.983, 0.4251 } },
    [987] = { { 530, -5867, -1600, 6400, 10670, 0, 0, 1, 1 } },
    [1411] = { { 1, -1716.667, -7250, 1808.333, -1962.5, 0, 0, 1, 1 } },
    [1412] = { { 1, -3697.917, -3089.583, -272.917, 2047.917, 0, 0, 1, 1 } },
    [1413] = { { 1, -5143.75, -7510.417, 1612.5, 2622.917, 0, 0, 1, 1 } },
    [1414] = { { 1, -11733.3, -19733.211, 12799.9, 17066.6, 0, 0, 1, 1 },
               { 530, -6933.33, -16000, 533.33, -8000, 0.202898, 0.08, 0.42029, 0.39 } },
    [1415] = { { 0, -15973.344, -22569.211, 11176.344, 18171.971, 0, 0, 1, 1 },
               { 530, 4800, -10133.3, 16000, -2666.67, 0.45258, -0.08927, 0.6385, 0.323258 } },
    [1416] = { { 0, -366.667, -2016.667, 1500, 783.333, 0, 0, 1, 1 } },
    [1417] = { { 0, -2533.333, -4466.667, -133.333, -866.667, 0, 0, 1, 1 } },
    [1418] = { { 0, -7547.917, -4566.667, -5889.583, -2079.167, 0, 0, 1, 1 } },
    [1419] = { { 0, -12800, -4591.667, -10566.666, -1241.667, 0, 0, 1, 1 } },
    [1420] = { { 0, 825, -1485.417, 3837.5, 3033.333, 0, 0, 1, 1 } },
    [1421] = { { 0, -1133.333, -750, 1666.667, 3450, 0, 0, 1, 1 } },
    [1422] = { { 0, 500, -3883.333, 3366.667, 416.667, 0, 0, 1, 1 } },
    [1423] = { { 0, 1218.75, -6056.25, 3800, -2185.417, 0, 0, 1, 1 } },
    [1424] = { { 0, -1733.333, -2133.333, 400, 1066.667, 0, 0, 1, 1 } },
    [1425] = { { 0, -1100, -5425, 1466.667, -1575, 0, 0, 1, 1 } },
    [1426] = { { 0, -7160.417, -3122.917, -3877.083, 1802.083, 0, 0, 1, 1 } },
    [1427] = { { 0, -7587.5, -2554.167, -6100, -322.917, 0, 0, 1, 1 } },
    [1428] = { { 0, -8983.333, -3195.833, -7031.25, -266.667, 0, 0, 1, 1 } },
    [1429] = { { 0, -10254.166, -1935.417, -7939.583, 1535.417, 0, 0, 1, 1 } },
    [1430] = { { 0, -11533.333, -3333.333, -9866.666, -833.333, 0, 0, 1, 1 } },
    [1431] = { { 0, -11516.666, -1866.667, -9716.666, 833.333, 0, 0, 1, 1 } },
    [1432] = { { 0, -6327.083, -4752.083, -4487.5, -1993.75, 0, 0, 1, 1 } },
    [1433] = { { 0, -10022.916, -3741.667, -8575, -1570.833, 0, 0, 1, 1 } },
    [1434] = { { 0, -15422.916, -4160.417, -11168.75, 2220.833, 0, 0, 1, 1 } },
    [1435] = { { 0, -11150, -4516.667, -9620.833, -2222.917, 0, 0, 1, 1 } },
    [1436] = { { 0, -11733.333, -483.333, -9400, 3016.667, 0, 0, 1, 1 } },
    [1437] = { { 0, -4904.167, -4525, -2147.917, -389.583, 0, 0, 1, 1 } },
    [1438] = { { 1, 8437.5, -1277.083, 11831.25, 3814.583, 0, 0, 1, 1 } },
    [1439] = { { 1, 3966.667, -3608.333, 8333.333, 2941.667, 0, 0, 1, 1 } },
    [1440] = { { 1, 829.167, -4066.667, 4672.917, 1700, 0, 0, 1, 1 } },
    [1441] = { { 1, -6900, -4833.333, -3966.667, -433.333, 0, 0, 1, 1 } },
    [1442] = { { 1, -339.583, -1637.5, 2916.667, 3245.833, 0, 0, 1, 1 } },
    [1443] = { { 1, -2545.833, -262.5, 452.083, 4233.333, 0, 0, 1, 1 } },
    [1444] = { { 1, -7000, -1508.333, -2366.667, 5441.667, 0, 0, 1, 1 } },
    [1445] = { { 1, -5533.333, -6225, -2033.333, -975, 0, 0, 1, 1 } },
    [1446] = { { 1, -10475, -7118.75, -5875, -218.75, 0, 0, 1, 1 } },
    [1447] = { { 1, 1960.417, -8347.916, 5341.667, -3277.083, 0, 0, 1, 1 } },
    [1448] = { { 1, 3300, -4108.333, 7133.333, 1641.667, 0, 0, 1, 1 } },
    [1449] = { { 1, -8433.333, -3166.667, -5966.667, 533.333, 0, 0, 1, 1 } },
    [1450] = { { 1, 6952.083, -3689.583, 8491.666, -1381.25, 0, 0, 1, 1 } },
    [1451] = { { 1, -8281.25, -945.834, -5958.334, 2537.5, 0, 0, 1, 1 } },
    [1452] = { { 1, 3800, -7416.667, 8533.333, -316.667, 0, 0, 1, 1 } },
    [1453] = { { 0, -9175.205, 36.701, -8278.851, 1380.971, 0, 0, 1, 1 } },
    [1454] = { { 1, 1338.461, -5083.206, 2273.877, -3680.601, 0, 0, 1, 1 } },
    [1455] = { { 0, -5096.846, -1504.216, -4569.241, -713.591, 0, 0, 1, 1 } },
    [1456] = { { 1, -1545.833, -527.083, -850, 516.667, 0, 0, 1, 1 } },
    [1457] = { { 1, 9532.587, 1880.03, 10238.316, 2938.363, 0, 0, 1, 1 } },
    [1458] = { { 0, 1237.841, -86.182, 1877.945, 873.193, 0, 0, 1, 1 } },
    [1459] = { { 30, -1739.583, -2456.25, 1085.417, 1781.25, 0, 0, 1, 1 } },
    [1460] = { { 489, 862.5, 895.833, 1627.083, 2041.667, 0, 0, 1, 1 } },
    [1461] = { { 529, 337.5, 102.083, 1508.333, 1858.333, 0, 0, 1, 1 } },
    [1463] = { { 0, -16530, -16530, 12270, 12270, 0, 0, 1, 1 },
               { 530, 4800, -11200, 13866.7, -4266.7, 0.4962, 0.0304, 0.7234, 0.3486 } },
    [1464] = { { 1, -11870, -13370, 12470, 10970, 0, 0, 1, 1 },
               { 530, -6933.3, -15466.7, 533.3, -9066.7, 0.1002, 0.0838, 0.3667, 0.3768 } },
    [1941] = { { 530, 7758.333, -9412.5, 11041.666, -4487.5, 0, 0, 1, 1 } },
    [1942] = { { 530, 6066.667, -8583.333, 8266.666, -5283.333, 0, 0, 1, 1 } },
    [1943] = { { 530, -5508.333, -14570.833, -2793.75, -10500, 0, 0, 1, 1 } },
    [1944] = { { 530, -1962.5, 375, 1481.25, 5539.583, 0, 0, 1, 1 } },
    [1945] = { { 530, -5821.359, -4468.039, 5821.359, 12996.039, 0, 0, 1, 1 } },
    [1946] = { { 530, -1416.667, 4447.917, 1935.417, 9475, 0, 0, 1, 1 } },
    [1947] = { { 530, -4314.371, -12123.138, -3609.683, -11066.367, 0, 0, 1, 1 } },
    [1948] = { { 530, -5614.583, -1275, -1947.917, 4225, 0, 0, 1, 1 } },
    [1949] = { { 530, 791.667, 3420.833, 4408.333, 8845.833, 0, 0, 1, 1 } },
    [1950] = { { 530, -2933.333, -13337.499, -758.333, -10075, 0, 0, 1, 1 } },
    [1951] = { { 530, -3641.667, 4770.833, 41.667, 10295.833, 0, 0, 1, 1 } },
    [1952] = { { 530, -4600, 1683.333, -1000, 7083.333, 0, 0, 1, 1 } },
    [1953] = { { 530, 1739.583, -91.667, 5456.25, 5483.333, 0, 0, 1, 1 } },
    [1954] = { { 530, 9346.938, -7612.208, 10153.709, -6400.75, 0, 0, 1, 1 } },
    [1955] = { { 530, -2344.788, 4829.009, -1473.954, 6135.259, 0, 0, 1, 1 } },
    [1956] = { { 566, 1404.167, 389.583, 2918.75, 2660.417, 0, 0, 1, 1 } },
    [1957] = { { 530, 11350, -8629.166, 13568.749, -5302.083, 0, 0, 1, 1 } },
}
M.MAPS, M.ROWS = MAPS, ROWS

local function MapInfoOf(id)
    local m = MAPS[id]
    if not m then return nil end
    return { mapID = id, name = m[1], mapType = m[2], parentMapID = m[3] }
end

local function IsAncestor(top, child)
    local id, depth = child, 0
    while id and id ~= 0 and depth < 20 do
        if id == top then return true end
        id = MAPS[id] and MAPS[id][3]
        depth = depth + 1
    end
    return false
end

-- World X grows north, Y grows west; map x runs with -west, map y with -north
local function RowWorld(row, x, y)
    local north = row[4] - (y - row[7]) / (row[9] - row[7]) * (row[4] - row[2])
    local west = row[5] - (x - row[6]) / (row[8] - row[6]) * (row[5] - row[3])
    return row[1], north, west
end
local function RowUI(row, north, west)
    return row[6] + (row[5] - west) / (row[5] - row[3]) * (row[8] - row[6]),
        row[7] + (row[4] - north) / (row[4] - row[2]) * (row[9] - row[7])
end
local function InUI(row, x, y)
    return x >= row[6] and x <= row[8] and y >= row[7] and y <= row[9]
end
local function InWorld(row, inst, north, west)
    return row[1] == inst and north >= row[2] and north <= row[4] and west >= row[3] and west <= row[5]
end

-- GetWorldPosFromMapPos: the last row whose UI square holds the point
local function FixtureWorld(map, x, y)
    local rows = ROWS[map]
    if not rows then return nil end
    for i = #rows, 1, -1 do
        if InUI(rows[i], x, y) and rows[i][4] ~= rows[i][2] then return RowWorld(rows[i], x, y) end
    end
    return nil
end
M.World = FixtureWorld

-- The inverse, for the player's and the corpse's map positions
local function FixtureMapPos(map, inst, north, west)
    local rows = ROWS[map]
    if not rows or inst == nil then return nil end
    for i = #rows, 1, -1 do
        local row = rows[i]
        if row[4] ~= row[2] and InWorld(row, inst, north, west) then
            local x, y = RowUI(row, north, west)
            if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
        end
    end
    return nil
end
M.MapPos = function(map, inst, north, west) return FixtureMapPos(map, inst, north, west) end

local function FixtureRect(child, top)
    if not IsAncestor(top, child) or child == top then return nil end
    local crow = ROWS[child] and ROWS[child][1]
    local trows = ROWS[top]
    if not crow or not trows then return nil end
    local cn, cw = (crow[2] + crow[4]) / 2, (crow[3] + crow[5]) / 2
    for i = #trows, 1, -1 do
        local t = trows[i]
        if InWorld(t, crow[1], cn, cw) then
            local left, topY = RowUI(t, crow[4], crow[5])
            local right, bottom = RowUI(t, crow[2], crow[3])
            return left, right, topY, bottom
        end
    end
    return nil
end

local function FixtureInfoAt(map, x, y)
    local inst, n, w = FixtureWorld(map, x, y)
    if not inst then return nil end
    local best, bestArea
    for id, m in pairs(MAPS) do
        if m[3] == map and m[2] >= 1 and m[2] <= 3 and ROWS[id] then
            for _, row in ipairs(ROWS[id]) do
                if InWorld(row, inst, n, w) then
                    local area = (row[4] - row[2]) * (row[5] - row[3])
                    if not best or area < bestArea then best, bestArea = id, area end
                end
            end
        end
    end
    return best and MapInfoOf(best) or nil
end

local function FixtureChildren(id)
    local kids = {}
    for kid, m in pairs(MAPS) do
        if m[3] == id then kids[#kids + 1] = MapInfoOf(kid) end
    end
    table.sort(kids, function(a, b) return a.mapID < b.mapID end)
    return kids
end

-- ===========================================================================
-- Output, errors
-- ===========================================================================
M.prints, M.errors, M.sounds, M.sent, M.chat, M.popups, M.tooltip = {}, {}, {}, {}, {}, {}, {}
M.blocked, M.writes, M.loadErrors, M.settingsOpened = {}, {}, {}, {}
M.menu = {}
M.itemRefs, M.filterCalls = {}, 0

function M.ClearLog()
    for _, list in ipairs({ M.prints, M.errors, M.sounds, M.sent, M.chat, M.popups, M.blocked, M.itemRefs }) do
        for i = #list, 1, -1 do list[i] = nil end
    end
end

function M.Has(list, needle)
    for _, s in ipairs(list or {}) do
        if type(s) == "string" and s:find(needle, 1, true) then return true end
    end
    return false
end

local function Capture(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    M.prints[#M.prints + 1] = table.concat(parts, " ")
end
M.realPrint = realPrint

-- ===========================================================================
-- Widgets
-- ===========================================================================
local W                          -- the current world (per Boot)
local NewWidget
local WidgetMT = {}

local function FireScript(widget, name, ...)
    local handler = widget.__scripts and widget.__scripts[name]
    if handler then return handler(widget, ...) end
end

local METHODS = {}
function METHODS.SetWidth(s, w) s.__w = w end
function METHODS.GetWidth(s) return s.__w or 0 end
function METHODS.SetHeight(s, h) s.__h = h end
function METHODS.GetHeight(s) return s.__h or 0 end
function METHODS.SetSize(s, w, h) s.__w, s.__h = w, h end
function METHODS.GetSize(s) return s.__w or 0, s.__h or 0 end
function METHODS.SetPoint(s, point, rel, relPoint, x, y)
    s.__points = s.__points or {}
    if type(rel) == "number" then rel, relPoint, x, y = nil, point, rel, relPoint end
    s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end
function METHODS.ClearAllPoints(s) s.__points = {} end
function METHODS.GetNumPoints(s) return #(s.__points or {}) end
function METHODS.GetPoint(s, i)
    local p = s.__points and s.__points[i or 1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function METHODS.SetAllPoints(s, rel) s.__allPoints = rel or true end
function METHODS.SetFrameLevel(s, level) s.__level = level end
function METHODS.GetFrameLevel(s) return s.__level or ((s.__parent and s.__parent.GetFrameLevel and s.__parent:GetFrameLevel() or 0) + 1) end
function METHODS.SetFrameStrata(s, strata) s.__strata = strata end
function METHODS.GetFrameStrata(s) return s.__strata or "MEDIUM" end
function METHODS.SetScale(s, v) s.__scale = v end
function METHODS.GetScale(s) return s.__scale or 1 end
function METHODS.GetEffectiveScale(s) return s.__scale or 1 end
function METHODS.GetLeft() return 0 end
function METHODS.GetTop() return 0 end
function METHODS.GetRight() return 0 end
function METHODS.GetBottom() return 0 end
function METHODS.GetCenter() return 0, 0 end
function METHODS.GetName(s) return s.__name end
function METHODS.GetParent(s) return s.__parent end
function METHODS.SetParent(s, p) s.__parent = p end
function METHODS.GetObjectType(s) return s.__kind end
function METHODS.SetText(s, text)
    if s.__kind == "FontString" and not s.__font then
        error("FontString:SetText(): Font not set", 2)
    end
    s.__text = text
end
function METHODS.SetFormattedText(s, fmt, ...) s:SetText(string.format(fmt, ...)) end
function METHODS.GetText(s) return s.__text end
function METHODS.SetFontObject(s, font) s.__font = font or "?" end
function METHODS.SetFont(s, path, size, flags) s.__font = path; s.__fontSize = size; s.__fontFlags = flags; return true end
function METHODS.GetFont(s) return "Fonts\\FRIZQT__.TTF", s.__fontSize or 12, s.__fontFlags or "" end
function METHODS.SetWordWrap(s, v) s.__wordWrap = v and true or false end
function METHODS.GetWordWrap(s) return s.__wordWrap ~= false end
function METHODS.SetMaxLines(s, n) s.__maxLines = n end
function METHODS.GetMaxLines(s) return s.__maxLines or 0 end
function METHODS.GetStringWidth(s) return #(tostring(s.__text or "")) * 6 end
function METHODS.GetStringHeight(s) return (s.__text and s.__text ~= "") and 12 or 0 end
function METHODS.SetTextColor(s, r, g, b, a) s.__textColor = { r, g, b, a } end
function METHODS.GetTextColor(s) local c = s.__textColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function METHODS.SetColorTexture(s, r, g, b, a) s.__color = { r, g, b, a } end
function METHODS.SetVertexColor(s, r, g, b, a) s.__vertex = { r, g, b, a } end
function METHODS.GetVertexColor(s) local c = s.__vertex or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function METHODS.SetTexture(s, file) s.__texture = file; return true end
function METHODS.GetTexture(s) return s.__texture end
function METHODS.SetTexCoord(s, ...) s.__texCoord = { ... } end
function METHODS.SetAlpha(s, a) s.__alpha = a end
function METHODS.GetAlpha(s) return s.__alpha or 1 end
function METHODS.SetRotation(s, angle) s.__rotation = angle end
function METHODS.GetRotation(s) return s.__rotation or 0 end
function METHODS.Show(s)
    local was = s.__shown
    s.__shown = true
    if not was then FireScript(s, "OnShow") end
end
function METHODS.Hide(s)
    local was = s.__shown
    s.__shown = false
    if was then FireScript(s, "OnHide") end
end
function METHODS.SetShown(s, shown) if shown then s:Show() else s:Hide() end end
function METHODS.IsShown(s) return s.__shown and true or false end
function METHODS.IsVisible(s) return M.Visible(s) end
function METHODS.EnableMouse(s, on) s.__mouse = on and true or false end
function METHODS.IsMouseEnabled(s) return s.__mouse and true or false end
function METHODS.EnableMouseWheel(s, on) s.__wheel = on and true or false end
function METHODS.SetMouseMotionEnabled(s, on) s.__motion = on and true or false end
function METHODS.IsMouseMotionEnabled(s) return s.__motion and true or false end
function METHODS.SetMouseClickEnabled(s, on) s.__click = on and true or false end
function METHODS.IsMouseClickEnabled(s) return s.__click and true or false end
function METHODS.IsMouseOver(s) return s.__mouseOver and true or false end
function METHODS.RegisterForClicks(s, ...) s.__clicks = { ... } end
function METHODS.RegisterForDrag(s, ...) s.__drags = { ... } end
function METHODS.SetMovable(s, v) s.__movable = v end
function METHODS.SetClampedToScreen(s, v) s.__clamped = v end
function METHODS.StartMoving(s) s.__moving = true end
function METHODS.StopMovingOrSizing(s) s.__moving = false end
function METHODS.SetChecked(s, v) s.__checked = v and true or false end
function METHODS.GetChecked(s) return s.__checked end
function METHODS.SetEnabled(s, v) s.__enabled = v and true or false end
function METHODS.Enable(s) s.__enabled = true end
function METHODS.Disable(s) s.__enabled = false end
function METHODS.IsEnabled(s) return s.__enabled ~= false end
function METHODS.SetMotionScriptsWhileDisabled(s, v) s.__motionWhileDisabled = v and true or false end
function METHODS.GetMotionScriptsWhileDisabled(s) return s.__motionWhileDisabled and true or false end
function METHODS.SetValue(s, v) s.__value = v; FireScript(s, "OnValueChanged", v) end
function METHODS.GetValue(s) return s.__value end
function METHODS.SetMinMaxValues(s, a, b) s.__min, s.__max = a, b end
function METHODS.GetMinMaxValues(s) return s.__min or 0, s.__max or 1 end
function METHODS.SetScrollChild(s, child) s.__child = child end
function METHODS.GetVerticalScroll(s) return s.__scroll or 0 end
function METHODS.SetVerticalScroll(s, v) s.__scroll = v end
function METHODS.GetVerticalScrollRange() return 0 end
function METHODS.SetBackdrop(s, b) s.__backdrop = b end
function METHODS.SetBackdropColor(s, r, g, b, a) s.__bdColor = { r, g, b, a } end
function METHODS.SetBackdropBorderColor(s, r, g, b, a) s.__bdBorder = { r, g, b, a } end
function METHODS.SetAutoFocus(s, v) s.__autoFocus = v end
function METHODS.SetFocus(s) s.__focus = true end
function METHODS.ClearFocus(s) s.__focus = false end
function METHODS.HasFocus(s) return s.__focus and true or false end
function METHODS.HighlightText() end
function METHODS.SetMaxLetters(s, n) s.__maxLetters = n end
function METHODS.GetID() return 1 end
-- Protected: refused in combat, as the client refuses it (no error raised)
function METHODS.SetPassThroughButtons(s, ...)
    if W and W.combat then
        M.blocked[#M.blocked + 1] = "SetPassThroughButtons"
        return
    end
    s.__passThrough = { ... }
end
function METHODS.SetScript(s, name, handler) s.__scripts[name] = handler end
function METHODS.GetScript(s, name) return s.__scripts[name] end
function METHODS.HookScript(s, name, handler)
    local previous = s.__scripts[name]
    if previous then
        s.__scripts[name] = function(...) previous(...) handler(...) end
    else
        s.__scripts[name] = handler
    end
end
function METHODS.RegisterEvent(s, event)
    W.registry[event] = W.registry[event] or {}
    for _, f in ipairs(W.registry[event]) do if f == s then return end end
    table.insert(W.registry[event], s)
end
function METHODS.RegisterUnitEvent(s, event) METHODS.RegisterEvent(s, event) end
function METHODS.UnregisterEvent(s, event)
    local list = W.registry[event]
    if list then
        for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
    end
end
function METHODS.UnregisterAllEvents(s)
    for _, list in pairs(W.registry) do
        for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
    end
end
function METHODS.IsEventRegistered(s, event)
    for _, f in ipairs(W.registry[event] or {}) do if f == s then return true end end
    return false
end
function METHODS.CreateTexture(s, name, layer, template, sublevel)
    local t = NewWidget("Texture", name, s)
    t.__layer, t.__sublevel = layer, sublevel
    return t
end
function METHODS.CreateMaskTexture(s, name)
    return NewWidget("MaskTexture", name, s)
end
function METHODS.CreateFontString(s, name, layer, template)
    local t = NewWidget("FontString", name, s)
    t.__layer, t.__font = layer, template
    return t
end
function METHODS.CreateLine(s, name, layer)
    local t = NewWidget("Line", name, s)
    t.__layer = layer
    return t
end
function METHODS.CreateAnimationGroup(s)
    local g = NewWidget("AnimationGroup", nil, s)
    g.CreateAnimation = function(self) return NewWidget("Animation", nil, self) end
    return g
end

local AUTO_PREFIXES = {
    "Set", "Enable", "Disable", "Register", "Unregister", "Clear", "Start", "Stop", "Raise",
    "Lower", "Lock", "Play", "Add", "Highlight", "Hook", "Update", "Insert", "Remove", "Scroll",
}
local function IsAutoMethod(key)
    for _, prefix in ipairs(AUTO_PREFIXES) do
        if key:sub(1, #prefix) == prefix then return true end
    end
    return key:sub(1, 3) == "Get" or key:sub(1, 2) == "Is" or key:sub(1, 3) == "Can"
end

WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    local fn = METHODS[key]
    if not fn and key:match("^[A-Z]") and IsAutoMethod(key) then fn = function() end end
    if fn then rawset(self, key, fn) end
    return fn
end

NewWidget = function(kind, name, parent)
    local w = setmetatable({ __kind = kind, __name = name, __parent = parent, __scripts = {},
                             __shown = true, __children = {} }, WidgetMT)
    if parent and type(parent) == "table" and parent.__children then
        parent.__children[#parent.__children + 1] = w
    end
    if W then W.widgets[#W.widgets + 1] = w end
    return w
end
M.NewWidget = function(...) return NewWidget(...) end

function M.Visible(s)
    local w, depth = s, 0
    while w and depth < 50 do
        if type(w) ~= "table" then return true end
        if w.__shown == false then return false end
        if w.IsShown and not w.__kind then return w:IsShown() end
        w = w.__parent
        depth = depth + 1
    end
    return true
end

local function MakeFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name, parent)
    f.__template = template
    -- A frame created without a parent is shown; with one, it follows it
    local t = template or ""
    if frameType == "CheckButton" or t:find("CheckButton") then
        f.Text = NewWidget("FontString", nil, f)
        f.Text.__font = "GameFontNormal"
    end
    if t:find("UIPanelButtonTemplate") then
        f.Text = NewWidget("FontString", nil, f)
        f.Text.__font = "GameFontNormal"
        f.SetText = function(self, text) self.__text = text; self.Text.__text = text end
    end
    if t:find("BasicFrameTemplate") then
        f.TitleText = NewWidget("FontString", nil, f)
        f.TitleText.__font = "GameFontNormal"
        f.CloseButton = NewWidget("Button", nil, f)
        for _, key in ipairs({ "Bg", "TitleBg", "TopLeftCorner", "TopRightCorner", "TopBorder",
                "BotLeftCorner", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder",
                "TopTileStreaks", "InsetBg" }) do
            f[key] = NewWidget("Texture", nil, f)
        end
    end
    if t:find("UIPanelScrollFrameTemplate") and name then
        local bar = NewWidget("Slider", name .. "ScrollBar", f)
        rawset(_G, name .. "ScrollBar", bar)
        rawset(_G, name .. "ScrollBarScrollUpButton", NewWidget("Button", nil, bar))
        rawset(_G, name .. "ScrollBarScrollDownButton", NewWidget("Button", nil, bar))
        f.ScrollBar = bar
    end
    if t:find("InputBoxTemplate") or frameType == "EditBox" then
        f.__text = ""
    end
    if name then
        -- a named frame is a global the client creates: recorded like a write
        M.writes[#M.writes + 1] = { name = name, phase = W and W.phase or "?", frame = true }
        rawset(_G, name, f)
    end
    return f
end

-- ===========================================================================
-- Pools, mixins, the world map (Blizzard_MapCanvas and Pools.lua, 2.5.6)
-- ===========================================================================
local function Mixin(object, ...)
    for i = 1, select("#", ...) do
        for k, v in pairs((select(i, ...))) do object[k] = v end
    end
    return object
end

local function NewObjectPool(createFunc, resetFunc)
    local pool = { createFunc = createFunc, resetFunc = resetFunc, activeObjects = {}, inactiveObjects = {},
                   activeObjectCount = 0, created = 0 }
    function pool:Acquire()
        local object = table.remove(self.inactiveObjects)
        local new = object == nil
        if new then
            object = self.createFunc(self)
            assert(type(object) == "table", "pool createFunc returned no object")
            self.created = self.created + 1
            if self.resetFunc then self.resetFunc(self, object, new) end
        end
        self.activeObjects[object] = true
        self.activeObjectCount = self.activeObjectCount + 1
        return object, new
    end
    function pool:Release(object)
        if not self.activeObjects[object] then return false end
        if self.resetFunc then self.resetFunc(self, object) end
        self.inactiveObjects[#self.inactiveObjects + 1] = object
        self.activeObjects[object] = nil
        self.activeObjectCount = self.activeObjectCount - 1
        return true
    end
    function pool:ReleaseAll()
        for object in pairs(self.activeObjects) do self:Release(object) end
    end
    function pool:EnumerateActive() return pairs(self.activeObjects) end
    function pool:GetNumActive() return self.activeObjectCount end
    return pool
end

local function HideAndClearAnchors(_, region)
    region:Hide()
    region:ClearAllPoints()
end

local function PoolPins(pool)
    local out = {}
    if pool then for pin in pool:EnumerateActive() do out[#out + 1] = pin end end
    return out
end
M.PoolPins = PoolPins

-- The pin-level manager's absolute levels on TBC (Blizzard_WorldMap.lua's list)
local PIN_LEVELS = {
    PIN_FRAME_LEVEL_AREA_POI = 2018, PIN_FRAME_LEVEL_DUNGEON_ENTRANCE = 2030,
    PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST = 2740, PIN_FRAME_LEVEL_GROUP_MEMBER = 2754,
    PIN_FRAME_LEVEL_CORPSE = 2755, PIN_FRAME_LEVEL_TOPMOST = 2757,
}
M.PIN_LEVELS = PIN_LEVELS

local function NewWorldMap()
    local wm = {
        writes = {}, providers = {}, providerAdds = 0, mapID = 1429, maximized = false,
        canvasDirty = false, canvasPasses = 0, canvasErrors = 0, cursor = { 0.5, 0.5 },
    }
    local frameWidget = NewWidget("Frame", nil, nil)
    frameWidget.__shown = false
    local container = NewWidget("ScrollFrame", nil, frameWidget)
    container.__level, container.__h, container.__w = 5, 600, 900
    local canvas = NewWidget("Frame", nil, container)
    canvas.__w, canvas.__h = 900, 600
    container.GetNormalizedCursorPosition = function() return wm.cursor[1], wm.cursor[2] end
    container.GetCanvas = function() return canvas end
    local border = NewWidget("Frame", nil, frameWidget)
    local fields = { pinPools = {}, ScrollContainer = container, BorderFrame = border, __widget = frameWidget }
    wm.fields, wm.container, wm.canvas, wm.widget = fields, container, canvas, frameWidget

    -- Widget methods pass to the frame widget behind the proxy
    for _, key in ipairs({ "HookScript", "SetScript", "GetScript", "IsShown", "IsVisible", "GetFrameLevel",
            "GetWidth", "GetHeight", "GetEffectiveScale", "GetScale", "GetFrameStrata", "CreateTexture",
            "CreateFontString", "GetParent" }) do
        fields[key] = function(_, ...) return frameWidget[key](frameWidget, ...) end
    end
    function fields.Show() frameWidget:Show() end
    function fields.Hide() frameWidget:Hide() end
    function fields.GetMapID() return wm.mapID end
    function fields.SetMapID(self, uiMapId)
        wm.mapID = uiMapId
        self:OnMapChanged()
    end
    function fields.OnMapChanged()
        for _, provider in ipairs(wm.providers) do provider:OnMapChanged() end
    end
    function fields.IsMaximized() return wm.maximized end
    -- TBC/Blizzard_WorldMap.lua SynchronizeDisplayState: maximized is
    -- FULLSCREEN strata with an opaque BlackoutFrame over all of UIParent,
    -- windowed is MEDIUM (M.SetMapMaximized)
    function fields.SynchronizeDisplayState()
        frameWidget.__strata = wm.maximized and "FULLSCREEN" or "MEDIUM"
    end
    function fields.GetCanvas() return canvas end
    function fields.GetCanvasContainer() return container end
    function fields.GetNormalizedCursorPosition() return wm.cursor[1], wm.cursor[2] end
    function fields.AddDataProvider(self, provider)
        wm.providerAdds = wm.providerAdds + 1
        wm.providers[#wm.providers + 1] = provider
        provider:OnAdded(self)
    end
    function fields.RemoveDataProvider(self, provider)
        for i = #wm.providers, 1, -1 do if wm.providers[i] == provider then table.remove(wm.providers, i) end end
    end
    local levels = { GetValidFrameLevel = function(_, levelType) return PIN_LEVELS[levelType] or 2000 end }
    function fields.GetPinFrameLevelsManager() return levels end
    -- Blizzard_MapCanvas.lua AcquirePin, in its order, with the mouse wiring
    -- a NEW click/motion-enabled pin gets
    function fields.AcquirePin(self, template, ...)
        local pool = fields.pinPools[template]
        assert(pool, "AcquirePin: no pool for " .. tostring(template))
        local pin, isNew = pool:Acquire()
        pin.pinTemplate = template
        pin.owningMap = self
        if isNew then
            -- Blizzard's OnPinMouseUp: pin:OnMouseUp(button) always, then
            -- pin:OnClick(button) only when the release is inside the pin
            -- (upInside); OnMouseDown is the mixin's own method
            if pin.IsMouseClickEnabled and pin:IsMouseClickEnabled() then
                pin:SetScript("OnMouseUp", function(p, button, upInside)
                    p:OnMouseUp(button)
                    if upInside and p.OnClick then p:OnClick(button) end
                end)
                pin:SetScript("OnMouseDown", pin.OnMouseDown)
            end
            if pin.IsMouseMotionEnabled and pin:IsMouseMotionEnabled() then
                assert(pin:GetScript("OnEnter") == nil, "AcquirePin: a new motion pin already has OnEnter")
                assert(pin:GetScript("OnLeave") == nil, "AcquirePin: a new motion pin already has OnLeave")
                pin:SetScript("OnEnter", function(p) if p.OnMouseEnter then p:OnMouseEnter() end end)
                pin:SetScript("OnLeave", function(p) if p.OnMouseLeave then p:OnMouseLeave() end end)
            end
            pin:OnLoad()
        end
        wm.canvasDirty = true
        pin:Show()
        pin:OnAcquired(...)
        return pin
    end
    function fields.RemoveAllPinsByTemplate(_, template)
        local pool = fields.pinPools[template]
        if pool then
            pool:ReleaseAll()
            wm.canvasDirty = true
        end
    end
    function fields.EnumeratePinsByTemplate(_, template)
        local list = PoolPins(fields.pinPools[template])
        local i = 0
        return function() i = i + 1; return list[i] end
    end
    function wm.CanvasPass()
        if not wm.canvasDirty then return end
        wm.canvasDirty = false
        wm.canvasPasses = wm.canvasPasses + 1
        for _, pool in pairs(fields.pinPools) do
            for _, pin in ipairs(PoolPins(pool)) do
                local ok, err = pcall(function() pin:OnCanvasScaleChanged(); pin:SetNudgeVector(nil, nil, nil, nil) end)
                if not ok then
                    wm.canvasErrors = wm.canvasErrors + 1
                    M.errors[#M.errors + 1] = "Blizzard_MapCanvas: " .. tostring(err)
                end
            end
        end
    end
    frameWidget.__scripts.OnShow = function()
        for _, provider in ipairs(wm.providers) do provider:RefreshAllData(true) end
    end

    wm.frame = setmetatable({}, {
        __fields = fields,
        __index = fields,
        __newindex = function(_, key, value)
            wm.writes[#wm.writes + 1] = tostring(key)
            fields[key] = value
        end,
    })
    return wm
end

-- ===========================================================================
-- The SV writer (16 significant digits, no functions or userdata)
-- ===========================================================================
local function SerializeValue(v, out, depth)
    local t = type(v)
    if t == "number" then
        if v ~= v then out[#out + 1] = "0/0"
        elseif v == math.huge then out[#out + 1] = "math.huge"
        elseif v == -math.huge then out[#out + 1] = "-math.huge"
        elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
        else out[#out + 1] = string.format("%.16g", v) end
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    elseif t == "boolean" then
        out[#out + 1] = tostring(v)
    elseif t == "table" then
        if depth > 40 then out[#out + 1] = "nil" return end
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
            return type(a) < type(b)
        end)
        for _, k in ipairs(keys) do
            local val = v[k]
            local vt = type(val)
            local kt = type(k)
            if vt ~= "function" and vt ~= "userdata" and vt ~= "thread"
                and (kt == "string" or kt == "number" or kt == "boolean") then
                out[#out + 1] = "["
                SerializeValue(k, out, depth + 1)
                out[#out + 1] = "]="
                SerializeValue(val, out, depth + 1)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
end

function M.Serialize(v)
    local out = {}
    SerializeValue(v, out, 0)
    return table.concat(out)
end

function M.Deserialize(text)
    local chunk = loadstring("return " .. text)
    if not chunk then return nil end
    setfenv(chunk, { math = math })
    return chunk()
end

-- ===========================================================================
-- The mock globals (rebuilt per Boot)
-- ===========================================================================
local MOCK                         -- served through _G's __index
local function Install(name, value) MOCK[name] = value end

local function Vector(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

local function UnitWorldOf(unit)
    if unit == "player" then
        if W.noPosition or not W.player.inst then return nil end
        return W.player.north, W.player.west, 0, W.player.inst
    end
    local u = W.units[unit]
    if u and u.inst then return u.north, u.west, 0, u.inst end
    return nil
end

local function UnitMapOf(unit)
    if unit == "player" then
        if W.noMap then return nil end
        return W.player.map
    end
    local u = W.units[unit]
    return u and u.map or nil
end

local function InstallClient()
    MOCK = {}
    -- Lua-level helpers the client defines
    Install("time", function() return math.floor(W.epoch + W.now) end)
    Install("date", os.date)
    Install("GetTime", function() return W.now end)
    Install("wipe", function(t) for k in pairs(t) do t[k] = nil end return t end)
    Install("tinsert", table.insert)
    Install("tremove", table.remove)
    Install("strlower", string.lower)
    Install("strupper", string.upper)
    Install("strfind", string.find)
    Install("strsub", string.sub)
    Install("strlen", string.len)
    Install("format", string.format)
    Install("gsub", string.gsub)
    Install("floor", math.floor)
    Install("ceil", math.ceil)
    Install("abs", math.abs)
    Install("min", math.min)
    Install("max", math.max)
    Install("sqrt", math.sqrt)
    Install("strtrim", function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end)
    Install("strsplit", function(sep, s, n)
        local out, pos = {}, 1
        while true do
            if n and #out == n - 1 then out[#out + 1] = s:sub(pos) break end
            local a, b = s:find(sep, pos, true)
            if not a then out[#out + 1] = s:sub(pos) break end
            out[#out + 1] = s:sub(pos, a - 1)
            pos = b + 1
        end
        return unpack(out)
    end)
    Install("strjoin", function(sep, ...) return table.concat({ ... }, sep) end)
    if not rawget(_G, "bit") then Install("bit", require("bit")) end
    Install("geterrorhandler", function() return function(err) M.errors[#M.errors + 1] = tostring(err) end end)
    Install("seterrorhandler", function() end)
    Install("CallErrorHandler", function(err) M.errors[#M.errors + 1] = tostring(err) end)
    Install("securecall", function(fn, ...) return fn(...) end)
    Install("issecure", function() return false end)
    Install("hooksecurefunc", function(target, name, post)
        if type(target) == "string" then target, name, post = _G, target, name end
        local original = target[name]
        assert(type(original) == "function", "hooksecurefunc on a missing method " .. tostring(name))
        local wrapper = function(...)
            local results = { original(...) }
            post(...)
            return unpack(results)
        end
        local mt = getmetatable(target)
        if mt and mt.__fields then mt.__fields[name] = wrapper else rawset(target, name, wrapper) end
    end)
    Install("Mixin", Mixin)
    Install("CreateFromMixins", function(...) return Mixin({}, ...) end)
    Install("CreateVector2D", Vector)

    -- Frames
    Install("CreateFrame", MakeFrame)
    local uiParent = NewWidget("Frame", "UIParent")
    uiParent.__w, uiParent.__h = 1920, 1080
    Install("UIParent", uiParent)
    Install("WorldFrame", NewWidget("Frame", "WorldFrame"))
    for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight",
            "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall", "GameFontHighlightLarge",
            "GameFontHighlightOutline", "GameFontHighlightSmallOutline", "GameFontNormalLargeOutline",
            "GameFontNormalOutline", "GameFontHighlightMedium", "GameFontWhite", "NumberFontNormal" }) do
        Install(f, NewWidget("Font", f))
    end
    local tooltip = NewWidget("GameTooltip", "GameTooltip")
    tooltip.SetOwner = function(self, owner, anchor)
        for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end
        self.__owner, self.__anchor = owner, anchor
    end
    tooltip.GetOwner = function(self) return self.__owner end
    tooltip.SetText = function(_, text) M.tooltip[#M.tooltip + 1] = tostring(text) end
    tooltip.AddLine = function(_, text) M.tooltip[#M.tooltip + 1] = tostring(text) end
    tooltip.AddDoubleLine = function(_, l, r) M.tooltip[#M.tooltip + 1] = tostring(l) .. "  " .. tostring(r) end
    tooltip.NumLines = function() return #M.tooltip end
    tooltip.Hide = function(self) self.__shown = false; self.__owner = nil end
    Install("GameTooltip", tooltip)
    Install("UISpecialFrames", {})
    Install("OKAY", "Okay")
    Install("CANCEL", "Cancel")
    Install("ACCEPT", "Accept")
    Install("BACKDROP_SLIDER_8_8", {})
    Install("SOUNDKIT", {
        IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
        MAP_PING = 3175, IG_QUEST_LIST_COMPLETE = 878, IG_QUEST_LOG_OPEN = 844, READY_CHECK = 8960,
        IG_CHARACTER_INFO_TAB = 841, U_CHAT_SCROLL_BUTTON = 1115,
    })
    Install("PlaySound", function(id, channel) M.sounds[#M.sounds + 1] = { id = id, channel = channel }; return true end)
    Install("PlaySoundFile", function(file, channel) M.sounds[#M.sounds + 1] = { id = file, channel = channel }; return true end)
    Install("RAID_CLASS_COLORS", { PALADIN = { r = 0.96, g = 0.55, b = 0.73 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } })
    Install("CLASS_ICON_TCOORDS", { PALADIN = { 0, 0.25, 0.5, 0.75 } })
    Install("Enum", {
        UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 },
        SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3,
            InvalidChatType = 4, NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8,
            GeneralError = 9, NotInGuild = 10, AddOnMessageLockdown = 11, TargetOffline = 12 },
    })
    Install("SlashCmdList", {})

    -- Settings (the framework's canvas categories)
    local categories = {}
    Install("Settings", {
        RegisterCanvasLayoutCategory = function(panel, name)
            local cat = { __panel = panel, name = name }
            categories[#categories + 1] = cat
            local id = #categories
            cat.GetID = function() return id end
            return cat
        end,
        RegisterCanvasLayoutSubcategory = function(_, panel, name)
            local cat = { __panel = panel, name = name }
            categories[#categories + 1] = cat
            local id = #categories
            cat.GetID = function() return id end
            return cat
        end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function(id) M.settingsOpened[#M.settingsOpened + 1] = id end,
    })
    W.categories = categories

    -- Dropdowns and menus
    Install("UIDropDownMenu_Initialize", function(frame, fn, displayMode)
        if not (frame and fn) then return end
        frame.__ddEntries = {}
        frame.__ddMode = displayMode
        W.ddCurrent = frame
        local ok, err = pcall(fn, frame, 1)
        if not ok then M.errors[#M.errors + 1] = "dropdown init: " .. tostring(err) end
        W.ddCurrent = nil
    end)
    Install("UIDropDownMenu_CreateInfo", function() return {} end)
    Install("UIDropDownMenu_AddButton", function(info)
        local f = W.ddCurrent
        if f and f.__ddEntries and info then f.__ddEntries[#f.__ddEntries + 1] = info end
    end)
    Install("UIDropDownMenu_SetWidth", function() end)
    Install("UIDropDownMenu_SetSelectedValue", function(frame, value) if frame then frame.__ddValue = value end end)
    Install("UIDropDownMenu_SetText", function(frame, text) if frame then frame.__ddText = text end end)
    Install("UIDropDownMenu_EnableDropDown", function() end)
    Install("UIDropDownMenu_DisableDropDown", function() end)
    Install("CloseDropDownMenus", function() end)
    Install("ToggleDropDownMenu", function(level, value, frame, anchor)
        M.menu = frame and frame.__ddEntries or {}
        M.menuAnchor = anchor
        M.menuFrame = frame
    end)

    -- Static popups
    Install("StaticPopupDialogs", {})
    Install("StaticPopup_Show", function(which, a1, a2, data)
        local info = _G.StaticPopupDialogs[which]
        assert(info, "StaticPopup_Show: no dialog " .. tostring(which))
        assert(not (info.OnAccept and info.OnButton1), "dialog has both OnAccept and OnButton1")
        assert(not (info.OnCancel and info.OnButton2), "dialog has both OnCancel and OnButton2")
        local box = NewWidget("EditBox", nil, nil)
        box.__text = ""
        if info.maxLetters then box.__maxLetters = info.maxLetters end
        local dialog = NewWidget("Frame", nil, nil)
        dialog.which, dialog.data, dialog.editBox = which, data, box
        box.__parent = dialog
        -- StaticPopup_SetUpPosition (StaticPopup.lua:845-847) runs before the
        -- dialog shows: parent UIParent (GetFullScreenFrame), strata DIALOG,
        -- whatever the frame was before. OnShow comes after, so a strata
        -- change there sticks (Blizzard's own GameDialogDefs.lua:3218-3221).
        dialog.__parent = _G.UIParent
        dialog.__strata = "DIALOG"
        dialog.__shown = true
        local entry = { which = which, a1 = a1, a2 = a2, data = data, dialog = dialog }
        M.popups[#M.popups + 1] = entry
        if info.OnShow then info.OnShow(dialog, data) end
        return dialog
    end)
    Install("StaticPopup_Hide", function() end)

    -- The world map
    W.map = NewWorldMap()
    Install("WorldMapFrame", W.map.frame)
    Install("MapCanvasDataProviderMixin", {
        OnAdded = function(self, map) self.owningMap = map end,
        OnRemoved = function(self) self.owningMap = nil end,
        GetMap = function(self) return self.owningMap end,
        OnMapChanged = function(self) self:RefreshAllData() end,
        RemoveAllData = function() end,
        RefreshAllData = function() end,
        OnShow = function() end, OnHide = function() end,
    })
    Install("MapCanvasPinMixin", {
        OnLoad = function() end, OnAcquired = function() end, OnReleased = function() end,
        OnMouseEnter = function() end, OnMouseLeave = function() end,
        GetMap = function(self) return self.owningMap end,
        UseFrameLevelType = function(self, levelType, index)
            self.__levelType, self.pinFrameLevelType, self.pinFrameLevelIndex = levelType, levelType, index
        end,
        SetScalingLimits = function(self, a, b, c) self.__scaling = { a, b, c } end,
        SetPosition = function(self, x, y)
            self.__x, self.__y = x, y
            self:ApplyFrameLevel()
        end,
        GetPosition = function(self) return self.__x, self.__y end,
        ApplyFrameLevel = function(self)
            local map = self:GetMap()
            local manager = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
            if manager then self:SetFrameLevel(manager:GetValidFrameLevel(self.pinFrameLevelType, self.pinFrameLevelIndex)) end
        end,
        OnCanvasScaleChanged = function() end, OnCanvasPanChanged = function() end,
        OnCanvasSizeChanged = function() end, SetNudgeVector = function() end,
    })
    Install("CreateUnsecuredRegionPoolInstance", function(template, createFunc, resetFunc)
        local pool = NewObjectPool(createFunc, resetFunc or HideAndClearAnchors)
        pool.GetTemplate = function() return template end
        return pool
    end)
    Install("CreateFramePool", function(frameType, parent, template, resetFunc, forbidden, postCreate)
        local proxy = {}
        local private = NewObjectPool(function()
            local frame = MakeFrame(frameType, nil, parent, template)
            if postCreate then postCreate(frame) end
            return frame
        end, function(_, object, new)
            if resetFunc then resetFunc(proxy, object, new) else HideAndClearAnchors(proxy, object) end
        end)
        return setmetatable(proxy, { __index = {
            Acquire = function() return private:Acquire() end,
            Release = function(_, object) return private:Release(object) end,
            ReleaseAll = function() return private:ReleaseAll() end,
            EnumerateActive = function() return private:EnumerateActive() end,
            GetNumActive = function() return private:GetNumActive() end,
        } })
    end)

    -- The minimap
    local minimap = NewWidget("Minimap", "Minimap", uiParent)
    minimap.__w, minimap.__h = 140, 140
    minimap.GetZoom = function() return W.zoom end
    minimap.SetZoom = function(_, z) W.zoom = z; W.zoomNudges = (W.zoomNudges or 0) + 1 end
    minimap.GetZoomLevels = function() return 6 end
    Install("Minimap", minimap)
    W.minimap = minimap

    -- CVars
    Install("GetCVar", function(name) return W.cvars[name] end)
    Install("SetCVar", function(name, value) W.cvars[name] = tostring(value) end)
    Install("GetCVarBool", function(name) return W.cvars[name] == "1" end)
    Install("C_CVar", {
        GetCVar = function(name) return W.cvars[name] end,
        SetCVar = function(name, value) W.cvars[name] = tostring(value) end,
        GetCVarBool = function(name) return W.cvars[name] == "1" end,
    })

    -- Addons
    local function Metadata(addon, key)
        local path = M.ADDONS .. "/" .. tostring(addon) .. "/" .. tostring(addon) .. ".toc"
        local f = io.open(path, "r")
        if not f then return nil end
        for line in f:lines() do
            local k, v = line:match("^## ([^:]+): (.*)$")
            if k == key then f:close() return (v:gsub("\r$", "")) end
        end
        f:close()
        return nil
    end
    local function Loaded(name) return W.loaded[name] and true or false, W.loaded[name] and true or false end
    Install("C_AddOns", { GetAddOnMetadata = Metadata, IsAddOnLoaded = Loaded,
                          GetAddOnEnableState = function() return 2 end })
    Install("GetAddOnMetadata", Metadata)
    Install("IsAddOnLoaded", Loaded)

    -- Timers (run by frame: an After(0) made during a frame runs on the next)
    Install("C_Timer", {
        After = function(delay, fn)
            W.timerSeq = W.timerSeq + 1
            W.timers[#W.timers + 1] = { at = W.now + (delay or 0), fn = fn, seq = W.timerSeq, frame = W.frameNo }
        end,
        NewTicker = function(interval, fn, iterations)
            local ticker = { cancelled = false }
            function ticker:Cancel() self.cancelled = true end
            function ticker:IsCancelled() return self.cancelled end
            local count = 0
            local function Arm()
                W.timerSeq = W.timerSeq + 1
                W.timers[#W.timers + 1] = { at = W.now + interval, seq = W.timerSeq, frame = W.frameNo, fn = function()
                    if ticker.cancelled then return end
                    count = count + 1
                    fn(ticker)
                    if not iterations or count < iterations then Arm() end
                end }
            end
            Arm()
            return ticker
        end,
        NewTimer = function(delay, fn)
            local timer = { cancelled = false }
            function timer:Cancel() self.cancelled = true end
            W.timerSeq = W.timerSeq + 1
            W.timers[#W.timers + 1] = { at = W.now + delay, seq = W.timerSeq, frame = W.frameNo,
                                        fn = function() if not timer.cancelled then fn(timer) end end }
            return timer
        end,
    })

    -- Maps
    Install("C_Map", {
        GetMapInfo = function(id) return MapInfoOf(id) end,
        GetWorldPosFromMapPos = function(map, vec)
            if type(vec) ~= "table" then error("bad position") end
            local inst, n, w = FixtureWorld(map, vec.x, vec.y)
            if not inst then return nil end
            return inst, Vector(n, w)
        end,
        GetMapRectOnMap = function(child, top) return FixtureRect(child, top) end,
        GetMapInfoAtPosition = function(map, x, y) return FixtureInfoAt(map, x, y) end,
        GetMapChildrenInfo = function(id) return FixtureChildren(id) end,
        GetBestMapForUnit = function(unit) return UnitMapOf(unit) end,
        GetPlayerMapPosition = function(map, unit)
            if unit == "player" and W.noPosition then return nil end
            local n, w, _, inst = UnitWorldOf(unit)
            if not n then return nil end
            local x, y = FixtureMapPos(map, inst, n, w)
            if not x then return nil end
            return Vector(x, y)
        end,
    })
    Install("C_DeathInfo", {
        GetCorpseMapPosition = function(map)
            local c = W.corpse
            if not c then return nil end
            local x, y = FixtureMapPos(map, c.inst, c.north, c.west)
            if not x then return nil end
            return Vector(x, y)
        end,
    })
    if W.entrances then
        Install("C_EncounterJournal", {
            GetDungeonEntrancesForMap = function(map) return W.entrances[map] end,
        })
    end

    -- The player
    Install("UnitPosition", function(unit)
        local u = W.units[unit]
        if u and u.noWorld then return nil end
        return UnitWorldOf(unit)
    end)
    Install("GetPlayerFacing", function() return W.facing end)
    Install("GetUnitSpeed", function(unit) if unit == "player" then return W.speed, 7, 7, 4.72 end return 0, 7, 7, 4.72 end)
    Install("UnitOnTaxi", function(unit) return unit == "player" and W.taxi or false end)
    Install("IsIndoors", function() return W.indoors end)
    Install("IsOutdoors", function() return not W.indoors end)
    Install("IsInInstance", function()
        if W.instanceKind then return true, W.instanceKind end
        return false, "none"
    end)
    -- name, instanceType, difficultyID, difficultyName, maxPlayers,
    -- dynamicDifficulty, isDynamic, instanceID (2.5.6's order); outside an
    -- instance the client names the continent and its frame's id
    Install("GetInstanceInfo", function()
        if W.instanceKind then
            return "Instance", W.instanceKind, 1, "Normal", W.instanceKind == "raid" and 25 or 5, 0, false, W.instanceID
        end
        return "World", "none", 0, "", 0, 0, false, W.player.inst or 0
    end)
    Install("UnitIsDead", function(unit) return unit == "player" and W.life == "DEAD" end)
    Install("UnitIsGhost", function(unit) return unit == "player" and W.life == "GHOST" end)
    Install("UnitIsDeadOrGhost", function(unit)
        return unit == "player" and (W.life == "DEAD" or W.life == "GHOST" or W.life == "FEIGN")
    end)
    Install("UnitIsFeignDeath", function(unit) return unit == "player" and W.life == "FEIGN" end)
    Install("UnitFactionGroup", function() return W.faction, W.faction end)
    Install("UnitClass", function() return "Paladin", "PALADIN", 2 end)
    Install("UnitRace", function() return "Blood Elf", "BloodElf", 10 end)
    Install("UnitLevel", function() return 70 end)
    Install("UnitGUID", function(unit)
        if unit == "player" then return "Player-1-00000001" end
        local i = type(unit) == "string" and tonumber(unit:match("^party(%d)$") or unit:match("^raid(%d+)$"))
        local name = i and W.group.members[i]
        if name then return "Player-1-" .. name end
        return nil
    end)
    Install("UnitExists", function(unit) return unit == "player" or W.units[unit] ~= nil end)
    Install("UnitName", function(unit)
        if unit == "player" then return W.name end
        local i = type(unit) == "string" and tonumber(unit:match("^party(%d)$") or unit:match("^raid(%d+)$"))
        if i and W.group.members[i] then return W.group.members[i] end
        return nil
    end)
    Install("UnitAffectingCombat", function() return W.combat end)
    Install("InCombatLockdown", function() return W.combat end)
    Install("GetCurrentRegion", function() return W.region end)
    Install("GetRealmName", function() return W.realm end)
    Install("GetNormalizedRealmName", function() return W.realm end)
    Install("Ambiguate", function(name, context)
        if type(name) ~= "string" then return name end
        local short, realm = name:match("^([^%-]+)%-(.+)$")
        if short and realm == W.realm then return short end
        if context == "short" and short then return short end
        return name
    end)
    Install("IsShiftKeyDown", function() return W.mods.SHIFT end)
    Install("IsControlKeyDown", function() return W.mods.CTRL end)
    Install("IsAltKeyDown", function() return W.mods.ALT end)
    Install("IsModifierKeyDown", function() return W.mods.SHIFT or W.mods.CTRL or W.mods.ALT end)
    Install("GetCursorPosition", function() return 0, 0 end)

    -- Groups and chat
    Install("LE_PARTY_CATEGORY_HOME", 1)
    Install("LE_PARTY_CATEGORY_INSTANCE", 2)
    Install("IsInGroup", function(category)
        local kind = W.group.kind
        if category == 2 then return kind == "instance" end
        return kind ~= nil
    end)
    Install("IsInRaid", function() return W.group.kind == "raid" end)
    Install("GetNumGroupMembers", function() return W.group.kind and (#W.group.members + 1) or 0 end)
    local function Member(name)
        if type(name) ~= "string" then return false end
        for _, m in ipairs(W.group.members) do if m == name then return true end end
        return false
    end
    Install("UnitInParty", function(name) return W.group.kind ~= nil and W.group.kind ~= "raid" and Member(name) end)
    Install("UnitInRaid", function(name) if W.group.kind == "raid" and Member(name) then return 1 end return nil end)
    Install("SendChatMessage", function(text, chatType, lang, target)
        M.chat[#M.chat + 1] = { text = text, chatType = chatType, target = target }
    end)
    Install("C_ChatInfo", {
        SendChatMessage = function(text, chatType, lang, target)
            M.chat[#M.chat + 1] = { text = text, chatType = chatType, target = target, api = "C_ChatInfo" }
        end,
        RegisterAddonMessagePrefix = function(prefix)
            W.prefixes[prefix] = true
            return 0
        end,
        IsAddonMessagePrefixRegistered = function(prefix) return W.prefixes[prefix] and true or false end,
        SendAddonMessage = function(prefix, text, channel, target)
            M.sent[#M.sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
            return W.sendResult
        end,
        InChatMessagingLockdown = function() return W.chatLockdown end,
    })

    if W.minimapShape then Install("GetMinimapShape", function() return W.minimapShape end) end

    -- EventRegistry (CallbackRegistryMixin, undefined events allowed): a
    -- function callback is called as fn(owner, ...); one per owner per event
    local callbacks = {}
    W.eventCallbacks = callbacks
    local ownerSeq = 0
    Install("EventRegistry", {
        RegisterCallback = function(_, event, fn, owner)
            assert(type(event) == "string" and type(fn) == "function", "EventRegistry:RegisterCallback(event, func, owner)")
            if owner == nil then ownerSeq = ownerSeq + 1; owner = ownerSeq end
            callbacks[event] = callbacks[event] or {}
            callbacks[event][owner] = fn
            return owner
        end,
        UnregisterCallback = function(_, event, owner)
            if callbacks[event] then callbacks[event][owner] = nil end
        end,
        TriggerEvent = function(_, event, ...)
            local list = {}
            for owner, fn in pairs(callbacks[event] or {}) do list[#list + 1] = { owner, fn } end
            for _, pair in ipairs(list) do
                local ok, err = pcall(pair[2], pair[1], ...)
                if not ok then M.errors[#M.errors + 1] = "EventRegistry " .. event .. ": " .. tostring(err) end
            end
        end,
    })
    -- SetItemRef: LinkUtil.ProcessLink's AddOn handler hands an addon: link
    -- to EventRegistry "SetItemRef"; the rest are recorded
    Install("SetItemRef", function(link, text, button, frame)
        if type(link) == "string" and link:sub(1, 6) == "addon:" then
            _G.EventRegistry:TriggerEvent("SetItemRef", link, text, button, frame)
            return
        end
        M.itemRefs[#M.itemRefs + 1] = { link = link, text = text, button = button }
    end)
    -- Chat message filters (ChatFrameFilters.lua)
    local filters = {}
    W.chatFilters = filters
    local function AddFilter(event, fn)
        filters[event] = filters[event] or {}
        for _, f in ipairs(filters[event]) do if f == fn then return end end
        table.insert(filters[event], fn)
    end
    local function RemoveFilter(event, fn)
        local list = filters[event]
        if not list then return end
        for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
    end
    Install("ChatFrameUtil", {
        AddMessageEventFilter = AddFilter,
        RemoveMessageEventFilter = RemoveFilter,
        GetMessageEventFilters = function(event) return filters[event] end,
    })
    Install("ChatFrame_AddMessageEventFilter", AddFilter)
    Install("ChatFrame_RemoveMessageEventFilter", RemoveFilter)
end

-- ProcessFilters as 2.5.6 runs it: each filter is called as fn(chatFrame,
-- event, arg1..arg14); a truthy first return discards the line and stops;
-- a non-nil second return replaces all fourteen args (so a filter that
-- returns only false, msg wipes the sender, lineID and GUID, as the client
-- does); an error counts as nil (securecallfunction) and is recorded.
function M.RunChatFilters(event, ...)
    local args = { ... }
    local frame = M.chatFrame or NewWidget("ScrollingMessageFrame", "ChatFrame1")
    M.chatFrame = frame
    for _, fn in ipairs((W.chatFilters or {})[event] or {}) do
        M.filterCalls = M.filterCalls + 1
        local results = { pcall(fn, frame, event, unpack(args, 1, 14)) }
        if not results[1] then
            M.errors[#M.errors + 1] = "chat filter " .. event .. ": " .. tostring(results[2])
        elseif results[2] then
            return true, unpack(args, 1, 14)
        elseif results[3] ~= nil then
            args = {}
            for i = 1, 14 do args[i] = results[i + 2] end
        end
    end
    return false, unpack(args, 1, 14)
end

-- Click the first |H...|h link in a printed line (SetItemRef's path)
function M.ClickLink(text, button, frame)
    local link, shown = tostring(text or ""):match("|H(.-)|h(.-)|h")
    if not link then return false end
    _G.SetItemRef(link, shown, button or "LeftButton", frame)
    return true
end

-- _G: Lua's own globals stay raw; the client's are served through __index,
-- so an addon ASSIGNING any of them is a new write and is recorded
local function InstallG()
    setmetatable(_G, {
        __index = function(_, k) return MOCK and MOCK[k] end,
        __newindex = function(t, k, v)
            M.writes[#M.writes + 1] = { name = tostring(k), phase = W and W.phase or "?" }
            rawset(t, k, v)
        end,
    })
end

local function ResetGlobals()
    setmetatable(_G, nil)
    for k in pairs(_G) do
        if BASELINE[k] == nil then _G[k] = nil end
    end
    for k, v in pairs(BASELINE) do
        if rawget(_G, k) ~= v then rawset(_G, k, v) end
    end
end

-- ===========================================================================
-- Time, frames, events
-- ===========================================================================
function M.Now() return W.now end

function M.Fire(event, ...)
    local list = {}
    for i, frame in ipairs(W.registry[event] or {}) do list[i] = frame end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, frame, event, ...)
            if not ok then M.errors[#M.errors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

function M.Frame(dt)
    dt = dt or (1 / 30)
    W.now = W.now + dt
    W.frameNo = W.frameNo + 1
    local due, keep = {}, {}
    for _, t in ipairs(W.timers) do
        if t.at <= W.now + 1e-9 and t.frame < W.frameNo then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    W.timers = keep
    table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    for _, t in ipairs(due) do
        local ok, err = pcall(t.fn)
        if not ok then M.errors[#M.errors + 1] = "timer: " .. tostring(err) end
    end
    local list = {}
    for i, w in ipairs(W.widgets) do list[i] = w end
    for _, w in ipairs(list) do
        local handler = w.__scripts and w.__scripts.OnUpdate
        if handler and M.Visible(w) then
            local ok, err = pcall(handler, w, dt)
            if not ok then M.errors[#M.errors + 1] = "OnUpdate: " .. tostring(err) end
        end
    end
    if W.map and W.map.CanvasPass then W.map.CanvasPass() end
end

function M.Advance(seconds, step)
    step = step or (1 / 30)
    local target = W.now + seconds - 1e-9
    while W.now < target do M.Frame(step) end
end

-- ===========================================================================
-- The player and the client, driven by the harness
-- ===========================================================================
function M.SetPlayerWorld(inst, north, west, map)
    W.player.inst, W.player.north, W.player.west = inst, north, west
    if map ~= nil then W.player.map = map end
end

function M.SetPlayer(map, x, y)
    local inst, n, w = FixtureWorld(map, x, y)
    assert(inst, "SetPlayer: no world position for map " .. tostring(map))
    M.SetPlayerWorld(inst, n, w, map)
end

function M.SetFacing(f) W.facing = f end
function M.SetSpeed(s) W.speed = s end
function M.SetTaxi(b) W.taxi = b and true or false end
function M.SetIndoors(b) W.indoors = b and true or false end
function M.SetNoPosition(b) W.noPosition = b and true or false end
function M.SetLife(state) W.life = state end
function M.SetInstance(kind, id)
    W.instanceKind = kind
    W.instanceID = kind and id or nil
end
function M.SetNoMap(b) W.noMap = b and true or nil end
function M.SetZoom(z) W.zoom = z end

function M.SetCombat(b)
    b = b and true or false
    if W.combat == b then return end
    W.combat = b
    M.Fire(b and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

function M.SetModifier(key, down)
    W.mods[key] = down and true or false
    M.Fire("MODIFIER_STATE_CHANGED", "L" .. key, down and 1 or 0)
end

function M.SetGroup(kind, members)
    W.group.kind = kind
    W.group.members = members or {}
end

function M.SetUnit(unit, map, x, y)
    if not map then W.units[unit] = nil return end
    local inst, n, w = FixtureWorld(map, x, y)
    W.units[unit] = { map = map, inst = inst, north = n, west = w }
end

-- UnitPosition answers nil for the member while the map position still
-- does (unverified in game that the client ever answers so: review-r2)
function M.SetUnitNoWorld(unit, b)
    local u = W.units[unit]
    if u then u.noWorld = b and true or nil end
end

function M.SetCorpse(map, x, y)
    if not map then W.corpse = nil return end
    local inst, n, w = FixtureWorld(map, x, y)
    W.corpse = { map = map, inst = inst, north = n, west = w }
end

function M.SetEntrances(zoneMap, list)
    W.entrances = W.entrances or {}
    W.entrances[zoneMap] = list
    MOCK.C_EncounterJournal = MOCK.C_EncounterJournal or {
        GetDungeonEntrancesForMap = function(map) return W.entrances[map] end,
    }
end

function M.SetMinimapShape(shape)
    W.minimapShape = shape
    if shape then MOCK.GetMinimapShape = function() return W.minimapShape end else MOCK.GetMinimapShape = nil end
end

function M.Receive(prefix, text, channel, sender)
    M.Fire("CHAT_MSG_ADDON", prefix, text, channel, sender)
end

function M.ShowMap(mapID)
    if mapID then W.map.mapID = mapID end
    W.map.frame:Show()
end
function M.HideMap() W.map.frame:Hide() end
function M.SetMapMaximized(on)
    W.map.maximized = on and true or false
    W.map.frame:SynchronizeDisplayState()
end

-- Frame strata in the client's drawing order, and whether a draws over b
M.STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
             FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
function M.StrataOver(a, b)
    return (M.STRATA[a] or 0) > (M.STRATA[b] or 0)
end
function M.SetMapID(mapID) W.map.frame:SetMapID(mapID) end
function M.SetMapCursor(nx, ny) W.map.cursor[1], W.map.cursor[2] = nx, ny end

-- A disabled Button: the client delivers no OnClick, and no OnEnter or
-- OnLeave unless SetMotionScriptsWhileDisabled(true) (2.5.6: Blizzard sets
-- it wherever a greyed button explains itself, GuildRegistrarFrame.xml:130,
-- UIButtonMixin:SetDisabledTooltip). The mock used to deliver both, which
-- hid a GoButton whose red reason no player could ever see (review:
-- consistency).
local function Disabled(frame)
    local kind = frame.__kind
    return (kind == "Button" or kind == "CheckButton") and frame.__enabled == false
end

function M.Click(frame, button)
    if not (frame and M.Visible(frame) and frame.__mouse) then return false end
    if Disabled(frame) then return false end
    local handler = frame.__scripts.OnClick
    if handler then handler(frame, button or "LeftButton", false) end
    return true
end

-- OnEnter; false when the client would not run it (a disabled Button
-- without motion scripts)
function M.Hover(frame)
    if frame and Disabled(frame) and not frame.__motionWhileDisabled then return false end
    local handler = frame and frame.__scripts.OnEnter
    if handler then handler(frame) end
    return true
end

function M.ClickMenu(text)
    for _, entry in ipairs(M.menu or {}) do
        if entry.text == text and entry.func and not entry.disabled then
            entry.func(entry)
            return true
        end
    end
    return false
end

function M.MenuTexts()
    local out = {}
    for _, entry in ipairs(M.menu or {}) do out[#out + 1] = tostring(entry.text) end
    return out
end

function M.ClickPopup(which, index)
    local entry
    for i = #M.popups, 1, -1 do
        if M.popups[i].which == which then entry = M.popups[i] break end
    end
    if not entry then return false end
    local info = _G.StaticPopupDialogs[which]
    local dialog, data = entry.dialog, entry.data
    local fn
    if info.selectCallbackByIndex then
        if index == 1 then fn = info.OnAccept or info.OnButton1
        elseif index == 2 then fn = info.OnCancel or info.OnButton2
        elseif index == 3 then fn = info.OnButton3 end
    else
        if index == 1 then fn = info.OnAccept or info.OnButton1
        elseif index == 2 then fn = info.OnCancel
        elseif index == 3 then fn = info.OnAlt end
    end
    if fn then fn(dialog, data, "clicked") end
    return true
end

-- ===========================================================================
-- Boot
-- ===========================================================================
local function NewWorld(opts)
    return {
        now = 1000, epoch = 1759570000, frameNo = 0, timers = {}, timerSeq = 0,
        registry = {}, widgets = {}, phase = "boot",
        player = { map = nil }, units = {}, facing = 0, speed = 0, taxi = false, indoors = false,
        noPosition = false, life = "ALIVE", instanceKind = nil, combat = false, mods = {},
        group = { kind = nil, members = {} }, faction = opts.faction or "Horde", name = "Cptnbubbles",
        realm = "Dreamscythe", region = 1, zoom = 0, cvars = { rotateMinimap = "0", minimapZoom = "0", minimapInsideZoom = "0" },
        loaded = opts.loaded or {}, prefixes = {}, sendResult = 0, chatLockdown = false,
        corpse = nil, entrances = opts.entrances, minimapShape = opts.minimapShape, restored = {},
    }
end

local function LoadFile(path, label)
    local chunk, err = loadfile(path)
    if not chunk then
        M.loadErrors[#M.loadErrors + 1] = label .. ": " .. tostring(err)
        return false
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        M.loadErrors[#M.loadErrors + 1] = label .. ": " .. tostring(runErr)
        return false
    end
    return true
end

local OVERRIDES = {
    CommanderOrders = "ORDERS_RUNTIME", CommanderOrdersDB = "ORDERS_DB", CommanderOrdersData = "ORDERS_DATA",
    CommanderOrdersStore = "ORDERS_STORE", CommanderOrdersGeo = "ORDERS_GEO",
    CommanderOrdersPins = "ORDERS_PINS", CommanderOrdersUI = "ORDERS_UI",
}

-- The Orders files in TOC order, the ones that exist
local function TocFiles()
    local out = {}
    local f = io.open(M.ORDERS .. "/Commander_Orders.toc", "r")
    if not f then return out end
    for line in f:lines() do
        line = line:gsub("\r$", "")
        if line:match("%.lua$") and not line:match("^#") then out[#out + 1] = line:gsub("%.lua$", "") end
    end
    f:close()
    return out
end
M.TocFiles = TocFiles

-- Another addon's TOC .lua files, in order (3.1, opts.addons)
function M.AddonTocFiles(name)
    local out = {}
    local f = io.open(M.ADDONS .. "/" .. tostring(name) .. "/" .. tostring(name) .. ".toc", "r")
    if not f then return out end
    for line in f:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line:match("%.lua$") and not line:match("^#") then out[#out + 1] = (line:gsub("\\", "/")) end
    end
    f:close()
    return out
end

local function Exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = DeepCopy(x) end
    return out
end

function M.Boot(opts)
    opts = opts or {}
    ResetGlobals()
    M.ClearLog()
    for i = #M.writes, 1, -1 do M.writes[i] = nil end
    for i = #M.loadErrors, 1, -1 do M.loadErrors[i] = nil end
    for i = #M.tooltip, 1, -1 do M.tooltip[i] = nil end
    M.menu = {}
    W = NewWorld(opts)
    M.W = W
    InstallClient()
    rawset(_G, "print", Capture)
    InstallG()
    local start = opts.player or { 1429, 0.42, 0.655 }
    M.SetPlayer(start[1], start[2], start[3])
    if opts.before then opts.before(M, W) end

    W.phase = "events"
    LoadFile(M.ADDONS .. "/Commander_Events/CommanderSettingsUI.lua", "CommanderSettingsUI.lua")
    -- 3.1: Commander.UI.GoButton, in its TOC slot (ORDERS_GOBUTTON=<copy>
    -- loads a mutated copy instead, for a mutation sweep)
    local goButton = os.getenv("ORDERS_GOBUTTON") or (M.ADDONS .. "/Commander_Events/CommanderGoButton.lua")
    if Exists(goButton) then
        LoadFile(goButton, "CommanderGoButton.lua")
    end
    LoadFile(M.ADDONS .. "/Commander_Events/CommanderEvents.lua", "CommanderEvents.lua")
    W.phase = "orders"
    local files = opts.files or TocFiles()
    local skip = opts.skipFiles or {}
    for _, name in ipairs(files) do
        local override = OVERRIDES[name] and os.getenv(OVERRIDES[name])
        local path = override or (M.ORDERS .. "/" .. name .. ".lua")
        if not skip[name] and Exists(path) then LoadFile(path, name .. ".lua") end
    end
    -- 3.1: consumer addons on top (opts.addons), in the order given
    local consumers = {}
    for _, a in ipairs(opts.addons or {}) do
        local name = type(a) == "table" and a.name or a
        local list = type(a) == "table" and a.files or M.AddonTocFiles(name)
        W.phase = "addon:" .. tostring(name)
        for _, file in ipairs(list or {}) do
            local path = M.ADDONS .. "/" .. name .. "/" .. file
            if Exists(path) then LoadFile(path, name .. "/" .. file) end
        end
        consumers[#consumers + 1] = name
        W.loaded[name] = true
    end
    W.phase = "orders"
    if opts.afterFiles then opts.afterFiles(M, W) end
    -- The client assigns the saved variables after the files ran, before
    -- ADDON_LOADED
    W.phase = "saved"
    for name, value in pairs(opts.saved or {}) do rawset(_G, name, DeepCopy(value)) end
    W.phase = "runtime"
    M.Fire("ADDON_LOADED", "Commander_Events")
    M.Fire("ADDON_LOADED", "Commander_Orders")
    for _, name in ipairs(consumers) do M.Fire("ADDON_LOADED", name) end
    if opts.combat then W.combat = true end
    M.Fire("PLAYER_LOGIN")
    M.Fire("PLAYER_ENTERING_WORLD", true, false)
    M.Frame()
    return W
end

-- The saved variables as the client would write and read them back
function M.SaveVariables(names)
    local out = {}
    for _, name in ipairs(names or { "CommanderOrdersDB", "CommanderOrdersChar", "CommanderUIDB" }) do
        local v = rawget(_G, name)
        if type(v) == "table" then out[name] = M.Deserialize(M.Serialize(v)) end
    end
    return out
end

function M.Reload(opts)
    opts = opts or {}
    M.Fire("PLAYER_LOGOUT")
    local saved = M.SaveVariables()
    local restored = {}
    for name, value in pairs(opts.extraSaved or {}) do restored[name] = M.Deserialize(M.Serialize(value)) end
    local merged = {}
    for k, v in pairs(opts) do merged[k] = v end
    merged.saved = saved
    local player = W and W.player
    if not merged.player and player and player.map then
        local x, y = FixtureMapPos(player.map, player.inst, player.north, player.west)
        if x then merged.player = { player.map, x, y } end
    end
    -- The world outside the addon carries over a reload: life, corpse,
    -- group, facing, instance, taxi
    local carry = {}
    for _, key in ipairs({ "life", "corpse", "facing", "instanceKind", "instanceID", "noMap", "noPosition", "taxi", "speed",
            "indoors", "loaded", "entrances", "minimapShape", "region" }) do
        carry[key] = W and W[key]
    end
    local group = W and W.group
    local units = W and W.units
    if not merged.faction then merged.faction = W and W.faction end
    if merged.loaded then carry.loaded = merged.loaded end
    local userBefore = merged.before
    merged.before = function(m, w)
        for key, value in pairs(carry) do w[key] = value end
        if group then w.group = group end
        if units then w.units = units end
        if w.minimapShape then m.SetMinimapShape(w.minimapShape) end
        if w.entrances then
            MOCK.C_EncounterJournal = { GetDungeonEntrancesForMap = function(map) return w.entrances[map] end }
        end
        if userBefore then userBefore(m, w) end
    end
    local world = M.Boot(merged)
    world.restored = restored
    return world
end

-- New globals written while Orders loaded or ran (Events' own excluded)
function M.OrdersWrites()
    local out, seen = {}, {}
    for _, w in ipairs(M.writes) do
        if w.phase ~= "events" and w.phase ~= "saved" and w.phase ~= "boot" and not seen[w.name] then
            seen[w.name] = true
            out[#out + 1] = w.name
        end
    end
    table.sort(out)
    return out
end

return M

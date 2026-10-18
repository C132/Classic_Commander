-- Commander Quest Log: the catalogue.
--
-- A tab of the quest log window that lists quests the player is NOT carrying
-- -- every quest of a zone, every quest of a faction -- read from Questie
-- through the adapter and judged by the completion engine. The Zones tab was
-- the first; the Reputations tab is the second, and the two are the same
-- machine pointed at a different set of quest ids. So the machine lives here,
-- as a factory: Q.NewCatalogue(spec) builds one tab's worth of widgets and
-- state, and the spec says where its quests come from and how its card, its
-- overview and its rows differ.
--
-- Why instances and not one set of widgets with a mode switch: that is the
-- anti-pattern D30 turned down for the Log and the Zones tab, and it would be
-- the same mistake here -- every code path a mode switch, every fix a chance
-- to break the other tab. An instance owns its toolbar set, its card, its
-- navigator rows, its briefing pools, its action buttons and its own two
-- named dropdowns, all built on first use, all hidden whenever another tab
-- is up. Only the code is shared, so a fix to the row pool, the ink on the
-- paper, the paging of the menu or the reveal of a quest asked for by name
-- lands once for every tab. Every instance borrows the window's ink, quads
-- and panes through Q._kit, so no tab can drift from another on colour (D16).
--
-- The traps every instance inherits (each one paid for in the Zones tab):
--
--   * The engine's Group (Q.Completion.Group) writes entry.header onto the
--     view's OWN entries, and BuildList matches rows to their headings
--     through it -- so the last Group call on a view decides every heading.
--     The navigator groups immediately before BuildList and nothing regroups
--     between them; an overview's "next up" list uses the engine's NextUp,
--     which reads the Guide's order without touching a header. A spec's own
--     Group must keep the same rule.
--   * Group titles are fold keys, kept in <prefix>Collapsed, never in the
--     Log's Collapsed: different lists sharing one widget, and a log heading
--     and a chain could share a name.
--   * Dim by `counted`, not by bucket. An exclusive choice's other members
--     keep bucket AVAILABLE or LOCKED and simply do not count.
--   * The LEVEL and NAME groupings are flat lists in the engine's own
--     ascending order. They go through BuildList with sort "LOG" to keep it.
--   * One search box, one search per tab. The box belongs to the window; each
--     instance keeps its own text, and the window swaps it on a tab change.
--   * The global quest-log selection is the Log's business (D2). An instance
--     touches it only through Q.ReadDetail, for a quest that is in the log,
--     which puts it back.
--   * A selected quest that a filter, a search or a fold takes off the list
--     drops the briefing to the overview (D6) -- unless something asked for
--     it by name (PrepareOpen), in which case the search is cleared, the
--     filter opened and its group unfolded.
--   * No shape glyphs in anything drawn (D11): markers are quads, states are
--     words. Every colour on the sheet goes through Paper() (D16) -- Line()
--     does it for every caller -- and pooled blocks get their font and colour
--     re-applied on every pass (D15).
--
-- ===========================================================================
-- THE SPEC (what a tab hands Q.NewCatalogue)
-- ===========================================================================
--
-- Every hook is optional unless marked REQUIRED, and every hook is called
-- with `cat` first: the instance's context table (below), never the public
-- instance, so a hook can reach the drawing primitives without them being
-- published. Words a spec supplies follow the module's voice: plain English,
-- British spelling, no glyphs.
--
--   id            REQUIRED. The tab's registry id and its ViewMode value
--                 ("ZONE", "REP").
--   label         The tab's word ("Zones"), also used in the "Questie is not
--                 loaded" sentence.
--   title         What the card and the briefing say with nothing resolved
--                 (default: label).
--   order, width, tooltip
--                 The tab button: its place in the strip (the Log is 10,
--                 the Zones tab 20), its width in pixels (58 fits "Zones"),
--                 its tooltip.
--   searchTip     The shared search box's tooltip while this tab is up.
--   register      false keeps the instance out of the window's register
--                 (Q.RegisterTab); by default it registers itself, as
--                 Z.tab, and the window builds its button, switches to it
--                 (ViewMode = id), hides it, routes the search box to it and
--                 opens it from outside (Q.OpenToTab(id, key, questId)).
--   prefix        DB key stem: <prefix>Filter, <prefix>Group,
--                 <prefix>Collapsed, <prefix>Follow, <prefix>Picked. Also
--                 the stem of the two named dropdowns:
--                 CommanderQuestLog<prefix>GroupDrop and
--                 CommanderQuestLog<prefix>Menu (UIDropDownMenuTemplate
--                 names its children after its parent, so they need names).
--   keys          Overrides for any of the five keys above ({ filter = ...,
--                 group = ..., collapsed = ..., follow = ..., picked = ... }).
--   names         Overrides for the two frame names ({ groupDrop, menu }).
--   showKey       The setting that switches the tab off ("ShowZoneTab").
--   offMessage    Printed when something asks to open a switched-off tab.
--   stateAliases  Extra READ-ONLY names for state fields (the Zones tab keeps
--                 S.areaId / S.areaName as names for S.key / S.keyName).
--   countTip      The tooltip of the toolbar's "n shown" readout.
--
--   Source -- which quests, and where they live:
--   Resolve(cat) -> key, name                    REQUIRED. What to show now:
--                 following or pinned, read from <prefix>Follow/Picked.
--                 nil key: nothing to show (EmptyMessage says why).
--   View(cat, key) -> view, err                  REQUIRED. The engine view.
--   KeyName(cat, key, current) -> name           The name when View fails.
--   PlayerPos(cat, key) -> pos | nil             For the Guide's nearest-first.
--   StarterArea(cat, entry) -> areaId | nil      Which zone's giver a
--                 waypoint or tooltip prefers (BestStarter's second argument).
--   MapArea(cat, entry) -> areaId | nil          The zone Show on Map opens.
--   DetailArea(cat) -> viewKey | nil             The view key handed to
--                 adapter.QuestDetail (it reads its cached fact from there).
--   QuestDetail(cat, entry) -> detail            Replaces that read outright.
--
--   Grouping and filtering:
--   groups        List of group modes for the dropdown (default the
--                 engine's, Q.Completion.GROUPS); groupLabels: mode -> word.
--   Group(cat, view, mode, opts) -> list | nil   A spec's own modes. Return
--                 nil to hand the mode to the engine's Q.Completion.Group.
--                 The list is the engine's shape: header rows { isHeader = true, title,
--                 group, countMode = "COUNT" | "RATIO", quests, complete }
--                 each followed by its entries, every entry's .header set to
--                 its heading's title (cat.Emit builds exactly that), or a
--                 flat list with every entry's .header = nil.
--   filterOrder, filterSpecs
--                 The filter buttons (default the engine's FILTER_ORDER /
--                 FILTERS; specs are { label, tooltip }). Five fit the
--                 toolbar.
--   PassesFilter(cat, entry, key) -> bool | nil  nil hands it to the engine.
--
--   Painting:
--   PaintCard(cat, card)          The card's name, totals, bar and note. The
--                 card is card.name, card.totals, card.barBg, card.bar
--                 (quads) and card.note; the wash and rule are done already.
--   CardTooltip(cat, owner)       The whole card tooltip (SetOwner included).
--   MenuInit(cat, level, menuList) The card's MENU dropdown (cat.Follow,
--                 cat.Pick and cat.AddCategoryPages are there for it).
--   PaintOverview(cat, view)      The briefing with nothing selected.
--   OverviewSections(cat, view)   Drawn after the overview.
--   Facts(cat, entry, view) -> list   The quest briefing's facts line
--                 (default cat.DefaultFacts: level, requires, view name, tag,
--                 where it starts, "not counted").
--   Reputation(cat, entry, detail)    Replaces the quest briefing's
--                 REPUTATION section.
--   BriefingSections(cat, entry, view, detail)  Drawn after the quest
--                 briefing's own sections.
--   reputationFirst  true, or a function(cat) -> bool: the REPUTATION
--                 section and BriefingSections come straight under the
--                 quest's reason line, before WHERE (default: last).
--   chainLabel    A string, or a function(cat) -> string | nil: the CHAIN
--                 heading's words before "· N of M done" (default "CHAIN").
--   StateWord(cat, entry) -> word, toneKey | nil     nil: the engine's.
--   Reason(cat, entry) -> sentence | nil              nil: the engine's.
--   RowRight(cat, entry) -> text | nil, colour, dim
--                 A right-aligned badge left of the state word ("+250").
--                 colour is a tone key ("good" "open" "log" "warn" "bad"
--                 "faint") or an {r, g, b} picked against the dark; it goes
--                 through Paper(). dim = true inks the title faint.
--   RowTooltip(cat, entry)        Extra GameTooltip lines on a quest row,
--                 after "Starts:" and before the hint.
--   EmptyMessage(cat) -> text     The navigator's sentence when Questie is
--                 READY but nothing is listed (no key, no quests, unreadable,
--                 nothing matches).
--
--   Actions (the bar under the briefing):
--   actions       A list. A string names a stock action -- "WAYPOINT",
--                 "MAP", "LOG", "IGNORE" -- and a table is either
--                 { stock = "MAP", label = ..., tooltip = ... } (a stock
--                 action with words of its own) or a custom one:
--                 { field, label, width, tooltip, onClick(cat), right,
--                   Update(cat, button, entry) }.
--                 Buttons are W[field]; `right = true` packs it at the right
--                 edge (Ignore, where the Log keeps Abandon). Tooltips may be
--                 functions of cat. Default: the four stock actions.
--   UpdateActions(cat)            Runs after the stock enable pass.
--
--   Opening and following:
--   followEvents  Client events that move the followed key
--                 ({ "ZONE_CHANGED_NEW_AREA" }); one refresh is queued when
--                 the tab is up and following.
--
-- THE CONTEXT (`cat`, every hook's first argument):
--   cat.spec, cat.instance (the public table), cat.S (state), cat.W
--   (widgets), cat.P (the briefing's cursor), cat.keys (the five DB keys)
--   cat.Line(text, template, colour, indent) -> block, height
--   cat.Heading(text), cat.Bar(indent, height, fraction, gap),
--   cat.Rule(spacingAbove), cat.Mark(indent, toneKey), cat.Band(top, height)
--   cat.Follow(), cat.Pick(_, key), cat.OpenMenu(anchor),
--   cat.AddCategoryPages(category)   ({ key, text, zones|items = {{name}} })
--   cat.SendWaypoint(entry), cat.ShowOnMap(), cat.OpenInLog(),
--   cat.ToggleIgnore(), cat.LogEntryFor(entry), cat.WaypointTarget(entry),
--   cat.DetailFor(entry), cat.StateWord(entry), cat.Reason(entry),
--   cat.DefaultFacts(entry, view), cat.Emit(list, key, title, members)
--   ...plus every shared helper in Q.Catalogue (ToneMarkup, InkT, ToneT,
--   GiverName, GiverPhrase, BreakdownText, UncountedText, SEP, DASH,
--   InSentence, Possessive, RepTag, ...).
--
-- The state (S) a hook may read: key, keyName, view, err, rows, shown,
-- selectedId, selectedEntry, search, char, playerPos, logByKey, logDetail,
-- state/reason (the adapter's word on Questie), menu (scratch for MenuInit).
--
-- THE INSTANCE (what Q.NewCatalogue returns; Q.Zones is one):
--   IsActive, NavTopInset, Refresh(entries), HideAll, RestyleToolbar,
--   UpdateActions, SetSearch, SearchText, EscapeSearch, Selected,
--   Select(questId), PrepareOpen(key, questId), UpdateTabs / EnsureTabs (the
--   window's, kept for old callers), tab (its register entry), and the
--   harness's _Widgets, _State, _Context.
--
-- Budgets (Lua 5.1, which luajit enforces): C.New closes over about 40 of
-- the 60 upvalues one function may have -- a new shared helper is better
-- reached through C (cat inherits it) than as one more file-level local --
-- and its body holds about 75 of 200 locals.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local C = {}
Q.Catalogue = C

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local CARD_H = 46            -- the card over the navigator column
local CARD_GAP = 4
local CARD_BAR_H = 4
local FILTER_W = 42          -- five of these end where the Log's four do
local STATE_W = 46           -- the state word's column (C.StateWord is <= 6 characters)
local BADGE_GAP = 4          -- between a row's badge and its state word
local BADGE_MAX_W = 64       -- a badge never takes more of the title than this
local TOTAL_BAR_H = 6
local CHAIN_BAR_H = 3
local MARK_SIZE = 6
local NEXT_UP_COUNT = 6
local GIVERS_SHOWN = 3
local MENU_PAGE = 20         -- menu rows per level-2 list (the Classic dropdown never scrolls)
local SEP = "  \194\183  "                -- the middle dot the Log's facts line uses
local DASH = " \226\128\148 "             -- em dash
local ELLIPSIS = "\226\128\166"

local DEFAULT_FILTER_ORDER = { "ALL", "OPEN", "LOCKED", "DONE", "MISSED" }
local DEFAULT_ACTIONS = { "WAYPOINT", "MAP", "LOG", "IGNORE" }

-- Status tones, picked against a dark UI like every literal in this window
-- and put through Paper() wherever they are drawn on the sheet (D16). The
-- engine names a tone (good / open / warn / bad / faint); this is the only
-- place one becomes a colour.
local TONES = {
    good = { 0.35, 0.82, 0.35 },
    open = { 0.95, 0.80, 0.30 },
    log  = { 0.45, 0.72, 1.00 },
    warn = { 1.00, 0.56, 0.25 },
    bad  = { 0.90, 0.36, 0.30 },
}
local STATUS_TONE = { DONE = "good", LOG = "log", AVAILABLE = "open", LOCKED = "warn", MISSED = "bad" }
local OBJECTIVE_DONE = { 0.35, 0.8, 0.35 }
local OBJECTIVE_OPEN = { 0.92, 0.86, 0.6 }
local TAG_WORDS = { DUNGEON = "Dungeon", RAID = "Raid", PVP = "PvP", ELITE = "Elite" }

C.CARD_H, C.CARD_GAP, C.CARD_BAR_H = CARD_H, CARD_GAP, CARD_BAR_H
C.TOTAL_BAR_H, C.CHAIN_BAR_H, C.MARK_SIZE = TOTAL_BAR_H, CHAIN_BAR_H, MARK_SIZE
C.NEXT_UP_COUNT, C.GIVERS_SHOWN, C.MENU_PAGE = NEXT_UP_COUNT, GIVERS_SHOWN, MENU_PAGE
C.SEP, C.DASH, C.ELLIPSIS = SEP, DASH, ELLIPSIS
C.TONES, C.STATUS_TONE, C.TAG_WORDS = TONES, STATUS_TONE, TAG_WORDS

-- ---------------------------------------------------------------------------
-- Reaching the rest of the module
-- ---------------------------------------------------------------------------

-- The window's kit. UI.lua loads first and publishes it; read late anyway,
-- so a load order nobody meant degrades to an absent tab rather than an error.
local function Kit()
    return Q._kit
end

local function Engine()
    local engine = Q.Completion
    if type(engine) == "table" and type(engine.Group) == "function" then return engine end
    return nil
end

local function Adapter()
    local adapter = Q.Questie
    if type(adapter) == "table" then return adapter end
    return nil
end

local function DB()
    return CommanderQuestLogDB or {}
end

local function Tip(widget, title, text, anchor)
    if Commander and Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(widget, title, text, anchor)
    end
end

local function HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

-- "ABSENT" | "LOADING" | "READY" | "BROKEN", reason. A missing engine is
-- BROKEN: the adapter would answer READY and every view would fail.
local function AdapterState()
    local adapter = Adapter()
    if not (adapter and adapter.State) then return "ABSENT", nil end
    local ok, state, reason = pcall(adapter.State)
    if not ok then return "BROKEN", tostring(state) end
    if state == "READY" and not Engine() then return "BROKEN", "the completion engine is not loaded" end
    return state or "ABSENT", reason
end

C.Kit, C.Engine, C.Adapter, C.DB, C.Tip, C.HideTooltip, C.AdapterState =
    Kit, Engine, Adapter, DB, Tip, HideTooltip, AdapterState

-- ---------------------------------------------------------------------------
-- Colour
-- ---------------------------------------------------------------------------

local function ToneRGB(key)
    local tone = TONES[key]
    if tone then return tone[1], tone[2], tone[3] end
    return Kit().Ink("faint")
end

-- A tone as a colour table, for Line(); Line puts it through Paper()
local function ToneT(key)
    return { ToneRGB(key) }
end

local function InkT(shade)
    return { Kit().Ink(shade) }
end

-- Inline markup for a word inside a longer line, already put on the paper
local function ToneMarkup(key, text)
    local r, g, b = Kit().Paper(ToneRGB(key))
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5), text)
end

-- The tone a quest's strip, sentence and chain mark take. Uncounted quests
-- (other choices, other faction, dailies, the ignored) are faint whatever
-- their bucket, except the missed, which are the one uncounted thing worth
-- seeing at a glance.
local function StatusToneKey(entry)
    if entry.base == "LOG" then
        if entry.ready then return "good" end
        if entry.failed then return "bad" end
    end
    if not entry.counted and entry.status ~= "MISSED" then return "faint" end
    return STATUS_TONE[entry.status] or "faint"
end

-- A colour a spec hands back: a tone key or an {r, g, b} table (picked
-- against the dark, like every literal here). nil is the secondary ink.
local function ColourRGB(colour)
    if type(colour) == "string" then return ToneRGB(colour) end
    if type(colour) == "table" then return colour[1] or 1, colour[2] or 1, colour[3] or 1 end
    return Kit().Ink("secondary")
end

C.ToneRGB, C.ToneT, C.InkT, C.ToneMarkup, C.StatusToneKey, C.ColourRGB =
    ToneRGB, ToneT, InkT, ToneMarkup, StatusToneKey, ColourRGB

-- ---------------------------------------------------------------------------
-- Givers
-- ---------------------------------------------------------------------------

local function ZoneNameOf(record)
    local adapter = Adapter()
    local areaId = record and (record.zone or record.areaId)
    if areaId and adapter and adapter.ZoneName then return adapter.ZoneName(areaId) end
    return nil
end

-- "Force Commander Danath — Hellfire Peninsula 56.6, 66.4"
local function GiverPhrase(record)
    if record.kind == "item" then return (record.name or "An item") .. " (an item)" end
    local text = record.name or "Someone Questie has no name for"
    local zone = record.zoneName or ZoneNameOf(record)
    if zone then text = text .. DASH .. zone end
    if record.x and record.y then text = text .. string.format(" %.1f, %.1f", record.x, record.y) end
    return text
end

-- The first spawn of each distinct giver, up to cap. A patrol with eight
-- spawns is one quest giver, not eight lines.
local function DistinctGivers(records, cap)
    local out, seen = {}, {}
    for _, record in ipairs(records or {}) do
        local key = tostring(record.kind) .. ":" .. tostring(record.id or record.name)
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = record
            if #out >= cap then break end
        end
    end
    return out
end

-- The first giver record with coordinates. The adapter orders spawns in the
-- viewed zone first, so this is the one standing here when there is one.
local function FirstPlaced(records)
    for _, record in ipairs(records or {}) do
        if record.x and record.y then return record end
    end
    return nil
end

-- The name to put after a quest in a short list: who hands it out, or for a
-- quest in the log who takes it back
local function GiverName(entry)
    local list = (entry.base == "LOG") and entry.finishers or entry.starters
    local giver
    for _, record in ipairs(list or {}) do
        if record.name then giver = record break end
    end
    if not giver then return nil end
    if entry.base ~= "LOG" and entry.startsHere == false and entry.startZoneName then
        return giver.name .. " in " .. entry.startZoneName
    end
    return giver.name
end

C.ZoneNameOf, C.GiverPhrase, C.DistinctGivers, C.FirstPlaced, C.GiverName =
    ZoneNameOf, GiverPhrase, DistinctGivers, FirstPlaced, GiverName

-- ---------------------------------------------------------------------------
-- The ignore list (one per character, shared by every tab: a quest you will
-- never do is one you will never do, whichever list it showed up on)
-- ---------------------------------------------------------------------------

local function IsIgnored(questId)
    local charDB = CommanderQuestLogChar
    local ignored = type(charDB) == "table" and charDB.Ignored or nil
    return (type(ignored) == "table" and ignored[questId]) and true or false
end

-- The per-character ignore set, made whole first (the DB file owns the shape)
local function IgnoredSet()
    if Q.EnsureCharDB then return Q.EnsureCharDB().Ignored end
    if type(CommanderQuestLogChar) ~= "table" then CommanderQuestLogChar = {} end
    if type(CommanderQuestLogChar.Ignored) ~= "table" then CommanderQuestLogChar.Ignored = {} end
    return CommanderQuestLogChar.Ignored
end

C.IsIgnored, C.IgnoredSet = IsIgnored, IgnoredSet

-- ---------------------------------------------------------------------------
-- Ink after a hover
--
-- A hover swaps a label to the highlight font and back to the normal one,
-- and each swap puts the font's own colour back over our ink (D14's lesson),
-- leaving gold on the paper until the next refresh. So the ink goes back on
-- after a hover -- a frame later, so it lands after the client's own swap
-- whichever order the two run in.
-- ---------------------------------------------------------------------------

local function ReinkAfterHover(button, restyle)
    button:HookScript("OnLeave", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, restyle) else restyle() end
    end)
    -- ...and on the paper the hovered label is ink too, not the highlight
    -- font's white over the pale strip (UI.lua's InkOnHover)
    local kit = Kit()
    if kit and kit.InkOnHover then kit.InkOnHover(button) end
end

C.ReinkAfterHover = ReinkAfterHover

-- ---------------------------------------------------------------------------
-- Menu paging
--
-- The Classic dropdown never scrolls and is not clamped to the screen: a
-- level-2 list grows by 16 per row and, near the bottom of the screen, flips
-- to grow upward instead -- off the top. At the window's default spot on a
-- 768-unit screen 24 rows fit and the Dungeons list holds 34, so a long
-- category is cut into pages of at most MENU_PAGE rows, each a row of its
-- own named by its initials ("Dungeons  A-O", "Dungeons  R-Z"). The cuts
-- fall where the initial changes, so no two pages claim the same letter;
-- where a letter outruns a page the rows are numbered as well ("(1/2)").
-- ---------------------------------------------------------------------------

-- A category row: opens its list a level down. keepShownOnClick, because a
-- click (rather than a hover) on a row with no func otherwise hides the
-- whole menu and picks nothing (UIDropDownMenuButton_OnClick).
local function AddCategoryRow(text, menuList)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.hasArrow = true
    info.notCheckable = true
    info.keepShownOnClick = true
    info.menuList = menuList
    UIDropDownMenu_AddButton(info, 1)
end

-- A name's first character, as a whole UTF-8 sequence: one byte of
-- "\195\150dland" (deDE) or of any ruRU or koKR name is half a character, and
-- on its own an invalid one. Only an ASCII letter is upper-cased.
local function Initial(name)
    local first = type(name) == "string" and name:match("^[%z\1-\127\194-\244][\128-\191]*") or nil
    if not first or first == "" then return "?" end
    return #first == 1 and first:upper() or first
end

-- Where the next page ends: nearest the even split, at a change of initial,
-- never past MENU_PAGE rows. Returns the last index and whether it is a
-- clean cut (false when one initial runs longer than the page can hold).
local function PageEnd(items, first)
    local remaining = #items - first + 1
    if remaining <= MENU_PAGE then return #items, true end
    local pages = math.ceil(remaining / MENU_PAGE)
    local ideal = first + math.ceil(remaining / pages) - 1
    local best
    for last = first, first + MENU_PAGE - 1 do
        if Initial(items[last].name) ~= Initial(items[last + 1].name)
            and (not best or math.abs(last - ideal) < math.abs(best - ideal)) then
            best = last
        end
    end
    if best then return best, true end
    return ideal, false
end

-- One category, as one row or as pages. category = { key, text, zones }
-- (a faction list may call its list `items`); a page's menuList is
-- { key, first, last }, a whole category's is its key.
local function AddCategoryPages(category)
    local items = category.zones or category.items or {}
    if #items <= MENU_PAGE then
        AddCategoryRow(category.text, category.key)
        return
    end
    local pages, clean, first = {}, true, 1
    while first <= #items do
        local last, cut = PageEnd(items, first)
        clean = clean and cut
        pages[#pages + 1] = { key = category.key, first = first, last = last }
        first = last + 1
    end
    for index, page in ipairs(pages) do
        local text = string.format("%s  %s-%s", category.text,
            Initial(items[page.first].name), Initial(items[page.last].name))
        if not clean then text = string.format("%s (%d/%d)", text, index, #pages) end
        AddCategoryRow(text, page)
    end
end

C.AddCategoryRow, C.AddCategoryPages, C.Initial = AddCategoryRow, AddCategoryPages, Initial

-- ---------------------------------------------------------------------------
-- Words for an overview
-- ---------------------------------------------------------------------------

local function BreakdownText(totals)
    local counted = totals.countedByStatus or {}
    return string.format("Done %d%sIn log %d%sOpen %d%sLocked %d",
        counted.DONE or 0, SEP, counted.LOG or 0, SEP, counted.AVAILABLE or 0, SEP, counted.LOCKED or 0)
end

-- The uncounted line, from byStatus. The counted buckets' extra members --
-- the other choices of an exclusive group -- are the difference between the
-- two tallies.
local function UncountedText(totals)
    local by, counted = totals.byStatus or {}, totals.countedByStatus or {}
    local parts = { "Missed " .. (by.MISSED or 0) }
    if (by.RIVAL or 0) > 0 then parts[#parts + 1] = "Other faction " .. by.RIVAL end
    parts[#parts + 1] = "Repeatable " .. (by.REPEATABLE or 0)
    parts[#parts + 1] = "Seasonal " .. (by.SEASONAL or 0)
    if (by.OPTIONAL or 0) > 0 then parts[#parts + 1] = "Optional " .. by.OPTIONAL end
    if (by.EXTRA or 0) > 0 then parts[#parts + 1] = "Starting here " .. by.EXTRA end
    if (by.IGNORED or 0) > 0 then parts[#parts + 1] = "Ignored " .. by.IGNORED end
    local choices = 0
    for _, bucket in ipairs({ "DONE", "LOG", "AVAILABLE", "LOCKED" }) do
        choices = choices + math.max(0, (by[bucket] or 0) - (counted[bucket] or 0))
    end
    if choices > 0 then parts[#parts + 1] = "Other choices " .. choices end
    return table.concat(parts, SEP) .. " (not counted)"
end

-- "done  Name (Zone)" for a prerequisite or a follow-up
local function RefLine(ref)
    local word = ref.done and ToneMarkup("good", "done") or ToneMarkup("warn", "to do")
    local text = word .. "  " .. (ref.name or ("Quest " .. tostring(ref.id)))
    if ref.zoneName then text = text .. " (" .. ref.zoneName .. ")" end
    return text
end

-- A heading and its members, in the engine's own shape (Q.Completion.Group),
-- for a spec's Group: the header row counts its members and how many are
-- done, and every member's .header names it (BuildList finds a row's heading
-- through that field). Nothing is emitted for an empty group.
local function Emit(list, key, title, members)
    if #members == 0 then return end
    local header = {
        isHeader = true, title = title, group = key, countMode = "COUNT",
        quests = #members, complete = 0,
    }
    for _, entry in ipairs(members) do
        if entry.base == "DONE" then header.complete = header.complete + 1 end
    end
    list[#list + 1] = header
    for _, entry in ipairs(members) do
        entry.header = title
        list[#list + 1] = entry
    end
end

C.BreakdownText, C.UncountedText, C.RefLine, C.Emit = BreakdownText, UncountedText, RefLine, Emit

-- ---------------------------------------------------------------------------
-- Reputation words the tabs (and the map drawer) share
--
-- A faction's name inside one of our sentences loses its capital ("from the
-- Aldor's quests", never "from The Aldor's"), and a row's badge names the
-- faction its figure is for ("+550 CC"): a quest that pays Cenarion Circle
-- must never read like the best Honor Hold quest in Hellfire, which is the
-- very surprise the reputation work set out to end.
-- ---------------------------------------------------------------------------

-- "The Aldor" -> "the Aldor"
local function InSentence(name)
    return (tostring(name or ""):gsub("^The%s", "the "))
end

-- "the Aldor's", "the Scryers'"
local function Possessive(name)
    name = InSentence(name)
    if name:sub(-1) == "s" then return name .. "'" end
    return name .. "'s"
end

local function FactionNameOf(factionId)
    local adapter = Q.Questie
    if type(adapter) == "table" and type(adapter.FactionName) == "function" then
        local ok, name = pcall(adapter.FactionName, factionId)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Faction " .. tostring(factionId)
end

-- The short tag of a faction on a row's badge: the rules engine's
-- abbreviation ("HH", "CC", "Cons"), made unique over the factions the
-- view's rows badge (Booty Bay and Bloodsail Buccaneers are not both "BB"),
-- the faction most rows lead with keeping the shortest form. Worked out once
-- per view per adapter generation; nil without the rules.
local tagTables = setmetatable({}, { __mode = "k" })
local function RepTag(view, factionId)
    local R = Q.Standing
    if not (factionId and type(R) == "table" and type(R.Abbrev) == "function") then return nil end
    local adapter = Q.Questie
    local generation = type(adapter) == "table" and adapter.generation or 0
    local tags
    if type(view) == "table" and type(R.AbbrevTable) == "function" and type(R.Primary) == "function" then
        local cached = tagTables[view]
        if cached and cached.generation == generation then
            tags = cached.tags
        else
            local names, counts, order = {}, {}, {}
            for _, entry in ipairs(type(view.entries) == "table" and view.entries or {}) do
                local fact = type(entry) == "table" and entry.fact
                local effects = type(fact) == "table" and fact.repEffects or nil
                local id = type(effects) == "table" and R.Primary(effects) or nil
                if id then
                    if not names[id] then
                        names[id], counts[id] = FactionNameOf(id), 0
                        order[#order + 1] = id
                    end
                    counts[id] = counts[id] + 1
                end
            end
            table.sort(order, function(a, b)
                if counts[a] ~= counts[b] then return counts[a] > counts[b] end
                return a < b
            end)
            tags = R.AbbrevTable(names, order)
            tagTables[view] = { generation = generation, tags = tags }
        end
    end
    local tag = tags and tags[factionId]
    if type(tag) ~= "string" or tag == "" then tag = R.Abbrev(FactionNameOf(factionId)) end
    return tag
end

-- A gain and its faction's tag for a row badge ("+275 HH"), held to
-- BADGE_CHARS characters. The badge is capped at BADGE_MAX_W, and what runs
-- past it ends in an ellipsis -- the tag first, the very cue it is there
-- for. "+1,000 Scryers" (Varedis Must Be Stopped, Turning Point) is 14
-- characters, about 70-77 px in Friz Quadrata at 10, so the thousands comma
-- goes first ("+1000 Scryers"), then the tag is cut to its first four
-- letters ("+1000 Scry", "+2000 Mag" for Mag'har). "+385 Scryers" and
-- "+42,000 Neth" (12) stay whole, as A54 measured them. The row's tooltip
-- names the faction in full. (2026-10-05 review)
local BADGE_CHARS = 12
local function CharCount(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end
local function CharPrefix(text, count)
    local out = {}
    for char in text:gmatch("[^\128-\191][\128-\191]*") do
        if #out >= count then break end
        out[#out + 1] = char
    end
    return table.concat(out)
end
local function RepBadgeText(R, delta, tag)
    local number = (type(R) == "table" and type(R.FormatRep) == "function" and R.FormatRep(delta)) or tostring(delta)
    if type(tag) ~= "string" or tag == "" then return number end
    if CharCount(number .. " " .. tag) <= BADGE_CHARS then return number .. " " .. tag end
    number = (number:gsub(",", ""))
    if CharCount(number .. " " .. tag) <= BADGE_CHARS then return number .. " " .. tag end
    local short = (CharPrefix(tag, 4):gsub("[%p%s]+$", ""))
    if short == "" then return number end
    return number .. " " .. short
end

C.InSentence, C.Possessive, C.RepTag, C.RepBadgeText = InSentence, Possessive, RepTag, RepBadgeText

-- ===========================================================================
-- One catalogue
-- ===========================================================================

function C.New(spec)
    assert(type(spec) == "table" and type(spec.id) == "string", "Q.NewCatalogue needs a spec with an id")
    assert(type(spec.Resolve) == "function" and type(spec.View) == "function",
        "Q.NewCatalogue: the spec's Resolve and View are required")
    local Z = {}
    local prefix = spec.prefix or spec.id
    local KEYS = {
        filter = prefix .. "Filter", group = prefix .. "Group", collapsed = prefix .. "Collapsed",
        follow = prefix .. "Follow", picked = prefix .. "Picked",
    }
    for name, key in pairs(spec.keys or {}) do KEYS[name] = key end
    local NAMES = {
        groupDrop = "CommanderQuestLog" .. prefix .. "GroupDrop",
        menu = "CommanderQuestLog" .. prefix .. "Menu",
    }
    for name, frameName in pairs(spec.names or {}) do NAMES[name] = frameName end
    local SHOW_KEY = spec.showKey
    local TITLE = spec.title or spec.label or spec.id

    -- -----------------------------------------------------------------------
    -- State
    --
    -- S is what the last pass worked out; W is what it is drawn with. Two
    -- tables rather than thirty upvalues, which keeps every function here
    -- well inside what Lua 5.1 lets one close over.
    -- -----------------------------------------------------------------------

    local S = {
        state = "ABSENT", reason = nil,     -- the adapter's word on Questie
        key = nil, keyName = nil,           -- what is shown (an AREA id, a faction id)
        view = nil, err = nil,              -- the engine's view, or why there is none
        rows = {}, shown = 0,               -- BuildList's answer
        selectedId = nil, selectedEntry = nil,
        pendingSelect = nil, reveal = false,
        search = "",
        logByKey = {}, logDetail = nil,     -- the Log's scan, keyed like catalogue entries
        char = nil, playerPos = nil,
        detailCache = nil,
    }
    if spec.stateAliases then
        local aliases = spec.stateAliases
        setmetatable(S, { __index = function(t, name)
            local real = aliases[name]
            if real then return rawget(t, real) end
            return nil
        end })
    end

    local W = {
        built = false,
        -- The window's tab buttons by id (UI.lua's, the same table for every
        -- tab), here so a harness reaches them as it always has
        tabs = Q.TabButtons and Q.TabButtons() or nil,
        toolbar = nil, filters = {}, groupDrop = nil, countFS = nil,
        card = nil, menu = nil, actions = nil, actionList = {},
        rows = {}, emptyFS = nil,
        blocks = {}, quads = {}, bands = {},
        goLines = {},           -- the briefing's row Go buttons (D45)
    }

    -- The briefing's cursor for one layout pass
    local P = { y = 0, block = 1, quad = 1, band = 1, width = 0, go = 1 }

    -- Every hook's first argument (see the file header)
    local cat = setmetatable({ spec = spec, instance = Z, S = S, W = W, P = P, keys = KEYS },
        { __index = C })

    function Z.IsActive()
        local db = DB()
        return db.ViewMode == spec.id and (not SHOW_KEY or db[SHOW_KEY] ~= false)
            and db.EnableQuestLog ~= false
    end

    -- How far the navigator moves down for the card (UI.lua's AnchorNavPane).
    -- Asked of the window's own predicate for which tab draws (Q.ViewMode), not
    -- of Z.IsActive: that one also wants the module switched on, and a window
    -- left open after unchecking Enable Quest Log still draws this tab on a
    -- tab switch -- with the card over the navigator's first rows.
    function Z.NavTopInset()
        local mode = Q.ViewMode and Q.ViewMode()
        if mode == spec.id then return CARD_H + CARD_GAP end
        return 0
    end

    -- -----------------------------------------------------------------------
    -- The engine's words, or the spec's
    -- -----------------------------------------------------------------------

    local function StateWord(entry)
        local word, toneKey
        if spec.StateWord then word, toneKey = spec.StateWord(cat, entry) end
        if word == nil then word, toneKey = Engine().StateWord(entry) end
        return word, toneKey
    end

    local function Reason(entry)
        local sentence
        if spec.Reason then sentence = spec.Reason(cat, entry) end
        if sentence == nil then sentence = Engine().Reason(entry, S.char or {}, S.view) end
        return sentence
    end

    -- -----------------------------------------------------------------------
    -- Givers and waypoints
    -- -----------------------------------------------------------------------

    local function LogEntryFor(entry)
        return entry and S.logByKey[entry.key] or nil
    end

    local function StarterArea(entry)
        if spec.StarterArea then return spec.StarterArea(cat, entry) end
        return nil
    end

    -- Where a waypoint for this quest goes: its turn-in once it is in the log
    -- and ready, else where it starts, else (in the log, no starter placed)
    -- its turn-in after all. Returns record, "finisher" | "starter".
    local function WaypointTarget(entry)
        local adapter = Adapter()
        if not (entry and adapter) then return nil end
        local logEntry = LogEntryFor(entry)
        local inLog = entry.base == "LOG" or logEntry ~= nil
        local ready = entry.ready or (logEntry and logEntry.isComplete)
        if inLog and ready then
            local finisher = FirstPlaced(entry.finishers)
            if finisher then return finisher, "finisher" end
        end
        local starter = adapter.BestStarter and adapter.BestStarter(entry, StarterArea(entry))
        if starter and starter.x and starter.y then return starter, "starter" end
        if inLog then
            local finisher = FirstPlaced(entry.finishers)
            if finisher then return finisher, "finisher" end
        end
        return nil
    end

    -- The adapter's waypoint target for a quest: its giver or its turn-in
    -- (WaypointTarget's choice), with every spawn of that giver riding along
    -- so the arrow takes the nearest: BestStarter packs them, a raw finisher
    -- record has them in its list
    local function GoTarget(entry)
        local adapter = Adapter()
        local target, role = WaypointTarget(entry)
        if not (target and adapter) then return nil end
        local spawns = target.spawns
        if not spawns and role == "finisher" and adapter.SpawnsOf then
            spawns = adapter.SpawnsOf(entry.finishers, target)
        end
        return {
            title = string.format("%s (%s)", entry.title or "Quest",
                target.name or (role == "finisher" and "turn in" or "quest giver")),
            areaId = target.areaId, uiMapId = target.uiMapId,
            zoneName = target.zoneName or ZoneNameOf(target),
            x = target.x, y = target.y, questId = entry.id, spawns = spawns,
        }
    end

    local function SendWaypoint(entry)
        local adapter = Adapter()
        local target = GoTarget(entry)
        if not (target and adapter and adapter.Waypoint) then
            print("Commander Quest Log: Questie does not know where |cffffd100" ..
                tostring(entry and entry.title or "that quest") .. "|r starts.")
            return nil
        end
        return adapter.Waypoint(target)
    end

    -- -----------------------------------------------------------------------
    -- Actions
    -- -----------------------------------------------------------------------

    -- Ignore is per character and leaves the quest listed (under Ignored).
    -- The adapter recomputes on its debounce, so the percentage follows a
    -- quarter second later; the button's own word flips at once.
    local function ToggleIgnore()
        local entry = S.selectedEntry
        if not entry then return end
        local ignored = IgnoredSet()
        if ignored[entry.id] then ignored[entry.id] = nil else ignored[entry.id] = true end
        local adapter = Adapter()
        if adapter and adapter.Bump then adapter.Bump("ignore") end
        Z.UpdateActions()
    end

    -- The uiMapID Show on Map opens, and the AREA id it came from
    local function MapFor(entry)
        local areaId = spec.MapArea and spec.MapArea(cat, entry) or nil
        local adapter = Adapter()
        if not (areaId and adapter and adapter.UiMapForArea) then return nil end
        return adapter.UiMapForArea(areaId), areaId
    end

    -- Out of combat only: opening the map from addon code is the one thing
    -- here that touches a Blizzard panel, and the Log refuses rather than
    -- risk it.
    local function ShowOnMap()
        if InCombatLockdown and InCombatLockdown() then
            print("Commander Quest Log: the world map is not opened from here in combat. Try again once you are out of it.")
            return
        end
        local uiMapId, areaId = MapFor(S.selectedEntry)
        if not uiMapId then return end
        local map = WorldMapFrame
        if not (map and map.IsShown and map:IsShown()) then
            -- ToggleWorldMap first: it is the player's own path (and loads
            -- the map, should a client ever make it load-on-demand again)
            if ToggleWorldMap then
                ToggleWorldMap()
            elseif map and ShowUIPanel then
                ShowUIPanel(map)
            end
            map = WorldMapFrame
        end
        if not map then return end
        if map.SetMapID then map:SetMapID(uiMapId) end
        -- The zone goes along, so the drawer can move the map itself should
        -- the SetMapID above not have landed (a map that was mid-transition)
        if S.selectedEntry and Q.Map and Q.Map.Focus then Q.Map.Focus(S.selectedEntry.id, areaId) end
        -- A maximised map is FULLSCREEN and covers this window, which is right
        -- where it was when the map closes. A windowed map is MEDIUM, and this
        -- window (HIGH) would sit on top of it, so it steps aside.
        if map.IsMaximized and not map:IsMaximized() and CommanderQuestLog_Hide then CommanderQuestLog_Hide() end
    end

    -- The Log keeps its own fold, filter and search, and any of them could
    -- hide the quest asked for; Q.RevealInLog opens them up for it (the Log's
    -- side of D31) where a plain select would brief whatever row came first
    local function OpenInLog()
        local logEntry = LogEntryFor(S.selectedEntry)
        if not logEntry then return end
        if Q.RevealInLog then
            Q.RevealInLog(logEntry.key)
            return
        end
        if Q.SetViewMode then Q.SetViewMode("LOG") end
        if Q.Select then Q.Select(logEntry.key) end
    end

    -- -----------------------------------------------------------------------
    -- The card's menu: following, pinning, and the spec's own list
    -- -----------------------------------------------------------------------

    local function Follow()
        local db = DB()
        db[KEYS.follow] = true
        db[KEYS.picked] = false
        S.selectedId = nil
        if CloseDropDownMenus then CloseDropDownMenus() end
        Q.Refresh()
    end

    local function Pick(_, key)
        if type(key) ~= "number" then return end
        local db = DB()
        db[KEYS.follow] = false
        db[KEYS.picked] = key
        S.selectedId = nil
        if CloseDropDownMenus then CloseDropDownMenus() end
        Q.Refresh()
    end

    local function MenuInit(_, level, menuList)
        if spec.MenuInit then spec.MenuInit(cat, level, menuList) end
    end

    local function OpenMenu(anchor)
        if not (W.menu and ToggleDropDownMenu) then return end
        ToggleDropDownMenu(1, nil, W.menu, anchor, 0, 0)
    end

    -- -----------------------------------------------------------------------
    -- Building the tab's widgets (first use)
    -- -----------------------------------------------------------------------

    local function GroupModes()
        if spec.groups then return spec.groups end
        local engine = Engine()
        return engine and engine.GROUPS or {}
    end

    local function GroupLabel(mode)
        if spec.groupLabels and spec.groupLabels[mode] then return spec.groupLabels[mode] end
        local engine = Engine()
        return (engine and engine.GROUP_LABELS[mode]) or mode
    end

    local function PickGroup(_, mode)
        DB()[KEYS.group] = mode
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(W.groupDrop, mode) end
        Q.Refresh()
    end

    local function GroupDropInit()
        local engine = Engine()
        if not engine then return end
        for _, mode in ipairs(GroupModes()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = GroupLabel(mode)
            info.value = mode
            info.checked = (DB()[KEYS.group] or "GUIDE") == mode
            info.arg1 = mode
            info.func = PickGroup
            UIDropDownMenu_AddButton(info)
        end
    end

    -- The tab's set of the toolbar: five filters where the Log has four
    -- (narrower, so the shared search box after them does not move), the
    -- group dropdown in the Log's sort slot, and a "n shown" readout at the
    -- right
    local function BuildToolbar(frame)
        local kit, engine = Kit(), Engine()
        local bar = CreateFrame("Frame", nil, frame.toolbar)
        bar:SetAllPoints(frame.toolbar)
        W.toolbar = bar

        local order = spec.filterOrder or (engine and engine.FILTER_ORDER) or DEFAULT_FILTER_ORDER
        local previous
        for _, key in ipairs(order) do
            local filterSpec = (spec.filterSpecs and spec.filterSpecs[key])
                or (engine and engine.FILTERS[key]) or { label = key, tooltip = "" }
            local button = CreateFrame("Button", nil, bar)
            button:SetSize(FILTER_W, kit.TOOLBAR_H)
            button:SetNormalFontObject(GameFontDisableSmall)
            button:SetHighlightFontObject(GameFontHighlightSmall)
            button:SetText(filterSpec.label)
            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else
                button:SetPoint("LEFT", bar, "LEFT", 0, 0)
            end
            button.underline = kit.Quad(button, "ARTWORK")
            button.underline:SetHeight(2)
            button.underline:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 5, 2)
            button.underline:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -5, 2)
            button:SetScript("OnClick", function()
                DB()[KEYS.filter] = key
                Q.Refresh()
            end)
            Tip(button, filterSpec.label, filterSpec.tooltip, "ANCHOR_BOTTOM")
            ReinkAfterHover(button, function() Z.RestyleToolbar() end)
            W.filters[key] = button
            previous = button
        end

        local drop = CreateFrame("Frame", NAMES.groupDrop, bar, "UIDropDownMenuTemplate")
        drop:SetPoint("LEFT", frame.searchBox, "RIGHT", -6, -2)
        if UIDropDownMenu_Initialize then
            UIDropDownMenu_Initialize(drop, GroupDropInit)
            UIDropDownMenu_SetWidth(drop, 118)
        end
        W.groupDrop = drop

        local hit = CreateFrame("Frame", nil, bar)
        hit:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
        hit:SetSize(110, kit.TOOLBAR_H)
        hit:EnableMouse(true)
        W.countFS = hit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        W.countFS:SetPoint("RIGHT", hit, "RIGHT", 0, 0)
        Tip(hit, "Shown", spec.countTip
            or "How many of the listed quests the search and the filter leave on the list.",
            "ANCHOR_BOTTOM")
    end

    local function CardEnter(self)
        if spec.CardTooltip then
            spec.CardTooltip(cat, self)
            return
        end
        local engine = Engine()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(S.keyName or TITLE, 1, 1, 1)
        if S.view and engine then
            GameTooltip:AddLine(engine.TotalsText(S.view.totals) .. " of the quests that count here.", 0.85, 0.85, 0.85)
        end
        GameTooltip:AddLine("Click to pick from the list. Right-click to follow.", 0.55, 0.55, 0.6, true)
        GameTooltip:Show()
    end

    -- The card: name and totals, a bar, and whether it follows you. A
    -- Button, because it is the picker.
    local function BuildCard(frame)
        local kit = Kit()
        local card = CreateFrame("Button", nil, frame)
        card:SetSize(kit.NAV_W, CARD_H)
        card:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
        card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        card.bg = kit.Quad(card, "BACKGROUND")
        card.bg:SetAllPoints()
        card.rule = kit.Quad(card, "ARTWORK")
        card.rule:SetHeight(1)
        card.rule:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card.rule:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)

        card.name = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        card.name:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -6)
        card.name:SetPoint("RIGHT", card, "RIGHT", -104, 0)
        card.name:SetJustifyH("LEFT")

        card.totals = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        card.totals:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
        card.totals:SetJustifyH("RIGHT")

        card.barBg = kit.Quad(card, "ARTWORK", 1)
        card.barBg:SetHeight(CARD_BAR_H)
        card.barBg:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -24)
        card.barBg:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -24)
        card.bar = kit.Quad(card, "ARTWORK", 2)
        card.bar:SetHeight(CARD_BAR_H)
        card.bar:SetPoint("TOPLEFT", card.barBg, "TOPLEFT", 0, 0)

        card.note = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        card.note:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -32)
        card.note:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        card.note:SetJustifyH("LEFT")
        -- One line, cut short rather than wrapped: the card is CARD_H tall
        -- and a second line would sit on the navigator's top rows (the
        -- tooltip says it all in full)
        if card.note.SetWordWrap then card.note:SetWordWrap(false) end
        if card.note.SetMaxLines then card.note:SetMaxLines(1) end

        local highlight = card:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(kit.QUAD)
        highlight:SetVertexColor(1, 1, 1, 0.05)
        card:SetHighlightTexture(highlight)

        card:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                Follow()
                return
            end
            S.selectedId = nil
            Q.Refresh()
            OpenMenu(self)
        end)
        card:SetScript("OnEnter", CardEnter)
        card:SetScript("OnLeave", HideTooltip)
        W.card = card

        -- Deliberately never anchored, like the suite's other menu frames: a
        -- MENU dropdown keeps an invisible, clickable button of its own, and
        -- one with a rect over the navigator would eat clicks meant for its
        -- first row. The list itself hangs off the card (ToggleDropDownMenu's
        -- anchor).
        local menu = CreateFrame("Frame", NAMES.menu, frame, "UIDropDownMenuTemplate")
        if UIDropDownMenu_Initialize then UIDropDownMenu_Initialize(menu, MenuInit, "MENU") end
        W.menu = menu
    end

    -- The stock actions every catalogue may list. Their words are the Zones
    -- tab's; a spec gives its own with { stock = ..., tooltip = ... }.
    local STOCK = {
        WAYPOINT = {
            field = "waypointBtn", label = "Go", width = 80, go = true,
            tooltip = function()
                local kit = Kit()
                local text = "Go to where this quest starts or, once it is in your log and ready, to where it is handed in. "
                -- Orders turned off greys the Go: no press to promise, only
                -- the row's right-click (the Kit's GoGreyedOff)
                if kit.GoGreyedOff and kit.GREYED_OFF and kit.GoGreyedOff() then
                    return text .. kit.GREYED_OFF:format("right-clicking a row")
                end
                local where = kit.WaypointWhere and kit.WaypointWhere() or "the chat frame"
                return text .. "Right-clicking a row does the same. Goes to " .. where .. "."
            end,
            onClick = function()
                if S.selectedEntry then SendWaypoint(S.selectedEntry) end
            end,
        },
        MAP = {
            field = "mapBtn", label = "Show on Map", width = 96,
            tooltip = "Open the world map on this zone, with the selected quest's givers marked. Not from here in combat.",
            onClick = ShowOnMap,
        },
        LOG = {
            field = "logBtn", label = "Open in Log", width = 92,
            tooltip = "Switch to the Log tab with this quest selected. Only for a quest that is in your log.",
            onClick = OpenInLog,
        },
        IGNORE = {
            field = "ignoreBtn", label = "Ignore", width = 72, right = true,
            tooltip = function()
                if S.selectedEntry and IsIgnored(S.selectedEntry.id) then
                    return "Put this quest back into the zone's 100%."
                end
                return "Leave this quest out of the zone's 100% for this character, for a quest you will never do. It stays on the list, under Ignored, and Count puts it back."
            end,
            onClick = ToggleIgnore,
        },
    }

    -- A spec's action list item as one table: a stock name, a stock action
    -- with words of its own, or a custom action
    local function ResolveAction(item)
        if type(item) == "string" then
            local stock = STOCK[item]
            if not stock then return nil end
            local action = { stock = item }
            for name, value in pairs(stock) do action[name] = value end
            return action
        end
        if type(item) ~= "table" then return nil end
        local action = {}
        if item.stock and STOCK[item.stock] then
            for name, value in pairs(STOCK[item.stock]) do action[name] = value end
        end
        for name, value in pairs(item) do action[name] = value end
        if not action.field then return nil end
        return action
    end

    -- The action bar: the spec's buttons packed from the left, and the ones
    -- marked `right` from the right edge (Ignore, where the Log keeps
    -- Abandon). A tooltip may be a function; it is asked with cat.
    local function BuildActions(frame)
        local actions = CreateFrame("Frame", nil, frame.actions)
        actions:SetAllPoints(frame.actions)
        W.actions = actions

        local function Button(label, width, tooltip, handler)
            local button = CreateFrame("Button", nil, actions, "UIPanelButtonTemplate")
            button:SetSize(width, 22)
            button:SetText(label)
            button:SetScript("OnClick", handler)
            Tip(button, label, tooltip, "ANCHOR_TOP")
            return button
        end

        -- The stock Go (D45): the suite's Go button over the selected quest,
        -- keyed by it as its spec is read; a plain button on SendWaypoint
        -- without it (the kit decides)
        local function GoAction(label, width, tooltip)
            local opts = { label = label, width = width, height = 22, source = "QuestLog", anchor = "ANCHOR_TOP",
                           tooltip = tooltip }
            opts.spec = function()
                local adapter = Adapter()
                local target = S.selectedEntry and GoTarget(S.selectedEntry)
                local spec, key, questId, note
                if target and adapter and adapter.WaypointSpec then
                    spec, key, questId, note = adapter.WaypointSpec(target)
                end
                opts.key, opts.questId, opts.note = key, questId, note
                return spec
            end
            opts.onGo = function(uid)
                local adapter = Adapter()
                if uid and adapter and adapter.NoteGo then adapter.NoteGo(opts.questId, opts.key, opts.note) end
            end
            opts.fallback = function()
                if S.selectedEntry then SendWaypoint(S.selectedEntry) end
            end
            return Kit().GoButton(actions, opts)
        end

        local left, right
        for _, item in ipairs(spec.actions or DEFAULT_ACTIONS) do
            local action = ResolveAction(item)
            if action then
                local tooltip = action.tooltip
                if type(tooltip) == "function" then
                    local ask = tooltip
                    tooltip = function() return ask(cat) end
                end
                local onClick = action.onClick
                local button
                if action.go and Kit().GoButton then
                    button = GoAction(action.label or "Go", action.width or 80, tooltip)
                else
                    button = Button(action.label or action.field, action.width or 80, tooltip, function()
                        if onClick then onClick(cat) end
                    end)
                end
                if action.right then
                    if right then
                        button:SetPoint("RIGHT", right, "LEFT", -4, 0)
                    else
                        button:SetPoint("RIGHT", actions, "RIGHT", 0, 0)
                    end
                    right = button
                else
                    if left then
                        button:SetPoint("LEFT", left, "RIGHT", 4, 0)
                    else
                        button:SetPoint("LEFT", actions, "LEFT", 0, 0)
                    end
                    left = button
                end
                action.button = button
                W[action.field] = button
                W.actionList[#W.actionList + 1] = action
            end
        end
    end

    local function EnsureBuilt(frame)
        if W.built then return end
        W.built = true
        BuildToolbar(frame)
        BuildCard(frame)
        BuildActions(frame)
    end

    -- -----------------------------------------------------------------------
    -- Navigator rows
    -- -----------------------------------------------------------------------

    local function RowClick(self, button)
        if self.headerTitle then
            local db = DB()
            local collapsed = db[KEYS.collapsed] or {}
            collapsed[self.headerTitle] = (not collapsed[self.headerTitle]) or nil
            db[KEYS.collapsed] = collapsed
            Q.Refresh()
            return
        end
        local entry = self.entry
        if not entry then return end
        if button == "RightButton" then
            SendWaypoint(entry)
            return
        end
        -- Clicking the briefed quest again goes back to the overview
        if S.selectedId == entry.id then
            S.selectedId = nil
        else
            S.selectedId = entry.id
            local scroll = Kit().DetailScroll()
            if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
        end
        Q.Refresh()
    end

    local function RowEnter(self)
        local entry = self.entry
        local engine = Engine()
        if not (entry and engine) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.title, 1, 1, 1)
        GameTooltip:AddLine(Reason(entry), 0.85, 0.85, 0.85, true)
        local adapter = Adapter()
        local starter = adapter and adapter.BestStarter and adapter.BestStarter(entry, StarterArea(entry))
        if not starter then
            local first = DistinctGivers(entry.starters, 1)[1]
            if first then starter = first end
        end
        if starter then GameTooltip:AddLine("Starts: " .. GiverPhrase(starter), 0.7, 0.7, 0.75, true) end
        if spec.RowTooltip then spec.RowTooltip(cat, entry) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click for details. Right-click for a waypoint.", 0.55, 0.55, 0.6)
        GameTooltip:Show()
    end

    local function AcquireRow(position)
        local row = W.rows[position]
        if row then return row end
        local kit = Kit()
        row = CreateFrame("Button", nil, kit.NavChild())
        row:SetHeight(kit.QUEST_ROW_H)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.selection = kit.Quad(row, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:Hide()

        -- The status strip: a quad down the left edge, tinted by the quest's state
        row.strip = kit.Quad(row, "ARTWORK", 1)
        row.strip:SetWidth(3)
        row.strip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        row.strip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.strip:Hide()

        row.level = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.level:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.level:SetWidth(26)
        row.level:SetJustifyH("RIGHT")

        row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
        row.title:SetJustifyH("LEFT")
        -- One line, cut with an ellipsis: about one title in twenty-five is
        -- wider than the column, and two 10 px lines do not fit a 24 px row.
        -- The row's tooltip carries the whole title.
        if row.title.SetWordWrap then row.title:SetWordWrap(false) end

        row.state = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.state:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.state:SetWidth(STATE_W)
        row.state:SetJustifyH("RIGHT")

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(kit.QUAD)
        highlight:SetVertexColor(1, 1, 1, 0.07)
        row:SetHighlightTexture(highlight)

        row:SetScript("OnClick", RowClick)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", HideTooltip)
        W.rows[position] = row
        return row
    end

    -- The badge left of the state word, made the first time a spec's
    -- RowRight answers for this row
    local function EnsureBadge(row)
        if row.badge then return row.badge end
        row.badge = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.badge:SetPoint("RIGHT", row.state, "LEFT", -BADGE_GAP, 0)
        row.badge:SetJustifyH("RIGHT")
        if row.badge.SetWordWrap then row.badge:SetWordWrap(false) end
        return row.badge
    end

    local function EmptyMessage()
        local state = S.state
        if state == "ABSENT" then
            return "Questie is not loaded. The " .. (spec.label or TITLE)
                .. " tab reads Questie's quest database; the Log tab works without it."
        end
        if state == "LOADING" then return "Questie is still loading" .. ELLIPSIS end
        if state == "BROKEN" then
            return "Questie is loaded but did not answer the way this window expects"
                .. (S.reason and (" (" .. tostring(S.reason) .. ")") or "")
                .. ". The Log tab still works; /cql status has the detail."
        end
        if spec.EmptyMessage then return spec.EmptyMessage(cat) end
        if not S.key then return "Nothing to show here. Pick one from the card above." end
        if S.err == "NO_QUESTS" then
            return "Questie lists no quests for " .. (S.keyName or "this one") .. ". Pick another from the card above."
        end
        if not S.view then
            return "This list could not be read (" .. tostring(S.err or "no answer") .. "). /cql status has the detail."
        end
        -- A view with nothing in it at all (every quest held back by a later
        -- content phase, say) is not the search's doing
        if #(S.view.entries or {}) == 0 then
            return "Nothing in " .. (S.keyName or "this list") .. " is listed for this character."
        end
        return "Nothing in " .. (S.keyName or "this list") .. " matches this search and filter."
    end

    local function LayoutHeaderRow(row, item, ar, ag, ab)
        local kit = Kit()
        local header = item.header
        row.headerTitle = header.title
        row:SetHeight(kit.ROW_H)
        kit.PointChevron(row, not item.collapsed)
        for _, bar in ipairs(row.chevron) do
            bar:SetVertexColor(ar, ag, ab, 0.9)
            bar:Show()
        end
        if row.badge then row.badge:Hide() end
        row.level:SetText("")
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row, "LEFT", 20, 0)
        row.title:SetPoint("RIGHT", row, "RIGHT", -(STATE_W + 8), 0)
        row.title:SetText(header.title)
        row.title:SetTextColor(kit.InkAccent())
        -- A chain heading reads done/total of its counted members; every
        -- other heading counts what it lists under the current search and
        -- filter
        if header.countMode == "RATIO" then
            row.state:SetText(string.format("%d/%d", header.complete or 0, header.quests or 0))
        else
            row.state:SetText(tostring(item.shownCount or header.quests or 0))
        end
        row.state:SetTextColor(kit.Paper(kit.Ink("secondary")))
        row.selection:SetVertexColor(ar, ag, ab, 0.08)
        row.selection:Show()
    end

    local function LayoutQuestRow(row, entry, ar, ag, ab)
        local kit = Kit()
        row.entry = entry
        if row.chevron then
            for _, bar in ipairs(row.chevron) do bar:Hide() end
        end
        row:SetHeight(kit.QUEST_ROW_H)

        row.strip:SetVertexColor(kit.Paper(ToneRGB(StatusToneKey(entry))))
        row.strip:Show()

        -- The spec's badge, when it has one for this quest: it takes its own
        -- width out of the title's, never more than BADGE_MAX_W
        local badgeText, badgeColour, dim
        if spec.RowRight then badgeText, badgeColour, dim = spec.RowRight(cat, entry) end
        local reserve = STATE_W + 10
        if badgeText and badgeText ~= "" then
            local badge = EnsureBadge(row)
            -- Measured unconstrained (a width of 0 is "as wide as the text"),
            -- then held to the cap
            badge:SetWidth(0)
            badge:SetText(badgeText)
            badge:SetTextColor(kit.Paper(ColourRGB(badgeColour)))
            badge:Show()
            local natural = (badge.GetUnboundedStringWidth and badge:GetUnboundedStringWidth())
                or badge:GetStringWidth() or 0
            local width = math.min(math.ceil(natural), BADGE_MAX_W)
            badge:SetWidth(width)
            reserve = reserve + width + BADGE_GAP
        elseif row.badge then
            row.badge:Hide()
        end

        if DB().ShowLevels ~= false and (entry.level or 0) > 0 then
            row.level:SetText(tostring(entry.level))
            row.level:SetTextColor(kit.Paper(Q.DifficultyColor(entry.level, S.char and S.char.level)))
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", row.level, "RIGHT", 5, 0)
        else
            row.level:SetText("")
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", row, "LEFT", 14, 0)
        end
        row.title:SetPoint("RIGHT", row, "RIGHT", -reserve, 0)
        row.title:SetText(entry.title)
        -- Dimmed by whether it COUNTS, not by its bucket: an exclusive
        -- choice's other members sit in Available or Locked and do not count
        if not entry.counted or dim then
            row.title:SetTextColor(kit.Paper(kit.Ink("faint")))
        elseif entry.base == "LOG" and entry.ready then
            row.title:SetTextColor(kit.Paper(kit.Ink("strong")))
        else
            row.title:SetTextColor(kit.Paper(kit.Ink("primary")))
        end

        local word, toneKey = StateWord(entry)
        row.state:SetText(word or "")
        row.state:SetTextColor(kit.Paper(ToneRGB(toneKey)))

        if S.selectedId and entry.id == S.selectedId then
            row.selection:SetVertexColor(ar, ag, ab, 0.22)
            row.selection:Show()
        end
    end

    local function LayoutRows()
        local kit = Kit()
        local navChild = kit.NavChild()
        -- The selection band, the heading wash and the chevrons are fills,
        -- and on the paper a fill is ink too (the default accent is white)
        local ar, ag, ab = kit.InkAccent()
        local y = 4
        S.selectedTop, S.selectedHeight = nil, nil

        for position, item in ipairs(S.rows) do
            local row = AcquireRow(position)
            row.entry, row.headerTitle = nil, nil
            row.selection:Hide()
            row.strip:Hide()
            if item.header then
                LayoutHeaderRow(row, item, ar, ag, ab)
            else
                LayoutQuestRow(row, item.entry, ar, ag, ab)
                if S.selectedId and item.entry.id == S.selectedId then
                    S.selectedTop, S.selectedHeight = y, row:GetHeight()
                end
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", navChild, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", navChild, "RIGHT", 0, 0)
            row:Show()
            y = y + row:GetHeight()
        end
        for position = #S.rows + 1, #W.rows do W.rows[position]:Hide() end

        if #S.rows == 0 then
            if not W.emptyFS then
                W.emptyFS = navChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
                W.emptyFS:SetPoint("TOPLEFT", navChild, "TOPLEFT", 12, -16)
                W.emptyFS:SetWidth(kit.NAV_W - 30)
                W.emptyFS:SetJustifyH("LEFT")
            end
            W.emptyFS:SetText(EmptyMessage())
            W.emptyFS:SetTextColor(kit.Paper(kit.Ink("faint")))
            W.emptyFS:Show()
            y = y + 60
        elseif W.emptyFS then
            W.emptyFS:Hide()
        end
        navChild:SetHeight(math.max(y + 6, 1))
    end

    -- -----------------------------------------------------------------------
    -- The briefing: drawing primitives
    --
    -- Pooled by position like the Log's, with the font and the colour put
    -- back on every pass (D15): the overview and a quest put different kinds
    -- of line at the same position. Quads come from two pools, bars and marks
    -- over the text layer and selection bands under it.
    -- -----------------------------------------------------------------------

    local function AcquireBlock(position, template)
        local block = W.blocks[position]
        if not block then
            block = Kit().DetailChild():CreateFontString(nil, "ARTWORK", template)
            block:SetJustifyH("LEFT")
            block:SetJustifyV("TOP")
            block._template = template
            W.blocks[position] = block
            return block
        end
        if block._template ~= template then
            block._template = template
            local font = _G[template]
            if font and block.SetFontObject then block:SetFontObject(font) end
        end
        return block
    end

    local function AcquireQuad(pool, position, layer)
        local quad = pool[position]
        if quad then return quad end
        quad = Kit().Quad(Kit().DetailChild(), layer)
        pool[position] = quad
        return quad
    end

    -- One line of text at the cursor; colour is an {r, g, b} table and goes
    -- through Paper() here, so no caller can forget it. Returns block, height.
    local function Line(text, template, colour, indent, right)
        local kit = Kit()
        indent = indent or 0
        local block = AcquireBlock(P.block, template or "GameFontHighlightSmall")
        P.block = P.block + 1
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -P.y)
        block:SetWidth(P.width - indent - (right or 0))
        block:SetText(text or "")
        local c = colour or InkT("secondary")
        block:SetTextColor(kit.Paper(c[1], c[2], c[3]))
        block:Show()
        local height = math.max(block:GetStringHeight() or 12, 12)
        P.y = P.y + height + 3
        return block, height
    end

    local function Heading(text)
        return Line(text, "GameFontNormalSmall", { Kit().InkAccent() })
    end

    -- A bar: a ground quad and an accent fill across `fraction` of it
    local function Bar(indent, height, fraction, gap)
        local kit = Kit()
        local span = P.width - indent
        local ground = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        ground:ClearAllPoints()
        ground:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -P.y)
        ground:SetSize(span, height)
        if kit.OnPaper() then ground:SetVertexColor(0, 0, 0, 0.14) else ground:SetVertexColor(1, 1, 1, 0.1) end
        ground:Show()
        if fraction and fraction > 0 then
            local fill = AcquireQuad(W.quads, P.quad, "ARTWORK")
            P.quad = P.quad + 1
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", ground, "TOPLEFT", 0, 0)
            fill:SetSize(math.max(1, span * math.min(fraction, 1)), height)
            local r, g, b = kit.InkAccent()
            fill:SetVertexColor(r, g, b, 0.9)
            fill:Show()
        end
        P.y = P.y + height + (gap or 6)
    end

    local function Rule(spacingAbove)
        local kit = Kit()
        P.y = P.y + (spacingAbove or 6)
        local rule = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD, -P.y)
        rule:SetSize(P.width, 1)
        local r, g, b = kit.InkAccent()
        rule:SetVertexColor(r, g, b, 0.25)
        rule:Show()
        P.y = P.y + 7
    end

    -- A small square at the cursor, for a chain member's state (a quad,
    -- never a bullet glyph -- D11). It does not move the cursor; the line
    -- beside it does.
    local function Mark(indent, toneKey)
        local kit = Kit()
        local mark = AcquireQuad(W.quads, P.quad, "ARTWORK")
        P.quad = P.quad + 1
        mark:ClearAllPoints()
        mark:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD + indent, -(P.y + 3))
        mark:SetSize(MARK_SIZE, MARK_SIZE)
        local r, g, b = kit.Paper(ToneRGB(toneKey))
        mark:SetVertexColor(r, g, b, 1)
        mark:Show()
    end

    -- The accent band under the current quest's line in its chain
    local function Band(top, height)
        local kit = Kit()
        local band = AcquireQuad(W.bands, P.band, "BACKGROUND")
        P.band = P.band + 1
        band:ClearAllPoints()
        band:SetPoint("TOPLEFT", kit.DetailChild(), "TOPLEFT", kit.PAD - 2, -top)
        band:SetSize(P.width + 4, height)
        local r, g, b = kit.InkAccent()
        band:SetVertexColor(r, g, b, 0.16)
        band:Show()
    end

    -- -----------------------------------------------------------------------
    -- The briefing: what is drawn
    -- -----------------------------------------------------------------------

    -- Everything Questie knows about the selected quest beyond its fact,
    -- read lazily once per quest per key per adapter generation
    local function DetailFor(entry)
        local adapter = Adapter()
        if not (entry and adapter and adapter.QuestDetail) then return nil end
        local generation = adapter.generation or 0
        local cached = S.detailCache
        if cached and cached.id == entry.id and cached.key == S.key and cached.generation == generation then
            return cached.detail
        end
        local detail
        if spec.QuestDetail then
            detail = spec.QuestDetail(cat, entry)
        else
            detail = adapter.QuestDetail(entry.id, spec.DetailArea and spec.DetailArea(cat) or nil)
        end
        S.detailCache = { id = entry.id, key = S.key, generation = generation, detail = detail }
        return detail
    end

    local function LayoutMessage()
        local kit = Kit()
        Line(S.keyName or TITLE, "GameFontNormalLarge", kit.InkSet().title)
        Line(EmptyMessage(), "GameFontHighlightSmall", InkT("secondary"))
    end

    -- With no spec painter: the name and the engine's totals
    local function DefaultOverview(view)
        local kit, engine = Kit(), Engine()
        local totals = view.totals or {}
        Line(view.name or S.keyName or "", "GameFontNormalLarge", kit.InkSet().title)
        Line(string.format("%d of %d quests done%s%s", totals.done or 0, totals.counted or 0, SEP,
            engine.PercentText(totals.pct)), "GameFontHighlight", InkT("primary"))
        Bar(0, TOTAL_BAR_H, totals.pct or 0)
    end

    local function LayoutOverview(view)
        if spec.PaintOverview then spec.PaintOverview(cat, view) else DefaultOverview(view) end
        if spec.OverviewSections then spec.OverviewSections(cat, view) end
    end

    local function DefaultFacts(entry, view)
        local facts = {}
        if (entry.level or 0) > 0 then facts[#facts + 1] = "Level " .. entry.level end
        if (entry.requiredLevel or 0) > 0 then facts[#facts + 1] = "requires " .. entry.requiredLevel end
        if view.name then facts[#facts + 1] = view.name end
        if entry.tag and TAG_WORDS[entry.tag] then facts[#facts + 1] = TAG_WORDS[entry.tag] end
        if entry.startsHere == false and entry.startZoneName then
            facts[#facts + 1] = "starts in " .. entry.startZoneName
        end
        if not entry.counted then facts[#facts + 1] = "not counted" end
        return facts
    end

    local function LayoutWhere(entry)
        Rule(4)
        Heading("WHERE")
        local starters = DistinctGivers(entry.starters, GIVERS_SHOWN)
        if #starters == 0 then
            Line("Starts  nowhere Questie knows of", "GameFontHighlightSmall", InkT("faint"), 4)
        end
        for _, starter in ipairs(starters) do
            Line("Starts  " .. GiverPhrase(starter), "GameFontHighlightSmall", InkT("primary"), 4)
        end
        local finisher = FirstPlaced(entry.finishers) or DistinctGivers(entry.finishers, 1)[1]
        if finisher then
            Line("Ends  " .. GiverPhrase(finisher), "GameFontHighlightSmall", InkT("primary"), 4)
        end
    end

    local function LayoutChain(entry, view)
        local chain
        for _, candidate in ipairs(view.chains or {}) do
            if candidate.id == entry.chain then chain = candidate break end
        end
        if not chain then return end
        Rule()
        -- the spec's own name for what its chains hold (the Reputations
        -- tab's hold only the quests that pay the faction)
        local label = spec.chainLabel
        if type(label) == "function" then label = label(cat) end
        if type(label) ~= "string" or label == "" then label = "CHAIN" end
        Heading(string.format("%s%s%d of %d done", label, SEP, chain.done or 0, chain.total or 0))
        for _, id in ipairs(chain.members or {}) do
            local member = view.byId and view.byId[id]
            if member then
                local current = member == entry
                local top = P.y
                local word, toneKey = StateWord(member)
                Mark(4, StatusToneKey(member))
                local _, height = Line(ToneMarkup(toneKey, word) .. "  " .. member.title, "GameFontHighlightSmall",
                    InkT(current and "strong" or (member.counted and "primary" or "faint")), 4 + MARK_SIZE + 6)
                if current then Band(top - 1, height + 2) end
            end
        end
    end

    -- A line with a row Go at its right (D45) when target() has somewhere
    -- to go; a plain line otherwise
    local function GoLine(text, colour, indent, target, tip)
        local kit = Kit()
        local spec = target and kit.LineGo and target()
        if not spec then return Line(text, "GameFontHighlightSmall", colour, indent) end
        local top = P.y
        local block, height = Line(text, "GameFontHighlightSmall", colour, indent, kit.LINE_GO_W + 6)
        kit.LineGo(W.goLines, P.go, top, target, tip)
        P.go = P.go + 1
        P.y = math.max(P.y, top + kit.LINE_GO_H)
        return block, height
    end

    -- A prerequisite's or a follow-up's Go: to where that quest starts
    -- (one still to do; a done one has nowhere left to send you)
    local function StarterTarget(ref)
        if ref.done or type(ref.id) ~= "number" then return nil end
        return function()
            local adapter = Adapter()
            if not (adapter and adapter.StarterSpec) then return nil end
            return adapter.StarterSpec(ref.id)
        end
    end

    local function StarterTip()
        return "Go to where this quest starts."
    end

    local function LayoutLinks(entry, detail)
        if not detail then return end
        local external = {}
        for _, id in ipairs(entry.externalPrereqs or {}) do external[id] = true end
        local shown = false
        for _, ref in ipairs(detail.prereqs or {}) do
            if external[ref.id] then
                if not shown then
                    Rule()
                    Heading("REQUIRES")
                    shown = true
                end
                GoLine(RefLine(ref), InkT("primary"), 4, StarterTarget(ref), StarterTip)
            end
        end
        if #(detail.followups or {}) > 0 then
            Rule()
            Heading("LEADS TO")
            for _, ref in ipairs(detail.followups) do
                GoLine(RefLine(ref), InkT("primary"), 4, StarterTarget(ref), StarterTip)
            end
        end
    end

    -- In the log: the live objectives with their counts (the Log's own scan
    -- and its detail read). Otherwise Questie's objective text.
    local function LayoutObjectives(entry, detail)
        local logEntry = LogEntryFor(entry)
        if logEntry then
            Rule()
            Heading("OBJECTIVES")
            local logDetail = S.logDetail
            if logDetail and logDetail.objectivesText and logDetail.objectivesText ~= "" then
                Line(logDetail.objectivesText, "GameFontHighlightSmall", InkT("primary"), 4)
            end
            local kit = Kit()
            for index, objective in ipairs(logEntry.objectives or {}) do
                local target, tip
                if not objective.finished and kit.ObjectiveHasPlace and kit.ObjectiveHasPlace(entry.id, index) then
                    target, tip = kit.ObjectiveTarget(entry.id, index), kit.ObjectiveTip(entry.id, index)
                end
                GoLine("\194\183 " .. (objective.text or ""), objective.finished and OBJECTIVE_DONE or OBJECTIVE_OPEN,
                    6, target, tip)
            end
            if logEntry.isComplete then
                Line("Ready to turn in.", "GameFontNormalSmall", ToneT("good"), 4)
            end
            return
        end
        local texts = detail and detail.objectivesText
        if type(texts) == "table" and #texts > 0 then
            Rule()
            Heading("OBJECTIVES")
            for _, text in ipairs(texts) do
                Line(tostring(text), "GameFontHighlightSmall", InkT("primary"), 4)
            end
        end
    end

    local function LayoutReputation(entry, detail)
        if spec.Reputation then
            spec.Reputation(cat, entry, detail)
            return
        end
        local rewards = detail and detail.repRewards
        if not (type(rewards) == "table" and #rewards > 0) then return end
        Rule()
        Heading("REPUTATION")
        for _, reward in ipairs(rewards) do
            Line(string.format("%+d  %s", tonumber(reward.value) or 0, reward.factionName or "a faction"),
                "GameFontHighlightSmall", InkT("secondary"), 4)
        end
    end

    local function LayoutQuest(entry, view)
        local kit = Kit()
        local detail = DetailFor(entry)
        local facts = spec.Facts and spec.Facts(cat, entry, view) or DefaultFacts(entry, view)
        Line(entry.title, "GameFontNormalLarge", kit.InkSet().title)
        Line(table.concat(facts, SEP), "GameFontDisableSmall", InkT("secondary"))
        Line(Reason(entry), "GameFontNormalSmall", ToneT(StatusToneKey(entry)))
        -- What the quest pays straight under its reason when the spec asks
        -- (a chain of thirty would otherwise push it out of the pane), the
        -- spec's own sections with it; else at the end, as 1.5.0 drew it
        local first = spec.reputationFirst
        if type(first) == "function" then first = first(cat) end
        if first then
            LayoutReputation(entry, detail)
            if spec.BriefingSections then spec.BriefingSections(cat, entry, view, detail) end
        end
        LayoutWhere(entry)
        if entry.chain then LayoutChain(entry, view) end
        LayoutLinks(entry, detail)
        LayoutObjectives(entry, detail)
        if not first then
            LayoutReputation(entry, detail)
            if spec.BriefingSections then spec.BriefingSections(cat, entry, view, detail) end
        end
    end

    local function LayoutBriefing()
        local kit = Kit()
        P.y, P.block, P.quad, P.band, P.go = 6, 1, 1, 1, 1
        P.width = kit.DetailWidth() - kit.PAD
        if not S.view then
            LayoutMessage()
        elseif S.selectedEntry then
            LayoutQuest(S.selectedEntry, S.view)
        else
            LayoutOverview(S.view)
        end
        for position = P.block, #W.blocks do W.blocks[position]:Hide() end
        for position = P.quad, #W.quads do W.quads[position]:Hide() end
        for position = P.band, #W.bands do W.bands[position]:Hide() end
        if kit.HideLineGo then kit.HideLineGo(W.goLines, P.go) end
        kit.DetailChild():SetHeight(math.max(P.y + 10, 1))
    end

    -- -----------------------------------------------------------------------
    -- Toolbar, card and action bar state
    -- -----------------------------------------------------------------------

    local function UpdateToolbar()
        local kit, engine = Kit(), Engine()
        local db = DB()
        local ar, ag, ab = kit.InkAccent()
        for key, button in pairs(W.filters) do
            local active = (db[KEYS.filter] or "ALL") == key
            if button.SetNormalFontObject then
                button:SetNormalFontObject(active and GameFontNormalSmall or GameFontDisableSmall)
            end
            -- After the font object, never before (D14's lesson): the swap
            -- re-applies the font's own grey
            local fs = button.GetFontString and button:GetFontString()
            if fs then
                if active then fs:SetTextColor(kit.Ink("strong")) else fs:SetTextColor(kit.Ink("faint")) end
            end
            button.underline:SetVertexColor(ar, ag, ab, active and 0.95 or 0)
        end
        -- Text only. UIDropDownMenu_SetSelectedValue refreshes whatever
        -- dropdown list is OPEN, which on a refresh mid-menu would be the
        -- card's menu; the selected value is set where the player picks it
        -- (PickGroup)
        if engine and UIDropDownMenu_SetText then
            local group = db[KEYS.group] or "GUIDE"
            UIDropDownMenu_SetText(W.groupDrop, GroupLabel(group))
        end
        W.countFS:SetText(S.view and string.format("%d shown", S.shown or 0) or "")
        W.countFS:SetTextColor(kit.Ink("secondary"))
    end

    -- The filters' labels again, after a hover put a font's own colour back
    function Z.RestyleToolbar()
        if W.toolbar and W.toolbar:IsShown() and Kit() then UpdateToolbar() end
    end

    -- With no spec painter: the name, the engine's totals and a bar
    local function DefaultCard(card)
        local kit, engine = Kit(), Engine()
        card.name:SetText(S.keyName or TITLE)
        card.name:SetTextColor(kit.InkAccent())
        local totals = S.view and S.view.totals
        card.totals:SetText((totals and engine) and engine.TotalsText(totals) or "")
        card.totals:SetTextColor(kit.Paper(kit.Ink("primary")))
        card.bar:Hide()
        card.note:SetText("")
    end

    local function UpdateCard()
        local card, kit = W.card, Kit()
        local ar, ag, ab = kit.InkAccent()
        -- The panes' own wash: a thin ink on the paper, half-black elsewhere
        if kit.OnPaper() then
            card.bg:SetVertexColor(0.30, 0.20, 0.08, 0.10)
        else
            card.bg:SetVertexColor(0, 0, 0, 0.4)
        end
        card.rule:SetVertexColor(ar, ag, ab, 0.35)
        if kit.OnPaper() then card.barBg:SetVertexColor(0, 0, 0, 0.14) else card.barBg:SetVertexColor(1, 1, 1, 0.1) end
        if spec.PaintCard then spec.PaintCard(cat, card) else DefaultCard(card) end
    end

    function Z.UpdateActions()
        if not W.actions then return end
        local entry = S.selectedEntry
        for _, action in ipairs(W.actionList) do
            local button, stock = action.button, action.stock
            if stock == "WAYPOINT" then
                if Kit().RefreshGo then
                    Kit().RefreshGo(button, entry ~= nil and WaypointTarget(entry) ~= nil)
                else
                    button:SetEnabled(entry ~= nil and WaypointTarget(entry) ~= nil)
                end
            elseif stock == "MAP" then
                button:SetEnabled(S.view ~= nil and MapFor(entry) ~= nil)
            elseif stock == "LOG" then
                button:SetEnabled(LogEntryFor(entry) ~= nil)
            elseif stock == "IGNORE" then
                button:SetEnabled(entry ~= nil)
                button:SetText((entry and IsIgnored(entry.id)) and "Count" or "Ignore")
            end
            if action.Update then action.Update(cat, button, entry) end
        end
        if spec.UpdateActions then spec.UpdateActions(cat) end
    end

    -- -----------------------------------------------------------------------
    -- The model pass
    -- -----------------------------------------------------------------------

    -- The Log's scan, keyed the way catalogue entries are ("id:9003"), so a
    -- row knows whether its quest is in the log and can borrow its live
    -- objectives
    local function IndexLog(entries)
        local byKey = {}
        for _, entry in ipairs(entries or {}) do
            if not entry.isHeader and entry.key then byKey[entry.key] = entry end
        end
        S.logByKey = byKey
    end

    -- Group, then list: nothing may regroup in between (see the file header)
    local function GroupAndList(view)
        local engine, db = Engine(), DB()
        local filter = db[KEYS.filter] or "ALL"
        local mode = db[KEYS.group] or "GUIDE"
        local opts = { playerPos = S.playerPos }
        local list
        if spec.Group then list = spec.Group(cat, view, mode, opts) end
        if list == nil then list = engine.Group(view, mode, opts) end
        local passes = spec.PassesFilter
        return Q.BuildList(list, {
            search = S.search,
            -- entry.header is a group here ("Pick up now", "Done"), not a
            -- zone: "pick" would list a whole group whose titles never say it
            matchHeader = false,
            sort = "LOG",
            collapsed = db[KEYS.collapsed] or {},
            predicate = function(entry)
                if passes then
                    local verdict = passes(cat, entry, filter)
                    if verdict ~= nil then return verdict end
                end
                return engine.PassesFilter(entry, filter)
            end,
        })
    end

    -- The Log's detail read for a quest that is in the log (its objective
    -- summary). Q.ReadDetail puts back a selection it found, but one it found
    -- EMPTY it leaves on the quest it read -- harmless on the Log, which
    -- selects the briefed quest anyway for its reward tooltips, and wrong
    -- here, where the client's selection is not this tab's to move (D2). So
    -- an empty one is emptied again.
    local function ReadLogDetail(logEntry)
        if not (logEntry and logEntry.index and Q.ReadDetail) then return nil end
        local before = GetQuestLogSelection and GetQuestLogSelection() or nil
        local detail = Q.ReadDetail(logEntry.index)
        if before == 0 and SelectQuestLogEntry and GetQuestLogSelection and GetQuestLogSelection() ~= 0 then
            SelectQuestLogEntry(0)
        end
        return detail
    end

    local function FindSelected()
        for _, item in ipairs(S.rows) do
            if item.entry and item.entry.id == S.selectedId then return item.entry end
        end
        return nil
    end

    -- A quest asked for by name that the search, the filter or a fold has
    -- taken off the list: clear the search, open the filter, unfold its group
    local function Reveal(view)
        local entry = view.byId and view.byId[S.selectedId]
        if not entry then return end
        local db = DB()
        S.search = ""
        local frame = Kit().Frame()
        if frame and frame.searchBox then frame.searchBox:SetText("") end
        db[KEYS.filter] = "ALL"
        if entry.header and type(db[KEYS.collapsed]) == "table" then db[KEYS.collapsed][entry.header] = nil end
        S.rows, S.shown = GroupAndList(view)
        S.selectedEntry = FindSelected()
    end

    local function BuildRows()
        local adapter = Adapter()
        local key, name = spec.Resolve(cat)
        if key ~= S.key then
            S.key = key
            S.selectedId = nil
            S.detailCache = nil
            local scroll = Kit().NavScroll()
            if scroll and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
        end
        if S.pendingSelect then
            S.selectedId = S.pendingSelect
            S.pendingSelect = nil
        end
        S.keyName = name
        if not key then return end

        local view, err = spec.View(cat, key)
        S.view, S.err = view, err
        if not view then
            if spec.KeyName then S.keyName = spec.KeyName(cat, key, S.keyName) end
            return
        end
        S.keyName = view.name or name
        S.char = adapter.Character and adapter.Character() or {}
        S.playerPos = spec.PlayerPos and spec.PlayerPos(cat, key) or nil

        S.rows, S.shown = GroupAndList(view)
        -- The selection has to be a row that is on screen (D6). The overview
        -- is the briefing with nothing selected, so a selection that went out
        -- of view falls back to it rather than to the first row.
        if S.selectedId then
            S.selectedEntry = FindSelected()
            if not S.selectedEntry and S.reveal then Reveal(view) end
            if not S.selectedEntry then S.selectedId = nil end
        end
        S.reveal = false

        S.logDetail = ReadLogDetail(LogEntryFor(S.selectedEntry))
    end

    local function SetOwnWidgetsShown(shown)
        if W.toolbar then W.toolbar:SetShown(shown) end
        if W.card then W.card:SetShown(shown) end
        if W.actions then W.actions:SetShown(shown) end
    end

    -- The tab's pass. UI.lua's Q.Refresh has scanned the log (entries) and
    -- put the other tabs' widgets away; this draws everything else.
    function Z.Refresh(entries)
        local kit = Kit()
        local frame = kit and kit.Frame()
        if not frame then return end
        EnsureBuilt(frame)
        SetOwnWidgetsShown(true)
        IndexLog(entries)

        S.state, S.reason = AdapterState()
        S.view, S.err, S.rows, S.shown = nil, nil, {}, 0
        S.selectedEntry, S.logDetail, S.char, S.playerPos = nil, nil, nil, nil
        -- A quest asked for by name is brought into view as well as revealed
        local scrollTo = S.reveal
        if S.state == "READY" then
            BuildRows()
        else
            S.keyName = nil
            S.reveal = false
        end

        LayoutRows()
        if scrollTo and S.selectedEntry and kit.ScrollIntoView then
            kit.ScrollIntoView(kit.NavScroll(), kit.NavChild(), S.selectedTop, S.selectedHeight)
        end
        LayoutBriefing()
        UpdateToolbar()
        UpdateCard()
        Z.UpdateActions()
    end

    -- Everything this tab drew, put away for another tab
    function Z.HideAll()
        SetOwnWidgetsShown(false)
        for _, row in ipairs(W.rows) do row:Hide() end
        if W.emptyFS then W.emptyFS:Hide() end
        for _, block in ipairs(W.blocks) do block:Hide() end
        for _, quad in ipairs(W.quads) do quad:Hide() end
        for _, band in ipairs(W.bands) do band:Hide() end
        for _, button in ipairs(W.goLines) do button:Hide() end
    end

    -- -----------------------------------------------------------------------
    -- Search, selection and opening from elsewhere
    -- -----------------------------------------------------------------------

    function Z.SetSearch(text)
        S.search = text or ""
    end

    function Z.SearchText()
        return S.search
    end

    -- Escape clears the search; pressed again on an empty search it goes
    -- back to the overview
    function Z.EscapeSearch()
        if S.search == "" then S.selectedId = nil end
        S.search = ""
    end

    -- The briefed quest (an engine entry), or nil on the overview
    function Z.Selected()
        return S.selectedEntry
    end

    function Z.Select(questId)
        S.selectedId = tonumber(questId)
        Q.Refresh()
    end

    -- Called before the window switches to this tab. key nil follows; a
    -- number pins it. Answers false when the tab is switched off.
    function Z.PrepareOpen(key, questId)
        local db = DB()
        if SHOW_KEY and db[SHOW_KEY] == false then
            print(spec.offMessage or ("Commander Quest Log: the " .. TITLE .. " tab is switched off in the settings."))
            return false
        end
        if type(key) == "number" then
            db[KEYS.follow] = false
            db[KEYS.picked] = key
        else
            db[KEYS.follow] = true
            db[KEYS.picked] = false
        end
        S.pendingSelect = tonumber(questId)
        S.reveal = S.pendingSelect ~= nil
        if not S.pendingSelect then S.selectedId = nil end
        return true
    end

    -- -----------------------------------------------------------------------
    -- Following: the spec's events move the followed key, which only matters
    -- to a tab that is up and following. Through the window's own
    -- one-pass-per-frame queue (D10).
    -- -----------------------------------------------------------------------

    if CreateFrame and spec.followEvents and #spec.followEvents > 0 then
        local events = CreateFrame("Frame")
        for _, event in ipairs(spec.followEvents) do events:RegisterEvent(event) end
        events:SetScript("OnEvent", function()
            if Z.IsActive() and DB()[KEYS.follow] ~= false and Q.QueueRefresh then Q.QueueRefresh() end
        end)
    end

    -- -----------------------------------------------------------------------
    -- The context's reach (see the file header)
    -- -----------------------------------------------------------------------

    cat.Line, cat.Heading, cat.Bar, cat.Rule, cat.Mark, cat.Band = Line, Heading, Bar, Rule, Mark, Band
    cat.Follow, cat.Pick, cat.OpenMenu = Follow, Pick, OpenMenu
    cat.SendWaypoint, cat.ShowOnMap, cat.OpenInLog, cat.ToggleIgnore = SendWaypoint, ShowOnMap, OpenInLog, ToggleIgnore
    cat.LogEntryFor, cat.WaypointTarget, cat.DetailFor = LogEntryFor, WaypointTarget, DetailFor
    cat.StateWord, cat.Reason, cat.DefaultFacts = StateWord, Reason, DefaultFacts

    -- -----------------------------------------------------------------------
    -- The window's register (UI.lua's Q.RegisterTab): this tab's button, its
    -- switch, its pass, its search and its way in. Late-bound through Z, so
    -- whatever replaces one of Z's functions is what the window calls.
    -- -----------------------------------------------------------------------

    Z.tab = {
        id = spec.id, order = spec.order or 50, label = spec.label or spec.id,
        width = spec.width, tooltip = spec.tooltip, instance = Z,
        IsEnabled = function() return not SHOW_KEY or DB()[SHOW_KEY] ~= false end,
        Refresh = function(entries) Z.Refresh(entries) end,
        HideAll = function() Z.HideAll() end,
        SearchText = function() return Z.SearchText() end,
        SetSearch = function(text) Z.SetSearch(text) end,
        EscapeSearch = function() Z.EscapeSearch() end,
        NavTopInset = function() return Z.NavTopInset() end,
        PrepareOpen = function(key, questId) return Z.PrepareOpen(key, questId) end,
        SearchTip = spec.searchTip or "Matches a quest's name, in the list on the card.",
    }
    if spec.register ~= false and Q.RegisterTab then Q.RegisterTab(Z.tab) end

    -- The tab buttons are the window's now; these two are kept so nothing
    -- that called them on the Zones tab breaks
    function Z.UpdateTabs()
        if Q.UpdateTabs then Q.UpdateTabs() end
    end
    Z.EnsureTabs = Z.UpdateTabs

    -- Harness accessors. Nothing in the game reads these.
    function Z._Widgets() return W end
    function Z._State() return S end
    function Z._Context() return cat end

    return Z
end

Q.NewCatalogue = C.New

-- ---------------------------------------------------------------------------
-- Events
--
-- The adapter's generation listener is the one signal that Questie's answer
-- changed (a turn-in, a level, a reputation tick, an Ignore, a setting); it
-- refreshes whichever tab is up, because the Log's "Turn in:" line reads
-- Questie too. One listener for every catalogue: the window's own queue
-- draws one pass per frame (D10) whichever tab asked.
-- ---------------------------------------------------------------------------

local function OnGeneration()
    if Q.QueueRefresh then Q.QueueRefresh() end
end

if CreateFrame then
    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_LOGIN")
    events:SetScript("OnEvent", function()
        local adapter = Adapter()
        if adapter and adapter.AddListener then adapter.AddListener(OnGeneration) end
    end)
end

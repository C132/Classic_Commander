-- Commander Quest Log: the Zones tab.
--
-- The second tab of the quest log window. Pick a zone -- or let it follow you
-- -- and see every quest it holds for this character: a completion bar
-- ("62 / 90 · 69%"), what is done, what is open, what is locked and why,
-- what has been missed for good and why, and the chains in order. With
-- nothing selected the briefing is the zone's overview and a short "what next"
-- list; with a quest selected it is that quest's briefing: where it starts and
-- ends, where it sits in its chain, what it needs. Every number and every word
-- comes from the completion engine (CommanderQuestLogCompletion.lua) over
-- facts the Questie adapter (CommanderQuestLogQuestie.lua) reads.
--
-- The machinery -- toolbar set, card, navigator rows, briefing pools, action
-- bar, search, folds, reveal, ink on the paper -- is the catalogue's
-- (CommanderQuestLogCatalogue.lua), which every tab of this kind shares; this
-- file is one instance of it and only says what is particular to a ZONE:
-- which zone (where you stand, or the one pinned), Questie's categories as
-- the picker, the completion card, the zone overview (completion, next up,
-- chains, missed), Show on Map at this zone, and a nearest-first route
-- through every open quest's giver. Why a tab of its own, with widgets of its
-- own, rather than a mode of the Log: see D30, and the catalogue's header for
-- why the Zones and Reputations tabs are instances rather than modes.
--
-- The names the rest of the module and the harness know are kept: Q.Zones,
-- its public functions, the two named dropdowns
-- (CommanderQuestLogZoneGroupDrop, CommanderQuestLogZoneMenu), the DB keys
-- (ZoneFilter, ZoneGroup, ZoneCollapsed, ZoneFollow, ZonePicked, ShowZoneTab)
-- and the state's areaId / areaName.
--
-- Reputation (1.6.0): every quest here says what it is worth -- a badge on
-- its row ("+275 HH", the faction named), the full effects in its briefing
-- (straight under its reason), a line in its tooltip -- and the overview
-- says, per faction and right under the zone's completion, what 100%-ing the
-- zone would still pay and whether that reaches the next standing. Every
-- number is the rules engine's (CommanderQuestLogStanding.lua) through the
-- adapter, the same one the Log, the Reputations tab, the map drawer, a
-- waypoint's note and the NPC's own dialog show; see the Reputation section
-- below.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local C = Q.Catalogue
-- A catalogue that failed to load leaves the window with its Log alone
if not (C and C.New) then return end

local Kit, Engine, Adapter, DB = C.Kit, C.Engine, C.Adapter, C.DB
local InkT, ToneMarkup, GiverName = C.InkT, C.ToneMarkup, C.GiverName
local BreakdownText, UncountedText = C.BreakdownText, C.UncountedText
local SEP, DASH = C.SEP, C.DASH

-- The tab button's width: "Zones" in GameFontNormalSmall, the Log's 58
local TAB_W = 58
local EMPTY = {}

-- ---------------------------------------------------------------------------
-- Which zone
-- ---------------------------------------------------------------------------

-- Following: wherever the player stands (nil in a spot that resolves to no
-- quest zone). Pinned: the zone picked, an AREA id.
local function ResolveZone()
    local adapter = Adapter()
    local db = DB()
    if db.ZoneFollow ~= false then
        if adapter and adapter.ZoneForPlayer then
            local areaId, name = adapter.ZoneForPlayer()
            if areaId then return areaId, name end
        end
        return nil, nil
    end
    local picked = tonumber(db.ZonePicked)
    if picked and picked ~= 0 then
        return picked, (adapter and adapter.ZoneName) and adapter.ZoneName(picked) or ("Zone " .. picked)
    end
    return nil, nil
end

-- The zone's open quests as one Commander Orders route, nearest first (the
-- adapter builds it and says how it went)
local function RouteZone(cat)
    local adapter = Adapter()
    if not (adapter and adapter.RouteOpen and cat.S.key) then return nil end
    return adapter.RouteOpen(cat.S.key)
end

-- How many givers a route through the shown zone would visit (0: none)
local function RouteStopCount(cat)
    local adapter = Adapter()
    local S = cat.S
    if not (adapter and adapter.RouteStops and S.view and S.key) then return 0 end
    return #(adapter.RouteStops(S.key) or {})
end

-- ---------------------------------------------------------------------------
-- The zone menu
--
-- "Where I am" first, then Questie's own categories with each one's zones a
-- level down (paged by the catalogue where a category outruns a screen), a
-- percentage beside every zone whose summary is known. Opening a category
-- asks the adapter to work out the rest in the background (one zone per
-- tick); an open dropdown cannot be redrawn in place, so they show the next
-- time it opens.
-- ---------------------------------------------------------------------------

-- One stable callback, so a second request for the menu's summaries replaces
-- the first job in the adapter instead of queueing behind it
local function MenuSummaryArrived() end

local function ZoneMenuText(zone)
    local adapter, engine = Adapter(), Engine()
    local summary = adapter and adapter.ZoneSummary and adapter.ZoneSummary(zone.areaId, true)
    if summary and summary.pct and engine then
        return zone.name .. "  " .. engine.PercentText(summary.pct)
    end
    return zone.name
end

local function ZoneMenuInit(cat, level, menuList)
    level = level or 1
    local adapter = Adapter()
    local db = DB()
    if level == 1 then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Where I am"
        info.checked = db.ZoneFollow ~= false
        info.func = cat.Follow
        UIDropDownMenu_AddButton(info, level)
        local menu = adapter and adapter.ZoneMenu and adapter.ZoneMenu() or {}
        cat.S.menu = menu
        for _, category in ipairs(menu) do cat.AddCategoryPages(category) end
        return
    end
    local page = type(menuList) == "table" and menuList or nil
    local key = page and page.key or menuList
    local picked = db.ZoneFollow == false and tonumber(db.ZonePicked) or nil
    for _, category in ipairs(cat.S.menu or {}) do
        if category.key == key then
            local zones = category.zones or {}
            local ids = {}
            for index = (page and page.first or 1), (page and page.last or #zones) do
                local zone = zones[index]
                if zone then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = ZoneMenuText(zone)
                    info.checked = picked == zone.areaId
                    info.arg1 = zone.areaId
                    info.func = cat.Pick
                    UIDropDownMenu_AddButton(info, level)
                    ids[#ids + 1] = zone.areaId
                end
            end
            if adapter and adapter.RequestSummaries and #ids > 0 then
                adapter.RequestSummaries(ids, MenuSummaryArrived)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The card: name and totals, a completion bar, and whether it follows you
-- ---------------------------------------------------------------------------

local function CardTooltip(cat, owner)
    local engine = Engine()
    local S = cat.S
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(S.keyName or "Zones", 1, 1, 1)
    if S.view and engine then
        GameTooltip:AddLine(engine.TotalsText(S.view.totals) .. " of the quests that count here.", 0.85, 0.85, 0.85)
    end
    GameTooltip:AddLine(DB().ZoneFollow ~= false and "Following the zone you are in."
        or "Pinned to this zone.", 0.7, 0.7, 0.75)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to pick a zone, or to go back to this one's overview. Right-click to follow the zone you are standing in.",
        0.55, 0.55, 0.6, true)
    GameTooltip:Show()
end

local function PaintCard(cat, card)
    local kit, engine = Kit(), Engine()
    local S = cat.S
    card.name:SetText(S.keyName or "Zones")
    card.name:SetTextColor(kit.InkAccent())
    local totals = S.view and S.view.totals
    card.totals:SetText((totals and engine) and engine.TotalsText(totals) or "")
    card.totals:SetTextColor(kit.Paper(kit.Ink("primary")))

    local span = (card:GetWidth() or 0) - 16
    if span <= 0 then span = kit.NAV_W - 16 end
    local pct = totals and totals.pct or 0
    if pct > 0 then
        card.bar:SetWidth(math.max(1, span * math.min(pct, 1)))
        local r, g, b = kit.InkAccent()
        card.bar:SetVertexColor(r, g, b, 0.9)
        card.bar:Show()
    else
        card.bar:Hide()
    end

    card.note:SetText(DB().ZoneFollow ~= false and "Following you. Click to pick a zone."
        or "Pinned. Click to change; right-click to follow you.")
    card.note:SetTextColor(kit.Paper(kit.Ink("faint")))
end

-- ---------------------------------------------------------------------------
-- The overview: nothing selected
-- ---------------------------------------------------------------------------

-- The overview's REPUTATION IN THIS ZONE (the Reputation section below)
local ZoneReputation

local function PaintOverview(cat, view)
    local kit, engine = Kit(), Engine()
    local S, Line, Heading, Bar, Rule = cat.S, cat.Line, cat.Heading, cat.Bar, cat.Rule
    local totals = view.totals or {}

    Line(view.name or S.keyName or "", "GameFontNormalLarge", kit.InkSet().title)
    Line(string.format("%d of %d quests done%s%s", totals.done or 0, totals.counted or 0, SEP,
        engine.PercentText(totals.pct)), "GameFontHighlight", InkT("primary"))
    Bar(0, C.TOTAL_BAR_H, totals.pct or 0)
    Line(BreakdownText(totals), "GameFontHighlightSmall", InkT("secondary"))
    Line(UncountedText(totals), "GameFontDisableSmall", InkT("faint"))

    -- "Can 100%-ing this zone get me there" is answered up front, under the
    -- zone's own completion: a pane is 410 px, and the chains below it fill
    -- that on their own in a zone like Hellfire
    if ZoneReputation then ZoneReputation(cat) end

    Rule()
    Heading("NEXT UP")
    local nextUp = engine.NextUp(view, C.NEXT_UP_COUNT, { playerPos = S.playerPos })
    if #nextUp == 0 then
        local finished = (totals.counted or 0) > 0 and totals.done == totals.counted
        Line(finished and "Every quest that counts here is done." or "Nothing to pick up or hand in here right now.",
            "GameFontHighlightSmall", InkT("faint"), 4)
    end
    for _, entry in ipairs(nextUp) do
        local word, toneKey = cat.StateWord(entry)
        local giver = GiverName(entry)
        Line(ToneMarkup(toneKey, word) .. "  " .. entry.title .. (giver and (DASH .. giver) or ""),
            "GameFontHighlightSmall", InkT("primary"), 4)
    end

    local chains = {}
    for _, chain in ipairs(view.chains or {}) do
        if (chain.total or 0) > 0 then chains[#chains + 1] = chain end
    end
    if #chains > 0 then
        Rule()
        Heading("CHAINS")
        for _, chain in ipairs(chains) do
            local finished = chain.done >= chain.total
            Line(string.format("%s  %d/%d", chain.title or ("Quest " .. chain.id), chain.done, chain.total),
                "GameFontHighlightSmall", InkT(finished and "secondary" or "primary"), 4)
            Bar(4, C.CHAIN_BAR_H, chain.done / chain.total, 4)
        end
    end

    local missed = {}
    for _, entry in ipairs(view.entries or {}) do
        if entry.status == "MISSED" then missed[#missed + 1] = entry end
    end
    if #missed > 0 then
        Rule()
        Heading("MISSED")
        for _, entry in ipairs(missed) do
            Line(entry.title .. DASH .. cat.Reason(entry), "GameFontHighlightSmall", InkT("secondary"), 4)
        end
    end
end

-- The navigator's sentence once Questie has answered
local function EmptyMessage(cat)
    local S = cat.S
    if not S.key then return "No quest zone here. Pick one from the card above." end
    if S.err == "NO_QUESTS" then
        return "Questie lists no quests for " .. (S.keyName or "this zone") .. ". Pick another zone from the card above."
    end
    if not S.view then
        return "This zone could not be read (" .. tostring(S.err or "no answer") .. "). /cql status has the detail."
    end
    return "Nothing in " .. (S.keyName or "this zone") .. " matches this search and filter."
end

-- ---------------------------------------------------------------------------
-- Reputation (1.6.0)
--
-- The brief that started it: a player 100%-ing Hellfire for a faction found
-- out quest by quest that some paid next to nothing and some paid nothing at
-- all. So every quest here carries its worth where it is seen -- a badge on
-- the row (the biggest direct gain and whose it is, "+275 HH"; "0" for none
-- or capped), the whole effect list in the briefing (direct, spillover, the
-- rival's loss, every cap and why, what was seen in game), a line in the
-- row's tooltip -- and the overview answers the real question up front: per
-- faction, what is still to be had here once, what was had, and whether it
-- reaches the next standing and how far short of Exalted it leaves you (the
-- engine's ordered projection, not a sum: gates close as a standing rises).
--
-- The traps:
--
--   * One number. Every figure is the adapter's (A.RepEffects / A.RepLine /
--     A.ZoneRepTotals over the rules engine), cached by it per generation and
--     shared: the badge, the tooltip and the briefing read the very table the
--     Log, the map drawer, a waypoint's note and the NPC dialog read. Never
--     Questie's GetReputationReward, and never a sum done here. What is left
--     and what spills in are the PROJECTION's (its order, its unreached, its
--     spill window's landed), never the zone totals' raw sums: a spill window
--     shuts at its standing, and the Aldor and the Scryers are one choice.
--   * The badge names its faction. "+550" alone made Missing Missive (Cenarion
--     Circle) look like Hellfire's best Honor Hold quest; "+550 CC" does not.
--   * Without the rules (the data file or the engine failed to load) there is
--     no number to give: no badge, no tooltip line, no zone section, and the
--     briefing keeps the stock section -- Questie's raw rows, as 1.5.0 drew
--     them -- rather than lose the faction names too. Reputation on Every
--     Quest switched off is the same: the briefing goes back to 1.5.0's.
--   * A dim title means "does not count toward 100%" on this tab. A quest
--     capped to 0 still counts, so its badge is faint and its title is not.
--   * The Wanted dailies rotate: one normal and one heroic a day, out of
--     every dungeon's. They are never a zone's daily income, and a figure
--     for its dailies is the best one OPEN to you now (a level-70 heroic
--     daily is no headline for a level-64 in Hellfire).
--   * BYREP groups by each quest's primary faction, headed by the faction's
--     own (localised) name, which is the fold key. The engine's rule holds:
--     Group writes entry.header (through cat.Emit) and nothing regroups
--     before BuildList.
--   * The zone section's totals are worked out once per zone per generation:
--     the overview is redrawn on every log tick, a projection is not free.
--   * The REPUTATION section is the Reputations tab's too (Z.PaintReputation,
--     with that tab's faction in the strong ink): the same quest reads the
--     same, in the same words, on both tabs.
-- ---------------------------------------------------------------------------

local OBSERVED_WORDS = "seen in game"
local ORDER_HINTS_SHOWN = 3
local FACTION_GAP = 4           -- extra space above each faction after the first in the zone section

local function Rules()
    local R = Q.Standing
    if type(R) == "table" and type(R.Primary) == "function" and type(R.FormatRep) == "function" then return R end
    return nil
end

-- The adapter's answer to "are the rules loaded" (the multiplier needs both
-- the engine and the generated data)
local function RulesLoaded()
    local adapter = Adapter()
    return Rules() ~= nil and adapter ~= nil and adapter.RepMultiplier ~= nil and adapter.RepMultiplier() ~= nil
end

local function RepWanted()
    return DB().ShowRepEverywhere ~= false
end

-- The briefing puts what a quest pays right under its reason while there is
-- a number to give; otherwise it is 1.5.0's briefing, raw rows at the end
local function ReputationFirst()
    return RepWanted() and RulesLoaded()
end

-- The generated data's Wanted kind of a quest ("NORMAL" | "HEROIC"), or nil
local function RotatingKind(questId)
    local D = CommanderQuestLogReputationData
    local rotating = type(D) == "table" and type(D.rotating) == "table" and D.rotating or nil
    return rotating and rotating[questId] or nil
end

local function FactionName(factionId)
    local adapter = Adapter()
    local name = adapter and adapter.FactionName and adapter.FactionName(factionId)
    if type(name) == "string" and name ~= "" then return name end
    return "Faction " .. tostring(factionId)
end

-- The client's standing words by standingID (GetText picks her form), with
-- the engine's English where the client has none
local labels
local function Labels()
    if labels then return labels end
    local out, sex = {}, nil
    if UnitSex then
        local ok, value = pcall(UnitSex, "player")
        if ok then sex = value end
    end
    for n = 1, 8 do
        local token, text = "FACTION_STANDING_LABEL" .. n, nil
        if GetText then
            local ok, value = pcall(GetText, token, sex)
            if ok then text = value end
        end
        if type(text) ~= "string" or text == "" then text = _G[token] end
        if type(text) == "string" and text ~= "" then out[n] = text end
    end
    labels = out
    return out
end

local function AnyObserved(effects)
    for _, effect in ipairs(effects or EMPTY) do
        if type(effect) == "table" and effect.observed then return true end
    end
    return false
end

-- "Reputation: +275 Honor Hold", or "No reputation", plus the calibration's
-- word when what is shown was seen in game
local function RepPhrase(line, effects)
    local R = Rules()
    local text = (R and line == R.NO_REPUTATION) and line or ("Reputation: " .. line)
    if AnyObserved(effects) then text = text .. " (" .. OBSERVED_WORDS .. ")" end
    return text
end

-- The row badge: the biggest direct gain and the faction it is for ("+275
-- HH"), "0" for a quest that pays nothing (or nothing more: capped). nil
-- without the rules or with it switched off.
local function RowRight(cat, entry)
    local db = DB()
    if db.ShowRepEverywhere == false or db.ZoneRowRep == false then return nil end
    local R = Rules()
    local effects = type(entry.fact) == "table" and entry.fact.repEffects or nil
    if not (R and type(effects) == "table") then return nil end
    local factionId, delta = R.Primary(effects)
    if not factionId or delta == 0 then return "0", "faint" end
    local tag = C.RepTag and C.RepTag(cat and cat.S.view, factionId) or nil
    -- held to what the 64-px badge shows whole ("+1000 Scry", not "+1,000 Sc...")
    local text = C.RepBadgeText and C.RepBadgeText(R, delta, tag) or (R.FormatRep(delta) .. (tag and (" " .. tag) or ""))
    if delta > 0 then return text, { Kit().Accent() } end
    return text, "bad"
end

-- The tooltip is the game's dark one whatever the sheet: a light literal, as
-- every other line of it, never the sheet's ink (dark brown on parchment)
local function RowTooltip(_, entry)
    if not RepWanted() then return end
    local adapter = Adapter()
    if not (adapter and adapter.RepLine) then return end
    local line, effects = adapter.RepLine(entry.id)
    if not line then return end
    GameTooltip:AddLine(RepPhrase(line, effects), 0.85, 0.85, 0.85, true)
end

-- One effect in words: "+137 The Sha'tar  ·  spillover, spillover stops at 8,999"
local function EffectText(R, effect)
    local text = R.FormatRep(effect.delta) .. " " .. FactionName(effect.factionId)
    local notes = {}
    if effect.kind == "SPILL" then
        notes[#notes + 1] = "spillover"
    elseif effect.kind == "RIVAL" then
        notes[#notes + 1] = "rival"
    end
    if effect.capNote then notes[#notes + 1] = effect.capNote end
    if effect.extra then
        notes[#notes + 1] = "seen in game only"
    elseif effect.observed then
        notes[#notes + 1] = OBSERVED_WORDS
    end
    if effect.unknown then notes[#notes + 1] = "standing not known" end
    if #notes > 0 then text = text .. SEP .. table.concat(notes, ", ") end
    return text
end

-- A loss in the bad tone, nothing in the faint ink; the faction a tab is
-- about (emphasis) in the strong ink, the rest of the direct gains primary
local function EffectColour(effect, emphasis)
    if effect.delta < 0 then return C.ToneT("bad") end
    if effect.delta == 0 then return InkT("faint") end
    if emphasis and effect.factionId == emphasis then return InkT("strong") end
    if effect.kind == "DIRECT" then return InkT("primary") end
    return InkT("secondary")
end

-- "Paid at 110% (Diplomacy)." when the multiplier is not 100
local function MultiplierNote(effects)
    local pct = tonumber(effects.pct)
    if not pct or pct == 100 then return nil end
    local adapter = Adapter()
    local mods
    if adapter and adapter.RepMultiplier then mods = select(2, adapter.RepMultiplier()) end
    local why = {}
    if type(mods) == "table" and mods.human then why[#why + 1] = "Diplomacy" end
    if type(mods) == "table" and mods.wickerman then why[#why + 1] = "Invocation of the Wickerman" end
    return string.format("Paid at %d%%%s.", pct, #why > 0 and (" (" .. table.concat(why, ", ") .. ")") or "")
end

-- The quest briefing's REPUTATION: every effect, a capped one with its
-- reason, a spill that a window keeps shut too ("no spillover above
-- Friendly"), and "No reputation" for a quest that moves nothing. Also the
-- Reputations tab's (Z.PaintReputation), so opts: emphasis (a faction id,
-- in the strong ink) and always (drawn whatever Reputation on Every Quest
-- says: on the Reputations tab reputation is the point).
local function Reputation(cat, entry, detail, opts)
    local R = Rules()
    local always = type(opts) == "table" and opts.always
    local emphasis = type(opts) == "table" and opts.emphasis or nil
    local effects = detail and detail.repEffects
    if type(effects) ~= "table" then effects = entry and type(entry.fact) == "table" and entry.fact.repEffects or nil end
    -- switched off: 1.5.0's section, Questie's raw rows, whatever the rules
    if not always and not RepWanted() then effects = nil end
    if not (R and type(effects) == "table") then
        local rewards = detail and detail.repRewards
        if not (type(rewards) == "table" and #rewards > 0) then
            if always then
                cat.Rule()
                cat.Heading("REPUTATION")
                cat.Line("Not known: the reputation rules are not loaded.", "GameFontHighlightSmall", InkT("faint"), 4)
            end
            return
        end
        cat.Rule()
        cat.Heading("REPUTATION")
        for _, reward in ipairs(rewards) do
            cat.Line(string.format("%+d  %s", tonumber(reward.value) or 0, reward.factionName or "a faction"),
                "GameFontHighlightSmall", InkT("secondary"), 4)
        end
        return
    end
    cat.Rule()
    cat.Heading("REPUTATION")
    local shown, overridden = 0, false
    for _, effect in ipairs(effects) do
        if type(effect) == "table" and tonumber(effect.delta)
            and (effect.delta ~= 0 or effect.kind == "DIRECT" or effect.capNote) then
            shown = shown + 1
            local mine = emphasis ~= nil and effect.factionId == emphasis and effect.delta >= 0
            cat.Line(EffectText(R, effect), mine and "GameFontNormalSmall" or "GameFontHighlightSmall",
                EffectColour(effect, emphasis), 4)
            if effect.overridden then overridden = true end
        end
    end
    if shown == 0 then cat.Line(R.NO_REPUTATION, "GameFontHighlightSmall", InkT("faint"), 4) end
    if overridden then
        cat.Line("Corrected from Wowhead's record of this quest, which the quest data misses.",
            "GameFontDisableSmall", InkT("faint"), 4)
    end
    local note = MultiplierNote(effects)
    if note then cat.Line(note, "GameFontDisableSmall", InkT("faint"), 4) end
end

-- ---- the overview's REPUTATION IN THIS ZONE ---------------------------------

local totalsCache = {}
local function ZoneTotals(areaId)
    local adapter = Adapter()
    if not (adapter and adapter.ZoneRepTotals and areaId) then return EMPTY end
    local generation = adapter.generation or 0
    if totalsCache.key ~= areaId or totalsCache.generation ~= generation then
        totalsCache.key, totalsCache.generation = areaId, generation
        totalsCache.totals = adapter.ZoneRepTotals(areaId) or EMPTY
    end
    return totalsCache.totals
end

local function Plural(count, word)
    return count .. " " .. word .. (count == 1 and "" or "s")
end

-- What the projection made of the zone's once-only quests: how many it does
-- in the best order, how many wait on a standing it never reaches, and what
-- its spill window actually LANDS from the one source it chose -- read from
-- the projection itself, so a totals table whose own sums are raw (a spill
-- summed over both rival sources, past where the window shuts; a count of
-- every quest, reachable or not) can never put them on screen
local function Projected(t)
    local projection = type(t.projection) == "table" and t.projection or EMPTY
    local doing = type(projection.order) == "table" and #projection.order or (t.leftCount or 0)
    local unreached = type(projection.unreached) == "table" and #projection.unreached or 0
    local window = type(projection.spillWindow) == "table" and projection.spillWindow or nil
    return doing, unreached, window and tonumber(window.landed) or 0, window
end

-- What is still to be had here, once: "+385 left in 2 quests", and how much
-- of it is the dungeon quests that start here (extraLeft: a zone's 100%
-- leaves them out, its reputation does not)
local function LeftText(R, t)
    local left = t.remainingOnce or 0
    local doing, unreached, landed = Projected(t)
    if doing > 0 and left <= 0 then
        -- the projection does them, but each pays 0 from here (a reward
        -- clamp): never "0 left in 13 quests"
        return Plural(doing, "quest") .. " left, none pays anything more"
    elseif doing > 0 then
        local text = R.FormatRep(left) .. " left in " .. Plural(doing, "quest")
        if landed > 0 and left > 0 then text = text .. ", spillover included" end
        local dungeons = tonumber(t.extraLeft) or 0
        if dungeons > 0 then text = text .. (landed > 0 and "; " or ", ") .. R.FormatRep(dungeons) .. " of it in dungeons" end
        return text
    elseif left > 0 then
        return R.FormatRep(left) .. " left by spillover"
    elseif unreached > 0 then
        return "Nothing within reach yet"
    end
    return "No one-time quest left"
end

-- The quests here that pay it but want a standing the quests here never
-- reach (Sporeggar's two at Friendly): counted apart, never as "0 left"
local function UnreachedLine(cat, t)
    local doing, unreached = Projected(t)
    if unreached <= 0 then return end
    local text
    if doing > 0 or (t.remainingOnce or 0) > 0 then
        text = unreached == 1 and "1 more needs a standing the quests here alone do not reach."
            or (unreached .. " more need a standing the quests here alone do not reach.")
    else
        text = unreached == 1 and "1 quest here needs a standing the quests here alone do not reach."
            or (unreached .. " quests here need a standing the quests here alone do not reach.")
    end
    cat.Line(text, "GameFontHighlightSmall", InkT("faint"), 12)
end

-- Whether 100%-ing the zone gets there: the projection's reach against the
-- next standing, and what that leaves short of Exalted
local function VerdictLine(cat, R, t)
    local words = Labels()
    if (t.remainingOnce or 0) <= 0 or not t.reach then return end
    if (t.value or 0) >= (tonumber(R.EXALTED) or 42000) then
        -- what is left only fills Exalted's bar: never "Quests here reach
        -- Exalted" for a faction that is (the Reputations tab's own words)
        cat.Line("Already " .. (R.StandingWord(7, words) or "Exalted") .. ".", "GameFontHighlightSmall",
            InkT("secondary"), 12)
    elseif t.reachesExalted then
        cat.Line("Quests here reach " .. (R.StandingWord(7, words) or "Exalted") .. ".", "GameFontHighlightSmall",
            C.ToneT("good"), 12)
    elseif t.reachesNext then
        local text = "Quests here reach " .. (R.FormatProgress(t.reach, words) or "")
        local short = R.ToExalted and R.ToExalted(t.reach)
        if short and short > 0 then
            text = text .. ", " .. R.FormatNumber(short) .. " short of " .. (R.StandingWord(7, words) or "Exalted")
        end
        cat.Line(text .. ".", "GameFontHighlightSmall", C.ToneT("good"), 12)
    else
        local _, _, nextAt = R.Rank(t.value or 0)
        local nextWord = R.StandingWord((t.rank or 0) + 1, words)
        if nextWord and nextAt and nextAt > t.reach then
            cat.Line(string.format("Quests here take it to %s: %s short of %s.", R.FormatProgress(t.reach, words) or "",
                R.FormatNumber(nextAt - t.reach), nextWord), "GameFontHighlightSmall", InkT("secondary"), 12)
        end
    end
end

-- What of that the spill window lands, from the ONE source the projection
-- chose ("from the Aldor's quests"), and nothing once the window has shut
local function SpillLine(cat, R, t)
    local _, _, landed, window = Projected(t)
    if landed <= 0 or not window then return end
    local top = window.to or window["until"]
    local source = window.source and C.Possessive(FactionName(window.source)) or "another faction's"
    local text = "Of that, " .. R.FormatRep(landed) .. " spills over from " .. source .. " quests here"
    if top then text = text .. ", only while " .. (R.WordFor(top, Labels()) or "") .. " or below" end
    cat.Line(text .. ".", "GameFontHighlightSmall", InkT("secondary"), 12)
end

-- The repeatables and dailies here: the steady ones with the best turn-in
-- OPEN to you now, and the rotating Wanted dailies apart -- one normal and
-- one heroic is offered a day out of every dungeon's, so they are never a
-- zone's daily income, and a level-70 heroic is no headline at 64
local OPEN_BASE = { AVAILABLE = true, LOG = true }

-- Open to you now: the adapter's word on the item when it gives one, else
-- the quest's bucket in the zone's view
local function IsOpen(cat, item)
    if type(item.open) == "boolean" then return item.open end
    local entry = (cat.S.view and cat.S.view.byId or EMPTY)[item.questId]
    return type(entry) == "table" and OPEN_BASE[entry.base] and true or false
end

local function BestTurnIn(cat, items)
    local best, bestOpen, anyOpen = 0, 0, false
    for _, item in ipairs(items) do
        local per = tonumber(item.perTurnIn) or 0
        if per > best then best = per end
        if IsOpen(cat, item) then
            anyOpen = true
            if per > bestOpen then bestOpen = per end
        end
    end
    return anyOpen and bestOpen or best, anyOpen
end

-- The generated data's condition on a quest ("HALAA"), or nil
local function ConditionOf(item)
    if item.conditional then return item.conditional end
    local D = CommanderQuestLogReputationData
    return type(D) == "table" and type(D.conditional) == "table" and D.conditional[item.questId] or nil
end
local CONDITION_WORDS = { HALAA = "only while your side holds Halaa" }

local function RepeatablesLine(cat, R, t)
    local list = t.repeatables or EMPTY
    if #list == 0 then return end
    local steady, wanted, held = {}, {}, {}
    for _, item in ipairs(list) do
        if item.rotating or RotatingKind(item.questId) then
            wanted[#wanted + 1] = item
        elseif ConditionOf(item) then
            held[#held + 1] = item
        else
            steady[#steady + 1] = item
        end
    end
    if #steady > 0 then
        local dailies = 0
        for _, item in ipairs(steady) do if item.daily then dailies = dailies + 1 end end
        local kind
        if dailies == #steady then
            kind = #steady == 1 and "1 daily" or (#steady .. " dailies")
        elseif dailies == 0 then
            kind = Plural(#steady, "repeatable")
        else
            kind = Plural(#steady, "repeatable") .. " (" .. dailies .. " daily)"
        end
        local best, open = BestTurnIn(cat, steady)
        if best <= 0 then
            -- each held to nothing from here by its reward clamp: never "0 a turn-in"
            cat.Line(string.format("%s here, %s.", kind, #steady == 1 and "paying nothing more at your standing"
                or "none paying anything more at your standing"), "GameFontHighlightSmall", InkT("faint"), 12)
        else
            cat.Line(string.format("%s here, %s%s a turn-in%s", kind, #steady == 1 and "" or "up to ", R.FormatRep(best),
                open and "." or "; none open to you yet."), "GameFontHighlightSmall", InkT("secondary"), 12)
        end
    end
    if #wanted > 0 then
        local best, open = BestTurnIn(cat, wanted)
        local text
        if best <= 0 then
            text = (#wanted == 1 and "1 rotating Wanted daily here, paying nothing more at your standing"
                or (#wanted .. " rotating Wanted dailies here, none paying anything more at your standing"))
            cat.Line(text .. ".", "GameFontHighlightSmall", InkT("faint"), 12)
        else
            if #wanted == 1 then
                text = "1 rotating Wanted daily here, " .. R.FormatRep(best) .. " on a day it is offered"
            else
                text = #wanted .. " rotating Wanted dailies here, up to " .. R.FormatRep(best) .. " on a day one is offered"
            end
            text = text .. " (one normal and one heroic a day in all)"
            cat.Line(text .. (open and "." or "; none open to you yet."), "GameFontHighlightSmall", InkT("secondary"), 12)
        end
    end
    -- a daily with a condition (Halaa's): listed with it, never income
    for _, item in ipairs(held) do
        local condition = ConditionOf(item)
        local per = tonumber(item.perTurnIn) or 0
        cat.Line(string.format("%s here, %s, %s%s", item.daily and "1 daily" or "1 repeatable",
            per > 0 and (R.FormatRep(per) .. " a turn-in") or "paying nothing more at your standing",
            CONDITION_WORDS[condition] or ("only when " .. tostring(condition)),
            IsOpen(cat, item) and "." or "; not open to you yet."), "GameFontHighlightSmall", InkT("secondary"), 12)
    end
end

-- The engine's own words for a gate the climb would shut ("Do "A Head Full
-- of Ivory" before Friendly"), and the quests no order can save
local function HintLines(cat, t)
    local projection = type(t.projection) == "table" and t.projection or EMPTY
    for index, hint in ipairs(projection.orderHints or EMPTY) do
        if index > ORDER_HINTS_SHOWN then break end
        cat.Line(hint .. ", or it closes.", "GameFontHighlightSmall", C.ToneT("warn"), 12)
    end
    local locked = #(projection.lockedOut or EMPTY)
    if locked > 0 then
        cat.Line(locked == 1 and "1 quest here will close before it opens to you."
            or (locked .. " quests here will close before they open to you."), "GameFontHighlightSmall", InkT("faint"), 12)
    end
end

local function PaintFaction(cat, R, t)
    local name = t.name or FactionName(t.factionId)
    if t.met == false then name = name .. " (not met yet)" end
    local standing = t.value and R.FormatProgress(t.value, Labels()) or t.word
    cat.Line(name .. (standing and (SEP .. standing) or ""), "GameFontHighlightSmall", InkT("strong"), 4)
    local parts = { LeftText(R, t) }
    if (t.doneCount or 0) > 0 then
        parts[#parts + 1] = "about " .. R.FormatRep(t.doneOnce or 0) .. " done in " .. Plural(t.doneCount, "quest")
    end
    cat.Line(table.concat(parts, SEP), "GameFontHighlightSmall", InkT("secondary"), 12)
    VerdictLine(cat, R, t)
    UnreachedLine(cat, t)
    SpillLine(cat, R, t)
    RepeatablesLine(cat, R, t)
    HintLines(cat, t)
end

ZoneReputation = function(cat)
    if not (RepWanted() and RulesLoaded()) then return end
    local R = Rules()
    local totals = ZoneTotals(cat.S.key)
    cat.Rule()
    cat.Heading("REPUTATION IN THIS ZONE")
    if #totals == 0 then
        cat.Line("No quest here pays this character reputation.", "GameFontHighlightSmall", InkT("faint"), 4)
        return
    end
    -- At the ceiling (Exalted 999 / 1,000) every quest and repeatable here
    -- pays 0: the faction is one name on one line, never "0 left in 13
    -- quests" and "up to 0 a turn-in" under a standing nobody can raise
    local ceiling = tonumber(R.CAP) or 42999
    local finished, capped, painted = {}, {}, 0
    for _, t in ipairs(totals) do
        local anyLeft = (t.remainingOnce or 0) > 0 or (t.leftCount or 0) > 0 or #(t.repeatables or EMPTY) > 0
        if anyLeft and (t.value or 0) >= ceiling then
            capped[#capped + 1] = t.name or FactionName(t.factionId)
        elseif anyLeft then
            -- a little air between one faction's lines and the next's
            if painted > 0 then cat.P.y = cat.P.y + FACTION_GAP end
            painted = painted + 1
            PaintFaction(cat, R, t)
        else
            finished[#finished + 1] = (t.name or FactionName(t.factionId)) .. " (about "
                .. R.FormatRep(t.doneOnce or 0) .. ")"
        end
    end
    if #capped > 0 then
        cat.Line((R.StandingWord(7, Labels()) or "Exalted") .. ", nothing more to earn here: " .. table.concat(capped, ", ")
            .. ".", "GameFontHighlightSmall", InkT("faint"), 4)
    end
    if #finished > 0 then
        cat.Line("Done here, nothing left: " .. table.concat(finished, ", ") .. ".", "GameFontHighlightSmall",
            InkT("faint"), 4)
    end
end

-- ---- grouping by reputation -------------------------------------------------

local NO_REP_GROUP = "No reputation"

-- Headers per primary faction, the biggest earners first, then the quests
-- that pay nothing; inside a group the biggest gain first
local function Group(cat, view, mode)
    if mode ~= "BYREP" then return nil end
    local R = Rules()
    if not R then return nil end
    local byFaction, groups, none, gain, any = {}, {}, {}, {}, false
    for _, entry in ipairs(view.entries or EMPTY) do
        local effects = type(entry.fact) == "table" and entry.fact.repEffects or nil
        if type(effects) == "table" then any = true end
        local factionId, delta = R.Primary(effects)
        gain[entry] = delta or 0
        if factionId then
            local group = byFaction[factionId]
            if not group then
                group = { id = factionId, title = FactionName(factionId), members = {}, total = 0 }
                byFaction[factionId] = group
                groups[#groups + 1] = group
            end
            group.members[#group.members + 1] = entry
            group.total = group.total + math.max(0, delta or 0)
        else
            none[#none + 1] = entry
        end
    end
    -- Without effects on the facts (the rules not loaded) the engine's Guide
    if not any then return nil end
    local function Before(a, b)
        if gain[a] ~= gain[b] then return gain[a] > gain[b] end
        if (a.counted and true or false) ~= (b.counted and true or false) then return a.counted and true or false end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        if (a.title or "") ~= (b.title or "") then return (a.title or "") < (b.title or "") end
        return (a.id or 0) < (b.id or 0)
    end
    table.sort(groups, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.title < b.title
    end)
    local list = {}
    for _, group in ipairs(groups) do
        table.sort(group.members, Before)
        cat.Emit(list, "REP:" .. group.id, group.title, group.members)
    end
    table.sort(none, Before)
    cat.Emit(list, "REP:NONE", NO_REP_GROUP, none)
    return list
end

-- The engine's modes, then By reputation
local GROUP_MODES = {}
for _, mode in ipairs((Engine() and Engine().GROUPS) or { "GUIDE", "STATUS", "CHAIN", "LEVEL", "NAME" }) do
    GROUP_MODES[#GROUP_MODES + 1] = mode
end
GROUP_MODES[#GROUP_MODES + 1] = "BYREP"

-- ---------------------------------------------------------------------------
-- The spec
-- ---------------------------------------------------------------------------

local ZONE_SPEC = {
    id = "ZONE", label = "Zones", title = "Zones",
    order = 20, width = TAB_W,
    tooltip = "Every quest a zone holds for this character, read from Questie: what is done, what is open, what is locked or missed and why, and what to do next.",
    prefix = "Zone", showKey = "ShowZoneTab",
    offMessage = "Commander Quest Log: the Zones tab is switched off (settings, Zones & Completion).",
    stateAliases = { areaId = "key", areaName = "keyName" },
    searchTip = "Matches a quest's name, in the zone on the card.",
    countTip = "How many of this zone's quests the search and the filter leave on the list. The zone card counts every quest that counts toward 100%, whatever is shown.",
    followEvents = { "ZONE_CHANGED_NEW_AREA" },

    Resolve = function() return ResolveZone() end,
    View = function(_, areaId) return Adapter().ZoneView(areaId) end,
    KeyName = function(_, areaId, current)
        local adapter = Adapter()
        if adapter.ZoneName then return adapter.ZoneName(areaId) end
        return current
    end,
    PlayerPos = function(_, areaId)
        local adapter = Adapter()
        return adapter.PlayerPos and adapter.PlayerPos(areaId) or nil
    end,
    -- A giver in the zone on the card is preferred, the map opens on it, and
    -- the quest's own detail is read from its view
    StarterArea = function(cat) return cat.S.key end,
    MapArea = function(cat) return cat.S.key end,
    DetailArea = function(cat) return cat.S.key end,

    MenuInit = ZoneMenuInit,
    CardTooltip = CardTooltip,
    PaintCard = PaintCard,
    PaintOverview = PaintOverview,
    EmptyMessage = EmptyMessage,

    -- Reputation (1.6.0): the overview's REPUTATION IN THIS ZONE (drawn by
    -- PaintOverview itself, under the zone's completion), the briefing's
    -- full effects (under the quest's reason while there is a number to
    -- give), a badge and a tooltip line on every row, and the By reputation
    -- grouping
    Reputation = Reputation,
    reputationFirst = ReputationFirst,
    RowRight = RowRight,
    RowTooltip = RowTooltip,
    groups = GROUP_MODES,
    groupLabels = { BYREP = "By reputation" },
    Group = Group,

    -- Waypoint, Show on Map, Open in Log, Route Zone (every open quest's
    -- giver as one Commander Orders route), and the Ignore / Count toggle at
    -- the right where the Log keeps Abandon
    actions = {
        "WAYPOINT", "MAP", "LOG",
        {
            -- A zone action, not a quest one: live with nothing selected
            field = "routeBtn", label = "Route Zone", width = 86,
            tooltip = function(cat)
                local adapter = Adapter()
                local path = adapter and adapter.WaypointPath and adapter.WaypointPath() or "PRINT"
                local text = "Set a Commander Orders route through every quest giver with an open quest in "
                    .. (cat.S.keyName or "this zone")
                    .. ", nearest first: arriving at one points the arrow at the next. Asking again replaces the route."
                if path == "ORDERS_OFF" then
                    return text .. " Commander Orders is turned off (/corder)."
                elseif path ~= "ORDERS" then
                    return text .. " Needs Commander Orders, which is not loaded."
                end
                local count = RouteStopCount(cat)
                if count == 0 then return text .. " No open quest here has a giver Questie can place." end
                return text .. string.format(" %d giver%s.", count, count == 1 and "" or "s")
            end,
            onClick = RouteZone,
            Update = function(cat, button)
                local adapter = Adapter()
                button:SetEnabled(adapter ~= nil and adapter.WaypointPath ~= nil and adapter.WaypointPath() == "ORDERS"
                    and RouteStopCount(cat) > 0)
            end,
        },
        "IGNORE",
    },
}

local Z = C.New(ZONE_SPEC)
Q.Zones = Z

-- The briefing's REPUTATION painter, for another catalogue's spec.Reputation
-- (cat, entry, detail, opts -- emphasis, always): a quest is worth the same
-- on every tab, in the same words
Z.PaintReputation = Reputation

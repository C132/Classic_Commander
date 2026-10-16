-- Commander Meters: the ARENA REPLAY — a spectator's view of a match at
-- any second of it.
--
-- Cut from the meter's own cloth (the THEME table and drawing helpers
-- shared through CommanderMeters_UI), laid out as fixed bands, top to
-- bottom:
--
--   HEADER      which match (a menu of every kept match), share, close
--   SUMMARY     gates, first blood, ratings, when
--   TEAMS       your team left, the enemy right — one PLAYER CARD per seat,
--               the way an arena frame or a spectator client draws them:
--               class portrait (with DEAD / the control on them written
--               over it), name and spec, health and power bars, the cast
--               in progress or the global cooldown sweep, a row of buffs
--               and the running cooldowns, a row of debuffs
--   TIMELINE    team pressure mirrored around an axis (us up, them down),
--               deaths / control / kicks / trinkets as markers, a cursor
--               you drag, a play button that runs the clock
--   METERS      one table per team: damage, healing, taken, control,
--               kicks, kills/deaths — as of the cursor
--   MOMENTS     the ledger around the cursor; click one to jump there
--   DISPEL LOG  a drawer to the right (header button DISPELS): every
--               dispel of the match cast by cast — who pressed what, and
--               which auras it took off whom, offensive and defensive,
--               Mass Dispel's shattered shields included — with a per-seat
--               tally above it, both read as of the cursor
--
-- The cursor is the whole idea: every band reads the match AS OF the
-- cursor time, so dragging it back to 1:12 shows the cards, the bars, the
-- auras, the casts and the meters exactly as they stood when first blood
-- fell. At the end (the default) it reads the whole match; on a live
-- match the cursor rides the live edge, which makes this a spectator
-- view of the game in progress.
--
-- Team is its own color jurisdiction (blue us / red them) and touches
-- only team chrome: the team heads, the versus bar, the pressure columns,
-- the stripe on a moment. Class colors own names and portraits; stat
-- colors own values; the accent owns the cursor and the cast bar.

local A = CommanderMetersArena
local U = CommanderMeters_UI
local THEME, WHITE, ESC = U.THEME, U.WHITE, U.ESC
local MakeText, MakeEdge, MakeGlyphButton, SetGlyphColor = U.MakeText, U.MakeEdge, U.MakeGlyphButton, U.SetGlyphColor
local FmtNum, FmtTime, ShortName, ClassColor = U.FmtNum, U.FmtTime, U.ShortName, U.ClassColor
local format = string.format
local floor, max, min = math.floor, math.max, math.min

-- ---------------------------------------------------------------------------
-- Geometry (fixed per bracket; the window never reflows while reading)
-- ---------------------------------------------------------------------------

local SIDEBAR_W = 172        -- the match list down the left
local CONTENT_W = 640        -- the replay itself
local W = SIDEBAR_W + CONTENT_W
local PAD = 4
local HEAD_H = THEME.headerH
local SIDE_ROW_H = 28        -- two lines per kept match
local SUM_H = 14
local COL_W = floor((CONTENT_W - PAD * 2 - 1) / 2)   -- 315
local TEAM_HEAD_H = 16
local CARD_H = 98
local CARD_GAP = 3
local MAX_SEATS = 5
local PORTRAIT = 44
local ICON = 16
local ICON_GAP = 2
local ICONS_PER_ROW = 8
local CTRL_W = 46
local PLOT_H = 80
local AXIS_H = 12
local ROW_H = 14
local METER_COLS = { -- key, label, color, width
    { "DMG", "DMG", "statDmg", 40 }, { "HEAL", "HEAL", "statHeal", 40 }, { "TAKEN", "TAKEN", "statTaken", 40 },
    { "CC", "CC", "statCC", 36 }, { "KICKS", "KICK", "statUtil", 30 }, { "KILLS", "K/D", "statDeath", 30 },
}
local FEED_ROWS = 6
local DLOG_W = 300           -- the dispel log drawer (the window widens by it when open)
local DLOG_LINES_MAX = 80    -- pooled log lines; as many show as the height fits
local DLOG_TAG_W = 60
local DLOG_TALLY = { -- field, label, color, width: the per-seat block, as of the cursor
    { "off", "OFF", "statUtil", 36 }, { "def", "DEF", "statCleanse", 36 },
    { "fail", "MISS", "danger", 38 }, { "lost", "LOST", "textDim", 38 }, { "cleansed", "FREED", "textDim", 42 },
}
local FEED_H = ROW_H + FEED_ROWS * ROW_H
local HINT_H = 12
local MAX_COLUMNS = 320
local MAX_MARKERS = 240
local PLAY_SPEEDS = { 1, 2, 4 }
local BRACKET = { [1] = "", [2] = " \194\189", [3] = " \194\188", [4] = " (immune?)" }
local CLASS_RING = "Interface\\TargetingFrame\\UI-Classes-Circles"
local TRINKET_SPELL = { id = 42292, name = "PvP Trinket" }  -- the medallion's spell, for the tooltip
local TRINKET_BADGE = 16
local TRINKET_CD = 120
-- The medallion's own art per faction, never the spell's icon (it reads as
-- a dispel); the shared Commander.TrinketIcon picks it
local function SeatTrinketIcon(seat)
    return Commander.TrinketIcon(nil, seat and seat.race, not seat or seat.team ~= "us")
end
local POWER_COLOR = {
    [0] = { 0.30, 0.55, 0.95 },   -- mana
    [1] = { 0.85, 0.25, 0.25 },   -- rage
    [2] = { 0.95, 0.60, 0.25 },   -- focus
    [3] = { 0.95, 0.85, 0.30 },   -- energy
}

-- ---------------------------------------------------------------------------
-- View state
-- ---------------------------------------------------------------------------

local view = {
    sel = "last",       -- "live" | "last" | match id
    t = nil,            -- cursor (match-relative s); nil = the end / live edge
    playing = false,
    speedIndex = 1,
    dragging = false,
    sideOffset = 0,     -- sidebar scroll (rows)
    dlog = true,        -- the dispel log drawer is open (db.ArenaDispelLog)
    dlogOffset = 0,     -- its scroll (lines)
    dlogFollow = true,  -- the list follows the cursor; the wheel stops it
    dlogFollowT = nil,  -- ...until the cursor moves again
    dlogUs = true, dlogThem = true,  -- filters: whose casts
    dlogOff = true, dlogDef = true,  -- filters: which side of a dispel
}

local root, content, head, matchBtn, shareBtn, dlogBtn, sumText
local side = {}         -- the match list: frame, rows, foot
local teams = {}        -- [1] us, [2] them: { head, cards = {} }
local vsBar = {}
local plot, ctrl, axis = {}, {}, {}
local meters = {}       -- [1], [2]: { head, rows = {} }
local feed = {}
local dlog = {}         -- the dispel log drawer: frame, chips, tally, lines
local hint
local bands = {}
local layoutRows = nil
local BuildSidebar -- forward
local stateScratch = {}
local onScratch = {}        -- guid -> { n, names } : who is on this seat at the cursor
local pressureScratch = {}
local pressureFor = nil
local repaintAcc = 0
local built = false
local RepaintAll -- forward

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function Match()
    if view.sel == "live" then return A.Live() or A.GetMatch("last") end
    return A.GetMatch(view.sel) or A.GetMatch("last")
end

local function IsLive(m) return m ~= nil and A.Live() == m end

local function EndTime(m)
    if IsLive(m) then return max(time() - m.tsStart, 0) end
    return m.tEnd or 0
end

local function Cursor(m)
    local e = EndTime(m)
    if view.t == nil or view.t >= e then return e, true end
    if view.t < 0 then view.t = 0 end
    return view.t, false
end

local function SetCursor(m, t)
    local e = EndTime(m)
    if t == nil or t >= e then view.t = nil else view.t = max(t, 0) end
end

local function GateTime(m, t)
    local g = m.tGates or 0
    local d = t - g
    if d < 0 then return "-" .. FmtTime(-d) end
    return FmtTime(d)
end

local function Esc(color) return U.EscOf(color) end

local function SeatLabel(m, guid, plain)
    local seat = guid and m.seats[guid]
    if not seat then return "?" end
    local name = ShortName(seat.name or "?")
    if plain then return name end
    return Esc(ClassColor(seat.class)) .. name .. "|r"
end

local function ResultText(m)
    if not m.result then return IsLive(m) and "LIVE" or "?" end
    if m.result == "WIN" or m.result == "LOSS" then
        local _, _, change = A.OurRating(m)
        if change then return format("%s %+d", m.result, change) end
    end
    return m.result
end

local function ResultColor(m)
    if m.result == "WIN" then return THEME.healTx end
    if m.result == "LOSS" then return THEME.danger end
    if IsLive(m) then return THEME.accent end
    return THEME.textDim
end

local function MatchTitle(m)
    if not m then return "NO MATCH RECORDED — /cm arenatest FOR A CANNED ONE" end
    local size = m.bracket > 0 and (m.bracket .. "v" .. m.bracket) or "ARENA"
    local dur = IsLive(m) and (time() - m.tsStart - (m.tGates or 0)) or m.dur
    if dur < 0 then dur = 0 end
    return format("%s · %s · %s%s|r · %s", size, (m.map or "ARENA"):upper(),
        Esc(ResultColor(m)), ResultText(m), FmtTime(dur))
end

local function IconTexture(rec)
    -- A medallion press shows the medallion, on the moment list as on the badge
    if type(rec) == "table" and rec.kind == "TRINKET" and rec.x == "TRINKET" then
        local m = Match()
        return SeatTrinketIcon(m and rec.src and m.seats[rec.src])
    end
    return U.IconOf(rec)
end

local function OpenMenu(builder, anchor) U.OpenMenu(builder, anchor) end

local function MakeFill(frame, color, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(WHITE)
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    t:SetAllPoints()
    return t
end

-- ---------------------------------------------------------------------------
-- Moments: the words for a ledger entry
-- ---------------------------------------------------------------------------

local KIND_COLOR = {
    CC = "statCC", CCFAIL = "danger", KICK = "statUtil", DISPEL = "statCleanse",
    DEATH = "statDeath", CD = "statCd", TRINKET = "statCd", DRINK = "statMana",
    DRAIN = "statMana", GATES = "accent", END = "accent", SPEC = "textDim", FEIGN = "textDim",
}

local function MomentWord(e)
    if e.kind == "DISPEL" then
        if e.x ~= "PURGE" then return "DISPEL" end
        return e.inf and "SHATTER" or "PURGE"
    end
    if e.kind == "CCFAIL" then return "WASTED" end
    return e.kind
end

local function MomentWho(e)
    if e.kind == "DEATH" then return e.dst end
    return e.src or e.dst
end

-- The far end of a removal: the seat, a pet with its owner, or the bare
-- name of something that has no seat
local function DispelTarget(m, dst, pet, dn)
    if dst and m.seats[dst] then
        local s = SeatLabel(m, dst)
        if pet then return pet .. ESC.dim .. " (|r" .. s .. ESC.dim .. ")|r" end
        return s
    end
    return ESC.dim .. (pet or dn or "?") .. "|r"
end

local function MomentText(m, e)
    local c = THEME[KIND_COLOR[e.kind] or "text"] or THEME.text
    if e.kind == "DISPEL" and e.x == "PURGE" then c = e.inf and THEME.accent or THEME.statUtil end
    local head = Esc(c) .. MomentWord(e) .. "|r  "
    local k = e.kind
    if k == "GATES" then return head .. "The gates open" end
    if k == "END" then return head .. "Match over — " .. (e.name or "?") end
    if k == "SPEC" then return head .. (e.name or "?") .. ESC.dim .. " revealed|r" end
    if k == "FEIGN" then return head .. "Feign Death" .. ESC.dim .. "  (not a death)|r" end
    if k == "CC" then
        local dur = e.t2 and format(" · %.1fs", e.t2 - e.t) or " · open"
        local s = head .. (e.name or "?") .. Esc(THEME.statCC) .. (BRACKET[e.x or 1] or "") .. "|r → "
            .. SeatLabel(m, e.dst) .. ESC.dim .. dur .. "|r"
        if e.brk then
            s = s .. (e.own and Esc(THEME.danger) or ESC.dim) .. "  broken by " .. SeatLabel(m, e.brk, true)
                .. (e.own and " (OWN TEAM)" or "") .. "|r"
        end
        return s
    end
    if k == "CCFAIL" then
        return head .. (e.name or "?") .. " → " .. SeatLabel(m, e.dst) .. ESC.dim .. "  " .. tostring(e.x or "") .. "|r"
    end
    if k == "KICK" then
        return head .. tostring(e.x or "?") .. " → " .. SeatLabel(m, e.dst) .. ESC.dim .. "'s " .. (e.name or "?") .. "|r"
    end
    if k == "DISPEL" then
        return head .. (e.name or "?") .. ESC.dim .. " off |r" .. DispelTarget(m, e.dst, e.pet, e.dn)
            .. (e.by and (ESC.dim .. " · " .. e.by .. "|r") or "")
    end
    if k == "DEATH" then
        local by = e.src and (" (" .. SeatLabel(m, e.src, true) .. ")") or ""
        return head .. SeatLabel(m, e.dst) .. ESC.dim .. " ← " .. (e.name or "?") .. by .. "|r"
    end
    if k == "CD" then
        return head .. (e.name or "?") .. ESC.dim .. "  " .. tostring(e.x or "") .. (e.amount and format(" · %ds cd", e.amount) or "") .. "|r"
    end
    if k == "TRINKET" then return head .. (e.name or "?") end
    if k == "DRINK" then return head .. ESC.dim .. (e.t2 and format("%.0fs", e.t2 - e.t) or "open") .. "|r" end
    if k == "DRAIN" then
        return head .. FmtNum(e.amount or 0) .. " mana" .. ESC.dim .. " ← " .. (e.name or "?") .. " → |r" .. SeatLabel(m, e.dst)
    end
    return head .. (e.name or "")
end

-- ---------------------------------------------------------------------------
-- Report to chat (both teams' damage and healing as of the cursor)
-- ---------------------------------------------------------------------------

local reportLines = {}

local function BuildReport(m)
    if not m then return 0 end
    local t, atEnd = Cursor(m)
    local n = 1
    reportLines[1] = format("Commander Meters — ARENA %s %s: %s, %s%s",
        m.bracket > 0 and (m.bracket .. "v" .. m.bracket) or "", m.map or "", m.result or "LIVE",
        FmtTime(A.DurationAt(m, t)), atEnd and "" or (" @ " .. GateTime(m, t)))
    local DMG, HEAL = A.StatByKey("DMG"), A.StatByKey("HEAL")
    for _, teamKey in ipairs({ "us", "them" }) do
        local tm = m.teams[teamKey]
        local parts = {}
        for i = 1, tm.n do
            local seat = m.seats[tm.order[i]]
            if seat then
                parts[#parts + 1] = format("%s %s dmg / %s heal", ShortName(seat.name or "?"),
                    FmtNum((A.SeatValueAt(m, seat, DMG, t))), FmtNum((A.SeatValueAt(m, seat, HEAL, t))))
            end
        end
        n = n + 1
        reportLines[n] = format("%s: %s", teamKey == "us" and "US" or "THEM", #parts > 0 and table.concat(parts, ", ") or "-")
    end
    if m.firstBlood then
        n = n + 1
        reportLines[n] = format("First blood %s: %s", GateTime(m, m.firstBlood.t), ShortName(A.SeatName(m, m.firstBlood.guid) or "?"))
    end
    return n
end

local function SendReport(channel)
    local n = BuildReport(Match())
    if n == 0 then
        print("|cff66ccffCommander Meters|r: no arena match to report")
        return
    end
    for i = 1, n do SendChatMessage(reportLines[i], channel) end
end

local function ArenaShareMenu()
    local function entry(label, channel, shown)
        if not shown then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = label
        info.notCheckable = true
        info.func = function() SendReport(channel) end
        UIDropDownMenu_AddButton(info)
    end
    local inInstanceGroup = IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
    local inHomeParty = IsInGroup
        and ((LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME))
            or (not LE_PARTY_CATEGORY_HOME and IsInGroup() and not inInstanceGroup))
    entry("SAY", "SAY", true)
    entry("PARTY", "PARTY", inHomeParty)
    entry("RAID", "RAID", IsInRaid() and not inInstanceGroup)
    entry("INSTANCE", "INSTANCE_CHAT", inInstanceGroup)
    entry("GUILD", "GUILD", IsInGuild and IsInGuild())
end

local function MatchMenu()
    local live = A.Live()
    if live then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "LIVE — " .. (live.map or "arena"):upper()
        info.checked = Match() == live
        info.func = function() view.sel = "live"; view.t = nil; view.playing = false; RepaintAll() end
        UIDropDownMenu_AddButton(info)
    end
    local list = A.GetMatches()
    if #list == 0 and not live then
        local info = UIDropDownMenu_CreateInfo()
        info.text = "No matches recorded yet"
        info.notCheckable, info.disabled = true, true
        UIDropDownMenu_AddButton(info)
        return
    end
    local current = Match()
    for i = 1, #list do
        local m = list[i]
        local info = UIDropDownMenu_CreateInfo()
        info.text = format("%s %s · %s · %s · %s", m.bracket > 0 and (m.bracket .. "v" .. m.bracket) or "?v?",
            (m.map or "?"):upper(), ResultText(m), FmtTime(m.dur), date("%H:%M", m.tsStart))
        info.checked = current == m
        local id = m.id
        info.func = function() view.sel = id; view.t = nil; view.playing = false; RepaintAll() end
        UIDropDownMenu_AddButton(info)
    end
end

-- ---------------------------------------------------------------------------
-- Player cards
-- ---------------------------------------------------------------------------

-- An aura / cooldown icon: a button with a trimmed spell texture, a 1 px
-- border quad, and a small text over its bottom edge (seconds left)
local function MakeIcon(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetTexture(WHITE)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.text = MakeText(b, 9, "RIGHT")
    b.text:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)
    b.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    b:SetScript("OnEnter", function(self)
        if not self.rec then return end
        local rec = self.rec
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local shown = false
        if rec.id and GameTooltip.SetSpellByID then
            shown = pcall(GameTooltip.SetSpellByID, GameTooltip, rec.id)
        end
        if not shown then
            GameTooltip:SetText(rec.name or "?", THEME.tipText[1], THEME.tipText[2], THEME.tipText[3])
        end
        GameTooltip:AddLine(" ")
        if self.tipLines then self.tipLines(self, rec) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function MakeBar(parent, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(h)
    f.track = f:CreateTexture(nil, "BACKGROUND")
    f.track:SetTexture(WHITE)
    f.track:SetVertexColor(1, 1, 1, 0.07)
    f.track:SetAllPoints()
    f.fill = f:CreateTexture(nil, "ARTWORK")
    f.fill:SetTexture(WHITE)
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    f.fill:SetWidth(0.001)
    f.text = MakeText(f, THEME.fontSizeSmall, "CENTER")
    f.text:SetAllPoints()
    return f
end

local function BuildCard(parent, index, teamIndex)
    local card = CreateFrame("Frame", nil, parent)
    card.teamIndex, card.cardIndex = teamIndex, index
    card:SetHeight(CARD_H)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(TEAM_HEAD_H + 2 + (index - 1) * (CARD_H + CARD_GAP)))
    card:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    card.fill = MakeFill(card, { 1, 1, 1, 0.04 })
    MakeEdge(card)

    -- Portrait: the class ring, dimmed when dead, ringed in the control's
    -- color while controlled; the state word sits under it
    card.portraitBtn = CreateFrame("Button", nil, card)
    card.portraitBtn:SetSize(PORTRAIT, PORTRAIT)
    card.portraitBtn:SetPoint("TOPLEFT", card, "TOPLEFT", 3, -3)
    card.portraitBtn:SetScript("OnEnter", function(self)
        if self.guid then U.ArenaSeatTooltip(self, Match()) end
    end)
    card.portraitBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    card.ring = card.portraitBtn:CreateTexture(nil, "BACKGROUND")
    card.ring:SetTexture(WHITE)
    card.ring:SetPoint("TOPLEFT", card.portraitBtn, "TOPLEFT", -2, 2)
    card.ring:SetPoint("BOTTOMRIGHT", card.portraitBtn, "BOTTOMRIGHT", 2, -2)
    card.ring:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], 1)
    card.portrait = card.portraitBtn:CreateTexture(nil, "ARTWORK")
    card.portrait:SetAllPoints()
    card.portraitFallback = MakeText(card.portraitBtn, 18, "CENTER")
    card.portraitFallback:SetAllPoints()
    card.portraitFallback:Hide()
    card.ccIcon = card.portraitBtn:CreateTexture(nil, "OVERLAY")
    card.ccIcon:SetSize(22, 22)
    card.ccIcon:SetPoint("CENTER", card.portraitBtn, "CENTER", -3, 3)
    card.ccIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.ccIcon:Hide()
    card.state = MakeText(card, 9, "CENTER")
    card.state:SetPoint("TOP", card.portraitBtn, "BOTTOM", 0, -1)
    card.state:SetWidth(PORTRAIT + 6)
    -- The PvP trinket badge on the portrait's top-right corner: full color
    -- while it is up, desaturated with the time left while it is down. The
    -- one enemy cooldown a spectator watches for above all others.
    card.trinket = MakeIcon(card)
    card.trinket.trinketBadge = true
    card.trinket:SetSize(TRINKET_BADGE, TRINKET_BADGE)
    -- Tucked inside the portrait's bottom-right corner (an arena frame's
    -- place for it); the control icon sits a little up-left of center to
    -- stay clear of it
    card.trinket:SetPoint("CENTER", card.portraitBtn, "BOTTOMRIGHT", -8, 8)
    card.trinket:SetFrameLevel(card.portraitBtn:GetFrameLevel() + 2)
    -- The clock sits on the badge itself (under it, it ran into the state
    -- word beneath the portrait)
    card.trinket.text:ClearAllPoints()
    card.trinket.text:SetPoint("CENTER", card.trinket, "CENTER", 0, 0)
    card.trinket.text:SetJustifyH("CENTER")
    card.trinket.text:SetWidth(24)
    -- The radial: the client's own cooldown sweep, PAUSED at the cursor's
    -- fraction (the Kicks / Arena Frames sweep, held still)
    card.trinket.sweep = CreateFrame("Cooldown", nil, card.trinket, "CooldownFrameTemplate")
    card.trinket.sweep:SetAllPoints()
    pcall(card.trinket.sweep.SetHideCountdownNumbers, card.trinket.sweep, true)
    pcall(card.trinket.sweep.SetDrawEdge, card.trinket.sweep, false)
    pcall(card.trinket.sweep.SetDrawBling, card.trinket.sweep, false)
    pcall(card.trinket.sweep.SetReverse, card.trinket.sweep, false)
    card.trinket.tipLines = function(self, rec)
        local m = Match()
        if not m then return end
        local td, tf = THEME.tipDim, THEME.tipFaint
        if self.left then
            GameTooltip:AddDoubleLine("READY IN", FmtTime(self.left), td[1], td[2], td[3], THEME.danger[1], THEME.danger[2], THEME.danger[3])
            if self.pressedAt then
                GameTooltip:AddDoubleLine("PRESSED", GateTime(m, self.pressedAt), td[1], td[2], td[3], tf[1], tf[2], tf[3])
            end
        else
            GameTooltip:AddDoubleLine("STATUS", "up", td[1], td[2], td[3], THEME.healTx[1], THEME.healTx[2], THEME.healTx[3])
            GameTooltip:AddLine("Read from the combat log: a press starts two minutes; nothing seen means up.",
                THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3], true)
        end
    end

    card.name = MakeText(card, THEME.fontSize, "LEFT")
    card.name:SetHeight(13)
    card.name:SetPoint("TOPLEFT", card, "TOPLEFT", PORTRAIT + 11, -3)
    card.name:SetPoint("RIGHT", card, "RIGHT", -96, 0)
    -- Who they are on, from their newest cast's target
    card.target = MakeText(card, THEME.fontSizeSmall, "RIGHT")
    card.target:SetHeight(13)
    card.target:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -3)
    card.target:SetWidth(90)

    card.hp = MakeBar(card, 12)
    card.hp:SetPoint("TOPLEFT", card, "TOPLEFT", PORTRAIT + 9, -18)
    card.hp:SetPoint("RIGHT", card, "RIGHT", -4, 0)
    card.pow = MakeBar(card, 6)
    card.pow:SetPoint("TOPLEFT", card, "TOPLEFT", PORTRAIT + 9, -32)
    card.pow:SetPoint("RIGHT", card, "RIGHT", -4, 0)
    card.pow.text:Hide()
    card.cast = MakeBar(card, 12)
    card.cast:SetPoint("TOPLEFT", card, "TOPLEFT", PORTRAIT + 9, -40)
    card.cast:SetPoint("RIGHT", card, "RIGHT", -4, 0)

    -- Row 1: buffs (left half) and running cooldowns (right half);
    -- row 2: debuffs (full width)
    card.buffs, card.cds, card.debuffs = {}, {}, {}
    local half = floor((COL_W - 6) / 2)
    for i = 1, ICONS_PER_ROW do
        local b = MakeIcon(card)
        b:SetPoint("TOPLEFT", card, "TOPLEFT", 3 + (i - 1) * (ICON + ICON_GAP), -60)
        b.border:SetVertexColor(0.25, 0.6, 0.3, 1)
        card.buffs[i] = b
        local c = MakeIcon(card)
        c:SetPoint("TOPLEFT", card, "TOPLEFT", 3 + half + (i - 1) * (ICON + ICON_GAP), -60)
        c.border:SetVertexColor(THEME.statCd[1], THEME.statCd[2], THEME.statCd[3], 1)
        card.cds[i] = c
    end
    for i = 1, ICONS_PER_ROW * 2 do
        local d = MakeIcon(card)
        d:SetPoint("TOPLEFT", card, "TOPLEFT", 3 + (i - 1) * (ICON + ICON_GAP), -79)
        d.border:SetVertexColor(0.75, 0.25, 0.25, 1)
        card.debuffs[i] = d
    end
    return card
end

local function BuildTeams(parent, y)
    for i = 1, 2 do
        local f = CreateFrame("Frame", nil, parent)
        f:SetWidth(COL_W)
        if i == 1 then
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        else
            f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y)
        end
        local tc = i == 1 and THEME.teamUs or THEME.teamThem
        f.head = CreateFrame("Frame", nil, f)
        f.head:SetHeight(TEAM_HEAD_H)
        f.head:SetPoint("TOPLEFT")
        f.head:SetPoint("TOPRIGHT")
        f.head.fill = MakeFill(f.head, THEME.chrome)
        f.head.stripe = f.head:CreateTexture(nil, "ARTWORK")
        f.head.stripe:SetTexture(WHITE)
        f.head.stripe:SetVertexColor(tc[1], tc[2], tc[3], 1)
        f.head.stripe:SetWidth(3)
        f.head.stripe:SetPoint("TOPLEFT")
        f.head.stripe:SetPoint("BOTTOMLEFT")
        f.head.title = MakeText(f.head, THEME.fontSizeSmall, "LEFT")
        f.head.title:SetPoint("LEFT", f.head, "LEFT", 7, 0)
        f.head.title:SetPoint("RIGHT", f.head, "RIGHT", -110, 0)
        f.head.title:SetTextColor(tc[1], tc[2], tc[3])
        f.head.total = MakeText(f.head, THEME.fontSizeSmall, "RIGHT")
        f.head.total:SetPoint("RIGHT", f.head, "RIGHT", -4, 0)
        f.head.total:SetWidth(106)
        f.cards = {}
        for c = 1, MAX_SEATS do f.cards[c] = BuildCard(f, c, i) end
        teams[i] = f
    end
end

-- ---------------------------------------------------------------------------
-- Timeline
-- ---------------------------------------------------------------------------

local function MouseX(frame)
    local x = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    return x / scale - (frame:GetLeft() or 0)
end

local function PlotWidth()
    local w = plot.frame:GetWidth()
    if not w or w <= 0 then w = CONTENT_W - PAD * 2 - CTRL_W - 2 end
    return w
end

-- The plot's window on the match: a few seconds before the gates to the
-- end (the pre-gate minute is a minute in which nothing happens)
local PLOT_LEAD = 3

local function PlotOrigin(m)
    local t0 = max((m.tGates or 0) - PLOT_LEAD, 0)
    local e = EndTime(m)
    if e <= t0 then t0 = max(e - 1, 0) end
    return t0, max(e - t0, 1)
end

local function CursorFromMouse(m)
    local frac = MouseX(plot.frame) / PlotWidth()
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    local t0, span = PlotOrigin(m)
    SetCursor(m, t0 + frac * span)
end

local function TogglePlay()
    local m = Match()
    if not m then return end
    if view.playing then
        view.playing = false
    else
        local _, atEnd = Cursor(m)
        if atEnd then view.t = max((m.tGates or 0) - PLOT_LEAD, 0) end
        view.playing = true
    end
    RepaintAll()
end

local function BuildTimeline(parent, y)
    ctrl.frame = CreateFrame("Frame", nil, parent)
    ctrl.frame:SetSize(CTRL_W, PLOT_H + AXIS_H)
    ctrl.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
    ctrl.play = MakeGlyphButton(ctrl.frame, "play")
    ctrl.play:SetSize(22, 22)
    ctrl.play:SetPoint("TOP", ctrl.frame, "TOP", 0, -2)
    ctrl.play.role = "play"
    ctrl.play:SetScript("OnClick", TogglePlay)
    Commander.UI.AttachTooltip(ctrl.play, "Play / Pause", "Run the clock from the cursor (from the gates when the cursor sits at the end). Every band follows the cursor.")
    ctrl.pause = MakeGlyphButton(ctrl.frame, "pause")
    ctrl.pause:SetSize(22, 22)
    ctrl.pause:SetPoint("TOP", ctrl.frame, "TOP", 0, -2)
    ctrl.pause:SetScript("OnClick", TogglePlay)
    ctrl.pause:Hide()
    ctrl.skip = MakeGlyphButton(ctrl.frame, "skip")
    ctrl.skip:SetSize(22, 22)
    ctrl.skip:SetPoint("TOP", ctrl.play, "BOTTOM", 0, -2)
    ctrl.skip.role = "skip"
    ctrl.skip:SetScript("OnClick", function()
        view.t = nil
        view.playing = false
        RepaintAll()
    end)
    Commander.UI.AttachTooltip(ctrl.skip, "To the End", "Read the whole match (or the live edge of one in progress).")
    ctrl.speed = CreateFrame("Button", nil, ctrl.frame)
    ctrl.speed:SetSize(CTRL_W - 4, 14)
    ctrl.speed:SetPoint("TOP", ctrl.skip, "BOTTOM", 0, -2)
    ctrl.speed.role = "speed"
    ctrl.speed.text = MakeText(ctrl.speed, THEME.fontSizeSmall, "CENTER")
    ctrl.speed.text:SetAllPoints()
    ctrl.speed.hover = ctrl.speed:CreateTexture(nil, "HIGHLIGHT")
    ctrl.speed.hover:SetTexture(WHITE)
    ctrl.speed.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
    ctrl.speed.hover:SetAllPoints()
    ctrl.speed:SetScript("OnClick", function()
        view.speedIndex = (view.speedIndex % #PLAY_SPEEDS) + 1
        RepaintAll()
    end)
    Commander.UI.AttachTooltip(ctrl.speed, "Playback Speed", "1x, 2x, or 4x real time.")
    ctrl.clock = MakeText(ctrl.frame, THEME.fontSizeSmall, "CENTER")
    ctrl.clock:SetPoint("BOTTOM", ctrl.frame, "BOTTOM", 0, 0)
    ctrl.clock:SetWidth(CTRL_W)
    ctrl.clock:SetTextColor(THEME.accent[1], THEME.accent[2], THEME.accent[3])

    plot.frame = CreateFrame("Frame", nil, parent)
    plot.frame:SetHeight(PLOT_H)
    plot.frame:SetPoint("TOPLEFT", ctrl.frame, "TOPRIGHT", 2, 0)
    plot.frame:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    plot.fill = MakeFill(plot.frame, THEME.plotFill)
    MakeEdge(plot.frame)
    plot.axis = plot.frame:CreateTexture(nil, "BORDER")
    plot.axis:SetTexture(WHITE)
    plot.axis:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], 1)
    plot.axis:SetHeight(1)
    plot.axis:SetPoint("LEFT", plot.frame, "LEFT", 0, 0)
    plot.axis:SetPoint("RIGHT", plot.frame, "RIGHT", 0, 0)
    plot.gates = plot.frame:CreateTexture(nil, "BORDER")
    plot.gates:SetTexture(WHITE)
    plot.gates:SetVertexColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.6)
    plot.gates:SetWidth(1)
    plot.gates:Hide()
    plot.cursor = plot.frame:CreateTexture(nil, "OVERLAY")
    plot.cursor:SetTexture(WHITE)
    plot.cursor:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.9)
    plot.cursor:SetWidth(1)
    -- A dim hairline and a clock follow the mouse, so a click lands where
    -- the eye expects (the graph's hover hairline, in dim)
    plot.hover = plot.frame:CreateTexture(nil, "OVERLAY")
    plot.hover:SetTexture(WHITE)
    plot.hover:SetVertexColor(THEME.text[1], THEME.text[2], THEME.text[3], 0.35)
    plot.hover:SetWidth(1)
    plot.hover:Hide()
    plot.hoverText = MakeText(plot.frame, THEME.fontSizeSmall, "CENTER")
    plot.hoverText:SetPoint("BOTTOM", plot.hover, "TOP", 0, 0)
    plot.hoverText:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    plot.hoverText:Hide()
    plot.frame:SetScript("OnEnter", function() plot.hovering = true end)
    plot.frame:SetScript("OnLeave", function()
        plot.hovering = false
        plot.hover:Hide()
        plot.hoverText:Hide()
    end)
    plot.usLabel = MakeText(plot.frame, THEME.fontSizeSmall, "LEFT")
    plot.usLabel:SetPoint("TOPLEFT", plot.frame, "TOPLEFT", 3, -2)
    plot.usLabel:SetTextColor(THEME.teamUs[1], THEME.teamUs[2], THEME.teamUs[3])
    plot.usLabel:SetText("US")
    plot.themLabel = MakeText(plot.frame, THEME.fontSizeSmall, "LEFT")
    plot.themLabel:SetPoint("BOTTOMLEFT", plot.frame, "BOTTOMLEFT", 3, 2)
    plot.themLabel:SetTextColor(THEME.teamThem[1], THEME.teamThem[2], THEME.teamThem[3])
    plot.themLabel:SetText("THEM")
    plot.msg = MakeText(plot.frame, THEME.fontSizeSmall, "CENTER")
    plot.msg:SetPoint("CENTER", plot.frame, "CENTER", 0, 0)
    plot.msg:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    plot.columns = {}
    plot.markers = {}
    plot.frame:EnableMouse(true)
    plot.frame:EnableMouseWheel(true)
    plot.frame:SetScript("OnMouseDown", function()
        local m = Match()
        if not m then return end
        view.dragging = true
        view.playing = false
        CursorFromMouse(m)
        RepaintAll()
    end)
    plot.frame:SetScript("OnMouseUp", function() view.dragging = false end)
    plot.frame:SetScript("OnMouseWheel", function(_, delta)
        local m = Match()
        if not m then return end
        local t = Cursor(m)
        SetCursor(m, t + delta)
        view.playing = false
        RepaintAll()
    end)

    axis.frame = CreateFrame("Frame", nil, parent)
    axis.frame:SetHeight(AXIS_H)
    axis.frame:SetPoint("TOPLEFT", plot.frame, "BOTTOMLEFT", 0, 0)
    axis.frame:SetPoint("RIGHT", plot.frame, "RIGHT", 0, 0)
    axis.left = MakeText(axis.frame, THEME.fontSizeSmall, "LEFT")
    axis.left:SetPoint("LEFT", axis.frame, "LEFT", 2, 0)
    axis.left:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    axis.mid = MakeText(axis.frame, THEME.fontSizeSmall, "CENTER")
    axis.mid:SetPoint("CENTER", axis.frame, "CENTER", 0, 0)
    axis.mid:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    axis.right = MakeText(axis.frame, THEME.fontSizeSmall, "RIGHT")
    axis.right:SetPoint("RIGHT", axis.frame, "RIGHT", -2, 0)
    axis.right:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
end

-- ---------------------------------------------------------------------------
-- Meters (one table per team) and the moments feed
-- ---------------------------------------------------------------------------

local METER_COLS_W = 0
for _, spec in ipairs(METER_COLS) do METER_COLS_W = METER_COLS_W + spec[4] end

local function BuildMeters(parent, y)
    for i = 1, 2 do
        local f = CreateFrame("Frame", nil, parent)
        f:SetWidth(COL_W)
        if i == 1 then
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        else
            f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y)
        end
        f.head = CreateFrame("Frame", nil, f)
        f.head:SetHeight(ROW_H)
        f.head:SetPoint("TOPLEFT")
        f.head:SetPoint("TOPRIGHT")
        f.head.fill = MakeFill(f.head, THEME.chrome)
        f.head.name = MakeText(f.head, THEME.fontSizeSmall, "LEFT")
        f.head.name:SetPoint("LEFT", f.head, "LEFT", 4, 0)
        f.head.name:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        f.head.name:SetText(i == 1 and "YOUR TEAM" or "ENEMY")
        f.head.cols = {}
        local x = COL_W - 2
        for c = #METER_COLS, 1, -1 do
            local spec = METER_COLS[c]
            local fs = MakeText(f.head, THEME.fontSizeSmall, "RIGHT")
            fs:SetPoint("RIGHT", f.head, "LEFT", x, 0)
            fs:SetWidth(spec[4])
            local col = THEME[spec[3]] or THEME.text
            fs:SetTextColor(col[1], col[2], col[3])
            fs:SetText(spec[2])
            f.head.cols[c] = fs
            x = x - spec[4]
        end
        f.rows = {}
        for r = 1, MAX_SEATS do
            local row = CreateFrame("Frame", nil, f)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(r * ROW_H))
            row:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            row.name = MakeText(row, THEME.fontSizeSmall, "LEFT")
            row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.name:SetWidth(COL_W - 6 - METER_COLS_W)
            row.cols = {}
            local rx = COL_W - 2
            for c = #METER_COLS, 1, -1 do
                local spec = METER_COLS[c]
                local fs = MakeText(row, THEME.fontSizeSmall, "RIGHT")
                fs:SetPoint("RIGHT", row, "LEFT", rx, 0)
                fs:SetWidth(spec[4])
                row.cols[c] = fs
                rx = rx - spec[4]
            end
            f.rows[r] = row
        end
        meters[i] = f
    end
end

local function FeedRowClick(self)
    local m = Match()
    if not (m and self.idx) then return end
    local e = m.ledger[self.idx]
    if not e then return end
    SetCursor(m, e.t)
    view.playing = false
    RepaintAll()
end

local function FeedRowEnter(self)
    local m = Match()
    if not (m and self.idx) then return end
    local e = m.ledger[self.idx]
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    if e.id and GameTooltip.SetSpellByID then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, e.id)
    end
    if not shown then
        GameTooltip:SetText(e.name or MomentWord(e), THEME.tipText[1], THEME.tipText[2], THEME.tipText[3])
    end
    local td, tf = THEME.tipDim, THEME.tipFaint
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("AT", GateTime(m, e.t), td[1], td[2], td[3], tf[1], tf[2], tf[3])
    if e.src then GameTooltip:AddDoubleLine("BY", SeatLabel(m, e.src, true), td[1], td[2], td[3], tf[1], tf[2], tf[3]) end
    if e.dst then GameTooltip:AddDoubleLine("ON", SeatLabel(m, e.dst, true), td[1], td[2], td[3], tf[1], tf[2], tf[3]) end
    if e.kind == "CC" then
        if e.x then
            local c = THEME.statCC
            GameTooltip:AddDoubleLine("DR BRACKET", e.x == 1 and "FULL" or e.x == 2 and "HALF" or e.x == 3 and "QUARTER" or "IMMUNE?",
                td[1], td[2], td[3], c[1], c[2], c[3])
        end
        if e.t2 then GameTooltip:AddDoubleLine("LASTED", format("%.1fs", e.t2 - e.t), td[1], td[2], td[3], tf[1], tf[2], tf[3]) end
        if e.brk then
            local c = e.own and THEME.danger or tf
            GameTooltip:AddDoubleLine("BROKEN BY", SeatLabel(m, e.brk, true) .. (e.own and "  (own team)" or ""), td[1], td[2], td[3], c[1], c[2], c[3])
        end
    end
    if e.kind == "DISPEL" then
        if e.by then GameTooltip:AddDoubleLine("CAST", e.by, td[1], td[2], td[3], tf[1], tf[2], tf[3]) end
        local c = e.x == "PURGE" and THEME.statUtil or THEME.statCleanse
        GameTooltip:AddDoubleLine("KIND", e.x == "PURGE" and (e.inf and "OFFENSIVE · SHATTERED" or "OFFENSIVE") or "DEFENSIVE",
            td[1], td[2], td[3], c[1], c[2], c[3])
    end
    GameTooltip:AddLine("Click to move the cursor here", THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3])
    GameTooltip:Show()
end

local function BuildFeed(parent, y)
    feed.title = MakeText(parent, THEME.fontSizeSmall, "LEFT")
    feed.title:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD + 2, y)
    feed.title:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    feed.title:SetText("MOMENTS")
    feed.count = MakeText(parent, THEME.fontSizeSmall, "RIGHT")
    feed.count:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD - 2, y)
    feed.count:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    feed.frame = CreateFrame("Frame", nil, parent)
    feed.frame:SetHeight(FEED_ROWS * ROW_H)
    feed.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y - ROW_H)
    feed.frame:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
    feed.frame:EnableMouseWheel(true)
    feed.frame:SetScript("OnMouseWheel", function(_, delta)
        -- The wheel steps the cursor to the previous / next moment
        local m = Match()
        if not m or m.ledgerN == 0 then return end
        local t = Cursor(m)
        local idx = A.LedgerIndexAt(m, t)
        local target
        if delta > 0 then
            local j = idx - 1
            while j >= 1 and m.ledger[j].t >= t do j = j - 1 end
            target = m.ledger[j]
        else
            local j = idx
            while j <= m.ledgerN and m.ledger[j].t <= t do j = j + 1 end
            target = m.ledger[j]
        end
        if target then
            SetCursor(m, target.t)
            view.playing = false
            RepaintAll()
        end
    end)
    feed.rows = {}
    for i = 1, FEED_ROWS do
        local row = CreateFrame("Button", nil, feed.frame)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", feed.frame, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", feed.frame, "RIGHT", 0, 0)
        row.ledgerRow = i
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetTexture(WHITE)
        row.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
        row.hover:SetAllPoints()
        row.now = row:CreateTexture(nil, "BACKGROUND")
        row.now:SetTexture(WHITE)
        row.now:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.14)
        row.now:SetAllPoints()
        row.now:Hide()
        row.team = row:CreateTexture(nil, "ARTWORK")
        row.team:SetTexture(WHITE)
        row.team:SetWidth(2)
        row.team:SetPoint("TOPLEFT")
        row.team:SetPoint("BOTTOMLEFT")
        row.team:Hide()
        row.time = MakeText(row, THEME.fontSizeSmall, "RIGHT")
        row.time:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.time:SetWidth(38)
        row.time:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        row.who = MakeText(row, THEME.fontSizeSmall, "LEFT")
        row.who:SetPoint("LEFT", row, "LEFT", 48, 0)
        row.who:SetWidth(84)
        row.text = MakeText(row, THEME.fontSizeSmall, "LEFT")
        row.text:SetPoint("LEFT", row, "LEFT", 136, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row:SetScript("OnClick", FeedRowClick)
        row:SetScript("OnEnter", FeedRowEnter)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        feed.rows[i] = row
    end
end

-- ---------------------------------------------------------------------------
-- The dispel log: a drawer right of the replay, every dispel cast by cast
-- ---------------------------------------------------------------------------

-- Each cast is a header line (when, who, what they pressed, how much it
-- took) with its removals under it in the order the log reported them:
-- the aura, whom it came off, and what kind of removal it was. Lines past
-- the cursor dim like the moments feed; the cast at the cursor is lit; a
-- click moves the cursor to that cast. The list follows the cursor until
-- the wheel scrolls it, and follows again the moment the cursor moves.

local flat = {}             -- pooled line descriptors { kind, c, h }
local tallyScratch = {}

local function HitTag(h)
    if h.r then
        return Esc(THEME.danger) .. ((h.r == "FAIL" or h.r == "RESIST") and "RESISTED" or h.r) .. "|r"
    end
    if h.inf then return Esc(THEME.accent) .. "SHATTER|r" end
    if h.off then return Esc(THEME.statUtil) .. (h.steal and "STEAL" or "PURGE") .. "|r" end
    return Esc(THEME.statCleanse) .. "DISPEL|r"
end

local function HitKind(h)
    if h.r then return "TOOK NOTHING · " .. ((h.r == "FAIL" or h.r == "RESIST") and "RESISTED" or h.r), THEME.danger end
    if h.inf then return "OFFENSIVE · SHATTERED BY MASS DISPEL", THEME.accent end
    if h.off then return h.steal and "OFFENSIVE · STOLEN" or "OFFENSIVE · PURGED", THEME.statUtil end
    return "DEFENSIVE · DISPELLED", THEME.statCleanse
end

local function CastCounts(c)
    local off, def, miss = 0, 0, 0
    for _, h in ipairs(c.hits) do
        if h.r then miss = miss + 1 elseif h.off then off = off + 1 else def = def + 1 end
    end
    return off, def, miss
end

local function DispelHitShown(h)
    if h.off == nil then return view.dlogOff or view.dlogDef end
    if h.off then return view.dlogOff end
    return view.dlogDef
end

local function DispelCastShown(m, c)
    local seat = c.src and m.seats[c.src]
    local team = seat and seat.team
    if team == "us" then return view.dlogUs end
    if team == "them" then return view.dlogThem end
    return view.dlogUs and view.dlogThem
end

-- The log as display lines, filters applied. A cast whose every removal is
-- filtered out goes too; a cast that took nothing at all stays (a Mass
-- Dispel into nothing is worth seeing). Returns the line count.
local function FlattenDispelLog(m)
    local n = 0
    local log, count = A.DispelLog(m)
    local function Line(kind, c, h)
        n = n + 1
        local d = flat[n]
        if not d then d = {}; flat[n] = d end
        d.kind, d.c, d.h = kind, c, h
    end
    for i = 1, count do
        local c = log[i]
        if DispelCastShown(m, c) then
            local first = n
            Line("cast", c, nil)
            local shown = 0
            for _, h in ipairs(c.hits) do
                if DispelHitShown(h) then
                    shown = shown + 1
                    Line("hit", c, h)
                end
            end
            if c.more and c.more > 0 and shown > 0 then Line("more", c, nil) end
            if shown == 0 and (#c.hits > 0 or not (view.dlogOff or view.dlogDef)) then n = first end
        end
    end
    for i = n + 1, #flat do flat[i].c, flat[i].h = nil, nil end
    return n
end

local function DispelLineClick(self)
    local m = Match()
    local d = self.desc
    if not (m and d and d.c) then return end
    SetCursor(m, d.c.t)
    view.playing = false
    view.dlogFollow = true
    RepaintAll()
end

local function DispelLineEnter(self)
    local m = Match()
    local d = self.desc
    if not (m and d and d.c) then return end
    local c, h = d.c, d.h
    local td, tf = THEME.tipDim, THEME.tipFaint
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local id = (h and h.id) or (not h and c.id) or nil
    local shown = false
    if id and GameTooltip.SetSpellByID then shown = pcall(GameTooltip.SetSpellByID, GameTooltip, id) end
    if not shown then
        GameTooltip:SetText((h and h.name) or c.name or "Dispel", THEME.tipText[1], THEME.tipText[2], THEME.tipText[3])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("AT", GateTime(m, c.t), td[1], td[2], td[3], tf[1], tf[2], tf[3])
    GameTooltip:AddDoubleLine("BY", (c.src and SeatLabel(m, c.src, true) or "?") .. (c.pet and ("'s " .. c.pet) or ""),
        td[1], td[2], td[3], tf[1], tf[2], tf[3])
    GameTooltip:AddDoubleLine("CAST", c.name or "?", td[1], td[2], td[3], tf[1], tf[2], tf[3])
    if h then
        if h.dst or h.dn or h.pet then
            local who = h.dst and SeatLabel(m, h.dst, true) or (h.pet or h.dn or "?")
            if h.dst and h.pet then who = h.pet .. " (" .. who .. ")" end
            GameTooltip:AddDoubleLine(h.off and "OFF" or "ON", who, td[1], td[2], td[3], tf[1], tf[2], tf[3])
        end
        local kind, kc = HitKind(h)
        GameTooltip:AddDoubleLine("KIND", kind, td[1], td[2], td[3], kc[1], kc[2], kc[3])
        if h.inf then
            GameTooltip:AddLine("Read off the shield's fade: Mass Dispel breaks an immunity with an effect the combat log never reports as a dispel, so the shield fading as the Mass Dispel landed is the record.",
                THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3], true)
        end
    else
        local off, def, miss = CastCounts(c)
        GameTooltip:AddDoubleLine("OFFENSIVE", tostring(off), td[1], td[2], td[3], THEME.statUtil[1], THEME.statUtil[2], THEME.statUtil[3])
        GameTooltip:AddDoubleLine("DEFENSIVE", tostring(def), td[1], td[2], td[3], THEME.statCleanse[1], THEME.statCleanse[2], THEME.statCleanse[3])
        if miss > 0 then GameTooltip:AddDoubleLine("TOOK NOTHING", tostring(miss), td[1], td[2], td[3], THEME.danger[1], THEME.danger[2], THEME.danger[3]) end
        if c.more then GameTooltip:AddLine(format("…and %d more the log kept no room for", c.more), tf[1], tf[2], tf[3]) end
    end
    GameTooltip:AddLine("Click to move the cursor here", THEME.tipHint[1], THEME.tipHint[2], THEME.tipHint[3])
    GameTooltip:Show()
end

local function SetChip(chip, on)
    local c = on and THEME.accent or THEME.textDim
    chip.text:SetTextColor(c[1], c[2], c[3])
    chip.under:SetShown(on)
end

local CHIP_TIPS = {
    us = { "Ours", "Show your team's dispels." },
    them = { "Theirs", "Show the enemy team's dispels." },
    off = { "Offensive", "Purges, steals and Mass Dispel's shattered shields: a BUFF taken off an enemy." },
    def = { "Defensive", "Dispels that freed a teammate: a DEBUFF taken off a friend." },
}
local CHIP_FIELD = { us = "dlogUs", them = "dlogThem", off = "dlogOff", def = "dlogDef" }

local function BuildDispelLog()
    local f = CreateFrame("Frame", nil, root)
    dlog.frame = f
    f:SetWidth(DLOG_W)
    f:SetPoint("TOPLEFT", root, "TOPLEFT", W, -HEAD_H)
    f:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", W, 0)
    f.fill = MakeFill(f, { 0, 0, 0, 0.25 })
    local edge = f:CreateTexture(nil, "BORDER")
    edge:SetTexture(WHITE)
    edge:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], 1)
    edge:SetWidth(1)
    edge:SetPoint("TOPLEFT")
    edge:SetPoint("BOTTOMLEFT")
    dlog.title = MakeText(f, THEME.fontSizeSmall, "LEFT")
    dlog.title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    dlog.title:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    dlog.title:SetText("DISPEL LOG")
    dlog.count = MakeText(f, THEME.fontSizeSmall, "RIGHT")
    dlog.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -3)
    dlog.count:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    -- Filter chips: whose casts, which side of a dispel
    dlog.chips = {}
    local x = 4
    for _, key in ipairs({ "us", "them", "off", "def" }) do
        local chip = CreateFrame("Button", nil, f)
        chip.chip = key
        chip:SetHeight(ROW_H)
        local label = key == "us" and "OURS" or key == "them" and "THEIRS" or key == "off" and "OFFENSIVE" or "DEFENSIVE"
        local w = key == "us" and 44 or key == "them" and 52 or 74
        chip:SetWidth(w)
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(ROW_H + 3))
        x = x + w + (key == "them" and 14 or 2)
        chip.text = MakeText(chip, THEME.fontSizeSmall, "CENTER")
        chip.text:SetAllPoints()
        chip.text:SetText(label)
        chip.under = chip:CreateTexture(nil, "ARTWORK")
        chip.under:SetTexture(WHITE)
        chip.under:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
        chip.under:SetHeight(1)
        chip.under:SetPoint("BOTTOMLEFT", chip, "BOTTOMLEFT", 6, 0)
        chip.under:SetPoint("BOTTOMRIGHT", chip, "BOTTOMRIGHT", -6, 0)
        chip.hover = chip:CreateTexture(nil, "HIGHLIGHT")
        chip.hover:SetTexture(WHITE)
        chip.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
        chip.hover:SetAllPoints()
        chip:SetScript("OnClick", function(self)
            local field = CHIP_FIELD[self.chip]
            view[field] = not view[field]
            RepaintAll()
        end)
        local tip = CHIP_TIPS[key]
        Commander.UI.AttachTooltip(chip, tip[1], tip[2] .. " Click to show or hide.")
        dlog.chips[key] = chip
    end
    -- The tally: one row per seat, as of the cursor
    local tally = CreateFrame("Button", nil, f)
    dlog.tally = tally
    tally:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(ROW_H * 2 + 8))
    tally:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    tally:SetHeight(ROW_H * (MAX_SEATS * 2 + 1))
    Commander.UI.AttachTooltip(tally, "Dispels per seat", "As of the cursor. OFF: buffs they took off an enemy (purges, steals, shattered shields). DEF: debuffs they took off a teammate. MISS: dispels that took nothing (resisted, immune). LOST: their buffs the other team purged. FREED: their debuffs their team dispelled.")
    tally.head = MakeText(tally, THEME.fontSizeSmall, "LEFT")
    tally.head:SetPoint("TOPLEFT", tally, "TOPLEFT", 2, 0)
    tally.head:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    tally.head:SetText("SEAT")
    tally.cols = {}
    local cx = DLOG_W - 8 - 2
    for k = #DLOG_TALLY, 1, -1 do
        local spec = DLOG_TALLY[k]
        local fs = MakeText(tally, THEME.fontSizeSmall, "RIGHT")
        fs:SetPoint("TOPRIGHT", tally, "TOPLEFT", cx, 0)
        fs:SetWidth(spec[4])
        local col = THEME[spec[3]] or THEME.text
        fs:SetTextColor(col[1], col[2], col[3])
        fs:SetText(spec[2])
        tally.cols[k] = fs
        cx = cx - spec[4]
    end
    tally.rows = {}
    for r = 1, MAX_SEATS * 2 do
        local row = CreateFrame("Frame", nil, tally)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", tally, "TOPLEFT", 0, -(r * ROW_H))
        row:SetPoint("RIGHT", tally, "RIGHT", 0, 0)
        row.team = row:CreateTexture(nil, "ARTWORK")
        row.team:SetTexture(WHITE)
        row.team:SetWidth(2)
        row.team:SetPoint("TOPLEFT")
        row.team:SetPoint("BOTTOMLEFT")
        row.name = MakeText(row, THEME.fontSizeSmall, "LEFT")
        row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.name:SetWidth(DLOG_W - 8 - 6 - 190)
        row.cols = {}
        local rx = DLOG_W - 8 - 2
        for k = #DLOG_TALLY, 1, -1 do
            local spec = DLOG_TALLY[k]
            local fs = MakeText(row, THEME.fontSizeSmall, "RIGHT")
            fs:SetPoint("RIGHT", row, "LEFT", rx, 0)
            fs:SetWidth(spec[4])
            row.cols[k] = fs
            rx = rx - spec[4]
        end
        tally.rows[r] = row
    end
    -- The log itself
    local list = CreateFrame("Frame", nil, f)
    dlog.list = list
    list:SetPoint("LEFT", f, "LEFT", 1, 0)
    list:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    list:SetPoint("BOTTOM", f, "BOTTOM", 0, 4)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        view.dlogOffset = max(0, view.dlogOffset - delta * 3)
        view.dlogFollow = false
        view.dlogFollowT = view.t
        RepaintAll()
    end)
    dlog.lines = {}
    for i = 1, DLOG_LINES_MAX do
        local row = CreateFrame("Button", nil, list)
        row.dlogLine = i
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", list, "RIGHT", 0, 0)
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetTexture(WHITE)
        row.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
        row.hover:SetAllPoints()
        row.now = row:CreateTexture(nil, "BACKGROUND")
        row.now:SetTexture(WHITE)
        row.now:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.14)
        row.now:SetAllPoints()
        row.now:Hide()
        row.team = row:CreateTexture(nil, "ARTWORK")
        row.team:SetTexture(WHITE)
        row.team:SetWidth(2)
        row.team:SetPoint("TOPLEFT")
        row.team:SetPoint("BOTTOMLEFT")
        row.time = MakeText(row, THEME.fontSizeSmall, "RIGHT")
        row.time:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.time:SetWidth(32)
        row.time:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(12, 12)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.text = MakeText(row, THEME.fontSizeSmall, "LEFT")
        row.text:SetPoint("RIGHT", row, "RIGHT", -(DLOG_TAG_W + 4), 0)
        row.tag = MakeText(row, THEME.fontSizeSmall, "RIGHT")
        row.tag:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.tag:SetWidth(DLOG_TAG_W)
        row:SetScript("OnClick", DispelLineClick)
        row:SetScript("OnEnter", DispelLineEnter)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        dlog.lines[i] = row
    end
end

-- Open or close the drawer: the window widens by it, the content column
-- never moves
local function ApplyDrawer()
    if not built then return end
    root:SetWidth(view.dlog and (W + DLOG_W) or W)
    dlog.frame:SetShown(view.dlog)
    local c = view.dlog and THEME.accent or THEME.text
    dlogBtn.text:SetTextColor(c[1], c[2], c[3])
end

local function DlogLayout(rows, rootH)
    if not dlog.frame then return end
    local seatRows = min(rows * 2, MAX_SEATS * 2)
    dlog.seatRows = seatRows
    dlog.tally:SetHeight(ROW_H * (seatRows + 1))
    local top = ROW_H * 2 + 8 + ROW_H * (seatRows + 1) + 4
    dlog.list:SetPoint("TOP", dlog.frame, "TOP", 0, -top)
    local h = rootH - HEAD_H - top - 4
    dlog.visible = max(min(floor(h / ROW_H), DLOG_LINES_MAX), 1)
end

local function RepaintDispelLog(m, t, atEnd)
    if not view.dlog or not dlog.frame then return end
    for key, chip in pairs(dlog.chips) do SetChip(chip, view[CHIP_FIELD[key]]) end
    -- A different match starts at its top, following
    if dlog.forMatch ~= m then
        dlog.forMatch = m
        view.dlogOffset = 0
        view.dlogFollow = true
    end
    local tally = dlog.tally
    local rowsShown = 0
    if m then
        A.DispelTallyAt(m, (not atEnd) and t or nil, tallyScratch)
        for _, teamKey in ipairs({ "us", "them" }) do
            local tm = m.teams[teamKey]
            for i = 1, tm.n do
                local seat = m.seats[tm.order[i]]
                if seat and rowsShown < (dlog.seatRows or 0) then
                    rowsShown = rowsShown + 1
                    local row = tally.rows[rowsShown]
                    local tc = teamKey == "us" and THEME.teamUs or THEME.teamThem
                    row.team:SetVertexColor(tc[1], tc[2], tc[3], 1)
                    row.name:SetText(SeatLabel(m, seat.guid))
                    local rec = tallyScratch[seat.guid]
                    for k, spec in ipairs(DLOG_TALLY) do
                        local v = rec and rec[spec[1]] or 0
                        local fs = row.cols[k]
                        fs:SetText(tostring(v))
                        local c = v > 0 and (THEME[spec[3]] or THEME.text) or THEME.textDim
                        fs:SetTextColor(c[1], c[2], c[3], v > 0 and 1 or 0.45)
                    end
                    row:Show()
                end
            end
        end
    end
    for r = rowsShown + 1, #tally.rows do tally.rows[r]:Hide() end

    local lines = dlog.lines
    if not m then
        dlog.count:SetText("")
        for i = 1, #lines do lines[i].desc = nil; lines[i]:Hide() end
        return
    end
    local log, logN = A.DispelLog(m)
    local total = FlattenDispelLog(m)
    local V = dlog.visible or 1
    -- The cast at the cursor: the last one at or before it
    local nowLine, castsSoFar = 0, 0
    for i = 1, total do
        local d = flat[i]
        if d.kind == "cast" and d.c.t <= t + 0.001 then nowLine = i end
    end
    for i = 1, logN do
        if log[i].t <= t + 0.001 then castsSoFar = i else break end
    end
    dlog.count:SetText(atEnd and format("%d casts", logN) or format("%d of %d", castsSoFar, logN))
    if not view.dlogFollow and view.t ~= view.dlogFollowT then view.dlogFollow = true end
    local maxOff = max(total - V, 0)
    if view.dlogFollow then
        if atEnd and IsLive(m) then
            view.dlogOffset = maxOff            -- live: the newest at the bottom
        elseif atEnd then
            view.dlogOffset = 0                 -- a finished match reads from the gates
        else
            view.dlogOffset = max(nowLine - floor(V / 3), 0)
        end
    end
    if view.dlogOffset > maxOff then view.dlogOffset = maxOff end
    local off = view.dlogOffset
    for i = 1, #lines do
        local row = lines[i]
        local d = (i <= V) and flat[i + off] or nil
        if d and i + off <= total then
            row.desc = d
            local c, h = d.c, d.h
            local seat = c.src and m.seats[c.src]
            row.icon:ClearAllPoints()
            row.text:ClearAllPoints()
            row.text:SetPoint("RIGHT", row, "RIGHT", -(DLOG_TAG_W + 4), 0)
            if d.kind == "cast" then
                row.time:SetText(GateTime(m, c.t))
                if seat then
                    local tc = seat.team == "us" and THEME.teamUs or THEME.teamThem
                    row.team:SetVertexColor(tc[1], tc[2], tc[3], 1)
                    row.team:Show()
                else
                    row.team:Hide()
                end
                row.icon:SetPoint("LEFT", row, "LEFT", 38, 0)
                row.icon:SetTexture(U.IconOf(c))
                row.icon:SetAlpha(1)
                row.icon:Show()
                row.text:SetPoint("LEFT", row, "LEFT", 54, 0)
                row.text:SetText((c.src and SeatLabel(m, c.src) or (ESC.dim .. "?|r"))
                    .. (c.pet and (ESC.dim .. " · " .. c.pet .. "|r") or "") .. "  " .. (c.name or "Dispel"))
                local o, df, miss = CastCounts(c)
                local n = o + df
                if n == 0 then
                    row.tag:SetText(Esc(THEME.danger) .. (miss > 0 and "missed" or "took nothing") .. "|r")
                else
                    row.tag:SetText(ESC.dim .. format("%d removed", n) .. "|r")
                end
                row.now:SetShown((not atEnd) and (i + off) == nowLine)
            elseif d.kind == "hit" then
                row.time:SetText("")
                row.team:Hide()
                row.icon:SetPoint("LEFT", row, "LEFT", 54, 0)
                row.icon:SetTexture(U.IconOf(h.id and h or c))
                row.icon:SetAlpha(h.r and 0.5 or 1)
                row.icon:Show()
                row.text:SetPoint("LEFT", row, "LEFT", 70, 0)
                local who = (h.dst or h.pet or h.dn) and DispelTarget(m, h.dst, h.pet, h.dn) or nil
                row.text:SetText((h.name and (Esc(THEME.text) .. h.name .. "|r") or "")
                    .. (who and (ESC.dim .. (h.name and " → " or "→ ") .. "|r" .. who) or ""))
                row.tag:SetText(HitTag(h))
                row.now:Hide()
            else
                row.time:SetText("")
                row.team:Hide()
                row.icon:Hide()
                row.text:SetPoint("LEFT", row, "LEFT", 70, 0)
                row.text:SetText(ESC.dim .. format("…and %d more", c.more or 0) .. "|r")
                row.tag:SetText("")
                row.now:Hide()
            end
            row:SetAlpha(c.t > t + 0.001 and 0.45 or 1)
            row:Show()
        else
            row.desc = nil
            row.now:Hide()
            row:Hide()
        end
    end
    if total == 0 then
        local row = lines[1]
        row.desc = nil
        row.time:SetText("")
        row.team:Hide()
        row.icon:Hide()
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -(DLOG_TAG_W + 4), 0)
        row.text:SetText(ESC.dim .. (logN > 0 and "Nothing matches the filters" or "No dispels yet") .. "|r")
        row.tag:SetText("")
        row.now:Hide()
        row:SetAlpha(1)
        row:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Sidebar: the match history, newest first, the live match on top
-- ---------------------------------------------------------------------------

local SIDE_ROWS_MAX = 40

local function SelectMatch(sel)
    view.sel = sel
    view.t = nil
    view.playing = false
    RepaintAll()
end

BuildSidebar = function()
    side.frame = CreateFrame("Frame", nil, root)
    side.frame:SetWidth(SIDEBAR_W)
    side.frame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEAD_H)
    side.frame:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
    side.frame.fill = MakeFill(side.frame, { 0, 0, 0, 0.25 })
    side.edge = side.frame:CreateTexture(nil, "BORDER")
    side.edge:SetTexture(WHITE)
    side.edge:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], 1)
    side.edge:SetWidth(1)
    side.edge:SetPoint("TOPRIGHT")
    side.edge:SetPoint("BOTTOMRIGHT")
    side.title = MakeText(side.frame, THEME.fontSizeSmall, "LEFT")
    side.title:SetPoint("TOPLEFT", side.frame, "TOPLEFT", 6, -3)
    side.title:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    side.title:SetText("MATCHES")
    side.count = MakeText(side.frame, THEME.fontSizeSmall, "RIGHT")
    side.count:SetPoint("TOPRIGHT", side.frame, "TOPRIGHT", -6, -3)
    side.count:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    side.list = CreateFrame("Frame", nil, side.frame)
    side.list:SetPoint("TOPLEFT", side.frame, "TOPLEFT", 0, -ROW_H - 2)
    side.list:SetPoint("BOTTOMRIGHT", side.frame, "BOTTOMRIGHT", -1, ROW_H)
    side.list:EnableMouseWheel(true)
    side.list:SetScript("OnMouseWheel", function(_, delta)
        view.sideOffset = max(0, view.sideOffset - delta)
        RepaintAll()
    end)
    side.rows = {}
    for i = 1, SIDE_ROWS_MAX do
        local row = CreateFrame("Button", nil, side.list)
        row.sideRow = i
        row:SetHeight(SIDE_ROW_H)
        row:SetPoint("TOPLEFT", side.list, "TOPLEFT", 0, -(i - 1) * SIDE_ROW_H)
        row:SetPoint("RIGHT", side.list, "RIGHT", 0, 0)
        row.hover = row:CreateTexture(nil, "HIGHLIGHT")
        row.hover:SetTexture(WHITE)
        row.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
        row.hover:SetAllPoints()
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetTexture(WHITE)
        row.sel:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.14)
        row.sel:SetAllPoints()
        row.sel:Hide()
        row.stripe = row:CreateTexture(nil, "ARTWORK")
        row.stripe:SetTexture(WHITE)
        row.stripe:SetWidth(3)
        row.stripe:SetPoint("TOPLEFT")
        row.stripe:SetPoint("BOTTOMLEFT")
        row.stripe:Hide()
        row.line1 = MakeText(row, THEME.fontSizeSmall, "LEFT")
        row.line1:SetHeight(13)
        row.line1:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -1)
        row.line1:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.line2 = MakeText(row, 9, "LEFT")
        row.line2:SetHeight(11)
        row.line2:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 2)
        row.line2:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.line2:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
        row:SetScript("OnClick", function(self)
            if self.matchSel ~= nil then SelectMatch(self.matchSel) end
        end)
        row:Hide()
        side.rows[i] = row
    end
    -- The foot: the running record over the kept matches
    side.foot = MakeText(side.frame, THEME.fontSizeSmall, "LEFT")
    side.foot:SetPoint("BOTTOMLEFT", side.frame, "BOTTOMLEFT", 6, 3)
    side.foot:SetPoint("RIGHT", side.frame, "RIGHT", -4, 0)
    side.foot:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
end

local historyScratch = {}

local function RepaintSidebar(current)
    local list = A.GetMatches()
    local live = A.Live()
    local total = #list + (live and 1 or 0)
    side.count:SetText(total > 0 and tostring(total) or "")
    local visible = min(side.visible or 12, SIDE_ROWS_MAX)
    local maxOff = max(0, total - visible)
    if view.sideOffset > maxOff then view.sideOffset = maxOff end
    local off = view.sideOffset
    for i = 1, SIDE_ROWS_MAX do
        local row = side.rows[i]
        local k = i + off
        local m, sel
        if i <= visible and k <= total then
            if live and k == 1 then m, sel = live, "live" else m = list[k - (live and 1 or 0)]; sel = m and m.id end
        end
        if m then
            row.matchSel = sel
            local size = m.bracket > 0 and (m.bracket .. "v" .. m.bracket) or "?v?"
            row.line1:SetText(size .. ESC.dim .. "  " .. (m.map or "Arena"):upper() .. "|r")
            local when = date("%b %d %H:%M", m.tsStart)
            if IsLive(m) then
                row.line2:SetText(Esc(THEME.accent) .. "LIVE|r  " .. ESC.dim .. when .. "|r")
            else
                row.line2:SetText(Esc(ResultColor(m)) .. ResultText(m) .. "|r  " .. ESC.dim .. FmtTime(m.dur) .. "  " .. when .. "|r")
            end
            local on = (m == current)
            row.sel:SetShown(on)
            local sc = ResultColor(m)
            row.stripe:SetVertexColor(sc[1], sc[2], sc[3], 1)
            row.stripe:Show()
            row:Show()
        else
            row.matchSel = nil
            row:Hide()
        end
    end
    if #list > 0 then
        A.History(list, historyScratch)
        local rec
        for i = 1, historyScratch.n do
            if historyScratch[i].kind == "RECORD" then rec = historyScratch[i]; break end
        end
        if rec then
            side.foot:SetText(format("%s%d W|r %s%d L|r%s", Esc(THEME.healTx), rec.wins, Esc(THEME.danger), rec.losses,
                rec.left > 0 and (ESC.dim .. format("  %d left|r", rec.left)) or ""))
        else
            side.foot:SetText("")
        end
    else
        side.foot:SetText(ESC.dim .. "no matches yet|r")
    end
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

local function BuildWindow()
    root = CreateFrame("Frame", "CommanderMetersArenaFrame", UIParent)
    root:SetSize(W, 600)
    root:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    root:SetFrameStrata("DIALOG")
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    root.fill = MakeFill(root, THEME.bg)
    MakeEdge(root)
    root:Hide()
    tinsert(UISpecialFrames, "CommanderMetersArenaFrame")

    head = CreateFrame("Frame", nil, root)
    head:SetHeight(HEAD_H)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head.fill = MakeFill(head, THEME.chrome)
    local rule = head:CreateTexture(nil, "BORDER")
    rule:SetTexture(WHITE)
    rule:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.5)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() root:StartMoving() end)
    head:SetScript("OnDragStop", function() root:StopMovingOrSizing() end)
    head.title = MakeText(head, THEME.fontSize, "LEFT")
    head.title:SetPoint("LEFT", head, "LEFT", 6, 0)
    head.title:SetWidth(96)
    head.title:SetText("ARENA REPLAY")
    head.title:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])

    matchBtn = U.MakeHeaderButton(head, "LEFT")
    matchBtn.headerRole = "arenaMatch"
    matchBtn:SetPoint("LEFT", head.title, "RIGHT", 0, 0)
    matchBtn:SetScript("OnClick", function(self) OpenMenu(MatchMenu, self) end)
    Commander.UI.AttachTooltip(matchBtn, "Match", "Which match the replay reads. Click for the live match and every kept one (newest first).")

    local close = MakeGlyphButton(head, "close")
    close:SetSize(16, 16)
    close:SetPoint("RIGHT", head, "RIGHT", -2, 0)
    close:SetScript("OnClick", function() root:Hide() end)
    shareBtn = MakeGlyphButton(head, "share")
    shareBtn.headerRole = "arenaShare"
    shareBtn:SetSize(16, 16)
    shareBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    shareBtn:SetScript("OnClick", function(self) OpenMenu(ArenaShareMenu, self) end)
    Commander.UI.AttachTooltip(shareBtn, "Share", "Report this match — both teams' damage and healing as of the cursor, and first blood — to a chat channel. Nothing is ever sent automatically.")
    dlogBtn = U.MakeHeaderButton(head, "CENTER")
    dlogBtn.headerRole = "arenaDispels"
    dlogBtn:SetWidth(62)
    dlogBtn:SetPoint("RIGHT", shareBtn, "LEFT", -4, 0)
    dlogBtn.text:SetText("DISPELS")
    dlogBtn:SetScript("OnClick", function()
        view.dlog = not view.dlog
        local db = U.DB and U.DB()
        if db then db.ArenaDispelLog = view.dlog end
        ApplyDrawer()
        RepaintAll()
    end)
    Commander.UI.AttachTooltip(dlogBtn, "Dispel Log", "Every dispel of the match, cast by cast — who pressed what, and which auras it took off whom, offensive and defensive, Mass Dispel's shattered shields included — with a per-seat tally. Read as of the cursor. Click to show or hide the drawer.")
    matchBtn:SetPoint("RIGHT", dlogBtn, "LEFT", 0, 0)

    -- The content column sits right of the sidebar; every band anchors to
    -- it, so the sidebar's width is the one number that places them
    -- (a fixed width, not the root's right edge: the dispel log drawer
    -- widens the window and must never stretch the replay)
    content = CreateFrame("Frame", nil, root)
    content:SetPoint("TOPLEFT", root, "TOPLEFT", SIDEBAR_W, 0)
    content:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", SIDEBAR_W, 0)
    content:SetWidth(CONTENT_W)
    BuildSidebar()
    BuildDispelLog()

    local y = -(HEAD_H + PAD)
    sumText = MakeText(content, THEME.fontSizeSmall, "LEFT")
    sumText:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + 2, y)
    sumText:SetPoint("RIGHT", content, "RIGHT", -PAD - 2, 0)
    sumText:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    y = y - (SUM_H + PAD)
    BuildTeams(content, y)
    -- The versus bar under the two team heads
    vsBar.track = CreateFrame("Frame", nil, content)
    vsBar.track:SetHeight(2)
    vsBar.track:SetPoint("TOPLEFT", teams[1], "TOPLEFT", 0, -TEAM_HEAD_H)
    vsBar.track:SetPoint("RIGHT", teams[2], "RIGHT", 0, 0)
    vsBar.fill = MakeFill(vsBar.track, THEME.barBack)
    vsBar.us = vsBar.track:CreateTexture(nil, "ARTWORK")
    vsBar.us:SetTexture(WHITE)
    vsBar.us:SetVertexColor(THEME.teamUs[1], THEME.teamUs[2], THEME.teamUs[3], 0.9)
    vsBar.us:SetPoint("TOPLEFT")
    vsBar.us:SetPoint("BOTTOMLEFT")
    vsBar.them = vsBar.track:CreateTexture(nil, "ARTWORK")
    vsBar.them:SetTexture(WHITE)
    vsBar.them:SetVertexColor(THEME.teamThem[1], THEME.teamThem[2], THEME.teamThem[3], 0.9)
    vsBar.them:SetPoint("TOPRIGHT")
    vsBar.them:SetPoint("BOTTOMRIGHT")

    -- Bands below the teams, positioned by Layout() once the bracket is known
    local function Band(h)
        local f = CreateFrame("Frame", nil, content)
        f:SetHeight(h)
        f:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        f:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        return f
    end
    bands.timeline = Band(PLOT_H + AXIS_H)
    bands.meters = Band(ROW_H * (MAX_SEATS + 1))
    bands.feed = Band(FEED_H)
    BuildTimeline(bands.timeline, 0)
    BuildMeters(bands.meters, 0)
    BuildFeed(bands.feed, 0)

    hint = MakeText(content, THEME.fontSizeSmall, "CENTER")
    hint:SetPoint("BOTTOM", content, "BOTTOM", 0, 2)
    hint:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
    hint:SetText(Esc(THEME.statDeath) .. "DEATH|r " .. Esc(THEME.statCC) .. "CONTROL|r " .. Esc(THEME.statUtil) .. "KICK|r "
        .. Esc(THEME.statCd) .. "TRINKET|r   ·   DRAG THE TIMELINE TO SCRUB · CLICK A MOMENT TO JUMP · ESC CLOSES")

    root:SetScript("OnUpdate", function(_, elapsed)
        repaintAcc = repaintAcc + elapsed
        local m = Match()
        if view.playing and m then
            local speed = PLAY_SPEEDS[view.speedIndex] or 1
            local t = (view.t or 0) + elapsed * speed
            if t >= EndTime(m) then
                view.t = nil
                view.playing = false
            else
                view.t = t
            end
        end
        if view.dragging and m then
            if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
                view.dragging = false
            else
                CursorFromMouse(m)
            end
        end
        if plot.hovering and m then
            local pw = PlotWidth()
            local x = MouseX(plot.frame)
            if x >= 0 and x <= pw then
                local t0, span = PlotOrigin(m)
                plot.hover:ClearAllPoints()
                plot.hover:SetPoint("TOP", plot.frame, "TOPLEFT", x, 0)
                plot.hover:SetPoint("BOTTOM", plot.frame, "BOTTOMLEFT", x, 0)
                plot.hoverText:SetText(GateTime(m, t0 + x / pw * span))
                plot.hover:Show()
                plot.hoverText:Show()
            else
                plot.hover:Hide()
                plot.hoverText:Hide()
            end
        end
        local period = (view.playing or view.dragging) and 0.1 or 0.5
        if repaintAcc >= period then
            repaintAcc = 0
            RepaintAll()
        end
    end)
    root:SetScript("OnShow", function() repaintAcc = 1; RepaintAll() end)
    root:SetScript("OnHide", function() view.playing = false; view.dragging = false end)
    built = true
    local db = U.DB and U.DB()
    view.dlog = not (db and db.ArenaDispelLog == false)
    ApplyDrawer()
end

-- Seat rows per team: the bracket (or the larger roster seen), never
-- fewer than two, never more than five
local function BoardRows(m)
    if not m then return 2 end
    return min(max(m.bracket or 0, m.teams.us.n, m.teams.them.n, 2), MAX_SEATS)
end

local function Layout(rows)
    if layoutRows == rows then return end
    layoutRows = rows
    local teamH = TEAM_HEAD_H + 2 + rows * (CARD_H + CARD_GAP) - CARD_GAP
    for i = 1, 2 do teams[i]:SetHeight(teamH) end
    local y = -(HEAD_H + PAD + SUM_H + PAD + teamH + PAD)
    bands.timeline:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - (PLOT_H + AXIS_H + PAD)
    bands.meters:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - (ROW_H * (rows + 1) + PAD)
    bands.feed:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    y = y - (FEED_H + HINT_H + PAD)
    root:SetHeight(-y)
    side.visible = floor((-y - HEAD_H - ROW_H - ROW_H - 2) / SIDE_ROW_H)
    DlogLayout(rows, -y)
end

-- ---------------------------------------------------------------------------
-- Repaint
-- ---------------------------------------------------------------------------

local function RepaintHeader(m)
    matchBtn.text:SetText(MatchTitle(m))
    if not m then
        sumText:SetText("Queue for an arena, or /cm arenatest for a canned match to watch.")
        return
    end
    local parts = {}
    parts[#parts + 1] = m.tGates and ("GATES " .. FmtTime(m.tGates)) or "GATES ?"
    if m.firstBlood then
        parts[#parts + 1] = "FIRST BLOOD " .. GateTime(m, m.firstBlood.t) .. " " .. SeatLabel(m, m.firstBlood.guid)
    end
    local us, them = m.teams.us, m.teams.them
    local myBefore, myAfter, myChange = A.OurRating(m)
    if myChange and (m.teamless or not (us.ratingBefore and us.ratingAfter)) then
        -- A personal-rating season: YOUR number, the team has none
        local col = myChange >= 0 and THEME.healTx or THEME.danger
        local txt = myBefore and format("%d → %d (%+d)", myBefore, myAfter, myChange) or format("%+d", myChange)
        parts[#parts + 1] = format("%sRATING|r %s%s|r", Esc(THEME.teamUs), Esc(col), txt)
            .. (us.mmr and (ESC.dim .. format(" (MMR %d)|r", us.mmr)) or "")
        if them.mmr then parts[#parts + 1] = format("%sTHEM|r %sMMR %d|r", Esc(THEME.teamThem), ESC.dim, them.mmr) end
    else
        if us.ratingBefore and us.ratingAfter then
            parts[#parts + 1] = format("%sUS|r %d → %d", Esc(THEME.teamUs), us.ratingBefore, us.ratingAfter)
                .. (us.mmr and (ESC.dim .. format(" (MMR %d)|r", us.mmr)) or "")
        end
        if them.ratingBefore and them.ratingAfter then
            parts[#parts + 1] = format("%sTHEM|r %d → %d", Esc(THEME.teamThem), them.ratingBefore, them.ratingAfter)
                .. (them.mmr and (ESC.dim .. format(" (MMR %d)|r", them.mmr)) or "")
        end
    end
    if m.rated == true then parts[#parts + 1] = "RATED" elseif m.rated == false then parts[#parts + 1] = "SKIRMISH" end
    parts[#parts + 1] = date("%b %d %H:%M", m.tsStart)
    sumText:SetText(table.concat(parts, ESC.dim .. "  ·  |r"))
end

local function TeamHeadText(m, teamKey)
    local tm = m.teams[teamKey]
    local label = teamKey == "us" and "YOUR TEAM" or "ENEMY"
    if tm.name then label = label .. ESC.dim .. "  " .. tm.name:upper() .. "|r" end
    return label
end

local function SetIcon(btn, rec, text)
    btn.rec = rec
    btn.icon:SetTexture(IconTexture(rec))
    btn.text:SetText(text or "")
    btn:Show()
end

local function AuraTip(self, rec)
    local m = Match()
    if not m then return end
    local td, tf = THEME.tipDim, THEME.tipFaint
    local t = Cursor(m)
    GameTooltip:AddDoubleLine("APPLIED", GateTime(m, rec.t), td[1], td[2], td[3], tf[1], tf[2], tf[3])
    if rec.src then GameTooltip:AddDoubleLine("BY", SeatLabel(m, rec.src, true), td[1], td[2], td[3], tf[1], tf[2], tf[3]) end
    if rec.t2 then
        GameTooltip:AddDoubleLine("ENDS", GateTime(m, rec.t2) .. format("  (%.1fs left)", rec.t2 - t), td[1], td[2], td[3], tf[1], tf[2], tf[3])
    else
        GameTooltip:AddDoubleLine("ENDS", "still on", td[1], td[2], td[3], tf[1], tf[2], tf[3])
    end
end

local function CdTip(self, rec)
    local m = Match()
    if not m then return end
    local td, tf = THEME.tipDim, THEME.tipFaint
    GameTooltip:AddDoubleLine("PRESSED", GateTime(m, rec.t), td[1], td[2], td[3], tf[1], tf[2], tf[3])
    if self.left then
        GameTooltip:AddDoubleLine("READY IN", FmtTime(self.left), td[1], td[2], td[3], THEME.statCd[1], THEME.statCd[2], THEME.statCd[3])
    end
end

local function RepaintCard(card, m, seat, st, t, atEnd)
    card.guid = seat.guid
    card.portraitBtn.guid = seat.guid
    local c = ClassColor(seat.class)
    -- Portrait
    local coords = seat.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[seat.class]
    if coords then
        card.portrait:SetTexture(CLASS_RING)
        card.portrait:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        card.portraitFallback:Hide()
    else
        card.portrait:SetTexture(WHITE)
        card.portrait:SetTexCoord(0, 1, 0, 1)
        card.portraitFallback:SetText((seat.class or "?"):sub(1, 1))
        card.portraitFallback:SetTextColor(c[1], c[2], c[3])
        card.portraitFallback:Show()
    end
    card.portrait:Show()
    local dead = st and not st.alive
    local cc = st and st.ccN > 0 and st.cc[1] or nil
    if dead then
        card.portrait:SetVertexColor(0.35, 0.35, 0.35, 1)
        card.ring:SetVertexColor(THEME.danger[1], THEME.danger[2], THEME.danger[3], 1)
        card.ccIcon:Hide()
        card.state:SetText(Esc(THEME.danger) .. "DEAD|r")
    elseif cc then
        card.portrait:SetVertexColor(coords and 0.55 or c[1] * 0.35, coords and 0.55 or c[2] * 0.35, coords and 0.55 or c[3] * 0.35, 1)
        card.ring:SetVertexColor(THEME.statCC[1], THEME.statCC[2], THEME.statCC[3], 1)
        card.ccIcon:SetTexture(IconTexture(cc))
        card.ccIcon:Show()
        local left = (cc.t2 or (cc.t + 12)) - t
        -- The word under the portrait is a short one; the control's name,
        -- bracket and clock take the cast bar (a controlled player is not
        -- casting anyway)
        card.state:SetText(Esc(THEME.statCC) .. format("%.1fs|r", max(left, 0)))
    elseif st and st.feign then
        -- Feigning: on the floor, not dead — dimmed, and said so
        card.portrait:SetVertexColor(coords and 0.6 or c[1] * 0.25, coords and 0.6 or c[2] * 0.25, coords and 0.6 or c[3] * 0.25, 1)
        card.ring:SetVertexColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 1)
        card.ccIcon:Hide()
        card.state:SetText(ESC.dim .. "FEIGN|r")
    else
        if coords then
            card.portrait:SetVertexColor(1, 1, 1, 1)
        else
            card.portrait:SetVertexColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 1)
        end
        card.ring:SetVertexColor(THEME.edge[1], THEME.edge[2], THEME.edge[3], 1)
        card.ccIcon:Hide()
        card.state:SetText(ESC.dim .. (seat.spec or seat.class or "") .. "|r")
    end
    -- Name
    card.name:SetText(Esc(c) .. ShortName(seat.name or "?") .. "|r"
        .. (seat.spec and (ESC.dim .. "  " .. seat.spec .. "|r") or "")
        .. (seat.fromScoreboard and (ESC.dim .. "  · scoreboard only|r") or ""))
    local tgt = st and st.target and m.seats[st.target]
    if tgt then
        card.target:SetText(ESC.dim .. "on |r" .. Esc(ClassColor(tgt.class)) .. ShortName(tgt.name or "?") .. "|r")
    else
        card.target:SetText("")
    end
    -- Health
    local w = card.hp:GetWidth()
    if not w or w <= 0 then w = COL_W - PORTRAIT - 13 end
    local hp = st and st.hp
    if dead then hp = 0 end
    if hp then
        local hc = U.HpColor(hp)
        card.hp.fill:SetWidth(max(hp * w, 0.001))
        card.hp.fill:SetVertexColor(hc[1], hc[2], hc[3], 0.85)
        card.hp.text:SetText(seat.hpMax and format("%s / %s  ·  %.0f%%", FmtNum(hp * seat.hpMax), FmtNum(seat.hpMax), hp * 100)
            or format("%.0f%%", hp * 100))
    else
        card.hp.fill:SetWidth(0.001)
        card.hp.text:SetText(ESC.dim .. "no reading|r")
    end
    -- Power
    local pow = st and st.pow
    if pow and not dead then
        local pc = POWER_COLOR[st.powType or 0] or POWER_COLOR[0]
        card.pow.fill:SetWidth(max(pow * w, 0.001))
        card.pow.fill:SetVertexColor(pc[1], pc[2], pc[3], 0.9)
    else
        card.pow.fill:SetWidth(0.001)
    end
    -- Cast bar: what killed them (for five seconds), the control on them,
    -- the cast in progress, the aftermath of a kick, the GCD, or — with
    -- nothing else to say — who is on them
    local cast = st and st.cast
    local killedBy
    if dead then
        for d = 1, #m.deaths do
            local dd = m.deaths[d]
            if dd.guid == seat.guid and dd.t <= t and t - dd.t < 5 then killedBy = dd; break end
        end
    end
    if killedBy then
        card.cast.fill:SetWidth(max(w, 0.001))
        card.cast.fill:SetVertexColor(THEME.danger[1], THEME.danger[2], THEME.danger[3], 0.45)
        card.cast.text:SetText("KILLED  ← " .. (killedBy.name or "?")
            .. (killedBy.killer and (" (" .. SeatLabel(m, killedBy.killer, true) .. ")") or ""))
        card.cast.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    elseif cc and not dead then
        local total = (cc.t2 or (cc.t + 12)) - cc.t
        local left = (cc.t2 or (cc.t + 12)) - t
        local frac = total > 0 and max(min(left / total, 1), 0) or 0
        card.cast.fill:SetWidth(max(frac * w, 0.001))
        card.cast.fill:SetVertexColor(THEME.statCC[1], THEME.statCC[2], THEME.statCC[3], 0.55)
        card.cast.text:SetText((cc.name or "CONTROLLED"):upper() .. (BRACKET[cc.x or 1] or "") .. format("  %.1fs", max(left, 0)))
        card.cast.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    elseif cast and not dead then
        -- A cast whose end is not known yet (live, still casting) fills
        -- against a typical three seconds and says so, instead of
        -- crawling toward the ten-second cap
        local known = cast.t2 ~= nil
        local dur = known and (cast.t2 - cast.t) or 3
        local frac = dur > 0 and min((t - cast.t) / dur, 1) or 0
        card.cast.fill:SetWidth(max(frac * w, 0.001))
        card.cast.fill:SetVertexColor(THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.6)
        card.cast.text:SetText((cast.name or "?") .. (known and format("  %.1fs", max(cast.t2 - t, 0)) or "  …"))
        card.cast.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
    else
        -- A kicked cast lingers red for a second and a half
        local kicked
        for i = seat.castLogN, 1, -1 do
            local k = seat.castLog[i]
            if k.t <= t then
                if k.r == "KICKED" and k.t2 and t - k.t2 < 1.5 then kicked = k; break end
                if k.t < t - 12 then break end
            end
        end
        if kicked then
            card.cast.fill:SetWidth(max(w, 0.001))
            card.cast.fill:SetVertexColor(THEME.danger[1], THEME.danger[2], THEME.danger[3], 0.45)
            card.cast.text:SetText("KICKED  " .. (kicked.name or "?"))
            card.cast.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
        elseif st and st.gcd and not dead then
            -- The GCD sweep names what it was spent on: icon, spell, then a
            -- dim GCD — "they just Kidney Shotted" reads off the bar
            card.cast.fill:SetWidth(max((1 - st.gcd) * w, 0.001))
            card.cast.fill:SetVertexColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3], 0.35)
            local gc = st.gcdCast
            if gc then
                card.cast.text:SetText(U.IconTag(gc, 11) .. " " .. (gc.name or "?") .. ESC.dim .. "  GCD|r")
            else
                card.cast.text:SetText(ESC.dim .. "GCD|r")
            end
            card.cast.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
        else
            card.cast.fill:SetWidth(0.001)
            local on = onScratch[seat.guid]
            if on and (on.n > 0 or on.allies ~= "") and not dead then
                local text = on.n > 0 and (ESC.dim .. format("%d on them: ", on.n) .. "|r" .. on.names) or ""
                if on.allies ~= "" then
                    text = text .. (text ~= "" and (ESC.dim .. "  ·  |r") or "") .. ESC.dim .. "with: |r" .. on.allies
                end
                card.cast.text:SetText(text)
            else
                card.cast.text:SetText("")
            end
        end
    end
    -- Buffs, cooldowns, debuffs
    local nb = st and st.buffN or 0
    for i = 1, ICONS_PER_ROW do
        local b = card.buffs[i]
        local a = i <= nb and st.buffs[i]
        if a then
            b.tipLines = AuraTip
            SetIcon(b, a, a.t2 and (a.t2 - t < 60 and format("%.0f", a.t2 - t) or "") or "")
        else
            b.rec = nil
            b:Hide()
        end
    end
    -- The trinket badge: down if a TRINKET press still covers the cursor
    local tk, tkLeft
    for i = 1, (st and st.cdN or 0) do
        local e = st.cd[i]
        if e.kind == "TRINKET" and e.x == "TRINKET" then tk, tkLeft = e, st.cdLeft[i]; break end
    end
    card.trinket.rec = TRINKET_SPELL
    card.trinket.icon:SetTexture(SeatTrinketIcon(seat))
    card.trinket.left = tkLeft
    card.trinket.pressedAt = tk and tk.t or nil
    local sweep = card.trinket.sweep
    if tk then
        -- Radial: start the client's sweep as if pressed (cd - left) ago,
        -- then hold it there; without Pause on this client it creeps by
        -- at most half a second between repaints before being reset
        local cdLen = tk.amount or TRINKET_CD
        sweep:SetCooldown(GetTime() - (cdLen - tkLeft), cdLen)
        if sweep.Pause then pcall(sweep.Pause, sweep) end
        card.trinket.icon:SetVertexColor(1, 1, 1, 1)
        card.trinket.border:SetVertexColor(THEME.danger[1], THEME.danger[2], THEME.danger[3], 1)
        card.trinket.text:SetText(FmtTime(tkLeft))
    else
        if sweep.Clear then pcall(sweep.Clear, sweep) else sweep:SetCooldown(0, 0) end
        card.trinket.icon:SetVertexColor(1, 1, 1, dead and 0.4 or 1)
        card.trinket.border:SetVertexColor(THEME.statCd[1], THEME.statCd[2], THEME.statCd[3], dead and 0.4 or 1)
        card.trinket.text:SetText("")
    end
    card.trinket:Show()
    -- Cooldown row: book presses and racial breaks; the medallion has its badge
    local ncd = st and st.cdN or 0
    local slot = 0
    for i = 1, ICONS_PER_ROW do
        local b = card.cds[i]
        local e
        while slot < ncd do
            slot = slot + 1
            local c = st.cd[slot]
            if not (c.kind == "TRINKET" and c.x == "TRINKET") then e = c; break end
        end
        if e then
            b.tipLines = CdTip
            b.left = st.cdLeft[slot]
            -- Minutes past a minute: "29:29" is wider than a 16 px icon
            local left = st.cdLeft[slot]
            SetIcon(b, e, left >= 60 and format("%dm", math.ceil(left / 60)) or format("%.0f", left))
        else
            b.rec = nil
            b:Hide()
        end
    end
    local nd = st and st.debuffN or 0
    for i = 1, ICONS_PER_ROW * 2 do
        local b = card.debuffs[i]
        local a = i <= nd and st.debuffs[i]
        if a then
            b.tipLines = AuraTip
            -- A control debuff wears the control color and its DR bracket
            local ccOf
            for k = 1, (st.ccN or 0) do
                if st.cc[k].name == a.name then ccOf = st.cc[k]; break end
            end
            local left = a.t2 and a.t2 - t or nil
            local text = left and left < 60 and format("%.0f", left) or ""
            if ccOf then
                text = (BRACKET[ccOf.x or 1] or ""):gsub("^%s+", "") .. (text ~= "" and (" " .. text) or "")
                b.border:SetVertexColor(THEME.statCC[1], THEME.statCC[2], THEME.statCC[3], 1)
            else
                b.border:SetVertexColor(0.75, 0.25, 0.25, 1)
            end
            SetIcon(b, a, text)
        else
            b.rec = nil
            b:Hide()
        end
    end
    card:Show()
end

local function RepaintTeams(m, t, atEnd)
    if not m then
        for i = 1, 2 do
            teams[i].head.title:SetText(i == 1 and "YOUR TEAM" or "ENEMY")
            teams[i].head.total:SetText("")
            for c = 1, MAX_SEATS do teams[i].cards[c]:Hide() end
        end
        vsBar.us:SetWidth(0.001)
        vsBar.them:SetWidth(0.001)
        return
    end
    A.StateAt(m, t, stateScratch)
    -- Who is on whom: every seat's target, inverted
    for guid, on in pairs(onScratch) do on.n = 0; on.names = ""; on.allies = "" end
    for guid, st in pairs(stateScratch.seats) do
        local tgt = st.target and m.seats[st.target]
        local caster = m.seats[guid]
        if tgt and caster and st.alive and tgt.guid ~= caster.guid then
            local on = onScratch[tgt.guid]
            if not on then on = { n = 0, names = "", allies = "" }; onScratch[tgt.guid] = on end
            local label = Esc(ClassColor(caster.class)) .. ShortName(caster.name or "?") .. "|r"
            if caster.team ~= tgt.team then
                -- Enemies on them
                on.n = on.n + 1
                on.names = on.names == "" and label or (on.names .. ESC.dim .. ", |r" .. label)
            else
                -- Teammates casting on them (heals, shields)
                on.allies = on.allies == "" and label or (on.allies .. ESC.dim .. ", |r" .. label)
            end
        end
    end
    local DMG, HEAL = A.StatByKey("DMG"), A.StatByKey("HEAL")
    local totals = { us = 0, them = 0 }
    local healTot = { us = 0, them = 0 }
    for i, teamKey in ipairs({ "us", "them" }) do
        local tm = m.teams[teamKey]
        local f = teams[i]
        local shown = 0
        for c = 1, tm.n do
            local seat = m.seats[tm.order[c]]
            if seat and shown < MAX_SEATS then
                shown = shown + 1
                RepaintCard(f.cards[shown], m, seat, stateScratch.seats[seat.guid], t, atEnd)
                totals[teamKey] = totals[teamKey] + (A.SeatValueAt(m, seat, DMG, t))
                healTot[teamKey] = healTot[teamKey] + (A.SeatValueAt(m, seat, HEAL, t))
            end
        end
        for c = shown + 1, MAX_SEATS do
            f.cards[c].guid = nil
            f.cards[c]:Hide()
        end
        f.head.title:SetText(TeamHeadText(m, teamKey))
        f.head.total:SetText(Esc(THEME.statDmg) .. FmtNum(totals[teamKey]) .. "|r" .. ESC.dim .. " · |r"
            .. Esc(THEME.statHeal) .. FmtNum(healTot[teamKey]) .. "|r")
    end
    local grand = totals.us + totals.them
    local trackW = vsBar.track:GetWidth()
    if not trackW or trackW <= 0 then trackW = W - PAD * 2 end
    if grand > 0 then
        vsBar.us:SetWidth(max(totals.us / grand * trackW, 0.001))
        vsBar.them:SetWidth(max(totals.them / grand * trackW, 0.001))
    else
        vsBar.us:SetWidth(0.001)
        vsBar.them:SetWidth(0.001)
    end
end

local function Column(i)
    local c = plot.columns[i]
    if not c then
        local up = plot.frame:CreateTexture(nil, "ARTWORK")
        up:SetTexture(WHITE)
        up:SetVertexColor(THEME.teamUs[1], THEME.teamUs[2], THEME.teamUs[3], 0.85)
        local down = plot.frame:CreateTexture(nil, "ARTWORK")
        down:SetTexture(WHITE)
        down:SetVertexColor(THEME.teamThem[1], THEME.teamThem[2], THEME.teamThem[3], 0.85)
        c = { up = up, down = down }
        plot.columns[i] = c
    end
    return c
end

local function Marker(i)
    local q = plot.markers[i]
    if not q then
        q = plot.frame:CreateTexture(nil, "OVERLAY")
        q:SetTexture(WHITE)
        plot.markers[i] = q
    end
    return q
end

local MARKER_KIND = { DEATH = true, CC = true, KICK = true, TRINKET = true }

local function RepaintTimeline(m, t, atEnd)
    local pw = PlotWidth()
    local half = PLOT_H / 2
    if not m then
        plot.msg:SetText("NO MATCH")
        for i = 1, #plot.columns do plot.columns[i].up:Hide(); plot.columns[i].down:Hide() end
        for i = 1, #plot.markers do plot.markers[i]:Hide() end
        plot.cursor:Hide()
        plot.gates:Hide()
        axis.left:SetText(""); axis.mid:SetText(""); axis.right:SetText("")
        ctrl.clock:SetText("")
        return
    end
    plot.msg:SetText("")
    local endT = EndTime(m)
    if endT <= 0 then endT = 1 end
    local t0, span = PlotOrigin(m)
    local pr
    if IsLive(m) or pressureFor ~= m then
        pr = A.Pressure(m, pressureScratch, floor(endT) + 1)
        pressureFor = (not IsLive(m)) and m or nil
    else
        pr = pressureScratch
    end
    local n = pr.n or 0
    local scaleX = pw / span
    local bFirst = floor(t0) + 1
    local nShown = max(n - bFirst + 1, 0)
    local columns = min(MAX_COLUMNS, max(floor(pw / 2), 1))
    local perCol = max(math.ceil(nShown / columns), 1)
    columns = nShown > 0 and math.ceil(nShown / perCol) or 0
    local colW = perCol * scaleX
    local peak = 0
    for c = 1, columns do
        local b0 = bFirst + (c - 1) * perCol
        local su, st = 0, 0
        for b = b0, min(b0 + perCol - 1, n) do
            su = su + (pr.us[b] or 0)
            st = st + (pr.them[b] or 0)
        end
        if su > peak then peak = su end
        if st > peak then peak = st end
    end
    for c = 1, columns do
        local b0 = bFirst + (c - 1) * perCol
        local su, st = 0, 0
        for b = b0, min(b0 + perCol - 1, n) do
            su = su + (pr.us[b] or 0)
            st = st + (pr.them[b] or 0)
        end
        local col = Column(c)
        local x = max((b0 - 1 - t0) * scaleX, 0)
        local hu = peak > 0 and (su / peak) * (half - 4) or 0
        local hd = peak > 0 and (st / peak) * (half - 4) or 0
        col.up:ClearAllPoints()
        col.up:SetPoint("BOTTOMLEFT", plot.frame, "LEFT", x, 0)
        col.up:SetSize(max(colW - 0.5, 0.5), max(hu, 0.001))
        col.up:SetShown(hu > 0)
        col.down:ClearAllPoints()
        col.down:SetPoint("TOPLEFT", plot.frame, "LEFT", x, 0)
        col.down:SetSize(max(colW - 0.5, 0.5), max(hd, 0.001))
        col.down:SetShown(hd > 0)
    end
    for c = columns + 1, #plot.columns do
        plot.columns[c].up:Hide()
        plot.columns[c].down:Hide()
    end
    local mi = 0
    for i = 1, m.ledgerN do
        local e = m.ledger[i]
        local dispelMark = view.dlog and e.kind == "DISPEL" and e.src
        if (MARKER_KIND[e.kind] or dispelMark) and mi < MAX_MARKERS then
            local who = (e.kind == "TRINKET" or dispelMark) and e.src or e.dst
            local seat = who and m.seats[who]
            if seat and e.t >= t0 then
                mi = mi + 1
                local q = Marker(mi)
                local x = (e.t - t0) * scaleX
                local up = seat.team == "us"
                q:ClearAllPoints()
                if e.kind == "DEATH" then
                    q:SetSize(3, 7)
                    q:SetVertexColor(THEME.statDeath[1], THEME.statDeath[2], THEME.statDeath[3], 1)
                    q:SetPoint(up and "TOP" or "BOTTOM", plot.frame, up and "TOPLEFT" or "BOTTOMLEFT", x, up and -2 or 2)
                elseif e.kind == "DISPEL" then
                    -- On the CASTER's side, a dot row clear of the CC and
                    -- kick ticks: offensive cyan, defensive mint
                    local c = e.x == "PURGE" and THEME.statUtil or THEME.statCleanse
                    q:SetSize(2, 2)
                    q:SetVertexColor(c[1], c[2], c[3], 1)
                    q:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", plot.frame, "LEFT", x, up and 5 or -5)
                else
                    local c = e.kind == "CC" and THEME.statCC or e.kind == "KICK" and THEME.statUtil or THEME.statCd
                    local len = e.kind == "CC" and (e.t2 and max((e.t2 - e.t) * scaleX, 1) or 1) or 1
                    q:SetSize(len, 3)
                    q:SetVertexColor(c[1], c[2], c[3], 0.95)
                    q:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT", plot.frame, "LEFT", x, up and 1 or -1)
                end
                q:Show()
            end
        end
    end
    for i = mi + 1, #plot.markers do plot.markers[i]:Hide() end
    if m.tGates and m.tGates >= t0 then
        local gx = (m.tGates - t0) * scaleX
        plot.gates:ClearAllPoints()
        plot.gates:SetPoint("TOP", plot.frame, "TOPLEFT", gx, 0)
        plot.gates:SetPoint("BOTTOM", plot.frame, "BOTTOMLEFT", gx, 0)
        plot.gates:Show()
    else
        plot.gates:Hide()
    end
    local cx = max((t - t0) * scaleX, 0)
    plot.cursor:ClearAllPoints()
    plot.cursor:SetPoint("TOP", plot.frame, "TOPLEFT", cx, 0)
    plot.cursor:SetPoint("BOTTOM", plot.frame, "BOTTOMLEFT", cx, 0)
    plot.cursor:Show()
    axis.left:SetText(GateTime(m, t0))
    axis.mid:SetText(GateTime(m, t0 + span / 2))
    local peakText = peak > 0 and (ESC.dim .. "peak " .. FmtNum(peak / perCol) .. "/s  ·  |r") or ""
    axis.right:SetText(peakText .. (IsLive(m) and (Esc(THEME.accent) .. "LIVE " .. GateTime(m, endT) .. "|r") or GateTime(m, endT)))
    ctrl.clock:SetText(atEnd and (IsLive(m) and "LIVE" or "END") or GateTime(m, t))
    ctrl.play:SetShown(not view.playing)
    ctrl.pause:SetShown(view.playing)
    SetGlyphColor(ctrl.pause, THEME.accent)
    SetGlyphColor(ctrl.play, atEnd and THEME.textDim or THEME.accent)
    SetGlyphColor(ctrl.skip, atEnd and THEME.textDim or THEME.accent)
    ctrl.speed.text:SetText((PLAY_SPEEDS[view.speedIndex] or 1) .. "x")
    ctrl.speed.text:SetTextColor(THEME.textDim[1], THEME.textDim[2], THEME.textDim[3])
end

local statCache = {}
local meterValues = {}   -- [statKey][guid] = value at the cursor, one engine pass per stat

local function RepaintMeters(m, t, rows)
    -- One CollectRows per stat (a single ledger pass each) instead of a
    -- per-seat scan: the ledger stats were the one cost that scaled with
    -- both the roster and the ledger
    if m then
        for _, spec in ipairs(METER_COLS) do
            local stat = statCache[spec[1]]
            if not stat then stat = A.StatByKey(spec[1]); statCache[spec[1]] = stat end
            local by = meterValues[spec[1]]
            if not by then by = {}; meterValues[spec[1]] = by end
            for k in pairs(by) do by[k] = nil end
            local rowsData, n = A.CollectRows(m, stat, t)
            for r = 1, n do by[rowsData[r].seat.guid] = rowsData[r].value end
        end
    end
    for i, teamKey in ipairs({ "us", "them" }) do
        local f = meters[i]
        local tm = m and m.teams[teamKey]
        local shown = 0
        if tm then
            for c = 1, tm.n do
                local seat = m.seats[tm.order[c]]
                if seat and shown < rows then
                    shown = shown + 1
                    local row = f.rows[shown]
                    row.name:SetText(Esc(ClassColor(seat.class)) .. ShortName(seat.name or "?") .. "|r")
                    for k, spec in ipairs(METER_COLS) do
                        local v = meterValues[spec[1]][seat.guid] or 0
                        local text
                        if spec[1] == "CC" then
                            text = FmtTime(v)
                        elseif spec[1] == "KILLS" then
                            local deaths = 0
                            for d = 1, #m.deaths do
                                if m.deaths[d].guid == seat.guid and m.deaths[d].t <= t then deaths = deaths + 1 end
                            end
                            text = format("%d/%d", v, deaths)
                        else
                            text = FmtNum(v)
                        end
                        row.cols[k]:SetText(text)
                    end
                    row:Show()
                end
            end
        end
        for r = shown + 1, MAX_SEATS do f.rows[r]:Hide() end
    end
end

local function RepaintFeed(m, t)
    if not m or m.ledgerN == 0 then
        feed.count:SetText("")
        for i = 1, FEED_ROWS do
            local row = feed.rows[i]
            row.idx = nil
            row.now:Hide()
            row.team:Hide()
            if i == 1 then
                row.time:SetText("")
                row.who:SetText("")
                row.text:SetText(m and "Nothing has happened yet" or "")
                row:Show()
            else
                row:Hide()
            end
        end
        return
    end
    local nextIdx = A.LedgerIndexAt(m, t)
    local cur = nextIdx - 1
    while nextIdx <= m.ledgerN and m.ledger[nextIdx].t <= t do
        cur = nextIdx
        nextIdx = nextIdx + 1
    end
    feed.count:SetText(format("%d of %d", max(cur, 0), m.ledgerN))
    local first = max(1, min(cur - 2, m.ledgerN - FEED_ROWS + 1))
    for i = 1, FEED_ROWS do
        local row = feed.rows[i]
        local idx = first + i - 1
        local e = m.ledger[idx]
        if e then
            row.idx = idx
            row.time:SetText(GateTime(m, e.t))
            local who = MomentWho(e)
            row.who:SetText(who and SeatLabel(m, who) or "")
            local seat = who and m.seats[who]
            if seat then
                local tc = seat.team == "us" and THEME.teamUs or THEME.teamThem
                row.team:SetVertexColor(tc[1], tc[2], tc[3], 1)
                row.team:Show()
            else
                row.team:Hide()
            end
            row.text:SetText(MomentText(m, e))
            row.now:SetShown(idx == cur)
            row:SetAlpha(e.t > t + 0.001 and 0.55 or 1)
            row:Show()
        else
            row.idx = nil
            row.now:Hide()
            row:Hide()
        end
    end
end

RepaintAll = function()
    if not built or not root:IsShown() then return end
    local m = Match()
    local t, atEnd = 0, true
    if m then t, atEnd = Cursor(m) end
    local rows = BoardRows(m)
    Layout(rows)
    RepaintSidebar(m)
    RepaintHeader(m)
    RepaintTeams(m, t, atEnd)
    RepaintTimeline(m, t, atEnd)
    RepaintMeters(m, t, rows)
    RepaintFeed(m, t)
    RepaintDispelLog(m, t, atEnd)
end

-- ---------------------------------------------------------------------------
-- Public surface (called from CommanderMeters.lua)
-- ---------------------------------------------------------------------------

function CommanderMetersArena_Init()
    if not built then BuildWindow() end
end

function CommanderMetersArena_Toggle()
    if not built then BuildWindow() end
    if root:IsShown() then
        root:Hide()
    else
        if not Match() then
            print("|cff66ccffCommander Meters|r: no arena match recorded yet — queue up, or /cm arenatest for a canned one")
        end
        root:Show()
        RepaintAll()
    end
end

-- Open on a match (an ARENA row passes its seat, which only picks the
-- match). A live match is read live; the cursor goes to the end.
function CommanderMetersArena_Open(seatGuid, matchId)
    if not built then BuildWindow() end
    if matchId then
        view.sel = matchId
    elseif A.Live() then
        view.sel = "live"
    else
        view.sel = "last"
    end
    view.t = nil
    view.playing = false
    root:Show()
    RepaintAll()
end

function CommanderMetersArena_OnMatchStart(m)
    if built and root:IsShown() then
        view.sel = "live"
        view.t = nil
        view.playing = false
        RepaintAll()
    end
end

function CommanderMetersArena_OnMatchEnd(m)
    pressureFor = nil
    if built and root:IsShown() then
        if m then view.sel = m.id else view.sel = "last" end
        view.t = nil
        view.playing = false
        RepaintAll()
    end
end

function CommanderMetersArena_IsShown()
    return built and root:IsShown() or false
end

function CommanderMetersArena_View()
    return view
end

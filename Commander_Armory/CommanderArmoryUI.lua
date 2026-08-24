-- CommanderArmoryUI.lua
--
-- Every pixel the module draws. Two surfaces and nothing else: the per-slot
-- popout hung off Blizzard's own paperdoll buttons, and the set manager, which
-- lives in a sixth character-frame tab and in a detachable window that shares
-- the same content frame.
--
-- What this file deliberately does NOT own: the equipment API, the snapshot,
-- the planner, the swap sequencer, the saved variables. It reads
-- CommanderArmory (the host) and CommanderArmoryEngine (pure, read-only) and
-- writes nothing but the ignore scratchpad and the hidden-item list. Every
-- cross-file call goes through HostCall/EngineCall, because this file loads
-- last and a sibling that failed to load must cost a feature, never a UI that
-- errors on every paint.
--
-- The one constraint that shaped it: protection propagates upward. Anything
-- containing a SecureActionButton cannot be shown, hidden or resized in
-- combat, so nothing here is secure and nothing here parents the host's secure
-- container -- it is a sibling the host mirrors onto us. That is also why the
-- set manager is a plain content pane that gets re-parented between the
-- character tab and its own window rather than two copies of the same UI.

local D = CommanderArmoryData
local E = CommanderArmoryEngine
local db = CommanderArmoryDB or {}

local format = string.format
local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local tinsert, tconcat, tsort = table.insert, table.concat, table.sort

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------
-- Chrome is themed; DATA is not. Quality colours, the bank blue and the three
-- slot states carry meaning and are the same in every accent.

local THEME = {
    font = "Fonts\\ARIALN.TTF", -- condensed, uniform digit widths (no jitter)

    bg      = { 0.045, 0.055, 0.065, 0.94 },
    chrome  = { 0.09, 0.11, 0.13, 1 },
    edge    = { 0.22, 0.27, 0.31, 1 },
    accent  = { 1.0, 0.72, 0.10 },
    text    = { 0.92, 0.94, 0.95 },
    textDim = { 0.52, 0.58, 0.62 },
    hover   = { 1, 1, 1, 0.10 },
    sunken  = { 0, 0, 0, 0.35 },

    -- Data colours. Never themed.
    ok      = { 0.40, 0.85, 0.45 },
    warn    = { 1.00, 0.82, 0.20 },
    bad     = { 0.90, 0.24, 0.20 },
    bank    = { 0.35, 0.65, 1.00 },
    ignore  = { 0.62, 0.52, 0.86 },
    broken  = { 0.90, 0.00, 0.00 },   -- Blizzard's own broken-item tint
}

local ACCENTS = {
    AMBER = { 1.0, 0.72, 0.10 },
    CYAN  = { 0.25, 0.85, 0.95 },
    GREEN = { 0.35, 0.90, 0.40 },
    RED   = { 0.95, 0.35, 0.30 },
    WHITE = { 0.95, 0.95, 0.95 },
}

-- The Console palette is another addon's table, so every read is soft-failed
-- against a local fallback (the TopBar pattern). A missing Console costs the
-- extra tints, never the accent.
local function AccentByKey(key)
    if key == "CLASS" then
        local info = Commander and Commander.GetClassInfo and Commander.GetClassInfo()
        if info and info.color then
            -- Copy, never alias: GetClassInfo memoizes that table suite-wide
            return { info.color[1], info.color[2], info.color[3] }
        end
    end
    if ACCENTS[key] then return ACCENTS[key] end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then
            return { color.r, color.g, color.b }
        end
    end
    return ACCENTS.AMBER
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ---------------------------------------------------------------------------
-- Text, textures, borders
-- ---------------------------------------------------------------------------

-- Every font string is registered so a Text Size change can restyle in place.
-- The suite bakes appearance at login and asks for a /reload; this one does not
-- have to, and a live font change is worth eleven lines.
local fontRegistry = {}

local function TextDelta()
    local size = tonumber(db and db.TextSize) or 11
    local delta = size - 11
    if delta < -1 then delta = -1 elseif delta > 2 then delta = 2 end
    return delta
end

local function StyleFont(fs, size, color, flags)
    -- "OUTLINE" or nothing. An invalid flag string hard-errors and aborts the
    -- whole file on this client, which is why the flag is never computed.
    fs:SetFont(THEME.font, size + TextDelta(), flags or "OUTLINE")
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
end

local function MakeText(parent, size, color, justify, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    StyleFont(fs, size, color, flags)
    if justify then fs:SetJustifyH(justify) end
    fontRegistry[#fontRegistry + 1] = { fs = fs, size = size, flags = flags }
    return fs
end

local function RestyleFonts()
    local delta = TextDelta()
    for i = 1, #fontRegistry do
        local entry = fontRegistry[i]
        entry.fs:SetFont(THEME.font, entry.size + delta, entry.flags or "OUTLINE")
    end
end

local function MakeTexture(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(WHITE)
    if color then t:SetVertexColor(color[1], color[2], color[3], color[4] or 1) end
    return t
end

-- Four hairlines rather than an edgeFile: a backdrop border scales its art and
-- goes fuzzy at the sizes these panels use.
local function Border(frame, color)
    local edges = {}
    for i = 1, 4 do
        edges[i] = MakeTexture(frame, "BORDER", color or THEME.edge)
    end
    edges[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    edges[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    edges[4]:SetWidth(1)
    frame.edges = edges
    return edges
end

local function Tip(widget, title, text)
    if Commander and Commander.UI and Commander.UI.AttachTooltip then
        Commander.UI.AttachTooltip(widget, title, text)
    end
end

-- ---------------------------------------------------------------------------
-- Drawn glyphs
-- ---------------------------------------------------------------------------
-- Icons are stacks of tinted WHITE8X8 quads, rotated for diagonals. ARIALN on
-- this client has no shape glyphs (a "✓" renders as the missing-glyph box) and
-- icon FILES move across patches; quads can do neither, and they tint with the
-- theme exactly like text does. Each glyph owner carries .glyphName so the
-- headless harness can find it and assert on what it is, not merely that it is.

local function Quad(owner, w, h, dx, dy, rotation)
    local q = owner:CreateTexture(nil, "ARTWORK")
    q:SetTexture(WHITE)
    q:SetSize(w, h)
    q:SetPoint("CENTER", owner, "CENTER", dx, dy)
    if rotation then q:SetRotation(rotation) end
    owner.icon[#owner.icon + 1] = q
end

local PI4 = math.pi / 4

local GLYPHS = {
    -- The popout arrows. One per paperdoll column plus the weapon row, because
    -- the arrow must hang off the edge that faces away from the model.
    popoutRight = function(b) Quad(b, 1.5, 6, -1.5, 1.5, -PI4); Quad(b, 1.5, 6, -1.5, -1.5, PI4) end,
    popoutLeft  = function(b) Quad(b, 1.5, 6, 1.5, 1.5, PI4); Quad(b, 1.5, 6, 1.5, -1.5, -PI4) end,
    popoutUp    = function(b) Quad(b, 1.5, 6, -1.8, -1, PI4); Quad(b, 1.5, 6, 1.8, -1, -PI4) end,

    close = function(b) Quad(b, 1.5, 9, 0, 0, PI4); Quad(b, 1.5, 9, 0, 0, -PI4) end,
    check = function(b) Quad(b, 1.5, 5, -3, -1.5, -PI4); Quad(b, 1.5, 9, 1, 1, PI4) end,
    dot   = function(b) Quad(b, 6, 6, 0, 0) end,

    -- Blizzard's own two special rows, drawn rather than borrowed:
    -- UI-GearManager-ItemIntoBag and UI-GearManager-LeaveItem-Opaque.
    bag = function(b)
        Quad(b, 10, 7, 0, -2)
        Quad(b, 5, 1.5, 0, 2.5)
        Quad(b, 1.5, 3, -2.5, 2)
        Quad(b, 1.5, 3, 2.5, 2)
    end,
    ignore = function(b)
        Quad(b, 11, 1.5, 0, 5); Quad(b, 11, 1.5, 0, -5)
        Quad(b, 1.5, 11, -5, 0); Quad(b, 1.5, 11, 5, 0)
        Quad(b, 1.5, 14, 0, 0, PI4)
    end,
    -- An empty box: "leave this slot bare". Deliberately the ignore glyph
    -- WITHOUT its diagonal, because the two rows sit next to each other and the
    -- difference between them -- hands off versus take it off -- is the single
    -- most important distinction in the module.
    bare = function(b)
        Quad(b, 11, 1.5, 0, 5); Quad(b, 11, 1.5, 0, -5)
        Quad(b, 1.5, 11, -5, 0); Quad(b, 1.5, 11, 5, 0)
    end,
    include = function(b)
        Quad(b, 10, 1.5, 1, 0)
        Quad(b, 1.5, 5, -3, 2, -PI4)
        Quad(b, 1.5, 5, -3, -2, PI4)
    end,

    sort  = function(b) Quad(b, 11, 1.5, 0, 3.5); Quad(b, 7, 1.5, -2, 0); Quad(b, 4, 1.5, -3.5, -3.5) end,
    warn  = function(b) Quad(b, 1.5, 7, 0, 1.5); Quad(b, 1.5, 1.5, 0, -4) end,
    pencil = function(b) Quad(b, 1.5, 10, 1, 1, -PI4); Quad(b, 3, 3, -3.5, -3.5) end,
    plus  = function(b) Quad(b, 11, 1.5, 0, 0); Quad(b, 1.5, 11, 0, 0) end,
}

local function SetGlyphColor(owner, c)
    for i = 1, #owner.icon do
        owner.icon[i]:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
end

local function MakeGlyph(parent, glyphName, w, h, asButton, name)
    local f = CreateFrame(asButton and "Button" or "Frame", name, parent)
    f:SetSize(w or 16, h or w or 16)
    f.glyphName = glyphName          -- how the headless harness finds it
    f.icon = {}
    if asButton then
        f.hover = f:CreateTexture(nil, "HIGHLIGHT")
        f.hover:SetTexture(WHITE)
        f.hover:SetVertexColor(1, 1, 1, THEME.hover[4])
        f.hover:SetAllPoints()
    end
    GLYPHS[glyphName](f)
    SetGlyphColor(f, THEME.textDim)
    return f
end

-- ---------------------------------------------------------------------------
-- Item presentation
-- ---------------------------------------------------------------------------

local qualityColorCache = {}

-- ITEM_QUALITY_COLORS[nil] ERRORS on this client -- it is not a plain table.
-- Type-check before indexing, every single time.
local function QualityColor(quality)
    if type(quality) ~= "number" then return 0.90, 0.90, 0.90 end
    local c = qualityColorCache[quality]
    if not c then
        local src = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        c = (src and src.r) and { src.r, src.g, src.b } or { 0.90, 0.90, 0.90 }
        qualityColorCache[quality] = c
    end
    return c[1], c[2], c[3]
end

local function QualityHex(quality)
    local r, g, b = QualityColor(quality)
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Slot 18 has three faces and one id. Ask the client which one is showing
-- rather than class-checking: a druid in a form that hides the relic slot and a
-- hunter with a bow both go through here.
local function SlotLabel(slotID)
    if slotID == 18 then
        local hasRelic = UnitHasRelicSlot and UnitHasRelicSlot("player")
        if hasRelic then
            return (type(RELICSLOT) == "string" and RELICSLOT ~= "" and RELICSLOT) or "Relic"
        end
    end
    if D and D.SlotLabel then return D.SlotLabel(slotID) end
    return "Slot " .. tostring(slotID)
end

-- The hide list and the Pawn scorer both used to be reimplemented here -- a
-- direct reach into the per-character store, and a values[1][2] read of Pawn's
-- item data. Both belong to the host, and the Pawn copy had already drifted:
-- the host scores an item by the best VISIBLE scale, so the flyout's sort and
-- the host's own ranking disagreed about the same two items depending on which
-- surface the player happened to be looking at. Two authorities for one number
-- is one too many. See HasPawn and the Candidates call below.

-- ---------------------------------------------------------------------------
-- The host and the engine
-- ---------------------------------------------------------------------------
-- Both are siblings written in their own files. Every call is guarded rather
-- than assumed: this file is last in the TOC, so a sibling that failed to parse
-- would otherwise turn one broken load into an error on every frame.

local function HostCall(name, ...)
    local host = CommanderArmory
    local fn = host and host[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

local function EngineCall(name, ...)
    E = E or CommanderArmoryEngine
    local fn = E and E[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c
end

-- Whether Pawn is worth offering as a sort mode is the host's answer, because
-- the host owns the scorer that would do the sorting. Asking the global
-- ourselves is a second opinion about the same fact, and the two can only ever
-- agree by accident. The global is kept as the pre-login fallback, where there
-- is no host to ask.
local function HasPawn()
    local has = HostCall("HasPawn")
    if has ~= nil then return has and true or false end
    return _G.PawnGetItemData ~= nil
end

-- One snapshot per paint pass. Building it walks every bag, so a refresh that
-- repaints six widgets must not build it six times.
local snapCache, snapCacheAt = nil, -1

local function Snapshot()
    local now = (GetTime and GetTime()) or 0
    if snapCache and snapCacheAt >= 0 and (now - snapCacheAt) < 0.15 then
        return snapCache
    end
    local snap = HostCall("Snapshot")
    if type(snap) == "table" then
        snapCache, snapCacheAt = snap, now
    end
    return snapCache
end

local function InvalidateSnapshot()
    snapCacheAt = -1
end

local function Sets()
    local sets = HostCall("Sets")
    if type(sets) ~= "table" then return {} end
    return sets
end

-- SelectedSet may hand back the set itself or its index; accept both and always
-- return the pair, because the row highlight needs the index and everything
-- else needs the table.
local function SelectedSet()
    local sel = HostCall("SelectedSet")
    if type(sel) == "table" then
        local sets = Sets()
        for i = 1, #sets do
            if sets[i] == sel then return sel, i end
        end
        return sel, nil
    end
    if type(sel) == "number" then
        local sets = Sets()
        return sets[sel], sel
    end
    return nil, nil
end

-- The ignore scratchpad is a live table the host hands out; toggling a slot
-- writes it directly (ARCHITECTURE §3.3). There is deliberately no
-- host-side ToggleIgnore: the pad IS the API, and Save reads it back.
local function IgnoreScratch()
    local scratch = HostCall("IgnoreScratch")
    if type(scratch) == "table" then return scratch end
    return nil
end

-- An entry's state is one of exactly three STRINGS: "ITEM", "IGNORED",
-- "EMPTY". Nothing here ever tests falsiness, or 0, or nil, to mean "empty" --
-- conflating those is the root cause of the incumbent addon's most-reported
-- bug (a swap that strips a slot it was told to leave alone, and strands an
-- item on the cursor). A state we do not recognise reads as IGNORED, because
-- "leave it alone" is the only safe direction to be wrong in.
local STATE_ITEM, STATE_IGNORED, STATE_EMPTY = "ITEM", "IGNORED", "EMPTY"

local function SetEntryState(set, slotKey)
    if not set or type(set.entries) ~= "table" then return STATE_IGNORED end
    local entry = set.entries[slotKey]
    -- A slot with no entry at all is IGNORED. That makes a half-authored set
    -- safe by default and means adding a slot to the canon later cannot
    -- retroactively strip anyone's gear.
    if type(entry) ~= "table" then return STATE_IGNORED end
    if entry.state == STATE_ITEM then return STATE_ITEM end
    if entry.state == STATE_EMPTY then return STATE_EMPTY end
    return STATE_IGNORED
end

local function SetIgnores(set, slotKey)
    return SetEntryState(set, slotKey) == STATE_IGNORED
end

local function ScratchIgnored(set, slotKey)
    local scratch = IgnoreScratch()
    if scratch then return scratch[slotKey] == true end
    return SetIgnores(set, slotKey)
end

-- Delegate to the host when it offers the verb, and only fall back to writing
-- the pad directly when it does not. This is not fussiness: the host tracks a
-- separate "ignore was touched" flag and fires the update notification, and
-- writing the table behind its back sets neither. The visible symptom of
-- getting this wrong is precise and easy to miss -- toggling ignore on a set
-- you are already wearing would leave Save greyed out, which is the one case
-- retail gets right and the reason the flag exists at all.
local function ToggleIgnore(set, slotKey)
    if CommanderArmory and type(CommanderArmory.ToggleIgnore) == "function" then
        local ok = pcall(CommanderArmory.ToggleIgnore, slotKey)
        if ok then return true end
    end
    local scratch = IgnoreScratch()
    if not scratch then return false end
    if scratch[slotKey] then scratch[slotKey] = nil else scratch[slotKey] = true end
    return true
end

-- Retail disables Save whenever the set is worn, then re-enables it the moment
-- an ignore flag changes -- because ignore state is a property of the set that
-- can differ while every item already matches. We make that explicit rather
-- than inferring it from a disabled button.
local function ScratchDiffers(set)
    local scratch = IgnoreScratch()
    if not scratch or not set then return false end
    for _, slot in ipairs((D and D.Slots) or {}) do
        if (scratch[slot.key] == true) ~= SetIgnores(set, slot.key) then return true end
    end
    return false
end

local function SetIsDirty(set, snapshot)
    if not set then return false end
    if ScratchDiffers(set) then return true end
    local dirty = EngineCall("SetIsDirty", set, snapshot)
    return dirty == true
end

-- The host owns the run's shape, so read every field defensively and normalise
-- once. A progress bar that errors because a field was renamed is worse than
-- no progress bar.
local function ReadRun()
    local run = HostCall("RunState")
    if type(run) == "string" then return { status = run, done = 0, total = 0 } end
    if type(run) ~= "table" then return nil end
    return {
        status = run.status or run.state or "RUNNING",
        done   = tonumber(run.done) or tonumber(run.completed) or 0,
        total  = tonumber(run.total) or tonumber(run.actions) or 0,
        label  = run.label or run.name or (type(run.set) == "table" and run.set.name) or nil,
    }
end

-- ---------------------------------------------------------------------------
-- The vocabulary
-- ---------------------------------------------------------------------------
-- The line this module is defending: never begin a swap you cannot finish, and
-- say why in a sentence a player can act on. Blizzard's entire failure
-- vocabulary here is one red set name.

local REASON_PHRASE = {
    MISSING          = function(r) return format("%s is not in your bags or your bank", r.itemName or "an item") end,
    IN_BANK          = function(r) return format("%s is in your bank", r.itemName or "an item") end,
    BAGS_FULL        = function(r, plan, snapshot)
        local need = tonumber(plan and plan.needFree) or 0
        local have = tonumber(snapshot and snapshot.freeBagSlots) or 0
        local short = need - have
        if short > 0 then
            return format("you need %d more free bag slot%s", short, short == 1 and "" or "s")
        end
        return "your bags are full"
    end,
    IN_COMBAT        = function() return "you are in combat" end,
    CASTING          = function() return "you are casting" end,
    DEAD             = function() return "you are dead" end,
    MERCHANT_OPEN    = function() return "a merchant window is open" end,
    CURSOR_BUSY      = function() return "something is on your cursor" end,
    LOCKED           = function(r) return format("%s is in flight", r.itemName or "an item") end,
    UNIQUE_CONFLICT  = function(r) return format("%s is unique-equipped and already worn", r.itemName or "an item") end,
    NOT_USABLE       = function(r) return format("you cannot use %s", r.itemName or "that item") end,
    NOTHING_TO_DO    = function() return "there is nothing to change" end,
    -- A WARNING, not a blocker (see PlanIsQueueable's neighbours below). The
    -- engine writes a full two-clause sentence naming both items; that belongs
    -- on the slot tooltip, where there is room for it. The panel gets this
    -- shorter form, because a pre-flight line the player has to read twice is a
    -- pre-flight line they stop reading.
    IGNORE_OVERRIDDEN = function(r)
        return format("%s comes off — the two-hander leaves no off-hand", r.itemName or "your off-hand")
    end,
}

local function ReasonPhrase(reason, plan, snapshot)
    if type(reason) ~= "table" then return tostring(reason) end
    local phrase = REASON_PHRASE[reason.code]
    if phrase then return phrase(reason, plan, snapshot) end
    -- The engine writes its own text for anything we have not enumerated
    return reason.text or reason.code or "something is in the way"
end

-- "a, b, and c" -- the Oxford join, because the reasons are read aloud in the
-- player's head and "in your bank and you need 2 free bag slots" runs together.
local function JoinPhrases(list)
    local n = #list
    if n == 0 then return "" end
    if n == 1 then return list[1] end
    if n == 2 then return list[1] .. ", and " .. list[2] end
    return tconcat(list, ", ", 1, n - 1) .. ", and " .. list[n]
end

-- Combat, casting, death and a busy cursor are the four things the passage of
-- time fixes on its own. The host already queues a swap blocked by any of them
-- and flushes it on PLAYER_REGEN_ENABLED (D7), so to this file they are "wait",
-- not "no". MERCHANT_OPEN is deliberately absent -- the host refuses that one
-- outright, because a swap with a vendor frame up can sell gear (D12) -- and so
-- is BAGS_FULL, which no amount of waiting empties.
local QUEUEABLE_REASON = {
    IN_COMBAT = true, CASTING = true, DEAD = true, CURSOR_BUSY = true,
}

-- EVERY blocker must be queueable, not merely one of them: a set that is
-- missing its boots AND was asked for mid-fight is still missing its boots when
-- the fight ends, and offering to queue that is a promise we would break.
--
-- Warnings are skipped entirely. A reason carrying `warning = true` rides along
-- on an ok plan and is not standing in anything's way; counting it here would
-- turn a perfectly good swap into a refusal, and a false refusal is the worse
-- of the two failures -- it teaches the player the addon is broken, where a
-- warning teaches them what the client is about to do (D3a).
local function PlanIsQueueable(plan)
    if not plan or plan.ok then return false end
    -- The queue is a setting. With it off the host warns and does nothing, so
    -- offering a Queue button would be offering a button that declines.
    if db and db.CombatQueue == false then return false end
    local blockers = 0
    for _, reason in ipairs(plan.reasons or {}) do
        if reason.warning ~= true then
            if not QUEUEABLE_REASON[reason.code] then return false end
            blockers = blockers + 1
        end
    end
    return blockers > 0
end

-- One pass, one side: `warnings = true` collects the informational reasons,
-- false collects the blockers. Never both in one list -- they are read in
-- different colours and mean opposite things.
local function PlanPhrases(plan, snapshot, warnings)
    local out, seen = {}, {}
    for _, reason in ipairs((plan and plan.reasons) or {}) do
        if (reason.warning == true) == (warnings == true) then
            local text = ReasonPhrase(reason, plan, snapshot)
            if text and not seen[text] then
                seen[text] = true
                out[#out + 1] = text
            end
        end
    end
    return out
end

local function VerdictText(set, plan, snapshot)
    if not set then
        return "|cff777777Pick a set on the left, or make one from what you are wearing.|r"
    end
    if not plan then
        return "|cff777777Nothing to pre-flight yet.|r"
    end

    -- Caution amber on its own line, never the refusal red, and never merged
    -- into the blocker sentence. This says "here is what is about to happen",
    -- which is the opposite of "here is why nothing will".
    local warnings = PlanPhrases(plan, snapshot, true)
    local function WithWarnings(line)
        if #warnings == 0 then return line end
        return line .. format("\n|cffffd100Heads up:|r %s.", JoinPhrases(warnings))
    end

    if plan.ok then
        local actions = type(plan.actions) == "table" and #plan.actions or 0
        if actions == 0 then
            return WithWarnings(format("|cff66dd66%s is already on you.|r Nothing would move.",
                set.name or "This set"))
        end
        local deferred = type(plan.deferred) == "table" and #plan.deferred or 0
        local line = format("|cff66dd66Ready.|r Equipping %s moves %d item%s.",
            set.name or "this set", actions, actions == 1 and "" or "s")
        if deferred > 0 then
            line = line .. format(" %d slot%s will wait for the queue.", deferred, deferred == 1 and "" or "s")
        end
        return WithWarnings(line)
    end

    local phrases = PlanPhrases(plan, snapshot, false)

    -- Blocked only by things that pass: this is a schedule, not a failure, and
    -- the button beside it says Queue rather than going grey. The engine has to
    -- report ok = false here -- it refuses before it mutates and emits zero
    -- actions (D8) -- so the difference between "cannot" and "not yet" is ours
    -- to draw, and drawing it is the whole point of the queue.
    if PlanIsQueueable(plan) then
        if #phrases == 0 then phrases[1] = "you are busy" end
        return WithWarnings(format(
            "|cffffd100Not yet — %s.|r Queue %s and it runs the instant that lets go. |cff777777Nothing moves before then.|r",
            JoinPhrases(phrases), set.name or "this set"))
    end

    if #phrases == 0 then phrases[1] = "something is in the way" end
    return WithWarnings(format("|cffee4433Can't equip %s:|r %s. |cff777777Nothing has been moved.|r",
        set.name or "this set", JoinPhrases(phrases)))
end

-- The one-line per-set summary. Retail's whole failure vocabulary here is
-- turning the set name red; this says what it will do and what is missing.
local function DiffSummary(diff)
    if type(diff) ~= "table" then return "|cff777777not analysed|r" end
    local bits = {}
    local touched = tonumber(diff.touched) or 0
    local ignored = tonumber(diff.ignored) or 0
    local inBank  = tonumber(diff.inBank) or 0
    local missing = tonumber(diff.missing) or 0
    if diff.isEquipped and touched == 0 then
        bits[#bits + 1] = "|cff66dd66worn|r"
    else
        bits[#bits + 1] = format("changes %d", touched)
    end
    if ignored > 0 then bits[#bits + 1] = format("ignores %d", ignored) end
    if inBank > 0 then bits[#bits + 1] = format("|cff59a6ff%d in bank|r", inBank) end
    if missing > 0 then bits[#bits + 1] = format("|cffee4433%d missing|r", missing) end
    return tconcat(bits, " |cff555555·|r ")
end

-- ---------------------------------------------------------------------------
-- Forward declarations
-- ---------------------------------------------------------------------------
-- Declared before every function body that reads them. A local declared AFTER a
-- body compiles to a GLOBAL read inside it and silently returns nil -- the bug
-- Commander_Spoils paid for five times and the reason globals_lint exists.

local RefreshFlyout, OpenFlyout, CloseFlyout, ToggleFlyout
local RefreshPane, EnsurePane, PaintPaperdollMarkers
local EnsureArmoryTab, EnsureWindow, DockPane
local OpenNameDialog
local Refresh

-- ---------------------------------------------------------------------------
-- A. The per-slot flyout
-- ---------------------------------------------------------------------------
-- Blizzard's own flyout sorts by physical bag position and offers no search, no
-- filter and no item level. That sort is its single worst property: it answers
-- "where does this happen to sit in memory" when the question was "which of
-- these is best". Ours defaults to item level descending and remembers which
-- junk you told it to stop showing you.

local FLY_ROW_W = 176
local FLY_ROW_H = 20
local FLY_PAD = 8
local FLY_HEADER_H = 44
local FLY_FOOTER_H = 26

local flyout
local flyoutRows = {}
local flyoutSlot, flyoutAnchor
local flyoutData = {}
local flyoutOffset = 0
local flyoutSearch = ""
local flyoutAltState = false

-- Where the popout was opened FROM, which is what a click on a row means.
--
-- One list, two verbs, and the difference is not cosmetic:
--
--   PAPERDOLL -- the arrows on Blizzard's own slot buttons. A click WEARS the
--                item, exactly as it always has.
--   PANE      -- the Armory pane's slot grid. With a set selected, a click
--                AUTHORS the item into that set and equips nothing at all.
--                With no set selected there is nothing to author, so it wears.
--
-- Authoring is what makes a naked new set usable: the whole point of a set that
-- specifies nothing is that you can fill it in without owning the gear, or
-- while wearing something else entirely. Shift-click stays a wear, so the pane
-- is not a dead end for the one thing you came to the paperdoll for.
local flyoutSource = "PAPERDOLL"

local function FlyoutMode()
    if flyoutSource == "PANE" and SelectedSet() then return "AUTHOR" end
    return "WEAR"
end

local SORT_MODES = { "ILVL", "QUALITY", "NAME", "SCORE" }
local SORT_LABEL = {
    ILVL = "Item level", QUALITY = "Quality", NAME = "Name", SCORE = "Pawn score",
}

local function FlyoutSortMode()
    local mode = db and db.FlyoutSort
    if not SORT_LABEL[mode] then return "ILVL" end
    -- Pawn's absence demotes SCORE rather than showing an empty ordering
    if mode == "SCORE" and not HasPawn() then return "ILVL" end
    return mode
end

local function FlyoutColumns()
    local n = tonumber(db and db.FlyoutColumns) or 5
    if n < 1 then n = 1 elseif n > 8 then n = 8 end
    return n
end

local function FlyoutMaxRows()
    local n = tonumber(db and db.FlyoutMaxRows) or 4
    if n < 2 then n = 2 elseif n > 8 then n = 8 end
    return n
end

-- The HOST's Candidates, not the engine's. It already folds in the minimum
-- quality, the sort mode, the hide list, the show-bank filter and Pawn's
-- scorer, and doing any of that a second time here is how the two surfaces came
-- to rank the same two items differently. Everything this function still passes
-- is genuinely local to the popout: what is typed in its search box, and
-- whether Alt is being held right now.
local function CandidateRows(slotID)
    local rows = HostCall("Candidates", slotID, {
        search = (flyoutSearch ~= "" and flyoutSearch) or nil,
        -- Hold Alt to reveal what you have hidden: the reveal is a gesture, not
        -- a setting, because you only ever want it for the four seconds it
        -- takes to un-hide something.
        showHidden = (IsAltKeyDown and IsAltKeyDown()) or false,
    })
    if type(rows) ~= "table" then return {} end
    return rows
end

-- A click ALWAYS means "put this on". It never means "put this away".
-- ItemRack's default is the opposite -- clicking with the bank open deposits,
-- which is one of its most complained-about behaviours and eventually got a
-- shift-click override bolted on. There is no deposit affordance anywhere in
-- this file: at the bank, a banked item is withdrawn and then equipped; away
-- from the bank it stays on the list, greyed, because "it's in your bank" is an
-- instruction and "it's gone" is a dead end, and no competitor on this client
-- tells the two apart.
local function RowIsReachable(row, snapshot)
    if not row then return false end
    if row.where ~= "BANK" then return true end
    return (snapshot and snapshot.atBank) == true
end

local function RowBadge(row, snapshot)
    if row.where == "EQUIPPED" then
        return "worn: " .. SlotLabel(row.fromSlot or 0), THEME.textDim
    elseif row.where == "BANK" then
        -- At the bank the withdrawal is part of equipping it, so say so rather
        -- than making the player guess whether the click will work.
        if snapshot and snapshot.atBank then return "bank →", THEME.bank end
        return "bank", THEME.bank
    end
    return "bags", THEME.textDim
end

local function ShowItemTooltip(owner, row)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local shown = false
    if row.where == "EQUIPPED" and row.fromSlot and GameTooltip.SetInventoryItem then
        shown = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", row.fromSlot)
    elseif row.bag and row.slot and GameTooltip.SetBagItem then
        shown = pcall(GameTooltip.SetBagItem, GameTooltip, row.bag, row.slot)
    end
    -- A cached bank row has no live container behind it, so the link is all we
    -- have -- and a link tooltip is a real tooltip, not a summary.
    if not shown and row.link and GameTooltip.SetHyperlink then
        pcall(GameTooltip.SetHyperlink, GameTooltip, row.link)
    end
    -- What the click will actually do. The gesture is the only place the two
    -- verbs are told apart at the moment of pressing, so it is spelled out here
    -- rather than left to be inferred from which surface you opened.
    if FlyoutMode() == "AUTHOR" then
        local set = SelectedSet()
        local accent = THEME.accent
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(format("Click to put this in \"%s\". Nothing is equipped.",
            (set and set.name) or "this set"), accent[1], accent[2], accent[3], true)
        GameTooltip:AddLine("Shift-click to wear it now instead.", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function FlyoutRowClick(self)
    local row = self.data
    if not row then return end

    -- Alt-click hides. This is the fix for the actual failure mode: twelve
    -- junk greens burying the two items you actually alternate between.
    -- ToggleHidden is the host's, because the host owns the store the flag
    -- lives in AND fires the update notification; writing the table from here
    -- left every other surface painting a stale list until something else
    -- happened to refresh it.
    if IsAltKeyDown and IsAltKeyDown() then
        HostCall("ToggleHidden", row.key or row.baseKey)
        RefreshFlyout()
        return
    end

    -- Authoring. Writing a set is not reaching for an object, so nothing here
    -- asks where the item is: a set may perfectly well name a piece sitting in
    -- the bank, or one you are about to go and get. Reachability is the
    -- EQUIPPER's question and it is asked on the wear path below.
    local wearNow = (IsShiftKeyDown and IsShiftKeyDown()) or false
    if FlyoutMode() == "AUTHOR" and not wearNow then
        local set = SelectedSet()
        local slot = D and D.SlotByID and D.SlotByID[flyoutSlot]
        if not set or not slot then return end
        if not HostCall("AuthorSlot", set, slot.key, row) then
            print("|cff66ccffCommander Armory|r: |cffff4433that item could not be written into the set.|r")
            return
        end
        print(format("|cff66ccffCommander Armory|r: \"%s\" now wants %s in the %s slot.",
            set.name or "set", row.name or "that item", SlotLabel(flyoutSlot)))
        CloseFlyout()
        Refresh()
        return
    end

    local snapshot = Snapshot()
    if not RowIsReachable(row, snapshot) then
        print(format("|cff66ccffCommander Armory|r: %s is in your bank — open a banker and this one click wears it.",
            row.name or "that item"))
        return
    end

    -- Equip. Always equip. A banked row at the bank is a withdraw-then-equip on
    -- the host's side; there is no path from here that puts an item away.
    HostCall("EquipSingle", flyoutSlot, row)
    CloseFlyout()
    Refresh()
end

local function FlyoutRowEnter(self)
    if self.data then ShowItemTooltip(self, self.data) end
    if flyout and flyout.detail and self.data then
        local q = QualityHex(self.data.quality)
        flyout.detail:SetText(format("%s%s|r", q, self.data.name or "?"))
    end
end

local function FlyoutRowLeave()
    if GameTooltip then GameTooltip:Hide() end
    if flyout and flyout.detail then flyout.detail:SetText("") end
end

local function BuildFlyoutRow(index)
    local row = CreateFrame("Button", "CommanderArmoryFlyoutRow" .. index, flyout)
    row:SetSize(FLY_ROW_W, FLY_ROW_H)
    row:RegisterForClicks("LeftButtonUp")

    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetTexture(WHITE)
    row.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    row.hl:SetAllPoints()

    row.tex = row:CreateTexture(nil, "ARTWORK")
    row.tex:SetSize(16, 16)
    row.tex:SetPoint("LEFT", row, "LEFT", 2, 0)

    -- There is deliberately no stack-count text over the icon. `count` is not
    -- in the candidate row contract -- the engine's COPY_FIELDS does not carry
    -- it and nothing downstream adds it -- so the widget that used to sit here
    -- could only ever draw an empty string. Equippable gear does not stack
    -- anyway. Do not re-add it without the host's row builder growing the field
    -- first.
    row.name = MakeText(row, 10, THEME.text, "LEFT")
    row.name:SetPoint("LEFT", row.tex, "RIGHT", 4, 0)
    row.name:SetWidth(FLY_ROW_W - 84)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    row.ilvl = MakeText(row, 10, THEME.textDim, "RIGHT")
    row.ilvl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.ilvl:SetWidth(24)

    row.badge = MakeText(row, 8, THEME.textDim, "RIGHT")
    row.badge:SetPoint("RIGHT", row.ilvl, "LEFT", -4, 0)
    row.badge:SetWidth(38)

    row:SetScript("OnClick", FlyoutRowClick)
    row:SetScript("OnEnter", FlyoutRowEnter)
    row:SetScript("OnLeave", FlyoutRowLeave)
    return row
end

local function EnsureFlyoutRow(index)
    local row = flyoutRows[index]
    if not row then
        row = BuildFlyoutRow(index)
        flyoutRows[index] = row
    end
    return row
end

-- Candidate rows are POOLED: the same table objects, refilled from the top on
-- every Candidates call. A widget that keeps one is holding a promise the
-- engine never made -- the next call rewrites it underneath, and the click that
-- follows equips whatever landed in that slot instead. So each row owns a flat
-- copy. `source` and `stats` come across as references on purpose: they point
-- into the host's snapshot, which is not pooled, and PlanSingle identifies the
-- item by `source`.
local function CopyRow(dst, src)
    dst = dst or {}
    for key in pairs(dst) do dst[key] = nil end
    for key, value in pairs(src) do dst[key] = value end
    return dst
end

local function PaintFlyoutRow(row, data, snapshot)
    row.data = CopyRow(row.data, data)
    row.tex:SetTexture(data.icon or QUESTION_MARK)
    row.name:SetText(data.name or "?")
    local r, g, b = QualityColor(data.quality)
    row.name:SetTextColor(r, g, b)

    local ilvl = tonumber(data.ilvl)
    row.ilvl:SetText(ilvl and format("%d", ilvl) or "")

    local badge, badgeColor = RowBadge(data, snapshot)
    row.badge:SetText(badge)
    row.badge:SetTextColor(badgeColor[1], badgeColor[2], badgeColor[3])

    -- Three separate dims, three separate meanings, never conflated:
    -- unreachable (banked, and you are not at a bank), unusable (no armor
    -- proficiency -- dimmed, NEVER hidden), and hidden-by-hand (only visible
    -- while Alt is held, and marked so you know why it came back).
    local alpha = 1
    if not RowIsReachable(data, snapshot) then alpha = 0.45 end
    if data.usable == false then alpha = min(alpha, 0.6) end
    row:SetAlpha(alpha)

    -- The engine already answered this while filtering, so the row says whether
    -- it is hidden and we do not re-derive it from the store.
    if data.hidden then
        row.badge:SetText("hidden")
        row.badge:SetTextColor(THEME.ignore[1], THEME.ignore[2], THEME.ignore[3])
    end
    row:Show()
end

local function BuildFlyout()
    if flyout then return flyout end
    local f = CreateFrame("Frame", "CommanderArmoryFlyout", UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetSize(FLY_ROW_W + FLY_PAD * 2, 200)
    f:Hide()

    f.bg = MakeTexture(f, "BACKGROUND", THEME.bg)
    f.bg:SetAllPoints()
    Border(f, THEME.edge)

    f.headerBar = MakeTexture(f, "BORDER", THEME.chrome)
    f.headerBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    f.headerBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    f.headerBar:SetHeight(18)

    f.rule = MakeTexture(f, "ARTWORK", THEME.accent)
    f.rule:SetPoint("BOTTOMLEFT", f.headerBar, "BOTTOMLEFT", 0, 0)
    f.rule:SetPoint("BOTTOMRIGHT", f.headerBar, "BOTTOMRIGHT", 0, 0)
    f.rule:SetHeight(1)

    f.title = MakeText(f, 11, THEME.accent, "LEFT")
    f.title:SetPoint("LEFT", f.headerBar, "LEFT", FLY_PAD, 0)

    f.closeBtn = MakeGlyph(f, "close", 16, 16, true)
    f.closeBtn:SetPoint("RIGHT", f.headerBar, "RIGHT", -4, 0)
    f.closeBtn:SetScript("OnClick", function() CloseFlyout() end)
    Tip(f.closeBtn, "Close", "Escape closes it too.")

    f.sortBtn = MakeGlyph(f, "sort", 16, 16, true)
    f.sortBtn:SetPoint("RIGHT", f.closeBtn, "LEFT", -2, 0)
    f.sortBtn:SetScript("OnClick", function()
        local at, mode = 1, FlyoutSortMode()
        for i, key in ipairs(SORT_MODES) do if key == mode then at = i end end
        local nextMode = SORT_MODES[(at % #SORT_MODES) + 1]
        if nextMode == "SCORE" and not HasPawn() then
            nextMode = SORT_MODES[((at + 1) % #SORT_MODES) + 1]
        end
        if db then db.FlyoutSort = nextMode end
        RefreshFlyout()
    end)
    Tip(f.sortBtn, "Sort", function()
        return "Currently: " .. (SORT_LABEL[FlyoutSortMode()] or "?")
            .. "\n\nItem level descending is the default because it answers the question you were actually asking. Pawn score needs Pawn installed."
    end)

    local search = CreateFrame("EditBox", "CommanderArmoryFlyoutSearch", f, "InputBoxTemplate")
    search:SetSize(FLY_ROW_W - 12, 18)
    search:SetPoint("TOPLEFT", f, "TOPLEFT", FLY_PAD + 6, -22)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        flyoutSearch = self:GetText() or ""
        flyoutOffset = 0
        RefreshFlyout()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.search = search

    -- The two special rows Blizzard prepends to its own flyout, in its own
    -- order: place-in-bags first, then the ignore toggle. Kept as dedicated
    -- buttons rather than list entries so their drawn glyphs are built once.
    local placeBags = CreateFrame("Button", "CommanderArmoryFlyoutPlaceInBags", f)
    placeBags:SetSize(FLY_ROW_W, FLY_ROW_H)
    placeBags.hl = placeBags:CreateTexture(nil, "HIGHLIGHT")
    placeBags.hl:SetTexture(WHITE)
    placeBags.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    placeBags.hl:SetAllPoints()
    placeBags.mark = MakeGlyph(placeBags, "bag", 16, 16, false)
    placeBags.mark:SetPoint("LEFT", placeBags, "LEFT", 2, 0)
    placeBags.text = MakeText(placeBags, 10, THEME.text, "LEFT")
    placeBags.text:SetPoint("LEFT", placeBags.mark, "RIGHT", 4, 0)
    placeBags.text:SetText("Place In Bags")
    placeBags:SetScript("OnClick", function()
        HostCall("RemoveSlot", flyoutSlot)
        CloseFlyout()
        Refresh()
    end)
    Tip(placeBags, "Place In Bags", "Take the item off and put it in your bags. Shown only when the slot has something in it, exactly as Blizzard's own flyout does.\n\nThis is the only thing in the Armory that takes gear off, and it never touches your bank — clicking an item always means \"put this on\".")
    f.placeBags = placeBags

    local ignoreBtn = CreateFrame("Button", "CommanderArmoryFlyoutIgnore", f)
    ignoreBtn:SetSize(FLY_ROW_W, FLY_ROW_H)
    ignoreBtn.hl = ignoreBtn:CreateTexture(nil, "HIGHLIGHT")
    ignoreBtn.hl:SetTexture(WHITE)
    ignoreBtn.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    ignoreBtn.hl:SetAllPoints()
    ignoreBtn.markIgnore = MakeGlyph(ignoreBtn, "ignore", 16, 16, false)
    ignoreBtn.markIgnore:SetPoint("LEFT", ignoreBtn, "LEFT", 2, 0)
    ignoreBtn.markInclude = MakeGlyph(ignoreBtn, "include", 16, 16, false)
    ignoreBtn.markInclude:SetPoint("LEFT", ignoreBtn, "LEFT", 2, 0)
    ignoreBtn.text = MakeText(ignoreBtn, 10, THEME.text, "LEFT")
    ignoreBtn.text:SetPoint("LEFT", ignoreBtn.markIgnore, "RIGHT", 4, 0)
    ignoreBtn:SetScript("OnClick", function()
        local set = SelectedSet()
        local slot = D and D.SlotByID and D.SlotByID[flyoutSlot]
        if not set or not slot then return end
        if not ToggleIgnore(set, slot.key) then
            print("|cff66ccffCommander Armory|r: |cffff4433the ignore scratchpad is not ready yet.|r")
            return
        end
        RefreshFlyout()
        Refresh()
    end)
    Tip(ignoreBtn, "Hands off this slot", "Ignored is not empty. Ignored means the set leaves whatever is here exactly as it is; empty means it takes the item off and bags it. Conflating those two is the single most-complained-about bug in Blizzard's own equipment manager.\n\nSave writes the flags into the set.")
    f.ignoreBtn = ignoreBtn

    -- The third special row, and the other half of the ignore decision. It only
    -- appears while authoring, because "this slot should be bare" is a statement
    -- about a SET; on the paperdoll the equivalent verb is Place In Bags, which
    -- takes the item off right now and is a different thing entirely.
    local bareBtn = CreateFrame("Button", "CommanderArmoryFlyoutLeaveBare", f)
    bareBtn:SetSize(FLY_ROW_W, FLY_ROW_H)
    bareBtn.hl = bareBtn:CreateTexture(nil, "HIGHLIGHT")
    bareBtn.hl:SetTexture(WHITE)
    bareBtn.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    bareBtn.hl:SetAllPoints()
    bareBtn.mark = MakeGlyph(bareBtn, "bare", 16, 16, false)
    bareBtn.mark:SetPoint("LEFT", bareBtn, "LEFT", 2, 0)
    bareBtn.text = MakeText(bareBtn, 10, THEME.text, "LEFT")
    bareBtn.text:SetPoint("LEFT", bareBtn.mark, "RIGHT", 4, 0)
    bareBtn.text:SetText("Leave This Slot Bare")
    bareBtn:SetScript("OnClick", function()
        local set = SelectedSet()
        local slot = D and D.SlotByID and D.SlotByID[flyoutSlot]
        if not set or not slot then return end
        -- nil row means EMPTY. It is written as a real entry, never as a
        -- deleted one: a missing entry means IGNORED, which is the opposite.
        if not HostCall("AuthorSlot", set, slot.key, nil) then
            print("|cff66ccffCommander Armory|r: |cffff4433that slot could not be written.|r")
            return
        end
        print(format("|cff66ccffCommander Armory|r: \"%s\" now wants the %s slot bare.",
            set.name or "set", SlotLabel(flyoutSlot)))
        CloseFlyout()
        Refresh()
    end)
    Tip(bareBtn, "Leave This Slot Bare", "Write EMPTY into this set for this slot: equipping the set takes whatever is here off and puts it in your bags.\n\nThis is the opposite of hands-off, and nothing is equipped or removed right now — it only changes what the set says.")
    f.bareBtn = bareBtn

    -- Which verb a click carries, said in words at the top of the list rather
    -- than left to be inferred from which surface opened it.
    f.modeText = MakeText(f, 9, THEME.accent, "LEFT")
    f.modeText:SetPoint("TOPLEFT", f, "TOPLEFT", FLY_PAD, -FLY_HEADER_H + 1)
    f.modeText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -FLY_PAD, -FLY_HEADER_H + 1)
    f.modeText:Hide()

    f.empty = MakeText(f, 10, THEME.textDim, "CENTER")
    f.empty:SetPoint("TOP", f, "TOP", 0, -FLY_HEADER_H - 8)

    f.detail = MakeText(f, 10, THEME.text, "LEFT")
    f.detail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", FLY_PAD, 14)
    f.detail:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -FLY_PAD, 14)

    f.hint = MakeText(f, 8, THEME.textDim, "LEFT")
    f.hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", FLY_PAD, 5)
    f.hint:SetText("alt-click hides an item · hold alt to reveal hidden")

    -- Scroll against the geometry the last paint actually used, not against the
    -- setting: the column count is clamped by the content, so reading the
    -- setting here would let the offset run past the end of a short list.
    f:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = max(0, (flyout.pageRows or 0) - (flyout.shownRows or 0))
        flyoutOffset = min(maxOffset, max(0, flyoutOffset - delta))
        RefreshFlyout()
    end)

    -- Alt is a gesture, not a setting, so the list has to notice the key going
    -- down without a click to hang the check on.
    f:SetScript("OnUpdate", function()
        local alt = (IsAltKeyDown and IsAltKeyDown()) or false
        if alt ~= flyoutAltState then
            flyoutAltState = alt
            RefreshFlyout()
        end
    end)

    if UISpecialFrames then tinsert(UISpecialFrames, "CommanderArmoryFlyout") end
    flyout = f
    return f
end

function RefreshFlyout()
    if not flyout or not flyout:IsShown() or not flyoutSlot then return end
    local snapshot = Snapshot()
    local set = SelectedSet()

    local mode = FlyoutMode()
    flyout.mode = mode          -- read by the harness, and by nothing else

    flyout.title:SetText((SlotLabel(flyoutSlot) or "?"):upper())

    -- The header grows by one line while authoring, because the difference
    -- between "this puts it on" and "this writes it down" is the one thing a
    -- player must not have to guess.
    local headerH = FLY_HEADER_H
    if mode == "AUTHOR" then
        flyout.modeText:SetText(format("|cffffd100editing|r %s  ·  a click writes, shift-click wears",
            (set and set.name) or "this set"))
        flyout.modeText:Show()
        headerH = headerH + 11
    else
        flyout.modeText:SetText("")
        flyout.modeText:Hide()
    end

    -- Special rows: decided first, ordered second, positioned in one loop. The
    -- accumulating offset this replaces had the row order and the row geometry
    -- interleaved, which is why a third row could not simply be added to it.
    local slot = D and D.SlotByID and D.SlotByID[flyoutSlot]
    local worn = snapshot and snapshot.equipped and snapshot.equipped[flyoutSlot]
    local wantBare = (mode == "AUTHOR")
    local wantIgnore = (set and slot) and true or false
    local wantBags = worn and true or false

    if not wantBare then flyout.bareBtn:Hide() end
    if not wantBags then flyout.placeBags:Hide() end

    if wantIgnore then
        local ignored = ScratchIgnored(set, slot.key)
        flyout.ignoreBtn.text:SetText(ignored and "Include This Slot" or "Ignore This Slot")
        if ignored then
            flyout.ignoreBtn.markIgnore:Hide()
            flyout.ignoreBtn.markInclude:Show()
            SetGlyphColor(flyout.ignoreBtn.markInclude, THEME.ignore)
            flyout.ignoreBtn.text:SetTextColor(THEME.ignore[1], THEME.ignore[2], THEME.ignore[3])
        else
            flyout.ignoreBtn.markInclude:Hide()
            flyout.ignoreBtn.markIgnore:Show()
            SetGlyphColor(flyout.ignoreBtn.markIgnore, THEME.textDim)
            flyout.ignoreBtn.text:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
        end
    else
        flyout.ignoreBtn:Hide()
    end

    local order = {}
    if wantBare then
        -- Authoring: the two verbs that write the SET come first, because they
        -- are what this list is for, and Place In Bags -- which acts on the body
        -- this instant -- goes last so it cannot be mistaken for one of them.
        order[#order + 1] = flyout.bareBtn
        if wantIgnore then order[#order + 1] = flyout.ignoreBtn end
        if wantBags then order[#order + 1] = flyout.placeBags end
    else
        -- Wearing: Blizzard's own order, which is Place In Bags then the ignore
        -- toggle, and which people already know.
        if wantBags then order[#order + 1] = flyout.placeBags end
        if wantIgnore then order[#order + 1] = flyout.ignoreBtn end
    end

    for i = 1, #order do
        local button = order[i]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", flyout, "TOPLEFT", FLY_PAD, -(headerH + (i - 1) * FLY_ROW_H))
        button:Show()
    end
    local specials = #order

    flyoutData = CandidateRows(flyoutSlot)

    local cols, maxRows = FlyoutColumns(), FlyoutMaxRows()
    local total = #flyoutData
    -- Never spread four items across five columns: the column count is a
    -- ceiling on how wide the popout may get, not an instruction to use it.
    local usedCols = max(1, min(cols, ceil(total / maxRows)))
    local pageRows = ceil(total / usedCols)
    local shownRows = min(maxRows, max(pageRows, 1))
    local maxOffset = max(0, pageRows - shownRows)
    if flyoutOffset > maxOffset then flyoutOffset = maxOffset end
    flyout.pageRows, flyout.shownRows = pageRows, shownRows

    local top = headerH + specials * FLY_ROW_H
    local drawn = 0
    for col = 1, usedCols do
        for r = 1, shownRows do
            -- Column-major: a second column continues the same ranked list the
            -- way a newspaper column does. Row-major would put ranks 1 and 2
            -- side by side and destroy "the best one is at the top".
            local dataIndex = (col - 1) * pageRows + (r + flyoutOffset)
            local data = flyoutData[dataIndex]
            drawn = drawn + 1
            local row = EnsureFlyoutRow(drawn)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", flyout, "TOPLEFT",
                FLY_PAD + (col - 1) * FLY_ROW_W, -(top + (r - 1) * FLY_ROW_H))
            if data then
                PaintFlyoutRow(row, data, snapshot)
            else
                row.data = nil
                row:Hide()
            end
        end
    end
    for i = drawn + 1, #flyoutRows do
        flyoutRows[i].data = nil
        flyoutRows[i]:Hide()
    end

    if total == 0 then
        local why = "Nothing else fits here."
        if flyoutSearch ~= "" then
            why = "Nothing here matches \"" .. flyoutSearch .. "\"."
        elseif (tonumber(db and db.FlyoutMinQuality) or 0) > 0 then
            why = "Nothing here at that quality or better."
        end
        flyout.empty:SetText("|cff777777" .. why .. "|r")
        -- Positioned against the header the paint actually used: while authoring
        -- the header is a line taller, and a constant offset put this text on
        -- top of it.
        flyout.empty:ClearAllPoints()
        flyout.empty:SetPoint("TOP", flyout, "TOP", 0, -(top + 6))
        flyout.empty:Show()
    else
        flyout.empty:Hide()
    end

    local bodyRows = (total == 0) and 1 or shownRows
    flyout:SetSize(FLY_PAD * 2 + usedCols * FLY_ROW_W,
        top + bodyRows * FLY_ROW_H + FLY_FOOTER_H)

    if maxOffset > 0 then
        flyout.hint:SetText(format("scroll for %d more · alt-click hides an item", total - shownRows * usedCols))
    elseif mode == "AUTHOR" then
        flyout.hint:SetText("shift-click wears it now · alt-click hides an item")
    else
        flyout.hint:SetText("alt-click hides an item · hold alt to reveal hidden")
    end
end

function OpenFlyout(slotID, anchor, source)
    if not slotID then return end
    -- Ammo is slot 0 and is not in the canon at all: its button does not
    -- inherit PaperDollItemSlotButtonTemplate, Blizzard excludes it from its
    -- own flyouts, and it is outside the set model entirely (DECISIONS D4).
    if not (D and D.SlotByID and D.SlotByID[slotID]) then return end
    BuildFlyout()
    flyoutSlot = slotID
    flyoutAnchor = anchor
    -- Default to the paperdoll's verb. Anything that does not say which surface
    -- it is means "wear it", which is the behaviour that predates authoring and
    -- the safe one to be wrong about: it is visible and undoable, whereas a
    -- silent write into a set is neither.
    flyoutSource = (source == "PANE") and "PANE" or "PAPERDOLL"
    flyoutOffset = 0
    flyoutSearch = ""
    if flyout.search then flyout.search:SetText("") end

    flyout:ClearAllPoints()
    if anchor then
        flyout:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 6)
    else
        flyout:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    flyout:Show()
    RefreshFlyout()

    -- Anchored top-left off the button, a long list can run off the right edge
    -- of the screen. Flip it once we know the real width.
    if anchor and flyout:GetRight() and UIParent:GetRight()
        and flyout:GetRight() > UIParent:GetRight() then
        flyout:ClearAllPoints()
        flyout:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 6)
    end
end

function CloseFlyout()
    if flyout then flyout:Hide() end
    flyoutSlot, flyoutAnchor = nil, nil
    flyoutSource = "PAPERDOLL"
end

-- Re-opening the SAME slot from the other surface is a change of verb, not a
-- second click on the same control, so it reopens rather than toggling shut.
function ToggleFlyout(slotID, anchor, source)
    local wanted = (source == "PANE") and "PANE" or "PAPERDOLL"
    if flyout and flyout:IsShown() and flyoutSlot == slotID and flyoutSource == wanted then
        CloseFlyout()
        return
    end
    OpenFlyout(slotID, anchor, source)
end

-- ---------------------------------------------------------------------------
-- The paperdoll: popout arrows and ignore markers
-- ---------------------------------------------------------------------------
-- Nothing Blizzard draws is replaced, re-anchored or hidden. We hook
-- PaperDollItemSlotButton_Update and _OnEnter (both plain globals on this
-- client) and add one child button and one overlay texture per slot.
--
-- Read the slot id with :GetID(). There is NO .id field on the TBC slot
-- buttons -- the fields they carry are .backgroundTextureName, .checkRelic,
-- .UpdateTooltip and .hasItem, and nothing else.

-- Which edge the arrow hangs off: away from the model in the middle. Derived
-- from the TBC paperdoll's two columns plus the weapon row along the bottom.
local POPOUT_SIDE = {
    head = "RIGHT", neck = "RIGHT", shoulder = "RIGHT", back = "RIGHT",
    chest = "RIGHT", shirt = "RIGHT", tabard = "RIGHT", wrist = "RIGHT",
    hands = "LEFT", waist = "LEFT", legs = "LEFT", feet = "LEFT",
    finger1 = "LEFT", finger2 = "LEFT", trinket1 = "LEFT", trinket2 = "LEFT",
    mainhand = "UP", offhand = "UP", ranged = "UP",
}

local popouts = {}      -- slotID -> arrow button
local markers = {}      -- slotID -> ignore overlay texture

local function EnsurePopout(button)
    if not button or not button.GetID then return nil end
    local slotID = button:GetID()
    if popouts[slotID] then return popouts[slotID] end
    local slot = D and D.SlotByID and D.SlotByID[slotID]
    if not slot then return nil end

    local side = POPOUT_SIDE[slot.key] or "RIGHT"
    local glyph = (side == "LEFT" and "popoutLeft") or (side == "UP" and "popoutUp") or "popoutRight"
    -- Named purely so the headless UI harness can assert on CONTENT: which
    -- slots grew an arrow, which way it points, whether it is shown. A check
    -- that only proves "nothing threw" cannot tell a working feature from one
    -- that silently does nothing.
    local arrow = MakeGlyph(button, glyph, 12, 12, true, "CommanderArmoryPopout" .. slotID)
    arrow.slotID = slotID
    arrow.slotKey = slot.key
    arrow:SetFrameLevel((button:GetFrameLevel() or 1) + 4)
    if side == "LEFT" then
        arrow:SetPoint("RIGHT", button, "LEFT", -1, 0)
    elseif side == "UP" then
        arrow:SetPoint("BOTTOM", button, "TOP", 0, 1)
    else
        arrow:SetPoint("LEFT", button, "RIGHT", 1, 0)
    end
    arrow.bg = MakeTexture(arrow, "BACKGROUND", { 0, 0, 0, 0.55 })
    arrow.bg:SetAllPoints()
    arrow:SetScript("OnClick", function(self)
        -- The paperdoll's arrow always WEARS. This is the surface the gesture
        -- came from originally and it does not change meaning because a set
        -- happens to be selected.
        ToggleFlyout(self.slotID, button, "PAPERDOLL")
    end)
    arrow:SetScript("OnEnter", function(self)
        SetGlyphColor(self, THEME.accent)
    end)
    arrow:SetScript("OnLeave", function(self)
        SetGlyphColor(self, THEME.textDim)
    end)
    Tip(arrow, SlotLabel(slotID), "Everything that could go in this slot — bags, bank, or another slot you are already wearing it in — sorted by item level.")

    popouts[slotID] = arrow

    -- The ignore marker is OUR OWN overlay, never desaturation. Desaturation
    -- means "locked" and a red tint means "broken"; three states, three
    -- treatments, exactly as Blizzard itself distinguishes them.
    local mark = button:CreateTexture("CommanderArmoryIgnoreMark" .. slotID, "OVERLAY")
    mark:SetTexture(WHITE)
    mark:SetVertexColor(THEME.ignore[1], THEME.ignore[2], THEME.ignore[3], 0.34)
    mark:SetAllPoints(button)
    mark:Hide()
    markers[slotID] = mark

    return arrow
end

function PaintPaperdollMarkers()
    local wantArrows = db and db.EnableArmory and db.ShowSlotFlyouts
    local wantMarks = db and db.EnableArmory and db.ShowIgnoreMarkers
    local set = wantMarks and SelectedSet() or nil

    for slotID, arrow in pairs(popouts) do
        if wantArrows then arrow:Show() else arrow:Hide() end
        local mark = markers[slotID]
        if mark then
            local slot = D and D.SlotByID and D.SlotByID[slotID]
            if set and slot and ScratchIgnored(set, slot.key) then
                mark:Show()
            else
                mark:Hide()
            end
        end
    end
end

local hooksInstalled = false

local function InstallPaperdollHooks()
    if hooksInstalled then return end
    if not hooksecurefunc or type(PaperDollItemSlotButton_Update) ~= "function" then return end
    hooksInstalled = true

    -- Hook, never replace. Both of these are plain globals on this client, and
    -- both fire often enough that attaching on either one is enough on its own;
    -- we take both so the arrows exist before the first mouseover as well.
    -- One attach point serves both surfaces: the arrow AND the ignore marker
    -- are built by EnsurePopout, so a player who wants the markers but not the
    -- arrows still gets them (the arrow's visibility is decided in the paint,
    -- not here). Coupling the two here would have silently disabled the
    -- markers for anyone who turned the flyouts off.
    local function Wanted()
        return db and db.EnableArmory and (db.ShowSlotFlyouts or db.ShowIgnoreMarkers)
    end

    hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
        if not Wanted() then return end
        EnsurePopout(button)
    end)
    if type(PaperDollItemSlotButton_OnEnter) == "function" then
        hooksecurefunc("PaperDollItemSlotButton_OnEnter", function(button)
            if not Wanted() then return end
            EnsurePopout(button)
        end)
    end

    -- Attach to whatever already exists, so enabling the option mid-session
    -- does not wait for the next paperdoll update.
    for _, slot in ipairs((D and D.Slots) or {}) do
        local button = _G[slot.button]
        if button then EnsurePopout(button) end
    end

    if CharacterFrame and CharacterFrame.HookScript then
        CharacterFrame:HookScript("OnHide", function() CloseFlyout() end)
    end
end

-- ---------------------------------------------------------------------------
-- B. The set manager pane
-- ---------------------------------------------------------------------------
-- One content frame, docked either into the sixth character tab or into its own
-- window. Two hosts, one build: a second copy of this UI would be a second
-- place for a bug to hide.

-- The character window is 384x512 with the art insetting the usable area on
-- every side, and the pane is docked into it at (22, -72). Anything past about
-- 352 tall is drawn ON the bottom border art rather than inside it -- which is
-- how the free-bag-slot line came to be clipped by the frame edge and the
-- status sentence came to sit on the moulding. So the height is the budget, and
-- everything below is laid out against CONTENT rather than against the frame
-- edges, so the page stays coherent as the set list fills up.
local PANE_W, PANE_H = 320, 352
local SET_ROWS = 7
local SET_ROW_H = 28
local SET_LIST_W = 152
local GRID_COLS, GRID_CELL = 5, 28
local GRID_X = 168

-- The list is a bordered box the rows live INSIDE, not seven rows floating on
-- the background. With two sets saved, the old layout left the middle third of
-- the pane as an unexplained hole; a framed list reads as an empty list, which
-- is what it is, and the block beneath it hangs off the box rather than off a
-- hard-coded offset that happened to match.
local LIST_PAD = 2
local LIST_H = SET_ROWS * SET_ROW_H + LIST_PAD * 2

-- One button size and one gutter for all five verbs, in a 3x2 grid that is
-- exactly as wide as the list above it. The previous block mixed 49px and 75px
-- buttons across two ragged rows and floated free of the list entirely.
local BTN_W, BTN_H, BTN_GAP = 48, 21, 4
local BTN_TOP = -(LIST_H + 7)
local BTN_BOTTOM = BTN_TOP - (BTN_H * 2 + BTN_GAP)

-- The full-width footer: status, pre-flight, the world hints, and the run bar.
local FOOT_TOP = BTN_BOTTOM - 9

-- The name header sits above the slot grid, in the column the grid and the
-- stats share, because that column IS the selected set and the header names it.
local HEAD_H = 18
local GRID_TOP = -(HEAD_H + 4)

local pane
local setRows = {}
local slotCells = {}
local setOffset = 0

-- Our own diff table rather than the engine's shared scratch. DiffSet's third
-- argument exists for exactly this: the scratch is refilled by every later
-- call, and the selected set's diff has to stay alive across the dirty check,
-- the plan and the stat totals -- all of which resolve the same set again
-- underneath us. Holding the shared one would have the grid painting rows that
-- describe a different set.
local paneDiff = { changes = {} }

local function PaneButton(parent, label, width)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 48, 21)
    btn:SetText(label)
    return btn
end

local function SetButtonState(btn, enabled, reason)
    btn.disabledReason = (not enabled) and reason or nil
    if enabled then btn:Enable() else btn:Disable() end
end

local function SetRowClick(self)
    if not self.setIndex then return end
    HostCall("SelectSet", self.setIndex)
    CloseFlyout()
    Refresh()
end

local function SetRowDoubleClick(self)
    if not self.set then return end
    HostCall("SelectSet", self.setIndex)
    HostCall("EquipSet", self.set)
    Refresh()
end

local function BuildSetRow(index)
    local row = CreateFrame("Button", "CommanderArmorySetRow" .. index, pane)
    row:SetSize(SET_LIST_W - LIST_PAD * 2, SET_ROW_H)
    row:SetPoint("TOPLEFT", pane, "TOPLEFT", LIST_PAD, -(LIST_PAD + (index - 1) * SET_ROW_H))
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.sel = MakeTexture(row, "BACKGROUND", { 1, 1, 1, 0.09 })
    row.sel:SetAllPoints()
    row.sel:Hide()
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetTexture(WHITE)
    row.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    row.hl:SetAllPoints()

    row.tex = row:CreateTexture(nil, "ARTWORK")
    row.tex:SetSize(22, 22)
    row.tex:SetPoint("LEFT", row, "LEFT", 3, 0)

    row.name = MakeText(row, 11, THEME.text, "LEFT")
    row.name:SetPoint("TOPLEFT", row.tex, "TOPRIGHT", 5, -1)
    row.name:SetWidth(SET_LIST_W - 54)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end

    row.summary = MakeText(row, 9, THEME.textDim, "LEFT")
    row.summary:SetPoint("BOTTOMLEFT", row.tex, "BOTTOMRIGHT", 5, 1)
    row.summary:SetWidth(SET_LIST_W - 30)
    if row.summary.SetWordWrap then row.summary:SetWordWrap(false) end

    row.check = MakeGlyph(row, "check", 12, 12, false)
    row.check:SetPoint("RIGHT", row, "RIGHT", -4, 5)
    SetGlyphColor(row.check, THEME.ok)
    row.check:Hide()

    row.dirty = MakeGlyph(row, "dot", 8, 8, false)
    row.dirty:SetPoint("RIGHT", row, "RIGHT", -6, -6)
    SetGlyphColor(row.dirty, THEME.warn)
    row.dirty:Hide()

    row:SetScript("OnClick", SetRowClick)
    row:SetScript("OnDoubleClick", SetRowDoubleClick)
    row:SetScript("OnEnter", function(self)
        if not self.set or not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.set.name or "?", 1, 1, 1)
        GameTooltip:AddLine(self.tooltipLine or "", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Double-click to equip.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function SlotCellClick(self)
    -- The ignore toggle lives in the flyout, where it has always lived, so a
    -- click here opens the flyout for that slot rather than inventing a second
    -- gesture for the same decision (UX.md correction 1).
    --
    -- Opened from the PANE, that flyout authors the selected set instead of
    -- equipping: this grid describes a set, so picking an item in it is a
    -- statement about the set, not about the body.
    ToggleFlyout(self.slotID, self, "PANE")
end

local function SlotCellEnter(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(SlotLabel(self.slotID), 1, 1, 1)
    for _, line in ipairs(self.tooltipLines or {}) do
        GameTooltip:AddLine(line[1], line[2], line[3], line[4], true)
    end
    GameTooltip:Show()
end

local function BuildSlotCell(slot, index)
    local cell = CreateFrame("Button", "CommanderArmorySlot" .. slot.id, pane)
    cell:SetSize(GRID_CELL - 2, GRID_CELL - 2)
    local col = (index - 1) % GRID_COLS
    local rowN = floor((index - 1) / GRID_COLS)
    cell:SetPoint("TOPLEFT", pane, "TOPLEFT", GRID_X + col * GRID_CELL, GRID_TOP - rowN * GRID_CELL)
    cell.slotID = slot.id
    cell.slotKey = slot.key

    cell.back = MakeTexture(cell, "BACKGROUND", THEME.sunken)
    cell.back:SetAllPoints()
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    cell.tex:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)

    -- Ignored: our own overlay. NOT desaturation -- that word is spoken for.
    cell.ignoreMark = MakeTexture(cell, "OVERLAY", { THEME.ignore[1], THEME.ignore[2], THEME.ignore[3], 0.38 })
    cell.ignoreMark:SetAllPoints()
    cell.ignoreMark:Hide()

    -- The diff stripe: what this set would do to this slot, at a glance.
    cell.stripe = MakeTexture(cell, "OVERLAY", THEME.ok)
    cell.stripe:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT", 0, 0)
    cell.stripe:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 0, 0)
    cell.stripe:SetHeight(2)
    cell.stripe:Hide()

    cell.hl = cell:CreateTexture(nil, "HIGHLIGHT")
    cell.hl:SetTexture(WHITE)
    cell.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    cell.hl:SetAllPoints()

    cell:SetScript("OnClick", SlotCellClick)
    cell:SetScript("OnEnter", SlotCellEnter)
    cell:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return cell
end

-- ---------------------------------------------------------------------------
-- The name header, and renaming in place
-- ---------------------------------------------------------------------------
-- The Rename button opens a modal window with an icon grid in it, which is the
-- right shape for choosing an icon and the wrong shape for fixing a typo. The
-- name is also the one field that gets changed after the fact, so it is
-- editable where it is displayed: click it, type, Enter.
--
-- A refusal SAYS SO. An edit box that quietly reverts is indistinguishable from
-- one that did not register the keypress, and "nothing happened" is the failure
-- this whole module was written to stop shipping -- so an empty name and a name
-- another set already has both print the reason and leave the box open with the
-- text still in it.

local nameEditing = false
local nameEditSet = nil

local function EndNameEdit()
    nameEditing = false
    nameEditSet = nil
    if not pane or not pane.nameEdit then return end
    pane.nameEdit:ClearFocus()
    pane.nameEdit:Hide()
    pane.nameBtn:Show()
end

local function CommitNameEdit()
    if not pane or not pane.nameEdit then return false end
    local set = SelectedSet()
    if not set then
        EndNameEdit()
        return false
    end
    -- The host owns the rules -- it is the only thing that can see every set on
    -- the character -- and it hands back the finished sentence so the dialog and
    -- this box refuse in the same words.
    local ok, reason = HostCall("RenameSet", set, pane.nameEdit:GetText() or "", nil)
    if ok ~= true then
        print("|cff66ccffCommander Armory|r: |cffff4433"
            .. (reason or "that name will not do.") .. "|r")
        pane.nameEdit:SetFocus()
        return false
    end
    EndNameEdit()
    Refresh()
    return true
end

local function BeginNameEdit()
    local set = SelectedSet()
    if not pane or not pane.nameEdit or not set then return false end
    nameEditing = true
    nameEditSet = set
    pane.nameEdit:SetText(set.name or "")
    pane.nameBtn:Hide()
    pane.nameEdit:Show()
    pane.nameEdit:SetFocus()
    pane.nameEdit:HighlightText()
    return true
end

local function BuildNameHeader()
    local btn = CreateFrame("Button", "CommanderArmoryPaneName", pane)
    btn:SetPoint("TOPLEFT", pane, "TOPLEFT", GRID_X, 0)
    btn:SetSize(PANE_W - GRID_X, HEAD_H)
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetTexture(WHITE)
    btn.hl:SetVertexColor(1, 1, 1, THEME.hover[4])
    btn.hl:SetAllPoints()
    btn.text = MakeText(btn, 12, THEME.accent, "LEFT")
    btn.text:SetPoint("LEFT", btn, "LEFT", 1, 0)
    btn.text:SetWidth(PANE_W - GRID_X - 16)
    if btn.text.SetWordWrap then btn.text:SetWordWrap(false) end
    btn.pencil = MakeGlyph(btn, "pencil", 10, 10, false)
    btn.pencil:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    btn:SetScript("OnClick", function() BeginNameEdit() end)
    Tip(btn, "Set Name", function()
        return btn.disabledReason
            or "Click to rename this set here. Enter commits it, Escape leaves it alone.\n\nThe Rename button does the same thing and also changes the icon."
    end)
    pane.nameBtn = btn

    local edit = CreateFrame("EditBox", "CommanderArmoryPaneNameEdit", pane, "InputBoxTemplate")
    edit:SetPoint("TOPLEFT", pane, "TOPLEFT", GRID_X + 6, -1)
    edit:SetSize(PANE_W - GRID_X - 10, HEAD_H - 2)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(32)
    edit:SetScript("OnEnterPressed", function() CommitNameEdit() end)
    edit:SetScript("OnEscapePressed", function()
        EndNameEdit()
        Refresh()
    end)
    edit:Hide()
    pane.nameEdit = edit
end

function EnsurePane()
    if pane then return pane end
    if not CreateFrame then return nil end

    pane = CreateFrame("Frame", "CommanderArmoryPane", UIParent)
    pane:SetSize(PANE_W, PANE_H)
    pane:Hide()

    -- The list box. Drawn before the rows so it sits behind them.
    pane.listBox = CreateFrame("Frame", "CommanderArmorySetList", pane)
    pane.listBox:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    pane.listBox:SetSize(SET_LIST_W, LIST_H)
    pane.listBack = MakeTexture(pane.listBox, "BACKGROUND", THEME.sunken)
    pane.listBack:SetAllPoints()
    Border(pane.listBox, THEME.edge)

    for i = 1, SET_ROWS do
        setRows[i] = BuildSetRow(i)
    end

    -- Shown in place of the rows when there are none at all, because an empty
    -- bordered box with no words in it reads as a thing that failed to load.
    pane.listEmpty = MakeText(pane, 10, THEME.textDim, "CENTER")
    pane.listEmpty:SetPoint("TOPLEFT", pane.listBox, "TOPLEFT", 6, -14)
    pane.listEmpty:SetPoint("TOPRIGHT", pane.listBox, "TOPRIGHT", -6, -14)
    pane.listEmpty:SetText("No sets yet.\nNew makes an empty one.")
    pane.listEmpty:Hide()

    pane:EnableMouseWheel(true)
    pane:SetScript("OnMouseWheel", function(_, delta)
        local total = #Sets()
        local maxOffset = max(0, total - SET_ROWS)
        setOffset = min(maxOffset, max(0, setOffset - delta))
        RefreshPane()
    end)

    -- Buttons. One block hung off the bottom of the list box, five verbs in a
    -- 3x2 grid of identical buttons, every disabled one carrying its reason in
    -- the tooltip rather than going quiet.
    local function PlaceButton(btn, col, rowN)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", pane.listBox, "BOTTOMLEFT",
            col * (BTN_W + BTN_GAP), -7 - rowN * (BTN_H + BTN_GAP))
    end
    pane.newBtn = PaneButton(pane, "New", BTN_W)
    pane.saveBtn = PaneButton(pane, "Save", BTN_W)
    pane.equipBtn = PaneButton(pane, "Equip", BTN_W)
    pane.deleteBtn = PaneButton(pane, "Delete", BTN_W)
    pane.renameBtn = PaneButton(pane, "Rename", BTN_W)
    PlaceButton(pane.newBtn, 0, 0)
    PlaceButton(pane.saveBtn, 1, 0)
    PlaceButton(pane.equipBtn, 2, 0)
    PlaceButton(pane.deleteBtn, 0, 1)
    PlaceButton(pane.renameBtn, 1, 1)

    pane.newBtn:SetScript("OnClick", function() OpenNameDialog("NEW") end)
    Tip(pane.newBtn, "New Set",
        "Make a set that specifies nothing worn at all: every slot bare, with shirt and tabard left hands-off.\n\nIt is not a snapshot of what you have on — fill it in by clicking the slots in the grid, or press Save to replace it with what you are wearing.")

    pane.saveBtn:SetScript("OnClick", function()
        local set = SelectedSet()
        if not set then return end
        HostCall("SaveSet", set, IgnoreScratch())
        Refresh()
    end)
    -- The warning is the tooltip's main job now. Save has always meant "replace
    -- this set with what I am wearing", but until slots could be authored one at
    -- a time that was indistinguishable from "keep this set up to date" -- there
    -- was nothing in a set that Save could destroy. There is now, and the
    -- tooltip is the only place a player finds out before pressing it.
    Tip(pane.saveBtn, "Save", function()
        return pane.saveBtn.disabledReason
            or "Replace this set with what you are wearing right now. Every slot it does not ignore is re-snapshotted from your body, and the hands-off flags you have set are written in.\n\nThat overwrites anything you chose slot by slot in the grid: Save does not merge, it replaces."
    end)

    pane.equipBtn:SetScript("OnClick", function()
        local set = SelectedSet()
        if not set then return end
        HostCall("EquipSet", set)
        Refresh()
    end)
    Tip(pane.equipBtn, "Equip", function()
        return pane.equipBtn.disabledReason
            or pane.equipBtn.queueHint
            or "Check the whole plan, then run it. If anything blocks it, nothing moves at all."
    end)

    pane.deleteBtn:SetScript("OnClick", function()
        local set = SelectedSet()
        if not set then return end
        if StaticPopupDialogs and StaticPopupDialogs["COMMANDER_ARMORY_DELETE_SET"] and StaticPopup_Show then
            StaticPopup_Show("COMMANDER_ARMORY_DELETE_SET", set.name or "?")
        else
            HostCall("DeleteSet", set)
            Refresh()
        end
    end)
    Tip(pane.deleteBtn, "Delete", function()
        return pane.deleteBtn.disabledReason or "Delete this set. Asks first. Nothing you are wearing changes."
    end)

    pane.renameBtn:SetScript("OnClick", function()
        if SelectedSet() then OpenNameDialog("RENAME") end
    end)
    Tip(pane.renameBtn, "Rename / Icon", function()
        return pane.renameBtn.disabledReason or "Change this set's name and its icon."
    end)

    -- The name header: the selected set's name, clickable, editable in place.
    -- The Rename button stays -- it also carries the icon grid -- but the name
    -- on its own is the thing that gets changed most and it should not need a
    -- modal window to change it.
    BuildNameHeader()

    -- The slot grid: 19 slots, our own three states, and the diff.
    local order = (D and D.Slots) or {}
    for i = 1, #order do
        slotCells[order[i].id] = BuildSlotCell(order[i], i)
    end

    local gridRows = ceil(#order / GRID_COLS)
    local statsTop = GRID_TOP - (gridRows * GRID_CELL) - 8

    pane.statsTitle = MakeText(pane, 10, THEME.accent, "LEFT")
    pane.statsTitle:SetPoint("TOPLEFT", pane, "TOPLEFT", GRID_X, statsTop)
    pane.statsTitle:SetText("STATS")

    -- Bounded rather than free-running: this is the one block that grows when a
    -- set is selected, and the space it grows into is the column below it, all
    -- the way down to the footer. An unbounded font string would run through the
    -- footer instead of stopping at it.
    pane.statsBody = MakeText(pane, 10, THEME.text, "LEFT")
    pane.statsBody:SetPoint("TOPLEFT", pane.statsTitle, "BOTTOMLEFT", 0, -3)
    pane.statsBody:SetWidth(PANE_W - GRID_X)
    pane.statsBody:SetHeight(max(24, (statsTop - 16) - FOOT_TOP))
    pane.statsBody:SetJustifyV("TOP")

    -- The footer, full width under both columns: the explicit dirty indicator,
    -- the pre-flight sentence, the world hints and the run bar. Retail's
    -- implicit version of the first -- Save is greyed out, work out why -- is a
    -- documented source of confusion.
    pane.statusPip = MakeGlyph(pane, "dot", 8, 8, false)
    pane.statusPip:SetPoint("TOPLEFT", pane, "TOPLEFT", 1, FOOT_TOP)
    pane.status = MakeText(pane, 10, THEME.text, "LEFT")
    pane.status:SetPoint("LEFT", pane.statusPip, "RIGHT", 4, 0)
    pane.status:SetPoint("RIGHT", pane, "RIGHT", 0, 0)

    -- The pre-flight panel: the product's whole thesis, in a sentence.
    pane.preflight = MakeText(pane, 10, THEME.text, "LEFT")
    pane.preflight:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, FOOT_TOP - 14)
    pane.preflight:SetWidth(PANE_W)
    pane.preflight:SetHeight(38)
    pane.preflight:SetJustifyV("TOP")

    -- Free bag slots and the world's refusals. It used to be pinned at -332 in
    -- a 372-tall pane, which put it on the window's bottom moulding and clipped
    -- it; it hangs off the pre-flight block now, inside the usable inset.
    pane.detail = MakeText(pane, 9, THEME.textDim, "LEFT")
    pane.detail:SetPoint("TOPLEFT", pane.preflight, "BOTTOMLEFT", 0, -3)
    pane.detail:SetWidth(PANE_W)
    pane.detail:SetHeight(12)
    pane.detail:SetJustifyV("TOP")

    -- Run progress and the combat queue, with the cancel affordance the queue
    -- is worthless without.
    pane.progressBack = MakeTexture(pane, "BACKGROUND", THEME.sunken)
    pane.progressBack:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, 1)
    pane.progressBack:SetSize(PANE_W - 84, 12)
    pane.progressFill = MakeTexture(pane, "ARTWORK", THEME.accent)
    pane.progressFill:SetPoint("TOPLEFT", pane.progressBack, "TOPLEFT", 0, 0)
    pane.progressFill:SetPoint("BOTTOMLEFT", pane.progressBack, "BOTTOMLEFT", 0, 0)
    pane.progressFill:SetWidth(1)
    pane.progressText = MakeText(pane, 9, THEME.text, "LEFT")
    pane.progressText:SetPoint("LEFT", pane.progressBack, "LEFT", 3, 0)

    pane.cancelBtn = PaneButton(pane, "Cancel", 78)
    pane.cancelBtn:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    pane.cancelBtn:SetScript("OnClick", function()
        HostCall("CancelQueue")
        Refresh()
    end)
    Tip(pane.cancelBtn, "Cancel", "Drop the queued swap. Nothing that has already moved moves back.")

    return pane
end

-- Painting one slot cell against the selected set's diff.
local function PaintSlotCell(cell, snapshot, set, changeBySlot, warnBySlot)
    local slotID = cell.slotID
    local worn = snapshot and snapshot.equipped and snapshot.equipped[slotID]
    local lines = {}

    cell.tex:SetDesaturated(false)
    cell.tex:SetVertexColor(1, 1, 1, 1)
    cell.tex:SetAlpha(1)

    if worn and worn.icon then
        cell.tex:SetTexture(worn.icon)
        lines[#lines + 1] = { QualityHex(worn.quality) .. (worn.name or "?") .. "|r", 1, 1, 1 }
    else
        -- The empty-slot art Blizzard already ships for this slot; a blank cell
        -- reads as "broken" and an empty slot is not.
        local infoName = D and D.SlotInfoName and D.SlotInfoName(slotID)
        local ok, _, texture = pcall(GetInventorySlotInfo, infoName or "HeadSlot")
        cell.tex:SetTexture((ok and texture) or QUESTION_MARK)
        cell.tex:SetAlpha(0.5)
        lines[#lines + 1] = { "|cff777777empty|r", 0.8, 0.8, 0.8 }
    end

    -- Locked is desaturation and broken is Blizzard's own 0.9/0/0 red. Both are
    -- facts about the ITEM; ignored is a fact about the SET and gets its own
    -- overlay so the three never have to be told apart by shade.
    if worn and worn.locked then
        cell.tex:SetDesaturated(true)
        lines[#lines + 1] = { "In flight — wait for it to settle.", 0.7, 0.7, 0.7 }
    end
    if worn and worn.broken then
        cell.tex:SetVertexColor(THEME.broken[1], THEME.broken[2], THEME.broken[3])
        lines[#lines + 1] = { "Broken. It equips fine, it just gives no stats.", 0.9, 0.4, 0.3 }
    end

    local slot = D and D.SlotByID and D.SlotByID[slotID]
    local ignored = set and slot and ScratchIgnored(set, slot.key)
    if ignored then
        cell.ignoreMark:Show()
        lines[#lines + 1] = { "Hands off: this set leaves this slot exactly as it is.",
            THEME.ignore[1], THEME.ignore[2], THEME.ignore[3] }
    else
        cell.ignoreMark:Hide()
        -- IGNORED and EMPTY are different instructions and the tooltip says
        -- which one this is in words. Ignored = leave it alone. Empty = take
        -- whatever is here off and put it in my bags.
        if set and slot and SetEntryState(set, slot.key) == STATE_EMPTY then
            lines[#lines + 1] = { "This set wants this slot bare — whatever is here goes to your bags.",
                THEME.warn[1], THEME.warn[2], THEME.warn[3] }
        end
    end

    -- The one case where the client overrides the module's central promise: a
    -- landing two-hander displaces the off-hand whatever the set says, and it
    -- does so even when the set was told to leave that slot alone. The plan
    -- warns instead of refusing, because the swap is legal and was asked for --
    -- so this is the one thing on the grid that happens DESPITE the hands-off
    -- flag, and it gets a stripe an ignored cell otherwise never shows. The
    -- engine's own sentence goes in the tooltip, where there is room to name
    -- both items; the pre-flight panel gets the short form.
    local warnText = slot and warnBySlot and warnBySlot[slot.key]
    if warnText then
        lines[#lines + 1] = { warnText, THEME.warn[1], THEME.warn[2], THEME.warn[3] }
    end

    local change = changeBySlot and changeBySlot[slotID]
    if change and not ignored then
        local color, text
        if change.status == "MISSING" then
            color, text = THEME.bad, "The item this set wants is nowhere in your bags or bank."
        elseif change.status == "IN_BANK" then
            color, text = THEME.bank, "The item this set wants is in your bank."
        elseif change.status == "LOCKED" then
            color, text = THEME.warn, "The item this set wants is in flight."
        elseif change.action == "EQUIP" then
            color = THEME.ok
            text = "Will equip " .. ((change.to and change.to.name) or "an item") .. "."
            if change.status == "LOOSE" then
                text = text .. " (a different copy — same item, different enchant or gems)"
            end
        elseif change.action == "REMOVE" then
            color, text = THEME.warn, "Will be taken off and put in your bags."
        end
        if color then
            cell.stripe:SetVertexColor(color[1], color[2], color[3], 1)
            cell.stripe:Show()
            lines[#lines + 1] = { text, color[1], color[2], color[3] }
        else
            cell.stripe:Hide()
        end
    elseif warnText then
        cell.stripe:SetVertexColor(THEME.warn[1], THEME.warn[2], THEME.warn[3], 1)
        cell.stripe:Show()
    else
        cell.stripe:Hide()
    end

    if not set then
        lines[#lines + 1] = { "Click to see everything that fits here.", 0.5, 0.5, 0.5 }
    else
        -- From this grid the popout AUTHORS: it writes the set, and equips
        -- nothing. Said here because the same list opened from the paperdoll
        -- does the opposite, and the only way to know which you are getting is
        -- to be told.
        lines[#lines + 1] = { "Click to choose what this set puts here — hands-off and bare are in the same list. Nothing is equipped.",
            0.5, 0.5, 0.5 }
    end
    cell.tooltipLines = lines
end

local function PaintStats(set, snapshot)
    if not set or not snapshot then
        pane.statsBody:SetText("|cff777777Select a set to see what it is worth.|r")
        return
    end
    local setStats, _, setAvg = EngineCall("SetStats", set, snapshot)
    if type(setStats) ~= "table" then
        pane.statsBody:SetText("|cff777777No stat totals available.|r")
        return
    end

    -- The worn side goes through EquippedStats, which the engine ships for
    -- exactly this and which fills its OWN scratch table. The previous route --
    -- capture a synthetic "what I am wearing" set and run SetStats over it --
    -- called SetStats twice, and SetStats returns one shared scratch table
    -- unless it is handed an `out`. So both halves of the comparison were the
    -- same table, wiped and refilled by the second call, and StatDelta was
    -- comparing it with itself: zero rows, no error, and a STATS block that
    -- read as "this set happens to be identical to what you have on".
    local wornStats = EngineCall("EquippedStats", snapshot)

    local lines = {}
    if setAvg then
        lines[#lines + 1] = format("|cffffd100Item level|r %.1f", setAvg)
    end

    local deltas = (type(wornStats) == "table") and EngineCall("StatDelta", setStats, wornStats) or nil
    if type(deltas) == "table" and #deltas > 0 then
        tsort(deltas, function(a, b)
            return math.abs(tonumber(a.delta) or 0) > math.abs(tonumber(b.delta) or 0)
        end)
        for i = 1, min(#deltas, 9) do
            local d = deltas[i]
            local value = tonumber(d.delta) or 0
            if value ~= 0 then
                local color = value > 0 and "|cff66dd66" or "|cffee6644"
                lines[#lines + 1] = format("%s%+d|r %s", color, value, d.label or d.key or "?")
            end
        end
    end
    if #lines == 0 then
        lines[1] = "|cff777777Identical to what you are wearing.|r"
    end
    pane.statsBody:SetText(tconcat(lines, "\n"))
end

local function PaintRun()
    local run = ReadRun()
    local queued = HostCall("IsQueued")
    local status = run and run.status

    if queued then
        pane.progressText:SetText("|cffffd100Queued|r — runs the instant combat, casting or death lets go")
        pane.progressFill:SetWidth(1)
        pane.progressBack:Show()
        pane.cancelBtn:Show()
        SetButtonState(pane.cancelBtn, true)
        return
    end

    if status == "RUNNING" or status == "WAITING" then
        local done, total = run.done, run.total
        local label = run.label and (" " .. run.label) or ""
        local waiting = (status == "WAITING") and " (waiting for an item to settle)" or ""
        pane.progressText:SetText(format("Equipping%s — %d of %d%s", label, done, max(total, done), waiting))
        local width = pane.progressBack:GetWidth() or 1
        local fraction = (total > 0) and (done / total) or 0
        pane.progressFill:SetWidth(max(1, width * min(fraction, 1)))
        pane.progressBack:Show()
        pane.cancelBtn:Show()
        SetButtonState(pane.cancelBtn, true)
        return
    end

    if status == "TIMEOUT" then
        pane.progressText:SetText("|cffee4433The swap stalled|r — the client stopped reporting item locks. Try again.")
        pane.progressFill:SetWidth(1)
        pane.progressBack:Show()
        pane.cancelBtn:Hide()
        return
    end

    pane.progressBack:Hide()
    pane.progressFill:SetWidth(1)
    pane.progressText:SetText("")
    pane.cancelBtn:Hide()
end

function RefreshPane()
    if not pane or not pane:IsShown() then return end
    local snapshot = Snapshot()
    local sets = Sets()
    local selected, selectedIndex = SelectedSet()

    local maxOffset = max(0, #sets - SET_ROWS)
    if setOffset > maxOffset then setOffset = maxOffset end

    -- The header names the selected set and is the control that renames it.
    -- An open editor survives a repaint -- a run finishing mid-edit must not
    -- swallow what has been typed -- but it does NOT survive the selection
    -- moving out from under it, because it would then be editing a set the
    -- player is no longer looking at.
    if nameEditing and nameEditSet ~= selected then EndNameEdit() end
    if selected then
        pane.nameBtn.text:SetText(selected.name or "?")
        pane.nameBtn.pencil:Show()
        SetButtonState(pane.nameBtn, true)
    else
        if nameEditing then EndNameEdit() end
        pane.nameBtn.text:SetText("|cff777777No set selected|r")
        pane.nameBtn.pencil:Hide()
        SetButtonState(pane.nameBtn, false, "Select a set first.")
    end

    pane.listEmpty:SetShown(#sets == 0)

    -- The set list. Every row carries the live summary retail replaces with a
    -- red name: what it changes, what it leaves alone, what is in the bank.
    for i = 1, SET_ROWS do
        local row = setRows[i]
        local index = i + setOffset
        local set = sets[index]
        if set then
            row.set, row.setIndex = set, index
            row.tex:SetTexture(set.icon or QUESTION_MARK)
            row.name:SetText(set.name or "?")
            -- The scratchpad holds the SELECTED set's pending hands-off edits,
            -- so it is threaded into that row's diff and no other. Folding it
            -- into every summary would report one set's unsaved flags against
            -- all of them.
            local diff = EngineCall("DiffSet", set, snapshot, nil,
                (set == selected) and IgnoreScratch() or nil)
            row.summary:SetText(DiffSummary(diff))
            row.tooltipLine = DiffSummary(diff):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if diff and diff.isEquipped then
                row.check:Show()
                row.name:SetTextColor(THEME.ok[1], THEME.ok[2], THEME.ok[3])
            else
                row.check:Hide()
                row.name:SetTextColor(THEME.text[1], THEME.text[2], THEME.text[3])
            end
            if set == selected and SetIsDirty(set, snapshot) then
                row.dirty:Show()
            else
                row.dirty:Hide()
            end
            if set == selected then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.set, row.setIndex = nil, nil
            row:Hide()
        end
    end

    -- The grid, the pre-flight sentence and the Equip button all describe ONE
    -- decision, so all three are computed here, from one diff and one plan,
    -- before a single cell is painted.
    local ignore = IgnoreScratch()
    local diff = selected and EngineCall("DiffSet", selected, snapshot, paneDiff, ignore) or nil

    -- The host's Preflight rather than a bare PlanSet: it threads the ignore
    -- scratchpad through, which is what the actual run does. Without it the
    -- pane refused a set whose only problem was a slot the player had just
    -- marked hands-off -- the grid painted the slot ignored and the pre-flight
    -- went on calling its boots missing, so the fix was visible and unusable.
    local plan = selected and HostCall("Preflight", selected) or nil
    if not plan and selected then
        -- No host: the engine directly, with the opts the host would have
        -- passed. Never PlanSet(set, snapshot) on its own -- a plan that cannot
        -- see the scratchpad is answering a question nobody asked.
        plan = EngineCall("PlanSet", selected, snapshot, { ignore = ignore })
    end

    local changeBySlot = {}
    if diff and type(diff.changes) == "table" then
        for _, change in ipairs(diff.changes) do
            if change.slotID then changeBySlot[change.slotID] = change end
        end
    end

    -- Warnings are per-slot and are NOT blockers: they name a slot the swap is
    -- about to touch anyway. The engine's own full sentence goes to the cell,
    -- which has a tooltip to put it in.
    local warnBySlot = {}
    for _, reason in ipairs((plan and plan.reasons) or {}) do
        if reason.warning == true and reason.slotKey then
            warnBySlot[reason.slotKey] = reason.text or ReasonPhrase(reason, plan, snapshot)
        end
    end

    for _, cell in pairs(slotCells) do
        PaintSlotCell(cell, snapshot, selected, changeBySlot, warnBySlot)
    end

    -- The explicit dirty indicator.
    if not selected then
        SetGlyphColor(pane.statusPip, THEME.textDim)
        pane.status:SetText("|cff777777No set selected.|r")
    elseif SetIsDirty(selected, snapshot) then
        SetGlyphColor(pane.statusPip, THEME.warn)
        local why = ScratchDiffers(selected)
            and "hands-off flags changed" or "differs from what you are wearing"
        pane.status:SetText(format("|cffffd100Unsaved|r — %s", why))
    else
        SetGlyphColor(pane.statusPip, THEME.ok)
        pane.status:SetText("|cff66dd66Saved|r — this set matches what is stored")
    end

    -- The pre-flight sentence, off the plan resolved above.
    if not plan and selected and diff then
        -- No planner at all: fall back to the diff, which at least knows what
        -- is missing and what is banked.
        plan = {
            ok = (tonumber(diff.missing) or 0) == 0 and (tonumber(diff.inBank) or 0) == 0,
            actions = diff.changes,
            reasons = {},
        }
        for _, change in ipairs(diff.changes or {}) do
            if change.status == "MISSING" or change.status == "IN_BANK" then
                plan.reasons[#plan.reasons + 1] = {
                    code = change.status,
                    itemName = (change.to and change.to.name) or nil,
                    slotKey = change.slotKey,
                }
            end
        end
    end
    pane.preflight:SetText(VerdictText(selected, plan, snapshot))

    local hints = {}
    if snapshot then
        hints[#hints + 1] = format("%d free bag slot%s",
            tonumber(snapshot.freeBagSlots) or 0, (tonumber(snapshot.freeBagSlots) or 0) == 1 and "" or "s")
        if snapshot.atBank then hints[#hints + 1] = "at the bank" end
        if snapshot.inCombat then hints[#hints + 1] = "in combat" end
        if snapshot.merchant then hints[#hints + 1] = "|cffee4433merchant open — swaps refused|r" end
    end
    pane.detail:SetText(tconcat(hints, " |cff555555·|r "))

    PaintStats(selected, snapshot)
    PaintRun()

    -- Every disabled button says why. A greyed control with no explanation is
    -- the thing this module exists to stop shipping.
    SetButtonState(pane.newBtn, true)

    pane.equipBtn.queueHint = nil

    if not selected then
        SetButtonState(pane.saveBtn, false, "Select a set first — Save re-snapshots the set you have chosen.")
        pane.equipBtn:SetText("Equip")
        SetButtonState(pane.equipBtn, false, "Select a set first.")
        SetButtonState(pane.deleteBtn, false, "Select a set first.")
        SetButtonState(pane.renameBtn, false, "Select a set first.")
    else
        local dirty = SetIsDirty(selected, snapshot)
        SetButtonState(pane.saveBtn, dirty,
            "Nothing to save: this set already matches what you are wearing and its hands-off flags are unchanged.")

        -- plan.ok is the enable test, and the ONLY one. A plan may now carry
        -- reasons while still being ok -- a warning rides along on a swap that
        -- runs -- so counting reasons here would grey out a working set and
        -- turn a silent problem into a false refusal, which is the worse of the
        -- two (D3a). Actions are counted separately, because an ok plan with
        -- nothing in it is "already wearing it", not "ready".
        local actions = (plan and type(plan.actions) == "table") and #plan.actions or 0
        local canEquip = (plan and plan.ok and actions > 0) and true or false

        if canEquip then
            pane.equipBtn:SetText("Equip")
            SetButtonState(pane.equipBtn, true)
        elseif diff and diff.isEquipped then
            pane.equipBtn:SetText("Equip")
            SetButtonState(pane.equipBtn, false, "You are already wearing this set.")
        elseif PlanIsQueueable(plan) then
            -- The engine forces ok = false in combat, so requiring plan.ok here
            -- greyed the primary control at the exact moment the combat queue
            -- exists to serve -- while a double-click on the set row went
            -- straight past the button and queued it anyway. A button that
            -- refuses what a double-click accepts reads as a bug from either
            -- direction, and it hid the cheapest big win on this client behind
            -- a gesture nobody is told about (D7, UX.md ranked #2).
            --
            -- Relabelled rather than left saying Equip, because it no longer
            -- equips: it schedules. Genuine blockers -- a missing item, bags
            -- with no room -- still fall through to the disabled branch with
            -- their own sentence.
            pane.equipBtn:SetText("Queue")
            SetButtonState(pane.equipBtn, true)
            pane.equipBtn.queueHint =
                "You cannot swap gear this second, so this hands the set to the queue. It runs the instant combat, casting or death lets go, and it can be cancelled until then."
        else
            pane.equipBtn:SetText("Equip")
            SetButtonState(pane.equipBtn, false,
                (VerdictText(selected, plan, snapshot):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
        end
        SetButtonState(pane.deleteBtn, true)
        SetButtonState(pane.renameBtn, true)
    end
end

-- ---------------------------------------------------------------------------
-- The name / icon dialog
-- ---------------------------------------------------------------------------

local ICON_COLS, ICON_ROWS, ICON_SIZE = 8, 5, 30

-- A curated fallback for a client (or a harness) with no macro-icon API. Small
-- on purpose: it exists so the dialog is never empty, not so it is a library.
local FALLBACK_ICONS = {
    "Interface\\Icons\\INV_Chest_Plate06", "Interface\\Icons\\INV_Sword_39",
    "Interface\\Icons\\INV_Shield_06", "Interface\\Icons\\INV_Staff_13",
    "Interface\\Icons\\INV_Misc_Cape_18", "Interface\\Icons\\INV_Helmet_24",
    "Interface\\Icons\\INV_Boots_Chain_05", "Interface\\Icons\\INV_Gauntlets_28",
    "Interface\\Icons\\INV_Jewelry_Ring_25", "Interface\\Icons\\INV_Misc_Fish_02",
    "Interface\\Icons\\Ability_Warrior_DefensiveStance", "Interface\\Icons\\Ability_DualWield",
    "Interface\\Icons\\Spell_Holy_PowerWordShield", "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain", "Interface\\Icons\\Ability_Rogue_Sprint",
}

local iconList
local dialog
local dialogMode, dialogIcon, dialogOffset = "NEW", nil, 0
local iconButtons = {}

local function BuildIconList()
    if iconList then return iconList end
    iconList = {}
    if GetNumMacroIcons and GetMacroIconInfo then
        local ok, count = pcall(GetNumMacroIcons)
        if ok and type(count) == "number" then
            for i = 1, min(count, 1200) do
                local fine, texture = pcall(GetMacroIconInfo, i)
                if fine and texture then iconList[#iconList + 1] = texture end
            end
        end
    elseif GetMacroIcons then
        pcall(GetMacroIcons, iconList)
    end
    if #iconList == 0 then
        for i = 1, #FALLBACK_ICONS do iconList[i] = FALLBACK_ICONS[i] end
    end
    return iconList
end

local RefreshDialog

local function BuildDialog()
    if dialog then return dialog end
    local f = CreateFrame("Frame", "CommanderArmoryNameDialog", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(ICON_COLS * ICON_SIZE + 40, ICON_ROWS * ICON_SIZE + 128)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("Commander Armory") end
    f:Hide()
    if UISpecialFrames then tinsert(UISpecialFrames, "CommanderArmoryNameDialog") end

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -32)
    label:SetText("Name")

    local nameBox = CreateFrame("EditBox", "CommanderArmorySetNameBox", f, "InputBoxTemplate")
    nameBox:SetSize(ICON_COLS * ICON_SIZE - 18, 20)
    nameBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 6, -4)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(32)
    nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.nameBox = nameBox

    for i = 1, ICON_COLS * ICON_ROWS do
        local btn = CreateFrame("Button", "CommanderArmoryIconButton" .. i, f)
        btn:SetSize(ICON_SIZE - 3, ICON_SIZE - 3)
        local col = (i - 1) % ICON_COLS
        local rowN = floor((i - 1) / ICON_COLS)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 18 + col * ICON_SIZE, -78 - rowN * ICON_SIZE)
        btn.tex = btn:CreateTexture(nil, "ARTWORK")
        btn.tex:SetAllPoints()
        btn.sel = MakeTexture(btn, "OVERLAY", { THEME.accent[1], THEME.accent[2], THEME.accent[3], 0.45 })
        btn.sel:SetAllPoints()
        btn.sel:Hide()
        btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
        btn.hl:SetTexture(WHITE)
        btn.hl:SetVertexColor(1, 1, 1, 0.2)
        btn.hl:SetAllPoints()
        btn:SetScript("OnClick", function(self)
            if self.texturePath then
                dialogIcon = self.texturePath
                RefreshDialog()
            end
        end)
        iconButtons[i] = btn
    end

    f:SetScript("OnMouseWheel", function(_, delta)
        local icons = BuildIconList()
        local maxOffset = max(0, ceil(#icons / ICON_COLS) - ICON_ROWS)
        dialogOffset = min(maxOffset, max(0, dialogOffset - delta))
        RefreshDialog()
    end)

    local accept = CreateFrame("Button", "CommanderArmoryNameAccept", f, "UIPanelButtonTemplate")
    accept:SetSize(90, 22)
    accept:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    accept:SetText("Save")
    accept:SetScript("OnClick", function()
        local name = (f.nameBox:GetText() or ""):match("^%s*(.-)%s*$")
        if name == "" then
            print("|cff66ccffCommander Armory|r: |cffff4433a set needs a name.|r")
            return
        end
        if dialogMode == "RENAME" then
            local set = SelectedSet()
            if not set then return end
            local ok, reason = HostCall("RenameSet", set, name, dialogIcon or set.icon)
            if ok ~= true then
                -- Refuse in the same words the inline editor uses, and keep the
                -- dialog open with the typed name still in it. Hiding on a
                -- refusal is how "nothing happened" gets shipped.
                print("|cff66ccffCommander Armory|r: |cffff4433"
                    .. (reason or "that name will not do.") .. "|r")
                return
            end
        else
            -- The HOST's NewSet, never the engine's. E.NewSet is a pure
            -- constructor: it hands back a bare table and stops there. The
            -- host's inserts that table into Sets(), assigns its order, makes
            -- it the selection and loads its ignore scratchpad -- and until it
            -- has, the set exists only in this local. SaveSet then captured
            -- nineteen slots into a table nobody was holding, printed
            -- saved "Arena", and the whole thing was collected on the next
            -- garbage pass: every set made through this dialog was lost, and
            -- only /cgear save ever worked.
            --
            -- There is deliberately no literal fallback beside this call. A
            -- detached table IS the bug, so resurrecting one the moment the
            -- host is missing would just hide it again; the honest failure is
            -- to say nothing was made and leave the dialog open with the name
            -- still typed in it.
            local set = HostCall("NewSet", name, dialogIcon)
            if not set then
                print("|cff66ccffCommander Armory|r: |cffff4433the set store is not ready, so nothing was created.|r")
                return
            end
            -- Deliberately NO SaveSet here. It used to capture the player's gear
            -- into the set the instant it was made, which meant "New" silently
            -- meant "save what I have on" and there was no way to start from
            -- nothing. The host's NewSet now hands back a naked set -- every
            -- slot bare, shirt and tabard hands-off -- and it stays that way
            -- until the player fills it in, slot by slot from the grid or in one
            -- go with Save.
            print(format("|cff66ccffCommander Armory|r: made \"%s\". It specifies nothing worn — click the slots to fill it in, or Save to take what you have on.",
                set.name or name))
        end
        f:Hide()
        Refresh()
    end)

    local cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancel:SetSize(90, 22)
    cancel:SetPoint("RIGHT", accept, "LEFT", -6, 0)
    cancel:SetText("Cancel")
    cancel:SetScript("OnClick", function() f:Hide() end)

    dialog = f
    return f
end

function RefreshDialog()
    if not dialog or not dialog:IsShown() then return end
    local icons = BuildIconList()
    local base = dialogOffset * ICON_COLS
    for i = 1, #iconButtons do
        local btn = iconButtons[i]
        local texture = icons[base + i]
        btn.texturePath = texture
        if texture then
            btn.tex:SetTexture(texture)
            btn.sel:SetShown(texture == dialogIcon)
            btn:Show()
        else
            btn:Hide()
        end
    end
end

function OpenNameDialog(mode)
    BuildDialog()
    dialogMode = mode or "NEW"
    dialogOffset = 0
    local set = SelectedSet()
    if dialogMode == "RENAME" and set then
        dialog.nameBox:SetText(set.name or "")
        dialogIcon = set.icon
    else
        dialog.nameBox:SetText("")
        dialogIcon = FALLBACK_ICONS[1]
    end
    if dialog.TitleText then
        dialog.TitleText:SetText(dialogMode == "RENAME" and "Rename Set" or "New Set")
    end
    dialog:Show()
    dialog.nameBox:SetFocus()
    RefreshDialog()
end

-- The delete confirmation. A KEY is added to StaticPopupDialogs; the table
-- itself is never assigned -- assigning it taints the global for the rest of
-- the session and every piece of FrameXML that later reads it inherits the
-- taint (the Dossier log-out bug, written up at length in CommanderDossier.lua).
if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_ARMORY_DELETE_SET"] = {
        text = "Delete the gear set \"%s\"?\n\nNothing you are wearing changes. This cannot be undone.",
        button1 = "Delete",
        button2 = "Cancel",
        OnAccept = function()
            local set = SelectedSet()
            if set then HostCall("DeleteSet", set) end
            if Refresh then Refresh() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

-- ---------------------------------------------------------------------------
-- Hosting the pane: the sixth tab, and the detached window
-- ---------------------------------------------------------------------------

local armoryFrame, armoryTab, armoryWindow
local tabHooked = false

local TAB_INSET_X, TAB_INSET_Y = 22, -72

function DockPane(host, x, y)
    local p = EnsurePane()
    if not p or not host then return end
    p:SetParent(host)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", host, "TOPLEFT", x, y)
    p:SetFrameLevel((host:GetFrameLevel() or 1) + 2)
    p:Show()
end

-- Everything degrades to nothing if the character frame is absent: this returns
-- nil rather than erroring, which is the RankCheck precedent
-- (CommanderRankCheck.lua:312) and the reason a missing Blizzard frame costs a
-- feature instead of a login error.
function EnsureArmoryTab()
    if armoryFrame then return armoryFrame end
    if not CharacterFrame or not CreateFrame then return nil end
    if type(PanelTemplates_SetNumTabs) ~= "function" then return nil end
    if type(CHARACTERFRAME_SUBFRAMES) ~= "table" then return nil end

    armoryFrame = CreateFrame("Frame", "CommanderArmoryFrame", CharacterFrame)
    armoryFrame:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 0, 0)
    armoryFrame:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", 0, 0)

    -- The window art has to come from US, and that is not obvious.
    --
    -- On this client CharacterFrame is close to an empty container: it draws the
    -- portrait, the title and the close button, and nothing else. Every tab
    -- supplies the whole 384x512 window itself, as four quadrant textures on the
    -- BORDER layer -- PaperDollFrame uses the CharacterTab-* set, SkillFrame the
    -- General-Top* + SkillFrame-Bot* set, and so on. A subframe that draws no
    -- background is therefore fully transparent, and its widgets appear to float
    -- over the game world with no frame around them at all. That is exactly what
    -- shipped in 1.0.0.
    --
    -- We borrow REPUTATION's window rather than the Character tab's, because the
    -- CharacterTab art has the model viewport and the paperdoll slot recesses
    -- baked into it and would fight our own layout.
    --
    -- The first version of this used SkillFrame's bottom halves, which was a
    -- mistake worth recording: Skills' bottom art has a recessed panel baked
    -- into it -- that is where Skills puts its collapse-all button -- and in a
    -- pane that has nothing to put there it reads as a dead region somebody
    -- forgot to fill. The reason it was chosen is that a search of
    -- Blizzard_CharacterFrame/ turns up no General-Bottom texture, which is true
    -- and misleading: the pair lives in Blizzard_UIPanels_Game/Vanilla, in
    -- ReputationFrame.xml, gated `AllowLoadGameType vanilla, tbc` -- so it is
    -- genuinely this client's art, and it is uniform with no recess in it.
    --
    -- All four quadrants anchor TOPLEFT, which is Blizzard's own arrangement
    -- there and simpler than the mixed corner anchors it replaces: a 384x512
    -- window is four fixed tiles at fixed offsets, not four things pinned to
    -- four corners of something that might resize.
    local BACKDROP = {
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",      256, 256,   2,   -1 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight",     128, 256, 258,   -1 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft",   256, 256,   2, -257 },
        { "Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight",  128, 256, 258, -257 },
    }
    for index = 1, #BACKDROP do
        local art = BACKDROP[index]
        local tex = armoryFrame:CreateTexture(
            "CommanderArmoryBackdrop" .. index, "BORDER")
        tex:SetTexture(art[1])
        tex:SetSize(art[2], art[3])
        tex:SetPoint("TOPLEFT", armoryFrame, "TOPLEFT", art[4], art[5])
    end
    -- ToggleCharacter calls PanelTemplates_SetTab(CharacterFrame, subFrame:GetID())
    armoryFrame:SetID(6)
    armoryFrame:Hide()
    armoryFrame:SetScript("OnShow", function()
        DockPane(armoryFrame, TAB_INSET_X, TAB_INSET_Y)
        InvalidateSnapshot()
        RefreshPane()
    end)
    armoryFrame:SetScript("OnHide", function()
        CloseFlyout()
        if pane and pane:GetParent() == armoryFrame then pane:Hide() end
    end)

    -- CHARACTERFRAME_SUBFRAMES is a global table and CharacterFrame_ShowSubFrame
    -- iterates it with pairs(), so adding our name is all it takes for the other
    -- five tabs to hide us correctly.
    local listed = false
    for _, name in pairs(CHARACTERFRAME_SUBFRAMES) do
        if name == "CommanderArmoryFrame" then listed = true end
    end
    if not listed then tinsert(CHARACTERFRAME_SUBFRAMES, "CommanderArmoryFrame") end

    armoryTab = _G["CharacterFrameTab6"]
    if not armoryTab then
        armoryTab = CreateFrame("Button", "CharacterFrameTab6", CharacterFrame, "CharacterFrameTabButtonTemplate")
        armoryTab:SetID(6)
        armoryTab:SetText("Armory")
        local previous = _G["CharacterFrameTab5"]
        if previous then
            armoryTab:SetPoint("LEFT", previous, "RIGHT", -15, 0)
        else
            armoryTab:SetPoint("BOTTOMLEFT", CharacterFrame, "BOTTOMLEFT", 15, 48)
        end
        pcall(PanelTemplates_SetNumTabs, CharacterFrame, 6)
        -- CharacterFrame_TabBoundsCheck loops 1..NUM_CHARACTERFRAME_TABS, a
        -- file-local 5, so tab 6 is never auto-sized. Size it ourselves.
        if type(PanelTemplates_TabResize) == "function" then
            pcall(PanelTemplates_TabResize, armoryTab, 0, nil, 36, 88)
        end
    end

    if not tabHooked and hooksecurefunc and type(CharacterFrameTab_OnClick) == "function" then
        tabHooked = true
        -- The built-in handler is a string-name if/elseif chain that simply
        -- no-ops for tab 6, so a hook is additive rather than a replacement.
        hooksecurefunc("CharacterFrameTab_OnClick", function(self)
            if self and self.GetName and self:GetName() == "CharacterFrameTab6" then
                if ToggleCharacter then ToggleCharacter("CommanderArmoryFrame") end
            end
        end)
    end

    return armoryFrame
end

function EnsureWindow()
    if armoryWindow then return armoryWindow end
    if not CreateFrame then return nil end
    armoryWindow = CreateFrame("Frame", "CommanderArmoryWindow", UIParent)
    armoryWindow:SetSize(PANE_W + 24, PANE_H + 24)
    armoryWindow:SetFrameStrata("HIGH")
    armoryWindow:Hide()
    armoryWindow:SetScript("OnShow", function()
        DockPane(armoryWindow, 12, -12)
        InvalidateSnapshot()
        RefreshPane()
    end)
    armoryWindow:SetScript("OnHide", function()
        CloseFlyout()
        if pane and pane:GetParent() == armoryWindow then pane:Hide() end
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, "CommanderArmoryWindow") end
    return armoryWindow
end

local function ApplyWindowChrome()
    if not armoryWindow then return end
    local ui = Commander and Commander.UI
    if not ui then return end
    if ui.ApplyHudChrome then
        ui.ApplyHudChrome(armoryWindow, db, "Hud", {
            defaultPoint = { point = "CENTER", x = 0, y = 40 },
            title = "Commander Armory",
        })
    end
    -- Unlocked means the player is positioning or scaling the window, and a
    -- window that is not on screen has no grip to take hold of. CONVENTIONS
    -- makes this the consumer's job rather than the framework's: ApplyHudChrome
    -- paints the chrome and stops, so a module that does not show its own frame
    -- while the lock is off ships an option that visibly does nothing --
    -- untick Lock in the settings with the window closed and there is simply
    -- nothing to drag. The price is that the window cannot be dismissed while
    -- unlocked; that is the intended reading of the rule, and locking it again
    -- is one click away in the same panel.
    if ui.HudUnlocked and ui.HudUnlocked(db, "Hud") and not armoryWindow:IsShown() then
        armoryWindow:Show()
    end
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- "This item belongs to" on item tooltips
-- ---------------------------------------------------------------------------
-- The third surface, and the smallest. Hovering a piece of gear anywhere --
-- bags, bank, a merchant, the paperdoll -- names the sets that want it.
--
-- It earns its place because of what it prevents rather than what it shows: the
-- single most expensive mistake a player makes with gear sets is vendoring or
-- disenchanting a piece that a set they have not worn in three weeks depends
-- on, and then discovering it as a red "missing" line at the worst moment. A
-- line on the tooltip is the only place that warning can reach them at the
-- moment it matters.
--
-- We HookScript rather than replace, so this composes with Commander_Tooltip
-- (which owns the anchor) instead of fighting it.

local tooltipHooked = false
local tooltipStamp = {}
local tooltipNames = {}

local function SetsContaining(link)
    if not link or not E or type(E.ItemKey) ~= "function" then return nil end
    local ok, key = pcall(E.ItemKey, link)
    if not ok or not key then return nil end
    local base = (type(E.BaseKey) == "function") and select(2, pcall(E.BaseKey, key)) or nil

    local sets = HostCall("Sets")
    if type(sets) ~= "table" then return nil end

    -- Cleared in place rather than via wipe(): this is the only call site in the
    -- file that would have needed that global, and one scratch table reused per
    -- hover beats a fresh array on every tooltip.
    for i = #tooltipNames, 1, -1 do tooltipNames[i] = nil end
    for _, set in ipairs(sets) do
        local entries = type(set) == "table" and set.entries
        if type(entries) == "table" then
            for _, entry in pairs(entries) do
                if type(entry) == "table" and entry.state == STATE_ITEM and entry.key then
                    -- Exact first, then the base key, so a re-enchanted copy of
                    -- the sword still reports the set that wants it. A loose
                    -- match is flagged, because "this is nearly the item your
                    -- set asked for" is a different and more useful statement
                    -- than silence.
                    if entry.key == key then
                        tooltipNames[#tooltipNames + 1] = set.name
                        break
                    elseif base and entry.baseKey and entry.baseKey == base then
                        tooltipNames[#tooltipNames + 1] = (set.name or "?") .. " |cff808080(variant)|r"
                        break
                    end
                end
            end
        end
    end
    if #tooltipNames == 0 then return nil end
    return table.concat(tooltipNames, ", ")
end

-- Could this item ever BE in a set? The negative line is only worth printing
-- for something a set could name, and without this gate every reagent, potion
-- and quest item in the game grows an Armory line -- which is worse than saying
-- nothing, because it makes the useful line invisible among the noise.
--
-- GetItemInfoInstant is synchronous and never nil for a real item, so this is
-- one call with no cache and no waiting. Ammo is excluded because slot 0 is
-- outside the set model entirely (D4) and "not in any set" would be a lie of
-- implication about a slot no set can ever speak for.
local function ItemCouldBeInASet(link)
    if not link or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return false end
    local ok, _, _, _, equipLoc = pcall(C_Item.GetItemInfoInstant, link)
    if not ok or type(equipLoc) ~= "string" or equipLoc == "" then return false end
    if equipLoc == "INVTYPE_AMMO" then return false end
    local slots = D and D.EquipLocSlots and D.EquipLocSlots[equipLoc]
    if type(slots) ~= "table" or type(slots[1]) ~= "number" then return false end
    return slots[1] ~= (D.AMMO_SLOT or 0)
end

local function InstallTooltipHook()
    if tooltipHooked or not GameTooltip or not GameTooltip.HookScript then return end
    tooltipHooked = true

    local function Decorate(tip)
        if not db or db.EnableArmory == false or db.ShowSetOnTooltip == false then return end
        -- OnTooltipSetItem can fire more than once for one hover, and a naive
        -- handler stacks a duplicate line each time. Stamp the link we last
        -- annotated on this tooltip and bail when it has not changed.
        local ok, _, link = pcall(tip.GetItem, tip)
        if not ok or not link then return end
        if tooltipStamp[tip] == link then return end

        local names = SetsContaining(link)
        tooltipStamp[tip] = link

        if names then
            local accent = THEME.accent or { 1, 0.82, 0.2 }
            tip:AddLine("Armory: " .. names, accent[1], accent[2], accent[3], true)
        elseif ItemCouldBeInASet(link) then
            -- Silence is not an answer. With no line at all, "no set wants this"
            -- is indistinguishable from the option being off, from the addon
            -- having failed to load, and from the tooltip simply not having
            -- updated -- so the one case where the answer is actually useful,
            -- deciding whether a piece is safe to vendor, is the case where the
            -- player cannot tell what they are looking at. Dim grey rather than
            -- the accent, because this is an absence, not a warning.
            tip:AddLine("Armory: not in any set", 0.5, 0.5, 0.5, true)
        else
            return
        end
        tip:Show()   -- re-fit; the added line is taller than the frame we were given
    end

    GameTooltip:HookScript("OnTooltipSetItem", Decorate)
    GameTooltip:HookScript("OnHide", function(tip) tooltipStamp[tip] = nil end)

    -- The comparison tooltips are separate frames and get the same treatment,
    -- because a shift-compare is exactly when you are deciding what to keep.
    for i = 1, 2 do
        local shopping = _G["ShoppingTooltip" .. i]
        if shopping and shopping.HookScript then
            shopping:HookScript("OnTooltipSetItem", Decorate)
            shopping:HookScript("OnHide", function(tip) tooltipStamp[tip] = nil end)
        end
    end
end

CommanderArmoryUI = {}

-- Prefer the character tab, because the set manager belongs next to the
-- paperdoll it describes. The window is the fallback for a client where
-- CharacterFrame never appeared, and the home for the drag/scale chrome.
function CommanderArmoryUI.Toggle()
    if db and db.EnableArmory == false then
        print("|cff66ccffCommander Armory|r: the module is switched off in its settings.")
        return false
    end
    if db and db.ShowArmoryTab ~= false then
        local frame = EnsureArmoryTab()
        if frame and ToggleCharacter then
            ToggleCharacter("CommanderArmoryFrame")
            return true
        end
    end
    local window = EnsureWindow()
    if not window then return false end
    -- Chrome AFTER the toggle, never before. ApplyWindowChrome keeps an
    -- unlocked window on screen, so applying it first would show the window and
    -- let the very next line hide it again -- opening the Armory while the
    -- frame was unlocked would do nothing at all, which is a worse bug than the
    -- one the unlock rule fixes.
    if window:IsShown() then window:Hide() else window:Show() end
    ApplyWindowChrome()
    return true
end

function CommanderArmoryUI.ToggleWindow()
    local window = EnsureWindow()
    if not window then return false end
    if window:IsShown() then window:Hide() else window:Show() end
    ApplyWindowChrome()   -- after the toggle, for the reason above
    return true
end

-- `source` is "PANE" to author the selected set and anything else (or nothing)
-- to wear, which is the keybind's and the paperdoll's meaning.
function CommanderArmoryUI.OpenFlyout(slotID, source)
    local button = D and D.SlotByID and D.SlotByID[slotID] and _G[D.SlotByID[slotID].button]
    OpenFlyout(slotID, button, source)
end

-- "WEAR" or "AUTHOR": what a click on a candidate row means right now.
function CommanderArmoryUI.FlyoutMode()
    return FlyoutMode()
end

-- Begin the inline rename, for a keybind or another surface that wants it.
function CommanderArmoryUI.EditName()
    return BeginNameEdit()
end

function CommanderArmoryUI.CloseFlyout()
    CloseFlyout()
end

function CommanderArmoryUI.IsShown()
    return (armoryFrame and armoryFrame:IsShown()) or (armoryWindow and armoryWindow:IsShown()) or false
end

-- Refresh = the data changed. Apply = the settings changed.
function CommanderArmoryUI.Refresh()
    InvalidateSnapshot()
    PaintPaperdollMarkers()
    RefreshPane()
    RefreshFlyout()
end

Refresh = CommanderArmoryUI.Refresh

function CommanderArmoryUI.Apply()
    db = CommanderArmoryDB or db or {}
    THEME.accent = AccentByKey(db.AccentColor)
    RestyleFonts()

    if db.EnableArmory ~= false and (db.ShowSlotFlyouts ~= false or db.ShowIgnoreMarkers ~= false) then
        InstallPaperdollHooks()
    end
    if db.EnableArmory ~= false and db.ShowSetOnTooltip ~= false then
        -- Hooked once and never unhooked: the handler re-reads the setting on
        -- every hover, so turning the option off stops the line rather than
        -- leaving a dead hook that has to be reasoned about.
        InstallTooltipHook()
    end
    if db.EnableArmory ~= false then
        -- Built eagerly rather than on first show. Nineteen slot cells and seven
        -- rows cost nothing at login, and a pane that exists is a pane the
        -- settings listener, the slash command and the harness can all reach
        -- without first opening the character sheet.
        EnsurePane()
    end
    if db.EnableArmory ~= false and db.ShowArmoryTab ~= false then
        EnsureArmoryTab()
    end
    if armoryTab then
        if db.EnableArmory ~= false and db.ShowArmoryTab ~= false then
            armoryTab:Show()
        else
            armoryTab:Hide()
            if armoryFrame and armoryFrame:IsShown() and CharacterFrame_ShowSubFrame then
                pcall(CharacterFrame_ShowSubFrame, "PaperDollFrame")
            end
        end
    end
    if armoryWindow then ApplyWindowChrome() end
    if db.EnableArmory == false then CloseFlyout() end

    CommanderArmoryUI.Refresh()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- One events frame, only PLAYER_LOGIN at file scope. Everything else is
-- registered once the DB is bound and the frames exist, which is the suite's
-- fixed main-file shape.

local refreshPending = false

local function RefreshSoon()
    if refreshPending then return end
    refreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            refreshPending = false
            CommanderArmoryUI.Refresh()
        end)
    else
        refreshPending = false
        CommanderArmoryUI.Refresh()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        db = CommanderArmoryDB or db or {}
        E = E or CommanderArmoryEngine
        D = D or CommanderArmoryData

        CommanderArmoryUI.Apply()

        -- The paperdoll is worth repainting on anything that can change what a
        -- slot holds. All of these are throttled through one debounce: a
        -- 15-slot swap fires PLAYER_EQUIPMENT_CHANGED fifteen times.
        events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        events:RegisterEvent("UNIT_INVENTORY_CHANGED")
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        events:RegisterEvent("ITEM_LOCK_CHANGED")
        events:RegisterEvent("BANKFRAME_OPENED")
        events:RegisterEvent("BANKFRAME_CLOSED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")

        if Commander and Commander.AddListener then
            local eventName = (COMMANDER_ARMORY_EVENTS and COMMANDER_ARMORY_EVENTS.UPDATE)
                or "COMMANDER_ARMORY_UPDATE"
            Commander.AddListener(eventName, function() CommanderArmoryUI.Apply() end)
        end
        return
    end

    RefreshSoon()
end)

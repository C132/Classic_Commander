-- Commander Tracer: the plumbing.
--
-- Floating combat text, rebuilt on the suite's rules. The combat log is the
-- feed (every number arrives with its spell, its school, its target and
-- whether it crit, which the stock text never had), the engine next door
-- decides what each event is and where on the screen it is at any moment,
-- and this file is what the client sees: six anchored lanes, a pool of
-- entry frames per lane, one OnUpdate driving all of them, the CVars that
-- switch Blizzard's own text off while this runs, and the sounds.
--
-- What is deliberately NOT here: any reasoning about events. A hit is a
-- hit because CommanderTracer_Engine.Classify said so, and that file runs
-- under plain luajit with the harness feeding it the 2.5.x field layout.

local DATA = CommanderTracer_Data
local E = CommanderTracer_Engine

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SOUND_GAP = 0.4        -- the same sound slot rings at most this often

-- ---------------------------------------------------------------------------
-- Settings accessors. A nil DB (the moment before ADDON_LOADED) can never
-- take the lanes down.
-- ---------------------------------------------------------------------------
local function G(key, default)
    local db = CommanderTracerDB
    if not db then return default end
    local value = db[key]
    if value == nil then return default end
    return value
end

local function L(P, key)
    local db = CommanderTracerDB
    local value = db and db[P .. key]
    if value == nil then return DATA.LANE_DEFAULTS[key] end
    return value
end

local function Enabled()
    return CommanderTracerDB and CommanderTracerDB.Enable and true or false
end

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------
local lanes = {}             -- key -> lane runtime (in DATA.LANES order in laneList)
local laneList = {}
local ctx = { player = nil, pet = nil }
local classColor = nil
local driver                 -- the one OnUpdate frame
local volley = nil           -- { start = t, shots = {...}, next = i } while a test runs
local lastSound = {}         -- slot key -> GetTime() it last rang
local cvarsPending = false
local built = false

local function ConsolePalette()
    return CommanderConsole_Colors
end

-- ---------------------------------------------------------------------------
-- Sounds
-- ---------------------------------------------------------------------------
local function PlaySlot(slotKey, force)
    local choice = G(slotKey, "NONE")
    local snd = DATA.SOUND_BY_KEY[choice]
    if not snd or snd.silent then return false end
    local now = GetTime()
    if not force and lastSound[slotKey] and now - lastSound[slotKey] < SOUND_GAP then return false end
    lastSound[slotKey] = now
    if snd.kit or snd.id then
        local id = (SOUNDKIT and snd.kit and SOUNDKIT[snd.kit]) or snd.id
        if id and PlaySound then
            local ok, played = pcall(PlaySound, id, "Master")
            if ok and played ~= false then return true end
        end
    end
    if snd.file and PlaySoundFile then
        pcall(PlaySoundFile, snd.file, "Master")
        return true
    end
    return false
end

-- Auditioning from the settings page ignores the gap on purpose
function CommanderTracer_PlaySound(slotKey)
    PlaySlot(slotKey, true)
end

-- ---------------------------------------------------------------------------
-- Entry frames: one pool per lane. A scroll entry is a point with a text
-- and an icon hung off it; a stack row is a panel with a backdrop, an
-- accent, an icon, a main line and a sub line. One frame type serves both,
-- the row parts simply hidden on a scroll lane.
-- ---------------------------------------------------------------------------
local function NewEntryFrame(lane)
    local f = CreateFrame("Frame", nil, lane.root)
    f:SetSize(1, 1)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture(WHITE)
    f.bg:SetAllPoints()
    f.bg:Hide()
    f.accent = f:CreateTexture(nil, "BORDER")
    f.accent:SetTexture(WHITE)
    f.accent:SetWidth(3)
    f.accent:Hide()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon:Hide()
    -- A font object at birth: a bare FontString has no font, and SetText
    -- on one is an error ("Font not set"), so every string starts on the
    -- client's own and takes the lane's face before it is written
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(false)
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.sub:Hide()
    f:Hide()
    return f
end

local function Acquire(lane)
    local f = table.remove(lane.pool)
    if not f then f = NewEntryFrame(lane) end
    f.faceFor = nil
    return f
end

local function Release(lane, f)
    f:Hide()
    f:ClearAllPoints()
    f:SetScale(1)
    lane.pool[#lane.pool + 1] = f
end

local function ApplyFace(fs, cfg, sizeScale)
    local path = DATA.FONTS[cfg.Font] or DATA.FONTS.DEFAULT
    local size = math.max(6, math.floor((tonumber(cfg.FontSize) or 16) * (sizeScale or 1) + 0.5))
    fs:SetFont(path, size, DATA.OUTLINES[cfg.Outline] or "OUTLINE")
    if fs.SetShadowOffset then
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, cfg.Shadow and 1 or 0)
    end
end

local function IconFor(rec)
    if rec.spellId and GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, rec.spellId)
        if ok and tex then return tex end
    end
    return nil
end

-- Lay an entry out from its record. Runs once per entry (and again after a
-- merge), never per frame.
local function Dress(lane, e, f)
    local cfg = lane.cfg
    local rec = e.rec
    local main, sub = E.Text(cfg, rec, G("NumberStyle", "SEPARATED"), G("PetTag", true))
    local r, g, b = E.Color(cfg, rec, classColor, ConsolePalette())
    local stack = (cfg.Motion == "STACK")
    local iconSize = (cfg.Icon ~= "NONE") and (tonumber(cfg.IconSize) or 16) or 0
    local tex = (iconSize > 0) and IconFor(rec) or nil

    ApplyFace(f.text, cfg, 1)
    f.text:SetText(main)
    f.text:SetTextColor(r, g, b)
    f.text:ClearAllPoints()
    f.icon:ClearAllPoints()
    f.sub:ClearAllPoints()
    f.accent:ClearAllPoints()

    if stack then
        local lineH = lane.lineH
        f:SetSize(tonumber(cfg.Width) or 260, lineH)
        f.bg:SetVertexColor(0, 0, 0, 0.55)
        f.bg:SetShown(cfg.RowBackdrop and true or false)
        f.accent:SetVertexColor(r, g, b, 0.9)
        if cfg.Icon == "RIGHT" then
            f.accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
            f.accent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        else
            f.accent:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
            f.accent:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        end
        f.accent:SetShown(cfg.RowAccent and true or false)
        -- Both edges anchored and no wrap: a long sentence is cut at the
        -- row's edge rather than run out past the backdrop
        local rightInset = 8
        if tex then
            f.icon:SetTexture(tex)
            f.icon:SetSize(iconSize, iconSize)
            if cfg.Icon == "RIGHT" then
                f.icon:SetPoint("RIGHT", f, "RIGHT", -6, 0)
                f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
                rightInset = 12 + iconSize
            else
                f.icon:SetPoint("LEFT", f, "LEFT", 7, 0)
                f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 13 + iconSize, -4)
            end
            f.icon:Show()
        else
            f.icon:Hide()
            f.text:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
        end
        f.text:SetPoint("RIGHT", f, "RIGHT", -rightInset, 0)
        if cfg.Sub ~= false and sub then
            ApplyFace(f.sub, cfg, 0.85)
            f.sub:SetText(sub)
            f.sub:SetTextColor(0.75, 0.75, 0.78)
            f.sub:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -1)
            f.sub:SetPoint("RIGHT", f, "RIGHT", -rightInset, 0)
            f.sub:Show()
        else
            f.sub:Hide()
        end
    else
        f:SetSize(1, 1)
        f.bg:Hide()
        f.accent:Hide()
        f.sub:Hide()
        f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
        if tex then
            f.icon:SetTexture(tex)
            f.icon:SetSize(iconSize, iconSize)
            if cfg.Icon == "RIGHT" then
                f.icon:SetPoint("LEFT", f.text, "RIGHT", 4, 0)
            else
                f.icon:SetPoint("RIGHT", f.text, "LEFT", -4, 0)
            end
            f.icon:Show()
        else
            f.icon:Hide()
        end
    end
    e.dirty = false
end

-- Put an entry where the engine says it is. Runs every frame.
local function Place(lane, e, f)
    local cfg = lane.cfg
    local alpha = (e.alpha or 0) * (tonumber(cfg.Alpha) or 1)
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    f:SetAlpha(alpha)
    local s = e.scale or 1
    f:ClearAllPoints()
    if cfg.Motion == "STACK" then
        -- Rows keep their size; a punch on a row would shove its
        -- neighbours, so the merge punch is the accent brightening instead
        f:SetScale(1)
        f:SetPoint("TOPLEFT", lane.root, "TOPLEFT", e.x or 0, e.y or 0)
        if e.punchAt then
            local k = 1 - math.min(1, (GetTime() - e.punchAt) / 0.15)
            f.accent:SetWidth(3 + 4 * k)
        end
    else
        -- Anchor offsets are in the frame's own scaled space: divide them
        -- out so a crit at 1.5x sits where a plain hit would
        f:SetScale(s)
        f:SetPoint("CENTER", lane.root, "CENTER", (e.x or 0) / s, (e.y or 0) / s)
    end
    if not f:IsShown() then f:Show() end
end

-- ---------------------------------------------------------------------------
-- Lanes
-- ---------------------------------------------------------------------------
local function ResolveLane(lane)
    local P = lane.key
    local cfg = lane.cfg
    for key in pairs(DATA.LANE_DEFAULTS) do cfg[key] = L(P, key) end
    lane.lineH = E.LineHeight(cfg)
    lane.enabled = Enabled() and cfg.Enable and true or false
    -- Every entry re-dresses under new settings
    for _, e in ipairs(lane.state.entries) do e.dirty = true end
end

local function ApplyLane(lane)
    ResolveLane(lane)
    local root = lane.root
    local cfg = lane.cfg
    root:SetFrameStrata(G("Strata", "LOW"))
    if cfg.Motion == "STACK" then
        root:SetSize(tonumber(cfg.Width) or 260, lane.lineH)
    else
        root:SetSize(160, lane.lineH)
    end
    Commander.UI.ApplyHudChrome(root, CommanderTracerDB, lane.key, {
        defaultPoint = lane.spec.point,
        title = "Tracer: " .. lane.spec.short,
    })
    local unlocked = Commander.UI.HudUnlocked(CommanderTracerDB, lane.key)
    -- The shared chrome keeps a locked frame mouse-enabled for its triple
    -- right-click unlock. Six invisible anchors round the character would
    -- each be a patch where a right-click camera turn does not start, so a
    -- locked lane never takes the mouse; unlock is the page or /ctracer.
    if not unlocked then root:EnableMouse(false) end
    root:SetShown(lane.enabled or unlocked)
    if not lane.enabled then
        -- Drop what is in flight; a disabled lane draws nothing
        for i = #lane.state.entries, 1, -1 do lane.state.entries[i] = nil end
    end
end

local function BuildLanes()
    if built then return end
    built = true
    for _, spec in ipairs(DATA.LANES) do
        local root = CreateFrame("Frame", "CommanderTracer" .. spec.key, UIParent)
        root:SetSize(160, 24)
        local lane = {
            key = spec.key, spec = spec, root = root, pool = {}, frames = {},
            state = E.NewLane(spec.key), cfg = {}, lineH = 20, enabled = false,
        }
        lanes[spec.key] = lane
        laneList[#laneList + 1] = lane
        -- A label while unlocked, so six green boxes can be told apart
        lane.label = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lane.label:SetPoint("CENTER", root, "CENTER", 0, 0)
        lane.label:SetText(spec.title)
        lane.label:Hide()
    end
end

local function ApplyAll()
    if not built then return end
    for _, lane in ipairs(laneList) do
        ApplyLane(lane)
        lane.label:SetShown(Commander.UI.HudUnlocked(CommanderTracerDB, lane.key))
    end
end

-- ---------------------------------------------------------------------------
-- Dispatch: a record from anywhere becomes entries in lanes
-- ---------------------------------------------------------------------------
local function Copy(rec)
    local c = {}
    for k, v in pairs(rec) do c[k] = v end
    return c
end

local function SpawnIn(lane, rec, now)
    if not lane.enabled then return nil end
    local cfg = lane.cfg
    local minAmount = tonumber(cfg.MinAmount) or 0
    if minAmount > 0 and rec.amount and not rec.missType and rec.amount < minAmount then return nil end
    local e = E.Spawn(lane.state, rec, now, cfg)
    return e
end

local YOURS = { DamageDone = true, PeriodicDone = true, AutoAttack = true, HealDone = true, PeriodicHeal = true, PetDamage = true }

local function Dispatch(rec, now)
    if not (rec and rec.kind) then return end
    local db = CommanderTracerDB
    if not db then return end
    now = now or GetTime()
    -- The big-hit rule and the crit chime, both about YOUR numbers
    if YOURS[rec.kind] and rec.amount then
        local threshold = tonumber(G("BigHitThreshold", 0)) or 0
        if not rec.crit and threshold > 0 and rec.amount >= threshold then
            rec.crit = true
            rec.big = true
        end
        if rec.crit and not rec.big and rec.amount >= (tonumber(G("CritChimeFrom", 1500)) or 1500) then
            PlaySlot("SoundCrit")
        end
    end
    local kind = DATA.KIND_BY_KEY[rec.kind]
    if kind and kind.sound then PlaySlot(kind.sound) end

    local laneKey, ledger = E.Route(db, rec)
    if laneKey and lanes[laneKey] then
        SpawnIn(lanes[laneKey], rec, now)
    end
    if ledger and lanes.Log then
        -- A copy: the ledger merges on its own clock and must not share
        -- amounts with the entry in the number lane
        SpawnIn(lanes.Log, Copy(rec), now)
    end
end

-- For other Commander modules: post a record of a known kind
function CommanderTracer_Post(rec)
    if not Enabled() then return false end
    if type(rec) ~= "table" or not DATA.KIND_BY_KEY[rec.kind] then return false end
    Dispatch(Copy(rec))
    return true
end

-- ---------------------------------------------------------------------------
-- The clock
-- ---------------------------------------------------------------------------
local function StepLane(lane, now)
    local state = lane.state
    if #state.entries == 0 and next(lane.frames) == nil then return end
    E.Step(state, now, lane.cfg, lane.lineH)
    -- Paint the living, stamping each with this tick (no table per frame)
    local tick = (lane.tick or 0) + 1
    lane.tick = tick
    for _, e in ipairs(state.entries) do
        local f = lane.frames[e]
        if not f then
            f = Acquire(lane)
            lane.frames[e] = f
            e.dirty = true
        end
        if e.dirty then Dress(lane, e, f) end
        Place(lane, e, f)
        e.seen = tick
    end
    -- Give back the dead
    for e, f in pairs(lane.frames) do
        if e.seen ~= tick then
            lane.frames[e] = nil
            Release(lane, f)
        end
    end
end

local function OnUpdate()
    local now = GetTime()
    if volley then
        local shots = volley.shots
        while volley.next <= #shots and now - volley.start >= shots[volley.next].at do
            Dispatch(Copy(shots[volley.next].rec), now)
            volley.next = volley.next + 1
        end
        if volley.next > #shots then volley = nil end
    end
    for _, lane in ipairs(laneList) do
        StepLane(lane, now)
    end
end

function CommanderTracer_Clear()
    for _, lane in ipairs(laneList) do
        for i = #lane.state.entries, 1, -1 do lane.state.entries[i] = nil end
        for e, f in pairs(lane.frames) do
            lane.frames[e] = nil
            Release(lane, f)
        end
    end
    volley = nil
end

function CommanderTracer_Test()
    if not Enabled() then
        print("Commander Tracer is disabled.")
        return
    end
    volley = { start = GetTime(), shots = E.TestVolley(), next = 1 }
end

-- ---------------------------------------------------------------------------
-- Blizzard's text. The values this module replaces are kept in the DB so
-- they can be given back exactly, whether that is because a box was
-- unticked, the module was disabled, or the addon was removed and the
-- backup read by hand.
-- ---------------------------------------------------------------------------
local function TakeCVars(list, want, backup)
    for _, name in ipairs(list) do
        if want then
            if backup[name] == nil then
                local ok, value = pcall(C_CVar.GetCVar, name)
                if ok and value ~= nil then backup[name] = tostring(value) end
            end
            pcall(C_CVar.SetCVar, name, "0")
        elseif backup[name] ~= nil then
            pcall(C_CVar.SetCVar, name, backup[name])
            backup[name] = nil
        end
    end
end

local function ApplyCVars()
    local db = CommanderTracerDB
    if not (db and C_CVar) then return end
    if InCombatLockdown and InCombatLockdown() then
        cvarsPending = true
        return
    end
    cvarsPending = false
    if type(db.CVarBackup) ~= "table" then db.CVarBackup = {} end
    local on = Enabled()
    TakeCVars(DATA.CVARS_WORLD, on and G("HideBlizzardWorldText", true), db.CVarBackup)
    TakeCVars(DATA.CVARS_PLAYER, on and G("HideBlizzardPlayerText", true), db.CVarBackup)
end

-- ---------------------------------------------------------------------------
-- The client's events
-- ---------------------------------------------------------------------------
local function RefreshIdentity()
    ctx.player = UnitGUID("player")
    ctx.pet = UnitExists("pet") and UnitGUID("pet") or nil
    local _, class = UnitClass("player")
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    classColor = c and { c.r, c.g, c.b } or nil
end

local function OnCombatLog()
    if not Enabled() then return end
    local rec = E.Classify(ctx, CombatLogGetCurrentEventInfo())
    if rec then Dispatch(rec) end
end

-- The client's own combat-text feed, for the two things the log does not
-- carry: a reactive ability lighting up, and honor arriving.
-- C_CombatText.GetCurrentEventInfo() gives (data, arg3, arg4) on this
-- client; the event's own varargs are the fallback.
local function OnCombatText(messageType, ...)
    if not Enabled() then return end
    if messageType ~= "SPELL_ACTIVE" and messageType ~= "HONOR_GAINED" then return end
    local data
    if C_CombatText and C_CombatText.GetCurrentEventInfo then
        local ok, a, b = pcall(C_CombatText.GetCurrentEventInfo)
        if ok then
            data = a
            if data == messageType then data = b end
        end
    end
    if data == nil then data = (select("#", ...) > 0) and (...) or nil end
    if messageType == "SPELL_ACTIVE" then
        if type(data) == "string" and data ~= "" then Dispatch(E.ProcRecord(data)) end
    else
        local amount = tonumber(data)
        if amount and amount > 0 then Dispatch(E.HonorRecord(amount)) end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_PET")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("COMBAT_TEXT_UPDATE")
events:SetScript("OnEvent", function(_, event, arg1, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "COMBAT_TEXT_UPDATE" then
        OnCombatText(arg1, ...)
    elseif event == "PLAYER_LOGIN" then
        BuildLanes()
        RefreshIdentity()
        driver = driver or CreateFrame("Frame")
        driver:SetScript("OnUpdate", OnUpdate)
        ApplyAll()
        ApplyCVars()
    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshIdentity()
        ApplyCVars()
    elseif event == "UNIT_PET" then
        if arg1 == "player" then RefreshIdentity() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if Enabled() then Dispatch(E.CombatRecord(true)) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if Enabled() then Dispatch(E.CombatRecord(false)) end
        if cvarsPending then ApplyCVars() end
    end
end)

Commander.AddListener(COMMANDER_TRACER_EVENTS.UPDATE, function()
    ApplyAll()
    ApplyCVars()
end)

-- ---------------------------------------------------------------------------
-- The report
-- ---------------------------------------------------------------------------
function CommanderTracer_Report()
    print("Commander Tracer: " .. (Enabled() and "enabled" or "disabled"))
    for _, lane in ipairs(laneList) do
        print(string.format("  %-16s %s  %s  %d in flight", lane.spec.title,
            lane.enabled and "on " or "off", lane.cfg.Motion or "?", #lane.state.entries))
    end
    local db = CommanderTracerDB
    local held = 0
    for _ in pairs((db and db.CVarBackup) or {}) do held = held + 1 end
    print(string.format("  Blizzard text: world %s, player %s (%d CVar%s held for restore%s)",
        G("HideBlizzardWorldText", true) and "hidden" or "shown",
        G("HideBlizzardPlayerText", true) and "hidden" or "shown",
        held, held == 1 and "" or "s", cvarsPending and ", apply pending combat" or ""))
end

-- Read-only, for the harness and for other modules
function CommanderTracer_Lane(key)
    return lanes[key]
end

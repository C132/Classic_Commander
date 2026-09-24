-- Commander Kicks: an interrupt bar for arena and battlegrounds.
--
-- The oldest arena addon there is, rebuilt on this suite's rules. Every enemy
-- interrupt -- Kick, Pummel, Shield Bash, Counterspell, Earth Shock, Spell
-- Lock, Silencing Shot, Silence, Feral Charge, Arcane Torrent -- as an icon
-- with a clock, so "can I cast right now?" is answered by glancing rather
-- than by reading a cooldown tracker.
--
-- Three things make it worth having rather than being the old bar again:
--
--   PER ENEMY    the old bar had one Kick icon. A double-rogue team has two
--                Kicks, and "one of them is down" is not an answer. Icons are
--                grouped by enemy -- the arena seats, in seat order, with a
--                seat badge on each -- so whose kick is down is on the icon.
--   FROM GATES   an arena seat's whole book is on the bar before anybody
--                has pressed anything, lit while ready. The bar has a fixed
--                shape you read by position, and a ready kick is the
--                dangerous state, so it is the visible one.
--   THE LOCKOUT  the clock is red for the first seconds of each cooldown --
--                the length of the lockout that kick just inflicted -- and
--                white after. For those seconds the kick is still doing its
--                work; after them the only thing to fear is the cooldown
--                ending, which the icon flashes to say.
--
-- The rules live in CommanderKicksEngine.lua, which touches no WoW API and is
-- tested under plain luajit. This file is the plumbing: what the client says,
-- when, and how it gets drawn.

local DATA = CommanderKicks_Data
local E = CommanderKicks_Engine

-- One accessor, so a nil DB (the moment before ADDON_LOADED) can never take
-- the bar down.
local function DB(key, default)
    local db = CommanderKicksDB
    if not db then return default end
    local value = db[key]
    if value == nil then return default end
    return value
end

local function Enabled()
    return CommanderKicksDB and CommanderKicksDB.Enable
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARENA_UNITS = { "arena1", "arena2", "arena3", "arena4", "arena5" }
local DRAW_THROTTLE = 0.1     -- 10Hz. A kick clock a tenth late has never
                              -- cost anybody a cast.
local PRUNE_EVERY = 5
local PRUNE_GRACE = 15        -- seconds past their last cooldown before a
                              -- stranger is forgotten

-- ---------------------------------------------------------------------------
-- Live state
-- ---------------------------------------------------------------------------
local bar = E.NewBar()
local identity = {}           -- guid -> { name, class, race, seat, pet }
local petOwner = {}           -- pet guid -> owner guid, from the arena tokens
local played = {}             -- owner\0spell -> the `at` whose ready we sounded
local playerGUID
local testUntil = 0

-- ---------------------------------------------------------------------------
-- Who people are.
--
-- A unit token is the best source (class, race and seat, from the client's
-- own mouth); the combat log is the worst (a name and a GUID). Between them
-- sits GetPlayerInfoByGUID, which answers for any player GUID the client has
-- seen, and is what lets a battleground stranger's Counterspell be drawn with
-- a mage-coloured badge rather than a grey one.
-- ---------------------------------------------------------------------------
local function Identify(guid, name)
    if not guid then return nil end
    local known = identity[guid]
    if known and known.class then
        known.name = known.name or name
        return known
    end
    known = known or {}
    identity[guid] = known
    known.name = known.name or name
    if GetPlayerInfoByGUID then
        local ok, _, class, _, race, _, pname = pcall(GetPlayerInfoByGUID, guid)
        if ok then
            known.class = class or known.class
            known.race = race or known.race
            known.name = known.name or pname
        end
    end
    return known
end

-- A hostile PLAYER behind a unit token, remembered with everything the token
-- knows. Returns the guid and the record, or nothing.
local function UnitIdentity(unit, seat)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    if not UnitCanAttack("player", unit) then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local known = identity[guid] or {}
    identity[guid] = known
    known.name = UnitName(unit) or known.name
    local _, class = UnitClass(unit)
    known.class = class or known.class
    if UnitRace then
        local _, race = UnitRace(unit)
        known.race = race or known.race
    end
    if seat then known.seat = seat end
    return guid, known
end

-- The arena seats' pets. The felhunter's Spell Lock arrives from the pet's
-- GUID, and the only place the client ties a pet to its arena owner is the
-- arenapetN token, so the map is rebuilt whenever the seats change.
local function RefreshArenaPets()
    for i, unit in ipairs(ARENA_UNITS) do
        local ownerGUID = UnitGUID(unit)
        local petGUID = ownerGUID and UnitGUID("arenapet" .. i)
        if petGUID then petOwner[petGUID] = ownerGUID end
    end
end

-- ---------------------------------------------------------------------------
-- Combat log.
--
-- One subevent. SPELL_CAST_SUCCESS is the right signal rather than _START: an
-- interrupt is instant, and success is the moment the cooldown was spent.
-- Hostile players and hostile pets only -- NPCs kick too, and an interrupt
-- bar is a PvP instrument.
-- ---------------------------------------------------------------------------
local function OnCombatLog()
    local _, subevent, _, sourceGUID, sourceName, sourceFlags, _, _, _, _, _,
          spellId, spellName = CombatLogGetCurrentEventInfo()
    if subevent ~= "SPELL_CAST_SUCCESS" then return end
    if not (sourceGUID and sourceFlags) then return end
    if bit.band(sourceFlags, COMBATLOG_OBJECT_REACTION_HOSTILE) == 0 then return end
    local isPlayer = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
    local isPet = bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) > 0
    if not (isPlayer or isPet) then return end

    local entry = E.Entry(spellId, spellName)
    if not entry then return end

    -- A pet's cooldown is its owner's where an owner can be named; an
    -- unowned pet is its own owner, named after itself and classed after the
    -- spell, which is the truth the log can support.
    local owner = sourceGUID
    if isPet then
        if not petOwner[sourceGUID] then RefreshArenaPets() end
        owner = petOwner[sourceGUID] or sourceGUID
    end

    bar:Used(owner, entry, GetTime())

    if owner == sourceGUID then
        if isPlayer then
            Identify(owner, sourceName)
        else
            local known = identity[owner] or {}
            identity[owner] = known
            known.name = known.name or sourceName
            known.class = known.class or entry.class
            known.pet = true
        end
    end
    bar:Describe(owner, identity[owner])
end

-- ---------------------------------------------------------------------------
-- The frames.
--
-- One root, a pool of cells, a pool of labels. Nothing is ever destroyed -- a
-- battleground would otherwise churn frames every time you changed target --
-- so the pools only grow to one session's high-water mark and are hidden
-- back down from there.
-- ---------------------------------------------------------------------------
local root = CreateFrame("Frame", "CommanderKicksFrame", UIParent)
root:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
root:SetSize(200, 30)
root:SetFrameStrata("MEDIUM")
root:Hide()

local cells, labels = {}, {}

local function NewCell(parent)
    local cell = CreateFrame("Frame", nil, parent)

    -- The rim carries the state: green up, grey down. A texture behind an
    -- inset icon rather than a border object, because a one-pixel inset
    -- reads as a rim at every icon size the slider allows.
    cell.rim = cell:CreateTexture(nil, "BACKGROUND")
    cell.rim:SetAllPoints()
    cell.rim:SetTexture(WHITE)

    -- The back-up flash: a halo outside the rim for the moment a cooldown
    -- ends, because that is the moment the icon changes from "safe" to
    -- "threat" and the change itself is the news.
    cell.glow = cell:CreateTexture(nil, "BACKGROUND", nil, -1)
    cell.glow:SetPoint("TOPLEFT", cell, "TOPLEFT", -3, 3)
    cell.glow:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", 3, -3)
    cell.glow:SetTexture(WHITE)
    cell.glow:Hide()

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    cell.icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    cell.cd = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.cd:SetAllPoints(cell.icon)
    cell.cd:SetHideCountdownNumbers(true)
    if cell.cd.SetDrawEdge then cell.cd:SetDrawEdge(false) end
    cell.cd:SetFrameLevel(cell:GetFrameLevel() + 1)

    -- Text sits ABOVE the cooldown frame, or the sweep dims it
    cell.text = CreateFrame("Frame", nil, cell)
    cell.text:SetAllPoints()
    cell.text:SetFrameLevel(cell:GetFrameLevel() + 2)

    cell.timer = cell.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.timer:SetPoint("CENTER", cell, "CENTER", 0, 0)

    cell.badge = cell.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.badge:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)

    return cell
end

local function AcquireCell(index)
    local cell = cells[index]
    if cell then return cell end
    cell = NewCell(root)
    cells[index] = cell
    return cell
end

local function AcquireLabel(index)
    local label = labels[index]
    if label then return label end
    label = root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    labels[index] = label
    return label
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------
local function IconFor(entry)
    local id = entry.id
    if id and GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, id)
        if ok and texture then return texture end
    end
    if id and GetSpellInfo then
        local ok, _, _, texture = pcall(GetSpellInfo, id)
        if ok and texture then return texture end
    end
    return DATA.FALLBACK_ICON
end

local function ClassColor(class)
    local colors = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if colors then return colors.r, colors.g, colors.b end
    return 0.9, 0.9, 0.9
end

-- The first character of a name, whole. strsub counts bytes and a name can
-- open with a multi-byte one; the lead byte says how long it is.
local function Initial(name)
    if not name or name == "" then return "" end
    local byte = strbyte(name, 1)
    local len = 1
    if byte >= 240 then len = 4 elseif byte >= 224 then len = 3 elseif byte >= 192 then len = 2 end
    return strsub(name, 1, len)
end

-- Cut to a length, without cutting a character in half.
local function Truncate(name)
    if not name then return "" end
    local maxChars = DB("NameMaxChars", 8)
    if strlen(name) <= maxChars then return name end
    local cut = maxChars
    while cut > 0 do
        local byte = strbyte(name, cut + 1)
        if not byte or byte < 128 or byte >= 192 then break end
        cut = cut - 1
    end
    return strsub(name, 1, cut)
end

local function ReadySound()
    if not DB("ReadySound", false) then return end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- One cell. `row` is an engine row: owner, entry, and where the cooldown is.
local function PaintCell(cell, row, now)
    local texture = IconFor(row.entry)
    if cell._tex ~= texture then
        cell._tex = texture
        cell.icon:SetTexture(texture)
    end

    if DB("ShowSeat", true) then
        local info = row.info
        local seat = info and info.seat
        cell.badge:SetText(seat and tostring(seat) or Initial(info and info.name))
        cell.badge:SetTextColor(ClassColor(info and info.class))
    else
        cell.badge:SetText("")
    end

    local flash = DB("ReadyFlash", 1.5)

    if row.ready then
        cell.icon:SetDesaturated(false)
        cell.icon:SetAlpha(DB("ReadyAlpha", 1))
        local tint = DATA.TINT.READY
        cell.rim:SetVertexColor(tint[1], tint[2], tint[3], 1)
        cell.cd:Hide()
        cell._cdAt = nil
        cell.timer:SetText("")

        -- The back-up flash fades over its length, so a bar full of ready
        -- kicks is not a bar full of halos: only the one that JUST came
        -- back is lit, and only for a moment.
        if row.justReady and flash > 0 and row.at then
            local elapsed = now - (row.at + row.cd)
            local strength = 1 - math.max(0, math.min(1, elapsed / flash))
            local glow = DATA.TINT.FLASH
            cell.glow:SetVertexColor(glow[1], glow[2], glow[3], 0.9 * strength)
            cell.glow:Show()
            -- Once per press: the sound is keyed on the stamp that just ran
            -- out, so a cooldown that ended while the bar was hidden says
            -- nothing when it comes back.
            local key = row.owner .. "\0" .. row.entry.name
            if played[key] ~= row.at then
                played[key] = row.at
                if now < testUntil or elapsed < DRAW_THROTTLE * 3 then ReadySound() end
            end
        else
            cell.glow:Hide()
        end
        return
    end

    cell.glow:Hide()
    cell.icon:SetDesaturated(DB("DesaturateDown", true) and true or false)
    cell.icon:SetAlpha(1)
    local tint = DATA.TINT.DOWN
    cell.rim:SetVertexColor(tint[1], tint[2], tint[3], 1)

    if DB("ShowSwipe", true) then
        cell.cd:Show()
        -- Only when it actually changes. SetCooldown restarts the sweep, so
        -- calling it every draw is a sweep that never moves.
        if cell._cdAt ~= row.at then
            cell._cdAt = row.at
            cell.cd:SetCooldown(row.at, row.cd)
        end
    else
        cell.cd:Hide()
        cell._cdAt = nil
    end

    if DB("ShowTimer", true) then
        cell.timer:SetText(E.FormatTime(row.remaining))
        if row.locked and DB("LockoutTint", true) then
            local lock = DATA.TINT.LOCK
            cell.timer:SetTextColor(lock[1], lock[2], lock[3])
        else
            cell.timer:SetTextColor(1, 1, 1)
        end
    else
        cell.timer:SetText("")
    end
end

-- ---------------------------------------------------------------------------
-- Who gets a group.
--
-- Fixed order, deduplicated by GUID: the arena seats in seat order, then the
-- target, then the focus. Fixed rather than sorted so a group stays where you
-- last looked for it -- an arena opponent who happens to be your target
-- appears once, in the seat's place, rather than jumping as you swap.
-- ---------------------------------------------------------------------------
local roster = {}
local rowsScratch = {}

local function AddMember(guid, info)
    if not guid or not info then return end
    for _, member in ipairs(roster) do
        if member.key == guid then return end
    end
    info.key = guid
    roster[#roster + 1] = info
end

local function BuildRoster()
    for i = #roster, 1, -1 do roster[i] = nil end

    if GetTime() < testUntil then
        for i = 1, 3 do
            local guid = "Player-TEST-" .. i
            AddMember(guid, identity[guid])
        end
        return
    end

    if DB("ShowArena", true) then
        for i, unit in ipairs(ARENA_UNITS) do
            local guid, info = UnitIdentity(unit, i)
            if guid then AddMember(guid, info) end
        end
    end
    if DB("ShowTarget", true) then
        local guid, info = UnitIdentity("target")
        if guid then AddMember(guid, info) end
    end
    if DB("ShowFocus", true) then
        local guid, info = UnitIdentity("focus")
        if guid then AddMember(guid, info) end
    end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- Whether this zone is one we draw in, CACHED: recomputed on the events that
-- can change it rather than asked in the combat-log handler.
local zoneOK = false

local function RefreshZone()
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then
        zoneOK = DB("ShowInArena", true) and true or false
    elseif instanceType == "pvp" then
        zoneOK = DB("ShowInBattleground", true) and true or false
    else
        zoneOK = DB("ShowInWorld", false) and true or false
    end
    return zoneOK
end

local function Draw()
    if not Enabled() then
        root:Hide()
        return
    end

    local now = GetTime()
    local testing = now < testUntil
    -- Unlocked for dragging, the frame has to stay on screen whatever the
    -- zone says: a hidden frame cannot be dragged (the chrome's contract).
    local unlocked = Commander.UI.HudUnlocked
        and Commander.UI.HudUnlocked(CommanderKicksDB, "Hud") or false
    if not testing and not unlocked then
        if not zoneOK then root:Hide() return end
        if DB("CombatOnly", false) and not (InCombatLockdown and InCombatLockdown()) then
            root:Hide()
            return
        end
    end

    BuildRoster()
    local rows = bar:Rows(now, roster, DB("ShowReady", true), DB("ReadyFlash", 1.5), rowsScratch)
    local size = DB("IconSize", 30)

    if #rows == 0 then
        for _, cell in ipairs(cells) do cell:Hide() end
        for _, label in ipairs(labels) do label:Hide() end
        if unlocked then
            -- An empty placeholder the width of a typical team, so there is
            -- something to take hold of
            root:SetSize(size * 4, size)
            root:Show()
        else
            root:Hide()
        end
        return
    end

    local gap = DB("IconSpacing", 3)
    local groupGap = DB("GroupSpacing", 10)
    local vertical = DB("Orientation", "HORIZONTAL") == "VERTICAL"
    local showName = DB("ShowName", false)
    local nameSize = DB("NameSize", 10)
    local labelHeight = showName and (nameSize + 3) or 0
    local timerSize = DB("TimerSize", 12)

    -- One pass along the main axis. `pos` is where the next icon goes; a
    -- change of owner opens the wider gap and, when names are on, a label.
    -- Horizontal labels sit above their group and cost no width; vertical
    -- ones sit in the column and cost their height.
    local pos, lastOwner, groupCount = 0, nil, 0
    for index, row in ipairs(rows) do
        if row.owner ~= lastOwner then
            if lastOwner ~= nil then pos = pos + groupGap end
            lastOwner = row.owner
            groupCount = groupCount + 1
            if showName then
                local label = AcquireLabel(groupCount)
                label:SetText(Truncate(row.info and row.info.name or "?"))
                label:SetTextColor(ClassColor(row.info and row.info.class))
                if label._fontSize ~= nameSize then
                    label._fontSize = nameSize
                    local font, _, flags = label:GetFont()
                    if font then label:SetFont(font, nameSize, flags) end
                end
                label:ClearAllPoints()
                if vertical then
                    label:SetPoint("TOPLEFT", root, "TOPLEFT", 1, -pos)
                    pos = pos + labelHeight
                else
                    label:SetPoint("BOTTOMLEFT", root, "TOPLEFT", pos + 1, 1)
                end
                label:Show()
            end
        end

        local cell = AcquireCell(index)
        if cell._size ~= size or cell._pos ~= pos or cell._vertical ~= vertical then
            cell._size, cell._pos, cell._vertical = size, pos, vertical
            cell:SetSize(size, size)
            cell:ClearAllPoints()
            if vertical then
                cell:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -pos)
            else
                cell:SetPoint("TOPLEFT", root, "TOPLEFT", pos, 0)
            end
        end
        -- OUTLINE unconditionally: this text sits on a spell icon, and the
        -- inherited flags are empty, which is unreadable over half the art.
        if cell._fontSize ~= timerSize then
            cell._fontSize = timerSize
            local font = cell.timer:GetFont()
            if font then
                cell.timer:SetFont(font, timerSize, "OUTLINE")
                cell.badge:SetFont(font, math.max(8, timerSize - 3), "OUTLINE")
            end
        end
        PaintCell(cell, row, now)
        cell:Show()
        pos = pos + size + gap
    end
    for index = #rows + 1, #cells do cells[index]:Hide() end
    for index = groupCount + 1, #labels do labels[index]:Hide() end

    local length = math.max(pos - gap, 1)
    if vertical then
        root:SetSize(size, length)
    else
        root:SetSize(length, size)
    end
    root:Show()
end

-- ---------------------------------------------------------------------------
-- The test bar.
--
-- Fabricated state run through the REAL painters, so what you place and size
-- is what you will see in a game. Three seats, staged to show every state at
-- once: a Counterspell inside its lockout, a Kick about to come back, an
-- Earth Shock just spent, an Arcane Torrent deep in its two minutes, and a
-- Spell Lock ready.
-- ---------------------------------------------------------------------------
local TEST = {
    { guid = "Player-TEST-1", name = "Frostpath", class = "MAGE", race = "Human" },
    { guid = "Player-TEST-2", name = "Shivspine", class = "ROGUE", race = "BloodElf" },
    { guid = "Player-TEST-3", name = "Zaldrek", class = "WARLOCK", race = "Undead" },
}

function CommanderKicks_Test()
    local now = GetTime()
    testUntil = now + 20

    for seat, fake in ipairs(TEST) do
        bar:Clear(fake.guid)
        identity[fake.guid] = { name = fake.name, class = fake.class, race = fake.race, seat = seat }
    end

    local cs = E.Entry(2139, "Counterspell")
    local kick = E.Entry(nil, "Kick")
    local torrent = E.Entry(nil, "Arcane Torrent")
    bar:Used(TEST[1].guid, cs, now - 3)              -- inside its 8s lockout
    bar:Used(TEST[2].guid, kick, now - 9)            -- back in a second
    bar:Used(TEST[2].guid, torrent, now - 40)        -- 1:20 to go
    -- The warlock's Spell Lock is left ready on purpose.

    Draw()
    print("|cff66ccffCommander Kicks|r: test bar up for 20 seconds.")
end

-- The answer to "what does this watch".
function CommanderKicks_Report()
    print("|cff66ccffCommander Kicks|r: the interrupt book (" .. DATA.BUILD .. ")")
    for _, entry in ipairs(E.Book()) do
        local who = entry.class or entry.race or "?"
        local extra = ""
        if entry.also then extra = "  (also " .. table.concat(entry.also, ", ") .. ")" end
        if entry.pet then extra = extra .. "  (the pet's)" end
        print(string.format("  %-16s %-8s %3ds cooldown, %ds lockout%s",
            entry.name, who, entry.cd, entry.lock or 0, extra))
    end
    print(string.format("  tracking %d %s right now",
        bar:Count(), bar:Count() == 1 and "person" or "people"))
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
local function Apply()
    if not Enabled() then
        root:Hide()
        return
    end
    Commander.UI.ApplyHudChrome(root, CommanderKicksDB, "Hud", {
        title = "Kicks",
        defaultPoint = { point = "CENTER", x = 0, y = -220 },
    })
    RefreshZone()
    Draw()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_FOCUS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UNIT_PET")
pcall(events.RegisterEvent, events, "ARENA_OPPONENT_UPDATE")

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Tracking is gated on the ZONE, not on the display: "only in
        -- combat" hides the bar and keeps the clocks running underneath.
        if Enabled() and zoneOK then OnCombatLog() end
        return
    end

    if event == "PLAYER_LOGIN" then
        playerGUID = UnitGUID("player")
        Apply()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- A new instance is a new set of people. Nothing learned in the last
        -- one is true here.
        playerGUID = playerGUID or UnitGUID("player")
        bar:Wipe()
        wipe(identity)
        wipe(petOwner)
        wipe(played)
        RefreshZone()
        RefreshArenaPets()
        Draw()
    elseif event == "ARENA_OPPONENT_UPDATE" then
        RefreshArenaPets()
        Draw()
    elseif event == "UNIT_PET" then
        if type(arg1) == "string" and strsub(arg1, 1, 5) == "arena" then RefreshArenaPets() end
    else
        Draw()
    end
end)

if Commander and Commander.AddListener then
    Commander.AddListener(COMMANDER_KICKS_EVENTS.UPDATE, Apply)
end

-- ---------------------------------------------------------------------------
-- A read-only view for other modules: seconds until this GUID's named
-- interrupt is back (nil = ready), and whether it has ever been seen. Arena
-- Frames or Plates can put "their kick is down" on the seat or the plate.
-- ---------------------------------------------------------------------------
function CommanderKicks_Remaining(guid, spellName, now)
    if not Enabled() or not guid then return nil, false end
    local entry = E.Entry(nil, spellName)
    if not entry then return nil, false end
    return bar:Remaining(guid, entry.name, now or GetTime())
end

local ticker = CreateFrame("Frame")
ticker.since = 0
ticker.sincePrune = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.since = self.since + elapsed
    if self.since < DRAW_THROTTLE then return end
    self.since = 0

    if not Enabled() then return end

    -- Forgetting people. Not while the test bar is up: its warlock is
    -- deliberately clean, and a pruner cannot tell "fabricated and quiet"
    -- from "gone".
    self.sincePrune = self.sincePrune + DRAW_THROTTLE
    if self.sincePrune >= PRUNE_EVERY and GetTime() >= testUntil then
        self.sincePrune = 0
        bar:Prune(GetTime(), PRUNE_GRACE)
        for guid in pairs(identity) do
            if not bar:Knows(guid) and not guid:find("^Player%-TEST") then
                -- Seats and the target keep their record through the roster;
                -- only log-only strangers are dropped with their cooldowns.
                local keep = false
                for _, member in ipairs(roster) do
                    if member.key == guid then keep = true break end
                end
                if not keep then identity[guid] = nil end
            end
        end
    end

    if self.wasTesting and GetTime() >= testUntil then
        self.wasTesting = false
        for _, fake in ipairs(TEST) do
            bar:Clear(fake.guid)
            identity[fake.guid] = nil
        end
    elseif GetTime() < testUntil then
        self.wasTesting = true
    end

    Draw()
end)

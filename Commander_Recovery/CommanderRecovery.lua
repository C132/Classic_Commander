-- Commander Recovery: casualty response. On death, capture the map position
-- where the unit fell and log a short report; when the spirit is released,
-- issue a Commander Orders move order pointing back at the corpse (the arrow
-- tracks the death spot — close enough to the corpse for a run-back); when
-- the player lives again, clear our order and confirm recovery.
--
-- Event flow on 2.5.x: PLAYER_DEAD (died) -> PLAYER_ALIVE (released, now a
-- ghost — or resurrected in place without releasing) -> PLAYER_UNGHOST
-- (back to life after being a ghost). UnitIsGhost distinguishes the two
-- PLAYER_ALIVE cases.
--
-- In a battleground the whole corpse-run apparatus is beside the point, so
-- Recovery also presses release for you there -- see the auto-release block
-- below.

local sessionDeaths = 0
local lastDeath = nil        -- { mapID, x, y, zone, when }
-- The corpse order we issued lives in CommanderRecoveryDB.IssuedOrder (a
-- SavedVariable, so it survives /reload while dead) and is only ever
-- cleared when the active Orders waypoint still matches it — never a
-- waypoint the player set themselves during the ghost run.

local function IsOn()
    return CommanderRecoveryDB and CommanderRecoveryDB.EnableRecovery
end

-- ---------------------------------------------------------------------------
-- Battleground auto-release
--
-- Nothing in a battleground is served by staring at the release popup: no one
-- walks back to a corpse there, the graveyard's resurrection cycle only starts
-- counting once the spirit is out, and the fight is being decided while you
-- read a dialog. So press it automatically -- but only there, and only when
-- releasing really is the best move: a soulstone, a reincarnation or a
-- resurrection already being cast all beat a graveyard trip, and the popup is
-- left alone whenever one of them is on offer.
--
-- Client note: `HasSoulstone` -- the function every Classic-era auto-release
-- recipe checks -- DOES NOT EXIST on this client. Self-resurrects are
-- enumerated by `C_DeathInfo.GetSelfResurrectOptions()` instead (verified in
-- the 2.5.6.69546 binary alongside `UseSelfResurrectOption`), which covers
-- soulstone, reincarnation and ankh through one list.
-- ---------------------------------------------------------------------------
local AUTO_RELEASE_RETRY = 1.0     -- seconds between attempts
local AUTO_RELEASE_WINDOW = 15     -- stop trying this long after the death
local AUTO_RELEASE_ZONE_IN = 2     -- extra settle time when we arrive dead

-- Bumped on every death, release and resurrection, so a scheduled attempt
-- that events have overtaken quietly does nothing
local releaseGeneration = 0
local announcedGeneration = nil
local autoReleasePressed = false

local function SelfResurrectReady()
    local options = C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions
        and C_DeathInfo.GetSelfResurrectOptions()
    if not options then return false end
    for _, option in ipairs(options) do
        -- An option the client says we cannot use yet is no reason to wait
        if type(option) ~= "table" or option.canUse ~= false then return true end
    end
    return false
end

-- Why auto-release is holding its hand, or nil when it would press release.
-- The "are we dead" checks are deliberately NOT in here: the tester asks this
-- question while the player is alive and well.
local function AutoReleaseHold()
    if not IsOn() then return "the module is disabled" end
    if not CommanderRecoveryDB.AutoRelease then return "auto-release is off" end
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then
        if not CommanderRecoveryDB.AutoReleaseArena then return "arenas are excluded" end
    elseif instanceType ~= "pvp" then
        return "this is not a battleground"
    end
    -- Once a side has won, the losers are resurrected on the way out anyway
    if GetBattlefieldWinner and GetBattlefieldWinner() then return "the match is decided" end
    if SelfResurrectReady() then return "a self-resurrect is ready" end
    if ResurrectGetOfferer and ResurrectGetOfferer() then return "a resurrection is incoming" end
    return nil
end

local function AttemptAutoRelease(generation, deadline)
    if generation ~= releaseGeneration then return end
    -- A hunter's Feign Death fires PLAYER_DEAD without killing anybody
    if not UnitIsDead("player") or UnitIsGhost("player") then return end
    if AutoReleaseHold() then return end
    if CommanderRecoveryDB.DeathReport and announcedGeneration ~= generation then
        announcedGeneration = generation
        print("Commander Recovery: releasing spirit -- redeploying from the graveyard")
    end
    autoReleasePressed = true
    RepopMe()
    -- Releasing is a server round trip, and the first press right after death
    -- can land too early to take. Keep pressing until PLAYER_ALIVE arrives
    -- (which bumps the generation) or the window closes.
    if GetTime() < deadline then
        C_Timer.After(AUTO_RELEASE_RETRY, function()
            AttemptAutoRelease(generation, deadline)
        end)
    end
end

-- extraDelay covers arriving in the battleground already dead, where the
-- instance state needs a beat to settle before any of this can be judged
local function StartAutoRelease(extraDelay)
    if AutoReleaseHold() then return end
    if not UnitIsDead("player") or UnitIsGhost("player") then return end
    local generation = releaseGeneration
    local delay = (CommanderRecoveryDB.AutoReleaseDelay or 0) + (extraDelay or 0)
    local deadline = GetTime() + delay + AUTO_RELEASE_WINDOW
    if delay <= 0 then
        AttemptAutoRelease(generation, deadline)
    else
        C_Timer.After(delay, function() AttemptAutoRelease(generation, deadline) end)
    end
end

local function CaptureDeathPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        -- Still return a sentinel: lastDeath doubles as the "currently
        -- tracking a death" flag, so nil would disable the re-fire guard
        -- and the recovery confirmation
        return { zone = GetZoneText() or "unknown territory" }
    end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        return { mapID = mapID, zone = GetZoneText() or "unknown territory" }
    end
    return {
        mapID = mapID, x = pos.x, y = pos.y,
        zone = GetZoneText() or "unknown territory",
        when = GetTime(),
    }
end

function CommanderRecovery_Report()
    if sessionDeaths == 0 then
        print("Commander Recovery: no casualties this session. Flawless campaign.")
        return
    end
    if lastDeath and lastDeath.x then
        print(string.format(
            "Commander Recovery: %d casualt%s this session — last unit lost in %s (%.0f, %.0f)",
            sessionDeaths, sessionDeaths == 1 and "y" or "ies",
            lastDeath.zone, lastDeath.x * 100, lastDeath.y * 100))
    else
        print(string.format(
            "Commander Recovery: %d casualt%s this session — last unit lost in %s",
            sessionDeaths, sessionDeaths == 1 and "y" or "ies",
            lastDeath and lastDeath.zone or "unknown territory"))
    end
end

-- Standard suite tester: preview the casualty flow — the report line for
-- a pretend death at your current position and the recovery sound —
-- without touching the session log or issuing any order
function CommanderRecovery_Test()
    if not IsOn() then
        print("Commander Recovery: module is disabled (enable it in settings or /crec)")
        return
    end
    local here = CaptureDeathPosition()
    if here.x then
        print(string.format(
            "Commander Recovery: TEST — unit lost in %s (%.0f, %.0f); releasing would issue a corpse run order back to this spot",
            here.zone, here.x * 100, here.y * 100))
    else
        print(string.format("Commander Recovery: TEST — unit lost in %s", here.zone))
    end
    local hold = AutoReleaseHold()
    if hold then
        print("Commander Recovery: TEST -- auto-release is holding here: " .. hold)
    else
        local delay = CommanderRecoveryDB.AutoReleaseDelay or 0
        print(string.format(
            "Commander Recovery: TEST -- auto-release armed, releasing %s after you fall",
            delay > 0 and string.format("%.1fs", delay) or "immediately"))
    end
    if CommanderRecoveryDB.RecoverySound then
        PlaySound(SOUNDKIT.READY_CHECK, "Master")
    end
end

local session   -- reload-resilient casualty count

local function OnDeath()
    if not IsOn() then return end
    -- PLAYER_DEAD can re-fire in odd resurrection flows; only count a death
    -- when we are not already tracking one
    if lastDeath then return end
    sessionDeaths = sessionDeaths + 1
    if session then session.deaths = sessionDeaths end
    lastDeath = CaptureDeathPosition()
    if CommanderRecoveryDB.DeathReport then
        CommanderRecovery_Report()
    end
end

local function OnReleased()
    if not IsOn() then return end
    if not (CommanderRecoveryDB.CorpseOrder and CommanderOrders_IssueOrder) then return end
    if not (lastDeath and lastDeath.x) then return end
    -- With Orders disabled the order would be silently accepted but no
    -- arrow would ever show — skip instead of pretending to help
    if CommanderOrdersDB and CommanderOrdersDB.EnableOrders == false then return end
    if CommanderOrders_IssueOrder(lastDeath.mapID, lastDeath.x, lastDeath.y) then
        CommanderRecoveryDB.IssuedOrder = { mapID = lastDeath.mapID, x = lastDeath.x, y = lastDeath.y }
        print("Commander Recovery: corpse run order issued — follow the arrow, soldier")
    end
end

-- Clear the corpse order if and only if it is still the active waypoint:
-- an order the player issued themselves mid-ghost-run (map click, rally)
-- or one that already self-cleared on arrival is left alone
local function ClearOwnOrder()
    local issued = CommanderRecoveryDB.IssuedOrder
    CommanderRecoveryDB.IssuedOrder = nil
    if not (issued and CommanderOrders_ClearOrder) then return end
    local waypoint = CommanderOrdersDB and CommanderOrdersDB.Waypoint
    if waypoint and waypoint.mapID == issued.mapID
        and waypoint.x == issued.x and waypoint.y == issued.y then
        CommanderOrders_ClearOrder(false)
    end
end

local function OnRecovered()
    -- Even with the module disabled mid-run, an order we issued is ours
    -- to clean up
    ClearOwnOrder()
    if not IsOn() then
        lastDeath = nil
        return
    end
    if lastDeath then
        print("Commander Recovery: unit recovered and back in the field")
        if CommanderRecoveryDB.RecoverySound then
            PlaySound(SOUNDKIT.READY_CHECK, "Master")
        end
    end
    lastDeath = nil
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("PLAYER_ALIVE")
events:RegisterEvent("PLAYER_UNGHOST")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        session = Commander.RestoreSession(CommanderRecoveryDB, { deaths = 0 })
        sessionDeaths = session.deaths
        return
    end
    -- Every one of these ends whatever auto-release attempt was in flight
    releaseGeneration = releaseGeneration + 1
    if event == "PLAYER_DEAD" then
        autoReleasePressed = false
        OnDeath()
        StartAutoRelease()
    elseif event == "PLAYER_ALIVE" then
        if UnitIsGhost("player") then
            -- The release popup does not always go with the corpse. Take it
            -- down only now that the release has demonstrably landed: hiding
            -- it on a press the server never accepted would leave the player
            -- dead with no button to press themselves.
            if autoReleasePressed and StaticPopup_Hide then
                StaticPopup_Hide("DEATH")
            end
            autoReleasePressed = false
            OnReleased()
        else
            -- Resurrected in place (soulstone, priest rez, battle rez)
            OnRecovered()
        end
    elseif event == "PLAYER_UNGHOST" then
        OnRecovered()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ported into the battleground on a corpse, or reloaded while dead
        -- in one: PLAYER_DEAD is long gone and will not fire again
        StartAutoRelease(AUTO_RELEASE_ZONE_IN)
    end
end)

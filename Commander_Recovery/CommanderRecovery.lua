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

local sessionDeaths = 0
local lastDeath = nil        -- { mapID, x, y, zone, when }
-- The corpse order we issued lives in CommanderRecoveryDB.IssuedOrder (a
-- SavedVariable, so it survives /reload while dead) and is only ever
-- cleared when the active Orders waypoint still matches it — never a
-- waypoint the player set themselves during the ghost run.

local function IsOn()
    return CommanderRecoveryDB and CommanderRecoveryDB.EnableRecovery
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
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        session = Commander.RestoreSession(CommanderRecoveryDB, { deaths = 0 })
        sessionDeaths = session.deaths
        return
    end
    if event == "PLAYER_DEAD" then
        OnDeath()
    elseif event == "PLAYER_ALIVE" then
        if UnitIsGhost("player") then
            OnReleased()
        else
            -- Resurrected in place (soulstone, priest rez, battle rez)
            OnRecovered()
        end
    elseif event == "PLAYER_UNGHOST" then
        OnRecovered()
    end
end)

-- Commander Recovery: casualty response. On death, capture the map position
-- where the unit fell and log a short report; when the spirit is released,
-- say so if the Commander Orders arrow has the corpse; when the player lives
-- again, confirm recovery.
--
-- Event flow on 2.5.x: PLAYER_DEAD (died) -> PLAYER_ALIVE (released, now a
-- ghost — or resurrected in place without releasing) -> PLAYER_UNGHOST
-- (back to life after being a ghost). UnitIsGhost distinguishes the two
-- PLAYER_ALIVE cases.
--
-- The corpse arrow is Commander Orders' own since Orders 3.0 (2.3.0 here).
-- Recovery used to issue an ordinary move order at the death spot and clear
-- it again on resurrection, and every part of that was a workaround:
--   * Orders had ONE account-wide slot, so the corpse order wiped out the
--     player's own waypoint and the clean-up left them with nothing.
--   * The clean-up matched the slot by float equality against an
--     account-wide IssuedOrder, so a second character could inherit (and
--     then delete) the first one's corpse run.
--   * The death spot stood in for the corpse, was a file local that a
--     /reload while dead lost, and an instance death gave no arrow at all.
-- Orders now finds the real corpse (C_DeathInfo.GetCorpseMapPosition, asked
-- on the map you are on and each parent), remembers the death per character
-- through a /reload, points a dungeon death at the entrance, leaves
-- battlegrounds and arenas alone, and gives the arrow back to whatever you
-- were following once you live. So Recovery issues nothing: its old
-- "Corpse Run Order" option is now Orders' CorpseArrow setting, shown on this
-- page through CommanderOrders.CorpseArrow / SetCorpseArrow (the DB file
-- migrates a player's "off" across), and the release line below only
-- speaks when Orders really has the corpse.
--
-- In a battleground the whole corpse-run apparatus is beside the point, so
-- Recovery also presses release for you there -- see the auto-release block
-- below.
--
-- 2.4.0 (Commander Orders 3.1, "Go to" everywhere): the death line's
-- coordinates are Orders' own (CommanderOrders.FormatCoords, at the player's
-- Coordinate Decimals) and end in Orders' [Go] chat link to the spot, titled
-- "Where you fell": a click puts a waypoint there (Shift shares it, Ctrl
-- copies its /way line, Right opens Orders' menu -- the one gesture rule
-- every Commander module follows), which is what a player wants after a
-- /reload or once the corpse arrow is gone. Without Orders 3.1 the numbers
-- are printed alone at one decimal, as Orders' default reads them.

local sessionDeaths = 0
local lastDeath = nil        -- { mapID, x, y, zone, when }

local function IsOn()
    return CommanderRecoveryDB and CommanderRecoveryDB.EnableRecovery
end

-- Commander Orders' public table when it is loaded (looked up each time: it
-- is an optional dependency, and its functions answer rather than raise)
local function Orders()
    local api = CommanderOrders
    if type(api) == "table" and type(api.CorpseArrow) == "function" then return api end
    return nil
end

-- Orders 3.1's "Go to" surface (FormatCoords, ChatLink), when loaded
local function OrdersGo()
    local api = CommanderOrders
    if type(api) == "table" and type(api.FormatCoords) == "function" and type(api.ChatLink) == "function" then
        return api
    end
    return nil
end

-- "(45.2, 66.8) [Go]": the spot in the player's chosen precision and Orders'
-- link to it; "(45.2, 66.8)" alone without Orders 3.1
local function Where(spot)
    local api = OrdersGo()
    local coords, link
    if api then
        local ok, text = pcall(api.FormatCoords, spot.x, spot.y)
        if ok and type(text) == "string" and text ~= "" then coords = text end
        if spot.mapID then
            local okLink, made = pcall(api.ChatLink, spot.mapID, spot.x, spot.y, "Where you fell")
            if okLink and type(made) == "string" and made ~= "" then link = made end
        end
    end
    coords = coords or string.format("%.1f, %.1f", spot.x * 100, spot.y * 100)
    return "(" .. coords .. ")" .. (link and (" " .. link) or "")
end

-- Whether a release will get the Orders corpse arrow, and if not, why:
-- true | false, "absent" | "off" | "disabled"
local function CorpseArrowReady()
    local api = Orders()
    if not api then return false, "absent" end
    local ok, on = pcall(api.CorpseArrow)
    if not (ok and on) then return false, "off" end
    if type(api.IsAvailable) == "function" then
        local okAvail, available = pcall(api.IsAvailable)
        if okAvail and not available then return false, "disabled" end
    end
    return true
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
            "Commander Recovery: %d casualt%s this session — last unit lost in %s %s",
            sessionDeaths, sessionDeaths == 1 and "y" or "ies",
            lastDeath.zone, Where(lastDeath)))
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
    local ready, why = CorpseArrowReady()
    local corpse
    if ready then
        corpse = "releasing would point the Commander Orders arrow at your corpse"
    elseif why == "off" then
        corpse = "no corpse arrow: it is off (Corpse Arrow, Commander Orders)"
    elseif why == "disabled" then
        corpse = "no corpse arrow: Commander Orders is turned off"
    end
    if here.x then
        print(string.format(
            "Commander Recovery: TEST — unit lost in %s %s%s",
            here.zone, Where(here), corpse and ("; " .. corpse) or ""))
    else
        print(string.format("Commander Recovery: TEST — unit lost in %s%s", here.zone,
            corpse and ("; " .. corpse) or ""))
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
    -- A hunter's Feign Death fires PLAYER_DEAD too. Counting it logged a
    -- casualty, armed the re-fire guard below on the fake, and so swallowed
    -- the hunter's next real death (and a bogus "recovered" followed)
    if UnitIsFeignDeath and UnitIsFeignDeath("player") then return end
    if UnitIsDeadOrGhost and not UnitIsDeadOrGhost("player") then return end
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

-- Orders adds the corpse waypoint from its own handler for the same event,
-- and the order two handlers run in is not ours to know: look a frame later.
-- Nothing is said when Orders has no corpse (a battleground, the setting
-- off, a corpse the client cannot place yet) -- the line never promises an
-- arrow that is not there.
local function SayIfCorpseArrow()
    if not (IsOn() and UnitIsGhost and UnitIsGhost("player")) then return end
    local api = Orders()
    if not (api and type(api.List) == "function") then return end
    local ok, corpses = pcall(api.List, { kind = "corpse" })
    if ok and type(corpses) == "table" and corpses[1] then
        print("Commander Recovery: corpse located -- follow the Commander Orders arrow, soldier")
    end
end

local function OnReleased()
    if not IsOn() then return end
    if not CorpseArrowReady() then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, SayIfCorpseArrow)
    else
        SayIfCorpseArrow()
    end
end

local function OnRecovered()
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

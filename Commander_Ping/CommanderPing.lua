-- Commander Ping: RTS-style minimap ping alerts. WoW's native group ping is
-- a tiny blip that is trivially missed; this module reacts to MINIMAP_PING
-- with a sound, a bright expanding ring on the pinged spot, and a chat
-- callout naming the pinger.

local FLASH_STEPS = 24
local FLASH_INTERVAL = 0.04

local flash = CreateFrame("Frame", "CommanderPingFlash", Minimap)
flash:SetSize(28, 28)
flash:SetFrameStrata("HIGH")
flash:Hide()

local ring = flash:CreateTexture(nil, "OVERLAY")
ring:SetAllPoints()
ring:SetTexture("Interface\\Minimap\\UI-Minimap-Ping-Expand")
ring:SetVertexColor(1, 0.9, 0.2, 1)

local flashTicker
local flashStep = 0

local function StopFlash()
    if flashTicker then
        flashTicker:Cancel()
        flashTicker = nil
    end
    flash:Hide()
end

-- x/y from MINIMAP_PING are normalized offsets from the minimap center
-- (-0.5 .. 0.5 on each axis)
local function StartFlash(x, y)
    StopFlash()
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    flash:ClearAllPoints()
    flash:SetPoint("CENTER", Minimap, "CENTER", x * width, y * height)
    flashStep = 0
    flash:SetAlpha(1)
    flash:SetSize(20, 20)
    flash:Show()
    flashTicker = C_Timer.NewTicker(FLASH_INTERVAL, function()
        flashStep = flashStep + 1
        if flashStep >= FLASH_STEPS then
            StopFlash()
            return
        end
        -- Ring grows and fades, twice, for a radar-pulse feel
        local phase = (flashStep % (FLASH_STEPS / 2)) / (FLASH_STEPS / 2)
        local size = 20 + phase * 36
        flash:SetSize(size, size)
        flash:SetAlpha(1 - phase * 0.9)
    end)
end

-- Shared with /cping test
function CommanderPing_Test()
    StartFlash(0.15, 0.15)
    if CommanderPingDB.PingSound then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
    end
    if CommanderPingDB.PingCallout then
        print("|cff40c0ffCommander Ping:|r this is what a group ping looks like")
    end
end

-- MINIMAP_PING payload is (unitTarget, x, y) — normalized offsets from the
-- minimap center. (An earlier build assumed y-first; in-game testing showed
-- bottom-right clicks flashing top-left, the signature of swapped axes.)
local function OnPing(unit, x, y)
    if not (CommanderPingDB and CommanderPingDB.EnablePing) then return end
    local isOwn = UnitIsUnit and UnitIsUnit(unit, "player")
    if isOwn and not CommanderPingDB.IncludeOwnPings then return end

    StartFlash(x or 0, y or 0)
    if CommanderPingDB.PingSound then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
    end
    if CommanderPingDB.PingCallout then
        local name = UnitName(unit) or "Someone"
        print(string.format("|cff40c0ffCommander Ping:|r %s pinged the minimap", name))
    end
end

-- The 2.5.6 patch made MINIMAP_PING a callback-only event: RegisterEvent
-- raises "unknown event" for it (Blizzard's own minimap switched to
-- RegisterEventCallback in the same patch). Pick the mechanism the client
-- actually supports; everything is guarded so the module always loads.
local events = CreateFrame("Frame")
if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid("MINIMAP_PING") then
    events:RegisterEvent("MINIMAP_PING")
    events:SetScript("OnEvent", function(self, event, unit, x, y)
        OnPing(unit, x, y)
    end)
elseif events.RegisterEventCallback then
    pcall(events.RegisterEventCallback, events, "MINIMAP_PING", function(owner, unit, x, y)
        OnPing(unit, x, y)
    end)
end

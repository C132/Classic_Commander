-- Commander Nameplate — the target's health as a number, not a percentage.
--
-- Two readouts, one setting each:
--
-- Blizzard's target frame answers to the account-wide statusTextDisplay CVar.
-- The only value that yields "current / max" there (NUMERIC) also strips the
-- percentage off the player frame, and BOTH puts the percentage on the left
-- with the bare current value on the right. The status-bar mixin documents a
-- per-bar override for exactly this case (showNumeric, "often externally set
-- as a temporary override"), so the target and focus health bars are flipped
-- to numeric on their own and the player frame keeps whatever the CVar says.
--
-- World nameplates carry health text too on this client (nameplateInfoDisplay
-- bits for percent / current value), but numeric there means the CURRENT value
-- alone, abbreviated — Blizzard sets disableMaxValue on every plate bar. The
-- same mixin fields let the target's plate read current / max, again without
-- touching the CVar, so the other plates keep showing what the user picked in
-- Blizzard's own Nameplates options.
--
-- Both overrides yield to Blizzard's judgement that no true value exists: on
-- the unit frames UnitFrameHealthBar_Update raises showPercentage when the
-- client only knows a unit's health as a percentage -- which on this client
-- is every hostile PLAYER -- and that bar used to be left alone rather than
-- shown as "45 / 100".
--
-- Now it is ESTIMATED instead. Commander.Health (in the Events hub) watches
-- the combat log against the percent readings and reverse-engineers the
-- maximum -- 900 damage for a ten-point drop is a 9000 bar, and a death from
-- full is exact -- so a percent-only bar reads "~3.2k / 7.2k", tilde first,
-- because it is a measurement and not a fact. The hook is Blizzard's own:
-- TextStatusBarMixin.numericDisplayTransformFunc, the documented seam for
-- "display these numbers differently".

local function DB(key, default)
    local value = CommanderNameplateDB and CommanderNameplateDB[key]
    if value == nil then return default end
    return value
end

local function Estimating()
    return DB("estimateHealth", true) and Commander and Commander.Health ~= nil
end

-- The unit a bar is drawing: unit frames carry .unit; a nameplate bar's grand-
-- parent is the CompactUnitFrame that does
local function BarUnit(bar)
    if bar.unit then return bar.unit end
    local uf = bar:GetParent() and bar:GetParent():GetParent()
    return uf and (uf.displayedUnit or uf.unit)
end

-- A transform per bar: default formatting unless the unit is percent-only AND
-- the book has a number for it
local function InstallTransform(bar, abbreviate)
    if bar.commanderTransform then return end
    bar.commanderTransform = true
    local format = abbreviate and AbbreviateLargeNumbers or BreakUpLargeNumbers
    bar.numericDisplayTransformFunc = function(value, valueMax)
        if valueMax == 100 and Estimating() then
            local unit = BarUnit(bar)
            if unit and Commander.Health.IsPercentOnly(unit) then
                local cur, max = Commander.Health.Current(unit)
                if cur and max then
                    local A = Commander.Health.Abbreviate
                    return "~" .. A(cur), A(max)
                end
            end
        end
        return format(value), format(valueMax)
    end
end

-- Does this percent-only bar have an estimate to show?
local function HasEstimate(bar)
    if not Estimating() then return false end
    local unit = BarUnit(bar)
    if not unit or not Commander.Health.IsPercentOnly(unit) then return false end
    local cur = Commander.Health.Current(unit)
    return cur ~= nil
end

-- ---------------------------------------------------------------------------
-- Unit frames: target and focus
-- ---------------------------------------------------------------------------

local UNIT_FRAMES = { "TargetFrame", "FocusFrame" }
local frameBars = {}   -- health bar -> true, the bars this file manages
local frameHooked = false

local function HealthBarOf(frameName)
    local host = _G[frameName]
    return _G[frameName .. "HealthBar"] or (host and (host.HealthBar or host.healthbar))
end

local function ApplyFrameBar(bar)
    InstallTransform(bar, false)
    local numeric = DB("targetFrameNumeric", true)
    local want
    if numeric and not bar.showPercentage then
        want = true
    elseif numeric and bar.showPercentage and HasEstimate(bar) then
        -- Blizzard raised showPercentage because the client only knows the
        -- percent; the book knows better, so the bar reads numeric after all
        want = true
        bar.showPercentage = false
        bar.commanderEstimated = true
    end
    if bar.showNumeric ~= want or bar.commanderEstimated then
        bar.showNumeric = want
        if not want then bar.commanderEstimated = nil end
        if bar.UpdateTextString then bar:UpdateTextString() end
    end
end

local function ApplyFrameBars()
    for bar in pairs(frameBars) do ApplyFrameBar(bar) end
end

local function InstallFrameBars()
    for _, name in ipairs(UNIT_FRAMES) do
        local bar = HealthBarOf(name)
        if bar and not frameBars[bar] then
            frameBars[bar] = true
            ApplyFrameBar(bar)
        end
    end
    -- showPercentage is rewritten on every unit or max-health change, and
    -- this is the one place Blizzard does it; re-decide right behind it
    if UnitFrameHealthBar_Update and not frameHooked then
        frameHooked = true
        hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar)
            if frameBars[statusbar] then ApplyFrameBar(statusbar) end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- World nameplates
-- ---------------------------------------------------------------------------

local plateBars = setmetatable({}, { __mode = "k" })   -- health bar -> true

local function PlateWantsNumeric(bar)
    InstallTransform(bar, true)
    local mode = DB("plateHealthText", "TARGET")
    if mode == "OFF" then return false end
    -- A percent-only unit (every hostile player) with no estimate yet would
    -- read "100 / 100" -- a percentage wearing a number's clothes. Blizzard's
    -- own display stands until the book has a real figure
    local unit = BarUnit(bar)
    if unit and Commander.Health and Commander.Health.IsPercentOnly(unit) and not HasEstimate(bar) then
        return false
    end
    -- Blizzard hides the text on simplified plates that are not the target,
    -- and whenever the name is hidden; that ruling stands
    local ok, shown = pcall(bar.ShouldTextBeShown, bar)
    if not ok or not shown then return false end
    if mode == "ALL" then return true end
    return bar:IsTarget() == true
end

-- Runs right behind Blizzard's UpdateTextDisplay, which has just recomputed
-- showNumeric / showPercentage / forceShow from the CVar and redrawn the text
local function ApplyPlateBar(bar)
    if PlateWantsNumeric(bar) then
        bar.showNumeric = true
        bar.showPercentage = false
        bar.forceShow = true
        bar.disableMaxValue = false
        bar.commanderNumeric = true
        bar:UpdateTextString()
    elseif bar.commanderNumeric then
        -- Blizzard's flags are already authoritative again; only the
        -- max-value change is ours to undo
        bar.commanderNumeric = nil
        bar.disableMaxValue = true
        bar:UpdateTextString()
    end
end

local function PlateHealthBar(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    local uf = plate and plate.UnitFrame
    if not uf or (uf.IsForbidden and uf:IsForbidden()) then return end
    local bar = (uf.HealthBarsContainer and uf.HealthBarsContainer.healthBar) or uf.healthBar
    if bar and bar.UpdateTextDisplay and bar.UpdateTextString then return bar end
end

local function OnPlateAdded(unit)
    local bar = PlateHealthBar(unit)
    if not bar then return end
    if not plateBars[bar] then
        plateBars[bar] = true
        hooksecurefunc(bar, "UpdateTextDisplay", ApplyPlateBar)
    end
    -- Blizzard's own handler ran first and already set unit and target state
    ApplyPlateBar(bar)
end

local function ReapplyPlates()
    -- UpdateTextDisplay restores Blizzard's flags and then lands in the hook,
    -- which re-decides under the current setting
    for bar in pairs(plateBars) do
        pcall(bar.UpdateTextDisplay, bar)
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

-- Declared ABOVE the handler that calls it: a local named below its call site
-- compiles as a global lookup and is nil when the event fires
local function RefreshWatch()
    if Estimating() and Commander.Health.Watch then Commander.Health.Watch() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        RefreshWatch()
        InstallFrameBars()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        OnPlateAdded(unit)
    end
end)

Commander.AddListener(COMMANDER_NAMEPLATE_EVENTS.UPDATE, function()
    RefreshWatch()
    InstallFrameBars()
    ApplyFrameBars()
    ReapplyPlates()
end)

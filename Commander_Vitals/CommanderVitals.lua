-- Commander Vitals: per-slot equipment condition readout, styled after the
-- unit wireframe in an RTS HUD. One row per durability-bearing slot: the
-- item's icon plus a small bar colored by remaining durability. Hidden
-- until something crosses the warning threshold (or Always Show is on).
--
-- 2.2.0 (Commander Orders 3.1): a worn slot's tooltip names the nearest
-- repairer (Orders' locator, { townsfolk = "Repair" }: your faction, your
-- landmass, the nearest) and how to go there, /cvitals repair, which asks
-- Orders for that waypoint (source "Vitals", key "repair"). The rows stay
-- hover-only: the HUD keeps passing clicks through, so the way there is a
-- word, not a click. Without Orders, or with nobody to name, the tooltip is
-- what it was.

-- The nearest repairer Orders can name: "Smith Argus (Elwynn Forest 41.8,
-- 67.1)", or nil. PlaceFor answers the spot the arrow would take; the
-- locator's own list (kept, so a hover is cheap) names who stands there.
local function NearestRepair()
    local O = CommanderOrders
    if not (type(O) == "table" and type(O.PlaceFor) == "function" and type(O.Locate) == "function") then
        return nil
    end
    local query = { townsfolk = "Repair" }
    local spot = O.PlaceFor(query)
    if type(spot) ~= "table" or type(spot.map) ~= "number" then return nil end
    local name = nil
    local places = O.Locate(query)
    for _, p in ipairs(type(places) == "table" and places or {}) do
        if p.map == spot.map and math.abs((p.x or -1) - spot.x) < 1e-6 and math.abs((p.y or -1) - spot.y) < 1e-6 then
            name = p.title
            break
        end
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(spot.map)
    local coords = type(O.FormatCoords) == "function" and O.FormatCoords(spot.x, spot.y)
        or string.format("%.1f, %.1f", spot.x * 100, spot.y * 100)
    local where = ((info and info.name) and (info.name .. " ") or "") .. coords
    return (name or spot.title or "Repair") .. " (" .. where .. ")"
end

-- /cvitals repair: Orders' arrow to the nearest repairer; Orders speaks for it
function CommanderVitals_GoToRepair()
    local O = CommanderOrders
    if not (type(O) == "table" and type(O.GoTo) == "function") then
        print("Commander Vitals: Go to Repair needs Commander Orders")
        return nil
    end
    return O.GoTo({ townsfolk = "Repair" }, { source = "Vitals", key = "repair", icon = "VENDOR" })
end

local DURABILITY_SLOTS = {
    { id = 1,  label = "Head" },
    { id = 3,  label = "Shoulder" },
    { id = 5,  label = "Chest" },
    { id = 6,  label = "Waist" },
    { id = 7,  label = "Legs" },
    { id = 8,  label = "Feet" },
    { id = 9,  label = "Wrist" },
    { id = 10, label = "Hands" },
    { id = 16, label = "Main Hand" },
    { id = 17, label = "Off Hand" },
    { id = 18, label = "Ranged" },
}

local ROW_HEIGHT = 14
local BAR_WIDTH = 60
local BAR_HEIGHT = 7

local root = CreateFrame("Frame", "CommanderVitalsFrame", UIParent)
root:SetPoint("RIGHT", UIParent, "RIGHT", -14, 0)
root:SetSize(BAR_WIDTH + 22, #DURABILITY_SLOTS * ROW_HEIGHT)
root:SetFrameStrata("MEDIUM")
root:Hide()

local function ConditionColor(pct)
    if pct > 0.5 then
        return 0.25, 0.9, 0.35
    elseif pct > 0.25 then
        return 1, 0.82, 0.15
    end
    return 1, 0.25, 0.2
end

local rows = {}
for i, slot in ipairs(DURABILITY_SLOTS) do
    local row = CreateFrame("Frame", nil, root)
    row:SetSize(BAR_WIDTH + 22, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    -- Hover-only mouse where the client supports it: EnableMouse(true)
    -- would swallow clicks (including the chrome overlay's drags beneath)
    if row.EnableMouseMotion then
        row:EnableMouseMotion(true)
    else
        row:EnableMouse(true)
    end

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(12, 12)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBG:SetVertexColor(0, 0, 0, 0.55)
    row.barBG:SetSize(BAR_WIDTH, BAR_HEIGHT)
    row.barBG:SetPoint("LEFT", row, "LEFT", 18, 0)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
    row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)

    row.slotID = slot.id
    -- ANCHOR_LEFT: the wireframe hugs the right screen edge, so a
    -- right-growing tooltip would render off screen
    Commander.UI.AttachTooltip(row, slot.label, function()
        local cur, max = GetInventoryItemDurability(row.slotID)
        if cur and max and max > 0 then
            local text = string.format("Condition: %d / %d (%.0f%%)", cur, max, cur / max * 100)
            -- Worn to the warning line: where to fix it (Commander Orders)
            local threshold = (CommanderVitalsDB and CommanderVitalsDB.WarnThreshold) or 0.5
            if cur / max <= threshold then
                local ok, repairer = pcall(NearestRepair)
                if ok and repairer then
                    text = text .. "\n\nNearest repair: " .. repairer .. "\n/cvitals repair: Go to Repair (the Commander Orders arrow)"
                end
            end
            return text
        end
        return "No durability on this slot."
    end, "ANCHOR_LEFT")

    rows[i] = row
end

local function Refresh()
    if not (CommanderVitalsDB and CommanderVitalsDB.EnableVitals) then
        root:Hide()
        return
    end
    Commander.UI.ApplyHudChrome(root, CommanderVitalsDB, "Vitals", {
        title = "Vitals",
        defaultPoint = { point = "RIGHT", x = -14, y = 0 },
    })

    local shownRows = 0
    local worst = 1
    for _, row in ipairs(rows) do
        local cur, max = GetInventoryItemDurability(row.slotID)
        if cur and max and max > 0 then
            local pct = cur / max
            worst = math.min(worst, pct)
            row.icon:SetTexture(GetInventoryItemTexture("player", row.slotID)
                or "Interface\\Icons\\INV_Misc_QuestionMark")
            -- Suite icon recess (Commander_Events' shared art)
            if Commander.DebossIcon then
                Commander.DebossIcon(row.icon,
                    (CommanderVitalsDB and CommanderVitalsDB.IconRecess) or "SOFT")
            end
            row.bar:SetSize(math.max(BAR_WIDTH * pct, 1), BAR_HEIGHT)
            row.bar:SetVertexColor(ConditionColor(pct))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -shownRows * ROW_HEIGHT)
            row:Show()
            shownRows = shownRows + 1
        else
            row:Hide()
        end
    end

    -- While unlocked the frame must stay visible to be draggable, even
    -- with nothing to report
    local unlocked = Commander.UI.HudUnlocked(CommanderVitalsDB, "Vitals")
    if shownRows == 0 then
        root:SetSize(BAR_WIDTH + 22, ROW_HEIGHT)
        root:SetShown(unlocked)
        return
    end
    root:SetSize(BAR_WIDTH + 22, shownRows * ROW_HEIGHT)
    local threshold = CommanderVitalsDB.WarnThreshold or 0.5
    root:SetShown(unlocked or CommanderVitalsDB.AlwaysShow or worst <= threshold)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
events:RegisterEvent("UNIT_INVENTORY_CHANGED")
events:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_INVENTORY_CHANGED" and unit ~= "player" then return end
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_VITALS_EVENTS.UPDATE, Refresh)
    end
    Refresh()
end)

-- Commander Vitals: per-slot equipment condition readout, styled after the
-- unit wireframe in an RTS HUD. One row per durability-bearing slot: the
-- item's icon plus a small bar colored by remaining durability. Hidden
-- until something crosses the warning threshold (or Always Show is on).

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
    row:EnableMouse(true)

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
            return string.format("Condition: %d / %d (%.0f%%)", cur, max, cur / max * 100)
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
    root:SetScale(CommanderVitalsDB.VitalsScale or 1)

    local shownRows = 0
    local worst = 1
    for _, row in ipairs(rows) do
        local cur, max = GetInventoryItemDurability(row.slotID)
        if cur and max and max > 0 then
            local pct = cur / max
            worst = math.min(worst, pct)
            row.icon:SetTexture(GetInventoryItemTexture("player", row.slotID)
                or "Interface\\Icons\\INV_Misc_QuestionMark")
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

    if shownRows == 0 then
        root:Hide()
        return
    end
    root:SetSize(BAR_WIDTH + 22, shownRows * ROW_HEIGHT)
    local threshold = CommanderVitalsDB.WarnThreshold or 0.5
    root:SetShown(CommanderVitalsDB.AlwaysShow or worst <= threshold)
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

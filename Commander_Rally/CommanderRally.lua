-- Commander Rally: four persistent rally point slots. Marking a slot stores
-- the player's current map position; rallying to a slot re-issues it as a
-- Commander Orders move order (hard dependency, listed in the TOC), so the
-- existing arrow does all the guidance work.

local function IsOn()
    return CommanderRallyDB and CommanderRallyDB.EnableRally
end

local function ValidSlot(slot)
    return type(slot) == "number" and slot >= 1 and slot <= 4
end

function CommanderRally_Set(slot)
    if not IsOn() then
        print("Commander Rally: module is disabled (enable it in settings or /crally)")
        return
    end
    if not ValidSlot(slot) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then
        print("Commander Rally: cannot mark a rally point here (no map position — instances and some interiors)")
        return
    end
    CommanderRallyDB.Points[slot] = {
        mapID = mapID, x = pos.x, y = pos.y,
        zone = GetZoneText() or "unknown territory",
    }
    if CommanderRallyDB.RallySound then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
    print(string.format("Commander Rally: rally point %d marked — %s (%.0f, %.0f)",
        slot, CommanderRallyDB.Points[slot].zone, pos.x * 100, pos.y * 100))
end

function CommanderRally_Go(slot)
    if not IsOn() then
        print("Commander Rally: module is disabled (enable it in settings or /crally)")
        return
    end
    if not ValidSlot(slot) then return end
    local p = CommanderRallyDB.Points[slot]
    if not p then
        print(string.format("Commander Rally: no rally point marked in slot %d (use /crally set %d)", slot, slot))
        return
    end
    if not CommanderOrders_IssueOrder then
        print("Commander Rally: Commander Orders is not loaded — no arrow available")
        return
    end
    -- IssueOrder itself does not check the Orders master flag, but the
    -- arrow never shows while it is off — refuse instead of faking success
    if CommanderOrdersDB and CommanderOrdersDB.EnableOrders == false then
        print("Commander Rally: Commander Orders is disabled — enable it to get a rally arrow")
        return
    end
    if not CommanderOrders_IssueOrder(p.mapID, p.x, p.y) then
        print(string.format("Commander Rally: could not issue an order for rally point %d (%s)", slot, p.zone or "unknown"))
    end
end

function CommanderRally_List()
    local any = false
    for slot = 1, 4 do
        local p = CommanderRallyDB.Points and CommanderRallyDB.Points[slot]
        if p then
            print(string.format("Commander Rally %d: %s (%.0f, %.0f)", slot, p.zone or "unknown", (p.x or 0) * 100, (p.y or 0) * 100))
            any = true
        end
    end
    if not any then
        print("Commander Rally: no rally points marked yet (/crally set 1 while standing somewhere worth returning to)")
    end
end

-- Commander Production: active spell cooldowns rendered as an RTS build
-- queue. SPELL_UPDATE_COOLDOWN triggers a spellbook sweep (classic-style
-- spellbook API); anything on a cooldown longer than the configured minimum
-- joins the queue as a bar filling toward ready. Keyed by spell name so
-- multiple ranks sharing a cooldown collapse into one entry.

local BOOKTYPE = "spell"
local BAR_WIDTH = 110
local BAR_HEIGHT = 12
local ROW_GAP = 4
local SWEEP_THROTTLE = 0.25
local DRAW_THROTTLE = 0.1

local active = {}     -- name -> { texture, start, duration }
local rowPool = {}
local sinceSweep, sinceDraw = 0, 0
local sweepQueued = false
local drawingAfterSweep = false

local root = CreateFrame("Frame", "CommanderProductionFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, -40)
root:SetSize(BAR_WIDTH + 20, 8 * (BAR_HEIGHT + ROW_GAP))
root:SetFrameStrata("MEDIUM")
root:Hide()

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, root)
    row:SetSize(BAR_WIDTH + 20, BAR_HEIGHT)
    row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(index - 1) * (BAR_HEIGHT + ROW_GAP))

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBG:SetVertexColor(0, 0, 0, 0.55)
    row.barBG:SetSize(BAR_WIDTH, BAR_HEIGHT)
    row.barBG:SetPoint("LEFT", row, "LEFT", BAR_HEIGHT + 4, 0)

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetVertexColor(0.35, 0.65, 1, 0.9)
    row.bar:SetSize(1, BAR_HEIGHT)
    row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)

    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFontObject(GameFontHighlightSmall)
    row.label:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
    row.label:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)
    row.label:SetJustifyH("LEFT")

    rowPool[index] = row
    return row
end

local function FormatRemaining(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    end
    return string.format("%ds", math.ceil(seconds))
end

local function ReadyAlert(name)
    if CommanderProductionDB.ReadyAlert then
        print(string.format("Commander Production: %s ready", name))
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
end

local function Sweep()
    if not GetNumSpellTabs then return end
    local minDuration = CommanderProductionDB.MinDuration or 10
    local now = GetTime()
    local scanned, stillOn = {}, {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSlots = GetSpellTabInfo(tab)
        for slot = offset + 1, offset + (numSlots or 0) do
            local name = GetSpellBookItemName(slot, BOOKTYPE)
            if name then
                scanned[name] = true
                local start, duration, enabled = GetSpellCooldown(slot, BOOKTYPE)
                if start and start > 0 and enabled == 1
                    and duration and duration >= minDuration
                    and (start + duration) > now then
                    stillOn[name] = true
                    local entry = active[name]
                    if not entry then
                        active[name] = {
                            texture = GetSpellBookItemTexture(slot, BOOKTYPE),
                            start = start, duration = duration,
                        }
                    else
                        entry.start, entry.duration = start, duration
                    end
                end
            end
        end
    end
    -- Early cooldown resets (Preparation, Cold Snap, Readiness): the
    -- spellbook now reports the cooldown gone before the recorded end
    -- time — the spell really is ready, so drop the bar and alert now
    -- instead of minutes later
    for name in pairs(active) do
        if scanned[name] and not stillOn[name] then
            active[name] = nil
            ReadyAlert(name)
        end
    end
end

local function Draw()
    local now = GetTime()
    local queue = {}
    for name, entry in pairs(active) do
        local remaining = entry.start + entry.duration - now
        if remaining <= 0 then
            active[name] = nil
            ReadyAlert(name)
        else
            queue[#queue + 1] = { name = name, entry = entry, remaining = remaining }
        end
    end
    table.sort(queue, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return a.name < b.name
    end)

    local maxBars = CommanderProductionDB.MaxBars or 5
    local shown = math.min(#queue, maxBars)
    for i = 1, shown do
        local row = AcquireRow(i)
        local item = queue[i]
        local progress = 1 - (item.remaining / item.entry.duration)
        row.icon:SetTexture(item.entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.bar:SetSize(math.max(BAR_WIDTH * progress, 1), BAR_HEIGHT)
        row.label:SetText(string.format("%s  %s", item.name, FormatRemaining(item.remaining)))
        row:Show()
    end
    for i = shown + 1, #rowPool do
        rowPool[i]:Hide()
    end
    -- Fixed height keeps a stable backdrop; dynamic fits what is shown.
    -- Unlocked or Always Show keeps the frame visible with an empty queue.
    local heightRows = CommanderProductionDB.FixedHeight
        and (CommanderProductionDB.MaxBars or 5) or math.max(shown, 1)
    root:SetSize(BAR_WIDTH + 20, heightRows * (BAR_HEIGHT + ROW_GAP))
    root:SetShown(shown > 0 or CommanderProductionDB.AlwaysShow
        or Commander.UI.HudUnlocked(CommanderProductionDB, "Hud"))
    -- Hiding the root kills the OnUpdate driver; a sweep still queued at
    -- that moment (new cooldown started as the last bar expired) must run
    -- now or the new bar would be lost until the next cooldown event
    if shown == 0 and sweepQueued and not drawingAfterSweep then
        sweepQueued = false
        sinceSweep = 0
        Sweep()
        drawingAfterSweep = true
        Draw()
        drawingAfterSweep = false
    end
end

root:SetScript("OnUpdate", function(self, elapsed)
    sinceDraw = sinceDraw + elapsed
    if sweepQueued then
        sinceSweep = sinceSweep + elapsed
        if sinceSweep >= SWEEP_THROTTLE then
            sinceSweep = 0
            sweepQueued = false
            Sweep()
        end
    end
    if sinceDraw >= DRAW_THROTTLE then
        sinceDraw = 0
        Draw()
    end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")

local function Apply()
    if CommanderProductionDB and CommanderProductionDB.EnableProduction then
        Commander.UI.ApplyHudChrome(root, CommanderProductionDB, "Hud", {
            defaultPoint = { point = "LEFT", x = 14, y = -40 },
        })
        Sweep()
        Draw()
        -- The OnUpdate driver only runs while the root is shown; when the
        -- queue is empty we still need sweeps, so wake on the next event
    else
        wipe(active)
        root:Hide()
    end
end

watcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Commander.AddListener(COMMANDER_PRODUCTION_EVENTS.UPDATE, Apply)
        Apply()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if CommanderProductionDB and CommanderProductionDB.EnableProduction then
            -- IsVisible, not IsShown: with the UI hidden (Alt+Z, cinematic)
            -- the OnUpdate driver is not ticking, so a queued sweep would
            -- never run — sweep directly instead
            if root:IsVisible() then
                sweepQueued = true
            else
                Sweep()
                Draw()
            end
        end
    end
end)

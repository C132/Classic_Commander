-- Commander Production: active spell cooldowns rendered as an RTS build
-- queue. SPELL_UPDATE_COOLDOWN triggers a spellbook sweep (classic-style
-- spellbook API); anything on a cooldown longer than the configured minimum
-- joins the queue as a bar filling toward ready. Keyed by spell name so
-- multiple ranks sharing a cooldown collapse into one entry.

local BOOKTYPE = "spell"
local BAR_HEIGHT = 12
local ROW_GAP = 4
local ICON_SIZE = 26
local ICON_GAP = 4
local ICON_BAR_HEIGHT = 4
local SWEEP_THROTTLE = 0.25
local DRAW_THROTTLE = 0.1
-- Linger When Ready: finished cooldowns hold on the queue this long...
local READY_HOLD = 60
-- ...then fade out over this long (90s total lingering)
local READY_FADE = 30

local active = {}     -- name -> { texture, start, duration }
local rowPool = {}
local sinceSweep, sinceDraw = 0, 0
local sweepQueued = false
local drawingAfterSweep = false

local root = CreateFrame("Frame", "CommanderProductionFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, -40)
root:SetSize(130, 8 * (BAR_HEIGHT + ROW_GAP))
root:SetFrameStrata("MEDIUM")
root:Hide()

local function BarWidth()
    return (CommanderProductionDB and CommanderProductionDB.BarWidth) or 110
end

local function LayoutMode()
    return (CommanderProductionDB and CommanderProductionDB.Layout) or "BARS_DOWN"
end

local function AcquireRow(index)
    local row = rowPool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, root)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.barBG = row:CreateTexture(nil, "BACKGROUND")
    row.barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBG:SetVertexColor(0, 0, 0, 0.55)
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetVertexColor(0.35, 0.65, 1, 0.9)
    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetFontObject(GameFontHighlightSmall)
    row.label:SetJustifyH("LEFT")

    -- Optional per-icon cooldown overlays: a radial sweep and a countdown
    -- text, toggled by the Cooldown Overlay setting
    row.sweep = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.sweep:SetAllPoints(row.icon)
    if row.sweep.SetHideCountdownNumbers then
        row.sweep:SetHideCountdownNumbers(true)
    end
    if row.sweep.SetDrawEdge then
        row.sweep:SetDrawEdge(false)
    end
    row.sweep:Hide()
    local timerHolder = CreateFrame("Frame", nil, row)
    timerHolder:SetAllPoints(row.icon)
    timerHolder:SetFrameLevel((row.sweep:GetFrameLevel() or 1) + 2)
    row.timer = timerHolder:CreateFontString(nil, "OVERLAY")
    row.timer:SetFontObject(GameFontHighlightSmall)
    do
        local fontPath, fontSize = row.timer:GetFont()
        if fontPath then
            row.timer:SetFont(fontPath, fontSize or 10, "OUTLINE")
        end
    end
    row.timer:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.timer:Hide()

    -- Full spell tooltip on hover (falls back to name + remaining when the
    -- spell can't be resolved); hover-only mouse so chrome drags pass
    if row.EnableMouseMotion then
        row:EnableMouseMotion(true)
    end
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spellID and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.spellID)
            if self.tipText then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.tipText, 0.3, 1, 0.4)
            end
        else
            GameTooltip:SetText(self.tipText or "")
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    rowPool[index] = row
    return row
end

-- Reposition an entry for the active layout. Applied only when the layout
-- signature changes, not every draw.
local function ApplyRowGeometry(row, index, layout, barWidth)
    row:ClearAllPoints()
    row.icon:ClearAllPoints()
    row.barBG:ClearAllPoints()
    row.bar:ClearAllPoints()
    row.label:ClearAllPoints()
    if layout == "ICONS" then
        -- SC2 replay production tab: icons marching right, a slim
        -- progress bar under each
        row:SetSize(ICON_SIZE, ICON_SIZE + ICON_BAR_HEIGHT + 2)
        row:SetPoint("TOPLEFT", root, "TOPLEFT", (index - 1) * (ICON_SIZE + ICON_GAP), 0)
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.barBG:SetSize(ICON_SIZE, ICON_BAR_HEIGHT)
        row.barBG:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -2)
        row.bar:SetSize(1, ICON_BAR_HEIGHT)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.label:Hide()
    else
        row:SetSize(barWidth + 20, BAR_HEIGHT)
        if layout == "BARS_UP" then
            row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (index - 1) * (BAR_HEIGHT + ROW_GAP))
        else
            row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(index - 1) * (BAR_HEIGHT + ROW_GAP))
        end
        row.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.barBG:SetSize(barWidth, BAR_HEIGHT)
        row.barBG:SetPoint("LEFT", row, "LEFT", BAR_HEIGHT + 4, 0)
        row.bar:SetSize(1, BAR_HEIGHT)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.label:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
        row.label:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)
        row.label:Show()
    end
    row.geometrySig = layout .. barWidth
end

local function FormatRemaining(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    end
    return string.format("%ds", math.ceil(seconds))
end

local function ReadyAlert(name)
    if CommanderProductionDB.ReadyAlert then
        if CommanderProductionDB.ReadyChat ~= false then
            print(string.format("Commander Production: %s ready", name))
        end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB, "Master")
    end
end

-- Scratch tables reused across sweeps: `scanned` holds every spellbook
-- name (100+ entries), so allocating it fresh each 250ms sweep was
-- kilobytes of garbage per call
local scanned, stillOn = {}, {}

local function Sweep()
    if not GetNumSpellTabs then return end
    local minDuration = CommanderProductionDB.MinDuration or 10
    local now = GetTime()
    wipe(scanned)
    wipe(stillOn)
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
                        local spellID
                        if GetSpellBookItemInfo then
                            local _, id = GetSpellBookItemInfo(slot, BOOKTYPE)
                            spellID = id
                        end
                        active[name] = {
                            texture = GetSpellBookItemTexture(slot, BOOKTYPE),
                            start = start, duration = duration,
                            spellID = spellID,
                        }
                    else
                        entry.start, entry.duration = start, duration
                        -- Recast while lingering: back to a pending bar
                        entry.readyAt = nil
                    end
                end
            end
        end
    end
    -- Early cooldown resets (Preparation, Cold Snap, Readiness): the
    -- spellbook now reports the cooldown gone before the recorded end
    -- time — the spell really is ready, so alert now instead of minutes
    -- later, and either drop the bar or park it as READY
    for name, entry in pairs(active) do
        if scanned[name] and not stillOn[name] and not entry.readyAt then
            if CommanderProductionDB.LingerReady then
                entry.readyAt = now
            else
                active[name] = nil
            end
            ReadyAlert(name)
        end
    end
end

-- Queue scratch reused across draws — the list plus one pooled item table
-- per slot, refilled in place. A fresh table set per 0.1s draw was this
-- module's main garbage source.
local queue = {}
local queueItems = {}

local function NextQueueItem()
    local index = #queue + 1
    local it = queueItems[index]
    if not it then
        it = {}
        queueItems[index] = it
    end
    it.name, it.entry, it.ready, it.alpha, it.remaining = nil, nil, nil, nil, nil
    queue[index] = it
    return it
end

-- Pending cooldowns first (soonest ready on top), READY stragglers
-- after, freshest first
local function QueueCompare(a, b)
    if (a.ready or false) ~= (b.ready or false) then return not a.ready end
    if a.ready then
        if a.entry.readyAt ~= b.entry.readyAt then
            return a.entry.readyAt > b.entry.readyAt
        end
        return a.name < b.name
    end
    if a.remaining ~= b.remaining then return a.remaining < b.remaining end
    return a.name < b.name
end

local function Draw()
    local now = GetTime()
    wipe(queue)
    for name, entry in pairs(active) do
        if entry.readyAt then
            -- Lingering READY entry: 60s hold, 30s fade, then gone
            local lingering = now - entry.readyAt
            if lingering > (READY_HOLD + READY_FADE) or not CommanderProductionDB.LingerReady then
                active[name] = nil
            else
                local alpha = 1
                if lingering > READY_HOLD then
                    alpha = 1 - (lingering - READY_HOLD) / READY_FADE
                end
                local it = NextQueueItem()
                it.name, it.entry, it.ready, it.alpha = name, entry, true, alpha
            end
        else
            local remaining = entry.start + entry.duration - now
            if remaining <= 0 then
                if CommanderProductionDB.LingerReady then
                    entry.readyAt = now
                    local it = NextQueueItem()
                    it.name, it.entry, it.ready, it.alpha = name, entry, true, 1
                else
                    active[name] = nil
                end
                ReadyAlert(name)
            else
                local it = NextQueueItem()
                it.name, it.entry, it.remaining = name, entry, remaining
            end
        end
    end
    table.sort(queue, QueueCompare)

    local maxBars = CommanderProductionDB.MaxBars or 5
    local shown = math.min(#queue, maxBars)
    local layout = LayoutMode()
    local barWidth = BarWidth()
    local geometrySig = layout .. barWidth
    for i = 1, shown do
        local row = AcquireRow(i)
        if row.geometrySig ~= geometrySig then
            ApplyRowGeometry(row, i, layout, barWidth)
            -- Layout switches change which widgets carry the text — force
            -- the next content write through the dirty-check below
            row.shownName = nil
        end
        local item = queue[i]
        local overlay = CommanderProductionDB.CooldownOverlay or "BAR"
        row.icon:SetTexture(item.entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- In the icon strip the slim bar is itself an overlay choice; in
        -- the bar layouts the big bar is the row and always stays
        local showBar = layout ~= "ICONS" or overlay == "BAR" or overlay == "BOTH"
        row.barBG:SetShown(showBar)
        row.bar:SetShown(showBar)
        if item.ready then
            -- READY straggler: full green bar, fading out on its clock.
            -- Text content is static per item (secs key -1) — only the
            -- first draw after a change pays the format
            row.bar:SetVertexColor(0.3, 1, 0.4, 0.9)
            if layout == "ICONS" then
                row.bar:SetSize(ICON_SIZE, ICON_BAR_HEIGHT)
            else
                row.bar:SetSize(barWidth, BAR_HEIGHT)
            end
            if row.shownName ~= item.name or row.shownSecs ~= -1 then
                row.shownName, row.shownSecs = item.name, -1
                if layout ~= "ICONS" then
                    row.label:SetText(string.format("%s  READY", item.name))
                end
                row.tipText = string.format("%s — ready", item.name)
            end
            row.sweepStart = nil
            row.sweep:Hide()
            row.timer:Hide()
            row:SetAlpha(item.alpha or 1)
        else
            local progress = 1 - (item.remaining / item.entry.duration)
            row.bar:SetVertexColor(0.35, 0.65, 1, 0.9)
            if layout == "ICONS" then
                row.bar:SetSize(math.max(ICON_SIZE * progress, 1), ICON_BAR_HEIGHT)
            else
                row.bar:SetSize(math.max(barWidth * progress, 1), BAR_HEIGHT)
            end
            -- Text changes once per second; the bar resizes every draw.
            -- Skip the format+SetText+tipText churn on unchanged seconds.
            local secs = math.ceil(item.remaining)
            if row.shownName ~= item.name or row.shownSecs ~= secs
                or row.shownOverlay ~= overlay then
                row.shownName, row.shownSecs, row.shownOverlay = item.name, secs, overlay
                if layout ~= "ICONS" then
                    row.label:SetText(string.format("%s  %s", item.name, FormatRemaining(item.remaining)))
                end
                if overlay == "TEXT" then
                    row.timer:SetText(FormatRemaining(item.remaining))
                end
                row.tipText = string.format("%s — %s", item.name, FormatRemaining(item.remaining))
            end
            if overlay == "SWEEP" or overlay == "BOTH" then
                -- Numeric comparison: the old string signature allocated
                -- two tostrings and a concat per row per draw
                if row.sweepStart ~= item.entry.start or row.sweepDuration ~= item.entry.duration then
                    row.sweepStart, row.sweepDuration = item.entry.start, item.entry.duration
                    row.sweep:SetCooldown(item.entry.start, item.entry.duration)
                end
                row.sweep:Show()
            else
                row.sweepStart = nil
                row.sweep:Hide()
            end
            if overlay == "TEXT" then
                row.timer:Show()
            else
                row.timer:Hide()
            end
            row:SetAlpha(1)
        end
        row.spellID = item.entry.spellID
        row:Show()
    end
    for i = shown + 1, #rowPool do
        rowPool[i]:Hide()
    end
    -- Fixed size keeps a stable backdrop; dynamic fits what is shown.
    -- Unlocked or Always Show keeps the frame visible with an empty queue.
    local slots = CommanderProductionDB.FixedHeight
        and (CommanderProductionDB.MaxBars or 5) or math.max(shown, 1)
    if layout == "ICONS" then
        root:SetSize(slots * (ICON_SIZE + ICON_GAP) - ICON_GAP, ICON_SIZE + ICON_BAR_HEIGHT + 2)
    else
        root:SetSize(barWidth + 20, slots * (BAR_HEIGHT + ROW_GAP))
    end
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

-- Standard suite tester: feed a fake 30-second cooldown through the real
-- queue so the frame, layout, overlays, and the ready flow can be
-- previewed anywhere. Never in the spellbook scan, so sweeps leave it
-- alone until it expires naturally.
function CommanderProduction_Test()
    if not (CommanderProductionDB and CommanderProductionDB.EnableProduction) then
        print("Commander Production: module is disabled (enable it in settings or /cprod)")
        return
    end
    active["Test Cooldown"] = {
        texture = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        start = GetTime(),
        duration = 30,
    }
    Draw()
    print("Commander Production: test cooldown queued — 30 seconds to ready")
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")

local function Apply()
    if CommanderProductionDB and CommanderProductionDB.EnableProduction then
        Commander.UI.ApplyHudChrome(root, CommanderProductionDB, "Hud", {
            title = "Production",
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

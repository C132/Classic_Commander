-- Commander Production: active spell cooldowns rendered as an RTS build
-- queue. SPELL_UPDATE_COOLDOWN triggers a spellbook sweep (classic-style
-- spellbook API); anything on a cooldown longer than the configured minimum
-- joins the queue as a bar draining toward ready — full at cooldown start,
-- empty the moment it comes back. Keyed by spell name so multiple ranks
-- sharing a cooldown collapse into one entry.

local BOOKTYPE = "spell"
-- Row metrics are settings (Row Height, Icon Size, Spacing, Icons per Row);
-- what is left here is the fallback used before the DB is written, plus the
-- geometry not worth a slider.
local BAR_HEIGHT = 12       -- Row Height default
local ROW_GAP = 4           -- Spacing default
local ICON_SIZE = 26        -- Icon Size default
local ICON_BAR_HEIGHT = 4   -- the slim progress bar under a strip icon
local ROW_ICON_GAP = 4      -- bar row: icon to bar
local ROW_PAD = 4           -- bar row: trailing slack
local MAX_PER_ROW = 20      -- Icons per Row ceiling, matching Queue Length's
local SWEEP_THROTTLE = 0.25
local DRAW_THROTTLE = 0.1
-- Linger When Ready: finished cooldowns hold on the queue for the
-- configured Linger Time, then fade out over half that again
local READY_FADE_SHARE = 0.5

local active = {}     -- name -> { texture, start, duration }
-- An interrupt lockout masquerades as a cooldown: a kicked school reports
-- the lock as a cooldown on every spell it covers, so one Counterspell
-- fills the queue with a dozen spells that are not recharging at all.
-- Showing them while the school is down is honest — that is exactly what
-- is unavailable — but they must not outlive it: a lock lifting is not a
-- cooldown coming back, so these entries leave the queue the moment it
-- ends, with no linger and no ready alert.
local MAX_LOCKOUT = 10.5       -- the longest school lock in TBC; a longer
                               -- cooldown is the spell's own, kick or not
local LOCKOUT_TOLERANCE = 0.5  -- the lock starts with the kick that caused it
local lockoutAt
local playerGUID

local function IsLockoutCooldown(start, duration)
    if not lockoutAt then return false end
    if GetTime() - lockoutAt > MAX_LOCKOUT then
        lockoutAt = nil
        return false
    end
    return duration <= MAX_LOCKOUT and math.abs(start - lockoutAt) <= LOCKOUT_TOLERANCE
end
local rowPool = {}
local sinceSweep, sinceDraw = 0, 0
local sweepQueued = false
local drawingAfterSweep = false

local root = CreateFrame("Frame", "CommanderProductionFrame", UIParent)
root:SetPoint("LEFT", UIParent, "LEFT", 14, -40)
root:SetSize(130, 8 * (BAR_HEIGHT + ROW_GAP))
root:SetFrameStrata("MEDIUM")
root:Hide()

-- Hold at full opacity, then the fade tail, from the Linger Time setting
local function LingerWindow()
    local hold = (CommanderProductionDB and CommanderProductionDB.LingerTime) or 10
    return hold, hold * READY_FADE_SHARE
end

-- Both strip directions share every icon-strip code path except row anchoring
local function IsIconStrip(layout)
    return layout == "ICONS" or layout == "ICONS_RTL"
end

-- Every size the queue draws with, resolved once per draw into one reused
-- table. The signature string is what rows are stamped with: geometry is
-- re-applied when a setting moves, not on every draw.
local metrics = {}

local function Metrics()
    local db = CommanderProductionDB or {}
    local m = metrics
    m.layout = db.Layout or "BARS_DOWN"
    m.strip = IsIconStrip(m.layout)
    m.overlay = db.CooldownOverlay or "BAR"
    -- In the strip the slim bar is one overlay choice among four, so when it
    -- is off the row gives that height back instead of reserving it
    m.showBar = (not m.strip) or m.overlay == "BAR" or m.overlay == "BOTH"
    m.barWidth = db.BarWidth or 110
    m.rowHeight = db.RowHeight or BAR_HEIGHT
    m.iconSize = db.IconSize or ICON_SIZE
    m.gap = db.Spacing or ROW_GAP
    m.perRow = math.max(1, math.min(db.PerRow or MAX_PER_ROW, MAX_PER_ROW))
    m.rowWidth = m.barWidth + m.rowHeight + ROW_ICON_GAP + ROW_PAD
    m.stripRowHeight = m.iconSize + (m.showBar and (ICON_BAR_HEIGHT + 2) or 0)
    m.stepX = m.iconSize + m.gap
    m.stepY = m.stripRowHeight + m.gap
    m.sig = string.format("%s|%d|%d|%d|%d|%d|%s", m.layout, m.barWidth,
        m.rowHeight, m.iconSize, m.gap, m.perRow, tostring(m.showBar))
    return m
end

-- Text has to shrink with the row that holds it, or a 10px bar is a row of
-- clipped glyphs. Keeps the font object's own face and flags.
local function SetScaledFont(fontString, size, minSize, maxSize)
    if not (fontString and fontString.GetFont) then return end
    local path, _, flags = fontString:GetFont()
    if not path then return end
    fontString:SetFont(path, math.max(minSize, math.min(math.floor(size + 0.5), maxSize)), flags)
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
    -- The countdown is its own right-aligned string in the Bars layouts: a
    -- single "name  30s" label is the first thing to run out of room as rows
    -- get shorter and narrower, and the number is the half worth keeping
    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetFontObject(GameFontHighlightSmall)
    row.time:SetJustifyH("RIGHT")

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

-- Reposition an entry for the active layout. Applied only when the metrics
-- signature changes, not every draw.
local function ApplyRowGeometry(row, index, m)
    row:ClearAllPoints()
    row.icon:ClearAllPoints()
    row.barBG:ClearAllPoints()
    row.bar:ClearAllPoints()
    row.label:ClearAllPoints()
    row.time:ClearAllPoints()
    if m.strip then
        -- SC2 replay production tab: icons marching out from the anchored
        -- edge in either direction, wrapping onto a new line every Icons per
        -- Row so a long queue reads as a block instead of a banner across
        -- the screen, a slim progress bar under each
        local col = (index - 1) % m.perRow
        local line = math.floor((index - 1) / m.perRow)
        row:SetSize(m.iconSize, m.stripRowHeight)
        if m.layout == "ICONS_RTL" then
            row:SetPoint("TOPRIGHT", root, "TOPRIGHT", -col * m.stepX, -line * m.stepY)
        else
            row:SetPoint("TOPLEFT", root, "TOPLEFT", col * m.stepX, -line * m.stepY)
        end
        row.icon:SetSize(m.iconSize, m.iconSize)
        row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        row.barBG:SetSize(m.iconSize, ICON_BAR_HEIGHT)
        row.barBG:SetPoint("TOPLEFT", row.icon, "BOTTOMLEFT", 0, -2)
        row.bar:SetSize(1, ICON_BAR_HEIGHT)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.label:Hide()
        row.time:Hide()
        SetScaledFont(row.timer, m.iconSize * 0.42, 8, 16)
    else
        row:SetSize(m.rowWidth, m.rowHeight)
        if m.layout == "BARS_UP" then
            row:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, (index - 1) * (m.rowHeight + m.gap))
        else
            row:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -(index - 1) * (m.rowHeight + m.gap))
        end
        row.icon:SetSize(m.rowHeight, m.rowHeight)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.barBG:SetSize(m.barWidth, m.rowHeight)
        row.barBG:SetPoint("LEFT", row, "LEFT", m.rowHeight + ROW_ICON_GAP, 0)
        row.bar:SetSize(1, m.rowHeight)
        row.bar:SetPoint("LEFT", row.barBG, "LEFT", 0, 0)
        row.time:SetPoint("RIGHT", row.barBG, "RIGHT", -3, 0)
        row.label:SetPoint("LEFT", row.barBG, "LEFT", 3, 0)
        row.label:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
        local textSize = m.rowHeight - 2
        SetScaledFont(row.label, textSize, 8, 14)
        SetScaledFont(row.time, textSize, 8, 14)
        SetScaledFont(row.timer, m.rowHeight * 0.62, 8, 14)
        row.label:Show()
        row.time:Show()
    end
    row.geometrySig = m.sig
end

local function FormatRemaining(seconds)
    if seconds >= 60 then
        return string.format("%dm", math.ceil(seconds / 60))
    end
    return string.format("%ds", math.ceil(seconds))
end

-- Ready Callout banner: a top-center announcement in the queue's READY
-- green. Same generation-token pattern as Commander_Adjutant's banner (an
-- earlier banner's uncancellable hold callback must not start fading a
-- later one), parked 40px below Adjutant's slot so the two never overlap.
local BANNER_HOLD = 3.0
local BANNER_FADE_STEP = 0.06

local banner = CreateFrame("Frame", "CommanderProductionBanner", UIParent)
banner:SetSize(600, 30)
banner:SetPoint("TOP", UIParent, "TOP", 0, -180)
banner:SetFrameStrata("HIGH")
banner:Hide()

local bannerText = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bannerText:SetPoint("CENTER")
bannerText:SetTextColor(0.3, 1, 0.4)

local bannerTicker
local bannerGeneration = 0

local function StopBannerFade()
    if bannerTicker then
        bannerTicker:Cancel()
        bannerTicker = nil
    end
end

local function ShowReadyBanner(text)
    StopBannerFade()
    bannerGeneration = bannerGeneration + 1
    local generation = bannerGeneration
    bannerText:SetText(text)
    banner:SetAlpha(1)
    banner:Show()
    C_Timer.After(BANNER_HOLD, function()
        if generation ~= bannerGeneration then return end
        StopBannerFade()
        bannerTicker = C_Timer.NewTicker(0.05, function()
            local alpha = banner:GetAlpha() - BANNER_FADE_STEP
            if alpha <= 0 then
                banner:Hide()
                banner:SetAlpha(1)
                StopBannerFade()
            else
                banner:SetAlpha(alpha)
            end
        end)
    end)
end

-- Every kit here is already in service elsewhere in the suite, so all are
-- known-good on this client
local READY_SOUNDS = {
    CLICK = SOUNDKIT.IG_CHARACTER_INFO_TAB,
    READY_CHECK = SOUNDKIT.READY_CHECK,
    QUEST = SOUNDKIT.IG_QUEST_LIST_COMPLETE,
    WARNING = SOUNDKIT.RAID_WARNING,
}

local function ReadyAlert(name)
    if not CommanderProductionDB.ReadyAlert then return end
    local callout = CommanderProductionDB.ReadyCallout or "CHAT"
    if callout == "CHAT" or callout == "BOTH" then
        print(string.format("Commander Production: %s ready", name))
    end
    if callout == "BANNER" or callout == "BOTH" then
        ShowReadyBanner(string.format("%s ready", name))
    end
    local sound = READY_SOUNDS[CommanderProductionDB.ReadySound or "CLICK"]
    if sound then
        PlaySound(sound, "Master")
    end
end

-- Settings-panel previews: picking a sound or a banner callout plays the
-- result immediately instead of costing a 30-second test cooldown
function CommanderProduction_PreviewReadySound(value)
    local sound = READY_SOUNDS[value]
    if sound then
        PlaySound(sound, "Master")
    end
end

function CommanderProduction_PreviewReadyBanner()
    ShowReadyBanner("Production ready")
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
                            lockout = IsLockoutCooldown(start, duration),
                        }
                    else
                        entry.start, entry.duration = start, duration
                        -- Re-tested every refresh: a real cast starts a
                        -- cooldown of its own and clears the flag
                        entry.lockout = IsLockoutCooldown(start, duration)
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
            if entry.lockout then
                -- The school is back, which is not news the queue should
                -- hold onto (nor announce a dozen times over)
                active[name] = nil
            else
                if CommanderProductionDB.LingerReady then
                    entry.readyAt = now
                else
                    active[name] = nil
                end
                ReadyAlert(name)
            end
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
    local readyHold, readyFade = LingerWindow()
    wipe(queue)
    for name, entry in pairs(active) do
        if entry.readyAt then
            -- Lingering READY entry: hold, fade, then gone
            local lingering = now - entry.readyAt
            if lingering > (readyHold + readyFade) or not CommanderProductionDB.LingerReady then
                active[name] = nil
            else
                local alpha = 1
                if lingering > readyHold then
                    alpha = 1 - (lingering - readyHold) / readyFade
                end
                local it = NextQueueItem()
                it.name, it.entry, it.ready, it.alpha = name, entry, true, alpha
            end
        else
            local remaining = entry.start + entry.duration - now
            if remaining <= 0 then
                if entry.lockout then
                    -- Lockout over: drop it, no linger, no alert
                    active[name] = nil
                elseif CommanderProductionDB.LingerReady then
                    entry.readyAt = now
                    local it = NextQueueItem()
                    it.name, it.entry, it.ready, it.alpha = name, entry, true, 1
                    ReadyAlert(name)
                else
                    active[name] = nil
                    ReadyAlert(name)
                end
            else
                local it = NextQueueItem()
                it.name, it.entry, it.remaining = name, entry, remaining
            end
        end
    end
    table.sort(queue, QueueCompare)

    local maxBars = CommanderProductionDB.MaxBars or 5
    local shown = math.min(#queue, maxBars)
    local m = Metrics()
    local overlay = m.overlay
    for i = 1, shown do
        local row = AcquireRow(i)
        if row.geometrySig ~= m.sig then
            ApplyRowGeometry(row, i, m)
            -- Layout and size switches change which widgets carry the text —
            -- force the next content write through the dirty-check below
            row.shownName = nil
        end
        local item = queue[i]
        row.icon:SetTexture(item.entry.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- Suite icon recess (Commander_Events' shared art)
        if Commander.DebossIcon then
            Commander.DebossIcon(row.icon, CommanderProductionDB.IconRecess or "SOFT")
        end
        row.barBG:SetShown(m.showBar)
        row.bar:SetShown(m.showBar)
        if item.ready then
            -- READY straggler: full green bar, fading out on its clock.
            -- Text content is static per item (secs key -1) — only the
            -- first draw after a change pays the format
            row.bar:SetVertexColor(0.3, 1, 0.4, 0.9)
            if m.strip then
                row.bar:SetSize(m.iconSize, ICON_BAR_HEIGHT)
            else
                row.bar:SetSize(m.barWidth, m.rowHeight)
            end
            if row.shownName ~= item.name or row.shownSecs ~= -1 then
                row.shownName, row.shownSecs = item.name, -1
                if not m.strip then
                    row.label:SetText(item.name)
                    row.time:SetText("READY")
                    row.time:SetTextColor(0.3, 1, 0.4)
                end
                row.tipText = string.format("%s — ready", item.name)
            end
            row.sweepStart = nil
            row.sweep:Hide()
            row.timer:Hide()
            row:SetAlpha(item.alpha or 1)
        else
            -- Drain style: full at cooldown start, empty at ready
            local fill = item.remaining / item.entry.duration
            row.bar:SetVertexColor(0.35, 0.65, 1, 0.9)
            if m.strip then
                row.bar:SetSize(math.max(m.iconSize * fill, 1), ICON_BAR_HEIGHT)
            else
                row.bar:SetSize(math.max(m.barWidth * fill, 1), m.rowHeight)
            end
            -- Text changes once per second; the bar resizes every draw.
            -- Skip the format+SetText+tipText churn on unchanged seconds.
            local secs = math.ceil(item.remaining)
            if row.shownName ~= item.name or row.shownSecs ~= secs
                or row.shownOverlay ~= overlay then
                row.shownName, row.shownSecs, row.shownOverlay = item.name, secs, overlay
                if not m.strip then
                    row.label:SetText(item.name)
                    row.time:SetText(FormatRemaining(item.remaining))
                    row.time:SetTextColor(1, 1, 1)
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
    if m.strip then
        -- Only as wide as the longest line, only as tall as the lines used
        local columns = math.min(slots, m.perRow)
        local lines = math.ceil(slots / m.perRow)
        root:SetSize(columns * m.stepX - m.gap, lines * m.stepY - m.gap)
    else
        root:SetSize(m.rowWidth, slots * (m.rowHeight + m.gap))
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

-- Embedding. Commander_PartyFrames can carry this queue on its banner, in
-- the slot its own class cooldowns take (Party Frames → Header → Production
-- in Header). It reads the queue exactly as the last draw sorted it —
-- pending first with the soonest ready on top, READY stragglers after —
-- capped at Queue Length, and draws it in the banner's own grammar. The
-- standalone frame is untouched: the banner is a second view of the same
-- queue, not a new home for it. Returns nothing while the module is off, so
-- the banner can fall back to its class cooldowns rather than go blank.
--
-- Read-only by contract: every item is a pooled scratch table refilled in
-- place by Draw, so a consumer that writes to one is writing into the next
-- draw. `remaining` is as of the last draw; compute it from the entry's
-- start and duration for a live number.
function CommanderProduction_Queue()
    if not (CommanderProductionDB and CommanderProductionDB.EnableProduction) then return nil end
    return queue, math.min(#queue, CommanderProductionDB.MaxBars or 5)
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
-- Only for the interrupt stamp above: the cooldowns a kick creates are
-- indistinguishable from real ones without it
watcher:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

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
        playerGUID = UnitGUID("player")
        Commander.AddListener(COMMANDER_PRODUCTION_EVENTS.UPDATE, Apply)
        Apply()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not (CommanderProductionDB and CommanderProductionDB.EnableProduction) then return end
        local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if subevent == "SPELL_INTERRUPT"
            and destGUID == (playerGUID or UnitGUID("player")) then
            lockoutAt = GetTime()
        end
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

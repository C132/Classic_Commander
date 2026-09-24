-- Commander Vault: the guild bank.
--
-- Read-only, and passive by default. That is a deliberate limit rather than an
-- unfinished feature.
--
-- Reading a guild bank tab means calling QueryGuildBankTab(tab) and waiting
-- for the server to answer, and that call also moves which tab is SELECTED.
-- An addon that sweeps all six tabs whenever the frame opens yanks the view
-- out from under anybody who is trying to use it — the standard complaint
-- about every addon that has ever done this. So:
--
--   * whatever tab you open, the module quietly records. Zero disruption,
--     and browsing the guild bank normally fills the cache as a side effect.
--   * a full sweep exists, but only when you ask for it, and it puts the tab
--     you were looking at back when it is done.
--
-- Nothing here ever deposits or withdraws. A guild bank has withdrawal limits
-- and a log with your name on it; automating it is somebody else's module.

CommanderVault = CommanderVault or {}
local V = CommanderVault

local SLOTS_PER_TAB = 98
local SWEEP_INTERVAL = 0.6

local sweeping, sweepTab, sweepReturnTo

local function DB()
    return CommanderVaultDB or {}
end

local function CacheRoot()
    CommanderVaultCache = CommanderVaultCache or {}
    CommanderVaultCache.guilds = CommanderVaultCache.guilds or {}
    return CommanderVaultCache.guilds
end

function V.GuildKey()
    local name = GetGuildInfo and GetGuildInfo("player")
    if not name then return nil end
    local realm = GetRealmName() or "?"
    return realm .. "|guild|" .. name, name, realm
end

-- Guild records wear the same shape as character records on purpose: the
-- roster, the read-only browser and RecordSnapshot then need to know nothing
-- about guild banks at all.
function V.GuildRecord(create)
    local key, name, realm = V.GuildKey()
    if not key then return nil end
    local root = CacheRoot()
    local record = root[key]
    if not record and create then
        record = { name = name, realm = realm, isGuild = true, tabs = {}, items = {} }
        root[key] = record
    end
    return record, key
end

function V.AllGuildRecords()
    local list = {}
    for key, record in pairs(CacheRoot()) do
        if type(record) == "table" then
            record.key = key
            record.isGuild = true
            list[#list + 1] = record
        end
    end
    table.sort(list, function(a, b)
        if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) > (b.at or 0) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

function V.ForgetGuild(key)
    local root = CacheRoot()
    if root[key] then
        root[key] = nil
        V.InvalidateRoster()
        return true
    end
    return false
end

local function MaxSlots()
    return MAX_GUILDBANK_SLOTS_PER_TAB or SLOTS_PER_TAB
end

-- One tab, as the client currently has it. The link is the reliable identity
-- here: GetGuildBankItemInfo's tuple has moved between builds, but the link
-- has always been a link.
local function ReadTab(tab)
    local rows = {}
    if not GetGuildBankItemLink then return rows end
    for slot = 1, MaxSlots() do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local itemID = C_Item.GetItemInfoInstant(link)
            if itemID then
                local count = 1
                if GetGuildBankItemInfo then
                    local _, itemCount = GetGuildBankItemInfo(tab, slot)
                    count = itemCount or 1
                end
                rows[#rows + 1] = { id = itemID, n = count, l = link, b = tab, s = slot }
            end
        end
    end
    return rows
end

-- Records whichever tab the client currently has data for. Called off
-- GUILDBANKBAGSLOTS_CHANGED, which is the only moment the data is trustworthy.
function V.ScanGuildTab(tab)
    if DB().TrackGuildBank == false then return end
    tab = tab or (GetCurrentGuildBankTab and GetCurrentGuildBankTab())
    if not tab or tab < 1 then return end
    local record = V.GuildRecord(true)
    if not record then return end

    local name, icon, isViewable
    if GetGuildBankTabInfo then
        name, icon, isViewable = GetGuildBankTabInfo(tab)
    end
    -- A tab your rank cannot see reads as empty, which is not the same as
    -- being empty; recording that would be a lie the tooltip then repeats
    if isViewable == false then
        record.tabs[tab] = { name = name, icon = icon, viewable = false, items = {}, at = time() }
        V.RebuildGuildItems(record)
        return
    end

    record.tabs[tab] = {
        name = name, icon = icon, viewable = true,
        items = ReadTab(tab), at = time(),
    }
    record.tabCount = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or record.tabCount
    V.RebuildGuildItems(record)
end

-- The flat item list the rest of the module reads. Rebuilt from the per-tab
-- snapshots so a tab scanned an hour ago and one scanned just now can coexist
-- without either overwriting the other.
function V.RebuildGuildItems(record)
    local items, newest, scanned = {}, 0, 0
    for _, tab in pairs(record.tabs or {}) do
        if tab.viewable ~= false then
            scanned = scanned + 1
            for _, entry in ipairs(tab.items or {}) do
                items[#items + 1] = entry
            end
        end
        if (tab.at or 0) > newest then newest = tab.at end
    end
    record.items = items
    record.at = newest
    record.scannedTabs = scanned
    record.total = scanned * MaxSlots()
    record.free = math.max(record.total - #items, 0)
    V.InvalidateRoster()
end

-- ---------------------------------------------------------------------------
-- The full sweep
--
-- Opt-in, one tab per tick, and it puts the tab you were on back afterwards.
-- ---------------------------------------------------------------------------

function V.IsSweepingGuild()
    return sweeping ~= nil
end

local function StopSweep(message)
    if sweeping then
        sweeping:Cancel()
        sweeping = nil
    end
    if sweepReturnTo and QueryGuildBankTab then
        -- Put the view back where it was found
        QueryGuildBankTab(sweepReturnTo)
        sweepReturnTo = nil
    end
    if message then print("Commander Vault: " .. message) end
    if COMMANDER_VAULT_EVENTS then
        Commander.Notify(COMMANDER_VAULT_EVENTS.UPDATE)
    end
end

V.StopGuildSweep = StopSweep

function CommanderVault_SweepGuildBank()
    if sweeping then
        print("Commander Vault: already reading the guild bank")
        return false
    end
    if not (GuildBankFrame and GuildBankFrame:IsShown()) then
        print("Commander Vault: open the guild bank first")
        return false
    end
    local tabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    if tabs < 1 then
        print("Commander Vault: this guild bank has no tabs you can read")
        return false
    end
    sweepTab = 0
    sweepReturnTo = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 1
    sweeping = C_Timer.NewTicker(SWEEP_INTERVAL, function()
        if not (GuildBankFrame and GuildBankFrame:IsShown()) then
            StopSweep("guild bank closed — read what there was time for")
            return
        end
        sweepTab = sweepTab + 1
        if sweepTab > tabs then
            local record = V.GuildRecord(false)
            StopSweep(string.format("read %d guild bank %s",
                record and record.scannedTabs or 0,
                (record and record.scannedTabs) == 1 and "tab" or "tabs"))
            return
        end
        if QueryGuildBankTab then QueryGuildBankTab(sweepTab) end
    end)
    return true
end

-- ---------------------------------------------------------------------------
-- Counting
-- ---------------------------------------------------------------------------

-- How many of this item the guild bank holds, plus which tabs they are in.
-- Only ever from the cache: the API answers for one tab at a time and only
-- while the frame is open, so a live read is not a thing that exists.
function V.GuildCountFor(itemID)
    if DB().TrackGuildBank == false then return 0, nil end
    local total, record = 0, V.GuildRecord(false)
    if not record or not record.items then return 0, nil end
    for _, entry in ipairs(record.items) do
        if entry.id == itemID then total = total + (entry.n or 1) end
    end
    return total, record
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- Registered late and guarded: a client without guild banks (or with
        -- the events renamed) must not take the rest of the module down
        for _, name in ipairs({ "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
                               "GUILDBANKBAGSLOTS_CHANGED" }) do
            if not C_EventUtils or not C_EventUtils.IsEventValid
                or C_EventUtils.IsEventValid(name) then
                pcall(self.RegisterEvent, self, name)
            end
        end
        return
    end
    if DB().EnableVault == false then return end

    if event == "GUILDBANKBAGSLOTS_CHANGED" then
        -- The one moment the current tab's contents are trustworthy
        V.ScanGuildTab()
        if COMMANDER_VAULT_EVENTS then
            Commander.Notify(COMMANDER_VAULT_EVENTS.UPDATE)
        end
    elseif event == "GUILDBANKFRAME_CLOSED" then
        StopSweep()
    end
end)

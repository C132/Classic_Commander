-- Commander Spoils: loot pickups as supply acquisitions. Self-loot chat
-- messages are parsed for the item link; qualifying pickups raise a toast
-- (icon + quality-colored name) in a small stack under the top bar, rares
-- chime, epics flash the screen purple via the same WorldFrame vignette
-- technique as Commander Impact.

local MAX_TOASTS = 4
local TOAST_TIME = 3.5
local TOAST_WIDTH = 240
local TOAST_HEIGHT = 24

local QUALITY_BY_COLOR = {
    ["ff9d9d9d"] = 0, ["ffffffff"] = 1, ["ff1eff00"] = 2,
    ["ff0070dd"] = 3, ["ffa335ee"] = 4, ["ffff8000"] = 5,
}
local QUALITY_COLORS = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 },
    [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}
local QUALITY_NAMES = {
    [0] = "poor", [1] = "common", [2] = "uncommon",
    [3] = "rare", [4] = "epic", [5] = "legendary",
}

local tally = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }

-- ---------------------------------------------------------------------------
-- Toast stack
-- ---------------------------------------------------------------------------
local root = CreateFrame("Frame", "CommanderSpoilsToasts", UIParent)
root:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -60)
root:SetSize(TOAST_WIDTH, MAX_TOASTS * (TOAST_HEIGHT + 4))
root:SetFrameStrata("HIGH")

local toastFrames = {}
for i = 1, MAX_TOASTS do
    local toast = CreateFrame("Frame", nil, root)
    toast:SetSize(TOAST_WIDTH, TOAST_HEIGHT)
    toast:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -(i - 1) * (TOAST_HEIGHT + 4))

    toast.bg = toast:CreateTexture(nil, "BACKGROUND")
    toast.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    toast.bg:SetVertexColor(0, 0, 0, 0.55)
    toast.bg:SetAllPoints()

    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(TOAST_HEIGHT - 4, TOAST_HEIGHT - 4)
    toast.icon:SetPoint("LEFT", toast, "LEFT", 2, 0)

    toast.label = toast:CreateFontString(nil, "OVERLAY")
    toast.label:SetFontObject(GameFontHighlightSmall)
    toast.label:SetPoint("LEFT", toast.icon, "RIGHT", 6, 0)
    toast.label:SetPoint("RIGHT", toast, "RIGHT", -4, 0)
    toast.label:SetJustifyH("LEFT")

    toast:Hide()
    toastFrames[i] = toast
end

local activeToasts = {}   -- newest first: { text, icon, r, g, b, expires }

local function RedrawToasts()
    local now = GetTime()
    -- Drop expired entries (newest-first order preserved)
    for i = #activeToasts, 1, -1 do
        if activeToasts[i].expires <= now then
            table.remove(activeToasts, i)
        end
    end
    for i = 1, MAX_TOASTS do
        local toast = toastFrames[i]
        local entry = activeToasts[i]
        if entry then
            toast.icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            toast.label:SetText(entry.text)
            toast.label:SetTextColor(entry.r, entry.g, entry.b)
            toast:Show()
        else
            toast:Hide()
        end
    end
end

local function PushToast(text, icon, quality)
    local color = QUALITY_COLORS[quality] or QUALITY_COLORS[1]
    table.insert(activeToasts, 1, {
        text = text, icon = icon,
        r = color[1], g = color[2], b = color[3],
        expires = GetTime() + TOAST_TIME,
    })
    while #activeToasts > MAX_TOASTS do
        table.remove(activeToasts)
    end
    RedrawToasts()
    C_Timer.After(TOAST_TIME + 0.1, RedrawToasts)
end

-- ---------------------------------------------------------------------------
-- Epic flash (Impact's vignette technique)
-- ---------------------------------------------------------------------------
local pulse = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
pulse:SetTexture("Interface\\FullScreenTextures\\LowHealth")
pulse:SetAllPoints(WorldFrame)
pulse:SetBlendMode("ADD")
pulse:SetAlpha(0)

local pulseDriver = CreateFrame("Frame")
local pulseAlpha = 0
local function OnDecay(self, elapsed)
    pulseAlpha = pulseAlpha - elapsed * 0.8
    if pulseAlpha <= 0 then
        pulseAlpha = 0
        pulse:SetAlpha(0)
        pulseDriver:SetScript("OnUpdate", nil)
        return
    end
    pulse:SetAlpha(pulseAlpha)
end

local function EpicPulse()
    pulse:SetVertexColor(0.64, 0.21, 0.93)
    pulseAlpha = 0.45
    pulse:SetAlpha(pulseAlpha)
    pulseDriver:SetScript("OnUpdate", OnDecay)
end

-- ---------------------------------------------------------------------------
-- Loot handling
-- ---------------------------------------------------------------------------
local function IsOn()
    return CommanderSpoilsDB and CommanderSpoilsDB.EnableSpoils
end

local function OnLoot(message)
    if type(message) ~= "string" then return end
    if not (message:find("You receive loot") or message:find("You receive item")) then return end
    local color, itemID, itemName = message:match("|c(%x%x%x%x%x%x%x%x)|Hitem:(%d+)[^|]*|h%[([^%]]+)%]")
    if not itemName then return end
    local quality = QUALITY_BY_COLOR[color:lower()] or 1
    tally[quality] = (tally[quality] or 0) + 1

    if quality < (CommanderSpoilsDB.MinQuality or 2) then return end
    local icon
    if C_Item and C_Item.GetItemInfo then
        icon = select(10, C_Item.GetItemInfo(tonumber(itemID)))
    end
    PushToast(string.format("SUPPLY ACQUIRED: %s", itemName), icon, quality)
    if quality >= 3 and CommanderSpoilsDB.SpoilsSound then
        PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE, "Master")
    end
    if quality >= 4 and CommanderSpoilsDB.EpicFlash then
        EpicPulse()
    end
end

function CommanderSpoils_Report()
    local total = 0
    for _, count in pairs(tally) do
        total = total + count
    end
    if total == 0 then
        print("Commander Spoils: no supplies acquired this session yet")
        return
    end
    local parts = {}
    for quality = 5, 0, -1 do
        if tally[quality] and tally[quality] > 0 then
            parts[#parts + 1] = string.format("%d %s", tally[quality], QUALITY_NAMES[quality])
        end
    end
    print(string.format("Commander Spoils: %d item%s this session — %s",
        total, total == 1 and "" or "s", table.concat(parts, ", ")))
end

function CommanderSpoils_Test()
    if not IsOn() then
        print("Commander Spoils: module is disabled (enable it in settings or /cspoils)")
        return
    end
    PushToast("SUPPLY ACQUIRED: Test of the Quartermaster", nil, 4)
    if CommanderSpoilsDB.EpicFlash then
        EpicPulse()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_LOOT")
events:SetScript("OnEvent", function(self, event, message)
    if IsOn() then
        OnLoot(message)
    end
end)

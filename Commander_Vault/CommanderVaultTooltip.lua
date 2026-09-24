-- Commander Vault: the tooltip line.
--
-- The single highest-leverage thing the module does, and it is three lines of
-- text: hovering ANY item anywhere in the game — a bag slot, an auction row, a
-- link in chat, a vendor's stock, a quest reward — says how many you already
-- have, where they are, and which alt is holding the rest.
--
-- The whole "do I already own this" question, answered before you buy it.
--
-- Hooked with GameTooltip:HookScript("OnTooltipSetItem"), which is the same
-- hook Commander_Tooltip has used in production on this client since 2.1.0.
-- The newer TooltipDataProcessor path is preferred where the client offers it,
-- because on those clients OnTooltipSetItem fires before the data is settled.

CommanderVault = CommanderVault or {}
local V = CommanderVault

local VAULT_COLOR = { 0.55, 0.78, 1 }
local BAGS_COLOR = { 0.62, 0.85, 0.62 }
local ALTS_COLOR = { 0.78, 0.72, 0.95 }
local GUILD_COLOR = { 0.25, 0.85, 0.55 }
local MAX_NAMED_ALTS = 4

local hooked = false

local function DB()
    return CommanderVaultDB or {}
end

local function ClassColor(class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then return color.r, color.g, color.b end
    return 0.8, 0.8, 0.85
end

-- OnTooltipSetItem fires more than once for a single hover on this client (a
-- re-Set, a refresh while the item finishes loading), so the lines are stamped
-- with the link they were written for and skipped on a repeat. The stamp is
-- cleared when the tooltip is cleared or hidden, which is what lets the NEXT
-- item get its lines.
local function AlreadyStamped(tooltip, link)
    if tooltip.commanderVaultStamp == link then return true end
    tooltip.commanderVaultStamp = link
    return false
end

local function ClearStamp(tooltip)
    tooltip.commanderVaultStamp = nil
end

local function AddCounts(tooltip)
    local mode = DB().TooltipCounts or "ALL"
    if mode == "OFF" then return end
    -- The vault's own item buttons write a tighter version of these lines
    -- themselves, in one block and in an order they chose. This hook fires
    -- from inside their SetBagItem call, so without the flag the two sets of
    -- counts interleave into the middle of the item text.
    if V.suppressTooltipCounts then return end
    if not tooltip or not tooltip.GetItem then return end

    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not ok or not link then return end
    if AlreadyStamped(tooltip, link) then return end

    local itemID = C_Item.GetItemInfoInstant(link)
    if not itemID then return end

    local carried, vault, others, where, guild = V.CountsFor(itemID)
    if carried == 0 and vault == 0 and others == 0 and guild == 0 then return end

    local wroteHeader = false
    local function Header()
        if wroteHeader then return end
        wroteHeader = true
        tooltip:AddLine(" ")
    end

    if vault > 0 then
        Header()
        tooltip:AddDoubleLine("Vault", tostring(vault),
            VAULT_COLOR[1], VAULT_COLOR[2], VAULT_COLOR[3],
            VAULT_COLOR[1], VAULT_COLOR[2], VAULT_COLOR[3])
    end
    -- What you are carrying is the one number the client half-answers already
    -- (the stack count under the icon), so it is opt-in rather than default
    if carried > 0 and DB().TooltipCarried then
        Header()
        tooltip:AddDoubleLine("Bags", tostring(carried),
            BAGS_COLOR[1], BAGS_COLOR[2], BAGS_COLOR[3],
            BAGS_COLOR[1], BAGS_COLOR[2], BAGS_COLOR[3])
    end

    if mode == "ALL" and guild > 0 then
        Header()
        tooltip:AddDoubleLine("Guild bank", tostring(guild),
            GUILD_COLOR[1], GUILD_COLOR[2], GUILD_COLOR[3],
            GUILD_COLOR[1], GUILD_COLOR[2], GUILD_COLOR[3])
    end

    if mode == "ALL" and others > 0 then
        Header()
        tooltip:AddDoubleLine("Alts", tostring(others),
            ALTS_COLOR[1], ALTS_COLOR[2], ALTS_COLOR[3],
            ALTS_COLOR[1], ALTS_COLOR[2], ALTS_COLOR[3])
        for index = 1, math.min(#where, MAX_NAMED_ALTS) do
            local entry = where[index]
            local r, g, b = ClassColor(entry.class)
            tooltip:AddDoubleLine("   " .. (entry.name or "?"), tostring(entry.count),
                r, g, b, r, g, b)
        end
        if #where > MAX_NAMED_ALTS then
            tooltip:AddLine(string.format("   …and %d more", #where - MAX_NAMED_ALTS),
                0.5, 0.5, 0.55)
        end
    end

    if wroteHeader then
        tooltip:Show()
    end
end

V.AddTooltipCounts = AddCounts

-- Every tooltip an item can land in. ShoppingTooltips are the vendor and
-- auction comparison panes; ItemRefTooltip is what a chat link opens.
local function TooltipList()
    local list = {}
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1",
                            "ShoppingTooltip2", "ShoppingTooltip3" }) do
        local tooltip = _G[name]
        if tooltip and tooltip.HookScript then list[#list + 1] = tooltip end
    end
    return list
end

function V.HookTooltips()
    if hooked then return end
    hooked = true

    -- Preferred where it exists: on clients that ship the tooltip data
    -- pipeline, OnTooltipSetItem runs before the data is settled and a post
    -- call is the only hook that sees a finished tooltip.
    local processor = _G.TooltipDataProcessor
    local dataType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
    if processor and processor.AddTooltipPostCall and dataType then
        processor.AddTooltipPostCall(dataType, function(tooltip)
            AddCounts(tooltip)
        end)
    else
        for _, tooltip in ipairs(TooltipList()) do
            tooltip:HookScript("OnTooltipSetItem", AddCounts)
        end
    end

    -- The stamp has to be dropped whichever way the tooltip is torn down, or
    -- the next item to reuse the frame inherits the last one's silence
    for _, tooltip in ipairs(TooltipList()) do
        tooltip:HookScript("OnTooltipCleared", ClearStamp)
        tooltip:HookScript("OnHide", ClearStamp)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    if DB().EnableVault == false then return end
    V.HookTooltips()
end)

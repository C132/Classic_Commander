-- Commander Muster — ratings on Blizzard's own lists (D13).
--
-- Three of Blizzard's windows list players by name. Each gets the lightest
-- touch that still shows their ratings:
--   * the friends list: the ratings lead the line under each friend's name
--   * the guild roster: hovering a member shows them in a tooltip
--   * the group finder: hovering a listing shows every member's ratings
--     beneath Blizzard's own listing tooltip
-- Every number comes from CommanderMuster.RatingsLine, so these lists show
-- what Muster has seen merged with the web feed (D11), with the feed's age.
-- Nothing here writes to a secure frame. The hooks only read Blizzard's
-- state, add text and own a GameTooltip.

local M = CommanderMuster

local DIM = "|cff9d9d9d"
local LABEL_R, LABEL_G, LABEL_B = 1, 0.82, 0

local function On()
    local db = CommanderMusterDB
    return type(db) == "table" and db.EnableMuster and db.RatingsOnLists
end

local function ClassColored(name, classToken)
    local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if color then
        return string.format("|cff%02x%02x%02x%s|r", math.floor(color.r * 255 + 0.5),
            math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5), name)
    end
    return name
end

local function HideIfOwner(owner)
    if GameTooltip:GetOwner() == owner then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Friends list
-- ---------------------------------------------------------------------------

-- Blizzard rewrites the info line on every update, so the ratings are put in
-- front of it again each time, never doubled
local function OnFriendButton(button)
    if not On() or type(button) ~= "table" or not button.info then return end
    if button.buttonType ~= FRIENDS_BUTTON_TYPE_WOW then return end
    if not (C_FriendList and C_FriendList.GetFriendInfoByIndex) then return end
    local ok, info = pcall(C_FriendList.GetFriendInfoByIndex, button.id)
    if not ok or type(info) ~= "table" or not info.name then return end
    local line = M.RatingsLine(info.name)
    if not line then return end
    local text = button.info:GetText()
    if text and text ~= "" then
        button.info:SetText(line .. DIM .. "  ·  |r" .. text)
    else
        button.info:SetText(line)
    end
end

-- ---------------------------------------------------------------------------
-- Guild roster
-- ---------------------------------------------------------------------------

local GUILD_ROW_PREFIXES = { "GuildFrameButton", "GuildFrameGuildStatusButton" }

local function OnGuildRowEnter(row)
    if not On() or not row.guildIndex or type(GetGuildRosterInfo) ~= "function" then return end
    local fullName, _, _, _, _, _, _, _, _, _, classToken = GetGuildRosterInfo(row.guildIndex)
    local line = fullName and M.RatingsLine(fullName)
    if not line then return end
    local shown = Ambiguate and Ambiguate(fullName, "guild") or fullName
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(ClassColored(shown, classToken), 1, 1, 1)
    GameTooltip:AddDoubleLine("Arena", line, LABEL_R, LABEL_G, LABEL_B, 1, 1, 1)
    GameTooltip:Show()
end

local function HookGuildRows()
    for i = 1, 30 do
        for _, prefix in ipairs(GUILD_ROW_PREFIXES) do
            local row = _G[prefix .. i]
            if row and row.HookScript and not row.__musterRatings then
                row.__musterRatings = true
                row:HookScript("OnEnter", OnGuildRowEnter)
                row:HookScript("OnLeave", HideIfOwner)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Group finder
-- ---------------------------------------------------------------------------

-- Every member's ratings, under Blizzard's listing tooltip. The listing's own
-- leaderPvpRatingInfo is shown too when the server fills it in: the API
-- documents it, and nothing yet shows that Anniversary sends it.
local function ShowListing(entry)
    if not On() or not entry.resultID or not C_LFGList then return end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, entry.resultID)
    if not ok or type(info) ~= "table" then return end

    local rows, known = {}, false
    for i = 1, math.max(info.numMembers or 1, 1) do
        local okMember, member = pcall(C_LFGList.GetSearchResultPlayerInfo, entry.resultID, i)
        if okMember and type(member) == "table" and member.name then
            local line = M.RatingsLine(member.name)
            if line then known = true end
            rows[#rows + 1] = { member.name, member.classFilename, line, member.isLeader }
        end
    end
    local listed = {}
    for _, rating in ipairs(type(info.leaderPvpRatingInfo) == "table" and info.leaderPvpRatingInfo or {}) do
        if type(rating) == "table" and (tonumber(rating.rating) or 0) > 0 then
            listed[#listed + 1] = (rating.activityName or "Rated") .. " " .. rating.rating
        end
    end
    -- A panel of "unknown"s says nothing (D8)
    if not known and #listed == 0 then
        HideIfOwner(entry)
        return
    end

    local anchor = entry
    if LFGBrowseSearchEntryTooltip and LFGBrowseSearchEntryTooltip:IsShown() then
        anchor = LFGBrowseSearchEntryTooltip
    end
    GameTooltip:SetOwner(entry, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    GameTooltip:SetText("Arena ratings", LABEL_R, LABEL_G, LABEL_B)
    for _, row in ipairs(rows) do
        local name = ClassColored(row[1], row[2]) .. (row[4] and (DIM .. " (leader)|r") or "")
        GameTooltip:AddDoubleLine(name, row[3] or (DIM .. "not known|r"), 1, 1, 1, 1, 1, 1)
    end
    if #listed > 0 then
        GameTooltip:AddLine(DIM .. "Listing: " .. table.concat(listed, ", ") .. "|r")
    end
    GameTooltip:Show()
end

-- Each row frame is hooked once, the first time Blizzard fills it in; a row
-- refreshed under the cursor refreshes the panel too
local function OnLFGEntryUpdate(entry)
    if type(entry) ~= "table" or not entry.HookScript then return end
    if not entry.__musterRatings then
        entry.__musterRatings = true
        entry:HookScript("OnEnter", ShowListing)
        entry:HookScript("OnLeave", HideIfOwner)
    end
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == entry then ShowListing(entry) end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

local hooked = {}

local function HookGlobal(name, fn)
    if hooked[name] or type(_G[name]) ~= "function" then return end
    hooked[name] = true
    hooksecurefunc(name, fn)
end

local function HookAll()
    HookGlobal("FriendsFrame_UpdateFriendButton", OnFriendButton)
    HookGuildRows()
    HookGlobal("LFGBrowseSearchEntry_Update", OnLFGEntryUpdate)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        HookAll()
    elseif addon == "Blizzard_GroupFinder_VanillaStyle" then
        HookGlobal("LFGBrowseSearchEntry_Update", OnLFGEntryUpdate)
    end
end)

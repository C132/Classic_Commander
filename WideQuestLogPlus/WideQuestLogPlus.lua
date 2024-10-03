-- Customize the appearance and behavior of the Quest Log window
UIPanelWindows["QuestLogFrame"] = {
    area = "override",
    pushable = 0,
    xoffset = -16,
    yoffset = 12,
    bottomClampOverride = 140 + 12,
    width = 724,
    height = 513,
    whileDead = 1
};

-- Function to customize the appearance and behavior of the wide Quest Log
local function WideQuestLogPlus()
    -- Widen the window
    QuestLogFrame:SetWidth(724)
    QuestLogFrame:SetHeight(513)

    -- Adjust quest log title text position
    QuestLogTitleText:ClearAllPoints()
    QuestLogTitleText:SetPoint("TOP", QuestLogFrame, "TOP", 0, -17)

    -- Relocate the quest detail frame
    QuestLogDetailScrollFrame:ClearAllPoints()
    QuestLogDetailScrollFrame:SetPoint("TOPLEFT", QuestLogListScrollFrame, "TOPRIGHT", 41, 0)
    QuestLogDetailScrollFrame:SetHeight(362)

    -- Relocate the "No Active Quests" text
    QuestLogNoQuestsText:ClearAllPoints()
    QuestLogNoQuestsText:SetPoint("TOP", QuestLogListScrollFrame, 0, -90)

    -- Expand the height of the quest list
    QuestLogListScrollFrame:SetHeight(362)

    -- Create additional rows for displaying quests
    local oldQuestsDisplayed = QUESTS_DISPLAYED
    QUESTS_DISPLAYED = QUESTS_DISPLAYED + 17

    -- Hook a script to update the quest titles and recommended levels
    QuestLogFrame:HookScript('OnUpdate', function(self)
        local numEntries, numQuests = GetNumQuestLogEntries()

        if (numEntries == 0) then
            return
        end

        local questIndex, questLogTitle, title, level, _, isHeader, questTextFormatted, questCheck
        for i = 1, _G.QUESTS_DISPLAYED, 1 do
            questIndex = i + FauxScrollFrame_GetOffset(QuestLogListScrollFrame)

            if (questIndex <= numEntries) then
                questLogTitle = _G["QuestLogTitle" .. i]
                questCheck = _G["QuestLogTitle" .. i .. "Check"]
                title, level, _, isHeader = GetQuestLogTitle(questIndex)

                if (not isHeader) then
                    -- Format the quest text with recommended level
                    questTextFormatted = format("  [%d] %s", level, title)
                    questLogTitle:SetText(questTextFormatted)
                    questCheck:SetPoint("LEFT", questLogTitle, "LEFT", questLogTitle.Text:GetStringWidth() + 15, 0)
                    questCheck:SetVertexColor(64 / 255, 224 / 255, 208 / 255)
                    questCheck:SetDrawLayer("ARTWORK")
                else
                    questCheck:Hide()
                end
            end
        end
    end)

    -- Add quest ID to quest text
    QuestLogFrame:HookScript('OnUpdate', function(self)
        local index = GetQuestLogSelection();
        local title, _, _, _, _, _, _, id = GetQuestLogTitle(index);
        if ( not title ) then
            title = "";
        else
            title = format("%s [%d]", title, id)
        end
        if ( IsCurrentQuestFailed() ) then
            title = format("%s - (%s)", title, _G.FAILED)
        end
        QuestLogQuestTitle:SetText(title);
    end)

    -- Create additional rows for displaying quests
    for i = oldQuestsDisplayed + 1, QUESTS_DISPLAYED do
        local button = CreateFrame("Button", "QuestLogTitle" .. i, QuestLogFrame, "QuestLogTitleButtonTemplate")
        button:SetID(i)
        button:Hide()
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", _G["QuestLogTitle" .. (i - 1)], "BOTTOMLEFT", 0, 1)
    end

    -- Handle background textures
    local regions = { QuestLogFrame:GetRegions() }
    local xOffsets = { Left = 3, Middle = 259, Right = 515 }
    local yOffsets = { Top = 0, Bot = -256 }
    local textures = {
        TopLeft = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopLeft",
        TopMiddle = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopMid",
        TopRight = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_TopRight",
        BotLeft = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotLeft",
        BotMiddle = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotMid",
        BotRight = "Interface\\AddOns\\WideQuestLogPlus\\img\\WQLP_BotRight"
    }

    local PATTERN = "^Interface\\QuestFrame\\UI%-QuestLog%-(([A-Z][a-z]+)([A-Z][a-z]+))$"
    for _, region in ipairs(regions) do
        if (region:IsObjectType("Texture")) then
            local texturefile = region:GetTextureFilePath()
            local which, yOfs, xOfs = texturefile:match(PATTERN)
            xOfs = xOfs and xOffsets[xOfs]
            yOfs = yOfs and yOffsets[yOfs]
            if (xOfs and yOfs and textures[which]) then
                -- Attempt to hide the original textures
                region:SetTexture(nil)
                region:SetAlpha(0)

                -- Create and configure a new texture region
                local newRegion = QuestLogFrame:CreateTexture(nil, "ARTWORK")
                newRegion:ClearAllPoints()
                newRegion:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", xOfs, yOfs)
                newRegion:SetWidth(256)
                newRegion:SetHeight(256)
                newRegion:SetTexture(textures[which])

                -- Remove the stored texture reference
                textures[which] = nil
            end
        end
    end

    -- Place the local textures
    for name, path in pairs(textures) do
        local yOfs, xOfs = name:match("^([A-Z][a-z]+)([A-Z][a-z]+)$");
        xOfs = xOfs and xOffsets[xOfs];
        yOfs = yOfs and yOffsets[yOfs];
        if (xOfs and yOfs) then
            local region = QuestLogFrame:CreateTexture(nil, "ARTWORK");
            region:ClearAllPoints();
            region:SetPoint("TOPLEFT", QuestLogFrame, "TOPLEFT", xOfs, yOfs);
            region:SetWidth(256);
            region:SetHeight(256);
            region:SetTexture(path);

	    -- Set the draw layer and sublevel for proper layering
            region:SetDrawLayer("ARTWORK", 2); -- Adjust the sublevel as needed to prevent the default UI textures from appearing in front of the new textures we're providing
        end
    end

    -- Handle empty quest log textures
    local topOfs = 0.37
    local topH = 256 * (1 - topOfs)

    local botCap = 0.83
    local botH = 128 * botCap

    local xSize = 256 + 64
    local ySize = topH + botH

    local nxSize = QuestLogDetailScrollFrame:GetWidth() + 26
    local nySize = QuestLogDetailScrollFrame:GetHeight() + 8

    local function relocateEmpty(t, w, h, x, y)
        local nx = x / xSize * nxSize - 10
        local ny = y / ySize * nySize + 8
        local nw = w / xSize * nxSize
        local nh = h / ySize * nySize

        t:SetWidth(nw)
        t:SetHeight(nh)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", QuestLogDetailScrollFrame, "TOPLEFT", nx, ny)
    end

    -- Loop through and handle empty quest log frame textures
    local txset = { EmptyQuestLogFrame:GetRegions() }
    for _, t in ipairs(txset) do
        if (t:IsObjectType("Texture")) then
            local p = t:GetTextureFilePath()
            if (type(p) == "string") then
                p = p:match("-([^-]+)$")
                if (p) then
                    if (p == "TopLeft") then
                        t:SetTexCoord(0, 1, topOfs, 1)
                        relocateEmpty(t, 256, topH, 0, 0)
                    elseif (p == "TopRight") then
                        t:SetTexCoord(0, 1, topOfs, 1)
                        relocateEmpty(t, 64, topH, 256, 0)
                    elseif (p == "BotLeft") then
                        t:SetTexCoord(0, 1, 0, botCap)
                        relocateEmpty(t, 256, botH, 0, -topH)
                    elseif (p == "BotRight") then
                        t:SetTexCoord(0, 1, 0, botCap)
                        relocateEmpty(t, 64, botH, 256, -topH)
                    else
                        t:Hide()  -- Hide textures that don't match expected patterns
                    end
                end
            end
        end
    end
end

-- Call the functions to customize the Quest Log appearance
WideQuestLogPlus()

CommanderBuffsDB = _G.CommanderBuffsDB or {}

local showBuffFrameCheckbox

COMMANDER_BUFFS_EVENTS = {
    UPDATE = "COMMANDER_BUFFS_UPDATE"
}

local DefaultSettings = {
    ShowBuffFrame = true,
    BuffScale = 1.0,
}

for key, value in pairs(DefaultSettings) do
    if CommanderBuffsDB[key] == nil then
        CommanderBuffsDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Buffs")
    for key, value in pairs(DefaultSettings) do
        CommanderBuffsDB[key] = value
    end
    Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CBUFF1 = "/cbuff"
    SlashCmdList["CBUFF"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Buffs Reset")
        else
            print("Usage: /cbuff [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Buffs"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Buffs Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Buffs options below.")

    showBuffFrameCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showBuffFrameCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showBuffFrameCheckbox.Text:SetText("Show Buff Frame")
    showBuffFrameCheckbox:SetChecked(CommanderBuffsDB.ShowBuffFrame)
    showBuffFrameCheckbox:SetScript("OnClick", function(self)
        CommanderBuffsDB.ShowBuffFrame = self:GetChecked()
        Notify(COMMANDER_BUFFS_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if showBuffFrameCheckbox then
        showBuffFrameCheckbox:SetChecked(CommanderBuffsDB.ShowBuffFrame)
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Buffs")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy() end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)

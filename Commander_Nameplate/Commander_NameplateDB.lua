CommanderNameplateDB = _G.CommanderNameplateDB or {}

COMMANDER_NAMEPLATE_EVENTS = {
    UPDATE = "COMMANDER_NAMEPLATE_UPDATE"
}

local DefaultSettings = {
}

for key, value in pairs(DefaultSettings) do
    if CommanderNameplateDB[key] == nil then
        CommanderNameplateDB[key] = value
    end
end


local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Nameplate")
    for key, value in pairs(DefaultSettings) do
        CommanderNameplateDB[key] = value
    end
    Notify(COMMANDER_NAMEPLATE_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CNP1 = "/cnp"
    SlashCmdList["CNP"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Nameplate Reset")
        else
            print("Usage: /cnp [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Nameplate"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Nameplate Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Nameplate options below.")
    
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        Reset()
        print("Commander Nameplate Reset")
    end)

    
    return panel
end

local function OnUpdate()

end

local function OnAwake()
    print("Commander Nameplate Awake")
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Nameplate")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_NAMEPLATE_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy()
    print("Commander Nameplate Destroy")
end

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
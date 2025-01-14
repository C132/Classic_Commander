CommanderCastingDB = _G.CommanderCastingDB or {}

local showFullscreenEffectCheckbox
local colorBySpellSchoolCheckbox

COMMANDER_CASTING_EVENTS = {
    UPDATE = "COMMANDER_CASTING_UPDATE"
}

local DefaultSettings = {
    ShowFullscreenEffect = true,
    ColorBySpellSchool = true
}

for key, value in pairs(DefaultSettings) do
    if CommanderCastingDB[key] == nil then
        CommanderCastingDB[key] = value
    end
end

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

local function Reset()
    print("Resetting Commander Casting")
    for key, value in pairs(DefaultSettings) do
        CommanderCastingDB[key] = value
    end
    Notify(COMMANDER_CASTING_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CCAST1 = "/ccast"
    SlashCmdList["CCAST"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
            print("Commander Casting Reset")
        else
            print("Usage: /ccast [reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Casting"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Casting Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Casting options below.")

    showFullscreenEffectCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    showFullscreenEffectCheckbox:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    showFullscreenEffectCheckbox.Text:SetText("Show Fullscreen Casting Effect")
    showFullscreenEffectCheckbox:SetChecked(CommanderCastingDB.ShowFullscreenEffect)
    showFullscreenEffectCheckbox:SetScript("OnClick", function(self)
        CommanderCastingDB.ShowFullscreenEffect = self:GetChecked()
        Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    end)

    colorBySpellSchoolCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    colorBySpellSchoolCheckbox:SetPoint("TOPLEFT", showFullscreenEffectCheckbox, "BOTTOMLEFT", 0, -8)
    colorBySpellSchoolCheckbox.Text:SetText("Color Effect by Spell School")
    colorBySpellSchoolCheckbox:SetChecked(CommanderCastingDB.ColorBySpellSchool)
    colorBySpellSchoolCheckbox:SetScript("OnClick", function(self)
        CommanderCastingDB.ColorBySpellSchool = self:GetChecked()
        Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    end)

    return panel
end

local function OnUpdate()
    if showFullscreenEffectCheckbox then
        showFullscreenEffectCheckbox:SetChecked(CommanderCastingDB.ShowFullscreenEffect)
    end
    if colorBySpellSchoolCheckbox then
        colorBySpellSchoolCheckbox:SetChecked(CommanderCastingDB.ColorBySpellSchool)
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(MainCategory, panel, "Commander Casting")
    local categoryID = category:GetID()
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(categoryID)
    AddListener(COMMANDER_CASTING_EVENTS.UPDATE, OnUpdate)
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


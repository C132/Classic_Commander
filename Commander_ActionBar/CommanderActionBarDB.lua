CommanderActionBarDB = _G.CommanderActionBarDB or {}

COMMANDER_ACTIONBAR_EVENTS = {
    UPDATE = "COMMANDER_ACTIONBAR_UPDATE"
}

local DefaultSettings = {
    locked = true,
    showBagButtons = true,
    position = {
        point = "CENTER",
        relativePoint = "CENTER", 
        xOfs = 0,
        yOfs = 0
    }
}

local function ApplyDefaultSettings()
    for key, value in pairs(DefaultSettings) do
        if CommanderActionBarDB[key] == nil then
            CommanderActionBarDB[key] = value
        end
    end
end

ApplyDefaultSettings()

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

-- Panel widgets kept at file scope so the UPDATE listener can re-sync them
-- after Reset or cross-addon changes to the DB
local lockCheckbox
local bagButtonsCheckbox

local function Reset()
    for key, value in pairs(DefaultSettings) do
        CommanderActionBarDB[key] = value
    end
    Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
end

local function InitializeSlashCommands(categoryID)
    SLASH_CAB1 = "/cab"
    SlashCmdList["CAB"] = function(msg)
        msg = msg:lower()
        if msg == "" then
            Settings.OpenToCategory(categoryID)
        elseif msg == "reset" then
            Reset()
        elseif msg == "lock" then
            CommanderActionBarDB.locked = true
            Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
            print("Commander Action Bar Locked")
        elseif msg == "unlock" then
            CommanderActionBarDB.locked = false
            Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
            print("Commander Action Bar Unlocked")
        else
            print("Usage: /cab [reset|lock|unlock]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Action Bar"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander Action Bar Settings")

    local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    description:SetText("Configure Commander Action Bar options below.")
    
    local resetButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetButton:SetSize(100, 22)
    resetButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        Reset()
    end)

    lockCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lockCheckbox:SetPoint("TOPLEFT", resetButton, "BOTTOMLEFT", 0, -8)
    lockCheckbox.Text:SetText("Lock Action Bars")
    lockCheckbox:SetChecked(CommanderActionBarDB.locked)
    lockCheckbox:SetScript("OnClick", function(self)
        CommanderActionBarDB.locked = self:GetChecked()
        Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    end)

    bagButtonsCheckbox = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    bagButtonsCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -8)
    bagButtonsCheckbox.Text:SetText("Show Bag Buttons")
    bagButtonsCheckbox:SetChecked(CommanderActionBarDB.showBagButtons)
    bagButtonsCheckbox:SetScript("OnClick", function(self)
        CommanderActionBarDB.showBagButtons = self:GetChecked()
        Commander.Notify(COMMANDER_ACTIONBAR_EVENTS.UPDATE)
    end)
    
    return panel
end

-- Set when a bag button update is skipped due to combat lockdown; applied on
-- PLAYER_REGEN_ENABLED
local pendingBagButtonUpdate = false

local function ApplyBagButtonVisibility()
    for i = 0, 3 do
        local bagButton = _G["CharacterBag" .. i .. "Slot"]
        if bagButton then
            bagButton:SetShown(CommanderActionBarDB.showBagButtons)
        end
    end
end

local function OnUpdate()
    -- CharacterBag0-3Slot are protected; SetShown on them during combat
    -- lockdown trips ADDON_ACTION_BLOCKED, so defer until combat ends
    if InCombatLockdown() then
        pendingBagButtonUpdate = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ApplyBagButtonVisibility()
    end
    -- Re-sync the panel widgets from the DB so Reset (and cross-addon writes,
    -- e.g. MyClassicAddon's mirror "Show Bag Buttons" toggle) show fresh values
    if lockCheckbox then
        lockCheckbox:SetChecked(CommanderActionBarDB.locked)
    end
    if bagButtonsCheckbox then
        bagButtonsCheckbox:SetChecked(CommanderActionBarDB.showBagButtons)
    end
end

local function OnAwake()
    local panel = CreateOptionsPanel()
    local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, panel, "Commander Action Bar")
    local categoryID = category:GetID()
    InitializeSlashCommands(categoryID)
    Commander.AddListener(COMMANDER_ACTIONBAR_EVENTS.UPDATE, OnUpdate)
end

local function OnDestroy()
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so re-apply defaults here
        if addonName == "Commander_ActionBar" then
            CommanderActionBarDB = CommanderActionBarDB or {}
            ApplyDefaultSettings()
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif event == "PLAYER_REGEN_ENABLED" then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingBagButtonUpdate then
            pendingBagButtonUpdate = false
            ApplyBagButtonVisibility()
        end
    elseif loaded then
        OnUpdate()
    end
end

frame:SetScript("OnEvent", OnEvent)

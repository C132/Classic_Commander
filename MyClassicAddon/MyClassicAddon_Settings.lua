-- MyClassicAddon settings panel: a quick-access page that mirrors options
-- owned by other Commander modules. Every widget reads from and writes to
-- the owning module's DB and fires the owning module's event, so both panels
-- always stay in sync. If an owner addon is disabled, its widget greys out.

local SettingsFrame = CreateFrame("Frame", "MyClassicAddonFrame", UIParent)
SettingsFrame.name = "My Classic Addon"
SettingsFrame:RegisterEvent("ADDON_LOADED")

local lastUI
local syncFunctions = {}

local function CreateTitle()
    local title = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("My Classic Addon Settings")
    lastUI = title
end

-- getDB returns the owning module's saved-variables table (or nil if that
-- addon is disabled / not yet loaded); key is the setting inside it.
local function DrawCheckBox(label, getDB, key, event)
    local checkbox = CreateFrame("CheckButton", nil, SettingsFrame, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", 0, -10)
    checkbox.Text:SetText(label)

    local function Sync()
        local db = getDB()
        if db then
            checkbox:Enable()
            checkbox:SetAlpha(1)
            checkbox:SetChecked(db[key] and true or false)
        else
            checkbox:SetChecked(false)
            checkbox:Disable()
            checkbox:SetAlpha(0.5)
        end
    end

    checkbox:SetScript("OnClick", function(self)
        local db = getDB()
        if db then
            db[key] = self:GetChecked() and true or false
            Commander.Notify(event)
        end
    end)

    table.insert(syncFunctions, Sync)
    Commander.AddListener(event, Sync)
    Sync()

    lastUI = checkbox
    return checkbox
end

local function DrawDropDown(label, getDB, key, options, event)
    local dropdown = CreateFrame("Frame", nil, SettingsFrame, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", -15, -10)

    local labelText = SettingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 20, 5)
    labelText:SetText(label)

    UIDropDownMenu_SetWidth(dropdown, 200)

    local function UpdateDropDownText(value)
        for _, option in ipairs(options) do
            if option.value == value then
                UIDropDownMenu_SetText(dropdown, option.text)
                return
            end
        end
        UIDropDownMenu_SetText(dropdown, "")
    end

    local function Sync()
        local db = getDB()
        if db then
            UIDropDownMenu_EnableDropDown(dropdown)
            dropdown:SetAlpha(1)
            UIDropDownMenu_SetSelectedValue(dropdown, db[key])
            UpdateDropDownText(db[key])
        else
            UIDropDownMenu_DisableDropDown(dropdown)
            dropdown:SetAlpha(0.5)
            UIDropDownMenu_SetText(dropdown, "")
        end
    end

    UIDropDownMenu_Initialize(dropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        for _, option in ipairs(options) do
            info.text = option.text
            info.value = option.value
            info.checked = (option.value == UIDropDownMenu_GetSelectedValue(dropdown))
            info.func = function(self)
                local db = getDB()
                if db then
                    UIDropDownMenu_SetSelectedValue(dropdown, self.value)
                    UpdateDropDownText(self.value)
                    db[key] = self.value
                    Commander.Notify(event)
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    table.insert(syncFunctions, Sync)
    Commander.AddListener(event, Sync)
    Sync()

    lastUI = dropdown
    return dropdown
end

local function CreateReloadButton()
    local reloadButton = CreateFrame("Button", nil, SettingsFrame, "UIPanelButtonTemplate")
    reloadButton:SetText("Reload")
    reloadButton:SetSize(100, 25)
    reloadButton:SetPoint("TOPLEFT", lastUI, "BOTTOMLEFT", 0, -20)
    reloadButton:SetScript("OnClick", ReloadUI)
    lastUI = reloadButton
end

local function GeneralSettings()
    CreateTitle()

    DrawCheckBox("Show Chat", function() return CommanderChatDB end, "ShowChatWindow", "COMMANDER_CHAT_UPDATE")
    DrawCheckBox("Show Five Second Rule", function() return CommanderResourceDB end, "ShowFiveSecondRule", "FIVE_SECOND_RULE_CHANGED")
    DrawCheckBox("Show Bag Buttons", function() return CommanderActionBarDB end, "showBagButtons", "COMMANDER_ACTIONBAR_UPDATE")
    DrawCheckBox("Fade Bags While Moving", function() return CommanderBagsDB end, "FadeBagsWhileMoving", "COMMANDER_BAGS_UPDATE")
    DrawCheckBox("Show Minimap Button", function() return CommanderMinimapDB end, "ShowMinimapButton", "COMMANDER_MINIMAP")

    DrawDropDown("XP Display Mode", function() return CommanderMinimapDB end, "XPDisplayMode", {
        {text = "Percentage", value = "PERCENTAGE"},
        {text = "Kills to Level", value = "KILLS_TO_LEVEL"}
    }, "COMMANDER_MINIMAP")

    CreateReloadButton()
end

SettingsFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyClassicAddon" then
        GeneralSettings()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Owner DBs may seed as late as PLAYER_LOGIN, so re-sync every widget each
-- time the panel is shown.
SettingsFrame:SetScript("OnShow", function()
    for _, sync in ipairs(syncFunctions) do
        sync()
    end
end)

local category = Settings.RegisterCanvasLayoutSubcategory(Commander.MainCategory, SettingsFrame, "My Classic Addon")

local function OpenSettings()
    Settings.OpenToCategory(category:GetID())
end

-- Add slash command
SLASH_MYCLASSICADDON1 = "/mca"
SlashCmdList["MYCLASSICADDON"] = function(msg)
    msg = msg:lower()
    if msg == "" or msg == "settings" then
        OpenSettings()
    else
        print("Usage: /mca [settings]")
        print("  /mca or /mca settings - Open MyClassicAddon settings")
    end
end

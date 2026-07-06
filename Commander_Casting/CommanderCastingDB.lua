CommanderCastingDB = _G.CommanderCastingDB or {}

COMMANDER_CASTING_EVENTS = {
    UPDATE = "COMMANDER_CASTING_UPDATE"
}

local TEXTURE_PATH = "Interface\\AddOns\\Commander_Casting\\Textures\\"
local TEXTURE_FILES = {
    "Glow1.png",
    "Glow2.png",
    "Glow3.png",
    "Glow4.png",
    "Glow5.png",
    "Glow6.png",
    "Glow7.png",
}

local DefaultSettings = {
    ShowFullscreenEffect = true,
    ColorBySpellSchool = true,
    EffectIntensity = 0.5,
    EffectTexture = TEXTURE_PATH .. TEXTURE_FILES[1]
}

local function ApplyDefaultSettings()
    for key, value in pairs(DefaultSettings) do
        if CommanderCastingDB[key] == nil then
            CommanderCastingDB[key] = value
        end
    end
end

ApplyDefaultSettings()

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
local loaded = false

local function Reset()
    for key, value in pairs(DefaultSettings) do
        CommanderCastingDB[key] = value
    end
    Commander.Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    print("Commander Casting: settings restored to defaults")
end

local function GetTextureDisplayName(filename)
    return filename:gsub("%.png$", "")
end

local function BuildTextureOptions()
    local options = {}
    for _, filename in ipairs(TEXTURE_FILES) do
        options[#options + 1] = {
            text = GetTextureDisplayName(filename),
            value = TEXTURE_PATH .. filename,
        }
    end
    return options
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Casting",
        title = "Casting",
        addonName = "Commander_Casting",
        description = "Adds a fullscreen glow that builds up around the edge of the screen while you cast, so you can track cast progress without watching a cast bar.",
        event = COMMANDER_CASTING_EVENTS.UPDATE,
        slash = { "/ccast" },
        slashHandlers = {
            reset = Reset,
        },
    })

    panel:AddSection("Fullscreen Effect")
    panel:AddCheckbox({
        label = "Show Fullscreen Casting Effect",
        tooltip = "Enable the glow effect while casting or channeling.",
        get = function() return CommanderCastingDB.ShowFullscreenEffect end,
        set = function(value) CommanderCastingDB.ShowFullscreenEffect = value end,
    })
    panel:AddCheckbox({
        label = "Color Effect by Spell School",
        tooltip = "Tint the glow to match the school of the spell being cast: blue for Frost, red for Fire, purple for Shadow, and so on.",
        get = function() return CommanderCastingDB.ColorBySpellSchool end,
        set = function(value) CommanderCastingDB.ColorBySpellSchool = value end,
        isEnabled = function() return CommanderCastingDB.ShowFullscreenEffect end,
    })
    panel:AddSlider({
        label = "Effect Intensity",
        tooltip = "Maximum brightness the glow reaches as the cast completes.",
        min = 0, max = 1, step = 0.05,
        format = function(value) return string.format("%d%%", value * 100 + 0.5) end,
        get = function() return CommanderCastingDB.EffectIntensity end,
        set = function(value) CommanderCastingDB.EffectIntensity = value end,
        isEnabled = function() return CommanderCastingDB.ShowFullscreenEffect end,
    })

    panel:AddSection("Effect Texture")
    local dropdown = panel:AddDropdown({
        label = "Glow Texture",
        tooltip = "The texture used for the fullscreen glow. The preview to the right shows the selected texture.",
        options = BuildTextureOptions(),
        width = 160,
        get = function() return CommanderCastingDB.EffectTexture end,
        set = function(value) CommanderCastingDB.EffectTexture = value end,
        isEnabled = function() return CommanderCastingDB.ShowFullscreenEffect end,
    })

    -- Live preview of the selected glow texture, anchored beside the dropdown
    local previewFrame = CreateFrame("Frame", nil, panel)
    previewFrame:SetSize(64, 64)
    previewFrame:SetPoint("LEFT", dropdown, "RIGHT", 24, 8)

    local previewBackground = previewFrame:CreateTexture(nil, "BACKGROUND")
    previewBackground:SetAllPoints()
    previewBackground:SetColorTexture(0, 0, 0, 0.6)

    local texturePreview = previewFrame:CreateTexture(nil, "ARTWORK")
    texturePreview:SetPoint("TOPLEFT", 2, -2)
    texturePreview:SetPoint("BOTTOMRIGHT", -2, 2)
    texturePreview:SetBlendMode("ADD")

    panel:_AddRefresher(function()
        texturePreview:SetTexture(CommanderCastingDB.EffectTexture)
        previewFrame:SetAlpha(CommanderCastingDB.ShowFullscreenEffect and 1 or 0.4)
    end)

    panel:Finalize({ onDefaults = Reset })
end

local function OnAwake()
    CreateOptionsPanel()
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" then
        -- SavedVariables replace the global table after the file runs, so re-apply defaults here
        if addonName == "Commander_Casting" then
            CommanderCastingDB = CommanderCastingDB or {}
            ApplyDefaultSettings()
        end
    elseif event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    end
end

frame:SetScript("OnEvent", OnEvent)

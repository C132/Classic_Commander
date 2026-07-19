CommanderPromotionDB = _G.CommanderPromotionDB or {}

COMMANDER_PROMOTION_EVENTS = {
    UPDATE = "COMMANDER_PROMOTION_UPDATE"
}

local DefaultSettings = {
    EnablePromotion = true,
    PromotionFlash = true,
    PromotionSound = true,
    StatReadout = true,
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderPromotionDB, DefaultSettings)
    Commander.Notify(COMMANDER_PROMOTION_EVENTS.UPDATE)
    print("Commander Promotion: settings restored to defaults")
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Promotion",
        title = "Promotion",
        addonName = "Commander_Promotion",
        description = "Levels are promotions, and promotions deserve a ceremony: a full-screen gold burst, a PROMOTION banner with your new rank, and the stat gains lined up underneath. Ten seconds of glory for hours of grind — as it should be.",
        event = COMMANDER_PROMOTION_EVENTS.UPDATE,
        slash = { "/cpromo" },
        slashHandlers = {
            test = function()
                if CommanderPromotion_Test then CommanderPromotion_Test() end
            end,
        },
    })

    panel:AddSection("Ceremony")
    panel:AddCheckbox({
        label = "Enable Promotion",
        tooltip = "Master switch for the whole module.",
        get = function() return CommanderPromotionDB.EnablePromotion end,
        set = function(value) CommanderPromotionDB.EnablePromotion = value end,
    })
    panel:AddCheckboxPair({
        label = "Gold Burst",
        tooltip = "Full-screen gold flash at the moment of promotion.",
        get = function() return CommanderPromotionDB.PromotionFlash end,
        set = function(value) CommanderPromotionDB.PromotionFlash = value end,
        isEnabled = function() return CommanderPromotionDB.EnablePromotion end,
    }, {
        label = "Ceremony Sound",
        tooltip = "Play a fanfare chime with the banner.",
        get = function() return CommanderPromotionDB.PromotionSound end,
        set = function(value) CommanderPromotionDB.PromotionSound = value end,
        isEnabled = function() return CommanderPromotionDB.EnablePromotion end,
    })
    panel:AddCheckbox({
        label = "Stat Readout",
        tooltip = "Show the attribute and resource gains under the banner.",
        get = function() return CommanderPromotionDB.StatReadout end,
        set = function(value) CommanderPromotionDB.StatReadout = value end,
        isEnabled = function() return CommanderPromotionDB.EnablePromotion end,
    })
    panel:AddButtonRow({
        {
            label = "Test Ceremony",
            width = 130,
            tooltip = "Preview the promotion ceremony (also: /cpromo test).",
            onClick = function()
                if CommanderPromotion_Test then CommanderPromotion_Test() end
            end,
        },
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Promotion" then
        Commander.UI.ApplyDefaults(CommanderPromotionDB, DefaultSettings)
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

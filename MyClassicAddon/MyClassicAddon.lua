local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

local function InitializeAddon()
    SLASH_MYCLASSICADDON1 = "/mca"
    SlashCmdList["MYCLASSICADDON"] = OpenSettings

    -- Enable Auto Loot
    local autoLootCVar = "autoLootDefault"
    if GetCVar(autoLootCVar) ~= "1" then
        SetCVar(autoLootCVar, "1")
        print("Auto Loot " .. (GetCVar(autoLootCVar) == "1" and "enabled" or "failed to enable"))
    end

    -- Display Auto Loot toggle key
    local autoLootKey = GetBindingKey("AUTOLOOTTOGGLE")
    print(autoLootKey and "Toggle Auto Loot: " .. autoLootKey or "Auto Loot toggle key not bound")

    -- Update UI and show action bar
    if MainMenuBar and MainMenuBar.UpdateMultiBarButtons then
        MainMenuBar:UpdateMultiBarButtons()
    end

    if MultiBarBottomLeft then
        MultiBarBottomLeft:Show()
        for i = 1, 12 do
            local button = _G["MultiBarBottomLeftButton"..i]
            if button then button:Show() end
        end
    end

    -- Ensure bar visibility after delay
    C_Timer.After(1, function()
        if MultiBarBottomLeft and not MultiBarBottomLeft:IsShown() then
            MultiBarBottomLeft:Show()
            print("Action Bar 2 visibility enforced after delay")
        end
    end)
end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InitializeAddon()
    end
end)
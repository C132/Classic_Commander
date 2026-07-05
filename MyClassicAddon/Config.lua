-- MyClassicAddon saved variables.
-- Data lives in MyClassicAddonDB; the legacy "Config" saved variable is
-- migrated into it once and kept declared for one release. The global alias
-- Config points at MyClassicAddonDB so any remaining Config.* reads/writes
-- persist to the new name.

local defaults = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("ADDON_LOADED")

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "MyClassicAddon" then
        MyClassicAddonDB = MyClassicAddonDB or {}

        if not MyClassicAddonDB._migratedFromConfig then
            if type(Config) == "table" then
                for key, value in pairs(Config) do
                    if key ~= "callbacks" and key ~= "cachedOutputs" and MyClassicAddonDB[key] == nil then
                        MyClassicAddonDB[key] = value
                    end
                end
            end
            MyClassicAddonDB._migratedFromConfig = true
        end

        for key, value in pairs(defaults) do
            if MyClassicAddonDB[key] == nil then
                MyClassicAddonDB[key] = value
            end
        end

        Config = MyClassicAddonDB

        self:UnregisterEvent("ADDON_LOADED")
    end
end)

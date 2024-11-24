Template = Template or {}
Template.listeners = {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

function AddListener(func)
    if type(func) ~= "function" then
        return
    end
    table.insert(Template.listeners, func)
end

function RemoveListener(func)
    if type(func) ~= "function" then
        return
    end
    Template.listeners = RemoveFromTable(Template.listeners, func)
end

function Notify()
    for _, func in ipairs(Template.listeners) do
        if type(func) == "function" then
            func()
        end
    end
end

local function OnAwake() end
local function OnDestroy() end
local function OnUpdate() end

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        OnUpdate()
    end
end)
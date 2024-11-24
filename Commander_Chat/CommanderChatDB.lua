CommanderChatDB = _G.CommanderChatDB or {}
CommanderChatDB.listeners = _G.CommanderChatDB.listeners or {}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
local loaded = false

function AddListener(func)
    print("Adding Chat Listener: " .. tostring(func))
    if type(func) ~= "function" then
        return
    end
    table.insert(CommanderChatDB.listeners, func)
end

function RemoveListener(func)
    if type(func) ~= "function" then
        return
    end
    CommanderChatDB.listeners = RemoveFromTable(CommanderChatDB.listeners, func)
end

function Notify()
    if not CommanderChatDB.listeners then
        CommanderChatDB.listeners = {}
        return
    end
    
    for _, func in ipairs(CommanderChatDB.listeners) do
        if type(func) == "function" then
            func()
        end
    end
end

function Reset()
    print("Resetting Commander Chat")
end

local function InitializeSlashCommands(catagory)
    SLASH_CI1 = "/cc"
    SlashCmdList["CC"] = function(msg)
        msg = msg:lower()
        if msg == "" or msg == "toggle" then
            Settings.OpenToCategory(catagory)
        elseif msg == "reset" then
            Reset()
        else
            print("Usage: /cc [toggle|reset]")
        end
    end
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander Chat"
    return panel
end

local function OnAwake() 
    local category = Settings.RegisterCanvasLayoutCategory(CreateOptionsPanel(), "Commander Chat")
    Settings.RegisterAddOnCategory(category)
    InitializeSlashCommands(category)
end
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
Commander = Commander or {}

local callbacks = {}

function Commander.AddListener(event, func)
    if not event then
        error("Event cannot be nil")
        return
    end

    if not func then
        error("Callback function cannot be nil")
        return
    end

    if not callbacks[event] then
        callbacks[event] = {}
    end

    for _, existing in ipairs(callbacks[event]) do
        if existing == func then
            return
        end
    end

    table.insert(callbacks[event], func)
end

function Commander.Notify(event, ...)
    if event and callbacks[event] then
        for _, func in ipairs(callbacks[event]) do
            local ok, err = pcall(func, ...)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end

-- Legacy aliases so existing call sites keep working
AddListener = Commander.AddListener
Notify = Commander.Notify

local function CreateMainPanel()
    local panel = CreateFrame("Frame")
    panel.name = "Commander"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Commander")

    return panel
end

Commander.MainPanel = CreateMainPanel()
Commander.MainCategory = Settings.RegisterCanvasLayoutCategory(Commander.MainPanel, "Commander")
Commander.MainCategoryID = Commander.MainCategory:GetID()
Settings.RegisterAddOnCategory(Commander.MainCategory)

-- Legacy aliases so existing call sites keep working
MainPanel = Commander.MainPanel
MainCategory = Commander.MainCategory
MainCategoryID = Commander.MainCategoryID

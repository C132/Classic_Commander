local function AnchorTooltipToMouse(tooltip)
    local scale = UIParent:GetEffectiveScale()
    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale
    tooltip:ClearAllPoints()
    tooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x + 20, y + 20)
end

local function OnTooltipSet(tooltip)
    AnchorTooltipToMouse(tooltip)
    -- Add custom information to tooltip (unit or item)
end

local function ErrorHandler(err)
    print("MyClassicAddon Tooltip Error: " .. tostring(err))
end

local function SafeHook(frame, script, func)
    frame:HookScript(script, function(...)
        local status, error = pcall(func, ...)
        if not status then
            ErrorHandler(error)
        end
    end)
end

local tooltips = {GameTooltip, ItemRefTooltip}
local scripts = {"OnTooltipSetUnit", "OnTooltipSetItem", "OnUpdate", "OnShow"}

for _, tooltip in ipairs(tooltips) do
    for _, script in ipairs(scripts) do
        SafeHook(tooltip, script, OnTooltipSet)
    end
end

local savedWorldFramePoints

local function CreateConsoleBackdrop()
    local backdrop = CreateFrame("Frame", "CAB_ConsoleBackdrop", UIParent)
    backdrop:SetFrameStrata("BACKGROUND")
    backdrop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    backdrop:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)

    local texture = backdrop:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(backdrop)  -- Set texture to fill the backdrop
    texture:SetTexture("Interface\\AddOns\\Commander_Console\\Textures\\Console3.png")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetAlpha(1)

    backdrop:Hide()  -- Hidden by default; ApplyConsoleState shows it when enabled

    return backdrop
end

local consoleBackdrop = CreateConsoleBackdrop()

local function SaveWorldFramePoints()
    if savedWorldFramePoints then
        return
    end
    savedWorldFramePoints = {}
    for i = 1, WorldFrame:GetNumPoints() do
        local point, relativeTo, relativePoint, xOfs, yOfs = WorldFrame:GetPoint(i)
        savedWorldFramePoints[i] = { point, relativeTo, relativePoint, xOfs, yOfs }
    end
end

local function RestoreWorldFramePoints()
    if not savedWorldFramePoints then
        return
    end
    WorldFrame:ClearAllPoints()
    if #savedWorldFramePoints > 0 then
        for _, point in ipairs(savedWorldFramePoints) do
            WorldFrame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
    else
        WorldFrame:SetPoint("TOPLEFT", 0, 0)
        WorldFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    end
end

local function ApplyConsoleState()
    if CommanderConsoleDB.ShowConsole then
        SaveWorldFramePoints()  -- Save the original anchors before adjusting the viewport
        consoleBackdrop:Show()
        WorldFrame:ClearAllPoints()
        WorldFrame:SetPoint("TOPLEFT", 0, 0)
        -- Leave room at the bottom of the screen for the console area
        WorldFrame:SetPoint("BOTTOMRIGHT", 0, CommanderConsoleDB.ConsoleHeight or 150)
    else
        consoleBackdrop:Hide()
        RestoreWorldFramePoints()
    end
end

local function ToggleConsoleBackdrop()
    CommanderConsoleDB.ShowConsole = not CommanderConsoleDB.ShowConsole
    Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
end

SLASH_TOGGLECONSOLE1 = "/toggleconsole"
SlashCmdList["TOGGLECONSOLE"] = ToggleConsoleBackdrop

local frame = CreateFrame("FRAME")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        ApplyConsoleState()
    end
end)

Commander.AddListener(COMMANDER_CONSOLE_EVENTS.UPDATE, ApplyConsoleState)

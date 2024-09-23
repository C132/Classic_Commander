local ActionBarOutput = {}
ActionBarOutput.__index = ActionBarOutput

function ActionBarOutput:New()
    local self = setmetatable({}, ActionBarOutput)
    self.outputTexts = {}
    self.cachedOutputs = GetCachedOutputs() or {}
    self.frame = CreateFrame("Frame")
    self.debugMode = false
    self.debugFrame = nil
    self.tooltipScanner = CreateFrame("GameTooltip", "ABOTooltipScanner", nil, "GameTooltipTemplate")
    self.tooltipScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    return self
end

function ActionBarOutput:UpdateOutput(button, text)
    if not button or not button.action then
        text:Hide()
        return
    end

    local actionType, id = GetActionInfo(button.action)
    if actionType == "spell" and id then
        local spellOutput = self.cachedOutputs[id]
        if spellOutput == nil then
            spellOutput = self:GetSpellOutput(id)
            self.cachedOutputs[id] = spellOutput
            self:UpdateConfigCachedOutputs()
        end
        
        if spellOutput and spellOutput > 0 then
            text:SetText(string.format("%.0f", spellOutput))
            text:Show()
        else
            text:Hide()
        end
    else
        text:Hide()
    end
end

function ActionBarOutput:GetSpellOutput(spellId)
    local spellName = GetSpellInfo(spellId)
    if not spellName then 
        return 0 
    end

    self.tooltipScanner:ClearLines()
    self.tooltipScanner:SetSpellByID(spellId)

    local patterns = {
        channeled = "(%d+) .+ each second for (%d+) sec",
        range = "(%d+) ?to ?(%d+)",
        single = "(%d+)",
        dot = ".+ (%d+) .+ over (%d+) sec",
        periodic = "(%d+) .+ every (%d+) sec for (%d+) sec"
    }

    local totalMinOutput, totalMaxOutput = 0, 0
    local debugInfo = self.debugMode and {} or nil
    local isChanneled = false
    local damageFound = false

    for i = 1, self.tooltipScanner:NumLines() do
        local text = _G["ABOTooltipScannerTextLeft" .. i]:GetText()
        if text then
            if debugInfo then table.insert(debugInfo, "Parsing line: " .. text) end

            if text:lower():find("damage") then
                damageFound = true
            end

            local function addOutput(min, max, debugText)
                totalMinOutput = totalMinOutput + min
                totalMaxOutput = totalMaxOutput + max
                if debugInfo then table.insert(debugInfo, debugText) end
            end

            local channeledOutput, channeledDuration = text:match(patterns.channeled)
            if channeledOutput and channeledDuration then
                local out = tonumber(channeledOutput) * math.floor(tonumber(channeledDuration))
                addOutput(out, out, "Channeled output found: " .. out .. " total, duration: " .. channeledDuration .. " sec")
                isChanneled = true
            elseif not isChanneled then
                local minOut, maxOut = text:match(patterns.range)
                if minOut and maxOut then
                    addOutput(tonumber(minOut), tonumber(maxOut), "Output range found: " .. minOut .. " to " .. maxOut)
                else
                    local output = text:match(patterns.single)
                    if output then
                        local out = tonumber(output)
                        if out and out ~= 0 and not text:match("Mana$") and not text:match("Rage$") and not text:match("Energy$") and not text:match(" sec$") and not text:match("sec cast") and not text:match("(%d+) sec") then
                            addOutput(out, out, "Single output found: " .. out)
                        end
                    end
                end

                local dotOutput, dotDuration = text:match(patterns.dot)
                if dotOutput and dotDuration then
                    local out = tonumber(dotOutput)
                    addOutput(out, out, "DoT output found: " .. out .. " over " .. dotDuration .. " sec")
                end

                local periodicOutput, interval, duration = text:match(patterns.periodic)
                if periodicOutput and interval and duration then
                    local out = tonumber(periodicOutput) * math.floor(tonumber(duration) / tonumber(interval))
                    addOutput(out, out, "Periodic output found: " .. out .. " total")
                end
            end
        end
    end

    local averageOutput = (totalMinOutput + totalMaxOutput) / 2
    if debugInfo then
        table.insert(debugInfo, "Total output for spell " .. spellName .. ": " .. averageOutput)
        self.debugInfo = debugInfo
    end
    return damageFound and averageOutput or 0
end

function ActionBarOutput:CreateOverlayText(button)
    local outputText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    outputText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    outputText:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    outputText:SetTextColor(1, 0.82, 0)
    outputText:SetDrawLayer("OVERLAY", 7)
    table.insert(self.outputTexts, outputText)
    return outputText
end

function ActionBarOutput:Initialize()
    for i = 1, 24 do
        local button = i <= 12 and _G["ActionButton" .. i] or _G["MultiBarBottomLeftButton" .. (i - 12)]
        if button then
            local outputText = self:CreateOverlayText(button)
            button.outputText = outputText
            button:HookScript("OnEnter", function()
                self:UpdateDebugWindow(button)
            end)
        end
    end
    self:SetupEventHandlers()
    self:RegisterSlashCommands()
    self:CreateDebugWindow()
end

function ActionBarOutput:SetupEventHandlers()
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    self.frame:RegisterEvent("PLAYER_DAMAGE_DONE_MODS")
    self.frame:RegisterEvent("SPELLS_CHANGED")
    
    self.frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_DAMAGE_DONE_MODS" then
            self.cachedOutputs = {}
            self:UpdateConfigCachedOutputs()
        end
        self:UpdateAllOutputs()
    end)
end

function ActionBarOutput:UpdateAllOutputs()
    for i, outputText in ipairs(self.outputTexts) do
        local button = i <= 12 and _G["ActionButton" .. i] or _G["MultiBarBottomLeftButton" .. (i - 12)]
        if button then
            self:UpdateOutput(button, outputText)
        else
            outputText:Hide()
        end
    end
end

function ActionBarOutput:GetCachedOutputs()
    return self.cachedOutputs
end

function ActionBarOutput:UpdateConfigCachedOutputs()
    Config.CachedOutputs = self.cachedOutputs
    UpdateCachedOutputs(self.cachedOutputs)
end

function ActionBarOutput:ClearCache()
    self.cachedOutputs = {}
    Config.CachedOutputs = {}
    UpdateCachedOutputs({})
    print("Action Bar Output cache cleared.")
    self:UpdateAllOutputs()
end

function ActionBarOutput:RegisterSlashCommands()
    SLASH_ACTIONBAROUTPUT1 = "/abo"
    SlashCmdList["ACTIONBAROUTPUT"] = function(msg)
        if msg == "debug" then
            self.debugMode = not self.debugMode
            print("Action Bar Output Debug Mode: " .. (self.debugMode and "Enabled" or "Disabled"))
            self.debugFrame:SetShown(self.debugMode)
        elseif msg == "clearcache" then
            self:ClearCache()
        end
    end
end

function ActionBarOutput:CreateDebugWindow()
    self.debugFrame = CreateFrame("Frame", "ABODebugFrame", UIParent, "BackdropTemplate")
    self.debugFrame:SetSize(300, 400)
    self.debugFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    self.debugFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    self.debugFrame:SetBackdropColor(0, 0, 0, 0.8)
    
    self.debugFrame.title = self.debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.debugFrame.title:SetPoint("TOPLEFT", 10, -10)
    self.debugFrame.title:SetText("Debug Info")
    
    self.debugFrame.content = self.debugFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    self.debugFrame.content:SetPoint("TOPLEFT", 10, -30)
    self.debugFrame.content:SetPoint("BOTTOMRIGHT", -10, 10)
    self.debugFrame.content:SetJustifyH("LEFT")
    self.debugFrame.content:SetJustifyV("TOP")
    
    self.debugFrame:Hide()
end

function ActionBarOutput:UpdateDebugWindow(button)
    if self.debugMode then
        local actionType, id = GetActionInfo(button.action)
        if actionType == "spell" and id then
            local spellName = GetSpellInfo(id)
            self:GetSpellOutput(id)
            
            local debugText = "Debug Info for " .. spellName .. "\n\n"
            for _, info in ipairs(self.debugInfo or {}) do
                debugText = debugText .. info .. "\n"
            end
            
            self.debugFrame.content:SetText(debugText)
            self.debugFrame:Show()
        end
    end
end

local actionBarOutput = ActionBarOutput:New()
actionBarOutput:Initialize()

-- Make sure the cached outputs are available globally
_G.ActionBarOutput = actionBarOutput

return actionBarOutput

local frame = CreateFrame("Frame")
local loaded = false

local function CreateFullScreenGlow()
    local glow = WorldFrame:CreateTexture(nil, "BACKGROUND", nil, -8)  -- -8 is the lowest drawable layer
    glow:SetTexture(CommanderCastingDB.EffectTexture)
    glow:SetAllPoints(WorldFrame)
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0)
    return glow
end

-- Spell school keyword tables (file scope so they aren't rebuilt every OnUpdate frame)
local frostKeywords = {"frost", "ice", "freeze", "blizzard", "frostbolt", "cone of cold"}
local holyKeywords = {"holy", "light", "heal", "smite", "flash", "prayer", "resurrection", "exorcism", "consecration"}
local fireKeywords = {"fire", "flame", "immolate", "scorch", "pyroblast", "blast wave", "flamestrike", "searing", "incinerate"}
local natureKeywords = {"nature", "lightning", "wrath", "bolt", "starfire", "hurricane", "tranquility", "healing", "touch"}
local shadowKeywords = {"shadow", "mind", "psychic", "flay", "blast", "mana burn", "devouring plague"}
local arcaneKeywords = {"arcane", "mana", "magic", "polymorph", "missiles", "explosion", "conjure", "evocation", "counterspell"}

-- Parse spell school from the spell name
local function getSpellSchool(spellName)
    spellName = string.lower(spellName)

    for _, keyword in ipairs(frostKeywords) do
        if string.find(spellName, keyword) then return "Frost" end
    end
    for _, keyword in ipairs(natureKeywords) do
        if string.find(spellName, keyword) then return "Nature" end
    end
    for _, keyword in ipairs(holyKeywords) do
        if string.find(spellName, keyword) then return "Holy" end
    end
    for _, keyword in ipairs(fireKeywords) do
        if string.find(spellName, keyword) then return "Fire" end
    end
    for _, keyword in ipairs(shadowKeywords) do
        if string.find(spellName, keyword) then return "Shadow" end
    end
    for _, keyword in ipairs(arcaneKeywords) do
        if string.find(spellName, keyword) then return "Arcane" end
    end

    return "Unknown"
end

local function UpdateCastingGlow(glow)
    -- Update texture if it changed in DB
    if glow:GetTexture() ~= CommanderCastingDB.EffectTexture then
        glow:SetTexture(CommanderCastingDB.EffectTexture)
    end

    local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible = UnitCastingInfo("player")
    if not name then
        name, text, texture, startTime, endTime, isTradeSkill = UnitChannelInfo("player")
    end

    if name and CommanderCastingDB.ShowFullscreenEffect then
        local castDuration = endTime - startTime
        if castDuration <= 0 then  -- Guard against dividing by zero (endTime == startTime)
            glow:SetAlpha(0)
            return
        end
        local castElapsed = GetTime() * 1000 - startTime
        local castProgress = castElapsed / castDuration

        local r, g, b = 1, 0.7, 0  -- Default color (yellow-orange)

        -- Set color from spell school when the option is enabled
        if CommanderCastingDB.ColorBySpellSchool then
            local spellSchool = getSpellSchool(name)

            if spellSchool == "Holy" then
                r, g, b = 1, 0.95, 0.2  -- Bright golden yellow
            elseif spellSchool == "Fire" then
                r, g, b = 1, 0.2, 0  -- Vivid orange-red
            elseif spellSchool == "Nature" then
                r, g, b = 0, 1, .3  -- Vibrant green
            elseif spellSchool == "Frost" then
                r, g, b = 0, 0.8, 1  -- Electric blue
            elseif spellSchool == "Shadow" then
                r, g, b = 0.6, 0, 1  -- Deep purple
            elseif spellSchool == "Arcane" then
                r, g, b = 1, 0.3, 1  -- Bright magenta
            end
        end

        local glowIntensity = math.max(0, math.min(1, castProgress)) * CommanderCastingDB.EffectIntensity
        glow:SetVertexColor(r, g, b)
        glow:SetAlpha(glowIntensity)
    else
        glow:SetAlpha(0)
    end
end

local fullScreenGlow = CreateFullScreenGlow()

local function OnUpdate()
    UpdateCastingGlow(fullScreenGlow)
end

-- Only run the OnUpdate script while the player is actually casting or channeling
local isWatching = false

local function StartWatching()
    if not isWatching then
        isWatching = true
        frame:SetScript("OnUpdate", OnUpdate)
    end
end

local function StopWatching()
    if isWatching then
        isWatching = false
        frame:SetScript("OnUpdate", nil)
    end
end

local function OnAwake()
    Commander.AddListener(COMMANDER_CASTING_EVENTS.UPDATE, OnUpdate)
    Commander.Notify(COMMANDER_CASTING_EVENTS.UPDATE)
    -- Handle logging in / reloading mid-cast
    if UnitCastingInfo("player") or UnitChannelInfo("player") then
        StartWatching()
    end
end

local function OnDestroy() end

local function OnEvent(self, event, unit)
    if event == "PLAYER_LOGIN" then
        OnAwake()
        loaded = true
    elseif event == "PLAYER_LOGOUT" then
        OnDestroy()
    elseif loaded then
        if unit == "player" then
            if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
                StartWatching()
            elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
                or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                -- Only stop once nothing is in progress (e.g. an instant can fail mid-channel)
                if not UnitCastingInfo("player") and not UnitChannelInfo("player") then
                    StopWatching()
                end
            end
        end
        OnUpdate()
    end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP") 
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
frame:SetScript("OnEvent", OnEvent)
local savedWorldFramePoints

local TEXTURE_DIR = "Interface\\AddOns\\Commander_Console\\Textures\\"
-- Screen-pixel height of the console band, matching the 150-unit WorldFrame
-- inset ApplyViewport applies (keep the two in step)
local CONSOLE_STRIP_PX = 150

local function CreateConsoleBackdrop()
    local backdrop = CreateFrame("Frame", "CAB_ConsoleBackdrop", UIParent)
    backdrop:SetFrameStrata("BACKGROUND")
    backdrop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    backdrop:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)

    -- Full-screen artwork texture: the console art styles paint the whole
    -- screen and let their transparent upper region show the world
    local texture = backdrop:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(backdrop)  -- Set texture to fill the backdrop
    texture:SetTexture(TEXTURE_DIR .. "Console3.png")
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetAlpha(1)
    backdrop.texture = texture

    -- Bottom strip: the solid / gradient / generated-texture styles fill only
    -- the console band. It rides its own frame that ignores the UI scale, so a
    -- fixed 150px height meets the raised world edge (WorldFrame's 150-unit
    -- inset) exactly at any UI scale. Anchoring a texture straight to WorldFrame
    -- is rejected as a cross-anchor-family connection, so the strip stays inside
    -- the backdrop's own family and matches the inset by height instead.
    local stripFrame = CreateFrame("Frame", nil, backdrop)
    stripFrame:SetPoint("BOTTOMLEFT", backdrop, "BOTTOMLEFT", 0, 0)
    stripFrame:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 0)
    if stripFrame.SetIgnoreParentScale then
        stripFrame:SetIgnoreParentScale(true)
        stripFrame:SetHeight(CONSOLE_STRIP_PX)
    else
        local scale = (backdrop.GetEffectiveScale and backdrop:GetEffectiveScale()) or 1
        stripFrame:SetHeight(CONSOLE_STRIP_PX / (scale > 0 and scale or 1))
    end
    backdrop.stripFrame = stripFrame

    local strip = stripFrame:CreateTexture(nil, "ARTWORK")
    strip:SetAllPoints(stripFrame)
    strip:SetTexture("Interface\\Buttons\\WHITE8X8")
    strip:Hide()
    backdrop.strip = strip

    -- Optional decorative border around the console band: its own
    -- BackdropTemplate frame over the strip. Backdrop edges draw inward, so
    -- only the top and sides show (the bottom is off-screen). Guarded for
    -- clients without the backdrop mixin.
    local trimFrame = CreateFrame("Frame", nil, stripFrame, "BackdropTemplate")
    trimFrame:SetAllPoints(stripFrame)
    trimFrame:Hide()
    backdrop.trimFrame = trimFrame

    backdrop:Hide()  -- Hidden by default; ApplyConsoleState shows it when enabled

    return backdrop
end

local consoleBackdrop = CreateConsoleBackdrop()

-- Style/color tables are defined in CommanderConsoleDB.lua (loads first)
local function CurrentStyle()
    local value = CommanderConsoleDB and CommanderConsoleDB.ConsoleStyle
    for _, style in ipairs(CommanderConsole_Styles or {}) do
        if style.value == value then
            return style
        end
    end
    return (CommanderConsole_Styles and CommanderConsole_Styles[1])
        or { kind = "ART", file = "Console3.png" }
end

local function ResolveColor(value)
    -- Class Color resolves live from the shared class-identity layer
    if value == "CLASS" and Commander.GetClassInfo then
        local info = Commander.GetClassInfo()
        if info and info.color then
            return info.color[1], info.color[2], info.color[3]
        end
        return 1, 1, 1
    end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == value then
            return color.r, color.g, color.b
        end
    end
    return 1, 1, 1
end

-- Gradient fills carry the color themselves, so the texture stays white and
-- fully opaque and the opacity is baked into the gradient's own alpha. The
-- modern signature takes color objects; older clients take raw components.
local function ApplyStripGradient(tex, fade, r, g, b, opacity)
    tex:SetVertexColor(1, 1, 1)
    tex:SetAlpha(1)
    local br, bg, bb, ba = r, g, b, opacity                       -- bottom stop
    local tr, tg, tb, ta                                          -- top stop
    if fade then
        tr, tg, tb, ta = r, g, b, 0                               -- fade into the world
    else
        tr, tg, tb, ta = r * 0.28, g * 0.28, b * 0.28, opacity    -- lit sheen
    end
    if tex.SetGradient and CreateColor then
        if pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(br, bg, bb, ba), CreateColor(tr, tg, tb, ta)) then
            return
        end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", br, bg, bb, ba, tr, tg, tb, ta)
    else
        tex:SetVertexColor(r, g, b)  -- no gradient API: fall back to a solid fill
        tex:SetAlpha(opacity)
    end
end

-- A flat white->white gradient neutralizes any gradient left on the texture
-- so a following SetVertexColor tints it normally again
local function ClearStripGradient(tex)
    if tex.SetGradient and CreateColor then
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)) then
            return
        end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", 1, 1, 1, 1, 1, 1, 1, 1)
    end
end

-- Tile a material across the strip. REPEAT wrap + texcoords > 1 repeat the
-- texture; the tile count comes from the strip width and the Texture Scale (a
-- base tile is one strip-height square). Blizzard tiling textures and our
-- 128px generated tiles are power-of-two, so REPEAT is valid. Width and the
-- strip height share the strip's coordinate space, so the ratio holds at any
-- resolution; a 12-tile fallback covers the first frame before layout.
local function ApplyStripTiling(strip, stripFrame, path, tileScale)
    local scale = (tileScale and tileScale > 0) and tileScale or 1
    local tilePx = CONSOLE_STRIP_PX * scale
    local w = (stripFrame.GetWidth and stripFrame:GetWidth()) or 0
    local tilesX = (w > 0) and math.max(1, math.floor(w / tilePx + 0.5))
        or math.max(1, math.floor((CONSOLE_STRIP_PX * 12) / tilePx + 0.5))
    local tilesY = CONSOLE_STRIP_PX / tilePx
    strip:SetTexture(path, "REPEAT", "REPEAT")
    strip:SetTexCoord(0, tilesX, 0, tilesY)
end

local function CurrentTrim()
    local value = CommanderConsoleDB and CommanderConsoleDB.TrimStyle
    for _, trim in ipairs(CommanderConsole_Trims or {}) do
        if trim.value == value then return trim end
    end
    return nil
end

-- Draw (or hide) the optional decorative border around the console band
local function ApplyTrim()
    local trimFrame = consoleBackdrop.trimFrame
    if not (trimFrame and trimFrame.SetBackdrop) then return end
    local trim = CurrentTrim()
    if not trim or trim.value == "NONE" or not trim.edgeFile then
        trimFrame:Hide()
        return
    end
    if trimFrame._trimKey ~= trim.value then
        trimFrame._trimKey = trim.value
        trimFrame:SetBackdrop({ edgeFile = trim.edgeFile, edgeSize = trim.edgeSize, tile = false })
    end
    local tr, tg, tb = ResolveColor(CommanderConsoleDB.TrimColor or "STEEL")
    trimFrame:SetBackdropBorderColor(tr, tg, tb, CommanderConsoleDB.ConsoleOpacity or 1)
    trimFrame:Show()
end

local function ApplyConsoleAppearance()
    local style = CurrentStyle()
    local kind = style.kind or "ART"
    local r, g, b = ResolveColor(CommanderConsoleDB.ConsoleColor)
    local opacity = CommanderConsoleDB.ConsoleOpacity or 1
    local art = consoleBackdrop.texture
    local strip = consoleBackdrop.strip
    if kind == "ART" then
        strip:Hide()
        art:SetTexture(TEXTURE_DIR .. (style.file or "Console3.png"))
        art:SetTexCoord(0, 1, 0, 1)
        art:SetVertexColor(r, g, b)
        art:SetAlpha(opacity)
        art:Show()
    else
        art:Hide()
        if kind == "SOLID" then
            ClearStripGradient(strip)
            strip:SetTexture("Interface\\Buttons\\WHITE8X8")
            strip:SetTexCoord(0, 1, 0, 1)
            strip:SetVertexColor(r, g, b)
            strip:SetAlpha(opacity)
        elseif kind == "GRADIENT" then
            strip:SetTexture("Interface\\Buttons\\WHITE8X8")
            strip:SetTexCoord(0, 1, 0, 1)
            ApplyStripGradient(strip, style.fade, r, g, b, opacity)
        elseif kind == "TILE" then
            ClearStripGradient(strip)
            local path = style.blizz and style.file or (TEXTURE_DIR .. (style.file or "TileStone.png"))
            ApplyStripTiling(strip, consoleBackdrop.stripFrame, path, CommanderConsoleDB.TextureScale)
            strip:SetVertexColor(r, g, b)
            strip:SetAlpha(opacity)
        else  -- TEX: generated greyscale strip, stretched, tinted by the color
            ClearStripGradient(strip)
            strip:SetTexture(TEXTURE_DIR .. (style.file or "StripBrushed.png"))
            strip:SetTexCoord(0, 1, 0, 1)
            strip:SetVertexColor(r, g, b)
            strip:SetAlpha(opacity)
        end
        strip:Show()
    end
    ApplyTrim()
end

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

-- WorldFrame is protected in combat, and re-anchoring it directly from a
-- settings-panel callback is refused as tainted even OUT of combat (the panel
-- checkbox runs inside Blizzard's UI context, which taints the whole call
-- path). So the actual viewport change is always deferred to this load-time
-- frame's next OnUpdate tick: that executes in a clean, untainted context and
-- also naturally waits out combat lockdown. The backdrop and strip are our own
-- insecure frames and update immediately.
local viewportRunner = CreateFrame("Frame")
viewportRunner:Hide()
viewportRunner:SetScript("OnUpdate", function(self)
    -- WorldFrame still cannot be touched during combat; keep ticking until it drops
    if InCombatLockdown() then return end
    self:Hide()
    if CommanderConsoleDB.ShowConsole then
        SaveWorldFramePoints()  -- Save the original anchors before adjusting the viewport
        WorldFrame:ClearAllPoints()
        WorldFrame:SetPoint("TOPLEFT", 0, 0)
        -- CONSOLE_STRIP_PX matches the console band the strip fills (and the
        -- console art's bottom band), so the world edge lines up with the console
        WorldFrame:SetPoint("BOTTOMRIGHT", 0, CONSOLE_STRIP_PX)
    else
        RestoreWorldFramePoints()
    end
end)

-- Queue the viewport change for the runner's next tick, out of the tainted /
-- combat-locked call path. Safe to call from anywhere, including settings callbacks.
local function ApplyViewport()
    viewportRunner:Show()
end

local function ApplyConsoleState()
    if CommanderConsoleDB.ShowConsole then
        ApplyConsoleAppearance()
        consoleBackdrop:Show()
    else
        consoleBackdrop:Hide()
    end
    ApplyViewport()
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

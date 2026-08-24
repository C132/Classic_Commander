-- Commander Buffs: the render layer. Scans the player's aura stack, draws it
-- next to the player unit frame in BLIZZARD'S OWN aura language (sizes, art
-- and fonts read out of this client's UI source, see the constants below),
-- and puts a loss-of-control light on the portrait — the category named in a
-- word, tinted by what it took from you, with a radial duration ring.
--
-- The two halves answer different questions. The block is "what is on me",
-- and its job is to look like it came with the game. The sentinel is "what
-- has hold of me right now", and its job is to be readable without being
-- looked at — which is why it stays empty most of the time.
--
-- Everything here is INSECURE by design. A frame built from a secure
-- template is protected: it cannot be moved, shown, or re-attributed in
-- combat from addon code (the PartyFrames click-cast lesson). An aura block
-- must re-lay-out mid-fight, so it is display-only — right-click cancel is a
-- best-effort pcall and says so in its option tooltip.
--
-- Blizzard's own BuffFrame/DebuffFrame are hidden rather than moved: we do
-- not fight Edit Mode for a frame we are replacing. Hiding is deferred out
-- of combat (the Console viewport lesson — even non-combat-looking frame
-- work fired from a settings callback can be refused).

local E = CommanderBuffsEngine
local db

local TEXTURES = "Interface\\AddOns\\Commander_Buffs\\Textures\\"
local RING = TEXTURES .. "Ring.png"
local RIM = TEXTURES .. "Rim.png"
local CIRCLE_MASK = TEXTURES .. "CircleMask.png"
local CIRCLE_RIM = TEXTURES .. "CircleRim.png"

local MAX_BUFFS, MAX_DEBUFFS = 40, 40

-- ---------------------------------------------------------------------------
-- Blizzard's own aura-button geometry, read out of this client's UI source
-- (Gethe/wow-ui-source, branch classic_anniversary:
-- Blizzard_BuffFrame/BuffFrameTemplates.xml and Classic/BuffFrame.lua) rather
-- than eyeballed. These are what "looks native" actually means, and every one
-- of them is a visible tell when it is wrong:
--
--   icon        30x30, NO texcoord trim — Blizzard never trims aura art, so
--               trimming is the single loudest sign a block is an addon's
--   cell        30 wide x 40 tall: the extra 10 is the duration text's lane
--   padding     5 between icons, 8 icons per row (iconStride/iconPadding)
--   debuff art  UI-Debuff-Overlays at 33x32 CENTERED on the icon (it
--               deliberately overhangs), tinted by dispel school
--   buff art    none at all — a bordered buff is not a Blizzard buff
--   count       NumberFontNormal, bottom-right INSIDE the icon at (-2, 2)
--   duration    GameFontNormalSmall directly under the icon, NORMAL (yellow)
--               until BUFF_DURATION_WARNING_TIME, HIGHLIGHT (white) below it
-- ---------------------------------------------------------------------------

local BLIZZ_OVERLAY = "Interface\\Buttons\\UI-Debuff-Overlays"
local BLIZZ_OVERLAY_COORDS = { 0.296875, 0.5703125, 0, 0.515625 }
local BLIZZ_ICON = 30            -- the size the ratios below were measured at
local BLIZZ_BORDER_W = 33
local BLIZZ_BORDER_H = 32
local BLIZZ_DURATION_LANE = 10   -- cell height 40 - icon height 30
local BLIZZ_WARNING_TIME = 90    -- BUFF_DURATION_WARNING_TIME

local function IsBlizzardStyle()
    return not db or db.BlockStyle ~= "COMMANDER"
end

-- ---------------------------------------------------------------------------
-- Palette. Debuff rims speak the client's own dispel-school grammar so the
-- encoding transfers from the target frame with zero learning; rule colors
-- are the local set plus every Commander_Console suite tint (the TopBar
-- soft-fail pattern) so a rule can match the rest of the suite.
-- ---------------------------------------------------------------------------

local SCHOOL_COLORS = {
    Magic   = { 0.20, 0.60, 1.00 },
    Curse   = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison  = { 0.00, 0.60, 0.00 },
    NONE    = { 0.80, 0.10, 0.10 },
}

local RULE_COLORS = {
    RED    = { 0.90, 0.25, 0.20 },
    GOLD   = { 1.00, 0.78, 0.20 },
    GREEN  = { 0.35, 0.85, 0.40 },
    CYAN   = { 0.30, 0.80, 0.95 },
    PURPLE = { 0.70, 0.45, 0.95 },
    WHITE  = { 0.95, 0.95, 0.95 },
}

local MINE_RIM = { 1.00, 0.82, 0.30 }
local PLAIN_RIM = { 0.35, 0.35, 0.35 }

local function ColorByKey(key)
    if not key then return nil end
    local local_ = RULE_COLORS[key]
    if local_ then return local_ end
    for _, color in ipairs(CommanderConsole_Colors or {}) do
        if color.value == key and color.r then
            return { color.r, color.g, color.b }
        end
    end
    return nil
end
CommanderBuffs_ColorByKey = ColorByKey

local function SchoolColor(school)
    local global = _G.DebuffTypeColor
    local entry = global and global[school]
    if entry and entry.r then return entry.r, entry.g, entry.b end
    local fallback = SCHOOL_COLORS[school] or SCHOOL_COLORS.NONE
    return fallback[1], fallback[2], fallback[3]
end
CommanderBuffs_SchoolColor = SchoolColor

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local auras, auraN = {}, 0     -- pooled scan output, buffs then debuffs
local auraPool = {}
local ranked = {}              -- engine results, highest score first
local blockList, blockN = {}, 0 -- what the block draws, after its own filter

local block, blockIcons = nil, {}
local sentinel, sentinelSlots = nil, {}
local hooked = {}              -- Blizzard frames we have hooked Show on
local hidingDefaults = false
local pendingDefaults = false  -- a hide/show waiting on PLAYER_REGEN_ENABLED
local testUntil = 0
local lastEval = 0

local function Enabled()
    return db and db.EnableBuffs
end

local function Now()
    return GetTime and GetTime() or 0
end

-- Does this result clear the portrait's quiet dial? The shared ranking is
-- computed with no floor (see EvalOptions), so this is where Minimum Score
-- is actually spent — and ALERT results never have to clear it, which is the
-- whole contract of that action.
local function SentinelPasses(entry)
    if not entry then return false end
    if entry.alert then return true end
    return (entry.score or 0) >= ((db and db.MinScore) or 0)
end
CommanderBuffs_SentinelPasses = SentinelPasses

-- ---------------------------------------------------------------------------
-- Aura scanning
-- ---------------------------------------------------------------------------

local function ReleaseAuras()
    for i = auraN, 1, -1 do
        auraPool[#auraPool + 1] = auras[i]
        auras[i] = nil
    end
    auraN = 0
end

local function AcquireAura()
    local n = #auraPool
    if n > 0 then
        local entry = auraPool[n]
        auraPool[n] = nil
        return entry
    end
    return {}
end

local function Ingest(data, index, harmful)
    if not data then return end
    local entry = AcquireAura()
    entry.name = data.name or "?"
    entry.icon = data.icon
    entry.spellId = data.spellId or 0
    entry.stacks = data.applications or data.charges or 0
    entry.duration = data.duration or 0
    entry.expirationTime = data.expirationTime or 0
    entry.isHarmful = harmful
    entry.dispelName = data.dispelName
    entry.mine = data.isFromPlayerOrPlayerPet == true
        or data.sourceUnit == "player" or data.sourceUnit == "pet"
    entry.isBossAura = data.isBossAura == true
    entry.isStealable = data.isStealable == true
    entry.index = index
    entry.filter = harmful and "HARMFUL" or "HELPFUL"
    auraN = auraN + 1
    auras[auraN] = entry
end

-- The test stack: every visual state the block and the sentinel can reach,
-- seeded without needing a fight (the suite's tester convention).
local function IngestTestStack()
    local now = Now()
    local fixture = {
        { name = "Ice Block", icon = 135841, spellId = 45438, duration = 10, left = 3, mine = true },
        { name = "Arcane Intellect", icon = 135932, spellId = 10157, duration = 1800, left = 1400 },
        { name = "Blessing of Kings", icon = 135993, spellId = 20217, duration = 0, left = 0 },
        { name = "Renew", icon = 135953, spellId = 139, duration = 15, left = 9, mine = true },
        -- Kidney Shot is here to be a STUN, not just a debuff: without a real
        -- loss-of-control aura the test stack could never show the sentinel
        -- doing its actual job.
        { name = "Kidney Shot", icon = 132298, spellId = 408, duration = 6, left = 4,
          harmful = true },
        { name = "Polymorph", icon = 136071, spellId = 118, duration = 10, left = 6,
          harmful = true, dispelName = "Magic" },
        { name = "Sunder Armor", icon = 132363, spellId = 7386, duration = 30, left = 22,
          harmful = true, stacks = 5 },
        { name = "Crippling Poison", icon = 132274, spellId = 3409, duration = 12, left = 4,
          harmful = true, dispelName = "Poison" },
        { name = "Curse of Agony", icon = 136139, spellId = 980, duration = 24, left = 18,
          harmful = true, dispelName = "Curse" },
        { name = "Mortal Strike", icon = 132355, spellId = 12294, duration = 10, left = 7,
          harmful = true },
    }
    for _, row in ipairs(fixture) do
        local entry = AcquireAura()
        entry.name = row.name
        entry.icon = row.icon
        entry.spellId = row.spellId
        entry.stacks = row.stacks or 0
        entry.duration = row.duration
        entry.expirationTime = row.duration > 0 and (now + row.left) or 0
        entry.isHarmful = row.harmful == true
        entry.dispelName = row.dispelName
        entry.mine = row.mine == true
        entry.isBossAura = false
        entry.isStealable = false
        entry.index = nil
        entry.filter = row.harmful and "HARMFUL" or "HELPFUL"
        auraN = auraN + 1
        auras[auraN] = entry
    end
end

local function ScanAuras()
    ReleaseAuras()
    if testUntil > Now() then
        IngestTestStack()
        return
    end
    if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then return end
    for i = 1, MAX_BUFFS do
        local data = C_UnitAuras.GetBuffDataByIndex("player", i, "HELPFUL")
        if not data then break end
        Ingest(data, i, false)
    end
    for i = 1, MAX_DEBUFFS do
        local data = C_UnitAuras.GetDebuffDataByIndex("player", i, "HARMFUL")
        if not data then break end
        Ingest(data, i, true)
    end
end

-- ---------------------------------------------------------------------------
-- The Buffs On Top property, mirrored from the target frame
-- ---------------------------------------------------------------------------

-- true / false when the client answers, nil when neither source knows.
local function TargetBuffsOnTop()
    local frame = _G.TargetFrame
    if frame and type(frame.buffsOnTop) == "boolean" then
        return frame.buffsOnTop
    end
    local ok, value = pcall(function()
        local manager = _G.EditModeManagerFrame
        if not (manager and manager.GetSettingValueBool and _G.Enum) then return nil end
        local system = Enum.EditModeSystem and Enum.EditModeSystem.UnitFrame
        local index = Enum.EditModeUnitFrameSystemIndices
            and Enum.EditModeUnitFrameSystemIndices.Target
        local setting = Enum.EditModeUnitFrameSetting
            and Enum.EditModeUnitFrameSetting.BuffsOnTop
        if system == nil or index == nil or setting == nil then return nil end
        return manager:GetSettingValueBool(system, index, setting)
    end)
    if ok and type(value) == "boolean" then return value end
    return nil
end

-- Does the mirror have a source right now? The settings page reports this
-- instead of quietly pretending the mirror works.
function CommanderBuffs_MirrorAvailable()
    return TargetBuffsOnTop() ~= nil
end

local function BuffsOnTop()
    local mode = db and db.BuffsOnTopMode or "MIRROR_TARGET"
    if mode == "ON" then return true end
    if mode == "OFF" then return false end
    local mirrored = TargetBuffsOnTop()
    if mirrored ~= nil then return mirrored end
    return false
end
CommanderBuffs_BuffsOnTop = BuffsOnTop

-- ---------------------------------------------------------------------------
-- Blizzard's own aura frames
-- ---------------------------------------------------------------------------

local function DefaultFrames()
    local list = { _G.BuffFrame, _G.DebuffFrame }
    if db and db.HideTempEnchants then
        list[#list + 1] = _G.TemporaryEnchantFrame
    end
    return list
end

local function ApplyDefaultFrames()
    -- The block must exist before its frames are taken away: hiding is only
    -- ever honored while we are actually drawing a replacement.
    local wantHide = Enabled() and db.EnableBlock and db.HideDefaultAuras
    if InCombatLockdown and InCombatLockdown() then
        pendingDefaults = true
        return
    end
    pendingDefaults = false
    hidingDefaults = wantHide

    for _, frame in ipairs({ _G.BuffFrame, _G.DebuffFrame, _G.TemporaryEnchantFrame }) do
        if frame then
            if not hooked[frame] and hooksecurefunc then
                hooked[frame] = true
                -- Edit Mode, layout changes, and the client's own aura code
                -- all re-show these; one hook keeps them down without
                -- unregistering events we could never faithfully restore.
                pcall(hooksecurefunc, frame, "Show", function(self)
                    if not (hidingDefaults and self.__cbHidden) then return end
                    -- Never touch a Blizzard frame from a hook during
                    -- combat; the regen handler re-asserts the hide.
                    if InCombatLockdown and InCombatLockdown() then
                        pendingDefaults = true
                        return
                    end
                    self:Hide()
                end)
            end
        end
    end

    local hideList = {}
    for _, frame in ipairs(DefaultFrames()) do hideList[frame] = true end
    for _, frame in ipairs({ _G.BuffFrame, _G.DebuffFrame, _G.TemporaryEnchantFrame }) do
        if frame then
            local hide = wantHide and hideList[frame] or false
            frame.__cbHidden = hide
            if hide then frame:Hide() else frame:Show() end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Icon widgets (shared by the block and the sentinel)
-- ---------------------------------------------------------------------------

local function BuildIcon(parent, named)
    local icon = CreateFrame("Frame", named, parent)
    icon:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)

    icon.rim = icon:CreateTexture(nil, "BACKGROUND")
    icon.rim:SetTexture(RIM)
    icon.rim:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    icon.rim:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)

    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints(icon)
    -- The client's icon art carries a border in its outer 7%; trimming it
    -- is what makes a grid of icons read as a grid.
    icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetAllPoints(icon)
    if icon.cd.SetDrawEdge then icon.cd:SetDrawEdge(false) end
    if icon.cd.SetHideCountdownNumbers then icon.cd:SetHideCountdownNumbers(true) end
    -- Inverted on purpose: a cooldown swipe starts full and unwinds, which
    -- reads backwards on a buff — the icon would be brightest at the moment
    -- it is about to fall off. Reversed, the shade GROWS as time runs out,
    -- so "dark" always means "about to expire".
    if icon.cd.SetReverse then icon.cd:SetReverse(true) end

    icon.count = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)

    icon.timer = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    icon.timer:SetPoint("TOP", icon, "BOTTOM", 0, -1)
    icon.textStyle = nil

    icon:EnableMouse(true)
    icon:SetScript("OnEnter", function(self)
        if not GameTooltip or not self.auraName then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = false
        if self.auraIndex then
            -- Test auras carry no index on purpose: a bogus one would show
            -- the tooltip of whatever real aura happens to sit there.
            if self.auraFilter == "HARMFUL" then
                ok = pcall(GameTooltip.SetUnitDebuff, GameTooltip, "player", self.auraIndex, "HARMFUL")
            else
                ok = pcall(GameTooltip.SetUnitBuff, GameTooltip, "player", self.auraIndex, "HELPFUL")
            end
        end
        if not ok then
            GameTooltip:SetText(self.auraName)
        end
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
    icon:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if not (db and db.RightClickCancel) then return end
        if self.auraFilter ~= "HELPFUL" or not self.auraIndex then return end
        -- Best effort: the retail-era framework this build runs may refuse
        -- CancelUnitBuff from insecure code. A refusal is a silent no-op.
        pcall(CancelUnitBuff, "player", self.auraIndex)
    end)

    return icon
end

-- The count and duration fontstrings wear whichever client's typography the
-- style asks for. Applied only on a change, because re-pointing a fontstring
-- every repaint is churn the 10 Hz tick would pay for forever.
local function ApplyTextStyle(icon, native)
    local wanted = native and "BLIZZARD" or "COMMANDER"
    if icon.textStyle == wanted then return end
    icon.textStyle = wanted
    -- The Commander style writes plain white over whatever the yellow/white
    -- warning color left behind, so the cached warning state is now a lie:
    -- clear it, or switching back would skip the SetTextColor that restores it.
    icon.timerWarn = nil

    icon.count:ClearAllPoints()
    icon.timer:ClearAllPoints()
    if native then
        icon.count:SetFontObject("NumberFontNormal")
        icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
        icon.timer:SetFontObject("GameFontNormalSmall")
        icon.timer:SetPoint("TOP", icon, "BOTTOM", 0, 0)
    else
        icon.count:SetFontObject("NumberFontNormalSmall")
        icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, 0)
        icon.timer:SetFontObject("GameFontHighlightSmall")
        icon.timer:SetPoint("TOP", icon, "BOTTOM", 0, -1)
        icon.timer:SetTextColor(1, 1, 1)
    end
end

-- Blizzard's duration text. SecondsToTimeAbbrev returns a PLURAL-AWARE FORMAT
-- plus its argument, so it has to go through SetFormattedText — the |4 escape
-- is resolved by the client, not by string.format. The (format, value) pair
-- is what gets cached rather than the rendered string, so the 10 Hz tick can
-- still skip work without rendering the text just to compare it.
local function SetDurationText(icon, remaining, native)
    if native and SecondsToTimeAbbrev then
        local ok, fmt, value = pcall(SecondsToTimeAbbrev, remaining)
        if ok and fmt then
            if icon.timerFmt ~= fmt or icon.timerValue ~= value then
                icon.timerFmt, icon.timerValue, icon.timerText = fmt, value, nil
                icon.timer:SetFormattedText(fmt, value)
            end
            local warn = remaining < BLIZZ_WARNING_TIME
            if icon.timerWarn ~= warn then
                icon.timerWarn = warn
                local color = warn and _G.HIGHLIGHT_FONT_COLOR or _G.NORMAL_FONT_COLOR
                if color and color.r then
                    icon.timer:SetTextColor(color.r, color.g, color.b)
                else
                    -- No font colors on this client: the yellow/white split is
                    -- decoration, so fall back to plain white rather than skip
                    -- the number entirely.
                    icon.timer:SetTextColor(1, 1, 1)
                end
            end
            return
        end
    end
    local text = E.FormatTime(remaining)
    if icon.timerText ~= text then
        icon.timerText = text
        icon.timerFmt, icon.timerValue, icon.timerWarn = nil, nil, nil
        icon.timer:SetText(text)
    end
end

-- The border. Blizzard's debuff overlay deliberately overhangs its icon
-- (33x32 art centered on 30x30), which is why it is sized by ratio here
-- instead of anchored to the icon's edges — anchoring it would squash the
-- art and lose exactly the silhouette we are matching. A buff gets no border
-- at all in this style unless My Buffs Rimmed is asking for one, and then it
-- wears the same overlay in gold rather than a second kind of frame.
local function ApplyBorder(icon, size, native, show, r, g, b)
    if not show then
        icon.rim:Hide()
        return
    end
    if native and not icon.round then
        icon.rim:SetTexture(BLIZZ_OVERLAY)
        icon.rim:SetTexCoord(BLIZZ_OVERLAY_COORDS[1], BLIZZ_OVERLAY_COORDS[2],
            BLIZZ_OVERLAY_COORDS[3], BLIZZ_OVERLAY_COORDS[4])
        icon.rim:ClearAllPoints()
        icon.rim:SetPoint("CENTER", icon, "CENTER", 0, 0)
        icon.rim:SetSize(size * BLIZZ_BORDER_W / BLIZZ_ICON,
            size * BLIZZ_BORDER_H / BLIZZ_ICON)
    else
        icon.rim:SetTexture(icon.round and CIRCLE_RIM or RIM)
        icon.rim:SetTexCoord(0, 1, 0, 1)
        icon.rim:ClearAllPoints()
        icon.rim:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
        icon.rim:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    end
    icon.rim:SetVertexColor(r, g, b, 1)
    icon.rim:Show()
end

local function PaintIcon(icon, entry, size, opts)
    local native = opts.native == true
    icon:SetSize(size, size)
    icon.texture:SetTexture(entry.icon)
    -- The client's icon art carries a border in its outer 7%. Trimming it
    -- makes a grid read as a grid, which is why the Commander style does —
    -- but Blizzard never trims, so the native style must not either.
    if native then
        icon.texture:SetTexCoord(0, 1, 0, 1)
    else
        icon.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    icon.auraIndex = entry.index
    icon.auraFilter = entry.filter
    icon.auraName = entry.name
    icon.entry = entry
    icon.showTimer = opts.timers and true or false
    icon.native = native
    -- The sentinel owns its own typography and anchors (its timer hangs
    -- lower, clear of the ring), so it opts out of the block's text style.
    if not opts.keepText then ApplyTextStyle(icon, native) end

    local r, g, b, show = nil, nil, nil, true
    if entry.isHarmful then
        r, g, b = SchoolColor(E.SchoolOf(entry))
    elseif opts.mineRim and entry.mine then
        r, g, b = MINE_RIM[1], MINE_RIM[2], MINE_RIM[3]
    elseif native then
        show = false     -- a Blizzard buff has no border, full stop
    else
        r, g, b = PLAIN_RIM[1], PLAIN_RIM[2], PLAIN_RIM[3]
    end
    if opts.borderColor then
        r, g, b = opts.borderColor[1], opts.borderColor[2], opts.borderColor[3]
        show = true
    end
    ApplyBorder(icon, size, native, show, r, g, b)

    -- The suite's icon recess, drawn from Commander_Events' shared art so a
    -- buff here and an icon on any other Commander board are cut the same way.
    -- Off for native, which exists precisely to look like Blizzard's own
    -- buffs, and shaped to whatever ApplyRound settled on -- a round icon gets
    -- the round cut, and a client that refused the mask gets the square one.
    if Commander.DebossIcon then
        local style = (not native) and (db and db.IconRecess or "SOFT") or nil
        Commander.DebossIcon(icon.texture, style, icon.round)
    end

    local stacks = entry.stacks or 0
    if stacks > 1 then
        icon.count:SetText(stacks)
        icon.count:Show()
    else
        icon.count:Hide()
    end

    local remaining = E.Remaining(entry, Now())
    if opts.sweep and entry.duration and entry.duration > 0 and remaining then
        icon.cd:SetCooldown(entry.expirationTime - entry.duration, entry.duration)
        icon.cd:Show()
    else
        icon.cd:Hide()
    end

    if opts.timers and remaining then
        SetDurationText(icon, remaining, native)
        icon.timer:Show()
    else
        icon.timerText, icon.timerFmt, icon.timerValue = nil, nil, nil
        icon.timer:Hide()
    end

    icon:Show()
end

-- Cut the sentinel icon into a disc with a circular alpha mask so it reads
-- as one shape with the ring around it — a square icon inside a round timer
-- is two different objects fighting for the same 26 pixels. The Afflictions
-- portrait pattern: guarded and pcall'd, so a client without mask textures
-- simply keeps square icons instead of breaking the sentinel. The rim only
-- goes circular if the mask actually took.
--
-- Only the MASK lives here. Which art the rim wears is ApplyBorder's job, and
-- it reads slot.round — so a client that refuses the mask keeps square icons
-- AND a square rim rather than a round rim around a square face.
local function ApplyRound(slot, round)
    -- Guarded on what was ASKED for, not on what was achieved: a client that
    -- cannot mask would otherwise retry the pcall on every single repaint.
    if slot.roundWanted == round then return end
    slot.roundWanted = round
    if round then
        if not slot.mask and slot.CreateMaskTexture and slot.texture.AddMaskTexture then
            pcall(function()
                local mask = slot:CreateMaskTexture()
                mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(slot.texture)
                slot.mask = mask
            end)
        end
        if slot.mask then
            pcall(slot.texture.AddMaskTexture, slot.texture, slot.mask)
        end
        slot.round = slot.mask ~= nil
    else
        if slot.mask and slot.texture.RemoveMaskTexture then
            pcall(slot.texture.RemoveMaskTexture, slot.texture, slot.mask)
        end
        slot.round = false
    end
end

-- ---------------------------------------------------------------------------
-- The block
-- ---------------------------------------------------------------------------

local function EnsureBlock()
    if block then return block end
    local parent = _G.PlayerFrame or _G.UIParent
    if not parent then return nil end
    block = CreateFrame("Frame", "CommanderBuffsBlock", parent)
    block:SetSize(1, 1)
    return block
end

local function AcquireBlockIcon(slot)
    local icon = blockIcons[slot]
    if not icon then
        icon = BuildIcon(block, "CommanderBuffsIcon" .. slot)
        blockIcons[slot] = icon
    end
    return icon
end

-- What the block draws. ALL keeps the client's own order (the mirror of
-- default behavior); RULES borrows only the policy's HIDE vetoes; SCORED
-- borrows the whole ranking, so the block reads most-interesting-first.
local function BuildBlockList()
    for i = blockN, 1, -1 do blockList[i] = nil end
    blockN = 0
    local mode = db.BlockFilter or "ALL"
    if mode == "ALL" then
        for i = 1, auraN do
            blockN = blockN + 1
            blockList[blockN] = auras[i]
        end
        return
    end
    -- Both filtered modes read the ranking, which already dropped HIDE
    -- rules; SCORED additionally keeps the ranking's order.
    local kept = {}
    for _, entry in ipairs(ranked) do kept[entry.aura] = true end
    if mode == "SCORED" then
        for _, entry in ipairs(ranked) do
            blockN = blockN + 1
            blockList[blockN] = entry.aura
        end
        return
    end
    for i = 1, auraN do
        if kept[auras[i]] then
            blockN = blockN + 1
            blockList[blockN] = auras[i]
        end
    end
end

-- Does this entry get the "mine" enlargement? Buffs only, deliberately: the
-- point is separating YOUR upkeep from what the raid put on you, and a debuff
-- you applied to yourself is not that. Same scoping as the gold rim.
local function MineScaleFor(entry, opts)
    local scale = opts.mineScale or 1
    if scale <= 1 then return 1 end
    if entry.isHarmful or not entry.mine then return 1 end
    return scale
end

local function LayoutGroup(startSlot, list, count, size, top, opts)
    local perRow = opts.perRow
    local gap = opts.gap
    -- The cell is sized for the LARGEST icon this group can hold, and every
    -- icon is top-centered inside its own cell. Growing one icon inside a
    -- fixed cell would just make it overlap its neighbours; growing the cell
    -- keeps a grid a grid, at the cost of a little air around the small ones.
    local cell = size * math.max(1, opts.mineScale or 1)
    -- Blizzard's cell is 30 wide by 40 tall: the extra 10 is the lane the
    -- duration text lives in, and rows that do not reserve it overlap.
    local stride = cell + gap + (opts.timers and BLIZZ_DURATION_LANE or 0)
    local slot = startSlot
    local rows = 0
    for i = 1, count do
        local entry = list[i]
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        rows = row + 1
        local icon = AcquireBlockIcon(slot)
        ApplyRound(icon, opts.round)
        PaintIcon(icon, entry, size * MineScaleFor(entry, opts), opts)
        icon:ClearAllPoints()
        -- Anchored by its BOTTOM CENTER to the foot of the cell. Bottom-aligned
        -- rather than top-aligned so every icon in a row sits on one baseline
        -- and their duration texts stay on one line — an enlarged icon grows
        -- UPWARD into the space the cell already reserved for it.
        local x = col * (cell + gap) + cell / 2
        local y = top - row * stride - cell
        if opts.growLeft then
            icon:SetPoint("BOTTOM", block, "TOPRIGHT", -x, y)
        else
            icon:SetPoint("BOTTOM", block, "TOPLEFT", x, y)
        end
        slot = slot + 1
    end
    return slot, rows * stride
end

local function LayoutBlock()
    if not block then return end
    if not (Enabled() and db.EnableBlock) then
        block:Hide()
        for _, icon in pairs(blockIcons) do icon:Hide() end
        return
    end

    BuildBlockList()

    local buffs, buffN = {}, 0
    local debuffs, debuffN = {}, 0
    for i = 1, blockN do
        local entry = blockList[i]
        if entry.isHarmful then
            debuffN = debuffN + 1
            debuffs[debuffN] = entry
        else
            buffN = buffN + 1
            buffs[buffN] = entry
        end
    end

    local opts = {
        perRow = db.IconsPerRow or 8,
        gap = db.IconGap or 5,
        timers = db.ShowTimers,
        sweep = db.IconSweep,
        mineRim = db.MineRim,
        growLeft = db.GrowLeft,
        round = db.RoundBlockIcons == true,
        native = IsBlizzardStyle(),
        mineScale = db.MineScale or 1,
    }

    local slot, top = 1, 0
    local groupGap = 4
    local buffsFirst = BuffsOnTop()
    local usedHeight = 0

    local function drawGroup(list, count, size)
        if count == 0 then return end
        local nextSlot, height = LayoutGroup(slot, list, count, size, top, opts)
        slot = nextSlot
        top = top - height - groupGap
        usedHeight = usedHeight + height + groupGap
    end

    if buffsFirst then
        drawGroup(buffs, buffN, db.BuffSize or BLIZZ_ICON)
        drawGroup(debuffs, debuffN, db.DebuffSize or BLIZZ_ICON)
    else
        drawGroup(debuffs, debuffN, db.DebuffSize or BLIZZ_ICON)
        drawGroup(buffs, buffN, db.BuffSize or BLIZZ_ICON)
    end

    for i = slot, #blockIcons do
        if blockIcons[i] then blockIcons[i]:Hide() end
    end

    -- The enlargement widens the BUFF cell only, so the block's own width is
    -- measured off whichever group actually ends up wider.
    local widest = math.max((db.BuffSize or BLIZZ_ICON) * math.max(1, opts.mineScale),
        db.DebuffSize or BLIZZ_ICON)
    local width = opts.perRow * (widest + opts.gap)
    block:SetSize(math.max(width, 1), math.max(usedHeight, 1))
    block:SetAlpha(db.BlockOpacity or 1)

    -- Anchor last: the block grows downward from its own top edge, so a
    -- block placed ABOVE the frame anchors by its bottom and one placed
    -- BELOW anchors by its top. Same layout math either way.
    local parent = _G.PlayerFrame or _G.UIParent
    local x = db.OffsetX or 0
    local y = db.OffsetY or 0
    block:ClearAllPoints()
    local horizontal = db.GrowLeft and "RIGHT" or "LEFT"
    if db.Placement == "ABOVE" then
        block:SetPoint("BOTTOM" .. horizontal, parent, "TOP" .. horizontal, x, y)
    else
        block:SetPoint("TOP" .. horizontal, parent, "BOTTOM" .. horizontal, x, y)
    end
    block:Show()
end

-- The 10 Hz path. Re-laying the whole block out ten times a second would
-- churn a SetPoint per icon for text that changes once a second; this walks
-- the icons already on screen and only touches their countdown.
local function TickBlockTimers()
    local now = Now()
    for i = 1, blockN do
        local icon = blockIcons[i]
        if not icon or not icon:IsShown() then break end
        if icon.showTimer and icon.entry then
            local remaining = E.Remaining(icon.entry, now)
            if remaining then
                SetDurationText(icon, remaining, icon.native)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The portrait sentinel
-- ---------------------------------------------------------------------------

local function EnsureSentinel()
    if sentinel then return sentinel end
    local parent = _G.PlayerFrame or _G.UIParent
    if not parent then return nil end
    sentinel = CreateFrame("Frame", "CommanderBuffsSentinel", parent)
    sentinel:SetSize(1, 1)
    sentinel:SetFrameStrata("MEDIUM")
    return sentinel
end

local function AcquireSlot(index)
    local slot = sentinelSlots[index]
    if slot then return slot end
    slot = BuildIcon(sentinel, "CommanderBuffsSentinel" .. index)
    -- The ring is the sentinel's whole idea: a swipe on a donut draws a
    -- progress ring around the icon instead of a wedge across the face.
    slot.ring = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    slot.ring:SetPoint("TOPLEFT", slot, "TOPLEFT", -3, 3)
    slot.ring:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 3, -3)
    if slot.ring.SetHideCountdownNumbers then slot.ring:SetHideCountdownNumbers(true) end
    if slot.ring.SetDrawEdge then slot.ring:SetDrawEdge(false) end
    if slot.ring.SetSwipeTexture then slot.ring:SetSwipeTexture(RING) end
    -- Same inversion as the block icons: the sweep fills as the aura dies.
    if slot.ring.SetReverse then slot.ring:SetReverse(true) end
    slot.timer:ClearAllPoints()
    slot.timer:SetPoint("TOP", slot, "BOTTOM", 0, -2)

    -- The word. An icon alone cannot tell you WHICH control you are under —
    -- Polymorph and Arcane Intellect are both a square of art, and the whole
    -- point of the sentinel is being read without being looked at. The label
    -- goes ABOVE the icon so it never collides with the remaining-time text.
    slot.loc = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slot.loc:SetPoint("BOTTOM", slot, "TOP", 0, 3)
    slot.loc:Hide()

    sentinelSlots[index] = slot
    return slot
end

local SENTINEL_ANCHORS = {
    CENTER = { "CENTER", "CENTER" },
    TOP = { "BOTTOM", "TOP" },
    BOTTOM = { "TOP", "BOTTOM" },
    LEFT = { "RIGHT", "LEFT" },
    RIGHT = { "LEFT", "RIGHT" },
}

local function UpdateSentinel()
    if not sentinel then return end
    if not (Enabled() and db.EnablePortrait) then
        for _, slot in pairs(sentinelSlots) do slot:Hide() end
        sentinel:Hide()
        return
    end

    local anchorTo = _G.PlayerPortrait or _G.PlayerFrame or _G.UIParent
    local pair = SENTINEL_ANCHORS[db.PortraitAnchor or "CENTER"] or SENTINEL_ANCHORS.CENTER
    sentinel:ClearAllPoints()
    sentinel:SetPoint(pair[1], anchorTo, pair[2], db.PortraitX or 0, db.PortraitY or 0)
    -- Opacity rides the CONTAINER, so the icon, its ring, its rim, and the
    -- expiry pulse all fade together and the pulse math stays untouched
    -- (child alpha multiplies with the parent's).
    sentinel:SetAlpha(db.PortraitOpacity or 1)
    sentinel:Show()

    local size = db.PortraitSize or 26
    local spacing = db.SlotSpacing or 3
    local slots = db.Slots or 1
    local now = Now()
    local shown = 0

    -- What the portrait is actually allowed to show, in order. The ranking
    -- itself carries everything (the block and the trace read it); Minimum
    -- Score is spent here.
    local shortlist = {}
    for i = 1, #ranked do
        if SentinelPasses(ranked[i]) then shortlist[#shortlist + 1] = ranked[i] end
    end

    -- Loss of control takes the whole sentinel. When something is holding you
    -- down, the runners-up are not context, they are competition — so the
    -- trailing slots stand down until you have your character back.
    if shortlist[1] and shortlist[1].loc and db.LocSolo ~= false then slots = 1 end

    for index = 1, slots do
        local entry = shortlist[index]
        local slot = AcquireSlot(index)
        ApplyRound(slot, db.RoundSentinel ~= false)
        if entry then
            local locInfo = E.LocInfo(entry.loc)
            -- Category beats rule color: RED means stunned on every character
            -- you play, whatever the rule that claimed it happens to be named.
            local color = locInfo and locInfo.color or ColorByKey(entry.color)
            PaintIcon(slot, entry.aura, size, {
                timers = db.PortraitTimer,
                sweep = false,          -- the ring below owns the radial duration
                mineRim = true,
                keepText = true,
                borderColor = color,
            })

            if locInfo and db.LocLabel ~= false then
                slot.loc:SetText(locInfo.label)
                slot.loc:SetTextColor(locInfo.color[1], locInfo.color[2], locInfo.color[3])
                slot.loc:Show()
            else
                slot.loc:Hide()
            end

            local remaining = E.Remaining(entry.aura, now)
            local duration = entry.aura.duration or 0
            if duration > 0 and remaining then
                if db.SweepStyle == "WEDGE" then
                    -- A solid quad swiped black is the classic cooldown
                    -- wedge; clearing the swipe texture outright is not a
                    -- supported call, so we swap art instead.
                    if slot.ring.SetSwipeTexture then
                        slot.ring:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
                    end
                    slot.ring:SetPoint("TOPLEFT", slot, "TOPLEFT", 0, 0)
                    slot.ring:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 0, 0)
                    if slot.ring.SetSwipeColor then slot.ring:SetSwipeColor(0, 0, 0, 0.65) end
                else
                    if slot.ring.SetSwipeTexture then slot.ring:SetSwipeTexture(RING) end
                    slot.ring:SetPoint("TOPLEFT", slot, "TOPLEFT", -3, 3)
                    slot.ring:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 3, -3)
                    if slot.ring.SetSwipeColor then
                        local c = color or MINE_RIM
                        slot.ring:SetSwipeColor(c[1], c[2], c[3], 0.95)
                    end
                end
                slot.ring:SetCooldown(entry.aura.expirationTime - duration, duration)
                slot.ring:Show()
            else
                slot.ring:Hide()
            end

            -- Expiry pulse: alpha, not size — a growing icon on the portrait
            -- fights the frame art, a pulsing one does not.
            local pulseUnder = db.PulseUnder or 0
            if pulseUnder > 0 and remaining and remaining <= pulseUnder then
                local phase = (now * 3) % 2
                slot:SetAlpha(phase < 1 and (0.45 + phase * 0.55) or (1.55 - phase * 0.55))
            else
                slot:SetAlpha(1)
            end

            slot:ClearAllPoints()
            if index == 1 then
                slot:SetPoint("CENTER", sentinel, "CENTER", 0, 0)
            else
                slot:SetPoint("LEFT", sentinelSlots[index - 1], "RIGHT", spacing, 0)
            end
            if not db.PortraitStacks then slot.count:Hide() end
            slot:Show()
            shown = shown + 1
        else
            slot:Hide()
        end
    end
    for index = slots + 1, #sentinelSlots do
        if sentinelSlots[index] then sentinelSlots[index]:Hide() end
    end
    if shown == 0 then sentinel:Hide() end
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

local evalOpts = {}

-- The shared ranking is computed with NO floor. Minimum Score is the
-- PORTRAIT's dial, and applying it here would take the rest of the module
-- down with it: the block's Rules Applied mode is documented as borrowing
-- only the policy's HIDE vetoes, and the editor's trace exists to show what
-- was dropped and why. Both read this list. The floor is applied at the last
-- moment, by SentinelPasses, where it belongs.
local function EvalOptions()
    evalOpts.fallback = db and db.FallbackMode or "IGNORE"
    evalOpts.minScore = 0
    return evalOpts
end


local function Rules()
    if not db then return {} end
    db.Rules = db.Rules or {}
    return db.Rules
end
CommanderBuffs_Rules = Rules

local function Refresh()
    if not db then return end
    ScanAuras()
    E.Evaluate(auras, Rules(), EvalOptions(), Now(), ranked)
    LayoutBlock()
    UpdateSentinel()
    if CommanderBuffsEditor_Repaint then CommanderBuffsEditor_Repaint() end
end
CommanderBuffs_Refresh = Refresh

-- The editor's live trace reads exactly what the sentinel reads.
function CommanderBuffs_GetTrace()
    return auras, auraN, ranked
end

function CommanderBuffs_Test()
    testUntil = Now() + 15
    print("|cff66ccffCommander Buffs|r: test stack for 15s")
    Refresh()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")

local function Apply()
    if not db then return end
    EnsureBlock()
    EnsureSentinel()
    ApplyDefaultFrames()
    Refresh()
end
CommanderBuffs_Apply = Apply

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        db = CommanderBuffsDB
        E.NormalizeRules(Rules())
        EnsureBlock()
        EnsureSentinel()
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        Commander.AddListener(COMMANDER_BUFFS_EVENTS.UPDATE, Apply)
        Apply()
    elseif event == "UNIT_AURA" then
        Refresh()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        -- Edit Mode re-anchors and re-shows its systems; re-assert both the
        -- hide and the mirrored Buffs On Top after it does.
        Apply()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingDefaults then ApplyDefaultFrames() end
        Refresh()
    end
end)

-- A slow ticker, not a per-frame one: scores change as auras approach expiry
-- (the expiring bonus can hand the portrait to a different aura with no
-- UNIT_AURA in sight), and the pulse needs a heartbeat. 10 Hz is plenty for
-- both and the whole evaluation is a few dozen comparisons.
events:SetScript("OnUpdate", function(_, elapsed)
    if not db or not Enabled() then return end
    lastEval = lastEval + elapsed
    if lastEval < 0.1 then return end
    lastEval = 0
    if testUntil > 0 and testUntil <= Now() then
        testUntil = 0
        Refresh()
        return
    end
    E.Evaluate(auras, Rules(), EvalOptions(), Now(), ranked)
    if db.EnableBlock and db.ShowTimers then TickBlockTimers() end
    UpdateSentinel()
end)

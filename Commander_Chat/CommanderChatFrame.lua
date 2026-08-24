-- Commander Chat — the replacement window.
--
-- The whole design rests on one decision: this frame does NOT re-implement
-- chat. Blizzard's ChatFrame1 keeps receiving every CHAT_MSG_* event and keeps
-- doing all the formatting — channel prefixes, class colors, localized
-- globalstrings, hyperlinks, timestamps, and whatever other addons inject —
-- and we mirror the finished line out of its AddMessage into our own
-- ScrollingMessageFrame. Perfect fidelity for a fraction of the surface, and
-- nothing in FrameXML is ever fought.
--
-- ChatFrame1 is then parked rather than hidden: shown (so every FrameXML path
-- that checks IsShown keeps working, including the edit box plumbing) but at
-- zero alpha with its mouse off and its tabs down. The one piece we do move is
-- the edit box, re-parented to UIParent so it can render while its old parent
-- is invisible, and re-anchored under our window. Every bit of that is undone
-- by Restore().

CommanderChatWindow = nil

local window, body
local parked = false
local editBoxHome = nil
local driver, driverRunning = nil, false
local driverElapsed, currentAlpha = 0, 1

local DRIVER_INTERVAL = 0.05
local FADE_RATE = 4.0

local function DB() return CommanderChatDB end

-- ---------------------------------------------------------------------------
-- Construction
-- ---------------------------------------------------------------------------
local function BuildWindow()
    if window then return window end

    window = CreateFrame("Frame", "CommanderChatWindow", UIParent)
    window:SetSize(430, 140)
    window:SetFrameStrata("BACKGROUND")
    CommanderChatWindow = window

    body = CreateFrame("ScrollingMessageFrame", "CommanderChatWindowBody", window)
    body:SetPoint("TOPLEFT", window, "TOPLEFT", 4, -4)
    body:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -4, 4)
    body:SetFontObject(ChatFontNormal)
    body:SetJustifyH("LEFT")
    body:SetMaxLines(500)
    body:SetFading(true)
    body:SetInsertMode("BOTTOM")
    window.body = body

    -- Hyperlinks are the one interactive thing a mirrored line still has to
    -- do for itself: the text carries |H...|h markup, but only the frame it
    -- was added to routes the click.
    if body.SetHyperlinksEnabled then
        body:SetHyperlinksEnabled(true)
    end
    body:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then SetItemRef(link, text, button, self) end
    end)
    body:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    body:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)

    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            if IsShiftKeyDown() then self:ScrollToTop() else self:ScrollUp() end
        else
            if IsShiftKeyDown() then self:ScrollToBottom() else self:ScrollDown() end
        end
    end)

    return window
end

-- ---------------------------------------------------------------------------
-- Parking Blizzard's window
-- ---------------------------------------------------------------------------
-- ChatFrame1's own button frame is a child and rides its alpha down, but
-- these two are parented elsewhere and would be left hovering beside a window
-- that is no longer there.
local STRAY_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton" }

local function Park()
    if parked then return end
    parked = true

    local chatFrame = ChatFrame1
    if not chatFrame then return end
    chatFrame:SetAlpha(0)
    chatFrame:EnableMouse(false)
    for _, name in ipairs(STRAY_BUTTONS) do
        local button = _G[name]
        if button and button:IsShown() then
            button:Hide()
            button._commanderParked = true
        end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab:IsShown() then
            tab:Hide()
            tab._commanderParked = true
        end
    end

    -- The edit box is a child of the frame we just made invisible, so it has
    -- to move out from under that alpha to stay usable. Its global name is
    -- untouched, which is all ChatEdit_* resolves it by, and
    -- editBox.chatFrame is set once in the template's OnLoad and is what
    -- ChatEdit_* resolves the owning window by, so re-parenting does not
    -- disturb the send path — and it is a sounder thing to restore to than
    -- whatever GetParent happens to say later.
    local editBox = chatFrame.editBox
    if editBox and not editBoxHome then
        editBoxHome = { parent = editBox.chatFrame or editBox:GetParent() or chatFrame, points = {} }
        for i = 1, (editBox:GetNumPoints() or 0) do
            local point = { editBox:GetPoint(i) }
            if point[1] then editBoxHome.points[#editBoxHome.points + 1] = point end
        end
        editBox:SetParent(UIParent)
    end
end

local function Unpark()
    if not parked then return end
    parked = false

    local chatFrame = ChatFrame1
    if chatFrame then
        chatFrame:SetAlpha(1)
        chatFrame:EnableMouse(true)
    end
    for _, name in ipairs(STRAY_BUTTONS) do
        local button = _G[name]
        if button and button._commanderParked then
            button._commanderParked = nil
            button:Show()
        end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab and tab._commanderParked then
            tab._commanderParked = nil
            tab:Show()
        end
    end

    local editBox = chatFrame and chatFrame.editBox
    if editBox and editBoxHome then
        editBox:SetParent(editBoxHome.parent)
        editBox:ClearAllPoints()
        if #editBoxHome.points > 0 then
            for _, point in ipairs(editBoxHome.points) do
                editBox:SetPoint(unpack(point))
            end
        else
            -- Nothing readable to put back: fall back to the template's own
            -- XML anchors rather than leaving the edit box floating
            editBox:SetPoint("TOPLEFT", editBoxHome.parent, "BOTTOMLEFT", -5, -2)
            editBox:SetPoint("TOPRIGHT", editBoxHome.parent, "BOTTOMRIGHT", 5, -2)
        end
        editBoxHome = nil
    end
end

local function AnchorEditBox()
    local editBox = ChatFrame1 and ChatFrame1.editBox
    if not editBox or not window or not editBoxHome then return end
    editBox:ClearAllPoints()
    editBox:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -2)
    editBox:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, -2)
end

-- ---------------------------------------------------------------------------
-- Mouseover fading — ours alone now, so there is nothing to race
-- ---------------------------------------------------------------------------
local function TargetAlpha()
    if not window then return 1 end
    local alpha = 1
    if DB().CombatQuiet and CommanderChat_InCombat and CommanderChat_InCombat() then
        alpha = DB().CombatQuietAlpha or 0.15
    end
    if DB().MouseoverOnly then
        local editBox = ChatFrame1 and ChatFrame1.editBox
        local active = window:IsMouseOver(4, -4, -4, 4)
            or (editBox and editBox:IsShown() and editBox:HasFocus())
        if active then
            alpha = 1
        else
            local idle = DB().IdleAlpha or 0.2
            if idle < alpha then alpha = idle end
        end
    end
    return alpha
end

local function DriverTick(_, elapsed)
    driverElapsed = driverElapsed + elapsed
    if driverElapsed < DRIVER_INTERVAL then return end
    local step = driverElapsed * FADE_RATE
    driverElapsed = 0

    local target = TargetAlpha()
    if currentAlpha < target then
        currentAlpha = math.min(currentAlpha + step, target)
    elseif currentAlpha > target then
        currentAlpha = math.max(currentAlpha - step, target)
    else
        return -- settled; nothing owns this alpha but us, so stop writing
    end
    window:SetAlpha(currentAlpha)
end

local function UpdateDriver(active)
    local needed = (active and DB().MouseoverOnly) and true or false
    if needed == driverRunning then return end
    driverRunning = needed
    driver = driver or CreateFrame("Frame")
    driver:SetScript("OnUpdate", needed and DriverTick or nil)
    driverElapsed = 0
end

-- ---------------------------------------------------------------------------
-- Public surface
-- ---------------------------------------------------------------------------
function CommanderChatWindow_IsActive()
    return (CommanderChatDB and CommanderChatDB.Enabled and CommanderChatDB.ReplaceChatFrame) and true or false
end

-- Called from the AddMessage hook on ChatFrame1 with the line Blizzard has
-- already finished formatting.
function CommanderChatWindow_Receive(text, r, g, b)
    if not body or not CommanderChatWindow_IsActive() then return end
    body:AddMessage(text, r, g, b)
end

function CommanderChatWindow_Restore()
    Unpark()
    UpdateDriver(false)
    if window then window:Hide() end
end

function CommanderChatWindow_Update()
    if not CommanderChatWindow_IsActive() then
        CommanderChatWindow_Restore()
        return
    end

    BuildWindow()
    Park()

    local db = DB()
    Commander.UI.ApplyHudChrome(window, db, "Window", {
        defaultPoint = { point = "BOTTOMLEFT", x = 24, y = 30 },
    })
    window:SetSize(db.ChatWidth or 430, db.ChatHeight or 140)

    local file, size, flags = ChatFontNormal:GetFont()
    local fontSize = db.FontSize or 0
    body:SetFont(file, fontSize > 0 and fontSize or size, flags)

    body:SetFading(not db.KeepChatVisible)
    if not db.KeepChatVisible then
        body:SetTimeVisible(db.FadeDelay or 120)
    end

    AnchorEditBox()
    window:Show()

    -- Snap so a settings change reads immediately; the driver eases from here
    currentAlpha = TargetAlpha()
    window:SetAlpha(currentAlpha)
    UpdateDriver(true)
end

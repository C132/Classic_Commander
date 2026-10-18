-- Commander Vault: the window.
--
-- Draws the vault as one continuous grid over every bank container, grouped
-- into sections, and paints the item art the module owns outright — the
-- quality ring, the bind padlock, the item level — rather than borrowing
-- Blizzard's, which repaints itself on every container event.
--
-- The item buttons are built from nothing rather than from
-- ContainerFrameItemButtonTemplate. That template reads its bag id off its
-- PARENT frame, which is exactly the assumption a unified grid breaks: here
-- one parent holds slots from eight different containers. Owning the button
-- means owning the click handling too, which is fine — container items are not
-- protected on this client, so a plain Button can pick up, use and link them.
--
-- 1.2.0 (Commander Orders 3.1, DECISIONS D48): while the window shows YOUR
-- vault remembered away from a banker, the footer line offers "Go to Bank",
-- Commander Orders' Go button (Commander_Events' Commander.UI.GoButton) to the
-- nearest banker ({ townsfolk = "Banker" }, source "Vault", key "bank").

CommanderVault = CommanderVault or {}
local V = CommanderVault

BINDING_HEADER_COMMANDERVAULT = "Commander Vault"
BINDING_NAME_COMMANDERVAULT_TOGGLE = "Open the Vault"
BINDING_NAME_COMMANDERVAULT_SEARCH = "Search the Vault"

local QUAD = "Interface\\Buttons\\WHITE8X8"
local PAD = 10
local HEADER_H = 18
local GAP = 4

-- The stock bank window's own parts sheet. Bank-Slot-BG is the stone socket
-- every bank slot sits in and Bank-Rivet is the stud between them; both are
-- virtual textures in the client's BankFrame.xml and these are their TexCoords
-- verbatim, not eyeballed. Blizzard draws the socket 6px proud of the button
-- on three sides and 7 below, which is where the grid's BANK spacing comes
-- from.
local BANK_PARTS = "Interface\\BankFrame\\Bank-Parts"
local BANK_SOCKET_TC = { 0.015625, 0.8125, 0.1171875, 0.5078125 }
-- The bank's own stone, as a tile.
--
-- No shipped texture is this material, and the numbers say so rather than a
-- hunch: the stock sheet's open stone averages 106/99/93, while
-- Interface\\BankFrame\\Bank-Background -- the file this used to draw, and the
-- reason the window read as a cellar -- is 69/65/52 and distinctly olive,
-- UI-Background-Rock is 52/47/43, and UI-Background-Marble, whatever the name
-- suggests, is 13/13/13, very nearly black. A backdrop colour multiplies, so
-- none of them can be lifted to the right tone from Lua.
--
-- Cutting a tile out of the real sheet does not work either: its scratches
-- were cut for a window shown ONCE, and every seamless arrangement of them
-- repeats into wallpaper. So this reproduces the MATERIAL -- the sheet's
-- measured palette, spread and grain, rebuilt as periodic noise that is
-- seamless at any size and has no motif to repeat.
-- Textures/make_bank_stone.py regenerates it.
local BANK_STONE = "Interface\\AddOns\\Commander_Vault\\Textures\\BankStone.png"
local GRIP_ART = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

-- Dragged size, clamped. The floor is the width at which the toolbar's own
-- controls stop colliding -- three view tabs, a search box worth typing in and
-- three action buttons -- which is a tighter constraint than the grid's.
-- MIN_W is the toolbar's floor, not the grid's (D46): three view tabs, the
-- four right-hand buttons with Deposit Mats among them, the match-count gap,
-- and about a hundred pixels of search box left over
local MIN_W, MIN_H = 680, 320
local MAX_W, MAX_H = 1800, 1400

local frame, grid, scroll, scrollChild, reportChild, reportScroll
local buttons, headers, reportRows, rosterRows = {}, {}, {}, {}
local bagButtons, bagHeaders = {}, {}
buttons.namePrefix = "CommanderVaultItem"
bagButtons.namePrefix = "CommanderVaultCarried"
local query = V.ParseQuery("")
local searchText = ""
local pendingRefresh
local savedBankPoint
-- itemIDs the last drawn snapshot had not finished loading. GET_ITEM_INFO_RECEIVED
-- fires city-wide and constantly — every inspect, every auction page, every
-- passer-by's gear — so an unfiltered handler relayouts the whole grid dozens
-- of times a second in a capital. Only an item this window is actually waiting
-- on is worth a pass. (The trap Commander_Quartermaster documents.)
local pendingItems = {}
-- Forward-declared: Refresh re-applies the framing on every pass, and it is
-- defined above the framing block
local ApplyFraming

-- Commander Orders' Go button (click Go, Shift-click share, Ctrl-click copy
-- the /way line, lit "Going" while the arrow goes there). The client reads a
-- NEW addon file only at start-up, so after an update and a /reload the
-- button's file may be missing: then a plain button that still asks Orders.
local function GoButton(parent, opts)
    local UI = Commander and Commander.UI
    if UI and type(UI.GoButton) == "function" then return UI.GoButton(parent, opts) end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(opts.width or 96, opts.height or 20)
    button:SetText(opts.label or "Go")
    button:SetScript("OnClick", function()
        local orders = CommanderOrders
        if type(orders) == "table" and type(orders.GoTo) == "function" then
            orders.GoTo(opts.query, { source = opts.source, key = opts.key, icon = opts.icon })
        end
    end)
    button.Refresh = function() end
    return button
end

local function DB()
    return CommanderVaultDB or {}
end

local function IsBankStyle()
    return (DB().FrameStyle or "BANK") == "BANK"
end

-- Button size and the gap between buttons. BANK needs the wider gap because
-- its sockets overhang the button they sit behind; the flat styles draw the
-- backing inside the button and can pack tighter.
local function Metrics()
    local size = DB().ButtonSize or 37
    return size, IsBankStyle() and 11 or GAP
end

-- Text has to change colour with the stone under it. A pale grey heading is a
-- rumour on the bank's light stone and a brown one is a rumour on the suite's
-- flat dark panels, and the same two font strings have to be both.
local PALETTE = {
    BANK = {
        heading = { 0.20, 0.13, 0.04 },
        subtle  = { 0.38, 0.32, 0.24 },
        rule    = { 0.16, 0.10, 0.03, 0.32 },
        hi      = "|cff2b1c06",
        gold    = "|cff7a5200",
    },
    FLAT = {
        heading = { 1, 0.82, 0.2 },
        subtle  = { 0.6, 0.6, 0.6 },
        rule    = { 1, 1, 1, 0.12 },
        hi      = "|cffffffff",
        gold    = "|cffffd200",
    },
}

local function Skin()
    return PALETTE[IsBankStyle() and "BANK" or "FLAT"]
end

-- ---------------------------------------------------------------------------
-- Item art
--
-- Lifted wholesale from Commander_Bags, which learned it the hard way: the
-- ring is DRAWN from tinted quads, never borrowed from IconBorder, so nothing
-- else in the UI can wash it out.
-- ---------------------------------------------------------------------------

local function EnsureRing(button)
    if button.ring then return button.ring end
    local ring = {}
    for index = 1, 8 do
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 5)
        tex:SetTexture(QUAD)
        tex:Hide()
        ring[index] = tex
    end
    button.ring = ring
    return ring
end

-- Four quads inset by `inset` from the icon's rect, `weight` thick. The
-- horizontals own the corners, so the verticals stop short of them.
local function LayoutRing(ring, first, anchor, inset, weight)
    local top, bottom, left, right = ring[first], ring[first + 1], ring[first + 2], ring[first + 3]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT", inset, -inset)
    top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -inset, -inset)
    top:SetHeight(weight)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", inset, inset)
    bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -inset, inset)
    bottom:SetHeight(weight)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(weight)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(weight)
end

local function ShowRing(button, r, g, b, thickness, halo)
    local ring = EnsureRing(button)
    if button.ringThickness ~= thickness then
        button.ringThickness = thickness
        LayoutRing(ring, 1, button.icon, 0, thickness)
        LayoutRing(ring, 5, button.icon, thickness, 1)
    end
    for index = 1, 4 do
        ring[index]:SetVertexColor(r, g, b, 1)
        ring[index]:Show()
    end
    for index = 5, 8 do
        if halo then
            ring[index]:SetVertexColor(r, g, b, 0.4)
            ring[index]:Show()
        else
            ring[index]:Hide()
        end
    end
end

local function HideRing(button)
    if not button.ring then return end
    for index = 1, 8 do button.ring[index]:Hide() end
end

local BADGE = 13

local function EnsureBadge(button)
    if button.badge then return button.badge end
    local function Quad(sublevel)
        local tex = button:CreateTexture(nil, "OVERLAY", nil, sublevel)
        tex:SetTexture(QUAD)
        return tex
    end
    local badge = { plate = Quad(6), body = Quad(7), postL = Quad(7), postR = Quad(7), bar = Quad(7) }
    badge.plate:SetSize(BADGE, BADGE)
    badge.plate:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMLEFT", 1, 1)
    badge.body:SetSize(9, 5)
    badge.body:SetPoint("BOTTOM", badge.plate, "BOTTOM", 0, 2)
    badge.postL:SetSize(2, 4)
    badge.postR:SetSize(2, 4)
    badge.bar:SetHeight(2)
    button.badge = badge
    return badge
end

local function HideBadge(button)
    if not button.badge then return end
    for _, tex in pairs(button.badge) do tex:Hide() end
end

-- Closed and steel means soulbound; open and gold means still bind-on-equip,
-- so still tradeable, sellable, disenchantable for somebody else.
local function ShowBadge(button, bound)
    local badge = EnsureBadge(button)
    local r, g, b, plateAlpha = 1, 0.84, 0.3, 0.7
    if bound then
        r, g, b, plateAlpha = 0.74, 0.78, 0.88, 0.55
    end
    badge.plate:SetVertexColor(0, 0, 0, plateAlpha)
    for _, key in ipairs({ "body", "postL", "postR", "bar" }) do
        badge[key]:SetVertexColor(r, g, b, 1)
    end
    badge.postL:ClearAllPoints()
    badge.postR:ClearAllPoints()
    badge.bar:ClearAllPoints()
    if bound then
        badge.postL:SetPoint("BOTTOM", badge.plate, "BOTTOM", -2.5, 6)
        badge.postR:SetPoint("BOTTOM", badge.plate, "BOTTOM", 2.5, 6)
        badge.bar:SetWidth(7)
        badge.bar:SetPoint("BOTTOM", badge.plate, "BOTTOM", 0, 9)
        badge.postR:Show()
    else
        -- Open: the shackle is hinged left and swung clear, so the right post
        -- is simply gone
        badge.postL:SetPoint("BOTTOM", badge.plate, "BOTTOM", -2.5, 6)
        badge.bar:SetWidth(6)
        badge.bar:SetPoint("BOTTOM", badge.plate, "BOTTOM", 1.5, 9)
        badge.postR:Hide()
    end
    badge.plate:Show()
    badge.body:Show()
    badge.postL:Show()
    badge.bar:Show()
end

-- A small gold flag in the top-right corner of anything a saved gear set wants.
-- It is the answer to "why is the report not shouting about these shoulders",
-- given on the shoulders themselves rather than only in the report.
local function EnsureSetFlag(button)
    if button.setFlag then return button.setFlag end
    local flag = button:CreateTexture(nil, "OVERLAY", nil, 6)
    flag:SetTexture(QUAD)
    flag:SetSize(5, 5)
    flag:SetPoint("TOPRIGHT", button.icon, "TOPRIGHT", -2, -2)
    flag:SetVertexColor(1, 0.82, 0.2, 0.95)
    button.setFlag = flag
    return flag
end

local QUEST_COLOR = { 1, 0.85, 0.1 }
local JUNK_COLOR = { 0.75, 0.25, 0.25 }
local CONSUMABLE_COLOR = { 0.35, 0.85, 0.95 }

-- Category beats quality where category is the more useful answer: a quest
-- item is a quest item whatever colour the client gave it, and a grey is money
-- rather than a white item that happens to be worse.
local function RingColorFor(row)
    if row.isQuest then return QUEST_COLOR end
    if row.quality == 0 then return JUNK_COLOR end
    if row.classID == 0 then return CONSUMABLE_COLOR end
    if (row.quality or 1) <= 1 then return nil end
    local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
    if not color then return nil end
    return { color.r, color.g, color.b }
end

-- ---------------------------------------------------------------------------
-- Item buttons
-- ---------------------------------------------------------------------------

-- Filling a tooltip from a slot can fail QUIETLY: the call does not error, it
-- simply produces nothing (a container id the client will not take, an item
-- whose data has not landed, a cached link from an older build). pcall returns
-- "did not error", which is NOT the same question — so every attempt is judged
-- by whether the tooltip actually gained lines, and the next source is tried
-- when it did not. An empty tooltip box was the whole "weird tooltip" bug.
-- Did the tooltip actually end up showing THIS item?
--
-- Counting lines is not the test, and believing it was is what let the bug
-- through twice. A Set* that fails on this client can still fire
-- OnTooltipSetItem, and any other addon hooked there (Auctionator's vendor and
-- auction prices, for one) appends its lines to the empty tooltip — so the
-- line count says "filled" while the item's own name, quality and text are
-- nowhere on it. The only signal another addon cannot forge is the tooltip's
-- own idea of which item it is showing, checked against the one we asked for.
local function TooltipShowsItem(itemID)
    if not GameTooltip.GetItem then return false end
    local ok, name, link = pcall(GameTooltip.GetItem, GameTooltip)
    if not ok or not link then return false end
    local shown = C_Item.GetItemInfoInstant(link)
    return shown == itemID and name ~= nil and name ~= ""
end

-- SetOwner, not ClearLines, between attempts: ClearLines empties the text but
-- leaves the tooltip's ITEM alone, so a failed fill would still answer GetItem
-- with whatever was hovered before it — and hovering two stacks of the same
-- thing in a row is the common case in a bank, not a corner one. SetOwner is
-- the call that genuinely starts a fresh tooltip.
local function TrySetTooltip(owner, itemID, fn, ...)
    if not fn then return false end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(fn, GameTooltip, ...)
    if not ok then return false end
    return TooltipShowsItem(itemID)
end

-- Everything the module already knows about the item, drawn as a tooltip.
-- Reached only when every client source has refused, which on this client is
-- not hypothetical: SetBagItem does not fill for bank containers. A stub
-- saying "not loaded" would be a worse answer than the one we can give.
local function TooltipFromRow(owner, row)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local color = row.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[row.quality]
    GameTooltip:SetText(row.name or "Loading…",
        color and color.r or 1, color and color.g or 1, color and color.b or 1)
    if (row.count or 1) > 1 then
        GameTooltip:AddLine(string.format("Stack of %d", row.count), 0.9, 0.9, 0.9)
    end
    local kind = row.subType or row.itemType
    if kind then
        local slotName = row.equipLoc and row.equipLoc ~= "" and _G[row.equipLoc]
        if slotName then
            GameTooltip:AddDoubleLine(slotName, kind, 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine(kind, 1, 1, 1)
        end
    end
    if (row.ilvl or 0) > 0 and row.equipLoc and row.equipLoc ~= "" then
        GameTooltip:AddLine("Item Level " .. row.ilvl, 1, 0.82, 0)
    end
    if (row.minLevel or 0) > 1 then
        GameTooltip:AddLine("Requires Level " .. row.minLevel, 0.8, 0.8, 0.8)
    end
    if row.bindType == 1 then
        GameTooltip:AddLine("Binds when picked up", 0.8, 0.8, 0.8)
    elseif row.bindType == 2 then
        GameTooltip:AddLine("Binds when equipped", 0.8, 0.8, 0.8)
    end
    if not row.full then
        GameTooltip:AddLine("Details still loading.", 0.5, 0.5, 0.55)
    end
end

local function TooltipFor(button)
    local row = button.row
    if not row then
        GameTooltip:Hide()
        return
    end
    -- The vault writes its own count lines below, in one block and in an order
    -- it chose. Without this the global counts layer fires from inside the
    -- fill and interleaves a SECOND set of them into the middle of the item
    -- text — nothing on a unique helm, a wall of duplicated numbers on cloth.
    V.suppressTooltipCounts = true
    local filled = false
    -- The slot is tried first only where it can say something the link cannot
    -- (whether THIS copy has bound). Everywhere else, and whenever it refuses,
    -- the link is the reliable source.
    if not row.cached and V.IsBankOpen() then
        filled = TrySetTooltip(button, row.itemID, GameTooltip.SetBagItem, row.bag, row.slot)
    end
    if not filled and row.link then
        filled = TrySetTooltip(button, row.itemID, GameTooltip.SetHyperlink, row.link)
    end
    if not filled then
        filled = TrySetTooltip(button, row.itemID, GameTooltip.SetItemByID, row.itemID)
    end
    if not filled then
        TooltipFromRow(button, row)
    end
    V.suppressTooltipCounts = false

    -- One block, one separator, and only lines that say something the item
    -- text above did not. "Also" folds what used to be two count lines and the
    -- global layer's alt list into a single sentence.
    local extra = {}
    -- Which container it is actually in. A vault runs to 28 slots plus up to
    -- seven bags, and "I can see it, where is it" is a real question in a
    -- window that deliberately does not draw the containers in order.
    if row.bag then
        extra[#extra + 1] = { text = "In " .. V.ContainerName(row.bag),
                              r = 0.6, g = 0.7, b = 0.85 }
    end
    local setName = V.SetWanting(row.itemID)
    if setName then
        extra[#extra + 1] = { text = "Saved set: " .. setName, r = 1, g = 0.82, b = 0.2 }
    end
    if not row.foreign then
        local carried, _, others, where = V.CountsFor(row.itemID)
        local also = {}
        if carried > 0 then also[#also + 1] = string.format("%d in your bags", carried) end
        if others > 0 then
            local who = where[1]
            also[#also + 1] = (#where == 1 and who)
                and string.format("%d on %s", others, who.name or "an alt")
                or string.format("%d on %d other characters", others, #where)
        end
        if #also > 0 then
            extra[#extra + 1] = { text = "Also " .. table.concat(also, ", "),
                                  r = 0.55, g = 0.8, b = 0.55 }
        end
        local days = V.DwellDays(row.itemID)
        if days and days >= 1 then
            extra[#extra + 1] = { text = string.format("Sitting here %d %s",
                days, days == 1 and "day" or "days"), r = 0.6, g = 0.6, b = 0.65 }
        end
    end
    -- Only for a real stack. Unit vendor price is already on the tooltip from
    -- Commander_Tooltip and from the auction addons most people run, so
    -- repeating it on a single item is just a third identical line; the
    -- multiplied total for a stack is the part nobody else works out.
    if (row.count or 1) > 1 then
        local value = V.RowValue(row)
        if value > 0 then
            extra[#extra + 1] = {
                text = string.format("Vendor x%d  %s", row.count, V.Money(value)),
                r = 0.8, g = 0.75, b = 0.5,
            }
        end
    end
    if row.cached then
        extra[#extra + 1] = { text = row.foreign and "From a remembered snapshot"
            or "From the remembered snapshot", r = 0.5, g = 0.5, b = 0.55 }
    end

    if #extra > 0 then
        GameTooltip:AddLine(" ")
        for _, line in ipairs(extra) do
            GameTooltip:AddLine(line.text, line.r, line.g, line.b)
        end
    end
    GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- Authored sections
--
-- Reached with ctrl+right-click on an item, because plain right-click already
-- means "move this to the other side" and that is the more common gesture by
-- a wide margin.
-- ---------------------------------------------------------------------------

-- StaticPopup's edit box has been reachable under two different names across
-- this UI's history; ask for both rather than pick one
local function DialogEditBox(dialog)
    if not dialog then return nil end
    if dialog.editBox then return dialog.editBox end
    local name = dialog.GetName and dialog:GetName()
    return name and _G[name .. "EditBox"] or nil
end

local function AssignAndRefresh(itemID, name)
    V.SetItemSection(itemID, name)
    V.Refresh()
end

if StaticPopupDialogs then
    StaticPopupDialogs["COMMANDER_VAULT_NEW_SECTION"] = {
        text = "Name a section for this item:",
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 24,
        OnShow = function(self)
            local box = DialogEditBox(self)
            if box then
                box:SetText("")
                box:SetFocus()
            end
        end,
        OnAccept = function(self)
            local box = DialogEditBox(self)
            local name = box and box:GetText()
            if name and name ~= "" and self.data then
                AssignAndRefresh(self.data, name)
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local dialog = self:GetParent()
            local name = self:GetText()
            if name and name ~= "" and dialog and dialog.data then
                AssignAndRefresh(dialog.data, name)
            end
            if dialog and dialog.Hide then dialog:Hide() end
        end,
        EditBoxOnEscapePressed = function(self)
            local dialog = self:GetParent()
            if dialog and dialog.Hide then dialog:Hide() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local function OpenSectionMenu(button)
    local row = button.row
    if not row then return end
    local menu = {
        { text = "File " .. (row.name or "this item") .. " under", isTitle = true, notCheckable = true },
    }
    local current = V.UserSectionOf(row.itemID)
    for _, name in ipairs(V.UserSectionList()) do
        menu[#menu + 1] = {
            text = name, notCheckable = false, checked = (current == name),
            func = function() AssignAndRefresh(row.itemID, name) end,
        }
    end
    menu[#menu + 1] = {
        text = "New section…", notCheckable = true,
        func = function()
            if StaticPopup_Show then
                local dialog = StaticPopup_Show("COMMANDER_VAULT_NEW_SECTION")
                if dialog then dialog.data = row.itemID end
            end
        end,
    }
    if current then
        menu[#menu + 1] = {
            text = "Back where it belongs", notCheckable = true,
            func = function() AssignAndRefresh(row.itemID, nil) end,
        }
    end
    if not frame.sectionMenu then
        frame.sectionMenu = CreateFrame("Frame", "CommanderVaultSectionMenu", frame, "UIDropDownMenuTemplate")
    end
    if EasyMenu then
        EasyMenu(menu, frame.sectionMenu, button, 0, 0, "MENU")
    else
        print("Commander Vault: no menu available — /cvault settings has the section list")
    end
end

-- Whether this button's (bag, slot) names a container THIS character can act
-- on right now.
--
-- Gating on "is the bank open" was a real bug and a nasty one: while browsing
-- an alt's vault or a guild bank the button carries THAT record's coordinates,
-- and your own bank is very likely open, because you are standing at a banker
-- looking up what the alt has. A click then moved, withdrew or used YOUR item
-- at those coordinates — an item you never touched. The flag is stamped at
-- paint time by whoever knows which snapshot is being drawn.
local function Actionable(button)
    return button.actionable == true
end

local function ButtonClick(button, mouseButton)
    local row = button.row
    if IsModifiedClick and IsModifiedClick("CHATLINK") and row and row.link then
        HandleModifiedItemClick(row.link)
        return
    end
    if mouseButton == "RightButton" then
        -- Filing an item is a judgement about the ITEM, not about the slot, so
        -- it works on a remembered vault and on an alt's just as well. Every
        -- other interaction below needs a real bank behind it: a cached slot
        -- is a picture of a vault you are not standing in.
        if IsControlKeyDown and IsControlKeyDown() then
            OpenSectionMenu(button)
            return
        end
        if not Actionable(button) then return end
        C_Container.UseContainerItem(button.bag, button.slot)
        return
    end
    if not Actionable(button) then return end
    if IsModifiedClick and IsModifiedClick("SPLITSTACK") and row and (row.count or 1) > 1 then
        if OpenStackSplitFrame then
            button.hasStackSplit = 1
            OpenStackSplitFrame(row.count, button, "BOTTOMRIGHT", "TOPRIGHT")
            return
        end
    end
    C_Container.PickupContainerItem(button.bag, button.slot)
end

local function CreateButton(parent, name)
    local button = CreateFrame("Button", name, parent)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- The stock bank slot: a stone socket the icon sits inside. In the flat
    -- styles it is swapped for a plain dark quad by ApplyFraming.
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -2, 2)
    button.count:SetJustifyH("RIGHT")

    button.ilvl = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    button.ilvl:SetPoint("TOPLEFT", button.icon, "TOPLEFT", 2, -2)
    button.ilvl:SetTextColor(0.9, 0.9, 0.6)

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(button.icon)
    highlight:SetTexture(QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.18)
    button:SetHighlightTexture(highlight)

    button:SetScript("OnEnter", TooltipFor)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnClick", ButtonClick)
    button:SetScript("OnDragStart", function(self)
        if Actionable(self) and self.row then
            C_Container.PickupContainerItem(self.bag, self.slot)
        end
    end)
    button:SetScript("OnReceiveDrag", function(self)
        -- An empty slot has no row but is still a legitimate drop target
        if Actionable(self) and self.bag then
            C_Container.PickupContainerItem(self.bag, self.slot)
        end
    end)
    -- The stack-split popup calls this back on the button it was opened over
    button.SplitStack = function(self, amount)
        if Actionable(self) then
            C_Container.SplitContainerItem(self.bag, self.slot, amount)
        end
    end
    return button
end

-- Pools are named per-pool: the vault grid and the carried-bags grid share a
-- parent, so a shared name would have the second pool quietly overwrite the
-- first pool's globals.
local function Acquire(pool, parent, index)
    local button = pool[index]
    if not button then
        button = CreateButton(parent, (pool.namePrefix or "CommanderVaultItem") .. index)
        pool[index] = button
    end
    return button
end

-- Applied per paint rather than once, because the frame style can change under
-- a pool that was built long before it.
--
-- BANK draws the client's own bank socket, at the offsets BankSlotsFrame_OnLoad
-- uses (-6/+5 top-left, +6/-7 bottom-right around a 37x38 button), so a slot
-- here is pixel-for-pixel the slot in the window this one replaces. It
-- overhangs the button, which is why Metrics widens the grid's gap in BANK.
local function StyleSlot(button)
    if IsBankStyle() then
        button.bg:SetTexture(BANK_PARTS)
        button.bg:SetTexCoord(unpack(BANK_SOCKET_TC))
        button.bg:SetVertexColor(1, 1, 1, 1)
        if not button._socketed then
            button._socketed = true
            button.bg:ClearAllPoints()
            button.bg:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 4)
            button.bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -6)
        end
    else
        button.bg:SetTexture(QUAD)
        button.bg:SetTexCoord(0, 1, 0, 1)
        button.bg:SetVertexColor(0, 0, 0, 0.45)
        if button._socketed then
            button._socketed = nil
            button.bg:ClearAllPoints()
            button.bg:SetAllPoints()
        end
    end
end

local function PaintButton(button, row, position, dimmed, actionable)
    local db = DB()
    local size = db.ButtonSize or 37
    button:SetSize(size, size)
    StyleSlot(button)
    button.row = row
    button.bag = position and position.bag or (row and row.bag)
    button.slot = position and position.slot or (row and row.slot)
    button.actionable = actionable and true or false

    if not row then
        button.icon:SetTexture(nil)
        button.count:SetText("")
        button.ilvl:SetText("")
        HideRing(button)
        HideBadge(button)
        if button.setFlag then button.setFlag:Hide() end
        button:SetAlpha(1)
        button:Show()
        return
    end

    button.icon:SetTexture(row.icon or (V.InstantOf(row.itemID) or {}).icon)
    button.count:SetText((row.count or 1) > 1 and row.count or "")
    if db.ShowItemLevel and row.equipLoc and row.equipLoc ~= "" and (row.ilvl or 0) > 0 then
        button.ilvl:SetText(row.ilvl)
    else
        button.ilvl:SetText("")
    end

    if db.ColorCodeItems then
        local color = RingColorFor(row)
        if color then
            ShowRing(button, color[1], color[2], color[3], db.BorderThickness or 2, db.RarityHalo)
        else
            HideRing(button)
        end
        local mode = db.BindBadges or "BOTH"
        local bound = row.bound == true or row.bindType == 1
        local unboundBoe = (row.bindType == 2 or row.bindType == 3) and row.bound ~= true
        if mode == "OFF" or (mode == "BOE" and not unboundBoe) then
            HideBadge(button)
        elseif bound or unboundBoe then
            ShowBadge(button, bound)
        else
            HideBadge(button)
        end
    else
        HideRing(button)
        HideBadge(button)
    end

    if V.SetWanting(row.itemID) then
        EnsureSetFlag(button):Show()
    elseif button.setFlag then
        button.setFlag:Hide()
    end

    button:SetAlpha(dimmed and 0.25 or 1)
    button:Show()
end

-- ---------------------------------------------------------------------------
-- Headers
-- ---------------------------------------------------------------------------

local function AcquireHeader(pool, parent, index)
    local header = pool[index]
    if header then return header end
    header = CreateFrame("Button", nil, parent)
    header:SetHeight(HEADER_H)
    header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    header.label = header:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header.label:SetPoint("LEFT", header, "LEFT", 2, 0)
    header.count = header:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    header.count:SetPoint("LEFT", header.label, "RIGHT", 6, 0)
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetColorTexture(1, 1, 1, 0.12)
    header.line:SetHeight(1)
    header.line:SetPoint("LEFT", header.count, "RIGHT", 8, 0)
    header.line:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            -- Dissolving an authored section just clears its assignments; the
            -- items go back to wherever the item class would have put them,
            -- and nothing is ever destroyed by tidying up a heading
            local name = V.UserSectionName(self.groupKey)
            if name then
                local cleared = V.ClearUserSection(name)
                print(string.format("Commander Vault: dissolved \"%s\" — %d %s filed back",
                    name, cleared, cleared == 1 and "item" or "items"))
                V.Refresh()
            end
            return
        end
        local db = DB()
        db.Collapsed = db.Collapsed or {}
        db.Collapsed[self.groupKey] = not db.Collapsed[self.groupKey] or nil
        V.Refresh()
    end)
    header:SetScript("OnEnter", function(self)
        local name = V.UserSectionName(self.groupKey)
        if not name then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name, 1, 0.82, 0.2)
        GameTooltip:AddLine("A section you named.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click to dissolve it — the items file themselves back.", 0.7, 0.6, 0.6)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[index] = header
    return header
end

-- ---------------------------------------------------------------------------
-- Grouping
--
-- Display order is the sort order, whether or not the physical sort has ever
-- been run: the grid always reads as organized, and running the sort is what
-- makes the underlying bank agree with what you were already looking at.
-- ---------------------------------------------------------------------------

local function GroupSnapshot(snap, mode)
    local groups, index = {}, {}
    local function Bucket(key, title)
        local bucket = index[key]
        if not bucket then
            bucket = { key = key, title = title, rows = {}, slots = {} }
            index[key] = bucket
            groups[#groups + 1] = bucket
        end
        return bucket
    end

    if mode == "NONE" then
        local bucket = Bucket("ALL", "Vault")
        for position = 1, #snap.slots do
            bucket.rows[#bucket.rows + 1] = snap.rows[position] or false
            bucket.slots[#bucket.slots + 1] = snap.slots[position]
        end
        return groups
    end

    for _, section in ipairs(V.OrderedSections()) do
        for _, row in ipairs(snap.items) do
            if row.section == section.key then
                local key, title = section.key, section.title
                if mode == "DETAIL" then
                    local sub = V.SubgroupOf(row)
                    if sub then
                        key = section.key .. ":" .. sub
                        title = sub
                    end
                end
                local bucket = Bucket(key, title)
                bucket.rows[#bucket.rows + 1] = row
                bucket.slots[#bucket.slots + 1] = { bag = row.bag, slot = row.slot }
            end
        end
    end

    local compare = V.Comparators[DB().SortOrder or "CATEGORY"] or V.Comparators.QUALITY
    for _, bucket in ipairs(groups) do
        -- The slot each row came from has to travel with it, or a sorted
        -- display would hand every click the wrong container
        local paired = {}
        for position, row in ipairs(bucket.rows) do
            paired[position] = { row = row, slot = bucket.slots[position] }
        end
        table.sort(paired, function(a, b) return compare(a.row, b.row) end)
        for position, entry in ipairs(paired) do
            bucket.rows[position] = entry.row
            bucket.slots[position] = entry.slot
        end
    end

    if DB().ShowSlotCounts then
        local free = Bucket("FREE", "Free Space")
        for position = 1, #snap.slots do
            if not snap.rows[position] then
                free.rows[#free.rows + 1] = false
                free.slots[#free.slots + 1] = snap.slots[position]
            end
        end
        if #free.rows == 0 then
            for i, bucket in ipairs(groups) do
                if bucket.key == "FREE" then table.remove(groups, i) break end
            end
        end
    end
    return groups
end

-- ---------------------------------------------------------------------------
-- Laying a grid out
--
-- Returns the height consumed, so the caller can stack a second grid (the
-- carried bags) under the first without either of them knowing about the other.
-- ---------------------------------------------------------------------------

local function LayoutGroups(parent, groups, buttonPool, headerPool, topOffset, hideMisses, actionable)
    local db = DB()
    local columns = V.GridColumns()
    local size, gap = Metrics()
    local step = size + gap
    local y = topOffset
    local buttonIndex, headerIndex = 0, 0
    local shown, hidden = 0, 0

    for _, bucket in ipairs(groups) do
        -- Under Hide the rest, a section whose every item was filtered out
        -- should not leave a lonely header behind
        local visible = {}
        for position, row in ipairs(bucket.rows) do
            local match = true
            if row and not V.QueryIsEmpty(query) then
                match = V.MatchRow(row, query)
            elseif not row and not V.QueryIsEmpty(query) then
                match = false
            end
            if match then shown = shown + 1 else hidden = hidden + 1 end
            if match or not hideMisses then
                visible[#visible + 1] = { row = row, slot = bucket.slots[position], dim = not match }
            end
        end
        if #visible > 0 then
            headerIndex = headerIndex + 1
            local header = AcquireHeader(headerPool, parent, headerIndex)
            header.groupKey = bucket.key
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, -y)
            header:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
            local collapsed = db.Collapsed and db.Collapsed[bucket.key]
            local title = bucket.title
            if V.IsUserSection(bucket.key) then
                title = Skin().gold .. title .. "|r"
            end
            header.label:SetText((collapsed and "|cff888888+|r " or "") .. title)
            header.count:SetText(string.format("%d", #visible))
            local skin = Skin()
            header.label:SetTextColor(unpack(skin.heading))
            header.count:SetTextColor(unpack(skin.subtle))
            header.line:SetColorTexture(unpack(skin.rule))
            header:Show()
            y = y + HEADER_H

            if not collapsed then
                for position, entry in ipairs(visible) do
                    buttonIndex = buttonIndex + 1
                    local button = Acquire(buttonPool, parent, buttonIndex)
                    button:SetParent(parent)
                    local column = (position - 1) % columns
                    local rowIndex = math.floor((position - 1) / columns)
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", parent, "TOPLEFT",
                        PAD + column * step, -(y + rowIndex * step))
                    PaintButton(button, entry.row or nil, entry.slot, entry.dim, actionable)
                end
                local rows = math.ceil(#visible / columns)
                y = y + rows * step
            end
            y = y + 6
        end
    end

    for index = buttonIndex + 1, #buttonPool do buttonPool[index]:Hide() end
    for index = headerIndex + 1, #headerPool do headerPool[index]:Hide() end
    return y, shown, hidden
end

-- ---------------------------------------------------------------------------
-- The report view
-- ---------------------------------------------------------------------------

local SEVERITY_COLOR = {
    [3] = { 1, 0.45, 0.4 },
    [2] = { 1, 0.82, 0.4 },
    [1] = { 0.6, 0.85, 1 },
}

local function AcquireReportRow(index)
    local row = reportRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, reportChild)
    row:SetPoint("LEFT", reportChild, "LEFT", PAD, 0)
    row:SetPoint("RIGHT", reportChild, "RIGHT", -PAD, 0)
    row:SetHeight(42)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetTexture(QUAD)
    row.stripe:SetVertexColor(1, 1, 1, 0.03)
    row.pip = row:CreateTexture(nil, "ARTWORK")
    row.pip:SetTexture(QUAD)
    row.pip:SetWidth(3)
    row.pip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    row.pip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    row.title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -4)
    row.title:SetJustifyH("LEFT")
    row.detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    row.detail:SetJustifyH("LEFT")
    row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.action:SetSize(70, 20)
    row.action:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.action:Hide()
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.06)
    row:SetHighlightTexture(highlight)
    reportRows[index] = row
    return row
end

local function ShowGridWithSearch(text)
    searchText = text or ""
    query = V.ParseQuery(searchText)
    if frame and frame.searchBox then
        frame.searchBox:SetText(searchText)
    end
    DB().View = "GRID"
    V.Refresh()
end

local function LayoutReport(findings)
    local y = 4
    for index, finding in ipairs(findings) do
        local row = AcquireReportRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", reportChild, "TOPLEFT", PAD, -y)
        row:SetPoint("RIGHT", reportChild, "RIGHT", -PAD, 0)
        local color = SEVERITY_COLOR[finding.severity] or SEVERITY_COLOR[1]
        row.pip:SetVertexColor(color[1], color[2], color[3], 0.9)
        row.title:SetText(finding.title)
        row.title:SetTextColor(color[1], color[2], color[3])
        row.detail:SetText(finding.detail or "")
        row.finding = finding
        row:SetScript("OnClick", function(self)
            if self.finding.search then
                ShowGridWithSearch(self.finding.search)
            end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.finding.title, 1, 1, 1)
            if self.finding.search then
                GameTooltip:AddLine("Click to show these in the vault.", 0.6, 0.8, 0.6)
            end
            local count = self.finding.rows and #self.finding.rows or 0
            if count > 0 then
                GameTooltip:AddLine(" ")
                for position = 1, math.min(count, 12) do
                    local item = self.finding.rows[position]
                    GameTooltip:AddLine((item.name or "…") ..
                        ((item.count or 1) > 1 and (" x" .. item.count) or ""), 0.8, 0.8, 0.85)
                end
                if count > 12 then
                    GameTooltip:AddLine(string.format("…and %d more", count - 12), 0.5, 0.5, 0.55)
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if finding.action == "SORT" then
            row.action:SetText("Sort")
            row.action:SetScript("OnClick", function() CommanderVault_SortBank() end)
            row.action:SetShown(V.IsBankOpen())
        elseif finding.action == "WITHDRAW_JUNK" then
            row.action:SetText("Withdraw")
            row.action:SetScript("OnClick", function()
                CommanderVault_Withdraw(function(item)
                    return item.quality == 0 and not item.noValue
                end, "withdrew the junk")
            end)
            row.action:SetShown(V.IsBankOpen())
        elseif finding.action == "DEPOSIT" then
            row.action:SetText("Deposit")
            row.action:SetScript("OnClick", function()
                CommanderVault_Deposit(V.DepositPredicate(V.DEPOSIT_RULES.KNOWN), "deposited")
            end)
            row.action:SetShown(V.IsBankOpen())
        else
            row.action:Hide()
        end
        row:Show()
        y = y + 46
    end
    for index = #findings + 1, #reportRows do reportRows[index]:Hide() end
    -- A report with no findings used to render as an empty panel, which reads
    -- as broken rather than as good news
    if #findings == 0 then
        if not reportChild.emptyFS then
            reportChild.emptyFS = reportChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            reportChild.emptyFS:SetPoint("TOP", reportChild, "TOP", 0, -40)
            reportChild.emptySub = reportChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            reportChild.emptySub:SetPoint("TOP", reportChild.emptyFS, "BOTTOM", 0, -6)
        end
        reportChild.emptyFS:SetText("|cff66cc66Nothing to report.|r")
        reportChild.emptySub:SetText("No junk, no split stacks, no gear you cannot use, nothing gathering dust.")
        reportChild.emptyFS:Show()
        reportChild.emptySub:Show()
        y = y + 90
    elseif reportChild.emptyFS then
        reportChild.emptyFS:Hide()
        reportChild.emptySub:Hide()
    end
    -- View state worth naming: "the report is showing good news" is a
    -- different thing from "the report drew nothing"
    V.reportEmpty = (#findings == 0)
    return y
end

-- ---------------------------------------------------------------------------
-- Bank bag slots
--
-- The stock window's entire bag apparatus, which this one had shrunk to seven
-- 26px squares in a corner carrying a dark red plus sign: seven real sockets,
-- the empty-bag art the client ships, red tinting on the slots you have not
-- bought, how full each bag you HAVE bought is, and the stock purchase row —
-- label, running price, button — underneath.
--
-- The gestures are the stock window's, plus one: a bought slot you click with
-- an empty cursor isolates that bag in the grid, which is this window's answer
-- to "open the bag" now that every bag is already on screen.
-- ---------------------------------------------------------------------------

local BAG_SLOT = 32
local BAG_GAP = 8
local EMPTY_BAG_ART = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function InventoryIDFor(bag)
    if C_Container and C_Container.ContainerIDToInventoryID then
        return C_Container.ContainerIDToInventoryID(bag)
    end
    if ContainerIDToInventoryID then return ContainerIDToInventoryID(bag) end
    return nil
end

-- V.Money paints its own gold/silver/copper colours, which is right nearly
-- everywhere and wrong here: the stock window turns the whole price red when
-- you cannot afford it, and an embedded colour code cannot be overruled from
-- outside. So the unaffordable case gets its own formatting rather than a
-- wrapper that would do nothing.
local function RedMoney(copper)
    copper = math.floor(copper or 0)
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100
    if gold > 0 then return string.format("|cffff4030%dg %ds|r", gold, silver) end
    if silver > 0 then return string.format("|cffff4030%ds %dc|r", silver, bronze) end
    return string.format("|cffff4030%dc|r", bronze)
end

-- Cost of the NEXT slot. GetBankSlotCost wants the number already purchased,
-- and GetNumBankSlots's second return is the only honest answer to "is there
-- another one to buy" — seven is not a number to hard-code when the client
-- ships NUM_BANKBAGSLOTS.
local function NextSlotCost()
    if not GetNumBankSlots then return nil, true, 0 end
    local purchased, full = GetNumBankSlots()
    purchased = purchased or 0
    if full then return nil, true, purchased end
    local cost = GetBankSlotCost and GetBankSlotCost(purchased) or nil
    return cost, false, purchased
end

-- The client's own confirmation, primed first.
--
-- CONFIRM_BUY_BANK_SLOT's OnShow does not ask the API for the price: it reads
-- BankFrame.nextSlotCost, a field only BankFrame's own PLAYER_MONEY handler
-- ever writes. Raise the popup from anywhere else and it can arrive holding
-- nil, which takes MoneyFrame_Update down with it. Writing the field first is
-- one API call and removes the whole class of failure. (The takeover leaves
-- BankFrame shown, so it usually HAS run — "usually" is not a guarantee worth
-- shipping an error for.)
local function BuyNextSlot()
    if not V.IsBankOpen() then
        print("Commander Vault: buying a bag slot needs a banker")
        return
    end
    local cost, full = NextSlotCost()
    if full then
        print("Commander Vault: every bank bag slot is already bought")
        return
    end
    if cost and BankFrame then BankFrame.nextSlotCost = cost end
    if cost and GetMoney and GetMoney() < cost then
        print("Commander Vault: the next slot costs " .. V.Money(cost)
            .. " — you are " .. V.Money(cost - GetMoney()) .. " short")
        return
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    end
    if StaticPopup_Show then
        StaticPopup_Show("CONFIRM_BUY_BANK_SLOT")
    elseif PurchaseSlot then
        PurchaseSlot()
    end
end

-- Clicking a bought slot narrows the grid to that container and clicking it
-- again lets go, so the rack doubles as a filter bar. It goes through the
-- search box rather than a private flag on purpose: bag:N is already a term
-- the query language understands, so it composes with everything else you
-- might be looking for and it is visible in the box that caused it.
local function IsolateBag(bag)
    local term = "bag:" .. tostring(bag)
    ShowGridWithSearch(searchText == term and "" or term)
end

local function BagFill(bag)
    if not C_Container or not C_Container.GetContainerNumSlots then return nil end
    local total = C_Container.GetContainerNumSlots(bag) or 0
    if total == 0 then return nil end
    local free = C_Container.GetContainerNumFreeSlots and C_Container.GetContainerNumFreeSlots(bag) or 0
    return total - (free or 0), total
end

local function BagSlotTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not self.purchased then
        GameTooltip:SetText(BANK_BAG_PURCHASE or "Purchase Bank Bag Slot", 1, 0.5, 0.4)
        local cost = NextSlotCost()
        if self.isNextToBuy and cost then
            GameTooltip:AddLine("Click to buy this slot for " .. V.Money(cost) .. ".", 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine("Slots are bought in order, left to right.", 0.7, 0.7, 0.7)
        end
        if not V.IsBankOpen() then
            GameTooltip:AddLine("You are not at a banker.", 0.8, 0.5, 0.4)
        end
        GameTooltip:Show()
        return
    end

    local invID = self.invID
    local filled = false
    if invID and GameTooltip.SetInventoryItem then
        filled = GameTooltip:SetInventoryItem("player", invID) and true or false
    end
    if not filled then
        GameTooltip:SetText(BANK_BAG or "Bank Bag", 1, 1, 1)
        -- "Empty" is only an honest claim at a banker. The container API
        -- answers for bank containers between BANKFRAME_OPENED and
        -- BANKFRAME_CLOSED and nowhere else, so away from one the right answer
        -- is that nobody can see, not that there is nothing there.
        if V.IsBankOpen() then
            GameTooltip:AddLine("Empty — drop a bag here, or drag one in from your inventory.",
                0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine("What is in this slot is only readable at a banker.",
                0.7, 0.7, 0.75, true)
        end
    else
        local used, total = BagFill(self.bag)
        if total then
            GameTooltip:AddLine(string.format("%d of %d slots used", used, total), 0.7, 0.85, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to show only this bag.", 0.7, 0.7, 0.75)
    if V.IsBankOpen() then
        GameTooltip:AddLine("Right-click or drag to take the bag off the slot.", 0.7, 0.7, 0.75)
    end
    GameTooltip:Show()
end

local function BagSlotClick(self, mouseButton)
    if not self.purchased then
        BuyNextSlot()
        return
    end
    local invID = self.invID
    if mouseButton == "RightButton" then
        if not V.IsBankOpen() then
            print("Commander Vault: taking a bag off its slot needs a banker")
        elseif invID and PickupBagFromSlot then
            PickupBagFromSlot(invID)
        end
        return
    end
    if V.IsBankOpen() and invID and CursorHasItem and CursorHasItem() then
        if PutItemInBag then PutItemInBag(invID) end
        return
    end
    IsolateBag(self.bag)
end

-- Both painters live here rather than inside RefreshBagSlots: that function
-- runs on every container event, and a closure rebuilt per deposit is garbage
-- nobody asked for.
local function PaintSocket(texture, button)
    if IsBankStyle() then
        texture:SetTexture(BANK_PARTS)
        texture:SetTexCoord(unpack(BANK_SOCKET_TC))
        texture:SetVertexColor(1, 1, 1, 1)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", -5, 4)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -6)
    else
        texture:SetTexture(QUAD)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetVertexColor(0, 0, 0, 0.5)
        texture:ClearAllPoints()
        texture:SetAllPoints()
    end
end

local function PaintIsolationRing(button)
    if searchText == "bag:" .. tostring(button.bag) then
        button.ring:ClearAllPoints()
        button.ring:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
        button.ring:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
        button.ring:SetVertexColor(1, 0.85, 0.3, 0.35)
        button.ring:Show()
    else
        button.ring:Hide()
    end
end

local function BuildBagSlots()
    if frame.bagSlots then return frame.bagSlots end

    local rack = CreateFrame("Frame", nil, frame)
    rack:SetHeight(BAG_SLOT + 8)
    rack:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 8, 12)
    rack:SetWidth((BAG_SLOT + BAG_GAP) * 8 + 8)
    frame.bagRack = rack

    local slots = {}
    local first, last = V.BankBagRange()
    local previous

    -- The vault's own 28 slots get a socket at the head of the rack. They are
    -- not a bag and cannot be bought, but they ARE a container, and without
    -- one here the rack is a filter bar that cannot select the biggest thing
    -- in the window.
    local base = CreateFrame("Button", "CommanderVaultBaseSlots", rack)
    base:SetSize(BAG_SLOT, BAG_SLOT)
    base:SetPoint("LEFT", rack, "LEFT", 0, 0)
    base.bag = BANK_CONTAINER or -1
    base.socket = base:CreateTexture(nil, "BACKGROUND")
    base.label = base:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    base.label:SetPoint("CENTER")
    base.ring = base:CreateTexture(nil, "OVERLAY")
    base.ring:SetTexture(QUAD)
    base.ring:Hide()
    local baseHighlight = base:CreateTexture(nil, "HIGHLIGHT")
    baseHighlight:SetAllPoints()
    baseHighlight:SetTexture(QUAD)
    baseHighlight:SetVertexColor(1, 1, 1, 0.2)
    base:SetHighlightTexture(baseHighlight)
    base:SetScript("OnClick", function(self) IsolateBag(self.bag) end)
    base:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ITEMSLOTTEXT or "Item Slots", 1, 1, 1)
        GameTooltip:AddLine("The vault's own slots — the ones that came with it.",
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Click to show only these.", 0.7, 0.7, 0.75)
        GameTooltip:Show()
    end)
    base:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.baseSlot = base
    previous = base

    for bag = first, last do
        local button = CreateFrame("Button", "CommanderVaultBankBag" .. bag, rack)
        button:SetSize(BAG_SLOT, BAG_SLOT)
        -- A wider gap after the base socket: the vault's own slots and the
        -- bags you bolted onto it are different kinds of thing
        button:SetPoint("LEFT", previous, "RIGHT",
            previous == frame.baseSlot and (BAG_GAP + 8) or BAG_GAP, 0)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:RegisterForDrag("LeftButton")
        button.bag = bag
        button.bagIndex = bag - first + 1

        button.socket = button:CreateTexture(nil, "BACKGROUND")
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 1, -1)
        button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        button.ring = button:CreateTexture(nil, "OVERLAY")
        button.ring:SetTexture(QUAD)
        button.ring:Hide()

        button.fill = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        button.fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)

        local highlight = button:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(QUAD)
        highlight:SetVertexColor(1, 1, 1, 0.2)
        button:SetHighlightTexture(highlight)

        button:SetScript("OnEnter", BagSlotTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnClick", BagSlotClick)
        button:SetScript("OnDragStart", function(self)
            if self.purchased and V.IsBankOpen() and self.invID and PickupBagFromSlot then
                PickupBagFromSlot(self.invID)
            end
        end)
        button:SetScript("OnReceiveDrag", function(self)
            if self.purchased and V.IsBankOpen() and self.invID and PutItemInBag then
                PutItemInBag(self.invID)
            end
        end)

        slots[#slots + 1] = button
        previous = button
    end
    frame.bagSlots = slots

    -- The stock purchase row: label, price, button. Hidden outright when every
    -- slot is bought, because a disabled Purchase invites the question of what
    -- would enable it.
    local buy = CreateFrame("Frame", nil, frame)
    buy:SetHeight(BAG_SLOT)
    buy:SetPoint("LEFT", rack, "RIGHT", 16, 0)
    buy:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
    frame.buyRow = buy

    buy.button = CreateFrame("Button", nil, buy, "UIPanelButtonTemplate")
    buy.button:SetSize(96, 22)
    -- Pinned to the right edge rather than the left: the window resizes, and
    -- of the two things on this row it is the price that can afford to be
    -- clipped
    buy.button:SetPoint("RIGHT", buy, "RIGHT", 0, 0)
    buy.button:SetText(BANKSLOTPURCHASE or "Purchase")
    buy.button:SetScript("OnClick", BuyNextSlot)
    buy.button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(BANKSLOTPURCHASE_LABEL or "Buy Bank Slot", 1, 1, 1)
        local cost, full, purchased = NextSlotCost()
        if full then
            GameTooltip:AddLine("You own every bank bag slot.", 0.6, 0.85, 0.6)
        elseif cost then
            GameTooltip:AddLine(string.format("Slot %d of %d.", (purchased or 0) + 1,
                (NUM_BANKBAGSLOTS or 7)), 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Costs " .. V.Money(cost) .. ".", 0.8, 0.8, 0.8)
            if GetMoney and GetMoney() < cost then
                GameTooltip:AddLine("You cannot afford it yet.", 1, 0.4, 0.35)
            end
        end
        GameTooltip:Show()
    end)
    buy.button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    buy.cost = buy:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    buy.cost:SetPoint("RIGHT", buy.button, "LEFT", -10, 0)
    buy.cost:SetJustifyH("RIGHT")

    -- The rack is built lazily, which means it can come into being AFTER the
    -- framing has already run and decided where the bottom strip sits. One
    -- forced re-frame puts it where the style wants it; ApplyFraming's own
    -- early-out means this never happens twice.
    if frame._framedAs then ApplyFraming(true) end

    return slots
end

-- `mine` is passed in rather than worked out here: the rack is about YOUR
-- bank, and browsing an alt's remembered vault must not offer to spend your
-- gold on a slot the grid is not even showing.
local function RefreshBagSlots(mine)
    local slots = BuildBagSlots()
    local cost, full, purchased = NextSlotCost()
    local open = V.IsBankOpen()

    frame.bagRack:SetShown(mine ~= false)
    -- Dimmed away from a banker, because most of what the rack can do needs
    -- one: only the isolate filter still works on a remembered vault
    frame.bagRack:SetAlpha(open and 1 or 0.6)

    local base = frame.baseSlot
    PaintSocket(base.socket, base)
    base.label:SetText("|cffe8dcc8" .. tostring(NUM_BANKGENERIC_SLOTS or 28) .. "|r")
    PaintIsolationRing(base)

    for _, button in ipairs(slots) do
        button.purchased = button.bagIndex <= (purchased or 0)
        button.isNextToBuy = (button.bagIndex == (purchased or 0) + 1)
        button.invID = InventoryIDFor(button.bag)

        PaintSocket(button.socket, button)

        local texture = button.invID and GetInventoryItemTexture
            and GetInventoryItemTexture("player", button.invID)
        button.icon:SetTexture(texture or EMPTY_BAG_ART)
        button.icon:Show()

        if not button.purchased then
            -- The stock window's own signal for an unbought slot: the empty
            -- bag art, in red. It reads at a glance and it reads the same way
            -- it does in every other bank window the player has ever opened.
            button.icon:SetVertexColor(1, 0.1, 0.1)
            button.icon:SetAlpha(button.isNextToBuy and 0.95 or 0.5)
            button.fill:SetText("")
        else
            button.icon:SetVertexColor(1, 1, 1)
            button.icon:SetAlpha(texture and 1 or 0.35)
            local used, total = BagFill(button.bag)
            if texture and total then
                button.fill:SetText(string.format("|cff%s%d|r",
                    used >= total and "ff7d6b" or "d8d8d8", total - used))
            else
                button.fill:SetText("")
            end
        end

        -- The isolate filter is state worth seeing: the slot the grid is
        -- currently narrowed to wears a ring, so "why am I only seeing six
        -- things" always has a visible answer.
        PaintIsolationRing(button)
    end

    -- Purchase is offered only where it can be taken: your own vault, a banker
    -- in front of you, and a slot left to buy.
    local offer = (mine ~= false) and open and not full and cost ~= nil
    frame.buyRow:SetShown(offer)
    if offer then
        local affordable = not GetMoney or GetMoney() >= cost
        frame.buyRow.cost:SetText(string.format("%s  %s",
            (BANKSLOTPURCHASE_LABEL or "Buy Bank Slot"),
            affordable and V.Money(cost) or RedMoney(cost)))
        frame.buyRow.cost:SetTextColor(unpack(Skin().subtle))
        frame.buyRow.button:SetEnabled(affordable)
    end
end

-- ---------------------------------------------------------------------------
-- The roster
--
-- Every character who has stood at a banker left a snapshot behind. Selecting
-- one swaps the grid over to that vault: same sections, same search, same
-- everything — read-only, because you are not standing in it.
-- ---------------------------------------------------------------------------

-- Guild banks wear the same record shape as characters on purpose, so the
-- roster and the read-only browser need to know nothing about them
local function RosterRecords()
    local list = {}
    for _, record in ipairs(V.AllRecords()) do list[#list + 1] = record end
    if V.AllGuildRecords and DB().TrackGuildBank ~= false then
        for _, record in ipairs(V.AllGuildRecords()) do list[#list + 1] = record end
    end
    return list
end

local function SelectedRecord()
    local key = DB().RosterChar
    if not key then return nil end
    for _, record in ipairs(RosterRecords()) do
        if record.key == key and not record.isPlayer then return record end
    end
    return nil
end

-- What the grid is drawing: an alt's remembered vault when one is selected,
-- your own live-or-remembered one otherwise.
local function ActiveSnapshot()
    local record = SelectedRecord()
    if record then return V.RecordSnapshot(record), record end
    return V.CurrentBank(), nil
end

local function Ago(stamp)
    local age = (stamp and stamp > 0) and (time() - stamp) or nil
    if not age then return "never" end
    if age < 3600 then return string.format("%d min", math.max(1, math.floor(age / 60))) end
    if age < 86400 then return string.format("%d hr", math.floor(age / 3600)) end
    return string.format("%d days", math.floor(age / 86400))
end

local function AcquireRosterRow(index)
    local row = rosterRows[index]
    if row then return row end
    row = CreateFrame("Button", nil, reportChild)
    row:SetHeight(34)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetTexture(QUAD)
    row.stripe:SetVertexColor(1, 1, 1, index % 2 == 0 and 0.03 or 0)
    row.pip = row:CreateTexture(nil, "ARTWORK")
    row.pip:SetTexture(QUAD)
    row.pip:SetWidth(3)
    row.pip:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    row.pip:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 10, 6)
    row.name:SetJustifyH("LEFT")
    row.note = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.note:SetPoint("LEFT", row, "LEFT", 10, -8)
    row.note:SetJustifyH("LEFT")
    row.count = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.count:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    row.count:SetJustifyH("RIGHT")
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(QUAD)
    highlight:SetVertexColor(1, 1, 1, 0.06)
    row:SetHighlightTexture(highlight)
    rosterRows[index] = row
    return row
end

local function LayoutRoster()
    local records = RosterRecords()
    local onlyRealm = DB().RosterCurrentRealmOnly
    local myRealm = select(2, V.CharKey())
    local y, index = 4, 0
    for _, record in ipairs(records) do
        if not (onlyRealm and record.realm and record.realm ~= myRealm) then
            index = index + 1
            local row = AcquireRosterRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", reportChild, "TOPLEFT", PAD, -y)
            row:SetPoint("RIGHT", reportChild, "RIGHT", -PAD, 0)
            local color = record.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[record.class]
            if record.isGuild then
                row.pip:SetVertexColor(0.25, 0.85, 0.55, 0.9)
            else
                row.pip:SetVertexColor(color and color.r or 0.7, color and color.g or 0.7,
                    color and color.b or 0.75, 0.9)
            end
            local selected = (DB().RosterChar == record.key)
            row.name:SetText((selected and "|cffffd200> |r" or "") .. (record.name or "?")
                .. (record.isPlayer and "  |cff888888(you)|r" or "")
                .. (record.isGuild and "  |cff888888(guild)|r" or ""))
            if record.isGuild then
                row.name:SetTextColor(0.4, 0.9, 0.6)
            elseif color then
                row.name:SetTextColor(color.r, color.g, color.b)
            end
            local items = record.items and #record.items or 0
            if record.isGuild then
                -- A guild bank is only ever as complete as the tabs you have
                -- opened, and saying so is the difference between "the guild
                -- has none" and "I have not looked"
                local tabs = record.tabCount or 0
                row.note:SetText(string.format("%d of %s %s read · seen %s ago",
                    record.scannedTabs or 0, tabs > 0 and tabs or "?",
                    (record.scannedTabs == 1) and "tab" or "tabs", Ago(record.at)))
            else
                row.note:SetText(string.format("%s · %d/%d slots free · seen %s ago",
                    record.realm or "?", record.free or 0, record.total or 0, Ago(record.at)))
            end
            row.count:SetText(string.format("|cffffffff%d|r stacks", items))
            row.record = record
            row:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "RightButton" then
                    if self.record.isPlayer then
                        print("Commander Vault: use Forget Snapshot in the settings for this character")
                        return
                    end
                    if self.record.isGuild then
                        V.ForgetGuild(self.record.key)
                        if DB().RosterChar == self.record.key then DB().RosterChar = nil end
                        print("Commander Vault: forgot the " .. (self.record.name or "?") .. " guild bank")
                        V.Refresh()
                        return
                    end
                    V.ForgetCharacter(self.record.key)
                    if DB().RosterChar == self.record.key then DB().RosterChar = nil end
                    print("Commander Vault: forgot " .. (self.record.name or "?"))
                    V.Refresh()
                    return
                end
                -- Your own row is the way back: selecting it clears the alt
                DB().RosterChar = (not self.record.isPlayer) and self.record.key or nil
                DB().View = "GRID"
                V.Refresh()
            end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.record.name or "?", 1, 1, 1)
                GameTooltip:AddLine("Click to browse this vault.", 0.6, 0.8, 0.6)
                if not self.record.isPlayer then
                    GameTooltip:AddLine("Right-click to forget it.", 0.8, 0.6, 0.6)
                end
                if self.record.isGuild then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Tabs are recorded as you open them. /cvault guild reads them all at once, with the guild bank open.", 0.7, 0.7, 0.75, true)
                end
                if self.record.money then
                    GameTooltip:AddLine("Carried " .. V.Money(self.record.money), 0.8, 0.75, 0.5)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:Show()
            y = y + 38
        end
    end
    for position = index + 1, #rosterRows do rosterRows[position]:Hide() end
    return y
end

-- ---------------------------------------------------------------------------
-- Drag and drop
-- ---------------------------------------------------------------------------

-- Dropping an item anywhere on the window deposits it into the first free
-- vault slot. Deliberately only ever the FIRST FREE one: dropping onto a
-- window is a coarse gesture, and a drop that displaced something would be a
-- coarse gesture with consequences.
local function DropIntoVault()
    if not CursorHasItem() then return end
    if not V.IsBankOpen() then
        print("Commander Vault: nothing to drop into — you are not at a banker")
        return
    end
    if SelectedRecord() then
        print("Commander Vault: that is an alt's vault, not yours")
        return
    end
    local snap = V.CurrentBank()
    for index = 1, #snap.slots do
        if not snap.rows[index] then
            local position = snap.slots[index]
            C_Container.PickupContainerItem(position.bag, position.slot)
            V.ScheduleRefresh()
            return
        end
    end
    print("Commander Vault: the vault is full")
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

-- How many columns the window is currently wide enough for.
--
-- Columns are read OFF the window rather than dictated to it. The width the
-- player dragged is the honest statement of how wide they want the grid, and a
-- Columns setting that disagreed with it would spend the whole drag fighting
-- the grip. The setting still decides the width of a window that has never
-- been dragged, and Reset Size hands the decision back to it.
function V.GridColumns()
    local size, gap = Metrics()
    local width = frame and frame:GetWidth() or 0
    if width <= 0 then return DB().Columns or 14 end
    local inner = width - PAD * 2 - 30
    return math.max(4, math.floor((inner + gap) / (size + gap)))
end

local function DefaultWidth()
    local size, gap = Metrics()
    return PAD * 2 + (DB().Columns or 14) * (size + gap) - gap + 30
end

V.DefaultVaultWidth = DefaultWidth

local function ApplyGeometry()
    local db = DB()
    local width = math.max(MIN_W, math.min(MAX_W, db.FrameW or DefaultWidth()))
    local height = math.max(MIN_H, math.min(MAX_H, db.FrameH or 520))
    frame:SetSize(width, height)
    frame:SetScale(db.FrameScale or 1)
end

function V.Refresh()
    if not frame or not frame:IsShown() then return end
    local db = DB()
    ApplyGeometry()

    local snap, owner = ActiveSnapshot()
    wipe(pendingItems)
    if snap.pending then
        for _, row in ipairs(snap.items) do
            if not row.full then pendingItems[row.itemID] = true end
        end
    end
    local view = db.View or "GRID"
    local reportOn = db.ShowAdvisor ~= false
    -- Tallied up front rather than at the footer, because the grid's empty
    -- state has to tell "this vault holds nothing" apart from "nothing was
    -- ever recorded" and the summary is the only thing that knows
    local summary = V.Summary(snap)

    frame.tabReport:SetShown(reportOn)
    if view == "REPORT" and not reportOn then view = "GRID" end
    -- An alt's vault is a picture: it cannot be sorted, deposited into, or
    -- usefully reported on, so the buttons that would lie are simply gone
    local mine = (owner == nil)

    scroll:SetShown(view == "GRID")
    reportScroll:SetShown(view ~= "GRID")
    frame.searchBox:SetShown(view == "GRID")
    frame.sortBtn:SetShown(view == "GRID" and mine)
    frame.depositBtn:SetShown(view == "GRID" and mine and V.IsBankOpen())
    frame.matsBtn:SetShown(view == "GRID" and mine and V.IsBankOpen())
    frame.withdrawBtn:SetShown(view == "GRID" and mine and V.IsBankOpen())
    local title = owner and ("Vault — " .. (owner.name or "?")) or "Vault"
    if frame.TitleText then frame.TitleText:SetText(title) end
    if frame.bankTitle then frame.bankTitle:SetText(title) end
    ApplyFraming()
    -- The dark well belongs to the LIST views. The grid's slots carry the
    -- client's own stone sockets, so on BANK it sits straight on the marble
    -- exactly as the stock bank's slots do; a well under it would be a dark
    -- rectangle covering the whole reason for the style.
    if frame.bankInset then
        frame.bankInset:SetShown(IsBankStyle() and view ~= "GRID")
    end

    if view == "GRID" then
        local hideMisses = (db.SearchMode or "DIM") == "HIDE" and not V.QueryIsEmpty(query)
        local groups = GroupSnapshot(snap, db.Grouping or "SECTION")
        -- The vault grid is live only when it is YOUR vault and you are
        -- standing in it; the carried grid is live whenever it is your own
        -- bags, which it always is
        local height, shown, hidden = LayoutGroups(scrollChild, groups, buttons, headers, 4,
            hideMisses, mine and V.IsBankOpen())
        if db.ShowCarried then
            V.ScanBags()
            local bagGroups = GroupSnapshot(V.bags, db.Grouping or "SECTION")
            for _, bucket in ipairs(bagGroups) do
                bucket.key = "BAG:" .. bucket.key
                bucket.title = "Carried · " .. bucket.title
            end
            height = LayoutGroups(scrollChild, bagGroups, bagButtons, bagHeaders, height + 10,
                hideMisses, mine)
        else
            for _, button in ipairs(bagButtons) do button:Hide() end
            for _, header in ipairs(bagHeaders) do header:Hide() end
        end
        -- An empty grid used to render as a blank pane, which reads as broken.
        -- The three ways it can be empty are three different pieces of news,
        -- and only one of them is a problem.
        local total = #snap.slots
        if not scrollChild.emptyFS then
            scrollChild.emptyFS = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            scrollChild.emptyFS:SetPoint("TOP", scrollChild, "TOP", 0, -50)
            scrollChild.emptySub = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            scrollChild.emptySub:SetPoint("TOP", scrollChild.emptyFS, "BOTTOM", 0, -8)
            scrollChild.emptySub:SetWidth(340)
            scrollChild.emptySub:SetJustifyH("CENTER")
        end
        local headline, detail, kind
        if total == 0 then
            kind = "UNRECORDED"
            headline = owner and "Nothing remembered for this character."
                or (Skin().gold .. "Nothing remembered yet.|r")
            detail = owner
                and "They have not stood at a banker with this module running."
                or "Visit a banker once and the vault is browsable, searchable and reportable from anywhere in the world."
        elseif shown == 0 and not V.QueryIsEmpty(query) then
            kind = "NO_MATCH"
            headline = Skin().gold .. "Nothing matches.|r"
            detail = "No item in this vault answers to \"" .. searchText .. "\"."
        elseif summary.items == 0 then
            kind = "EMPTY"
            headline = "|cff66cc66This vault is empty.|r"
            detail = string.format("All %d slots free.", total)
        end
        scrollChild.emptyFS:SetShown(headline ~= nil)
        scrollChild.emptySub:SetShown(headline ~= nil)
        if headline then
            scrollChild.emptyFS:SetTextColor(unpack(Skin().heading))
            scrollChild.emptyFS:SetText(headline)
            scrollChild.emptySub:SetText(detail)
            scrollChild.emptySub:SetTextColor(unpack(Skin().subtle))
            height = math.max(height, 130)
        end
        -- View state worth naming, the way the report's is: "the grid is
        -- empty because nothing was ever recorded" and "the grid is empty
        -- because the search excluded everything" are different claims
        V.gridEmpty = kind

        scrollChild:SetHeight(math.max(height + 10, 1))
        frame.matchFS:SetText(V.QueryIsEmpty(query) and ""
            or string.format("%s%d|r of %d", Skin().hi, shown, shown + hidden))
        frame.matchFS:SetTextColor(unpack(Skin().subtle))
    else
        -- Leaving the grid puts its pooled buttons away rather than relying on
        -- the hidden scroll frame to cover them: a pool left "shown" is a pool
        -- that lies to anything asking what is on screen
        for position = 1, #buttons do buttons[position]:Hide() end
        for position = 1, #headers do headers[position]:Hide() end
        for position = 1, #bagButtons do bagButtons[position]:Hide() end
        for position = 1, #bagHeaders do bagHeaders[position]:Hide() end
    end

    if view == "ROSTER" then
        for position = 1, #reportRows do reportRows[position]:Hide() end
        reportChild:SetHeight(math.max(LayoutRoster(), 1))
        frame.matchFS:SetText("")
    elseif view ~= "GRID" then
        for position = 1, #rosterRows do rosterRows[position]:Hide() end
        local findings = mine and V.BuildReport(snap, db.ShowCarried and V.bags or V.ScanBags()) or {}
        local height = LayoutReport(findings)
        reportChild:SetHeight(math.max(height, 1))
        frame.matchFS:SetText("")
    else
        for position = 1, #reportRows do reportRows[position]:Hide() end
        for position = 1, #rosterRows do rosterRows[position]:Hide() end
    end

    local hi = Skin().hi
    local parts = {}
    parts[#parts + 1] = string.format("%s%d|r items", hi, summary.items)
    if summary.total > 0 then
        parts[#parts + 1] = string.format("%s%d|r/%d free", hi, summary.free, summary.total)
    end
    if summary.value > 0 then
        parts[#parts + 1] = V.Money(summary.value)
    end
    if owner then
        parts[#parts + 1] = Skin().gold .. (owner.name or "?") .. "'s vault|r"
    end
    if summary.cached then
        local age = summary.at > 0 and (time() - summary.at) or 0
        local when = age < 3600 and string.format("%d min", math.max(1, math.floor(age / 60)))
            or (age < 86400 and string.format("%d hr", math.floor(age / 3600))
            or string.format("%d days", math.floor(age / 86400)))
        parts[#parts + 1] = "|cff888888remembered " .. when .. " ago|r"
    end
    frame.footerFS:SetText(table.concat(parts, "  ·  "))
    frame.footerFS:SetTextColor(unpack(Skin().subtle))

    -- Go to Bank (1.2.0): your own vault, remembered, away from a banker.
    -- An alt's remembered vault is not a place you can open from here.
    if frame.goBank then
        local away = summary.cached and mine ~= false and not V.IsBankOpen()
        frame.goBank:SetShown(away and true or false)
        if away and frame.goBank.Refresh then frame.goBank:Refresh() end
    end

    RefreshBagSlots(mine)

    frame.tabGrid:SetEnabled(view ~= "GRID")
    frame.tabReport:SetEnabled(view ~= "REPORT")
    frame.tabRoster:SetEnabled(view ~= "ROSTER")
end

-- Container events arrive in clusters — one per moved item, several per
-- deposit — so the refresh is coalesced onto the next frame rather than run
-- once per event.
local function ScheduleRefresh()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0.05, function()
        pendingRefresh = false
        if V.IsBankOpen() then V.ScanBank() end
        V.Refresh()
    end)
end

V.ScheduleRefresh = ScheduleRefresh

-- ---------------------------------------------------------------------------
-- Window construction
-- ---------------------------------------------------------------------------

-- The relative point is stored too, because resizing re-anchors the window to
-- TOPLEFT/UIParent-BOTTOMLEFT so it grows away from the corner the cursor is
-- holding still. Restoring that with relativePoint = point would put the
-- window a screen-height away from where it was left. Positions saved before
-- this fall back to the old behaviour, which was right for how they were made.
local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        local scale = frame:GetScale() or 1
        DB().FramePos = { point = point, rel = relPoint, x = x * scale, y = y * scale }
    end
end

local function ApplyPosition()
    local db = DB()
    local scale = db.FrameScale or 1
    frame:SetScale(scale)
    if frame._dragging then return end
    frame:ClearAllPoints()
    local pos = db.FramePos
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.rel or pos.point,
            (pos.x or 0) / scale, (pos.y or 0) / scale)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    end
end

-- ---------------------------------------------------------------------------
-- Framing
--
-- BANK is the stock bank window's own dressing: light stone, the classic gold
-- dialog border, and the dialog header plate the era hangs every window title
-- on. WINDOW is the newer inset panel the rest of the suite's browsers use;
-- DARK is the suite's flat HUD panel.
--
-- The stone is the module's own tile rather than a borrowed file, because no
-- shipped file is that material; BANK_STONE carries the measurements.
--
-- Every region touched here is guarded: a future template that stops shipping
-- one of them must degrade to a plainer window, not to an error.
-- ---------------------------------------------------------------------------

local BANK_BACKDROP = {
    bgFile = BANK_STONE,
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 256, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}


local INSET_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function EnsureBankArt()
    if frame.bankArt then return frame.bankArt end

    local art = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    art:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
    if art.SetBackdrop then
        art:SetBackdrop(BANK_BACKDROP)
        art:SetBackdropColor(1, 1, 1, 1)
        art:SetBackdropBorderColor(1, 1, 1, 1)
    end
    frame.bankArt = art

    -- The era's title treatment: a carved plate straddling the top edge with
    -- the window's name cut into it
    local plate = art:CreateTexture(nil, "ARTWORK")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(256, 64)
    plate:SetPoint("TOP", frame, "TOP", 0, 12)
    frame.headerPlate = plate

    local title = art:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", plate, "TOP", 0, -14)
    frame.bankTitle = title

    local inset = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    inset:SetFrameLevel(math.max((frame:GetFrameLevel() or 1) - 1, 0))
    if inset.SetBackdrop then
        inset:SetBackdrop(INSET_BACKDROP)
        inset:SetBackdropColor(0, 0, 0, 0.55)
        inset:SetBackdropBorderColor(0.5, 0.45, 0.35, 1)
    end
    frame.bankInset = inset

    return art
end

function ApplyFraming(force)
    if not frame then return end
    local style = DB().FrameStyle or "BANK"
    -- Refresh runs on every container event; re-anchoring three panes and
    -- rebuilding a backdrop on each one is wasted work the player sees as
    -- flicker. Only an actual style change does the work.
    if not force and frame._framedAs == style then return end
    frame._framedAs = style
    local bank = (style == "BANK")

    -- The template's own dressing steps aside for the bank art -- ALL of it.
    --
    -- This list used to be four guessed names, and three of them do not exist
    -- on this client: BasicFrameTemplate here has no NineSlice and no Inset
    -- frame. What it does have is nine border pieces, a tiled title bar, a
    -- streak layer and a marble inset, none of which were being hidden -- so
    -- the "bank" window was wearing the template's steel frame with the bank's
    -- gold one somewhere behind it, and the two horizontal bars either side of
    -- the title were the template's TopTileStreaks showing past the header
    -- plate. The names below are taken from the client's own
    -- UIPanelTemplates.xml (BaseBasicFrameTemplate + BasicFrameTemplate +
    -- BasicFrameTemplateWithInset), and every one is still guarded: a template
    -- that stops shipping a region must degrade to a plainer window, never to
    -- an error.
    -- The list this window worked out now lives in the shared framework, so
    -- the Quest Log and the Notebook stop repeating the same wrong guess.
    Commander.UI.SetTemplateDressing(frame, not bank)

    if bank then
        EnsureBankArt()
        frame.bankArt:Show()
        frame.bankInset:Show()
        frame.headerPlate:Show()
        frame.bankTitle:Show()
    elseif frame.bankArt then
        frame.bankArt:Hide()
        frame.bankInset:Hide()
        frame.headerPlate:Hide()
        frame.bankTitle:Hide()
    end
    if not bank then
        Commander.UI.ApplyStyleBackdrop(frame, style == "DARK" and "DARK" or "NONE")
    else
        Commander.UI.ApplyStyleBackdrop(frame, "NONE")
    end

    -- The header plate eats the top of the window, so the toolbar drops below
    -- it; the classic border is thicker than the inset template's, so the
    -- content pulls in on every side.
    local top = bank and -42 or -28
    local side = bank and 16 or PAD
    frame.toolbar:ClearAllPoints()
    frame.toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", side, top)
    frame.toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -side, top)

    -- The bottom strip is two lines: the bag rack and its purchase row along
    -- the bottom, the vault's summary on the line above them. They used to
    -- share one line, which is why seven bag slots and a sentence about how
    -- much gold is in the vault were sitting on top of each other.
    local footInset = bank and 20 or (PAD + 2)
    if frame.bagRack then
        frame.bagRack:ClearAllPoints()
        frame.bagRack:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", footInset, bank and 14 or 10)
    end
    frame.footerFS:ClearAllPoints()
    frame.footerFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -footInset, bank and 56 or 52)
    -- Go to Bank: the footer line's left end, above the bag rack
    if frame.goBank then
        frame.goBank:ClearAllPoints()
        frame.goBank:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", footInset, bank and 56 or 52)
    end

    for _, pane in ipairs({ scroll, reportScroll }) do
        pane:ClearAllPoints()
        pane:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", bank and 6 or 0, -8)
        pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bank and -32 or -28,
            bank and 80 or 76)
    end
    if bank then
        frame.bankInset:ClearAllPoints()
        frame.bankInset:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
        frame.bankInset:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 26, -6)
    end
end

V.ApplyFraming = ApplyFraming

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "CommanderVaultFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    if frame.SetResizable then frame:SetResizable(true) end
    frame:Hide()
    if frame.TitleText then frame.TitleText:SetText("Vault") end
    if UISpecialFrames then table.insert(UISpecialFrames, "CommanderVaultFrame") end

    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
    drag:SetHeight(24)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        frame._dragging = true
        frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        frame._dragging = false
        SavePosition()
    end)

    local toolbar = CreateFrame("Frame", nil, frame)
    frame.toolbar = toolbar
    toolbar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -28)
    toolbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -28)
    toolbar:SetHeight(24)

    frame.tabGrid = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.tabGrid:SetSize(56, 22)
    frame.tabGrid:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    frame.tabGrid:SetText("Vault")
    frame.tabGrid:SetScript("OnClick", function()
        DB().View = "GRID"
        V.Refresh()
    end)

    frame.tabReport = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.tabReport:SetSize(64, 22)
    frame.tabReport:SetPoint("LEFT", frame.tabGrid, "RIGHT", 4, 0)
    frame.tabReport:SetText("Report")
    frame.tabReport:SetScript("OnClick", function()
        DB().View = "REPORT"
        V.Refresh()
    end)

    frame.tabRoster = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.tabRoster:SetSize(64, 22)
    frame.tabRoster:SetPoint("LEFT", frame.tabReport, "RIGHT", 4, 0)
    frame.tabRoster:SetText("Roster")
    frame.tabRoster:SetScript("OnClick", function()
        DB().View = "ROSTER"
        V.Refresh()
    end)
    frame.tabRoster:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Every vault you own", 1, 1, 1)
        GameTooltip:AddLine("One row per character who has stood at a banker with this module running. Click one to browse its vault from here.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.tabRoster:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.searchBox = CreateFrame("EditBox", "CommanderVaultSearchBox", toolbar, "InputBoxTemplate")
    frame.searchBox:SetHeight(20)
    -- Anchored on BOTH sides rather than given a width: the window resizes
    -- now, and a fixed 180px box meant the tabs and the Sort button climbed
    -- over each other the moment it was dragged narrow. The search is the one
    -- control here that is happy to be any size.
    frame.searchBox:SetPoint("LEFT", frame.tabRoster, "RIGHT", 14, 0)
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetMaxLetters(80)
    frame.searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        searchText = self:GetText() or ""
        query = V.ParseQuery(searchText)
        V.Refresh()
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        searchText = ""
        query = V.ParseQuery("")
        self:ClearFocus()
        V.Refresh()
    end)
    frame.searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local ghost = frame.searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ghost:SetPoint("LEFT", frame.searchBox, "LEFT", 4, 0)
    ghost:SetText("Search the vault")
    frame.searchBox:HookScript("OnTextChanged", function(self)
        ghost:SetShown((self:GetText() or "") == "")
    end)
    frame.searchBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Vault search", 1, 1, 1)
        GameTooltip:AddLine("Words narrow; a leading minus excludes.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("q:epic  q:>=rare      quality", 0.7, 0.85, 1)
        GameTooltip:AddLine("ilvl:>115             item level", 0.7, 0.85, 1)
        GameTooltip:AddLine("t:consumable          type or subtype", 0.7, 0.85, 1)
        GameTooltip:AddLine("s:head                equip slot", 0.7, 0.85, 1)
        GameTooltip:AddLine("old:60  new           days in the vault", 0.7, 0.85, 1)
        GameTooltip:AddLine("bag:5                 one container (the rack does this)", 0.7, 0.85, 1)
        GameTooltip:AddLine("boe  bop  usable  partial  set", 0.7, 0.85, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Ctrl+right-click an item to file it under a section of your own.", 0.7, 0.7, 0.75, true)
        GameTooltip:Show()
    end)
    frame.searchBox:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.matchFS = toolbar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.matchFS:SetPoint("LEFT", frame.searchBox, "RIGHT", 8, 0)

    frame.depositBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.depositBtn:SetSize(70, 22)
    frame.depositBtn:SetPoint("RIGHT", toolbar, "RIGHT", 0, 0)
    frame.depositBtn:SetText("Deposit")
    frame.depositBtn:SetScript("OnClick", function(self)
        if not V.IsBankOpen() then return end
        local menu = {}
        for _, key in ipairs({ "KNOWN", "MATS", "TRADE", "GEAR" }) do
            local rule = V.DEPOSIT_RULES[key]
            menu[#menu + 1] = {
                text = rule.label, notCheckable = true,
                func = function()
                    CommanderVault_Deposit(V.DepositPredicate(rule), "deposited")
                end,
            }
        end
        if not V.QueryIsEmpty(query) then
            local snapshot = query
            menu[#menu + 1] = {
                text = "Everything Matching the Search", notCheckable = true,
                func = function()
                    CommanderVault_Deposit(function(row)
                        return not row.isQuest and V.MatchRow(row, snapshot)
                    end, "deposited")
                end,
            }
        end
        if not frame.depositMenu then
            frame.depositMenu = CreateFrame("Frame", "CommanderVaultDepositMenu", frame, "UIDropDownMenuTemplate")
        end
        if EasyMenu then
            EasyMenu(menu, frame.depositMenu, self, 0, 0, "MENU")
        else
            -- No menu framework (a stripped client, or the harness): the most
            -- useful of the three rather than nothing at all
            CommanderVault_Deposit(V.DepositPredicate(V.DEPOSIT_RULES.KNOWN), "deposited")
        end
    end)

    -- The one deposit worth its own button: "put my mats away" is what most
    -- trips to the bank are, and a menu is one click too many for it
    frame.matsBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.matsBtn:SetSize(90, 22)
    frame.matsBtn:SetPoint("RIGHT", frame.depositBtn, "LEFT", 4, 0)
    frame.matsBtn:SetText("Deposit Mats")
    frame.matsBtn:SetScript("OnClick", function()
        if not V.IsBankOpen() then return end
        CommanderVault_Deposit(V.DepositPredicate(V.DEPOSIT_RULES.MATS), "mats deposited")
    end)
    frame.matsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(V.DEPOSIT_RULES.MATS.label, 1, 1, 1)
        GameTooltip:AddLine(V.DEPOSIT_RULES.MATS.tooltip, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.matsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.withdrawBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.withdrawBtn:SetSize(74, 22)
    frame.withdrawBtn:SetPoint("RIGHT", frame.matsBtn, "LEFT", 4, 0)
    frame.withdrawBtn:SetText("Withdraw")
    frame.withdrawBtn:SetScript("OnClick", function(self)
        if not V.IsBankOpen() then return end
        local menu = {}
        if not V.QueryIsEmpty(query) then
            local snapshot = query
            menu[#menu + 1] = {
                text = "Everything Matching the Search", notCheckable = true,
                func = function()
                    CommanderVault_Withdraw(function(row)
                        return V.MatchRow(row, snapshot)
                    end, "withdrew")
                end,
            }
        end
        local loadout = V.LoadoutWanted()
        if next(loadout) then
            menu[#menu + 1] = {
                text = "Loadout Consumables", notCheckable = true,
                func = function()
                    CommanderVault_Withdraw(function(row)
                        return loadout[row.itemID] == true
                    end, "withdrew")
                end,
            }
        end
        if #menu == 0 then
            print("Commander Vault: search for something first, then withdraw all of it")
            return
        end
        if not frame.withdrawMenu then
            frame.withdrawMenu = CreateFrame("Frame", "CommanderVaultWithdrawMenu", frame, "UIDropDownMenuTemplate")
        end
        if EasyMenu then
            EasyMenu(menu, frame.withdrawMenu, self, 0, 0, "MENU")
        else
            menu[1].func()
        end
    end)
    frame.withdrawBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Withdraw", 1, 1, 1)
        GameTooltip:AddLine("Take out everything the search is showing, or everything the Quartermaster says your loadout is short of.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.withdrawBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.sortBtn = CreateFrame("Button", nil, toolbar, "UIPanelButtonTemplate")
    frame.sortBtn:SetSize(50, 22)
    frame.sortBtn:SetPoint("RIGHT", frame.withdrawBtn, "LEFT", 4, 0)
    frame.sortBtn:SetText("Sort")
    frame.sortBtn:SetScript("OnClick", function()
        if V.IsBankOpen() then
            CommanderVault_SortBank()
        else
            print("Commander Vault: sorting needs a banker")
        end
    end)
    frame.sortBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Sort the vault", 1, 1, 1)
        GameTooltip:AddLine("Merges split stacks first — that is the part that gives slots back — then arranges by "
            .. ((DB().SortOrder or "CATEGORY"):lower()) .. ".", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    frame.sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Closed last, because it needs the button on its right to exist. The gap
    -- is the room the match count lives in.
    frame.searchBox:SetPoint("RIGHT", frame.sortBtn, "LEFT", -62, 0)

    scroll = CreateFrame("ScrollFrame", "CommanderVaultScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 62)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 40
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    -- The stepper buttons read as two floating squares against the stone; the
    -- wheel and the drag already do everything they do.
    Commander.UI.SlimScrollBar("CommanderVaultScroll", 2, 2)
    scroll:SetScript("OnSizeChanged", function(_, width) scrollChild:SetWidth(width) end)
    grid = scrollChild

    reportScroll = CreateFrame("ScrollFrame", "CommanderVaultReportScroll", frame, "UIPanelScrollFrameTemplate")
    reportScroll:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -6)
    reportScroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 62)
    reportScroll:EnableMouseWheel(true)
    reportScroll:SetScript("OnMouseWheel", function(self, delta)
        local target = self:GetVerticalScroll() - delta * 40
        local maxScroll = self:GetVerticalScrollRange()
        if target < 0 then target = 0 elseif target > maxScroll then target = maxScroll end
        self:SetVerticalScroll(target)
    end)
    reportChild = CreateFrame("Frame", nil, reportScroll)
    reportChild:SetSize(1, 1)
    reportScroll:SetScrollChild(reportChild)
    Commander.UI.SlimScrollBar("CommanderVaultReportScroll", 2, 2)
    reportScroll:SetScript("OnSizeChanged", function(_, width) reportChild:SetWidth(width) end)
    reportScroll:Hide()

    -- Dropping an item on the window deposits it. The scroll frame is the
    -- big target; the window itself catches the edges.
    for _, target in ipairs({ frame, scroll }) do
        target:EnableMouse(true)
        target:SetScript("OnReceiveDrag", DropIntoVault)
        target:HookScript("OnMouseUp", function(_, mouseButton)
            if mouseButton == "LeftButton" then DropIntoVault() end
        end)
    end

    frame.footerFS = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.footerFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 2, 52)
    frame.footerFS:SetJustifyH("RIGHT")

    -- Go to Bank (Commander Orders 3.1): shown by Refresh only while the
    -- window shows your own vault remembered away from a banker
    frame.goBank = GoButton(frame, {
        label = "Go to Bank", width = 104, height = 20, anchor = "ANCHOR_TOP",
        query = { townsfolk = "Banker" }, title = "Nearest banker", source = "Vault", key = "bank", icon = "BANK",
        tooltip = "The nearest banker, on the Commander Orders arrow: this is your vault as it was when you last stood at one.",
    })
    frame.goBank:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD + 2, 52)
    frame.goBank:Hide()

    -- The size grip.
    --
    -- Sizing is done by hand rather than with StartSizing because the window
    -- is anchored by whichever point the player last dropped it on, and
    -- StartSizing on a CENTRE-anchored frame grows it in both directions at
    -- once — the corner under the cursor runs away from the cursor. The drag
    -- therefore re-anchors to TOPLEFT first, which pins the three corners the
    -- player is NOT holding and makes the grip behave like a grip.
    --
    -- The relayout is gated on the column count actually changing. A full
    -- Refresh per frame would rebuild the snapshot sixty times a second (with
    -- the bank shut, CurrentBank rescans outright), and nothing on screen
    -- moves until a column is gained or lost anyway.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 25)
    grip:SetNormalTexture(GRIP_ART .. "Up")
    grip:SetHighlightTexture(GRIP_ART .. "Highlight")
    grip:SetPushedTexture(GRIP_ART .. "Down")
    frame.grip = grip

    grip:SetScript("OnMouseDown", function(self)
        -- Shift is the way back: a window dragged to an awkward size should
        -- not have to be dragged back to a good one by eye
        if IsShiftKeyDown and IsShiftKeyDown() then
            DB().FrameW, DB().FrameH = nil, nil
            ApplyGeometry()
            V.Refresh()
            return
        end
        local startCursorX, startCursorY = GetCursorPosition()
        local effective = frame:GetEffectiveScale()
        if not effective or effective == 0 then effective = 1 end
        local startW, startH = frame:GetWidth(), frame:GetHeight()
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        frame._dragging = true
        local lastColumns = V.GridColumns()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local width = startW + (x - startCursorX) / effective
            local height = startH - (y - startCursorY) / effective
            DB().FrameW = math.max(MIN_W, math.min(MAX_W, width))
            DB().FrameH = math.max(MIN_H, math.min(MAX_H, height))
            frame:SetSize(DB().FrameW, DB().FrameH)
            local columns = V.GridColumns()
            if columns ~= lastColumns then
                lastColumns = columns
                V.Refresh()
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        frame._dragging = false
        SavePosition()
        V.Refresh()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Resize", 1, 1, 1)
        GameTooltip:AddLine("Drag to resize the vault. The grid takes as many columns as the width allows.",
            0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Shift-click to go back to the default size.", 0.7, 0.7, 0.75, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Closing the window while standing at a banker has to end the banker's
    -- session too, or the next visit opens onto a session the server thinks is
    -- already running
    frame:HookScript("OnHide", function()
        if V.IsBankOpen() and CloseBankFrame then
            CloseBankFrame()
        end
    end)
    frame:HookScript("OnShow", function()
        ApplyPosition()
        V.Refresh()
        -- Focus is only ever taken when the player ASKED for the window. A
        -- vault that opens because you walked up to a banker must not put the
        -- cursor in a text box: with an edit box focused, WASD types letters
        -- instead of moving you.
        if frame._openedDeliberately and DB().AutoFocusSearch and DB().View ~= "REPORT" then
            frame.searchBox:SetFocus()
        end
        frame._openedDeliberately = nil
    end)

    ApplyGeometry()
    ApplyPosition()
    ApplyFraming(true)
    return frame
end

-- ---------------------------------------------------------------------------
-- Taking the bank window over
--
-- The stock frame is never HIDDEN: BankFrame's OnHide closes the banker's
-- session, so hiding it would shut the bank the moment the vault opened.
-- It is moved off-screen and made transparent instead, and put back exactly
-- as it was when the session ends.
-- ---------------------------------------------------------------------------

local function StashBankFrame()
    if not BankFrame or savedBankPoint then return end
    local point, relativeTo, relativePoint, x, y = BankFrame:GetPoint(1)
    savedBankPoint = { point = point, relativeTo = relativeTo,
                       relativePoint = relativePoint, x = x, y = y,
                       alpha = BankFrame:GetAlpha() }
    BankFrame:SetClampedToScreen(false)
    BankFrame:SetAlpha(0)
    BankFrame:ClearAllPoints()
    BankFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -4000, 4000)
end

local function RestoreBankFrame()
    if not BankFrame or not savedBankPoint then return end
    BankFrame:SetAlpha(savedBankPoint.alpha or 1)
    BankFrame:ClearAllPoints()
    if savedBankPoint.point then
        BankFrame:SetPoint(savedBankPoint.point, savedBankPoint.relativeTo,
            savedBankPoint.relativePoint, savedBankPoint.x, savedBankPoint.y)
    end
    BankFrame:SetClampedToScreen(true)
    savedBankPoint = nil
end

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

function CommanderVault_Toggle(forceOpen)
    EnsureFrame()
    if frame:IsShown() and not forceOpen then
        frame:Hide()
    else
        frame._openedDeliberately = true
        frame:Show()
    end
end

-- Open the vault straight into the search box. Bound to a key, this is the
-- whole module in one press: "where is my X" answered without a banker, a bag,
-- or a trip across the continent.
function CommanderVault_FocusSearch()
    EnsureFrame()
    if not frame:IsShown() then
        frame._openedDeliberately = true
        frame:Show()
    end
    DB().View = "GRID"
    V.Refresh()
    frame.searchBox:SetFocus()
    frame.searchBox:HighlightText()
end

function CommanderVault_Search(text)
    EnsureFrame()
    if not frame:IsShown() then
        frame._openedDeliberately = true
        frame:Show()
    end
    ShowGridWithSearch(text)
end

function CommanderVault_PrintReport()
    local snap = V.CurrentBank()
    local findings = V.BuildReport(snap, V.ScanBags())
    print("|cff7fd5ffCommander Vault|r — " .. (snap.cached and "remembered snapshot" or "live"))
    if #findings == 0 then
        print("  Nothing to report. The vault is in good order.")
        return
    end
    for _, finding in ipairs(findings) do
        local color = finding.severity == 3 and "|cffff7059"
            or (finding.severity == 2 and "|cffffd166" or "|cff9fd8ff")
        print("  " .. color .. finding.title .. "|r — " .. (finding.detail or ""))
    end
end

-- Searching from the command line: a separate slash command rather than a
-- subcommand, because the suite's shared dispatcher matches the WHOLE message
-- against its handler table and so cannot pass an argument through.
SLASH_COMMANDERVAULTFIND1 = "/vfind"
SlashCmdList["COMMANDERVAULTFIND"] = function(msg)
    CommanderVault_Search((msg or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
events:RegisterEvent("PLAYERBANKBAGSLOTS_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
-- The purchase row prices the next slot and says whether you can afford it,
-- so it has to hear about money as well as about slots
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("ITEM_LOCK_CHANGED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")

events:SetScript("OnEvent", function(_, event, arg1)
    local db = DB()
    if event == "PLAYER_LOGIN" then
        EnsureFrame()
        Commander.AddListener(COMMANDER_VAULT_EVENTS.UPDATE, function()
            if frame and frame:IsShown() then
                ApplyPosition()
                V.Refresh()
            end
        end)
        return
    end
    if db.EnableVault == false then return end

    if event == "BANKFRAME_OPENED" then
        V.SetBankOpen(true)
        V.ForgetKnownRecipes()
        V.ScanBank()
        if db.TakeOverBankFrame ~= false then
            StashBankFrame()
            EnsureFrame()
            frame:Show()
        end
        V.Refresh()
    elseif event == "BANKFRAME_CLOSED" then
        -- The container cache is still readable during this dispatch, so the
        -- final snapshot is taken BEFORE the flag flips; after it, every read
        -- comes back empty and the cache would be overwritten with nothing.
        V.ScanBank()
        V.SetBankOpen(false)
        V.StopMover()
        RestoreBankFrame()
        if frame and frame:IsShown() and db.TakeOverBankFrame ~= false then
            frame:Hide()
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Fires constantly city-wide. An open window is not reason enough:
        -- the item has to be one the grid is actually still waiting on, or
        -- standing in Shattrath relayouts the vault dozens of times a second.
        if frame and frame:IsShown() and arg1 and pendingItems[arg1] then
            pendingItems[arg1] = nil
            ScheduleRefresh()
        end
    else
        ScheduleRefresh()
    end
end)

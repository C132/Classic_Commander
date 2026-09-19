-- Commander Formulary: defaults, the settings page, and the load lifecycle.
--
-- Two saved tables. CommanderFormularyDB is account-wide settings, which
-- Restore Defaults may rewrite in full. CommanderFormularyChar is the
-- character's own state — which recipes the craft window has been seen to
-- contain, which categories they collapsed, what was selected — and nothing
-- on the options page can touch it.

CommanderFormularyDB = _G.CommanderFormularyDB or {}
CommanderFormularyChar = _G.CommanderFormularyChar or {}

COMMANDER_FORMULARY_EVENTS = {
    UPDATE = "COMMANDER_FORMULARY_UPDATE",
}

local DefaultSettings = {
    EnableFormulary = true,

    -- The window
    ReplaceCraftWindow = true,
    FrameStyle = "STONE",
    FrameScale = 1.0,
    Filter = "ALL",
    Sort = "SKILL",
    ShowSourceColumn = true,
    TooltipVerdict = true,
    DisenchantAdvice = true,

    -- Counting
    CountBank = true,

    -- Crafting
    AutoTargetGear = false,
    AutoConfirmReplace = true,
}

CommanderFormulary_Defaults = DefaultSettings

local STYLE_OPTIONS = {
    { text = "Dark Stone", value = "STONE" },
    { text = "Parchment", value = "PARCHMENT" },
    { text = "Dark Panel", value = "DARK" },
}

local SORT_OPTIONS = {
    { text = "Skill", value = "SKILL" },
    { text = "Name", value = "NAME" },
}

local frame = CreateFrame("FRAME")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderFormularyDB, DefaultSettings)
    Commander.Notify(COMMANDER_FORMULARY_EVENTS.UPDATE)
    print("Commander Formulary: settings restored to defaults.")
end

local function Call(name, ...)
    local fn = _G[name]
    if type(fn) == "function" then return fn(...) end
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Formulary",
        title = "Formulary",
        addonName = "Commander_Formulary",
        description = "The whole of a profession in one double-wide window: every recipe there is, grouped by the slot it enchants or the thing it makes, the ones you know coloured by difficulty and the ones you do not with where they come from — trainer, vendor, drop, quest, reputation — searchable across names, reagents, sellers and droppers. The right half is the recipe: its tooltip, its reagents against your bags, exactly how to learn it, and a Craft button. It replaces the stock Enchanting window rather than sitting beside it. Enchanting for now.",
        event = COMMANDER_FORMULARY_EVENTS.UPDATE,
        slash = { "/cfm", "/cformulary" },
        slashHandlers = {
            [""] = function() Call("CommanderFormulary_Toggle") end,
            show = function() Call("CommanderFormulary_Show") end,
            search = function(arg) Call("CommanderFormulary_Search", arg) end,
            status = function() Call("CommanderFormulary_Status") end,
            refresh = function(arg) Call("CommanderFormulary_RefreshPrices", arg) end,
            reset = function() Call("CommanderFormulary_ResetChar") end,
        },
    })

    panel:AddSection("Formulary")
    panel:AddCheckbox({
        label = "Enable the Formulary",
        tooltip = "Master switch. Turning it off gives you the stock Enchanting window back.",
        get = function() return CommanderFormularyDB.EnableFormulary end,
        set = function(value) CommanderFormularyDB.EnableFormulary = value end,
    })
    panel:AddCheckbox({
        label = "Replace The Enchanting Window",
        tooltip = "When your Enchanting window opens, show the Formulary in its place. Off, the stock window opens as usual and the Formulary is a separate window from /cfm.",
        get = function() return CommanderFormularyDB.ReplaceCraftWindow end,
        set = function(value) CommanderFormularyDB.ReplaceCraftWindow = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    })
    panel:AddDropdownPair({
        label = "Window Style",
        tooltip = "Dark Stone is the suite's weight; Parchment is the stock profession window's paper; Dark Panel matches the HUD frames.",
        options = STYLE_OPTIONS,
        get = function() return CommanderFormularyDB.FrameStyle end,
        set = function(value) CommanderFormularyDB.FrameStyle = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    }, {
        label = "Sort Recipes By",
        tooltip = "Within a slot: by the skill they are learned at, or by name. The sort menu on the window changes it for the session; this is what it goes back to.",
        options = SORT_OPTIONS,
        get = function() return CommanderFormularyDB.Sort end,
        set = function(value) CommanderFormularyDB.Sort = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    })
    panel:AddSlider({
        label = "Window Scale",
        tooltip = "Size of the whole window.",
        min = 0.7, max = 1.3, step = 0.05,
        format = "%.2f",
        get = function() return CommanderFormularyDB.FrameScale end,
        set = function(value) CommanderFormularyDB.FrameScale = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    })
    panel:AddCheckboxPair({
        label = "Show The Source Column",
        tooltip = "A word on every unknown recipe's row saying where it comes from — Trainer, Vendor, Reputation, Drop, Quest, World drop.",
        get = function() return CommanderFormularyDB.ShowSourceColumn end,
        set = function(value) CommanderFormularyDB.ShowSourceColumn = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    }, {
        label = "Count The Bank",
        tooltip = "Treat reagents in your bank as reachable when counting how many times a recipe can be cast. Bank counts exist once you have opened the bank this session.",
        get = function() return CommanderFormularyDB.CountBank end,
        set = function(value) CommanderFormularyDB.CountBank = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    })

    panel:AddCheckboxPair({
        label = "Formula Verdicts On Tooltips",
        tooltip = "On any formula's tooltip — at a vendor, in the auction house, in your bags — a line saying whether you already know the recipe, can learn it now, or need more skill first.",
        get = function() return CommanderFormularyDB.TooltipVerdict end,
        set = function(value) CommanderFormularyDB.TooltipVerdict = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    }, {
        label = "Disenchant Advice On Tooltips",
        tooltip = "On any green, blue or purple weapon or armour: what it disenchants into (from the game's own tables, by item level), what that is worth at today's auction prices, against the vendor and the auction house — and which to do. This is where an enchanter's gold comes from.",
        get = function() return CommanderFormularyDB.DisenchantAdvice end,
        set = function(value) CommanderFormularyDB.DisenchantAdvice = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    })

    panel:AddSection("Crafting",
        "The Craft button runs a macro: /cast the recipe. What else it does:")
    panel:AddCheckboxPair({
        label = "Cast On My Own Gear",
        tooltip = "Add a /use line so an enchant lands on the matching piece you are wearing instead of leaving the glowing cursor for you to aim. Off by default here: this window is for enchanting whatever you choose, and the leveling guide (Commander Tradecraft) is the one that enchants your own bracers a hundred times.",
        get = function() return CommanderFormularyDB.AutoTargetGear end,
        set = function(value) CommanderFormularyDB.AutoTargetGear = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary end,
    }, {
        label = "Confirm Replacing An Enchant",
        tooltip = "With Cast On My Own Gear on, end the macro with /click StaticPopup1Button1 to answer the replace question. Does nothing when no dialog is up.",
        get = function() return CommanderFormularyDB.AutoConfirmReplace end,
        set = function(value) CommanderFormularyDB.AutoConfirmReplace = value end,
        isEnabled = function() return CommanderFormularyDB.EnableFormulary and CommanderFormularyDB.AutoTargetGear end,
    })

    panel:AddButtonRow({
        {
            label = "Open Formulary",
            width = 130,
            tooltip = "Open the window (also: /cfm).",
            onClick = function() Call("CommanderFormulary_Show") end,
        },
        {
            label = "Forget Recipe Memory",
            width = 160,
            tooltip = "Forget which recipes this character's craft window has been seen to contain. The next time the window opens they are read again.",
            onClick = function() Call("CommanderFormulary_ResetChar") end,
        },
    })

    panel:Finalize({
        onDefaults = Reset,
        defaultsTooltip = "Reset every option on this page. What this character has been seen to know is not touched.",
    })
end

local function OnEvent(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "Commander_Formulary" then
        Commander.UI.ApplyDefaults(CommanderFormularyDB, DefaultSettings)
        local char = CommanderFormularyChar
        char.known = type(char.known) == "table" and char.known or {}
        char.collapsed = type(char.collapsed) == "table" and char.collapsed or {}
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        CreateOptionsPanel()
        Call("CommanderFormulary_OnLogin")
    end
end

frame:SetScript("OnEvent", OnEvent)

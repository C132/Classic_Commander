CommanderConsoleDB = _G.CommanderConsoleDB or {}

COMMANDER_CONSOLE_EVENTS = {
    UPDATE = "COMMANDER_CONSOLE_UPDATE"
}

-- Shared with CommanderConsole.lua (this file loads first). The console
-- strip's height is fixed (its top meets the raised world edge 150 UI units
-- up), so height is deliberately not a setting — but the fill, its tint, its
-- trim, and its opacity are. Each style has a `kind`:
--   ART      full-screen console artwork (bottom band is the console)
--   SOLID    the strip filled flat with the Console Color
--   GRADIENT the strip filled with a vertical gradient built from the color
--   TEX      a generated strip texture, stretched (greyscale, tinted)
--   TILE     a tiling material (blizz = a Blizzard game texture; otherwise a
--            generated greyscale tile), repeated across the strip and tinted
-- Any material (TILE) crossed with any Console Color yields a themed console
-- (holy marble, fiery obsidian, frost stone, cosmic dark, class-colored, ...).
CommanderConsole_Styles = {
    -- Console artwork
    { text = "Full Console", value = "FULL", kind = "ART", file = "Console3.png" },
    { text = "Low Profile", value = "LOW_PROFILE", kind = "ART", file = "Console3_LowProfile.png" },
    -- Flat / gradient
    { text = "Solid Bar", value = "SOLID", kind = "SOLID" },
    { text = "Gradient — Fade Up", value = "GRAD_FADE", kind = "GRADIENT", fade = true },
    { text = "Gradient — Steel Sheen", value = "GRAD_SHEEN", kind = "GRADIENT", fade = false },
    { text = "Brushed Steel", value = "TEX_BRUSHED", kind = "TEX", file = "StripBrushed.png" },
    { text = "Gradient Panel", value = "TEX_GRADIENT", kind = "TEX", file = "StripGradient.png" },
    -- Blizzlike materials (the game's own tiling textures)
    { text = "Marble", value = "BLZ_MARBLE", kind = "TILE", blizz = true, file = "Interface\\FrameGeneral\\UI-Background-Marble" },
    { text = "Rock", value = "BLZ_ROCK", kind = "TILE", blizz = true, file = "Interface\\FrameGeneral\\UI-Background-Rock" },
    { text = "Stone Panel", value = "BLZ_STONE", kind = "TILE", blizz = true, file = "Interface\\DialogFrame\\UI-DialogBox-Background" },
    { text = "Dark Stone", value = "BLZ_DARK", kind = "TILE", blizz = true, file = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    { text = "Vault", value = "BLZ_VAULT", kind = "TILE", blizz = true, file = "Interface\\BankFrame\\Bank-Background" },
    { text = "Parchment", value = "BLZ_PARCH", kind = "TILE", blizz = true, file = "Interface\\QuestFrame\\QuestBackground" },
    -- Generated materials (greyscale, tinted by the Console Color)
    { text = "Riveted Iron", value = "TILE_IRON", kind = "TILE", file = "TileIron.png" },
    { text = "Carved Stone", value = "TILE_STONE", kind = "TILE", file = "TileStone.png" },
    { text = "Obsidian", value = "TILE_OBSIDIAN", kind = "TILE", file = "TileObsidian.png" },
    { text = "Aged Wood", value = "TILE_WOOD", kind = "TILE", file = "TileWood.png" },
    { text = "Arcane Runes", value = "TILE_RUNES", kind = "TILE", file = "TileRunes.png" },
    { text = "Hazard Stripes", value = "TILE_HAZARD", kind = "TILE", file = "TileHazard.png" },
    { text = "Carbon Weave", value = "TILE_CARBON", kind = "TILE", file = "TileCarbon.png" },
    { text = "Cosmic", value = "TILE_COSMIC", kind = "TILE", file = "TileCosmic.png" },
}

CommanderConsole_Colors = {
    -- Metals / neutrals
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Gold", value = "GOLD", r = 1, g = 0.85, b = 0.5 },
    { text = "Bronze", value = "BRONZE", r = 0.85, g = 0.6, b = 0.3 },
    { text = "Void", value = "VOID", r = 0.16, g = 0.16, b = 0.2 },
    -- Schools / personas
    { text = "Holy", value = "HOLY", r = 1, g = 0.93, b = 0.6 },
    { text = "Shadow", value = "SHADOW", r = 0.55, g = 0.3, b = 0.75 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Fire", value = "FIRE", r = 1, g = 0.35, b = 0.1 },
    { text = "Ember", value = "EMBER", r = 1, g = 0.55, b = 0.4 },
    { text = "Frost", value = "FROST", r = 0.6, g = 0.8, b = 1 },
    { text = "Nature", value = "NATURE", r = 0.35, g = 0.85, b = 0.3 },
    { text = "Forest", value = "FOREST", r = 0.6, g = 1, b = 0.65 },
    { text = "Arcane", value = "ARCANE", r = 0.8, g = 0.6, b = 1 },
    { text = "Cosmic", value = "COSMIC", r = 0.75, g = 0.4, b = 1 },
    { text = "Blood", value = "BLOOD", r = 0.6, g = 0.05, b = 0.08 },
    { text = "Crimson", value = "CRIMSON", r = 0.85, g = 0.2, b = 0.24 },
    -- Factions / command
    { text = "Alliance", value = "ALLIANCE", r = 0.2, g = 0.4, b = 0.95 },
    { text = "Horde", value = "HORDE", r = 0.85, g = 0.15, b = 0.1 },
    { text = "Command Blue", value = "COMMAND", r = 0.25, g = 0.5, b = 0.95 },
    -- Resolved live from your class in CommanderConsole.lua (no fixed rgb)
    { text = "Class Color", value = "CLASS" },
}

-- Optional decorative border drawn around the console band. NONE hides it;
-- the rest are Blizzard edge textures tinted by the Trim Color.
CommanderConsole_Trims = {
    { text = "None", value = "NONE" },
    { text = "Gold Dialog", value = "GOLD", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 32 },
    { text = "Tooltip", value = "TOOLTIP", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 },
    { text = "Steel Line", value = "THIN", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 },
    { text = "Carved Wood", value = "WOOD", edgeFile = "Interface\\AchievementFrame\\UI-Achievement-WoodBorder", edgeSize = 48 },
}

local DefaultSettings = {
    ShowConsole = false,
    ConsoleStyle = "FULL",
    ConsoleColor = "STEEL",
    ConsoleOpacity = 1.0,
    TextureScale = 1.0,
    TrimStyle = "NONE",
    TrimColor = "STEEL",
}

local frame = CreateFrame("FRAME");
frame:RegisterEvent("PLAYER_LOGIN")

local function Reset()
    Commander.UI.ResetToDefaults(CommanderConsoleDB, DefaultSettings)
    Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
    print("Commander Console: settings restored to defaults")
end

local function BuildOptions(list)
    local options = {}
    for _, entry in ipairs(list) do
        options[#options + 1] = { text = entry.text, value = entry.value }
    end
    return options
end

local function CreateOptionsPanel()
    local panel = Commander.UI.NewPanel({
        key = "Console",
        title = "Console",
        addonName = "Commander_Console",
        description = "Frames the game world like a classic RTS: the viewport rises and an armored command console fills the bottom of the screen, docking neatly under the suite's action bar, minimap, and bag panels.",
        event = COMMANDER_CONSOLE_EVENTS.UPDATE,
        slash = { "/cconsole", "/cc" },
        slashHandlers = {
            toggle = function()
                CommanderConsoleDB.ShowConsole = not CommanderConsoleDB.ShowConsole
                Commander.Notify(COMMANDER_CONSOLE_EVENTS.UPDATE)
            end,
        },
    })

    panel:AddSection("Console", "The console's height is matched to its artwork, so it always lines up with the world edge.")
    panel:AddCheckbox({
        label = "Show Console",
        tooltip = "Enable the console backdrop and shrink the game viewport to make room for it.",
        get = function() return CommanderConsoleDB.ShowConsole end,
        set = function(value) CommanderConsoleDB.ShowConsole = value end,
    })

    panel:AddSection("Appearance", "Pick a material and a color — any material crossed with any color gives a themed console. Add an optional trim and set how solid it sits over the world.")
    panel:AddDropdown({
        label = "Console Style",
        tooltip = "The console's fill. Full Console / Low Profile are the armored artwork; Solid and the Gradients are flat fills. The Blizzlike materials (Marble, Rock, Stone, Vault, Parchment) are the game's own tiling textures, and the generated materials (Iron, Stone, Obsidian, Wood, Runes, Hazard, Carbon, Cosmic) are greyscale tiles — all of them tinted by the Console Color, so e.g. Marble + Holy or Obsidian + Fire.",
        options = BuildOptions(CommanderConsole_Styles),
        width = 170,
        get = function() return CommanderConsoleDB.ConsoleStyle end,
        set = function(value) CommanderConsoleDB.ConsoleStyle = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })
    panel:AddDropdown({
        label = "Console Color",
        tooltip = "Color of the console — the theme. Materials and metals plus schools and personas (Holy, Shadow, Fel, Fire, Frost, Nature, Arcane, Cosmic, Blood), factions, and your Class Color. On the artwork styles Steel is untinted; on every other style the color is the fill itself.",
        options = BuildOptions(CommanderConsole_Colors),
        width = 160,
        get = function() return CommanderConsoleDB.ConsoleColor end,
        set = function(value) CommanderConsoleDB.ConsoleColor = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })
    panel:AddSlider({
        label = "Texture Scale",
        tooltip = "Size of the tiles for the material (tiling) styles — smaller repeats more, larger repeats less. No effect on the artwork, solid, or gradient styles.",
        min = 0.5, max = 2.5, step = 0.1,
        format = "%.1fx",
        get = function() return CommanderConsoleDB.TextureScale end,
        set = function(value) CommanderConsoleDB.TextureScale = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })
    panel:AddDropdownPair({
        label = "Trim",
        tooltip = "An optional decorative border drawn around the console band: the gold dialog frame, tooltip edge, a thin steel line, or carved wood. None leaves it clean.",
        options = BuildOptions(CommanderConsole_Trims),
        get = function() return CommanderConsoleDB.TrimStyle end,
        set = function(value) CommanderConsoleDB.TrimStyle = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    }, {
        label = "Trim Color",
        tooltip = "Tint for the trim border (Steel leaves the gold/wood art untinted). Set it to your Class Color to frame the console in your class.",
        options = BuildOptions(CommanderConsole_Colors),
        get = function() return CommanderConsoleDB.TrimColor end,
        set = function(value) CommanderConsoleDB.TrimColor = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole and CommanderConsoleDB.TrimStyle ~= "NONE" end,
    })
    panel:AddSlider({
        label = "Console Opacity",
        tooltip = "How solid the console is. Lower values let the world show through.",
        min = 0.2, max = 1.0, step = 0.05,
        format = Commander.UI.FormatPercent,
        get = function() return CommanderConsoleDB.ConsoleOpacity end,
        set = function(value) CommanderConsoleDB.ConsoleOpacity = value end,
        isEnabled = function() return CommanderConsoleDB.ShowConsole end,
    })

    panel:Finalize({ onDefaults = Reset })
end

local function OnEvent(self, event)
    if event == "PLAYER_LOGIN" then
        -- Merge defaults here so SavedVariables are already loaded
        Commander.UI.ApplyDefaults(CommanderConsoleDB, DefaultSettings)
        -- Drop the briefly-shipped ConsoleHeight setting; the art is fixed-size
        CommanderConsoleDB.ConsoleHeight = nil
        CreateOptionsPanel()
    end
end

frame:SetScript("OnEvent", OnEvent)

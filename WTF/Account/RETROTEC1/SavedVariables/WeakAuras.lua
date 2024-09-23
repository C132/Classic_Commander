
WeakAurasSaved = {
["dynamicIconCache"] = {
},
["editor_tab_spaces"] = 4,
["displays"] = {
["Buff Bar"] = {
["grow"] = "RIGHT",
["controlledChildren"] = {
"Buff",
},
["borderBackdrop"] = "Blizzard Tooltip",
["xOffset"] = -124.1727905273438,
["yOffset"] = -272.0986938476563,
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["space"] = 5,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["radius"] = 200,
["selfPoint"] = "LEFT",
["align"] = "CENTER",
["stagger"] = 0,
["subRegions"] = {
},
["config"] = {
},
["internalVersion"] = 77,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["limit"] = 5,
["backdropColor"] = {
1,
1,
1,
0.5,
},
["fullCircle"] = true,
["animate"] = false,
["authorOptions"] = {
},
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "dynamicgroup",
["borderSize"] = 2,
["sort"] = "descending",
["gridType"] = "RD",
["rotation"] = 0,
["constantFactor"] = "RADIUS",
["stepAngle"] = 15,
["borderOffset"] = 4,
["rowSpace"] = 1,
["alpha"] = 1,
["id"] = "Buff Bar",
["frameStrata"] = 1,
["gridWidth"] = 5,
["anchorFrameType"] = "SCREEN",
["useLimit"] = false,
["borderInset"] = 1,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["uid"] = "o13PrCDWfds",
["conditions"] = {
},
["information"] = {
},
["arcLength"] = 360,
},
["Buff"] = {
["iconSource"] = -1,
["color"] = {
0.8392157554626465,
0.8392157554626465,
0.7843137979507446,
1,
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["showClones"] = true,
["type"] = "aura2",
["subeventSuffix"] = "_CAST_START",
["matchesShowOn"] = "showOnActive",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["names"] = {
},
["unit"] = "player",
["debuffType"] = "BOTH",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["internalVersion"] = 77,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_anchorPoint"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_fontType"] = "OUTLINE",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["useGlowColor"] = false,
["glowType"] = "buttonOverlay",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["glowDuration"] = 1,
["glowXOffset"] = 0,
["glowThickness"] = 1,
["glowScale"] = 1,
["glow"] = false,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 0,
["border_size"] = 1,
["border_color"] = {
0.2274509966373444,
0.5490196347236633,
1,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 24,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["xOffset"] = 0,
["keepAspectRatio"] = false,
["information"] = {
},
["authorOptions"] = {
},
["uid"] = "r1mkQZ)hrXB",
["zoom"] = 0,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["id"] = "Buff",
["frameStrata"] = 1,
["useCooldownModRate"] = true,
["width"] = 24,
["cooldownTextDisabled"] = false,
["config"] = {
},
["inverse"] = false,
["useTooltip"] = true,
["conditions"] = {
},
["cooldown"] = true,
["parent"] = "Buff Bar",
},
["Player Name"] = {
["outline"] = "OUTLINE",
["authorOptions"] = {
},
["displayText"] = "%1.name\n",
["shadowYOffset"] = -1,
["anchorPoint"] = "CENTER",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Auto",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["use_namerealm"] = false,
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["use_unit"] = true,
["spellIds"] = {
},
["unit"] = "player",
["names"] = {
},
["useName"] = true,
["auranames"] = {
"",
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["displayText_format_p_format"] = "timed",
["internalVersion"] = 77,
["selfPoint"] = "BOTTOM",
["font"] = "Friz Quadrata TT",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["fontSize"] = 14,
["shadowXOffset"] = 1,
["regionType"] = "text",
["displayText_format_p_time_legacy_floor"] = false,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayText_format_p_time_precision"] = 1,
["conditions"] = {
},
["displayText_format_p_time_dynamic_threshold"] = 60,
["displayText_format_p_time_mod_rate"] = true,
["justify"] = "LEFT",
["wordWrap"] = "WordWrap",
["id"] = "Player Name",
["config"] = {
},
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["yOffset"] = -250,
["uid"] = "PZJGRDmbV(K",
["xOffset"] = -240,
["color"] = {
1,
0.8901961445808411,
0.07450980693101883,
1,
},
["shadowColor"] = {
0,
0,
0,
1,
},
["fixedWidth"] = 200,
["information"] = {
},
["displayText_format_1.name_format"] = "none",
},
["Target Name"] = {
["outline"] = "OUTLINE",
["color"] = {
1,
0.8901961445808411,
0.07450980693101883,
1,
},
["displayText_format_p_time_dynamic_threshold"] = 60,
["shadowYOffset"] = -1,
["anchorPoint"] = "CENTER",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Auto",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["use_namerealm"] = false,
["type"] = "unit",
["auranames"] = {
"",
},
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["use_unit"] = true,
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["useName"] = true,
["names"] = {
},
["unit"] = "target",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["displayText_format_p_time_mod_rate"] = true,
["displayText_format_1.name_format"] = "none",
["selfPoint"] = "BOTTOM",
["font"] = "Friz Quadrata TT",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["fontSize"] = 14,
["shadowXOffset"] = 1,
["regionType"] = "text",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["displayText_format_p_time_legacy_floor"] = false,
["displayText_format_p_time_precision"] = 1,
["fixedWidth"] = 200,
["xOffset"] = 240,
["wordWrap"] = "WordWrap",
["justify"] = "LEFT",
["displayText"] = "%1.name\n",
["id"] = "Target Name",
["uid"] = "pi83aTixNe)",
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["yOffset"] = -250,
["config"] = {
},
["authorOptions"] = {
},
["displayText_format_p_format"] = "timed",
["shadowColor"] = {
0,
0,
0,
1,
},
["conditions"] = {
},
["information"] = {
},
["internalVersion"] = 77,
},
["Target Power"] = {
["sparkWidth"] = 10,
["iconSource"] = -1,
["xOffset"] = 240.1975377400717,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -416.7899980545044,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["sparkRotationMode"] = "AUTO",
["icon"] = false,
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["event"] = "Power",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["use_unit"] = true,
["names"] = {
},
["unit"] = "target",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["icon_color"] = {
1,
1,
1,
1,
},
["internalVersion"] = 77,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["barColor"] = {
0.2549019753932953,
0.501960813999176,
0.7372549176216125,
1,
},
["desaturate"] = false,
["anchorFrameType"] = "SCREEN",
["sparkOffsetY"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%1.power / %1.maxpower",
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_1.power_format"] = "none",
["text_selfPoint"] = "CENTER",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_text_format_p_time_dynamic_threshold"] = 60,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_1.health_format"] = "none",
["text_text_format_1.maxpower_format"] = "none",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["type"] = "subtext",
["text_text_format_1.maxhealth_format"] = "none",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = -1,
["text_visible"] = true,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "None",
["text_anchorPoint"] = "INNER_CENTER",
["text_text_format_p_time_legacy_floor"] = false,
["text_text_format_p_time_format"] = 0,
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_p_format"] = "timed",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%n",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowYOffset"] = -1,
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_anchorPoint"] = "INNER_RIGHT",
["text_text_format_n_format"] = "none",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_fontType"] = "None",
},
{
["border_offset"] = 0,
["border_anchor"] = "bar",
["border_size"] = 1,
["border_color"] = {
0.4745098352432251,
0.4745098352432251,
0.4745098352432251,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 14.99999237060547,
["textureSource"] = "LSM",
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["sparkOffsetX"] = 0,
["barColor2"] = {
1,
1,
0,
1,
},
["parent"] = "Bars",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["config"] = {
},
["uid"] = "Uup1Rwur0jd",
["icon_side"] = "RIGHT",
["zoom"] = 0,
["sparkHeight"] = 30,
["texture"] = "Clean",
["frameStrata"] = 1,
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = false,
["gradientOrientation"] = "HORIZONTAL",
["id"] = "Target Power",
["sparkHidden"] = "NEVER",
["alpha"] = 1,
["width"] = 181.8262481689453,
["authorOptions"] = {
},
["sparkColor"] = {
1,
1,
1,
1,
},
["inverse"] = false,
["enableGradient"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["information"] = {
},
["backgroundColor"] = {
0,
0,
0,
1,
},
},
["Target Level"] = {
["outline"] = "OUTLINE",
["authorOptions"] = {
},
["displayText_format_p_time_dynamic_threshold"] = 60,
["shadowYOffset"] = -1,
["anchorPoint"] = "CENTER",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Auto",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["use_namerealm"] = false,
["type"] = "unit",
["use_level"] = true,
["auranames"] = {
"",
},
["event"] = "Unit Characteristics",
["subeventPrefix"] = "SPELL",
["use_unit"] = true,
["spellIds"] = {
},
["unit"] = "target",
["names"] = {
},
["useName"] = true,
["subeventSuffix"] = "_CAST_START",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["displayText_format_p_time_mod_rate"] = true,
["internalVersion"] = 77,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["font"] = "Friz Quadrata TT",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["fontSize"] = 17,
["shadowXOffset"] = 1,
["regionType"] = "text",
["displayText_format_p_time_legacy_floor"] = false,
["displayText_format_1.level_format"] = "none",
["selfPoint"] = "BOTTOM",
["displayText_format_p_time_precision"] = 1,
["conditions"] = {
},
["displayText_format_p_format"] = "timed",
["xOffset"] = 324.3656249999999,
["justify"] = "LEFT",
["color"] = {
1,
0.8901961445808411,
0.07450980693101883,
1,
},
["id"] = "Target Level",
["config"] = {
},
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["yOffset"] = -252.8397064208984,
["uid"] = ")DoIuU0APAU",
["displayText"] = "%1.level\n",
["wordWrap"] = "WordWrap",
["shadowColor"] = {
0,
0,
0,
1,
},
["fixedWidth"] = 200,
["information"] = {
},
["displayText_format_1.name_format"] = "none",
},
["Target Health"] = {
["sparkWidth"] = 10,
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -396.6421337127686,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["sparkRotationMode"] = "AUTO",
["icon"] = false,
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["use_unit"] = true,
["unit"] = "target",
["names"] = {
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["icon_color"] = {
1,
1,
1,
1,
},
["internalVersion"] = 77,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["barColor"] = {
0.3490196168422699,
0.8392157554626465,
0,
1,
},
["desaturate"] = false,
["width"] = 181.8262481689453,
["sparkOffsetY"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%1.health / %1.maxhealth",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "CENTER",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_p_time_mod_rate"] = true,
["anchorXOffset"] = 0,
["text_text_format_p_format"] = "timed",
["type"] = "subtext",
["text_text_format_p_time_format"] = 0,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_text_format_p_time_legacy_floor"] = false,
["text_shadowYOffset"] = -1,
["text_fontType"] = "None",
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_anchorPoint"] = "INNER_CENTER",
["text_text_format_p_time_precision"] = 1,
["text_text_format_1.maxhealth_format"] = "none",
["text_fontSize"] = 12,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_1.health_format"] = "none",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%n",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowYOffset"] = -1,
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_anchorPoint"] = "INNER_RIGHT",
["text_fontType"] = "None",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_n_format"] = "none",
},
{
["border_offset"] = 0,
["border_anchor"] = "bar",
["border_size"] = 1,
["border_color"] = {
0.4745098352432251,
0.4745098352432251,
0.4745098352432251,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 14.99999237060547,
["textureSource"] = "LSM",
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["xOffset"] = 240.197509765625,
["information"] = {
},
["parent"] = "Bars",
["backgroundColor"] = {
0,
0,
0,
1,
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["uid"] = "Nt4NAZFXLTV",
["config"] = {
},
["icon_side"] = "RIGHT",
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["sparkHeight"] = 30,
["texture"] = "Clean",
["alpha"] = 1,
["zoom"] = 0,
["spark"] = false,
["sparkHidden"] = "NEVER",
["id"] = "Target Health",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["gradientOrientation"] = "HORIZONTAL",
["sparkColor"] = {
1,
1,
1,
1,
},
["inverse"] = false,
["enableGradient"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["barColor2"] = {
1,
1,
0,
1,
},
["sparkOffsetX"] = 0,
},
["Buff 2"] = {
["iconSource"] = -1,
["xOffset"] = 0,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = 0,
["anchorPoint"] = "CENTER",
["cooldownSwipe"] = true,
["cooldownEdge"] = false,
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["showClones"] = true,
["type"] = "aura2",
["subeventSuffix"] = "_CAST_START",
["matchesShowOn"] = "showOnActive",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["names"] = {
},
["unit"] = "target",
["debuffType"] = "BOTH",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["useTooltip"] = true,
["keepAspectRatio"] = false,
["selfPoint"] = "CENTER",
["desaturate"] = false,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["text_shadowXOffset"] = 0,
["text_text_format_s_format"] = "none",
["text_text"] = "%s",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowYOffset"] = 0,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_anchorPoint"] = "INNER_BOTTOMRIGHT",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_fontType"] = "OUTLINE",
},
{
["glowFrequency"] = 0.25,
["type"] = "subglow",
["glowDuration"] = 1,
["glowType"] = "buttonOverlay",
["glowLength"] = 10,
["glowYOffset"] = 0,
["glowColor"] = {
1,
1,
1,
1,
},
["useGlowColor"] = false,
["glowXOffset"] = 0,
["glow"] = false,
["glowScale"] = 1,
["glowThickness"] = 1,
["glowLines"] = 8,
["glowBorder"] = false,
},
{
["border_offset"] = 0,
["border_size"] = 1,
["border_color"] = {
1,
1,
1,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 24,
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["useAdjustededMax"] = false,
["progressSource"] = {
-1,
"",
},
["useAdjustededMin"] = false,
["regionType"] = "icon",
["color"] = {
1,
1,
1,
1,
},
["authorOptions"] = {
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["cooldown"] = true,
["zoom"] = 0,
["config"] = {
},
["cooldownTextDisabled"] = false,
["parent"] = "Debuff Bar",
["width"] = 24,
["id"] = "Buff 2",
["useCooldownModRate"] = true,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["frameStrata"] = 1,
["uid"] = "sH(LzFXEgJN",
["inverse"] = false,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["conditions"] = {
{
["check"] = {
["trigger"] = 1,
["variable"] = "debuffClass",
["value"] = "magic",
["op"] = "==",
},
["changes"] = {
{
["value"] = {
0,
0.7764706611633301,
1,
1,
},
["property"] = "sub.4.border_color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "debuffClass",
["op"] = "==",
["value"] = "curse",
},
["changes"] = {
{
["value"] = {
0.6313725709915161,
0.04313725605607033,
1,
1,
},
["property"] = "sub.4.border_color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "debuffClass",
["value"] = "disease",
["op"] = "==",
},
["changes"] = {
{
["value"] = {
1,
0.5372549295425415,
0.01568627543747425,
1,
},
["property"] = "sub.4.border_color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "debuffClass",
["op"] = "==",
["value"] = "enrage",
},
["changes"] = {
{
["value"] = {
1,
0,
0.05882353335618973,
1,
},
["property"] = "sub.4.border_color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "debuffClass",
["value"] = "poison",
["op"] = "==",
},
["changes"] = {
{
["value"] = {
0.03921568766236305,
1,
0,
1,
},
["property"] = "sub.4.border_color",
},
},
},
{
["check"] = {
["trigger"] = 1,
["variable"] = "debuffClass",
["op"] = "==",
["value"] = "none",
},
["changes"] = {
{
["value"] = {
0.5333333611488342,
0.5333333611488342,
0.5490196347236633,
1,
},
["property"] = "sub.4.border_color",
},
},
},
},
["information"] = {
},
["internalVersion"] = 77,
},
["New"] = {
["outline"] = "OUTLINE",
["authorOptions"] = {
},
["displayText"] = "%1.class\n",
["shadowYOffset"] = -1,
["anchorPoint"] = "CENTER",
["displayText_format_p_time_format"] = 0,
["customTextUpdate"] = "event",
["automaticWidth"] = "Auto",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["use_character"] = false,
["event"] = "Unit Characteristics",
["subeventPrefix"] = "SPELL",
["use_npcId"] = false,
["use_class"] = true,
["spellIds"] = {
},
["classification"] = {
},
["use_unit"] = true,
["names"] = {
},
["unit"] = "target",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["displayText_format_p_format"] = "timed",
["internalVersion"] = 77,
["selfPoint"] = "BOTTOM",
["font"] = "Friz Quadrata TT",
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["load"] = {
["use_never"] = true,
["talent"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["fontSize"] = 12,
["shadowXOffset"] = 1,
["regionType"] = "text",
["fixedWidth"] = 200,
["displayText_format_1.classification_format"] = "none",
["displayText_format_1.class_format"] = "none",
["displayText_format_p_time_precision"] = 1,
["displayText_format_p_time_mod_rate"] = true,
["displayText_format_p_time_dynamic_threshold"] = 60,
["color"] = {
1,
1,
1,
1,
},
["justify"] = "LEFT",
["uid"] = "hkbWUtvr4Iv",
["id"] = "New",
["wordWrap"] = "WordWrap",
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["yOffset"] = -289.9754791259766,
["config"] = {
},
["xOffset"] = -21.72802734375,
["displayText_format_p_time_legacy_floor"] = false,
["shadowColor"] = {
0,
0,
0,
1,
},
["conditions"] = {
},
["information"] = {
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
},
["Player Portrait"] = {
["modelIsUnit"] = true,
["borderBackdrop"] = "ElvUI Blank",
["api"] = false,
["xOffset"] = -240.0351033528646,
["preferToUpdate"] = false,
["yOffset"] = -325.16669921875,
["anchorPoint"] = "CENTER",
["model_x"] = 0,
["borderColor"] = {
0,
0,
0,
1,
},
["url"] = "https://wago.io/pC9o4ZkCE/1",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["use_alwaystrue"] = true,
["unevent"] = "auto",
["duration"] = "1",
["event"] = "Conditions",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["unit"] = "player",
["names"] = {
},
["subeventSuffix"] = "_CAST_START",
["use_unit"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["portraitZoom"] = true,
["internalVersion"] = 77,
["model_fileId"] = "player",
["selfPoint"] = "CENTER",
["model_st_ty"] = -55,
["rotation"] = 0,
["borderInset"] = 4,
["version"] = 1,
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["height"] = 114.5999649047852,
["borderOffset"] = 5,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["zoneIds"] = "",
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["backdropColor"] = {
0,
0,
0,
0.70000001788139,
},
["advance"] = false,
["sequence"] = 11,
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["scale"] = 1,
["source"] = "import",
["border"] = true,
["borderEdge"] = "None",
["regionType"] = "model",
["borderSize"] = 1,
["model_st_us"] = 115,
["uid"] = "KapFsKCU5Yn",
["model_st_rz"] = 102,
["frameStrata"] = 2,
["anchorFrameType"] = "SCREEN",
["model_z"] = 0,
["semver"] = "1.0.0",
["tocversion"] = 11305,
["id"] = "Player Portrait",
["model_y"] = 0,
["model_st_rx"] = 90,
["width"] = 181.9665751139323,
["model_st_ry"] = 0,
["config"] = {
},
["model_st_tx"] = 55,
["model_path"] = "player",
["conditions"] = {
},
["model_st_tz"] = -245,
["authorOptions"] = {
},
},
["Target Cast Bar"] = {
["sparkWidth"] = 10,
["sparkOffsetX"] = 0,
["parent"] = "Bars",
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -374.9137391690842,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["sparkRotationMode"] = "AUTO",
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["use_genericShowOn"] = true,
["event"] = "Cast",
["subeventPrefix"] = "SPELL",
["genericShowOn"] = "showOnCooldown",
["use_spellName"] = true,
["spellIds"] = {
},
["unit"] = "target",
["use_unit"] = true,
["names"] = {
},
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["barColor"] = {
0.7372549176216125,
0.615686297416687,
0,
1,
},
["desaturate"] = false,
["anchorFrameType"] = "SCREEN",
["sparkOffsetY"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["text_text_format_p_time_format"] = 0,
["text_text"] = "%1.name",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "CENTER",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["rotateText"] = "NONE",
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_1.health_format"] = "none",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_p_format"] = "timed",
["type"] = "subtext",
["text_font"] = "Friz Quadrata TT",
["text_color"] = {
1,
1,
1,
1,
},
["text_text_format_1.maxhealth_format"] = "none",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = -1,
["text_visible"] = true,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "None",
["text_anchorPoint"] = "INNER_CENTER",
["text_text_format_p_time_legacy_floor"] = false,
["text_shadowXOffset"] = 1,
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_1.name_format"] = "none",
},
{
["text_text_format_n_format"] = "none",
["text_text"] = "%1.t",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_1.t_time_legacy_floor"] = false,
["text_text_format_1.t_time_precision"] = 1,
["rotateText"] = "NONE",
["type"] = "subtext",
["text_text_format_1.t_time_format"] = 0,
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowXOffset"] = 1,
["text_shadowYOffset"] = -1,
["text_text_format_1.t_time_dynamic_threshold"] = 60,
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_anchorPoint"] = "INNER_RIGHT",
["text_text_format_1.t_format"] = "timed",
["text_fontType"] = "None",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_1.t_time_mod_rate"] = true,
},
{
["type"] = "subborder",
["border_anchor"] = "bar",
["border_offset"] = 0,
["border_color"] = {
0.4745098352432251,
0.4745098352432251,
0.4745098352432251,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["border_size"] = 1,
},
},
["gradientOrientation"] = "HORIZONTAL",
["textureSource"] = "LSM",
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["backgroundColor"] = {
0,
0,
0,
1,
},
["barColor2"] = {
1,
1,
0,
1,
},
["internalVersion"] = 77,
["authorOptions"] = {
},
["iconSource"] = -1,
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["sparkColor"] = {
1,
1,
1,
1,
},
["uid"] = "23PDKiP2J2s",
["icon_side"] = "RIGHT",
["height"] = 14.99999237060547,
["sparkHeight"] = 30,
["texture"] = "Clean",
["alpha"] = 1,
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = false,
["zoom"] = 0,
["sparkHidden"] = "NEVER",
["id"] = "Target Cast Bar",
["frameStrata"] = 5,
["width"] = 181.8262481689453,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["config"] = {
},
["inverse"] = false,
["selfPoint"] = "CENTER",
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["information"] = {
},
["xOffset"] = 240,
},
["Target"] = {
["modelIsUnit"] = true,
["borderBackdrop"] = "ElvUI Blank",
["api"] = false,
["authorOptions"] = {
},
["preferToUpdate"] = false,
["yOffset"] = -325.2598724365234,
["anchorPoint"] = "CENTER",
["model_x"] = 0,
["borderColor"] = {
0,
0,
0,
1,
},
["url"] = "https://wago.io/pC9o4ZkCE/1",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["unevent"] = "auto",
["duration"] = "1",
["event"] = "Unit Characteristics",
["subeventPrefix"] = "SPELL",
["unit"] = "target",
["use_unitisunit"] = true,
["spellIds"] = {
},
["unitisunit"] = "target",
["use_unit"] = true,
["subeventSuffix"] = "_CAST_START",
["names"] = {
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["portraitZoom"] = true,
["internalVersion"] = 77,
["model_fileId"] = "target",
["model_path"] = "player",
["model_st_ty"] = 0,
["rotation"] = 0,
["config"] = {
},
["version"] = 1,
["subRegions"] = {
{
["type"] = "subbackground",
},
},
["height"] = 108.7408676147461,
["model_st_tx"] = 0,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["zoneIds"] = "",
},
["source"] = "import",
["backdropColor"] = {
0,
0,
0,
0.70000001788139,
},
["selfPoint"] = "CENTER",
["sequence"] = 1,
["model_st_tz"] = 0,
["scale"] = 1,
["advance"] = false,
["border"] = true,
["borderEdge"] = "None",
["regionType"] = "model",
["borderSize"] = 1,
["model_st_us"] = 40,
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["model_st_rz"] = 0,
["model_st_ry"] = 0,
["width"] = 184.5925903320313,
["borderOffset"] = 5,
["semver"] = "1.0.0",
["tocversion"] = 11305,
["id"] = "Target",
["model_y"] = 0,
["frameStrata"] = 2,
["anchorFrameType"] = "SCREEN",
["model_st_rx"] = 270,
["borderInset"] = 4,
["model_z"] = 0,
["uid"] = "Ff8ABk1kmDO",
["conditions"] = {
},
["information"] = {
["forceEvents"] = true,
["ignoreOptionsEventErrors"] = true,
},
["xOffset"] = 238.4942016601563,
},
["Debuff Bar"] = {
["grow"] = "LEFT",
["controlledChildren"] = {
"Buff 2",
},
["borderBackdrop"] = "Blizzard Tooltip",
["authorOptions"] = {
},
["yOffset"] = -335.703369140625,
["anchorPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["space"] = 5,
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["names"] = {
},
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
},
["columnSpace"] = 1,
["radius"] = 200,
["selfPoint"] = "RIGHT",
["align"] = "CENTER",
["stagger"] = 0,
["subRegions"] = {
},
["uid"] = "M6NcyqequFX",
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["limit"] = 5,
["backdropColor"] = {
1,
1,
1,
0.5,
},
["rotation"] = 0,
["animate"] = false,
["arcLength"] = 360,
["scale"] = 1,
["centerType"] = "LR",
["border"] = false,
["borderEdge"] = "Square Full White",
["regionType"] = "dynamicgroup",
["borderSize"] = 2,
["sort"] = "descending",
["fullCircle"] = true,
["gridType"] = "RD",
["constantFactor"] = "RADIUS",
["useLimit"] = false,
["borderOffset"] = 4,
["rowSpace"] = 1,
["gridWidth"] = 5,
["id"] = "Debuff Bar",
["frameStrata"] = 1,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["stepAngle"] = 15,
["config"] = {
},
["xOffset"] = 124.9630737304688,
["borderInset"] = 1,
["conditions"] = {
},
["information"] = {
},
["internalVersion"] = 77,
},
["Player Power"] = {
["sparkWidth"] = 10,
["sparkOffsetX"] = 0,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -416.7899980545044,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["sparkRotationMode"] = "AUTO",
["icon"] = false,
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["event"] = "Power",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["use_unit"] = true,
["unit"] = "player",
["names"] = {
},
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["icon_color"] = {
1,
1,
1,
1,
},
["internalVersion"] = 77,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["barColor"] = {
0.2549019753932953,
0.501960813999176,
0.7372549176216125,
1,
},
["desaturate"] = false,
["width"] = 181.8262481689453,
["sparkOffsetY"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%1.power / %1.maxpower",
["text_text_format_p_time_mod_rate"] = true,
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "CENTER",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorXOffset"] = 0,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["text_text_format_1.health_format"] = "none",
["text_text_format_1.power_format"] = "none",
["text_text_format_1.maxpower_format"] = "none",
["text_text_format_p_time_format"] = 0,
["type"] = "subtext",
["text_text_format_p_time_legacy_floor"] = false,
["text_color"] = {
1,
1,
1,
1,
},
["text_text_format_1.maxhealth_format"] = "none",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = -1,
["text_fontType"] = "None",
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_anchorPoint"] = "INNER_CENTER",
["text_font"] = "Friz Quadrata TT",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_fontSize"] = 12,
["text_text_format_p_time_dynamic_threshold"] = 60,
["rotateText"] = "NONE",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%n",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowYOffset"] = -1,
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_anchorPoint"] = "INNER_RIGHT",
["text_fontType"] = "None",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_n_format"] = "none",
},
{
["border_offset"] = 0,
["border_anchor"] = "bar",
["border_size"] = 1,
["border_color"] = {
0.4745098352432251,
0.4745098352432251,
0.4745098352432251,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 14.99999237060547,
["textureSource"] = "LSM",
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["xOffset"] = -240.2,
["information"] = {
},
["parent"] = "Bars",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["uid"] = "zsMOZIzPa((",
["config"] = {
},
["icon_side"] = "RIGHT",
["zoom"] = 0,
["sparkHeight"] = 30,
["texture"] = "Clean",
["alpha"] = 1,
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = false,
["id"] = "Player Power",
["sparkHidden"] = "NEVER",
["backgroundColor"] = {
0,
0,
0,
1,
},
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["gradientOrientation"] = "HORIZONTAL",
["sparkColor"] = {
1,
1,
1,
1,
},
["inverse"] = false,
["enableGradient"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["barColor2"] = {
1,
1,
0,
1,
},
["iconSource"] = -1,
},
["Bars"] = {
["backdropColor"] = {
1,
1,
1,
0.5,
},
["controlledChildren"] = {
"Target Power",
"Target Health",
"Player Power",
"Player Health",
"Player Cast Bar",
"Target Cast Bar",
},
["borderBackdrop"] = "Blizzard Tooltip",
["authorOptions"] = {
},
["borderEdge"] = "Square Full White",
["border"] = false,
["yOffset"] = 0,
["regionType"] = "group",
["borderSize"] = 2,
["selfPoint"] = "CENTER",
["borderColor"] = {
0,
0,
0,
1,
},
["scale"] = 1,
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["triggers"] = {
{
["trigger"] = {
["debuffType"] = "HELPFUL",
["type"] = "aura2",
["spellIds"] = {
},
["subeventSuffix"] = "_CAST_START",
["unit"] = "player",
["subeventPrefix"] = "SPELL",
["event"] = "Health",
["names"] = {
},
},
["untrigger"] = {
},
},
},
["anchorPoint"] = "CENTER",
["borderOffset"] = 4,
["xOffset"] = 0,
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["id"] = "Bars",
["internalVersion"] = 77,
["frameStrata"] = 1,
["anchorFrameType"] = "SCREEN",
["config"] = {
},
["borderInset"] = 1,
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["subRegions"] = {
},
["alpha"] = 1,
["conditions"] = {
},
["information"] = {
},
["uid"] = "IBVq0w6H5KE",
},
["Player Health"] = {
["sparkWidth"] = 10,
["iconSource"] = -1,
["xOffset"] = -240,
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -396.6421337127686,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["sparkRotationMode"] = "AUTO",
["icon"] = false,
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["event"] = "Health",
["subeventPrefix"] = "SPELL",
["spellIds"] = {
},
["use_unit"] = true,
["names"] = {
},
["unit"] = "player",
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["icon_color"] = {
1,
1,
1,
1,
},
["internalVersion"] = 77,
["progressSource"] = {
-1,
"",
},
["selfPoint"] = "CENTER",
["barColor"] = {
0.2627451121807098,
0.8705883026123047,
0,
1,
},
["desaturate"] = false,
["anchorFrameType"] = "SCREEN",
["sparkOffsetY"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%1.health / %1.maxhealth",
["text_text_format_p_time_mod_rate"] = true,
["text_selfPoint"] = "CENTER",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_1.health_format"] = "none",
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["type"] = "subtext",
["text_text_format_1.maxhealth_format"] = "none",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = -1,
["text_visible"] = true,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "None",
["text_anchorPoint"] = "INNER_CENTER",
["text_text_format_p_time_legacy_floor"] = false,
["text_text_format_p_time_format"] = 0,
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_p_format"] = "timed",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%n",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["type"] = "subtext",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_shadowYOffset"] = -1,
["text_wordWrap"] = "WordWrap",
["text_visible"] = false,
["text_anchorPoint"] = "INNER_RIGHT",
["text_text_format_n_format"] = "none",
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_fontType"] = "None",
},
{
["border_offset"] = 0,
["border_anchor"] = "bar",
["border_size"] = 1,
["border_color"] = {
0.4745098352432251,
0.4745098352432251,
0.4745098352432251,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["height"] = 14.99999237060547,
["textureSource"] = "LSM",
["load"] = {
["size"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["talent"] = {
["multi"] = {
},
},
},
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["sparkOffsetX"] = 0,
["barColor2"] = {
1,
1,
0,
1,
},
["parent"] = "Bars",
["actions"] = {
["start"] = {
},
["init"] = {
},
["finish"] = {
},
},
["animation"] = {
["start"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["type"] = "none",
["easeStrength"] = 3,
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["config"] = {
},
["uid"] = "hQSAxy3zwQR",
["icon_side"] = "RIGHT",
["zoom"] = 0,
["sparkHeight"] = 30,
["texture"] = "Clean",
["frameStrata"] = 1,
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = false,
["gradientOrientation"] = "HORIZONTAL",
["id"] = "Player Health",
["sparkHidden"] = "NEVER",
["alpha"] = 1,
["width"] = 181.8262481689453,
["authorOptions"] = {
},
["sparkColor"] = {
1,
1,
1,
1,
},
["inverse"] = false,
["enableGradient"] = false,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["information"] = {
},
["backgroundColor"] = {
0,
0,
0,
1,
},
},
["Player Cast Bar"] = {
["sparkWidth"] = 10,
["iconSource"] = -1,
["authorOptions"] = {
},
["adjustedMax"] = "",
["adjustedMin"] = "",
["yOffset"] = -374.9137391690842,
["anchorPoint"] = "CENTER",
["sparkRotation"] = 0,
["sparkRotationMode"] = "AUTO",
["icon"] = true,
["triggers"] = {
{
["trigger"] = {
["type"] = "unit",
["subeventSuffix"] = "_CAST_START",
["use_genericShowOn"] = true,
["event"] = "Cast",
["subeventPrefix"] = "SPELL",
["genericShowOn"] = "showOnCooldown",
["use_spellName"] = true,
["spellIds"] = {
},
["unit"] = "player",
["names"] = {
},
["use_unit"] = true,
["use_track"] = true,
["debuffType"] = "HELPFUL",
},
["untrigger"] = {
},
},
["activeTriggerMode"] = -10,
},
["icon_color"] = {
1,
1,
1,
1,
},
["enableGradient"] = false,
["progressSource"] = {
-1,
"",
},
["animation"] = {
["start"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["main"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
["finish"] = {
["easeStrength"] = 3,
["type"] = "none",
["duration_type"] = "seconds",
["easeType"] = "none",
},
},
["barColor"] = {
0.7372549176216125,
0.615686297416687,
0,
1,
},
["desaturate"] = false,
["width"] = 181.8262481689453,
["sparkOffsetY"] = 0,
["subRegions"] = {
{
["type"] = "subbackground",
},
{
["type"] = "subforeground",
},
{
["text_text_format_p_time_format"] = 0,
["text_text"] = "%1.name",
["text_text_format_p_format"] = "timed",
["text_selfPoint"] = "CENTER",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["text_shadowColor"] = {
0,
0,
0,
1,
},
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["anchorXOffset"] = 0,
["text_text_format_1.health_format"] = "none",
["text_shadowXOffset"] = 1,
["type"] = "subtext",
["text_text_format_p_time_legacy_floor"] = false,
["text_color"] = {
1,
1,
1,
1,
},
["text_text_format_1.maxhealth_format"] = "none",
["text_text_format_p_time_precision"] = 1,
["text_shadowYOffset"] = -1,
["text_fontType"] = "None",
["text_wordWrap"] = "WordWrap",
["text_visible"] = true,
["text_anchorPoint"] = "INNER_CENTER",
["text_font"] = "Friz Quadrata TT",
["text_text_format_p_time_mod_rate"] = true,
["text_fontSize"] = 12,
["text_text_format_p_time_dynamic_threshold"] = 60,
["text_text_format_1.name_format"] = "none",
},
{
["text_shadowXOffset"] = 1,
["text_text"] = "%1.t",
["text_shadowColor"] = {
0,
0,
0,
1,
},
["text_selfPoint"] = "AUTO",
["text_automaticWidth"] = "Auto",
["text_fixedWidth"] = 64,
["anchorYOffset"] = 0,
["text_justify"] = "CENTER",
["rotateText"] = "NONE",
["text_text_format_1.t_time_mod_rate"] = true,
["text_text_format_1.t_time_precision"] = 1,
["type"] = "subtext",
["text_text_format_n_format"] = "none",
["text_color"] = {
1,
1,
1,
1,
},
["text_font"] = "Friz Quadrata TT",
["text_visible"] = true,
["text_shadowYOffset"] = -1,
["text_text_format_1.t_time_dynamic_threshold"] = 60,
["text_wordWrap"] = "WordWrap",
["text_fontType"] = "None",
["text_anchorPoint"] = "INNER_RIGHT",
["text_text_format_1.t_format"] = "timed",
["text_text_format_1.t_time_format"] = 0,
["text_fontSize"] = 12,
["anchorXOffset"] = 0,
["text_text_format_1.t_time_legacy_floor"] = false,
},
{
["border_offset"] = 0,
["border_anchor"] = "bar",
["border_size"] = 1,
["border_color"] = {
0.4745098352432251,
0.4745098352432251,
0.4745098352432251,
1,
},
["border_visible"] = true,
["border_edge"] = "Square Full White",
["type"] = "subborder",
},
},
["gradientOrientation"] = "HORIZONTAL",
["textureSource"] = "LSM",
["load"] = {
["talent"] = {
["multi"] = {
},
},
["spec"] = {
["multi"] = {
},
},
["class"] = {
["multi"] = {
},
},
["size"] = {
["multi"] = {
},
},
},
["sparkBlendMode"] = "ADD",
["useAdjustededMax"] = false,
["xOffset"] = -240,
["information"] = {
},
["parent"] = "Bars",
["backgroundColor"] = {
0,
0,
0,
1,
},
["selfPoint"] = "CENTER",
["useAdjustededMin"] = false,
["regionType"] = "aurabar",
["config"] = {
},
["sparkColor"] = {
1,
1,
1,
1,
},
["icon_side"] = "RIGHT",
["actions"] = {
["start"] = {
},
["finish"] = {
},
["init"] = {
},
},
["sparkHeight"] = 30,
["texture"] = "Clean",
["frameStrata"] = 5,
["sparkTexture"] = "Interface\\CastingBar\\UI-CastingBar-Spark",
["spark"] = false,
["sparkHidden"] = "NEVER",
["id"] = "Player Cast Bar",
["zoom"] = 0,
["alpha"] = 1,
["anchorFrameType"] = "SCREEN",
["height"] = 14.99999237060547,
["uid"] = "zcnQyZ5TU(L",
["inverse"] = false,
["internalVersion"] = 77,
["orientation"] = "HORIZONTAL",
["conditions"] = {
},
["barColor2"] = {
1,
1,
0,
1,
},
["sparkOffsetX"] = 0,
},
},
["historyCutoff"] = 730,
["lastArchiveClear"] = 1725060290,
["minimap"] = {
["hide"] = false,
},
["lastUpgrade"] = 1726353418,
["dbVersion"] = 77,
["migrationCutoff"] = 730,
["registered"] = {
},
["login_squelch_time"] = 10,
["features"] = {
},
["editor_font_size"] = 12,
}

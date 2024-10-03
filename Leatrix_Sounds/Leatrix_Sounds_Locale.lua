----------------------------------------------------------------------
-- Leatrix Sounds Locale
----------------------------------------------------------------------

-- Create locale structure
local GameLocale = GetLocale()
local void, Leatrix_Sounds = ...
local function localeFunc(L, key) return key end
local L = setmetatable({}, {__index = localeFunc})
Leatrix_Sounds.L = L

-- Locale override (enUS, zhCN, zhTW, ruRU, koKR, deDE, esMX, frFR, itIT, ptBR)
-- GameLocale = "enUS"

-- zhCN: Simplified Chinese (People's Republic of China)
if GameLocale == "zhCN" then

end

-- zhTW: Traditional Chinese (Taiwan)
if GameLocale == "zhTW" then

end

-- ruRU: Russian
if GameLocale == "ruRU" then

end

-- koKR: Korean
if GameLocale == "koKR" then

end

-- deDE: German
if GameLocale == "deDE" then
	
end

-- esMX: Spanish (Mexico)
if GameLocale == "esMX" then

end

-- esES: Spanish (Spain)
if GameLocale == "esES" then

end

-- frFR: French
if GameLocale == "frFR" then

end

-- itIT: Italian
if GameLocale == "itIT" then

end

-- ptBR: Portugese (Brazil)
if GameLocale == "ptBR" then

end

local addonName = ...
local BetterFishing = {}
local internal = {
  -- Defaults
  _frame = CreateFrame("frame"),
  clear_override = false,
  cvarsChanged = false,
  DOUBLECLICK_MIN_SECONDS = 0.04,
  previousClickTime = 0,
  isClassic = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE,
}

local soundCache = {}
local CVarCacheSounds = {
  "Sound_MasterVolume",
  "Sound_SFXVolume",
  "Sound_EnableAmbience",
  "Sound_MusicVolume",
  "Sound_EnableAllSound",
  "Sound_EnablePetSounds",
  "Sound_EnableSoundWhenGameIsInBG",
  "Sound_EnableSFX",
}

BINDING_NAME_BETTERFISHINGKEY = "Cast and Interact"

local ClassicFishingIDs = {
  7620, 7731, 7732, 18248, 33095, 51294, 88868
}

function BetterFishing:GetFishingCastID()
  if internal.isClassic then
    for i=1, #ClassicFishingIDs do
      if IsSpellKnown(ClassicFishingIDs[i]) then
        return ClassicFishingIDs[i]
      end
    end
  end

  return 131476
end

function BetterFishing:GetFishingID()
  if internal.isClassic then
    for i=1, #ClassicFishingIDs do
      if IsSpellKnown(ClassicFishingIDs[i]) then
        return ClassicFishingIDs[i]
      end
    end
  end

  return 131474
end

function BetterFishing:GetFishingName()
  local GetSpellName = GetSpellInfo or C_Spell.GetSpellName
  -- technically 7620 exists on every version but still add mainline fallback if for some reason not
  local localizedName = GetSpellName(7620)
  return localizedName or GetSpellName(131474)
end

local function IsTaintable()
  return (InCombatLockdown() or (UnitAffectingCombat("player") or UnitAffectingCombat("pet")))
end

function BetterFishing:GetSecureButton()
  if not self.secureButton then
    local button = CreateFrame("Button", addonName.."Button", nil, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", self:GetFishingID())
    button:SetScript("PostClick", function(self, mouse_button, down)
      MouselookStart()
      if down then return end
      MouselookStop()
    end)
    SecureHandlerWrapScript(button, "PostClick", button,  string.format([[
      local isClassic = %s
      if isClassic == true then
        self:ClearBindings()
      else
        if not down then
          self:ClearBindings()
        end
      end
    ]], tostring(internal.isClassic)))

    self.secureButton = button
  end
  return self.secureButton
end

function BetterFishing:IsFlying()
  -- Check for Zen Flight
  if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(125883) then
    return false
  else
    return IsFlying()
  end
end

function BetterFishing_Run()
  if IsTaintable() or BetterFishing:IsFlying() or GetNumLootItems() ~= 0 or BetterFishing:IsFishing() or (not BetterFishingDB.overrideLunker and BetterFishing:IsLunkerActive()) then return end
  local key1, key2 = GetBindingKey("BETTERFISHINGKEY")
  local localizedName = BetterFishing:GetFishingName()
  if key1 then
    SetOverrideBindingSpell(BetterFishing:GetSecureButton(), 1, key1, localizedName)
  end
  if key2 then
    SetOverrideBindingSpell(BetterFishing:GetSecureButton(), 2, key2, localizedName)
  end
end

WorldFrame:HookScript("OnMouseDown", function(_, button, down)
  if not BetterFishingDB.doubleClickEnabled then return end
  if button == "RightButton" and not IsTaintable() then
    if GetNumLootItems() == 0 then
      local doubleClickTime = GetTime() - internal.previousClickTime
      if (doubleClickTime >= internal.DOUBLECLICK_MIN_SECONDS and doubleClickTime <= BetterFishingDB.doubleClickSpeed) then
        if BetterFishing:AllowFishing() then
          SetOverrideBindingClick(BetterFishing:GetSecureButton(), true, "BUTTON2", addonName.."Button")
        end
        internal.previousClickTime = nil
      end
    end
    internal.previousClickTime = GetTime()
  end
end)

function BetterFishing:IsFishing()
  local spellID = select(8,UnitChannelInfo("player"))
  if spellID == self:GetFishingCastID() or spellID == 377895 then
    return true
  end
  return false
end

function BetterFishing:IsLunkerActive()
  local spellID = select(8,UnitChannelInfo("player"))
  if spellID == 392270 then
    return true
  end
  return false
end

function BetterFishing:IsFishingpoleEquipped()
  local itemID = GetInventoryItemID("player", INVSLOT_MAINHAND)
  if itemID then
    local subclassID = select(7, C_Item.GetItemInfoInstant(itemID))
    if subclassID and subclassID == Enum.ItemWeaponSubclass.Fishingpole then
      return true
    end
  end
  return false
end

function BetterFishing:AllowFishing()
  if not IsSpellKnown(self:GetFishingID())
  or internal.isClassic and not self:IsFishingpoleEquipped()
  or IsPlayerMoving()
  or IsMounted()
  or BetterFishing:IsFlying()
  or IsFalling()
  or IsStealthed()
  or IsSwimming()
  or IsSubmerged()
  or not HasFullControl()
  or UnitHasVehicleUI("player")
  or IsInInstance() and GetNumGroupMembers() > 1 then
    return false
  end

  if self:IsFishing() and not BetterFishingDB.recastOnDoubleClick or (not BetterFishingDB.overrideLunker and self:IsLunkerActive()) then
    return false
  end

  return true
end

local InteractCVarTable = {
  "SoftTargetInteract",
  "SoftTargetInteractArc",
  "SoftTargetInteractRange",
  "SoftTargetIconGameObject",
  "SoftTargetIconInteract"
}

local InteractCVars = {}

do
  for _, cvar in ipairs(InteractCVarTable) do
    InteractCVars[string.lower(cvar)] = GetCVar(cvar)
  end
end

hooksecurefunc(C_CVar, "SetCVar", function(cvar, value)
	if internal.cvarsChanged then return end
  local cvar_lower = string.lower(cvar)
  if InteractCVars[cvar_lower] then
    InteractCVars[cvar_lower] = value
  end
end)

function BetterFishing:ResetCVars(logout)
  if not logout then
    internal.cvarsChanged = true
  end
  BetterFishing:EnhanceSounds(false)
  for cvar, value in pairs(InteractCVars) do
    SetCVar(cvar, value)
  end
  C_Timer.After(0.2, function() internal.cvarsChanged = false end)
end

function BetterFishing:SetCVars()
  internal.cvarsChanged = true
  BetterFishing:EnhanceSounds(true)
  SetCVar("SoftTargetInteract", 3);
  SetCVar("SoftTargetInteractArc", 2);
  SetCVar("SoftTargetInteractRange", 25);
  SetCVar("SoftTargetIconGameObject", BetterFishingDB.objectIconDisabled and 0 or 1);
  SetCVar("SoftTargetIconInteract", BetterFishingDB.objectIconDisabled and 0 or 1);
  C_Timer.After(0.2, function() internal.cvarsChanged = false end)
end

function BetterFishing:OnEvent(event, ...)
  if event == "ADDON_LOADED" and addonName == ... then
    BetterFishingDB = BetterFishingDB or {};
  elseif event == "PLAYER_REGEN_ENABLED" then
    if internal.clear_override then
      ClearOverrideBindings(BetterFishing:GetSecureButton())
      internal.clear_override = false
      BetterFishing:ResetCVars()
    end
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    local unit,_,spellID = ...
    if unit == "player" and (spellID == self:GetFishingCastID() or spellID == 377895) then
      BetterFishing:SetCVars()
      if IsTaintable() then return end
      local key1, key2 = GetBindingKey("BETTERFISHINGKEY")
      if key1 then
        SetOverrideBinding(BetterFishing:GetSecureButton(), true, key1, "INTERACTTARGET")
      end
      if key2 then
        SetOverrideBinding(BetterFishing:GetSecureButton(), true, key2, "INTERACTTARGET")
      end
    end
  elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
    local unit,_,spellID = ...
    if unit == "player" and (spellID == self:GetFishingCastID() or spellID == 377895) then
      if not IsTaintable() then
        BetterFishing:ResetCVars()
        ClearOverrideBindings(BetterFishing:GetSecureButton());
      else
        internal.clear_override = true;
      end
    end
  elseif event == "PLAYER_LOGOUT" then
    BetterFishing:ResetCVars(true)
  elseif event == "CVAR_UPDATE" then
    if self:IsFishing() then return end
    for i = 1, #CVarCacheSounds do
      if CVarCacheSounds[i] == ... then
        soundCache[CVarCacheSounds[i]] = GetCVar(...);
      end
    end
  end
end

internal._frame:SetScript("OnEvent", function(self, ...) BetterFishing:OnEvent(...) end)
FrameUtil.RegisterFrameForEvents(internal._frame, {
  "ADDON_LOADED",
  "PLAYER_REGEN_ENABLED",
  "UNIT_SPELLCAST_CHANNEL_START",
  "UNIT_SPELLCAST_CHANNEL_STOP",
  "CVAR_UPDATE",
  "PLAYER_LOGOUT"
})

function BetterFishing:EnhanceSounds(enable)
  if not BetterFishingDB.enhanceSounds then return end

  if not enable then
    for i = 1, #CVarCacheSounds do
      if soundCache[CVarCacheSounds[i]] then
        SetCVar(CVarCacheSounds[i], soundCache[CVarCacheSounds[i]])
      end
    end
  else
    for i = 1, #CVarCacheSounds do
      soundCache[CVarCacheSounds[i]] = GetCVar(CVarCacheSounds[i])
      SetCVar(CVarCacheSounds[i], 0)
    end
    SetCVar("Sound_EnableAmbience", 0)
    SetCVar("Sound_MusicVolume", 0)
    SetCVar("Sound_EnablePetSounds", 0)

    SetCVar("Sound_EnableSFX", 1)
    SetCVar("Sound_EnableSoundWhenGameIsInBG", 1)
    SetCVar("Sound_EnableAllSound", 1)
    BetterFishingDB.enhanceSoundsScale = BetterFishingDB.enhanceSoundsScale or 1
    SetCVar("Sound_SFXVolume", BetterFishingDB.enhanceSoundsScale)
    SetCVar("Sound_MasterVolume", BetterFishingDB.enhanceSoundsScale)
  end
end
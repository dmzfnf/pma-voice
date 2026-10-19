local wasProximityDisabledFromOverride = false
disableProximityCycle = false
RegisterCommand('setvoiceintent', function(source, args)
	if GetConvarInt('voice_allowSetIntent', 1) == 1 then
		local intent = args[1]
		if intent == 'speech' then
			MumbleSetAudioInputIntent(`speech`)
		elseif intent == 'music' then
			MumbleSetAudioInputIntent(`music`)
		end
		LocalPlayer.state:set('voiceIntent', intent, true)
	end
end)

RegisterCommand('vol', function(_, args)
	if not args[1] then return end
	setVolume(tonumber(args[1]))
end)

exports('setAllowProximityCycleState', function(state)
	type_check({state, "boolean"})
	disableProximityCycle = state
end)

local proximityPreviewUntil = 0
local currentProximityRange
local function voicePreferenceKey()
 return 'hesslife_voice_range_' .. (GetConvar('voice_useNativeAudio', 'false') == 'true' and 'native' or 'standard')
end
function RestoreVoicePreference()
 local saved = GetResourceKvpInt(voicePreferenceKey())
 local max = GetConvar('voice_useNativeAudio', 'false') == 'true' and 15.0 or 30.0
 if saved > 0 then
  currentProximityRange = math.max(Cfg.voiceModes[1][1], math.min(max, saved / 100.0))
  mode = currentProximityRange <= Cfg.voiceModes[1][1] and 1 or currentProximityRange <= Cfg.voiceModes[2][1] and 2 or 3
 end
end
function GetVoiceDisplayIndex()
 return GetCurrentVoiceProximityRange() > Cfg.voiceModes[3][1] and #Cfg.voiceModes or mode - 1
end
function GetVoiceDisplayName()
 return GetCurrentVoiceProximityRange() > Cfg.voiceModes[3][1] and 'Crier' or Cfg.voiceModes[mode][2]
end
function GetCurrentVoiceProximityRange()
 return currentProximityRange or Cfg.voiceModes[mode][1]
end

function setProximityState(proximityRange, isCustom)
 currentProximityRange = proximityRange
 if not isCustom then SetResourceKvpInt(voicePreferenceKey(), math.floor(proximityRange * 100.0 + 0.5)) end
	local voiceModeData = Cfg.voiceModes[mode]
	MumbleSetTalkerProximity(proximityRange + 0.0)
	LocalPlayer.state:set('proximity', {
		index = mode,
		distance = proximityRange,
		mode = isCustom and "Personnalisé" or GetVoiceDisplayName(),
	}, true)
	sendUIMessage({
		-- JS expects this value to be - 1, "custom" voice is on the last index
		voiceMode = isCustom and #Cfg.voiceModes or GetVoiceDisplayIndex()
	})
end

exports("overrideProximityRange", function(range, disableCycle)
	type_check({range, "number"})
	setProximityState(range, true)
	if disableCycle then
		disableProximityCycle = true
		wasProximityDisabledFromOverride = true
	end
end)

exports("clearProximityOverride", function()
	local voiceModeData = Cfg.voiceModes[mode]
	setProximityState(voiceModeData[1], false)
	if wasProximityDisabledFromOverride then
		disableProximityCycle = false
	end
end)

RegisterCommand('cycleproximity', function()
	-- Proximity is either disabled, or manually overwritten.
	if GetConvarInt('voice_enableProximityCycle', 1) ~= 1 or disableProximityCycle then return end
	local newMode = mode + 1

	-- If we're within the range of our voice modes, allow the increase, otherwise reset to the first state
	if newMode <= #Cfg.voiceModes then
		mode = newMode
	else
		mode = 1
	end

	setProximityState(Cfg.voiceModes[mode][1], false)
	proximityPreviewUntil = GetGameTimer() + 1500
	TriggerEvent('pma-voice:setTalkingMode', mode)
end, false)
if gameVersion == 'fivem' then
	RegisterKeyMapping('cycleproximity', 'Cycle Proximity', 'keyboard', GetConvar('voice_defaultCycle', 'F11'))
end

local function drawProximityPreview()
 local ped = PlayerPedId()
 if not DoesEntityExist(ped) then return end
 local coords = GetEntityCoords(ped)
 local found, ground = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 0.5, false)
 local z = found and ground + 0.04 or coords.z - 0.95
 local radius = GetCurrentVoiceProximityRange()
 local inner, outer = math.max(0.0, radius - 0.04), radius + 0.04
 local previousInnerX, previousInnerY = coords.x + inner, coords.y
 local previousOuterX, previousOuterY = coords.x + outer, coords.y
 for i = 1, 96 do
  local angle = i * (math.pi * 2.0 / 96)
  local cosine, sine = math.cos(angle), math.sin(angle)
  local innerX, innerY = coords.x + cosine * inner, coords.y + sine * inner
  local outerX, outerY = coords.x + cosine * outer, coords.y + sine * outer
  DrawPoly(previousInnerX, previousInnerY, z, previousOuterX, previousOuterY, z, outerX, outerY, z, 145, 65, 220, 210)
  DrawPoly(previousInnerX, previousInnerY, z, outerX, outerY, z, innerX, innerY, z, 145, 65, 220, 210)
  previousInnerX, previousInnerY = innerX, innerY
  previousOuterX, previousOuterY = outerX, outerY
 end
end

local function adjustWheelProximity(direction)
 if disableProximityCycle or GetConvarInt('voice_enableProximityCycle', 1) ~= 1 then return end
 local native = GetConvar('voice_useNativeAudio', 'false') == 'true'
 local range = math.max(Cfg.voiceModes[1][1], math.min(native and 15.0 or 30.0,
  GetCurrentVoiceProximityRange() + direction * (native and 0.5 or 1.0)))
 if range == GetCurrentVoiceProximityRange() then return end
 proximityPreviewUntil = GetGameTimer() + 1500
 local previousMode = mode
 mode = range <= Cfg.voiceModes[1][1] and 1 or range <= Cfg.voiceModes[2][1] and 2 or 3
 setProximityState(range, false)
 if previousMode ~= mode then TriggerEvent('pma-voice:setTalkingMode', mode) end
end

if gameVersion == 'fivem' then
 CreateThread(function()
  while true do
   local ctrl = IsControlPressed(0, 36) or IsDisabledControlPressed(0, 36)
   if ctrl and not IsPauseMenuActive() and not IsNuiFocused() then
    DisableControlAction(0, 14, true)
    DisableControlAction(0, 15, true)
    DisableControlAction(0, 16, true)
    DisableControlAction(0, 17, true)
    DisableControlAction(0, 241, true)
    DisableControlAction(0, 242, true)
    if IsDisabledControlJustPressed(0, 241) then adjustWheelProximity(1)
    elseif IsDisabledControlJustPressed(0, 242) then adjustWheelProximity(-1) end
    drawProximityPreview()
    Wait(0)
   elseif GetGameTimer() < proximityPreviewUntil and not IsPauseMenuActive() and not IsNuiFocused() then
    drawProximityPreview()
    Wait(0)
   else
   Wait(100)
         end
      end
   end)
end

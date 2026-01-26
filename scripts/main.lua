local uevrUtils = require('libs/uevr_utils')
local controllers = require('libs/controllers')
local configui = require("libs/configui")
local reticule = require("libs/reticule")
local hands = require('libs/hands')
local attachments = require('libs/attachments')
local input = require('libs/input')
local pawnModule = require('libs/pawn')
local montage = require('libs/montage')
local interaction = require('libs/interaction')
local ui = require('libs/ui')
local remap = require('libs/remap')
local gestures = require('libs/gestures')
local gunstock = require('libs/gunstock')
--local scope = require('libs/scope')
local flickerFixer = require('libs/flicker_fixer')
--local dev = require('libs/uevr_dev')
--dev.init()

-- uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- -- input.setLogLevel(LogLevel.Debug)
-- attachments.setLogLevel(LogLevel.Debug)
-- -- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- --flickerFixer.setLogLevel(LogLevel.Debug)
-- --hands.setLogLevel(LogLevel.Debug)

-- uevrUtils.setDeveloperMode(true)

-- --hands.enableConfigurationTool()
ui.init()
ui.setRequireWidgetOpenState(true)
montage.init()
montage.addMeshMonitor("Arms", "Pawn.FPVMesh")
interaction.init()
attachments.init()
reticule.init()
pawnModule.init()
remap.init()
input.init()
gunstock.showConfiguration()

local versionTxt = "v1.0.0"
local title = "The Outer Worlds Spacer Choice Edition First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "The Outer Worlds Config",
		saveFile = "tow_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200}, {id="uevr_reticule_eye_dominance_offset", initialValue=2.0, isHidden=true}}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "UI" }, { widgetType = "begin_rect", },
				expandArray(ui.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Input" }, { widgetType = "begin_rect", },
				expandArray(input.getConfigurationWidgets),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
				{
					widgetType = "combo",
					id = "interaction_control_mode",
					label = "Interaction Controls",
					selections = {"Vanilla", "Mixed", "Full Immersion"},
					initialValue = 1,
					width = 200,
				},
				-- {
				-- 	widgetType = "checkbox",
				-- 	id = "full_body_mode",
				-- 	label = "Full Body Mode (experimental)",
				-- 	initialValue = true
				-- },
				-- {
				-- 	widgetType = "checkbox",
				-- 	id = "left_handed_mode",
				-- 	label = "Left Handed",
				-- 	initialValue = true
				-- },
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}
configui.create(configDefinition)

local status = {}
attachments.init(nil, nil, {0,0,0}, {0,0,0})

local function hasValidScope(parent)
	local weaponMode = uevrUtils.getValid(pawn,{"Equipment","EquippedWeapon","PrimaryMode"})
	if weaponMode ~= nil then
		return weaponMode:HasScope()
	end
	return false
end

attachments.registerOnScopeUpdateCallback(function(attachment)
	return hasValidScope(attachment)
end)

local function getWeaponMesh()
	if uevrUtils.getValid(pawn) ~= nil and pawn.GetCurrentWeapon ~= nil then
		local currentWeapon = pawn:GetCurrentWeapon()
		if currentWeapon ~= nil then 
			local weaponMesh = currentWeapon.SkeletalMeshComponent
			if weaponMesh ~= nil then
				--some games mess with the weapon FOV and that needs to be fixed programatically
				uevrUtils.fixMeshFOV(weaponMesh, "ForegroundPriorityEnabled", 0.0, true, true, false)
				return weaponMesh
			end
		end
	end
	return nil
end

attachments.registerOnGripUpdateCallback(function()
    local weaponMesh = getWeaponMesh()
    if configui.getValue("left_handed_mode") then
        return nil,nil,nil,weaponMesh, hands.getHandComponent(Handed.Left)  --, controllers.getController(Handed.Left)
    else
		local handsComponent = hands.getHandComponent(Handed.Right)
        return handsComponent and weaponMesh, handsComponent --, controllers.getController(Handed.Right)
    end
	--return getWeaponMesh(), controllers.getController(Handed.Right)
end)

function on_level_change(level)
	print("Level changed\n")
	flickerFixer.create()
end

--when leaving the inventory, destroy the current hands so if gloves changed the new ones are created
ui.registerWidgetChangeCallback("Ledger_BP_C", function(active)
	if not active then
        hands.destroyHands()
	end
end)

--fix the pawn mesh fov (not really necessary because pawn is hidden but in case we decide to show arms during montages)
setInterval(1000, function()
	if pawn and pawn.FPVMesh ~= nil then
		--check pawn.bFixedFovForFPVEnabled
		uevrUtils.fixMeshFOV(pawn.FPVMesh, "ForegroundPriorityEnabled", 0.0, true, true, false)
	end
end)

-- Weapon FX get created at fire time so this needs to be called per tick
-- NiagaraComponent children get added and do not get deleted on each fire so the childlist could get 
--   large as the game proceeds
local function fixWeaponFXFOV()
	local propertyName = "ForegroundPriorityEnabled"
	local value = 0.0
	
	if pawn.GetCurrentWeapon ~= nil then
		local weapon = pawn:GetCurrentWeapon()
		if weapon ~= nil  then
			local mesh = weapon.SkeletalMeshComponent
			if mesh ~= nil then
				local children = mesh.AttachChildren
				if children ~= nil then
					for i, child in ipairs(children) do				
						if child:is_a(uevrUtils.get_class("Class /Script/Niagara.NiagaraComponent")) then
							child:SetNiagaraVariableFloat(propertyName, value)
							--print("Child Niagara Material:", child:get_full_name(),"\n")
						end
					end
				end
			end
		end
	end
end

function on_pre_engine_tick(engine, delta)
	fixWeaponFXFOV()

	local primaryMode = uevrUtils.getValid(pawn,{"Equipment","EquippedWeapon","PrimaryMode"})
	if primaryMode ~= nil and primaryMode.FiringAngle ~= nil then
		if status["grenadeLauncherEquipped"] then
			-- local controllerRotation = controllers.getControllerRotation(Handed.Right)
			-- if controllerRotation ~= nil then
			-- 	primaryMode.FiringAngle = controllerRotation.Pitch + 10.0
			-- end
			local location, rotation = attachments.getActiveAttachmentTransforms(Handed.Right)
			if rotation ~= nil then
				primaryMode.FiringAngle = rotation.Pitch + 10.0
			end
		else
			primaryMode.FiringAngle = 0.0
		end
	end
end

attachments.registerAttachmentChangeCallback(function(id, hand, attachment)
	-- Reduces processing when no melee weapon is equipped
    local isRightMelee = attachments.isActiveAttachmentMelee(Handed.Right)
    local isLeftMelee = attachments.isActiveAttachmentMelee(Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isLeftMelee, Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isLeftMelee, Handed.Left)

	status["grenadeLauncherEquipped"] = false
	input.setOverridePawnRotationMode(nil)
	local equippedWeapon = uevrUtils.getValid(pawn,{"Equipment","EquippedWeapon"})
	if equippedWeapon ~= nil then
		if equippedWeapon:is_a(uevrUtils.get_class("BlueprintGeneratedClass /Game/Blueprints/WEAP/HvyWpn/Launcher/Ham_GrenadeLauncher/Ham_GrenadeLauncher_Weapon_Base.Ham_GrenadeLauncher_Weapon_Base_C")) then
			status["grenadeLauncherEquipped"] = true
			--grenade launcher direction works differently from all other weapons. It takes its
			--aim direction from the direction the pawn is looking rather than from the FPVCamera.
			--To correct this we override pawn rotation mode to "Right Controller". This of course
			--means right controller controls pawn movement direction while the grenade launcher is equipped
			--but since its not a melee weapon, it seems like a good compromise.
			input.setOverridePawnRotationMode( input.PawnRotationMode.RIGHT_CONTROLLER)
		end
	end

end)
--won't callback unless an updateDeferral hasnt been called in the last 1000ms
uevrUtils.createDeferral("melee_attack", 1000, function()
    input.setAimRotationOffset({Pitch=0, Yaw=0, Roll=0})
end)

local function setMeleeOffset(hand)
    local offset = attachments.getActiveAttachmentMeleeRotationOffset(hand)
    if offset then
        input.setAimRotationOffset(offset)
        uevrUtils.updateDeferral("melee_attack")
    end
end

local status = {}
local monitorRightHand = true
local monitorLeftHand = false
gestures.registerSwipeRightCallback(function(strength, hand)
	if attachments.isActiveAttachmentMelee(hand) ~= true then
		return
	end
	setMeleeOffset(hand)
	delay(20, function()
		status["hasSwipe"] = true
	end)
end, monitorRightHand, monitorLeftHand)

gestures.registerSwipeLeftCallback(function(strength, hand)
	if attachments.isActiveAttachmentMelee(hand) ~= true then
		return
	end
	setMeleeOffset(hand)
	delay(20, function()
		status["hasSwipe"] = true
	end)
end, monitorRightHand, monitorLeftHand)

uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    if status["hasSwipe"] then
        print("Processing swipe gesture into input")
        state.Gamepad.bRightTrigger = 255
        status["hasSwipe"] = false
    end

	local interactionControlMode = configui.getValue("interaction_control_mode") or 1
	if interactionControlMode ~= 1 and (ui.isRemapDisabled()) ~= true then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = gestures.getHeadGestures(state, Handed.Left, false)
		if gripMouth then
			uevrUtils.pressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		else
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		end
	end
end, 5) --increased priority to get values before remap occurs

setInterval(1000, function()
	-- if pawn and pawn.HealthComponent ~= nil then 
	-- 	pawn.HealthComponent:SetHealthPercent(1.0)  --keep health full to avoid death during testing
	-- end

	local disguise = uevrUtils.getValid(pawn,{"Equipment","CurrentDisguise"})
	if status["currentDisguise"] ~= disguise then
		status["currentDisguise"] = disguise
		--print("Disguise changed to:", disguise)
		if disguise == nil then
			delay(100, function()
				hands.destroyHands()
				--hands.reapplyMaterials()
			end)
		end
	end
end)

local attackMontages = {
	AS_MeleeHvy_FP_BasicAttack_R2L_Hit_001_Montage = true,
	AS_MeleeLt_FP_BasicAttack_R2L_Hit_01_Montage = true,
}
montage.registerMontageChangeCallback(function(montageObject, montageName, label)
	--print("Montage changed callback:", montageName, label)
	if montageName ~= "" and label == "Arms" then
		local knownMontage = attackMontages[montageName]
		if knownMontage == true then
			montage.setPlaybackRate(montageObject, label, 10.0)
		end
	end
end)


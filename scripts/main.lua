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
local scopes = require('libs/scope')
local particlesConfigDev = require('libs/config/particles_config_dev')
local ik = require('libs/ik')
local animation = require('libs/animation')
local plugin = require('libs/core/plugin')

local flickerFixer = require('libs/flicker_fixer')

--uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- input.setLogLevel(LogLevel.Debug)
-- attachments.setLogLevel(LogLevel.Debug)
-- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- flickerFixer.setLogLevel(LogLevel.Debug)
-- hands.setLogLevel(LogLevel.Debug)
-- widgetModule.setLogLevel(LogLevel.Debug)
-- ik.setLogLevel(LogLevel.Debug)

--uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()
--uevrUtils.profiler:toggle(true)


ui.init()
ui.setRequireWidgetOpenState(true)
montage.init()
montage.addMeshMonitor("Arms", "Pawn.FPVMesh")
interaction.init()
attachments.init()
--attachments.setLaserColor("#00FFFFFF")
reticule.init()
reticule.setHiddenWhenScopeActive(true)
pawnModule.init()
remap.init()
input.init()
gunstock.showConfiguration()
scopes.setDefaultPitchOffset(90.0)
particlesConfigDev.init()
ik.init()
--laser.setLaserLengthPercentage(0.0)

--since weapons are attached to the hand sockets for this game
--only let the hands be affected by gunstock offsets
attachments.setGunstockOffsetsEnabled(false)
hands.setGunstockOffsetsEnabled(true)
ik.setGunstockOffsetsEnabled(true)

hands.setAutoCreateHands(false)
ik.setAutoCreateArms(false)

local settings = {}

local versionTxt = "v1.0.2"
local title = "The Outer Worlds Spacer Choice Edition First Person Mod " .. versionTxt
local configDefinition = {
	{
		panelLabel = "The Outer Worlds Config",
		saveFile = "tow_config",
		layout = spliceableInlineArray
		{
			{ widgetType = "text", id = "title", label = title },
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Control" }, { widgetType = "begin_rect", },
                {
                    widgetType = "combo",
                    id = "hands_type",
                    label = "Hands Type",
                    selections = {"Forearms", "IK Arms"},
                    initialValue = 1,
                },
				{
					widgetType = "combo",
					id = "interaction_control_mode",
					label = "Interaction Controls",
					selections = {"Vanilla", "Mixed", "Full Immersion"},
					initialValue = 1,
					width = 200,
				},
				{ widgetType = "begin_group", id = "interaction_info_group", isHidden = true },
				{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "How to use" }, { widgetType = "begin_rect", },
                { widgetType = "indent", width = 10 },
				{ widgetType = "text", wrapped = true, label = "Use inhaler: Grip with your left hand near your mouth", },
				{ widgetType = "text", wrapped = true, label = "Inventory: Left Grip near ear", },
				{ widgetType = "text", wrapped = true, label = "Time Dilation: Left Trigger near ear", },
				{ widgetType = "text", wrapped = true, label = "Jump: Right Stick forward", },
				{ widgetType = "text", wrapped = true, label = "Dodge: Right Stick back with Left Stick in direction of movement", },
				{ widgetType = "begin_group", id = "interaction_info_full_immersion_group", isHidden = true },
					{ widgetType = "text", wrapped = true, label = "Grab/Interact: Left or Right Grip", },
					{ widgetType = "text", wrapped = true, label = "Throw Grenade: Right Grip at your chest to equip the grenade", },
				{ widgetType = "end_group", },
                { widgetType = "unindent", width = 10 },
            	{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
				{ widgetType = "new_line" },
				{ widgetType = "end_group", },
				{
					widgetType = "checkbox",
					id = "idle_animation",
					label = "Idle Animation",
					initialValue = true
				},
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
			{ widgetType = "indent", width = 20 }, { widgetType = "text", label = "Reticule" }, { widgetType = "begin_rect", },
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200}, {id="uevr_reticule_eye_dominance_offset", initialValue=2.0, isHidden=false}}),
			{ widgetType = "end_rect", additionalSize = 12, rounding = 5 }, { widgetType = "unindent", width = 20 },
			{ widgetType = "new_line" },
		}
	}
}
local options = {
	{label = "Default", shape=ui.ShapeEnum.Flat, headLockedUISize = 2.0, headLockedUIPosition = {X=0.08, Y=-0.240, Z=2.0}},
	{label = "Helmet", shape=ui.ShapeEnum.Cylinder, headLockedUISize = 0.36, headLockedUIPosition = {X=0.0, Y=-0.07, Z=0.34}}
}
ui.setHeadLockedUIOptions(options)

local status = {}
local function cleanup()
    status = {}
end

local function setIdleCameraTimeout()
	local value = configui.getValue("idle_animation")
	local idleCamera = uevrUtils.getValid(pawn, {"IdleCamera"})
	if idleCamera ~= nil and idleCamera.SecondsToWait ~= nil then
		idleCamera.SecondsToWait = value and 60 or 60000
		--print("Idle animation timeout set to:", idleCamera.SecondsToWait)
	end
end

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

--This only needs to be run once when the weapon is activated
local function fixWeaponParticleSystemFOV()
	local propertyName = "ForegroundPriorityEnabled"
	local value = 0.0

	if pawn.GetCurrentWeapon ~= nil then
		local weapon = pawn:GetCurrentWeapon()
		if weapon ~= nil  then
			local mesh = weapon.SkeletalMeshComponent
			if mesh ~= nil then
				mesh:SetScalarParameterValueOnMaterials(propertyName, value)
				local children = mesh.AttachChildren
				if children ~= nil then
					for i, child in ipairs(children) do
						if child:is_a(uevrUtils.get_class("Class /Script/Engine.ParticleSystemComponent")) then
							child:SetFloatParameter(propertyName, value)
							-- local result = plugin.getProperty(child, "InstanceParameters")												
							-- for i, param in ipairs(result) do
							-- 	print(param.Name)
							-- 	if param.Name == propertyName then
							-- 		print("Setting ForegroundPriorityEnabled from:", param.Scalar, "to:", value)
							-- 		param.Scalar = value
							-- 	end
							-- end
						end
					end
				end
			end
		end
	end
end

local function getWeaponMesh()
	if status.isGrippingGrenade then
		return status.grenageMesh
	end
	if uevrUtils.getValid(pawn) ~= nil and pawn.GetCurrentWeapon ~= nil then
		local currentWeapon = pawn:GetCurrentWeapon()
		local anim = uevrUtils.getValid(pawn, {"FPVMesh","AnimScriptInstance"})
		local holstered = anim and anim.bWeaponIsHolstered
		if currentWeapon ~= nil and not holstered then
			local weaponMesh = currentWeapon.SkeletalMeshComponent
			if weaponMesh ~= nil then
				--some games mess with the weapon FOV and that needs to be fixed programatically
				uevrUtils.fixMeshFOV(weaponMesh, "ForegroundPriorityEnabled", 0.0, true, true, false)
				--for some reason changing the weapon causes the hands mesh FOV to revert to wrong value but changing the FPVMesh fixes it even though that makes no sense
				uevrUtils.fixMeshFOV(pawn.FPVMesh, "ForegroundPriorityEnabled", 0.0, true, true, false)
				return weaponMesh
			end
		end
	end
	return nil
end

attachments.registerOnGripUpdateCallback(function()
    local weaponMesh = getWeaponMesh()
    if configui.getValue("left_handed_mode") then
        return nil,nil,nil,weaponMesh, controllers.getController(Handed.Left)  --, controllers.getController(Handed.Left)
    else
		local handsComponent = status["ikMeshComponent"] or hands.getHandComponent(Handed.Right) --controllers.getController(Handed.Right) -- 
        if status["hasBoltActionFired"] == true then
			handsComponent = controllers.getController(Handed.Right)
		end
		--return handsComponent and weaponMesh, handsComponent, "WeaponPoint" --, controllers.getController(Handed.Right)
		local weaponAttachSocket = uevrUtils.getValid(pawn,{"Equipment","WeaponAttachSocket"}) or "WeaponPoint"
		return handsComponent and weaponMesh, handsComponent, weaponAttachSocket --, controllers.getController(Handed.Right)
    end
	--return getWeaponMesh(), controllers.getController(Handed.Right)
end)

local HandsType = {
	Forearms = 1,
	IKArms = 2,
}
local function regenerateHands(value)
	--detach attachments first so they dont get "lost" when hands are destroyed
	attachments.detachGripAttachments(Handed.Right)
	attachments.detachGripAttachments(Handed.Left)

	-- only allow autocreate of hands if using forearms
    hands.setAutoCreateHands(value == HandsType.Forearms)
    ik.setAutoCreateArms(value == HandsType.IKArms)

    status["ikMeshComponent"] = nil
    hands.destroyHands()
    ik.destroyAll()
end

configui.onUpdate("hands_type", function(value)
    regenerateHands(value)
end)

ik.registerOnMeshCreatedCallback(function(meshComponentList, ikInstance)
    --print("IK Mesh created:", meshComponent ~= nil, ikInstance ~= nil and ikInstance.rigId or "")
    local meshComponent = meshComponentList and meshComponentList[1] or nil
	if meshComponent ~= nil then
        meshComponent.bCastDynamicShadow = false
        meshComponent.bRenderInDepthPass = false
        animation.setComponent("left_arms", meshComponent)
		animation.setComponent("right_arms", meshComponent)
        status["ikMeshComponent"] = meshComponent
    end
end)

local function remapXIcon(val)
	if configui.getValue("interaction_control_mode") == 3 and ui.isRemapDisabled() ~= true then
		local XBOX_ICONS_DATA = "IndianaUIControllerIconsData /Game/UI/XboxOneControllerIcons.XboxOneControllerIcons"
		local iconsData = uevrUtils.find_required_object(XBOX_ICONS_DATA)
		if val then
			local XBOX_RB_TEXTURE = "Texture2D /Game/UI/Art/FrontEnd/General/Navigation/Xbox/T_Button_Xbox_RB.T_Button_Xbox_RB"
			local rbTexture = uevrUtils.find_required_object(XBOX_RB_TEXTURE)
			plugin.setProperty(iconsData, "Icons[Gamepad_FaceButton_Left]", rbTexture)
			--print("Set texture to RB")
		else
			local XBOX_X_TEXTURE = "Texture2D /Game/UI/Art/FrontEnd/General/Navigation/Xbox/T_Button_Xbox_X.T_Button_Xbox_X"
			local xTexture = uevrUtils.getLoadedAsset(XBOX_X_TEXTURE)
			plugin.setProperty(iconsData, "Icons[Gamepad_FaceButton_Left]", xTexture)
			--print("Set texture to X")
		end
	else
		local XBOX_ICONS_DATA = "IndianaUIControllerIconsData /Game/UI/XboxOneControllerIcons.XboxOneControllerIcons"
		local iconsData = uevrUtils.find_required_object(XBOX_ICONS_DATA)
		local XBOX_X_TEXTURE = "Texture2D /Game/UI/Art/FrontEnd/General/Navigation/Xbox/T_Button_Xbox_X.T_Button_Xbox_X"
		local xTexture = uevrUtils.getLoadedAsset(XBOX_X_TEXTURE)
		plugin.setProperty(iconsData, "Icons[Gamepad_FaceButton_Left]", xTexture)
		--wqwprint("Set texture to X override")
	end
end

ui.onUpdate("remapEnabled", function(value, priority)
	print("remapEnabled changed:", value, priority)
    remapXIcon(uevrUtils.ternary(value == nil, true, value))
end)

function on_level_change(level)
    cleanup()
	--print("Level changed\n")
	flickerFixer.create()
	setIdleCameraTimeout()
	regenerateHands(configui.getValue("hands_type"))
	remapXIcon(true)
end

--when leaving the inventory, destroy the current hands so if gloves changed the new ones are created
ui.registerWidgetChangeCallback("Ledger_BP_C", function(active)
	if not active then
		regenerateHands(configui.getValue("hands_type"))
        --hands.destroyHands()
	end
end)

--fix the pawn mesh fov (not really necessary because pawn is hidden but in case we decide to show arms during montages)
setInterval(1000, function()
	if pawn and pawn.FPVMesh ~= nil then
		--check pawn.bFixedFovForFPVEnabled
		uevrUtils.fixMeshFOV(pawn.FPVMesh, "ForegroundPriorityEnabled", 0.0, true, true, false)
	end
end)



attachments.registerAttachmentChangeCallback(function(id, hand, attachment)
	-- Reduces processing when no melee weapon is equipped
    local isRightMelee = attachments.isActiveAttachmentMelee(Handed.Right)
    local isLeftMelee = attachments.isActiveAttachmentMelee(Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isRightMelee, Handed.Right)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_RIGHT, isLeftMelee, Handed.Left)
	gestures.autoDetectGesture(gestures.Gesture.SWIPE_LEFT, isLeftMelee, Handed.Left)

	status["grenadeLauncherEquipped"] = false
	--input.setOverridePawnRotationMode(nil)
	local equippedWeapon = uevrUtils.getValid(pawn,{"Equipment","EquippedWeapon"})
	if equippedWeapon ~= nil then
		if equippedWeapon:is_a(uevrUtils.get_class("BlueprintGeneratedClass /Game/Blueprints/WEAP/HvyWpn/Launcher/Ham_GrenadeLauncher/Ham_GrenadeLauncher_Weapon_Base.Ham_GrenadeLauncher_Weapon_Base_C")) then
			status["grenadeLauncherEquipped"] = true
			--grenade launcher direction works differently from all other weapons. It takes its
			--aim direction from the direction the pawn is looking rather than from the FPVCamera.
			--To correct this we override pawn rotation mode to "Right Controller". This of course
			--means right controller controls pawn movement direction while the grenade launcher is equipped
			--but since its not a melee weapon, it seems like a good compromise.
			--input.setOverridePawnRotationMode( input.PawnRotationMode.RIGHT_CONTROLLER)

			-- this works well instead of the above
			local primaryMode = uevrUtils.getValid(pawn,{"Equipment","EquippedWeapon","PrimaryMode"})
			if primaryMode ~= nil then
				primaryMode.bUseTargeting = true
			end
		end
	end

	fixWeaponParticleSystemFOV()

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

-- local function isItemContainerOpen()
-- 	local hud = uevrUtils.getValid(uevr.api:get_player_controller(0), {"MyHUD"})
-- 	if hud ~= nil then
-- 		local itemContainer = hud:GetHUD().ItemContainerWidget
-- 		if itemContainer ~= nil and itemContainer.VerticalContainer ~= nil then
-- 			return itemContainer.VerticalContainer:GetRenderOpacity() > 0.01
-- 		end
-- 	end
-- 	return false
-- end

local function setLadderClimbBodyYawSuppressed(active)
	if input.setBodyYawWritesSuppressed == nil then
		return
	end
	if status.ladderClimbYawSuppressed == active then
		return
	end
	status.ladderClimbYawSuppressed = active
	input.setBodyYawWritesSuppressed(active)
end

-- Climb mount snaps pawn yaw to the ladder; LOCKED body yaw fighting that causes shudder.
hook_function("Class /Script/Indiana.EquipmentComponent", "OnStartClimb", true,
	nil,
	function(fn, obj, locals)
		setLadderClimbBodyYawSuppressed(true)
		status.ladderClimbSuppressToken = (status.ladderClimbSuppressToken or 0) + 1
		local token = status.ladderClimbSuppressToken
		-- AnimBP climb flag is often still false on this frame; wait before a safety clear
		-- in case OnStopClimb is missed.
		delay(500, function()
			if token ~= status.ladderClimbSuppressToken then
				return
			end
			if not status.ladderClimbYawSuppressed then
				return
			end
			local anim = uevrUtils.getValid(pawn, {"FPVMesh", "AnimScriptInstance"})
			if anim ~= nil and anim.MovementStateIsClimbing == false then
				setLadderClimbBodyYawSuppressed(false)
			end
		end)
	end,
	false
)
hook_function("Class /Script/Indiana.EquipmentComponent", "OnStopClimb", true,
	nil,
	function(fn, obj, locals)
		status.ladderClimbSuppressToken = (status.ladderClimbSuppressToken or 0) + 1
		setLadderClimbBodyYawSuppressed(false)
	end,
	false
)

local function clearGrenadeAim()
	input.setOverridePawnRotationMode(nil)
	if input.setForcedBodyYaw ~= nil then
		input.setForcedBodyYaw(nil)
	end
	status.frozenGrenadePitch = nil
end

local function getGrenade()
	local throwable = uevrUtils.getValid(pawn,{"Equipment","CurrentThrowable"})
	if throwable ~= nil then
		if status.grenageMesh == nil then
			status.grenageMesh = uevrUtils.createStaticMeshComponent("StaticMesh /Game/Art/WEAP/Thrown/P_FragGrenade/SM_W_P_Frag_Grenade_01.SM_W_P_Frag_Grenade_01")
		end
		status.isGrippingGrenade = true
		remapXIcon(false)
		status.grenadeAimClearToken = (status.grenadeAimClearToken or 0) + 1
		status.frozenGrenadePitch = nil
		if input.setForcedBodyYaw ~= nil then
			input.setForcedBodyYaw(nil)
		end
		--grenade direction works differently from all other weapons. It takes its
		--aim direction from the direction the pawn is looking rather than from the FPVCamera.
		--To correct this we override pawn rotation mode to "Right Controller". This of course
		--means right controller controls pawn movement direction while the grenade launcher is equipped
		--but since its not a melee weapon, it seems like a good compromise.
		input.setOverridePawnRotationMode( input.PawnRotationMode.RIGHT_CONTROLLER)
	end
end

-- keepAimForThrow: RB release starts a throw anim; BeginThrow notify fires later.
-- Keep RIGHT_CONTROLLER for mode/camera continuity; hold yaw at the release aim via
-- setForcedBodyYaw so the dropping hand doesn't retarget the throw.
local function ungripGrenade(keepAimForThrow)
	if not status.isGrippingGrenade then
		return
	end
	status.isGrippingGrenade = false
	remapXIcon(true)

	if keepAimForThrow then
		local root = uevrUtils.getValid(pawn, {"RootComponent"})
		local rootRot = root and root.K2_GetComponentRotation and root:K2_GetComponentRotation() or nil
		local throwable = uevrUtils.getValid(pawn, {"Equipment", "CurrentThrowable"})
		local pitch = throwable and throwable.AimPitchOffset or nil
		if pitch == nil then
			local controllerRotation = controllers.getControllerRotation(Handed.Right)
			pitch = controllerRotation and controllerRotation.Pitch or 7.0
		end
		status.frozenGrenadePitch = pitch
		if rootRot ~= nil and input.setForcedBodyYaw ~= nil then
			input.setForcedBodyYaw(rootRot.Yaw)
		end

		status.grenadeAimClearToken = (status.grenadeAimClearToken or 0) + 1
		local token = status.grenadeAimClearToken
		-- Long enough for AnimNotify_ThrowableStateMachineBeginThrow on quick/full throw.
		delay(750, function()
			if token ~= status.grenadeAimClearToken then
				return
			end
			clearGrenadeAim()
		end)
	else
		status.grenadeAimClearToken = (status.grenadeAimClearToken or 0) + 1
		clearGrenadeAim()
	end
end

local xInputStatus = {}
uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    if status["hasSwipe"] then
        print("Processing swipe gesture into input")
        state.Gamepad.bRightTrigger = 255
        status["hasSwipe"] = false
    end

	local interactionControlMode = configui.getValue("interaction_control_mode") or 1
	if interactionControlMode ~= 1 and (ui.isRemapDisabled()) ~= true then
		local gripMouth, gripEyes, gripHead, gripEar, triggerMouth, triggerEyes, triggerHead, triggerEar = gestures.getHeadGestures(state, Handed.Left, true)
		local gripChest = gestures.getBodyGestures(state, Handed.Right, true)

		if xInputStatus.isGrippingMouth ~= gripMouth then
			xInputStatus.isGrippingMouth = gripMouth
			if gripMouth then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_DPAD_DOWN)
			end
		end
		if gripMouth then
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		end

		local isPullingDownRightStick = state.Gamepad.sThumbRY < -22000
		if xInputStatus.isPullingDownRightStick ~= isPullingDownRightStick then
			xInputStatus.isPullingDownRightStick = isPullingDownRightStick
			if isPullingDownRightStick then
				uevrUtils.doDoubleTap(XINPUT_GAMEPAD_A, 25, 40)
			end
		end

		if xInputStatus.triggerEar ~= triggerEar then
			xInputStatus.triggerEar = triggerEar
			if triggerEar then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
			end
		end

		if xInputStatus.isGrippingEar ~= gripEar then
			xInputStatus.isGrippingEar = gripEar
			if gripEar then
				uevrUtils.pressButton(state, XINPUT_GAMEPAD_BACK)
			end
		end

		if interactionControlMode == 3 then
			if xInputStatus.isGrippingChest ~= gripChest then
				xInputStatus.isGrippingChest = gripChest
				if gripChest then
					getGrenade()
				end
			end

			local isGrippingRightShoulder = uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
			if not isGrippingRightShoulder then
				-- RB release while gripping = throw. Freeze aim for the throw anim notify.
				ungripGrenade(true)
				xInputStatus.suppressGripInteractionUntilRelease = false
			end

			if status.isGrippingGrenade then
				if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X) then
					ungripGrenade(false)
					-- X tells the game to put the grenade away. Keep the physical
					-- grip/RB state intact until it is released; otherwise the
					-- interaction remap below releases RB and throws the grenade.
					xInputStatus.suppressGripInteractionUntilRelease = true
				end
			elseif xInputStatus.suppressGripInteractionUntilRelease then
				-- Pass the real X and RB states through unchanged while the game
				-- processes the put-away action.
			elseif not triggerEar then
				if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER) then
					uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
				elseif isGrippingRightShoulder then -- and isItemContainerOpen() then
					uevrUtils.pressButton(state, XINPUT_GAMEPAD_X)
					uevrUtils.unpressButton(state, XINPUT_GAMEPAD_RIGHT_SHOULDER)
				else
					uevrUtils.unpressButton(state, XINPUT_GAMEPAD_X)
				end
			end
		else
			ungripGrenade(false)
			xInputStatus.suppressGripInteractionUntilRelease = false
			xInputStatus.isGrippingChest = false
		end

		--if opening inventory or full immersion mode and not triggering ear then disable left grip TTD
		if gripEar or (not triggerEar and interactionControlMode == 3) then
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
		end
	elseif ui.isRemapDisabled() then
		--if we got to the inventory by grabbing the ear, cool down so left grip doesnt cause inventory to tab
		if xInputStatus.isGrippingEar then
			uevrUtils.unpressButton(state, XINPUT_GAMEPAD_LEFT_SHOULDER)
			delay(500,function()
				xInputStatus.isGrippingEar = false
			end)
		end
	end
end, 5) --increased priority to get values before remap occurs

-- uevrUtils.registerUEVRCallback("scope_active_change", function(value)
-- 	remap.setDisabled(value)
-- end)

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
				regenerateHands(configui.getValue("hands_type"))
				--hands.destroyHands()
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

	if montageName == "AS_LngGn_FP_BoltAction_Shoot_Montage" or montageName == "AS_LngGn_FP_BoltAction_Reload_Montage" then
		--montage ended
		delay(150, function()
			status["hasBoltActionFired"] = true
		end)
	end
	if montageObject == nil then
		--montage ended
		status["hasBoltActionFired"] = false
	end
	-- if montageName == "AS_Hndgn_FP_H_Revolver_Reload_001_Montage" then
	-- 	--montage ended
	-- 	montage.setPlaybackRate(montageObject, label, 0.1)
	-- end
end)

ui.registerWidgetChangeCallback("MainMenu_C", function(active)
	if active then
		local widget = uevrUtils.find_first_instance("WidgetBlueprintGeneratedClass /Game/UI/Menus/MainMenu/MainMenu.MainMenu_C", false)
		-- LogoContainer is a UOverlay that already contains LogoImage (see tree dump above)
		if widget ~= nil and widget.LogoContainer ~= nil then
			local result = plugin.executeFunction(kismet_rendering_library, "ImportFileAsTexture2D", uevrUtils.get_world(), "$data/images/VROverlay.png")
			local texture = nil
			if result ~= nil then texture = result.ReturnValue end
			print("Texture", texture)
			if texture ~= nil then
				print("Texture imported successfully")
				local x = texture:Blueprint_GetSizeX()
				local y = texture:Blueprint_GetSizeY()
				print("Texture size: " .. tostring(x) .. " x " .. tostring(y))

				-- UImage is not a UUserWidget, so use spawn_object (not createWidget).
				-- Outer should be the WidgetTree so UMG owns the new child properly.
				local outer = widget.WidgetTree or widget
				local image = uevrUtils.spawn_object("Class /Script/UMG.Image", outer)
				if image ~= nil then
					image:SetBrushFromTexture(texture, true)
					local slot = widget.LogoContainer:AddChildToOverlay(image)
					if slot ~= nil then
						-- EHorizontalAlignment / EVerticalAlignment: 0=Fill, 1=Left/Top, 2=Center, 3=Right/Bottom
						slot:SetHorizontalAlignment(0)
						slot:SetVerticalAlignment(0)
					end
					print("Added new Image to LogoContainer")
				else
					print("Failed to spawn UImage")
				end
			end
		end
	end
end)

-- hook_function("Class /Script/Engine.AnimNotify", "Received_Notify", false,
--     function(fn, obj, locals, result)
-- 		print("AnimNotify fired:", obj and obj:get_class():get_full_name() or "nil")
-- 		-- if locals ~= nil then
-- 		-- 	for k,v in pairs(locals) do
-- 		-- 		print("  ", k, v and v:get_full_name() or "nil")
-- 		-- 	end
-- 		-- 	local montage = locals.Montage
-- 		-- 	if montage ~= nil then
-- 		-- 		print("Montage:", montage:get_full_name())
-- 		-- 	end
-- 		-- 	local pawn = locals.Pawn
-- 		-- 	if pawn ~= nil then
-- 		-- 		print("Pawn:", pawn:get_full_name())
-- 		-- 	end
-- 		-- 	local meshComp = locals.MeshComp
-- 		-- 	if meshComp ~= nil then
-- 		-- 		print("MeshComp:", meshComp:get_full_name())
-- 		-- 	end
-- 		-- 	local anim = locals.Animation
-- 		-- 	if anim ~= nil then
-- 		-- 		print("Animation:", anim:get_full_name())
-- 		-- 	end
-- 		-- end
--         -- if not shouldLogSocketRequests() then return end

--         -- local attachNotifyClass = uevrUtils.get_class("Class /Script/Indiana.AnimNotify_AttachWeapon")
--         -- if attachNotifyClass == nil or obj == nil or obj.is_a == nil or (not obj:is_a(attachNotifyClass)) then
--         --     return
--         -- end

--         -- local montageName = (montage.getMostRecentMontage and montage.getMostRecentMontage()) or ""
--         -- local animName = (locals.Animation and locals.Animation.get_full_name) and locals.Animation:get_full_name() or ""
--         -- local meshName = (locals.MeshComp and locals.MeshComp.get_full_name) and locals.MeshComp:get_full_name() or ""

--         -- local equip = uevrUtils.getValid(pawn, { "Equipment" })
--         -- local weaponAttachSocket = equip and equip.WeaponAttachSocket or nil

--         -- pendingSocketRequest = {
--         --     montageName = montageName,
--         --     animName = animName,
--         --     meshName = meshName,
--         --     weaponAttachSocket = fnameToString(weaponAttachSocket),
--         -- }

--         -- print("[SocketRequest] AnimNotify_AttachWeapon fired",
--         --     "montage=" .. montageName,
--         --     "weaponAttachSocket=" .. pendingSocketRequest.weaponAttachSocket,
--         --     "anim=" .. animName,
--         --     "mesh=" .. meshName
--         -- )
-- 		return false
--     end
-- 	, nil, true
-- )

configui.onCreateOrUpdate("idle_animation", function(value)
	setIdleCameraTimeout()
end)

configui.onCreateOrUpdate("interaction_control_mode", function(value)
	configui.setHidden("interaction_info_group", value == 1)
	configui.setHidden("interaction_info_full_immersion_group", value ~= 3)
	remapXIcon(value == 3)
end)

configui.create(configDefinition)

local isPaused = false

function on_pre_engine_tick(engine, delta)
	fixWeaponFXFOV()

	local fpvmesh = uevrUtils.getValid(pawn, {"FPVMesh"})
	if fpvmesh ~= nil then
		uevrUtils.fixMeshFOV(fpvmesh, "ForegroundPriorityEnabled", 0.0, true, true, false)
	end

	local throwable = uevrUtils.getValid(pawn,{"Equipment","CurrentThrowable"})
	if throwable ~= nil and throwable.AimPitchOffset ~= nil then
		if status.frozenGrenadePitch ~= nil then
			throwable.AimPitchOffset = status.frozenGrenadePitch
		else
			local controllerRotation = controllers.getControllerRotation(Handed.Right)
			if controllerRotation ~= nil then
				throwable.AimPitchOffset = controllerRotation.Pitch
			else
				throwable.AimPitchOffset = 7.0
			end
		end
	end

end

uevr.params.sdk.callbacks.on_script_reset(function()
	status["ikMeshComponent"] = nil
end)


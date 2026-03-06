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
local laser = require('libs/laser')
local particlesConfigDev = require('libs/config/particles_config_dev')
local widgetModule = require('libs/widget')
local ik = require('libs/ik')
local animation = require('libs/animation')

local flickerFixer = require('libs/flicker_fixer')
--local dev = require('libs/uevr_dev')
--dev.init()

uevrUtils.setLogLevel(LogLevel.Debug)
-- reticule.setLogLevel(LogLevel.Debug)
-- -- input.setLogLevel(LogLevel.Debug)
attachments.setLogLevel(LogLevel.Debug)
-- -- animation.setLogLevel(LogLevel.Debug)
-- ui.setLogLevel(LogLevel.Debug)
-- remap.setLogLevel(LogLevel.Debug)
-- --flickerFixer.setLogLevel(LogLevel.Debug)
-- --hands.setLogLevel(LogLevel.Debug)
widgetModule.setLogLevel(LogLevel.Debug)
ik.setLogLevel(LogLevel.Debug)

uevrUtils.setDeveloperMode(true)
--hands.enableConfigurationTool()
uevrUtils.profiler:toggle(true)


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
--This is needed to prevent jittery IK arms
--input.setOptimizeBodyYawCalculations(true)
--laser.setLaserLengthPercentage(0.0)

--since weapons are attached to the hand sockets for this game
--only let the hands be affected by gunstock offsets
attachments.setGunstockOffsetsEnabled(false)
hands.setGunstockOffsetsEnabled(true)
ik.setGunstockOffsetsEnabled(true)

local settings = {}
local meshCopy = nil

local texture = nil
register_key_bind("F1", function()
	texture = kismet_rendering_library:ImportFileAsTexture2D(uevrUtils.get_world(), "C:\\Users\\john\\source\\AO.png")
	print(texture)
	if texture ~= nil then
		print("Texture imported successfully")
		local x = texture:Blueprint_GetSizeX()
		local y = texture:Blueprint_GetSizeY()
		print("Texture size: " .. tostring(x) .. " x " .. tostring(y))

		--create widget Class /Script/UMG.Image
		--image:SetBrushFromTexture(class UTexture2D* Texture, bool bMatchSize);
	end
end)

--[[
[info] CanvasPanel_0
[info]   InvisibleButton
[info]   LogoContainer
[info]     LogoImage
[info]   PressKeyPromptOverlay
[info]     PressKeyPrompt
[info]     XboxTextblockContainer
[info]       LeftSidePrompt
[info]       Image_0
[info]       RightSidePrompt
[info]   GammaSelection
[info]   ContentOverlay
[info]     MainOptions
[info]     ExtraOptions
[info]     DeliverablesOptions
[info]     MenuDLCManager
[info]     UserNameTextBlock
[info]     VersionTextBlock
[info]   AutosaveSplashOverlay
[info]     VerticalBox_0
[info]       AutosaveSplashText
[info]       SavingSpinnerWidget
[info]   CreditsWidget
[info]   LegalWidget
[info]   SavingWidget_BP
]]--
-- register_key_bind("F2", function()
-- 	local userWidget = uevrUtils.getActiveWidgetByClass("WidgetBlueprintGeneratedClass /Game/UI/Menus/MainMenu/MainMenu.MainMenu_C")
-- 	if userWidget ~= nil then
-- 		print("Main menu widget found:")
-- 		--widgetModule.logWidgetDescendants(userWidget)
-- 		widgetModule.dumpWidgetEditableFields(userWidget)
-- 	else
-- 		print("No main menu widget found")
-- 	end
-- end)

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
				expandArray(reticule.getConfigurationWidgets,{{id="uevr_reticule_update_distance", initialValue=200}, {id="uevr_reticule_eye_dominance_offset", initialValue=2.0, isHidden=false}}),
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
				{
					widgetType = "checkbox",
					id = "idle_animation",
					label = "Idle Animation",
					initialValue = true
				},
                -- {
                --     widgetType = "drag_float3",
                --     id = "twist_rotation",
                --     label = "Rotation",
                --     speed = 1,
                --     range = {-180, 180},
                --     initialValue = {0, 0, 0},
                --     isHidden = false,
                -- },
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

local status = {}

local function setIdleCameraTimeout()
	local value = configui.getValue("idle_animation")
	local idleCamera = uevrUtils.getValid(pawn, {"IdleCamera"})
	if idleCamera ~= nil and idleCamera.SecondsToWait ~= nil then
		idleCamera.SecondsToWait = value and 60 or 60000
		print("Idle animation timeout set to:", idleCamera.SecondsToWait)
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

local function getWeaponMesh()
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

-- TODO:
-- weapons need to be able to quickly switch from attached to controller to attached to hand at socket so
-- that we can animate the right hand and have the weapon move with it during an animation but then switch back to
-- having the hand attached to the weapon when not in a montage so that gunstock works. 
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

    hands.destroyHands()
    ik.destroyAll()

	-- forearms will autocreate if value == 1 or create IK if value == 2
    status["ikMeshComponent"] = nil
    if value == HandsType.IKArms then
        ik.new({ animationsFile = "hands_parameters" })
    end
end

configui.onUpdate("hands_type", function(value)
    regenerateHands(value)
end)

ik.registerOnMeshCreatedCallback(function(meshComponent, ikInstance)
    --print("IK Mesh created:", meshComponent ~= nil, ikInstance ~= nil and ikInstance.rigId or "")
    if meshComponent ~= nil then
        meshComponent.bCastDynamicShadow = false
        meshComponent.bRenderInDepthPass = false
        animation.setComponent("left_arms", meshComponent)
		animation.setComponent("right_arms", meshComponent)
        status["ikMeshComponent"] = meshComponent
    end
end)

function on_level_change(level)
	meshCopy = nil
	--print("Level changed\n")
	flickerFixer.create()
	setIdleCameraTimeout()
	regenerateHands(configui.getValue("hands_type"))

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
			--input.setOverridePawnRotationMode( input.PawnRotationMode.RIGHT_CONTROLLER)
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
--[[
--heres an example of how to draw and put textures directly onto the hud. Seems to crash a lot though
--note turn on AHUD compatability in uevr params for this to work
local texture = nil
register_key_bind("F1", function()
	texture = kismet_rendering_library:ImportFileAsTexture2D(uevrUtils.get_world(), "C:\\Users\\john\\source\\AO.png")
	print(texture)
	if texture ~= nil then
		print("Texture imported successfully")
		local x = texture:Blueprint_GetSizeX()
		local y = texture:Blueprint_GetSizeY()
		print("Texture size: " .. tostring(x) .. " x " .. tostring(y))

		--uevr.params.vr:set_mod_value("VR_Compatibility_AHUD", "true")
		-- local billboardComponent = uevrUtils.create_component_of_class("Class /Script/Engine.BillboardComponent")
		-- if billboardComponent ~= nil then
		-- 	uevrUtils.set_component_relative_scale(billboardComponent, {X=0.1, Y=0.1, Z=0.1})
		-- 	billboardComponent:SetSprite(texture)
		-- 	billboardComponent:SetVisibility(true, true)
		-- 	controllers.attachComponentToController(Handed.Right, billboardComponent)
		-- end

		-- local playerController = uevr.api:get_player_controller(0)
		-- playerController.MyHUD:DrawTexture(texture, 0, 0, 1024, 786, 0.5, 0.5, x, y, uevrUtils.color_from_rgba(1,1,1,1, true), 0, 1, 0, 0, uevrUtils.vector2D(0,0))
		-- local hud = lplayer:GetHUD() 

		-- 	print(hud:get_full_name())
		-- 	print(hud:get_class():get_full_name())
				
		-- 	local hud_c = api:find_uobject("Class /Script/Engine.HUD")
		-- 	print(hud_c)

		-- 	local hud_fn = hud_c:find_function("ReceiveDrawHUD")

		-- 	print(hud_fn)

        --         hud_fn:set_function_flags(hud_fn:get_function_flags() | 0x400) -- Mark as native
        --         hud_fn:hook_ptr(function(fn, obj, locals, result)
                
        --             hud:DrawLine(10,10,200,200,new_color,5)
                    
        --             return false
        --         end)

	else
		print("Texture import failed")
	end
end)

hook_function("Class /Script/Engine.HUD", "ReceiveDrawHUD", true,
	function(fn, obj, locals, result)
		obj:DrawLine(10,10,200,200,uevrUtils.color_from_rgba(0,1,0,1, true),5)
		if uevrUtils.getValid(texture) ~= nil then
			obj:DrawTexture(texture, 0, 0, texture:Blueprint_GetSizeX(), texture:Blueprint_GetSizeY(), 0, 0, 1, 1, uevrUtils.color_from_rgba(1,1,1,1, true), 2, 1, false, 0, uevrUtils.vector2D(0.5,0.5))
		end
		return false
	end
, nil, true)

]]
configui.onCreateOrUpdate("idle_animation", function(value)
	setIdleCameraTimeout()
	-- local idleCamera = uevrUtils.getValid(pawn,{"IdleCamera"})
	-- if idleCamera ~= nil and idleCamera.SecondsToWait ~= nil then
	-- 	idleCamera.SecondsToWait = value and 60 or 60000
	-- 	print("Idle animation timeout set to:", idleCamera.SecondsToWait)
	-- end
end)

configui.create(configDefinition)

-- local EBoneSpaces =
-- {
-- 	WorldSpace                               = 0,
-- 	ComponentSpace                           = 1,
-- 	EBoneSpaces_MAX                          = 2,
-- };
-- local UKismetAnimationLibrary = nil

-- local SafeNormalize

-- local IK_MIN_SWING_DEG = 0.02
-- local IK_MIN_TWIST_DEG = 0.02

-- -- Optional: couple wrist roll into elbow pole so the elbow raises/lowers slightly as you pronate/supinate.
-- -- Keep conservative defaults to avoid pole flips.
-- local ELBOW_POLE_TWIST_INFLUENCE = -0.25 -- 0..1 (try 0.15-0.40)
-- local ELBOW_POLE_TWIST_MAX_DEG   = 75.0 -- clamp the measured twist before applying

-- -- Module-level constants (allocated once, never mutated).
-- local VEC_UNIT_Y     = nil  -- uevrUtils.vector(0,1,0) — initialised on first use after kismet is live
-- local HAND_CORRECTION = nil -- uevrUtils.rotator(0,0,180) — same

-- -- Minimal IK state: baseline elbow direction for a stable pole.
-- local ikState = {
-- 	baselineElbowDirCS = nil,
-- 	jointPoleAxisChoice = nil,
-- 	jointPoleAxisForBones = nil,
-- 	composeOrderSwing = nil,   -- cached: true = ComposeRotators(currentRot, delta), false = (delta, currentRot)
-- 	composeOrderTwist = nil,   -- cached: true = ComposeRotators(swingRot, twist),   false = (twist, swingRot)
-- 	twistBoneVecs = nil,       -- per-bone: { x, z } axes stored in lower-arm local space at F2 capture time
-- 	lastCtrlPoleCS = nil,      -- for stable pole twist coupling
-- 	poleTwistSmoothedDeg = 0.0,
-- 	-- Cached per-mesh constants (invalidated when mesh is recreated at F2).
-- 	-- NOTE: compToWorld and meshRightVec are NOT cached — they change every tick as the pawn rotates.
-- 	upperLen = nil,            -- upper arm bone length         — skeleton constant
-- 	lowerLen = nil,            -- lower arm bone length         — skeleton constant
-- 	bonesKey = nil,            -- JointBone.."->"..EndBone     — never changes per call site
-- }

-- local function mulVec(v, s)
-- 	return kismet_math_library:Multiply_VectorFloat(v, s)
-- end

-- local function getBoneDirCS(mesh, fromBone, toBone)
-- 	if mesh == nil then return nil end
-- 	local a = mesh:GetBoneLocationByName(fromBone, EBoneSpaces.ComponentSpace)
-- 	local b = mesh:GetBoneLocationByName(toBone, EBoneSpaces.ComponentSpace)
-- 	if a == nil or b == nil then return nil end
-- 	return SafeNormalize(kismet_math_library:Subtract_VectorVector(b, a))
-- end

-- local function axisVectorsFromRot(rot)
-- 	if rot == nil then return nil, nil, nil end
-- 	return SafeNormalize(kismet_math_library:GetForwardVector(rot)),
-- 		SafeNormalize(kismet_math_library:GetRightVector(rot)),
-- 		SafeNormalize(kismet_math_library:GetUpVector(rot))
-- end

-- local function chooseBestAxis(axisX, axisY, axisZ, dir)
-- 	if dir == nil then return { axis = "X", sign = 1, score = 0 } end
-- 	local function scoreAxis(a)
-- 		if a == nil then return 0 end
-- 		local d = kismet_math_library:Dot_VectorVector(a, dir) or 0
-- 		return d
-- 	end
-- 	local dx = scoreAxis(axisX)
-- 	local dy = scoreAxis(axisY)
-- 	local dz = scoreAxis(axisZ)
-- 	local adx, ady, adz = math.abs(dx), math.abs(dy), math.abs(dz)
-- 	if adx >= ady and adx >= adz then
-- 		return { axis = "X", sign = (dx >= 0) and 1 or -1, score = dx }
-- 	elseif ady >= adx and ady >= adz then
-- 		return { axis = "Y", sign = (dy >= 0) and 1 or -1, score = dy }
-- 	else
-- 		return { axis = "Z", sign = (dz >= 0) and 1 or -1, score = dz }
-- 	end
-- end

-- local function chooseBestPoleAxis(axisX, axisY, axisZ, longAxisChar, poleDir)
-- 	local best = { axis = "Y", sign = 1, score = 0 }
-- 	local function tryAxis(char, vec)
-- 		if char == longAxisChar or vec == nil then return end
-- 		local d = kismet_math_library:Dot_VectorVector(vec, poleDir) or 0
-- 		local ad = math.abs(d)
-- 		if ad > best.score then
-- 			best = { axis = char, sign = (d >= 0) and 1 or -1, score = ad }
-- 		end
-- 	end
-- 	tryAxis("X", axisX)
-- 	tryAxis("Y", axisY)
-- 	tryAxis("Z", axisZ)
-- 	return best
-- end

-- local function axisVectorFromRotator(rot, axisChar)
-- 	if rot == nil then return nil end
-- 	if axisChar == "X" then
-- 		return kismet_math_library:GetForwardVector(rot)
-- 	elseif axisChar == "Y" then
-- 		return kismet_math_library:GetRightVector(rot)
-- 	else
-- 		return kismet_math_library:GetUpVector(rot)
-- 	end
-- end

-- local function signedAngleDegAroundAxis(a, b, axis)
-- 	-- Signed angle from a->b around axis.
-- 	local cross = kismet_math_library:Cross_VectorVector(a, b)
-- 	local y = kismet_math_library:Dot_VectorVector(axis, cross) or 0.0
-- 	local x = kismet_math_library:Dot_VectorVector(a, b) or 1.0
-- 	return kismet_math_library:RadiansToDegrees(math.atan(y, x))
-- end

-- local function alignBoneAxisToDirCS(mesh, boneName, childBoneName, desiredDirCS, axisChoice, poleCS)
-- 	local currentRot = mesh:GetBoneRotationByName(boneName, EBoneSpaces.ComponentSpace)
-- 	if currentRot == nil then return nil end

-- 	-- 1) Determine current direction to align.
-- 	-- In this project we always call with childBoneName; keep a small fallback for completeness.
-- 	local currentDir = (childBoneName ~= nil) and getBoneDirCS(mesh, boneName, childBoneName) or nil
-- 	if currentDir == nil and axisChoice ~= nil then
-- 		local axisVec = axisVectorFromRotator(currentRot, axisChoice.axis or "X")
-- 		currentDir = axisVec and SafeNormalize(mulVec(axisVec, axisChoice.sign or 1)) or nil
-- 	end
-- 	if currentDir == nil or kismet_math_library:VSize(currentDir) < 0.0001 then
-- 		return currentRot
-- 	end
-- 	local desiredDir = SafeNormalize(desiredDirCS)
-- 	if desiredDir == nil or kismet_math_library:VSize(desiredDir) < 0.0001 then
-- 		return currentRot
-- 	end

-- 	-- 2) Swing: rotate currentDir -> desiredDir.
-- 	local dot = kismet_math_library:Dot_VectorVector(currentDir, desiredDir) or 1.0
-- 	dot = kismet_math_library:FClamp(dot, -1.0, 1.0)
-- 	local swingAngleDeg = kismet_math_library:RadiansToDegrees(kismet_math_library:Acos(dot))
-- 	if swingAngleDeg ~= nil and swingAngleDeg < IK_MIN_SWING_DEG then return currentRot end

-- 	local swingAxis = kismet_math_library:Cross_VectorVector(currentDir, desiredDir)
-- 	if kismet_math_library:VSize(swingAxis) < 0.0001 then
-- 		-- 180° case: pick a stable fallback axis using the pole.
-- 		local pole = SafeNormalize(poleCS)
-- 		if pole == nil or kismet_math_library:VSize(pole) < 0.0001 then pole = VEC_UNIT_Y end
-- 		swingAxis = kismet_math_library:Cross_VectorVector(currentDir, pole)
-- 	end
-- 	swingAxis = SafeNormalize(swingAxis)
-- 	if swingAxis == nil or kismet_math_library:VSize(swingAxis) < 0.0001 then return currentRot end

-- 	local deltaSwing = kismet_math_library:RotatorFromAxisAndAngle(swingAxis, swingAngleDeg)
-- 	local cand1 = kismet_math_library:ComposeRotators(deltaSwing, currentRot)
-- 	local cand2 = kismet_math_library:ComposeRotators(currentRot, deltaSwing)

-- 	local swingRot
-- 	if ikState.composeOrderSwing == nil then
-- 		-- Detect once: which composition order actually rotates the bone direction toward desiredDir?
-- 		local localDir = SafeNormalize(kismet_math_library:LessLess_VectorRotator(currentDir, currentRot))
-- 		local function score(rot)
-- 			if rot == nil then return -1 end
-- 			local a = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(localDir, rot))
-- 			return kismet_math_library:Dot_VectorVector(a, desiredDir) or -1
-- 		end
-- 		ikState.composeOrderSwing = score(cand2) > score(cand1)
-- 	end
-- 	swingRot = ikState.composeOrderSwing and cand2 or cand1

-- 	-- 3) Optional twist: align a pole axis in the plane orthogonal to desiredDir.
-- 	local poleAxisChoice = axisChoice and axisChoice.pole or nil
-- 	if poleAxisChoice == nil then
-- 		return swingRot
-- 	end
-- 	local poleAxisChar = poleAxisChoice.axis
-- 	local poleAxisSign = poleAxisChoice.sign or 1

-- 	local desiredPole = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(poleCS, desiredDir))
-- 	if desiredPole == nil or kismet_math_library:VSize(desiredPole) < 0.0001 then return swingRot end

-- 	local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
-- 	if poleAxisVec == nil then return swingRot end
-- 	local currentPole = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir))
-- 	if currentPole == nil or kismet_math_library:VSize(currentPole) < 0.0001 then return swingRot end

-- 	local twistAngleDeg = signedAngleDegAroundAxis(currentPole, desiredPole, desiredDir)
-- 	if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then return swingRot end

-- 	local deltaTwist = kismet_math_library:RotatorFromAxisAndAngle(desiredDir, twistAngleDeg)
-- 	local t1 = kismet_math_library:ComposeRotators(deltaTwist, swingRot)
-- 	local t2 = kismet_math_library:ComposeRotators(swingRot, deltaTwist)
-- 	if ikState.composeOrderTwist == nil then
-- 		local function scorePole(rot)
-- 			local p = axisVectorFromRotator(rot, poleAxisChar)
-- 			if p == nil then return -1 end
-- 			p = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(mulVec(p, poleAxisSign), desiredDir))
-- 			return kismet_math_library:Dot_VectorVector(p, desiredPole) or -1
-- 		end
-- 		ikState.composeOrderTwist = scorePole(t2) > scorePole(t1)
-- 	end
-- 	return ikState.composeOrderTwist and t2 or t1
-- end

-- SafeNormalize = function(v)
-- 	if v == nil then return uevrUtils.vector(0,0,0) end
-- 	-- UKismetMathLibrary has VSize/Divide_VectorFloat (see Engine_classes.hpp)
-- 	local len = kismet_math_library:VSize(v)
-- 	if len == nil or len < 0.0001 then
-- 		return uevrUtils.vector(0,0,0)
-- 	end
-- 	return kismet_math_library:Divide_VectorFloat(v, len)
-- end

--==============================================================
-- SolveVRArmIK
-- Full VR arm IK pipeline using K2_TwoBoneIK
--==============================================================

-- function SolveVRArmIK(
--     mesh,               -- UPoseableMeshComponent
--     RootBone,           -- e.g. "UpperArm_L"
--     JointBone,          -- e.g. "LowerArm_L"
--     EndBone,            -- e.g. "Hand_L"
--     wristBone,            -- e.g. "Hand_L"
-- 	ControllerWS,       -- VR controller world location (FVector)
-- 	ControllerRotWS,    -- VR controller world rotation (FRotator) (optional)
-- 	HandOffset,         -- FVector offset from controller → hand bone (in controller local space)
--     AllowStretch,       -- bool
--     StartStretchRatio,  -- float
--     MaxStretchScale,     -- float
-- 	twistBones
-- )

-- 	if UKismetAnimationLibrary == nil then
-- 		UKismetAnimationLibrary = uevrUtils.find_default_instance("Class /Script/AnimGraphRuntime.KismetAnimationLibrary")
-- 	end
-- 	if UKismetAnimationLibrary == nil then
-- 		print("SolveVRArmIK: Unable to find KismetAnimationLibrary")
-- 		return
-- 	end
-- 	-- Allocate-once constants: kismet_math_library is guaranteed live by this point.
-- 	if VEC_UNIT_Y     == nil then VEC_UNIT_Y     = uevrUtils.vector(0, 1, 0) end
-- 	if HAND_CORRECTION == nil then HAND_CORRECTION = uevrUtils.rotator(0, 0, 180) end

-- 	--print(ControllerRotWS.Pitch, ControllerRotWS.Yaw, ControllerRotWS.Roll)

--     --------------------------------------------------------------
--     -- 1. Compute Effector (hand target)
--     --------------------------------------------------------------
--     -- Effector = where the HAND BONE should go
--     -- ControllerWS is where the real hand is
--     -- HandOffset rotates/translates controller → hand bone pose
--     --------------------------------------------------------------
-- 	-- If you want no offsets: pass HandOffset=nil and EffectorWS will be the controller location.
-- 	-- HandOffset is controller-local, so we must rotate it by the controller's world rotation.
-- 	if ControllerWS == nil then
-- 		return
-- 	end
-- 	local EffectorWS = ControllerWS
-- 	if HandOffset ~= nil then
-- 		local offsetWS = HandOffset
-- 		if ControllerRotWS ~= nil then
-- 			offsetWS = kismet_math_library:GreaterGreater_VectorRotator(HandOffset, ControllerRotWS)
-- 		end
-- 		EffectorWS = kismet_math_library:Add_VectorVector(ControllerWS, offsetWS)
-- 	end


--     --------------------------------------------------------------
--     -- 2. Component transform + shoulder position (fail-fast)
--     --------------------------------------------------------------
-- 	-- compToWorld MUST be fetched every tick: the mesh is parented to pawn.RootComponent,
-- 	-- so any body rotation changes this transform. Caching it causes the hand to drift
-- 	-- away from the controller whenever the pawn rotates.
-- 	if mesh.K2_GetComponentToWorld == nil then
-- 		print("SolveVRArmIK: Mesh has no K2_GetComponentToWorld")
-- 		return
-- 	end
-- 	local compToWorld = mesh:K2_GetComponentToWorld()
-- 	if compToWorld == nil then return end

-- 	local ShoulderWS = mesh:GetBoneLocationByName(RootBone, EBoneSpaces.WorldSpace)
-- 	if ShoulderWS == nil then return end

--     --------------------------------------------------------------
--     -- 3. Auto-generate JointTarget (elbow direction)
--     --------------------------------------------------------------
--     -- Forward direction from shoulder → hand target
-- 	local Forward = SafeNormalize(kismet_math_library:Subtract_VectorVector(EffectorWS, ShoulderWS))

-- 	-- Elbow pole vector:
-- 	-- Use the baseline elbow direction projected onto the reach plane.
-- 	-- This keeps the elbow bending in a consistent, "natural" direction instead of flipping.
-- 	if ikState ~= nil and ikState.baselineElbowDirCS == nil then
-- 		local sCS0 = mesh:GetBoneLocationByName(RootBone, EBoneSpaces.ComponentSpace)
-- 		local jCS0 = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.ComponentSpace)
-- 		if sCS0 ~= nil and jCS0 ~= nil then
-- 			ikState.baselineElbowDirCS = SafeNormalize(kismet_math_library:Subtract_VectorVector(jCS0, sCS0))
-- 		end
-- 	end
-- 	-- GetRightVector changes with pawn rotation — fetch fresh every tick.
-- 	local OutwardWS = mesh:GetRightVector()
-- 	if ikState ~= nil and ikState.baselineElbowDirCS ~= nil then
-- 		local reachCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, Forward))
-- 		local poleCS = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(ikState.baselineElbowDirCS, reachCS))
-- 		if kismet_math_library:VSize(poleCS) < 0.0001 then
-- 			poleCS = VEC_UNIT_Y
-- 		end

-- 	--This lets the elbox move slightly when wrist rotates far either way. At little jerky but working okish

-- 		-- -- Optional: rotate pole around reach axis based on controller's orientation in the reach plane.
-- 		-- -- NOTE: keep this stable: do NOT switch between controller axes per-frame (that flickers).
-- 		-- -- If direction is wrong, flip the sign of ELBOW_POLE_TWIST_INFLUENCE.
-- 		-- if ControllerRotWS ~= nil and ELBOW_POLE_TWIST_INFLUENCE ~= nil and (ELBOW_POLE_TWIST_INFLUENCE > 0.0001 or ELBOW_POLE_TWIST_INFLUENCE < -0.0001) then
-- 		-- 	local ctrlCompRot = kismet_math_library:InverseTransformRotation(compToWorld, ControllerRotWS)
-- 		-- 	if ctrlCompRot ~= nil then
-- 		-- 		local ctrlUpCS = SafeNormalize(kismet_math_library:GetUpVector(ctrlCompRot))
-- 		-- 		local upProj = (ctrlUpCS ~= nil) and SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(ctrlUpCS, reachCS)) or nil
-- 		-- 		local upProjLen = (upProj ~= nil) and (kismet_math_library:VSize(upProj) or 0.0) or 0.0
-- 		-- 		-- If the controller up axis is close to the reach axis, projection becomes unstable.
-- 		-- 		-- In that case, hold the last valid projection instead of flipping sign/axis.
-- 		-- 		if upProjLen > 0.25 then
-- 		-- 			ikState.lastCtrlPoleCS = upProj
-- 		-- 		end
-- 		-- 		local ctrlPoleCS = ikState.lastCtrlPoleCS
-- 		-- 		if ctrlPoleCS ~= nil and kismet_math_library:VSize(ctrlPoleCS) > 0.0001 then
-- 		-- 			local rawTwistDeg = signedAngleDegAroundAxis(poleCS, ctrlPoleCS, reachCS)
-- 		-- 			if rawTwistDeg ~= nil then
-- 		-- 				rawTwistDeg = kismet_math_library:FClamp(rawTwistDeg, -ELBOW_POLE_TWIST_MAX_DEG, ELBOW_POLE_TWIST_MAX_DEG)
-- 		-- 				local targetApplied = rawTwistDeg * ELBOW_POLE_TWIST_INFLUENCE
-- 		-- 				-- Light smoothing to prevent per-frame bounce.
-- 		-- 				ikState.poleTwistSmoothedDeg = (ikState.poleTwistSmoothedDeg or 0.0) + (targetApplied - (ikState.poleTwistSmoothedDeg or 0.0)) * 0.20
-- 		-- 				local appliedDeg = ikState.poleTwistSmoothedDeg or 0.0
-- 		-- 				if math.abs(appliedDeg) > 0.01 then
-- 		-- 					local deltaPoleRot = kismet_math_library:RotatorFromAxisAndAngle(reachCS, appliedDeg)
-- 		-- 					poleCS = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(poleCS, deltaPoleRot))
-- 		-- 				end
-- 		-- 			end
-- 		-- 		end
-- 		-- 	end
-- 		-- end

-- 		OutwardWS = SafeNormalize(kismet_math_library:TransformDirection(compToWorld, poleCS))
-- 	end

-- 	-- Bone lengths are skeleton constants — measure once, then reuse.
-- 	local JointWS = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.WorldSpace)
-- 	local EndWS   = mesh:GetBoneLocationByName(EndBone,   EBoneSpaces.WorldSpace)
-- 	if ikState.upperLen == nil and JointWS ~= nil then
-- 		ikState.upperLen = kismet_math_library:VSize(kismet_math_library:Subtract_VectorVector(JointWS, ShoulderWS))
-- 	end
-- 	if ikState.lowerLen == nil and JointWS ~= nil and EndWS ~= nil then
-- 		ikState.lowerLen = kismet_math_library:VSize(kismet_math_library:Subtract_VectorVector(EndWS, JointWS))
-- 	end
-- 	local upperLen = ikState.upperLen or 30.0
-- 	local lowerLen = ikState.lowerLen or 30.0
-- 	local forwardDist = (upperLen + lowerLen) * 0.5
-- 	local outwardDist = upperLen * 0.35

-- 	-- Final elbow direction point
-- 	local JointTargetWS = kismet_math_library:Add_VectorVector(
-- 		ShoulderWS,
-- 		kismet_math_library:Add_VectorVector(
-- 			kismet_math_library:Multiply_VectorFloat(Forward, forwardDist),
-- 			kismet_math_library:Multiply_VectorFloat(OutwardWS, outwardDist)
-- 		)
-- 	)


--     --------------------------------------------------------------
--     -- 5. Run IK solver
--     --------------------------------------------------------------
--     local OutJointWS = uevrUtils.vector()
--     local OutEndWS   = uevrUtils.vector()

--     UKismetAnimationLibrary:K2_TwoBoneIK(
--         ShoulderWS, JointWS, EndWS,
--         JointTargetWS, EffectorWS,
--         OutJointWS, OutEndWS,
--         AllowStretch, StartStretchRatio, MaxStretchScale
--     )


--     --------------------------------------------------------------
--     -- 6. Reconstruct rotations from solved positions
--     --------------------------------------------------------------
-- 	local UpperDirWS = SafeNormalize(kismet_math_library:Subtract_VectorVector(OutJointWS, ShoulderWS))
-- 	local LowerDirWS = SafeNormalize(kismet_math_library:Subtract_VectorVector(OutEndWS, OutJointWS))

-- 	--------------------------------------------------------------
-- 	-- 7. Build target rotations in ComponentSpace
-- 	--------------------------------------------------------------
-- 	-- Many skeletons do NOT use +X as the "bone points-to-child" axis.
-- 	-- We calibrate which axis (X/Y/Z with sign) to align, then construct a component-space rot.
-- 	local upperDirCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, UpperDirWS))
-- 	local lowerDirCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, LowerDirWS))
-- 	local poleCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, OutwardWS))

-- 	-- Cache the elbow pole axis selection once.
-- 	-- Re-detecting every tick can flip between axes as the joint rotates, which looks like a 180° palm twist.
-- 	if ikState.bonesKey == nil then ikState.bonesKey = JointBone .. "->" .. EndBone end
-- 	local bonesKey = ikState.bonesKey
-- 	if ikState.jointPoleAxisChoice == nil or ikState.jointPoleAxisForBones ~= bonesKey then
-- 		local jointDir = getBoneDirCS(mesh, JointBone, EndBone)
-- 		local jx, jy, jz = axisVectorsFromRot(mesh:GetBoneRotationByName(JointBone, EBoneSpaces.ComponentSpace))
-- 		local jointLong = chooseBestAxis(jx, jy, jz, jointDir)
-- 		ikState.jointPoleAxisChoice = chooseBestPoleAxis(jx, jy, jz, jointLong.axis, VEC_UNIT_Y)
-- 		ikState.jointPoleAxisForBones = bonesKey
-- 	end
-- 	local axisJoint = { pole = ikState.jointPoleAxisChoice }

-- 	--------------------------------------------------------------
-- 	-- 8. Apply component-space rotations
-- 	--------------------------------------------------------------
-- 	-- Shoulder: swing-only. Twist here tends to look terrible; push twist down-chain.
-- 	local ShoulderCompRot = alignBoneAxisToDirCS(mesh, RootBone, JointBone, upperDirCS, nil, poleCS)
-- 	if ShoulderCompRot ~= nil then
-- 		mesh:SetBoneRotationByName(RootBone, ShoulderCompRot, EBoneSpaces.ComponentSpace)
-- 	end

-- 	-- IMPORTANT: compute elbow AFTER applying shoulder.
-- 	-- The joint's ComponentSpace basis changes when the parent rotates; using the pre-shoulder joint basis
-- 	-- can leave the end bone significantly off even if the solver's OutEndWS hits the effector.
-- 	local ElbowCompRot = alignBoneAxisToDirCS(mesh, JointBone, EndBone, lowerDirCS, axisJoint, poleCS)
-- 	if ElbowCompRot ~= nil then
-- 		mesh:SetBoneRotationByName(JointBone, ElbowCompRot, EBoneSpaces.ComponentSpace)
-- 	end

-- 	--------------------------------------------------------------
-- 	-- 9. Apply controller rotation to hand/wrist bone
-- 	--------------------------------------------------------------
-- 	-- Convert the controller's world-space rotation into mesh component space,
-- 	-- then stamp it directly onto the end bone so the wrist tracks the controller.
-- 	if ControllerRotWS ~= nil then
-- 		local HandCompRot = kismet_math_library:InverseTransformRotation(compToWorld, ControllerRotWS)
-- 		if HandCompRot ~= nil then
-- 			--print("HandCompRot before correction:", HandCompRot.Pitch, HandCompRot.Yaw, HandCompRot.Roll)
-- 			-- HAND_CORRECTION = rotator(0,0,180): module-level constant, allocated once.
-- 			-- Adjust if the wrist still looks wrong (try Roll=0/180, Pitch=0/180, Yaw=0/180).
-- 			local finalHandCompRot = kismet_math_library:ComposeRotators(HAND_CORRECTION, HandCompRot)
-- 			mesh:SetBoneRotationByName(EndBone, finalHandCompRot, EBoneSpaces.ComponentSpace)
-- 			mesh:SetBoneRotationByName(wristBone, finalHandCompRot, EBoneSpaces.ComponentSpace)


-- 			--print("HandCompRot after correction:", HandCompRot.Pitch, HandCompRot.Yaw, HandCompRot.Roll)
-- 			-- ElbowCompRot was just stamped onto JointBone — reuse it directly, no read-back needed.
-- 			local lowerArmRotCS = ElbowCompRot

-- 			-- Signed angle between elbow and hand around the forearm tube axis.
-- 			--[[
-- 				Why this is needed: The hand rolls but that roll cant be appled directly to the forearm because of Pitch/Yaw in the hand with respect to forearm which changes what roll means.
-- 				If elbowUp == handUp (both pointing the same way, only differing by Roll) → Roll is the tube angle. Valid.
-- 				The moment their forwards diverge (wrist pitched/yawed relative to elbow) → the Euler decomposition picks a different Pitch/Yaw/Roll split to represent the same physical rotation, and Roll absorbs some of the swing. It's no longer the tube angle.
-- 				The atan(dot(axis, cross), dot(up,up)) is essentially computing the same thing as Roll would be in the locked case — but geometrically, so it remains correct regardless of what Pitch and Yaw are doing. The up-vector approach is just "what Roll means, without the assumption that Pitch and Yaw are zero."
-- 			]]--
-- 			local twistAngleDeg = math:computeSignedAngleAroundAxis_Rotators(lowerArmRotCS, finalHandCompRot, lowerDirCS)
-- 			---------------------------------------------

-- 			for _, entry in ipairs(twistBones) do
-- 				if not entry._fname then entry._fname = uevrUtils.fname_from_string(entry.bone) end
-- 				local boneFName = entry._fname
-- 				local vecs = ikState.twistBoneVecs and ikState.twistBoneVecs[entry.bone]
-- 				if vecs == nil or lowerArmRotCS == nil then break end

-- 				-- Step 1: bring stored bone-local axes into current component space.
-- 				-- GreaterGreater_VectorRotator(v_local, rot) = pure matrix multiply, no Euler decomposition.
-- 				local xCS = kismet_math_library:GreaterGreater_VectorRotator(vecs.x, lowerArmRotCS)
-- 				local zCS = kismet_math_library:GreaterGreater_VectorRotator(vecs.z, lowerArmRotCS)

-- 				-- Step 2: rotate both axes around the forearm tube axis by the fractional angle.
-- 				local tubeRot = kismet_math_library:RotatorFromAxisAndAngle(lowerDirCS, twistAngleDeg * entry.fraction)
-- 				xCS = kismet_math_library:GreaterGreater_VectorRotator(xCS, tubeRot)
-- 				zCS = kismet_math_library:GreaterGreater_VectorRotator(zCS, tubeRot)

-- 				-- Step 3: reconstruct CS rotation from two vectors — no Euler composition at all.
-- 				local finalCS = kismet_math_library:MakeRotFromXZ(xCS, zCS)
-- 				mesh:SetBoneRotationByName(boneFName, finalCS, EBoneSpaces.ComponentSpace)
-- 			end
-- 		end

-- 	end
-- end


-- local function getArmsCopy()
-- 	if meshCopy == nil then
-- 		local fpvMesh = uevrUtils.getValid(pawn, {"FPVMesh"})
-- 		if fpvMesh ~= nil then
-- 			meshCopy = uevrUtils.createPoseableMeshFromSkeletalMesh(fpvMesh, {useDefaultPose = true, showDebug=false})
-- 			if meshCopy ~= nil then
-- 				uevrUtils.fixMeshFOV(meshCopy, "ForegroundPriorityEnabled", 0.0, true, true, false)
-- 				meshCopy:K2_AttachTo(pawn.RootComponent, uevrUtils.fname_from_string(""), 0, false)
-- 				meshCopy:SetVisibility(true, true)
-- 				meshCopy:SetHiddenInGame(false, true)
-- 				meshCopy.BoundsScale = 16.0

-- 				animation.setComponent("left_arms", meshCopy)
-- 				animation.setComponent("right_arms", meshCopy)

-- 			end
-- 		end
-- 	end
-- 	return meshCopy
-- end

-- function getCustomIKComponent(key)
-- 	return getArmsCopy()
-- end

-- function getCustomHandComponent(key)
-- 	return getArmsCopy()
-- end

-- local ikParameters = {
-- 	mesh = "Custom",
-- 	animation_mesh = "",
-- 	animation_location_offset = uevrUtils.vector(0,0,0),
--     animation_rotation_offset = uevrUtils.rotator(0,0,0),
-- 	solvers = {
-- 		a323432_ab_434543 = {
-- 			label = "Arms Only Right",
-- 			solver_type = ik.SolverType.TWO_BONE,
-- 			end_bone = "r_Hand_JNT",
-- 			end_control_type = ik.ControllerType.RIGHT_CONTROLLER,
-- 			end_bone_offset = uevrUtils.vector(-8,0,0),
-- 			end_bone_rotation = uevrUtils.rotator(0,0,180),
-- 			allow_wrist_affects_elbow = false,
-- 			allow_stretch = false,
-- 			start_stretch_ratio = 0.0,
-- 			max_stretch_scale = 0.0,
-- 			wrist_bone = "r_wrist_JNT",
-- 			twist_bones = {
-- 				{ bone = "r_lowerTwistUp_JNT",  fraction = 0.25 },
-- 				{ bone = "r_lowerTwistMid_JNT", fraction = 0.50 },
-- 				{ bone = "r_lowerTwistLow_JNT", fraction = 0.75 },
-- 			},
-- 			sort_order = 1,
-- 		},
-- 		b567788_ab_434543 = {
-- 			label = "Arms Only Left",
-- 			--mesh = "Pawn.FPVMesh",
-- 			solver_type = ik.SolverType.TWO_BONE,
-- 			end_bone = "l_Hand_JNT",
-- 			end_control_type = ik.ControllerType.LEFT_CONTROLLER,
-- 			end_bone_offset = uevrUtils.vector(-8,0,0),
-- 			allow_wrist_affects_elbow = false,
-- 			allow_stretch = false,
-- 			start_stretch_ratio = 0.0,
-- 			max_stretch_scale = 0.0,
-- 			invert_forearm_roll = true,
-- 			wrist_bone = "l_wrist_JNT",
-- 			twist_bones = {
-- 				{ bone = "l_lowerTwistUp_JNT",  fraction = 0.25 },
-- 				{ bone = "l_lowerTwistMid_JNT", fraction = 0.50 },
-- 				{ bone = "l_lowerTwistLow_JNT", fraction = 0.75 },
-- 			},
-- 			sort_order = 2,
-- 		}
-- 	}
-- }
-- local ikInstance = nil
-- register_key_bind("F2", function()
-- 	--hands.hideHands(true)

-- 	ikInstance = ik.new({
-- 	})
-- 	--ikInstance:setParameters(ikParameters, true)
-- 	ikInstance:setActive("a323432_ab_434543")
-- 	ikInstance:setActive("b567788_ab_434543")

-- 	-- local fpvMesh = uevrUtils.getValid(pawn, {"FPVMesh"})
-- 	-- if fpvMesh ~= nil then
-- 	-- 	meshCopy = uevrUtils.createPoseableMeshFromSkeletalMesh(fpvMesh, {useDefaultPose = true, showDebug=false})
-- 	-- 	if meshCopy ~= nil then
-- 	-- 		uevrUtils.fixMeshFOV(meshCopy, "ForegroundPriorityEnabled", 0.0, true, true, false)
-- 	-- 		meshCopy:K2_AttachTo(pawn.RootComponent, uevrUtils.fname_from_string(""), 0, false)
-- 	-- 		meshCopy.RelativeLocation.Z = -100
-- 	-- 		meshCopy:SetVisibility(true, true)
-- 	-- 		meshCopy:SetHiddenInGame(false, true)


-- 	-- 		-- Capture twist bone axes in lower-arm local space while mesh is in default pose.
-- 	-- 		-- Must happen here, before IK runs, to get the true rest-pose orientation.
-- 	-- 		-- LessLess_VectorRotator(v, rot) = express v in rot's local frame (bone space).
-- 	-- 		-- Reset all cached per-mesh state so it is re-derived from the new mesh.
-- 	-- 		-- ikState.upperLen          = nil
-- 	-- 		-- ikState.lowerLen          = nil
-- 	-- 		-- ikState.bonesKey          = nil
-- 	-- 		-- ikState.baselineElbowDirCS = nil
-- 	-- 		-- ikState.jointPoleAxisChoice = nil
-- 	-- 		-- ikState.jointPoleAxisForBones = nil
-- 	-- 		-- ikState.composeOrderSwing = nil
-- 	-- 		-- ikState.composeOrderTwist = nil
-- 	-- 		-- ikState.lastCtrlPoleCS = nil
-- 	-- 		-- ikState.poleTwistSmoothedDeg = 0.0
-- 	-- 		-- ikState.twistBoneVecs = {}
-- 	-- 		-- local lowerArmRot = meshCopy:GetBoneRotationByName("r_LowerArm_JNT", EBoneSpaces.ComponentSpace)
-- 	-- 		-- if lowerArmRot ~= nil then
-- 	-- 		-- 	local twistBoneNames = {"r_lowerTwistUp_JNT", "r_lowerTwistMid_JNT", "r_lowerTwistLow_JNT"}
-- 	-- 		-- 	for _, boneName in ipairs(twistBoneNames) do
-- 	-- 		-- 		local boneCS = meshCopy:GetBoneRotationByName(boneName, EBoneSpaces.ComponentSpace)
-- 	-- 		-- 		if boneCS ~= nil then
-- 	-- 		-- 			ikState.twistBoneVecs[boneName] = {
-- 	-- 		-- 				x = kismet_math_library:LessLess_VectorRotator(kismet_math_library:GetForwardVector(boneCS), lowerArmRot),
-- 	-- 		-- 				z = kismet_math_library:LessLess_VectorRotator(kismet_math_library:GetUpVector(boneCS),    lowerArmRot),
-- 	-- 		-- 			}
-- 	-- 		-- 		end
-- 	-- 		-- 	end
-- 	-- 		-- end
-- 	-- 	end
-- 	-- end
-- end)

-- configui.onUpdate("twist_rotation", function(value)
-- 	if ikInstance ~= nil then
-- 		--ikInstance:setSolverParameter("a323432_ab_434543", "baseline_forearm_roll_deg", value.z)
-- 		--ikInstance:setSolverParameter("b567788_ab_434543", "baseline_forearm_roll_deg", value.z)
-- 	end
-- end)
-- local handsHidden = false
-- register_key_bind("F3", function()
-- 	handsHidden = not handsHidden
--     hands.hideHands(handsHidden)
-- end)
-- -- register_key_bind("F4", function()
-- --     uevrUtils.profiler:report()
-- -- end)

-- register_key_bind("F4", function()
-- 	if ikInstance ~= nil then
--     	ikInstance:printMeshBoneTransforms("a323432_ab_434543")
-- 	end
-- end)

-- register_key_bind("F1", function()
--     ik.destroyAll()
--     status["ikMeshComponent"] = nil
--     --ik.new({ animationsFile = "hands_parameters" })
-- end)




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

	-- if meshCopy ~= nil then
	-- 	SolveVRArmIK(
	-- 		meshCopy,               -- UPoseableMeshComponent
	-- 		"r_UpperArm_JNT",           -- e.g. "UpperArm_L"
	-- 		"r_LowerArm_JNT",          -- e.g. "LowerArm_L"
	-- 		"r_Hand_JNT",            -- e.g. "Hand_L"
	-- 		"r_wrist_JNT",
	-- 		controllers.getControllerLocation(Handed.Right),       -- VR controller world location (FVector)
	-- 		controllers.getControllerRotation(Handed.Right),       -- VR controller world rotation (FRotator)
	-- 		uevrUtils.vector(-8,0,0),         -- Offset from controller → hand bone (controller-local)
	-- 		false,       -- AllowStretch (rotation-only solve cannot magically extend the arm)
	-- 		0.0,  -- float
	-- 		0.0,     -- float,
	-- 		{  -- TwistBones: distribute wrist roll across the three forearm pronation bones
	-- 			{ bone = "r_lowerTwistUp_JNT",  fraction = 0.25 }, -- nearest elbow
	-- 			{ bone = "r_lowerTwistMid_JNT", fraction = 0.50 },
	-- 			{ bone = "r_lowerTwistLow_JNT", fraction = 0.75 }, -- nearest wrist
	-- 			--{ bone = "r_wrist_JNT", fraction = 0.90 }, -- nearest wrist
	-- 			-- r_wrist_JNT is a flexion bone (rest rotation differs ~90°) — not a twist bone
	-- 		}

	-- 	)
	-- end
end

uevr.params.sdk.callbacks.on_script_reset(function()
	if meshCopy ~= nil then
		uevrUtils.destroyComponent(meshCopy, true, true)
		meshCopy = nil
	end
	status["ikMeshComponent"] = nil
end)

-- register_key_bind("F2", function()
-- 	stopDebug = true
-- end)
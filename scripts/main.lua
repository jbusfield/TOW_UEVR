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

uevrUtils.setDeveloperMode(true)
hands.enableConfigurationTool()

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
--laser.setLaserLengthPercentage(0.0)

--since weapons are attached to the hand sockets for this game
--only let the hands be affected by gunstock offsets
attachments.setGunstockOffsetsEnabled(false)
hands.setGunstockOffsetsEnabled(true)

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
register_key_bind("F2", function()
	local userWidget = uevrUtils.getActiveWidgetByClass("WidgetBlueprintGeneratedClass /Game/UI/Menus/MainMenu/MainMenu.MainMenu_C")
	if userWidget ~= nil then
		print("Main menu widget found:")
		--widgetModule.logWidgetDescendants(userWidget)
		widgetModule.dumpWidgetEditableFields(userWidget)
	else
		print("No main menu widget found")
	end
end)

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
		local handsComponent = hands.getHandComponent(Handed.Right) --controllers.getController(Handed.Right) -- 
        if status["hasBoltActionFired"] == true then
			handsComponent = controllers.getController(Handed.Right)
		end
		--return handsComponent and weaponMesh, handsComponent, "WeaponPoint" --, controllers.getController(Handed.Right)
		local weaponAttachSocket = uevrUtils.getValid(pawn,{"Equipment","WeaponAttachSocket"}) or "WeaponPoint"
		return handsComponent and weaponMesh, handsComponent, weaponAttachSocket --, controllers.getController(Handed.Right)
    end
	--return getWeaponMesh(), controllers.getController(Handed.Right)
end)

function on_level_change(level)
	--print("Level changed\n")
	flickerFixer.create()
	setIdleCameraTimeout()
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

hook_function("Class /Script/Engine.AnimNotify", "Received_Notify", false,
    function(fn, obj, locals, result)
		print("AnimNotify fired:", obj and obj:get_class():get_full_name() or "nil")
		-- if locals ~= nil then
		-- 	for k,v in pairs(locals) do
		-- 		print("  ", k, v and v:get_full_name() or "nil")
		-- 	end
		-- 	local montage = locals.Montage
		-- 	if montage ~= nil then
		-- 		print("Montage:", montage:get_full_name())
		-- 	end
		-- 	local pawn = locals.Pawn
		-- 	if pawn ~= nil then
		-- 		print("Pawn:", pawn:get_full_name())
		-- 	end
		-- 	local meshComp = locals.MeshComp
		-- 	if meshComp ~= nil then
		-- 		print("MeshComp:", meshComp:get_full_name())
		-- 	end
		-- 	local anim = locals.Animation
		-- 	if anim ~= nil then
		-- 		print("Animation:", anim:get_full_name())
		-- 	end
		-- end
        -- if not shouldLogSocketRequests() then return end

        -- local attachNotifyClass = uevrUtils.get_class("Class /Script/Indiana.AnimNotify_AttachWeapon")
        -- if attachNotifyClass == nil or obj == nil or obj.is_a == nil or (not obj:is_a(attachNotifyClass)) then
        --     return
        -- end

        -- local montageName = (montage.getMostRecentMontage and montage.getMostRecentMontage()) or ""
        -- local animName = (locals.Animation and locals.Animation.get_full_name) and locals.Animation:get_full_name() or ""
        -- local meshName = (locals.MeshComp and locals.MeshComp.get_full_name) and locals.MeshComp:get_full_name() or ""

        -- local equip = uevrUtils.getValid(pawn, { "Equipment" })
        -- local weaponAttachSocket = equip and equip.WeaponAttachSocket or nil

        -- pendingSocketRequest = {
        --     montageName = montageName,
        --     animName = animName,
        --     meshName = meshName,
        --     weaponAttachSocket = fnameToString(weaponAttachSocket),
        -- }

        -- print("[SocketRequest] AnimNotify_AttachWeapon fired",
        --     "montage=" .. montageName,
        --     "weaponAttachSocket=" .. pendingSocketRequest.weaponAttachSocket,
        --     "anim=" .. animName,
        --     "mesh=" .. meshName
        -- )
		return false
    end
	, nil, true
)
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

-- Reload guidance (NO UFunction hooks; derives "what to do" from the animation)
local reloadGuide = {
    enabled = false,
    leftBoneName = nil,
    weaponSockets = nil,
    weaponMeshFullName = nil,
    suggestedSocket = nil,
    lastPrintKey = nil,
}

local function pickFirstExistingBone(mesh, candidates)
    if mesh == nil or mesh.GetSocketLocation == nil then return nil end
    for _, name in ipairs(candidates) do
        local ok, vec = pcall(function()
            return mesh:GetSocketLocation(uevrUtils.fname_from_string(name))
        end)
        if ok and vec ~= nil and vec.X ~= nil then
            return name
        end
    end
    return nil
end
local function ensureWeaponSockets(weaponMesh)
    if weaponMesh == nil then return end
    local full = weaponMesh:get_full_name()
    if reloadGuide.weaponSockets ~= nil and reloadGuide.weaponMeshFullName == full then return end

    reloadGuide.weaponSockets = nil
    reloadGuide.weaponMeshFullName = full

    uevrUtils.getSocketNames(weaponMesh, function(arr)
        reloadGuide.weaponSockets = {}
        if arr ~= nil then
            for _, v in ipairs(arr) do
                reloadGuide.weaponSockets[#reloadGuide.weaponSockets + 1] = tostring(v)
            end
        end
        print("[ReloadGuide] cached weapon sockets:", #reloadGuide.weaponSockets, "for", full)
    end)
end

register_key_bind("F3", function()
    reloadGuide.enabled = not reloadGuide.enabled
    reloadGuide.suggestedSocket = nil
    reloadGuide.lastPrintKey = nil
    print("[ReloadGuide] enabled =", reloadGuide.enabled)
end)

register_key_bind("F4", function()
    if not reloadGuide.enabled then
        print("[ReloadGuide] F4 ignored (disabled)")
        return
    end
    local socket = reloadGuide.suggestedSocket
    if socket == nil or socket == "" then
        print("[ReloadGuide] no suggested socket yet")
        return
    end

    local weaponMesh = getWeaponMesh()
    local leftHandComp = hands.getHandComponent(Handed.Left)
    if weaponMesh == nil or leftHandComp == nil then
        print("[ReloadGuide] missing weaponMesh or leftHandComp")
        return
    end

    -- AttachType: try 2 (SnapToTarget) first; if weird, change to 0.
    leftHandComp:K2_AttachTo(weaponMesh, uevrUtils.fname_from_string(socket), 2, false)
    print("[ReloadGuide] ATTACH NOW: left hand ->", socket)
end)

setInterval(10, function()
    if not reloadGuide.enabled then return end

    local weaponMesh = getWeaponMesh()
    local armsMesh = uevrUtils.getValid(pawn, {"FPVMesh"})
    local animInstance = uevrUtils.getValid(pawn, {"FPVMesh", "AnimScriptInstance"})
    if weaponMesh == nil or armsMesh == nil or animInstance == nil then return end

    local montageObj = (animInstance.GetCurrentActiveMontage ~= nil) and animInstance:GetCurrentActiveMontage() or nil
    if montageObj == nil then return end

    local montageName = uevrUtils.getShortName(montageObj)
    if montageName == nil then montageName = "" end
    if not montageName:lower():find("reload", 1, true) then
        return
    end

    ensureWeaponSockets(weaponMesh)

    if reloadGuide.leftBoneName == nil then
        reloadGuide.leftBoneName = pickFirstExistingBone(armsMesh, {
            "hand_l", "Hand_L", "l_hand", "LeftHand", "b_l_hand", "ik_hand_l"
        })
        print("[ReloadGuide] left bone =", tostring(reloadGuide.leftBoneName))
    end

    if reloadGuide.leftBoneName == nil or reloadGuide.weaponSockets == nil then return end
    if armsMesh.GetSocketLocation == nil or weaponMesh.GetSocketLocation == nil then return end

    local t = (animInstance.Montage_GetPosition ~= nil) and animInstance:Montage_GetPosition(montageObj) or -1
    local section = (animInstance.Montage_GetCurrentSection ~= nil) and animInstance:Montage_GetCurrentSection(montageObj) or nil
    local sectionStr = (section ~= nil and section.to_string ~= nil) and section:to_string() or tostring(section or "")

    local lh = armsMesh:GetSocketLocation(uevrUtils.fname_from_string(reloadGuide.leftBoneName))
    if lh == nil then return end

    local bestName, bestDist2 = nil, nil
    for _, socketName in ipairs(reloadGuide.weaponSockets) do
        local sp = weaponMesh:GetSocketLocation(uevrUtils.fname_from_string(socketName))
        if sp ~= nil then
            local dx, dy, dz = sp.X - lh.X, sp.Y - lh.Y, sp.Z - lh.Z
            local d2 = dx*dx + dy*dy + dz*dz
            if bestDist2 == nil or d2 < bestDist2 then
                bestDist2 = d2
                bestName = socketName
            end
        end
    end

    if bestName == nil then return end
    reloadGuide.suggestedSocket = bestName

    local printKey = montageName .. "|" .. sectionStr .. "|" .. bestName
    if printKey ~= reloadGuide.lastPrintKey then
        reloadGuide.lastPrintKey = printKey
        print(string.format("[ReloadGuide] montage=%s t=%.3f section=%s -> ATTACH socket=%s dist=%.2f",
            montageName, tonumber(t) or -1, sectionStr, bestName, math.sqrt(bestDist2 or 0)
        ))
    end
end)

register_key_bind("F6", function()
    local armsMesh = uevrUtils.getValid(pawn, {"FPVMesh"})
    if armsMesh == nil then
        print("[ReloadGuide] F6: no FPVMesh")
        return
    end
    uevrUtils.getSocketNames(armsMesh, function(arr)
        print("[ReloadGuide] FPVMesh socket/bone names (filtered):", arr and #arr or 0)
        if arr then
            for _, v in ipairs(arr) do
                local s = tostring(v)
                local sl = s:lower()
                if sl:find("hand", 1, true) or sl:find("wrist", 1, true) or sl:find("ik_", 1, true) then
                    print("  ", s)
                end
            end
        end
    end)
end)
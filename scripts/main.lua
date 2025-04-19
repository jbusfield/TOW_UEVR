local uevrUtils = require("libs/uevr_utils")
local flickerFixer = require("libs/flicker_fixer")
local controllersModule = require("libs/controllers")
uevrUtils.initUEVR(uevr)
local animation = require("libs/animation")
local handAnimations = require("addons/hand_animations")
local root = require("addons/root")

local masterPoseableComponent = nil
local isHoldingWeapon = false
local boneList = {22, 26, 11, 15, 19, 57, 61, 46, 50, 54}

function on_level_change(level)
	print("Level changed\n")
	flickerFixer.create()

	masterPoseableComponent = createPoseableTorso(pawn.FPVMesh)
	animation.add("hands", masterPoseableComponent, handAnimations)
	animation.pose("hands", "open_left")

	--root.create(pawn.FPVMesh)
end


function updatePoseableComponent(poseableComponent)
	if poseableComponent ~= nil then
		local boneSpace = 0
		local boneFName = uevrUtils.fname_from_string("r_wrist_JNT")

		local rightRotation = controllersModule.getControllerRotation(1)
		if rightRotation ~= nil then
		local leftRotation = controllersModule.getControllerRotation(0)
		rightRotation.Roll = rightRotation.Roll + 180 --right hand is rotated 180
		local fv = kismet_math_library:GetForwardVector(rightRotation)
		local uv = kismet_math_library:GetUpVector(rightRotation)
		local rv = kismet_math_library:GetRightVector(rightRotation)
		local forwardOffset = fv * -9.7
		local upOffset = uv * -2.6
		local rightOffset = rv * -2.5
		
		local leftLocation = controllersModule.getControllerLocation(0)
		local rightLocation = controllersModule.getControllerLocation(1) + forwardOffset + upOffset + rightOffset
		
		poseableComponent:SetBoneRotationByName(boneFName, rightRotation, boneSpace)
		poseableComponent:SetBoneLocationByName(boneFName, rightLocation, boneSpace);
		
		boneFName = uevrUtils.fname_from_string("l_wrist_JNT")
		poseableComponent:SetBoneRotationByName(boneFName, leftRotation, boneSpace)
		poseableComponent:SetBoneLocationByName(boneFName, leftLocation, boneSpace);
		
		poseableComponent:SetBoneLocationByName(uevrUtils.fname_from_string("r_shoulder_JNT"), rightLocation, boneSpace);
		poseableComponent:SetBoneLocationByName(uevrUtils.fname_from_string("r_UpperArm_JNT"), rightLocation, boneSpace);
		poseableComponent:SetBoneLocationByName(uevrUtils.fname_from_string("r_LowerArm_JNT"), rightLocation, boneSpace);

		poseableComponent:SetBoneLocationByName(uevrUtils.fname_from_string("l_shoulder_JNT"), leftLocation, boneSpace);
		poseableComponent:SetBoneLocationByName(uevrUtils.fname_from_string("l_UpperArm_JNT"), leftLocation, boneSpace);
		poseableComponent:SetBoneLocationByName(uevrUtils.fname_from_string("l_LowerArm_JNT"), leftLocation, boneSpace);

		local miniScale = 0.0001
		local count = poseableComponent:GetNumBones()
		for index = 1 , 5 do
			poseableComponent:SetBoneScaleByName(poseableComponent:GetBoneName(index), vector_3f(miniScale, miniScale, miniScale), boneSpace);
		end

		poseableComponent:SetBoneScaleByName(uevrUtils.fname_from_string("r_wrist_JNT"), vector_3f(1, 1, 1), boneSpace);		
		poseableComponent:SetBoneScaleByName(uevrUtils.fname_from_string("l_wrist_JNT"), vector_3f(1, 1, 1), boneSpace);
		end
	end 
end

function createPoseableMeshFromSkeletalMesh(skeletalMeshComponent)
	--print("Creating PoseableMeshComponent from",skeletalMeshComponent:get_full_name())
	local poseableComponent = nil
	if skeletalMeshComponent ~= nil then
		poseableComponent = uevrUtils.create_component_of_class("Class /Script/Engine.PoseableMeshComponent", false)
		if poseableComponent ~= nil then
			poseableComponent.SkeletalMesh = skeletalMeshComponent.SkeletalMesh		
			--force initial update
			poseableComponent:SetMasterPoseComponent(skeletalMeshComponent, true)
			poseableComponent:SetMasterPoseComponent(nil, false)
			
			pcall(function()
				poseableComponent:CopyPoseFromSkeletalComponent(skeletalMeshComponent)	
			end)	
		else 
			print("PoseableMeshComponent could not be created")
		end
	end
	return poseableComponent
end


function createPoseableTorso(skeletalMeshComponent)
	local poseableComponent = nil
	if skeletalMeshComponent ~= nil then
		poseableComponent = createPoseableMeshFromSkeletalMesh(skeletalMeshComponent)
		poseableComponent:SetVisibility(false,true)
		poseableComponent:K2_AttachTo(skeletalMeshComponent, uevrUtils.fname_from_string(""), 0, false)
		skeletalMeshComponent:SetMasterPoseComponent(poseableComponent, true)
	end
	return poseableComponent
end

function fixPlayerFOV(playerMesh)
	local propertyName = "ForegroundPriorityEnabled"
	local propertyFName = uevrUtils.fname_from_string(propertyName)	
	local value = 0.0
	
	local mesh = playerMesh
	if mesh ~= nil then
		local materials = mesh.OverrideMaterials
		for i, material in ipairs(materials) do
			--local oldValue = material:K2_GetScalarParameterValue(propertyFName)
			material:SetScalarParameterValue(propertyFName, value)
			--local newValue = material:K2_GetScalarParameterValue(propertyFName)
			--print("Material:",i, material:get_full_name(), oldValue, newValue,"\n")
		end

		children = mesh.AttachChildren
		if children ~= nil then
			for i, child in ipairs(children) do
				if child:is_a(static_mesh_component_c) then
					local materials = child.OverrideMaterials
					for i, material in ipairs(materials) do
						--local oldValue = material:K2_GetScalarParameterValue(propertyFName)
						material:SetScalarParameterValue(propertyFName, value)
						--local newValue = material:K2_GetScalarParameterValue(propertyFName)
						--print("Child Material:",i, material:get_full_name(), oldValue, newValue,"\n")
					end
				end
				
				if child:is_a(uevrUtils.get_class("Class /Script/Niagara.NiagaraComponent")) then
					child:SetNiagaraVariableFloat(propertyName, value)
					--print("Child Niagara Material:", child:get_full_name(),"\n")
				end
			end
		end
	end
end




function setFingerAngles(fingerIndex, jointIndex, angleID, angle)
	local pc = masterPoseableComponent
	local boneSpace = 0
	local boneFName = pc:GetBoneName(fingers[fingerIndex] + jointIndex - 1, boneSpace)
	
	local localRotator, pTransform = animation.getBoneSpaceLocalRotator(pc, boneFName, boneSpace)
	print("Local Space Before", fingerIndex, jointIndex, localRotator.Pitch, localRotator.Yaw, localRotator.Roll)
	if angleID == 0 then
		localRotator.Pitch = localRotator.Pitch + angle
	elseif angleID == 1 then
		localRotator.Yaw = localRotator.Yaw + angle
	elseif angleID == 2 then
		localRotator.Roll = localRotator.Roll + angle
	end
	print("Local Space After", fingerIndex, jointIndex, localRotator.Pitch, localRotator.Yaw, localRotator.Roll)
	animation.setBoneSpaceLocalRotator(pc, boneFName, localRotator, boneSpace, pTransform)

	animation.logBoneRotators(boneList)

	--FTransform MakeTransform(const struct FVector& Location, const struct FRotator& Rotation, const struct FVector& Scale)
	-- local wRotator =  kismet_math_library:TransformRotation(pTransform, localRotator);
	-- pc:SetBoneRotationByName(pc:GetBoneName(index), wRotator, boneSpace)
	
	-- local rotator = pc:GetBoneRotationByName(pc:GetBoneName(index), boneSpace)
	-- if angleID == 0 then
		-- rotator.Pitch = rotator.Pitch + angle
	-- elseif angleID == 1 then
		-- rotator.Yaw = rotator.Yaw + angle
	-- elseif angleID == 2 then
		-- rotator.Roll = rotator.Roll + angle
	-- end
	-- pc:SetBoneRotationByName(pc:GetBoneName(index), rotator, boneSpace)
	
	-- for i = 61 , 63 do
		-- local rotator = pc:GetBoneRotationByName(pc:GetBoneName(i), boneSpace)
		-- print(i, rotator.Pitch, rotator.Yaw, rotator.Roll)
	-- end
-- 61      RightHandIndex1_JNT
-- 62      RightHandIndex2_JNT
-- 63      RightHandIndex3_JNT

--original
-- Local Space2    61      13.954922676086 14.658146858215 12.959842681885
-- Local Space2    62      -7.2438387870789        36.064968109131 -3.0500030517578
-- Local Space2    63      -4.330756187439 11.854819297791 -4.8701119422913

--trigger
-- Local Space2    61      13.954909324646 19.658151626587 12.959843635559
-- Local Space2    62      -7.2438044548035        66.065002441406 -3.0500452518463
-- Local Space2    63      -4.330756187439 11.854818344116 -4.8701190948486


-- grip
-- Local Space2    61      8.955265045166  39.657428741455 22.959760665894
-- Local Space2    62      -2.2438399791718        96.064979553223 -33.050228118896
-- Local Space2    63      -4.330756187439 11.854824066162 -4.8701181411743

-- 61      54.028121948242 -55.77481842041 -178.15281677246
-- 62      4.8360877037048 -136.28285217285        126.11332702637
-- 63      -64.425819396973        -167.84855651855        132.86322021484
end

local animStates = {}
function updateAnimation(animID, animName, isPressed)
	if animStates[animName] == nil then animStates[animName] = false end
	if isPressed then
		if not animStates[animName] then
			animation.animate(animID, animName, "on")
		end
		animStates[animName] = true
	else
		if animStates[animName] then
			animation.animate(animID, animName, "off")
		end
		animStates[animName] = false
	end
end 

function on_xinput_get_state(retval, user_index, state)
	
	local triggerValue = state.Gamepad.bLeftTrigger
	updateAnimation("hands", "left_trigger", triggerValue > 100)

	updateAnimation("hands", "left_grip", uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_LEFT_SHOULDER))

    local left_controller = uevr.params.vr.get_left_joystick_source()
    local h_left_rest = uevr.params.vr.get_action_handle("/actions/default/in/ThumbrestTouchLeft")    
	updateAnimation("hands", "left_thumb", uevr.params.vr.is_action_active(h_left_rest, left_controller))
 
 	if not isHoldingWeapon then
		local triggerValue = state.Gamepad.bRightTrigger
		updateAnimation("hands", "right_trigger", triggerValue > 100)

		updateAnimation("hands", "right_grip", uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_RIGHT_SHOULDER))

		local right_controller = uevr.params.vr.get_right_joystick_source()
		local h_right_rest = uevr.params.vr.get_action_handle("/actions/default/in/ThumbrestTouchRight")  
		updateAnimation("hands", "right_thumb", uevr.params.vr.is_action_active(h_right_rest, right_controller))
	else
		local triggerValue = state.Gamepad.bRightTrigger
		updateAnimation("hands", "right_trigger_weapon", triggerValue > 100)
	end

end


function on_post_engine_tick(engine, delta)
	if uevrUtils.validate_object(masterPoseableComponent) ~= nil then
		masterPoseableComponent:SetVisibility(false,true)
		updatePoseableComponent(masterPoseableComponent)
	end
	if pawn.FPVMesh ~= nil then
		pawn.FPVMesh:SetVisibility(true, false)
		fixPlayerFOV(pawn.FPVMesh)
	end
	
end

hook_function("Class /Script/Indiana.IndianaPlayerCharacter", "EquippedWeaponChanged", true, 
	function(fn, obj, locals, result)
		print("IndianaPlayerCharacter EquippedWeaponChanged")
		print(NewlyEquippedWeapon)
		return false
	end
, nil, true)

hook_function("Class /Script/Indiana.IndianaPlayerCharacter", "WeaponHolstered", true, 
	function(fn, obj, locals, result)
		print("IndianaPlayerCharacter WeaponHolstered")
		isHoldingWeapon = false
		animation.pose("hands", "open_right")
		return false
	end
, nil, true)

hook_function("Class /Script/Indiana.IndianaPlayerCharacter", "WeaponUnholstered", true, 
	function(fn, obj, locals, result)
		print("IndianaPlayerCharacter WeaponUnholstered")
		isHoldingWeapon = true
		animation.pose("hands", "grip_right_weapon")
		return false
	end
, nil, true)

-- register_key_bind("F2", function()
    -- print("F2 pressed\n")
	-- masterPoseableComponent = createPoseableTorso(pawn.FPVMesh)
-- end)

register_key_bind("F1", function()
    print("F1 pressed\n")
	animation.logBoneRotators(boneList)
end)


local currentIndex = 1
local currentFinger = 1
register_key_bind("F2", function()
    print("F2 pressed\n")
	currentIndex = currentIndex + 1
	if currentIndex > 3 then currentIndex = 1 end
	print("Current finger joint", currentFinger, currentIndex)
end)

register_key_bind("F3", function()
    print("F3 pressed\n")
	currentFinger = currentFinger + 1
	if currentFinger > 10 then currentFinger = 1 end
	print("Current finger joint", currentFinger, currentIndex)
end)

--pitch
register_key_bind("y", function()
    print("y pressed\n")
	setFingerAngles(currentFinger, currentIndex, 0, 5)
end)
register_key_bind("b", function()
    print("b pressed\n")
	setFingerAngles(currentFinger, currentIndex, 0, -5)
end)

--yaw
register_key_bind("h", function()
    print("h pressed\n")
	setFingerAngles(currentFinger, currentIndex, 1, 5)
end)
register_key_bind("g", function()
    print("g pressed\n")
	setFingerAngles(currentFinger, currentIndex, 1, -5)
end)

--roll
register_key_bind("n", function()
    print("n pressed\n")
	setFingerAngles(currentFinger, currentIndex, 2, 5)
end)
register_key_bind("v", function()
    print("v pressed\n")
	setFingerAngles(currentFinger, currentIndex, 2, -5)
end)


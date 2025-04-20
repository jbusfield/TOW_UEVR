local uevrUtils = require("libs/uevr_utils")
local flickerFixer = require("libs/flicker_fixer")
local controllersModule = require("libs/controllers")
uevrUtils.initUEVR(uevr)
local animation = require("libs/animation")
local handAnimations = require("addons/hand_animations")
local hands = require("addons/hands")

local masterPoseableComponent = nil
local isHoldingWeapon = false

function on_level_change(level)
	print("Level changed\n")
	flickerFixer.create()
	hands.reset()
end

function on_lazy_poll()
	if not hands.exists() then
		hands.create(pawn.FPVMesh)
	end
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

function on_xinput_get_state(retval, user_index, state)
	hands.handleInput(state, isHoldingWeapon)
end


function on_post_engine_tick(engine, delta)
	if pawn.FPVMesh ~= nil then
		pawn.FPVMesh:SetVisibility(false, false)
		fixPlayerFOV(pawn.FPVMesh)
	end
	--animation.updateSkeletalVisualization(hands.getHandComponent(1))

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
		animation.pose("right_hand", "open_right")
		return false
	end
, nil, true)

hook_function("Class /Script/Indiana.IndianaPlayerCharacter", "WeaponUnholstered", true, 
	function(fn, obj, locals, result)
		print("IndianaPlayerCharacter WeaponUnholstered")
		isHoldingWeapon = true
		animation.pose("right_hand", "grip_right_weapon")
		return false
	end
, nil, true)


register_key_bind("F1", function()
    print("F1 pressed\n")
	animation.logBoneNames(pawn.FPVMesh)
	animation.getHierarchyForBone(pawn.FPVMesh, "r_LowerArm_JNT")
	--animation.createSkeletalVisualization(hands.getHandComponent(1), 0.003)
end)

local currentHand = 1
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
	hands.adjustLocation(currentHand, 1, 0.5)
	--hands.adjustRotation(currentHand, 1, 45)
	--hands.setFingerAngles(currentFinger, currentIndex, 0, 5)
end)
register_key_bind("b", function()
    print("b pressed\n")
	hands.adjustLocation(currentHand, 1, -0.5)
	--hands.adjustRotation(currentHand, 1, -45)
	--setFingerAngles(currentFinger, currentIndex, 0, -5)
end)

--yaw
register_key_bind("h", function()
    print("h pressed\n")
	hands.adjustLocation(currentHand, 2, 0.5)
	--hands.adjustRotation(currentHand, 2, 45)
	--setFingerAngles(currentFinger, currentIndex, 1, 5)
end)
register_key_bind("g", function()
    print("g pressed\n")
	hands.adjustLocation(currentHand, 2, -0.5)
	--hands.adjustRotation(currentHand, 2, -45)
	--setFingerAngles(currentFinger, currentIndex, 1, -5)
end)

--roll
register_key_bind("n", function()
    print("n pressed\n")
	hands.adjustLocation(currentHand, 3, 0.5)
	--hands.adjustRotation(currentHand, 3, 45)
	--setFingerAngles(currentFinger, currentIndex, 2, 5)
end)
register_key_bind("v", function()
    print("v pressed\n")
	hands.adjustLocation(currentHand, 3, -0.5)
	--hands.adjustRotation(currentHand, 3, -45)
	--setFingerAngles(currentFinger, currentIndex, 2, -5)
end)


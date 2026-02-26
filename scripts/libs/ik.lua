local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")
local animation = require("libs/animation")
require("libs/enums/unreal")

local M = {}

M.SolverType = {
    TWO_BONE = 1,
    ROTATION_ONLY = 2,
}

M.ControllerType = {
    LEFT_CONTROLLER = 0,
    RIGHT_CONTROLLER = 1,
}

local isDeveloperMode = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[ik] " .. text, logLevel)
	end
end

local ikConfigDev = nil
local parametersFileName = "ik_parameters"
local parameters = {
    label = "Default",
    mesh = "",
    solver = M.SolverType.TWO_BONE,
    end_bone = "",
    end_control_type = M.ControllerType.RIGHT_CONTROLLER,
    end_bone_offset = uevrUtils.vector(0,0,0),
    end_bone_rotation = uevrUtils.rotator(0,0,0),
    allow_wrist_affects_elbow = false,
    allow_stretch = false,
    start_stretch_ratio = 0.0,
    max_stretch_scale = 0.0,
    wrist_bone = "",
    twist_bones = {},
    invert_forearm_roll = false,
}
local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

local function setParameter(key, value, persist)
    print("[ik] Setting parameter:", key, value)
    return paramManager:setInActiveProfile(key, value, persist)
end

local function saveParameter(key, value, persist)
	--paramManager:set(key, value, persist)
    setParameter(key, value, persist)
end

local function getParameter(key)
    return paramManager:get(key)
end

local IK = {}
IK.__index = IK

local UKismetAnimationLibrary = nil
local accessoryStatus = {}

local SafeNormalize

local IK_MIN_SWING_DEG = 0.02
local IK_MIN_TWIST_DEG = 0.02

-- Optional: couple wrist roll into elbow pole so the elbow raises/lowers slightly as you pronate/supinate.
-- Keep conservative defaults to avoid pole flips.
local ELBOW_POLE_TWIST_INFLUENCE = -0.25 -- 0..1 (try 0.15-0.40)
local ELBOW_POLE_TWIST_MAX_DEG   = 75.0 -- clamp the measured twist before applying

-- Module-level constants (allocated once, never mutated).
local VEC_UNIT_Y     = nil  -- uevrUtils.vector(0,1,0) — initialised on first use after kismet is live
local VEC_UNIT_Y_FORWARD     = nil  -- uevrUtils.vector(0,1,0) — initialised on first use after kismet is live
local VEC_UNIT_Y_INVERSE     = nil  -- uevrUtils.vector(0,-1,0) — initialised on first use after kismet is live

-- Minimal IK state: baseline elbow direction for a stable pole.
local function newIKState()
	return {
		baselineElbowDirCS = nil,
		jointPoleAxisChoice = nil,
		jointPoleAxisForBones = nil,
		composeOrderSwing = nil,   -- cached: true = ComposeRotators(currentRot, delta), false = (delta, currentRot)
		composeOrderTwist = nil,   -- cached: true = ComposeRotators(swingRot, twist),   false = (twist, swingRot)
		twistBoneVecs = nil,       -- per-bone: { x, z } axes stored in lower-arm local space at F2 capture time
		lastCtrlPoleCS = nil,      -- for stable pole twist coupling
		poleTwistSmoothedDeg = 0.0,
		-- Cached per-mesh constants.
		-- NOTE: compToWorld and meshRightVec are NOT cached — they change every tick as the pawn rotates.
		upperLen = nil,            -- upper arm bone length         — skeleton constant
		lowerLen = nil,            -- lower arm bone length         — skeleton constant
		bonesKey = nil,            -- JointBone.."->"..EndBone     — never changes per call site
	}
end


function M.new(options)
    options = options or {}
    local self = setmetatable({
		tickPhase = options.tickPhase or "post", -- "pre" or "post"
		tickPriority = options.tickPriority,

    }, IK)

    if isDeveloperMode then
        local createConfigMonitor = doOnce(function()
            uevrUtils.registerUEVRCallback("on_ik_config_param_change", function(key, value, persist)
                self:setSolverParameter(paramManager:getActiveProfile(), key, value, true)
            end)
        end, Once.EVER)
        createConfigMonitor()
    end


    self:create() -- auto-create component
    return self
end

function IK:setParameters(params, persist)
    for k, v in pairs(params) do
        if persist then
            paramManager:createProfile(k, v.label)
            paramManager:setActiveProfile(k)
            for pk, pv in pairs(v) do
                paramManager:setInActiveProfile(pk, pv, true)
            end
        else
            saveParameter(k, v, persist)
        end
    end
end

local function getAncestorBones(mesh, boneName, generations)
    if mesh == nil or boneName == nil or generations == nil then
        return {}
    end
    local ancestors = {}
    local currentBone = boneName
    for i = 1, generations do
        local parentBone = mesh:GetParentBone(currentBone)
        if parentBone == nil or parentBone == "" then
            break
        end
        table.insert(ancestors, parentBone:to_string())
        currentBone = parentBone
    end
    return ancestors
end

local keyMap = {
    end_bone = "endBone",
    wrist_bone = "wristBone",
    end_bone_offset = "handOffset",
    end_bone_rotation = "endBoneRotation",
    allow_wrist_affects_elbow = "allowWristAffectsElbow",
    allow_stretch = "allowStretch",
    start_stretch_ratio = "startStretchRatio",
    max_stretch_scale = "maxStretchScale",
    controller = "controller",
    twist_bones = "twistBones",
    invert_forearm_roll = "invertForearmRoll",
}
function IK:setSolverParameter(solverId, paramName, value, persist)
    if persist then
        saveParameter(paramName, value, persist)
        -- local p = paramManager:get(solverId) or {}
        -- p[paramName] = value
        -- saveParameter(solverId, p, persist)
    end

            -- self.activeSolvers[solverId] = {
            --     mesh = mesh,
            --     rootBone = parentBones[#parentBones],
            --     jointBone = parentBones[#parentBones - 1],
            --     endBone = solverParams["end_bone"],
            --     wristBone = solverParams["wrist_bone"] or "",
            --     controller = controller,
            --     handOffset = solverParams["end_bone_offset"] and uevrUtils.vector(solverParams["end_bone_offset"]) or uevrUtils.vector(0,0,0),
            --     endBoneRotation = solverParams["end_bone_rotation"] and uevrUtils.rotator(solverParams["end_bone_rotation"]) or uevrUtils.rotator(0,0,0),
            --     allowWristAffectsElbow = solverParams["allow_wrist_affects_elbow"] or false,
            --     allowStretch = solverParams["allow_stretch"] or false,
            --     startStretchRatio = solverParams["start_stretch_ratio"] or 0.0,
            --     maxStretchScale = solverParams["max_stretch_scale"] or 0.0,
            --     twistBones = solverParams["twist_bones"] or {},
            --     invertForearmRoll = solverParams["invert_forearm_roll"] or false,
			-- 	state = newIKState(),
            -- }

    -- print("IK:setSolverParameter:", solverId, paramName, value)
	-- self.activeSolvers = self.activeSolvers or {}
	-- local active = self.activeSolvers[solverId]
	-- if active ~= nil and keyMap[paramName] ~= nil then
	-- 	active[keyMap[paramName]] = value
	-- end

    self:setActive(solverId, true)
end


local function executeIsAnimatingFromMeshCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", table.unpack({...}))
end

function IK:setInitialTransform(solverId)
    local activeParams = self.activeSolvers[solverId]
    if activeParams ~= nil and activeParams.wasAnimating then
        activeParams.wasAnimating = false
        local mesh = activeParams.mesh
        local transforms = activeParams.initialTransforms
        if transforms and type(transforms) == "table" then
            --keeping the bones in the same numbered order as the original seems to keep the transforms
            --being applied in the correct order but I dont know if that is always the case
            --Applying them out of order results in a destroyed mesh
            for i, entry in ipairs(transforms) do
                if entry.boneName and entry.transform then
                    --print("Re-applying initial transform for bone:", entry.boneName)
                    local f = uevrUtils.fname_from_string(entry.boneName)
                    mesh:SetBoneTransformByName(f, entry.transform, EBoneSpaces.ComponentSpace)
                end
            end
            -- for boneName, data in pairs(transforms) do
            --     if boneName and data then
            --         print("Re-applying transform for bone:", boneName)
            --         local f = uevrUtils.fname_from_string(boneName)
            --         mesh:SetBoneTransformByName(f, data, EBoneSpaces.ComponentSpace)
            --     end
            -- end
        end
    end
end

function IK:animateFromMesh(animationMesh)
    if animationMesh == nil then return end
    local poseCopied = {}
    for solverId, activeParams in pairs(self.activeSolvers) do
        if activeParams then
            --only copy the pose once per tick
            if poseCopied[activeParams.mesh] == nil then
                local success, response = pcall(function()
                    activeParams.mesh:CopyPoseFromSkeletalComponent(animationMesh)
                end)
                if success == false then
                    --M.print("[hands] " .. response, LogLevel.Error)
                    print(activeParams.mesh)
                    print(activeParams.mesh:get_full_name())
                end
                poseCopied[activeParams.mesh] = true
            end

            activeParams.wasAnimating = true
        end
    end
end

function IK:create()
    if UKismetAnimationLibrary == nil then
		UKismetAnimationLibrary = uevrUtils.find_default_instance("Class /Script/AnimGraphRuntime.KismetAnimationLibrary")
	end
	if UKismetAnimationLibrary == nil then
		print("Unable to find KismetAnimationLibrary. IK disabled")
		return
	end
	-- Allocate-once constants: kismet_math_library is guaranteed live by this point.
	if VEC_UNIT_Y     == nil then VEC_UNIT_Y     = uevrUtils.vector(0, 1, 0) end
	if VEC_UNIT_Y_FORWARD     == nil then VEC_UNIT_Y_FORWARD     = uevrUtils.vector(0, 1, 0) end
    if VEC_UNIT_Y_INVERSE     == nil then VEC_UNIT_Y_INVERSE     = uevrUtils.vector(0, -1, 0) end

    self.activeSolvers = {}
	-- Register tick callback
	local tickFn = function(engine, delta)
        if self.activeSolvers ~= nil then
            local isLeftAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Left))
		    local isRightAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Right))
            if (isLeftAnimating or isRightAnimating) then
                self:animateFromMesh(uevrUtils.getValid(pawn, {"FPVMesh"}))
            else
                for solverId, activeParams in pairs(self.activeSolvers) do
                    if activeParams then
                        if activeParams.wasAnimating then
                            self:setInitialTransform(solverId) --redundently applies to single mesh twice but only happens once at montage end. Still should be better
                        end

                        local solverParams = paramManager:get(solverId)
                        if solverParams ~= nil then
                            if solverParams.solver == M.SolverType.TWO_BONE then
                                self:solveTwoBone(activeParams)
                            end
                        end
                    end
                end
            end
        end
	end
	if self.tickPhase == "pre" then
		uevrUtils.registerPreEngineTickCallback(tickFn, self.tickPriority)
	else
		uevrUtils.registerPostEngineTickCallback(tickFn, self.tickPriority)
	end
end

-- local parameters = {
--     a323432_ab_434543 = {
--         label = "Arms Only Right",
--         --mesh = "Pawn.FPVMesh",
--         mesh = "Custom",
--         solver = M.SolverType.TWO_BONE,
--         end_bone = "r_Hand_JNT",
--         end_control_type = M.ControllerType.RIGHT_CONTROLLER,
--         end_bone_offset = uevrUtils.vector(-8,0,0),
--         allow_stretch = false,
--         start_stretch_ratio = 0.0,
--         max_stretch_scale = 0.0,
--         wrist_bone = "r_wrist_JNT",
--         twist_bones = {
--             { bone = "r_lowerTwistUp_JNT",  fraction = 0.25 },
--             { bone = "r_lowerTwistMid_JNT", fraction = 0.50 },
--             { bone = "r_lowerTwistLow_JNT", fraction = 0.75 },
--         },
--     },
--     b567788_ab_434543 = {
--         label = "Arms Only Left",
--         --mesh = "Pawn.FPVMesh",
--         mesh = "Custom",
--         solver = M.SolverType.TWO_BONE,
--         end_bone = "l_Hand_JNT",
--         end_control_type = M.ControllerType.LEFT_CONTROLLER,
--         end_bone_offset = uevrUtils.vector(-8,0,0),
--         allow_stretch = false,
--         start_stretch_ratio = 0.0,
--         max_stretch_scale = 0.0,
--         wrist_bone = "l_wrist_JNT",
--         twist_bones = {
--             { bone = "l_lowerTwistUp_JNT",  fraction = 0.25 },
--             { bone = "l_lowerTwistMid_JNT", fraction = 0.50 },
--             { bone = "l_lowerTwistLow_JNT", fraction = 0.75 },
--         },
--     }
-- }

local function mulVec(v, s)
	return kismet_math_library:Multiply_VectorFloat(v, s)
end

local function getBoneDirCS(mesh, fromBone, toBone)
	if mesh == nil then return nil end
	local a = mesh:GetBoneLocationByName(fromBone, EBoneSpaces.ComponentSpace)
	local b = mesh:GetBoneLocationByName(toBone, EBoneSpaces.ComponentSpace)
	if a == nil or b == nil then return nil end
	return SafeNormalize(kismet_math_library:Subtract_VectorVector(b, a))
end

local function axisVectorsFromRot(rot)
	if rot == nil then return nil, nil, nil end
	return SafeNormalize(kismet_math_library:GetForwardVector(rot)),
		SafeNormalize(kismet_math_library:GetRightVector(rot)),
		SafeNormalize(kismet_math_library:GetUpVector(rot))
end

local function chooseBestAxis(axisX, axisY, axisZ, dir)
	if dir == nil then return { axis = "X", sign = 1, score = 0 } end
	local function scoreAxis(a)
		if a == nil then return 0 end
		local d = kismet_math_library:Dot_VectorVector(a, dir) or 0
		return d
	end
	local dx = scoreAxis(axisX)
	local dy = scoreAxis(axisY)
	local dz = scoreAxis(axisZ)
	local adx, ady, adz = math.abs(dx), math.abs(dy), math.abs(dz)
	if adx >= ady and adx >= adz then
		return { axis = "X", sign = (dx >= 0) and 1 or -1, score = dx }
	elseif ady >= adx and ady >= adz then
		return { axis = "Y", sign = (dy >= 0) and 1 or -1, score = dy }
	else
		return { axis = "Z", sign = (dz >= 0) and 1 or -1, score = dz }
	end
end

local function chooseBestPoleAxis(axisX, axisY, axisZ, longAxisChar, poleDir)
	local best = { axis = "Y", sign = 1, score = 0 }
	local function tryAxis(char, vec)
		if char == longAxisChar or vec == nil then return end
		local d = kismet_math_library:Dot_VectorVector(vec, poleDir) or 0
		local ad = math.abs(d)
		if ad > best.score then
			best = { axis = char, sign = (d >= 0) and 1 or -1, score = ad }
		end
	end
	tryAxis("X", axisX)
	tryAxis("Y", axisY)
	tryAxis("Z", axisZ)
	return best
end

local function axisVectorFromRotator(rot, axisChar)
	if rot == nil then return nil end
	if axisChar == "X" then
		return kismet_math_library:GetForwardVector(rot)
	elseif axisChar == "Y" then
		return kismet_math_library:GetRightVector(rot)
	else
		return kismet_math_library:GetUpVector(rot)
	end
end

local function signedAngleDegAroundAxis(a, b, axis)
	-- Signed angle from a->b around axis.
	local cross = kismet_math_library:Cross_VectorVector(a, b)
	local y = kismet_math_library:Dot_VectorVector(axis, cross) or 0.0
	local x = kismet_math_library:Dot_VectorVector(a, b) or 1.0
	return kismet_math_library:RadiansToDegrees(math.atan(y, x))
end

local function alignBoneAxisToDirCS(mesh, boneName, childBoneName, desiredDirCS, axisChoice, poleCS, state)
	local currentRot = mesh:GetBoneRotationByName(boneName, EBoneSpaces.ComponentSpace)
	if currentRot == nil then return nil end

	-- 1) Determine current direction to align.
	-- In this project we always call with childBoneName; keep a small fallback for completeness.
	local currentDir = (childBoneName ~= nil) and getBoneDirCS(mesh, boneName, childBoneName) or nil
	if currentDir == nil and axisChoice ~= nil then
		local axisVec = axisVectorFromRotator(currentRot, axisChoice.axis or "X")
		currentDir = axisVec and SafeNormalize(mulVec(axisVec, axisChoice.sign or 1)) or nil
	end
	if currentDir == nil or kismet_math_library:VSize(currentDir) < 0.0001 then
		return currentRot
	end
	local desiredDir = SafeNormalize(desiredDirCS)
	if desiredDir == nil or kismet_math_library:VSize(desiredDir) < 0.0001 then
		return currentRot
	end

	-- 2) Swing: rotate currentDir -> desiredDir.
	local dot = kismet_math_library:Dot_VectorVector(currentDir, desiredDir) or 1.0
	dot = kismet_math_library:FClamp(dot, -1.0, 1.0)
	local swingAngleDeg = kismet_math_library:RadiansToDegrees(kismet_math_library:Acos(dot))
	if swingAngleDeg ~= nil and swingAngleDeg < IK_MIN_SWING_DEG then return currentRot end

	local swingAxis = kismet_math_library:Cross_VectorVector(currentDir, desiredDir)
	if kismet_math_library:VSize(swingAxis) < 0.0001 then
		-- 180° case: pick a stable fallback axis using the pole.
		local pole = SafeNormalize(poleCS)
		if pole == nil or kismet_math_library:VSize(pole) < 0.0001 then pole = VEC_UNIT_Y end
		swingAxis = kismet_math_library:Cross_VectorVector(currentDir, pole)
	end
	swingAxis = SafeNormalize(swingAxis)
	if swingAxis == nil or kismet_math_library:VSize(swingAxis) < 0.0001 then return currentRot end

	local deltaSwing = kismet_math_library:RotatorFromAxisAndAngle(swingAxis, swingAngleDeg)
	local cand1 = kismet_math_library:ComposeRotators(deltaSwing, currentRot)
	local cand2 = kismet_math_library:ComposeRotators(currentRot, deltaSwing)

	local swingRot
	if state ~= nil and state.composeOrderSwing == nil then
		-- Detect once: which composition order actually rotates the bone direction toward desiredDir?
		local localDir = SafeNormalize(kismet_math_library:LessLess_VectorRotator(currentDir, currentRot))
		local function score(rot)
			if rot == nil then return -1 end
			local a = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(localDir, rot))
			return kismet_math_library:Dot_VectorVector(a, desiredDir) or -1
		end
		state.composeOrderSwing = score(cand2) > score(cand1)
	end
	swingRot = (state ~= nil and state.composeOrderSwing) and cand2 or cand1

	-- 3) Optional twist: align a pole axis in the plane orthogonal to desiredDir.
	local poleAxisChoice = axisChoice and axisChoice.pole or nil
	if poleAxisChoice == nil then
		return swingRot
	end
	local poleAxisChar = poleAxisChoice.axis
	local poleAxisSign = poleAxisChoice.sign or 1
    --poleAxisSign = -poleAxisSign

	local desiredPole = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(poleCS, desiredDir))
	if desiredPole == nil or kismet_math_library:VSize(desiredPole) < 0.0001 then return swingRot end

	local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
	if poleAxisVec == nil then return swingRot end
	local currentPole = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir))
	if currentPole == nil or kismet_math_library:VSize(currentPole) < 0.0001 then return swingRot end

	local twistAngleDeg = signedAngleDegAroundAxis(currentPole, desiredPole, desiredDir)
	if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then return swingRot end

	local deltaTwist = kismet_math_library:RotatorFromAxisAndAngle(desiredDir, twistAngleDeg)
	local t1 = kismet_math_library:ComposeRotators(deltaTwist, swingRot)
	local t2 = kismet_math_library:ComposeRotators(swingRot, deltaTwist)
	if state ~= nil and state.composeOrderTwist == nil then
		local function scorePole(rot)
			local p = axisVectorFromRotator(rot, poleAxisChar)
			if p == nil then return -1 end
			p = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(mulVec(p, poleAxisSign), desiredDir))
			return kismet_math_library:Dot_VectorVector(p, desiredPole) or -1
		end
		state.composeOrderTwist = scorePole(t2) > scorePole(t1)
	end
	return (state ~= nil and state.composeOrderTwist) and t2 or t1
end
alignBoneAxisToDirCS = uevrUtils.profiler:wrap("alignBoneAxisToDirCS", alignBoneAxisToDirCS)

SafeNormalize = function(v)
	if v == nil then return uevrUtils.vector(0,0,0) end
	-- UKismetMathLibrary has VSize/Divide_VectorFloat (see Engine_classes.hpp)
	local len = kismet_math_library:VSize(v)
	if len == nil or len < 0.0001 then
		return uevrUtils.vector(0,0,0)
	end
	return kismet_math_library:Divide_VectorFloat(v, len)
end
SafeNormalize = uevrUtils.profiler:wrap("SafeNormalize", SafeNormalize)

-- local function getTargetLocationAndRotation(hand, controller)
--     local loc = nil
--     local rot = nil
--     if accessoryStatus[hand] == nil then
--         loc = controller and controller:K2_GetComponentLocation() or nil
--         rot = controller and controller:K2_GetComponentRotation() or nil
--     else
--         local status = accessoryStatus[hand]
--         loc = status.parentAttachment:GetSocketLocation(uevrUtils.fname_from_string(status.socketName or ""))
--         rot = status.parentAttachment:GetSocketRotation(uevrUtils.fname_from_string(status.socketName or ""))
--         if status.loc ~= nil and status.rot ~= nil then
--             local offsetPos = uevrUtils.vector(status.loc) or uevrUtils.vector(0,0,0)
--             local offsetRot = uevrUtils.rotator(status.rot) or uevrUtils.rotator(0,0,0)
--             --its not clear why this is needed
--             local temp = offsetRot.Pitch
--             offsetRot.Pitch = -offsetRot.Roll
--             offsetRot.Roll = -temp

--             loc = kismet_math_library:Add_VectorVector(loc, kismet_math_library:GreaterGreater_VectorRotator(offsetPos, rot))
--             rot = kismet_math_library:ComposeRotators(rot, offsetRot)
--         end
--         -- = {
--         --     parentAttachment = parentAttachment,
--         --     socketName = socketName,
--         --     attachType = attachType,
--         --     loc = loc,
--         --     rot = rot,
--         -- }
--     end
--     return loc, rot
-- end

local function getTargetLocationAndRotation(hand, controller)
    local loc = nil
    local rot = nil
    if accessoryStatus[hand] == nil then
        loc = controller and controller:K2_GetComponentLocation() or nil
        rot = controller and controller:K2_GetComponentRotation() or nil
    else
        local status = accessoryStatus[hand]
        loc = status.parentAttachment:GetSocketLocation(uevrUtils.fname_from_string(status.socketName or ""))
        rot = status.parentAttachment:GetSocketRotation(uevrUtils.fname_from_string(status.socketName or ""))
        if status.loc ~= nil and status.rot ~= nil then
            local offsetPos = uevrUtils.vector(status.loc) or uevrUtils.vector(0,0,0)
            local offsetRot = uevrUtils.rotator(status.rot) or uevrUtils.rotator(0,0,0)

            loc = kismet_math_library:Add_VectorVector(loc, kismet_math_library:GreaterGreater_VectorRotator(offsetPos, rot))
            rot = kismet_math_library:ComposeRotators(offsetRot, rot)
        end
    end
    return loc, rot
end

function IK:solveTwoBone(solverParams)
    -- mesh,               -- UPoseableMeshComponent
    -- RootBone,           -- e.g. "UpperArm_L"
    -- JointBone,          -- e.g. "LowerArm_L"
    -- EndBone,            -- e.g. "Hand_L"
    -- wristBone,            -- e.g. "Hand_L"
	-- ControllerWS,       -- VR controller world location (FVector)
	-- ControllerRotWS,    -- VR controller world rotation (FRotator) (optional)
	-- HandOffset,         -- FVector offset from controller → hand bone (in controller local space)
    -- AllowStretch,       -- bool
    -- StartStretchRatio,  -- float
    -- MaxStretchScale,     -- float
	-- twistBones
    local mesh = solverParams.mesh
    local RootBone = solverParams.rootBone
    local JointBone = solverParams.jointBone
    local EndBone = solverParams.endBone
    local wristBone = solverParams.wristBone
    local controllerPosWS, controllerRotWS = getTargetLocationAndRotation(solverParams.hand, solverParams.controller)
    -- local controllerPosWS = solverParams.controller and solverParams.controller:K2_GetComponentLocation() or nil
    -- local controllerRotWS = solverParams.controller and solverParams.controller:K2_GetComponentRotation() or nil
    local handOffset = solverParams.handOffset
    local AllowStretch = solverParams.allowStretch
    local StartStretchRatio = solverParams.startStretchRatio
    local MaxStretchScale = solverParams.maxStretchScale
    local twistBones = solverParams.twistBones
    local endBoneRotation = solverParams.endBoneRotation
    local allowWristAffectsElbow = solverParams.allowWristAffectsElbow
    local invertForearmRoll = solverParams.invertForearmRoll
	local state = solverParams.state
	-- if state == nil then
	-- 	state = newIKState()
	-- 	solverParams.state = state
	-- end
    VEC_UNIT_Y = invertForearmRoll == true and VEC_UNIT_Y_INVERSE or VEC_UNIT_Y_FORWARD


	if controllerPosWS == nil or controllerRotWS == nil then
        print("solveTwoBone: Missing controller position/rotation")
		return
	end
	--print(ControllerRotWS.Pitch, ControllerRotWS.Yaw, ControllerRotWS.Roll)

    --------------------------------------------------------------
    -- 1. Component transform + shoulder position (fail-fast)
    --------------------------------------------------------------
	-- compToWorld MUST be fetched every tick: the mesh is parented to pawn.RootComponent,
	-- so any body rotation changes this transform. Caching it causes the hand to drift
	-- away from the controller whenever the pawn rotates.
	if mesh.K2_GetComponentToWorld == nil then
		print("SolveVRArmIK: Mesh has no K2_GetComponentToWorld")
		return
	end
	local compToWorld = mesh:K2_GetComponentToWorld()
	if compToWorld == nil then return end

	local ShoulderWS = mesh:GetBoneLocationByName(RootBone, EBoneSpaces.WorldSpace)
	if ShoulderWS == nil then return end


    --------------------------------------------------------------
    -- 2. Compute Effector (hand target)
    --------------------------------------------------------------
    -- effectorWS = where the HAND BONE should go
    -- controllerPosWS is where the real hand is
    -- handOffset rotates/translates controller → hand bone pose
    --------------------------------------------------------------
	-- If you want no offsets: pass handOffset=nil and effectorWS will be the controller location.
	-- handOffset is controller-local, so we must rotate it by the controller's world rotation.
	local effectorWS = controllerPosWS
	if handOffset ~= nil then
		local offsetWS = handOffset
		if controllerRotWS ~= nil then
			offsetWS = kismet_math_library:GreaterGreater_VectorRotator(handOffset, controllerRotWS)
		end
		effectorWS = kismet_math_library:Add_VectorVector(controllerPosWS, offsetWS)
	end

    --------------------------------------------------------------
    -- 3. Auto-generate JointTarget (elbow direction)
    --------------------------------------------------------------
    -- Forward direction from shoulder → hand target
	local Forward = SafeNormalize(kismet_math_library:Subtract_VectorVector(effectorWS, ShoulderWS))

	-- Elbow pole vector:
	-- Use the baseline elbow direction projected onto the reach plane.
	-- This keeps the elbow bending in a consistent, "natural" direction instead of flipping.

	if state ~= nil and state.baselineElbowDirCS == nil then
		local sCS0 = mesh:GetBoneLocationByName(RootBone, EBoneSpaces.ComponentSpace)
		local jCS0 = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.ComponentSpace)
		if sCS0 ~= nil and jCS0 ~= nil then
			state.baselineElbowDirCS = SafeNormalize(kismet_math_library:Subtract_VectorVector(jCS0, sCS0))
		end
	end
	-- GetRightVector changes with pawn rotation — fetch fresh every tick.
	local OutwardWS = mesh:GetRightVector()
	if state ~= nil and state.baselineElbowDirCS ~= nil then
		local reachCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, Forward))
		local poleCS = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(state.baselineElbowDirCS, reachCS))
		if kismet_math_library:VSize(poleCS) < 0.0001 then
			poleCS = VEC_UNIT_Y
		end

		-- Optional: rotate pole around reach axis based on controller's orientation in the reach plane.
		-- NOTE: keep this stable: do NOT switch between controller axes per-frame (that flickers).
		-- If direction is wrong, flip the sign of ELBOW_POLE_TWIST_INFLUENCE.
		if allowWristAffectsElbow and controllerRotWS ~= nil and ELBOW_POLE_TWIST_INFLUENCE ~= nil and math.abs(ELBOW_POLE_TWIST_INFLUENCE) > 0.0001 then
			local ctrlCompRot = kismet_math_library:InverseTransformRotation(compToWorld, controllerRotWS)
			if ctrlCompRot ~= nil then
				local ctrlUpCS = SafeNormalize(kismet_math_library:GetUpVector(ctrlCompRot))
				local upProj = (ctrlUpCS ~= nil) and SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(ctrlUpCS, reachCS)) or nil
				local upProjLen = (upProj ~= nil) and (kismet_math_library:VSize(upProj) or 0.0) or 0.0
				-- If the controller up axis is close to the reach axis, projection becomes unstable.
				-- In that case, hold the last valid projection instead of flipping sign/axis.
				if upProjLen > 0.25 then
					state.lastCtrlPoleCS = upProj
				end
				local ctrlPoleCS = state.lastCtrlPoleCS
				if ctrlPoleCS ~= nil and kismet_math_library:VSize(ctrlPoleCS) > 0.0001 then
					local rawTwistDeg = signedAngleDegAroundAxis(poleCS, ctrlPoleCS, reachCS)
					if rawTwistDeg ~= nil then
						rawTwistDeg = kismet_math_library:FClamp(rawTwistDeg, -ELBOW_POLE_TWIST_MAX_DEG, ELBOW_POLE_TWIST_MAX_DEG)
						local targetApplied = rawTwistDeg * ELBOW_POLE_TWIST_INFLUENCE
						-- Light smoothing to prevent per-frame bounce.
						state.poleTwistSmoothedDeg = (state.poleTwistSmoothedDeg or 0.0) + (targetApplied - (state.poleTwistSmoothedDeg or 0.0)) * 0.20
						local appliedDeg = state.poleTwistSmoothedDeg or 0.0
						if math.abs(appliedDeg) > 0.01 then
							local deltaPoleRot = kismet_math_library:RotatorFromAxisAndAngle(reachCS, appliedDeg)
							poleCS = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(poleCS, deltaPoleRot))
						end
					end
				end
			end
		end

		OutwardWS = SafeNormalize(kismet_math_library:TransformDirection(compToWorld, poleCS))
	end

	-- Bone lengths are skeleton constants — measure once, then reuse.
	local JointWS = mesh:GetBoneLocationByName(JointBone, EBoneSpaces.WorldSpace)
	local EndWS   = mesh:GetBoneLocationByName(EndBone,   EBoneSpaces.WorldSpace)
	if state.upperLen == nil and JointWS ~= nil then
		state.upperLen = kismet_math_library:VSize(kismet_math_library:Subtract_VectorVector(JointWS, ShoulderWS))
	end
	if state.lowerLen == nil and JointWS ~= nil and EndWS ~= nil then
		state.lowerLen = kismet_math_library:VSize(kismet_math_library:Subtract_VectorVector(EndWS, JointWS))
	end
	local upperLen = state.upperLen or 30.0
	local lowerLen = state.lowerLen or 30.0
	local forwardDist = (upperLen + lowerLen) * 0.5
	local outwardDist = upperLen * 0.35

	-- Final elbow direction point
	local JointTargetWS = kismet_math_library:Add_VectorVector(
		ShoulderWS,
		kismet_math_library:Add_VectorVector(
			kismet_math_library:Multiply_VectorFloat(Forward, forwardDist),
			kismet_math_library:Multiply_VectorFloat(OutwardWS, outwardDist)
		)
	)


    --------------------------------------------------------------
    -- 5. Run IK solver
    --------------------------------------------------------------
    local OutJointWS = uevrUtils.vector()
    local OutEndWS   = uevrUtils.vector()

---@diagnostic disable-next-line: need-check-nil, undefined-field
    UKismetAnimationLibrary:K2_TwoBoneIK(
        ShoulderWS, JointWS, EndWS,
        JointTargetWS, effectorWS,
        OutJointWS, OutEndWS,
        AllowStretch, StartStretchRatio, MaxStretchScale
    )


    --------------------------------------------------------------
    -- 6. Reconstruct rotations from solved positions
    --------------------------------------------------------------
	local UpperDirWS = SafeNormalize(kismet_math_library:Subtract_VectorVector(OutJointWS, ShoulderWS))
	local LowerDirWS = SafeNormalize(kismet_math_library:Subtract_VectorVector(OutEndWS, OutJointWS))

	--------------------------------------------------------------
	-- 7. Build target rotations in ComponentSpace
	--------------------------------------------------------------
	-- Many skeletons do NOT use +X as the "bone points-to-child" axis.
	-- We calibrate which axis (X/Y/Z with sign) to align, then construct a component-space rot.
	local upperDirCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, UpperDirWS))
	local lowerDirCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, LowerDirWS))
	local poleCS = SafeNormalize(kismet_math_library:InverseTransformDirection(compToWorld, OutwardWS))

	-- Cache the elbow pole axis selection once.
	-- Re-detecting every tick can flip between axes as the joint rotates, which looks like a 180° palm twist.
	if state.bonesKey == nil then state.bonesKey = JointBone .. "->" .. EndBone end
	local bonesKey = state.bonesKey
	if state.jointPoleAxisChoice == nil or state.jointPoleAxisForBones ~= bonesKey then
		local jointDir = getBoneDirCS(mesh, JointBone, EndBone)
		local jx, jy, jz = axisVectorsFromRot(mesh:GetBoneRotationByName(JointBone, EBoneSpaces.ComponentSpace))
		local jointLong = chooseBestAxis(jx, jy, jz, jointDir)
		state.jointPoleAxisChoice = chooseBestPoleAxis(jx, jy, jz, jointLong.axis, VEC_UNIT_Y)
		state.jointPoleAxisForBones = bonesKey
	end
	local axisJoint = { pole = state.jointPoleAxisChoice }

	--------------------------------------------------------------
	-- 8. Apply component-space rotations
	--------------------------------------------------------------
	-- Shoulder: swing-only. Twist here tends to look terrible; push twist down-chain.
	local ShoulderCompRot = alignBoneAxisToDirCS(mesh, RootBone, JointBone, upperDirCS, nil, poleCS, state)
	if ShoulderCompRot ~= nil then
		mesh:SetBoneRotationByName(RootBone, ShoulderCompRot, EBoneSpaces.ComponentSpace)
	end

	-- IMPORTANT: compute elbow AFTER applying shoulder.
	-- The joint's ComponentSpace basis changes when the parent rotates; using the pre-shoulder joint basis
	-- can leave the end bone significantly off even if the solver's OutEndWS hits the effector.
	local ElbowCompRot = alignBoneAxisToDirCS(mesh, JointBone, EndBone, lowerDirCS, axisJoint, poleCS, state)
		if ElbowCompRot ~= nil then
			--------------------------------------------------------------
			-- For the left arm Apply a 90° forearm roll (around the forearm tube axis in component space).
			-- This composes a bone-local rotation after the computed elbow rotation.
			if invertForearmRoll then
				local forearmRollDeg = -90.0
				if forearmRollDeg ~= 0 then
					-- Quaternion-based roll: create rotator from axis/angle, convert to quat, rotate up vector.
					local axis = SafeNormalize(lowerDirCS)
					if axis == nil or kismet_math_library:VSize(axis) < 0.0001 then
						axis = SafeNormalize(axisVectorFromRotator(ElbowCompRot, "X")) or VEC_UNIT_Y
					end
					local forwardFromRot = SafeNormalize(kismet_math_library:GetForwardVector(ElbowCompRot))
					local upFromRot = SafeNormalize(kismet_math_library:GetUpVector(ElbowCompRot))
					if forwardFromRot ~= nil and upFromRot ~= nil and axis ~= nil then
						local deltaRot = kismet_math_library:RotatorFromAxisAndAngle(axis, forearmRollDeg)
						local quatDelta = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(deltaRot.Roll, deltaRot.Pitch, deltaRot.Yaw))
						local rotatedUp = SafeNormalize(kismet_math_library:Quat_RotateVector(quatDelta, upFromRot))
						local poleProj = SafeNormalize(kismet_math_library:ProjectVectorOnToPlane(rotatedUp, forwardFromRot))
						if poleProj ~= nil and kismet_math_library:VSize(poleProj) > 0.0001 then
							local recon = kismet_math_library:MakeRotFromXZ(forwardFromRot, poleProj)
							if recon ~= nil then ElbowCompRot = recon end
						end
					end
				end
			end
        --     end
        --     This one jitters. Maybe gimbal lock
        --     -- Apply any configured forearm roll to the final elbow rotation so runtime
        --     -- slider changes take immediate visual effect.
        --     -- Diagnostics & sanity checks (to find root cause of unstable roll)
        --     if forearmRollDeg ~= 0 then
        --         local rollAxis = lowerDirCS
        --         local rollAxisLen = (rollAxis ~= nil) and (kismet_math_library:VSize(rollAxis) or 0.0) or 0.0
        --         -- Fallback if axis is degenerate
        --         if rollAxis == nil or rollAxisLen < 0.0001 then
        --             rollAxis = axisVectorFromRotator(ElbowCompRot, "X") or VEC_UNIT_Y
        --         end
        --         -- Compose the roll after the elbow rotation so it behaves like a bone-local roll.
        --         local delta = kismet_math_library:RotatorFromAxisAndAngle(rollAxis, forearmRollDeg)
        --         -- apply delta
        --         ElbowCompRot = kismet_math_library:ComposeRotators(ElbowCompRot, delta)
        --     end
        -- end
        ------------------------------------------------------------------------

		mesh:SetBoneRotationByName(JointBone, ElbowCompRot, EBoneSpaces.ComponentSpace)
		-- Cache last lower-axis for next tick to improve stability if needed.
		if state then state.lastLowerDirCS = lowerDirCS; state.lastElbowCompRot = ElbowCompRot end
	end

	--------------------------------------------------------------
	-- 9. Apply controller rotation to hand/wrist bone
	--------------------------------------------------------------
	-- Convert the controller's world-space rotation into mesh component space,
	-- then stamp it directly onto the end bone so the wrist tracks the controller.
	if controllerRotWS ~= nil then
		local HandCompRot = kismet_math_library:InverseTransformRotation(compToWorld, controllerRotWS)
		if HandCompRot ~= nil then
			--print("HandCompRot before correction:", HandCompRot.Pitch, HandCompRot.Yaw, HandCompRot.Roll)
			-- Adjust if the wrist still looks wrong (try Roll=0/180, Pitch=0/180, Yaw=0/180).
            -- endBoneRotation is often 180 roll from left to right hand
			local finalHandCompRot = kismet_math_library:ComposeRotators(endBoneRotation, HandCompRot)
			mesh:SetBoneRotationByName(EndBone, finalHandCompRot, EBoneSpaces.ComponentSpace)
			if wristBone ~= "" then
                mesh:SetBoneRotationByName(wristBone, finalHandCompRot, EBoneSpaces.ComponentSpace)
            end

			--print("HandCompRot after correction:", HandCompRot.Pitch, HandCompRot.Yaw, HandCompRot.Roll)
			-- ElbowCompRot was just stamped onto JointBone — reuse it directly, no read-back needed.
			local lowerArmRotCS = ElbowCompRot

			-- Signed angle between elbow and hand around the forearm tube axis.
			--[[
				Why this is needed: The hand rolls but that roll cant be appled directly to the forearm because of Pitch/Yaw in the hand with respect to forearm which changes what roll means.
				If elbowUp == handUp (both pointing the same way, only differing by Roll) → Roll is the tube angle. Valid.
				The moment their forwards diverge (wrist pitched/yawed relative to elbow) → the Euler decomposition picks a different Pitch/Yaw/Roll split to represent the same physical rotation, and Roll absorbs some of the swing. It's no longer the tube angle.
				The atan(dot(axis, cross), dot(up,up)) is essentially computing the same thing as Roll would be in the locked case — but geometrically, so it remains correct regardless of what Pitch and Yaw are doing. The up-vector approach is just "what Roll means, without the assumption that Pitch and Yaw are zero."
			]]--
			local twistAngleDeg = math:computeSignedAngleAroundAxis_Rotators(lowerArmRotCS, finalHandCompRot, lowerDirCS)
			---------------------------------------------

			for _, entry in ipairs(twistBones) do
				if not entry._fname then entry._fname = uevrUtils.fname_from_string(entry.bone) end
				local boneFName = entry._fname
				local vecs = state.twistBoneVecs and state.twistBoneVecs[entry.bone]
				if vecs == nil or lowerArmRotCS == nil then break end

				-- Step 1: bring stored bone-local axes into current component space.
				-- GreaterGreater_VectorRotator(v_local, rot) = pure matrix multiply, no Euler decomposition.
				local xCS = kismet_math_library:GreaterGreater_VectorRotator(vecs.x, lowerArmRotCS)
				local zCS = kismet_math_library:GreaterGreater_VectorRotator(vecs.z, lowerArmRotCS)

				-- Step 2: rotate both axes around the forearm tube axis by the fractional angle.
				local tubeRot = kismet_math_library:RotatorFromAxisAndAngle(lowerDirCS, twistAngleDeg * entry.fraction)
				xCS = kismet_math_library:GreaterGreater_VectorRotator(xCS, tubeRot)
				zCS = kismet_math_library:GreaterGreater_VectorRotator(zCS, tubeRot)

				-- Step 3: reconstruct CS rotation from two vectors — no Euler composition at all.
				local finalCS = kismet_math_library:MakeRotFromXZ(xCS, zCS)
				mesh:SetBoneRotationByName(boneFName, finalCS, EBoneSpaces.ComponentSpace)
			end
		end

	end
end
IK.solveTwoBone = uevrUtils.profiler:wrap("solveTwoBone", IK.solveTwoBone)

-- Print all bone transforms in bone-local space for a mesh/component
function M.printMeshBoneTransforms(mesh, boneSpace)
	if mesh == nil or uevrUtils.validate_object(mesh) == nil then
		M.print("printMeshBoneTransforms: mesh is nil or invalid", LogLevel.Warning)
		return
	end
	boneSpace = boneSpace or 0
	local boneNames = uevrUtils.getBoneNames(mesh)
	for i, bname in ipairs(boneNames) do
		local f = uevrUtils.fname_from_string(bname)
		local localRot, localLoc, localScale = nil, nil, nil
		-- animation.getBoneSpaceLocalTransform returns (rot, loc, scale, parentTransform)
		if animation and animation.getBoneSpaceLocalTransform then
			localRot, localLoc, localScale = animation.getBoneSpaceLocalTransform(mesh, f, boneSpace)
		end
		if localRot == nil then
			-- fallback: compute via component transforms
			local parentTransform = mesh:GetBoneTransformByName(mesh:GetParentBone(f), boneSpace)
			local wTransform = mesh:GetBoneTransformByName(f, boneSpace)
			local localTransform = kismet_math_library:ComposeTransforms(wTransform, kismet_math_library:InvertTransform(parentTransform))
			localLoc = uevrUtils.vector(0,0,0)
			local localRotTmp = uevrUtils.rotator(0,0,0)
			local localScaleTmp = uevrUtils.vector(0,0,0)
			kismet_math_library:BreakTransform(localTransform, localLoc, localRotTmp, localScaleTmp)
			localRot = kismet_math_library:TransformRotation(localTransform, uevrUtils.rotator(0,0,0))
			localScale = localScaleTmp or wTransform.Scale3D
		end

		if localLoc ~= nil and localRot ~= nil then
			M.print(string.format("%s: Loc=(%.3f,%.3f,%.3f) Rot=(%.3f,%.3f,%.3f) Scale=(%.3f,%.3f,%.3f)",
				bname,
				(localLoc.X or localLoc[1] or 0), (localLoc.Y or localLoc[2] or 0), (localLoc.Z or localLoc[3] or 0),
				(localRot.Pitch or localRot.pitch or 0), (localRot.Yaw or localRot.yaw or 0), (localRot.Roll or localRot.roll or 0),
				(localScale and (localScale.X or localScale[1] or 0) or 0), (localScale and (localScale.Y or localScale[2] or 0) or 0), (localScale and (localScale.Z or localScale[3] or 0) or 0)
			), LogLevel.Info)
		else
			M.print(tostring(bname) .. ": <could not resolve local transform>", LogLevel.Warning)
		end
	end
end

function IK:printMeshBoneTransforms(solverID)
    local solverParams = paramManager:get(solverID)
    if solverParams == nil then
        M.print("printMeshBoneTransforms: no solver params for solverID " .. tostring(solverID), LogLevel.Warning)
        return
    end
    local mesh = solverParams.mesh == "Custom" and getCustomIKComponent(solverID) or uevrUtils.getObjectFromDescriptor(solverParams.mesh, false)
    if mesh == nil then
        M.print("printMeshBoneTransforms: could not resolve mesh for solverID " .. tostring(solverID), LogLevel.Warning)
        return
    end
    M.printMeshBoneTransforms(mesh, EBoneSpaces.ComponentSpace)
end

function IK:setActive(solverId, value)
    if value == nil then value = true end
    self.activeSolvers = self.activeSolvers or {}
    self.activeSolvers[solverId] = nil
    if value == true then
        local solverParams = paramManager:get(solverId)
        if solverParams ~= nil then
            local mesh = solverParams.mesh == "Custom" and getCustomIKComponent(solverId) or uevrUtils.getObjectFromDescriptor(solverParams.mesh, false)
            local parentBones = getAncestorBones(mesh, solverParams["end_bone"], 3) -- ensure bone ancestry cache is built
            local controller = nil
            if solverParams["end_control_type"] == M.ControllerType.LEFT_CONTROLLER then
                controller = controllers.getController(Handed.Left)
            else
                controller = controllers.getController(Handed.Right)
            end
            if mesh == nil or mesh.GetBoneLocationByName == nil or controller == nil or #parentBones ~= 3 then
                M.print("setActive: Missing or invalid mesh or controller or correct bones for solverId " .. tostring(solverId), LogLevel.Warning)
                return
            end
            self.activeSolvers[solverId] = {
                mesh = mesh,
                rootBone = parentBones[#parentBones],
                jointBone = parentBones[#parentBones - 1],
                endBone = solverParams["end_bone"],
                wristBone = solverParams["wrist_bone"] or "",
                controller = controller,
                hand = solverParams["end_control_type"],
                handOffset = solverParams["end_bone_offset"] and uevrUtils.vector(solverParams["end_bone_offset"]) or uevrUtils.vector(0,0,0),
                endBoneRotation = solverParams["end_bone_rotation"] and uevrUtils.rotator(solverParams["end_bone_rotation"]) or uevrUtils.rotator(0,0,0),
                allowWristAffectsElbow = solverParams["allow_wrist_affects_elbow"] or false,
                allowStretch = solverParams["allow_stretch"] or false,
                startStretchRatio = solverParams["start_stretch_ratio"] or 0.0,
                maxStretchScale = solverParams["max_stretch_scale"] or 0.0,
                twistBones = solverParams["twist_bones"] or {},
                invertForearmRoll = solverParams["invert_forearm_roll"] or false,
				state = newIKState(),
            }

			local active = self.activeSolvers[solverId]
			local state = active and active.state or nil
			if state ~= nil then
				state.twistBoneVecs = {}
				local lowerArmRot = mesh:GetBoneRotationByName(active.jointBone, EBoneSpaces.ComponentSpace)
				local twistBones = active.twistBones
				if lowerArmRot ~= nil and twistBones ~= nil then
					for _, entry in ipairs(twistBones) do
						local boneName = entry and entry.bone
						if boneName ~= nil then
							local boneCS = mesh:GetBoneRotationByName(boneName, EBoneSpaces.ComponentSpace)
							if boneCS ~= nil then
								state.twistBoneVecs[boneName] = {
									x = kismet_math_library:LessLess_VectorRotator(kismet_math_library:GetForwardVector(boneCS), lowerArmRot),
									z = kismet_math_library:LessLess_VectorRotator(kismet_math_library:GetUpVector(boneCS),    lowerArmRot),
								}
							end
						end
					end
				end
			end

            local initialTransforms = {}
            local boneNames = uevrUtils.getBoneNames(mesh)
            for i, boneName in ipairs(boneNames) do
                local f = uevrUtils.fname_from_string(boneName)
                table.insert(initialTransforms, {boneName = boneName, transform = mesh:GetBoneTransformByName(f, EBoneSpaces.ComponentSpace)})
            end
            active.initialTransforms = initialTransforms

			-- -- Capture ancestor bones (shoulder->root) local transforms for later use.
			-- -- Get full ancestor chain from end bone and use indices 4..end as requested.
			-- local ancestors = getAncestorBones(mesh, solverParams["end_bone"], 100)
			-- local ancestorLocalTransforms = {}
			-- if ancestors ~= nil and #ancestors >= 4 then
			-- 	for idx = 4, #ancestors do
			-- 		local boneName = ancestors[idx]
            --         if boneName == "None" then break end
			-- 		if boneName ~= nil then
			-- 			local f = uevrUtils.fname_from_string(boneName)
            --             ancestorLocalTransforms[boneName] = mesh:GetBoneTransformByName(f, EBoneSpaces.ComponentSpace)
			-- 		end
			-- 	end
			-- end
			-- active.ancestorLocalTransforms = ancestorLocalTransforms
        end
    end
end

-- function on_pre_engine_tick(engine, delta)
-- 	if meshCopy ~= nil then
-- 		SolveVRArmIK(
-- 			meshCopy,               -- UPoseableMeshComponent
-- 			"r_UpperArm_JNT",           -- e.g. "UpperArm_L"
-- 			"r_LowerArm_JNT",          -- e.g. "LowerArm_L"
-- 			"r_Hand_JNT",            -- e.g. "Hand_L"
-- 			"r_wrist_JNT",
-- 			controllers.getControllerLocation(Handed.Right),       -- VR controller world location (FVector)
-- 			controllers.getControllerRotation(Handed.Right),       -- VR controller world rotation (FRotator)
-- 			uevrUtils.vector(-8,0,0),         -- Offset from controller → hand bone (controller-local)
-- 			false,       -- AllowStretch (rotation-only solve cannot magically extend the arm)
-- 			0.0,  -- float
-- 			0.0,     -- float,
-- 			{  -- TwistBones: distribute wrist roll across the three forearm pronation bones
-- 				{ bone = "r_lowerTwistUp_JNT",  fraction = 0.25 }, -- nearest elbow
-- 				{ bone = "r_lowerTwistMid_JNT", fraction = 0.50 },
-- 				{ bone = "r_lowerTwistLow_JNT", fraction = 0.75 }, -- nearest wrist
-- 				--{ bone = "r_wrist_JNT", fraction = 0.90 }, -- nearest wrist
-- 				-- r_wrist_JNT is a flexion bone (rest rotation differs ~90°) — not a twist bone
-- 			}

-- 		)
-- 	end
-- end

function M.init(m_isDeveloperMode, logLevel)
    if logLevel ~= nil then
        M.setLogLevel(logLevel)
    end
    if m_isDeveloperMode == nil and uevrUtils.getDeveloperMode() ~= nil then
        m_isDeveloperMode = uevrUtils.getDeveloperMode()
    end

    if m_isDeveloperMode then
        ikConfigDev = require("libs/config/ik_config_dev")
        ikConfigDev.init(paramManager)
    else
    end

    isDeveloperMode = m_isDeveloperMode
end

-- function M.updateAnimationFromMesh(hand, mesh, componentName)
-- 	--print("Updating animation from mesh", hand, mesh:get_full_name(), componentName)
-- 	if mesh ~= nil then
-- 		componentName = getComponentName(componentName)
-- 		if componentName == nil or componentName == "" or handDefinitions[componentName] == nil then
-- 			M.print("Could not update Animation From Mesh because component is undefined")
-- 		else
-- 			local component = M.getHandComponent(hand, componentName)
-- 			local handStr = hand == Handed.Left and "Left" or "Right"
-- 			local definition = handDefinitions[componentName][handStr]
-- 			if definition ~= nil then
-- 				local jointName = definition["Name"]
-- 				if jointName ~= nil and jointName ~= "" then
-- 					local success, response = pcall(function()
-- 						component:CopyPoseFromSkeletalComponent(mesh)
-- 						-- --component:SetLeaderPoseComponent(mesh, true)
-- 						-- local location = getValidVector(definition, "Location", {0,0,0})
-- 						-- local rotation = getValidRotator(definition, "Rotation", {0,0,0})
-- 						-- local scale = getValidVector(definition, "Scale", {1,1,1})
-- 						-- local taperOffset = getValidVector(definition, "TaperOffset", {0,0,0})
-- 						-- --When an animation is applied, every bone in the entire skeleton is moved, so we need to reapply the transform from wrist to root
-- 						-- local optimizeAnimationFromMesh = handDefinitions[componentName]["OptimizeAnimations"] ~= false
-- 						-- local optimizationRootBone = definition["OptimizeAnimationsRootBone"]
-- 						-- animation.transformBoneToRoot(component, jointName, location, rotation, scale, taperOffset, optimizeAnimationFromMesh, optimizationRootBone)
-- 						-- --component:SetLeaderPoseComponent(nil, false)
-- 					end)
-- 					if success == false then
-- 						M.print("[hands] " .. response, LogLevel.Error)
-- 					end
-- 				end
-- 			end
-- 		end
-- 	end
-- end

uevrUtils.registerUEVRCallback("on_accessory_attach", function(handed, parentAttachment, socketName, attachType, loc, rot)
	accessoryStatus = accessoryStatus or {}
    accessoryStatus[handed] = {
        parentAttachment = parentAttachment,
        socketName = socketName,
        attachType = attachType,
        loc = loc,
        rot = rot,
    }
end)

uevrUtils.registerUEVRCallback("on_accessory_detach", function(handed)
	accessoryStatus = accessoryStatus or {}
    accessoryStatus[handed] = nil
end)

uevrUtils.registerUEVRCallback("on_accessory_animation", function(handed, anim)

end)

return M
local uevrUtils = require("libs/uevr_utils")
local paramModule = require("libs/core/params")
local controllers = require("libs/controllers")
--local animation = require("libs/animation") --used for debugging only
require("libs/accessories")
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
local gunstockRotation = uevrUtils.rotator(0,0,0)
local gunstockOffsetsEnabled = false
function M.setGunstockOffsetsEnabled(val)
	gunstockOffsetsEnabled = val
end

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

local function ProjectVectorOnToPlane(vec, planeNormal)
	if kismet_math_library.ProjectVectorOnToPlane ~= nil then
        return kismet_math_library:ProjectVectorOnToPlane(vec, planeNormal)
    else
        if vec == nil then return uevrUtils.vector(0,0,0) end
			if planeNormal == nil then return vec end

			-- Prefer engine helpers if present
			if kismet_math_library.Dot_VectorVector and kismet_math_library.Multiply_VectorFloat and kismet_math_library.Subtract_VectorVector then
				local dotVN = kismet_math_library:Dot_VectorVector(vec, planeNormal) or 0.0
				local denom = kismet_math_library:Dot_VectorVector(planeNormal, planeNormal) or 0.0
				if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
				local scale = dotVN / denom
				local comp = kismet_math_library:Multiply_VectorFloat(planeNormal, scale)
				return kismet_math_library:Subtract_VectorVector(vec, comp)
			end

			-- Fallback: plain numeric vectors (supports {X,Y,Z} or array)
			local vx = vec.X or vec[1] or 0
			local vy = vec.Y or vec[2] or 0
			local vz = vec.Z or vec[3] or 0
			local nx = planeNormal.X or planeNormal[1] or 0
			local ny = planeNormal.Y or planeNormal[2] or 0
			local nz = planeNormal.Z or planeNormal[3] or 0
			local dotVN = vx*nx + vy*ny + vz*nz
			local denom = nx*nx + ny*ny + nz*nz
			if denom <= 1e-8 then return uevrUtils.vector(0,0,0) end
			local s = dotVN / denom
			return uevrUtils.vector(vx - nx*s, vy - ny*s, vz - nz*s)
	end
end

local ikConfigDev = nil
local parametersFileName = "ik_parameters"
local parameters = {
	mesh = "",
    animation_mesh = "",
    mesh_location_offset = uevrUtils.vector(0,0,0),
    mesh_rotation_offset = uevrUtils.rotator(0,0,0),
    animation_location_offset = uevrUtils.vector(0,0,0),
    animation_rotation_offset = uevrUtils.rotator(0,0,0),
	solvers = {},
}
local paramManager = paramModule.new(parametersFileName, parameters, true)
paramManager:load(true)

local function setParameter(key, value, persist)
	local activeProfile = paramManager:getActiveProfile()
	if activeProfile == nil then return end
	if type(key) == "table" then
		local fullKey = {activeProfile}
		for _, k in ipairs(key) do
			table.insert(fullKey, k)
		end
		return paramManager:set(fullKey, value, persist)
	end
	return paramManager:set({activeProfile, key}, value, persist)
end

local function saveParameter(key, value, persist)
	--paramManager:set(key, value, persist)
    setParameter(key, value, persist)
end

local function getParameter(key)
    return paramManager:get(key)
end

local Rig = {}
Rig.__index = Rig

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
		rigId = options.rigId or paramManager:getActiveProfile(),
		orderedSolvers = nil,
		solverOrderDirty = true,

    }, Rig)

    local paramUpdateMonitor = doOnce(function()
        uevrUtils.registerUEVRCallback("on_ik_config_param_change", function(key, value, persist)
            --live update of ui config changes
			local activeRigId = paramManager:getActiveProfile()
			if self.rigId ~= nil and activeRigId ~= nil and self.rigId == activeRigId then
			    self:setConfigParameter(key, value, persist)
            end
        end)
    end, Once.EVER)
    paramUpdateMonitor()

    self:create() -- auto-create component
    return self
end

-- allow a full rig table to be defined externally and set all parameters at once
-- TODO vector params are currently not being reflected in the json
function Rig:setParameters(params, persist)
	if type(params) ~= "table" then
		return
	end

	local rigId = self.rigId or paramManager:getActiveProfile() or "default"

	-- New schema: single rig payload passed directly.
    if persist then
        paramManager:createProfile(rigId, params.label or "Rig")
        paramManager:setActiveProfile(rigId)
    end
    for key, value in pairs(params) do
        if key ~= "label" then
            paramManager:set({rigId, key}, value, persist)
        end
    end

end

local function getRigParams(rigId)
	if rigId == nil then return nil end
	return paramManager:get(rigId)
end

local function getSolverParams(rigId, solverId)
	if rigId == nil or solverId == nil then return nil end
	return paramManager:get({rigId, "solvers", solverId})
end

local function isRigLevelParam(paramName)
	return paramName == "mesh"
		or paramName == "mesh_location_offset"
		or paramName == "mesh_rotation_offset"
		or paramName == "animation_mesh"
		or paramName == "animation_location_offset"
		or paramName == "animation_rotation_offset"
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

function Rig:setRigParameter(paramName, value)
	if self.activeSolvers == nil then return end

	if paramName == "mesh" then
		local mesh = nil
		if value == "Custom" then
			if getCustomIKComponent ~= nil then
				mesh = getCustomIKComponent(self.rigId)
			end
		else
			mesh = uevrUtils.getObjectFromDescriptor(value, false)
		end
		if mesh ~= nil then
			self.mesh = mesh
			for solverId, active in pairs(self.activeSolvers) do
				active.mesh = mesh
				if active.endBone ~= nil and active.endBone ~= "" then
					local parentBones = getAncestorBones(mesh, active.endBone, 3)
					if #parentBones == 3 then
						if active.startBone == nil or active.startBone == "" then
							active.startBone = parentBones[#parentBones]
						end
						if active.jointBone == nil or active.jointBone == "" then
							active.jointBone = parentBones[#parentBones - 1]
						end
					end
				end
				self:initializeSolverState(active)
			end
		end
		return
	end

    if paramName == "mesh_location_offset" then
		local offset = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		--get this rigs mesh and set its relative location
        if self.mesh ~= nil then
            self.mesh.RelativeLocation = offset
        end
		return
	end

    if paramName == "mesh_rotation_offset" then
		local offset = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		--get this rigs mesh and set its relative rotation
        if self.mesh ~= nil then
            self.mesh.RelativeRotation = offset
        end
		return
	end

	if paramName == "animation_mesh" then
		local animationMesh = nil
		if value == "Custom" then
			if getCustomAnimationIKComponent ~= nil then
				animationMesh = getCustomAnimationIKComponent(self.rigId)
			end
		else
			animationMesh = uevrUtils.getObjectFromDescriptor(value, false)
		end
		self.animationMesh = animationMesh
		-- for _, active in pairs(self.activeSolvers) do
		-- 	active.animationMesh = animationMesh
		-- end
		return
	end

	if paramName == "animation_location_offset" then
		local offset = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		self.animationLocationOffset = offset
		-- for _, active in pairs(self.activeSolvers) do
		-- 	active.animationLocationOffset = offset
		-- end
		return
	end

	if paramName == "animation_rotation_offset" then
		local offset = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		self.animationRotationOffset = offset
		-- for _, active in pairs(self.activeSolvers) do
		-- 	active.animationRotationOffset = offset
		-- end
	end
end

local keyMap = {
	solver_type = "solverType",
    end_bone = "endBone",
	start_bone = "startBone",
	joint_bone = "jointBone",
    wrist_bone = "wristBone",
    end_bone_offset = "handOffset",
    end_bone_rotation = "endBoneRotation",
    allow_wrist_affects_elbow = "allowWristAffectsElbow",
    allow_stretch = "allowStretch",
    start_stretch_ratio = "startStretchRatio",
    max_stretch_scale = "maxStretchScale",
    end_control_type = "hand",
    twist_bones = "twistBones",
--    invert_forearm_roll = "invertForearmRoll",
	sort_order = "sortOrder",
}
function Rig:setSolverParameter(solverId, paramName, value)
	local active = self.activeSolvers and self.activeSolvers[solverId]
	if active == nil then return end

	if paramName == "end_bone" then
		local mesh = active.mesh
		local jointBone = active.jointBone or ""
		local startBone = active.startBone or ""
		if mesh ~= nil and jointBone == "" and startBone == "" then
			local parentBones = getAncestorBones(mesh, value, 3)
			if #parentBones == 3 then
				active.startBone = parentBones[#parentBones]
				active.jointBone = parentBones[#parentBones - 1]
			end
		end
	elseif paramName == "end_control_type" then
		local controller = nil
		if value == M.ControllerType.LEFT_CONTROLLER then
			controller = controllers.getController(Handed.Left)
		else
			controller = controllers.getController(Handed.Right)
		end
		active.controller = controller
	end

	local runtimeKey = keyMap[paramName]
	if runtimeKey ~= nil then
		if runtimeKey == "handOffset" then
			active[runtimeKey] = value and uevrUtils.vector(value) or uevrUtils.vector(0,0,0)
		elseif runtimeKey == "endBoneRotation" then
			active[runtimeKey] = value and uevrUtils.rotator(value) or uevrUtils.rotator(0,0,0)
		else
			active[runtimeKey] = value
		end
	end

	if paramName == "sort_order" then
		self.solverOrderDirty = true
	end

	if paramName == "twist_bones" or paramName == "joint_bone" or paramName == "start_bone" then
		self:initializeSolverState(active)
	end
end

function Rig:setConfigParameter(key, value, persist)
	if type(key) == "table" then
		saveParameter(key, value, persist)
		if key[1] == "solvers" and key[2] ~= nil and key[3] ~= nil then
			self:setSolverParameter(key[2], key[3], value)
			return
		end
		if key[1] ~= nil then
			self:setRigParameter(key[1], value)
		end
		return
	end

	if isRigLevelParam(key) then
		saveParameter(key, value, persist)
		self:setRigParameter(key, value)
		return
	end

	local defaultSolverId = self.defaultSolverId
	if defaultSolverId == nil then
		for solverId, _ in pairs(self.activeSolvers or {}) do
			defaultSolverId = solverId
			break
		end
	end
	if defaultSolverId ~= nil then
		saveParameter({"solvers", defaultSolverId, key}, value, persist)
		self:setSolverParameter(defaultSolverId, key, value)
	end
end


local function executeIsAnimatingFromMeshCallback(...)
	return uevrUtils.executeUEVRCallbacksWithPriorityBooleanResult("is_hands_animating_from_mesh", table.unpack({...}))
end

function Rig:rebuildOrderedSolversIfNeeded()
	if self.activeSolvers == nil then
		self.orderedSolvers = {}
		self.solverOrderDirty = false
		return
	end
	if self.solverOrderDirty ~= true and self.orderedSolvers ~= nil then
		return
	end

	local ordered = {}
	for solverId, activeParams in pairs(self.activeSolvers) do
		table.insert(ordered, { id = solverId, params = activeParams, order = (activeParams and activeParams.sortOrder) or 0 })
	end
	table.sort(ordered, function(a, b)
		if a.order == b.order then
			return tostring(a.id) < tostring(b.id)
		end
		return a.order < b.order
	end)

	self.orderedSolvers = ordered
	self.solverOrderDirty = false
end

function Rig:setInitialTransform()
    local mesh = self.mesh
    local transforms = self.initialTransforms
    if mesh ~= nil and transforms and type(transforms) == "table" then
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
    end
end

function Rig:animateFromMesh()
    local didAnimate = false
    local success, response = pcall(function()
        self.mesh:CopyPoseFromSkeletalComponent(self.animationMesh)
        didAnimate = true
        self.wasAnimating = true
    end)
    if success == false then
        M.print(response, LogLevel.Error)
    end

    -- In some games the animation moves the skeleton by an offset (probably so they are more visible in the 2D screen)
    -- but we dont want this offset in VR so we correct it here
    if self.animationRotationOffset.Pitch ~= 0 or self.animationRotationOffset.Yaw ~= 0 or self.animationRotationOffset.Roll ~= 0 or self.animationLocationOffset.X ~= 0 or self.animationLocationOffset.Y ~= 0 or self.animationLocationOffset.Z ~= 0 then
        local rootName = uevrUtils.fname_from_string(self.rootBone)
        --adding rotators would normally be bad but since its just an offset determined by UI it works here
        local rot = self.mesh:GetBoneRotationByName(rootName, EBoneSpaces.ComponentSpace) + self.animationRotationOffset
        --local loc = activeParams.mesh:GetBoneLocationByName(rootName, EBoneSpaces.ComponentSpace) + activeParams.animationLocationOffset -- this doesnt work, the get returns world space
        -- base location of root should be 0,0,0 in component space so this should work as an offset
        local loc = self.animationLocationOffset
        self.mesh:SetBoneRotationByName(rootName, rot, EBoneSpaces.ComponentSpace)
        self.mesh:SetBoneLocationByName(rootName, loc, EBoneSpaces.ComponentSpace)
    end

    return didAnimate
end

function Rig:create()
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
	self.orderedSolvers = {}
	self.solverOrderDirty = true
	-- Register tick callback
	local tickFn = function(engine, delta)
        if self.activeSolvers ~= nil then
            local isLeftAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Left))
		    local isRightAnimating = select(1, executeIsAnimatingFromMeshCallback(Handed.Right))
            local didAnimate = false
            if (isLeftAnimating or isRightAnimating) then
                didAnimate = self:animateFromMesh()--uevrUtils.getValid(pawn, {"FPVMesh"}))
            end
            if didAnimate == false then
                if self.wasAnimating then
                    self:setInitialTransform()
                    self.wasAnimating = false
                end

                self:rebuildOrderedSolversIfNeeded()
				for _, solverEntry in ipairs(self.orderedSolvers or {}) do
					local solverId = solverEntry.id
					local activeParams = solverEntry.params
                    if activeParams then
						if activeParams.solverType == M.SolverType.TWO_BONE then
							self:solveTwoBone(activeParams)
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

local function composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)
	if state ~= nil and state.composeOrderSwing ~= nil then
		return state.composeOrderSwing
			and kismet_math_library:ComposeRotators(currentRot, deltaSwing)
			or kismet_math_library:ComposeRotators(deltaSwing, currentRot)
	end

	local cand1 = kismet_math_library:ComposeRotators(deltaSwing, currentRot)
	local cand2 = kismet_math_library:ComposeRotators(currentRot, deltaSwing)
	if state ~= nil and state.composeOrderSwing == nil then
		local localDir = SafeNormalize(kismet_math_library:LessLess_VectorRotator(currentDir, currentRot))
		local function score(rot)
			if rot == nil then return -1 end
			local a = SafeNormalize(kismet_math_library:GreaterGreater_VectorRotator(localDir, rot))
			return kismet_math_library:Dot_VectorVector(a, desiredDir) or -1
		end
		state.composeOrderSwing = score(cand2) > score(cand1)
	end
	return (state ~= nil and state.composeOrderSwing) and cand2 or cand1
end

local function composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
	if state ~= nil and state.composeOrderTwist ~= nil then
		return state.composeOrderTwist
			and kismet_math_library:ComposeRotators(swingRot, deltaTwist)
			or kismet_math_library:ComposeRotators(deltaTwist, swingRot)
	end

	local t1 = kismet_math_library:ComposeRotators(deltaTwist, swingRot)
	local t2 = kismet_math_library:ComposeRotators(swingRot, deltaTwist)
	if state ~= nil and state.composeOrderTwist == nil then
		local function scorePole(rot)
			local p = axisVectorFromRotator(rot, poleAxisChar)
			if p == nil then return -1 end
			p = SafeNormalize(ProjectVectorOnToPlane(mulVec(p, poleAxisSign), desiredDir))
			return kismet_math_library:Dot_VectorVector(p, desiredPole) or -1
		end
		state.composeOrderTwist = scorePole(t2) > scorePole(t1)
	end
	return (state ~= nil and state.composeOrderTwist) and t2 or t1
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
	local swingRot = composeSwingWithCachedOrder(state, currentDir, currentRot, desiredDir, deltaSwing)

    return swingRot

    --This code may have been created during debugging but doesnt appear to be needed
    --because Invert Forearm Roll UI item doesnt appear to be needed
    --[[
	-- 3) Optional twist: align a pole axis in the plane orthogonal to desiredDir.
	local poleAxisChoice = axisChoice and axisChoice.pole or nil
	if poleAxisChoice == nil then
		return swingRot
	end
	local poleAxisChar = poleAxisChoice.axis
	local poleAxisSign = poleAxisChoice.sign or 1
    --poleAxisSign = -poleAxisSign

	local desiredPole = SafeNormalize(ProjectVectorOnToPlane(poleCS, desiredDir))
	if desiredPole == nil or kismet_math_library:VSize(desiredPole) < 0.0001 then return swingRot end

	local poleAxisVec = axisVectorFromRotator(swingRot, poleAxisChar)
	if poleAxisVec == nil then return swingRot end
	local currentPole = SafeNormalize(ProjectVectorOnToPlane(mulVec(poleAxisVec, poleAxisSign), desiredDir))
	if currentPole == nil or kismet_math_library:VSize(currentPole) < 0.0001 then return swingRot end

	local twistAngleDeg = signedAngleDegAroundAxis(currentPole, desiredPole, desiredDir)
	if twistAngleDeg == nil or math.abs(twistAngleDeg) < IK_MIN_TWIST_DEG then return swingRot end

	local deltaTwist = kismet_math_library:RotatorFromAxisAndAngle(desiredDir, twistAngleDeg)
	return composeTwistWithCachedOrder(state, swingRot, deltaTwist, desiredDir, desiredPole, poleAxisChar, poleAxisSign)
    ]]--
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


local function getTargetLocationAndRotation(hand, controller)
    local loc = nil
    local rot = nil
    if accessoryStatus[hand] == nil then
        loc = controller and controller:K2_GetComponentLocation() or nil
        rot = controller and controller:K2_GetComponentRotation() or nil
        --TODO hard coded for right handed weapon holding. Add left support
        if rot ~= nil and hand == Handed.Right and gunstockOffsetsEnabled == true then
            --rotate the worldspace controller rotation but the gunstock local space offset
            rot = kismet_math_library:ComposeRotators(gunstockRotation, rot)
        end
    else
        local status = accessoryStatus[hand]
        if status.parentAttachment ~= nil then
            if status.parentAttachment.GetSocketLocation == nil then
                print("IK accessory parent attachment has no GetSocketLocation:", status.parentAttachment:get_full_name())
            else
                loc = status.parentAttachment:GetSocketLocation(uevrUtils.fname_from_string(status.socketName or ""))
                rot = status.parentAttachment:GetSocketRotation(uevrUtils.fname_from_string(status.socketName or ""))
                if status.loc ~= nil and status.rot ~= nil then
                    local offsetPos = uevrUtils.vector(status.loc) or uevrUtils.vector(0,0,0)
                    local offsetRot = uevrUtils.rotator(status.rot) or uevrUtils.rotator(0,0,0)

                    loc = kismet_math_library:Add_VectorVector(loc, kismet_math_library:GreaterGreater_VectorRotator(offsetPos, rot))
                    rot = kismet_math_library:ComposeRotators(offsetRot, rot)
                end
            end
        end 
    end
    return loc, rot
end

function Rig:solveTwoBone(solverParams)
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
    local RootBone = solverParams.startBone
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
--   local invertForearmRoll = solverParams.invertForearmRoll
	local state = solverParams.state
	-- if state == nil then
	-- 	state = newIKState()
	-- 	solverParams.state = state
	-- end
    VEC_UNIT_Y = VEC_UNIT_Y_FORWARD--invertForearmRoll == true and VEC_UNIT_Y_INVERSE or VEC_UNIT_Y_FORWARD

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
	if uevrUtils.getValid(mesh) == nil or mesh.K2_GetComponentToWorld == nil then
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
		local poleCS = SafeNormalize(ProjectVectorOnToPlane(state.baselineElbowDirCS, reachCS))
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
				local upProj = (ctrlUpCS ~= nil) and SafeNormalize(ProjectVectorOnToPlane(ctrlUpCS, reachCS)) or nil
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
	-- if state.bonesKey == nil then state.bonesKey = JointBone .. "->" .. EndBone end
	-- local bonesKey = state.bonesKey
	-- if state.jointPoleAxisChoice == nil or state.jointPoleAxisForBones ~= bonesKey then
	-- 	local jointDir = getBoneDirCS(mesh, JointBone, EndBone)
	-- 	local jx, jy, jz = axisVectorsFromRot(mesh:GetBoneRotationByName(JointBone, EBoneSpaces.ComponentSpace))
	-- 	local jointLong = chooseBestAxis(jx, jy, jz, jointDir)
	-- 	state.jointPoleAxisChoice = chooseBestPoleAxis(jx, jy, jz, jointLong.axis, VEC_UNIT_Y)
	-- 	state.jointPoleAxisForBones = bonesKey
	-- end
	-- local axisJoint = { pole = state.jointPoleAxisChoice }

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
	local ElbowCompRot = alignBoneAxisToDirCS(mesh, JointBone, EndBone, lowerDirCS, nil, poleCS, state)
		if ElbowCompRot ~= nil then
			--------------------------------------------------------------
			-- For the left arm Apply a 90° forearm roll (around the forearm tube axis in component space).
			-- This composes a bone-local rotation after the computed elbow rotation.
			-- if invertForearmRoll then
			-- 	local forearmRollDeg = -90.0
			-- 	if forearmRollDeg ~= 0 then
			-- 		-- Quaternion-based roll: create rotator from axis/angle, convert to quat, rotate up vector.
			-- 		local axis = SafeNormalize(lowerDirCS)
			-- 		if axis == nil or kismet_math_library:VSize(axis) < 0.0001 then
			-- 			axis = SafeNormalize(axisVectorFromRotator(ElbowCompRot, "X")) or VEC_UNIT_Y
			-- 		end
			-- 		local forwardFromRot = SafeNormalize(kismet_math_library:GetForwardVector(ElbowCompRot))
			-- 		local upFromRot = SafeNormalize(kismet_math_library:GetUpVector(ElbowCompRot))
			-- 		if forwardFromRot ~= nil and upFromRot ~= nil and axis ~= nil then
			-- 			local deltaRot = kismet_math_library:RotatorFromAxisAndAngle(axis, forearmRollDeg)
			-- 			local quatDelta = kismet_math_library:Quat_MakeFromEuler(uevrUtils.vector(deltaRot.Roll, deltaRot.Pitch, deltaRot.Yaw))
			-- 			local rotatedUp = SafeNormalize(kismet_math_library:Quat_RotateVector(quatDelta, upFromRot))
			-- 			local poleProj = SafeNormalize(ProjectVectorOnToPlane(rotatedUp, forwardFromRot))
			-- 			if poleProj ~= nil and kismet_math_library:VSize(poleProj) > 0.0001 then
			-- 				local recon = kismet_math_library:MakeRotFromXZ(forwardFromRot, poleProj)
			-- 				if recon ~= nil then ElbowCompRot = recon end
			-- 			end
			-- 		end
			-- 	end
			-- end
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
				--if not entry._fname then entry._fname = uevrUtils.fname_from_string(entry.bone) end
				local boneFName = uevrUtils.fname_from_string(entry.bone)
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
Rig.solveTwoBone = uevrUtils.profiler:wrap("solveTwoBone", Rig.solveTwoBone)

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
		-- if animation and animation.getBoneSpaceLocalTransform then
		-- 	localRot, localLoc, localScale = animation.getBoneSpaceLocalTransform(mesh, f, boneSpace)
		-- end
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

function Rig:printMeshBoneTransforms(solverID)
	local active = self.activeSolvers and self.activeSolvers[solverID]
	if active == nil then
        M.print("printMeshBoneTransforms: no solver params for solverID " .. tostring(solverID), LogLevel.Warning)
        return
    end
	local mesh = active.mesh
    if mesh == nil then
        M.print("printMeshBoneTransforms: could not resolve mesh for solverID " .. tostring(solverID), LogLevel.Warning)
        return
    end
    M.printMeshBoneTransforms(mesh, EBoneSpaces.ComponentSpace)
end

function Rig:initializeSolverState(active)
	local state = active and active.state or nil
	local mesh = active and active.mesh or nil
	if state == nil or mesh == nil then return end

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

function Rig:setActive(solverId, value)
    if value == nil then value = true end
	if self.rigId == nil then
		self.rigId = paramManager:getActiveProfile()
	end
    self.activeSolvers = self.activeSolvers or {}
    self.solverOrderDirty = true
    self.activeSolvers[solverId] = nil
	if self.defaultSolverId == solverId then
		self.defaultSolverId = nil
	end
    if value == true then
		local rigParams = getRigParams(self.rigId)
		local solverParams = getSolverParams(self.rigId, solverId)
		if solverParams ~= nil and rigParams ~= nil then
			local mesh = self.mesh
			if mesh == nil then
				if rigParams.mesh == "Custom" then
					if getCustomIKComponent ~= nil then
						mesh = getCustomIKComponent(self.rigId)
					end
				else
					mesh = uevrUtils.getObjectFromDescriptor(rigParams.mesh, false)
				end
				self.mesh = mesh
			end
            if mesh == nil or mesh.GetBoneLocationByName == nil then
                M.print("setActive: Missing or invalid mesh " .. tostring(solverId), LogLevel.Warning)
                return
            end

            local parentBones = getAncestorBones(mesh, solverParams["end_bone"], 3) -- ensure bone ancestry cache is built
            if #parentBones ~= 3 then
                M.print("setActive: incorrect bones for solverId " .. tostring(solverId), LogLevel.Warning)
                return
            end

            local controller = nil
            if solverParams["end_control_type"] == M.ControllerType.LEFT_CONTROLLER then
                controller = controllers.getController(Handed.Left)
            else
                controller = controllers.getController(Handed.Right)
            end
            if controller == nil then
                M.print("setActive: missing controller for solverId " .. tostring(solverId), LogLevel.Warning)
                return
            end

			local animationMesh = self.animationMesh
			if animationMesh == nil then
				if rigParams.animation_mesh == "Custom" then
					if getCustomAnimationIKComponent ~= nil then
						animationMesh = getCustomAnimationIKComponent(self.rigId)
					end
				else
					animationMesh = uevrUtils.getObjectFromDescriptor(rigParams.animation_mesh, false)
				end
				self.animationMesh = animationMesh
            end

            --this just completely overrides control
            -- if mesh ~= nil and animationMesh ~= nil then
            --     mesh:SetMasterPoseComponent(animationMesh, true)
            -- end

			M.print("Using bones " .. solverParams["end_bone"] .. ", " ..  parentBones[#parentBones - 1] .. ", " .. parentBones[#parentBones] .. " for solverId " .. tostring(solverId), LogLevel.Info)

            self.activeSolvers[solverId] = {
                mesh = mesh,
                --animationMesh = animationMesh,
                startBone = solverParams["start_bone"] or parentBones[#parentBones], --upperarm
                jointBone = solverParams["joint_bone"] or parentBones[#parentBones - 1], --lowerarm
                endBone = solverParams["end_bone"], --hand
                wristBone = solverParams["wrist_bone"] or "",
                controller = controller,
                hand = solverParams["end_control_type"],
                solverType = solverParams["solver_type"] or solverParams["solver"] or M.SolverType.TWO_BONE,
                sortOrder = solverParams["sort_order"] or 0,
                handOffset = solverParams["end_bone_offset"] and uevrUtils.vector(solverParams["end_bone_offset"]) or uevrUtils.vector(0,0,0),
                endBoneRotation = solverParams["end_bone_rotation"] and uevrUtils.rotator(solverParams["end_bone_rotation"]) or uevrUtils.rotator(0,0,0),
                allowWristAffectsElbow = solverParams["allow_wrist_affects_elbow"] or false,
                allowStretch = solverParams["allow_stretch"] or false,
                startStretchRatio = solverParams["start_stretch_ratio"] or 0.0,
                maxStretchScale = solverParams["max_stretch_scale"] or 0.0,
                twistBones = solverParams["twist_bones"] or {},
                --invertForearmRoll = solverParams["invert_forearm_roll"] or false,
                --animationLocationOffset = rigParams["animation_location_offset"] and uevrUtils.vector(rigParams["animation_location_offset"]) or uevrUtils.vector(0,0,0),
				--animationRotationOffset = rigParams["animation_rotation_offset"] and uevrUtils.rotator(rigParams["animation_rotation_offset"]) or uevrUtils.rotator(0,0,0),
				state = newIKState(),
            }

            mesh.RelativeLocation = rigParams["mesh_location_offset"] and uevrUtils.vector(rigParams["mesh_location_offset"]) or uevrUtils.vector(0,0,0)
            mesh.RelativeRotation = rigParams["mesh_rotation_offset"] and uevrUtils.rotator(rigParams["mesh_rotation_offset"]) or uevrUtils.rotator(0,0,0)


			local active = self.activeSolvers[solverId]
			self:initializeSolverState(active)
			if self.defaultSolverId == nil then
				self.defaultSolverId = solverId
			end

            local initialTransforms = {}
            local boneNames = uevrUtils.getBoneNames(mesh)
            for i, boneName in ipairs(boneNames) do
                local f = uevrUtils.fname_from_string(boneName)
                table.insert(initialTransforms, {boneName = boneName, transform = mesh:GetBoneTransformByName(f, EBoneSpaces.ComponentSpace)})
            end
            self.initialTransforms = initialTransforms
            self.rootBone = mesh:GetBoneName(0):to_string()


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

function Rig:addSolver(solverId)
	self:setActive(solverId, true)
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

-- local createConfigMonitor = doOnce(function()
--     uevrUtils.registerUEVRCallback("on_ik_config_param_change", function(key, value, persist)
-- 		-- Persistence is handled by Rig:setConfigParameter for each active rig instance.
--     end)
-- end, Once.EVER)

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

        --createConfigMonitor()
    end

    isDeveloperMode = m_isDeveloperMode
end


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

uevrUtils.registerUEVRCallback("gunstock_transform_change", function(id, newLocation, newRotation, newOffhandLocationOffset)
    if gunstockOffsetsEnabled then
		gunstockRotation = newRotation
	end
end)

return M
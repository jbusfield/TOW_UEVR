local uevrUtils = require('libs/uevr_utils')
local configui = require('libs/configui')

local json = json

local M = {}

M.SolverType = {
    TWO_BONE = 1,
    ROTATION_ONLY = 2,
}

M.ControllerType = {
    LEFT_CONTROLLER = 0,
    RIGHT_CONTROLLER = 1,
}

local configFileName = "dev/ik_config_dev"
local configTabLabel = "IK Dev Config"
local widgetPrefix = "uevr_ik_"

local paramManager = nil
local configDefaults = {
    label = "",
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
}

local meshList = {}
local boneNames = {}

local helpText = "Developer IK configuration. Edit individual solver parameter sets per profile."

local function getConfigWidgets(m_paramManager)
    local hideLabels = true
	return spliceableInlineArray{
		expandArray(m_paramManager.getProfilePreConfigurationWidgets, widgetPrefix),
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "ik_tree",
			initialOpen = true,
			label = "IK Parameters"
		},
				{
					widgetType = "input_text",
					id = widgetPrefix .. "label",
					label = "Label",
					initialValue = "",
					width = 300,
                    isHidden = true
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "mesh_combo",
					label = "Mesh",
					selections = {"None"},
					initialValue = 1,
                    width = 263
				},
                { widgetType = "same_line" },
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "mesh_combo_show_children",
					label = "Show Children",
					initialValue = false
				},
				{
					widgetType = "input_text",
					id = widgetPrefix .. "mesh",
					label = "Mesh",
					initialValue = "",
                    isHidden = hideLabels
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "solver_type",
					label = "Solver Type",
					selections = {"Two Bone", "Rotation Only"},
					initialValue = 1,
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "end_control_type",
					label = "Hand",
					selections = {"Left", "Right"},
					initialValue = 2,
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "end_bone_combo",
					label = "Hand Bone",
					selections = {"None"},
					initialValue = 1,
				},
				{
					widgetType = "input_text",
					id = widgetPrefix .. "end_bone",
					label = "Hand Bone",
					initialValue = "",
                    isHidden = hideLabels
				},
				{
					widgetType = "drag_float3",
					id = widgetPrefix .. "end_bone_offset",
					label = "Hand Position",
					speed = 0.1,
					range = {-100, 100},
					initialValue = {0,0,0}
				},
				{
					widgetType = "drag_float3",
					id = widgetPrefix .. "end_bone_rotation",
					label = "Hand Rotation",
					speed = 1,
					range = {-360, 360},
					initialValue = {0,0,0}
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "wrist_bone_combo",
					label = "Wrist Bone",
					selections = {"None"},
					initialValue = 1,
				},
				{
					widgetType = "input_text",
					id = widgetPrefix .. "wrist_bone",
					label = "Wrist Bone",
					initialValue = "",
					width = 300,
                    isHidden = hideLabels
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "allow_wrist_affects_elbow",
					label = "Allow Wrist Affects Elbow",
					initialValue = false
				},
				{
					widgetType = "checkbox",
					id = widgetPrefix .. "allow_stretch",
					label = "Allow Stretch",
					initialValue = false
				},
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "start_stretch_ratio",
					label = "Start Stretch Ratio",
					speed = 0.01,
					range = {0, 1},
					initialValue = 0.0
				},
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "max_stretch_scale",
					label = "Max Stretch Scale",
					speed = 0.01,
					range = {0, 5},
					initialValue = 0.0
				},
				{ widgetType = "new_line" },
				{
					widgetType = "text",
					id = widgetPrefix .. "twist_header",
					label = "Lower Arm Twist Bones",
					wrapped = false
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "lower_twist_bone_1_combo",
					label = "Bone 1",
					selections = {"None"},
					initialValue = 1,
                    width = 200
				},
				{
					widgetType = "input_text",
					id = widgetPrefix .. "lower_twist_bone_1",
					label = "Bone 1",
					initialValue = "",
					width = 200,
                    isHidden = hideLabels
				},
                { widgetType = "same_line" },
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "lower_twist_bone_frac_1",
					label = "%",
					speed = 0.01,
					range = {0,1},
					initialValue = 0.25,
					width = 80
				},
				{
					widgetType = "combo",
					id = widgetPrefix .. "lower_twist_bone_2_combo",
					label = "Bone 2",
					selections = {"None"},
					initialValue = 1,
                    width = 200
				},
				{
					widgetType = "input_text",
					id = widgetPrefix .. "lower_twist_bone_2",
					label = "Bone 2",
					initialValue = "",
					width = 200,
                    isHidden = hideLabels
				},
                { widgetType = "same_line" },
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "lower_twist_bone_frac_2",
					label = "%",
					speed = 0.01,
					range = {0,1},
					initialValue = 0.5,
					width = 80
				},
                {
                    widgetType = "combo",
                    id = widgetPrefix .. "lower_twist_bone_3_combo",
                    label = "Bone 3",
                    selections = {"None"},
                    initialValue = 1,
                    width = 200
                },
				{
					widgetType = "input_text",
					id = widgetPrefix .. "lower_twist_bone_3",
					label = "Bone 3",
					initialValue = "",
					width = 200,
                    isHidden = hideLabels
				},
                { widgetType = "same_line" },
				{
					widgetType = "slider_float",
					id = widgetPrefix .. "lower_twist_bone_frac_3",
					label = "%",
					speed = 0.01,
					range = {0,1},
					initialValue = 0.75,
					width = 80
				},
		{
			widgetType = "tree_pop"
		},
		{ widgetType = "new_line" },
		expandArray(m_paramManager.getProfilePostConfigurationWidgets, widgetPrefix),
		{ widgetType = "new_line" },
		{
			widgetType = "tree_node",
			id = widgetPrefix .. "help_tree",
			initialOpen = false,
			label = "Help"
		},
			{
				widgetType = "text",
				id = widgetPrefix .. "help",
				label = helpText,
				wrapped = true
			},
		{
			widgetType = "tree_pop"
		},
	}
end

local function updateSetting(key, value)
    if key == "end_control_type" then
        value = value == 1 and M.ControllerType.LEFT_CONTROLLER or M.ControllerType.RIGHT_CONTROLLER
    end
	uevrUtils.executeUEVRCallbacks("on_ik_config_param_change", key, value, true)
end

local function setUIValue(key, value)
    configui.setValue(widgetPrefix .. key, value, true)
end

local function updateUI(params)
	for key, value in pairs(params or {}) do
        if key == "twist_bones" then
            for i = 1,3 do
                local twistBone = value[i] or {}
                setUIValue("lower_twist_bone_" .. i, twistBone.bone or "")
                setUIValue("lower_twist_bone_frac_" .. i, twistBone.fraction or 0.0)
            end
        elseif key == "end_control_type" then
            local selectedIndex = value == M.ControllerType.LEFT_CONTROLLER and 1 or 2
            configui.setValue(widgetPrefix .. key, selectedIndex, true)
        else
		    setUIValue(key, value)
        end
	end
end

function M.getConfigurationWidgets(options)
	return configui.applyOptionsToConfigWidgets(getConfigWidgets(paramManager), options)
end

function M.showConfiguration(saveFileName, options)
	local configDefinition = {
		{
			panelLabel = configTabLabel,
			saveFile = saveFileName,
			layout = spliceableInlineArray{
				expandArray(M.getConfigurationWidgets, options)
			}
		}
	}
    for paramName, param in ipairs(configDefaults) do
		configui.onCreateOrUpdate(widgetPrefix .. paramName, function(value)
			updateSetting(paramName, value)
		end)
	end
	configui.create(configDefinition)

end

local function setSelectedMesh(currentMeshName, noCallbacks)
	local selectedIndex = 1
	for i = 1, #meshList do
		if meshList[i] == currentMeshName then
			selectedIndex = i
			break
		end
	end
	configui.setValue(widgetPrefix .. "mesh_combo", selectedIndex, noCallbacks)
end

local function setMeshList(currentMeshName, noCallbacks)
    meshList = uevrUtils.getObjectPropertyDescriptors(pawn, "Pawn", "Class /Script/Engine.SkeletalMeshComponent", configui.getValue(widgetPrefix .. "mesh_combo_show_children"))
	table.insert(meshList, 1, "None")
	table.insert(meshList, "Custom")

	configui.setSelections(widgetPrefix .. "mesh_combo", meshList)
	setSelectedMesh(currentMeshName, noCallbacks)
end

local function setSelectedBone(comboWidgetID, valueWidgetID)
    configui.setSelections(widgetPrefix .. comboWidgetID, boneNames)

    local currentBoneName = configui.getValue(widgetPrefix .. valueWidgetID)
    local selectedIndex = 1
    for i = 1, #boneNames do
        if boneNames[i] == currentBoneName then
            selectedIndex = i
            break
        end
    end
    configui.setValue(widgetPrefix .. comboWidgetID, selectedIndex, true)
end

local function setBoneList()
    boneNames = {}
    local currentMesh = configui.getValue(widgetPrefix .. "mesh")
    if currentMesh == "None" or currentMesh == "" then
        configui.setSelections(widgetPrefix .. "end_bone_combo", {"None"})
        configui.setValue(widgetPrefix .. "end_bone_combo", 1)
        return
    end
    local mesh = nil
    if currentMesh == "Custom" then
        if getCustomIKComponent == nil then
--TODO this function is getting called too early need to investigate how to recover
            print("Error: getCustomIKComponent function not defined for custom IK mesh retrieval")
            return
        end
        local activeProfileID = paramManager and paramManager:getActiveProfile() or ""
        mesh = getCustomIKComponent(activeProfileID)
    else
        mesh = uevrUtils.getObjectFromDescriptor(configui.getValue(widgetPrefix .. "mesh"))
    end

    if mesh ~= nil then
		boneNames = uevrUtils.getBoneNames(mesh)
        table.insert(boneNames, 1, "None")

        configui.setSelections(widgetPrefix .. "end_bone_combo", boneNames)
        configui.setSelections(widgetPrefix .. "wrist_bone_combo", boneNames)
        configui.setSelections(widgetPrefix .. "lower_twist_bone_1_combo", boneNames)
        configui.setSelections(widgetPrefix .. "lower_twist_bone_2_combo", boneNames)
        configui.setSelections(widgetPrefix .. "lower_twist_bone_3_combo", boneNames)

        setSelectedBone("end_bone_combo", "end_bone")
        setSelectedBone("wrist_bone_combo", "wrist_bone")
        setSelectedBone("lower_twist_bone_1_combo", "lower_twist_bone_1")
        setSelectedBone("lower_twist_bone_2_combo", "lower_twist_bone_2")
        setSelectedBone("lower_twist_bone_3_combo", "lower_twist_bone_3")
    end
end

function M.init(m_paramManager)
	configDefaults = m_paramManager and m_paramManager:getAllActiveProfileParams() or {}
	paramManager = m_paramManager
    M.showConfiguration(configFileName)

	paramManager:initProfileHandler(widgetPrefix, function(profileParams)
		updateUI(profileParams)
        setMeshList(profileParams["mesh"], true)
        setBoneList()
	end)
end

uevrUtils.registerUEVRCallback("on_ik_config_param_change", function(key, value)
	setUIValue(key, value)
end)

configui.onCreateOrUpdate(widgetPrefix .. "mesh_combo_show_children", function(value)
    setMeshList(configui.getValue(widgetPrefix .. "mesh"), true)
end)

configui.onUpdate(widgetPrefix .. "mesh_combo", function(value)
    updateSetting("mesh", meshList[value] == "None" and "" or meshList[value])
    setBoneList()
end)

configui.onUpdate(widgetPrefix .. "end_bone_combo", function(value)
    updateSetting("end_bone", boneNames[value] == "None" and "" or boneNames[value])
end)

configui.onUpdate(widgetPrefix .. "wrist_bone_combo", function(value)
    updateSetting("wrist_bone", boneNames[value] == "None" and "" or boneNames[value])
end)

local function updateTwistBones()
    local twistBones = {}
    for i = 1,3 do
        local boneName = configui.getValue(widgetPrefix .. "lower_twist_bone_" .. i)
        local frac = configui.getValue(widgetPrefix .. "lower_twist_bone_frac_" .. i)
        if boneName ~= nil and boneName ~= "" then
            table.insert(twistBones, {bone = boneName, fraction = frac})
        end
    end
    updateSetting("twist_bones", twistBones)
end

configui.onUpdate(widgetPrefix .. "lower_twist_bone_1_combo", function(value)
    --updateSetting("lower_twist_bone_1", boneNames[value] == "None" and "" or boneNames[value])
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_2_combo", function(value)
    --updateSetting("lower_twist_bone_2", boneNames[value] == "None" and "" or boneNames[value])
    updateTwistBones()
end)
configui.onUpdate(widgetPrefix .. "lower_twist_bone_3_combo", function(value)
    --updateSetting("lower_twist_bone_3", boneNames[value] == "None" and "" or boneNames[value])
    updateTwistBones()
end)



return M


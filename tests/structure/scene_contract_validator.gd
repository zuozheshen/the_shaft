extends RefCounted
## 只验证正式代码依赖的结构，不实例化到 SceneTree，不启动业务流程。

const MAIN_SCENE := "res://scenes/main/main_3d.tscn"
const SCRIPTS := {
	"FloatingCommUI": "res://scripts/ui/floating_comm_ui.gd",
	"MainConsolePresentation3D": "res://scripts/presentation/main_console_presentation_3d.gd",
	"RightConsolePresentation3D": "res://scripts/presentation/right_console_presentation_3d.gd",
	"GameRuntime": "res://scripts/runtime/game_runtime.gd",
	"DemoFlowManager": "res://scripts/flow/demo_flow_manager.gd",
	"RuntimeConnector3D": "res://scripts/runtime/runtime_connector_3d.gd",
	"CabinViewController3D": "res://scripts/elevator/cabin_view_controller_3d.gd",
	"CabinInterfaceRouter3D": "res://scripts/ui/cabin_interface_router_3d.gd",
	"ConsoleInterface": "res://scripts/ui/console_interface.gd",
	"BuildingTerminalInterface": "res://scripts/ui/building_terminal_interface.gd",
	"DestinationControlInterface": "res://scripts/ui/destination_control_interface.gd",
	"CabinInteractionController3D": "res://scripts/interaction/cabin_interaction_controller.gd",
	"InteractionHotspot3D": "res://scripts/interaction/interaction_hotspot_3d.gd",
	"LeftTerminalScreen3D": "res://scripts/ui/left_terminal_screen_3d.gd",
	"MonitorCameraController3D": "res://scripts/presentation/monitor_camera_controller_3d.gd",
	"MonitorPresentationCoordinator3D": "res://scripts/presentation/monitor_presentation_coordinator_3d.gd",
	"MonitorStageController3D": "res://scripts/presentation/monitor_stage_controller_3d.gd",
	"ElevatorDoorVisual3D": "res://scripts/presentation/elevator_door_visual_3d.gd",
	"PassengerVisual3D": "res://scripts/presentation/passenger_visual_3d.gd",
	"LayeredFloorSlice25D": "res://scripts/presentation/layered_floor_slice_2_5d.gd",
}
const SCENES := {
	"res://scenes/ui/FloatingCommUI.tscn": "FloatingCommUI",
	MAIN_SCENE: "Node",
	"res://scenes/runtime/game_runtime.tscn": "GameRuntime",
	"res://scenes/elevator/elevator_cabin_3d.tscn": "CabinViewController3D",
	"res://scenes/ui/ConsoleInterface.tscn": "ConsoleInterface",
	"res://scenes/ui/BuildingTerminalInterface.tscn": "BuildingTerminalInterface",
	"res://scenes/ui/DestinationControlInterface.tscn": "DestinationControlInterface",
	"res://scenes/presentation/monitor_test_stage_3d.tscn": "MonitorStageController3D",
	"res://scenes/presentation/elevator_door_visual_3d.tscn": "ElevatorDoorVisual3D",
	"res://scenes/presentation/passenger_visual_3d.tscn": "PassengerVisual3D",
	"res://scenes/presentation/layered_floor_slice_2_5d.tscn": "LayeredFloorSlice25D",
}
const AUTOLOADS := {
	"DialogueManager": "res://addons/dialogue_manager/dialogue_manager.gd",
	"ContentRegistry": "res://scripts/data/content_registry.gd",
}
const GODOT_AI_PLUGIN := "res://addons/godot_ai/plugin.cfg"
const GODOT_AI_VERSION := "4.1.0"
const GODOT_AI_AUTOLOAD_NAME := "_mcp_game_helper"
const GODOT_AI_AUTOLOAD := "res://addons/godot_ai/runtime/game_helper.gd"

# 导出路径允许重新配置和移动节点；只要求目标能解析且类型正确。
const EXPORTED_PATHS := {
	"MainConsolePresentation3D": {
		"console_interface_path": "ConsoleInterface", "stage_controller_path": "MonitorStageController3D",
		"monitor_subviewport_path": "SubViewport", "screen_mesh_path": "MeshInstance3D",
		"cam_01_backlight_path": "Node3D", "cam_02_backlight_path": "Node3D",
		"comm_light_path": "Node3D", "door_light_path": "MeshInstance3D",
		"fault_light_path": "Node3D", "status_label_path": "Label3D",
	},
	"RightConsolePresentation3D": {
		"destination_interface_path": "DestinationControlInterface",
		"information_label_path": "Label3D", "input_label_path": "Label3D",
		"feedback_label_path": "Label3D", "lever_pivot_path": "Node3D",
	},
	"RuntimeConnector3D": {"game_runtime_path": "GameRuntime", "elevator_cabin_path": "CabinViewController3D"},
	"CabinInteractionController3D": {"player_camera_path": "Camera3D", "view_controller_path": "CabinViewController3D", "console_interface_path": "ConsoleInterface", "building_terminal_interface_path": "BuildingTerminalInterface", "left_console_presentation_path": "LeftTerminalScreen3D", "destination_interface_path": "DestinationControlInterface", "right_console_presentation_path": "RightConsolePresentation3D", "interaction_hint_label_path": "Label"},
	"LeftTerminalScreen3D": {"screen_mesh_path": "MeshInstance3D", "sub_viewport_path": "SubViewport", "terminal_interface_path": "BuildingTerminalInterface", "player_camera_path": "Camera3D", "view_controller_path": "CabinViewController3D", "system_key_selected_path": "Node3D", "record_key_selected_path": "Node3D", "transcript_key_selected_path": "Node3D", "system_unread_light_path": "Node3D", "record_unread_light_path": "Node3D", "transcript_unread_light_path": "Node3D", "scroll_wheel_visual_path": "Node3D"},
	"MonitorCameraController3D": {"monitor_subviewport_path": "SubViewport", "monitor_camera_path": "Camera3D", "cabin_camera_anchor_path": "Marker3D", "door_camera_anchor_path": "Marker3D"},
	"MonitorStageController3D": {
		"floor_slice_mount_path": "Node3D", "initial_floor_slice_path": "LayeredFloorSlice25D", "floor_label_path": "Label3D",
		"floor_light_path": "Light3D",
		"passenger_mount_path": "Node3D", "initial_passenger_visual_path": "PassengerVisual3D",
		"outside_wait_anchor_path": "Marker3D", "threshold_anchor_path": "Marker3D",
		"cabin_position_anchor_path": "Marker3D", "outside_exit_anchor_path": "Marker3D", "door_visual_path": "ElevatorDoorVisual3D",
	},
	"ElevatorDoorVisual3D": {"animation_player_path": "AnimationPlayer", "audio_player_path": "AudioStreamPlayer3D"},
	"PassengerVisual3D": {"visual_root_path": "Node3D", "sprite_path": "Sprite3D", "contact_shadow_path": "MeshInstance3D", "dialogue_focus_path": "Marker3D"},
	"LayeredFloorSlice25D": {"far_layer_path": "MeshInstance3D", "main_layer_path": "MeshInstance3D", "mid_left_layer_path": "MeshInstance3D", "mid_right_layer_path": "MeshInstance3D", "ground_layer_path": "MeshInstance3D", "front_left_layer_path": "MeshInstance3D", "front_right_layer_path": "MeshInstance3D"},
}
const METHODS := {
	"FloatingCommUI": ["present", "set_minimized", "is_minimized", "blocks_pointer"],
	"MainConsolePresentation3D": ["set_fault_active"],
	"RightConsolePresentation3D": ["request_submit", "is_lever_animating"],
	"GameRuntime": ["get_demo_flow_manager"],
	"RuntimeConnector3D": ["get_demo_flow_manager"],
	"CabinViewController3D": ["get_current_direction", "is_turning"],
	"CabinInterfaceRouter3D": ["get_main_interface", "get_left_interface", "get_right_interface", "is_main_console_visible"],
	"ConsoleInterface": ["set_demo_flow_manager", "set_embedded_3d_mode", "set_camera_feed_texture", "get_current_camera_index", "request_open_door", "request_close_door", "request_toggle_microphone", "request_select_camera", "get_case_phase_display_text"],
	"BuildingTerminalInterface": ["set_demo_flow_manager", "set_embedded_3d_mode", "set_actively_viewed", "show_system_log", "show_passenger_record", "show_transcript", "scroll_current_content", "get_current_section", "get_unread_snapshot"],
	"LeftTerminalScreen3D": ["rotate_scroll_wheel"],
	"DestinationControlInterface": ["set_demo_flow_manager", "set_embedded_3d_mode", "append_destination_digit", "backspace_destination_input", "clear_destination_input", "request_verify_destination", "request_submit_destination", "get_destination_presentation"],
	"MonitorCameraController3D": ["setup", "select_camera"],
	"MonitorPresentationCoordinator3D": ["setup", "is_presentation_busy"],
	"MonitorStageController3D": ["request_door_open_presentation", "request_door_close_presentation", "request_passenger_boarding", "request_passenger_disembark", "apply_floor_visual_profile", "get_current_floor_visual_profile", "get_current_floor_visual_id"],
	"LayeredFloorSlice25D": ["apply_visual_profile", "reset_visual_profile"],
	"ElevatorDoorVisual3D": ["request_open", "request_close", "is_busy", "snap_open", "snap_closed"],
}
const SIGNALS := {
	"FloatingCommUI": ["choice_selected"],
	"DemoFlowManager": ["case_updated", "dispatch_started", "dispatch_completed", "shift_completed", "elevator_movement_completed", "left_terminal_section_updated", "left_terminal_session_reset"],
	"CabinViewController3D": ["turn_started", "facing_changed"],
	"CabinInterfaceRouter3D": ["main_console_visibility_changed"],
	"ConsoleInterface": ["camera_selected", "mic_enabled_changed", "case_phase_display_changed", "presentation_effects_requested", "return_requested"],
	"BuildingTerminalInterface": ["return_requested", "section_changed", "unread_state_changed"],
	"DestinationControlInterface": ["presentation_effects_requested", "destination_presentation_changed", "return_requested"],
	"MonitorPresentationCoordinator3D": ["presentation_busy_changed"],
	"MonitorStageController3D": ["door_presentation_state_changed", "door_presentation_opened", "door_presentation_closed", "passenger_boarded", "passenger_exited", "presentation_busy_changed"],
	"ElevatorDoorVisual3D": ["door_state_changed", "door_busy_changed", "door_opened", "door_closed"],
}

var errors: Array[String] = []
var _scene_path: String
var _root: Node


func validate_project() -> Array[String]:
	errors.clear()
	var config := ConfigFile.new()
	var result := config.load("res://project.godot")
	if result != OK:
		_problem("res://project.godot", ".", "readable configuration", str(result))
	else:
		validate_configuration(config)
	for path: String in SCENES:
		if not ResourceLoader.exists(path, "PackedScene"):
			_problem(path, ".", "PackedScene", "missing")
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			_problem(path, ".", "PackedScene", "load failed")
			continue
		var instance := packed.instantiate()
		validate_scene(instance, path)
		instance.free()
	return errors.duplicate()


func validate_configuration(config: ConfigFile) -> void:
	var actual_entry := resolve_resource_path(str(config.get_value("application", "run/main_scene", "")))
	if actual_entry != MAIN_SCENE:
		_problem("res://project.godot", "application/run/main_scene", MAIN_SCENE, actual_entry)
	var resolved_autoloads: Dictionary = {}
	for name: String in config.get_section_keys("autoload") if config.has_section("autoload") else PackedStringArray():
		var value := str(config.get_value("autoload", name))
		var path := resolve_resource_path(value.trim_prefix("*"))
		resolved_autoloads[name] = path
		if path in [SCRIPTS.GameRuntime, SCRIPTS.DemoFlowManager]:
			_problem("res://project.godot", "autoload/" + name, "core managers owned by main scene", path)
		if path in AUTOLOADS.values() and not value.begins_with("*"):
			_problem("res://project.godot", "autoload/" + name, "enabled singleton", value)
	for name: String in AUTOLOADS:
		if resolved_autoloads.get(name, "") != AUTOLOADS[name]:
			_problem("res://project.godot", "autoload/" + name, AUTOLOADS[name], str(resolved_autoloads.get(name, "missing")))
		var count := resolved_autoloads.values().count(AUTOLOADS[name])
		if count != 1:
			_problem("res://project.godot", "autoload/" + name, "one script instance", str(count))
	if resolved_autoloads.get(GODOT_AI_AUTOLOAD_NAME, "") != GODOT_AI_AUTOLOAD:
		_problem("res://project.godot", "autoload/" + GODOT_AI_AUTOLOAD_NAME,
			GODOT_AI_AUTOLOAD, str(resolved_autoloads.get(GODOT_AI_AUTOLOAD_NAME, "missing")))
	var helper_value := str(config.get_value("autoload", GODOT_AI_AUTOLOAD_NAME, ""))
	if not helper_value.begins_with("*"):
		_problem("res://project.godot", "autoload/" + GODOT_AI_AUTOLOAD_NAME,
			"enabled development helper", helper_value)
	var enabled_plugins: PackedStringArray = config.get_value(
		"editor_plugins", "enabled", PackedStringArray()
	)
	for plugin_path: String in ["res://addons/dialogue_manager/plugin.cfg", GODOT_AI_PLUGIN]:
		if plugin_path not in enabled_plugins:
			_problem("res://project.godot", "editor_plugins/enabled", plugin_path, "missing")
	var godot_ai_config := ConfigFile.new()
	var plugin_load_result := godot_ai_config.load(GODOT_AI_PLUGIN)
	if plugin_load_result != OK:
		_problem(GODOT_AI_PLUGIN, ".", "readable Godot AI plugin configuration", str(plugin_load_result))
	elif str(godot_ai_config.get_value("plugin", "version", "")) != GODOT_AI_VERSION:
		_problem(GODOT_AI_PLUGIN, "plugin/version", GODOT_AI_VERSION,
			str(godot_ai_config.get_value("plugin", "version", "missing")))
	for action: String in ["turn_left", "turn_right"]:
		if not config.has_section_key("input", action):
			_problem("res://project.godot", "input/" + action, "script-referenced action", "missing")


func validate_scene(instance: Node, scene_path: String) -> void:
	# 不调用 _ready / setup / getter：这些方法依赖已入树的运行环境。
	_root = instance
	_scene_path = scene_path
	if instance == null:
		_problem(scene_path, ".", "scene instance", "null")
		return
	_expect(instance, ".", str(SCENES.get(scene_path, "Node")))
	if scene_path == MAIN_SCENE:
		_expect_named(instance, "游戏运行层", "GameRuntime")
		_expect_named(instance, "运行层连接器", "RuntimeConnector3D")
		_expect_named(instance, "三维操作舱", "CabinViewController3D")
		_check_unique_script("GameRuntime")
		_check_unique_script("DemoFlowManager")
	_visit(instance)
	_root = null


func _visit(node: Node) -> void:
	var script := node.get_script() as Script
	if script != null:
		for type_name: String in SCRIPTS:
			if script.resource_path != SCRIPTS[type_name]:
				continue
			validate_api(node, METHODS.get(type_name, []), SIGNALS.get(type_name, []),
				_scene_path, str(_root.get_path_to(node)))
			for property: String in EXPORTED_PATHS.get(type_name, {}):
				_check_export(node, property, EXPORTED_PATHS[type_name][property])
			_check_fixed_dependencies(node, type_name)
	for child: Node in node.get_children():
		_visit(child)


func validate_api(node: Node, methods: Array, signals: Array, source: String, path: String) -> void:
	for method: String in methods:
		if not node.has_method(method):
			_problem(source, path + "/method:" + method, "public method", "missing")
	for signal_name: String in signals:
		if not node.has_signal(signal_name):
			_problem(source, path + "/signal:" + signal_name, "signal", "missing")


func _check_fixed_dependencies(node: Node, type_name: String) -> void:
	match type_name:
		"GameRuntime":
			_expect(node, "演示流程管理器", "DemoFlowManager")
		"CabinViewController3D":
			_expect(node, "玩家视角/摄像机旋转轴", "Node3D")
			_expect(node, "玩家视角/摄像机旋转轴/玩家摄像机", "Camera3D")
			_expect(node, "调试界面/当前方向文本", "Label")
			_expect(node, "调试界面/操作提示文本", "Label")
			for name: String in ["主操作台方向", "左操作台方向", "电梯门方向", "右操作台方向"]:
				_expect(node, "观察方向/" + name, "Marker3D")
			# 与 RuntimeConnector / Router 使用的名称查询保持一致，不冻结中间容器路径。
			_expect_named(node, "操作台界面层", "CabinInterfaceRouter3D")
			_expect_named(node, "BuildingTerminalInterface", "BuildingTerminalInterface")
			_expect_named(node, "监控测试摄影棚", "MonitorStageController3D")
			_expect_named(node, "监控表现协调器", "MonitorPresentationCoordinator3D")
			_expect_named(node, "监控渲染系统", "MonitorCameraController3D")
			_expect_named(node, "交互控制器", "CabinInteractionController3D")
			_check_unique_script("LeftTerminalScreen3D")
			_check_unique_script("ConsoleInterface")
			_check_unique_script("FloatingCommUI")
			_check_unique_script("MonitorCameraController3D")
			_check_unique_script("MainConsolePresentation3D")
			_check_unique_script("RightConsolePresentation3D")
		"CabinInterfaceRouter3D":
			_expect(node, "..", "CabinViewController3D")
			_expect(node, "门区提示", "Label")
			_expect_named(node, "主操作台界面容器", "Control")
			_expect_named(node, "右操作台界面容器", "Control")
			_expect_named(node, "ConsoleInterface", "ConsoleInterface")
			_expect_named(node, "DestinationControlInterface", "DestinationControlInterface")
		"FloatingCommUI":
			_expect(node, "%PassengerSpeechLabel", "Label")
			_expect(node, "%DialogueChoices", "VBoxContainer")
			_expect(node, "%ContentScroll", "ScrollContainer")
			_expect(node, "%TitleBar", "Control")
			_expect(node, "%MinimizeButton", "Button")
		"MainConsolePresentation3D":
			for property: String in ["door_closed_material", "door_moving_material", "door_open_material"]:
				if not node.get(property) is StandardMaterial3D:
					_report(node, property, "StandardMaterial3D", "missing or wrong type")
			var screen := node.get_node_or_null(node.get("screen_mesh_path")) as MeshInstance3D
			if screen != null and not screen.material_override is StandardMaterial3D:
				_report(node, "screen_mesh_path/material_override", "StandardMaterial3D", "missing or wrong type")
		"RightConsolePresentation3D":
			var right_root := _root.find_child("右操作台定位", true, false)
			if right_root == null:
				_report(node, "右操作台定位", "Node3D", "missing")
			else:
				_expect(right_root, "下部斜面根", "Node3D")
				_expect(right_root, "下部斜面根/楼层导引书", "Node3D")
				_expect(right_root, "下部斜面根/底缘挡条", "CSGBox3D")
				for key_name: String in [
					"数字1", "数字2", "数字3", "数字4", "数字5", "数字6",
					"数字7", "数字8", "数字9", "清空", "数字0", "退格",
				]:
					_expect(right_root, "数字键盘/" + key_name, "InteractionHotspot3D")
				_expect(right_root, "数字显示组/验证楼层热点", "InteractionHotspot3D")
				_expect(right_root, "下部斜面根/执行拨杆热点", "InteractionHotspot3D")
		"LeftTerminalScreen3D":
			_expect(node, "左台屏幕", "MeshInstance3D")
			_expect(node, "左台界面视口", "SubViewport")
			_expect(node, "左台界面视口/BuildingTerminalInterface", "BuildingTerminalInterface")
			_expect(node, "栏目控制区", "Node3D")
			for section_name: String in ["系统日志", "乘客档案", "对话记录"]:
				_expect(node, "栏目控制区/" + section_name, "InteractionHotspot3D")
				_expect(node, "栏目控制区/" + section_name + "/CollisionShape3D", "CollisionShape3D")
				_expect(node, "栏目控制区/" + section_name + "/按钮帽", "MeshInstance3D")
				_expect(node, "栏目控制区/" + section_name + "/状态灯", "Node3D")
			_expect(node, "滚轮根", "InteractionHotspot3D")
			_expect(node, "滚轮根/CollisionShape3D", "CollisionShape3D")
			_expect(node, "滚轮根/滚轮视觉", "Node3D")
		"ConsoleInterface":
			_expect(node, "FloatingCommUI", "FloatingCommUI")
			_expect(node, "RejectionToast", "Label")
			_expect(node, "ToastTimer", "Timer")
			_expect(node, "%OpenDoorButton", "Button")
			_expect(node, "%CloseDoorButton", "Button")
			_expect(node, "%CameraFeedTextureRect", "TextureRect")
			var panel := "ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/CameraControlPanel/"
			_expect(node, panel + "PrevCameraButton", "Button")
			_expect(node, panel + "NextCameraButton", "Button")
		"BuildingTerminalInterface":
			_expect(node, "TerminalLayout/TabButtonPanel", "HBoxContainer")
			_expect(node, "TerminalLayout/ContentScrollContainer", "ScrollContainer")
			_expect(node, "TerminalLayout/ContentScrollContainer/TerminalContentPanel/TerminalContentMargin/TerminalContentLabel", "Label")
		"DestinationControlInterface":
			_expect(node, "RootMargin/DestinationLayout/ManualInputPanel/ManualInputLayout/ManualDestinationLineEdit", "LineEdit")
			_expect(node, "RootMargin/DestinationLayout/SubmitDestinationButton", "Button")
		"MonitorStageController3D":
			_check_mount(node, "initial_floor_slice_path", "floor_slice_mount_path")
			_check_mount(node, "initial_passenger_visual_path", "passenger_mount_path")
		"ElevatorDoorVisual3D":
			var path: NodePath = node.get("animation_player_path")
			var player := node.get_node_or_null(path) as AnimationPlayer
			if player != null:
				for animation_name: String in ["RESET", "door_open", "door_close"]:
					if not player.has_animation(animation_name):
						_report(node, str(path) + ":" + animation_name, "script-referenced animation", "missing")


func _check_export(node: Node, property: String, expected_type: String) -> void:
	var properties: Array[String] = []
	for entry: Dictionary in node.get_property_list():
		properties.append(str(entry.name))
	if property not in properties:
		_report(node, property, "NodePath property", "missing")
		return
	var value: Variant = node.get(property)
	if not value is NodePath or value.is_empty():
		_report(node, property, "non-empty NodePath", str(value))
		return
	_expect(node, str(value), expected_type, property)


func _check_mount(node: Node, child_property: String, parent_property: String) -> void:
	var child_path: NodePath = node.get(child_property)
	var parent_path: NodePath = node.get(parent_property)
	if child_path.is_empty() or parent_path.is_empty():
		return
	var child := node.get_node_or_null(child_path)
	var mount := node.get_node_or_null(parent_path)
	if child != null and mount != null and child.get_parent() != mount:
		_report(node, str(child_path), "child of " + str(parent_path), "different parent")


func _expect(origin: Node, path: String, expected_type: String, property: String = "") -> void:
	var candidate := origin.get_node_or_null(NodePath(path))
	if not _matches(candidate, expected_type):
		var actual := "missing"
		if candidate != null:
			var script := candidate.get_script() as Script
			actual = candidate.get_class() + " / " + (script.resource_path if script != null else "no script")
		_report(origin, path + (" [" + property + "]" if not property.is_empty() else ""), expected_type, actual)


func _expect_named(origin: Node, node_name: String, expected_type: String) -> void:
	var matches := origin.find_children(node_name, "", true, false)
	if matches.size() != 1:
		_report(origin, "**/" + node_name, "one named " + expected_type, str(matches.size()))
	for candidate: Node in matches:
		_expect(origin, str(origin.get_path_to(candidate)), expected_type)


func _matches(node: Node, expected_type: String) -> bool:
	if node == null:
		return false
	if expected_type in SCRIPTS:
		var script := node.get_script() as Script
		return script != null and script.resource_path == SCRIPTS[expected_type]
	return node.is_class(expected_type)


func _check_unique_script(type_name: String) -> void:
	var count := _count_script(_root, SCRIPTS[type_name])
	if count != 1:
		_report(_root, "**/" + type_name, "one core manager", str(count))


func _count_script(node: Node, expected_path: String) -> int:
	var count := 0
	var script := node.get_script() as Script
	# 子类也计入重复实例，不能用继承绕过唯一 Manager 约束。
	while script != null:
		if script.resource_path == expected_path:
			count += 1
			break
		script = script.get_base_script()
	for child: Node in node.get_children():
		count += _count_script(child, expected_path)
	return count


func _report(origin: Node, path: String, expected: String, actual: String) -> void:
	_problem(_scene_path, str(_root.get_path_to(origin)) + "/" + path, expected, actual)


func _problem(source: String, path: String, expected: String, actual: String) -> void:
	errors.append("%s | %s | expected: %s | actual: %s" % [source, path, expected, actual])


func resolve_resource_path(value: String) -> String:
	if not value.begins_with("uid://"):
		return value
	var id := ResourceUID.text_to_id(value)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return "unresolved:" + value
	return ResourceUID.get_id_path(id)

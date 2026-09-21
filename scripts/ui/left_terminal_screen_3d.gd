class_name LeftTerminalScreen3D
extends Node3D


@export var screen_mesh_path: NodePath = ^"左台屏幕"
@export var sub_viewport_path: NodePath = ^"左台界面视口"
@export var terminal_interface_path: NodePath = ^"左台界面视口/BuildingTerminalInterface"
@export var player_camera_path: NodePath
@export var view_controller_path: NodePath
@export var system_key_selected_path: NodePath = ^"栏目控制区/系统日志/选中指示"
@export var record_key_selected_path: NodePath = ^"栏目控制区/乘客档案/选中指示"
@export var transcript_key_selected_path: NodePath = ^"栏目控制区/对话记录/选中指示"
@export var system_unread_light_path: NodePath = ^"栏目控制区/系统日志/状态灯"
@export var record_unread_light_path: NodePath = ^"栏目控制区/乘客档案/状态灯"
@export var transcript_unread_light_path: NodePath = ^"栏目控制区/对话记录/状态灯"
@export var scroll_wheel_visual_path: NodePath = ^"滚轮根/滚轮视觉"
@export_range(4.0, 45.0, 1.0) var scroll_tick_degrees: float = 16.0

var _screen_mesh: MeshInstance3D
var _sub_viewport: SubViewport
var _terminal: BuildingTerminalInterface
var _player_camera: Camera3D
var _view_controller: CabinViewController3D
var _selected_visuals: Array[Node3D] = []
var _unread_lights: Array[Node3D] = []
var _scroll_wheel_visual: Node3D


func _ready() -> void:
	_screen_mesh = _get_required_node(screen_mesh_path, "MeshInstance3D") as MeshInstance3D
	_sub_viewport = _get_required_node(sub_viewport_path, "SubViewport") as SubViewport
	_terminal = _get_required_node(terminal_interface_path, "Control") as BuildingTerminalInterface
	_player_camera = _get_required_node(player_camera_path, "Camera3D") as Camera3D
	_view_controller = _get_required_node(view_controller_path, "Node3D") \
			as CabinViewController3D
	_selected_visuals = [
		_get_required_node(system_key_selected_path, "Node3D") as Node3D,
		_get_required_node(record_key_selected_path, "Node3D") as Node3D,
		_get_required_node(transcript_key_selected_path, "Node3D") as Node3D,
	]
	_unread_lights = [
		_get_required_node(system_unread_light_path, "Node3D") as Node3D,
		_get_required_node(record_unread_light_path, "Node3D") as Node3D,
		_get_required_node(transcript_unread_light_path, "Node3D") as Node3D,
	]
	_scroll_wheel_visual = _get_required_node(scroll_wheel_visual_path, "Node3D") as Node3D
	if _screen_mesh == null or not _screen_mesh.mesh is QuadMesh:
		push_error("左台屏幕必须使用 QuadMesh 承载唯一 BuildingTerminalInterface。")
	else:
		_configure_screen_material()
	if _view_controller == null:
		push_error("左台屏幕控制器没有连接 CabinViewController3D。")
	else:
		if not _view_controller.turn_started.is_connected(_on_turn_started):
			_view_controller.turn_started.connect(_on_turn_started)
		if not _view_controller.facing_changed.is_connected(_on_facing_changed):
			_view_controller.facing_changed.connect(_on_facing_changed)
	if _terminal != null:
		if not _terminal.section_changed.is_connected(_on_section_changed):
			_terminal.section_changed.connect(_on_section_changed)
		if not _terminal.unread_state_changed.is_connected(_on_unread_state_changed):
			_terminal.unread_state_changed.connect(_on_unread_state_changed)
		_on_section_changed(_terminal.get_current_section())
		_on_unread_state_changed(_terminal.get_unread_snapshot())
	_sync_active_view_state()


func rotate_scroll_wheel(direction: int) -> void:
	if _scroll_wheel_visual == null or direction == 0:
		return
	# CylinderMesh 的本地 Y 是实体轴；只绕自身轴步进，根、碰撞和 Inspector 布局保持不变。
	_scroll_wheel_visual.rotate_object_local(
		Vector3.UP,
		deg_to_rad(-scroll_tick_degrees * direction)
	)


func _configure_screen_material() -> void:
	if _screen_mesh == null or _sub_viewport == null:
		return
	var screen_material := StandardMaterial3D.new()
	screen_material.resource_local_to_scene = true
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen_material.albedo_texture = _sub_viewport.get_texture()
	_screen_mesh.material_override = screen_material


func _sync_active_view_state() -> void:
	if _terminal == null:
		return
	var is_viewed := _player_camera != null \
			and _player_camera.is_current() \
			and _view_controller != null \
			and not _view_controller.is_turning() \
			and _view_controller.get_current_direction() \
					== CabinViewController3D.FacingDirection.LEFT_CONSOLE
	_terminal.set_actively_viewed(is_viewed)


func _on_turn_started(_direction: int, _direction_name: String) -> void:
	if _terminal != null:
		_terminal.set_actively_viewed(false)


func _on_facing_changed(_direction: int, _direction_name: String) -> void:
	_sync_active_view_state()


func _on_section_changed(section: int) -> void:
	for index in _selected_visuals.size():
		var visual := _selected_visuals[index]
		if visual != null:
			visual.visible = index == section


func _on_unread_state_changed(snapshot: Dictionary) -> void:
	var ids: Array[StringName] = [
		BuildingTerminalInterface.SECTION_SYSTEM_LOG,
		BuildingTerminalInterface.SECTION_PASSENGER_RECORD,
		BuildingTerminalInterface.SECTION_TRANSCRIPT,
	]
	for index in _unread_lights.size():
		var light := _unread_lights[index]
		if light != null:
			light.visible = bool(snapshot.get(ids[index], false))


func _get_required_node(node_path: NodePath, expected_class: String) -> Node:
	if node_path.is_empty():
		push_error("左台实体终端缺少 %s 的 NodePath 配置。" % expected_class)
		return null
	var required_node := get_node_or_null(node_path)
	if required_node == null:
		push_error("左台实体终端找不到节点：%s" % node_path)
		return null
	if not required_node.is_class(expected_class):
		push_error("节点 %s 应为 %s，实际为 %s。" % [
			node_path,
			expected_class,
			required_node.get_class(),
		])
		return null
	return required_node

class_name CabinInteractionController3D
extends Node


const OPEN_MICROPHONE_ACTION: StringName = &"open_microphone"
const OPEN_DOOR_ACTION: StringName = &"open_door"
const CLOSE_DOOR_ACTION: StringName = &"close_door"


@export var player_camera_path: NodePath
@export var view_controller_path: NodePath
@export var console_interface_path: NodePath
@export var interaction_hint_label_path: NodePath
@export_flags_3d_physics var interaction_collision_mask: int = 1 << 7
@export_range(1.0, 50.0, 0.5) var ray_length: float = 10.0

var _player_camera: Camera3D
var _view_controller: CabinViewController3D
var _console_interface: ConsoleInterface
var _interaction_hint_label: Label
var _default_hint_text: String = ""
var _hovered_hotspot: InteractionHotspot3D
var _has_hovered_hotspot: bool = false
var _warned_action_ids: Dictionary = {}


func _ready() -> void:
	# 引用集中从 Inspector 配置，场景结构变化时能在 Output 中明确指出缺失项。
	_player_camera = _get_required_node(player_camera_path, "Camera3D") as Camera3D
	_view_controller = _get_required_node(view_controller_path, "Node3D") \
			as CabinViewController3D
	_console_interface = _get_required_node(console_interface_path, "Control") \
			as ConsoleInterface
	_interaction_hint_label = _get_required_node(interaction_hint_label_path, "Label") as Label
	if _interaction_hint_label != null:
		_default_hint_text = _interaction_hint_label.text
	if _view_controller == null:
		push_error("3D 交互控制器的视角节点没有挂载 CabinViewController3D 脚本。")
	if _console_interface == null:
		push_error("3D 交互控制器的主台界面节点不是 ConsoleInterface。")

	if _view_controller != null:
		if not _view_controller.turn_started.is_connected(_on_turn_started):
			_view_controller.turn_started.connect(_on_turn_started)
		if not _view_controller.facing_changed.is_connected(_on_facing_changed):
			_view_controller.facing_changed.connect(_on_facing_changed)


func _exit_tree() -> void:
	_clear_hovered_hotspot()


func _process(_delta: float) -> void:
	_update_hovered_hotspot()


func _unhandled_input(event: InputEvent) -> void:
	# 使用未处理输入，让真正的 2D Button 优先消费点击，避免同时触发背后的 3D 热点。
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null \
			or mouse_event.button_index != MOUSE_BUTTON_LEFT \
			or not mouse_event.pressed:
		return
	if not _can_use_hotspots() or _hovered_hotspot == null:
		return

	# 点击时重新射线确认，不能执行鼠标先前悬停后缓存下来的旧热点。
	var clicked_hotspot := _raycast_hotspot(mouse_event.position)
	if clicked_hotspot == null or clicked_hotspot != _hovered_hotspot:
		_clear_hovered_hotspot()
		return
	if not _is_hotspot_allowed(clicked_hotspot):
		_clear_hovered_hotspot()
		return

	_execute_action(clicked_hotspot.get_action_id())
	get_viewport().set_input_as_handled()


func _update_hovered_hotspot() -> void:
	if not _can_use_hotspots() or _is_pointer_over_blocking_gui():
		_clear_hovered_hotspot()
		return

	var hotspot := _raycast_hotspot(get_viewport().get_mouse_position())
	if hotspot == null or not _is_hotspot_allowed(hotspot):
		_clear_hovered_hotspot()
		return
	_set_hovered_hotspot(hotspot)


func _raycast_hotspot(mouse_position: Vector2) -> InteractionHotspot3D:
	if _player_camera == null or _player_camera.get_world_3d() == null:
		return null
	var ray_origin := _player_camera.project_ray_origin(mouse_position)
	var ray_direction := _player_camera.project_ray_normal(mouse_position)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length
	)
	query.collision_mask = interaction_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := _player_camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return null
	return result.get("collider") as InteractionHotspot3D


func _can_use_hotspots() -> bool:
	return _player_camera != null \
			and _player_camera.is_current() \
			and _view_controller != null \
			and not _view_controller.is_turning()


func _is_hotspot_allowed(hotspot: InteractionHotspot3D) -> bool:
	return hotspot.can_interact() \
			and hotspot.get_station_id() == _view_controller.get_current_station_id()


func _is_pointer_over_blocking_gui() -> bool:
	var hovered_control := get_viewport().gui_get_hovered_control()
	return hovered_control != null \
			and hovered_control.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _set_hovered_hotspot(hotspot: InteractionHotspot3D) -> void:
	# 只有命中对象发生变化时才切换视觉，不在每帧重复设置同一高亮。
	if _has_hovered_hotspot \
			and is_instance_valid(_hovered_hotspot) \
			and _hovered_hotspot == hotspot:
		return
	if is_instance_valid(_hovered_hotspot):
		_hovered_hotspot.set_hovered(false)
	_hovered_hotspot = hotspot
	_has_hovered_hotspot = true
	_hovered_hotspot.set_hovered(true)
	if _interaction_hint_label != null:
		_interaction_hint_label.text = hotspot.get_prompt_text()


func _clear_hovered_hotspot() -> void:
	if not _has_hovered_hotspot:
		return
	if is_instance_valid(_hovered_hotspot):
		_hovered_hotspot.set_hovered(false)
	_hovered_hotspot = null
	_has_hovered_hotspot = false
	_restore_default_hint()


func _restore_default_hint() -> void:
	if _interaction_hint_label != null:
		_interaction_hint_label.text = _default_hint_text


func _execute_action(action_id: StringName) -> void:
	match action_id:
		OPEN_MICROPHONE_ACTION:
			if _console_interface != null:
				_console_interface.request_toggle_microphone()
		OPEN_DOOR_ACTION:
			if _console_interface != null:
				_console_interface.request_open_door()
		CLOSE_DOOR_ACTION:
			if _console_interface != null:
				_console_interface.request_close_door()
		_:
			if not _warned_action_ids.has(action_id):
				_warned_action_ids[action_id] = true
				push_warning("未注册的 3D 交互动作：%s" % action_id)


func _on_turn_started(_direction: int, _direction_name: String) -> void:
	_clear_hovered_hotspot()


func _on_facing_changed(_direction: int, _direction_name: String) -> void:
	_clear_hovered_hotspot()


func _get_required_node(node_path: NodePath, expected_class: String) -> Node:
	if node_path.is_empty():
		push_error("3D 交互控制器缺少 %s 的 NodePath 配置。" % expected_class)
		return null
	var required_node := get_node_or_null(node_path)
	if required_node == null:
		push_error("3D 交互控制器找不到节点：%s" % node_path)
		return null
	if not required_node.is_class(expected_class):
		push_error("节点 %s 应为 %s，实际为 %s。" % [
			node_path,
			expected_class,
			required_node.get_class(),
		])
		return null
	return required_node

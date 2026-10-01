class_name CabinInteractionController3D
extends Node


const OPEN_MICROPHONE_ACTION: StringName = &"open_microphone"
const OPEN_DOOR_ACTION: StringName = &"open_door"
const CAM_01_ACTION: StringName = &"select_camera_01"
const CAM_02_ACTION: StringName = &"select_camera_02"
const CLOSE_DOOR_ACTION: StringName = &"close_door"
const LEFT_SYSTEM_LOG_ACTION: StringName = &"left_system_log"
const LEFT_PASSENGER_RECORD_ACTION: StringName = &"left_passenger_record"
const LEFT_TRANSCRIPT_ACTION: StringName = &"left_transcript"
const LEFT_SCROLL_ACTION: StringName = &"left_scroll"
const DESTINATION_DIGIT_PREFIX: String = "destination_digit_"
const DESTINATION_CLEAR_ACTION: StringName = &"destination_clear"
const DESTINATION_BACKSPACE_ACTION: StringName = &"destination_backspace"
const DESTINATION_VERIFY_ACTION: StringName = &"destination_verify"
const DESTINATION_SUBMIT_ACTION: StringName = &"destination_submit"
const FOCUS_LEFT_ACTION: StringName = &"focus_left"
const FOCUS_RIGHT_ACTION: StringName = &"focus_right"
const FOCUS_UP_ACTION: StringName = &"focus_up"
const FOCUS_DOWN_ACTION: StringName = &"focus_down"
const INTERACT_CONFIRM_ACTION: StringName = &"interact_confirm"
const INTERACT_CANCEL_ACTION: StringName = &"interact_cancel"
const COMM_TOGGLE_ACTION: StringName = &"comm_toggle"
const CONTEXT_SCROLL_UP_ACTION: StringName = &"context_scroll_up"
const CONTEXT_SCROLL_DOWN_ACTION: StringName = &"context_scroll_down"

enum InputMode {
	MOUSE,
	GAMEPAD,
}


@export var player_camera_path: NodePath
@export var view_controller_path: NodePath
@export var console_interface_path: NodePath
@export var building_terminal_interface_path: NodePath
@export var left_console_presentation_path: NodePath
@export var destination_interface_path: NodePath
@export var right_console_presentation_path: NodePath
@export var interaction_hint_label_path: NodePath
@export_flags_3d_physics var interaction_collision_mask: int = 1 << 7
@export_range(1.0, 50.0, 0.5) var ray_length: float = 10.0
@export_range(0.1, 1.0, 0.05) var gamepad_navigation_threshold: float = 0.55
@export_range(0.05, 1.0, 0.05) var gamepad_initial_repeat_delay: float = 0.35
@export_range(0.03, 0.5, 0.01) var gamepad_repeat_interval: float = 0.12
@export_range(0.1, 1.0, 0.05) var context_scroll_threshold: float = 0.55

var _player_camera: Camera3D
var _view_controller: CabinViewController3D
var _console_interface: ConsoleInterface
var _building_terminal_interface: BuildingTerminalInterface
var _left_console_presentation: LeftTerminalScreen3D
var _destination_interface: DestinationControlInterface
var _right_console_presentation: RightConsolePresentation3D
var _interaction_hint_label: Label
var _default_hint_text: String = ""
var _hovered_hotspot: InteractionHotspot3D
var _has_hovered_hotspot: bool = false
var _warned_action_ids: Dictionary = {}
var _input_mode: InputMode = InputMode.MOUSE
var _navigation_direction: Vector2i = Vector2i.ZERO
var _navigation_repeat_remaining: float = 0.0
var _scroll_direction: int = 0
var _scroll_repeat_remaining: float = 0.0


func _ready() -> void:
	# 引用集中从 Inspector 配置，场景结构变化时能在 Output 中明确指出缺失项。
	_player_camera = _get_required_node(player_camera_path, "Camera3D") as Camera3D
	_view_controller = _get_required_node(view_controller_path, "Node3D") \
			as CabinViewController3D
	_console_interface = _get_required_node(console_interface_path, "Control") \
			as ConsoleInterface
	_building_terminal_interface = _get_required_node(
		building_terminal_interface_path,
		"Control"
	) as BuildingTerminalInterface
	_left_console_presentation = _get_required_node(
		left_console_presentation_path,
		"Node3D"
	) as LeftTerminalScreen3D
	_destination_interface = _get_required_node(destination_interface_path, "Control") \
			as DestinationControlInterface
	_right_console_presentation = _get_required_node(
		right_console_presentation_path,
		"Node"
	) as RightConsolePresentation3D
	_interaction_hint_label = _get_required_node(interaction_hint_label_path, "Label") as Label
	if _interaction_hint_label != null:
		_default_hint_text = CabinViewController3D.OPERATION_HINT_TEXT
	if _view_controller == null:
		push_error("3D 交互控制器的视角节点没有挂载 CabinViewController3D 脚本。")
	if _console_interface == null:
		push_error("3D 交互控制器的主台界面节点不是 ConsoleInterface。")
	if _building_terminal_interface == null:
		push_error("3D 交互控制器找不到左台 BuildingTerminalInterface。")
	if _left_console_presentation == null:
		push_error("3D 交互控制器找不到左台实体展示根。")
	if _destination_interface == null:
		push_error("3D 交互控制器的右台界面节点不是 DestinationControlInterface。")
	if _right_console_presentation == null:
		push_error("3D 交互控制器找不到右台实体展示绑定。")

	if _view_controller != null:
		if not _view_controller.turn_started.is_connected(_on_turn_started):
			_view_controller.turn_started.connect(_on_turn_started)
		if not _view_controller.facing_changed.is_connected(_on_facing_changed):
			_view_controller.facing_changed.connect(_on_facing_changed)


func _exit_tree() -> void:
	_clear_hovered_hotspot()


func _process(delta: float) -> void:
	if _input_mode == InputMode.MOUSE:
		_update_hovered_hotspot()
	else:
		_validate_gamepad_focus()
	_update_gamepad_navigation(delta)
	_update_context_scroll(delta)


func _input(event: InputEvent) -> void:
	# 在 GUI 之前仲裁手柄动作，防止 Control 的 ui_accept 消费 A 后绕过实体/COMM 优先级。
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_switch_to_mouse_mode()
		return
	if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return
	for action in [FOCUS_LEFT_ACTION, FOCUS_RIGHT_ACTION, FOCUS_UP_ACTION, FOCUS_DOWN_ACTION]:
		if event.is_action(action):
			# 方向由 _process 的统一 threshold/repeat 状态机消费，阻止 GUI 自带导航抢焦点。
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(COMM_TOGGLE_ACTION):
		_switch_to_gamepad_mode()
		_reset_gamepad_repeat_state()
		var comm := _get_comm_view()
		if comm != null:
			comm.toggle_from_controller()
			if not comm.has_controller_choice_context():
				_establish_default_gamepad_focus()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(INTERACT_CANCEL_ACTION):
		var cancel_comm := _get_comm_view()
		if cancel_comm != null and cancel_comm.cancel_controller_context():
			_switch_to_gamepad_mode()
			_reset_gamepad_repeat_state()
			_establish_default_gamepad_focus()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(INTERACT_CONFIRM_ACTION):
		_switch_to_gamepad_mode()
		_handle_gamepad_confirm()
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	# 只有鼠标点击与滚轮留给 GUI 先处理，避免穿透 Floating COMM。

	# 使用未处理输入，让 Floating COMM 优先消费点击/滚轮，避免穿透到实体控件。
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	_switch_to_mouse_mode()
	if not _can_use_hotspots() or _is_pointer_over_blocking_gui():
		return

	# 点击时只信任当前事件坐标的射线，不能执行任何旧缓存热点。
	var clicked_hotspot := _raycast_hotspot(mouse_event.position)
	if clicked_hotspot == null or not _is_hotspot_allowed(clicked_hotspot):
		_clear_hovered_hotspot()
		return
	_set_hovered_hotspot(clicked_hotspot)

	var action_id := clicked_hotspot.get_action_id()
	if mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if action_id != LEFT_SCROLL_ACTION:
			return
		_execute_left_scroll(-1 if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_execute_action(action_id)
	else:
		return
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


func _switch_to_mouse_mode() -> void:
	if _input_mode == InputMode.MOUSE:
		return
	_input_mode = InputMode.MOUSE
	_reset_gamepad_repeat_state()
	_clear_hovered_hotspot()


func _switch_to_gamepad_mode() -> void:
	if _input_mode == InputMode.GAMEPAD:
		return
	_input_mode = InputMode.GAMEPAD
	_clear_hovered_hotspot()


func _update_gamepad_navigation(delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength(FOCUS_RIGHT_ACTION)
				- Input.get_action_strength(FOCUS_LEFT_ACTION),
		Input.get_action_strength(FOCUS_DOWN_ACTION)
				- Input.get_action_strength(FOCUS_UP_ACTION)
	)
	var direction := _quantize_navigation_direction(input_vector)
	if direction == Vector2i.ZERO:
		_navigation_direction = Vector2i.ZERO
		_navigation_repeat_remaining = 0.0
		return
	if direction != _navigation_direction:
		_navigation_direction = direction
		_navigation_repeat_remaining = gamepad_initial_repeat_delay
		_handle_gamepad_navigation(direction)
		return
	_navigation_repeat_remaining -= delta
	if _navigation_repeat_remaining > 0.0:
		return
	_navigation_repeat_remaining += gamepad_repeat_interval
	_handle_gamepad_navigation(direction)


func _quantize_navigation_direction(input_vector: Vector2) -> Vector2i:
	if input_vector.length() < gamepad_navigation_threshold:
		return Vector2i.ZERO
	if absf(input_vector.x) > absf(input_vector.y):
		return Vector2i(1 if input_vector.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if input_vector.y > 0.0 else -1)


func _handle_gamepad_navigation(direction: Vector2i) -> void:
	_switch_to_gamepad_mode()
	if not _can_use_hotspots():
		return
	var comm := _get_comm_view()
	if comm != null and comm.has_controller_choice_context():
		# COMM 优先且只使用同一套 repeat；左右不移动背后 3D 热点。
		if direction.y != 0:
			comm.focus_controller_choice(direction.y)
		return
	if not _has_hovered_hotspot or not _is_gamepad_focus_valid(_hovered_hotspot):
		_establish_default_gamepad_focus()
	if not _has_hovered_hotspot:
		return
	var next_hotspot := _find_directional_hotspot(_hovered_hotspot, direction)
	if next_hotspot != null:
		_set_hovered_hotspot(next_hotspot)


func _handle_gamepad_confirm() -> bool:
	if not _can_use_hotspots():
		return true
	var comm := _get_comm_view()
	if comm != null and comm.has_controller_choice_context():
		return comm.confirm_controller_choice()
	if not _has_hovered_hotspot or not _is_gamepad_focus_valid(_hovered_hotspot):
		_establish_default_gamepad_focus()
	if not _has_hovered_hotspot or not _is_gamepad_focus_valid(_hovered_hotspot):
		return false
	_execute_action(_hovered_hotspot.get_action_id())
	return true


func _validate_gamepad_focus() -> void:
	var comm := _get_comm_view()
	if comm != null and comm.has_controller_choice_context():
		_clear_hovered_hotspot()
		# 自动展开时，COMM 已接管输入，但 present() 当时可能仍处于最小化状态。
		# 只补建缺失的选项焦点，不覆盖玩家后来选中的有效按钮。
		if not comm.has_controller_choice_focus():
			comm.focus_controller_choice(0)
		return
	if not _can_use_hotspots():
		_clear_hovered_hotspot()
		return
	if _has_hovered_hotspot and not _is_gamepad_focus_valid(_hovered_hotspot):
		_clear_hovered_hotspot()


func _establish_default_gamepad_focus() -> void:
	if _input_mode != InputMode.GAMEPAD or not _can_use_hotspots():
		return
	var comm := _get_comm_view()
	if comm != null and comm.has_controller_choice_context():
		_clear_hovered_hotspot()
		comm.focus_controller_choice(0)
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var best_hotspot: InteractionHotspot3D
	var best_score := INF
	for hotspot in _get_gamepad_candidates():
		var normalized := _get_normalized_screen_position(hotspot, viewport_size)
		var score := normalized.distance_squared_to(Vector2(0.5, 0.5))
		if score < best_score or (is_equal_approx(score, best_score) \
				and _is_path_before(hotspot, best_hotspot)):
			best_hotspot = hotspot
			best_score = score
	if best_hotspot != null:
		_set_hovered_hotspot(best_hotspot)


func _find_directional_hotspot(
		current: InteractionHotspot3D,
		direction: Vector2i
) -> InteractionHotspot3D:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return null
	var current_position := _get_normalized_screen_position(current, viewport_size)
	var direction_vector := Vector2(direction).normalized()
	var perpendicular := Vector2(-direction_vector.y, direction_vector.x)
	var best_hotspot: InteractionHotspot3D
	var best_score := INF
	for candidate in _get_gamepad_candidates():
		if candidate == current:
			continue
		var delta := _get_normalized_screen_position(candidate, viewport_size) \
				- current_position
		var forward := delta.dot(direction_vector)
		var lateral := absf(delta.dot(perpendicular))
		# 限制为约 ±60° 的方向锥，避免边缘键横按时跳到主要位于下方的拨杆。
		if forward <= 0.0001 or forward < lateral * 0.5:
			continue
		var score := forward + lateral * 2.0
		if score < best_score or (is_equal_approx(score, best_score) \
				and _is_path_before(candidate, best_hotspot)):
			best_hotspot = candidate
			best_score = score
	return best_hotspot


func _get_gamepad_candidates() -> Array[InteractionHotspot3D]:
	var candidates: Array[InteractionHotspot3D] = []
	if _view_controller == null or _player_camera == null:
		return candidates
	_collect_gamepad_candidates(_view_controller, candidates)
	return candidates


func _collect_gamepad_candidates(
		node: Node,
		candidates: Array[InteractionHotspot3D]
) -> void:
	if node is InteractionHotspot3D:
		var hotspot := node as InteractionHotspot3D
		# 实体滚轮只由鼠标滚轮和右摇杆驱动，不能成为按 A 无动作的焦点。
		if hotspot.get_action_id() != LEFT_SCROLL_ACTION \
				and _is_hotspot_allowed(hotspot) \
				and not _player_camera.is_position_behind(hotspot.global_position):
			candidates.append(hotspot)
	for child in node.get_children():
		_collect_gamepad_candidates(child, candidates)


func _get_normalized_screen_position(
		hotspot: InteractionHotspot3D,
		viewport_size: Vector2
) -> Vector2:
	var screen_position := _player_camera.unproject_position(hotspot.global_position)
	return Vector2(
		screen_position.x / viewport_size.x,
		screen_position.y / viewport_size.y
	)


func _is_gamepad_focus_valid(hotspot: InteractionHotspot3D) -> bool:
	return is_instance_valid(hotspot) \
			and hotspot.get_action_id() != LEFT_SCROLL_ACTION \
			and _is_hotspot_allowed(hotspot) \
			and not _player_camera.is_position_behind(hotspot.global_position)


func _is_path_before(
		candidate: InteractionHotspot3D,
		current_best: InteractionHotspot3D
) -> bool:
	return current_best == null or String(candidate.get_path()) < String(current_best.get_path())


func _update_context_scroll(delta: float) -> void:
	var strength := Input.get_action_strength(CONTEXT_SCROLL_DOWN_ACTION) \
			- Input.get_action_strength(CONTEXT_SCROLL_UP_ACTION)
	var direction := 0
	if absf(strength) >= context_scroll_threshold:
		direction = 1 if strength > 0.0 else -1
	if direction == 0 or not _can_use_gamepad_context_scroll():
		_scroll_direction = 0
		_scroll_repeat_remaining = 0.0
		return
	_switch_to_gamepad_mode()
	if direction != _scroll_direction:
		_scroll_direction = direction
		_scroll_repeat_remaining = gamepad_initial_repeat_delay
		_execute_left_scroll(direction)
		return
	_scroll_repeat_remaining -= delta
	if _scroll_repeat_remaining > 0.0:
		return
	_scroll_repeat_remaining += gamepad_repeat_interval
	_execute_left_scroll(direction)


func _can_use_gamepad_context_scroll() -> bool:
	if not _can_use_hotspots() or _view_controller.get_current_station_id() != &"left_console":
		return false
	var comm := _get_comm_view()
	return comm == null or not comm.has_controller_choice_context()


func _get_comm_view() -> FloatingCommUI:
	if _console_interface == null:
		return null
	return _console_interface.comm_view


func _reset_gamepad_repeat_state() -> void:
	_navigation_direction = Vector2i.ZERO
	_navigation_repeat_remaining = 0.0
	_scroll_direction = 0
	_scroll_repeat_remaining = 0.0


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
		_interaction_hint_label.text = "%s　｜　%s" % [
			hotspot.get_prompt_text(),
			_default_hint_text,
		]


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
		CAM_01_ACTION, CAM_02_ACTION:
			if _console_interface != null:
				_console_interface.request_select_camera(0 if action_id == CAM_01_ACTION else 1)
		CLOSE_DOOR_ACTION:
			if _console_interface != null:
				_console_interface.request_close_door()
		LEFT_SYSTEM_LOG_ACTION:
			if _building_terminal_interface != null:
				_building_terminal_interface.show_system_log()
		LEFT_PASSENGER_RECORD_ACTION:
			if _building_terminal_interface != null:
				_building_terminal_interface.show_passenger_record()
		LEFT_TRANSCRIPT_ACTION:
			if _building_terminal_interface != null:
				_building_terminal_interface.show_transcript()
		LEFT_SCROLL_ACTION:
			# 滚轮热点只响应鼠标滚轮，不把左键误当成滚动。
			pass
		DESTINATION_CLEAR_ACTION:
			if _destination_interface != null:
				_destination_interface.clear_destination_input()
		DESTINATION_BACKSPACE_ACTION:
			if _destination_interface != null:
				_destination_interface.backspace_destination_input()
		DESTINATION_VERIFY_ACTION:
			if _destination_interface != null:
				_destination_interface.request_verify_destination()
		DESTINATION_SUBMIT_ACTION:
			if _right_console_presentation != null:
				_right_console_presentation.request_submit()
		_:
			var action_text := String(action_id)
			if action_text.begins_with(DESTINATION_DIGIT_PREFIX):
				var digit := action_text.trim_prefix(DESTINATION_DIGIT_PREFIX)
				if _destination_interface != null:
					_destination_interface.append_destination_digit(digit)
				return
			if not _warned_action_ids.has(action_id):
				_warned_action_ids[action_id] = true
				push_warning("未注册的 3D 交互动作：%s" % action_id)


func _execute_left_scroll(direction: int) -> void:
	if _building_terminal_interface != null:
		_building_terminal_interface.scroll_current_content(direction)
	if _left_console_presentation != null:
		_left_console_presentation.rotate_scroll_wheel(direction)


func _on_turn_started(_direction: int, _direction_name: String) -> void:
	_reset_gamepad_repeat_state()
	_clear_hovered_hotspot()


func _on_facing_changed(_direction: int, _direction_name: String) -> void:
	_clear_hovered_hotspot()
	if _input_mode == InputMode.GAMEPAD:
		_establish_default_gamepad_focus()


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

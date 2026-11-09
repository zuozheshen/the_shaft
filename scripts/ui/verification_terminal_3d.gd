class_name VerificationTerminal3D
extends Node3D
## 这里只保存终端表现与本单 UI 会话；业务资料仍通过 #91 的受限端口读取。

signal input_capture_changed(captured: bool)

const TOGGLE_ACTION: StringName = &"verification_terminal_toggle"
const PAD_ACTIONS: Array[StringName] = [
	&"focus_left", &"focus_right", &"focus_up", &"focus_down",
	&"interact_confirm", &"interact_cancel", &"comm_toggle",
	&"context_scroll_up", &"context_scroll_down",
]

@export var view_controller_path: NodePath
@export var interaction_controller_path: NodePath
@export var console_interface_path: NodePath
@export var left_screen_path: NodePath
@export_range(0.5, 0.9, 0.01) var width_fraction: float = 0.78
@export_range(0.5, 0.9, 0.01) var height_fraction: float = 0.78
@export_range(0.5, 1.5, 0.05) var camera_distance: float = 0.9
@export_range(0.1, 0.8, 0.01) var slide_duration: float = 0.32

@onready var shell: Node3D = $Shell
@onready var input_shield: Control = $WorkspaceLayer/InputShield
@onready var screen: PanelContainer = $WorkspaceLayer/InputShield/Screen
@onready var workspace: VerificationWorkspace = %VerificationWorkspace
@onready var close_button: Button = %CloseButton
@onready var session_label: Label = %SessionLabel

var target_open: bool = false
var open_progress: float = 0.0
var _captured: bool = false
var _slide: Tween
var _camera: Camera3D
var _view: CabinViewController3D
var _interaction: CabinInteractionController3D
var _console: ConsoleInterface
var _left_screen: LeftTerminalScreen3D
var _port: Dictionary = {}
var _session_id: int = 0
var _ui_focus: WeakRef
var _pad_needs_neutral: bool = false
var _nav_direction: int = 0
var _nav_remaining: float = 0.0
var _scroll_direction: int = 0
var _scroll_remaining: float = 0.0
var _held_keys: Dictionary = {}

func _ready() -> void:
	_camera = get_parent() as Camera3D
	close_button.pressed.connect(set_open.bind(false))
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_connect_cabin.call_deferred()

func _connect_cabin() -> void:
	_view = get_node(view_controller_path) as CabinViewController3D
	_interaction = get_node(interaction_controller_path) as CabinInteractionController3D
	_console = get_node(console_interface_path) as ConsoleInterface
	_left_screen = get_node(left_screen_path) as LeftTerminalScreen3D
	# 连接局部守卫，不新增全局输入所有者。COMM 在正式空舱中允许不存在。
	input_capture_changed.connect(_view.set_workspace_input_blocked)
	input_capture_changed.connect(_interaction.set_workspace_input_blocked)
	if is_instance_valid(_console.comm_view):
		input_capture_changed.connect(_console.comm_view.set_workspace_input_blocked)
	input_capture_changed.connect(_left_screen.set_workspace_input_blocked)

func set_workspace_port(port: Dictionary) -> void:
	_port = port.duplicate()
	workspace.bind_port(_port, close_button)
	reset_document_session(int(_port["get_session_id"].call()))

func reset_document_session(session: int) -> void:
	if session == _session_id:
		return
	_session_id = session
	workspace.reset_session(session)
	_ui_focus = null
	_refresh_session_label()
	if _captured:
		close_button.grab_focus()

func _refresh_session_label() -> void:
	# 只切换场景里已写好的中性空态，不枚举未取得资料或创建假业务内容。
	session_label.text = session_label.get_meta("idle_text") if _session_id == 0 \
			else "当前派单 / 核验工作区"

func is_input_captured() -> bool:
	return _captured

## 这条展示接线只消费已经取得的单份左台资料，不给 W 新的取得权限。
func open_left_archive_document(session: int, ref: Dictionary) -> void:
	_open_archive_document(session, ref, "left")


func open_right_archive_document(session: int, ref: Dictionary) -> void:
	_open_archive_document(session, ref, "right")


func _open_archive_document(session: int, ref: Dictionary, route: String) -> void:
	if session <= 0 or session != _session_id or _port.is_empty():
		return
	var receipt: Dictionary = _port.get_acquired_document.call(session, ref)
	if receipt.get("route") != route:
		return
	set_open(true)
	workspace.open_retrieved_document(ref)


func set_open(value: bool) -> void:
	if target_open == value:
		return
	target_open = value
	workspace.set_reading_enabled(value)
	if value:
		workspace.refresh()
	if value and not _captured:
		_set_capture(true)
	if is_instance_valid(_slide):
		_slide.kill()
	var endpoint := 1.0 if value else 0.0
	_slide = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_slide.tween_method(_set_progress, open_progress, endpoint,
			maxf(0.001, slide_duration * absf(endpoint - open_progress)))
	_slide.tween_callback(_finish_slide.bind(value))

func _set_progress(value: float) -> void:
	open_progress = value
	_update_layout()

func _finish_slide(opened: bool) -> void:
	if opened != target_open:
		return
	_set_progress(1.0 if opened else 0.0)
	if not opened:
		_set_capture(false)

func _set_capture(value: bool) -> void:
	if _captured == value:
		return
	if not value:
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and screen.is_ancestor_of(focused):
			_ui_focus = weakref(focused)
			focused.release_focus()
	_captured = value
	_nav_direction = 0
	_scroll_direction = 0
	_pad_needs_neutral = value
	_update_layout()
	input_capture_changed.emit(value)
	if value:
		var restored := _ui_focus.get_ref() as Control if _ui_focus != null else null
		if is_instance_valid(restored) and restored.is_visible_in_tree():
			restored.grab_focus()
		else:
			close_button.grab_focus()

func _input(event: InputEvent) -> void:
	# W 先于 GUI 的默认 ui_up；释放和 echo 也消费，但只在非 echo 按下时切换。
	if event.is_action(TOGGLE_ACTION):
		if event.is_action_pressed(TOGGLE_ACTION) and not event.is_echo():
			set_open(not target_open)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if _captured:
			if event.pressed:
				_held_keys[code] = true
			else:
				_held_keys.erase(code)
		elif _held_keys.has(code):
			if not event.pressed:
				_held_keys.erase(code)
			get_viewport().set_input_as_handled()
			return
	if not _captured:
		return
	if not target_open:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if target_open and not _pad_needs_neutral:
			if event.is_action_pressed(&"interact_cancel"):
				set_open(false)
			elif event.is_action_pressed(&"interact_confirm"):
				workspace.confirm_focus()
		get_viewport().set_input_as_handled()

	# 键盘与鼠标先交给聚焦的工作区 GUI；后台事件和轮询已有显式守卫。
	if event is InputEventKey:
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not screen.is_ancestor_of(focused):
			close_button.grab_focus()

func _shortcut_input(event: InputEvent) -> void:
	# GUI 之后再拦截剩余按键；不能在 _input 吞掉 Tab/Enter/Space。
	if _captured and event is InputEventKey:
		get_viewport().set_input_as_handled()

func refresh_documents(session: int) -> void:
	workspace.refresh(session)

func _process(delta: float) -> void:
	if not _captured or not target_open:
		return
	if _pad_needs_neutral:
		if _pad_controls_neutral():
			_pad_needs_neutral = false
		return
	var axis := Vector2(
		Input.get_action_strength(&"focus_right") - Input.get_action_strength(&"focus_left"),
		Input.get_action_strength(&"focus_down") - Input.get_action_strength(&"focus_up"))
	var strongest := axis.x if absf(axis.x) > absf(axis.y) else axis.y
	var direction := int(signf(strongest)) if absf(strongest) >= 0.55 else 0
	if direction == 0:
		_nav_direction = 0
	elif direction != _nav_direction:
		_nav_direction = direction
		_nav_remaining = 0.35
		_move_focus(direction)
	else:
		_nav_remaining -= delta
		if _nav_remaining <= 0.0:
			_nav_remaining = 0.12
			_move_focus(direction)
	var scroll_axis := Input.get_action_strength(&"context_scroll_down") \
			- Input.get_action_strength(&"context_scroll_up")
	var scroll_step := int(signf(scroll_axis)) if absf(scroll_axis) >= 0.55 else 0
	if scroll_step == 0:
		_scroll_direction = 0
	elif scroll_step != _scroll_direction:
		_scroll_direction = scroll_step
		_scroll_remaining = 0.35
		workspace.scroll_active(scroll_step * 96)
	else:
		_scroll_remaining -= delta
		if _scroll_remaining <= 0.0:
			_scroll_remaining = 0.12
			workspace.scroll_active(scroll_step * 96)

func _pad_controls_neutral() -> bool:
	for action in PAD_ACTIONS:
		if Input.get_action_strength(action) >= 0.2:
			return false
	return true

func _move_focus(direction: int) -> void:
	workspace.move_focus(direction)

func get_screen_rect() -> Rect2:
	if _camera == null:
		return Rect2()
	var top_left := _camera.unproject_position(shell.to_global(Vector3(-0.84, 0.44, 0.025)))
	var bottom_right := _camera.unproject_position(shell.to_global(Vector3(0.84, -0.44, 0.025)))
	return Rect2(top_left, bottom_right - top_left)

func _update_layout() -> void:
	if not is_node_ready() or _camera == null:
		return
	var available := get_viewport().get_visible_rect().size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var left := _camera.to_local(_camera.project_position(Vector2.ZERO, camera_distance))
	var right := _camera.to_local(_camera.project_position(available, camera_distance))
	var span := Vector2(absf(right.x - left.x), absf(right.y - left.y))
	# 灰盒宽高可独立校准；按视口宽度而不是总面积控制占比。
	shell.scale = Vector3(span.x * width_fraction / 2.24,
			span.y * height_fraction / 1.52, minf(span.x, span.y) * 0.52)
	var travel := Vector2(span.x * (0.5 + width_fraction * 0.65),
			span.y * (0.5 + height_fraction * 0.75))
	shell.position = Vector3(travel.x * (1.0 - open_progress),
			travel.y * (1.0 - open_progress), -camera_distance)
	shell.visible = open_progress > 0.0
	input_shield.visible = _captured
	var rect := get_screen_rect()
	screen.position = rect.position
	screen.size = rect.size.max(Vector2.ONE)

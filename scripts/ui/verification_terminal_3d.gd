class_name VerificationTerminal3D
extends Node3D
## 这里只保存终端表现与本单 UI 会话；业务资料仍通过 #91 的受限端口读取。

signal input_capture_changed(captured: bool)

# 机壳包络来自 Blender 导出，前缘留少量余量给螺丝头。用于计算画面容纳尺寸。
const HOUSING_HALF_SIZE := Vector2(0.310, 0.192)
const HOUSING_FRONT := 0.031
const HOUSING_BACK := 0.040

const TOGGLE_ACTION: StringName = &"verification_terminal_toggle"
const PAD_ACTIONS: Array[StringName] = [
	&"focus_left", &"focus_right", &"focus_up", &"focus_down",
	&"interact_confirm", &"interact_cancel",
	&"context_scroll_up", &"context_scroll_down",
]

@export var view_controller_path: NodePath
@export var interaction_controller_path: NodePath
@export var left_screen_path: NodePath
@export_range(0.5, 0.9, 0.01) var width_fraction: float = 0.78
@export_range(0.5, 0.9, 0.01) var height_fraction: float = 0.78
@export_range(0.5, 1.5, 0.05) var camera_distance: float = 0.9
@export_range(0.1, 0.8, 0.01) var slide_duration: float = 0.32

@onready var shell: Node3D = $Shell
@onready var screen_corners: Node3D = $Shell/ScreenCorners
@onready var input_shield: Control = $WorkspaceLayer/InputShield
@onready var screen: PanelContainer = $WorkspaceLayer/InputShield/Screen
@onready var workspace: VerificationWorkspace = %VerificationWorkspace
@onready var close_button: Button = %CloseButton

var target_open: bool = false
var open_progress: float = 0.0
var _captured: bool = false
var _slide: Tween
var _camera: Camera3D
var _view: CabinViewController3D
var _interaction: CabinInteractionController3D
var _left_screen: LeftTerminalScreen3D
var _port: Dictionary = {}
var _session_id: int = 0
var _ui_focus: WeakRef
var _pad_needs_neutral: bool = false
var _statement_confirm_held := false
var _nav_direction: int = 0
var _nav_remaining: float = 0.0
var _scroll_direction: int = 0
var _scroll_remaining: float = 0.0
var _held_keys: Dictionary = {}

func _ready() -> void:
	screen.theme = preload("res://scripts/ui/terminal_ui_style.gd").make_theme(20)
	_camera = get_parent() as Camera3D
	close_button.pressed.connect(set_open.bind(false))
	get_viewport().size_changed.connect(_update_layout)
	get_window().focus_exited.connect(_on_focus_exited)
	_update_layout()
	_connect_cabin.call_deferred()

func _connect_cabin() -> void:
	_view = get_node(view_controller_path) as CabinViewController3D
	_interaction = get_node(interaction_controller_path) as CabinInteractionController3D
	_left_screen = get_node(left_screen_path) as LeftTerminalScreen3D
	# 连接 W 的局部输入守卫。
	input_capture_changed.connect(_view.set_workspace_input_blocked)
	input_capture_changed.connect(_interaction.set_workspace_input_blocked)
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
	if _captured and open_progress >= 1.0:
		close_button.grab_focus()

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
	# 动画期间继续拦截后台，正文只在完全打开后接收操作。
	workspace.set_reading_enabled(false)
	_pad_needs_neutral = true
	_nav_direction = 0
	_scroll_direction = 0
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
	if opened:
		workspace.set_reading_enabled(true)
		var focused := get_viewport().gui_get_focus_owner()
		if not _is_screen_focus(focused):
			var restored := _ui_focus.get_ref() as Control if _ui_focus != null else null
			if _is_screen_focus(restored):
				restored.grab_focus()
			else:
				close_button.grab_focus()
	else:
		_set_capture(false)


func _is_screen_focus(control: Control) -> bool:
	return is_instance_valid(control) and control.is_visible_in_tree() \
			and control.focus_mode != Control.FOCUS_NONE and screen.is_ancestor_of(control) \
			and (not control is BaseButton or not (control as BaseButton).disabled)


func _on_focus_exited() -> void:
	if _captured:
		workspace.cancel_pointer_interaction()
		_pad_needs_neutral = true
		_nav_direction = 0
		_scroll_direction = 0

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
	if not target_open or open_progress < 1.0:
		if target_open and (event.is_action_pressed(&"interact_cancel")
				or event.is_action_pressed(&"ui_cancel")) and not event.is_echo():
			set_open(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event.is_action_released(&"interact_confirm"):
			_statement_confirm_held = false
		if not _pad_needs_neutral:
			if event.is_action_pressed(&"interact_cancel"):
				if not workspace.cancel_statement_selection():
					set_open(false)
			elif event.is_action_pressed(&"interact_confirm") and not _statement_confirm_held:
				_statement_confirm_held = not workspace.statement_documents.is_empty()
				workspace.confirm_focus()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.is_action_pressed(&"ui_cancel") and not event.is_echo() \
			and not workspace.statement_documents.is_empty():
		if not workspace.cancel_statement_selection():
			set_open(false)
		get_viewport().set_input_as_handled()
		return

	# 键盘与鼠标先交给聚焦的工作区 GUI；后台事件和轮询已有显式守卫。
	if event is InputEventKey:
		var focused := get_viewport().gui_get_focus_owner()
		if not _is_screen_focus(focused):
			close_button.grab_focus()

func _shortcut_input(event: InputEvent) -> void:
	# GUI 之后再拦截剩余按键；不能在 _input 吞掉 Tab/Enter/Space。
	if _captured and event is InputEventKey:
		get_viewport().set_input_as_handled()

func refresh_documents(session: int) -> void:
	workspace.refresh(session)

func _process(delta: float) -> void:
	if not _captured or not target_open or open_progress < 1.0:
		return
	if _pad_needs_neutral:
		if _pad_controls_neutral():
			_pad_needs_neutral = false
			_statement_confirm_held = false
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
	# 四角位于模型的同一内凹平面，直接使用机壳的当前变换。
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner: Marker3D in screen_corners.get_children():
		var pixel := _camera.unproject_position(corner.global_position)
		minimum = minimum.min(pixel)
		maximum = maximum.max(pixel)
	return Rect2(minimum, maximum - minimum)

func _update_layout() -> void:
	if not is_node_ready() or _camera == null:
		return
	var available := get_viewport().get_visible_rect().size
	if available.x <= 0.0 or available.y <= 0.0:
		return
	var left := _camera.to_local(_camera.project_position(Vector2.ZERO, camera_distance))
	var right := _camera.to_local(_camera.project_position(available, camera_distance))
	var span := Vector2(absf(right.x - left.x), absf(right.y - left.y))
	# 从前缘的投影解出宽、高各自的缩放上限，整个机壳取同一个较小值。
	var fit := span * Vector2(width_fraction, height_fraction)
	var limit := fit / (HOUSING_HALF_SIZE * 2.0 + fit * HOUSING_FRONT / camera_distance)
	var uniform_scale := minf(limit.x, limit.y)
	shell.scale = Vector3.ONE * uniform_scale
	# 用最远后壳平面计算关闭端，确保机身完全退出画面下沿。
	var back_span := span.y * (1.0 + HOUSING_BACK * uniform_scale / camera_distance)
	var travel_y := back_span * 0.54 + HOUSING_HALF_SIZE.y * uniform_scale
	shell.position = Vector3(0.0, -travel_y * (1.0 - open_progress), -camera_distance)
	shell.visible = open_progress > 0.0
	input_shield.visible = _captured
	var rect := get_screen_rect()
	screen.position = rect.position
	screen.size = rect.size.max(Vector2.ONE)

class_name FloatingCommUI
extends PanelContainer


signal choice_selected(index: int)

@export var expanded_size: Vector2 = Vector2(440, 320)
@export var minimized_height: float = 52.0

@onready var speech_label: Label = %PassengerSpeechLabel
@onready var choice_container: VBoxContainer = %DialogueChoices
@onready var content_scroll: ScrollContainer = %ContentScroll
@onready var title_bar: Control = %TitleBar
@onready var minimize_button: Button = %MinimizeButton

# 这里只记窗口表现；MIC、台词和可推进的对话状态仍由 ConsoleInterface 持有。
var _minimized: bool = true
var _manually_minimized: bool = false
var _dragging: bool = false
var _drag_offset: Vector2


func _ready() -> void:
	title_bar.gui_input.connect(_on_title_input)
	minimize_button.pressed.connect(_toggle_minimized)
	get_viewport().size_changed.connect(_fit_window)
	_fit_window.call_deferred()


func present(mic_on: bool, line: String, choices: Array[Dictionary],
		can_choose: bool, has_dialogue: bool) -> void:
	speech_label.text = line
	# 保留同一索引的 Button，避免刷新时重复连接或丢失焦点。
	while choice_container.get_child_count() > choices.size():
		var old_button := choice_container.get_child(-1)
		choice_container.remove_child(old_button)
		old_button.queue_free()
	while choice_container.get_child_count() < choices.size():
		var index: int = choice_container.get_child_count()
		var button := Button.new()
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 38.0
		button.pressed.connect(_on_choice_pressed.bind(index))
		choice_container.add_child(button)
	for index in choices.size():
		var button := choice_container.get_child(index) as Button
		button.text = str(choices[index].get("text", ""))
		button.disabled = not can_choose or not bool(choices[index].get("is_allowed", true))
	choice_container.visible = can_choose and not choices.is_empty()
	if not mic_on:
		set_minimized(true, false)
	elif has_dialogue and not _manually_minimized:
		set_minimized(false, false)


func _on_choice_pressed(index: int) -> void:
	choice_selected.emit(index)


func _toggle_minimized() -> void:
	set_minimized(not _minimized)


func set_minimized(value: bool, by_player: bool = true) -> void:
	if by_player:
		_manually_minimized = value
	if _minimized == value:
		return
	_minimized = value
	_fit_window()


func is_minimized() -> bool:
	return _minimized


func blocks_pointer(viewport_position: Vector2) -> bool:
	# 左台在 GUI 之前处理输入，因此必须用当前事件坐标判断，不能借用旧 hover。
	return is_visible_in_tree() and (
		_dragging or get_global_rect().has_point(viewport_position)
	)


func _on_title_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	_dragging = true
	_drag_offset = get_viewport().get_mouse_position() - global_position
	accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		move_window_to(event.position - _drag_offset)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_dragging = false
		get_viewport().set_input_as_handled()


func move_window_to(target: Vector2) -> void:
	var viewport_rect := get_viewport_rect()
	var maximum := viewport_rect.position + (viewport_rect.size - size).max(Vector2.ZERO)
	global_position = target.clamp(viewport_rect.position, maximum)


func _fit_window() -> void:
	if not is_node_ready():
		return
	content_scroll.visible = not _minimized
	minimize_button.text = "+" if _minimized else "−"
	minimize_button.tooltip_text = "展开通讯" if _minimized else "最小化通讯"
	var available := get_viewport_rect().size
	var target := Vector2(expanded_size.x, minimized_height if _minimized else expanded_size.y)
	target = target.min(available)
	var chrome_height: float = get_theme_stylebox("panel").get_minimum_size().y \
			+ title_bar.get_parent().get_combined_minimum_size().y \
			+ $Layout.get_theme_constant("separation")
	content_scroll.custom_minimum_size.y = maxf(0.0, target.y - chrome_height)
	size = target
	move_window_to(global_position)
	# Container 的最小尺寸在布局队列刷新后确定，再夹紧一次防止边缘溢出。
	_clamp_current_position.call_deferred()


func _clamp_current_position() -> void:
	# 不能把排队时的坐标带入回调，否则会覆盖玩家这期间完成的拖动。
	move_window_to(global_position)

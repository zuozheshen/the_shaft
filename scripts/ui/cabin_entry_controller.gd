class_name CabinEntryController
extends Node
## 只管理玩家进入工作台前的视角与菜单，不拥有派单状态。

const Style := preload("res://scripts/ui/terminal_ui_style.gd")
enum Phase { REST, SITTING_UP, WORK }

@export_range(0.05, 2.0, 0.05) var sit_up_duration := 0.65

@onready var cabin: CabinViewController3D = $"../三维操作舱"
@onready var terminal: VerificationTerminal3D = cabin.find_child("核验终端", true, false)
@onready var menu: CanvasLayer = $"../休息菜单"
@onready var actions: VBoxContainer = menu.get_node("InputShield/Actions")
@onready var start_button: Button = actions.get_node("Start")
@onready var settings_button: Button = actions.get_node("Settings")

var phase := Phase.REST
var _pad_direction := 0
var _developer_origin := Origin.NONE
var _developer_queued := false
var _paused_before := false

enum Origin { NONE, REST, STATION, DOCUMENTS }


func _ready() -> void:
	actions.theme = Style.make_theme(34)
	start_button.pressed.connect(start_duty)
	settings_button.pressed.connect(_request_developer)
	terminal.developer_requested.connect(_request_developer)
	terminal.slide_finished.connect(_on_terminal_slide)
	cabin.facing_changed.connect(func(_direction: int, _name: String) -> void:
		if phase == Phase.WORK:
			_open_queued_developer.call_deferred())
	terminal.developer_panel.back_requested.connect(_return_from_developer)
	var connector: RuntimeConnector3D = $"../运行层连接器"
	terminal.developer_panel.quit_requested.connect(connector.request_quit.bind(0))
	terminal.developer_panel.bindings_changed.connect(cabin.refresh_operation_hint)
	_load_settings.call_deferred()
	terminal.set_entry_blocked(true)
	cabin.show_rest_pose()
	start_button.grab_focus()


func start_duty() -> void:
	if phase != Phase.REST or not menu.visible:
		return
	phase = Phase.SITTING_UP
	start_button.disabled = true
	settings_button.disabled = true
	var tween := create_tween()
	tween.tween_property(actions, ^"modulate:a", 0.0, minf(0.15, sit_up_duration))
	await cabin.sit_up(sit_up_duration)
	menu.hide()
	phase = Phase.WORK
	if _developer_queued:
		_open_queued_developer()
	terminal.set_entry_blocked(false)


func _load_settings() -> void:
	# 测试/预览实例不读取或应用玩家的全局设置。
	if get_parent() != get_tree().current_scene or DisplayServer.get_name() == "headless":
		return
	var settings := terminal.developer_panel.store
	settings.load_settings()
	settings.apply_audio()
	settings.apply_keys()
	settings.apply_display(settings.fullscreen, settings.window_size)
	cabin.refresh_operation_hint()


func _request_developer() -> void:
	if _developer_origin != Origin.NONE:
		return
	if phase == Phase.SITTING_UP or terminal.is_sliding() or cabin.is_turning():
		_developer_queued = true
		return
	if phase == Phase.REST:
		_developer_origin = Origin.REST
		menu.hide()
	else:
		_developer_origin = Origin.DOCUMENTS if terminal.target_open else Origin.STATION
	_paused_before = get_tree().paused
	get_tree().paused = true
	terminal.show_developer_page(_developer_origin == Origin.DOCUMENTS)


func _return_from_developer() -> void:
	if _developer_origin == Origin.NONE:
		return
	var documents := _developer_origin == Origin.DOCUMENTS
	terminal.hide_developer_page(documents)
	if documents:
		_finish_developer_return()


func _on_terminal_slide(opened: bool) -> void:
	if not opened and _developer_origin != Origin.NONE:
		_finish_developer_return()
	elif _developer_origin == Origin.NONE:
		_open_queued_developer.call_deferred()


func _open_queued_developer() -> void:
	if _developer_queued:
		_developer_queued = false
		_request_developer()


func _finish_developer_return() -> void:
	var rest := _developer_origin == Origin.REST
	_developer_origin = Origin.NONE
	get_tree().paused = _paused_before
	if rest:
		menu.show()
		settings_button.grab_focus()


func _process(_delta: float) -> void:
	if phase != Phase.REST or not menu.visible:
		return
	var axis := Input.get_action_strength(&"focus_down") - Input.get_action_strength(&"focus_up")
	var direction := int(signf(axis)) if absf(axis) >= 0.55 else 0
	if direction != 0 and direction != _pad_direction:
		var target := start_button if direction < 0 else settings_button
		target.grab_focus()
	_pad_direction = direction

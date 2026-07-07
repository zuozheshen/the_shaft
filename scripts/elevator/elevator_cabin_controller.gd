extends Control


enum FacingDirection {
	FRONT,
	RIGHT,
	BACK,
	LEFT,
}


const DIRECTION_NAMES: Array[String] = ["FRONT", "RIGHT", "BACK", "LEFT"]
const FACING_OBJECTS: Array[String] = ["主调度台", "日志台", "后方舱壁", "监控台"]

const CONSOLE_DESCRIPTIONS: Dictionary = {
	FacingDirection.FRONT: "这里以后显示派单、路线建议和门控。",
	FacingDirection.RIGHT: "这里以后显示本次送达记录和日志选项。",
	FacingDirection.LEFT: "这里以后显示摄像头矩阵和乘客舱画面。",
}

var current_direction: int = FacingDirection.FRONT

@onready var cabin_view: Control = %CabinView
@onready var direction_label: Label = %DirectionLabel
@onready var facing_object_label: Label = %FacingObjectLabel
@onready var interaction_hint_label: Label = %InteractionHintLabel
@onready var console_interface: ConsoleInterface = %ConsoleInterface
@onready var demo_flow_manager: DemoFlowManager = get_node_or_null("../DemoFlowManager") as DemoFlowManager


func _ready() -> void:
	console_interface.set_demo_flow_manager(demo_flow_manager)
	console_interface.return_requested.connect(_exit_console)
	_update_cabin_text()


func _input(event: InputEvent) -> void:
	if console_interface.visible:
		return

	if _is_key_pressed(event, KEY_Q):
		_rotate_left()
	elif _is_key_pressed(event, KEY_E):
		_rotate_right()
	elif event.is_action_pressed("ui_accept") or _is_key_pressed(event, KEY_W):
		_interact_with_facing_object()
	else:
		return

	get_viewport().set_input_as_handled()


func _rotate_left() -> void:
	current_direction = wrapi(current_direction - 1, 0, FacingDirection.size())
	_update_cabin_text()


func _rotate_right() -> void:
	current_direction = wrapi(current_direction + 1, 0, FacingDirection.size())
	_update_cabin_text()


func _interact_with_facing_object() -> void:
	if current_direction == FacingDirection.BACK:
		interaction_hint_label.text = "后方没有可用操作台。"
		return

	console_interface.show_console(
		DIRECTION_NAMES[current_direction],
		FACING_OBJECTS[current_direction],
		CONSOLE_DESCRIPTIONS[current_direction]
	)
	cabin_view.hide()


func _exit_console() -> void:
	console_interface.hide()
	cabin_view.show()
	_update_cabin_text()


func _update_cabin_text() -> void:
	direction_label.text = "当前朝向：%s" % DIRECTION_NAMES[current_direction]
	facing_object_label.text = "当前面对：%s" % FACING_OBJECTS[current_direction]
	if current_direction == FacingDirection.BACK:
		interaction_hint_label.text = "Q / E 转向　W / Enter 检查后方"
	else:
		interaction_hint_label.text = "Q / E 转向　W / Enter 进入操作台"


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)

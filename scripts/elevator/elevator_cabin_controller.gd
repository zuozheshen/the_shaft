extends Control


# 四个方向按顺时针排列，便于 Q / E 使用循环索引完成转向。
enum FacingDirection {
	FRONT,
	RIGHT,
	BACK,
	LEFT,
}


const DIRECTION_NAMES: Array[String] = ["FRONT", "RIGHT", "BACK", "LEFT"]
const FACING_OBJECTS: Array[String] = ["主调度台", "目标楼层控制台", "后方舱壁", "建筑终端"]

const CONSOLE_DESCRIPTIONS: Dictionary = {
	FacingDirection.FRONT: "这里以后显示派单、路线建议和门控。",
	FacingDirection.RIGHT: "这里用于确认系统推荐或手动输入的目标楼层。",
	FacingDirection.LEFT: "这里显示系统日志、乘客档案和对话记录。",
}

var current_direction: int = FacingDirection.FRONT

# 使用场景中的唯一节点名取得界面引用，集中声明便于新手看清控制器依赖。
@onready var cabin_view: Control = %CabinView
@onready var direction_label: Label = %DirectionLabel
@onready var facing_object_label: Label = %FacingObjectLabel
@onready var interaction_hint_label: Label = %InteractionHintLabel
@onready var console_interface: ConsoleInterface = %ConsoleInterface
@onready var building_terminal_interface: BuildingTerminalInterface = %BuildingTerminalInterface
@onready var destination_control_interface: DestinationControlInterface = %DestinationControlInterface
@onready var demo_flow_manager: DemoFlowManager = get_node_or_null("../DemoFlowManager") as DemoFlowManager


func _ready() -> void:
	# 控制器负责把流程管理器交给操作台，并监听操作台发出的退出请求。
	console_interface.set_demo_flow_manager(demo_flow_manager)
	console_interface.set_destination_control_interface(destination_control_interface)
	console_interface.return_requested.connect(_exit_console)
	# LEFT 使用独立建筑终端，并沿用 FRONT 的返回流程恢复操作间。
	building_terminal_interface.set_demo_flow_manager(demo_flow_manager)
	building_terminal_interface.return_requested.connect(_exit_building_terminal)
	# RIGHT 目标楼层控制台只负责目标确认，并沿用相同的返回操作间流程。
	destination_control_interface.set_demo_flow_manager(demo_flow_manager)
	destination_control_interface.return_requested.connect(_exit_destination_control)
	_update_cabin_text()


func _input(event: InputEvent) -> void:
	# 操作台打开后由 ConsoleInterface 接管 S / Esc 等输入，避免舱内操作同时触发。
	if console_interface.visible or building_terminal_interface.visible \
			or destination_control_interface.visible:
		return

	# Q / E 左右转向；W 或 ui_accept（Enter / Space）检查当前面对的操作台。
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
	# wrapi 让方向在 FRONT、LEFT、BACK、RIGHT 之间首尾循环。
	current_direction = wrapi(current_direction - 1, 0, FacingDirection.size())
	_update_cabin_text()


func _rotate_right() -> void:
	current_direction = wrapi(current_direction + 1, 0, FacingDirection.size())
	_update_cabin_text()


func _interact_with_facing_object() -> void:
	# BACK 只有舱壁，没有可进入的操作台，因此只更新提示文字。
	if current_direction == FacingDirection.BACK:
		interaction_hint_label.text = "后方没有可用操作台。"
		return

	# LEFT 打开系统复核终端，RIGHT 打开目标楼层控制台，FRONT 保留主仲裁台行为。
	if current_direction == FacingDirection.LEFT:
		building_terminal_interface.show_terminal()
		cabin_view.hide()
		return
	if current_direction == FacingDirection.RIGHT:
		destination_control_interface.show_destination_console()
		cabin_view.hide()
		return

	console_interface.show_console(
		DIRECTION_NAMES[current_direction],
		FACING_OBJECTS[current_direction],
		CONSOLE_DESCRIPTIONS[current_direction]
	)
	cabin_view.hide()


func _exit_console() -> void:
	# 收到返回请求后恢复舱内视图，玩家可以继续转向或进入其他操作台。
	console_interface.hide()
	cabin_view.show()
	_update_cabin_text()


func _exit_building_terminal() -> void:
	building_terminal_interface.hide()
	cabin_view.show()
	_update_cabin_text()


func _exit_destination_control() -> void:
	destination_control_interface.hide()
	cabin_view.show()
	_update_cabin_text()


func _update_cabin_text() -> void:
	# 每次转向或退出操作台后同步朝向、对象和可用操作提示。
	direction_label.text = "当前朝向：%s" % DIRECTION_NAMES[current_direction]
	facing_object_label.text = "当前面对：%s" % FACING_OBJECTS[current_direction]
	if current_direction == FacingDirection.BACK:
		interaction_hint_label.text = "Q / E 转向　W / Enter 检查后方"
	else:
		interaction_hint_label.text = "Q / E 转向　W / Enter 进入操作台"


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)

extends Control
class_name ConsoleInterface


signal return_requested


# 这些引用对应操作台场景中的界面模块，统一声明便于看清显示与按钮依赖。
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var dispatch_panel: Control = %DispatchPanel
@onready var state_label: Label = %StateLabel
@onready var door_control_panel: Control = %DoorControlPanel
@onready var open_door_button: Button = %OpenDoorButton
@onready var delay_door_button: Button = %DelayDoorButton
@onready var close_door_button: Button = %CloseDoorButton
@onready var flow_control_panel: Control = %FlowControlPanel
@onready var advance_state_button: Button = %AdvanceStateButton
@onready var system_hint_label: Label = %SystemHintLabel
@onready var return_button: Button = %ReturnButton

var demo_flow_manager: DemoFlowManager


func _ready() -> void:
	# 主调度台的门控按钮只输出原型操作记录，三个按钮共用同一个处理函数。
	open_door_button.pressed.connect(_print_door_action.bind("开门"))
	delay_door_button.pressed.connect(_print_door_action.bind("延迟关门"))
	close_door_button.pressed.connect(_print_door_action.bind("关门"))
	# 推进按钮调用流程管理器；返回按钮通过信号通知舱体控制器退出界面。
	advance_state_button.pressed.connect(_advance_state)
	return_button.pressed.connect(_request_return)


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		return

	# 监听状态变化后即时刷新文字，并防止重复连接同一个信号。
	if not demo_flow_manager.state_changed.is_connected(_update_state_label):
		demo_flow_manager.state_changed.connect(_update_state_label)
	_update_state_label(demo_flow_manager.get_current_state_name())


func show_console(
		console_type: String,
		console_name: String,
		console_description: String
) -> void:
	# FRONT 是主调度台，需要显示调度、门控和流程按钮；其他方向只显示各自说明。
	var is_main_dispatch_console: bool = console_type == "FRONT"
	title_label.text = console_name
	description_label.text = console_description
	dispatch_panel.visible = is_main_dispatch_console
	door_control_panel.visible = is_main_dispatch_console
	flow_control_panel.visible = is_main_dispatch_console
	system_hint_label.visible = is_main_dispatch_console

	if is_main_dispatch_console and demo_flow_manager != null:
		_update_state_label(demo_flow_manager.get_current_state_name())

	show()
	# 默认焦点跟随当前操作台类型，键盘玩家可直接继续操作或返回。
	if is_main_dispatch_console:
		advance_state_button.grab_focus()
	else:
		return_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# 操作台可用 Esc（ui_cancel）或 S 退出，与舱内进入操作形成清晰对应。
	if event.is_action_pressed("ui_cancel") or _is_key_pressed(event, KEY_S):
		_request_return()
		get_viewport().set_input_as_handled()


func _request_return() -> void:
	# 界面只发送退出意图，具体恢复舱内视图由外层控制器负责。
	return_requested.emit()


func _print_door_action(action_name: String) -> void:
	print("Door action: ", action_name)


func _advance_state() -> void:
	# 流程管理器缺失时保留界面可运行，并用警告提示场景连接问题。
	if demo_flow_manager == null:
		push_warning("ConsoleInterface: DemoFlowManager is not connected.")
		return

	demo_flow_manager.advance_state()


func _update_state_label(new_state_name: String) -> void:
	state_label.text = "当前状态：%s" % new_state_name


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)

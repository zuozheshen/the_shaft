extends Control
class_name ConsoleInterface


signal return_requested


const CAMERA_FEEDS: Array[Dictionary] = [
	{
		"name": "CAM 01｜主摄像头",
		"feed": "画面占位：乘客站在舱内。面部、衣物、证件和说话状态等待接入。",
	},
	{
		"name": "CAM 02｜地面摄像头",
		"feed": "画面占位：地面区域。鞋印、液体、拖拽痕迹和第二组影子等待接入。",
	},
	{
		"name": "CAM 03｜门外摄像头",
		"feed": "画面占位：门外三到五米切片。楼层状态、等待者和异常痕迹等待接入。",
	},
]

# 场景缺少流程管理器时使用的对话 fallback；正常运行从 current_case 读取。
const DIALOGUE_NODES: Array = [
	[
		{
			"operator": "下面是哪一层？",
			"passenger": "乘客：我不知道编号。只是比这里更低。",
			"status_hint": "目的地解析失败。乘客无法提供标准楼层编号，建议复核历史路线或保持门控关闭。",
		},
		{
			"operator": "你的申请记录显示目标是 900 层。",
			"passenger": "乘客：记录是旧的。那不是我要去的地方。",
			"status_hint": "乘客自述与派单记录冲突。建筑建议查看 RECORD 页，确认近期路线重复情况。",
		},
		{
			"operator": "你看起来不想去系统给你的地方。",
			"passenger": "乘客：你们总是这么说，好像我要去哪里是我决定的。",
			"status_hint": "检测到乘客对路线自主权存在抵触。建议降低询问强度，避免立即开门。",
		},
		{
			"operator": "先留在舱内，等我确认路线。",
			"passenger": "乘客：可以。但别让门开太久。那边会听见。",
			"status_hint": "乘客对门外环境表现出回避。建议查看门外摄像头，并保持乘客舱隔离。",
		},
	],
	[
		{
			"operator": "我会先保持门关闭。",
			"passenger": "乘客：谢谢。至少现在不要开。",
			"status_hint": "乘客明确请求维持隔离。建筑建议保持门控关闭，等待路线复核。",
		},
		{
			"operator": "我需要查看地面摄像头。",
			"passenger": "乘客：别看地上。那不是我的影子。",
			"status_hint": "乘客主动提及影子异常。建议切换至地面摄像头，并标记现场证据。",
		},
		{
			"operator": "门外是什么地方？",
			"passenger": "乘客：我不确定。灯太稳了。",
			"status_hint": "乘客描述门外灯候异常。建筑提示：过度稳定可能表示目标楼层状态不可信。",
		},
		{
			"operator": "暂时结束通话。",
			"passenger": "乘客：好。别把我写成异常。",
			"status_hint": "乘客担心异常归档。建议谨慎填写后续记录，避免过早上报。",
		},
	],
]


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

# 新增节点在运行时安全查找，缺少单个占位节点不会阻止 Issue 5 的旧功能运行。
var passenger_monitor_panel: Control
var monitor_title_label: Label
var camera_name_label: Label
var monitor_feed_label: Label
var passenger_speech_label: Label
var previous_camera_button: Button
var next_camera_button: Button
var intercom_panel: Control
var mic_status_label: Label
var talk_button: Button
var dialogue_choice_panel: Control
var dialogue_prompt_label: Label
var dialogue_choice_buttons: Array[Button] = []

var demo_flow_manager: DemoFlowManager
var active_console_type: String = ""
var current_camera_index: int = 0
var mic_enabled: bool = false
var dialogue_node_index: int = 0
var dialogue_started: bool = false
var dialogue_finished: bool = false
var current_passenger_line: String = "乘客舱音频链路待机。"

func _ready() -> void:
	_cache_front_interaction_nodes()
	# 三个门控按钮共用处理函数，同时把操作同步给 LEFT 的临时事件缓存。
	open_door_button.pressed.connect(_print_door_action.bind("开门"))
	delay_door_button.pressed.connect(_print_door_action.bind("延迟关门"))
	close_door_button.pressed.connect(_print_door_action.bind("关门"))
	# 推进按钮调用流程管理器；返回按钮通过信号通知舱体控制器退出界面。
	advance_state_button.pressed.connect(_advance_state)
	return_button.pressed.connect(_request_return)
	_connect_front_interaction_signals()
	_initialize_front_interaction()


func _cache_front_interaction_nodes() -> void:
	passenger_monitor_panel = _find_optional_node("PassengerMonitorPanel") as Control
	monitor_title_label = _find_optional_node("MonitorTitleLabel") as Label
	camera_name_label = _find_optional_node("CameraNameLabel") as Label
	monitor_feed_label = _find_optional_node("MonitorFeedLabel") as Label
	passenger_speech_label = _find_optional_node("PassengerSpeechLabel") as Label
	previous_camera_button = _find_optional_node("PrevCameraButton") as Button
	next_camera_button = _find_optional_node("NextCameraButton") as Button
	intercom_panel = _find_optional_node("IntercomPanel") as Control
	mic_status_label = _find_optional_node("MicStatusLabel") as Label
	talk_button = _find_optional_node("TalkButton") as Button
	dialogue_choice_panel = _find_optional_node("DialogueChoicePanel") as Control
	dialogue_prompt_label = _find_optional_node("DialoguePromptLabel") as Label

	for choice_number in range(1, 5):
		var choice_button := _find_optional_node(
			"DialogueChoiceButton%d" % choice_number
		) as Button
		if choice_button != null:
			dialogue_choice_buttons.append(choice_button)


func _find_optional_node(node_name: String) -> Node:
	var found_node: Node = find_child(node_name, true, false)
	if found_node == null:
		push_warning("ConsoleInterface: Missing optional node '%s'." % node_name)
	return found_node


func _connect_front_interaction_signals() -> void:
	# 新增按钮信号逐个检查，避免节点缺失或重复初始化造成错误。
	var previous_camera_callback: Callable = _change_camera.bind(-1)
	var next_camera_callback: Callable = _change_camera.bind(1)
	if previous_camera_button != null \
			and not previous_camera_button.pressed.is_connected(previous_camera_callback):
		previous_camera_button.pressed.connect(previous_camera_callback)
	if next_camera_button != null \
			and not next_camera_button.pressed.is_connected(next_camera_callback):
		next_camera_button.pressed.connect(next_camera_callback)
	if talk_button != null and not talk_button.pressed.is_connected(_toggle_microphone):
		talk_button.pressed.connect(_toggle_microphone)

	for choice_index in dialogue_choice_buttons.size():
		var choice_button := dialogue_choice_buttons[choice_index]
		var choice_callback: Callable = _select_dialogue_choice.bind(choice_index)
		if not choice_button.pressed.is_connected(choice_callback):
			choice_button.pressed.connect(choice_callback)


func _initialize_front_interaction() -> void:
	current_camera_index = 0
	mic_enabled = false
	dialogue_node_index = 0
	dialogue_started = false
	dialogue_finished = false
	current_passenger_line = "乘客舱音频链路待机。"

	if monitor_title_label != null:
		monitor_title_label.text = "乘客舱主监控 / PASSENGER CABIN FEED"
	if dialogue_prompt_label != null:
		dialogue_prompt_label.text = "选择对乘客的回应："
	_update_camera_display()
	_update_microphone_display()
	_update_dialogue_buttons()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		return

	# 监听状态变化后即时刷新文字，并防止重复连接同一个信号。
	if not demo_flow_manager.state_changed.is_connected(_update_state_label):
		demo_flow_manager.state_changed.connect(_update_state_label)
	_update_state_label(demo_flow_manager.get_current_state_name())
	_update_dialogue_buttons()


func show_console(
		console_type: String,
		console_name: String,
		console_description: String
) -> void:
	# FRONT 是主调度台，需要显示调度、门控和流程按钮；其他方向只显示各自说明。
	var is_main_dispatch_console: bool = console_type == "FRONT"
	active_console_type = console_type
	title_label.text = console_name
	description_label.text = console_description
	dispatch_panel.visible = is_main_dispatch_console
	door_control_panel.visible = is_main_dispatch_console
	flow_control_panel.visible = is_main_dispatch_console
	system_hint_label.visible = is_main_dispatch_console
	if passenger_monitor_panel != null:
		passenger_monitor_panel.visible = is_main_dispatch_console
	if intercom_panel != null:
		intercom_panel.visible = is_main_dispatch_console
	if dialogue_choice_panel != null and not is_main_dispatch_console:
		dialogue_choice_panel.hide()
	_update_dialogue_visibility()

	if is_main_dispatch_console and demo_flow_manager != null:
		_update_state_label(demo_flow_manager.get_current_state_name())
		_append_front_operation("进入 FRONT 主仲裁台")

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
	if active_console_type == "FRONT":
		_append_front_operation("返回操作间")
	return_requested.emit()


func _change_camera(direction: int) -> void:
	# 三路摄像头只是主仲裁台的文字占位，不创建 Viewport 或真实渲染画面。
	current_camera_index = posmod(current_camera_index + direction, CAMERA_FEEDS.size())
	_update_camera_display()
	_append_front_operation("摄像头切换：%s" % CAMERA_FEEDS[current_camera_index]["name"])

	if mic_enabled and current_camera_index != 0:
		system_hint_label.text = "非主摄像头仅用于观察。返回主摄像头继续通话。"
	else:
		system_hint_label.text = "已切换至 %s。" % CAMERA_FEEDS[current_camera_index]["name"]
	_update_dialogue_visibility()


func _update_camera_display() -> void:
	var camera_feed: Dictionary = CAMERA_FEEDS[current_camera_index]
	if camera_name_label != null:
		camera_name_label.text = camera_feed["name"]
	if monitor_feed_label != null:
		monitor_feed_label.text = camera_feed["feed"]


func _toggle_microphone() -> void:
	# 麦克风目前只是交互状态占位，不接入真实录音。
	mic_enabled = not mic_enabled
	_append_front_operation("麦克风%s" % ("开启" if mic_enabled else "关闭"))

	if mic_enabled and not dialogue_started and not dialogue_finished:
		dialogue_started = true
		current_passenger_line = _get_initial_passenger_line()
	_update_microphone_display()

	if mic_enabled and current_camera_index != 0:
		system_hint_label.text = "非主摄像头仅用于观察。返回主摄像头继续通话。"
	elif mic_enabled:
		system_hint_label.text = "乘客通话链路已开启。"
	else:
		system_hint_label.text = "乘客通话链路已关闭。"


func _update_microphone_display() -> void:
	if mic_status_label != null:
		mic_status_label.text = "麦克风：开启" if mic_enabled else "麦克风：关闭"
	if talk_button != null:
		talk_button.text = "关闭麦克风" if mic_enabled else "开启麦克风"
	if passenger_speech_label != null:
		passenger_speech_label.text = current_passenger_line \
			if mic_enabled else "乘客舱音频链路待机。"
	_update_dialogue_visibility()


func _update_dialogue_visibility() -> void:
	if dialogue_choice_panel == null:
		return

	var is_front_visible: bool = passenger_monitor_panel != null \
		and passenger_monitor_panel.visible
	# 关闭麦克风时彻底隐藏对话区；开启后再根据摄像头和对话状态决定能否选择。
	dialogue_choice_panel.visible = is_front_visible and mic_enabled
	if not dialogue_choice_panel.visible:
		return

	var can_select_dialogue: bool = mic_enabled and current_camera_index == 0 \
		and not dialogue_finished
	for choice_button in dialogue_choice_buttons:
		choice_button.disabled = not can_select_dialogue

	if dialogue_prompt_label == null:
		return
	if dialogue_finished:
		dialogue_prompt_label.text = "当前通话节点已结束。"
	elif current_camera_index != 0:
		dialogue_prompt_label.text = "返回 CAM 01｜主摄像头继续对话。"
	else:
		dialogue_prompt_label.text = "选择对乘客的回应："


func _update_dialogue_buttons() -> void:
	var dialogue_nodes: Array = _get_dialogue_nodes()
	if dialogue_finished or dialogue_node_index >= dialogue_nodes.size():
		return

	var current_node: Array = dialogue_nodes[dialogue_node_index]
	for choice_index in dialogue_choice_buttons.size():
		var choice_button := dialogue_choice_buttons[choice_index]
		choice_button.visible = choice_index < current_node.size()
		if choice_button.visible:
			choice_button.text = current_node[choice_index]["operator"]


func _select_dialogue_choice(choice_index: int) -> void:
	if not mic_enabled or current_camera_index != 0 or dialogue_finished:
		return

	var dialogue_nodes: Array = _get_dialogue_nodes()
	if dialogue_node_index >= dialogue_nodes.size():
		return
	var current_node: Array = dialogue_nodes[dialogue_node_index]
	if choice_index >= current_node.size():
		return

	var selected_choice: Dictionary = current_node[choice_index]
	var operator_line: String = selected_choice["operator"]
	var passenger_reply: String = selected_choice["passenger"]
	var status_hint: String = selected_choice["status_hint"]
	current_passenger_line = passenger_reply
	if passenger_speech_label != null:
		passenger_speech_label.text = current_passenger_line
	_append_front_dialogue(operator_line, passenger_reply, status_hint)

	dialogue_node_index += 1
	if dialogue_node_index >= dialogue_nodes.size():
		dialogue_finished = true
		system_hint_label.text = "当前通话节点结束。请确认门控或查看其他控制台。"
		_update_dialogue_visibility()
		return

	_update_dialogue_buttons()
	system_hint_label.text = "乘客已回应。请选择下一句。"


func _get_dialogue_nodes() -> Array:
	# UI 只通过临时 getter 读取案例；未来改用 JSON Loader 时这里无需重写。
	if demo_flow_manager != null:
		var case_dialogue_nodes: Array = demo_flow_manager.get_dialogue_nodes()
		if not case_dialogue_nodes.is_empty():
			return case_dialogue_nodes
	return DIALOGUE_NODES


func _get_initial_passenger_line() -> String:
	if demo_flow_manager != null:
		var initial_line: String = demo_flow_manager.get_initial_passenger_line()
		if not initial_line.is_empty():
			return initial_line
	return "乘客：你是真人在听吗？我需要去下面。"


func _append_front_dialogue(
		operator_text: String,
		passenger_text: String,
		status_hint: String
) -> void:
	# 对话与建筑提示走独立通道，不写入 LEFT 的 SYSTEM LOG。
	if demo_flow_manager != null:
		demo_flow_manager.add_front_dialogue(operator_text, passenger_text, status_hint)


func _append_front_operation(operation_text: String) -> void:
	# 麦克风、摄像头和门控属于玩家操作，只写入 LEFT 的 SYSTEM LOG。
	if demo_flow_manager != null:
		demo_flow_manager.add_front_operation(operation_text)


func _print_door_action(action_name: String) -> void:
	print("Door action: ", action_name)
	_append_front_operation("门控：%s" % action_name)


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

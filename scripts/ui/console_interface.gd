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
var dispatch_info_label: Label
var route_suggestion_label: Label
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
var building_alert_label: Label

var demo_flow_manager: DemoFlowManager
var active_console_type: String = ""
var current_camera_index: int = 0
var mic_enabled: bool = false
var current_dialogue_node_id: String = "onboard_start"
var dialogue_started: bool = false
var dialogue_finished: bool = false
var current_passenger_line: String = "乘客舱音频链路待机。"

func _ready() -> void:
	_cache_front_interaction_nodes()
	# 三个门控按钮共用处理函数，同时把操作同步给 LEFT 的临时事件缓存。
	open_door_button.pressed.connect(_handle_open_door)
	delay_door_button.pressed.connect(_print_door_action.bind("延迟关门"))
	close_door_button.pressed.connect(_handle_close_door)
	# 推进按钮调用流程管理器；返回按钮通过信号通知舱体控制器退出界面。
	advance_state_button.pressed.connect(_advance_state)
	return_button.pressed.connect(_request_return)
	_connect_front_interaction_signals()
	_initialize_front_interaction()
	# 原型阶段暂不提供无实际用途的流程推进与延迟关门入口。
	advance_state_button.visible = false
	delay_door_button.visible = false


func _cache_front_interaction_nodes() -> void:
	passenger_monitor_panel = _find_optional_node("PassengerMonitorPanel") as Control
	dispatch_info_label = find_child("DispatchInfoLabel", true, false) as Label
	# 该旧栏位可能由场景手工删除，因此不通过会报警的必需节点查找。
	route_suggestion_label = find_child("RouteSuggestionLabel", true, false) as Label
	if route_suggestion_label != null:
		route_suggestion_label.hide()
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
	building_alert_label = _find_optional_node("BuildingAlertLabel") as Label

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
	current_dialogue_node_id = "onboard_start"
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
	_update_building_alert()
	_update_dispatch_panel()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		return

	# 监听状态变化后即时刷新文字，并防止重复连接同一个信号。
	if not demo_flow_manager.state_changed.is_connected(_update_state_label):
		demo_flow_manager.state_changed.connect(_update_state_label)
	if not demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.connect(_refresh_case_display)
	_update_state_label(demo_flow_manager.get_current_state_name())
	_update_dialogue_buttons()
	_refresh_case_display()


func show_console(
		console_type: String,
		console_name: String,
		console_description: String
) -> void:
	# FRONT 是主调度台，需要显示调度、门控和流程按钮；其他方向只显示各自说明。
	var is_main_dispatch_console: bool = console_type == "FRONT"
	active_console_type = console_type
	title_label.text = console_name
	description_label.text = "乘客接乘、证据复核与门控。" \
		if is_main_dispatch_console else console_description
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
		_update_dispatch_panel()
		_refresh_case_display()
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

	if mic_enabled and _can_talk_on_current_camera():
		current_passenger_line = _get_phase_passenger_line()
		_update_microphone_display()
	if mic_enabled and not _can_talk_on_current_camera():
		system_hint_label.text = _get_unavailable_dialogue_hint()
	else:
		system_hint_label.text = "已切换至 %s。" % CAMERA_FEEDS[current_camera_index]["name"]
	_update_dialogue_visibility()


func _update_camera_display() -> void:
	var camera_feed: Dictionary = CAMERA_FEEDS[current_camera_index]
	if camera_name_label != null:
		camera_name_label.text = camera_feed["name"]
	if monitor_feed_label != null:
		monitor_feed_label.text = _get_phase_camera_feed(current_camera_index)


func _get_phase_camera_feed(camera_index: int) -> String:
	if demo_flow_manager == null:
		return str(CAMERA_FEEDS[camera_index]["feed"])
	return demo_flow_manager.get_camera_feed_for_phase(
		demo_flow_manager.get_case_phase(),
		camera_index
	)


func _toggle_microphone() -> void:
	# 麦克风目前只是交互状态占位，不接入真实录音。
	mic_enabled = not mic_enabled
	_append_front_operation("麦克风%s" % ("开启" if mic_enabled else "关闭"))

	if mic_enabled and not dialogue_started and not dialogue_finished:
		dialogue_started = true
		current_passenger_line = _get_phase_passenger_line()
	_update_microphone_display()

	if mic_enabled and not _can_talk_on_current_camera():
		system_hint_label.text = _get_unavailable_dialogue_hint()
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
	# 对话区只在门外问候或关门后的正式询问条件完整满足时出现。
	var can_select_dialogue: bool = is_front_visible and mic_enabled \
		and (_is_door_greeting_available() or _is_onboard_dialogue_available())
	dialogue_choice_panel.visible = can_select_dialogue
	for choice_button in dialogue_choice_buttons:
		choice_button.disabled = false
	if not dialogue_choice_panel.visible:
		return

	if dialogue_prompt_label == null:
		return
	if dialogue_finished:
		dialogue_prompt_label.text = "当前通话节点已结束。"
	elif not _can_talk_on_current_camera():
		dialogue_prompt_label.text = "请切换到当前阶段可用的通话摄像头。"
	else:
		dialogue_prompt_label.text = "选择对乘客的回应："


func _update_dialogue_buttons() -> void:
	if demo_flow_manager != null and demo_flow_manager.get_case_phase() == "ARRIVED_AT_PICKUP":
		for button_index in dialogue_choice_buttons.size():
			var greeting_button := dialogue_choice_buttons[button_index]
			greeting_button.visible = button_index == 0
			if button_index == 0:
				greeting_button.text = "你好。"
		return
	var current_node: Dictionary = _get_dialogue_node(current_dialogue_node_id)
	var choices: Array = current_node.get("choices", [])
	for choice_index in dialogue_choice_buttons.size():
		var choice_button := dialogue_choice_buttons[choice_index]
		choice_button.visible = choice_index < choices.size()
		if choice_button.visible:
			choice_button.text = str(choices[choice_index].get("operator", "继续"))


func _select_dialogue_choice(choice_index: int) -> void:
	if not mic_enabled or not _can_talk_on_current_camera() or dialogue_finished:
		return
	if demo_flow_manager != null and demo_flow_manager.get_case_phase() == "ARRIVED_AT_PICKUP":
		_handle_door_greeting(choice_index)
		return
	var current_node: Dictionary = _get_dialogue_node(current_dialogue_node_id)
	var choices: Array = current_node.get("choices", [])
	if choice_index >= choices.size():
		return
	var selected_choice: Dictionary = choices[choice_index]
	var operator_line: String = str(selected_choice.get("operator", ""))
	var passenger_reply: String = str(selected_choice.get("passenger", ""))
	var status_hint: String = str(selected_choice.get("status_hint", ""))
	current_passenger_line = passenger_reply
	if passenger_speech_label != null:
		passenger_speech_label.text = current_passenger_line
	_append_front_dialogue(operator_line, passenger_reply, status_hint)

	current_dialogue_node_id = _resolve_dialogue_node_id(str(selected_choice.get("next", "case_summary")))
	var next_node: Dictionary = _get_dialogue_node(current_dialogue_node_id)
	current_passenger_line = str(next_node.get("passenger_line", passenger_reply))
	if current_dialogue_node_id == "case_summary" and demo_flow_manager != null:
		# 乘客线索整理完成后，系统只增加中继缓冲候选，不直接泄露 004 / 387。
		demo_flow_manager.mark_case_summary_reached()
	if next_node.get("choices", []).is_empty():
		dialogue_finished = true
		var summary_hint: String = str(next_node.get("status_hint", ""))
		if not summary_hint.is_empty() and demo_flow_manager != null:
			demo_flow_manager.set_building_status_hint(summary_hint, true)
		system_hint_label.text = "乘客已给出目标线索。请复核建筑终端，或前往右侧目标楼层控制台。"
		_update_dialogue_visibility()
		return

	_update_dialogue_buttons()
	system_hint_label.text = "乘客已回应。请选择下一句。"
	_update_microphone_display()
	_update_building_alert()


func _get_dialogue_nodes() -> Array:
	# UI 只通过临时 getter 读取案例；未来改用 JSON Loader 时这里无需重写。
	if demo_flow_manager != null:
		var case_dialogue_nodes: Array = demo_flow_manager.get_dialogue_nodes()
		if not case_dialogue_nodes.is_empty():
			return case_dialogue_nodes
	return DIALOGUE_NODES


func _get_dialogue_node(node_id: String) -> Dictionary:
	if demo_flow_manager == null:
		return {}
	var tree: Dictionary = demo_flow_manager.get_dialogue_tree()
	if tree.has(node_id):
		return tree[node_id]
	# 兼容旧案例的两层数组；正式 Rowan 案例始终优先使用 dialogue_tree。
	if tree.is_empty():
		var legacy_nodes: Array = _get_dialogue_nodes()
		if not legacy_nodes.is_empty():
			return {"passenger_line": _get_initial_passenger_line(), "choices": legacy_nodes[0]}
	return tree.get("case_summary", tree.get("onboard_start", {}))


func _resolve_dialogue_node_id(requested_id: String) -> String:
	if demo_flow_manager == null:
		return "onboard_start"
	var current_case: Dictionary = demo_flow_manager.get_current_case()
	var tree: Dictionary = current_case.get("dialogue_tree", {})
	var fallbacks: Dictionary = current_case.get("dialogue_fallbacks", {})
	var resolved_id: String = str(fallbacks.get(requested_id, requested_id))
	if tree.has(resolved_id):
		return resolved_id
	return "case_summary" if tree.has("case_summary") else "onboard_start"


func _can_talk_on_current_camera() -> bool:
	return _is_door_greeting_available() or _is_onboard_dialogue_available()


func _is_door_greeting_available() -> bool:
	return demo_flow_manager != null \
		and demo_flow_manager.get_case_phase() == "ARRIVED_AT_PICKUP" \
		and not demo_flow_manager.is_door_greeting_done() \
		and current_camera_index == 2


func _is_onboard_dialogue_available() -> bool:
	return demo_flow_manager != null \
		and demo_flow_manager.get_case_phase() == "PASSENGER_ONBOARD" \
		and demo_flow_manager.is_passenger_onboard() \
		and demo_flow_manager.is_cabin_door_closed_after_boarding() \
		and current_camera_index == 0 \
		and not dialogue_finished


func _get_phase_passenger_line() -> String:
	if demo_flow_manager == null:
		return _get_initial_passenger_line()
	var phase: String = demo_flow_manager.get_case_phase()
	if phase == "ARRIVED_AT_PICKUP":
		return str(demo_flow_manager.get_pickup_data().get("outside_audio_idle", "门外音频链路已开启。"))
	if phase == "BOARDING_WAIT_DOOR_CLOSE":
		return demo_flow_manager.get_after_open_line()
	if phase in ["PASSENGER_ONBOARD", "DESTINATION_CONFIRMED"]:
		var feedback := demo_flow_manager.get_destination_feedback(
			demo_flow_manager.get_submitted_destination()
		)
		if not feedback.is_empty() and phase == "DESTINATION_CONFIRMED":
			return str(feedback.get("passenger", ""))
		return str(_get_dialogue_node(current_dialogue_node_id).get("passenger_line", _get_initial_passenger_line()))
	return "乘客舱音频链路待机。"


func _get_unavailable_dialogue_hint() -> String:
	if demo_flow_manager == null:
		return "当前摄像头仅用于观察。"
	var phase: String = demo_flow_manager.get_case_phase()
	if phase == "ARRIVED_AT_PICKUP":
		return "请切换至门外摄像头联系等待乘客。"
	if phase == "DOOR_GREETING_DONE":
		return "门外乘客已确认。请开启舱门。"
	if phase == "BOARDING_WAIT_DOOR_CLOSE":
		return "请先关闭舱门，再继续舱内询问。"
	if not demo_flow_manager.is_passenger_onboard():
		return "乘客尚未进入舱内。"
	return "当前摄像头仅用于观察。"


func _handle_door_greeting(choice_index: int) -> void:
	if choice_index != 0 or demo_flow_manager == null:
		return
	var greeting: Dictionary = demo_flow_manager.get_pickup_greeting()
	var operator_line: String = str(greeting.get("operator", "你好。"))
	var passenger_reply: String = str(greeting.get("passenger", "乘客：……"))
	var status_hint: String = str(greeting.get("status_hint", "门外乘客已回应。"))
	current_passenger_line = passenger_reply
	demo_flow_manager.add_front_dialogue(operator_line, passenger_reply)
	demo_flow_manager.set_door_greeting_done(true)
	demo_flow_manager.set_case_phase("DOOR_GREETING_DONE")
	demo_flow_manager.set_building_status_hint(status_hint, true)
	system_hint_label.text = str(greeting.get("system_hint", status_hint))
	_update_microphone_display()
	_update_dialogue_buttons()
	_update_building_alert()


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


func _handle_open_door() -> void:
	print("Door action: 开门")
	if demo_flow_manager == null:
		_append_front_operation("门控：开门")
		return
	var phase: String = demo_flow_manager.get_case_phase()
	if phase == "ARRIVED_AT_PICKUP" and not demo_flow_manager.is_door_greeting_done():
		system_hint_label.text = "建议先通过门外摄像头与等待乘客确认。"
		_append_front_operation("门控：开门尝试 / 未完成门外确认")
		return
	_append_front_operation("门控：开门")
	if phase == "DOOR_GREETING_DONE":
		demo_flow_manager.set_passenger_onboard(true)
		demo_flow_manager.set_pickup_completed(true)
		demo_flow_manager.set_cabin_door_closed_after_boarding(false)
		demo_flow_manager.set_case_phase("BOARDING_WAIT_DOOR_CLOSE")
		_append_front_operation("乘客进入舱内")
		current_dialogue_node_id = "onboard_start"
		dialogue_started = false
		dialogue_finished = false
		current_passenger_line = demo_flow_manager.get_after_open_line()
		system_hint_label.text = demo_flow_manager.get_after_open_hint()
		_update_camera_display()
		_update_dialogue_buttons()
		_update_microphone_display()
		if passenger_speech_label != null:
			passenger_speech_label.text = current_passenger_line


func _handle_close_door() -> void:
	print("Door action: 关门")
	_append_front_operation("门控：关门")
	if demo_flow_manager == null \
		or demo_flow_manager.get_case_phase() != "BOARDING_WAIT_DOOR_CLOSE":
		return
	# 登舱后必须显式关门，正式舱内询问才会解锁。
	demo_flow_manager.set_cabin_door_closed_after_boarding(true)
	demo_flow_manager.set_case_phase("PASSENGER_ONBOARD")
	_append_front_operation("乘客舱门已关闭")
	current_passenger_line = demo_flow_manager.get_after_close_line()
	system_hint_label.text = demo_flow_manager.get_after_close_hint()
	demo_flow_manager.set_building_status_hint(demo_flow_manager.get_after_close_status_hint(), true)
	_update_camera_display()
	_update_dialogue_buttons()
	_update_microphone_display()
	if passenger_speech_label != null:
		passenger_speech_label.text = current_passenger_line


func _refresh_case_display() -> void:
	_update_dispatch_panel()
	_update_camera_display()
	_update_dialogue_buttons()
	_update_dialogue_visibility()
	if demo_flow_manager != null and demo_flow_manager.get_case_phase() == "DESTINATION_CONFIRMED":
		current_passenger_line = _get_phase_passenger_line()
		system_hint_label.text = "目标楼层已提交：%s。乘客反应已更新。" % demo_flow_manager.get_submitted_destination()
		_update_microphone_display()
		if passenger_speech_label != null:
			passenger_speech_label.text = current_passenger_line
	# 最后刷新短提醒，避免目标反馈刷新时覆盖无专用 Label 的 fallback。
	_update_building_alert()


func _update_building_alert() -> void:
	if building_alert_label == null:
		if demo_flow_manager != null \
				and demo_flow_manager.has_unread_building_status_hint() \
				and system_hint_label != null \
				and not system_hint_label.text.begins_with("建筑终端收到新的复核提示。"):
			# 缺少专用 Label 时只补一行短提醒，不把 LEFT STATUS 正文搬到 FRONT。
			system_hint_label.text = "建筑终端收到新的复核提示。\n" + system_hint_label.text
		elif demo_flow_manager != null \
				and not demo_flow_manager.has_unread_building_status_hint() \
				and system_hint_label != null \
				and system_hint_label.text.begins_with("建筑终端收到新的复核提示。\n"):
			system_hint_label.text = system_hint_label.text.trim_prefix("建筑终端收到新的复核提示。\n")
		return
	var has_unread: bool = demo_flow_manager != null \
		and demo_flow_manager.has_unread_building_status_hint()
	building_alert_label.text = "建筑终端：有新复核提示" if has_unread \
		else "建筑终端：无新提示"


func _advance_state() -> void:
	# 流程管理器缺失时保留界面可运行，并用警告提示场景连接问题。
	if demo_flow_manager == null:
		push_warning("ConsoleInterface: DemoFlowManager is not connected.")
		return

	demo_flow_manager.advance_state()


func _update_state_label(_new_state_name: String) -> void:
	# 旧 DemoState 信号仍保留兼容，但 FRONT 主显示改由案例阶段驱动。
	_update_dispatch_panel()


func _update_dispatch_panel() -> void:
	if demo_flow_manager == null:
		return
	var phase: String = demo_flow_manager.get_case_phase()
	var passenger_text: String = "当前乘客：%s" % demo_flow_manager.get_passenger_label()
	var phase_text: Dictionary = demo_flow_manager.get_front_phase_text(phase)
	if state_label != null:
		state_label.text = str(phase_text.get("state", ""))
	if dispatch_info_label != null:
		dispatch_info_label.text = passenger_text + "\n" + str(phase_text.get("task", ""))


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)

extends Control
class_name ConsoleInterface


signal return_requested


const DialogueManagerAdapterScript := preload("res://scripts/dialogue/dialogue_manager_adapter.gd")

const CAMERA_NAMES: Array[String] = [
	"CAM 01｜舱内摄像头",
	"CAM 02｜门外摄像头",
]

enum DialogueContext {
	NONE,
	PICKUP,
	ONBOARD,
	DESTINATION,
}


# 这些引用对应操作台场景中的界面模块，统一声明便于看清显示与按钮依赖。
@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var dispatch_panel: Control = %DispatchPanel
@onready var state_label: Label = %StateLabel
@onready var door_control_panel: Control = %DoorControlPanel
@onready var open_door_button: Button = %OpenDoorButton
@onready var close_door_button: Button = %CloseDoorButton
@onready var system_hint_label: Label = %SystemHintLabel
@onready var return_button: Button = %ReturnButton

@onready var passenger_monitor_panel: Control = $ConsoleLayout/PassengerMonitorPanel
@onready var dispatch_info_label: Label = $ConsoleLayout/DispatchPanel/DispatchInfoLabel
@onready var monitor_title_label: Label = $ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/MonitorTitleLabel
@onready var camera_name_label: Label = $ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/CameraNameLabel
@onready var monitor_feed_label: Label = $ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/MonitorScreenPanel/MonitorScreenLayout/MonitorFeedLabel
@onready var passenger_speech_label: Label = $ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/MonitorScreenPanel/MonitorScreenLayout/PassengerSpeechLabel
@onready var previous_camera_button: Button = $ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/CameraControlPanel/PrevCameraButton
@onready var next_camera_button: Button = $ConsoleLayout/PassengerMonitorPanel/PassengerMonitorLayout/CameraControlPanel/NextCameraButton
@onready var intercom_panel: Control = $ConsoleLayout/IntercomPanel
@onready var mic_status_label: Label = $ConsoleLayout/IntercomPanel/IntercomLayout/MicStatusLabel
@onready var talk_button: Button = $ConsoleLayout/IntercomPanel/IntercomLayout/TalkButton
@onready var dialogue_choice_panel: Control = $ConsoleLayout/DialogueChoicePanel
@onready var dialogue_prompt_label: Label = $ConsoleLayout/DialogueChoicePanel/DialogueChoiceLayout/DialoguePromptLabel
@onready var dialogue_choice_buttons: Array[Button] = [
	$ConsoleLayout/DialogueChoicePanel/DialogueChoiceLayout/DialogueChoiceButton1,
	$ConsoleLayout/DialogueChoicePanel/DialogueChoiceLayout/DialogueChoiceButton2,
	$ConsoleLayout/DialogueChoicePanel/DialogueChoiceLayout/DialogueChoiceButton3,
	$ConsoleLayout/DialogueChoicePanel/DialogueChoiceLayout/DialogueChoiceButton4,
]

var demo_flow_manager: DemoFlowManager
var dialogue_manager_adapter: DialogueManagerAdapter
var current_camera_index: int = 0
var mic_enabled: bool = false
var current_passenger_line: String = "乘客舱音频链路待机。"
var dm_dialogue_started: bool = false
var dm_dialogue_finished: bool = false
var dm_choices: Array[Dictionary] = []
var dm_pending_status_hint_update: bool = false
var dm_pending_unlocked_floor_ids: Array[String] = []
var current_dialogue_context: DialogueContext = DialogueContext.NONE
var current_dialogue_context_finished: bool = false
var embedded_3d_mode: bool = false

func _ready() -> void:
	_create_dialogue_manager_adapter()
	# 三个门控按钮共用处理函数，同时把操作同步给 LEFT 的临时事件缓存。
	open_door_button.pressed.connect(_handle_open_door)
	close_door_button.pressed.connect(_handle_close_door)
	# 推进按钮调用流程管理器；返回按钮通过信号通知舱体控制器退出界面。
	return_button.pressed.connect(_request_return)
	_connect_front_interaction_signals()
	_initialize_front_interaction()


func _create_dialogue_manager_adapter() -> void:
	# 主操作台通过本地 adapter 接入 DM3，后续乘客铺量时只替换 resource_path。
	dialogue_manager_adapter = DialogueManagerAdapterScript.new() as DialogueManagerAdapter
	dialogue_manager_adapter.name = "DialogueManagerAdapter"
	add_child(dialogue_manager_adapter)
	dialogue_manager_adapter.dialogue_line_received.connect(_on_dm_dialogue_line_received)
	dialogue_manager_adapter.choices_received.connect(_on_dm_choices_received)
	dialogue_manager_adapter.dialogue_finished.connect(_on_dm_dialogue_finished)
	dialogue_manager_adapter.status_hint_requested.connect(_on_dm_status_hint_requested)
	dialogue_manager_adapter.floor_unlock_requested.connect(_on_dm_floor_unlock_requested)
	dialogue_manager_adapter.door_greeting_done_requested.connect(_on_dm_door_greeting_done_requested)


func _connect_front_interaction_signals() -> void:
	# 两个摄像头按钮现在是直接选择，不再按上一台/下一台循环。
	var cabin_camera_callback: Callable = _select_camera.bind(0)
	var door_camera_callback: Callable = _select_camera.bind(1)
	if not previous_camera_button.pressed.is_connected(cabin_camera_callback):
		previous_camera_button.pressed.connect(cabin_camera_callback)
	if not next_camera_button.pressed.is_connected(door_camera_callback):
		next_camera_button.pressed.connect(door_camera_callback)
	if not talk_button.pressed.is_connected(_toggle_microphone):
		talk_button.pressed.connect(_toggle_microphone)

	for choice_index in dialogue_choice_buttons.size():
		var choice_button := dialogue_choice_buttons[choice_index]
		var choice_callback: Callable = _select_dialogue_choice.bind(choice_index)
		if not choice_button.pressed.is_connected(choice_callback):
			choice_button.pressed.connect(choice_callback)


func _initialize_front_interaction() -> void:
	current_camera_index = 0
	mic_enabled = false
	dm_dialogue_started = false
	dm_dialogue_finished = false
	dm_choices.clear()
	current_passenger_line = "乘客舱音频链路待机。"

	monitor_title_label.text = "乘客舱主监控 / PASSENGER CABIN FEED"
	dialogue_prompt_label.text = "选择对乘客的回应："
	_update_camera_display()
	_update_microphone_display()
	_update_dialogue_buttons()
	_update_dispatch_panel()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		return
	_disconnect_demo_flow_manager()
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("ConsoleInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.connect(_refresh_case_display)
	if not demo_flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		demo_flow_manager.dispatch_started.connect(_on_dispatch_started)
	if not demo_flow_manager.dispatch_completed.is_connected(_on_dispatch_completed):
		demo_flow_manager.dispatch_completed.connect(_on_dispatch_completed)
	if not demo_flow_manager.shift_completed.is_connected(_on_shift_completed):
		demo_flow_manager.shift_completed.connect(_on_shift_completed)
	_reset_dispatch_ui_state()
	_update_dialogue_buttons()
	_refresh_case_display()


func _disconnect_demo_flow_manager() -> void:
	if demo_flow_manager == null:
		return
	if demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.disconnect(_refresh_case_display)
	if demo_flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		demo_flow_manager.dispatch_started.disconnect(_on_dispatch_started)
	if demo_flow_manager.dispatch_completed.is_connected(_on_dispatch_completed):
		demo_flow_manager.dispatch_completed.disconnect(_on_dispatch_completed)
	if demo_flow_manager.shift_completed.is_connected(_on_shift_completed):
		demo_flow_manager.shift_completed.disconnect(_on_shift_completed)


func _on_dispatch_started(_dispatch_id: StringName) -> void:
	_reset_dispatch_ui_state()
	_refresh_case_display()


func _on_dispatch_completed(_result: DispatchResult) -> void:
	_reset_dispatch_ui_state()


func _on_shift_completed() -> void:
	_reset_dispatch_ui_state()
	_refresh_case_display()


func _reset_dispatch_ui_state() -> void:
	# 每条派单使用独立对话上下文，摄像头位置和电梯楼层不在这里重置。
	mic_enabled = false
	dm_dialogue_started = false
	dm_dialogue_finished = false
	dm_choices.clear()
	dm_pending_status_hint_update = false
	dm_pending_unlocked_floor_ids.clear()
	current_dialogue_context = DialogueContext.NONE
	current_dialogue_context_finished = false
	current_passenger_line = "乘客舱音频链路待机。"
	if dialogue_manager_adapter != null:
		dialogue_manager_adapter.reset_dialogue()
	_update_microphone_display()
	_update_dialogue_buttons()


func show_main_console() -> void:
	# LEFT 与 RIGHT 使用独立界面，ConsoleInterface 只负责 FRONT 主调度台。
	title_label.text = "主调度台"
	description_label.text = "乘客接乘、证据复核与门控。"
	dispatch_panel.show()
	door_control_panel.show()
	system_hint_label.show()
	passenger_monitor_panel.show()
	intercom_panel.show()
	_update_dialogue_visibility()

	if demo_flow_manager != null:
		_update_dispatch_panel()
		_refresh_case_display()

	show()
	open_door_button.grab_focus()


# 3D 模式只关闭旧的“退出操作台”入口，不改变旧 2D 场景的默认行为。
func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	if return_button != null:
		return_button.visible = not is_enabled
		return_button.disabled = is_enabled
		if is_enabled:
			return_button.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or embedded_3d_mode:
		return

	# 操作台可用 Esc（ui_cancel）或 S 退出，与舱内进入操作形成清晰对应。
	if event.is_action_pressed("ui_cancel") or _is_key_pressed(event, KEY_S):
		_request_return()
		get_viewport().set_input_as_handled()


func _request_return() -> void:
	# 界面只发送退出意图，具体恢复舱内视图由外层控制器负责。
	if embedded_3d_mode:
		return
	return_requested.emit()


func _select_camera(camera_index: int) -> void:
	# 摄像头只切换证据画面，不再决定麦克风是否可以对话。
	current_camera_index = clampi(camera_index, 0, CAMERA_NAMES.size() - 1)
	_update_camera_display()
	_show_system_hint("已切换至 %s。" % CAMERA_NAMES[current_camera_index])
	_update_dialogue_visibility()


func _update_camera_display() -> void:
	camera_name_label.text = CAMERA_NAMES[current_camera_index]
	monitor_feed_label.text = _get_phase_camera_feed(current_camera_index)


func _get_phase_camera_feed(camera_index: int) -> String:
	if demo_flow_manager != null:
		var feed_text: String = demo_flow_manager.get_camera_feed_for_phase(
			demo_flow_manager.get_case_phase(),
			camera_index
		)
		if not feed_text.is_empty():
			return feed_text
		return "画面占位：乘客舱内为空。" if camera_index == 0 \
				else "画面占位：当前楼层门外切片。"

	return "画面占位：摄像头文本未连接。"


func _toggle_microphone() -> void:
	# 麦克风目前只是交互状态占位，不接入真实录音。
	if demo_flow_manager == null or not demo_flow_manager.has_active_dispatch():
		_show_system_hint("当前没有可通话的乘客派单。")
		return
	mic_enabled = not mic_enabled

	if mic_enabled and not dm_dialogue_started and not dm_dialogue_finished:
		if not _start_dialogue_manager_passenger():
			current_passenger_line = _get_phase_passenger_line()
	_update_microphone_display()

	if mic_enabled and dm_dialogue_started and not dm_dialogue_finished:
		_show_system_hint("乘客通话链路已开启。")
	elif mic_enabled:
		_show_system_hint("乘客通话链路已开启。")
	else:
		_show_system_hint("乘客通话链路已关闭。")


func _start_dialogue_manager_passenger() -> bool:
	# DM 对话按旧 phase 分入口：接乘前只做门外确认，关门后才进入舱内询问。
	var start_title: String = _get_dialogue_manager_start_title()
	if start_title.is_empty():
		return false
	dm_dialogue_started = true
	dm_dialogue_finished = false
	current_dialogue_context_finished = false
	current_dialogue_context = DialogueContext.PICKUP \
			if start_title == "pickup_start" else DialogueContext.ONBOARD
	dm_choices.clear()
	_begin_dm_front_hint_batch()
	if dialogue_manager_adapter != null:
		dialogue_manager_adapter.start_dialogue(_get_current_dispatch_dialogue_path(), start_title)
	return true


func _get_dialogue_manager_start_title() -> String:
	if demo_flow_manager == null:
		return ""
	var phase: String = demo_flow_manager.get_case_phase()
	if phase == "ARRIVED_AT_PICKUP" and not demo_flow_manager.is_door_greeting_done():
		return "pickup_start"
	if phase == "PASSENGER_ONBOARD" \
			and demo_flow_manager.is_passenger_onboard() \
			and demo_flow_manager.is_cabin_door_closed_after_boarding():
		return "onboard_start"
	return ""


func _update_microphone_display() -> void:
	mic_status_label.text = "麦克风：开启" if mic_enabled else "麦克风：关闭"
	talk_button.text = "关闭麦克风" if mic_enabled else "开启麦克风"
	var should_show_passenger_line: bool = mic_enabled or dm_dialogue_started
	passenger_speech_label.text = current_passenger_line \
		if should_show_passenger_line else "乘客舱音频链路待机。"
	_update_dialogue_visibility()


func _update_dialogue_visibility() -> void:
	var is_front_visible: bool = passenger_monitor_panel.visible
	# 对话区不再要求特定摄像头；摄像头只提供不同证据画面。
	var can_select_dialogue: bool = is_front_visible and mic_enabled \
		and dm_dialogue_started \
		and not dm_dialogue_finished
	dialogue_choice_panel.visible = can_select_dialogue
	for choice_button in dialogue_choice_buttons:
		choice_button.disabled = false
	if not dialogue_choice_panel.visible:
		return

	_update_dialogue_manager_buttons()


func _update_dialogue_buttons() -> void:
	if dm_dialogue_started and not dm_dialogue_finished:
		_update_dialogue_manager_buttons()
		return
	_clear_dialogue_buttons()


func _clear_dialogue_buttons() -> void:
	for choice_button in dialogue_choice_buttons:
		choice_button.visible = false
		choice_button.disabled = true
		choice_button.text = ""


func _update_dialogue_manager_buttons() -> void:
	for button_index in dialogue_choice_buttons.size():
		var choice_button := dialogue_choice_buttons[button_index]
		choice_button.visible = false
		choice_button.disabled = true
		choice_button.text = ""

	if dm_dialogue_finished:
		dialogue_prompt_label.text = "当前通话已结束。"
		return

	dialogue_prompt_label.text = "选择对乘客的回应："
	for choice_index in dialogue_choice_buttons.size():
		var has_choice: bool = choice_index < dm_choices.size()
		var choice_button := dialogue_choice_buttons[choice_index]
		choice_button.visible = has_choice
		choice_button.disabled = not has_choice or not bool(dm_choices[choice_index].get("is_allowed", true))
		if has_choice:
			choice_button.text = str(dm_choices[choice_index].get("text", "选项"))


func _select_dialogue_choice(choice_index: int) -> void:
	_select_dialogue_manager_choice(choice_index)


func _select_dialogue_manager_choice(choice_index: int) -> void:
	if not mic_enabled or dm_dialogue_finished or dialogue_manager_adapter == null:
		return
	if choice_index < 0 or choice_index >= dm_choices.size():
		return

	var operator_line: String = str(dm_choices[choice_index].get("text", ""))
	if demo_flow_manager != null:
		demo_flow_manager.add_front_transcript_operator(operator_line)
	_begin_dm_front_hint_batch()
	dialogue_manager_adapter.choose_response(choice_index)


func _on_dm_dialogue_line_received(
		character: String,
		text: String,
		has_choices: bool
) -> void:
	var speaker: String = _format_dialogue_character(character)
	current_passenger_line = "%s：%s" % [speaker, text] if not speaker.is_empty() else text
	if passenger_speech_label != null:
		passenger_speech_label.text = current_passenger_line
	if demo_flow_manager != null:
		demo_flow_manager.add_front_transcript_passenger(current_passenger_line)

	if not has_choices:
		# DM 接入不再提供“继续”按钮；无选项的乘客回复显示后即收起选项区。
		dm_dialogue_finished = true
		_finish_current_dialogue_context()
	_update_microphone_display()
	_update_dialogue_buttons()
	_update_dialogue_visibility()


func _on_dm_choices_received(choices: Array) -> void:
	dm_choices.clear()
	for choice in choices:
		if choice is Dictionary:
			dm_choices.append(choice)
	_update_dialogue_buttons()
	_update_dialogue_visibility()


func _on_dm_dialogue_finished() -> void:
	dm_dialogue_finished = true
	dm_choices.clear()
	_finish_current_dialogue_context()
	_update_dialogue_buttons()
	_update_dialogue_visibility()


func _finish_current_dialogue_context() -> void:
	# 无后续选项与 adapter 结束信号可能连续到达，因此必须幂等处理。
	if current_dialogue_context_finished:
		return
	current_dialogue_context_finished = true
	if current_dialogue_context == DialogueContext.DESTINATION \
			and demo_flow_manager != null:
		demo_flow_manager.mark_dropoff_feedback_finished()


func _on_dm_status_hint_requested(text: String) -> void:
	# DM 的详细判断写入 LEFT 系统日志；FRONT 只显示短操作提示，避免复读正文。
	if demo_flow_manager != null:
		demo_flow_manager.set_building_status_hint(text)
	dm_pending_status_hint_update = true
	_apply_dm_front_hint_batch()


func _on_dm_floor_unlock_requested(floor_id: String) -> void:
	var normalized_floor_id: String = floor_id.strip_edges()
	# Dialogue mutation 直接修改派单状态，右台通过 case_updated 自动刷新。
	if demo_flow_manager != null:
		demo_flow_manager.add_recommended_destination(normalized_floor_id)
	if not normalized_floor_id.is_empty() and normalized_floor_id not in dm_pending_unlocked_floor_ids:
		dm_pending_unlocked_floor_ids.append(normalized_floor_id)
	_apply_dm_front_hint_batch()


func _begin_dm_front_hint_batch() -> void:
	# 一次 DM 行推进可能连续触发多个 mutation，这里先清空，随后合成一条 FRONT 短提示。
	dm_pending_status_hint_update = false
	dm_pending_unlocked_floor_ids.clear()


func _apply_dm_front_hint_batch() -> void:
	var unlocked_floor_labels := PackedStringArray()
	for floor_id in dm_pending_unlocked_floor_ids:
		unlocked_floor_labels.append(floor_id)
	var unlocked_text: String = "、".join(unlocked_floor_labels)
	if dm_pending_status_hint_update and not unlocked_text.is_empty():
		_show_system_hint("系统判断已更新；推荐楼层已更新：%s。" % unlocked_text)
		_record_system_log("推荐目标列表已更新。")
	elif dm_pending_status_hint_update:
		_show_system_hint("系统判断已更新，请查看左侧系统日志。")
	elif not unlocked_text.is_empty():
		_show_system_hint("推荐楼层已更新：%s。" % unlocked_text)
		_record_system_log("推荐目标列表已更新。")


func _on_dm_door_greeting_done_requested() -> void:
	# DM 只完成“门外乘客已确认”；后续开门、进舱、关门仍走原有门控 phase。
	if demo_flow_manager == null:
		return
	if demo_flow_manager.get_case_phase() != "ARRIVED_AT_PICKUP":
		return
	demo_flow_manager.set_door_greeting_done(true)
	demo_flow_manager.set_case_phase("DOOR_GREETING_DONE")
	_update_dialogue_buttons()
	_update_dialogue_visibility()


func _show_destination_feedback_for_current_floor() -> void:
	# 到站本身不触发乘客反馈；只有玩家开门时才按当前楼层读取 destination_xxx。
	if demo_flow_manager == null or not demo_flow_manager.is_passenger_onboard():
		return
	var current_floor: String = demo_flow_manager.get_current_floor()
	if demo_flow_manager.get_selected_target_floor() != current_floor:
		return
	if dialogue_manager_adapter == null:
		return
	# 同一派单的抵达反馈只允许触发一次，重复开门不会重复播放对白。
	if not demo_flow_manager.try_mark_arrival_triggered():
		return
	var title: String = "destination_%s" % current_floor
	dm_dialogue_started = true
	dm_dialogue_finished = false
	dm_choices.clear()
	current_dialogue_context = DialogueContext.DESTINATION
	current_dialogue_context_finished = false
	_begin_dm_front_hint_batch()
	if dialogue_manager_adapter.dialogue_resource == null:
		dialogue_manager_adapter.start_dialogue(_get_current_dispatch_dialogue_path(), title)
	else:
		dialogue_manager_adapter.show_title(title)


func _format_dialogue_character(character: String) -> String:
	if character == "Passenger":
		return "乘客"
	return character


func _get_current_dispatch_dialogue_path() -> String:
	if demo_flow_manager == null:
		return ""
	return demo_flow_manager.get_dispatch_dialogue_path()


func _get_phase_passenger_line() -> String:
	if demo_flow_manager == null:
		return "乘客舱音频链路待机。"
	var phase: String = demo_flow_manager.get_case_phase()
	if phase == "ARRIVED_AT_PICKUP":
		var outside_audio_idle: String = demo_flow_manager.get_outside_audio_idle()
		return outside_audio_idle if not outside_audio_idle.is_empty() else "门外音频链路已开启。"
	if phase == "BOARDING_WAIT_DOOR_CLOSE":
		return demo_flow_manager.get_after_open_line()
	if phase == "PASSENGER_ONBOARD":
		# 乘客对正式目标楼层的反馈统一来自 .dialogue 的 destination_xxx 标题。
		return current_passenger_line
	if phase == "DROPOFF_WAIT_DOOR_CLOSE":
		return "乘客已离舱。"
	return "乘客舱音频链路待机。"


func _show_system_hint(hint_text: String) -> void:
	# FRONT 的短提示不自动写入历史，避免左侧日志重复玩家刚完成的操作。
	system_hint_label.text = hint_text


func _record_system_log(message_text: String) -> void:
	if demo_flow_manager != null:
		demo_flow_manager.add_system_log_message(message_text)


func _handle_open_door() -> void:
	print("Door action: 开门")
	if demo_flow_manager == null:
		return
	if demo_flow_manager.is_elevator_moving():
		_show_system_hint("电梯正在运行中，无法开门。")
		return
	if demo_flow_manager.is_cabin_door_open():
		_show_system_hint("舱门已经开启。")
		return

	var phase: String = demo_flow_manager.get_case_phase()
	var dialogue_reply_applied: bool = _apply_dialogue_door_reply(true)
	demo_flow_manager.set_cabin_door_open(true)
	if phase in ["ARRIVED_AT_PICKUP", "DOOR_GREETING_DONE"]:
		demo_flow_manager.set_passenger_onboard(true)
		demo_flow_manager.set_cabin_door_closed_after_boarding(false)
		demo_flow_manager.set_case_phase("BOARDING_WAIT_DOOR_CLOSE")
		dm_dialogue_started = false
		dm_dialogue_finished = false
		dm_choices.clear()
		if not dialogue_reply_applied:
			current_passenger_line = demo_flow_manager.get_after_open_line()
		_show_system_hint(demo_flow_manager.get_after_open_hint())
		_update_camera_display()
		_update_dialogue_buttons()
		_update_microphone_display()
		if not dialogue_reply_applied:
			passenger_speech_label.text = current_passenger_line
	elif phase == "ARRIVED_AT_DESTINATION" \
			and demo_flow_manager.is_cabin_door_closed_after_boarding():
		demo_flow_manager.set_case_phase("DROPOFF_FEEDBACK")
		_show_destination_feedback_for_current_floor()
		_update_microphone_display()
		_update_dialogue_buttons()
		_update_dialogue_visibility()


func _handle_close_door() -> void:
	print("Door action: 关门")
	if demo_flow_manager == null:
		return
	if not demo_flow_manager.is_cabin_door_open():
		_show_system_hint("舱门已经关闭。")
		return
	var phase: String = demo_flow_manager.get_case_phase()
	if phase == "DROPOFF_FEEDBACK":
		_show_system_hint("请等待乘客反馈结束后再关闭舱门。")
		return
	demo_flow_manager.set_cabin_door_open(false)
	var dialogue_reply_applied: bool = _apply_dialogue_door_reply(false)
	if phase == "DROPOFF_WAIT_DOOR_CLOSE":
		demo_flow_manager.complete_active_dispatch()
		return
	if phase != "BOARDING_WAIT_DOOR_CLOSE":
		return
	# 登舱后必须显式关门，正式舱内询问才会解锁。
	demo_flow_manager.set_cabin_door_closed_after_boarding(true)
	demo_flow_manager.set_case_phase("PASSENGER_ONBOARD")
	dm_dialogue_started = false
	dm_dialogue_finished = false
	dm_choices.clear()
	if not dialogue_reply_applied:
		current_passenger_line = demo_flow_manager.get_after_close_line()
	_show_system_hint(demo_flow_manager.get_after_close_hint())
	demo_flow_manager.set_building_status_hint(demo_flow_manager.get_after_close_status_hint())
	if mic_enabled:
		_start_dialogue_manager_passenger()
	_update_camera_display()
	_update_dialogue_buttons()
	_update_microphone_display()
	if not dialogue_reply_applied:
		passenger_speech_label.text = current_passenger_line


func _apply_dialogue_door_reply(is_open_action: bool) -> bool:
	# 门控按钮本身触发乘客回应；不提前根据门状态生成分支对白。
	if dialogue_manager_adapter == null:
		return false
	var reply: String = dialogue_manager_adapter.consume_open_door_reply() \
		if is_open_action else dialogue_manager_adapter.consume_close_door_reply()
	if reply.is_empty():
		return false
	current_passenger_line = reply
	if mic_enabled:
		passenger_speech_label.text = current_passenger_line
	if demo_flow_manager != null:
		demo_flow_manager.add_front_transcript_passenger(current_passenger_line)
	return true


func _refresh_case_display() -> void:
	_clear_pickup_dialogue_after_departure()
	_update_dispatch_panel()
	_update_camera_display()
	_update_dialogue_buttons()
	_update_dialogue_visibility()
	if demo_flow_manager != null:
		# 即使存在快捷键或旧场景连接，运行中也不能执行开门。
		open_door_button.disabled = demo_flow_manager.is_elevator_moving()
		talk_button.disabled = not demo_flow_manager.has_active_dispatch()
		system_hint_label.text = demo_flow_manager.get_current_building_status_hint()


func _clear_pickup_dialogue_after_departure() -> void:
	# 已完成门外确认但尚未登舱时可以离开；此时不能继续保留 612 门外对话。
	if demo_flow_manager == null \
			or demo_flow_manager.is_passenger_onboard() \
			or demo_flow_manager.get_case_phase() != "WAITING_FOR_PICKUP":
		return
	if not dm_dialogue_started and dm_choices.is_empty():
		return
	dm_dialogue_started = false
	dm_dialogue_finished = false
	dm_choices.clear()
	current_passenger_line = "乘客舱音频链路待机。"
	_update_microphone_display()


func _update_dispatch_panel() -> void:
	if demo_flow_manager == null:
		return
	if not demo_flow_manager.has_active_dispatch():
		state_label.text = "当前状态：值班待命"
		dispatch_info_label.text = "当前派单：无\n当前任务：暂无待处理派单"
		return
	var phase: String = demo_flow_manager.get_case_phase()
	var phase_text: Dictionary = demo_flow_manager.get_front_phase_text(phase)
	state_label.text = str(phase_text.get("state", ""))
	var task_text: String = str(phase_text.get("task", ""))
	# 乘客未登舱前不在主操作台暴露身份；接乘点仅显示待处理任务。
	if demo_flow_manager.is_passenger_onboard():
		dispatch_info_label.text = "当前乘客：%s\n%s" % [
			demo_flow_manager.get_passenger_label(), task_text,
		]
	else:
		dispatch_info_label.text = task_text


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)

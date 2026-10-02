extends Control
class_name ConsoleInterface


const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)


signal return_requested
signal camera_selected(camera_index: int)
signal mic_enabled_changed(enabled: bool)
signal case_phase_display_changed(text: String)
signal presentation_effects_requested(effects: Array[StringName])


const DialogueManagerAdapterScript := preload("res://scripts/dialogue/dialogue_manager_adapter.gd")

const CAMERA_NAMES: Array[String] = [
	"CAM 01｜舱内摄像头",
	"CAM 02｜门外摄像头",
]
const DOOR_PRESENTATION_BUSY_HINT: String = \
		"舱门机构正在运行，请等待动作完成。"
const PRESENTATION_BUSY_HINT: String = \
		"监控表现流程尚未完成，请等待乘客与舱门动作结束。"

enum DialogueContext {
	NONE,
	PICKUP,
	ONBOARD,
	DESTINATION,
}


# 业务状态不再依赖旧 2D 控件；通讯窗保留玩家实际使用的 UI。
@onready var comm_view: FloatingCommUI = $FloatingCommUI
@onready var passenger_speech_label: Label = comm_view.speech_label
@onready var rejection_toast: Label = $RejectionToast
@onready var toast_timer: Timer = $ToastTimer
var demo_flow_manager: DemoFlowManager
var _monitor_stage_controller: MonitorStageController3D
var _monitor_presentation_coordinator: MonitorPresentationCoordinator3D
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
var _choice_in_progress: bool = false
var _system_hint: String = ""

func _ready() -> void:
	_create_dialogue_manager_adapter()
	comm_view.choice_selected.connect(_select_dialogue_manager_choice)
	toast_timer.timeout.connect(rejection_toast.hide)
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


func _initialize_front_interaction() -> void:
	current_camera_index = 0
	mic_enabled = false
	dm_dialogue_started = false
	dm_dialogue_finished = false
	dm_choices.clear()
	current_passenger_line = "乘客舱音频链路待机。"

	_update_microphone_display()
	_update_dialogue_buttons()
	_update_dispatch_panel()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		_sync_door_presentation_to_business_state()
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
	_sync_door_presentation_to_business_state()


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


func set_monitor_stage_controller(stage_controller: MonitorStageController3D) -> void:
	_monitor_stage_controller = stage_controller
	_sync_door_presentation_to_business_state()


func set_monitor_presentation_coordinator(coordinator: MonitorPresentationCoordinator3D) -> void:
	_monitor_presentation_coordinator = coordinator


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
	_refresh_case_display()
	show()
	_refresh_comm_view()


func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_comm_view()


func request_select_camera(camera_index: int) -> void:
	if camera_index in [0, 1]:
		_select_camera(camera_index)


func _select_camera(camera_index: int) -> void:
	# 摄像头只切换证据画面，不再决定麦克风是否可以对话。
	current_camera_index = clampi(camera_index, 0, CAMERA_NAMES.size() - 1)
	_show_system_hint("已切换至 %s。" % CAMERA_NAMES[current_camera_index])
	_update_dialogue_visibility()
	camera_selected.emit(current_camera_index)


func get_current_camera_index() -> int:
	return current_camera_index


func request_toggle_microphone() -> void:
	# 麦克风目前只是交互状态占位，不接入真实录音。
	if demo_flow_manager == null or not demo_flow_manager.has_active_dispatch():
		_show_system_hint("当前没有可通话的乘客派单。", true)
		return
	mic_enabled = not mic_enabled

	if mic_enabled and not dm_dialogue_started and not dm_dialogue_finished:
		if not _start_dialogue_manager_passenger():
			current_passenger_line = _get_phase_passenger_line()
	_update_microphone_display()

	if mic_enabled:
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
	if phase == DispatchPhase.ARRIVED_AT_PICKUP and not demo_flow_manager.is_door_greeting_done():
		return "pickup_start"
	if phase == DispatchPhase.PASSENGER_ONBOARD \
			and demo_flow_manager.is_passenger_onboard() \
			and demo_flow_manager.is_cabin_door_closed_after_boarding():
		return "onboard_start"
	return ""


func _update_microphone_display() -> void:
	var should_show_passenger_line: bool = mic_enabled or dm_dialogue_started
	passenger_speech_label.text = current_passenger_line \
		if should_show_passenger_line else "乘客舱音频链路待机。"
	mic_enabled_changed.emit(mic_enabled)
	_update_dialogue_visibility()


func _update_dialogue_visibility() -> void:
	_refresh_comm_view()


func _update_dialogue_buttons() -> void:
	_refresh_comm_view()


func _refresh_comm_view() -> void:
	var can_choose := mic_enabled and dm_dialogue_started and not dm_dialogue_finished
	comm_view.present(mic_enabled, current_passenger_line, dm_choices,
			can_choose and not _choice_in_progress, dm_dialogue_started)


func _select_dialogue_choice(choice_index: int) -> void:
	_select_dialogue_manager_choice(choice_index)


func _select_dialogue_manager_choice(choice_index: int) -> void:
	if not mic_enabled or not dm_dialogue_started or dm_dialogue_finished \
			or _choice_in_progress or dialogue_manager_adapter == null:
		return
	if choice_index < 0 or choice_index >= dm_choices.size():
		return

	if not bool(dm_choices[choice_index].get("is_allowed", true)):
		return
	_choice_in_progress = true
	_refresh_comm_view()
	var operator_line: String = str(dm_choices[choice_index].get("text", ""))
	if demo_flow_manager != null:
		demo_flow_manager.add_front_transcript_operator(operator_line)
	_begin_dm_front_hint_batch()
	await dialogue_manager_adapter.choose_response(choice_index)
	_choice_in_progress = false
	_refresh_comm_view()


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
		var result: FlowCommandResultScript = \
				demo_flow_manager.request_finish_dropoff_feedback()
		if not result.succeeded:
			_show_command_rejection(result)
		else:
			presentation_effects_requested.emit(result.get_effects())


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
	var result: FlowCommandResultScript = \
			demo_flow_manager.request_complete_door_greeting()
	if not result.succeeded:
		_show_command_rejection(result)
	_update_dialogue_buttons()
	_update_dialogue_visibility()


func _show_destination_feedback_for_current_floor() -> void:
	# 到站本身不触发乘客反馈；只有玩家开门时才按当前楼层读取 destination_xxx。
	if demo_flow_manager == null:
		return
	var current_floor: String = demo_flow_manager.get_current_floor()
	if dialogue_manager_adapter == null:
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
	if phase == DispatchPhase.ARRIVED_AT_PICKUP:
		var outside_audio_idle: String = demo_flow_manager.get_outside_audio_idle()
		return outside_audio_idle if not outside_audio_idle.is_empty() else "门外音频链路已开启。"
	if phase == DispatchPhase.BOARDING_WAIT_DOOR_CLOSE:
		return demo_flow_manager.get_after_open_line()
	if phase == DispatchPhase.PASSENGER_ONBOARD:
		# 乘客对正式目标楼层的反馈统一来自 .dialogue 的 destination_xxx 标题。
		return current_passenger_line
	if phase == DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE:
		return "乘客已离舱。"
	return "乘客舱音频链路待机。"


func _show_system_hint(hint_text: String, is_rejection: bool = false) -> void:
	# FRONT 的短提示不自动写入历史，避免左侧日志重复玩家刚完成的操作。
	_system_hint = hint_text
	if embedded_3d_mode and is_rejection and not hint_text.is_empty():
		rejection_toast.text = hint_text
		rejection_toast.show()
		toast_timer.start()


func _show_command_rejection(result: FlowCommandResultScript) -> void:
	var needs_explanation: bool = result.code not in [&"DOOR_ALREADY_OPEN", &"DOOR_ALREADY_CLOSED"]
	_show_system_hint(result.message, needs_explanation)


func _record_system_log(message_text: String) -> void:
	if demo_flow_manager != null:
		demo_flow_manager.add_system_log_message(message_text)


func request_open_door() -> void:
	# 实体热点统一调用流程命令；UI 只处理表现效果。
	if _is_presentation_busy():
		_show_system_hint(_get_presentation_busy_hint(), true)
		return
	if demo_flow_manager == null:
		return
	var result: FlowCommandResultScript = \
			demo_flow_manager.request_open_cabin_door()
	if not result.succeeded:
		_show_command_rejection(result)
		return

	if result.has_effect(FlowCommandResultScript.DOOR_OPENED):
		_request_door_open_presentation()
	presentation_effects_requested.emit(result.get_effects())

	if result.has_effect(FlowCommandResultScript.PASSENGER_BOARDED):
		dm_dialogue_started = false
		dm_dialogue_finished = false
		dm_choices.clear()
		var dialogue_reply_applied: bool = _apply_dialogue_door_reply(true)
		if not dialogue_reply_applied:
			current_passenger_line = demo_flow_manager.get_after_open_line()
		_show_system_hint(result.message)
		_update_dialogue_buttons()
		_update_microphone_display()
		if not dialogue_reply_applied:
			passenger_speech_label.text = current_passenger_line
	elif result.has_effect(
			FlowCommandResultScript.DROPOFF_FEEDBACK_REQUESTED
	):
		_show_destination_feedback_for_current_floor()
		_update_microphone_display()
		_update_dialogue_buttons()
		_update_dialogue_visibility()
	else:
		if not result.message.is_empty():
			_show_system_hint(result.message)


func request_close_door() -> void:
	# 关闭规则由流程命令处理，UI 仅根据 effects 解锁对应表现。
	if _is_presentation_busy():
		_show_system_hint(_get_presentation_busy_hint(), true)
		return
	if demo_flow_manager == null:
		return
	var result: FlowCommandResultScript = \
			demo_flow_manager.request_close_cabin_door()
	if not result.succeeded:
		_show_command_rejection(result)
		return

	# 先触发表现，再处理完成派单等早退分支，保证最后一次关门不漏播。
	if result.has_effect(FlowCommandResultScript.DOOR_CLOSED):
		_request_door_close_presentation()
	presentation_effects_requested.emit(result.get_effects())

	if result.has_effect(FlowCommandResultScript.DISPATCH_COMPLETED):
		return
	if result.has_effect(
			FlowCommandResultScript.ONBOARD_DIALOGUE_AVAILABLE
	):
		# 登舱后的关门结果才会解锁正式舱内询问。
		dm_dialogue_started = false
		dm_dialogue_finished = false
		dm_choices.clear()
		var dialogue_reply_applied: bool = _apply_dialogue_door_reply(false)
		if not dialogue_reply_applied:
			current_passenger_line = demo_flow_manager.get_after_close_line()
		_show_system_hint(result.message)
		if mic_enabled:
			_start_dialogue_manager_passenger()
		_update_dialogue_buttons()
		_update_microphone_display()
		if not dialogue_reply_applied:
			passenger_speech_label.text = current_passenger_line
	else:
		if not result.message.is_empty():
			_show_system_hint(result.message)


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


func _is_door_presentation_busy() -> bool:
	return is_instance_valid(_monitor_stage_controller) \
			and _monitor_stage_controller.is_door_presentation_busy()


func _is_presentation_busy() -> bool:
	if is_instance_valid(_monitor_presentation_coordinator):
		return _monitor_presentation_coordinator.is_presentation_busy()
	return _is_door_presentation_busy()


func _get_presentation_busy_hint() -> String:
	if is_instance_valid(_monitor_presentation_coordinator):
		return PRESENTATION_BUSY_HINT
	return DOOR_PRESENTATION_BUSY_HINT


func _sync_door_presentation_to_business_state() -> void:
	if demo_flow_manager == null \
			or not is_instance_valid(_monitor_stage_controller):
		return
	if not _monitor_stage_controller.sync_door_presentation(
			demo_flow_manager.is_cabin_door_open()
	):
		push_warning("ConsoleInterface: 双开门表现无法与业务门状态同步。")


func _request_door_open_presentation() -> void:
	if not is_instance_valid(_monitor_stage_controller):
		return
	if _monitor_stage_controller.request_door_open_presentation():
		return
	push_warning("ConsoleInterface: 业务开门成功，但开门动画未能启动。")
	_sync_door_presentation_to_business_state()


func _request_door_close_presentation() -> void:
	if not is_instance_valid(_monitor_stage_controller):
		return
	if _monitor_stage_controller.request_door_close_presentation():
		return
	push_warning("ConsoleInterface: 业务关门成功，但关门动画未能启动。")
	_sync_door_presentation_to_business_state()


func _refresh_case_display() -> void:
	_clear_pickup_dialogue_after_departure()
	_update_dispatch_panel()
	_update_dialogue_buttons()
	_update_dialogue_visibility()
	if demo_flow_manager != null:
		_system_hint = demo_flow_manager.get_current_building_status_hint()


func _clear_pickup_dialogue_after_departure() -> void:
	# 已完成门外确认但尚未登舱时可以离开；此时不能继续保留 612 门外对话。
	if demo_flow_manager == null \
			or demo_flow_manager.is_passenger_onboard() \
			or demo_flow_manager.get_case_phase() != DispatchPhase.WAITING_FOR_PICKUP:
		return
	if not dm_dialogue_started and dm_choices.is_empty():
		return
	dm_dialogue_started = false
	dm_dialogue_finished = false
	dm_choices.clear()
	current_passenger_line = "乘客舱音频链路待机。"
	_update_microphone_display()


func _update_dispatch_panel() -> void:
	case_phase_display_changed.emit(get_case_phase_display_text())


func get_case_phase_display_text() -> String:
	if demo_flow_manager == null or not demo_flow_manager.has_active_dispatch():
		return "CASE — · 值班待命"
	var dispatch := demo_flow_manager.get_active_dispatch()
	var phase_text := demo_flow_manager.get_front_phase_text(demo_flow_manager.get_case_phase())
	return "%s · %s" % [
		String(dispatch.dispatch_id).replace("_", " "),
		str(phase_text.get("state", "")).trim_prefix("当前状态："),
	]

# 提示快照供表现层和测试读取，不借用隐藏 Label 保存业务数据。
func get_system_hint() -> String:
	return _system_hint

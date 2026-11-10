extends Control
class_name ConsoleInterface


const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)


signal camera_selected(camera_index: int)
signal case_phase_display_changed(text: String)
signal presentation_effects_requested(effects: Array[StringName])
signal excerpt_button_pressed


const DialogueManagerAdapterScript := preload("res://scripts/dialogue/dialogue_manager_adapter.gd")

const CAMERA_NAMES: Array[String] = [
	"CAM 01｜舱内摄像头",
	"CAM 02｜门外摄像头",
]
const DOOR_PRESENTATION_BUSY_HINT: String = \
		"舱门机构正在运行，请等待动作完成。"
const PRESENTATION_BUSY_HINT: String = \
		"监控表现流程尚未完成，请等待乘客与舱门动作结束。"


@onready var rejection_toast: Label = $RejectionToast
@onready var toast_timer: Timer = $ToastTimer
var demo_flow_manager: DemoFlowManager
var _monitor_stage_controller: MonitorStageController3D
var _monitor_presentation_coordinator: MonitorPresentationCoordinator3D
var dialogue_manager_adapter: DialogueManagerAdapter
var current_camera_index: int = 0
var dm_pending_status_hint_update: bool = false
var dm_pending_unlocked_floor_ids: Array[String] = []
var embedded_3d_mode: bool = false
var _system_hint: String = ""
var _excerpt_source: Callable

func _ready() -> void:
	dialogue_manager_adapter = DialogueManagerAdapterScript.new()
	dialogue_manager_adapter.name = "DialogueManagerAdapter"
	add_child(dialogue_manager_adapter)
	dialogue_manager_adapter.scoped_mutation_requested.connect(_on_dm_scoped_mutation)
	toast_timer.timeout.connect(rejection_toast.hide)
	_update_dispatch_panel()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		_sync_door_presentation_to_business_state()
		return
	_disconnect_demo_flow_manager()
	demo_flow_manager = flow_manager
	if dialogue_manager_adapter != null:
		dialogue_manager_adapter.bind_flow_manager(flow_manager)
	if demo_flow_manager == null:
		push_warning("ConsoleInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.connect(_refresh_case_display)
	demo_flow_manager.document_session_changed.connect(_on_dialogue_session_changed)
	demo_flow_manager.passenger_event_pending.connect(_schedule_passenger_events)
	demo_flow_manager.set_review_delivery_ready(_can_deliver_review)
	_reset_dispatch_ui_state()
	_schedule_passenger_events()
	_refresh_case_display()
	_sync_door_presentation_to_business_state()


func _disconnect_demo_flow_manager() -> void:
	if demo_flow_manager == null:
		return
	demo_flow_manager.set_review_delivery_ready(Callable())
	if demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.disconnect(_refresh_case_display)
	if demo_flow_manager.passenger_event_pending.is_connected(_schedule_passenger_events):
		demo_flow_manager.passenger_event_pending.disconnect(_schedule_passenger_events)
	if demo_flow_manager.document_session_changed.is_connected(_on_dialogue_session_changed):
		demo_flow_manager.document_session_changed.disconnect(_on_dialogue_session_changed)


func set_monitor_stage_controller(stage_controller: MonitorStageController3D) -> void:
	_monitor_stage_controller = stage_controller
	_sync_door_presentation_to_business_state()


func set_monitor_presentation_coordinator(coordinator: MonitorPresentationCoordinator3D) -> void:
	_monitor_presentation_coordinator = coordinator


func _on_dialogue_session_changed(_session: int) -> void:
	_reset_dispatch_ui_state()
	_refresh_case_display()


func _reset_dispatch_ui_state() -> void:
	toast_timer.stop()
	rejection_toast.hide()
	dm_pending_status_hint_update = false
	dm_pending_unlocked_floor_ids.clear()
	dialogue_manager_adapter.reset_dialogue()


func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func request_select_camera(camera_index: int) -> void:
	if camera_index in [0, 1]:
		_select_camera(camera_index)


func _select_camera(camera_index: int) -> void:
	# 摄像头只切换证据画面。
	current_camera_index = clampi(camera_index, 0, CAMERA_NAMES.size() - 1)
	_show_system_hint("已切换至 %s。" % CAMERA_NAMES[current_camera_index])
	camera_selected.emit(current_camera_index)


func get_current_camera_index() -> int:
	return current_camera_index


func _on_dm_scoped_mutation(scope: RefCounted, kind: StringName, value: String) -> void:
	if not scope.is_current(dialogue_manager_adapter, demo_flow_manager):
		return
	match kind:
		&"status_hint": _on_dm_status_hint_requested(value, scope)
		&"unlock_floor": _on_dm_floor_unlock_requested(value, scope)
		&"door_greeting": _on_dm_door_greeting_done_requested(scope)


func _on_dm_status_hint_requested(text: String, scope: RefCounted) -> void:
	# DM 的详细判断写入 LEFT 系统日志；FRONT 只显示短操作提示，避免复读正文。
	if demo_flow_manager != null:
		demo_flow_manager.set_building_status_hint(text)
	if not scope.is_current(dialogue_manager_adapter, demo_flow_manager):
		return
	dm_pending_status_hint_update = true
	_apply_dm_front_hint_batch()


func _on_dm_floor_unlock_requested(floor_id: String, scope: RefCounted) -> void:
	var normalized_floor_id: String = floor_id.strip_edges()
	# Dialogue mutation 直接修改派单状态，右台通过 case_updated 自动刷新。
	if demo_flow_manager != null:
		demo_flow_manager.add_recommended_destination(normalized_floor_id)
	if not scope.is_current(dialogue_manager_adapter, demo_flow_manager):
		return
	if not normalized_floor_id.is_empty() and normalized_floor_id not in dm_pending_unlocked_floor_ids:
		dm_pending_unlocked_floor_ids.append(normalized_floor_id)
	_apply_dm_front_hint_batch()



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


func _on_dm_door_greeting_done_requested(scope: RefCounted) -> void:
	# DM 只完成“门外乘客已确认”；后续开门、进舱、关门仍走原有门控 phase。
	if demo_flow_manager == null:
		return
	var result: FlowCommandResultScript = \
			demo_flow_manager.request_complete_door_greeting()
	if not scope.is_current(dialogue_manager_adapter, demo_flow_manager):
		return
	if not result.succeeded:
		_show_command_rejection(result)


func set_excerpt_source(source: Callable) -> void:
	_excerpt_source = source


func request_excerpt_current_call() -> void:
	var manager := demo_flow_manager
	var session := manager.get_document_session_id() if manager != null else 0
	var event_id: String = _excerpt_source.call() if _excerpt_source.is_valid() else ""
	excerpt_button_pressed.emit()
	if session == 0:
		_show_system_hint("当前没有可摘录的乘客派单。", false, true)
		return
	if not is_instance_valid(manager) or manager != demo_flow_manager or manager.get_document_session_id() != session:
		return
	var result := manager.acquire_main_call_excerpt(session, event_id)
	if manager != demo_flow_manager or manager.get_document_session_id() != session:
		return
	match result.code:
		&"UNCHANGED":
			_show_system_hint("该陈述已在 W 收件箱。", false, true)
		&"EXCERPT_NOT_PRESENTED":
			_show_system_hint("当前陈述尚未完整呈现。", false, true)
		&"NO_EXCERPT":
			_show_system_hint("暂无已呈现的乘客陈述。", false, true)
		_:
			_show_system_hint("已摘录至 W 收件箱。" if result.succeeded else "暂无法摘录当前陈述。", false, true)


func _show_system_hint(hint_text: String, is_rejection: bool = false, show_toast: bool = false) -> void:
	# FRONT 的短提示不自动写入历史，避免左侧日志重复玩家刚完成的操作。
	_system_hint = hint_text
	if embedded_3d_mode and (is_rejection or show_toast) and not hint_text.is_empty():
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
	var session := demo_flow_manager.get_document_session_id()
	var result: FlowCommandResultScript = \
			demo_flow_manager.request_open_cabin_door()
	if not result.succeeded:
		_show_command_rejection(result)
		return

	if result.has_effect(FlowCommandResultScript.DOOR_OPENED):
		_request_door_open_presentation()
	presentation_effects_requested.emit(result.get_effects())

	if result.has_effect(FlowCommandResultScript.DROPOFF_FEEDBACK_REQUESTED) \
			and session == demo_flow_manager.get_document_session_id():
		# 保留原离舱效果，由门动画和表现联锁接管，不等待可选陈述。
		var finished := demo_flow_manager.request_finish_dropoff_feedback()
		if finished.succeeded:
			presentation_effects_requested.emit(finished.get_effects())
		else:
			_show_command_rejection(finished)
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
	if not result.message.is_empty():
		_show_system_hint(result.message)


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
	_update_dispatch_panel()
	if demo_flow_manager != null:
		_system_hint = demo_flow_manager.get_current_building_status_hint()


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


func _schedule_passenger_events() -> void:
	# 命令先返回门控等业务效果，再独立解析可选陈述。
	dialogue_manager_adapter.process_pending_events.call_deferred()


func _can_deliver_review() -> bool:
	return _excerpt_source.is_valid() and dialogue_manager_adapter.can_accept_review()

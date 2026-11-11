extends Node
class_name DemoFlowManager


# 协调层继续发送原有信号，三个 UI 不需要知道内部模块已经拆分。
signal case_updated
signal elevator_movement_completed(arrived_floor: String)
signal dispatch_started(dispatch_id: StringName)
signal disembark_requested(action: Dictionary)
signal passenger_event_pending
signal passenger_event_changed

const REVIEW_QUEUE_LIMIT := 4
var _review_delivery_ready: Callable
signal dispatch_completed(result: DispatchResult)
signal shift_completed
# 左台只订阅“既有内容已变化”的窄通知；业务内容仍由 UIHistoryState / Resource 唯一持有。
signal left_terminal_section_updated(section_id: StringName)
signal left_terminal_session_reset(has_active_dispatch: bool)
signal document_session_changed(session_id: int)
signal documents_changed(session_id: int)
signal material_requested(session_id: int)
signal contradiction_challenge_recorded(session_id: int)


const LEFT_SECTION_SYSTEM_LOG: StringName = &"system_log"
const LEFT_SECTION_PASSENGER_RECORD: StringName = &"passenger_record"


const ElevatorRuntimeStateScript := preload(
	"res://scripts/runtime/elevator/elevator_runtime_state.gd"
)
const DispatchLifecycleScript := preload(
	"res://scripts/runtime/dispatch/dispatch_lifecycle.gd"
)
const ShiftRunnerScript := preload("res://scripts/runtime/shift/shift_runner.gd")
const UIHistoryStateScript := preload("res://scripts/runtime/ui/ui_history_state.gd")
const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)

@export var initial_floor: String = "318"
@export_range(0.1, 5.0, 0.1, "suffix:s") var movement_duration_seconds: float = 0.6
@export var initial_shift: ShiftDefinition

var elevator_runtime_state: ElevatorRuntimeStateScript
var dispatch_lifecycle: DispatchLifecycleScript
var shift_runner: ShiftRunnerScript
var ui_history_state: UIHistoryStateScript
var _document_applicability_resolver: Callable
var _document_command_busy: bool = false
var _travel_busy_query: Callable


func _ready() -> void:
	_initialize_runtime_components()
	elevator_runtime_state.initialize(initial_floor, movement_duration_seconds)
	case_updated.emit()
	# 未配置值班时正常空舱待机；后续流程由显式命令启动。
	if initial_shift != null:
		start_shift(initial_shift)


func _initialize_runtime_components() -> void:
	# 组件由协调层直接持有；重复初始化不会按节点名称搜索或创建第二份状态。
	if elevator_runtime_state == null:
		elevator_runtime_state = ElevatorRuntimeStateScript.new()
		elevator_runtime_state.name = "ElevatorRuntimeState"
		add_child(elevator_runtime_state)
	if not elevator_runtime_state.movement_completed.is_connected(
		_on_elevator_movement_completed
	):
		elevator_runtime_state.movement_completed.connect(
			_on_elevator_movement_completed
		)
	if dispatch_lifecycle == null:
		dispatch_lifecycle = DispatchLifecycleScript.new()
	if shift_runner == null:
		shift_runner = ShiftRunnerScript.new()
	if ui_history_state == null:
		ui_history_state = UIHistoryStateScript.new()


func start_dispatch(dispatch_id: StringName) -> bool:
	return _start_dispatch_internal(dispatch_id, true)


func _start_dispatch_internal(
		dispatch_id: StringName,
		should_emit_case_updated: bool
) -> bool:
	var dispatch: DispatchDefinition = ContentRegistry.get_dispatch(String(dispatch_id))
	if dispatch == null:
		push_error("DemoFlowManager: 无法开始不存在的派单：%s" % dispatch_id)
		return false

	var initial_phase: String = DispatchPhase.ARRIVED_AT_PICKUP \
			if get_current_floor() == String(dispatch.pickup_floor_id) \
			else DispatchPhase.WAITING_FOR_PICKUP
	if not dispatch_lifecycle.start_dispatch(dispatch, initial_phase):
		return false

	elevator_runtime_state.clear_target_floor()
	var initial_hint: String
	if initial_phase == DispatchPhase.ARRIVED_AT_PICKUP:
		initial_hint = "新派单已建立。\n当前楼层检测到等待乘客。\n可通过门外摄像头确认，或直接开启舱门。"
	else:
		initial_hint = "新派单已建立。\n%s 层检测到等待乘客。\n请前往接乘楼层。" \
				% String(dispatch.pickup_floor_id)
	ui_history_state.reset_for_new_dispatch(initial_hint)
	var session := get_document_session_id()
	document_session_changed.emit(session)
	_record_passenger_event(session, "dispatch_started")
	if initial_phase == DispatchPhase.ARRIVED_AT_PICKUP:
		_record_passenger_event(session, "arrived_at_pickup")
	left_terminal_session_reset.emit(true)
	if should_emit_case_updated:
		case_updated.emit()
	return true


func start_shift(shift: ShiftDefinition) -> bool:
	if not shift_runner.start_shift(shift):
		push_error("DemoFlowManager: 无法开始空的值班资源。")
		finish_shift()
		return false
	return start_next_dispatch()


func start_next_dispatch() -> bool:
	return _start_next_dispatch_internal(true)


func _start_next_dispatch_internal(should_emit_case_updated: bool) -> bool:
	# 静态资源校验留在协调层；ShiftRunner 只提供顺序中的下一个 ID。
	while true:
		var dispatch_id: StringName = shift_runner.get_next_dispatch_id()
		if dispatch_id == &"":
			_finish_shift_internal(should_emit_case_updated)
			return false
		if _start_dispatch_internal(dispatch_id, should_emit_case_updated):
			dispatch_started.emit(dispatch_id)
			return true
		push_error("DemoFlowManager: 已跳过无效派单：%s" % dispatch_id)
	return false


func complete_active_dispatch() -> bool:
	# 兼容入口沿用旧返回语义：最后一单完成但没有下一单时仍返回 false。
	var completion: Dictionary = _complete_active_dispatch_internal(true)
	return bool(completion.get("next_dispatch_started", false))


func _complete_active_dispatch_internal(
		should_emit_case_updated: bool
) -> Dictionary:
	var completion := {
		"dispatch_completed": false,
		"next_dispatch_started": false,
		"shift_completed": false,
	}
	if not has_active_dispatch():
		return completion
	var active := dispatch_lifecycle.get_active_state()
	if get_case_phase() != DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE \
			or is_cabin_door_open() or is_elevator_moving() \
			or active.passenger_inside or active.exited_floor_id == &"":
		push_warning("DemoFlowManager: 当前阶段不允许完成派单。")
		return completion

	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return completion
	var result := DispatchResult.create(
		dispatch_lifecycle.get_dispatch_id(),
		dispatch.passenger_id,
		active.exited_floor_id,
		shift_runner.get_completed_count() + 1
	)
	result.requested_floor_id = active.requested_floor_id
	result.travel_legs = active.travel_legs.duplicate(true)
	# 逐次取得记录保留历史版本；只复制引用、来源及取得渠道。
	var session := get_document_session_id()
	for event: Dictionary in active.document_state.get_events(session):
		for ref: Dictionary in event.document_refs:
			var receipt := active.document_state.get_document(session, ref)
			result.acquired_information.append({
				"ref": ref, "source": receipt.document.source,
				"route": receipt.route, "event_id": receipt.event_id,
			})
	shift_runner.record_completed_result(result)
	dispatch_lifecycle.clear()
	document_session_changed.emit(0)
	elevator_runtime_state.clear_target_floor()
	dispatch_completed.emit(result)
	completion["dispatch_completed"] = true
	if should_emit_case_updated:
		case_updated.emit()
	var next_dispatch_started := _start_next_dispatch_internal(
		should_emit_case_updated
	)
	completion["next_dispatch_started"] = next_dispatch_started
	completion["shift_completed"] = not next_dispatch_started \
			and shift_runner.is_finished()
	return completion


func finish_shift() -> void:
	_finish_shift_internal(true)


func _finish_shift_internal(should_emit_case_updated: bool) -> bool:
	if not shift_runner.finish_shift():
		return false
	dispatch_lifecycle.clear()
	document_session_changed.emit(0)
	elevator_runtime_state.clear_target_floor()
	ui_history_state.finish_shift()
	left_terminal_session_reset.emit(false)
	left_terminal_section_updated.emit(LEFT_SECTION_SYSTEM_LOG)
	shift_completed.emit()
	if should_emit_case_updated:
		case_updated.emit()
	return true


func clear_active_dispatch() -> void:
	dispatch_lifecycle.clear()
	document_session_changed.emit(0)
	ui_history_state.clear_active_dispatch()
	left_terminal_session_reset.emit(false)
	case_updated.emit()


func has_active_dispatch() -> bool:
	return dispatch_lifecycle != null and dispatch_lifecycle.has_active_dispatch()


func add_front_transcript_operator(operator_text: String) -> void:
	ui_history_state.add_operator_transcript(operator_text)


func add_front_transcript_passenger(passenger_text: String) -> void:
	ui_history_state.add_passenger_transcript(passenger_text)


func get_front_dialogue_history() -> Array[String]:
	return ui_history_state.get_front_dialogue_history()


func get_current_building_status_hint() -> String:
	return ui_history_state.get_current_building_status_hint()


func set_building_status_hint(
		hint: String,
		include_in_history: bool = true,
		history_text: String = ""
) -> void:
	if ui_history_state.set_building_status_hint(
		hint,
		include_in_history,
		history_text
	):
		if include_in_history:
			left_terminal_section_updated.emit(LEFT_SECTION_SYSTEM_LOG)
		case_updated.emit()


func add_system_log_message(message_text: String) -> void:
	if ui_history_state.add_system_log_message(message_text):
		left_terminal_section_updated.emit(LEFT_SECTION_SYSTEM_LOG)
		case_updated.emit()


func get_system_message_history() -> Array[String]:
	return ui_history_state.get_system_message_history()


func get_passenger_label() -> String:
	var passenger: PassengerDefinition = get_active_passenger()
	if passenger == null:
		return ""
	return passenger.system_name if passenger.display_name.is_empty() \
			else "%s / %s" % [passenger.system_name, passenger.display_name]


func get_active_dispatch() -> DispatchDefinition:
	if not has_active_dispatch():
		return null
	var dispatch_id: StringName = dispatch_lifecycle.get_dispatch_id()
	var dispatch: DispatchDefinition = ContentRegistry.get_dispatch(String(dispatch_id))
	if dispatch == null:
		push_error("DemoFlowManager: 当前状态引用了不存在的派单：%s" % dispatch_id)
	return dispatch


func get_active_passenger() -> PassengerDefinition:
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return null
	return ContentRegistry.get_passenger(String(dispatch.passenger_id))


func get_passenger_archive_text() -> String:
	var passenger: PassengerDefinition = get_active_passenger()
	return passenger.archive_text if passenger != null else ""


func get_pickup_floor() -> String:
	var dispatch: DispatchDefinition = get_active_dispatch()
	return String(dispatch.pickup_floor_id) if dispatch != null else ""


func _get_pickup_text(property_name: String) -> String:
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return ""
	return str(dispatch.pickup_data.get(property_name, ""))


func get_pickup_arrival_status_hint() -> String:
	return _get_pickup_text("arrival_status_hint")


func get_after_open_line() -> String:
	return _get_pickup_text("after_open_line")


func get_after_open_hint() -> String:
	return _get_pickup_text("after_open_hint")


func get_after_close_line() -> String:
	return _get_pickup_text("after_close_line")


func get_after_close_hint() -> String:
	return _get_pickup_text("after_close_hint")


func get_after_close_status_hint() -> String:
	return _get_pickup_text("after_close_status_hint")


func get_outside_audio_idle() -> String:
	return _get_pickup_text("outside_audio_idle")


func get_front_phase_text(phase: String) -> Dictionary:
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return {}
	var phase_texts: Dictionary = dispatch.front_phase_texts
	var text_data: Dictionary = phase_texts.get(
		phase,
		phase_texts.get(DispatchPhase.WAITING_FOR_PICKUP, {})
	).duplicate(true)
	text_data["state"] = _format_case_text(str(text_data.get("state", "")))
	text_data["task"] = _format_case_text(str(text_data.get("task", "")))
	return text_data


func _format_case_text(template: String) -> String:
	return template.replace("{pickup_floor}", get_pickup_floor())


func get_dispatch_from() -> String:
	return get_pickup_floor()


func get_dispatch_to() -> String:
	var dispatch: DispatchDefinition = get_active_dispatch()
	return String(dispatch.default_destination_floor_id) if dispatch != null else ""


func get_dispatch_text() -> String:
	return "%s → %s" % [get_dispatch_from(), get_dispatch_to()]


func get_dispatch_dialogue_path() -> String:
	var dispatch: DispatchDefinition = get_active_dispatch()
	return dispatch.dialogue_path if dispatch != null else ""


func get_dispatch_floor_relation(floor_id: String) -> DispatchFloorRelation:
	if not has_active_dispatch():
		return null
	return ContentRegistry.get_dispatch_floor_relation(
		String(dispatch_lifecycle.get_dispatch_id()),
		floor_id
	)


func request_open_cabin_door() -> FlowCommandResultScript:
	var session := get_document_session_id()
	var previous_phase: String = get_case_phase()
	if is_elevator_moving():
		return FlowCommandResultScript.failure(
			&"ELEVATOR_MOVING",
			"电梯正在运行中，无法开门。",
			previous_phase,
			previous_phase
		)
	if is_cabin_door_open():
		return FlowCommandResultScript.failure(
			&"DOOR_ALREADY_OPEN",
			"舱门已经开启。",
			previous_phase,
			previous_phase
		)

	var result_effects: Array[StringName] = [
		FlowCommandResultScript.DOOR_OPENED,
	]
	var message: String = ""
	if previous_phase in [
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.DOOR_GREETING_DONE,
	]:
		if not dispatch_lifecycle.board_passenger():
			return FlowCommandResultScript.failure(
				&"PHASE_TRANSITION_REJECTED",
				"当前流程阶段无法完成乘客登舱。",
				previous_phase,
				get_case_phase()
			)
		result_effects.append(FlowCommandResultScript.PASSENGER_BOARDED)
		message = get_after_open_hint()
	elif previous_phase == DispatchPhase.ARRIVED_AT_DESTINATION:
		if get_current_floor() != get_selected_target_floor() \
				or not _travel_interlock_clear() \
				or not dispatch_lifecycle.begin_dropoff_feedback():
			return FlowCommandResultScript.failure(
				&"PHASE_TRANSITION_REJECTED",
				"当前流程状态无法开始乘客反馈。",
				previous_phase,
				get_case_phase()
			)
		result_effects.append(
			FlowCommandResultScript.DROPOFF_FEEDBACK_REQUESTED
		)

	# 门状态写入放在阶段原子操作之后；通过前置检查后该基础写入不会失败。
	if not elevator_runtime_state.set_cabin_door_open(true):
		return FlowCommandResultScript.failure(
			&"DOOR_STATE_REJECTED",
			"舱门无法开启。",
			previous_phase,
			get_case_phase()
		)
	case_updated.emit()
	if FlowCommandResultScript.PASSENGER_BOARDED in result_effects:
		_record_passenger_event(session, "passenger_boarded")
	elif FlowCommandResultScript.DROPOFF_FEEDBACK_REQUESTED in result_effects:
		_record_passenger_event(session, "destination_opened", dispatch_lifecycle.get_active_state().travel_legs.size())
	return FlowCommandResultScript.success(
		&"DOOR_OPENED",
		message,
		previous_phase,
		get_case_phase(),
		get_current_floor(),
		result_effects
	)


func request_close_cabin_door() -> FlowCommandResultScript:
	var session := get_document_session_id()
	var previous_phase: String = get_case_phase()
	if not is_cabin_door_open():
		return FlowCommandResultScript.failure(
			&"DOOR_ALREADY_CLOSED",
			"舱门已经关闭。",
			previous_phase,
			previous_phase
		)
	if previous_phase == DispatchPhase.DROPOFF_FEEDBACK:
		return FlowCommandResultScript.failure(
			&"DROPOFF_FEEDBACK_IN_PROGRESS",
			"请等待乘客离舱或安全返回舱内后再关闭舱门。",
			previous_phase,
			previous_phase
		)
	if previous_phase in [DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
			DispatchPhase.ARRIVED_AT_DESTINATION, DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE] \
			and not _travel_interlock_clear():
		return FlowCommandResultScript.failure(
			&"PRESENTATION_BUSY", "舱门或乘客动作尚未安全完成。",
			previous_phase, previous_phase
		)

	var result_effects: Array[StringName] = [
		FlowCommandResultScript.DOOR_CLOSED,
	]
	var message: String = ""
	if previous_phase == DispatchPhase.BOARDING_WAIT_DOOR_CLOSE:
		if not dispatch_lifecycle.secure_passenger_after_door_close():
			return FlowCommandResultScript.failure(
				&"PHASE_TRANSITION_REJECTED",
				"当前流程阶段无法确认乘客已安全登舱。",
				previous_phase,
				get_case_phase()
			)
		result_effects.append(
			FlowCommandResultScript.ONBOARD_DIALOGUE_AVAILABLE
		)
		message = get_after_close_hint()
		ui_history_state.set_building_status_hint(
			get_after_close_status_hint(),
			true
		)
		left_terminal_section_updated.emit(LEFT_SECTION_SYSTEM_LOG)
	elif previous_phase == DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE:
		# 结算前先确认静态派单仍有效，避免关门后才发现无法创建结果。
		if get_active_dispatch() == null:
			return FlowCommandResultScript.failure(
				&"NO_ACTIVE_DISPATCH",
				"当前没有可结算的派单。",
				previous_phase,
				previous_phase
			)

	if not elevator_runtime_state.set_cabin_door_open(false):
		return FlowCommandResultScript.failure(
			&"DOOR_STATE_REJECTED",
			"舱门无法关闭。",
			previous_phase,
			get_case_phase()
		)

	if previous_phase == DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE:
		var completion: Dictionary = _complete_active_dispatch_internal(false)
		if not bool(completion.get("dispatch_completed", false)):
			# 前置条件已全部验证；此分支仅保护意外的内部失败。
			elevator_runtime_state.set_cabin_door_open(true)
			return FlowCommandResultScript.failure(
				&"DISPATCH_COMPLETION_REJECTED",
				"当前派单无法完成。",
				previous_phase,
				get_case_phase()
			)
		result_effects.append(FlowCommandResultScript.DISPATCH_COMPLETED)
		if bool(completion.get("next_dispatch_started", false)):
			result_effects.append(
				FlowCommandResultScript.NEXT_DISPATCH_STARTED
			)
			message = "本次派单已完成，下一条派单已开始。"
		elif bool(completion.get("shift_completed", false)):
			result_effects.append(FlowCommandResultScript.SHIFT_COMPLETED)
			message = "本次派单已完成，值班已结束。"

	case_updated.emit()
	if FlowCommandResultScript.ONBOARD_DIALOGUE_AVAILABLE in result_effects:
		_record_passenger_event(session, "onboard_secured")
	return FlowCommandResultScript.success(
		&"DOOR_CLOSED",
		message,
		previous_phase,
		get_case_phase(),
		get_current_floor(),
		result_effects
	)


func request_complete_door_greeting() -> FlowCommandResultScript:
	var previous_phase: String = get_case_phase()
	if not dispatch_lifecycle.complete_door_greeting():
		return FlowCommandResultScript.failure(
			&"PHASE_TRANSITION_REJECTED",
			"当前阶段无法完成门外确认。",
			previous_phase,
			get_case_phase()
		)
	var result_effects: Array[StringName] = [
		FlowCommandResultScript.DOOR_GREETING_COMPLETED,
	]
	case_updated.emit()
	return FlowCommandResultScript.success(
		&"DOOR_GREETING_COMPLETED",
		"门外乘客确认已完成。",
		previous_phase,
		get_case_phase(),
		"",
		result_effects
	)


func request_validate_destination(floor_id: String) -> FlowCommandResultScript:
	var previous_phase: String = get_case_phase()
	var normalized_floor_id: String = floor_id.strip_edges()
	if normalized_floor_id.is_empty():
		return _clear_validation_for_failed_command(
			&"EMPTY_FLOOR_ID",
			"请输入目标楼层。",
			previous_phase,
			normalized_floor_id
		)
	if not ContentRegistry.has_floor(normalized_floor_id):
		return _clear_validation_for_failed_command(
			&"UNKNOWN_FLOOR",
			"无法识别目标楼层：%s。" % normalized_floor_id,
			previous_phase,
			normalized_floor_id
		)

	if has_active_dispatch():
		dispatch_lifecycle.set_validated_floor(normalized_floor_id)
		case_updated.emit()
	var result_effects: Array[StringName] = [
		FlowCommandResultScript.DESTINATION_VALIDATED,
	]
	return FlowCommandResultScript.success(
		&"DESTINATION_VALIDATED",
		"目标已验证：%s。" % normalized_floor_id,
		previous_phase,
		get_case_phase(),
		normalized_floor_id,
		result_effects
	)


func _clear_validation_for_failed_command(
		result_code: StringName,
		result_message: String,
		previous_phase: String,
		normalized_floor_id: String
) -> FlowCommandResultScript:
	var result_effects: Array[StringName] = []
	if has_active_dispatch() and not get_validated_floor().is_empty():
		# 主要验证目标虽失败，但旧验证确实被清除，因此仍报告清理 effect。
		dispatch_lifecycle.set_validated_floor("")
		result_effects.append(FlowCommandResultScript.VALIDATION_CLEARED)
		case_updated.emit()
	return FlowCommandResultScript.failure(
		result_code,
		result_message,
		previous_phase,
		get_case_phase(),
		normalized_floor_id,
		result_effects
	)


func request_clear_destination_validation() -> FlowCommandResultScript:
	var previous_phase: String = get_case_phase()
	var validation_changed: bool = has_active_dispatch() \
			and not get_validated_floor().is_empty()
	if has_active_dispatch():
		dispatch_lifecycle.set_validated_floor("")
	if validation_changed:
		case_updated.emit()
	var result_effects: Array[StringName] = [
		FlowCommandResultScript.VALIDATION_CLEARED,
	]
	return FlowCommandResultScript.success(
		&"VALIDATION_CLEARED",
		"",
		previous_phase,
		get_case_phase(),
		"",
		result_effects
	)


func set_travel_busy_query(query: Callable) -> void:
	_travel_busy_query = query


func _travel_interlock_busy() -> Variant:
	return _travel_busy_query.call() if _travel_busy_query.is_valid() else null


func _travel_interlock_clear() -> bool:
	var busy: Variant = _travel_interlock_busy()
	return busy is bool and not busy


func request_travel_to_floor(floor_id: String) -> FlowCommandResultScript:
	var previous_phase: String = get_case_phase()
	var normalized_floor_id: String = floor_id.strip_edges()
	if normalized_floor_id.is_empty():
		return FlowCommandResultScript.failure(
			&"EMPTY_FLOOR_ID",
			"请输入目标楼层。",
			previous_phase,
			previous_phase
		)
	var definition := ContentRegistry.get_floor(normalized_floor_id)
	if definition == null:
		return FlowCommandResultScript.failure(
			&"UNKNOWN_FLOOR",
			"无法前往：楼层 %s 不在当前楼层数据库中。" % normalized_floor_id,
			previous_phase,
			previous_phase,
			normalized_floor_id
		)
	if is_cabin_door_open():
		return FlowCommandResultScript.failure(
			&"DOOR_OPEN",
			"请先关闭舱门，再确认前往楼层。",
			previous_phase,
			previous_phase,
			normalized_floor_id
		)
	if is_elevator_moving():
		return FlowCommandResultScript.failure(
			&"ELEVATOR_MOVING",
			"电梯正在运行中，请等待停靠。",
			previous_phase,
			previous_phase,
			normalized_floor_id
		)

	if not definition.elevator_accessible:
		var reason := definition.elevator_block_reason.strip_edges()
		return FlowCommandResultScript.failure(
			&"FLOOR_NOT_ACCESSIBLE",
			"该楼层不支持电梯停靠。" if reason.is_empty() else reason,
			previous_phase, previous_phase, normalized_floor_id
		)
	# 正式场景未接线或协调器已失效时，无法确认安全，拒绝启动。
	var busy: Variant = _travel_interlock_busy()
	if not busy is bool:
		return FlowCommandResultScript.failure(
			&"TRAVEL_INTERLOCK_UNAVAILABLE", "电梯安全联锁未就绪。",
			previous_phase, previous_phase, normalized_floor_id
		)
	if busy:
		return FlowCommandResultScript.failure(
			&"PRESENTATION_BUSY", "乘客或舱门动作尚未完成，暂时无法启动电梯。",
			previous_phase, previous_phase, normalized_floor_id
		)

	var passenger_is_onboard: bool = is_passenger_onboard()
	if previous_phase in [DispatchPhase.DROPOFF_FEEDBACK,
			DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE] or (passenger_is_onboard \
			and previous_phase not in [DispatchPhase.PASSENGER_ONBOARD, DispatchPhase.ARRIVED_AT_DESTINATION]):
		return FlowCommandResultScript.failure(
			&"TRAVEL_PHASE_BLOCKED", "当前乘客流程尚未允许发车。",
			previous_phase, previous_phase, normalized_floor_id
		)
	var departure_floor := get_current_floor()
	if passenger_is_onboard and previous_phase == DispatchPhase.ARRIVED_AT_DESTINATION \
			and normalized_floor_id == departure_floor:
		return FlowCommandResultScript.failure(
			&"ALREADY_AT_FLOOR", "电梯已停靠在该楼层。",
			previous_phase, previous_phase, normalized_floor_id
		)
	if not elevator_runtime_state.request_movement(normalized_floor_id):
		return FlowCommandResultScript.failure(
			&"MOVEMENT_REJECTED", "无法开始移动，请检查电梯状态。",
			previous_phase, previous_phase, normalized_floor_id
		)
	if passenger_is_onboard:
		# 发车成功后一次提交路线及阶段，更新通知不会看到上一站的到站状态。
		var active := dispatch_lifecycle.get_active_state()
		dispatch_lifecycle.set_selected_target_floor(normalized_floor_id)
		active.travel_legs.append({
			"from_floor_id": departure_floor, "target_floor_id": normalized_floor_id,
			"arrived_floor_id": "",
		})
		if previous_phase == DispatchPhase.ARRIVED_AT_DESTINATION:
			dispatch_lifecycle.try_set_phase(DispatchPhase.PASSENGER_ONBOARD)

	ui_history_state.set_building_status_hint(
		"电梯正在前往 %s 层。" % normalized_floor_id,
		true
	)
	left_terminal_section_updated.emit(LEFT_SECTION_SYSTEM_LOG)
	var result_effects: Array[StringName] = [
		FlowCommandResultScript.MOVEMENT_STARTED,
	]
	if passenger_is_onboard:
		result_effects.append(
			FlowCommandResultScript.DISPATCH_TARGET_SELECTED
		)
	case_updated.emit()
	return FlowCommandResultScript.success(
		&"MOVEMENT_STARTED",
		"目标楼层已确认：%s。电梯正在前往该楼层。" % normalized_floor_id,
		previous_phase,
		get_case_phase(),
		normalized_floor_id,
		result_effects
	)


func request_finish_dropoff_feedback() -> FlowCommandResultScript:
	var previous_phase := get_case_phase()
	if not is_cabin_door_open() or not dispatch_lifecycle.finish_dropoff_feedback():
		return FlowCommandResultScript.failure(
			&"DROPOFF_FEEDBACK_NOT_ACTIVE", "当前没有可结束的乘客反馈。",
			previous_phase, previous_phase
		)
	var active := dispatch_lifecycle.get_active_state()
	active.disembark_attempt += 1
	active.pending_disembark = {
		"session_id": get_document_session_id(),
		"attempt": active.disembark_attempt,
		"floor_id": get_current_floor(),
	}
	disembark_requested.emit(active.pending_disembark.duplicate())
	return FlowCommandResultScript.success(
		&"DROPOFF_FEEDBACK_FINISHED", "乘客准备离舱。",
		previous_phase, get_case_phase(), get_current_floor(),
		[FlowCommandResultScript.DROPOFF_FEEDBACK_FINISHED]
	)


func resolve_disembark(action: Dictionary, completed: bool) -> bool:
	var active := dispatch_lifecycle.get_active_state()
	if active == null or action.is_empty() or action != active.pending_disembark \
			or get_case_phase() != DispatchPhase.DROPOFF_FEEDBACK \
			or get_current_floor() != action.floor_id or is_elevator_moving() \
			or not is_cabin_door_open():
		return false
	# 先消费动作身份，再发通知。失败时保留在舱，等待安全恢复。
	active.pending_disembark.clear()
	if completed:
		dispatch_lifecycle.confirm_passenger_exited(action.floor_id)
		set_building_status_hint("乘客已离舱。请关闭舱门完成本次派单。", true)
	else:
		set_building_status_hint("离舱动作未完成，等待乘客恢复到舱内安全位置。", true)
	return true


func needs_disembark_recovery() -> bool:
	var active := dispatch_lifecycle.get_active_state()
	return active != null and get_case_phase() == DispatchPhase.DROPOFF_FEEDBACK \
			and active.dropoff_feedback_finished and active.pending_disembark.is_empty()


func confirm_disembark_recovery(session: int) -> void:
	if _current_document_state(session) == null or not needs_disembark_recovery() \
			or is_elevator_moving() or not is_cabin_door_open():
		return
	dispatch_lifecycle.restore_passenger_after_failed_exit()
	set_building_status_hint("乘客已恢复到舱内。请关门后重试离舱或改送。", true)


func get_current_floor() -> String:
	return elevator_runtime_state.current_floor


func get_target_floor() -> String:
	return elevator_runtime_state.target_floor


func get_movement_state_text() -> String:
	return elevator_runtime_state.get_movement_state_text()


func is_elevator_moving() -> bool:
	return elevator_runtime_state.is_moving()


func is_cabin_door_open() -> bool:
	return elevator_runtime_state.is_cabin_door_open()


func _on_elevator_movement_completed(arrived_floor: String) -> void:
	var session := get_document_session_id()
	# 到站后的派单含义仍由协调层判断，电梯模块只报告物理停靠结果。
	if is_passenger_onboard():
		if get_case_phase() != DispatchPhase.PASSENGER_ONBOARD or arrived_floor != get_selected_target_floor():
			return
		var active := dispatch_lifecycle.get_active_state()
		if active.travel_legs.is_empty() or not active.travel_legs.back().arrived_floor_id.is_empty():
			return
		active.travel_legs.back().arrived_floor_id = arrived_floor
		dispatch_lifecycle.try_set_phase(DispatchPhase.ARRIVED_AT_DESTINATION)
		set_building_status_hint("已抵达目标楼层。可开门送达或重新选择目的地。", true)
		_record_passenger_event(session, "arrived_at_destination", active.travel_legs.size())
	elif not is_passenger_onboard() and arrived_floor == get_pickup_floor():
		var pickup_phase: String = DispatchPhase.DOOR_GREETING_DONE \
				if is_door_greeting_done() else DispatchPhase.ARRIVED_AT_PICKUP
		if get_case_phase() != pickup_phase:
			_try_transition_case_phase(pickup_phase)
		set_building_status_hint(
			get_pickup_arrival_status_hint(),
			true,
			"已抵达接乘楼层。\n等待乘客确认。"
		)
	elif not is_passenger_onboard() and get_case_phase() in [
			DispatchPhase.ARRIVED_AT_PICKUP,
			DispatchPhase.DOOR_GREETING_DONE,
		]:
		_try_transition_case_phase(DispatchPhase.WAITING_FOR_PICKUP)
		set_building_status_hint("已停靠于 %s 层，舱门保持关闭。" % arrived_floor)
	else:
		set_building_status_hint("已停靠于 %s 层，舱门保持关闭。" % arrived_floor)
	if get_case_phase() == DispatchPhase.ARRIVED_AT_PICKUP:
		_record_passenger_event(session, "arrived_at_pickup")
	elevator_movement_completed.emit(arrived_floor)


func _try_transition_case_phase(next_phase: String) -> bool:
	# 物理停靠引发的阶段变化属于内部流程事件，不暴露低级状态 setter。
	var previous_phase: String = get_case_phase()
	var succeeded: bool = dispatch_lifecycle.try_set_phase(next_phase)
	if succeeded and previous_phase != next_phase:
		case_updated.emit()
	return succeeded


func get_case_phase() -> String:
	return dispatch_lifecycle.get_phase()


func is_passenger_onboard() -> bool:
	return dispatch_lifecycle.is_passenger_inside()


func is_door_greeting_done() -> bool:
	return dispatch_lifecycle.is_door_greeting_done()


func is_cabin_door_closed_after_boarding() -> bool:
	return dispatch_lifecycle.is_cabin_door_closed_after_boarding()


func get_validated_floor() -> String:
	return dispatch_lifecycle.get_validated_floor()


func get_selected_target_floor() -> String:
	return dispatch_lifecycle.get_selected_target_floor()


func get_current_recommended_destinations() -> Array[String]:
	var phase: String = get_case_phase()
	var pickup_phases: Array[String] = [
		DispatchPhase.WAITING_FOR_PICKUP,
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.DOOR_GREETING_DONE,
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE,
	]
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return []
	if not is_passenger_onboard() and phase in pickup_phases:
		var pickup_floor: String = String(dispatch.pickup_floor_id)
		return [pickup_floor] if not pickup_floor.is_empty() else []

	var candidates: Array[String] = []
	for destination: StringName in dispatch_lifecycle.get_recommended_floor_ids():
		var floor_number: String = String(destination)
		var relation: DispatchFloorRelation = get_dispatch_floor_relation(floor_number)
		if relation != null and relation.recommendation_eligible \
				and floor_number not in candidates:
			candidates.append(floor_number)
	return candidates


func add_recommended_destination(destination: String) -> void:
	if not has_active_dispatch():
		push_warning("DemoFlowManager: 当前无派单，无法解锁推荐楼层。")
		return
	var floor_number: String = destination.strip_edges()
	if floor_number.is_empty():
		return
	var relation: DispatchFloorRelation = get_dispatch_floor_relation(floor_number)
	if relation == null or not relation.recommendation_eligible:
		push_warning("DemoFlowManager: 楼层 %s 不具备当前派单的推荐资格。" % floor_number)
		return
	if dispatch_lifecycle.add_recommended_floor(StringName(floor_number)):
		case_updated.emit()


## W 只获得这些 Callable，不注入 Registry、完整 Manager 或左右台回写入口。
func get_document_workspace_port() -> Dictionary:
	return {"get_session_id": get_document_session_id,
		"get_received_materials": get_received_materials, "get_acquired_documents": get_acquired_documents,
		"get_acquired_document": get_acquired_document, "get_acquired_field": get_acquired_field,
		"get_document_events": get_document_events, "get_material_requests": get_material_requests,
		"get_contradiction_challenges": get_contradiction_challenges,
		"get_system_references": get_system_references, "open_system_reference": open_system_reference,
		"submit_material_request": submit_material_request, "submit_document_challenge": submit_document_challenge,
		"retry_review_delivery": retry_review_delivery, "get_review_deliveries": get_review_deliveries,
		"has_review_rules": has_review_rules}


func get_document_session_id() -> int:
	var state: DispatchDocumentState = _document_state()
	return state.session_id if state != null else 0


func _document_state() -> DispatchDocumentState:
	return dispatch_lifecycle.get_active_state().document_state if has_active_dispatch() else null


func _current_document_state(session: int) -> DispatchDocumentState:
	var state: DispatchDocumentState = _document_state()
	return state if state != null and state.matches_session(session) else null


## 只供主台接收当前 Dialogue 片段，W 的读取端口不暴露此命令。
func acquire_main_call_excerpt(session: int, event_id: String) -> FlowCommandResultScript:
	var state := _current_document_state(session)
	if state == null:
		return _document_command_result(DispatchDocumentState.outcome(false, "STALE_SESSION"))
	if _document_command_busy:
		return _document_command_result(DispatchDocumentState.outcome(false, "COMMAND_BUSY"))
	var excerpt := _find_passenger_event(state, event_id)
	if excerpt.is_empty():
		return _document_command_result(DispatchDocumentState.outcome(false, "NO_EXCERPT"))
	if not excerpt.has("presented_at"):
		return _document_command_result(DispatchDocumentState.outcome(false, "EXCERPT_NOT_PRESENTED"))
	var dispatch := get_active_dispatch()
	var builder := preload("res://scripts/dialogue/call_excerpt_builder.gd")
	var document := builder.build(excerpt, session, dispatch.passenger_id, get_dispatch_dialogue_path())
	if document == null or ContentRegistry.validate_document_definitions([document]).has_errors():
		return _document_command_result(DispatchDocumentState.outcome(false, "INVALID_EXCERPT"))
	_document_command_busy = true
	var result := state.receive(session, document.document_id, [document], "main")
	_document_command_busy = false
	if result.changed:
		documents_changed.emit(session)
	return _document_command_result(result)


func receive_passenger_batch(session: int, submission_id: StringName, refs: Array) -> FlowCommandResultScript:
	return _acquire_document_refs(session, submission_id, refs, "passenger")


func open_system_reference(session: int, ref: Dictionary) -> FlowCommandResultScript:
	return _acquire_document_refs(session, StringName("open:%s@%s" % [ref.get("document_id", ""), ref.get("version", 0)]), [ref], "system")


## 左台查询只返回定义快照；按键调阅之前，W 不会取得这些记录。
func query_current_passenger_archive(session: int) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if _current_document_state(session) == null:
		return records
	var dispatch := get_active_dispatch()
	var definitions := ContentRegistry.get_current_passenger_archive_documents(dispatch)
	if ContentRegistry.validate_document_definitions(definitions).has_errors():
		return records
	for document: DocumentDefinition in definitions:
		records.append(document.snapshot())
	return records


func retrieve_passenger_archive_document(session: int, query_id: StringName,
		displayed_document: Dictionary) -> FlowCommandResultScript:
	if _current_document_state(session) == null:
		return _document_command_result(DispatchDocumentState.outcome(false, "STALE_SESSION"))
	# 对照本单当前定义，避免把玩家尚未读过的新版本送到 W。
	for current: Dictionary in query_current_passenger_archive(session):
		if current == displayed_document:
			return accept_left_lookup_result(session, query_id, [{
				"document_id": current.document_id, "version": current.version}])
	return _document_command_result(DispatchDocumentState.outcome(false, "LEFT_RECORD_CHANGED"))


## 仅交给左台主动查询的完成回调；W 端口不包含此入口。
## query_id 是本次查询的唯一事件 ID，不是关键词；新查询/刷新分配新 ID，同一回调重试复用。
func accept_left_lookup_result(session: int, query_id: StringName, refs: Array) -> FlowCommandResultScript:
	return _acquire_document_refs(session, query_id, refs, "left")


## 右台遵守同一事件约定：相同关键词的新查询也使用新的 query_id。
func accept_right_lookup_result(session: int, query_id: StringName, refs: Array) -> FlowCommandResultScript:
	return _acquire_document_refs(session, query_id, refs, "right")


func _acquire_document_refs(session: int, event_id: StringName, refs: Array, route: String) -> FlowCommandResultScript:
	if _document_command_busy:
		return _document_command_result(DispatchDocumentState.outcome(false, "COMMAND_BUSY"))
	var state: DispatchDocumentState = _current_document_state(session)
	if state == null:
		return _document_command_result(DispatchDocumentState.outcome(false, "STALE_SESSION"))
	_document_command_busy = true
	var documents: Array[DocumentDefinition] = []
	for ref: Variant in refs:
		if not ref is Dictionary:
			_document_command_busy = false
			return _document_command_result(DispatchDocumentState.outcome(false, "INVALID_DOCUMENT_REF"))
		var document: DocumentDefinition = ContentRegistry.get_document_definition(String(dispatch_lifecycle.get_dispatch_id()), ref)
		if document == null:
			_document_command_busy = false
			return _document_command_result(DispatchDocumentState.outcome(false, "INVALID_DOCUMENT_REF"))
		documents.append(document)
	var report: ContentValidationReport = ContentRegistry.validate_document_definitions(documents)
	var result: Dictionary = DispatchDocumentState.outcome(false, "INVALID_DOCUMENT")
	if not report.has_errors():
		result = state.receive(session, event_id, documents, route)
	_document_command_busy = false
	if result.changed:
		documents_changed.emit(session)
	return _document_command_result(result)


func get_received_materials(session: int) -> Array[Dictionary]:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_documents(session, true) if state != null else []


func get_acquired_documents(session: int) -> Array[Dictionary]:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_documents(session) if state != null else []


func get_acquired_document(session: int, ref: Dictionary) -> Dictionary:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_document(session, ref) if state != null else {}


func get_acquired_field(session: int, ref: Dictionary) -> Dictionary:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_field(session, ref) if state != null else {}


func get_system_references(session: int) -> Array[Dictionary]:
	return ContentRegistry.get_system_reference_documents(String(dispatch_lifecycle.get_dispatch_id())) if _current_document_state(session) != null else []


func get_document_events(session: int) -> Array[Dictionary]:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_events(session) if state != null else []


func get_material_requests(session: int) -> Array[Dictionary]:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_requests(session) if state != null else []


func get_contradiction_challenges(session: int) -> Array[Dictionary]:
	var state: DispatchDocumentState = _current_document_state(session)
	return state.get_challenges(session) if state != null else []


## 应用层配置接入口；不向 W 暴露，也不提供默认正式判断器。
func set_document_applicability_resolver(resolver: Callable) -> void:
	if not _document_command_busy:
		_document_applicability_resolver = resolver


func request_material(session: int, request_id: StringName, clause_ref: Dictionary) -> FlowCommandResultScript:
	if _document_command_busy:
		return _document_command_result(DispatchDocumentState.outcome(false, "COMMAND_BUSY"))
	var state: DispatchDocumentState = _current_document_state(session)
	if state == null:
		return _document_command_result(DispatchDocumentState.outcome(false, "STALE_SESSION"))
	# 尚未上传不能等同于已上传但缺件；先过提交门，再调用适用性依赖。
	if not state.has_initial_submission(session):
		return _document_command_result(DispatchDocumentState.outcome(false, "INITIAL_SUBMISSION_REQUIRED"))
	var clause: Dictionary = state.get_clause(session, clause_ref)
	if clause.is_empty():
		return _document_command_result(DispatchDocumentState.outcome(false, "INVALID_CLAUSE"))
	if not _document_applicability_resolver.is_valid():
		return _document_command_result(DispatchDocumentState.outcome(false, "RULE_UNRESOLVED"))
	# 通用条款的陈述对象可为 system；索取对象绑定当前乘客，不写死在共享规程里。
	var target: Dictionary = {"type": "passenger", "id": String(get_active_dispatch().passenger_id)}
	var context: Dictionary = {"session_id": session, "dispatch_id": String(dispatch_lifecycle.get_dispatch_id()),
		"passenger_id": target.id, "floor_id": get_current_floor()}
	_document_command_busy = true
	var raw_decision: Variant = _document_applicability_resolver.call(clause.duplicate(true), context)
	var applicability: StringName = StringName(raw_decision) if raw_decision is String or raw_decision is StringName else &"UNRESOLVED"
	var result: Dictionary = DispatchDocumentState.outcome(false, "RULE_UNRESOLVED")
	if _current_document_state(session) != state:
		result = DispatchDocumentState.outcome(false, "STALE_SESSION")
	elif applicability == &"APPLICABLE":
		result = state.record_material_request(session, request_id, clause_ref, target)
	elif applicability == &"NOT_APPLICABLE":
		result = DispatchDocumentState.outcome(false, "RULE_NOT_APPLICABLE")
	_document_command_busy = false
	if result.changed:
		material_requested.emit(session)
	return _document_command_result(result)


func record_contradiction_challenge(session: int, challenge_id: StringName,
		a_ref: Dictionary, b_ref: Dictionary) -> FlowCommandResultScript:
	if _document_command_busy:
		return _document_command_result(DispatchDocumentState.outcome(false, "COMMAND_BUSY"))
	var state: DispatchDocumentState = _current_document_state(session)
	if state == null:
		return _document_command_result(DispatchDocumentState.outcome(false, "STALE_SESSION"))
	var result: Dictionary = state.record_challenge(session, challenge_id, a_ref, b_ref)
	if result.changed:
		contradiction_challenge_recorded.emit(session)
	return _document_command_result(result)


func _document_command_result(result: Dictionary) -> FlowCommandResultScript:
	var code: StringName = StringName(result.code)
	if result.succeeded:
		return FlowCommandResultScript.success(code, "相关材料已提供。" if code == &"ALREADY_PROVIDED" else "")
	return FlowCommandResultScript.failure(code, "该条款当前不适用。" if code == &"RULE_NOT_APPLICABLE" else "当前无法执行资料请求。")


func _record_passenger_event(session: int, key: String, leg: int = 0) -> void:
	var event_key := "%s:%d" % [key, leg] if leg > 0 else key
	var state := _current_document_state(session)
	if state == null or state.passenger_events.has(event_key):
		return
	var dispatch := get_active_dispatch()
	var title: String = dispatch.dialogue_events.get(key, "")
	if title.is_empty():
		return
	state.passenger_events[event_key] = {
		"source_event_id": "%d:%s" % [session, event_key], "session": session,
		"key": key, "title": title, "resource_path": dispatch.dialogue_path,
		"passenger_id": dispatch.passenger_id, "floor_id": get_current_floor(),
		"occurred_at": Time.get_unix_time_from_system(), "status": "pending",
	}
	passenger_event_changed.emit()
	passenger_event_pending.emit()


func take_pending_passenger_event() -> Dictionary:
	var state := _document_state()
	if state != null:
		var occupied := 0
		for event: Dictionary in state.passenger_events.values():
			if event.status in ["resolved", "running"]:
				occupied += 1
		if occupied >= REVIEW_QUEUE_LIMIT:
			return {}
		for event: Dictionary in state.passenger_events.values():
			if event.status == "pending":
				event.status = "running"
				return event.duplicate(true)
	return {}


func finish_passenger_event(snapshot: Dictionary, source_version: String, rows: Array[Dictionary]) -> void:
	var state := _current_document_state(snapshot.session)
	if state == null:
		return
	var event: Dictionary = state.passenger_events.get(snapshot.key, {})
	if event.get("source_event_id") != snapshot.source_event_id or event.get("status") != "running":
		return
	if event.get("attempt", 0) != snapshot.get("attempt", 0):
		return
	if not event.get("supplement_action", "").is_empty() and not event.get("supplement_done", false):
		rows = []
	event.status = "failed" if rows.is_empty() else "resolved"
	event.source_version = source_version
	event.rows = rows.duplicate(true)
	for row: Dictionary in rows:
		add_front_transcript_passenger(String(row.text))
	passenger_event_changed.emit()


func _find_passenger_event(state: DispatchDocumentState, event_id: String) -> Dictionary:
	if state != null and not event_id.is_empty():
		for event: Dictionary in state.passenger_events.values():
			if event.source_event_id == event_id:
				return event
	return {}


## 仅由主屏的末页绘制回执调用。原时间保留，重复回执不改摘录快照。
func note_passenger_event_drawn(session: int, event_id: String) -> void:
	var event := _find_passenger_event(_current_document_state(session), event_id)
	if event.get("status") == "resolved" and not event.has("presented_at"):
		event.presented_at = Time.get_unix_time_from_system()


## 末页停留结束后释放槽位，已完整呈现的原文保留在本次派单。
func mark_passenger_event_presented(session: int, event_id: String) -> void:
	var event := _find_passenger_event(_current_document_state(session), event_id)
	if event.get("status") == "resolved" and event.has("presented_at"):
		event.status = "presented"
		passenger_event_changed.emit()
		passenger_event_pending.emit()


func get_passenger_events() -> Array:
	var state := _document_state()
	return state.passenger_events.values().duplicate(true) if state != null else []


## 正式 W 审查。兼容记录接口不暴露给 W，也不发起回应。
func set_review_delivery_ready(check: Callable) -> void:
	_review_delivery_ready = check


func submit_material_request(session: int, operation_id: StringName, clause: Dictionary) -> FlowCommandResultScript:
	return _submit_review(session, operation_id, [clause], true)


func submit_document_challenge(session: int, operation_id: StringName,
		a: Dictionary, b: Dictionary) -> FlowCommandResultScript:
	var refs := [a, b]
	if var_to_str(_review_ref(a)) > var_to_str(_review_ref(b)):
		refs = [b, a]
	return _submit_review(session, operation_id, refs, false)


func _review_ref(ref: Dictionary) -> Dictionary:
	return {"document_id": String(ref.get("document_id", "")), "version": ref.get("version"),
		"field_id": String(ref.get("field_id", ""))}


func _submit_review(session: int, operation_id: StringName, refs: Array,
		material: bool) -> FlowCommandResultScript:
	var state := _current_document_state(session)
	if state == null:
		return _review_result(false, &"STALE_SESSION", "当前派单已变更。")
	if _document_command_busy or operation_id == &"":
		return _review_result(false, &"COMMAND_BUSY", "暂时无法提交审查。")
	if not state.has_initial_submission(session):
		return _review_result(false, &"INITIAL_SUBMISSION_REQUIRED", "请等待乘客提交本批材料。")
	for ref: Dictionary in refs:
		if not DispatchDocumentState.valid_ref(ref, true):
			return _review_result(false, &"INVALID_FIELD_REF", "请重新选择资料。")
	var normalized: Array[Dictionary] = []
	for ref: Dictionary in refs:
		normalized.append(_review_ref(ref))
	var prior: Dictionary = state.review_operations.get(operation_id, {})
	if not prior.is_empty():
		if prior.get("refs") != normalized:
			return _review_result(false, &"EVENT_CONFLICT", "这次操作的资料已变更。")
		return _review_already(state.passenger_events[prior.key])
	var a := state.get_current_field(session, normalized[0])
	var b := {} if material else state.get_current_field(session, normalized[1])
	if a.is_empty() or (not material and (b.is_empty() or a.ref.document_id == b.ref.document_id)):
		return _review_result(false, &"INVALID_FIELD_REF", "请选择当前已取得的资料。")
	if material and state.get_clause(session, a.ref).is_empty():
		return _review_result(false, &"INVALID_CLAUSE", "这条资料不是可索证的规程。")

	var dispatch := get_active_dispatch()
	var rules: Array[DocumentReviewRule] = []
	for rule: DocumentReviewRule in dispatch.review_rules:
		if not DocumentReviewMatcher.valid(rule):
			continue
		if material:
			if a.requirement_key == String(rule.requirement_key) and a.applicability_key == String(rule.applicability_key) \
					and DocumentReviewMatcher.context_matches(state, rule.context):
				rules.append(rule)
		elif DocumentReviewMatcher.challenge_matches(rule, state, a, b):
			rules.append(rule)
	if rules.size() != 1:
		return _review_result(false, &"REVIEW_NO_MATCH", "暂未找到需要进一步说明的依据。")
	var rule := rules[0]
	var key := "review/" + String(rule.question_id)
	if state.passenger_events.has(key):
		state.review_operations[operation_id] = {"refs": normalized, "key": key}
		var existing: Dictionary = state.passenger_events[key]
		if material and existing.supplement_done and existing.status != "failed":
			return _review_result(true, &"ALREADY_PROVIDED", "相关材料已提供。")
		return _review_already(existing)
	var target := {"type": "passenger", "id": String(dispatch.passenger_id)}
	if material:
		for receipt: Dictionary in state.get_documents(session, true):
			var doc: Dictionary = receipt.document
			if doc.owner_type == target.type and doc.owner_id == target.id and doc.material_type == a.required_material_type:
				return _review_result(true, &"ALREADY_PROVIDED", "相关材料已提供。")
	var supplements: Array[DocumentDefinition] = []
	for ref: Dictionary in rule.supplement_refs:
		var doc := ContentRegistry.get_document_definition(String(dispatch.dispatch_id), ref) as DocumentDefinition
		if doc == null or doc.owner_id != dispatch.passenger_id or doc.owner_type != &"passenger" \
				or doc.source == null or doc.source.kind != &"passenger_upload" or String(doc.material_type) != a.required_material_type:
			return _review_result(false, &"REVIEW_UNAVAILABLE", "该回应暂不可用。")
		supplements.append(doc.duplicate(true) as DocumentDefinition)
	if not supplements.is_empty() and ContentRegistry.validate_document_definitions(supplements).has_errors():
		return _review_result(false, &"REVIEW_UNAVAILABLE", "该回应暂不可用。")
	var gate := _review_preflight(state, dispatch.dialogue_path, rule.response_title, rule.supplement_action)
	if gate != null:
		return gate

	# 从校验到写入没有 await；通知只在问题与交付同时落地后发送。
	var delivery_id := "%d:review:%d" % [session, state.passenger_events.size()]
	var record := state.record_material_request(session, StringName(delivery_id), a.ref, target) if material \
		else state.record_challenge(session, StringName(delivery_id), a.ref, b.ref)
	if not record.changed:
		return _document_command_result(record)
	state.review_operations[operation_id] = {"refs": normalized, "key": key}
	state.passenger_events[key] = {
		"key": key, "source_event_id": delivery_id, "question_id": rule.question_id,
		"review_refs": normalized, "session": session, "title": rule.response_title,
		"resource_path": dispatch.dialogue_path, "passenger_id": dispatch.passenger_id,
		"floor_id": get_current_floor(), "occurred_at": Time.get_unix_time_from_system(),
		"status": "pending", "attempt": 1, "supplement_action": rule.supplement_action,
		"supplements": supplements, "supplement_done": false,
	}
	_notify_review_pending()
	return _review_result(true, &"REVIEW_SUBMITTED", "已提交，回应将显示在主台监视器。")


func _review_preflight(state: DispatchDocumentState, path: String,
		title: String, action: String) -> FlowCommandResultScript:
	if not _review_delivery_ready.is_valid():
		return _review_result(false, &"REVIEW_UNAVAILABLE", "主台回应通道暂不可用。")
	var occupied := 0
	for event: Dictionary in state.passenger_events.values():
		if event.status in ["pending", "running"]:
			return _review_result(false, &"REVIEW_BUSY", "回应处理中，请稍后再试。")
		if event.status == "resolved":
			occupied += 1
	if occupied >= REVIEW_QUEUE_LIMIT:
		return _review_result(false, &"REVIEW_QUEUE_FULL", "请先在主台查看待呈现的回应。")
	var resource := load(path) as DialogueResource if ResourceLoader.exists(path) else null
	if not DialogueManagerAdapter.is_event_title(resource, title, true, action):
		return _review_result(false, &"REVIEW_UNAVAILABLE", "该回应暂不可用。")
	var session := state.session_id
	_document_command_busy = true
	var ready: bool = _review_delivery_ready.call()
	_document_command_busy = false
	if _current_document_state(session) != state:
		return _review_result(false, &"STALE_SESSION", "当前派单已变更。")
	if not ready:
		return _review_result(false, &"REVIEW_BUSY", "回应通道暂不可用，请稍后再试。")
	return null


func retry_review_delivery(session: int, operation_id: StringName, delivery_id: String) -> FlowCommandResultScript:
	var state := _current_document_state(session)
	var event := _find_passenger_event(state, delivery_id)
	if event.is_empty() or not event.has("question_id"):
		return _review_result(false, &"STALE_DELIVERY", "没有可重试的回应。")
	if _document_command_busy or operation_id == &"":
		return _review_result(false, &"COMMAND_BUSY", "暂时无法重试。")
	var prior: Dictionary = state.review_operations.get(operation_id, {})
	if not prior.is_empty():
		if prior.get("retry") != delivery_id:
			return _review_result(false, &"EVENT_CONFLICT", "这次操作的回应已变更。")
		return _review_already(event)
	if event.status != "failed":
		return _review_already(event)
	var gate := _review_preflight(state, event.resource_path, event.title, event.supplement_action)
	if gate != null:
		return gate
	state.review_operations[operation_id] = {"retry": delivery_id}
	event.attempt += 1
	event.status = "pending"
	_notify_review_pending()
	return _review_result(true, &"REVIEW_RETRIED", "已重试同一回应。")


## 受控对白动作只允许提交该交付预先固定的资料。先写动作完成标记，再通知 UI。
func apply_review_supplement(session: int, snapshot: Dictionary, action: String) -> bool:
	var state := _current_document_state(session)
	var event := _find_passenger_event(state, snapshot.source_event_id)
	if event.is_empty() or not event.has("question_id") or event.status != "running" \
			or event.attempt != snapshot.get("attempt") or event.supplement_action != action or action.is_empty():
		return false
	if event.supplement_done:
		return true
	if _document_command_busy:
		return false
	_document_command_busy = true
	var event_id := StringName("%d:review:%s:%s" % [session, event.question_id, action])
	var result := state.receive(session, event_id, event.supplements, "passenger")
	if result.succeeded:
		event.supplement_done = true
	_document_command_busy = false
	if result.changed:
		documents_changed.emit(session)
	return result.succeeded


func get_review_deliveries(session: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var state := _current_document_state(session)
	if state != null:
		for event: Dictionary in state.passenger_events.values():
			if event.has("question_id"):
				result.append({"delivery_id": event.source_event_id, "status": event.status})
	return result


func _notify_review_pending() -> void:
	passenger_event_changed.emit()
	passenger_event_pending.emit()


func _review_already(event: Dictionary) -> FlowCommandResultScript:
	return _review_result(true, &"REVIEW_ALREADY_SUBMITTED",
		"回应未送达，可重试。" if event.status == "failed" else "该问题已提交。")


func _review_result(ok: bool, code: StringName, message: String) -> FlowCommandResultScript:
	return FlowCommandResultScript.success(code, message) if ok else FlowCommandResultScript.failure(code, message)


func has_review_rules(session: int) -> bool:
	return _current_document_state(session) != null and not get_active_dispatch().review_rules.is_empty()

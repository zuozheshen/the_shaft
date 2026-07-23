extends Node
class_name DemoFlowManager


# 协调层继续发送原有信号，三个 UI 不需要知道内部模块已经拆分。
signal case_updated
signal elevator_movement_completed(arrived_floor: String)
signal dispatch_started(dispatch_id: StringName)
signal dispatch_completed(result: DispatchResult)
signal shift_completed


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

@export var initial_floor: String = "900"
@export_range(0.1, 5.0, 0.1, "suffix:s") var movement_duration_seconds: float = 0.6
@export var initial_shift: ShiftDefinition

var elevator_runtime_state: ElevatorRuntimeStateScript
var dispatch_lifecycle: DispatchLifecycleScript
var shift_runner: ShiftRunnerScript
var ui_history_state: UIHistoryStateScript


func _ready() -> void:
	_initialize_runtime_components()
	elevator_runtime_state.initialize(initial_floor, movement_duration_seconds)
	case_updated.emit()
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
	if get_case_phase() != DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE \
			or is_cabin_door_open():
		push_warning("DemoFlowManager: 当前阶段不允许完成派单。")
		return completion

	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return completion
	var result := DispatchResult.create(
		dispatch_lifecycle.get_dispatch_id(),
		dispatch.passenger_id,
		StringName(get_selected_target_floor()),
		shift_runner.get_completed_count() + 1
	)
	shift_runner.record_completed_result(result)
	dispatch_lifecycle.clear()
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
	elevator_runtime_state.clear_target_floor()
	ui_history_state.finish_shift()
	shift_completed.emit()
	if should_emit_case_updated:
		case_updated.emit()
	return true


func clear_active_dispatch() -> void:
	dispatch_lifecycle.clear()
	ui_history_state.clear_active_dispatch()
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
		case_updated.emit()


func add_system_log_message(message_text: String) -> void:
	if ui_history_state.add_system_log_message(message_text):
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


func get_camera_feed_for_phase(phase: String, camera_index: int) -> String:
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return ""
	var camera_feeds: Dictionary = dispatch.camera_feeds
	var phase_feeds: Array = camera_feeds.get(
		phase,
		camera_feeds.get(DispatchPhase.WAITING_FOR_PICKUP, [])
	)
	if camera_index < 0 or camera_index >= phase_feeds.size():
		return ""
	return str(phase_feeds[camera_index])


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
		if not dispatch_lifecycle.begin_dropoff_feedback():
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
	return FlowCommandResultScript.success(
		&"DOOR_OPENED",
		message,
		previous_phase,
		get_case_phase(),
		get_current_floor(),
		result_effects
	)


func request_close_cabin_door() -> FlowCommandResultScript:
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
			"请等待乘客反馈结束后再关闭舱门。",
			previous_phase,
			previous_phase
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
	if not ContentRegistry.has_floor(normalized_floor_id):
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

	var passenger_is_onboard: bool = is_passenger_onboard()
	if passenger_is_onboard:
		if not has_active_dispatch():
			return FlowCommandResultScript.failure(
				&"NO_ACTIVE_DISPATCH",
				"当前没有可执行送达的派单。",
				previous_phase,
				previous_phase,
				normalized_floor_id
			)
		if normalized_floor_id != get_validated_floor():
			return FlowCommandResultScript.failure(
				&"DESTINATION_NOT_VALIDATED",
				"乘客在舱内时，请先验证目标楼层。",
				previous_phase,
				previous_phase,
				normalized_floor_id
			)

	var previous_selected_floor: String = get_selected_target_floor()
	if passenger_is_onboard:
		dispatch_lifecycle.set_selected_target_floor(normalized_floor_id)
	if not elevator_runtime_state.request_movement(normalized_floor_id):
		if passenger_is_onboard:
			dispatch_lifecycle.set_selected_target_floor(previous_selected_floor)
		return FlowCommandResultScript.failure(
			&"MOVEMENT_REJECTED",
			"无法开始移动，请检查电梯状态。",
			previous_phase,
			get_case_phase(),
			normalized_floor_id
		)

	ui_history_state.set_building_status_hint(
		"电梯正在前往 %s 层。" % normalized_floor_id,
		true
	)
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
	var previous_phase: String = get_case_phase()
	if not dispatch_lifecycle.finish_dropoff_feedback():
		return FlowCommandResultScript.failure(
			&"DROPOFF_FEEDBACK_NOT_ACTIVE",
			"当前没有可结束的乘客反馈。",
			previous_phase,
			get_case_phase()
		)
	ui_history_state.set_building_status_hint(
		"乘客已离舱。请关闭舱门完成本次派单。",
		true,
		"乘客已离舱，等待关门结算。"
	)
	var result_effects: Array[StringName] = [
		FlowCommandResultScript.DROPOFF_FEEDBACK_FINISHED,
	]
	case_updated.emit()
	return FlowCommandResultScript.success(
		&"DROPOFF_FEEDBACK_FINISHED",
		"乘客已离舱。请关闭舱门完成本次派单。",
		previous_phase,
		get_case_phase(),
		get_current_floor(),
		result_effects
	)


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


func set_cabin_door_open(is_open: bool) -> void:
	# 兼容旧测试与外部脚本；正式 UI 应调用结构化开关门命令。
	if elevator_runtime_state.set_cabin_door_open(is_open):
		case_updated.emit()


func request_elevator_movement(destination: String) -> bool:
	# 兼容入口只执行基础移动；正式右台应调用 request_travel_to_floor。
	var requested_floor: String = destination.strip_edges()
	if requested_floor.is_empty() or not ContentRegistry.has_floor(requested_floor):
		return false
	if not elevator_runtime_state.request_movement(requested_floor):
		return false
	set_building_status_hint("电梯正在前往 %s 层。" % requested_floor)
	return true


func _on_elevator_movement_completed(arrived_floor: String) -> void:
	# 到站后的派单含义仍由协调层判断，电梯模块只报告物理停靠结果。
	if is_passenger_onboard() \
			and not get_selected_target_floor().is_empty() \
			and arrived_floor == get_selected_target_floor():
		set_case_phase(DispatchPhase.ARRIVED_AT_DESTINATION)
		set_building_status_hint(
			"已抵达目标楼层。请开启舱门完成送达。",
			true,
			"已抵达目标楼层，等待开门送达。"
		)
	elif not is_passenger_onboard() and arrived_floor == get_pickup_floor():
		var pickup_phase: String = DispatchPhase.DOOR_GREETING_DONE \
				if is_door_greeting_done() else DispatchPhase.ARRIVED_AT_PICKUP
		if get_case_phase() != pickup_phase:
			set_case_phase(pickup_phase)
		set_building_status_hint(
			get_pickup_arrival_status_hint(),
			true,
			"已抵达接乘楼层。\n等待乘客确认。"
		)
	elif not is_passenger_onboard() and get_case_phase() in [
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.DOOR_GREETING_DONE,
	]:
		set_case_phase(DispatchPhase.WAITING_FOR_PICKUP)
		set_building_status_hint("已停靠于 %s 层，舱门保持关闭。" % arrived_floor)
	else:
		set_building_status_hint("已停靠于 %s 层，舱门保持关闭。" % arrived_floor)
	elevator_movement_completed.emit(arrived_floor)


func get_case_phase() -> String:
	return dispatch_lifecycle.get_phase()


func set_case_phase(phase: String) -> void:
	# 兼容入口；玩家操作不得再由 UI 连续拼装阶段和其他字段。
	try_set_case_phase(phase)


func try_set_case_phase(next_phase: String) -> bool:
	var previous_phase: String = get_case_phase()
	var succeeded: bool = dispatch_lifecycle.try_set_phase(next_phase)
	if succeeded and previous_phase != next_phase:
		case_updated.emit()
	return succeeded


func is_passenger_onboard() -> bool:
	return dispatch_lifecycle.is_passenger_inside()


func set_passenger_onboard(value: bool) -> void:
	# 兼容入口；正式接乘使用 request_open_cabin_door。
	if dispatch_lifecycle.set_passenger_inside(value):
		case_updated.emit()


func is_door_greeting_done() -> bool:
	return dispatch_lifecycle.is_door_greeting_done()


func set_door_greeting_done(value: bool) -> void:
	# 兼容入口；正式门外确认使用 request_complete_door_greeting。
	if dispatch_lifecycle.set_door_greeting_done(value):
		case_updated.emit()


func is_cabin_door_closed_after_boarding() -> bool:
	return dispatch_lifecycle.is_cabin_door_closed_after_boarding()


func set_cabin_door_closed_after_boarding(value: bool) -> void:
	# 兼容入口；正式关门使用 request_close_cabin_door。
	if dispatch_lifecycle.set_cabin_door_closed_after_boarding(value):
		case_updated.emit()


func set_validated_floor(floor_id: String) -> bool:
	# 兼容入口；正式右台验证使用 request_validate_destination。
	if not has_active_dispatch():
		return dispatch_lifecycle.set_validated_floor(floor_id)
	var normalized_id: String = floor_id.strip_edges()
	if not normalized_id.is_empty() and not ContentRegistry.has_floor(normalized_id):
		push_warning("DemoFlowManager: 无法记录不存在的验证楼层：%s" % normalized_id)
		return false
	if not dispatch_lifecycle.set_validated_floor(normalized_id):
		return false
	case_updated.emit()
	return true


func get_validated_floor() -> String:
	return dispatch_lifecycle.get_validated_floor()


func select_target_floor(floor_id: String) -> bool:
	# 兼容入口；正式目标提交使用 request_travel_to_floor。
	if not has_active_dispatch():
		return dispatch_lifecycle.set_selected_target_floor(floor_id)
	var normalized_id: String = floor_id.strip_edges()
	if normalized_id.is_empty() or not ContentRegistry.has_floor(normalized_id):
		push_warning("DemoFlowManager: 无法提交不存在的楼层：%s" % normalized_id)
		return false
	if not dispatch_lifecycle.set_selected_target_floor(normalized_id):
		return false
	case_updated.emit()
	return true


func get_selected_target_floor() -> String:
	return dispatch_lifecycle.get_selected_target_floor()


func try_mark_arrival_triggered() -> bool:
	if not dispatch_lifecycle.try_mark_arrival_triggered():
		return false
	case_updated.emit()
	return true


func mark_dropoff_feedback_finished() -> bool:
	# 兼容入口保留 bool 返回；正式 UI 使用结构化命令结果。
	return request_finish_dropoff_feedback().succeeded


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

class_name DispatchLifecycle
extends RefCounted


var _active_dispatch: ActiveDispatchState


func start_dispatch(
		dispatch: DispatchDefinition,
		initial_phase: String = DispatchPhase.WAITING_FOR_PICKUP
) -> bool:
	if dispatch == null:
		return false

	# 每条派单都创建新状态，上一轮的验证、目标和反馈标记不会被复用。
	_active_dispatch = ActiveDispatchState.create_from_definition(dispatch)
	_active_dispatch.current_phase = initial_phase \
			if DispatchPhase.is_valid(initial_phase) \
			else DispatchPhase.WAITING_FOR_PICKUP
	return true


func clear() -> void:
	_active_dispatch = null


func has_active_dispatch() -> bool:
	return _active_dispatch != null


func get_active_state() -> ActiveDispatchState:
	return _active_dispatch


func get_dispatch_id() -> StringName:
	return _active_dispatch.dispatch_id if _active_dispatch != null else &""


func get_phase() -> String:
	return _active_dispatch.current_phase \
			if _active_dispatch != null else DispatchPhase.SHIFT_IDLE


func try_set_phase(next_phase: String) -> bool:
	var previous_phase: String = get_phase()
	if _active_dispatch == null:
		push_warning(
			"DemoFlowManager: 当前无派单，无法修改派单阶段：%s -> %s"
			% [previous_phase, next_phase]
		)
		return false
	if not DispatchPhase.is_valid(next_phase):
		push_warning(
			"DemoFlowManager: 目标派单阶段无效：%s -> %s"
			% [previous_phase, next_phase]
		)
		return false
	if previous_phase == next_phase:
		return true
	if not DispatchPhase.can_transition(previous_phase, next_phase):
		push_warning(
			"DemoFlowManager: 不允许派单阶段转换：%s -> %s"
			% [previous_phase, next_phase]
		)
		return false
	_active_dispatch.current_phase = next_phase
	return true


func complete_door_greeting() -> bool:
	# 先完成所有前置检查，再一次写入阶段与标记，避免留下半完成状态。
	if _active_dispatch == null \
			or _active_dispatch.current_phase != DispatchPhase.ARRIVED_AT_PICKUP:
		return false
	_active_dispatch.current_phase = DispatchPhase.DOOR_GREETING_DONE
	_active_dispatch.door_greeting_done = true
	return true


func board_passenger() -> bool:
	if _active_dispatch == null or _active_dispatch.current_phase not in [
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.DOOR_GREETING_DONE,
	]:
		return false
	_active_dispatch.current_phase = DispatchPhase.BOARDING_WAIT_DOOR_CLOSE
	_active_dispatch.passenger_inside = true
	_active_dispatch.cabin_door_closed_after_boarding = false
	return true


func secure_passenger_after_door_close() -> bool:
	if _active_dispatch == null \
			or _active_dispatch.current_phase != DispatchPhase.BOARDING_WAIT_DOOR_CLOSE \
			or not _active_dispatch.passenger_inside:
		return false
	_active_dispatch.current_phase = DispatchPhase.PASSENGER_ONBOARD
	_active_dispatch.cabin_door_closed_after_boarding = true
	return true


func begin_dropoff_feedback() -> bool:
	if _active_dispatch == null \
			or _active_dispatch.current_phase != DispatchPhase.ARRIVED_AT_DESTINATION \
			or not _active_dispatch.passenger_inside \
			or not _active_dispatch.cabin_door_closed_after_boarding \
			or _active_dispatch.arrival_triggered:
		return false
	_active_dispatch.current_phase = DispatchPhase.DROPOFF_FEEDBACK
	_active_dispatch.arrival_triggered = true
	return true


func is_passenger_inside() -> bool:
	return _active_dispatch != null and _active_dispatch.passenger_inside


func set_passenger_inside(value: bool) -> bool:
	if _active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改乘客进舱状态。")
		return false
	_active_dispatch.passenger_inside = value
	return true


func is_door_greeting_done() -> bool:
	return _active_dispatch != null and _active_dispatch.door_greeting_done


func set_door_greeting_done(value: bool) -> bool:
	if _active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改门外问候状态。")
		return false
	_active_dispatch.door_greeting_done = value
	return true


func is_cabin_door_closed_after_boarding() -> bool:
	return _active_dispatch != null \
			and _active_dispatch.cabin_door_closed_after_boarding


func set_cabin_door_closed_after_boarding(value: bool) -> bool:
	if _active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改登舱后的门控状态。")
		return false
	_active_dispatch.cabin_door_closed_after_boarding = value
	return true


func set_validated_floor(floor_id: String) -> bool:
	if _active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法记录楼层验证。")
		return false
	_active_dispatch.validated_floor_id = StringName(floor_id.strip_edges())
	return true


func get_validated_floor() -> String:
	return String(_active_dispatch.validated_floor_id) \
			if _active_dispatch != null else ""


func set_selected_target_floor(floor_id: String) -> bool:
	if _active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法记录目标楼层。")
		return false
	_active_dispatch.selected_target_floor_id = StringName(floor_id.strip_edges())
	return true


func get_selected_target_floor() -> String:
	return String(_active_dispatch.selected_target_floor_id) \
			if _active_dispatch != null else ""


func try_mark_arrival_triggered() -> bool:
	if _active_dispatch == null or _active_dispatch.arrival_triggered:
		return false
	_active_dispatch.arrival_triggered = true
	return true


func is_arrival_triggered() -> bool:
	return _active_dispatch != null and _active_dispatch.arrival_triggered


func finish_dropoff_feedback() -> bool:
	if _active_dispatch == null \
			or get_phase() != DispatchPhase.DROPOFF_FEEDBACK \
			or _active_dispatch.dropoff_feedback_finished:
		return false
	_active_dispatch.dropoff_feedback_finished = true
	_active_dispatch.passenger_inside = false
	return try_set_phase(DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE)


func is_dropoff_feedback_finished() -> bool:
	return _active_dispatch != null \
			and _active_dispatch.dropoff_feedback_finished


func add_recommended_floor(floor_id: StringName) -> bool:
	if _active_dispatch == null:
		return false
	return _active_dispatch.add_recommended_floor(floor_id)


func get_recommended_floor_ids() -> Array[StringName]:
	if _active_dispatch == null:
		var empty_floor_ids: Array[StringName] = []
		return empty_floor_ids
	return _active_dispatch.get_recommended_floor_ids()

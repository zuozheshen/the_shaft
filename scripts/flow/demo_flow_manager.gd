extends Node
class_name DemoFlowManager


# 状态变化后通知界面等监听者，避免其他节点反复查询流程状态。
signal case_updated
signal elevator_movement_completed(arrived_floor: String)


const MAX_FRONT_HISTORY_LINES: int = 20
const INITIAL_DISPATCH_ID: StringName = &"CASE_001"

# 电梯位置独立于案例阶段：派单只提供建议，不能限制实际可前往的楼层。
enum MovementState {
	IDLE,
	MOVING,
	ARRIVED,
}

# 可在 Main 场景的 DemoFlowManager Inspector 中调整，避免起始楼层散落在多个脚本里。
@export var initial_floor: String = "900"
@export_range(0.1, 5.0, 0.1, "suffix:s") var movement_duration_seconds: float = 0.6

var current_floor: String = ""
var target_floor: String = ""
var movement_state: MovementState = MovementState.IDLE
var cabin_door_is_open: bool = false
var movement_timer: Timer
var active_dispatch: ActiveDispatchState = null

# FRONT 到 LEFT 的临时桥接：对话记录与系统通信分别保存，后续由 UIHistoryState 管理。
var front_dialogue_history: Array[String] = []
var system_message_history: Array[String] = []
var current_building_status_hint: String = "暂无系统消息。"


func _ready() -> void:
	start_dispatch(INITIAL_DISPATCH_ID)
	_initialize_elevator_position()


func _initialize_elevator_position() -> void:
	# 初始位置在流程管理器中统一初始化，RIGHT 与 FRONT 都从这里读取。
	current_floor = initial_floor.strip_edges()
	target_floor = ""
	movement_state = MovementState.IDLE
	cabin_door_is_open = false
	movement_timer = Timer.new()
	movement_timer.one_shot = true
	movement_timer.wait_time = movement_duration_seconds
	movement_timer.timeout.connect(_complete_elevator_movement)
	add_child(movement_timer)
	case_updated.emit()


func start_dispatch(dispatch_id: StringName) -> bool:
	var dispatch: DispatchDefinition = ContentRegistry.get_dispatch(String(dispatch_id))
	if dispatch == null:
		push_error("DemoFlowManager: 无法开始不存在的派单：%s" % dispatch_id)
		return false

	# 每次开始派单都创建新对象，避免上一轮验证、目标或门控状态残留。
	active_dispatch = ActiveDispatchState.create_from_definition(dispatch)
	front_dialogue_history.clear()
	current_building_status_hint = "当前系统提示：\n%s 层检测到待接乘客。\n建议前往 %s 层完成接乘确认。\n\n当前任务：\n前往接乘楼层。" % [get_pickup_floor(), get_pickup_floor()]
	system_message_history = [current_building_status_hint]
	case_updated.emit()
	return true


func clear_active_dispatch() -> void:
	active_dispatch = null
	front_dialogue_history.clear()
	system_message_history.clear()
	current_building_status_hint = "暂无系统消息。"
	case_updated.emit()


func has_active_dispatch() -> bool:
	return active_dispatch != null


func add_front_transcript_operator(operator_text: String) -> void:
	# 单行写入供 Dialogue Manager 接入使用；仍然只进入 TRANSCRIPT。
	if operator_text.is_empty():
		return
	front_dialogue_history.append("操作员：%s" % operator_text)
	_trim_front_dialogue_history()


func add_front_transcript_passenger(passenger_text: String) -> void:
	if passenger_text.is_empty():
		return
	var formatted_passenger_text: String = passenger_text
	if not formatted_passenger_text.begins_with("乘客："):
		formatted_passenger_text = "乘客：%s" % formatted_passenger_text
	front_dialogue_history.append(formatted_passenger_text)
	_trim_front_dialogue_history()


func _trim_front_dialogue_history() -> void:
	while front_dialogue_history.size() > MAX_FRONT_HISTORY_LINES:
		front_dialogue_history.pop_front()


func get_front_dialogue_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享对话缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_dialogue_history)
	return history_copy


func get_current_building_status_hint() -> String:
	return current_building_status_hint


func set_building_status_hint(
		hint: String,
		include_in_history: bool = true,
		history_text: String = ""
) -> void:
	if hint.is_empty():
		return
	current_building_status_hint = hint
	if include_in_history:
		var message_text: String = history_text if not history_text.is_empty() else hint
		_append_system_message(message_text)
	case_updated.emit()


func add_system_log_message(message_text: String) -> void:
	# 仅写入左侧历史，不覆盖 FRONT 当前正在显示的短提示。
	if message_text.is_empty():
		return
	_append_system_message(message_text)
	case_updated.emit()


func _append_system_message(message_text: String) -> void:
	system_message_history.append(message_text)
	while system_message_history.size() > MAX_FRONT_HISTORY_LINES:
		system_message_history.pop_front()


func get_system_message_history() -> Array[String]:
	# 返回副本，避免终端界面意外改写本轮系统通信记录。
	var history_copy: Array[String] = []
	history_copy.assign(system_message_history)
	return history_copy


func get_passenger_label() -> String:
	var passenger: PassengerDefinition = get_active_passenger()
	if passenger == null:
		return ""
	return passenger.system_name if passenger.display_name.is_empty() \
			else "%s / %s" % [passenger.system_name, passenger.display_name]


func get_active_dispatch() -> DispatchDefinition:
	if active_dispatch == null:
		return null
	var dispatch: DispatchDefinition = ContentRegistry.get_dispatch(String(active_dispatch.dispatch_id))
	if dispatch == null:
		push_error("DemoFlowManager: 当前状态引用了不存在的派单：%s" % active_dispatch.dispatch_id)
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
	# 缺少阶段时回退到接乘初始画面；无效摄像头编号只返回空文本，避免数组越界。
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return ""
	var camera_feeds: Dictionary = dispatch.camera_feeds
	var phase_feeds: Array = camera_feeds.get(phase, camera_feeds.get("WAITING_FOR_PICKUP", []))
	if camera_index < 0 or camera_index >= phase_feeds.size():
		return ""
	return str(phase_feeds[camera_index])


func get_front_phase_text(phase: String) -> Dictionary:
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return {}
	var phase_texts: Dictionary = dispatch.front_phase_texts
	var text_data: Dictionary = phase_texts.get(phase, phase_texts.get("WAITING_FOR_PICKUP", {})).duplicate(true)
	text_data["state"] = _format_case_text(str(text_data.get("state", "")))
	text_data["task"] = _format_case_text(str(text_data.get("task", "")))
	return text_data


func _format_case_text(template: String) -> String:
	# 主操作台阶段文案目前只使用接乘楼层占位符。
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
	if active_dispatch == null:
		return null
	return ContentRegistry.get_dispatch_floor_relation(String(active_dispatch.dispatch_id), floor_id)


func get_current_floor() -> String:
	return current_floor


func get_target_floor() -> String:
	return target_floor


func get_movement_state_text() -> String:
	var door_text: String = "舱门开启" if cabin_door_is_open else "舱门关闭"
	match movement_state:
		MovementState.MOVING:
			return "运行中，舱门关闭"
		MovementState.ARRIVED:
			return "已停靠，%s" % door_text
		_:
			return "待命，%s" % door_text


func is_elevator_moving() -> bool:
	return movement_state == MovementState.MOVING


func is_cabin_door_open() -> bool:
	return cabin_door_is_open


func set_cabin_door_open(is_open: bool) -> void:
	# 门控由 FRONT 处理，位置状态只保存门是否已开，确保不能开门移动。
	if cabin_door_is_open == is_open:
		return
	cabin_door_is_open = is_open
	case_updated.emit()


func request_elevator_movement(destination: String) -> bool:
	# 只处理电梯移动，不推进接乘、送达或案例阶段。
	var requested_floor: String = destination.strip_edges()
	if requested_floor.is_empty() or not ContentRegistry.has_floor(requested_floor):
		return false
	if is_elevator_moving() or cabin_door_is_open:
		return false

	target_floor = requested_floor
	movement_state = MovementState.MOVING
	set_building_status_hint("电梯正在前往 %s 层。" % target_floor)
	if movement_timer != null:
		movement_timer.start()
	return true


func _complete_elevator_movement() -> void:
	# 到站只更新位置并保持舱门关闭；乘客登舱与楼层反馈仍必须等 FRONT 的开门操作。
	if target_floor.is_empty():
		return
	current_floor = target_floor
	target_floor = ""
	movement_state = MovementState.ARRIVED
	cabin_door_is_open = false
	# 接乘点状态跟随当前位置刷新，保证离开 612 后门外摄像头不会继续显示 612 的证据。
	if not is_passenger_onboard() and current_floor == get_pickup_floor():
		var pickup_phase: String = "DOOR_GREETING_DONE" \
			if is_door_greeting_done() else "ARRIVED_AT_PICKUP"
		if get_case_phase() != pickup_phase:
			set_case_phase(pickup_phase)
		# 主台仍保留原有接乘提示；日志只保存精简的关键状态。
		set_building_status_hint(
			get_pickup_arrival_status_hint(),
			true,
			"已抵达接乘楼层。\n等待乘客确认。"
		)
	elif not is_passenger_onboard() and get_case_phase() in ["ARRIVED_AT_PICKUP", "DOOR_GREETING_DONE"]:
		set_case_phase("WAITING_FOR_PICKUP")
		set_building_status_hint("已停靠于 %s 层，舱门保持关闭。" % current_floor)
	else:
		set_building_status_hint("已停靠于 %s 层，舱门保持关闭。" % current_floor)
	elevator_movement_completed.emit(current_floor)


func get_case_phase() -> String:
	return String(active_dispatch.current_phase) if active_dispatch != null else "WAITING_FOR_PICKUP"


func set_case_phase(phase: String) -> void:
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改派单阶段。")
		return
	active_dispatch.current_phase = StringName(phase)
	case_updated.emit()


func is_passenger_onboard() -> bool:
	return active_dispatch != null and active_dispatch.passenger_inside


func set_passenger_onboard(value: bool) -> void:
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改乘客进舱状态。")
		return
	active_dispatch.passenger_inside = value
	case_updated.emit()


func is_door_greeting_done() -> bool:
	return active_dispatch != null and active_dispatch.door_greeting_done


func set_door_greeting_done(value: bool) -> void:
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改门外问候状态。")
		return
	active_dispatch.door_greeting_done = value
	case_updated.emit()


func is_cabin_door_closed_after_boarding() -> bool:
	return active_dispatch != null and active_dispatch.cabin_door_closed_after_boarding


func set_cabin_door_closed_after_boarding(value: bool) -> void:
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法修改登舱后的门控状态。")
		return
	active_dispatch.cabin_door_closed_after_boarding = value
	case_updated.emit()


func set_validated_floor(floor_id: String) -> bool:
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法记录楼层验证。")
		return false
	var normalized_id: String = floor_id.strip_edges()
	if not normalized_id.is_empty() and not ContentRegistry.has_floor(normalized_id):
		push_warning("DemoFlowManager: 无法记录不存在的验证楼层：%s" % normalized_id)
		return false
	active_dispatch.validated_floor_id = StringName(normalized_id)
	case_updated.emit()
	return true


func get_validated_floor() -> String:
	return String(active_dispatch.validated_floor_id) if active_dispatch != null else ""


func select_target_floor(floor_id: String) -> bool:
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法记录目标楼层。")
		return false
	var normalized_id: String = floor_id.strip_edges()
	if normalized_id.is_empty() or not ContentRegistry.has_floor(normalized_id):
		push_warning("DemoFlowManager: 无法提交不存在的楼层：%s" % normalized_id)
		return false
	active_dispatch.selected_target_floor_id = StringName(normalized_id)
	case_updated.emit()
	return true


func get_selected_target_floor() -> String:
	return String(active_dispatch.selected_target_floor_id) if active_dispatch != null else ""


func try_mark_arrival_triggered() -> bool:
	if active_dispatch == null or active_dispatch.arrival_triggered:
		return false
	active_dispatch.arrival_triggered = true
	case_updated.emit()
	return true


func get_current_recommended_destinations() -> Array[String]:
	var phase: String = get_case_phase()
	var pickup_phases: Array[String] = [
		"WAITING_FOR_PICKUP",
		"ARRIVED_AT_PICKUP",
		"DOOR_GREETING_DONE",
		"BOARDING_WAIT_DOOR_CLOSE",
	]
	var dispatch: DispatchDefinition = get_active_dispatch()
	if dispatch == null:
		return []
	var is_pickup_phase: bool = not is_passenger_onboard() and phase in pickup_phases
	# 接乘阶段只显示接乘楼层，正式派单推荐要等乘客进舱后才可见。
	if is_pickup_phase:
		var pickup_floor: String = String(dispatch.pickup_floor_id)
		return [pickup_floor] if not pickup_floor.is_empty() else []

	# 运行时列表决定当前显示内容，静态关系是推荐资格的唯一规则来源。
	var candidates: Array[String] = []
	var runtime_recommendations: Array[StringName] = active_dispatch.get_recommended_floor_ids()
	for destination: StringName in runtime_recommendations:
		var floor_number: String = String(destination)
		var relation: DispatchFloorRelation = get_dispatch_floor_relation(floor_number)
		if relation != null and relation.recommendation_eligible \
				and floor_number not in candidates:
			candidates.append(floor_number)
	return candidates


func add_recommended_destination(destination: String) -> void:
	# DM mutation 只追加本轮运行时推荐；是否有资格由派单关系资源决定。
	if active_dispatch == null:
		push_warning("DemoFlowManager: 当前无派单，无法解锁推荐楼层。")
		return
	var floor_number: String = destination.strip_edges()
	if floor_number.is_empty():
		return
	var relation: DispatchFloorRelation = get_dispatch_floor_relation(floor_number)
	if relation == null or not relation.recommendation_eligible:
		push_warning("DemoFlowManager: 楼层 %s 不具备当前派单的推荐资格。" % floor_number)
		return
	var changed: bool = active_dispatch.add_recommended_floor(StringName(floor_number))
	if changed:
		case_updated.emit()

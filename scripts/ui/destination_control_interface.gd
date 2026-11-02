extends Control
class_name DestinationControlInterface


const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)


signal presentation_effects_requested(effects: Array[StringName])
signal destination_presentation_changed(snapshot: Dictionary)
signal destination_travel_result(result: FlowCommandResult)


const PRESENTATION_BUSY_HINT: String = \
		"乘客或舱门动作尚未完成，暂时无法启动电梯。"


# 数字输入与反馈属于唯一业务实例，GLB 和 UI 只读取展示快照。
var _destination_input: String = ""
var _destination_feedback: String = ""

var demo_flow_manager: DemoFlowManager
var _monitor_presentation_coordinator: MonitorPresentationCoordinator3D
var embedded_3d_mode: bool = false
var _standalone_validated_floor: String = ""
var _address_status: String = "未验证"


func _ready() -> void:
	_initialize_destination_text()
	_refresh_travel_availability()
	_notify_destination_presentation_changed()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		return
	_disconnect_demo_flow_manager()
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		push_warning("DestinationControlInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.connect(_refresh_case_display)
	if not demo_flow_manager.elevator_movement_completed.is_connected(_on_elevator_movement_completed):
		demo_flow_manager.elevator_movement_completed.connect(_on_elevator_movement_completed)
	if not demo_flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		demo_flow_manager.dispatch_started.connect(_on_dispatch_started)
	if not demo_flow_manager.shift_completed.is_connected(_on_shift_completed):
		demo_flow_manager.shift_completed.connect(_on_shift_completed)
	# 子节点 ready 后才注入共享流程，因此这里再次刷新案例相关文字。
	_initialize_destination_text()
	_notify_destination_presentation_changed()


func set_monitor_presentation_coordinator(
		coordinator: MonitorPresentationCoordinator3D
) -> void:
	if _monitor_presentation_coordinator == coordinator:
		_refresh_travel_availability()
		return
	_disconnect_monitor_presentation_coordinator()
	_monitor_presentation_coordinator = coordinator
	if is_instance_valid(_monitor_presentation_coordinator) \
			and not _monitor_presentation_coordinator \
					.presentation_busy_changed.is_connected(
						_on_presentation_busy_changed
					):
		_monitor_presentation_coordinator.presentation_busy_changed.connect(
			_on_presentation_busy_changed
		)
	_refresh_travel_availability()


func _disconnect_monitor_presentation_coordinator() -> void:
	if not is_instance_valid(_monitor_presentation_coordinator):
		return
	if _monitor_presentation_coordinator \
			.presentation_busy_changed.is_connected(
				_on_presentation_busy_changed
			):
		_monitor_presentation_coordinator.presentation_busy_changed.disconnect(
			_on_presentation_busy_changed
		)


func _disconnect_demo_flow_manager() -> void:
	if demo_flow_manager == null:
		return
	if demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.disconnect(_refresh_case_display)
	if demo_flow_manager.elevator_movement_completed.is_connected(_on_elevator_movement_completed):
		demo_flow_manager.elevator_movement_completed.disconnect(_on_elevator_movement_completed)
	if demo_flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		demo_flow_manager.dispatch_started.disconnect(_on_dispatch_started)
	if demo_flow_manager.shift_completed.is_connected(_on_shift_completed):
		demo_flow_manager.shift_completed.disconnect(_on_shift_completed)


func _on_dispatch_started(_dispatch_id: StringName) -> void:
	# 新派单保留电梯位置，但清掉上一单的输入、验证和派单评估。
	_set_destination_input("", false)
	_standalone_validated_floor = ""
	_address_status = "未验证"
	_destination_feedback = "新派单已加载，请选择或输入目标楼层。"
	_refresh_case_display()


func _on_shift_completed() -> void:
	_set_destination_input("", false)
	_standalone_validated_floor = ""
	_address_status = "未验证"
	_destination_feedback = "本轮派单已完成；仍可输入已登记楼层自由移动。"
	_refresh_case_display()


func _refresh_case_display() -> void:
	_notify_destination_presentation_changed()


func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notify_destination_presentation_changed()


func _initialize_destination_text() -> void:
	_destination_feedback = "请选择推荐楼层，或手动输入目标楼层。"
	if demo_flow_manager == null:
		_destination_feedback = "数据源未连接：无法读取楼层与派单信息。"


func _on_destination_text_changed(_new_text: String) -> void:
	# 数字输入每次改写都使旧验证失效。
	_standalone_validated_floor = ""
	_address_status = "未验证"
	if demo_flow_manager != null:
		demo_flow_manager.request_clear_destination_validation()
	_destination_feedback = "目标已变更，请重新验证地址。"
	_notify_destination_presentation_changed()


func _verify_destination() -> void:
	if demo_flow_manager == null:
		_standalone_validated_floor = ""
		_address_status = "系统未连接"
		_destination_feedback = "数据源未连接：无法验证目标楼层。"
		_notify_destination_presentation_changed()
		return

	var result: FlowCommandResultScript = demo_flow_manager.request_validate_destination(
		_get_current_destination()
	)
	_destination_feedback = result.message
	if not result.succeeded:
		_standalone_validated_floor = ""
		_address_status = "验证失败"
		_notify_destination_presentation_changed()
		return
	_standalone_validated_floor = result.floor_id
	_address_status = "已验证"

	_notify_destination_presentation_changed()


func _submit_destination() -> void:
	# 统一入口阻止在乘客或舱门表现运行时提交。
	if _is_presentation_busy():
		_destination_feedback = PRESENTATION_BUSY_HINT
		_notify_destination_presentation_changed()
		return
	if demo_flow_manager == null:
		_destination_feedback = "电梯位置系统尚未连接。"
		_notify_destination_presentation_changed()
		return

	var result: FlowCommandResultScript = demo_flow_manager.request_travel_to_floor(
		_get_current_destination()
	)
	_destination_feedback = result.message
	if result.code == &"DESTINATION_NOT_VALIDATED":
		_address_status = "未验证｜请先验证楼层"
	if result.succeeded:
		presentation_effects_requested.emit(result.get_effects())
		# 行驶已经接收后只清空 LCD 输入缓存；保留本次验证状态供移动流程使用。
		_set_destination_input("", false, false)
	_notify_destination_presentation_changed()
	destination_travel_result.emit(result)


func _is_presentation_busy() -> bool:
	return is_instance_valid(_monitor_presentation_coordinator) \
			and _monitor_presentation_coordinator.is_presentation_busy()


func _refresh_travel_availability() -> void:
	_notify_destination_presentation_changed()


func _on_presentation_busy_changed(_is_busy: bool) -> void:
	_refresh_travel_availability()


func _on_elevator_movement_completed(arrived_floor: String) -> void:
	# 移动完成时清除“正在前往”的旧提示，避免右侧保留过期运行状态。
	_destination_feedback = "已停靠于 %s 层，舱门保持关闭。" % arrived_floor
	_notify_destination_presentation_changed()


# 数字键改写同一输入缓存，验证失效仍通过既有命令执行。
func append_destination_digit(digit: String) -> void:
	if digit.length() != 1 or digit < "0" or digit > "9":
		push_warning("右台数字键收到无效字符：%s" % digit)
		return
	_set_destination_input(_get_current_destination() + digit, true)


func backspace_destination_input() -> void:
	var current_input := _get_current_destination()
	if current_input.is_empty():
		return
	_set_destination_input(current_input.left(current_input.length() - 1), true)


func clear_destination_input() -> void:
	if _get_current_destination().is_empty():
		return
	_set_destination_input("", true)


func request_verify_destination() -> void:
	_verify_destination()


func request_submit_destination() -> void:
	_submit_destination()


func get_destination_presentation() -> Dictionary:
	var current_floor := "---"
	var validated_floor := _standalone_validated_floor
	var recommendations: Array[String] = []
	if demo_flow_manager != null:
		current_floor = demo_flow_manager.get_current_floor()
		for recommendation: String in _get_recommended_destinations():
			recommendations.append(recommendation)
		if demo_flow_manager.has_active_dispatch():
			validated_floor = demo_flow_manager.get_validated_floor()

	var recommendation_text := "—"
	if _should_show_recommendations() and not recommendations.is_empty():
		recommendation_text = " / ".join(recommendations)
	return {
		"input": _get_current_destination(),
		"current_floor": current_floor,
		"recommended": recommendation_text,
		"validated_floor": validated_floor if not validated_floor.is_empty() else "---",
		"address_status": _address_status,
		"feedback": _destination_feedback,
		"presentation_busy": _is_presentation_busy(),
	}


func _set_destination_input(
		new_text: String,
		invalidate_validation: bool,
		notify_change: bool = true
) -> void:
	if _destination_input == new_text:
		return
	_destination_input = new_text
	if invalidate_validation:
		_on_destination_text_changed(new_text)
	elif notify_change:
		_notify_destination_presentation_changed()


func _notify_destination_presentation_changed() -> void:
	if not is_node_ready():
		return
	destination_presentation_changed.emit(get_destination_presentation())


func _get_current_destination() -> String:
	# 保留字符串编号，例如 001；只清理首尾空格。
	return _destination_input.strip_edges()


func _get_recommended_destinations() -> Array:
	if demo_flow_manager == null:
		return []
	return demo_flow_manager.get_current_recommended_destinations()


func _should_show_recommendations() -> bool:
	# 乘客上梯后显示正式推荐；接乘阶段则只显示乘客所在楼层。
	if demo_flow_manager == null or not demo_flow_manager.has_active_dispatch():
		return false
	if demo_flow_manager.is_passenger_onboard():
		return true
	return demo_flow_manager.get_case_phase() in [
		DispatchPhase.WAITING_FOR_PICKUP,
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.DOOR_GREETING_DONE,
	]

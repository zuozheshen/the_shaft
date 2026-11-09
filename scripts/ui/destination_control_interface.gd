extends Control
class_name DestinationControlInterface


const FlowCommandResultScript := preload(
	"res://scripts/runtime/commands/flow_command_result.gd"
)


signal presentation_effects_requested(effects: Array[StringName])
signal destination_presentation_changed(snapshot: Dictionary)
signal destination_travel_result(result: FlowCommandResult)
signal archive_document_retrieved(session: int, ref: Dictionary)


const PRESENTATION_BUSY_HINT: String = \
		"乘客或舱门动作尚未完成，暂时无法启动电梯。"


# 数字输入与反馈属于唯一业务实例，GLB 和 UI 只读取展示快照。
var _destination_input: String = ""
var _destination_feedback: String = ""

var demo_flow_manager: DemoFlowManager
var _monitor_presentation_coordinator: MonitorPresentationCoordinator3D
var embedded_3d_mode: bool = false
var _lookup: Dictionary = {}
var _lookup_session: int = 0
var _query_sequence: int = 0


func _ready() -> void:
	_refresh_lookup()
	_refresh_travel_availability()
	_notify_destination_presentation_changed()


func set_demo_flow_manager(flow_manager: DemoFlowManager) -> void:
	if demo_flow_manager == flow_manager:
		return
	_disconnect_demo_flow_manager()
	demo_flow_manager = flow_manager
	if demo_flow_manager == null:
		_refresh_lookup()
		_notify_destination_presentation_changed()
		push_warning("DestinationControlInterface: DemoFlowManager is not connected.")
		return
	if not demo_flow_manager.case_updated.is_connected(_refresh_case_display):
		demo_flow_manager.case_updated.connect(_refresh_case_display)
	if not demo_flow_manager.elevator_movement_completed.is_connected(_on_elevator_movement_completed):
		demo_flow_manager.elevator_movement_completed.connect(_on_elevator_movement_completed)
	if not demo_flow_manager.document_session_changed.is_connected(_on_document_session_changed):
		demo_flow_manager.document_session_changed.connect(_on_document_session_changed)
	# 子节点 ready 后才注入共享流程，因此这里再次刷新案例相关文字。
	_refresh_lookup()
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
	if demo_flow_manager.document_session_changed.is_connected(_on_document_session_changed):
		demo_flow_manager.document_session_changed.disconnect(_on_document_session_changed)


func _on_document_session_changed(_session: int) -> void:
	_destination_input = ""
	_destination_feedback = ""
	_refresh_lookup()
	_notify_destination_presentation_changed()


func _refresh_case_display() -> void:
	_notify_destination_presentation_changed()


func set_embedded_3d_mode(is_enabled: bool) -> void:
	embedded_3d_mode = is_enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notify_destination_presentation_changed()


# 待调阅快照只属于这一次输入。即使改回原编号，也分配新的查询身份。
func _refresh_lookup() -> void:
	_lookup.clear()
	_query_sequence += 1
	_lookup_session = demo_flow_manager.get_document_session_id() if demo_flow_manager != null else 0
	var floor_id := _get_current_destination()
	if demo_flow_manager != null and not floor_id.is_empty():
		_lookup = ContentRegistry.query_floor_archive(floor_id, demo_flow_manager.get_active_dispatch())


func request_retrieve_floor_archive() -> void:
	if demo_flow_manager == null:
		_destination_feedback = "楼层资料系统未连接。"
	elif _lookup_session <= 0:
		_destination_feedback = "当前无派单，无法加入核验资料。"
	elif _lookup.get("status") != "found":
		_destination_feedback = "请输入可查询的完整楼层编号。"
	else:
		var floor_id := _get_current_destination()
		var current := ContentRegistry.query_floor_archive(floor_id, demo_flow_manager.get_active_dispatch())
		if _lookup_session != demo_flow_manager.get_document_session_id() or current != _lookup \
				or String(_lookup.document.owner_id) != floor_id:
			_refresh_lookup()
			_destination_feedback = "档案已更新，请核对摘要后重新调阅。"
		else:
			var session := _lookup_session
			var sequence := _query_sequence
			var ref := {"document_id": _lookup.document.document_id, "version": _lookup.document.version}
			var query_id := StringName("right:%d:%d" % [session, sequence])
			var result := demo_flow_manager.accept_right_lookup_result(session, query_id, [ref])
			# 收件信号可能同步切换会话，旧回调不能再打开窗口或覆盖新状态。
			if sequence != _query_sequence or session != demo_flow_manager.get_document_session_id():
				return
			if result.succeeded:
				_destination_feedback = "已调阅 %s 档案。" % floor_id
				archive_document_retrieved.emit(session, ref)
			else:
				_destination_feedback = "无法调阅档案（%s）。" % result.code
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
	if result.succeeded:
		# 成功清空查询，但运行中的目标仍由 Manager 独立提供。
		_destination_input = ""
		_refresh_lookup()
		presentation_effects_requested.emit(result.get_effects())
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


# 数字键改写同一个字符串输入，修改后立即更新只读查询。
func append_destination_digit(digit: String) -> void:
	if digit.length() != 1 or digit < "0" or digit > "9":
		push_warning("右台数字键收到无效字符：%s" % digit)
		return
	_set_destination_input(_get_current_destination() + digit)


func backspace_destination_input() -> void:
	var current_input := _get_current_destination()
	if current_input.is_empty():
		return
	_set_destination_input(current_input.left(current_input.length() - 1))


func clear_destination_input() -> void:
	if _get_current_destination().is_empty():
		return
	_set_destination_input("")


func request_submit_destination() -> void:
	_submit_destination()


func get_destination_presentation() -> Dictionary:
	var current_floor := "---"
	var execution_target := "---"
	if demo_flow_manager != null:
		current_floor = demo_flow_manager.get_current_floor()
		if demo_flow_manager.is_elevator_moving():
			execution_target = demo_flow_manager.get_target_floor()

	var status: String = _lookup.get("status", "")
	var document: Dictionary = _lookup.get("document", {})
	var source: Dictionary = document.get("source", {})
	var source_id: String = source.get("source_id", "—")
	var source_version: String = source.get("source_version", "")
	if source_id.begins_with("registry/floor/"):
		source_id = "楼层登记"
		source_version = ""
	return {
		"input": _get_current_destination(),
		"current_floor": current_floor,
		"execution_target": execution_target,
		"query_floor": document.get("owner_id", "---"),
		"query_status": status,
		"current_function": _summary_field(document, "current_function"),
		"current_area": _summary_field(document, "current_area"),
		"administrative_access_conditions": _summary_field(document, "administrative_access_conditions"),
		"elevator_stop": ("支持停靠" if _lookup.elevator_accessible else "不支持停靠") if status == "found" else "—",
		"source": source_id,
		"source_version": source_version,
		"updated_at": source.get("updated_at", ""),
		"feedback": _destination_feedback,
		"presentation_busy": _is_presentation_busy(),
	}


func _summary_field(document: Dictionary, field_id: String) -> String:
	var field: Dictionary = document.get("fields", {}).get(field_id, {})
	var value := String(field.get("display_value", "")).strip_edges()
	return value if field.get("has_value", false) and not value.is_empty() else "未记录"


func _set_destination_input(new_text: String) -> void:
	if _destination_input == new_text:
		return
	_destination_input = new_text
	_destination_feedback = ""
	_refresh_lookup()
	_notify_destination_presentation_changed()


func _notify_destination_presentation_changed() -> void:
	if not is_node_ready():
		return
	destination_presentation_changed.emit(get_destination_presentation())


func _get_current_destination() -> String:
	# 保留字符串编号，例如 001；只清理首尾空格。
	return _destination_input.strip_edges()

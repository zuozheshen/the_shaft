class_name MonitorPresentationCoordinator3D
extends Node


signal presentation_busy_changed(is_busy: bool)


@export var passenger_visual_profiles: Array[PassengerVisualProfile] = []

var _flow_manager: DemoFlowManager
var _main_interface: ConsoleInterface
var _destination_interface: DestinationControlInterface
var _stage_controller: MonitorStageController3D

var _profile_by_passenger_id: Dictionary = {}
var _pending_boarding: bool = false
var _pending_disembark: bool = false
var _pending_dispatch_sync_after_door_close: bool = false
var _is_setup_complete: bool = false
var _last_reported_busy: bool = false


func setup(
		flow_manager: DemoFlowManager,
		main_interface: ConsoleInterface,
		destination_interface: DestinationControlInterface,
		stage_controller: MonitorStageController3D
) -> void:
	# 重复 setup 时先断开旧来源，避免同一个业务 effect 被处理多次。
	_disconnect_sources()
	if is_instance_valid(_stage_controller):
		_stage_controller.cancel_passenger_movement()

	_flow_manager = flow_manager
	_main_interface = main_interface
	_destination_interface = destination_interface
	_stage_controller = stage_controller
	_pending_boarding = false
	_pending_disembark = false
	_pending_dispatch_sync_after_door_close = false
	_is_setup_complete = false
	_build_profile_index()

	# 流程管理器是唯一必需的业务来源；其余节点缺失时只关闭对应表现能力。
	if not is_instance_valid(_flow_manager):
		push_warning("监控表现协调器缺少 DemoFlowManager，将保持非阻塞状态。")
		_refresh_presentation_busy()
		return

	_connect_sources()
	_is_setup_complete = true
	_apply_active_passenger_profile()
	_sync_stable_presentation_from_business()
	_refresh_presentation_busy()


func is_presentation_busy() -> bool:
	return _pending_boarding \
			or _pending_disembark \
			or (
				is_instance_valid(_stage_controller)
				and _stage_controller.is_presentation_busy()
			)


func _exit_tree() -> void:
	_disconnect_sources()
	_pending_boarding = false
	_pending_disembark = false
	_pending_dispatch_sync_after_door_close = false
	_is_setup_complete = false


func _connect_sources() -> void:
	if not _flow_manager.dispatch_started.is_connected(_on_dispatch_started):
		_flow_manager.dispatch_started.connect(_on_dispatch_started)
	if not _flow_manager.dispatch_completed.is_connected(_on_dispatch_completed):
		_flow_manager.dispatch_completed.connect(_on_dispatch_completed)
	if not _flow_manager.shift_completed.is_connected(_on_shift_completed):
		_flow_manager.shift_completed.connect(_on_shift_completed)
	if not _flow_manager.elevator_movement_completed.is_connected(
			_on_elevator_movement_completed
	):
		_flow_manager.elevator_movement_completed.connect(
			_on_elevator_movement_completed
		)

	if is_instance_valid(_main_interface):
		if not _main_interface.presentation_effects_requested.is_connected(
				_on_presentation_effects_requested
		):
			_main_interface.presentation_effects_requested.connect(
				_on_presentation_effects_requested
			)
	else:
		push_warning("监控表现协调器缺少 ConsoleInterface，门控业务仍可继续运行。")

	if is_instance_valid(_destination_interface):
		if not _destination_interface.presentation_effects_requested.is_connected(
				_on_presentation_effects_requested
		):
			_destination_interface.presentation_effects_requested.connect(
				_on_presentation_effects_requested
			)
	else:
		push_warning("监控表现协调器缺少 DestinationControlInterface，门与乘客表现仍可工作。")

	if is_instance_valid(_stage_controller):
		if not _stage_controller.door_presentation_state_changed.is_connected(
				_on_door_presentation_state_changed
			):
			_stage_controller.door_presentation_state_changed.connect(
				_on_door_presentation_state_changed
			)
		if not _stage_controller.door_presentation_opened.is_connected(
				_on_door_presentation_opened
			):
			_stage_controller.door_presentation_opened.connect(
				_on_door_presentation_opened
			)
		if not _stage_controller.presentation_busy_changed.is_connected(
				_on_stage_presentation_busy_changed
		):
			_stage_controller.presentation_busy_changed.connect(
				_on_stage_presentation_busy_changed
			)
	else:
		push_warning("监控表现协调器缺少 MonitorStageController3D，将跳过三维表现。")


func _disconnect_sources() -> void:
	if is_instance_valid(_flow_manager):
		if _flow_manager.dispatch_started.is_connected(_on_dispatch_started):
			_flow_manager.dispatch_started.disconnect(_on_dispatch_started)
		if _flow_manager.dispatch_completed.is_connected(_on_dispatch_completed):
			_flow_manager.dispatch_completed.disconnect(_on_dispatch_completed)
		if _flow_manager.shift_completed.is_connected(_on_shift_completed):
			_flow_manager.shift_completed.disconnect(_on_shift_completed)
		if _flow_manager.elevator_movement_completed.is_connected(
				_on_elevator_movement_completed
		):
			_flow_manager.elevator_movement_completed.disconnect(
				_on_elevator_movement_completed
			)

	if is_instance_valid(_main_interface) \
			and _main_interface.presentation_effects_requested.is_connected(
				_on_presentation_effects_requested
			):
		_main_interface.presentation_effects_requested.disconnect(
			_on_presentation_effects_requested
		)

	if is_instance_valid(_destination_interface) \
			and _destination_interface.presentation_effects_requested.is_connected(
				_on_presentation_effects_requested
			):
		_destination_interface.presentation_effects_requested.disconnect(
			_on_presentation_effects_requested
		)

	if is_instance_valid(_stage_controller):
		if _stage_controller.door_presentation_state_changed.is_connected(
				_on_door_presentation_state_changed
			):
			_stage_controller.door_presentation_state_changed.disconnect(
				_on_door_presentation_state_changed
			)
		if _stage_controller.door_presentation_opened.is_connected(
				_on_door_presentation_opened
			):
			_stage_controller.door_presentation_opened.disconnect(
				_on_door_presentation_opened
			)
		if _stage_controller.presentation_busy_changed.is_connected(
				_on_stage_presentation_busy_changed
		):
			_stage_controller.presentation_busy_changed.disconnect(
				_on_stage_presentation_busy_changed
			)


func _build_profile_index() -> void:
	_profile_by_passenger_id.clear()
	for profile: PassengerVisualProfile in passenger_visual_profiles:
		if profile == null:
			push_warning("监控表现协调器跳过了空的 PassengerVisualProfile。")
			continue
		if profile.passenger_id == &"":
			push_warning("监控表现协调器跳过了 passenger_id 为空的 Profile。")
			continue
		if _profile_by_passenger_id.has(profile.passenger_id):
			push_warning(
				"监控表现协调器跳过了重复的乘客 Profile：%s"
				% profile.passenger_id
			)
			continue
		_profile_by_passenger_id[profile.passenger_id] = profile


func _apply_active_passenger_profile() -> void:
	if not is_instance_valid(_stage_controller) \
			or not is_instance_valid(_flow_manager) \
			or not _flow_manager.has_active_dispatch():
		return
	var dispatch: DispatchDefinition = _flow_manager.get_active_dispatch()
	if dispatch == null:
		return
	var passenger_id: StringName = dispatch.passenger_id
	var profile: PassengerVisualProfile = _profile_by_passenger_id.get(
		passenger_id
	) as PassengerVisualProfile
	if profile == null:
		# 缺少映射时保留摄影棚当前占位 Profile，不能因此中断派单。
		push_warning("监控表现协调器找不到乘客 Profile：%s" % passenger_id)
		return
	if not _stage_controller.apply_passenger_profile(profile):
		push_warning("监控表现协调器未能应用乘客 Profile：%s" % passenger_id)


func _on_presentation_effects_requested(effects: Array[StringName]) -> void:
	if not _is_setup_complete:
		return
	if FlowCommandResult.PASSENGER_BOARDED in effects:
		_queue_passenger_boarding()
	if FlowCommandResult.DROPOFF_FEEDBACK_FINISHED in effects:
		_queue_passenger_disembark()
	if FlowCommandResult.MOVEMENT_STARTED in effects:
		_handle_movement_started()


func _queue_passenger_boarding() -> void:
	_pending_boarding = true
	_refresh_presentation_busy()

	if not is_instance_valid(_stage_controller):
		# 业务已经成功登舱；表现层缺失时只释放表现锁。
		_pending_boarding = false
		_refresh_presentation_busy()
		return
	var state: int = _stage_controller.get_passenger_presentation_state()
	if state in [
		MonitorStageController3D.PassengerPresentationState.BOARDING,
		MonitorStageController3D.PassengerPresentationState.CABIN,
	]:
		_pending_boarding = false
		_refresh_presentation_busy()
		return
	_try_start_pending_passenger_movement()


func _queue_passenger_disembark() -> void:
	_pending_disembark = true
	_refresh_presentation_busy()

	if not is_instance_valid(_stage_controller):
		# 业务已进入等待关门阶段；无表现节点时不能永久保留 pending。
		_pending_disembark = false
		_refresh_presentation_busy()
		return
	var state: int = _stage_controller.get_passenger_presentation_state()
	if state in [
		MonitorStageController3D.PassengerPresentationState.DISEMBARKING,
		MonitorStageController3D.PassengerPresentationState.EXITED,
	]:
		_pending_disembark = false
		_refresh_presentation_busy()
		return
	_try_start_pending_passenger_movement()


func _try_start_pending_passenger_movement() -> void:
	_resolve_conflicting_pending()
	if not _pending_boarding and not _pending_disembark:
		_refresh_presentation_busy()
		return
	if not is_instance_valid(_stage_controller):
		_clear_pending_flags()
		_refresh_presentation_busy()
		return

	var door_visual: ElevatorDoorVisual3D = _stage_controller.get_door_visual()
	if not is_instance_valid(door_visual):
		_finish_pending_with_stable_snap()
		return

	match door_visual.get_door_state():
		ElevatorDoorVisual3D.DoorPresentationState.OPEN:
			_start_pending_passenger_movement()
		ElevatorDoorVisual3D.DoorPresentationState.OPENING:
			# pending 本身计入 busy，覆盖门刚开完到乘客 Tween 启动之间的窗口。
			return
		_:
			# 成功业务命令没有启动开门动画时，直接恢复到对应稳定表现。
			_finish_pending_with_stable_snap()


func _on_door_presentation_opened() -> void:
	if not _is_setup_complete:
		return
	_resolve_conflicting_pending()
	if _pending_boarding or _pending_disembark:
		_start_pending_passenger_movement()


func _start_pending_passenger_movement() -> void:
	if _pending_boarding:
		_pending_boarding = false
		if not is_instance_valid(_stage_controller) \
				or not _stage_controller.request_passenger_boarding():
			push_warning("监控表现协调器未能启动乘客登舱，改用稳定舱内位置。")
			if is_instance_valid(_stage_controller):
				_stage_controller.snap_passenger_cabin()
		_refresh_presentation_busy()
		return

	if _pending_disembark:
		_pending_disembark = false
		if not is_instance_valid(_stage_controller) \
				or not _stage_controller.request_passenger_disembark():
			push_warning("监控表现协调器未能启动乘客离舱，改用稳定离场位置。")
			if is_instance_valid(_stage_controller) \
					and not _stage_controller.snap_passenger_exited():
				_stage_controller.snap_passenger_hidden()
	_refresh_presentation_busy()


func _finish_pending_with_stable_snap() -> void:
	if _pending_boarding:
		_pending_boarding = false
		if is_instance_valid(_stage_controller) \
				and not _stage_controller.snap_passenger_cabin():
			push_warning("监控表现协调器无法恢复乘客舱内稳定位置。")
	elif _pending_disembark:
		_pending_disembark = false
		if is_instance_valid(_stage_controller) \
				and not _stage_controller.snap_passenger_exited():
			_stage_controller.snap_passenger_hidden()
	_refresh_presentation_busy()


func _resolve_conflicting_pending() -> void:
	if not _pending_boarding or not _pending_disembark:
		return
	push_error("监控表现协调器同时收到登舱与离舱 pending，将按业务阶段消除冲突。")
	var phase: String = _flow_manager.get_case_phase() \
			if is_instance_valid(_flow_manager) else ""
	if phase == DispatchPhase.BOARDING_WAIT_DOOR_CLOSE:
		_pending_disembark = false
	elif phase == DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE:
		_pending_boarding = false
	else:
		# 异常阶段仍沿用门开启回调规定的登舱优先级，绝不同时启动两条 Tween。
		_pending_disembark = false


func _handle_movement_started() -> void:
	if not is_instance_valid(_stage_controller):
		return
	if _stage_controller.get_passenger_presentation_state() \
			!= MonitorStageController3D.PassengerPresentationState.OUTSIDE_WAITING:
		return
	_pending_boarding = false
	if not _stage_controller.snap_passenger_hidden():
		push_warning("监控表现协调器未能在离开接乘楼层时隐藏乘客。")
	_refresh_presentation_busy()


func _on_elevator_movement_completed(arrived_floor: String) -> void:
	if not _is_setup_complete or not is_instance_valid(_stage_controller):
		return
	if not _flow_manager.has_active_dispatch():
		_stage_controller.snap_passenger_hidden()
		return

	# 已业务登舱的乘客跨楼层时始终留在舱内，不因楼层切片替换而消失。
	if _flow_manager.is_passenger_onboard():
		var state: int = _stage_controller.get_passenger_presentation_state()
		if state in [
			MonitorStageController3D.PassengerPresentationState.HIDDEN,
			MonitorStageController3D.PassengerPresentationState.OUTSIDE_WAITING,
			MonitorStageController3D.PassengerPresentationState.EXITED,
		]:
			_stage_controller.snap_passenger_cabin()
		return

	var pickup_floor: String = _flow_manager.get_pickup_floor()
	var phase: String = _flow_manager.get_case_phase()
	if arrived_floor == pickup_floor and phase in [
		DispatchPhase.ARRIVED_AT_PICKUP,
		DispatchPhase.DOOR_GREETING_DONE,
	]:
		_stage_controller.snap_passenger_outside_waiting()
	else:
		_stage_controller.snap_passenger_hidden()
	_refresh_presentation_busy()


func _on_dispatch_completed(_result: DispatchResult) -> void:
	_clear_pending_flags()
	if is_instance_valid(_stage_controller):
		_stage_controller.cancel_passenger_movement()
		_stage_controller.snap_passenger_hidden()
	_refresh_presentation_busy()


func _on_dispatch_started(_dispatch_id: StringName) -> void:
	_clear_pending_flags()
	if is_instance_valid(_stage_controller):
		_stage_controller.cancel_passenger_movement()
		_stage_controller.snap_passenger_hidden()
	_apply_active_passenger_profile()
	if _should_defer_dispatch_sync_until_door_closed():
		# 业务会在旧派单关门命令中同步启动下一单，但此时门动画还没开始。
		# 先隐藏新乘客，等门完全关闭后再恢复门外等待态，避免闪现在门后。
		_pending_dispatch_sync_after_door_close = true
	else:
		_sync_stable_presentation_from_business()
	_refresh_presentation_busy()


func _on_shift_completed() -> void:
	_clear_pending_flags()
	if is_instance_valid(_stage_controller):
		_stage_controller.cancel_passenger_movement()
		_stage_controller.snap_passenger_hidden()
	_refresh_presentation_busy()


func _sync_stable_presentation_from_business() -> void:
	if not is_instance_valid(_stage_controller):
		return
	_stage_controller.cancel_passenger_movement()
	_clear_pending_flags()
	if not is_instance_valid(_flow_manager) \
			or not _flow_manager.has_active_dispatch():
		_stage_controller.snap_passenger_hidden()
		return

	var phase: String = _flow_manager.get_case_phase()
	match phase:
		DispatchPhase.WAITING_FOR_PICKUP:
			if _flow_manager.get_current_floor() == _flow_manager.get_pickup_floor():
				_stage_controller.snap_passenger_outside_waiting()
			else:
				_stage_controller.snap_passenger_hidden()
		DispatchPhase.ARRIVED_AT_PICKUP, DispatchPhase.DOOR_GREETING_DONE:
			_stage_controller.snap_passenger_outside_waiting()
		DispatchPhase.BOARDING_WAIT_DOOR_CLOSE, \
				DispatchPhase.PASSENGER_ONBOARD, \
				DispatchPhase.ARRIVED_AT_DESTINATION, \
				DispatchPhase.DROPOFF_FEEDBACK:
			_stage_controller.snap_passenger_cabin()
		DispatchPhase.DROPOFF_WAIT_DOOR_CLOSE:
			if not _stage_controller.snap_passenger_exited():
				_stage_controller.snap_passenger_hidden()
		_:
			push_warning("监控表现协调器无法映射派单阶段：%s" % phase)
			_stage_controller.snap_passenger_hidden()


func _clear_pending_flags() -> void:
	_pending_boarding = false
	_pending_disembark = false
	_pending_dispatch_sync_after_door_close = false


func _should_defer_dispatch_sync_until_door_closed() -> bool:
	if not is_instance_valid(_stage_controller):
		return false
	var door_visual: ElevatorDoorVisual3D = _stage_controller.get_door_visual()
	return is_instance_valid(door_visual) and not door_visual.is_closed()


func _on_door_presentation_state_changed(state: int) -> void:
	if not _is_setup_complete \
			or not _pending_dispatch_sync_after_door_close \
			or state != ElevatorDoorVisual3D.DoorPresentationState.CLOSED:
		return
	_pending_dispatch_sync_after_door_close = false
	_sync_stable_presentation_from_business()
	_refresh_presentation_busy()


func _on_stage_presentation_busy_changed(_is_busy: bool) -> void:
	_refresh_presentation_busy()


func _refresh_presentation_busy() -> void:
	var is_busy: bool = is_presentation_busy()
	if is_busy == _last_reported_busy:
		return
	_last_reported_busy = is_busy
	presentation_busy_changed.emit(is_busy)

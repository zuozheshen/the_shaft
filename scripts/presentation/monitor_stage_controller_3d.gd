class_name MonitorStageController3D
extends Node3D


signal door_presentation_state_changed(state: int)
signal door_presentation_busy_changed(is_busy: bool)
signal door_presentation_opened
signal door_presentation_closed


const FLOOR_LABEL_FALLBACK: String = "FLOOR ---"
const CURRENT_SLICE_NAME: String = "当前楼层切片"
const CURRENT_PASSENGER_VISUAL_NAME: String = "当前乘客视觉"
const PASSENGER_POSITION_OUTSIDE: StringName = &"outside"
const PASSENGER_POSITION_THRESHOLD: StringName = &"threshold"
const PASSENGER_POSITION_CABIN: StringName = &"cabin"

@export var floor_slice_mount_path: NodePath
@export var initial_floor_slice_path: NodePath
@export var floor_label_path: NodePath
@export var passenger_mount_path: NodePath
@export var initial_passenger_visual_path: NodePath
@export var outside_wait_anchor_path: NodePath
@export var threshold_anchor_path: NodePath
@export var cabin_position_anchor_path: NodePath
@export var door_visual_path: NodePath
@export var initial_passenger_profile: PassengerVisualProfile

var _floor_slice_mount: Node3D
var _current_floor_slice: LayeredFloorSlice25D
var _floor_label: Label3D
var _passenger_mount: Node3D
var _current_passenger_visual: PassengerVisual3D
var _outside_wait_anchor: Marker3D
var _threshold_anchor: Marker3D
var _cabin_position_anchor: Marker3D
var _door_visual: ElevatorDoorVisual3D
var _is_floor_stage_ready: bool = false
var _is_passenger_stage_ready: bool = false
var _is_door_stage_ready: bool = false


func _ready() -> void:
	# 楼层、乘客与门分别初始化；任一模块失败都不会阻断另外两项。
	_initialize_floor_stage()
	_initialize_passenger_stage()
	_initialize_door_stage()


func _initialize_floor_stage() -> void:
	_floor_slice_mount = _get_typed_node(
		floor_slice_mount_path,
		"Node3D",
		"门外楼层挂载点"
	) as Node3D
	var initial_slice_candidate := _get_typed_node(
		initial_floor_slice_path,
		"Node3D",
		"当前楼层切片"
	)
	if initial_slice_candidate is LayeredFloorSlice25D:
		_current_floor_slice = initial_slice_candidate as LayeredFloorSlice25D
	elif initial_slice_candidate != null:
		push_error("监控摄影棚的当前楼层切片必须挂载 LayeredFloorSlice25D 脚本。")
	_floor_label = _get_typed_node(
		floor_label_path,
		"Label3D",
		"门外楼层编号"
	) as Label3D

	if _floor_slice_mount == null \
			or _current_floor_slice == null \
			or _floor_label == null:
		push_error("监控摄影棚控制器初始化不完整，将保留现有场景内容。")
		return
	if _current_floor_slice.get_parent() != _floor_slice_mount:
		push_error("当前楼层切片不在配置的门外楼层挂载点下，将保留现有场景。")
		return
	_is_floor_stage_ready = true


func _initialize_passenger_stage() -> void:
	_passenger_mount = _get_typed_node(
		passenger_mount_path,
		"Node3D",
		"当前乘客挂载点"
	) as Node3D
	var initial_visual_candidate := get_node_or_null(
		initial_passenger_visual_path
	) if not initial_passenger_visual_path.is_empty() else null
	if initial_visual_candidate is PassengerVisual3D:
		_current_passenger_visual = initial_visual_candidate as PassengerVisual3D
	elif initial_visual_candidate == null:
		push_error("监控摄影棚找不到当前乘客视觉：%s" % initial_passenger_visual_path)
	else:
		push_error("监控摄影棚的当前乘客视觉必须挂载 PassengerVisual3D 脚本。")

	_outside_wait_anchor = _get_typed_node(
		outside_wait_anchor_path,
		"Marker3D",
		"门外等待点"
	) as Marker3D
	_threshold_anchor = _get_typed_node(
		threshold_anchor_path,
		"Marker3D",
		"门槛点"
	) as Marker3D
	_cabin_position_anchor = _get_typed_node(
		cabin_position_anchor_path,
		"Marker3D",
		"舱内站位"
	) as Marker3D

	if _passenger_mount == null \
			or _current_passenger_visual == null \
			or _outside_wait_anchor == null \
			or _threshold_anchor == null \
			or _cabin_position_anchor == null:
		push_error("监控摄影棚的乘客表现初始化不完整，将保留现有占位内容。")
		return
	if _current_passenger_visual.get_parent() != _passenger_mount:
		push_error("当前乘客视觉不在配置的乘客挂载点下，将保留现有场景。")
		return

	_is_passenger_stage_ready = true
	if initial_passenger_profile != null:
		_current_passenger_visual.apply_profile(initial_passenger_profile)


func _initialize_door_stage() -> void:
	if door_visual_path.is_empty():
		push_error("监控摄影棚缺少双开门视觉的 NodePath 配置。")
		return

	var candidate := get_node_or_null(door_visual_path)
	if candidate == null:
		push_error("监控摄影棚找不到双开门视觉：%s" % door_visual_path)
		return
	if not candidate is ElevatorDoorVisual3D:
		push_error("监控摄影棚的门节点必须挂载 ElevatorDoorVisual3D 脚本。")
		return

	_door_visual = candidate as ElevatorDoorVisual3D
	if not _door_visual.door_state_changed.is_connected(
			_on_door_state_changed
	):
		_door_visual.door_state_changed.connect(_on_door_state_changed)
	if not _door_visual.door_busy_changed.is_connected(
			_on_door_busy_changed
	):
		_door_visual.door_busy_changed.connect(_on_door_busy_changed)
	if not _door_visual.door_opened.is_connected(_on_door_opened):
		_door_visual.door_opened.connect(_on_door_opened)
	if not _door_visual.door_closed.is_connected(_on_door_closed):
		_door_visual.door_closed.connect(_on_door_closed)

	_is_door_stage_ready = _door_visual.is_ready_for_commands()
	if not _is_door_stage_ready:
		push_error("监控摄影棚的双开门视觉尚未准备完成。")


func get_current_floor_slice() -> LayeredFloorSlice25D:
	return _current_floor_slice


func get_current_passenger_visual() -> PassengerVisual3D:
	return _current_passenger_visual


func get_door_visual() -> ElevatorDoorVisual3D:
	return _door_visual


func request_door_open_presentation() -> bool:
	if not _is_door_stage_ready or _door_visual == null:
		push_warning("监控摄影棚的开门表现不可用。")
		return false
	return _door_visual.request_open()


func request_door_close_presentation() -> bool:
	if not _is_door_stage_ready or _door_visual == null:
		push_warning("监控摄影棚的关门表现不可用。")
		return false
	return _door_visual.request_close()


func is_door_presentation_busy() -> bool:
	return _door_visual != null and _door_visual.is_busy()


func sync_door_presentation(is_open: bool) -> bool:
	if not _is_door_stage_ready or _door_visual == null:
		push_warning("监控摄影棚无法同步不可用的双开门视觉。")
		return false
	if is_open:
		_door_visual.snap_open()
	else:
		_door_visual.snap_closed()
	return true


func set_floor_display_id(floor_id: StringName) -> bool:
	if _floor_label == null:
		push_warning("监控摄影棚缺少楼层编号节点，无法更新显示。")
		return false
	var display_id := String(floor_id)
	_floor_label.text = FLOOR_LABEL_FALLBACK \
			if display_id.is_empty() else "FLOOR %s" % display_id
	return true


func replace_floor_slice(slice_scene: PackedScene) -> LayeredFloorSlice25D:
	if slice_scene == null:
		push_warning("监控摄影棚拒绝空的楼层切片场景。")
		return null
	if _floor_slice_mount == null:
		push_warning("监控摄影棚缺少楼层挂载点，保留当前切片。")
		return null

	# 先验证新实例，再移除旧切片，失败时不会破坏当前画面。
	var candidate := slice_scene.instantiate()
	if not candidate is LayeredFloorSlice25D:
		push_warning("楼层切片场景根节点必须是 LayeredFloorSlice25D，保留当前切片。")
		candidate.free()
		return null

	var new_slice := candidate as LayeredFloorSlice25D
	if _current_floor_slice != null:
		var old_parent := _current_floor_slice.get_parent()
		if old_parent != null:
			old_parent.remove_child(_current_floor_slice)
		_current_floor_slice.queue_free()

	_floor_slice_mount.add_child(new_slice)
	new_slice.name = CURRENT_SLICE_NAME
	new_slice.transform = Transform3D.IDENTITY
	_current_floor_slice = new_slice
	return _current_floor_slice


func apply_passenger_profile(profile: PassengerVisualProfile) -> bool:
	if not _is_passenger_stage_ready or _current_passenger_visual == null:
		push_warning("监控摄影棚的乘客表现尚未准备完成。")
		return false
	return _current_passenger_visual.apply_profile(profile)


func set_passenger_position(position_id: StringName) -> bool:
	if not _is_passenger_stage_ready or _passenger_mount == null:
		push_warning("监控摄影棚缺少可用的乘客挂载点。")
		return false

	var anchor := get_passenger_position_anchor(position_id)
	if anchor == null:
		push_warning("监控摄影棚拒绝无效乘客位置：%s" % position_id)
		return false

	var mount_parent := _passenger_mount.get_parent() as Node3D
	if mount_parent == null:
		push_warning("乘客挂载点的父节点必须是 Node3D，无法对齐位置。")
		return false

	# 将锚点的全局姿态换算到挂载点父节点空间，并单独保留挂载点原有缩放。
	var target_transform := mount_parent.global_transform.affine_inverse() \
			* anchor.global_transform
	var preserved_scale := _passenger_mount.scale
	_passenger_mount.transform = Transform3D(
		target_transform.basis.orthonormalized(),
		target_transform.origin
	)
	_passenger_mount.scale = preserved_scale
	return true


func set_passenger_visible(is_visible: bool) -> bool:
	if not _is_passenger_stage_ready or _current_passenger_visual == null:
		push_warning("监控摄影棚缺少可见的乘客视觉。")
		return false
	_current_passenger_visual.set_passenger_visible(is_visible)
	return true


func replace_passenger_visual(
		passenger_scene: PackedScene
) -> PassengerVisual3D:
	if passenger_scene == null:
		push_warning("监控摄影棚拒绝空的乘客视觉场景。")
		return null
	if _passenger_mount == null:
		push_warning("监控摄影棚缺少乘客挂载点，保留当前乘客。")
		return null

	# 与楼层替换一致，候选实例先通过类型验证，旧乘客才会被移除。
	var candidate := passenger_scene.instantiate()
	if not candidate is PassengerVisual3D:
		push_warning("乘客视觉场景根节点必须是 PassengerVisual3D，保留当前乘客。")
		candidate.free()
		return null

	var new_visual := candidate as PassengerVisual3D
	if _current_passenger_visual != null:
		var old_parent := _current_passenger_visual.get_parent()
		if old_parent != null:
			old_parent.remove_child(_current_passenger_visual)
		_current_passenger_visual.queue_free()

	_passenger_mount.add_child(new_visual)
	new_visual.name = CURRENT_PASSENGER_VISUAL_NAME
	new_visual.transform = Transform3D.IDENTITY
	_current_passenger_visual = new_visual
	_is_passenger_stage_ready = true
	if initial_passenger_profile != null:
		new_visual.apply_profile(initial_passenger_profile)
	return _current_passenger_visual


func get_passenger_position_anchor(position_id: StringName) -> Marker3D:
	match position_id:
		PASSENGER_POSITION_OUTSIDE:
			return _outside_wait_anchor
		PASSENGER_POSITION_THRESHOLD:
			return _threshold_anchor
		PASSENGER_POSITION_CABIN:
			return _cabin_position_anchor
		_:
			return null


func _get_typed_node(
		node_path: NodePath,
		expected_class: StringName,
		display_name: String
) -> Node:
	if node_path.is_empty():
		push_error("监控摄影棚缺少%s的 NodePath 配置。" % display_name)
		return null
	var candidate := get_node_or_null(node_path)
	if candidate == null:
		push_error("监控摄影棚找不到%s：%s" % [display_name, node_path])
		return null
	if not candidate.is_class(expected_class):
		push_error("监控摄影棚的%s应为 %s，实际为 %s。" % [
			display_name,
			expected_class,
			candidate.get_class(),
		])
		return null
	return candidate


func _on_door_state_changed(
		state: ElevatorDoorVisual3D.DoorPresentationState
) -> void:
	door_presentation_state_changed.emit(int(state))


func _on_door_busy_changed(is_busy: bool) -> void:
	door_presentation_busy_changed.emit(is_busy)


func _on_door_opened() -> void:
	door_presentation_opened.emit()


func _on_door_closed() -> void:
	door_presentation_closed.emit()

class_name MonitorStageController3D
extends Node3D


const FLOOR_LABEL_FALLBACK: String = "FLOOR ---"
const CURRENT_SLICE_NAME: String = "当前楼层切片"

@export var floor_slice_mount_path: NodePath
@export var initial_floor_slice_path: NodePath
@export var floor_label_path: NodePath

var _floor_slice_mount: Node3D
var _current_floor_slice: LayeredFloorSlice25D
var _floor_label: Label3D
var _is_stage_ready: bool = false


func _ready() -> void:
	# 摄影棚只管理门外切片挂载点和编号，不介入摄像机或正式流程。
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
	_is_stage_ready = true


func get_current_floor_slice() -> LayeredFloorSlice25D:
	return _current_floor_slice


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

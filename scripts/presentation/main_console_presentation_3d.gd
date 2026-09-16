class_name MainConsolePresentation3D
extends Node


# 所有外形、布局与状态材质都在场景中配置；这里只绑定已有数据。
@export var console_interface_path: NodePath
@export var stage_controller_path: NodePath
@export var monitor_subviewport_path: NodePath
@export var screen_mesh_path: NodePath
@export var cam_01_backlight_path: NodePath
@export var cam_02_backlight_path: NodePath
@export var comm_light_path: NodePath
@export var door_light_path: NodePath
@export var fault_light_path: NodePath
@export var status_label_path: NodePath
@export var door_closed_material: StandardMaterial3D
@export var door_moving_material: StandardMaterial3D
@export var door_open_material: StandardMaterial3D

var _console: ConsoleInterface
var _stage: MonitorStageController3D
var _cam_01: Node3D
var _cam_02: Node3D
var _comm: Node3D
var _door: MeshInstance3D
var _fault: Node3D
var _status: Label3D


func _ready() -> void:
	_bind_presentation.call_deferred()


func _bind_presentation() -> void:
	_console = get_node_or_null(console_interface_path) as ConsoleInterface
	_stage = get_node_or_null(stage_controller_path) as MonitorStageController3D
	var viewport := get_node_or_null(monitor_subviewport_path) as SubViewport
	var screen := get_node_or_null(screen_mesh_path) as MeshInstance3D
	_cam_01 = get_node_or_null(cam_01_backlight_path) as Node3D
	_cam_02 = get_node_or_null(cam_02_backlight_path) as Node3D
	_comm = get_node_or_null(comm_light_path) as Node3D
	_door = get_node_or_null(door_light_path) as MeshInstance3D
	_fault = get_node_or_null(fault_light_path) as Node3D
	_status = get_node_or_null(status_label_path) as Label3D
	if _console == null or _stage == null or viewport == null or screen == null \
			or _cam_01 == null or _cam_02 == null or _comm == null \
			or _door == null or _fault == null or _status == null:
		push_error("主台展示缺少关键导出路径或节点类型错误。")
		return
	var source_material := screen.material_override as StandardMaterial3D
	if source_material == null or door_closed_material == null \
			or door_moving_material == null or door_open_material == null:
		push_error("主台展示缺少 Inspector 中配置的 StandardMaterial3D。")
		return
	# 复制原材质只隔离纹理写入，不覆盖用户调整的基础参数和 Mesh。
	var material := source_material.duplicate() as StandardMaterial3D
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material
	_console.camera_selected.connect(_on_camera_selected)
	_console.mic_enabled_changed.connect(_on_microphone_changed)
	_console.case_phase_display_changed.connect(_on_case_text_changed)
	_stage.door_presentation_state_changed.connect(_on_door_state_changed)
	_on_camera_selected(_console.get_current_camera_index())
	_on_microphone_changed(_console.mic_enabled)
	_on_case_text_changed(_console.get_case_phase_display_text())
	set_fault_active(false)
	var door := _stage.get_door_visual()
	if door == null:
		push_error("主台 DOOR 灯未取得现有门表现，不能推导机构状态。")
		return
	_on_door_state_changed(door.get_door_state())


func _on_camera_selected(index: int) -> void:
	_cam_01.visible = index == 0
	_cam_02.visible = index == 1


func _on_microphone_changed(enabled: bool) -> void:
	_comm.visible = enabled


func _on_case_text_changed(text: String) -> void:
	_status.text = text


func _on_door_state_changed(state: int) -> void:
	match state:
		ElevatorDoorVisual3D.DoorPresentationState.CLOSED:
			_door.material_override = door_closed_material
		ElevatorDoorVisual3D.DoorPresentationState.OPENING, \
				ElevatorDoorVisual3D.DoorPresentationState.CLOSING:
			_door.material_override = door_moving_material
		ElevatorDoorVisual3D.DoorPresentationState.OPEN:
			_door.material_override = door_open_material


func set_fault_active(active: bool) -> void:
	# 仅预留真实故障展示入口；当前业务不调用，普通拒绝和 busy 不接入。
	if is_instance_valid(_fault):
		_fault.visible = active

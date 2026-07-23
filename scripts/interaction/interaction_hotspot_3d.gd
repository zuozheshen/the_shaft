class_name InteractionHotspot3D
extends Area3D


# 热点只描述“玩家碰到了什么”，具体业务动作由操作舱交互控制器统一转发。
@export var action_id: StringName = &""
@export var prompt_text: String = ""
@export var station_id: StringName = &"main_console"
@export var interaction_enabled: bool = true
@export_node_path("Node3D") var hover_visual_path: NodePath

var _is_hovered: bool = false
var _hover_visual: Node3D


func _ready() -> void:
	# 高亮是可选表现层；没有绑定时，热点的检测与动作仍可独立工作。
	if not hover_visual_path.is_empty():
		_hover_visual = get_node_or_null(hover_visual_path) as Node3D
	if _hover_visual != null:
		_hover_visual.visible = false


func _exit_tree() -> void:
	# 热点离开场景时收起高亮，避免重新挂载后保留旧的悬停状态。
	if is_instance_valid(_hover_visual):
		_hover_visual.visible = false
	_is_hovered = false


func can_interact() -> bool:
	return interaction_enabled and not action_id.is_empty()


func get_action_id() -> StringName:
	return action_id


func get_prompt_text() -> String:
	return prompt_text


func get_station_id() -> StringName:
	return station_id


func set_hovered(hovered: bool) -> void:
	# 禁用热点时不能显示“可操作”反馈；相同状态不会重复写 visible。
	var should_show_hover: bool = hovered and interaction_enabled
	if _is_hovered == should_show_hover:
		return
	_is_hovered = should_show_hover
	if is_instance_valid(_hover_visual):
		_hover_visual.visible = _is_hovered

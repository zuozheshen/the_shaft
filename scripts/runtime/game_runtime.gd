class_name GameRuntime
extends Node


const RUNTIME_GROUP: StringName = &"the_shaft_game_runtime"

@onready var demo_flow_manager: DemoFlowManager = $演示流程管理器 as DemoFlowManager


func _ready() -> void:
	# 一个主场景只能存在一份正式运行层，避免派单和电梯状态各自推进两次。
	add_to_group(RUNTIME_GROUP)
	var runtime_nodes := get_tree().get_nodes_in_group(RUNTIME_GROUP)
	if runtime_nodes.size() > 1:
		push_error("检测到重复的游戏运行层；当前场景只能实例化一个“游戏运行层”。")
	if demo_flow_manager == null:
		push_error("游戏运行层缺少关键节点：演示流程管理器。")


func get_demo_flow_manager() -> DemoFlowManager:
	return demo_flow_manager

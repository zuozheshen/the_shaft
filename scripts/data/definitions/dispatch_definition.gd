class_name DispatchDefinition
extends Resource


## 一次派单的静态模板。运行期间的阶段和玩家发现内容不写回此资源。
@export var dispatch_id: StringName
@export var passenger_id: StringName
@export var pickup_floor_id: StringName
@export var default_destination_floor_id: StringName
@export var dialogue_path: String

## 当前派单的固定接乘表现。它们随派单变化，但不是运行时状态。
@export var pickup_data: Dictionary = {}
@export var camera_feeds: Dictionary = {}
@export var front_phase_texts: Dictionary = {}

## 派单内嵌楼层关系；它们不需要单独注册到 ContentRegistry。
@export var floor_relations: Array[DispatchFloorRelation] = []


func get_floor_relation(raw_floor_id: String) -> DispatchFloorRelation:
	var floor_id: StringName = StringName(raw_floor_id.strip_edges())

	for relation: DispatchFloorRelation in floor_relations:
		if relation != null and relation.floor_id == floor_id:
			return relation

	return null

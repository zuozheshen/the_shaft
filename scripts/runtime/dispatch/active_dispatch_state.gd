class_name ActiveDispatchState
extends RefCounted


## 当前派单的纯运行时状态。这里只保存本轮会变化的数据，不持有静态 Resource。
var dispatch_id: StringName = &""
var current_phase: StringName = &"WAITING_FOR_PICKUP"

var validated_floor_id: StringName = &""
var selected_target_floor_id: StringName = &""

var passenger_inside: bool = false
var arrival_triggered: bool = false
var door_greeting_done: bool = false
var cabin_door_closed_after_boarding: bool = false
var dropoff_feedback_finished: bool = false

var _recommended_floor_ids: Array[StringName] = []


static func create_from_definition(dispatch: DispatchDefinition) -> ActiveDispatchState:
	var state := ActiveDispatchState.new()
	if dispatch == null:
		return state

	state.dispatch_id = dispatch.dispatch_id
	for relation: DispatchFloorRelation in dispatch.floor_relations:
		if relation == null:
			continue
		if relation.initially_recommended:
			state.add_recommended_floor(relation.floor_id)

	return state


func add_recommended_floor(floor_id: StringName) -> bool:
	var normalized_id := _normalize_floor_id(floor_id)
	if normalized_id == &"" or normalized_id in _recommended_floor_ids:
		return false
	_recommended_floor_ids.append(normalized_id)
	return true


func get_recommended_floor_ids() -> Array[StringName]:
	return _recommended_floor_ids.duplicate()


func _normalize_floor_id(value: StringName) -> StringName:
	# 只清理空格，不转换为整数，确保 004 始终保留前导零。
	return StringName(String(value).strip_edges())

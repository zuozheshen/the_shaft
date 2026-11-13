class_name DispatchResult
extends RefCounted


## 派单完成后的最小运行时结果，后续后果系统可以在此基础上扩展。
var dispatch_id: StringName
var passenger_id: StringName
## 兼容字段：以乘客实际离舱楼层为准。
var destination_floor_id: StringName
var requested_floor_id: StringName
var travel_legs: Array[Dictionary] = []
var acquired_information: Array[Dictionary] = []
var completion_order: int


static func create(
		source_dispatch_id: StringName,
		source_passenger_id: StringName,
		source_destination_floor_id: StringName,
		source_completion_order: int
) -> DispatchResult:
	var result := DispatchResult.new()
	result.dispatch_id = source_dispatch_id
	result.passenger_id = source_passenger_id
	result.destination_floor_id = source_destination_floor_id
	result.completion_order = source_completion_order
	return result

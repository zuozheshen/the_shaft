class_name FlowCommandResult
extends RefCounted


# succeeded 表示命令主要目标是否完成；effects 只描述本次调用中已经发生的变化。
# 失败结果通常没有 effects，但若失败过程中确实完成清理，也可以携带清理类 effect。
const DOOR_OPENED: StringName = &"DOOR_OPENED"
const DOOR_CLOSED: StringName = &"DOOR_CLOSED"
const PASSENGER_BOARDED: StringName = &"PASSENGER_BOARDED"
const ONBOARD_DIALOGUE_AVAILABLE: StringName = &"ONBOARD_DIALOGUE_AVAILABLE"
const DROPOFF_FEEDBACK_REQUESTED: StringName = &"DROPOFF_FEEDBACK_REQUESTED"
const DISPATCH_COMPLETED: StringName = &"DISPATCH_COMPLETED"
const NEXT_DISPATCH_STARTED: StringName = &"NEXT_DISPATCH_STARTED"
const SHIFT_COMPLETED: StringName = &"SHIFT_COMPLETED"
const DESTINATION_VALIDATED: StringName = &"DESTINATION_VALIDATED"
const VALIDATION_CLEARED: StringName = &"VALIDATION_CLEARED"
const MOVEMENT_STARTED: StringName = &"MOVEMENT_STARTED"
const DISPATCH_TARGET_SELECTED: StringName = &"DISPATCH_TARGET_SELECTED"
const DOOR_GREETING_COMPLETED: StringName = &"DOOR_GREETING_COMPLETED"
const DROPOFF_FEEDBACK_FINISHED: StringName = &"DROPOFF_FEEDBACK_FINISHED"

var succeeded: bool = false
var code: StringName = &""
var message: String = ""
var previous_phase: String = ""
var current_phase: String = ""
var floor_id: String = ""
var effects: Array[StringName] = []


static func success(
		result_code: StringName = &"OK",
		result_message: String = "",
		previous: String = "",
		current: String = "",
		result_floor_id: String = "",
		result_effects: Array[StringName] = []
):
	return _create(
		true,
		result_code,
		result_message,
		previous,
		current,
		result_floor_id,
		result_effects
	)


static func failure(
		result_code: StringName,
		result_message: String,
		previous: String = "",
		current: String = "",
		result_floor_id: String = "",
		result_effects: Array[StringName] = []
):
	return _create(
		false,
		result_code,
		result_message,
		previous,
		current,
		result_floor_id,
		result_effects
	)


func has_effect(effect_id: StringName) -> bool:
	return effect_id in effects


func get_effects() -> Array[StringName]:
	return effects.duplicate()


static func _create(
		was_successful: bool,
		result_code: StringName,
		result_message: String,
		previous: String,
		current: String,
		result_floor_id: String,
		result_effects: Array[StringName]
):
	var result = new()
	result.succeeded = was_successful
	result.code = result_code
	result.message = result_message
	result.previous_phase = previous
	result.current_phase = current
	result.floor_id = result_floor_id
	for effect_id: StringName in result_effects:
		if effect_id not in result.effects:
			result.effects.append(effect_id)
	return result

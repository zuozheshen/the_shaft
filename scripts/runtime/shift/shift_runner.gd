class_name ShiftRunner
extends RefCounted


var _active_shift: ShiftDefinition
var _current_dispatch_index: int = -1
var _completed_dispatch_results: Array[DispatchResult] = []
var _shift_is_finished: bool = false


func start_shift(shift: ShiftDefinition) -> bool:
	_active_shift = shift
	_current_dispatch_index = -1
	_completed_dispatch_results.clear()
	_shift_is_finished = false
	return _active_shift != null and not _active_shift.dispatch_ids.is_empty()


func get_next_dispatch_id() -> StringName:
	if _active_shift == null or _shift_is_finished:
		return &""
	if _current_dispatch_index + 1 >= _active_shift.dispatch_ids.size():
		return &""
	_current_dispatch_index += 1
	return _active_shift.dispatch_ids[_current_dispatch_index]


func record_completed_result(result: DispatchResult) -> bool:
	if result == null:
		return false
	_completed_dispatch_results.append(result)
	return true


func get_completed_results() -> Array[DispatchResult]:
	return _completed_dispatch_results.duplicate()


func get_completed_count() -> int:
	return _completed_dispatch_results.size()


func finish_shift() -> bool:
	if _shift_is_finished:
		return false
	_shift_is_finished = true
	return true


func is_finished() -> bool:
	return _shift_is_finished

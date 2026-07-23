class_name ElevatorRuntimeState
extends Node


signal movement_completed(arrived_floor: String)


## 电梯状态只描述位置、移动和基础门控，不理解派单或楼层业务含义。
enum MovementState {
	IDLE,
	MOVING,
	ARRIVED,
}

var current_floor: String = ""
var target_floor: String = ""
var movement_state: MovementState = MovementState.IDLE
var cabin_door_is_open: bool = false
var movement_timer: Timer


func initialize(starting_floor: String, movement_duration_seconds: float) -> void:
	current_floor = starting_floor.strip_edges()
	target_floor = ""
	movement_state = MovementState.IDLE
	cabin_door_is_open = false

	# 测试或场景重复初始化时复用同一个 Timer，避免一次移动被完成多次。
	if movement_timer == null:
		movement_timer = Timer.new()
		movement_timer.name = "MovementTimer"
		movement_timer.one_shot = true
		movement_timer.timeout.connect(_complete_movement)
		add_child(movement_timer)
	else:
		movement_timer.stop()
	movement_timer.wait_time = movement_duration_seconds


func request_movement(destination: String) -> bool:
	var normalized_destination: String = destination.strip_edges()
	if normalized_destination.is_empty():
		return false
	if is_moving() or cabin_door_is_open or movement_timer == null:
		return false

	target_floor = normalized_destination
	movement_state = MovementState.MOVING
	movement_timer.start()
	return true


func clear_target_floor() -> void:
	target_floor = ""


func get_movement_state_text() -> String:
	var door_text: String = "舱门开启" if cabin_door_is_open else "舱门关闭"
	match movement_state:
		MovementState.MOVING:
			return "运行中，舱门关闭"
		MovementState.ARRIVED:
			return "已停靠，%s" % door_text
		_:
			return "待命，%s" % door_text


func is_moving() -> bool:
	return movement_state == MovementState.MOVING


func is_cabin_door_open() -> bool:
	return cabin_door_is_open


func set_cabin_door_open(is_open: bool) -> bool:
	if cabin_door_is_open == is_open:
		return false
	cabin_door_is_open = is_open
	return true


func _complete_movement() -> void:
	if target_floor.is_empty():
		return
	current_floor = target_floor
	target_floor = ""
	movement_state = MovementState.ARRIVED
	cabin_door_is_open = false
	movement_completed.emit(current_floor)

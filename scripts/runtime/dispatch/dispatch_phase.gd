class_name DispatchPhase
extends RefCounted


## 派单阶段只描述当前流程位置；具体业务动作仍由现有流程管理器和界面负责。
const SHIFT_IDLE: String = "SHIFT_IDLE"
const WAITING_FOR_PICKUP: String = "WAITING_FOR_PICKUP"
const ARRIVED_AT_PICKUP: String = "ARRIVED_AT_PICKUP"
const DOOR_GREETING_DONE: String = "DOOR_GREETING_DONE"
const BOARDING_WAIT_DOOR_CLOSE: String = "BOARDING_WAIT_DOOR_CLOSE"
const PASSENGER_ONBOARD: String = "PASSENGER_ONBOARD"
const ARRIVED_AT_DESTINATION: String = "ARRIVED_AT_DESTINATION"
const DROPOFF_FEEDBACK: String = "DROPOFF_FEEDBACK"
const DROPOFF_WAIT_DOOR_CLOSE: String = "DROPOFF_WAIT_DOOR_CLOSE"

const _ALL_PHASES: Array[String] = [
	SHIFT_IDLE,
	WAITING_FOR_PICKUP,
	ARRIVED_AT_PICKUP,
	DOOR_GREETING_DONE,
	BOARDING_WAIT_DOOR_CLOSE,
	PASSENGER_ONBOARD,
	ARRIVED_AT_DESTINATION,
	DROPOFF_FEEDBACK,
	DROPOFF_WAIT_DOOR_CLOSE,
]

const _TRANSITIONS: Dictionary = {
	WAITING_FOR_PICKUP: [
		ARRIVED_AT_PICKUP,
		DOOR_GREETING_DONE,
	],
	ARRIVED_AT_PICKUP: [
		WAITING_FOR_PICKUP,
		DOOR_GREETING_DONE,
		BOARDING_WAIT_DOOR_CLOSE,
	],
	DOOR_GREETING_DONE: [
		WAITING_FOR_PICKUP,
		BOARDING_WAIT_DOOR_CLOSE,
	],
	BOARDING_WAIT_DOOR_CLOSE: [
		PASSENGER_ONBOARD,
	],
	PASSENGER_ONBOARD: [
		ARRIVED_AT_DESTINATION,
	],
	ARRIVED_AT_DESTINATION: [
		DROPOFF_FEEDBACK,
	],
	DROPOFF_FEEDBACK: [
		DROPOFF_WAIT_DOOR_CLOSE,
	],
}


static func get_all() -> Array[String]:
	return _ALL_PHASES.duplicate()


static func is_valid(phase: String) -> bool:
	return phase in _ALL_PHASES


static func can_transition(from_phase: String, to_phase: String) -> bool:
	# 重复设置有效阶段是幂等成功，不代表产生一次新的状态变化。
	if from_phase == to_phase:
		return is_valid(from_phase)
	if not is_valid(from_phase) or not is_valid(to_phase):
		return false
	var allowed_targets: Array = _TRANSITIONS.get(from_phase, [])
	return to_phase in allowed_targets

extends Node
class_name DemoFlowManager


# 状态变化后通知界面等监听者，避免其他节点反复查询流程状态。
signal state_changed(new_state_name: String)


const MAX_FRONT_HISTORY_LINES: int = 20


# DemoState 按演示流程顺序排列，用一个简单状态机串起完整体验。
enum DemoState {
	BOOT,
	WAITING_FOR_DISPATCH,
	PASSENGER_BOARDING,
	ROUTE_SELECTION,
	ARRIVAL,
	LOGGING,
	CASE_COMPLETE,
}


var current_state: DemoState = DemoState.BOOT

# 三份状态是 FRONT 到 LEFT 的临时桥接，后续会由正式 PassengerCase 替换。
# 对话历史只用于 TRANSCRIPT，操作历史只用于 SYSTEM LOG，提示只用于 STATUS。
var front_dialogue_history: Array[String] = []
var front_operation_history: Array[String] = []
var current_building_status_hint: String = "暂无前台通话。"


func _ready() -> void:
	print_current_state()


func _unhandled_input(event: InputEvent) -> void:
	# ui_accept 作为早期原型的快捷推进方式，已被界面处理的输入不会走到这里。
	if event.is_action_pressed("ui_accept"):
		advance_state()
		get_viewport().set_input_as_handled()


func advance_state() -> void:
	# 每次只推进一个阶段，让按钮和快捷键共用同一套状态转换逻辑。
	match current_state:
		DemoState.BOOT:
			current_state = DemoState.WAITING_FOR_DISPATCH
		DemoState.WAITING_FOR_DISPATCH:
			current_state = DemoState.PASSENGER_BOARDING
		DemoState.PASSENGER_BOARDING:
			current_state = DemoState.ROUTE_SELECTION
		DemoState.ROUTE_SELECTION:
			current_state = DemoState.ARRIVAL
		DemoState.ARRIVAL:
			current_state = DemoState.LOGGING
		DemoState.LOGGING:
			current_state = DemoState.CASE_COMPLETE
		DemoState.CASE_COMPLETE:
			# 完成状态是流程终点，继续操作不会重复发送状态变化。
			return

	print_current_state()
	state_changed.emit(get_current_state_name())


func get_current_state_name() -> String:
	# 界面和调试输出使用可读名称，不需要了解枚举对应的整数值。
	return str(DemoState.keys()[current_state])


func print_current_state() -> void:
	print("Current demo state: ", get_current_state_name())


func add_front_dialogue(
		operator_text: String,
		passenger_text: String,
		status_hint: String
) -> void:
	# 一次选择写入成对台词，并把该选项的建筑判断交给 LEFT STATUS。
	front_dialogue_history.append("操作员：%s" % operator_text)
	var formatted_passenger_text: String = passenger_text
	if not formatted_passenger_text.begins_with("乘客："):
		formatted_passenger_text = "乘客：%s" % formatted_passenger_text
	front_dialogue_history.append(formatted_passenger_text)
	current_building_status_hint = status_hint

	# 每次移除一整组问答，避免 20 行上限把操作员与乘客台词拆开。
	while front_dialogue_history.size() > MAX_FRONT_HISTORY_LINES:
		front_dialogue_history.pop_front()
		front_dialogue_history.pop_front()


func add_front_operation(operation_text: String) -> void:
	# 玩家操作单独进入系统日志缓存，不混入完整对话内容。
	front_operation_history.append(operation_text)
	if front_operation_history.size() > MAX_FRONT_HISTORY_LINES:
		front_operation_history.pop_front()


func get_front_dialogue_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享对话缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_dialogue_history)
	return history_copy


func get_front_operation_history() -> Array[String]:
	# 返回副本，避免 LEFT 界面意外改写共享操作缓存。
	var history_copy: Array[String] = []
	history_copy.assign(front_operation_history)
	return history_copy


func get_current_building_status_hint() -> String:
	return current_building_status_hint

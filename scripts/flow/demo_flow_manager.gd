extends Node
class_name DemoFlowManager


# 状态变化后通知界面等监听者，避免其他节点反复查询流程状态。
signal state_changed(new_state_name: String)


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

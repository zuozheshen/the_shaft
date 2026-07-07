extends Node


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
	if event.is_action_pressed("ui_accept"):
		advance_state()
		get_viewport().set_input_as_handled()


func advance_state() -> void:
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
			return

	print_current_state()


func print_current_state() -> void:
	print("Current demo state: ", DemoState.keys()[current_state])

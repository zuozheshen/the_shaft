extends Control
class_name ConsoleInterface


signal return_requested


@onready var console_name_label: Label = %ConsoleNameLabel
@onready var console_description_label: Label = %ConsoleDescriptionLabel
@onready var return_button: Button = %ReturnButton


func _ready() -> void:
	return_button.pressed.connect(_request_return)


func show_console(console_name: String, console_description: String) -> void:
	console_name_label.text = console_name
	console_description_label.text = console_description
	show()
	return_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel") or _is_key_pressed(event, KEY_S):
		_request_return()
		get_viewport().set_input_as_handled()


func _request_return() -> void:
	return_requested.emit()


func _is_key_pressed(event: InputEvent, key: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == key or event.physical_keycode == key)

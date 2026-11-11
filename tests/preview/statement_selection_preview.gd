extends Node

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Fixture := preload("res://tests/fixtures/runtime/test_statement_selection.gd")


func _ready() -> void:
	Content.install(ContentRegistry)
	var main := Fixture.prepare()
	add_child(main)
	await get_tree().process_frame
	var terminal := Fixture.open_preview(main)
	await get_tree().create_timer(terminal.slide_duration + 0.1).timeout
	terminal.workspace.open_document(Fixture.ref("application"))
	print("STATEMENT SELECTION PREVIEW READY")


func _exit_tree() -> void:
	Content.restore(ContentRegistry)

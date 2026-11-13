extends Node

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Fixture := preload("res://tests/fixtures/runtime/test_call_excerpt_fixture.gd")


func _ready() -> void:
	Content.install(ContentRegistry)
	var main := Fixture.prepare()
	var dispatch := ContentRegistry.get_dispatch(Fixture.SECOND) as DispatchDefinition
	dispatch.dialogue_events["dispatch_started"] = "monitor_long"
	dispatch.dialogue_events["arrived_at_pickup"] = "statement"
	add_child(main)
	await main.get_node("值守入口").start_duty()
	await get_tree().process_frame
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.start_dispatch(Fixture.SECOND)
	print("MONITOR DIALOGUE PREVIEW READY")


func _exit_tree() -> void:
	Content.restore(ContentRegistry)

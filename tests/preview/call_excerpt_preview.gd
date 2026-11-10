extends Node

const Content := preload("res://tests/fixtures/runtime/test_content.gd")
const Fixture := preload("res://tests/fixtures/runtime/test_call_excerpt_fixture.gd")


func _ready() -> void:
	Content.install(ContentRegistry)
	var main := Fixture.prepare()
	add_child(main)
	await get_tree().process_frame
	var manager := main.get_node("游戏运行层/演示流程管理器") as DemoFlowManager
	manager.start_dispatch(Fixture.SECOND)
	print("CALL EXCERPT PREVIEW READY：等待监视器末页绘制，按实体摘录键，再按 W 查看收件箱")


func _exit_tree() -> void:
	Content.restore(ContentRegistry)

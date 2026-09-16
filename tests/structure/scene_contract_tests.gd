extends RefCounted
## 反例只改未入树的临时实例，不写正式场景，也不复制业务数据。

const Validator := preload("res://tests/structure/scene_contract_validator.gd")
var failures: Array[String] = []
var checks: int = 0


func run() -> Array[String]:
	var packed := load(Validator.MAIN_SCENE) as PackedScene
	_expect("missing scene instance", _scene_errors(null).contains("scene instance"))
	var instance := packed.instantiate()
	var flow := instance.get_node("游戏运行层/演示流程管理器")
	flow.get_parent().remove_child(flow)
	flow.free()
	var diagnostics := _scene_errors(instance)
	_expect("missing manager includes scene and node", diagnostics.contains(Validator.MAIN_SCENE)
		and diagnostics.contains("游戏运行层/演示流程管理器"))
	instance.free()

	instance = packed.instantiate()
	var duplicate := load("res://scenes/runtime/game_runtime.tscn").instantiate() as Node
	duplicate.name = "另一运行层"
	instance.add_child(duplicate)
	_expect("duplicate core manager", _scene_errors(instance).contains("one core manager"))
	instance.free()

	instance = packed.instantiate()
	var connector := instance.get_node("运行层连接器")
	connector.set("game_runtime_path", NodePath("../不存在的运行层"))
	_expect("broken exported path", _scene_errors(instance).contains("不存在的运行层 [game_runtime_path]"))
	instance.free()

	instance = packed.instantiate()
	connector = instance.get_node("运行层连接器")
	connector.set("game_runtime_path", NodePath(""))
	_expect("empty exported path", _scene_errors(instance).contains("non-empty NodePath"))
	instance.free()

	instance = packed.instantiate()
	var runtime := instance.get_node("游戏运行层")
	runtime.set_script(null)
	_expect("missing script attachment", _scene_errors(instance).contains("no script"))
	instance.free()

	instance = packed.instantiate()
	var camera := instance.get_node("三维操作舱/监控渲染系统/监控视口/监控摄像机")
	var parent := camera.get_parent()
	parent.remove_child(camera)
	camera.free()
	var wrong_camera := Node3D.new()
	wrong_camera.name = "监控摄像机"
	parent.add_child(wrong_camera)
	_expect("wrong camera type", _scene_errors(instance).contains("expected: Camera3D | actual: Node3D"))
	instance.free()

	instance = packed.instantiate()
	var ui := instance.find_child("ConsoleInterface", true, false)
	var button := ui.get_node("%OpenDoorButton")
	button.unique_name_in_owner = false
	_expect("lost unique name used by code", _scene_errors(instance).contains("%OpenDoorButton"))
	instance.free()

	instance = packed.instantiate()
	var stage := instance.find_child("监控测试摄影棚", true, false)
	var visual := stage.get_node(stage.get("initial_passenger_visual_path"))
	visual.owner = null
	visual.reparent(stage.get_node("乘客视觉区域"), false)
	stage.set("initial_passenger_visual_path", stage.get_path_to(visual))
	_expect("passenger must remain below its movement mount", _scene_errors(instance).contains("different parent"))
	instance.free()

	# 正常调整机位路径、布局容器或装饰，不应被验证器误判为结构损坏。
	for invalid_path in [NodePath(""), NodePath("缺失灯光"), NodePath("门外楼层区域")]:
		instance = packed.instantiate()
		stage = instance.find_child("监控测试摄影棚", true, false)
		stage.set("floor_light_path", invalid_path)
		_expect("missing or invalid floor light " + str(invalid_path),
				_scene_errors(instance).contains("floor_light_path"))
		instance.free()

	instance = packed.instantiate()
	stage = instance.find_child("监控测试摄影棚", true, false)
	var floor_light := stage.get_node(stage.get("floor_light_path"))
	floor_light.name = "重新配置的门外灯"
	stage.set("floor_light_path", stage.get_path_to(floor_light))
	_expect("floor light path permits reconfiguration", _scene_errors(instance).is_empty())
	instance.free()

	instance = packed.instantiate()
	var monitor := instance.find_child("监控渲染系统", true, false)
	camera = monitor.get_node(monitor.get("monitor_camera_path"))
	camera.name = "重命名机位"
	monitor.set("monitor_camera_path", monitor.get_path_to(camera))
	var cabin := instance.get_node("三维操作舱") as Node3D
	cabin.position = Vector3(3, 4, 5)
	var decoration := Node3D.new()
	decoration.name = "自由装饰"
	cabin.add_child(decoration)
	_expect("reconfigured exported path and decoration allowed", _scene_errors(instance).is_empty())
	instance.free()

	instance = packed.instantiate()
	var router := instance.find_child("操作台界面层", true, false)
	var comm_container := router.find_child("全局通讯容器", true, false)
	var wrapper := Control.new()
	wrapper.name = "可调整布局"
	router.get_node("操作台界面根").add_child(wrapper)
	# 真正移动唯一主台实例，并同步全部显式接线；不只移动空的兼容容器。
	comm_container.owner = null
	comm_container.reparent(wrapper, false)
	var interaction := instance.find_child("交互控制器", true, false)
	ui = router.find_child("ConsoleInterface", true, false)
	interaction.set("console_interface_path", interaction.get_path_to(ui))
	var binding := instance.find_child("主台展示绑定", true, false)
	binding.set("console_interface_path", binding.get_path_to(ui))
	var left_controller := instance.find_child("左操作台定位", true, false)
	left_controller.set("comm_view_path", left_controller.get_path_to(ui.get_node("FloatingCommUI")))
	_expect("router permits layout wrapper with updated references", _scene_errors(instance).is_empty())
	instance.free()

	# 新设备引用仍允许用户重配；缺失关键视图/屏幕应给出明确诊断。
	instance = packed.instantiate()
	var presentation := instance.find_child("主台展示绑定", true, false)
	presentation.set("screen_mesh_path", NodePath("不存在的屏幕"))
	_expect("missing main screen", _scene_errors(instance).contains("screen_mesh_path"))
	instance.free()

	instance = packed.instantiate()
	var left_screen := instance.find_child("左操作台定位", true, false)
	left_screen.set("comm_view_path", NodePath(""))
	_expect("missing COMM input guard", _scene_errors(instance).contains("comm_view_path"))
	instance.free()

	instance = packed.instantiate()
	presentation = instance.find_child("主台展示绑定", true, false)
	var screen := presentation.get_node(presentation.get("screen_mesh_path")) as MeshInstance3D
	screen.name = "手调后的主屏"
	screen.position += Vector3(0.1, 0.2, 0.3)
	screen.mesh = screen.mesh.duplicate()
	(screen.mesh as QuadMesh).size *= 0.9
	presentation.set("screen_mesh_path", presentation.get_path_to(screen))
	_expect("main screen permits Inspector edits and exported path", _scene_errors(instance).is_empty())
	instance.free()

	var validator := Validator.new()
	var empty_node := Node.new()
	validator.validate_api(empty_node, ["get_demo_flow_manager"], ["dispatch_started"], "fixture", "接口")
	_expect("missing public method", str(validator.errors).contains("method:get_demo_flow_manager"))
	_expect("missing public signal", str(validator.errors).contains("signal:dispatch_started"))
	empty_node.free()

	var config := ConfigFile.new()
	config.load("res://project.godot")
	config.set_value("application", "run/main_scene", "res://wrong_entry.tscn")
	validator = Validator.new()
	validator.validate_configuration(config)
	_expect("wrong project entry", str(validator.errors).contains("application/run/main_scene"))
	config.load("res://project.godot")
	config.set_value("autoload", "ExtraContentRegistry", "*" + Validator.AUTOLOADS.ContentRegistry)
	validator = Validator.new()
	validator.validate_configuration(config)
	_expect("duplicate autoload under another name", str(validator.errors).contains("one script instance"))
	config.load("res://project.godot")
	config.set_value("autoload", "ContentRegistry", "*res://wrong.gd")
	validator = Validator.new()
	validator.validate_configuration(config)
	_expect("wrong autoload script", str(validator.errors).contains("autoload/ContentRegistry"))
	config.load("res://project.godot")
	config.set_value("autoload", "ExtraFlow", "*" + Validator.SCRIPTS.DemoFlowManager)
	validator = Validator.new()
	validator.validate_configuration(config)
	_expect("core manager cannot also be autoload", str(validator.errors).contains("core managers owned by main scene"))
	config.load("res://project.godot")
	config.erase_section_key("input", "turn_left")
	validator = Validator.new()
	validator.validate_configuration(config)
	_expect("required input action", str(validator.errors).contains("input/turn_left"))
	_expect("unknown UID diagnosed", validator.resolve_resource_path("uid://bbbbbbbbbbbbb").begins_with("unresolved:"))
	return failures.duplicate()


func _scene_errors(instance: Node) -> String:
	var validator := Validator.new()
	validator.validate_scene(instance, Validator.MAIN_SCENE)
	return "\n".join(validator.errors)


func _expect(label: String, passed: bool) -> void:
	checks += 1
	if passed:
		print("PASS | contract self-test | " + label)
	else:
		failures.append("contract self-test | " + label)

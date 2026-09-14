extends Node
## 独立的小型结构检查宿主；既有 flow runner 的调度与断言保持不变。

const Validator := preload("res://tests/structure/scene_contract_validator.gd")
const ContractTests := preload("res://tests/structure/scene_contract_tests.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	# 命令行反例用于检验真实进程退出码，不修改磁盘文件或执行业务。
	if "--negative-control" in OS.get_cmdline_user_args():
		var instance := load(Validator.MAIN_SCENE).instantiate() as Node
		instance.get_node("游戏运行层/演示流程管理器").free()
		var validator := Validator.new()
		validator.validate_scene(instance, Validator.MAIN_SCENE)
		errors.assign(validator.errors)
		instance.free()
		_finish(errors)
		return

	# 显式加载所有源脚本；不只依赖编辑器导入的 exit code。
	var scripts: Array[String] = []
	for directory: String in ["res://scripts", "res://tests", "res://addons"]:
		_collect_scripts(directory, scripts, errors)
	for path: String in scripts:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			errors.append(path + " | GDScript | cannot load/compile")
	print("SCRIPTS CHECKED | %d" % scripts.size())
	var validator := Validator.new()
	errors.append_array(validator.validate_project())
	print("SCENES CHECKED | %d" % Validator.SCENES.size())
	var self_tests := ContractTests.new()
	errors.append_array(self_tests.run())
	print("CONTRACT SELF-TESTS | %d" % self_tests.checks)
	_finish(errors)


func _collect_scripts(directory: String, paths: Array[String], errors: Array[String]) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		errors.append(directory + " | cannot read script directory")
		return
	for filename: String in access.get_files():
		if filename.ends_with(".gd"):
			paths.append(directory.path_join(filename))
	for child: String in access.get_directories():
		if not child.begins_with(".") and not access.is_link(child):
			_collect_scripts(directory.path_join(child), paths, errors)


func _finish(errors: Array[String]) -> void:
	for error: String in errors:
		printerr("FAIL | " + error)
	if errors.is_empty():
		print("PROJECT CHECKS PASS")
	else:
		print("PROJECT CHECKS FAILED | %d" % errors.size())
	get_tree().quit(0 if errors.is_empty() else 1)

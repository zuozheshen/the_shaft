extends SceneTree
## Pass B 只读门：从正式 main_3d 检查几何清单；Pass C 纹理/CLI 检查尚未实现。

const MAIN_PATH := "res://scenes/main/main_3d.tscn"
const MANIFEST_PATH := "res://art_source/floors/floor_slice_layout_v1.json"
const TOLERANCE := 0.00001

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var print_layout := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--print-layout":
			print_layout = true
		elif argument != "--check-layout":
			printerr("Unsupported Pass B argument: " + argument)
			quit(2)
			return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest is Dictionary:
		printerr("LAYOUT CHECK FAIL | manifest is not a JSON object")
		quit(1)
		return

	_check("schema", manifest.get("schema_version"), 1)
	_check("layer count", manifest.get("layers", []).size(), 7)
	for source_path in manifest.get("provenance", {}).get("sources", {}):
		# 仓库 LF 为 hash 依据，允许 Windows checkout 使用 CRLF。
		var source := FileAccess.get_file_as_string("res://" + source_path).replace("\r\n", "\n")
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(source.to_utf8_buffer())
		_check("source hash " + source_path, hasher.finish().hex_encode(),
				manifest.provenance.sources[source_path])

	# --script 在 autoload 注册前解析入口脚本；正式场景延后到运行期加载。
	await process_frame
	var main_scene := load(MAIN_PATH) as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var cabin := main.get_node("三维操作舱")
	var stage := cabin.get_node("监控摄影棚定位/监控测试摄影棚") as Node3D
	var viewport := cabin.get_node("监控渲染系统/监控视口") as SubViewport
	var camera := viewport.get_node("监控摄像机") as Camera3D
	_check("stage world transform", _transform(stage.global_transform),
			manifest.stage_world_transform)
	_check("viewport", [viewport.size.x, viewport.size.y], manifest.viewport)
	for property_name in ["fov", "keep_aspect", "near", "far", "cull_mask"]:
		_check("camera " + property_name, camera.get(property_name), manifest.camera[property_name])
	for anchor in manifest.camera.anchors:
		_check_node_transform(stage, anchor)
	for marker in manifest.passenger.markers:
		_check_node_transform(stage, marker)

	var report_layers: Array[Dictionary] = []
	var seen_ids: Array[String] = []
	for layer in manifest.layers:
		var id := String(layer.id)
		_check("unique layer " + id, id in seen_ids, false)
		seen_ids.append(id)
		var node := stage.get_node_or_null(NodePath(layer.node_path)) as MeshInstance3D
		if node == null or not node.mesh is QuadMesh:
			_failures.append("Missing QuadMesh: " + layer.node_path)
			continue
		var quad := node.mesh as QuadMesh
		_check(id + " size", [quad.size.x, quad.size.y], layer.quad_size_m)
		_check(id + " local transform", _transform(node.transform), layer.local_transform)
		_check_node_transform(stage, layer)
		_check(id + " layers", node.layers, layer.render_layers)
		_check(id + " scale", _vector(node.scale), layer.scale)
		report_layers.append({"id": id, "size": [quad.size.x, quad.size.y],
				"local_transform": _transform(node.transform),
				"world_transform": _transform(node.global_transform)})
	var fixed_boxes := _fixed_boxes(stage)
	_check("fixed box count", fixed_boxes.size(), manifest.fixed_occluders.size())
	for occluder in manifest.fixed_occluders:
		var node := stage.get_node_or_null(NodePath(occluder.node_path)) as GeometryInstance3D
		if node == null:
			_failures.append("Missing fixed occluder: " + occluder.node_path)
			continue
		var size := Vector3.ZERO
		if node is CSGBox3D:
			size = node.size
		elif node is MeshInstance3D and node.mesh is BoxMesh:
			size = node.mesh.size
		_check(occluder.node_path + " size", _vector(size), occluder.size)
		_check(occluder.node_path + " visible", node.is_visible_in_tree(), occluder.visible)
		_check(occluder.node_path + " layers", node.layers, occluder.render_layers)
		_check_node_transform(stage, occluder)

	var label := stage.get_node("门外楼层区域/门外楼层编号") as Label3D
	for property_name in ["font_size", "pixel_size", "outline_size", "billboard", "no_depth_test"]:
		_check("label " + property_name, label.get(property_name),
				manifest.shared_label[property_name])
	_check("label transform", _transform(stage.global_transform.affine_inverse()
			* label.global_transform), manifest.shared_label.stage_transform)
	for node_path in manifest.retained_hidden_nodes:
		var node := stage.get_node_or_null(NodePath(node_path)) as Node3D
		_check("retained hidden " + node_path, node != null and node.is_visible_in_tree(), false)
		if node == null:
			_failures.append("Missing retained node: " + node_path)

	if print_layout:
		print(JSON.stringify({"layers": report_layers, "stage_world_transform":
				_transform(stage.global_transform), "viewport": [viewport.size.x, viewport.size.y]}))
	# 只释放本命令创建的运行实例，不保存场景或触碰正式 manifest。
	main.queue_free()
	await process_frame
	await process_frame
	if _failures.is_empty():
		print("LAYOUT CHECKS PASS | seven Quads, camera, fixed occluders, markers, label, source hashes")
		quit(0)
	else:
		for failure in _failures:
			printerr("LAYOUT CHECK FAIL | " + failure)
		quit(1)


func _check_node_transform(stage: Node3D, expected: Dictionary) -> void:
	var node := stage.get_node_or_null(NodePath(expected.node_path)) as Node3D
	if node == null:
		_failures.append("Missing transform node: " + expected.node_path)
		return
	_check(expected.node_path + " stage transform",
			_transform(stage.global_transform.affine_inverse() * node.global_transform),
			expected.stage_transform)
	if expected.has("world_transform"):
		_check(expected.node_path + " world transform", _transform(node.global_transform),
				expected.world_transform)


func _fixed_boxes(stage: Node3D) -> Array[Node3D]:
	var boxes: Array[Node3D] = []
	var pending: Array[Node] = [stage.get_node("固定乘客舱"), stage.get_node("固定门区")]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if String(stage.get_path_to(node)).begins_with("固定门区/双开门视觉3D"):
			continue
		pending.append_array(node.get_children())
		if node is Node3D and node.is_visible_in_tree() \
				and (node is CSGBox3D or (node is MeshInstance3D and node.mesh is BoxMesh)):
			boxes.append(node)
	return boxes


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _transform(value: Transform3D) -> Dictionary:
	return {"basis_columns": [_vector(value.basis.x), _vector(value.basis.y),
			_vector(value.basis.z)], "origin": _vector(value.origin)}


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if not _matches(actual, expected):
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _matches(actual: Variant, expected: Variant) -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		return absf(float(actual) - float(expected)) <= TOLERANCE
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return false
		for index in actual.size():
			if not _matches(actual[index], expected[index]):
				return false
		return true
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size():
			return false
		for key in expected:
			if not actual.has(key) or not _matches(actual[key], expected[key]):
				return false
		return true
	return actual == expected

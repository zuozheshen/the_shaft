extends SceneTree
## B/C 只读门：校验正式 main_3d 几何与实际 PNG/Profile；不保存源或清单。

const MAIN_PATH := "res://scenes/main/main_3d.tscn"
const MANIFEST_PATH := "res://art_source/floors/floor_slice_layout_v1.json"
const TOLERANCE := 0.00001

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var print_layout := false
	var check_profile := false
	var density := 64
	for argument in OS.get_cmdline_user_args():
		if argument == "--print-layout":
			print_layout = true
		elif argument == "--check-profile":
			check_profile = true
		elif argument.begins_with("--density="):
			var value := argument.trim_prefix("--density=")
			if value not in ["48", "64", "80"]:
				printerr("Unsupported density")
				quit(2)
				return
			density = int(value)
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
	var configured_main := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check("main UID resolves to formal scene",
			ResourceUID.get_id_path(ResourceUID.text_to_id(configured_main)), MAIN_PATH)
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

	if check_profile:
		_check_profile(cabin, manifest, density)
	if print_layout:
		print(JSON.stringify({"layers": report_layers, "stage_world_transform":
				_transform(stage.global_transform), "viewport": [viewport.size.x, viewport.size.y]}))
	# 只释放本命令创建的运行实例，不保存场景或触碰正式 manifest。
	main.queue_free()
	await process_frame
	await process_frame
	if _failures.is_empty():
		print("FLOOR PROFILE CHECKS PASS" if check_profile else "LAYOUT CHECKS PASS | seven Quads, camera, fixed occluders, markers, label, source hashes")
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

# C 侧：实际加载绑定资源，并与原生 PNG 像素/受控色板对照。
func _check_profile(cabin: Node, manifest: Dictionary, density: int) -> void:
	var receipt_path := "res://assets/art/floors/318/pipeline_receipt.json"
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
	if not receipt is Dictionary:
		_failures.append("Missing pipeline receipt")
		return
	_check("receipt schema", receipt.get("schema_version"), 1)
	_check("receipt density", receipt.get("density_candidate"), density)
	_check("receipt PNG count", receipt.get("pngs", []).size(), 7)
	_check("receipt layout hash", receipt.get("layout_sha256"), _text_hash(MANIFEST_PATH))
	var profile := load("res://data/presentation/floor_visuals/floor_318_visual.tres") as FloorVisualProfile
	if profile == null:
		_failures.append("Cannot load 318 FloorVisualProfile")
		return
	_check("Profile ID", String(profile.floor_id), "318")
	_check("Profile hash", receipt.get("profile_sha256"),
			_text_hash("res://data/presentation/floor_visuals/floor_318_visual.tres"))
	var coordinator = cabin.get_node("监控表现协调器")
	_check("formal Profile registration", profile in coordinator.get("floor_visual_profiles"), true)
	var source_path := String(receipt.get("source", ""))
	var palette_path := String(receipt.get("palette_source", ""))
	if (not source_path.begins_with("art_source/floors/") or ".." in source_path
			or not source_path.ends_with(".aseprite")
			or not palette_path.begins_with("art_source/floors/318/") or ".." in palette_path):
		_failures.append("Invalid receipt source/palette path")
		return
	_check("saved source hash", FileAccess.get_sha256("res://" + source_path), receipt.get("source_sha256"))
	_check("palette hash", _text_hash("res://" + palette_path), receipt.get("palette_sha256"))
	var palette: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://" + palette_path))
	if not palette is Dictionary:
		_failures.append("Invalid palette JSON")
		return
	_check("palette identity", palette.get("id"), receipt.get("palette_id"))
	_check("palette colors", palette.get("colors"), receipt.get("palette_colors"))
	_check("palette approval", palette.get("art_approved"), receipt.get("art_palette_approved"))
	var allowed: Dictionary = {}
	for value in receipt.palette_colors:
		allowed[_rgba_key(value)] = true
	var stage = cabin.get_node("监控摄影棚定位/监控测试摄影棚")
	_check("apply actual 318 textures", stage.apply_floor_visual_profile(profile), true)
	for geometry in manifest.layers:
		var id := String(geometry.id)
		var path := "res://assets/art/floors/318/" + id + ".png"
		var texture := profile.get(id + "_texture") as Texture2D
		if texture == null:
			_failures.append("Unbound Texture2D: " + id)
			continue
		_check(id + " resource path", texture.resource_path, path)
		var size := [ceili(float(geometry.quad_size_m[0]) * density),
				ceili(float(geometry.quad_size_m[1]) * density)]
		_check(id + " Texture2D size", [texture.get_width(), texture.get_height()], size)
		var png: Dictionary = {}
		for entry in receipt.pngs:
			if entry.id == id:
				png = entry
		if png.is_empty():
			_failures.append("Missing PNG receipt: " + id)
			continue
		_check(id + " PNG hash", FileAccess.get_sha256(path), png.sha256)
		var raw := Image.load_from_file(ProjectSettings.globalize_path(path))
		var imported := texture.get_image()
		if raw == null or imported == null:
			_failures.append("Image decode failed: " + id)
			continue
		_check(id + " lossless import", imported.is_compressed(), false)
		_check(id + " no mipmaps", imported.has_mipmaps(), false)
		raw.convert(Image.FORMAT_RGBA8)
		imported.convert(Image.FORMAT_RGBA8)
		_check(id + " imported pixels identical", imported.get_data(), raw.get_data())
		var opaque := 0
		var transparent := 0
		var invalid := false
		for y in raw.get_height():
			for x in raw.get_width():
				var color := raw.get_pixel(x, y)
				var rgba := [roundi(color.r * 255), roundi(color.g * 255),
						roundi(color.b * 255), roundi(color.a * 255)]
				if not allowed.has(_rgba_key(rgba)) or rgba[3] not in [0, 255]:
					invalid = true
				if rgba[3] == 0:
					transparent += 1
				else:
					opaque += 1
		_check(id + " exact palette / binary alpha", invalid, false)
		_check(id + " opaque count", opaque, png.opaque)
		_check(id + " transparent count", transparent, png.transparent)
		if id in ["far", "ground"]:
			_check(id + " continuous fallback", transparent, 0)
		var config := ConfigFile.new()
		_check(id + " import config", config.load(path + ".import"), OK)
		for setting in {"compress/mode": 0, "mipmaps/generate": false,
				"process/size_limit": 0, "process/premult_alpha": false,
				"process/fix_alpha_border": false, "detect_3d/compress_to": 0}:
			var expected: Variant = {"compress/mode": 0, "mipmaps/generate": false,
					"process/size_limit": 0, "process/premult_alpha": false,
					"process/fix_alpha_border": false, "detect_3d/compress_to": 0}[setting]
			_check(id + " import " + setting, config.get_value("params", setting), expected)
		var material := stage.get_current_floor_slice().get_layer_node(StringName(id)).get_active_material(0) as BaseMaterial3D
		_check(id + " Alpha Scissor", material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
		_check(id + " scissor threshold", material.alpha_scissor_threshold, 0.5)
		_check(id + " source color", material.albedo_color, profile.ambient_tint)
		_check(id + " nearest", material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST)
		_check(id + " Unshaded", material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)


func _rgba_key(value: Array) -> String:
	return "%d,%d,%d,%d" % [int(value[0]), int(value[1]), int(value[2]), int(value[3])]


func _text_hash(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_string(path).replace("\r\n", "\n").to_utf8_buffer())
	return context.finish().hex_encode()

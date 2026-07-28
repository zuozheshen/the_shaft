extends RefCounted


const LAYERED_SLICE_SCENE := preload(
	"res://scenes/presentation/layered_floor_slice_2_5d.tscn"
)
const MONITOR_STAGE_SCENE := preload(
	"res://scenes/presentation/monitor_test_stage_3d.tscn"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	await _test_layered_floor_slice(test_runner, tree)
	await _test_monitor_stage_controller(test_runner, tree)


func _test_layered_floor_slice(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var slice := LAYERED_SLICE_SCENE.instantiate() as LayeredFloorSlice25D
	test_runner.add_child(slice)
	await tree.process_frame

	test_runner.assert_not_equal(
		"LayeredFloorSlice25D / 场景可加载",
		null,
		slice
	)
	var layer_ids := slice.get_supported_layer_ids()
	test_runner.assert_equal(
		"LayeredFloorSlice25D / 支持七个固定图层",
		7,
		layer_ids.size()
	)

	var original_transforms: Dictionary = {}
	var all_layers_valid := true
	for layer_id in layer_ids:
		var layer := slice.get_layer_node(layer_id)
		all_layers_valid = all_layers_valid and layer != null
		if layer != null:
			original_transforms[layer_id] = layer.transform
	test_runner.assert_true(
		"LayeredFloorSlice25D / 七个 ID 均对应 MeshInstance3D",
		all_layers_valid
	)
	test_runner.assert_equal(
		"LayeredFloorSlice25D / 无效 ID 返回 null",
		null,
		slice.get_layer_node(&"invalid")
	)
	test_runner.assert_false(
		"LayeredFloorSlice25D / 无效 ID 可见性设置安全失败",
		slice.set_layer_visible(&"invalid", false)
	)

	var far_layer := slice.get_layer_node(LayeredFloorSlice25D.LAYER_FAR)
	var main_layer := slice.get_layer_node(LayeredFloorSlice25D.LAYER_MAIN)
	var original_far_visible := far_layer.visible
	var original_main_visible := main_layer.visible
	test_runner.assert_true(
		"LayeredFloorSlice25D / 可设置目标图层可见性",
		slice.set_layer_visible(
			LayeredFloorSlice25D.LAYER_FAR,
			not original_far_visible
		)
	)
	test_runner.assert_equal(
		"LayeredFloorSlice25D / 可见性只影响目标图层",
		original_main_visible,
		main_layer.visible
	)
	slice.set_layer_visible(LayeredFloorSlice25D.LAYER_FAR, original_far_visible)

	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var original_far_material := far_layer.get_active_material(0)
	var original_main_material := main_layer.get_active_material(0)
	test_runner.assert_true(
		"LayeredFloorSlice25D / 可设置运行时纹理",
		slice.set_layer_texture(LayeredFloorSlice25D.LAYER_FAR, texture)
	)
	test_runner.assert_not_equal(
		"LayeredFloorSlice25D / 目标图层使用独立运行时材质",
		original_far_material,
		far_layer.get_active_material(0)
	)
	test_runner.assert_equal(
		"LayeredFloorSlice25D / 其他图层材质不受替换影响",
		original_main_material,
		main_layer.get_active_material(0)
	)
	var node_count_before_clear := slice.get_child_count()
	slice.clear_runtime_textures()
	test_runner.assert_equal(
		"LayeredFloorSlice25D / 清理后恢复原始 fallback 材质",
		original_far_material,
		far_layer.get_active_material(0)
	)
	test_runner.assert_equal(
		"LayeredFloorSlice25D / 清理纹理不会删除节点",
		node_count_before_clear,
		slice.get_child_count()
	)

	var transforms_unchanged := true
	for layer_id in layer_ids:
		var layer := slice.get_layer_node(layer_id)
		transforms_unchanged = transforms_unchanged \
				and layer.transform == original_transforms[layer_id]
	test_runner.assert_true(
		"LayeredFloorSlice25D / 接口不修改七层 Transform",
		transforms_unchanged
	)

	slice.queue_free()
	await tree.process_frame


func _test_monitor_stage_controller(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var stage := MONITOR_STAGE_SCENE.instantiate() as MonitorStageController3D
	test_runner.add_child(stage)
	await tree.process_frame

	var original_slice := stage.get_current_floor_slice()
	test_runner.assert_not_equal(
		"MonitorStageController3D / 可取得当前楼层切片",
		null,
		original_slice
	)

	var floor_label := stage.get_node(
		"门外楼层区域/门外楼层编号"
	) as Label3D
	test_runner.assert_true(
		"MonitorStageController3D / 可设置带前导零楼层编号",
		stage.set_floor_display_id(&"004")
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 楼层编号保留 004",
		"FLOOR 004",
		floor_label.text
	)
	stage.set_floor_display_id(&"")
	test_runner.assert_equal(
		"MonitorStageController3D / 空楼层编号使用 fallback",
		"FLOOR ---",
		floor_label.text
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 空 PackedScene 安全失败",
		null,
		stage.replace_floor_slice(null)
	)

	var invalid_root := Node3D.new()
	var invalid_scene := PackedScene.new()
	invalid_scene.pack(invalid_root)
	invalid_root.free()
	test_runner.assert_equal(
		"MonitorStageController3D / 无效场景不会替换切片",
		null,
		stage.replace_floor_slice(invalid_scene)
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 无效替换保留旧切片",
		original_slice,
		stage.get_current_floor_slice()
	)

	var fixed_cabin := stage.get_node("固定乘客舱")
	var fixed_door_area := stage.get_node("固定门区")
	var camera_anchors := stage.get_node("摄像机锚点")
	var replacement := stage.replace_floor_slice(
		LAYERED_SLICE_SCENE
	)
	await tree.process_frame
	var mount := stage.get_node(
		"门外楼层区域/门外楼层挂载点"
	) as Node3D
	test_runner.assert_not_equal(
		"MonitorStageController3D / 有效场景替换成功",
		null,
		replacement
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 挂载点仅保留一个切片",
		1,
		mount.get_child_count()
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 新切片使用默认局部 Transform",
		Transform3D.IDENTITY,
		replacement.transform
	)
	test_runner.assert_true(
		"MonitorStageController3D / 固定摄影棚节点不受替换影响",
		is_instance_valid(fixed_cabin)
				and is_instance_valid(fixed_door_area)
				and is_instance_valid(camera_anchors)
	)

	stage.queue_free()
	await tree.process_frame

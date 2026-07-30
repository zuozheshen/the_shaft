extends RefCounted


const LAYERED_SLICE_SCENE := preload(
	"res://scenes/presentation/layered_floor_slice_2_5d.tscn"
)
const MONITOR_STAGE_SCENE := preload(
	"res://scenes/presentation/monitor_test_stage_3d.tscn"
)
const PASSENGER_VISUAL_SCENE := preload(
	"res://scenes/presentation/passenger_visual_3d.tscn"
)
const PASSENGER_PROFILE_001 := preload(
	"res://data/presentation/passenger_visuals/passenger_001_visual.tres"
)
const PASSENGER_PROFILE_002 := preload(
	"res://data/presentation/passenger_visuals/passenger_002_visual.tres"
)
const PASSENGER_PROFILE_003 := preload(
	"res://data/presentation/passenger_visuals/passenger_003_visual.tres"
)


func run(test_runner: Variant, tree: SceneTree) -> void:
	await _test_layered_floor_slice(test_runner, tree)
	await _test_passenger_visual(test_runner, tree)
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


func _test_passenger_visual(
		test_runner: Variant,
		tree: SceneTree
) -> void:
	var profiles: Array[PassengerVisualProfile] = [
		PASSENGER_PROFILE_001,
		PASSENGER_PROFILE_002,
		PASSENGER_PROFILE_003,
	]
	var expected_ids: Array[StringName] = [
		&"passenger_001",
		&"passenger_002",
		&"passenger_003",
	]
	var profiles_valid := true
	for index in profiles.size():
		profiles_valid = profiles_valid \
				and profiles[index] != null \
				and profiles[index].passenger_id == expected_ids[index]
	test_runner.assert_true(
		"PassengerVisualProfile / 三个占位 Profile 均可加载且 ID 正确",
		profiles_valid
	)

	var visual := PASSENGER_VISUAL_SCENE.instantiate() as PassengerVisual3D
	test_runner.add_child(visual)
	await tree.process_frame
	test_runner.assert_not_equal(
		"PassengerVisual3D / 场景可加载",
		null,
		visual
	)

	var visual_root := visual.get_node("纸片动画根") as Node3D
	var sprite := visual.get_node("纸片动画根/乘客纸片") as Sprite3D
	var shadow := visual.get_node("接触阴影") as MeshInstance3D
	var focus := visual.get_dialogue_focus()
	test_runner.assert_true(
		"PassengerVisual3D / 可取得纸片、阴影与对话焦点",
		visual_root != null
				and sprite != null
				and shadow != null
				and focus != null
	)
	test_runner.assert_false(
		"PassengerVisual3D / 空 Profile 安全失败",
		visual.apply_profile(null)
	)

	var root_transform_before_profile := visual.transform
	var base_sprite_scale := sprite.scale
	test_runner.assert_true(
		"PassengerVisual3D / 可应用 passenger_002 Profile",
		visual.apply_profile(PASSENGER_PROFILE_002)
	)
	test_runner.assert_equal(
		"PassengerVisual3D / 应用后 passenger_id 正确",
		&"passenger_002",
		visual.get_passenger_id()
	)
	test_runner.assert_equal(
		"PassengerVisual3D / 纹理正确应用",
		PASSENGER_PROFILE_002.texture,
		sprite.texture
	)
	test_runner.assert_true(
		"PassengerVisual3D / tint 正确应用",
		sprite.modulate.is_equal_approx(PASSENGER_PROFILE_002.tint)
	)
	var expected_sprite_scale := Vector3(
		base_sprite_scale.x * PASSENGER_PROFILE_002.visual_scale.x,
		base_sprite_scale.y * PASSENGER_PROFILE_002.visual_scale.y,
		base_sprite_scale.z
	)
	test_runner.assert_true(
		"PassengerVisual3D / visual_scale 相对场景基础值应用",
		sprite.scale.is_equal_approx(expected_sprite_scale)
	)
	test_runner.assert_true(
		"PassengerVisual3D / 对话焦点高度正确应用",
		is_equal_approx(
			focus.position.y,
			PASSENGER_PROFILE_002.dialogue_focus_height
		)
	)
	test_runner.assert_equal(
		"PassengerVisual3D / 应用 Profile 不修改根 Transform",
		root_transform_before_profile,
		visual.transform
	)

	var all_profiles_reuse_scene := true
	for index in profiles.size():
		all_profiles_reuse_scene = all_profiles_reuse_scene \
				and visual.apply_profile(profiles[index]) \
				and visual.get_passenger_id() == expected_ids[index]
	test_runner.assert_true(
		"PassengerVisualProfile / 三个 Profile 复用同一视觉实例",
		all_profiles_reuse_scene
	)

	visual.apply_profile(PASSENGER_PROFILE_002)
	visual.set_idle_enabled(false)
	var base_visual_position := visual_root.position
	var shadow_transform_before_idle := shadow.transform
	var root_transform_before_idle := visual.transform
	visual.set_idle_enabled(true)
	visual._process(0.5)
	test_runner.assert_false(
		"PassengerVisual3D / 待机只让纸片动画根产生位移",
		visual_root.position.is_equal_approx(base_visual_position)
	)
	test_runner.assert_equal(
		"PassengerVisual3D / 待机不修改接触阴影 Transform",
		shadow_transform_before_idle,
		shadow.transform
	)
	test_runner.assert_equal(
		"PassengerVisual3D / 待机不修改乘客根 Transform",
		root_transform_before_idle,
		visual.transform
	)
	visual.set_idle_enabled(false)
	test_runner.assert_true(
		"PassengerVisual3D / 关闭待机恢复纸片动画根基础位置",
		visual_root.position.is_equal_approx(base_visual_position)
	)
	test_runner.assert_equal(
		"PassengerVisual3D / 使用固定 Y 轴 Billboard",
		BaseMaterial3D.BILLBOARD_FIXED_Y,
		sprite.billboard
	)

	visual.set_passenger_visible(false)
	test_runner.assert_false(
		"PassengerVisual3D / 可隐藏乘客视觉",
		visual.visible
	)
	visual.set_passenger_visible(true)
	test_runner.assert_true(
		"PassengerVisual3D / 可恢复乘客视觉",
		visual.visible
	)

	visual.queue_free()
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

	var fixed_cabin := stage.get_node("固定乘客舱") as Node3D
	var fixed_door_area := stage.get_node("固定门区") as Node3D
	var camera_anchors := stage.get_node("摄像机锚点") as Node3D
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

	var original_passenger := stage.get_current_passenger_visual()
	test_runner.assert_not_equal(
		"MonitorStageController3D / 可取得当前乘客视觉",
		null,
		original_passenger
	)
	test_runner.assert_true(
		"MonitorStageController3D / 替换楼层后当前乘客仍有效",
		is_instance_valid(original_passenger)
	)

	var profiles: Array[PassengerVisualProfile] = [
		PASSENGER_PROFILE_001,
		PASSENGER_PROFILE_002,
		PASSENGER_PROFILE_003,
	]
	var profiles_applied := true
	for profile in profiles:
		profiles_applied = profiles_applied \
				and stage.apply_passenger_profile(profile) \
				and stage.get_current_passenger_visual().get_passenger_id() \
						== profile.passenger_id
	test_runner.assert_true(
		"MonitorStageController3D / 可依次应用三种乘客 Profile",
		profiles_applied
	)

	var passenger_mount := stage.get_node(
		"乘客视觉区域/当前乘客挂载点"
	) as Node3D
	var mount_scale_before_positions := passenger_mount.scale
	var fixed_door_transform := fixed_door_area.transform
	var outside_anchor := stage.get_passenger_position_anchor(
		MonitorStageController3D.PASSENGER_POSITION_OUTSIDE
	)
	var threshold_anchor := stage.get_passenger_position_anchor(
		MonitorStageController3D.PASSENGER_POSITION_THRESHOLD
	)
	var cabin_anchor := stage.get_passenger_position_anchor(
		MonitorStageController3D.PASSENGER_POSITION_CABIN
	)
	test_runner.assert_true(
		"MonitorStageController3D / outside 对齐门外等待点",
		stage.set_passenger_position(
			MonitorStageController3D.PASSENGER_POSITION_OUTSIDE
		) and passenger_mount.global_position.is_equal_approx(
			outside_anchor.global_position
		)
	)
	test_runner.assert_true(
		"MonitorStageController3D / threshold 对齐门槛点",
		stage.set_passenger_position(
			MonitorStageController3D.PASSENGER_POSITION_THRESHOLD
		) and passenger_mount.global_position.is_equal_approx(
			threshold_anchor.global_position
		)
	)
	test_runner.assert_true(
		"MonitorStageController3D / cabin 对齐舱内站位",
		stage.set_passenger_position(
			MonitorStageController3D.PASSENGER_POSITION_CABIN
		) and passenger_mount.global_position.is_equal_approx(
			cabin_anchor.global_position
		)
	)
	test_runner.assert_false(
		"MonitorStageController3D / 无效乘客位置安全失败",
		stage.set_passenger_position(&"invalid")
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 位置切换保留挂载点缩放",
		mount_scale_before_positions,
		passenger_mount.scale
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 位置切换不修改固定门区",
		fixed_door_transform,
		fixed_door_area.transform
	)

	test_runner.assert_equal(
		"MonitorStageController3D / 空乘客场景安全失败",
		null,
		stage.replace_passenger_visual(null)
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 无效乘客场景不会替换旧乘客",
		null,
		stage.replace_passenger_visual(invalid_scene)
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 无效替换保留旧乘客",
		original_passenger,
		stage.get_current_passenger_visual()
	)

	var new_passenger := stage.replace_passenger_visual(
		PASSENGER_VISUAL_SCENE
	)
	await tree.process_frame
	test_runner.assert_not_equal(
		"MonitorStageController3D / 有效乘客视觉替换成功",
		null,
		new_passenger
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 挂载点只保留一个当前乘客视觉",
		1,
		passenger_mount.get_child_count()
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 新乘客使用默认局部 Transform",
		Transform3D.IDENTITY,
		new_passenger.transform
	)
	test_runner.assert_equal(
		"MonitorStageController3D / 替换乘客后当前楼层切片仍有效",
		replacement,
		stage.get_current_floor_slice()
	)

	var passenger_before_floor_replace := stage.get_current_passenger_visual()
	var second_slice := stage.replace_floor_slice(LAYERED_SLICE_SCENE)
	await tree.process_frame
	test_runner.assert_true(
		"MonitorStageController3D / 再次替换楼层不删除乘客",
		is_instance_valid(passenger_before_floor_replace)
				and passenger_before_floor_replace \
						== stage.get_current_passenger_visual()
	)
	test_runner.assert_not_equal(
		"MonitorStageController3D / 替换乘客后楼层接口仍可替换",
		null,
		second_slice
	)
	test_runner.assert_true(
		"MonitorStageController3D / 摄像机锚点仍有效",
		is_instance_valid(stage.get_node("摄像机锚点/舱内摄像机锚点"))
				and is_instance_valid(
					stage.get_node("摄像机锚点/门外摄像机锚点")
				)
	)

	stage.queue_free()
	await tree.process_frame

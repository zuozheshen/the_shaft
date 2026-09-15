extends RefCounted
## 使用正式场景配置与内存纹理验证切换；不复制业务资源或新增运行时系统。

const STAGE := preload("res://scenes/presentation/monitor_test_stage_3d.tscn")
const CABIN := preload("res://scenes/elevator/elevator_cabin_3d.tscn")
const CATALOG := preload("res://data/catalogs/floor_catalog.tres")
const SHIFT := preload("res://data/shifts/demo_shift_001.tres")


func run(r: Variant, tree: SceneTree) -> void:
	_test_scene_configuration(r)
	await _test_complete_overwrite(r, tree)
	await _test_arrival_and_fallback(r, tree)
	await _test_animation_and_camera_isolation(r, tree)
	await _test_missing_light(r, tree)


func configured_coordinator() -> MonitorPresentationCoordinator3D:
	# 读取真实导出配置，宿主不上树，不启动正式 UI 或玩家输入。
	var cabin := CABIN.instantiate()
	var coordinator := cabin.get_node("监控表现协调器") as MonitorPresentationCoordinator3D
	cabin.remove_child(coordinator)
	cabin.free()
	return coordinator


func _test_scene_configuration(r: Variant) -> void:
	var cabin := CABIN.instantiate()
	var coordinator := cabin.get_node("监控表现协调器") as MonitorPresentationCoordinator3D
	var ids: Array[StringName] = []
	for profile in coordinator.floor_visual_profiles:
		r.assert_true("楼层配置 / 有效且无重复", profile != null and profile.floor_id not in ids)
		if profile != null:
			ids.append(profile.floor_id)
	r.assert_equal("楼层配置 / 数量与真实 Catalog 一致", CATALOG.floors.size(), ids.size())
	for floor_data in CATALOG.floors:
		r.assert_true("楼层配置 / 覆盖 " + String(floor_data.floor_id), floor_data.floor_id in ids)
	r.assert_true("楼层配置 / 已配置 fallback", coordinator.fallback_floor_visual_profile != null)
	var stage := cabin.find_child("监控测试摄影棚", true, false) as MonitorStageController3D
	var floor_light := stage.get_node(stage.floor_light_path) as Light3D
	r.assert_equal("灯光隔离 / 门外灯只照 Layer 3", 4, floor_light.light_cull_mask)
	for node in stage.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var outside := stage.get_node("门外楼层区域").is_ancestor_of(geometry)
		r.assert_equal("渲染层 / " + str(stage.get_path_to(geometry)), 4 if outside else 2, geometry.layers)
	var player: Camera3D
	# 玩家节点名称不是本测试的契约；用正式摄像机集合识别非监控机位。
	for candidate in cabin.find_children("*", "Camera3D", true, false):
		if candidate.name != &"监控摄像机":
			player = candidate as Camera3D
	r.assert_true("渲染层 / 玩家排除摄影棚两层", player != null and (player.cull_mask & 6) == 0)
	var monitor := cabin.get_node("监控渲染系统/监控视口/监控摄像机") as Camera3D
	r.assert_equal("渲染层 / 同一监控摄像机看见 Layer 2+3", 6, monitor.cull_mask)
	cabin.free()


func _test_complete_overwrite(r: Variant, tree: SceneTree) -> void:
	var stage := STAGE.instantiate() as MonitorStageController3D
	var other := STAGE.instantiate() as MonitorStageController3D
	r.add_child(stage)
	r.add_child(other)
	var slice := stage.get_current_floor_slice()
	var original := _snapshot(stage)
	var shared_before := _snapshot(other)
	var label := stage.get_node(stage.floor_label_path) as Label3D
	var light := stage.get_node(stage.floor_light_path) as Light3D
	var base_energy := light.light_energy
	var base_color := light.light_color
	var texture := ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var a := FloorVisualProfile.new()
	a.floor_id = &"612"
	a.ambient_tint = Color(0.6, 0.7, 0.8, 1)
	a.light_energy_multiplier = 0.5
	for layer_id in slice.get_supported_layer_ids():
		a.set(String(layer_id) + "_texture", texture)
		a.set(String(layer_id) + "_visible", false)
	r.assert_true("楼层覆盖 / 完整应用 A", stage.apply_floor_visual_profile(a))
	for layer_id in slice.get_supported_layer_ids():
		var layer := slice.get_layer_node(layer_id)
		var material := layer.get_active_material(0) as BaseMaterial3D
		r.assert_true("楼层覆盖 / A 纹理与隐藏 " + String(layer_id),
				material.albedo_texture == texture and not layer.visible)
		r.assert_true("楼层覆盖 / tint 按基础颜色 " + String(layer_id),
				material.albedo_color.is_equal_approx(original[layer_id].color * a.ambient_tint))
	var a_snapshot := _snapshot(stage)
	stage.apply_floor_visual_profile(a)
	r.assert_equal("楼层覆盖 / 重复应用不累积", a_snapshot, _snapshot(stage))
	r.assert_equal("楼层覆盖 / 不污染另一共享实例", shared_before, _snapshot(other))
	r.assert_true("灯光 / 倍率与颜色按缓存基础值",
			is_equal_approx(light.light_energy, base_energy * 0.5)
			and light.light_color.is_equal_approx(base_color * a.ambient_tint))

	var b := FloorVisualProfile.new()
	b.floor_id = &"004"
	b.display_label = "测试附注"
	stage.apply_floor_visual_profile(b)
	r.assert_equal("楼层标签 / 附注不替代前导零编号", "FLOOR 004 — 测试附注", label.text)
	r.assert_equal("楼层覆盖 / B 清空七层纹理并恢复显隐色调灯光", original, _snapshot(stage))
	r.assert_equal("楼层 getter / Profile", b, stage.get_current_floor_visual_profile())
	r.assert_equal("楼层 getter / 004", &"004", stage.get_current_floor_visual_id())
	for invalid_multiplier in [-1.0, INF, NAN]:
		b.light_energy_multiplier = invalid_multiplier
		stage.apply_floor_visual_profile(b)
		r.assert_equal("灯光 / 非法倍率安全回基础值", base_energy, light.light_energy)
	stage.apply_floor_visual_profile(a)
	r.assert_false("楼层覆盖 / null 安全失败", stage.apply_floor_visual_profile(null))
	r.assert_equal("楼层覆盖 / null 恢复安全默认", original, _snapshot(stage))
	r.assert_equal("楼层覆盖 / null 清除旧 getter", null, stage.get_current_floor_visual_profile())
	r.assert_equal("楼层覆盖 / null 清除旧编号", "FLOOR ---", label.text)

	var coordinator := configured_coordinator()
	for floor_id in [&"900", &"612", &"004", &"900"]:
		for profile in coordinator.floor_visual_profiles:
			if profile.floor_id == floor_id:
				stage.apply_floor_visual_profile(profile)
				r.assert_equal("多层往返 / 编号 " + String(floor_id), floor_id, stage.get_current_floor_visual_id())
	r.assert_equal("多层往返 / 900 完整恢复", original, _snapshot(stage))
	coordinator.free()
	stage.queue_free()
	other.queue_free()
	await tree.process_frame


func _snapshot(stage: MonitorStageController3D) -> Dictionary:
	var result := {}
	var slice := stage.get_current_floor_slice()
	for layer_id in slice.get_supported_layer_ids():
		var layer := slice.get_layer_node(layer_id)
		var material := layer.get_active_material(0) as BaseMaterial3D
		result[layer_id] = {
			"texture": material.albedo_texture, "visible": layer.visible,
			"color": material.albedo_color, "transform": layer.transform,
			"shading": material.shading_mode,
		}
	var light := stage.get_node(stage.floor_light_path) as Light3D
	result["energy"] = light.light_energy
	result["light_color"] = light.light_color
	return result


func _test_arrival_and_fallback(r: Variant, tree: SceneTree) -> void:
	var manager := DemoFlowManager.new()
	manager.initial_floor = "004"
	manager.initial_shift = SHIFT
	manager.movement_duration_seconds = 0.01
	var stage := STAGE.instantiate() as MonitorStageController3D
	var coordinator := configured_coordinator()
	var original_profiles := coordinator.floor_visual_profiles.duplicate()
	var original_fallback := coordinator.fallback_floor_visual_profile
	var duplicate := FloorVisualProfile.new()
	duplicate.floor_id = &"004"
	duplicate.front_left_visible = false
	coordinator.floor_visual_profiles.append_array([null, FloorVisualProfile.new(), duplicate])
	r.add_child(manager)
	r.add_child(stage)
	r.add_child(coordinator)
	coordinator.setup(manager, null, null, stage)
	r.assert_equal("楼层初始化 / 使用当前实际 004", &"004", stage.get_current_floor_visual_id())
	for profile in original_profiles:
		if profile.floor_id == &"004":
			r.assert_equal("楼层索引 / 重复项保留首个", profile, stage.get_current_floor_visual_profile())
	coordinator.setup(manager, null, null, stage)
	r.assert_equal("楼层初始化 / 重复 setup 仅一条到站连接",
			1, manager.elevator_movement_completed.get_connections().size())
	var ordering := {"seen": false, "correct": true}
	stage.passenger_presentation_state_changed.connect(func(state: int) -> void:
		if state == MonitorStageController3D.PassengerPresentationState.OUTSIDE_WAITING:
			ordering.seen = true
			ordering.correct = ordering.correct and stage.get_current_floor_visual_id() == &"612" \
					and (stage.get_node(stage.floor_label_path) as Label3D).text == "FLOOR 612"
	)
	var before_move := _snapshot(stage)
	var result := manager.request_travel_to_floor("612")
	coordinator._on_presentation_effects_requested(result.get_effects())
	r.assert_true("到站时序 / 真实移动命令成功", result.succeeded and manager.is_elevator_moving())
	r.assert_equal("到站时序 / MOVEMENT_STARTED 保持上一楼层", &"004", stage.get_current_floor_visual_id())
	r.assert_equal("到站时序 / 移动期间材质不变", before_move, _snapshot(stage))
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	r.assert_true("到站时序 / 显示乘客的同步信号内楼层已生效", ordering.seen and ordering.correct)
	r.assert_equal("到站时序 / 实际抵达才切换", &"612", stage.get_current_floor_visual_id())

	# 遍历真实 Catalog 的合法移动，验证每一个正式映射，而不直接调用私有查找表。
	for floor_data in CATALOG.floors:
		var travel := manager.request_travel_to_floor(String(floor_data.floor_id))
		coordinator._on_presentation_effects_requested(travel.get_effects())
		if manager.is_elevator_moving():
			await manager.elevator_movement_completed
		r.assert_equal("楼层映射 / 实际抵达 " + String(floor_data.floor_id),
				floor_data.floor_id, stage.get_current_floor_visual_id())
		var expected: FloorVisualProfile
		for profile in original_profiles:
			if profile.floor_id == floor_data.floor_id:
				expected = profile
		r.assert_equal("楼层映射 / 使用正式资源 " + String(floor_data.floor_id),
				expected, stage.get_current_floor_visual_profile())

	# 删除一个已注册业务楼层的表现配置，业务仍可正常完成移动。
	coordinator.floor_visual_profiles = []
	coordinator.setup(manager, null, null, stage)
	var fallback_base := _snapshot(stage)
	var dirty_profile := FloorVisualProfile.new()
	dirty_profile.floor_id = &"old"
	dirty_profile.main_texture = ImageTexture.create_from_image(
			Image.create(2, 2, false, Image.FORMAT_RGBA8))
	dirty_profile.front_left_visible = false
	dirty_profile.ambient_tint = Color(0.3, 0.4, 0.5, 1)
	dirty_profile.light_energy_multiplier = 0.4
	stage.apply_floor_visual_profile(dirty_profile)
	var travel := manager.request_travel_to_floor("004")
	if manager.is_elevator_moving():
		await manager.elevator_movement_completed
	r.assert_true("fallback / 缺视觉不阻止业务抵达", travel.succeeded and manager.get_current_floor() == "004")
	r.assert_equal("fallback / 不残留旧视觉", fallback_base, _snapshot(stage))
	r.assert_equal("fallback / 标签保留真实编号", "FLOOR 004",
			(stage.get_node(stage.floor_label_path) as Label3D).text)
	r.assert_equal("fallback / 不修改共享 fallback ID", &"fallback", original_fallback.floor_id)
	var custom_fallback := original_fallback.duplicate() as FloorVisualProfile
	custom_fallback.ambient_tint = Color(0.8, 0.9, 0.7, 1)
	custom_fallback.front_right_visible = false
	custom_fallback.light_energy_multiplier = 0.7
	custom_fallback.display_label = "不应显示的模板名称"
	coordinator.fallback_floor_visual_profile = custom_fallback
	coordinator.setup(manager, null, null, stage)
	r.assert_equal("fallback / 使用导出的自定义色调", custom_fallback.ambient_tint,
			stage.get_current_floor_visual_profile().ambient_tint)
	r.assert_false("fallback / 使用导出的显隐",
			stage.get_current_floor_slice().get_layer_node(&"front_right").visible)
	r.assert_equal("fallback / 模板名称不替代真实编号", "FLOOR 004",
			(stage.get_node(stage.floor_label_path) as Label3D).text)
	r.assert_equal("fallback / 不修改自定义模板 ID", &"fallback", custom_fallback.floor_id)

	# 新业务楼层尚未配置视觉的情形用空派单实例模拟，不改正式 Catalog。
	var empty_manager := DemoFlowManager.new()
	empty_manager.initial_floor = "099"
	empty_manager.initial_shift = SHIFT
	r.add_child(empty_manager)
	empty_manager.finish_shift()
	coordinator.fallback_floor_visual_profile = null
	coordinator.setup(empty_manager, null, null, stage)
	r.assert_equal("fallback / 无默认资源也清理状态", fallback_base, _snapshot(stage))
	r.assert_equal("fallback / 未知楼层 setup 保留编号", &"099", stage.get_current_floor_visual_id())
	r.assert_equal("重复 setup / 断开旧 Manager", 0, manager.elevator_movement_completed.get_connections().size())
	empty_manager.elevator_runtime_state.request_movement("098")
	await empty_manager.elevator_movement_completed
	r.assert_equal("fallback / 无派单到站仍切换真实编号", &"098", stage.get_current_floor_visual_id())
	r.assert_false("fallback / 无派单仍保持乘客隐藏", stage.get_current_passenger_visual().visible)
	coordinator.queue_free()
	stage.queue_free()
	manager.queue_free()
	empty_manager.queue_free()
	await tree.process_frame


func _test_animation_and_camera_isolation(r: Variant, tree: SceneTree) -> void:
	var cabin := CABIN.instantiate()
	var mount := cabin.get_node("监控摄影棚定位") as Node3D
	var monitor := cabin.get_node("监控渲染系统") as MonitorCameraController3D
	cabin.remove_child(mount)
	cabin.remove_child(monitor)
	cabin.free()
	var fixture := Node3D.new()
	fixture.add_child(mount)
	fixture.add_child(monitor)
	r.add_child(fixture)
	var stage := mount.get_node("监控测试摄影棚") as MonitorStageController3D
	var passenger := stage.get_current_passenger_visual()
	var passenger_profile := passenger.get_current_profile()
	var cabin_light := stage.get_node("监控灯光/摄影棚顶灯") as Light3D
	var cabin_energy := cabin_light.light_energy
	var cabin_color := cabin_light.light_color
	var passenger_sprite := passenger.get_node(passenger.sprite_path) as Sprite3D
	var passenger_modulate := passenger_sprite.modulate
	var camera := monitor.get_node(monitor.monitor_camera_path) as Camera3D
	monitor.select_camera(0)
	var camera_transform := camera.global_transform
	var camera_fov := camera.fov
	var profile := FloorVisualProfile.new()
	profile.floor_id = &"004"
	profile.ambient_tint = Color(0.4, 0.5, 0.6, 1)
	profile.light_energy_multiplier = 0.3
	stage.apply_floor_visual_profile(profile)
	var door := stage.get_door_visual()
	var animations := door.get_animation_player()
	stage.request_door_open_presentation()
	animations.advance(0.1)
	var door_state := door.get_door_state()
	var animation := animations.current_animation
	var animation_position := animations.current_animation_position
	var passenger_state := stage.get_passenger_presentation_state()
	stage.apply_floor_visual_profile(profile)
	r.assert_true("表现隔离 / 不重播正在运行的开门动画",
			door.get_door_state() == door_state and animations.current_animation == animation
			and is_equal_approx(animations.current_animation_position, animation_position))
	r.assert_equal("表现隔离 / 不改变乘客稳定状态", passenger_state, stage.get_passenger_presentation_state())
	r.assert_equal("表现隔离 / 不改变摄像机 Transform", camera_transform, camera.global_transform)
	r.assert_equal("表现隔离 / 不改变摄像机 FOV", camera_fov, camera.fov)
	r.assert_equal("表现隔离 / 不改变机位选择", 0, monitor.get("_current_camera_index"))

	# 手动覆盖一层形成探针：如果 CAM 切换重新 apply，这个值会被 Profile 覆盖。
	stage.get_current_floor_slice().set_layer_visible(&"front_left", false)
	var snapshot := _snapshot(stage)
	monitor.select_camera(1)
	monitor.select_camera(0)
	r.assert_equal("CAM 往返 / 不重新应用楼层", snapshot, _snapshot(stage))
	r.assert_equal("CAM 往返 / Profile 引用保持", profile, stage.get_current_floor_visual_profile())
	r.assert_equal("CAM 往返 / 返回原机位", camera_transform, camera.global_transform)

	animations.advance(2.0)
	stage.snap_passenger_outside_waiting()
	r.assert_true("表现隔离 / 启动真实登舱 Tween", stage.request_passenger_boarding())
	var tween := stage.get("_passenger_movement_tween") as Tween
	var boarded := {"count": 0}
	stage.passenger_boarded.connect(func() -> void: boarded.count += 1)
	stage.apply_floor_visual_profile(profile)
	r.assert_true("表现隔离 / 楼层切换保留登舱 Tween",
			tween.is_valid() and tween.is_running()
			and stage.get("_passenger_movement_tween") == tween
			and stage.get_passenger_presentation_state() == MonitorStageController3D.PassengerPresentationState.BOARDING)
	tween.custom_step(3.0)
	r.assert_true("表现隔离 / 原登舱 Tween 正常完成一次",
			boarded.count == 1 and not stage.is_passenger_presentation_busy()
			and stage.get_passenger_presentation_state() == MonitorStageController3D.PassengerPresentationState.CABIN)
	r.assert_true("表现隔离 / 启动真实离舱 Tween", stage.request_passenger_disembark())
	tween = stage.get("_passenger_movement_tween") as Tween
	var exited := {"count": 0}
	stage.passenger_exited.connect(func() -> void: exited.count += 1)
	profile = FloorVisualProfile.new()
	profile.floor_id = &"900"
	stage.apply_floor_visual_profile(profile)
	r.assert_true("表现隔离 / 楼层切换保留离舱 Tween",
			tween.is_valid() and tween.is_running()
			and stage.get("_passenger_movement_tween") == tween
			and stage.get_passenger_presentation_state() == MonitorStageController3D.PassengerPresentationState.DISEMBARKING)
	tween.custom_step(3.0)
	r.assert_true("表现隔离 / 原离舱 Tween 正常完成一次",
			exited.count == 1 and not stage.is_passenger_presentation_busy()
			and stage.get_passenger_presentation_state() == MonitorStageController3D.PassengerPresentationState.EXITED)
	r.assert_equal("表现隔离 / 不修改乘客 Profile", passenger_profile, passenger.get_current_profile())
	r.assert_equal("表现隔离 / 不修改乘客调色", passenger_modulate, passenger_sprite.modulate)
	r.assert_equal("表现隔离 / 不修改舱内灯能量", cabin_energy, cabin_light.light_energy)
	r.assert_equal("表现隔离 / 不修改舱内灯颜色", cabin_color, cabin_light.light_color)
	r.assert_true("表现隔离 / 门仍保持开启", door.is_open())
	stage.request_door_close_presentation()
	animations.advance(0.1)
	animation_position = animations.current_animation_position
	door_state = door.get_door_state()
	stage.apply_floor_visual_profile(profile)
	r.assert_true("表现隔离 / 不重播正在运行的关门动画",
			door.get_door_state() == door_state and animations.is_playing()
			and is_equal_approx(animations.current_animation_position, animation_position))
	fixture.queue_free()
	await tree.process_frame


func _test_missing_light(r: Variant, tree: SceneTree) -> void:
	var stage := STAGE.instantiate() as MonitorStageController3D
	stage.floor_light_path = NodePath("不存在的门外灯")
	r.add_child(stage)
	var profile := FloorVisualProfile.new()
	profile.floor_id = &"004"
	r.assert_true("灯光降级 / 缺灯仍可应用视觉", stage.apply_floor_visual_profile(profile))
	r.assert_equal("灯光降级 / 标签保持真实编号", "FLOOR 004",
			(stage.get_node(stage.floor_label_path) as Label3D).text)
	stage.queue_free()
	await tree.process_frame

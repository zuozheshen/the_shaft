class_name FloorGuideBook3D
extends Node3D

signal inspection_closed

enum State { CLOSED, OPENING, OPEN, TURNING, CLOSING }

@export_range(0.1, 1.0, 0.01) var open_duration: float = 0.35
@export_range(0.1, 1.0, 0.01) var close_duration: float = 0.35
@export_range(0.1, 1.0, 0.01) var page_turn_duration: float = 0.28

@onready var _rest_pose: Marker3D = $RestPose
@onready var _inspect_pose: Marker3D = $InspectPose
@onready var _book_root: Node3D = $BookRoot
@onready var _cover_pivot: Node3D = $BookRoot/CoverPivot
@onready var _left_page: MeshInstance3D = $BookRoot/LeftPageMesh
@onready var _right_page: MeshInstance3D = $BookRoot/RightPageMesh
@onready var _left_page_base: MeshInstance3D = $BookRoot/LeftPageBase
@onready var _turn_page_pivot: Node3D = $BookRoot/TurnPagePivot
@onready var _turn_page: MeshInstance3D = $BookRoot/TurnPagePivot/TurnPage
@onready var _closed_hotspot: InteractionHotspot3D = $BookRoot/BookHotspot
@onready var _previous_hotspot: InteractionHotspot3D = $BookRoot/PrevPageHotspot
@onready var _next_hotspot: InteractionHotspot3D = $BookRoot/NextPageHotspot
@onready var _close_hotspot: InteractionHotspot3D = $BookRoot/CloseBookHotspot
@onready var _left_viewport: SubViewport = $LeftPageViewport
@onready var _right_viewport: SubViewport = $RightPageViewport
@onready var _number: Label = $LeftPageViewport/Page/Number
@onready var _name: Label = $LeftPageViewport/Page/Name
@onready var _description: Label = $LeftPageViewport/Page/Description
@onready var _function: Label = $RightPageViewport/Page/FunctionText
@onready var _history: Label = $RightPageViewport/Page/HistoryText
@onready var _note: Label = $RightPageViewport/Page/NoteText
@onready var _page_count: Label = $RightPageViewport/Page/PageCount

var _destination: DestinationControlInterface
var _state: State = State.CLOSED
var _page_index: int = 0
var _animation: Tween


func _ready() -> void:
	# 两页纹理各自映射到实体纸面；休止时不持续刷新离屏 UI。
	_bind_page_texture(_left_page, _left_viewport)
	_bind_page_texture(_right_page, _right_viewport)
	_book_root.transform = _rest_pose.transform
	_cover_pivot.rotation.y = 0.0
	_left_page.visible = false
	_right_page.visible = false
	_left_page_base.visible = false
	_turn_page.visible = false
	_left_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_right_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_hotspot(_closed_hotspot, true)
	_set_hotspot(_previous_hotspot, false)
	_set_hotspot(_next_hotspot, false)
	_set_hotspot(_close_hotspot, false)


func bind_destination(destination: DestinationControlInterface) -> void:
	_destination = destination


func is_inspection_active() -> bool:
	return _state != State.CLOSED


func is_open() -> bool:
	return _state == State.OPEN


func is_busy() -> bool:
	return _state == State.OPENING or _state == State.TURNING or _state == State.CLOSING


func get_page_index() -> int:
	return _page_index


func open_book() -> bool:
	if _state != State.CLOSED or _destination == null:
		return false
	var count: int = _destination.get_floor_book_page_count()
	if count == 0:
		return false
	_page_index = clampi(_page_index, 0, count - 1)
	_state = State.OPENING
	_set_hotspot(_closed_hotspot, false)
	_show_page(_page_index)
	_left_page.visible = true
	_right_page.visible = true
	_left_page_base.visible = true
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_animation.set_parallel(true)
	_animation.tween_property(_book_root, "transform", _inspect_pose.transform, open_duration)
	_animation.tween_property(_cover_pivot, "rotation:y", PI, open_duration)
	_animation.set_parallel(false)
	_animation.tween_callback(_finish_open)
	return true


func _finish_open() -> void:
	_book_root.transform = _inspect_pose.transform
	_cover_pivot.rotation.y = PI
	_cover_pivot.visible = false
	_state = State.OPEN
	_set_reading_hotspots(true)


func close_book() -> bool:
	# 翻页或展开未落定时拒绝合书，避免封面与页面停在半途。
	if _state != State.OPEN:
		return false
	_state = State.CLOSING
	_cover_pivot.visible = true
	_set_reading_hotspots(false)
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_animation.set_parallel(true)
	_animation.tween_property(_cover_pivot, "rotation:y", 0.0, close_duration)
	_animation.tween_property(_book_root, "transform", _rest_pose.transform, close_duration)
	_animation.set_parallel(false)
	_animation.tween_callback(_finish_close)
	return true


func _finish_close() -> void:
	_cover_pivot.rotation.y = 0.0
	_book_root.transform = _rest_pose.transform
	_left_page.visible = false
	_right_page.visible = false
	_left_page_base.visible = false
	_left_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_right_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_state = State.CLOSED
	_set_hotspot(_closed_hotspot, true)
	inspection_closed.emit()


func turn_page(direction: int) -> bool:
	if _state != State.OPEN or _destination == null or direction == 0:
		return false
	var target: int = _page_index + signi(direction)
	if target < 0 or target >= _destination.get_floor_book_page_count():
		return false
	_state = State.TURNING
	_set_reading_hotspots(false)
	_turn_page.visible = true
	# 负向转过书脊，让薄页朝读者一侧掠过，而不是藏到书的背后。
	_turn_page_pivot.rotation.y = 0.0 if direction > 0 else -PI
	_turn_page_pivot.scale = Vector3.ONE
	var midpoint: float = -PI * 0.5
	var end_angle: float = -PI if direction > 0 else 0.0
	var mid_scale := Vector3(1.0, 0.6, 0.35)
	_animation = create_tween()
	_animation.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_animation.set_parallel(true)
	_animation.tween_property(_turn_page_pivot, "rotation:y", midpoint, page_turn_duration * 0.5)
	_animation.tween_property(_turn_page_pivot, "scale", mid_scale, page_turn_duration * 0.5)
	_animation.set_parallel(false)
	_animation.tween_callback(_turn_midpoint.bind(target))
	_animation.set_parallel(true)
	_animation.tween_property(_turn_page_pivot, "rotation:y", end_angle, page_turn_duration * 0.5)
	_animation.tween_property(_turn_page_pivot, "scale", Vector3.ONE, page_turn_duration * 0.5)
	_animation.set_parallel(false)
	_animation.tween_callback(_finish_turn)
	return true


func _turn_midpoint(target: int) -> void:
	# 两张底页在翻页面遮挡视线的中点同步换内容，页码不提前跳。
	_page_index = target
	_show_page(_page_index)


func _finish_turn() -> void:
	_turn_page.visible = false
	_turn_page_pivot.rotation.y = 0.0
	_turn_page_pivot.scale = Vector3.ONE
	_state = State.OPEN
	_set_reading_hotspots(true)


func _show_page(index: int) -> void:
	var snapshot: Dictionary = _destination.get_floor_book_snapshot(index)
	if snapshot.is_empty():
		push_error("楼层导引书缺少页快照：%d" % index)
		return
	_number.text = str(snapshot["floor_id"])
	_name.text = str(snapshot["display_name"])
	_fit_text(_description, str(snapshot["description"]), 42, 34)
	_fit_text(_function, str(snapshot["function_description"]), 38, 30)
	_fit_text(_history, str(snapshot["maintenance_history"]), 38, 30)
	_fit_text(_note, str(snapshot["book_note"]), 38, 30)
	_page_count.text = "%02d / %02d" % [snapshot["page_number"], snapshot["page_count"]]
	_left_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_right_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _fit_text(label: Label, value: String, default_size: int, minimum_size: int) -> void:
	label.text = value
	for font_size in range(default_size, minimum_size - 1, -2):
		label.add_theme_font_size_override("font_size", font_size)
		if label.get_line_count() * font_size * 1.35 <= label.size.y:
			return
	push_error("楼层导引书正文超出版心：%s" % label.name)


func _bind_page_texture(mesh: MeshInstance3D, viewport: SubViewport) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mesh.material_override = material


func _set_reading_hotspots(enabled: bool) -> void:
	_set_hotspot(_previous_hotspot, enabled)
	_set_hotspot(_next_hotspot, enabled)
	_set_hotspot(_close_hotspot, enabled)


func _set_hotspot(hotspot: InteractionHotspot3D, enabled: bool) -> void:
	hotspot.interaction_enabled = enabled
	hotspot.collision_layer = (1 << 7) if enabled else 0
	if not enabled:
		hotspot.set_hovered(false)

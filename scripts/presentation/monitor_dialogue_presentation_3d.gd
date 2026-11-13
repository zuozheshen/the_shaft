class_name MonitorDialoguePresentation3D
extends SubViewport

## 画面持有页码，派单状态持有事件与呈现回执。转向、W 和窗口失焦都会暂停计时。
const LINES_PER_PAGE := 3
const MIN_PAGE_SECONDS := 4.0
const FINAL_PAGE_SECONDS := 6.0
const REVIEW_HANDOFF_SECONDS := 1.5
const SECONDS_PER_CHARACTER := 0.12

@onready var _bubble: Panel = $Bubble
@onready var _speaker: Label = $Bubble/Speaker
@onready var _text: Label = $Bubble/Text

var _manager: DemoFlowManager
var _view: CabinViewController3D
var _terminal: VerificationTerminal3D
var _screen: MeshInstance3D
var _lamp: Node3D
var _event: Dictionary = {}
var _pages: Array[Dictionary] = []
var _page := 0
var _elapsed := 0.0
var _frame_delta := 0.0
var _draw_candidate := false
var _last_draw_valid := false
var _page_complete := false
var _final_page_drawn := false


func setup(manager: DemoFlowManager, view: CabinViewController3D,
		terminal: VerificationTerminal3D, screen: MeshInstance3D, lamp: Node3D) -> void:
	_manager = manager
	_view = view
	_terminal = terminal
	_screen = screen
	_lamp = lamp
	manager.document_session_changed.connect(_reset)
	manager.passenger_event_changed.connect(_refresh)
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)
	_refresh()


func _reset(_session: int) -> void:
	_event.clear()
	_pages.clear()
	_bubble.hide()
	_text.text = ""
	_speaker.text = ""
	_draw_candidate = false
	_last_draw_valid = false
	_refresh()


func _refresh() -> void:
	var next: Dictionary = {}
	var unread := false
	for event: Dictionary in _manager.get_passenger_events():
		if event.status in ["pending", "running", "resolved"]:
			unread = true
		if event.status == "resolved" and (next.is_empty() or event.key == "destination_opened"):
			next = event
	_lamp.visible = unread
	# 开门后离舱已开始，先呈现该层回应。其他事件仍留在队列里。
	var dropoff_ready: bool = next.get("key") == "destination_opened"
	if dropoff_ready or _event.is_empty() or _page_complete:
		if not next.is_empty() and next.source_event_id != _event.get("source_event_id"):
			_show_event(next)


func _show_event(event: Dictionary) -> void:
	_event = event
	_pages.clear()
	var font := _text.get_theme_font("font")
	var font_size := _text.get_theme_font_size("font_size")
	for row: Dictionary in event.rows:
		var lines: Array[String] = []
		for paragraph: String in String(row.text).split("\n"):
			var shaped := TextParagraph.new()
			shaped.width = _text.size.x
			shaped.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_GRAPHEME_BOUND | TextServer.BREAK_ADAPTIVE
			shaped.add_string(paragraph, font, font_size)
			if paragraph.is_empty():
				lines.append("")
			for index in shaped.get_line_count():
				var span := shaped.get_line_range(index)
				lines.append(paragraph.substr(span.x, span.y - span.x))
		for index in range(0, lines.size(), LINES_PER_PAGE):
			_pages.append({"speaker": row.speaker, "text": "\n".join(lines.slice(index, index + LINES_PER_PAGE))})
	if not _pages.is_empty():
		_show_page(0)


func _show_page(index: int) -> void:
	_page = index
	_elapsed = 0.0
	_page_complete = false
	_final_page_drawn = false
	_draw_candidate = false
	_last_draw_valid = false
	var speaker: String = _pages[index].speaker
	_speaker.text = "%s  ·  %d/%d" % ["乘客" if speaker in ["", "Passenger"] else speaker, index + 1, _pages.size()]
	_text.text = _pages[index].text
	_bubble.show()


func _process(delta: float) -> void:
	_frame_delta = minf(delta, 0.10)


func _before_draw() -> void:
	_draw_candidate = _can_read()


func _after_draw() -> void:
	var valid := _draw_candidate and _can_read()
	_draw_candidate = false
	if not valid or not _last_draw_valid:
		_last_draw_valid = valid
		return
	_elapsed += _frame_delta
	var final_page := _page + 1 == _pages.size()
	var duration := maxf(MIN_PAGE_SECONDS, _text.text.length() * SECONDS_PER_CHARACTER)
	if final_page:
		# 末页已经绘制时允许摘录，停留与队列槽仍按原节奏结束。
		if not _final_page_drawn:
			_final_page_drawn = true
			_confirm_final_draw.call_deferred(_event.session, _event.source_event_id, _page)
		duration = maxf(duration, FINAL_PAGE_SECONDS)
		# 下一条质疑已就绪时，末页绘制后可更快交接，仍允许摘录原文。
		if _event.has("question_id") and _elapsed >= REVIEW_HANDOFF_SECONDS:
			for event: Dictionary in _manager.get_passenger_events():
				if event.status == "resolved" and event.has("question_id") \
						and event.source_event_id != _event.source_event_id:
					duration = REVIEW_HANDOFF_SECONDS
					break
	if _elapsed < duration:
		return
	# 状态通知与换页在渲染回调之后执行，避免旧回执影响下一页。
	_page_complete = true
	_advance.call_deferred(_event.session, _event.source_event_id, _page)


func _advance(session: int, event_id: String, page: int) -> void:
	while is_inside_tree() and get_tree().paused:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	if _event.get("session") != session or _event.get("source_event_id") != event_id or _page != page:
		return
	if _page + 1 < _pages.size():
		_show_page(_page + 1)
	else:
		_manager.mark_passenger_event_presented(session, event_id)


func _can_read() -> bool:
	if get_tree().paused or _event.is_empty() or _page_complete or not _bubble.visible \
			or _manager.get_document_session_id() != _event.session:
		return false
	if _view.get_current_station_id() != &"main_console" or _view.is_turning() \
			or _terminal.target_open or _terminal.open_progress > 0.0 or _terminal.is_input_captured():
		return false
	var player_viewport := _screen.get_viewport()
	var camera := player_viewport.get_camera_3d()
	var quad := _screen.mesh as QuadMesh
	if camera == null or quad == null or not _screen.is_visible_in_tree() \
			or not _screen.get_window().has_focus():
		return false
	var viewport_rect := player_viewport.get_visible_rect()
	var rect := _bubble.get_rect()
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y),
		Vector2(rect.position.x, rect.end.y), rect.end, rect.get_center()]
	var space := camera.get_world_3d().direct_space_state
	for pixel: Vector2 in corners:
		var uv := pixel / Vector2(size)
		var target := _screen.to_global(Vector3((uv.x - 0.5) * quad.size.x, (0.5 - uv.y) * quad.size.y, 0.01))
		if camera.is_position_behind(target) or not viewport_rect.has_point(camera.unproject_position(target)):
			return false
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, target)
		if not space.intersect_ray(ray).is_empty():
			return false
	return true


func get_current_event_id() -> String:
	return _event.get("source_event_id", "") if _bubble.visible else ""


func _confirm_final_draw(session: int, event_id: String, page: int) -> void:
	while is_inside_tree() and get_tree().paused:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	if _event.get("session") == session and _event.get("source_event_id") == event_id and _page == page:
		_manager.note_passenger_event_drawn(session, event_id)

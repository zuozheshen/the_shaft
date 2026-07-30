class_name ElevatorDoorVisual3D
extends Node3D


enum DoorPresentationState {
	CLOSED,
	OPENING,
	OPEN,
	CLOSING,
}


signal door_state_changed(state: DoorPresentationState)
signal door_opened
signal door_closed
signal door_busy_changed(is_busy: bool)


const ANIMATION_RESET: StringName = &"RESET"
const ANIMATION_OPEN: StringName = &"door_open"
const ANIMATION_CLOSE: StringName = &"door_close"

@export var animation_player_path: NodePath
@export var audio_player_path: NodePath

var _animation_player: AnimationPlayer
var _audio_player: AudioStreamPlayer3D
var _door_state: DoorPresentationState = DoorPresentationState.CLOSED
var _is_visual_ready: bool = false


func _ready() -> void:
	_initialize_animation_player()
	_initialize_audio_player()
	# 场景保存在哪个关键帧都不可靠，运行时统一恢复为关闭姿态。
	snap_closed()


func request_open() -> bool:
	if _door_state != DoorPresentationState.CLOSED or not _is_visual_ready:
		return false

	_change_state(DoorPresentationState.OPENING)
	if _play_animation(ANIMATION_OPEN):
		return true

	# 表现资源运行时失效时恢复稳定状态，不把错误传播到业务门控。
	_change_state(DoorPresentationState.CLOSED)
	_apply_animation_end_pose(ANIMATION_RESET)
	return false


func request_close() -> bool:
	if _door_state != DoorPresentationState.OPEN or not _is_visual_ready:
		return false

	_change_state(DoorPresentationState.CLOSING)
	if _play_animation(ANIMATION_CLOSE):
		return true

	# 关闭动画无法启动时仍维持开启姿态，等待上层执行一次同步恢复。
	_change_state(DoorPresentationState.OPEN)
	_apply_animation_end_pose(ANIMATION_OPEN)
	return false


func snap_open() -> void:
	_apply_animation_end_pose(ANIMATION_OPEN)
	_change_state(DoorPresentationState.OPEN)


func snap_closed() -> void:
	if not _apply_animation_end_pose(ANIMATION_RESET):
		_apply_animation_end_pose(ANIMATION_CLOSE)
	_change_state(DoorPresentationState.CLOSED)


func get_door_state() -> DoorPresentationState:
	return _door_state


func is_busy() -> bool:
	return _door_state in [
		DoorPresentationState.OPENING,
		DoorPresentationState.CLOSING,
	]


func is_open() -> bool:
	return _door_state == DoorPresentationState.OPEN


func is_closed() -> bool:
	return _door_state == DoorPresentationState.CLOSED


func is_ready_for_commands() -> bool:
	return _is_visual_ready


func get_animation_player() -> AnimationPlayer:
	return _animation_player


func _initialize_animation_player() -> void:
	if animation_player_path.is_empty():
		push_error("双开门视觉缺少 AnimationPlayer 的 NodePath 配置。")
		return

	var candidate := get_node_or_null(animation_player_path)
	if not candidate is AnimationPlayer:
		var actual_type := "null" if candidate == null else candidate.get_class()
		push_error("双开门视觉的动画节点应为 AnimationPlayer，实际为 %s。" % actual_type)
		return

	_animation_player = candidate as AnimationPlayer
	if not _animation_player.animation_finished.is_connected(
			_on_animation_finished
	):
		_animation_player.animation_finished.connect(_on_animation_finished)

	var animations_valid := true
	for animation_name: StringName in [
		ANIMATION_RESET,
		ANIMATION_OPEN,
		ANIMATION_CLOSE,
	]:
		if _animation_player.has_animation(animation_name):
			continue
		animations_valid = false
		push_error("双开门视觉缺少动画：%s" % animation_name)
	_is_visual_ready = animations_valid


func _initialize_audio_player() -> void:
	if audio_player_path.is_empty():
		push_warning("双开门视觉未配置可选的 AudioStreamPlayer3D。")
		return

	var candidate := get_node_or_null(audio_player_path)
	if not candidate is AudioStreamPlayer3D:
		var actual_type := "null" if candidate == null else candidate.get_class()
		push_warning(
			"双开门视觉的音效节点应为 AudioStreamPlayer3D，实际为 %s。"
			% actual_type
		)
		return
	_audio_player = candidate as AudioStreamPlayer3D


func _play_animation(animation_name: StringName) -> bool:
	if _animation_player == null \
			or not _animation_player.has_animation(animation_name):
		push_error("双开门视觉无法播放动画：%s" % animation_name)
		return false
	_animation_player.play(animation_name)
	return true


func _apply_animation_end_pose(animation_name: StringName) -> bool:
	if _animation_player == null \
			or not _animation_player.has_animation(animation_name):
		return false
	var animation := _animation_player.get_animation(animation_name)
	if animation == null:
		return false

	# seek(update=true) 立即应用关键帧，stop(keep_state=true) 保留该姿态。
	_animation_player.play(animation_name)
	_animation_player.seek(animation.length, true)
	_animation_player.stop(true)
	return true


func _change_state(next_state: DoorPresentationState) -> void:
	if _door_state == next_state:
		return
	var was_busy := is_busy()
	_door_state = next_state
	door_state_changed.emit(_door_state)
	var busy_now := is_busy()
	if was_busy != busy_now:
		door_busy_changed.emit(busy_now)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == ANIMATION_OPEN \
			and _door_state == DoorPresentationState.OPENING:
		_change_state(DoorPresentationState.OPEN)
		door_opened.emit()
	elif animation_name == ANIMATION_CLOSE \
			and _door_state == DoorPresentationState.CLOSING:
		_change_state(DoorPresentationState.CLOSED)
		door_closed.emit()

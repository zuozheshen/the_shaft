class_name ElevatorMovementAudio
extends AudioStreamPlayer


const SILENT_VOLUME_DB: float = -60.0

@export_range(-40.0, 0.0, 1.0, "suffix:dB") var running_volume_db: float = -12.0
@export_range(0.05, 1.0, 0.05, "suffix:s") var fade_in_seconds: float = 0.25
@export_range(0.05, 1.0, 0.05, "suffix:s") var fade_out_seconds: float = 0.35

var _flow_manager: DemoFlowManager
var _last_moving: bool = false
var _fade_tween: Tween


func setup(flow_manager: DemoFlowManager) -> void:
	if _flow_manager == flow_manager:
		return
	if is_instance_valid(_flow_manager):
		if _flow_manager.case_updated.is_connected(_sync_movement):
			_flow_manager.case_updated.disconnect(_sync_movement)
		if _flow_manager.elevator_movement_completed.is_connected(_on_movement_completed):
			_flow_manager.elevator_movement_completed.disconnect(_on_movement_completed)
	_flow_manager = flow_manager
	if is_instance_valid(_flow_manager):
		_flow_manager.case_updated.connect(_sync_movement)
		_flow_manager.elevator_movement_completed.connect(_on_movement_completed)
	_sync_movement()


func _sync_movement() -> void:
	# 只读取唯一运行层的行驶状态；普通界面刷新不会重新起播或改变行驶计时。
	var moving := is_instance_valid(_flow_manager) and _flow_manager.is_elevator_moving()
	if moving == _last_moving:
		return
	_last_moving = moving
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	if moving:
		# 完整运行音效每趟从头播放一次，避免续播上一趟的收尾段。
		volume_db = SILENT_VOLUME_DB
		play(0.0)
		_fade_tween.tween_property(self, ^"volume_db", running_volume_db, fade_in_seconds)
	else:
		_fade_tween.tween_property(self, ^"volume_db", SILENT_VOLUME_DB, fade_out_seconds)
		_fade_tween.tween_callback(stop)


func _on_movement_completed(_arrived_floor: String) -> void:
	_sync_movement()

class_name PassengerVisualProfile
extends Resource


# Profile 只保存摄影棚表现参数，不承载派单、楼层或对话业务状态。
@export var passenger_id: StringName
@export var texture: Texture2D
@export var tint: Color = Color.WHITE
@export var visual_scale: Vector2 = Vector2.ONE
@export var sprite_offset: Vector3 = Vector3.ZERO
@export_range(0.0, 0.08, 0.001) var idle_amplitude: float = 0.012
@export_range(0.1, 5.0, 0.1) var idle_speed: float = 1.2
@export var dialogue_focus_height: float = 1.35
@export var shadow_scale: Vector2 = Vector2.ONE

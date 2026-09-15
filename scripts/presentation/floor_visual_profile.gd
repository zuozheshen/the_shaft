class_name FloorVisualProfile
extends Resource


## 楼层视觉独立于业务资料；字符串编号保留 004 的前导零。
@export var floor_id: StringName
@export var display_label: String = ""

@export_group("七层纹理")
@export var far_texture: Texture2D
@export var main_texture: Texture2D
@export var mid_left_texture: Texture2D
@export var mid_right_texture: Texture2D
@export var ground_texture: Texture2D
@export var front_left_texture: Texture2D
@export var front_right_texture: Texture2D

@export_group("七层显隐")
@export var far_visible: bool = true
@export var main_visible: bool = true
@export var mid_left_visible: bool = true
@export var mid_right_visible: bool = true
@export var ground_visible: bool = true
@export var front_left_visible: bool = true
@export var front_right_visible: bool = true

@export_group("色调与灯光")
@export var ambient_tint: Color = Color.WHITE
@export_range(0.0, 4.0, 0.05, "or_greater")
var light_energy_multiplier: float = 1.0


func get_safe_light_energy_multiplier() -> float:
	# 资源也可能从文本或代码赋值，不能仅依赖 Inspector 的范围限制。
	if not is_finite(light_energy_multiplier) or light_energy_multiplier < 0.0:
		push_warning("楼层视觉 %s 的灯光倍率无效，使用 1.0。" % floor_id)
		return 1.0
	return light_energy_multiplier

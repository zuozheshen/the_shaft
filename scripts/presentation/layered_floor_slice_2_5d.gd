class_name LayeredFloorSlice25D
extends Node3D


const LAYER_FAR: StringName = &"far"
const LAYER_MAIN: StringName = &"main"
const LAYER_MID_LEFT: StringName = &"mid_left"
const LAYER_MID_RIGHT: StringName = &"mid_right"
const LAYER_GROUND: StringName = &"ground"
const LAYER_FRONT_LEFT: StringName = &"front_left"
const LAYER_FRONT_RIGHT: StringName = &"front_right"

const SUPPORTED_LAYER_IDS: Array[StringName] = [
	LAYER_FAR,
	LAYER_MAIN,
	LAYER_MID_LEFT,
	LAYER_MID_RIGHT,
	LAYER_GROUND,
	LAYER_FRONT_LEFT,
	LAYER_FRONT_RIGHT,
]

@export var far_layer_path: NodePath
@export var main_layer_path: NodePath
@export var mid_left_layer_path: NodePath
@export var mid_right_layer_path: NodePath
@export var ground_layer_path: NodePath
@export var front_left_layer_path: NodePath
@export var front_right_layer_path: NodePath

var _layer_nodes: Dictionary = {}
var _fallback_states: Dictionary = {}
var _runtime_materials: Dictionary = {}


func _ready() -> void:
	# 图层路径由场景显式配置；单层失效时，其余图层仍可继续工作。
	for layer_id in SUPPORTED_LAYER_IDS:
		_cache_layer(layer_id, _get_layer_path(layer_id))


func get_supported_layer_ids() -> Array[StringName]:
	# 返回副本，避免调用方改动控制器内部约定的固定顺序。
	return SUPPORTED_LAYER_IDS.duplicate()


func get_layer_node(layer_id: StringName) -> MeshInstance3D:
	var layer := _layer_nodes.get(layer_id) as MeshInstance3D
	if layer == null:
		push_warning("分层楼层切片找不到有效图层：%s" % layer_id)
	return layer


func set_layer_visible(layer_id: StringName, is_visible: bool) -> bool:
	var layer := get_layer_node(layer_id)
	if layer == null:
		return false
	layer.visible = is_visible
	return true


func set_layer_texture(layer_id: StringName, texture: Texture2D) -> bool:
	var layer := get_layer_node(layer_id)
	if layer == null:
		return false

	var runtime_material := _runtime_materials.get(layer_id) as BaseMaterial3D
	if runtime_material == null:
		runtime_material = _create_runtime_material(layer_id, layer)
		if runtime_material == null:
			push_warning("图层 %s 无法建立独立运行时材质。" % layer_id)
			return false
		_runtime_materials[layer_id] = runtime_material
		layer.material_override = runtime_material

	# 只替换材质纹理，不触碰图层 Transform、QuadMesh 尺寸或可见状态。
	runtime_material.albedo_texture = texture
	return true


func clear_runtime_textures() -> void:
	# 恢复每个节点原有的材质入口，场景中的纯色 fallback 从未被直接修改。
	for layer_id in _runtime_materials.keys():
		var layer := _layer_nodes.get(layer_id) as MeshInstance3D
		var fallback_state := _fallback_states.get(layer_id) as Dictionary
		if layer == null or fallback_state == null:
			continue
		layer.material_override = fallback_state.get("material_override") as Material
	_runtime_materials.clear()


func _cache_layer(layer_id: StringName, node_path: NodePath) -> void:
	if node_path.is_empty():
		push_error("分层楼层切片缺少图层 %s 的 NodePath 配置。" % layer_id)
		return

	var candidate := get_node_or_null(node_path)
	if candidate == null:
		push_error("分层楼层切片找不到图层 %s：%s" % [layer_id, node_path])
		return
	if not candidate is MeshInstance3D:
		push_error("分层楼层切片的图层 %s 应为 MeshInstance3D，实际为 %s。" % [
			layer_id,
			candidate.get_class(),
		])
		return

	var layer := candidate as MeshInstance3D
	var active_material := layer.get_active_material(0)
	var fallback_color := Color.WHITE
	var fallback_texture: Texture2D
	if active_material is BaseMaterial3D:
		var base_material := active_material as BaseMaterial3D
		fallback_color = base_material.albedo_color
		fallback_texture = base_material.albedo_texture

	_layer_nodes[layer_id] = layer
	_fallback_states[layer_id] = {
		"material": active_material,
		"material_override": layer.material_override,
		"albedo_color": fallback_color,
		"albedo_texture": fallback_texture,
		"visible": layer.visible,
	}


func _create_runtime_material(
		layer_id: StringName,
		layer: MeshInstance3D
) -> BaseMaterial3D:
	var source_material := layer.get_active_material(0)
	var runtime_material: BaseMaterial3D
	if source_material is BaseMaterial3D:
		# 深复制确保修改一个图层时，不会污染 QuadMesh 或其他图层的材质。
		runtime_material = source_material.duplicate(true) as BaseMaterial3D
	else:
		runtime_material = StandardMaterial3D.new()
		var fallback_state := _fallback_states.get(layer_id) as Dictionary
		if fallback_state != null:
			runtime_material.albedo_color = fallback_state.get(
				"albedo_color",
				Color.WHITE
			) as Color

	if runtime_material == null:
		return null
	runtime_material.resource_local_to_scene = true
	runtime_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	runtime_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# 七个平面都是纯绘制环境图层；运行时副本延续当前 Unshaded 表现。
	runtime_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return runtime_material


func _get_layer_path(layer_id: StringName) -> NodePath:
	match layer_id:
		LAYER_FAR:
			return far_layer_path
		LAYER_MAIN:
			return main_layer_path
		LAYER_MID_LEFT:
			return mid_left_layer_path
		LAYER_MID_RIGHT:
			return mid_right_layer_path
		LAYER_GROUND:
			return ground_layer_path
		LAYER_FRONT_LEFT:
			return front_left_layer_path
		LAYER_FRONT_RIGHT:
			return front_right_layer_path
		_:
			return NodePath()

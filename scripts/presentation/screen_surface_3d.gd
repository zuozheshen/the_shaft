class_name ScreenSurface3D
extends MeshInstance3D


## 屏面的 Quad、UV 和显示参数在场景与材质中配置；这里只绑定实例自己的视口纹理。
func bind_viewport(feed: SubViewport, dialogue: SubViewport = null) -> bool:
	if feed == null or not mesh is QuadMesh:
		return false

	if material_override is ShaderMaterial:
		var profile := material_override as ShaderMaterial
		if profile.shader == null:
			return false
		var material := profile.duplicate() as ShaderMaterial
		material.set_shader_parameter(&"feed_texture", feed.get_texture())
		if dialogue != null:
			material.set_shader_parameter(&"dialogue_texture", dialogue.get_texture())
		material_override = material
		return true

	if material_override is StandardMaterial3D and dialogue == null:
		var material := material_override.duplicate() as StandardMaterial3D
		material.albedo_texture = feed.get_texture()
		if material.emission_enabled:
			material.emission_texture = material.albedo_texture
		material_override = material
		return true

	return false

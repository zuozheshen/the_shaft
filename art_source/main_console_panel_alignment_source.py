"""主台面板前沿对齐：从原 GLB 派生 Mesh，保留顶面与控件坐标。

用 --godot 指定 Godot，--scratch-dir 指定仓库外临时目录。
原 GLB 和 Blender 文件不变；视觉 wrapper 使用生成的两份 ArrayMesh。
"""
from pathlib import Path
import argparse
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MESH_DIR = 'assets/art/materials/main_console_v2'
SCRIPT = r'''extends SceneTree
func _initialize():
	var shell = load("res://assets/art/models/main_console_shell.glb").instantiate()
	var panels = shell.get_node("主操作台外壳")
	var camera_vertices = panels.get_node("CAMERA模块板壳").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var front_z = -1.24
	var target_y = INF
	for vertex in camera_vertices:
		if absf(vertex.z - front_z) < 0.00001:
			target_y = minf(target_y, vertex.y)
	assert(absf(target_y - 0.814903736) < 0.00001)
	# 复制原模块材质的全部参数，改用同像素的仓库纹理，避免保存内嵌大图。
	var panel_material = panels.get_node("COMM模块板壳").mesh.surface_get_material(0).duplicate()
	panel_material.albedo_texture = load("res://assets/art/textures/main_console_v2/panel_fastener_albedo.png")
	panel_material.normal_texture = load("res://assets/art/textures/main_console_v2/paint_normal.png")
	panel_material.roughness_texture = load("res://assets/art/textures/main_console_v2/paint_roughness.png")
	assert(panel_material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN)
	# 原金属度系数为0，内嵌ORM图的金属通道不参与着色。
	assert(is_zero_approx(panel_material.metallic))
	panel_material.metallic_texture = null
	var material_path = "res://assets/art/materials/main_console_v2/panel_aligned_material.tres"
	assert(ResourceSaver.save(panel_material, material_path) == OK)
	panel_material.take_over_path(material_path)
	for spec in [["COMM模块板壳", "panel_comm_aligned", 0.842903733], ["DOOR模块板壳", "panel_door_aligned", 0.824903727]]:
		var original = panels.get_node(spec[0]).mesh
		assert(original.get_surface_count() == 1)
		assert(original.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES)
		var arrays = original.surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var changed = 0
		# 只延长前沿下缘；斜顶面、后缘、UV 与索引保持原值。
		for index in vertices.size():
			if absf(vertices[index].z - front_z) < 0.00001 and absf(vertices[index].y - spec[2]) < 0.00001:
				vertices[index].y = target_y
				changed += 1
		assert(changed == 6)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		# 只更新改变坡度的下表面法线，保持原硬边、顶面法线和切线。
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var bottom_normal = Vector3.ZERO
		for triangle in range(0, indices.size(), 3):
			var first = indices[triangle]
			if normals[first].y < -0.5:
				bottom_normal = (vertices[indices[triangle + 1]] - vertices[first]).cross(vertices[indices[triangle + 2]] - vertices[first]).normalized()
				if bottom_normal.dot(normals[first]) < 0:
					bottom_normal = -bottom_normal
				break
		assert(bottom_normal.length_squared() > 0.99)
		for index in normals.size():
			if normals[index].y < -0.5:
				normals[index] = bottom_normal
		arrays[Mesh.ARRAY_NORMAL] = normals
		var aligned = ArrayMesh.new()
		aligned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		aligned.surface_set_material(0, panel_material)
		aligned.resource_name = spec[0] + "前沿对齐"
		assert(ResourceSaver.save(aligned, "res://assets/art/materials/main_console_v2/" + spec[1] + ".tres") == OK)
		print(spec[0], " front lower edge=", target_y, "; adjusted vertices=", changed)
	shell.free()
	print("PANEL ALIGNMENT SOURCE PASS")
	quit()
'''


def build(godot, scratch):
    scratch.mkdir(parents=True, exist_ok=True)
    script = scratch / 'build_panel_alignment.gd'
    script.write_text(SCRIPT, encoding='utf-8', newline='\n')
    result = subprocess.run(
        [str(godot), '--headless', '--path', str(ROOT), '--script', str(script)],
        capture_output=True, text=True, encoding='utf-8', timeout=90)
    if result.returncode or 'ERROR' in result.stderr or 'PANEL ALIGNMENT SOURCE PASS' not in result.stdout:
        raise RuntimeError(result.stdout + result.stderr)
    for name in ('panel_comm_aligned', 'panel_door_aligned', 'panel_aligned_material'):
        path = ROOT / MESH_DIR / (name + '.tres')
        text = re.sub(r' uid="uid://[^"]+"', '', path.read_text(encoding='utf-8'))
        path.write_text(text, encoding='utf-8', newline='\n')
    print(result.stdout.strip())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--scratch-dir', type=Path, required=True)
    args = parser.parse_args()
    build(args.godot, args.scratch_dir)

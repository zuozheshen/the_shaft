"""#66 PLAN v2 小样：从 V1 派生窄装配缝，不改 V1 或 ART-02。
纹理由 Python 确定性绘制；两个折边由 Godot SurfaceTool 保存为原生 ArrayMesh。
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

import numpy as np
from PIL import Image

NAMESPACE = "elevator_cabin_assembly_v2"
BASE = "assets/art/textures/elevator_cabin_v1"
MATERIALS = "assets/art/materials/" + NAMESPACE
TEXTURES = "assets/art/textures/" + NAMESPACE
DOOR_BAND = 0.006


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normal_image(vectors):
    vectors = vectors / np.maximum(np.linalg.norm(vectors, axis=-1, keepdims=True), 1e-8)
    return Image.fromarray(np.rint((vectors + 1) * 127.5).clip(0, 255).astype("uint8"))


def door_maps(base, side):
    # 实机 +Z 面 UV：左边 u=0、右边 u=1/3；只画各自朝中央的边。
    height, width = base.shape[:2]
    yy, xx = np.mgrid[:height, :width]
    u = (xx + 0.5) / width
    distance = (1 / 3 - u) * 3 * 1.04 if side == "left" else u * 3 * 1.04
    mask = (yy < height // 2) & (distance >= 0) & (distance <= DOOR_BAND)
    d = np.maximum(distance, 0)
    # 320×240 下一个源像素约10mm；在既定6mm带内保留平稳暗芯，避免被mip完全平均掉。
    shoulder = np.clip((DOOR_BAND - d) / 0.001, 0, 1)
    shadow = 0.20 * shoulder
    albedo = np.full_like(base, 255)
    values = np.rint(255 * np.power(1 - shadow, 1 / 2.2)).astype("uint8")
    albedo[mask] = values[mask, None]
    vectors = base.astype(float) / 127.5 - 1
    # 6mm 内缘浅折边；不改变 band 外任何 V1 normal 像素。
    slope = 0.48 * np.sin(np.pi * np.clip(d / DOOR_BAND, 0, 1))
    vectors[..., 0] += slope * (1 if side == "left" else -1)
    derived = np.asarray(normal_image(vectors))
    normal = base.copy()
    normal[mask] = derived[mask]
    assert np.array_equal(normal[~mask], base[~mask])
    return Image.fromarray(albedo), Image.fromarray(normal), int(mask.sum())


def seam_maps():
    yy, xx = np.mgrid[:256, :64]
    across = ((xx + 0.5) / 64 - 0.5) * 0.012
    depth = -0.00035 * np.exp(-(across / 0.0014) ** 2)
    slope = np.gradient(depth, 0.012 / 64, axis=1)
    normal = normal_image(np.stack((-slope, np.zeros_like(slope), np.ones_like(slope)), axis=-1))
    alpha = np.exp(-(across / 0.0020) ** 2)
    end = np.minimum((yy + 0.5) / 2, (256 - yy - 0.5) / 2).clip(0, 1)
    pixels = np.zeros((256, 64, 4), dtype="uint8")
    pixels[..., 3] = np.rint(alpha * end * 255).astype("uint8")
    return Image.fromarray(pixels), normal


def threshold_maps():
    yy, xx = np.mgrid[:64, :256]
    across = ((yy + 0.5) / 64 - 0.5) * 0.28
    profile = sum(np.exp(-((across - center) / 0.0025) ** 2) for center in (-0.06, 0.06))
    slope = np.gradient(-0.00025 * profile, 0.28 / 64, axis=0)
    normal = normal_image(np.stack((np.zeros_like(slope), slope, np.ones_like(slope)), axis=-1))
    end = np.minimum((xx + 0.5) / 2, (256 - xx - 0.5) / 2).clip(0, 1)
    pixels = np.zeros((64, 256, 4), dtype="uint8")
    pixels[..., 3] = np.rint(np.clip(profile, 0, 1) * end * 255).astype("uint8")
    return Image.fromarray(pixels), normal


def door_material(repo, side):
    text = (repo / "assets/art/materials/elevator_cabin_v1/door_coated_steel.tres").read_text(encoding="utf-8")
    text = text.replace("res://" + BASE + "/door_normal.png", "res://" + TEXTURES + "/door_" + side + "_normal.png")
    text = text.replace("[resource]", '[ext_resource type="Texture2D" path="res://' + TEXTURES + "/door_" + side + '_albedo.png" id="3_albedo"]\n\n[resource]')
    text = text.replace('resource_name = "ART03_door_coated_steel"', 'resource_name = "ART03_door_' + side + '_assembly"')
    text = text.replace("roughness = ", 'albedo_texture = ExtResource("3_albedo")\nroughness = ', 1)
    return text


def extrusion_faces(width, drop, length, kind):
    # 六边 L 截面一次闭合挤出，不用重叠 Box；两端也闭合。
    t = 0.002
    polygon = [(0, 0), (width, 0), (width, t), (t, t), (t, drop), (0, drop)]
    def point(a, b, end):
        return np.array((a, end, b) if kind == "corner" else (a, -b, end), dtype=float)
    ends = (0.036, 2.469) if kind == "corner" else (-length / 2, length / 2)
    faces = []
    def face(points, normal, triangles):
        # Godot 正面三角形为 clockwise；保持 winding 与显式 normal 一致。
        p = np.array(points)
        n = np.array(normal, dtype=float)
        if np.dot(np.cross(p[triangles[1]] - p[triangles[0]], p[triangles[2]] - p[triangles[0]]), n) > 0:
            triangles = [v for i in range(0, len(triangles), 3) for v in (triangles[i], triangles[i + 2], triangles[i + 1])]
        if len(points) == 4:
            uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
        else:
            uv = [(a / width, b / drop) for a, b in polygon]
        faces.append({"points": [list(v) for v in p], "normal": list(n), "uv": uv, "indices": triangles})
    for i, (a, b) in enumerate(polygon):
        aa, bb = polygon[(i + 1) % len(polygon)]
        outward = np.array((bb - b, -(aa - a)))
        outward = outward / np.linalg.norm(outward)
        n = (outward[0], 0, outward[1]) if kind == "corner" else (outward[0], -outward[1], 0)
        face([point(a, b, ends[0]), point(aa, bb, ends[0]), point(aa, bb, ends[1]), point(a, b, ends[1])], n, [0, 1, 2, 0, 2, 3])
    triangles = [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5]
    for j, end in enumerate(ends):
        n = (0, -1 if j == 0 else 1, 0) if kind == "corner" else (0, 0, -1 if j == 0 else 1)
        face([point(a, b, end) for a, b in polygon], n, triangles)
    return faces


def build_meshes(repo, output, godot, scratch):
    data = {
        "corner_fold_mesh": extrusion_faces(0.025, 0.025, 2.433, "corner"),
        "top_fold_mesh": extrusion_faces(0.020, 0.0295, 3.398, "top"),
    }
    scratch.mkdir(parents=True, exist_ok=True)
    gd = scratch / "issue66-v2-mesh-build.gd"
    serialized = json.dumps(json.dumps(data))
    directory = json.dumps(str(output / MATERIALS).replace("\\", "/"))
    code = """extends SceneTree

func _initialize() -> void:
	var meshes = JSON.parse_string(DATA_STRING)
	var material = load("res://assets/art/materials/elevator_cabin_v1/wall_paint.tres")
	for mesh_name in meshes:
		var surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(material)
		for face in meshes[mesh_name]:
			var n = face["normal"]
			for index in face["indices"]:
				var p = face["points"][index]
				var uv = face["uv"][index]
				surface.set_normal(Vector3(n[0], n[1], n[2]))
				surface.set_uv(Vector2(uv[0], uv[1]))
				surface.add_vertex(Vector3(p[0], p[1], p[2]))
		surface.generate_tangents()
		var mesh = surface.commit()
		mesh.resource_name = mesh_name
		var error = ResourceSaver.save(mesh, OUTPUT_DIRECTORY + "/" + mesh_name + ".tres")
		if error != OK:
			push_error("Cannot save assembly mesh: " + mesh_name)
			quit(1)
			return
	print("ASSEMBLY MESH BUILD PASS")
	quit(0)
""".replace("DATA_STRING", serialized).replace("OUTPUT_DIRECTORY", directory)
    gd.write_text(code, encoding="utf-8", newline="\n")
    run = subprocess.run([str(godot), "--headless", "--path", str(repo), "--script", str(gd)], capture_output=True, text=True, encoding="utf-8", timeout=60)
    if run.returncode != 0 or "ASSEMBLY MESH BUILD PASS" not in run.stdout or "ERROR" in run.stderr:
        raise RuntimeError(run.stdout + run.stderr)
    # 去掉首次保存时的随机 UID/声明 ID；场景按路径引用，重建可逐字节比较。
    for mesh_name in data:
        path = output / MATERIALS / (mesh_name + ".tres")
        text = re.sub(r' uid="uid://[^"]+"', "", path.read_text(encoding="utf-8"))
        resource_id = re.search(r'\[ext_resource[^\n]+ id="([^"]+)"', text).group(1)
        text = text.replace('id="' + resource_id + '"', 'id="1_wall"')
        text = text.replace('ExtResource("' + resource_id + '")', 'ExtResource("1_wall")')
        path.write_text(text, encoding="utf-8", newline="\n")
    print(run.stdout.strip())


def build(repo, output, godot, scratch):
    record = json.loads((repo / BASE / "material_provenance.json").read_text(encoding="utf-8"))
    for name in ("door_normal.png", "door_roughness.png"):
        if sha(repo / BASE / name) != record["outputs"][name]["sha256"]:
            raise ValueError("V1 source SHA mismatch: " + name)
    (output / MATERIALS).mkdir(parents=True, exist_ok=True)
    (output / TEXTURES).mkdir(parents=True, exist_ok=True)
    base = np.asarray(Image.open(repo / BASE / "door_normal.png").convert("RGB"))
    images, masks = {}, {}
    for side in ("left", "right"):
        albedo, normal, count = door_maps(base, side)
        images["door_" + side + "_albedo.png"] = albedo
        images["door_" + side + "_normal.png"] = normal
        masks[side] = count
        (output / MATERIALS / ("door_" + side + "_assembly.tres")).write_text(door_material(repo, side), encoding="utf-8", newline="\n")
    images["vertical_seam_albedo.png"], images["vertical_seam_normal.png"] = seam_maps()
    images["threshold_groove_albedo.png"], images["threshold_groove_normal.png"] = threshold_maps()
    for name, image in images.items():
        image.save(output / TEXTURES / name)
    build_meshes(repo, output, godot, scratch)
    manifest = {
        "issue": 66, "plan": "v2 first sample only", "baseline": "8cafcab2cacbce272dd84f2bc627935ae789d684",
        "source": {"path": BASE + "/door_normal.png", "sha256": sha(repo / BASE / "door_normal.png"), "provenance": BASE + "/material_provenance.json", "license": "project-authored structure over V1 CC0 Metal028 micro-surface"},
        "door": {"band_m_per_leaf": DOOR_BAND, "face": "+Z, u=0..1/3 v=0..1/2", "inner_edge": {"left": "u=1/3", "right": "u=0"}, "max_linear_shadow": 0.20, "changed_normal_pixels": masks, "roughness_unchanged_sha256": sha(repo / BASE / "door_roughness.png"), "outside_band_normal_unchanged": True, "mesh_uv_animation_unchanged": True},
        "decal": {"vertical_band_m": 0.012, "nominal_groove_m": 0.008, "depth_m": 0.006, "orm_emission": False, "threshold_grooves_z_m": [-0.06, 0.06]},
        "mesh": {"sheet_thickness_m": 0.002, "corner_wings_m": 0.025, "corner_y_m": [0.036, 2.469], "top_return_m": 0.020, "top_drop_m": 0.0295, "collision": False, "native_generator": "Godot SurfaceTool/ArrayMesh, no Blender or GLB"},
        "outputs": {name: {"resolution": list(image.size), "bytes": (output / TEXTURES / name).stat().st_size, "sha256": sha(output / TEXTURES / name)} for name, image in images.items()},
    }
    for name in ("corner_fold_mesh.tres", "top_fold_mesh.tres"):
        manifest["outputs"][name] = {"bytes": (output / MATERIALS / name).stat().st_size, "sha256": sha(output / MATERIALS / name)}
    (output / TEXTURES / "assembly_provenance.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("ASSEMBLY RESOURCES PASS: " + str(sum((output / TEXTURES / name).stat().st_size for name in images)) + " PNG bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--scratch-dir", type=Path, required=True)
    parser.add_argument("--output-root", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    build(repo, args.output_root.resolve() if args.output_root else repo, args.godot.resolve(), args.scratch_dir.resolve())

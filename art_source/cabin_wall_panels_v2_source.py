"""ART-07 / #72: independent painted wall geometry, metres, Godot world origin.
Run in the dedicated Blender file only:
blender cabin_wall_panels_v2.blend --background --python cabin_wall_panels_v2_source.py -- --root <worktree> --stage C --rebuild
Godot owns the four external materials; this generator never rewrites V3 scenes.
"""
import argparse
import json
import math
from pathlib import Path
import sys
import bpy
import bmesh
from mathutils import Vector

SCENE = "舱壁金属面板V2"
COLLECTION = "AgentGenerated_ART07_WallPanels"
FACE = 1.693
THICKNESS = .024
SEAM = .016
WALLS = {"Front": (-1.35, 1.35), "Left": (-1.21, 1.21),
         "Rear": (-1.10, .40), "Right": (-.75, .75)}
# 保守安装避让：只减去被既有台体遮住的墙板部分，台位和业务节点不动。
CUTOUTS = {"Front": (-1.335, 1.335, .065, 2.439),
           "Right": (-.715, .715, .635, 2.282)}

def godot_point(wall, u, height, distance):
    return {"Front": (u, height, -distance),
            "Left": (-distance, height, -u),
            "Rear": (-u, height, distance),
            "Right": (distance, height, u)}[wall]

def blender_point(point):
    x, y, z = point
    return (x, -z, y)

def subtract_rect(rect, hole):
    if hole is None:
        return [rect]
    x0, x1, y0, y1 = rect
    hx0, hx1, hy0, hy1 = hole
    a, b, c, d = max(x0, hx0), min(x1, hx1), max(y0, hy0), min(y1, hy1)
    if a >= b or c >= d:
        return [rect]
    pieces = [(x0, a, y0, y1), (b, x1, y0, y1),
              (a, b, y0, c), (a, b, d, y1)]
    return [p for p in pieces if p[1]-p[0] > .0001 and p[3]-p[2] > .0001]

def build(root, stage, rebuild=False):
    root = Path(root).resolve()
    target = root / "art_source/cabin_wall_panels_v2.blend"
    assert (root / "project.godot").is_file()
    assert Path(bpy.data.filepath).resolve() == target, "Wrong Blender source"
    assert bpy.context.scene.name == SCENE, "Wrong Scene"
    collection = bpy.data.collections.get(COLLECTION)
    assert collection is not None
    assert all(collection in o.users_collection for o in bpy.data.objects), "Unowned objects in source"
    if bpy.data.objects:
        assert rebuild, "Use --rebuild to replace only this generated asset"
        for obj in list(collection.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        for mesh in list(bpy.data.meshes):
            if mesh.users == 0:
                bpy.data.meshes.remove(mesh)
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    materials = {}
    specs = {"Main": ((.36, .415, .45, 1), .64, 0),
             "Replacement": ((.378, .43575, .4725, 1), .71, 0),
             "Trim": ((.306, .35275, .3825, 1), .48, 0),
             "Fastener": ((.25, .27, .28, 1), .48, .75)}
    for name, (color, rough, metal) in specs.items():
        material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        material.use_nodes = True
        bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        material.diffuse_color = color
        materials[name] = material
    parent = bpy.data.objects.new("CabinWallPanelsV2", None)
    collection.objects.link(parent)
    manifest = []

    def mesh_object(name, vertices, faces, material, bevel):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([blender_point(v) for v in vertices], [], faces)
        mesh.update()
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        if bevel:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=3, affect="EDGES",
                           clamp_overlap=True)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        # 4m 一次重复的正交 UV；提供导入切线，Godot 外部材质再使用世界三平面映射。
        uv = mesh.uv_layers.new(name="WallMetres")
        for polygon in mesh.polygons:
            axis = max(range(3), key=lambda a: abs(polygon.normal[a]))
            for loop_index in polygon.loop_indices:
                p = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                pair = (p.y, p.z) if axis == 0 else (p.x, p.z) if axis == 1 else (p.x, p.y)
                uv.data[loop_index].uv = (pair[0]/4.0, pair[1]/4.0)
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj.parent = parent
        mesh.materials.append(materials[material])
        # 大平面保持平整；三段小倒角以真实面法线产生边缘高光。
        for p in mesh.polygons:
            p.use_smooth = False
        manifest.append({"name": name, "material": material, "vertices": len(mesh.vertices),
                         "faces": len(mesh.polygons), "bevel_m": bevel})
        return obj

    def wall_box(name, wall, rectangles, d0, d1, material, bevel):
        vertices, faces = [], []
        cube_faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                      (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        for u0, u1, y0, y1 in rectangles:
            start = len(vertices)
            vertices += [godot_point(wall, u, y, d)
                         for d in (d0, d1) for u, y in
                         ((u0, y0), (u1, y0), (u1, y1), (u0, y1))]
            faces += [tuple(start + i for i in f) for f in cube_faces]
        return mesh_object(name, vertices, faces, material, bevel)

    for wall, seams in WALLS.items():
        ends = [-1.69, seams[0]-.008, seams[0]+.008,
                seams[1]-.008, seams[1]+.008, 1.69]
        for i in range(3):
            rect = (ends[i*2], ends[i*2+1], .065, 2.465)
            replacement = (wall == "Rear" and i == 1) or (wall == "Right" and i == 2)
            # 仅后墙一块板退后 4mm；绝不整面向玩家推入。
            face = FACE + (.004 if wall == "Rear" and i == 1 else 0)
            wall_box(f"Panel_{wall}_{i+1:02}", wall, subtract_rect(rect, CUTOUTS.get(wall)),
                     face, face+THICKNESS, "Replacement" if replacement else "Main", .003)
        for i, u in enumerate(seams):
            # 背衬建模深度 8mm；原 CSG 的 1.700m 面保留，会限制实机最深可见处。
            wall_box(f"Seam_{wall}_{i+1:02}", wall,
                     subtract_rect((u-.010, u+.010, .065, 2.465), CUTOUTS.get(wall)),
                     FACE+.008, FACE+.011, "Trim", .0005)
        wall_box(f"Top_{wall}", wall, [(-1.69, 1.69, 2.465, 2.495)],
                 FACE-.006, FACE+.008, "Trim", .002)
        wall_box(f"Bottom_{wall}", wall, [(-1.69, 1.69, .005, .065)],
                 FACE-.006, FACE+.010, "Trim", .002)

    # 四个闭合 L 型护角；45mm 翼宽、10mm 突出，不靠共面贴条表现厚度。
    for sx in (-1, 1):
        for sz in (-1, 1):
            outer, inner, end = FACE+.002, FACE-.010, FACE-.045
            profile = [(end, inner), (inner, inner), (inner, end),
                       (outer, end), (outer, outer), (end, outer)]
            verts = [(sx*x, y, sz*z) for y in (.065, 2.465) for x, z in profile]
            count = len(profile)
            faces = [tuple(range(count-1, -1, -1)), tuple(range(count, count*2))]
            faces += [(i, (i+1)%count, (i+1)%count+count, i+count) for i in range(count)]
            mesh_object(f"Corner_{sx}_{sz}", verts, faces, "Trim", .0025)

    if stage == "C":
        # 固定件只放在检修区域及边板，不在左台背后消耗 10.5mm 安全间隙。
        for index, (wall, u, y) in enumerate([("Rear", -1.40, .22), ("Rear", -1.40, 2.28),
                           ("Rear", 1.42, .22), ("Rear", 1.42, 2.28),
                           ("Right", 1.42, .22), ("Right", 1.42, 2.28)], 1):
            d = FACE-.001
            verts = [godot_point(wall, u+.011*math.cos(i*math.tau/12),
                                 y+.011*math.sin(i*math.tau/12), z)
                     for z in (d-.003, d) for i in range(12)]
            faces = [tuple(range(11, -1, -1)), tuple(range(12, 24))]
            faces += [(i, (i+1)%12, (i+1)%12+12, i+12) for i in range(12)]
            mesh_object(f"Fastener_{wall}_{index:02}", verts, faces, "Fastener", .0006)

    # 导出只有本 Collection 的静态 Mesh 和原点 Empty，标准 Y-up，无 Camera/Light/碰撞。
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parent
    bpy.ops.wm.save_as_mainfile(filepath=str(target))
    output = root / "assets/art/models/cabin_wall_panels_v2.glb"
    bpy.ops.export_scene.gltf(filepath=str(output), export_format="GLB", use_selection=True,
                             export_yup=True, export_cameras=False, export_lights=False,
                             export_texcoords=True, export_normals=True, export_materials="EXPORT")
    print(json.dumps({"source": str(target), "export": str(output), "stage": stage,
                      "objects": manifest, "root": parent.name, "face_m": FACE,
                      "panel_thickness_m": THICKNESS, "seam_width_m": SEAM}, ensure_ascii=False))
    return manifest

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--stage", choices=("A", "C"), default="C")
    parser.add_argument("--rebuild", action="store_true")
    opts = parser.parse_args(args)
    build(opts.root, opts.stage, opts.rebuild)

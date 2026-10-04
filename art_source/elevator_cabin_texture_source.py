"""#66 舱体微表面：已校验 CC0 喷漆来源 + 自制防滑颗粒和低强度磨亮。
只派生六张实际使用的 Normal/Roughness，不读写 ART-02 成品或运行时状态。
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageFilter
import PIL

SIZE = 1024
SEED = 66


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def source_maps(archive, repo):
    record = json.loads((repo / "assets/art/textures/main_console_v2/material_provenance.json").read_text(encoding="utf-8"))["sources"]
    record = next(item for item in record if item["asset"] == "Metal028")
    raw = archive.read_bytes()
    if sha(raw) != record["archive_sha256"]:
        raise ValueError("CC0 source archive SHA mismatch")
    maps = {}
    with ZipFile(io.BytesIO(raw)) as bundle:
        for item in record["maps_used"]:
            data = bundle.read(item["file"])
            if sha(data) != item["sha256"]:
                raise ValueError("CC0 source map SHA mismatch: " + item["file"])
            maps[item["map"]] = Image.open(io.BytesIO(data)).copy()
    return maps, record


def normal_image(vectors):
    vectors = vectors / np.maximum(np.linalg.norm(vectors, axis=2, keepdims=True), 1e-8)
    return Image.fromarray(np.rint((vectors + 1.0) * 127.5).clip(0, 255).astype("uint8"))


def paint_normal(image):
    # 与 #64 同源；此处不添加主台通风/螺丝/密封带保留区。
    image = image.convert("RGB").filter(ImageFilter.GaussianBlur(1.2))
    xy = (np.asarray(image, dtype=float)[..., :2] / 127.5 - 1) * 0.35
    z = np.sqrt(np.maximum(0, 1 - np.sum(xy * xy, axis=2)))
    return normal_image(np.dstack((xy, z)))


def paint_roughness(image):
    image = image.convert("L")
    field = np.asarray(image, dtype=float) - np.asarray(image.filter(ImageFilter.GaussianBlur(8)), dtype=float)
    high = np.clip(field / max(float(np.std(field)), 1), -2, 2)
    return Image.fromarray(np.rint(247 + 3 * high).astype("uint8"))


def floor_maps():
    rng = np.random.default_rng(SEED)
    grain = rng.normal(0, 1, (SIZE, SIZE))
    # 环绕卷积使 tile 接边连续；高频只作为橡胶细颗粒，不形成随机大斑。
    for _ in range(2):
        grain = (grain * 4 + np.roll(grain, 1, 0) + np.roll(grain, -1, 0)
                 + np.roll(grain, 1, 1) + np.roll(grain, -1, 1)) / 8
    grain = np.clip(grain / float(np.std(grain)), -2, 2)
    gx = (np.roll(grain, -1, 1) - np.roll(grain, 1, 1)) * 0.035
    gy = (np.roll(grain, -1, 0) - np.roll(grain, 1, 0)) * 0.035
    normal = normal_image(np.dstack((-gx, gy, np.ones_like(grain))))
    yy, xx = np.mgrid[:SIZE, :SIZE] / SIZE
    polish = np.maximum(
        np.exp(-((xx - 0.45) / 0.018) ** 2 - ((yy - 0.57) / 0.10) ** 2),
        np.exp(-((xx - 0.55) / 0.018) ** 2 - ((yy - 0.50) / 0.10) ** 2),
    )
    delta = np.rint(polish * 11)
    fraction = float(np.mean(delta > 0))
    if fraction > 0.05:
        raise ValueError("Floor polish exceeds approved area")
    rough = Image.fromarray(np.rint(247 + grain * 3 - delta).clip(0, 255).astype("uint8"))
    return normal, rough, fraction


def door_maps(normal, roughness):
    # 原生 BoxMesh 的 3×2 UV：六面共享一个 atlas，不改变 Mesh/UV 或动画轴。
    atlas_n = Image.new("RGB", (SIZE, SIZE))
    atlas_r = Image.new("L", (SIZE, SIZE))
    total_polished = 0
    for row in range(2):
        for column in range(3):
            left, right = round(column * SIZE / 3), round((column + 1) * SIZE / 3)
            top, bottom = row * SIZE // 2, (row + 1) * SIZE // 2
            width, height = right - left, bottom - top
            atlas_n.paste(normal.resize((width, height), Image.Resampling.BOX), (left, top))
            base = np.asarray(roughness.resize((width, height), Image.Resampling.BOX), dtype=float)
            yy, xx = np.mgrid[:height, :width]
            edge_distance = np.minimum.reduce([xx, width - 1 - xx, yy, height - 1 - yy])
            mask = np.clip(1 - edge_distance / 2.0, 0, 1)
            delta = np.rint(mask * 12)
            total_polished += int(np.sum(delta > 0))
            atlas_r.paste(Image.fromarray(np.rint(base - delta).clip(0, 255).astype("uint8")), (left, top))
    fraction = total_polished / (SIZE * SIZE)
    if fraction > 0.03:
        raise ValueError("Door polish exceeds approved area")
    return atlas_n, atlas_r, fraction


def build(output, archive):
    repo = Path(__file__).resolve().parents[1]
    maps, record = source_maps(archive, repo)
    output.mkdir(parents=True, exist_ok=True)
    paint_n = paint_normal(maps["NormalGL"])
    paint_r = paint_roughness(maps["Roughness"])
    floor_n, floor_r, floor_fraction = floor_maps()
    door_n, door_r, door_fraction = door_maps(paint_n, paint_r)
    images = {"paint_normal.png": paint_n, "paint_roughness.png": paint_r,
              "floor_normal.png": floor_n, "floor_roughness.png": floor_r,
              "door_normal.png": door_n, "door_roughness.png": door_r}
    outputs = {}
    for name, image in images.items():
        target = output / name
        image.save(target)
        outputs[name] = {"resolution": list(image.size), "bytes": target.stat().st_size,
                         "sha256": sha(target.read_bytes())}
    provenance = {
        "issue": 66,
        "sources": [record],
        "source_reuse": "Only the SHA-verified Metal028 NormalGL/Roughness source; no ART-02 output images modified.",
        "derivation": {
            "normal_direction": "OpenGL +Y; vector normalization; no sRGB conversion for data maps",
            "paint": {"normal_xy_scale": 0.35, "normal_prefilter_px": 1.2,
                      "roughness_highpass_px": 8, "roughness_multiplier": "247 +/- 6"},
            "floor": {"source": "project-authored periodic grain", "seed": SEED,
                      "tile_meters": 4, "texel_per_meter": 256,
                      "polish_area_fraction": floor_fraction, "polish_max_reduction_255": 11},
            "door": {"layout": "native BoxMesh 3x2 UV", "polish_area_fraction": door_fraction,
                     "polish_max_reduction_255": 12, "geometry_uv_changed": False},
        },
        "roughness_targets": {"wall": 0.68, "ceiling": 0.76, "floor": 0.88,
                              "door": 0.54, "frame": 0.62, "trim": 0.86},
        "generator_libraries": {"Pillow": PIL.__version__, "NumPy": np.__version__},
        "outputs": outputs,
    }
    (output / "material_provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"outputs": len(outputs), "bytes": sum(item["bytes"] for item in outputs.values()),
                      "floor_polish_area": floor_fraction, "door_polish_area": door_fraction}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--source-archive", required=True, type=Path)
    args = parser.parse_args()
    build(args.output, args.source_archive)

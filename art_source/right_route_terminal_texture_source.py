"""ART-06: 六个固定件的共用小Atlas；不包含动态显示或操作文本。"""
from pathlib import Path
import argparse, hashlib, json
from PIL import Image, ImageDraw

def build(repo: Path) -> None:
    output = repo / 'assets/art/textures/right_route_terminal_v1'
    output.mkdir(parents=True, exist_ok=True)
    atlas = Image.new('RGBA', (256, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    draw.ellipse((23, 23, 105, 105), fill=(119, 120, 113, 255), outline=(44, 48, 46, 255), width=4)
    draw.arc((28, 28, 100, 100), 190, 280, fill=(157, 158, 147, 255), width=3)
    draw.line((38, 64, 90, 64), fill=(38, 41, 39, 255), width=5)
    draw.rectangle((160, 61, 255, 65), fill=(46, 50, 47, 220))
    atlas.save(output / 'right_route_detail_atlas.png')
    (output / 'right_route_detail_atlas.json').write_text(json.dumps({
        'resolution': [256, 128],
        'tiles': {'fastener': [0, 0, 128, 128], 'seam': [160, 0, 96, 128]},
        'coordinates': 'pixels from top left; rectangles [x,y,width,height]',
        'usage': 'six fixed fastener marks and one service-cover seam; no hotspots, no dynamic text',
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    shared = repo / 'assets/art/textures/main_console_v2'
    reused = [{'path': p.relative_to(repo).as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in [shared / n for n in ['paint_normal.png', 'paint_roughness.png', 'control_normal_256.png', 'control_roughness_256.png']]]
    provenance = {
        'issue': 71,
        'atlas': 'project-authored fastener/seam marks; generated with Pillow, no font or remote download',
        'atlas_sha256': hashlib.sha256((output / 'right_route_detail_atlas.png').read_bytes()).hexdigest(),
        'micro_surface_sources': json.loads((shared / 'material_provenance.json').read_text(encoding='utf-8'))['sources'],
        'reused_maps': reused,
        'palette': 'same warm gray as ART-05 shell; ART-02 functional panel gray; localized dark Bakelite grip',
        'uv': 'paint v=0.02..0.46, excludes main-console reserved upper-image assembly tile',
        'normal': 'existing OpenGL +Y maps; paint 0.45, controls 0.75',
        'roughness': '247/255-centered maps; compensated factors: body .48, panel .54, frame .70, cap/grip .78',
        'license': 'shared maps retain existing CC0 provenance; atlas project-authored',
    }
    (output / 'material_provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    build(parser.parse_args().repo.resolve())

"""ART-05 固定标签Atlas；只写本Issue纹理目录，不下载或改主台贴图。"""
from pathlib import Path
import hashlib
import json
import argparse
from PIL import Image, ImageDraw, ImageFont


def build(repo: Path) -> None:
    output = repo / 'assets/art/textures/left_archive_terminal_v1'
    output.mkdir(parents=True, exist_ok=True)
    en_font = ImageFont.load_default(size=23)
    cn_path = Path('C:/Windows/Fonts/msyh.ttc')
    cn_font = ImageFont.truetype(str(cn_path), size=24)
    atlas = Image.new('RGB', (1024, 512), (195, 192, 184))
    draw = ImageDraw.Draw(atlas)
    ink = (30, 34, 35)
    tiles = {}
    for index, (key, english, chinese) in enumerate([
        ('passenger', 'PASSENGER FILE', '乘客档案'),
        ('transcript', 'TRANSCRIPT', '对话记录'),
        ('system', 'SYSTEM LOG', '系统日志'),
        ('scroll', 'SCROLL', '上下阅读'),
    ]):
        x = index * 256
        tiles[key] = [x + 8, 128 + 8, 240, 112]
        draw.rectangle((x + 8, 136, x + 247, 247), outline=(124, 125, 118), width=2)
        draw.text((x + 128, 172), english, font=en_font, fill=ink, anchor='mm')
        draw.text((x + 128, 217), chinese, font=cn_font, fill=ink, anchor='mm')
    tiles['title'] = [8, 37, 752, 34]
    draw.text((384, 54), 'ARCHIVE TERMINAL  /  档案终端', font=cn_font, fill=ink, anchor='mm')
    # 细接缝与固定螺丝使用Atlas；不添加装饰按钮或螺丝Mesh。
    tiles['fastener'] = [800, 16, 96, 96]
    draw.ellipse((824, 40, 872, 88), fill=(114, 115, 111), outline=(48, 51, 50), width=3)
    draw.line((832, 64, 864, 64), fill=(45, 48, 47), width=4)
    tiles['seam'] = [16, 320, 992, 48]
    draw.rectangle((16, 339, 1007, 343), fill=(86, 91, 89))
    atlas.save(output / 'left_archive_detail_atlas.png')
    (output / 'left_archive_detail_atlas.json').write_text(json.dumps({
        'resolution': [1024, 512], 'tiles': tiles,
        'coordinates': 'pixels from top left; rectangles [x,y,width,height]',
        'runtime': 'fixed shell labels; never attached to a rotating or pressing axis',
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    shared = repo / 'assets/art/textures/main_console_v2'
    reused = []
    for name in ['paint_normal.png', 'paint_roughness.png', 'control_normal_256.png', 'control_roughness_256.png']:
        path = shared / name
        reused.append({'path': path.relative_to(repo).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    sources = json.loads((shared / 'material_provenance.json').read_text(encoding='utf-8'))['sources']
    provenance = {
        'issue': 69, 'atlas': 'project-authored functional labels, seam and fastener marks',
        'fonts': {'english': 'Pillow bundled default font', 'chinese': 'Microsoft YaHei from local Windows; rasterized labels only, no font redistribution', 'local_font_sha256': hashlib.sha256(cn_path.read_bytes()).hexdigest()},
        'micro_surface_sources': sources, 'reused_maps': reused,
        'uv': 'paint uses image lower half only (UV v=0.02..0.48); excludes main console reserved upper-image assembly tile',
        'normal': 'existing OpenGL +Y maps; paint strength 0.45, controls 0.75',
        'roughness': 'existing 247/255-centered maps, factor compensates to paint 0.48 / frame 0.70 / cap 0.78',
        'license': 'shared micro maps retain existing CC0 provenance; no remote downloads',
    }
    (output / 'material_provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    build(parser.parse_args().repo.resolve())

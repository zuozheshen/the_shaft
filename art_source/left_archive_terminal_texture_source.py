"""ART-05 固定标签Atlas；只写本Issue纹理目录，不下载或改主台贴图。"""
from pathlib import Path
import hashlib
import json
import argparse
from PIL import Image, ImageDraw, ImageFont


def build(repo: Path) -> None:
    output = repo / 'assets/art/textures/left_archive_terminal_v1'
    output.mkdir(parents=True, exist_ok=True)
    cn_path = Path('C:/Windows/Fonts/msyh.ttc')
    cn_font = ImageFont.truetype(str(cn_path), size=36)
    atlas = Image.new('RGB', (1024, 512), (195, 192, 184))
    draw = ImageDraw.Draw(atlas)
    ink = (30, 34, 35)
    tiles = {}
    for index, (key, chinese) in enumerate([
        ('passenger', '乘客档案'),
        ('transcript', '对话记录'),
        ('system', '系统日志'),
        ('scroll', '滚动'),
    ]):
        x = index * 256
        # UV裁切与铭牌比例一致，让单行中文字形保持原比例。
        width = 172 if key == 'scroll' else 240
        left = x + (256 - width) // 2
        tiles[key] = [left, 136, width, 86]
        draw.rectangle((left, 136, left + width - 1, 221), outline=(124, 125, 118), width=2)
        draw.text((x + 128, 179), chinese, font=cn_font, fill=ink, anchor='mm')
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
        'fonts': {'chinese': 'Microsoft YaHei from local Windows; rasterized labels only, no font redistribution', 'local_font_sha256': hashlib.sha256(cn_path.read_bytes()).hexdigest()},
        'micro_surface_sources': sources, 'reused_maps': reused,
        'uv': 'paint uses image lower half only (UV v=0.02..0.48); excludes main console reserved upper-image assembly tile',
        'normal': 'existing OpenGL +Y maps; paint strength 0.45, controls 0.75',
        'roughness': 'existing 247/255-centered maps, factor compensates to body 0.48 / functional panel 0.54 / frame 0.70 / cap 0.78',
        'functional_panel': 'main console module gray: sRGB [128,128,128], copied as a uniform color without its assembly tiles',
        'license': 'shared micro maps retain existing CC0 provenance; no remote downloads',
    }
    (output / 'material_provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    build(parser.parse_args().repo.resolve())

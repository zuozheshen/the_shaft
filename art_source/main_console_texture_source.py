"""#64 混合材质派生源。官方 CC0 微表面 + 本地确定性 Atlas。

用 Python + Pillow + NumPy 执行；输出目录为位置参数，--sources 指向仓库外已校验的素材目录。
只生成实际需要的通道，简单颜色/金属度留给共享材质。
"""
from pathlib import Path
import argparse
import json
import hashlib
import io
from zipfile import ZipFile
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter


def load_source_provenance(sources):
    local_record = sources / 'source-provenance.json'
    if local_record.exists():
        return json.loads(local_record.read_text(encoding='utf-8'))
    record = Path(__file__).resolve().parents[1] / 'assets/art/textures/main_console_v2/material_provenance.json'
    return json.loads(record.read_text(encoding='utf-8'))['sources']


def source_image(sources, asset, channel):
    filename = f'{asset}_1K-PNG_{channel}.png'
    provenance = load_source_provenance(sources)
    record = next(row for row in provenance if row['asset'] == asset)
    expected = next(row['sha256'] for row in record['maps_used'] if row['map'] == channel)
    path = sources / filename
    if path.exists():
        raw = path.read_bytes()
    else:
        archive = sources / f'{asset}_1K-PNG.zip'
        assert hashlib.sha256(archive.read_bytes()).hexdigest() == record['archive_sha256'], archive
        with ZipFile(archive) as pack:
            raw = pack.read(filename)
    assert hashlib.sha256(raw).hexdigest() == expected, filename
    image = Image.open(io.BytesIO(raw))
    assert image.size == (1024, 1024)
    return image


def derived_normal(image, size, strength):
    # 在向量空间缩放 XY，重建 Z；使用 OpenGL +Y，不做颜色空间转换。
    normal = np.asarray(image.convert('RGB').resize((size, size), Image.Resampling.BOX), dtype=float) / 127.5 - 1
    normal[..., :2] *= strength
    normal[..., 2] = np.sqrt(np.maximum(0, 1 - np.sum(normal[..., :2] ** 2, axis=2)))
    normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1e-8)
    return Image.fromarray(np.rint((normal + 1) * 127.5).clip(0, 255).astype('uint8'))


def derived_roughness(image, size):
    image = image.convert('L')
    field = np.asarray(image, dtype=float)
    # 剔除照片/原材质中的大尺度斑纹；只采用细颗粒，不烘入脏污或指印。
    high = field - np.asarray(image.filter(ImageFilter.GaussianBlur(8)), dtype=float)
    high = np.clip(high / max(float(np.std(high)), 1.0), -2, 2)
    multiplier = Image.fromarray(np.rint(247 + 3 * high).astype('uint8'))
    return multiplier.resize((size, size), Image.Resampling.BOX)


def grille_normal(size=256):
    yy, xx = np.mgrid[:size, :size]
    pitch = 7 * size / 240
    dx = (xx + 0.5) % pitch - pitch / 2
    dy = (yy + 0.5) % pitch - pitch / 2
    depth = -0.85 * np.exp(-(dx * dx + dy * dy) / 1.6)
    gy, gx = np.gradient(depth)
    normal = np.stack((-gx, gy, np.ones_like(gx)), axis=2)
    normal /= np.linalg.norm(normal, axis=2, keepdims=True)
    return Image.fromarray(np.rint((normal + 1) * 127.5).astype('uint8'))


def build_micro(output, sources):
    output.mkdir(parents=True, exist_ok=True)
    for asset, prefix, sizes, strength in [('Metal028', 'paint', [1024], 0.65),
                                          ('Plastic013A', 'control', [512, 256], 0.55)]:
        for size in sizes:
            suffix = '' if prefix == 'paint' else '_' + str(size)
            derived_roughness(source_image(sources, asset, 'Roughness'), size).save(output / f'{prefix}_roughness{suffix}.png')
            derived_normal(source_image(sources, asset, 'NormalGL'), size, strength).save(output / f'{prefix}_normal{suffix}.png')
    # 微弱触摸磨亮只留在帽 UV 中央小圆，掩膜面积小于2%，无 albedo 磨损。
    for size in [512, 256]:
        path = output / f'control_roughness_{size}.png'
        rough = np.asarray(Image.open(path), dtype=float)
        yy, xx = np.mgrid[:size, :size]
        distance = np.hypot(xx / size - 0.5, yy / size - 0.5)
        mask = np.clip((0.065 - distance) / 0.025, 0, 1)
        assert float(np.mean(mask > 0)) < 0.02
        Image.fromarray(np.rint(rough - mask * 4).astype('uint8')).save(path)
    # 四个既有色区：底座金属、PTT塑料、鹅颈/黑漆、麦头规则自制网罩。
    normal = Image.new('RGB', (512, 512), (128, 128, 255))
    normal.paste(derived_normal(source_image(sources, 'Metal028', 'NormalGL'), 256, 0.65), (0, 0))
    normal.paste(derived_normal(source_image(sources, 'Plastic013A', 'NormalGL'), 256, 0.55), (256, 0))
    normal.paste(derived_normal(source_image(sources, 'Metal028', 'NormalGL'), 256, 0.35), (0, 256))
    normal.paste(grille_normal(), (256, 256))
    normal.save(output / 'microphone_normal.png')
    provenance = load_source_provenance(sources)
    (output / 'material_provenance.json').write_text(json.dumps({
        'sources': provenance, 'derivation': {'normal': 'OpenGL +Y; BOX resize; scale XY; rebuild and normalize Z',
        'paint_xy_strength': 0.65, 'plastic_xy_strength': 0.55,
        'roughness': '8px Gaussian high-pass, clipped +/-2 sigma; 247 +/-6 multiplier',
        'contact_polish': 'roughness only; <=1.33% UV mask; <=4/255 reduction',
        'grille': 'local regular holes; gradient normal; no external grille image'},
        'no_external_albedo': True, 'generator_libraries': {'Pillow': '12.3.0', 'NumPy': '2.3.5'}
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def build_atlas(output):
    # 图案库提供复用单元；实际主台不必使用螺丝、铆钉或通风条。
    atlas = Image.new('RGB', (1024, 1024), (195, 192, 184))
    draw = ImageDraw.Draw(atlas)
    index = {'resolution': [1024, 1024], 'padding_px': 8,
             'source': 'deterministic local drawing; no downloaded or generated images',
             'tiles': {}}
    for row in range(2):
        for col in range(8):
            x, y = col * 128, row * 128
            kind = ['screw', 'rivet', 'vent', 'groove'][col % 4]
            index['tiles'][f'{kind}_{row}_{col}'] = [x + 8, y + 8, 112, 112]
            if kind in ['screw', 'rivet']:
                draw.ellipse((x+42, y+42, x+86, y+86), fill=(145,145,145), outline=(112,112,112), width=2)
                if kind == 'screw':draw.line((x+51, y+64, x+77, y+64), fill=(86,86,86), width=3)
            elif kind == 'vent':
                for line_y in range(y+39, y+92, 10):
                    draw.rounded_rectangle((x+28,line_y,x+100,line_y+3),radius=1,fill=(104,104,104))
            else:draw.line((x+22,y+64,x+106,y+64),fill=(151,151,151),width=2)
    for col in range(4):
        x, y = col*256, 256
        if col == 0:
            draw.rounded_rectangle((x+16,y+16,x+240,y+240),radius=3,outline=(151,151,151),width=2)
            index['tiles']['blank_frame']=[x+8,y+8,240,240]
        elif col == 1:
            draw.rectangle((x+8,y+8,x+247,y+247), fill=(37,37,37))
            for yy in range(y+12,y+247,7):
                for xx in range(x+12,x+247,7):
                    draw.ellipse((xx,yy,xx+2,yy+2),fill=(27,27,27))
            index['tiles']['microphone_grille']=[x+8,y+8,240,240]
        else:
            # 无脏污的可复用板面，只含很浅的线框。
            draw.rectangle((x+24,y+24,x+232,y+232),outline=(177,177,177),width=1)
            index['tiles'][f'plain_panel_{col}']=[x+8,y+8,240,240]
    labels=['COMM','CAMERA SELECT','DOOR CONTROL','STATUS','CAM 01','CAM 02',
            'OPEN','CLOSE','TX','DOOR','FAULT','UNIT 01']
    plate_ratios={'COMM':.34/.03,'CAMERA SELECT':.42/.03,'DOOR CONTROL':.54/.03,
                  'STATUS':.32/.03,'CAM 01':.145/.038,'CAM 02':.145/.038,
                  'OPEN':.18/.04,'CLOSE':.18/.04,'TX':3,'DOOR':3,'FAULT':3}
    for number,label in enumerate(labels):
        x=(number%2)*512;y=512+(number//2)*64
        ratio=plate_ratios.get(label,10)
        width=min(480,round(48*ratio));height=round(width/ratio)
        left=x+256-width//2;top=y+32-height//2
        draw.rectangle((left,top,left+width-1,top+height-1),fill=(203,200,192),outline=(159,157,151),width=1)
        font=ImageFont.load_default(size=round(height*(1.0 if ratio>10 else .9)))
        center=x+256-(width*.065/.34 if label=='COMM' else 0)
        draw.text((center,y+32),label,font=font,fill=(30,30,30),anchor='mm')
        index['tiles'][label]=[left,top,width,height]
    for number,label in enumerate(['CAMERA','01','02','UNIT / 01']):
        x=number*256;y=896
        draw.rectangle((x+8,y+8,x+247,y+119),outline=(159,157,151),width=1)
        draw.text((x+128,y+64),label,font=ImageFont.load_default(size=36),fill=(42,42,42),anchor='mm')
        index['tiles'][label]=[x+8,y+8,240,112]
    atlas.save(output/'main_console_detail_atlas.png')
    (output/'main_console_detail_atlas.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def build_surface_details(output):
    # 单个CRT散热/检修条：1处通风、2个固定螺丝，不铺满其他模块。
    atlas = Image.open(output / 'main_console_detail_atlas.png').convert('RGB')
    index = json.loads((output / 'main_console_detail_atlas.json').read_text(encoding='utf-8'))
    plate = Image.new('RGB', (72, 450), (86, 89, 96))
    draw = ImageDraw.Draw(plate)
    draw.rounded_rectangle((11, 145, 61, 270), radius=2, outline=(64, 66, 72), width=1)
    x, y, width, height = index['tiles']['vent_0_2']
    vents = atlas.crop((x, y, x + width, y + height)).convert('L').resize((48, 96), Image.Resampling.BOX)
    # Atlas中的槽形作为遮罩；最终项目颜色保持近黑/灰，不采外部Albedo。
    mask = Image.fromarray((np.asarray(vents) < 150).astype('uint8') * 255)
    plate.paste((27, 29, 32), (12, 161), mask)
    x, y, width, height = index['tiles']['screw_0_0']
    screw = atlas.crop((x, y, x + width, y + height)).resize((14, 14), Image.Resampling.BOX).convert('L')
    screw_mask = Image.fromarray((np.asarray(screw) < 170).astype('uint8') * 255)
    for position in [(29, 145), (29, 254)]:
        plate.paste((56, 58, 63), position, screw_mask)
    draw.text((36, 291), 'UNIT 01', font=ImageFont.load_default(size=10), fill=(177, 178, 180), anchor='mm')
    albedo = Image.new('RGB', (1024, 1024), (86, 89, 96))
    albedo.paste(plate, (96, 32))
    albedo.save(output / 'module_detail_albedo.png')
    # 各既有普通UV的v<0.5；唯一指定前脸使用v=542..992/1024保留区。
    normal_path = output / 'paint_normal.png'
    normal = np.asarray(Image.open(normal_path), dtype=float) / 127.5 - 1
    height = np.zeros((1024, 1024), dtype=float)
    height[32:482, 96:168] = np.where(np.asarray(plate).mean(axis=2) < 45, -0.7, 0)
    gy, gx = np.gradient(height)
    normal[..., 0] -= gx
    normal[..., 1] += gy
    normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1e-8)
    Image.fromarray(np.rint((normal + 1) * 127.5).clip(0, 255).astype('uint8')).save(normal_path)
    index['applied_details'] = {'CRT右厚框': {'face_normal': [0, -1, 0], 'uv_rect_pixels': [96, 542, 72, 450],
        'vent_banks': 1, 'fasteners': 2, 'identifier': 'UNIT 01',
        'reason': 'CRT housing cooling/service strip', 'new_geometry': False}}
    (output / 'main_console_detail_atlas.json').write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    provenance_path = output / 'material_provenance.json'
    provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
    # 正式FOV70下预过滤喷漆高频法线；C图案像素保持，避免增强通风/编号。
    normal_path = output / 'paint_normal.png'
    original = Image.open(normal_path).convert('RGB')
    filtered = original.filter(ImageFilter.GaussianBlur(1.2))
    protected = (88, 24, 176, 490)
    filtered.paste(original.crop(protected), protected[:2])
    filtered.save(normal_path)
    provenance['derivation']['paint_normal_prefilter'] = {'method': 'GaussianBlur', 'radius_pixels': 1.2, 'protected_rect': list(protected)}
    provenance['material_normal_scales'] = {'paint': 0.45, 'control_imported': 0.75, 'microphone_base_ptt': 0.85, 'microphone_neck_grille': 0.75, 'Godot_cap_overrides': 0.75, 'CRT_detail': 0.24}
    provenance['material_roughness_targets'] = {'body': 0.48, 'module': 0.54, 'camera_module': 0.50, 'dark_backing': 0.70, 'frames': 0.46, 'caps': 0.78, 'microphone_base': 0.48, 'microphone_ptt': 0.78, 'microphone_neck_grille': 0.90}
    provenance['self_made_details'] = index['applied_details']
    provenance['outputs'] = {file.name: {'resolution': list(Image.open(file).size),
        'sha256': hashlib.sha256(file.read_bytes()).hexdigest()} for file in sorted(output.glob('*.png'))}
    provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def build_microphone(output):
    # 四个色区保留原来的三材质槽；网罩只分配给麦头，底座和鹅颈不加孔。
    atlas = Image.open(output/'main_console_detail_atlas.png')
    grille = atlas.crop((264,264,504,504)).resize((256,256),Image.Resampling.NEAREST)
    grille = Image.fromarray(np.rint(np.asarray(grille,dtype=float)*32/37).astype('uint8'))
    image = Image.new('RGB',(512,512),(64,64,64))
    draw = ImageDraw.Draw(image)
    draw.rectangle((256,0,511,255),fill=(110,110,110))
    draw.rectangle((0,256,255,511),fill=(32,32,32))
    image.paste(grille,(256,256))
    image.save(output/'microphone_albedo.png')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--sources', type=Path, required=True)
    args = parser.parse_args()
    build_micro(args.output, args.sources)
    build_atlas(args.output)
    build_microphone(args.output)
    build_surface_details(args.output)

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




# #67：仅固定表面的装配细节，不新增几何或材质。坐标为 PNG 左上原点像素。
ASSEMBLY_SURFACES = {
    'CRT左厚框': {'face': 1, 'rect': [12, 32, 64, 450], 'size_m': [.178, 1.102273],
                  'screws': [[.325, .082, .011], [.325, .906, .011]]},
    'CRT右厚框': {'face': 1, 'rect': [96, 32, 72, 450], 'size_m': [.178, 1.102273],
                  'screws': [[.71, .082, .011], [.71, .906, .011]], 'existing_uv': True},
    'COMM模块板壳': {'face': 4, 'rect': [224, 32, 284, 132], 'size_m': [.77, .357411],
                  'screws': [[.08, .76, .009], [.87, .17, .009]], 'seam': True},
    'CAMERA模块板壳': {'face': 4, 'rect': [528, 32, 205, 132], 'size_m': [.555, .357411],
                  'screws': [[.12, .19, .008], [.9, .77, .008]], 'seam': True, 'drive': 'cross',
                  'polish': [[.33, .72, 6, .65], [.71, .72, 6, .65]]},
    'DOOR模块板壳': {'face': 4, 'rect': [224, 190, 430, 132], 'size_m': [1.165, .357411],
                  'screws': [[.053, .75, .009], [.55, .17, .009]], 'seam': True,
                  'status_seam_u': .66, 'polish': [[.2, .72, 6, .65], [.46, .72, 6, .65]]},
    '前缘水平托台': {'face': 4, 'rect': [224, 466, 780, 28], 'size_m': [2.64, .075],
                  'polish': [[.34, .8, 8, .65], [.62, .8, 8, .65]]},
}
ASSEMBLY_GASKET = {
    # v_min/v_max 指 Blender UV；PNG Y 方向与 UV V 相反。
    '3': {'rect': [224, 400, 550, 40], 'edge': 'v_max'},
    '7': {'rect': [800, 32, 48, 450], 'edge': 'u_max'},
    '11': {'rect': [224, 344, 550, 40], 'edge': 'v_min'},
    '15': {'rect': [864, 32, 48, 450], 'edge': 'u_min'},
}
ASSEMBLY_MICROPHONE = {'face': 1, 'rect': [16, 8, 220, 84], 'size_m': [.248, .16],
                      'screws': [[.157, .175, .0055], [.843, .175, .0055]]}


def _surface_background(image, old_uv_rect, destination):
    # 保留该面原有微表面，仅将采样范围移入不被其他面使用的预留区。
    x, y, width, height = destination
    source = image.crop(old_uv_rect).resize((width, height), Image.Resampling.BILINEAR)
    image.paste(source, (x, y))


def _assembly_normal(image, rect, height):
    x, y, width, rows = rect
    normal = np.asarray(image.crop((x, y, x + width, y + rows)), dtype=float) / 127.5 - 1
    gy, gx = np.gradient(height)
    normal[..., 0] -= gx
    normal[..., 1] += gy  # OpenGL +Y；PNG 向下，UV 向上。
    normal[..., 2] = np.sqrt(np.maximum(.01, 1 - np.sum(normal[..., :2] ** 2, axis=2)))
    normal /= np.maximum(np.linalg.norm(normal, axis=2, keepdims=True), 1e-8)
    image.paste(Image.fromarray(np.rint((normal + 1) * 127.5).clip(0, 255).astype('uint8')), (x, y))


def _fastener_height(height, surface, diameter_scale=1.0):
    yy, xx = np.mgrid[:height.shape[0], :height.shape[1]]
    for u, v, diameter in surface.get('screws', []):
        rx = diameter * height.shape[1] / surface['size_m'][0] / 2 * diameter_scale
        ry = diameter * height.shape[0] / surface['size_m'][1] / 2 * diameter_scale
        dx = (xx + .5 - u * height.shape[1]) / rx
        dy = (yy + .5 - v * height.shape[0]) / ry
        radius = np.hypot(dx, dy)
        # 沉头座和一字槽只有法线，没有黑色圆片或凸起螺栓。
        height += .10 * np.exp(-(radius / .65) ** 4)
        height -= .14 * np.exp(-((radius - .88) / .18) ** 2)
        slot = np.exp(-(dy / .24) ** 2) * np.clip((.67 - np.abs(dx)) / .2, 0, 1)
        height -= .22 * slot
        if surface.get('drive') == 'cross':
            height -= .22 * np.exp(-(dx / .24) ** 2) * np.clip((.67 - np.abs(dy)) / .2, 0, 1)


def _fastener_albedo(image, surface, head, rim, slot):
    # 固定件用同源绘制的灰色头部、细沉头座和明确槽口，FOV70 下可辨认。
    # 小图先在 128px 绘制再采样，避免把低分辨率圆头变成硬方块。
    # Albedo 使用两倍采样密度，原 UV/法线布局不变；槽口需覆盖实机像素。
    x, y, width, rows = [2 * value for value in surface['rect']]
    for u, v, diameter in surface.get('screws', []):
        stamp = Image.new('RGBA', (128, 128), (0, 0, 0, 0))
        draw = ImageDraw.Draw(stamp)
        draw.ellipse((4, 4, 123, 123), fill=(*rim, 255))
        draw.ellipse((22, 22, 105, 105), fill=(*head, 255))
        draw.line((31, 64, 96, 64), fill=(*slot, 255), width=30)
        if surface.get('drive') == 'cross':
            draw.line((64, 31, 64, 96), fill=(*slot, 255), width=30)
        size=(max(3, round(diameter * width / surface['size_m'][0])),
              max(3, round(diameter * rows / surface['size_m'][1])))
        stamp=stamp.resize(size, Image.Resampling.LANCZOS)
        left=x+round(u*width-size[0]/2)
        top=y+round(v*rows-size[1]/2)
        image.paste(stamp, (left, top), stamp)


def build_assembly_details(output):
    paint_normal = Image.open(output / 'paint_normal.png').convert('RGB')
    paint_roughness = Image.open(output / 'paint_roughness.png').convert('L')
    detail_albedo = Image.open(output / 'module_detail_albedo.png').convert('RGB')
    mic_normal = Image.open(output / 'microphone_normal.png').convert('RGB')
    mic_albedo = Image.open(output / 'microphone_albedo.png').convert('RGB')
    # 128 sRGB 精确匹配 COMM/DOOR 原纯色因子，不改变普通板面底色。
    panel_albedo = Image.new('RGB', (1024, 1024), (128, 128, 128))
    index_path = output / 'main_console_detail_atlas.json'
    index = json.loads(index_path.read_text(encoding='utf-8'))

    # #64 各面旧正交 UV；右侧检修条像素及 UV 原样保留，仅额外添加两处浅法线。
    old_rects = {
        'CRT左厚框': (20, 597, 87, 1004),
        'COMM模块板壳': (20, 872, 305, 1004),
        'CAMERA模块板壳': (20, 872, 226, 1004),
        'DOOR模块板壳': (20, 872, 451, 1004),
        '前缘水平托台': (20, 976, 994, 1004),
    }
    polish_area = 0.0
    eligible_area = 0.0
    for name, surface in ASSEMBLY_SURFACES.items():
        rect = surface['rect']
        x, y, width, rows = rect
        if name in old_rects:
            for image in (paint_normal, paint_roughness):
                _surface_background(image, old_rects[name], rect)
        height = np.zeros((rows, width), dtype=float)
        _fastener_height(height, surface)
        if surface.get('seam'):
            # 1.2mm 浅槽，边界留 6mm；无黑色 Albedo 描边。
            yy, xx = np.mgrid[:rows, :width]
            pad_x = .006 * width / surface['size_m'][0]
            pad_y = .006 * rows / surface['size_m'][1]
            distance = np.minimum.reduce([xx + .5 - pad_x, width - xx - .5 - pad_x,
                                          yy + .5 - pad_y, rows - yy - .5 - pad_y])
            height -= .075 * np.exp(-(distance / .42) ** 2)
            if 'status_seam_u' in surface:
                # 同一原板壳上区分 DOOR / STATUS，不切几何，不加 STATUS 固定件。
                height -= .06 * np.exp(-((xx + .5 - width * surface['status_seam_u']) / .42) ** 2)
        if np.any(height):
            _assembly_normal(paint_normal, rect, height)
        if surface.get('polish'):
            rough = np.asarray(paint_roughness.crop((x, y, x + width, y + rows)), dtype=float)
            yy, xx = np.mgrid[:rows, :width]
            mask = np.zeros((rows, width), dtype=float)
            for u, v, sigma_x, sigma_y in surface['polish']:
                q = ((xx + .5 - u * width) / sigma_x) ** 2 + ((yy + .5 - v * rows) / sigma_y) ** 2
                mask = np.maximum(mask, np.where(q <= 4, np.exp(-q / 2), 0))
            result = np.rint(rough - 4 * mask).clip(0, 255).astype('uint8')
            area = surface['size_m'][0] * surface['size_m'][1]
            polish_area += float(np.mean(result < rough)) * area
            eligible_area += area
            paint_roughness.paste(Image.fromarray(result), (x, y))
    assert polish_area / eligible_area < .01

    # 内坡面后缘：3.5mm 密封带位于玻璃之外，屏幕与孔口几何完全不变。
    old_gasket_rects = {
        '3': (20, 941, 559, 1004),
        '7': (20, 600, 62, 1004),
        '11': (20, 960, 559, 1004),
        '15': (20, 600, 62, 1004),
    }
    for face, surface in ASSEMBLY_GASKET.items():
        x, y, width, rows = surface['rect']
        for image in (paint_normal, paint_roughness):
            _surface_background(image, old_gasket_rects[face], surface['rect'])
        color = np.full((rows, width, 3), (86, 89, 96), dtype='uint8')
        edge = surface['edge']
        yy, xx = np.mgrid[:rows, :width]
        axis = width if edge.startswith('u') else rows
        band = .0035 / .099 * axis
        distance = (xx + .5 if edge == 'u_min' else width - xx - .5 if edge == 'u_max'
                    else rows - yy - .5 if edge == 'v_min' else yy + .5)
        mask = np.clip(band + .5 - distance, 0, 1)
        color = np.rint(color * (1 - mask[..., None]) + np.array([24, 25, 27]) * mask[..., None]).astype('uint8')
        detail_albedo.paste(Image.fromarray(color), (x, y))

    # 麦座唯一上表面分配到原灰色象限的空白范围，其他面仍使用原 UV。
    mic = ASSEMBLY_MICROPHONE
    _surface_background(mic_normal, (10, 114, 214, 246), mic['rect'])
    height = np.zeros((mic['rect'][3], mic['rect'][2]), dtype=float)
    _fastener_height(height, mic)
    _assembly_normal(mic_normal, mic['rect'], height)

    paint_normal.save(output / 'paint_normal.png')
    paint_roughness.save(output / 'paint_roughness.png')
    detail_albedo.save(output / 'module_detail_albedo.png')
    mic_normal.save(output / 'microphone_normal.png')
    detail_albedo = detail_albedo.resize((2048, 2048), Image.Resampling.NEAREST)
    panel_albedo = panel_albedo.resize((2048, 2048), Image.Resampling.NEAREST)
    mic_albedo = mic_albedo.resize((1024, 1024), Image.Resampling.NEAREST)
    for name, surface in ASSEMBLY_SURFACES.items():
        if name in ('COMM模块板壳', 'DOOR模块板壳'):
            _fastener_albedo(panel_albedo, surface, (184, 184, 180), (64, 64, 64), (38, 38, 38))
        else:
            _fastener_albedo(detail_albedo, surface, (151, 153, 157), (49, 51, 56), (24, 26, 30))
    _fastener_albedo(mic_albedo, mic, (122, 124, 126), (28, 29, 30), (16, 17, 18))
    detail_albedo.save(output / 'module_detail_albedo.png')
    panel_albedo.save(output / 'panel_fastener_albedo.png')
    mic_albedo.save(output / 'microphone_albedo.png')
    index['assembly_detail_pass'] = {
        'issue': 67, 'surfaces': ASSEMBLY_SURFACES, 'gasket': ASSEMBLY_GASKET,
        'microphone': ASSEMBLY_MICROPHONE,
        'fastener_totals': {'CRT_including_existing': 6, 'COMM': 2, 'CAMERA': 2, 'DOOR': 2, 'STATUS': 0, 'microphone_base': 2},
        'gasket_width_m': .0035, 'seam_width_m': .0012,
        'new_geometry': False, 'new_materials': False, 'optional_identifier': None,
        'fastener_rendering': 'albedo_head_seat_drive_with_shallow_normal',
        'albedo_sampling': {'module_panel_resolution': 2048, 'microphone_resolution': 1024, 'layout_rect_scale': 2, 'geometry_uv_unchanged': True},
        'panel_albedo': {'file': 'panel_fastener_albedo.png', 'background_srgb': [128, 128, 128], 'materials': ['体块模块灰']},
        'polish': {'channel': 'roughness_only', 'max_reduction_255': 4,
                   'visible_area_fraction': polish_area / eligible_area},
    }
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    provenance_path = output / 'material_provenance.json'
    provenance = json.loads(provenance_path.read_text(encoding='utf-8'))
    provenance['assembly_detail_pass'] = index['assembly_detail_pass']
    provenance['outputs'] = {file.name: {'resolution': list(Image.open(file).size),
        'sha256': hashlib.sha256(file.read_bytes()).hexdigest()} for file in sorted(output.glob('*.png'))}
    provenance_path.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--sources', type=Path, required=True)
    args = parser.parse_args()
    build_micro(args.output, args.sources)
    build_atlas(args.output)
    build_microphone(args.output)
    build_surface_details(args.output)
    build_assembly_details(args.output)

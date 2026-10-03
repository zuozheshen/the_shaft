"""#64 自制纹理源。固定 seed、固定尺寸，不读取照片或网络资产。

用 Python + Pillow + NumPy 执行；输出目录作为唯一参数。
只生成实际需要的通道，简单颜色/金属度留给共享材质。
"""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def micro_surface(size, seed):
    rng = np.random.default_rng(seed)
    coarse = Image.fromarray(rng.integers(90, 166, (32, 32), dtype=np.uint8))
    field = np.asarray(coarse.resize((size, size), Image.Resampling.BICUBIC), dtype=float)
    field = (field - 128) / 38
    grain = rng.normal(0, 0.7, (size, size))
    # 仅低幅粗糙度变化，不在 albedo 上制造污渍。
    return Image.fromarray(np.clip(246 + field * 4 + grain, 239, 252).astype('uint8'))


def build_micro(output):
    output.mkdir(parents=True, exist_ok=True)
    for name, size, seed in [('paint_roughness', 1024, 6401),
                             ('control_roughness_512', 512, 6402),
                             ('control_roughness_256', 256, 6403)]:
        micro_surface(size, seed).save(output / (name + '.png'))


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


def build_microphone(output):
    # 四个色区保留原来的三材质槽；网罩只分配给麦头，底座和鹅颈不加孔。
    atlas = Image.open(output/'main_console_detail_atlas.png')
    grille = atlas.crop((264,264,504,504)).resize((256,256),Image.Resampling.NEAREST)
    grille = Image.fromarray(np.rint(np.asarray(grille,dtype=float)*32/37).astype('uint8'))
    image = Image.new('RGB',(512,512),(152,152,152))
    draw = ImageDraw.Draw(image)
    draw.rectangle((256,0,511,255),fill=(222,219,211))
    draw.rectangle((0,256,255,511),fill=(32,32,32))
    image.paste(grille,(256,256))
    image.save(output/'microphone_albedo.png')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    build_micro(args.output)
    build_atlas(args.output)
    build_microphone(args.output)

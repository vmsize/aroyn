"""Original Aroyn icon family. Offline, supersampled round strokes; no downloads."""
from pathlib import Path
import math
from PIL import Image, ImageDraw

import argparse
parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args()
ASSETS=Path(__file__).resolve().parent.parent/'assets'
ROOT=Path(args.output).resolve()
if ROOT.exists() and any(ROOT.iterdir()):raise ValueError('Choose an empty generated-assets directory')
ROOT.mkdir(parents=True,exist_ok=True)
CELL, SUPERSAMPLE = 128, 8
KEYS = ['cart', 'plot', 'compost', 'market', 'settings', 'pets', 'components']
atlas = Image.new('RGBA', (CELL * len(KEYS), CELL))
svgs = []
for index, key in enumerate(KEYS):
    mask = Image.new('L', (CELL * SUPERSAMPLE, CELL * SUPERSAMPLE))
    d = ImageDraw.Draw(mask)
    factor = CELL * SUPERSAMPLE / 24
    # 2.2 screen pixels at a 24px holder; visible footprint ~21px.
    stroke = 2.2
    parts = []
    def path(points):
        coords = [(round(x * factor), round(y * factor)) for x, y in points]
        d.line(coords, fill=255, width=round(stroke * factor), joint='curve')
        radius = stroke * factor / 2
        for x, y in coords:
            d.ellipse((x-radius, y-radius, x+radius, y+radius), fill=255)
        parts.append('<polyline points="' + ' '.join(f'{x},{y}' for x,y in points) + '"/>')
    def curve(points):
        start, c1, c2, end = points
        sampled=[]
        for n in range(65):
            t=n/64; u=1-t
            sampled.append(tuple(u**3*start[k]+3*u*u*t*c1[k]+3*u*t*t*c2[k]+t**3*end[k] for k in (0,1)))
        path(sampled)
    def circle(x,y,r,fill=False):
        box=tuple(v*factor for v in (x-r,y-r,x+r,y+r))
        d.ellipse(box, fill=255 if fill else None, outline=255, width=round(stroke*factor))
        parts.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{"white" if fill else "none"}"/>')
    if key=='cart':
        path([(2,3),(5,3),(7.8,15.2),(19.2,15.2)])
        path([(6,6.5),(22,6.5),(19.8,11.7),(7.2,11.7)])
        circle(9,20,1.35,True); circle(18,20,1.35,True)
    elif key=='plot':
        path([(12,22),(12,13)])
        curve([(12,14),(3,14),(2,8),(2,4)])
        curve([(2,4),(9,4),(12,7),(12,14)])
        curve([(12,12),(12,5),(17,2),(22,2)])
        curve([(22,2),(22,9),(17,12),(12,12)])
        path([(5,22),(19,22)])
    elif key=='compost':
        path([(12,2),(22,7.5),(22,17),(12,22.5),(2,17),(2,7.5),(12,2)])
        path([(2,7.5),(12,13),(22,7.5)])
        path([(12,13),(12,22.5)])
    elif key=='market':
        path([(2,8),(4,2),(20,2),(22,8)])
        path([(2,8),(2,10),(4,11),(7,11),(9,9),(12,11),(15,9),(17,11),(20,11),(22,10),(22,8)])
        path([(4,12),(4,22),(20,22),(20,12)])
        path([(9,22),(9,15),(15,15),(15,22)])
        path([(8,2),(7,8)]);path([(16,2),(17,8)])
    elif key=='settings':
        for y,x in [(5,8),(12,16),(19,9)]:
            path([(2,y),(x-3,y)]);path([(x+3,y),(22,y)])
            circle(x,y,2.5)
    elif key=='pets':
        curve([(6,20),(3,17),(8,12),(10,12)])
        curve([(10,12),(12,11),(14,12),(14,12)])
        curve([(14,12),(17,12),(22,18),(18,20)])
        curve([(18,20),(15,23),(14,20),(12,20)])
        curve([(12,20),(10,20),(9,23),(6,20)])
        for x,y in [(3,10),(8,4),(16,4),(21,10)]:circle(x,y,1.5,True)
    else:
        for x,y in [(2,2),(14,2),(2,14),(14,14)]:
            d.rounded_rectangle(tuple(v*factor for v in (x,y,x+8,y+8)),radius=1.6*factor,outline=255,width=round(stroke*factor))
            parts.append(f'<rect x="{x}" y="{y}" width="8" height="8" rx="1.6"/>')
    image=Image.new('RGBA',mask.size,'white'); image.putalpha(mask)
    image=image.resize((CELL,CELL),Image.Resampling.LANCZOS)
    atlas.alpha_composite(image,(index*CELL,0))
    svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="white" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'+''.join(parts)+'</g></svg>\n'
    (ROOT/(key+'.svg')).write_text(svg,encoding='utf-8')
atlas.save(ROOT/'navigation-2b.png',optimize=True)
proof=Image.new('RGB',(560,166),(23,23,25))
for index,key in enumerate(KEYS):
    cell=atlas.crop((index*CELL,0,(index+1)*CELL,CELL))
    proof.paste(cell.resize((24,24),Image.Resampling.LANCZOS),(index*80+28,20),cell.resize((24,24),Image.Resampling.LANCZOS))
    proof.paste(cell.resize((64,64),Image.Resampling.LANCZOS),(index*80+8,64),cell.resize((64,64),Image.Resampling.LANCZOS))
    ImageDraw.Draw(proof).text((index*80+6,144),key,fill=(181,181,176))
proof.save(ROOT/'navigation-proof.png')
print('Built seven original 128px icons and 24px/64px inspection sheet.')

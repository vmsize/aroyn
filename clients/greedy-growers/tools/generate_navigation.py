"""Offline padded atlas: native Roblox must retain the source pixel dimensions."""
from pathlib import Path
from PIL import Image, ImageDraw
import base64, math, re

import argparse
parser=argparse.ArgumentParser();parser.add_argument('--output',required=True);args=parser.parse_args()
ASSETS=Path(__file__).resolve().parent.parent/'assets'
ROOT=Path(args.output).resolve()
if ROOT.exists() and any(ROOT.iterdir()):raise ValueError('Choose an empty generated-assets directory')
ROOT.mkdir(parents=True,exist_ok=True)
CELL, SUPERSAMPLE, STROKE=128,8,2.2
COLS, STRIDE, PAD=5,160,16
KEYS=['cart','plot','compost','market','settings','pets','components','harvest','gear','stats']
before=Image.open(ASSETS/'navigation-before.png').convert('RGBA')
assert before.size==(7*CELL,CELL)
atlas=Image.new('RGBA',(len(KEYS)*CELL,CELL))
atlas.paste(before,(0,0))  # Exact original RGBA pixels, including transparent margins.

for slot,key in enumerate(KEYS[7:],7):
    mask=Image.new('L',(CELL*SUPERSAMPLE,CELL*SUPERSAMPLE))
    draw=ImageDraw.Draw(mask)
    factor=CELL*SUPERSAMPLE/24
    parts=[]
    def path(points):
        coords=[(round(x*factor),round(y*factor)) for x,y in points]
        draw.line(coords,fill=255,width=round(STROKE*factor),joint='curve')
        radius=STROKE*factor/2
        for x,y in coords:
            draw.ellipse((x-radius,y-radius,x+radius,y+radius),fill=255)
        parts.append('<polyline points="'+' '.join(f'{x:.4f},{y:.4f}' for x,y in points)+'"/>')
    def curve(points):
        start,c1,c2,end=points
        sampled=[]
        for n in range(65):
            t=n/64;u=1-t
            sampled.append(tuple(u**3*start[k]+3*u*u*t*c1[k]+3*u*t*t*c2[k]+t**3*end[k] for k in (0,1)))
        path(sampled)
    def circle(x,y,r):
        draw.ellipse(tuple(v*factor for v in (x-r,y-r,x+r,y+r)),outline=255,width=round(STROKE*factor))
        parts.append(f'<circle cx="{x}" cy="{y}" r="{r}"/>')
    if key=='harvest':
        path([(3,10),(5.5,21),(18.5,21),(21,10),(3,10)])
        curve([(7,10),(7,1),(17,1),(17,10)])
        path([(9,13.5),(10,17.5)])
        path([(15,13.5),(14,17.5)])
    elif key=='gear':
        points=[]
        for tooth in range(8):
            for offset,radius in [(-22.5,7.4),(-15,7.4),(-8,10),(8,10),(15,7.4)]:
                angle=math.radians(tooth*45+offset)
                points.append((12+radius*math.cos(angle),12+radius*math.sin(angle)))
        path(points+[points[0]])
        circle(12,12,3)
    else:
        path([(3,3),(3,21),(21,21)])
        for x,top in [(8,14),(13,9),(18,4)]:
            path([(x,top),(x,17.5)])
    icon=Image.new('RGBA',mask.size,'white');icon.putalpha(mask)
    icon=icon.resize((CELL,CELL),Image.Resampling.LANCZOS)
    atlas.paste(icon,(slot*CELL,0))
    svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><g fill="none" stroke="white" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'+''.join(parts)+'</g></svg>\n'
    (ROOT/(key+'.svg')).write_text(svg,encoding='utf-8')

flat=atlas
atlas=Image.new('RGBA',(1024,512))
for slot in range(len(KEYS)):
    atlas.paste(flat.crop((slot*CELL,0,(slot+1)*CELL,CELL)),
        ((slot%COLS)*STRIDE+PAD,(slot//COLS)*STRIDE+PAD))
output=ROOT/'navigation-phase6a.png'
atlas.save(output,optimize=True)
for slot in range(7):
    x,y=(slot%COLS)*STRIDE+PAD,(slot//COLS)*STRIDE+PAD
    assert atlas.crop((x,y,x+CELL,y+CELL)).tobytes()==before.crop((slot*CELL,0,(slot+1)*CELL,CELL)).tobytes()
used=[('Buy Seeds','cart'),('Plot','plot'),('Collect','harvest'),('Compost','compost'),('Market','market'),('Pets','pets'),('Session','stats'),('Settings','gear')]
proof=Image.new('RGB',(8*96,166),(23,23,25))
for i,(page,key) in enumerate(used):
    slot=KEYS.index(key)
    x,y=(slot%COLS)*STRIDE+PAD,(slot//COLS)*STRIDE+PAD
    cell=atlas.crop((x,y,x+CELL,y+CELL))
    for size,y in [(24,20),(64,64)]:
        scaled=cell.resize((size,size),Image.Resampling.LANCZOS)
        proof.paste(scaled,(i*96+(96-size)//2,y),scaled)
    ImageDraw.Draw(proof).text((i*96+8,144),page,fill=(181,181,176))
proof.save(ROOT/'navigation-proof.png')
print('Padded 1024x512 atlas: ten unchanged icon cells; 128px crops, 160px stride, 16px guards, five columns.')

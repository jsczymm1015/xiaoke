#!/usr/bin/env python3
"""Pack generated pixels only: crop transparent gutters, uniformly resize, align.
No head/body warping, synthesized art, or frame-by-frame zoom. Requires Pillow.
"""
from pathlib import Path
from statistics import median
import json
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'artwork/unified'
CELL = (192, 208)
def transparent_seams(im, count):
    alpha = im.getchannel('A')
    seams = [[0] * im.height]
    peaks = []
    for index in range(1, count):
        center = round(im.width * index / count)
        radius = round(im.width / count * .35)
        positions = list(range(max(0, center-radius), min(im.width-1, center+radius)+1))
        scores, parents = [0.0] * len(positions), []
        for y in range(im.height):
            new, parent = [], []
            for i, x in enumerate(positions):
                prev = min(range(max(0, i-2), min(len(positions), i+3)), key=lambda j: scores[j] + abs(i-j)*.00003)
                new.append(scores[prev] + abs(i-prev)*.00003 + (alpha.getpixel((x,y))/255)**8*100000 + abs(x-center)*.0000003)
                parent.append(prev)
            parents.append(parent)
            scores = new
        idx = min(range(len(scores)), key=scores.__getitem__)
        seam = [0] * im.height
        for y in reversed(range(im.height)):
            seam[y] = positions[idx]
            idx = parents[y][idx]
        peak = max(alpha.getpixel((x,y)) for y,x in enumerate(seam))
        assert peak < 128, ('Opaque sprite overlap', index, peak)
        seams.append(seam)
        peaks.append(peak)
    return seams + [[im.width]*im.height], peaks



def extract(name, count=6):
    im = Image.open(SOURCE / (name + '.png')).convert('RGBA')
    ys, yp = transparent_seams(im.transpose(Image.Transpose.TRANSPOSE), count)
    rows, report = [], []
    for r in range(count):
        strip = Image.new('RGBA', im.size)
        for x in range(im.width):
            y1,y2=ys[r][x],ys[r+1][x]
            strip.paste(im.crop((x,y1,x+1,y2)),(x,y1))
        bounds=strip.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox()
        strip=strip.crop((0,max(0,bounds[1]-1),im.width,min(im.height,bounds[3]+1)))
        xs,xp=transparent_seams(strip,count)
        poses=[]
        for c in range(count):
            pose=Image.new('RGBA',strip.size)
            for y in range(strip.height):
                x1,x2=xs[c][y],xs[c+1][y]
                pose.paste(strip.crop((x1,y,x2,y+1)),(x1,y))
            box=pose.getchannel('A').point(lambda a:255 if a>32 else 0).getbbox()
            poses.append(pose.crop(box))
        rows.append(poses)
        report.append({'source':name,'row':r,'seam_alpha_max':max(yp+xp)})
    # Head measurement uses the same band even for sitting poses, so sitting
    # never gets enlarged to fill a standing-height rectangle.
    head_band=round(median(p.height for p in rows[0])*.43)
    normalized=[]
    for r,poses in enumerate(rows):
        widths=[]
        for p in poses:
            box=p.getchannel('A').point(lambda a:255 if a>128 else 0).crop((0,0,p.width,min(head_band,p.height))).getbbox()
            widths.append(box[2]-box[0])
        factor=100/median(widths)
        assert max(p.width*factor for p in poses)<185,(name,r,'too wide')
        assert max(p.height*factor for p in poses)<200,(name,r,'too tall')
        result=[]
        for c,p in enumerate(poses):
            p=p.resize((round(p.width*factor),round(p.height*factor)),Image.Resampling.LANCZOS)
            frame=Image.new('RGBA',CELL)
            lift=round(4*(1-abs(c-2.5)/2.5)) if name=='emotes' and r==1 else 0
            frame.alpha_composite(p,((192-p.width)//2,203-p.height-lift))
            result.append(frame)
        report[r].update(scale=factor,head_widths=[round(w*factor,2) for w in widths],heights=[round(p.height*factor) for p in poses])
        normalized.append(result)
    return normalized,report


def atlas(rows, filename, columns=6, heights=None):
    im=Image.new('RGBA',(columns*192,len(rows)*208))
    for r,row in enumerate(rows):
        for c,frame in enumerate(row):im.alpha_composite(frame,(c*192,r*208))
    im.save(ROOT/'Resources'/filename)
    return im


def main():
    groups={};report=[]
    for name in ['core','daily','emotes','foods','gaze']:
        groups[name],details=extract(name,4 if name=='gaze' else 6);report+=details
    core,daily,emotes,foods=[groups[n] for n in ['core','daily','emotes','foods']]
    base=[core[0],core[5],emotes[5],emotes[0],emotes[1],emotes[2],emotes[3],core[1],emotes[4]]
    counts=[6,8,8,4,5,8,6,6,6]
    base=[[row[min(5,int(c*6/count))] for c in range(count)] for row,count in zip(base,counts)]
    gaze=[p for row in groups['gaze'] for p in row]
    base += [gaze[:8],gaze[8:]]
    atlas(base,'l3d-spritesheet.png',8)
    atlas([core[1],core[2]],'l3d-spritesheet-activities.png')
    atlas(daily[:5]+[foods[0],foods[1],core[3],core[4],core[0]],'l3d-spritesheet-life.png')
    atlas(foods[2:],'l3d-spritesheet-foods.png')
    atlas([daily[5]],'l3d-spritesheet-blanket.png')
    preview=Image.new('RGBA',(8*192,4*240),'#fff8f1')
    items=[('standing',core[0]),('writing',core[1]),('sleeping',core[2]),('carry',core[3]),('land',core[4]),('walk-right',core[5])]
    items += [(n,row) for n,row in zip(['rub-eyes','stretch','page-flip','groom','yawn','blanket'],daily)]
    items += [(n,row) for n,row in zip(['wave','jump','sad','wait','review','walk-left'],emotes)]
    items += [(n,row) for n,row in zip(['cookie','drink','rice','sandwich','apple','cake'],foods)]
    items += [('gaze-'+str(i),[gaze[i]]) for i in range(8)]
    for i,(name,row) in enumerate(items):
        x,y=(i%8)*192,(i//8)*240
        ImageDraw.Draw(preview).text((x+8,y+8),name,fill='#51435e')
        preview.alpha_composite(row[0],(x,y+25))
    preview.convert('RGB').save(ROOT/'docs/artwork/unified-contact.png')
    (ROOT/'docs/artwork/measurements.json').write_text(json.dumps(report,indent=2))
    print('Packed all actions; head width range:',min(w for r in report for w in r['head_widths']),max(w for r in report for w in r['head_widths']))

if __name__=='__main__':main()

"""Compare the front render at the same scale as the supplied front photograph."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageFilter
import numpy as np,json
ROOT=Path(__file__).resolve().parents[1]
ref=Image.open(ROOT/'references/view_05.png').convert('RGB')
render=Image.open(ROOT/'face.png').convert('RGBA')
# Orthographic front camera: width 0.165m, target x=.008, z=.010.
# Tracing coordinates: x_world=(pixel_x-260)*.00022-.002;
# z_world=.002+(724-pixel_y)*.00022.
ppm=render.width/.165;s=.00022*ppm
ox=render.width/2-.010*ppm-260*s
oy=render.height/2+.008*ppm-724*s
aligned=render.transform(ref.size,Image.Transform.AFFINE,(s,0,ox,0,s,oy),Image.Resampling.BICUBIC)
model=Image.new('RGB',ref.size,'white');model.paste(aligned,mask=aligned.getchannel('A'))
crop=(0,515,600,867)
canvas=Image.new('RGB',(1600,630),'white');draw=ImageDraw.Draw(canvas)
font='/System/Library/Fonts/Helvetica.ttc';heading=ImageFont.truetype(font,30);label=ImageFont.truetype(font,21)
for i,(im,title) in enumerate([(ref,'Reference photograph'),(model,'Revised 3D head — front view')]):
    draw.text((32+800*i,26),title,font=heading,fill=(30,34,40))
    panel=im.crop(crop).resize((768,451),Image.Resampling.LANCZOS)
    canvas.paste(panel,(16+800*i,95))
draw.text((32,581),'Independent contours for the head and face insert · Shorter hosel · Estimated dimensions',font=label,fill=(95,100,106))
canvas.save(ROOT/'front_comparison.png',optimize=True)
# Silhouette agreement in the body region, excluding the unmodelled shaft.
box=(0,610,550,850)
a=np.array(ref.crop(box)).min(2)<245
b=np.array(aligned.getchannel('A').crop(box))>128
# Fill tiny highlight holes without joining the shaft-to-crown gap.
a=np.array(Image.fromarray(np.uint8(a)*255).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3)))>128
report={'comparison':'Orthographic render aligned to traced reference pixels; not a camera calibration','body_region_pixels':box,'silhouette_intersection_over_union':float((a&b).sum()/(a|b).sum())}
(ROOT/'front_comparison.json').write_text(json.dumps(report,indent=2));print(report)

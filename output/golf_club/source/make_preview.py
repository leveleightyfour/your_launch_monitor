from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
canvas=Image.new('RGB',(1600,820),(239,241,243))
d=ImageDraw.Draw(canvas)
font_path='/System/Library/Fonts/Helvetica.ttc'
title=ImageFont.truetype(font_path,38)
small=ImageFont.truetype(font_path,19)
label=ImageFont.truetype(font_path,24)
d.text((48,32),'Titleist GT2',font=title,fill=(25,29,33))
d.text((1552,45),'HEAD ONLY  /  PHOTO-INFORMED RECONSTRUCTION',font=small,fill=(90,96,102),anchor='ra')
d.line((48,91,1552,91),fill=(200,205,211),width=1)
for i,(name,txt) in enumerate([('hero','Face & crown'),('sole','Sole & adjustable hosel')]):
    im=Image.open(ROOT/(name+'.png')).convert('RGBA');im.thumbnail((780,613),Image.Resampling.LANCZOS)
    canvas.paste(im,(i*800+(800-im.width)//2,117),im)
    d.text((i*800+48,762),txt,font=label,fill=(48,54,60))
canvas.save(ROOT/'preview.png',optimize=True)

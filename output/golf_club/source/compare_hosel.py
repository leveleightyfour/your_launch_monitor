from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
canvas=Image.new('RGB',(1600,720),(243,244,246));d=ImageDraw.Draw(canvas)
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',29)
small=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',20)
for i,(path,label) in enumerate([(ROOT/'revisions/v2/hosel.png','Previous junction'),(ROOT/'hosel.png','Smoothed junction')]):
    im=Image.open(path).convert('RGBA');im.thumbnail((790,621),Image.Resampling.LANCZOS)
    canvas.paste(im,(i*800+(800-im.width)//2,67),im)
    d.text((i*800+28,22),label,font=font,fill=(31,36,42))
d.text((28,691),'Same camera and lighting · Head and lower hosel now form one continuous mesh',font=small,fill=(92,99,106))
canvas.save(ROOT/'hosel_comparison.png',optimize=True)

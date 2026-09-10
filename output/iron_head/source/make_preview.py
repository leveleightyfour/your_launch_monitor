from PIL import Image,ImageDraw,ImageFont,ImageOps
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
font='/System/Library/Fonts/Helvetica.ttc'
canvas=Image.new('RGB',(1800,1470),(239,239,236));d=ImageDraw.Draw(canvas)
d.text((65,40),'SRIXON ZXi7 / 7-IRON',font=ImageFont.truetype(font,42),fill=(30,34,36))
d.text((66,101),'Head only · photo-informed 3D reconstruction',font=ImageFont.truetype(font,23),fill=(91,94,94))
for name,title,box in [('back','SCULPTED BACK',(40,165,890,785)),('face','TRACED FACE OUTLINE',(910,165,1760,785)),('hosel','CONTINUOUS HOSEL',(40,820,890,1410)),('side','SOLE & THICKNESS',(910,820,1760,1410))]:
    im=Image.open(ROOT/(name+'.png')).convert('RGBA');bb=im.getbbox();im=im.crop(bb);im.thumbnail((box[2]-box[0]-70,box[3]-box[1]-80),Image.Resampling.LANCZOS)
    canvas.paste(im,((box[0]+box[2]-im.width)//2,box[1]+55+(box[3]-box[1]-70-im.height)//2),im)
    d.text((box[0]+25,box[1]+10),title,font=ImageFont.truetype(font,20),fill=(90,94,94))
canvas.save(ROOT/'preview.png')
# Side-by-side source and model, retaining the full hosel transition for inspection.
board=Image.new('RGB',(1800,880),(245,245,243));d=ImageDraw.Draw(board)
d.text((50,28),'Front view / source photograph and model',font=ImageFont.truetype(font,32),fill=(30,34,36))
ref=Image.open(ROOT/'references/view_578.png').convert('RGB').crop((80,290,801,688))
ref.thumbnail((790,665),Image.Resampling.LANCZOS);board.paste(ref,(45,170+(665-ref.height)//2))
im=Image.open(ROOT/'face.png').convert('RGBA');im=im.crop(im.getbbox());im.thumbnail((850,665),Image.Resampling.LANCZOS);board.paste(im,(920+(850-im.width)//2,170+(665-im.height)//2),im)
d.text((50,108),'SUPPLIED PHOTO',font=ImageFont.truetype(font,20),fill=(100,104,104));d.text((960,108),'3D MODEL',font=ImageFont.truetype(font,20),fill=(100,104,104))
board.save(ROOT/'front_comparison.png')

from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageFilter
import numpy as np
ROOT=Path(__file__).resolve().parents[1];T=ROOT/'textures';T.mkdir(exist_ok=True)
# Scoreline dimensions and stepped endpoints are read from the supplied face photograph.
N=2048
xx=np.linspace(197,546,N)[None,:];zz=np.linspace(331,663,N)[:,None]
rows=[(376,258),(398,311),(421,363),(443,411),(466,457),(488,501),(510,538),(532,538),(554,538),(577,538),(599,538),(621,538),(643,538)]
h=np.zeros((N,N),np.float32)
for cy,end in rows:
    dx=np.maximum(np.maximum(205-xx,xx-(end-2)),0);rr=np.sqrt(dx*dx+(zz-cy)**2)
    t=np.clip((2.05-rr)/1.05,0,1);h=np.minimum(h,-.00013*(t*t*(3-2*t)))
rng=np.random.default_rng(72);brush=rng.normal(0,.6,(N,1))
base=np.clip(196+brush+np.where(h<0,-45*np.minimum(1,-h/.00013),0),0,255).astype('uint8')
Image.fromarray(np.repeat(base[:,:,None],3,axis=2)).save(T/'face_color.png')
# Tangent coordinates: U increasing x, V increasing z. Texture rows run downward.
dy,dx=np.gradient(h,332*.00017/(N-1),349*.00017/(N-1))
norm=np.stack([-dx,dy,np.ones_like(dx)],axis=-1);norm/=np.linalg.norm(norm,axis=2)[:,:,None]
Image.fromarray(np.clip((norm*.5+.5)*255,0,255).astype('uint8')).save(T/'face_normal.png')
Image.new('RGB',(16,16),(141,141,141)).save(T/'face_roughness.png')
# Extract the original brand lettering alone; photographed lighting is excluded.
im=Image.open(ROOT/'references/view_575.png').convert('RGB').crop((105,211,205,266))
ar=np.asarray(im).astype(float);alpha=np.clip((125-ar.min(2))/65,0,1)*255
logo=Image.new('RGBA',im.size,(13,14,15,0));logo.putalpha(Image.fromarray(alpha.astype('uint8')))
logo=logo.rotate(14,resample=Image.Resampling.BICUBIC,expand=True)
box=logo.getbbox();logo=logo.crop(box);logo=logo.crop((0,0,logo.width,round(logo.height*.74)));logo.resize((640,round(640*logo.height/logo.width)),Image.Resampling.LANCZOS).save(T/'srixon.png')
fontdir=Path('/System/Library/Fonts/Supplemental')
for label,text,font,size in [('zxi7','ZXi7','Arial Bold Italic.ttf',150),('pureframe','P U R E F R A M E','Arial.ttf',55),('forged','i-FORGED','Arial Bold Italic.ttf',85),('seven','7','Arial.ttf',220)]:
    f=ImageFont.truetype(str(fontdir/font),size);box=f.getbbox(text);img=Image.new('RGBA',(box[2]-box[0]+12,box[3]-box[1]+12),(0,0,0,0));d=ImageDraw.Draw(img);d.text((6-box[0],6-box[1]),text,font=f,fill=(15,16,17,255));img.save(T/(label+'.png'))
print('Textures prepared')

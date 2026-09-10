"""Prepare portable UV textures for the reference-based GT2 model."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import numpy as np
ROOT = Path(__file__).resolve().parents[1]
TEX = ROOT / 'textures'
TEX.mkdir(exist_ok=True)
# Use the supplied sole photography, masking outside the head with black lacquer.
im = Image.open(ROOT/'references/view_02.png').convert('RGB')
a = np.asarray(im).copy()
mask = Image.new('L', im.size)
d = ImageDraw.Draw(mask)
d.polygon([(580,620),(465,588),(330,545),(205,483),(135,422),(99,352),(96,280),(121,212),(163,144),(225,82),(310,34),(398,8),(481,9),(561,38),(614,85),(641,142),(656,215),(660,300),(653,413),(640,505),(621,571),(602,614)], fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(5))
m = np.array(mask)/255.
a = np.uint8(a*m[...,None]+np.array([9,10,11])*(1-m[...,None]))
# Avoid projecting the side logo a second time onto the lower toe wall.
for yy in range(95):
    blend=max(0,min(1,(yy-60)/35))
    a[yy,:,:]=np.uint8(a[yy,:,:]*blend+np.array([9,10,11])*(1-blend))
# Replace the photographed screw with the separately modelled hardware.
for yy in range(488,580):
    for xx in range(548,612):
        rr=((xx-580)/30)**2+((yy-538)/44)**2
        blend=max(0,min(1,(rr-.65)/.35))
        a[yy,xx]=np.uint8(a[yy,xx]*blend+np.array([12,13,14])*(1-blend))
# Preserve product markings and panels while reducing baked highlight intensity.
a = np.uint8(np.clip(a.astype(float)*0.86+4,0,255))
Image.fromarray(a).save(TEX/'sole_basecolor.png',optimize=True)
# Extract the actual script logo from the supplied side view into a small decal.
logo = Image.open(ROOT/'references/view_04.png').convert('RGB').crop((405,749,588,824))
la=np.asarray(logo).astype(float)
alpha=np.uint8(np.clip((la.min(axis=2)-115)/105,0,1)*255)
rgba=np.full((*alpha.shape,4),235,dtype=np.uint8); rgba[:,:,3]=alpha
Image.fromarray(rgba).resize((732,300),Image.Resampling.LANCZOS).save(TEX/'titleist_decal.png')
# The independent face contour samples the actual scoring and edge geometry.
face=Image.open(ROOT/'references/view_05.png').convert('RGB').crop((60,615,478,834))
face.save(TEX/'face_basecolor.png',optimize=True)
print('Prepared three texture images for the head.')

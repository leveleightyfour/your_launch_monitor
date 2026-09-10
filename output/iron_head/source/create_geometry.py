"""Analytic rounded head with sculpted back and smooth-union hosel, sampled as an isosurface."""
from pathlib import Path
import numpy as np, json, time
ROOT=Path(__file__).resolve().parents[1]
p=json.loads((ROOT/'source/shape.json').read_text())
points=np.array(p['face_outline'],float)
points=(points-np.array(p['origin_pixel']))*p['metres_per_pixel_estimate'];points[:,1]*=-1

def spline(points,n=7):
    out=[]
    for i in range(len(points)):
        a,b,c,d=[points[j%len(points)] for j in (i-1,i,i+1,i+2)]
        for t in np.arange(n)/n:out.append(.5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t**3))
    return np.array(out)

def sdf_poly(X,Z,poly):
    dist=np.full(np.broadcast_shapes(X.shape,Z.shape),np.inf,dtype=np.float32);inside=np.zeros(dist.shape,bool)
    for a,b in zip(poly,np.roll(poly,-1,axis=0)):
        dx,dz=b-a;t=np.clip(((X-a[0])*dx+(Z-a[1])*dz)/(dx*dx+dz*dz),0,1)
        dist=np.minimum(dist,(X-a[0]-t*dx)**2+(Z-a[1]-t*dz)**2)
        inside^=((a[1]>Z)!=(b[1]>Z))&(X<(b[0]-a[0])*(Z-a[1])/(b[1]-a[1]+1e-20)+a[0])
    return np.sqrt(dist)*np.where(inside,-1,1)

def smoothstep(a,b,t):
    q=np.clip((t-a)/(b-a),0,1);return q*q*(3-2*q)

def smin(a,b,k):
    h=np.clip(.5+.5*(b-a)/k,0,1);return b*(1-h)+a*h-k*h*(1-h)

step=.00028
xs=np.arange(-.043,.084,step,dtype=np.float32)
ys=np.arange(-.047,.022,step,dtype=np.float32)
zs=np.arange(-.007,.088,step,dtype=np.float32)
X=xs[:,None];Z=zs[None,:]
outline=spline(points)
D=sdf_poly(X,Z,outline)
# Trace each rear structure independently from the supplied back photo.
rear=json.loads((ROOT/'source/back_contours.json').read_text());A=[];B=[]
for (x,z),(u,v) in zip(rear['mapping_image_points'],rear['mapping_face_local_m']):
    A.extend([[x,z,1,0,0,0,-u*x,-u*z],[0,0,0,x,z,1,-v*x,-v*z]]);B.extend([u,v])
H=np.r_[np.linalg.solve(A,B),1].reshape(3,3)
def project(points):
    q=np.c_[points,np.ones(len(points))]@H.T;return q[:,:2]/q[:,2:]
pocket=spline(project(rear['recess_outer']),7)
inner_contour=spline(project(rear['recess_inner']),7)
P=sdf_poly(X,Z,pocket);Q=sdf_poly(X,Z,inner_contour)
rail=project(rear['sole_rail_crest']);rd=np.full(np.broadcast_shapes(X.shape,Z.shape),1.)
for a,b in zip(rail,rail[1:]):
    dx,dz=b-a;t=np.clip(((X-a[0])*dx+(Z-a[1])*dz)/(dx*dx+dz*dz),0,1)
    rd=np.minimum(rd,np.sqrt((X-a[0]-dx*t)**2+(Z-a[1]-dz*t)**2))
def baseline(z):return .0155-.011*smoothstep(.004,.054,z)+.0006*np.exp(-((z-.008)/.004)**2)
base=baseline(Z)+.0015*np.exp(-(rd/.0030)**2)
mask=smoothstep(0,.0012,-P);inner=smoothstep(-.0001,.0011,-Q)
# The shared points define real oblique planes and the centre pad's crease lines.
heights={(199,158):.0003,(213,178):.0009,(243,286):.0011,(332,191):.0014,(351,207):.0015,(312,271):-.0003}
target=np.broadcast_to(baseline(Z)-.0021,P.shape).copy()
for key in ['left_facet','centre_facet','heel_facet']:
    pixels=rear[key];poly=project(pixels)
    depth=np.array([baseline(pt[1])-.0023+.65*heights.get(tuple(px),0) for px,pt in zip(pixels,poly)])
    for j in range(1,len(poly)-1):
        ids=[0,j,j+1];a,b,c_=poly[ids];den=(b[1]-c_[1])*(a[0]-c_[0])+(c_[0]-b[0])*(a[1]-c_[1])
        u=((b[1]-c_[1])*(X-c_[0])+(c_[0]-b[0])*(Z-c_[1]))/den
        v=((c_[1]-a[1])*(X-c_[0])+(a[0]-c_[0])*(Z-c_[1]))/den;w=1-u-v
        inside=(u>=0)&(v>=0)&(w>=0)
        target=np.where(inside,u*depth[ids[0]]+v*depth[ids[1]]+w*depth[ids[2]],target)
back=base-mask*.0040
back=back*(1-inner)+target*inner
# A very small spatial filter rounds forged creases without removing the distinct planes.
for _ in range(5):back=(4*back+np.roll(back,1,0)+np.roll(back,-1,0)+np.roll(back,1,1)+np.roll(back,-1,1))/8
L=np.deg2rad(p['loft_degrees_estimate']);c=np.cos(L);s=np.sin(L)
axis=np.array([.48,0,.877268]);axis/=np.linalg.norm(axis)
top=np.array([.068,.012,.064])
path=np.array([[.036,.020,.008],[.044,.020,.018],[.051,.015,.032],[.060,.012,.049],top])
radii=np.array([.004,.0064,.0064,.0064,.0064])
# Open Catmull-Rom path avoids the lumps of intersecting large capsules.
cp_=np.column_stack((path,radii));sampled=[]
for k in range(len(cp_)-1):
    a,b,c_,d=[cp_[min(len(cp_)-1,max(0,q))] for q in (k-1,k,k+1,k+2)]
    for t in np.arange(6)/6:sampled.append(.5*(2*b+(-a+c_)*t+(2*a-5*b+4*c_-d)*t*t+(-a+3*b-3*c_+d)*t**3))
sampled=np.array(sampled+[cp_[-1]]);path=sampled[:,:3];radii=sampled[:,3]
from PIL import Image
rough=(.20+.17*smoothstep(.0004,.0018,-Q))*255
# Image U is X, V is face-local Z.
Image.fromarray(rough.T[::-1].astype('uint8')).convert('RGB').resize((1024,1024),Image.Resampling.BICUBIC).save(ROOT/'textures/body_roughness.png')
field=np.empty((len(xs),len(ys),len(zs)),np.float32)
print('Grid',field.shape,flush=True)
for j,Y in enumerate(ys):
    # Rounded extrusion. Face stays exactly planar except at the polished rim.
    r=.00085+.0018*(1-smoothstep(.000,.008,Z));q0=D+r;q1=np.maximum(-Y,Y-back)+r
    body=np.sqrt(np.maximum(q0,0)**2+np.maximum(q1,0)**2)+np.minimum(np.maximum(q0,q1),0)-r
    wy=c*Y+s*Z;wz=-s*Y+c*Z
    neck=np.full(body.shape,1.,np.float32)
    for a,b,ra,rb in zip(path,path[1:],radii,radii[1:]):
        dv=b-a;t=np.clip(((X-a[0])*dv[0]+(wy-a[1])*dv[1]+(wz-a[2])*dv[2])/np.dot(dv,dv),0,1)
        dd=np.sqrt((X-a[0]-t*dv[0])**2+(wy-a[1]-t*dv[1])**2+(wz-a[2]-t*dv[2])**2)-(ra+t*(rb-ra))
        neck=np.minimum(neck,dd)
    axial=(X-top[0])*axis[0]+(wy-top[1])*axis[1]+(wz-top[2])*axis[2]
    neck=np.maximum(neck,axial)
    union=smin(body,neck,.0055)
    # Real shaft socket, blind drilled 20mm into the head; no shaft geometry.
    radial=np.sqrt(np.maximum(0,(X-top[0])**2+(wy-top[1])**2+(wz-top[2])**2-axial**2))
    bore=np.maximum(radial-.00445,-axial-.020)
    field[:,j,:]=np.maximum(union,-bore)

np.save(ROOT/'source/field.npy',field)
np.savez(ROOT/'source/grid.npz',origin=[xs[0],ys[0],zs[0]],step=step)
# Vectorized marching tetrahedra, sharing edge intersections after welding.
shape=np.array(field.shape);corner=np.array([[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]])
lo=np.minimum.reduce([field[a:a+shape[0]-1,b:b+shape[1]-1,c_:c_+shape[2]-1] for a,b,c_ in corner])
hi=np.maximum.reduce([field[a:a+shape[0]-1,b:b+shape[1]-1,c_:c_+shape[2]-1] for a,b,c_ in corner])
cells=np.stack(np.where((lo<0)&(hi>=0)),axis=1)
del lo,hi
print('Boundary cells',len(cells),flush=True)
ci=cells[:,None,:]+corner[None,:,:]
cv=field[ci[:,:,0],ci[:,:,1],ci[:,:,2]]
cp=np.array([xs[0],ys[0],zs[0]])+ci*step
alltris=[]
for tet in [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]:
    vals=cv[:,tet];coords=cp[:,tet];codes=np.sum((vals<0)*np.array([1,2,4,8]),axis=1)
    for code in range(1,15):
        sel=codes==code
        if not sel.any():continue
        v=vals[sel];p_=coords[sel];inside=[i for i in range(4) if code&(1<<i)];outside=[i for i in range(4) if not code&(1<<i)]
        def edge(a,b):
            t=v[:,a]/(v[:,a]-v[:,b]);return p_[:,a]+t[:,None]*(p_[:,b]-p_[:,a])
        if len(inside)==1:alltris.append(np.stack([edge(inside[0],b) for b in outside],axis=1))
        elif len(inside)==3:alltris.append(np.stack([edge(outside[0],b) for b in inside],axis=1))
        else:
            a,b=inside;u,v_=outside;e0=edge(a,u);e1=edge(a,v_);e2=edge(b,u);e3=edge(b,v_)
            alltris.extend([np.stack([e0,e1,e2],axis=1),np.stack([e1,e3,e2],axis=1)])
tri=np.concatenate(alltris).reshape(-1,3)
# Quantized coordinates remove duplicate intersections along shared tetrahedron edges.
verts,inv=np.unique(np.round(tri/1e-8).astype(np.int32),axis=0,return_inverse=True)
verts=verts.astype(np.float32)*1e-8;faces=inv.reshape(-1,3)
valid=(faces[:,0]!=faces[:,1])&(faces[:,0]!=faces[:,2])&(faces[:,1]!=faces[:,2]);faces=faces[valid]
np.savez_compressed(ROOT/'source/geometry.npz',vertices=verts,faces=faces,outline=outline,pocket=pocket)
print('Saved',len(verts),'vertices',len(faces),'triangles',flush=True)

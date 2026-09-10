"""Build the referenced Srixon ZXi7 7-iron head, native Blender and portable GLB."""
import bpy,bmesh,math,json,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];PROJECT=ROOT.parents[1];TEX=ROOT/'textures'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.name='ZXi7 • head inspection';scene.unit_settings.system='METRIC';scene.unit_settings.length_unit='MILLIMETERS'
model=bpy.data.collections.new('ZXi7 • 7-iron head');scene.collection.children.link(model)
studio=bpy.data.collections.new('Studio • excluded from GLB');scene.collection.children.link(studio)
root=bpy.data.objects.new('Srixon_ZXi7_7_Head',None);model.objects.link(root)
root['scope']='7-iron head, integrated hosel and short ferrule; no shaft or grip'
root['construction']='Photo-informed approximation from five supplied product photos, not manufacturer CAD'
root['units']='metres';root['estimated_loft_degrees']=32

def mat(name,color,metal=.9,rough=.24,tex=None,alpha=False):
    m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough;m.diffuse_color=(*color,1)
    if tex:
        t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(TEX/tex),check_existing=True);m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
        if alpha:m.node_tree.links.new(t.outputs['Alpha'],p.inputs['Alpha']);m.surface_render_method='DITHERED'
    return m
chrome=mat('Forged steel • polished perimeter',(.65,.68,.71),1,.19)
frontchrome=mat('Polished steel • face rim',(.65,.68,.71),1,.22)
satin=mat('PureFrame • satin forged facets',(.52,.54,.55),1,.35)
face=mat('Milled face • brushed steel and recessed scorelines',(.55,.56,.57),1,.52,'face_color.png')
p=face.node_tree.nodes.get('Principled BSDF');n=face.node_tree.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(TEX/'face_normal.png'));n.image.colorspace_settings.name='Non-Color';normal=face.node_tree.nodes.new('ShaderNodeNormalMap');face.node_tree.links.new(n.outputs['Color'],normal.inputs['Color']);face.node_tree.links.new(normal.outputs['Normal'],p.inputs['Normal'])
ferrulemat=mat('Ferrule • polished black',(.003,.004,.005),.05,.28)



def mesh(name,v,f,material,uv=None):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update();ob=bpy.data.objects.new(name,me);model.objects.link(ob);ob.parent=root;me.materials.append(material)
    if uv:
        layer=me.uv_layers.new(name='UVMap')
        for loop in me.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
    return ob

def apply(ob,mod):
    bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)

geo=np.load(ROOT/'source/geometry.npz');body=mesh('Head and hosel • single forged surface',geo['vertices'].tolist(),geo['faces'].tolist(),chrome)
print('Loaded implicit surface',flush=True)
bm=bmesh.new();bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-9)
bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
print('Pre-decimation boundary edges',sum(len(e.link_faces)!=2 for e in bm.edges),flush=True)
assert all(len(e.link_faces)==2 for e in bm.edges), 'Input surface must be watertight before decimation'
bm.to_mesh(body.data);bm.free()
# Preserve the field's planar face and cavity facets while reducing its dense sampling.
d=body.modifiers.new('Mobile mesh reduction','DECIMATE');d.ratio=.065;apply(body,d)
bm=bmesh.new();bm.from_mesh(body.data)
for _ in range(3):
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bad=[f for f in bm.faces if f.calc_area()<5e-14]
    if not bad:break
    edges=set(min(f.edges,key=lambda e:e.calc_length()) for f in bad);bmesh.ops.collapse(bm,edges=list(edges),uvs=True)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(body.data);bm.free()
body.data.materials.append(satin)
body.data.materials.append(frontchrome)
# Smooth roughness transition across the recess, independent of triangle boundaries.
roughpath=TEX/'body_roughness.png'
if roughpath.exists():
    t=chrome.node_tree.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(roughpath));t.image.colorspace_settings.name='Non-Color';chrome.node_tree.links.new(t.outputs['Color'],chrome.node_tree.nodes.get('Principled BSDF').inputs['Roughness'])
    uv=body.data.uv_layers.new(name='UVMap')
    for loop in body.data.loops:
        v=body.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=((v.x+.043)/(.00028*453),(v.z+.007)/(.00028*339))
np.savez_compressed(ROOT/'source/reduced_geometry.npz', vertices=np.array([v.co[:] for v in body.data.vertices]), faces=np.array([p.vertices[:] for p in body.data.polygons]))
# Assign satin only within the recessed central pocket; leave the rim polished.
pocket=geo['pocket']
def pd(x,z):
    inside=False;dist=1.
    for a,b in zip(pocket,np.roll(pocket,-1,axis=0)):
        dx,dz=b-a;t=max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)));dist=min(dist,math.hypot(x-a[0]-t*dx,z-a[1]-t*dz))
        if (a[1]>z)!=(b[1]>z) and x<(b[0]-a[0])*(z-a[1])/(b[1]-a[1])+a[0]:inside=not inside
    return -dist if inside else dist
for p in body.data.polygons:
    p.use_smooth=True
    # Continuous material prevents jagged boundaries between sampled triangles.
    p.material_index=2 if p.center.y<.0009 and p.normal.y<-.3 else 0
# Field-gradient normals keep the analytic surfaces smooth after mesh reduction.
fld=np.load(ROOT/'source/field.npy',mmap_mode='r');grid=np.load(ROOT/'source/grid.npz');origin=grid['origin'];step=float(grid['step'])
pos=np.array([v.co[:] for v in body.data.vertices]);q=(pos-origin)/step

def sample(q):
    low=np.floor(q).astype(int);f=q-low;result=np.zeros(len(q))
    low=np.clip(low,0,np.array(fld.shape)-2)
    for a in (0,1):
        for b in (0,1):
            for c in (0,1):result+=fld[low[:,0]+a,low[:,1]+b,low[:,2]+c]*((f[:,0] if a else 1-f[:,0])*(f[:,1] if b else 1-f[:,1])*(f[:,2] if c else 1-f[:,2]))
    return result
norm=np.stack([sample(q+np.eye(3)[k]*.6)-sample(q-np.eye(3)[k]*.6) for k in range(3)],axis=1)
norm/=np.maximum(np.linalg.norm(norm,axis=1)[:,None],1e-15)
corner=[norm[loop.vertex_index].tolist() for loop in body.data.loops]
for polygon in body.data.polygons:
    if all(abs(body.data.vertices[v].co.y)<2e-6 for v in polygon.vertices):
        for li in polygon.loop_indices:corner[li]=(0,-1,0)
body.data.normals_split_custom_set(corner)
print('Reduced surface',len(body.data.polygons),flush=True)
# The scoring patch shares the exact face plane. Grooves use a portable tangent normal map.
coords=[(199,337),(543,483),(543,659),(199,659)]
v=[((x-325)*.00017,-.000014,(670-z)*.00017) for x,z in coords];uv=[((x-197)/349,(663-z)/332) for x,z in coords]
patch=mesh('Face • 13 stepped scorelines',v,[(2,1,0),(3,2,0)],face,uv)
# BVH conforms the markings to actual sculpted geometry rather than floating on a plane.
bm=bmesh.new();bm.from_mesh(body.data);tree=BVHTree.FromBMesh(bm);bm.free()
def decal(name,texture,cx,cz,w,h,angle=0,sole=False):
    material=mat(name+' • black inlay',(.006,.006,.006),.1,.35,texture,True)
    vs=[];uv=[];fs=[];nx=32;ny=12;a=math.radians(angle)
    for j in range(ny+1):
        for i in range(nx+1):
            u=i/nx;v=j/ny;dx=(u-.5)*w;dz=-(v-.5)*h
            x=cx+math.cos(a)*dx-math.sin(a)*dz;z=cz+math.sin(a)*dx+math.cos(a)*dz
            if sole:
                loc,n,_,_=tree.ray_cast(Vector((x,z,-.015)),Vector((0,0,1)))
            else:loc,n,_,_=tree.ray_cast(Vector((x,.04,z)),Vector((0,-1,0)))
            if loc is None:raise ValueError('Decal misses surface '+name+str((x,z)))
            vs.append(tuple(loc+n*.000022));uv.append((u,v))
    for j in range(ny):
        for i in range(nx):
            k=j*(nx+1)+i;fs.extend([(k,k+1,k+nx+2),(k,k+nx+2,k+nx+1)])
    ob=mesh(name,vs,fs,material,uv)
    for p in ob.data.polygons:p.use_smooth=True
    return ob

decal('Srixon • original reference wordmark','srixon.png',-.019,.0355,.015,.0045,20)
decal('ZXi7 • model marking','zxi7.png',-.020,.0495,.017,.0048,-15)
decal('PureFrame • upper rail','pureframe.png',.017,.038,.019,.0015,-26)
decal('7 • sole identification','seven.png',-.024,.008,.005,.007,0,True)
# Rotate blade to its estimated playing loft; hosel was already defined in world space then inverse-transformed.
R=Matrix.Rotation(math.radians(-32),4,'X')
for ob in list(model.objects):
    if ob.type=='MESH':ob.data.transform(R)
axis=Vector((.48,0,.877268)).normalized();top=Vector((.068,.012,.064));u=Vector((0,1,0));v=axis.cross(u).normalized()
# A tubular ferrule with an open socket. No shaft or grip is present.
def tube(name,profile,material):
    n=96;verts=[];faces=[]
    for t,r in profile:
        for i in range(n):verts.append(tuple(top+axis*t+r*(u*math.cos(2*math.pi*i/n)+v*math.sin(2*math.pi*i/n))))
    for j in range(len(profile)):
        j2=(j+1)%len(profile)
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,j2*n+(i+1)%n,j2*n+i))
    ob=mesh(name,verts,faces,material)
    bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(ob.data);bm.free()
    for p in ob.data.polygons:p.use_smooth=True
    return ob
tube('Ferrule • short black taper',[(0,.00638),(.0004,.00652),(.013,.00595),(.015,.00555),(.015,.00445),(0,.00445)],ferrulemat)
tube('Ferrule • fine silver trim',[(.014,.0058),(.0146,.00566),(.0146,.00554),(.014,.00565)],chrome)
# Small forged stamp follows the back of the cylindrical neck.
m=mat('i-FORGED • hosel marking',(.006,.006,.006),.1,.3,'forged.png',True)
vs=[];uv=[];fs=[]
for j in range(25):
    for i in range(9):
        a=(i/8-.5)*.52;t=-.003-j/24*.011
        pos=top+axis*t+.00653*(u*math.cos(a)+v*math.sin(a));vs.append(tuple(pos));uv.append((j/24,i/8))
for j in range(24):
    for i in range(8):k=j*9+i;fs.extend([(k,k+1,k+10),(k,k+10,k+9)])
mesh('i-FORGED • hosel stamp',vs,fs,m,uv)
world=bpy.data.worlds.new('Soft grey studio');scene.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.30,.32,.35,1);world.node_tree.nodes['Background'].inputs[1].default_value=.45

def area(name,pos,power,size,sy,color=(1,1,1)):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='RECTANGLE';d.size=size;d.size_y=sy;d.color=color;ob=bpy.data.objects.new(name,d);studio.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((.01,.008,.026))-ob.location).to_track_quat('-Z','Y').to_euler()
area('Key softbox',(-.09,-.12,.15),1.8,.07,.18,(1,.98,.94))
area('Back broad card',(-.04,.14,.08),1.2,.10,.20)
area('Heel strip',(.16,.05,.09),1.5,.025,.18,(.88,.94,1))
area('Lower strip',(-.09,.08,-.06),.65,.025,.16)
area('Face card',(.03,-.18,.04),.5,.035,.20)

def cam(name,pos,target,scale,roll=0):
    d=bpy.data.cameras.new(name);d.type='ORTHO';d.ortho_scale=scale;d.clip_start=.001;d.clip_end=10;ob=bpy.data.objects.new(name,d);studio.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();ob.rotation_euler.rotate_axis('Z',roll);return ob
center=(.021,.006,.034)
cams={
'back':cam('01 • Back and cavity',(-.025,.26,-.09),center,.172,math.pi+.30),
'face':cam('02 • Face outline',(.019,-.28,.204),center,.153),
'hero':cam('03 • Face and hosel',(-.12,-.25,.14),center,.165),
'side':cam('04 • Toe and sole profile',(-.25,.016,.055),(.004,.013,.027),.145),
'hosel':cam('05 • Continuous heel and hosel',(.10,-.19,.10),(.046,.014,.030),.085),
'sole':cam('06 • Sole and cavity',(-.04,.10,-.21),(.01,.007,.029),.155,math.pi)
}
scene.camera=cams['back'];scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=True;scene.render.resolution_x=1400;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True;scene.view_settings.view_transform='AgX'
# Export only the asset collection; all textures are embedded.
bpy.ops.object.select_all(action='DESELECT')
for ob in model.objects:ob.select_set(True)
bpy.context.view_layer.objects.active=body
out=PROJECT/'assets/models/srixon_zxi7_7_head.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_apply=True,export_yup=True,export_extras=True)
for img in bpy.data.images:
    if img.source=='FILE':img.pack()
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            sp=a.spaces.active;sp.clip_start=.001;sp.clip_end=10;sp.shading.type='MATERIAL';sp.overlay.show_overlays=False;sp.region_3d.view_distance=.21;sp.region_3d.view_location=Vector(center);sp.region_3d.view_rotation=cams['back'].rotation_euler.to_quaternion();sp.region_3d.view_perspective='ORTHO'
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);bpy.context.view_layer.objects.active=body
note=bpy.data.texts.new('START HERE • model notes');note.write('SRIXON ZXi7 — 7-IRON HEAD\n\nHead with continuous forged hosel and short ferrule. No shaft or grip.\nFive supplied product images; estimated dimensions and 32-degree loft.\nThis is a visual reconstruction, not manufacturer CAD or a scan.\n\nAll material images are packed. Cameras 01–06 inspect the back, face,\nhosel, side and sole. Studio is excluded from the GLB.\nMiddle mouse orbits. Numpad . frames the selected head.\n\nBlender: +X heel, +Y rear, +Z up; metres. GLB: Y up.\nGrooves use a tangent normal map; cavity and hosel are actual geometry.\n')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'srixon_zxi7_7_head.blend'))
tris=0
for o in model.objects:
    if o.type=='MESH':o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
info={'name':'Srixon ZXi7 7-iron head','scope':'Head, hosel and short ferrule only. No shaft or grip.','source_photos':[575,578,579,580,581],'units':'metres','loft_degrees_estimate':32,'mesh_objects':sum(o.type=='MESH' for o in model.objects),'triangles':tris,'glb_bytes':out.stat().st_size,'notes':['Asymmetric blade outline traced from front photo.','Cavity, forged facets, sole and continuous hosel are geometry.','13 stepped scorelines use a portable tangent normal texture.','Scale, loft and hidden surfaces are inferred; not manufacturer CAD.']}
(ROOT/'model_info.json').write_text(json.dumps(info,indent=2))
for key in ['face','back','hosel','side','hero','sole']:
    scene.camera=cams[key];scene.render.filepath=str(ROOT/(key+'.png'));bpy.ops.render.render(write_still=True)
print('DONE',json.dumps(info),flush=True)

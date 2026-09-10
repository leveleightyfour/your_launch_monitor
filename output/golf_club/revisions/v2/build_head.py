"""Build a photo-informed Titleist GT2 head, render previews, export native + GLB.
Run: Blender --background --python output/golf_club/source/build_head.py
Units: metres. Blender X=heel, Y=rear, Z=up. Head/hosel only.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector
from math import sin, cos, pi, copysign
ROOT=Path(__file__).resolve().parents[1]
PROJECT=ROOT.parents[1]
TEX=ROOT/'textures'
OUT=PROJECT/'assets/models'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.name='GT2 • Head inspection'
scene.unit_settings.system='METRIC'
scene.unit_settings.length_unit='MILLIMETERS'
model_col=bpy.data.collections.new('GT2 • Head and adjustable hosel')
scene.collection.children.link(model_col)
studio_col=bpy.data.collections.new('Studio • cameras and lighting (not exported)')
scene.collection.children.link(studio_col)
root=bpy.data.objects.new('GT2_Head',None)
model_col.objects.link(root)
root['description']='Photo-informed Titleist GT2 driver head, 9.0 marking. Approximate geometry, not a CAD scan.'
root['units']='metres'
root['axes_blender']='X heel; Y rear; Z up. Origin at head centre.'
root['reference_images']='Supplied product views 02, 03, 04, 05.'
root['scope']='Head and adjustable hosel only. No shaft or grip.'

def material(name,color,metallic=0,roughness=.3,texture=None,alpha=False):
    m=bpy.data.materials.new(name); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metallic
    p.inputs['Roughness'].default_value=roughness
    if texture:
        n=m.node_tree.nodes.new('ShaderNodeTexImage')
        n.image=bpy.data.images.load(str(TEX/texture),check_existing=True)
        n.interpolation='Linear'
        m.node_tree.links.new(n.outputs['Color'],p.inputs['Base Color'])
        if alpha:
            m.node_tree.links.new(n.outputs['Alpha'],p.inputs['Alpha'])
            m.surface_render_method='DITHERED'
    m.diffuse_color=(*color,1)
    return m
lacquer=material('Obsidian • polished crown',(.002,.0025,.003),.05,.20)
sole_mat=material('Sole • original photographic graphics',(.02,.02,.02),.45,.33,'sole_basecolor.png')
face_mat=material('Titanium face • etched scoring',(.11,.115,.115),.72,.38,'face_basecolor.png')
edge_mat=material('Face perimeter • dark titanium',(.017,.019,.020),.72,.25)
metal=material('Machined collar and screw',(.26,.28,.29),.92,.25)
black_metal=material('SureFit • anodized black',(.006,.007,.008),.5,.28)
rubber=material('Ferrule • satin black',(.003,.004,.005),.05,.31)
white=material('Ivory identification',(.75,.77,.69),.25,.35)
logo_mat=material('Titleist • reference script decal',(.9,.9,.9),.0,.35,'titleist_decal.png',True)


def objmesh(name,vs,fs,mats,uvs=None,indices=None):
    me=bpy.data.meshes.new(name+' geometry'); me.from_pydata(vs,[],fs); me.update()
    ob=bpy.data.objects.new(name,me); model_col.objects.link(ob); ob.parent=root
    for m in mats: me.materials.append(m)
    if uvs:
        uv=me.uv_layers.new(name='UVMap')
        for p in me.polygons:
            for li in p.loop_indices: uv.data[li].uv=uvs[me.loops[li].vertex_index]
    if indices:
        for p,mi in zip(me.polygons,indices): p.material_index=mi
    bm=bmesh.new();bm.from_mesh(me); bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7); bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free()
    for p in me.polygons: p.use_smooth=True
    return ob

# Smooth longitudinal sections reconstructed from the crown, sole and side silhouettes.
# y, half width, half height, vertical centre, lateral centre
sections=[(-.044,.0591,.0282,.002,.002),(-.039,.0593,.0284,.002,.0025),
          (-.027,.0595,.0285,.0015,.003),(-.011,.059,.0275,.000,.004),
          (.008,.0545,.0255,-.002,.005),(.028,.046,.0195,-.0045,.006),
          (.046,.033,.0125,-.007,.007),(.060,.0175,.0065,-.0085,.008),
          (.066,.0075,.0028,-.009,.008),(.068,0,0,-.009,.008)]

def interp(y):
    k=next((i for i in range(len(sections)-1) if y<=sections[i+1][0]),len(sections)-2)
    a=sections[k];b=sections[k+1];t=max(0,min(1,(y-a[0])/(b[0]-a[0])))
    res=[]
    for c in range(1,5):
        prev=sections[max(0,k-1)];nxt=sections[min(len(sections)-1,k+2)]
        da=(b[c]-prev[c])/(b[0]-prev[0]);db=(nxt[c]-a[c])/(nxt[0]-a[0])
        v=(2*t**3-3*t*t+1)*a[c]+(t**3-2*t*t+t)*(b[0]-a[0])*da+(-2*t**3+3*t*t)*b[c]+(t**3-t*t)*(b[0]-a[0])*db
        res.append(v)
    return res

def sp(v,p):return copysign(abs(v)**p,v)

# Independent image-space traces replace the old symmetric superellipse.
from functools import lru_cache
PROFILE=json.loads((ROOT/'source/front_profile.json').read_text())
PIXEL_SCALE=PROFILE['metres_per_pixel_estimate']

def sampled_contour(points):
    curve=[]
    for i,p in enumerate(points):
        p0=Vector(points[(i-1)%len(points)]);p1=Vector(p)
        p2=Vector(points[(i+1)%len(points)]);p3=Vector(points[(i+2)%len(points)])
        for j in range(16):
            t=j/16
            a=.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            curve.append(Vector(((260-a.x)*PIXEL_SCALE,(724-a.y)*PIXEL_SCALE)))
    return curve

CONTOURS={key:sampled_contour(PROFILE[key]) for key in ['head_outline','face_insert']}
def cross2(a,b):return a.x*b.y-a.y*b.x

@lru_cache(maxsize=8192)
def front_profile(theta,kind='head_outline'):
    direction=Vector((.0572*cos(theta),.0266*sin(theta)))
    curve=CONTOURS[kind]; hits=[]
    for a,b in zip(curve,curve[1:]+curve[:1]):
        edge=b-a;den=cross2(direction,edge)
        if abs(den)<1e-15:continue
        t=cross2(a,edge)/den;u=cross2(a,direction)/den
        if t>0 and 0<=u<=1:hits.append(t)
    if not hits:raise ValueError((theta,kind))
    p=direction*min(hits)
    return Vector((.002+p.x,.002+p.y))

def body_point(y,theta):
    rx,rz,cz,cx=interp(y)
    p=front_profile(theta)
    # The entire frontal envelope follows the asymmetric trace. Deeper rings
    # shrink inside it, instead of restoring an oval behind the traced face.
    width_scale=rx/.0595
    height_scale=rz/.0285
    x=.002+(p.x-.002)*width_scale+(cx-.002)*.28
    z=.002+(p.y-.002)*height_scale+(cz-.002)*.30
    front_weight=max(0,1-(y+.044)/.030)**2
    yy=y+front_weight*(math.tan(math.radians(9))*(z-.002)+1.1*(x-.002)**2)
    return Vector((x,yy,z))

N=96; ROWS=52
ys=[-.044+(.068+.044)*i/ROWS for i in range(ROWS)]
v=[];uv=[];f=[];mi=[]
for y in ys:
    for j in range(N):
        p=body_point(y,2*pi*j/N);v.append(p)
        # Camera projection onto the sole, with the photo's heel and toe kept in register.
        px=650-(p.y+.041)/.109*554
        py=321-(p.x-.002)/.063*308
        uv.append((px/755,1-py/1017))
for i in range(ROWS-1):
    for j in range(N):
        f.append((i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j))
        mi.append(1 if sin(2*pi*(j+.5)/N)<-.42 else 0)
v.append(Vector((.00368,.068,-.0013)));uv.append((.12,.68))
for j in range(N):
    f.append(((ROWS-1)*N+j,(ROWS-1)*N+(j+1)%N,len(v)-1))
    mi.append(1 if sin(2*pi*(j+.5)/N)<-.42 else 0)
body=objmesh('Head shell • rounded pear profile',v,f,[lacquer,sole_mat],uv,mi)
# Independently traced metal face surrounded by an asymmetric black cheek.
# Interpolate between two contours; a uniform inset would erase the wide toe.
face_center=Vector((.002,-.0453,.002))
v=[face_center];uv=[((260-60)/418,1-(724-615)/219)];f=[];mi=[]
levels=[('insert',i/16) for i in range(1,17)]+[('cheek',i/6) for i in range(1,7)]
for kind,t in levels:
    for j in range(N):
        theta=2*pi*j/N
        outer=body_point(-.044,theta)
        inset=front_profile(theta,'face_insert')
        if kind=='insert':
            x=.002+(inset.x-.002)*t;z=.002+(inset.y-.002)*t
        else:
            x=inset.x*(1-t)+outer.x*t;z=inset.y*(1-t)+outer.z*t
        rim_ratio=((x-.002)/.0572)**2+((z-.002)/.0266)**2
        # A continuous bulged surface, relaxing to the exact shell at the rim.
        bulge=(1-t)*.00065 if kind=='cheek' else .00065+.0005*(1-t*t)
        y=-.044+math.tan(math.radians(9))*(z-.002)+1.1*(x-.002)**2-bulge
        px=260-(x-.002)/PIXEL_SCALE;py=724-(z-.002)/PIXEL_SCALE
        v.append(Vector((x,y,z)));uv.append(((px-60)/418,1-(py-615)/219))
for j in range(N):f.append((0,1+(j+1)%N,1+j));mi.append(0)
for i in range(len(levels)-1):
    for j in range(N):
        f.append((1+i*N+j,1+i*N+(j+1)%N,1+(i+1)*N+(j+1)%N,1+(i+1)*N+j))
        mi.append(0 if i<15 else 1)
face=objmesh('Forged face • traced asymmetric insert and toe cheek',v,f,[face_mat,lacquer],uv,mi)
# Weld the face boundary into the shell so reflections flow over the rim.
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True);face.select_set(True);bpy.context.view_layer.objects.active=body
bpy.ops.object.join()
bm=bmesh.new();bm.from_mesh(body.data)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bm.to_mesh(body.data);bm.free();body.data.update()
body.name='Head shell and face • traced asymmetric profile'
body.select_set(False)
# Script logo hugs the toe-side shell rather than floating on a flat card.
v=[];f=[];uv=[];NX=32;NY=10
for j in range(NY+1):
    for i in range(NX+1):
        u=i/NX;vv=j/NY
        p=body_point(.008-u*.035,.26+vv*.45)
        p.x+=.00011
        v.append(p);uv.append((u,vv))
for j in range(NY):
    for i in range(NX):
        a=j*(NX+1)+i;f.append((a,a+1,a+NX+2,a+NX+1))
objmesh('Toe-side Titleist script',v,f,[logo_mat],uv)


def move_to_model(ob):
    for c in list(ob.users_collection):c.objects.unlink(ob)
    model_col.objects.link(ob);ob.parent=root
    return ob

axis=Vector((-.53,.018,.848)).normalized()
base=Vector((-.046,-.031,.012))

def tube(name,start,axis,profile,mat,n=64):
    """Lathed hollow/capped part. Profile follows the axis with varying radii."""
    axis=Vector(axis).normalized();ex=axis.cross(Vector((0,1,0))).normalized();ey=axis.cross(ex)
    v=[];f=[];uv=[]
    for i,(t,r) in enumerate(profile):
        for j in range(n):
            a=2*pi*j/n;v.append(Vector(start)+axis*t+r*(ex*cos(a)+ey*sin(a)));uv.append((j/n,i/(len(profile)-1)))
    for i in range(len(profile)-1):
        for j in range(n):f.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
    return objmesh(name,v,f,[mat],uv)

def hosel_tube(name,start,axis,profile,mat,n=64):
    return tube(name,start,axis,[(t*.74,r*(.80+.10*min(1,t/.0505))) for t,r in profile],mat,n)

hosel_tube('Hosel • integrated tapered neck',base,axis,[(-.009,0),(-.005,.003),(0,.005),(.007,.0080),(.014,.0095),(.021,.0080),(.024,.0075)],lacquer)
hosel_tube('SureFit • lower adjustment collar',base,axis,[(.022,.0075),(.023,.0081),(.025,.0082),(.029,.0080),(.030,.0074)],black_metal)
hosel_tube('SureFit • precision silver index band',base,axis,[(.0299,.0074),(.030,.0079),(.0307,.0079),(.0308,.0074)],metal)
hosel_tube('SureFit • upper adjustment collar',base,axis,[(.0308,.0074),(.031,.0078),(.037,.0075),(.038,.0070)],black_metal)
# An open ferrule and visible bore makes the shaft-free model physically readable.
hosel_tube('Ferrule • open shaft socket',base,axis,[(.038,.0071),(.039,.0073),(.046,.0065),(.050,.0060),(.0505,.0058),(.0505,.00455),(.0485,.0045),(.038,.0045)],rubber)
hosel_tube('Socket • inner metal sleeve',base,axis,[(.049,.0045),(.049,.0042),(.033,.0042),(.033,0)],black_metal)

# Real geometry for the screw under the heel, with a six-lobed Torx recess.
sx=-.041;sy=-.026
def sole_point(x,y):
    lo,hi=pi,2*pi
    for _ in range(48):
        mid=(lo+hi)/2
        if body_point(y,mid).x<x:lo=mid
        else:hi=mid
    return body_point(y,(lo+hi)/2)
surface=sole_point(sx,sy)
dx=sole_point(sx+.0001,sy)-sole_point(sx-.0001,sy)
dy=sole_point(sx,sy+.0001)-sole_point(sx,sy-.0001)
down=dx.cross(dy).normalized()
if down.z>0:down=-down
start=surface+down*.00005
screw_u=down.cross(Vector((0,1,0))).normalized();screw_v=down.cross(screw_u)
tube('Sole • recessed weight surround',start,down,[(0,.005),(.0004,.0053),(.001,.0048),(.0011,.0033)],black_metal,48)
tube('Sole • retaining screw',start,down,[(.0008,.0030),(.0011,.0030),(.0014,.0027),(.0014,.00145),(.0009,.00145)],metal,48)
v=[start+down*.00146];f=[]
for j in range(48):
    a=j*2*pi/48;r=.0011*(1+.19*cos(6*a));v.append(start+down*.00148+r*(screw_u*cos(a)+screw_v*sin(a)))
for j in range(48):f.append((0,1+j,1+(j+1)%48))
objmesh('Sole • Torx recess',v,f,[black_metal])

def text_mesh(name,text,pos,size,rotation=(0,0,0),mat=white):
    curve=bpy.data.curves.new(name,'FONT');curve.body=text;curve.size=size;curve.align_x='CENTER';curve.align_y='CENTER';curve.shear=.23;curve.extrude=0
    ob=bpy.data.objects.new(name,curve);model_col.objects.link(ob);ob.parent=root;ob.location=pos;ob.rotation_euler=rotation;ob.data.materials.append(mat)
    bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.convert(target='MESH');ob.select_set(False)
    return ob
p=body_point(-.029,pi/2)
# The small GT alignment mark is legible from address position.
align=text_mesh('Crown • GT alignment mark','GT',(p.x,p.y,p.z+.00020),.0042)
# Curved-position tiny collar index marking.
p=base+axis*(.034*.74)+Vector((0,-.0067,0))
text_mesh('SureFit • index A1','A1',p,.0025,(pi/2,0,0))

# Reflect the inferred plan into the reference's right-handed configuration.
# Reverse winding as well, so this is real geometry without negative scale transforms.
for ob in list(model_col.objects):
    if ob.type != 'MESH': continue
    ob.location.x *= -1
    if ob.name not in ['Crown • GT alignment mark','SureFit • index A1']:
        for vertex in ob.data.vertices: vertex.co.x *= -1
        bm=bmesh.new(); bm.from_mesh(ob.data)
        bmesh.ops.reverse_faces(bm,faces=list(bm.faces))
        bm.to_mesh(ob.data); bm.free(); ob.data.update()

# The loft stamp falls outside the reliably projected area of the sole photograph.
stamp_p=sole_point(-.038,.004)
stamp_dx=sole_point(-.0379,.004)-sole_point(-.0381,.004)
stamp_dy=sole_point(-.038,.0041)-sole_point(-.038,.0039)
stamp_n=stamp_dx.cross(stamp_dy).normalized()
if stamp_n.z>0:stamp_n=-stamp_n
stamp_n.x*=-1
stamp_p=Vector((-stamp_p.x,stamp_p.y,stamp_p.z))+stamp_n*.00015
stamp=text_mesh('Sole • loft identification','9.0',stamp_p,.0048)
# Normal direction determines the local text plane; turn the text to follow the sole badge.
stamp.rotation_euler=stamp_n.to_track_quat('Z','Y').to_euler()
stamp.rotation_euler.rotate_axis('Z',pi/2)

# Add saved viewpoints and a neutral, portable material-preview studio.
world=bpy.data.worlds.new('Soft grey studio');scene.world=world;world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.20,.22,.25,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.18

def area(name,loc,power,size,color=(1,1,1),size_y=None):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='RECTANGLE';data.size=size;data.size_y=size_y or size
    data.color=color;ob=bpy.data.objects.new(name,data);studio_col.objects.link(ob);ob.location=loc;ob.rotation_euler=(Vector((0,.006,0))-ob.location).to_track_quat('-Z','Y').to_euler();return ob
area('Key • tall softbox',(.10,-.12,.18),1.3,.10,(1,.96,.9),.28)
area('Rim • long strip',(-.14,.08,.09),1.8,.04,(.82,.89,1),.22)
area('Fill • broad card',(.10,.15,.06),.6,.10,(1,1,1),.22)
area('Sole softbox',(.015,-.03,-.19),.7,.12,(.96,.98,1),.20)
area('Face vertical card',(-.05,-.20,.025),.4,.035,(1,1,1),.15)

def camera(name,pos,target,scale):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);studio_col.objects.link(ob)
    ob.location=pos;ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.type='ORTHO';data.ortho_scale=scale;data.lens=55;data.clip_start=.001;data.clip_end=10
    return ob
cams={
'hero':camera('01 • Face and crown',(-.19,-.26,.17),(.006,.006,.01),.205),
'sole':camera('02 • Sole graphics',(-.07,-.06,-.30),(.008,.005,.004),.205),
'crown':camera('03 • Address view',(.008,.007,.33),(.008,.007,.010),.205),
'face':camera('04 • Face inspection',(.008,-.30,.010),(.008,-.002,.010),.165),
'side':camera('05 • Toe profile',(-.30,.006,.035),(.002,.006,.01),.180),
}
scene.camera=cams['hero']
scene.render.engine='CYCLES';scene.cycles.samples=48
scene.cycles.use_denoising=True
scene.render.resolution_x=1400;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
scene.view_settings.view_transform='AgX'
# Only the asset collection enters the GLB; no lights or cameras.
bpy.ops.object.select_all(action='DESELECT')
for ob in model_col.objects:ob.select_set(True)
bpy.context.view_layer.objects.active=body
bpy.ops.export_scene.gltf(filepath=str(OUT/'titleist_gt2_head.glb'),export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_apply=True,export_yup=True,export_extras=True)
# Save a friendly initial orbit view in Blender with studio material preview.
for screen in bpy.data.screens:
    for area_ in screen.areas:
        if area_.type=='VIEW_3D':
            space=area_.spaces.active;space.clip_start=.001;space.clip_end=10
            space.shading.type='MATERIAL';space.shading.studiolight_rotate_z=.6
            space.overlay.show_overlays=False
            space.region_3d.view_distance=.28;space.region_3d.view_location=Vector((.008,.003,.008))
            space.region_3d.view_rotation=cams['hero'].rotation_euler.to_quaternion()
            space.region_3d.view_perspective='ORTHO'
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);bpy.context.view_layer.objects.active=body
for img in bpy.data.images:
    if img.source=='FILE':img.pack()
readme=bpy.data.texts.new('START HERE • model notes')
readme.write('TITLEIST GT2 — HEAD ONLY\n\nPhoto-informed visual reconstruction, not a dimensional scan.\nHead and hosel only; no shaft or grip. Dimensions are estimates.\nPacked textures: this .blend opens without external image files.\n\nOrbit with middle mouse. Numpad . frames the selected head.\nCameras 01–05 provide face, crown, sole and side inspection views.\nThe separate Studio collection is excluded from the GLB export.\n\nBlender axes: +X heel, +Y rear, +Z up. Metres.\nGLB axes: +X heel, +Y up, +Z face/ball direction.\nThe original photos and rebuild scripts accompany the asset.\n')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'titleist_gt2_head.blend'))
# Statistics are computed from evaluated meshes, not control-point counts.
tri=0;verts=0
for ob in model_col.objects:
    if ob.type=='MESH':ob.data.calc_loop_triangles();tri+=len(ob.data.loop_triangles);verts+=len(ob.data.vertices)
points=[ob.matrix_world@Vector(c) for ob in model_col.objects if ob.type=='MESH' for c in ob.bound_box]
mins=[min(p[i] for p in points) for i in range(3)];maxs=[max(p[i] for p in points) for i in range(3)]
metadata={'revision':2,'name':'Titleist GT2 driver head (photo-informed approximation)','scope':'head and hosel only; no shaft or grip','units':'metres','triangles':tri,'vertices_blender':verts,'mesh_objects':sum(o.type=='MESH' for o in model_col.objects),'bounds_blender_m':{'min':mins,'max':maxs},'dimensions_including_hosel_m':[b-a for a,b in zip(mins,maxs)],'glb_bytes':(OUT/'titleist_gt2_head.glb').stat().st_size,'materials':len(bpy.data.materials),'notes':['Geometry inferred from four photographs; no calibrated dimensions or photogrammetric reconstruction.','Sole graphic is projected from supplied photograph and retains some photographed lighting.','Head and face outlines traced independently from view 05; face scoring uses the supplied photograph.','No shaft or grip included.']}
(ROOT/'model_info.json').write_text(json.dumps(metadata,indent=2))
for name in ['face','hero','sole','crown','side']:
    scene.camera=cams[name];scene.render.filepath=str(ROOT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('DONE',json.dumps(metadata))

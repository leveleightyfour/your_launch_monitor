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
sections=[(-.044,.054,.0255,.002,.002),(-.039,.0575,.0285,.002,.0025),
          (-.027,.0595,.030,.0015,.003),(-.011,.059,.029,.000,.004),
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

def body_point(y,theta):
    rx,rz,cz,cx=interp(y)
    x=cx+rx*sp(cos(theta),.86)
    z=cz+rz*sp(sin(theta),.86)+.0025*(x-cx)/.06
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
v.append(Vector((.008,.068,-.009)));uv.append((.12,.68))
for j in range(N):
    f.append(((ROWS-1)*N+j,(ROWS-1)*N+(j+1)%N,len(v)-1))
    mi.append(1 if sin(2*pi*(j+.5)/N)<-.42 else 0)
body=objmesh('Head shell • rounded pear profile',v,f,[lacquer,sole_mat],uv,mi)
# A continuous face cap with a curved impact surface and a dark perimeter lip.
v=[Vector((.002,-.0453,.002))];uv=[(.5,.5)];f=[];mi=[]
rhos=[i*.945/15 for i in range(1,16)]+[.966,1.0]
for rho in rhos:
    for j in range(N):
        boundary=body_point(-.044,2*pi*j/N)
        x=.002+(boundary.x-.002)*rho;z=.002+(boundary.z-.002)*rho
        y=-.044+math.tan(math.radians(9))*(z-.002)+1.1*(x-.002)**2-.0013*(1-rho*rho)
        v.append(Vector((x,y,z)));uv.append(((x-.002)/.108+.5,(z-.002)/.055+.5))
for j in range(N):f.append((0,1+(j+1)%N,1+j));mi.append(0)
for i in range(len(rhos)-1):
    for j in range(N):
        f.append((1+i*N+j,1+i*N+(j+1)%N,1+(i+1)*N+(j+1)%N,1+(i+1)*N+j))
        mi.append(0 if i<14 else 1)
face=objmesh('Forged face • bulge roll and score lines',v,f,[face_mat,edge_mat],uv,mi)
# Script logo hugs the toe-side shell rather than floating on a flat card.
v=[];f=[];uv=[];NX=32;NY=10
for j in range(NY+1):
    for i in range(NX+1):
        u=i/NX;vv=j/NY
        p=body_point(.008-u*.035,-.12+vv*.47)
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

axis=Vector((-.515,.018,.857)).normalized()
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

tube('Hosel • integrated tapered neck',base,axis,[(0,.0092),(.007,.0102),(.014,.0095),(.021,.0080),(.024,.0075)],lacquer)
tube('SureFit • lower adjustment collar',base,axis,[(.022,.0075),(.023,.0081),(.025,.0082),(.029,.0080),(.030,.0074)],black_metal)
tube('SureFit • precision silver index band',base,axis,[(.0299,.0074),(.030,.0079),(.0307,.0079),(.0308,.0074)],metal)
tube('SureFit • upper adjustment collar',base,axis,[(.0308,.0074),(.031,.0078),(.037,.0075),(.038,.0070)],black_metal)
# An open ferrule and visible bore makes the shaft-free model physically readable.
tube('Ferrule • open shaft socket',base,axis,[(.038,.0071),(.039,.0073),(.046,.0065),(.050,.0060),(.0505,.0058),(.0505,.00455),(.0485,.0045),(.038,.0045)],rubber)
tube('Socket • inner metal sleeve',base,axis,[(.049,.0045),(.049,.0042),(.033,.0042),(.033,0)],black_metal)

# Real geometry for the screw under the heel, with a six-lobed Torx recess.
sx=-.041;sy=-.026
rx,rz,cz,cx=interp(sy)
st= -math.sqrt(max(.0,1-abs((sx-cx)/rx)**(2/.86)))
sz=cz+rz*sp(st,.86)+.0025*(sx-cx)/.06
start=Vector((sx,sy,sz-.0006));down=Vector((0,0,-1))
tube('Sole • recessed weight surround',start,down,[(0,.005),(.0004,.0053),(.001,.0048),(.0011,.0033)],black_metal,48)
tube('Sole • retaining screw',start,down,[(.0008,.0030),(.0011,.0030),(.0014,.0027),(.0014,.00145),(.0009,.00145)],metal,48)
v=[start+down*.00146];f=[]
for j in range(48):
    a=j*2*pi/48;r=.0011*(1+.19*cos(6*a));v.append(start+down*.00148+Vector((r*cos(a),r*sin(a),0)))
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
p=base+axis*.034+Vector((0,-.0077,0))
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
text_mesh('Sole • loft identification','9.0',(.038,.004,-.0242),.0048,(pi,0,-pi/2))

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
'face':camera('04 • Face inspection',(.008,-.30,.035),(.008,-.002,.012),.205),
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
metadata={'name':'Titleist GT2 driver head (photo-informed approximation)','scope':'head and hosel only; no shaft or grip','units':'metres','triangles':tri,'vertices_blender':verts,'mesh_objects':sum(o.type=='MESH' for o in model_col.objects),'bounds_blender_m':{'min':mins,'max':maxs},'dimensions_including_hosel_m':[b-a for a,b in zip(mins,maxs)],'glb_bytes':(OUT/'titleist_gt2_head.glb').stat().st_size,'materials':len(bpy.data.materials),'notes':['Geometry inferred from four photographs; no calibrated dimensions or photogrammetric reconstruction.','Sole graphic is projected from supplied photograph and retains some photographed lighting.','Face scoring and small GT mark are reconstructed.','No shaft or grip included.']}
(ROOT/'model_info.json').write_text(json.dumps(metadata,indent=2))
for name in ['hero','sole','crown','face','side']:
    scene.camera=cams[name];scene.render.filepath=str(ROOT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('DONE',json.dumps(metadata))

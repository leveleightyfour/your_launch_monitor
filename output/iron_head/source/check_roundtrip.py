import bpy,bmesh,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'srixon_zxi7_7_head.blend'))
source=bpy.data.collections['ZXi7 • 7-iron head'];body=next(o for o in source.objects if o.name.startswith('Head and hosel'))
expected=sum(o.type=='MESH' for o in source.objects)
bm=bmesh.new();bm.from_mesh(body.data)
nonmanifold=sum(len(e.link_faces)!=2 for e in bm.edges)
assert nonmanifold==0, f'{nonmanifold} nonmanifold body edges'
remaining=set(bm.verts);components=0
while remaining:
    components+=1;todo=[remaining.pop()]
    while todo:
        v=todo.pop()
        for e in v.link_edges:
            other=e.other_vert(v)
            if other in remaining:remaining.remove(other);todo.append(other)
assert components==1,components
bm.free()
packed=sum(bool(i.packed_file) for i in bpy.data.images)
assert packed>=7
scene=bpy.context.scene
scene.collection.children.unlink(source)
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.import_scene.gltf(filepath=str(ROOT.parents[1]/'assets/models/srixon_zxi7_7_head.glb'))
meshes=[o for o in bpy.context.selected_objects if o.type=='MESH'];assert len(meshes)==expected
assert not any('shaft' in o.name.lower() or 'grip' in o.name.lower() for o in meshes)
for name,camera in [('glb_verified','01 • Back and cavity'),('glb_hosel_verified','05 • Continuous heel and hosel')]:
    scene.camera=bpy.data.objects[camera];scene.render.filepath=str(ROOT/(name+'.png'));bpy.ops.render.render(write_still=True)
scene.camera=bpy.data.objects['01 • Back and cavity'];scene.camera.data.ortho_scale=.112;scene.camera.location+=Vector((-.021,.014,-.012));scene.render.filepath=str(ROOT/'back_detail.png');bpy.ops.render.render(write_still=True)
points=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
dims=[max(p[i] for p in points)-min(p[i] for p in points) for i in range(3)]
info=json.loads((ROOT/'model_info.json').read_text());info['dimensions_including_hosel_m']=dims;info['rear_contours']='Independent photo traces of both recess boundaries, three central facet regions and sole rail crest';(ROOT/'model_info.json').write_text(json.dumps(info,indent=2))
report={'native_blend_reopens':True,'native_packed_textures':packed,'head_hosel_one_closed_connected_mesh':True,'nonmanifold_body_edges':nonmanifold,'glb_reimports':True,'imported_meshes':len(meshes),'scope':'head, integrated hosel, ferrule; no shaft or grip','roundtrip_preview':'glb_verified.png'}
(ROOT/'roundtrip_validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))

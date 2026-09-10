import bpy,math,json
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'srixon_zxi7_7_head.blend'))
model=bpy.data.collections['ZXi7 • 7-iron head'];body=next(o for o in model.objects if o.name.startswith('Head and hosel'))
Rinv=Matrix.Rotation(math.radians(32),3,'X');n=Vector((0,-math.cos(math.radians(32)),math.sin(math.radians(32))))
local=[Rinv@v.co for v in body.data.vertices];corners=[v.vector[:] for v in body.data.corner_normals];count=0
for p in body.data.polygons:
    if all(abs(local[v].y)<2e-6 for v in p.vertices):
        count+=1
        for li in p.loop_indices:corners[li]=tuple(n)
body.data.normals_split_custom_set(corners)
bpy.data.materials['Ferrule • polished black'].node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.5
bpy.ops.object.select_all(action='DESELECT')
for ob in model.objects:ob.select_set(True)
bpy.context.view_layer.objects.active=body
out=ROOT.parents[1]/'assets/models/srixon_zxi7_7_head.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_cameras=False,export_lights=False,export_apply=True,export_yup=True,export_extras=True)
bpy.ops.object.select_all(action='DESELECT');body.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'srixon_zxi7_7_head.blend'))
info=json.loads((ROOT/'model_info.json').read_text());info['glb_bytes']=out.stat().st_size;(ROOT/'model_info.json').write_text(json.dumps(info,indent=2))
for name,cam in [('face','02 • Face outline'),('back','01 • Back and cavity'),('hosel','05 • Continuous heel and hosel'),('side','04 • Toe and sole profile'),('hero','03 • Face and hosel'),('sole','06 • Sole and cavity')]:
    bpy.context.scene.camera=bpy.data.objects[cam];bpy.context.scene.render.filepath=str(ROOT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('Pinned planar-face normals on',count,'triangles')

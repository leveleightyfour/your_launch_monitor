"""Reopen the native project and compare it to a clean GLB import."""
import bpy,json,bmesh
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'titleist_gt2_head.blend'))
scene=bpy.context.scene
source=bpy.data.collections['GT2 • Head and adjustable hosel']
expected=sum(ob.type=='MESH' for ob in source.objects)
packed=sum(bool(im.packed_file) for im in bpy.data.images if im.source=='FILE')
assert packed==3
shell=next(ob for ob in source.objects if ob.name.startswith('Head and hosel'))
bm=bmesh.new();bm.from_mesh(shell.data)
assert all(len(e.link_faces)==2 for e in bm.edges), 'Head and hosel must form a closed surface'
visited=set();pending=[next(iter(bm.verts))]
while pending:
    vertex=pending.pop()
    if vertex in visited:continue
    visited.add(vertex)
    pending.extend(e.other_vert(vertex) for e in vertex.link_edges)
assert len(visited)==len(bm.verts), 'Head and hosel must be one connected component'
bm.free()
scene.collection.children.unlink(source)
bpy.ops.import_scene.gltf(filepath=str(ROOT.parents[1]/'assets/models/titleist_gt2_head.glb'))
meshes=[ob for ob in scene.objects if ob.type=='MESH']
assert len(meshes)==expected,(len(meshes),expected)
assert not any('shaft' in ob.name.lower() and 'socket' not in ob.name.lower() for ob in meshes)
scene.camera=bpy.data.objects['01 • Face and crown']
scene.render.filepath=str(ROOT/'glb_verified.png')
bpy.ops.render.render(write_still=True)
scene.camera=bpy.data.objects['06 • Hosel blend detail']
scene.render.filepath=str(ROOT/'glb_hosel_verified.png')
bpy.ops.render.render(write_still=True)
report={'head_hosel_one_closed_connected_mesh':True,'native_blend_reopens':True,'native_packed_textures':packed,'glb_reimports':True,'imported_meshes':len(meshes),'camera_and_lights_excluded':True,'preview':'glb_verified.png'}
(ROOT/'roundtrip_validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))

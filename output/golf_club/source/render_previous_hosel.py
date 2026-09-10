import bpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'revisions/v2/titleist_gt2_head.blend'))
scene=bpy.context.scene
camera=scene.camera
camera.location=(-.035,-.15,.080)
camera.rotation_euler=(Vector((.043,-.026,.026))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.ortho_scale=.072
scene.render.filepath=str(ROOT/'revisions/v2/hosel.png')
bpy.ops.render.render(write_still=True)

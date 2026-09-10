# Club head view

The Club tab draws the selected club's head in three dimensions and hangs the
shot's delivery numbers on the geometry. Three views — Side, Top, Impact —
each show the figures that are legible from that angle, and a change of view
fades the figures out, swings the head, and fades the new figures in.

**Code map**

| Layer | File | Responsibility |
|---|---|---|
| Shared | `lib/shared/three/glb_model.dart` | Minimal glTF binary reader: triangle meshes, normals, UVs, materials, embedded images. Pure Dart, runs in an isolate |
| Application | `lib/features/launch_monitor/application/club_head_model_provider.dart` | Loads the asset, decodes textures, measures the face; `clubHeadModelProvider` |
| Presentation | `lib/features/launch_monitor/presentation/widgets/tabs/club_head_view.dart` | Camera presets, pose from the shot, mesh painter, annotations, the view transition |
| Presentation | `lib/features/launch_monitor/presentation/widgets/tabs/club_tab.dart` | Header chips and toggles; falls back to the flat panels if the model fails to load |
| Prefs | `UnitPrefs.clubView` | The last view, so the tab reopens where it was left |
| Assets | `assets/models/*.glb` | Head models. Only `titleist_gt2_head.glb` is wired up; every club shows it until its own model lands |

## Rendering

No 3D library: the mesh is transformed, lit and projected in Dart and drawn
with `Canvas.drawVertices`, one call per part, textures through an
`ImageShader` on the paint. Back faces are culled by screen winding and each
part's triangles are bucket-sorted far to near; parts are drawn far to near
by mean depth with blended decals last. The last frame is cached so a still
view repaints without touching a vertex; only the transition rebuilds frames.

The palette is the app's: near-black lacquer and raw metal alike are lifted
to a matte mid grey so the shape carries and the accent stays the only
colour, and textures keep their own tone. Lines and arcs use the accent for
the shot's own measurements and the target-line grey for references.

## Frame of reference

+Z out of the face toward the target, +Y up, +X toward the toe, −X toward
the heel and hosel. A right-handed golfer stands on the −X side with the
target to their left, so "right of target" is +X: an open face turns its
normal toward +X, an in-to-out path travels toward +X.

The GT2 export is the mirror image of that (hosel at +X, face at +Z — a
left-handed head; its decals read backwards to prove it), so
`ClubHeadModel.load` reflects the mesh on X, reversing every triangle's
winding. Anything that builds a model without going through `load`,
including the render rig, must apply `mirroredX()` itself.

Camera presets, yaw about +Y: Impact 0° (in front of the face), Side −90°
(at the heel, looking along the face), Top −180° from 76° above. Yaw is one
continuous scale so every move swings the same way round.

## Measuring the face

The face is the part whose material is named for it. Its average normal
gives the plane and the loft built into the geometry (10.4° on the GT2);
+Y flattened onto the plane and the cross product with the normal give the
face's up and across axes. The face centre is the midpoint of the outline's
extents on those axes — not the vertex centroid, which would drift toward
the densest mesh, the scoring — pushed out to the bulge's outermost depth.
An impact position in millimetres from the device is then a real position
on that plane. If a device's zero ever proves not to be the geometric
centre, the correction is one offset here, not a per-image guess.

## Figures per view

- **Side**: dynamic loft, as the face plane against vertical, and angle of
  attack, as the path through the ball against the ground line. The head is
  tilted about the heel–toe axis until its face reads the shot's dynamic
  loft relative to the built-in loft.
- **Top**: face to target, as the face line's normal against the target
  line; club path, as an arrow through the ball; and face to path.
- **Impact**: club speed in the golfer's units, the strike position and the
  session's strikes on the face, with the heatmap toggle, and the horizontal
  and vertical offsets.

Lie angle is not shown: the device does not report it.

## Adding a model

Export a head as a `.glb` with triangle meshes, embedded PNG textures and a
material whose name contains "face". Check its hand — hosel at −X once
loaded, face at +Z, sole at −Y — and add a mapping from club to asset in the
provider. The model is an asset, so it reaches devices only in a store
release; the rendering code itself can follow as a patch.

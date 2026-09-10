# Titleist GT2 — head only

A photo-informed 3D reconstruction of the driver head in the four supplied product photographs. Includes the head, curved face, sole graphics, Titleist script, GT alignment mark, heel screw, adjustment collars and open hosel. No shaft or grip.

## Files

- `titleist_gt2_head.blend` — editable Blender project with packed textures and six inspection cameras.
- `../../assets/models/titleist_gt2_head.glb` — self-contained glTF 2.0 binary for a Flutter-compatible 3D renderer. Materials and all three PNG textures are embedded.
- `preview.png` — rendered face/crown and sole overview.
- `front_comparison.png` — the reference photo and revised front render at a common scale.
- `hosel.png` — close-up of the continuous head-to-hosel blend.
- `hosel_comparison.png` — previous and smoothed junctions from the same camera.
- `source/front_profile.json` — independently traced head and face-insert outlines.
- `hero.png`, `sole.png`, `crown.png`, `face.png`, `side.png` — full-resolution transparent renders.
- `model_info.json`, `validation.json`, `roundtrip_validation.json` — model statistics and verification results.
- `source/`, `textures/`, `references/` — reproducible model generation and source material.

## Open in Blender

Open `titleist_gt2_head.blend` normally. It opens framed on the head in Material Preview. Orbit with the middle mouse button; scroll to zoom. The `GT2 • Head and adjustable hosel` collection contains the editable meshes. The separate Studio collection contains the cameras and lighting. Camera `06 • Hosel blend detail` focuses on the new transition.

Choose one of the six cameras for the face, crown, sole or side. Render the active camera with F12. The GLB excludes studio cameras and lights. Textures are packed, so the native project also opens on another machine without locating external images.

## Flutter

The GLB is saved at `assets/models/titleist_gt2_head.glb`, and `assets/models/` has been registered in this project's `pubspec.yaml`. No viewer dependency or app screen has been added.

For Android, iOS or web, one option is [model_viewer_plus](https://pub.dev/packages/model_viewer_plus). After adding the package and following its platform setup instructions:

```dart
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class ClubHeadPreview extends StatelessWidget {
  const ClubHeadPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 360,
      child: ModelViewer(
        src: 'assets/models/titleist_gt2_head.glb',
        alt: 'Titleist GT2 driver head',
        backgroundColor: Color(0xFFF1F2F3),
        cameraControls: true,
        autoRotate: true,
        ar: false,
      ),
    );
  }
}
```

The linked package declares Android, iOS and web support. A native Windows or macOS app needs a renderer that supports those targets. The GLB itself is independent of any Flutter package. The example has not been run in the app.

Use an environment map or studio lighting to show the reflective black surfaces. No Blender-only procedural material nodes, Draco decoding, or glTF material extensions are required. The face scoring is in a texture sampled from the front photograph to keep the geometry light.

## Scale and orientation

Units are metres. The model including the hosel is approximately 130 × 116 × 72 mm. These dimensions are estimates from the photographs. The origin is near the head centre.

- Blender: +X toward the heel, −X toward the toe, +Y toward the rear, +Z up.
- GLB: +X toward the heel, −X toward the toe, +Y up, +Z toward the face/ball direction.

## Reconstruction limits

This is a visual approximation, not a scan or manufacturer CAD model. Four uncalibrated photographs do not establish exact dimensions or hidden construction. The asymmetric front outline and metal face boundary are traced independently from view 05. The head and lower hosel share one closed mesh, with a locally sculpted transition; the adjustment collars remain separate parts. The depth, loft, hosel and screw geometry remain inferred. The sole texture comes from the supplied photograph and retains some photographed lighting; the face texture also comes from the supplied front photograph, and the small GT mark is reconstructed. Sole decorative panels are primarily textured, while the main shell, face curvature, hosel and screw are geometry.

## Rebuild

First decode the four supplied JPEG XL photographs into `references/view_02.png` through `view_05.png`. The decoded references are already included. Run `source/prepare_textures.py` using Python with Pillow and NumPy. Run `source/build_head.py` with Blender in background mode. Run `source/verify_glb.py` with Python/NumPy and `source/check_roundtrip.py` with Blender to repeat validation.

GLB materials follow Blender's [glTF material export conventions](https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html).

# Srixon ZXi7 7-iron head

Photo-informed reconstruction of the **7-iron shown in the five supplied images**. Includes the head, integrated metal hosel, open shaft socket and short black ferrule. No shaft or grip. This is one photographed head, not a dimensionally different set of irons.

## Files

- `srixon_zxi7_7_head.blend` — native Blender scene, packed textures and six inspection cameras.
- `../../assets/models/srixon_zxi7_7_head.glb` — portable glTF 2.0 binary for a compatible Flutter renderer.
- `preview.png` — rendered inspection views.
- `model_info.json`, `validation.json`, `roundtrip_validation.json` — asset details and checks.
- `references/` — converted supplied photographs.
- `source/` — reproducible geometry, material and export scripts.

## Shape and finish

The blade outline follows the front photograph's tall rounded toe, sloping top edge and flatter sole. The back has independently traced outer and inner recess boundaries, a raised sole rail, a recessed perimeter channel and three regions of angled central facets. These features and the curved heel-to-hosel transition are geometry. The body and metal hosel form a single mesh. The shaft socket is open and ends inside the hosel.

The face has 13 stepped scorelines, represented by a tangent normal map and colour texture. They give a recessed appearance without adding tiny mobile geometry. The supplied Srixon wordmark is isolated from the photograph; the other small markings are recreated. Metal highlights respond to the viewing environment rather than being baked from the product photo.

Scale, hidden surfaces and the **32° loft estimate** are inferred from uncalibrated photographs. This is a visual approximation, not a scan, manufacturer's CAD file, or a source for manufacturing or club fitting. The complete iron set has not been inferred from this one 7-iron.

## Open in Blender

Open the `.blend` directly. Textures are packed. The head is selected and the initial view shows the back. Middle mouse orbits; Numpad `.` frames the selection. Cameras 01–06 inspect the back, face, heel, side and sole. The separate Studio collection supplies preview lighting and is excluded from the GLB.

Blender coordinates use metres: +X toward the heel, +Y toward the rear, +Z up. The GLB uses Y up. The face has the estimated loft built into its geometry.

## Flutter

The project already registers `assets/models/` in `pubspec.yaml`. Use:

```text
assets/models/srixon_zxi7_7_head.glb
```

For an application using `model_viewer_plus`, an example widget is:

```dart
ModelViewer(
  src: 'assets/models/srixon_zxi7_7_head.glb',
  alt: 'Srixon ZXi7 7-iron head',
  cameraControls: true,
  autoRotate: false,
  ar: false,
)
```

This requires the package and its import in the host app. No new viewer package or app screen was added for this asset. `model_viewer_plus` targets Android, iOS and web; a native desktop app needs a compatible glTF renderer. The model has been checked as a GLB asset, not run inside a Flutter viewer here.

Reference: [model_viewer_plus](https://pub.dev/packages/model_viewer_plus).

## Rebuild

Run `source/prepare_textures.py` and then `source/create_geometry.py` with a Python environment containing NumPy and Pillow. Run `source/build_iron.py` with Blender 5.2. The geometry generator writes temporary surface samples used by Blender; these are not required to open either delivered model. `source/verify_glb.py` checks the binary asset, while `source/check_roundtrip.py` checks the native topology and renders a reimported GLB.

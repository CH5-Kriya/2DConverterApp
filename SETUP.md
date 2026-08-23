# Setup on a fresh machine

Everything the app needs is in git **except the depth model**, which is ~645 MB
and CC-BY-NC-4.0, so it is deliberately excluded (see `.gitignore`). A clone
builds and runs without it — it just silently produces worse relief, because the
pipeline falls back to a heuristic backend. Steps 3 and 6 are the ones that
matter.

---

## 1. Requirements

| | |
|---|---|
| Mac | Apple Silicon. `opencv2.xcframework` ships `ios-arm64`, `ios-arm64-simulator` and `macos-arm64` slices only — there is no x86_64 slice, so an Intel Mac cannot even run the simulator build. |
| macOS | 15 (Sequoia) or newer. |
| Xcode | 26.5 or newer — the app target sets `IPHONEOS_DEPLOYMENT_TARGET = 26.5`. |
| Device | iPad, iPadOS 26.5+. `TARGETED_DEVICE_FAMILY = 2`, so iPad only. The simulator works but has no Neural Engine, which makes depth inference far slower. |
| Apple ID | Any free or paid account works — you will re-sign with your own team in step 4. |
| Disk | ~2 GB: ~100 MB clone (OpenCV is committed), 645 MB model, the rest DerivedData. |

No package manager setup, no CocoaPods, no Homebrew. Every dependency is either
local (`ReliefKit`) or vendored (`opencv2.xcframework`, `Simplify.h`), so Xcode
resolves offline.

## 2. Clone

```sh
git clone https://github.com/CH5-Kriya/2DConverterApp.git
cd 2DConverterApp
```

`main` has the full pipeline. If you need the interactive 3D preview and the
Tactura rename, use `ell`, which is three commits ahead:

```sh
git checkout ell
```

Sanity check — if `ReliefKit/Package.swift` is missing you are on an old commit,
not a broken clone:

```sh
ls ReliefKit/Package.swift ReliefKit/Frameworks/opencv2.xcframework
```

## 3. Add the depth model

Two artifacts go into `Tactura/Resources/`. **Both are required.** The
loader needs the model *and* the position-embedding grid, and gives up if either
is absent.

```
Tactura/Resources/
├── base_1x1370x1024.f32                        5.4 MB
└── dav2_large_multifunction_f16.mlpackage/    640 MB
    ├── Manifest.json
    └── Data/com.apple.CoreML/
        ├── model.mlmodel
        └── weights/weight.bin
```

Get them one of two ways.

**Copy from a machine that has them.** `.mlpackage` is a directory, so copy
recursively and keep the extension intact:

```sh
rsync -a --progress \
  "<source>/Tactura/Resources/dav2_large_multifunction_f16.mlpackage" \
  "<source>/Tactura/Resources/base_1x1370x1024.f32" \
  Tactura/Resources/
```

**Or regenerate from the Python repo:**

```sh
conda run -n coreml python scripts/convert_coreml.py --shapes multifunction
```

then copy the resulting `.mlpackage` and `out/coreml/pos_embed/base_1x1370x1024.f32`
into `Tactura/Resources/`.

Verify the transfer — a truncated `weight.bin` fails at *prediction* time, not at
load time, which is a confusing way to find out:

```sh
shasum -a 256 Tactura/Resources/base_1x1370x1024.f32 \
  Tactura/Resources/dav2_large_multifunction_f16.mlpackage/Data/com.apple.CoreML/{model.mlmodel,weights/weight.bin}
```

```
eb2510cc11485f9f6f8cef79721dc601556e0d77a8d3864431fe165e03ee708f  base_1x1370x1024.f32
a4c8805e97c97f7ecd88557d3092d684a64a99d98f2fa164abe56cb6f57987f6  model.mlmodel
57f3e6bb93e146350c05d6bc44cd81343869456b9b46323454d56804273ac3eb  weight.bin
```

**Filenames must match exactly.** `CoreMLDepthBackend.bundled()` looks up
`dav2_large_multifunction_f16` and `base_1x1370x1024` by name; a renamed file is
an absent file.

**Do not add anything in Xcode.** The project uses a synchronized root group, so
the folder contents are picked up from disk automatically. Dragging the model
into the navigator creates a duplicate reference instead. Xcode compiles the
`.mlpackage` into `.mlmodelc` during the build.

## 4. Set your signing team

`project.pbxproj` hardcodes the original developer team, so signing fails on any
other account. In Xcode: **target Tactura → Signing & Capabilities**

- **Team** — your own.
- **Bundle Identifier** — change it if `com.elliezer.kriya.-DConverterApp` is
  already taken on your account.

Leave *Automatically manage signing* on. Avoid committing this change unless the
whole team is moving to one account — it churns the project file on every clone.

## 5. Build and run

```sh
open Tactura.xcodeproj
```

Wait for **Package Resolution** to finish (`ReliefKit` is a local package; it is
quick and needs no network), pick an iPad destination, then ⌘R.

First build is slow — the C++ numerical core and the 640 MB model both compile.
No shared scheme is committed, so Xcode generates one automatically the first
time; that is expected.

## 6. Confirm the real model is loaded

This is the step people skip, and the failure is silent by design —
`ReliefService` falls back to `ClassicalLayersBackend` when the model is missing,
so a misplaced file degrades quality instead of throwing:

```swift
let backend: DepthBackend = CoreMLDepthBackend.bundled()
    ?? ClassicalLayersBackend(layerCount: config.depth.classicalLayers)
```

Run a conversion and check the analysis notes. With the model in place they read:

```
Depth Anything V2 Large, 742x518
```

Anything else means `bundled()` returned `nil`. Check both filenames and that
`.mlpackage` is a folder, not a zip.

For more detail, set the `RELIEF_DEBUG_DEPTH` environment variable in the scheme
— it prints the model input size, the selected multifunction function name, and
the output shape and strides on every prediction.

## 7. Optional: the headless CLI

`ReliefKit` also builds on macOS for `relief-verify`, which checks the port
against the Python reference's golden fixtures:

```sh
cd ReliefKit
swift build -c release
swift test
```

`swift test` runs without any fixtures beyond the ones committed under
`Tests/ReliefCoreTests/Fixtures/`.

**`SlicProbe` will not work as-is on your machine.** `depth_check.swift`,
`fullrun.swift`, `fixture_mesh.swift` and `roughness_check.swift` all contain
absolute paths from the original machine, e.g.

```swift
let res = URL(fileURLWithPath: "/Users/elliezer/Documents/Projects/Challenge 5/ios-app/2DConverterApp/Tactura/Resources")
```

Edit them to your own paths, and note they also expect the Python repo's
`test_python/tests/golden_1536` fixtures alongside. The app itself is unaffected
— it resolves everything through `Bundle.main`.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `local binary target 'opencv2' does not contain a binary artifact` | The clone is incomplete or the xcframework was excluded. It **is** committed — re-clone rather than rebuilding OpenCV. |
| Relief output looks flat or stepped, no error shown | The classical fallback is running. See step 6. |
| `Depth model not found at …` | Only reachable via the direct `CoreMLDepthBackend(modelURL:)` path, e.g. the SlicProbe tools. The app never raises it. |
| `not a valid .mlmodelc file` | A hand-placed `.mlpackage` that Core ML has not compiled. The backend compiles it once at runtime and caches; if this persists the package directory is malformed. |
| ``'MLModelConfiguration'`s `.functionName` property must be `nil` unless the model type is ML Program`` | Simulator only, and the message is misleading — the model *is* an ML Program. See "Core ML on the simulator" below. |
| `This crop is too long and narrow to convert` | The crop is wider than 2:1 (or taller than 1:2). The package carries a function for every multiple of 14 from 518 to 1036 with the short side at 518, which covers every aspect from square to 2:1; past that it raises rather than squashing the image to fit. |
| Signing errors on build | Step 4. |
| Simulator build fails to link | Intel Mac. There is no x86_64 slice. |
| Depth is unusably slow | Running on the simulator, which has no Neural Engine. Use a physical iPad. |

## Core ML on the simulator

The simulator's Metal backend fails validation on this model — the console shows
`Espresso exception: "Invalid state": MpsGraph backend validation on incompatible
OS`. Core ML then falls back to a loader that does not understand the
multifunction description, and surfaces it as:

```
`MLModelConfiguration`'s `.functionName` property must be `nil`
unless the model type is ML Program.
```

The message is a red herring. The model *is* an ML Program; the GPU path just
never got far enough to see that. Measured on an iPad Pro 11-inch (M5), iOS 26.5:

| `computeUnits` | Simulator |
|---|---|
| `.all` | fails — the error above |
| `.cpuAndGPU` | fails — same |
| `.cpuOnly` | loads and predicts |
| `.cpuAndNeuralEngine` | loads and predicts |

Any mode that includes the GPU breaks. `CoreMLDepth.swift` therefore selects
`.cpuOnly` under `#if targetEnvironment(simulator)` and keeps `.all` on device.

Expect it to be **slow** — a 305M-parameter transformer on the simulator's CPU,
with no Neural Engine. The simulator is for checking that the pipeline runs; use
a physical iPad to judge speed or output quality.

## What is and isn't in git

**Committed:** app sources, `ReliefKit` (Swift + C++ core), and
`opencv2.xcframework` (~93 MB). OpenCV is committed on purpose — without it the
package cannot resolve and a clone would not build at all. Every file is under
GitHub's 100 MB limit. Rebuild recipe: `ReliefKit/Frameworks/BUILD_OPENCV.md`.

**Not committed:** `Tactura/Resources/*.mlpackage/` and
`Tactura/Resources/*.f32`. The weights alone are 635 MB, well past
GitHub's limit, and the model is CC-BY-NC-4.0 — fine for research and TestFlight,
not something to redistribute through this repository.

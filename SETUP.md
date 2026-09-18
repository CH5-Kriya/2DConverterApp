# Setup on a fresh machine

Everything the app needs **is in git**, including its depth model: Depth
Anything V2 *Small*, as Apple publishes it, is 50 MB and Apache-2.0, so it is
committed. Clone, set your team, run.

---

## 1. Requirements

| | |
|---|---|
| Mac | Apple Silicon. `opencv2.xcframework` ships `ios-arm64`, `ios-arm64-simulator` and `macos-arm64` slices only — there is no x86_64 slice, so an Intel Mac cannot even run the simulator build. |
| macOS | 15 (Sequoia) or newer. |
| Xcode | 26.5 or newer — the app target sets `IPHONEOS_DEPLOYMENT_TARGET = 26.5`. |
| Device | iPhone or iPad, 26.5+. `TARGETED_DEVICE_FAMILY = "1,2"`. The layout is designed for iPad landscape and is simply squeezed on a phone — that is known, not a regression. The simulator works but has no Neural Engine, which makes depth inference far slower. |
| Apple ID | Any free or paid account works — you will re-sign with your own team in step 3. |
| Disk | At least 1 GB free. OpenCV and the ~50 MB model are committed; Xcode also needs room for DerivedData. |

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

## 3. Set your signing team

`project.pbxproj` hardcodes the original developer team, so signing fails on any
other account. In Xcode: **target Tactura → Signing & Capabilities**

- **Team** — your own.
- **Bundle Identifier** — change it if `com.elliezer.kriya.-DConverterApp` is
  already taken on your account.

Leave *Automatically manage signing* on. Avoid committing this change unless the
whole team is moving to one account — it churns the project file on every clone.

## 4. Build and run

```sh
open Tactura.xcodeproj
```

Wait for **Package Resolution** to finish (`ReliefKit` is a local package; it is
quick and needs no network), pick an iPhone or iPad destination, then ⌘R.

First build is slow — the C++ numerical core and bundled Core ML model compile.
No shared scheme is committed, so Xcode generates one automatically the first
time; that is expected.

## 5. Confirm the real model is loaded

This is the step people skip, and the failure is silent by design —
`ReliefService` falls back to `ClassicalLayersBackend` when the model is missing,
so a misplaced file degrades quality instead of throwing:

```swift
let backend: DepthBackend = (AppleDepthBackend.bundled() as DepthBackend?)
    ?? ClassicalLayersBackend(layerCount: config.depth.classicalLayers)
```

Run a conversion and check the analysis notes. They should read:

```
Depth Anything V2 Small, 392x518 (stretched)
```

`heuristic ordering, not a learned model` means `AppleDepthBackend.bundled()`
returned `nil` and the classical fallback is running. Check that
`Tactura/Resources/DepthAnythingV2SmallF16.mlpackage` exists and is a folder,
not a zip.

The small model's input is fixed at 518x392, so every crop is stretched to 4:3
rather than resized on its short side the way the ladder does — that is the
fidelity the small model trades for its size, and `(stretched)` in the note is
there to say so.

For more detail, set the `RELIEF_DEBUG_DEPTH` environment variable in the scheme
— it prints the model input size, output size and pixel format on every
prediction.

## 6. Optional: the headless CLI

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
| Relief output looks flat or stepped, no error shown | The classical fallback is running. See step 5. |
| `not a valid .mlmodelc file` | A hand-placed `.mlpackage` that Core ML has not compiled. The backend compiles it once at runtime and caches; if this persists the package directory is malformed. |
| Signing errors on build | Step 3. |
| Simulator build fails to link | Intel Mac. There is no x86_64 slice. |
| Depth is unusably slow | Running on the simulator, which has no Neural Engine. Use a physical iPad. |

## Core ML on the simulator

The simulator's Metal backend fails validation on this model. Measured on an
iPad Pro 11-inch (M5), iOS 26.5:

| `computeUnits` | Simulator |
|---|---|
| `.all` | fails — the error above |
| `.cpuAndGPU` | fails — same |
| `.cpuOnly` | loads and predicts |
| `.cpuAndNeuralEngine` | loads and predicts |

Any mode that includes the GPU breaks. `AppleDepthBackend.swift` therefore selects
`.cpuOnly` under `#if targetEnvironment(simulator)` and keeps `.all` on device.

Expect it to be **slow** on the simulator's CPU, with no Neural Engine. The
simulator is for checking that the pipeline runs; use a physical device to judge
speed or output quality.

## What is in git

**Committed:** app sources, `ReliefKit` (Swift + C++ core), and
`opencv2.xcframework` (~93 MB). OpenCV is committed on purpose — without it the
package cannot resolve and a clone would not build at all. Every file is under
GitHub's 100 MB limit. Rebuild recipe: `ReliefKit/Frameworks/BUILD_OPENCV.md`.

**Also committed:** `Tactura/Resources/DepthAnythingV2SmallF16.mlpackage`
(~50 MB, largest file 47 MB). It is the app's active depth model. Its Apache-2.0
license and file size allow a fresh clone to run real depth inference with no
download or conversion step.

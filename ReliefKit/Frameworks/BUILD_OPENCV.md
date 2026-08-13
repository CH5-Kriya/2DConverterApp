# Rebuilding `opencv2.xcframework`

The vendored binary is **part of the specification**, not a convenience. The
Python reference reaches `cv::CLAHE`, `cv::ximgproc::guidedFilter` and
`cv::distanceTransform(DIST_L2, 5)` through thin `cv2` bindings, so calling the
same C++ from Swift is the reference implementation running on the same data
rather than an approximation of it. Pinning the binary pins that.

Current build: opencv + opencv_contrib `4.x`, arm64, Swift wrappers disabled.
153 MB across three slices (`ios-arm64`, `ios-arm64-simulator`, `macos-arm64`);
the app itself ships only the 49 MB iOS slice.

## Prerequisites

```sh
brew install cmake ninja
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

`DEVELOPER_DIR` matters: on this machine `xcode-select -p` points at
`/Library/Developer/CommandLineTools`, so `xcodebuild` does not exist without
it. Exporting the variable avoids needing `sudo xcode-select -s`.

## 1. Sources

```sh
git clone --depth 1 --branch 4.x https://github.com/opencv/opencv.git
git clone --depth 1 --branch 4.x https://github.com/opencv/opencv_contrib.git
```

## 2. iOS and iOS-simulator

```sh
python3 opencv/platforms/apple/build_xcframework.py \
  --out ./opencv_xcf \
  --contrib ./opencv_contrib \
  --iphoneos_archs arm64 \
  --iphonesimulator_archs arm64 \
  --macos_archs arm64 \
  --build_only_specified_archs \
  --disable-swift \
  --iphoneos_deployment_target 17.0 \
  --without gapi --without dnn --without java --without python --without ts \
  --without videoio --without highgui --without stitching --without objdetect
```

`--disable-swift` is not optional. Generating the Swift wrappers for contrib is
the step known to break on Apple Silicon (`XimgprocExt.swift`), and this port
never uses them — it calls the C++ API through a shim.

**The macOS leg of this command fails**, and the iOS legs succeed. See below.

## 3. macOS, separately

The `apple/build_xcframework.py` driver hands the macOS build the same flags it
gives iOS, and CMake then cannot find a compiler:

```
-- The CXX compiler identification is unknown
CMake Error at CMakeLists.txt:134 (project):
  No CMAKE_CXX_COMPILER could be found.
```

The iOS legs work because their toolchain files name the compiler outright; the
native macOS configure step probes for it, and probing follows `xcode-select`
rather than `DEVELOPER_DIR`. Naming the compiler explicitly fixes it without
needing `sudo`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
export CXX="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

python3 opencv/platforms/osx/build_framework.py ./opencv_xcf/macos \
  --macos_archs arm64 --framework_name opencv2 --build_only_specified_archs \
  --contrib ./opencv_contrib --disable-swift \
  --without gapi --without dnn --without java --without python --without ts \
  --without videoio --without highgui --without stitching --without objdetect
```

Note the absence of `--iphoneos_deployment_target` here.

## 4. Assemble

```sh
cd opencv_xcf
xcodebuild -create-xcframework \
  -framework iphoneos/opencv2.framework \
  -framework iphonesimulator/opencv2.framework \
  -framework macos/opencv2.framework \
  -output opencv2.xcframework
```

## 5. Verify

`OpenCVLinkTests` calls `relief_opencv_selftest()`, which exercises all three
functions the pipeline depends on. Run it before trusting a rebuild:

```sh
swift test --filter OpenCVLinkTests
```

## Linking notes

`ReliefNumerics` needs, in `Package.swift`:

- **Accelerate** — OpenCV's LAPACK/BLAS paths (`lapack_Cholesky32f` in
  `hal_internal`) resolve there on Apple platforms.
- **libc++**.
- **OpenCL, macOS only** — the macOS build enables it, the iOS build has no such
  backend.

## Known divergence to close

The macOS slice has OpenCL enabled and the iOS slice does not. It is only
reachable through `UMat`/T-API and this port uses `cv::Mat` throughout, so no
kernel is ever dispatched — but "no kernel is dispatched" is an argument, and
this project's standard is measurement. Rebuild macOS with `--disable opencl`
so verification and shipping take provably identical code paths.

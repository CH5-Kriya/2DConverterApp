// swift-tools-version: 6.0
import PackageDescription

// The numerical core of the relief pipeline, kept out of the app target so the
// same code can be driven headlessly by `relief-verify` on macOS. That CLI is
// how the port is held against the Python reference's golden fixtures, so macOS
// support is a requirement, not a convenience.
let package = Package(
    name: "ReliefKit",
    platforms: [
        // iOS 18 / macOS 15 is the floor for Core ML **multifunction** models,
        // which is how the depth model ships: one function per aspect bucket,
        // all sharing a single copy of the weights. The app targets iPadOS 26.5
        // regardless; macOS matters only for the `relief-verify` harness.
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ReliefCore", targets: ["ReliefCore"]),
        .executable(name: "relief-verify", targets: ["ReliefVerify"]),
    ],
    targets: [
        // C++ numerical core. Stages that OpenCV covers call it directly, so
        // they run the same code the Python reaches through `cv2`; the rest are
        // hand-ported where no shippable C++ equivalent exists (scikit-image's
        // colour conversion, SLIC, and the bespoke SFS solver).
        // Vendored so the exact OpenCV build is pinned rather than resolved
        // per-developer: `cv::CLAHE` tile interpolation and
        // `cv::ximgproc::guidedFilter` are the reference implementation here,
        // not an approximation of it, so the binary is part of the spec.
        // Built from opencv/opencv_contrib 4.x, arm64, --disable-swift.
        .binaryTarget(name: "opencv2",
                      path: "Frameworks/opencv2.xcframework"),

        .target(
            name: "ReliefNumerics",
            dependencies: ["opencv2"],
            publicHeadersPath: "include",
            cxxSettings: [
                // Fidelity over speed: the reference is float32 IEEE arithmetic
                // evaluated in a fixed order. -ffast-math would let the compiler
                // reassociate and contract, which on a 300-sweep solver is drift
                // rather than rounding.
                .unsafeFlags(["-fno-fast-math", "-ffp-contract=off"]),
            ],
            linkerSettings: [
                // OpenCV's LAPACK/BLAS paths (Cholesky in hal_internal) resolve
                // against Accelerate on Apple platforms.
                .linkedFramework("Accelerate"),
                .linkedLibrary("c++"),
                // The macOS OpenCV build enables OpenCL; the iOS one has no
                // such backend. Both are only reachable through UMat/T-API and
                // this port uses cv::Mat throughout, so no kernel is ever
                // dispatched -- but the macOS binary still references the
                // symbols and needs the framework at link time.
                // TODO: rebuild macOS with `--disable opencl` so verification
                // and shipping take provably identical code paths.
                .linkedFramework("OpenCL", .when(platforms: [.macOS])),
            ]
        ),

        // Config, types and the fixture reader. No platform dependencies, so it
        // builds anywhere and the tests run without a device.
        .target(name: "ReliefCore", dependencies: ["ReliefNumerics"],
                swiftSettings: [.swiftLanguageMode(.v5)]),

        // Differential harness against tests/golden/ in the Python repo.
        .executableTarget(name: "ReliefVerify", dependencies: ["ReliefCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "SlicProbe", dependencies: ["ReliefCore", "ReliefNumerics"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),

        .testTarget(name: "ReliefCoreTests",
                    dependencies: ["ReliefCore", "ReliefNumerics"],
                    resources: [.copy("Fixtures")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

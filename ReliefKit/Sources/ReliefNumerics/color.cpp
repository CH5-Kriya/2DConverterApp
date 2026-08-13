#include "relief_numerics.h"

#include <algorithm>
#include <cmath>

namespace {

// skimage.color.colorconv.xyz_from_rgb, cast to float32 exactly as
// `xyz_from_rgb.T.astype(arr.dtype)` does before the matmul.
constexpr float kXyzFromRgb[3][3] = {
    {0.412453f, 0.357580f, 0.180423f},
    {0.212671f, 0.715160f, 0.072169f},
    {0.019334f, 0.119193f, 0.950227f},
};

// D65, 2-degree observer -- skimage's default for rgb2lab.
constexpr float kWhiteX = 0.95047f;
constexpr float kWhiteY = 1.0f;
constexpr float kWhiteZ = 1.08883f;

// Legacy CIE constants, matching scikit-image. The exact values are
// 216/24389 = 0.008856451... and 841/108 = 7.787037...; scikit-image uses the
// truncated forms below and this port must too.
constexpr float kEpsilon = 0.008856f;
constexpr float kKappa = 7.787f;
constexpr float kOffset = 16.0f / 116.0f;

inline float srgb_to_linear(float c) {
    // np.power((c + 0.055) / 1.055, 2.4) above the knee, c / 12.92 below.
    return c > 0.04045f ? std::pow((c + 0.055f) / 1.055f, 2.4f) : c / 12.92f;
}

inline float lab_f(float t) {
    return t > kEpsilon ? std::cbrt(t) : kKappa * t + kOffset;
}

}  // namespace

void relief_rgb2lab(const float *rgb, float *lab_out, size_t rows,
                    size_t cols) {
    const size_t n = rows * cols;
    for (size_t i = 0; i < n; ++i) {
        const float r = srgb_to_linear(rgb[i * 3 + 0]);
        const float g = srgb_to_linear(rgb[i * 3 + 1]);
        const float b = srgb_to_linear(rgb[i * 3 + 2]);

        // arr @ xyz_from_rgb.T.
        //
        // numpy's float32 matmul is measurably *closer* to the float64-exact
        // answer than a naive float32 loop is (8.6e-8 vs 1.14e-7 max error
        // here), and differs from it on ~23% of elements -- the signature of
        // fused multiply-add, which rounds once per term instead of twice.
        // Reproducing that with `std::fma` is what makes this bit-exact rather
        // than merely close; a plain `a*x + b*y + c*z` is a few ulp off, and
        // those few ulp survive the Gaussian blur in SLIC and flip k-means ties.
        //
        // This is also why the target is built with `-ffp-contract=off`: the
        // contraction has to be *chosen* per expression, not left to the
        // compiler, or it varies by optimisation level.
        const float x = std::fma(kXyzFromRgb[0][0], r,
                        std::fma(kXyzFromRgb[0][1], g, kXyzFromRgb[0][2] * b));
        const float y = std::fma(kXyzFromRgb[1][0], r,
                        std::fma(kXyzFromRgb[1][1], g, kXyzFromRgb[1][2] * b));
        const float z = std::fma(kXyzFromRgb[2][0], r,
                        std::fma(kXyzFromRgb[2][1], g, kXyzFromRgb[2][2] * b));

        const float fx = lab_f(x / kWhiteX);
        const float fy = lab_f(y / kWhiteY);
        const float fz = lab_f(z / kWhiteZ);

        lab_out[i * 3 + 0] = 116.0f * fy - 16.0f;
        lab_out[i * 3 + 1] = 500.0f * (fx - fy);
        lab_out[i * 3 + 2] = 200.0f * (fy - fz);
    }
}

void relief_lightness_from_lab(const float *lab, float *out, size_t rows,
                               size_t cols) {
    const size_t n = rows * cols;
    for (size_t i = 0; i < n; ++i) {
        out[i] = std::min(std::max(lab[i * 3] / 100.0f, 0.0f), 1.0f);
    }
}

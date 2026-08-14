#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

void relief_clahe(const float *gray01, float *out, size_t rows, size_t cols,
                  double clip_limit, int tile_grid) {
    const int r = static_cast<int>(rows), c = static_cast<int>(cols);

    // `np.clip(gray01 * 65535.0, 0, 65535).astype(np.uint16)`.
    //
    // `astype` **truncates** toward zero; it does not round. Using a rounding
    // conversion here shifts roughly half the pixels by one 16-bit step before
    // CLAHE ever runs, which is small but systematic and shows up immediately
    // against the fixture.
    //
    // The multiply happens in **float32**, not double: `gray01` is a float32
    // array and 65535.0 is a Python float, which numpy treats as weakly typed,
    // so the product stays float32. Computing it in double instead lands on a
    // different integer whenever float32 rounding crosses a boundary -- a
    // one-step difference that CLAHE then amplifies, because at 16-bit the clip
    // limit floors to 1 and the 65536-bin CDF is a sparse step function.
    cv::Mat u16(r, c, CV_16UC1);
    for (int y = 0; y < r; ++y) {
        for (int x = 0; x < c; ++x) {
            const float v = gray01[y * c + x] * 65535.0f;
            const float clamped = std::min(std::max(v, 0.0f), 65535.0f);
            u16.at<uint16_t>(y, x) = static_cast<uint16_t>(clamped);
        }
    }

    // The reference runs this at 16-bit on purpose: at 8-bit the quantization
    // CLAHE introduces resurfaces as banding in the stage-4 de-bander.
    cv::Ptr<cv::CLAHE> clahe =
        cv::createCLAHE(clip_limit, cv::Size(tile_grid, tile_grid));
    cv::Mat equalized;
    clahe->apply(u16, equalized);

    for (int y = 0; y < r; ++y)
        for (int x = 0; x < c; ++x)
            out[y * c + x] =
                static_cast<float>(equalized.at<uint16_t>(y, x)) / 65535.0f;
}

void relief_albedo_normalize(const float *lightness, const int32_t *labels,
                             const float *albedo, size_t region_count,
                             float albedo_floor, float *out, size_t rows,
                             size_t cols) {
    const size_t n = rows * cols;

    // rho = np.maximum(seg.albedo, cfg.albedo_floor)
    std::vector<float> rho(region_count);
    for (size_t i = 0; i < region_count; ++i)
        rho[i] = std::max(albedo[i], albedo_floor);

    float peak = 0.0f;
    for (size_t i = 0; i < n; ++i) {
        const int32_t label = labels[i];
        const float r = (label >= 0 && static_cast<size_t>(label) < region_count)
                            ? rho[static_cast<size_t>(label)]
                            : albedo_floor;
        const float v = lightness[i] / r;
        out[i] = v;
        if (v > peak) peak = v;
    }

    // Eq. (1) normalizes albedo to 1, which can push bright pixels past 1.0.
    // Rescale rather than clip: clipping flattens highlights, and stage 5 reads
    // highlights as surfaces facing the light -- the MBC that breaks the
    // concave/convex ambiguity depends on them.
    //
    // numpy divides a float32 array by a Python float as float32 (the scalar is
    // weak-typed), so this stays in float rather than promoting to double.
    if (peak > 1.0f)
        for (size_t i = 0; i < n; ++i) out[i] /= peak;
}

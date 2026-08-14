#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

inline int reflect_idx(int i, int n) {  // scipy 'reflect': (d c b a | a b c d)
    while (i < 0 || i >= n) {
        if (i < 0) i = -1 - i;
        if (i >= n) i = 2 * n - 1 - i;
    }
    return i;
}

// Grayscale morphology over a footprint, matching skimage's default
// mode='reflect'. `cross` selects 4-connectivity; otherwise the full 3x3.
template <bool Dilate>
void morph(const int32_t *src, int32_t *dst, int H, int W, bool cross) {
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            int32_t best = Dilate ? std::numeric_limits<int32_t>::min()
                                  : std::numeric_limits<int32_t>::max();
            for (int dy = -1; dy <= 1; ++dy) {
                for (int dx = -1; dx <= 1; ++dx) {
                    if (cross && dy != 0 && dx != 0) continue;
                    const int32_t v = src[static_cast<size_t>(
                        reflect_idx(y + dy, H)) * W + reflect_idx(x + dx, W)];
                    best = Dilate ? std::max(best, v) : std::min(best, v);
                }
            }
            dst[static_cast<size_t>(y) * W + x] = best;
        }
    }
}

}  // namespace

void relief_find_boundaries_outer(const int32_t *labels, uint8_t *out, size_t rows,
                                  size_t cols) {
    // `skimage.segmentation.find_boundaries(labels, mode='outer')`, background=0.
    //
    // Note this treats label 0 as *background* even though the pipeline's
    // labels are a dense 0..n-1 with 0 a perfectly ordinary region. That is the
    // reference's behaviour and it is reproduced rather than corrected.
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    std::vector<int32_t> dil(N), ero(N);
    morph<true>(labels, dil.data(), H, W, /*cross=*/true);
    morph<false>(labels, ero.data(), H, W, /*cross=*/true);

    std::vector<int32_t> inverted(labels, labels + N);
    for (size_t i = 0; i < N; ++i)
        if (labels[i] == 0) inverted[i] = std::numeric_limits<int32_t>::max();

    std::vector<int32_t> dil8(N), ero8(N);
    morph<true>(labels, dil8.data(), H, W, /*cross=*/false);
    morph<false>(inverted.data(), ero8.data(), H, W, /*cross=*/false);

    for (size_t i = 0; i < N; ++i) {
        const bool boundary = dil[i] != ero[i];
        const bool background = labels[i] == 0;
        const bool adjacent = (dil8[i] != ero8[i]) && !background;
        out[i] = (boundary && (background || adjacent)) ? 1 : 0;
    }
}

void relief_inflate(const int32_t *labels, const uint8_t *foreground, float *out,
                    size_t rows, size_t cols, int iters, int kernel) {
    // Every region is inflated in a single distance transform: label
    // boundaries are the outline, so the distance to the nearest boundary *is*
    // the distance to that region's own outline. Normalisation is global, so a
    // large robe domes higher than a small hand -- normalising per region would
    // turn every superpixel into an identical hemisphere.
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    std::vector<uint8_t> boundaries(N);
    relief_find_boundaries_outer(labels, boundaries.data(), rows, cols);

    cv::Mat interior(H, W, CV_8UC1);
    for (size_t i = 0; i < N; ++i) {
        uint8_t v = boundaries[i] ? 0 : 1;
        if (foreground != nullptr) v &= (foreground[i] ? 1 : 0);
        interior.ptr<uint8_t>()[i] = v;
    }

    // DIST_L2 with a 5x5 mask is the accurate variant; the 3x3 approximation
    // produces visible octagonal domes. The plan deliberately keeps this
    // approximation rather than substituting an exact EDT -- an exact transform
    // is genuinely better and genuinely *different*, and parity comes first.
    cv::Mat dist;
    cv::distanceTransform(interior, dist, cv::DIST_L2, 5);

    // Iterated mean filter that never moves the outline. Re-pinning to zero on
    // every pass is what keeps the region from deflating: an unconstrained mean
    // filter bleeds height across the silhouette and flattens everything toward
    // the global mean.
    cv::Mat z = dist.clone();
    for (size_t i = 0; i < N; ++i)
        if (!interior.ptr<uint8_t>()[i]) z.ptr<float>()[i] = 0.0f;

    for (int it = 0; it < iters; ++it) {
        cv::Mat blurred;
        cv::blur(z, blurred, cv::Size(kernel, kernel));
        z = blurred;
        for (size_t i = 0; i < N; ++i)
            if (!interior.ptr<uint8_t>()[i]) z.ptr<float>()[i] = 0.0f;
    }

    relief_normalize01(z.ptr<float>(), out, N, /*robust=*/0);
}

void relief_normalize01(const float *in, float *out, size_t n, int robust) {
    // `io_utils.normalize01`. Returns zeros for a constant input rather than
    // NaN. `robust` clips to the 1st/99th percentile first, which stops a
    // single hot pixel from crushing the rest of the range.
    double lo, hi;
    if (robust) {
        std::vector<float> sorted(in, in + n);
        std::sort(sorted.begin(), sorted.end());
        auto pct = [&](double q) {
            const double idx = (sorted.size() - 1) * (q / 100.0);
            const size_t a = static_cast<size_t>(std::floor(idx));
            const size_t b = static_cast<size_t>(std::ceil(idx));
            if (a == b) return static_cast<double>(sorted[a]);
            return static_cast<double>(sorted[a]) +
                   (idx - a) * (static_cast<double>(sorted[b]) -
                                static_cast<double>(sorted[a]));
        };
        lo = pct(1.0);
        hi = pct(99.0);
    } else {
        lo = std::numeric_limits<double>::infinity();
        hi = -std::numeric_limits<double>::infinity();
        for (size_t i = 0; i < n; ++i) {
            lo = std::min(lo, static_cast<double>(in[i]));
            hi = std::max(hi, static_cast<double>(in[i]));
        }
    }
    if (hi - lo < 1e-12) {
        std::memset(out, 0, n * sizeof(float));
        return;
    }
    const float flo = static_cast<float>(lo), fhi = static_cast<float>(hi);
    for (size_t i = 0; i < n; ++i) {
        const float v = (in[i] - flo) / (fhi - flo);
        out[i] = std::min(std::max(v, 0.0f), 1.0f);
    }
}

void relief_detail_gradient(const float *brightness, float *out, size_t rows,
                            size_t cols) {
    // Paper Eq. (18-20). **Prewitt, not Sobel** -- reproduced as printed.
    // Z_detail carries the finest surface texture; alone it is meaningless as
    // geometry, which is why the paper caps its weight below 0.05.
    static const float PX[9] = {1, 0, -1, 1, 0, -1, 1, 0, -1};
    static const float PY[9] = {1, 1, 1, 0, 0, 0, -1, -1, -1};

    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    cv::Mat src(H, W, CV_32FC1, const_cast<float *>(brightness));
    cv::Mat kx(3, 3, CV_32F, const_cast<float *>(PX));
    cv::Mat ky(3, 3, CV_32F, const_cast<float *>(PY));

    cv::Mat gx, gy;
    cv::filter2D(src, gx, CV_32F, kx);
    cv::filter2D(src, gy, CV_32F, ky);

    std::vector<float> mag(rows * cols);
    for (size_t i = 0; i < rows * cols; ++i) {
        const float a = gx.ptr<float>()[i], b = gy.ptr<float>()[i];
        mag[i] = std::sqrt(a * a + b * b);
    }
    relief_normalize01(mag.data(), out, rows * cols, /*robust=*/1);
}

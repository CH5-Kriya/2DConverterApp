#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

// numpy sums float32 arrays with pairwise summation in blocks of 128, which is
// measurably more accurate than a naive loop over ~400k elements. Reproducing
// the recursion keeps the routing scalars comparable at 1e-6 instead of leaving
// a summation-order difference that looks like a porting bug.
float pairwise_sum(const float *a, size_t n) {
    if (n < 8) {
        float s = 0.0f;
        for (size_t i = 0; i < n; ++i) s += a[i];
        return s;
    }
    if (n <= 128) {
        // numpy unrolls by 8 and keeps 8 partial accumulators.
        float r[8] = {a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]};
        size_t i = 8;
        for (; i + 8 <= n; i += 8)
            for (int k = 0; k < 8; ++k) r[k] += a[i + k];
        float s = ((r[0] + r[1]) + (r[2] + r[3])) +
                  ((r[4] + r[5]) + (r[6] + r[7]));
        for (; i < n; ++i) s += a[i];
        return s;
    }
    size_t half = n / 2;
    half -= half % 8;  // numpy splits on an 8-element boundary
    return pairwise_sum(a, half) + pairwise_sum(a + half, n - half);
}

}  // namespace

void relief_route_metrics(const float *lab, size_t rows, size_t cols,
                          int quantize_colors, float *out_metrics) {
    const int r = static_cast<int>(rows), c = static_cast<int>(cols);
    const size_t n = rows * cols;

    // gray = clip(lab[..., 0] / 100, 0, 1), then a sigma-1.0 Gaussian.
    // ksize (0, 0) lets OpenCV derive the kernel from sigma, so it must stay
    // (0, 0) here rather than be pinned to a guessed size.
    cv::Mat gray(r, c, CV_32FC1);
    for (int y = 0; y < r; ++y)
        for (int x = 0; x < c; ++x)
            gray.at<float>(y, x) =
                std::min(std::max(lab[(y * c + x) * 3] / 100.0f, 0.0f), 1.0f);

    cv::Mat blurred;
    cv::GaussianBlur(gray, blurred, cv::Size(0, 0), 1.0);

    cv::Mat gx, gy;
    cv::Sobel(blurred, gx, CV_32F, 1, 0, 3);
    cv::Sobel(blurred, gy, CV_32F, 0, 1, 3);

    std::vector<float> grad(n);
    for (size_t i = 0; i < n; ++i) {
        const float a = gx.ptr<float>()[i], b = gy.ptr<float>()[i];
        grad[i] = std::sqrt(a * a + b * b);
    }

    // --- flat_area_frac: the share that is genuinely flat. Flat fills are the
    // defining feature of graphic art; even smoothly-lit paint carries
    // brushwork and canvas, so it rarely goes fully flat.
    size_t flat = 0;
    for (size_t i = 0; i < n; ++i)
        if (grad[i] < 0.01f) ++flat;
    out_metrics[0] = static_cast<float>(static_cast<double>(flat) / n);

    // --- palette_concentration: uniform CIELAB binning, not k-means --
    // deterministic and far cheaper, and this is only a routing decision.
    // `side = max(2, round(32^(1/3))) = 3`, so 27 bins; with so few, the top-8
    // share saturates at 1.0 on most real images.
    const int side = std::max(2, static_cast<int>(std::lround(
                                     std::cbrt(static_cast<double>(quantize_colors)))));
    std::vector<long long> counts(static_cast<size_t>(side) * side * side, 0);
    for (size_t i = 0; i < n; ++i) {
        const float L = std::min(std::max(lab[i * 3 + 0] / 100.0f, 0.0f), 1.0f);
        const float A = std::min(std::max((lab[i * 3 + 1] + 128.0f) / 255.0f, 0.0f), 1.0f);
        const float B = std::min(std::max((lab[i * 3 + 2] + 128.0f) / 255.0f, 0.0f), 1.0f);
        // `.astype(np.int32)` truncates toward zero, it does not round.
        const int b0 = std::min(static_cast<int>(L * side), side - 1);
        const int b1 = std::min(static_cast<int>(A * side), side - 1);
        const int b2 = std::min(static_cast<int>(B * side), side - 1);
        ++counts[static_cast<size_t>(b0) * side * side + b1 * side + b2];
    }
    std::sort(counts.begin(), counts.end(), std::greater<long long>());
    long long top = 0;
    for (size_t i = 0; i < std::min<size_t>(8, counts.size()); ++i) top += counts[i];
    out_metrics[1] = static_cast<float>(static_cast<double>(top) /
                                        std::max<size_t>(1, n));

    // --- edge_step_ratio: how concentrated gradient energy is in a few hard
    // edges. An illustration's edges are steps; a painting spreads that energy.
    const float total = pairwise_sum(grad.data(), n);
    if (total < 1e-9f) {
        out_metrics[2] = 1.0f;  // perfectly uniform is as flat as art gets
        return;
    }
    const size_t k = std::max<size_t>(1, static_cast<size_t>(0.01 * n));
    std::vector<float> sorted(grad);
    // np.partition(flat, -k)[-k:] -- the k largest, order unspecified.
    std::nth_element(sorted.begin(), sorted.end() - k, sorted.end());
    const float top_sum = pairwise_sum(sorted.data() + (n - k), k);

    const float share = top_sum / total;
    out_metrics[2] = std::min(std::max((share - 0.3f) / 0.5f, 0.0f), 1.0f);
}

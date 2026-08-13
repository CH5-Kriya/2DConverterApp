#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/ximgproc/edge_filter.hpp>

namespace {

// `np.percentile(a, q)` with the default 'linear' interpolation.
double percentile_linear(std::vector<float> v, double q) {
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    const double idx = (v.size() - 1) * (q / 100.0);
    const size_t lo = static_cast<size_t>(std::floor(idx));
    const size_t hi = static_cast<size_t>(std::ceil(idx));
    if (lo == hi) return static_cast<double>(v[lo]);
    const double frac = idx - lo;
    return static_cast<double>(v[lo]) + frac * (static_cast<double>(v[hi]) -
                                                static_cast<double>(v[lo]));
}

}  // namespace

void relief_despeckle(const float *depth, float *out, size_t rows, size_t cols,
                      int kernel) {
    // OpenCV's medianBlur accepts only ksize 3 or 5 on float32.
    const int size = std::min(5, std::max(3, kernel | 1));
    cv::Mat src(static_cast<int>(rows), static_cast<int>(cols), CV_32FC1,
                const_cast<float *>(depth));
    cv::Mat dst;
    cv::medianBlur(src, dst, size);
    std::memcpy(out, dst.ptr<float>(), rows * cols * sizeof(float));
}

void relief_guided_filter(const float *depth, const float *guide, float *out,
                          size_t rows, size_t cols, int radius, double eps) {
    // Monocular depth networks predict at reduced resolution and upsample,
    // which rounds off every silhouette. The painting still has those edges, so
    // it makes a good guide: this snaps depth discontinuities back onto the
    // luminance discontinuities that produced them.
    cv::Mat src(static_cast<int>(rows), static_cast<int>(cols), CV_32FC1,
                const_cast<float *>(depth));
    cv::Mat ref(static_cast<int>(rows), static_cast<int>(cols), CV_32FC1,
                const_cast<float *>(guide));
    cv::Mat dst;
    cv::ximgproc::guidedFilter(ref, src, dst, radius, eps);
    std::memcpy(out, dst.ptr<float>(), rows * cols * sizeof(float));
}

int relief_deband(const float *depth, float *out, size_t rows, size_t cols,
                  double spike_ratio, double banding_mass_threshold) {
    const size_t n = rows * cols;
    const int bins = 1024;

    // Banding has a specific histogram signature: tall spikes *separated by
    // empty gaps*. A tall bin alone means nothing -- every depth map has a
    // mode. So the gap test comes first, and unless enough of the image sits on
    // isolated levels the map is returned untouched.
    std::vector<double> edges(bins + 1);
    for (int i = 0; i <= bins; ++i) edges[i] = static_cast<double>(i) / bins;
    edges[bins] = 1.0;

    std::vector<int64_t> hist(bins, 0);
    std::vector<int32_t> index(n);
    for (size_t i = 0; i < n; ++i) {
        // np.digitize(depth, edges) - 1, clipped -- searchsorted(side='right').
        const double x = depth[i];
        int b = static_cast<int>(std::upper_bound(edges.begin(), edges.end(), x) -
                                 edges.begin()) - 1;
        b = std::min(std::max(b, 0), bins - 1);
        index[i] = b;
        if (x >= 0.0 && x <= 1.0) hist[b] += 1;
    }

    std::vector<char> occupied(bins, 0);
    int n_occupied = 0;
    for (int i = 0; i < bins; ++i)
        if (hist[i] > 0) { occupied[i] = 1; ++n_occupied; }
    if (n_occupied < 2) {
        std::memcpy(out, depth, n * sizeof(float));
        return 0;
    }

    std::vector<char> flanked(bins, 0);
    for (int i = 0; i + 1 < bins; ++i) if (!occupied[i + 1]) flanked[i] = 1;
    for (int i = 1; i < bins; ++i) if (!occupied[i - 1]) flanked[i] = 1;

    int64_t total = 0, isolated_count = 0;
    std::vector<char> isolated(bins, 0);
    for (int i = 0; i < bins; ++i) {
        total += hist[i];
        if (occupied[i] && flanked[i]) { isolated[i] = 1; isolated_count += hist[i]; }
    }
    const double isolated_mass =
        static_cast<double>(isolated_count) / std::max<double>(total, 1.0);

    if (isolated_mass < banding_mass_threshold) {
        std::memcpy(out, depth, n * sizeof(float));
        return 0;  // continuous input -- nothing to do
    }

    // Height alone cannot be the test: when the whole map is quantized every
    // occupied bin is an equally tall spike, so the median *is* the spike height.
    std::vector<int64_t> occ_counts;
    for (int i = 0; i < bins; ++i) if (occupied[i]) occ_counts.push_back(hist[i]);
    std::sort(occ_counts.begin(), occ_counts.end());
    const size_t m = occ_counts.size();
    const double median = (m % 2) ? static_cast<double>(occ_counts[m / 2])
                                  : 0.5 * (occ_counts[m / 2 - 1] + occ_counts[m / 2]);

    std::vector<char> spike(bins, 0);
    int n_spikes = 0;
    for (int i = 0; i < bins; ++i)
        if (isolated[i] || hist[i] > spike_ratio * median) { spike[i] = 1; ++n_spikes; }
    if (n_spikes == 0) {
        std::memcpy(out, depth, n * sizeof(float));
        return 0;
    }

    // Each spiked pixel is nudged toward its local mean and clamped to its own
    // bin's half-width: detail returns inside the band while no pixel crosses
    // into a neighbouring one, so the predicted depth ordering survives exactly.
    const float half_width = static_cast<float>(0.5 / bins);
    cv::Mat src(static_cast<int>(rows), static_cast<int>(cols), CV_32FC1,
                const_cast<float *>(depth));
    cv::Mat local_mean;
    cv::GaussianBlur(src, local_mean, cv::Size(0, 0), 2.0);

    for (size_t i = 0; i < n; ++i) {
        float delta = local_mean.ptr<float>()[i] - depth[i];
        delta = std::min(std::max(delta, -half_width), half_width);
        out[i] = spike[index[i]] ? depth[i] + delta : depth[i];
    }
    return n_spikes;
}

void relief_quantize_layers(const float *depth, const int32_t *labels,
                            int region_count, float *out, size_t rows,
                            size_t cols) {
    // A monocular network on flat graphic art gets the ordering right and then
    // ruins it -- having decided the mountain is behind the house, it shades
    // the mountain's interior into a dome the artist never drew. Collapsing
    // each region to its mean leaves every pairwise ordering identical by
    // construction while removing the invention.
    const size_t n = rows * cols;
    std::vector<double> sums(region_count, 0.0), counts(region_count, 0.0);
    for (size_t i = 0; i < n; ++i) {
        sums[labels[i]] += depth[i];
        counts[labels[i]] += 1.0;
    }
    std::vector<float> means(region_count);
    for (int i = 0; i < region_count; ++i)
        means[i] = static_cast<float>(sums[i] / std::max(counts[i], 1.0));
    for (size_t i = 0; i < n; ++i) out[i] = means[labels[i]];
}

void relief_clean_layers(const float *depth, float *out, size_t rows,
                         size_t cols) {
    // Deliberately not a blur: on the illustration branch the discontinuities
    // are the artist's compositional ordering, and smoothing them into ramps
    // reintroduces exactly the fake 3D warping this branch exists to avoid.
    relief_despeckle(depth, out, rows, cols, 5);
}

void relief_suppress_background(const float *depth, float *out, size_t rows,
                                size_t cols, double percentile) {
    // Relief budget is finite. Any of it spent lifting the background off the
    // base plate is depth not available to the subjects.
    const size_t n = rows * cols;
    const double floor_v =
        percentile_linear(std::vector<float>(depth, depth + n), percentile);
    if (floor_v >= 1.0 - 1e-6) {
        std::memcpy(out, depth, n * sizeof(float));
        return;
    }
    const float f = static_cast<float>(floor_v);
    for (size_t i = 0; i < n; ++i) {
        const float v = (depth[i] - f) / (1.0f - f);
        out[i] = std::min(std::max(v, 0.0f), 1.0f);
    }
}

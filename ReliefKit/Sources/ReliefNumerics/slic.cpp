// SLIC superpixels, reproducing `skimage.segmentation.slic`.
//
// OpenCV ships `cv::ximgproc::createSuperpixelSLIC`, and it is *not* usable
// here: it is a different implementation with different initialisation and
// different connectivity enforcement, so it would produce a different number of
// regions. Region count is not cosmetic in this pipeline -- it feeds the albedo
// divide, the ordering constraint and the layer-quantize decision -- so this is
// a deliberate hand-port of scikit-image's algorithm rather than a substitution.
//
// Ported against scikit-image 0.25.2's `_slic.pyx` and `slic_superpixels.py`.
// Several details are load-bearing and easy to get wrong:
//
//   * The image is **min-max normalised before the Lab conversion**, so SLIC's
//     internal Lab is not `rgb2lab(rgb)`.
//   * Colour centroids initialise to **zero**, not to the image colour at the
//     seed, so the first assignment pass is effectively spatial-only.
//   * The Lab image is scaled by `1 / compactness` before the solve, and the
//     spatial term is weighted by `1 / step^2`.
//   * Centroid accumulation happens in **float32 in z,y,x order**. Summing in
//     double, or in a different order, moves centroids and therefore labels.

#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

struct Grid {
    int start_y, start_x;
    int step_y, step_x;
    float step;  // max of the step sizes
};

// `skimage.util.regular_grid` for the 3D shape (1, H, W).
Grid regular_grid(int height, int width, int n_points) {
    // Dimensions sorted ascending are (1, min(H,W), max(H,W)); the depth axis
    // is always 1 here, which trips the `sorted_dims < stepsizes` branch and
    // pins the depth step to 1.
    const double space_size = 1.0 * height * width;
    Grid g{};
    if (space_size <= n_points) {
        g.start_y = g.start_x = 0;
        g.step_y = g.step_x = 1;
        g.step = 1.0f;
        return g;
    }

    // dim 0 (depth, size 1) takes stepsize 1, then the remaining two share
    // sqrt(space / n_points).
    const double planar = static_cast<double>(height) * width;
    const double step_yx = std::pow(planar / n_points, 1.0 / 2.0);

    g.start_y = static_cast<int>(std::floor(step_yx / 2.0));
    g.start_x = g.start_y;
    // numpy's `np.round` is banker's rounding: halfway goes to even.
    g.step_y = static_cast<int>(std::nearbyint(step_yx));
    g.step_x = g.step_y;
    g.step = static_cast<float>(std::max(1.0, static_cast<double>(g.step_y)));
    return g;
}

}  // namespace

int relief_slic(const float *rgb, size_t rows, size_t cols, int n_segments,
                double compactness, double sigma, int enforce_connectivity,
                int32_t *labels_out) {
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    // --- img_as_float, then min-max normalise across *all* channels. This
    // happens before the Lab conversion, which is why SLIC's Lab differs from
    // the pipeline's own `01_lab`.
    std::vector<float> img(N * 3);
    float imin = std::numeric_limits<float>::infinity();
    float imax = -std::numeric_limits<float>::infinity();
    for (size_t i = 0; i < N * 3; ++i) {
        imin = std::min(imin, rgb[i]);
        imax = std::max(imax, rgb[i]);
    }
    for (size_t i = 0; i < N * 3; ++i) {
        float v = rgb[i] - imin;
        if (imax != imin) v /= (imax - imin);
        img[i] = v;
    }

    // --- rgb2lab on the normalised image.
    std::vector<float> lab(N * 3);
    relief_rgb2lab(img.data(), lab.data(), rows, cols);

    // --- Gaussian smoothing, sigma on the spatial axes only.
    //
    // scikit-image calls `skimage.filters.gaussian`, i.e. scipy's
    // `gaussian_filter` with `mode='reflect'`. scipy's 'reflect' is
    // (d c b a | a b c d) -- OpenCV's BORDER_REFLECT, *not* the
    // BORDER_REFLECT_101 that `cv::GaussianBlur` uses by default. Radius is
    // `int(truncate * sigma + 0.5)` with truncate=4, so sigma 1 gives 9 taps.
    if (sigma > 0.0) {
        const int radius = static_cast<int>(4.0 * sigma + 0.5);
        const int ksize = 2 * radius + 1;

        // scipy builds the kernel in float64 as exp(-0.5 x^2 / sigma^2),
        // normalised to sum 1.
        std::vector<double> k(ksize);
        double sum = 0.0;
        for (int i = 0; i < ksize; ++i) {
            const double x = i - radius;
            k[i] = std::exp(-0.5 * x * x / (sigma * sigma));
            sum += k[i];
        }
        for (int i = 0; i < ksize; ++i) k[i] /= sum;

        // scipy's `correlate1d` accumulates each 1D pass in **double** and
        // stores the result back as float32; OpenCV's `filter2D` accumulates in
        // float32. That difference alone moved ~68% of the blurred Lab values
        // by a few ulp, which was enough to flip k-means ties. So the separable
        // pass is written out here rather than delegated.
        //
        // Axis order is scipy's: rows (H) first, then columns (W), with a
        // float32 array in between -- the same as `gaussian_filter` writing
        // each 1D result into the output buffer before the next axis runs.
        //
        // `mode='reflect'` is (d c b a | a b c d): index -1-i below zero and
        // 2n-1-i above the end.
        auto reflect = [](int i, int n) {
            while (i < 0 || i >= n) {
                if (i < 0) i = -1 - i;
                if (i >= n) i = 2 * n - 1 - i;
            }
            return i;
        };

        std::vector<float> tmp(N * 3);
        // pass 1: along H
        for (int y = 0; y < H; ++y)
            for (int x = 0; x < W; ++x)
                for (int c = 0; c < 3; ++c) {
                    double acc = 0.0;
                    for (int t = 0; t < ksize; ++t) {
                        const int yy = reflect(y + t - radius, H);
                        acc += k[t] * static_cast<double>(
                                          lab[(static_cast<size_t>(yy) * W + x) * 3 + c]);
                    }
                    tmp[(static_cast<size_t>(y) * W + x) * 3 + c] =
                        static_cast<float>(acc);
                }
        // pass 2: along W
        for (int y = 0; y < H; ++y)
            for (int x = 0; x < W; ++x)
                for (int c = 0; c < 3; ++c) {
                    double acc = 0.0;
                    for (int t = 0; t < ksize; ++t) {
                        const int xx = reflect(x + t - radius, W);
                        acc += k[t] * static_cast<double>(
                                          tmp[(static_cast<size_t>(y) * W + xx) * 3 + c]);
                    }
                    lab[(static_cast<size_t>(y) * W + x) * 3 + c] =
                        static_cast<float>(acc);
                }

        if (const char *dump = getenv("RELIEF_DUMP_SLIC_BLUR")) {
            FILE *f = fopen(dump, "wb");
            if (f) { fwrite(lab.data(), sizeof(float), N * 3, f); fclose(f); }
        }
    }

    // --- seeds on a regular grid; colour components start at zero.
    const Grid grid = regular_grid(H, W, n_segments);
    std::vector<int> seed_y, seed_x;
    for (int y = grid.start_y; y < H; y += grid.step_y)
        for (int x = grid.start_x; x < W; x += grid.step_x) {
            seed_y.push_back(y);
            seed_x.push_back(x);
        }
    const int K = static_cast<int>(seed_y.size());
    if (K == 0) return 0;

    // segments[k] = {y, x, L, a, b}; the depth coordinate is dropped since it
    // is always 0 for a 2D image.
    std::vector<float> cy(K), cx(K), cL(K, 0.0f), ca(K, 0.0f), cb(K, 0.0f);
    for (int k = 0; k < K; ++k) {
        cy[k] = static_cast<float>(seed_y[k]);
        cx[k] = static_cast<float>(seed_x[k]);
    }

    // --- the Lab image is scaled by 1/compactness before the solve.
    const float ratio = static_cast<float>(1.0 / compactness);
    for (size_t i = 0; i < N * 3; ++i) lab[i] *= ratio;

    const float spatial_weight = 1.0f / (grid.step * grid.step);
    const int step_y = grid.step_y, step_x = grid.step_x;

    std::vector<int32_t> nearest(N, -1);
    std::vector<float> distance(N);
    std::vector<int64_t> counts(K);

    const int max_num_iter = 10;
    for (int iter = 0; iter < max_num_iter; ++iter) {
        bool change = false;
        // The reference assigns DBL_MAX into a float32 array, which overflows
        // to +inf. Any finite candidate wins either way.
        std::fill(distance.begin(), distance.end(),
                  std::numeric_limits<float>::infinity());

        for (int k = 0; k < K; ++k) {
            const int y_min = std::max(static_cast<int>(cy[k] - 2 * step_y), 0);
            const int y_max = std::min(static_cast<int>(cy[k] + 2 * step_y + 1), H);
            const int x_min = std::max(static_cast<int>(cx[k] - 2 * step_x), 0);
            const int x_max = std::min(static_cast<int>(cx[k] + 2 * step_x + 1), W);

            for (int y = y_min; y < y_max; ++y) {
                float dy = cy[k] - y;
                dy *= dy;
                for (int x = x_min; x < x_max; ++x) {
                    float dx = cx[k] - x;
                    dx *= dx;
                    float dist = (dy + dx) * spatial_weight;

                    const size_t idx = static_cast<size_t>(y) * W + x;
                    const float tL = lab[idx * 3 + 0] - cL[k];
                    const float ta = lab[idx * 3 + 1] - ca[k];
                    const float tb = lab[idx * 3 + 2] - cb[k];
                    dist += tL * tL + ta * ta + tb * tb;

                    if (distance[idx] > dist) {
                        nearest[idx] = k;
                        distance[idx] = dist;
                        change = true;
                    }
                }
            }
        }

        if (!change) break;

        // Recompute centroids. Accumulation is float32 and in raster order --
        // both matter, because a different summation order moves the centroid
        // and therefore the labels.
        std::fill(counts.begin(), counts.end(), 0);
        std::fill(cy.begin(), cy.end(), 0.0f);
        std::fill(cx.begin(), cx.end(), 0.0f);
        std::fill(cL.begin(), cL.end(), 0.0f);
        std::fill(ca.begin(), ca.end(), 0.0f);
        std::fill(cb.begin(), cb.end(), 0.0f);

        for (int y = 0; y < H; ++y) {
            for (int x = 0; x < W; ++x) {
                const size_t idx = static_cast<size_t>(y) * W + x;
                const int k = nearest[idx];
                counts[k] += 1;
                cy[k] += static_cast<float>(y);
                cx[k] += static_cast<float>(x);
                cL[k] += lab[idx * 3 + 0];
                ca[k] += lab[idx * 3 + 1];
                cb[k] += lab[idx * 3 + 2];
            }
        }
        for (int k = 0; k < K; ++k) {
            const float n = static_cast<float>(counts[k]);
            cy[k] /= n; cx[k] /= n; cL[k] /= n; ca[k] /= n; cb[k] /= n;
        }
    }

    if (!enforce_connectivity) {
        for (size_t i = 0; i < N; ++i) labels_out[i] = nearest[i];
        return K;
    }

    // --- enforce connectivity: BFS each component, absorb the undersized ones
    // into an adjacent label, exactly as the reference does.
    const double segment_size = static_cast<double>(N) / K;
    const int min_size = static_cast<int>(0.5 * segment_size);
    const int max_size = static_cast<int>(3.0 * segment_size);

    std::vector<int32_t> connected(N, -1);
    int current_new_label = 0;
    std::vector<int64_t> coords(static_cast<size_t>(std::max(max_size, 1)));

    const int ddy[4] = {0, 0, 1, -1};
    const int ddx[4] = {1, -1, 0, 0};

    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const size_t start = static_cast<size_t>(y) * W + x;
            if (connected[start] >= 0) continue;

            int adjacent = current_new_label;
            const int32_t label = nearest[start];
            connected[start] = current_new_label;
            int size = 1, visited = 0;
            coords[0] = static_cast<int64_t>(start);

            while (visited < size && size < max_size) {
                const int64_t cur = coords[visited];
                const int cyy = static_cast<int>(cur / W);
                const int cxx = static_cast<int>(cur % W);
                for (int i = 0; i < 4; ++i) {
                    const int yy = cyy + ddy[i];
                    const int xx = cxx + ddx[i];
                    if (xx < 0 || xx >= W || yy < 0 || yy >= H) continue;
                    const size_t nidx = static_cast<size_t>(yy) * W + xx;
                    if (nearest[nidx] == label && connected[nidx] < 0) {
                        connected[nidx] = current_new_label;
                        coords[size] = static_cast<int64_t>(nidx);
                        ++size;
                        if (size >= max_size) break;
                    } else if (connected[nidx] >= 0 &&
                               connected[nidx] != current_new_label) {
                        adjacent = connected[nidx];
                    }
                }
                ++visited;
            }

            if (size < min_size) {
                for (int i = 0; i < size; ++i)
                    connected[static_cast<size_t>(coords[i])] = adjacent;
            } else {
                ++current_new_label;
            }
        }
    }

    for (size_t i = 0; i < N; ++i) labels_out[i] = connected[i];
    return current_new_label;
}

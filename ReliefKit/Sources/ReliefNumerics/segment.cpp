// Region merging and cleanup, reproducing the second half of
// `relief/segment.py`: `rag_mean_color` + `cut_threshold`, then
// `_absorb_small`, `_pack` and `_segment_means`.
//
// Label *numbering* matters here, not just the partition: `02_albedo` is an
// array indexed by label, and the fixture comparison is per-pixel label
// equality. So the component ordering that scikit-image and networkx happen to
// produce has to be reproduced, not just an equivalent grouping.

#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_set>
#include <vector>

namespace {

inline int clampi(int v, int lo, int hi) { return std::min(std::max(v, lo), hi); }

// Undirected edge key for a pair of labels, order-independent.
inline uint64_t edge_key(int a, int b) {
    const uint32_t lo = static_cast<uint32_t>(std::min(a, b));
    const uint32_t hi = static_cast<uint32_t>(std::max(a, b));
    return (static_cast<uint64_t>(hi) << 32) | lo;
}

}  // namespace

int relief_merge_regions(const float *lab, const int32_t *labels_in, size_t rows,
                         size_t cols, double merge_threshold, int min_segment_px,
                         int32_t *labels_out, float *albedo_out,
                         int albedo_capacity) {
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    int max_label = 0;
    for (size_t i = 0; i < N; ++i) max_label = std::max(max_label, labels_in[i]);
    const int n_labels = max_label + 1;

    std::vector<int32_t> cur(labels_in, labels_in + N);

    // ---------------------------------------------------------------- merge
    if (merge_threshold > 0.0) {
        // Mean colour per region, accumulated in float64 as `rag_mean_color`
        // does ('total color' is a float64 array).
        std::vector<double> sumL(n_labels, 0.0), sumA(n_labels, 0.0),
            sumB(n_labels, 0.0);
        std::vector<int64_t> count(n_labels, 0);
        for (size_t i = 0; i < N; ++i) {
            const int l = cur[i];
            count[l] += 1;
            sumL[l] += lab[i * 3 + 0];
            sumA[l] += lab[i * 3 + 1];
            sumB[l] += lab[i * 3 + 2];
        }
        for (int l = 0; l < n_labels; ++l) {
            if (count[l] > 0) {
                sumL[l] /= count[l];
                sumA[l] /= count[l];
                sumB[l] /= count[l];
            }
        }

        // Adjacency, built exactly as `RAG.__init__` does: a 3x3 footprint
        // (connectivity=2, i.e. 8-adjacency) swept in raster order with
        // mode='nearest' (clamped) borders, adding an edge from the centre to
        // every differing value. Node *insertion order* is recorded because
        // networkx's `connected_components` iterates nodes in that order, and
        // the component index becomes the new label.
        std::unordered_set<uint64_t> seen_edges;
        std::vector<std::vector<int>> adj(n_labels);
        std::vector<int> insertion_order;
        std::vector<char> inserted(n_labels, 0);

        auto touch = [&](int node) {
            if (!inserted[node]) {
                inserted[node] = 1;
                insertion_order.push_back(node);
            }
        };

        for (int y = 0; y < H; ++y) {
            for (int x = 0; x < W; ++x) {
                const int center = cur[static_cast<size_t>(y) * W + x];
                for (int dy = -1; dy <= 1; ++dy) {
                    for (int dx = -1; dx <= 1; ++dx) {
                        const int yy = clampi(y + dy, 0, H - 1);
                        const int xx = clampi(x + dx, 0, W - 1);
                        const int v = cur[static_cast<size_t>(yy) * W + xx];
                        if (v == center) continue;
                        const uint64_t key = edge_key(center, v);
                        if (seen_edges.insert(key).second) {
                            touch(center);
                            touch(v);
                            adj[center].push_back(v);
                            adj[v].push_back(center);
                        }
                    }
                }
            }
        }

        // `cut_threshold` drops edges whose weight is >= thresh, where the
        // weight is the Euclidean distance between mean colours -- a CIE76 dE
        // because the image is CIELAB.
        std::vector<int> component(n_labels, -1);
        int n_components = 0;
        std::vector<int> queue;
        for (int seed : insertion_order) {
            if (component[seed] >= 0) continue;
            const int id = n_components++;
            component[seed] = id;
            queue.clear();
            queue.push_back(seed);
            for (size_t qi = 0; qi < queue.size(); ++qi) {
                const int u = queue[qi];
                for (int v : adj[u]) {
                    if (component[v] >= 0) continue;
                    const double dL = sumL[u] - sumL[v];
                    const double dA = sumA[u] - sumA[v];
                    const double dB = sumB[u] - sumB[v];
                    const double w = std::sqrt(dL * dL + dA * dA + dB * dB);
                    if (w >= merge_threshold) continue;  // edge was removed
                    component[v] = id;
                    queue.push_back(v);
                }
            }
        }
        // Labels absent from the graph keep a component of their own, matching
        // networkx yielding isolated nodes as singleton components.
        for (int l = 0; l < n_labels; ++l)
            if (count[l] > 0 && component[l] < 0) component[l] = n_components++;

        for (size_t i = 0; i < N; ++i) cur[i] = component[cur[i]];
    }

    // -------------------------------------------------------- absorb small
    // Tiny clusters are poison downstream: their albedo estimate is noise, and
    // Z_rough would inflate each one into its own pimple.
    if (min_segment_px > 1) {
        for (int sweep = 0; sweep < 4; ++sweep) {  // absorbing exposes new ones
            int cur_max = 0;
            for (size_t i = 0; i < N; ++i) cur_max = std::max(cur_max, cur[i]);
            std::vector<int64_t> counts(cur_max + 1, 0);
            for (size_t i = 0; i < N; ++i) counts[cur[i]] += 1;

            std::vector<int> small;
            for (int l = 0; l <= cur_max; ++l)
                if (counts[l] > 0 && counts[l] < min_segment_px) small.push_back(l);
            if (small.empty()) break;

            // All remaps are computed against the same snapshot, then applied
            // together -- the reference never mutates `out` inside the loop.
            std::vector<int> lut(cur_max + 1);
            for (int l = 0; l <= cur_max; ++l) lut[l] = l;
            bool any = false;

            std::vector<int64_t> nb(cur_max + 1, 0);
            for (int label : small) {
                std::fill(nb.begin(), nb.end(), 0);
                bool found = false;
                for (int y = 0; y < H; ++y) {
                    for (int x = 0; x < W; ++x) {
                        const size_t idx = static_cast<size_t>(y) * W + x;
                        if (cur[idx] == label) continue;
                        // 4-adjacent to any pixel of `label`?
                        bool adjacent = false;
                        if (y > 0 && cur[idx - W] == label) adjacent = true;
                        else if (y + 1 < H && cur[idx + W] == label) adjacent = true;
                        else if (x > 0 && cur[idx - 1] == label) adjacent = true;
                        else if (x + 1 < W && cur[idx + 1] == label) adjacent = true;
                        if (adjacent) { nb[cur[idx]] += 1; found = true; }
                    }
                }
                if (!found) continue;
                // `np.bincount(...).argmax()` returns the *first* maximum, so
                // ties resolve to the lowest label.
                int best = -1;
                int64_t best_count = -1;
                for (int l = 0; l <= cur_max; ++l)
                    if (nb[l] > best_count) { best_count = nb[l]; best = l; }
                if (best >= 0 && best_count > 0) { lut[label] = best; any = true; }
            }
            if (!any) break;

            // Collapse chains (a -> b -> c) exactly three times, as the
            // reference does, so nothing points at a dissolved label.
            for (int pass = 0; pass < 3; ++pass) {
                std::vector<int> next(lut.size());
                for (size_t l = 0; l < lut.size(); ++l) next[l] = lut[lut[l]];
                lut.swap(next);
            }
            for (size_t i = 0; i < N; ++i) cur[i] = lut[cur[i]];
        }
    }

    // ----------------------------------------------------------------- pack
    // `np.unique(labels, return_inverse=True)` -- unique values ascending, so
    // the packed numbering follows sorted order.
    int cur_max = 0;
    for (size_t i = 0; i < N; ++i) cur_max = std::max(cur_max, cur[i]);
    std::vector<int> remap(cur_max + 1, -1);
    for (size_t i = 0; i < N; ++i) remap[cur[i]] = 0;
    int n = 0;
    for (int l = 0; l <= cur_max; ++l)
        if (remap[l] == 0) remap[l] = n++;
    for (size_t i = 0; i < N; ++i) labels_out[i] = remap[cur[i]];

    // -------------------------------------------------------- albedo (rho_i)
    // Mean of clip(L*/100) per region, accumulated in float64 like
    // `_segment_means`, then cast to float32.
    if (albedo_out != nullptr && n <= albedo_capacity) {
        std::vector<double> sums(n, 0.0);
        std::vector<double> counts(n, 0.0);
        for (size_t i = 0; i < N; ++i) {
            const float v = std::min(std::max(lab[i * 3] / 100.0f, 0.0f), 1.0f);
            sums[labels_out[i]] += v;
            counts[labels_out[i]] += 1.0;
        }
        for (int i = 0; i < n; ++i)
            albedo_out[i] = static_cast<float>(sums[i] / std::max(counts[i], 1.0));
    }

    return n;
}

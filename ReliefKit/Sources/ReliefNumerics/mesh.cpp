// Stage 6 -- close the height field into a printable solid.
//
// The geometry is overhang-free from +Z by construction: every point on the
// surface is reachable from directly above, which is what makes it print
// without supports and mill in a single setup.

#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

int relief_resample_height(const float *height, size_t rows, size_t cols,
                           int max_grid, float *out, size_t *out_rows,
                           size_t *out_cols) {
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    if (std::max(H, W) <= max_grid) {
        std::copy(height, height + rows * cols, out);
        *out_rows = rows; *out_cols = cols;
        return 0;
    }
    const double factor = static_cast<double>(max_grid) / std::max(H, W);
    const int nw = std::max(2, static_cast<int>(std::lround(W * factor)));
    const int nh = std::max(2, static_cast<int>(std::lround(H * factor)));
    cv::Mat src(H, W, CV_32FC1, const_cast<float *>(height));
    cv::Mat dst;
    cv::resize(src, dst, cv::Size(nw, nh), 0, 0, cv::INTER_AREA);
    std::copy(dst.ptr<float>(), dst.ptr<float>() + static_cast<size_t>(nh) * nw, out);
    *out_rows = static_cast<size_t>(nh);
    *out_cols = static_cast<size_t>(nw);
    return 0;
}

size_t relief_perimeter_count(size_t rows, size_t cols) {
    if (rows < 2 || cols < 2) return rows * cols;
    return 2 * (rows + cols) - 4;
}

void relief_solid_counts(size_t rows, size_t cols, size_t *vertex_count,
                         size_t *face_count) {
    const size_t p = relief_perimeter_count(rows, cols);
    *vertex_count = rows * cols + p + 1;          // grid + dropped ring + centre
    *face_count = 2 * (rows - 1) * (cols - 1)     // top surface
                + 2 * p                            // skirt walls
                + p;                               // back cap fan
}

namespace {

// Perimeter walk: top row, right column, bottom reversed, left reversed.
// The order is what makes the wall winding consistent.
std::vector<int32_t> perimeter_indices(int rows, int cols) {
    std::vector<int32_t> out;
    out.reserve(2 * (rows + cols));
    for (int x = 0; x < cols; ++x) out.push_back(x);                        // top
    for (int y = 1; y < rows; ++y) out.push_back(y * cols + (cols - 1));    // right
    for (int x = cols - 2; x >= 0; --x) out.push_back((rows - 1) * cols + x); // bottom
    for (int y = rows - 2; y >= 1; --y) out.push_back(y * cols);            // left
    return out;
}

}  // namespace

void relief_solidify(const float *grid, size_t rows, size_t cols,
                     double plate_w, double plate_h, double base_mm,
                     double relief_mm, double *vertices, int32_t *faces) {
    const int R = static_cast<int>(rows), C = static_cast<int>(cols);

    // Image row 0 is the top of the picture, which is +Y in model space --
    // hence ys running from plate_h down to 0. Flip it and the relief mirrors.
    std::vector<double> xs(C), ys(R);
    for (int x = 0; x < C; ++x)
        xs[x] = C > 1 ? plate_w * x / (C - 1) : 0.0;
    for (int y = 0; y < R; ++y)
        ys[y] = R > 1 ? plate_h - plate_h * y / (R - 1) : plate_h;

    for (int y = 0; y < R; ++y) {
        for (int x = 0; x < C; ++x) {
            const size_t i = static_cast<size_t>(y) * C + x;
            const double h = std::min(std::max(static_cast<double>(grid[i]), 0.0), 1.0);
            vertices[i * 3 + 0] = xs[x];
            vertices[i * 3 + 1] = ys[y];
            // The bas-relief compression: the whole scene's depth squashed into
            // `relief_mm` over a `base_mm` plate. This is the Depth slider.
            vertices[i * 3 + 2] = base_mm + h * relief_mm;
        }
    }

    // Top surface: two triangles per cell.
    size_t f = 0;
    auto emit = [&](int32_t a, int32_t b, int32_t c) {
        faces[f * 3 + 0] = a; faces[f * 3 + 1] = b; faces[f * 3 + 2] = c; ++f;
    };
    for (int y = 0; y < R - 1; ++y)
        for (int x = 0; x < C - 1; ++x) {
            const int32_t a = y * C + x, b = y * C + x + 1;
            const int32_t c = (y + 1) * C + x + 1, d = (y + 1) * C + x;
            emit(a, d, c);
        }
    for (int y = 0; y < R - 1; ++y)
        for (int x = 0; x < C - 1; ++x) {
            const int32_t a = y * C + x, b = y * C + x + 1;
            const int32_t c = (y + 1) * C + x + 1;
            emit(a, c, b);
        }

    // Back plate from the perimeter ring only. A flat back needs two triangles'
    // worth of information, not another 600k -- mirroring the grid would double
    // the file for no geometric gain.
    const std::vector<int32_t> ring = perimeter_indices(R, C);
    const size_t count = ring.size();
    const size_t base_start = static_cast<size_t>(R) * C;
    for (size_t i = 0; i < count; ++i) {
        vertices[(base_start + i) * 3 + 0] = vertices[ring[i] * 3 + 0];
        vertices[(base_start + i) * 3 + 1] = vertices[ring[i] * 3 + 1];
        vertices[(base_start + i) * 3 + 2] = 0.0;
    }
    const size_t centre = base_start + count;
    vertices[centre * 3 + 0] = plate_w / 2.0;
    vertices[centre * 3 + 1] = plate_h / 2.0;
    vertices[centre * 3 + 2] = 0.0;

    for (size_t i = 0; i < count; ++i) {
        const size_t n = (i + 1) % count;
        emit(ring[i], static_cast<int32_t>(base_start + i),
             static_cast<int32_t>(base_start + n));
    }
    for (size_t i = 0; i < count; ++i) {
        const size_t n = (i + 1) % count;
        emit(ring[i], static_cast<int32_t>(base_start + n), ring[n]);
    }
    for (size_t i = 0; i < count; ++i) {
        const size_t n = (i + 1) % count;
        emit(static_cast<int32_t>(base_start + n),
             static_cast<int32_t>(base_start + i),
             static_cast<int32_t>(centre));
    }
}

double relief_mesh_volume(const double *vertices, const int32_t *faces,
                          size_t face_count) {
    // Signed volume as a sum of tetrahedra from the origin. Accumulated in
    // double; for a closed, consistently wound mesh the sign is the winding.
    double total = 0.0;
    for (size_t i = 0; i < face_count; ++i) {
        const double *a = vertices + static_cast<size_t>(faces[i * 3 + 0]) * 3;
        const double *b = vertices + static_cast<size_t>(faces[i * 3 + 1]) * 3;
        const double *c = vertices + static_cast<size_t>(faces[i * 3 + 2]) * 3;
        total += (a[0] * (b[1] * c[2] - b[2] * c[1])
                - a[1] * (b[0] * c[2] - b[2] * c[0])
                + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0;
    }
    return std::fabs(total);
}

void relief_fix_normals(const double *vertices, int32_t *faces,
                        size_t face_count, size_t vertex_count) {
    // `trimesh.fix_normals()`. The raw winding out of `_solidify` is *not*
    // consistent -- the top surface, the skirt walls and the back cap are each
    // wound sensibly in isolation but disagree with one another, so a signed
    // volume over the raw mesh largely cancels. The reference leans on trimesh
    // to repair this, so the port has to do the same or every downstream
    // measurement (volume, watertightness, the STL itself) is wrong.
    //
    // Two passes: make the winding *consistent* by walking face adjacency, then
    // flip globally if the result came out inside-out.
    if (face_count == 0) return;

    // edge (min,max) -> up to two incident faces
    struct EdgeRef { int32_t f[2]; int8_t n; };
    std::vector<std::pair<uint64_t, int32_t>> edges;
    edges.reserve(face_count * 3);
    auto key = [](int32_t a, int32_t b) {
        const uint32_t lo = static_cast<uint32_t>(std::min(a, b));
        const uint32_t hi = static_cast<uint32_t>(std::max(a, b));
        return (static_cast<uint64_t>(hi) << 32) | lo;
    };
    for (size_t f = 0; f < face_count; ++f)
        for (int e = 0; e < 3; ++e)
            edges.emplace_back(key(faces[f * 3 + e], faces[f * 3 + (e + 1) % 3]),
                               static_cast<int32_t>(f));
    std::sort(edges.begin(), edges.end());

    // neighbour lists, built from runs of equal edge keys
    std::vector<std::vector<int32_t>> neighbours(face_count);
    for (size_t i = 0; i < edges.size();) {
        size_t j = i;
        while (j < edges.size() && edges[j].first == edges[i].first) ++j;
        for (size_t a = i; a < j; ++a)
            for (size_t b = a + 1; b < j; ++b) {
                neighbours[edges[a].second].push_back(edges[b].second);
                neighbours[edges[b].second].push_back(edges[a].second);
            }
        i = j;
    }

    // Does face `f` traverse the directed edge (u -> v)?
    auto traverses = [&](int32_t f, int32_t u, int32_t v) {
        for (int e = 0; e < 3; ++e)
            if (faces[f * 3 + e] == u && faces[f * 3 + (e + 1) % 3] == v) return true;
        return false;
    };

    std::vector<char> visited(face_count, 0);
    std::vector<int32_t> stack;
    for (size_t seed = 0; seed < face_count; ++seed) {
        if (visited[seed]) continue;
        visited[seed] = 1;
        stack.clear();
        stack.push_back(static_cast<int32_t>(seed));
        while (!stack.empty()) {
            const int32_t f = stack.back();
            stack.pop_back();
            for (int32_t g : neighbours[f]) {
                if (visited[g]) continue;
                // Two correctly-wound neighbours traverse their shared edge in
                // *opposite* directions. If they agree, one is flipped.
                bool conflict = false;
                for (int e = 0; e < 3 && !conflict; ++e) {
                    const int32_t u = faces[f * 3 + e];
                    const int32_t v = faces[f * 3 + (e + 1) % 3];
                    if (traverses(g, u, v)) conflict = true;
                }
                if (conflict) std::swap(faces[g * 3 + 1], faces[g * 3 + 2]);
                visited[g] = 1;
                stack.push_back(g);
            }
        }
    }

    // Now consistent, but possibly inside-out. Signed volume decides.
    double signed_total = 0.0;
    for (size_t i = 0; i < face_count; ++i) {
        const double *a = vertices + static_cast<size_t>(faces[i * 3 + 0]) * 3;
        const double *b = vertices + static_cast<size_t>(faces[i * 3 + 1]) * 3;
        const double *c = vertices + static_cast<size_t>(faces[i * 3 + 2]) * 3;
        signed_total += (a[0] * (b[1] * c[2] - b[2] * c[1])
                       - a[1] * (b[0] * c[2] - b[2] * c[0])
                       + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0;
    }
    if (signed_total < 0.0)
        for (size_t i = 0; i < face_count; ++i)
            std::swap(faces[i * 3 + 1], faces[i * 3 + 2]);
}

int relief_mesh_is_watertight(const int32_t *faces, size_t face_count) {
    // Watertight means every edge is shared by exactly two faces. A
    // non-watertight STL is a silent failure that only shows up at the printer.
    std::vector<uint64_t> keys;
    keys.reserve(face_count * 3);
    for (size_t f = 0; f < face_count; ++f)
        for (int e = 0; e < 3; ++e) {
            const int32_t a = faces[f * 3 + e], b = faces[f * 3 + (e + 1) % 3];
            const uint32_t lo = static_cast<uint32_t>(std::min(a, b));
            const uint32_t hi = static_cast<uint32_t>(std::max(a, b));
            keys.push_back((static_cast<uint64_t>(hi) << 32) | lo);
        }
    std::sort(keys.begin(), keys.end());
    for (size_t i = 0; i < keys.size();) {
        size_t j = i;
        while (j < keys.size() && keys[j] == keys[i]) ++j;
        if (j - i != 2) return 0;
        i = j;
    }
    return 1;
}

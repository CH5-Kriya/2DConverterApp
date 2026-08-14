// Shape from shading -- Z_main, the paper's section 2.3.3.
//
// This is the stage that separates a tactile model from a depth visualization.
// The AI depth map places objects correctly in space and renders each as a
// smooth blob; this recovers the modelled form on top of it -- cheekbones,
// drapery folds. Unlike every other stage here it is iterative, so its
// tolerance is a correlation *and* a max error rather than bit-exactness.
//
// The functional (Eq. 11) is quadratic in the *normals* rather than in height,
// which is what makes the solve linear. With the boundary condition fixing the
// neighbour count at 4 everywhere, the 3x3 system is identical for every pixel
// and is inverted once.

#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

namespace {

// `np.gradient`: central differences inside, one-sided at the edges.
void gradient_y(const float *z, float *gy, int H, int W) {
    for (int x = 0; x < W; ++x) {
        for (int y = 0; y < H; ++y) {
            const size_t i = static_cast<size_t>(y) * W + x;
            if (H == 1) { gy[i] = 0.0f; continue; }
            if (y == 0) gy[i] = z[i + W] - z[i];
            else if (y == H - 1) gy[i] = z[i] - z[i - W];
            else gy[i] = (z[i + W] - z[i - W]) / 2.0f;
        }
    }
}

void gradient_x(const float *z, float *gx, int H, int W) {
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const size_t i = static_cast<size_t>(y) * W + x;
            if (W == 1) { gx[i] = 0.0f; continue; }
            if (x == 0) gx[i] = z[i + 1] - z[i];
            else if (x == W - 1) gx[i] = z[i] - z[i - 1];
            else gx[i] = (z[i + 1] - z[i - 1]) / 2.0f;
        }
    }
}

double percentile_of(const std::vector<float> &v, double q) {
    if (v.empty()) return 0.0;
    std::vector<float> s(v);
    std::sort(s.begin(), s.end());
    const double idx = (s.size() - 1) * (q / 100.0);
    const size_t a = static_cast<size_t>(std::floor(idx));
    const size_t b = static_cast<size_t>(std::ceil(idx));
    if (a == b) return static_cast<double>(s[a]);
    return static_cast<double>(s[a]) +
           (idx - a) * (static_cast<double>(s[b]) - static_cast<double>(s[a]));
}

// Orthonormal DCT-II (and its inverse, DCT-III) applied separably.
//
// Matches `cv::dct` and `scipy.fft.dct(type=2, norm='ortho')`: the k=0 term is
// scaled by sqrt(1/N) and the rest by sqrt(2/N).
void dct1d(const double *in, double *out, int n, bool inverse,
           const std::vector<double> &cosTable) {
    const double s0 = std::sqrt(1.0 / n), sk = std::sqrt(2.0 / n);
    if (!inverse) {
        for (int k = 0; k < n; ++k) {
            double acc = 0.0;
            for (int i = 0; i < n; ++i) acc += in[i] * cosTable[k * n + i];
            out[k] = acc * (k == 0 ? s0 : sk);
        }
    } else {
        for (int i = 0; i < n; ++i) {
            double acc = in[0] * s0;
            for (int k = 1; k < n; ++k) acc += in[k] * sk * cosTable[k * n + i];
            out[i] = acc;
        }
    }
}

void dct2_ortho(const double *in, double *out, int H, int W, bool inverse) {
    auto table = [](int n) {
        std::vector<double> t(static_cast<size_t>(n) * n);
        for (int k = 0; k < n; ++k)
            for (int i = 0; i < n; ++i)
                t[static_cast<size_t>(k) * n + i] =
                    std::cos(M_PI * k * (2.0 * i + 1.0) / (2.0 * n));
        return t;
    };
    const std::vector<double> tw = table(W), th = table(H);

    std::vector<double> tmp(static_cast<size_t>(H) * W);
    std::vector<double> row(W), rowOut(W), col(H), colOut(H);

    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) row[x] = in[static_cast<size_t>(y) * W + x];
        dct1d(row.data(), rowOut.data(), W, inverse, tw);
        for (int x = 0; x < W; ++x) tmp[static_cast<size_t>(y) * W + x] = rowOut[x];
    }
    for (int x = 0; x < W; ++x) {
        for (int y = 0; y < H; ++y) col[y] = tmp[static_cast<size_t>(y) * W + x];
        dct1d(col.data(), colOut.data(), H, inverse, th);
        for (int y = 0; y < H; ++y)
            out[static_cast<size_t>(y) * W + x] = colOut[y];
    }
}

// Normals from a height field: N = unit(-dz/dx, -dz/dy, 1).
void normals_from_height(const float *z, float *n, int H, int W) {
    const size_t N = static_cast<size_t>(H) * W;
    std::vector<float> gx(N), gy(N);
    gradient_x(z, gx.data(), H, W);
    gradient_y(z, gy.data(), H, W);
    for (size_t i = 0; i < N; ++i) {
        const float a = -gx[i], b = -gy[i], c = 1.0f;
        const float m = std::max(std::sqrt(a * a + b * b + c * c), 1e-6f);
        n[i * 3 + 0] = a / m;
        n[i * 3 + 1] = b / m;
        n[i * 3 + 2] = c / m;
    }
}

}  // namespace

void relief_poisson_dct(const float *p_in, const float *q_in, float *out,
                        size_t rows, size_t cols) {
    // Least-squares surface whose gradient best matches (p, q) -- Eq. (16),
    // whose normal equations are Poisson's equation. Neumann boundaries leave
    // the outline free rather than pinning it to zero.
    //
    // `cv::dct` implements exactly `scipy.fft.dct(type=2, norm='ortho')`: the
    // same orthonormal scaling, sum(x)/sqrt(N) at k=0 and sqrt(2/N) elsewhere.
    // Getting that scaling wrong would put the heights off by a constant
    // factor, which reads as a tuning problem rather than as a bug.
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    // Precision matters here in a way that is easy to miss. In the reference,
    // `wx`/`wy` are float64, so `spectrum / denominator` **promotes the whole
    // spectrum to float64**, and `idctn` therefore runs in double, with the
    // cast back to float32 happening only at the very end. Doing the division
    // in double but storing back into a float32 spectrum loses that, and over
    // the 15 integrability projections in a 300-sweep solve the difference
    // compounds into a visible one.
    cv::Mat divergence(H, W, CV_64FC1, cv::Scalar(0));
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const size_t i = static_cast<size_t>(y) * W + x;
            double v = 0.0;
            if (x > 0) v += static_cast<double>(p_in[i]) - p_in[i - 1];
            if (y > 0) v += static_cast<double>(q_in[i]) - q_in[i - W];
            divergence.ptr<double>()[i] = v;
        }
    }

    const bool even = (H % 2) == 0 && (W % 2) == 0;

    cv::Mat spectrum(H, W, CV_64FC1);
    if (even) {
        cv::dct(divergence, spectrum);
    } else {
        // `cv::dct` refuses odd-length transforms, and the SFS working size is
        // whatever the aspect ratio gives -- routinely odd on one axis.
        dct2_ortho(divergence.ptr<double>(), spectrum.ptr<double>(), H, W, false);
    }

    std::vector<double> wx(W), wy(H);
    for (int x = 0; x < W; ++x) wx[x] = 2.0 * std::cos(M_PI * x / W) - 2.0;
    for (int y = 0; y < H; ++y) wy[y] = 2.0 * std::cos(M_PI * y / H) - 2.0;

    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const size_t i = static_cast<size_t>(y) * W + x;
            double den = wx[x] + wy[y];
            if (x == 0 && y == 0) den = 1.0;  // DC: absolute height unconstrained
            spectrum.ptr<double>()[i] /= den;
        }
    }
    spectrum.ptr<double>()[0] = 0.0;

    cv::Mat height(H, W, CV_64FC1);
    if (even) {
        cv::idct(spectrum, height);
    } else {
        dct2_ortho(spectrum.ptr<double>(), height.ptr<double>(), H, W, true);
    }
    for (size_t i = 0; i < N; ++i)
        out[i] = static_cast<float>(height.ptr<double>()[i]);
}

void relief_integrate_normals(const float *normals, const uint8_t *mask,
                              float *out, size_t rows, size_t cols,
                              float max_slope) {
    const size_t N = rows * cols;
    std::vector<float> p(N), q(N);
    for (size_t i = 0; i < N; ++i) {
        const float nx = normals[i * 3 + 0];
        const float ny = normals[i * 3 + 1];
        // Guard against near-vertical facets, which would blow the slope up.
        const float nz = std::max(normals[i * 3 + 2], 0.05f);
        float pv = std::min(std::max(-nx / nz, -max_slope), max_slope);
        float qv = std::min(std::max(-ny / nz, -max_slope), max_slope);
        if (mask != nullptr) { pv *= mask[i] ? 1.0f : 0.0f;
                               qv *= mask[i] ? 1.0f : 0.0f; }
        p[i] = pv;
        q[i] = qv;
    }
    relief_poisson_dct(p.data(), q.data(), out, rows, cols);
}

int relief_solve_normals(const float *image, const float *light,
                         const uint8_t *mask, const float *init_height,
                         float *normals_out, size_t rows, size_t cols,
                         float smoothness, int iters, float omega,
                         double mbc_percentile, int project_every,
                         float *residual_out) {
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    float L[3] = {light[0], light[1], light[2]};
    {
        const float m = std::max(std::sqrt(L[0]*L[0] + L[1]*L[1] + L[2]*L[2]), 1e-9f);
        L[0] /= m; L[1] /= m; L[2] /= m;
    }

    std::vector<float> n(N * 3, 0.0f);
    if (init_height != nullptr) {
        normals_from_height(init_height, n.data(), H, W);
    } else {
        for (size_t i = 0; i < N; ++i) n[i * 3 + 2] = 1.0f;
    }

    // SBC part 1 (Eq. 13): everything outside the reconstruction domain lies on
    // the z-axis and stays there for the whole solve. This is also what fixes
    // the neighbour count at 4.
    for (size_t i = 0; i < N; ++i) {
        if (!mask[i]) {
            n[i * 3 + 0] = 0.0f; n[i * 3 + 1] = 0.0f; n[i * 3 + 2] = 1.0f;
        }
    }

    // MBC (Eq. 14): highlights face the light. This is the constraint that
    // resolves the concave/convex ambiguity.
    std::vector<float> masked;
    masked.reserve(N);
    for (size_t i = 0; i < N; ++i) if (mask[i]) masked.push_back(image[i]);
    std::vector<uint8_t> pinned(N, 0);
    if (!masked.empty()) {
        const float cut = static_cast<float>(percentile_of(masked, mbc_percentile));
        cv::Mat hi(H, W, CV_8UC1, cv::Scalar(0));
        for (size_t i = 0; i < N; ++i)
            hi.ptr<uint8_t>()[i] = (mask[i] && image[i] >= cut) ? 1 : 0;
        // Isolated bright pixels are craquelure or varnish specular, not
        // modelled form; an opening drops them.
        cv::Mat opened;
        cv::morphologyEx(hi, opened, cv::MORPH_OPEN,
                         cv::Mat::ones(3, 3, CV_8U));
        for (size_t i = 0; i < N; ++i) pinned[i] = opened.ptr<uint8_t>()[i];
    }
    for (size_t i = 0; i < N; ++i)
        if (pinned[i]) { n[i*3+0] = L[0]; n[i*3+1] = L[1]; n[i*3+2] = L[2]; }

    // SBC part 2: on the silhouette a convex subject's normal lies in the image
    // plane pointing outward. This anchors the solve to the outline the
    // segmentation already gave us -- geometry known for free, which shading
    // alone cannot supply. Measured worth 0.46 -> 0.78 on the golden sphere.
    {
        std::vector<float> indicator(N);
        for (size_t i = 0; i < N; ++i) indicator[i] = mask[i] ? 1.0f : 0.0f;
        cv::Mat solid(H, W, CV_8UC1);
        for (size_t i = 0; i < N; ++i) solid.ptr<uint8_t>()[i] = mask[i] ? 1 : 0;
        cv::Mat eroded;
        cv::erode(solid, eroded, cv::Mat::ones(3, 3, CV_8U), cv::Point(-1, -1),
                  1, cv::BORDER_CONSTANT, cv::Scalar(0));

        std::vector<float> gx(N), gy(N);
        gradient_x(indicator.data(), gx.data(), H, W);
        gradient_y(indicator.data(), gy.data(), H, W);

        for (size_t i = 0; i < N; ++i) {
            const bool ring = mask[i] && !eroded.ptr<uint8_t>()[i];
            if (!ring) continue;
            const float ox = -gx[i], oy = -gy[i];
            const float mag = std::sqrt(ox * ox + oy * oy);
            // A mask filling the frame has no real silhouette, only a crop
            // edge; those pixels are left free rather than pinned to nonsense.
            if (!(mag > 1e-3f)) continue;
            const float d = std::max(mag, 1e-6f);
            n[i*3+0] = ox / d; n[i*3+1] = oy / d; n[i*3+2] = 0.0f;
            pinned[i] = 1;
        }
    }

    std::vector<uint8_t> freeMask(N);
    size_t n_free = 0;
    for (size_t i = 0; i < N; ++i) {
        freeMask[i] = (mask[i] && !pinned[i]) ? 1 : 0;
        if (freeMask[i]) ++n_free;
    }
    if (n_free == 0) {
        std::memcpy(normals_out, n.data(), N * 3 * sizeof(float));
        if (residual_out) *residual_out = 0.0f;
        return 0;
    }

    // (L L^T + lambda * m * I), constant across pixels thanks to the SBC.
    const float m_neighbours = 4.0f;
    cv::Mat system(3, 3, CV_32F);
    for (int a = 0; a < 3; ++a)
        for (int b = 0; b < 3; ++b)
            system.at<float>(a, b) = L[a] * L[b] +
                (a == b ? smoothness * m_neighbours : 0.0f);
    cv::Mat inv = system.inv();
    float M[3][3];
    for (int a = 0; a < 3; ++a)
        for (int b = 0; b < 3; ++b) M[a][b] = inv.at<float>(a, b);

    std::vector<float> prev(N * 3);
    std::vector<float> nbsum(N * 3);
    float residual = 0.0f;
    int used = iters;

    for (int sweep = 0; sweep < iters; ++sweep) {
        std::memcpy(prev.data(), n.data(), N * 3 * sizeof(float));

        // Red/black checkerboard: a red pixel's 4-neighbours are all black, so
        // updating one colour at a time using current values *is* Gauss-Seidel
        // while staying trivially parallel.
        for (int colour = 0; colour < 2; ++colour) {
            // Neighbour sum with the border padded by the z-axis constant --
            // the SBC of Eq. (13) at the image edge, keeping the count at 4.
            for (int y = 0; y < H; ++y) {
                for (int x = 0; x < W; ++x) {
                    const size_t i = static_cast<size_t>(y) * W + x;
                    float s0 = 0, s1 = 0, s2 = 0;
                    auto add = [&](int yy, int xx) {
                        if (yy < 0 || yy >= H || xx < 0 || xx >= W) { s2 += 1.0f; return; }
                        const size_t j = static_cast<size_t>(yy) * W + xx;
                        s0 += n[j*3+0]; s1 += n[j*3+1]; s2 += n[j*3+2];
                    };
                    add(y - 1, x); add(y + 1, x); add(y, x - 1); add(y, x + 1);
                    nbsum[i*3+0] = s0; nbsum[i*3+1] = s1; nbsum[i*3+2] = s2;
                }
            }
            for (int y = 0; y < H; ++y) {
                for (int x = 0; x < W; ++x) {
                    const size_t i = static_cast<size_t>(y) * W + x;
                    if (!freeMask[i]) continue;
                    if (((y + x) & 1) != (colour == 0 ? 0 : 1)) continue;

                    const float r0 = image[i] * L[0] + smoothness * nbsum[i*3+0];
                    const float r1 = image[i] * L[1] + smoothness * nbsum[i*3+1];
                    const float r2 = image[i] * L[2] + smoothness * nbsum[i*3+2];

                    // rhs @ inverse.T
                    const float c0 = r0*M[0][0] + r1*M[0][1] + r2*M[0][2];
                    const float c1 = r0*M[1][0] + r1*M[1][1] + r2*M[1][2];
                    const float c2 = r0*M[2][0] + r1*M[2][1] + r2*M[2][2];

                    // Successive over-relaxation: overshoot the Gauss-Seidel step.
                    n[i*3+0] = (1.0f - omega) * n[i*3+0] + omega * c0;
                    n[i*3+1] = (1.0f - omega) * n[i*3+1] + omega * c1;
                    n[i*3+2] = (1.0f - omega) * n[i*3+2] + omega * c2;
                }
            }
        }

        // The linear formulation drops |N| = 1 -- that is what makes it linear.
        // Reimposing it once per sweep keeps the solution on the manifold.
        for (size_t i = 0; i < N; ++i) {
            if (!freeMask[i]) continue;
            const float a = n[i*3+0], b = n[i*3+1], c = n[i*3+2];
            const float mag = std::max(std::sqrt(a*a + b*b + c*c), 1e-6f);
            n[i*3+0] = a / mag; n[i*3+1] = b / mag; n[i*3+2] = c / mag;
        }

        // Integrability projection (Frankot & Chellappa): integrate the current
        // field, then take the normals of the surface that came out. Anything
        // not belonging to a real surface is discarded.
        if (project_every > 0 && (sweep + 1) % project_every == 0) {
            std::vector<float> height(N);
            relief_integrate_normals(n.data(), mask, height.data(), rows, cols, 8.0f);
            std::vector<float> projected(N * 3);
            normals_from_height(height.data(), projected.data(), H, W);
            for (size_t i = 0; i < N; ++i)
                if (freeMask[i])
                    for (int c = 0; c < 3; ++c) n[i*3+c] = projected[i*3+c];
        }

        if (sweep % 25 == 0 || sweep == iters - 1) {
            // Mean, not max: on a real painting a handful of pixels along hard
            // craquelure edges oscillate indefinitely, so a max-based residual
            // reports "not converged" long after the field has settled.
            double acc = 0.0;
            for (size_t i = 0; i < N; ++i) {
                if (!freeMask[i]) continue;
                for (int c = 0; c < 3; ++c)
                    acc += std::fabs(n[i*3+c] - prev[i*3+c]);
            }
            residual = static_cast<float>(acc / (n_free * 3));
            if (residual < 1e-6f) { used = sweep + 1; break; }
        }
    }

    std::memcpy(normals_out, n.data(), N * 3 * sizeof(float));
    if (residual_out) *residual_out = residual;
    return used;
}

void relief_estimate_light(const float *image, const uint8_t *mask, size_t rows,
                           size_t cols, float elevation, float *out_vector,
                           float *out_confidence) {
    // The heuristic: on a convex, roughly centred subject the surface facing
    // the light is the bright one, so the offset from the subject's centroid to
    // the centroid of its brightest pixels points along the light's azimuth.
    // Crude next to a photometric solve -- but photometric assumptions do not
    // hold on a hand-painted surface anyway, and this fails visibly: a relief
    // lit from the wrong side looks wrong immediately under raking light.
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    auto fallback = [&](float x, float y, float z, float conf) {
        out_vector[0] = x; out_vector[1] = y; out_vector[2] = z;
        *out_confidence = conf;
    };

    size_t mask_count = 0;
    for (size_t i = 0; i < N; ++i) if (mask[i]) ++mask_count;
    if (mask_count < 64) { fallback(0.3f, 0.4f, 0.85f, 0.0f); return; }

    cv::Mat src(H, W, CV_32FC1, const_cast<float *>(image));
    cv::Mat smooth;
    cv::GaussianBlur(src, smooth, cv::Size(0, 0), 3.0);

    std::vector<float> values;
    values.reserve(mask_count);
    for (size_t i = 0; i < N; ++i)
        if (mask[i]) values.push_back(smooth.ptr<float>()[i]);
    const float cut = static_cast<float>(percentile_of(values, 90.0));

    double sx = 0, sy = 0, bx = 0, by = 0;
    size_t bright_count = 0;
    for (int y = 0; y < H; ++y) {
        for (int x = 0; x < W; ++x) {
            const size_t i = static_cast<size_t>(y) * W + x;
            if (!mask[i]) continue;
            sx += x; sy += y;
            if (smooth.ptr<float>()[i] >= cut) { bx += x; by += y; ++bright_count; }
        }
    }
    if (bright_count < 16) { fallback(0.3f, 0.4f, 0.85f, 0.0f); return; }

    const double subject_x = sx / mask_count, subject_y = sy / mask_count;
    const double dx = bx / bright_count - subject_x;
    const double dy = by / bright_count - subject_y;

    // Normalize by the subject's own extent, so the result does not depend on
    // resolution or on how much of the frame the subject fills.
    double vx = 0, vy = 0;
    for (int y = 0; y < H; ++y)
        for (int x = 0; x < W; ++x) {
            const size_t i = static_cast<size_t>(y) * W + x;
            if (!mask[i]) continue;
            vx += (x - subject_x) * (x - subject_x);
            vy += (y - subject_y) * (y - subject_y);
        }
    const double extent_x = std::max(1.0, std::sqrt(vx / mask_count) * 2.0);
    const double extent_y = std::max(1.0, std::sqrt(vy / mask_count) * 2.0);

    const double nx = dx / extent_x, ny = dy / extent_y;
    const double magnitude = std::hypot(nx, ny);
    if (magnitude < 1e-3) { fallback(0.0f, 0.0f, 1.0f, 0.1f); return; }

    const double scale = std::min(1.0, magnitude) / magnitude;
    double ux = nx * scale, uy = ny * scale, uz = elevation;
    const double m = std::max(std::sqrt(ux*ux + uy*uy + uz*uz), 1e-9);
    out_vector[0] = static_cast<float>(ux / m);
    out_vector[1] = static_cast<float>(uy / m);
    out_vector[2] = static_cast<float>(uz / m);
    *out_confidence = static_cast<float>(std::min(std::max(magnitude, 0.0), 1.0));
}

void relief_shape_from_shading(const float *image, const float *light,
                               const uint8_t *mask, const float *init_height,
                               float *out, size_t rows, size_t cols,
                               float smoothness, int iters, float omega,
                               double mbc_percentile, int scale,
                               int project_every) {
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    // Solved at reduced resolution: the SFS result is inherently low-frequency
    // (the smoothness term guarantees it), so full-resolution iteration costs
    // time without adding information. Fine detail is Z_detail's job.
    int sh = H, sw = W;
    const bool downscale = (scale > 0 && std::max(H, W) > scale);
    if (downscale) {
        const double factor = static_cast<double>(scale) / std::max(H, W);
        sw = std::max(2, static_cast<int>(std::lround(W * factor)));
        sh = std::max(2, static_cast<int>(std::lround(H * factor)));
    }

    cv::Mat imgFull(H, W, CV_32FC1, const_cast<float *>(image));
    cv::Mat maskFull(H, W, CV_8UC1);
    for (size_t i = 0; i < N; ++i) maskFull.ptr<uint8_t>()[i] = mask[i];

    cv::Mat imgS, maskS, initS;
    if (downscale) {
        cv::resize(imgFull, imgS, cv::Size(sw, sh), 0, 0, cv::INTER_AREA);
        cv::resize(maskFull, maskS, cv::Size(sw, sh), 0, 0, cv::INTER_NEAREST);
        if (init_height != nullptr) {
            cv::Mat initFull(H, W, CV_32FC1, const_cast<float *>(init_height));
            cv::resize(initFull, initS, cv::Size(sw, sh), 0, 0, cv::INTER_AREA);
        }
    } else {
        imgS = imgFull; maskS = maskFull;
        if (init_height != nullptr)
            initS = cv::Mat(H, W, CV_32FC1, const_cast<float *>(init_height));
    }

    const size_t NS = static_cast<size_t>(sh) * sw;
    std::vector<float> normals(NS * 3);
    float residual = 0.0f;
    relief_solve_normals(imgS.ptr<float>(), light, maskS.ptr<uint8_t>(),
                         initS.empty() ? nullptr : initS.ptr<float>(),
                         normals.data(), sh, sw, smoothness, iters, omega,
                         mbc_percentile, project_every, &residual);

    std::vector<float> height(NS);
    relief_integrate_normals(normals.data(), maskS.ptr<uint8_t>(), height.data(),
                             sh, sw, 8.0f);
    std::vector<float> normed(NS);
    relief_normalize01(height.data(), normed.data(), NS, 0);

    cv::Mat small(sh, sw, CV_32FC1, normed.data());
    if (sh != H || sw != W) {
        cv::Mat up;
        cv::resize(small, up, cv::Size(W, H), 0, 0, cv::INTER_CUBIC);
        std::memcpy(out, up.ptr<float>(), N * sizeof(float));
    } else {
        std::memcpy(out, small.ptr<float>(), N * sizeof(float));
    }
    for (size_t i = 0; i < N; ++i) out[i] *= mask[i] ? 1.0f : 0.0f;
}

void relief_resize_bicubic_channels(const float *src, float *dst, int src_h,
                                    int src_w, int dst_h, int dst_w,
                                    int channels) {
    // PyTorch's `F.interpolate(mode="bicubic", align_corners=False)`.
    //
    // Written out rather than delegated to `cv::resize(INTER_CUBIC)` because
    // the two disagree at the borders: OpenCV replicates edge pixels, PyTorch
    // clamps the *sample index* into range while keeping the cubic weights.
    // On a 37x37 grid the border is 4 of every 37 rows, so that difference is
    // not a rounding detail.
    //
    // Cubic convolution with A = -0.75, matching both.
    const double A = -0.75;
    auto weights = [&](double t, double w[4]) {
        const double t1 = t, t2 = 1.0 - t;
        w[0] = ((A * (t1 + 1) - 5 * A) * (t1 + 1) + 8 * A) * (t1 + 1) - 4 * A;
        w[1] = ((A + 2) * t1 - (A + 3)) * t1 * t1 + 1;
        w[2] = ((A + 2) * t2 - (A + 3)) * t2 * t2 + 1;
        w[3] = ((A * (t2 + 1) - 5 * A) * (t2 + 1) + 8 * A) * (t2 + 1) - 4 * A;
    };

    const double scale_y = static_cast<double>(src_h) / dst_h;
    const double scale_x = static_cast<double>(src_w) / dst_w;

    std::vector<int> xi(dst_w * 4);
    std::vector<double> xw(dst_w * 4);
    for (int x = 0; x < dst_w; ++x) {
        const double sx = (x + 0.5) * scale_x - 0.5;   // align_corners=False
        const int base = static_cast<int>(std::floor(sx));
        double w[4];
        weights(sx - base, w);
        for (int k = 0; k < 4; ++k) {
            xi[x * 4 + k] = std::min(std::max(base - 1 + k, 0), src_w - 1);
            xw[x * 4 + k] = w[k];
        }
    }

    for (int y = 0; y < dst_h; ++y) {
        const double sy = (y + 0.5) * scale_y - 0.5;
        const int baseY = static_cast<int>(std::floor(sy));
        double wy[4];
        weights(sy - baseY, wy);
        int yi[4];
        for (int k = 0; k < 4; ++k)
            yi[k] = std::min(std::max(baseY - 1 + k, 0), src_h - 1);

        for (int x = 0; x < dst_w; ++x) {
            for (int c = 0; c < channels; ++c) {
                double acc = 0.0;
                for (int ky = 0; ky < 4; ++ky) {
                    double row = 0.0;
                    for (int kx = 0; kx < 4; ++kx) {
                        const size_t idx =
                            (static_cast<size_t>(yi[ky]) * src_w + xi[x * 4 + kx]) *
                                channels + c;
                        row += xw[x * 4 + kx] * src[idx];
                    }
                    acc += wy[ky] * row;
                }
                dst[(static_cast<size_t>(y) * dst_w + x) * channels + c] =
                    static_cast<float>(acc);
            }
        }
    }
}

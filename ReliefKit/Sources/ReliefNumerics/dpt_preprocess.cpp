#include "relief_numerics.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace {

// PIL's BICUBIC filter: cubic convolution with a = -0.5, support 2.0.
//
// Note the constant differs from PyTorch's -0.75. The reference pipeline hands
// the image to `DPTImageProcessor`, which resizes a **PIL** image, so this is
// the filter that has to be reproduced -- not the one used for the position
// embeddings a few lines away in the same file.
// PIL's LANCZOS: sinc(x) * sinc(x/3), support 3.0.
//
// This is the filter `io_utils.load_image` reaches through
// `Image.resize(..., Image.LANCZOS)`. It is *not* what CGImageSource's
// thumbnail path produces -- measured against PIL on a real painting, that
// differs by 1.6% mean and 18% max, which is orders of magnitude past every
// stage tolerance in this pipeline and shows up in the relief as spikes.
inline double pil_sinc(double x) {
    if (x == 0.0) return 1.0;
    x *= M_PI;
    return std::sin(x) / x;
}

inline double pil_lanczos(double x) {
    if (-3.0 <= x && x < 3.0) return pil_sinc(x) * pil_sinc(x / 3.0);
    return 0.0;
}

inline double pil_bicubic(double x) {
    const double a = -0.5;
    x = std::fabs(x);
    if (x < 1.0) return ((a + 2.0) * x - (a + 3.0)) * x * x + 1.0;
    if (x < 2.0) return (((x - 5.0) * x + 8.0) * x - 4.0) * a;
    return 0.0;
}

// One axis of PIL's resample.
//
// Two details decide whether this matches or is off by one 8-bit step:
//
//   * The support widens by the reduction factor when downscaling. That
//     antialiasing is the main way PIL differs from a plain bicubic sample, and
//     skipping it aliases every fine brushstroke.
//   * PIL accumulates in **fixed-point int32**, not float. Weights are
//     normalised in double, then rounded to 22-bit fixed point; the sum starts
//     at half an LSB for rounding and is shifted back down at the end. Doing it
//     in floating point lands one step away on a scattering of pixels, which
//     after ImageNet normalisation is 1.75e-2 -- small, but systematic.
constexpr int kPrecisionBits = 32 - 8 - 2;   // PIL's PRECISION_BITS

inline uint8_t clip8(int32_t v) {
    v >>= kPrecisionBits;
    return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
}

void resample_axis(const float *src, float *dst, int src_len, int dst_len,
                   int other_len, int channels, bool horizontal,
                   bool lanczos = false) {
    const double scale = static_cast<double>(src_len) / dst_len;
    const double filterscale = std::max(1.0, scale);
    const double base_support = lanczos ? 3.0 : 2.0;
    const double support = base_support * filterscale;
    const double inv = 1.0 / filterscale;

    std::vector<double> w;
    std::vector<int32_t> k;

    for (int i = 0; i < dst_len; ++i) {
        const double centre = (i + 0.5) * scale;
        int xmin = static_cast<int>(centre - support + 0.5);
        int xmax = static_cast<int>(centre + support + 0.5);
        xmin = std::max(xmin, 0);
        xmax = std::min(xmax, src_len);
        const int n = xmax - xmin;
        if (n <= 0) continue;

        w.assign(n, 0.0);
        double total = 0.0;
        for (int j = 0; j < n; ++j) {
            const double t = (j + xmin - centre + 0.5) * inv;
            const double v = lanczos ? pil_lanczos(t) : pil_bicubic(t);
            w[j] = v;
            total += v;
        }
        if (total != 0.0)
            for (auto &v : w) v /= total;

        // round half away from zero, as PIL's normalize_coeffs_8bpc does
        k.assign(n, 0);
        for (int j = 0; j < n; ++j) {
            const double scaled = w[j] * (1 << kPrecisionBits);
            k[j] = static_cast<int32_t>(scaled < 0 ? scaled - 0.5 : scaled + 0.5);
        }

        for (int j = 0; j < other_len; ++j) {
            for (int c = 0; c < channels; ++c) {
                int32_t acc = 1 << (kPrecisionBits - 1);   // rounding term
                for (int t = 0; t < n; ++t) {
                    const size_t idx = horizontal
                        ? (static_cast<size_t>(j) * src_len + (xmin + t)) * channels + c
                        : (static_cast<size_t>(xmin + t) * other_len + j) * channels + c;
                    acc += static_cast<int32_t>(src[idx]) * k[t];
                }
                const size_t out = horizontal
                    ? (static_cast<size_t>(j) * dst_len + i) * channels + c
                    : (static_cast<size_t>(i) * other_len + j) * channels + c;
                dst[out] = static_cast<float>(clip8(acc));
            }
        }
    }
}

}  // namespace

void relief_dpt_preprocess(const float *rgb, size_t rows, size_t cols,
                           int out_h, int out_w, float *out) {
    // Reproduces `DPTImageProcessor`: uint8 -> PIL bicubic resize -> /255 ->
    // (x - mean) / std, emitted as CHW for the model.
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    // The reference builds a PIL image from uint8, so the quantisation happens
    // *before* the resize and has to happen here too:
    //
    //     Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    //
    // `astype` **truncates** toward zero. Rounding instead shifts roughly half
    // the pixels by one 8-bit step going in, which survives the resize and
    // lands as 1.75e-2 after ImageNet normalisation -- the same trap as the
    // 16-bit conversion feeding CLAHE in stage 1.
    std::vector<float> u8(N * 3);
    for (size_t i = 0; i < N * 3; ++i)
        u8[i] = std::trunc(std::min(std::max(rgb[i], 0.0f), 1.0f) * 255.0f);

    // PIL resizes horizontally then vertically.
    std::vector<float> tmp(static_cast<size_t>(H) * out_w * 3);
    resample_axis(u8.data(), tmp.data(), W, out_w, H, 3, /*horizontal=*/true);
    std::vector<float> resized(static_cast<size_t>(out_h) * out_w * 3);
    resample_axis(tmp.data(), resized.data(), H, out_h, out_w, 3,
                  /*horizontal=*/false);

    // ImageNet statistics, from preprocessor_config.json.
    const float mean[3] = {0.485f, 0.456f, 0.406f};
    const float std_[3] = {0.229f, 0.224f, 0.225f};

    const size_t plane = static_cast<size_t>(out_h) * out_w;
    for (int y = 0; y < out_h; ++y)
        for (int x = 0; x < out_w; ++x)
            for (int c = 0; c < 3; ++c) {
                const float v = resized[(static_cast<size_t>(y) * out_w + x) * 3 + c]
                              / 255.0f;
                out[c * plane + static_cast<size_t>(y) * out_w + x] =
                    (v - mean[c]) / std_[c];
            }
}


void relief_pil_lanczos_rgb(const uint8_t *rgb, size_t rows, size_t cols,
                            int out_h, int out_w, float *out) {
    // `io_utils.load_image`: PIL LANCZOS downscale of the 8-bit image, then
    // /255 into float32. Reproduced rather than delegated to CoreGraphics --
    // see the note on `pil_lanczos` for what that costs.
    const int H = static_cast<int>(rows), W = static_cast<int>(cols);
    const size_t N = rows * cols;

    std::vector<float> src(N * 3);
    for (size_t i = 0; i < N * 3; ++i) src[i] = static_cast<float>(rgb[i]);

    // PIL resizes horizontally first, then vertically, clamping to 8 bits in
    // between; both passes have to happen in that order to match.
    std::vector<float> tmp(static_cast<size_t>(H) * out_w * 3);
    resample_axis(src.data(), tmp.data(), W, out_w, H, 3, true, /*lanczos=*/true);
    std::vector<float> resized(static_cast<size_t>(out_h) * out_w * 3);
    resample_axis(tmp.data(), resized.data(), H, out_h, out_w, 3, false,
                  /*lanczos=*/true);

    for (size_t i = 0; i < static_cast<size_t>(out_h) * out_w * 3; ++i)
        out[i] = resized[i] / 255.0f;
}

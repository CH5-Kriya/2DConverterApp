// C API for the numerical core. Swift talks to this; the implementations are
// C++ so they can call OpenCV directly.
//
// The Python pipeline is the specification, so each function here documents
// which reference function it reproduces and any place where matching it
// required doing something that looks wrong in isolation.

#ifndef RELIEF_NUMERICS_H
#define RELIEF_NUMERICS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// sRGB -> CIELAB, reproducing `skimage.color.rgb2lab`.
///
/// `rgb` is `rows * cols * 3` interleaved float32 in [0, 1]; `lab_out` is
/// `rows * cols * 3` interleaved float32 with L in [0, 100] and a/b roughly in
/// [-128, 127]. In-place is not supported.
///
/// Deliberately *not* `cv::cvtColor(..., COLOR_RGB2Lab)`: OpenCV's conversion
/// uses different constants and a different scaling, so it would diverge from
/// the reference. This is one of the few places the port hand-writes what a
/// library could nearly do.
///
/// Three details that matter for matching scikit-image exactly:
///
///  * Everything runs in **float32**. scikit-image keeps the input dtype, and
///    the pipeline hands it float32, so computing in double and rounding at the
///    end gives different answers.
///  * The Lab nonlinearity uses the **legacy** constants 0.008856 and 7.787,
///    not the exact CIE 216/24389 and 841/108. A "more correct" implementation
///    is a mismatch here.
///  * The XYZ matrix is cast to float32 *before* the multiply, matching
///    `arr @ xyz_from_rgb.T.astype(arr.dtype)`.
void relief_rgb2lab(const float *rgb, float *lab_out, size_t rows, size_t cols);

/// Perceptual lightness in [0, 1] -- `clip(lab[..., 0] / 100, 0, 1)`, the
/// pipeline's `Y_L` before CLAHE.
///
/// This is not a grayscale conversion. Grayscale is a weighted average of R, G
/// and B; L* is the channel that responds the way the eye does, which is what
/// the shape-from-shading solver in stage 7 assumes it is being given.
void relief_lightness_from_lab(const float *lab, float *out, size_t rows,
                               size_t cols);

/// CLAHE on a [0, 1] image, reproducing `s1_preprocess._clahe`.
///
/// Runs at **16-bit**, as the reference does: at 8-bit the quantization CLAHE
/// introduces resurfaces as banding in the stage-4 de-bander.
void relief_clahe(const float *gray01, float *out, size_t rows, size_t cols,
                  double clip_limit, int tile_grid);

/// Paper Eq. (1), `Y_i = (1/rho_i) * Y_Li` -- `s1_preprocess.albedo_normalize`.
///
/// This is the step that "bypasses the colouring": shape-from-shading assumes
/// brightness varies only with surface orientation, but in a painting it also
/// varies with pigment. Dividing each region by its own mean lightness removes
/// the pigment term, so a dark robe and a bright wall at the same depth stop
/// reconstructing as different heights.
///
/// `albedo` has `region_count` entries indexed by the values in `labels`.
void relief_albedo_normalize(const float *lightness, const int32_t *labels,
                             const float *albedo, size_t region_count,
                             float albedo_floor, float *out, size_t rows,
                             size_t cols);

/// Stage 2 routing metrics, from `s2_route._metrics`.
///
/// Writes three values into `out_metrics`, in this order:
/// `flat_area_frac`, `palette_concentration`, `edge_step_ratio`. The router
/// scores them with an equal-weighted mean and calls anything at or above
/// `flatness_threshold` an illustration.
///
/// Routing no longer selects a different depth model -- it only decides whether
/// stage 4 quantizes depth to one constant per colour region.
void relief_route_metrics(const float *lab, size_t rows, size_t cols,
                          int quantize_colors, float *out_metrics);

/// SLIC superpixels, reproducing `skimage.segmentation.slic`.
///
/// Deliberately hand-ported rather than delegated to
/// `cv::ximgproc::createSuperpixelSLIC`, which is a different algorithm and
/// would yield a different number of regions. Region count feeds the albedo
/// divide, the ordering constraint and the layer-quantize decision, so it has
/// to match the reference exactly rather than approximately.
///
/// `rgb` is interleaved float32 in [0, 1]. Writes `rows * cols` labels in
/// [0, n) and returns n.
int relief_slic(const float *rgb, size_t rows, size_t cols, int n_segments,
                double compactness, double sigma, int enforce_connectivity,
                int32_t *labels_out);

/// Region merging and cleanup -- the second half of `relief/segment.py`.
///
/// Takes SLIC's labels and merges adjacent regions whose mean CIELAB colours
/// are within `merge_threshold` (a CIE76 dE), dissolves regions below
/// `min_segment_px` into their most common neighbour, packs the labels dense,
/// and writes the per-region albedo rho_i.
///
/// `lab` is the pipeline's own CIELAB (from the *unnormalised* image), not the
/// internally normalised one SLIC uses. Returns the region count.
int relief_merge_regions(const float *lab, const int32_t *labels_in, size_t rows,
                         size_t cols, double merge_threshold, int min_segment_px,
                         int32_t *labels_out, float *albedo_out,
                         int albedo_capacity);

/// Stage 4 pieces, from `s4_correct.py`. Each mirrors one reference function.
void relief_despeckle(const float *depth, float *out, size_t rows, size_t cols,
                      int kernel);
void relief_guided_filter(const float *depth, const float *guide, float *out,
                          size_t rows, size_t cols, int radius, double eps);
/// Returns the number of spike levels found; 0 means the map was returned
/// untouched because the histogram showed no banding.
int relief_deband(const float *depth, float *out, size_t rows, size_t cols,
                  double spike_ratio, double banding_mass_threshold);
void relief_quantize_layers(const float *depth, const int32_t *labels,
                            int region_count, float *out, size_t rows,
                            size_t cols);
void relief_clean_layers(const float *depth, float *out, size_t rows,
                         size_t cols);
void relief_suppress_background(const float *depth, float *out, size_t rows,
                                size_t cols, double percentile);

/// `io_utils.normalize01` -- rescale to [0, 1], zeros for constant input.
void relief_normalize01(const float *in, float *out, size_t n, int robust);

/// `skimage.segmentation.find_boundaries(labels, mode='outer')`, background=0.
void relief_find_boundaries_outer(const int32_t *labels, uint8_t *out,
                                  size_t rows, size_t cols);

/// Z_rough (paper section 2.3.2) -- inflate every labelled region within its
/// own outline. `foreground` may be null.
void relief_inflate(const int32_t *labels, const uint8_t *foreground, float *out,
                    size_t rows, size_t cols, int iters, int kernel);

/// Z_detail, paper Eq. (18-20) -- Prewitt gradient magnitude of the
/// albedo-normalized brightness, robustly normalized.
void relief_detail_gradient(const float *brightness, float *out, size_t rows,
                            size_t cols);

/// Poisson integration via DCT-II. `cv::dct` matches
/// `scipy.fft.dct(type=2, norm='ortho')` exactly.
void relief_poisson_dct(const float *p, const float *q, float *out, size_t rows,
                        size_t cols);
void relief_integrate_normals(const float *normals, const uint8_t *mask,
                              float *out, size_t rows, size_t cols,
                              float max_slope);
/// The red/black SOR solve. Returns the number of sweeps used.
int relief_solve_normals(const float *image, const float *light,
                         const uint8_t *mask, const float *init_height,
                         float *normals_out, size_t rows, size_t cols,
                         float smoothness, int iters, float omega,
                         double mbc_percentile, int project_every,
                         float *residual_out);
/// Apparent light direction from where the highlights sit.
void relief_estimate_light(const float *image, const uint8_t *mask, size_t rows,
                           size_t cols, float elevation, float *out_vector,
                           float *out_confidence);
/// Z_main -- the full shape-from-shading solve, downscaled and re-upscaled.
void relief_shape_from_shading(const float *image, const float *light,
                               const uint8_t *mask, const float *init_height,
                               float *out, size_t rows, size_t cols,
                               float smoothness, int iters, float omega,
                               double mbc_percentile, int scale,
                               int project_every);

/// Stage 6 -- height field to watertight solid.
int relief_resample_height(const float *height, size_t rows, size_t cols,
                           int max_grid, float *out, size_t *out_rows,
                           size_t *out_cols);
size_t relief_perimeter_count(size_t rows, size_t cols);
/// Buffer sizes for `relief_solidify`, which are analytic in the grid size.
void relief_solid_counts(size_t rows, size_t cols, size_t *vertex_count,
                         size_t *face_count);
void relief_solidify(const float *grid, size_t rows, size_t cols,
                     double plate_w, double plate_h, double base_mm,
                     double relief_mm, double *vertices, int32_t *faces);
double relief_mesh_volume(const double *vertices, const int32_t *faces,
                          size_t face_count);
/// `trimesh.fix_normals()` -- make winding consistent, then orient outward.
/// `_solidify`'s raw output is not consistently wound; without this every
/// volume and watertightness measurement is wrong.
void relief_fix_normals(const double *vertices, int32_t *faces,
                        size_t face_count, size_t vertex_count);
/// Every edge shared by exactly two faces.
int relief_mesh_is_watertight(const int32_t *faces, size_t face_count);

/// Quadric edge-collapse decimation. Returns the resulting face count and
/// writes the vertex count through `out_vertex_count`. Buffers must be sized
/// for the *input* mesh; the result is never larger.
size_t relief_decimate(const double *vertices, const int32_t *faces,
                       size_t vertex_count, size_t face_count,
                       size_t target_faces, double aggressiveness,
                       double *out_vertices, int32_t *out_faces,
                       size_t *out_vertex_count);

/// Interleaved multi-channel bicubic resize matching PyTorch's
/// `F.interpolate(mode="bicubic", align_corners=False)`. Used for DINOv2's
/// position-embedding grid, which the Core ML graph no longer computes.
void relief_resize_bicubic_channels(const float *src, float *dst, int src_h,
                                    int src_w, int dst_h, int dst_w,
                                    int channels);

/// `DPTImageProcessor` preprocessing: PIL bicubic resize, rescale, ImageNet
/// normalisation. Writes CHW float32 ready for the Core ML model.
void relief_dpt_preprocess(const float *rgb, size_t rows, size_t cols,
                           int out_h, int out_w, float *out);

/// Link-and-run check for the vendored OpenCV: exercises `cv::CLAHE` on 16-bit,
/// `cv::ximgproc::guidedFilter` and `cv::distanceTransform(DIST_L2, 5)`.
/// Returns 0 on success, or the index of the first check that failed.
int relief_opencv_selftest(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RELIEF_NUMERICS_H

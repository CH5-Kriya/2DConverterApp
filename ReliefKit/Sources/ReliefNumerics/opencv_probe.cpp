// Smoke test that the vendored framework really provides the two functions the
// whole strategy rests on. If either of these fails to link, the plan's §2
// premise -- that the port can *call* the reference implementation rather than
// reimplement it -- is false, and that should surface here rather than three
// stages later.

#include "relief_numerics.h"

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/ximgproc/edge_filter.hpp>

int relief_opencv_selftest(void) {
    // cv::CLAHE, applied to 16-bit as stage 1 does. 8-bit would let
    // quantization resurface as banding in stage 4.
    cv::Mat gray16(32, 32, CV_16UC1, cv::Scalar(0));
    for (int r = 0; r < gray16.rows; ++r)
        for (int c = 0; c < gray16.cols; ++c)
            gray16.at<uint16_t>(r, c) = static_cast<uint16_t>((r * 32 + c) * 60);
    cv::Ptr<cv::CLAHE> clahe = cv::createCLAHE(2.0, cv::Size(8, 8));
    cv::Mat equalized;
    clahe->apply(gray16, equalized);
    if (equalized.size() != gray16.size()) return 1;

    // cv::ximgproc::guidedFilter -- the contrib symbol most likely to be
    // missing from a mis-built framework.
    cv::Mat guide(32, 32, CV_32FC1, cv::Scalar(0.5f));
    cv::Mat src(32, 32, CV_32FC1, cv::Scalar(0.25f));
    cv::Mat filtered;
    cv::ximgproc::guidedFilter(guide, src, filtered, 8, 1e-4);
    if (filtered.size() != src.size()) return 2;

    // cv::distanceTransform with the 5x5 mask -- Z_rough depends on this exact
    // approximation, octagonal-dome artefact and all.
    cv::Mat binary(32, 32, CV_8UC1, cv::Scalar(255));
    cv::Mat dist;
    cv::distanceTransform(binary, dist, cv::DIST_L2, 5);
    if (dist.size() != binary.size()) return 3;

    return 0;
}

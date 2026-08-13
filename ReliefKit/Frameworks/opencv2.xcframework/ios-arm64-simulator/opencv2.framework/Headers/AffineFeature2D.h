//
// This file is auto-generated. Please don't modify it!
//
#pragma once

#ifdef __cplusplus
//#import "opencv.hpp"
#import "opencv2/xfeatures2d.hpp"
#else
#define CV_EXPORTS
#endif

#import <Foundation/Foundation.h>
#import "Feature2D.h"





NS_ASSUME_NONNULL_BEGIN

// C++: class AffineFeature2D
/**
 * Class implementing affine adaptation for key points.
 *
 * A *Ref:* FeatureDetector and a *Ref:* DescriptorExtractor are wrapped to augment the
 * detected points with their affine invariant elliptic region and to compute
 * the feature descriptors on the regions after warping them into circles.
 *
 * The interface is equivalent to *Ref:* Feature2D, adding operations for
 * *Ref:* Elliptic_KeyPoint "Elliptic_KeyPoints" instead of *Ref:* KeyPoint "KeyPoints".
 *
 * Member of `Xfeatures2d`
 */
CV_EXPORTS @interface AffineFeature2D : Feature2D


#ifdef __cplusplus
@property(readonly)cv::Ptr<cv::xfeatures2d::AffineFeature2D> nativePtrAffineFeature2D;
#endif

#ifdef __cplusplus
- (instancetype)initWithNativePtr:(cv::Ptr<cv::xfeatures2d::AffineFeature2D>)nativePtr;
+ (instancetype)fromNative:(cv::Ptr<cv::xfeatures2d::AffineFeature2D>)nativePtr;
#endif


#pragma mark - Methods



@end

NS_ASSUME_NONNULL_END



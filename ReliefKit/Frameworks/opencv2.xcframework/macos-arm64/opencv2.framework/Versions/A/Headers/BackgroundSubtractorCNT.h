//
// This file is auto-generated. Please don't modify it!
//
#pragma once

#ifdef __cplusplus
//#import "opencv.hpp"
#import "opencv2/bgsegm.hpp"
#else
#define CV_EXPORTS
#endif

#import <Foundation/Foundation.h>
#import "BackgroundSubtractor.h"

@class Mat;



NS_ASSUME_NONNULL_BEGIN

// C++: class BackgroundSubtractorCNT
/**
 * Background subtraction based on counting.
 *
 *   About as fast as MOG2 on a high end system.
 *   More than twice faster than MOG2 on cheap hardware (benchmarked on Raspberry Pi3).
 *
 *   %Algorithm by Sagi Zeevi ( https://github.com/sagi-z/BackgroundSubtractorCNT )
 *
 * Member of `Bgsegm`
 */
CV_EXPORTS @interface BackgroundSubtractorCNT : BackgroundSubtractor


#ifdef __cplusplus
@property(readonly)cv::Ptr<cv::bgsegm::BackgroundSubtractorCNT> nativePtrBackgroundSubtractorCNT;
#endif

#ifdef __cplusplus
- (instancetype)initWithNativePtr:(cv::Ptr<cv::bgsegm::BackgroundSubtractorCNT>)nativePtr;
+ (instancetype)fromNative:(cv::Ptr<cv::bgsegm::BackgroundSubtractorCNT>)nativePtr;
#endif


#pragma mark - Methods


//
//  void cv::bgsegm::BackgroundSubtractorCNT::apply(Mat image, Mat& fgmask, double learningRate = -1)
//
- (void)apply:(Mat*)image fgmask:(Mat*)fgmask learningRate:(double)learningRate NS_SWIFT_NAME(apply(image:fgmask:learningRate:));

- (void)apply:(Mat*)image fgmask:(Mat*)fgmask NS_SWIFT_NAME(apply(image:fgmask:));


//
//  void cv::bgsegm::BackgroundSubtractorCNT::apply(Mat image, Mat knownForegroundMask, Mat& fgmask, double learningRate = -1)
//
/**
 * Computes a foreground mask with known foreground mask input.
 *
 * @param image Next video frame.
 * @param knownForegroundMask The mask for inputting already known foreground.
 * @param fgmask The output foreground mask as an 8-bit binary image.
 * @param learningRate The value between 0 and 1 that indicates how fast the background model is
 *     learnt. Negative parameter value makes the algorithm to use some automatically chosen learning
 *     rate. 0 means that the background model is not updated at all, 1 means that the background model
 *     is completely reinitialized from the last frame.
 *
 * Note:* This method has a default virtual implementation that throws a "not impemented" error.
 *     Foreground masking may not be supported by all background subtractors.
 */
- (void)apply:(Mat*)image knownForegroundMask:(Mat*)knownForegroundMask fgmask:(Mat*)fgmask learningRate:(double)learningRate NS_SWIFT_NAME(apply(image:knownForegroundMask:fgmask:learningRate:));

/**
 * Computes a foreground mask with known foreground mask input.
 *
 * @param image Next video frame.
 * @param knownForegroundMask The mask for inputting already known foreground.
 * @param fgmask The output foreground mask as an 8-bit binary image.
 *     learnt. Negative parameter value makes the algorithm to use some automatically chosen learning
 *     rate. 0 means that the background model is not updated at all, 1 means that the background model
 *     is completely reinitialized from the last frame.
 *
 * Note:* This method has a default virtual implementation that throws a "not impemented" error.
 *     Foreground masking may not be supported by all background subtractors.
 */
- (void)apply:(Mat*)image knownForegroundMask:(Mat*)knownForegroundMask fgmask:(Mat*)fgmask NS_SWIFT_NAME(apply(image:knownForegroundMask:fgmask:));


//
//  void cv::bgsegm::BackgroundSubtractorCNT::getBackgroundImage(Mat& backgroundImage)
//
- (void)getBackgroundImage:(Mat*)backgroundImage NS_SWIFT_NAME(getBackgroundImage(backgroundImage:));


//
//  int cv::bgsegm::BackgroundSubtractorCNT::getMinPixelStability()
//
/**
 * Returns number of frames with same pixel color to consider stable.
 */
- (int)getMinPixelStability NS_SWIFT_NAME(getMinPixelStability());


//
//  void cv::bgsegm::BackgroundSubtractorCNT::setMinPixelStability(int value)
//
/**
 * Sets the number of frames with same pixel color to consider stable.
 */
- (void)setMinPixelStability:(int)value NS_SWIFT_NAME(setMinPixelStability(value:));


//
//  int cv::bgsegm::BackgroundSubtractorCNT::getMaxPixelStability()
//
/**
 * Returns maximum allowed credit for a pixel in history.
 */
- (int)getMaxPixelStability NS_SWIFT_NAME(getMaxPixelStability());


//
//  void cv::bgsegm::BackgroundSubtractorCNT::setMaxPixelStability(int value)
//
/**
 * Sets the maximum allowed credit for a pixel in history.
 */
- (void)setMaxPixelStability:(int)value NS_SWIFT_NAME(setMaxPixelStability(value:));


//
//  bool cv::bgsegm::BackgroundSubtractorCNT::getUseHistory()
//
/**
 * Returns if we're giving a pixel credit for being stable for a long time.
 */
- (BOOL)getUseHistory NS_SWIFT_NAME(getUseHistory());


//
//  void cv::bgsegm::BackgroundSubtractorCNT::setUseHistory(bool value)
//
/**
 * Sets if we're giving a pixel credit for being stable for a long time.
 */
- (void)setUseHistory:(BOOL)value NS_SWIFT_NAME(setUseHistory(value:));


//
//  bool cv::bgsegm::BackgroundSubtractorCNT::getIsParallel()
//
/**
 * Returns if we're parallelizing the algorithm.
 */
- (BOOL)getIsParallel NS_SWIFT_NAME(getIsParallel());


//
//  void cv::bgsegm::BackgroundSubtractorCNT::setIsParallel(bool value)
//
/**
 * Sets if we're parallelizing the algorithm.
 */
- (void)setIsParallel:(BOOL)value NS_SWIFT_NAME(setIsParallel(value:));



@end

NS_ASSUME_NONNULL_END



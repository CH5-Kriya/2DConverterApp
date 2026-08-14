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

// C++: class BackgroundSubtractorMOG
/**
 * Gaussian Mixture-based Background/Foreground Segmentation Algorithm.
 *
 * The class implements the algorithm described in *Cite:* KB2001 .
 *
 * Member of `Bgsegm`
 */
CV_EXPORTS @interface BackgroundSubtractorMOG : BackgroundSubtractor


#ifdef __cplusplus
@property(readonly)cv::Ptr<cv::bgsegm::BackgroundSubtractorMOG> nativePtrBackgroundSubtractorMOG;
#endif

#ifdef __cplusplus
- (instancetype)initWithNativePtr:(cv::Ptr<cv::bgsegm::BackgroundSubtractorMOG>)nativePtr;
+ (instancetype)fromNative:(cv::Ptr<cv::bgsegm::BackgroundSubtractorMOG>)nativePtr;
#endif


#pragma mark - Methods


//
//  void cv::bgsegm::BackgroundSubtractorMOG::apply(Mat image, Mat& fgmask, double learningRate = -1)
//
/**
 * Computes a foreground mask.
 *
 * @param image Next video frame of type CV_8UC(n),CV_8SC(n),CV_16UC(n),CV_16SC(n),CV_32SC(n),CV_32FC(n),CV_64FC(n), where n is 1,2,3,4.
 * @param fgmask The output foreground mask as an 8-bit binary image.
 * @param learningRate The value between 0 and 1 that indicates how fast the background model is
 *     learnt. Negative parameter value makes the algorithm to use some automatically chosen learning
 *     rate. 0 means that the background model is not updated at all, 1 means that the background model
 *     is completely reinitialized from the last frame.
 */
- (void)apply:(Mat*)image fgmask:(Mat*)fgmask learningRate:(double)learningRate NS_SWIFT_NAME(apply(image:fgmask:learningRate:));

/**
 * Computes a foreground mask.
 *
 * @param image Next video frame of type CV_8UC(n),CV_8SC(n),CV_16UC(n),CV_16SC(n),CV_32SC(n),CV_32FC(n),CV_64FC(n), where n is 1,2,3,4.
 * @param fgmask The output foreground mask as an 8-bit binary image.
 *     learnt. Negative parameter value makes the algorithm to use some automatically chosen learning
 *     rate. 0 means that the background model is not updated at all, 1 means that the background model
 *     is completely reinitialized from the last frame.
 */
- (void)apply:(Mat*)image fgmask:(Mat*)fgmask NS_SWIFT_NAME(apply(image:fgmask:));


//
//  void cv::bgsegm::BackgroundSubtractorMOG::apply(Mat image, Mat knownForegroundMask, Mat& fgmask, double learningRate = -1)
//
/**
 * Computes a foreground mask and skips known foreground in evaluation.
 *
 * @param image Next video frame of type CV_8UC(n),CV_8SC(n),CV_16UC(n),CV_16SC(n),CV_32SC(n),CV_32FC(n),CV_64FC(n), where n is 1,2,3,4.
 * @param fgmask The output foreground mask as an 8-bit binary image.
 * @param knownForegroundMask The mask for inputting already known foreground, allows model to ignore learning known pixels.
 * @param learningRate The value between 0 and 1 that indicates how fast the background model is
 *     learnt. Negative parameter value makes the algorithm to use some automatically chosen learning
 *     rate. 0 means that the background model is not updated at all, 1 means that the background model
 *     is completely reinitialized from the last frame.
 */
- (void)apply:(Mat*)image knownForegroundMask:(Mat*)knownForegroundMask fgmask:(Mat*)fgmask learningRate:(double)learningRate NS_SWIFT_NAME(apply(image:knownForegroundMask:fgmask:learningRate:));

/**
 * Computes a foreground mask and skips known foreground in evaluation.
 *
 * @param image Next video frame of type CV_8UC(n),CV_8SC(n),CV_16UC(n),CV_16SC(n),CV_32SC(n),CV_32FC(n),CV_64FC(n), where n is 1,2,3,4.
 * @param fgmask The output foreground mask as an 8-bit binary image.
 * @param knownForegroundMask The mask for inputting already known foreground, allows model to ignore learning known pixels.
 *     learnt. Negative parameter value makes the algorithm to use some automatically chosen learning
 *     rate. 0 means that the background model is not updated at all, 1 means that the background model
 *     is completely reinitialized from the last frame.
 */
- (void)apply:(Mat*)image knownForegroundMask:(Mat*)knownForegroundMask fgmask:(Mat*)fgmask NS_SWIFT_NAME(apply(image:knownForegroundMask:fgmask:));


//
//  int cv::bgsegm::BackgroundSubtractorMOG::getHistory()
//
- (int)getHistory NS_SWIFT_NAME(getHistory());


//
//  void cv::bgsegm::BackgroundSubtractorMOG::setHistory(int nframes)
//
- (void)setHistory:(int)nframes NS_SWIFT_NAME(setHistory(nframes:));


//
//  int cv::bgsegm::BackgroundSubtractorMOG::getNMixtures()
//
- (int)getNMixtures NS_SWIFT_NAME(getNMixtures());


//
//  void cv::bgsegm::BackgroundSubtractorMOG::setNMixtures(int nmix)
//
- (void)setNMixtures:(int)nmix NS_SWIFT_NAME(setNMixtures(nmix:));


//
//  double cv::bgsegm::BackgroundSubtractorMOG::getBackgroundRatio()
//
- (double)getBackgroundRatio NS_SWIFT_NAME(getBackgroundRatio());


//
//  void cv::bgsegm::BackgroundSubtractorMOG::setBackgroundRatio(double backgroundRatio)
//
- (void)setBackgroundRatio:(double)backgroundRatio NS_SWIFT_NAME(setBackgroundRatio(backgroundRatio:));


//
//  double cv::bgsegm::BackgroundSubtractorMOG::getNoiseSigma()
//
- (double)getNoiseSigma NS_SWIFT_NAME(getNoiseSigma());


//
//  void cv::bgsegm::BackgroundSubtractorMOG::setNoiseSigma(double noiseSigma)
//
- (void)setNoiseSigma:(double)noiseSigma NS_SWIFT_NAME(setNoiseSigma(noiseSigma:));



@end

NS_ASSUME_NONNULL_END



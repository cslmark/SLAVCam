//
//  TAVCamera.h
//  SLAVCam
//
//  Created by Iansl on 2019/1/25.
//  Copyright © 2019 Iansl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "TAVCameraDefine.h"
#import "AVCamPreView.h"
#import <UIKit/UIKit.h>

@class TAVCamera;
@protocol TAVCameraDataOuputDelagate <NSObject>
@optional
/// 音频和视频数据推流
- (CMSampleBufferRef)camera:(TAVCamera *)camera processVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (CMSampleBufferRef)camera:(TAVCamera *)camera processAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end

@protocol TAVCameraRecordDelagate <NSObject>
@optional
/// 当录制开始，结束，失败，接收到一帧的sampleBuffer，完成将会使用该协议通知使用者
- (void)camera:(TAVCamera *)camera didStartRecordingInFileUrl:(NSURL *)fileUrl;
- (void)camera:(TAVCamera *)camera didStopRecordingWithSegmentsUrls:(NSArray<NSURL *> *) fileUrls;
- (void)camera:(TAVCamera *)camera didFailRecordingWithError:(NSError *)error;
- (void)cameraDidReceiveVideoSampleBuffer:(TAVCamera *)camera;
- (void)cameraDidCompleteRecording:(TAVCamera *)camera;
@end

@interface TAVCamera : NSObject
@property (nonatomic, weak) id <TAVCameraRecordDelagate> recordDelegate;
@property (nonatomic, weak) id <TAVCameraDataOuputDelagate> dataDelegate;
@property (nonatomic, assign) TAVCameraTorchMode  torchMode;                    // 补光(手电筒)模式
@property (nonatomic, assign, readonly, getter=isRecording) BOOL Recording;     // 录制状态
@property (nonatomic, assign, readonly) CMTime recordDuration;                  // 录制时长
@property (nonatomic, assign) TAVRecordVideoOrientation captureOrientation;     // 录制方向
@property (nonatomic, assign, readonly) BOOL recordFinished;                    // 录制完成


/// 录制最大时长，如果使用 init方法初始化，录制时长不限制
- (instancetype)initWithMaxPublishDuration:(NSTimeInterval)duration NS_DESIGNATED_INITIALIZER;

/// 预览视图以及视图模式
- (void)setCameraPreview:(AVCamPreView *)cameraPreview;
- (void)setCameraPreviewContenMode:(UIViewContentMode) contentMode;
- (void)setExposureTargetBias:(float)bias;
- (void)changeVideoZoomFactor:(CGFloat)videoZoomFactor;



/// 启动和停止会话(AVCaptureSession)
- (void)startRunning;
- (void)stopRunning;

/// 开始和介绍录制
- (void)startRecording;
- (void)stopRecording;

/// 切换前/后摄像头
- (void)switchCameraPosition;
/// 聚焦
- (void)focusAtPoint:(CGPoint)point;

/// 检查当前摄像头是否具有闪光灯，手电筒
- (BOOL)isFlashAvailable;
- (BOOL)isTorchAvailable;

/// 返回当前设备的前后摄像头是否可用
+ (BOOL)isFrontCameraAvailable;
+ (BOOL)isRearCameraAvailable;

/// 删除所有录制的片段频
- (void)removeAllSegments;
/// 删除最后一段视频
- (void)removeLastSegment;
/// 返回录制所有视频片段的文件地址
- (NSArray<NSString *> *)recordSegmentsFileUrls;
/// 返回一个包含所有录制视频的AVAsset
- (AVAsset *)assetRepresentingSegments;
/// 将上次拍摄好的视频地址传入，恢复多段拍摄
-(void)addSegmentsFromFileUrls:(NSArray<NSString *> *)fileUrls;
@end

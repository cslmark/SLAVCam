//
//  TAVCameraDefine.h
//  TAVCamera
//
//  Created by Iansl on 2019/1/16.
//  Copyright © 2019 Tencent. All rights reserved.
//

#ifndef TAVCameraDefine_h
#define TAVCameraDefine_h

#ifndef DECLARE_WEAK_SELF
#define DECLARE_WEAK_SELF __typeof(&*self) __weak weakSelf = self
#endif

#ifndef DECLARE_STRONG_SELF
#define DECLARE_STRONG_SELF __typeof(&*self) __strong strongSelf = weakSelf;
#endif

#define   CameraLOGEnable   1
#if  CameraLOGEnable
#define CameraLog(...) do{ NSLog(__VA_ARGS__); } while(0)
#else
#define CameraLog(...) do{ } while(0)
#endif

/*  录制方向 */
typedef NS_ENUM(NSInteger, TAVRecordVideoOrientation) {
    TAVRecordVideoOrientationPortrait           = 0, //video should be oriented vertically, home button on the bottom.
    TAVRecordVideoOrientationLandscapeRight     = 1, //video should be oriented horizontally, home button on the right.
    TAVRecordVideoOrientationLandscapeLeft      = 2, //video should be oriented horizontally, home button on the left.
};

/*  补光灯开关 */
typedef NS_ENUM(NSUInteger,TAVCameraTorchMode) {
    TAVCameraTorchModeOff,
    TAVCameraTorchModeOn,
    TAVCameraTorchModeAuto
};

/*  美颜选项 */
typedef NS_ENUM(NSUInteger, TAVBeautyConfigViewConfigType) {
    TAVBeautyConfigViewConfigTypeBeauty,
    TAVBeautyConfigViewConfigTypeBrightness,
    TAVBeautyConfigViewConfigTypeVFace,
    TAVBeautyConfigViewConfigTypeNarrowFace,
    TAVBeautyConfigViewConfigTypeBigEye,
};

/*  录制速度 */
typedef NS_ENUM(NSInteger, TAVRecordPreviewSpeed) {
    TAVRecordPreviewSpeed1_1 = 0,       //默认为正常倍速
    TAVRecordPreviewSpeed1_5,       //1.5倍速
    TAVRecordPreviewSpeed0_5,       //0.5倍速
};

/*  宽高比 */
typedef NS_ENUM(NSInteger, TAVRecordAspectRatio) {
    TAVRecordAspectRatio9_16 = 0,       //默认9:16竖屏
    TAVRecordAspectRatio3_4,       //3:4竖屏
    TAVRecordAspectRatio1_1,       //1:1
    TAVRecordAspectRatio4_3,       //4:3横屏
    TAVRecordAspectRatio16_9,      //16:9倍速
};


#endif /* TAVCameraDefine_h */

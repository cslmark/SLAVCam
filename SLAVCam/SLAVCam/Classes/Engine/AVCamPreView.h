//
//  AVCamPreView.h
//  SLAVCam
//
//  Created by Iansl on 2018/12/3.
//  Copyright © 2018 Iansl. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <AVFoundation/AVCaptureVideoPreviewLayer.h>
#import <UIKit/UIKit.h>


@interface AVCamPreView : UIView
@property (nonatomic, readonly) AVCaptureVideoPreviewLayer* videoPreviewLayer;
@property (nonatomic) AVCaptureSession* session;
@end


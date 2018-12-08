//
//  AVCamPreView.m
//  SLAVCam
//
//  Created by Iansl on 2018/12/3.
//  Copyright © 2018 Iansl. All rights reserved.
//

#import "AVCamPreView.h"



@implementation AVCamPreView

+(Class)layerClass{
    return [AVCaptureVideoPreviewLayer class];
}

-(AVCaptureVideoPreviewLayer *)videoPreviewLayer{
    return (AVCaptureVideoPreviewLayer *)self.layer;
}

-(AVCaptureSession *)session{
    return self.videoPreviewLayer.session;
}

-(void) setSession:(AVCaptureSession *)session{
    self.videoPreviewLayer.session = session;
}

@end

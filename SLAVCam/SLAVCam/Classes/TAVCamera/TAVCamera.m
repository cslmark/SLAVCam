//
//  TAVCamera.m
//  SLAVCam
//
//  Created by Iansl on 2019/1/25.
//  Copyright © 2019 Iansl. All rights reserved.
//

#import "TAVCamera.h"
#import "AVCamPreView.h"

typedef NS_ENUM( NSInteger, AVCamSetupResult ) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};

static void * SessionRunningContext = &SessionRunningContext;

@interface TAVCamera()<AVCaptureVideoDataOutputSampleBufferDelegate>
{
    AVCaptureConnection *_videoConnection;
    CGFloat _videoZoomFactor;
}
@property (nonatomic, assign) CGFloat maxPublishVideoDuration;
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, weak) AVCamPreView *previewView;

@property (nonatomic) AVCamSetupResult setupResult;

// 队列
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) dispatch_queue_t captureQueue;
// 当前的录制方向
@property (readwrite) AVCaptureVideoOrientation videoOrientation;

// 具体的物理设备
@property (nonatomic) AVCaptureDevice *videoDevice;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
// 后台任务
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
// 辅助属性
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;
// 是否自动调节方向
@property (assign, nonatomic) BOOL autoSetVideoOrientation;
@end

@implementation TAVCamera
- (instancetype) init{
    return [self initWithMaxPublishDuration:MAXFLOAT];
}

- (instancetype)initWithMaxPublishDuration:(NSTimeInterval)duration{
    self = [super init];
    if(self) {
        _recordFinished = NO;
        _autoSetVideoOrientation = YES;
        self.maxPublishVideoDuration = duration;
        [self _setUpCamera];
        [self addObservers];
    }
    return self;
}

- (void) dealloc{
    [self removeObservers];
}

-(void)_setUpCamera {
    self.session = [[AVCaptureSession alloc] init];
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    self.captureQueue = dispatch_queue_create( "capture queue", DISPATCH_QUEUE_SERIAL );
    
    switch ( [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] )
    {
        case AVAuthorizationStatusAuthorized:
        {
            break;
        }
        case AVAuthorizationStatusNotDetermined:
        {
            dispatch_suspend( self.sessionQueue );
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^( BOOL granted ) {
                if ( ! granted ) {
                    self.setupResult = AVCamSetupResultCameraNotAuthorized;
                }
                dispatch_resume( self.sessionQueue );
            }];
            break;
        }
        default:
        {
            // The user has previously denied access.
            self.setupResult = AVCamSetupResultCameraNotAuthorized;
            break;
        }
    }
    dispatch_async( self.sessionQueue, ^{
        [self configureSession];
    } );
}

#pragma mark - KVO & Notification
- (void)addObservers
{
    [self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaServicesWereReset:) name:AVAudioSessionMediaServicesWereResetNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaServicesWereLost:) name:AVAudioSessionMediaServicesWereLostNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self  selector:@selector(deviceOrientationChanged:) name:UIDeviceOrientationDidChangeNotification  object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSLog(@"%s", __func__);
    if ( context == SessionRunningContext ) {
        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
        //        BOOL livePhotoCaptureSupported = self.photoOutput.livePhotoCaptureSupported;
        //        BOOL livePhotoCaptureEnabled = self.photoOutput.livePhotoCaptureEnabled;
        //        BOOL depthDataDeliverySupported = self.photoOutput.depthDataDeliverySupported;
        //        BOOL depthDataDeliveryEnabled = self.photoOutput.depthDataDeliveryEnabled;
        
        dispatch_async( dispatch_get_main_queue(), ^{
            // Only enable the ability to change camera if the device has more than one camera.
            //            self.cameraButton.enabled = isSessionRunning && ( self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1 );
//            self.shootBtn.enabled = isSessionRunning;
            //            self.photoButton.enabled = isSessionRunning;
            //            self.captureModeControl.enabled = isSessionRunning;
            //            self.livePhotoModeButton.enabled = isSessionRunning && livePhotoCaptureEnabled;
            //            self.livePhotoModeButton.hidden = ! ( isSessionRunning && livePhotoCaptureSupported );
            //            self.depthDataDeliveryButton.enabled = isSessionRunning && depthDataDeliveryEnabled ;
            //            self.depthDataDeliveryButton.hidden = ! ( isSessionRunning && depthDataDeliverySupported );
        } );
    }
    else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)subjectAreaDidChange:(NSNotification *)notification
{
    NSLog(@"失去焦点的时候 自动往中部聚焦 %s", __func__);
    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
    NSLog(@"%s", __func__);
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    NSLog( @"Capture session runtime error: %@", error );
    
    /*
     Automatically try to restart the session running if media services were
     reset and the last start running succeeded. Otherwise, enable the user
     to try to resume the session running.
     */
    if ( error.code == AVErrorMediaServicesWereReset ) {
        dispatch_async( self.sessionQueue, ^{
            if ( self.isSessionRunning ) {
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
            }
            else {
                dispatch_async( dispatch_get_main_queue(), ^{
                    //                    self.resumeButton.hidden = NO;
                } );
            }
        } );
    }
    else {
        //        self.resumeButton.hidden = NO;
    }
}

- (void)sessionWasInterrupted:(NSNotification *)notification
{
    NSLog(@"%s", __func__);
    BOOL showResumeButton = NO;
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
    
    if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
        reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
        showResumeButton = YES;
    }
    else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
        
    }
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog(@"%s", __func__);
    NSLog( @"Capture session interruption ended" );
}

- (void)mediaServicesWereReset:(NSNotification *)notification {
    NSLog(@"MEDIA SERVICES WERE RESET");
}

- (void)mediaServicesWereLost:(NSNotification *)notification {
    NSLog(@"MEDIA SERVICES WERE LOST");
}

- (void)deviceOrientationChanged:(id)sender {
    if (_autoSetVideoOrientation) {
        dispatch_sync(self.sessionQueue, ^{
            [self updateVideoOrientation];
        });
    }
}

- (void)applicationDidEnterBackground:(id)sender {
    [self pause];
}

- (void)applicationDidBecomeActive:(id)sender {
   
}


#pragma mark ================   Private Method  ================
- (void)configureSession
{
    if ( self.setupResult != AVCamSetupResultSuccess ) {
        return;
    }
    NSError *error = nil;
    [self.session beginConfiguration];
    self.session.sessionPreset = AVCaptureSessionPresetHigh;
    
    AVCaptureDevice *videoDevice = nil;
    if (@available(iOS 10.2, *)) {
        videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        if ( ! videoDevice ) {
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
            if ( ! videoDevice ) {
                videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
            }
        }
    } else {
        videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    self.videoDevice = videoDevice;
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if ( ! videoDeviceInput ) {
        NSLog( @"Could not create video device input: %@", error );
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    if ( [self.session canAddInput:videoDeviceInput] ) {
        [self.session addInput:videoDeviceInput];
        self.videoDeviceInput = videoDeviceInput;
    }
    else {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    // Add audio input.
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&error];
    if ( ! audioDeviceInput ) {
        NSLog( @"Could not create audio device input: %@", error );
    }
    if ( [self.session canAddInput:audioDeviceInput] ) {
        [self.session addInput:audioDeviceInput];
    }
    else {
        NSLog( @"Could not add audio device input to the session" );
    }
    
    // Add Data Output For Beauty
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    if ([self.session canAddOutput:_videoOutput]) {
        [self.session addOutput:_videoOutput];
        [_videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                                   forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        [_videoOutput setSampleBufferDelegate:self queue:self.captureQueue];
        [_videoOutput setAlwaysDiscardsLateVideoFrames:YES];
        
        _videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
        self.videoOrientation = _videoConnection.videoOrientation;
    } else {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    [self.session commitConfiguration];
}

- (void)updateVideoOrientation {
    AVCaptureVideoOrientation videoOrientation = [self actualVideoOrientation];
    AVCaptureConnection *videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    
    if ([videoConnection isVideoOrientationSupported]) {
        videoConnection.videoOrientation = videoOrientation;
    }
    if([self.previewView.videoPreviewLayer.connection isVideoOrientationSupported]){
        self.previewView.videoPreviewLayer.connection.videoOrientation = videoOrientation;
    }
    
    AVCaptureConnection *movieOutputConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (movieOutputConnection.isVideoOrientationSupported) {
        movieOutputConnection.videoOrientation = videoOrientation;
    }
}

- (AVCaptureVideoOrientation)actualVideoOrientation {
    AVCaptureVideoOrientation videoOrientation = _videoOrientation;
    if (_autoSetVideoOrientation) {
        UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
        switch (deviceOrientation) {
            case UIDeviceOrientationLandscapeLeft:
                videoOrientation = AVCaptureVideoOrientationLandscapeRight;
                break;
            case UIDeviceOrientationLandscapeRight:
                videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
                break;
            case UIDeviceOrientationPortrait:
                videoOrientation = AVCaptureVideoOrientationPortrait;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
                break;
            default:
                break;
        }
    }
    return videoOrientation;
}

- (void)pause {
    [self pause:nil];
}

- (void)pause:(void(^)(void))completionHandler {
    
}

- (void)reconfigureVideoInput:(BOOL)shouldConfigureVideo audioInput:(BOOL)shouldConfigureAudio {
    
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    if (output == _videoOutput) {

    }
}

#pragma mark ================   Private Mothod    ================
- (void)focusWithMode:(AVCaptureFocusMode)focusMode exposeWithMode:(AVCaptureExposureMode)exposureMode atDevicePoint:(CGPoint)point monitorSubjectAreaChange:(BOOL)monitorSubjectAreaChange
{
    dispatch_async( self.sessionQueue, ^{
        AVCaptureDevice *device = self.videoDeviceInput.device;
        NSError *error = nil;
        if ( [device lockForConfiguration:&error] ) {
            /*
             Setting (focus/exposure)PointOfInterest alone does not initiate a (focus/exposure) operation.
             Call set(Focus/Exposure)Mode() to apply the new point of interest.
             */
            if ( device.isFocusPointOfInterestSupported && [device isFocusModeSupported:focusMode] ) {
                device.focusPointOfInterest = point;
                device.focusMode = focusMode;
            }
            
            if ( device.isExposurePointOfInterestSupported && [device isExposureModeSupported:exposureMode] ) {
                device.exposurePointOfInterest = point;
                device.exposureMode = exposureMode;
            }
            
            device.subjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange;
            [device unlockForConfiguration];
        }
        else {
            NSLog( @"Could not lock device for configuration: %@", error );
        }
    } );
}

#pragma mark ================   Public Method    ================
- (void)startRunning{
    dispatch_async(self.sessionQueue, ^{
        if(self.session && !self.session.isRunning) {
            [self.session startRunning];
            self.sessionRunning = self.session.isRunning;
        }
    });
}

- (void)stopRunning{
    dispatch_async(self.sessionQueue, ^{
        if(self.session) {
            [self.session stopRunning];
            self.sessionRunning = self.session.isRunning;
        }
    });
}

- (void)setCameraPreview:(AVCamPreView *)cameraPreview{
    dispatch_async( dispatch_get_main_queue(), ^{
        self.previewView  = cameraPreview;
        UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
        AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
        if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
            initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
        }
        self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
        self.previewView.session = self.session;
    } );
}

- (void)setCameraPreviewContenMode:(UIViewContentMode) contentMode{
    
}

- (void) switchCameraPosition{
    dispatch_async(self.sessionQueue, ^{
        AVCaptureDevice* currentVideoDevice = self.videoDeviceInput.device;
        AVCaptureDevicePosition currentPosition = currentVideoDevice.position;
        
        AVCaptureDevicePosition preferredPosition;
        //        AVCaptureDeviceType preferredDeviceType;
        
        switch (currentPosition) {
            case AVCaptureDevicePositionUnspecified:
            case AVCaptureDevicePositionFront:
                preferredPosition = AVCaptureDevicePositionBack;
                //                preferredDeviceType = AVCaptureDeviceTypeBuiltInDualCamera;
                break;
            case AVCaptureDevicePositionBack:
                preferredPosition = AVCaptureDevicePositionFront;
                //                preferredDeviceType = AVCaptureDeviceTypeBuiltInWideAngleCamera;
                break;
        }
        
        NSArray<AVCaptureDevice *> *devices;
        if(@available(iOS 10.2, *)) {
            NSArray<AVCaptureDeviceType> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera];
            AVCaptureDeviceDiscoverySession* videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
            devices = videoDeviceDiscoverySession.devices;
        } else {
            devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        }
        AVCaptureDevice *newVideoDevice = nil;
        
        // First, look for a device with both the preferred position and device type.
        //        for ( AVCaptureDevice *device in devices ) {
        //            if ( device.position == preferredPosition && [device.deviceType isEqualToString:preferredDeviceType] ) {
        //                newVideoDevice = device;
        //                break;
        //            }
        //        }
        
        // Otherwise, look for a device with only the preferred position.
        if ( ! newVideoDevice ) {
            for ( AVCaptureDevice *device in devices ) {
                if ( device.position == preferredPosition ) {
                    newVideoDevice = device;
                    break;
                }
            }
        }
        
        if ( newVideoDevice ) {
            AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:newVideoDevice error:NULL];
            
            [self.session beginConfiguration];
            [self.session removeInput:self.videoDeviceInput];
            
            if ( [self.session canAddInput:videoDeviceInput] ) {
                [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:currentVideoDevice];
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:newVideoDevice];
                
                [self.session addInput:videoDeviceInput];
                self.videoDeviceInput = videoDeviceInput;
            }
            else {
                [self.session addInput:self.videoDeviceInput];
            }
            [self.session commitConfiguration];
        }
    });
}

- (void)setTorchMode:(TAVCameraTorchMode)torchMode{
    if([self.videoDevice hasTorch]) {
        [self.videoDevice lockForConfiguration:nil];
        if(torchMode == TAVCameraTorchModeOff) {
            [self.videoDevice setTorchMode:AVCaptureTorchModeOn];
        }
        if(torchMode == TAVCameraTorchModeOn){
            [self.videoDevice setTorchMode:AVCaptureTorchModeOff];
        }
        [self.videoDevice unlockForConfiguration];
    }
}

// bias取值返回 0 - 1
- (void)setExposureTargetBias:(float)bias
{
    if(bias < 0.0 || bias > 1.0){
        return;
    }
    float maxExposureTargetBias  = self.videoDevice.maxExposureTargetBias;
    float minExposureTargetBias  = self.videoDevice.minExposureTargetBias;
    float setBias = (maxExposureTargetBias - minExposureTargetBias) * bias + minExposureTargetBias;
    NSLog(@"bias[%lf]  setBias[%lf] maxExposureTargetBias[%lf] minExposureTargetBias[%lf]", bias, setBias, maxExposureTargetBias, minExposureTargetBias);
    dispatch_async(self.sessionQueue, ^{
        [self.videoDevice lockForConfiguration:nil];
        [self.videoDevice setExposureTargetBias:setBias completionHandler:^(CMTime syncTime) {
            
        }];
        [self.videoDevice unlockForConfiguration];
    });
}

- (BOOL)cameraSupportsZoom
{
    return (self.videoDevice.activeFormat.videoMaxZoomFactor > 1.0);
}


//视频缩放
- (void)changeVideoZoomFactor:(CGFloat)videoZoomFactor
{
    if (_videoZoomFactor == videoZoomFactor) {
        return;
    }else{
        _videoZoomFactor = videoZoomFactor;
    }
    if (![self cameraSupportsZoom]) {
        return;
    }
    
    AVCaptureDevice *device = self.videoDevice;
    if ([device respondsToSelector:@selector(videoZoomFactor)]) {
        NSError *error;
        if ([device lockForConfiguration:&error]) {
            if (videoZoomFactor <= device.activeFormat.videoMaxZoomFactor && videoZoomFactor >= 1.0) {
                device.videoZoomFactor = videoZoomFactor;
            } else {
                NSLog(@"Unable to set videoZoom: (max %f, asked %f)", device.activeFormat.videoMaxZoomFactor, videoZoomFactor);
            }
            
            [device unlockForConfiguration];
        } else {
            NSLog(@"Unable to set videoZoom: %@", error.localizedDescription);
        }
    }
}

- (void)focusAtPoint:(CGPoint)point{
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:point monitorSubjectAreaChange:YES];
}

- (BOOL)isFlashAvailable {
    return [self.videoDevice hasFlash];
}

- (BOOL)isTorchAvailable {
    return [self.videoDevice hasTorch];
}

+ (BOOL)isFrontCameraAvailable{
    if(@available(iOS 10.2, *)) {
        NSArray<AVCaptureDeviceType> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera];
        AVCaptureDeviceDiscoverySession* videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
        NSArray<AVCaptureDevice *> *devices = videoDeviceDiscoverySession.devices;
        for ( AVCaptureDevice *device in devices ) {
            if ( device.position == AVCaptureDevicePositionFront ) {
                return YES;
            }
        }
    } else {
        NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in videoDevices)
            if (device.position == AVCaptureDevicePositionFront) return YES;
    }
    return NO;
}

+ (BOOL)isRearCameraAvailable{
    if(@available(iOS 10.2, *)) {
        NSArray<AVCaptureDeviceType> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera];
        AVCaptureDeviceDiscoverySession* videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
        NSArray<AVCaptureDevice *> *devices = videoDeviceDiscoverySession.devices;
        for ( AVCaptureDevice *device in devices ) {
            if ( device.position == AVCaptureDevicePositionBack ) {
                return YES;
            }
        }
    } else {
        NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
        for (AVCaptureDevice *device in videoDevices)
            if (device.position == AVCaptureDevicePositionBack) return YES;
    }
    return NO;
}

@end

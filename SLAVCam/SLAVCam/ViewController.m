//
//  ViewController.m
//  SLAVCam
//
//  Created by Iansl on 2018/11/30.
//  Copyright © 2018 Iansl. All rights reserved.
//

#import "ViewController.h"
#import <Masonry/Masonry.h>
#import <Photos/Photos.h>
#import "AVCamPreView.h"
#import "SLUICommon.h"

typedef NS_ENUM( NSInteger, AVCamSetupResult ) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};
static void * SessionRunningContext = &SessionRunningContext;

API_AVAILABLE(ios(10.0))
@interface ViewController ()<AVCaptureFileOutputRecordingDelegate>
@property (nonatomic, weak) AVCamPreView *previewView;
@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;   // Available 10.2
@property (nonatomic, strong) UIImageView *focusView;//对焦框

// 具体的物理设备
@property (nonatomic) AVCaptureDevice *videoDevice;

// 四个要素<Connection 需要的时候创建>
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic, strong) AVCaptureConnection *movieFileOutputConnection;

// 辅助属性
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;

// 队列
@property (nonatomic) dispatch_queue_t sessionQueue;

// 后台任务
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@end

@implementation ViewController

#pragma mark ================   Life Cycle    ================
- (void)viewDidLoad {
    [super viewDidLoad];
    [self regiseterNotification];
    [self setupUI];
    [self setupUIDevice];
}

-(void) viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    dispatch_async(self.sessionQueue, ^{
        switch ( self.setupResult )
        {
            case AVCamSetupResultSuccess:
            {
                // Only setup observers and start the session running if setup succeeded.
                [self addObservers];
                [self.session startRunning];
                self.sessionRunning = self.session.isRunning;
                break;
            }
            case AVCamSetupResultCameraNotAuthorized:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"AVCam doesn't have permission to use the camera, please change privacy settings", @"Alert message when the user has denied access to the camera" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    // Provide quick access to Settings.
                    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"Settings", @"Alert button to open Settings" ) style:UIAlertActionStyleDefault handler:^( UIAlertAction *action ) {
                        if (@available(iOS 10.0, *)) {
                            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                        } else {
                            // Fallback on earlier versions
                            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
                        }
                    }];
                    [alertController addAction:settingsAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
            case AVCamSetupResultSessionConfigurationFailed:
            {
                dispatch_async( dispatch_get_main_queue(), ^{
                    NSString *message = NSLocalizedString( @"Unable to capture media", @"Alert message when something goes wrong during capture session configuration" );
                    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"AVCam" message:message preferredStyle:UIAlertControllerStyleAlert];
                    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString( @"OK", @"Alert OK button" ) style:UIAlertActionStyleCancel handler:nil];
                    [alertController addAction:cancelAction];
                    [self presentViewController:alertController animated:YES completion:nil];
                } );
                break;
            }
        }
    });
}


-(void)dealloc{
    [self removeObservers];
}

#pragma mark ================   Notification Center && KVO    ================
-(void) regiseterNotification{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appEnternBackGround) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResign) name:UIApplicationWillResignActiveNotification object:nil];
}

-(void) unregisterNotification{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


-(void) appEnternBackGround{
    NSLog(@"===== %s", __func__);
}

-(void) appWillResign{
    NSLog(@"===== %s", __func__);
}

- (void)addObservers
{
    [self.session addObserver:self forKeyPath:@"running" options:NSKeyValueObservingOptionNew context:SessionRunningContext];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.videoDeviceInput.device];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionWasInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
}

- (void)removeObservers
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.session removeObserver:self forKeyPath:@"running" context:SessionRunningContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == SessionRunningContext ) {
//        BOOL isSessionRunning = [change[NSKeyValueChangeNewKey] boolValue];
//        BOOL livePhotoCaptureSupported = self.photoOutput.livePhotoCaptureSupported;
//        BOOL livePhotoCaptureEnabled = self.photoOutput.livePhotoCaptureEnabled;
//        BOOL depthDataDeliverySupported = self.photoOutput.depthDataDeliverySupported;
//        BOOL depthDataDeliveryEnabled = self.photoOutput.depthDataDeliveryEnabled;
        
        dispatch_async( dispatch_get_main_queue(), ^{
            // Only enable the ability to change camera if the device has more than one camera.
//            self.cameraButton.enabled = isSessionRunning && ( self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1 );
//            self.recordButton.enabled = isSessionRunning && ( self.captureModeControl.selectedSegmentIndex == AVCamCaptureModeMovie );
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
//    CGPoint devicePoint = CGPointMake( 0.5, 0.5 );
//    [self focusWithMode:AVCaptureFocusModeContinuousAutoFocus exposeWithMode:AVCaptureExposureModeContinuousAutoExposure atDevicePoint:devicePoint monitorSubjectAreaChange:NO];
}

- (void)sessionRuntimeError:(NSNotification *)notification
{
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
    /*
     In some scenarios we want to enable the user to resume the session running.
     For example, if music playback is initiated via control center while
     using AVCam, then the user can let AVCam resume
     the session running, which will stop music playback. Note that stopping
     music playback in control center will not automatically resume the session
     running. Also note that it is not always possible to resume, see -[resumeInterruptedSession:].
     */
    BOOL showResumeButton = NO;
    
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    NSLog( @"Capture session was interrupted with reason %ld", (long)reason );
    
    if ( reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient ||
        reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient ) {
        showResumeButton = YES;
    }
    else if ( reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps ) {
        // Simply fade-in a label to inform the user that the camera is unavailable.
//        self.cameraUnavailableLabel.alpha = 0.0;
//        self.cameraUnavailableLabel.hidden = NO;
        [UIView animateWithDuration:0.25 animations:^{
//            self.cameraUnavailableLabel.alpha = 1.0;
        }];
    }
    
    if ( showResumeButton ) {
        // Simply fade-in a button to enable the user to try to resume the session running.
//        self.resumeButton.alpha = 0.0;
//        self.resumeButton.hidden = NO;
        [UIView animateWithDuration:0.25 animations:^{
//            self.resumeButton.alpha = 1.0;
        }];
    }
}

- (void)sessionInterruptionEnded:(NSNotification *)notification
{
    NSLog( @"Capture session interruption ended" );
//    if ( ! self.resumeButton.hidden ) {
//        [UIView animateWithDuration:0.25 animations:^{
//            self.resumeButton.alpha = 0.0;
//        } completion:^( BOOL finished ) {
//            self.resumeButton.hidden = YES;
//        }];
//    }
//    if ( ! self.cameraUnavailableLabel.hidden ) {
//        [UIView animateWithDuration:0.25 animations:^{
//            self.cameraUnavailableLabel.alpha = 0.0;
//        } completion:^( BOOL finished ) {
//            self.cameraUnavailableLabel.hidden = YES;
//        }];
//    }
}



#pragma mark ================   Setup UI & Init Data    ================
+ (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets safeAreaInsets;
    if (@available(iOS 11, *)) {
        safeAreaInsets = [UIApplication sharedApplication].keyWindow.safeAreaInsets;
    } else {
        safeAreaInsets = UIEdgeInsetsZero;
    }
    return safeAreaInsets;
}

-(void) setupUI{
    UIView* superView = self.view;
    self.view.backgroundColor = [UIColor blackColor];
    
    CGFloat safeTop = [SLUICommon safeAreaInsets].top;
    CGFloat safeBottom = [SLUICommon safeAreaInsets].bottom;
    
    AVCamPreView* previewView = [[AVCamPreView alloc] init];
    self.previewView = previewView;
    [self.view addSubview:previewView];
    [previewView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.edges.equalTo(superView);
    }];
    
    UIButton* flashButton = [[UIButton alloc] init];
    [flashButton setImage:[UIImage imageNamed:@"publish_light"] forState:UIControlStateSelected];
    [flashButton setImage:[UIImage imageNamed:@"publish_lightoff"]  forState:UIControlStateNormal];
    [self.view addSubview:flashButton];
    [flashButton addTarget:self action:@selector(flashButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    [flashButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(superView).with.offset(q_pt(45.3) + safeTop);
        make.right.equalTo(superView).with.offset(-q_pt(10));
        make.width.mas_equalTo(q_pt(40));
        make.height.mas_equalTo(q_pt(40));
    }];
    
    UIButton* cameralButton = [[UIButton alloc] init];
    [cameralButton setImage:[UIImage imageNamed:@"publish_trans"] forState:UIControlStateNormal];
    [cameralButton addTarget:self action:@selector(changeCameral:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cameralButton];
    [cameralButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(flashButton.mas_bottom).with.offset(q_pt(20));
        make.right.equalTo(superView).with.offset(-q_pt(10));
        make.width.mas_equalTo(q_pt(40));
        make.height.mas_equalTo(q_pt(40));
    }];
 
    UIButton* frameButton = [[UIButton alloc] init];
    [frameButton setImage:[UIImage imageNamed:@"publish_9:16selected"] forState:UIControlStateNormal];
    [self.view addSubview:frameButton];
    [frameButton addTarget:self action:@selector(frameChangeClick:) forControlEvents:UIControlEventTouchUpInside];
    [frameButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(cameralButton.mas_bottom).with.offset(q_pt(20));
        make.right.equalTo(superView).with.offset(-q_pt(10));
        make.width.mas_equalTo(q_pt(40));
        make.height.mas_equalTo(q_pt(40));
    }];
    
    UIView* bottomMenuView = [[UIView alloc] init];
    [self.view addSubview:bottomMenuView];
    [bottomMenuView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(superView).with.offset(-(q_pt(145) + safeBottom));
        make.centerX.equalTo(superView);
        make.width.mas_equalTo(q_pt(268));
        make.height.mas_equalTo(q_pt(32));
    }];
    
    UIButton* shootBtn = [[UIButton alloc] init];
    [shootBtn setImage:[UIImage imageNamed:@"camera_record"] forState:UIControlStateNormal];
    [shootBtn setImage:[UIImage imageNamed:@"publish_shooting"] forState:UIControlStateSelected];
    [shootBtn addTarget:self action:@selector(toggleMovieRecording:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:shootBtn];
    [shootBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.equalTo(bottomMenuView);
        make.top.equalTo(bottomMenuView.mas_bottom).with.offset(q_pt(20));
        make.width.mas_equalTo(q_pt(68));
        make.height.mas_equalTo(q_pt(68));
    }];
    
    UIButton* filterBtn = [[UIButton alloc] init];
    [filterBtn setTitle:@"滤镜" forState:UIControlStateNormal];
    [bottomMenuView addSubview:filterBtn];
    [filterBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(bottomMenuView);
        make.top.equalTo(bottomMenuView);
        make.bottom.equalTo(bottomMenuView);
    }];
    
    
    UIButton* beautyBtn = [[UIButton alloc] init];
    [bottomMenuView addSubview:beautyBtn];
    [beautyBtn setTitle:@"美颜" forState:UIControlStateNormal];
    [beautyBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(filterBtn.mas_right);
        make.top.equalTo(bottomMenuView);
        make.bottom.equalTo(bottomMenuView);
        make.width.equalTo(filterBtn);
    }];
    
    UIButton* discountBtn = [[UIButton alloc] init];
    [bottomMenuView addSubview:discountBtn];
    [discountBtn setTitle:@"倒计时" forState:UIControlStateNormal];
    [discountBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(beautyBtn.mas_right);
        make.right.equalTo(bottomMenuView);
        make.top.equalTo(bottomMenuView);
        make.bottom.equalTo(bottomMenuView);
        make.width.equalTo(filterBtn);
    }];
    
    self.focusView = [[UIImageView alloc] init];
    self.focusView.bounds = CGRectMake(0, 0, q_pt(120.f), q_pt(120.f));
    [self.focusView setImage:[UIImage imageNamed:@"publishFocusingbig"]];
    self.focusView.hidden = YES;
    [self.view addSubview:self.focusView];
    
    UITapGestureRecognizer* tapGes = [[UITapGestureRecognizer alloc] init];
    [tapGes addTarget:self action:@selector(focusTap:)];
    [self.previewView addGestureRecognizer:tapGes];
}

-(void) setupUIDevice{
    if (@available(iOS 10.2, *)) {
        NSArray<AVCaptureDeviceType> *deviceTypes = @[AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInDualCamera];
        self.videoDeviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
    } else {
        // Fallback on earlier versions
    }
    self.session = [[AVCaptureSession alloc] init];
    self.previewView.session = self.session;
    
//    AVCaptureVideoPreviewLayer * layer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
//    layer.videoGravity=AVLayerVideoGravityResizeAspectFill;
//    layer.frame=self.view.layer.bounds;
//    [self.view.layer insertSublayer:layer atIndex:0];
    
    self.sessionQueue = dispatch_queue_create( "session queue", DISPATCH_QUEUE_SERIAL );
    self.setupResult =  AVCamSetupResultSuccess;
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

#pragma mark ================   Private Method  ================
- (void)configureSession
{
    if ( self.setupResult != AVCamSetupResultSuccess ) {
        return;
    }
    NSError *error = nil;
    [self.session beginConfiguration];
    
    /*
     We do not create an AVCaptureMovieFileOutput when setting up the session because the
     AVCaptureMovieFileOutput does not support movie recording with AVCaptureSessionPresetPhoto.
     */
    self.session.sessionPreset = AVCaptureSessionPresetHigh;
    
    // Add video input.
    // Choose the back dual camera if available, otherwise default to a wide angle camera.
    AVCaptureDevice *videoDevice = nil;
    if (@available(iOS 10.2, *)) {
        videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInDualCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
        if ( ! videoDevice ) {
            // If the back dual camera is not available, default to the back wide angle camera.
            videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack];
            
            // In some cases where users break their phones, the back wide angle camera is not available. In this case, we should default to the front wide angle camera.
            if ( ! videoDevice ) {
                videoDevice = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
            }
        }
    } else {
        // Fallback on earlier versions
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
        
        dispatch_async( dispatch_get_main_queue(), ^{
            /*
             Why are we dispatching this to the main queue?
             Because AVCaptureVideoPreviewLayer is the backing layer for AVCamPreviewView and UIView
             can only be manipulated on the main thread.
             Note: As an exception to the above rule, it is not necessary to serialize video orientation changes
             on the AVCaptureVideoPreviewLayer’s connection with other session manipulation.
             
             Use the status bar orientation as the initial video orientation. Subsequent orientation changes are
             handled by -[AVCamCameraViewController viewWillTransitionToSize:withTransitionCoordinator:].
             */
            UIInterfaceOrientation statusBarOrientation = [UIApplication sharedApplication].statusBarOrientation;
            AVCaptureVideoOrientation initialVideoOrientation = AVCaptureVideoOrientationPortrait;
            if ( statusBarOrientation != UIInterfaceOrientationUnknown ) {
                initialVideoOrientation = (AVCaptureVideoOrientation)statusBarOrientation;
            }
            self.previewView.videoPreviewLayer.connection.videoOrientation = initialVideoOrientation;
        } );
    }
    else {
        NSLog( @"Could not add video device input to the session" );
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
    
    //  Add photo output.
    AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ( [self.session canAddOutput:movieFileOutput] )
    {
        [self.session addOutput:movieFileOutput];
        self.session.sessionPreset = AVCaptureSessionPresetHigh;
        AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
        if ( connection.isVideoStabilizationSupported ) {
            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
        }
        self.movieFileOutput = movieFileOutput;
    } else {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    [self.session commitConfiguration];
}


#pragma mark ================   Action Method    ================
-(void) goBack{
    
}

- (void)toggleMovieRecording:(UIButton *)sender
{
    sender.selected = !sender.selected;
    /*
     Retrieve the video preview layer's video orientation on the main queue
     before entering the session queue. We do this to ensure UI elements are
     accessed on the main thread and session configuration is done on the session queue.
     */
    AVCaptureVideoOrientation videoPreviewLayerVideoOrientation = self.previewView.videoPreviewLayer.connection.videoOrientation;
    dispatch_async( self.sessionQueue, ^{
        if ( ! self.movieFileOutput.isRecording ) {
            if ( [UIDevice currentDevice].isMultitaskingSupported ) {
                /*
                 Setup background task.
                 This is needed because the -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:]
                 callback is not received until AVCam returns to the foreground unless you request background execution time.
                 This also ensures that there will be time to write the file to the photo library when AVCam is backgrounded.
                 To conclude this background execution, -[endBackgroundTask:] is called in
                 -[captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:] after the recorded file has been saved.
                 */
                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:nil];
            }

            // Update the orientation on the movie file output video connection before starting recording.
            AVCaptureConnection *movieFileOutputConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            movieFileOutputConnection.videoOrientation = videoPreviewLayerVideoOrientation;

            // Use HEVC codec if supported
            if (@available(iOS 11.0, *)) {
                if ( [self.movieFileOutput.availableVideoCodecTypes containsObject:AVVideoCodecTypeHEVC] ) {
                    [self.movieFileOutput setOutputSettings:@{ AVVideoCodecKey : AVVideoCodecTypeHEVC } forConnection:movieFileOutputConnection];
                }
            } else {
                // Fallback on earlier versions

            }

            // Start recording to a temporary file.
            NSString *outputFileName = [NSUUID UUID].UUIDString;
            NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mov"]];
            [self.movieFileOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputFilePath] recordingDelegate:self];
        }
        else {
            [self.movieFileOutput stopRecording];
        }
    } );
}

-(void) flashButtonClick:(UIButton *) sender{
    if([self.videoDevice hasTorch]){
        sender.selected = !sender.selected;
        [self.videoDevice lockForConfiguration:nil];
        if(sender.selected) {
            [self.videoDevice setTorchMode:AVCaptureTorchModeOn];
        } else {
            [self.videoDevice setTorchMode:AVCaptureTorchModeOff];
        }
        [self.videoDevice unlockForConfiguration];
    }
}

-(void) changeCameral:(UIButton *) sender{
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
        
        NSArray<AVCaptureDevice *> *devices = self.videoDeviceDiscoverySession.devices;
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
            
            // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
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
            
            AVCaptureConnection *movieFileOutputConnection = [self.movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            if ( movieFileOutputConnection.isVideoStabilizationSupported ) {
                movieFileOutputConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
            }
            self.movieFileOutputConnection = movieFileOutputConnection;
            [self.session commitConfiguration];
        }
        
        dispatch_async( dispatch_get_main_queue(), ^{
           
        } );
        
    });
}

-(void) focusTap:(UITapGestureRecognizer *) tapGes{
    CGPoint touchPoint = [tapGes locationInView:tapGes.view];
    CGPoint devicePoint = [self.previewView.videoPreviewLayer captureDevicePointOfInterestForPoint:touchPoint];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposeWithMode:AVCaptureExposureModeAutoExpose atDevicePoint:devicePoint monitorSubjectAreaChange:YES];
    [self runFocusAnimationAtPoint:touchPoint];
}

-(void) frameChangeClick:(UIButton *) sender{
    sender.selected = !sender.selected;
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = [UIScreen mainScreen].bounds.size.height;
    if(sender.selected) {
        height = width;
    }
    [self setActiveFormatWithFrameRate:[self frameRate] width:width andHeight:height error:nil];
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

// 聚焦、曝光动画
-(void)runFocusAnimationAtPoint:(CGPoint)point{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissFocusView) object:nil];
    self.focusView.center = point;
    self.focusView.hidden = NO;
    self.focusView.transform = CGAffineTransformIdentity;
    [UIView animateWithDuration:0.15f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.focusView.layer.transform = CATransform3DMakeScale(0.75, 0.75, 1.0);
//        self.focusView.transform = CGAffineTransformTranslate(self.focusView.transform, 0.75, 0.75);
    } completion:^(BOOL complete) {
        [self performSelector:@selector(dismissFocusView) withObject:nil afterDelay:1.0];
    }];
}

-(void)dismissFocusView {
    self.focusView.hidden = YES;
    self.focusView.transform = CGAffineTransformIdentity;
}

// 调整画幅
- (BOOL)setActiveFormatWithFrameRate:(CMTimeScale)frameRate width:(int)width andHeight:(int)height error:(NSError *__autoreleasing *)error {
    AVCaptureDevice *device = self.videoDeviceInput.device;
    CMVideoDimensions dimensions;
    dimensions.width = width;
    dimensions.height = height;
    
    BOOL foundSupported = NO;
    if (device != nil) {
        AVCaptureDeviceFormat *bestFormat = nil;
        
        for (AVCaptureDeviceFormat *format in device.formats) {
            if ([[self class] formatInRange:format frameRate:frameRate dimensions:dimensions]) {
                if (bestFormat == nil) {
                    bestFormat = format;
                } else {
                    CMVideoDimensions bestDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription);
                    CMVideoDimensions currentDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
                    
                    if (currentDimensions.width < bestDimensions.width && currentDimensions.height < bestDimensions.height) {
                        bestFormat = format;
                    } else if (currentDimensions.width == bestDimensions.width && currentDimensions.height == bestDimensions.height) {
                        if ([[self class] maxFrameRateForFormat:bestFormat minFrameRate:frameRate] > [[self class] maxFrameRateForFormat:format minFrameRate:frameRate]) {
                            bestFormat = format;
                        }
                    }
                }
            }
        }
        
        if (bestFormat != nil) {
            if ([device lockForConfiguration:error]) {
                CMTime frameDuration = CMTimeMake(1, frameRate);
                
                device.activeFormat = bestFormat;
                foundSupported = true;
                
                device.activeVideoMinFrameDuration = frameDuration;
                device.activeVideoMaxFrameDuration = frameDuration;
                
                [device unlockForConfiguration];
            }
        } else {
            if (error != nil) {
                *error = [[self class] createError:[NSString stringWithFormat:@"No format that supports framerate %d and dimensions %d/%d was found", (int)frameRate, dimensions.width, dimensions.height]];
            }
        }
    } else {
        if (error != nil) {
            *error = [[self class] createError:@"The camera must be initialized before setting active format"];
        }
    }
    
    if (foundSupported && error != nil) {
        *error = nil;
    }
    
    return foundSupported;
}

- (CMTimeScale)frameRate {
    AVCaptureDeviceInput * deviceInput = self.videoDeviceInput;
    
    CMTimeScale framerate = 0;
    if (deviceInput != nil) {
        if ([deviceInput.device respondsToSelector:@selector(activeVideoMaxFrameDuration)]) {
            framerate = deviceInput.device.activeVideoMaxFrameDuration.timescale;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            AVCaptureConnection *videoConnection = self.movieFileOutputConnection;
            framerate = videoConnection.videoMaxFrameDuration.timescale;
#pragma clang diagnostic pop
        }
    }
    
    return framerate;
}

#pragma mark - Tool Method
+ (BOOL)formatInRange:(AVCaptureDeviceFormat*)format frameRate:(CMTimeScale)frameRate dimensions:(CMVideoDimensions)dimensions {
    CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    
    if (size.width >= dimensions.width && size.height >= dimensions.height) {
        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
            if (range.minFrameDuration.timescale >= frameRate && range.maxFrameDuration.timescale <= frameRate) {
                return YES;
            }
        }
    }
    return NO;
}

+ (CMTimeScale)maxFrameRateForFormat:(AVCaptureDeviceFormat *)format minFrameRate:(CMTimeScale)minFrameRate {
    CMTimeScale lowerTimeScale = 0;
    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
        if (range.minFrameDuration.timescale >= minFrameRate && (lowerTimeScale == 0 || range.minFrameDuration.timescale < lowerTimeScale)) {
            lowerTimeScale = range.minFrameDuration.timescale;
        }
    }
    
    return lowerTimeScale;
}

+ (NSError*)createError:(NSString*)errorDescription {
    return [NSError errorWithDomain:@"SLCamerError" code:200 userInfo:@{NSLocalizedDescriptionKey : errorDescription}];
}


#pragma mark ================   AVCaptureFileOutputRecordingDelegate    ================
- (void)captureOutput:(AVCaptureFileOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray<AVCaptureConnection *> *)connections error:(nullable NSError *)error{
    UIBackgroundTaskIdentifier currentBackgroundRecordingID = self.backgroundRecordingID;
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    
    dispatch_block_t cleanUp = ^{
        if ( [[NSFileManager defaultManager] fileExistsAtPath:outputFileURL.path] ) {
            [[NSFileManager defaultManager] removeItemAtPath:outputFileURL.path error:NULL];
        }
        
        if ( currentBackgroundRecordingID != UIBackgroundTaskInvalid ) {
            [[UIApplication sharedApplication] endBackgroundTask:currentBackgroundRecordingID];
        }
    };
    
    BOOL success = YES;
    
    if ( error ) {
        NSLog( @"Movie file finishing error: %@", error );
        success = [error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] boolValue];
    }
    if ( success ) {
        // Check authorization status.
        [PHPhotoLibrary requestAuthorization:^( PHAuthorizationStatus status ) {
            if ( status == PHAuthorizationStatusAuthorized ) {
                // Save the movie file to the photo library and cleanup.
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetResourceCreationOptions *options = [[PHAssetResourceCreationOptions alloc] init];
                    options.shouldMoveFile = YES;
                    PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAsset];
                    [creationRequest addResourceWithType:PHAssetResourceTypeVideo fileURL:outputFileURL options:options];
                } completionHandler:^( BOOL success, NSError *error ) {
                    if ( ! success ) {
                        NSLog( @"Could not save movie to photo library: %@", error );
                    }
                    cleanUp();
                }];
            }
            else {
                cleanUp();
            }
        }];
    }
    else {
        cleanUp();
    }
    
    // Enable the Camera and Record buttons to let the user switch camera and start another recording.
    dispatch_async( dispatch_get_main_queue(), ^{
        // Only enable the ability to change camera if the device has more than one camera.
        
    });
}

@end

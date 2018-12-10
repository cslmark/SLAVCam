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
#import <Metal/Metal.h>
#import "AVCamPreView.h"
#import "SLUICommon.h"
#import "SCSampleBufferHolder.h"
#import "SCImageView.h"
#import "RippleModel.h"
#include <OpenGLES/ES2/glext.h>

// Uniform index.
enum
{
    UNIFORM_Y,
    UNIFORM_UV,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD,
    NUM_ATTRIBUTES
};


typedef NS_ENUM( NSInteger, AVCamSetupResult ) {
    AVCamSetupResultSuccess,
    AVCamSetupResultCameraNotAuthorized,
    AVCamSetupResultSessionConfigurationFailed
};
static void * SessionRunningContext = &SessionRunningContext;

API_AVAILABLE(ios(10.0))
@interface ViewController ()<AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
{
    SCSampleBufferHolder* _lastVideoBuffer;
    BOOL _shouldIgnore;
    AVCaptureConnection *currentConnection;
    CVPixelBufferRef currentSampleBuffer;
    
    GLuint _program;
    
    GLuint _positionVBO;
    GLuint _texcoordVBO;
    GLuint _indexVBO;
    
    CGFloat _screenWidth;
    CGFloat _screenHeight;
    size_t _textureWidth;
    size_t _textureHeight;
    unsigned int _meshFactor;
    
    EAGLContext *_context;
    RippleModel *_ripple;
    
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    
    NSString *_sessionPreset;
    CVOpenGLESTextureCacheRef _videoTextureCache;
}
@property (nonatomic, weak) AVCamPreView *previewView;
@property (nonatomic) AVCamSetupResult setupResult;
@property (nonatomic) AVCaptureDeviceDiscoverySession *videoDeviceDiscoverySession;   // Available 10.2
@property (nonatomic, strong) UIImageView *focusView;//对焦框
@property (nonatomic, weak) UIButton* shootBtn;

// 具体的物理设备
@property (nonatomic) AVCaptureDevice *videoDevice;

// 四个要素<Connection 需要的时候创建>
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoDeviceInput;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;
@property (nonatomic, strong) AVCaptureConnection *movieFileOutputConnection;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
// AVCaptureAudioDataOutput *_audioOutput;

// 辅助属性
@property (nonatomic, getter=isSessionRunning) BOOL sessionRunning;

// 滤镜等美颜功能
@property (strong, nonatomic) SCImageView *__nullable SCImageView;

// 队列
@property (nonatomic) dispatch_queue_t sessionQueue;

// 后台任务
@property (nonatomic) UIBackgroundTaskIdentifier backgroundRecordingID;
@end

@implementation ViewController

#pragma mark ================   Life Cycle    ================
- (void)viewDidLoad {
    [super viewDidLoad];
    
    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    if (!_context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = _context;
    self.preferredFramesPerSecond = 60;
    
    _screenWidth = [UIScreen mainScreen].bounds.size.width;
    _screenHeight = [UIScreen mainScreen].bounds.size.height;
    view.contentScaleFactor = [UIScreen mainScreen].scale;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        // meshFactor controls the ending ripple mesh size.
        // For example mesh width = screenWidth / meshFactor.
        // It's chosen based on both screen resolution and device size.
        _meshFactor = 8;
        
        // Choosing bigger preset for bigger screen.
        _sessionPreset = AVCaptureSessionPreset1280x720;
    }
    else
    {
        _meshFactor = 4;
        _sessionPreset = AVCaptureSessionPreset640x480;
    }
    [self setupGL];
    
    
    [self regiseterNotification];
    [self setupUI];
    [self setupUIDevice];
    
    _lastVideoBuffer =  [SCSampleBufferHolder new];
    _shouldIgnore = NO;
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

- (void)viewDidUnload
{
    [super viewDidUnload];
    
    [self tearDownAVCapture];
    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == _context) {
        [EAGLContext setCurrentContext:nil];
    }
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
            self.shootBtn.enabled = isSessionRunning;
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
    NSLog(@"%s", __func__);
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
    NSLog(@"%s", __func__);
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
    //-- Create CVOpenGLESTextureCacheRef for optimal CVImageBufferRef to GLES texture conversion.
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_videoTextureCache);
#else
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)_context, NULL, &_videoTextureCache);
#endif
    if (err)
    {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        return;
    }
    
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
    self.shootBtn = shootBtn;
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
- (void)setupGL
{
    [EAGLContext setCurrentContext:_context];
    
    [self loadShaders];
    
    glUseProgram(_program);
    
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
}

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
    
    //  Add Video output.
//    AVCaptureMovieFileOutput *movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
//    if ( [self.session canAddOutput:movieFileOutput] )
//    {
//        [self.session addOutput:movieFileOutput];
//        self.session.sessionPreset = AVCaptureSessionPresetHigh;
//        AVCaptureConnection *connection = [movieFileOutput connectionWithMediaType:AVMediaTypeVideo];
//        if ( connection.isVideoStabilizationSupported ) {
//            connection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
//        }
//        self.movieFileOutput = movieFileOutput;
//    } else {
//        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
//        [self.session commitConfiguration];
//        return;
//    }
    
    // Add Data Output For Beauty
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    if ([self.session canAddOutput:_videoOutput]) {
        [self.session addOutput:_videoOutput];
        [_videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                                   forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        [_videoOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
        [_videoOutput setAlwaysDiscardsLateVideoFrames:YES];
        
//        AVCaptureConnection *videoOutputConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
//        videoOutputConnection.videoOrientation = self.previewView.videoPreviewLayer.connection.videoOrientation;
//        if ( videoOutputConnection.isVideoStabilizationSupported ) {
//            videoOutputConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
//        }
    } else {
        self.setupResult = AVCamSetupResultSessionConfigurationFailed;
        [self.session commitConfiguration];
        return;
    }
    
    self.backgroundRecordingID = UIBackgroundTaskInvalid;
    [self.session commitConfiguration];
}

- (void)tearDownAVCapture
{
    [self cleanUpTextures];
    
    CFRelease(_videoTextureCache);
}

- (void)setupBuffers
{
    glGenBuffers(1, &_indexVBO);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _indexVBO);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, [_ripple getIndexSize], [_ripple getIndices], GL_STATIC_DRAW);
    
    glGenBuffers(1, &_positionVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _positionVBO);
    glBufferData(GL_ARRAY_BUFFER, [_ripple getVertexSize], [_ripple getVertices], GL_STATIC_DRAW);
    
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2*sizeof(GLfloat), 0);
    
    glGenBuffers(1, &_texcoordVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _texcoordVBO);
    glBufferData(GL_ARRAY_BUFFER, [_ripple getVertexSize], [_ripple getTexCoords], GL_DYNAMIC_DRAW);
    
    glEnableVertexAttribArray(ATTRIB_TEXCOORD);
    glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 2*sizeof(GLfloat), 0);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:_context];
    
    glDeleteBuffers(1, &_positionVBO);
    glDeleteBuffers(1, &_texcoordVBO);
    glDeleteBuffers(1, &_indexVBO);
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

- (void)cleanUpTextures
{
    if (_lumaTexture)
    {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    
    if (_chromaTexture)
    {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
    
    // Periodic texture cache flush every frame
    CVOpenGLESTextureCacheFlush(_videoTextureCache, 0);
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
                typeof(*&self) __weak weakSelf = self;
                self.backgroundRecordingID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                    NSLog(@"进入后台需要处理 ========");
                    [[UIApplication sharedApplication] endBackgroundTask:weakSelf.backgroundRecordingID];
                }];
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
    [self setActiveFormatWithFrameRate:[self frameRate] width:height andHeight:width error:nil];
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
                    CMVideoDimensions size = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription);
                    NSLog(@"bestFormat size === [%0.1d %0.1d] ====== dimensions === [%0.1d %0.1d]", size.width, size.height, dimensions.width, dimensions.height);
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
    
    NSLog(@"formatInRange size === [%0.1d %0.1d] ====== dimensions === [%0.1d %0.1d]", size.width, size.height, dimensions.width, dimensions.height);
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

- (void)captureOutputOrigin:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (captureOutput == _videoOutput) {
        _lastVideoBuffer.sampleBuffer = sampleBuffer;
        //        NSLog(@"VIDEO BUFFER: %fs (%fs)", CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)), CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer)));
        
        if (_shouldIgnore) {
            return;
        }
        
        SCImageView *imageView = _SCImageView;
        if (imageView != nil) {
            CFRetain(sampleBuffer);
            dispatch_async(dispatch_get_main_queue(), ^{
                [imageView setImageBySampleBuffer:sampleBuffer];
                CFRelease(sampleBuffer);
            });
        }
    }
}

- (AVCaptureVideoOrientation)actualVideoOrientation {
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationPortrait;
//    AVCaptureVideoOrientation videoOrientation = _videoOrientation;
//
//    if (_autoSetVideoOrientation) {
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
//    }
    
    return videoOrientation;
}


#pragma mark - support Method
- (BOOL)supportMetal {
    static BOOL support = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if(device){
            if (@available(iOS 9.0, *)) {
                support = [device supportsFeatureSet:MTLFeatureSet_iOS_GPUFamily1_v2];
            }
        }
    });
    return support;
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

#pragma mark ================   AVCaptureVideoDataOutputSampleBufferDelegate    ================
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    NSLog(@"%s", __func__);
    CVReturn err;
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    if (!_videoTextureCache)
    {
        NSLog(@"No video texture cache");
        return;
    }
    
    if (_ripple == nil ||
        width != _textureWidth ||
        height != _textureHeight)
    {
        _textureWidth = width;
        _textureHeight = height;
        
        _ripple = [[RippleModel alloc] initWithScreenWidth:_screenWidth
                                              screenHeight:_screenHeight
                                                meshFactor:_meshFactor
                                               touchRadius:5
                                              textureWidth:_textureWidth
                                             textureHeight:_textureHeight];
        
        [self setupBuffers];
    }
    
    [self cleanUpTextures];
    
    // CVOpenGLESTextureCacheCreateTextureFromImage will create GLES texture
    // optimally from CVImageBufferRef.
    
    // Y-plane
    glActiveTexture(GL_TEXTURE0);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RED_EXT,
                                                       _textureWidth,
                                                       _textureHeight,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &_lumaTexture);
    if (err)
    {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // UV-plane
    glActiveTexture(GL_TEXTURE1);
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       _videoTextureCache,
                                                       pixelBuffer,
                                                       NULL,
                                                       GL_TEXTURE_2D,
                                                       GL_RG_EXT,
                                                       _textureWidth/2,
                                                       _textureHeight/2,
                                                       GL_RG_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       1,
                                                       &_chromaTexture);
    if (err)
    {
        NSLog(@"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
    }
    
    glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE); 
}

#pragma mark - OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(_program, ATTRIB_TEXCOORD, "texCoord");
    
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_Y] = glGetUniformLocation(_program, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(_program, "SamplerUV");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    if (_ripple)
    {
        [_ripple runSimulation];
        
        // no need to rebind GL_ARRAY_BUFFER to _texcoordVBO since it should be still be bound from setupBuffers
        glBufferData(GL_ARRAY_BUFFER, [_ripple getVertexSize], [_ripple getTexCoords], GL_DYNAMIC_DRAW);
    }
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);
    
    if (_ripple)
    {
        glDrawElements(GL_TRIANGLE_STRIP, [_ripple getIndexCount], GL_UNSIGNED_SHORT, 0);
    }
}

#pragma mark - Touch handling methods

- (void)myTouch:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *touch in touches)
    {
        CGPoint location = [touch locationInView:touch.view];
        [_ripple initiateRippleAtLocation:location];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self myTouch:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self myTouch:touches withEvent:event];
}

@end

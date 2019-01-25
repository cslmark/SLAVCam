//
//  SLCameraViewController.m
//  SLAVCam
//
//  Created by Iansl on 2019/1/25.
//  Copyright © 2019 Iansl. All rights reserved.
//

#import "SLCameraViewController.h"
#import <Masonry/Masonry.h>
#import "AVCamPreView.h"
#import "SLUICommon.h"
#import "TAVCamera.h"
#import "TTExposureSlider.h"


@interface SLCameraViewController ()
{
    CGFloat _exposeVlaue;
    CGFloat _totalScale;
}
@property (nonatomic, weak) AVCamPreView *previewView;
@property (nonatomic, strong) UIImageView *focusView;
@property (nonatomic, weak) UIButton* shootBtn;
@property (nonatomic, strong) TAVCamera* camera;
@property (nonatomic, strong) TTExposureSlider* exposeSliderView;
@end

@implementation SLCameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    _exposeVlaue = 0.5;
    _totalScale = 1.0;
    _camera = [[TAVCamera alloc] initWithMaxPublishDuration:300];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
    [_camera startRunning];
    [_camera setCameraPreview:self.previewView];
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
    
    self.exposeSliderView = [[TTExposureSlider alloc] init];
    self.exposeSliderView.bounds = CGRectMake(0, 0, q_pt(20.f), q_pt(140.f));
    self.exposeSliderView.hidden = YES;
    [self.view addSubview:self.exposeSliderView];
    
    UITapGestureRecognizer* tapGes = [[UITapGestureRecognizer alloc] init];
    [tapGes addTarget:self action:@selector(focusTap:)];
    [self.previewView addGestureRecognizer:tapGes];
    
    UIPanGestureRecognizer* panGes = [[UIPanGestureRecognizer alloc] init];
    [panGes addTarget:self action:@selector(panGes:)];
    [self.previewView addGestureRecognizer:panGes];
    
    UIPinchGestureRecognizer *pinchGestureRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinchGes:)];
    [self.previewView addGestureRecognizer:pinchGestureRecognizer];
}

#pragma mark ================   Action Method    ================
-(void) flashButtonClick:(UIButton *) sender{
    sender.selected = !sender.selected;
    if(sender.selected) {
        self.camera.torchMode = TAVCameraTorchModeOn;
    } else {
        self.camera.torchMode = TAVCameraTorchModeOff;
    }
}

-(void) changeCameral:(UIButton *) sender{
    [self.camera switchCameraPosition];
}

- (void)toggleMovieRecording:(UIButton *)sender
{
    sender.selected = !sender.selected;
}

- (void)frameChangeClick:(UIButton *) sender{
    //Do Nothing PituEffect
}

-(void) focusTap:(UITapGestureRecognizer *) tapGes{
    CGPoint touchPoint = [tapGes locationInView:tapGes.view];
    CGPoint devicePoint = [self.previewView.videoPreviewLayer captureDevicePointOfInterestForPoint:touchPoint];
    [self.camera focusAtPoint:devicePoint];
    [self runFocusAnimationAtPoint:touchPoint];
}

- (void) panGes:(UIPanGestureRecognizer *) panGes{
    CGPoint moviePoint = [panGes translationInView:panGes.view];
    [panGes setTranslation:CGPointZero inView:panGes.view];
//    CGPoint velocity = [panGes velocityInView:panGes.view];
    float exposeValue = -moviePoint.y / self.view.bounds.size.height;
    if(_exposeVlaue == 1 && exposeValue > 0) {
        return;
    }
    if(_exposeVlaue == 0 && exposeValue < 0) {
        return;
    }
    _exposeVlaue += exposeValue;
    if(_exposeVlaue >= 1) {
        _exposeVlaue = 1;
    }
    if(_exposeVlaue <= 0) {
        _exposeVlaue = 0;
    }
    [self.camera setExposureTargetBias:_exposeVlaue];
}

- (void) pinchGes:(UIPinchGestureRecognizer *) pinchGes{
    CGFloat scale = pinchGes.scale;
    NSLog(@"scale[%lf]", scale);
    _totalScale *= scale;
    pinchGes.scale = 1.0;
    [self.camera changeVideoZoomFactor:_totalScale];
}

// 聚焦、曝光动画
-(void)runFocusAnimationAtPoint:(CGPoint)point{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(dismissFocusView) object:nil];
    self.focusView.center = point;
    self.focusView.hidden = NO;
    self.exposeSliderView.value = _exposeVlaue;
    [self.exposeSliderView show:YES animated:YES];
    self.exposeSliderView.center = CGPointMake(point.x + 70, point.y);
    self.focusView.transform = CGAffineTransformIdentity;
    
    [UIView animateWithDuration:0.15f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.focusView.layer.transform = CATransform3DMakeScale(0.75, 0.75, 1.0);
        //        self.focusView.transform = CGAffineTransformTranslate(self.focusView.transform, 0.75, 0.75);
    } completion:^(BOOL complete) {
        [self performSelector:@selector(dismissFocusView) withObject:nil afterDelay:1.0];
    }];
}

- (void)dismissFocusView {
    self.focusView.hidden = YES;
    self.focusView.transform = CGAffineTransformIdentity;
}

@end

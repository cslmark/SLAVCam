//
//  TTExposureSlider.m
//  SLAVCam
//
//  Created by Iansl on 2019/1/25.
//  Copyright © 2019 Iansl. All rights reserved.
//

#import "TTExposureSlider.h"

@interface TTExposureSlider()
{
    float _defaultValue;
    float _autoAdjustOffsetValue;
    
    CGFloat _sliderHeight;
    CGFloat _sliderBgWidth;
    CGFloat _sliderAlpha;
    CGFloat _sliderBgheight;
    BOOL _isDragging;
    CGPoint _touchStartPoint;
    float _touchStartValue;
}
@property (nonatomic, strong) UIImageView *sliderBgUpView;
@property (nonatomic, strong) UIImageView *sliderBgDownView;
@property (nonatomic, strong) UIImageView *sliderCenterView;
@property (nonatomic, strong) NSTimer *autoHideTimer;
@end

@implementation TTExposureSlider

+ (instancetype)slider
{
    return [[[self class] alloc] init];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        
        _minimumValue = 0.f;
        _maximumValue = 1.f;
        _sliderHeight = 120.f + 11.f + _sliderCenterView.frame.size.height + 28.f;
        _autoHideSlider = YES;
        _defaultValue = 0.f;
        _sliderAlpha = 0.6f;
        [self updateAutoAdjustOffset];
        
        self.bounds = CGRectMake(0.f, 0.f, 38.f, _sliderHeight);
        
        
        UIImage *image = [UIImage imageNamed:@"camera_exposure_bg"];
        _sliderBgWidth = image.size.width;
        
        UIImage *upImage = [image stretchableImageWithLeftCapWidth:image.size.width / 2.f topCapHeight:5.5f];
        self.sliderBgUpView = [[UIImageView alloc] initWithImage:upImage];
        [self addSubview:_sliderBgUpView];
        
        UIImage *downImage = [image stretchableImageWithLeftCapWidth:image.size.width / 2.f topCapHeight:5.5f];
        self.sliderBgDownView = [[UIImageView alloc] initWithImage:downImage];
        [self addSubview:_sliderBgDownView];
        
        UIImage *centerImage = [UIImage imageNamed:@"camera_exposure_light"];
        self.sliderCenterView = [[UIImageView alloc] initWithFrame:CGRectMake(0.f, 0.f,   centerImage.size.width, centerImage.size.height)];
        _sliderCenterView.image = centerImage;
        [self addSubview:_sliderCenterView];
        
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(sliderTapped:)];
        [self addGestureRecognizer:tapGesture];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGSize _superSize = self.bounds.size;
    
    float _total = _maximumValue - _minimumValue;
    float _percentage = 0.f;
    if (_total > 0.f) {
        _percentage = (_maximumValue - _value) / _total;
    }
    
    self.alpha = _value == _defaultValue ? 1.f : _sliderAlpha;
    _sliderBgUpView.hidden = _percentage < 0.12f ? YES : NO;
    _sliderBgDownView.hidden = _percentage > 0.88f ? YES : NO;
    
    CGFloat _effectiveHeight = _sliderHeight;
    
    CGFloat _topHeight = _effectiveHeight * _percentage;
    CGFloat _bottomHeight = _effectiveHeight - _topHeight;
    
    _sliderCenterView.center = CGPointMake(_superSize.width / 2.f, _topHeight );
    
    _topHeight = _topHeight + 11.f ;
    _bottomHeight = _bottomHeight + 11.f;
    
    CGFloat _bgOffsetX = (_superSize.width - _sliderBgWidth) / 2.f;
    _sliderBgUpView.frame = CGRectMake(_bgOffsetX, 0.f, _sliderBgWidth, _topHeight - 26.5f);
    _sliderBgDownView.frame = CGRectMake(_bgOffsetX, _superSize.height - _bottomHeight + 26.5f, _sliderBgWidth, _bottomHeight - 26.5f );
}

- (void)setValue:(float)value
{
    value = MAX(_minimumValue, MIN(_maximumValue, value));
    value = fabsf(value - _defaultValue) < _autoAdjustOffsetValue ? _defaultValue : value;
    if (_value != value) {
        _value = value;
        [self setNeedsLayout];
    }
}

- (void)setMinimumValue:(float)minimumValue
{
    _minimumValue = minimumValue;
    [self updateAutoAdjustOffset];
}

- (void)setMaximumValue:(float)maximumValue
{
    _maximumValue = maximumValue;
    [self updateAutoAdjustOffset];
}

- (void)setIsShow:(BOOL)isShow
{
    [self show:isShow animated:NO];
}

- (void)show:(BOOL)isShow animated:(BOOL)animated
{
    _isShow = isShow;
    CGFloat _showAlpha = _value == _defaultValue ? 1.f : _sliderAlpha;
    if (animated) {
        if (isShow) {
            self.hidden = NO;
        }
        //        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:^{
        [UIView animateWithDuration:.3f animations:^{
            self.alpha = isShow ? _showAlpha : 0.0;
        } completion:^(BOOL finished) {
            self.hidden = isShow ? NO : YES;
        }];
    } else {
        self.alpha = isShow ? _showAlpha : 0.0;
        self.hidden = isShow ? NO : YES;
    }
    
    if (isShow) {
        [self refreshTimer];
    } else {
        [_autoHideTimer invalidate];
    }
}

- (void)autoHideView
{
    if (_autoHideSlider) {
        [self show:NO animated:YES];
    }
}

- (void)refreshTimer
{
    [_autoHideTimer invalidate];
    self.autoHideTimer = [NSTimer scheduledTimerWithTimeInterval:2.f target:self selector:@selector(autoHideView) userInfo:nil repeats:NO];
}

- (void)updateValueWithDistance:(CGFloat)distance previousValue:(float)previousValue
{
    CGFloat _effectiveHeight = _sliderHeight - 11.f - _sliderCenterView.frame.size.height;
    CGFloat _dValue = distance * (_maximumValue - _minimumValue) / _effectiveHeight;
    self.value = previousValue + _dValue;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

//滑杆自动吸附范围
- (void)updateAutoAdjustOffset
{
    _autoAdjustOffsetValue = (_maximumValue - _minimumValue) / 25.f;
}

#pragma mark - Touch

- (void)sliderTapped:(UITapGestureRecognizer *)recognizer
{
    if (!_isDragging) {
        CGPoint point = [recognizer locationInView:self];
        [self updateValueWithDistance:_sliderCenterView.center.y - point.y previousValue:_value];
    }
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [_autoHideTimer invalidate];
    _autoHideTimer = nil;
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    if (CGRectContainsPoint(_sliderCenterView.frame, point)) {
        _isDragging = YES;
        _touchStartPoint = point;
        _touchStartValue = _value;
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [_autoHideTimer invalidate];
    if (_isDragging) {
        UITouch *touch = [touches anyObject];
        CGPoint point = [touch locationInView:self];
        [self updateValueWithDistance:_touchStartPoint.y - point.y previousValue:_touchStartValue];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    _isDragging = NO;
    [self refreshTimer];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    _isDragging = NO;
    [self refreshTimer];
}

@end

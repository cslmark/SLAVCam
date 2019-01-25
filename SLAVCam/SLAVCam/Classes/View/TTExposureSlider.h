//
//  TTExposureSlider.h
//  SLAVCam
//
//  Created by Iansl on 2019/1/25.
//  Copyright © 2019 Iansl. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TTExposureSlider : UIControl
@property (nonatomic, assign) float value;
@property (nonatomic, assign) float minimumValue;
@property (nonatomic, assign) float maximumValue;
@property (nonatomic, assign) BOOL isShow;
@property (nonatomic, assign) BOOL autoHideSlider;


+ (instancetype)slider;
- (void)show:(BOOL)isShow animated:(BOOL)animated;
@end

NS_ASSUME_NONNULL_END

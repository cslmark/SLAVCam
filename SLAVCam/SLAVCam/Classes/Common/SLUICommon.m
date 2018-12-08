//
//  SLUICommon.m
//  SLAVCam
//
//  Created by Iansl on 2018/12/3.
//  Copyright © 2018 Iansl. All rights reserved.
//

#import "SLUICommon.h"


CGFloat q_pt(CGFloat designpt) {
    CGFloat appScale = [UIScreen mainScreen].scale;
    CGFloat designpx = appScale * designpt;
    return floor(designpx * SLUICommon.designScale + 0.5) / appScale;
}

CGSize q_size(CGSize designsize) {
    return SLUICommon.size(designsize);
}

@implementation SLUICommon
+ (CGFloat)designScale {
    static CGFloat designScale;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        CGFloat screenWidth = (screenSize.width < screenSize.height) ? screenSize.width : screenSize.height;
        designScale = screenWidth / 360.0;
    });
    return designScale;
}

+ (CGFloat (^)(CGFloat))pt {
    return ^CGFloat(CGFloat designpt) {
        CGFloat appScale = [UIScreen mainScreen].scale;
        CGFloat designpx = appScale * designpt;
        return floor(designpx * SLUICommon.designScale + 0.5) / appScale;
    };
}

+ (CGSize (^)(CGSize))size {
    return ^CGSize(CGSize designsize) {
        return CGSizeMake(self.pt(designsize.width), self.pt(designsize.height));
    };
}

+ (NSString * _Nonnull (^)(UIColor * _Nonnull))hexValues {
    return ^NSString *(UIColor *rgbColor) {
        if (!rgbColor) {
            return nil;
        }
        
        CGFloat red, blue, green, alpha;
        if (![rgbColor getRed:&red green:&green blue:&blue alpha:&alpha]) {
            return nil;
        }
        
        int r = (int)(red * 255);
        int g = (int)(green * 255);
        int b = (int)(blue * 255);
        int a = (int)(alpha * 255);
        NSString *returnString = [NSString stringWithFormat:@"#%02x%02x%02x%02x", (unsigned int)a, (unsigned int)r, (unsigned int)g, (unsigned int)b];
        return returnString;
    };
}

+ (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets safeAreaInsets;
    if (@available(iOS 11, *)) {
        safeAreaInsets = [UIApplication sharedApplication].keyWindow.safeAreaInsets;
    } else {
        safeAreaInsets = UIEdgeInsetsZero;
    }
    return safeAreaInsets;
}

@end

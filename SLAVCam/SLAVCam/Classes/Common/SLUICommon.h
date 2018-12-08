//
//  SLUICommon.h
//  SLAVCam
//
//  Created by Iansl on 2018/12/3.
//  Copyright © 2018 Iansl. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// 几个快速接口
extern CGFloat  q_pt(CGFloat designpt);
extern UIColor *q_hexcolor(NSString *hexstring);

NS_ASSUME_NONNULL_BEGIN

@interface SLUICommon : NSObject
/**
 app 设计定义的 scale 值, pt * designScale
 */
@property (nonatomic, assign, class, readonly) CGFloat designScale;
+ (CGSize (^)(CGSize))size;
+ (UIEdgeInsets)safeAreaInsets;
@end

NS_ASSUME_NONNULL_END

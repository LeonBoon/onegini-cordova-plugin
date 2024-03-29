//
//  UIColor+OGNHex.m
//  OneginiCordovaPlugin
//
//  Created by Stanisław Brzeski on 02/06/16.
//  Copyright © 2016 Onegini. All rights reserved.
//

#import "UIColor+OGNHex.h"

@implementation UIColor (OGNHex)

+ (UIColor *)ogn_colorWithHexString:(NSString *)hexString {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [UIColor colorWithRed:((rgbValue & 0xFF0000) >> 16) / 255.0 green:((rgbValue & 0xFF00) >> 8) / 255.0 blue:(rgbValue & 0xFF) / 255.0 alpha:1.0];
}

@end

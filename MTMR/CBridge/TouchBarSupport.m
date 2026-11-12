//
//  TouchBarSupport.m
//  MTMR
//
//  Created by Anton Palgunov on 08/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import "TouchBarSupport.h"
#import <AppKit/AppKit.h>
#import <IOKit/hidsystem/ev_keymap.h>

@implementation MediaKeys

// Decision: post NX_SYSDEFINED aux keys as CGEvents instead of IOHIDPostEvent/IOMasterPort
// (deprecated macOS 11 / 12). Same event layout as before: subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS),
// data1 = keyCode << 16 | (NX_KEYDOWN|NX_KEYUP) << 8. Requires Accessibility permission (app already asks for it).
+ (void)postAuxKey:(UInt8)keyCode down:(BOOL)down {
    NSInteger flags = down ? NX_KEYDOWN : NX_KEYUP; // 0xa / 0xb
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                        location:NSZeroPoint
                                   modifierFlags:(down ? 0xa00 : 0xb00)
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                         subtype:NX_SUBTYPE_AUX_CONTROL_BUTTONS
                                           data1:(((NSInteger)keyCode) << 16) | (flags << 8)
                                           data2:-1];
    CGEventPost(kCGHIDEventTap, event.CGEvent);
}

+ (void)HIDPostAuxKey: (UInt8)keyCode {
    [self postAuxKey:keyCode down:YES];
    [self postAuxKey:keyCode down:NO];
}

@end

//
//  TouchBarSupport.h
//  MTMR
//
//  Created by Anton Palgunov on 08/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MediaKeys : NSObject

+ (void)HIDPostAuxKey:(UInt8)keyCode;

@end

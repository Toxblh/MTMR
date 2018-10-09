//
//  CBBlueLightClient.h
//  MTMR
//
//  Created by Anton Palgunov on 28/08/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef struct {
    int hour;
    int minute;
} Time;

typedef struct {
    Time fromTime;
    Time toTime;
} Schedule;

typedef struct {
    BOOL active;
    BOOL enabled;
    BOOL sunSchedulePermitted;
    int mode;
    Schedule schedule;
    unsigned long long disableFlags;
} Status;

@interface CBBlueLightClient: NSObject
- (BOOL) setEnabled: (BOOL)enabled;
- (BOOL) setMode: (int)mode;
- (void) getBlueLightStatus: (Status *)status;
@end

//
//  TouchBarSupport.m
//  MTMR
//
//  Created by Anton Palgunov on 08/04/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import "TouchBarSupport.h"
#import <IOKit/hidsystem/ev_keymap.h>

@implementation MediaKeys

static io_connect_t get_event_driver(void)
{
    static  mach_port_t sEventDrvrRef = 0;
    mach_port_t masterPort, service, iter;
    kern_return_t    kr;
    
    if (!sEventDrvrRef)
    {
        kr = IOMasterPort( bootstrap_port, &masterPort );
        kr = IOServiceGetMatchingServices( masterPort, IOServiceMatching( kIOHIDSystemClass ), &iter );
        service = IOIteratorNext( iter );
        kr = IOServiceOpen( service, mach_task_self(),
                           kIOHIDParamConnectType, &sEventDrvrRef );
        IOObjectRelease( service );
        IOObjectRelease( iter );
    }
    return sEventDrvrRef;
}


static void HIDReleaseAuxKey( const UInt8 auxKeyCode )
{
    NXEventData   event;
    kern_return_t kr;
    IOGPoint      loc = { 0, 0 };
    
    // Key press event
    UInt32 evtInfo = auxKeyCode << 16 | NX_KEYDOWN << 8;
    bzero(&event, sizeof(NXEventData));
    event.compound.subType = NX_SUBTYPE_AUX_CONTROL_BUTTONS;
    event.compound.misc.L[0] = evtInfo;
    kr = IOHIDPostEvent( get_event_driver(), NX_SYSDEFINED, loc, &event, kNXEventDataVersion, 0, FALSE );
    
    // Key release event
    evtInfo = auxKeyCode << 16 | NX_KEYUP << 8;
    bzero(&event, sizeof(NXEventData));
    event.compound.subType = NX_SUBTYPE_AUX_CONTROL_BUTTONS;
    event.compound.misc.L[0] = evtInfo;
    kr = IOHIDPostEvent( get_event_driver(), NX_SYSDEFINED, loc, &event, kNXEventDataVersion, 0, FALSE );
}

+ (void)HIDPostAuxKey: (UInt8)keyCode {
    HIDReleaseAuxKey(keyCode);
}

@end

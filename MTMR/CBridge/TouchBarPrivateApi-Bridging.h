//
//  TouchBarPrivateApi-Bridging.h
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

#import "AMR_ANSIEscapeHelper.h"
#import "TouchBarPrivateApi.h"
#import "TouchBarSupport.h"
#import "DeprecatedCarbonAPI.h"
#import "CBBlueLightClient.h"
#import "LaunchAtLoginController.h"

NS_ASSUME_NONNULL_BEGIN

// Returns NULL when no actuator exists for the ID (verified on M1: bogus IDs -> NULL), so _Nullable.
CF_EXPORT CFTypeRef _Nullable MTActuatorCreateFromDeviceID(UInt64 deviceID);
CF_EXPORT IOReturn MTActuatorOpen(CFTypeRef actuatorRef);
CF_EXPORT IOReturn MTActuatorClose(CFTypeRef actuatorRef);
CF_EXPORT IOReturn MTActuatorActuate(CFTypeRef actuatorRef, SInt32 actuationID, UInt32 arg1, Float32 arg2, Float32 arg3);
CF_EXPORT bool MTActuatorIsOpen(CFTypeRef actuatorRef);

CF_EXPORT void CoreDisplay_Display_SetUserBrightness(int CGDirectDisplayID, double level);
CF_EXPORT double CoreDisplay_Display_GetUserBrightness(int CGDirectDisplayID);

NS_ASSUME_NONNULL_END

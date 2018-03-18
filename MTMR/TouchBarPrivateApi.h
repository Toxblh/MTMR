
#import <AppKit/AppKit.h>

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier, BOOL);

extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL);

@interface NSTouchBarItem (PrivateMethods)

+ (void)addSystemTrayItem:(NSTouchBarItem *)item;

+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;

@end

@interface NSTouchBar (PrivateMethods)

// presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;

+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;

+ (void)dismissSystemModalFunctionBar:(NSTouchBar *)touchBar;

+ (void)minimizeSystemModalFunctionBar:(NSTouchBar *)touchBar;

@end

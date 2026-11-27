
#import <AppKit/AppKit.h>

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier, BOOL);

extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL);

// The older DFRGetScreenSize always reports the first-generation canvas on some Macs.
typedef struct MTMRTouchBarDisplay *MTMRTouchBarDisplayRef;
extern MTMRTouchBarDisplayRef DFRTouchBarGetMain(void) __attribute__((weak_import));
extern CGSize DFRTouchBarGetScreenSize(MTMRTouchBarDisplayRef) __attribute__((weak_import));
static inline CGSize MTMRMainTouchBarSize(void) {
    if (DFRTouchBarGetMain && DFRTouchBarGetScreenSize) {
        MTMRTouchBarDisplayRef display = DFRTouchBarGetMain();
        if (display) return DFRTouchBarGetScreenSize(display);
    }
    return CGSizeZero;
}

@interface NSTouchBarItem (PrivateMethods)

+ (void)addSystemTrayItem:(NSTouchBarItem *)item;

+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;

@end


@interface NSTouchBar (PrivateMethods)

// macOS 10.14
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;

// macOS 10.13
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar placement:(long long)placement systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)presentSystemModalFunctionBar:(NSTouchBar *)touchBar systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)dismissSystemModalFunctionBar:(NSTouchBar *)touchBar;
+ (void)minimizeSystemModalFunctionBar:(NSTouchBar *)touchBar;

@end


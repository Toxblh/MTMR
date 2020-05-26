## TODOs

* try view controllers on `NSCustomTouchBarItem` instead of subclassing item itself
* try move away from enums when parse preset – enums are hard to extend
* find better way to hide bar items
* extract bar items creating from TouchBarController to separate class, cover with tests


### Roadmap

- [x] Create the first prototype with TouchBar in Storyboard
- [x] Put in stripe menu on startup the application
- [x] Find how to simulate real buttons like brightness, volume, night shift and etc.
- [x] Time in touchbar!
- [x] First the weather plugin
- [x] Find how to open full-screen TouchBar without the cross and stripe menu
- [x] Find how to add haptic feedback
- [x] Add icon and menu in StatusBar
- [x] Hide from Dock
- [x] Status menu: "preferences", "quit"
- [x] JSON or another approch for save preset, maybe in `~/Library/Application Support/MTMR/`
- [x] Custom buttons size, actions by click
- [x] Layout: [always left, NSSliderView for center, always right]
- [x] System for autoupdate (https://sparkle-project.org/)
- [ ] Overwrite default values from item types (e.g. title for brightness)
- [ ] Custom settings for paddings and margins for buttons
- [ ] XPC Service for scripts
- [ ] UI for settings
- [ ] Import config from BTT

Settings:

- [ ] Interface for plugins and export like presets
- [x] Startup at login
- [ ] Show on/off in Dock
- [ ] Show on/off in StatusBar
- [x] On/off Haptic Feedback

Maybe:

- [ ] Refactoring the application into packages (AppleScript, JavaScript? and Swift?)

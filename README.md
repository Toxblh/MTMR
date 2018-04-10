
<p align="center">
    <img src="Resources/logo.png" width="120">
</p>

# My TouchBar. My rules
[![GitHub release](https://img.shields.io/github/release/toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/releases)

<p align="center">
    <img src="Resources/TouchBar-v0.3.png">
</p>

My the idea is to create the program like a platform for plugins for customization TouchBar. I very like BTT and a full custom TouchBar (my [BTT preset](https://github.com/Toxblh/btt-touchbar-preset)). And I want to create it. And it's my the first Swift project for MacOS :)

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
- [ ] Layout: [always left, NSSliderView for center, always right]
- [ ] Custom buttons size, actions by click in settings
- [ ] Overwrite default values from item types (e.g. title for brightness)
- [ ] System for autoupdate (maybe https://sparkle-project.org/)

Settings:
- [ ] Intarface for plugins and export like presets
- [ ] Startup at login
- [ ] Show on/off in Dock
- [ ] Show on/off in StatusBar
- [ ] On/off Haptic Feedback

Maybe:
- [ ] Refactoring the application on packages (AppleScript, JavaScript? and Swift?)

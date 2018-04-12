
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
- [x] Custom buttons size, actions by click
- [ ] Layout: [always left, NSSliderView for center, always right]
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

### Example presets

@ReDetection:
```json
[
{ "type": "escape", "width": 110 },
{ "type": "exitTouchbar" },
{ "type": "brightnessDown", "width": 40 },
{ "type": "brightnessUp", "width": 40 },
{ "type": "appleScriptTitledButton", "refreshInterval": 15, "source": { "inline": "if application \"Safari\" is running then\r\ttell application \"Safari\"\r\t\trepeat with t in tabs of windows\r\t\t\ttell t\r\t\t\t\tif URL starts with \"https:\/\/music.yandex.ru\" and name does not end with \"на Яндекс.Музыке\" then\r\t\t\t\t\treturn name of t as text\r\t\t\t\tend if\r\t\t\tend tell\r\t\tend repeat\r\tend tell\rend if\rreturn \"\"" },
"action": "appleScript", "actionAppleScript": {"inline": "if application \"Safari\" is running then\r\ttell application \"Safari\"\r\t\trepeat with w in windows\r\t\t\trepeat with t in tabs of w\r\t\t\t\ttell t\r\t\t\t\t\tif URL starts with \"https:\/\/music.yandex.ru\" and name does not end with \"на Яндекс.Музыке\" then --последнее условие проверяет, запущена ли музыка\r\t\t\t\t\t\tactivate\r\t\t\t\t\t\tset index of w to 1\r\t\t\t\t\t\tdelay 0.1\r\t\t\t\t\t\tset current tab of w to t\r\t\t\t\t\tend if\r\t\t\t\tend tell\r\t\t\tend repeat\r\t\tend repeat\r\tend tell\rend if"},
},
{ "type": "appleScriptTitledButton", "source": { "inline": "tell application \"Reminders\"\r\tset activeReminders to name of (reminders of list \"Напоминания\" whose completed is false)\r\tif activeReminders is not {} then\r\t\treturn first item of activeReminders\r\telse\r\t\treturn \"\"\r\tend if\rend tell" }, "refreshInterval": 30},
{ "type": "flexSpace" },
{ "type": "appleScriptTitledButton", "source": { "inline": "if application \"iTunes\" is running then\r\ttell application \"iTunes\"\r\t\tif player state is not stopped then return \"\"\r\tend tell\rend if\rif application \"Safari\" is running then\r\ttell application \"Safari\"\r\t\trepeat with t in tabs of windows\r\t\t\ttell t\r\t\t\t\tif URL starts with \"https:\/\/music.yandex.ru\" and name does not end with \"на Яндекс.Музыке\" then\r\t\t\t\t\treturn \"\"\r\t\t\t\tend if\r\t\t\tend tell\r\t\tend repeat\r\tend tell\rend if\rreturn \"▶\"" }, "refreshInterval": 30, "width": 40},
{ "type": "volumeDown", "width": 44 },
{ "type": "volumeUp", "width": 44 },
{ "type": "displaySleep" },
{ "type": "appleScriptTitledButton", "refreshInterval": 1800, "source": { "filePath": "/Users/redetection/Library/Application Support/MTMR/Weather.scpt"} },
{ "type": "timeButton" },
]
```

## Credits

Built by [@toxblh](https://patreon.com/toxblh) and [@ReDetection](http://patreon.com/ReDetection).

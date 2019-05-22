<p align="center"><img src="Resources/logo.png" width="120"></p>

# My TouchBar. My rules

*The TouchBar Customization App for your MacBook Pro*

[![GitHub release](https://img.shields.io/github/release/toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/releases)
[![license](https://img.shields.io/github/license/Toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/blob/master/LICENSE) [![Total downloads](https://img.shields.io/github/downloads/Toxblh/MTMR/total.svg)](https://github.com/Toxblh/MTMR/releases/latest) ![minimal system requirements](https://img.shields.io/badge/required-macOS%2010.12.2-blue.svg) ![travis](https://travis-ci.org/Toxblh/MTMR.svg?branch=master)

<p align="center">
    <img src="Resources/TouchBar-v0.8.1.png">
</p>

**MTMR** Community:
[<img height="24px" src="https://camo.githubusercontent.com/88f53948f291c54736bf08f5fd7b037a848dfc62/68747470733a2f2f646973636f72646170702e636f6d2f6173736574732f30376463613830613130326434313439653937333664346231363263666636662e69636f"> Discord](https://discord.gg/CmNcDuQ)
[<img height="24px" src="https://telegram.org/img/t_logo.png" /> Telegram](https://t.me/joinchat/AmVYGg8vW38c13_3MxdE_g)

<a href="https://www.paypal.me/toxblh/10" title="Donate via Paypal"><img height="36px" src="Resources/support_paypal.svg" alt="PayPal donate button" /></a>
<a href="https://www.buymeacoffee.com/toxblh" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" height="36px" ></a>
<a href="https://www.patreon.com/bePatron?u=9900748"><img height="36px"  src="https://c5.patreon.com/external/logo/become_a_patron_button.png" srcset="https://c5.patreon.com/external/logo/become_a_patron_button@2x.png 2x"></a>
<a href="https://www.producthunt.com/posts/my-touchbar-my-rules-mtmr">
    <img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=my-touchbar-my-rules-mtmr&theme=light" alt="My TouchBar My Rules (MTMR)" height="36px" style="max-width:100%">
</a>


My idea is to create a platform for creating plugins to customize the TouchBar. I very much like BTT and having a full custom TouchBar (my [BTT preset](https://github.com/Toxblh/btt-touchbar-preset)), and I wanted to create it. It's my first Swift project for MacOS :)

#### Share your presets [here](https://github.com/Toxblh/MTMR-presets)

## Installation
- Download lastest [release](https://github.com/Toxblh/MTMR/releases) from github
- Or via Homebrew `brew cask install mtmr`

> First open: you should allow access for MTMR in Accessibility for correct buttons work like <kbd>Esc</kbd> Volume/Brightness and another system keys

## Troubleshooting
If you can't open preferences:
- Opening another program which can't edit text
    1. Open Terminal.app
    2. Put `open -a TextEdit ~/Library/Application\ Support/MTMR/items.json` command and press <kbd>Enter</kbd>

Buttons or gestures doesn't work:
- "After the last update my mtmr is not working anymore!"
- "Buttons sometimes do not trigger action"
- "ESC don't work"
- "Gestures don't work"

Re-tick or check a tick for access 🍏→ System Preferences → Security and Privacy → tab Privacy → Accessibility → MTMR

<img width="450" alt="screenshot 2019-02-24 at 23 19 20" src="https://user-images.githubusercontent.com/2198153/53307057-2b078200-388c-11e9-8212-8c2b1aff0aa6.png">

## Built-in button types:
> Buttons
- escape
- exitTouchbar
- brightnessUp
- brightnessDown
- illuminationUp (keyboard illumination)
- illuminationDown (keyboard illumination)
- volumeDown
- volumeUp
- mute

> Native Plugins
- battery
- currency
- weather
- inputsource
- music (tap for pause, longTap for next)
- dock (half-long click to open app, full-long click to kill app)
- nightShift
- dnd (Don't disturb)
- darkMode
- pomodoro
- network

> Media Keys
- previous
- play
- next

> AppleScript plugins
- sleep
- displaySleep

## Gestures on central part:
- two finger slide: change you Volume
- three finger slide: change you Brightness

## Built-in slider types:

- brightness
- volume

### You can also make custom buttons using these types
- `staticButton`
```json
 "type": "staticButton",
 "title": "esc",
```

- `appleScriptTitledButton`
```js
    "type": "appleScriptTitledButton",
    "refreshInterval": 60, //optional
    "source": {
      "filePath": "/Users/toxblh/Library/Application Support/MTMR/iTunes.nowPlaying.scpt",
      // or
      "inline": "tell application \"Finder\"\rmake new Finder window\rset target of front window to path to home folder as string\ractivate\rend tell",
      // or
      "base64": "StringInbase64"
    },
```

- `timeButton`
```js
  "type": "timeButton",
  "formatTemplate": "HH:mm" //optional
```

## Groups
```js
{
"type": "group",
"align": "center",
"bordered": true,
"title": "stats",
"items": [
    { "type": "play" }, { "type": "mute" }, ...]
}
```

To close a group, use the button:
```
{
"type": "close",
"width": 64
},
```

## Native plugins
#### `timeButton`
> Attention! Works not all: https://en.wikipedia.org/wiki/List_of_time_zone_abbreviations
```js
{
  "type": "timeButton",
  "formatTemplate": "dd HH:mm",
  "timeZone": "UTC"
}
```

#### `weather`
> Provider: https://openweathermap.org Need allowance location service
```js
  "type": "weather",
  "refreshInterval": 600, // in seconds
  "units": "metric", // or imperial
  "icon_type": "text" // or images
  "api_key": "" // you can get the key on openweather
```

#### `currency`
> Provider: https://coinbase.com
```js
  "type": "currency",
  "refreshInterval": 600, // in seconds
  "align": "right",
  "from": "BTC",
  "to": "USD",
  "full": true // £‣1.29$
```

#### `music`
```js
{
  "type": "music",
  "align": "center",
  "width": 80,
  "bordered": false,
  "refreshInterval": 2, // in seconds
},
```

#### `pomodoro`
> Pomodoro plugin. One click to start the work timer, longclick to start the rest timer. Click in progress for reset.
```js
{
  "type": "pomodoro",
  "workTime": 1200, // set time work in seconds. Default 1500 (25 min)
  "restTime": 600 // set time rest in seconds. Default 300 (5 min)
},
```

#### `network`
> Network plugin. The plugin to show usage a network
```js
{
  "type": "network",
  "flip": true
},
```

#### `dock`
> Dock plugin
```js
{
  "type": "dock",
  "autoResize": true
},
```

## Actions:
- `hidKey`
> https://github.com/aosm/IOHIDFamily/blob/master/IOHIDSystem/IOKit/hidsystem/ev_keymap.h use only numbers
```json
 "action": "hidKey",
 "keycode": 53,
```

- `keyPress`
```json
 "action": "keyPress",
 "keycode": 1,
```

- `appleScript`
```js
 "action": "appleScript",
 "actionAppleScript": {
     "inline": "tell application \"Finder\"\rmake new Finder window\rset target of front window to path to home folder as string\ractivate\rend tell"
    // "filePath" or "base64" will work as well
 },
```

- `shellScript`
```js
 "action": "shellScript",
 "executablePath": "/usr/bin/pmset",
 "shellArguments": ["sleepnow"], // optional

```

- `openUrl`
```js
 "action": "openUrl",
 "url": "https://google.com",
```

## LongActions
If you want to longPress for some operations, it is similar to the configuration for Actions but with additional parameters, for example:
```js
 "longAction": "hidKey",
 "longKeycode": 53,
```

- longAction
- longKeycode
- longActionAppleScript
- longExecutablePath
- longShellArguments
- longUrl

## Additional parameters:

- `width` restrict how much room a particular button will take
```json
  "width": 34
```

- `align` can stick the item to the side. default is center
```js
  "align": "left" // "left", "right" or "center"
```

- `bordered` you can do button without border
```js
  "bordered": "false" // "true" or "false"
```

## Example configuration:
```json
[
  { "type": "escape", "width": 110 },
  { "type": "exitTouchbar", "align": "left" },
  {
    "type": "brightnessUp",
    "align": "left",
    "width": 36
  },
  {
    "type": "staticButton",
    "align": "left",
    "title": "🔆",
    "action": "keyPress",
    "keycode": 113,
    "width": 36
  },

  {
    "type": "appleScriptTitledButton",
    "source": {
      "filePath": "/Users/toxblh/Library/Application Support/MTMR/iTunes.nowPlaying.scpt"
    },
    "refreshInterval": 1
  },
 {
    "type": "staticButton",
    "align": "left",
    "image": { "base64" : "%base64Finder%"},
    "action": "appleScript",
    "actionAppleScript": {
        "inline": "tell application \"Finder\"\rmake new Finder window\rset target of front window to path to home folder as string\ractivate\rend tell"
    },
    "width": 36
  },
  {
    "type": "appleScriptTitledButton",
    "source": {
      "inline": "if application \"Safari\" is running then\r\ttell application \"Safari\"\r\t\trepeat with t in tabs of windows\r\t\t\ttell t\r\t\t\t\tif URL starts with \"https:\/\/music.yandex.ru\" and name does not end with \"на Яндекс.Музыке\" then\r\t\t\t\t\treturn name of t as text\r\t\t\t\tend if\r\t\t\tend tell\r\t\tend repeat\r\tend tell\rend if\rreturn \"\""
    },
    "refreshInterval": 1
  },
  { "type": "previous", "width": 36, "align": "right" },
  { "type": "play", "width": 36, "align": "right" },
  { "type": "next", "width": 36, "align": "right" },
  { "type": "sleep", "width": 36 , "align": "right"},
  { "type": "displaySleep", "align": "right" },
  { "type": "weather", "refreshInterval": 1800, "width": 70, "align": "right" },
  { "type": "volumeDown", "width": 36 , "align": "right"},
  { "type": "volumeUp", "width": 36 , "align": "right"},
  { "type": "battery", "refreshInterval": 60 , "align": "right"},
  { "type": "appleScriptTitledButton", "refreshInterval": 1800, "source": { "filePath": "/Users/redetection/Library/Application Support/MTMR/Weather.scpt"} , "align": "right"},
  { "type": "timeButton", "formatTemplate": "HH:mm", "width": 64, "align": "right" }
]
```


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
- [ ] On/off Haptic Feedback

Maybe:
- [ ] Refactoring the application on packages (AppleScript, JavaScript? and Swift?)

### Author's presets
[@Toxblh preset](Resources/toxblh.json)

[@ReDetection preset](Resources/ReDetection.json)

### User's presets
[@luongvo209 preset](Resources/luongvo209.json)
![](Resources/luongvo209.png)

[aadi_vs_anand preset](Resources/aadi_vs_anand.json)
![](Resources/aadi_vs_anand1.png)
![](Resources/aadi_vs_anand2.png)

## Credits

Built by [@Toxblh](https://patreon.com/toxblh) and [@ReDetection](http://patreon.com/ReDetection).

[![Analytics](https://ga-beacon.appspot.com/UA-96373624-2/mtmr?pixel)](https://github.com/igrigorik/ga-beacon)

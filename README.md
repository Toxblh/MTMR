
<p align="center">
    <img src="Resources/logo.png" width="120">
</p>

# My TouchBar. My rules

*The TouchBar Customization App for your MacBook Pro*

[![GitHub release](https://img.shields.io/github/release/toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/releases)
[![license](https://img.shields.io/github/license/Toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/blob/master/LICENSE) [![Total downloads](https://img.shields.io/github/downloads/Toxblh/MTMR/total.svg)](https://github.com/Toxblh/MTMR/releases/latest) ![minimal system requirements](https://img.shields.io/badge/required-macOS%2010.12.2-blue.svg) ![travis](https://travis-ci.org/Toxblh/MTMR.svg?branch=master)

<p align="center">
    <img src="Resources/TouchBar-v0.8.1.png">
</p>

**MTMR** Community:
[<img height="24px" src="https://github.com/discourse/DiscourseMobile/raw/master/icon.png" /> Discourse](https://forum.mtmr.app)
[<img height="24px" src="https://telegram.org/img/t_logo.png" /> Telegram](https://t.me/joinchat/AmVYGg8vW38c13_3MxdE_g)

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
- [x] Layout: [always left, NSSliderView for center, always right]
- [ ] Overwrite default values from item types (e.g. title for brightness)
- [ ] Custom settings for paddings and margins for buttons
- [ ] XPC Service for scripts
- [ ] UI for settings
- [ ] Import config from BTT
- [ ] System for autoupdate (maybe https://sparkle-project.org/)

Settings:
- [ ] Interface for plugins and export like presets
- [x] Startup at login
- [ ] Show on/off in Dock
- [ ] Show on/off in StatusBar
- [ ] On/off Haptic Feedback

Maybe:
- [ ] Refactoring the application on packages (AppleScript, JavaScript? and Swift?)


## Installation
- Download last [release](https://github.com/Toxblh/MTMR/releases)
- Or via Homebrew `brew cask install mtmr`

## Preset

File for customize your preset for MTMR: `open ~/Library/Application\ Support/MTMR/items.json`

## Built-in button types:

- escape
- exitTouchbar
- brightnessUp
- brightnessDown
- illuminationUp (keyboard illumination)
- illuminationDown (keyboard illumination)
- volumeDown
- volumeUp
- mute
- dock (half-long click to open app, full-long click to kill app)

> Native Plugins
- battery
- currency
- weather
- inputsource
- music (tap for pause, longTap for next)

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

### You can also make a custom buttons using these types
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
"items": [{ button }, {button}, ...]
}
```

## Native plugins
- `weather`
> Provider: https://openweathermap.org Need allowance location service
```js
  "type": "weather",
  "refreshInterval": 600,
  "units": "metric", // or imperial
  "icon_type": "text" // or images
  "api_key": "" // you can get the key on openweather
```

- `currency`
> Provider: https://coinbase.com
```js
  "type": "currency",
  "refreshInterval": 600,
  "align": "right",
  "from": "BTC",
  "to": "USD",
```

- `music`
```js
{
  "type": "music",
  "align": "center",
  "width": 80,
  "bordered": false,
  "refreshInterval": 2,
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
This then you want to use longPress for some operations is will the same values like for Actions but different additional parameters, example:
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

- `width` allow to restrict how much room a particular button will take
```json
  "width": 34
```

- `align` can stick the item to the side. default is center
```js
  "align": "left" //or "right" or "center"
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


### Author's presets

[@Toxblh preset](Resources/toxblh.json)

[@ReDetection preset](Resources/ReDetection.json)

### User's presets

[@luongvo209 preset](Resources/luongvo209.json)
![](Resources/luongvo209.png)

## Credits

<a href="https://www.buymeacoffee.com/toxblh" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" style="height: auto !important;width: auto !important;" ></a>

Built by [@Toxblh](https://patreon.com/toxblh) and [@ReDetection](http://patreon.com/ReDetection).

[![Analytics](https://ga-beacon.appspot.com/UA-96373624-2/mtmr?pixel)](https://github.com/igrigorik/ga-beacon)

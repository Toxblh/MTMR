# My touchbar. My rules. [![GitHub release](https://img.shields.io/github/release/toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/releases) [![license](https://img.shields.io/github/license/Toxblh/MTMR.svg)](https://github.com/Toxblh/MTMR/blob/master/LICENSE)![minimal system requirements](https://img.shields.io/badge/required-macOS%2010.12.2-blue.svg) ![travis](https://travis-ci.org/Toxblh/MTMR.svg?branch=master)

<img src="Resources/logo.png" align="right"
     title="MTMR by Toxblh" width="110" height="110">

_The TouchBar Customization App for your MacBook Pro_

My idea is to create a platform for creating plugins to customize the TouchBar. I very much like BTT and having a full custom TouchBar (my BTT preset), and I wanted to create it. It's my first Swift project for MacOS :)

**Share your presets [here](https://github.com/Toxblh/MTMR-presets)**

<p align="center">
  <img src="./Resources/aaaaa-acc6-17fee7572ed0.png" alt="Mackbook with touchbar" width="800">
</p>

<p align="center">
<a href="https://discord.gg/CmNcDuQ"><img height="20px" src="https://camo.githubusercontent.com/88f53948f291c54736bf08f5fd7b037a848dfc62/68747470733a2f2f646973636f72646170702e636f6d2f6173736574732f30376463613830613130326434313439653937333664346231363263666636662e69636f"> Discord</a>
<a href="https://t.me/joinchat/AmVYGg8vW38c13_3MxdE_g"><img height="20px" src="https://telegram.org/img/t_logo.png" /> Telegram</a>
</p>

<p align="center"><a href="https://www.paypal.me/toxblh/10" title="Donate via Paypal"><img height="36px" src="Resources/support_paypal.svg" alt="PayPal donate button" /></a>
<a href="https://www.buymeacoffee.com/toxblh" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy Me A Coffee" height="36px" ></a>
<a href="https://www.patreon.com/bePatron?u=9900748"><img height="36px"  src="https://c5.patreon.com/external/logo/become_a_patron_button.png" srcset="https://c5.patreon.com/external/logo/become_a_patron_button@2x.png 2x"></a>
<a href="https://www.producthunt.com/posts/my-touchbar-my-rules-mtmr">
    <img src="https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=my-touchbar-my-rules-mtmr&theme=light" alt="My TouchBar My Rules (MTMR)" height="36px" style="max-width:100%">
</a></p>

## Installation

- Download lastest [release](https://github.com/Toxblh/MTMR/releases) (.dmg) from github
- Or via Homebrew `brew cask install mtmr`
- [Dario Prski](https://medium.com/@urdigitalpulse) has written a [fantastic article on medium](https://medium.com/@urdigitalpulse/customise-your-macbook-pro-touch-bar-966998e606b5) that goes into more detail on installing MTMR

**On first install** you need to allow access for MTMR in Accessibility otherwise buttons like <kbd>Esc</kbd>, <kbd>Volume</kbd>, <kbd>Brightness</kbd> and other system keys won't work

<p align="center">
<img width="450" alt="screenshot 2019-02-24 at 23 19 20" src="https://user-images.githubusercontent.com/2198153/53307057-2b078200-388c-11e9-8212-8c2b1aff0aa6.png">
</p>

<p align="center">
🍏→ System Preferences → Security and Privacy → tab Privacy → Accessibility → MTMR
</p>

## Examples

- [@Toxblh preset](Resources/toxblh.json)
- [@ReDetection preset](Resources/ReDetection.json)
- [@luongvo209 preset](Resources/luongvo209.json)
- [aadi_vs_anand preset](Resources/aadi_vs_anand.json)

<p align="center">
  <img src="./Resources/Artboard.png" alt="Presets for touchbar" width="800">
</p>

## Customization

MTMR preferences are stored under `~/Library/Application\ Support/MTMR/items.json`.

The pre-installed configuration contains less or more than you'll probably want, try to configure:

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
- yandexWeather
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

> Provider: https://openweathermap.org \
> Note: you need to register on https://openweathermap.org to get your API key \
> Note: you may need to wait for near 20 mins until your API key will be activated by Openweathermap \
> Note: you need to allow using "Location Services" in your Mac OS "Security & Privacy" settings for MTMR

```js
  "type": "weather",
  "refreshInterval": 600, // in seconds
  "units": "metric", // or imperial
  "icon_type": "text" // or images
  "api_key": "" // you can get the key on openweather
```

#### `yandexWeather` (experimental)

> Provider: https://yandex.ru/pogoda. One click to open up weather forecast in your browser. \
> Note: you need to allow using "Location Services" in your Mac OS "Security & Privacy" settings for MTMR

```js
  "type": "yandexWeather",
  "refreshInterval": 600 // in seconds
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
  "width": 80, // Optional
  "bordered": false, // Optional
  "refreshInterval": 2, // in seconds. Optional. Default 5 seconds
  "disableMarquee": true // to disable marquee effect. Optional. Default false
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

- [ ] Refactoring the application into packages (AppleScript, JavaScript? and Swift?)

## Credits

Built by [@Toxblh](https://patreon.com/toxblh) and [@ReDetection](http://patreon.com/ReDetection).

[![Analytics](https://ga-beacon.appspot.com/UA-96373624-2/mtmr?pixel)](https://github.com/igrigorik/ga-beacon)

# This script requires two libs. Download them:
# https://itunes.apple.com/ru/app/json-helper-for-applescript/id453114608?l=en&mt=12
# https://itunes.apple.com/ru/app/location-helper-for-applescript/id488536386?mt=12
tell application "Location Helper"
	set clocation_coords to get location coordinates
	tell application "JSON Helper"
		set weather to fetch JSON from "http://api.openweathermap.org/data/2.5/weather?lat=" & item 1 of clocation_coords & "&lon=" & item 2 of clocation_coords & "&units=metric&appid=32c4256d09a4c52b38aecddba7a078f6"
		set temp to temp of main of weather as string
		set cond_icon to icon of item 1 of weather of weather as string
		if cond_icon is in ["01d", "01n"] then
			set cond to "☀️"
		else if cond_icon is in ["02d", "02n"] then
			set cond to "⛅️"
		else if cond_icon is in ["03d", "03n", "04d", "04n"] then
			set cond to "☁️"
		else if cond_icon is in ["09d", "09n"] then
			set cond to "🌧"
		else if cond_icon is in ["10d", "10n"] then
			set cond to "🌦"
		else if cond_icon is in ["11d", "11n"] then
			set cond to "🌩"
		else if cond_icon is in ["13d", "13n"] then
			set cond to "❄️"
		else if cond_icon is in ["50d", "50n"] then
			set cond to "🌫"
		else
			set cond to ""
		end if
		set temp_round to round (temp * 1.0)
		return cond & " " & temp_round & "°C"
	end tell
end tell

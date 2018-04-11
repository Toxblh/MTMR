if application "VOX" is running then
	tell application "VOX"
		if player state is 1 then
			return (get artist) & " – " & (get track)
		else
			return ""
		end if
	end tell
end if
return ""

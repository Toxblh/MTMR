if application "iTunes" is running then
	tell application "iTunes"
		if player state is playing then
			return (get artist of current track) & " – " & (get name of current track)
		else
			return ""
		end if
	end tell
end if
return ""

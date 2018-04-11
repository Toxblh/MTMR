if application "iTunes" is running then
	tell application "iTunes"
		if player state is playing then
			next track
		end if
	end tell
end if

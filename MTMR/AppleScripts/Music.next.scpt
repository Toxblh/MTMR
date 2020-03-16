if application "Music" is running then
	tell application "Music"
		if player state is playing then
			next track
		end if
	end tell
end if

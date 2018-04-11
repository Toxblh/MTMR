if application "Spotify" is running then
	tell application "Spotify"
		if player state is playing then
			next track
		end if
	end tell
end if

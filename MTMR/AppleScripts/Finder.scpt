tell application "Finder"
	if not (exists window 1) then
		make new Finder window
		set target of front window to path to home folder as string
	end if
	activate
end tell

tell application "Finder"
	make new Finder window
	set target of front window to path to home folder as string
	activate
end tell

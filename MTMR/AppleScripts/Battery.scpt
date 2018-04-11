set theList to paragraphs of text of (do shell script "pmset -g batt")
set percent to word 6 of theList's item 2
set charge to word 7 of theList's item 2

if (charge = "charging") then
	set iconC to "⚡️"
else
	set iconC to ""
end if

set remainingRaw to my split(theList's item 2, " ")
set remainingTime to remainingRaw's item 5

if (remainingTime = "(no") then
	set strTime to " (?)"
else if (remainingTime = "0:00") then
	set strTime to ""
else
	set strTime to " (" & remainingTime & ")"
end if

return iconC & percent & "%" & strTime

to split(someText, delimiter)
	set AppleScript's text item delimiters to delimiter
	set someText to someText's text items
	set AppleScript's text item delimiters to {""}
	return someText
end split

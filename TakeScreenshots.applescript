-- Tappy App Store Screenshots
-- Run this in Script Editor to capture each state

set outputDir to "/Users/castao/Desktop/KeyboardSoundApp/AppStoreScreenshots_raw/"
do shell script "mkdir -p " & quoted form of outputDir

-- Bring Tappy to front
tell application "Tappy" to activate
delay 1

-- Get window bounds
tell application "System Events"
	tell process "Tappy"
		set w to window 1
		set p to position of w
		set s to size of w
		set x1 to item 1 of p
		set y1 to item 2 of p
		set w1 to item 1 of s
		set h1 to item 2 of s
	end tell
end tell

-- Screenshot 1: Farming selected (current state)
tell application "Tappy" to activate
delay 0.3
do shell script "screencapture -R " & x1 & "," & y1 & "," & w1 & "," & h1 & " -x " & quoted form of (outputDir & "01_farming.png")

-- Screenshot 2: Click Plastic Tapping
tell application "System Events"
	tell process "Tappy"
		set clickX to x1 + 100
		set clickY to y1 + 130
		click at {clickX, clickY}
	end tell
end tell
delay 0.5
tell application "Tappy" to activate
delay 0.3
do shell script "screencapture -R " & x1 & "," & y1 & "," & w1 & "," & h1 & " -x " & quoted form of (outputDir & "02_plastic.png")

-- Screenshot 3: Click Sword Battle
tell application "System Events"
	tell process "Tappy"
		set clickX to x1 + 440
		set clickY to y1 + 130
		click at {clickX, clickY}
	end tell
end tell
delay 0.5
tell application "Tappy" to activate
delay 0.3
do shell script "screencapture -R " & x1 & "," & y1 & "," & w1 & "," & h1 & " -x " & quoted form of (outputDir & "03_sword.png")

-- Screenshot 4: Click Bubble
tell application "System Events"
	tell process "Tappy"
		set clickX to x1 + 600
		set clickY to y1 + 130
		click at {clickX, clickY}
	end tell
end tell
delay 0.5
tell application "Tappy" to activate
delay 0.3
do shell script "screencapture -R " & x1 & "," & y1 & "," & w1 & "," & h1 & " -x " & quoted form of (outputDir & "04_bubble.png")

display notification "Screenshots saved to AppStoreScreenshots_raw!" with title "Tappy Screenshots"

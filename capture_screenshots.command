#!/bin/bash
OUTPUT_DIR="/Users/castao/Desktop/KeyboardSoundApp/AppStoreScreenshots_raw"
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/debug.log"
echo "Script started at $(date)" > "$LOG"

# Helper: capture Tappy window in a given state
capture_state() {
    local FILENAME="$1"
    
    # Bring Tappy to front so it looks active
    osascript -e 'tell application "Tappy" to activate' 2>/dev/null || \
    osascript -e 'tell application "Tappy" to activate' 2>/dev/null
    sleep 0.8

    # Get window position
    RAW=$(osascript -e '
tell application "System Events"
    set tappyProc to first process whose name contains "Tappy"
    tell tappyProc
        set w to window 1
        set p to position of w
        set s to size of w
        return ((item 1 of p) as text) & " " & ((item 2 of p) as text) & " " & ((item 1 of s) as text) & " " & ((item 2 of s) as text)
    end tell
end tell' 2>&1)
    
    echo "Window bounds for $FILENAME: $RAW" >> "$LOG"
    X=$(echo "$RAW" | awk '{print $1}')
    Y=$(echo "$RAW" | awk '{print $2}')
    W=$(echo "$RAW" | awk '{print $3}')
    H=$(echo "$RAW" | awk '{print $4}')
    
    if [[ -z "$X" || "$X" == "0" ]]; then
        echo "ERROR: Could not get window position" >> "$LOG"
        screencapture -x "$OUTPUT_DIR/fullscreen_$FILENAME.png"
    else
        screencapture -R "${X},${Y},${W},${H}" -x "$OUTPUT_DIR/${FILENAME}.png"
        echo "Saved: ${FILENAME}.png (region ${W}x${H} at ${X},${Y})" >> "$LOG"
    fi
}

# === State 1: Farming selected (current state) ===
capture_state "01_farming"
sleep 0.5

# === State 2: Click Plastic Tapping card ===
osascript -e '
tell application "System Events"
    set tappyProc to first process whose name contains "Tappy"
    tell tappyProc
        -- Click first pack card (Plastic Tapping)
        set w to window 1
        set p to position of w
        set x1 to (item 1 of p) + 100
        set y1 to (item 2 of p) + 130
        click at {x1, y1}
    end tell
end tell' 2>/dev/null
sleep 0.5
capture_state "02_plastic_tapping"
sleep 0.5

# === State 3: Click Sword Battle card ===
osascript -e '
tell application "System Events"
    set tappyProc to first process whose name contains "Tappy"
    tell tappyProc
        set w to window 1
        set p to position of w
        set x1 to (item 1 of p) + 440
        set y1 to (item 2 of p) + 130
        click at {x1, y1}
    end tell
end tell' 2>/dev/null
sleep 0.5
capture_state "03_sword_battle"
sleep 0.5

# === State 4: Click Bubble card ===
osascript -e '
tell application "System Events"
    set tappyProc to first process whose name contains "Tappy"
    tell tappyProc
        set w to window 1
        set p to position of w
        set x1 to (item 1 of p) + 600
        set y1 to (item 2 of p) + 130
        click at {x1, y1}
    end tell
end tell' 2>/dev/null
sleep 0.5
capture_state "04_bubble"

echo "All screenshots done!" >> "$LOG"
cat "$LOG"
echo ""
echo "Check: $OUTPUT_DIR"

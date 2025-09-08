#!/bin/bash
# check for audio files created by ai&i

RECORDINGS_DIR="$HOME/Documents/ai&i-recordings"

echo "🔍 checking for audio files in: $RECORDINGS_DIR"
echo ""

if [ -d "$RECORDINGS_DIR" ]; then
    echo "📁 files in recordings folder:"
    ls -lh "$RECORDINGS_DIR" | grep -E "mic_|system_"
    echo ""
    
    # find the latest pair
    LATEST_TIMESTAMP=$(ls "$RECORDINGS_DIR" | grep -E "^mic_" | sed 's/mic_\([0-9]*\)\.wav/\1/' | sort -n | tail -1)
    
    if [ -n "$LATEST_TIMESTAMP" ]; then
        echo "📊 latest recording pair (timestamp: $LATEST_TIMESTAMP):"
        
        MIC_FILE="$RECORDINGS_DIR/mic_$LATEST_TIMESTAMP.wav"
        SYSTEM_FILE="$RECORDINGS_DIR/system_$LATEST_TIMESTAMP.wav"
        
        if [ -f "$MIC_FILE" ]; then
            echo "  ✅ mic audio: $(ls -lh "$MIC_FILE" | awk '{print $5}')"
        else
            echo "  ❌ mic audio: not found"
        fi
        
        if [ -f "$SYSTEM_FILE" ]; then
            echo "  ✅ system audio: $(ls -lh "$SYSTEM_FILE" | awk '{print $5}')"
        else
            echo "  ❌ system audio: not found"
        fi
        
        echo ""
        echo "🎬 ready to mix with ffmpeg:"
        echo "  ffmpeg -i mic_$LATEST_TIMESTAMP.wav -i system_$LATEST_TIMESTAMP.wav -filter_complex amix mixed_$LATEST_TIMESTAMP.wav"
    else
        echo "❌ no recordings found"
    fi
else
    echo "❌ recordings folder doesn't exist: $RECORDINGS_DIR"
fi
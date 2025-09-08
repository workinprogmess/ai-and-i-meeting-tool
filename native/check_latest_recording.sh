#!/bin/bash

# find and analyze the latest recording

RECORDINGS_DIR="$HOME/Documents/AI-and-I-Recordings"
echo "🎵 checking latest recording..."
echo ""

# get latest file
LATEST=$(ls -t "$RECORDINGS_DIR"/*.m4a 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
    echo "❌ no recordings found"
    exit 1
fi

echo "📁 latest: $(basename "$LATEST")"
echo "📅 created: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$LATEST")"
echo ""

# get file info
echo "📊 technical details:"
ffprobe -v quiet -show_format -show_streams "$LATEST" 2>/dev/null | grep -E "(codec_name|sample_rate|channels|duration|bit_rate)" | head -10

echo ""
echo "🎧 to play: afplay \"$LATEST\""
echo "🔍 to analyze: ffmpeg -i \"$LATEST\" -af astats -f null -"
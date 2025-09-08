#!/bin/bash

# monitor audio device switches in real-time

echo "🎧 monitoring audio device switches..."
echo "start your recording and switch devices"
echo "press ctrl+c to stop monitoring"
echo ""

# watch for device changes and audio events
log stream --predicate 'process == "AI-and-I" AND (eventMessage CONTAINS "device" OR eventMessage CONTAINS "airpod" OR eventMessage CONTAINS "input" OR eventMessage CONTAINS "agc" OR eventMessage CONTAINS "format")' --style compact | while read line; do
    # extract timestamp and message
    echo "$line" | grep -E "(🎤|🎧|📊|agc|airpod|device|format)" 
done
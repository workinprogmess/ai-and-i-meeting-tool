#!/bin/bash

# Create dock icon with text overlay
echo "Creating dock icon..."
sips -s format png --resampleHeightWidth 512 512 icon.icns --out temp_dock.png 2>/dev/null

# Create a simple tray icon using existing icon but smaller
echo "Creating tray icon..." 
sips -s format png --resampleHeightWidth 20 20 icon.icns --out temp_tray.png 2>/dev/null

# Use ImageMagick if available, otherwise use what we have
if command -v convert >/dev/null 2>&1; then
    echo "Using ImageMagick to add text..."
    # Create dock icon with text
    convert -size 512x512 xc:white -fill black -pointsize 120 -gravity center -annotate +0+0 "ai&i" dock-icon.png
    
    # Create tray icon with text  
    convert -size 20x20 xc:none -fill black -pointsize 10 -gravity center -annotate +0+0 "ai" tray-icon.png
    
    echo "Icons created with text!"
else
    echo "ImageMagick not available, using simpler approach..."
    # Use the existing converted icons
    mv temp_dock.png dock-icon.png 2>/dev/null || echo "Dock icon already exists"
    mv temp_tray.png tray-icon.png 2>/dev/null || echo "Tray icon already exists"
fi

rm -f temp_*.png

#!/usr/bin/env bash
set -euo pipefail

MAX_SCROLLS=${1:-20}

echo "Starting LinkedIn auto-liker for $MAX_SCROLLS scrolls..."
echo "Press Ctrl+C to stop anytime."
echo ""

for i in $(seq 1 "$MAX_SCROLLS"); do
  adb shell uiautomator dump /sdcard/screen.xml > /dev/null 2>&1
  adb pull /sdcard/screen.xml /tmp/screen.xml > /dev/null 2>&1

  python3 << 'PYEOF'
import xml.dom.minidom, re, subprocess, time

dom = xml.dom.minidom.parse('/tmp/screen.xml')
nodes = dom.getElementsByTagName('node')

tapped = 0
for n in nodes:
    desc = n.getAttribute('content-desc')
    bounds = n.getAttribute('bounds')
    # Only match the actual "no reaction" like button
    if desc.strip() == 'Reaction button state: no reaction':
        m = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
        if m:
            cx = (int(m.group(1)) + int(m.group(3))) // 2
            cy = (int(m.group(2)) + int(m.group(4))) // 2
            # Like buttons are always in the left area of the action bar
            if 150 < cx < 350:
                subprocess.run(['adb', 'shell', 'input', 'tap', str(cx), str(cy)], capture_output=True)
                time.sleep(0.4)
                tapped += 1

print(f"Liked {tapped} post(s)")
PYEOF

  adb shell input swipe 610 2200 610 300 1000
  sleep 3
done

echo ""
echo "Done - $MAX_SCROLLS scrolls completed"

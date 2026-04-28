#!/usr/bin/env bash
set -euo pipefail

MAX_POSTS=${1:-5}

echo "Starting LinkedIn auto-commenter for $MAX_POSTS posts..."
echo "Press Ctrl+C to stop anytime."
echo ""

COMMENTED=0

for i in $(seq 1 "$MAX_POSTS"); do
  adb shell uiautomator dump /sdcard/screen.xml > /dev/null 2>&1
  adb pull /sdcard/screen.xml /tmp/screen.xml > /dev/null 2>&1

  RESULT=$(python3 << 'PYEOF'
import xml.dom.minidom, re, subprocess, time

dom = xml.dom.minidom.parse('/tmp/screen.xml')
nodes = dom.getElementsByTagName('node')

# Find post text and comment buttons
posts = []
comment_btn = None

for n in nodes:
    text = n.getAttribute('text')
    desc = n.getAttribute('content-desc')
    bounds = n.getAttribute('bounds')

    if desc.strip() == 'Comment' and not comment_btn:
        m = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds)
        if m:
            cx = (int(m.group(1)) + int(m.group(3))) // 2
            cy = (int(m.group(2)) + int(m.group(4))) // 2
            if 350 < cx < 600:
                comment_btn = (cx, cy)

    if text and len(text) > 30:
        posts.append(text[:200])

if not comment_btn:
    print("NO_COMMENT_BTN")
else:
    # Pick a comment based on post content
    post_text = " ".join(posts).lower()

    if any(w in post_text for w in ["ai", "artificial intelligence", "machine learning", "llm", "gpt", "chatgpt", "openai", "model"]):
        comment = "Great insights on AI. The pace of innovation right now is incredible, and posts like this help make sense of it all."
    elif any(w in post_text for w in ["startup", "founder", "fundraising", "venture", "investor", "saas", "mvp"]):
        comment = "Love this perspective. The startup journey is all about execution over ideas, and this captures it well."
    elif any(w in post_text for w in ["developer", "coding", "software", "engineer", "programming", "code", "build"]):
        comment = "This resonates a lot. Building in public and shipping fast matters more than chasing perfection."
    elif any(w in post_text for w in ["marketing", "growth", "sales", "customer", "content", "social media"]):
        comment = "Such a valuable take. The best growth strategies come from understanding people first, not just tactics."
    elif any(w in post_text for w in ["career", "job", "hiring", "interview", "layoff", "resign", "promot"]):
        comment = "Really helpful advice. The job market keeps evolving, and adaptability is the real superpower."
    elif any(w in post_text for w in ["design", "ux", "ui", "user experience", "product"]):
        comment = "Well said. Great design is invisible, but its impact is undeniable."
    elif any(w in post_text for w in ["focus", "productivity", "mental", "health", "meditation", "mindfulness"]):
        comment = "Needed to hear this. Protecting your focus is the most underrated productivity hack."
    elif any(w in post_text for w in ["leadership", "management", "team", "culture", "hiring"]):
        comment = "Strong leadership is rare. Thanks for sharing what actually works in building great teams."
    elif any(w in post_text for w in ["money", "finance", "invest", "passive", "income", "earning"]):
        comment = "Appreciate you sharing this. Financial literacy is something more people need to talk about."
    elif any(w in post_text for w in ["freelance", "freelancer", "remote", "work from"]):
        comment = "The future of work is freelance and remote. Thanks for sharing your experience on this."
    else:
        comment = "Great post. Thanks for sharing your thoughts on this."

    print(f"BTN:{comment_btn[0]},{comment_btn[1]}")
    print(f"COMMENT:{comment}")
PYEOF
)

  if [[ "$RESULT" == "NO_COMMENT_BTN" ]]; then
    echo "Scroll $i: No comment button found, scrolling..."
    adb shell input swipe 610 2200 610 300 1000
    sleep 3
    continue
  fi

  BTN_X=$(echo "$RESULT" | grep "^BTN:" | cut -d: -f2 | cut -d, -f1)
  BTN_Y=$(echo "$RESULT" | grep "^BTN:" | cut -d: -f2 | cut -d, -f2)
  COMMENT_TEXT=$(echo "$RESULT" | grep "^COMMENT:" | cut -d: -f2-)

  if [[ -z "$BTN_X" || -z "$BTN_Y" || -z "$COMMENT_TEXT" ]]; then
    echo "Scroll $i: Failed to parse, scrolling..."
    adb shell input swipe 610 2200 610 300 1000
    sleep 3
    continue
  fi

  echo "Scroll $i: Commenting on post..."

  # Tap Comment button
  adb shell input tap "$BTN_X" "$BTN_Y"
  sleep 3

  # Check if comment input appeared
  adb shell uiautomator dump /sdcard/screen.xml > /dev/null 2>&1
  adb pull /sdcard/screen.xml /tmp/screen.xml > /dev/null 2>&1

  HAS_INPUT=$(python3 -c "
import xml.dom.minidom
dom = xml.dom.minidom.parse('/tmp/screen.xml')
for n in dom.getElementsByTagName('node'):
    if 'Add a comment' in n.getAttribute('text'):
        print('YES')
        break
")

  if [[ "$HAS_INPUT" != "YES" ]]; then
    echo "  Comment sheet did not open, skipping..."
    adb shell input keyevent 4
    sleep 2
    adb shell input swipe 610 2200 610 300 1000
    sleep 3
    continue
  fi

  # Type comment word by word
  python3 << PYEOF
import subprocess, time
comment = """$COMMENT_TEXT"""
for word in comment.split():
    clean = ''.join(c for c in word if c.isalnum() or c in '.,!?;:-_@#')
    if clean:
        subprocess.run(['adb', 'shell', 'input', 'text', clean], check=True, capture_output=True)
        subprocess.run(['adb', 'shell', 'input', 'keyevent', '62'], check=True, capture_output=True)
        time.sleep(0.1)
subprocess.run(['adb', 'shell', 'input', 'keyevent', '67'], check=True, capture_output=True)
PYEOF

  sleep 1

  # Find and tap send button
  adb shell uiautomator dump /sdcard/screen.xml > /dev/null 2>&1
  adb pull /sdcard/screen.xml /tmp/screen.xml > /dev/null 2>&1

  SEND_XY=$(python3 -c "
import xml.dom.minidom, re
dom = xml.dom.minidom.parse('/tmp/screen.xml')
for n in dom.getElementsByTagName('node'):
    if n.getAttribute('text') == 'Comment' and n.getAttribute('enabled') == 'true':
        b = n.getAttribute('bounds')
        m = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            print((int(m.group(1))+int(m.group(3)))//2, (int(m.group(2))+int(m.group(4)))//2)
            break
")

  if [[ -n "$SEND_XY" ]]; then
    SEND_X=$(echo "$SEND_XY" | cut -d' ' -f1)
    SEND_Y=$(echo "$SEND_XY" | cut -d' ' -f2)
    adb shell input tap "$SEND_X" "$SEND_Y"
    sleep 3
    COMMENTED=$((COMMENTED + 1))
    echo "  Comment sent!"
  else
    echo "  Send button not found"
    adb shell input keyevent 4
    sleep 2
  fi

  # Go back to feed
  adb shell input keyevent 4
  sleep 2
  adb shell input swipe 610 2200 610 300 1000
  sleep 3
done

echo ""
echo "Done - commented on $COMMENTED post(s)"

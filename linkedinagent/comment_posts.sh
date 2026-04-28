#!/usr/bin/env bash
set -euo pipefail

MAX_POSTS=${1:-5}
API_KEY="${OPENROUTER_API_KEY:-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}"

echo "Starting LinkedIn AI auto-commenter for $MAX_POSTS posts..."
echo "Press Ctrl+C to stop anytime."
echo ""

COMMENTED=0

for i in $(seq 1 "$MAX_POSTS"); do
  adb shell uiautomator dump /sdcard/screen.xml > /dev/null 2>&1
  adb pull /sdcard/screen.xml /tmp/screen.xml > /dev/null 2>&1

  RESULT=$(python3 << PYEOF
import xml.dom.minidom, re, subprocess, time, json, urllib.request

dom = xml.dom.minidom.parse('/tmp/screen.xml')
nodes = dom.getElementsByTagName('node')

# Extract post context: author + headline + post text
post_author = ""
post_headline = ""
post_body = ""
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

    if text:
        if not post_author and len(text) < 50 and not text.startswith("http"):
            post_author = text
        elif len(text) > 30 and len(text) < 200:
            post_body = text
        elif len(text) >= 200:
            post_body = text[:500]

if not comment_btn:
    print("NO_COMMENT_BTN")
else:
    context = f"Author: {post_author}\nPost: {post_body[:300]}"

    api_key = "$API_KEY"
    prompt = f"""You are replying to a LinkedIn post. Here is the post:

{context}

Write ONE short reply (10-20 words) that sounds like a real person wrote it. Be natural and specific to this post content. No hashtags. No emojis. Just the reply text."""

    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps({
            "model": "openrouter/free",
            "messages": [
                {"role": "user", "content": f"How many r's are in the word 'strawberry'?"},
                {"role": "assistant", "content": "There are 3 r's in strawberry."},
                {"role": "user", "content": prompt}
            ],
            "reasoning": {"enabled": True}
        }).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
    )

    try:
        resp = json.loads(urllib.request.urlopen(req, timeout=20).read())
        comment = resp['choices'][0]['message']['content'].strip().strip('"').strip("'")
        words = comment.split()
        if len(words) > 25:
            comment = " ".join(words[:25])
        print(f"BTN:{comment_btn[0]},{comment_btn[1]}")
        print(f"COMMENT:{comment}")
    except Exception as e:
        print(f"API_ERROR:{e}")
        print(f"BTN:{comment_btn[0]},{comment_btn[1]}")
        print("COMMENT:Great post, thanks for sharing!")
PYEOF
)

  if [[ "$RESULT" == "NO_COMMENT_BTN" ]]; then
    echo "Scroll $i: No comment button found, scrolling..."
    adb shell input swipe 610 2400 610 200 1200
    sleep 3
    continue
  fi

  if echo "$RESULT" | grep -q "^API_ERROR"; then
    BTN_X=$(echo "$RESULT" | sed -n 's/^BTN:\([0-9]*\),\([0-9]*\)/\1/p')
    BTN_Y=$(echo "$RESULT" | sed -n 's/^BTN:\([0-9]*\),\([0-9]*\)/\2/p')
    ERROR_MSG=$(echo "$RESULT" | sed -n 's/^API_ERROR:\(.*\)/\1/p')
    COMMENT_TEXT="Great post, thanks for sharing!"
    echo "Scroll $i: API error ($ERROR_MSG), using fallback"
  else
    BTN_X=$(echo "$RESULT" | grep "^BTN:" | cut -d: -f2 | cut -d, -f1)
    BTN_Y=$(echo "$RESULT" | grep "^BTN:" | cut -d: -f2 | cut -d, -f2)
    COMMENT_TEXT=$(echo "$RESULT" | grep "^COMMENT:" | cut -d: -f2-)
  fi

  if [[ -z "$BTN_X" || -z "$BTN_Y" ]]; then
    echo "Scroll $i: Failed to parse, scrolling..."
    adb shell input swipe 610 2400 610 200 1200
    sleep 3
    continue
  fi

  echo "Scroll $i: \"$COMMENT_TEXT\""

  adb shell input tap "$BTN_X" "$BTN_Y"
  sleep 3

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
    echo "  Sheet did not open, skipping..."
    adb shell input keyevent 4
    sleep 2
    adb shell input swipe 610 2400 610 200 1200
    sleep 3
    continue
  fi

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
    echo "  Sent!"
  else
    echo "  Send button not found"
    adb shell input keyevent 4
    sleep 2
  fi

  adb shell input keyevent 4
  sleep 2
  adb shell input swipe 610 2400 610 200 1200
  sleep 3
done

echo ""
echo "Done - commented on $COMMENTED post(s)"

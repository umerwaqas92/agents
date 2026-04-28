#!/usr/bin/env bash
set -euo pipefail

# Cross-post to LinkedIn + Facebook + X in one shot
# Usage:
#   ./post.sh "Post text here" [image1] [image2] ...
#   ./post.sh -c "Multi-line
# post content" [image ...]

MODE=text
CONTENT=""
IMAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--content)
      MODE=content
      shift
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -z "$CONTENT" ]]; then
        CONTENT="$1"
      else
        IMAGES+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ -z "$CONTENT" ]]; then
  echo "Usage: $0 [-c] \"post content\" [image1 image2 ...]"
  exit 1
fi

# ----------------------------------------------------------------
# 1. Generate safe ADB text
# ----------------------------------------------------------------
type_adb_text() {
  python3 - "$1" << 'PY'
import subprocess, sys, time
text = sys.argv[1]
for word in text.split():
    subprocess.run(['adb', 'shell', 'input', 'text', word], check=True, capture_output=True)
    subprocess.run(['adb', 'shell', 'input', 'keyevent', '62'], check=True, capture_output=True)
    time.sleep(0.12)
subprocess.run(['adb', 'shell', 'input', 'keyevent', '67'], check=True)
PY
}

type_adb_lines() {
  python3 - "$1" << 'PY'
import subprocess, sys, time
lines = sys.argv[1].split('\n')
for i, line in enumerate(lines):
    if line.strip():
        for word in line.split():
            subprocess.run(['adb', 'shell', 'input', 'text', word], check=True, capture_output=True)
            subprocess.run(['adb', 'shell', 'input', 'keyevent', '62'], check=True, capture_output=True)
            time.sleep(0.12)
        subprocess.run(['adb', 'shell', 'input', 'keyevent', '67'], check=True)
    if i < len(lines) - 1:
        subprocess.run(['adb', 'shell', 'input', 'keyevent', '66'], check=True)
        time.sleep(0.3)
PY
}

# ----------------------------------------------------------------
# 2. Push images to device
# ----------------------------------------------------------------
push_images() {
  if [[ ${#IMAGES[@]} -eq 0 ]]; then
    return
  fi
  echo "Pushing ${#IMAGES[@]} image(s) to device..."
  for img in "${IMAGES[@]}"; do
    fname=$(basename "$img")
    adb push "$img" "/sdcard/DCIM/Camera/$fname" > /dev/null 2>&1
    adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
      -d "file:///sdcard/DCIM/Camera/$fname" > /dev/null 2>&1
  done
  sleep 2
}

# ----------------------------------------------------------------
# 3. Post to LinkedIn
# ----------------------------------------------------------------
post_linkedin() {
  echo "--- LinkedIn ---"
  adb shell monkey -p com.linkedin.android -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  sleep 4

  # Open composer via Post tab
  adb shell input tap 610 2592
  sleep 3

  # Type content
  if [[ "$MODE" == "content" ]]; then
    type_adb_lines "$CONTENT"
  else
    type_adb_text "$CONTENT"
  fi

  # Attach images
  if [[ ${#IMAGES[@]} -gt 0 ]]; then
    adb shell input tap 946 1530  # Photo button (composer bottom, NOT bottom nav)
    sleep 3
    # Find FIRST image dynamically via XML
    adb shell uiautomator dump /sdcard/screen.xml > /dev/null 2>&1
    adb pull /sdcard/screen.xml /tmp/screen.xml > /dev/null 2>&1
    IFS=' ' read -r IX IY <<< "$(python3 -c "
import xml.dom.minidom, re
dom = xml.dom.minidom.parse('/tmp/screen.xml')
for n in dom.getElementsByTagName('node'):
    d = n.getAttribute('content-desc')
    b = n.getAttribute('bounds')
    if 'Photo taken on' in d:
        m = re.search(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', b)
        if m:
            print((int(m.group(1))+int(m.group(3)))//2, (int(m.group(2))+int(m.group(4)))//2)
            break
")"
    if [[ -n "$IX" ]]; then
      adb shell input tap "$IX" "$IY"
      sleep 1
    fi
    adb shell input tap 1008 2484  # Done
    sleep 3
    adb shell input tap 1082 206   # Next
    sleep 2
  fi

  # Publish
  adb shell input tap 1087 194
  sleep 4
  echo "  ✓ Posted to LinkedIn"
}

# ----------------------------------------------------------------
# 4. Post to Facebook
# ----------------------------------------------------------------
post_facebook() {
  echo "--- Facebook ---"
  adb shell am start -n com.facebook.katana/.LoginActivity > /dev/null 2>&1
  sleep 5

  # Create → Post
  adb shell input tap 878 188
  sleep 2
  adb shell input tap 878 375
  sleep 4

  # Type content
  adb shell input tap 610 669
  sleep 1
  if [[ "$MODE" == "content" ]]; then
    type_adb_lines "$CONTENT"
  else
    type_adb_text "$CONTENT"
  fi

  # Attach images
  if [[ ${#IMAGES[@]} -gt 0 ]]; then
    adb shell input tap 141 1530  # Photo/video
    sleep 3

    # Select multiple
    adb shell input tap 899 374
    sleep 1
    for i in $(seq 1 ${#IMAGES[@]}); do
      case $i in
        1) adb shell input tap 203 728 ;;
        2) adb shell input tap 611 728 ;;
        3) adb shell input tap 1017 728 ;;
        4) adb shell input tap 203 1269 ;;
      esac
      sleep 0.3
    done
    sleep 1
    adb shell input tap 1077 2523  # Next
    sleep 3
  fi

  # Next → Post
  adb shell input tap 1095 188
  sleep 2
  adb shell input tap 1096 188
  sleep 4
  echo "  ✓ Posted to Facebook"
}

# ----------------------------------------------------------------
# 5. Post to X (Twitter)
# ----------------------------------------------------------------
post_x() {
  echo "--- X (Twitter) ---"
  adb shell monkey -p com.twitter.android -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
  sleep 5

  # FAB → Post
  adb shell input tap 1088 2364
  sleep 2
  adb shell input tap 1088 2364
  sleep 3

  # Type content
  type_adb_text "$CONTENT"

  # Publish
  adb shell input tap 1073 206
  sleep 3
  echo "  ✓ Posted to X"
}

# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------
push_images

post_linkedin
post_facebook
# Uncomment below to post to X as well:
# post_x

echo ""
echo "All done!"

#!/usr/bin/env bash
# Capture a page at 375, 768, 1440 and 2560px, in light and dark, with headless Chrome.
# Usage: screenshot.sh <url> <out-dir> [height]
# Output: <out-dir>/<width>-<light|dark>.png
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <url> <out-dir> [height]" >&2
    exit 2
fi

url=$1
out_dir=$2
height=${3:-900}
chrome=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}

if [[ ! -x $chrome ]]; then
    echo "Chrome not found at $chrome (set CHROME=...)" >&2
    exit 1
fi

mkdir -p "$out_dir"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Headless Chrome will not go below ~500px: render 375px inside an iframe of that width.
wrapper="$work/375.html"
cat > "$wrapper" << EOF
<!doctype html><html><body style="margin:0">
<iframe src="$url" style="width:375px;height:${height}px;border:0"></iframe>
</body></html>
EOF

for theme in light dark; do
    if [[ $theme == light ]]; then
        theme_flags=(--blink-settings=preferredColorScheme=1)
    else
        theme_flags=(--force-dark-mode --blink-settings=preferredColorScheme=0)
    fi
    for width in 375 768 1440 2560; do
        target=$url
        window_width=$width
        if [[ $width == 375 ]]; then
            target="file://$wrapper"
            window_width=500
        fi
        shot="$out_dir/$width-$theme.png"
        # Headless Chrome sometimes never exits after writing the file: bound each capture.
        if ! timeout 30 "$chrome" --headless=new --disable-gpu --hide-scrollbars \
            "${theme_flags[@]}" \
            --virtual-time-budget=3000 \
            --window-size="$window_width,$height" \
            --screenshot="$shot" \
            "$target" > /dev/null 2>&1 && [[ ! -s $shot ]]; then
            echo "FAILED $shot" >&2
            continue
        fi
        if [[ $width == 375 ]]; then
            sips --cropToHeightWidth "$height" 375 --cropOffset 0 0 "$shot" > /dev/null
        fi
        echo "$shot"
    done
done

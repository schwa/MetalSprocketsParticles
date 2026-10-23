#!/usr/bin/env bash
# Renders every sample preset into one H.264 movie for hosting online, with each preset's name at the top left and
# its comment at the bottom.
#
#   Scripts/make-reel.sh                  # writes all-effects.mp4
#   Scripts/make-reel.sh path/to/out.mp4
#
# Needs ffmpeg, ImageMagick (magick), jq, and bc. Set PARTICLES_RENDER to use an existing particles-render binary
# instead of building one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
presets="$root/Sources/MetalSprocketsParticlesSamples/Resources/Presets"
output="$(cd "$(dirname "${1:-all-effects.mp4}")" && pwd)/$(basename "${1:-all-effects.mp4}")"
width=1280
height=720
fps=30
# Looping effects show this many seconds, from one second in. Finite effects play until they finish.
clip_seconds=4
finite_seconds=10
finite="confetti flare"
bitrate=1.8M
title_font="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
body_font="/System/Library/Fonts/Supplemental/Arial.ttf"

if [[ -z "${PARTICLES_RENDER:-}" ]]; then
    swift build --package-path "$root" -c release --product particles-render
    PARTICLES_RENDER="$(swift build --package-path "$root" -c release --show-bin-path)/particles-render"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"
: > list.txt

while read -r slug; do
    name="$(jq -r .name "$presets/$slug.json")"
    comment="$(jq -r '.comment // ""' "$presets/$slug.json")"
    echo "Rendering $name"

    if [[ " $finite " == *" $slug "* ]]; then
        "$PARTICLES_RENDER" --preset "$name" --video "$slug.mov" --duration "$finite_seconds" --until-finished \
            --width "$width" --height "$height" --fps "$fps" > /dev/null
        start=0
        length="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$slug.mov")"
    else
        "$PARTICLES_RENDER" --preset "$name" --video "$slug.mov" --duration "$((clip_seconds + 1))" \
            --width "$width" --height "$height" --fps "$fps" > /dev/null
        start=1
        length=$clip_seconds
    fi

    magick -size "${width}x${height}" xc:none \
        \( -background none -font "$title_font" -pointsize 40 -fill white -stroke '#0008' -strokewidth 2 \
            label:"$name" \) -gravity northwest -geometry +40+30 -composite \
        \( -background '#0009' -font "$body_font" -pointsize 20 -fill white -size "$((width - 80))x" \
            -gravity center caption:"$comment" -bordercolor '#0009' -border 12x8 \) \
        -gravity south -geometry +0+24 -composite "$slug.png"

    fade_out="$(echo "$length - 0.3" | bc)"
    ffmpeg -v error -y -ss "$start" -t "$length" -i "$slug.mov" -i "$slug.png" -filter_complex \
        "[0:v]fps=$fps,format=yuv420p[v];[v][1:v]overlay,fade=in:d=0.3,fade=out:st=$fade_out:d=0.3" \
        -an -c:v libx264 -preset veryfast -crf 14 "segment-$slug.mp4"
    echo "file 'segment-$slug.mp4'" >> list.txt
done < <(jq -r '.[]' "$presets/index.json")

ffmpeg -v error -y -f concat -safe 0 -i list.txt -c copy master.mp4

# Two-pass H.264 at a fixed bitrate, with the index at the front so browsers can start playing before the download ends.
encode=(-c:v libx264 -preset slow -profile:v high -b:v "$bitrate" -maxrate 3M -bufsize 6M -pix_fmt yuv420p -an)
ffmpeg -v error -y -i master.mp4 "${encode[@]}" -pass 1 -f mp4 /dev/null
ffmpeg -v error -y -i master.mp4 "${encode[@]}" -pass 2 -movflags +faststart "$output"

ls -lh "$output"

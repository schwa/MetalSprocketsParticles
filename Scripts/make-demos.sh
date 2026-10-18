#!/usr/bin/env bash
# Renders the demo clips and posters in Documentation/Demos and rewrites its README from the presets.
#
#   Scripts/make-demos.sh            # every preset
#   Scripts/make-demos.sh flare fog  # only these presets (the README is always rewritten)
#
# Needs ffmpeg and jq. Set PARTICLES_RENDER to use an existing particles-render binary instead of building one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
presets="$root/Sources/MetalSprocketsParticlesSamples/Resources/Presets"
demos="$root/Documentation/Demos"
video_url="https://raw.githubusercontent.com/schwa/MetalSprocketsParticles/main/Documentation/Demos/videos"
# Finite effects play until they finish, up to this many seconds; the rest get a fixed length.
finite_seconds=15
clip_seconds=6
finite="confetti flare"

if [[ -z "${PARTICLES_RENDER:-}" ]]; then
    swift build --package-path "$root" -c release --product particles-render
    PARTICLES_RENDER="$(swift build --package-path "$root" -c release --show-bin-path)/particles-render"
fi

slugs=("$@")
if [[ ${#slugs[@]} -eq 0 ]]; then
    mapfile -t slugs < <(jq -r '.[]' "$presets/index.json")
fi

mkdir -p "$demos/videos" "$demos/posters"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for slug in "${slugs[@]}"; do
    name="$(jq -r .name "$presets/$slug.json")"
    if [[ " $finite " == *" $slug "* ]]; then
        length=(--duration "$finite_seconds" --until-finished)
    else
        length=(--duration "$clip_seconds")
    fi
    "$PARTICLES_RENDER" --preset "$name" --video "$work/$slug.mov" "${length[@]}" --width 1280 --height 720
    ffmpeg -v error -y -i "$work/$slug.mov" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart -an \
        "$demos/videos/$slug.mp4"
    # The poster is the middle frame.
    seconds="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/$slug.mov")"
    ffmpeg -v error -y -ss "$(echo "$seconds / 2" | bc -l)" -i "$work/$slug.mov" -frames:v 1 -q:v 3 \
        "$demos/posters/$slug.jpg"
done

# The README lists every preset in index.json order, with its comment, poster, and clip.
{
    echo "# MetalSprocketsParticles Demos"
    echo
    echo "Clips of every built-in preset, rendered offscreen with \`particles-render --video\` (1280×720, re-encoded to"
    echo "H.264 MP4, 30 fps, seed 0, the preset's camera). Finite effects play until they finish. Regenerate them with"
    echo "\`Scripts/make-demos.sh\`."
    echo
    echo "## Contents"
    echo
    while read -r slug; do
        echo "- [$(jq -r .name "$presets/$slug.json")](#$slug)"
    done < <(jq -r '.[]' "$presets/index.json")
    while read -r slug; do
        echo
        echo "## $(jq -r .name "$presets/$slug.json")"
        echo
        jq -r .comment "$presets/$slug.json"
        echo
        echo "[![$slug](posters/$slug.jpg)]($video_url/$slug.mp4)"
    done < <(jq -r '.[]' "$presets/index.json")
} > "$demos/README.md"

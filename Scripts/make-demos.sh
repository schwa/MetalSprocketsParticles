#!/usr/bin/env bash
# Renders the demo clips and posters in Documentation/Demos and rewrites Demos.md from the presets.
#
#   Scripts/make-demos.sh            # every preset
#   Scripts/make-demos.sh flare fog  # only these presets (Demos.md is always rewritten)
#   Scripts/make-demos.sh --index-only  # only rewrite Demos.md
#
# Needs ffmpeg and jq. Set PARTICLES_RENDER to use an existing particles-render binary instead of building one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
presets="$root/Sources/MetalSprocketsParticlesSamples/Resources/Presets"
demos="$root/Documentation/Demos"
# Relative links open GitHub's file page, which plays the movie; raw.githubusercontent.com links download it.
video_url="videos"
# Finite effects play until they finish, up to this many seconds; the rest get a fixed length.
finite_seconds=15
clip_seconds=6
finite="confetti flare"

index_only=false
if [[ "${1:-}" == "--index-only" ]]; then
    index_only=true
    shift
fi

if [[ $index_only == false && -z "${PARTICLES_RENDER:-}" ]]; then
    swift build --package-path "$root" -c release --product particles-render
    PARTICLES_RENDER="$(swift build --package-path "$root" -c release --show-bin-path)/particles-render"
fi

slugs=("$@")
if [[ $index_only == true ]]; then
    slugs=()
elif [[ ${#slugs[@]} -eq 0 ]]; then
    mapfile -t slugs < <(jq -r '.[]' "$presets/index.json")
fi

mkdir -p "$demos/videos" "$demos/posters"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for slug in "${slugs[@]+"${slugs[@]}"}"; do
    name="$(jq -r .name "$presets/$slug.json")"
    if [[ " $finite " == *" $slug "* ]]; then
        length=(--duration "$finite_seconds" --until-finished)
    else
        length=(--duration "$clip_seconds")
    fi
    "$PARTICLES_RENDER" --preset "$name" --video "$work/$slug.mov" "${length[@]}" --width 1280 --height 720
    ffmpeg -v error -y -i "$work/$slug.mov" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart -an \
        "$demos/videos/$slug.mp4"
    # The poster is the middle frame, at 640×360 so every thumbnail is the same size.
    seconds="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/$slug.mov")"
    ffmpeg -v error -y -ss "$(echo "$seconds / 2" | bc -l)" -i "$work/$slug.mov" -frames:v 1 -vf scale=640:360 -q:v 3 \
        "$demos/posters/$slug.jpg"
done

# Demos.md lists every preset in index.json order, with its comment, poster, and clip.
{
    echo "# MetalSprocketsParticles Demos"
    echo
    echo "Clips of every sample preset, rendered offscreen with \`particles-render --video\` (1280×720, re-encoded to"
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
} > "$demos/Demos.md"

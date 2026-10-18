#!/usr/bin/env bash
# Renders the demo clips and their animated previews in Documentation/Demos, and rewrites Demos.md from the presets.
#
#   Scripts/make-demos.sh                # every preset
#   Scripts/make-demos.sh flare fog      # only these presets (Demos.md is always rewritten)
#   Scripts/make-demos.sh --from-videos  # remake every preview from the existing clips, and Demos.md; no rendering
#   Scripts/make-demos.sh --index-only   # only rewrite Demos.md
#
# Needs ffmpeg, gif2webp (libwebp), and jq. Set PARTICLES_RENDER to use an existing particles-render binary instead of
# building one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
presets="$root/Sources/MetalSprocketsParticlesSamples/Resources/Presets"
demos="$root/Documentation/Demos"
# Finite effects play until they finish, up to this many seconds; the rest get a fixed length.
finite_seconds=15
clip_seconds=6
finite="confetti flare"

mode=render
case "${1:-}" in
--from-videos) mode=previews; shift ;;
--index-only) mode=index; shift ;;
esac

slugs=("$@")
if [[ $mode == index ]]; then
    slugs=()
elif [[ ${#slugs[@]} -eq 0 ]]; then
    mapfile -t slugs < <(jq -r '.[]' "$presets/index.json")
fi

if [[ $mode == render && -z "${PARTICLES_RENDER:-}" ]]; then
    swift build --package-path "$root" -c release --product particles-render
    PARTICLES_RENDER="$(swift build --package-path "$root" -c release --show-bin-path)/particles-render"
fi

mkdir -p "$demos/videos" "$demos/previews"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# An animated WebP of four seconds of the clip, from one second in, at 480 pixels wide and 15 fps. GitHub shows
# animated images inline but does not play videos from the repository.
make_preview() {
    local slug="$1"
    ffmpeg -v error -y -ss 1 -t 4 -i "$demos/videos/$slug.mp4" \
        -vf "fps=15,scale=480:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" \
        -loop 0 "$work/$slug.gif"
    gif2webp -q 60 -lossy -m 6 -mt -quiet "$work/$slug.gif" -o "$demos/previews/$slug.webp"
}

for slug in "${slugs[@]+"${slugs[@]}"}"; do
    if [[ $mode == render ]]; then
        name="$(jq -r .name "$presets/$slug.json")"
        if [[ " $finite " == *" $slug "* ]]; then
            length=(--duration "$finite_seconds" --until-finished)
        else
            length=(--duration "$clip_seconds")
        fi
        "$PARTICLES_RENDER" --preset "$name" --video "$work/$slug.mov" "${length[@]}" --width 1280 --height 720
        ffmpeg -v error -y -i "$work/$slug.mov" -c:v libx264 -pix_fmt yuv420p -crf 23 -movflags +faststart -an \
            "$demos/videos/$slug.mp4"
    fi
    make_preview "$slug"
done

# Demos.md lists every preset in index.json order, with its comment and preview. A preview links to the full clip.
{
    echo "# MetalSprocketsParticles Demos"
    echo
    echo "Every sample preset, rendered offscreen with \`particles-render --video\` (seed 0, the preset's camera). The"
    echo "previews are four-second loops; click one for the full 1280×720 clip. Regenerate them with"
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
        echo "[![$slug](previews/$slug.webp)](videos/$slug.mp4)"
    done < <(jq -r '.[]' "$presets/index.json")
} > "$demos/Demos.md"

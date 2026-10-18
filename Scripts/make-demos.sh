#!/usr/bin/env bash
# Renders an animated preview of each sample preset into Documentation/previews, and rewrites Documentation/Demos.md
# from the presets.
#
#   Scripts/make-demos.sh               # every preset
#   Scripts/make-demos.sh flare fog     # only these presets (Demos.md is always rewritten)
#   Scripts/make-demos.sh --index-only  # only rewrite Demos.md
#
# Needs ffmpeg, gif2webp (libwebp), and jq. Set PARTICLES_RENDER to use an existing particles-render binary instead of
# building one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
presets="$root/Sources/MetalSprocketsParticlesSamples/Resources/Presets"
demos="$root/Documentation"
# Finite effects play until they finish, up to this many seconds; the rest get a fixed length.
finite_seconds=15
clip_seconds=6
finite="confetti flare"

mode=render
if [[ "${1:-}" == "--index-only" ]]; then
    mode=index
    shift
fi

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

mkdir -p "$demos/previews"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# An animated WebP of four seconds of the rendered clip, from one second in, at 480 pixels wide and 15 fps. GitHub
# shows animated images inline but does not play videos from the repository.
make_preview() {
    local slug="$1"
    ffmpeg -v error -y -ss 1 -t 4 -i "$work/$slug.mov" \
        -vf "fps=15,scale=480:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer" \
        -loop 0 "$work/$slug.gif"
    gif2webp -q 60 -lossy -m 6 -mt -quiet "$work/$slug.gif" -o "$demos/previews/$slug.webp"
}

for slug in "${slugs[@]+"${slugs[@]}"}"; do
    name="$(jq -r .name "$presets/$slug.json")"
    if [[ " $finite " == *" $slug "* ]]; then
        length=(--duration "$finite_seconds" --until-finished)
    else
        length=(--duration "$clip_seconds")
    fi
    "$PARTICLES_RENDER" --preset "$name" --video "$work/$slug.mov" "${length[@]}" --width 960 --height 540
    make_preview "$slug"
done

# Demos.md lists every preset in index.json order, with its comment and preview.
{
    echo "# MetalSprocketsParticles Demos"
    echo
    echo "Every sample preset as a four-second loop, rendered offscreen with \`particles-render --video\` (seed 0, the"
    echo "preset's camera). Regenerate them with \`Scripts/make-demos.sh\`."
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
        echo "![$slug](previews/$slug.webp)"
    done < <(jq -r '.[]' "$presets/index.json")
} > "$demos/Demos.md"

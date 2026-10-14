#!/bin/zsh
# Runs the last open-source Periphery (MIT). The project went commercial and its
# repository is archived, so Homebrew deprecated the formula; the release zip on
# GitHub stays, and this pins it by version and checksum. Arguments go to periphery.
set -euo pipefail

version=3.8.0
sha256=07d4e286e31dd79164df39097e0b59f533c94badbe18158464a455ea88a166d7
dir=${XDG_CACHE_HOME:-$HOME/Library/Caches}/claude_counter/periphery-$version

if [[ ! -x $dir/periphery ]]; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/periphery.zip" \
        "https://github.com/peripheryapp/periphery/releases/download/$version/periphery-$version.zip"
    actual=$(shasum -a 256 "$tmp/periphery.zip" | cut -d' ' -f1)
    if [[ $actual != $sha256 ]]; then
        print -u2 "periphery.sh: checksum mismatch for periphery-$version.zip: $actual"
        exit 1
    fi
    mkdir -p "$dir"
    unzip -qo "$tmp/periphery.zip" -d "$dir"
fi

exec "$dir/periphery" "$@"

#!/usr/bin/env bash
# Copies every image pinned in image/pins.env to OrielOS's own registry (ghcr.io/orielos/mirror),
# keeping its digest, so builds still find it after the upstream registry stops serving it.
# Images already copied are left as they are. Needs skopeo, and a login to ghcr.io with
# permission to write packages (CI uses the workflow's token).
#
# Usage: tools/mirror-pins.sh [--pins FILE] [--check] [--help]
#   --pins FILE   pins file (default image/pins.env)
#   --check       only report which pins are copied, without copying anything
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
CHECK=0
# shellcheck source=lib/pins.sh
source "$ROOT/tools/lib/pins.sh"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pins)
            [[ $# -ge 2 ]] || die "--pins needs a file"
            PINS="$2"
            shift 2
            ;;
        --check)
            CHECK=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown option: $1"
            ;;
    esac
done

command -v skopeo >/dev/null 2>&1 || die "skopeo is not installed"
[[ -r "$PINS" ]] || die "cannot read $PINS"
# shellcheck source=/dev/null
source "$PINS"

missing=0
for var in "${PINNED_IMAGES[@]}"; do
    ref="${!var:-}"
    [[ "$ref" =~ ^[a-z0-9.-]+(/[a-z0-9._-]+)+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]] ||
        die "$var in $PINS is not an image pinned as name:tag@sha256:<digest>"
    copy="$(mirror_ref "$ref")"
    if skopeo inspect --raw "docker://$copy" >/dev/null 2>&1; then
        printf '%s: already copied (%s)\n' "$var" "$copy"
        continue
    fi
    if [[ "$CHECK" -eq 1 ]]; then
        printf '%s: not copied yet (%s)\n' "$var" "$copy"
        missing=$((missing + 1))
        continue
    fi
    upstream="${ref%@*}"
    upstream="${upstream%:*}@${ref##*@}"
    printf '%s: copying %s to %s\n' "$var" "$upstream" "${copy%@*}:$(mirror_tag "$ref")"
    # --all keeps the whole manifest list, so the copy has the same digest as the pin.
    skopeo copy --all --preserve-digests --retry-times 3 \
        "docker://$upstream" "docker://${copy%@*}:$(mirror_tag "$ref")"
    skopeo inspect --raw "docker://$copy" >/dev/null ||
        die "$var: the copy isn't served by the digest it was pinned by"
done
if [[ "$missing" -gt 0 ]]; then
    exit 1
fi

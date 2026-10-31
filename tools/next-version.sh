#!/usr/bin/env bash
# Prints the version the next published build gets, from the tags already published, read one per
# line on standard input. Versions are vMAJOR.MINOR.PATCH: PATCH runs from 0 to 10 and MINOR from 0
# to 100, and each rolls over into the next number up, so v0.0.10 is followed by v0.1.0 and
# v0.100.10 by v1.0.0. MAJOR has no limit. Tags that aren't versions, such as testing, stable or
# the older date tags (44.20261026), are ignored; with no versions at all, the next is v0.0.1.
#
# Usage: skopeo list-tags docker://ghcr.io/orielos/orielos | jq -r '.Tags[]' | tools/next-version.sh
#        tools/next-version.sh --help
set -Eeuo pipefail

PATCH_MAX=10
MINOR_MAX=100

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
fi
if [[ $# -gt 0 ]]; then
    printf 'error: unknown option: %s\n' "$1" >&2
    exit 2
fi

found=0
major=0
minor=0
patch=0
while IFS= read -r tag || [[ -n "$tag" ]]; do
    tag="${tag%$'\r'}"
    [[ "$tag" =~ ^v(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]?)$ ]] || continue
    a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}" c="${BASH_REMATCH[3]}"
    if ((b > MINOR_MAX || c > PATCH_MAX)); then continue; fi
    if ((found == 0 || a > major || (a == major && (b > minor || (b == minor && c > patch))))); then
        found=1 major=$a minor=$b patch=$c
    fi
done

if ((found == 0)); then
    printf 'v0.0.1\n'
    exit 0
fi
patch=$((patch + 1))
if ((patch > PATCH_MAX)); then
    patch=0
    minor=$((minor + 1))
fi
if ((minor > MINOR_MAX)); then
    minor=0
    major=$((major + 1))
fi
printf 'v%d.%d.%d\n' "$major" "$minor" "$patch"

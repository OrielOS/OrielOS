#!/usr/bin/env bash
# Prints what is new in a build: the entries of the CHANGELOG's Unreleased section at the build's
# commit that weren't in it at the previous build's commit, under their headings (### Added and so
# on). An entry stays whole: one whose text or sub-entries changed since the previous build counts
# as new, with all of them. Prints nothing when nothing is new.
#
# Usage: tools/build-changelog.sh PREVIOUS CURRENT
#   PREVIOUS  CHANGELOG.md at the previous build's commit; an empty file if there is none
#   CURRENT   CHANGELOG.md at this build's commit
#        tools/build-changelog.sh --help
set -Eeuo pipefail

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi
    [[ $# -eq 2 ]] || {
        usage >&2
        exit 1
    }
    local previous="$1" current="$2"
    [[ -r "$previous" ]] || die "cannot read $previous"
    [[ -r "$current" ]] || die "cannot read $current"
    grep -q '^## \[Unreleased\]' "$current" || die "$current has no Unreleased section"

    awk -v previous="$previous" '
        BEGIN {
            on = 0
            while ((getline line < previous) > 0) {
                sub(/\r$/, "", line)
                if (line ~ /^## \[Unreleased\]/) { on = 1; continue }
                if (on && line ~ /^## \[/) break
                if (on && line != "") known[line] = 1
            }
        }
        { sub(/\r$/, "") }
        # Keeps the block of one entry and its indented sub-entries if any of its lines is new.
        function close_block(   i) {
            if (nblock && changed) {
                if (!(group in seen)) { groups[++ngroups] = group; seen[group] = 1 }
                for (i = 1; i <= nblock; i++) out[group] = out[group] block[i] "\n"
            }
            nblock = 0; changed = 0
        }
        function take(line) { block[++nblock] = line; if (!(line in known)) changed = 1 }
        state == 0 && /^## \[Unreleased\]/ { state = 1; group = ""; next }
        state == 0 { next }
        state == 1 && /^## \[/ { close_block(); state = 2; next }
        state == 1 && /^### / { close_block(); group = $0; next }
        state == 1 && /^- / { close_block(); take($0); next }
        state == 1 && /^[[:space:]]+[^[:space:]]/ && nblock { take($0); next }
        # Any other text is a block of its own, so nothing is lost.
        state == 1 && /[^[:space:]]/ { close_block(); take($0); next }
        state == 1 { close_block(); next }
        END {
            if (state == 1) close_block()
            for (k = 1; k <= ngroups; k++) {
                if (k > 1) print ""
                if (groups[k] != "") { print groups[k]; print "" }
                printf "%s", out[groups[k]]
            }
        }
    ' "$current"
}

main "$@"

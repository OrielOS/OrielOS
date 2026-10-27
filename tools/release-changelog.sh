#!/usr/bin/env bash
# Starts a released version's section in CHANGELOG.md. The section holds what the release's Unreleased
# section said at the commit the build was made from; whatever was added to Unreleased after that
# commit, or changed since, stays under Unreleased, because the release doesn't contain it. An entry
# stays whole: one whose text or sub-entries changed after the commit stays under Unreleased with
# all of them.
#
# Usage: tools/release-changelog.sh CHANGELOG RELEASED VERSION DATE
#   CHANGELOG  the CHANGELOG.md to update; the result goes to standard output
#   RELEASED   the Unreleased section at the build's commit, without its heading (the release notes)
#   VERSION    the version released, such as v0.0.7; the heading leaves out the v
#   DATE       the release date, YYYY-MM-DD
#        tools/release-changelog.sh --help
set -Eeuo pipefail

usage() {
    sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    [[ $# -eq 4 ]] || {
        usage >&2
        exit 1
    }
    local changelog="$1" released="$2" version="$3" date="$4"
    [[ -r "$changelog" ]] || die "cannot read $changelog"
    [[ -r "$released" ]] || die "cannot read $released"
    [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version looks like v0.0.7"
    [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "the date looks like 2026-10-27"
    grep -q '^## \[Unreleased\]' "$changelog" || die "$changelog has no Unreleased section"
    grep -q '[^[:space:]]' "$released" || die "$released is empty"

    awk -v released="$released" -v heading="## [${version#v}] - ${date}" '
        BEGIN {
            while ((getline line < released) > 0) {
                sub(/\r$/, "", line)
                rel[++nrel] = line
                if (line != "") known[line] = 1
            }
        }
        { sub(/\r$/, "") }
        # Keeps the block of one entry and its indented sub-entries if any of its lines is new.
        function close_block() {
            if (nblock && changed) {
                if (!(group in printed_group)) { kept[++nkept] = group; printed_group[group] = 1 }
                for (i = 1; i <= nblock; i++) out[group] = out[group] block[i] "\n"
            }
            nblock = 0; changed = 0
        }
        state == 0 && /^## \[Unreleased\]/ { state = 1; group = ""; next }
        state == 0 { print; next }
        state == 1 && /^## \[/ { close_block(); finish(); state = 2; print; next }
        state == 1 && /^### / { close_block(); group = $0; next }
        state == 1 && /^- / { close_block(); block[++nblock] = $0; if (!($0 in known)) changed = 1; next }
        state == 1 && /^[[:space:]]+[^[:space:]]/ && nblock {
            block[++nblock] = $0; if (!($0 in known)) changed = 1; next
        }
        # Any other text is a block of its own, so nothing is lost.
        state == 1 && /[^[:space:]]/ { close_block(); block[++nblock] = $0; if (!($0 in known)) changed = 1; next }
        state == 1 { close_block(); next }
        state == 2 { print }
        function finish(   k, first, last) {
            print "## [Unreleased]"
            print ""
            for (k = 1; k <= nkept; k++) {
                if (kept[k] != "") { print kept[k]; print "" }
                printf "%s\n", out[kept[k]]
            }
            print heading
            print ""
            first = 1; while (first <= nrel && rel[first] == "") first++
            last = nrel; while (last >= first && rel[last] == "") last--
            for (k = first; k <= last; k++) print rel[k]
            print ""
            done = 1
        }
        END { if (state == 1) { close_block(); finish() } }
    ' "$changelog"
}

main "$@"

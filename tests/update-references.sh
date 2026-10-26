#!/usr/bin/env bash
# Updates the boot test's visual check references from a run's results: copies visual-desktop.png
# and visual-start.png to tests/references/desktop.png and start.png, after printing how much each
# differs from the reference it replaces. Look at the screenshots before running it: every later
# boot test compares against them. This is the only way the references should change.
#
# Usage: tests/update-references.sh RESULTS_DIR [--only desktop|start] [--help]
#   RESULTS_DIR      a boot test's results folder (tests/results/<run id>, or its --results)
#   --only NAME      update only that reference
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REFERENCES="$ROOT/tests/references"
NAMES=(desktop start)

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local results="" only="" name shot out
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only)
                [[ $# -ge 2 ]] || die "--only needs desktop or start"
                only="$2"
                shift 2
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            -*)
                usage >&2
                die "unknown option: $1"
                ;;
            *)
                [[ -z "$results" ]] || die "give one results folder"
                results="$1"
                shift
                ;;
        esac
    done
    [[ -n "$results" ]] || die "give the boot test's results folder (see --help)"
    [[ -z "$only" || " ${NAMES[*]} " == *" $only "* ]] || die "--only takes desktop or start"
    for name in "${NAMES[@]}"; do
        [[ -z "$only" || "$name" == "$only" ]] || continue
        shot="$results/visual-$name.png"
        [[ -r "$shot" ]] || die "cannot read $shot; run the boot test first"
        if [[ -r "$REFERENCES/$name.png" ]]; then
            out="$(python3 -I "$ROOT/tests/lib/screens.py" "$REFERENCES/$name.png" "$shot" --mask "$REFERENCES/$name.mask" 2>&1)" || true
            printf '%s: replacing the reference, which differs by %s\n' "$name" "$out"
        else
            printf '%s: adding the first reference\n' "$name"
        fi
        cp "$shot" "$REFERENCES/$name.png"
    done
    printf 'Done. Review the new images in %s and commit them with the change that needs them.\n' "$REFERENCES"
}

main "$@"

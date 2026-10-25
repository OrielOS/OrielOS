#!/usr/bin/env bash
# Creates or updates the repository labels listed in .github/labels.yml.
# Usage: tools/sync-labels.sh [--dry-run] [--prune] [--repo OWNER/NAME]
#   --dry-run  print the gh commands instead of running them
#   --prune    also delete GitHub's default labels that overlap with ours
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABELS_FILE="${ROOT}/.github/labels.yml"
DEFAULT_LABELS=(bug enhancement documentation question duplicate invalid wontfix)

dry_run=0
prune=0
repo_args=()

usage() {
    sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
    echo "sync-labels: $*" >&2
    exit 1
}

run() {
    if ((dry_run)); then
        printf '%q ' "$@"
        printf '\n'
    else
        "$@"
    fi
}

# Prints one "name<TAB>color<TAB>description" line per label.
parse_labels() {
    awk '
        function value(line) {
            sub(/^[^:]*:[ ]*/, "", line)
            gsub(/^"|"$/, "", line)
            return line
        }
        function flush() {
            if (name != "") printf "%s\t%s\t%s\n", name, color, desc
            name = color = desc = ""
        }
        /^- name:/ { flush(); name = value($0); next }
        /^  color:/ { color = value($0); next }
        /^  description:/ { desc = value($0); next }
        END { flush() }
    ' "${LABELS_FILE}"
}

main() {
    while (($#)); do
        case "$1" in
            --dry-run) dry_run=1 ;;
            --prune) prune=1 ;;
            --repo)
                (($# >= 2)) || die "--repo needs a value"
                repo_args=(--repo "$2")
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *) die "unknown option: $1" ;;
        esac
        shift
    done

    [[ -f "${LABELS_FILE}" ]] || die "missing ${LABELS_FILE}"
    if ((! dry_run)); then
        command -v gh >/dev/null || die "the GitHub CLI (gh) is required"
    fi

    local name color desc count=0
    while IFS=$'\t' read -r name color desc; do
        [[ -n "${name}" && -n "${color}" ]] || die "incomplete label entry: ${name}"
        run gh label create "${name}" --color "${color}" --description "${desc}" --force "${repo_args[@]}"
        count=$((count + 1))
    done < <(parse_labels)
    ((count > 0)) || die "no labels found in ${LABELS_FILE}"

    if ((prune)); then
        for name in "${DEFAULT_LABELS[@]}"; do
            run gh label delete "${name}" --yes "${repo_args[@]}" ||
                echo "sync-labels: could not delete '${name}' (already gone?)" >&2
        done
    fi
}

main "$@"

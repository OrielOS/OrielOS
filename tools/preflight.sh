#!/usr/bin/env bash
# Runs the checks a pull request gets in CI, before the branch is pushed, so they pass the first
# time:
# - pins: every image digest in image/pins.env is still served by its registry, and every pinned
#   URL still answers. A container image already in the local cache would otherwise hide a digest
#   the registry has dropped, which then fails the image and app builds in CI.
# - commits: every commit on the branch is signed off by its author (CI's dco check) and its
#   subject is a Conventional Commit.
# - lint: tools/lint.sh (CI's lint check).
# - apps: tools/test-apps.sh (CI's apps check), when the branch changes a file the app build
#   reads, as in CI.
# Prints PASS/FAIL/SKIP per check and exits 1 on any failure.
#
# Usage: tools/preflight.sh [--base REF] [--apps | --skip-apps] [--help]
#   --base REF    branch the pull request will go into (default origin/main); fetch it first
#   --apps        build and test the apps even if nothing they read has changed
#   --skip-apps   don't build the apps
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="origin/main"
APPS=auto
PASSED=0
FAILED=0
SKIPPED=0
# The files the app build reads, as in .github/workflows/apps.yml. Markdown files never count.
APP_PATHS=(apps plasma artwork CMakeLists.txt image/Containerfile image/build/apps-builder.sh
    image/pins.env .containerignore .gitattributes tools/test-apps.sh tools/lib/pins.sh
    .github/workflows/apps.yml ':(exclude)*.md')
CONVENTIONAL='^(feat|fix|docs|chore|test|build|ci|refactor|perf|style|revert)(\([a-z0-9._/-]+\))?!?: [^ ]'

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_OFF=$'\033[0m'
else
    C_GREEN=""
    C_RED=""
    C_YELLOW=""
    C_OFF=""
fi

pass() {
    PASSED=$((PASSED + 1))
    printf '%sPASS%s  %-10s %s\n' "$C_GREEN" "$C_OFF" "$1" "${2:-}"
}
fail() {
    FAILED=$((FAILED + 1))
    printf '%sFAIL%s  %-10s %s\n' "$C_RED" "$C_OFF" "$1" "${2:-}"
    if [[ -n "${3:-}" ]]; then printf '%s\n' "$3" | sed 's/^/      /'; fi
    if [[ -n "${4:-}" ]]; then printf '      hint: %s\n' "$4"; fi
    return 0
}
skip() {
    SKIPPED=$((SKIPPED + 1))
    printf '%sSKIP%s  %-10s %s\n' "$C_YELLOW" "$C_OFF" "$1" "${2:-}"
}

usage() {
    sed -n '2,/^set -Eeuo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            [[ $# -ge 2 ]] || {
                printf 'error: --base needs a ref\n' >&2
                exit 2
            }
            BASE="$2"
            shift 2
            ;;
        --apps)
            APPS=yes
            shift
            ;;
        --skip-apps)
            APPS=no
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'error: unknown option %s (see --help)\n' "$1" >&2
            exit 2
            ;;
    esac
done

cd "$ROOT"
if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    printf 'error: %s is not a commit here; fetch it first (git fetch origin main)\n' "$BASE" >&2
    exit 2
fi
MERGE_BASE="$(git merge-base "$BASE" HEAD)"

# pins: each KEY="value" line of image/pins.env whose value is a pinned image or a URL.
check_pins() {
    local key value ref repo bad=() checked=0
    if ! command -v skopeo >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        fail pins "(skopeo or curl is missing)" "" "install skopeo and curl (tools/check-env.sh lists what the build needs)"
        return 0
    fi
    while IFS='=' read -r key value; do
        ref="${value%\"}"
        ref="${ref#\"}"
        case "$ref" in
            http://* | https://*)
                checked=$((checked + 1))
                # A pinned download is <url>@sha256:<checksum>; the build checks the checksum. A
                # one-byte range request, as some download hosts refuse HEAD.
                curl -sfL -r 0-0 -o /dev/null "${ref%@sha256:*}" || bad+=("$key: ${ref%@sha256:*} doesn't answer")
                ;;
            *@sha256:*)
                checked=$((checked + 1))
                # skopeo doesn't accept a tag and a digest together, and the digest is what's pinned.
                repo="${ref%@*}"
                repo="${repo%:*}"
                skopeo inspect --raw "docker://$repo@${ref##*@}" >/dev/null 2>&1 ||
                    bad+=("$key: the registry no longer serves ${ref##*@} (${ref%@*} is now $(skopeo inspect --format '{{.Digest}}' "docker://${ref%@*}" 2>/dev/null || echo 'unknown'))")
                ;;
        esac
    done < <(grep -E '^[A-Z_]+=' image/pins.env)
    if [[ "${#bad[@]}" -eq 0 ]]; then
        pass pins "($checked pinned images and URLs answer)"
    else
        fail pins "(${#bad[@]} of $checked)" "$(printf '%s\n' "${bad[@]}")" "tools/update-pins.sh --write moves the pins to their current digests; then build and test"
    fi
}

# commits: sign-off and subject of every commit on the branch, as CI's dco check reads them.
check_commits() {
    local sha email subject problems=() count=0
    for sha in $(git rev-list --no-merges "$MERGE_BASE..HEAD"); do
        count=$((count + 1))
        email="$(git log -1 --format='%ae' "$sha")"
        subject="$(git log -1 --format='%s' "$sha")"
        if ! git log -1 --format='%(trailers:key=Signed-off-by,valueonly)' "$sha" | grep -qiF "<$email>"; then
            problems+=("${sha:0:12} has no Signed-off-by line for $email")
        fi
        if [[ ! "$subject" =~ $CONVENTIONAL ]]; then
            problems+=("${sha:0:12} \"$subject\" isn't a Conventional Commit subject")
        fi
    done
    if [[ "$count" -eq 0 ]]; then
        skip commits "(no commits since $BASE)"
    elif [[ "${#problems[@]}" -eq 0 ]]; then
        pass commits "($count signed off, Conventional Commit subjects)"
    else
        fail commits "(${#problems[@]} problems)" "$(printf '%s\n' "${problems[@]}")" \
            "sign off with git commit -s; reword with git rebase -i $BASE before the branch is pushed"
    fi
}

# lint and apps: the CI scripts themselves, with their output only on failure.
run_script() {
    local label="$1" out rc=0
    shift
    out="$("$@" 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        pass "$label" "($*)"
    else
        fail "$label" "($* exited with $rc)" "$(printf '%s\n' "$out" | tail -n 25)"
    fi
}

check_pins
check_commits
run_script lint tools/lint.sh
if [[ "$APPS" == no ]]; then
    skip apps "(--skip-apps)"
elif [[ "$APPS" == yes ]] || ! git diff --quiet "$MERGE_BASE" HEAD -- "${APP_PATHS[@]}"; then
    run_script apps tools/test-apps.sh
else
    skip apps "(nothing the app build reads has changed since $BASE)"
fi

printf '\n%d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi

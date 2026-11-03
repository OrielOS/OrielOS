#!/usr/bin/env bash
# Unit tests for the lists of files that decide what CI builds: every file a Containerfile stage
# reads (its COPY sources and bind mounts) must be in the apps check's change filter
# (.github/workflows/apps.yml and tools/preflight.sh), in the inputs of a prebuilt stage
# (tools/lib/stage-inputs.sh), and in the paths that start the image build
# (.github/workflows/image.yml). A file left out of one of them lets a change skip the build
# that would have tested it, and the check still passes. Prints PASS/FAIL per case and exits 1 if
# any case fails.
#
# Usage: tests/unit/change-filters-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASSED=0
FAILED=0

# shellcheck source=tools/lib/stage-inputs.sh
source "$ROOT/tools/lib/stage-inputs.sh"

# What each stage of image/Containerfile reads from the build context, one "<stage> <path>" per
# line; the stage after the last named one is "final". A bind mount of image/build at /ctx counts
# as the scripts the step runs from it.
stage_reads() {
    awk '
        /\\$/ { sub(/\\$/, ""); line = line $0 " "; next }
        { line = line $0; $0 = line; line = "" }
        $1 == "FROM" { stage = (toupper($3) == "AS") ? $4 : "final"; next }
        $1 == "COPY" && $0 !~ /--from=/ { for (i = 2; i < NF; i++) print stage, $i; next }
        $1 == "RUN" {
            n = split($0, words, /[ \t]+/)
            for (i = 1; i <= n; i++) {
                if (words[i] !~ /^--mount=type=bind,/ || words[i] ~ /,from=/) continue
                if (!match(words[i], /source=[^,]+/)) continue
                source = substr(words[i], RSTART + 7, RLENGTH - 7)
                if (source != "image/build" || words[i] !~ /target=\/ctx(,|$)/) { print stage, source; continue }
                for (j = 1; j <= n; j++) if (words[j] ~ /^\/ctx\//) print stage, "image/build/" substr(words[j], 6)
            }
        }
    ' <(tr -d '\r' <"$ROOT/image/Containerfile") | sed 's|/$||'
}

# The paths the apps check compares, from the git diff in .github/workflows/apps.yml.
apps_workflow_paths() {
    # shellcheck disable=SC2016 # ${base} is the workflow's text, not a variable here.
    tr -d '\r' <"$ROOT/.github/workflows/apps.yml" | sed -n '/git diff --quiet "${base}" HEAD -- \\/,/:(exclude)/p' |
        tail -n +2 | tr -s ' \134' '\n' | grep -v -e '^$' -e '^.:(exclude)' -e '|| rc'
}

# The paths tools/preflight.sh compares, from its APP_PATHS.
preflight_paths() {
    tr -d '\r' <"$ROOT/tools/preflight.sh" | sed -n '/^APP_PATHS=(/,/)$/p' | sed 's/^APP_PATHS=(//; s/)$//' |
        tr -s ' ' '\n' | grep -v -e '^$' -e '^.:(exclude)'
}

# The paths that start the image build on main, from .github/workflows/image.yml.
image_workflow_paths() {
    tr -d '\r"' <"$ROOT/.github/workflows/image.yml" |
        awk '/^  push:/ { push = 1; next } push && /^  [a-z_]+:/ { exit } push && /^      - / { print $2 }'
}

# covered <path> <list entry>...: succeeds when an entry is the path or a folder holding it.
# Entries starting with ! are exclusions and never cover anything.
covered() {
    local path="$1" entry
    shift
    for entry in "$@"; do
        [[ "$entry" == '!'* ]] && continue
        entry="${entry%/\*\*}"
        entry="${entry%/}"
        if [[ "$path" == "$entry" || "$path" == "$entry"/* ]]; then return 0; fi
    done
    return 1
}

# expect_covered <case> <reads, one "<stage> <path>" per line> <stage pattern> <list entry>...
expect_covered() {
    local name="$1" reads="$2" stages="$3" stage path missing=()
    shift 3
    while read -r stage path; do
        [[ -n "$stage" ]] || continue
        # shellcheck disable=SC2053
        [[ "$stage" == $stages ]] || continue
        covered "$path" "$@" || missing+=("$path ($stage)")
    done <<<"$reads"
    if [[ "${#missing[@]}" -eq 0 ]]; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      missing: %s\n' "$name" "${missing[*]}"
        FAILED=$((FAILED + 1))
    fi
}

# expect_missed <case> <path> <list entry>...: the check itself must notice a path left out.
expect_missed() {
    local name="$1" path="$2"
    shift 2
    if covered "$path" "$@"; then
        printf 'FAIL  %s\n      %s counted as covered\n' "$name" "$path"
        FAILED=$((FAILED + 1))
    else
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    fi
}

READS="$(stage_reads)"
mapfile -t APPS_WORKFLOW < <(apps_workflow_paths)
mapfile -t PREFLIGHT < <(preflight_paths)
mapfile -t IMAGE_WORKFLOW < <(image_workflow_paths)
mapfile -t APP_DEPS_INPUTS < <(stage_paths app-deps)
mapfile -t OS_BASE_INPUTS < <(stage_paths os-base)

# The reads are parsed, not listed by hand, so a parse that finds nothing would pass everything.
if grep -qx 'app-deps image/build/apps-builder.sh' <<<"$READS" && grep -qx 'app-builder data' <<<"$READS" &&
    grep -qx 'os-base image/packages' <<<"$READS" && grep -qx 'final CHANGELOG.md' <<<"$READS"; then
    printf 'PASS  %s\n' "The Containerfile's stages and what they read are found"
    PASSED=$((PASSED + 1))
else
    printf 'FAIL  %s\n      found:\n%s\n' "The Containerfile's stages and what they read are found" "$READS"
    FAILED=$((FAILED + 1))
fi
expect_covered "apps.yml compares every file the app stages read" "$READS" "app-*" "${APPS_WORKFLOW[@]}"
expect_covered "tools/preflight.sh compares every file the app stages read" "$READS" "app-*" "${PREFLIGHT[@]}"
expect_covered "The builder's inputs hold every file app-deps reads" "$READS" "app-deps" "${APP_DEPS_INPUTS[@]}"
expect_covered "The OS base's inputs hold every file os-base reads" "$READS" "os-base" "${OS_BASE_INPUTS[@]}"
# Markdown never starts an image build on its own: the changelog goes out with the next build.
expect_covered "image.yml starts a build for every file the image reads" "$(grep -v '\.md$' <<<"$READS")" "*" \
    "${IMAGE_WORKFLOW[@]}"
expect_missed "A filter without data/ is caught" data apps plasma artwork CMakeLists.txt
expect_missed "A file is not covered by a folder whose name it starts with" image/build-extra image/build
expect_missed "An exclusion covers nothing" apps/x.cpp '!apps/**'

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]

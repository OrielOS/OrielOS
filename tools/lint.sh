#!/usr/bin/env bash
# Runs every linter over the repository: shellcheck, shfmt, hadolint,
# actionlint, clang-format and gitleaks (qmllint runs in tools/test-apps.sh).
# Prints PASS/FAIL/SKIP per check with the linter's own output on failure, and
# exits 1 on any failure.
# Tracked files and new files that are not ignored are both linted.
#
# Usage: tools/lint.sh [--help]
# Environment:
#   ORIELOS_TOOLS_DIR   folder with the pinned tools (default <repository>/.cache/tools),
#                       filled by tools/install-lint-tools.sh
set -Eeuo pipefail
shopt -s extglob

PASSED=0
FAILED=0
SKIPPED=0
FILES=()

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
    printf '%sPASS%s  %-22s %s\n' "$C_GREEN" "$C_OFF" "$1" "${2:-}"
}
fail() {
    FAILED=$((FAILED + 1))
    printf '%sFAIL%s  %-22s %s\n' "$C_RED" "$C_OFF" "$1" "${2:-}"
    if [[ -n "${3:-}" ]]; then printf '%s\n' "$3" | sed 's/^/      /'; fi
    if [[ -n "${4:-}" ]]; then printf '      hint: %s\n' "$4"; fi
    return 0
}
skip() {
    SKIPPED=$((SKIPPED + 1))
    printf '%sSKIP%s  %-22s %s\n' "$C_YELLOW" "$C_OFF" "$1" "(no $2 files)"
}

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Succeed when the first line of a file is a sh or bash shebang.
has_shell_shebang() {
    local line=""
    IFS= read -r line <"$1" 2>/dev/null || true
    [[ "$line" =~ ^#!.*[/[:space:]](ba)?sh([[:space:]]|$) ]]
}

# Select FILES whose base name matches one of the given glob patterns.
select_by_name() {
    local f base pat
    SELECTED=()
    for f in "${FILES[@]}"; do
        base="${f##*/}"
        for pat in "$@"; do
            # shellcheck disable=SC2053
            if [[ "$base" == $pat ]]; then
                SELECTED+=("$f")
                break
            fi
        done
    done
}

select_shell_files() {
    local f base
    SELECTED=()
    for f in "${FILES[@]}"; do
        base="${f##*/}"
        if [[ "$base" == *.sh ]]; then
            SELECTED+=("$f")
        elif [[ "$base" != *.* ]] && has_shell_shebang "$f"; then
            SELECTED+=("$f")
        fi
    done
}

# Select the workflow files; they are matched by path, not base name.
select_workflows() {
    local f
    SELECTED=()
    for f in "${FILES[@]}"; do
        case "$f" in
            .github/workflows/*.yml | .github/workflows/*.yaml) SELECTED+=("$f") ;;
        esac
    done
}

# run_check <label> <kind> <tool> <install hint> <failure hint> <command...>
# Runs the command on the files in SELECTED (appended to the command).
run_check() {
    local label="$1" kind="$2" tool="$3" install_hint="$4" hint="$5" out rc=0
    shift 5
    if [[ "${#SELECTED[@]}" -eq 0 ]]; then
        skip "$label" "$kind"
        return 0
    fi
    if ! command -v "$tool" >/dev/null 2>&1 && [[ ! -x "$tool" ]]; then
        fail "$label" "($tool is missing)" "" "$install_hint"
        return 0
    fi
    out="$("$@" "${SELECTED[@]}" 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        pass "$label" "(${#SELECTED[@]} files)"
    else
        fail "$label" "" "$out" "$hint"
    fi
}

# qmllint needs the import paths and Qt and KDE Frameworks versions of the app build to give
# meaningful results, so it runs there (tools/test-apps.sh) rather than here.
check_qmllint() {
    select_by_name '*.qml'
    if [[ "${#SELECTED[@]}" -eq 0 ]]; then
        skip qmllint QML
    else
        SKIPPED=$((SKIPPED + 1))
        printf '%sSKIP%s  %-22s %s\n' "$C_YELLOW" "$C_OFF" qmllint "(runs in tools/test-apps.sh)"
    fi
}

check_gitleaks() {
    local out rc=0 hint="run tools/install-lint-tools.sh"
    if ! command -v gitleaks >/dev/null 2>&1; then
        fail "gitleaks (history)" "(gitleaks is missing)" "" "$hint"
        fail "gitleaks (uncommitted)" "(gitleaks is missing)" "" "$hint"
        return 0
    fi
    hint="remove the secret and rotate it; for a false positive, narrow the rule in .gitleaks.toml"
    out="$(gitleaks git --no-banner --redact --config .gitleaks.toml . 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then pass "gitleaks (history)"; else fail "gitleaks (history)" "" "$out" "$hint"; fi
    rc=0
    out="$(gitleaks git --pre-commit --no-banner --redact --config .gitleaks.toml . 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then pass "gitleaks (uncommitted)"; else fail "gitleaks (uncommitted)" "" "$out" "$hint"; fi
}

main() {
    local arg root tools_dir f install="run tools/install-lint-tools.sh"
    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                usage
                exit 0
                ;;
            *)
                printf 'Unknown option: %s\n' "$arg" >&2
                usage >&2
                exit 2
                ;;
        esac
    done

    root="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>&1)" || {
        printf 'error: cannot find the repository root with git: %s\n' "$root" >&2
        exit 2
    }
    cd "$root"
    tools_dir="${ORIELOS_TOOLS_DIR:-$root/.cache/tools}"
    PATH="$tools_dir/bin:$PATH"

    while IFS= read -r -d '' f; do
        if [[ -f "$f" && "$f" != .cache/* ]]; then FILES+=("$f"); fi
    done < <(git ls-files -z --cached --others --exclude-standard)

    select_shell_files
    run_check shellcheck shell shellcheck "$install" "fix the findings above" shellcheck --severity=style
    run_check shfmt shell shfmt "$install" "run shfmt -w -i 4 -ci <file> to apply the formatting" shfmt -d -i 4 -ci
    select_by_name Containerfile 'Containerfile.*' '*.Containerfile' Dockerfile 'Dockerfile.*'
    run_check hadolint Containerfile hadolint "$install" "fix the findings above" hadolint
    select_workflows
    run_check actionlint workflow actionlint "$install" "fix the findings above" actionlint
    select_by_name '*.cpp' '*.cc' '*.cxx' '*.h' '*.hpp' '*.hh'
    run_check clang-format C++ clang-format "$install" "run clang-format -i <file> to apply the formatting" \
        clang-format --dry-run --Werror
    check_qmllint
    check_gitleaks

    printf '%d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
    [[ "$FAILED" -eq 0 ]]
}

main "$@"

#!/usr/bin/env bash
# Installs the pinned linters that tools/lint.sh needs (shellcheck, shfmt,
# hadolint, actionlint, gitleaks and clang-format) into one local folder.
# Downloads are checked against the SHA-256 values in tools/lint-tools.env;
# nothing is installed system-wide and sudo is never used.
#
# Usage: tools/install-lint-tools.sh [--help]
# Environment:
#   ORIELOS_TOOLS_DIR   install folder (default <repository>/.cache/tools)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=""

cleanup() {
    if [[ -n "$TMP" ]]; then rm -rf "$TMP"; fi
    return 0
}
trap cleanup EXIT

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

repo_root() {
    git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd)
}

# Install one downloaded tool: install_tool <name> <archive member or "-"> <executable name>
install_tool() {
    local name="$1" member="$2" exe="$3" upper version url sha stamp file
    upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    version="${upper}_VERSION"
    url="${upper}_URL"
    sha="${upper}_SHA256"
    version="${!version}"
    url="${!url}"
    sha="${!sha}"
    stamp="$BIN_DIR/.$name.stamp"

    if [[ -x "$BIN_DIR/$exe" && -f "$stamp" && "$(cat "$stamp")" == "$version $sha" ]]; then
        printf 'present    %s %s\n' "$name" "$version"
        return 0
    fi

    file="$TMP/$(basename "$url")"
    curl -fsSL --retry 3 -o "$file" "$url"
    (cd "$TMP" && printf '%s  %s\n' "$sha" "$(basename "$file")" | sha256sum -c --status -) ||
        die "checksum mismatch for $name $version; refusing to install it"

    if [[ "$member" == "-" ]]; then
        install -m 0755 "$file" "$BIN_DIR/$exe"
    else
        mkdir -p "$TMP/$name"
        tar -xf "$file" -C "$TMP/$name"
        install -m 0755 "$TMP/$name/$member" "$BIN_DIR/$exe"
    fi
    printf '%s %s\n' "$version" "$sha" >"$stamp"
    printf 'installed  %s %s\n' "$name" "$version"
}

install_clang_format() {
    local req="$ROOT/tools/lint-requirements.txt" stamp="$BIN_DIR/.clang-format.stamp" want version
    want="$(sha256sum "$req" | cut -d' ' -f1)"
    version="$(sed -n 's/^clang-format==\([0-9.]*\).*/\1/p' "$req")"
    if [[ -x "$TOOLS_DIR/venv/bin/clang-format" && -f "$stamp" && "$(cat "$stamp")" == "$version $want" ]]; then
        ln -sf "$TOOLS_DIR/venv/bin/clang-format" "$BIN_DIR/clang-format"
        printf 'present    clang-format %s\n' "$version"
        return 0
    fi
    command -v python3 >/dev/null 2>&1 || die "python3 is not installed (sudo apt install python3 python3-venv)"
    rm -rf "$TOOLS_DIR/venv"
    python3 -m venv "$TOOLS_DIR/venv" >/dev/null 2>&1 ||
        die "python3 -m venv failed; install the venv module with: sudo apt install python3-venv"
    "$TOOLS_DIR/venv/bin/python" -m pip install --quiet --disable-pip-version-check --require-hashes --no-deps -r "$req"
    ln -sf "$TOOLS_DIR/venv/bin/clang-format" "$BIN_DIR/clang-format"
    printf '%s %s\n' "$version" "$want" >"$stamp"
    printf 'installed  clang-format %s\n' "$version"
}

main() {
    local arg
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

    ROOT="$(repo_root)"
    TOOLS_DIR="${ORIELOS_TOOLS_DIR:-$ROOT/.cache/tools}"
    BIN_DIR="$TOOLS_DIR/bin"
    mkdir -p "$BIN_DIR"
    TMP="$(mktemp -d)"

    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/lint-tools.env"

    install_tool shellcheck "shellcheck-v$SHELLCHECK_VERSION/shellcheck" shellcheck
    install_tool shfmt - shfmt
    install_tool hadolint - hadolint
    install_tool actionlint actionlint actionlint
    install_tool gitleaks gitleaks gitleaks
    install_clang_format

    printf 'Done. Run tools/lint.sh to lint the repository.\n'
}

main "$@"

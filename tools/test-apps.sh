#!/usr/bin/env bash
# Builds and tests OrielOS's own apps the same way the image build does, without building the
# whole image. It builds only the app-builder stage of image/Containerfile, which configures,
# builds, runs the unit tests and qmllint, and installs the apps. Exits 1 if any step fails.
# Works with rootless and rootful Podman, and never uses sudo.
#
# Usage: tools/test-apps.sh [--pins FILE] [--tag REF] [--help]
#   --pins FILE   pins file (default image/pins.env)
#   --tag REF     tag for the built stage (default localhost/orielos-app-builder)
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
# shellcheck source=lib/pins.sh
source "$ROOT/tools/lib/pins.sh"
TAG="localhost/orielos-app-builder"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pins | --tag)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --pins) PINS="$2" ;;
                    --tag) TAG="$2" ;;
                esac
                shift 2
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "unknown option: $1"
                ;;
        esac
    done

    command -v podman >/dev/null 2>&1 || die "podman is not installed"
    [[ -r "$PINS" ]] || die "cannot read $PINS"
    # shellcheck source=/dev/null
    source "$PINS"
    [[ -n "${BUILDER_IMAGE:-}" ]] || die "BUILDER_IMAGE is not set in $PINS"
    [[ "$BUILDER_IMAGE" =~ @sha256:[0-9a-f]{64}$ ]] ||
        die "BUILDER_IMAGE in $PINS is not pinned by digest (expected name:tag@sha256:<64 hex digits>)"

    # From OrielOS's copy where it has it (tools/lib/pins.sh): upstream registries drop old digests.
    BUILDER_IMAGE="$(pull_pin "$BUILDER_IMAGE")" || die "can't pull $BUILDER_IMAGE from OrielOS's copy or upstream"
    step "Building and testing the apps in $BUILDER_IMAGE"
    if ! podman build --pull=missing -f "$ROOT/image/Containerfile" --target app-builder \
        --build-arg "BUILDER_IMAGE=$BUILDER_IMAGE" -t "$TAG" "$ROOT"; then
        die "the apps failed to build, a test failed or qmllint reported a problem; see the output above"
    fi
    step "Done: the apps built and passed their tests ($TAG)"
}

main "$@"

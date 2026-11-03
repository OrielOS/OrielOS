#!/usr/bin/env bash
# Builds and tests OrielOS's own apps the same way the image build does, without building the
# whole image. It builds only the app-builder stage of image/Containerfile, which configures,
# builds, runs the unit tests and qmllint, and installs the apps. Exits 1 if any step fails.
# Works with rootless and rootful Podman, and never uses sudo.
#
# Usage: tools/test-apps.sh [--pins FILE] [--tag REF] [--use-published] [--help]
#   --pins FILE        pins file (default image/pins.env)
#   --tag REF          tag for the built stage (default localhost/orielos-app-builder)
#   --use-published    start from CI's prebuilt build tools (ghcr.io/orielos/orielos-builder)
#                      when they were built from this checkout's inputs (tools/lib/stage-inputs.sh)
# Set ORIELOS_CCACHE_DIR to a folder to keep a compiler cache there between builds.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
# shellcheck source=lib/pins.sh
source "$ROOT/tools/lib/pins.sh"
# shellcheck source=lib/stage-inputs.sh
source "$ROOT/tools/lib/stage-inputs.sh"
TAG="localhost/orielos-app-builder"
USE_PUBLISHED=0

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
            --use-published)
                USE_PUBLISHED=1
                shift
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

    local app_deps=""
    if [[ "$USE_PUBLISHED" -eq 1 ]]; then app_deps="$(published_stage "$ROOT" app-deps)"; fi
    if [[ -z "$app_deps" ]]; then
        # From OrielOS's copy where it has it (tools/lib/pins.sh): upstream registries drop old digests.
        BUILDER_IMAGE="$(pull_pin "$BUILDER_IMAGE")" || die "can't pull $BUILDER_IMAGE from OrielOS's copy or upstream"
        app_deps=app-deps
    fi
    local cache=()
    if [[ -n "${ORIELOS_CCACHE_DIR:-}" ]]; then
        mkdir -p "$ORIELOS_CCACHE_DIR" || die "cannot create $ORIELOS_CCACHE_DIR"
        cache=(--volume "$(cd "$ORIELOS_CCACHE_DIR" && pwd):/ccache:z")
    fi
    if [[ "$app_deps" == app-deps ]]; then
        step "Building and testing the apps in $BUILDER_IMAGE"
    else
        step "Building and testing the apps in $app_deps"
    fi
    if ! podman build --pull=missing -f "$ROOT/image/Containerfile" --target app-builder \
        --build-arg "BUILDER_IMAGE=$BUILDER_IMAGE" --build-arg "APP_DEPS_FROM=$app_deps" \
        "${cache[@]}" -t "$TAG" "$ROOT"; then
        die "the apps failed to build, a test failed or qmllint reported a problem; see the output above"
    fi
    step "Done: the apps built and passed their tests ($TAG)"
}

main "$@"

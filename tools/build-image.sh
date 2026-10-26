#!/usr/bin/env bash
# Builds the OrielOS image locally with rootful Podman from the inputs pinned in image/pins.env,
# and exports a compressed OCI archive for test VMs.
#
# Usage: tools/build-image.sh [--pins FILE] [--version VERSION] [--output DIR]
#                             [--no-archive] [--keep N] [--clean-only] [--help]
#   --pins FILE        pins file (default image/pins.env)
#   --version VERSION  the build's version: vMAJOR.MINOR.PATCH for a build that is published, as
#                      CI gives it (tools/next-version.sh), or dev.<n> (the default: one more than
#                      the newest dev.<n> build here)
#   --output DIR       where the archive goes (default /var/lib/orielos/builds)
#   --no-archive       do not export an OCI archive
#   --keep N           keep the newest N builds and remove older ones (default 1)
#   --clean-only       only remove old builds, then exit
# The image is tagged localhost/orielos:<version> and localhost/orielos:latest.
# Runs as root; re-executes itself through sudo otherwise. Stops at once if another build or a VM
# test is running.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
# shellcheck source=lib/pins.sh
source "$ROOT/tools/lib/pins.sh"
# shellcheck source=lib/lock.sh
source "$ROOT/tools/lib/lock.sh"
VERSION=""
OUTPUT="/var/lib/orielos/builds"
ARCHIVE=1
KEEP=1
CLEAN_ONLY=0
REPO="localhost/orielos"
# The kernel the akmods images carry, set by preflight. It replaces the ostree.linux label the
# image would otherwise inherit from the base image, whose kernel is swapped out.
KERNEL=""

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

check_pin() {
    local name="$1" ref="${!1:-}"
    [[ -n "$ref" ]] || die "$name is not set in $PINS"
    [[ "$ref" =~ @sha256:[0-9a-f]{64}$ ]] || die "$name in $PINS is not pinned by digest (expected <name:tag or URL>@sha256:<64 hex digits>)"
}

kernel_of() {
    podman image inspect --format '{{index .Labels "ostree.linux"}}' "$1"
}

preflight() {
    local akmods_kernel nvidia_kernel var ref
    # From OrielOS's copies where it has them (tools/lib/pins.sh): upstream registries drop old
    # digests. Each pin then names the image that was pulled, with the same digest.
    step "Pulling the pinned images"
    for var in "${PINNED_IMAGES[@]}"; do
        ref="$(pull_pin "${!var}")" || die "can't pull $var (${!var}) from OrielOS's copy or upstream"
        printf -v "$var" '%s' "$ref"
        step "$var: $ref"
    done
    akmods_kernel="$(kernel_of "$AKMODS_IMAGE")"
    nvidia_kernel="$(kernel_of "$AKMODS_NVIDIA_IMAGE")"
    if [[ "$akmods_kernel" != "$nvidia_kernel" ]]; then
        die "kernel/NVIDIA version mismatch: akmods has $akmods_kernel, akmods-nvidia-open was built for $nvidia_kernel"
    fi
    step "Kernel $akmods_kernel matches the NVIDIA modules"
    KERNEL="$akmods_kernel"
}

report() {
    local tag="$1" size
    step "Image contents"
    podman run --rm "$REPO:$tag" bash -c '
        kver="$(rpm -q --qf "%{VERSION}-%{RELEASE}.%{ARCH}" kernel-core)"
        printf "kernel:         %s\n" "$kver"
        printf "kmod-nvidia:    %s\n" "$(rpm -q --qf "%{VERSION}-%{RELEASE}" kmod-nvidia)"
        printf "nvidia-driver:  %s\n" "$(rpm -q --qf "%{VERSION}-%{RELEASE}" nvidia-driver)"
        printf "module signer:  %s\n" "$(modinfo -k "$kver" -F signer nvidia)"
        printf "modules by signer:\n"
        find "/usr/lib/modules/$kver" -type f \( -name "*.ko" -o -name "*.ko.xz" -o -name "*.ko.zst" \) -print0 |
            xargs -0 modinfo -F signer | sort | uniq -c | sed "s/^/  /"
    '
    size="$(podman image inspect --format '{{.Size}}' "$REPO:$tag")"
    printf 'size:           %s\n' "$(numfmt --to=iec --suffix=B "$size")"
}

export_archive() {
    local tag="$1" file
    file="$OUTPUT/orielos-$tag.ociarchive"
    step "Exporting $file"
    mkdir -p "$OUTPUT"
    podman push --compression-format zstd "$REPO:$tag" "oci-archive:$file:$tag"
    printf 'archive:        %s (%s)\n' "$file" "$(du -h "$file" | cut -f1)"
}

# The local build after the newest dev.<n> one here: dev.1, dev.2 and so on.
next_dev_version() {
    local last
    last="$(podman images --format '{{.Tag}}' "$REPO" | sed -n 's/^dev\.\([1-9][0-9]*\)$/\1/p' | sort -n | tail -n1)"
    printf 'dev.%d\n' "$((${last:-0} + 1))"
}

# Removes builds older than the newest $KEEP, judged by when they were made, whatever their tags.
cleanup() {
    local tags=() files=() t f n=0
    step "Removing builds older than the newest $KEEP"
    mapfile -t tags < <(podman images --format '{{.CreatedAt}}|{{.Tag}}' "$REPO" | sort -r | cut -d'|' -f2 |
        grep -v -x -e latest -e '<none>' || true)
    if [[ "${#tags[@]}" -gt "$KEEP" ]]; then
        for t in "${tags[@]:KEEP}"; do
            podman rmi "$REPO:$t" >/dev/null
            printf 'removed image %s:%s\n' "$REPO" "$t"
            n=$((n + 1))
        done
    fi
    if [[ -d "$OUTPUT" ]]; then
        mapfile -t files < <(find "$OUTPUT" -maxdepth 1 -name 'orielos-*.ociarchive' -printf '%T@ %f\n' | sort -rn | cut -d' ' -f2)
        if [[ "${#files[@]}" -gt "$KEEP" ]]; then
            for f in "${files[@]:KEEP}"; do
                rm -f "${OUTPUT:?}/$f"
                printf 'removed archive %s\n' "$f"
                n=$((n + 1))
            done
        fi
    fi
    if [[ "$n" -eq 0 ]]; then printf 'nothing to remove\n'; fi
    podman image prune -f >/dev/null
}

main() {
    local original=("$@")
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pins | --version | --output | --keep)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --pins) PINS="$2" ;;
                    --version) VERSION="$2" ;;
                    --output) OUTPUT="$2" ;;
                    --keep) KEEP="$2" ;;
                esac
                shift 2
                ;;
            --no-archive)
                ARCHIVE=0
                shift
                ;;
            --clean-only)
                CLEAN_ONLY=1
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
    [[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep needs a number"
    if [[ -n "$VERSION" && ! "$VERSION" =~ ^(v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)|dev\.[1-9][0-9]*)$ ]]; then
        die "--version needs the form v0.0.1 or dev.1"
    fi

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    command -v podman >/dev/null 2>&1 || die "podman is not installed"
    # One build or VM test at a time (tools/lib/lock.sh).
    take_orielos_lock || exit 1
    [[ -r "$PINS" ]] || die "cannot read $PINS"
    # shellcheck source=/dev/null
    source "$PINS"
    check_pin BASE_IMAGE
    check_pin AKMODS_IMAGE
    check_pin AKMODS_NVIDIA_IMAGE
    check_pin BUILDER_IMAGE
    check_pin UMU_LAUNCHER_RPM

    if [[ "$CLEAN_ONLY" -eq 1 ]]; then
        cleanup
        return 0
    fi

    local tag="${VERSION:-$(next_dev_version)}" revision labels=()
    # The commit the build is made from, for the image's revision label; a GitHub Release made
    # from the build points at it. The checkout may belong to a user other than root.
    revision="$(git -c safe.directory="$ROOT" -C "$ROOT" rev-parse HEAD 2>/dev/null || true)"
    if [[ -n "$revision" ]]; then labels+=(--label "org.opencontainers.image.revision=$revision"); fi
    preflight

    # The app-builder stage is built and tagged first, as tools/test-apps.sh does. Untagged, its
    # layers would be removed by the image prune in cleanup, so every build would rebuild the
    # apps and every layer after them.
    step "Building the apps ($REPO-app-builder)"
    podman build --pull=missing -f "$ROOT/image/Containerfile" --target app-builder \
        --build-arg "BUILDER_IMAGE=$BUILDER_IMAGE" -t "$REPO-app-builder" "$ROOT"

    step "Building $REPO:$tag"
    podman build --pull=missing -f "$ROOT/image/Containerfile" \
        --build-arg "BASE_IMAGE=$BASE_IMAGE" \
        --build-arg "AKMODS_IMAGE=$AKMODS_IMAGE" \
        --build-arg "AKMODS_NVIDIA_IMAGE=$AKMODS_NVIDIA_IMAGE" \
        --build-arg "BUILDER_IMAGE=$BUILDER_IMAGE" \
        --build-arg "UMU_LAUNCHER_RPM=$UMU_LAUNCHER_RPM" \
        --build-arg "IMAGE_VERSION=$tag" \
        --label "ostree.linux=$KERNEL" \
        "${labels[@]}" \
        -t "$REPO:$tag" "$ROOT"
    podman tag "$REPO:$tag" "$REPO:latest"

    report "$tag"
    if [[ "$ARCHIVE" -eq 1 ]]; then export_archive "$tag"; fi
    cleanup
    step "Done: $REPO:$tag"
}

main "$@"

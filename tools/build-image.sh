#!/usr/bin/env bash
# Builds the OrielOS image locally with rootful Podman from the inputs pinned in image/pins.env,
# and exports a compressed OCI archive for test VMs.
#
# Usage: tools/build-image.sh [--pins FILE] [--date YYYYMMDD] [--output DIR] [--no-archive]
#                             [--keep N] [--clean-only] [--help]
#   --pins FILE    pins file (default image/pins.env)
#   --date DATE    build date used in the tag (default: today, UTC)
#   --output DIR   where the archive goes (default /var/lib/orielos/builds)
#   --no-archive   do not export an OCI archive
#   --keep N       keep the newest N builds and remove older ones (default 3)
#   --clean-only   only remove old builds, then exit
# The image is tagged localhost/orielos:<fedora major>.<date> and localhost/orielos:latest.
# Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
DATE=""
OUTPUT="/var/lib/orielos/builds"
ARCHIVE=1
KEEP=3
CLEAN_ONLY=0
REPO="localhost/orielos"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

check_pin() {
    local name="$1" ref="${!1:-}"
    [[ -n "$ref" ]] || die "$name is not set in $PINS"
    [[ "$ref" =~ @sha256:[0-9a-f]{64}$ ]] || die "$name in $PINS is not pinned by digest (expected name:tag@sha256:<64 hex digits>)"
}

kernel_of() {
    podman image inspect --format '{{index .Labels "ostree.linux"}}' "$1"
}

preflight() {
    local akmods_kernel nvidia_kernel
    step "Pulling the akmods images"
    podman pull --quiet "$AKMODS_IMAGE" >/dev/null
    podman pull --quiet "$AKMODS_NVIDIA_IMAGE" >/dev/null
    akmods_kernel="$(kernel_of "$AKMODS_IMAGE")"
    nvidia_kernel="$(kernel_of "$AKMODS_NVIDIA_IMAGE")"
    if [[ "$akmods_kernel" != "$nvidia_kernel" ]]; then
        die "kernel/NVIDIA version mismatch: akmods has $akmods_kernel, akmods-nvidia-open was built for $nvidia_kernel"
    fi
    step "Kernel $akmods_kernel matches the NVIDIA modules"
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

# Removes builds older than the newest $KEEP, judged by tag (<major>.<date> sorts by date).
cleanup() {
    local major="$1" tags=() files=() t f n=0
    step "Removing builds older than the newest $KEEP"
    mapfile -t tags < <(podman images --format '{{.Tag}}' "$REPO" | grep -E "^${major}\.[0-9]{8}$" | sort -ur || true)
    if [[ "${#tags[@]}" -gt "$KEEP" ]]; then
        for t in "${tags[@]:KEEP}"; do
            podman rmi "$REPO:$t" >/dev/null
            printf 'removed image %s:%s\n' "$REPO" "$t"
            n=$((n + 1))
        done
    fi
    if [[ -d "$OUTPUT" ]]; then
        mapfile -t files < <(find "$OUTPUT" -maxdepth 1 -name 'orielos-*.ociarchive' -printf '%f\n' | sort -r)
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
            --pins | --date | --output | --keep)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --pins) PINS="$2" ;;
                    --date) DATE="$2" ;;
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
    if [[ -z "$DATE" ]]; then DATE="$(date -u +%Y%m%d)"; fi
    [[ "$DATE" =~ ^[0-9]{8}$ ]] || die "--date needs the form YYYYMMDD"

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    command -v podman >/dev/null 2>&1 || die "podman is not installed"
    [[ -r "$PINS" ]] || die "cannot read $PINS"
    # shellcheck source=/dev/null
    source "$PINS"
    [[ -n "${FEDORA_MAJOR:-}" ]] || die "FEDORA_MAJOR is not set in $PINS"
    check_pin BASE_IMAGE
    check_pin AKMODS_IMAGE
    check_pin AKMODS_NVIDIA_IMAGE

    if [[ "$CLEAN_ONLY" -eq 1 ]]; then
        cleanup "$FEDORA_MAJOR"
        return 0
    fi

    local tag="$FEDORA_MAJOR.$DATE"
    preflight

    step "Building $REPO:$tag"
    podman build --pull=missing -f "$ROOT/image/Containerfile" \
        --build-arg "BASE_IMAGE=$BASE_IMAGE" \
        --build-arg "AKMODS_IMAGE=$AKMODS_IMAGE" \
        --build-arg "AKMODS_NVIDIA_IMAGE=$AKMODS_NVIDIA_IMAGE" \
        --build-arg "IMAGE_VERSION=$tag" \
        -t "$REPO:$tag" "$ROOT/image/"
    podman tag "$REPO:$tag" "$REPO:latest"

    report "$tag"
    if [[ "$ARCHIVE" -eq 1 ]]; then export_archive "$tag"; fi
    cleanup "$FEDORA_MAJOR"
    step "Done: $REPO:$tag"
}

main "$@"

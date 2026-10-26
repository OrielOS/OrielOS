#!/usr/bin/env bash
# Installs the OrielOS image to a virtual machine disk with bootc, for QEMU (qcow2) and VMware
# (VMDK). The disk has no user account; Plasma Setup creates the first one on first boot.
#
# Usage: tools/make-vm-disk.sh [--image REF | --archive FILE] [--size GIB] [--output DIR]
#                              [--formats qcow2,vmdk] [--serial-console] [--help]
#   --image REF         image to install (default localhost/orielos:latest)
#   --archive FILE      load this OCI archive (from tools/build-image.sh) into Podman first and
#                       install it as localhost/orielos-archive:<file name>
#   --size GIB          disk size in GiB (default 64); the files only take the space in use
#   --output DIR        where the disks go (default /var/lib/orielos/vm-disks)
#   --formats LIST      comma-separated: qcow2, vmdk or both (default qcow2,vmdk)
#   --serial-console    also send the console, systemd's status lines and kernel messages to the
#                       first serial port, without the boot splash, for debugging and for
#                       tools/vmware-vm.sh boot-check
# The disks are named orielos-<tag>.qcow2 and orielos-<tag>.vmdk, where the tag is the image's
# version label, or its tag if it has none. Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

IMAGE="localhost/orielos:latest"
IMAGE_SET=0
ARCHIVE=""
SIZE=64
OUTPUT="/var/lib/orielos/vm-disks"
FORMATS="qcow2,vmdk"
SERIAL=0
WORK=""
# The image load_archive added to Podman, which cleanup removes again.
LOADED=""

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cleanup() {
    local rc=$?
    trap - EXIT
    if [[ -n "$WORK" ]]; then rm -rf "$WORK"; fi
    if [[ -n "$LOADED" ]]; then
        podman rmi "$LOADED" >/dev/null 2>&1 || true
        podman image prune -f >/dev/null 2>&1 || true
    fi
    exit "$rc"
}

load_archive() {
    local id
    [[ -r "$ARCHIVE" ]] || die "cannot read $ARCHIVE"
    if ! podman image exists "$IMAGE"; then LOADED="$IMAGE"; fi
    step "Loading $ARCHIVE as $IMAGE"
    # skopeo creates only the requested tag; podman pull also tags the archive's own name.
    if command -v skopeo >/dev/null 2>&1; then
        skopeo copy --quiet "oci-archive:$ARCHIVE" "containers-storage:$IMAGE" ||
            die "could not load $ARCHIVE"
    else
        id="$(podman pull --quiet "oci-archive:$ARCHIVE")" || die "could not load $ARCHIVE"
        podman tag "$id" "$IMAGE"
    fi
}

# Print the name part of the disk files: the image's version label, or its tag.
image_tag() {
    local version tag="latest"
    version="$(podman image inspect --format '{{index .Labels "org.opencontainers.image.version"}}' "$IMAGE")" || true
    if [[ -n "$version" && "$version" != "<no value>" ]]; then
        tag="$version"
    elif [[ "${IMAGE##*/}" == *:* ]]; then
        tag="${IMAGE##*:}"
    fi
    printf '%s\n' "$tag" | tr -c 'A-Za-z0-9._\n-' '_'
}

# Install the image to a sparse raw disk file, the same way tests/boot-test.sh does.
install_image() {
    local raw="$1" log="$WORK/install.log" start=$SECONDS kargs=()
    if [[ "$SERIAL" -eq 1 ]]; then
        # The image boots with "rhgb quiet" for its splash screen. Show the console, systemd's
        # status lines and kernel messages on the first serial port too, and turn Plymouth off,
        # because while it runs no status lines reach the serial port.
        kargs=(--karg console=tty0 --karg "console=ttyS0,115200"
            --karg systemd.show_status=1 --karg ignore_loglevel --karg plymouth.enable=0)
    fi
    step "Installing $IMAGE to a $SIZE GiB disk (this takes a few minutes)"
    truncate -s "${SIZE}G" "$raw"
    podman run --rm --privileged --pid=host --security-opt label=disable \
        -v /var/lib/containers:/var/lib/containers -v /dev:/dev -v "$WORK:/output" \
        "$IMAGE" bootc install to-disk --via-loopback --generic-image --wipe "${kargs[@]}" \
        "/output/${raw##*/}" >"$log" 2>&1 || {
        tail -n 20 "$log" >&2
        die "the installation failed (the last lines of its output are above)"
    }
    printf 'Installed in %s s\n' "$((SECONDS - start))"
}

# Convert the raw disk: convert <raw file> <format> <output file>
convert() {
    local raw="$1" format="$2" file="$3" tmp="$3.part"
    step "Writing $file"
    case "$format" in
        # Compressed clusters keep the file small; QEMU reads them directly.
        qcow2) qemu-img convert -c -O qcow2 "$raw" "$tmp" ;;
        # A single growable file, which VMware Workstation opens as an existing disk.
        vmdk) qemu-img convert -O vmdk -o subformat=monolithicSparse,adapter_type=lsilogic "$raw" "$tmp" ;;
    esac
    mv -f "$tmp" "$file"
}

main() {
    local original=("$@") tag raw cmd format formats=() files=() file
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image | --archive | --size | --output | --formats)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --image)
                        IMAGE="$2"
                        IMAGE_SET=1
                        ;;
                    --archive) ARCHIVE="$2" ;;
                    --size) SIZE="$2" ;;
                    --output) OUTPUT="$2" ;;
                    --formats) FORMATS="$2" ;;
                esac
                shift 2
                ;;
            --serial-console)
                SERIAL=1
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
    [[ "$IMAGE_SET" -eq 0 || -z "$ARCHIVE" ]] || die "use either --image or --archive, not both"
    [[ "$SIZE" =~ ^[0-9]+$ && "$SIZE" -ge 16 ]] || die "--size needs a whole number of GiB, at least 16"
    IFS=, read -r -a formats <<<"$FORMATS"
    [[ "${#formats[@]}" -gt 0 ]] || die "--formats needs qcow2, vmdk or both"
    for format in "${formats[@]}"; do
        [[ "$format" == qcow2 || "$format" == vmdk ]] || die "unknown format: $format (use qcow2, vmdk or both)"
    done

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    for cmd in podman qemu-img; do
        command -v "$cmd" >/dev/null 2>&1 || die "$cmd is not installed (tools/check-env.sh shows what is missing)"
    done

    trap cleanup EXIT
    if [[ -n "$ARCHIVE" ]]; then
        tag="${ARCHIVE##*/}"
        IMAGE="localhost/orielos-archive:${tag%.ociarchive}"
        load_archive
    fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"
    tag="$(image_tag)"

    mkdir -p "$OUTPUT"
    WORK="$(mktemp -d "$OUTPUT/.work-XXXXXX")"
    raw="$WORK/disk.raw"
    install_image "$raw"
    for format in "${formats[@]}"; do
        file="$OUTPUT/orielos-$tag.$format"
        convert "$raw" "$format" "$file"
        files+=("$file")
    done
    rm -f "$raw"

    step "Done"
    for file in "${files[@]}"; do
        printf '%s  %s on disk, %s GiB virtual\n' "$file" "$(du -h "$file" | cut -f1)" "$SIZE"
    done
}

main "$@"

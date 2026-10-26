#!/usr/bin/env bash
# Frees the disk space that builds and VM tests leave behind, keeping only the newest build.
#
# Usage: tools/clean.sh [--all] [--help]
#   --all    also remove the newest build and its archive, and every image no container uses,
#            including the base images and the app builder, so the next build downloads and
#            builds them again
# By default it removes the VM test folders (disks kept with --keep too), the disks from
# tools/make-vm-disk.sh, images loaded from build archives, every build but the newest, stopped
# containers, untagged images, and all but the newest 5 result folders in tests/results. Other
# folders in /var/lib/orielos and other local images are listed, not removed. It refuses to run
# while a VM test is running. Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/lock.sh
source "$ROOT/tools/lib/lock.sh"
STATE="/var/lib/orielos"
RESULTS_KEPT=5
ALL=0

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Hold the lock until this script ends, so no build or VM test starts while things are removed.
# A VM started by hand, or a build or test from an older copy of the tools, holds no lock, so
# look for those too: removing a build's working containers would break it.
take_lock() {
    local running
    take_orielos_lock || exit 1
    # The kernel keeps 15 characters of a process name: qemu-system-x86_64 shows as qemu-system-x86.
    running="$(pgrep -d ' ' -x qemu-system-x86 || true)"
    [[ -z "$running" ]] || die "a VM is running (QEMU, process $running); stop it first"
    running="$(pgrep -d ' ' -f '(^|/)(podman build|buildah) ' || true)"
    [[ -z "$running" ]] || die "an image build is running (process $running); run this once it has finished"
}

# The filesystem that holds Podman's storage, where builds and VM disks go.
storage() {
    if [[ -d /var/lib/containers ]]; then
        df --output=target /var/lib/containers | tail -n 1
    else
        printf '/\n'
    fi
}

space() {
    df -h --output=used,avail,target "$(storage)" | awk 'NR == 2 { printf "%s used, %s free on %s\n", $1, $2, $3 }'
}

# Remove everything directly under a folder, printing each entry with its size.
empty_dir() {
    local dir="$1" entry n=0
    if [[ -d "$dir" ]]; then
        for entry in "$dir"/* "$dir"/.[!.]*; do
            [[ -e "$entry" || -L "$entry" ]] || continue
            printf 'removed %s (%s)\n' "${entry##*/}" "$(du -sh "$entry" 2>/dev/null | cut -f1)"
            rm -rf "${entry:?}"
            n=$((n + 1))
        done
    fi
    if [[ "$n" -eq 0 ]]; then printf 'nothing to remove\n'; fi
}

# Remove every tag of a local image repository.
remove_images() {
    local refs=() ref
    mapfile -t refs < <(podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null |
        awk -v repo="$1:" 'index($0, repo) == 1 && $0 !~ /:<none>$/' || true)
    for ref in "${refs[@]}"; do
        if podman rmi "$ref" >/dev/null 2>&1; then
            printf 'removed image %s\n' "$ref"
        else
            printf 'could not remove image %s\n' "$ref"
        fi
    done
    if [[ "${#refs[@]}" -eq 0 ]]; then printf 'nothing to remove\n'; fi
}

# A build that was interrupted leaves its working containers behind. Podman lists them only with
# --external, with the status "Storage"; no prune removes them, and they keep their images.
remove_build_containers() {
    local ids=()
    mapfile -t ids < <(podman ps --all --external --format '{{.ID}} {{.Status}}' 2>/dev/null |
        awk '$2 == "Storage" { print $1 }')
    if [[ "${#ids[@]}" -gt 0 ]]; then
        podman rm -f "${ids[@]}" >/dev/null 2>&1 || true
    fi
    printf 'removed %d containers left by builds\n' "${#ids[@]}"
}

# Keep the newest result folders in tests/results and remove the rest.
prune_results() {
    local dir="$ROOT/tests/results" old=() d
    if [[ -d "$dir" ]]; then
        mapfile -t old < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' |
            sort -rn | tail -n "+$((RESULTS_KEPT + 1))" | cut -d' ' -f2-)
    fi
    for d in "${old[@]}"; do
        rm -rf "${d:?}"
    done
    printf 'removed %d, kept the newest %d\n' "${#old[@]}" "$RESULTS_KEPT"
}

# List what the tools don't manage: other folders in $STATE and other local images.
list_others() {
    local entry others=0
    for entry in "$STATE"/*; do
        [[ -e "$entry" ]] || continue
        case "${entry##*/}" in
            builds | vm | vm-disks) continue ;;
        esac
        printf 'not removed: %s (%s)\n' "$entry" "$(du -sh "$entry" 2>/dev/null | cut -f1)"
        others=$((others + 1))
    done
    while read -r entry; do
        [[ -n "$entry" ]] || continue
        printf 'not removed: image %s\n' "$entry"
        others=$((others + 1))
    done < <(podman images --format '{{.Repository}}:{{.Tag}} ({{.Size}})' 2>/dev/null |
        grep '^localhost/' | grep -Ev '^localhost/orielos(-app-builder)?:' || true)
    if [[ "$others" -eq 0 ]]; then printf 'nothing else\n'; fi
}

main() {
    local original=("$@")
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)
                ALL=1
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

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    local cmd
    for cmd in podman flock pgrep df; do
        command -v "$cmd" >/dev/null 2>&1 || die "$cmd is not installed (tools/check-env.sh shows what is missing)"
    done
    take_lock

    step "Before: $(space)"

    step "Removing VM test folders"
    empty_dir "$STATE/vm"

    step "Removing VM disks from tools/make-vm-disk.sh"
    empty_dir "$STATE/vm-disks"

    step "Removing images loaded from build archives"
    remove_images localhost/orielos-archive

    if [[ "$ALL" -eq 1 ]]; then
        step "Removing every build"
        remove_images localhost/orielos
        empty_dir "$STATE/builds"
    else
        "$ROOT/tools/build-image.sh" --clean-only --keep 1
    fi

    step "Removing stopped containers, containers left by interrupted builds and untagged images"
    podman container prune -f >/dev/null
    remove_build_containers
    podman image prune -f >/dev/null
    if [[ "$ALL" -eq 1 ]]; then
        step "Removing every image no container uses"
        podman system prune --all --force >/dev/null
    fi

    step "Removing old test results"
    prune_results

    step "Left in place"
    list_others

    if command -v fstrim >/dev/null 2>&1; then
        fstrim "$(storage)" >/dev/null 2>&1 || true
    fi
    step "After: $(space)"

    if grep -qi microsoft /proc/version 2>/dev/null; then
        cat <<'EOF'

The space is free inside WSL, and new builds reuse it. WSL's disk file on Windows stays at the
largest size it has reached until it is compacted. To shrink it, run wsl --shutdown, then in an
administrator prompt run diskpart and enter:
  select vdisk file="<the distribution's ext4.vhdx>"
  compact vdisk
EOF
    fi
}

main "$@"

#!/usr/bin/env bash
# Builds the OrielOS image locally with rootful Podman from the inputs pinned in image/pins.env,
# and exports a compressed OCI archive for test VMs.
#
# Usage: tools/build-image.sh [--pins FILE] [--version VERSION] [--output DIR]
#                             [--no-archive] [--keep N] [--clean-only] [--use-published]
#                             [--stages-only] [--help]
#   --pins FILE        pins file (default image/pins.env)
#   --version VERSION  the build's version: vMAJOR.MINOR.PATCH for a build that is published, as
#                      CI gives it (tools/next-version.sh), or dev.<n> (the default: one more than
#                      the newest dev.<n> build here)
#   --output DIR       where the archive goes (default /var/lib/orielos/builds)
#   --no-archive       do not export an OCI archive
#   --keep N           keep the newest N builds and remove older ones (default 1)
#   --clean-only       only remove old builds, then exit
#   --use-published    start from CI's prebuilt app-deps and os-base images where they were built
#                      from this checkout's inputs (tools/lib/stage-inputs.sh)
#   --stages-only      build only the app-deps and os-base stages, labelled with their inputs, as
#                      localhost/orielos-builder and localhost/orielos-base, and export them
# The image is tagged localhost/orielos:<version> and localhost/orielos:latest.
# Runs as root; re-executes itself through sudo otherwise. Stops at once if another build or a VM
# test is running. Set ORIELOS_CCACHE_DIR to a folder to compile the apps with a compiler cache
# kept there.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
# shellcheck source=lib/pins.sh
source "$ROOT/tools/lib/pins.sh"
# shellcheck source=lib/lock.sh
source "$ROOT/tools/lib/lock.sh"
# shellcheck source=lib/stage-inputs.sh
source "$ROOT/tools/lib/stage-inputs.sh"
VERSION=""
OUTPUT="/var/lib/orielos/builds"
ARCHIVE=1
KEEP=1
CLEAN_ONLY=0
USE_PUBLISHED=0
STAGES_ONLY=0
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
    sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

check_pin() {
    local name="$1" ref="${!1:-}"
    [[ -n "$ref" ]] || die "$name is not set in $PINS"
    [[ "$ref" =~ @sha256:[0-9a-f]{64}$ ]] || die "$name in $PINS is not pinned by digest (expected <name:tag or URL>@sha256:<64 hex digits>)"
}

# The kernel an image was built for, from the local copy or else the registry.
kernel_of() {
    podman image inspect --format '{{index .Labels "ostree.linux"}}' "$1" 2>/dev/null ||
        skopeo inspect --format '{{index .Labels "ostree.linux"}}' "docker://$1"
}

# Pulls the pinned images the stages built here start from: preflight <app-deps> <os-base>, each
# the stage's name when it is built here or the prebuilt image used instead. An image that isn't
# needed is only looked up, for the kernel check.
preflight() {
    local app_deps="$1" os_base="$2" akmods_kernel nvidia_kernel var ref
    # From OrielOS's copies where it has them (tools/lib/pins.sh): upstream registries drop old
    # digests. Each pin then names the image that was pulled, with the same digest.
    step "Pulling the pinned images"
    for var in "${PINNED_IMAGES[@]}"; do
        if [[ ("$var" == BUILDER_IMAGE && "$app_deps" != app-deps) ||
            ("$var" != BUILDER_IMAGE && "$os_base" != os-base) ]]; then
            ref="$(mirror_ref "${!var}")"
            skopeo inspect --raw "docker://$ref" >/dev/null 2>&1 || ref="${!var}"
            printf -v "$var" '%s' "$ref"
            step "$var: $ref (not needed here)"
            continue
        fi
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

# Builds the app-deps and os-base stages as localhost/orielos-builder and localhost/orielos-base,
# each labelled with the hash of its inputs, and exports both to OUTPUT for publishing:
# build_stages <pinned build arguments>
build_stages() {
    local stage name inputs
    for stage in app-deps os-base; do
        case "$stage" in
            app-deps) name="$REPO-builder" ;;
            os-base) name="$REPO-base" ;;
        esac
        inputs="$(stage_inputs "$ROOT" "$stage")"
        [[ "$inputs" != uncommitted ]] || die "the $stage stage's inputs have uncommitted changes"
        step "Building the $stage stage ($name, inputs $inputs)"
        podman build --pull=missing -f "$ROOT/image/Containerfile" --target "$stage" "$@" \
            --label "$STAGE_LABEL=$inputs" -t "$name" "$ROOT"
        if [[ "$ARCHIVE" -eq 1 ]]; then
            step "Exporting $OUTPUT/${name##*/}.ociarchive"
            mkdir -p "$OUTPUT"
            rm -f "$OUTPUT/${name##*/}.ociarchive"
            podman push --compression-format zstd "$name" "oci-archive:$OUTPUT/${name##*/}.ociarchive:latest"
        fi
    done
    step "Done: $REPO-builder and $REPO-base"
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
            --use-published)
                USE_PUBLISHED=1
                shift
                ;;
            --stages-only)
                STAGES_ONLY=1
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
    # CI's prebuilt stages, where they were built from this checkout's inputs.
    local app_deps=app-deps os_base=os-base found
    if [[ "$USE_PUBLISHED" -eq 1 && "$STAGES_ONLY" -eq 0 ]]; then
        found="$(published_stage "$ROOT" app-deps)"
        app_deps="${found:-app-deps}"
        found="$(published_stage "$ROOT" os-base)"
        os_base="${found:-os-base}"
    fi
    preflight "$app_deps" "$os_base"

    local pinned=(--build-arg "BASE_IMAGE=$BASE_IMAGE"
        --build-arg "AKMODS_IMAGE=$AKMODS_IMAGE"
        --build-arg "AKMODS_NVIDIA_IMAGE=$AKMODS_NVIDIA_IMAGE"
        --build-arg "BUILDER_IMAGE=$BUILDER_IMAGE"
        --build-arg "UMU_LAUNCHER_RPM=$UMU_LAUNCHER_RPM")
    if [[ "$STAGES_ONLY" -eq 1 ]]; then
        build_stages "${pinned[@]}"
        return 0
    fi

    # The apps compile while the OS base is pulled or built; the two share nothing. The app
    # build is tagged, so the image build below copies from it instead of building it again, and
    # the cleanup's image prune keeps it, so the next build reuses its layers.
    # The compiler cache is mounted for the app build only, so it never reaches the image.
    local cache=() apps_pid
    if [[ -n "${ORIELOS_CCACHE_DIR:-}" ]]; then
        mkdir -p "$ORIELOS_CCACHE_DIR" || die "cannot create $ORIELOS_CCACHE_DIR"
        cache=(--volume "$(cd "$ORIELOS_CCACHE_DIR" && pwd):/ccache:z")
    fi
    step "Building the apps ($REPO-app-builder) from $app_deps"
    (
        set -o pipefail
        podman build --pull=missing -f "$ROOT/image/Containerfile" --target app-builder \
            --build-arg "BUILDER_IMAGE=$BUILDER_IMAGE" --build-arg "APP_DEPS_FROM=$app_deps" \
            "${cache[@]}" -t "$REPO-app-builder" "$ROOT" 2>&1 | sed -u 's/^/apps: /'
    ) &
    apps_pid=$!
    if [[ "$os_base" != os-base ]]; then
        step "Pulling the OS base $os_base"
        podman pull --quiet "$os_base" >/dev/null || {
            wait "$apps_pid" || true
            die "can't pull $os_base"
        }
        labels+=(--label "org.orielos.os-base=$os_base")
    else
        step "Building the OS base ($REPO-base)"
        if ! podman build --pull=missing -f "$ROOT/image/Containerfile" --target os-base \
            "${pinned[@]}" -t "$REPO-base" "$ROOT"; then
            wait "$apps_pid" || true
            die "the OS base failed to build"
        fi
        os_base="$REPO-base"
    fi
    wait "$apps_pid" || die "the apps failed to build, a test failed or qmllint reported a problem"

    step "Building $REPO:$tag"
    podman build --pull=missing -f "$ROOT/image/Containerfile" \
        "${pinned[@]}" \
        --build-arg "OS_BASE_FROM=$os_base" \
        --build-arg "APPS_FROM=$REPO-app-builder" \
        --build-arg "IMAGE_VERSION=$tag" \
        --unsetlabel "$STAGE_LABEL" \
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

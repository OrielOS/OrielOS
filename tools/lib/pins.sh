# shellcheck shell=bash
# Helpers for the images pinned in image/pins.env, sourced by the build tools.
#
# Upstream registries stop serving old digests: Fedora's within about a day of its tags moving.
# OrielOS keeps its own copy of every pinned image under PINS_MIRROR, with the same digest
# (tools/mirror-pins.sh, run by .github/workflows/mirror.yml), so a pin keeps working after its
# upstream registry has dropped it.

PINS_MIRROR="${PINS_MIRROR:-ghcr.io/orielos/mirror}"

# The images pinned by digest in image/pins.env.
# shellcheck disable=SC2034 # used by the tools that source this file
PINNED_IMAGES=(BASE_IMAGE AKMODS_IMAGE AKMODS_NVIDIA_IMAGE BUILDER_IMAGE)

# OrielOS's copy of a pinned image, by the same digest: mirror_ref <name:tag@sha256:digest>
# For example quay.io/fedora/fedora:44@sha256:… becomes ghcr.io/orielos/mirror/fedora@sha256:…
mirror_ref() {
    local repo="${1%@*}"
    repo="${repo%:*}"
    printf '%s/%s@%s\n' "$PINS_MIRROR" "${repo##*/}" "${1##*@}"
}

# The tag OrielOS's copy is pushed under, so it's never an untagged version: the upstream tag and
# the start of the digest, such as 44-3988086adef2: mirror_tag <name:tag@sha256:digest>
mirror_tag() {
    local tag="${1%@*}" digest="${1##*@sha256:}"
    printf '%s-%s\n' "${tag##*:}" "${digest:0:12}"
}

# Pull a pinned image, from OrielOS's copy if it has it, otherwise from upstream, and print the
# reference that was pulled, to build from: pull_pin <name:tag@sha256:digest>
pull_pin() {
    local copy
    copy="$(mirror_ref "$1")"
    if podman pull --quiet "$copy" >/dev/null 2>&1; then
        printf '%s\n' "$copy"
    elif podman pull --quiet "$1" >/dev/null; then
        printf '%s\n' "$1"
    else
        return 1
    fi
}

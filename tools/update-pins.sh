#!/usr/bin/env bash
# Shows the current registry digests of the pinned upstream images and, with --write,
# updates image/pins.env to them. Refuses to write if the kernels of the two akmods images differ.
#
# Usage: tools/update-pins.sh [--pins FILE] [--write] [--help]
#   --pins FILE   pins file to read and update (default image/pins.env)
#   --write       rewrite the pins file in place (default: only report)
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/image/pins.env"
WRITE=0
VARS=(BASE_IMAGE AKMODS_IMAGE AKMODS_NVIDIA_IMAGE BUILDER_IMAGE)

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pins)
                [[ $# -ge 2 ]] || die "--pins needs a file"
                PINS="$2"
                shift 2
                ;;
            --write)
                WRITE=1
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

    command -v skopeo >/dev/null 2>&1 || die "skopeo is not installed"
    [[ -r "$PINS" ]] || die "cannot read $PINS"
    # shellcheck source=/dev/null
    source "$PINS"

    declare -A old_digest new_digest kernel
    local var ref name_tag
    for var in "${VARS[@]}"; do
        ref="${!var:-}"
        [[ "$ref" == *@sha256:* ]] || die "$var in $PINS is not pinned by digest"
        name_tag="${ref%%@*}"
        old_digest[$var]="${ref#*@}"
        printf '==> Reading %s\n' "$name_tag"
        new_digest[$var]="$(skopeo inspect --format '{{.Digest}}' "docker://$name_tag")"
        [[ "${new_digest[$var]}" =~ ^sha256:[0-9a-f]{64}$ ]] || die "unexpected digest for $name_tag: ${new_digest[$var]}"
        kernel[$var]=""
        # Only the akmods images carry a kernel label; the others are just reported by digest.
        if [[ "$var" == AKMODS_* ]]; then
            kernel[$var]="$(skopeo inspect --format '{{index .Labels "ostree.linux"}}' "docker://${name_tag%%:*}@${new_digest[$var]}")"
        fi
    done

    local changed=0 state
    for var in "${VARS[@]}"; do
        state="unchanged"
        if [[ "${old_digest[$var]}" != "${new_digest[$var]}" ]]; then
            state="CHANGED"
            changed=1
        fi
        printf '\n%s (%s)\n  old: %s\n  new: %s\n' "$var" "$state" "${old_digest[$var]}" "${new_digest[$var]}"
        if [[ -n "${kernel[$var]}" ]]; then printf '  kernel: %s\n' "${kernel[$var]}"; fi
    done
    printf '\n'

    if [[ "${kernel[AKMODS_IMAGE]}" != "${kernel[AKMODS_NVIDIA_IMAGE]}" ]]; then
        printf 'error: kernel/NVIDIA version mismatch: akmods has %s, akmods-nvidia-open was built for %s\n' \
            "${kernel[AKMODS_IMAGE]}" "${kernel[AKMODS_NVIDIA_IMAGE]}" >&2
        if [[ "$WRITE" -eq 1 ]]; then die "not writing $PINS"; fi
        exit 1
    fi

    if [[ "$WRITE" -eq 0 ]]; then
        if [[ "$changed" -eq 1 ]]; then
            printf 'Run with --write to update %s.\n' "$PINS"
        else
            printf 'The pins are already current.\n'
        fi
        return 0
    fi

    for var in "${VARS[@]}"; do
        ref="${!var}"
        sed -i "s#^$var=.*#$var=\"${ref%%@*}@${new_digest[$var]}\"#" "$PINS"
    done
    printf '==> Updated %s. Review the versions above, build, boot-test and commit.\n' "$PINS"
}

main "$@"

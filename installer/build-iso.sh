#!/usr/bin/env bash
# Builds OrielOS.iso, the network installer: Fedora's installer (Anaconda) built with lorax under
# the OrielOS name with generic logos, which downloads the current OrielOS build of a channel from
# ghcr.io and checks its signature. Then mkksiso adds the kickstart (orielos.ks.in), an updates
# image (updates/: the installer's Anaconda profile, its DNS fix, the container signature policy
# with OrielOS's public key, and Anaconda's deploy step patched to show the download's progress)
# and inst.profile=orielos.
#
# Usage: installer/build-iso.sh [--channel stable|testing] [--output DIR] [--keep-lorax] [--help]
#   --channel CHANNEL  the channel the installer installs (default stable)
#   --output DIR       where OrielOS.iso and SHA256SUMS go (default /var/lib/orielos/installer)
#   --keep-lorax       reuse the installer environment from the last build (lorax takes several
#                      minutes); only the kickstart and the updates image are made again
# Runs as root; re-executes itself through sudo otherwise. Builds in the pinned Fedora container
# (BUILDER_IMAGE in image/pins.env), privileged, because lorax and mkksiso use loop devices.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERE="$ROOT/installer"
PINS="$ROOT/image/pins.env"
KEY="$ROOT/image/keys/orielos-cosign.pub"
# shellcheck source=/dev/null
source "$ROOT/tools/lib/pins.sh"

CHANNEL=stable
OUTPUT=/var/lib/orielos/installer
KEEP_LORAX=0

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '9,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local original=("$@")
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --channel)
                [[ $# -ge 2 ]] || die "--channel needs a value"
                CHANNEL="$2"
                shift 2
                ;;
            --output)
                [[ $# -ge 2 ]] || die "--output needs a value"
                OUTPUT="$2"
                shift 2
                ;;
            --keep-lorax)
                KEEP_LORAX=1
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "unknown option: $1"
                ;;
        esac
    done
    [[ "$CHANNEL" == stable || "$CHANNEL" == testing ]] || die "--channel is stable or testing"
    [[ "$OUTPUT" == /* ]] || die "--output needs an absolute path"

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    command -v podman >/dev/null 2>&1 || die "podman is not installed"
    grep -q 'BEGIN PUBLIC KEY' "$KEY" 2>/dev/null || die "$KEY is not OrielOS's public key"
    [[ -r "$PINS" ]] || die "cannot read $PINS"
    # shellcheck source=/dev/null
    source "$PINS"
    local builder
    builder="$(pull_pin "$BUILDER_IMAGE")" || die "can't pull $BUILDER_IMAGE from OrielOS's copy or upstream"

    # The work folder: inputs, lorax's output and the ISO. Kept between builds for --keep-lorax.
    local work="$OUTPUT/work"
    mkdir -p "$work"
    if [[ "$KEEP_LORAX" -eq 0 || ! -r "$work/lorax/images/boot.iso" ]]; then
        rm -rf "$work/lorax"
    fi
    rm -rf "$work/updates" "$work/orielos.ks" "$work/OrielOS.iso"
    cp -r "$HERE/updates" "$work/updates"
    install -D -m 0644 "$KEY" "$work/updates/etc/pki/containers/orielos.pub"
    sed "s/@CHANNEL@/$CHANNEL/" "$HERE/orielos.ks.in" >"$work/orielos.ks"
    grep -q "orielos:$CHANNEL " "$work/orielos.ks" || die "the kickstart doesn't name the $CHANNEL channel"
    cp "$HERE/fedora.repo" "$HERE/patch-anaconda.py" "$work/"

    printf '==> Building the installer for the %s channel in %s\n' "$CHANNEL" "$builder"
    podman run --rm --privileged --security-opt label=disable \
        -v /dev:/dev -v "$work:/work" "$builder" bash -c '
set -Eeuo pipefail
# grub2-common'\''s scriptlet fails on the container'\''s overlay root and dnf then exits 1, though
# everything installs, so check the tools instead.
dnf -y -q install lorax cpio squashfs-tools >/dev/null 2>&1 || true
for tool in lorax mkksiso cpio unsquashfs; do command -v "$tool" >/dev/null || { echo "$tool is missing"; exit 1; }; done
cd /work
if [[ ! -r lorax/images/boot.iso ]]; then
    rm -rf lorax tmp
    mkdir -p tmp
    echo "==> lorax (several minutes)"
    lorax -p OrielOS -v "$(rpm -E %fedora)" -r "$(rpm -E %fedora)" --isfinal --volid OrielOS-x86_64 --nomacboot \
        --skip-branding -i generic-release -i generic-logos --repo /work/fedora.repo \
        --tmp /work/tmp --logfile /work/lorax.log lorax >/work/lorax.out 2>&1 \
        || { tail -40 /work/lorax.out; exit 1; }
    rm -rf tmp
fi
# NetworkManager writes the name servers here (updates/etc/NetworkManager/conf.d/90-orielos-dns.conf).
ln -sfn /run/NetworkManager/resolv.conf updates/etc/resolv.conf
# Download progress for the deploy step: patch this installer'\''s own copy of Anaconda'\''s deploy
# code and ship it with fresh bytecode, so the installer can'\''t use its stale .pyc files.
rel=$(unsquashfs -l lorax/images/install.img | sed -n "s|^squashfs-root/||p" \
    | grep "/pyanaconda/modules/payloads/payload/rpm_ostree/installation.py$")
[[ -n "$rel" ]] || { echo "installation.py is not in install.img"; exit 1; }
rm -rf anaconda-src
unsquashfs -q -d anaconda-src lorax/images/install.img "$rel" >/dev/null
install -D -m 0644 "anaconda-src/$rel" "updates/$rel"
rm -rf anaconda-src
python3 /work/patch-anaconda.py "updates/$rel"
python3 -c "
import py_compile, sys
src = sys.argv[1]
base = src.rsplit(\"/\", 1)[0] + \"/__pycache__/installation.\" + sys.implementation.cache_tag
for opt, suffix in ((0, \".pyc\"), (1, \".opt-1.pyc\")):
    py_compile.compile(src, cfile=base + suffix, optimize=opt, doraise=True,
                       invalidation_mode=py_compile.PycInvalidationMode.TIMESTAMP)
" "updates/$rel"
(cd updates && find . | cpio -o -H newc --quiet | gzip -9) >updates.img
echo "==> mkksiso"
mkksiso --ks orielos.ks -u updates.img -c "inst.profile=orielos" lorax/images/boot.iso OrielOS.iso \
    >/work/mkksiso.out 2>&1 || { tail -40 /work/mkksiso.out; exit 1; }
'
    mv -f "$work/OrielOS.iso" "$OUTPUT/OrielOS.iso"
    (cd "$OUTPUT" && sha256sum OrielOS.iso >SHA256SUMS)
    local size
    size="$(stat -c %s "$OUTPUT/OrielOS.iso")"
    # GitHub Releases take files under 2 GiB.
    [[ "$size" -lt 2147483648 ]] || die "OrielOS.iso is $size bytes, over GitHub's 2 GiB limit"
    printf '==> Done: %s (%s MB), installs ghcr.io/ncjsvr/orielos:%s\n' "$OUTPUT/OrielOS.iso" "$((size / 1000000))" "$CHANNEL"
    cat "$OUTPUT/SHA256SUMS"
}

main "$@"

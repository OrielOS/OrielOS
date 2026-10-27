#!/usr/bin/env bash
# Builds OrielOS.iso, the network installer: Fedora's installer (Anaconda) built with lorax under
# the OrielOS name with generic logos, which downloads the current OrielOS build of a channel from
# ghcr.io and checks its signature. Then mkksiso adds the kickstart (orielos.ks.in), an updates
# image (updates/: the installer's Anaconda profile, its DNS fix, the container signature policy
# with OrielOS's public key, and Anaconda patched by patch-anaconda.py) and inst.profile=orielos.
# The installer and its boot menu name the OrielOS version the channel has when it's built.
#
# Usage: installer/build-iso.sh [--channel stable|testing] [--version vX.Y.Z] [--output DIR]
#                               [--keep-lorax] [--help]
#   --channel CHANNEL  the channel the installer installs (default stable)
#   --version VERSION  the version the installer shows (default: the channel's current build's)
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
VERSION=""
OUTPUT=/var/lib/orielos/installer
KEEP_LORAX=0

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '9,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
            --version)
                [[ $# -ge 2 ]] || die "--version needs a value"
                VERSION="$2"
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
    [[ -z "$VERSION" || "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version is vMAJOR.MINOR.PATCH"
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
        -e "CHANNEL=$CHANNEL" -e "VERSION=$VERSION" \
        -v /dev:/dev -v "$work:/work" "$builder" bash -c '
set -Eeuo pipefail
# grub2-common'\''s scriptlet fails on the container'\''s overlay root and dnf then exits 1, though
# everything installs, so check the tools instead.
dnf -y -q install lorax cpio squashfs-tools skopeo >/dev/null 2>&1 || true
for tool in lorax mkksiso cpio unsquashfs skopeo python3; do command -v "$tool" >/dev/null || { echo "$tool is missing"; exit 1; }; done
cd /work
# The installer shows the version of OrielOS the channel has now, which is what it installs
# until a newer one arrives. A channel with no build yet is named instead.
if [[ -z "$VERSION" ]]; then
    VERSION="$(skopeo inspect --no-tags "docker://ghcr.io/ncjsvr/orielos:$CHANNEL" 2>/dev/null |
        python3 -c "import json, sys; print(json.load(sys.stdin)[\"Labels\"].get(\"org.opencontainers.image.version\", \"\"))" ||
        true)"
fi
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "warning: no OrielOS version found for the $CHANNEL channel; the installer shows the channel instead"
    VERSION="$CHANNEL"
fi
echo "==> The installer shows OrielOS $VERSION"
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
# Patch this installer'\''s own copy of Anaconda (patch-anaconda.py: download progress, the
# version shown whole, the BitLocker warning) and ship the files with fresh bytecode, so the
# installer can'\''t use its stale .pyc files.
py=$(unsquashfs -l lorax/images/install.img | sed -n "s|^squashfs-root/||p" \
    | grep "/site-packages/pyanaconda/__init__.py$")
[[ -n "$py" ]] || { echo "Anaconda is not in install.img"; exit 1; }
py="${py%/__init__.py}"
files=(modules/payloads/payload/rpm_ostree/installation.py core/product.py ui/helpers.py
    modules/storage/checker/utils.py)
rm -rf anaconda-src
unsquashfs -q -d anaconda-src lorax/images/install.img .buildstamp "${files[@]/#/$py/}" >/dev/null
for f in "${files[@]}"; do install -D -m 0644 "anaconda-src/$py/$f" "updates/$py/$f"; done
python3 /work/patch-anaconda.py "updates/$py"
python3 -c "
import py_compile, sys
for src in sys.argv[1:]:
    folder, name = src.rsplit(\"/\", 1)
    base = folder + \"/__pycache__/\" + name[:-3] + \".\" + sys.implementation.cache_tag
    for opt, suffix in ((0, \".pyc\"), (1, \".opt-1.pyc\")):
        py_compile.compile(src, cfile=base + suffix, optimize=opt, doraise=True,
                           invalidation_mode=py_compile.PycInvalidationMode.TIMESTAMP)
" "${files[@]/#/updates/$py/}"
# Anaconda names the product from /.buildstamp, which lorax writes with the Fedora release.
grep -q "^Version=" anaconda-src/.buildstamp || { echo ".buildstamp has no Version"; exit 1; }
sed "s/^Version=.*/Version=$VERSION/" anaconda-src/.buildstamp >updates/.buildstamp
rm -rf anaconda-src
(cd updates && find . | cpio -o -H newc --quiet | gzip -9) >updates.img
echo "==> mkksiso"
fedora="$(rpm -E %fedora)"
grep -q "OrielOS $fedora" lorax/EFI/BOOT/grub.cfg || { echo "the boot menu doesn'\''t say OrielOS $fedora"; exit 1; }
mkksiso --ks orielos.ks -u updates.img -c "inst.profile=orielos" \
    -R "OrielOS $fedora" "OrielOS $VERSION" -R "Rescue a OrielOS system" "Rescue an OrielOS system" \
    lorax/images/boot.iso OrielOS.iso >/work/mkksiso.out 2>&1 || { tail -40 /work/mkksiso.out; exit 1; }
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

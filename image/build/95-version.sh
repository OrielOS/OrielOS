#!/usr/bin/env bash
# Records the build's version where the system shows it, in the image's last layer:
# - os-release names OrielOS and the version. The boot menu's entries, the Settings app and system
#   tools read it; the boot menu shows PRETTY_NAME, so it carries the version. Fedora's ID,
#   VERSION_ID and CPE_NAME stay, so tools that look for the Fedora release the packages come from
#   still find it.
# - A kernel argument, orielos.build=<version>. Builds often share a kernel and initramfs, and ostree
#   treats deployments with the same kernel, initramfs and arguments as having the same boot
#   entries: when going back changes their order it only repoints them, and each entry keeps the
#   other build's name. With an argument that differs, it writes the entries again.
# Usage: 95-version.sh VERSION
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

version="${1:-}"
[[ "$version" =~ ^[0-9A-Za-z._-]+$ ]] || die "usage: 95-version.sh VERSION (letters, digits and . _ - only)"

file=/usr/lib/os-release
[[ -f "$file" && ! -L "$file" ]] || die "$file is missing or a link"

# Fedora's links send people to Fedora's support and bug tracker, which don't cover OrielOS.
tmp="$(mktemp)"
grep -v -E '^(NAME|VERSION|PRETTY_NAME|HOME_URL|DOCUMENTATION_URL|SUPPORT_URL|BUG_REPORT_URL|DEFAULT_HOSTNAME|IMAGE_ID|IMAGE_VERSION|REDHAT_[A-Z_]+)=' \
    "$file" >"$tmp" || true
cat >>"$tmp" <<EOF
NAME="OrielOS"
VERSION="$version"
PRETTY_NAME="OrielOS $version"
IMAGE_ID=orielos
IMAGE_VERSION=$version
DEFAULT_HOSTNAME="orielos"
HOME_URL="https://orielos.org/"
DOCUMENTATION_URL="https://github.com/ncjsvr/OrielOS/tree/main/docs"
SUPPORT_URL="https://github.com/ncjsvr/OrielOS/discussions"
BUG_REPORT_URL="https://github.com/ncjsvr/OrielOS/issues"
EOF
install -m 0644 "$tmp" "$file"
rm -f "$tmp"

# One line for each key, and the name and version as written.
for key in NAME VERSION PRETTY_NAME IMAGE_ID IMAGE_VERSION ID VERSION_ID; do
    count="$(grep -c -E "^$key=" "$file" || true)"
    [[ "$count" -eq 1 ]] || die "$file has $count $key lines"
done
# shellcheck source=/dev/null
(. "$file" && [[ "$PRETTY_NAME" == "OrielOS $version" && "$IMAGE_VERSION" == "$version" && "$ID" == fedora ]]) ||
    die "$file does not name OrielOS $version"

kargs=/usr/lib/bootc/kargs.d/90-orielos-build.toml
mkdir -p "${kargs%/*}"
cat >"$kargs" <<EOF
# The build's version, so two builds never have the same boot entries (see image/build/95-version.sh).
kargs = ["orielos.build=$version"]
EOF
chmod 0644 "$kargs"
grep -q "^kargs = \[\"orielos.build=$version\"\]$" "$kargs" || die "$kargs does not set orielos.build=$version"

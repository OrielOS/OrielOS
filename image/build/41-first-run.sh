#!/usr/bin/env bash
# The first-run setup, Plasma Setup: puts its pages in OrielOS's order (language, keyboard, network,
# time zone, power, account), removes the display and device-name pages, which OrielOS doesn't ask
# about, and shows the OrielOS logo on the last page instead of Konqi. OrielOS's own network and
# power pages come from plasma/firstrun. Plasma Setup orders its pages by each package's
# X-KDE-Weight, so this changes the weights in place. It fails the build unless every file it
# changes is the version it was written for, so a Plasma update can't be changed blindly; then
# check the new files and update the checksums here.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

PACKAGES=/usr/share/plasma/packages
# sha256 of each page's metadata.json in plasma-setup 6.7.5.
declare -A METADATA_SUMS=(
    [language]=43ed694acf5a38e6257b7684e87145cd0f7fe5bdd1fd0153c14de4d9ec9cdb0d
    [keyboard]=ba792eea0eb9dcb0919945e510a861c8c1c97c3c3115fdc8542664f40bf05aef
    [prepare]=e429621b9e07e14ebe002169ac85ca2e6c076f3951ee026d28511de0437cd4c3
    [account]=97bb689c9a14d323e7ec3bff1c30c69fa9fc84c0c451b03d72ccde2e6d492ddd
    [hostname]=efe6aa2b919eb3e5e7abb5e0210f1dd623f20cb54430ea871d239c7b76b210fa
    [time]=23fd1bd8b3f461942eb7dcb1c1f9b0732cbe11aef741a30f155e050719abc0f2
    [wifi]=90d36d9bfd5c7455905a9a693a459ca655e6c0fa470e3d3f9f6101cf7bad1aeb
    [finished]=7fcbc52132eb2ba75ace08cd5b1124dc8b67f9ed3eeb1d57a4f5e68ca000ad84
)
# The weights OrielOS gives Plasma Setup's pages. OrielOS's network page is 11 and its power page
# 18; the finished page stays at 200.
declare -A WEIGHTS=([language]=0 [keyboard]=5 [wifi]=10 [time]=15 [account]=20)
REMOVE=(prepare hostname)
FINISHED_UI="$PACKAGES/org.kde.plasmasetup.finished/contents/ui"
# sha256 of the finished page's konqi-calling.png in plasma-setup 6.7.5.
KONQI_SUM=7183631a020d2017997b259ac925519f48beaf4fc173b4c126cc688415ed3be1
# The OrielOS logo, installed from the apps build (plasma/CMakeLists.txt).
FINISHED_LOGO=/usr/share/orielos/first-run/finished-logo.png

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Fail unless a file has the expected sha256: check_sum <file> <sha256>
check_sum() {
    local actual
    [[ -f "$1" ]] || die "$1 does not exist; plasma-setup's packaging changed, so update image/build/41-first-run.sh"
    actual="$(sha256sum "$1" | cut -d' ' -f1)"
    [[ "$actual" == "$2" ]] ||
        die "$1 is not the version image/build/41-first-run.sh was written for (sha256 $actual); check the new file and update the checksum"
}

main() {
    local page file
    for page in "${!METADATA_SUMS[@]}"; do
        check_sum "$PACKAGES/org.kde.plasmasetup.$page/metadata.json" "${METADATA_SUMS[$page]}"
    done
    check_sum "$FINISHED_UI/konqi-calling.png" "$KONQI_SUM"

    for page in "${!WEIGHTS[@]}"; do
        file="$PACKAGES/org.kde.plasmasetup.$page/metadata.json"
        jq --indent 4 --argjson weight "${WEIGHTS[$page]}" '."X-KDE-Weight" = $weight' "$file" >"$file.new"
        chmod --reference="$file" "$file.new"
        mv "$file.new" "$file"
    done
    for page in "${REMOVE[@]}"; do
        rm -rf "${PACKAGES:?}/org.kde.plasmasetup.$page"
    done
    # The page loads the image by this name. Konqi's licence note goes with Konqi.
    ln -sf "$FINISHED_LOGO" "$FINISHED_UI/konqi-calling.png"
    rm -f "$FINISHED_UI/konqi-calling.png.license"

    printf 'first-run setup: ordered the pages of plasma-setup %s and removed %s\n' \
        "$(rpm -q --qf '%{VERSION}' plasma-setup)" "${REMOVE[*]}"
}

main "$@"

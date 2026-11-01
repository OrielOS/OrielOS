#!/usr/bin/env bash
# The first-run setup, Plasma Setup: puts its pages in OrielOS's order (language, keyboard, network,
# time zone, power, the computer's name, account), removes the display page, which OrielOS doesn't
# ask about, and its time zone page, which OrielOS's own replaces, and shows the OrielOS logo on the
# last page instead of Konqi. OrielOS's own network, time zone and power pages come from
# plasma/firstrun. Plasma Setup orders its pages by each package's
# X-KDE-Weight, so this changes the weights in place. It fails the build unless every file it
# changes is the version it was written for, so a Plasma update can't be changed blindly; then
# check the new files and update the checksums here.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

PACKAGES=/usr/share/plasma/packages
# sha256 of each page's metadata.json in plasma-setup 6.8.2.
declare -A METADATA_SUMS=(
    [language]=ad55415b4c4d468957ee02a2bd437e846b27a4891df13f95be3c5b62e29e9d0b
    [keyboard]=5222cc5bd731a414c5aea3617abd717c6e1ca15b445e644c54947c473c112612
    [prepare]=2c77e29cafcee3e20bfe857e342c6f05a9b505b048754737fdf0b11e2fa1868b
    [account]=f3f27a603db3c704a264c04bf93f26a804d41f12885d69b3bdf03e2411e309d0
    [hostname]=5ae15d723257d305bc5064717daf1e3e07ba168faf4c383644c4a5e5c483edb5
    [time]=ae6797c64bbfaed52783ef506ade750f51ccbf003cf2d310f3f4687d031a8035
    [wifi]=820ed61cf9a6d5e0e813fee3334d74fc67555cc07c91cbd49aeaa8b8d820e69a
    [finished]=14f846bf110d674002a685135508b7d1ebdd30da48717ab8bfc8e333758490b1
)
# The weights OrielOS gives Plasma Setup's pages. OrielOS's network page is 11, its time zone page
# 15 and its power page 18; the finished page stays at 200.
# The computer's name comes after the power page (18) and before the account, as Windows asks it.
declare -A WEIGHTS=([language]=0 [keyboard]=5 [wifi]=10 [hostname]=19 [account]=20)
REMOVE=(prepare time)
FINISHED_UI="$PACKAGES/org.kde.plasmasetup.finished/contents/ui"
# sha256 of the finished page's konqi-calling.png in plasma-setup 6.8.2.
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

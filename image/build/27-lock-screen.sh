#!/usr/bin/env bash
# The lock screen: installs OrielOS's copy of Plasma's lock screen layout, which puts the time
# and date under the sill of the OrielOS wallpaper. Plasma 6 takes the lock screen from the
# desktop shell package, which a look-and-feel package can't override, so this replaces that
# one file. It fails the build unless Plasma's file is exactly the version OrielOS's copy is
# based on, so a Plasma update can't silently mix the two; then rebase image/lockscreen/ on
# the new file and update the checksum here.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

target=/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml
# sha256 of LockScreenUi.qml in plasma-desktop 6.7.5.
upstream=328501780ab06cc0497a25ff48c6f027a1abed8506f0969f39a5f8bc6696181c

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

main() {
    local actual
    [[ -f "$target" ]] || die "$target does not exist; plasma-desktop's packaging changed, so update image/build/27-lock-screen.sh"
    actual="$(sha256sum "$target" | cut -d' ' -f1)"
    [[ "$actual" == "$upstream" ]] ||
        die "$target is not the version image/lockscreen/LockScreenUi.qml is based on (sha256 $actual); rebase the copy on the new file and update the checksum in image/build/27-lock-screen.sh"
    install -m 0644 /lockscreen/LockScreenUi.qml "$target"
    printf 'lock screen: installed OrielOS LockScreenUi.qml over plasma-desktop %s\n' \
        "$(rpm -q --qf '%{VERSION}' plasma-desktop)"
}

main "$@"

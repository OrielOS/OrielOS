#!/usr/bin/env bash
# The sign-in screen: installs OrielOS's SDDM theme and makes it the one SDDM shows. The theme is
# Breeze's with OrielOS's Main.qml, metadata and settings from image/sddm/orielos (mounted at
# /sddm): Breeze's other files are copied in unchanged. It fails the build unless Breeze's
# Main.qml is exactly the version OrielOS's is based on, so a Plasma update can't mix the two;
# then rebase image/sddm/orielos/Main.qml on the new file and update the checksum here.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

breeze=/usr/share/sddm/themes/breeze
theme=/usr/share/sddm/themes/orielos
# sha256 of Main.qml in sddm-breeze 6.7.5.
upstream=136ce0f867812b97e0e19f687e6b5ee90270068ef58149833c281d2c70c4a3af

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

main() {
    local actual f
    [[ -f "$breeze/Main.qml" ]] || die "$breeze/Main.qml does not exist; sddm-breeze's packaging changed, so update image/build/28-sign-in.sh"
    actual="$(sha256sum "$breeze/Main.qml" | cut -d' ' -f1)"
    [[ "$actual" == "$upstream" ]] ||
        die "$breeze/Main.qml is not the version image/sddm/orielos/Main.qml is based on (sha256 $actual); rebase the copy on the new file and update the checksum in image/build/28-sign-in.sh"

    install -d "$theme"
    cp -a "$breeze/." "$theme/"
    rm -f "$theme/preview.png"
    for f in Main.qml metadata.desktop theme.conf; do
        install -m 0644 "/sddm/$f" "$theme/$f"
    done

    # Fedora's /usr/lib/sddm/sddm.conf.d chooses its own Breeze variant; /etc/sddm.conf.d comes after
    # it, so this setting wins.
    install -d /etc/sddm.conf.d
    printf '[Theme]\nCurrent=orielos\n' >/etc/sddm.conf.d/10-orielos-theme.conf
    printf 'sign-in screen: installed the orielos SDDM theme over sddm-breeze %s\n' "$(rpm -q --qf '%{VERSION}' sddm-breeze)"
}

main "$@"

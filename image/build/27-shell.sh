#!/usr/bin/env bash
# The OrielOS shell: checks that the Plasma files OrielOS's shell package (plasma/shell/) carries
# changed copies of are those of the Plasma this image installs: a full copy of Plasma's lock screen
# folder, with OrielOS's clock, because its files load each other by relative path, and the popup
# for taskbar widgets (applet/CompactApplet.qml). When a Plasma update changes any of them, the
# build stops here: rebase the copies on the new files and update plasma/shell/upstream.sha256.
# The package itself is installed with the apps, and /etc/xdg/plasmashellrc and
# /etc/xdg/plasma-workspace/env/orielos-shell.sh make it the default; 90-finalise.sh checks both.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

plasma_shell=/usr/share/plasma/shells/org.kde.plasma.desktop/contents
sums=/shell/upstream.sha256

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

main() {
    local listed actual
    [[ -d "$plasma_shell/lockscreen" ]] ||
        die "$plasma_shell/lockscreen does not exist; plasma-desktop's packaging changed, so update image/build/27-shell.sh"
    [[ -r "$sums" ]] || die "$sums is missing"
    # Every lock screen file Plasma ships must be listed, and every listed file must match.
    listed="$(awk '{print $2}' "$sums" | sort)"
    actual="$(cd "$plasma_shell" && { find lockscreen -type f && echo applet/CompactApplet.qml; } | sort)"
    [[ "$listed" == "$actual" ]] ||
        die "plasma-desktop's lock screen files differ from the list in plasma/shell/upstream.sha256; rebase plasma/shell/org.orielos.desktop/contents/lockscreen/ on them"
    (cd "$plasma_shell" && sha256sum --quiet -c "$sums") ||
        die "plasma-desktop $(rpm -q --qf '%{VERSION}' plasma-desktop) changed files the OrielOS shell copies; rebase plasma/shell/org.orielos.desktop/contents/ on them and update plasma/shell/upstream.sha256"
    printf 'shell: the OrielOS shell'\''s copies match plasma-desktop %s\n' "$(rpm -q --qf '%{VERSION}' plasma-desktop)"
}

main "$@"

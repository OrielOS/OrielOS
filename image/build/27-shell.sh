#!/usr/bin/env bash
# The OrielOS shell: checks that the lock screen in OrielOS's shell package (plasma/shell/) is
# based on the lock screen of the Plasma this image installs. The shell package carries a full copy
# of Plasma's lock screen folder, with OrielOS's clock, because its files load each other by
# relative path. When a Plasma update changes any of Plasma's lock screen files, the build stops
# here: rebase the copy on the new files and update plasma/shell/lockscreen-upstream.sha256.
# The package itself is installed with the apps, and /etc/xdg/plasmashellrc and
# /etc/xdg/plasma-workspace/env/orielos-shell.sh make it the default; 90-finalise.sh checks both.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

plasma_shell=/usr/share/plasma/shells/org.kde.plasma.desktop/contents
sums=/shell/lockscreen-upstream.sha256

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

main() {
    local listed actual
    [[ -d "$plasma_shell/lockscreen" ]] ||
        die "$plasma_shell/lockscreen does not exist; plasma-desktop's packaging changed, so update image/build/27-shell.sh"
    [[ -r "$sums" ]] || die "$sums is missing"
    # Every file Plasma ships must be listed, and every listed file must match.
    listed="$(awk '{print $2}' "$sums" | sort)"
    actual="$(cd "$plasma_shell" && find lockscreen -type f | sort)"
    [[ "$listed" == "$actual" ]] ||
        die "plasma-desktop's lock screen files differ from the list in plasma/shell/lockscreen-upstream.sha256; rebase plasma/shell/org.orielos.desktop/contents/lockscreen/ on them"
    (cd "$plasma_shell" && sha256sum --quiet -c "$sums") ||
        die "plasma-desktop $(rpm -q --qf '%{VERSION}' plasma-desktop) changed its lock screen; rebase plasma/shell/org.orielos.desktop/contents/lockscreen/ on it and update plasma/shell/lockscreen-upstream.sha256"
    printf 'shell: the OrielOS lock screen matches plasma-desktop %s\n' "$(rpm -q --qf '%{VERSION}' plasma-desktop)"
}

main "$@"

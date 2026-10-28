#!/usr/bin/env bash
# Copies the OrielOS shell from this checkout onto a running OrielOS computer over SSH, for trying
# changes without building an image: the shell package, OrielOS's Plasma theme and widgets, its KWin
# effects, its line icons, the settings that make them the desktop, and the sign-in theme. OrielOS's
# /usr (and /usr/local) is read-only, so the files go to /var/usrlocal/orielos-sideload/share,
# which carries /usr's SELinux label: a session environment
# script puts it first on XDG_DATA_DIRS for Plasma and the lock screen, and an SDDM setting points
# the sign-in screen at its themes. Every file it places is listed on the computer in
# /var/usrlocal/orielos-sideload/manifest, so --undo can take them all away again; undo before
# moving the computer to an image that has the shell built in.
#
# Usage: tools/sideload-shell.sh [--apps] [--restart USER] [--undo] [--help] HOST
#   HOST            an SSH destination (user@host) whose user can use sudo without a password
#   --apps          also sideload OrielOS's compiled Plasma widgets (such as Start) and window frames from the app
#                   build, localhost/orielos-app-builder (tools/test-apps.sh), or
#                   ORIELOS_APP_IMAGE; QT_PLUGIN_PATH puts them before the installed ones
#   --restart USER  restart USER's Plasma desktop afterwards, so a signed-in session shows the change
#   --undo          remove everything an earlier sideload placed, instead of copying
# A signed-in session picks up the new search path the next time it signs in; the lock screen shows
# a change the next time the screen locks, and the sign-in screen the next time it appears.
# ORIELOS_SSH_KEY, if set, is the SSH key to use.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_OPTS=(-o BatchMode=yes)
if [[ -n "${ORIELOS_SSH_KEY:-}" ]]; then SSH_OPTS+=(-i "$ORIELOS_SSH_KEY"); fi
HOST=""
RESTART_USER=""
UNDO=0
APPS=0
APP_IMAGE="${ORIELOS_APP_IMAGE:-localhost/orielos-app-builder}"
STAGING=""

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cleanup() {
    if [[ -n "$STAGING" ]]; then rm -rf -- "$STAGING"; fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --restart)
                [[ $# -ge 2 ]] || die "--restart needs a user name"
                RESTART_USER="$2"
                shift 2
                ;;
            --undo)
                UNDO=1
                shift
                ;;
            --apps)
                APPS=1
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            -*) die "unknown option: $1 (see --help)" ;;
            *)
                [[ -z "$HOST" ]] || die "only one HOST can be given"
                HOST="$1"
                shift
                ;;
        esac
    done
    [[ -n "$HOST" ]] || die "no HOST given (see --help)"
    if [[ -n "$RESTART_USER" && ! "$RESTART_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        die "not a user name: $RESTART_USER"
    fi
}

# The script that runs on the computer, as root, with the arguments UNDO and RESTART_USER. It reads
# the files to place from a tar stream on standard input (nothing for --undo).
remote_script() {
    cat <<'REMOTE'
set -Eeuo pipefail
state=/var/usrlocal/orielos-sideload
data="$state/share"
manifest="$state/manifest"
undo="$1"
restart_user="$2"

remove_placed() {
    if [[ -f "$manifest" ]]; then
        while IFS= read -r path; do
            case "$path" in
                /var/usrlocal/orielos-sideload/* | /etc/xdg/* | /etc/sddm.conf.d/*) rm -rf -- "$path" ;;
                *) printf 'skipped an unexpected path in the manifest: %s\n' "$path" >&2 ;;
            esac
        done <"$manifest"
    fi
    rm -rf -- "$state"
}

remove_placed
if [[ "$undo" == 1 ]]; then
    echo "removed the sideloaded shell"
else
    staging="$(mktemp -d)"
    trap 'rm -rf -- "$staging"' EXIT
    tar -C "$staging" -x
    mkdir -p "$data/plasma/shells" "$data/plasma/desktoptheme" "$data/plasma/plasmoids" "$data/sddm/themes" "$data/icons/hicolor/scalable/actions" "$data/kwin/effects" "$data/kwin/tabbox" /etc/sddm.conf.d
    : >"$manifest"
    place() { # place SOURCE TARGET
        cp -a -- "$1" "$2"
        printf '%s\n' "$2" >>"$manifest"
    }
    write() { # write TARGET, with the content on standard input
        cat >"$1"
        printf '%s\n' "$1" >>"$manifest"
    }
    place "$staging/shell/org.orielos.desktop" "$data/plasma/shells/org.orielos.desktop"
    place "$staging/desktoptheme/orielos" "$data/plasma/desktoptheme/orielos"
    for widget in "$staging"/plasmoids/*; do
        place "$widget" "$data/plasma/plasmoids/${widget##*/}"
    done
    place "$staging/kwin/snaplayouts" "$data/kwin/effects/orielos-snaplayouts"
    place "$staging/kwin/switcher" "$data/kwin/tabbox/org.orielos.switcher"
    for icon in "$staging"/icons/*.svg; do
        place "$icon" "$data/icons/hicolor/scalable/actions/${icon##*/}"
    done
    place "$staging/etc/plasmashellrc" /etc/xdg/plasmashellrc
    place "$staging/etc/plasmarc" /etc/xdg/plasmarc
    place "$staging/etc/kwinrc" /etc/xdg/kwinrc
    place "$staging/etc/orielos-shell.sh" /etc/xdg/plasma-workspace/env/orielos-shell.sh
    plugin_path=""
    if [[ -d "$staging/plugins" ]]; then
        place "$staging/plugins" "$state/plugins"
        plugin_path="QT_PLUGIN_PATH=\"$state/plugins\${QT_PLUGIN_PATH:+:\$QT_PLUGIN_PATH}\"
export QT_PLUGIN_PATH"
    fi
    write /etc/xdg/plasma-workspace/env/orielos-sideload.sh <<ENV
XDG_DATA_DIRS="$data:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export XDG_DATA_DIRS
$plugin_path
ENV
    # The sign-in theme is Breeze's with OrielOS's files over it, as the image build makes it.
    theme="$data/sddm/themes/orielos"
    mkdir -p "$theme"
    cp -a /usr/share/sddm/themes/breeze/. "$theme/"
    rm -f "$theme/preview.png"
    cp -- "$staging"/sddm/* "$theme/"
    write /etc/sddm.conf.d/90-orielos-sideload.conf <<CONF
[Theme]
ThemeDir=$data/sddm/themes
Current=orielos
CONF
    restorecon -R "$state" /etc/xdg /etc/sddm.conf.d 2>/dev/null || true
    echo "placed $(wc -l <"$manifest") items; see $manifest"
fi
if [[ -n "$restart_user" ]]; then
    uid="$(id -u "$restart_user")"
    as_user() {
        runuser -u "$restart_user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
    }
    # A running session read its environment when it started; give it the sideload's.
    if [[ -d "$state/plugins" ]]; then
        as_user systemctl --user set-environment "QT_PLUGIN_PATH=$state/plugins" || true
    else
        as_user systemctl --user unset-environment QT_PLUGIN_PATH || true
    fi
    if [[ "$undo" != 1 ]]; then
        current="$(as_user systemctl --user show-environment | sed -n 's/^XDG_DATA_DIRS=//p')"
        case ":$current:" in
            *":$data:"*) ;;
            *) as_user systemctl --user set-environment "XDG_DATA_DIRS=$data:${current:-/usr/local/share:/usr/share}" || true ;;
        esac
    fi
    if as_user systemctl --user restart plasma-plasmashell.service; then
        as_user dbus-send --session --dest=org.kde.KWin --type=method_call /KWin org.kde.KWin.reconfigure || true
        echo "restarted $restart_user's desktop"
    else
        echo "could not restart $restart_user's desktop; sign out and in again to see the change" >&2
    fi
fi
REMOTE
}

main() {
    parse_args "$@"
    local script
    script="$(remote_script)"
    if [[ "$UNDO" -eq 1 ]]; then
        step "Removing the sideloaded shell from $HOST"
        ssh "${SSH_OPTS[@]}" "$HOST" sudo bash -c "$(printf '%q' "$script")" sideload 1 "$(printf '%q' "$RESTART_USER")" </dev/null
        return
    fi
    trap cleanup EXIT
    STAGING="$(mktemp -d)"
    mkdir -p "$STAGING/shell" "$STAGING/desktoptheme" "$STAGING/etc" "$STAGING/sddm"
    cp -a "$ROOT/plasma/shell/org.orielos.desktop" "$STAGING/shell/"
    cp -a "$ROOT/plasma/desktoptheme/orielos" "$STAGING/desktoptheme/"
    cp -a "$ROOT/plasma/plasmoids" "$STAGING/plasmoids"
    mkdir -p "$STAGING/icons"
    cp -a "$ROOT/plasma/kwin" "$STAGING/kwin"
    cp "$ROOT"/artwork/icons/*-symbolic.svg "$STAGING/icons/"
    cp "$ROOT/image/system/etc/xdg/plasmarc" "$STAGING/etc/plasmarc"
    cp "$ROOT/image/system/etc/xdg/kwinrc" "$STAGING/etc/kwinrc"
    cp "$ROOT/image/system/etc/xdg/plasmashellrc" "$STAGING/etc/plasmashellrc"
    cp "$ROOT/image/system/etc/xdg/plasma-workspace/env/orielos-shell.sh" "$STAGING/etc/orielos-shell.sh"
    cp "$ROOT"/image/sddm/orielos/*.qml "$ROOT/image/sddm/orielos/metadata.desktop" \
        "$ROOT/image/sddm/orielos/theme.conf" "$STAGING/sddm/"
    if [[ "$APPS" -eq 1 ]]; then
        local container
        container="$(podman create "$APP_IMAGE" true)" || die "can't use $APP_IMAGE; run tools/test-apps.sh first"
        mkdir -p "$STAGING/plugins/plasma"
        podman cp "$container:/out/usr/lib64/qt6/plugins/plasma/applets" "$STAGING/plugins/plasma/applets"
        podman cp "$container:/out/usr/lib64/qt6/plugins/org.kde.kdecoration3" "$STAGING/plugins/org.kde.kdecoration3"
        podman cp "$container:/out/usr/lib64/qt6/plugins/plasma/containmentactions" "$STAGING/plugins/plasma/containmentactions"
        podman rm -f "$container" >/dev/null
        find "$STAGING/plugins" -type f ! -name 'org.orielos.*' -delete
    fi
    step "Sideloading the shell from $(git -C "$ROOT" log -1 --format='%h %s' 2>/dev/null || echo "$ROOT") onto $HOST"
    tar -C "$STAGING" -c . | ssh "${SSH_OPTS[@]}" "$HOST" sudo bash -c "$(printf '%q' "$script")" sideload 0 "$(printf '%q' "$RESTART_USER")"
}

main "$@"

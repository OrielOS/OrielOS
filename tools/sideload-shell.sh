#!/usr/bin/env bash
# Copies the OrielOS shell from this checkout onto a running OrielOS computer over SSH, for trying
# changes without building an image: the shell package, OrielOS's Plasma theme and widgets, its KWin
# effects, its line icons, Settings' shortcuts, the settings that make them the desktop, and the
# sign-in theme. OrielOS's /usr (and /usr/local) is read-only, so the files go to /var/usrlocal/orielos-sideload/share,
# which carries /usr's SELinux label: a session environment
# script puts it first on XDG_DATA_DIRS for Plasma and the lock screen, and an SDDM setting points
# the sign-in screen at its themes. Every file it places is listed on the computer in
# /var/usrlocal/orielos-sideload/manifest, so --undo can take them all away again; undo before
# moving the computer to an image that has the shell built in.
#
# Usage: tools/sideload-shell.sh [--apps] [--restart USER] [--undo] [--help] HOST
#   HOST            an SSH destination (user@host) whose user can use sudo without a password
#   --apps          also sideload OrielOS's compiled Plasma widgets (such as Start), window frames and Display mode (Win+P) from the app
#                   build, localhost/orielos-app-builder (tools/test-apps.sh), or
#                   ORIELOS_APP_IMAGE; QT_PLUGIN_PATH puts them before the installed ones. Without
#                   it, the compiled parts an earlier sideload placed stay as they are
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
CONTAINER=""

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cleanup() {
    if [[ -n "$STAGING" ]]; then rm -rf -- "$STAGING"; fi
    if [[ -n "$CONTAINER" ]]; then podman rm -f "$CONTAINER" >/dev/null 2>&1 || true; fi
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

# The script that runs on the computer, as root, with the arguments UNDO, RESTART_USER and KEEP_APPS.
# It reads the files to place from a tar stream on standard input (nothing for --undo).
remote_script() {
    cat <<'REMOTE'
set -Eeuo pipefail
state=/var/usrlocal/orielos-sideload
data="$state/share"
manifest="$state/manifest"
undo="$1"
restart_user="$2"
keep_apps="$3"

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

if [[ "$undo" == 1 ]]; then
    remove_placed
    echo "removed the sideloaded shell"
else
    staging="$(mktemp -d)"
    trap 'rm -rf -- "$staging"' EXIT
    tar -C "$staging" -x
    # Without --apps, the compiled parts an earlier sideload placed stay, as if sent again.
    if [[ "$keep_apps" == 1 && ! -d "$staging/plugins" ]]; then
        if [[ -d "$state/plugins" ]]; then cp -a -- "$state/plugins" "$staging/plugins"; fi
        if [[ -d "$state/bin" ]]; then cp -a -- "$state/bin" "$staging/bin"; fi
        if [[ -f "$data/applications/org.orielos.DisplayMode.desktop" ]]; then
            cp -- "$data/applications/org.orielos.DisplayMode.desktop" "$staging/displaymode.desktop"
        fi
        if [[ -d "$data/locale/en@orielos" ]]; then cp -a -- "$data/locale/en@orielos" "$staging/locale-en@orielos"; fi
    fi
    remove_placed
    mkdir -p "$data/plasma/shells" "$data/plasma/desktoptheme" "$data/plasma/plasmoids" "$data/sddm/themes" "$data/icons/hicolor/scalable/actions" "$data/kwin/effects" "$data/kwin/tabbox" "$data/kwin/scripts" "$data/plasma/look-and-feel" /etc/sddm.conf.d
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
    place "$staging/desktoptheme/orielos-accent" "$data/plasma/desktoptheme/orielos-accent"
    for widget in "$staging"/plasmoids/*; do
        place "$widget" "$data/plasma/plasmoids/${widget##*/}"
    done
    place "$staging/kwin/snaplayouts" "$data/kwin/effects/orielos-snaplayouts"
    place "$staging/kwin/snapassist" "$data/kwin/effects/orielos-snapassist"
    place "$staging/kwin/switcheropen" "$data/kwin/effects/orielos-switcheropen"
    for lnf in "$staging"/look-and-feel/*; do
        place "$lnf" "$data/plasma/look-and-feel/${lnf##*/}"
    done
    place "$staging/kwin/switcher" "$data/kwin/tabbox/org.orielos.switcher"
    place "$staging/kwin/closeorshutdown" "$data/kwin/scripts/orielos-closeorshutdown"
    place "$staging/kwin/windowkeys" "$data/kwin/scripts/orielos-windowkeys"
    mkdir -p "$data/applications" "$data/kglobalaccel"
    place "$staging/settings.desktop" "$data/applications/org.orielos.Settings.desktop"
    place "$staging/settings.desktop" "$data/kglobalaccel/org.orielos.Settings.desktop"
    # Display mode on Win+P, run from the sideload, and Plasma's screen picker without Win+P, as
    # the image build makes it.
    if [[ -f "$staging/bin/orielos-display-mode" ]]; then
        place "$staging/bin" "$state/bin"
        sed "s|^Exec=orielos-display-mode\$|Exec=$state/bin/orielos-display-mode|" "$staging/displaymode.desktop" |
            write "$data/applications/org.orielos.DisplayMode.desktop"
        cp -- "$data/applications/org.orielos.DisplayMode.desktop" "$data/kglobalaccel/org.orielos.DisplayMode.desktop"
        printf '%s\n' "$data/kglobalaccel/org.orielos.DisplayMode.desktop" >>"$manifest"
        sed 's/^X-KDE-Shortcuts=Display,Meta+P$/X-KDE-Shortcuts=Display/' /usr/share/kglobalaccel/org.kde.kscreen.desktop |
            write "$data/kglobalaccel/org.kde.kscreen.desktop"
    fi
    # The Run box on Win+R, and KRunner without it, as the image build makes them.
    if [[ -f "$staging/bin/orielos-run" ]]; then
        sed "s|^Exec=orielos-run\$|Exec=$state/bin/orielos-run|" "$staging/run.desktop" |
            write "$data/applications/org.orielos.Run.desktop"
        cp -- "$data/applications/org.orielos.Run.desktop" "$data/kglobalaccel/org.orielos.Run.desktop"
        printf '%s
' "$data/kglobalaccel/org.orielos.Run.desktop" >>"$manifest"
        sed '0,/^X-KDE-Shortcuts=/s/^X-KDE-Shortcuts=.*/X-KDE-Shortcuts=Alt+F2,Search/' /usr/share/kglobalaccel/org.kde.krunner.desktop |
            write "$data/kglobalaccel/org.kde.krunner.desktop"
    fi
    # The contrast theme and Mouse Keys shortcuts, run from the sideload, and the contrast themes.
    if [[ -f "$staging/bin/orielos-accessibility-keys" ]]; then
        for entry in "$staging"/accessibility/*.desktop; do
            sed "s|^Exec=/usr/libexec/orielos/accessibility-keys|Exec=$state/bin/orielos-accessibility-keys|" "$entry" |
                write "$data/applications/${entry##*/}"
            cp -- "$data/applications/${entry##*/}" "$data/kglobalaccel/${entry##*/}"
            printf '%s
' "$data/kglobalaccel/${entry##*/}" >>"$manifest"
        done
    fi
    place "$staging/color-schemes" "$data/color-schemes"
    # Settings itself, run from the sideload, so pages added since the image show.
    if [[ -f "$staging/bin/orielos-settings" ]]; then
        sed "s|^Exec=orielos-settings|Exec=$state/bin/orielos-settings|" "$staging/settings.desktop" |
            write "$data/applications/org.orielos.Settings.desktop"
    fi
    if [[ -d "$staging/locale-en@orielos" ]]; then
        mkdir -p "$data/locale"
        place "$staging/locale-en@orielos" "$data/locale/en@orielos"
    fi
    for icon in "$staging"/icons/*.svg; do
        place "$icon" "$data/icons/hicolor/scalable/actions/${icon##*/}"
    done
    place "$staging/etc/plasmashellrc" /etc/xdg/plasmashellrc
    place "$staging/etc/plasmarc" /etc/xdg/plasmarc
    place "$staging/etc/kwinrc" /etc/xdg/kwinrc
    place "$staging/etc/plasmanotifyrc" /etc/xdg/plasmanotifyrc
    place "$staging/etc/plasmaparc" /etc/xdg/plasmaparc
    place "$staging/etc/ksmserverrc" /etc/xdg/ksmserverrc
    place "$staging/etc/ksplashrc" /etc/xdg/ksplashrc
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
        ssh "${SSH_OPTS[@]}" "$HOST" sudo bash -c "$(printf '%q' "$script")" sideload 1 "$(printf '%q' "$RESTART_USER")" 0 </dev/null
        return
    fi
    trap cleanup EXIT
    STAGING="$(mktemp -d)"
    mkdir -p "$STAGING/shell" "$STAGING/desktoptheme" "$STAGING/etc" "$STAGING/sddm"
    cp -a "$ROOT/plasma/shell/org.orielos.desktop" "$STAGING/shell/"
    cp -a "$ROOT/plasma/desktoptheme/orielos" "$ROOT/plasma/desktoptheme/orielos-accent" "$STAGING/desktoptheme/"
    cp -a "$ROOT/plasma/plasmoids" "$STAGING/plasmoids"
    mkdir -p "$STAGING/icons" "$STAGING/look-and-feel"
    cp -a "$ROOT/plasma/kwin" "$STAGING/kwin"
    cp -a "$ROOT/plasma/color-schemes" "$STAGING/color-schemes"
    cp "$ROOT"/artwork/icons/*-symbolic.svg "$STAGING/icons/"
    cp "$ROOT/image/system/etc/xdg/plasmarc" "$STAGING/etc/plasmarc"
    cp "$ROOT/image/system/etc/xdg/kwinrc" "$STAGING/etc/kwinrc"
    cp "$ROOT/image/system/etc/xdg/plasmanotifyrc" "$STAGING/etc/plasmanotifyrc"
    cp "$ROOT/image/system/etc/xdg/plasmaparc" "$STAGING/etc/plasmaparc"
    cp "$ROOT/image/system/etc/xdg/ksmserverrc" "$STAGING/etc/ksmserverrc"
    cp "$ROOT/image/system/etc/xdg/ksplashrc" "$STAGING/etc/ksplashrc"
    # The look-and-feel packages as the image installs them: with the shell's layout, the
    # Ctrl+Alt+Del screen and the welcome screen.
    for lnf in org.orielos.desktop org.orielos.desktop.dark; do
        cp -a "$ROOT/plasma/look-and-feel/$lnf" "$STAGING/look-and-feel/"
        mkdir -p "$STAGING/look-and-feel/$lnf/contents/layouts"
        cp -a "$ROOT/plasma/look-and-feel/logout" "$ROOT/plasma/look-and-feel/splash" "$STAGING/look-and-feel/$lnf/contents/"
        cp "$ROOT/plasma/shell/org.orielos.desktop/contents/lockscreen/AccountPicture.qml" "$STAGING/look-and-feel/$lnf/contents/splash/"
        for shell in org.orielos.desktop org.kde.plasma.desktop; do
            cp "$ROOT/plasma/shell/org.orielos.desktop/contents/layout.js" "$STAGING/look-and-feel/$lnf/contents/layouts/$shell-layout.js"
        done
    done
    cp "$ROOT/image/system/etc/xdg/plasmashellrc" "$STAGING/etc/plasmashellrc"
    # Settings' desktop entry, whose actions carry its shortcuts (Settings itself is in the image).
    cp "$ROOT/apps/settings/org.orielos.Settings.desktop" "$STAGING/settings.desktop"
    cp "$ROOT/image/system/etc/xdg/plasma-workspace/env/orielos-shell.sh" "$STAGING/etc/orielos-shell.sh"
    cp "$ROOT"/image/sddm/orielos/*.qml "$ROOT/image/sddm/orielos/metadata.desktop" \
        "$ROOT/image/sddm/orielos/theme.conf" "$STAGING/sddm/"
    if [[ "$APPS" -eq 1 ]]; then
        CONTAINER="$(podman create "$APP_IMAGE" true)" || die "can't use $APP_IMAGE; run tools/test-apps.sh first"
        mkdir -p "$STAGING/plugins/plasma"
        podman cp "$CONTAINER:/out/usr/lib64/qt6/plugins/plasma/applets" "$STAGING/plugins/plasma/applets"
        podman cp "$CONTAINER:/out/usr/lib64/qt6/plugins/org.kde.kdecoration3" "$STAGING/plugins/org.kde.kdecoration3"
        podman cp "$CONTAINER:/out/usr/lib64/qt6/plugins/plasma/containmentactions" "$STAGING/plugins/plasma/containmentactions"
        mkdir -p "$STAGING/plugins/plasma/kcms"
        podman cp "$CONTAINER:/out/usr/lib64/qt6/plugins/plasma/kcms/systemsettings" "$STAGING/plugins/plasma/kcms/systemsettings"
        podman cp "$CONTAINER:/out/usr/share/locale/en@orielos" "$STAGING/locale-en@orielos"
        mkdir -p "$STAGING/bin"
        podman cp "$CONTAINER:/out/usr/bin/orielos-display-mode" "$STAGING/bin/orielos-display-mode"
        podman cp "$CONTAINER:/out/usr/bin/orielos-settings" "$STAGING/bin/orielos-settings"
        podman cp "$CONTAINER:/out/usr/bin/orielos-run" "$STAGING/bin/orielos-run"
        # The administrator prompt's program only, for trying it by hand: the session keeps its agent.
        podman cp "$CONTAINER:/out/usr/libexec/orielos-polkit-agent" "$STAGING/bin/orielos-polkit-agent"
        cp "$ROOT/apps/runbox/org.orielos.Run.desktop" "$STAGING/run.desktop"
        # Storage Sense, for Settings' clean-up buttons (its daily timer comes with an image).
        install -m 0755 "$ROOT/image/system/usr/libexec/orielos/accessibility-keys" "$STAGING/bin/orielos-accessibility-keys"
        mkdir -p "$STAGING/accessibility"
        cp "$ROOT/image/system/usr/share/applications/org.orielos.ContrastTheme.desktop" "$ROOT/image/system/usr/share/applications/org.orielos.MouseKeys.desktop" "$STAGING/accessibility/"
        install -m 0755 "$ROOT/image/system/usr/libexec/orielos/storage-sense" "$STAGING/bin/orielos-storage-sense"
        cp "$ROOT/apps/displaymode/org.orielos.DisplayMode.desktop" "$STAGING/displaymode.desktop"
        podman rm -f "$CONTAINER" >/dev/null
        CONTAINER=""
        find "$STAGING/plugins" -type f ! -name 'org.orielos.*' ! -name 'kcm_orielos_*' -delete
    fi
    step "Sideloading the shell from $(git -C "$ROOT" log -1 --format='%h %s' 2>/dev/null || echo "$ROOT") onto $HOST"
    tar -C "$STAGING" -c . | ssh "${SSH_OPTS[@]}" "$HOST" sudo bash -c "$(printf '%q' "$script")" sideload 0 "$(printf '%q' "$RESTART_USER")" "$((1 - APPS))"
}

main "$@"

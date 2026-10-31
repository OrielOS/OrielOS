#!/usr/bin/env bash
# Checks that no build tools are installed, that the first boot will run Plasma Setup with its
# pages in OrielOS's order, install Firefox and queue Universal Blue's key for Secure Boot (and enables the latter two) and that new
# users get the taskbar and the wallpapers, enables the background update check and the unit that
# keeps the boot menu hidden after good boots, refreshes the icon cache, rebuilds the initramfs for
# the installed kernel, removes build leftovers and lints the image.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

# The apps are built in the app-builder stage; compilers and headers must stay out of the image.
mapfile -t build_tools < <(rpm -qa --qf '%{NAME}\n' |
    grep -E -- '-devel$|^(gcc|gcc-c\+\+|cmake|extra-cmake-modules)$' | sort -u || true)
if [[ "${#build_tools[@]}" -gt 0 ]]; then
    printf 'error: build tools must not be installed in the final image; found: %s\n' "${build_tools[*]}" >&2
    printf 'error: build software in the app-builder stage and copy only the result into the image\n' >&2
    exit 1
fi

# Plasma Setup creates the first user account on first boot. It only runs while its done marker
# is missing, and only offers to create an account when there is no regular user yet.
first_boot_errors=()
if [[ "$(systemctl is-enabled plasma-setup.service 2>&1)" != "enabled" ]]; then
    first_boot_errors+=("plasma-setup.service is not enabled")
fi
if [[ -e /etc/plasma-setup-done ]]; then
    first_boot_errors+=("/etc/plasma-setup-done exists, so Plasma Setup would never run")
fi
mapfile -t users < <(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd)
if [[ "${#users[@]}" -gt 0 ]]; then
    first_boot_errors+=("the image has regular users (${users[*]}); Plasma Setup creates the first one")
fi
if [[ "${#first_boot_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${first_boot_errors[@]}" >&2
    exit 1
fi

# Plasma Setup's pages come in OrielOS's order (build/41-first-run.sh and plasma/firstrun), and the
# power page has what it needs to save its choices.
first_run_errors=()
first_run_order="$(for f in /usr/share/plasma/packages/*/metadata.json; do
    jq -r 'select(.KPackageStructure == "KDE/PlasmaSetup") | "\(."X-KDE-Weight") \(.KPlugin.Id)"' "$f"
done | sort -n | cut -d' ' -f2 | paste -sd ' ' -)"
first_run_expected="org.kde.plasmasetup.language org.kde.plasmasetup.keyboard org.kde.plasmasetup.wifi org.orielos.plasmasetup.network org.kde.plasmasetup.time org.orielos.plasmasetup.power org.kde.plasmasetup.hostname org.kde.plasmasetup.account org.kde.plasmasetup.finished"
if [[ "$first_run_order" != "$first_run_expected" ]]; then
    first_run_errors+=("Plasma Setup's pages are in the wrong order: $first_run_order")
fi
[[ -x /usr/libexec/orielos/first-run-power ]] || first_run_errors+=("/usr/libexec/orielos/first-run-power is not executable")
for f in /usr/share/polkit-1/actions/org.orielos.first-run.policy /usr/share/polkit-1/rules.d/49-orielos-first-run.rules \
    /usr/lib/tmpfiles.d/orielos-first-run.conf /usr/lib64/qt6/qml/org/orielos/firstrun/qmldir \
    /usr/share/plasma/packages/org.kde.plasmasetup.finished/contents/ui/konqi-calling.png; do
    [[ -r "$f" ]] || first_run_errors+=("$f is missing")
done
if [[ "${#first_run_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${first_run_errors[@]}" >&2
    exit 1
fi

# The preset file is not applied while the image builds, and the unit is copied in after the
# package layers, so enable it here. The stamp file that ends it must not be in the image.
systemctl enable orielos-flatpak-setup.service
if [[ "$(systemctl is-enabled orielos-flatpak-setup.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-flatpak-setup.service is not enabled\n' >&2
    exit 1
fi
if [[ -e /var/lib/orielos/flatpak-setup.done ]]; then
    printf 'error: /var/lib/orielos/flatpak-setup.done exists, so Firefox would never be installed\n' >&2
    exit 1
fi

# The Secure Boot key service queues Universal Blue's key on first boot, and the session tells the
# user what to do; it is enabled here for the same reason. Its state must not be in the image.
systemctl enable orielos-secure-boot-key.service
secure_boot_errors=()
if [[ "$(systemctl is-enabled orielos-secure-boot-key.service 2>/dev/null)" != "enabled" ]]; then
    secure_boot_errors+=("orielos-secure-boot-key.service is not enabled")
fi
for f in /usr/libexec/orielos/secure-boot-key /usr/libexec/orielos/secure-boot-notify; do
    [[ -x "$f" ]] || secure_boot_errors+=("$f is not executable")
done
if [[ ! -r /etc/pki/akmods/certs/akmods-ublue.der ]]; then
    secure_boot_errors+=("Universal Blue's key, /etc/pki/akmods/certs/akmods-ublue.der, is missing")
fi
if [[ ! -r /etc/xdg/autostart/orielos-secure-boot-notify.desktop ]]; then
    secure_boot_errors+=("the Secure Boot notification's autostart entry is missing")
fi
if ! command -v mokutil >/dev/null || ! command -v notify-send >/dev/null; then
    secure_boot_errors+=("mokutil or notify-send is not installed")
fi
if [[ -e /var/lib/orielos/secure-boot ]]; then
    secure_boot_errors+=("/var/lib/orielos/secure-boot exists in the image")
fi
if [[ "${#secure_boot_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${secure_boot_errors[@]}" >&2
    exit 1
fi

# The update check stages builds in the background and records each boot's state for the update
# tray icon and the Update settings page; both units are enabled here for the same reason as above. No update state may be in
# the image: it belongs to each computer.
systemctl enable orielos-update-check.timer orielos-update-state.service orielos-app-update.timer
update_errors=()
for unit in orielos-update-check.timer orielos-update-state.service orielos-app-update.timer; do
    if [[ "$(systemctl is-enabled "$unit" 2>/dev/null)" != "enabled" ]]; then
        update_errors+=("$unit is not enabled")
    fi
done
for cmd in skopeo pkexec busctl bootc jq flatpak; do
    command -v "$cmd" >/dev/null || update_errors+=("$cmd, which orielos-update needs, is not installed")
done
for f in /usr/lib/orielos/update.conf /usr/share/polkit-1/actions/org.orielos.update.policy \
    /etc/xdg/autostart/org.orielos.UpdateNotifier.desktop /usr/share/applications/org.orielos.UpdateNotifier.desktop \
    /usr/share/knotifications6/orielos-update-notifier.notifyrc \
    /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_orielos_update.so /usr/share/applications/kcm_orielos_update.desktop; do
    [[ -r "$f" ]] || update_errors+=("$f is missing")
done
[[ -x /usr/bin/orielos-update-notifier ]] || update_errors+=("the update notifier, /usr/bin/orielos-update-notifier, is missing")
# Settings hosts the Update page; it has Win+I and Start's Settings entry, System Settings neither.
[[ -x /usr/bin/orielos-settings ]] || update_errors+=("Settings, /usr/bin/orielos-settings, is missing")
# OrielOS's own Settings pages besides Update.
for module in kcm_orielos_accessories kcm_orielos_accent kcm_orielos_start kcm_orielos_taskbar kcm_orielos_security \
    kcm_orielos_powermode kcm_orielos_signin kcm_orielos_multitasking kcm_orielos_pointer; do
    for f in "/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/$module.so" "/usr/share/applications/$module.desktop"; do
        [[ -r "$f" ]] || update_errors+=("$f is missing")
    done
done
# Device security reads the accepted module signers from here.
[[ -r /usr/share/orielos/module-signers.txt ]] || update_errors+=("/usr/share/orielos/module-signers.txt is missing")
for f in /usr/share/applications/org.orielos.Settings.desktop /usr/share/kglobalaccel/org.orielos.Settings.desktop; do
    grep -qxF 'X-KDE-Shortcuts=Meta+I' "$f" 2>/dev/null || update_errors+=("$f is missing or doesn't give Settings Win+I")
done
# Display mode, on Win+P, which Plasma's screen picker gives up.
[[ -x /usr/bin/orielos-display-mode ]] || update_errors+=("/usr/bin/orielos-display-mode is missing")
grep -qxF 'X-KDE-Shortcuts=Meta+P' /usr/share/kglobalaccel/org.orielos.DisplayMode.desktop 2>/dev/null || update_errors+=("Display mode doesn't have Win+P")
grep -qxF 'X-KDE-Shortcuts=Display' /usr/share/kglobalaccel/org.kde.kscreen.desktop || update_errors+=("Plasma's screen picker still has Win+P")
# The administrator prompt, in place of Plasma's polkit agent.
[[ -x /usr/libexec/orielos-polkit-agent ]] || update_errors+=("/usr/libexec/orielos-polkit-agent is missing")
grep -qxF 'ExecStart=/usr/libexec/orielos-polkit-agent' /usr/lib/systemd/user/plasma-polkit-agent.service.d/orielos.conf 2>/dev/null ||
    update_errors+=("plasma-polkit-agent.service doesn't start OrielOS's administrator prompt")
# The Run box, on Win+R, which KRunner gives up.
[[ -x /usr/bin/orielos-run ]] || update_errors+=("/usr/bin/orielos-run is missing")
grep -qxF 'X-KDE-Shortcuts=Meta+R' /usr/share/kglobalaccel/org.orielos.Run.desktop 2>/dev/null || update_errors+=("the Run box doesn't have Win+R")
grep -qxF 'X-KDE-Shortcuts=Alt+F2,Search' /usr/share/kglobalaccel/org.kde.krunner.desktop || update_errors+=("KRunner still has Win+R")
grep -qxF 'NoDisplay=true' /usr/share/applications/systemsettings.desktop || update_errors+=("System Settings is still listed in Start")
# One settings app: System Settings' and kcmshell6's commands open Settings, and NVIDIA's settings are
# a page of Settings rather than a second settings app in Start.
for f in /usr/bin/systemsettings /usr/bin/kcmshell6; do
    grep -q 'exec /usr/bin/orielos-settings' "$f" 2>/dev/null || update_errors+=("$f doesn't open Settings")
done
nvidia_entry=/usr/share/applications/nvidia-settings.desktop
if [[ -f "$nvidia_entry" ]]; then
    grep -qxF 'NoDisplay=true' "$nvidia_entry" || sed -i '/^\[Desktop Entry\]$/a NoDisplay=true' "$nvidia_entry"
    grep -qxF 'NoDisplay=true' "$nvidia_entry" || update_errors+=("NVIDIA's settings are still listed in Start")
else
    update_errors+=("$nvidia_entry is missing; Settings' NVIDIA page opens it")
fi
# Start's and KRunner's search open Settings' pages in Settings, through OrielOS's runner.
[[ -r /usr/lib64/qt6/plugins/kf6/krunner/krunner_orielos_settings.so ]] || update_errors+=("the settings search runner, krunner_orielos_settings, is missing")
if [[ "$(kreadconfig6 --file /etc/xdg/krunnerrc --group Plugins --key krunner_systemsettingsEnabled)" != "false" ]]; then
    update_errors+=("/etc/xdg/krunnerrc does not turn off System Settings' search runner")
fi
if [[ -e /var/lib/orielos/update ]]; then
    update_errors+=("/var/lib/orielos/update exists in the image")
fi
# Run this app opens Windows programs (40-apps.sh makes it the default), through umu-launcher.
[[ -x /usr/bin/orielos-run-app ]] || update_errors+=("Run this app, /usr/bin/orielos-run-app, is missing")
[[ -r /usr/share/applications/org.orielos.RunApp.desktop ]] || update_errors+=("org.orielos.RunApp.desktop is missing")
for type in application/x-ms-dos-executable application/x-msi; do
    grep -qxF "$type=org.orielos.RunApp.desktop" /usr/share/applications/mimeapps.list ||
        update_errors+=("Run this app isn't the default for $type")
done
command -v umu-run >/dev/null || update_errors+=("umu-run, which Run this app runs programs with, is missing")
if [[ "${#update_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${update_errors[@]}" >&2
    exit 1
fi

# The first start's power mode, Performance, comes from the shipped base profile (see 45-gaming.sh).
if [[ "$(cat /etc/tuned/ppd_base_profile 2>/dev/null)" != performance ]]; then
    printf 'error: /etc/tuned/ppd_base_profile does not start tuned-ppd in performance\n' >&2
    exit 1
fi

# The boot menu stays hidden, and an update that fails to reach the desktop twice is undone without
# asking. bootupd adds OrielOS's GRUB snippet to the boot loader's configuration when OrielOS is
# installed. Each desktop session then asks orielos-boot-success.service to mark the start as
# good, through a user unit enabled for every user here and a polkit rule that allows only that.
systemctl --global enable orielos-mark-boot-success.service
boot_menu_errors=()
# 13_orielos-windows.cfg adds Windows to the menu, and shows it, on PCs that also have Windows.
for menu_snippet in /usr/lib/bootupd/grub2-static/configs.d/12_orielos-menu.cfg \
    /usr/lib/bootupd/grub2-static/configs.d/13_orielos-windows.cfg; do
    if [[ ! -r "$menu_snippet" ]]; then
        boot_menu_errors+=("the boot menu's GRUB snippet, $menu_snippet, is missing")
    elif ! grub2-script-check "$menu_snippet"; then
        boot_menu_errors+=("grub2-script-check found errors in $menu_snippet")
    fi
done
if [[ "$(systemctl --global is-enabled orielos-mark-boot-success.service 2>/dev/null)" != "enabled" ]]; then
    boot_menu_errors+=("orielos-mark-boot-success.service is not enabled for users")
fi
for f in /usr/lib/systemd/system/orielos-boot-success.service /usr/share/polkit-1/rules.d/50-orielos-boot-success.rules; do
    [[ -r "$f" ]] || boot_menu_errors+=("$f is missing")
done
[[ -x /usr/libexec/orielos/boot-flags ]] || boot_menu_errors+=("/usr/libexec/orielos/boot-flags is not executable")
for cmd in grub2-editenv lsblk findmnt mountpoint unshare flock ostree; do
    command -v "$cmd" >/dev/null || boot_menu_errors+=("$cmd, which the boot menu's flags or removing the previous build need, is not installed")
done
if [[ "${#boot_menu_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${boot_menu_errors[@]}" >&2
    exit 1
fi

# The startup sound plays once per boot, when the sign-in screen first appears, through the sign-in
# screen's own sound server.
systemctl enable orielos-startup-sound.service
if [[ "$(systemctl is-enabled orielos-startup-sound.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-startup-sound.service is not enabled\n' >&2
    exit 1
fi
for cmd in paplay pactl; do
    command -v "$cmd" >/dev/null || {
        printf 'error: %s, which the startup sound needs, is not installed\n' "$cmd" >&2
        exit 1
    }
done

# Alt+F4 belongs to OrielOS's Close or shut down KWin script and Ctrl+Esc opens Start; accounts made
# before them get both once at sign-in (new ones get them from /etc/skel).
systemctl --global enable orielos-user-shortcuts.service
if [[ "$(systemctl --global is-enabled orielos-user-shortcuts.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-user-shortcuts.service is not enabled for users\n' >&2
    exit 1
fi
[[ -x /usr/libexec/orielos/user-shortcuts ]] || {
    printf 'error: /usr/libexec/orielos/user-shortcuts is not executable\n' >&2
    exit 1
}
[[ -f /usr/share/kwin/scripts/orielos-closeorshutdown/metadata.json ]] || {
    printf 'error: the Close or shut down KWin script is not installed\n' >&2
    exit 1
}
[[ -f /usr/share/kwin/effects/orielos-snapassist/metadata.json ]] || {
    printf 'error: the Snap Assist KWin effect is not installed\n' >&2
    exit 1
}
[[ -f /usr/share/kwin/scripts/orielos-windowkeys/metadata.json ]] || {
    printf 'error: the Window shortcuts KWin script is not installed\n' >&2
    exit 1
}

# The Bin on each user's desktop, put there once at sign-in, as Windows has its Recycle Bin.
systemctl --global enable orielos-desktop-bin.service
if [[ "$(systemctl --global is-enabled orielos-desktop-bin.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-desktop-bin.service is not enabled for users\n' >&2
    exit 1
fi
[[ -x /usr/libexec/orielos/desktop-bin ]] || {
    printf 'error: /usr/libexec/orielos/desktop-bin is not executable\n' >&2
    exit 1
}

# Quick sign-in: the PIN service, started for each request by its socket, which the sign-in screen,
# the lock screen and administrator prompts ask through pin-auth (29-quick-sign-in.sh) and Settings
# asks to set or remove a PIN.
systemctl enable orielos-pin.socket
if [[ "$(systemctl is-enabled orielos-pin.socket 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-pin.socket is not enabled\n' >&2
    exit 1
fi
for f in /usr/libexec/orielos/pin-service /usr/libexec/orielos/pin-auth; do
    [[ -x "$f" ]] || {
        printf 'error: %s is not executable\n' "$f" >&2
        exit 1
    }
done
for f in /etc/pam.d/sddm /etc/pam.d/kde /etc/pam.d/polkit-1; do
    grep -q 'orielos/pin-auth' "$f" || {
        printf 'error: %s does not ask for the PIN\n' "$f" >&2
        exit 1
    }
done
[[ -f /usr/lib/pam.d/orielos-pin ]] || {
    printf 'error: /usr/lib/pam.d/orielos-pin, which the PIN service checks passwords with, is missing\n' >&2
    exit 1
}
python3 -I -c 'import hashlib; hashlib.scrypt(b"0", salt=b"0", n=2, r=8, p=1)' || {
    printf 'error: python3 with scrypt, which the PIN service needs, is missing\n' >&2
    exit 1
}

# Double-clicking a disc image opens it as a drive, as in Windows (the Mount disc image app).
mimeapps=/usr/share/applications/mimeapps.list
for type in application/x-cd-image application/vnd.efi.iso; do
    sed -i "/^${type//\//\\/}=/d" "$mimeapps"
    sed -i "/^\[Default Applications\]$/a ${type}=org.orielos.MountDiscImage.desktop" "$mimeapps"
done
for f in /usr/libexec/orielos/mount-iso /usr/libexec/orielos/send-to; do
    [[ -x "$f" ]] || {
        printf 'error: %s is not executable\n' "$f" >&2
        exit 1
    }
done

# Windows' touchpad defaults (tap to click, the page following the fingers) for each new touchpad.
systemctl --global enable orielos-touchpad-defaults.service
if [[ "$(systemctl --global is-enabled orielos-touchpad-defaults.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-touchpad-defaults.service is not enabled for users\n' >&2
    exit 1
fi
[[ -x /usr/libexec/orielos/touchpad-defaults ]] || {
    printf 'error: /usr/libexec/orielos/touchpad-defaults is not executable\n' >&2
    exit 1
}

# Do not disturb for the first hour after an update.
systemctl --global enable orielos-quiet-after-update.service
if [[ "$(systemctl --global is-enabled orielos-quiet-after-update.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-quiet-after-update.service is not enabled for users\n' >&2
    exit 1
fi
[[ -x /usr/libexec/orielos/quiet-after-update ]] || {
    printf 'error: /usr/libexec/orielos/quiet-after-update is not executable\n' >&2
    exit 1
}

# Dynamic lock: locks the session when the phone chosen in Settings goes out of range; the unit
# runs only for users who chose one.
systemctl --global enable orielos-dynamic-lock.service
if [[ "$(systemctl --global is-enabled orielos-dynamic-lock.service 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-dynamic-lock.service is not enabled for users\n' >&2
    exit 1
fi
[[ -x /usr/libexec/orielos/dynamic-lock ]] || {
    printf 'error: /usr/libexec/orielos/dynamic-lock is not executable\n' >&2
    exit 1
}

# GE-Proton is the default for Windows games: orielos-update installs it next to Steam from the
# Store, and this timer sets it as each user's Steam default, once, while Steam is closed.
systemctl --global enable orielos-steam-default-proton.timer
if [[ "$(systemctl --global is-enabled orielos-steam-default-proton.timer 2>/dev/null)" != "enabled" ]]; then
    printf 'error: orielos-steam-default-proton.timer is not enabled for users\n' >&2
    exit 1
fi
[[ -x /usr/libexec/orielos/steam-default-proton ]] || {
    printf 'error: /usr/libexec/orielos/steam-default-proton is not executable\n' >&2
    exit 1
}
command -v python3 >/dev/null || {
    printf 'error: python3, which steam-default-proton runs on, is not installed\n' >&2
    exit 1
}

# Every user's desktop is OrielOS's own shell, org.orielos.desktop, which lays out the taskbar for a
# new desktop and carries an earlier one over; /etc/xdg/plasmashellrc makes it the default and the
# session's environment script keeps it the fallback. The shell, the look-and-feel packages and the
# Start button's icon come from the app-builder stage; 20-desktop.sh makes the look-and-feel the
# default.
lnf=org.orielos.desktop
shell=/usr/share/plasma/shells/org.orielos.desktop
taskbar_errors=()
# Dark by default: OrielOS Dark's colours become every user's default colours, until they choose
# light in Settings, which writes their own. Apps read colours from kdeglobals' [Colors:*] groups,
# not from the scheme's name, so the whole scheme goes into /etc/xdg/kdeglobals; the wallpapers
# and the lock screen show Nightfall with dark colours.
dark_scheme=/usr/share/color-schemes/OrielOSDark.colors
# Prints each colour entry of a colour scheme as group<TAB>key<TAB>value, the group as Plasma
# writes it in kdeglobals, such as Colors:Header][Inactive.
scheme_entries() {
    python3 -I - "$1" <<'PY'
import configparser, sys

scheme = configparser.RawConfigParser(strict=False, interpolation=None)
scheme.optionxform = str
scheme.read(sys.argv[1], encoding="utf-8")
for section in scheme.sections():
    if section.startswith("Colors:") or section.startswith("ColorEffects:") or section == "WM":
        for key, value in scheme.items(section):
            print(f"{section}\t{key}\t{value}")
PY
}
if [[ -r "$dark_scheme" ]]; then
    while IFS=$'\t' read -r group key value; do
        IFS='][' read -ra groups <<<"$group"
        args=()
        for g in "${groups[@]}"; do [[ -n "$g" ]] && args+=(--group "$g"); done
        kwriteconfig6 --file /etc/xdg/kdeglobals "${args[@]}" --key "$key" "$value"
    done < <(scheme_entries "$dark_scheme")
    kwriteconfig6 --file /etc/xdg/kdeglobals --group General --key ColorScheme OrielOSDark
fi
window_default="$(kreadconfig6 --file /etc/xdg/kdeglobals --group Colors:Window --key BackgroundNormal)"
window_dark="$(kreadconfig6 --file "$dark_scheme" --group Colors:Window --key BackgroundNormal 2>/dev/null)"
if [[ "$(kreadconfig6 --file /etc/xdg/kdeglobals --group General --key ColorScheme)" != OrielOSDark ]] ||
    [[ -z "$window_dark" || "$window_default" != "$window_dark" ]]; then
    taskbar_errors+=("/etc/xdg/kdeglobals does not carry OrielOS Dark's colours")
fi
shell_id='import json, sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Id"])'
if [[ "$(python3 -I -c "$shell_id" "$shell/metadata.json" 2>/dev/null)" != org.orielos.desktop ]]; then
    taskbar_errors+=("the OrielOS shell package is not installed in $shell")
fi
for f in contents/layout.js contents/lockscreen/LockScreen.qml contents/lockscreen/LockScreenUi.qml contents/applet/CompactApplet.qml \
    contents/updates/orielos-desktop-1.js; do
    [[ -f "$shell/$f" ]] || taskbar_errors+=("the OrielOS shell package has no $f")
done
for f in metadata.json widgets/panel-background.svg widgets/tasks.svg dialogs/background.svg translucent/dialogs/background.svg; do
    [[ -f "/usr/share/plasma/desktoptheme/orielos/$f" ]] || taskbar_errors+=("OrielOS's Plasma theme has no $f")
    # Its variant with the accent colour, which Settings' Accent colour page switches to.
    [[ -f "/usr/share/plasma/desktoptheme/orielos-accent/$f" ]] || taskbar_errors+=("OrielOS's accent Plasma theme has no $f")
done
if [[ "$(kreadconfig6 --file /etc/xdg/plasmarc --group Theme --key name)" != orielos ]]; then
    taskbar_errors+=("/etc/xdg/plasmarc does not make orielos the Plasma theme")
fi
if [[ "$(kreadconfig6 --file /etc/xdg/plasmashellrc --group Shell --key ShellPackage)" != org.orielos.desktop ]]; then
    taskbar_errors+=("/etc/xdg/plasmashellrc does not make org.orielos.desktop the shell")
fi
grep -qx 'PLASMA_DEFAULT_SHELL=org.orielos.desktop' /etc/xdg/plasma-workspace/env/orielos-shell.sh 2>/dev/null ||
    taskbar_errors+=("/etc/xdg/plasma-workspace/env/orielos-shell.sh does not make org.orielos.desktop the fallback shell")
if [[ "$(kreadconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage)" != "$lnf.dark" ]]; then
    taskbar_errors+=("/etc/xdg/kdeglobals does not make $lnf.dark the default look-and-feel")
fi
for package in "$lnf" "$lnf.dark"; do
    for layout in org.orielos.desktop-layout.js org.kde.plasma.desktop-layout.js; do
        cmp -s "$shell/contents/layout.js" "/usr/share/plasma/look-and-feel/$package/contents/layouts/$layout" ||
            taskbar_errors+=("the $package look-and-feel package's $layout is missing or isn't the shell's layout")
    done
done
if [[ "$(kreadconfig6 --file /etc/xdg/kdeglobals --group KDE --key DefaultDarkLookAndFeel)" != "$lnf.dark" ]]; then
    taskbar_errors+=("/etc/xdg/kdeglobals does not make $lnf.dark the dark look-and-feel")
fi
for scheme in OrielOSLight OrielOSDark; do
    [[ -r "/usr/share/color-schemes/$scheme.colors" ]] || taskbar_errors+=("the $scheme colour scheme is not installed")
done
if [[ ! -f /usr/share/icons/hicolor/scalable/apps/orielos-start.svg ]]; then
    taskbar_errors+=("the Start button's icon, orielos-start.svg, is not installed")
fi
# The layout script puts OrielOS's Start menu on the taskbar; Plasma would leave a gap without it.
if [[ ! -f /usr/lib64/qt6/plugins/plasma/applets/org.orielos.startmenu.so ]]; then
    taskbar_errors+=("the Start menu widget, org.orielos.startmenu.so, is not installed")
fi
# The layout script's other widgets on the taskbar, and the window frames /etc/xdg/kwinrc chooses.
for widget in org.orielos.search org.orielos.taskview org.orielos.quicksettings org.orielos.clock org.orielos.showdesktop; do
    [[ -f "/usr/share/plasma/plasmoids/$widget/metadata.json" ]] || taskbar_errors+=("the taskbar widget $widget is not installed")
done
if [[ ! -f /usr/lib64/qt6/plugins/plasma/containmentactions/org.orielos.desktopmenu.so ]]; then
    taskbar_errors+=("the desktop's right-click menu, org.orielos.desktopmenu.so, is not installed")
fi
if [[ ! -f /usr/lib64/qt6/plugins/plasma/containmentactions/org.orielos.panelmenu.so ]]; then
    taskbar_errors+=("the taskbar's right-click menu, org.orielos.panelmenu.so, is not installed")
fi
if [[ ! -f /usr/lib64/qt6/plugins/org.kde.kdecoration3/org.orielos.decoration.so ]]; then
    taskbar_errors+=("OrielOS's window frames, org.orielos.decoration.so, are not installed")
fi
if [[ "$(kreadconfig6 --file /etc/xdg/kwinrc --group org.kde.kdecoration2 --key library)" != org.orielos.decoration ]]; then
    taskbar_errors+=("/etc/xdg/kwinrc does not make org.orielos.decoration the window frames")
fi
# It uses the menu models from plasma-workspace's private kicker QML module.
if [[ ! -f /usr/lib64/qt6/qml/org/kde/plasma/private/kicker/qmldir ]]; then
    taskbar_errors+=("plasma-workspace's org.kde.plasma.private.kicker QML module, which the Start menu needs, is missing")
fi
# The wallpapers come from the app-builder stage too. The look-and-feel package, its layout script
# and /etc/xdg/kscreenlockerrc make OrielOS the desktop and lock screen wallpaper.
for f in OrielOS/metadata.json OrielOS/contents/images/3840x2160.jpg OrielOS/contents/images_dark/3840x2160.jpg \
    OrielOS-Horizon/metadata.json OrielOS-Horizon/contents/images/3840x2160.jpg OrielOS-Horizon/contents/images_dark/3840x2160.jpg; do
    [[ -f "/usr/share/wallpapers/$f" ]] || taskbar_errors+=("the wallpaper file /usr/share/wallpapers/$f is not installed")
done
if [[ "$(kreadconfig6 --file /etc/xdg/kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image \
    --group General --key Image)" != "file:///usr/share/wallpapers/OrielOS/" ]]; then
    taskbar_errors+=("/etc/xdg/kscreenlockerrc does not make OrielOS the lock screen wallpaper")
fi
# OrielOS's sound theme comes from the app-builder stage; 20-desktop.sh makes it the default.
for f in index.theme stereo/desktop-login.oga stereo/message-new-instant.oga stereo/bell-window-system.oga; do
    [[ -f "/usr/share/sounds/orielos/$f" ]] || taskbar_errors+=("the sound theme file /usr/share/sounds/orielos/$f is not installed")
done
if [[ "$(kreadconfig6 --file /etc/xdg/kdeglobals --group Sounds --key Theme)" != orielos ]]; then
    taskbar_errors+=("/etc/xdg/kdeglobals does not make orielos the sound theme")
fi
# About this System shows the logo os-release names (95-version.sh sets LOGO=orielos-logo-icon), as
# long as /etc/xdg/kcm-about-distrorc sets no LogoPath of its own.
[[ -f /usr/share/icons/hicolor/scalable/apps/orielos-logo-icon.svg ]] ||
    taskbar_errors+=("OrielOS's logo icon, orielos-logo-icon.svg, is not installed")
if [[ -n "$(kreadconfig6 --file /etc/xdg/kcm-about-distrorc --group General --key LogoPath)" ]]; then
    taskbar_errors+=("/etc/xdg/kcm-about-distrorc points About this System at another logo")
fi
# OrielOS's wording for Plasma's widgets, such as "Pin to taskbar", comes from the app-builder
# stage as catalogues for en@orielos, which the session's environment script puts first for
# English. A catalogue only works while the widget still has every string it translates: Plasma
# builds a widget's text into its plugin, as UTF-16. If Plasma rewords one, update
# plasma/translations to match.
wording=/usr/share/locale/en@orielos/LC_MESSAGES
[[ -r /etc/xdg/plasma-workspace/env/orielos-wording.sh ]] ||
    taskbar_errors+=("/etc/xdg/plasma-workspace/env/orielos-wording.sh, which applies OrielOS's wording, is missing")
[[ -f "$wording/plasma_applet_org.kde.plasma.taskmanager.mo" ]] ||
    taskbar_errors+=("OrielOS's wording for the taskbar, $wording/plasma_applet_org.kde.plasma.taskmanager.mo, is not installed")
for catalogue in "$wording"/plasma_applet_*.mo; do
    [[ -f "$catalogue" ]] || continue
    applet="$(basename "$catalogue" .mo)"
    applet="/usr/lib64/qt6/plugins/plasma/applets/${applet#plasma_applet_}.so"
    if ! missing="$(
        python3 -I - "$catalogue" "$applet" <<'PY'
import os, struct, sys

catalogue, applet = sys.argv[1:]
if not os.path.isfile(applet):
    print(f"{catalogue} rewords {applet}, which is not installed")
    sys.exit()
plugin = open(applet, "rb").read()
data = open(catalogue, "rb").read()
count, originals = struct.unpack("<2I", data[8:16])
for i in range(count):
    length, offset = struct.unpack("<2I", data[originals + 8 * i:originals + 8 * i + 8])
    text = data[offset:offset + length].decode().split("\x04")[-1]
    if text and text.encode("utf-16-le") not in plugin:
        print(f"{applet} no longer has the text {text!r} that {catalogue} rewords")
PY
    )"; then
        taskbar_errors+=("could not check $catalogue against $applet")
    fi
    while IFS= read -r line; do
        [[ -z "$line" ]] || taskbar_errors+=("$line")
    done <<<"$missing"
done
if [[ "${#taskbar_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${taskbar_errors[@]}" >&2
    exit 1
fi
# The image's files all have the same timestamp, so icon loaders would trust the old icon cache
# and never find icons added after it was made, such as the Start button's.
gtk-update-icon-cache --force --quiet /usr/share/icons/hicolor

# The boot splash: OrielOS's Plymouth theme, with its logo from the app-builder stage and the spinner,
# password and keyboard images from Plymouth's spinner theme. The initramfs below carries it.
theme=/usr/share/plymouth/themes/orielos
spinner=/usr/share/plymouth/themes/spinner
for f in "$spinner"/throbber-*.png "$spinner"/animation-*.png "$spinner"/{bullet,capslock,entry,keyboard,keymap-render,lock}.png; do
    install -m 0644 "$f" "$theme/"
done
splash_errors=()
for f in orielos.plymouth watermark.png throbber-0001.png entry.png lock.png; do
    [[ -s "$theme/$f" ]] || splash_errors+=("$theme/$f is missing")
done
plymouth-set-default-theme orielos
[[ "$(plymouth-set-default-theme)" == orielos ]] || splash_errors+=("Plymouth's theme is $(plymouth-set-default-theme), not orielos")

kver="$(ls /usr/lib/modules)"
dracut --no-hostonly --kver "$kver" --reproducible --zstd --add "ostree plymouth" -f "/usr/lib/modules/$kver/initramfs.img"
# grep reads the whole listing: with -q it would stop at the match, lsinitrd would die of SIGPIPE,
# and pipefail would count the pipeline as failed.
lsinitrd "/usr/lib/modules/$kver/initramfs.img" | grep -F 'usr/share/plymouth/themes/orielos/watermark.png' >/dev/null ||
    splash_errors+=("the initramfs doesn't contain the OrielOS boot splash")
if [[ "${#splash_errors[@]}" -gt 0 ]]; then
    printf 'error: %s\n' "${splash_errors[@]}" >&2
    exit 1
fi

dnf clean all
rm -rf /var/cache/* /var/log/* /var/lib/dnf /tmp/* /run/dnf /run/sddm

bootc container lint

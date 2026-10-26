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
first_run_expected="org.kde.plasmasetup.language org.kde.plasmasetup.keyboard org.kde.plasmasetup.wifi org.orielos.plasmasetup.network org.kde.plasmasetup.time org.orielos.plasmasetup.power org.kde.plasmasetup.account org.kde.plasmasetup.finished"
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
    kcm_orielos_powermode; do
    for f in "/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/$module.so" "/usr/share/applications/$module.desktop"; do
        [[ -r "$f" ]] || update_errors+=("$f is missing")
    done
done
# Device security reads the accepted module signers from here.
[[ -r /usr/share/orielos/module-signers.txt ]] || update_errors+=("/usr/share/orielos/module-signers.txt is missing")
for f in /usr/share/applications/org.orielos.Settings.desktop /usr/share/kglobalaccel/org.orielos.Settings.desktop; do
    grep -qxF 'X-KDE-Shortcuts=Meta+I' "$f" 2>/dev/null || update_errors+=("$f is missing or doesn't give Settings Win+I")
done
grep -qxF 'NoDisplay=true' /usr/share/applications/systemsettings.desktop || update_errors+=("System Settings is still listed in Start")
# Start's and KRunner's search open Settings' pages in Settings, through OrielOS's runner.
[[ -r /usr/lib64/qt6/plugins/kf6/krunner/krunner_orielos_settings.so ]] || update_errors+=("the settings search runner, krunner_orielos_settings, is missing")
if [[ "$(kreadconfig6 --file /etc/xdg/krunnerrc --group Plugins --key krunner_systemsettingsEnabled)" != "false" ]]; then
    update_errors+=("/etc/xdg/krunnerrc does not turn off System Settings' search runner")
fi
if [[ -e /var/lib/orielos/update ]]; then
    update_errors+=("/var/lib/orielos/update exists in the image")
fi
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
menu_snippet=/usr/lib/bootupd/grub2-static/configs.d/12_orielos-menu.cfg
if [[ ! -r "$menu_snippet" ]]; then
    boot_menu_errors+=("the boot menu's GRUB snippet, $menu_snippet, is missing")
elif ! grub2-script-check "$menu_snippet"; then
    boot_menu_errors+=("grub2-script-check found errors in $menu_snippet")
fi
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

# New users get the taskbar from OrielOS's look-and-feel package, which 20-desktop.sh makes the
# default; the package and the Start button's icon come from the app-builder stage.
lnf=org.orielos.desktop
taskbar_errors=()
if [[ "$(kreadconfig6 --file /etc/xdg/kdeglobals --group KDE --key LookAndFeelPackage)" != "$lnf" ]]; then
    taskbar_errors+=("/etc/xdg/kdeglobals does not make $lnf the default look-and-feel")
fi
for package in "$lnf" "$lnf.dark"; do
    if [[ ! -f "/usr/share/plasma/look-and-feel/$package/contents/layouts/org.kde.plasma.desktop-layout.js" ]]; then
        taskbar_errors+=("the $package look-and-feel package or its layout script is not installed")
    fi
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

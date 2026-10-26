#!/usr/bin/env bash
# Installs the OrielOS image to a disk file, boots it headless under QEMU/KVM with Secure Boot
# and a software TPM, and checks that the first boot shows Plasma Setup. Over SSH through a vsock
# device it then finishes setup the way the wizard does (creates a user and marks setup done),
# restarts the VM and checks that the second boot reaches the login screen without Plasma Setup.
# On the second boot it checks the services, starts OrielOS's apps and logs the new user in to a
# Plasma Wayland session inside the VM, and checks that the new user got the OrielOS taskbar with
# OrielOS's Start menu, the OrielOS wallpaper and the Windows keyboard shortcuts. It checks the
# gaming defaults (ntsync, the sysctl settings, zram swap, GameMode, umu-launcher, the controller
# and peripheral udev rules and drivers) and that Fedora's countme reporting is off.
# It also checks that the Store shows Flathub only and that
# Firefox was installed from Flathub on first boot, waiting up to 10 minutes for the install.
# Last, it drives the Start menu with the keyboard over QMP (searching runs nothing, Enter opens
# the first result, Menu then Enter pins an app), restarts the VM and checks the pin is kept, then
# opens a recent file, takes screenshots of Recommended, each Tab stop and the account and power
# menus, and unpins the app again.
# The VM's firmware has Universal Blue's driver-signing key enrolled, and the test checks that the
# kernel trusts it. It also checks that the second boot is in the mode anti-cheat needs: kernel
# lockdown, the IOMMU on, kexec disabled, the BPF LSM, no hibernation and only allowed module
# signers. Prints PASS/FAIL per check.
#
# Usage: tests/boot-test.sh [--image REF] [--archive FILE] [--timeout SECONDS] [--memory MIB]
#                           [--cpus N] [--results DIR] [--no-mok] [--keep] [--help]
#   --image REF         image to test (default localhost/orielos:latest)
#   --archive FILE      load this OCI archive (from tools/build-image.sh) into Podman first and
#                       test it as localhost/orielos-archive:<file name>, unless --image is given
#   --timeout SECONDS   time to wait for SDDM after power-on, and again after the restart
#                       (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, the screenshots and summary.txt go
#                       (default tests/results/<run id>)
#   --no-mok            do not enrol Universal Blue's key in the VM's firmware; the key check
#                       then expects the key to be queued for enrolment instead
#   --keep              keep the disk and work folder, and print how to boot them again
# The work folder is /var/lib/orielos/vm/<run id>, where the run id is <image tag>-<UTC time>.
# Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
IMAGE="localhost/orielos:latest"
IMAGE_SET=0
ARCHIVE=""
TIMEOUT=600
MEMORY=6144
CPUS=4
RESULTS=""
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
SUMMARY=""
# The NVIDIA driver component packages; keep in step with image/build/85-check-modules.sh.
NVIDIA_COMPONENTS='^(nvidia-driver(-.*)?|nvidia-kmod-common|nvidia-modprobe|nvidia-persistenced|nvidia-settings|nvidia-xconfig|nvidia-libXNVCtrl|libnvidia-.*|xorg-x11-nvidia) '
SDDM_SECONDS=""
# The serial log holds every boot; the checks read the current boot's part, from LOG_FROM on.
# The Start menu checks restart the VM once more and then set LOG_UNTIL to the last line of the
# second boot, so the other checks still read the second boot alone.
LOG_FROM=1
LOG_UNTIL=""
REBOOTED=0
# First boot: Plasma Setup.
SETUP_USER="plasma-setup"
SETUP_SSH_OK=0
SETUP_SDDM_SECONDS=""
SETUP_UNIT=""
SETUP_USERS=""
SETUP_DONE=""
SETUP_TYPES=""
SETUP_PROCS=""
SETUP_SECONDS=""
SETUP_COLOURS=""
# Second boot: Plasma Setup must not run again.
AGAIN_UNIT=""
AGAIN_USERS=""
AGAIN_PROCS=""
SSH_SDDM=""
SSH_NM=""
SELFTEST_OUT=""
SELFTEST_RC=""
SESSION_FILE="plasma.desktop"
LOGIN_LOG_LINES=""
SESSION_TYPES=""
SESSION_PROCS=""
SESSION_SECONDS=""
DESKTOP_COLOURS=""
SOUND_STATE=""
# The new user's taskbar, read from their Plasma layout after the desktop login.
TASKBAR_READ=0
TASKBAR_PANELS=""
TASKBAR_LOCATION=""
TASKBAR_ORDER=""
TASKBAR_LAUNCHERS=""
TASKBAR_ICON=""
# The new user's desktop wallpaper, from the same file, and whether its light image is installed.
WALLPAPER_IMAGE=""
WALLPAPER_FILE=""
# The Windows shortcuts: "<shortcut>|<Qt key code>|<component>|<action>". The component may be
# empty when only the action name is fixed. Keep in step with docs/keyboard-shortcuts.md.
SHORTCUT_TABLE=(
    "Meta+E|0x10000045|org.kde.dolphin.desktop|_launch"
    "Meta+R|0x10000052|org.kde.krunner.desktop|_launch"
    "Meta+L|0x1000004c|ksmserver|Lock Session"
    "Meta+D|0x10000044|kwin|Show Desktop"
    "Meta+Tab|0x11000001|kwin|Overview"
    "Meta+I|0x10000049|systemsettings.desktop|_launch"
    "Meta+Shift+S|0x12000053|org.kde.spectacle.desktop|_launch"
    "Meta+V|0x10000056||show-on-mouse-pos"
    "Meta+.|0x1000002e|org.kde.plasma.emojier.desktop|_launch"
    "Ctrl+Shift+Esc|0x07000000|org.kde.plasma-systemmonitor.desktop|_launch"
    "Meta+Left|0x11000012|kwin|Window Quick Tile Left"
    "Meta+Right|0x11000014|kwin|Window Quick Tile Right"
    "Meta+Up|0x11000013|kwin|Window Maximize"
    "Meta+Down|0x11000015|kwin|Window Minimize"
    "Meta+Print|0x11000009|org.kde.spectacle.desktop|FullScreenToFile"
)
SHORTCUTS_OUT=""
SHORTCUT_CLASHES=""
TOOL_NAMES=""
WIN_E_SECONDS=""
# OrielOS's Start menu, driven with the keyboard over QMP last, because it restarts the VM. Each
# step's result is empty when the step was not reached; START_WHY says why the steps stopped.
START_WHY=""
START_SEARCH_RAN=""
START_ENTER_SECONDS=""
START_PINNED=""
START_FAVORITES=""
START_KEPT=""
START_KEPT_FAVORITES=""
# After the restart: whether a recently opened file was registered for Recommended, and whether
# unpinning Ark removed it from the pinned apps.
START_RECENT=""
START_UNPINNED=""
START_UNPIN_FAVORITES=""
BT_ENABLED=""
BT_ACTIVE=""
SERVER_UNITS=""
GAMING_OUT=""
MODULE_SIGNER=""
KERNEL_RPMS=""
NVIDIA_VERSIONS=""
IMAGE_KERNEL=""
KDUMP_BINARIES=""
# The Store and Firefox. Firefox's install starts on the first boot, so it is timed from the
# first power-on.
FIRST_POWER_ON=0
FIREFOX_WAIT=600
FIREFOX_SECONDS=""
STORE_REMOTES=""
STORE_NAME=""
STORE_BACKENDS=""
FIREFOX_APPS=""
FIREFOX_BROWSER=""
FIREFOX_VERSION=""
FIREFOX_JOURNAL=""
# Universal Blue's key and the drivers it signs.
KEY_TEST=""
KEY_STATE=""
KEY_NEW=""
V4L2_LOADED=""
MODULES_LOAD=""
# The anti-cheat boot mode, read over SSH on the second boot.
ANTICHEAT_OUT=""
ANTICHEAT_KARGS=(lockdown=integrity intel_iommu=on iommu.passthrough=0)

usage() {
    sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Print the current boot's part of the serial log.
clean_log() {
    if [[ -n "$LOG_UNTIL" ]]; then
        full_log | sed -n "${LOG_FROM},${LOG_UNTIL}p"
    else
        full_log | tail -n "+$LOG_FROM"
    fi
}

grep_log() {
    clean_log | grep -E "$@" || true
}

# Print the serial log up to the scripted desktop login, which restarts SDDM on purpose.
login_log() {
    if [[ -n "$LOGIN_LOG_LINES" ]]; then
        clean_log | sed -n "1,${LOGIN_LOG_LINES}p"
    else
        clean_log
    fi
}

# Remote script that prints Plasma Setup's state: "unit=<state of plasma-setup.service>",
# "users=<regular users>" and "done=yes|no" for its done marker.
setup_probe() {
    cat <<'SH'
printf 'unit=%s\n' "$(systemctl show -p ActiveState -p Result -p ConditionResult plasma-setup.service | sort | paste -sd ' ' -)"
printf 'users=%s\n' "$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | paste -sd ' ' -)"
if [ -e /etc/plasma-setup-done ]; then echo done=yes; else echo done=no; fi
SH
}

# First boot: read Plasma Setup's state, wait up to 120 s for SDDM to log the plasma-setup user
# in and for the wizard to start in that session, then take first-boot.png.
first_boot() {
    local start out probe status=""
    out="$(vm_ssh "$(setup_probe)" 2>&1)" || true
    SETUP_UNIT="$(sed -n 's/^unit=//p' <<<"$out")"
    SETUP_USERS="$(sed -n 's/^users=//p' <<<"$out")"
    SETUP_DONE="$(sed -n 's/^done=//p' <<<"$out")"
    info "plasma-setup.service: ${SETUP_UNIT:-no output}"
    info "Waiting up to 120 s for Plasma Setup's wizard"
    probe="$(session_probe "$SETUP_USER" kwin_wayland plasma-setup)"
    start=$SECONDS
    while ((SECONDS - start < 120)); do
        out="$(vm_ssh "$probe" 2>/dev/null)" || true
        SETUP_TYPES="$(sed -n 's/^types=//p' <<<"$out")"
        SETUP_PROCS="$(sed -n 's/^running=//p' <<<"$out" | paste -sd ' ' -)"
        if [[ " $SETUP_TYPES " == *" wayland "* && "$SETUP_PROCS" == "kwin_wayland plasma-setup" ]]; then
            SETUP_SECONDS=$((SECONDS - BOOT_START))
            break
        fi
        vm_running || return 0
        sleep 3
    done
    if [[ -z "$SETUP_SECONDS" ]]; then
        info "Plasma Setup's wizard did not start within 120 s"
    else
        info "Plasma Setup's wizard started $SETUP_SECONDS s after power-on; waiting 15 s for it to draw"
        sleep 15
    fi
    status="$(take_screenshots "$WORK/first-boot.ppm" "$RESULTS/first-boot.png" 0 | sed -n 's/^status=//p')" || true
    if [[ "$status" == "running" && -r "$WORK/first-boot.ppm" ]]; then
        SETUP_COLOURS="$(count_colours "$WORK/first-boot.ppm")" || true
    fi
}

# Restart the VM from inside, and move the start of the current boot's log to the new kernel's
# first line. Returns 1 if the new boot does not start within 120 s.
reboot_vm() {
    local from line start
    from=$(($(full_log | wc -l) + 1))
    info "Restarting the VM"
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    BOOT_START=$SECONDS
    SSH_OK=0
    start=$SECONDS
    while ((SECONDS - start < 120)); do
        line="$(full_log | tail -n "+$from" | grep -n -m1 'Linux version ' | cut -d: -f1)" || true
        if [[ -n "$line" ]]; then
            LOG_FROM=$((from + line - 1))
            REBOOTED=1
            info "The next boot started $((SECONDS - start)) s after the restart"
            return 0
        fi
        vm_running || break
        sleep 2
    done
    info "The next boot did not start within 120 s of the restart"
    return 1
}

# Check the services, start the apps and report the system state over SSH.
collect_over_ssh() {
    local state units out
    out="$(vm_ssh "$(setup_probe)
        pgrep -u $SETUP_USER -x plasma-setup >/dev/null && echo running=plasma-setup
        test -e /etc/sddm.conf.d/99-plasma-setup.conf && echo running=autologin" 2>&1)" || true
    AGAIN_UNIT="$(sed -n 's/^unit=//p' <<<"$out")"
    AGAIN_USERS="$(sed -n 's/^users=//p' <<<"$out")"
    AGAIN_PROCS="$(sed -n 's/^running=//p' <<<"$out" | paste -sd ' ' -)"
    SSH_SDDM="$(vm_ssh systemctl is-active sddm 2>&1)" || true
    SSH_NM="$(vm_ssh systemctl is-active NetworkManager 2>&1)" || true
    SELFTEST_RC=0
    SELFTEST_OUT="$(vm_ssh orielos-buildcheck --self-test 2>&1)" || SELFTEST_RC=$?
    state="$(vm_ssh systemctl is-system-running 2>&1)" || true
    info "System state: ${state:-unknown}"
    units="$(vm_ssh systemctl --failed --no-legend --plain 2>&1 | awk '{print $1}' | paste -sd ' ' -)" || true
    info "Failed units: ${units:-none}"
    BT_ENABLED="$(vm_ssh systemctl is-enabled bluetooth.service 2>&1)" || true
    BT_ACTIVE="$(vm_ssh systemctl is-active bluetooth.service 2>&1)" || true
    SERVER_UNITS="$(vm_ssh systemctl is-enabled bootc-fetch-apply-updates.timer sshd.service 2>&1 | paste -sd ' ' -)" || true
    KDUMP_BINARIES="$(vm_ssh command -v kexec kdumpctl makedumpfile 2>&1 | paste -sd ' ' -)" || true
    GAMING_OUT="$(vm_ssh "$(gaming_probe)" 2>&1)" || true
    MODULE_SIGNER="$(vm_ssh modinfo -F signer nvidia 2>&1)" || true
    KERNEL_RPMS="$(vm_ssh rpm -q kernel 2>&1 | paste -sd ' ' -)" || true
    STORE_REMOTES="$(vm_ssh flatpak remotes --system --columns=name 2>&1 | paste -sd ' ' -)" || true
    STORE_NAME="$(vm_ssh grep -m1 '^Name=' /usr/share/applications/org.kde.discover.desktop 2>&1)" || true
    STORE_BACKENDS="$(vm_ssh ls /usr/lib64/qt6/plugins/discover 2>&1 | paste -sd ' ' -)" || true
    NVIDIA_VERSIONS="$(vm_ssh "rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | grep -E '$NVIDIA_COMPONENTS' | grep -v '^nvidia-driver-selinux '" 2>&1)" || true
    KEY_TEST="$(vm_ssh mokutil --test-key "$UBLUE_KEY" 2>&1)" || true
    KEY_STATE="$(vm_ssh "sed -n 's/^key=//p' /var/lib/orielos/secure-boot/state" 2>&1)" || true
    KEY_NEW="$(vm_ssh mokutil --list-new 2>&1)" || true
    V4L2_LOADED="$(vm_ssh "lsmod | awk '\$1 == \"v4l2loopback\" {print \"loaded\"}'" 2>&1)" || true
    MODULES_LOAD="$(vm_ssh systemctl is-active systemd-modules-load.service 2>&1)" || true
    ANTICHEAT_OUT="$(vm_ssh "$(anticheat_probe)" 2>&1)" || true
}

# Print a shell script that reports the gaming defaults, one key=value per line: whether ntsync is
# loaded, the two sysctl settings, transparent hugepages, zram swap, the gaming and peripheral
# packages, umu-launcher, the extra drivers and their signer, the PlayStation touchpad rule, and
# Fedora's countme reporting.
gaming_probe() {
    cat <<'EOF'
echo "ntsync=$(lsmod | awk '$1 == "ntsync" {print "loaded"}')$(test -c /dev/ntsync && echo ',/dev/ntsync')"
echo "map_count=$(sysctl -n vm.max_map_count 2>&1)"
echo "split_lock=$(sysctl -n kernel.split_lock_mitigate 2>&1)"
echo "thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>&1)"
echo "zram=$(swapon --show=NAME --noheadings 2>&1 | grep zram | paste -sd ' ' -)"
echo "ananicy=$(rpm -q ananicy-cpp >/dev/null 2>&1 && echo installed)"
echo "missing=$(for p in gamemode umu-launcher steam-devices solaar-udev libratbag-ratbagd openrgb-udev-rules zram-generator-defaults; do rpm -q "$p" >/dev/null 2>&1 || printf '%s ' "$p"; done)"
echo "umu=$(command -v umu-run)"
echo "signers=$(for m in xone_gip hid_xpadneo hid_playstation ntsync; do printf '%s:%s ' "$m" "$(modinfo -F signer "$m" 2>/dev/null | head -n1)"; done)"
echo "touchpad_rule=$(test -f /usr/lib/udev/rules.d/70-orielos-playstation-touchpad.rules && echo present)"
echo "countme_files=$(grep -l '^countme=1' /etc/yum.repos.d/*.repo 2>/dev/null | paste -sd ' ' -)"
echo "countme_timer=$(systemctl is-enabled rpm-ostree-countme.timer 2>&1)"
EOF
}

# Print one value from gaming_probe's output: gaming_value <key>
gaming_value() {
    sed -n "s/^$1=//p" <<<"$GAMING_OUT" | head -n1
}

# Print a shell script that reports the kernel command line, lockdown, kexec, the active LSMs,
# whether hibernation is offered, and every loaded module with its signer.
anticheat_probe() {
    cat <<'EOF'
echo "cmdline=$(cat /proc/cmdline)"
echo "lockdown=$(cat /sys/kernel/security/lockdown 2>&1)"
echo "kexec=$(cat /proc/sys/kernel/kexec_load_disabled 2>&1)"
echo "lsm=$(cat /sys/kernel/security/lsm 2>&1)"
echo "hibernate=$(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate 2>&1)"
while read -r m _; do
    printf 'module=%s|%s\n' "$m" "$(modinfo -F signer "$m" 2>/dev/null)"
done </proc/modules
EOF
}

# Print the loaded modules whose signer is not in image/module-signers.txt, as "<module> (<signer>)".
anticheat_bad_modules() {
    local allowed name signer ok s
    mapfile -t allowed < <(grep -v -e '^#' -e '^[[:space:]]*$' "$ROOT/image/module-signers.txt")
    while IFS='|' read -r name signer; do
        ok=0
        for s in "${allowed[@]}"; do
            if [[ "$signer" == "$s" ]]; then ok=1; fi
        done
        if [[ "$ok" -ne 1 ]]; then printf '%s (%s)\n' "$name" "${signer:-unsigned}"; fi
    done < <(sed -n 's/^module=//p' <<<"$ANTICHEAT_OUT")
}

# Succeed if the first-boot Flatpak service has finished; record when, counted from the first
# power-on, the first time it has.
firefox_stamp_seen() {
    vm_ssh test -e /var/lib/orielos/flatpak-setup.done >/dev/null 2>&1 || return 1
    if [[ -z "$FIREFOX_SECONDS" ]]; then FIREFOX_SECONDS=$((SECONDS - FIRST_POWER_ON)); fi
    return 0
}

# Wait up to $FIREFOX_WAIT s for orielos-flatpak-setup.service to finish installing Firefox
# (it started on the first boot), then read what the checks need: the system-wide apps, the
# default browser for https links as the test user, Firefox's version and the service's journal.
wait_for_firefox() {
    local start=$SECONDS
    info "Waiting up to $FIREFOX_WAIT s for Firefox to be installed from Flathub"
    while ((SECONDS - start < FIREFOX_WAIT)); do
        firefox_stamp_seen && break
        vm_running || return 0
        sleep 5
    done
    FIREFOX_APPS="$(vm_ssh flatpak list --system --app --columns=application 2>&1 | paste -sd ' ' -)" || true
    FIREFOX_BROWSER="$(vm_ssh runuser -l "$TEST_USER" -c "'xdg-mime query default x-scheme-handler/https'" 2>&1)" || true
    FIREFOX_VERSION="$(vm_ssh "flatpak info --system org.mozilla.firefox | sed -n 's/^ *Version: *//p'" 2>&1)" || true
    FIREFOX_JOURNAL="$(vm_ssh journalctl -u orielos-flatpak-setup -b 0 -n 5 --no-pager -o cat 2>&1)" || true
}

# Remote script that prints the types of a user's sessions and which of the given processes run
# as that user: "types=<type ...>" and one "running=<process>" line each.
#   session_probe <user> <process...>
session_probe() {
    local user="$1"
    shift
    cat <<SH
types=""
for s in \$(loginctl list-sessions --no-legend | awk '\$3 == "$user" {print \$1}'); do
    types="\$types \$(loginctl show-session -p Type --value "\$s")"
done
printf 'types=%s\n' "\${types# }"
for p in $*; do
    if pgrep -u $user -x "\$p" >/dev/null; then printf 'running=%s\n' "\$p"; fi
done
SH
}

# Log the user that setup created in to the Plasma Wayland session through SDDM's autologin,
# wait up to 90 s for the session, then take desktop.png, check the user's sound services and read
# the user's taskbar.
desktop_login() {
    local start out probe status=""
    LOGIN_LOG_LINES="$(clean_log | wc -l)"
    info "Logging $TEST_USER in to the Plasma Wayland session ($SESSION_FILE) through SDDM's autologin"
    if ! out="$(vm_ssh "set -e
        id $TEST_USER >/dev/null
        test -r /usr/share/wayland-sessions/$SESSION_FILE
        mkdir -p /etc/sddm.conf.d
        printf '[Autologin]\nUser=%s\nSession=%s\n' $TEST_USER $SESSION_FILE >/etc/sddm.conf.d/99-boot-test-autologin.conf
        systemctl restart sddm" 2>&1)"; then
        info "Could not set up the desktop login: ${out:-no output}"
        return 0
    fi
    probe="$(session_probe "$TEST_USER" plasmashell kwin_wayland)"
    start=$SECONDS
    while ((SECONDS - start < 90)); do
        out="$(vm_ssh "$probe" 2>/dev/null)" || true
        SESSION_TYPES="$(sed -n 's/^types=//p' <<<"$out")"
        SESSION_PROCS="$(sed -n 's/^running=//p' <<<"$out" | paste -sd ' ' -)"
        if [[ " $SESSION_TYPES " == *" wayland "* && "$SESSION_PROCS" == "plasmashell kwin_wayland" ]]; then
            SESSION_SECONDS=$((SECONDS - start))
            break
        fi
        vm_running || return 0
        sleep 3
    done
    if [[ -z "$SESSION_SECONDS" ]]; then
        info "No Plasma Wayland session within 90 s"
        return 0
    fi
    info "The Plasma Wayland session started $SESSION_SECONDS s after restarting SDDM; waiting 15 s for the desktop to draw"
    sleep 15
    status="$(take_screenshots "$WORK/desktop.ppm" "$RESULTS/desktop.png" 0 | sed -n 's/^status=//p')" || true
    if [[ "$status" == "running" && -r "$WORK/desktop.ppm" ]]; then
        DESKTOP_COLOURS="$(count_colours "$WORK/desktop.ppm")" || true
    fi
    SOUND_STATE="$(vm_ssh systemctl --user -M "$TEST_USER@" is-active pipewire wireplumber 2>&1 | paste -sd ' ' -)" || true
    read_taskbar
    read_shortcuts
    press_win_e
}

# Ask the test user's kglobalaccel which action each Windows shortcut runs, over the session's
# D-Bus. Prints one "<shortcut>|<names>" line per shortcut, where <names> are the component and
# action names kglobalaccel returns, separated by "|", then "meta=<kwinrc's action for the Win key
# alone>" (empty means Plasma's default, Start).
shortcut_probe() {
    cat <<SH
ask() {
    out="\$(busctl --user -M $TEST_USER@ call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel action i "\$2" 2>/dev/null)"
    if [ -z "\$(printf '%s' "\$out" | grep -o '"[^"]*"')" ]; then
        out="\$(busctl --user -M $TEST_USER@ call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel globalShortcutsByKey '(ai)i' 1 "\$2" 0 2>/dev/null)"
    fi
    printf '%s|%s\n' "\$1" "\$(printf '%s' "\$out" | grep -o '"[^"]*"' | tr -d '"' | paste -sd '|' -)"
}
SH
    for spec in "${SHORTCUT_TABLE[@]}"; do
        IFS='|' read -r key code _ <<<"$spec"
        printf 'ask %q %d\n' "$key" "$code"
    done
    cat <<SH
printf 'meta=%s\n' "\$(runuser -l $TEST_USER -c 'kreadconfig6 --file kwinrc --group ModifierOnlyShortcuts --key Meta')"
SH
}

# Read the action of each Windows shortcut in the test user's session, and copy the user's
# kglobalshortcutsrc to the results.
read_shortcuts() {
    SHORTCUTS_OUT="$(vm_ssh "$(shortcut_probe)" 2>&1)" || true
    vm_ssh cat "/home/$TEST_USER/.config/kglobalshortcutsrc" >"$RESULTS/kglobalshortcutsrc" 2>/dev/null || true
    SHORTCUT_CLASHES="$(shortcut_clashes "$RESULTS/kglobalshortcutsrc" 2>/dev/null)" || true
    TOOL_NAMES="$(vm_ssh "grep -m1 -h '^Name=' /usr/share/applications/org.kde.plasma-systemmonitor.desktop /usr/share/applications/org.kde.spectacle.desktop /usr/share/applications/org.kde.dolphin.desktop" 2>&1 | paste -sd ',' -)" || true
}

# Print each key that more than one action in a kglobalshortcutsrc file has as its active
# shortcut, as "<key>: <group>/<action> <group>/<action>...", one line per key.
#   shortcut_clashes <file>
shortcut_clashes() {
    awk '
        /^\[/ { group = substr($0, 2, length($0) - 2); next }
        /^_k_friendly_name=/ || !/=/ { next }
        {
            name = substr($0, 1, index($0, "=") - 1)
            value = substr($0, index($0, "=") + 1)
            active = substr(value, 1, index(value, ",") - 1)
            n = split(active, keys, /\\t/)
            for (i = 1; i <= n; i++) {
                if (keys[i] == "" || keys[i] == "none") continue
                count[keys[i]]++
                owners[keys[i]] = owners[keys[i]] " " group "/" name
            }
        }
        END { for (k in count) if (count[k] > 1) print k ":" owners[k] }
    ' "$1"
}

# Press Win+E in the session over QMP and wait up to 20 s for Dolphin to start as the test user.
press_win_e() {
    local start
    vm_ssh pgrep -u "$TEST_USER" -x dolphin >/dev/null 2>&1 && return 0
    python3 -I - "$WORK/qmp.sock" <<'PY' || return 0
import json, socket, sys

sock = socket.socket(socket.AF_UNIX)
sock.settimeout(60)
sock.connect(sys.argv[1])
f = sock.makefile("rw")


def cmd(name, args=None):
    msg = {"execute": name}
    if args:
        msg["arguments"] = args
    f.write(json.dumps(msg) + "\n")
    f.flush()
    while True:
        reply = json.loads(f.readline())
        if "return" in reply or "error" in reply:
            return reply


f.readline()
cmd("qmp_capabilities")
cmd("send-key", {"keys": [{"type": "qcode", "data": "meta_l"}, {"type": "qcode", "data": "e"}]})
PY
    start=$SECONDS
    while ((SECONDS - start < 20)); do
        if vm_ssh pgrep -u "$TEST_USER" -x dolphin >/dev/null 2>&1; then
            WIN_E_SECONDS=$((SECONDS - start))
            vm_ssh pkill -u "$TEST_USER" -x dolphin >/dev/null 2>&1 || true
            return 0
        fi
        sleep 2
    done
}

# Print "running" or "stopped" for the test user's Dolphin, or nothing if SSH does not answer.
dolphin_state() {
    vm_ssh "if pgrep -u $TEST_USER -x dolphin >/dev/null; then echo running; else echo stopped; fi" 2>/dev/null || true
}

# Wait up to <seconds> for the test user's Dolphin to be running or stopped. Returns 1 if it is
# not by then, or if the VM stops.
#   wait_for_dolphin running|stopped <seconds>
wait_for_dolphin() {
    local want="$1" limit="$2" start=$SECONDS
    while true; do
        [[ "$(dolphin_state)" == "$want" ]] && return 0
        ((SECONDS - start < limit)) && vm_running || return 1
        sleep 1
    done
}

# Stop the test user's Dolphin and wait up to 10 s for it to go. Returns 1 if it does not.
stop_dolphin() {
    vm_ssh pkill -u "$TEST_USER" -x dolphin >/dev/null 2>&1 || true
    wait_for_dolphin stopped 10
}

# Print "favorites=<value>" for each OrielOS Start menu in a plasma-org.kde.plasma.desktop-appletsrc
# file: the pinned apps in its [Configuration][General] group. Plasma leaves the setting out while
# the pins are the defaults (unpinning the one app added removes it), so a missing setting prints
# the default from the Start menu's main.xml. Prints nothing if there is no Start menu.
#   start_favorites <file>
start_favorites() {
    python3 -I - "$1" "$ROOT/plasma/startmenu/main.xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

default = ""
for entry in ET.parse(sys.argv[2]).iter():
    if entry.tag.endswith("entry") and entry.get("name") == "favorites":
        default = next((d.text or "" for d in entry if d.tag.endswith("default")), "")

groups = {}
group = None
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    header = re.fullmatch(r"\[(.*)\]", line)
    if header:
        group = tuple(header.group(1).split("]["))
        groups.setdefault(group, {})
    elif group and "=" in line:
        key, value = line.split("=", 1)
        groups[group][key] = value

for g, keys in groups.items():
    if len(g) == 4 and g[0] == "Containments" and g[2] == "Applets" and keys.get("plugin") == "org.orielos.startmenu":
        print("favorites=" + groups.get(g + ("Configuration", "General"), {}).get("favorites", default))
PY
}

# Copy the test user's Plasma layout to <name> in the results and print the Start menu's pinned
# apps. Returns 1 if the file cannot be read or has no Start menu.
#   read_start_favorites <name>
read_start_favorites() {
    local out
    vm_ssh cat "/home/$TEST_USER/.config/plasma-org.kde.plasma.desktop-appletsrc" >"$RESULTS/$1" 2>/dev/null || return 1
    out="$(start_favorites "$RESULTS/$1")" || return 1
    [[ -n "$out" ]] || return 1
    sed -n '1s/^favorites=//p' <<<"$out"
}

# Read the Start menu's pinned apps into START_FAVORITES, polling for up to 30 s because Plasma
# saves widget settings to disk a few seconds after they change. Saves start-appletsrc.
wait_for_ark_pin() {
    local out start=$SECONDS
    while true; do
        if out="$(read_start_favorites start-appletsrc)"; then START_FAVORITES="$out"; fi
        [[ "$START_FAVORITES" == *org.kde.ark.desktop* ]] && return 0
        ((SECONDS - start < 30)) && vm_running || return 1
        sleep 3
    done
}

# Drive OrielOS's Start menu with the keyboard over QMP, as someone would: search without
# running anything, open the first result with Enter, pin Ark with the Menu key, then restart and
# check that the pin is still there. Runs after the other second-boot checks, because it restarts
# the VM; the second boot's SSH state and log range are put back afterwards.
start_menu_checks() {
    local start second_end ssh_ok=$SSH_OK log_from=$LOG_FROM
    if ! vm_running || [[ "$SSH_OK" -ne 1 ]]; then
        START_WHY="the VM stopped or SSH did not answer before the Start menu checks"
        return 0
    elif [[ -z "$SESSION_SECONDS" ]]; then
        START_WHY="$TEST_USER's Plasma session did not start"
        return 0
    fi
    info "Start menu: searching, opening and pinning with the keyboard over QMP"
    # Win+E started Dolphin earlier, so stop it before checking what the menu starts.
    if ! stop_dolphin; then
        START_WHY="$TEST_USER's Dolphin did not stop within 10 s"
        return 0
    fi

    # Typing only lists results; nothing may start until Enter.
    if ! vm_qmp keys:meta_l wait:2 keys:f wait:0.3 keys:i wait:0.3 keys:l wait:3 "shot:$RESULTS/start-search.png"; then
        START_WHY="could not send keys over QMP"
        return 0
    fi
    if wait_for_dolphin running 5; then
        START_SEARCH_RAN="yes"
        stop_dolphin || true
    elif [[ "$(dolphin_state)" == "stopped" ]]; then
        START_SEARCH_RAN="no"
    else
        START_WHY="SSH stopped answering after typing in the Start menu"
        return 0
    fi

    START_ENTER_SECONDS="none"
    vm_qmp keys:ret || true
    start=$SECONDS
    if wait_for_dolphin running 20; then START_ENTER_SECONDS=$((SECONDS - start)); fi
    if ! stop_dolphin; then
        START_WHY="$TEST_USER's Dolphin did not stop within 10 s after Enter"
        return 0
    fi

    # Ark is not pinned by default. The Menu key opens the result's context menu with "Pin to
    # Start" highlighted, so Enter pins it. A PC keyboard's Menu key is QEMU's "compose" key,
    # which Linux and Qt read as Menu; QEMU's "menu" key is a different, rarely used key.
    START_PINNED="no"
    if ! vm_qmp keys:meta_l wait:2 keys:a wait:0.3 keys:r wait:0.3 keys:k wait:3 \
        keys:compose wait:1 "shot:$RESULTS/start-pin-menu.png" keys:ret wait:2 keys:esc wait:5; then
        START_WHY="could not send keys over QMP"
        return 0
    fi
    if wait_for_ark_pin; then
        START_PINNED="yes"
    else
        START_WHY="pinning Ark did not save it, so the restart was skipped"
        return 0
    fi

    # The second boot's log ends here, before the shutdown messages.
    second_end="$(full_log | wc -l)"
    start_menu_restart
    SSH_OK=$ssh_ok
    if [[ "$LOG_FROM" != "$log_from" ]]; then
        LOG_UNTIL=$second_end
        LOG_FROM=$log_from
    fi
}

# Restart the VM, wait for SDDM's autologin to bring the test user's Plasma session back, read
# the Start menu's pinned apps again into start-appletsrc-restart and take start-pinned.png.
start_menu_restart() {
    local out probe types procs
    START_KEPT="no"
    if ! reboot_vm; then
        START_WHY="the VM did not restart"
        return 0
    fi
    if ! wait_for_ssh; then
        START_WHY="SSH did not answer after the restart"
        return 0
    fi
    # The autologin written by desktop_login stays in /etc/sddm.conf.d, so SDDM logs the user
    # straight back in.
    info "Waiting for $TEST_USER's Plasma session after the restart"
    probe="$(session_probe "$TEST_USER" plasmashell kwin_wayland)"
    while true; do
        out="$(vm_ssh "$probe" 2>/dev/null)" || true
        types="$(sed -n 's/^types=//p' <<<"$out")"
        procs="$(sed -n 's/^running=//p' <<<"$out" | paste -sd ' ' -)"
        [[ " $types " == *" wayland "* && "$procs" == "plasmashell kwin_wayland" ]] && break
        if ((SECONDS - BOOT_START >= TIMEOUT)) || ! vm_running; then
            START_WHY="$TEST_USER's Plasma session did not start within $TIMEOUT s of the restart"
            return 0
        fi
        sleep 3
    done
    info "The Plasma session is back $((SECONDS - BOOT_START)) s after the restart; waiting 15 s for the desktop to draw"
    sleep 15
    if ! START_KEPT_FAVORITES="$(read_start_favorites start-appletsrc-restart)"; then
        START_WHY="could not read the Start menu's settings after the restart"
        return 0
    fi
    if [[ "$START_KEPT_FAVORITES" == *org.kde.ark.desktop* ]]; then START_KEPT="yes"; fi
    vm_qmp keys:meta_l wait:3 "shot:$RESULTS/start-pinned.png" keys:esc || true
    start_menu_more_checks
}

# A script for the VM that writes a text file in the test user's Documents and tells the session's
# activity manager it was opened and closed, as an editor would, so the Start menu's Recommended
# list has a recent file. Prints "recent=yes" when the activity manager took both events.
start_recent_script() {
    local file="/home/$TEST_USER/Documents/orielos-notes.txt"
    cat <<SH
runuser -u $TEST_USER -- sh -c 'mkdir -p /home/$TEST_USER/Documents && echo Notes >$file'
bus() { busctl --user -M $TEST_USER@ "\$@" 2>/dev/null; }
# RegisterResourceEvent(application, window id, URI, event): 1 is Opened, 3 is Closed.
if bus call org.kde.ActivityManager /ActivityManager/Resources org.kde.ActivityManager.Resources \
    RegisterResourceEvent susu org.kde.kwrite 0 "file://$file" 1 >/dev/null &&
    bus call org.kde.ActivityManager /ActivityManager/Resources org.kde.ActivityManager.Resources \
        RegisterResourceEvent susu org.kde.kwrite 0 "file://$file" 3 >/dev/null; then
    echo recent=yes
else
    echo recent=no
fi
SH
}

# Wait up to 30 s for Ark to leave the Start menu's pinned apps, keeping the last reading in
# START_UNPIN_FAVORITES and start-appletsrc-unpinned. Returns 1 if it stays.
wait_for_ark_unpinned() {
    local start=$SECONDS
    while true; do
        START_UNPIN_FAVORITES="$(read_start_favorites start-appletsrc-unpinned)" || START_UNPIN_FAVORITES=""
        [[ -n "$START_UNPIN_FAVORITES" && "$START_UNPIN_FAVORITES" != *org.kde.ark.desktop* ]] && return 0
        ((SECONDS - start < 30)) && vm_running || return 1
        sleep 3
    done
}

# The rest of the Start menu, after the restart: Recommended with a recent file (Firefox, installed
# on the first boot, is recently added too), every stop in the Tab order, the account and power
# menus, and unpinning Ark. The screenshots are for reading by eye; unpinning is checked in the
# saved settings.
start_menu_more_checks() {
    local out i
    out="$(vm_ssh "$(start_recent_script)" 2>/dev/null)" || true
    START_RECENT="$(sed -n 's/^recent=//p' <<<"$out")"
    vm_qmp keys:meta_l wait:3 "shot:$RESULTS/start-recommended.png" || true
    # Tab from the search field visits All apps, the pinned apps, Recommended, the account and the
    # power button, then comes back to the search field.
    for i in 1 2 3 4 5 6; do
        vm_qmp keys:tab wait:1 "shot:$RESULTS/start-tab-$i.png" || true
    done
    # Shift+Tab from the search field goes round to the power button; Enter opens its menu.
    vm_qmp keys:esc wait:2 keys:meta_l wait:3 keys:shift+tab wait:1 keys:ret wait:2 \
        "shot:$RESULTS/start-power-menu.png" keys:esc wait:1 keys:esc wait:2 || true
    vm_qmp keys:meta_l wait:3 keys:shift+tab wait:1 keys:shift+tab wait:1 keys:ret wait:2 \
        "shot:$RESULTS/start-account-menu.png" keys:esc wait:1 keys:esc wait:2 || true
    # Ark is pinned, so the Menu key offers "Unpin from Start" first.
    START_UNPINNED="no"
    if vm_qmp keys:meta_l wait:2 keys:a wait:0.3 keys:r wait:0.3 keys:k wait:3 \
        keys:compose wait:1 "shot:$RESULTS/start-unpin-menu.png" keys:ret wait:2 keys:esc wait:5 &&
        wait_for_ark_unpinned; then
        START_UNPINNED="yes"
    fi
}

# Copy the test user's Plasma layout to plasma-appletsrc in the results and read its panels:
# how many there are, where the panel is, its widgets in order, the task manager's pinned apps
# and the Start button's icon. Also read the desktop's wallpaper and check that the OrielOS
# wallpaper's light image is installed.
read_taskbar() {
    local out
    vm_ssh cat "/home/$TEST_USER/.config/plasma-org.kde.plasma.desktop-appletsrc" >"$RESULTS/plasma-appletsrc" 2>/dev/null || return 0
    out="$(taskbar_summary "$RESULTS/plasma-appletsrc")" || return 0
    TASKBAR_READ=1
    TASKBAR_PANELS="$(sed -n 's/^panels=//p' <<<"$out")"
    TASKBAR_LOCATION="$(sed -n 's/^location=//p' <<<"$out")"
    TASKBAR_ORDER="$(sed -n 's/^order=//p' <<<"$out")"
    TASKBAR_LAUNCHERS="$(sed -n 's/^launchers=//p' <<<"$out")"
    TASKBAR_ICON="$(sed -n 's/^icon=//p' <<<"$out")"
    WALLPAPER_IMAGE="$(sed -n 's/^wallpaper=//p' <<<"$out")"
    WALLPAPER_FILE="$(vm_ssh "test -f /usr/share/wallpapers/OrielOS/contents/images/3840x2160.jpg && echo present || echo missing" 2>&1)" || true
}

# Print a summary of the panels in a plasma-org.kde.plasma.desktop-appletsrc file:
# "wallpaper=<the desktops' Image values, comma-separated>", "panels=<count>" and,
# when there is exactly one panel, "location=<edge>" (4 is the bottom), "order=<widgets>" (plugin
# names without org.kde.plasma. or org.orielos.), "launchers=<pinned apps>" and "icon=<the Start
# menu's icon>".
#   taskbar_summary <file>
taskbar_summary() {
    python3 -I - "$1" <<'PY'
import re
import sys

groups = {}
group = None
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    header = re.fullmatch(r"\[(.*)\]", line)
    if header:
        group = tuple(header.group(1).split("]["))
        groups.setdefault(group, {})
    elif group and "=" in line:
        key, value = line.split("=", 1)
        groups[group][key] = value

# Desktops belong to an activity; panels and the system tray do not.
desktops = [g for g, keys in groups.items()
            if len(g) == 2 and g[0] == "Containments" and keys.get("activityId")]
images = sorted({groups.get(d + ("Wallpaper", "org.kde.image", "General"), {}).get("Image", "") for d in desktops})
print("wallpaper=" + ",".join(images))
panels = [g[1] for g, keys in groups.items()
          if len(g) == 2 and g[0] == "Containments" and keys.get("plugin") == "org.kde.panel"]
print(f"panels={len(panels)}")
if len(panels) != 1:
    sys.exit()
panel = ("Containments", panels[0])
print("location=" + groups[panel].get("location", ""))
applets = [g[3] for g in groups if len(g) == 4 and g[:3] == panel + ("Applets",)]
saved = groups.get(panel + ("General",), {}).get("AppletOrder", "").split(";")
order = [a for a in saved if a in applets]
order += sorted((a for a in applets if a not in order), key=int)
names = []
for applet in order:
    plugin = groups[panel + ("Applets", applet)].get("plugin", "")
    general = groups.get(panel + ("Applets", applet, "Configuration", "General"), {})
    if plugin == "org.orielos.startmenu":
        print("icon=" + general.get("icon", ""))
    if plugin == "org.kde.plasma.icontasks":
        print("launchers=" + general.get("launchers", ""))
    names.append(re.sub(r"^org\.(kde\.plasma|orielos)\.", "", plugin))
print("order=" + " ".join(names))
PY
}

# Wait until the current boot has started SDDM and reached graphical.target, and record when
# SDDM started. On the first boot SDDM logs Plasma Setup's user in; afterwards it shows the
# login screen. Returns 1 on timeout.
wait_for_sddm() {
    local text
    info "Waiting up to $TIMEOUT s for SDDM"
    while ((SECONDS - BOOT_START < TIMEOUT)); do
        text="$(clean_log)"
        if [[ -z "$SDDM_SECONDS" && "$text" == *"Started sddm.service"* ]]; then
            SDDM_SECONDS=$((SECONDS - BOOT_START))
        fi
        if [[ "$text" == *"Started sddm.service"* && "$text" == *"Reached target graphical.target"* ]]; then
            return 0
        fi
        if ! vm_running; then
            info "The VM stopped before SDDM started"
            return 1
        fi
        sleep 2
    done
    info "Timed out after $TIMEOUT s"
    return 1
}

# Over QMP: check the VM is running, press a key first if asked (so the login form shows), and
# take a PPM and a PNG screendump. Prints "status=<run state>".
#   take_screenshots <ppm file> <png file> <press a key: 1 or 0>
take_screenshots() {
    python3 -I - "$WORK/qmp.sock" "$@" <<'PY'
import json, socket, sys, time

sock = socket.socket(socket.AF_UNIX)
sock.settimeout(60)
sock.connect(sys.argv[1])
f = sock.makefile("rw")


def cmd(name, args=None):
    msg = {"execute": name}
    if args:
        msg["arguments"] = args
    f.write(json.dumps(msg) + "\n")
    f.flush()
    while True:
        reply = json.loads(f.readline())
        if "return" in reply or "error" in reply:
            return reply


f.readline()
cmd("qmp_capabilities")
print("status=" + str(cmd("query-status").get("return", {}).get("status")))
if sys.argv[4] == "1":
    cmd("send-key", {"keys": [{"type": "qcode", "data": "shift"}]})
    time.sleep(3)
cmd("screendump", {"filename": sys.argv[2], "format": "ppm"})
cmd("screendump", {"filename": sys.argv[3], "format": "png"})
PY
}

# Print the number of distinct pixel values in a binary P6 PPM file.
count_colours() {
    python3 -I - "$1" <<'PY'
import sys

data = open(sys.argv[1], "rb").read()
pos = 0
tokens = []
while len(tokens) < 4:
    while data[pos:pos + 1].isspace():
        pos += 1
    if data[pos:pos + 1] == b"#":
        while data[pos:pos + 1] != b"\n":
            pos += 1
        continue
    start = pos
    while not data[pos:pos + 1].isspace():
        pos += 1
    tokens.append(data[start:pos])
pos += 1
if tokens[0] != b"P6":
    sys.exit("not a P6 PPM file")
pixels = data[pos:]
print(len({pixels[i:i + 3] for i in range(0, len(pixels) - 2, 3)}))
PY
}

run_checks() {
    local status="$1" colours="$2" cmdline btrfs after failed unit line versions rejected taskbar wallpaper shown="not reached"
    local wrong spec key component action names meta arg skipped
    local ac_cmdline ac_lockdown ac_kexec ac_lsm ac_hibernate ac_modules ac_bad ac_missing
    local no_ssh="SSH over vsock did not answer, so this could not be checked inside the VM"
    local ssh_hint="check that /dev/vhost-vsock exists on the host, and look for sshd or systemd-ssh-generator errors in serial.log"

    info "First boot"
    if [[ "$SETUP_SSH_OK" -ne 1 ]]; then
        fail "Plasma Setup starts on first boot: $no_ssh"
        hint "$ssh_hint"
    elif [[ " $SETUP_UNIT " != *" ConditionResult=yes "* || " $SETUP_UNIT " != *" Result=success "* ]]; then
        fail "plasma-setup.service did not run on first boot (${SETUP_UNIT:-no output})"
    elif [[ "$SETUP_DONE" != "no" ]]; then
        fail "Plasma Setup's done marker /etc/plasma-setup-done existed on first boot"
    elif [[ -n "$SETUP_USERS" ]]; then
        fail "There were regular users before Plasma Setup ran: $SETUP_USERS"
    elif [[ " $SETUP_TYPES " != *" wayland "* || "$SETUP_PROCS" != "kwin_wayland plasma-setup" ]]; then
        fail "Plasma Setup's wizard did not start within 120 s (session types for $SETUP_USER: ${SETUP_TYPES:-none}; running: ${SETUP_PROCS:-neither kwin_wayland nor plasma-setup})"
    elif [[ ! "$SETUP_COLOURS" =~ ^[0-9]+$ || "$SETUP_COLOURS" -le 1 ]]; then
        fail "Plasma Setup's wizard started but the screen is blank (${SETUP_COLOURS:-no screenshot} distinct colours)"
    else
        pass "Plasma Setup starts on first boot (plasma-setup.service ran; no regular users; the wizard runs in a Wayland session for $SETUP_USER after $SETUP_SECONDS s; $SETUP_COLOURS distinct colours on screen)"
    fi

    info "Second boot, after finishing setup as $TEST_USER and restarting"
    if [[ "$FINISH_OK" -ne 1 ]]; then
        fail "Plasma Setup does not run again: setup could not be finished on first boot"
    elif [[ "$REBOOTED" -ne 1 ]]; then
        fail "Plasma Setup does not run again: the VM did not restart"
    elif [[ "$SSH_OK" -ne 1 ]]; then
        fail "Plasma Setup does not run again: $no_ssh"
        hint "$ssh_hint"
    elif [[ " $AGAIN_UNIT " != *" ConditionResult=no "* ]]; then
        fail "plasma-setup.service was not skipped on the second boot (${AGAIN_UNIT:-no output})"
    elif [[ -n "$AGAIN_PROCS" ]]; then
        fail "Plasma Setup runs again on the second boot (found: ${AGAIN_PROCS/autologin/its SDDM autologin})"
    elif [[ "$AGAIN_USERS" != "$TEST_USER" ]]; then
        fail "The regular users are not just $TEST_USER after setup (${AGAIN_USERS:-none})"
    elif [[ "$SSH_SDDM" != "active" ]]; then
        fail "Plasma Setup was skipped, but SDDM is not active (systemctl is-active sddm: ${SSH_SDDM:-no output})"
    else
        pass "Plasma Setup does not run again (plasma-setup.service skipped by its condition on /etc/plasma-setup-done; no wizard or autologin; SDDM active; regular users: $AGAIN_USERS)"
    fi

    if [[ -n "$(grep_log 'secureboot: Secure boot enabled')" ]]; then
        pass "Secure Boot was on"
    else
        fail "Secure Boot was not on (no 'secureboot: Secure boot enabled' line)"
    fi

    cmdline="$(grep_log 'Kernel command line:' | head -n1)"
    if [[ "$cmdline" =~ (^|[[:space:]])rootflags=compress=zstd:1([[:space:]]|$) ]]; then
        pass "The kernel command line has rootflags=compress=zstd:1"
    else
        fail "The kernel command line lacks rootflags=compress=zstd:1 (${cmdline:-no command line found})"
    fi

    btrfs="$(grep_log 'BTRFS.*(device [^)]*).*zstd' | head -n1)"
    if [[ -n "$btrfs" ]]; then
        pass "The root filesystem is Btrfs with zstd compression ($btrfs)"
    else
        fail "No Btrfs zstd compression line in the kernel log"
    fi

    if [[ -n "$(grep_log 'Reached target graphical\.target')" ]]; then
        pass "graphical.target was reached"
    else
        fail "graphical.target was not reached"
    fi

    after="$(login_log | sed -n '/Started sddm\.service/,$p' |
        grep -E 'Stopp(ed|ing) sddm\.service|Failed to start sddm\.service|sddm\.service: (Failed|Main process exited)' || true)"
    if [[ -z "$(grep_log 'Started sddm\.service')" ]]; then
        fail "SDDM did not start"
    elif [[ -n "$after" ]]; then
        fail "SDDM stopped or failed after starting ($(head -n1 <<<"$after"))"
    elif [[ "$status" != "running" ]]; then
        fail "SDDM started but the VM was not running (state: ${status:-unknown})"
    elif [[ ! "$colours" =~ ^[0-9]+$ || "$colours" -le 1 ]]; then
        fail "SDDM started but the screen is blank (${colours:-no screenshot} distinct colours)"
    elif [[ "$SSH_OK" -ne 1 ]]; then
        fail "SDDM started and the screen shows $colours distinct colours, but $no_ssh"
        hint "$ssh_hint"
    elif [[ "$SSH_SDDM" != "active" ]]; then
        fail "SDDM is not active inside the VM (systemctl is-active sddm: ${SSH_SDDM:-no output})"
    else
        pass "SDDM is running ($colours distinct colours on screen; systemctl is-active sddm: active)"
    fi

    if [[ -z "$(grep_log 'Started NetworkManager\.service')" ]]; then
        fail "NetworkManager did not start"
    elif [[ -n "$(grep_log 'Failed to start NetworkManager\.service|NetworkManager\.service: Failed')" ]]; then
        fail "NetworkManager failed"
    elif [[ "$SSH_OK" -ne 1 ]]; then
        fail "NetworkManager started, but $no_ssh"
        hint "$ssh_hint"
    elif [[ "$SSH_NM" != "active" ]]; then
        fail "NetworkManager is not active inside the VM (systemctl is-active NetworkManager: ${SSH_NM:-no output})"
    else
        pass "NetworkManager is running (systemctl is-active NetworkManager: active)"
    fi

    line="$(grep -m1 'orielos-buildcheck: self-test passed' <<<"$SELFTEST_OUT" || true)"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "OrielOS apps start: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$SELFTEST_RC" -eq 0 && -n "$line" ]]; then
        pass "OrielOS apps start ($line)"
    else
        fail "OrielOS apps do not start (orielos-buildcheck --self-test exited with status $SELFTEST_RC)"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then say "" "    " "$line"; fi
        done <<<"$SELFTEST_OUT"
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Plasma Wayland session starts: $no_ssh"
        hint "$ssh_hint"
    elif [[ " $SESSION_TYPES " != *" wayland "* ]]; then
        fail "No Wayland session for $TEST_USER within 90 s (session types: ${SESSION_TYPES:-none})"
    elif [[ "$SESSION_PROCS" != "plasmashell kwin_wayland" ]]; then
        fail "The Plasma session for $TEST_USER is incomplete (running: ${SESSION_PROCS:-neither plasmashell nor kwin_wayland})"
    elif [[ ! "$DESKTOP_COLOURS" =~ ^[0-9]+$ || "$DESKTOP_COLOURS" -le 1 ]]; then
        fail "The Plasma session started but the desktop is blank (${DESKTOP_COLOURS:-no screenshot} distinct colours)"
    else
        pass "Plasma Wayland session starts (type wayland, plasmashell and kwin_wayland running after $SESSION_SECONDS s; $DESKTOP_COLOURS distinct colours on screen)"
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Sound services run: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$SOUND_STATE" == "active active" ]]; then
        pass "Sound services run (pipewire and wireplumber are active for $TEST_USER)"
    else
        fail "Sound services do not run for $TEST_USER (pipewire, wireplumber: ${SOUND_STATE:-no output})"
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Bluetooth service is enabled: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$BT_ENABLED" == "enabled" ]]; then
        pass "Bluetooth service is enabled (systemctl is-enabled bluetooth.service: enabled)"
        info "bluetooth.service is ${BT_ACTIVE:-unknown}; the VM has no Bluetooth adapter, so the service's condition skips it"
    else
        fail "Bluetooth service is not enabled (systemctl is-enabled bluetooth.service: ${BT_ENABLED:-no output})"
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Server defaults are off: $no_ssh"
        hint "$ssh_hint"
    else
        info "bootc-fetch-apply-updates.timer, sshd.service: ${SERVER_UNITS:-no output}"
        info "kexec and kdump binaries: ${KDUMP_BINARIES:-none}"
        if [[ "$SERVER_UNITS" == "disabled disabled" && -z "$KDUMP_BINARIES" ]]; then
            pass "Server defaults are off (automatic update reboots and sshd.service disabled; no kexec or kdump)"
        else
            fail "Server defaults are not all off (units: ${SERVER_UNITS:-no output}; kexec and kdump binaries: ${KDUMP_BINARIES:-none})"
        fi
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Gaming defaults are set: $no_ssh"
        fail "Gaming system pieces are installed: $no_ssh"
        fail "Fedora's countme reporting is off: $no_ssh"
        hint "$ssh_hint"
    else
        local ntsync map split thp zram ananicy missing umu signers rule
        ntsync="$(gaming_value ntsync)"
        map="$(gaming_value map_count)"
        split="$(gaming_value split_lock)"
        thp="$(gaming_value thp)"
        zram="$(gaming_value zram)"
        ananicy="$(gaming_value ananicy)"
        if [[ "$ntsync" == "loaded,/dev/ntsync" && "$map" == 1048576 && "$split" == 0 && "$thp" == *"[madvise]"* &&
            -n "$zram" && -z "$ananicy" ]]; then
            pass "Gaming defaults are set (ntsync loaded with /dev/ntsync; vm.max_map_count $map; kernel.split_lock_mitigate $split; transparent hugepages $thp; zram swap on $zram; no ananicy-cpp)"
        else
            fail "Gaming defaults are not all set (ntsync: ${ntsync:-not loaded}; vm.max_map_count: $map; kernel.split_lock_mitigate: $split; transparent hugepages: $thp; zram swap: ${zram:-none}; ananicy-cpp: ${ananicy:-not installed})"
        fi
        missing="$(gaming_value missing)"
        umu="$(gaming_value umu)"
        signers="$(gaming_value signers)"
        rule="$(gaming_value touchpad_rule)"
        # The extra drivers are signed by Universal Blue, the kernel's own ones by Fedora.
        if [[ -z "${missing// /}" && -n "$umu" && "$signers" == *"xone_gip:ublue kernel "* &&
            "$signers" == *"hid_xpadneo:ublue kernel "* && "$signers" =~ hid_playstation:[^\ ]+ &&
            "$rule" == present ]]; then
            pass "Gaming system pieces are installed (GameMode, umu-launcher at $umu, steam-devices and the peripheral udev rules; signers: ${signers% }; PlayStation touchpad rule present)"
        else
            fail "Gaming system pieces are missing (packages: ${missing:-none missing}; umu-run: ${umu:-missing}; signers: ${signers:-none}; PlayStation touchpad rule: ${rule:-missing})"
        fi
        if [[ -z "$(gaming_value countme_files)" && "$(gaming_value countme_timer)" == disabled ]]; then
            pass "Fedora's countme reporting is off (no repository sets countme=1; rpm-ostree-countme.timer disabled)"
        else
            fail "Fedora's countme reporting is still on (countme=1 in: $(gaming_value countme_files); rpm-ostree-countme.timer: $(gaming_value countme_timer))"
        fi
    fi

    versions="$(awk '{print $2}' <<<"$NVIDIA_VERSIONS" | sort -u)"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Kernel modules are signed by Fedora or Universal Blue: $no_ssh"
        hint "$ssh_hint"
    else
        info "rpm -q kernel: ${KERNEL_RPMS:-no output}"
        info "NVIDIA driver version: ${versions//$'\n'/ }"
        if [[ "$MODULE_SIGNER" != "ublue kernel" ]]; then
            fail "The NVIDIA kernel module is not signed by Universal Blue (modinfo -F signer nvidia: ${MODULE_SIGNER:-no output})"
        elif [[ -z "$IMAGE_KERNEL" || "$KERNEL_RPMS" != "kernel-$IMAGE_KERNEL" ]]; then
            fail "The installed kernel is not the image's kernel (rpm -q kernel: ${KERNEL_RPMS:-no output}; image: ${IMAGE_KERNEL:-unknown})"
        elif [[ -z "$versions" || "$(wc -l <<<"$versions")" -ne 1 ]]; then
            fail "The NVIDIA packages are not one version (${versions//$'\n'/ })"
        else
            pass "Kernel modules are signed by Fedora or Universal Blue (nvidia signer: $MODULE_SIGNER; kernel $IMAGE_KERNEL; NVIDIA $versions everywhere)"
        fi
    fi

    rejected="$(grep_log 'Loading of module with unavailable key is rejected' | head -n1)"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Universal Blue's key is trusted: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$MOK_ENROL" -ne 1 ]]; then
        # --no-mok: the key is not in the firmware, so the first boot must have queued it.
        if [[ "$KEY_STATE" != "pending" ]]; then
            fail "Universal Blue's key is not queued for enrolment (state: key=${KEY_STATE:-no output})"
        elif [[ "$KEY_NEW" != *"ublue kernel"* || "$(grep -c '^\[key ' <<<"$KEY_NEW")" -ne 1 ]]; then
            fail "mokutil --list-new does not show Universal Blue's key alone ($(grep -c '^\[key ' <<<"$KEY_NEW") keys)"
        else
            pass "Universal Blue's key is queued for enrolment (state: key=pending; mokutil --list-new shows only the ublue kernel key)"
        fi
    elif [[ "$KEY_TEST" != *"is already enrolled"* ]]; then
        fail "Universal Blue's key is not enrolled (mokutil --test-key: ${KEY_TEST:-no output})"
    elif [[ "$KEY_STATE" != "enrolled" ]]; then
        fail "orielos-secure-boot-key.service did not record the key as enrolled (state: key=${KEY_STATE:-no output})"
    elif [[ -n "$rejected" ]]; then
        fail "The kernel rejected a module signed with an unknown key ($rejected)"
    elif [[ "$V4L2_LOADED" != "loaded" ]]; then
        fail "v4l2loopback, signed by Universal Blue, is not loaded (lsmod)"
    elif [[ "$MODULES_LOAD" != "active" ]]; then
        fail "systemd-modules-load.service is not active (${MODULES_LOAD:-no output})"
    else
        pass "Universal Blue's key is trusted (mokutil --test-key: enrolled; state: key=enrolled; v4l2loopback loaded; systemd-modules-load.service active)"
    fi

    taskbar="panelspacer startmenu icontasks panelspacer systemtray digitalclock showdesktop"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "The OrielOS taskbar is set up: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$TASKBAR_READ" -ne 1 ]]; then
        fail "The OrielOS taskbar is set up: could not read $TEST_USER's ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
    elif [[ "$TASKBAR_PANELS" != "1" ]]; then
        fail "$TEST_USER does not have exactly one panel (${TASKBAR_PANELS:-no} panels; see plasma-appletsrc in the results)"
    elif [[ "$TASKBAR_LOCATION" != "4" ]]; then
        fail "$TEST_USER's panel is not at the bottom (location=${TASKBAR_LOCATION:-none}; 4 is the bottom)"
    elif [[ "$TASKBAR_ORDER" != "$taskbar" ]]; then
        fail "$TEST_USER's taskbar widgets are not in the OrielOS layout's order (found: ${TASKBAR_ORDER:-none}; expected: $taskbar)"
    elif [[ ",$TASKBAR_LAUNCHERS," != *",applications:org.kde.dolphin.desktop,"* ||
        ",$TASKBAR_LAUNCHERS," != *",applications:org.mozilla.firefox.desktop,"* ||
        ",$TASKBAR_LAUNCHERS," != *",applications:org.kde.discover.desktop,"* ]]; then
        fail "The taskbar does not pin Files, Firefox and Store (launchers: ${TASKBAR_LAUNCHERS:-none})"
    else
        pass "The OrielOS taskbar is set up (one panel at the bottom: $TASKBAR_ORDER; pinned: $TASKBAR_LAUNCHERS)"
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Taskbar: Start is OrielOS's Start menu: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$TASKBAR_READ" -ne 1 ]]; then
        fail "Taskbar: Start is OrielOS's Start menu: could not read $TEST_USER's ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
    elif [[ " $TASKBAR_ORDER " != *" startmenu "* ]]; then
        fail "Taskbar: $TEST_USER's panel has no org.orielos.startmenu (widgets: ${TASKBAR_ORDER:-none})"
    elif [[ " $TASKBAR_ORDER " =~ \ (kickoff|kicker|kickerdash)\  ]]; then
        fail "Taskbar: $TEST_USER's panel still has Plasma's launcher next to the Start menu (widgets: $TASKBAR_ORDER)"
    elif [[ "$TASKBAR_ICON" != "orielos-start" ]]; then
        fail "Taskbar: the Start button does not use the OrielOS logo (startmenu icon: ${TASKBAR_ICON:-none})"
    else
        pass "Taskbar: Start is OrielOS's Start menu (org.orielos.startmenu on the panel, no Plasma launcher; icon: $TASKBAR_ICON)"
    fi

    wallpaper="file:///usr/share/wallpapers/OrielOS/"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "The OrielOS wallpaper is set: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$TASKBAR_READ" -ne 1 ]]; then
        fail "The OrielOS wallpaper is set: could not read $TEST_USER's ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
    elif [[ "$WALLPAPER_IMAGE" != "$wallpaper" ]]; then
        fail "$TEST_USER's desktop does not use the OrielOS wallpaper (Image: ${WALLPAPER_IMAGE:-none}; expected: $wallpaper)"
    elif [[ "$WALLPAPER_FILE" != "present" ]]; then
        fail "The OrielOS wallpaper's light image is not installed (/usr/share/wallpapers/OrielOS/contents/images/3840x2160.jpg: ${WALLPAPER_FILE:-no output})"
    else
        pass "The OrielOS wallpaper is set (desktop Image: $WALLPAPER_IMAGE; /usr/share/wallpapers/OrielOS/contents/images/3840x2160.jpg is installed)"
    fi

    wrong=""
    for spec in "${SHORTCUT_TABLE[@]}"; do
        IFS='|' read -r key _ component action <<<"$spec"
        names="$(awk -F'|' -v k="$key" '$1 == k {sub(/^[^|]*\|/, ""); print; exit}' <<<"$SHORTCUTS_OUT")"
        if [[ "|$names|" != *"|$action|"* || (-n "$component" && "|$names|" != *"|$component|"*) ]]; then
            wrong="$wrong $key (${names:-nothing})"
        fi
    done
    meta="$(sed -n 's/^meta=//p' <<<"$SHORTCUTS_OUT")"
    if [[ -n "$meta" && "$meta" != *activateLauncherMenu* ]]; then wrong="$wrong Meta ($meta)"; fi
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Windows shortcuts are set: $no_ssh"
        hint "$ssh_hint"
    elif [[ -z "$SESSION_SECONDS" ]]; then
        fail "Windows shortcuts are set: $TEST_USER's Plasma session did not start"
    elif [[ -n "$wrong" ]]; then
        fail "Windows shortcuts are set: these shortcuts do not run the expected action:$wrong (see kglobalshortcutsrc in the results)"
    elif [[ -n "$SHORTCUT_CLASHES" ]]; then
        fail "Windows shortcuts are set, but more than one action has the same shortcut: $(paste -sd ';' - <<<"$SHORTCUT_CLASHES")"
    elif [[ -z "$WIN_E_SECONDS" ]]; then
        fail "Windows shortcuts are set, but pressing Win+E over QMP did not start Dolphin within 20 s"
    elif [[ "$TOOL_NAMES" != "Name=Process Manager,Name=Screenshot,Name=Files" ]]; then
        fail "System Monitor, Spectacle and Dolphin do not have their OrielOS names (${TOOL_NAMES:-no output})"
    else
        pass "Windows shortcuts are set (${#SHORTCUT_TABLE[@]} shortcuts and the Win key map to the expected actions in $TEST_USER's session; Win+E started Dolphin in $WIN_E_SECONDS s; Start shows Process Manager, Screenshot and Files)"
    fi

    info "Store and Firefox"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Store is Discover with Flathub only: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$STORE_REMOTES" != "flathub" ]]; then
        fail "The system Flatpak remotes are not just flathub (flatpak remotes --system: ${STORE_REMOTES:-no output})"
    elif [[ "$STORE_NAME" != "Name=Store" ]]; then
        fail "Discover's desktop entry is not named Store (${STORE_NAME:-no output})"
    elif [[ "$STORE_BACKENDS" != "flatpak-backend.so" ]]; then
        fail "Discover has backends other than Flatpak (plugins: ${STORE_BACKENDS:-none})"
    else
        pass "Store is Discover with Flathub only (remotes: flathub; org.kde.discover.desktop has Name=Store; backend plugins: $STORE_BACKENDS)"
    fi

    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "Firefox is installed on first boot: $no_ssh"
        hint "$ssh_hint"
    elif [[ -z "$FIREFOX_SECONDS" ]]; then
        fail "Firefox was not installed within $FIREFOX_WAIT s (no /var/lib/orielos/flatpak-setup.done)"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then say "" "    " "$line"; fi
        done <<<"$FIREFOX_JOURNAL"
    elif [[ " $FIREFOX_APPS " != *" org.mozilla.firefox "* ]]; then
        fail "org.mozilla.firefox is not in flatpak list --system (${FIREFOX_APPS:-no output})"
    elif [[ "$FIREFOX_BROWSER" != "org.mozilla.firefox.desktop" ]]; then
        fail "The default browser for https links is not Firefox (xdg-mime query default x-scheme-handler/https: ${FIREFOX_BROWSER:-no output})"
    else
        pass "Firefox is installed on first boot (flatpak-setup.done written; org.mozilla.firefox installed system-wide; xdg-mime gives $FIREFOX_BROWSER for https links as $TEST_USER)"
        info "Firefox was installed $FIREFOX_SECONDS s after the first power-on (version ${FIREFOX_VERSION:-unknown})"
    fi

    info "Start menu, last, because it restarts the VM"
    skipped="could not be checked: ${START_WHY:-the VM did not reach the desktop of $TEST_USER}"
    if [[ -z "$START_SEARCH_RAN" ]]; then
        fail "Start menu: typing a search runs nothing: $skipped"
    elif [[ "$START_SEARCH_RAN" == "yes" ]]; then
        fail "Start menu: typing \"fil\" started Dolphin before Enter was pressed (see start-search.png)"
    else
        pass "Start menu: typing a search runs nothing (no Dolphin within 5 s of typing \"fil\" after Win; see start-search.png)"
    fi

    if [[ -z "$START_ENTER_SECONDS" ]]; then
        fail "Start menu: Enter opens the first result: $skipped"
    elif [[ "$START_ENTER_SECONDS" == "none" ]]; then
        fail "Start menu: Enter after typing \"fil\" did not start Dolphin within 20 s (see start-search.png)"
    else
        pass "Start menu: Enter opens the first result (Dolphin started $START_ENTER_SECONDS s after Enter)"
    fi

    if [[ -z "$START_PINNED" ]]; then
        fail "Start menu: pinning saves the app: $skipped"
    elif [[ "$START_PINNED" != "yes" ]]; then
        fail "Start menu: Menu then Enter on Ark did not save org.kde.ark.desktop within 30 s (favorites: ${START_FAVORITES:-none}; see start-appletsrc)"
    else
        pass "Start menu: pinning saves the app (favorites: $START_FAVORITES)"
    fi

    if [[ -z "$START_KEPT" ]]; then
        fail "Start menu: pins survive a restart: $skipped"
    elif [[ "$START_KEPT" != "yes" ]]; then
        fail "Start menu: pins do not survive a restart (${START_WHY:-favorites after the restart: ${START_KEPT_FAVORITES:-none}}; see start-appletsrc-restart)"
    else
        pass "Start menu: pins survive a restart (favorites after the restart: $START_KEPT_FAVORITES; see start-pinned.png)"
    fi

    if [[ -z "$START_UNPINNED" ]]; then
        fail "Start menu: unpinning removes the app: $skipped"
    elif [[ "$START_UNPINNED" != "yes" ]]; then
        fail "Start menu: Menu then Enter on the pinned Ark did not remove it within 30 s (favorites: ${START_UNPIN_FAVORITES:-none}; see start-unpin-menu.png, start-appletsrc-unpinned)"
    else
        pass "Start menu: unpinning removes the app (favorites: $START_UNPIN_FAVORITES; see start-unpin-menu.png)"
    fi
    if [[ -n "$START_UNPINNED" ]]; then
        info "Start menu, to read by eye: start-recommended.png (Firefox recently added, orielos-notes.txt opened; registered: ${START_RECENT:-no}), start-tab-1.png to start-tab-6.png (the Tab order), start-power-menu.png and start-account-menu.png"
    fi

    info "Anti-cheat boot mode"
    ac_cmdline="$(sed -n 's/^cmdline=//p' <<<"$ANTICHEAT_OUT")"
    ac_lockdown="$(sed -n 's/^lockdown=//p' <<<"$ANTICHEAT_OUT")"
    ac_kexec="$(sed -n 's/^kexec=//p' <<<"$ANTICHEAT_OUT")"
    ac_lsm="$(sed -n 's/^lsm=//p' <<<"$ANTICHEAT_OUT")"
    ac_hibernate="$(sed -n 's/^hibernate=//p' <<<"$ANTICHEAT_OUT")"
    ac_modules="$(grep -c '^module=' <<<"$ANTICHEAT_OUT" || true)"
    ac_bad="$(anticheat_bad_modules | paste -sd ',' - | sed 's/,/, /g')"
    ac_missing=""
    for arg in "${ANTICHEAT_KARGS[@]}"; do
        if [[ " $ac_cmdline " != *" $arg "* ]]; then ac_missing="$ac_missing $arg"; fi
    done
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "The boot is anti-cheat ready: $no_ssh"
        hint "$ssh_hint"
    else
        info "Kernel lockdown: ${ac_lockdown:-no output}"
        info "Active LSMs: ${ac_lsm:-no output}"
        info "Loaded modules checked: $ac_modules"
        if [[ -n "$ac_missing" ]]; then
            fail "The boot is not anti-cheat ready: the kernel command line lacks$ac_missing"
            hint "check image/system/usr/lib/bootc/kargs.d/20-orielos-anticheat.toml and bootc's kargs in the install log"
        elif [[ "$ac_lockdown" != *"[integrity]"* ]]; then
            fail "The boot is not anti-cheat ready: kernel lockdown is not in integrity mode (${ac_lockdown:-no output})"
        elif [[ "$ac_kexec" != "1" ]]; then
            fail "The boot is not anti-cheat ready: kexec is not disabled (kernel.kexec_load_disabled: ${ac_kexec:-no output})"
            hint "check that systemd-sysctl.service read /usr/lib/sysctl.d/60-orielos-kexec.conf"
        elif [[ ",$ac_lsm," != *",bpf,"* ]]; then
            fail "The boot is not anti-cheat ready: the BPF LSM is not active (LSMs: ${ac_lsm:-no output})"
        elif [[ -z "$ac_hibernate" || "$ac_hibernate" == *'"yes"'* ]]; then
            fail "The boot is not anti-cheat ready: hibernation is offered (CanHibernate: ${ac_hibernate:-no output})"
            hint "check /usr/lib/systemd/sleep.conf.d/50-orielos.conf"
        elif [[ "$ac_modules" -eq 0 ]]; then
            fail "The boot is not anti-cheat ready: no loaded modules found in /proc/modules"
        elif [[ -n "$ac_bad" ]]; then
            fail "The boot is not anti-cheat ready: loaded modules with an unexpected signer or none: $ac_bad"
            hint "the allowed signers are in image/module-signers.txt"
        else
            pass "The boot is anti-cheat ready (${ANTICHEAT_KARGS[*]} on the command line; lockdown $ac_lockdown; kexec disabled; bpf LSM active; CanHibernate: $ac_hibernate; all $ac_modules loaded modules signed by an allowed signer)"
        fi
    fi

    failed="$(grep_log 'FAILED' | sed -n 's/.*Failed to start \([^ ]*\).*/\1/p' | sort -u)"
    while IFS= read -r unit; do
        [[ -n "$unit" && "$unit" != sddm.service && "$unit" != NetworkManager.service ]] || continue
        warn "$unit failed to start"
    done <<<"$failed"
    if [[ -n "$SETUP_SDDM_SECONDS" ]]; then shown="about $SETUP_SDDM_SECONDS s"; fi
    info "First boot: time from power-on to SDDM: $shown"
    shown="not reached"
    if [[ -n "$SETUP_SECONDS" ]]; then shown="about $SETUP_SECONDS s"; fi
    info "First boot: time from power-on to Plasma Setup's wizard: $shown"
    shown="not reached"
    if [[ "$REBOOTED" -eq 1 && -n "$SDDM_SECONDS" ]]; then shown="about $SDDM_SECONDS s"; fi
    info "Second boot: time from the restart to SDDM: $shown"
}

main() {
    local original=("$@") run_id tag status="" colours="" timed_out=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image | --archive | --timeout | --memory | --cpus | --results)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --image)
                        IMAGE="$2"
                        IMAGE_SET=1
                        ;;
                    --archive) ARCHIVE="$2" ;;
                    --timeout) TIMEOUT="$2" ;;
                    --memory) MEMORY="$2" ;;
                    --cpus) CPUS="$2" ;;
                    --results) RESULTS="$2" ;;
                esac
                shift 2
                ;;
            --keep)
                KEEP=1
                shift
                ;;
            --no-mok)
                MOK_ENROL=0
                shift
                ;;
            --help | -h)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "unknown option: $1"
                ;;
        esac
    done
    [[ "$TIMEOUT" =~ ^[0-9]+$ && "$TIMEOUT" -gt 0 ]] || die "--timeout needs a number of seconds"
    [[ "$MEMORY" =~ ^[0-9]+$ ]] || die "--memory needs a number of MiB"
    [[ "$CPUS" =~ ^[0-9]+$ ]] || die "--cpus needs a number"

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host

    # An archive gets its own tag unless --image was given, so builds keep their tags.
    if [[ -n "$ARCHIVE" && "$IMAGE_SET" -eq 0 ]]; then
        tag="${ARCHIVE##*/}"
        IMAGE="localhost/orielos-archive:${tag%.ociarchive}"
    fi
    tag="latest"
    if [[ "${IMAGE##*/}" == *:* ]]; then tag="${IMAGE##*:}"; fi
    run_id="$(printf '%s-%s' "$tag" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/$run_id"
    if [[ -z "$RESULTS" ]]; then RESULTS="$ROOT/tests/results/$run_id"; fi
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT

    info "Run $run_id; results in $RESULTS"
    if [[ -n "$ARCHIVE" ]]; then load_archive; fi
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"
    # The ostree.linux label comes from the base image, so ask the image itself which kernel it has.
    IMAGE_KERNEL="$(podman run --rm "$IMAGE" rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)" || die "could not read the kernel version from $IMAGE"

    setup_ssh
    install_image
    start_vm
    FIRST_POWER_ON=$BOOT_START

    info "First boot: Plasma Setup should start"
    wait_for_sddm || timed_out=1
    SETUP_SDDM_SECONDS="$SDDM_SECONDS"
    if vm_running && wait_for_ssh; then
        SETUP_SSH_OK=1
        first_boot
        finish_setup
        firefox_stamp_seen || true
        if vm_running; then reboot_vm || timed_out=1; fi
    fi

    if [[ "$REBOOTED" -eq 1 ]]; then
        info "Second boot: the login screen should appear"
        SDDM_SECONDS=""
        if wait_for_sddm; then
            info "Waiting 15 s for the greeter to draw"
            sleep 15
        else
            timed_out=1
        fi
        if vm_running && wait_for_ssh; then collect_over_ssh; fi
        if vm_running; then
            status="$(take_screenshots "$WORK/screen.ppm" "$RESULTS/screenshot.png" 1 | sed -n 's/^status=//p')" || true
            if [[ -r "$WORK/screen.ppm" ]]; then colours="$(count_colours "$WORK/screen.ppm")" || true; fi
            if [[ "$SSH_OK" -eq 1 && "$status" == "running" ]]; then desktop_login; fi
        fi
        # Last, so the download runs alongside the other checks; most of the time it is done.
        if vm_running && [[ "$SSH_OK" -eq 1 ]]; then wait_for_firefox; fi
        # After everything else on the second boot, because it restarts the VM.
        start_menu_checks
    fi
    stop_pid "$WORK/qemu.pid"
    full_log >"$RESULTS/serial.log"

    run_checks "$status" "$colours"
    if [[ "$FAILED" -eq 0 && "$timed_out" -eq 0 ]]; then
        say "$C_GREEN" PASS "All $PASSED checks passed"
        return 0
    fi
    say "$C_RED" FAIL "$FAILED of $((PASSED + FAILED)) checks failed"
    return 1
}

main "$@"

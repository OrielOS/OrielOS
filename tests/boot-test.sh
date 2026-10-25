#!/usr/bin/env bash
# Installs the OrielOS image to a disk file, boots it headless under QEMU/KVM with Secure Boot
# and a software TPM, and checks that the first boot shows Plasma Setup. Over SSH through a vsock
# device it then finishes setup the way the wizard does (creates a user and marks setup done),
# restarts the VM and checks that the second boot reaches the login screen without Plasma Setup.
# On the second boot it checks the services, starts OrielOS's apps and logs the new user in to a
# Plasma Wayland session inside the VM, and checks that the new user got the Windows-style taskbar.
# It also checks that the Store shows Flathub only and that
# Firefox was installed from Flathub on first boot, waiting up to 10 minutes for the install.
# Prints PASS/FAIL per check.
#
# Usage: tests/boot-test.sh [--image REF] [--archive FILE] [--timeout SECONDS] [--memory MIB]
#                           [--cpus N] [--results DIR] [--keep] [--help]
#   --image REF         image to test (default localhost/orielos:latest)
#   --archive FILE      load this OCI archive (from tools/build-image.sh) into Podman first and
#                       test it as localhost/orielos-archive:<file name>, unless --image is given
#   --timeout SECONDS   time to wait for SDDM after power-on, and again after the restart
#                       (default 600)
#   --memory MIB        VM memory (default 6144)
#   --cpus N            VM CPUs (default 4)
#   --results DIR       where serial.log, install.log, the screenshots and summary.txt go
#                       (default tests/results/<run id>)
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
# The serial log holds both boots; the checks read the current boot's part, from this line on.
LOG_FROM=1
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
BT_ENABLED=""
BT_ACTIVE=""
SERVER_UNITS=""
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

# Print the current boot's part of the serial log.
clean_log() {
    full_log | tail -n "+$LOG_FROM"
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
            info "The second boot started $((SECONDS - start)) s after the restart"
            return 0
        fi
        vm_running || break
        sleep 2
    done
    info "The second boot did not start within 120 s of the restart"
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
    MODULE_SIGNER="$(vm_ssh modinfo -F signer nvidia 2>&1)" || true
    KERNEL_RPMS="$(vm_ssh rpm -q kernel 2>&1 | paste -sd ' ' -)" || true
    STORE_REMOTES="$(vm_ssh flatpak remotes --system --columns=name 2>&1 | paste -sd ' ' -)" || true
    STORE_NAME="$(vm_ssh grep -m1 '^Name=' /usr/share/applications/org.kde.discover.desktop 2>&1)" || true
    STORE_BACKENDS="$(vm_ssh ls /usr/lib64/qt6/plugins/discover 2>&1 | paste -sd ' ' -)" || true
    NVIDIA_VERSIONS="$(vm_ssh "rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' | grep -E '$NVIDIA_COMPONENTS' | grep -v '^nvidia-driver-selinux '" 2>&1)" || true
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
}

# Copy the test user's Plasma layout to plasma-appletsrc in the results and read its panels:
# how many there are, where the panel is, its widgets in order, the task manager's pinned apps
# and the Start button's icon.
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
}

# Print a summary of the panels in a plasma-org.kde.plasma.desktop-appletsrc file: "panels=<count>"
# and, when there is exactly one panel, "location=<edge>" (4 is the bottom), "order=<widgets>"
# (plugin names without org.kde.plasma.), "launchers=<pinned apps>" and "icon=<Start icon>".
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
    if plugin == "org.kde.plasma.kickoff":
        print("icon=" + general.get("icon", ""))
    if plugin == "org.kde.plasma.icontasks":
        print("launchers=" + general.get("launchers", ""))
    names.append(plugin.removeprefix("org.kde.plasma."))
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
    local status="$1" colours="$2" cmdline btrfs after failed unit line versions taskbar shown="not reached"
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

    taskbar="panelspacer kickoff icontasks panelspacer systemtray digitalclock showdesktop"
    if [[ "$SSH_OK" -ne 1 ]]; then
        fail "The Windows-style taskbar is set up: $no_ssh"
        hint "$ssh_hint"
    elif [[ "$TASKBAR_READ" -ne 1 ]]; then
        fail "The Windows-style taskbar is set up: could not read $TEST_USER's ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
    elif [[ "$TASKBAR_PANELS" != "1" ]]; then
        fail "$TEST_USER does not have exactly one panel (${TASKBAR_PANELS:-no} panels; see plasma-appletsrc in the results)"
    elif [[ "$TASKBAR_LOCATION" != "4" ]]; then
        fail "$TEST_USER's panel is not at the bottom (location=${TASKBAR_LOCATION:-none}; 4 is the bottom)"
    elif [[ "$TASKBAR_ORDER" != "$taskbar" ]]; then
        fail "$TEST_USER's taskbar widgets are not in the Windows-style order (found: ${TASKBAR_ORDER:-none}; expected: $taskbar)"
    elif [[ ",$TASKBAR_LAUNCHERS," != *",applications:org.kde.dolphin.desktop,"* ||
        ",$TASKBAR_LAUNCHERS," != *",applications:org.mozilla.firefox.desktop,"* ||
        ",$TASKBAR_LAUNCHERS," != *",applications:org.kde.discover.desktop,"* ]]; then
        fail "The taskbar does not pin Files, Firefox and Store (launchers: ${TASKBAR_LAUNCHERS:-none})"
    elif [[ "$TASKBAR_ICON" != "orielos-start" ]]; then
        fail "The Start button does not use the OrielOS logo (kickoff icon: ${TASKBAR_ICON:-none})"
    else
        pass "The Windows-style taskbar is set up (one panel at the bottom: $TASKBAR_ORDER; pinned: $TASKBAR_LAUNCHERS; Start icon: $TASKBAR_ICON)"
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

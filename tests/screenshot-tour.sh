#!/usr/bin/env bash
# Installs the OrielOS image to a disk file, boots it under QEMU/KVM with Secure Boot, a software
# TPM and a 1920x1080 screen, and saves a numbered set of screenshots that show what OrielOS looks
# like: the boot splash, Plasma Setup's pages, the sign-in screen, the desktop, Start, a setting
# found from Start, Files, the Store, Process Manager, Settings and some of its pages, Firefox,
# Screenshot, the overview, the lock screen (idle and unlocking), the dark theme and the dark lock
# screen. It drives the VM with QMP mouse clicks and key presses, as a person would, and uses SSH
# through a vsock device to wait for each step and to close windows between screenshots.
# A screenshot that cannot be taken is reported as a WARN line and skipped.
#
# Usage: tests/screenshot-tour.sh [--image REF] [--keep] [--help]
#   --image REF   image to show (default localhost/orielos:latest)
#   --keep        keep the disk and work folder, and print how to boot them again
# The screenshots go to tests/results/tour-<run id>/NN-name.png, with a contact sheet,
# 00-contact-sheet.png, when Pillow or ImageMagick is installed. The work folder is
# /var/lib/orielos/vm/tour-<run id>, where the run id is <image tag>-<UTC time>.
# Runs as root; re-executes itself through sudo otherwise.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/vm.sh
source "$ROOT/tests/lib/vm.sh"
IMAGE="localhost/orielos:latest"
MEMORY=6144
CPUS=4
KEEP=0
VM_ROOT="/var/lib/orielos/vm"
WORK=""
RESULTS=""
SUMMARY=""
# The account typed into Plasma Setup's user page.
TOUR_NAME="Alex Morgan"
TOUR_USER="alex"
TOUR_PASSWORD="orielos-tour"
# Plasma Setup's Next button on a 1920x1080 screen.
NEXT_X=1283
NEXT_Y=883
# The apps the tour opens; closed between screenshots.
APPS="dolphin plasma-discover plasma-systemmonitor orielos-settings systemsettings firefox spectacle"

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Save a screenshot as <name>.png in the results: shot <name>
shot() {
    if vm_qmp "shot:$RESULTS/$1.png" && [[ -s "$RESULTS/$1.png" ]]; then
        info "Saved $1.png"
    else
        warn "Could not save $1.png"
    fi
}

# Save a screenshot as <name>.ppm in the work folder and print its path: frame <name>
frame() {
    vm_qmp "shot:$WORK/$1.ppm" >/dev/null 2>&1 || true
    printf '%s\n' "$WORK/$1.ppm"
}

# Wait up to <seconds> for every process to run as a user: wait_for_procs <seconds> <user> <process...>
wait_for_procs() {
    local seconds="$1" user="$2" start=$SECONDS script="" p
    shift 2
    for p in "$@"; do script="$script pgrep -u $user -x $p >/dev/null &&"; done
    script="$script true"
    while ((SECONDS - start < seconds)); do
        vm_ssh "$script" >/dev/null 2>&1 && return 0
        vm_running || return 1
        sleep 2
    done
    return 1
}

# Wait up to <seconds> for a command in the VM to succeed: wait_until <seconds> <command>
wait_until() {
    local seconds="$1" start=$SECONDS
    while ((SECONDS - start < seconds)); do
        vm_ssh "$2" >/dev/null 2>&1 && return 0
        vm_running || return 1
        sleep 3
    done
    return 1
}

# Run a command in the tour user's desktop session: in_session <command...>
in_session() {
    vm_ssh "systemd-run --user -M $TOUR_USER@ --collect --quiet --setenv=WAYLAND_DISPLAY=wayland-0 -- $*"
}

# Close the apps the tour opens.
close_apps() {
    local p
    # Match whole command lines: process names are cut to 15 characters, and Flatpak apps run
    # under other names.
    for p in $APPS; do vm_ssh "pkill -u $TOUR_USER -f $p" >/dev/null 2>&1 || true; done
    sleep 3
}

# Take a screenshot every second for the first 60 s after power-on, and keep the boot splash
# as 01-boot-splash.png: the frame at the full screen size with the most colours before the
# desktop appears. Without Pillow, keep the frame from 25 s after power-on.
capture_splash() {
    local i
    mkdir -p "$WORK/boot"
    info "Taking a screenshot every second for 60 s to catch the boot splash"
    for i in $(seq -w 1 60); do
        vm_qmp "shot:$WORK/boot/$i.png" >/dev/null 2>&1 || true
        sleep 1
    done
    if python3 -c 'import PIL' >/dev/null 2>&1; then
        i="$(
            python3 -I - "$WORK/boot" "$VM_SCREEN" <<'PY'
import glob, sys
from PIL import Image

size = tuple(int(n) for n in sys.argv[2].split("x"))
best, most = "", 0
for name in sorted(glob.glob(sys.argv[1] + "/*.png")):
    im = Image.open(name).convert("RGB")
    colours = len(im.resize((320, 180)).getcolors(1 << 16) or range(1 << 16))
    if colours > 1000:
        break
    if im.size == size and colours > most:
        best, most = name, colours
print(best)
PY
        )" || i=""
    else
        i="$WORK/boot/25.png"
    fi
    if [[ -n "$i" && -s "$i" ]]; then
        cp "$i" "$RESULTS/01-boot-splash.png"
        i="${i##*/}"
        info "Saved 01-boot-splash.png (${i%.png} s after power-on)"
    else
        warn "Could not catch the boot splash"
    fi
}

# Whether two frames show the same page: they differ in at most a few thousand bytes, such as a
# text cursor blinking. Without Python, only identical frames count: same_page <frame> <frame>
same_page() {
    if ! command -v python3 >/dev/null 2>&1; then
        cmp -s "$1" "$2"
        return
    fi
    python3 -I - "$1" "$2" <<'PY'
import sys

with open(sys.argv[1], "rb") as a, open(sys.argv[2], "rb") as b:
    first, second = a.read(), b.read()
if len(first) != len(second):
    sys.exit(1)
sys.exit(0 if sum(x != y for x, y in zip(first, second)) <= 5000 else 1)
PY
}

# Click Plasma Setup's Next button, up to ten times, until the page stays the same or the account
# exists, saving each new page as 03-setup-<n>.png from <n> on. Prints the next free number:
# next_pages <n>
next_pages() {
    local n="$1" limit=$(($1 + 10)) before after
    while ((n < limit)); do
        before="$(frame before)"
        vm_qmp "click:$NEXT_X,$NEXT_Y" wait:3 >/dev/null 2>&1 || true
        after="$(frame after)"
        same_page "$before" "$after" && break
        shot "03-setup-$n" >&2
        n=$((n + 1))
        vm_ssh "id $TOUR_USER" >/dev/null 2>&1 && break
    done
    printf '%s\n' "$n"
}

# First boot: wait for Plasma Setup's wizard and go through it with the mouse and keyboard,
# typing the tour's account on the page where Next stops. If the account was not created, finish
# setup over SSH as the boot test does. Either way the account gets the tour's password.
drive_setup() {
    local n
    info "Waiting up to 180 s for Plasma Setup's wizard"
    if ! wait_for_procs 180 plasma-setup kwin_wayland plasma-setup; then
        warn "Plasma Setup's wizard did not start"
    else
        sleep 15
        shot 02-setup-welcome
        # Tab moves the focus to Begin Setup.
        vm_qmp keys:tab wait:1 keys:spc wait:3 >/dev/null 2>&1 || true
        shot 03-setup-1-language
        n="$(next_pages 2)"
        info "Typing the account on the user page"
        # The password field's Show Password button takes a Tab of its own.
        vm_qmp "type:$TOUR_NAME" keys:tab keys:ctrl+a "type:$TOUR_USER" keys:tab \
            "type:$TOUR_PASSWORD" keys:tab keys:tab "type:$TOUR_PASSWORD" wait:2 >/dev/null 2>&1 || true
        # The same page as the last one saved, with the account typed in.
        shot "03-setup-$((n - 1))-account"
        next_pages "$((n + 1))" >/dev/null
        wait_until 30 "id $TOUR_USER" || true
    fi
    if vm_ssh "id $TOUR_USER" >/dev/null 2>&1; then
        info "Plasma Setup created $TOUR_USER"
    else
        warn "Plasma Setup did not create $TOUR_USER; finishing setup over SSH instead"
        finish_setup
        vm_ssh "chfn -f '$TOUR_NAME' $TOUR_USER" >/dev/null 2>&1 || true
    fi
    vm_ssh "printf '%s:%s\n' $TOUR_USER $TOUR_PASSWORD | chpasswd" >/dev/null 2>&1 ||
        warn "Could not set $TOUR_USER's password"
}

# Restart the VM over SSH and wait up to 300 s for SSH to answer from the new boot.
restart_vm() {
    local old new start=$SECONDS
    old="$(vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
    info "Restarting the VM"
    vm_ssh systemctl reboot >/dev/null 2>&1 || true
    sleep 10
    while ((SECONDS - start < 300)); do
        new="$(SSH_TIMEOUT=10 vm_ssh cat /proc/sys/kernel/random/boot_id 2>/dev/null)" || true
        if [[ -n "$new" && "$new" != "$old" ]]; then
            info "The VM restarted; SSH answered $((SECONDS - start)) s after the restart"
            return 0
        fi
        vm_running || break
        sleep 3
    done
    die "the VM did not come back after the restart"
}

# Second boot: wait for Firefox's first-boot install and for the sign-in screen, then sign in by
# typing the password. If no session starts, log in through SDDM's autologin as the boot test does.
sign_in() {
    info "Waiting up to 600 s for Firefox to be installed from Flathub"
    wait_until 600 "test -e /var/lib/orielos/flatpak-setup.done" || warn "Firefox was not installed within 600 s"
    wait_until 120 "pgrep -f sddm-greeter" || warn "The sign-in screen did not start"
    sleep 10
    vm_qmp keys:shift wait:3 >/dev/null 2>&1 || true
    shot 04-sign-in
    vm_qmp "type:$TOUR_PASSWORD" keys:ret >/dev/null 2>&1 || true
    if ! wait_for_procs 90 "$TOUR_USER" plasmashell kwin_wayland; then
        warn "Typing the password did not start a session; logging in through SDDM's autologin"
        vm_ssh "printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' $TOUR_USER >/etc/sddm.conf.d/99-tour-autologin.conf
            systemctl restart sddm" >/dev/null 2>&1 || true
        wait_for_procs 90 "$TOUR_USER" plasmashell kwin_wayland || die "no Plasma session for $TOUR_USER"
    fi
    info "Waiting 20 s for the desktop to draw"
    sleep 20
}

# Run QMP steps, wait, then save a screenshot: press_and_shot <name> <seconds> <step...>
press_and_shot() {
    local name="$1" seconds="$2"
    shift 2
    vm_qmp "$@" >/dev/null 2>&1 || true
    sleep "$seconds"
    shot "$name"
}

# Start an app in the session, wait for a process whose command line has <pattern>, then wait
# <seconds> more for it to draw: open_app <seconds> <pattern> <command...>
open_app() {
    local seconds="$1" pattern="$2"
    shift 2
    in_session "$@" >/dev/null 2>&1 || true
    wait_until 60 "pgrep -u $TOUR_USER -f $pattern" || warn "$pattern did not start"
    sleep "$seconds"
}

# The desktop, one screenshot each, closing windows in between.
desktop_tour() {
    shot 05-desktop
    press_and_shot 06-start-menu 3 keys:meta_l
    press_and_shot 07-start-search 3 type:store
    vm_qmp keys:esc wait:1 keys:esc >/dev/null 2>&1 || true
    sleep 2
    # A setting found from Start, which Enter opens in Settings.
    press_and_shot 07-start-search-setting 3 keys:meta_l wait:2 "type:dark mode"
    press_and_shot 07-start-search-setting-opened 10 keys:ret
    close_apps

    press_and_shot 08-files 8 keys:meta_l+e
    close_apps

    open_app 15 plasma-discover plasma-discover
    shot 09-store
    close_apps

    press_and_shot 10-process-manager 10 keys:ctrl+shift+esc
    close_apps

    press_and_shot 11-settings 10 keys:meta_l+i
    # OrielOS's own pages, opened in the same window.
    in_session orielos-settings accent >/dev/null 2>&1 || warn "Could not open the Accent colour page"
    sleep 5
    shot 11-settings-accent
    in_session orielos-settings accessories >/dev/null 2>&1 || warn "Could not open the Accessory apps page"
    sleep 5
    shot 11-settings-accessories
    # Taskbar reads its settings from the running desktop.
    in_session orielos-settings taskbar >/dev/null 2>&1 || warn "Could not open the Taskbar page"
    sleep 5
    shot 11-settings-taskbar
    # Device security checks the running system; the VM has no IOMMU.
    in_session orielos-settings device-security >/dev/null 2>&1 || warn "Could not open the Device security page"
    sleep 8
    shot 11-settings-security
    in_session orielos-settings power-mode >/dev/null 2>&1 || warn "Could not open the Power mode page"
    sleep 5
    shot 11-settings-power-mode
    close_apps

    open_app 15 firefox flatpak run org.mozilla.firefox
    shot 12-firefox
    close_apps

    press_and_shot 13-screenshot 5 keys:meta_l+shift+s
    vm_qmp keys:esc >/dev/null 2>&1 || true
    close_apps

    open_app 3 dolphin dolphin
    open_app 3 systemsettings systemsettings
    open_app 10 firefox flatpak run org.mozilla.firefox
    press_and_shot 14-overview 4 keys:meta_l+tab
    vm_qmp keys:esc >/dev/null 2>&1 || true
    close_apps

    # The lock screen while idle, then once a key wakes the password prompt.
    press_and_shot 15-lock-screen 6 keys:meta_l+l
    press_and_shot 16-lock-screen-unlocking 3 keys:shift
    vm_ssh loginctl unlock-sessions >/dev/null 2>&1 || true
    sleep 5

    in_session plasma-apply-colorscheme OrielOSDark >/dev/null 2>&1 || warn "Could not switch to the dark colour scheme"
    sleep 10
    press_and_shot 17-desktop-dark 3 keys:meta_l
    vm_qmp keys:esc >/dev/null 2>&1 || true
    press_and_shot 18-lock-screen-dark 6 keys:meta_l+l
    vm_ssh loginctl unlock-sessions >/dev/null 2>&1 || true
}

# Make 00-contact-sheet.png from the screenshots, with Pillow or ImageMagick.
contact_sheet() {
    local shots=()
    mapfile -t shots < <(find "$RESULTS" -maxdepth 1 -name '[0-9][0-9]-*.png' ! -name '00-*' | sort)
    [[ "${#shots[@]}" -gt 0 ]] || return 0
    if python3 -c 'import PIL' >/dev/null 2>&1; then
        python3 -I - "$RESULTS/00-contact-sheet.png" "${shots[@]}" <<'PY' || warn "Could not make the contact sheet"
import os, sys
from PIL import Image, ImageDraw

cols, w, h, label = 4, 480, 270, 24
names = sys.argv[2:]
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + label)), "white")
draw = ImageDraw.Draw(sheet)
for i, name in enumerate(names):
    x, y = (i % cols) * w, (i // cols) * (h + label)
    im = Image.open(name).convert("RGB")
    im.thumbnail((w - 8, h - 8))
    sheet.paste(im, (x + 4, y + 4))
    draw.text((x + 6, y + h), os.path.basename(name), fill="black")
sheet.save(sys.argv[1])
PY
    elif command -v montage >/dev/null 2>&1; then
        montage -label '%t' -geometry 480x270+4+4 -tile 4x "${shots[@]}" "$RESULTS/00-contact-sheet.png" ||
            warn "Could not make the contact sheet"
    else
        info "Neither Pillow nor ImageMagick is installed, so there is no contact sheet"
        return 0
    fi
    if [[ -s "$RESULTS/00-contact-sheet.png" ]]; then info "Saved 00-contact-sheet.png"; fi
}

main() {
    local original=("$@") run_id tag
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --image)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                IMAGE="$2"
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

    if [[ "$EUID" -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || die "run this script as root (sudo is not installed)"
        exec sudo "${BASH_SOURCE[0]}" "${original[@]}"
    fi
    check_host

    tag="latest"
    if [[ "${IMAGE##*/}" == *:* ]]; then tag="${IMAGE##*:}"; fi
    run_id="$(printf '%s-%s' "$tag" "$(date -u +%Y%m%dT%H%M%SZ)" | tr -c 'A-Za-z0-9._\n-' '_')"
    WORK="$VM_ROOT/tour-$run_id"
    RESULTS="$ROOT/tests/results/tour-$run_id"
    mkdir -p "$WORK" "$RESULTS"
    SUMMARY="$RESULTS/summary.txt"
    : >"$SUMMARY"
    trap cleanup EXIT
    info "Run $run_id; screenshots in $RESULTS"
    podman image exists "$IMAGE" || die "image $IMAGE does not exist (build it with tools/build-image.sh)"

    # Boot as a PC does, with the splash screen, at full HD; finish_setup creates the tour's user.
    INSTALL_KARGS=()
    VM_SCREEN="1920x1080"
    TEST_USER="$TOUR_USER"
    SSH_WAIT=180
    setup_ssh
    install_image
    start_vm

    capture_splash
    wait_for_ssh || die "SSH did not answer on the first boot"
    drive_setup
    restart_vm
    sign_in
    desktop_tour
    contact_sheet
    info "Saved $(find "$RESULTS" -maxdepth 1 -name "[0-9][0-9]-*.png" | wc -l) images in $RESULTS"
}

main "$@"

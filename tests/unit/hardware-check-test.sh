#!/usr/bin/env bash
# Unit tests for the hardware check: image/system/usr/libexec/orielos/hardware-check (which lists
# the Wi-Fi, Bluetooth, network, sound and camera devices without a driver or firmware),
# firmware-log (which copies the kernel log's firmware failures for it) and hardware-check-notify
# (which tells the user once per device). It builds a scratch sysfs tree with recorded hwdata
# entries and a recorded kernel log, and uses stand-ins for notify-send, so it needs no root or VM.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/hardware-check-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIBEXEC="$ROOT/image/system/usr/libexec/orielos"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0

pass() {
    printf 'PASS  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/      /'; fi
    FAILED=$((FAILED + 1))
}

check() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT"; fi
}

SYS="$WORK/sys"
HW="$WORK/hwdata"
FW="$WORK/run/firmware-failures"

# pci_dev <address> <class> <vendor> <device> [driver] [net]
pci_dev() {
    local d="$SYS/bus/pci/devices/$1"
    mkdir -p "$d"
    printf '0x%s\n' "$2" >"$d/class"
    printf '0x%s\n' "$3" >"$d/vendor"
    printf '0x%s\n' "$4" >"$d/device"
    if [[ -n "${5:-}" ]]; then
        mkdir -p "$SYS/bus/pci/drivers/$5"
        ln -s "../../../bus/pci/drivers/$5" "$d/driver"
    fi
    if [[ -n "${6:-}" ]]; then mkdir -p "$d/net/$6"; fi
}

# usb_dev <address> <device class> <vendor> <product> <interface class+subclass+protocol> [driver]
usb_dev() {
    local d="$SYS/bus/usb/devices/$1" i
    mkdir -p "$d"
    printf '%s\n' "$2" >"$d/bDeviceClass"
    printf '%s\n' "$3" >"$d/idVendor"
    printf '%s\n' "$4" >"$d/idProduct"
    i="$d/$1:1.0"
    mkdir -p "$i"
    printf '%s\n' "${5:0:2}" >"$i/bInterfaceClass"
    printf '%s\n' "${5:2:2}" >"$i/bInterfaceSubClass"
    printf '%s\n' "${5:4:2}" >"$i/bInterfaceProtocol"
    if [[ -n "${6:-}" ]]; then
        mkdir -p "$SYS/bus/usb/drivers/$6"
        ln -s "../../../../bus/usb/drivers/$6" "$i/driver"
    fi
}

# A laptop like the test laptop: every device works. Intel Wi-Fi (iwlwifi, with the usual
# firmware versions it tried first), Realtek Ethernet, HD audio, Intel Bluetooth over USB, a
# webcam, a mouse receiver, and a USB hub.
setup() {
    rm -rf "${WORK:?}/sys" "${WORK:?}/hwdata" "${WORK:?}/run" "${WORK:?}/state"
    mkdir -p "$SYS/bus/pci/devices" "$SYS/bus/usb/devices" "$HW" "$WORK/run"
    cat >"$HW/pci.ids" <<'IDS'
# Recorded entries from hwdata's pci.ids
8086  Intel Corporation
	51f1  Raptor Lake PCH CNVi WiFi
	51ca  Raptor Lake-P/U/H cAVS
10ec  Realtek Semiconductor Co., Ltd.
	8168  RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller
14e4  Broadcom Inc. and subsidiaries
	43a0  BCM4360 802.11ac Dual Band Wireless Network Adapter
		106b 0117  Apple MacBook Pro
C 02  Network controller
IDS
    cat >"$HW/usb.ids" <<'IDS'
# Recorded entries from hwdata's usb.ids
046d  Logitech, Inc.
	c52b  Unifying Receiver
	0825  Webcam C270
0bda  Realtek Semiconductor Corp.
	8813  RTL8814AU 802.11a/b/g/n/ac Wireless Adapter
8087  Intel Corp.
	0033  AX211 Bluetooth
IDS
    pci_dev 0000:00:14.3 028000 8086 51f1 iwlwifi wlo1
    pci_dev 0000:03:00.0 020000 10ec 8168 r8169 enp3s0
    pci_dev 0000:00:1f.3 040380 8086 51ca snd_hda_intel
    pci_dev 0000:00:02.0 030000 8086 a7a0 i915
    pci_dev 0000:00:1f.4 0c0500 8086 51a3
    usb_dev 1-10 e0 8087 0033 e00101 btusb
    usb_dev 1-5 ef 046d 0825 0e0100 uvcvideo
    usb_dev 1-3 00 046d c52b 030101 usbhid
    usb_dev 1-1 09 05e3 0610 090000 hub
    mkdir -p "$SYS/bus/usb/devices/usb1"
    printf '8086 51f1\n' >/dev/null
    cat >"$WORK/kernel.log" <<'LOG'
iwlwifi 0000:00:14.3: Direct firmware load for iwlwifi-so-a0-gf-a0-89.ucode failed with error -2
iwlwifi 0000:00:14.3: Direct firmware load for iwlwifi-so-a0-gf-a0-88.ucode failed with error -2
iwlwifi 0000:00:14.3: loaded firmware version 86.fb5c9aeb.0 so-a0-gf-a0-86.ucode op_mode iwlmvm
r8169 0000:03:00.0 enp3s0: Link is Down
LOG
}

run_check() {
    RC=0
    OUT="$(ORIELOS_SYSFS="$SYS" ORIELOS_HWDATA="$HW" ORIELOS_FIRMWARE_FAILURES="$FW" "$LIBEXEC/hardware-check" "$@" 2>&1)" || RC=$?
}

run_log() {
    RC=0
    OUT="$(ORIELOS_KERNEL_LOG="$WORK/kernel.log" ORIELOS_RUN_DIR="$WORK/run" "$LIBEXEC/firmware-log" 2>&1)" || RC=$?
}

has_line() { grep -qxF "$1" <<<"$OUT"; }

setup
run_log
check "firmware-log runs" test "$RC" -eq 0
OUT="$(cat "$FW")"
check "and notes each failure once, as driver, device and file" test "$OUT" == $'iwlwifi\t0000:00:14.3\tiwlwifi-so-a0-gf-a0-89.ucode\niwlwifi\t0000:00:14.3\tiwlwifi-so-a0-gf-a0-88.ucode'
check "the file is readable by everyone" test "$(stat -c %a "$FW")" == 644
run_check
check "a PC where everything works reports nothing" test "$RC" -eq 0 -a -z "$OUT"

setup
pci_dev 0000:04:00.0 028000 14e4 43a0
run_check
check "a Wi-Fi card without a driver is reported, named from pci.ids" has_line $'wifi\tpci\t0000:04:00.0\t14e4:43a0\tBroadcom Inc. and subsidiaries BCM4360 802.11ac Dual Band Wireless Network Adapter\tno-driver\t'
check "and nothing else is" test "$(wc -l <<<"$OUT")" -eq 1

setup
usb_dev 1-2 00 0bda 8813 ffffff
run_check
check "a vendor-specific USB Wi-Fi adapter without a driver is reported by its name" has_line $'wifi\tusb\t1-2\t0bda:8813\tRealtek Semiconductor Corp. RTL8814AU 802.11a/b/g/n/ac Wireless Adapter\tno-driver\t'

setup
rm "$SYS/bus/usb/devices/1-10/1-10:1.0/driver"
run_check
check "a Bluetooth adapter without a driver is reported" has_line $'bluetooth\tusb\t1-10\t8087:0033\tIntel Corp. AX211 Bluetooth\tno-driver\t'

setup
rm "$SYS/bus/pci/devices/0000:00:1f.3/driver"
rm "$SYS/bus/usb/devices/1-5/1-5:1.0/driver"
run_check
check "sound and camera devices without drivers are reported" test "$(cut -f1 <<<"$OUT" | xargs)" == "sound camera"

setup
usb_dev 1-4 00 1234 5678 ffffff
printf 'Acme\n' >"$SYS/bus/usb/devices/1-4/manufacturer"
printf 'RGB Controller\n' >"$SYS/bus/usb/devices/1-4/product"
run_check
check "a vendor-specific USB device that isn't a network device isn't reported" test -z "$OUT"

setup
usb_dev 1-6 00 1234 9999 ffffff
printf 'Acme\n' >"$SYS/bus/usb/devices/1-6/manufacturer"
printf '802.11n WLAN Adapter\n' >"$SYS/bus/usb/devices/1-6/product"
run_check
check "a device hwdata doesn't know is named from its own strings" has_line $'wifi\tusb\t1-6\t1234:9999\tAcme 802.11n WLAN Adapter\tno-driver\t'

setup
usb_dev 1-7 ef 5986 217c 0e0100
printf 'Bison\n' >"$SYS/bus/usb/devices/1-7/manufacturer"
printf 'HD Webcam\n' >"$SYS/bus/usb/devices/1-7/product"
printf '5986  Bison Electronics Inc.\n' >>"$HW/usb.ids"
run_check
check "a model hwdata doesn't know takes the device's own name after the maker's" has_line $'camera\tusb\t1-7\t5986:217c\tBison Electronics Inc. HD Webcam\tno-driver\t'

setup
run_log
rm -r "$SYS/bus/pci/devices/0000:00:14.3/net"
run_check
check "a Wi-Fi card whose driver loaded no firmware is reported, with the first file it missed" has_line $'wifi\tpci\t0000:00:14.3\t8086:51f1\tIntel Corporation Raptor Lake PCH CNVi WiFi\tno-firmware\tiwlwifi-so-a0-gf-a0-89.ucode'

setup
rm -r "$SYS/bus/pci/devices/0000:00:14.3/net"
run_check
check "without a firmware failure, a card without an interface yet isn't reported" test -z "$OUT"

setup
run_check extra
check "an argument is refused with exit 2" test "$RC" -eq 2

# The notification: once per device, with the device's name.
cat >"$WORK/notify-send" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$WORK/notified"
SH
chmod +x "$WORK/notify-send"
run_notify() {
    RC=0
    OUT="$(XDG_STATE_HOME="$WORK/state" ORIELOS_HARDWARE_CHECK="$WORK/check" ORIELOS_NOTIFY_SEND="$WORK/notify-send" \
        ORIELOS_FIRMWARE_FAILURES="$FW" ORIELOS_WAIT_SECONDS=0 ORIELOS_UID="${NOTIFY_UID:-1000}" "$LIBEXEC/hardware-check-notify" 2>&1)" || RC=$?
}
setup
run_log
rm -f "$WORK/notified"
cat >"$WORK/check" <<'SH'
#!/usr/bin/env bash
printf 'wifi\tpci\t0000:04:00.0\t14e4:43a0\tBroadcom BCM4360\tno-driver\t\n'
printf 'bluetooth\tusb\t1-10\t8087:0033\tIntel AX211 Bluetooth\tno-firmware\tintel/ibt-0040-0041.sfi\n'
SH
chmod +x "$WORK/check"
run_notify
check "the notifier runs" test "$RC" -eq 0
OUT="$(cat "$WORK/notified" 2>/dev/null || true)"
check "and says the Wi-Fi card has no driver, by name" grep -q 'Your Wi-Fi card has no driver OrielOS has no driver for the Broadcom BCM4360' <<<"$OUT"
check "and that the Bluetooth adapter is missing its firmware" grep -q 'Your Bluetooth adapter is missing its firmware' <<<"$OUT"
check "with a Learn more button" grep -q 'action=learn=Learn more' <<<"$OUT"
rm -f "$WORK/notified"
run_notify
check "the same devices aren't mentioned again" test ! -e "$WORK/notified"

rm -rf "$WORK/state"
NOTIFY_UID=500 run_notify
check "system accounts, such as Plasma Setup's, aren't told anything" test ! -e "$WORK/notified"

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]

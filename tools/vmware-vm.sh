#!/usr/bin/env bash
# Creates, boot-checks and deletes a VMware Workstation virtual machine that runs an OrielOS
# VMDK from tools/make-vm-disk.sh. Runs inside WSL2 on a Windows host with VMware Workstation
# installed, and drives Workstation's vmcli.exe and vmrun.exe through Windows interop.
#
# Usage: tools/vmware-vm.sh create --vmdk FILE --dir WINDOWS_DIR [--name NAME]
#        tools/vmware-vm.sh boot-check --vmx FILE [--timeout S]
#        tools/vmware-vm.sh delete --vmx FILE
#        tools/vmware-vm.sh --help
#   create       copies the VMDK into WINDOWS_DIR\NAME (default name: the VMDK's file name) and
#                creates a VM with UEFI and Secure Boot, 6 GB of memory, 4 CPUs, the disk on an
#                NVMe controller, NAT networking, a sound card, and the first serial port
#                writing to NAME-serial.log next to the .vmx file. Prints the .vmx path.
#   boot-check   starts the VM without a window, waits up to S seconds (default 600) for the
#                serial log to show Plasma Setup or SDDM and graphical.target, prints PASS or
#                FAIL and stops the VM. Needs a disk made with make-vm-disk.sh --serial-console.
#   delete       stops the VM if it runs and deletes it and its files.
# WINDOWS_DIR and FILE may be Windows paths (C:\...) or WSL paths (/mnt/c/...). VMware only runs
# VMs from the Windows file system, so WINDOWS_DIR must be on it.
set -Eeuo pipefail

VMWARE_DIR="/mnt/c/Program Files (x86)/VMware/VMware Workstation"
VMCLI="$VMWARE_DIR/vmcli.exe"
VMRUN="$VMWARE_DIR/vmrun.exe"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

step() { printf '==> %s\n' "$1"; }

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Check that this is WSL with VMware Workstation's tools on the Windows side.
check_host() {
    grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null ||
        die "this tool runs inside WSL2 on Windows with VMware Workstation installed"
    command -v wslpath >/dev/null 2>&1 || die "wslpath is missing; this tool needs WSL2"
    [[ -x "$VMCLI" && -x "$VMRUN" ]] ||
        die "VMware Workstation's command-line tools are not in $VMWARE_DIR; install VMware Workstation"
}

# Print a path as Windows (C:\...) or WSL (/mnt/c/...): win_path PATH, wsl_path PATH
win_path() {
    if [[ "$1" == /* ]]; then wslpath -w "$1"; else printf '%s\n' "$1"; fi
}
wsl_path() {
    if [[ "$1" == /* ]]; then printf '%s\n' "$1"; else wslpath -u "$1"; fi
}

# Run a Windows tool from a Windows folder, so it does not start in a WSL path, and drop the
# carriage returns from its output.
run_exe() {
    (cd /mnt/c && "$@") | tr -d '\r'
    return "${PIPESTATUS[0]}"
}

# Print a serial log without colour codes or unprintable bytes.
clean_log() {
    sed 's/\x1b\[[0-9;?]*[A-Za-z]//g' "$1" | tr -cd '\11\12\40-\176'
}

vm_is_running() {
    run_exe "$VMRUN" -T ws list | grep -Fqi -- "$1"
}

create() {
    local vmdk="" dir="" name="" folder vmx serial key
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmdk | --dir | --name)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --vmdk) vmdk="$2" ;;
                    --dir) dir="$2" ;;
                    --name) name="$2" ;;
                esac
                shift 2
                ;;
            *) die "unknown option for create: $1" ;;
        esac
    done
    [[ -n "$vmdk" && -n "$dir" ]] || die "create needs --vmdk FILE and --dir WINDOWS_DIR"
    vmdk="$(wsl_path "$vmdk")"
    [[ -r "$vmdk" ]] || die "cannot read $vmdk"
    if [[ -z "$name" ]]; then
        name="${vmdk##*/}"
        name="${name%.vmdk}"
    fi
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "--name may only use letters, digits, dots, dashes and underscores"
    folder="$(wsl_path "$dir")/$name"
    [[ "$folder" == /mnt/[a-z]/* ]] || die "--dir must be on the Windows file system, for example C:\\VMs or /mnt/c/VMs"
    [[ ! -e "$folder/$name.vmx" ]] || die "$folder/$name.vmx already exists; delete it first"
    mkdir -p "$folder"

    step "Creating the VM $name in $(win_path "$folder")"
    run_exe "$VMCLI" VM Create -n "$name" -d "$(win_path "$folder")" -g fedora-64 >/dev/null ||
        die "vmcli could not create the VM"
    vmx="$(win_path "$folder/$name.vmx")"
    serial="$(win_path "$folder/$name-serial.log")"
    # vmcli creates an empty disk with the VM's name; the OrielOS disk replaces it.
    step "Copying $vmdk ($(du -h "$vmdk" | cut -f1))"
    cp -f "$vmdk" "$folder/$name.vmdk"

    local -a entries=(
        displayName "$name"
        # UEFI with Secure Boot. Shim is signed by Microsoft's UEFI CA, which VMware trusts.
        firmware efi
        uefi.secureBoot.enabled TRUE
        memsize 6144
        numvcpus 4
        # The disk on an NVMe controller, as on most current PCs.
        nvme0.present TRUE
        nvme0:0.present TRUE
        nvme0:0.fileName "$name.vmdk"
        ethernet0.present TRUE
        ethernet0.connectionType nat
        ethernet0.virtualDev vmxnet3
        ethernet0.addressType generated
        sound.present TRUE
        sound.virtualDev hdaudio
        sound.autoDetect TRUE
        sound.fileName -1
        usb.present TRUE
        usb_xhci.present TRUE
        # The console goes to a file, for boot-check.
        serial0.present TRUE
        serial0.fileType file
        serial0.fileName "$serial"
        serial0.yieldOnMsrRead TRUE
    )
    for ((key = 0; key < ${#entries[@]}; key += 2)); do
        run_exe "$VMCLI" "$vmx" ConfigParams SetEntry "${entries[key]}" "${entries[key + 1]}" >/dev/null ||
            die "vmcli could not set ${entries[key]}"
    done
    step "Created $vmx"
    printf '%s\n' "$vmx"
}

boot_check() {
    local vmx="" timeout=600 serial start text started="" passed=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmx | --timeout)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                case "$1" in
                    --vmx) vmx="$2" ;;
                    --timeout) timeout="$2" ;;
                esac
                shift 2
                ;;
            *) die "unknown option for boot-check: $1" ;;
        esac
    done
    [[ -n "$vmx" ]] || die "boot-check needs --vmx FILE"
    [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -gt 0 ]] || die "--timeout needs a number of seconds"
    [[ -r "$(wsl_path "$vmx")" ]] || die "cannot read $vmx"
    vmx="$(win_path "$vmx")"
    serial="$(wsl_path "$vmx")"
    serial="${serial%.vmx}-serial.log"
    if vm_is_running "$vmx"; then die "the VM is already running; stop it first"; fi

    rm -f "$serial"
    step "Starting $vmx without a window; waiting up to $timeout s"
    run_exe "$VMRUN" -T ws start "$vmx" nogui || die "vmrun could not start the VM"
    start=$SECONDS
    while ((SECONDS - start < timeout)); do
        if [[ -r "$serial" ]]; then
            text="$(clean_log "$serial")"
            if [[ -z "$started" && "$text" == *"Linux version "* ]]; then
                started=1
                printf 'The kernel started after %s s\n' "$((SECONDS - start))"
            fi
            if [[ ("$text" == *"Finished plasma-setup.service"* || "$text" == *"Started sddm.service"*) &&
                "$text" == *"Reached target graphical.target"* ]]; then
                passed=1
                break
            fi
        fi
        vm_is_running "$vmx" || break
        sleep 5
    done

    if [[ -r "$serial" ]]; then
        text="$(clean_log "$serial")"
        grep -m1 -o 'secureboot: Secure boot [a-z]*' <<<"$text" || true
        grep -m1 -E 'Finished plasma-setup\.service' <<<"$text" || true
        grep -m1 -E 'Started sddm\.service' <<<"$text" || true
    fi
    step "Stopping the VM"
    run_exe "$VMRUN" -T ws stop "$vmx" hard >/dev/null 2>&1 || true
    if [[ "$passed" -eq 1 ]]; then
        printf 'PASS  the VM reached Plasma Setup or SDDM and graphical.target after %s s (serial log: %s)\n' \
            "$((SECONDS - start))" "$(win_path "$serial")"
        return 0
    fi
    if [[ -z "$started" ]]; then
        printf 'FAIL  no kernel messages on the serial port within %s s; was the disk made with make-vm-disk.sh --serial-console?\n' "$timeout"
    else
        printf 'FAIL  the VM did not reach Plasma Setup or SDDM and graphical.target within %s s (serial log: %s)\n' \
            "$timeout" "$(win_path "$serial")"
    fi
    return 1
}

delete() {
    local vmx="" folder
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vmx)
                [[ $# -ge 2 ]] || die "$1 needs a value"
                vmx="$2"
                shift 2
                ;;
            *) die "unknown option for delete: $1" ;;
        esac
    done
    [[ -n "$vmx" ]] || die "delete needs --vmx FILE"
    [[ -r "$(wsl_path "$vmx")" ]] || die "cannot read $vmx"
    vmx="$(win_path "$vmx")"
    folder="$(wsl_path "$vmx")"
    folder="${folder%/*}"
    if vm_is_running "$vmx"; then
        step "Stopping the VM"
        run_exe "$VMRUN" -T ws stop "$vmx" hard >/dev/null || true
    fi
    step "Deleting $vmx"
    run_exe "$VMRUN" -T ws deleteVM "$vmx" || die "vmrun could not delete the VM"
    # The serial log is not part of the VM, so deleteVM leaves it behind.
    rm -f "${folder:?}"/*-serial.log
    rmdir "$folder" 2>/dev/null || true
}

main() {
    local command="${1:-}"
    case "$command" in
        --help | -h)
            usage
            exit 0
            ;;
        create | boot-check | delete) shift ;;
        *)
            usage >&2
            die "unknown command: ${command:-none}"
            ;;
    esac
    check_host
    case "$command" in
        create) create "$@" ;;
        boot-check) boot_check "$@" ;;
        delete) delete "$@" ;;
    esac
}

main "$@"

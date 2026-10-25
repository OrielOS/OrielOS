#!/usr/bin/env bash
# Fails the build unless every boot will meet the anti-cheat requirements: the kernel arguments
# for lockdown and the IOMMU, kexec disabled and not installed, the BPF LSM built into the
# kernel's default list and hibernation switched off.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

kargs_file=/usr/lib/bootc/kargs.d/20-orielos-anticheat.toml
required_kargs=(lockdown=integrity intel_iommu=on iommu.passthrough=0)

errors=()
fail() { errors+=("$1"); }

# Every kargs.d file has a single kargs line; the anti-cheat one has every required argument.
check_kargs() {
    local f
    for f in /usr/lib/bootc/kargs.d/*.toml; do
        if [[ "$(grep -c '^kargs = \[' "$f")" -ne 1 ]]; then
            fail "$f must have exactly one 'kargs = [...]' line"
        fi
    done
    if [[ ! -r "$kargs_file" ]]; then
        fail "$kargs_file is missing"
        return
    fi
    local arg
    for arg in "${required_kargs[@]}"; do
        grep -q "\"$arg\"" "$kargs_file" || fail "$kargs_file does not set $arg"
    done
    if grep -q '"lsm=' /usr/lib/bootc/kargs.d/*.toml; then
        fail "a kargs.d file sets lsm=, which would replace the kernel's default list"
    fi
}

check_kexec() {
    if rpm -q kexec-tools >/dev/null 2>&1; then
        fail "kexec-tools is installed; 15-server-defaults.sh removes it"
    fi
    if ! grep -qx 'kernel.kexec_load_disabled = 1' /usr/lib/sysctl.d/60-orielos-kexec.conf 2>/dev/null; then
        fail "/usr/lib/sysctl.d/60-orielos-kexec.conf does not set kernel.kexec_load_disabled = 1"
    fi
}

# The kernel's built-in default LSM list must include bpf, so no lsm= argument is needed.
check_bpf_lsm() {
    local kver config lsm
    kver="$(ls /usr/lib/modules)"
    config="/usr/lib/modules/$kver/config"
    if [[ ! -r "$config" ]]; then
        fail "$config is missing"
        return
    fi
    grep -qx 'CONFIG_BPF_LSM=y' "$config" || fail "the kernel $kver is not built with CONFIG_BPF_LSM=y"
    lsm="$(sed -n 's/^CONFIG_LSM="\(.*\)"$/\1/p' "$config")"
    if [[ ",$lsm," != *,bpf,* ]]; then
        fail "the kernel $kver's default LSM list (${lsm:-none}) does not include bpf"
    fi
    printf 'kernel:         %s\n' "$kver"
    printf 'default LSMs:   %s\n' "$lsm"
}

check_hibernation() {
    local conf=/usr/lib/systemd/sleep.conf.d/50-orielos.conf key
    for key in AllowHibernation AllowSuspendThenHibernate AllowHybridSleep; do
        grep -qx "$key=no" "$conf" 2>/dev/null || fail "$conf does not set $key=no"
    done
}

main() {
    check_kargs
    check_kexec
    check_bpf_lsm
    check_hibernation
    if [[ "${#errors[@]}" -gt 0 ]]; then
        printf 'error: %s\n' "${errors[@]}" >&2
        exit 1
    fi
    printf 'kernel args:    %s\n' "${required_kargs[*]}"
    printf 'kexec:          disabled at boot, kexec-tools not installed\n'
    printf 'hibernation:    not offered\n'
}

main "$@"

#!/usr/bin/env bash
# Removes what fedora-bootc ships for servers and a desktop does not need, and switches off
# automatic update reboots and the SSH server. Installs nothing. The same units are disabled
# in system/usr/lib/systemd/system-preset/80-orielos.preset, so a preset run keeps them off.
# Also masks the EFI system partition automount, which can't work on the read-only root.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

remove=(
    # Crash dumps through kexec; kexec will be disabled at boot.
    kexec-tools kdump-utils makedumpfile
    # Cloud instance set-up: metadata network configuration, Azure's agent rules and
    # growing the root partition on first boot.
    NetworkManager-cloud-setup WALinuxAgent-udev cloud-utils-growpart
    # Server diagnostics: support reports and their S3 upload libraries, and the real-time
    # CPU stall monitor.
    sos python3-boto3 python3-botocore python3-s3transfer stalld
    # Emulators for running containers built for other CPU architectures.
    'qemu-user-static*'
    # NFS server and disk quotas. Mounting NFS shares still works through nfs-client-utils.
    nfs-utils quota quota-nls
    # The static iptables rules service; firewalld manages the firewall instead.
    iptables-services
    # Server console banners that show the machine's addresses and SSH keys at the text login.
    console-login-helper-messages console-login-helper-messages-issuegen console-login-helper-messages-profile
)

dnf -y remove "${remove[@]}"

# Updates are staged and the user is asked before restarting, so no automatic update reboots.
# openssh-server stays installed: systemd's vsock SSH socket uses sshd without sshd.service.
systemctl disable bootc-fetch-apply-updates.timer sshd.service

# systemd's GPT generator adds an automount for the EFI system partition at /efi, which doesn't
# exist and can't be made on the read-only root, so it fails at every boot and leaves the system
# "degraded". Nothing needs it there: bootupd and the boot menu's flags mount the partition
# themselves. The mask is in /etc because generated units take precedence over /usr/lib.
systemctl mask efi.automount
if [[ "$(readlink /etc/systemd/system/efi.automount)" != /dev/null ]]; then
    printf 'error: efi.automount is not masked\n' >&2
    exit 1
fi

dnf clean all

#!/usr/bin/env bash
# Disables every repository that does not come from Fedora itself, and switches off Fedora's
# package-count reporting ("countme"): no repository sends the count flag, and rpm-ostree's
# weekly count timer is disabled. The timer is disabled in
# system/usr/lib/systemd/system-preset/80-orielos.preset too, so a preset run keeps it off.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

for f in /etc/yum.repos.d/*.repo; do
    case "${f##*/}" in
        # Fedora's own files: fedora*.repo (including fedora-updates*) and fedora-cisco-openh264.repo.
        fedora*.repo) continue ;;
    esac
    mapfile -t ids < <(sed -n 's/^\[\(.*\)\]$/\1/p' "$f")
    for id in "${ids[@]}"; do
        dnf config-manager setopt "$id.enabled=0"
    done
done

# Fedora's repositories set countme=1, which adds a weekly anonymous count to metadata requests.
# The files are changed rather than overridden, so the configuration says what it does.
sed -i 's/^countme=1[[:space:]]*$/countme=0/' /etc/yum.repos.d/*.repo
systemctl disable rpm-ostree-countme.timer
if grep -l '^countme=1' /etc/yum.repos.d/*.repo; then
    printf 'error: the repositories above still set countme=1\n' >&2
    exit 1
fi
if [[ "$(systemctl is-enabled rpm-ostree-countme.timer 2>/dev/null)" == "enabled" ]]; then
    printf 'error: rpm-ostree-countme.timer is still enabled\n' >&2
    exit 1
fi

dnf repolist --enabled

#!/usr/bin/env bash
# Disables every repository that does not come from Fedora itself.
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

dnf repolist --enabled

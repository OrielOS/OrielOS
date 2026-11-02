#!/usr/bin/env bash
# Measures OrielOS's boot and idle numbers on the computer it runs on, as OrielOS's performance
# targets define them: the boot loader to the sign-in screen, signing in to a usable desktop, and
# memory in use after signing in, once the desktop has been idle for two minutes. Run it in a
# terminal on the desktop, soon after signing in, without other apps open.
#
# Usage: tests/benchmark/system.sh [--no-wait]
#   --no-wait  measure memory straight away instead of after two idle minutes
set -Eeuo pipefail

wait=120
[[ "${1:-}" == --no-wait ]] && wait=0

# From the boot loader handing over (loader + kernel + initrd + userspace) to graphical.target,
# which is when the sign-in screen is up.
boot="$(systemd-analyze time 2>/dev/null | sed -n 's/.*graphical.target reached after \([0-9.]*\)s.*/\1/p')"
total="$(systemd-analyze time 2>/dev/null | sed -n '1s/.*= \([0-9.]*min \)\{0,1\}\([0-9.]*\)s.*/\2/p')"
printf 'Boot loader to sign-in screen: %s s (graphical.target)\n' "${boot:-unknown}"
printf 'Whole start-up as systemd counts it: %s s\n' "${total:-unknown}"

# Signing in to a usable desktop: from the session starting to Plasma's shell being ready, from
# this boot's journal.
login="$(journalctl --user -b -o short-unix --no-pager 2>/dev/null | awk '
    /Started plasma-ksmserver.service|Starting plasma-plasmashell.service/ && !start { start = $1 }
    /Started plasma-plasmashell.service/ && !shell { shell = $1 }
    END { if (start && shell) printf "%.1f", shell - start }')"
printf 'Sign-in to desktop: %s s (Plasma session start to the shell)\n' "${login:-unknown}"

if ((wait > 0)); then
    printf 'Waiting %d s with the desktop idle before measuring memory...\n' "$wait"
    sleep "$wait"
fi
used="$(free -m | awk '/^Mem:/ { print $3 }')"
printf 'Memory in use after signing in: %s MiB\n' "$used"

#!/usr/bin/env bash
# Unit tests for image/system/usr/libexec/orielos/firewall-watch, which asks whether to let other
# computers connect to an app the first time it listens on a port the firewall blocks. Each case
# runs it once with --dry-run against stub ss and firewall-cmd commands and a made-up home folder.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/firewall-watch-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/image/system/usr/libexec/orielos/firewall-watch"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""

check() {
    local name="$1"
    shift
    if "$@"; then
        printf 'PASS  %s\n' "$name"
        PASSED=$((PASSED + 1))
    else
        printf 'FAIL  %s\n      output: %s\n' "$name" "$OUT"
        FAILED=$((FAILED + 1))
    fi
}

# Stub commands: ss prints $WORK/ss.txt; firewall-cmd answers for the zone "home", which allows
# 8000-8010/tcp and the ssh service (22/tcp), unless $WORK/no-firewall exists.
setup() {
    rm -rf "${WORK:?}"/*
    mkdir -p "$WORK/bin" "$WORK/home/.local/share/applications"
    cat >"$WORK/bin/ss" <<'STUB'
#!/usr/bin/env bash
cat "$STUB_DIR/ss.txt"
STUB
    cat >"$WORK/bin/firewall-cmd" <<'STUB'
#!/usr/bin/env bash
[[ -e "$STUB_DIR/no-firewall" ]] && exit 252
case "$*" in
    --get-active-zones) printf 'home\n  interfaces: wlo1\n' ;;
    "--zone=home --list-ports") echo "8000-8010/tcp" ;;
    "--zone=home --list-services") echo "ssh" ;;
    --info-service=ssh) printf 'ssh\n  ports: 22/tcp\n  protocols:\n' ;;
    *) exit 1 ;;
esac
STUB
    chmod +x "$WORK/bin/ss" "$WORK/bin/firewall-cmd"
    : >"$WORK/ss.txt"
}

listen() {
    printf 'LISTEN 0 128 %s *:* users:(("%s",pid=%s,fd=3))\n' "$1" "$2" "${3:-100}" >>"$WORK/ss.txt"
}

run() {
    OUT="$(STUB_DIR="$WORK" PATH="$WORK/bin:$PATH" HOME="$WORK/home" XDG_STATE_HOME="$WORK/home/.local/state" \
        XDG_DATA_HOME="$WORK/home/.local/share" bash "$SCRIPT" --once --dry-run 2>&1)"
}

setup
listen "0.0.0.0:27036" steam
listen "[::]:27036" steam 101
cat >"$WORK/home/.local/share/applications/steam.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Steam
Exec=/usr/bin/steam %U
DESKTOP
run
check "asks once for an app listening on a blocked port, by its app name" test "$OUT" == "ask Steam 27036/tcp"

setup
listen "127.0.0.1:631" cupsd
listen "[::1]:5000" myapp
listen "[::ffff:127.0.0.1]:6000" other
run
check "ignores apps listening only on this computer" test -z "$OUT"

setup
listen "0.0.0.0:8005" python3
listen "0.0.0.0:22" sshd
run
check "ignores ports the zone allows, its own and its services'" test -z "$OUT"

setup
listen "192.168.1.20:3000" node
run
check "names an app without a menu entry by its command" test "$OUT" == "ask node 3000/tcp"

setup
listen "0.0.0.0:3000" node
mkdir -p "$WORK/home/.local/state/orielos"
echo "node 3000/tcp block" >"$WORK/home/.local/state/orielos/firewall-decisions"
run
check "doesn't ask again once answered" test -z "$OUT"

setup
listen "0.0.0.0:3000" node
touch "$WORK/no-firewall"
run
check "does nothing while the firewall isn't running" test -z "$OUT"

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
((FAILED == 0))

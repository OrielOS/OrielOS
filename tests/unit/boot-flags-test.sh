#!/usr/bin/env bash
# Unit tests for the boot menu's flag helper, image/system/usr/libexec/orielos/boot-flags: what
# each command does to the flags GRUB reads, and keeping the previous build after the boot loader
# fell back. It works on a plain file (ORIELOS_BOOT_FLAGS_FILE) instead of the EFI system
# partition, with stand-ins for grub2-editenv and orielos-update, so it needs no root or VM.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/boot-flags-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/libexec/orielos/boot-flags"
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
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT; flags: $(flags_line)"; fi
}

# A fresh scratch directory with stand-ins: grub2-editenv keeps name=value lines in the file, and
# orielos-update logs its arguments and the flag file it was given, failing if undo-fails exists.
setup() {
    rm -rf "${WORK:?}/bin" "${WORK:?}/env" "${WORK:?}/calls" "${WORK:?}/undo-fails"
    mkdir -p "$WORK/bin"
    : >"$WORK/calls"
    cat >"$WORK/bin/grub2-editenv" <<'SH'
#!/usr/bin/env bash
file="$1"
shift
case "$1" in
    create) printf '# GRUB Environment Block\n' >"$file" ;;
    list) grep -v '^#' "$file" ;;
    set)
        shift
        for pair in "$@"; do
            grep -v "^${pair%%=*}=" "$file" >"$file.new" || true
            printf '%s\n' "$pair" >>"$file.new"
            mv "$file.new" "$file"
        done
        ;;
esac
SH
    cat >"$WORK/bin/orielos-update" <<'SH'
#!/usr/bin/env bash
printf 'orielos-update %s file=%s\n' "$*" "${ORIELOS_BOOT_FLAGS_FILE:-}" >>"$WORK/calls"
[[ ! -e "$WORK/undo-fails" ]]
SH
    sed -i "s|\$WORK|$WORK|g" "$WORK/bin/orielos-update"
    chmod +x "$WORK/bin/"*
}

# Start from these flags: flags <name=value...>
flags() {
    printf '# GRUB Environment Block\n' >"$WORK/env"
    printf '%s\n' "$@" >>"$WORK/env"
}

# The flags as one sorted line.
flags_line() {
    if [[ -r "$WORK/env" ]]; then grep -v '^#' "$WORK/env" | sort | paste -sd ' ' -; fi
}

run() {
    RC=0
    OUT="$(ORIELOS_BOOT_FLAGS_FILE="$WORK/env" ORIELOS_UPDATE_TOOL="$WORK/bin/orielos-update" PATH="$WORK/bin:$PATH" \
        bash "$TOOL" "$@" 2>&1)" || RC=$?
}

is() {
    [[ "$(flags_line)" == "$1" ]]
}

setup
run trial
check "trial creates the file and puts the next start on trial" is "orielos_fails=0 orielos_trial=1"

setup
flags orielos_boot_ok=0 orielos_trial=1 orielos_fails=1
run good
check "good after a version on trial reached the desktop clears the trial" is "orielos_boot_ok=1 orielos_fails=0 orielos_trial=0"
check "good with nothing to undo leaves orielos-update alone" test ! -s "$WORK/calls"

setup
flags orielos_boot_ok=0 orielos_trial=fallback orielos_fails=1
run good
check "good after the boot loader fell back keeps the previous build" grep -q "^orielos-update undo-update file=$WORK/env$" "$WORK/calls"
check "then the start counts as good and nothing is on trial" is "orielos_boot_ok=1 orielos_fails=0 orielos_trial=0"

setup
flags orielos_boot_ok=0 orielos_trial=fallback orielos_fails=1
: >"$WORK/undo-fails"
run good
check "good fails with exit 1 if the previous build can't be kept" test "$RC" -eq 1
check "then it still marks the start good but keeps the fallback, so a new failure shows the menu" \
    is "orielos_boot_ok=1 orielos_fails=1 orielos_trial=fallback"

setup
flags orielos_boot_ok=0 orielos_trial=kept orielos_fails=0
run good
check "good after a kept build reached the desktop ends the fallback" is "orielos_boot_ok=1 orielos_fails=0 orielos_trial=0"

setup
flags orielos_boot_ok=1 orielos_trial=1 orielos_fails=1
run clear
check "clear takes the next start off trial" is "orielos_boot_ok=1 orielos_fails=0 orielos_trial=0"

setup
flags orielos_boot_ok=0 orielos_trial=fallback orielos_fails=1
run kept
check "kept records that the previous build was kept" is "orielos_boot_ok=0 orielos_fails=0 orielos_trial=kept"

setup
flags orielos_boot_ok=1 orielos_trial=0 orielos_fails=0
run menu
check "menu shows the boot menu at the next start and keeps the other flags" is "orielos_boot_ok=1 orielos_fails=0 orielos_menu=1 orielos_trial=0"

setup
flags orielos_boot_ok=1 orielos_trial=0 orielos_fails=0
run status
check "status prints the three flags" \
    test "$OUT" == "$(printf 'orielos_boot_ok=1\norielos_trial=0\norielos_fails=0')"

setup
run status
check "status without the file prints empty flags" \
    test "$OUT" == "$(printf 'orielos_boot_ok=\norielos_trial=\norielos_fails=')"

for args in "" "bad" "good extra"; do
    setup
    # shellcheck disable=SC2086 # the arguments are split on purpose
    run $args
    check "'$args' is refused with exit 2" test "$RC" -eq 2
done

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]

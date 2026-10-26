# shellcheck shell=bash
# The lock that lets one image build or VM test run at a time, so a computer never holds more
# than one of them in progress. Sourced by tools/build-image.sh, tools/clean.sh and
# tests/lib/vm.sh, which hold it for their whole run; it goes when the process ends.

ORIELOS_LOCK="/run/lock/orielos.lock"

# Take the lock for the rest of the run, or print who holds it and return 1. A process started by
# the holder, such as tools/clean.sh running tools/build-image.sh, shares the holder's lock. The
# file is opened for appending, so the holder's process ID can be read while it holds the lock.
take_orielos_lock() {
    local fd holder=""
    if [[ -n "${ORIELOS_LOCK_HELD:-}" ]]; then return 0; fi
    mkdir -p "${ORIELOS_LOCK%/*}"
    exec {fd}>>"$ORIELOS_LOCK"
    if ! flock -n "$fd"; then
        holder="$(cat "$ORIELOS_LOCK" 2>/dev/null || true)"
        printf 'error: another OrielOS build or VM test is running (process %s); they run one at a time\n' \
            "${holder:-unknown}" >&2
        return 1
    fi
    printf '%s\n' "$$" >"$ORIELOS_LOCK"
    export ORIELOS_LOCK_HELD="$$"
}

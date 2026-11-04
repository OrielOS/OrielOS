#!/usr/bin/env bash
# Unit tests for orielos-reset: getting a reset ready (the download's progress, the new system's
# kernel arguments and the settings it keeps or leaves behind), cancelling it, undoing one whose
# start failed, and the reset start's home folders and clean-up. Runs the real script against a
# scratch directory (ORIELOS_RESET_ROOT) with stand-ins for skopeo, ostree, bootc, rpm-ostree,
# systemctl, findmnt and the boot menu's flag helper, so it needs no root, VM or network.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/orielos-reset-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/image/system/usr/bin/orielos-reset"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
DIGEST="sha256:$(printf 'b%.0s' {1..64})"
COMMIT="$(printf 'c%.0s' {1..64})"
OUT=""
RC=0
R=""

pass() {
    printf 'PASS  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/      /'; fi
    FAILED=$((FAILED + 1))
}

# check <name> <condition...>: PASS if the command succeeds, else FAIL with the last output.
check() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name" "exit $RC: $OUT"; fi
}

# A fresh scratch computer running the "default" stateroot with one account, alice, whose home
# folder is in the stateroot's /var, and stand-in commands that log their arguments to
# $WORK/stub/calls. ostree's stand-in keeps the deployments in $WORK/stub/deployments, one
# "<stateroot> <checksum>" a line, and creates the deployment folders it's asked to.
setup() {
    rm -rf "${WORK:?}/root" "${WORK:?}/stub" "${WORK:?}/bin"
    R="$WORK/root"
    mkdir -p "$R/usr/lib/orielos" "$R/usr/lib/bootc/kargs.d" "$R/etc/orielos" "$R/etc/NetworkManager/system-connections" \
        "$R/proc/sys/kernel/random" "$R/var/lib/orielos/update" "$R/var/lib/AccountsService/users" \
        "$R/sysroot/ostree/deploy/default/deploy/aaaa.0/etc" "$R/sysroot/ostree/deploy/default/var/home/alice" \
        "$R/var/home/alice" "$WORK/stub" "$WORK/bin"
    printf 'source=docker://example.test/orielos\n' >"$R/usr/lib/orielos/update.conf"
    printf 'channel=testing\npaused_until=2026-12-01T00:00:00Z\napp_updates=off\n' >"$R/var/lib/orielos/update/settings"
    printf 'boot-1\n' >"$R/proc/sys/kernel/random/boot_id"
    printf 'BOOT_IMAGE=(hd0,gpt2)/vmlinuz root=UUID=1234 rw rootflags=subvol=root,compress=zstd:1 quiet orielos.build=v0.2.0 ostree=/ostree/boot.0/default/abcd/0\n' >"$R/proc/cmdline"
    printf 'kargs = ["quiet"]\n' >"$R/usr/lib/bootc/kargs.d/10-splash.toml"
    printf 'kargs = ["orielos.build=v0.2.0"]\n' >"$R/usr/lib/bootc/kargs.d/90-build.toml"
    printf 'root:x:0:0:root:/root:/bin/bash\nalice:x:1000:1000:Alice:/var/home/alice:/bin/bash\n' >"$R/etc/passwd"
    printf 'root:x:0:\nwheel:x:10:alice\nalice:x:1000:\n' >"$R/etc/group"
    # shellcheck disable=SC2016 # a password hash, with literal $ signs
    printf 'root:!::0:99999:7:::\nalice:$y$secret:20000:0:99999:7:::\n' >"$R/etc/shadow"
    printf 'root:!::\nwheel:!::alice\nalice:!::\n' >"$R/etc/gshadow"
    printf 'UUID=1234 /boot ext4 defaults 1 2\n' >"$R/etc/fstab"
    printf 'alices-pc\n' >"$R/etc/hostname"
    printf 'abc123\n' >"$R/etc/machine-id"
    printf 'done\n' >"$R/etc/plasma-setup-done"
    printf '[wifi]\nssid=Home\n' >"$R/etc/NetworkManager/system-connections/Home.nmconnection"
    printf '[User]\nIcon=/var/lib/AccountsService/icons/alice\n' >"$R/var/lib/AccountsService/users/alice"
    printf 'my file\n' >"$R/var/home/alice/notes.txt"
    printf 'my file\n' >"$R/sysroot/ostree/deploy/default/var/home/alice/notes.txt"
    printf 'default aaaa\n' >"$WORK/stub/deployments"
    # The boot loader's entry for the running system, and the boot link it points at.
    mkdir -p "$R/boot/loader/entries" "$R/sysroot/ostree/boot.0/default/abcd/0"
    printf 'title OrielOS\noptions root=UUID=1234 rw ostree=/ostree/boot.0/default/abcd/0\n' >"$R/boot/loader/entries/ostree-default.conf"
    : >"$WORK/stub/calls"

    cat >"$WORK/bin/skopeo" <<'SH'
#!/usr/bin/env bash
printf 'skopeo %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ -e "$ORIELOS_TEST_STUB/skopeo-fails" ]]; then
    echo "pinging container registry: no route to host" >&2
    exit 1
fi
case "$1" in
    inspect)
        if [[ "$2" == --raw ]]; then
            printf '{"layers": [{"size": 3000}, {"size": 1000}], "config": {"size": 100}}\n'
        else
            printf '{"Digest": "%s", "Labels": {"org.opencontainers.image.version": "v0.3.1"}}\n' "$ORIELOS_TEST_DIGEST"
        fi
        ;;
    copy)
        dir="${*: -1}"
        dir="${dir#oci:}"
        dir="${dir%:reset}"
        mkdir -p "$dir"
        printf '{"manifests": [{"digest": "%s"}]}\n' "${ORIELOS_TEST_COPIED:-$ORIELOS_TEST_DIGEST}" >"$dir/index.json"
        head -c 4100 /dev/zero >"$dir/blob"
        ;;
esac
SH
    cat >"$WORK/bin/ostree" <<'SH'
#!/usr/bin/env bash
printf 'ostree %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
deployments="$ORIELOS_TEST_STUB/deployments"
sysroot="$ORIELOS_RESET_ROOT/sysroot"
case "$1 $2" in
    "admin status")
        first=1
        while read -r stateroot checksum; do
            if [[ "$stateroot" == default && "$checksum" == aaaa ]]; then mark="*"; else mark=" "; fi
            printf '%s %s %s.0\n    origin: <unknown origin type>\n' "$mark" "$stateroot" "$checksum"
            first=0
        done <"$deployments"
        ;;
    "admin undeploy")
        index="$3"
        line="$(sed -n "$((index + 1))p" "$deployments")"
        sed -i "$((index + 1))d" "$deployments"
        read -r stateroot checksum <<<"$line"
        rm -rf "$sysroot/ostree/deploy/$stateroot/deploy/$checksum.0" "$sysroot/ostree/boot.0/$stateroot"
        rm -f "$ORIELOS_RESET_ROOT/boot/loader/entries/ostree-$stateroot.conf"
        ;;
    "admin os-init")
        mkdir -p "$sysroot/ostree/deploy/$3/var" "$sysroot/ostree/deploy/$3/deploy"
        ;;
    "admin deploy")
        stateroot=""
        for arg in "$@"; do
            case "$arg" in
                --stateroot=*) stateroot="${arg#--stateroot=}" ;;
                --origin-file=*) cp "${arg#--origin-file=}" "$ORIELOS_TEST_STUB/origin" ;;
            esac
        done
        commit="${*: -1}"
        mkdir -p "$sysroot/ostree/deploy/$stateroot/deploy/$commit.0/etc"
        # The new build's own account files, with a system account the old one lacks.
        printf 'root:x:0:0:root:/root:/bin/bash\nnewsvc:x:990:990::/:/sbin/nologin\n' \
            >"$sysroot/ostree/deploy/$stateroot/deploy/$commit.0/etc/passwd"
        printf '%s %s\n%s' "$stateroot" "$commit" "$(cat "$deployments")" >"$deployments.new"
        printf '\n' >>"$deployments.new"
        grep -v '^$' "$deployments.new" >"$deployments"
        rm -f "$deployments.new"
        # The new system's boot entry and link. With break-boot, the old system's link goes, as it
        # did when ostree was pointed at /sysroot on a computer with a /boot partition of its own.
        mkdir -p "$sysroot/ostree/boot.0/$stateroot/abcd/0"
        printf 'title OrielOS\noptions root=UUID=1234 rw ostree=/ostree/boot.0/%s/abcd/0\n' "$stateroot" \
            >"$ORIELOS_RESET_ROOT/boot/loader/entries/ostree-$stateroot.conf"
        if [[ -e "$ORIELOS_TEST_STUB/break-boot" ]]; then rm -rf "$sysroot/ostree/boot.0/default"; fi
        ;;
    "container image")
        case "$3" in
            pull)
                if [[ -e "$ORIELOS_TEST_STUB/pull-fails" ]]; then
                    echo "error: importing: no space left on device" >&2
                    exit 1
                fi
                while [[ $# -gt 0 ]]; do
                    if [[ "$1" == --ostree-digestfile ]]; then printf '%s\n' "$ORIELOS_TEST_COMMIT" >"$2"; fi
                    shift
                done
                ;;
            remove)
                # Like ostree-ext, removing takes the bare image name, not how to check it.
                if [[ "${!#}" == ostree-* ]]; then
                    echo "error: invalid value '${!#}' for '[IMGREFS]...': Invalid transport" >&2
                    exit 2
                fi
                ;;
        esac
        ;;
    *)
        # ostree --repo=... ls|cat <commit> <path>: the new build's kargs.d.
        if [[ "$2" == ls ]]; then
            printf -- '-00644 0 0 30 /usr/lib/bootc/kargs.d/10-splash.toml\n-00644 0 0 30 /usr/lib/bootc/kargs.d/90-build.toml\n'
        elif [[ "$2" == cat && "$4" == */10-splash.toml ]]; then
            printf 'kargs = ["quiet"]\n'
        elif [[ "$2" == cat && "$4" == */90-build.toml ]]; then
            printf 'kargs = ["orielos.build=v0.3.1"]\n'
        fi
        ;;
esac
SH
    cat >"$WORK/bin/bootc" <<'SH'
#!/usr/bin/env bash
printf 'bootc %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
if [[ -e "$ORIELOS_TEST_STUB/staged" ]]; then echo '{"status": {"staged": {}}}'; else echo '{"status": {"staged": null}}'; fi
SH
    cat >"$WORK/bin/rpm-ostree" <<'SH'
#!/usr/bin/env bash
printf 'rpm-ostree %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
SH
    cat >"$WORK/bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
# is-active: nothing runs, unless the stub says so.
if [[ "$1" == is-active ]]; then [[ -e "$ORIELOS_TEST_STUB/unit-active" ]]; fi
SH
    # findmnt lists the mounts: /var/home only when the stub says so, and nothing under a stateroot.
    cat >"$WORK/bin/findmnt" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$ORIELOS_RESET_ROOT/"
if [[ -e "$ORIELOS_TEST_STUB/home-separate" ]]; then printf '%s\n' "$ORIELOS_RESET_ROOT/var/home"; fi
SH
    # df: plenty of room unless the stub says otherwise.
    cat >"$WORK/bin/df" <<'SH'
#!/usr/bin/env bash
printf 'Avail\n%s\n' "$(cat "$ORIELOS_TEST_STUB/free" 2>/dev/null || echo 100000000000)"
SH
    mkdir -p "$R/usr/libexec/orielos"
    cat >"$R/usr/libexec/orielos/boot-flags" <<'SH'
#!/usr/bin/env bash
printf 'boot-flags %s\n' "$*" >>"$ORIELOS_TEST_STUB/calls"
SH
    chmod +x "$WORK/bin/"* "$R/usr/libexec/orielos/boot-flags"
}

# Run orielos-reset, keeping its output in OUT and its exit status in RC.
run() {
    RC=0
    OUT="$(ORIELOS_RESET_ROOT="$R" ORIELOS_TEST_STUB="$WORK/stub" ORIELOS_TEST_DIGEST="$DIGEST" ORIELOS_TEST_COMMIT="$COMMIT" \
        PATH="$WORK/bin:$PATH" bash "$TOOL" "$@" 2>&1)" || RC=$?
}

state() {
    jq -r "$1" "$R/var/lib/orielos/reset/state.json"
}

prepared() {
    sed -n "s/^$1=//p" "$R/var/lib/orielos/reset/prepared"
}

called() {
    grep -qF -- "$1" "$WORK/stub/calls"
}

not_called() {
    ! grep -qF -- "$1" "$WORK/stub/calls"
}

# Whether the new system was deployed with the new build's kargs.d arguments once each, and without
# the old build's or those only one start has.
new_build_kargs() {
    [[ "$(grep -o -- '--karg-append=quiet' "$WORK/stub/calls" | wc -l)" -eq 1 ]] &&
        called "--karg-append=orielos.build=v0.3.1" && not_called "orielos.build=v0.2.0" &&
        not_called "--karg-append=ostree=" && not_called "--karg-append=BOOT_IMAGE"
}

# The new stateroot's folder, and its deployment's /etc.
new_root() {
    printf '%s/sysroot/ostree/deploy/%s' "$R" "$(prepared new)"
}

new_etc() {
    printf '%s/deploy/%s.0/etc' "$(new_root)" "$COMMIT"
}

#BEGIN Getting a reset ready
setup
run prepare keep
check "prepare keep succeeds" test "$RC" -eq 0
check "the state says the reset is ready, with the version and the download's size" \
    test "$(state .phase)" == ready -a "$(state .version)" == v0.3.1 -a "$(state .total)" == 4100 -a "$(state .mode)" == keep
check "it downloads the channel's build by its digest, without its signature" \
    called "skopeo copy --retry-times 3 --remove-signatures docker://example.test/orielos@$DIGEST oci:"
check "it reads the computer's channel" called "skopeo inspect docker://example.test/orielos:testing"
check "it removes the imported download by its image name, leaving no copy behind" \
    called "ostree container image remove --repo $R/sysroot/ostree/repo oci:$R/var/lib/orielos/reset/download:reset"
check "the new system is a new stateroot" test -n "$(prepared new)" -a "$(prepared new)" != default -a "$(prepared old)" == default
check "the new system tracks the build by its digest" \
    grep -qx "container-image-reference=ostree-image-signed:docker://example.test/orielos@$DIGEST" "$WORK/stub/origin"
check "the new system is deployed at once, from the imported commit, with fresh settings" \
    called "ostree admin deploy --sysroot=$R --stateroot=$(prepared new) --no-merge --origin-file="
check "the new system keeps this computer's own kernel arguments" \
    called "--karg-append=root=UUID=1234 --karg-append=rw --karg-append=rootflags=subvol=root,compress=zstd:1"
check "the new system gets the new build's arguments, not the old build's or the start's own" new_build_kargs
# A password hash starts with a literal $.
# shellcheck disable=SC2016
check "accounts and passwords stay" grep -q '^alice:\$y\$secret:' "$(new_etc)/shadow"
check "the new build's system accounts are added" grep -q '^newsvc:' "$(new_etc)/passwd"
check "the old system's accounts come first" test "$(sed -n 2p "$(new_etc)/passwd")" == "alice:x:1000:1000:Alice:/var/home/alice:/bin/bash"
check "group members stay" grep -qx 'wheel:x:10:alice' "$(new_etc)/group"
check "the name, saved networks, mount table and setup's mark stay" \
    test -f "$(new_etc)/hostname" -a -f "$(new_etc)/NetworkManager/system-connections/Home.nmconnection" -a -f "$(new_etc)/fstab" -a -f "$(new_etc)/plasma-setup-done"
check "account pictures stay" test -f "$(new_root)/var/lib/AccountsService/users/alice"
check "the channel and app updates setting stay, the pause doesn't" \
    test "$(cat "$(new_root)/var/lib/orielos/update/settings")" == "$(printf 'channel=testing\npaused_until=\napp_updates=off')"
check "the reset start's mark for apply is written" grep -qx 'mode=keep' "$(new_etc)/orielos/reset-apply"
check "the reset start's mark for finish is written" test -f "$(new_root)/var/lib/orielos/reset/finish"
check "the new system is on trial" called "boot-flags trial"
check "the download is removed" test ! -e "$R/var/lib/orielos/reset/download"
check "updates wait while the reset is ready" test -e "$R/var/lib/orielos/reset/pending"
check "an update check running is stopped first" called "systemctl stop orielos-update-check.service"

setup
run prepare erase
check "prepare erase keeps only the mount table" \
    test -f "$(new_etc)/fstab" -a ! -e "$(new_etc)/hostname" -a ! -e "$(new_etc)/plasma-setup-done" -a ! -e "$(new_etc)/shadow"
check "removing everything keeps no account pictures" test ! -e "$(new_root)/var/lib/AccountsService"
check "removing everything still keeps the channel" grep -qx 'channel=testing' "$(new_root)/var/lib/orielos/update/settings"
check "removing everything turns app updates back on" grep -qx 'app_updates=on' "$(new_root)/var/lib/orielos/update/settings"

setup
touch "$WORK/stub/home-separate"
run prepare keep
check "a computer with its own home file system is noted" test "$(prepared home_separate)" == 1

setup
touch "$WORK/stub/staged"
run prepare keep
check "an update waiting for a restart is set aside first" called "rpm-ostree cleanup --pending"
#END

#BEGIN When getting ready fails
setup
touch "$WORK/stub/skopeo-fails"
run prepare keep
check "no connection fails with a plain message" test "$RC" -eq 1 -a "$(state .phase)" == failed
check "the message says what to do" test "$(state .message)" == "Couldn't reach OrielOS's downloads. Check the internet connection and try again."
check "a failure leaves nothing pending" test ! -e "$R/var/lib/orielos/reset/pending" -a ! -e "$R/var/lib/orielos/reset/prepared"

setup
printf '1000\n' >"$WORK/stub/free"
run prepare keep
check "too little free space is refused" test "$RC" -eq 1
check "too little free space is found before downloading" not_called "skopeo copy"
check "the message says how much is needed" grep -q "enough free space" <<<"$(state .message)"

setup
touch "$WORK/stub/pull-fails"
run prepare keep
check "a failed unpack fails the reset" test "$RC" -eq 1 -a "$(state .phase)" == failed
check "a failed unpack removes the download" test ! -e "$R/var/lib/orielos/reset/download"
check "nothing new was deployed" test "$(cat "$WORK/stub/deployments")" == "default aaaa"

setup
touch "$WORK/stub/break-boot"
run prepare keep
check "a boot entry that leads nowhere fails the reset" test "$RC" -eq 1 -a "$(state .phase)" == failed
check "the message says nothing was changed" grep -q "Nothing was changed" <<<"$(state .message)"
check "a failed boot check removes the new system" test "$(cat "$WORK/stub/deployments")" == "default aaaa"
check "a failed boot check names the broken entry in the log" grep -q "leads nowhere" "$R/var/lib/orielos/reset/prepare.log"

setup
rm -f "$R/boot/loader/entries/ostree-default.conf"
run prepare keep
check "no boot entry for the old system fails the reset" test "$RC" -eq 1 -a "$(state .phase)" == failed

setup
RC=0
OUT="$(ORIELOS_RESET_ROOT="$R" ORIELOS_TEST_STUB="$WORK/stub" ORIELOS_TEST_DIGEST="$DIGEST" ORIELOS_TEST_COMMIT="$COMMIT" \
    ORIELOS_TEST_COPIED="sha256:$(printf 'd%.0s' {1..64})" PATH="$WORK/bin:$PATH" bash "$TOOL" prepare keep 2>&1)" || RC=$?
check "a download that isn't the build asked for is refused" test "$RC" -eq 1
check "a download that isn't the build asked for isn't unpacked" not_called "ostree container image pull"
#END

#BEGIN Cancelling and undoing
setup
run prepare keep
new="$(prepared new)"
run cancel
check "cancel succeeds" test "$RC" -eq 0 -a "$(state .phase)" == cancelled
check "cancel removes the new system" test ! -e "$R/sysroot/ostree/deploy/$new" -a "$(cat "$WORK/stub/deployments")" == "default aaaa"
check "cancel takes the new system off trial" called "boot-flags clear"
check "cancel lets updates go on" test ! -e "$R/var/lib/orielos/reset/pending"
check "cancel stops a reset being got ready" called "systemctl stop orielos-reset@keep.service orielos-reset@erase.service"

setup
run prepare keep
run refresh
check "refresh in the same start leaves a ready reset alone" test "$(state .phase)" == ready -a -e "$R/var/lib/orielos/reset/prepared"

setup
run prepare keep
new="$(prepared new)"
# The reset start moved alice's home folder across, then failed twice; the old system started.
mv "$R/sysroot/ostree/deploy/default/var/home" "$R/sysroot/ostree/deploy/$new/var/home"
printf 'boot-2\n' >"$R/proc/sys/kernel/random/boot_id"
run refresh
check "refresh after the old system started says the reset didn't finish" test "$(state .phase)" == failed
check "refresh puts the home folders back" test -f "$R/sysroot/ostree/deploy/default/var/home/alice/notes.txt"
check "refresh removes the new system" test ! -e "$R/sysroot/ostree/deploy/$new"

setup
mkdir -p "$R/var/lib/orielos/reset"
touch "$R/var/lib/orielos/reset/pending"
run refresh
check "refresh clears a reset that was interrupted before it was ready" \
    test ! -e "$R/var/lib/orielos/reset/pending" -a "$(state .phase)" == failed
#END

#BEGIN The reset start
# The new system has started: its stateroot is on the kernel command line, the old one is still
# there, and the marks prepare wrote are in place.
start_new_system() {
    run prepare "$1"
    new="$(prepared new)"
    printf 'boot-2\n' >"$R/proc/sys/kernel/random/boot_id"
    printf 'root=UUID=1234 rw ostree=/ostree/boot.1/%s/ef01/0\n' "$new" >"$R/proc/cmdline"
    mkdir -p "$R/etc/orielos"
    cp "$(new_etc)/orielos/reset-apply" "$R/etc/orielos/reset-apply"
    mkdir -p "$R/var/lib/orielos/reset"
    cp "$(new_root)/var/lib/orielos/reset/finish" "$R/var/lib/orielos/reset/finish"
}

setup
start_new_system keep
run apply
check "apply moves the home folders into the new system" \
    test -f "$R/sysroot/ostree/deploy/$new/var/home/alice/notes.txt" -a ! -e "$R/sysroot/ostree/deploy/default/var/home"
check "apply runs once" test ! -e "$R/etc/orielos/reset-apply"
run finish
check "finish removes the old system" test ! -e "$R/sysroot/ostree/deploy/default" -a "$(cat "$WORK/stub/deployments")" == "$new $COMMIT"
check "finish says the PC was reset" test "$(state .phase)" == "done" -a "$(state .version)" == v0.3.1
check "finish runs once" test ! -e "$R/var/lib/orielos/reset/finish"

setup
start_new_system keep
rm -f "$R/etc/orielos/reset-apply"
run finish
check "finish keeps the old system when its home folders weren't moved" \
    test "$RC" -eq 1 -a -f "$R/sysroot/ostree/deploy/default/var/home/alice/notes.txt"
check "finish says where the files are" grep -q "home folders stayed with the old system" <<<"$(state .message)"

setup
touch "$WORK/stub/home-separate"
start_new_system erase
run apply
check "removing everything moves a separate home file system's folders out of setup's way" \
    test -f "$R/var/home/.orielos-erased/alice/notes.txt" -a ! -e "$R/var/home/alice"
run finish
check "finish deletes them" test ! -e "$R/var/home/.orielos-erased"

setup
run apply
run finish
check "apply and finish succeed on an ordinary start" test "$RC" -eq 0
check "apply and finish change nothing on an ordinary start" not_called "ostree admin undeploy"
#END

#BEGIN Usage
setup
run prepare everything
check "prepare takes only keep or erase" test "$RC" -eq 2
run status
check "status without a reset says idle" test "$OUT" == '{"phase": "idle"}'
#END

printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]

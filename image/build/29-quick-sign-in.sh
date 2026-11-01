#!/usr/bin/env bash
# Quick sign-in, like Windows Hello: a PIN and fingerprints, besides the password, at the sign-in
# screen (sddm), the lock screen (kde) and administrator prompts (polkit-1).
#
# The PIN is checked first: pam_exec hands what was typed to /usr/libexec/orielos/pin-auth, which
# asks OrielOS's PIN service; if it isn't the account's PIN, PAM carries on to the password with the
# same text, so one box takes either. Administrator prompts try a fingerprint first, then the PIN,
# then the password. authselect's with-fingerprint feature makes the fingerprint-auth stack real,
# which the lock screen tries in parallel with the box (kde-fingerprint). The PIN service and its
# units come in with image/system; 90-finalise.sh enables the socket and checks the helpers.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

pin_line='auth        [success=done default=ignore]                pam_exec.so quiet expose_authtok /usr/libexec/orielos/pin-auth'

# /usr/lib/pam.d/polkit-1 in polkit 127, without comments, blank lines or repeated spaces.
polkit_upstream='auth include system-auth
account include system-auth
password include system-auth
session include system-auth'

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

# Puts the PIN line before the first auth line that hands over to the password stack ($2) in $1.
add_pin() {
    local file="$1" stack="$2"
    [[ -f "$file" ]] || die "$file is missing"
    grep -q 'orielos/pin-auth' "$file" && return 0
    grep -qE "^auth[[:space:]]+(substack|include)[[:space:]]+$stack\$" "$file" ||
        die "$file has no 'auth substack/include $stack' line to put the PIN before; check its packaging"
    sed -i -E "0,/^auth[[:space:]]+(substack|include)[[:space:]]+$stack\$/s//${pin_line//\//\\/}\n&/" "$file"
    grep -q 'orielos/pin-auth' "$file" || die "could not add the PIN to $file"
}

main() {
    add_pin /etc/pam.d/sddm password-auth
    add_pin /etc/pam.d/kde password-auth

    # The administrator prompts' stack is polkit's own file in /usr, which only includes system-auth;
    # one in /etc replaces it. Should polkit's file change, this one needs to follow.
    [[ "$(grep -v '^#' /usr/lib/pam.d/polkit-1 | tr -s '[:blank:]' ' ' | sed '/^$/d')" == "$polkit_upstream" ]] ||
        die "/usr/lib/pam.d/polkit-1 changed; update the administrator prompts' stack in this script to match"
    cat >/etc/pam.d/polkit-1 <<PAM
#%PAM-1.0
# OrielOS's administrator prompts: a fingerprint, the PIN or the password, in that order
# (image/build/29-quick-sign-in.sh). polkit's own stack is /usr/lib/pam.d/polkit-1.
-auth       [success=done default=ignore]                pam_fprintd.so
$pin_line
auth        substack      password-auth
account     include       system-auth
password    include       system-auth
session     include       system-auth
PAM

    authselect enable-feature with-fingerprint
    grep -q pam_fprintd /etc/pam.d/system-auth || die "authselect did not add fprintd to system-auth"

    printf 'quick sign-in: the PIN goes before the password for sddm, kde and polkit-1; fingerprints are on\n'
}

main "$@"

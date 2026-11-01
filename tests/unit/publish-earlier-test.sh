#!/usr/bin/env bash
# Unit tests for tools/publish-earlier.sh: a build is copied to the earlier address, signed there
# (not by reusing the signature from the new address), and only then does the channel tag move.
# Stand-ins for skopeo and cosign record their arguments, so the test needs no registry or key.
# Prints PASS/FAIL per case and exits 1 if any case fails.
#
# Usage: tests/unit/publish-earlier-test.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/publish-earlier.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASSED=0
FAILED=0
OUT=""
RC=0

SRC="ghcr.io/orielos/orielos"
DEST="ghcr.io/ncjsvr/orielos"
TAG="v0.1.8"
DIGEST="sha256:$(printf 'a%.0s' {1..64})"
OTHER="sha256:$(printf 'b%.0s' {1..64})"

pass() {
    printf 'PASS  %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail() {
    printf 'FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed 's/^/      /'; fi
    FAILED=$((FAILED + 1))
}

# ref_file <docker reference without scheme> -> path of the file holding its digest.
ref_file() {
    printf '%s\n' "$WORK/refs/${1//\//_}"
}

setup() {
    rm -rf "${WORK:?}/bin" "${WORK:?}/refs" "${WORK:?}/signed"
    rm -f "$WORK/sign-fails" "$WORK/sign-does-not-verify" "$WORK/calls.token"
    mkdir -p "$WORK/bin" "$WORK/refs" "$WORK/signed"
    : >"$WORK/calls"
    printf '%s\n' "$DIGEST" >"$(ref_file "${SRC}:${TAG}")"
    cat >"$WORK/bin/skopeo" <<'SH'
#!/usr/bin/env bash
printf 'skopeo %s\n' "$*" >>"$STUB_CALLS"
ref="${!#}"
ref="${ref#docker://}"
file="$STUB_REFS/${ref//\//_}"
case "$1" in
    inspect)
        [[ -f "$file" ]] || exit 1
        printf '%s\n' "$(cat "$file")"
        ;;
    copy)
        src="${@: -2:1}"
        src="${src#docker://}"
        digest="${src#*@}"
        printf '%s\n' "$digest" >"$file"
        ;;
    login)
        token="$(cat)"
        printf 'login-user %s\n' "$4" >>"$STUB_CALLS"
        printf '%s' "$token" >"$STUB_CALLS.token"
        ;;
    *)
        printf 'unexpected skopeo %s\n' "$*" >&2
        exit 1
        ;;
esac
SH
    cat >"$WORK/bin/cosign" <<'SH'
#!/usr/bin/env bash
printf 'cosign %s\n' "$*" >>"$STUB_CALLS"
image="${!#}"
marker="$STUB_SIGNED/${image//\//_}"
case "$1" in
    verify)
        [[ -f "$marker" ]] || exit 1
        ;;
    sign)
        if [[ -f "$STUB_SIGN_FAILS" ]]; then
            printf 'sign failed\n' >&2
            exit 1
        fi
        if [[ ! -f "$STUB_SIGN_DOES_NOT_VERIFY" ]]; then
            : >"$marker"
        fi
        ;;
    login)
        cat >/dev/null
        ;;
    *)
        printf 'unexpected cosign %s\n' "$*" >&2
        exit 1
        ;;
esac
SH
    chmod +x "$WORK/bin/skopeo" "$WORK/bin/cosign"
}

run_tool() {
    local token="${PREVIOUS_REGISTRY_TOKEN-}"
    RC=0
    OUT="$(
        STUB_CALLS="$WORK/calls" STUB_REFS="$WORK/refs" STUB_SIGNED="$WORK/signed" \
            STUB_SIGN_FAILS="$WORK/sign-fails" STUB_SIGN_DOES_NOT_VERIFY="$WORK/sign-does-not-verify" \
            PATH="$WORK/bin:$PATH" \
            REPOSITORY="$SRC" PREVIOUS_REPOSITORY="$DEST" \
            COSIGN_PRIVATE_KEY="${COSIGN_PRIVATE_KEY-test-key}" \
            PREVIOUS_REGISTRY_TOKEN="$token" \
            "$TOOL" "$@" 2>&1
    )" || RC=$?
}

calls_have() {
    grep -qxF "$1" "$WORK/calls"
}

# The channel tag is copied only after a successful sign of the earlier address.
channel_after_sign() {
    awk '
        $0 ~ /^cosign sign / { signed = 1 }
        $0 ~ /^skopeo copy / && $0 ~ /:testing$/ { if (!signed) bad = 1 }
        END { exit bad ? 1 : 0 }
    ' "$WORK/calls"
}

setup
run_tool --help
if [[ "$RC" -eq 0 && "$OUT" == *"--tag TAG"* ]]; then pass "--help"; else fail "--help" "exit $RC: $OUT"; fi

setup
run_tool --tag v0.1 --channel testing
if [[ "$RC" -ne 0 && "$OUT" == *"looks like v0.1.8"* ]]; then pass "a tag that is not a version is refused"; else fail "a tag that is not a version is refused" "exit $RC: $OUT"; fi

setup
run_tool --tag "$TAG" --channel latest
if [[ "$RC" -ne 0 && "$OUT" == *"--channel is testing or stable"* ]]; then pass "a channel other than testing or stable is refused"; else fail "a channel other than testing or stable is refused" "exit $RC: $OUT"; fi

setup
rm -f "$(ref_file "${SRC}:${TAG}")"
run_tool --tag "$TAG" --channel testing
if [[ "$RC" -ne 0 ]] && ! grep -q '^skopeo copy ' "$WORK/calls"; then
    pass "a missing source build copies nothing"
else
    fail "a missing source build copies nothing" "exit $RC: $OUT"
fi

setup
printf '%s\n' "$OTHER" >"$(ref_file "${DEST}:${TAG}")"
run_tool --tag "$TAG" --channel testing
if [[ "$RC" -ne 0 && "$OUT" == *"versions are never reused"* ]] && ! grep -q '^skopeo copy ' "$WORK/calls"; then
    pass "an existing version with another digest is not overwritten"
else
    fail "an existing version with another digest is not overwritten" "exit $RC: $OUT"
fi

setup
COSIGN_PRIVATE_KEY="" run_tool --tag "$TAG" --channel testing
if [[ "$RC" -ne 0 && "$OUT" == *"COSIGN_PRIVATE_KEY"* ]] && ! grep -q '^skopeo copy ' "$WORK/calls"; then
    pass "a missing signing key copies nothing"
else
    fail "a missing signing key copies nothing" "exit $RC: $OUT"
fi

sign_line="cosign sign --yes --new-bundle-format=false --use-signing-config=false --key env://COSIGN_PRIVATE_KEY ${DEST}@${DIGEST}"
version_copy="skopeo copy --preserve-digests docker://${SRC}@${DIGEST} docker://${DEST}:${TAG}"
channel_copy="skopeo copy --preserve-digests docker://${DEST}@${DIGEST} docker://${DEST}:testing"

setup
run_tool --tag "$TAG" --channel testing
if [[ "$RC" -eq 0 ]] &&
    calls_have "$version_copy" && calls_have "$sign_line" && calls_have "$channel_copy" &&
    calls_have "cosign verify --key ${ROOT}/image/keys/orielos-cosign.pub ${DEST}@${DIGEST}" &&
    ! grep -q '\.sig' "$WORK/calls" &&
    channel_after_sign && [[ "$OUT" == *"Published ${DEST}:${TAG} (${DIGEST}) and moved testing to it"* ]]; then
    pass "a new build is signed at the earlier address before testing moves"
else
    fail "a new build is signed at the earlier address before testing moves" "exit $RC: $OUT
$(cat "$WORK/calls")"
fi

setup
: >"$WORK/sign-does-not-verify"
run_tool --tag "$TAG" --channel testing
if [[ "$RC" -ne 0 && "$OUT" == *"did not verify"* ]] && ! calls_have "$channel_copy"; then
    pass "testing does not move when the new signature does not verify"
else
    fail "testing does not move when the new signature does not verify" "exit $RC: $OUT
$(cat "$WORK/calls")"
fi

setup
printf '%s\n' "$DIGEST" >"$(ref_file "${DEST}:${TAG}")"
printf '%s\n' "$OTHER" >"$(ref_file "${DEST}:testing")"
: >"$WORK/signed/${DEST//\//_}@${DIGEST}"
COSIGN_PRIVATE_KEY="" run_tool --tag "$TAG" --channel testing
if [[ "$RC" -eq 0 ]] && calls_have "$channel_copy" && ! grep -q '^cosign sign ' "$WORK/calls" &&
    ! calls_have "$version_copy"; then
    pass "a build already signed at the earlier address only moves testing"
else
    fail "a build already signed at the earlier address only moves testing" "exit $RC: $OUT
$(cat "$WORK/calls")"
fi

setup
printf '%s\n' "$DIGEST" >"$(ref_file "${DEST}:${TAG}")"
printf '%s\n' "$DIGEST" >"$(ref_file "${DEST}:stable")"
: >"$WORK/signed/${DEST//\//_}@${DIGEST}"
run_tool --tag "$TAG" --channel stable
if [[ "$RC" -eq 0 && "$OUT" == *"is already ${TAG}"* ]] && ! grep -E -q '^(skopeo copy|cosign sign) ' "$WORK/calls"; then
    pass "a channel that already points at the build is left as it is"
else
    fail "a channel that already points at the build is left as it is" "exit $RC: $OUT
$(cat "$WORK/calls")"
fi

setup
PREVIOUS_REGISTRY_TOKEN="" run_tool --login --tag "$TAG" --channel testing
if [[ "$RC" -ne 0 && "$OUT" == *"PREVIOUS_REGISTRY_TOKEN"* ]] && ! grep -q '^skopeo ' "$WORK/calls"; then
    pass "login without a token stops before any registry call"
else
    fail "login without a token stops before any registry call" "exit $RC: $OUT"
fi

setup
PREVIOUS_REGISTRY_TOKEN="secret-token" run_tool --login --tag "$TAG" --channel testing
if [[ "$RC" -eq 0 ]] && calls_have "login-user ncjsvr" &&
    [[ "$(cat "$WORK/calls.token")" == "secret-token" ]] && ! grep -q 'secret-token' "$WORK/calls"; then
    pass "login uses the earlier address's owner and does not record the token"
else
    fail "login uses the earlier address's owner and does not record the token" "exit $RC: $OUT
$(cat "$WORK/calls")"
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]

#!/usr/bin/env bash
# Publishes one build that is already at ghcr.io/orielos/orielos to the earlier address,
# ghcr.io/ncjsvr/orielos, and moves a channel tag there onto it. Computers installed before the
# move to the OrielOS organisation still update from the earlier address, and their policy accepts
# a signature only when it names the address they pull from (signedIdentity matchRepository). The
# signature on the new address names that address, so it is not copied: the build is signed again
# here, with the same key and the same classic cosign format the Image workflow uses. The channel
# tag moves only after that signature verifies, so no computer on the channel sees an unsigned build.
#
# Usage: tools/publish-earlier.sh --tag v0.1.8 --channel testing|stable [--login]
#   --tag TAG        version tag already published at REPOSITORY
#   --channel NAME   testing or stable; moved on the earlier address to this build
#   --login          log skopeo and cosign in to ghcr.io with PREVIOUS_REGISTRY_TOKEN, as the
#                    owner of PREVIOUS_REPOSITORY. The workflow's own token cannot write there.
# Environment:
#   REPOSITORY                 source (default ghcr.io/orielos/orielos)
#   PREVIOUS_REPOSITORY        destination (default ghcr.io/ncjsvr/orielos)
#   PREVIOUS_REGISTRY_TOKEN    with --login: a classic personal access token, write:packages only
#   COSIGN_PRIVATE_KEY         signing key; required when the destination has no signature yet
#   COSIGN_PASSWORD            password for that key, when it has one
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${REPOSITORY:-ghcr.io/orielos/orielos}"
PREVIOUS_REPOSITORY="${PREVIOUS_REPOSITORY:-ghcr.io/ncjsvr/orielos}"
KEY="$ROOT/image/keys/orielos-cosign.pub"
TAG=""
CHANNEL=""
DO_LOGIN=0

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

usage() {
    sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            [[ $# -ge 2 ]] || die "--tag needs a version"
            TAG="$2"
            shift 2
            ;;
        --channel)
            [[ $# -ge 2 ]] || die "--channel needs testing or stable"
            CHANNEL="$2"
            shift 2
            ;;
        --login)
            DO_LOGIN=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown option: $1"
            ;;
    esac
done

[[ -n "$TAG" ]] || die "--tag is required"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the build looks like v0.1.8, not ${TAG}"
[[ "$CHANNEL" == testing || "$CHANNEL" == stable ]] || die "--channel is testing or stable, not ${CHANNEL}"
[[ "$REPOSITORY" =~ ^[a-z0-9.-]+/[a-z0-9-]+/[a-z0-9._-]+$ ]] || die "REPOSITORY is not a registry address"
[[ "$PREVIOUS_REPOSITORY" =~ ^[a-z0-9.-]+/[a-z0-9-]+/[a-z0-9._-]+$ ]] ||
    die "PREVIOUS_REPOSITORY is not a registry address"
[[ "$REPOSITORY" != "$PREVIOUS_REPOSITORY" ]] || die "the earlier address is the same as the source"
[[ -s "$KEY" ]] || die "${KEY#"$ROOT"/} is missing, so the signature can't be checked"

login_earlier() {
    local rest owner
    rest="${PREVIOUS_REPOSITORY#*/}"
    owner="${rest%%/*}"
    if [[ -z "${PREVIOUS_REGISTRY_TOKEN:-}" ]]; then
        printf '::error::The publish environment has no PREVIOUS_REGISTRY_TOKEN secret, so %s cannot be updated. Create a classic personal access token for the %s account with only the write:packages scope and add it to the publish environment. The workflow token cannot write there: the package belongs to that account and is not linked to this repository.\n' \
            "$PREVIOUS_REPOSITORY" "$owner" >&2
        exit 1
    fi
    printf '%s' "${PREVIOUS_REGISTRY_TOKEN}" | skopeo login ghcr.io --username "${owner}" --password-stdin
    printf '%s' "${PREVIOUS_REGISTRY_TOKEN}" | cosign login ghcr.io --username "${owner}" --password-stdin
}

if [[ "$DO_LOGIN" -eq 1 ]]; then
    login_earlier
fi

command -v skopeo >/dev/null 2>&1 || die "skopeo is not installed"
command -v cosign >/dev/null 2>&1 || die "cosign is not installed"

digest="$(skopeo inspect --format '{{.Digest}}' "docker://${REPOSITORY}:${TAG}")"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || die "${REPOSITORY}:${TAG} has no digest"

existing=""
if existing="$(skopeo inspect --format '{{.Digest}}' "docker://${PREVIOUS_REPOSITORY}:${TAG}" 2>/dev/null)"; then
    [[ "$existing" == "$digest" ]] ||
        die "${PREVIOUS_REPOSITORY}:${TAG} is ${existing}, not ${digest}; versions are never reused"
fi

# Stop before copying when a signature is still needed and the key is missing, so a failed run
# does not leave a new unsigned tag. A build already at the earlier address keeps the signature
# it was published with.
need_sign=1
if [[ "$existing" == "$digest" ]] &&
    cosign verify --key "$KEY" "${PREVIOUS_REPOSITORY}@${digest}" >/dev/null 2>&1; then
    need_sign=0
fi
if [[ "$need_sign" -eq 1 && -z "${COSIGN_PRIVATE_KEY:-}" ]]; then
    die "COSIGN_PRIVATE_KEY is not set, so ${PREVIOUS_REPOSITORY}@${digest} cannot be signed"
fi

changed=0
if [[ "$existing" != "$digest" ]]; then
    skopeo copy --preserve-digests "docker://${REPOSITORY}@${digest}" "docker://${PREVIOUS_REPOSITORY}:${TAG}"
    copied="$(skopeo inspect --format '{{.Digest}}' "docker://${PREVIOUS_REPOSITORY}:${TAG}")"
    [[ "$copied" == "$digest" ]] || die "the copy's digest is ${copied}, not ${digest}"
    changed=1
fi

if [[ "$need_sign" -eq 1 ]]; then
    # The same flags as the Image workflow. The reference is the earlier address, so the
    # signature's identity is that address and matchRepository accepts it.
    cosign sign --yes --new-bundle-format=false --use-signing-config=false \
        --key env://COSIGN_PRIVATE_KEY "${PREVIOUS_REPOSITORY}@${digest}"
    cosign verify --key "$KEY" "${PREVIOUS_REPOSITORY}@${digest}" >/dev/null ||
        die "the signature at ${PREVIOUS_REPOSITORY}@${digest} did not verify"
    changed=1
fi

channel_digest=""
if channel_digest="$(skopeo inspect --format '{{.Digest}}' "docker://${PREVIOUS_REPOSITORY}:${CHANNEL}" 2>/dev/null)"; then
    :
fi
if [[ "$channel_digest" != "$digest" ]]; then
    skopeo copy --preserve-digests "docker://${PREVIOUS_REPOSITORY}@${digest}" \
        "docker://${PREVIOUS_REPOSITORY}:${CHANNEL}"
    channel_digest="$(skopeo inspect --format '{{.Digest}}' "docker://${PREVIOUS_REPOSITORY}:${CHANNEL}")"
    [[ "$channel_digest" == "$digest" ]] ||
        die "${PREVIOUS_REPOSITORY}:${CHANNEL} is ${channel_digest}, not ${digest}"
    changed=1
fi

if [[ "$changed" -eq 1 ]]; then
    printf '::notice::Published %s:%s (%s) and moved %s to it\n' \
        "$PREVIOUS_REPOSITORY" "$TAG" "$digest" "$CHANNEL"
else
    printf '::notice::%s:%s is already %s (%s)\n' \
        "$PREVIOUS_REPOSITORY" "$CHANNEL" "$TAG" "$digest"
fi

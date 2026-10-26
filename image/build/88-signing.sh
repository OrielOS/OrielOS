#!/usr/bin/env bash
# Makes installed computers check the signature of every OrielOS build they update to. The public
# half of the key that CI signs published builds with is image/keys/orielos-cosign.pub, mounted at
# /keys. This installs it as /etc/pki/containers/orielos.pub, requires a sigstore signature made
# with it for ghcr.io/ncjsvr/orielos in /etc/containers/policy.json, and tells the container tools
# to look for signatures attached in the registry. orielos-update then stages builds with bootc's
# --enforce-container-sigpolicy. Until the key is in the repository, nothing changes and the build
# says so.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

key=/keys/orielos-cosign.pub
repository=ghcr.io/ncjsvr/orielos
policy=/etc/containers/policy.json

if [[ ! -s "$key" ]]; then
    printf 'note: %s is not in the repository yet, so updates are not signature-checked\n' "${key#/keys/}"
    exit 0
fi
grep -q 'BEGIN PUBLIC KEY' "$key" || {
    printf 'error: %s is not a PEM public key\n' "$key" >&2
    exit 1
}

install -D -m 0644 "$key" /etc/pki/containers/orielos.pub
[[ -r "$policy" ]] || {
    printf 'error: %s is missing from the base image\n' "$policy" >&2
    exit 1
}
tmp="$(mktemp)"
jq --arg repo "$repository" '.transports.docker[$repo] = [{
        type: "sigstoreSigned",
        keyPath: "/etc/pki/containers/orielos.pub",
        signedIdentity: {type: "matchRepository"}
    }]' "$policy" >"$tmp"
install -m 0644 "$tmp" "$policy"
rm -f "$tmp"

install -d /etc/containers/registries.d
printf 'docker:\n  %s:\n    use-sigstore-attachments: true\n' "$repository" >/etc/containers/registries.d/orielos.yaml

jq -e --arg repo "$repository" '.transports.docker[$repo][0].type == "sigstoreSigned"' "$policy" >/dev/null || {
    printf 'error: %s does not require a signature for %s\n' "$policy" "$repository" >&2
    exit 1
}
printf 'Updates from %s must be signed with %s\n' "$repository" /etc/pki/containers/orielos.pub

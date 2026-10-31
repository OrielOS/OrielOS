#!/usr/bin/env bash
# Makes installed computers check the signature of every OrielOS build they update to. The public
# half of the key that CI signs published builds with is image/keys/orielos-cosign.pub, mounted at
# /keys. This installs it as /etc/pki/containers/orielos.pub, requires a sigstore signature made
# with it for OrielOS's image in /etc/containers/policy.json (whose global default rejects,
# with a default per transport that accepts other images as before), and tells the container tools
# to look for signatures attached in the registry. orielos-update then stages builds with bootc's
# --enforce-container-sigpolicy. Until the key is in the repository, nothing changes and the build
# says so.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

key=/keys/orielos-cosign.pub
# OrielOS's image, at its address under the OrielOS organisation and at its earlier address, which
# computers installed before the move still update from until they've moved.
repositories=(ghcr.io/orielos/orielos ghcr.io/ncjsvr/orielos)
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
# bootc's --enforce-container-sigpolicy refuses to stage anything while the policy's global default
# is insecureAcceptAnything, as Fedora's is, even for an image with its own signature rule: updates
# from the registry failed with "containers-policy.json specifies a default of
# `insecureAcceptAnything`; refusing usage". So the global default rejects, and each transport gets
# its own default that accepts anything, as before, so Podman and other tools pull as they did;
# only OrielOS's own image needs its signature.
transports='["docker", "docker-daemon", "docker-archive", "oci", "oci-archive", "dir", "containers-storage", "sif", "tarball"]'
tmp="$(mktemp)"
jq --argjson transports "$transports" '
    .default = [{type: "reject"}]
    | reduce $transports[] as $t (.; .transports[$t][""] //= [{type: "insecureAcceptAnything"}])
    | reduce $ARGS.positional[] as $repo (.; .transports.docker[$repo] = [{
        type: "sigstoreSigned",
        keyPath: "/etc/pki/containers/orielos.pub",
        signedIdentity: {type: "matchRepository"}
    }])' "$policy" --args "${repositories[@]}" >"$tmp"
install -m 0644 "$tmp" "$policy"
rm -f "$tmp"

install -d /etc/containers/registries.d
{
    printf 'docker:\n'
    printf '  %s:\n    use-sigstore-attachments: true\n' "${repositories[@]}"
} >/etc/containers/registries.d/orielos.yaml

for repository in "${repositories[@]}"; do
    jq -e --arg repo "$repository" '.transports.docker[$repo][0].type == "sigstoreSigned"' "$policy" >/dev/null || {
        printf 'error: %s does not require a signature for %s\n' "$policy" "$repository" >&2
        exit 1
    }
done
jq -e '.default == [{type: "reject"}]' "$policy" >/dev/null || {
    printf 'error: %s has a default other than reject, so bootc would refuse to stage updates\n' "$policy" >&2
    exit 1
}
jq -e --argjson transports "$transports" \
    '. as $p | all($transports[]; $p.transports[.][""][0].type == "insecureAcceptAnything")' "$policy" >/dev/null || {
    printf 'error: %s does not let other images through on every transport\n' "$policy" >&2
    exit 1
}
printf 'Updates from %s must be signed with %s\n' "${repositories[*]}" /etc/pki/containers/orielos.pub

# shellcheck shell=bash
# Helpers for the two Containerfile stages CI publishes prebuilt (.github/workflows/stages.yml):
# app-deps as ghcr.io/orielos/orielos-builder and os-base as ghcr.io/orielos/orielos-base.
#
# Each published image is labelled with a hash of its stage's inputs: the committed contents of
# every file the stage reads. A build uses a published image only when that hash matches its own
# checkout, and its signature verifies, so a change to anything a stage reads is never built on
# a stale prebuilt image. Fedora's updates reach the published images when they are rebuilt.

STAGE_REGISTRY="${STAGE_REGISTRY:-ghcr.io/orielos}"
STAGE_LABEL="org.orielos.stage-inputs"

# The published image of a stage: stage_image app-deps|os-base
stage_image() {
    case "$1" in
        app-deps) printf '%s/orielos-builder\n' "$STAGE_REGISTRY" ;;
        os-base) printf '%s/orielos-base\n' "$STAGE_REGISTRY" ;;
        *) return 1 ;;
    esac
}

# The files and folders a stage reads, relative to the repository root.
stage_paths() {
    case "$1" in
        app-deps) printf '%s\n' image/Containerfile image/build/apps-builder.sh image/pins.env ;;
        os-base) printf '%s\n' image/Containerfile image/build image/packages image/keys image/sddm/orielos \
            plasma/shell image/pins.env ;;
        *) return 1 ;;
    esac
}

# The hash of a stage's inputs in a checkout, or "uncommitted" when any of them has uncommitted
# changes: stage_inputs <root> <stage>
stage_inputs() {
    local root="$1" stage="$2" paths=()
    mapfile -t paths < <(stage_paths "$stage") || return 1
    local git=(git -c "safe.directory=$root" -C "$root")
    if ! "${git[@]}" diff --quiet HEAD -- "${paths[@]}" ||
        [[ -n "$("${git[@]}" ls-files --others --exclude-standard -- "${paths[@]}")" ]]; then
        printf 'uncommitted\n'
        return 0
    fi
    { printf 'stage %s\n' "$stage" && "${git[@]}" ls-files -s -- "${paths[@]}"; } | sha256sum | cut -d' ' -f1
}

# The published image of a stage, by digest, when it was built from the same inputs as the
# checkout and is signed with OrielOS's key; prints nothing otherwise: published_stage <root> <stage>
# Needs skopeo and cosign. Every reason not to use the image is printed to stderr.
published_stage() {
    local root="$1" stage="$2" want image info have digest key="$1/image/keys/orielos-cosign.pub"
    want="$(stage_inputs "$root" "$stage")" || return 0
    image="$(stage_image "$stage")" || return 0
    if [[ "$want" == uncommitted ]]; then
        printf 'not using %s: its inputs have uncommitted changes\n' "$image" >&2
        return 0
    fi
    if ! info="$(skopeo inspect --format "{{index .Labels \"$STAGE_LABEL\"}} {{.Digest}}" "docker://$image:latest" 2>/dev/null)"; then
        printf 'not using %s: it could not be read\n' "$image" >&2
        return 0
    fi
    read -r have digest <<<"$info"
    if [[ "$have" != "$want" ]]; then
        printf 'not using %s: it was built from other inputs\n' "$image" >&2
        return 0
    fi
    if ! command -v cosign >/dev/null 2>&1 || [[ ! -s "$key" ]]; then
        printf 'not using %s: its signature cannot be checked here\n' "$image" >&2
        return 0
    fi
    if ! cosign verify --key "$key" "$image@$digest" >/dev/null 2>&1; then
        printf 'not using %s@%s: its signature does not verify\n' "$image" "$digest" >&2
        return 0
    fi
    printf '%s@%s\n' "$image" "$digest"
}

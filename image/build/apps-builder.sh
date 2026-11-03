#!/usr/bin/env bash
# Builds OrielOS's own apps in the app-builder stage of the Containerfile.
#   apps-builder.sh deps    installs the build dependencies
#   apps-builder.sh build   configures, builds, runs the tests and qmllint, and installs to /out
# The build fails if any test fails or qmllint reports a warning.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

src=/src
build=/src/build
ccache_dir=/ccache

step() { printf '==> %s\n' "$1"; }

deps() {
    dnf -y install --setopt=install_weak_deps=False \
        cmake ninja-build gcc-c++ ccache mold extra-cmake-modules \
        qt6-qtbase-devel qt6-qtdeclarative-devel \
        kf6-kirigami-devel kf6-ki18n-devel kf6-kcoreaddons-devel \
        libplasma-devel kf6-kconfig-devel \
        kf6-kstatusnotifieritem-devel kf6-knotifications-devel kf6-kdbusaddons-devel \
        kf6-kcmutils-devel kf6-kwidgetsaddons-devel kf6-kwindowsystem-devel \
        kf6-kio-devel kf6-kjobwidgets-devel kf6-kservice-devel kf6-krunner-devel kf6-solid-devel \
        kdecoration-devel kf6-kglobalaccel-devel libkscreen-devel layer-shell-qt-devel \
        polkit-qt6-1-devel
    # The QML modules the Start menu imports, so qmllint can check it: Plasma's private menu
    # models come with plasma-workspace. Settings' Camera page imports Qt Multimedia.
    dnf -y install --setopt=install_weak_deps=False \
        plasma-workspace kf6-kitemmodels kf6-kcmutils qt6-qtmultimedia
    dnf clean all
}

# Runs qmllint over every QML module with the import paths and resources CMake generated for
# it. The generated all_qmllint target cannot fail on warnings, so this calls qmllint itself. A
# module with only C++ types has no QML or JavaScript files to lint, and qmllint given none prints
# its usage and fails, so such a module is skipped. The modules are linted in parallel, one per
# core, and each one's output is printed whole when it finishes.
lint_qml() {
    local rsp modules=()
    while IFS= read -r -d '' rsp; do
        if ! grep -q -E '\.(qml|js|mjs)$' "$rsp"; then
            step "Skipping ${rsp##*/}: no QML or JavaScript files"
            continue
        fi
        modules+=("$rsp")
    done < <(find "$build" -path '*/.rcc/qmllint/*.rsp' ! -name '*_json.rsp' ! -name '*_module.rsp' -print0 | sort -z)
    if [[ "${#modules[@]}" -eq 0 ]]; then
        printf 'error: no QML modules found to lint\n' >&2
        exit 1
    fi
    if ! printf '%s\0' "${modules[@]}" | xargs -0 -n 1 -P "$(nproc)" "${BASH_SOURCE[0]}" lint-module; then
        printf 'error: qmllint reported a problem; see the output above\n' >&2
        exit 1
    fi
    printf 'qmllint: no warnings in %d QML module(s)\n' "${#modules[@]}"
}

# Lints one QML module, given its response file, and prints qmllint's output in one piece.
lint_module() {
    local out rc=0
    out="$(/usr/lib64/qt6/bin/qmllint --max-warnings 0 "@$1" 2>&1)" || rc=$?
    step "Running qmllint on ${1##*/}"
    if [[ -n "$out" ]]; then printf '%s\n' "$out"; fi
    return "$rc"
}

build_apps() {
    # A compiler cache mounted at /ccache (ORIELOS_CCACHE_DIR in tools/test-apps.sh and
    # tools/build-image.sh) is used for the build; without it, everything compiles from scratch.
    # mold links: links aren't cached, so they are much of a build with a warm cache.
    local launcher=()
    if [[ -d "$ccache_dir" ]]; then
        export CCACHE_DIR="$ccache_dir"
        ccache --max-size=2G >/dev/null
        ccache --zero-stats >/dev/null
        launcher=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
    fi
    step "Configuring"
    cmake -S "$src" -B "$build" -G Ninja "${launcher[@]}" \
        -DCMAKE_LINKER_TYPE=MOLD -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_TESTING=ON
    step "Building"
    cmake --build "$build"
    if [[ -d "$ccache_dir" ]]; then ccache --show-stats; fi
    # The tests run in parallel, one per core; tests that share a file take a RESOURCE_LOCK.
    step "Running the tests"
    QT_QPA_PLATFORM=offscreen ctest --test-dir "$build" --output-on-failure --verbose --parallel "$(nproc)"
    lint_qml
    step "Installing to /out"
    DESTDIR=/out cmake --install "$build"
    # Only /out goes into the image. Leaving the build tree in the stage made committing it slow,
    # as Podman compares every file.
    rm -rf "$build"
}

case "${1:-}" in
    deps) deps ;;
    build) build_apps ;;
    lint-module) lint_module "$2" ;;
    *)
        printf 'usage: %s deps|build\n' "${0##*/}" >&2
        exit 2
        ;;
esac

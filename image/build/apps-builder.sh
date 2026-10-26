#!/usr/bin/env bash
# Builds OrielOS's own apps in the app-builder stage of the Containerfile.
#   apps-builder.sh deps    installs the build dependencies
#   apps-builder.sh build   configures, builds, runs the tests and qmllint, and installs to /out
# The build fails if any test fails or qmllint reports a warning.
set -Eeuo pipefail
if [[ -n "${ORIELOS_BUILD_TRACE:-}" ]]; then set -x; fi

src=/src
build=/src/build

step() { printf '==> %s\n' "$1"; }

deps() {
    dnf -y install --setopt=install_weak_deps=False \
        cmake ninja-build gcc-c++ extra-cmake-modules \
        qt6-qtbase-devel qt6-qtdeclarative-devel \
        kf6-kirigami-devel kf6-ki18n-devel kf6-kcoreaddons-devel \
        libplasma-devel kf6-kconfig-devel \
        kf6-kstatusnotifieritem-devel kf6-knotifications-devel kf6-kdbusaddons-devel \
        kf6-kcmutils-devel kf6-kwidgetsaddons-devel kf6-kwindowsystem-devel \
        kf6-kio-devel kf6-kjobwidgets-devel kf6-kservice-devel
    # The QML modules the Start menu imports, so qmllint can check it: Plasma's private menu
    # models come with plasma-workspace.
    dnf -y install --setopt=install_weak_deps=False \
        plasma-workspace kf6-kitemmodels kf6-kcmutils
    dnf clean all
}

# Runs qmllint over every QML module with the import paths and resources CMake generated for
# it. The generated all_qmllint target cannot fail on warnings, so this calls qmllint itself.
lint_qml() {
    local qmllint=/usr/lib64/qt6/bin/qmllint rsp modules=0
    while IFS= read -r -d '' rsp; do
        step "Running qmllint on ${rsp##*/}"
        "$qmllint" --max-warnings 0 "@$rsp"
        modules=$((modules + 1))
    done < <(find "$build" -path '*/.rcc/qmllint/*.rsp' ! -name '*_json.rsp' ! -name '*_module.rsp' -print0 | sort -z)
    if [[ "$modules" -eq 0 ]]; then
        printf 'error: no QML modules found to lint\n' >&2
        exit 1
    fi
    printf 'qmllint: no warnings in %d QML module(s)\n' "$modules"
}

build_apps() {
    step "Configuring"
    cmake -S "$src" -B "$build" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=ON
    step "Building"
    cmake --build "$build"
    step "Running the tests"
    QT_QPA_PLATFORM=offscreen ctest --test-dir "$build" --output-on-failure --verbose
    lint_qml
    step "Installing to /out"
    DESTDIR=/out cmake --install "$build"
}

case "${1:-}" in
    deps) deps ;;
    build) build_apps ;;
    *)
        printf 'usage: %s deps|build\n' "${0##*/}" >&2
        exit 2
        ;;
esac

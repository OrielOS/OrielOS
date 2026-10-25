# tools

Developer scripts. They are written in Bash, must pass shellcheck, and are meant to run inside Linux or WSL2.

Contains:

- `check-env.sh`: checks that this machine can build and boot-test the image.
- `build-image.sh`: builds the image locally from the pinned inputs and exports an archive for test VMs.
- `update-pins.sh`: shows, and optionally applies, newer digests for the pinned inputs in `image/pins.env`.
- `test-apps.sh`: builds and tests OrielOS's own apps the same way the image build does, without building the whole image. It builds only the `app-builder` stage of `image/Containerfile`, which compiles the apps, runs their tests and `qmllint`, and exits 1 if any of them fail. It works with rootless Podman, needs no `sudo`, and CI runs it on every pull request.
- `lint.sh`: runs every linter (shellcheck, shfmt, hadolint, actionlint, clang-format, gitleaks) and exits 1 on any finding. `qmllint` runs in `test-apps.sh` instead, where the Qt and KDE Frameworks imports resolve. Run `tools/install-lint-tools.sh` once first; it installs the pinned tools into `.cache/tools`. The pinned versions and checksums are in `lint-tools.env` and `lint-requirements.txt`. CI runs the same two scripts.

Will contain:

- Launching test VMs.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).

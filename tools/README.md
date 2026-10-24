# tools

Developer scripts. They are written in Bash, must pass shellcheck, and are meant to run inside Linux or WSL2.

Contains:

- `check-env.sh`: checks that this machine can build and boot-test the image.
- `lint.sh`: runs every linter (shellcheck, shfmt, hadolint, actionlint, clang-format, qmllint, gitleaks) and exits 1 on any finding. Run `tools/install-lint-tools.sh` once first; it installs the pinned tools into `.cache/tools`. The pinned versions and checksums are in `lint-tools.env` and `lint-requirements.txt`. CI runs the same two scripts.

Will contain:

- Building the image locally.
- Launching test VMs.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).

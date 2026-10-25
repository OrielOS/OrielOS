# Contributing to OrielOS

Thank you for helping with OrielOS. This page explains how to report problems, suggest ideas and send changes. Please also read the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and proposing features

- **Questions** belong in the [Q&A](https://github.com/ncjsvr/OrielOS/discussions/categories/q-a) category of GitHub Discussions, and **open-ended ideas** in the [General](https://github.com/ncjsvr/OrielOS/discussions/categories/general) category. Issues are kept for actionable reports.
- **Bugs, game compatibility, hardware support and feature requests** use the issue forms. Choose the form that fits when you open a new issue, and fill in every required field. Search existing issues first.
- **Security problems** must not be reported in public. Follow [SECURITY.md](SECURITY.md).

## Contributing code

1. Fork the repository, or create a branch if you have write access.
2. Name the branch `<type>/<slug>`, for example `feat/start-menu` or `fix/updater-restart`.
3. Make one logical change per pull request. Small, focused pull requests are reviewed faster.
4. Write commit messages and the pull request title in [Conventional Commits](https://www.conventionalcommits.org/) form, for example `feat: add the Win+V clipboard history`. Pull requests are squash-merged, so the title becomes the commit message on `main`.
5. Sign off every commit with `git commit -s`. This adds a `Signed-off-by:` line with your name and email, and certifies the [Developer Certificate of Origin](https://developercertificate.org/). CI checks it. There is no contributor licence agreement.
6. Open the pull request against `main` and complete the template. The maintainer reviews and merges every pull request.

### Building, linting and testing

All tools run inside Linux or WSL2.

- `tools/check-env.sh` checks that the machine can build and boot-test the image.
- `tools/install-lint-tools.sh` installs the pinned linters once; `tools/lint.sh` then runs all of them.
- `tools/test-apps.sh` builds and tests the OrielOS apps.
- `tools/build-image.sh` builds the image locally.
- `tests/boot-test.sh` boot-tests the image under QEMU/KVM.

CI runs the linters and checks on every pull request, and it must pass before a change is merged.

### Code style

- `.editorconfig` and `.clang-format` define the formatting; use an editor that honours them.
- Shell scripts pass `shellcheck` and `shfmt -i 4 -ci`.
- QML passes `qmllint`.
- Every user-visible string goes through KI18n so that it can be translated.

## Artwork

Artwork must be original, or under a compatible licence with the author and licence recorded alongside it. Nothing owned by Microsoft may be used: no logos, fonts, icons, sounds or wallpapers.

## Licensing of contributions

Contributions are licensed under the same terms as the project (inbound equals outbound). Code and configuration are `GPL-3.0-or-later`. Documentation in `docs/` and artwork in `artwork/` are `CC BY-SA 4.0`. By signing off a commit you confirm you have the right to contribute it under those terms.
